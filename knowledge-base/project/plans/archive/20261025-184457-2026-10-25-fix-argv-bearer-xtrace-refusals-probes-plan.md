---
title: "fix: xtrace credential refusals on the inngest consumer probe and the rendered heartbeat body (issues #10093 + #10363)"
type: fix
date: 2026-10-25
slug: argv-bearer-xtrace-refusals-probes
branch: feat-one-shot-10093-argv-bearer-pair
issue: 10363
closes: [10363, 10093]
lane: single-domain
---

## Overview

Close the two open argv-bearer follow-ups in one PR.

**Issue #10363** (`type/security`): after PR C (#10356) the heartbeat URL is off
curl argv but is still a shell variable expanded in `printf`/`curl` words, so a
traced launch (`bash -x`, `sh -x`, `SHELLOPTS=xtrace`, `BASH_ENV`) prints it to
stderr — and journald ships that stderr off-box to Better Stack Logs. The issue
asks for a `case $- in *x*)` xtrace refusal (exit 78, value-free message, one
test row per script, lint baseline unchanged or reduced) on:

1. `apps/web-platform/infra/inngest-consumer-probe.sh` — **no refusal today**.
2. `apps/web-platform/infra/web-zot-consumer-probe.sh` — the issue says its
   refusal "covers only the pull token, not WEB_ZOT_CONSUMER_URL". **Already
   fixed by #10637** (merged 2026-10-20, five days after the issue was filed):
   the refusal at `web-zot-consumer-probe.sh:10-17` also fires on
   `WEB_ZOT_CONSUMER_URL_KEY` being set, and `web-zot-consumer-probe.test.sh`
   F6 rows (refusal[key only], refusal[credential only], canary-only[key only],
   mutant[hoist]) already assert exit 78 with the URL in no stream. Verify-only.
3. The `HEARTBEATSCRIPTEOF` body of `apps/web-platform/infra/inngest-bootstrap.sh`
   — the rendered `/usr/local/bin/inngest-heartbeat.sh` (`#!/bin/sh`, dash on
   Ubuntu) has no refusal; a POSIX `case $- in *x*)` works in dash.

**Issue #10093** (`type/security`): the residual argv-bearer list from the
umbrella sweep #9757. **Every listed site is already converted on `main`** —
verified by inspection, see Premise Validation. Deliverable: a verification
sweep + `Closes #10093`.

The issue bodies' line numbers have drifted; the consumer set above was
re-derived by inspection of the files, not from the bodies.

## Premise Validation

Checked every cited artifact against `origin/main` (the worktree is level with
`origin/main` for all files in scope):

| Cited artifact | Claim in issue | Reality on main | Plan response |
|---|---|---|---|
| `web-zot-consumer-probe.sh` xtrace refusal | covers only the pull token | covers pull token **and** `WEB_ZOT_CONSUMER_URL_KEY` (the only path by which the URL becomes non-empty); F6 test rows exist | no code change; verification AC |
| `inngest-consumer-probe.sh` | no xtrace refusal | confirmed — no `case $-` anywhere | add refusal + test row |
| `inngest-consumer-probe.service` wrapper | (not named; found by re-derivation) | `ExecStart` resolves `INNGEST_CONSUMER_URL="$${!INNGEST_CONSUMER_URL_KEY}"` in an inner `bash -c` — under `SHELLOPTS=xtrace` that export prints the URL **before** the script's refusal can run (the F6 class #10637 fixed for zot/nic-guard). Already acked in `doppler-injection-bound.test.sh` `WRAPPER_ACK_REASONS` as "NOT fixed ... adding one is a separate change" | fold in the #10637 pattern: script resolves the key after its refusal; ExecStart drops the inner export; ack entry removed (cardinality 2→1 — "baseline reduced") |
| `HEARTBEATSCRIPTEOF` body | no refusal | confirmed — `inngest-bootstrap.sh:184-368` has none; unit `ExecStart` is `doppler run -- ... -- /usr/local/bin/inngest-heartbeat.sh` (no wrapper expansion, no F6 residual) | add POSIX refusal at body top + test row in `inngest.test.sh` |
| `cloud-init-registry.yml` heartbeat curls | on argv | converted by #10322 (lines ~293, ~1095 use `--config -`) | verify only |
| 4 skill markdown snippets | bearer on argv | converted by #10185 — all credential curls use `--config -` | verify only |
| 3 probe scripts' heartbeat curls | on argv | converted by #10356 — all use `--config -` | verify only |
| S6-HB residual allowlist | "shrinks by deletion only" | `S6H_ALLOW=()` is already EMPTY (ceiling 0, pinned at `tests/scripts/test-argv-bearer-sweep.sh:6629-6723`) | no change; note the ceiling is already at zero |
| Tag mint | "the inngest body change mints a tag" | automatic: `mint-inngest-bootstrap-tag.yml` fires on push to main for `apps/web-platform/infra/inngest*`; it cuts `vinngest-vX.Y.Z` and dispatches `build-inngest-bootstrap-image.yml`, whose bump job rewrites the `IREF`/`ZIREF` `tag@sha256` pins by signed commit. `check-inngest-bootstrap-build.yml` gives a PR-time candidate `docker build` (no push) as a required check | no manual tag/pin step in this PR; recorded under Merge consequences |

**Not a fix-but-build case:** every site named in #10093 exists and is already
converted — nothing to build there. The two xtrace additions in #10363 are real
remaining work.

## Mechanism Minimality

**Property list** (what the ask buys):

- P1: a traced launch of `inngest-consumer-probe` exits 78 with a value-free
  message before any expansion of the heartbeat URL.
- P2: a traced launch of the rendered `inngest-heartbeat.sh` exits 78 with a
  value-free message before any expansion of `INNGEST_HEARTBEAT_URL`.
- P3: one behavioural test row per script proves exit-78 + value-free; lint
  baselines unchanged or reduced.
- P4: the #10093 residual list is verified clean and the issue closes.

**Mechanism check:** for each mechanism named in the ask —

- `case $- in *x*)` refusal → buys P1/P2; the established in-repo mechanism
  (`web-private-nic-guard.sh:12-14`, `inngest-bootstrap.sh:35-37`,
  `web-zot-consumer-probe.sh:10-17`) — reuse, do not invent.
- Resolution-inside-script for `inngest-consumer-probe` → buys P1 *on the unit's
  actual launch path*; the in-repo mechanism is the #10637 pattern
  (`_key_ok` + `URL="${!<KEY>:-}"` after the refusal, plain `doppler run` ExecStart).
- New test rows → buy P3; in-repo harnesses exist (`run_unit`-style ExecStart
  replay in `web-zot-consumer-probe.test.sh` F6 block; `run_ping`/`hb_run` in
  `inngest.test.sh`).

**Cut list:** none. No mechanism in the ask is already covered elsewhere, and
none is invented by this plan.

## Research Insights

- **The xtrace-refusal idiom** (sibling precedent, three copies):
  `case "$-" in *x*) printf '[FATAL] refusing to run under xtrace: this script handles a live credential and -x would print it (see #7797)\n' >&2; exit 78 ;; esac` —
  placed after `set -u`, before the header comment block, i.e. before any
  executable command. `inngest-consumer-probe.sh` is bash; the refusal goes at
  the top before `SCRIPT_DIR=` (line 64) and before the `source` of
  `inngest-registry-probe.sh`, so the refusal also covers the sourced body.
- **#10637 established the full pattern this plan folds in** for
  `inngest-consumer-probe`: script-side `_key_ok` (`local LC_ALL=C`, upper-case
  identifier only, LC_ALL=C pins ASCII ranges — the F6 locale[ranges off] row in
  `web-zot-consumer-probe.test.sh`/`web-private-nic-guard.test.sh` makes that
  case), `unset URL` then `URL=""` then `KEY_BAD=false`, resolve
  `URL="${!INNGEST_CONSUMER_URL_KEY:-}"` **after** the refusal, `KEY_BAD` line
  on the empty-URL WARN path, and an ExecStart that no longer expands anything:
  `ExecStart=/bin/bash -c 'doppler run --project soleur --config prd -- /usr/local/bin/inngest-consumer-probe.sh'`.
  `doppler-injection-bound.test.sh` `WRAPPER_ACK_REASONS` /
  `WRAPPER_ACK_CARDINALITY` (currently 2, entry at ~line 326) drops the
  inngest-consumer-probe entry; the surviving `web-git-data-probe.service`
  entry stays (see Scope Check — not one of the three scripts this issue names).
- **Env-file side needs nothing**: `server.tf:1285` and
  `web-probe-envwrite.sh:80` already write
  `INNGEST_CONSUMER_URL_KEY=INNGEST_CONSUMER_URL` (identity mapping — the
  service file comment at `inngest-consumer-probe.service:31-33` documents the
  indirection is kept "so all three web probes read identically").
- **The rendered heartbeat body** (`inngest-bootstrap.sh:184-368`): POSIX sh,
  first executable line `LOG_TAG="inngest-heartbeat"`. The refusal goes above it
  as the first command (Rule-A prologue shape); `printf` to stderr, never
  `logger -t "$LOG_TAG"` — `inngest.test.sh` bans any logger/echo/printf line
  that references `INNGEST_HEARTBEAT_URL` and the refusal message must be
  value-free AND name-free. The `@@DARK_ARM@@` sed render is anchored on
  `^@@DARK_ARM@@$` — unaffected. `inngest.test.sh` extracts the body via
  `awk '/^cat > "\$HEARTBEAT_SCRIPT" <</{f=1;next} /^HEARTBEATSCRIPTEOF$/{f=0} f'`
  (line ~298), renders both host variants via `render_ping_script`, and runs
  them via `run_ping`/`hb_run` — the new row runs a rendered copy under `sh -x`
  and asserts rc=78 + refusal on a non-trace line + the `CANARY_SENTINEL` URL in
  no stream.
- **Lint interaction**: `inngest-consumer-probe.sh` is currently out of
  `scripts/lint-shell-trace-credential-refusal.py`'s `SECRET_SIGNALS` scope; the
  folded-in `${!INNGEST_CONSUMER_URL_KEY}` puts it IN scope (SIGNAL_INDIRECT /
  `_KEY`), and the refusal we're adding makes it compliant — baseline file
  unchanged. `inngest-bootstrap.sh` is already in scope and compliant; the
  heredoc-body refusal doesn't change file-level evaluation. `WRAPPER_ACK`
  dropping 2→1 is the "baseline reduced" arm of the acceptance criterion.
- **Ordering pins that must not break**: `journald-config.test.sh:607` R3-4.5f
  pins the zot probe's `--canary-only` branch preceding its credential FATAL
  guards — we are NOT touching the zot probe, so it stays green.
  `tests/scripts/test-argv-bearer-sweep.sh` stage S6-HB (`S6H_CONVERTED` line
  6629, parity digests at 6752-6807) counts exactly one `url = "` config line
  and one shape-guard class per converted script and byte-compares
  `_hb_url_ok`/`_hb_curl` across four files — the new `case $-` blocks add
  neither a C nor a G record and touch no `_hb_*` definition.
- **Production-apply blast radius (issue-mandated constraint)**: edits to
  `inngest-consumer-probe.sh`/`.service` re-fire
  `terraform_data.inngest_consumer_probe_install` in the merge-triggered push
  apply (`apply-web-platform-infra.yml` -target set, line ~1269) — an SSH
  re-delivery to web-1, no host replace. The `inngest-bootstrap.sh` heredoc edit
  is NOT in any push-apply -target set; it mints a tag via
  `mint-inngest-bootstrap-tag.yml` (path filter `apps/web-platform/infra/inngest*`),
  builds the `soleur-inngest-bootstrap` image, and the bump job rewrites the
  `IREF`/`ZIREF` pins — all automatic. The new heartbeat body reaches live hosts
  on the next `deploy inngest` of the bumped tag / host replace, exactly the
  "batch with an operator-noticed apply" shape the issue prescribes.
  **This plan is code + tests only; it schedules no production apply.**
- **Adjacent residual, out of scope**: `web-git-data-probe.service` keeps the
  same ExecStart-wrapper expansion (`GIT_DATA_HEARTBEAT_URL_KEY`) and its script
  has no xtrace refusal — the surviving `WRAPPER_ACK_REASONS` entry already
  records it as "a separate change". Not one of the three scripts #10363 names;
  tracked, not silently dropped.
- **Institutional learnings applied**: `2026-10-14-my-stubs-checked-the-shape-of-argv-and-never-the-value-and-a-glob-registered-suite-degrades-the-affected-gate.md`
  (assert the VALUE's absence under trace, not just argv shape);
  `2026-10-06-an-argv-bearer-sweep-needed-a-ratchet-a-token-shape-guard-and-a-process-substitution-not-a-pipe.md`;
  `cq-test-fixtures-synthesized-only` (sentinel URLs/tokens only);
  `hr-never-git-stash-in-worktrees`, `hr-verify-repo-capability-claim-before-assert`
  (every "already done" claim above was verified by reading the file, not by
  trusting the issue text).
- **Code-review overlap check (Phase 1.7.5)**: see `## Open Code-Review Overlap`.

## Files to Edit

- `apps/web-platform/infra/inngest-consumer-probe.sh` — add the unconditional
  xtrace refusal (top, after `set -u`); move URL resolution into the script
  after the refusal: `_key_ok` + `unset URL`/`URL=""`/`KEY_BAD=false` +
  `URL="${!INNGEST_CONSUMER_URL_KEY:-}"`, `KEY_BAD` branch on the existing
  empty-URL WARN path (`_ping`, ~line 135). Header comment updated to name the
  new test seam(s) and the resolve-after-refusal contract.
- `apps/web-platform/infra/inngest-consumer-probe.service` — simplify
  `ExecStart` (line 40) to the sibling form
  `ExecStart=/bin/bash -c 'doppler run --project soleur --config prd -- /usr/local/bin/inngest-consumer-probe.sh'`;
  update the comment block (lines 29-38) that documents the old wrapper.
- `apps/web-platform/infra/inngest-bootstrap.sh` — inside the quoted
  `HEARTBEATSCRIPTEOF` body, add a POSIX `case $- in *x*) ... exit 78 ;; esac`
  as the first executable statement (above `LOG_TAG=`), plus a comment block in
  the house style naming #7797/#10363.
- `apps/web-platform/infra/inngest-consumer-probe.test.sh` — add the F6-shaped
  block: replay the real `ExecStart` text under `SHELLOPTS=xtrace` and
  `BASH_ENV` forms (refusal rc=78, value-free refusal line on a non-`+` row,
  sentinel URL in no stream); refusal[key only] row (KEY set, no other
  credential); positive control (untraced ExecStart delivers the URL to the
  heartbeat stub's stdin config exactly once); mutant[hoist] row proving the
  order pin (a lookup moved above the refusal leaks and the row sees it).
- `apps/web-platform/infra/inngest.test.sh` — add a row running a rendered
  heartbeat body under `sh -x`: rc=78, refusal text on a non-`+` line,
  `CANARY_SENTINEL` absent from stdout+stderr+logger sink; plus a positive
  control (existing untraced rows already cover the healthy path). Bump the
  suite's assertion-count comment block if it carries one (line ~3097 ledger).
- `apps/web-platform/infra/doppler-injection-bound.test.sh` — remove the
  `inngest-consumer-probe.service` entry from `WRAPPER_ACK_REASONS` (line ~326),
  drop `WRAPPER_ACK_CARDINALITY` 2→1, and reword its class-A `ACK_REASONS`
  entry to the sibling form ("the script resolves INNGEST_CONSUMER_URL_KEY by
  indirect expansion ...").

## Files to Create

- None. (Spec-side artifacts `tasks.md`, `decision-challenges.md` under
  `knowledge-base/project/specs/feat-one-shot-10093-argv-bearer-pair/` are
  workflow artifacts, not product files.)

## Implementation Phases

### Phase 1 — inngest-consumer-probe: refusal + resolve-after-refusal + unit

1. `inngest-consumer-probe.sh`: insert the xtrace refusal block after `set -u`
   (line 2), before the header comment — unconditional (the script has no
   `--canary-only` mode; `web-private-nic-guard.sh:12-14` is the template).
2. In the same file, replace `URL="${INNGEST_CONSUMER_URL:-}"` (line 83) with
   the #10637 block: `_key_ok` definition, `unset URL; URL=""; KEY_BAD=false`,
   `if _key_ok "${INNGEST_CONSUMER_URL_KEY:-}"; then URL="${!INNGEST_CONSUMER_URL_KEY:-}"; else KEY_BAD=true; fi`.
   Placement: after the refusal and before `_ping`'s first read of `URL`; the
   empty-URL WARN arm gains the KEY_BAD second line, byte-shape copied from
   `web-zot-consumer-probe.sh:145-147`.
3. `inngest-consumer-probe.service`: ExecStart loses the nested
   `bash -c 'export ...; exec ...'` wrapper → the sibling form; comment updated
   to say the script resolves the key after its refusal.
4. `doppler-injection-bound.test.sh`: remove the
   `inngest-consumer-probe.service` `WRAPPER_ACK_REASONS` entry, set
   `WRAPPER_ACK_CARDINALITY = 1`, reword the class-A `ACK_REASONS` entry to the
   sibling phrasing, update the comment counts.
5. `inngest-consumer-probe.test.sh`: add the F6 block mirroring
   `web-zot-consumer-probe.test.sh:1283-1404` — real-ExecStart replay under
   `SHELLOPTS=xtrace` and `BASH_ENV`, refusal[key only], positive untraced
   delivery, mutant[hoist] order row.

### Phase 2 — rendered heartbeat body: POSIX refusal + test row

6. `inngest-bootstrap.sh`: inside the `HEARTBEATSCRIPTEOF` heredoc, insert the
   refusal as the first executable line (above `LOG_TAG=`), POSIX form
   (`case $- in *x*)` — no quotes needed around `$-` in the case word; works in
   dash, verified against the sibling POSIX spellings. Message is printf to
   stderr, value-free and name-free (never `logger`, never the var name).
7. `inngest.test.sh`: add the traced-run row(s) beside the existing
   `run_ping`/`hb_run` harness — run a rendered body (`WEB_PING`, and
   `DEDICATED_PING` if the row structure supports it cheaply) with `sh -x` and
   a sentinel `INNGEST_HEARTBEAT_URL`; assert rc=78, the refusal text on a
   non-`+` line, the sentinel in no stream. Update the suite count ledger
   comment if present.

### Phase 3 — verification + issue closure evidence

8. Re-run the derived sweep proving #10093's list is clean: the S6-HB scan
   (`s6h_scan`) over `apps/web-platform/infra/*.sh` reports zero violations and
   `S6H_ALLOW` stays empty; `git grep` checks for `Authorization`/URL-on-argv in
   the four skill files and the two `cloud-init-registry.yml` heartbeat curls.
9. Green run of every touched/sibling suite:
   `inngest-consumer-probe.test.sh`, `inngest.test.sh`,
   `web-zot-consumer-probe.test.sh`, `doppler-injection-bound.test.sh`,
   `journald-config.test.sh`, `infra-config-gate.test.sh` (byte-length/newline
   invariants over infra/*.sh), `tests/scripts/test-argv-bearer-sweep.sh`
   (S6-HB rows), `lint-shell-trace-credential-refusal.test.sh`, and the lint's
   repo-wide run for A/B/C + D + E baselines.
10. PR body carries `Closes #10363` and `Closes #10093` + the merge-consequence
    note (push-apply redelivery + auto tag mint), so the operator sees the
    apply it batches with.

## Acceptance Criteria

- [ ] AC1: `SHELLOPTS=xtrace` and a `BASH_ENV`-armed `set -x` launch of the real
      `inngest-consumer-probe.service` `ExecStart` exits 78 with a refusal
      message that contains neither the URL value nor its variable name, and
      the sentinel URL appears in no captured stream.
- [ ] AC2: `inngest-consumer-probe.service` `ExecStart` contains no indirect
      expansion (no `${!...}`); `doppler-injection-bound.test.sh` has no
      `inngest-consumer-probe.service` `WRAPPER_ACK` entry and
      `WRAPPER_ACK_CARDINALITY` is 1.
- [ ] AC3: an untraced `inngest-consumer-probe` run resolves the URL through
      `${!INNGEST_CONSUMER_URL_KEY}` and delivers it to the heartbeat curl on
      the stdin config exactly once (behaviour identical to today).
- [ ] AC4: `sh -x` on the rendered `inngest-heartbeat.sh` body (web render and,
      where the harness supports it, the dedicated render) exits 78 with a
      value-free, name-free refusal; `CANARY_SENTINEL` appears in no stream;
      `sh -n` stays clean on both renders.
- [ ] AC5: `web-zot-consumer-probe.sh` URL-gate refusal is verified covered —
      the existing F6 rows (`refusal[key only]`, `canary-only[key only,
      traced]`, `mutant[hoist]`) are green on this branch; no code change to
      that file.
- [ ] AC6: `tests/scripts/test-argv-bearer-sweep.sh` stage S6-HB is green:
      zero argv violations over `apps/web-platform/infra/*.sh`,
      `S6H_ALLOW` remains empty (ceiling 0), converted-script identities and
      `_hb_*` parity digests unchanged.
- [ ] AC7: `scripts/lint-shell-trace-credential-refusal` repo-wide run is green
      with **unchanged** baseline files (A/B/C, D, E) — the two files gaining
      refusals are compliant, not baselined.
- [ ] AC8: #10093 verification sweep recorded: every site the issue lists —
      three probe scripts, `cloud-init-registry.yml` `disk_heartbeat_url` +
      `liveness_heartbeat_url` curls, and the four skill markdown files — uses
      `curl --config -` (no credential-bearing argv); the one residual the
      issue flags (the baked URLs' readability via the Hetzner metadata API as
      `user_data`) is recorded as out-of-fix-shape, not silently dropped.
- [ ] AC9: PR body: `Closes #10363`, `Closes #10093`, and the merge-consequence
      block (push-apply redelivery of `terraform_data.inngest_consumer_probe_install`
      to web-1; auto `vinngest-v*` tag mint + image build + pin bump; new
      heartbeat body lands on hosts at the next `deploy inngest`/replace —
      no plan-scheduled production apply).
- [ ] AC10: all named suites in Phase 3 item 9 run green (pre-existing reds, if
      any, recorded and not absorbed).

## Test Scenarios

| # | Scenario | Where | Expected |
|---|---|---|---|
| T1 | `SHELLOPTS=xtrace` replay of real `inngest-consumer-probe.service` ExecStart, KEY set, sentinel URL | `inngest-consumer-probe.test.sh` (new F6 block) | rc=78, refusal on a non-`+` line, sentinel absent everywhere |
| T2 | `BASH_ENV` trace-injection arm of the same replay | same | rc=78, same assertions |
| T3 | refusal[key only]: KEY set, no other credential, traced | same | rc=78, refusal text, no heartbeat call attempted |
| T4 | positive: untraced ExecStart delivers sentinel URL to stub curl's stdin `url = "..."` exactly once | same | rc=0, one cfg line, URL in no argv row |
| T5 | mutant[hoist]: URL lookup moved above the refusal leaks under `SHELLOPTS=xtrace` | same | sentinel observed in trace — proves the order row is load-bearing |
| T6 | `sh -x` rendered heartbeat body (WEB_PING), sentinel `INNGEST_HEARTBEAT_URL` | `inngest.test.sh` | rc=78, refusal non-`+` line, sentinel absent from stdout/stderr/logger |
| T7 | `sh -n` on both renders stays clean; `LOG_TAG` assertion unchanged | `inngest.test.sh` (existing rows) | green |
| T8 | `doppler-injection-bound.test.sh` | suite | wrapper stage sees no `inngest-consumer-probe.service` expansion; cardinality 1 |
| T9 | S6-HB rows | `test-argv-bearer-sweep.sh` | green; `S6H_ALLOW` empty; parity digests stable |
| T10 | `journald-config.test.sh` R3-4.5f ordering pin | suite | green (zot probe untouched) |

## Guard Contract

### Guard 1 — xtrace refusals on the two new surfaces

**Property.** No expansion of the heartbeat-URL credential can be traced
before the script exits: under any trace-armed launch (`-x`, `SHELLOPTS`,
`BASH_ENV`), each named script exits 78 emitting only a value-free,
name-free refusal.

**Assembly.** The launch paths the property quantifies over: (a) the
`inngest-consumer-probe.service` `ExecStart` chain (outer `bash -c` →
`doppler run` → target script) — the chokepoint is the FIRST executable
statement of `inngest-consumer-probe.sh`, which is reachable only if the
wrapper expands nothing, so the ExecStart is part of the assembly;
(b) the rendered `/usr/local/bin/inngest-heartbeat.sh` — chokepoint is the
first executable line inside the quoted `HEARTBEATSCRIPTEOF` heredoc;
(c) direct `bash -x`/`sh -x` invocation of either script by an operator.

**Mutation matrix.**

| Mutation | Must be RED because |
|---|---|
| Delete the `case $-` block from `inngest-consumer-probe.sh` | traced replay in T1 leaks the sentinel — row goes red |
| Keep the refusal but leave `export INNGEST_CONSUMER_URL="${!...}"` in the unit ExecStart | trace prints the export before the script runs — T1 red; also `doppler-injection-bound` wrapper stage flags it |
| Hoist the `URL="${!...}"` resolution above the refusal in the script | mutant[hoist] row T5 sees the sentinel in the trace |
| Emit the URL value or var name in the refusal message | T1/T6 stream-absence assertions red |
| Delete the body refusal inside `HEARTBEATSCRIPTEOF` | T6 leaks the sentinel under `sh -x` |
| Make the refusal conditional on `INNGEST_CONSUMER_URL` being set | a traced launch with the var unset-but-later-armed would pass — the unconditional form is required; a conditional-arm mutant must go red on a traced launch |
| Must-PASS: untraced healthy run (T4) and `sh -n` syntax rows (T7) | proves the guard rejects trace, not execution — catches a vacuous always-78 refusal |

**Anchor.** The refusals' correctness does not depend on a stored value in
the same diff; the assertion is behavioural (run the real artifact under
trace), and `doppler-injection-bound.test.sh` + S6-HB independently pin the
unit/script shapes.

## Observability

```yaml
liveness_signal:
  what: "the probes' existing Better Stack heartbeats are unchanged; the refusals only fire on traced launches, which production never performs — the observable new signal is the [FATAL] refusal line on stderr"
  cadence: "on traced launch only"
  alert_target: "journald -> vector Source 4 -> Better Stack (SyslogIdentifier inngest-consumer-probe / inngest-heartbeat already allowlisted; no vector change)"
  configured_in: "inngest-consumer-probe.service / inngest-heartbeat.service (existing units)"
error_reporting:
  destination: "stderr -> journald -> Better Stack; exit 78 also reds the systemd unit (oneshot) for the inngest probe"
  fail_loud: "yes — exit 78 non-zero; value-free refusal line"
failure_modes:
  - mode: "operator traces a launch for debugging -> exit 78 + refusal line; the intended behaviour, decodable via journalctl -t / Better Stack"
    detection: "SOLEUR-refusal line on the unit's tagged channel"
    alert_route: "journald -> vector Source 4 -> Better Stack"
  - mode: "wrapper regression: a future ExecStart re-adds an indirect expansion -> doppler-injection-bound.test.sh wrapper stage flags it at CI"
    detection: "static guard at PR time"
    alert_route: "CI check failure"
logs:
  where: "journald, shipped via existing Source 4 allowlist entries (no allowlist edit needed — SyslogIdentifier tags are unchanged)"
  retention: "Better Stack per existing policy"
discoverability_test:
  command: "bash -c 'SHELLOPTS=xtrace bash apps/web-platform/infra/inngest-consumer-probe.sh 2>&1 | grep -c \"refusing to run under xtrace\"'"
  expected_output: "1"
```

## Open Code-Review Overlap

None. Queried `gh issue list --label code-review --state open` (2026-10-25,
200 issues) for all six edit-target paths (`inngest-consumer-probe.sh`,
`inngest-consumer-probe.service`, `inngest-bootstrap.sh`,
`inngest-consumer-probe.test.sh`, `inngest.test.sh`,
`doppler-injection-bound.test.sh`) — zero issue bodies name any of them.

## User-Brand Impact

- **If this lands broken, the user experiences:** no end-user-visible change —
  worst realistic failure is a false 78 on an untraced path (a probe heartbeat
  suppressed → absence-of-ping alarms as "host down", an operator-facing false
  page, not user-facing).
- **If this leaks, the user's [data / workflow] is exposed via:** this change
  *reduces* exposure — it closes a path by which a heartbeat bearer URL reaches
  off-box logs; a miss leaves status quo, it does not open anything new.
- **Brand-survival threshold:** none
  - `threshold: none, reason: security-hardening of existing probe scripts — no new data surface, no new processing, no user-facing surface; touches only host-side monitoring scripts and their tests`

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change on
existing host-monitoring scripts and their suites. Product/UX mechanical
override checked: no `components/**/*.tsx`, `app/**/page.tsx` or
`app/**/layout.tsx` in the Files lists — no UI surface.

## Architecture Decision (ADR/C4)

None required. This applies two already-decided patterns (ADR-280's
stdin-config transport; #10637's resolve-after-refusal unit/script shape) — no
new boundary, no reversal, no extension of an existing ADR. C4 checked against
`model.c4`/`views.c4`/`spec.c4` for the feature's actors/systems/relationships:
no new external human actor, no new external system/vendor (Better Stack,
Doppler, GHCR, Hetzner, systemd already modeled), no new container or data
store, no changed access relationship — a credential-delivery detail inside an
existing host, already covered.

## Encryption Posture

Skipped per Phase 2.11's own predicate: no new persistent store and no new
cross-component connection (no `.tf` edit, no `.sql`, no `cloud-init.*` edit —
the `.service`/`.sh` files are inside an already-provisioned surface).

## Scope Check

### Ask Mapping

| Ask (quoted/paraphrased from issue text) | Status | Plan coverage |
|---|---|---|
| "add the xtrace refusal (exit 78 with a value-free message) to inngest-consumer-probe.sh" | mapped | Phase 1 items 1-2, AC1, T1-T5 |
| "web-zot-consumer-probe.sh's URL gate (its existing refusal covers only the pull token)" | mapped — **already satisfied by #10637**; AC5 verifies, no code change |
| "the HEARTBEATSCRIPTEOF body of apps/web-platform/infra/inngest-bootstrap.sh (a POSIX `case $- in *x*)` works in dash)" | mapped | Phase 2 items 6-7, AC4, T6-T7 |
| "one test row per script" | mapped | T1-T3 (probe), T6 (heartbeat), existing zot F6 rows (AC5) |
| "lint baseline unchanged or reduced" | mapped | `WRAPPER_ACK` drops 2→1 (reduced); refusal-lint baselines unchanged — AC2/AC7 |
| "the inngest-bootstrap.sh body change mints a tag — check what that entails in the repo's release machinery" | mapped | Premise Validation row 9 (auto mint→build→pin-bump chain); AC9 merge-consequence note |
| #10093 "take heartbeat URLs and bearer tokens off curl argv" at all named sites | mapped | verified already-converted on main — Phase 3, AC8; issue closes |
| "plan for code + tests, not a production apply" | mapped | AC9 records the auto-fired apply + tag chain; no apply step in the plan |

### Plan-Item Provenance

| Plan item | Provenance | Justification |
|---|---|---|
| `inngest-consumer-probe.sh` refusal + test rows | asked | #10363 gap 1 |
| heartbeat-body refusal + test row | asked | #10363 gap 3 |
| zot URL-gate verification | asked | #10363 gap 2 — verified satisfied by #10637 |
| `inngest-consumer-probe.service` ExecStart wrapper fix + `doppler-injection-bound.test.sh` ack removal | inferred | without it, `SHELLOPTS=xtrace` propagating through `doppler run` traces the inner `export` and prints the URL before the script's refusal runs — the literal acceptance ("script exits 78") would hold while the issue's stated property fails on the unit's real launch path; mirrors #10637; the `WRAPPER_ACK` entry already acks it as pending separate work |
| `web-git-data-probe.service` same-class wrapper | inferred — declined | not one of the three scripts #10363 names; already tracked as the surviving `WRAPPER_ACK_REASONS` entry ("a separate change"); noted for follow-up, not silently dropped |

### Split Assessment

- Recommendation: single PR. The two issues share one fix shape, one test idiom, and one merge train (the same push-apply `-target` set and the same auto tag mint); splitting would land the heartbeat-body edit in one merge and the probe edits in another for no independent-rollback benefit — both are additive refusals + test rows.



## Merge consequences (operator-facing, no manual steps)

- Push to main fires `apply-web-platform-infra.yml` (path glob
  `apps/web-platform/infra/**`), whose -target set includes
  `terraform_data.inngest_consumer_probe_install` — an SSH re-delivery of the
  probe script + unit to web-1. Routine, batched with this merge exactly as the
  issue prescribes.
- Push to main fires `mint-inngest-bootstrap-tag.yml` (path
  `apps/web-platform/infra/inngest*`) → auto `vinngest-v*` tag →
  `build-inngest-bootstrap-image.yml` (dispatched, main) → image publish →
  `bump-cloud-init-pin` signed commit updating `IREF`/`ZIREF` pins.
- The rendered heartbeat body reaches live hosts on the next `deploy inngest`
  of the bumped tag or a host replace — the "batch with an operator-noticed
  apply" shape #10093 prescribes. Nothing in this plan schedules an apply.

## Sharp Edges

- A plan whose `## User-Brand Impact` section omits the threshold fails
  deepen-plan — it is present above (`none`, with the sensitive-path scope-out
  sentence).
- Do NOT "simplify" the fold-in back to a script-only refusal: the ExecStart
  wrapper is the actual launch path and `SHELLOPTS=xtrace` propagates through
  `doppler run` into it. The WRAPPER_ACK machinery exists to pin exactly this.
- Do NOT touch `web-zot-consumer-probe.sh` — its refusal + F6 rows are already
  correct; `journald-config.test.sh:607` pins its `--canary-only`-before-FATAL
  ordering, and S6-HB parity-digests byte-compare its `_hb_*` pair.
- The heartbeat-body refusal must not name `INNGEST_HEARTBEAT_URL` in any
  logger/echo/printf line (`inngest.test.sh` asserts that shape is banned) and
  must not use `logger` before `LOG_TAG` exists — printf to stderr above
  `LOG_TAG=` is the correct form.
- `infra-config-gate.test.sh` scans every `infra/*.sh` for byte-length and
  newline-position invariants; keep inserted blocks plain POSIX (no tabs
  surprises, no CRLF).
- `vector-pii-scrub.test.sh` derives the tag set from `LOG_TAG="..."` lines —
  add no second `LOG_TAG=` and no inline `logger -t <literal>`.

## Plan Review

Pending — the plan-review panel runs next, per the skill's Plan Review phase.

## Deepen-pass (2026-10-25)

Gates evaluated in-line (subagent fan-out unavailable in this harness; each gate
executed against the plan file directly):

- 4.6 user-brand impact: present, `threshold: none` + non-empty scope-out reason
  (diff touches `apps/*/infra/`, a sensitive path).
- 4.7 observability: five fields present; `discoverability_test.command` first
  token `bash` (probe-verb allowlist), no `ssh`, sub-15s, `expected_output: "1"`
  is a matchable literal.
- 4.8 PAT sweep: no match.
- 4.9 UI wireframe: no UI-surface files — skipped.
- 4.10 encryption posture: no `.tf` / `.sql` / `cloud-init.*` / `docker-compose`
  edit and no new store or connection — recorded skip in plan.
- 4.11 guard contract: `lint-guard-contract.py` green (1 entry; field format
  corrected to the canonical `**Property.**`/`**Assembly.**`/`**Mutation
  matrix.**` spans during this pass).
- 4.12 scope check: `### Ask Mapping` / `### Plan-Item Provenance` / `### Split
  Assessment` present; zero `unmapped`; one `inferred` item (ExecStart wrapper)
  justified; `Recommendation: single PR` present.
- 4.13 task design: no new autonomous-task surface — skipped.
- 4.4 precedent-diff: pattern-bound behaviour verified against sibling
  precedents read in-tree (`web-private-nic-guard.sh`, `web-zot-consumer-probe.sh`
  refusal + `_key_ok`/`${!KEY}` resolution, the F6 test block shape).
- Citations verified live: #10093, #10363, #9757 OPEN; #10356, #10637, #10185,
  #10322, #10120 state checked via `gh`. Rule IDs cited (`hr-*`, `cq-*`) grep
  active in `AGENTS.rules.md`.
