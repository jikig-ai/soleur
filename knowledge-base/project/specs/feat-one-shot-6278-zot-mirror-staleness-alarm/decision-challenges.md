# Architecture Decision — #6278 alarm mechanism

## Fork: Branch B (metric alert) vs Branch A (issue alert) — RESOLVED by CTO agent (2026-07-09)

**Decision:** Ship **Branch A** — `sentry_issue_alert.zot_mirror_fallback_rate` with a
`conditions_v2` `event_frequency` (count > 3 / 1h) rule, notifying via the repo-standard
symbolic `IssueOwners → ActiveMembers` fallthrough. Reject Branch B (`sentry_metric_alert`)
for this PR.

**Why the plan's stated PRIMARY (Branch B) was inverted:** Phase-0 implementation surfaced a
constraint the plan under-weighted. `sentry_metric_alert` `trigger.action` requires a concrete
numeric `target_identifier` (team/member id) — there is NO `IssueOwners/ActiveMembers` symbolic
fallthrough for metric-alert actions. This Sentry TF root has **zero** resolvable numeric notify
targets (no `sentry_team` data source, no `owner=`, no team var; all 20 existing issue alerts use
the symbolic fallthrough), and the token to look one up (`SENTRY_IAC_AUTH_TOKEN`) is CI-only
(ADR-031, not in Doppler). Branch B is therefore not autonomously deployable/verifiable this
session and risks a safety control that fires but **pages nobody** — the strictly worst outcome.

**Accepted limitation (operator-surfaced in PR body):** Branch A's `event_frequency` thresholds
PER fingerprinted issue-group, not on a true cross-signal aggregate. It reliably pages on the
dominant shared-tag correlated outage (a rolling-deploy zot miss drives many hosts onto the same
`ghcr-fallback (web:<tag>)` group → crosses 3/group), missing only the fully-distributed thin
spread (<3 in every signal-group simultaneously) — the correlated-failure tail, not the mode the
"aggregate pattern" threshold targets.

**Follow-up filed:** upgrade to `sentry_metric_alert` once a resolvable numeric notify target lands
(unblocks at the first non-founder Sentry seat — the same boundary issue-alerts.tf comments already
defer).

**Rejected alternatives:** (1) Branch B — theoretically-superior aggregation, but unresolvable/
unverifiable notify target. (2) Branch B + `data "sentry_team"` slug lookup — does not rescue
verifiability (wrong/member-less slug either fails apply or emails nobody; `terraform validate`
catches neither) and adds guard artifacts without removing the core defect.

**CTO-mandated cleanups folded in:** correct the stale `event_frequency` "no verified support"
comments (issue-alerts.tf:838-839, ADR-062:120 — falsified by the beta2 schema probe); guard-parity
check on the existing type-level destroy-guard/scope-guard/counter-test.
