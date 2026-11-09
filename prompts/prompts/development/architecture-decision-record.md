---
title: "Architecture Decision Record"
version: 1
description: "Document an architectural decision with context, options, and rationale"
variables: ["clipboard"]
---

Create an Architecture Decision Record (ADR) based on the following context or technical decision.

Use this structure:

## Title
ADR-NNN: [Short descriptive title]

## Status
Proposed / Accepted / Deprecated / Superseded

## Context
- What is the technical or business problem?
- What forces are at play (constraints, requirements, team capabilities)?
- Why does this decision need to be made now?

## Options Considered

For each option:
- **Description** — what the approach entails
- **Pros** — advantages and strengths
- **Cons** — disadvantages and risks
- **Effort** — rough implementation cost
- **Examples** — where this approach has worked before

## Decision
- Which option was chosen and why
- How it satisfies the key requirements
- What trade-offs are being accepted

## Consequences
- What becomes easier or harder as a result
- What follow-up work is needed
- What to watch for — signals that this decision should be revisited

Context / decision:

{{clipboard}}

Be precise about the technical trade-offs. Future readers need to understand not just what was decided, but why — especially the alternatives that were rejected and the reasoning behind that.
