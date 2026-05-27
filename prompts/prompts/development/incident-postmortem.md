---
title: "Incident Postmortem"
version: 1
description: "Write a blameless incident postmortem with root cause analysis"
variables: ["clipboard"]
---

Write a blameless incident postmortem based on the following incident details, logs, or notes.

Structure:

## Incident Summary
- **Date/Time:** when it started and ended
- **Duration:** total impact time
- **Severity:** SEV1 / SEV2 / SEV3 / SEV4
- **Impact:** what users experienced, how many were affected

## Timeline
Chronological sequence of events from first signal to full resolution. Include:
- When the issue was first detected (and how)
- Key actions taken during response
- When mitigation was applied
- When full resolution was confirmed

## Root Cause Analysis
- **Immediate cause** — what directly triggered the incident
- **Contributing factors** — conditions that allowed the immediate cause to have impact
- **Underlying cause** — the deeper systemic issue (use 5 Whys technique)

## What Went Well
- Things that worked during detection and response
- Processes or tools that helped

## What Went Wrong
- Gaps in detection, response, or communication
- Missing runbooks, monitoring, or safeguards

## Action Items
For each action item:
- Description of the fix or improvement
- Owner
- Priority (P0 / P1 / P2)
- Target completion date
- Whether it addresses the root cause or a contributing factor

## Lessons Learned
- Key takeaways for the team
- How this changes our understanding of risk

Incident details:

{{clipboard}}

Keep the tone blameless and constructive. Focus on systems and processes, not individuals. The goal is to learn and prevent recurrence.
