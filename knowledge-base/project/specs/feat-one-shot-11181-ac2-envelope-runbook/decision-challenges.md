# Decision Challenges — feat-one-shot-11181-ac2-envelope-runbook

Planning ran headless in a Task subagent without the `Agent` tool (OpenCode harness, nesting depth one). Technical items below carry `pending - assumed:` per technical-ruling-delegation.md §3/§6: the calling pipeline obtains the CTO ruling in one batched spawn right after the plan phase; ship's `technical-ruling-gate.sh` fails any row still unruled.

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| T1 commit the envelope byte-identical or redact internal IPs before the public-repo commit | technical | Ruled by CTO agent, 2026-10-27: commit byte-identical - ADR-289 receipts pin `sha256=` against the bytes read from git, so any redaction edit breaks every future receipt with a false mismatch and defeats the audit purpose this commit exists to serve; evidence confirmed the envelope carries no credential values (its only values are RFC1918 host addresses) and ~15 sibling runbooks already on main publish the same 10.0.x.x class of address. Ruling stands on verified precedent, not on the brief's names-only framing |
| T2 brand-survival threshold for this plan (drives review-panel size per ADR-267) | technical | Ruled by CTO agent, 2026-10-27: none - the canonical sensitive-path regex covers only apps/web-platform server/supabase/lib surfaces, apps/*/infra/, Doppler-aware scripts, and credential-handling workflows; a knowledge-base/engineering/operations/runbooks/*.md addition matches zero of these and ships no user-facing or production-mutating artifact, worst failure is a lost audit trail |
| T3 no delegated-act receipt comment exists on epic #11181 for the AC2 act - which carrier reconciles it | technical | Ruled by CTO agent, 2026-10-27: reconciliation stays with epic #11181 and the executing session's receipt duty (cto.md step 6), not this KB archival PR - folding a GitHub-comment act in would ship an undelegated action on a different carrier surface; the lead session's single consolidated status comment on the epic carries the AC2 receipt reference |
