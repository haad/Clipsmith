---
title: "Assess Technical Debt"
version: 1
description: "Identify, categorize, and prioritize technical debt"
variables: ["clipboard"]
---

Analyze the following code, architecture description, or codebase notes and produce a technical debt assessment.

For each debt item identified:

1. **Description** — what the issue is, in clear terms
2. **Category** — code quality / architecture / testing / infrastructure / dependencies / documentation
3. **Impact** — how it affects development velocity, reliability, or user experience
4. **Risk** — what happens if it's not addressed (low / medium / high / critical)
5. **Effort to Fix** — rough estimate (hours / days / weeks)
6. **Interest Rate** — is this getting worse over time? How fast?

Then provide:

- **Prioritized Debt Backlog** — ordered by risk × impact, with quick wins highlighted
- **Recommended Sprint Allocation** — suggested percentage of sprint capacity for debt reduction
- **Dependencies** — debt items that should be addressed together
- **Strategic Recommendations** — systemic changes to prevent similar debt accumulation

Code / architecture context:

{{clipboard}}

Focus on debt that meaningfully slows down the team or creates risk. Not every imperfection is worth fixing — distinguish between "messy but harmless" and "actively causing problems."
