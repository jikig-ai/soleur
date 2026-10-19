---
title: "fix: read the webhook-deploy token with sed instead of sourcing it as root (#9639 F5)"
date: 2026-10-19
slug: webhook-deploy-env-read-not-sourced
branch: feat-one-shot-9639-f5-webhook-env-no-source
issue: 9639
lane: single-domain
type: fix
---

# fix: read the webhook-deploy token with sed instead of sourcing it as root (#9639 F5)

PR body: `Ref #9639` and `Part of tracker #9217`. No closing keyword (F6-F8 stay open).

## Enhancement Summary

**Deepened on:** 2026-10-19
**Gates run:** 4.6 User-Brand Impact (pass), 4.7 Observability (pass; new block, `grep` verb, literal `:0`, no ssh, fits the 15s cap), 4.8 PAT-shaped variable (none), 4.9 UI wireframe (no UI surface, skipped), 4.10 Encryption Posture (no `.tf`/cloud-init/migration in Files to Edit/Create, skipped), 4.11 Guard Contract (`scripts/lint-guard-contract.py` green, adequacy read done), 4.12 Scope Check (1 unfenced section, all rows mapped/justified).
**Research agents used:** none spawned - the change is two lines in two shell scripts; every claim was verified directly (shell experiments, grep, `gh`), which is the proportionate depth for a mechanical fix with a CTO ruling already recorded.

### Key Improvements
1. Empirically verified the semantic-parity claim in BOTH dash and bash (matrix below) instead of leaning on the CTO's reasoning alone.
2. Found a lint trap: the bare `DOPPLER_TOKEN=$_t` assignment trips shellcheck SC2034 (the old `.` hid it). The plan now prescribes an explicit directive.
3. Verified every cited number, line and label live.

### New Considerations Discovered
- shellcheck SC2034 on the new assignment (Phase 3 / AC updated).
- In the dash bootstrap the assignment is inert (the token is not exported there) - this is parity with the sourcing it replaces, not a bug introduced here; a reviewer should not "fix" it with `export` (CTO ruling).

### Verified parity matrix (scratch experiment, dash and bash identical)

| Case | Old `. file` | New sed read | Parity |
|------|--------------|--------------|--------|
| Parent did not export the token | shell var set, child env count 0 | shell var set to last assignment, child env count 0 | yes |
| Parent exported `DOPPLER_TOKEN=inh`, file has token | child sees file value | child sees file value (`last`) | yes |
| Parent exported, file empty | child keeps `inh` | child keeps `inh` | yes |
| Parent exported, file missing | child keeps `inh` | child keeps `inh` | yes |
| `#DOPPLER_TOKEN=bad` comment line, duplicate keys | n/a | `^` anchor ignores the comment; `tail -n 1` takes the last | yes |
| `sh -ue` caller with the new lines inside `( set +e ... )` | n/a | still alive | safe |

## Overview

`apps/web-platform/infra/cron-egress-enforce-probe.sh` (`emit_fail`, line 74) and `apps/web-platform/infra/soleur-host-bootstrap.sh` (`_sentry_emit`, line 46) both run `. /etc/default/webhook-deploy 2>/dev/null || true` as root. cloud-init writes that file as `DOPPLER_TOKEN=..`, `DOPPLER_CONFIG_DIR=/tmp/.doppler`, `DOPPLER_ENABLE_VERSION_CHECK=false` and then `chown deploy:deploy` (cloud-init.yml:451-453), so anything the deploy user plants in it (including `set -x`, which lands after the xtrace refusal already passed) executes as root.

Fix: replace the `.` with a `sed -n` read of the `DOPPLER_TOKEN=` line, as a plain assignment, in both files. Add a fixture that proves a hostile file no longer executes, with no env-declared seam in production code.

## Research Insights

**Premise validation.** #9639 is OPEN (F5-F8 body read). Both cited lines exist on `origin/main` (`git show origin/main:.../cron-egress-enforce-probe.sh | sed -n 74p` prints the sourcing line; bootstrap line 46 read in the worktree). No open PR touches `cron-egress-enforce-probe.sh`, `soleur-host-bootstrap.sh` or `server.tf` (`gh pr list --state open --json files` filtered; empty). `cloud-init.yml`, `betterstack-logs-alerts.tf` and `apply-web-platform-infra.yml` are explicitly out of bounds (#10501/#10546/#7390). No ADR in the brief proposes a mechanism that needs ADR-corpus checking: the fix is a one-line read-vs-source swap.

**Property List.**
1. Nothing in `/etc/default/webhook-deploy` executes in the root-run emit helpers (probe `emit_fail`, bootstrap `_sentry_emit`).
2. The Doppler-token behavior of those helpers is unchanged for every well-formed file (inherited env keeps working; same token reaches `doppler`).
3. A regression to sourcing is caught by a test that does not require a production-code env seam.

**Cut List.**
- Env-declared path seam (`WEBHOOK_ENV_FILE=`) in production code -> buys property 3 -> already covered by a path-rewritten copy of the real script in the test (CTO ruling; the issue forbids the seam).
- Token charset allowlist -> would buy hardening beyond property 1 (value is only an env var, never evaluated) -> cut (CTO ruling; #9638 territory).
- `export DOPPLER_TOKEN` -> would change property 2 (makes the bootstrap Doppler fallback newly live, token in curl's env) -> cut (CTO ruling).
- Sentry-DSN curl transport hardening (#9638), F7 boot-trail event, F8 alert -> recorded-not-fixed by the brief.

**Institutional facts used.**
- Sourcing `webhook-deploy` exports nothing in dash/bash unless `set -a` is active (cloud-init.yml:349 comment, #6985; `soleur-host-bootstrap-observability.test.sh` ~938). In the probe, the cloud-init terminal block has already done `set -a; . /etc/default/webhook-deploy; set +a` (cloud-init.yml:772), so `DOPPLER_TOKEN` is exported when the probe runs. In the bootstrap (`sh "$SEED/soleur-host-bootstrap.sh"`, cloud-init.yml:557, dash, no `set -a`) the sourced token was never exported, so a plain assignment preserves behavior exactly.
- Precedent for reading rather than sourcing: `inngest-bootstrap.sh:1422` uses `grep -oP ... | head -n1`. Not reusable here: `-P` is not portable to the dash bootstrap, and `scripts/lint-shell-capture-exit.py` flags `grep` captures (S1) while `sed` is not in its list. `sed -n 's/^DOPPLER_TOKEN=//p' | tail -n 1` is POSIX and lint-clean; `tail -n 1` gives the same last-assignment-wins semantics sourcing had.
- Drift pins checked and NOT pinning the sourcing line: "Sentry TRANSPORT parity" in `cron-egress-enforce-probe.test.sh` (lines 141-147) pins only the KEY/SHOST/PROJ sed lines, the `curl -m 10 --retry 3` line and the `X-Sentry-Auth` line; `soleur-host-bootstrap-observability.test.sh` AC8c (~lines 602-620) pins the same transport constructs; its other `webhook-deploy` mentions are comments and the `EnvironmentFile=/etc/default/webhook-deploy` unit assertion (AC22). `doppler-download-error-channel.mutation.py` references `soleur-host-bootstrap.sh` but contains no `. /etc` or `_sentry_emit` pin (grep). Result: no lockstep edits to those pins are needed.
- The new line is inside `( set +e ... ) || true`, so errexit capture lints are moot; the `lint-shell-trace-credential-refusal` baselines do not list the probe (test row P-L) and the xtrace refusal is untouched.

**Prototype (scratchpad, not committed).** A path-rewritten copy of the real probe, a hostile fixture (`set -x`, `touch pwned`, `DOPPLER_TOKEN=tok123`) and PATH stubs for docker/sleep/doppler/curl reproduced the bug on the unfixed line (planted `pwned` file created, `+ ` xtrace lines on stderr) and showed none of it with the sed line substituted. The technique works.

## Research Reconciliation - Spec vs. Codebase

| Brief claim | Reality | Plan response |
|-------------|---------|---------------|
| "Sentry TRANSPORT parity" pin might pin the sourcing line | It pins only the KEY/SHOST/PROJ/curl/X-Sentry-Auth lines | No edit to the pin |
| Fixture "needs no env-declared seam" | The path is hardcoded in both scripts | Test rewrites the literal path in a COPY of the real script (anti-vacuity row proves the rewrite hit) |
| Both files "baked into the web image (server.tf ~173-210)" | Confirmed by the probe test's `host_script_files` row | No server.tf edit; PR lands without host replace |

## Open Code-Review Overlap

None (open `code-review` issues queried by body for the four touched paths: no match).

## Files to Edit

- `apps/web-platform/infra/cron-egress-enforce-probe.sh` - replace line 74 with the two-line sed read; refresh the header comments at ~line 40 ("the deploy-owned /etc/default/webhook-deploy it sources") and the `LIMIT:` comment at ~lines 78-79 (the planted-`set -x` hole is closed; keep the `#9639` pointer only for the still-open F6-F8 items).
- `apps/web-platform/infra/soleur-host-bootstrap.sh` - replace line 46 with the same two-line sed read (POSIX sh), same variable name; no other change. Keep the "Transport stays BYTE-IDENTICAL" comment as is.
- `apps/web-platform/infra/cron-egress-enforce-probe.test.sh` - new section "webhook-deploy is read, never sourced (#9639 F5)": static row over both scripts, anti-vacuity row, hostile-fixture rows, must-pass non-canonical fixtures, negative control; extend the existing `doppler` stub to also record `${DOPPLER_TOKEN-UNSET}` into a separate file (not the argv `calls` log, so existing `grep -c "^doppler"` counts do not move).
- `apps/web-platform/infra/soleur-host-bootstrap-observability.test.sh` - one behavioral block: extract `_sentry_emit` with awk, run it under dash with a path-rewritten fixture, hostile + negative-control + must-pass rows (CTO ruling). Leave `MIN_ASSERTIONS` as a lower bound unless the new count changes the measured green count; if it does, bump it in the same edit.

## Files to Create

- None in product code. Planning artifacts only: this plan, `knowledge-base/project/specs/feat-one-shot-9639-f5-webhook-env-no-source/tasks.md`, `.../decision-challenges.md`.

Do NOT touch: `cloud-init.yml`, `betterstack-logs-alerts.tf`, `apply-web-platform-infra.yml`, `server.tf`.

## The change (exact shape)

Probe (bash), inside `emit_fail`'s `( set +e ... )`, replacing the sourcing line:

```bash
    _t=$(sed -n 's/^DOPPLER_TOKEN=//p' /etc/default/webhook-deploy 2>/dev/null | tail -n 1)
    # shellcheck disable=SC2034  # consumed by the doppler child through the inherited env, not in this shell
    [ -z "$_t" ] || DOPPLER_TOKEN=$_t
```

Bootstrap `_sentry_emit` (POSIX sh) takes the identical lines (verified: `shellcheck -s sh` on the snippet reports only SC2034, which the directive covers). Semantics, per CTO ruling:

- Plain assignment, no `export`: an already-exported `DOPPLER_TOKEN` stays exported with the file's value (probe); an unexported one stays unexported (dash bootstrap). Same as sourcing.
- Assign only when non-empty: a missing, unreadable or token-less file leaves an inherited token untouched, as sourcing did.
- `DOPPLER_CONFIG_DIR` / `DOPPLER_ENABLE_VERSION_CHECK` are no longer re-read: in the probe they are already exported by the caller's `set -a` with identical values; in the bootstrap they were never exported. No behavior change.
- Residual (documented, not fixed): a hostile file can still set a different token string, redirecting which Doppler scope answers the DSN lookup. No code execution; any exfil is limited to the Sentry transport (#9638, recorded-not-fixed).

## Implementation Phases

### Phase 1 - Tests first (RED), `cron-egress-enforce-probe.test.sh`

Write the rows below before touching the scripts; run the suite and confirm the hostile and static rows are RED on the unfixed tree.

1. Stub change: `doppler` stub additionally appends `${DOPPLER_TOKEN-UNSET}` to `$STUBS/doppler-tok`.
2. Helper `make_probe_copy <fixture-path> <out>`: `sed "s#/etc/default/webhook-deploy#<fixture>#g" "$PROBE" > <out>`; anti-vacuity: require the copy contains the fixture path and no longer contains the literal `/etc/default/webhook-deploy` on a code line (fail the whole block loudly if not, so a rewrite miss cannot pass by reading a non-existent real file).
3. `run_probe_copy` drives the copy down the `container_absent` branch (`STUB_PS_NAMES=other`, `sleep` stub already instant) so `emit_fail` fires; env includes `DOPPLER_TOKEN=inherited-tok` exported.
4. Rows:
   - F5-S1 static (both files): comment-stripped code lines contain no `.`/`source` of `webhook-deploy` (regex `(^|[;&|[:space:]])(\.|source)[[:space:]]+[^#]*webhook-deploy`), plus non-vacuity (extraction non-empty; each file contains the `sed -n 's/^DOPPLER_TOKEN=//p'` read).
   - F5-H1 hostile fixture (`set -x`, `touch $STUBS/pwned`, `DOPPLER_TOKEN=tok123`, plus an `echo` of a marker): rc 1, `container-absent` named, `pwned` absent, no stderr line starting `+`, no marker, and the doppler stub saw `tok123` (assignment from the file value, still exported because inherited).
   - F5-H2 negative control: a second copy where the two sed lines are replaced by `. <fixture>` (assert the substitution hit); the same hostile fixture MUST create `pwned` and emit `+` lines. This is the row that proves the harness can see the defect.
   - F5-P1 must-pass non-canonical fixture (not the canonical cloud-init file): extra unrelated lines, a `#DOPPLER_TOKEN=commented` line before the real one, the real key after other keys, and a duplicate key (last wins); the stub sees the last real value.
   - F5-P2 empty/absent fixture: the stub sees `inherited-tok` (assign-only-when-non-empty).
   - F5-P3 no-export parity: run without `DOPPLER_TOKEN` in the environment against the canonical fixture; the stub sees `UNSET` (plain assignment, not exported).
5. Anti-vacuity floor: leave `MIN_CASES=65` (lower bound; the measured count only rises).

### Phase 2 - Bootstrap behavioral block, `soleur-host-bootstrap-observability.test.sh`

Extract `_sentry_emit` with `awk '/^_sentry_emit\(\)/{f=1} f{print} f&&/^}/{exit}'` (assert non-empty), rewrite the path, run under `dash` (`command -v dash`, else `sh`) with stub `doppler`/`curl` and `SOLEUR_SENTRY_DSN` unset so the Doppler fallback runs. Rows: hostile fixture no execution; negative control (`. fixture` form) executes; canonical fixture does not export the token in dash (stub sees `UNSET`) - the parity row. If extraction proves brittle, ship the static row (Phase 1, F5-S1 already covers the bootstrap) and file a follow-up (weaker; CTO-noted).

### Phase 3 - GREEN: edit both scripts

Apply the two-line read; refresh the stale comments in the probe. Run both suites, `bash -n` both scripts, `shellcheck` both (the repo runs it in CI; the new bare assignment needs the SC2034 directive shown above or it goes red), and `dash -n` on the bootstrap.

### Phase 4 - Sweep and wrap

- `git grep -n "\. /etc/default/webhook-deploy" -- apps/web-platform/infra` to confirm the only remaining root-sourcing is the cloud-init terminal block (intentional `set -a` export; out of bounds under #10501).
- Create a tracking issue for that remaining site (same class, needs `set -a` semantics and a `cloud-init.yml` edit, blocked on #10501), milestone from `knowledge-base/product/roadmap.md`, label `deferred-scope-out`, per `wg-when-deferring-a-capability-create-a`.
- Run the touched suites plus `bash apps/web-platform/infra/cron-egress-firewall.test.sh` and `cloud-init-web-zot-seed.test.sh` (both mention `webhook-deploy`) to confirm nothing else pinned the lines.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "read the one token with `sed -n` instead of sourcing" [brief] | The change; Phase 3 probe edit | mapped |
| 2 | "fix it the same way in this PR" (`soleur-host-bootstrap.sh` `_sentry_emit`) [brief] | Phase 3 bootstrap edit | mapped |
| 3 | "Add a test fixture row that needs no env-declared seam" [brief] | Phase 1 rows (path-rewritten copy) | mapped |
| 4 | "Check that the \"Sentry TRANSPORT parity\" byte-identical pin ... do not pin the sourcing line; if they do, update them in lockstep" [brief] | Research Insights (checked: not pinned; no edit) | mapped |
| 5 | "do NOT touch cloud-init.yml ..., betterstack-logs-alerts.tf or apply-web-platform-infra.yml" [brief] | Files to Edit "Do NOT touch" | mapped |
| 6 | "do NOT harden the Sentry-DSN curl transport ... and do NOT add the F7 boot-trail event or F8 alert" [brief] | Cut List; residual note | mapped |
| 7 | "PR body uses \"Ref #9639\" and \"Part of tracker #9217\", NOT a closing keyword" [brief] | Plan header; Acceptance Criteria | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Probe edit | "read the one token with `sed -n` instead of sourcing" | asked |
| Bootstrap edit | "fix it the same way in this PR" | asked |
| Probe test rows (Phase 1) | "Add a test fixture row that needs no env-declared seam" | asked |
| Static row over both files | asks 2-3 | inferred - justification: the bootstrap is covered by the same row so the two copies cannot drift apart without a RED, which is what the "same way" ask requires to stay true |
| Bootstrap behavioral block (Phase 2) | - | inferred - justification: CTO ruling 2026-10-19 (decision-challenges.md); the static row cannot observe the dash/`sh` path where nothing is exported |
| Comment refresh in probe | - | inferred - justification: the `LIMIT:` comment names the hole this PR closes; leaving it makes the file lie |
| Tracking issue for the remaining cloud-init sourcing site | - | inferred - justification: `wg-when-deferring-a-capability-create-a`; an untracked deferral is invisible |

### Split Assessment

- Subsystems touched: 1 - apps/web-platform/infra
- Planned files: 4 | Estimated changed lines: ~150 (mostly test rows)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## User-Brand Impact

- **If this lands broken, the user experiences:** a fresh web host whose fallback Sentry emit loses its Doppler token (no SSH-free failure signal on a fail-closed boot) - no user-facing page changes; running hosts are unaffected (`ignore_changes=[user_data]`, no host replace).
- **If this leaks, the user's workflow is exposed via:** the status quo being fixed - a deploy-user-planted line in `/etc/default/webhook-deploy` running as root on a fresh host during boot; the fix removes that path, it adds none.
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** the exploit needs a prior deploy-user compromise on a fresh host and the change cannot expose user data by itself, so it is not a single-user incident; it is one privilege-boundary item in the #9217 hardening series.

## Observability

```yaml
liveness_signal:
  what: the existing Sentry "soleur egress-enforce probe failed" / "soleur-host-bootstrap failed" fatal events keep firing on failure; no new signal is added (F7/F8 are recorded-not-fixed)
  cadence: per fresh-host boot failure
  alert_target: Sentry web-platform project (existing)
  configured_in: apps/web-platform/infra/cron-egress-enforce-probe.sh emit_fail and apps/web-platform/infra/soleur-host-bootstrap.sh _sentry_emit
error_reporting:
  destination: Sentry via the DSN from SOLEUR_SENTRY_DSN (bootstrap) or doppler secrets get SENTRY_DSN (both) - unchanged
  fail_loud: the emit is best-effort by design (fail-open subshell); the regression guard is the test suite, which exits 1 on any failed row
failure_modes:
  - mode: a future edit re-introduces `. /etc/default/webhook-deploy` in either helper
    detection: cron-egress-enforce-probe.test.sh static row F5-S1 and hostile-fixture rows go RED in infra-validation CI
    alert_route: PR check failure
  - mode: the sed read returns empty on a well-formed file (token lost, fallback DSN lookup silently dead)
    detection: rows F5-H1 and F5-P1 assert the doppler stub received the file's token
    alert_route: PR check failure
logs:
  where: PR CI log for infra-validation; on a host, cloud-init output (unchanged)
  retention: GitHub Actions default
discoverability_test:
  command: grep -cE '^[[:space:]]*\. /etc/default/webhook-deploy' apps/web-platform/infra/cron-egress-enforce-probe.sh apps/web-platform/infra/soleur-host-bootstrap.sh
  expected_output: ":0"
```

## Guard Contract

### Guard 1 - webhook-deploy is never sourced by a root-run emit helper

**Property.** No code line in the two root-run emit helpers (probe `emit_fail`, bootstrap `_sentry_emit`) executes the contents of `/etc/default/webhook-deploy`.

**Assembly.** Quantifies over both files in full, every code line (comments stripped), every sourcing spelling (`.`, `source`, mid-line after `;`/`&&`), not only the line currently at 74/46. The chokepoint is the file read: the only permitted read of that path in these two files is the `sed -n 's/^DOPPLER_TOKEN=//p'` form. The cloud-init terminal block's `set -a; . /etc/default/webhook-deploy` is out of this guard's assembly by design (different file, owned by #10501) and is tracked separately.

**Mutation matrix.**

| # | Edit | Must go RED |
|---|------|-------------|
| 1 | Restore `. /etc/default/webhook-deploy` in the probe's `emit_fail` | F5-S1 (probe) and F5-H1 (planted `pwned`) |
| 2 | Add `source /etc/default/webhook-deploy` to the bootstrap AFTER the compliant probe, as a second member | F5-S1 (bootstrap) and the Phase 2 bootstrap hostile row; a check that stopped at the first file would stay green |
| 3 | Add a second sourcing line elsewhere in the probe (outside `emit_fail`) | F5-S1 (scans all code lines, not one function) |
| 4 | Change the probe's path spelling so the test's path rewrite misses (guard's own dispatch) | the rewrite anti-vacuity row (the suite must not report green over a copy that still reads the real path) |
| 5 | Drop the `[ -z "$_t" ] ||` guard so an empty read blanks an inherited token | F5-P2 (inherited token must survive) |
| 6 | Add `export` to the assignment | F5-P3 (token must stay unexported in the no-inherit run) |

**Harness rows.** Edit to the suite: delete the negative-control substitution so the legacy variant equals the fixed script - F5-H2 must go RED (a control that cannot reproduce the defect proves nothing). Must-PASS input that is not the canonical file: F5-P1 (comment line, reordered keys, extra keys, duplicate key; last wins).

**Anchor.** The guard compares behavior (planted write absent), not a stored value; no stored hash or count is relied on beyond the existing `MIN_CASES` floor, which is a lower bound paired with the per-row assertions.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `bash apps/web-platform/infra/cron-egress-enforce-probe.test.sh` exits 0 and its new rows (F5-S1, F5-H1, F5-H2, F5-P1, F5-P2, F5-P3) all ran (assertion count above the previous green count).
- [ ] `bash apps/web-platform/infra/soleur-host-bootstrap-observability.test.sh` exits 0 with the new dash block present.
- [ ] Unfixed-tree run: with the two scripts restored to `origin/main`, F5-S1 and F5-H1 are RED (recorded in the PR body, from the Phase 1 RED run).
- [ ] `grep -cE '^[[:space:]]*\. /etc/default/webhook-deploy' apps/web-platform/infra/cron-egress-enforce-probe.sh apps/web-platform/infra/soleur-host-bootstrap.sh` prints `:0` for both files.
- [ ] `git diff origin/main --stat` lists only the 4 infra files above plus plan/spec artifacts: no `cloud-init.yml`, `betterstack-logs-alerts.tf`, `apply-web-platform-infra.yml`, `server.tf`.
- [ ] The "Sentry TRANSPORT parity" block and AC8c still pass unchanged (transport lines untouched).
- [ ] `bash -n`, `dash -n` (bootstrap) and `shellcheck` (no new SC2034) clean on both scripts.
- [ ] PR body carries `Ref #9639` and `Part of tracker #9217` and no closing keyword; the decision-challenges rows are rendered by ship.
- [ ] Tracking issue exists for the remaining cloud-init terminal-block sourcing site, linked from the PR body.

### Post-merge

- None. No terraform apply, no host replace (`ignore_changes=[user_data]`); the baked scripts reach hosts only on the next fresh-host boot from the new image.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected - infrastructure/tooling hardening of two baked boot scripts; no user-facing surface, no new vendor, store or connection.

## Test Scenarios

1. Hostile file with `set -x` + planted write + token: no execution, no trace, token delivered to `doppler`.
2. Same file against the `. fixture` control: planted write appears (harness can see the bug).
3. Well-formed but non-canonical file (comments, reordering, duplicates): last real token wins.
4. Missing/empty file: inherited token untouched.
5. Dash bootstrap: token is not exported to children (behavior parity).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or placeholder fails `deepen-plan` Phase 4.6; this one carries a concrete threshold.
- The path-rewrite fixture is only meaningful if the rewrite is proven to hit; the anti-vacuity row is mandatory, not optional.
- Do not "fix" the parity-pinned transport lines while editing nearby: the `KEY=`/`SHOST=`/`PROJ=`/`curl` lines must stay byte-identical between the two scripts and in the baked `soleur-boot-emit` copy.
- The two-line read is inert in the dash bootstrap when the parent did not export the token (verified; same as the sourcing it replaces). Reviewers may call it dead code; the answer is parity, not `export`.
- Do not add `export`: it silently makes the bootstrap Doppler fallback live, a behavior change outside F5.
- `sed -n 's/^DOPPLER_TOKEN=//p'` keeps any trailing `\r` or quotes the file might carry; the writer (`printf 'DOPPLER_TOKEN=%s\n'`) never adds them, and sourcing would have stripped quotes - noted as an accepted divergence for a hostile/hand-edited file only.
