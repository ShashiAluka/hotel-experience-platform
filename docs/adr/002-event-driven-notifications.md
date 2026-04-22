# ADR-002: Event-Driven Notification Architecture

**Status:** Accepted  
**Date:** 2024-01-15

## Context

The reservation service needs to trigger email/SMS notifications when reservation status changes (confirmed, cancelled, checked-in). Options:
1. Direct call to notification service from within reservation service transaction
2. Synchronous REST call after transaction commits
3. EventBridge → SQS → Lambda (event-driven, fully decoupled)

## Decision

Use **EventBridge → SQS → Lambda** pipeline. The reservation service publishes domain events to EventBridge after each state transition. EventBridge rules route matching events to an SQS queue. The notification Lambda polls SQS with batch processing and partial-failure reporting.

## Rationale

- **Reliability**: Notification failure doesn't fail the booking transaction. SQS retries automatically (up to 3x), then routes to DLQ for inspection.
- **Decoupling**: Reservation service has no compile-time dependency on notification service. New notification types (loyalty points, review requests) are added by adding EventBridge rules — zero reservation service changes.
- **Observability**: SQS DLQ gives a clear signal when notifications fail. CloudWatch metrics on queue depth catch backlogs.
- **Scalability**: Lambda scales independently of ECS; a spike in bookings auto-scales notification throughput.

## Consequences

- Notifications are delivered **asynchronously** (~1-5 seconds after booking) — acceptable for this domain
- DLQ must be monitored and alarmed; failed notifications require manual re-drive or replay
- Guest email must be enriched before or during notification processing (EventBridge pipe or Lambda enrichment from DynamoDB)
