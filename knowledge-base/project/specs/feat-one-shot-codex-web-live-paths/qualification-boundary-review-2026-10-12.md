---
title: Focused qualification boundary preparation review
date: 2026-10-12
pr: 9051
source_sha: ca627f794f7a68cc4afcb685bef3f53d1eacc436
status: seven-focused-findings-source-verified-operational-candidate-pending
---

# Focused review scope

Security, data-integrity and test-design seats independently examine the pushed
preparation delta from `bc0f0d47c72369c26eac91308687a6a1fe9ea762` to the source
above. This is preparation source review, not full PR review, runtime rehearsal,
SAST, C.9 clearance, authentication evidence or promotion approval.

## Findings ledger before fixes

| Raw finding | Canonical defect key | Reporting seat(s) | Planned fix commit |
|---|---|---|---|
| Queued request dispatches after fatal/deadline | proxy-admission-state-race | security-sentinel | qualification boundary corrections |
| Inherited image volume lacks registered owned bind | implicit-unowned-image-volume | security-sentinel | qualification boundary corrections |
| Foreign Host fixture can contact upstream and still pass | TLS-refusal-upstream-oracle | test-design-reviewer | qualification boundary corrections |
| No prohibited stdin transport assertion | exec-upgrade-stdin-oracle | test-design-reviewer | qualification boundary corrections |
| Comment-only runner anchors remove blockers | runner-shape-comment-vacuity | data-integrity-guardian | qualification boundary corrections |
| Pending execution survives cleanup transition; transport fatal lacks lock | proxy-admission-state-race | security-sentinel | qualification cleanup correction |
| Backend EOF can precede proxy fatal publication | exec-upgrade-stdin-oracle | test-design-reviewer | qualification cleanup correction |

## Binding technical direction

Ruled by CTO agent, 2026-10-12: extend the owned Docker internal-network
controller and namespace bridge, with role-specific effective image/command/
environment profiles and task-scoped exact-host TLS/DNS. Internal-network
declarations are preparation, not demonstrated route/DNS isolation. No bwrap
substitution or host DNS/global trust changes. Dissent: no independent dissent
collected in that focused ruling.

Ruled by CTO agent, 2026-10-12: fix the canonical fresh-ledger defect before
qualifying a fresh full-schema apply; fixture-precreating `content_sha` would
conceal the source defect. Preserve atomic body-plus-ledger application,
complete forward bodies and production guards. The exact namespace-only
`net.ipv4.ip_unprivileged_port_start=0` is admissible for nonroot TLS/resolver
roles with no added capabilities or host networking; runtime observation is
still owed. Dissent: no independent dissent collected.

## Disposition limits

### Source verification — 2026-10-13

At pushed `a42d5e94fb2acc7923fd6b4695f73f1925481952`, a fresh code-quality
verifier independently closed all seven ledger rows within preparation source
and synthetic-fixture scope, with no new concrete same-area finding. It ran
37 tests across six modules, repeated both cleanup transition schedules against
the old and corrected sources, and forced delayed fatal publication after
backend EOF to verify the repaired stdin synchronization. Root's complete
offline wrapper passed with inherited `PYTHONOPTIMIZE=1`; no assertion-erasure
environment was accepted. Schema guardian independently verified the exact
canonical runner identity and found no unresolved concrete finding in the
prepared SQL source. No SQL was evaluated.

Main through `41b8801ad8e8e19ec41cbb79c98e9a77f06620d9` and then
`943ebacc2d1e7fc5f8e0f7fc7f47110447aff35a` was merged. The first resolution
recomputed the three merged legal-document hashes and retained main's safe
temporary-directory pattern alongside the existing CI-only-test procedure.
The second retained the new control-intake evidence in main's historical
rollout archive and repointed active references. Both merges leave the
qualification components and canonical runner unchanged. Incoming runtime,
plugin and schema inputs still require fresh source fingerprints; preceding
previews remain historical. No incoming runtime/deployment/SQL command ran.

Current-head CI identified `role_profiles.py` as an unpinned Supabase Management
API caller solely because its environment ban names the access token. The
existing dated non-caller mechanism records this pure policy file; the scanner
still requires zero Management API sites for it. No real caller or host check
is exempted. Full pushed-head CI and final-description guards remain separate.

No Docker, image pull/build/retry, application/database startup, SQL execution,
authentication, credentials/provider/account/shared write, deployment or
flag/cohort operation occurred. A runnable operational candidate still needs
actual role image configurations, namespace/session orchestration and retained
file-byte manifests. Build/recovery approval remains consumed. Keep draft,
auto-merge off, Codex default-off and customer content blocked. Full review,
required SAST and current-source C.9 remain incomplete.
