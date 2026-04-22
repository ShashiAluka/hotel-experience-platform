# 🏨 Hotel Experience Platform (HXP)

A production-grade, serverless-first full-stack cloud platform for hospitality management. Built on AWS using event-driven microservices, React, Java Spring Boot, TypeScript, and Terraform IaC — demonstrating enterprise-scale cloud-native architecture.

[![CI/CD](https://github.com/ShashiAluka/hotel-experience-platform/actions/workflows/ci.yml/badge.svg)](https://github.com/ShashiAluka/hotel-experience-platform/actions)
[![Terraform](https://img.shields.io/badge/IaC-Terraform-7B42BC)](https://www.terraform.io/)
[![AWS](https://img.shields.io/badge/Cloud-AWS-FF9900)](https://aws.amazon.com/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                          CloudFront CDN                              │
│                     (React SPA + API routing)                        │
└───────────────────────────┬─────────────────────────────────────────┘
                            │
              ┌─────────────▼──────────────┐
              │       API Gateway (REST)    │
              └──┬──────────┬──────────────┘
                 │          │
    ┌────────────▼──┐   ┌───▼────────────────┐
    │  Lambda       │   │  ECS Fargate        │
    │  (TS)         │   │  Reservation Svc    │
    │  Guest Profile│   │  (Java Spring Boot) │
    └────────┬──────┘   └───────┬────────────┘
             │                  │
    ┌────────▼──────────────────▼────────────┐
    │           Event Bus (EventBridge)       │
    └───────────────────┬────────────────────┘
                        │
         ┌──────────────▼──────────────┐
         │     SQS Queues + DLQ        │
         └──────────┬──────────────────┘
                    │
         ┌──────────▼──────────────┐
         │  Notification Lambda    │
         │  (SES email + SMS)      │
         └─────────────────────────┘

Data Layer:
  RDS PostgreSQL  ← Reservations (relational, ACID)
  DynamoDB        ← Guest Profiles (key-value, high throughput)
  DocumentDB      ← Audit Logs (document store)
  S3 Data Lake    ← Analytics events (Glue + Athena)
```

---

## Services

| Service | Language | Runtime | Database | Description |
|---------|----------|---------|----------|-------------|
| `reservation-service` | Java 17 + Spring Boot | ECS Fargate | RDS PostgreSQL | Booking lifecycle management |
| `guest-profile-service` | TypeScript | Lambda | DynamoDB | Guest profiles & loyalty |
| `notification-service` | TypeScript | Lambda | — | Event-driven email/SMS |
| `analytics-pipeline` | Python (Glue) | Glue + Athena | S3 | Reservation analytics |
| `frontend` | React 18 + TypeScript | S3 + CloudFront | — | Management dashboard |

---

## Tech Stack

### Backend & APIs
- **Java 17** + Spring Boot 3 (Reservation Service — ECS Fargate)
- **TypeScript** + AWS Lambda (Guest Profile, Notification services)
- **REST APIs** via API Gateway with request validation and authorizers

### Frontend
- **React 18** + TypeScript + Vite
- Hosted on **S3** served via **CloudFront**
- Recharts for occupancy analytics

### AWS Infrastructure
- **Compute**: Lambda, ECS Fargate, EC2 (Bastion)
- **API**: API Gateway (REST), CloudFront
- **Messaging**: EventBridge, SQS (+ DLQ)
- **Storage**: RDS PostgreSQL, DynamoDB, DocumentDB, S3
- **Networking**: VPC, subnets, security groups, NAT gateway
- **Observability**: CloudWatch, X-Ray, structured JSON logging
- **Security**: IAM least-privilege, Secrets Manager, KMS

### IaC & DevOps
- **Terraform** (primary IaC) — modular, 3 environments (dev/staging/prod)
- **AWS CDK** (supplementary for Lambda deployments)
- **GitHub Actions** CI/CD with environment gates
- **Docker** + ECR for containerized services

### Data Engineering
- **DBT** for analytics transformations
- **AWS Glue** for ETL
- **Athena** for serverless SQL on S3

---

## Repository Structure

```
hxp/
├── infrastructure/
│   └── terraform/
│       ├── modules/          # Reusable Terraform modules
│       │   ├── vpc/
│       │   ├── rds/
│       │   ├── dynamodb/
│       │   ├── lambda/
│       │   ├── ecs/
│       │   ├── s3/
│       │   └── api-gateway/
│       └── environments/     # Per-environment root configs
│           ├── dev/
│           ├── staging/
│           └── prod/
├── services/
│   ├── reservation-service/  # Java Spring Boot (ECS)
│   ├── guest-profile-service/# TypeScript Lambda
│   └── notification-service/ # TypeScript Lambda
├── frontend/                 # React 18 + TypeScript
├── analytics/
│   ├── dbt/                  # DBT models
│   └── glue/                 # AWS Glue jobs
├── docs/
│   ├── adr/                  # Architecture Decision Records
│   └── diagrams/             # Architecture diagrams
└── .github/
    └── workflows/            # CI/CD pipelines
```

---

## Getting Started

### Prerequisites
- AWS CLI configured with appropriate credentials
- Terraform >= 1.6
- Docker & Docker Compose
- Node.js >= 20
- Java 17 + Maven
- (Optional) AWS CDK CLI

### Local Development

```bash
# Clone the repo
git clone https://github.com/ShashiAluka/hotel-experience-platform.git
cd hotel-experience-platform

# Start all services locally with Docker Compose
docker-compose up -d

# Frontend dev server
cd frontend && npm install && npm run dev

# Reservation service
cd services/reservation-service && mvn spring-boot:run

# Guest profile service
cd services/guest-profile-service && npm install && npm run dev
```

### Deploy to AWS (dev environment)

```bash
cd infrastructure/terraform/environments/dev

terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

---

## CI/CD Pipeline

```
Push to feature/* → CI (lint, test, build)
                         │
Merge to main    → Deploy to DEV (auto)
                         │
Manual gate      → Deploy to STAGING
                         │
Manual gate      → Deploy to PROD (with approval)
```

Pipeline stages per service:
1. **Lint & Format** — ESLint, Checkstyle, Prettier
2. **Unit Tests** — JUnit 5, Jest
3. **Integration Tests** — Testcontainers (PostgreSQL), DynamoDB Local
4. **Build** — Maven JAR, npm build, Docker image
5. **Push to ECR** — Tagged with git SHA
6. **Terraform Plan** — Reviewed as PR comment
7. **Deploy** — Blue/green via ECS, Lambda versioning

---

## Architecture Decision Records

| ADR | Title | Status |
|-----|-------|--------|
| [ADR-001](docs/adr/001-serverless-first.md) | Serverless-first compute strategy | Accepted |
| [ADR-002](docs/adr/002-event-driven-notifications.md) | Event-driven notification architecture | Accepted |
| [ADR-003](docs/adr/003-database-per-service.md) | Database-per-service pattern | Accepted |
| [ADR-004](docs/adr/004-terraform-over-cdk.md) | Terraform as primary IaC | Accepted |
| [ADR-005](docs/adr/005-java-reservation-service.md) | Java Spring Boot for Reservation Service | Accepted |

---

## Cost Estimate (dev environment)

| Service | Monthly Est. |
|---------|-------------|
| ECS Fargate (0.25 vCPU, 0.5GB) | ~$8 |
| RDS PostgreSQL (db.t3.micro, single-AZ) | ~$15 |
| DynamoDB (on-demand, low traffic) | ~$1 |
| API Gateway (1M requests) | ~$3.50 |
| Lambda (1M invocations) | ~$0.20 |
| CloudFront + S3 | ~$1 |
| **Total (dev)** | **~$29/month** |

> Prod estimate: ~$180–250/month depending on traffic volume.

---

## Author

**Shashi Preetham Alukapally** — Senior Data / Full Stack Cloud Engineer  
[GitHub](https://github.com/ShashiAluka) · [LinkedIn](https://linkedin.com/in/shashi-preetham)

---

## License

MIT License — see [LICENSE](LICENSE)
