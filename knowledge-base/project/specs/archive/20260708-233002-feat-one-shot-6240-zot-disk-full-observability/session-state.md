# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-07-08-fix-zot-disk-full-observability-and-resize2fs-plan.md
- Status: complete

### Errors
None.

### Decisions
- Root cause: the ext4 fs on the 30 GB zot volume is out of space; leading mechanism is `resize2fs` silently failing (`|| true`) so the fs never grew to the 30 GB block device. The prior post-mortem's "disk not full" was FALSIFIED — it read the Hetzner block-device size, never the fs size. "Recurring since 957350d8" is time-correlation, not causal.
- Observability path: `SOLEUR_ZOT_DISK` structured event (df% + resize before/after + fs size + zot health) POSTed to the existing Better Stack Logs source via `BETTERSTACK_LOGS_TOKEN` in the isolated `soleur-registry` Doppler project (precedent: inngest-betterstack-token.tf), queryable via `betterstack-query.sh --grep`. Boot isolation guard amended 2→3 secrets (fail-loud).
- Fix + sequencing: ONE PR = observability + resize2fs fail-loud hardening (device-wait, e2fsprogs audit, verify fs≈30 GB) + gc/retention tightening → ONE registry-host-replace redeploy where telemetry both diagnoses + confirms. Volume-grow and dedupe/OOM are telemetry-gated contingent follow-ups, not blind changes.
- Architecture: amend ADR-096 (isolation-guard cardinality, disk-observability delivery, resize remediation) + add `zotRegistry -> betterstack` edge to model.c4 (in-scope deliverables).
- Gate: deepen-plan 4.8 PAT-shaped halt false-positives on `var.betterstack_logs_token` (Better Stack ingest token, not GitHub PAT; mirrors merged precedent) — documented non-violation. Downtime & Cutover / network-outage gates satisfied (registry reboot accepted; serving GHCR-fallback-covered; threshold aggregate pattern).

### Components Invoked
- Skills: soleur:plan, soleur:deepen-plan
- Agents: learnings-researcher, functional-discovery
