# Lambda Function Deployment Plan

## Overview
This document outlines the deployment process for Lambda functions from development through UAT to production.

## Deployment Workflow

### Prerequisites
- Lambda function has been tested on DEV environment using AWS Console
- Lambda function is ready to move to UAT

### Steps

1. **Lambda Testing Complete**
   - Lambda function tested and validated in DEV environment

2. **Push Lambda Code to Dev Branch**
   - Done by Developers
   - Push final lambda code to `dev` branch under `lambda_functions/<function_name>/`

3. **Update UAT Environment Configuration**
   - Done by Cloud Engineer
   - Update `environments/UAT/` folder with new terraform module calls for the new lambda functions

4. **Update Production Environment Configuration**
   - Done by Cloud Engineer
   - Update `environments/Prod/` folder with new terraform module calls for the new lambda functions

5. **Create PR: Dev → UAT**
   - Create Pull Request from `dev` branch to `UAT` branch

6. **UAT Deployment**
   - Workflow will automatically run and apply the new lambda function in UAT environment

7. **Create PR: UAT → Prod**
   - After UAT validation, create Pull Request from `UAT` branch to `Prod` branch

8. **Production Deployment**
   - Workflow will automatically run and apply the new lambda function in Production environment with a manual approval gateway before applying

## Notes
- All deployments are automated via CI/CD workflows triggered by PR merges
- Cloud Engineer is responsible for Terraform configuration updates
- Developers are responsible for Lambda function code updates

