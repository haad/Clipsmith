---
title: "Optimize Performance"
version: 1
description: "Identify and fix performance issues"
variables: ["clipboard"]
---

Identify and fix performance bottlenecks in this code. Check for:

1. **Unnecessary allocations** — object creation inside loops, avoidable copies, retained closures
2. **N+1 patterns** — repeated queries or lookups that should be batched or cached
3. **Redundant computation** — repeated calculations that can be memoized or moved outside loops
4. **Blocking operations** — synchronous calls that should be async, or work on the wrong thread

Code to optimize:

{{clipboard}}

For each issue found, suggest a specific fix and describe the expected performance improvement. Prioritise changes by impact — not every micro-optimisation is worth the added complexity.
