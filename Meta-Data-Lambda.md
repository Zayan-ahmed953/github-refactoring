# Lambda Config Exporter - Code and Deployment Guide

This document includes:
- The current Lambda source code
- Required/optional environment variables
- Required IAM permissions
- Deployment steps (AWS CLI)

## Lambda Source Code

```python
import base64
import json
import os
from typing import Any, Dict, List, Set
from urllib import error, request

import boto3
from botocore.exceptions import ClientError


lambda_client = boto3.client("lambda")
iam_client = boto3.client("iam")
apigateway_client = boto3.client("apigateway")
apigatewayv2_client = boto3.client("apigatewayv2")


def _or_default(value: Any, default: str = "No value exists") -> Any:
    """
    Return the provided value if it is not "empty", otherwise the default string.
    """
    if value in (None, "", [], {}):
        return default
    return value


def _github_api_request(
    method: str, url: str, token: str, payload: Dict[str, Any] | None = None
) -> Dict[str, Any]:
    """
    Execute a GitHub REST API request and parse JSON response.
    """
    body = None
    if payload is not None:
        body = json.dumps(payload).encode("utf-8")

    req = request.Request(
        url=url,
        data=body,
        method=method,
        headers={
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {token}",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "lambda-config-exporter",
            "Content-Type": "application/json",
        },
    )

    with request.urlopen(req, timeout=20) as response:
        raw = response.read().decode("utf-8")
        if not raw:
            return {}
        return json.loads(raw)


def _normalize_github_repo(repo_value: str) -> str:
    """
    Accept owner/repo, https URL, or git@ URL and return owner/repo.
    """
    repo = (repo_value or "").strip()
    if not repo:
        return ""

    if repo.startswith("https://github.com/"):
        repo = repo[len("https://github.com/") :]
    elif repo.startswith("http://github.com/"):
        repo = repo[len("http://github.com/") :]
    elif repo.startswith("git@github.com:"):
        repo = repo[len("git@github.com:") :]

    repo = repo.strip().strip("/")
    if repo.endswith(".git"):
        repo = repo[:-4]

    parts = repo.split("/")
    if len(parts) != 2 or not parts[0] or not parts[1]:
        return ""
    return f"{parts[0]}/{parts[1]}"


def _get_github_file_sha(repo: str, branch: str, file_path: str, token: str) -> str:
    """
    Return existing file SHA for update calls, or empty string if not present.
    """
    url = (
        f"https://api.github.com/repos/{repo}/contents/{file_path}"
        f"?ref={branch}"
    )
    try:
        existing = _github_api_request("GET", url, token)
        sha = existing.get("sha")
        return sha if isinstance(sha, str) else ""
    except error.HTTPError as http_err:
        if http_err.code == 404:
            return ""
        raise


def _get_repo_default_branch(repo: str, token: str) -> str:
    """
    Fetch repository default branch name.
    """
    url = f"https://api.github.com/repos/{repo}"
    repo_info = _github_api_request("GET", url, token)
    default_branch = repo_info.get("default_branch")
    return default_branch if isinstance(default_branch, str) else ""


def _commit_json_to_github(function_name: str, payload: Dict[str, Any]) -> Dict[str, Any]:
    """
    Create or update <function-name>-config.json in a GitHub repo/path from env vars.
    """
    repo_raw = os.environ.get("GITHUB_REPO", "").strip()
    repo = _normalize_github_repo(repo_raw)
    token = os.environ.get("GITHUB_TOKEN", "").strip()
    base_path = os.environ.get("GITHUB_TARGET_PATH", "").strip().strip("/")
    branch = os.environ.get("GITHUB_BRANCH", "main").strip() or "main"
    committer_name = os.environ.get("GITHUB_COMMITTER_NAME", "").strip()
    committer_email = os.environ.get("GITHUB_COMMITTER_EMAIL", "").strip()

    missing = []
    if not repo_raw:
        missing.append("GITHUB_REPO")
    if not token:
        missing.append("GITHUB_TOKEN")

    if missing:
        return {
            "Status": "Skipped",
            "Reason": f"Missing env vars: {', '.join(missing)}",
        }

    if not repo:
        return {
            "Status": "Skipped",
            "Reason": "GITHUB_REPO must be owner/repo or a valid github.com repo URL",
            "Repository": repo_raw,
        }

    file_name = f"{function_name}-config.json"
    file_path = f"{base_path}/{file_name}" if base_path else file_name
    encoded_content = base64.b64encode(
        json.dumps(payload, indent=2, sort_keys=True).encode("utf-8")
    ).decode("utf-8")

    put_payload_base: Dict[str, Any] = {
        "message": f"Update Lambda config snapshot for {function_name}",
        "content": encoded_content,
    }
    if committer_name and committer_email:
        put_payload_base["committer"] = {
            "name": committer_name,
            "email": committer_email,
        }

    def _put_file_to_branch(target_branch: str) -> Dict[str, Any]:
        put_payload = dict(put_payload_base)
        put_payload["branch"] = target_branch
        sha = _get_github_file_sha(repo, target_branch, file_path, token)
        if sha:
            put_payload["sha"] = sha

        url = f"https://api.github.com/repos/{repo}/contents/{file_path}"
        result = _github_api_request("PUT", url, token, put_payload)
        commit = result.get("commit", {}) if isinstance(result, dict) else {}
        return {
            "Status": "Success",
            "Repository": repo,
            "Branch": target_branch,
            "Path": file_path,
            "CommitSha": commit.get("sha", "Unknown"),
        }

    try:
        return _put_file_to_branch(branch)
    except error.HTTPError as http_err:
        try:
            body = http_err.read().decode("utf-8")
        except Exception:
            body = str(http_err)

        # If configured branch doesn't exist, retry on repo default branch.
        branch_not_found = http_err.code == 404 and f"Branch {branch} not found" in body
        if branch_not_found:
            try:
                default_branch = _get_repo_default_branch(repo, token)
            except Exception:
                default_branch = ""

            if default_branch and default_branch != branch:
                try:
                    retry_result = _put_file_to_branch(default_branch)
                    retry_result["RequestedBranch"] = branch
                    retry_result["FallbackBranchUsed"] = True
                    return retry_result
                except error.HTTPError as retry_err:
                    try:
                        retry_body = retry_err.read().decode("utf-8")
                    except Exception:
                        retry_body = str(retry_err)
                    return {
                        "Status": "Failed",
                        "Repository": repo,
                        "Branch": default_branch,
                        "RequestedBranch": branch,
                        "Path": file_path,
                        "Error": retry_body,
                    }
                except Exception as retry_exc:
                    return {
                        "Status": "Failed",
                        "Repository": repo,
                        "Branch": default_branch,
                        "RequestedBranch": branch,
                        "Path": file_path,
                        "Error": str(retry_exc),
                    }

        return {
            "Status": "Failed",
            "Repository": repo,
            "Branch": branch,
            "Path": file_path,
            "Error": body,
        }
    except Exception as exc:
        return {
            "Status": "Failed",
            "Repository": repo,
            "Branch": branch,
            "Path": file_path,
            "Error": str(exc),
        }


def _extract_api_ids_from_lambda_policy(policy_str: str) -> Set[str]:
    """
    Parse Lambda resource policy JSON and extract execute-api API IDs.
    """
    api_ids: Set[str] = set()
    try:
        policy = json.loads(policy_str)
    except (TypeError, json.JSONDecodeError):
        return api_ids

    statements = policy.get("Statement", [])
    if isinstance(statements, dict):
        statements = [statements]

    for stmt in statements:
        if not isinstance(stmt, dict):
            continue
        condition = stmt.get("Condition", {})
        if not isinstance(condition, dict):
            continue

        # SourceArn may be under ArnLike or ArnEquals depending on policy shape.
        candidate_blocks = []
        for key in ("ArnLike", "ArnEquals"):
            block = condition.get(key, {})
            if isinstance(block, dict):
                candidate_blocks.append(block)

        for block in candidate_blocks:
            source_arn = block.get("AWS:SourceArn")
            if not isinstance(source_arn, str):
                continue
            # execute-api ARN format:
            # arn:aws:execute-api:{region}:{account}:{api-id}/{stage}/{method}/{resource}
            arn_parts = source_arn.split(":")
            if len(arn_parts) < 6 or arn_parts[2] != "execute-api":
                continue

            api_path = arn_parts[5]
            api_id = api_path.split("/")[0]
            if api_id and api_id != "*":
                api_ids.add(api_id)

    return api_ids


def _integration_points_to_lambda(
    integration_uri: str, function_arn: str, function_name: str
) -> bool:
    """
    Check whether an API Gateway integration URI targets this Lambda.
    """
    if not integration_uri:
        return False

    base_function_name = function_name.split(":")[0] if function_name else ""
    base_function_arn = function_arn
    if function_arn and ":function:" in function_arn:
        arn_prefix, arn_suffix = function_arn.split(":function:", 1)
        lambda_name_part = arn_suffix.split(":")[0]
        base_function_arn = f"{arn_prefix}:function:{lambda_name_part}"

    if function_arn and function_arn in integration_uri:
        return True

    if base_function_arn and base_function_arn in integration_uri:
        return True

    # Covers URIs that include function name and optional alias/version.
    function_marker = f":function:{function_name}"
    if function_name and function_marker in integration_uri:
        return True

    base_function_marker = f":function:{base_function_name}"
    if base_function_name and base_function_marker in integration_uri:
        return True

    return False


def _collect_api_gateway_matches_by_integration_scan(
    function_arn: str, function_name: str
) -> List[Dict[str, str]]:
    """
    Discover API Gateway integrations by scanning API-side configuration.
    """
    matches: List[Dict[str, str]] = []
    seen: Set[str] = set()

    # REST APIs (v1): scan resources/methods and fetch integration for each method.
    try:
        rest_paginator = apigateway_client.get_paginator("get_rest_apis")
        for page in rest_paginator.paginate():
            for api in page.get("items", []):
                api_id = api.get("id")
                api_name = api.get("name")
                if not api_id or not api_name:
                    continue

                position = None
                while True:
                    kwargs = {"restApiId": api_id, "embed": ["methods"]}
                    if position:
                        kwargs["position"] = position

                    resources_page = apigateway_client.get_resources(**kwargs)
                    for resource in resources_page.get("items", []):
                        resource_id = resource.get("id")
                        resource_path = resource.get("path", "/")
                        methods = resource.get("resourceMethods", {}) or {}
                        if not resource_id:
                            continue

                        for http_method in methods.keys():
                            try:
                                integration = apigateway_client.get_integration(
                                    restApiId=api_id,
                                    resourceId=resource_id,
                                    httpMethod=http_method,
                                )
                            except apigateway_client.exceptions.NotFoundException:
                                continue
                            except ClientError:
                                continue

                            integration_uri = integration.get("uri", "")
                            if _integration_points_to_lambda(
                                integration_uri, function_arn, function_name
                            ):
                                unique_key = f"REST|{api_id}|{http_method}|{resource_path}"
                                if unique_key in seen:
                                    continue
                                seen.add(unique_key)
                                matches.append(
                                    {
                                        "ApiName": api_name,
                                        "ApiType": "REST",
                                        "Path": resource_path,
                                        "Method": http_method,
                                    }
                                )

                    position = resources_page.get("position")
                    if not position:
                        break
    except ClientError:
        pass

    # HTTP/WebSocket APIs (v2): find matching integrations, then map to routes.
    try:
        next_token = None
        while True:
            if next_token:
                apis_page = apigatewayv2_client.get_apis(NextToken=next_token)
            else:
                apis_page = apigatewayv2_client.get_apis()

            for api in apis_page.get("Items", []):
                api_id = api.get("ApiId")
                api_name = api.get("Name")
                if not api_id or not api_name:
                    continue

                integration_token = None
                matched_integration_ids: Set[str] = set()
                while True:
                    if integration_token:
                        integrations_page = apigatewayv2_client.get_integrations(
                            ApiId=api_id, NextToken=integration_token
                        )
                    else:
                        integrations_page = apigatewayv2_client.get_integrations(
                            ApiId=api_id
                        )

                    for integration in integrations_page.get("Items", []):
                        integration_id = integration.get("IntegrationId")
                        integration_uri = integration.get("IntegrationUri", "")
                        if _integration_points_to_lambda(
                            integration_uri, function_arn, function_name
                        ):
                            if integration_id:
                                matched_integration_ids.add(integration_id)

                    integration_token = integrations_page.get("NextToken")
                    if not integration_token:
                        break

                if not matched_integration_ids:
                    continue

                route_token = None
                while True:
                    if route_token:
                        routes_page = apigatewayv2_client.get_routes(
                            ApiId=api_id, NextToken=route_token
                        )
                    else:
                        routes_page = apigatewayv2_client.get_routes(ApiId=api_id)

                    for route in routes_page.get("Items", []):
                        route_key = route.get("RouteKey", "No route key")
                        target = route.get("Target", "")
                        if not isinstance(target, str):
                            continue

                        target_integration_id = ""
                        if "/" in target:
                            target_integration_id = target.rsplit("/", 1)[-1]

                        if target_integration_id in matched_integration_ids:
                            unique_key = f"HTTP|{api_id}|{route_key}"
                            if unique_key in seen:
                                continue
                            seen.add(unique_key)
                            matches.append(
                                {
                                    "ApiName": api_name,
                                    "ApiType": "HTTP/WebSocket",
                                    "Path": route_key,
                                    "Method": "N/A",
                                }
                            )

                    route_token = routes_page.get("NextToken")
                    if not route_token:
                        break

            next_token = apis_page.get("NextToken")
            if not next_token:
                break
    except ClientError:
        pass

    return matches


def _find_api_gateway_names_by_integration_scan(
    function_arn: str, function_name: str
) -> List[str]:
    """
    Discover API Gateway names by scanning API-side integrations.
    """
    matches = _collect_api_gateway_matches_by_integration_scan(function_arn, function_name)
    names: List[str] = []
    seen_names: Set[str] = set()
    for match in matches:
        api_name = match.get("ApiName")
        if api_name and api_name not in seen_names:
            seen_names.add(api_name)
            names.append(api_name)

    return names


def _get_attached_api_gateway_names(
    fn_name: str, function_arn: str, scanned_names: List[str]
) -> List[str]:
    """
    Find API Gateway names for APIs that can invoke this Lambda.
    """
    api_names: List[str] = []
    seen_names: Set[str] = set()

    try:
        policy_response = lambda_client.get_policy(FunctionName=fn_name)
    except lambda_client.exceptions.ResourceNotFoundException:
        return scanned_names
    except ClientError:
        return scanned_names

    policy_str = policy_response.get("Policy", "")
    api_ids = _extract_api_ids_from_lambda_policy(policy_str)
    if not api_ids:
        return scanned_names

    for api_id in api_ids:
        # Try REST API Gateway first (v1).
        try:
            rest_api = apigateway_client.get_rest_api(restApiId=api_id)
            rest_name = rest_api.get("name")
            if rest_name and rest_name not in seen_names:
                seen_names.add(rest_name)
                api_names.append(rest_name)
                continue
        except apigateway_client.exceptions.NotFoundException:
            pass
        except ClientError:
            pass

        # Then try API Gateway v2 (HTTP/WebSocket APIs).
        try:
            api_v2 = apigatewayv2_client.get_api(ApiId=api_id)
            api_v2_name = api_v2.get("Name")
            if api_v2_name and api_v2_name not in seen_names:
                seen_names.add(api_v2_name)
                api_names.append(api_v2_name)
        except apigatewayv2_client.exceptions.NotFoundException:
            pass
        except ClientError:
            pass

    if api_names:
        return api_names

    return scanned_names


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    AWS Lambda entrypoint.

    Expects an event payload like:
    {
        "function_name": "my-fn-name"
    }
    """
    fn_name = event.get("function_name")
    if not fn_name:
        return {
            "statusCode": 400,
            "body": "Missing 'function_name' in event",
        }

    try:
        config = lambda_client.get_function_configuration(FunctionName=fn_name)
    except lambda_client.exceptions.ResourceNotFoundException:
        # Target function doesn't exist at all; return "No value exists" for everything else.
        no_val = "No value exists"
        response_payload = {
            "FunctionName": fn_name,
            "FunctionArn": no_val,
            "Runtime": no_val,
            "Role": no_val,
            "Handler": no_val,
            "AllHandlers": [no_val],
            "CodeSize": no_val,
            "Description": no_val,
            "Timeout": no_val,
            "MemorySize": no_val,
            "LastModified": no_val,
            "CodeSha256": no_val,
            "Version": no_val,
            "Environment": {
                "Variables": no_val,
            },
            "TracingConfig": {
                "Mode": no_val,
            },
            "Architectures": [no_val],
            "EphemeralStorage": {
                "Size": no_val,
            },
            "AttachedIamPolicyNames": [no_val],
            "ApiGatewayNames": [no_val],
            "ApiGatewayPaths": [no_val],
        }
        response_payload["GitHubCommit"] = _commit_json_to_github(
            fn_name, response_payload
        )
        return response_payload
    except ClientError as e:
        # Some other AWS error; surface minimal info.
        return {
            "statusCode": 500,
            "body": f"Error fetching configuration for '{fn_name}': {str(e)}",
        }

    # Fetch IAM policy names attached to the Lambda's execution role
    attached_policy_names = []
    role_arn = config.get("Role")
    if role_arn:
        # Role ARN is like arn:aws:iam::123456789012:role/service-role/my-role
        role_name = role_arn.split("/")[-1]
        try:
            paginator = iam_client.get_paginator("list_attached_role_policies")
            for page in paginator.paginate(RoleName=role_name):
                for policy in page.get("AttachedPolicies", []):
                    name = policy.get("PolicyName")
                    if name:
                        attached_policy_names.append(name)
        except iam_client.exceptions.NoSuchEntityException:
            attached_policy_names = []
        except ClientError:
            attached_policy_names = []

    env_vars = config.get("Environment", {}).get("Variables")
    tracing_mode = config.get("TracingConfig", {}).get("Mode")
    architectures = config.get("Architectures") or []
    ephemeral_storage_size = config.get("EphemeralStorage", {}).get("Size")
    function_arn = config.get("FunctionArn", "")
    api_gateway_matches = _collect_api_gateway_matches_by_integration_scan(
        function_arn, fn_name
    )

    scanned_api_names: List[str] = []
    seen_scanned_names: Set[str] = set()
    api_gateway_paths: List[str] = []
    for match in api_gateway_matches:
        api_name = match.get("ApiName", "Unknown API")
        if api_name not in seen_scanned_names:
            seen_scanned_names.add(api_name)
            scanned_api_names.append(api_name)

        method = match.get("Method", "N/A")
        path = match.get("Path", "No path")
        route_value = path if method == "N/A" else f"{method} {path}"
        api_gateway_paths.append(api_name)
        api_gateway_paths.append(route_value)

    api_gateway_names = _get_attached_api_gateway_names(
        fn_name, function_arn, scanned_api_names
    )

    response_payload = {
        "FunctionName": _or_default(config.get("FunctionName")),
        "FunctionArn": _or_default(config.get("FunctionArn")),
        "Runtime": _or_default(config.get("Runtime")),
        "Role": _or_default(config.get("Role")),
        "Handler": _or_default(config.get("Handler")),
        "AllHandlers": [_or_default(config.get("Handler"))],
        "CodeSize": _or_default(config.get("CodeSize")),
        "Description": _or_default(config.get("Description")),
        "Timeout": _or_default(config.get("Timeout")),
        "MemorySize": _or_default(config.get("MemorySize")),
        "LastModified": _or_default(config.get("LastModified")),
        "CodeSha256": _or_default(config.get("CodeSha256")),
        "Version": _or_default(config.get("Version")),
        "Environment": {
            "Variables": _or_default(env_vars),
        },
        "TracingConfig": {
            "Mode": _or_default(tracing_mode),
        },
        "Architectures": architectures if architectures else ["No value exists"],
        "EphemeralStorage": {
            "Size": _or_default(ephemeral_storage_size),
        },
        "AttachedIamPolicyNames": attached_policy_names
        if attached_policy_names
        else ["No value exists"],
        "ApiGatewayNames": api_gateway_names
        if api_gateway_names
        else ["No value exists"],
        "ApiGatewayPaths": api_gateway_paths
        if api_gateway_paths
        else ["No value exists"],
    }
    response_payload["GitHubCommit"] = _commit_json_to_github(fn_name, response_payload)
    return response_payload
```

## Input Event Requirement

This Lambda expects:

```json
{
  "function_name": "target-lambda-name"
}
```

## Environment Variables

Required if you want GitHub commit/export
- `GITHUB_REPO` (e.g. `owner/repo` or GitHub repo URL)
- `GITHUB_TOKEN` (GitHub token with repo content write access)
- `GITHUB_TARGET_PATH` (optional path in repo where JSON is saved)
- `GITHUB_BRANCH` (optional, defaults to `main`)
- `GITHUB_COMMITTER_NAME` (optional; used with committer email)
- `GITHUB_COMMITTER_EMAIL` (optional; used with committer name)

## IAM Role Permissions

Your Lambda execution role needs permission to read Lambda/IAM/API Gateway metadata.

### Least-Privilege Actions
- `AWSLambda_ReadOnlyAccess`
- `IAMReadOnlyAccess`
- Either attach `AmazonAPIGatewayAdministrator` **or** use this narrower API Gateway read-only policy:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "APIGatewayReadOnlyAccess",
            "Effect": "Allow",
            "Action": [
                "apigateway:GET"
            ],
            "Resource": "*"
        }
    ]
}
```
