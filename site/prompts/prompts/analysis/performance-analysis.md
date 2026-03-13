---
title: "Performance Analysis"
version: 1
description: "Identify performance bottlenecks and optimization opportunities"
variables: ["clipboard"]
---

Analyze the following code, query, system metrics, or architecture for performance issues and optimization opportunities.

Investigate:

1. **Execution Bottlenecks**
   - Nested loops, expensive iterations, or O(n²)+ algorithms
   - Blocking I/O, synchronous calls that could be async
   - Redundant computations or repeated work
   - Expensive serialization/deserialization

2. **Database Performance**
   - Slow queries (missing indexes, full table scans, unnecessary JOINs)
   - N+1 query patterns
   - Over-fetching data (SELECT * when only a few columns are needed)
   - Transaction scope too broad (holding locks too long)

3. **Memory & Resource Usage**
   - Memory leaks or unbounded growth
   - Large object allocations in hot paths
   - Inefficient data structures for the access pattern
   - Resource handles not being released (connections, file descriptors)

4. **Caching Opportunities**
   - Repeated expensive computations that could be cached
   - Cache invalidation strategy
   - Appropriate TTLs and cache size limits

5. **Concurrency**
   - Thread contention, lock congestion
   - Opportunities for parallelism
   - Async patterns that could improve throughput

Code / metrics / system details:

{{clipboard}}

For each issue: describe the problem, estimate the performance impact (high / medium / low), and provide a concrete fix with example code where applicable. Prioritize by impact — fix the biggest bottleneck first.
