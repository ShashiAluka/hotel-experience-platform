# ADR-006: Multi-Environment Strategy (Dev / Staging / Prod)

**Status:** Accepted  
**Date:** 2024-01-15

---

## Decision

Three fully isolated AWS environments, each with its own VPC, state bucket, and resource set. Environments are promoted sequentially: dev → staging → prod.

## Environment Comparison

| Concern              | Dev                  | Staging               | Prod                     |
|----------------------|----------------------|-----------------------|--------------------------|
| VPC CIDR             | 10.0.0.0/16          | 10.1.0.0/16           | 10.2.0.0/16              |
| AZs                  | 2                    | 2                     | 3                        |
| RDS instance         | db.t3.micro          | db.t3.small           | db.t3.medium             |
| RDS Multi-AZ         | No                   | No                    | Yes                      |
| RDS deletion guard   | Off                  | Off                   | On                       |
| ECS CPU / Memory     | 256 / 512            | 512 / 1024            | 1024 / 2048              |
| ECS desired count    | 1                    | 1                     | 2                        |
| Fargate strategy     | FARGATE_SPOT         | FARGATE_SPOT          | FARGATE                  |
| WAF                  | No                   | No                    | Yes                      |
| CloudWatch retention | 3 days               | 7 days                | 14–30 days               |
| Deploy trigger       | Auto on main merge   | Manual gate           | Manual gate + approval   |
| Image tag            | latest               | git SHA               | git SHA (pinned)         |

## State Management

Each environment has its own S3 state bucket (`hxp-terraform-state-{env}`) but shares a single DynamoDB lock table (`hxp-terraform-locks`). This prevents concurrent applies across environments.

Run `infrastructure/terraform/bootstrap.sh <account-id>` once to create all state buckets.

## Promotion Flow

```
feature branch → PR → CI (lint + test + terraform plan comment)
                   ↓
              merge to main
                   ↓
           Auto-deploy to DEV
                   ↓
        Manual gate → Deploy to STAGING
        (load test, smoke test, QA sign-off)
                   ↓
        Manual gate → Deploy to PROD
        (requires reviewer approval in GitHub)
```

Image tags are pinned to the exact git SHA in staging and prod — never `latest`. This ensures full traceability: you can always know exactly which code is running in prod.
