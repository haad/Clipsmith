---
title: "Disaster Recovery Plan"
version: 1
description: "Create a disaster recovery plan with backup, RTO, and RPO targets"
variables: ["clipboard"]
---

Create a comprehensive disaster recovery plan for the following system or infrastructure.

**Recovery Objectives:**
- **RTO** (Recovery Time Objective) — maximum acceptable downtime
- **RPO** (Recovery Point Objective) — maximum acceptable data loss window
- Justify these targets based on business impact

**Backup Strategy:**
- What to back up (databases, configs, secrets, state files, artifacts)
- Backup frequency and retention policy
- Backup location (cross-region, cross-provider, offline copies)
- Backup verification and restore testing schedule

**Failure Scenarios:**
For each scenario, document:
- What triggers it
- Impact (data loss, downtime, partial degradation)
- Detection method
- Step-by-step recovery runbook
- Estimated recovery time

Cover at minimum:
1. Single service failure
2. Database corruption or loss
3. Full region/zone outage
4. Accidental deletion (infrastructure or data)
5. Security breach / compromised credentials
6. DNS or networking failure

**Testing Plan:**
- How often to run DR drills
- What to validate during each drill
- Success criteria and reporting

System / infrastructure description:

{{clipboard}}

Be specific with commands, scripts, and configurations. A DR plan is useless if it can't be executed under pressure by an on-call engineer at 3 AM.
