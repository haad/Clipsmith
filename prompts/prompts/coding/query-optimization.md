---
title: "Optimize Database Query"
version: 1
description: "Refactor a query to move operations from application memory into SQL for better performance"
variables: ["clipboard"]
---

Analyze the following code and refactor it to move filtering, sorting, and computation from application memory into SQL for better database performance.

For your refactoring:

1. **Problem Analysis**
   - Identify where the query executes prematurely (e.g., triggering eager loading, `.to_a`, iteration)
   - List all operations currently happening in application memory that could be SQL
   - Note any N+1 query patterns

2. **Refactored Code**
   - Build the entire query in SQL so it executes in a single database call
   - Replace in-memory `.select`/`.filter`/`.map` with SQL `WHERE`, `JOIN`, and `SELECT` clauses
   - Move calculated values into SQL expressions
   - Select only the columns needed, not entire records

3. **Key Optimizations Explained**
   - For each change: what it was before, what it is now, and why it's better
   - Explain join strategy (e.g., `includes` vs. `joins` in Rails)

4. **Suggested Indexes**
   - Recommend indexes based on the WHERE and JOIN conditions
   - Note any composite indexes that would help

5. **Expected Impact**
   - Estimated reduction in query count, memory usage, and response time
   - Any trade-offs introduced by the refactoring

Code to optimize:

{{clipboard}}

Preserve the original behavior and return format. Only change how the data is retrieved, not what is returned.
