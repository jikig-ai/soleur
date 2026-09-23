---
title: "fix(test): vendor-bundle-coverage TS4 lefthook-glob predicates race SIGPIPE under pipefail"
type: fix
date: 2026-09-23
slug: fix-vendor-bundle-coverage-sigpipe-race
branch: feat-one-shot-vendor-bundle-coverage-sigpipe
issue: 7005
lane: cross-domain
brand_survival_threshold: none
---

# fix(test): vendor-bundle-coverage TS4 lefthook-glob predicates race SIGPIPE under pipefail

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed). No spec.md exists for this
branch; the change is test-only and no domain fan-out is warranted (see Domain Review).

## Plan Status

Recovered from partial artifact: the planning subagent was stopped by an API session limit
partway through `soleur:deepen-plan`. The plan body (through `## Acceptance Criteria`) was on
disk and was reconciled for internal consistency before `soleur:work`; see
`knowledge-base/project/specs/feat-one-shot-vendor-bundle-coverage-sigpipe/session-state.md`.

## Overview

`plugins/soleur/test/vendor-bundle-coverage.test.sh` (Guard 2, #8122) runs under
`set -euo pipefail`. Its two TS4 lefthook-glob predicates pipe one grep into a second grep that
exits early:

```bash
if grep -E '^[[:space:]]+-[[:space:]]' "$LEFTHOOK" | grep -qF "$prefix/NOTICE"; then
if grep -E '^[[:space:]]+-[[:space:]]' "$LEFTHOOK" | grep -qF "$prefix/references/"; then
```

When `grep -q` exits on its first match while the upstream grep still has unwritten output, the
upstream write fails. `pipefail` promotes that failure, the `if` reads false, and the suite
reports a false `FAIL: … references/ not covered by any lefthook glob` for a bundle that IS
covered. CI logged exactly that, preceded by `grep: write error: Broken pipe`.

Fix: move the lefthook predicate into one small pipe-free helper that captures the producer into
a variable and tests it with a herestring. Add a regression block (TS7) that runs **the same
helper** against a synthesized >256 KiB lefthook-shaped fixture with the needle on line 1, plus a
one-line decoy that proves the `run:`-line exclusion still holds.

The file's two `printf … | grep -q` sites (TS3 and the TS4 `run:` predicate) are converted the
same way **for consistency, not because they race**. `printf` emits its well-under-4 KiB output in
one write, and `grep -q` cannot exit before that write lands. Reviewers should not look for a race
there.

PR body: `Ref #7005` (NOT `Closes`). The repo-wide sweep stays in #7005 / #6601 / #7432.

## Research Insights

### Premise Validation

- `#7005` OPEN — "sweep the remaining pipefail + grep -q fail-open sites in scripts/ and plugins/". Holds; this PR is one slice of it, hence `Ref`.
- `#6601` OPEN — "sigpipe guard class … conversion deferred pending a design call". Holds.
- `#7432` OPEN — "remove the JOBS=1 stopgap …; grep -q linter". Holds.
- PR `#7240` MERGED — its `apps/web-platform/infra/git-data-luks.test.sh` uses the `grep -qF '…' <<<"$src"` herestring form (e.g. its `doppler_$${DOPPLER_VERSION}` and `sha256sum -c -` probes). That is the convention adopted here.
- `.claude/hooks/grep-q-pipe-guard.test.sh` exists on `origin/main`. Its header states the two sanctioned replacements (`grep -q PATTERN <<<"$var"` or `grep -c … || true` compared against 0). It does NOT scan `plugins/soleur/test/vendor-bundle-coverage.test.sh` (its pathspec is `.claude/hooks/*.sh`, `.claude/hooks/lib/*.sh`, `.openhands/hooks/*.sh`, plus two named `#7024` files).
- The four cited sites exist at the stated lines on this branch (91, 99, 73, 115-116). No stale premise.

### Root cause, measured (not assumed)

The brief's facts reproduce: `grep -E '^[[:space:]]+-[[:space:]]' lefthook.yml | wc -lc` → `93 4303`.
The race mechanism is more specific than "grep -q exits early", and it explains why the flake
is rare locally and still real:

1. **Upstream grep writes in 4096-byte chunks.** Pipe `st_blksize` is 4096. A reader that takes
   one `read()` sees exactly 4096 bytes: 20/20 runs of
   `grep … lefthook.yml | { dd bs=65536 count=1 | wc -c; …; }` printed `4096`. The 4303-byte
   output is therefore two writes: 4096 bytes, then 207 bytes.
2. **Every TS4 needle sits inside the first chunk.** Byte offsets of the first match in the
   producer output: gdpr-gate `references/` 3402, gdpr-gate `NOTICE` 3529, legal-generate
   `references/` 3580, legal-generate `NOTICE` 3643. All are below 4096.
3. So `grep -q` can match and exit after reading only the first chunk. If the scheduler lets that
   happen before upstream issues its second 207-byte `write()`, that write fails. On a fast local
   box the second write almost always lands first (the brief's 0/200). A loaded CI runner widens
   the window.
4. **CI exit code is 2, not 141.** The CI line `grep: write error: Broken pipe` means SIGPIPE was
   *ignored* in the runner's environment. grep then gets `EPIPE`, prints that message, and exits
   2. With default SIGPIPE disposition grep dies silently with 141. Measured locally:
   `(trap '' PIPE; grep … | grep -qF needle-bundle; echo "${PIPESTATUS[*]}")` →
   `grep: write error: Broken pipe` / `2 0`. **Consequence:** no assertion anywhere may pin `141`.
   Assert "non-zero" / "match found", never a specific signal code.

### Large-fixture reproduction (drives the regression design)

Fixture (every line indented 6 spaces, as in `lefthook.yml`): line 1 is the list item
`- "plugins/soleur/skills/needle-bundle/NOTICE"`, then 6000 list items
`- "plugins/soleur/skills/filler-NNNNN/references/**"` → **354,053 bytes**.

| Shape | False negatives |
|---|---|
| `grep -E … "$F" \| grep -qF "$needle"` (current) | **30/30** |
| `lines="$(grep -E … "$F" \|\| true)"; grep -qF "$needle" <<<"$lines"` (fix) | **0/30** |

The old shape fails **deterministically** at this size. Upstream can park at most 64 KiB in
the pipe, plus whatever the downstream read before it exited. At 354 KB it is guaranteed to
still hold unwritten output when downstream exits. A >256 KiB fixture therefore turns a flaky race
into a deterministic RED under the old shape, and the regression check cannot pass vacuously.

### Relevant files

- `plugins/soleur/test/vendor-bundle-coverage.test.sh`: the only file edited.
- `plugins/soleur/test/test-helpers.sh`: `assert_eq expected actual msg` (used by TS7). `print_results [floor]` is an anti-vacuity FLOOR (`ran < floor` → exit 1), currently called with `19`. The measured run count today is **21** (4 file-exists + TS2 1 + TS3 1 + TS4 2 bundles × 5 + TS5 4 + TS6 1). **It also installs an EXIT trap** (the incident-telemetry sandbox cleanup, composed with any prior trap). A `trap … EXIT` set AFTER sourcing it would REPLACE it and leak the sandbox, so the suite's owning trap goes BEFORE the source (amended at /work; see Implementation step 5).
- `.github/workflows/vendor-pin-verify.yml` `detect-changes` lists `plugins/soleur/test/vendor-bundle-coverage\.test\.sh$`, so this PR triggers the vendor-pin-verify job. That is expected, and it also exercises the fixed suite in CI.
- `scripts/test-all.sh` collects `plugins/soleur/test/*.test.sh`, so no runner wiring changes.

### Institutional learnings / conventions applied

- `.claude/hooks/grep-q-pipe-guard.test.sh` header (#6992): the herestring replacement and the
  "fail-open under pipefail" framing. Here the failure direction is a *false FAIL*, not a
  fail-open, because the predicate sits in `if <match>; then PASS`.
- `cq-test-fixtures-synthesized-only`: the fixture is generated by `awk` at test time, not copied
  from `lefthook.yml`.
- Portability (plan-sharp-edges, #8231): the fixture size check uses `wc -c < file` (not
  `stat -c`), and fixture generation uses `awk 'BEGIN{…}'`. **Not** `yes | head -n N`. That
  pipeline itself dies with SIGPIPE under `pipefail` and would abort the suite under `set -e`.

### Property List (Phase 0.6b)

- **P1**: A TS4 lefthook-glob predicate returns the true answer regardless of producer size or scheduler timing. It never reports "not covered" for a covered bundle.
- **P2**: The TS4 scoping is preserved. A needle that appears only on a `run:` line does NOT count as glob coverage (the existing comment at the TS4 predicate states this contract).
- **P3**: TS3 and the TS4 `run:`-line predicate are equally immune. No `… | grep -q` remains in executable lines of this file.
- **P4**: A regression check exercises the SAME predicate code the TS4 loop uses against a producer well above 64 KiB with the needle on line 1. That check would go RED if the pipe shape came back into the helper.

### Cut List (Phase 0.6b)

- Repo-wide sweep of sibling `| grep -q` sites → P1–P4 are file-scoped → already tracked by #7005 (sweep), #6601 (design call), #7432 (linter). Not done here, and no new issue is filed (operator scope decision).
- Enrolling this file in `.claude/hooks/grep-q-pipe-guard.test.sh`'s named-file list. That goes against the guard's own "growth happens by adding a named file" rule, so the reason is recorded here: **enrollment is not a one-line change.** The guard's `PATTERN` (`\|[[:space:]]*grep[[:space:]]+-[A-Za-z]*q`) also matches the `| grep` inside a logical `||`. It would false-flag TS6's `grep -qF … || grep -qF …` (line ~164, reads files, no pipe) and the converted TS4 `run:` predicate, so the file would fail on day one. Making it pass needs one of three edits, and each touches a second file or misuses the marker: narrow the shared pattern for every enrolled file, apply the `sigpipe-demo: intentional` marker to non-demo lines, or rewrite TS6. The operator's "this file only" scope rules out all three. The narrowed pattern this plan uses for AC2, `(^|[^|])\|[[:space:]]*grep[[:space:]]+-[A-Za-z]*q`, is the input #7432 (the grep -q linter) needs before any `.test.sh` with `||` chains can be enrolled. The residual is Guard Contract row M5.
- `grep -c … || true` + `-gt 0` alternative form → buys nothing over the herestring for P1. The herestring is the repo convention the brief names (#7240).
- A shipped "old shape fails on this fixture" positive control → it would put the forbidden shape into the file. The size floor plus the work-time mutation run (M1) establish non-vacuity without shipping it.

### Value-proposition / external research

Not a cost/perf claim (0.6c skip). No external research: strong local precedent (#6992 guard,
#7240 herestring convention) and a measured reproduction.

## Files to Edit

- `plugins/soleur/test/vendor-bundle-coverage.test.sh`: the only file.

## Files to Create

None. The regression fixture is synthesized into a `mktemp -d` directory at test time and removed
in the same block.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` (75 issues) searched for
`vendor-bundle-coverage`: 0 matches.

## Implementation

Test-only, single file. The changes, in file order:

1. **Add the helper** after the four `assert_file_exists` lines, before TS1:

   ```bash
   # Capture + herestring, not a pipe into grep -q: under pipefail the early exit can fail
   # the producer (EPIPE rc 2 on CI) -> false "not covered". Ref #7005.
   glob_item_contains() {
     local items
     items="$(grep -E '^[[:space:]]+-[[:space:]]' "$1" || true)"
     grep -qF -- "$2" <<<"$items"
   }
   ```

   `|| true` is required because, under `set -e`, a no-match (rc 1) inside the command
   substitution would abort the suite. It also swallows rc 2 (unreadable file), which is
   fail-closed: empty items, predicate false, FAIL line. The `run:`-line scoping contract (P2)
   stays documented in the existing TS4 comment block, which is not duplicated here.

2. **TS3 (line ~73), consistency conversion:**
   `if grep -qx "incident" <<<"$(printf '%s\n' "${NONCONFORMING[@]:-}")"; then`

3. **TS4 lefthook predicates (lines ~91, ~99):**
   `if glob_item_contains "$LEFTHOOK" "$prefix/NOTICE"; then` and
   `if glob_item_contains "$LEFTHOOK" "$prefix/references/"; then`. Keep the existing comment
   block above them.

4. **TS4 `run:` predicate (lines ~115-116), consistency conversion:**

   ```bash
   if grep -qF "NOTICE_FILE=\"$prefix/NOTICE\"" <<<"$run_lines" \
      || grep -qF "skills/$slug/scripts/vendor-pin-integrity.sh" <<<"$run_lines"; then
   ```

5. **Add TS7** after TS6, before `print_results`. It uses `assert_eq` from test-helpers.sh (the
   `assert_*` style TS5 already uses):

   ```bash
   echo "TS7: glob_item_contains is size/timing-immune and item-scoped (#7005)"
   fixture_dir="$(mktemp -d)"
   big="$fixture_dir/big.yml"
   decoy="$fixture_dir/decoy.yml"
   needle="plugins/soleur/skills/needle-bundle/NOTICE"
   awk -v n="$needle" 'BEGIN { printf "      - \"%s\"\n", n; for (i = 0; i < 6000; i++) printf "      - \"plugins/soleur/skills/filler-%05d/references/**\"\n", i }' > "$big"
   printf '      run: NOTICE_FILE="%s" bash x.sh\n' "$needle" > "$decoy"
   big_bytes=$(( $(wc -c < "$big") ))
   # 262144 = 4x the 64 KiB pipe capacity: the old pipe shape is deterministically RED here
   # (measured 30/30 false negatives at 354 KB). The floor keeps this row non-vacuous.
   rc=0; { (( big_bytes >= 262144 )) && glob_item_contains "$big" "$needle"; } || rc=$?
   assert_eq 0 "$rc" "needle on line 1 of a ${big_bytes}-byte (>= 262144) producer is found"
   rc=0; glob_item_contains "$decoy" "$needle" || rc=$?
   assert_eq 1 "$rc" "needle only on a run: line is not glob coverage"
   rm -rf "$fixture_dir"
   echo ""
   ```

   - `big_bytes=$(( … ))` strips BSD `wc -c`'s leading padding and runs `wc` once.
   - `rc=0; … || rc=$?` is safe under `set -e`, because a failure on the left of `||` does not
     abort. The `{ …; }` groups the size floor with the lookup, so a shrunk fixture FAILs this
     row (the byte count in the message says why).
   - **Trap placement (amended at /work):** `lint-trap-tempfile-ownership` rule (c) requires an
     owning `trap … EXIT` in any file that calls `mktemp`, so the suite installs
     `trap 'rm -rf "${fixture_dir:-}"' EXIT` **before** `source test-helpers.sh`, which composes a
     prior EXIT trap with its own sandbox cleanup. Never after the source. The explicit `rm -rf`
     at the end of TS7 stays.
   - The decoy row is a negative assertion, and it would pass on an empty or missing decoy. The
     `printf > "$decoy"` just above runs under `set -e`, and AC4's M2 run proves the row can go
     RED.

6. **Bump the floor:** `print_results 19` → `print_results 23`. 21 checks run today and TS7 adds
   2, so the suite runs 23. A floor of 23 trips if **either** TS7 row, or the whole block, is
   deleted.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing at runtime. This is a CI test file. The worst case is a still-flaky or falsely-green Guard 2 suite. A false GREEN would let a vendored bundle ship un-enrolled in lefthook pin-integrity, which weakens the vendor-drift tripwire for Soleur's own CC0/legal template bundles.
- **If this leaks, the user's data / workflow / money is exposed via:** no exposure vector. No secrets, no user data, no network. The fixture is synthesized, local, and deleted.
- **Brand-survival threshold:** `none`

## Acceptance Criteria

- [x] **AC1**: `bash plugins/soleur/test/vendor-bundle-coverage.test.sh` exits 0 and prints `Passed: 23` / `Failed: 0`. The file's last line (`tail -n 1`) is `print_results 23`.
- [x] **AC2**: No executable line of the file pipes into `grep -q…`. The check is `[ -z "$(grep -nE '(^|[^|])\|[[:space:]]*grep[[:space:]]+-[A-Za-z]*q' plugins/soleur/test/vendor-bundle-coverage.test.sh | grep -vE '^[0-9]+:[[:space:]]*#')" ]`, which exits 0. Comment lines are excluded because the helper's comment names the forbidden shape. The `(^|[^|])` prefix is load-bearing: the drift guard's bare `PATTERN` also matches the `| grep` inside a logical `|| grep -qF`, which would false-flag TS6 (line ~164) and the converted `run:` predicate. Non-vacuity was measured on the pre-fix file: the check hits exactly lines 73, 91, 99, 115 and 116, and not 164.
- [x] **AC3**: Both TS4 lefthook predicates route through the helper (P4). `grep -cE '^[[:space:]]*if glob_item_contains "\$LEFTHOOK" "\$prefix/(NOTICE|references/)"; then$' plugins/soleur/test/vendor-bundle-coverage.test.sh` → `2`.
- [x] **AC4 (mutations, run once at /work, not shipped; results recorded in the PR body):** Apply each edit to the helper or suite, run the suite, confirm the stated outcome, then restore.
  - **M1**: helper body becomes `grep -E '^[[:space:]]+-[[:space:]]' "$1" | grep -qF -- "$2"`. Expect exit 1 with the TS7 "needle on line 1" row FAILing.
  - **M2**: helper body becomes `grep -qF -- "$2" "$1"` (item scoping dropped). Expect the TS7 decoy row to FAIL.
  - **H1**: the `awk` line-1 needle becomes a filler path. Expect the "needle on line 1" row to FAIL.
  - **H2**: the needle moves to the last line of `big` instead of line 1. Expect the row to stay PASS.
  - **Measured at /work** (`env -i PATH=/usr/bin:/bin bash --noprofile --norc`, real grep): M1 RED 5/5 (`Passed: 22 / Failed: 1`, needle row); M2 decoy row RED; M3 needle row RED at 643 bytes; M4 (decoy row deleted) floor tripped at 22 < 23; H1 needle row RED; H2 GREEN 23/0; M5 (line ~99 re-inlined as a pipe) GREEN 23/0, the documented residual that AC2 catches. Fixed suite GREEN 10/10, 5 of them with SIGPIPE ignored as on CI.
- [ ] **AC5**: The PR body contains `Ref #7005` and neither `Closes #7005` nor `Fixes #7005`.
- [ ] **AC6**: The diff touches only `plugins/soleur/test/vendor-bundle-coverage.test.sh`, plus the pipeline's own artifacts: `knowledge-base/project/plans/2026-09-23-fix-vendor-bundle-coverage-sigpipe-race-plan.md`, `knowledge-base/project/specs/feat-one-shot-vendor-bundle-coverage-sigpipe/**`, and any generated `knowledge-base/INDEX.md`.

## Guard Contract

### Guard 1 — TS7 large-producer regression for glob_item_contains

**Property.** `glob_item_contains FILE NEEDLE` returns 0 iff NEEDLE occurs on a `^[[:space:]]+-[[:space:]]` list-item line, for every lefthook-shaped input, whatever the producer size or scheduling. In particular, a needle on line 1 of an input far larger than the pipe buffer is found, and a needle present only on a `run:` line is not.

**Assembly.** One chokepoint: the `glob_item_contains` function body. Both TS4 lefthook call sites and both TS7 rows go through it. Residual assembly outside the chokepoint: the TS3 and TS4 `run:`-line herestrings. They are converted inline and checked by AC2 at /work and review time, not by TS7.

**Mutation matrix.**

| # | Edit (guarded code or its dispatch) | Expected |
|---|---|---|
| M1 | Helper body reverted to `grep -E … "$1" \| grep -qF -- "$2"` | TS7 "needle on line 1" row RED. Measured 30/30 (plan) and 20/20 (plan-review, incl. SIGPIPE ignored), and deterministic because output exceeds pipe capacity plus one read |
| M2 | Item scoping dropped (`grep -qF -- "$2" "$1"`) | TS7 decoy row RED |
| M3 | Fixture filler loop shrunk (6000 → 10 lines) | TS7 "needle on line 1" row RED via the folded size floor (measured 643 bytes) |
| M4 | Either TS7 row, or the whole block, deleted (guard's own dispatch) | `print_results 23` floor trips (22 or 21 ran < 23), exit 1 |
| M5 | A TS4 call site re-inlines the pipe while the first stays compliant (e.g. line ~99 reverted, helper intact) | **Not reddened by TS7**, which tests the helper, not call sites. Caught only by AC2/AC3 at /work and review. AC2 also misses `grep --quiet`, `grep PATTERN -q` and a trailing-`\|` line continuation. Known residual: the class-wide lock is #7432 (linter) / #7005 (sweep), and enrollment is blocked by the guard's `\|\|` false positive (see Cut List) |

**Harness rows.**

| # | Edit to the SUITE or its input | Expected |
|---|---|---|
| H1 | `big` built without the needle (must-FAIL input) | "needle on line 1" row RED, which proves it is not constant-true. Executed at /work (AC4) |
| H2 | Must-PASS non-canonical input: needle on the LAST line of `big` | Row stays GREEN. The contract permits any position. Executed at /work (AC4) |

**Anchor.** Not applicable. The guard compares no stored value, hash or count against the thing it protects. The `print_results` floor is a developer-incremented anti-vacuity count, and M4 exercises it.

## Test Scenarios

- Suite green on the real `lefthook.yml` (AC1). TS4 still PASSes for gdpr-gate and legal-generate on both the NOTICE and `references/` rows.
- TS7 rows as in the Guard Contract. M1, M2, H1 and H2 run once at /work (AC4) and are not shipped as code.
- Negative sanity, unchanged behaviour: TS6 still reports `incident` as correctly unenrolled.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected. This is a test-only change to one bash suite, with no user-facing, legal, marketing, product, or infrastructure surface.

## Observability

Skipped per Phase 2.9: `## Files to Edit` contains only `plugins/soleur/test/*.test.sh`, which
falls outside the code/infra trigger paths (`apps/*/server|src|infra`, `plugins/*/scripts/`).
There is no new runtime surface. The suite's own PASS/FAIL lines in CI are the signal.

## Sharp Edges

- test-helpers.sh installs an EXIT trap (incident sandbox cleanup) and composes it with any EXIT trap already set. A `trap … EXIT` added AFTER sourcing it silently replaces that cleanup, so the suite's own owning trap is installed BEFORE the source (Implementation step 5).
- Never assert exit `141`. CI ignores SIGPIPE, so the producer exits `2` with `write error: Broken pipe`.
- Do not generate the fixture with `yes … | head`. That pipeline itself takes SIGPIPE under `pipefail` and aborts the suite under `set -e`.
- `local items` and the assignment are on separate lines, so `local` cannot mask a substitution's rc. The `|| true` is still what keeps a no-match from tripping `set -e`.
- If `awk` or `wc` aborts the suite under `set -e`, the pre-source owning trap removes the `mktemp -d` directory. Measured at /work: an `exit 7` injected after the `awk` line leaves 0 entries in `$TMPDIR` with the trap and 1 without it.
- The helper matches everything on an empty needle. That cannot happen here, because `prefix` is always `plugins/soleur/skills/<slug>` and the TS7 needle is a literal.
- Plan-review dispositions: DHH's "drop helper + TS7" and "native TS3 membership test" are recorded in `knowledge-base/project/specs/feat-one-shot-vendor-bundle-coverage-sigpipe/decision-challenges.md`. The operator's direction is kept.
