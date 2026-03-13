---
title: "Cloud Cost Optimization"
version: 1
description: "Identify cloud cost savings through rightsizing, waste detection, and FinOps"
variables: ["clipboard"]
---

Analyze the following cloud infrastructure, billing data, or resource configuration and identify cost optimization opportunities.

Evaluate across these areas:

1. **Rightsizing** — instances, containers, or services that are over-provisioned
   - Compare allocated vs. actual utilisation
   - Recommend appropriate instance types or sizes
   - Estimate monthly savings

2. **Waste Detection** — resources that are idle or orphaned
   - Unattached EBS volumes, unused Elastic IPs, idle load balancers
   - Stopped instances still incurring storage costs
   - Unused snapshots, old AMIs, stale ECR images
   - Dev/staging resources running 24/7

3. **Commitment Discounts** — reserved instances, savings plans, committed use
   - Which workloads are stable enough for reservations?
   - What commitment term makes sense (1 year / 3 year)?
   - Estimated discount vs. on-demand pricing

4. **Architecture Optimizations** — structural changes for cost efficiency
   - Spot/preemptible instances for fault-tolerant workloads
   - Serverless alternatives for bursty traffic
   - Storage tier optimization (hot / warm / cold / archive)
   - Data transfer cost reduction (CDN, VPC endpoints, compression)

5. **Governance** — processes to prevent cost creep
   - Tagging strategy for cost allocation
   - Budget alerts and anomaly detection
   - Automated cleanup policies

Cloud infrastructure details:

{{clipboard}}

Present findings as a prioritized table with: issue, current cost, projected savings, effort to implement, and risk level. Focus on the top 10 highest-impact opportunities first.
