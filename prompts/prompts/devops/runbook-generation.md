---
title: "Generate Runbook"
version: 1
description: "Create operational runbooks for incident detection, triage, and resolution"
variables: ["clipboard"]
---

Create a detailed operational runbook for the following service, alert, or failure scenario. This runbook will be used by on-call engineers during incidents.

Structure:

## Overview
- What this runbook covers
- When to use it (triggering alert or condition)
- Service owner and escalation contacts

## Detection
- How the issue is detected (alert name, monitoring dashboard)
- What the alert means in plain language
- Severity classification

## Triage
- Quick health checks to run first (with exact commands)
- How to assess impact (users affected, data at risk)
- Decision tree: when to escalate vs. self-resolve

## Diagnosis
- Step-by-step diagnostic commands with expected output
- Common causes ranked by frequency
- How to distinguish between causes
- Relevant logs and where to find them

## Mitigation
- Immediate actions to reduce impact (before root cause is fixed)
- Rollback procedures if applicable
- How to communicate status to stakeholders

## Resolution
- Step-by-step fix for each common cause
- Verification commands to confirm the fix worked
- How to determine if the issue is fully resolved

## Post-Resolution
- What to clean up
- Monitoring to watch for recurrence
- When to close the incident
- Follow-up action items

Service / scenario description:

{{clipboard}}

Write for an engineer who may be unfamiliar with this system. Every command should be copy-pasteable. Include expected output so the reader knows if they're on the right track.
