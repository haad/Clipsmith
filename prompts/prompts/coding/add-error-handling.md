---
title: "Add Error Handling"
version: 1
description: "Add proper error handling to code"
variables: ["clipboard"]
---

Add robust error handling to this code. Focus on:

1. **Input validation** — check for invalid, missing, or malformed inputs before processing
2. **Nil/null checks** — guard against null dereferences at every access point
3. **Failure paths** — wrap operations that can fail with try-catch or result types
4. **Error messages** — provide clear, actionable messages that identify the problem

Code to improve:

{{clipboard}}

Keep error handling proportional to risk — not every line needs a guard, but every failure that could crash or corrupt state must be handled. Show the updated code.
