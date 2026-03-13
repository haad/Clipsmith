---
title: "Incident Pattern Analysis"
version: 1
description: "Analyze incident data to identify patterns and reduce alert noise"
variables: ["clipboard"]
---

Analyze the following incident or alert data to identify patterns and actionable opportunities for reducing alert noise.

Structure your analysis as:

1. **High-Frequency Issues**
   - Rank incidents by occurrence count
   - For each: frequency, peak times, average resolution time, auto-resolve rate
   - Identify which are symptoms vs. root causes

2. **Temporal Patterns**
   - Distribution by hour of day, day of week, and month
   - Correlations with deployments, batch jobs, or traffic patterns
   - Seasonal or cyclical trends

3. **Issue Status**
   - Active issues: current status, impact level, ETA for resolution
   - Recently resolved: what fixed them, what prevention was added
   - Recurring: issues that were "resolved" but came back

4. **Alert Noise Reduction Opportunities**
   - For each opportunity: current alert volume, projected volume after fix, percent reduction, effort level
   - Categorize as: threshold adjustment, alert aggregation, auto-remediation, or alert removal

5. **Recommendations**
   - Immediate actions (threshold changes, aggregation rules)
   - Short-term improvements (enhanced monitoring, runbook updates)
   - Long-term projects (anomaly detection, unified dashboards)
   - Include specific configuration changes where possible

6. **Implementation Plan**
   - Prioritized timeline with expected outcomes
   - Metrics to track improvement

Incident data:

{{clipboard}}

Focus on actionable changes that reduce on-call burden without hiding real problems. Quantify the expected impact of each recommendation.
