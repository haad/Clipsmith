---
title: "Troubleshooting Guide"
version: 1
description: "Systematic troubleshooting of production issues with diagnostic steps"
variables: ["clipboard"]
---

Help troubleshoot the following production issue. Work through this systematically, like a senior engineer on call.

**Step 1: Understand the Symptom**
- What exactly is happening vs. what should happen?
- When did it start? Was there a recent change (deploy, config change, traffic spike)?
- Who/what is affected? Is it all users or a subset?
- Is it intermittent or consistent?

**Step 2: Gather Evidence**
Suggest specific diagnostic commands and checks to run:
- Health checks, status endpoints
- Relevant logs (and what to grep for)
- Metrics to examine (CPU, memory, latency, error rates)
- Network connectivity tests
- Database state and query performance
- Recent deployment or configuration changes

**Step 3: Form Hypotheses**
List the most likely causes ranked by probability, with:
- Why you suspect each cause
- How to confirm or rule it out
- Expected evidence for each hypothesis

**Step 4: Isolate the Problem**
- How to narrow down the failing component
- Binary search approach to find the change that broke things
- How to reproduce the issue in a safe environment

**Step 5: Resolve**
For each likely cause, provide:
- Immediate mitigation (stop the bleeding)
- Proper fix (address the root cause)
- Rollback procedure if the fix doesn't work

**Step 6: Verify**
- How to confirm the issue is resolved
- What to monitor for the next 24 hours

Issue description:

{{clipboard}}

Think out loud. Explain your reasoning at each step so the reader learns the troubleshooting approach, not just the answer. Provide exact commands to run.
