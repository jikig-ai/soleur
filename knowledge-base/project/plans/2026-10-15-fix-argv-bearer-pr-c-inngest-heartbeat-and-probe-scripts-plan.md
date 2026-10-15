---
title: "fix(security): argv-bearer sweep PR C - inngest heartbeat URL and three probe scripts off curl argv"
type: fix
date: 2026-10-15
slug: argv-bearer-pr-c-inngest-heartbeat-and-probe-scripts
branch: feat-one-shot-argv-bearer-pr-c-inngest-probes
issue: 10120
refs: [10120, 10093, 9757]
priority: p3-low
domain: engineering
brand_survival_threshold: aggregate pattern
requires_cpo_signoff: false
lane: cross-domain
---

# fix(security): argv-bearer sweep PR C

Source plan (archived, PR C section only): `knowledge-base/project/plans/archive/20261014-173446-2026-10-13-fix-argv-bearer-followups-registry-inngest-probes-community-plan.md`.
PRs A (#10185, community write-env and S7) and B (#10322, registry template) are MERGED; this plan is the remaining PR C. Draft PR: #10356.
Every issue reference in the PR is `Ref #N` (#10120, #10093, #9757); no closing keyword anywhere, and the PR body carries the line `Ref #9757`.

## Overview

A Better Stack heartbeat URL carries its secret in the path, so any `curl ... "$URL"` puts it in `/proc/<pid>/cmdline` for the life of the child.
PR C removes the last four such sites and turns the sweep's residual allowlist into an empty set:

| Site | Shell | Today | After |
|---|---|---|---|
| `inngest-bootstrap.sh`, `HEARTBEATSCRIPTEOF` heredoc body (issue 10120) | POSIX sh (dash) | `exec /usr/bin/curl -gfsS --max-time 10 "$INNGEST_HEARTBEAT_URL"` | judged by an https-then-negated-class `case`, then `printf 'url = "%s"\n' "$URL" \| /usr/bin/curl --disable --noproxy '*' -gfsS --max-time 10 --config -` |
| `web-zot-consumer-probe.sh` `_ping()` (issue 10093) | bash, `set -u` | two `curl ... "$URL"` attempts | `_hb_url_ok` + per-attempt `_hb_curl` on `--config - < <(printf ...)` |
| `inngest-consumer-probe.sh` `_ping()` (issue 10093) | bash, `set -u` | two `curl ... "$URL"` attempts | same |
| `web-private-nic-guard.sh` `beat()` (issue 10093) | bash, `set -u` | `curl ... "$URL"` (comment: "still rides curl's argv (tracked as #9639)") | same; comment rewritten |

Battery stage S6-HB (`tests/scripts/test-argv-bearer-sweep.sh`) loses its four `S6H_ALLOW` entries (ceiling 4 to 0) and gains the four scripts in `S6H_CONVERTED`.
The registry template and its probe are NOT touched (merged by #10322 and verified in production on 2026-10-15).

What this PR's merge fires (all automatic; the pipeline dispatches nothing by hand): the push apply (three `terraform_data` SSH re-deliveries of the probe scripts to web-1, because `triggers_replace` hashes the script bytes), `mint-inngest-bootstrap-tag.yml` (the carrier `inngest-bootstrap.sh` changed, so the next `vinngest-v*` tag is minted, the image is built and a pin-bump PR is opened by the bot), `web-platform-release.yml` and `validate-vector-config.yml` (validation only).

## Research Reconciliation - Spec vs. Codebase

| Claim in the brief / source plan | Reality measured 2026-10-15 on `origin/main` 8c8401e6fa | Plan response |
|---|---|---|
| GuardA is green on main (250/250, pin `vinngest-v1.1.52`) | **Already red**: `bash apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh` is 266/269 with exactly three red rows: web pin row (pin v1.1.53 vs latest merged tag v1.1.54), dedicated-host pin row (same), and `GuardA: every baked carrier is byte-identical at vinngest-v1.1.53 (drifted: vector.toml)`. Cause: #10255 edited `vector.toml`, the mint produced v1.1.54, and the bot's pin-bump PR #10330 has not merged. | The gate is a named-row subset predicate (Operator Holds, Gate 3), not "GuardA red by design" in the abstract. PR C adds `inngest-bootstrap.sh` to the drifted list; nothing else may go red. |
| #10330 is red on e2e - measure why | `gh run view 38643783443`: job `e2e`, 50 Playwright specs failed, 49 passed, 1 skipped. Every failing spec dies with `net::ERR_CONNECTION_REFUSED` to `http://localhost:3100/dashboard` (`nav-states-nav-pending.e2e.ts`, `nav-states-shell.e2e.ts`) after the web server logged repeated `500 /api/team-names`. The PR diff is only `cloud-init.yml` and `cloud-init-inngest.yml` (pin literal), so it cannot move app behaviour; main's CI is green on 8c8401e6fa; the PR is BEHIND. | Reported only (environmental e2e web-server loss, unrelated to the pin). Not touched. The mint decides from the tree against the newest merged tag, so PR C does not need #10330 to merge first (CTO ruling, Decision Classes row 3). |
| Both inngest Better Stack monitors are paused, so the refusal marker is their sole detector | Live read (`arm-heartbeats.sh --status`, read-scope token): `soleur-inngest-server-prd` id 460830 `paused=false status=up period=60 grace=30`; `soleur-inngest-consumer-prd` id 482259 `paused=false status=up period=180 grace=60`. Source says `paused = true` with `ignore_changes`, but both were armed live. | A false refusal or a broken beat on either inngest script PAGES (90 s and 240 s). The marker is the cause-naming detector, the monitor is the alarm. Observability and post-merge checks updated; the stale "pages nobody" claim is not carried forward. |
| `EXPECTED_TESTS` 781 to 783 (the preserved commit) | Current literal is **811** (registry PR and community PR added rows); measured 811/811 green. | Re-measure after the last edit; never by arithmetic from 783. |
| `INNGEST_MIN_ASSERTIONS` floor 451 to 506 | Current literal 451 and the suite measures 451/451, so it sits exactly AT its floor today. | Re-measure; the preserved commit's +55 is a guide, not the value. |
| Re-implement `b48247d559` because main moved | `git log b48247d559..HEAD` on the two infra files: `inngest-bootstrap.sh` (#10128, #10255 vector partition), `inngest.test.sh` (#10257, #10268). `git apply --check` of the commit's `inngest-bootstrap.sh` and `inngest.test.sh` hunks succeeds against HEAD; its sweep hunk does NOT (EXPECTED_TESTS line moved). | Read every hunk against its current neighbours and re-type; a clean apply is not proof. The sweep edit is re-done by hand against the 811 base. |
| R7: the stored URLs might fail the new shape guard (a false refusal pages) | Counts-only read of Doppler (`ok`/`refused`, no value printed) with the exact guard: `soleur/prd` `WEB_ZOT_CONSUMER_URL_WEB_1` ok, `_WEB_2` ok, `WEB_NIC_GUARD_URL_WEB_1` ok, `_WEB_2` ok, `INNGEST_CONSUMER_URL` ok, `INNGEST_HEARTBEAT_URL` ok; `soleur-inngest/prd` `INNGEST_HEARTBEAT_URL` ok. 7 of 7 pass. | R7 closed with evidence; re-run at ship time (Phase 6) in case a value is rotated. |
| Registry must settle before C (parent merge-order ruling) | `registry-host-replace-dispatch.yml` run 38714214071 (push, head 8c8401e6fa) concluded success on 2026-10-15; the brief states the replace is finished and verified. | Ordering gate becomes a merge-base predicate; no registry file is touched. |
| `inngest-consumer-probe.sh` also fires the mint (glob `inngest*`) | The path filter only STARTS the workflow; the decision script mints only when the image's contents changed. The `COPY` list of the build workflow (13 files) does not include `inngest-consumer-probe.sh`; `inngest-bootstrap.sh` is carrier #1. | The mint fires because of `inngest-bootstrap.sh`; the probe scripts do not bake into the image. |

## Research Insights

**Premise Validation (Phase 0.6).** `gh issue view`: #10120 OPEN (deferred-scope-out), #10093 OPEN, #9757 OPEN (umbrella), #9081 OPEN (GuardA PR-context exemption); PR #10356 is this draft, #10330 OPEN. All cited files exist on `origin/main` (the four scripts, four suites, battery, ADR-280, mint workflow, build workflow, `arm-heartbeats.sh`, `betterstack-query.sh`). Local branch commit `b48247d559` exists and is readable. ADR corpus: ADR-280 (`adopting`) carries the mechanism (stdin config, inline form on checkout-less hosts) and already has PR A and PR B follow-up sections; ADR-232 owns mint/bump (pre-merge tag impossible, #8775); nothing rejects the approach. Stale premises found and corrected in the table above: GuardA green, inngest monitors paused, battery floor 783.

**Property List (Phase 0.6b).**

1. No Better Stack heartbeat URL of these four scripts is an argument of any process (`curl` or a wrapper).
2. A malformed stored URL makes zero requests and logs one value-free `SOLEUR_CREDENTIAL_REFUSED` line, at most one per hour per script; the fail-soft exit semantics of each script are unchanged (a refusal is never an argv fallback and never a crash).
3. The conversion is derived, not curated: the sweep population finds every `apps/web-platform/infra/*.sh` heartbeat script, the residual allowlist is empty, and a regression of any of the four is a RED battery row.
4. The merge's production effects are bounded and observable without a host login: three script re-deliveries and one mint, each with a read-only verdict.

**Cut List (Phase 0.6b).**

- Shared heartbeat library for the four scripts - cut: checkout-less hosts cannot source one (source-plan Cut List); the inline copies already exist (`web-git-data-probe.sh`, `luks-monitor.sh`).
- Pre-merge tag mint or pin bump in this PR - impossible (#8775, ADR-232 A5): a `vinngest-v*` tag must sit on a main commit and the bump job holds `infra-privileged`.
- Waiting for #10330 before merging - cut (CTO): the mint compares tree against newest merged tag, not against the pin.
- A new anti-vacuity floor in the two probe suites that have none - cut: a new floor joins the `guard-vacuity-floor.test.sh` meta-guard shape for no added property; per-block row-count self-assertions carry it.
- A shared rate-limit helper across the three probes - cut (CTO ruling 1): one small helper per script modelled on the file's own existing limiter.
- Changing any systemd unit, `server.tf` provisioner or `web-probe*.tf` file - cut: the units expand the URL inside an inner `bash -c` (no argv exposure); #9639 keeps tracking the xtrace-ordering half and is not in this ask.

**Learnings applied** (from the source plan's sweep plus this session): `2026-10-06-an-argv-bearer-sweep-needed-a-ratchet-a-token-shape-guard-and-a-process-substitution-not-a-pipe` (process substitution preserves curl's status; a pipe changes it, hence the POSIX body uses a pipe deliberately and the bash bodies use `< <(...)`); `2026-10-11` inline-copy parity (pin the contract, not the copies); `2026-05-18-vendor-cron-heartbeat-silent-fail-pattern` (no `|| true` hiding a heartbeat failure); `2026-07-18-shared-delivery-substrate-and-reused-heartbeat-url-masking`; `2026-10-13-a-locale-pin-fix-needed-the-guard-around-the-prune-and-the-repos-own-ratchets` (run the repo-wide ratchets, not only the file-selected suites).

## Problem Statement / Motivation

Same exposure class as the swept sites: a Better Stack heartbeat URL is a capability (anyone holding it can spoof "alive") and sits in `/proc/<pid>/cmdline` of the child `curl` for every 60 s tick on web-1 (three probe scripts) and on the inngest host (bootstrap heartbeat). `web-git-data-probe.sh` and `luks-monitor.sh` were converted in #10086; the registry heartbeats in #10322; this PR closes the set and deletes the allowlist that tracked the remainder.

## User-Brand Impact

- **If this lands broken, the user experiences:** a false refusal in a converted heartbeat script stops a liveness beat and pages "host down" for the zot consumer, the private NIC guard, the inngest consumer or the inngest server (all four monitors are armed and `up` today); a regression in the bootstrap heredoc is baked into the next image and reaches the inngest host only at a later image deploy or replace, so a mistake there is latent and is caught by the dash row before merge, not by a page.
- **If this leaks, the user's workflow is exposed via:** a same-host reader of `/proc/<pid>/cmdline` seeing a Better Stack heartbeat URL (spoof "alive" for the zot consumer, the NIC guard or inngest) - a rotatable capability with no user data on the path.
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** each site is a same-host local-reader exposure of a rotatable credential; unchanged from the parent plans. No sensitive-path diff beyond `apps/web-platform/infra/*.sh` host scripts; no `threshold: none` scope-out is needed.

## Hypotheses

The feature description mentions "SSH" only to forbid it (baselines "readable without SSH"). No connectivity fault is being diagnosed, so the L3-first checklist of `hr-ssh-diagnosis-verify-firewall` is not engaged; every read in this plan is a vendor-API or Doppler read.

## Proposed Solution

### C1 - `inngest-bootstrap.sh` heartbeat body (issue 10120), POSIX sh

Anchor (by content): the single line `exec /usr/bin/curl -gfsS --max-time 10 "$INNGEST_HEARTBEAT_URL" >/dev/null` immediately before `HEARTBEATSCRIPTEOF` (the only match of `grep -c -e 'max-time 10 "[$]INNGEST'`). Read `git show b48247d559 -- apps/web-platform/infra/inngest-bootstrap.sh` and re-type the block against the current neighbours (the listener gate and the dark arm still run first; `dark_arm_emit_due` and `LOG_TAG="inngest-heartbeat"` are unchanged on main):

```sh
_hb_ok=
case $INNGEST_HEARTBEAT_URL in
  https://*)
    case ${INNGEST_HEARTBEAT_URL#https://} in
      ''|*[!A-Za-z0-9._~:/?\&=%+-]*) ;;
      *) _hb_ok=1 ;;
    esac ;;
esac
if [ -z "$_hb_ok" ]; then
  case $INNGEST_HEARTBEAT_URL in '') _hb_reason=empty ;; *[[:cntrl:]]*) _hb_reason=control_char ;; *) _hb_reason=token_shape ;; esac
  _hb_marker="SOLEUR_CREDENTIAL_REFUSED script=inngest-heartbeat reason=$_hb_reason var=INNGEST_HEARTBEAT_URL"
  if INNGEST_HEARTBEAT_DARK_STAMP="${INNGEST_HEARTBEAT_REFUSAL_STAMP:-/run/inngest-heartbeat/refusal.stamp}" dark_arm_emit_due; then
    logger -t "$LOG_TAG" "$_hb_marker"
  fi
  exit 2
fi
printf 'url = "%s"\n' "$INNGEST_HEARTBEAT_URL" | /usr/bin/curl --disable --noproxy '*' -gfsS --max-time 10 --config - >/dev/null
```

Design points (each is a test row, see C3): `https://` is its own test because the negated class alone admits `http://x`; the class is NEGATED because a positive pattern constrains only the first character (`*` matches quotes and newlines); no trimming, no host pin; a pipe (not a heredoc: Rule E of `lint-shell-trace-credential-refusal.py` refuses a heredoc feeding the config) and no `[[ ]]` / process substitution (dash); no `exec` before curl (inside a pipeline it runs in a subshell and replaces nothing; the line is the script's LAST command, so the script's status is the pipeline's, which is curl's, as the old `exec curl` gave; the comment says so; review finding, the preserved commit had `exec`); no `pipefail` exists in the body; the marker is assigned to a variable first so no `logger` line names the URL variable (the suite bans that shape); exit 2 equals what curl's own blank-URL rejection gave, so the web render (no dark arm) stays loud on an absent URL; the refusal limiter has its OWN stamp (not the dark arm's or the listener gate's), reusing `dark_arm_emit_due`'s hourly interval. The heredoc stays QUOTED. The comment block above the new lines is rewritten (keep the `-g` rationale; add the ADR-280 reason).

### C2 - the three probe scripts (bash, `set -u`)

Copy `_hb_url_ok` from `web-git-data-probe.sh` verbatim (so the class literal `[!A-Za-z0-9._~:/?\&=%+-]` appears exactly once in each file, on a line BEFORE the single `url = "` config line, which the S6-HB scan pins) and define ONE per-attempt `_hb_curl` called twice (a process substitution is consumed once, so each attempt needs its own):

```bash
_hb_curl() { curl --disable --noproxy '*' -gfsS -m 10 -o /dev/null --config - 2>/dev/null < <(printf 'url = "%s"\n' "$URL"); }
```

The check sits AFTER the file's existing test seam and empty-URL branch (so every existing seamed row, several of which use `http://127.0.0.1:1/hb`, is unaffected, and the empty-URL WARN text is unchanged) and is exercised by NEW rows that run with a recording curl stub and no ping-log seam.

Refusal emit (CTO ruling 1, `Ruled by CTO agent, 2026-10-15`): each script has its own refusal stamp, never shared with a fault or canary limiter, 3600 s, at most 24 rows/day/script; the marker line and the existing-style WARN both sit inside the limiter; a future-dated or garbage stamp reads as "emit" and the stamp is rewritten on emit; the refusal is fail-soft (no ping, exit status unchanged, never an argv fallback). Marker: `SOLEUR_CREDENTIAL_REFUSED script=<basename without .sh> reason=<token_shape|control_char> var=<NAME>` to stderr (the inngest body alone adds `reason=empty` for a zero-length value: on the web render there is no dark arm, so an unset URL reaches the guard and must not be filed as malformed; its absent-URL Test Scenario asserts the reason) (each unit's SyslogIdentifier ships it; tags `web-zot-consumer-probe`, `inngest-consumer-probe`, `web-nic-guard` are already allowlisted in `vector.toml`, verified).

| Script | Call site | Limiter | Marker `var=` | Notes |
|---|---|---|---|---|
| `web-zot-consumer-probe.sh` | `_ping()` after the `PING_LOG` seam and the `[ -n "$URL" ]` branch | reuse `_window_open` / `_stamp`; add an OPTIONAL window argument written `${2:-1800}` so the canary and per-repo callers do not change (regression rows: a 1801 s-old canary stamp still emits and a 1799 s-old one does not; boundary pair at 3600 for the refusal stamp; if touching the shared helper disturbs any existing row, use the same inline helper as the other two scripts, which satisfies the ruling's own-stamp and 3600 s requirement); new marker `${SOLEUR_PROBE_REFUSAL_MARKER:-/run/web-zot-consumer-probe.refusal}` passed 3600 | `WEB_ZOT_CONSUMER_URL` | `_window_open` already treats future-dated and garbage stamps as "emit" |
| `inngest-consumer-probe.sh` | `_ping()` after the `PING_LOG` seam and empty-URL branch | NEW small inline `_refusal_due` with own marker `${SOLEUR_INNGEST_CONSUMER_REFUSAL_MARKER:-/run/inngest-consumer-probe.refusal}`; NOT `_fault` (its stamp is shared by every fault class and its negative-age shape suppresses) | `INNGEST_CONSUMER_URL` | file keeps `set +e +o pipefail` after the sourced registry probe |
| `web-private-nic-guard.sh` | replaces `beat()`; the `if [ "$NIC_OK" = true ] && [ "$SHIP_REFUSED" = false ] && [ -n "$URL" ]` block keeps its predicate and branches `_hb_url_ok` then `_hb_curl \|\| _hb_curl \|\| WARN` / refusal | NEW inline `_refusal_due`, marker `${SOLEUR_NIC_REFUSAL_MARKER:-/run/web-private-nic-guard.refusal}` (the guard's only FS-read seam is `SOLEUR_NIC_TEST_ROOT`; a refusal stamp is a write, so it needs its own override) | `WEB_NIC_GUARD_URL` | rewrite the comment "still rides curl's argv (tracked as #9639)" to say the URL reaches curl on its stdin config and #9639 still tracks only the unit's pre-refusal expansion |

An unwritable stamp (read-only or absent `/run`) fails OPEN by the ruling (emit on every tick, up to 1,440 rows/day for that script, loud rather than silent; the NIC guard has no existing writer under `/run`, so an unwritable-stamp row exists in each suite and the ADR paragraph states the fail-open default). A `SHIP_REFUSED` guard that cannot report still withholds the beat; a URL refusal does not set `SHIP_REFUSED` (the Better Stack POST was attempted, so the telemetry channel is healthy) but, like it, lets the beat lapse so absence alarms.

### C3 - tests (RED first, `cq-write-failing-tests-before`)

Per-script suites (every consumer enumerated first with `git grep -l -F <script>`; the list for each script is in Files to Edit):

- `web-zot-consumer-probe.test.sh`: extend the `STUBCURL` (the heartbeat call is the one with `-o /dev/null` and no `-w`; it must print nothing, honour `-f`, and take a `STUB_HB_RC` to fail on demand); new block "heartbeat channel" with NO `SOLEUR_ZOT_PROBE_PING_LOG`: well-formed `https://` canary with a different token than the fixture (every allowed punctuation class) beats once, argv has no URL word and starts `--disable --noproxy * -gfsS -m 10 -o /dev/null --config -`, stdin is exactly one `url = "..."` line; first attempt failing gives two attempts with two identical stdin lines (the per-attempt row: a stub that records no stdin line fails it); twelve hostile or malformed values defined ONCE per suite as an array with a row asserting its length is 12 (so the copies in the zot, inngest-consumer and inngest suites cannot silently diverge) (empty rest, `http://`, uppercase scheme, leading space, trailing space, double quote, single quote, backslash, newline with a smuggled `url =` directive, CR, tab, `;`/`$`/backtick/`@`/`#`) make ZERO heartbeat curls, one marker, exit status unchanged, value never echoed; limiter rows (four refused runs inside one window log one marker; an aged stamp re-emits; a future-dated stamp emits and rewrites; the stamp is the refusal stamp, not the canary or repo-marker stamp). T8's `wc -l SARGV == 2` stays true because those rows keep the ping seam. `MIN_ASSERTS=300` is raised to the new measured count minus the existing 3-row terraform margin (read the file's comment on how the floor is derived).
- `inngest-consumer-probe.test.sh`: no curl stub exists today (all rows use `PING_LOG` and a python mock for GraphQL). Add one recording stub plus the `INNGEST_PROBE_FUNCTIONS_FIXTURE` seam inherited from the sourced registry probe (non-empty registry, no network), then the same row set. No new anti-vacuity floor (none exists).
- `web-private-nic-guard.test.sh`: the stub's "ping" branch records the LAST POSITIONAL as the URL; repoint it to read the stdin ONCE (`cfg_in=$(cat)` when `--config -` is present, because a pipe or process substitution is consumed by the first read) and write that capture to `STUB_STDIN` (as today) and, for the ping kind, the parsed URL to `STUB_PING` (so T1/X1 keep their URL assertions); add a row that `STUB_PING` is non-empty on the healthy run, so a stub that lost the stdin cannot make T1/X1 pass vacuously. `transport_audit` golden argv for the ping class becomes `--disable --noproxy '*' -gfsS -m 10 -o /dev/null --config -` with zero tail arguments, and its stdin golden for a ping becomes exactly one `url = "https://..."` line (it is "empty" today). The X1/X3/X6 negative rows that assert the heartbeat URL is absent from argv go vacuous once the URL is never on argv; repoint them to the recorded stdin line so a leak into either stream still REDs. Add the refusal rows (zero ping calls, one marker per window, beat withheld, POST unaffected).
- `inngest.test.sh`: re-type the preserved rows: https canary (the guard has no http arm), absent-URL row attributes the loud failure to the guard, the `--config` census excludes curl's own stdin-config line, recording curl stub wired in by rewriting `/usr/bin/curl` in a copy of the rendered script, twelve hostile values with zero requests, limiter re-emit row, own-stamp row, static POSIX-shape rows (no `[[ ]]`, no process substitution, exactly one transport line, no heredoc feeding the config, no logger/echo/printf naming the URL variable except that line, the negated class), the `LOG_TAG` derivation unaffected, and the dash row. Dash row (CTO ruling 2): the digest-pinned `ubuntu:24.04` image (read from `git-data-runcmd-rehearsal.test.sh`) is authoritative and mandatory in CI (missing docker, failed pull or skipped row is a FAILURE); local `dash` is a labelled fallback ("non-pinned dash") only when docker is absent; neither present is a loud skip. CI is detected by `GITHUB_ACTIONS` or `CI=1|true` (the preserved commit's `_in_ci_dash`). The image reference is parsed from `git-data-runcmd-rehearsal.test.sh` (`UBUNTU_BASE=`) and asserted against `^ubuntu:24\.04@sha256:[0-9a-f]{64}$` before use, so a reshaped line fails loudly instead of degrading to a skip or a bad pull; a registry rate-limit on the pull is a CI FAILURE to retry, not a skip. Floor: skipped dash rows do NOT count toward it. `INNGEST_MIN_ASSERTIONS` becomes a two-tier floor in the zot suite's shape (a lower literal without the dash rows for a docker-less local run, the full literal when the container ran), re-measured (preserved commit: 451 to 506, which counted skips and is not carried).
- `tests/scripts/test-argv-bearer-sweep.sh` (stage S6-HB, read the block start to end first): `S6H_CONVERTED` gains `inngest-bootstrap.sh web-zot-consumer-probe.sh inngest-consumer-probe.sh web-private-nic-guard.sh`; `S6H_ALLOW=()` and `S6H_ALLOW_CEIL=0`; the ceiling row becomes `0 == 0` plus a grow-by-one mutant judged RED by the same predicate (mirror `s6_ceiling_ok` of stage S6); re-anchor the "stale" mutation (it currently converts `web-private-nic-guard.sh` while its entry stands) onto an INJECTED synthetic allowlist entry for an already-converted script (the real array is now empty); re-anchor the "growth" mutation if its anchor text moved; new mutation rows per Guard Contract 1; update the stage header comment ("tracked in #10093" and "residual allowlist" prose), the converted-set comment and the ceiling row text ("#10093 converts the three probe scripts"); the scratch-base copy loop (`for f in "${S6H_CONVERTED[@]}" web-zot-consumer-probe.sh ...`) copies files twice once the converted set holds them, so de-duplicate it; the "growth" mutation (one more occurrence inside an allowlisted file) loses its meaning with an empty allowlist and becomes a plain argv violation, so re-title it; `s6h_judge` reads the global `S6H_ALLOW`, so the injected-entry and grow-by-one mutants save and restore the array around the judge call (as stage S6 does at its `S6_ALLOW_SAVE` lines). `EXPECTED_TESTS`: 811 is the baseline; set it from the measured total of a full green run (expected a few above 811: four converted-script rows plus the new mutation rows), state pre and post values in the PR body.
- Re-measure, do not hand-edit: `.claude/hooks/grep-q-pipe-guard.test.sh` (`PRODUCER_JOIN` / `PJ_TRIPLES`, names the zot probe), `plugins/soleur/test/fixture-relative-assert.baseline.txt` (names the zot and inngest-consumer suites), `scripts/guard-vacuity-floor.test.sh` (names the zot probe and NIC guard suites; its mutants are built from the floor literal adjacency, keep that shape), `scripts/lint-shell-trace-credential-refusal.test.sh` and the ADR-280 census rows. New fixture dirs follow `assert_fixture_dir` byte-for-byte; run `fixture-relative-assert.test.sh`, `fixture-dir-operand-assert.test.sh` and `python3 scripts/lint-shell-capture-exit.py --baseline scripts/lint-shell-capture-exit.baseline.txt <file>` on each edited suite BEFORE its first commit (work Phase 2 item 6.6).

### C4 - ADR-280 follow-up paragraph

Append under the existing `## Addendum - 2026-10-12 (#9757 residue)` chain, after PR B's `### 2026-10-14 follow-ups - PR B` section, `### 2026-10-15 follow-ups - PR C (#10120, probe scripts of #10093)`: the facts a future engineer cannot derive from the code: pipe-not-heredoc for the POSIX sh body; the allowlist deleted to zero and the three probes plus the inngest body under the same inline-guard exception; the per-script refusal stamp (own stamp, 3600 s, fail-open when unwritable) and the residual (same-uid `/proc/<pid>/environ` readers, #9639); the stale 2026-10-12 sentence about "three further heartbeat probe scripts ... tracked in #10093" gets a superseded note. Status stays `adopting` (the flip belongs to #9905's follow-through).

## Pre-merge baselines (read-only, recorded 2026-10-15, no secret printed)

These go verbatim into the PR body under `### Pre-merge baseline`; Gate 4 re-reads them at merge time.

| Item | Value | Source |
|---|---|---|
| origin/main | 8c8401e6fa (contains registry PR #10322) | `git rev-parse origin/main` |
| Inngest pin literal (web `cloud-init.yml` and `cloud-init-inngest.yml`) | `v1.1.53` (`sha256:a9441388...f3da0`, 4 refs) | `grep -n 'soleur-inngest-bootstrap:v' apps/web-platform/infra/cloud-init*.yml` |
| Latest merged `vinngest-v*` tag | `vinngest-v1.1.54` (also v1.1.53 below it) | `git ls-remote --tags origin 'vinngest-v*'` |
| Open pin-bump PR | #10330 (to v1.1.54), BEHIND, red only on `e2e` (see Reconciliation); untouched | `gh pr view 10330` |
| GuardA suite on main | 266/269; red rows = web pin, dedicated-host pin, byte-identity (drifted: `vector.toml`) | `bash apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh` |
| `soleur-web-zot-consumer-web-1` | id 473113, `paused=false status=up period=180 grace=60` | `arm-heartbeats.sh --status` (read-scope `BETTERSTACK_API_TOKEN_READONLY`) |
| `soleur-web-nic-guard-web-1` | id 473114, `paused=false status=up period=360 grace=120` | same |
| `soleur-web-zot-consumer-web-2` / `soleur-web-nic-guard-web-2` | ids 475781 / 475780, both `up`, same periods | same |
| `soleur-inngest-server-prd` / `soleur-inngest-consumer-prd` | ids 460830 (period 60 grace 30) / 482259 (period 180 grace 60), both `paused=false status=up` | same |
| web-1 `boot_id` | `8c86d413-5e03-46de-9c73-dabec64c096e` (uptime about 18.33e6 s, the longest-uptime web-variant `SOLEUR_PRIVATE_NIC` emitter, `zot_store_mounted=n/a`); web-2 is `dd08ac9d-a7fa-49da-a41e-a63e5d6b0f14` (uptime about 0.65e6 s) | `doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh --since 3h --grep SOLEUR_PRIVATE_NIC`, decoded |
| Registry replace dispatcher | run 38714214071 success at 8c8401e6fa; apply-web-platform-infra last 3 runs success; mint/build last runs success; no run in progress | `gh run list --workflow ...` |
| Stored URL shapes | 7 of 7 `ok` under the new guard (counts only) | Doppler read, see Reconciliation |
| Suites on main | inngest.test.sh 451/451 (floor 451), web-zot 303/303 (MIN_ASSERTS 300), inngest-consumer 55/55, web-nic 169/169, battery 811/811 (EXPECTED_TESTS 811) | local runs |

Re-record at ship time: monitor statuses, boot_id, pin, tag, and the GuardA row set can all move before merge (any new mint changes them).

## Operator Holds

(Consumed by ship Phase 6 and by the merging CTO agent; a predicate that cannot be evaluated STANDS as a hold. These are machine-checkable `Gate:` predicates; none asks the operator a technical question. Merging, tag minting and apply dispatch are never performed by the planning or implementation pipeline: no tag is minted or pushed, no workflow is dispatched, no terraform is run, auto-merge is never armed.)

- **Gate 1: merge-base.** `git merge-base --is-ancestor 8c8401e6fa <PR head>` exits 0 and `git merge-base --is-ancestor 8c8401e6fa origin/main` exits 0 (the registry PR #10322 is in the history), and the PR diff contains no file matching `cloud-init-registry.yml`, `zot-registry.tf`, `registry-boot-guard.test.sh`, `htpasswd-stdin.test.sh` (`git diff --name-only origin/main...<head>`).
- **Gate 2: quiet host.** For each of `registry-host-replace-dispatch.yml`, `apply-web-platform-infra.yml`, `mint-inngest-bootstrap-tag.yml`, `build-inngest-bootstrap-image.yml`: `gh run list --workflow <w> --status in_progress --json databaseId --jq length` and the same for `--status queued` and `--status waiting` all print `0`; AND the four web-1 monitors of the baseline read `status=up` (`arm-heartbeats.sh --status`); AND the web-1 `boot_id` still equals the baseline (no reboot or replace in flight).
- **Gate 3: GuardA.** Let RED = the set of `FAIL:` rows of `bash apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh` on the PR head. RED must be a subset of {web pin row, dedicated-host pin row, `GuardA: every baked carrier is byte-identical at ...`}, the drifted list inside the byte-identity row must be a subset of {`vector.toml`, `inngest-bootstrap.sh`}, and every OTHER test file this PR touches is fully green. This is the documented sanctioned-window exception (#9081, ADR-232, precedents #10073 and #9944), evidenced by named rows; any other red row, or any drifted carrier beyond the two named, fails the gate. It also holds if #10330 merges first (the pin rows may go green and `vector.toml` may leave the list). Ruled by CTO agent, 2026-10-15.
- **Gate 4: baseline recorded.** The PR body contains the `### Pre-merge baseline` block with the pin literal, the latest tag, the four web monitor statuses, the two inngest monitor statuses, the web-1 `boot_id` and the main SHA, and contains no URL path, token or hash value (`grep -E 'https://[^ ]*(hooks|heartbeat)'` over the body finds nothing).
- **Gate 5: PR body hygiene.** The body has the line `Ref #9757`, `Ref #10120` and `Ref #10093`, no `Closes`, `Fixes` or `Resolves` keyword anywhere (title included), and ends with this `## Operator Holds` section.
- **Gate 6: lead gate evidence.** The body records `bash scripts/test-all.sh --affected` with its selection compared against `--print-selection`, its BREAKDOWN line, and the explicitly named suites run directly (below); the claim "all covering suites ran" is absent unless the two lists match.

## Production-apply coupling

| File in PR | Workflow fired on merge | Effect |
|---|---|---|
| `inngest-bootstrap.sh`, `inngest.test.sh` | `mint-inngest-bootstrap-tag.yml` (decides carrier changed: mints the next `vinngest-v*`, dispatches the build from main), then `build-inngest-bootstrap-image.yml` (image through `infra-privileged`, opens the pin-bump PR); push apply (no Terraform diff); `validate-vector-config.yml` (validation) | New tag and image; no host change until a later image deploy or replace. GuardA window opens at merge and closes when the bot's pin-bump PR merges. |
| `web-zot-consumer-probe.sh`, `inngest-consumer-probe.sh`, `web-private-nic-guard.sh` (+ suites) | push apply | `terraform_data` SSH re-delivery of each script to web-1 (`private_nic_guard_install`, `zot_consumer_probe_install`, `inngest_consumer_probe_install`; `triggers_replace` hashes the bytes); `hcloud_server.web` ignores `user_data`, so no replace. The next 60 s tick runs the converted ping. |
| `tests/scripts/test-argv-bearer-sweep.sh`, ADR-280, plan/spec | none (docs and tests) | none |
| `inngest-consumer-probe.sh` / `.test.sh` (match the `inngest*` path filter) | start `mint-inngest-bootstrap-tag.yml` | the decision script no-ops for these files alone (not a carrier); the mint here is caused by `inngest-bootstrap.sh` |

## Downtime & Cutover

No serving surface goes offline. Probe re-delivery is a file copy plus an already-enabled 60 s timer (the next tick runs the new body; heartbeat grace is 60 s and 120 s, a late beat is covered). The mint publishes an image with no host change. Rollback: revert the commit; deliveries are idempotent, the revert re-delivers the old bytes and mints another tag.

## Infrastructure (IaC)

### Terraform changes

None. No `.tf` file, provider, variable or secret changes; `triggers_replace` hashes change because script bytes change (the existing delivery mechanism).

### Apply path

Existing paths only: web-1 probe scripts via the push-apply `terraform_data` provisioners; the inngest bootstrap via the mint/build pipeline. Expected downtime: none.

### Host fan-out

No provisioner is added or edited; `web-host-provisioner-parity.test.sh` classifications unchanged (re-run green).

### Distinctness / drift safeguards

No `dev != prd` surface; no `lifecycle` change.

### Vendor-tier reality check

Better Stack heartbeat behaviour is unchanged (same URL, same GET).

## Architecture Decision (ADR/C4)

### ADR

Amend ADR-280 (no new ordinal) with the PR C follow-up paragraph described in C4. This is a task of this plan, not a follow-up issue.

### C4 views

No new element or relationship, checked against all three files (`model.c4` 962 lines, `views.c4`, `spec.c4`): external human actors (founder/Owner, inbound correspondents, contributors: none added or changed); external systems (Better Stack, Doppler, Hetzner, the zot registry, the Inngest hosts: all modeled, no new vendor or edge - this changes how a credential reaches a child process); containers and stores (`inngest`, `inngestRedis`, `zotRegistry`, the git-data store untouched, no new store); actor-to-surface access relationships (unchanged). `bash plugins/soleur/test/c4-count-parity.test.sh` run now: 0 failed, `ALL TESTS PASSED`; re-run at the end.

### Sequencing

The addendum ships in this PR.

## Guard Contract

### Guard 1 - Heartbeat URL never reaches curl argv in the infra scripts (S6-HB, empty allowlist)

**Property.** In every `apps/web-platform/infra/*.sh` heartbeat script a heartbeat URL is never an argument of any process, is sent only after the shape judgement, and the residual allowlist that excused four scripts is empty and cannot grow.

**Assembly.** The population is DERIVED by stage S6-HB (every tracked or untracked `apps/web-platform/infra/*.sh`, not `*.test.sh`, whose non-comment code mentions `heartbeat`), one violating-segment scan over every logical line (continuations joined, whole-line comments dropped, `< <(...)` feed removed, split on `||`, `&&`, `;`, `|`), one converted set `S6H_CONVERTED` (gains the four scripts; each must hold exactly ONE stdin `url = "` line and exactly ONE copy of the guard-class literal on an earlier line), and `S6H_ALLOW=()` with `S6H_ALLOW_CEIL=0`. Chokepoint per script: the single guarded `--config -` line. Named gaps: a URL held in a variable that is none of `$URL`, `$hb_url`, `*HEARTBEAT_URL`; `eval`; the registry template (stage S6 owns it).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Put the URL back on argv in the inngest heartbeat body (`exec /usr/bin/curl ... "$INNGEST_HEARTBEAT_URL"`) and, separately, in one probe (`curl ... "$URL"`) | RED (`argv:<file>` and `cfg:<file>`, the config line is gone) |
| 2 | Add a second heartbeat curl after the compliant first in a probe, both as an argv URL and as a second unguarded `url = "` line | RED (argv; and a second config line) |
| 3 | Widen the guard class in `inngest-bootstrap.sh` (`[!A-Za-z0-9]` replaced by a wider class) | RED (`guard:` identity of the literal) |
| 4 | Inject a synthetic allowlist entry for an already-converted script into the harness array (the real array is empty); and grow the empty allowlist by one entry | RED, `stale-allowlist` and nothing else for the first; RED by the ceiling predicate `0 == 0` for the second (same predicate as the real array) |
| 5 | Rename the word `heartbeat` in a scratch tree so the scan sees 0 scripts (existing floor row, kept green) | RED (`floor`) |

**Harness rows.** The ceiling rows become `0 == 0` plus a grow-by-one mutant; the stale and growth mutations are re-anchored on text that still exists after this PR (an injected entry, not the deleted ones); must-PASS: a local health curl beside a heartbeat, a non-heartbeat probe whose variable is also `URL`, and a converted script carrying a different well-formed token (existing control rows stay green).

### Guard 2 - A refused value makes zero requests, one rate-limited marker, and the guard cannot be bypassed (per-script suites)

**Property.** In each of the four scripts a stored URL outside `https://` plus `[A-Za-z0-9._~:/?&=%+-]` makes zero heartbeat requests, logs at most one value-free `SOLEUR_CREDENTIAL_REFUSED` line per hour, never echoes the value, and keeps the script's exit semantics; a well-formed URL beats exactly once per attempt with the URL on stdin only.

**Assembly.** Four call sites (inngest body, zot `_ping`, inngest-consumer `_ping`, NIC `beat` block); each suite derives its hostile-value list once and loops it; the recording curl stub is the single witness of requests (argv and stdin per call); the limiter state is the per-script refusal stamp. The dash row covers the POSIX body under the production shell.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Keep `_hb_url_ok` defined but delete its call in one probe (the static class-before-config row cannot see this) | RED in that probe's suite (zero requests plus one marker expected) |
| 2 | Drop the scheme test (`https://` arm) so `http://x` passes the class | RED (hostile row `http://` makes a request) |
| 3 | Positive-pattern `case` in the POSIX body, or `[[ ]]` / process substitution in it | RED (hostile-value rows; dash row; static POSIX-shape row) |
| 4 | Remove the limiter (emit every refusal) | RED (four refused runs inside one window must log exactly one marker) |
| 5 | Share the stamp with the dark arm / fault limiter / canary | RED (own-stamp row: a fresh dark or fault stamp must not suppress the refusal marker, and vice versa) |
| 6 | Second heartbeat attempt reuses the first substitution (one `_hb_curl` input consumed once) | RED (per-attempt stdin row: two attempts, two identical `url = "` lines) |
| 7 | A refusal falls back to the argv form or exits non-zero in a probe | RED (exit-status and zero-request rows) |

**Harness rows.** A stub curl that ignores stdin and records nothing must make the per-attempt row RED (a missing recorded `url = "` line fails it); the NIC suite's `transport_audit` stdin walk must fail closed if it saw fewer calls than the argv walk; must-PASS inputs that differ from the canonical fixture in a permitted way: a different token using every allowed punctuation class, run once under bash (probes) and once under dash (inngest body, container row authoritative). Mutants are applied to the SUITE as well as the script (delete the stdin-recording line of the stub: the audit rows must RED).

## Observability

```yaml
liveness_signal:
  what: "Better Stack heartbeats keep arriving after delivery. All armed and up today: soleur-web-zot-consumer-web-1 (period 180, grace 60), soleur-web-nic-guard-web-1 (360, 120), the web-2 pair, soleur-inngest-consumer-prd (180, 60) and soleur-inngest-server-prd (60, 30). The inngest bootstrap body reaches its host only at a later image deploy or replace, so its monitor is a no-regression baseline, not proof of this change"
  cadence: "60s timers; heartbeat periods 60s to 360s"
  alert_target: "operator email via the existing Better Stack heartbeat policies"
  configured_in: "apps/web-platform/infra/web-probe.tf, apps/web-platform/infra/inngest.tf"
error_reporting:
  destination: "layer 3: host journald to Vector Source 4 to Better Stack Logs (tags web-zot-consumer-probe, inngest-consumer-probe, web-nic-guard, inngest-heartbeat are allowlisted in vector.toml); layer 6 for the suites and workflows (run logs)"
  fail_loud: "SOLEUR_CREDENTIAL_REFUSED script=<name> reason=<token_shape|control_char> var=<NAME> (at most one per hour per script), the existing WARN lines, and the missed beat itself through the heartbeat policy"
failure_modes:
  - mode: "a stored heartbeat URL fails the shape guard in a probe or the inngest body"
    detection: "layer 3: doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh --since 1h --grep SOLEUR_CREDENTIAL_REFUSED; the same read is the pre-merge shape count (7 of 7 ok) and the post-merge absence check, paired with the positive control that the four monitors read up"
    alert_route: "the armed heartbeat policy pages on the missed beat (90 s to 480 s); the marker row names the cause and rides the same journald path, so it can be absent exactly when that path is the fault"
  - mode: "a probe regresses to the argv form or loses its guard"
    detection: "layer 6: battery stage S6-HB and the four per-script suites on the PR run log"
    alert_route: "required CI check fails the PR"
  - mode: "the inngest tag mint, image build or auto pin-bump fails after merge"
    detection: "layer 6: mint-inngest-bootstrap-tag.yml and build-inngest-bootstrap-image.yml run results (stage-named ::error::, Slack post), GuardA staying red on main past the bump"
    alert_route: "Slack from the mint workflow; the red GuardA rows on the next PR run"
  - mode: "the web-1 re-delivery fails or half-applies"
    detection: "layer 6: apply-web-platform-infra.yml push-apply run conclusion; layer 3: the four web-1 monitors reading up after period plus grace (240 s zot, 480 s NIC)"
    alert_route: "workflow failure plus the missed-beat page"
logs:
  where: "Better Stack Logs (host scripts via Vector), GitHub Actions run logs"
  retention: "Better Stack Logs team retention; Actions logs 90 days"
discoverability_test:
  command: grep -c -e 'max-time 10 "[$]INNGEST' apps/web-platform/infra/inngest-bootstrap.sh
  expected_output: "0"
```

The probe prints `1` on main and `0` once C1 lands (a RED to GREEN reading). The three probe scripts are covered by the battery and the Acceptance Criteria below, which carry their own greps.

## Domain Review

**Domains relevant:** Engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** credential-transport hardening of existing host scripts; no new architecture, no product, marketing, legal, finance or sales implication (no user-facing surface, no personal data, no new processor). The CTO agent ruled the three forks below. GDPR gate: no regulated-data surface and none of the (a)-(d) expansion triggers - skipped. Encryption posture (2.11): no `.tf`, migration, cloud-init or compose file is edited, no store or connection added - skipped. IaC routing (2.8): no new infrastructure; delivery paths are the existing provisioners and the mint pipeline.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---|---|---|
| 1 | "the inngest heartbeat URL off argv in apps/web-platform/infra/inngest-bootstrap.sh (issue #10120), re-implemented against CURRENT main from the preserved work ... do NOT blind-cherry-pick" | C1 | mapped |
| 2 | "the three probe-script conversions web-zot-consumer-probe.sh, inngest-consumer-probe.sh, web-private-nic-guard.sh" | C2 | mapped |
| 3 | "the S6-HB allowlist entries for those three scripts are deleted and the scripts join the converted set, with the matching test-argv-bearer-sweep.sh and per-script suites updated, EXPECTED_TESTS re-measured" | C3 | mapped |
| 4 | "no registry file may be touched here" | Gate 1 diff predicate | mapped |
| 5 | "an older pin-bump PR (#10330 to v1.1.54) is open and red on e2e - measure why and report it, do not touch it" | Reconciliation row 2, Gate 3 | mapped |
| 6 | "Use only 'Ref #N' ... put the line `Ref #9757` in the PR body" | Gate 5 | mapped |
| 7 | "Do NOT mint a tag, push a tag, dispatch any workflow, run terraform, arm auto-merge, or merge" | Operator Holds preamble | mapped |
| 8 | "End the PR with a `## Operator Holds` section phrased as automated Gate: predicates" | Operator Holds | mapped |
| 9 | "record in the PR body the exact pre-merge baselines you could read read-only" | Pre-merge baselines | mapped |
| 10 | "Run the lead gate as `bash scripts/test-all.sh --affected` ... and the repo-wide ratchets named by the work skill" | Acceptance Criteria, C3 last bullet | mapped |
| 11 | "A technical question never goes to the operator: spawn soleur:engineering:cto (at most two spawns) and record 'Ruled by CTO agent'" | Decision Classes (one spawn used) | mapped |

### Plan-Item Provenance

| Plan item | User words cited | Verdict |
|---|---|---|
| Per-script own refusal stamp, 3600 s | "The marker is rate-limited so a persistent malformed URL does not ship 1,440 rows a day" (source plan, asked) | asked; the design is CTO-ruled |
| Dash row (pinned container authoritative) | "a dash row that runs the rendered body inside the digest-pinned ubuntu image" (issue 10120) | asked; local fallback CTO-ruled |
| Named-row GuardA predicate | "GuardA green on the head or the documented sanctioned-window exception with its evidence" | asked; predicate form CTO-ruled |
| ADR-280 follow-up paragraph | none | inferred - justification: plan Phase 2.10, a decision a future engineer would find undocumented; each prior PR of the arc added one |
| Reconciliation corrections (monitors armed, GuardA already red) | "measure why and report it" | inferred - justification: the Operator Holds predicates are only evaluable if the baseline is real |

### Split Assessment

- Subsystems touched: 4 - `apps/web-platform/infra`, `tests/scripts`, `knowledge-base`, `.claude/hooks` (re-measure only)
- Planned files: 13 | Estimated changed lines: about 900 (the preserved commit alone was 294 insertions)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: **keep as one PR.** The 800-line threshold trips on estimated test lines only; splitting the inngest body from the probes would put two GuardA-adjacent windows in series and the brief fixes the grouping (CTO-ruled in the source plan, one tag mint and one set of re-deliveries).

## Files to Edit

- `apps/web-platform/infra/inngest-bootstrap.sh` (heartbeat heredoc body only)
- `apps/web-platform/infra/inngest.test.sh`
- `apps/web-platform/infra/web-zot-consumer-probe.sh`, `apps/web-platform/infra/web-zot-consumer-probe.test.sh`
- `apps/web-platform/infra/inngest-consumer-probe.sh`, `apps/web-platform/infra/inngest-consumer-probe.test.sh`
- `apps/web-platform/infra/web-private-nic-guard.sh`, `apps/web-platform/infra/web-private-nic-guard.test.sh`
- `tests/scripts/test-argv-bearer-sweep.sh` (stage S6-HB block and header comment, `EXPECTED_TESTS`)
- `knowledge-base/engineering/architecture/decisions/ADR-280-credentials-reach-curl-on-stdin-config-through-one-shared-library.md` (follow-up paragraph)
- Re-measure and edit only if the ratchet moves: `.claude/hooks/grep-q-pipe-guard.test.sh`, `plugins/soleur/test/fixture-relative-assert.baseline.txt`, `scripts/lint-shell-capture-exit.baseline.txt`, `scripts/guard-vacuity-floor.test.sh` (expected unchanged; it only reads literals)
- Other consumers found by `git grep -l -F` of the three script names, read but expected unchanged: `fresh-boot-parity.test.sh`, `doppler-injection-bound.test.sh`, `journald-config.test.sh`, `web-ghcr-deny.test.sh`, `web-probe-envwrite.sh`, `soleur-host-bootstrap.sh`, `plugins/soleur/lib/heartbeat-manifest.ts`, `plugins/soleur/test/cloud-init-user-data-size.test.ts` (75/75 green now; script bytes do not enter the web render)

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-argv-bearer-pr-c-inngest-probes/tasks.md` and `decision-challenges.md` (this plan's own artifacts).
- No new production file and no new script (the Gate predicates are one-liners over existing commands). No follow-through probe is created: the source plan's `scripts/followthroughs/*` probes are PR B/C hand-over devices for a held-merge pipeline; here a CTO agent merges after the Gates and the post-merge reads below are the Acceptance Criteria it runs (see Cut List: not enrolled, with the verdict reads named).

## Open Code-Review Overlap

None (open `code-review` issues queried by body-contains on every planned path; no match; 93 open issues scanned).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] Diff scope: `git diff --name-only origin/main...HEAD` is a subset of the Files-to-Edit list plus pipeline-written `knowledge-base/` artifacts; no registry file; no `.tf`, workflow or unit file.
- [ ] `grep -c -e 'max-time 10 "[$]INNGEST' apps/web-platform/infra/inngest-bootstrap.sh` prints `0` (it prints `1` on main), and no `curl` line in the three probe scripts carries `"$URL"` as an argument: `grep -nE 'curl[^|<]*"\$URL"' apps/web-platform/infra/{web-zot-consumer-probe,inngest-consumer-probe,web-private-nic-guard}.sh` prints nothing (comment lines excluded).
- [ ] `bash apps/web-platform/infra/inngest.test.sh` green at the re-measured floor, including the dash row run in the pinned container (record the image digest and dash version printed by the row).
- [ ] `web-zot-consumer-probe.test.sh`, `inngest-consumer-probe.test.sh`, `web-private-nic-guard.test.sh` green; each new RED row was observed RED against the unfixed script first (record the failing count before the fix).
- [ ] `bash tests/scripts/test-argv-bearer-sweep.sh` green; `S6H_ALLOW` empty, `S6H_ALLOW_CEIL=0`, `EXPECTED_TESTS` set from the measured total with pre (811) and post values in the PR body.
- [ ] `bash apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh`: the red-row set satisfies Gate 3 and every other row is green (record the exact `FAIL:` lines and the drifted list).
- [ ] Lead gate: `bash scripts/test-all.sh --print-selection` is read and recorded first; `bash scripts/test-all.sh --affected` is run; the PR body states the mode, the selection, and the BREAKDOWN line. Because the diff is `apps/web-platform/infra/**` plus `tests/scripts`, the Phase-2 shard may select little: the suites below are run directly and compared against the selection, and no sentence claims "all covering suites ran" unless the selection contains every one of them.
- [ ] Directly run and recorded (each exit code read on its own line): `inngest.test.sh`, the three probe suites, `cloud-init-inngest-bootstrap.test.sh`, `web-host-provisioner-parity.test.sh`, `infra-config-gate.test.sh`, `ci-deploy.test.sh`, `fresh-boot-parity.test.sh`, `doppler-injection-bound.test.sh`, `journald-config.test.sh`, `arm-heartbeats.test.sh`, `scripts/lint-shell-trace-credential-refusal.test.sh` and `python3 scripts/lint-shell-trace-credential-refusal.py --changed`, `.claude/hooks/grep-q-pipe-guard.test.sh`, `plugins/soleur/test/c4-count-parity.test.sh`, `bun test plugins/soleur/test/cloud-init-user-data-size.test.ts`.
- [ ] Repo-wide ratchets named by the work skill, run even though no file-based selection returns them: `plugins/soleur/test/fixture-relative-assert.test.sh`, `fixture-dir-operand-assert.test.sh`, `python3 scripts/lint-shell-capture-exit.py --baseline scripts/lint-shell-capture-exit.baseline.txt <edited .test.sh files>`, `scripts/guard-vacuity-floor.test.sh`, `lint-diagnosis-claims`, `no-control-regex` (as named by the work skill's file-selected-set warning), `python3 scripts/lint-guard-contract.py <this plan>`, `npx markdownlint-cli2` on touched markdown, `knowledge-base/INDEX.md` never `git add`ed.
- [ ] ADR-280 follow-up paragraph present (heading `### 2026-10-15 follow-ups - PR C (#10120, probe scripts of #10093)`).
- [ ] PR body: first line states that merging fires the tag mint and three web-1 re-deliveries and opens the GuardA sanctioned window; carries `Ref #10120`, `Ref #10093`, `Ref #9757`; the `### Pre-merge baseline` block; the #10330 e2e measurement; the sibling-PR rebase note; `Ruled by CTO agent, 2026-10-15` entries; ends with `## Operator Holds`.

### Post-merge (executed by the merging CTO agent; read-only, no SSH, no dispatch)

- [ ] `mint-inngest-bootstrap-tag.yml` run for the merge SHA concluded success and minted `vinngest-v1.1.55` (or the next free ordinal); `build-inngest-bootstrap-image.yml` succeeded; the bot's pin-bump PR is open (`gh pr list --search 'inngest-bootstrap pin' --state open`). The merge does NOT merge that PR.
- [ ] `apply-web-platform-infra.yml` push run for the merge SHA concluded success.
- [ ] After period plus grace (at least 480 s after the apply run ended): `arm-heartbeats.sh --status` reads `status=up` for `soleur-web-zot-consumer-web-1`, `soleur-web-nic-guard-web-1`, the web-2 pair and `soleur-inngest-consumer-prd`; a `paused` reading is CANNOT ESTABLISH, not a pass.
- [ ] Absence check paired with its positive control: `betterstack-query.sh --since 15m --grep SOLEUR_CREDENTIAL_REFUSED` returns no row naming `web-zot-consumer-probe`, `inngest-consumer-probe` or `web-private-nic-guard`, AND a fresh `SOLEUR_PRIVATE_NIC` row from the web-1 `boot_id` exists. A "no refusal for the inngest script" check is deliberately NOT claimed (that script reaches its host only at a later image deploy).
- [ ] The web-1 `boot_id` is unchanged. The GuardA window closes when the bot's pin-bump PR merges; its merge is not part of this PR.

## Test Scenarios

- Given a well-formed `https://` heartbeat URL with a different token than the fixture, when a probe pings, then the recording curl stub saw one call (two when the first fails) whose argv carries no URL word and whose stdin is exactly one `url = "..."` line (integration, each of three probes and the dash row for the inngest body).
- Given any of the twelve hostile or malformed values, then zero heartbeat requests, one marker inside the window, the value never echoed, exit status unchanged (integration).
- Given four refused runs inside one hour, then exactly one marker; given an aged or future-dated stamp, then it re-emits and rewrites the stamp (unit).
- Given the dark arm's or a fault limiter's stamp is fresh, then the refusal marker is still emitted (own-stamp row).
- Given the inngest render with the dark arm omitted and the URL absent, then exit 2, zero requests, one marker; given the dedicated render with the URL absent, then the dark arm still wins (exit 0, no refusal marker); given the listener gate fails, then suppression wins first (exit 0, no refusal marker).
- Given a mutant that restores `"$URL"` on any converted curl, then the battery is RED (mutation).
- Verification commands for `soleur:qa` (offline): `bash apps/web-platform/infra/inngest.test.sh`, the three probe suites, `bash tests/scripts/test-argv-bearer-sweep.sh`, `bash apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh`.

## Dependencies & Risks

- **R1: GuardA window (high, by design).** `deploy-script-tests` (Infra Validation) is NOT in the required status checks of the main ruleset (required set read via `gh api repos/jikig-ai/soleur/rules/branches/main`: includes `test`, `e2e`, `Bash fixture tests for guard scripts`; no `deploy-script-tests`; #9081 is the open prerequisite for making it required), so the red GuardA rows do not block merge by themselves; at implementation read whether the required `test` context runs `cloud-init-inngest-bootstrap.test.sh` (`suite-shard-legs.tsv` registers it to leg 4 of the sharded infra legs) and record the answer in the PR body; Gate 3 is the CTO agent's evidence either way. Main is already red on three named rows. After merge the mint decides from the tree (HEAD vs `vinngest-v1.1.54`), mints the next tag and the bot opens another pin-bump PR; `infra-validation.yml` and the six-hourly `main-health-monitor.yml` may file a P1 `ci/main-broken` issue naming the GuardA assertions (precedents #10073, #9944). The PR body names the exact red rows; the bump PR's merge closes the window. #10330 stays untouched; it may merge before or after.
- **R9: required `e2e` flake (medium).** `e2e` IS a required check and is what holds #10330 red. This PR changes no app code, so an e2e failure here is the same environmental class (web server loss on the runner); the merging agent re-runs the failed job rather than treating it as a code signal, and no code change is made to chase it.
- **R2: false refusal on a liveness path (medium).** All four monitors are armed; a refusal pages within 90 s to 480 s. Mitigated by the 7 of 7 counts-only Doppler read (re-run at ship time), the permissive-superset class proven in `web-git-data-probe.sh` and `luks-monitor.sh`, and a fail-soft refusal.
- **R3: `EXPECTED_TESTS` conflict (medium).** Sibling open PRs also edit `tests/scripts/test-argv-bearer-sweep.sh`: #10294 (git-data wipe, non-draft) edits stage S4 hunks at lines near 4491-4529 and moves `EXPECTED_TESTS` 802 to 805 on a stale base; #10320 (stale registry draft WIP, superseded by merged #10322) edits stage S6 hunks near 6348-6696 adjacent to the S6-HB header. This PR's hunks sit in S6-HB (lines near 6722-6890) and the `EXPECTED_TESTS` literal. Whoever merges second re-measures the whole battery after their last rebase; the pin never decreases without a named reason (this PR deletes no row: it adds rows).
- **R4: stub fidelity (medium).** Suites that matched curl argv or read the last positional as the URL now must read stdin; a stub that records nothing must fail loudly (Guard 2 harness rows). Several negative rows go vacuous when the URL leaves argv; each is repointed, not deleted.
- **R5: inngest suite sits at its floor (low).** 451/451; the new rows raise it. Counting skipped dash rows toward the floor would let a deleted row hide behind a docker-less run, so the floor is two-tier (zot suite's shape) and the skip is loud; CI fails closed.
- **R6: shell portability (medium).** The bootstrap body runs under dash on Ubuntu 24.04: no `[[ ]]`, no process substitution, no bashisms in the added lines; `printf` is a builtin; the existing `dark_arm_emit_due` helper is reused unchanged.
- **R7: line numbers drift.** Every location is paired with a content anchor; re-anchor by content.
- **R8: `-x` tracing.** The NIC guard refuses xtrace; the probes are not traced on-host; the unit's inner `bash -c` expansion before the refusal is #9639, unchanged.

## Rollback

Revert the commit (no live state in the PR). Deliveries are idempotent: the revert re-delivers the old script bytes and the mint mints another tag. The GuardA window re-opens or closes accordingly.

## Success Metrics

- Population rows read from the battery stage S6-HB: heartbeat curl with the URL on argv = 0; `S6H_ALLOW` 4 to 0.
- Converted set 2 to 6 scripts (`luks-monitor.sh`, `web-git-data-probe.sh`, `inngest-bootstrap.sh`, three probes).
- #9757: the checklist item for #10093/#10120 is ticked by the CTO agent with the evidence above after the post-merge reads; the umbrella is closed by the last landing PR's hand-over, never by a closing keyword.

## Decision Classes

Mirrored in `knowledge-base/project/specs/feat-one-shot-argv-bearer-pr-c-inngest-probes/decision-challenges.md`.

| Item | Class | Ruling |
|---|---|---|
| Limiter design for the three probe refusal markers (own stamp each, interval) | technical | Ruled by CTO agent, 2026-10-15: own refusal stamp per script, never shared with a fault or canary limiter, uniform 3600 s; zot reuses `_window_open`/`_stamp` with an optional window argument defaulting to 1800; inngest-consumer and the NIC guard get a small inline helper each; future-dated or garbage stamp emits and the stamp is rewritten on emit. Not `_fault`, because a refusal must not mask a real fault line and vice versa. |
| Dash row source | technical | Ruled by CTO agent, 2026-10-15: digest-pinned ubuntu:24.04 container first and authoritative (same OS and dash as production); local dash only as a labelled "non-pinned dash" fallback when docker is absent; neither present is a loud counted skip; in CI the pinned-container row must run and pass (missing docker, failed pull or skipped row is a failure). Supersedes the source plan's local-dash-first preference. |
| GuardA sanctioned-window gate form, and ordering vs #10330 | technical | Ruled by CTO agent, 2026-10-15: named-row subset predicate (RED rows subset of the two pin rows and the byte-identity row; drifted list subset of `vector.toml` and `inngest-bootstrap.sh`; every other touched test file green), not a blanket exception; #10330 is not a prerequisite (the mint compares tree against the newest merged tag) and PR C may merge ahead of it. |
| Probe guard placed after the test seam and the empty-URL branch; refusal is fail-soft (WARN, no ping, unchanged exit) | technical | Settled mechanically by the precedent `web-git-data-probe.sh` (CTO ruling in the source plan); recorded here, not re-ruled. |
| Not creating follow-through probe scripts for PR C | technical | Settled by the brief: a CTO agent merges after machine-checkable gates and runs the post-merge reads; the source plan's probes served a held-merge pipeline. No operator item. |

## Sharp Edges

- Never write `Closes`, `Fixes` or `Resolves` anywhere in the PR (title included); `Ref #9757` is a required line.
- `-g` must stay on every converted heartbeat curl (`--config -` does not subsume it); `--disable` first, `--noproxy '*'`.
- Each `_ping` attempt needs its own `< <(printf ...)`: a process substitution is consumed once, so a `||` second attempt would read EOF.
- The inngest heartbeat body is POSIX sh: no `[[ ]]`, no process substitution, no `logger`/`echo`/`printf` line naming the URL variable except the one piping transport line, no heredoc feeding the config (Rule E). A local `/bin/sh` that is bash proves nothing; the dash row names its image.
- The heredoc stays QUOTED; the `sed` render of the dark arm anchors on the standalone sentinel line and must not be disturbed.
- The class literal `[!A-Za-z0-9._~:/?\&=%+-]` must appear exactly once per converted script on a non-comment line before the single `url = "` line; a second copy (even in a log string) breaks the S6-HB identity check.
- Do not add `pipefail` to `inngest-consumer-probe.sh` (the sourced registry probe sets it; the file resets `set +e +o pipefail`), and do not add `set -e` to any of the probes.
- Never print a token, URL or hash in a failure message; rows print counts and field names. The Doppler shape read prints only `ok`/`refused`.
- Do not mint, push or dispatch anything; a hand-pushed tag starts nothing (the build has no `push: tags` trigger).
- `knowledge-base/INDEX.md` may be created untracked by the learnings tool; never `git add` it (explicit paths only).
- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold fails `deepen-plan` Phase 4.6; this one states `aggregate pattern`.

## References

- Umbrella #9757; issues #10120, #10093; related #9081 (GuardA PR-context exemption), #8775 (tag must sit on main), #9639 (unit pre-refusal expansion), #10128 and #10255 (inngest-bootstrap changes since the preserved commit), #10330 (open pin bump), #10356 (this draft PR).
- Source plan (archived) and parent plan `knowledge-base/project/plans/2026-10-12-fix-argv-bearer-sweep-held-back-sites-htpasswd-and-inspect-evidence-plan.md`; preserved local commit `b48247d559` on `keep/9757-inngest-heartbeat-argv`.
- ADR-280 (and its 2026-10-12 addendum and the PR A, PR B follow-ups), ADR-232 (mint/bump), ADR-117 (heartbeat arming).
