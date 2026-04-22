# ADR-001: Serverless-First Compute Strategy

**Status:** Accepted  
**Date:** 2024-01-15  
**Author:** Shashi Preetham Alukapally

---

## Context

HXP needs a compute strategy for its microservices. Options considered:
1. EC2-based always-on instances
2. ECS Fargate (container-based, serverless infrastructure)
3. AWS Lambda (function-as-a-service)
4. Hybrid (Lambda for stateless, Fargate for stateful)

The platform has uneven traffic patterns — peak bookings during business hours, near-zero at night. Services range from simple CRUD (guest profiles) to long-running transactional workflows (reservations).

---

## Decision

Adopt a **serverless-first, hybrid approach**:

- **AWS Lambda** for stateless, event-driven, and CRUD-heavy services (guest-profile-service, notification-service, analytics triggers)
- **ECS Fargate** for the reservation-service, which has Spring Boot startup overhead, manages JPA connection pools, and benefits from persistent process state
- **No self-managed EC2** except bastion hosts for DB access

---

## Rationale

| Factor | Lambda | Fargate |
|--------|--------|---------|
| Cold start | <1s (TS) / 2-4s (Java) | Warm always |
| Cost (low traffic) | ~$0 | ~$8/month |
| Connection pooling | Limited (RDS Proxy needed) | Native |
| Scaling | Instantaneous | 30-60s |
| Operational overhead | Minimal | Low |

Lambda is the right choice for guest profiles and notifications — both are stateless, bursty, and TypeScript-based (fast cold starts). The reservation service uses Java/Spring Boot with JPA + connection pooling, making Fargate more appropriate.

---

## Consequences

**Positive:**
- Near-zero idle cost in dev/staging
- No server patching or capacity planning
- Auto-scaling by default
- Lambda concurrency limits provide natural rate limiting

**Negative:**
- Lambda cold starts add latency on first invocation (mitigated with provisioned concurrency in prod)
- Fargate requires ECS cluster management
- Different deployment models per service (zip vs container image)

---

## Alternatives Rejected

- **All Lambda**: Java cold starts (2-4s) are unacceptable for the synchronous reservation API. JPA + connection pooling does not work well in Lambda without RDS Proxy (added cost/complexity).
- **All Fargate**: Overengineered for simple Lambda-suited workloads; higher idle cost.
- **EC2**: Too much operational overhead; no alignment with serverless-first mandate.
