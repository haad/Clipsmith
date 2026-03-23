---
title: "Design Monitoring & Alerting"
version: 1
description: "Set up monitoring, alerting rules, and dashboards for services"
variables: ["clipboard"]
---

Design a monitoring and alerting strategy for the following service or system. Cover the full observability stack.

**Metrics to Track:**
1. **RED Metrics** (for services) — Rate, Errors, Duration
2. **USE Metrics** (for resources) — Utilisation, Saturation, Errors
3. **Business Metrics** — KPIs specific to this service's purpose
4. **SLI/SLO Definitions** — what "healthy" looks like, with specific thresholds

**Alert Rules:**
For each alert, specify:
- Alert name and severity (critical / warning / info)
- PromQL or query expression
- Threshold and evaluation window
- Runbook link or immediate action steps
- Who gets paged and through what channel

**Dashboard Design:**
- Overview dashboard with key health indicators
- Drill-down panels for debugging
- Suggested Grafana panel types and queries

**Log Strategy:**
- What to log at each level (error / warn / info / debug)
- Structured logging fields to include
- Log-based alerts for events that metrics can't catch

Service / system description:

{{clipboard}}

Focus on actionable alerts that indicate real problems — avoid alert fatigue. Every critical alert should have a clear response action. Include example Prometheus rules and Grafana JSON where helpful.
