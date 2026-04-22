# ADR-003: Database-Per-Service Pattern

**Status:** Accepted  
**Date:** 2024-01-15  
**Author:** Shashi Preetham Alukapally

---

## Context

Multiple services need persistent storage. We must decide whether to share a single database or give each service its own.

---

## Decision

Each service owns its own data store, chosen to fit its access patterns:

| Service | Database | Rationale |
|---------|----------|-----------|
| reservation-service | RDS PostgreSQL | Relational, ACID transactions, complex queries |
| guest-profile-service | DynamoDB | Key-value, high read throughput, flexible schema |
| audit-service | DocumentDB | JSON documents, append-only, schema flexibility |
| analytics | S3 + Athena | Immutable event lake, serverless SQL |

No service queries another service's database directly — cross-service data access goes through APIs or events.

---

## Consequences

**Positive:**
- Services can scale, deploy, and fail independently
- Database schema changes don't require coordinated cross-team deployments
- Each database is optimized for its workload
- Fault isolation: RDS failure doesn't affect DynamoDB reads

**Negative:**
- No cross-service SQL joins (must use API composition or event-driven denormalization)
- Higher operational surface area (multiple database types)
- Data consistency is eventual for cross-service aggregates

---

## Consistency Strategy

For read-heavy cross-service views (e.g., "reservation with guest name"), we use:
1. **API composition at the BFF/Gateway layer** for low-volume requests
2. **Event-driven denormalization** — guest-profile-service publishes `guest.updated` events; reservation-service caches the guest name it needs at booking time
