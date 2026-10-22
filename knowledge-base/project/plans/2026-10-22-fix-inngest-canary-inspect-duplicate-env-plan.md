---
title: "fix: Inngest TLS canary inspect check fails on a duplicated env entry and names no cause"
type: fix
date: 2026-10-22
slug: inngest-canary-inspect-duplicate-env
branch: feat-one-shot-inngest-canary-env-dup
issue: 10136
closes: none
lane: single-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# fix: Inngest TLS canary `inspect` check fails on a duplicated env entry and names no cause

Epic #10205, item #10136, ADR-294. **Stop-before-merge pipeline:** everything below runs through review, QA and green CI;
nothing is merged, nothing is armed, the flip workflow is never run or dispatched, no Doppler or production write happens,
production is read only through Better Stack, and there is no SSH. The pipeline ends with a `Paused:` line asking for a
typed go that names the merge. The second flip is a separate owner act after merge.

## Overview

The first Inngest TLS flip (workflow run 39817708732, 16:52Z) stopped at the canary's container-level check on web-1:
Better Stack row `INNGEST_LINK: class=canary_failed level=error check=inspect cause=none`. The canary was running and had
passed its health probes; the resolver had logged `state=https_pending scheme=https`. Two defects meet here.

- **Ambiguous effective env.** `inngest_link_canary_check` (apps/web-platform/infra/ci-deploy.sh) requires exactly one
  `INNGEST_BASE_URL=` line, exactly one `INNGEST_BASE_URL=https://10.0.1.40:8443` line and exactly one
  `NODE_EXTRA_CA_CERTS=/etc/soleur/inngest-ca.pem` line in the canary's `.Config.Env`. Both `docker run` sites pass
  `--env-file "$ENV_FILE"` (the Doppler prd snapshot) and then `-e INNGEST_BASE_URL=...` / `-e NODE_EXTRA_CA_CERTS=...`.
  Docker keeps BOTH entries in `Config.Env` when a key is in the file and also passed with `-e` (verified locally by the
  requester with Docker 29.9.2), so a snapshot that still carries its pre-TLS `INNGEST_BASE_URL=http://...` line makes the
  count 2. Whether the snapshot carries it is unconfirmed (Doppler key names were not read); the plan is correct either way.
- **No diagnosis.** `cause` starts at `none` and the inspect branch never sets it, so the event names none of the three
  conditions, and a failing `docker inspect` (`|| envs=""`) is indistinguishable from a wrong count. The test mock of
  `docker inspect` builds its output from the `-e` flags only and ignores the env-file, so no test could ever show a duplicate.

**Ruled by the CTO agent (2026-10-22; rows in `knowledge-base/project/specs/feat-one-shot-inngest-canary-env-dup/decision-challenges.md`):**
scrub `INNGEST_BASE_URL` and `NODE_EXTRA_CA_CERTS` out of the env-file copy after the resolver succeeds (unconditionally, http
and https), so the `-e` flags are the only source; keep the inspect check strict; name the failed condition in the event with
fixed integers only; abort a strict (https) deploy if the scrub fails, continue a non-strict one; split the synchronous
deploy-state reason for the inspect check; amend ADR-294 in this PR.

## Research Insights

**Premise Validation (Phase 0.6).** #10136 and #10205 are both OPEN with no closing PR. Workflow run 39817708732 exists
(`Inngest Link Flip`, completed, failure). The cited symbols exist on `origin/main` at the rebased HEAD (4da1673510):
`inngest_link_canary_check`, the `--name soleur-web-platform-canary` run, the prod `docker run`, the mock `apparmor-trace` /
`MOCK_IL_CANARY` branch, `docker-run-tuple.py`. The mechanism was checked against the ADR corpus: ADR-294 states the
five-check canary layer and does not discuss env-file composition, so this is a gap in the adopted design, not a rejected
alternative. The only other open PR touching these files is #10697 (sdk-bash); edits stay in three localized places. No stale
premise found. Corrections to the brief found while reading the code: (a) a second suite,
`apps/web-platform/infra/inngest-link-resolver.test.sh`, also pins this check (stub inspect modes, rows E3/E7 asserting
`check=inspect cause=none`, mutation anchors ANCH_B1..B3, a `MIN_ROWS` floor-drift check) and changes in the same PR; (b) the
env overlay runs on `$ENV_FILE` before the resolver, so a snapshot `NODE_EXTRA_CA_CERTS` aborts the deploy with
`github_app_key_env_hijack` before any docker run (the brief said "should be impossible"; it is enforced, and a row pins it).
A read-only Better Stack query on 2026-10-22 (`betterstack-query.sh`) confirmed the ci-deploy `INNGEST_LINK:` rows are
queryable.

**Property List (Phase 0.6b).**

- P1: the canary (and prod) is handed exactly one `INNGEST_BASE_URL` and exactly one `NODE_EXTRA_CA_CERTS`, from the `-e` flags only.
- P2: a real duplicate or wrong value in the canary's `Config.Env` still fails the canary (the check stays strict).
- P3: the failure event names which condition was off, with fixed integers only; a failed `docker inspect` is `inspect_failed`, never `none`.
- P4: no key the app needs at runtime is touched, and the resolver's reads of `INNGEST_LINK_TLS` / `INNGEST_TLS_CA` still work.
- P5: the tuple census still accepts the composition, the first-boot path is undisturbed, and a scrub fault cannot block a rollback.

**Cut List (Phase 0.6b).**

- Relaxing the check to last-wins semantics: cut; the check's purpose is proving what the container was handed.
- Dropping the `-e` flags and putting the pinned values in the env-file: cut; the values would come from an untrusted snapshot.
- A live `docker inspect` of the PROD container after the swap: cut; prod gets the same scrubbed `$ENV_FILE` and the same `-e` flags (the tuple census pins them) and the mock asserts the effective env of both runs. `canary_ok` is therefore a canary-only proof and the runbook says so.
- Editing `docker-run-tuple.py` or the first-boot tuple: cut (CTO ruling); ARGV is unchanged, the first boot has no inspect check, and its duplicate is harmless.
- A new Sentry alert rule for `op=inngest-link`: cut; tracked as #10556.
- A committed red-run evidence file: cut (plan review); the red output lives in the "test: red" commit message and the PR description.
- Hardening the overlay's own `grep` (same weakness as below): cut from this PR, filed as #10855.

**Institutional learnings applied.** `knowledge-base/project/learnings/2026-06-16-infra-test-orphan-suites-and-node-options-env-file-clobber.md`
(docker resolves `-e` over `--env-file` for one key). The two suites already run under the infra-validation workflow's path filter
(`apps/*/infra/**`); no new suite is created, so no orphan risk.

**Code-review overlap (Phase 1.7.5).** `gh issue list --label code-review --state open` (200 issues) matched none of the seven planned file paths.

**Network-outage hypothesis check.** Not triggered (the failure is a count of env lines; the canary's egress checks were never reached).

## Research Reconciliation — Spec vs. Codebase

| Brief claim | Reality | Plan response |
|---|---|---|
| "No test could ever show a duplicate" (mock ignores the env-file) | True: the `inspect` branch of the `apparmor-trace` mock awks the `-e` flags of the first canary run line only | Phase 1 makes the mock env-file-aware (snapshot the env-file at run time, emit file lines then `-e`, as Docker does) |
| "Check ci-deploy.test.sh" only | A second suite pins the same check and its `cause=none` event | Both suites change; `MIN_ROWS` in inngest-link-resolver.test.sh moves in the same edit |
| "NODE_EXTRA_CA_CERTS duplicate should be impossible" | The overlay refuses any prd `NODE_*` name other than `NODE_ENV` (bare-name lines too) with `env_hijack`, before the resolver runs | Pin it: an integration row (deploy aborts, zero docker runs) plus a unit row feeding the scrub directly |
| "check docker-run-tuple.py so the tuple census still accepts the composition" | The census parses ARGV only; `--env-file "$ENV_FILE"` is unchanged by an in-place rewrite; env-file CONTENT is a stated residual in its docstring | Run `docker-run-tuple.py` and `docker-run-tuple.test.sh` as ACs; no edit |
| "the env-file is read by something else" | Readers of `$ENV_FILE`: `_cred_redact_env_values`, the `github_app_key_present "$ENV_FILE"` call, the overlay, the resolver (`INNGEST_LINK_TLS`, `INNGEST_TLS_CA`, `DOPPLER_PROJECT`, `DOPPLER_CONFIG`), both docker runs, the EXIT trap `rm -f`. Probes read `inngest-link.env`, not `$ENV_FILE` | The scrub runs AFTER the resolver and removes only the two names; the redactor loses a non-secret constant URL from its substitution set, which is harmless |

## Problem Statement / Motivation

The flip cannot get past its own canary while the snapshot carries a stale `INNGEST_BASE_URL`, and when it fails the reader
cannot tell why without the code (the row says `cause=none`). TLS verification on the Inngest link is CLO-dated (live by
2026-11-12, fallback 2026-11-19, hard stop 2026-12-10, ADR-294), so a flip that cannot start or fails opaquely burns time the dates
do not have. The canary must stay strict: it proves the container was handed the https URL and the pinned CA, and weakening it
to match a daemon's merge order would trade a visible failure for an unverified claim.

## Proposed Solution

**1. Scrub (the source of truth).** A new function `inngest_link_scrub_env_file <env-file>` inside the
`# >>> inngest-link-resolver >>>` block, called once at the deploy site directly after the `resolve_inngest_link` failure handling and
before `PROD_NODE_OPTIONS=`, on every deploy (http and https alike: one code path, so its first live use is a routine release, not the flip).

- Regex (one constant, mirroring the overlay's hijack regex so bare-name and padded lines are covered):
  `^[[:space:]]*(INNGEST_BASE_URL|NODE_EXTRA_CA_CERTS)[[:space:]]*(=|$)`. A bare-name line goes too: Docker would resolve it from the docker CLI's own environment.
- Every grep in the function runs as `LC_ALL=C grep -a` (measured by plan review: under the ambient locale `grep -v` silently drops a line with invalid UTF-8, and a NUL byte makes grep treat the file as binary and print nothing, both with rc 0).
- Order, validate before `mv` (CTO): count the matching lines `n` (rc 1 means none, rc 2+ is `stage=read`); write the non-matching lines to `_gak_tmp=$(mktemp "$1.scrub.XXXXXX")` (rc 0 or 1 accepted, 1 meaning every line matched);
  check conservation (kept lines + `n` equals the total line count, else `stage=write`); recount the target regex on the temp file, which must be 0 (else `stage=recount`); only then `mv -f` over `$1`.
  Every failure path leaves `$1` byte-identical and removes the temp file, so a continue-after-failure is exactly today's behavior.
- Contract: kept lines are byte-exact, a final newline is guaranteed (a file whose last line lacks one gains one, harmless for a Docker env-file), mode stays 0600 (mktemp).
- The temp name carries `.scrub.` (distinct from the overlay's `.gak.`) and is held in `_gak_tmp`, which the existing deploy EXIT trap already removes, so no trap edit (CTO; keeps the diff clear of #10697). A comment at the function and at the trap names the second user of the variable.
- Events: `INNGEST_LINK: class=env_scrubbed level=info removed=<n>` only when `n > 0` (a row means the Doppler snapshot carried a pinned name: the no-SSH, no-key-name answer to the unconfirmed root cause);
  `INNGEST_LINK: class=env_scrub_failed level=error stage=<read|write|recount>` on failure.
- Failure policy at the call site (CTO Q7): when `INNGEST_LINK_CA_STRICT=1` abort with `logger ... DEPLOY_ABORT ... keeping previous version`, `final_write_state 1 "inngest_env_scrub_failed"` (a fixed literal: `final_write_state` splices it into JSON unquoted) and `exit 1`, the shape of `github_app_key_merge_failed`;
  when `INNGEST_LINK_CA_STRICT=0` emit the error event and continue, so a persistent scrub fault can never block a rollback (`action=off`, revert redeploy) or a hotfix. After a strict abort the resolver has already installed the CA file and `inngest-link.env`, but the scheme and the stale-CA reset are staged and committed only after the prod container starts, the same footprint as a canary failure after install; the previous container keeps serving.

**2. Strict check, named cause.** `inngest_link_canary_check` captures the `docker inspect` return code in its own local (`irc`; the existing `rc` is the later `docker exec` accumulator and must start at 0)
and evaluates in this order, emitting the first failing condition:

| cause | condition |
|---|---|
| `inspect_failed` | `docker inspect` returned non-zero or printed nothing |
| `url_count` | lines matching `^INNGEST_BASE_URL=` is not exactly 1 |
| `url_value` | exactly one such line, but not `INNGEST_BASE_URL=https://10.0.1.40:8443` |
| `ca_count` | lines matching `^NODE_EXTRA_CA_CERTS=` is not exactly 1 |
| `ca_value` | exactly one such line, but not `NODE_EXTRA_CA_CERTS=/etc/soleur/inngest-ca.pem` |

Event: `INNGEST_LINK: class=canary_failed level=error check=inspect cause=<enum> url_lines=<n> url_https=<n> ca_lines=<n> ca_ok=<n>`,
each integer normalized with `$((10#${n:-0}))` and clamped to 99. No env value, no key beyond the two fixed names, no raw text enters the event.
The other checks' events are byte-unchanged.

**3. Synchronous reason (CTO Q6).** For `check=inspect` only, `CANARY_FAIL_REASON` becomes the fixed literal `canary_inngest_link_inspect_failed`; every other in-container check
keeps `canary_inngest_link_failed`. Chosen by a literal per branch, never interpolated from `$why` or `$cause`. The run log alone then separates "the container was handed the wrong env" (a
composition defect) from "egress, TLS or registry" (a network or CA defect). Verified at plan time: the old literal appears only in ci-deploy.sh, the two suites and the two runbooks.

**4. Runbooks and ADR.** Update canary-probe-set.md and inngest-server.md (decode with a next no-SSH read per cause, the per-host flip read, the canary-only proof limit) and add an ADR-294 addendum.

## Technical Considerations

- **Architecture impact:** one new invariant, "the `-e` flags are the only source of `INNGEST_BASE_URL` and `NODE_EXTRA_CA_CERTS`" (ADR-294 addendum). No new container, store, actor or edge.
- **Runtime effect on the app:** none expected. The daemon merges `Config.Env` last-wins when it builds the process environment (moby `ReplaceOrAppendEnvValues`, the behavior the 2026-06-16 learning records for `NODE_OPTIONS`), so the effective value was already the `-e` value; only the inspect view was ambiguous. The fix does not depend on this claim (the scrub removes the ambiguity either way); Phase 4 records the real-Docker output.
- **Padded names:** Docker's env-file parser trims leading whitespace but rejects whitespace inside a variable name (plan-review recollection, confirm in Phase 4), so `INNGEST_BASE_URL =x` fails a `docker run` today; scrubbing it turns that into a pass, which is harmless and intended.
- **Performance:** one tens-of-lines file rewrite per deploy before the first docker run.
- **Security:** the pinned values keep coming from script constants, never the snapshot; event privacy is asserted by an anchored regex test on the event line.
- **Delivery:** ci-deploy.sh reaches web-1 through the infra-config webhook (an atomic write) and web-2 through the `deploy_pipeline_fix_web2` SSH sibling (fail-closed; a plain file write that could rewrite the script under a deploy waiting in the cron drain, up to 4200 s), both fired by `apply-deploy-pipeline-fix.yml` when a merge touches the trigger files. The merge is the authorization and is not run here; the owner merges in a cron-quiet window.
- **Per-host skew:** both the old check and the old scrub-less composition live in one file, so a host is either old or new. The flip's `ok` proves web-1's canary and swap plus a 202 from web-2, so the runbook's per-host read (below) is the web-2 evidence.
- **Accepted residuals:** the first-boot tuple keeps its duplicate (no inspect check there, replaced at the next deploy); prod is not inspected live; the overlay's `grep` weakness is #10855.

## User-Brand Impact

- **If this lands broken, the user experiences:** a blocked release (a strict-path scrub fault aborts the deploy; the previous version keeps serving, so stale code, not unavailability), or, worse, a container started with an unintended Inngest URL or without the pinned CA so durable-agent sends (user prompts, task payloads) travel over the wrong link.
- **If this leaks, the user's data is exposed via:** a regression that lets a snapshot value override the pinned URL (events and the event key in the `/e/<key>` path travel over plaintext `:8288` instead of verified TLS), or an event line that echoes an env value into Better Stack or Sentry. The residual that remains by design: the canary proves what the container was handed, not that the app's send path used TLS (the post-swap `legacy_8288` counter in the soak evidence does).
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** carried from ADR-294 (the same boundary: user event payloads and the event key on the Inngest link); this change touches the code that proves that boundary.

CPO advisory at plan time (2026-10-22): sign-off yes, conditioned on the red-run evidence existing before the fix commit, the PR body not claiming TLS is verified in production, a typed go that names the merge, and a dated owner follow-through for the second flip (below). `soleur:engineering:review:user-impact-reviewer` runs at review time. The CLO posture is unchanged: ADR-294 stays `adopting` and the legal wording stays "TLS adopting".

## Architecture Decision (ADR/C4)

### ADR

Amend `knowledge-base/engineering/architecture/decisions/ADR-294-inngest-link-tls-terminator-and-flagged-flip.md` with `## Addendum (2026-10-22, #10136 canary inspect)`
(its existing addenda use the `(date, #issue)` heading form), 8 to 10 lines: the env-file handed to the canary and prod runs is scrubbed of `INNGEST_BASE_URL` and `NODE_EXTRA_CA_CERTS` after resolution so the `-e` flags are the only source; the inspect check stays strict and names its cause;
alternatives rejected (relax to last-wins: weakens the proof; pinned values via the env-file: untrusted source); status stays `adopting`. A Phase 3 task, not a follow-up issue.

### C4 views

No C4 change. Checked against all three model files (`model.c4`, `views.c4`, `spec.c4`): external human actors, none new; external systems, Doppler (`doppler -> engine "Runtime secrets"`), Better Stack and Sentry already modeled with no new edge (the events use the existing ci-deploy paths);
containers and data stores, `api` and `inngest` unchanged and no new store; actor-to-surface access relationships unchanged; derived cardinalities in edge prose untouched. Run `bash plugins/soleur/test/c4-count-parity.test.sh` at work time to confirm.

### Sequencing

The addendum describes the target state and ships in this PR.

## Infrastructure (IaC)

No new infrastructure (no resource, secret, vendor, DNS record or firewall rule); a host-resident script that the existing deploy-pipeline machinery delivers.

### Terraform changes

None. No `.tf` file is edited; `terraform_data.deploy_pipeline_fix` and its web-2 sibling re-trigger because their trigger inputs include ci-deploy.sh.

### Apply path

The existing auto-apply: `apply-deploy-pipeline-fix.yml` fires on a merge to main that touches the trigger files. Blast radius: the host script is replaced; running containers are untouched until the next deploy. Not run by this pipeline.

### Host fan-out

ci-deploy.sh is on both web hosts: web-1 by the infra-config webhook, web-2 by the SSH sibling in the same workflow, fail-closed. No host is outside the fan-out for this file.

### Distinctness / drift safeguards

Not applicable (no dev/prd value, no `ignore_changes` touched).

### Vendor-tier reality check

Not applicable.

## Implementation Phases

Run every suite one at a time with stdin from `/dev/null` (`bash <suite> < /dev/null`). Work only in this worktree; rebase on `origin/main` (never merge main in); no `git stash`.

### Phase 1 — RED first (tests before the fix)

- **1.1 Mock (ci-deploy.test.sh, the `apparmor-trace` branch of the mock docker).** On `run` (next to the existing `MOCK_IL_RUN_LOG` append) store that run's EFFECTIVE env at `${MOCK_IL_RUN_LOG}.eff<N>` (N = the run log's new line count): the `--env-file` content normalized as Docker does (drop blank and `#` lines, trim leading whitespace; a bare-name line is dropped, a documented approximation of "unset in the CLI environment") followed by the `-e` pairs in order. The `inspect` branch prints the canary's `.eff<N>` then `MOCK_IL_INSPECT_EXTRA`; `MOCK_IL_INSPECT_FAIL=1` exits 1 with no output.
- **1.2 Helpers.** `il_deploy` gains `IL_SNAP_EXTRA` (newline-separated snapshot lines) and clears `"$IL_RUNLOG".eff*` next to its `: > "$IL_RUNLOG"`; a `mktemp` shim is added to `create_base_mocks` (it execs the real binary, and fails only when `MOCK_SCRUB_MKTEMP_FAIL=1` and the template contains `.scrub.`, so the overlay's `.gak.` and the state-file templates are untouched). New `il_effective_clean <url> <ca>`: every run in the log (canary and prod) has exactly one `INNGEST_BASE_URL=` equal to `<url>` and exactly one `NODE_EXTRA_CA_CERTS=` equal to `<ca>` in its `.eff<N>`.
- **1.3 Integration rows (ci-deploy.test.sh, beside the flag-on rows).**
- **T1 (the red row, a loop over flag on and flag off).** The snapshot carries `INNGEST_BASE_URL=http://10.0.1.40:8288`: rc 0, two runs, `il_effective_clean` (https plus the CA path when on, the http literal when off), `class=env_scrubbed level=info removed=1`, the run-time env-file still holds `KEY=value`, `INNGEST_LINK_TLS` and `INNGEST_TLS_CA` lines and no pinned-name line, and (flag on) `class=canary_ok`. The canary's mocked inspect output must contain the sentinel `KEY=value` (a mock that ignored the env-file would make T1 vacuous).
- **T3 (characterization).** The snapshot carries `NODE_EXTRA_CA_CERTS=/tmp/x`: rc != 0, reason `github_app_key_env_hijack`, zero docker runs.
- **T5 (strictness kept).** Flag on, scrub in place, `MOCK_IL_INSPECT_EXTRA=INNGEST_BASE_URL=http://10.0.1.40:8288`: rc != 0, only the canary started, event contains `check=inspect cause=url_count url_lines=2 url_https=1 ca_lines=1 ca_ok=1`, deploy-state reason `canary_inngest_link_inspect_failed`; the existing negative-control and `check=health` rows keep asserting `canary_inngest_link_failed`, and one assertion shows a non-inspect failure never carries the inspect reason.
- **T6.** `MOCK_IL_INSPECT_FAIL=1`: event `check=inspect cause=inspect_failed url_lines=0 url_https=0 ca_lines=0 ca_ok=0`, and `cause=none` never appears.
- **T8a / T8b (scrub failure policy, the mktemp shim).** Flag on plus `MOCK_SCRUB_MKTEMP_FAIL=1`: rc != 0, reason `inngest_env_scrub_failed`, zero docker runs, `class=env_scrub_failed level=error stage=write`, `last-scheme` unwritten. Flag off plus the same: rc 0, two runs, the same error event, the env-file unchanged.
- **1.4 Resolver suite (inngest-link-resolver.test.sh).** Stub docker `inspect` modes: keep `https|http|noca|twice|none`; add `duphttp` (two http URL lines), `dupca` (two CA lines), `badca` (one CA line, wrong value), `empty` (rc 0, no output), `many` (150 URL lines).
- **E3** loops every failing mode. **E7**'s `check=inspect cause=none` assertion is replaced by one exact line per mode: `http` gives `cause=url_value url_lines=1 url_https=0 ca_lines=1 ca_ok=1`; `noca` gives `cause=ca_count url_lines=1 url_https=1 ca_lines=0 ca_ok=0`; `twice` gives `cause=url_count url_lines=2 url_https=1 ca_lines=1 ca_ok=1`; `duphttp` gives `cause=url_count url_lines=2 url_https=0 ca_lines=1 ca_ok=1`; `dupca` gives `cause=ca_count url_lines=1 url_https=1 ca_lines=2 ca_ok=2`; `badca` gives `cause=ca_value url_lines=1 url_https=1 ca_lines=1 ca_ok=0`; `none` and `empty` give `cause=inspect_failed` with all four counts 0; `many` gives `url_lines=99`. One more assertion: every `check=inspect` event line matches the anchored regex `check=inspect cause=(inspect_failed|url_count|url_value|ca_count|ca_value) url_lines=[0-9]{1,2} url_https=[0-9]{1,2} ca_lines=[0-9]{1,2} ca_ok=[0-9]{1,2}$` and never contains `cause=none`, an IP or a path. E3 also asserts `val reason` is `canary_inngest_link_inspect_failed` and the other rows keep `canary_inngest_link_failed` (`canary_fails` takes the expected reason as a parameter).
- **Scrub unit rows** (the function sourced from the extracted block, run on throwaway files under `$RUN`).
- **L1** removes plain, leading-space, trailing-space and bare-name lines of BOTH names, keeps every other line byte-for-byte (`INNGEST_LINK_TLS`, `INNGEST_TLS_CA`, `INNGEST_SIGNING_KEY`, `INNGEST_EVENT_KEY`, the lookalikes `INNGEST_BASE_URL_EXTRA=` and `NODE_EXTRA_CA_CERTS_X=`, a CRLF line, a line with a non-UTF-8 byte), survives a NUL byte, and keeps mode 0600.
- **L2** no-match is a no-op (kept lines identical, `removed` silent) and idempotent; a file without a trailing newline gains exactly one.
- **L3** an unreadable file gives rc 1 `stage=read`; a failing `mktemp` or `mv` stub gives `stage=write`; both leave the original byte-identical and no temp file.
- **L4** (recount) a `grep` stub that ignores `-v` gives `stage=recount`, original untouched. **L5** (conservation) a `grep` stub that drops a kept line gives `stage=write`, original untouched.
- **L6** a file containing only the two names yields an empty file and rc 0 (grep rc 1 tolerated). **L7** the wiring row: `L_SCRUB` is a unique code-line anchor (match count asserted to be 1) that sits after `resolve_inngest_link` and before the canary `docker run`.
- **Mutation and floor bookkeeping.** Update `ANCH_B1..B3` and their three `kill_mut` rows to the new check text; add the `kill_mut` rows named in the Guard Contract; append every new row id to `ROW_IDS`; raise `MIN_ROWS` by the exact number of rows added in the same edit (the suite's own floor-drift check, and `scripts/guard-vacuity-floor.test.sh`, read that literal).
- **1.5 Red run evidence step (mandatory, before any fix).** On the unmodified ci-deploy.sh, run `bash apps/web-platform/infra/ci-deploy.test.sh < /dev/null` and then `bash apps/web-platform/infra/inngest-link-resolver.test.sh < /dev/null`, one at a time.
  Required RED: ci-deploy T1 (both arms; on-code it fails with `check=inspect cause=none`), T5 (the cause text), T6, T8a, T8b; resolver E3/E7 inspect rows, L1 to L6 (function absent), the wiring row.
  Required NOT red (they prove the harness): T3, the T1 sentinel assertion. Put the FAIL lines (no env values) and the totals in the commit message of a "test: red" commit that contains only the tests, and paste them in the PR description; the fix commit cites it.
  If T1 is not red on unmodified code the premise is wrong: stop and investigate the mock before touching ci-deploy.sh (CTO: "evidence that would flip Q1").

### Phase 2 — the fix

- **2.1** ci-deploy.sh, inside the resolver markers (after `inngest_link_commit_scheme`, before the canary-check comment): the regex constant and `inngest_link_scrub_env_file`; on every failure path `rm -f` the temp file, clear `_gak_tmp`, set `INNGEST_LINK_REASON=inngest_env_scrub_failed`, return 1.
- **2.2** ci-deploy.sh, deploy site: the call plus the policy block (abort when strict, event-and-continue when not) between the resolver handling and `PROD_NODE_OPTIONS=`.
- **2.3** ci-deploy.sh, `inngest_link_canary_check`: the ordered cause evaluation with its own `irc`, the extended event, and the reason split; update the function's header comment (the "five checks" paragraph, and "Sets CANARY_FAIL_REASON (a constant ...)").
- **2.4** Run one at a time: the resolver suite, ci-deploy.test.sh (every new row green, no previously green row red, Guard 7 included), `bash apps/web-platform/infra/docker-run-tuple.test.sh`, `python3 apps/web-platform/infra/lib/docker-run-tuple.py` (repo census, exit 0), `python3 scripts/lint-trap-tempfile-ownership.py` (report the actual result; annotate the new `mktemp` with `# lint-trap-ownership: ok <reason>` only if the lint asks), `bash scripts/guard-vacuity-floor.test.sh`, `bash plugins/soleur/test/c4-count-parity.test.sh`, `bun test plugins/soleur/test/preflight-discoverability-test.test.ts` (after the ratchet bump), shellcheck as CI runs it, and the invocations `infra-validation.yml` uses for these suites.

### Phase 3 — runbooks and ADR

- **3.1 canary-probe-set.md** (Layer 5 item 1 and the failure-read paragraph): the new grammar, a compact decode (one line per cause with its next no-SSH read), the two reason literals and the defect class each means, and "`canary_ok` proves the canary only; prod evidence is the post-swap `legacy_8288` counter read".
  Decode: `inspect_failed` means the canary vanished or the daemon call failed (read the same deploy's `canary_health_failed` and `cstate` rows); `url_count` above 1 with no `class=env_scrubbed` row means a source the scrub does not cover (an image `ENV` does not duplicate, so suspect a new `-e` or a second env-file; stop and file it, do not retry);
  `url_value` means a non-https URL reached the container; `ca_count` and `ca_value` mean the CA env is absent, duplicated or different; no `canary_ok` or `canary_failed` row at all means the resolver returned `lease_expired` (http, canary skipped) or the health check failed first.
- **3.2 inngest-server.md** (the resolver event table): update the `canary_failed` row, add `env_scrubbed` (info, only when `removed>0`) and `env_scrub_failed` (error, `stage=read|write|recount`; strict deploys abort with reason `inngest_env_scrub_failed`, non-strict continue), and add the per-host flip read: for each web host, keyed on the OS `host` field (not `host_name`, which can be stale, #6616),
  read `class=resolved`, `class=canary_ok` or `class=canary_failed`, and `class=env_scrub_failed`, each `--since` the flip's T0, because `resolved` is written before the canary and proves neither `canary_ok` nor the swap. Note that no Better Stack or Vector rule keys on the event text (checked: `vector.toml` admits the `ci-deploy` tag by identifier and `betterstack-logs-alerts.tf` has no `INNGEST_LINK` match), so no allowlist change; #10556 still tracks the missing alert. No SSH step anywhere.
- **3.3** The ADR-294 addendum (above).

### Phase 4 — local real-Docker confirmation (not CI, not production)

With an image already present locally (`docker image ls`; never pull from an untrusted registry), `docker create` two throwaway containers (not started): one with `--env-file <file with INNGEST_BASE_URL=http://x> -e INNGEST_BASE_URL=https://y`, one with the scrubbed file; `docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}'` each, plus once with a padded `INNGEST_BASE_URL =x` line to record what Docker does.
Record the counts (2 then 1; no secrets) in the PR description. If the first shows 1 entry the premise is wrong (the Phase 1.5 stop rule). A green mock is a proxy for this; the PR body says so.

### Phase 5 — review, QA, CI, then stop

- **5.1** `soleur:review` (user-impact-reviewer and observability-coverage-reviewer are mandatory here), fix findings inline, `soleur:qa`, green CI.
- **5.2** `soleur:ship` up to the merge gate. **No `gh pr merge`, no auto-merge arming, no dispatch of any workflow, no Doppler or production write.**
- **5.3** The PR body states: the fix is proven by the mock and the local Docker check only; a green flip is web-1 evidence unless the per-host read shows web-2; the second flip is the owner's next act with a target date no later than 2026-11-05 on #10205.
- **5.4** The pipeline's last line is `Paused:` asking for a typed go that names the merge.

## Files to Edit

- `apps/web-platform/infra/ci-deploy.sh` (resolver block: new function; deploy site: call and policy; `inngest_link_canary_check`: cause evaluation and reason split)
- `apps/web-platform/infra/ci-deploy.test.sh` (mock docker `apparmor-trace` branch, `create_base_mocks` shim, `il_deploy` and helpers, rows T1, T3, T5, T6, T8a, T8b)
- `apps/web-platform/infra/inngest-link-resolver.test.sh` (stub inspect modes, E3/E7, scrub rows, wiring row, anchors, `kill_mut` rows, `ROW_IDS`, `MIN_ROWS`)
- `knowledge-base/engineering/operations/runbooks/canary-probe-set.md`
- `knowledge-base/engineering/operations/runbooks/inngest-server.md`
- `knowledge-base/engineering/architecture/decisions/ADR-294-inngest-link-tls-terminator-and-flagged-flip.md`
- `plugins/soleur/test/preflight-discoverability-test.test.ts` (bump `BASELINE_DECLARED_PROBES` to the live value plus one, with the PLACEMENT / TRUTH / NO-SUBSTITUTE comment entry, because this plan declares `credentials_required`; run the suite first, a sibling PR may have moved the number, it was 73 at plan time)

All seven verified to exist (`git ls-files`). No glob is prescribed. Not edited (CTO): `apps/web-platform/infra/lib/docker-run-tuple.py`, `soleur-host-bootstrap.sh`, `cloud-init.yml`, `vector.toml`, `betterstack-logs-alerts.tf`.

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-inngest-canary-env-dup/decision-challenges.md` (created at plan time)
- `knowledge-base/project/specs/feat-one-shot-inngest-canary-env-dup/tasks.md`

## Guard Contract

### Guard 1 — the strict canary inspect check (with named cause)

**Property.** The canary's `Config.Env` carries exactly one `INNGEST_BASE_URL` equal to the https URL and exactly one `NODE_EXTRA_CA_CERTS` equal to the pinned path, any deviation fails the canary, and the event names the first deviating condition with fixed integers only.

**Assembly.** The sources that can put a duplicate in `Config.Env`: the env-file at the canary `docker run` (scrubbed by Guard 2) and the `-e` flags of that run. (An image-baked `ENV` is replaced by the user value, not duplicated.) The chokepoint is the single `docker inspect` read in `inngest_link_canary_check`; there is exactly one canary `docker run` site. The prod site is not inspected (Cut List); its env is covered by the effective-env assertion over both runs in T1 and the tuple census on its ARGV. The conditions are evaluated in a fixed order over one captured `envs` value.

**Mutation matrix** (each edit must drive the named row RED):

| # | Edit | Must redden |
|---|---|---|
| 1 | drop the `inspect_failed` branch (treat rc != 0 or empty as a wrong count) | resolver E3 `none` and `empty`, E7 `inspect_failed` lines, ci-deploy T6 |
| 2 | swap the precedence of `url_count` and `url_value` | E7 `duphttp` (two http lines: expected `url_count`, mutated reads `url_value`) |
| 3 | measure `ca_count` by exact-value count instead of prefix count | E7 `badca` (expected `ca_value`) and `dupca` |
| 4 | accept last-wins (count only the last `INNGEST_BASE_URL=` line) | E3 `twice`, ci-deploy T5 |
| 5 | the event loses its integers or `cause=` | the E7 anchored-regex row |
| 6 | the inspect step never runs (`return 0` before the read) | E3 modes, T5, T6 (a guard that reports nothing and exits 0 is vacuous) |
| 7 | the reason is not split, or is built from `$why` / `$cause` | the E3 reason assertion, the non-inspect-reason assertion, T5 |

**Harness rows.** A suite edit that must redden: restore the mock `inspect` to the `-e`-only form -> the T1 sentinel assertion goes RED (otherwise T1 passes vacuously on unmodified code). Must-PASS non-canonical inputs: a snapshot with lookalike keys (`INNGEST_BASE_URL_EXTRA`) that the check must not count, and a CRLF line.

**Anchor.** The pinned values are the script's own constants (`INNGEST_LINK_HTTPS_URL`, the CA path literal). A weakening has to move, outside this function, the resolver suite's anchors (`ANCH_B1..B3`) and, for argv, the pinned digest literals of `docker-run-tuple.test.sh` and `test/docker-run-tuple-posture.test.ts`, so one diff cannot quietly edit both the value and the check.

### Guard 2 — the env-file scrub

**Property.** After the scrub, `$ENV_FILE` has zero lines naming `INNGEST_BASE_URL` or `NODE_EXTRA_CA_CERTS` (plain, whitespace-padded, bare-name), every other line is byte-identical, and a failure leaves the file untouched and, on the strict path, aborts the deploy before any container starts.

**Assembly.** Every reader of `$ENV_FILE` (the resolver, the redactor, the `github_app_key_present` call, the overlay, both docker runs, the EXIT trap) sees the file after one rewrite at one call site; the two `docker run` sites take the same variable, so one scrub covers both, and the tuple census (`TUPLE_COUNT`) keeps the count of `--env-file "$ENV_FILE"` sites at two. Both names are members of one regex; a pinned variable added later must join the regex and L1.

**Mutation matrix** (kill_mut rows mutate a copy of the resolver block; the call-site row cannot, see below):

| # | Edit | Must redden |
|---|---|---|
| 1 | drop `NODE_EXTRA_CA_CERTS` from the regex (the second member) | L1 |
| 2 | drop the bare-name alternative (`(=\|$)` becomes `=`) | L1 (bare-name line) |
| 3 | delete the recount, or the conservation check | L4, L5 |
| 4 | treat grep rc 1 as an error | L6 (all lines match) |
| 5 | drop `LC_ALL=C` / `-a` from one grep | L1 (NUL and non-UTF-8 lines) |
| 6 | the regex made greedy (an `INNGEST_` prefix) | L1 (lookalike keys survive: a must-PASS row) |
| 7 | the scrub call removed, or moved after the canary `docker run` | the wiring row L7 (static line order over the real file) and T1 (not a `kill_mut` row: the call site is outside the block; do not count it in `MIN_ROWS` as one) |

**Harness rows.** A suite edit that must redden: make L1 compare only the line count -> the byte-for-byte assertion (kept as its own assertion) is the one that catches it. Must-PASS non-canonical inputs: CRLF, lookalike keys, a file without a trailing newline, an empty file, a NUL byte, a non-UTF-8 byte.

**Anchor.** The regex and the call-site order are pinned by the resolver suite (a block copy is mutated; the wiring row reads the real file), outside the function being weakened.

## Observability

```yaml
liveness_signal:
  what: per web host and per deploy, the existing INNGEST_LINK journald rows (class=resolved always; class=canary_ok on a flag-on deploy that passes; class=env_scrubbed removed=<n> when the Doppler snapshot carried a pinned name)
  cadence: once per deploy per host (not periodic)
  alert_target: none today for op=inngest-link (#10556, tracked); the flip run and the release run fail non-zero on a failed canary or strict scrub (synchronous, layer 6); the rows are read in Better Stack
  configured_in: apps/web-platform/infra/ci-deploy.sh (inngest_link_event); shipped by apps/web-platform/infra/vector.toml Source 4 (tag ci-deploy), unchanged
error_reporting:
  destination: Better Stack Logs via the journald tag ci-deploy (layer 3) and Sentry (feature=ci-deploy, op=inngest-link, classification=canary_failed or env_scrub_failed) for warning and error events (the existing inngest_link_event path)
  fail_loud: a failed strict deploy exits non-zero with a constant reason in the release run log (layer 6: canary_inngest_link_inspect_failed, canary_inngest_link_failed or inngest_env_scrub_failed), and the event carries the discriminating fields (layer 3 and Sentry)
failure_modes:
  - mode: the canary is handed an ambiguous or wrong Inngest env (duplicate or non-https URL, missing or different CA path, or the daemon call failed)
    detection: class=canary_failed check=inspect cause=<inspect_failed|url_count|url_value|ca_count|ca_value> with url_lines, url_https, ca_lines, ca_ok in one event, which discriminates the five competing hypotheses without a second read (layer 3 Better Stack and Sentry); the layer 6 run log carries the reason canary_inngest_link_inspect_failed, which alone separates this composition defect from the network, CA and registry class (canary_inngest_link_failed)
    alert_route: none today (#10556); failed release or flip run (layer 6)
  - mode: the scrub cannot read or write the env-file, or conservation or the recount fails
    detection: class=env_scrub_failed level=error stage=<read|write|recount> (layer 3 and Sentry); on a strict deploy also the state reason inngest_env_scrub_failed in the run log (layer 6)
    alert_route: failed release run on the strict path (layer 6); a non-strict deploy continues and the event is the only signal
  - mode: the Doppler snapshot carries a stale pinned name (config hygiene, harmless after the fix)
    detection: class=env_scrubbed removed=<n> on every deploy of that host (layer 3)
    alert_route: none (read after the next flip; tidying Doppler is an owner act and not part of this change)
  - mode: web-2 still runs the old script, or its canary fails while web-1 passes
    detection: the per-host read in the runbook (class=resolved, canary_ok or canary_failed, env_scrub_failed per host, each since the flip's T0, keyed on host; layer 3)
    alert_route: the owner reads it after the flip; no page
  - mode: an event line leaks an env value
    detection: the anchored-regex test on the event line (CI); integers and fixed tokens only by construction
    alert_route: CI red
logs:
  where: Better Stack Logs (Vector Source 4, journald tag ci-deploy) and Sentry (op=inngest-link)
  retention: Better Stack Logs source retention and Sentry project retention (existing)
discoverability_test:
  command: doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh --since 7d --grep 'INNGEST_LINK: class=' --limit 1
  expected_output: class=
  credentials_required: BETTERSTACK_QUERY_HOST, BETTERSTACK_QUERY_USERNAME and BETTERSTACK_QUERY_PASSWORD (ClickHouse read credentials in Doppler soleur/prd_terraform) - Better Stack warehouse reads have no anonymous path and the ingest token is write-only, so no unauthenticated probe verifies the same property. The command reads the channel the new rows ship through (the existing INNGEST_LINK events); the new rows exist only after delivery and a deploy, and are read with --grep 'class=env_scrubbed' or 'check=inspect'
```

Layers cited: 3 (Vector journald shipper to Better Stack, plus the Sentry POST from `inngest_link_event`) and 6 (the release or flip run log, a constant reason only).
Stated limit: the cause enum and counts are asynchronous (layer 3); the run log separates the inspect class from the rest but not the five inspect causes from each other.

## Domain Review

**Domains relevant:** engineering

### Engineering

**Status:** reviewed
**Assessment:** CTO ruled the fix shape, placement and failure policy, diagnostics grammar, scope boundaries, test plan, ADR treatment and the synchronous reason (rows in decision-challenges.md). Plan review (DHH, Kieran, code-simplicity, architecture-strategist, spec-flow, CPO) changed: the abort is strict-path only, the scrub validates before `mv` with `LC_ALL=C grep -a`, the red evidence moved to a commit message, test volume was trimmed, and the per-host read and delivery risks were added.
No product, marketing, legal, finance, operations-spend or sales implication: a deploy script, its tests and two runbooks; no user-facing surface, no data-processing change (the GDPR gate is not triggered: no schema, auth flow, API route or `.sql` file, no new processing activity), no new vendor or paid dependency.

## Open Code-Review Overlap

None (200 open `code-review` issues searched by body for the planned files).

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "FAILING TEST FIRST in ci-deploy.test.sh: with the mock `inspect` made env-file-aware" [brief] | Phase 1.1, 1.2, 1.5 | mapped |
| 2 | "the flip-on deploy must be shown failing before the fix and passing after, with canary AND prod still starting with exactly one https `INNGEST_BASE_URL` in effect" [brief] | T1, `il_effective_clean`, Phase 1.5 | mapped |
| 3 | "(and a case for a duplicate `NODE_EXTRA_CA_CERTS`)" [brief] | T3, L1 | mapped |
| 4 | "Plan must state the red run evidence step" [brief] | Phase 1.5 | mapped |
| 5 | "FIX: the CTO agent rules on the shape" [brief] | decision-challenges.md rows; Phase 2 | mapped |
| 6 | "drop INNGEST_BASE_URL and NODE_EXTRA_CA_CERTS from the env-file copy handed to the canary and prod runs, without touching any key the app needs at runtime" [brief] | Phase 2.1, 2.2, L1 | mapped |
| 7 | "keep the inspect check strict so a real duplicate still fails" [brief] | Guard 1, T5, E3 | mapped |
| 8 | "Check apps/web-platform/infra/lib/docker-run-tuple.py and its tests ... check both the canary and the prod `docker run` sites (and the first-boot tuple if relevant)" [brief] | Phase 2.4 runs, Cut List, accepted residual | mapped |
| 9 | "resolve_inngest_link reads INNGEST_LINK_TLS and INNGEST_TLS_CA from it; do not break that" [brief] | scrub after the resolver; L1 keeps those keys; T1 asserts them | mapped |
| 10 | "the `canary_failed` event for the inspect check must name which condition was off ... plus observed counts as fixed integers" [brief] | Proposed Solution 2, E7 | mapped |
| 11 | "a failed `docker inspect` must report `inspect_failed` rather than `none`" [brief] | cause table, E3/E7 `none` and `empty`, T6 | mapped |
| 12 | "Update knowledge-base/engineering/operations/runbooks/canary-probe-set.md and the failure table in knowledge-base/engineering/operations/runbooks/inngest-server.md, and add a test row per cause" [brief] | Phase 3.1, 3.2; one E7 mode per cause | mapped |
| 13 | "Check whether a Better Stack/Vector allowlist or alert definition keys on the event text" [brief] | Phase 3.2 note (checked: none) | mapped |
| 14 | "Observability review per hr-observability-as-plan-quality-gate; no SSH in any runbook step" [brief] | Observability section, Phase 3 | mapped |
| 15 | "STOP BEFORE MERGE ... the pipeline ends with a `Paused:` line" [brief] | Phase 5.2 to 5.4 | mapped |
| 16 | "keep edits localized to reduce conflict risk" (open sdk-bash PR) [brief] | three localized edit places; no trap edit | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| ci-deploy.sh edits | "FIX: the CTO agent rules on the shape" (asks 5 to 7, 10, 11) | asked |
| ci-deploy.test.sh edits, mock, rows T1 to T8 | asks 1 to 4 | asked |
| inngest-link-resolver.test.sh edits | — | inferred — justification: it pins the same check (`check=inspect cause=none` assertions, ANCH_B1..B3, the `MIN_ROWS` floor), so leaving it unedited makes the suite red |
| canary-probe-set.md, inngest-server.md edits | ask 12 | asked |
| ADR-294 addendum | — | inferred — justification: plan skill Phase 2.10 makes the ADR update a deliverable of the plan that changes the recorded invariant, and the CTO ruled it |
| `inngest_env_scrub_failed` reason, `env_scrub_failed` event, strict-only abort | "without touching any key the app needs at runtime" (ask 6) | inferred — justification: a scrub with no failure policy either proceeds on an unscrubbed file or blocks rollbacks; CTO ruled (Q2, Q7) |
| `env_scrubbed removed=<n>` info event | "unconfirmed because Doppler key names were not read" (brief) | inferred — justification: the only no-SSH, no-key-name way to confirm the root cause; emitted only when `removed>0` |
| Phase 4 local real-Docker confirmation | "Verified locally with Docker 29.9.2" (brief) | inferred — justification: the mock cannot prove Docker behavior; the CTO required one local check |
| split reason `canary_inngest_link_inspect_failed` | — | inferred — justification: observability gate and `observability-coverage-reviewer` Step 2.5 flag a fatal cause visible only asynchronously for a webhook-driven deploy; CTO ruled (Q6) |
| `preflight-discoverability-test.test.ts` baseline bump | — | inferred — justification: the Observability block declares `credentials_required`, and that repo-global ratchet counts declaring plans, so omitting the bump reds the full battery at ship |
| Phase 5 review, QA, CI | "Do everything through review, QA and green CI" | asked |

### Split Assessment

- Subsystems touched: 2 (apps/web-platform/infra, knowledge-base) plus one ratchet line under plugins/soleur/test
- Planned files: 7 edited, 2 created | Estimated changed lines: about 450 (about 90 in ci-deploy.sh, about 250 tests, about 80 docs, a few in the ratchet test)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

### Pre-merge (PR)

- [ ] The "test: red" commit exists before the fix commit and its message shows T1 (both arms), T5, T6, T8a, T8b and the resolver inspect and scrub rows RED, and T3 and the T1 sentinel assertion green, on unmodified code.
- [ ] `bash apps/web-platform/infra/ci-deploy.test.sh < /dev/null` exits 0 with every new row passing and no previously passing row failing (Guard 7 included).
- [ ] `bash apps/web-platform/infra/inngest-link-resolver.test.sh < /dev/null` exits 0, `MIN_ROWS` equals the row count, and every new `kill_mut` row reports killed.
- [ ] `python3 apps/web-platform/infra/lib/docker-run-tuple.py` exits 0 and `bash apps/web-platform/infra/docker-run-tuple.test.sh < /dev/null` passes, with no edit to either.
- [ ] `bun test plugins/soleur/test/preflight-discoverability-test.test.ts` passes with `BASELINE_DECLARED_PROBES` raised by exactly one over its live value, with its comment entry (no `LEFTHOOK_EXCLUDE=bun-test`).
- [ ] `python3 scripts/lint-trap-tempfile-ownership.py` does not raise its highwater; `bash scripts/guard-vacuity-floor.test.sh < /dev/null` and `bash plugins/soleur/test/c4-count-parity.test.sh < /dev/null` pass.
- [ ] In T1, the canary and the prod run each have exactly one `INNGEST_BASE_URL=https://10.0.1.40:8443` and exactly one `NODE_EXTRA_CA_CERTS=/etc/soleur/inngest-ca.pem` in effect, and `class=canary_ok` is logged.
- [ ] A real duplicate still fails (T5) with `check=inspect cause=url_count url_lines=2 ...`; `cause=none` never appears for `check=inspect`.
- [ ] A failed inspect sets the deploy-state reason `canary_inngest_link_inspect_failed`; every other Inngest canary failure keeps `canary_inngest_link_failed`; the reason is a literal per branch.
- [ ] A strict-path scrub failure aborts with `inngest_env_scrub_failed` and no container started (T8a); a non-strict one continues with the env-file unchanged (T8b).
- [ ] The inspect event line matches the anchored regex (integers and fixed tokens only).
- [ ] Both runbooks and ADR-294 are updated and the added lines contain no SSH step (a grep for the `ssh` verb over the added lines returns nothing).
- [ ] The Phase 4 local real-Docker output (2 entries, then 1) is in the PR description, with the proxy limits stated.
- [ ] The PR body carries `Ref #10136` and `Ref #10205` (not `Closes`: the flip is not done), the proof-limits statement and the second-flip target date (Phase 5.3).
- [ ] Multi-agent review done (user-impact-reviewer and observability-coverage-reviewer included), QA done, CI green. Nothing merged, nothing armed, no workflow dispatched.

### Post-merge (owner-gated, NOT performed by this pipeline)

- [ ] The owner's typed go merges in a cron-quiet window; the merge triggers the existing deploy-pipeline auto-apply to both web hosts (irreversible-class, never run here).
- [ ] Before the second flip: the apply run for the merge commit concluded success (its web-1 and web-2 jobs are fail-closed, a read through `gh run list`), then the second flip is the owner's separate typed go, and the per-host Better Stack read in the runbook is its evidence.

## Test Scenarios

| # | Given | When | Then |
|---|---|---|---|
| T1 | flag on and off, snapshot has `INNGEST_BASE_URL=http://...` | full deploy under the mock | rc 0, canary and prod effective env clean, `canary_ok` (on), `env_scrubbed removed=1`, sentinel `KEY=value` visible (RED before the fix: `cause=none`) |
| T3 | snapshot has `NODE_EXTRA_CA_CERTS=/tmp/x` | full deploy | aborts `github_app_key_env_hijack`, zero runs |
| T5 | scrub in place, a second URL line injected at inspect | full deploy | fails, `cause=url_count url_lines=2 url_https=1 ca_lines=1 ca_ok=1`, only the canary started |
| T6 | `docker inspect` exits 1 | full deploy | `cause=inspect_failed`, zero counts |
| T8a, T8b | the scrub cannot write | full deploy, flag on or off | on: aborts `inngest_env_scrub_failed`, zero runs; off: continues, env-file unchanged |
| E modes | stub inspect `http noca twice duphttp dupca badca none empty many` | `inngest_link_canary_check` | the exact event line per mode |
| L1 to L7 | throwaway env files, `grep`/`mv`/`mktemp` stubs | the scrub function | per Phase 1.4 |

## Dependencies and Risks

- **#10697 (open, sdk-bash)** edits both ci-deploy files: three localized edit places and no trap edit; rebase on `origin/main` before review and keep both sides.
- **Production not verifiable here** (no SSH, no Doppler or production write): the first live proof is the next flip attempt's `canary_ok` or its new `cause=`; the PR body says so.
- **Doppler may not carry the name** (unconfirmed): then the diagnostics become the whole fix and the unconditional scrub is a silent no-op (no `env_scrubbed` row). The PR is correct either way.
- **web-2 skew and non-atomic write:** the per-host read and the cron-quiet merge window mitigate; stated, not eliminated.
- **Mock approximation:** the mock drops bare-name lines; the scrub's bare-name handling is proven by L1, not T1.
- **Shared-counter conflicts:** `MIN_ROWS` and `BASELINE_DECLARED_PROBES` can collide with a sibling PR; re-measure at work time and at the last rebase.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or omits the threshold fails `deepen-plan`; this one declares `single-user incident`.
- `MIN_ROWS` in the resolver suite must equal the real row count exactly, in the same edit as any row.
- The reason literals `inngest_env_scrub_failed`, `canary_inngest_link_inspect_failed` and `canary_inngest_link_failed` must be constants: `final_write_state` splices them into JSON unquoted.
- Use `mktemp "$1.scrub.XXXXXX"` beside the target (same filesystem for the atomic `mv`, and distinct from the overlay's `.gak.` template that Guard 7's stubs key on).
- Keep `LC_ALL=C grep -a` on every grep in the scrub; the plain form silently loses lines on a file that holds secrets.
- Run the suites one at a time with stdin from `/dev/null`.
