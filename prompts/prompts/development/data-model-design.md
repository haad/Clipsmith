---
title: "Data Model Design"
version: 1
description: "Transform requirements into a validated data model with SQL implementation"
variables: ["clipboard"]
---

Design and validate a data model based on the following requirements.

Follow this process:

1. **Requirements Analysis**
   - Identify all entities and their attributes
   - Map relationships (one-to-one, one-to-many, many-to-many)
   - Note any constraints, indexes, or special behaviors needed

2. **Schema Design**
   - Produce a normalized SQL schema (CREATE TABLE statements)
   - Include primary keys, foreign keys, indexes, and constraints
   - Add audit fields (created_at, updated_at) where appropriate
   - Handle soft deletes, versioning, or history tracking if the requirements call for it

3. **Relationship Mapping**
   - Document each relationship with cardinality
   - Explain junction tables for many-to-many relationships
   - Note cascade behavior for deletes and updates

4. **Use Case Validation**
   - For each use case in the requirements, provide a sample query (INSERT, SELECT, UPDATE) that proves the model supports it
   - Flag any use case the model cannot support and suggest additions

5. **Performance Considerations**
   - Recommend indexes for common query patterns
   - Note potential N+1 or join-heavy queries and how to mitigate them
   - Suggest denormalization only where justified by read patterns

Requirements:

{{clipboard}}

Keep the design as simple as possible while fully supporting the stated use cases. Avoid speculative features.
