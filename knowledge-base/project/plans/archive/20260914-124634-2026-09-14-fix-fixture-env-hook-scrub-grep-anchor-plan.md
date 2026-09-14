---
title: "fix: fixture-env suite hermetic under git hooks (prefix scrub) + anchor Guard-2 probe_schema grep"
date: 2026-09-14
slug: fix-fixture-env-hook-scrub-grep-anchor
branch: feat-one-shot-8051-8053-fixture-env-grep-anchor
issue: 8051
closes: 8051, 8053
type: bug
priority: p2
domain: engineering
brand_survival_threshold: none
lane: cross-domain
---

# fix: fixture-env suite hermetic under git hooks (prefix scrub) + anchor Guard-2 probe_schema grep

## Enhancement Summary

**Deepened on:** 2026-09-14 (same session as plan authoring; deepen-plan executed sequentially
in-process — no Task/subagent spawn available in this harness — with every mechanical gate run
for real)

**Sections enhanced:** Observability (field values inlined for preflight Check 10), Research
Insights (verification log below), Acceptance Criteria (AC5 rewritten to `grep -cF` fixed-string
form — the original `\\$` BRE escape was correct but fragile).

**Agents/skills applied (sequential, in-process):** repo-research-analyst, learnings-researcher,
functional-overlap check (zero overlap — repo-internal test/workflow hygiene), spec-flow lens
(recursion-flag survival, per-child env specs, ledger independence), plan-review eng panel
(DHH overengineering / Kieran correctness / code-simplicity per-mechanism vs the Property List),
cto/devex lens (named panel — only axis activated by the independent relevance read),
verify-the-negative pass, post-edit self-audit, lint-guard-contract.py.

### Key improvements

1. #8051's measured failure shape is **stale** (fixed by #7976, merged one day post-filing);
   the plan retargets the live failure — a full hook env fails **10** arms standalone, not 3 —
   while keeping the issue's letter (probe scrub) and title (suite inside a hook) in scope.
2. The #8053 message site was **mis-attributed** in the pipeline brief — it lives in
   `.github/workflows/apply-web-platform-infra.yml` ~line 2325, not
   `tests/scripts/lib/inngest-host-dark-gate.sh`. Verified by grep; `## Files to Edit` is correct.
3. Two independent scrub layers prescribed (suite-top ambient + probe-local), each pinned by a
   distinct mechanism (hook-env replay arm; `MIN_ASSERTIONS` floor) — the file's own
   defense-in-depth idiom.

### New considerations discovered

- A real `pre-commit` hook env was dumped this session (`GIT_AUTHOR_DATE/EMAIL/NAME`,
  `GIT_EDITOR`, `GIT_EXEC_PATH`, `GIT_INDEX_FILE`, `GIT_PREFIX`, `GIT_TERMINAL_PROMPT`) — and
  `GIT_TERMINAL_PROMPT` was *already set* in the planning session's own shell env, evidence that
  `GIT_*` leakage reaches suites from more than hooks; the ambient prefix scrub covers both.
- `${!GIT_@}` verified live under `set -u` (sweep executed, ambient var count >0, `unset`
  confirmed, no nounset trip).
- The workflow path matches the deepen-plan sensitive-path regex (`web-platform` substring) —
  the `threshold: none, reason:` scope-out bullet in `## User-Brand Impact` is load-bearing,
  not optional.
- `lint-guard-contract.py` — green (2 guard entries, ≥3 mutation rows each).
- Attributions probed on this branch: `e0f097fde` (#7976) added the `-u GIT_AUTHOR_NAME` line;
  `0d97ede5c` (#8019 batch) carries the unanchored grep; `vinngest-v1.1.35` resolves to
  `af700648f565c753f4742e62f52cdedcac3614fb` (`git rev-parse --verify`).

## Overview

Two p2 bugs from the same operator batch, both small and both verified against the live tree during
planning.

**#8051** — `plugins/soleur/test/git-fixture-env-shell.test.sh` is not hermetic when invoked inside
a git hook. Git exports `GIT_AUTHOR_NAME`, `GIT_AUTHOR_EMAIL`, `GIT_AUTHOR_DATE`, `GIT_EDITOR`,
`GIT_EXEC_PATH`, `GIT_INDEX_FILE`, `GIT_PREFIX` and `GIT_TERMINAL_PROMPT` into every commit-hook
process (measured from a real `pre-commit` hook this session). The suite's leak probe cannot
distinguish an inherited value from one the builder exported, and every `bash -c` child that
sources `plugins/soleur/test/lib/git-fixture-env.sh` trips the Guard-3 location tripwire on an
inherited `GIT_INDEX_FILE`/`GIT_DIR`. Measured on this worktree: a hook-shaped environment drives
the suite to **14 passed / 10 failed**. The remedy is a **prefix scrub** of ambient `GIT_*`
variables — the repo's own idiom (`${!GIT_@}` in `git-fixture-env.sh:171`, `!k.startsWith("GIT_")`
in `git-clean-env.ts`) — never a longer name list (the 2026-09-04 learning: a hand-listed six-name
`GIT_*` scrub is exactly how this class was re-derived wrongly once already).

**#8053** — the Guard-2 `stale_schema` recovery command printed by
`.github/workflows/apply-web-platform-infra.yml` (the `::error::inngest-volume-recut REFUSED`
message, one line, ~line 2325) counts comment lines because its `grep -c "probe_schema=\$EXPECTED"`
lacks a `^` anchor. Measured against the pinned bootstrap: unanchored = **5**, anchored = **1**;
the message documents only 0-or-1 branches. Fix is one character.

*Spec lacks valid `lane:` — defaulted to cross-domain (TR2 fail-closed). No
`knowledge-base/project/specs/feat-one-shot-8051-8053-fixture-env-grep-anchor/spec.md` exists
(one-shot pipeline entry).*

## Research Reconciliation — Spec vs. Codebase

| Claim in the issue/pipeline brief | Reality verified on this branch | Plan response |
|---|---|---|
| #8051: suite fails with exactly 3 `PARTIAL env leaked` arms when `GIT_AUTHOR_NAME` is inherited | **Stale.** #7976 (merged 2026-09-11, one day after the issue was filed) added `-u GIT_AUTHOR_NAME` to the probe's `env -u` list; `GIT_AUTHOR_NAME=x bash <suite>` is 24/0 green today. The LIVE failure is broader: a full hook env (incl. `GIT_INDEX_FILE`/`GIT_DIR`) fails **10** arms — every lib-sourcing child hits the tripwire — when the suite runs standalone. | Treat the issue's letter (probe scrub) and title (suite fails inside a hook) both as in-scope: suite-level ambient prefix scrub + probe-local prefix scrub + a hook-env replay regression arm. |
| #8053: "the recovery message text lives in `tests/scripts/lib/inngest-host-dark-gate.sh`" | **Wrong file.** The message lives in `.github/workflows/apply-web-platform-infra.yml` (~line 2325, the `::error::inngest-volume-recut REFUSED by Guard 2` echo). The lib only carries `_IHDG_EXPECTED_SCHEMA="8"` (line 201), which the message's `EXPECTED=` derivation reads. | `## Files to Edit` names the workflow file; the lib is context-only, not edited. |
| #8053 fix is `grep -c "^probe_schema=$EXPECTED"` | Correct; verified `5`→`1` against `apps/web-platform/infra/inngest-bootstrap.sh` on this branch. The anchor is also established precedent: `tests/scripts/test-inngest-host-dark-gate.sh:815` already greps `^probe_schema=[0-9]+`. | Apply as prescribed; add a workflow-text pin so a regression of the anchor reds a suite. |

## Research Insights

**Premise Validation (Phase 0.6).** Checked: `gh issue view` for both issues (both OPEN,
priority/p2-medium, domain/engineering); every cited file exists
(`plugins/soleur/test/git-fixture-env-shell.test.sh`, `plugins/soleur/test/lib/git-fixture-env.sh`,
`tests/scripts/lib/inngest-host-dark-gate.sh`, `apps/web-platform/infra/inngest-bootstrap.sh`, the
2026-09-04 learning). Reproduced both measurements (suite 24/0 clean, 14/10 under hook env; grep
5→1). Stale items recorded in the reconciliation table above. Related-issue check: #7822 (the
umbrella "shell suites spawn git with no scrub" census) is still OPEN — this fix is one instance of
that class; **acknowledged, not folded** (#7822's scope is a repo-wide census plus a lint, larger
than this PR). #8019 (the PR whose verification surfaced both issues) and #7976 (which already
landed the interim `-u GIT_AUTHOR_NAME` name-list fix) are both MERGED. ADR corpus grep
(`knowledge-base/engineering/architecture/decisions/`): no ADR decides env-scrub or grep-anchor
mechanics — neither proposed mechanism sits in a rejected-alternatives table. ADR-199 is the
gate's own decision record and is consistent with the anchor fix (the amendment history already
replaced a hardcoded count once, #8017).

**Property List (Phase 0.6b).**

- P1 — The leak probe measures "the builder exported nothing" hermetically: its child starts from
  a known-empty `GIT_*` state regardless of what any parent exported.
- P2 — The suite exits 0 when invoked from inside a git hook environment (the issue's title
  scenario), including standalone invocation — not only via `scripts/test-all.sh`'s entry-point
  scrub.
- P3 — The Guard-2 recovery count means what its prose documents: exactly 0 or 1, never a
  comment-line count.
- P4 — The fix's own regression is observable in CI (a scrub deletion or anchor loss reddens a
  suite), not only under a real hook or a live `stale_schema` verdict.

**Cut List (Phase 0.6b).** Nothing cut — both proposed mechanisms map 1:1 onto properties and no
existing mechanism covers them: `scripts/test-all.sh:332` and `lefthook.yml`'s
`plugin-component-test` unset only the nine `GIT_LOCATION_VARS` (location family — they can never
cover `GIT_AUTHOR_NAME`/`GIT_CONFIG_KEY_0`, and they don't reach a standalone suite invocation);
`git-clean-env.ts` is TypeScript-only; `git-fixture-env.sh` cannot be sourced by this suite for a
scrub (sourcing arms the tripwire — the suite's file header documents why it sources nothing).
No new shared helper is created: the suite is deliberately self-contained (it cannot source
`test-helpers.sh` or the lib), so the prefix loop is inlined at the two sites that need it.

**Relevant file paths.**

- `plugins/soleur/test/git-fixture-env-shell.test.sh` — the suite under repair. Probe at
  ~lines 184–201 (`env -u` 5-name chain at 192–194); `readonly MIN_ASSERTIONS=24` at line 25;
  verdict ledger + EXIT trap at 82–106.
- `plugins/soleur/test/lib/git-fixture-env.sh` — subject lib; `${!GIT_@}` prefix-sweep idiom at
  line 171 (mirror this); `GIT_LOCATION_VARS` at 44–54; tripwire at 75–95. **Not edited.**
- `plugins/soleur/test/lib/git-clean-env.ts` — the TS prefix helper; comment block documents the
  "EXCLUSION BY PREFIX, NEVER BY NAME LIST" contract this fix mirrors in bash.
- `.github/workflows/apply-web-platform-infra.yml` ~line 2325 — the `::error::inngest-volume-recut
  REFUSED by Guard 2` message; single occurrence of `grep -c "probe_schema=\$EXPECTED"` (verified
  `grep -c` count = 1). Note: hook env measured this session shows git exports `GIT_INDEX_FILE`
  into commit hooks; a linked-worktree commit exports it **absolute** (lefthook.yml comment at
  `plugin-component-test`).
- `tests/scripts/test-inngest-volume-recut-gate.sh` — home for the new anchor pin; its "Row 6
  (workflow dispatch)" block (~lines 365–375) already greps the workflow text for call-site
  properties; anti-vacuity floor at end (`_ran < 53` fails).
- `tests/scripts/test-inngest-host-dark-gate.sh:815` — existing anchored-grep precedent
  (`grep -oE '^probe_schema=[0-9]+'`).
- `scripts/test-all.sh:332` — the nine-name entry-point unset (leave as-is: it is the
  `GIT_LOCATION_VARS` canonical list, lockstep-enforced by `git-env-list-parity.test.sh`, and a
  name list is correct *there* — it is a defined set, not a guess about git).
- `plugins/soleur/test/hook-git-env-coverage.test.sh` — Guard 2 entry-point coverage guard;
  unaffected (it quantifies over `run:` commands and `scripts/hooks/`, not suite internals).

**Institutional learnings.**

- `knowledge-base/project/learnings/2026-09-04-a-learning-two-working-copies-and-it-still-got-re-derived-wrong.md`
  — strip by **prefix**, never by name list; "a fixture that spawns git must be run once with
  `GIT_DIR` deliberately set" (the replay arm implements this verbatim); #7822 tracks the remaining
  shell-suite population.
- `knowledge-base/project/learnings/workflow-issues/2026-04-03-lefthook-git-env-var-leak-breaks-tests.md`
  — the April original: `!key.startsWith("GIT_")` allowlist-by-exclusion.
- `cq-assert-anchor-not-bare-token` — the new pin must match the anchored command string, not a
  bare `probe_schema` token.
- Related merged plan: `knowledge-base/project/plans/2026-09-10-fix-inngest-probe-schema-8-mount-devid-plan.md`
  (the #8017/8015/8013 batch — context for the Guard-2 message lineage).

**Related issues/PRs.** Closes #8051, #8053. Context: #7822 (open umbrella), #7976/#8019 (merged),
#7917 (first surfacing of the conflation), #7849/#7853/#7854 (suite adoption), #7695/ADR-199
(the gate), #8017 (the derivation that introduced the unanchored count).

**Conventions.** Bash suites here use `set -uo pipefail`, `ok`/`bad` helpers, a verdict-ledger
EXIT trap, an instrument self-test, and an assertion floor (`MIN_ASSERTIONS`). Comments carry
issue numbers and the *reasoning*, not just the *what*. Workflow edits may trip the
`security-reminder` PreToolUse hook during `/work` — expected, not an error.

## Problem Statement / Motivation

**#8051.** The suite's leak probe spawns a child that inherits the caller's environment, then
reads `${GIT_AUTHOR_NAME:-<unset>}` from it. The assertion means "the function exported nothing";
what it measures is "nothing is set" — and those differ exactly when a parent already set it.
#7976 patched the surfaced instance by adding names to the probe's `env -u` list — the exact
hand-listed form the 2026-09-04 learning identifies as the re-derivation failure mode. The list
is a claim about which variables git honours, and it goes stale the moment git (or a different
hook) exports another one. Beyond the probe, the suite's other lib-sourcing children (`git init`,
commit-identity, gpgsign, sweep, `INCIDENTS_REPO_ROOT` arms) inherit `GIT_INDEX_FILE`/`GIT_DIR`
from a hook env and trip the location tripwire — a standalone run inside a hook fails 10 arms,
not 3. Lefthook happens to be green today because `scripts/test-all.sh:332` scrubs the location
family at the entry point — that protects the runner path only and cannot cover non-location
`GIT_*` vars the probe asserts on.

**#8053.** #8017 replaced the hardcoded `grep -c probe_schema=3` with a derived
`grep -c "probe_schema=$EXPECTED"` — correct derivation, but the count (5) matches neither
documented branch (0 = pin predates schema, 1 = pin carries it). The four extra hits are comment
lines in the pinned bootstrap. The message is read in exactly one situation: a `stale_schema`
refusal on the gate that authorizes an irreversible volume destroy, by an operator deciding
whether to replace a production host.

## Proposed Solution

**#8051 — two scrub sites + one regression arm, all in `plugins/soleur/test/git-fixture-env-shell.test.sh`:**

1. **Ambient prefix scrub** near the top of the suite (immediately after the `export TMPDIR`
   line, before `REPO_ROOT`), using the lib's own idiom:

   ```bash
   # #8051 — a suite about the environment must own the environment it starts from. git exports
   # GIT_* vars into every hook process (measured from a real pre-commit hook: GIT_DIR,
   # GIT_INDEX_FILE, GIT_AUTHOR_*, GIT_EDITOR, GIT_EXEC_PATH, GIT_PREFIX, GIT_TERMINAL_PROMPT),
   # and every bash -c child below would inherit them. Strip by prefix — a hand-listed name set
   # is a claim about which variables git honours and goes stale the day git adds one
   # (2026-09-04 learning; the five-name env -u list this replaces was itself that shape).
   for _v in ${!GIT_@}; do
     [[ "$_v" == "GIT_LOCATION_VARS" ]] && continue
     unset "$_v"
   done
   unset _v
   ```

   Per-child env injections (`GIT_DIR=/tmp/hostile bash -c …`, the sweep arm's `GIT_SSH=…`, the
   `env "$v=/tmp/hostile"` member loop) are unaffected — they set the var in the child's own env
   spec, after the ambient scrub.

2. **Probe-local prefix scrub** replacing the five-name `env -u` chain at ~lines 192–194, so the
   probe's "known-empty state" property is self-contained even if the ambient scrub is later
   moved or deleted (defense-in-depth, in this file's own style):

   ```bash
   probe=$(bash -c '
     for _v in ${!GIT_@}; do unset "$_v"; done
     source "$1"; git_fixture_env "$2" >/dev/null 2>&1 || true
     echo "CEIL=${GIT_CEILING_DIRECTORIES:-<unset>} ID=${GIT_AUTHOR_NAME:-<unset>} SIGN=${GIT_CONFIG_KEY_0:-<unset>}"' \
     _ "$LIB" "$bad_dir" 2>&1)
   ```

   The scrub runs **before** `source`, so an inherited `GIT_INDEX_FILE` can no longer trip the
   tripwire inside the probe child either.

3. **Hook-env replay regression arm** — the 2026-09-04 learning's "run once with `GIT_DIR`
   deliberately set", self-contained so CI (which never has a hook env) still exercises it:

   ```bash
   printf '\n=== the suite is green under a hook-shaped environment (#8051 regression) ===\n'
   if [[ "${_GFE_HOOK_ENV_REPLAY:-0}" == "1" ]]; then
     ok "inner replay run (the outer invocation supplied the hook env)"
   else
     _replay_rc=0
     _GFE_HOOK_ENV_REPLAY=1 \
       GIT_DIR="/tmp/gfe-hostile-gitdir" GIT_INDEX_FILE="/tmp/gfe-hostile-index" \
       GIT_AUTHOR_NAME="Hook Inherited" GIT_AUTHOR_EMAIL="hook@example.com" \
       GIT_COMMITTER_NAME="Hook Inherited" GIT_EDITOR=":" GIT_PREFIX="sub/" \
       GIT_TERMINAL_PROMPT=0 GIT_EXEC_PATH="/usr/lib/git-core" \
       bash "${BASH_SOURCE[0]}" >/dev/null 2>&1 || _replay_rc=$?
     if [[ "$_replay_rc" == "0" ]]; then
       ok "suite exits 0 under an inherited hook env (GIT_DIR/GIT_INDEX_FILE/GIT_AUTHOR_*)"
     else
       bad "suite exited $_replay_rc under an inherited hook env — the ambient prefix scrub regressed"
     fi
   fi
   ```

   The flag (not a `GIT_*` name, so it survives the inner scrub) prevents recursion; the inner
   run's mktemp ledger and fixture root are independent. Bump `readonly MIN_ASSERTIONS` 24→25.

4. Update the ~line-185 comment block so it documents the prefix scrub (keep the #7917 history;
   the comment explains *why*, which is this file's convention).

**#8053 — one character plus a pin:**

1. `.github/workflows/apply-web-platform-infra.yml` (~line 2325): `grep -c "probe_schema=\$EXPECTED"`
   → `grep -c "^probe_schema=\$EXPECTED"`.
2. New assertion in `tests/scripts/test-inngest-volume-recut-gate.sh`, inside the existing "Row 6
   (workflow dispatch)" block, using `grep -qF` (the `\$` is literal in the file — the message
   prints a copy-pasteable command, so `\$EXPECTED` is deliberately escaped):

   ```bash
   # Row 6d — the recovery command's count must mean what the message documents (0 or 1):
   # unanchored it counts the bootstrap's comment lines (measured 5 vs 1, #8053). The anchored
   # form is already the repo's idiom (test-inngest-host-dark-gate.sh greps '^probe_schema=').
   if grep -qF 'grep -c "^probe_schema=\$EXPECTED"' "$WF"; then
     pass
   else
     fail "Row 6d: the stale_schema recovery command's probe_schema grep lost its ^ anchor (#8053)"
   fi
   ```

**Not in scope:** widening `scripts/test-all.sh`'s or lefthook's nine-name unsets (the
`GIT_LOCATION_VARS` canonical list — correct as a name list, lockstep-enforced); the #7822 census
of other un-scrubbed suites (tracked separately); `inngest-bootstrap.sh` (its comments are correct
and load-bearing); `tests/scripts/lib/inngest-host-dark-gate.sh` (context only).

## Technical Considerations

- **`${!GIT_@}` under `set -u`:** name-expansion (not value-expansion); expands to the empty list
  when no `GIT_*` var is set — no nounset trip. Same idiom as `git-fixture-env.sh:171`. The
  `GIT_LOCATION_VARS` skip is defensive dead code at both new sites (the lib isn't sourced at
  suite top, and the probe child scrubs pre-source) — kept to mirror the lib idiom verbatim and
  to stay safe if a future edit moves a scrub post-source.
- **`compgen -e GIT_` alternative:** equivalent for env vars; `${!GIT_@}` preferred for
  consistency with the subject lib. Either is acceptable to the implementer if the other proves
  necessary (e.g., a shell-version quirk); the ACs assert behaviour, not spelling.
- **Recursion safety:** the replay arm's inner run must not re-enter the arm — the
  `_GFE_HOOK_ENV_REPLAY` flag gates it, and the flag's name deliberately lacks the `GIT_` prefix
  so the inner ambient scrub cannot strip it.
- **Ledger independence:** the inner replay run allocates its own `_VERDICT_LEDGER`/`_FIXTURE_ROOT`
  via `mktemp` — no shared state with the outer run; the outer run counts exactly one new
  assertion.
- **Workflow edit surface:** the message is a single `echo "::error::…"` line inside a `run:`
  block; the `\$EXPECTED` escape is load-bearing (it prints a literal `$EXPECTED` for the operator
  to paste) — the `^` goes inside the quotes, before `probe_schema`, leaving the escape intact.
- **No YAML shape change:** one character inside a double-quoted string in a `run:` script — no
  workflow-structure, trigger, or permission change. CI's `bun-test`/shell suites are unaffected
  by the workflow line itself (it only ever prints on a `stale_schema` refusal).
- **Attack-surface note (security-adjacent):** the prefix scrub runs in the *test suite*, not in
  any security boundary; it widens what the suite clears, never what a fixture grants. No new
  trust decision.

## User-Brand Impact

- **If this lands broken, the user experiences:** (a) a developer's `git commit` failing
  pre-commit with a `[FAIL] PARTIAL env leaked` line naming their own git identity — reads like a
  real credential leak; (b) an operator at the `stale_schema` refusal of an irreversible
  volume-destroy gate reading a count (5) that matches neither documented branch (0 or 1),
  inviting hesitation or a wrong replace decision at the worst moment.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no data exposure — both
  surfaces are internal tooling text (a test assertion and a CI error message).
- **Brand-survival threshold:** `none`
- `threshold: none, reason: the diff touches only a test suite, its pin suite, and one CI error
  message — no regulated data, no user-facing product surface, no persisted state.`

> Sharp edge: a plan whose `## User-Brand Impact` section is empty, contains only placeholder
> text, or omits the threshold fails `deepen-plan` Phase 4.6. It is filled — leave it.

## Observability

```yaml
liveness_signal:
  what:            # the modified suite + pin suite run per lefthook pre-commit and per CI gate run
  cadence:         # per-run (pre-commit on matching globs; full battery in CI)
  alert_target:    # committer's terminal / CI check red
  configured_in:   # lefthook.yml (bun-test -> scripts/test-all.sh), .github/workflows/*
error_reporting:
  destination:     # suite [FAIL]/[FATAL] lines on stderr + non-zero exit
  fail_loud:       # "PARTIAL env leaked for [...]", "[FAIL] suite exited N under an inherited hook env", "Row 6d: ... lost its ^ anchor", verdict-ledger FATAL
failure_modes:
  - mode:          # ambient GIT_* scrub deleted or narrowed to a name list
    detection:     # the hook-env replay arm re-execs the suite under injected GIT_DIR/GIT_INDEX_FILE/GIT_AUTHOR_* and requires exit 0
    alert_route:   # suite red in lefthook/CI
  - mode:          # workflow grep loses its ^ anchor
    detection:     # Row 6d grep -qF on the anchored literal in test-inngest-volume-recut-gate.sh
    alert_route:   # suite red in CI
  - mode:          # suite silently runs fewer arms (arm deletion)
    detection:     # MIN_ASSERTIONS floor (25) + verdict-ledger conservation check
    alert_route:   # suite FATAL, exit 1
logs:
  where:           suite stdout/stderr; lefthook run log; GitHub Actions step log
  retention:       terminal scrollback / Actions log retention (per-repo defaults)
discoverability_test:
  command:         bash plugins/soleur/test/git-fixture-env-shell.test.sh
  expected_output: "0 failed"   # substring of the summary line "N passed, 0 failed, N assertions"
```

## Guard Contract

The deliverable modifies assertion-based checks (the suite's new arms, the workflow pin), so the
guards it touches carry a contract.

### Guard 1 — suite ambient-`GIT_*` hermeticity (new prefix scrub + replay arm)

**Property.** Every `bash -c` child the suite spawns observes a `GIT_*`-free ambient environment,
so lib-sourcing children never trip the location tripwire on inherited vars and the leak probe
measures only what the builder exported.

**Assembly.** The single ambient scrub loop at suite top (the chokepoint every child spawn
flows through — all `bash -c`/`env` invocations inherit it) plus the independent probe-local
scrub inside the leak-probe child (the chokepoint for the asserted-var property, deliberately
redundant with the first).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete the suite-top scrub loop | RED — the replay arm's inner run inherits `GIT_DIR`/`GIT_INDEX_FILE` and fails ≥1 arm |
| 2 | Replace the prefix scrub with the old five-name `env -u` list | RED — the replay arm injects `GIT_DIR`/`GIT_INDEX_FILE`, which the five-name list never covered (tripwire fires inside children) |
| 3 | Delete the replay arm entirely | RED — `MIN_ASSERTIONS` floor (25) breaches: 24 < 25 |
| 4 | Remove the `_GFE_HOOK_ENV_REPLAY` gate so the arm re-execs unconditionally | RED — infinite recursion / inner run never terminates (timeout at harness level; also the arm's own `bad` fires on non-zero) |
| 5 | Harness row: run the suite with only `GIT_AUTHOR_NAME` set (no location vars) — a must-PASS non-canonical input | PASS — proves the scrub doesn't over-clear (identity vars aren't what the tripwire refuses anyway) and that the replay arm isn't the only thing keeping it green |

### Guard 2 — recovery-command anchor pin (new Row 6d)

**Property.** The `stale_schema` recovery command's `probe_schema` count yields exactly the
documented 0/1 semantics — anchored at line start so the bootstrap's comment lines cannot count.

**Assembly.** The single `grep -c` site inside the `::error::inngest-volume-recut REFUSED` echo in
`.github/workflows/apply-web-platform-infra.yml` (verified: exactly one `grep -c "probe_schema=`
occurrence in the file). The pin lives in `test-inngest-volume-recut-gate.sh`'s Row 6 block — the
existing chokepoint for workflow call-site assertions.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Remove the `^` (restore `grep -c "probe_schema=\$EXPECTED"`) | RED — `grep -qF` on the anchored literal fails |
| 2 | Retarget the grep token (e.g. `probe_schema=` → `schema=` in the message) | RED — anchored literal no longer present |
| 3 | Own-dispatch: delete the `if grep -qF …` condition in Row 6d | RED — the `else fail` fires on every run (the check cannot pass vacuously) |
| 4 | Harness row: keep the `^` but drop the `grep -c` verb (`grep "^probe_schema=…"` in the message) | RED — the pinned literal includes `grep -c`, so a weakened command form still fails the pin |

## Acceptance Criteria

- [ ] **AC1 (#8051 regression base).** `bash plugins/soleur/test/git-fixture-env-shell.test.sh`
  under a clean env exits 0 and prints `N passed, 0 failed` (N ≥ 25 after the new arm; all
  pre-existing 24 arms still green).
- [ ] **AC2 (#8051 title scenario).** Under a hook-shaped env —
  `GIT_DIR=/tmp/x GIT_INDEX_FILE=/tmp/x GIT_AUTHOR_NAME="X" GIT_AUTHOR_EMAIL=x@y GIT_COMMITTER_NAME="X" GIT_EDITOR=: GIT_PREFIX=sub/ GIT_TERMINAL_PROMPT=0 GIT_EXEC_PATH=/usr/lib/git-core` —
  `bash plugins/soleur/test/git-fixture-env-shell.test.sh` exits 0 with 0 failures.
- [ ] **AC3 (#8051 mechanism).** The suite contains no `env -u GIT_` hand-listed scrub in the
  leak probe; both scrub sites use prefix expansion (`${!GIT_@}` or `compgen -e GIT_`).
  Verified: `grep -n 'env -u GIT_' plugins/soleur/test/git-fixture-env-shell.test.sh` → no match.
- [ ] **AC4 (#8051 hermetic probe).** The replay arm exists and is flag-gated:
  `grep -n '_GFE_HOOK_ENV_REPLAY' plugins/soleur/test/git-fixture-env-shell.test.sh` → ≥2 hits
  (gate + injection).
- [ ] **AC5 (#8053 mechanism).** `grep -cF 'grep -c "^probe_schema=\$EXPECTED"' .github/workflows/apply-web-platform-infra.yml`
  → `1` (anchored literal present, exactly once — fixed-string match, the `\$` is literal in the
  file) and `grep -cF 'grep -c "probe_schema=\$EXPECTED"'` on the same file → `0` (the unanchored
  form absent — the `^` sits between `"` and `probe_schema`, so the two patterns discriminate).
- [ ] **AC6 (#8053 measured).**
  `EXPECTED=8; git show vinngest-v1.1.35:apps/web-platform/infra/inngest-bootstrap.sh | grep -c "^probe_schema=$EXPECTED"`
  prints `1` (was `5` unanchored), matching the message's documented `1` branch.
- [ ] **AC7 (pin suite green).** `bash tests/scripts/test-inngest-volume-recut-gate.sh` exits 0,
  including the new Row 6d assertion; its anti-vacuity floor still holds.
- [ ] **AC8 (no collateral).** `bash plugins/soleur/test/hook-git-env-coverage.test.sh`,
  `bash plugins/soleur/test/git-fixture-containment.test.sh`, and
  `bash plugins/soleur/test/git-env-list-parity.test.sh` all still exit 0 (no entry-point scrub
  or `GIT_LOCATION_VARS` list touched).

## Test Scenarios

- Given a clean environment, when the suite runs, then all arms pass and the verdict ledger
  reports 0 failures (AC1).
- Given an environment shaped like a `git commit` hook's (the AC2 variable set), when the suite
  runs standalone, then every arm passes — including the three `PARTIAL` arms and every
  lib-sourcing child (AC2).
- Given the ambient scrub deleted, when the replay arm's inner run executes, then it exits
  non-zero and the outer arm reports `[FAIL]` (Guard 1, row 1).
- Given the replay injection uses only `GIT_AUTHOR_NAME`, when the suite runs, then it still
  passes — the scrub clears exactly the `GIT_` prefix and nothing else the suite needs (Guard 1,
  row 5).
- Given the workflow message carries `grep -c "^probe_schema=\$EXPECTED"`, when
  `test-inngest-volume-recut-gate.sh` runs, then Row 6d passes; given the `^` removed, then Row
  6d fails (AC5, Guard 2 rows 1–4).
- Given the pinned `vinngest-v1.1.35` bootstrap, when the recovery command is executed verbatim,
  then it prints `1` — the documented "pin carries it" branch (AC6).

## Success Metrics

- `bash plugins/soleur/test/git-fixture-env-shell.test.sh` → `N passed, 0 failed` under both
  clean and hook-shaped environments.
- Recovery-command count on the pinned image: `1` (down from `5`), matching the documented
  branch.
- Zero changes outside the three named files; `git diff --stat` shows ~40 added / ~10 removed
  lines total.

## Dependencies & Risks

- **Risk — workflow-edit hook:** `.github/workflows/` edits may trip the
  `security-reminder` PreToolUse hook at `/work` time. Mitigation: expected; the change is a
  single character inside one echo string.
- **Risk — `${!GIT_@}` portability:** suite is `#!/usr/bin/env bash`; the idiom needs bash ≥3 and
  is already used by the subject lib. If an environment quirk surfaces, `compgen -e GIT_` is the
  documented fallback — the ACs assert behaviour.
- **Risk — inner-run flakiness:** the replay arm runs the full suite a second time (~seconds;
  the suite already self-fixtures under `TMPDIR`). Acceptable; it replaces a failure mode CI
  could never otherwise see.
- **Dependency — none external:** no new files, no new tools, no network, no infra.
- **Open question (deferred, not blocking):** whether `ralph-loop.test.sh` and the other #7822
  census suites should adopt the same ambient scrub — tracked by #7822, deliberately not folded.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — engineering test/tooling change on internal surfaces
(a bash test suite, its pin suite, one CI error message). No UI-surface file in `## Files to
Edit`/`## Files to Create`, so the Product/UX mechanical override does not fire.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` (65 issues) searched for each planned
file path — `plugins/soleur/test/git-fixture-env-shell.test.sh`,
`.github/workflows/apply-web-platform-infra.yml`,
`tests/scripts/test-inngest-volume-recut-gate.sh`,
`plugins/soleur/test/lib/git-fixture-env.sh` — zero body matches.

## Files to Edit

- `plugins/soleur/test/git-fixture-env-shell.test.sh` — ambient prefix scrub (after `export
  TMPDIR`, ~line 18); probe-local prefix scrub replacing the `env -u` chain (~lines 192–194);
  hook-env replay arm (new, before the summary); `MIN_ASSERTIONS` 24→25 (line 25); comment
  refresh at ~lines 185–191.
- `.github/workflows/apply-web-platform-infra.yml` — `grep -c "probe_schema=\$EXPECTED"` →
  `grep -c "^probe_schema=\$EXPECTED"` in the `::error::inngest-volume-recut REFUSED by Guard 2`
  message (~line 2325).
- `tests/scripts/test-inngest-volume-recut-gate.sh` — new "Row 6d" anchor pin inside the
  workflow-dispatch block (~after line 375).

## Files to Create

None.

## References & Research

- Issues: #8051, #8053 (this plan closes both); #7822 (open umbrella — acknowledged);
  #7917, #7976, #8017, #8019, #7849 (context, merged).
- Subject files: `plugins/soleur/test/git-fixture-env-shell.test.sh`,
  `plugins/soleur/test/lib/git-fixture-env.sh:171` (prefix-sweep idiom),
  `plugins/soleur/test/lib/git-clean-env.ts` (TS prefix helper + rationale),
  `.github/workflows/apply-web-platform-infra.yml` ~line 2325 (message site),
  `tests/scripts/test-inngest-volume-recut-gate.sh` ~lines 365–375 (pin site),
  `tests/scripts/test-inngest-host-dark-gate.sh:815` (anchored-grep precedent).
- Learnings:
  `knowledge-base/project/learnings/2026-09-04-a-learning-two-working-copies-and-it-still-got-re-derived-wrong.md`,
  `knowledge-base/project/learnings/workflow-issues/2026-04-03-lefthook-git-env-var-leak-breaks-tests.md`.
- Sibling plan: `knowledge-base/project/plans/2026-09-10-fix-inngest-probe-schema-8-mount-devid-plan.md`.
- Decision record context: ADR-199 (`inngest` destructive-clearance gate), ADR-129 (owning EXIT
  trap convention), ADR-193 (instrument self-test convention).
- Measured this session: real `pre-commit` hook env dump
  (`GIT_AUTHOR_DATE/EMAIL/NAME`, `GIT_EDITOR`, `GIT_EXEC_PATH`, `GIT_INDEX_FILE`, `GIT_PREFIX`,
  `GIT_TERMINAL_PROMPT`); suite 24/0 clean vs 14/10 under that env; grep 5→1 on the pinned
  bootstrap.
