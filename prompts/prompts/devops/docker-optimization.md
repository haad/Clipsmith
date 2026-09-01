---
title: "Optimize Dockerfile"
version: 1
description: "Audit and optimize Dockerfiles for size, security, and build performance"
variables: ["clipboard"]
---

Audit the following Dockerfile and provide specific improvements across these dimensions:

1. **Image Size** — reduce final image size
   - Use multi-stage builds where appropriate
   - Choose minimal base images (alpine, distroless, slim variants)
   - Remove unnecessary files, caches, and build dependencies
   - Combine RUN layers to reduce layer count

2. **Build Performance** — speed up builds
   - Optimize layer caching (order commands by change frequency)
   - Leverage BuildKit features (cache mounts, parallel stages)
   - Avoid invalidating the cache unnecessarily

3. **Security** — harden the image
   - Run as non-root user
   - Pin base image versions (avoid :latest)
   - Remove unnecessary packages and tools
   - Scan for known vulnerabilities in dependencies
   - Don't copy secrets or credentials into the image

4. **Best Practices** — general improvements
   - Use .dockerignore effectively
   - Add health checks
   - Set appropriate labels and metadata
   - Handle signals correctly (use exec form for CMD/ENTRYPOINT)

Dockerfile to review:

{{clipboard}}

Provide the optimized Dockerfile with comments explaining each change. Show a before/after comparison of expected image size where possible.
