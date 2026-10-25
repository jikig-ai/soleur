---
title: "test: missing-tool SKIP counts as a pass outside .claude/hooks/ — convert to UNRESOLVED (exit 3) and widen the #8616 regression suite"
type: fix
date: 2026-10-24
slug: fix-8773-skip-unresolved
branch: feat-one-shot-8773-skip-unresolved
issue: 8773
closes: 8773
lane: procedural
brand_survival_threshold: none
---

# test: missing-tool SKIP counts as a pass outside .claude/hooks/

## Enhancement Summary

#8616 converted every `.claude/hooks/*.test.sh` dependency guard from `echo "SKIP: <tool>
missing"; exit 0` (which the runner counts as a pass) to `UNRESOLVED: <tool> missing … ; exit 3`,
and added `.claude/hooks/hook-suite-dep-unresolved.test.sh` to keep them that way. Its scope was
deliberately deferred at the `.claude/hooks/` boundary, and #8773 carries the rest of the repo.

This plan does three things:

1. Converts every remaining `SKIP … exit 0` dependency guard outside `.claude/hooks/` to the same
   taxonomy — a missing **tool** exits **3 (UNRESOLVED)**; a missing **file under test** exits
   **1 (FAIL)** — including the multi-line and probe shapes the issue's one-line grep missed.
2. Converts the unconditional skips under `apps/web-platform/infra/` to the ADR-188 `_skip()`
   contract: a local exit-0 skip stays (dev hosts are not contracted to have docker/terraform),
   but under `CI`/`GITHUB_ACTIONS` the same absence fails closed.
3. Widens `hook-suite-dep-unresolved.test.sh`: an explicit `EXTRA_PAIRED_SUITES` list holds the
   converted files' `command -v` guards to the same rc==3 + `UNRESOLVED:` contract, and the static
   `SKIP`+`exit 0` sweep is extended to every converted directory.

## Research Reconciliation — Issue vs. Codebase

The issue body listed ~13 files from a one-line grep; its own comment added the multi-line forms.
Re-running the census with the checker's own `scan_skip_exit0` awk plus a `command -v`/`which`
guard-derivation pass over every tracked `*.sh` found the issue's set was **incomplete**:

| Issue claim | Reality (measured 2026-10-24) | Plan response |
|---|---|---|
| `scripts/*.test.sh` (5): expenses-verify-by-check, sweep-followthroughs, review-reminder-liveness, lint-workflow-issue-write-scope, lint-workflow-local-action-checkout | All five confirmed, **plus `scripts/check-backstop-revision.test.sh`** (`command -v git || { SKIP; exit 0 }`, line 25), **plus `scripts/lint-agents-rule-budget.test.sh`** (SUT-missing `SKIP; exit 0` — dead code now that `lint-agents-rule-budget.py` exists), **plus `scripts/audit-suite-reads.test.sh`** (a *fixture* line `echo "SKIP: npx not on PATH"' 'exit 0'` that the widened sweep would flag), **plus `scripts/rule-metrics-aggregate.test.sh`** (three `"cannot SKIP"` prose literals inside FAIL messages followed by bare `return`), **plus `scripts/sweep-followthroughs.test.sh`'s S2D-5 arm** (`SKIP: … needs /proc/self/status; return 0`). | Convert all of them; the fixture/prose sites get literal-hygiene edits that keep runtime behavior identical. |
| `plugins/soleur/test/` (2): fixture-relative-assert, hook-input-classification-mutation | Confirmed both, **plus `ralph-loop.test.sh`** (jq, multi-line), **`render-c4-model.test.sh`** (npx, multi-line — an *arm* guard: earlier rows run first), **`codeql-main-alert-gate-workflow-wiring.test.sh`** (jq at exit 2 — honest but non-canonical — plus python3 and PyYAML skips), **`pencil-adapter-auth-hard-fail.test.sh`** (Node ≥ 22.9 probe, multi-line), **`community-argv.test.sh`** (jq/openssl/python3 loop with a CI-branch skip), and **`plugins/soleur/scripts/scan-ancestor-signal-helpers.test.sh`** (python3, multi-line). | Convert all of them. |
| `plugins/soleur/skills/*/test/` (2): the two argv-ceiling suites | Confirmed both (jq), **plus `git-worktree/test/stale-lock-sweep.test.sh`** (functional GNU-coreutils probe → skip + exit 0). | Convert all three. |
| `apps/web-platform/infra/` (2): `workspaces-luks-*`, ADR-188 `_skip()` rules | The two `skip() { …; exit 0; }` definitions are in `workspaces-luks-g4-mutation.test.sh` and `workspaces-luks-verify-root-mtime.test.sh`, **plus `cloud-init-plugin-seed.test.sh`** (two unconditional docker skips) and **`git-data-userdata-budget.sh`** (terraform skip *lacks* the CI branch its two sibling budget scripts carry). `workspaces-luks-t2-rehearsal` (`tool_missing`), `workspaces-luks-loopback` (`unavailable`, fail-closed), `git-data-emit`, `canary-bundle-claim-check`, `registry-render-delta`, `registry-userdata-budget`, `web-ghcr-deny`, `inngest-userdata-budget` are **already ADR-188-shaped** (local skip, CI fail). | Add the CI/GITHUB_ACTIONS fail branch to the four non-compliant sites; keep the local exit-0 skip — that is the ADR-188 contract, not the defect. |
| probes "not *.test.sh": hook-input-fault-discoverability-probe.sh, context-reviewed-gate-discoverability.sh | Confirmed both, **plus `scripts/resend-alert-path-discoverability.sh`** (`dig` absent → `RESEND_ALERT_PATH_SKIP_NO_DIG … exit 0` after the static arms ran — the taxonomy's *arm* row). | Convert all three: tools → `UNRESOLVED … exit 3`; the missing hook file → `FAIL … exit 1`. |
| (not listed) `tests/scripts/` | `test-soleur-sandbox.sh` exits 0 locally on a missing non-tmpfs dir while *saying* "NOT a pass" (already fails in CI). | Local branch → `UNRESOLVED … exit 3`; CI branch unchanged. |
| (not listed) `apps/web-platform/scripts/lib/in-image-copy-src.test.sh` | `skip() { echo "  SKIP: $1"; SKIP+=1; return 0; }` — a **counted, floored, per-case** decline (three call sites: two cascade-skips after an already-counted FAIL, one running-as-root). Not the whole-suite defect, but its literal trips the widened sweep. | Rename the emitted label to lowercase `skip:` (the counted decline mechanism is honest and stays); document that the `SKIP` token is reserved for the dependency-guard shape. |

Verified clean: `.claude/hooks/*.test.sh` are all converted (the `SKIPPED`+`exit 0` hits there are in
`.sh` *hooks*, where exit 0 means "allow the tool call" — correct hook semantics, not a suite).
`apps/cla-evidence/scripts/*.test.sh`, `apps/web-platform/scripts/*.test.sh`, `scripts/lib/*.test.sh`
(other than frontmatter-strip), `apps/web-platform/test/`, `tests/scripts/` (other than
test-soleur-sandbox), `scripts/followthroughs/` carry no `SKIP`-literal-plus-`exit 0` site.

## Problem Statement

Identical to #8616, one directory level up: `exit 0` is the runner's pass code, so a suite whose
dependency guard prints `SKIP: <tool> missing; exit 0` is recorded as **passing while asserting
nothing** on any host that lacks the tool. The remaining sites also include two shapes the hook
sweep never had: a *file-under-test* skip (`frontmatter-strip`, `lint-agents-rule-budget`), and
unconditional skips in ADR-188 territory (`apps/web-platform/infra/`), where the contract is
"skip locally, **fail in CI**" — and three sites don't even do the CI half.

## Proposed Solution

### The taxonomy (unchanged from #8616; the checker header is its single home)

| Condition | Exit | Canonical line |
|---|---|---|
| A tool the whole suite needs is off PATH | 3 | `UNRESOLVED: <tool> missing — this suite asserted nothing; install <tool>` |
| The file under test is missing (repo-owned) | 1 | `FAIL: <path> not found — …` |
| One arm hit a missing tool, other arms ran | non-zero | `UNRESOLVED: <tool> missing — <arm> not run` (+ a counted `bad`/`fail` where the suite's accounting needs it) |
| ADR-188 domain (`apps/web-platform/infra/`): tool absent **locally** | 0 | `_skip`/`skip()` unchanged — the printed `SKIP:` line stays |
| ADR-188 domain: tool absent **under CI** | non-zero | `FAIL … the runner must provide this dependency` |

### Conversions (all use the canonical one-liner where the guard is a whole-suite `command -v`)

**`scripts/*.test.sh` (6):**
- `expenses-verify-by-check.test.sh` (date), `review-reminder-liveness.test.sh` (python3),
  `lint-workflow-issue-write-scope.test.sh` (python3 — drops the fake `0/0 passed` results line),
  `lint-workflow-local-action-checkout.test.sh` (python3 — same), `check-backstop-revision.test.sh`
  (git; its `$SUT`-missing `FATAL exit 2` → `FAIL … exit 1` per the file-under-test row).
- `sweep-followthroughs.test.sh` (realpath → canonical; the **S2D-5 arm** `SKIP: … /proc/self/status;
  return 0` → print `UNRESOLVED: /proc/self/status missing — S2D-5 arm not run` and count it via
  `TOTAL+=1; fail "…"` — the arm-row shape `bare-head-self-heal.test.sh` already uses. The deliberate
  `command -v mawk → awk --traditional` **fallback stays**: that arm is measured either way, which is
  also why this file is *not* in `EXTRA_PAIRED_SUITES` — toggling mawk legitimately exits 0.)

**`scripts/lib/` (1):** `frontmatter-strip.test.sh` — perl + python3 → canonical; the
`[[ -f $SH && -f $PY ]] || { SKIP (RED); exit 0; }` file-under-test guard → `FAIL … exit 1`. The
`command -v bun … && HAS_BUN=1` optional-TS-arm stays (positive `&&` form, no pair derived, no SKIP
literal).

**`scripts/` top-level, non-suite edits (sweep hygiene):**
- `lint-agents-rule-budget.test.sh`: `SKIP: $SUT not yet present (Phase 1 RED)` → `FAIL … exit 1`
  (the `.py` exists now; the deferral is dead code — a missing SUT can never fire it again).
- `rule-metrics-aggregate.test.sh`: three `"… cannot SKIP (a skipped pin …)"` FAIL messages →
  `cannot be skipped` — the message's own point is that a skip would be wrong; the literal trips
  the sweep on a technicality.
- `audit-suite-reads.test.sh`: the `fx_suite skipper` fixture keeps printing `SKIP: npx not on PATH`
  at runtime, spelled `'echo "SK""IP: npx not on PATH"'` in the source so the sweep's literal check
  does not see the token it is *measuring* the fixture for.

**`plugins/soleur/test/` (5) + `plugins/soleur/scripts/` (1) + `plugins/soleur/skills/*/test/` (4):**
- `fixture-relative-assert.test.sh` (python3; `$SCANNER`-missing `FATAL exit 2` → `FAIL … exit 1`),
- `hook-input-classification-mutation.test.sh` (jq, python3, git — three canonical lines),
- `codeql-main-alert-gate-workflow-wiring.test.sh` (jq `FATAL exit 2` → canonical `UNRESOLVED exit 3`;
  python3 skip → canonical; the `python3 -c 'import yaml'` probe → `UNRESOLVED: PyYAML missing … exit 3`;
  the SUT-files check `FATAL exit 2` → `FAIL exit 1`),
- `ralph-loop.test.sh` (jq multi-line `if !` → canonical one-liner),
- `render-c4-model.test.sh` (npx `if !` block → `UNRESOLVED: npx missing — the likec4 arm did not run
  …; install npx` + `exit 3` — derived `whole` class since the block exits, so rc==3 is required),
- `scan-ancestor-signal-helpers.test.sh` (python3 `if !` → canonical),
- `skills/drain-prs/test/argv-ceiling.test.sh` + `skills/skill-security-scan/test/argv-ceiling.test.sh`
  (jq → canonical),
- `skills/community/test/community-argv.test.sh` (the `for dep in jq openssl python3` loop keeps its
  loop shape but collapses to `UNRESOLVED: $dep missing — this suite asserted nothing; install $dep;
  exit 3` — exit 3 is honest under CI too, so the separate `CI → exit 1` branch is no longer needed),
- `skills/git-worktree/test/stale-lock-sweep.test.sh` (functional GNU probe → `UNRESOLVED: GNU
  coreutils missing … exit 3`).

**`tests/scripts/` (1):** `test-soleur-sandbox.sh` — keep the `CI → FAIL exit 1` branch; the local
`SKIPPED … exit 0` → `UNRESOLVED: no non-tmpfs writable dir — 0 sandbox allocator cases ran … ; exit 3`.

**Discoverability probes (3):**
- `hook-input-fault-discoverability-probe.sh` (jq → canonical, "this probe asserted nothing"),
- `context-reviewed-gate-discoverability.sh` (the combined `if !` is split into three canonical
  lines — jq, git, perl — placed *before* `git rev-parse`, and `[[ ! -x $HOOK ]]` → `FAIL … exit 1`),
- `resend-alert-path-discoverability.sh` (`dig` absent after the static arms → `UNRESOLVED: dig
  missing — the sender-domain arms did not run` + `exit 3`. **Sweep-covered but not pair-listed**:
  `dig` is absent on some dev hosts (this one included), and the checker's own self-taxonomy exits 3
  when a derived tool is missing — listing it would make the whole checker UNRESOLVED there.)

**`apps/web-platform/scripts/lib/` (1, hygiene):** `in-image-copy-src.test.sh` `skip()` emits
lowercase `  skip:` — the counted/floored per-case decline mechanism is unchanged.

### ADR-188 conversions (`apps/web-platform/infra/`)

Local exit-0 skip stays; the `CI`/`GITHUB_ACTIONS` branch is what gets added:

- `workspaces-luks-g4-mutation.test.sh` + `workspaces-luks-verify-root-mtime.test.sh`: `skip()`
  gains the `canary-bundle-claim-check.test.sh` predicate shape — `-n CI || -n GITHUB_ACTIONS` →
  `FAIL … the runner must provide this dependency; exit 1`, else `SKIP:` + `exit 0` as today.
- `cloud-init-plugin-seed.test.sh`: the two `if ! docker …` blocks route through a `_skip()` of the
  same shape (the file's header comment "Skip cleanly if Docker is unavailable" is amended to name
  the CI half).
- `git-data-userdata-budget.sh`: the terraform guard gains the exact sibling shape from
  `inngest-userdata-budget.sh`/`registry-userdata-budget.sh` (`terraform is REQUIRED in CI … exit 2`).

### The regression suite — widening `.claude/hooks/hook-suite-dep-unresolved.test.sh`

Option A from the issue (widen the population) — the checker gains two populations, neither of which
touches `test-all.sh`'s `SUITE_GLOBS`:

1. **`EXTRA_PAIRED_SUITES`** — an explicit per-file list (16 files, 22 derived pairs) appended to
   `SUITE_LIST` before `derive_pairs`. Per-file, not a directory glob: the siblings in those
   directories still carry `FAIL: <tool> missing; exit 1|2` guards — honest but not the canonical 3 —
   and a directory glob would hold ~30 unconverted files to a contract nobody converted them to.
   Every listed file must exist (a deleted file silently un-covers its guards → `FATAL`) **and**
   must derive ≥1 pair (a listed file with no guard-shaped line is dead coverage → `FATAL`).
   - `scripts/check-backstop-revision.test.sh` (git), `scripts/expenses-verify-by-check.test.sh`
     (date), `scripts/lint-workflow-issue-write-scope.test.sh` (python3),
     `scripts/lint-workflow-local-action-checkout.test.sh` (python3),
     `scripts/review-reminder-liveness.test.sh` (python3),
     `scripts/lib/frontmatter-strip.test.sh` (perl, python3),
     `plugins/soleur/test/fixture-relative-assert.test.sh` (python3),
     `plugins/soleur/test/hook-input-classification-mutation.test.sh` (jq, python3, git),
     `plugins/soleur/test/codeql-main-alert-gate-workflow-wiring.test.sh` (jq, python3),
     `plugins/soleur/test/ralph-loop.test.sh` (jq),
     `plugins/soleur/test/render-c4-model.test.sh` (npx),
     `plugins/soleur/scripts/scan-ancestor-signal-helpers.test.sh` (python3),
     `plugins/soleur/skills/drain-prs/test/argv-ceiling.test.sh` (jq),
     `plugins/soleur/skills/skill-security-scan/test/argv-ceiling.test.sh` (jq),
     `scripts/hook-input-fault-discoverability-probe.sh` (jq),
     `scripts/context-reviewed-gate-discoverability.sh` (jq, git, perl).
2. **Sweep-only roots** — `scan_skip_exit0` extends to: every non-`.claude/hooks/` runner glob
   (automatic once the loop collects them), plus checker-declared globs `scripts/*.test.sh`,
   `scripts/followthroughs/*.test.sh`, `tests/scripts/*.sh`, plus the three probe files. Each
   declared root gets the same `FATAL`-when-empty discipline the runner roots already have.
   `MIN_PAIRS` moves 54 → **76** (54 hook pairs + 22 new pairs, the measured values).

**Named exclusions (documented in the checker header):**
- `apps/web-platform/infra/` — ADR-188 domain: a *local* exit-0 `SKIP:` is the contract there, so the
  sweep cannot read it. The CI half is what this plan converts, and `scheduled-rehearsal-skip-monitor`
  plus infra-validation's own gates carry the CI-side honesty.
- `apps/web-platform/test/` and `apps/cla-evidence/test/` — not runner globs, no current hits.
- `plugins/soleur/test/lib/*.sh` — sourced libraries, already named "not covered" by the checker
  (the gitleaks probe is an ADR-188 local skip).
- `.claude/hooks/*.sh` — the hooks themselves: `SKIPPED` + `exit 0` is allow-the-tool-call semantics.

**Residual, named:** ~30 suites under the sweep-covered roots keep `FAIL: <tool> missing; exit 1|2`
guards. They never green-washed (the defect class this issue closes), but they are not the canonical
`UNRESOLVED … 3`. Promoting them — and thereby promoting whole directories into the paired
population — is follow-on work, one directory at a time, exactly as the issue's "different owners and
CI shards" deferral intends.

## Files to Edit

- `.claude/hooks/hook-suite-dep-unresolved.test.sh` — `EXTRA_PAIRED_SUITES` + sweep-only roots +
  `MIN_PAIRS` 54→76 + header taxonomy/coverage notes.
- `scripts/`: `check-backstop-revision.test.sh`, `expenses-verify-by-check.test.sh`,
  `review-reminder-liveness.test.sh`, `lint-workflow-issue-write-scope.test.sh`,
  `lint-workflow-local-action-checkout.test.sh`, `sweep-followthroughs.test.sh`,
  `lint-agents-rule-budget.test.sh`, `rule-metrics-aggregate.test.sh` (reword only),
  `audit-suite-reads.test.sh` (fixture literal split only),
  `lib/frontmatter-strip.test.sh`, `hook-input-fault-discoverability-probe.sh`,
  `context-reviewed-gate-discoverability.sh`, `resend-alert-path-discoverability.sh`.
- `plugins/soleur/test/`: `fixture-relative-assert.test.sh`,
  `hook-input-classification-mutation.test.sh`, `codeql-main-alert-gate-workflow-wiring.test.sh`,
  `ralph-loop.test.sh`, `render-c4-model.test.sh`, `pencil-adapter-auth-hard-fail.test.sh`.
- `plugins/soleur/scripts/scan-ancestor-signal-helpers.test.sh`.
- `plugins/soleur/skills/drain-prs/test/argv-ceiling.test.sh`,
  `plugins/soleur/skills/skill-security-scan/test/argv-ceiling.test.sh`,
  `plugins/soleur/skills/community/test/community-argv.test.sh`,
  `plugins/soleur/skills/git-worktree/test/stale-lock-sweep.test.sh`.
- `tests/scripts/test-soleur-sandbox.sh`.
- `apps/web-platform/scripts/lib/in-image-copy-src.test.sh` (label only).
- `apps/web-platform/infra/`: `workspaces-luks-g4-mutation.test.sh`,
  `workspaces-luks-verify-root-mtime.test.sh`, `cloud-init-plugin-seed.test.sh`,
  `git-data-userdata-budget.sh`.

## Non-Goals / Scope Boundary

- Normalizing the ~30 honest `FAIL … exit 1|2` whole-suite guards to canonical `UNRESOLVED … 3`
  (named residual above).
- `.claude/hooks/*.sh` *hook* scripts' `SKIPPED + exit 0` — allow-the-tool-call semantics.
- `apps/web-platform/infra/` local exits — ADR-188 keeps them at 0 by contract.
- `sentry-adoption-plan-assert.sh`'s "not an adoption plan" SKIP verdict — a domain verdict, not a
  dependency guard.
- `apps/web-platform/scripts/bwrap-userns-seccomp-probe.sh`'s `USNS_SECCOMP_SKIP_NO_BWRAP` and
  `sandbox-canary-regression.test.sh`'s per-case `skip()` — measured tokens / counted declines.

## Risks

- **A covered pair can't fire on a tool the host lacks.** The checker's pre-flight already handles
  this: a derived tool absent from the PATH farm makes the *checker* exit 3 (UNRESOLVED), never RED.
  `dig`/`mawk` are missing on this host; neither is pair-listed (resend and sweep-followthroughs are
  the exclusions).
- **Sweep false-positives on prose.** `rule-metrics-aggregate`'s "cannot SKIP" and the
  `audit-suite-reads` fixture are the two found; both are fixed by literal hygiene, not exclusions.
- **`EXTRA_PAIRED_SUITES` rots.** Countered by the two FATALs: file must exist, and must derive ≥1
  pair. A suite whose guard is deliberately removed fails the second check loudly.
- **`env -i` pair runs.** Same discipline as .claude/hooks pairs — every converted guard is placed at
  or before its tool's first use, so a toggled-off suite exits inside its guard block (verified per
  file during implementation).

## Guard Contract

### Guard 1 — no `SKIP` literal paired with `exit 0` survives in the covered population

**Property.** `scan_skip_exit0` over SUITE_LIST ∪ sweep-only roots yields zero hits.

**Assembly.** The sweep roots are the union of (a) every runner glob (which now collects non-hook
roots into `SWEEP_ONLY` instead of skipping them), (b) checker-declared globs `scripts/*.test.sh`,
`scripts/followthroughs/*.test.sh`, `tests/scripts/*.sh`, (c) the three probe paths. A root that
matches nothing is a `FATAL`, so an empty coverage list cannot read as green.

**Mutation matrix.**

| # | Edit | Expected RED |
|---|---|---|
| M1 | Revert any one converted guard to `echo "SKIP: <tool> missing"; exit 0` | static sweep names file:line |
| M2 | Revert the `audit-suite-reads` fixture split so the source literal reads `SKIP` again | static sweep names file:line |
| M3 | Revert `scripts/rule-metrics-aggregate.test.sh`'s `cannot be skipped` reword back to `cannot SKIP` | static sweep names file:line (the prose literal trips it) |

### Guard 2 — every converted `command -v` guard exits 3 with the `UNRESOLVED:` line

**Property.** All 22 derived pairs over `SUITE_LIST` (hook suites + `EXTRA_PAIRED_SUITES`) report
rc==3 (whole) / non-zero (arm) plus `UNRESOLVED: <tool> missing` under `env -i`.

**Assembly.** `EXTRA_PAIRED_SUITES` (16 files, listed in the checker) is appended to `SUITE_LIST`
before `derive_pairs`, so the same `check_pair` machinery that measures hook suites measures them.
Every listed file must exist and derive ≥1 pair, or the checker `FATAL`s.

**Mutation matrix.**

| # | Edit | Expected RED |
|---|---|---|
| M4 | `check-backstop-revision.test.sh`: `exit 3` → `exit 0` on the git guard | pair (check-backstop-revision, git): `rc=0` |
| M5 | `hook-input-classification-mutation.test.sh`: revert only the *third* guard (git) | pair (…, git) RED under the git toggle — the compliant jq/python3 guards don't mask it |
| M6 | `context-reviewed-gate-discoverability.sh`: re-merge the three canonical lines into the old combined `if !` with `exit 0` | pairs (jq, git, perl) RED under every toggle |
| M7 | A listed file's guard is deleted outright | `FATAL: <file> derived no (file, tool) pairs — its listing is dead` |
| M8 | `MIN_PAIRS` lowered while a conversion is reverted | floor holds — `found N pairs < MIN_PAIRS` only fires if the population itself shrinks, which a message reword does not cause |

**Anchor.** `EXTRA_PAIRED_SUITES` and the suites it names live in the same tree, so one diff can
delete a suite and its listing together. The listing itself is the registry a reviewer diffs; the
per-file `≥1 pair` FATAL is what keeps a listing honest after it lands. A removed sweep-only glob
(M3's sibling edit) leaves the *paired* files covered but silently un-sweeps their siblings — that
is why the root-empty FATALs exist.

## Test Scenarios

1. Every converted suite runs **green** on a host with all tools present (this host).
2. Per-pair simulation: PATH-strip `git`/`python3`/`jq`/`date`/`perl`/`npx` on the converted files —
   direct runs on ≥3 suites must print `UNRESOLVED: <tool> missing` and exit 3. The widened
   regression suite does this for all 22 pairs mechanically.
3. `scripts/resend-alert-path-discoverability.sh` on this host (`dig` absent) → exit 3 +
   `UNRESOLVED: dig missing` — a live arm-decline proof.
4. ADR-188 arms: `CI=1 bash apps/web-platform/infra/cloud-init-plugin-seed.test.sh` with docker
   shadowed → exit 1, not 0; local run without `CI` still skips 0 as before.
5. `bash .claude/hooks/hook-suite-dep-unresolved.test.sh` → green end-to-end, `N pairs` ≥ floor.
