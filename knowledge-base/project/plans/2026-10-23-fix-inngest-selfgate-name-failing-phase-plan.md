---
title: "fix(inngest): name the failing phase in the selfgate_failed event (rc=56 was unreadable on the second flip)"
type: fix
date: 2026-10-23
slug: fix-inngest-selfgate-name-failing-phase
branch: feat-one-shot-inngest-selfgate-phase
issue: 10934
closes: 10934
lane: single-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# fix(inngest): name the failing phase in the `selfgate_failed` event (rc=56 was unreadable on the second flip)

Epic #10205, item #10136, ADR-294. **Stop-before-merge pipeline:** everything below runs through review, QA and green CI; nothing is
merged, nothing is armed, the flip workflow is never run or dispatched, no Doppler or production write happens, production is not read
(the live-signal probe in `## Observability` is a post-merge read for the owner's session, not a step of this pipeline), and there is no SSH. The
pipeline ends with a `Paused:` line asking for a typed go that names the merge: the merge auto-applies `ci-deploy.sh` to both production
web hosts, and the third flip is a separate owner act after it.

## Enhancement Summary

**Deepened on:** 2026-10-23
**Gates run (deepen-plan):** User-Brand Impact (4.6, threshold `single-user incident`, filled), Observability (4.7, `credentials_required` declared so the probe-verb gate is skipped as `SKIP-DECLARED`, the same shape as the #10874 plan; the probe is never run by this pipeline), PAT sweep (4.8, clean), UI wireframe (4.9, no UI surface), Encryption Posture (4.10, not triggered: no store, no new connection, no `.tf`/migration/cloud-init edit), Guard Contract (4.11, `lint-guard-contract.py` green, one guard entry), Scope Check (4.12, one unfenced section, no unmapped ask), precedent diff (4.4, added below), cited issues and PR re-verified live (#10934, #10205, #10136, #10880, #10556, #10543, #10856 open; #10874 merged), rule ids resolved (`cq-write-failing-tests-before`, `hr-weigh-every-decision-against-target-user-impact`), cited learning files resolved by name (two abbreviated names corrected), the literal commands the plan prescribes run once (`git grep -c` call-site count = 1, both `gh run list` idle checks, `probe-verb-gate.sh`), markdownlint clean.
**Agents used:** soleur:engineering:cto (rulings F1 to F5, F2a, R3a to R3e), dhh-rails-reviewer, kieran-rails-reviewer, code-simplicity-reviewer, architecture-strategist, spec-flow-analyzer (plan review); user-impact-reviewer, observability-coverage-reviewer, test-design-reviewer (deepen); functional-discovery (no overlap), learnings-researcher.

### Key Improvements

1. The success verdict is decided first, from rc and the first token alone, before any shape validation (a short `-w` line from a healthy listener can never fail the gate); `http=` and every field come only from validated values.
2. The phase map is derived from times with rc used only for 77 and 60; the same times with rc 52, 56 and 1 pin `request`; a truncated 200 (rc 18, measured in the deepen pass) reads `request`, not `status`; `verify` is forced to 0 outside `phase=verify`.
3. One shared profile table and printer for both curl doubles, a sentinel that makes an unknown variable or profile fail loudly (the function under test swallows curl's exit and stderr), a real-curl differential comparing rc class, code, zero-ness of the times and verify, and a profile-file mutation row that proves the differential can go RED.
4. Mutation rows proven after the fix in three steps (not claimed RED before it); 20 rows with split `unknown` arms; S rows pin `SG_ATTEMPTS`; S7 asserts equality; S9 runs against a known-bad doc copy.
5. The decode names a first no-SSH read per token from the shipped `tls-health` phone-home rows, keeps the phase honest about layer 6 (the run log carries only the constant reason), lists the unexpected `verify` values, and states that `attempts=` is the denominator.

### New Considerations Discovered

- The Inngest host already ships `tls-health` rows (unit, nrestarts, listener, bind, served_sha256 against cert_sha256) by a direct phone-home POST independent of the journald shipper, so a terminator-state read exists without #10880.
- The ratchet `BASELINE_DECLARED_PROBES` moved the moment this plan was committed (it declares `credentials_required`), so its bump is Phase 0 and the first work commit.
- A RED commit cannot pass the pre-push ratchet lane; it stays local and is pushed with the fix.

## Overview

On 2026-10-23 the second flip of the Inngest scheduler link (run 39977793262) failed at the host-side self-gate on web-1 with
`INNGEST_LINK: class=selfgate_failed level=error rc=56 http=000 attempts=3` (deploy reason `inngest_link_selfgate_failed`) before any canary ran,
and the fleet reverted to http. The event carries only the last attempt's curl exit code and HTTP status, so the stage that failed (listener
unreachable, TLS handshake, certificate verification, or the request after a verified handshake) cannot be read from it, and the terminator's own
journald is not shipped (#10880). This change makes `_inngest_link_selfgate` name that stage with fixed-token and clamped-integer fields only, the
same move #10874 made for the canary's `inspect` check, and proves the new fields against what real curl prints, not against a hand-written mock.

## Research Insights

**Premise Validation (Phase 0.6).** Checked live with `gh` and `git grep` on `origin/main`: #10934 is OPEN with no closing PR; #10205, #10136,
#10880, #10556, #10543 and #10856 are OPEN; #10874 is MERGED. `_inngest_link_selfgate` and `inngest_link_event selfgate_failed` exist on `origin/main`
(one definition, one call site at `resolve_inngest_link`). Stale or loose premises found: (1) the brief calls #10543 a "replay check after flip", but
its subject is the dashboard send route (`app/api/dashboard/today/[id]/send/route.ts`) having no retry or replay path; it is related context
(the flip's container swap widens its exposure) and out of scope here. (2) The brief and the issue place the stub rows in `ci-deploy.test.sh`; the
self-gate rows (A4, A7, A8, F2) live in `apps/web-platform/infra/inngest-link-resolver.test.sh`, which sources the real resolver block under
stubs, so the per-phase rows go there and `ci-deploy.test.sh` gets the honest mock plus one end-to-end row (see Scope Check, ask 2). (3) The ADR corpus
was grepped for the proposed mechanism (`-w` variables, a second diagnostic probe): ADR-294 names the self-gate and its host-side `--cacert` contract but
no event grammar for it and no rejected alternative about a second probe; nothing in the corpus rules the approach out.

**Property List (Phase 0.6b).** P1: a failed self-gate event says which stage the last attempt reached, readable without SSH. P2: the event cannot
carry a value (URL, IP, certificate text, error text, header). P3: the pass/fail verdict of the gate is exactly what it is today
(`rc==0` and HTTP 200 on a TLS verification against the candidate file). P4: the test double for curl prints what real curl prints for each
phase, and a double that drifts from real curl turns a test red. P5: the fields rely only on curl features the hosts' curl has.
**Cut List.** (a) A second diagnostic probe after a failure (an unverified `curl -k`, or the existing `/hooks/inngest-tls-handshake` call) buys P1 only
by adding an unverified-TLS code path to the trust path and a second timeout budget; the single `-w` line already buys P1; cut (CTO F3). (b)
Raw millisecond timing fields (`time_connect`, `time_appconnect` as numbers) buy no decision beyond the derived token and add cardinality plus a
certificate-timing side channel; cut (CTO F1). (c) `%{errormsg}` / `%{exitcode}` (curl 7.75+) buy a readable cause but are free text and a version
constraint; cut, P2 and P5. (d) Shipping the Inngest host's journald (#10880) and a Sentry alert on `op=inngest-link` (#10556) are named out of scope by
the issue.

**Measured, not assumed (the evidence file).** `knowledge-base/project/specs/feat-one-shot-inngest-selfgate-phase/curl-w-measurements.md` records the
self-gate's exact curl line against real local servers (a python `ssl` listener and a real `stunnel` 5.72 with the production conf shape) on curl
**7.81.0** (Ubuntu 22.04 package), **8.5.0** (Ubuntu 24.04 package; `server.tf` provisions `ubuntu-24.04` and the CI runner is the same userland) and
**8.23.0** (the dev host), 23 scenarios. The host's real curl version was NOT read (no production reads); the repo facts say 8.5.0. Findings that
shape the design: (1) `http_code`, `time_connect`, `time_appconnect`, `ssl_verify_result` exist since curl 7.19 and printed identically on all
three builds; `%{errormsg}` needs 7.75 and is not used. (2) rc alone is ambiguous (28 occurs in connect, handshake and response; 56 only after TLS)
and **differs across builds for the same wire event** (TCP close without `close_notify`: rc 52 on 8.5.0, rc 56 on 7.81 and 8.23; a missing `--cacert`
file: rc 77 or rc 2 with empty output on 8.23), so the phase is derived from the times. (3) `ssl_verify_result` reads 1 for hostname mismatch, CA-file
errors and every handshake failure, and 0 for connect failures and every completed handshake: it is a verification code only when rc is 60 (18 =
served certificate is not the pinned one, 10 = expired). (4) With real stunnel, **upstream `127.0.0.1:8288` refused gives rc=56 with TLS completed and
verified** (`000|0.000138|0.004360|0|1`): the exact incident signature; upstream accept-and-close or RST gives rc=52; upstream silent gives rc=28 after
the 10 s `--max-time`. A measured match, not proof of the 2026-10-23 cause. (5) Empty `-w` output happens (rc 124 from the `timeout 20` wrapper; rc 2 on
8.23). (6) An unknown `-w` variable prints nothing, exits 0 and warns on stderr, so the test double must refuse variables it does not model. (7) `-w`
output has no trailing newline.

**Institutional learnings applied** (from `soleur:engineering:research:learnings-researcher`, 25 entries read for relevance):
`2026-10-22-docker-keeps-env-file-and-dash-e-entries-and-the-mock-could-not-show-it.md` (a double that models part of the tool hides the defect; a
diagnostic default like `cause=none` names nothing: set the phase on every branch, no default that reads as success),
`2026-09-21-curl-retry-flags-turn-a-throttled-emit-into-success-and-my-stubs-were-looser-than-the-code.md` and
`test-failures/2026-08-19-my-stub-could-not-express-the-failure-so-the-fix-reverted-green.md` (the stub needs an exit-code axis and real partial stdout),
`2026-09-28-a-counter-named-for-a-cause-measured-a-gap-that-every-outage-produced.md` (`-w` prints on failure; a `|| echo` fallback appends a second
value), `2026-10-08-a-pipe-tail-swapped-for-a-command-substitution-aborts-mute-and-the-green-suite-ran-on-a-newer-toolchain-than-ci.md` (run each changed bash suite once in an
`ubuntu:24.04` container before the first push: the dev host's curl 8.23 and bash 5.3 are newer than CI's 8.5.0 and 5.2), `2026-10-19-a-fail-closed-gates-tests-asserted-the-safe-verdict-which-two-causes-produce.md` (assert the cause, not the verdict), `2026-10-15-a-new-nonpaging-marker-moved-a-pin-in-a-suite-the-affected-gate-never-selects.md` and `2026-10-09-a-rollback-recipe-nobody-had-run-and-a-baselined-file-touched-without-its-changed-lint.md` (grep every
pinned-count suite and run the `--changed` lints before pushing), `best-practices/2026-05-27-bash-set-e-leaks-from-functions-use-or-true.md`.

**Conventions (CLAUDE.md / AGENTS.md).** One suite at a time with stdin from `/dev/null`; poll CI with Monitor; "unavailable" or "disruption" for a
service that is down; the two words for the infrastructure apply command never appear in a Bash command; no `git stash`; they/them when pronouns are unknown;
`cq-write-failing-tests-before` (tests first, RED evidence on unmodified code); `hr-weigh-every-decision-against-target-user-impact` (see
`## User-Brand Impact`).

## Research Reconciliation — Spec vs. Codebase

| Spec claim (issue #10934 and the brief) | Reality on `origin/main` | Plan response |
|---|---|---|
| "Add rows to `ci-deploy.test.sh` with a stub curl for each phase" | The self-gate is exercised in `inngest-link-resolver.test.sh` (rows A4, A7, A8, F2, mutation rows M05x, M18x) with a `$BIN/curl` stub that prints only the HTTP code or nothing and exits 0, 60 or the `FX_CURL_FAIL_FIRST` count. `ci-deploy.test.sh`'s unified curl mock answers every `*"/health"*` URL with `200` when `-w` mentions `http_code`. | Per-phase rows and mutation rows go in the resolver suite; the unified mock in `ci-deploy.test.sh` is rebuilt to interpret the `-w` format, plus one end-to-end row. Both doubles share one measured profile table (values copied from the evidence file). |
| "the `selfgate_failed` row currently lists three causes" | Runbook row at `inngest-server.md` ("The listener is down, the CA does not match the served certificate, or the host-to-host path is blocked"); correct. | Rewritten with a field decode and a per-phase reading; a `deploy-status-debugging.md` row for the constant reason `inngest_link_selfgate_failed` is added (it has none). |
| "the host's curl version has not been read; do not assume" | Hosts are provisioned `ubuntu-24.04` (`server.tf`, `inngest-host.tf`); the CI runner userland is curl 8.5.0 (learnings). Not read from a host. | Use only variables present since curl 7.19; measured on 7.81, 8.5.0, 8.23; a static row pins the `-w` variable allowlist so a later edit that adds `%{errormsg}` reds. |
| "clamped like the canary integers (`_inngest_link_count99`)" | `_inngest_link_count99` is defined after `_inngest_link_selfgate` in the same block; non-numeric reads 0; never aborts. | Reused for `tcp`, `tls`, `verify`. Definition order is irrelevant at call time. |
| "PR 10874 touched ... MIN_ROWS ... BASELINE_DECLARED_PROBES ... grep-q-pipe-guard / fixture-relative-assert baselines" | `MIN_ROWS=203` (exact) in `inngest-link-resolver.test.sh`; `CI_DEPLOY_ASSERT_FLOOR=719` (a floor) in `ci-deploy.test.sh`; `BASELINE_DECLARED_PROBES=76` at `preflight-discoverability-test.test.ts:3021` (equal on `origin/main`); `PJ_TRIPLES=294` in `.claude/hooks/grep-q-pipe-guard.test.sh`; `fixture-relative-assert.baseline.txt` per-file counts. | Phase 5 re-measures each from a green run; none is bumped by reasoning. |

## Problem Statement / Motivation

The self-gate is the proof, run on the host before the CA is installed, that the pinned file verifies the live listener and that the listener answers
`/health` with 200. Its failure event names `rc` and `http` of the last of three attempts. rc=56 with http=000 means curl connected and then failed
to receive data; it cannot tell a terminator that reset a verified TLS session (its upstream leg to `127.0.0.1:8288` refused) from other causes by the
event alone. Because each flip attempt costs two host swaps (the flip and its revert), which cut running agent sessions, an unreadable failure
means another disruption to find out why (issue #10934, User-Impact).

## Proposed Solution

### Event grammar (ruled, CTO F1/F2, 2026-10-23)

```
INNGEST_LINK: class=selfgate_failed level=error rc=<n> http=<ddd|none> attempts=<n> phase=<token> tcp=<0-99> tls=<0-99> verify=<0-99>
```

The existing prefix `rc= http= attempts=` stays byte-identical (the A7 row substring-matches `rc=0 http=502`; no other consumer matches the full
string: `grep` over the repo finds `selfgate_failed` only in `ci-deploy.sh`, the resolver suite and the runbook). New fields are appended:

- `phase=` one fixed token naming the stage the LAST attempt reached: `connect | handshake | verify | ca_file | request | status | unknown`.
- `tcp=` the number of attempts (of all) whose `time_connect` was non-zero, i.e. reached TCP connect; `tls=` the number whose `time_appconnect` was
  non-zero, i.e. completed the TLS handshake. Both clamped by `_inngest_link_count99`. They show attempt-to-attempt change that `phase` (last attempt only) hides.
- `verify=` is `0` unless `phase=verify`, and then the last attempt's `ssl_verify_result` clamped to 99 (18 pinned certificate is not the served one, 10 expired, 1 hostname/SAN mismatch,
  any other value an unlisted X509 verification code). The raw value is 1 on handshake and CA-file failures and would read as a SAN mismatch, so the emitter coerces it (CTO R3b); a mutation row pins the coercion.
- Every field is a fixed token or a clamped integer; `http=` is printed from the validated three-digit first token, else `none`, never from raw curl output. `tcp` and `tls` count only attempts whose own time field passed the shape check.

### Phase derivation (one curl per attempt; no second probe: CTO F3)

The curl call keeps every current flag and changes only the format: `-w '%{http_code} %{time_connect} %{time_appconnect} %{ssl_verify_result}'`.
Output is split into `code tc ta ver` with `read -r` from a here-string (curl prints no trailing newline; the here-string supplies one, bash 5.1+ feeds a small here-string through a pipe (reasoned from bash's changelog, not measured; ubuntu-24.04 runs bash 5.2), so no temp file is involved; `|| true` is defensive, not load-bearing). All variables are declared `local` with initial values (the suite runs under `set -u`).
**The success verdict is decided first, from rc and the first token alone**: `rc==0` and `code==200` returns 0 before any shape validation of the other three fields, so a short or odd `-w` line from a healthy listener
can never turn a pass into a failure (a mutation row pins it). Only then are fields validated, once, with the regexes held in variables: code `^[0-9]{3}$` (else `http=none`), times `^[0-9]+[.,][0-9]+$` (either separator accepted,
zero tested by `^[0.,]*$` after the shape check, no float math). The phase is the output of a pure helper `_inngest_link_selfgate_phase <rc> <code> <tc> <ta>` printing one token, in precedence order (ruled by the CTO, R3a):

1. rc 124, or empty output, gives `unknown`. No branch defaults to a success-looking token.
2. rc 77 gives `ca_file`; rc 60 gives `verify`. Both from the rc alone (decided from rc, never from `ssl_verify_result`: 1 is ambiguous).
3. a validated three-digit code other than `000` and other than `200` gives `status` (TLS verified, an HTTP status other than 200, e.g. 502; never from rc alone). Code 200 with a non-zero rc (a truncated body: measured rc 18 on curl 8.5.0, `200|0.000329|0.012484|0`) is NOT `status`: it falls through to the time rules and reads `request` (deepen-pass finding, ratified by the CTO as row R3e; a non-200 code with a non-zero rc stays `status`, measured rc 18 with a 502 header: `502|0.000110|0.007349|0`).
4. only now are the time fields needed: if either fails its shape check the phase is `unknown`.
5. `time_connect` zero gives `connect` (rc 7, 6, or rc 28 with no TCP connection: a firewall drop or a stopped listener).
6. `time_appconnect` zero gives `handshake` (TCP up, TLS incomplete: rc 35, or rc 28 "SSL connection timeout").
7. otherwise `request` (TLS completed and verified, no HTTP status: rc 52, 56, 28, 1).

Rules 5 to 7 classify by times, not by an rc list (ratified by the CTO, rows F2a and R3a of `decision-challenges.md`) because the measured rc for one wire event differs across curl builds (52 on 8.5.0 vs 56 on 7.81 and 8.23).
`phase=request` means only "TLS verified, no HTTP status came back"; the runbook and the ADR addendum word it as "check the terminator and its upstream, not the certificate" and never assert a root cause.
An attempt whose time fields are unparsable adds nothing to `tcp` or `tls`, so `phase=unknown tcp=0 tls=0` does not mean "connect failed": the runbook decode says so (rc 124 = the `timeout 20` wrapper killed curl, a hang; rc 2 = an unreadable CA file on curl 8.23; rc 0 with `unknown` = the curl output format changed).

### What stays out

No `-k`, no second probe, no `%{url_effective}` / `%{errormsg}` / `%{remote_ip}`, no raw times, no retry or timeout change (3 attempts, `sleep 2`, 5 s connect,
10 s max, `timeout 20`), no change to the install order or to what a failed gate does to the previous CA file.

## Technical Considerations

- **Host curl constraint.** The four variables exist since curl 7.19 (`time_connect`, `time_appconnect`, `ssl_verify_result` documented from 7.19.0; verified
  by measurement on 7.81.0, 8.5.0, 8.23.0, which brackets the curl any supported Ubuntu userland ships; builds older than 7.81 were not measured, and all four variables predate 7.19). The format allowlist is pinned by a
  static row (names in the `-w` string must be a subset of the four). Residual: the host curl was not read; rc 56 vs 52 for one wire event differs by build,
  which the time-based derivation absorbs.
- **Mock honesty (P4).** Three doubles of curl exist after this change (the resolver suite's `$BIN/curl`, the unified mock in `ci-deploy.test.sh`, and real curl in a differential row). Both stubs
  source ONE shared file, `apps/web-platform/infra/test-fixtures/curl-w-profiles.sh`: a profile table (name, rc, http_code, time_connect, time_appconnect, ssl_verify_result; values copied from the evidence file) plus ONE
  printer function that interprets the `-w` string from argv, substitutes only the four modelled variables, prints no trailing newline, and on an unknown variable or an unknown profile **exits 99 and drops a sentinel file**
  (the function under test swallows a non-zero curl exit and its stderr, so the exit alone would read as one more failed attempt; every suite asserts after each row that the sentinel is absent, which is what makes a typo fail loudly).
  A profile can never default to a 200 profile (that is how #10874 hid). The existing `FX_CURL_FAIL_FIRST` branch used to exit 60 with empty stdout, which real curl never does (it prints `000 ... 18`); it now prints `verify18`.
  Raw profiles (`raw_empty`, `raw_garbage`, `raw_short3`, `raw_nonnum`, `ok200_comma_extra`) model non-canonical output for S6 and S8 and are outside H7's format regex. A harness row (H6) runs the REAL `_inngest_link_selfgate` against real curl and local python `ssl`
  listeners for six fast scenarios (closed port, accept-and-close, pinned-certificate mismatch, TLS then clean close, TLS 200, TLS 502) and compares the stub profile with real curl on (rc class, code, which of connect/appconnect are zero, verify), not on the phase alone,
  asserting rc class and not the exact rc for the 52/56 pair. RST, the empty-CA-file case and the hang phases (5 s and 10 s timers) are stub-only, resting on the evidence file. Under `CI` a missing curl/python3/openssl is a failure, not a skip;
  locally the skip is explicit and does `ROWS+=N; SKIP+=N` (as H3 does) so the exact `MIN_ROWS` is not FATAL.
- **The run environment.** The bare `ubuntu:24.04` image has no curl, python3, openssl, jq or shellcheck: the container run starts with `apt-get install -y curl python3 openssl jq shellcheck` and records `curl --version` and `bash --version`
  in the output. Run each changed suite once in `docker run --rm -v "$PWD":/w ubuntu:24.04` before the first push, as the 2026-10-08 learning requires; the dev host's curl 8.23 and bash 5.3 are newer than CI.
- **`set -e` / pipefail.** The self-gate runs under `if ! _inngest_link_selfgate`, so `set -e` is suppressed inside it even in the real script; the resolver suite runs under `set -uo pipefail` without `-e`. No new pipe is added; no `mktemp` is added (the trap-ownership lint stays untouched).
  The no-newline row (S8b) pins the parse (a stub that prints no newline still yields all four fields), not an abort behaviour.
- **Delivery.** `ci-deploy.sh` reaches web-1 through `terraform_data.deploy_pipeline_fix` and web-2 through its twin `deploy_pipeline_fix_web2` (#10856: an in-place file write; bash reads a running script incrementally, so a deploy in flight on web-2 when the write lands can
  continue from a stale offset, and the apply is fail-closed on web-2, so a stuck web-2 blocks web-1's apply as well). Accepted and disclosed in the PR body. Mitigation owned by the owner's merge step: the read-only idle check runs IMMEDIATELY before the merge go and covers any in-flight release or apply workflow (`gh run list --workflow web-platform-release.yml --status in_progress` and `gh run list --workflow apply-deploy-pipeline-fix.yml --status in_progress`, both run read-only at deepen time and both returned) and web-1's live deploy state (the `/hooks/deploy-status` read `scripts/check-deploy-script-parity.sh` already performs, read-only);
  the abort lever is `[skip-deploy-fix-apply]` in a commit message (`apply-deploy-pipeline-fix.yml` honours it). No new provisioner or host artifact is added, so there is nothing to classify twin or role-only.
- **No architectural decision.** No new substrate, boundary or ADR reversal; the ADR-294 addendum (below) records the second flip's observed event and the new fields as history, like the two
  earlier addenda. C4 is untouched (no actor, system, store or relationship changes).

## User-Brand Impact

**If this lands broken, the user experiences:** a deploy of the web app that is refused or disrupted on both production web hosts. Two shapes. (1) A syntax or
parse error in the `inngest-link-resolver` block aborts `ci-deploy.sh` for EVERY deploy including a rollback, so a customer-facing hotfix cannot ship until a repair merges (mitigated by
`bash -n`, shellcheck and both suites on the CI userland). (2) A bug in the new parsing that makes the gate report failure on a healthy listener would refuse every flag-on release, and a bug that
loosened the success predicate would let a CA that does not verify the live listener become the trust anchor for the app container's outbound TLS (mitigated by P3: the predicate is unchanged and
pinned by M18b and a new first-token row; a wrong CA fails against the real host, so it denies service rather than enabling a MITM). A flag-off deploy never calls the self-gate. (3) A decode that points the owner at the wrong fix (for example reading `verify=18` as a re-mint when the served certificate is merely a different self-signed one, or acting on `phase=request` as if the upstream refusal were established) would send the owner into another flip, and each flip attempt costs two host swaps that cut running agent sessions; mitigated by the wording ACs (`phase=request` is only "TLS verified, no HTTP response"), the decode table's per-token first reads, and S9. (4) Delivery: web-2 gets `ci-deploy.sh` by an in-place write (#10856), so a deploy in flight on web-2 at that instant can run a torn script; mitigated by the owner's idle check immediately before the merge go and the `[skip-deploy-fix-apply]` lever (Technical Considerations).
**If this leaks, the user's [data / workflow] is exposed via:** the event line rides journald, Better Stack and Sentry `extra.detail`; the only new content is a token from a seven-value set and
three integers 0 to 99, never a URL, address, certificate text, header or curl's `errormsg`, pinned by an anchored-regex row and a mutation that appends the URL.
**Brand-survival threshold:** single-user incident

`requires_cpo_signoff: true`. `soleur:engineering:review:user-impact-reviewer` runs at review time. CTO assessed the design at plan time (Domain Review).

## Infrastructure (IaC)

### Terraform changes

None. No `.tf` file, provider, variable or secret changes.

### Apply path

Not applicable: no resource is created or replaced. The only delivery is the existing push-triggered `apply-deploy-pipeline-fix.yml` path for `apps/web-platform/infra/ci-deploy.sh`, which fires on
merge, and merge is held for the owner's typed go. Expected blast radius at delivery: none for a flag-off fleet (the self-gate is only called when the flag resolves https; the flag is off after the revert).

### Host fan-out

No new provisioner or host artifact. `ci-deploy.sh` is delivered to web-1 (`deploy_pipeline_fix`) and web-2 (`deploy_pipeline_fix_web2`, in-place write, #10856); both hosts get the same file.

### Distinctness / drift safeguards

Unchanged. After the owner's merge, `scripts/check-deploy-script-parity.sh` compares `.ci_deploy_sha256` with `git show origin/main:apps/web-platform/infra/ci-deploy.sh | sha256sum`.

### Vendor-tier reality check

Not applicable.

## Implementation Phases

Order follows `cq-write-failing-tests-before`: the honest doubles and the rows land first and are shown RED on unmodified `ci-deploy.sh`, then the fix.
Every suite runs one at a time with stdin from `/dev/null`.

**Phase 0 - the corpus ratchet the plan already moved.** First work commit: `BASELINE_DECLARED_PROBES` 76 to 77 in `plugins/soleur/test/preflight-discoverability-test.test.ts` with a PLACEMENT / TRUTH / NO SUBSTITUTE comment entry (this plan declares `credentials_required`,
so the corpus count moved the moment the plan was committed; the bump must not be skipped with `LEFTHOOK_EXCLUDE`; re-read the live value after rebasing onto `origin/main`).

**Phase 1 - the honest doubles (tests only).**
1.1 create `apps/web-platform/infra/test-fixtures/curl-w-profiles.sh`: the profile table (values from `curl-w-measurements.md`, comment cites the file and the three curl builds, no `num_connects` column: it is never printed), the raw profiles, `req_partial` (rc 18, `200|0.000329|0.012484|0`) and `status_partial` (rc 18, `502|0.000110|0.007349|0`), both measured on curl 8.5.0 and added to the evidence file, and the one printer (unknown variable or profile: stderr message, exit 99, sentinel file; profile file path overridable by `CURL_W_PROFILES_FILE`);
1.2 `inngest-link-resolver.test.sh`: rebuild `$BIN/curl` to source the shared file, per-attempt selection via `FX_CURL_PROFILES=<p1,p2,...>` (the last repeats), keep `FX_CURL_FAIL_FIRST`, `FX_CURL_ALWAYS_OK`, `FX_CURL_CODE` and the `-k` / fingerprint behaviour but route every outcome through the printer (a failing outcome prints `verify18`, not nothing); a Sentry POST (no `-w`) passes through silently; assert the sentinel is absent after every row (the mock heredoc bakes the absolute fixture and sentinel paths in at creation and uses `source ... || exit 98`, so an unset variable or a failed source cannot hide as one more failed attempt);
1.3 `ci-deploy.test.sh`: the unified mock's https self-gate route (`*"8443/health"*` ahead of the generic `/health` route) sources the same shared file, with `MOCK_IL_SELFGATE_PROFILE` (default `ok200`), and the same sentinel assertion.

**Phase 2 - rows, mutation rows, real-curl differential (tests only), then RED.** In the resolver suite: rows S1 to S9 and H6/H7/H8 as in `## Test Scenarios`; the `kill_mut` rows of `## Guard Contract`; register rows in `ROW_IDS`. In `ci-deploy.test.sh`: two end-to-end rows (a flag-on deploy with `MOCK_IL_SELFGATE_PROFILE=raw_short3`, rc 0 and code 200, must still reach `docker run`; and the failure row, flag on,
`MOCK_IL_SELFGATE_PROFILE=req_reset`: non-zero exit, reason `inngest_link_selfgate_failed`, no `docker run`, the logged event line matches the anchored grammar with `phase=request tcp=3 tls=3 verify=0`).
**RED evidence (required):** run both suites on unmodified `ci-deploy.sh`; the new S rows and the end-to-end rows go RED, every pre-existing row stays GREEN (the mutation rows are NOT part of the RED claim: their anchors are absent before the fix, so they would be RED for the wrong reason; they are proven after the fix in the three steps of the Guard Contract) (the stub change must not move an old row). The exact `MIN_ROWS` and `CI_DEPLOY_ASSERT_FLOOR`
counters are NOT part of the RED claim (they are set after green, Phase 5). The RED commit stays local: it cannot pass the pre-push ratchet lane, so it is pushed only together with the fix commit. Record the FAIL lines in the commit message.

**Phase 3 - the fix.** `apps/web-platform/infra/ci-deploy.sh`, inside the `inngest-link-resolver` markers: `_inngest_link_selfgate_phase` (zero tests inlined with regex variables, no second helper), the new `-w`, the parse and validation, the per-attempt `tcp` / `tls` counters, the `verify` capture and coercion, the event with
the appended fields; update the self-gate header comment (what each field means, the reading rule, that `request` does not prove a cause). **Re-anchor the existing mutation rows that match the old text**: M18a to M18e and M05c (exact anchors on `code="$(timeout 20 curl --disable`, `"$code" == 200`, the `sleep 2` / `i=$((i + 1))` block and the `--cacert` line) must still hit the new text.
No change to success semantics, retry, timeouts, or flags other than the `-w` string.

**Phase 4 - docs.** Runbook `inngest-server.md` (`selfgate_failed` row plus a "Reading `selfgate_failed`" decode table with a retry column, the flapping rule, the `unknown` decode and the proof limits), `deploy-status-debugging.md` (one row), ADR-294 addendum (`Addendum (2026-10-23, the second flip attempt)`, at most 8 lines, measured facts only),
`canary-probe-set.md` only if a cross-reference is needed (grep first; skip if none).

**Phase 5 - ratchets (each re-measured from a green run, never by reasoning).** `MIN_ROWS` in the resolver suite (exact); `CI_DEPLOY_ASSERT_FLOOR` in `ci-deploy.test.sh` (raise to the measured total);
`bash plugins/soleur/test/fixture-relative-assert.test.sh` (regenerate with `--write-baseline` only if it reds, and only the rows this diff earned); `PJ_TRIPLES` / `PRODUCER_JOIN` in `.claude/hooks/grep-q-pipe-guard.test.sh`
(run its suite; add a justified `PRODUCER_JOIN` line only if a new test-file/verb/producer triple appears); then `bash scripts/pre-push-ratchet-lane.sh`, `python3 scripts/lint-guard-contract.py`, `python3 scripts/lint-trap-tempfile-ownership.py --check-highwater`,
`bash plugins/soleur/test/c4-count-parity.test.sh`, `bash scripts/lint-orphan-test-suites.sh` (the shared fixture file is not a suite; confirm it is not reported), `shellcheck`, `bash -n apps/web-platform/infra/ci-deploy.sh`.

**Phase 6 - CI-userland run, review, QA, stop.** Run the two suites inside `ubuntu:24.04` once (install step in Technical Considerations); `soleur:review` (user-impact-reviewer, observability-coverage-reviewer, test-design-reviewer),
`soleur:qa`, green CI via Monitor, `soleur:ship` with `--stop-before-merge` semantics; PR body discloses the proof limits (below) and #10856; end with a `Paused:` line asking for a typed go that names the merge and stating the owner's preconditions for the third flip:
`scripts/check-deploy-script-parity.sh` green on web-1 AND web-2 (an old script on either host emits the same unreadable event), and the immediate-before-merge idle check of Technical Considerations.

## Files to Edit

- `apps/web-platform/infra/ci-deploy.sh` - the self-gate, its phase helper and header comment (inside the `inngest-link-resolver` block).
- `apps/web-platform/infra/inngest-link-resolver.test.sh` - honest curl stub on the shared profiles, rows S1 to S9, H6, H7, H8, mutation rows, re-anchored M18a to M18e and M05c, `ROW_IDS`, `MIN_ROWS`.
- `apps/web-platform/infra/ci-deploy.test.sh` - unified curl mock's https route on the shared profiles and `MOCK_IL_SELFGATE_PROFILE`, one end-to-end row, `CI_DEPLOY_ASSERT_FLOOR`.
- `knowledge-base/engineering/operations/runbooks/inngest-server.md` - `selfgate_failed` row and the decode table.
- `plugins/soleur/skills/postmerge/references/deploy-status-debugging.md` - a row for `inngest_link_selfgate_failed`.
- `knowledge-base/engineering/architecture/decisions/ADR-294-inngest-link-tls-terminator-and-flagged-flip.md` - second-flip addendum (8 lines at most).
- `plugins/soleur/test/preflight-discoverability-test.test.ts` - `BASELINE_DECLARED_PROBES` 76 to 77 and its comment entry (Phase 0).
- `plugins/soleur/test/fixture-relative-assert.baseline.txt` - only if the check reds on rows this diff earned.
- `.claude/hooks/grep-q-pipe-guard.test.sh` - only if a new triple appears (`PJ_TRIPLES`, `PRODUCER_JOIN`).

## Files to Create

- `apps/web-platform/infra/test-fixtures/curl-w-profiles.sh` - the shared profile table and printer sourced by both curl doubles (a test fixture, never delivered to a host).
- `knowledge-base/project/specs/feat-one-shot-inngest-selfgate-phase/curl-w-measurements.md` - the measurement evidence (created at plan time).
- `knowledge-base/project/specs/feat-one-shot-inngest-selfgate-phase/decision-challenges.md` - the ruled forks (created at plan time).
- `knowledge-base/project/specs/feat-one-shot-inngest-selfgate-phase/tasks.md` - the task breakdown.
- A learning from the compound step at ship time (path chosen then).

## Open Code-Review Overlap

None. Queried 95 open `code-review` issues for each planned path; no body names any of the nine edited files.

## Guard Contract

### Guard 1 - the self-gate's verdict is unchanged and its event names the stage the last attempt reached

**Property.** `_inngest_link_selfgate` returns 0 exactly when curl exits 0 and the first token of its `-w` output is `200` (decided before any validation of the other fields), and every failure emits one `selfgate_failed` event whose `phase`, `tcp`, `tls` and `verify`
fields are drawn only from a seven-token set and integers 0 to 99 (`verify` forced to 0 unless `phase=verify`; `http=` only from a validated three-digit token, else `none`), naming the stage the last attempt reached, with `unknown` (never a success-looking token) for anything unparsable.

**Assembly.** The property quantifies over: (1) the single curl call site and the single `inngest_link_event selfgate_failed` emit in `_inngest_link_selfgate` (`git grep -c 'INNGEST_LINK_HTTPS_URL/health' apps/web-platform/infra/ci-deploy.sh` is 1, measured at plan time;
`_inngest_link_selfgate` has one call site, in `resolve_inngest_link`, and the suite pins that count); (2) the parse, the validation and the phase helper, the only code that reads the `-w` line; (3) the three doubles of curl that must agree on the format
and the profile values: the resolver suite's `$BIN/curl` and the unified mock in `ci-deploy.test.sh` (both sourcing the one shared file, so there is one table and one printer) and real curl (the H6 differential); (4) the per-attempt loop (attempt order is the lifetime the
`phase` = last attempt property lives in); (5) the sinks the event reaches: the journald line, the host-local syslog copy `logger` also writes, Better Stack and Sentry `extra.detail`. Members drift; the chokepoints are the one call site, the one helper and the one table.

**Mutation matrix.** Each row must drive the named rows RED; rows M22a to M22c, M22j and M22m are derived from the design (the seven-token map, the order of attempts and the verdict), not from the code's current shape. Every anchor must occur exactly once inside the `_inngest_link_selfgate*` text of the block (the block also holds canary code with similar tokens), and each row is proven in THREE steps after the fix: the named rows are GREEN on the pristine block, the mutation kills them, and the anchor count in the self-gate text is 1.

| # | Mutation (applied to a copy of the block) | Must redden |
|---|---|---|
| M22a | precedence swap: test `time_appconnect` zero before rc 60 (a verify failure reads `handshake`) | S2 (verify profiles) |
| M22b | `time_connect` zero test dropped (a refused connection reads `handshake`) | S1 (connect profiles) |
| M22c | the `status` branch dropped (a TLS-verified 502 reads `request`) | S3 (`status502` asserts `phase=status` on the whole line) |
| M22d | the unparsable arm defaults to `request` instead of `unknown` (the #10874 default-hides-the-defect shape) | S6 (`raw_garbage`, `raw_short3` with rc 56) |
| M22e | the rc 124 / empty-output arm dropped (an empty line with rc 124 reads `connect`) | S6 (`raw_empty` with rc 124 and rc 2) |
| M22f | the time shape check dropped (a non-numeric time is zero-tested as zero) | S6 (`raw_nonnum`) |
| M22g | the rc 77 arm dropped (`ca_file` reads `handshake`) | S1 (`ca_file` profile) |
| M22h | the rc 60 arm dropped (a verify failure reads `handshake`) | S2 (verify profiles) |
| M22i | the time-zero test inverted (zero reads as TLS complete) | S1, S2, S3 |
| M22j | phase taken from the FIRST failed attempt instead of the last (an order mutation) | S4 (three different profiles in sequence: connect, handshake, request) |
| M22k | `tls` counter increments on `time_connect` (counts TCP as TLS) | S4 |
| M22l | clamp removed from `tcp` / `tls` (`SG_ATTEMPTS=120`) | S4b (clamp row) |
| M22m | success decided on `[[ "$out" == 200 ]]` (whole output) instead of the first token | A2, S8 (success row) |
| M22n | success gated on the full shape check of all four fields (a healthy listener with a short `-w` line fails the gate) | S8 (`ok200_comma_extra`, `raw_short3` with rc 0 and code 200) |
| M22o | the event appends `url=$INNGEST_LINK_HTTPS_URL` (the URL leaks) | S5 (anchored grammar, journald and Sentry sinks) |
| M22p | the final `request` arm keyed on rc (`52` or `28` only) instead of the times (the pre-ratification shape) | S3b (same times, rc 56 and rc 1 must still read `request`) |
| M22q | `verify` printed raw instead of coerced to 0 outside `phase=verify` (a handshake failure prints `verify=1`) | S2 (whole line) |
| M22r | `http=` printed from the raw first token (`${code:-none}` as before, unvalidated) | S6 (`raw_garbage`: `http=none`) |
| M22s | `status` taken for any code other than 000 (a truncated 200 reads `status`) | S3 (`req_partial`: rc 18, code 200, expects `request`) |
| M22t | `status` additionally gated on rc 0 (a truncated 502 reads `request`) | S3 (`status_partial`: rc 18, code 502, expects `status`) |

**Harness rows.** Harness edits that MUST redden the suite: H1 extended: with `CURL_ALWAYS_OK=1` the new phase rows go RED too (a suite that cannot see an always-success curl proves nothing); H8: with `CURL_PROFILES_IGNORED=1` (the stub always prints `ok200` regardless of `FX_CURL_PROFILES`) S1 to S4 go RED; H9: H6 run against a COPY of the profile file (path overridable by `CURL_W_PROFILES_FILE`) with one value flipped goes RED (the differential row detects a drifting table).
Must-PASS input that is not the canonical: `ok200_comma_extra` (comma decimal separator, no trailing newline, one extra trailing token) still passes the gate and the same failing profile with commas still maps to its phase (S8). H7: the printer exits 99 and drops the sentinel on `%{errormsg}` and on an unknown profile (a through-the-function control row sends an unknown variable and expects the sentinel to appear; the mock heredoc bakes the absolute fixture and sentinel paths in at creation and uses `source ... || exit 98`),
and every MEASURED profile prints `^[0-9]{3} [0-9]+\.[0-9]{6} [0-9]+\.[0-9]{6} [0-9]+$`. **H6 mechanics:** its own `PATH` with a passthrough shim around REAL curl that logs stdout and rc (the function swallows both) plus `sleep` and `logger` stubs only (not `$BIN/curl`), `INNGEST_LINK_HTTPS_URL` overridden after sourcing, a certificate with `IP:127.0.0.1` in its SAN, listeners bound to port 0 with a readiness poll (no fixed sleeps), `SG_ATTEMPTS=1`, clean proxy environment; "rc class" means exact rc except that 52 and 56 form one class.

**Anchor.** The profile values are anchored outside the commit's own edit by the real-curl differential (H6), which prints what the installed curl prints for each of six phases, and by the evidence file (a record of the measurements, not parsed by a row); a one-diff edit of a covered profile that does not match real curl reds H6 (proved by H9).
The uncovered profiles (RST, empty CA file, truncated body, the hang phases) rest on the evidence file alone: stated in the runbook as a proof limit. A `>= N` floor survives substitution, so `MIN_ROWS` is an exact count and the profile names are asserted as a set (S1 to S4 each iterate the named set and the table is checked for exactly those names).

## Observability

```yaml
liveness_signal:
  what: per web host and per flag-on deploy that reaches the self-gate, the existing INNGEST_LINK journald rows; a failed gate now carries class=selfgate_failed with phase=, tcp=, tls=, verify= (a passing gate emits no row of its own: the next row, class=resolved, proves the resolver ran)
  cadence: once per flag-on deploy per host (not periodic); the self-gate is not called with the flag off
  alert_target: none today for op=inngest-link (#10556, tracked); the flip run and the release run fail non-zero with the constant reason inngest_link_selfgate_failed (synchronous, layer 6); the rows are read in Better Stack
  configured_in: apps/web-platform/infra/ci-deploy.sh (inngest_link_event); shipped by apps/web-platform/infra/vector.toml Source 4 (tag ci-deploy), unchanged
error_reporting:
  destination: Better Stack Logs via the journald tag ci-deploy (layer 3) and Sentry (feature=ci-deploy, op=inngest-link, classification=selfgate_failed) for the error event (the existing inngest_link_event path)
  fail_loud: a failed strict deploy exits non-zero with the constant reason inngest_link_selfgate_failed in the run log (layer 6), and the event carries the discriminating fields (layer 3 and Sentry)
failure_modes:
  - mode: the listener is unreachable (stopped terminator, firewall drop, wrong address)
    detection: phase=connect with tcp=0 tls=0 (rc 7 or rc 28 in the same event, rc is needed to tell them apart; tcp and tls count against attempts=); one event discriminates it from every later stage (layer 3 vector/Better Stack and Sentry); first read: the Inngest host's `tls-health` phone-home rows (`listener`, `nrestarts`, `bind`; layer 3, a direct POST independent of the journald shipper)
    alert_route: none today (#10556); failed release or flip run (layer 6 workflow run log, which carries only the constant reason, so the phase is read in Better Stack before any re-flip)
  - mode: TCP is accepted but TLS does not complete (terminator crash loop, plaintext on the TLS port, a stalled handshake)
    detection: phase=handshake with tcp>=1 tls=0 (layer 3)
    alert_route: none today (#10556); failed release or flip run (layer 6 workflow run log, which carries only the constant reason, so the phase is read in Better Stack before any re-flip)
  - mode: the pinned CA does not verify the served certificate (cert re-mint without a CA re-publish, expired cert, SAN without the IP)
    detection: phase=verify with verify=18 (the served certificate is a different self-signed certificate than the pin: the pinned file is a self-signed leaf by design, so a re-mint without a re-publish reads 18), 10 (expired) or 1 (hostname/SAN mismatch); 19, 20 and 21 mean the served chain is not the designed self-signed shape and read as unexpected (layer 3); first read: `tls-health` `served_sha256` against `cert_sha256`
    alert_route: none today (#10556); failed release or flip run (layer 6 workflow run log, which carries only the constant reason, so the phase is read in Better Stack before any re-flip)
  - mode: TLS verified, then no HTTP status (the terminator reset or closed the session: its upstream 127.0.0.1:8288 refused or closed, or the app answered nothing)
    detection: phase=request with tls>=1 verify=0 (the incident signature; rc 56, 52 or 28, and rc 18 with a 200 code) - check the terminator and its upstream, not the certificate; the event does not prove which (layer 3); first read: `tls-health` `unit`, `nrestarts`, `listener` of the Inngest host for the same window, the only terminator state shipped today (no SSH step; SSH is the owner's decision only after these reads)
    alert_route: none today (#10556); failed release or flip run (layer 6 workflow run log, which carries only the constant reason, so the phase is read in Better Stack before any re-flip)
  - mode: TLS verified and the app answered a non-200 status
    detection: phase=status with an http= value (layer 3)
    alert_route: none today (#10556); failed release or flip run (layer 6 workflow run log, which carries only the constant reason, so the phase is read in Better Stack before any re-flip)
  - mode: the listener changes state across the three attempts (a terminator restart between tries)
    detection: tcp or tls below attempts while tls>=1, or a last phase that differs from what the counts imply (for example phase=handshake with tls>=1): read it as an unstable or restarting listener, not as the last token alone; the runbook carries one worked line per mixed pattern (layer 3)
    alert_route: none today (#10556); failed release or flip run (layer 6)
  - mode: a field is unparsable (timeout kill, an unexpected curl)
    detection: phase=unknown with tcp=0 tls=0 does NOT mean connect failed (unparsable attempts count nothing); rc=124 is the timeout wrapper killing curl, rc=2 an unreadable CA file on curl 8.23, rc=0 a changed curl output format; http=none (layer 3)
    alert_route: none (read after the next flip)
  - mode: the event line leaks a value
    detection: the anchored-regex row S5 (CI) is the prevention; a leak would ride layer 3 and Sentry extra.detail, so the post-flip read checks that every field after attempts= is a token from the set or an integer
    alert_route: CI red
logs:
  where: Better Stack Logs (Vector Source 4, journald tag ci-deploy), the host-local syslog copy `logger` also writes, and Sentry (op=inngest-link)
  retention: Better Stack Logs source retention and Sentry project retention (existing)
discoverability_test:
  command: doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh --since 7d --grep 'INNGEST_LINK: class=' --limit 1
  expected_output: class=
  credentials_required: BETTERSTACK_QUERY_HOST, BETTERSTACK_QUERY_USERNAME and BETTERSTACK_QUERY_PASSWORD (ClickHouse read credentials in Doppler soleur/prd_terraform) - Better Stack warehouse reads have no anonymous path and the ingest token is write-only, so no unauthenticated probe verifies the same property. The command is a CHANNEL probe: it reads the channel the new fields ship through (existing INNGEST_LINK rows such as class=resolved) and is satisfied with or without this change; the new fields exist only after delivery and a failed flip, and are read with --grep 'class=selfgate_failed' (the integration rows S1 to S4 and the end-to-end row are the CI proof that the code emits them). This pipeline does not run the probe. Check that the 7-day query fits the 15-second cap at work time
```

Layers cited: 3 (Vector journald shipper to Better Stack, plus the Sentry POST from `inngest_link_event`) and 6 (the release or flip run log, a constant reason only).
Stated limit: the phase and counts are asynchronous (layer 3); the run log carries one constant reason for every self-gate failure. The terminator's own journald is not shipped (#10880), so the cause behind `phase=request` is not readable without it.

## Domain Review

**Domains relevant:** engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** the CTO agent ruled F1 to F5 on 2026-10-23 (see `decision-challenges.md`): derived `phase=` plus `tcp= tls= verify=` appended after the unchanged prefix, no raw timings; derivation from one `-w` line with shape validation and `unknown` on any parse failure;
one curl per attempt with no second probe; honest doubles that refuse unknown variables and profiles, plus a real-curl differential asserting phase class rather than exact rc, with a missing tool failing under `CI`; ratchet bumps re-measured, plus a grep for full-string consumers of the
event (done: none). CTO risks adopted: word `phase=request` as "check the terminator and its upstream, not the certificate"; the stub's unknown profile never defaults to success; the phase describes the last attempt only, the counts cover all.
No product, marketing, finance, sales, support, legal or operations surface: infrastructure and tooling change.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "have `selfgate_failed` name the phase that failed, with fixed-token numeric fields only (no values, no URL), for example curl's `%{time_connect}`, `%{time_appconnect}`, `%{ssl_verify_result}` and the number of attempts that reached the TLS stage, clamped like the canary integers" [issue #10934] | Phase 3 (`ci-deploy.sh`), `## Proposed Solution` | mapped |
| 2 | "Add rows to `ci-deploy.test.sh` with a stub curl for each phase" [issue #10934] | Phases 1 to 2: per-phase rows in `inngest-link-resolver.test.sh` (where the self-gate is exercised, see Research Reconciliation) and the honest mock plus an end-to-end row in `ci-deploy.test.sh` | mapped |
| 3 | "a decode row in `inngest-server.md` (the `selfgate_failed` row currently lists three causes)" [issue #10934] | Phase 4 (runbook row and decode table) | mapped |
| 4 | "and a mutation row" [issue #10934] | Guard Contract matrix M22a to M22t as `kill_mut` rows | mapped |
| 5 | "keep the mock honest: model what real curl prints for each phase and MEASURE the `-w` variables against a real local curl/TLS server before relying on them" [brief] | `curl-w-measurements.md`, profile table, H6 differential, H7 | mapped |
| 6 | "Check the host's curl version constraint: `%{errormsg}` needs curl 7.75+, so measure which `-w` variables exist on the curl the hosts run (the host curl version has not been read; do not assume)" [brief] | Technical Considerations, measured on three builds, allowlist row S7; the host itself is not read | mapped |
| 7 | "Technical forks go to the CTO agent (soleur:engineering:cto)" [brief] | `decision-challenges.md` rows F1 to F5 | mapped |
| 8 | "expect the same ratchets to need bumping and check each" [brief] | Phase 5 | mapped |
| 9 | "arm nothing, MERGE NOTHING ... do not run or dispatch the flip workflow, no Doppler writes, no production writes or reads. Stop before merge" [brief] | Acceptance Criteria (process), Phase 6 | mapped |
| 10 | "Related open issues: #10880 ..., #10556 ..., #10543 ..., #10856 ..." [brief] | context only; #10880 and #10556 are the issue's own "Out of scope"; #10856 is disclosed in the PR body; #10543 is unrelated to this diff | descoped - justification: each is named out of scope by the issue or does not touch the diff |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `ci-deploy.sh` self-gate change | "have `selfgate_failed` name the phase that failed" | asked |
| `_inngest_link_selfgate_phase` helper and `_inngest_link_time_nonzero` | "name the phase that failed" (asks 1) | asked |
| `inngest-link-resolver.test.sh` profile table, honest stub, rows S1 to S9 | "Add rows ... with a stub curl for each phase" (asks 2) | asked |
| mutation rows M22a to M22t | "and a mutation row" (asks 4) | asked |
| H6 real-curl differential, H7 stub refusals | "MEASURE the `-w` variables against a real local curl/TLS server before relying on them" (asks 5) | asked |
| `ci-deploy.test.sh` unified mock `-w` interpreter and one end-to-end row | "keep the mock honest: model what real curl prints for each phase" (asks 5) | asked |
| `apps/web-platform/infra/test-fixtures/curl-w-profiles.sh` shared profile table and printer | "keep the mock honest: model what real curl prints for each phase" (asks 5) | asked |
| runbook `selfgate_failed` row and decode table | "a decode row in `inngest-server.md`" (asks 3) | asked |
| `curl-w-measurements.md` | "MEASURE the `-w` variables" (asks 5) | asked |
| `decision-challenges.md` | "Technical forks go to the CTO agent" (asks 7) | asked |
| ratchet bumps (`MIN_ROWS`, `CI_DEPLOY_ASSERT_FLOOR`, `BASELINE_DECLARED_PROBES`, baselines) | "expect the same ratchets to need bumping and check each" (asks 8) | asked |
| `deploy-status-debugging.md` row for `inngest_link_selfgate_failed` | - | inferred - justification: the failed run's log carries only the constant reason, and that reason has no row in the table the postmerge skill reads, so an operator would not reach the new decode; without the row the decode is unreachable from the log |
| ADR-294 second-flip addendum | - | inferred - justification: the two earlier flip attempts each got an addendum recording what was observed and what is not established; skipping it leaves the recorded history one attempt behind and the wording of "request" unqualified |
| `tasks.md` | - | inferred - justification: the pipeline's work phase consumes it |

### Split Assessment

- Subsystems touched: 3 to 4 - `apps/web-platform`, `knowledge-base`, `plugins/soleur`, and `.claude` only if `PJ_TRIPLES` moves
- Planned files: 12 | Estimated changed lines: about 650 (resolver suite about 350, `ci-deploy.sh` about 60, `ci-deploy.test.sh` about 60, docs about 120, ratchets about 30, the two spec files about 120)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR. If the `.claude` root joins it reaches the root threshold, but the ratchet files pin the sibling edit (a split would leave the first PR red on its own counters), the lines and files are far under the other two thresholds, and `.claude` is touched only by a count bump.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `_inngest_link_selfgate` requests `-w '%{http_code} %{time_connect} %{time_appconnect} %{ssl_verify_result}'` and keeps every other flag, the 3 attempts, `sleep 2`, 5 s / 10 s / 20 s timers, `--disable --noproxy '*'`, `--cacert "$1"`, no `-k`, no `--capath`.
- [ ] The success predicate is `rc==0` and the first token `200`, decided before any validation of the other fields; M18b, M22m and M22n are RED when it is loosened, changed or gated on the full shape.
- [ ] The failure event reads `INNGEST_LINK: class=selfgate_failed level=error rc=<n> http=<ddd|none> attempts=<n> phase=<token> tcp=<n> tls=<n> verify=<n>`; the first three fields are byte-identical to today's apart from `http=` now coming from a validated token; the anchored regex row S5 passes for every profile on the journald and Sentry sinks and rejects an appended `url=` (M22o RED).
- [ ] Every measured phase maps to its token through the stub, and through real curl for the six H6 scenarios: connect (closed port), handshake (accept and close), verify with `verify=18` (pinned-certificate mismatch), request (TLS then clean close), status (502) and the 200 pass; `ca_file` and RST rest on the stub and the evidence file; `unknown` for empty output, rc 124, rc 2, a short field count and a non-numeric time.
- [ ] `verify=` is 0 unless `phase=verify` (M22q RED when printed raw); `http=none` for a non-numeric first token (M22r RED); the same times with rc 52, 56 and 1 give `request` (M22p RED); code 200 with rc 18 gives `request`, never `status` (M22s RED), and code 502 with rc 18 stays `status` (M22t RED).
- [ ] A mixed sequence (connect, handshake, request across three attempts) reports `phase=request tcp=2 tls=1`; a flapping fixture pins the runbook's worked lines.
- [ ] A comma decimal separator, a missing trailing newline and an extra trailing token still parse (S8, S8b), and a healthy listener with a short `-w` line still passes the gate.
- [ ] The `-w` variable names in `ci-deploy.sh` are a subset of the four-name allowlist (S7); the shared printer exits 99 and drops a sentinel on an unknown variable or profile, prints no trailing newline, and every suite asserts the sentinel absent after each row (H7).
- [ ] The H6 real-curl differential runs in CI (a missing curl, python3 or openssl under `CI` is a failure, not a skip); locally an absent tool is a counted skip that keeps the exact `MIN_ROWS` consistent.
- [ ] `curl-w-measurements.md` exists; the profile values in `curl-w-profiles.sh` are copied from it and checked against real curl by H6 for the six covered phases (not parsed from the markdown); the uncovered profiles are named as a proof limit in the runbook.
- [ ] RED evidence is recorded: on unmodified `ci-deploy.sh` the S rows and the end-to-end rows are RED and every pre-existing row is GREEN (the exact counters and the mutation rows are excluded from that claim); the same suites are GREEN after the fix; each mutation row is proven after the fix in three steps (named rows GREEN on the pristine block, the mutation kills them, the anchor occurs once inside the self-gate text); M18a to M18e and M05c are re-anchored and still RED when mutated.
- [ ] Both changed suites pass once inside `docker run --rm -v "$PWD":/w ubuntu:24.04` after the apt install step (curl 8.5.0, bash 5.2); `bash -n` and `shellcheck` are clean on `ci-deploy.sh`.
- [ ] Ratchets re-measured from green runs and moved only as earned: `BASELINE_DECLARED_PROBES` equal to the live value plus one with a PLACEMENT / TRUTH / NO SUBSTITUTE entry (first commit), `MIN_ROWS` exact in the resolver suite, `CI_DEPLOY_ASSERT_FLOOR` in `ci-deploy.test.sh`, `fixture-relative-assert.test.sh` green (baseline regenerated only if it reddened, rows this diff earned), `grep-q-pipe-guard.test.sh` green (`PJ_TRIPLES` / `PRODUCER_JOIN` moved only if a triple appeared), `scripts/pre-push-ratchet-lane.sh` green, `lint-guard-contract.py` green, `lint-trap-tempfile-ownership.py --check-highwater` unchanged, `c4-count-parity.test.sh` green, `lint-orphan-test-suites.sh` does not report the shared fixture file.
- [ ] Runbook: the `selfgate_failed` row and the decode table cover every field and every token, name a first no-SSH read per token (connect, handshake, request: the Inngest host's `tls-health` rows `listener`, `nrestarts`, `bind`, with the exact `betterstack-query.sh --grep stage=tls-health` form the runbook already documents; verify: `served_sha256` against `cert_sha256`), list `verify` 18, 10, 1 and the unexpected 19, 20, 21 (the pinned file is a self-signed leaf by design, so 18 means a different self-signed certificate), state that `attempts=` is the denominator for `tcp` and `tls` and that `rc` is needed to separate rc 7 from rc 28 when `tcp=0`, give a retry column (deterministic phases fail the same way on a re-flip; a mixed pattern may pass, and each retry costs two host swaps), a flapping rule, the `unknown` decode and the proof limits (hang phases, RST and the empty CA file are stub-only; the stunnel signature is measured on curl 8.5.0 only), state the `verify` reading rule and the unlisted-code case,
  word `phase=request` as "TLS verified, no HTTP response: check the terminator and its upstream, not the certificate, and no cause is readable until #10880 ships the Inngest host's journald", point at the existing read-only `/hooks/inngest-tls-handshake` call already documented in the runbook, and carry no SSH step; `deploy-status-debugging.md` has one `inngest_link_selfgate_failed` row that says the phase is only in Better Stack (the run log carries the constant reason, `INNGEST_LINK_REASON` is enum-checked) and to read `--grep 'class=selfgate_failed'` before any re-flip; ADR-294 has an addendum of at most 8 lines with measured facts only and the unmeasured parts named.
- [ ] `decision-challenges.md` carries one row per ruled fork (F1 to F5, F2a, R3a to R3d) and `technical-ruling-gate.sh --branch` passes; no row is `pending`.
- [ ] Nothing merged, armed, dispatched or written in Doppler or production; the PR body names the proof limits and #10856; the pipeline ends with a `Paused:` line asking for a typed go that names the merge and stating the owner's preconditions for the third flip (parity green on both hosts; the idle check immediately before the merge).

### Post-merge (owner's session, not this pipeline)

- [ ] After the owner's go and the delivery to both hosts, `scripts/check-deploy-script-parity.sh` shows both hosts on the merged `ci-deploy.sh` BEFORE any third flip; on the next flip a failed self-gate (if any) is read with `--grep 'class=selfgate_failed'` per the runbook decode table.

## Test Scenarios

Resolver suite (`apps/web-platform/infra/inngest-link-resolver.test.sh`, rows run against the real block under the honest stub; every row asserts the printer sentinel is absent afterwards; the logger stub records `$*`, so S5 strips the leading `-t ci-deploy` argument pair before matching):

- **Whole-line rule (applies to S1 to S6):** each row compares the ENTIRE logged `INNGEST_LINK: class=selfgate_failed ...` line to an expected string, never a substring; the counter fields get a world where the count differs from its flag form (`tcp=2 tls=1`, S4), one where `tls=0` while `tcp` is not (handshake profiles), and one where both are 0 (connect profiles).
- **Attempt count:** `scenario()` defaults `SG_ATTEMPTS` to 2, so every row pins it: 1 for single-attempt rows (so `tcp` and `tls` read 0 or 1), 3 for S4, 120 for the clamp row.
- **S1 connect and ca_file:** profiles `refused` (rc 7), `fw_drop` (rc 28, time_connect 0), `ca_file` (rc 77): phase `connect`, `connect`, `ca_file`, with tcp/tls 0/0, 0/0, 1/0 and `verify=0` (raw value 1 on `ca_file` is suppressed).
- **S2 handshake and verify:** `hs_close`, `hs_rst`, `hs_plain` (rc 35), `hs_hang` (rc 28): `handshake` with tcp 1 tls 0 and `verify=0`; `verify18`, `verify10`, `verify1_san` (rc 60): `verify` with `verify=18`, `10`, `1`.
- **S3 request and status:** `req_reset` (rc 56, the incident signature), `req_empty` (rc 52), `req_hang` (rc 28), `req_http09` (rc 1), `req_partial` (rc 18, code 200): `request` with tcp 1 tls 1 verify 0 (the runbook reads `http=200 phase=request` as "200 header, body cut short", not healthy); `status_partial` (rc 18, code 502): `status`; `status502`: `phase=status http=502` (this row asserts the phase, so M22c can redden it); TLS-complete with a non-200 code still fails the gate.
- **S3b version independence (CTO amendment):** the SAME times (`0.000138 0.004360`, verify 0, code 000) with rc 52, rc 56 and rc 1 all give `phase=request`; `status` is taken from the validated 3-digit code, never from rc alone.
- **S4 sequence:** connect, handshake, request across three attempts gives `phase=request tcp=2 tls=1`; plus a flapping fixture (request, connect, request) pinning the worked lines the runbook quotes.
- **S5 grammar:** the anchored regex `^INNGEST_LINK: class=selfgate_failed level=error rc=[0-9]{1,3} http=([0-9]{3}|none) attempts=[0-9]{1,3} phase=(connect|handshake|verify|ca_file|request|status|unknown) tcp=[0-9]{1,2} tls=[0-9]{1,2} verify=[0-9]{1,2}$` over every profile's event; no `10.0.1.40`, no `https://`; the same detail string is asserted on the Sentry sink (`KEEP_SENTRY=1`, the stub records the POST body: `extra.detail` equals the journald detail, tags carry `classification=selfgate_failed`), because "no value in the event" is about the whole event, not the logger call. The curl stub must pass a Sentry POST (no `-w`) through silently.
- **S6 unknown arms and validated values:** `raw_empty` with rc 124, `raw_empty` with rc 2, `raw_garbage` (`http=none`, never the raw token), `raw_short3`, `raw_nonnum` time: each row states its rc and expected whole line; a bad time field with rc 60 still reads `verify` and with a code 502 still reads `status` (the rc-only and code-only rules do not need the times); the gate still fails.
- **S7 allowlist:** the `-w` names in the block EQUAL the four names `http_code time_connect time_appconnect ssl_verify_result` (equality, not a subset check: a subset also passes before the fix and when a variable is dropped).
- **S8 / S8b non-canonical:** `ok200_comma_extra` passes the gate; a failing profile with commas maps correctly; `raw_short3` with rc 0 and code 200 still passes (success is decided before validation); a no-newline stub still yields all four fields.
- **S9 decode drift:** exactly seven tokens are extracted from the helper (the row asserts the count, so an empty set before the fix is RED) and each token and field name appears in the runbook decode table (a static grep row, proved against a known-bad copy of the doc, since `kill_mut` mutates the block and cannot reach the runbook), so the doc cannot silently lag the grammar.
- **H6 real curl:** the real function against real curl and a local python `ssl` server for six scenarios (closed port, accept-and-close, pinned-certificate mismatch, TLS then clean close, TLS 200, TLS 502); compares the stub profile with real curl on (rc class, code, zero-ness of connect and appconnect, verify).
- **H7 printer fidelity and H8 dispatch:** see `## Guard Contract` harness rows.

`ci-deploy.test.sh`: two end-to-end rows (flag on with `req_reset`: failure event, no `docker run`; flag on with `raw_short3` rc 0 code 200: reaches `docker run`) and the existing flag-on rows unchanged (the flag-on happy path already runs the default `ok200`) (the default profile `ok200` prints the full `-w` line); sentinel absent after each row.

## Precedent Diff (deepen-plan Phase 4.4)

| Pattern | Precedent on `main` | This plan |
|---|---|---|
| Fixed-token event with clamped integers | `inngest_link_canary_check` (`canary_failed ... url_lines= url_https= ca_lines= ca_ok=`, `_inngest_link_count99`) | same helper and clamp; tokens come from a pure helper, not inline `if` chains |
| Event grammar gets an anchored-regex row | resolver suite E7/E8 (exact line per cause, anchored grammar) | S5 on journald and Sentry sinks, whole-line rows S1 to S6 |
| A mock that models part of the tool | the 2026-10-22 learning (the mock docker ignored the env-file) | one shared printer, refusal plus sentinel, a real-curl differential (H6), a profile-file mutation (H9) |
| Real-tool harness row with an explicit skip count | H3 and H4 (node) in the resolver suite | H6 (curl, python `ssl`): the same `ROWS+=N; SKIP+=N` skip, but a failure under `CI` |
| Mutation rows through `kill_mut` over a copy of the block | M05x, M18x, M20x, M21x | M22a to M22t; anchors unique inside the self-gate text; proven after the fix |
| Counter or flag fields in a fixed-shape line | the 2026-10-18 wipe-assert learning (a count must differ from its flag form) | `tcp=2 tls=1`, `tls=0` beside `tcp=1`, both 0; whole-line pins |

No novel pattern: every shape above has a sibling on `main`.

## Dependencies & Risks

- **The host curl was not read.** The four variables predate curl 7.19, were measured on three builds, and an allowlist row pins them; a host curl older than 7.19 is not a supported Ubuntu userland. Residual accepted and named in the PR body.
- **`phase=request` can be over-read.** It means TLS verified and no HTTP status came back; it does not prove the upstream refused (the terminator's journald is not shipped, #10880). Wording is constrained by an AC and the runbook says "check, do not conclude".
- **The stub can drift from real curl.** Mitigated by H6 running real curl in CI and failing, not skipping, when a tool is missing under `CI`.
- **Ratchets move with unrelated PRs.** `BASELINE_DECLARED_PROBES` and the baselines are re-measured after rebasing onto `origin/main`, never by reasoning.
- **The block is shared by every deploy.** A parse error would break all deploys including a rollback: `bash -n`, shellcheck and the CI-userland run are acceptance criteria, and no non-ASCII or `$(...)`-inside-`[[ ]]` construct is added.
- **Delivery by in-place write (#10856).** A deploy running at the instant web-2's file lands could continue from a stale byte offset. Accepted, disclosed; a read-only idle check precedes the owner's go.
- **Proof limits to state in the PR.** Real stunnel measured on curl 8.5.0 only; the incident's cause is not established by this change (only the next failure will be readable); the hang phases are stub-only.

## Sharp Edges

- A `## User-Brand Impact` section that is empty, `TBD`, or lacks the threshold fails deepen-plan Phase 4.6; this plan's is filled with threshold `single-user incident`.
- The first field set after `attempts=` is appended, never inserted: any consumer that substring-matches `rc= http= attempts=` must keep working (A7 does).
- Do not default an unknown profile or an unknown `-w` variable in either stub to a 200 profile: a stub that "helpfully" succeeds is how #10874 hid.
- Do not assert exact rc for the TLS-close rows: 52 vs 56 differs by curl build; assert the phase class.
- `ssl_verify_result` is not a stage flag (1 is "unset" and appears in handshake, CA-file and SAN failures); only rc 60 makes it a verification code.
