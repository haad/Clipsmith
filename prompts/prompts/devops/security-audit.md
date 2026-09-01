---
title: "Infrastructure Security Audit"
version: 1
description: "Audit infrastructure code and configuration for security vulnerabilities"
variables: ["clipboard"]
---

Perform a security audit on the following infrastructure code, configuration, or architecture. Act as a DevSecOps engineer reviewing for production readiness.

Check for:

1. **Secrets & Credentials**
   - Hardcoded secrets, API keys, or passwords
   - Proper use of secrets management (Vault, AWS Secrets Manager, etc.)
   - Secrets in environment variables vs. mounted volumes

2. **Access Control**
   - Principle of least privilege (IAM roles, RBAC, network policies)
   - Overly permissive security groups or firewall rules
   - Default credentials or accounts that should be disabled

3. **Network Security**
   - Unnecessary public exposure (open ports, public endpoints)
   - Missing encryption in transit (TLS, mTLS)
   - Network segmentation and isolation

4. **Container & Runtime Security**
   - Running as root
   - Privileged containers or host mounts
   - Unsigned or unverified images
   - Missing resource limits (denial-of-service risk)

5. **Data Protection**
   - Encryption at rest for databases and storage
   - Backup encryption
   - Data retention and deletion policies

6. **Compliance**
   - Logging and audit trails
   - Relevant compliance gaps (SOC2, HIPAA, GDPR as applicable)

Infrastructure code / configuration:

{{clipboard}}

For each finding:
- **Severity:** Critical / High / Medium / Low
- **Issue:** What the problem is
- **Risk:** What could go wrong
- **Fix:** Specific remediation with code example

Prioritize findings by exploitability and impact.
