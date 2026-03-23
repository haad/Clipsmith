---
title: "Architecture Review"
version: 1
description: "Review system architecture for scalability, reliability, and maintainability"
variables: ["clipboard"]
---

Perform a thorough architecture review of the following system design, diagram, or codebase description.

Evaluate across these dimensions:

1. **Scalability**
   - Can this handle 10x current load? 100x?
   - Where are the single points of contention (single-threaded, synchronous, in-memory)?
   - Can components scale horizontally or only vertically?
   - Are there bottlenecks in data flow (queues, databases, external APIs)?

2. **Reliability & Fault Tolerance**
   - What happens when each component fails?
   - Are there single points of failure?
   - Is there retry logic, circuit breaking, and graceful degradation?
   - What is the blast radius of a failure in each component?

3. **Data Integrity**
   - How is consistency maintained across services?
   - Are there race conditions or eventual consistency risks?
   - What happens during partial failures in distributed transactions?

4. **Security**
   - How is authentication and authorization handled?
   - Is data encrypted in transit and at rest?
   - Are there unnecessary attack surfaces?

5. **Operational Readiness**
   - Can this be deployed with zero downtime?
   - Is it observable (metrics, logs, traces)?
   - How is configuration managed across environments?

6. **Maintainability**
   - Are boundaries between components clean?
   - Can teams work independently without blocking each other?
   - Is the complexity proportional to the problem being solved?

Architecture to review:

{{clipboard}}

For each concern found, rate it (critical / important / minor), explain the risk, and propose a specific improvement. End with a summary of the top 5 architectural changes that would have the biggest positive impact.
