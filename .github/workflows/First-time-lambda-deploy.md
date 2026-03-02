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

We deploy new Lambda functions using Terraform via the existing environment-based pipeline model.

High-level flow:

1. Developer adds Lambda code under `lambda/functions/`
2. Terraform module (`modules/lambda`) is updated or reused
3. Environment `main.tf` references the Lambda module
4. PR created → KICS + Validation
5. Merge to main
6. Deploy to `dev`
7. Promote to `uat`
8. Promote to `prod` (manual approval required)

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

# First-Time Deployment Flowchart

```text
                ┌─────────────────────────────┐
                │ Developer Adds New Lambda   │
                │ Code Under lambda/functions │
                └──────────────┬──────────────┘
                               │
                               ▼
                ┌─────────────────────────────┐
                │ Update Environment main.tf  │
                │ Add Lambda Module Reference │
                └──────────────┬──────────────┘
                               │
                               ▼
                ┌─────────────────────────────┐
                │ Create Pull Request         │
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
                │ Merge to Main               │
                └──────────────┬──────────────┘
                               │
                               ▼
                ┌─────────────────────────────┐
                │ Deploy to DEV Account       │
                │ cd environments/dev         │
                │ terraform apply             │
                └──────────────┬──────────────┘
                               │
                               ▼
                ┌─────────────────────────────┐
                │ Promote to UAT              │
                └──────────────┬──────────────┘
                               │
                               ▼
                ┌─────────────────────────────┐
                │ Promote to PROD (Approval)  │
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

Repeat for uat and prod as needed.

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

Deployment order:

1. DEV automatic
2. UAT manual or workflow-triggered
3. PROD requires approval

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

# IAM Requirements

Pipeline IAM principal must have:

- lambda:CreateFunction
- lambda:UpdateFunctionCode
- iam:CreateRole
- iam:AttachRolePolicy
- logs:CreateLogGroup
- s3:GetObject (if using artifact bucket)

And:

- secretsmanager:GetSecretValue (if using Secrets Manager)

Permissions must exist in each environment’s AWS account.

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

For first-time deployment:

```
PR → Merge → Deploy DEV
       ↓
Manual Trigger → Deploy UAT
       ↓
Approval Gate → Deploy PROD
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

# Risk Controls

✔ Separate AWS accounts per environment  
✔ Separate state backend per environment  
✔ No shared credentials  
✔ No manual AWS console resources  
✔ Terraform-only lifecycle  
✔ Security scanning before deployment  
✔ Secrets externalized  

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