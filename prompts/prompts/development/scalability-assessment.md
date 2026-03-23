---
title: "Scalability Assessment"
version: 1
description: "Assess system scalability and identify limits under load"
variables: ["clipboard"]
---

Assess the scalability of the following system, service, or code. Identify where it will break under increasing load and what needs to change.

Analyze:

1. **Current Capacity Estimate**
   - Approximate requests/second, concurrent users, or data volume this can handle
   - Which resource will be exhausted first (CPU, memory, disk I/O, network, connections)?

2. **Scaling Bottlenecks**
   - Synchronous operations that block under load
   - Database queries that degrade with data growth (missing indexes, full table scans, N+1)
   - In-memory structures that grow unbounded
   - Connection pool limits, thread pool exhaustion
   - External service rate limits or latency amplification

3. **Horizontal vs. Vertical Scaling**
   - Can this scale out by adding instances?
   - What state is held locally that prevents horizontal scaling?
   - Are there shared resources that become contention points?

4. **Data Layer Scaling**
   - Read vs. write scaling strategies
   - Sharding, partitioning, or replication options
   - Caching opportunities and cache invalidation risks

5. **Scaling Roadmap**
   - Quick wins for immediate improvement
   - Medium-term architectural changes
   - Long-term redesign if fundamentals limit scaling

System / code to assess:

{{clipboard}}

Be quantitative where possible — estimate breaking points, not just flag risks. Provide concrete recommendations with expected improvement for each change.
