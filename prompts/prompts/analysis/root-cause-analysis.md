---
title: "Root Cause Analysis"
version: 1
description: "Systematic root cause analysis using 5 Whys and fault tree techniques"
variables: ["clipboard"]
---

Perform a systematic root cause analysis on the following incident, bug, or failure.

Use multiple RCA techniques:

**5 Whys Analysis:**
Start with the observed problem and ask "why" iteratively until you reach the root cause. Document each level clearly.

**Fault Tree:**
Map out the possible causes as a tree:
- Top event (the failure)
- Intermediate causes (AND/OR gates)
- Basic events (root causes)

**Contributing Factors:**
Identify factors that didn't directly cause the issue but made it possible or worse:
- Process gaps
- Missing safeguards
- Environmental conditions
- Human factors (without blame)

**Timeline Reconstruction:**
- What was the sequence of events?
- When did the system first deviate from normal?
- What was the trigger vs. the underlying vulnerability?

Incident / failure details:

{{clipboard}}

Deliver:
1. **Root Cause Statement** — one clear sentence describing the fundamental cause
2. **Contributing Factor Summary** — other conditions that enabled the failure
3. **Evidence** — data supporting the conclusion
4. **Corrective Actions** — fixes for the root cause (not just the symptom)
5. **Preventive Actions** — systemic changes to prevent similar issues
6. **Detection Improvements** — how to catch this earlier next time

Distinguish between the root cause (why it happened), the trigger (what set it off), and the symptoms (what was observed).
