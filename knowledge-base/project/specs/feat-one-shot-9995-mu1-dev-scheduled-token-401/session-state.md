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

## Work Phase (2026-10-11)
- Status: implementation complete, deferred provisioning per operator decision

### Done
- `scripts/probe-github-app-mint.sh` + `.test.sh` — 27/27 rows (Guard-1 1–5
  + missing/non-numeric env + garbage PEM + xtrace refusal). ADR-280
  superseded the plan's inline process-substitution Bearer header: the JWT
  rides `bc_curl`'s stdin config; the test asserts no Authorization in argv.
- `scripts/audit-dev-scheduled-shapes.sh` + `.test.sh` — 32/32 rows; live run
  `checked=60 ok=30 fail=0 unclassified=30`; posted to #9995. pem class
  widened to accept alphabet-clean bare key blobs (VAPID false positive).
- RED drill live: exit 1, `status=401 fp=8246898e` — fingerprint matches CI.
- mu1 workflow step runs the probe before vitest; mu1 test header + runbook
  updated to name `soleur-ci-fixture`.
- `apps/web-platform/infra/github-ci-fixture-app-manifest.json` written.
- Deferred provisioning track filed: #10058 (deferred-automation +
  ci/integration-suites + type/chore, milestone Post-MVP/Later); staged
  `bootstrap.sh` + `app-manifest-post.html` committed beside this file;
  `plugins/soleur/test/operator-agent-runnable.test.sh` green (47/47).
- Fixture ratchets green: fixture-relative-assert 62/62,
  fixture-dir-operand-assert 71/71, lint-shell-capture-exit 0 new findings.

### Decisions / drift from plan
- Inline `--header @<(...)` replaced by bearer-curl.sh `bc_curl` (ADR-280,
  merged after the plan was authored).
- Operator deferred Phase 1 provisioning (G1–G3 clicks): PR ships wiring +
  `Refs #9995`/`Tracks #10058` (not `Closes`); the mu1 leg fails fast at
  the probe until #10058 closes.
- `dev` config dead key left untouched (plan Cut List); recorded in #9995.

### Next
- push + affected-gate (test-all.sh has a registration-only edit) → review
  → QA → ship via soleur:ship.

### Review round (2026-10-11)
- P1 fixed: apply_write_doppler re-proves `installed_app` + PEM in-process —
  an empty gh read could have written empty secrets and deleted the PEM.
- P2s fixed: probe fp now hashes the EXPANDED pem (== CI pemFingerprint,
  verified against github-app.ts getPrivateKey/createHash); exp now +540
  (matches createAppJwt; +600 boundary would 401 under 1s skew); PEM tmpfs
  ordering (XDG_RUNTIME_DIR first); record-key stat is GNU-only so a
  non-Linux refusal names the platform.
- P3s: GITHUB_WORKSPACE path in workflow, audit PEMD tmpfs + newline
  normalization comment, sort -V → sort -n, -sS, dead FIXTURE_APP_CREATED
  clause removed, declared affected-paths edges for both new suites.
