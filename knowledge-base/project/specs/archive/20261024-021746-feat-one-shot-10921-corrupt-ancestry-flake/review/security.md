# Security Review — PR #10953 (feat-one-shot-10921-corrupt-ancestry-flake)

Reviewer: `soleur:engineering:review:security-sentinel` · 2026-10-23 · report-only seat
Diff base: `origin/main...HEAD` on worktree `feat-one-shot-10921-corrupt-ancestry-flake`

## Executive Summary

**Verdict: NO P0. One P1 (hardening gap vs. the standing log-injection rule), five P2.**

The diff is a guard-shaped change: a new shared test lib forging corrupt git object graphs
(`plugins/soleur/test/lib/git-corrupt-graph.sh`), counted-skip machinery wired into two CI
fixture suites, and a second run-source added to the standing skip-persistence probe plus
monitor-workflow alert-text edits. The attack surfaces I was asked to check — command
injection via log-derived strings, GitHub annotation forgery, `gh` write surfaces, skip-
machinery guard bypass, and xtrace/credential hygiene — are all handled correctly or are
bounded by design. The one finding above the P2 line is that `corrupt_skip`'s sanitizer
implements the plan's pinned `%`→`%25` + CR/LF contract exactly, but that contract is
narrower than the corpus log-injection rule (C0 range + `\x7f` + U+2028/U+2029), and this
function is the single sanitization chokepoint for every future call site.

Settled-rulings compliance: forged-oid over repack-aware `rm` (implemented), only
walk-contract skip-eligible (implemented — invariants are fail-only/zero-counted), probe
extended in this PR (implemented), tier aggregate pattern (consistent with diff scope:
test/monitor files only; no SUT or gating-logic drift).

## Verified safe (the requested check list)

- **Command injection via log-derived strings — CLEAN.** In the probe
  (`scripts/followthroughs/t5-skip-persistence-bound-7510.sh`), `gh run view --log`
  output lands in `$log` and is consumed only by `grep -qF`/`grep -cF` with fixed-string
  patterns (L273-284). Log content is never re-emitted: every `echo`/`printf` carries
  constants (`_uname`, `_disc`, `_marks` from `GUARD_UNITS`, counters) or nothing. In the
  suites, git-derived strings (`walk_err`, `b7a_set`, `b7a_err`, `i6_err`, `i6_rc`) are
  only compared and `printf`'d — never eval'd or substituted into a command. The monitor
  workflow's `SUMMARY` output is `probe.out + probe.err`, which contain only
  probe-generated constants/numbers — no log-derived text reaches the issue body.
- **Annotation forgery — PINNED CONTRACT MET.** `corrupt_skip`
  (`git-corrupt-graph.sh:236-240`) applies `%`→`%25` **before** the CR/LF strip — the
  correct order (a literal `%0A` in the input is neutralized rather than decoded). The
  `::warning::` payload goes to stdout and `SKIP (loud):` to stderr, matching the plan
  pin and the mint suite's `fl-encode` precedent (`test-mint-inngest-bootstrap-tag.sh:1221`).
  See P1 for the residual gap.
- **`gh` write surfaces — CLEAN.** Probe reads only (`gh run list`, `gh run view --log`).
  Workflow writes are `gh issue list` (read, `--state open`, quoted title literal,
  `--limit 200`, error→refuse-to-file), `gh issue comment` / `gh issue create` with a
  literal title and `--body-file` of constants. Issue dedupe is open-only with failure
  fatal, not fall-through-to-create. Workflow permissions are least-privilege:
  `contents: read`, `issues: write`, `actions: read`.
- **Guard bypass via skip machinery — CLEAN.** `CORRUPT_WALK_PROBE_FORCE` accepts only
  `skip`; any other value calls `fail()` then degrades to the loud arm — a force-to-present
  knob cannot exist (`git-corrupt-graph.sh:200-211`). The knob is set nowhere in CI (only
  inside suite selftests). Skip-eligibility is confined to the walk-contract probe;
  construction invariants are fail-only/zero-counted. Every skip charges its declared
  cost into `SKIPPED_ASSERTIONS`, folds into `TOTAL` against `MIN_ASSERTIONS`, and is
  bounded by `SKIP_CAP` (bump 28 = 8+9+8+3; mint 3). Declared costs verified against the
  real branches: `assert_refused`=7, `assert_excluded`=9, so B7/B7c=8, B7a=9, I6=3,
  fl.walk=3 — all exact. Any real skip in a sampled run FAILs the monitor.
- **xtrace/credential hygiene — CLEAN.** The probe retains the exit-78
  refuse-to-trace-with-live-`GH_TOKEN` guard (`t5-skip-persistence-bound-7510.sh:69-77`);
  no `set -x` added anywhere in the diff; the token is bound only for `gh` calls;
  `gh` stderr is `2>/dev/null` at every call site; no run-log or token content is echoed.
- **Fixture write confinement — CLEAN.** All `hash-object -w`/`update-ref` writes go
  through `git -C <repo>` on fixture repos; `_corrupt_assert_repo` rejects an empty
  operand and delegates to `assert_fixture_dir` (absolute-path/`..`/synthetic-fs/root
  refusal) when the suite defines it. Census self-check currently yields zero hits
  (verified by running it).
- **Selftest marker poisoning — handled.** Exercised `SKIP (loud):`/`::warning::` lines
  are captured into files (`$TMP/skip.st*`, `$LAST_OUT`), never the suite's streams —
  required because selftest row names (`g1b.selftest-*`, `fl.selftest-*`) match the
  monitor's `g1b.`/`fl.` prefixes.

## Findings

### P1 — `corrupt_skip` sanitizer is narrower than the standing log-injection rule

`plugins/soleur/test/lib/git-corrupt-graph.sh:236-237`:

```bash
reason=${reason//'%'/'%25'}
reason=${reason//[$'\n\r']/}
```

The bracket expression strips only `\n` and `\r`. Every other C0 control byte
(`\x00-\x08`, `\x0b`, `\x0c`, `\x0e-\x1f` — including `ESC`, which enables terminal-
escape injection into rendered logs/annotations), `\x7f`, and the Unicode line
separators U+2028/U+2029 pass through verbatim into both the `SKIP (loud):` stderr line
and the `::warning::` annotation payload. The agent's standing checklist requires
log-injection sanitizers to cover `\x7f`, `\u2028`, `\u2029` in addition to `\x00-\x1f`
(`knowledge-base/project/learnings/security-issues/2026-04-17-log-injection-unicode-line-separators.md`).

Exploitability **today** is near-zero: every call-site reason embeds constrained git
stderr (`walk_err`, `b7a_err`, `i6_err` — `error:`/`Could not read` text plus sha-shaped
tokens). But `corrupt_skip` is the designed single chokepoint for all future skip
producers; a later call site embedding less-constrained evidence inherits the gap
silently. Fix is one line: widen the strip to `[$'\x00-\x1f\x7f']` and remove the two
Unicode separators (bash: `${reason//$'\u2028'/}` + `${reason//$'\u2029'/}`, or a
`sed`/`LC_ALL` pass). Note `$row` is unsanitized too — bounded today by the roster-parity
single-quoted-literal enforcement, but the same chokepoint argument applies; consider
asserting `[ "$row" = "${row//[$'\x00-\x1f\x7f']/}" ]` or sanitizing it alongside.

### P2 — Roster-parity self-checks only see single-quoted call-site names

`test-bump-inngest-bootstrap-pin.sh:2987`, `test-mint-inngest-bootstrap-tag.sh:2009`,
and the probe test's (p) row all anchor on `corrupt_skip[[:space:]]+'[^']+'`. A future
`corrupt_skip "x.row" ...` (double quotes) or `corrupt_skip "$var" ...` evades every
parity check — an unregistered skip producer that the monitor cannot see would land
silently. Suggest a second assertion that every `corrupt_skip` invocation in the file
matches the registered-prefix pattern *in some quoting form* (e.g., grep all
`corrupt_skip ` call sites, extract the first operand regardless of quoting).

### P2 — Suite discriminator is forgeable text inside the log it discriminates

`t5-skip-persistence-bound-7510.sh:179-182` keys "the suite ran" on the literal
`=== test-<name>.sh ===` banner — text any step in the same job log can print. A
pull_request whose run prints the banner (a contributor test echoing suite names, or a
malicious PR) marks that suite `observed` even when run-all never executed it, turning
a would-be-TRANSIENT into `unit_obs >= 1`. It cannot hide real markers (those live in
the same log), so the bound is: an un-run suite reading as observed — the un-run-
instrument class this file exists to prevent, at lower confidence. Consider AND-ing the
banner with suite-emitted terminal evidence (e.g., that suite's `Results:` line), or
document the residual explicitly.

### P2 — PR-controlled logs can force a monitor FAIL → deduped alert issue

Source 2 samples `pull_request` runs by event. A PR author can emit
`SKIP (loud): g1b.x` in their own test output → `any_fail=1` → the monitor files an
alert issue (deduped to one open issue; per-source lines name the origin). The code
acknowledges this ("a PR introducing a skip arm trips the monitor pre-merge (real
evidence, labelled by source)") — correct posture for a private repo — but the filed
issue body could additionally note that hits may originate from unmerged-branch runs so
triagers check the run source before treating it as runner-image regression. Nuisance
severity; noise decays as the 20-run window advances.

### P2 — Declared skip costs are reviewer-verified constants with no automated parity

Each `corrupt_skip` call hardcodes its taken-branch assertion count (8/9/8/3, 3). If a
helper gains an assertion or a row gains a check, the declared cost silently mis-charges:
over-charge masks coverage loss inside the `SKIP_CAP` envelope; under-charge drags
`TOTAL` toward the floor. `MIN_ASSERTIONS` + `SKIP_CAP` bound the drift but do not
localize it. A cheap guard: a selftest row asserting each skip-eligible row's declared
cost equals its counted real-branch assertions (the st_run machinery already measures
deltas), or at minimum a comment convention coupling the two.

### P2 — Minor machinery notes (batch)

- `SOLEUR_FIXTURE_PACKED` (AC4 packed-store arm) is read by the lib but set nowhere in
  CI — the arm is dormant/manual; if continuous packed-layout coverage was intended it
  is unobserved.
- `_corrupt_assert_repo`'s standalone fallback is non-empty-only; suites that don't
  define `assert_fixture_dir` get weaker operand validation (header documents the
  caller contract — acceptable, noted).
- Census regex uses unescaped `.` in `.git`/`objects` and enumerates `rm`/`unlink`/
  `find -delete`/`rm -rf` only — a deletion spelled another way (`git clean`,
  truncation, a different verb) escapes it; scope comment covers `.github/scripts/test/`
  only, external sites tracked in #10956.
- `pg_ids` construction (`{ gh|jq; gh|jq; } | awk | head`) can SIGPIPE `awk` under
  `pipefail` — harmless without `set -e`, and a `gh run list` failure is masked into
  "no runs" → TRANSIENT (safe direction, same verdict either way).
- `mkcase`'s generated `gh` stub keys `view` on "last `[0-9]*` arg" — a future numeric
  trailing flag on `gh run view` would misroute; test-only, fails loudly.

## Risk matrix

| Severity | Count | Items |
|---|---|---|
| Critical/P0 | 0 | — |
| P1 | 1 | sanitizer breadth vs. corpus rule |
| P2 | 5 | roster quoting; forgeable discriminator; PR-forged markers; cost parity; minor batch |

## Remediation roadmap

1. Widen the `corrupt_skip` strip per P1 (one-line change, suite green expected).
2. Add the unanchored-quoting roster assertion (P2-1).
3. Defer or implement the stronger discriminator (P2-2) and the issue-body "pre-merge
   source" note (P2-3); file a follow-up if deferred.
4. Cost-parity check (P2-4) optional but cheap via existing delta machinery.
