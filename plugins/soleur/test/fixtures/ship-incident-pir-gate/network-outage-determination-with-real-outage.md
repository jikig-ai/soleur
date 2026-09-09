---
title: "Fix the chat message-saving regression"
type: fix
brand_survival_threshold: single-user incident
---

# fix: restore chat message persistence

### Network-Outage Deep-Dive determination (Phase 4.5)

L3 firewall and L3 DNS/routing were checked and are not implicated.

## Context

The RLS policy shipped in a prior migration required a column the INSERT sites
never populated. Every chat message write failed in production for roughly three
weeks before anyone noticed. Users were unable to save conversations for the
whole window, and the failure was silent — the client reported success.

This is a genuine production incident and owes a post-incident report.
