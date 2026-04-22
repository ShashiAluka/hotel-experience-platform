# ADR-004: Terraform as Primary IaC Tool

**Status:** Accepted  
**Date:** 2024-01-15

## Decision

Use **Terraform** as the primary IaC tool across all environments, with AWS CDK used only for Lambda packaging helpers where CDK's asset bundling is convenient.

## Rationale

- Terraform's declarative HCL is readable and reviewable in PRs by non-engineers
- Mature module ecosystem (Terraform Registry)
- State management via S3 + DynamoDB is battle-tested at scale
- Multi-cloud portability (future-proofing)
- Team has existing Terraform expertise (matches JD requirement)
- `terraform plan` output in PRs gives reviewers clear change visibility

## Tradeoffs vs CDK

CDK has better type-safety and L2/L3 constructs that reduce boilerplate. However, Terraform's explicit state management and plan/apply workflow is more auditable for compliance environments like hospitality (PCI-DSS adjacent).

---

# ADR-005: Java Spring Boot for Reservation Service

**Status:** Accepted  
**Date:** 2024-01-15

## Decision

Implement the reservation service in **Java 17 + Spring Boot 3** running on ECS Fargate, rather than TypeScript Lambda.

## Rationale

The reservation service is the most complex service in HXP:
- **ACID transactions** across multiple state transitions (create → confirm → check-in → check-out)
- **JPA/Hibernate** for rich ORM mappings, query building, and Flyway schema migrations
- **Connection pooling** (HikariCP) for sustained throughput — Lambda + RDS requires RDS Proxy workaround
- **Spring ecosystem**: Spring Data JPA, Spring Validation, Spring Actuator all reduce boilerplate substantially
- Java's **strong typing** and compile-time checks reduce runtime errors in business-critical booking flows

Lambda cold starts for Java (2-4s) are acceptable for async workloads but not for synchronous booking APIs where p99 latency matters. Fargate keeps the JVM warm.

## Tradeoffs

- Higher idle cost (~$8/month in dev) vs Lambda (~$0)
- Slower build times (Maven) vs TypeScript
- Container image deployment complexity vs zip upload

These are acceptable given the reliability and throughput requirements of the booking path.
