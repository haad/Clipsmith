---
title: "Analyze Logs"
version: 1
description: "Parse application or system logs to identify errors, patterns, and anomalies"
variables: ["clipboard"]
---

Analyze the following application or system logs and extract actionable insights.

Identify:

1. **Errors & Exceptions**
   - Unique error types and their frequency
   - Stack traces and the originating code paths
   - First occurrence vs. recurring pattern

2. **Error Patterns**
   - Are errors clustered around specific times?
   - Do they correlate with specific endpoints, users, or request types?
   - Is there an increase in error rate over time?

3. **Performance Signals**
   - Slow requests or operations (with durations)
   - Timeout patterns
   - Queue depth or backpressure indicators

4. **Anomalies**
   - Unusual patterns that deviate from normal behaviour
   - Unexpected status codes or response patterns
   - Security-relevant events (auth failures, unusual access patterns)

5. **Causal Chain**
   - Which error came first?
   - Are downstream errors caused by an upstream failure?
   - What is the root event in the cascade?

Logs to analyze:

{{clipboard}}

Present findings as:
- **Critical Issues** — errors requiring immediate attention
- **Warning Patterns** — concerning trends to watch
- **Informational** — useful context for understanding system behaviour

Include specific log lines as evidence. Suggest queries or filters to continue investigating each finding.
