---
title: "Convert to Async/Await"
version: 1
description: "Modernize callback/completion handler code"
variables: ["clipboard"]
---

Convert this callback or completion-handler code to async/await. Ensure:

1. **Behaviour preserved** — all existing logic, branching, and side effects remain identical
2. **Error handling** — use do-catch blocks to replace callback error parameters
3. **Cancellation** — maintain cancellation support where the original code supported it
4. **Concurrency** — preserve any thread or actor isolation requirements

Code to convert:

{{clipboard}}

Show the fully converted async/await version. Note any cases where the conversion required a design decision or where behaviour could not be perfectly preserved.
