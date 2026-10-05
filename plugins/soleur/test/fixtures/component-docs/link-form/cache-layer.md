---
component: cache-layer
updated: 2026-08-06
primary_location: src/cache/
---

# Cache Layer

Synthesized fixture. Pre-contract shape; depends on database via a link, and
also names a component that does not exist in this corpus so the parser's
drop-dangling-edge behaviour is exercised.

## Dependencies

- **Internal**: [database](database.md), [ghost-service](ghost-service.md)
- **External**: redis
