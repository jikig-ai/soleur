# Session State

## Plan Phase
- Plan file: /data/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-9995-mu1-dev-scheduled-token-401/knowledge-base/project/plans/2026-10-11-fix-mu1-ac2-dev-scheduled-github-app-credential-plan.md
- Status: complete

### Errors
- `iac-plan-write-guard.sh` blocked the first plan write (`doppler secrets set` + operator-driven framing) — resolved via genuine Phase 2.8 review + `<!-- iac-routing-ack: plan-phase-2-8-reviewed -->` literal.
- Same guard blocked tasks.md twice (ack literal exactness, "operator installs" phrasing) — fixed.
- No Task/subagent tool in subagent harness — plan-review panel and deepen fan-out ran inline sequential-fallback (disclosed in plan Enhancement Summary).

### Decisions
- Root cause proven at plan time via shape-only probes: `dev_scheduled`'s `GITHUB_APP_PRIVATE_KEY` is a valid 1679-byte PEM whose JWT `GET /app` returns 401 (unregistered key; fingerprint `8246898e` matches CI's logged pemFingerprint), while `prd`/`soleur-github-app/prd` mint 200.
- Repair = dedicated least-privilege `soleur-ci-fixture` GitHub App (`contents:read` on `jikig-ai/mu1-fixture` only) rather than copying a soleur-ai key — prd key is the retired pre-rotation key due to die at #8609 R7; isolated live key must never re-enter a `soleur/*` config per ADR-241 D10.
- Durable `scripts/probe-github-app-mint.sh` canary inside the mu1 workflow step (curl Bearer via process substitution, portable `openssl base64 -A` b64url, `openssl rsa -check` pre-flight) plus `scripts/audit-dev-scheduled-shapes.sh` auditing the dev_scheduled census with an RFC 6750 property guard.
- ACs split Pre-merge (PR) / Post-merge (operator); three consent-class gates (App create, key gen, repo install) named with automation-status annotations; `dev`'s identical dead key deliberately left unchanged.

### Components Invoked
- soleur:plan (all phases incl. tasks.md save + commit)
- soleur:deepen-plan (gates §§4.4–4.12 inline; learnings sweep; committed+pushed)
- scripts/lint-guard-contract.py — green (2 guard entries)
- gh CLI — issue/PR state verification
- doppler — shape-only probes only
- git — commits `77a288fa6f`, `a593a8bf01`, pushed to branch
