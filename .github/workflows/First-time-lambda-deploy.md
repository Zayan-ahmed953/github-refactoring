# First-Time Lambda Deployment Plan

This document defines how new Lambda functions will be deployed for the first time across isolated AWS environments:

- dev
- uat
- prod

Each environment has:
- Its own AWS account
- Its own Terraform backend (S3 state bucket)
- Its own credentials (via GitHub Secrets / OIDC)

This plan ensures:
- Proper packaging
- State initialization
- Secure deployment
- Environment promotion strategy
- No manual console changes

---

# Deployment Strategy Overview

We deploy new Lambda functions using Terraform via the existing environment-based pipeline model and **branch-based promotion** between `dev`, `uat`, and `prod`.

High-level flow:

1. Developer adds Lambda code under `lambda/functions/` on the **dev branch**
2. Terraform module (`modules/lambda`) is updated or reused
3. `environments/dev/main.tf` references the Lambda module
4. Terraform is applied to the **dev AWS account** to test and validate the new Lambda
5. After dev testing, `environments/uat/main.tf` is updated on the **uat branch** to reference the same Lambda module/function
6. A PR is opened from **dev → uat**; KICS + validation run; on merge, the workflow applies Terraform for `environments/uat`
7. After UAT validation, `environments/prod/main.tf` is updated on the **prod branch**
8. A PR is opened from **uat → prod`**, with manual approval required before the workflow applies Terraform for `environments/prod`

---

# Architecture Alignment

Repository structure relevant to Lambda:

```
lambda/
  ├── functions/
  │   └── <function-name>/
  │        ├── app.py
  │        └── requirements.txt
  └── layers/
      └── <layer-name>/

modules/
  └── lambda/
      ├── main.tf
      ├── variables.tf
      └── output.tf

environments/
  ├── dev/
  ├── uat/
  └── prod/
```

Each environment calls:

```
module "my_lambda" {
  source = "../../modules/lambda"

  function_name = "my-lambda"
  source_path   = "../../lambda/functions/my-lambda"
  environment   = var.environment
}
```

---

# First-Time Deployment Flowchart (from dev to uat)

```text
                ┌─────────────────────────────┐
                │ Developer Adds New Lambda   │
                │ Code Under lambda/functions │   # in the dev branch 
                └──────────────┬──────────────┘
                               │
                               ▼
                ┌─────────────────────────────┐
                │ Update Environment main.tf  │
                │ Add Lambda Module Reference │   # for the dev environment under environment/dev
                └──────────────┬──────────────┘
                               │
                               ▼
                ┌─────────────────────────────┐
                │ Deploy to dev AWS           |
                |  to perform testing         |   # Once we have thoroughly tested our code in dev we will only then proceed to uat deployment
                |  and validation             │ 
                └──────────────┬──────────────┘
                               │
                               ▼  
                ┌─────────────────────────────┐
                │ Update the main.tf for      |
                |  uat folder e.g under       |  # so that we can call the newly added lambda function in uat terraform
                |  environments/uat           │ 
                └──────────────┬──────────────┘
                               │
                               ▼   
                ┌─────────────────────────────┐
                │ Create Pull Request         │  # With target branch as uat and base as dev
                └──────────────┬──────────────┘
                               │
                               ▼
                ┌─────────────────────────────┐
                │ PR Validation Pipeline      │
                │ - Terraform Validate        │
                │ - KICS Scan                 │
                └──────────────┬──────────────┘
                               │
                               ▼
                ┌─────────────────────────────┐
                │ Merge to UAT branch         │
                └──────────────┬──────────────┘
                               │
                               ▼
                ┌─────────────────────────────┐
                │ Workflow will be triggerd   │
                │ cd environments/uat         │  # This will deploy to UAT env
                │ terraform apply             │
                └──────────────┬──────────────┘
                               │
                               ▼
                ┌─────────────────────────────┐
                │ Update the prod environment | # Once testing has been done in uat env we will proceed to promote prod
                |        terraform            │
                └──────────────┬──────────────┘
                               │
                               ▼
                ┌─────────────────────────────┐
<<<<<<< HEAD
                │ Raise PR from uat branch    |
                |        to main branch)      │ 
                └──────────────|──────────────┘
                               │
                               ▼
                ┌─────────────────────────────┐
                │ Workflow will require manual| 
                |  approval before deploying  |
                |            to prod          │ 
=======
                │ Promote to PROD (Approval)  │
>>>>>>> 7ef2a46 (updated with the code itself)
                └──────────────|──────────────┘
                               │
                               ▼
                ┌─────────────────────────────┐
                │  Workflow will be triggerd  │
                │  cd environments/prod       │
                │  terraform apply            |
                └─────────────────────────────┘
```

---

# Detailed Execution Plan

## Step 1 — Add Lambda Code

Create new directory:

```
lambda/functions/my-new-function/
```

Example structure:

```
lambda/functions/my-new-function/
  ├── app.py
  ├── requirements.txt
```

---

## Step 2 — Packaging Strategy

#### Option B — CI Packaging Step

Pipeline:
- Install dependencies
- Zip code
- Upload to S3 artifact bucket
- Terraform references S3 object

Recommended only if:
- Code is large
- Build step required
- Native dependencies involved

For first-time deployment, Option A is simpler.

---

## Step 3 — Update Environment Configuration

### Dev environment

In:

```
environments/dev/main.tf
```

Add:

```
module "my_new_lambda" {
  source        = "../../modules/lambda"
  function_name = "my-new-lambda"
  source_path   = "../../lambda/functions/my-new-function"
  environment   = "dev"
}
```

Commit this change to the **dev branch**. Applying Terraform from `environments/dev` will create and wire the Lambda for the dev AWS account.

### UAT environment

After the Lambda is tested and validated in dev, update:

```
environments/uat/main.tf
```

to reference the same module/function (for example, `environment = "uat"` and any UAT-specific settings). Open a PR with **base branch = uat** and **head/source branch = dev** so that, on merge, the UAT workflow applies Terraform from `environments/uat`.

### Prod environment

Once UAT validation is complete, update:

```
environments/prod/main.tf
```

to reference the same module/function for production (for example, `environment = "prod"` and prod-specific settings). Open a PR with **base branch = prod** and **head/source branch = uat`; merging this PR (with required approval) triggers the prod workflow and applies Terraform from `environments/prod`.

---

## Step 4 — First Terraform Apply (DEV)

Run:

```
cd environments/dev
terraform init
terraform plan -var-file=dev.tfvars
terraform apply -var-file=dev.tfvars
```

What happens:

- Terraform packages Lambda
- Creates IAM role
- Creates Lambda function
- Attaches policies
- Configures environment variables
- Stores state in dev S3 backend
- Uses dev AWS account credentials

No manual AWS console work required.

---

# Environment Promotion Strategy

## DEV → UAT → PROD

Deployment order (branch + environment):

1. **DEV** – changes merged into the dev branch; Terraform runs in `environments/dev` against the dev AWS account
2. **UAT** – PR from dev → uat; on merge, Terraform runs in `environments/uat` against the uat AWS account
3. **PROD** – PR from uat → prod; on merge (with approval), Terraform runs in `environments/prod` against the prod AWS account

Promotion means:

- Same Terraform module
- Same Lambda source
- Different AWS account
- Different backend
- Different tfvars

Isolation guarantees:
- No cross-account contamination
- Separate IAM roles
- Separate logs
- Separate monitoring

---

# State Considerations (First-Time Deploy)

When Lambda does not exist:

Terraform behavior:

- Detects resource does not exist
- Creates it
- Adds to state
- No import required

If Lambda already exists manually:

- Must run:
  terraform import aws_lambda_function.my_lambda <function_name>
- Then apply

Avoid manual resource creation outside Terraform.

---


# Secret Injection for Lambda

Two approaches:

### GitHub Secrets → TF_VAR_*

Pipeline sets:

```
TF_VAR_db_password = ${{ secrets.TF_VAR_DB_PASSWORD_DEV }}
```

Terraform injects as environment variable in Lambda.

---

### AWS Secrets Manager (Recommended)

Inside module:

```
data "aws_secretsmanager_secret_version" "lambda_secrets" {
  secret_id = "lambda/${var.environment}/secrets"
}

locals {
  secrets = jsondecode(data.aws_secretsmanager_secret_version.lambda_secrets.secret_string)
}
```

Then:

```
environment {
  variables = {
    DB_PASSWORD = local.secrets["db_password"]
  }
}
```

Better security posture.
No secrets in pipeline logs.

---

# CI/CD Deployment Model

For first-time deployment (branch-based):

```
Feature PR → Merge into dev branch → Deploy DEV
                      ↓
             PR dev → uat → Deploy UAT
                      ↓
      PR uat → prod (Approval Gate) → Deploy PROD
```

No direct PROD deployment without:

- PR validation
- Security scan
- Manual approval

---

# Complete First-Time Deployment Flow

```text
Developer Writes Lambda
        ↓
PR Created
        ↓
KICS Scan + Terraform Validate
        ↓
Merge Approved
        ↓
Deploy DEV (terraform apply)
        ↓
Test + Validate
        ↓
Deploy UAT
        ↓
Business Validation
        ↓
Deploy PROD (Manual Approval Required)
        ↓
Live
```

---


# Summary

First-time Lambda deployment is:

- Fully Terraform-managed
- Environment isolated
- Security validated
- Pipeline controlled
- Promotion-based
- Zero manual console dependency

This approach ensures scalable, repeatable, and compliant serverless deployment across dev, uat, and prod accounts.
