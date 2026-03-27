---
adr: ADR-019
title: Terraform Only for Infrastructure
status: active
date: 2026-03-27
---

# ADR-019: Terraform Only for Infrastructure

## Context

Vendor-specific APIs (Hetzner API, AWS CLI) were used for creating servers, volumes, firewalls. This creates non-reproducible, non-portable infrastructure.

## Decision

Always use Terraform for infrastructure provisioning — never vendor-specific APIs for creating servers, volumes, firewalls, or DNS records. Use vendor APIs only for read-only operations (checking availability, listing resources) or account-level tasks that Terraform doesn't cover. Existing patterns live in apps/telegram-bridge/infra/ and apps/web-platform/infra/.

## Consequences

Reproducible infrastructure across environments. Portable across cloud providers. State tracked in remote backend (ADR-006). Vendor APIs still useful for discovery and account management. Slightly more setup overhead for simple one-off resources.
