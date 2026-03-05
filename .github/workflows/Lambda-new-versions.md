# Lambda Code Update Deployment Plan

## Overview

This document describes how new versions of already deployed AWS Lambda functions are released using Terraform and CI/CD.

The process ensures:

- Immutable Lambda versions  
- Safe environment promotion (dev → uat → prod)  
- Zero downtime  
- Full Terraform control (no manual console updates)

---

## 1. Architecture Principles

- Each environment (dev, uat, prod) runs in a separate AWS account  
- Each environment has its own Terraform state backend  
- Each env has its own git branch e.g dev, uat, prod
- Lambda functions are deployed using Terraform  
- Lambda versions are immutable  
- An alias per environment points to the active version  
- Code changes trigger new Lambda versions automatically  

---

## 2. Required Lambda Terraform Configuration

### 2.1 Publish Versions

```hcl
resource "aws_lambda_function" "this" {
  function_name = var.function_name
  filename      = var.package_path
  handler       = var.handler
  runtime       = var.runtime
  role          = var.role_arn

  source_code_hash = filebase64sha256(var.package_path)

  publish = true
}
```

**Why**

- `publish = true` creates a new immutable version on every change  
- `source_code_hash` ensures Terraform detects code changes  

### 2.2 Use Environment Alias

```hcl
resource "aws_lambda_alias" "current" {
  name             = var.environment
  function_name    = aws_lambda_function.this.function_name
  function_version = aws_lambda_function.this.version
}
```

**Why**

- API Gateway / triggers point to alias  
- Enables safe rollback  
- Enables traffic shifting  
- Avoids using `$LATEST`  

---



<<<<<<< HEAD
## 3. How Terraform Detects Code Changes
=======
Update files under:

```text
lambda/functions/<function-name>/
```

**Example**

```text
lambda/functions/my-function/app.py
```

Commit changes:

```bash
git commit -m "feat: improve validation logic"
```

Open a Pull Request.

### Step 2 — Pull Request Pipeline

For target environment (usually `dev`), the pipeline runs:

- Terraform format check  
- KICS security scan  
- `terraform init`  
- `terraform plan -var-file=dev.tfvars`  

**Expected plan output**

- Lambda function shows `~` update in-place  
- New version will be created  
- Alias will be updated  
- No infrastructure destruction should occur  

### Step 3 — Merge to dev branch (Deploy to Dev)

On merge into the **dev branch**, the Terraform pipeline is run for the `dev` environment. Conceptually, it executes:

```bash
cd environments/dev
terraform apply -var-file=dev.tfvars
```

**Result**

- New Lambda version published  
- Alias updated to new version  
- Zero downtime  
- Previous version still exists  

### Step 4 — Promote to UAT (dev → uat)

After validation in `dev`, a PR is opened from the **dev branch to the uat branch**. When the PR is approved and merged, the Terraform pipeline is run for the `uat` environment. Conceptually, it applies:

```bash
cd environments/uat
terraform apply -var-file=uat.tfvars
```

**Effect**

- Same code deployed to UAT account  
- New version created in UAT  
- Alias updated  

### Step 5 — Deploy to Production (uat → prod)

After UAT approval, a PR is opened from the **uat branch to the prod branch**. When the PR is approved and merged, the Terraform pipeline is run for the `prod` environment. Conceptually, it applies:

```bash
cd environments/prod
terraform apply -var-file=prod.tfvars
```

**Effect**

- New Lambda version published in prod account  
- Alias updated  
- Zero downtime  

---

## 4. How Terraform Detects Code Changes
>>>>>>> 7ef2a46 (updated with the code itself)

This line is critical:

```hcl
source_code_hash = filebase64sha256(var.package_path)
```

**When code changes**

- File hash changes  
- Terraform detects drift  
- New version created  
- Alias repointed automatically  

**If no code changes**

- No update occurs  

---

## 4. Rollback Strategy

### Option 1 — Alias Rollback (Fastest)

Change alias to previous version:

```hcl
function_version = "12"
```

Run apply:

```bash
terraform apply
```

Result: instant rollback.

### Option 2 — Git Revert

```bash
git revert <commit-sha>
```

Merge the revert PR → pipeline redeploys the previous working version.

---

## 5. Zero-Downtime Guarantee

Because:

- Versions are immutable  
- Alias switches pointer  
- No function replacement occurs  

There is no downtime during deployment.

---

## 6. CI/CD Flow Summary

1. Pull Request  
2. Terraform `fmt` check  
3. KICS scan  
4. Terraform `plan`  
5. Merge  
6. Terraform `apply` (dev)  
7. Manual approval  
8. Deploy to UAT  
9. Manual approval  
10. Deploy to Prod  

---

## 7. What Does Not Change During Code Update

The following resources are **not** recreated:

- IAM roles  
- VPC configuration  
- Security groups  
- Event triggers  
- CloudWatch log groups  
- Terraform backend  

Only these change:

- Lambda version  
- Alias pointer  

---

## 8. First Deployment vs Update

| Scenario          | Behavior                        |
| ----------------- | ------------------------------- |
| First deployment  | Function + alias created        |
| Code update       | New version + alias updated     |
| No code change    | No update                       |
| Config change     | New version created             |

---

## 9. Best Practices

- Always use `publish = true`  
- Always use `source_code_hash`  
- Never deploy via AWS Console  
- Never use `$LATEST` in production  
- Always use alias per environment  
- Require approval before production deployment  
- Keep environments isolated per AWS account  

---

## 10. Deployment Summary

- Modify Lambda code  
- Open PR  
- CI runs plan  
- Merge  
- Apply to dev  
- Promote to UAT  
- Promote to prod  
- Alias repoints automatically  
- Zero downtime achieved  

