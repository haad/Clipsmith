---
title: "API Design Review"
version: 1
description: "Review and improve REST or GraphQL API design"
variables: ["clipboard"]
---

Review the following API design (endpoints, schema, or specification) and provide detailed feedback.

Evaluate against these criteria:

1. **Naming & Consistency** — are resource names, endpoints, and fields clear and consistent?
2. **RESTful Principles** — proper use of HTTP methods, status codes, and resource modelling
3. **Request/Response Design** — are payloads well-structured, minimal, and predictable?
4. **Error Handling** — are errors informative, consistent, and machine-parseable?
5. **Pagination & Filtering** — are collection endpoints properly paginated with filtering support?
6. **Versioning** — is there a clear versioning strategy?
7. **Authentication & Authorization** — is the auth model appropriate and consistently applied?
8. **Rate Limiting & Quotas** — are there protections against abuse?
9. **Idempotency** — are mutating operations safe to retry?
10. **Documentation** — are the endpoints self-documenting or well-described?

API design to review:

{{clipboard}}

For each issue found:
- Explain the problem
- Rate severity (critical / important / suggestion)
- Provide a concrete fix with example

End with a summary of the top 3 changes that would most improve this API.
