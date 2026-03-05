# Repository Structure

This document describes the folder structure for Terraform and Lambda in this repository, how environments and backends are set up, and how CI/CD uses it.

---

## Overview

- **Environments:** `dev`, `uat`, `prod` — each has its own **AWS account** and its own **Terraform state backend** (separate S3 bucket per environment within that account).
- **Pipelines:** Terraform is run **from inside each environment folder** (e.g. `cd environments/prod`). Plan, apply, and destroy are executed in that directory using that env’s `backend.tf`, `provider.tf`, and `<env>.tfvars`.
- **Credentials:** AWS credentials are **not** stored in the repo; they are supplied at runtime via **GitHub Secrets** and used by the pipeline (e.g. `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, or OIDC) to authenticate to the corresponding AWS account per environment.

---

## Directory Tree

```
.
├── environments/              # Per-environment Terraform root (pipeline runs here)
│   ├── dev/
│   │   ├── main.tf            # Entry point; calls central modules
│   │   ├── backend.tf         # S3 backend for dev (dev AWS account, dev state bucket)
│   │   ├── provider.tf        # AWS provider config for dev account
│   │   └── dev.tfvars         # Dev variable values
│   ├── uat/
│   │   ├── main.tf
│   │   ├── backend.tf         # S3 backend for UAT (uat AWS account, uat state bucket)
│   │   ├── provider.tf        # AWS provider config for uat account
│   │   └── uat.tfvars
│   └── prod/
│       ├── main.tf
│       ├── backend.tf         # S3 backend for prod (prod AWS account, prod state bucket)
│       ├── provider.tf        # AWS provider config for prod account
│       └── prod.tfvars
├── modules/                   # Shared Terraform modules (reused by all envs)
│   ├── vpc/
│   ├── ec2/
│   ├── lambda/
│   ├── rds/
│   ├── s3/
│   └── iam/
├── lambda/                    # Lambda source code and layers (referenced by modules/lambda)
│   ├── functions/
│   │   └── app.py             # (example; add more function dirs as needed)
│   └── layers/
├── scripts/                   # Python and YAML used with Terraform / automation
├── IMPROVEMENTS.md            # Review and improvement notes
└── STRUCTURE.md               # This file
```

---

## Top-Level Folders

### `environments/`

One directory per environment: **dev**, **uat**, **prod**. Each is the **working directory for Terraform** when the pipeline runs for that environment.

- **Different AWS account per env:** Each environment uses its own AWS account. The pipeline uses credentials (from GitHub Secrets) for that account when running Terraform for that env.
- **Different backend per env:** Each environment has its own Terraform state backend — a **different S3 bucket** in that environment’s AWS account. So:
  - `environments/dev/backend.tf`  → dev account, dev state bucket
  - `environments/uat/backend.tf`  → uat account, uat state bucket
  - `environments/prod/backend.tf` → prod account, prod state bucket

**Files in each env folder:**

| File | Purpose |
|------|--------|
| `main.tf` | Entry point; instantiates central modules (e.g. `../../modules/vpc`, `../../modules/lambda`) and wires them together. |
| `backend.tf` | Defines the Terraform backend (e.g. S3) for this env: bucket name, key, region — all for **this environment’s AWS account**. |
| `provider.tf` | Configures the AWS provider (region, etc.) for this environment’s account. |
| `<env>.tfvars` | Variable values for this env (e.g. instance sizes, tags). Used as `-var-file=dev.tfvars` (or `prod.tfvars` / `uat.tfvars`) in the pipeline. |

No shared backend or shared account across envs; each env is isolated by account and state bucket.

---

### `modules/`

Reusable Terraform modules used by all environments. Each subfolder is one module (e.g. VPC, EC2, Lambda, RDS, S3, IAM). Environments reference them with relative paths from their directory (e.g. `../../modules/vpc`).

Typical layout per module: `main.tf`, `variables.tf`, `output.tf` (and optionally `outputs.tf`). Add or remove module subfolders as needed.

---

### `lambda/`

Lambda **function code** and **layers** in one place. The Terraform in `modules/lambda` (or in env `main.tf`) points at paths under here (e.g. `lambda/functions/<name>`, `lambda/layers/<name>`).

- **`lambda/functions/`** — One directory per function (e.g. `app.py` or a subfolder per function). Packaged and deployed by Terraform.
- **`lambda/layers/`** — Shared layers (e.g. dependencies). Referenced by the Lambda module or env config.

---

### `scripts/`

Central place for **Python** (`.py`) and **YAML** (`.yaml`) used with Terraform or automation (e.g. codegen, config generation, pipeline helpers). Not applied by Terraform directly unless invoked by your workflow.

---

## AWS Accounts and Backends (per environment)

| Environment | AWS account | State backend |
|-------------|-------------|---------------|
| **dev** | Dev AWS account | S3 bucket in dev account (e.g. `myorg-terraform-state-dev-yoyo`) |
| **uat** | UAT AWS account | S3 bucket in uat account (e.g. `myorg-terraform-state-uat`) |
| **prod** | Prod AWS account | S3 bucket in prod account (e.g. `myorg-terraform-state-prod`) |

- Each env’s `backend.tf` configures the S3 backend for **that env’s bucket in that env’s account**.
- Credentials for each account are **not** in the repo; they are provided at pipeline runtime (see below).

---

## Credentials: GitHub Secrets

AWS credentials are **not** committed to the repository. The pipeline (e.g. GitHub Actions) uses **GitHub Secrets** to authenticate to AWS.

- **Per-environment secrets:** Use separate secrets per env (e.g. `AWS_ACCESS_KEY_ID_DEV`, `AWS_SECRET_ACCESS_KEY_DEV` for dev; similarly for UAT and prod), or one set of secrets and assume different roles per env.
- **Usage in pipeline:** Before running Terraform for an environment, the workflow sets the appropriate AWS credentials (e.g. from `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` or OIDC) so that `terraform init` and `terraform apply` target the correct account and state bucket for that env.

Example pattern (conceptual):

- For **dev:** use dev secrets → `cd environments/dev` → `terraform init` (uses `backend.tf` in dev) → `terraform plan -var-file=dev.tfvars` → `apply`.
- For **prod:** use prod secrets → `cd environments/prod` → same steps with `prod.tfvars` and prod `backend.tf`.

Do **not** put AWS keys or long-lived credentials in `.tfvars` or in the repo; keep them only in GitHub Secrets (or equivalent secret store) and inject them in the pipeline.

---

## Sensitive Terraform variables

Sensitive Terraform variables (passwords, API keys, tokens, connection strings) are **not** stored in the repository. You can keep them in **GitHub Secrets** or in **AWS Secrets Manager** (per-environment account). In both cases the pipeline injects them at runtime before running Terraform.

- **Committed:** Only **non-sensitive** variables go in `environments/<env>/<env>.tfvars` (e.g. instance types, tag names, env names, counts, feature flags, resource names). These files are safe to review in PRs.
- **Not in repo:** Sensitive variables live either in GitHub Secrets or in AWS Secrets Manager (see below). They are never committed.

### Option 1: GitHub Secrets

- Store each sensitive value as a repository or environment secret (e.g. `TF_VAR_DB_PASSWORD_PROD`). Use per-environment names so the workflow passes the right one for each env.
- **At runtime:** The pipeline sets `TF_VAR_*` from secrets (e.g. `TF_VAR_db_password: ${{ secrets.TF_VAR_DB_PASSWORD_PROD }}`) or writes a temporary file from secrets and passes it as `-var-file=secrets.auto.tfvars`. Terraform then sees both the committed `.tfvars` and the secret values.

### Option 2: AWS Secrets Manager

- Store sensitive Terraform variables in **AWS Secrets Manager in each environment’s AWS account** (e.g. one secret per env such as `terraform/prod/vars`, or one secret per variable). Secrets stay in the same account as the resources; you can use rotation, audit, and IAM policies there.

**2a. Pipeline fetches and injects (as above):** The pipeline calls Secrets Manager, then sets `TF_VAR_*` or writes a temporary tfvars file before running Terraform.

**2b. Data source in Terraform (recommended when using Secrets Manager):** You can avoid pipeline injection and let Terraform fetch secrets at plan/apply time. Use the `aws_secretsmanager_secret_version` data source to read the secret; decode it (e.g. from JSON) into **locals**; and have your resources reference those locals. The pipeline only needs to supply AWS credentials (which it already does); Terraform then pulls the secret values and uses them wherever they are referenced.

Example pattern in `main.tf` (or a module):

```hcl
data "aws_secretsmanager_secret_version" "terraform_vars" {
  secret_id = "terraform/${var.environment}/vars"
}

locals {
  secret_vars = jsondecode(data.aws_secretsmanager_secret_version.terraform_vars.secret_string)
}

# Resources reference the values, e.g.:
# password = local.secret_vars["db_password"]
# api_key  = local.secret_vars["api_key"]
```

Store the secret in Secrets Manager as a JSON object (e.g. `{"db_password":"...","api_key":"..."}`). Mark any output that might expose these as `sensitive = true`. The IAM principal used by Terraform (same as the pipeline’s AWS creds) needs `secretsmanager:GetSecretValue` on the secret.

- **IAM:** The IAM principal used by the pipeline/Terraform in each account needs `secretsmanager:GetSecretValue` on the relevant secret(s).
- **Convention:** Use a consistent secret name or path per env (e.g. `terraform/dev/vars`, `terraform/prod/vars`) so the data source can use `var.environment` or a similar value.

**Choosing:** Use **GitHub Secrets** when you want a single place (GitHub) for both AWS creds and Terraform secrets and minimal pipeline logic. Use **AWS Secrets Manager** when you want secrets to live in the same AWS account as the stack, need rotation/audit in AWS, or already manage other app secrets there. With Secrets Manager, prefer the **data source** approach so Terraform fetches values directly and resources reference them via locals—no pipeline secret-handling step.

---

## How to Run Terraform

From the **repository root**, for a given environment:

```bash
cd environments/<env>          # <env> = dev | uat | prod
terraform init                 # Uses this folder’s backend.tf and current AWS creds
terraform plan -var-file=<env>.tfvars
terraform apply -var-file=<env>.tfvars   # or destroy
```

Ensure the AWS credentials in the environment (e.g. from GitHub Secrets) correspond to the **same** environment (dev account for dev, prod account for prod). Each env’s `backend.tf` and `provider.tf` then target the correct account and state bucket.

---

## Summary

| Topic | Detail |
|-------|--------|
| **Environments** | `dev`, `uat`, `prod` under `environments/`. |
| **AWS** | One AWS account per environment; one S3 state bucket per env in that account. |
| **Backend** | Defined in each env’s `backend.tf`; different bucket (and account) per env. |
| **Credentials** | From GitHub Secrets; never stored in the repo. |
| **Sensitive Terraform vars** | GitHub Secrets (pipeline injects) or AWS Secrets Manager; with Secrets Manager you can use a Terraform data source to fetch values into locals for resources to reference. |
| **Pipeline** | Runs Terraform from `environments/<env>` with that env’s backend, provider, and tfvars. |
| **Modules** | Shared under `modules/`; env `main.tf` calls them with relative paths. |
| **Lambda** | Code and layers under `lambda/functions/` and `lambda/layers/`. |
