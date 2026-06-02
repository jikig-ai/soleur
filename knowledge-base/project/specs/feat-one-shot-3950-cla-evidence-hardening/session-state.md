# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-06-02-refactor-cla-evidence-scripts-hardening-bundle-plan.md
- Status: complete

### Errors
- `iac-plan-write-guard.sh` PreToolUse hook blocked first two plan-write attempts (plan quoted literal `doppler secrets set` referencing pre-existing bootstrap code). Resolved by rewording to "Doppler-secrets push" — no new infra introduced. No CWD/bare-root errors.

### Decisions
- Corrected issue body's inaccurate file lists via Research Reconciliation (git grep-verified): item-1 endpoint pinning applies to 4 real consumers (gdpr-override.sh, inspect-evidence.sh, r2-conditional-put.sh, infra/bootstrap.sh), NOT the named 6 — upload-bypass.sh/upload-evidence.sh delegate to r2-conditional-put.sh; sentinel-pr.sh doesn't consume the var. Item-2 `env -u` applies to 2 real `doppler run -- aws` sites (both in gdpr-override.sh), not the named 5.
- bootstrap.sh is in infra/, not scripts/ — new _cf-admin-token.sh helper (scripts/) requires cross-dir `source ../scripts/` with a hoisting concern (verify block runs before INFRA_DIR computed). Primary Sharp Edge.
- All 7 test fixtures use non-canonical endpoints that fail the new regex; must switch to canonical-shaped synthetic hostname. Rejected a test-only bypass backdoor.
- Rejected literal `by-pr` 404→tombstone fall-through (incoherent — tombstone keyed by sha, by-pr never holds sha); replaced with explicit `tombstone <sha>` subcommand + hint message.
- Sequenced item 3 (helper) first per issue. Used `Ref #3950` not `Closes` per do-not-autoclose.

### Components Invoked
- Skill: soleur:plan (pipeline-mode), soleur:deepen-plan; Bash, Read, Write/Edit
