---
title: "fix(infra): egress-enforce probe mints empty session-token file — every fresh host dies at gw_allow_fail"
type: fix
date: 2026-10-27
slug: fix-egress-probe-token-mint
branch: feat-one-shot-11361-egress-probe-token-mint
issue: 11361
closes: 11361
priority: p1-high
domain: infra
brand_survival_threshold: none
lane: cross-domain
---

# fix(infra): egress-enforce probe mints empty session-token file — every fresh host dies at gw_allow_fail

## Overview

The fresh-host boot probe `apps/web-platform/infra/cron-egress-enforce-probe.sh` mints its Squid session token as an empty file (`: > "$GW_TOKEN_DIR/$GW_TOK"` at line 190), but the Squid basic-auth helper `apps/web-platform/infra/egress-auth-helper.sh` answers `OK` only when the token file's content equals the presented username (`probe`). Every fresh web host therefore fails the gateway allow leg with `probe_result=gw_allow_fail` and `poweroff -f`s at boot, so `web-host-replace` can never produce a live host — it blocked #11321 step O2 on 2026-10-27 (Sentry `bc89e3dca1454a13a752566efcadd611`, dispatch 40573930081). The sibling `cron-egress-resolve.sh` mints `printf 'probe' > …` and runs green on web-1 every 5 minutes. The fix is byte-parity at the one mint site plus a stub-level test that pins minted-content == presented-username — the contract the deploy gate shipped unexercised.

## Problem Statement / Motivation

`web-host-replace` dispatch 40573930081 produced a web-2 that booted dark: `stage=egress_enforce_probe rc=1` → `poweroff -f`, Sentry tag `probe_result=gw_allow_fail`. The defect is deterministic, not environmental:

- **Mint site** (`cron-egress-enforce-probe.sh:190`): `if ! : > "$GW_TOKEN_DIR/$GW_TOK" 2>/dev/null; then` — creates an **empty** file.
- **Auth contract** (`egress-auth-helper.sh:25`): `[[ "$pass" =~ ^[A-Za-z0-9_-]{16,128}$ && -f "$TOKDIR/$pass" && "$user" == "$(<"$TOKDIR/$pass")" ]]` — the file must CONTAIN the username. This is the ADR-278-documented attribution binding ("the auth helper requires the presented username to equal the token file's content").
- **Presented username** (`cron-egress-enforce-probe.sh:200,215`): `--proxy "http://probe:${GW_TOK}@${GW_IP}:8443"` — `probe`.
- Empty content ≠ `probe` → helper `ERR` → Squid `407` → `GW_CODE=407` → `probe_result=gw_allow_fail` → fail-closed poweroff.

Why it was latent: the probe runs ONLY at fresh-host cloud-init and its test stubs `docker exec`/`EGRESS_GW_TOKEN_DIR`, so the real Squid auth contract was never exercised — the deploy-gating check shipped mock-green and failed on its first real run (the `wg-dark-launch-deploy-gates` failure shape). The egress-gateway feature merged ~2026-10-12; this was the first fresh web host since.

Every fresh-host boot of any image built from current main fails this leg → `web-host-replace` cannot succeed → blocks #11321 O2 (cloudflared eMudhra migration). `app.soleur.ai` is unaffected — running hosts are not probed.

## Proposed Solution

1. **The one-line fix.** In `cron-egress-enforce-probe.sh`, change the mint from `: > "$GW_TOKEN_DIR/$GW_TOK"` to `printf 'probe' > "$GW_TOKEN_DIR/$GW_TOK"` — the sibling's exact form (`cron-egress-resolve.sh:958`), keeping the surrounding `if ! … 2>/dev/null` writability guard (printf's exit status reflects the write, so the `gw_absent`/`egress-gw-token-dir` failure arm is unchanged).
2. **The pin.** Extend `cron-egress-enforce-probe.test.sh` so the defect reds in CI, not at a real host's first boot — two layers:
   - **Behavioral (stub-level contract replication):** the docker stub's `docker exec … --proxy http://<user>:<tok>@<ip>:8443 …` arm parses the presented `user`/`tok` out of argv, reads `$EGRESS_GW_TOKEN_DIR/<tok>` at CONNECT time (the exact moment real Squid evaluates auth, before the probe's `rm -f`), and answers `407` when content ≠ user — helper-identical semantics (`$(<file)` comparison). Under the shipped defect the healthy `run_probe --` run then emits `ASSERT-FAILED: egress-gw-allow` — a faithful stub reproduction of `gw_allow_fail`.
   - **Static (syntax pins, `cq-assert-anchor-not-bare-token`):** `assert_grep` on `$PROBE` for the mint syntax `printf 'probe' > "$GW_TOKEN_DIR/$GW_TOK"`, `assert_not_grep` for the empty-mint shape `: > "$GW_TOKEN_DIR/$GW_TOK"`, and an anchor `assert_grep` on `egress-auth-helper.sh` for the `"$user" == "$(<"$TOKDIR/$pass")"` contract line — the authority the pin is keyed on.
3. **Follow-through enrollment.** A `scripts/followthroughs/egress-enforce-probe-11361.sh` verification closes the loop on the next real fresh-host boot: exit 0 when (a) a `web-host-replace`/`web-host-create` apply run completed `success` after merge AND (b) zero `stage=egress_enforce_probe` fatal Sentry events exist since merge; FAIL (leave tracker open, investigate) on any `gw_allow_fail`/`egress_enforce_probe` fatal event; TRANSIENT on API errors. Both `SENTRY_ACTIONS_RO_TOKEN` and `GH_TOKEN` are already wired in `scheduled-followthrough-sweeper.yml` — no new secrets.

## Technical Considerations

- **Deny leg is unaffected and its semantics are restored.** The deny CONNECT expects `rc != 0`. Under the defect it was refused by Squid auth (407 → rc≠0); post-fix it is refused by the real `egress_deny` ACL (403 → rc≠0). The leg's verdict property ("metadata CONNECT is not bypassed") holds under both, but only post-fix does it exercise the actual ACL path. The stub's deny arm (`STUB_GW_DENY_RC`) needs no auth check — both refusal modes produce the same verdict shape.
- **`$(<file)` vs byte content.** The helper reads the file via `"$(<"$TOKDIR/$pass")"`, which strips trailing newlines, so `probe\n` would also authenticate. The pin asserts byte-parity with the sibling (`printf 'probe'`, no newline) — deliberately stricter than the helper's tolerance, so any deviation is a visible, deliberate change rather than silent drift.
- **No new credentials or surfaces.** The token is a one-run random name, minted and deleted within one boot run; the minted content `probe` is the username contract, never a credential (helper header: "the username … is never a credential").
- **Deployment.** The probe rides the app image's host-scripts bundle (`Dockerfile:369` COPY + `server.tf:210` `host_script_files` + cloud-init extract → `docker cp /opt/soleur/host-scripts`). Merging `apps/web-platform/**` triggers `web-platform-release.yml` → a new image tag is built and deployed automatically. The fix reaches a fresh host on the NEXT `web-host-replace`/`web-host-create` dispatch, which pins `image_tag` — **do NOT re-dispatch against `image_tag=0.364.13`** (it bakes this defect). No workflow file changes.
- **Merging this PR mutates production** (sharp-edge §infra-diff): `apps/web-platform/**` is on `web-platform-release.yml`'s push paths, so merge IS the image-rebuild trigger. The mutation is a deploy of the corrected probe onto running hosts' script bundles (harmless mid-life — the probe only runs at fresh-host boot) plus availability to the next host birth.

## Research Insights

**Premise Validation (Phase 0.6).** Verified 2026-10-27 against origin/main:

- Issue #11361 is OPEN; its blocker target #11321 is OPEN (`action-required: execute cloudflared eMudhra prod migration`). Collision precheck flags PR #11363 — it is THIS branch's own pipeline WIP draft (empty diff), not a foreign duplicate.
- All four cited files exist on `origin/main`: `cron-egress-enforce-probe.sh`, `egress-auth-helper.sh`, `cron-egress-resolve.sh`, `cron-egress-enforce-probe.test.sh`.
- Root cause confirmed byte-for-byte: mint at `cron-egress-enforce-probe.sh:190` (`: >`), contract at `egress-auth-helper.sh:25`, working sibling at `cron-egress-resolve.sh:958` (`printf 'probe' > "$EGRESS_GW_TOKEN_DIR/$tok"`, with the explanatory comment "the file must contain "probe", an empty mint reads as a forged username").
- **Blast radius answered:** only web hosts bake the probe — `apps/web-platform/Dockerfile:369`, `apps/web-platform/infra/server.tf:210` (`host_script_files`), `apps/web-platform/infra/cloud-init.yml:821`. Repo-wide grep finds no `egress-enforce-probe`/`EGRESS_GW_TOKEN_DIR` reference in git-data, inngest, or zot-registry host definitions. No sibling landmine.
- **Mechanism vs ADR corpus:** the username==file-content contract is the documented design (ADR-278 §"Attribution binding"); the fix conforms, no ADR is reversed or extended. ADR-148 (host replace is a distinct gated dispatch) governs the post-merge deployment route; ADR-145 (host birth is a guarded capability) is consistent with the probe's fail-closed posture.

**Property List (Phase 0.6b).**

- P1 — A fresh web host's boot probe authenticates its gateway allow leg: the minted token file's content equals the presented username `probe`.
- P2 — A regression to an empty or wrong-content mint fails CI before any image bakes it — the defect must never again reach a real host to be discovered.
- P3 — The deny leg keeps its verdict property: a CONNECT to `169.254.169.254` through the proxy must exit non-zero (post-fix, via the real `egress_deny` ACL → 403).

**Cut List (Phase 0.6b).**

- Shared mint helper / `GW_USER` variable extraction → P1 — rejected (YAGNI): two call sites, a one-line contract; byte-parity + the test pin binds the contract without a third artifact to keep in delivery lockstep. The helper would also need a new `host_script_files` entry + Dockerfile COPY + bootstrap install line — machinery for a constant.
- Auth check added to the stub's deny arm → P3 — rejected: 407 and 403 both yield `rc != 0`; the deny verdict cannot distinguish them and does not need to.
- Workflow/`server.tf`/cloud-init changes → none — rejected: the probe already rides the image bundle; delivery is unchanged.

**Relevant file paths.**

- `apps/web-platform/infra/cron-egress-enforce-probe.sh:189-217` — token mint (190), allow leg (199-209), deny leg (213-223), cleanup `rm -f` (204, 217).
- `apps/web-platform/infra/egress-auth-helper.sh:25` — the auth contract the mint must satisfy.
- `apps/web-platform/infra/cron-egress-resolve.sh:957-958` — the correct sibling mint + its explanatory comment.
- `apps/web-platform/infra/cron-egress-enforce-probe.test.sh:221-237` — the docker stub to extend (proxy arm at 225), `run_probe` harness (242-255), `check()` rows, `MIN_CASES=103` floor (536).
- `apps/web-platform/infra/cron-egress-firewall.test.sh:~1820-1827` — precedent: the sibling's mint is already grep-pinned (`printf 'probe' >` + `assert_not_grep ': > "\$EGRESS_GW_TOKEN_DIR/\$tok"'`) — scoped to `$RESOLVER`, so it never covered the boot probe's differently-named variables.

**Learnings applied.**

- `wg-dark-launch-deploy-gates` failure shape (this defect IS an instance): a deploy-gating check shipped mock-green because its stub never modeled the real auth contract — the fix's test replicates the contract inside the stub.
- Guard-discipline conventions from this repo's test corpus: `_selftest` instrument checks, non-vacuity controls, accounting identity, `MIN_CASES` floor — the new rows follow the file's own `check()` idiom.
- Sharp-edges consulted (full catalogue read): §"run every prescribed command once" (suite timed at 5.6s, prints `0 failed`), §"discoverability command must survive Check 10's shell-active reject" (single-word command, no shell metacharacters), §"AC split pre/post-merge when post-merge operator actions exist", §"follow-through closing on absence needs proof the party can produce the signal" (the enrollment requires a real post-merge birth, not just zero failures).

**Conventions.** `*.test.sh` bash suites run via `bash <path>` and register in `infra-validation.yml`; new rows use the file's `check "id description" 'condition'` idiom; row ids follow the file's `P<N>-<row>` naming.

**Related issues/PRs.** #11361 (this fix), #11321 (blocked migration, step O2), #9534 (egress gateway), #5933 (fresh-host probe provenance), #9639 (F5/F7 probe hardening precedent), ADR-278, ADR-148, ADR-145.

**Agent fan-out note.** This run executed inside a Devin one-shot subagent without a Task-spawning tool; the Phase 1 local-research and Phase 2.5 domain-lead fan-outs were performed inline by the planning orchestrator (same greps and file reads the agents prescribe, recorded above), and the plan-review panel was applied as a single-pass self-review against the same checklists. Community-discovery was skipped (no uncovered stacks — no flutter/rust/elixir/go/swift/kotlin/php signatures); functional-overlap was assessed inline (a one-line internal host-script fix has no community-artifact analogue; discovery must never block planning).

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` (99 issues) bodies contain none of the planned paths (`cron-egress-enforce-probe.sh`, `cron-egress-enforce-probe.test.sh`, `egress-auth-helper.sh`, `cron-egress-resolve.sh`, `scripts/followthroughs/egress-enforce-probe-11361.sh`).

## User-Brand Impact

- **If this lands broken, the user experiences:** no user-facing artifact — the failure mode is a fresh web host powering off during a `web-host-replace`/`web-host-create` dispatch (an internal ops path); `app.soleur.ai` keeps serving from existing hosts. The indirect exposure is delayed host replacement if a serving host is lost.
- **If this leaks, the user's [data / workflow / money] is exposed via:** nothing new — the minted token is a one-run random name written and deleted inside a boot run, and its content `probe` is the documented username contract, not a credential.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** the diff touches a deploy-gating host script but the failure direction is fail-closed host-absence on an ops dispatch path, not a user-facing defect or data exposure — `none`, not `single-user incident`.

`threshold: none, reason: touches apps/web-platform/infra/ (sensitive-path regex) but the changed surface is an internal boot-probe token mint whose failure aborts an ops host birth — no user-facing artifact and no credential-bearing data`

## Observability

```yaml
liveness_signal:
  what: "egress_gw_probe result=ok heartbeat rows emitted by cron-egress-resolve.sh per live web host; fresh-host boot stages via soleur-boot-emit"
  cadence: "every 300s per host (EGRESS_GW_PROBE_INTERVAL); the enforce probe runs once per fresh-host boot"
  alert_target: "Better Stack absence alert on the egress-gw-probe tag; Sentry fatal event on stage=egress_enforce_probe"
  configured_in: "apps/web-platform/infra/cron-egress-resolve.sh (probe_emit + logger -t egress-gw-probe); apps/web-platform/infra/betterstack-logs-alerts.tf"

error_reporting:
  destination: "Sentry web-platform via SENTRY_DSN (emit_fail envelope with stage/failed_file/host_id/probe_result tags)"
  fail_loud: "Sentry event 'soleur egress-enforce probe failed' tagged stage=egress-enforce probe_result=gw_allow_fail; soleur-boot-emit egress_enforce_probe fatal; fail-closed poweroff"

failure_modes:
  - mode: "minted content != presented username (this defect)"
    detection: "in-surface CI: the docker stub's proxy arm replicates the helper auth contract (content == user) so an empty/wrong mint reds the suite at bake time; on-host: probe_result=gw_allow_fail Sentry tag + boot poweroff"
    alert_route: "required check infra-validation.yml; Sentry fatal + host absent pages ops"
  - mode: "deny ACL broken (metadata CONNECT reaches 169.254.169.254)"
    detection: "on-host probe_result=gw_deny_fail; suite row STUB_GW_DENY_RC=0"
    alert_route: "Sentry fatal; host poweroff"
  - mode: "gateway container or token dir absent at boot"
    detection: "probe_result=gw_absent / egress-gw-token-dir"
    alert_route: "Sentry fatal; host poweroff"

logs:
  where: "host journald — probe stdout sentinels (egress-gw-allow-ok / egress-gw-deny-ok / ASSERT-FAILED) and logger -t egress-gw-probe rows shipped via Vector to Better Stack"
  retention: "Better Stack per-source retention; journald local rotation"

discoverability_test:
  command: bash apps/web-platform/infra/cron-egress-enforce-probe.test.sh
  expected_output: "0 failed"
```

## Guard Contract

### Guard 1 — minted-content == presented-username pin

**Property.** The session-token file the boot probe mints contains exactly the username presented to Squid in both CONNECT legs (`probe`), because `egress-auth-helper.sh` authenticates only `"$user" == "$(<"$TOKDIR/$pass")"`; an empty or wrong-content mint denies every authenticated CONNECT.

**Assembly.** The single mint write to `$GW_TOKEN_DIR` in `cron-egress-enforce-probe.sh` is the chokepoint (grep `GW_TOKEN_DIR`: one mint site, two `rm -f` cleanups — every gateway-authenticated CONNECT in the script flows through that one file's content). Enforcement is the test's docker stub `--proxy` arm in `cron-egress-enforce-probe.test.sh` — the only site where stub argv reaches the token dir — plus static `assert_grep`/`assert_not_grep` pins on the mint syntax and on the helper's contract line.

**Anchor.** `egress-auth-helper.sh`'s `"$user" == "$(<"$TOKDIR/$pass")"` comparison is the contract authority: a consistent weakening of helper + probe in one diff is caught by the pin on the helper line; the mint pin alone cannot see it.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Restore `: > "$GW_TOKEN_DIR/$GW_TOK"` (the shipped defect — empty file) | RED — healthy `run_probe --` emits `ASSERT-FAILED: egress-gw-allow` (stub answers 407 on empty content) |
| 2 | Mint `printf 'root' > "$GW_TOKEN_DIR/$GW_TOK"` (valid file, wrong identity) | RED — content ≠ presented user → allow leg fails |
| 3 | Append a second write `: > "$GW_TOKEN_DIR/$GW_TOK"` after the compliant mint (two members, last write wins) | RED — the stub reads file content at CONNECT time, after the second write |
| 4 | Stub's proxy arm returns 200 without reading the token dir (guard's own dispatch blind — auth never evaluated) | RED — the row asserting the stub recorded an auth verdict / read the minted file fails |
| 5 | Assertion greps the suite's call log for an auth-verdict marker the stub never emits (harness keyed on a dead channel) | RED — non-vacuity row on the stub's emitted verdict field |
| 6 | `STUB_GW_ALLOW_CODE=503` (must-PASS path: injected upstream failure, auth valid) | PASS — the STUB override still drives `gw_allow_fail` through the non-auth path, so the contract arm does not swallow unrelated 5xx verdicts |
| 7 | Token filename differs per run (random `GW_TOK`) — property binds content, not name | PASS — the stub parses the token name out of argv each run |

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "`printf 'probe' > "$GW_TOKEN_DIR/$GW_TOK"` (byte-parity with cron-egress-resolve.sh — `$(<file)` strips trailing newlines; use the sibling's exact form)" [issue #11361] | Files-to-Edit `cron-egress-enforce-probe.sh` / Phase 1 | mapped |
| 2 | "a test that pins minted-content == presented username (a stub-level assertion that would have caught this — the minted file's bytes must equal `probe`). Mutation-test the assertion." [issue #11361] | Files-to-Edit `cron-egress-enforce-probe.test.sh` / Phase 2-3 / Guard Contract | mapped |
| 3 | "check whether the registry/git-data/inngest host bundles bake the same probe — same latent landmine on their next replace" [issue #11361] | Research Insights blast-radius finding + AC6 | mapped |
| 4 | "do NOT re-dispatch `web-host-replace` against `image_tag=0.364.13`; it bakes this defect" [issue #11361] | Deployment note + post-merge AC8 | mapped |
| 5 | "check the probe's deny leg still behaves (it expects rc!=0; a valid-auth CONNECT to 169.254.169.254 must hit the Squid egress_deny ACL → 403)" [brief] | Technical Considerations deny-leg note + test scenario | mapped |
| 6 | "anchored on syntax not a bare token" [brief] | Static pin design (assert_grep on mint syntax + helper contract line) | mapped |
| 7 | "deployment note only; no workflow changes needed" [brief] | Non-goal (no `.github/workflows/` edits) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `cron-egress-enforce-probe.sh` mint edit | "`printf 'probe' > "$GW_TOKEN_DIR/$GW_TOK"`" | asked |
| `cron-egress-enforce-probe.test.sh` stub/row edits | "a test that pins minted-content == presented username … Mutation-test the assertion." | asked |
| `scripts/followthroughs/egress-enforce-probe-11361.sh` + tracker directive | — | inferred — justification: the defect shipped mock-green and failed on its first real run; plan Phase 2.9.1 requires enrollment once a post-deploy close criterion exists, and the fix's only real-world proof is the next fresh-host boot |

### Split Assessment

- Subsystems touched: 2 — `apps/web-platform` (infra probe + test), `scripts` (followthrough)
- Planned files: 3 | Estimated changed lines: ~70
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1.** `grep -nE 'printf .probe. > "\$GW_TOKEN_DIR/\$GW_TOK"' apps/web-platform/infra/cron-egress-enforce-probe.sh` returns ≥1 line, and `grep -cE ': > "\$GW_TOKEN_DIR/\$GW_TOK"' apps/web-platform/infra/cron-egress-enforce-probe.sh` returns `0` — the mint is byte-parity with `cron-egress-resolve.sh:958`.
- [ ] **AC2.** `bash apps/web-platform/infra/cron-egress-enforce-probe.test.sh` exits 0 and prints `0 failed`; the suite includes rows exercising the stub's auth-contract arm (verified by the mutation battery below, not by count alone).
- [ ] **AC3.** The docker stub's `docker exec … --proxy` arm in `cron-egress-enforce-probe.test.sh` reads `$EGRESS_GW_TOKEN_DIR/<parsed-token>` and gates CONNECT success on file content == presented username — asserted by the suite's own non-vacuity row that the stub recorded the auth verdict.
- [ ] **AC4.** Mutation battery (run at soleur:work on a scratch copy, results recorded in the PR): Guard Contract rows 1-3 each drive the suite RED naming `egress-gw-allow`; row 6 (`STUB_GW_ALLOW_CODE=503` with valid auth) still fails the allow leg (override path intact).
- [ ] **AC5.** A static pin asserts the helper's contract survives: `grep -cE '"\$user" == "\$\(<"\$TOKDIR/\$pass"\)' apps/web-platform/infra/egress-auth-helper.sh` returns ≥1 in the test file's anchor row (a consistent weakening of helper + probe reds the suite).
- [ ] **AC6.** Blast-radius answer recorded in PR body: `grep -rln 'cron-egress-enforce-probe' apps/` returns only `apps/web-platform/…` paths (verified at plan time 2026-10-27 — Dockerfile, `.dockerignore`, `infra/` scripts+tf+cloud-init, `server/egress-forwarder.ts`; registry/git-data/inngest bundles do not bake the probe).
- [ ] **AC7.** `scripts/followthroughs/egress-enforce-probe-11361.sh` exists, `bash -n` parses, carries the xtrace credential-refusal shape used by sibling followthroughs, and `bash scripts/followthroughs/egress-enforce-probe-11361.sh` exits non-zero today (no post-merge fresh-host birth yet → not-yet-verifiable, per sweeper contract).
- [ ] **AC8.** `MIN_CASES` floor in `cron-egress-enforce-probe.test.sh` is bumped by the number of added rows (anti-vacuity against row deletion).

### Post-merge (operator)

- [ ] **AC9.** Merge triggers `web-platform-release.yml` (path `apps/web-platform/**`) → new image tag; the next `apply-web-platform-infra.yml` `web-host-replace`/`web-host-create` dispatch (the #11321 O2 step) pins the NEW tag — `image_tag=0.364.13` is never re-dispatched. *Automation: not feasible for the dispatch itself — it is the prod-mutating, environment-gated authorization the operator owns (per `hr-menu-option-ack-not-prod-write-auth`); the image rebuild is already automatic on merge.*
- [ ] **AC10.** Tracker comment on #11361 carries `<!-- soleur:followthrough script=scripts/followthroughs/egress-enforce-probe-11361.sh earliest=<merge+7d> secrets=GH_TOKEN,SENTRY_ACTIONS_RO_TOKEN -->` and the `follow-through` label is applied.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change. Product/UX Gate: no UI-surface file in Files to Create/Edit → NONE.

## Test Scenarios

- **(unit)** Given the probe script with the compliant mint, when `run_probe --` executes, then the docker stub's proxy arm reads the minted file, content == `probe`, allow leg prints `200`, and the run reaches `egress-enforce-ok`.
- **(unit)** Given the mint reverted to `: >` (the shipped defect), when the suite runs on a scratch copy, then the healthy run emits `ASSERT-FAILED: egress-gw-allow` and rows red.
- **(unit)** Given mint content `root` (valid file, wrong identity), when the suite runs, then the allow leg reds the same way — the property is content == presented user, not file existence.
- **(unit)** Given a compliant mint followed by a second `: >` write, when the suite runs, then the stub still reads empty content at CONNECT time and reds (last-writer-wins).
- **(unit)** Given `STUB_GW_ALLOW_CODE=503`, when the suite runs with valid auth, then `gw_allow_fail` still fires through the injected-code path (the contract arm must not swallow non-auth failures).
- **(unit)** Given `STUB_GW_DENY_RC=0`, when the suite runs, then `ASSERT-FAILED: egress-gw-deny` fires (existing row — confirms the deny leg's discrimination is unchanged by the fix).
- **(integration)** Given a post-merge `web-host-replace`/`web-host-create` run, when the new host boots, then it emits `egress_gw_probe result=ok` rows and zero `stage=egress_enforce_probe` fatal Sentry events — verified by `scripts/followthroughs/egress-enforce-probe-11361.sh` under the sweeper (not by this PR's CI).

## Implementation Phases

- **Phase 1 — RED first (`cq-write-failing-tests-before`).** Extend `cron-egress-enforce-probe.test.sh`: docker stub proxy arm (parse `--proxy http://<user>:<tok>@`, read `$EGRESS_GW_TOKEN_DIR/<tok>` content, answer 407 on mismatch; log the observed verdict for the non-vacuity row), new `check()` rows (auth-contract rows, second-write row, static mint pins, helper-contract anchor pin), `MIN_CASES` bump. Run the suite — the defect-minted empty file must red it (`ASSERT-FAILED: egress-gw-allow`).
- **Phase 2 — GREEN.** Apply the one-line mint fix in `cron-egress-enforce-probe.sh` (`printf 'probe' > "$GW_TOKEN_DIR/$GW_TOK"`). Suite goes green.
- **Phase 3 — Mutation battery.** On scratch copies apply Guard Contract rows 1-3, confirm each reds naming `egress-gw-allow`; confirm row 6 passes. Record results for the PR body.
- **Phase 4 — Follow-through.** Write `scripts/followthroughs/egress-enforce-probe-11361.sh` (Sentry query for `stage=egress_enforce_probe` fatal events + `gh run list` birth evidence, exit semantics per sweeper contract, xtrace credential refusal). Post the tracker directive + `follow-through` label on #11361 (via ship phase or inline post-merge).
- **Phase 5 — Deployment (operator).** Merge → new image tag via `web-platform-release.yml` → next `web-host-replace`/`web-host-create` dispatch under #11321 O2 pins the new tag (never `0.364.13`).

## Files to Edit

- `apps/web-platform/infra/cron-egress-enforce-probe.sh` — line 190, the one-line mint fix.
- `apps/web-platform/infra/cron-egress-enforce-probe.test.sh` — docker stub `--proxy` auth-contract arm + ~6-10 new `check()` rows + static mint pins + `MIN_CASES` bump (~15-30 lines).

## Files to Create

- `scripts/followthroughs/egress-enforce-probe-11361.sh` — post-deploy verification probe (exit 0 only when a real post-merge fresh-host birth produced zero `egress_enforce_probe` fatal events).
- `knowledge-base/project/specs/feat-one-shot-11361-egress-probe-token-mint/tasks.md` — planning artifact (generated with this plan).
- `knowledge-base/project/specs/feat-one-shot-11361-egress-probe-token-mint/decision-challenges.md` — planning artifact (technical rulings).

## Enhancement Summary

Deepen-pass (`soleur:deepen-plan`, 2026-10-27, executed inline — this run has no Task-spawning tool; the per-section research and review-agent fan-outs were folded into a single orchestrator pass over the same greps and gate checks):

**Halt gates evaluated:** 4.4 precedent-diff — PASSED via byte-level sibling precedent (`cron-egress-resolve.sh:958` mint + `cron-egress-firewall.test.sh` mint pins adopted verbatim, not invented); 4.45 verify-the-negative — all three negative claims grep-verified ("no user-facing artifact", "never a credential" per helper header, "no other host bundle bakes the probe" per `grep -rln 'cron-egress-enforce-probe' apps/`); 4.5 network-outage — evaluated, does not fire (trigger tokens appear only outside Overview/Problem — filename `cron-egress-firewall.test.sh` and the `503` test knob; the root cause is deterministic L7 auth since Squid answered 407, which itself proves L3 allow-list, L3 routing, and L7 TLS all worked); 4.55 downtime — does not fire (no serving-surface operation; the change lands on hosts that do not run the probe mid-life); 4.6 User-Brand — PASSED (threshold `none` + sensitive-path scope-out line present); 4.7 Observability — PASSED (5 fields non-placeholder; `discoverability_test.command` = `bash apps/web-platform/infra/cron-egress-enforce-probe.test.sh`, allowlisted verb, measured 5.6s < 15s cap, literal expected_output `0 failed`); 4.8 PAT — PASSED (no PAT-shaped tokens); 4.9 UI-wireframe — skipped (no UI surface); 4.10 encryption — skipped (no new store/connection); 4.11 Guard Contract — PASSED (`scripts/lint-guard-contract.py` green: 1 entry, ≥3-row matrix; assembly is structural — the single mint write is the chokepoint all gateway-authenticated CONNECTs flow through); 4.12 Scope Check — PASSED (one live section, all asks quoted verbatim from #11361 + brief, one `inferred` row justified); 4.13 task-design — skipped (followthrough script rides the existing sweeper — no new scheduler surface).

**Key improvements folded in by the deepen pass:** the stub-contract design was sharpened to observe the file *at CONNECT time* (before the probe's `rm -f`), since a post-run assertion can never see the minted bytes; the deny-leg semantic restoration (403 real-ACL vs 407 auth-refusal) was recorded as an explicit technical consideration; the follow-through was shaped to require positive birth evidence rather than absence-of-failures alone (a zero count on a never-replaced fleet would be certain-but-meaningless).

**New considerations discovered:** none blocking — blast radius confirmed web-hosts-only at plan time; the only post-merge step is the operator's already-gated #11321 O2 re-dispatch pinned to the new image tag.

## Success Metrics

- `bash apps/web-platform/infra/cron-egress-enforce-probe.test.sh` → `0 failed` with the defect-mutation battery demonstrably red on scratch copies.
- Next `web-host-replace`/`web-host-create` dispatch on the new image produces a host that reaches `egress-enforce-ok` (no `stage=egress_enforce_probe` fatal event; host stays up) — verified by the follow-through probe, closing the enrollment on #11361.
- #11321 O2 unblocked.

## Dependencies & Risks

- **Risk: deny-leg semantic change.** Post-fix the deny CONNECT reaches the real `egress_deny` ACL (403) instead of auth refusal (407) — both `rc != 0`, so the verdict shape is identical and the change is the intended semantics.
- **Risk: helper contract changes later.** Covered by the anchor pin (AC5) — a consistent helper+probe drift reds the suite.
- **Risk: image-tag misuse at next dispatch.** `image_tag=0.364.13` bakes the defect; the deployment note + AC9 name the pin requirement. Mitigated by the follow-through probe (a wrong-tag dispatch shows as a fresh `egress_enforce_probe` fatal event → tracker stays open and investigates).
- **Dependency:** none new — no workflow, Terraform, or Doppler changes; the follow-through uses already-wired sweeper secrets.

## References & Research

- Issue: #11361 (root-cause + fix spec), blocks #11321 O2. Sentry event `bc89e3dca1454a13a752566efcadd611`; run log `https://github.com/jikig-ai/soleur/actions/runs/40573930081`.
- `apps/web-platform/infra/cron-egress-enforce-probe.sh:190` (defect), `egress-auth-helper.sh:25` (contract), `cron-egress-resolve.sh:958` (working sibling).
- `apps/web-platform/infra/cron-egress-firewall.test.sh:~1820-1827` (sibling-side mint pins precedent).
- ADR-278 (attribution binding), ADR-148 (replace dispatch), ADR-145 (guarded birth).
