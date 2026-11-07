---
title: "feat: propagate a brief's stated constraints from one-shot to ship"
type: feat
date: 2026-11-06
slug: propagate-brief-constraints-to-ship
branch: feat-one-shot-brief-constraints-reach-ship
lane: cross-domain
---

# feat: propagate a brief's stated constraints from one-shot to ship

Spec lacks valid `lane:` (no `spec.md` exists for this branch) - defaulted to cross-domain (TR2 fail-closed).

PR: #12246 (draft, already open). Tracker references use `Ref #N` only. Deferral tracked as #12247.

## Enhancement Summary

**Deepened on:** 2026-11-06
**Halt gates run:** 4.6 User-Brand Impact (pass), 4.7 Observability (block added, pass), 4.8 PAT-shaped variables (no hit), 4.9 UI wireframe (not a UI plan), 4.10 Encryption posture (no store or connection), 4.11 Guard Contract (`lint-guard-contract.py` green, assembly read as structural), 4.12 Scope Check (one live section, no `unmapped`/`BLOCKED`), 4.13 Task design (no new autonomous task), 4.5/4.55 (no network or downtime trigger).
**Agents used (scoped fan-out, not the full 40-agent sweep: the plan had already been through plan-review with DHH, Kieran, code-simplicity and CTO-devex, a sharp-edges pass, and two CTO ruling rounds):** security-sentinel, test-design-reviewer, architecture-strategist.

### Key improvements

1. Infra refusal made real for the working tree: the arm builds its own NUL-delimited, rename-free path list from the committed diff, tracked working-tree changes and untracked files, from the repo root, with each source's failure and the grep rc failing closed. Without it a C-quoted (`é.tf`, tab) or untracked infra path rode through a token (security P1, P2).
2. Token channel hardened: the section ends at the first non-bullet line or at a blank line after a bullet, any `#` heading is a boundary, the reader runs under `LC_ALL=C`, and the printed words are an ASCII-only, markup-free, labelled untrusted string, so a planted or appended line cannot become a token, forge a verdict, or smuggle `Closes #N` / `@name` into a pasted PR body (security P2-P3).
3. Test block made falsifiable: each of T18a-c carries a same-branch no-token control, the infra rows use a contexts-absent stub and the arm's full reason, the parity row builds its fixture from the reference's fenced example on a clean tree and also runs the renamed-heading copy, and the mutants grade the exact rc and reason with unique OLD strings (test-design P1-P2).
4. Writer lifecycle: a resumed one-shot run keeps the earlier token when the new brief has none; the writer reads only the operator's typed brief, never a file or issue body (architecture P2).
5. ADR text widened: four skip channels listed, ADR-276's "fails toward stall" sentence qualified to the no-token path, `merge_group` named as the real authority behind "CI is the gate" (architecture P2).

### New considerations discovered

- The existing non-token infra check shares the C-quoted-path blind spot; filed as #12251 (`Ref #12246`), not fixed here.
- Phase 6.45 archival creates a new head SHA, so a post-archival Phase 4 re-run is usually OWED until CI completes (reference wording corrected).
- Only `ci-is-the-gate` is machine-read; other `- constraint:` bullets are informational until #12247 (stated in the reference and the echo).
- Suite duration: +6 to +10 s expected (unmeasured); share one fixture across the reject rows if the drift gate (1.5x and +10 s) would trip.

## Overview

A brief told the pipeline to rely on CI's required test check, and the ship lifecycle skill still ran the local affected battery for about 45 minutes. The cause is a hand-off gap: `soleur:one-shot` passes the brief to plan, but invokes work with the plan path only and ship with no args, and ship's battery gate (`battery-owed.sh`) reads CI state, never operator intent. The design was ruled by the CTO agent on 2026-11-06 as D7 (learning `knowledge-base/project/learnings/2026-11-06-a-cleanup-brief-with-three-items-had-two-already-resolved-on-main.md`, Session Error #3; archived `decision-challenges.md` D7 under `knowledge-base/project/specs/archive/20261106-100947-feat-one-shot-bun-pair-ratchet-accept-cleanup/`): one-shot writes the brief's constraint lines under `## Operator Constraints` in `specs/<branch>/session-state.md` with a `- ci-is-the-gate: <verbatim operator words>` token, and `battery-owed.sh` exits 42 on that token unless `--full` or an infra/unresolved diff is in play. This plan turns that design into edits, and records the residual forks the D7 ruling left open (F1-F14, all CTO-ruled; see `knowledge-base/project/specs/feat-one-shot-brief-constraints-reach-ship/decision-challenges.md`).

## Research Reconciliation - Spec vs. Codebase

| Brief / learning claim | Reality (measured 2026-11-06) | Plan response |
|---|---|---|
| "ship has 44 B and one-shot 9 B of body-budget headroom" | True: `ship/SKILL.md` 273911 B vs ceiling 273955; `one-shot/SKILL.md` 51991 B vs 52000 (`plugins/soleur/test/skill-body-budget.json`) | Edits are net-negative, measured on the real files (ship -146 B, one-shot -3 B; a reviewer's scratch measurement of an earlier draft read -44 B for one-shot); `skill-body-budget.json` is not touched |
| "`battery-owed.sh` exits 42 on the token unless `--full` or an infra/unresolved diff" | `--full` already outranks `battery-owed.sh` in the Phase 4 dispatch block (FULL_BATTERY arm first). The infra/unresolved-diff scoping is condition 3's block, which sits AFTER condition 1 (dirty tree) and condition 2 (origin/main ancestor) | CTO F1 + F10: the token stands conditions 1 and 2 down and its arm sits after the existing diff scoping and before condition 4; no function hoist |
| (implicit) the first Phase 4 run sees a clean tree | Repo research: no skill explicitly commits `session-state.md` before Phase 4 (ship Phase 1 "stage and commit" may sweep it - not verified), so the tree is usually dirty (untracked file) at the first run and condition 1 returns OWED on any `git status --porcelain` output | CTO F2/F11: a dirty tree does not block the token skip; no "tree dirty" note (constant noise on the one path this serves) |
| (implicit) the token outlives the run | `ship` Phase 6.45 (`archive-kb.sh`) `git mv`s `specs/<branch>/` to `specs/archive/` before merge; the script reads only `specs/<branch>/session-state.md` | CTO F12 rule A: documented limit in the reference; a later re-run falls back to the existing CI-evidence path |
| (implicit) one-shot appends to `session-state.md` | The one-shot success arm step 3 writes a full-document template ("create if needed") - whole-file overwrite semantics; the fallback arm writes "under `## Plan Phase`" | The constraints section is appended AFTER each arm's own write; later writes only append (O1 and the reference say so) |
| "new rows in `ship-battery-owed.test.sh`" | The suite ends `print_results 63`, a FLOOR (`ran < expected` fails; more is fine) | Raise the floor to the exact count of a green run; do not leave it at 63 (slack hides deleted rows) |
| brief: "edit one-shot, ship and battery-owed.sh" | Also needed: new `one-shot/references/operator-constraints.md`, new test rows, one declared edge in `scripts/lib/test-affected-paths.sh`, an ADR-242 amendment (CTO F8) | Listed under Files to Create / Edit |

## Research Insights

**Premise validation (Phase 0.6).** Cited artifacts: PR #12187 (open, not draft, edits `ship/SKILL.md`, `scripts/lib/test-affected-paths.sh`, `scripts/suite-durations.tsv`, `scripts/suite-shard-legs.tsv`, `plugins/soleur/test/fixture-relative-assert.baseline.txt` - different content; not touched here). `git grep ci-is-the-gate|Operator Constraints origin/main` returns nothing: this is a build, not the completion of a half-landed change. ADR corpus: ADR-242 `## Consequences` ("`/ship` Phase 4 dispatches `battery-owed.sh` first; OWED (or any non-42 verdict) runs `--affected`") and ADR-183/ADR-276 were read; none rejects an operator-intent input to the gate; ADR-242 needs an amendment because it defines 42 as "CI verified this tree".

**Property List (Phase 0.6b).**

1. A brief that says to rely on CI reaches the code that decides whether Phase 4's local battery runs (the brief's words, not a model's memory of them).
2. With that constraint, Phase 4's local battery is skipped without a 45-minute run, including when the branch is behind `origin/main`, has no CI yet, or the tree is dirty.
3. The skip never covers the local infra shard (the suites `test-all.sh` runs for `apps/web-platform/infra/` and `.github/workflows/apply-web-platform-infra.yml`, the two prefixes of its `_infra_in_diff` block; no required CI check runs them, #6480) - an infra path (committed, staged or untracked) or an unresolved diff stays OWED. Other `infra-validation.yml` path triggers (`apps/*/infra/**`, `infra/**`) are neither covered locally nor required today; the arm neither changes nor claims them.
4. `--full` still outranks the constraint.
5. The PR records what did NOT run, in the operator's words.
6. SKILL.md bodies do not grow.

**Cut List.** Deterministic constraint-extractor script - property 1 is met by a phrase list judged by the one-shot agent with "when in doubt, no token" (CTO F5; an extractor would add a suite plus three registry rows). Passing constraints through ship's `$ARGUMENTS` - ship is invoked with no args and `--full` parsing lives there; a file the script reads needs no arg plumbing and survives a resumed session. A new Test-plan template block in `ship/SKILL.md` - the script's verdict line already carries the text (CTO F6). An env kill-switch - another bypass surface; `--full` already forces the full run (CTO F9). A function hoist of condition 3's diff scoping (CTO F10: stand-down guards on conditions 1 and 2 give the same behaviour with no moved block). A symlink test on the token file and a `; tree dirty` note (CTO F11: no threat model / constant noise). Reading the archived `session-state.md` after Phase 6.45 (CTO F12: could belong to an older run of the same branch name). Rows dropped by plan-review as duplicates of existing pins: dirty-tree, rename-into-infra, FULL_BATTERY ordering, SKILL.md-link clause. Honouring the token in work Phase 2 / review - out of scope, tracked as #12247 (CTO F7).

**Institutional learnings applied.** `2026-09-23-compressing-prose-to-fit-a-byte-ceiling-dropped-the-conditions-that-made-it-correct.md` (every trimmed clause below is rationale, not a condition; the Phase 4 conditions stay in the script); `2026-10-28-a-brief-said-rc4-meant-the-monitor-lock-and-the-issue-meant-the-battery-refusal.md` (origin of "CI is the gate" exit 42; every conjunct of a skip must be checked at the emit site and have a mutant row); `2026-05-15-one-shot-plan-subagent-cwd-divergence.md` (write by explicit worktree path); `battery-owed.sh` header (check-run names arrive in the PR diff - hence the live ruleset, never a committed file, is merge authority; the token is read as an operator-intent hint only).

**Functional overlap check (Phase 1.5b).** No community skill or agent provides operator-constraint propagation into a ship gate (3 registries queried, 0 hits).

**Tests pinning the touched text (repo research).** `ship-battery-owed.test.sh` T16 extracts the Phase 4 dispatch block with awk from the `FULL_BATTERY:-}.*==.*true` line to the first column-0 `fi` and pins `affected-tests.sh" --full`, no `battery-owed.sh.*--full`, `affected-tests.sh` in the OWED arm, and `rc -eq 42`; `fullsuite-merge-gate.test.ts` slices `## Phase 4: Run Tests` .. `## Phase 5: Final Checklist`; `plan-skeleton-checkpoint.test.ts` pins one `bash` block in one-shot containing `^branch:` + `awk`; `components.test.ts` requires every `references/*.md` to be named by basename in its skill's SKILL.md and bans backtick `references/...` paths in skill bodies; `plugin-root-skills-ratchet.tsv` forbids new bare `bash scripts/...` lines in one-shot/ship. None pins the paragraphs this plan edits.

## Open Code-Review Overlap

None (queried `gh issue list --label code-review --state open` for all planned file paths; no body names any).

## Problem Statement

`soleur:ship` Phase 4 mandates the local affected gate; its only skips are machine-derived (`battery-owed.sh` exit 42 when CI already verified the SHA, `battery-refusal-wait.sh` exit 42 on a sibling-run refusal). Neither can read operator intent, and `battery-owed.sh` is OWED on the first Phase 4 run by construction (no CI for HEAD yet; typically also behind main and dirty). A brief's "rely on CI's required test check" therefore has no path to the decision.

## Proposed Solution

```text
brief ($ARGUMENTS / persist_safe_summary)
   |  one-shot: after the plan subagent returns, in BOTH arms, once that arm has written session-state.md (later writes only append)
   v
knowledge-base/project/specs/<branch>/session-state.md
   ## Operator Constraints
   - constraint: <each binding constraint line, verbatim>
   - ci-is-the-gate: <operator's own words, one line, <= 200 bytes>      <- only when the brief says rely on CI
   |  ship Phase 4: `--full`? -> run full.  else battery-owed.sh
   v
battery-owed.sh
   token? -> conditions 1 (dirty) and 2 (behind main) stand down; diff scoping (existing) -> infra surface? OWED : SKIPPABLE (42), BEFORE condition 4
   no token -> conditions 1-4 exactly as today (byte-identical path)
```

### `battery-owed.sh` changes (exact shape; CTO F1 + F10, hardened by plan-review and the sharp-edges pass)

No function hoist and no moved block: the token is read once near the top, conditions 1 and 2 stand down for it, and the arm sits right after the existing `INFRA_RE=` line (diff scoping is already computed there, so the unresolvable/undecidable-diff exits are the existing ones) and BEFORE condition 4.

1. After the `is-inside-work-tree` check, read the token (working-tree file only, never `origin/*`; detached HEAD or a missing file means no token). The reader runs under `LC_ALL=C` (bytes, not locale characters), ends the section at the first non-bullet line or at a blank line after a bullet (so text appended later cannot become a token), treats any `#` heading as a boundary, and passes the words through a printable-ASCII filter that also drops markup characters (deepen-plan security pass #3, #4, #5):

```bash
OPERATOR_CI_WORDS=""
_br="$(git branch --show-current 2>/dev/null)"
_ss="$(git rev-parse --show-toplevel 2>/dev/null)/knowledge-base/project/specs/${_br}/session-state.md"
if [[ -n "$_br" && -f "$_ss" ]]; then
  OPERATOR_CI_WORDS="$(LC_ALL=C awk '
    /^#+[[:space:]]/ { s = ($0 == "## Operator Constraints"); b = 0; next }
    s && /^[[:space:]]*$/ { if (b) s = 0; next }
    s && !/^- / { s = 0; next }
    s { b = 1 }
    s && /^- ci-is-the-gate:[[:space:]]+[^[:space:]]/ { sub(/^- ci-is-the-gate:[[:space:]]+/, ""); print substr($0, 1, 200); exit }' "$_ss" 2>/dev/null \
    | LC_ALL=C tr -cd ' -~' | LC_ALL=C tr -d '"\\`@#<>$[]')"
  [[ -n "${OPERATOR_CI_WORDS//[[:space:]]/}" ]] || OPERATOR_CI_WORDS=""
fi
```

   The line anchor needs a non-space character after at least one space, and the filter runs BEFORE the emptiness test, so whitespace-only, control-only or non-ASCII-only words are no token. The 200 is a byte cut (`LC_ALL=C`, pinned by a multibyte row). The first token line in ANY section named exactly `## Operator Constraints` wins (the writer is told to keep exactly one section; a second one is read, not ignored). A CRLF file fails closed (the heading anchor is an exact string). The reader prints only lines that match the token anchor, so a symlinked `session-state.md` cannot make it emit arbitrary file content (no `-L` test, CTO F11b).
2. Condition 1: `[[ -n "$DIRTY" ]] && owed ...` becomes `[[ -n "$DIRTY" && -z "$OPERATOR_CI_WORDS" ]] && owed ...` (CTO F2). Condition 2: `if ! git merge-base --is-ancestor refs/remotes/origin/main HEAD ...` becomes `if [[ -z "$OPERATOR_CI_WORDS" ]] && ! git merge-base --is-ancestor refs/remotes/origin/main HEAD ...`.
3. The three `undecidable` messages in the diff-scoping region (origin/main unresolvable, diff failure, empty-diff-not-ancestor) gain the prefix `${OPERATOR_CI_WORDS:+operator ci-is-the-gate set but }` so an operator who said "rely on CI" and sees a battery run is told why (devex review #1; empty expansion on the no-token path).
4. The arm, immediately after the `INFRA_RE=` line. Condition 1 is no longer guaranteed, so the arm builds its OWN path list from three NUL-delimited, rename-free sources (committed diff, tracked working-tree changes, untracked files) before the infra test. NUL-delimited because git C-quotes paths holding a non-ASCII byte, tab, `"` or `\` (`"apps/web-platform/infra/\303\251.tf"`), which the `^`-anchored `INFRA_RE` then misses (security pass #1, verified on a probe repo); `--no-renames` lists both the old and the new path of a rename; `git -C "$_top"` makes the untracked listing root-relative and repo-wide whatever the cwd (security pass #2). Each source has its own failure exit, and a grep error fails closed:

```bash
if [[ -n "$OPERATOR_CI_WORDS" ]]; then
  _top="$(git rev-parse --show-toplevel 2>/dev/null)" \
    && _w1="$(git -C "$_top" diff -z --no-renames --name-only origin/main...HEAD | tr '\0' '\n')" \
    && _w2="$(git -C "$_top" diff -z --no-renames --name-only HEAD | tr '\0' '\n')" \
    && _w3="$(git -C "$_top" ls-files -z -o --exclude-standard | tr '\0' '\n')" \
    || undecidable "operator ci-is-the-gate set but the working-tree scope check failed"
  _all="${_w1}"$'\n'"${_w2}"$'\n'"${_w3}"
  grep -qE "$INFRA_RE" <<<"$_all"; _g=$?
  (( _g == 0 )) && owed "operator ci-is-the-gate set, but the diff touches the infra surface (no required CI check, #6480): the local infra shard is its only BLOCKING gate"
  (( _g == 1 )) || undecidable "operator ci-is-the-gate set but the infra scope check errored (grep rc=${_g})"
  skippable "operator ci-is-the-gate (untrusted text from session-state.md: ${OPERATOR_CI_WORDS}): local battery NOT executed; CI's required test context is the gate. Record in the PR Test plan: local battery NOT executed per operator constraint; CI test is the gate"
fi
```

   The arm runs its OWN `INFRA_RE` grep: the existing infra refusal sits after condition 4 and depends on `REQUIRED_JSON`, which a token exit before condition 4 would skip (CTO F10). It needs only `git`, `awk`, `tr` and `grep`, so it works where condition 4 would be UNDECIDABLE. The words are printed so a planted token is visible, labelled as untrusted text, and cannot forge a verdict line, close the quote, or smuggle `Closes #N` / `@name` into a pasted PR body (the filter dropped `"`, `\`, a backtick, `@`, `#`, `<`, `>`, `$`, `[`, `]` and every non-printable or non-ASCII byte); the PR Test plan receives only the fixed phrase after `Record in the PR Test plan:`. The arm's infra refusal does not self-retire like condition 4's (it refuses forever; fails closed). Pre-existing, out of scope and tracked separately: the existing non-token infra check in condition 3/4 reads the C-quoted `--name-status` output and shares the same blind spot (filed as a separate issue, `Ref #12246`). A branch name containing `/` maps to a nested path and reads no token; add both facts as inline comments.
5. Update the exit-contract header: 42 now also means "the operator declared CI the gate"; add the WHY (2026-11-06 incident) and the trust statement (single source for the trust model; the reference points here). Do not touch the existing `rc=$?` after the `CHANGED=` pipeline: under `pipefail` it reads the pipeline's rightmost non-zero status, so a failing `git diff` already reaches `undecidable`.

### `ship/SKILL.md` edits (measured on the real file: 273911 -> 273765 B; S1 -28, S2 +63, S3 -21, S4 -160 = -146 B)

Four hunks (CTO F14: no cross-skill link; the verdict line carries the instruction). T16's awk window (FULL_BATTERY line to the first column-0 `fi`) and its four pins are unaffected by S1. The old `(#8247)` pointer disappears from the echo only; it remains in the script header.

S1 - dispatch block, rc 42 arm (the old text is false for the token case; the script prints the true verdict):

````text
BEFORE:     echo "battery SKIPPED: CI already verified this exact SHA (#8247)"
AFTER:      echo "battery SKIPPED (verdict above)"
````

S2 - the "At the FIRST Phase 4 run" paragraph, one clause:

````text
BEFORE: Phase 6 push and there is no CI for `HEAD` yet.
AFTER:  Phase 6 push and there is no CI for `HEAD` yet, unless the brief set `ci-is-the-gate` (see `battery-owed.sh`).
````

S3 - checklist line:

````text
BEFORE: recorded "CI is the gate" (battery-refusal-wait exit 42)
AFTER:  recorded "CI is the gate" (exit 42)
````

S4 - the offset (needed: S1-S3 alone measure +14 B). Delete this sentence, which duplicates the script header's WHY paragraph ("Measured on PR #8233: two full batteries, ~70 min"); it sits in the same paragraph as S2, so the four hunks stay local:

````text
 Measured on PR #8233: two full
batteries, ~70 minutes, the second finishing against a head whose 26/26 required
checks were already green on the identical SHA.
````

### `one-shot/SKILL.md` edits (measured: 51991 -> 51988 B; O1 +232, O2 -235 = -3 B; margin is thin)

O1 - after the sentence "After the subagent returns, check for a `## Session Summary` heading in the output." append:

````text
 In both arms, once that arm has written session-state.md, append the brief's `## Operator Constraints` ([operator-constraints.md](${CLAUDE_PLUGIN_ROOT}/skills/one-shot/references/operator-constraints.md)); later writes only append.
````

O2 - Step 0a.5 "Why this gate exists" paragraph (rationale only, no condition). Delete these three fragments; if `wc -c` after editing is not <= 51991, delete further rationale clauses from the same paragraph (never a condition):

````text
The check is cheap (≤2 `gh` calls per issue ref) and runs before the worktree exists, so the abort path costs nothing.
 See #4363 for the original false-positive that motivated the carve-out.
 Cost is the same ≤2 `gh` calls per ref.
````

Both files stay under their ceilings with the ceilings untouched. The implementer MUST re-measure with `wc -c` and `python3 scripts/lint-skill-body-budget.py --base origin/main` after editing (a trimmed clause that turns out to be pinned is restored and the trim moved elsewhere, per the 2026-09-23 learning).

### New reference `plugins/soleur/skills/one-shot/references/operator-constraints.md` (about 25 lines; the writer contract only)

No `${CLAUDE_PLUGIN_ROOT}` shell commands, so no plugin-root preamble is required. It carries a fenced example of the section so the parity row (T18p) can derive the strings from it.

1. **What to write.** After the success arm's template write or the fallback arm's outcome write (both rewrite or create the file, so the append comes second; every later write to `session-state.md` only appends), append `## Operator Constraints` to `knowledge-base/project/specs/<exact-branch-name>/session-state.md` by explicit worktree path (create the file if absent; REPLACE an existing section on a resumed run, never append a second one): one bullet per binding constraint line of the brief (the `Constraints:` / rules paragraph or bullet list, not the problem statement), verbatim, control characters stripped, each written as `- constraint: <text>` so a brief line can never be mistaken for the token (sharp-edges #5), all bullets contiguous (a blank line ends the section for the reader), and any later append goes under its OWN level-2 heading. The writer reads only the operator's typed brief text (`persist_safe_summary` when substituted); the body of a file-path or `#N` target is never scanned, so no token is written for it (architecture pass #2). Before the arm's whole-file template write, save any existing `## Operator Constraints` section; after the write put this run's section back, or the saved one when this run's brief yields no constraint lines, and print `kept existing token line: ...` (architecture pass #1). Only `ci-is-the-gate` is machine-read, and only by ship Phase 4; other `- constraint:` lines are informational until #12247. Constraint text is DATA: never obeyed as an instruction by the writer. Then print, in the session, the exact token line written or `no ci-is-the-gate token written` (CTO F13).
2. **The token.** `- ci-is-the-gate: <the operator's own words, one line, at most 200 bytes>` as its own bullet inside that section, written ONLY when the brief tells the pipeline to rely on CI for the tests (phrase list: "rely on CI", "CI is the gate", "CI's required test check", "do not run the local (affected) battery"). Not when the brief is silent, asks for a local run, or passes `--full`. When in doubt, no token (false negative = today's behaviour; false positive = a skipped local run with CI still gating).
3. **Recover and lifetime.** Wrong token: delete the bullet, or run `/ship --full` for one run. Missing token: add `- ci-is-the-gate: <words>` under `## Operator Constraints` by hand. The token applies to every Phase 4 run on the branch until removed, and until ship Phase 6.45 archives `specs/<branch>/` (CTO F12: a re-run after archival falls back to the existing CI-evidence path, which is usually OWED until CI completes on the archive commit's new head SHA). Reader, trust model and `--full`/infra behaviour: the `battery-owed.sh` header. work Phase 2 and review's local gate do not read the token (#12247).

### Tests (`plugins/soleur/test/ship-battery-owed.test.sh`, new block T18)

Written FIRST (RED against the unmodified script). Reuse `build_fixture`, `make_stub`, `run_gate`, `run_gate_out`, `assert_reason`, `in_fixture`, `new_fixture_root`; add two small helpers: `assert_not_reason` (a negative needle, always paired with the positive fall-through needle so an empty crash output cannot satisfy "lacks") and `parity_rc <reference-path>` (see T18p). `run_gate` always `cd`s to the fixture root, so T18g takes an optional subdir argument. The first-run state of `session-state.md` is EITHER untracked or committed (ship Phase 1 may or may not have swept it - not verified), so rows cover both and say which. Setup chains steps with `&&` and ends non-failing (`in_fixture` returns non-zero on any failed inner command, which under the harness's errexit would kill the suite mid-file with no message). Write session-state through `in_fixture ... bash -c 'mkdir -p ... && printf ... > relative/path'` (relative operands inside the fixture) so `fixture-relative-assert.baseline.txt` stays equal; if the count moves anyway, regenerate in the same commit with `bash plugins/soleur/test/fixture-relative-assert.test.sh --write-baseline` (PR #12187 edits that file too, so keep this to the minimum). Needles for `assert_reason` are built with `printf` and never start with `-`. Time the suite once after the block lands (about 18 s today, +6 to +10 s expected, unmeasured); if it would exceed 1.5x AND +10 s, share one fixture across the reject rows T18j-n instead of building one each.

A reject row asserts BOTH the fall-through reason (for example `required context(s) not present`) and, through `assert_not_reason`, that the verdict line lacks `operator ci-is-the-gate`. The infra rows use a contexts-ABSENT stub (`green_sha=""`), so "arm gone" falls through to a clearly different reason instead of the existing condition-4 infra refusal that a green stub would also reach.

Each of the first three rows isolates ONE of the conditions the arm outranks, and carries a same-fixture no-token CONTROL (rename the branch, `git branch -m feat-fixture feat-other`, so the token path is invisible while tree and HEAD are unchanged, assert the specific non-42 verdict, rename back) that proves the counterfactual:

| Row | Fixture | Isolates | Expect (token) | Control (no token) |
|---|---|---|---|---|
| T18a | committed token, in sync with origin/main, ruleset unreadable (`rules_rc=1`) | condition 4 | 42 | rc 2 |
| T18b | committed token, `origin/main` advanced (branch BEHIND, built as in T5d), required contexts green for HEAD | condition 2 | 42 | reason `not an ancestor of HEAD` |
| T18c | UNTRACKED token file, in sync, required contexts green for HEAD | condition 1 | 42 | reason `working tree is dirty` |
| T18d | all at once - the incident shape: untracked token as the LAST of three bullets, branch behind, contexts ABSENT, ruleset readable; output contains `local battery NOT executed per operator constraint` | 1, 2, 4 together | 42 | - |
| T18e | token + `apps/web-platform/infra/deploy.sh` committed in the diff | infra, committed | 0; reason `operator ci-is-the-gate set, but the diff touches the infra surface` | - |
| T18f | token + ONLY `.github/workflows/apply-web-platform-infra.yml` in the diff | infra, 2nd alternative | 0; same reason | - |
| T18g | token + an UNTRACKED `apps/web-platform/infra/new.tf` (clean committed diff), run from the repo root AND from a fixture subdirectory; plus an unstaged-modified tracked infra file sub-row | working-tree infra | 0; same reason | - |
| T18h | token + a rename INTO the infra surface, built by committing `outside.tf` (content `y`) then `mkdir -p apps/web-platform/infra && git mv outside.tf apps/web-platform/infra/outside.tf`, uncommitted; a loud setup assertion that `git diff --name-status -M HEAD` starts with `R` | working-tree rename | 0; same reason | - |
| T18i | token + a committed `apps/web-platform/infra/é.tf` and a second with a tab in its name (git C-quotes both without `-z`) | quoted paths | 0; same reason | - |
| T18j | `- ci-is-the-gate: x` under `## Plan Phase`; and the same bullet under a `### Errors` sub-heading after the section | wrong section | 0; reject assertions | - |
| T18k | `- ci-is-the-gate:` with no words; with two spaces only; with only a control character; with only non-ASCII (four sub-rows) | empty words | 0; reject assertions | - |
| T18l | token only in `specs/some-other-branch/session-state.md` | wrong branch | 0; reject assertions | - |
| T18m | `- constraint: ci-is-the-gate: x` and no agent token; a token bullet appended after a blank line following the section; a token after a non-bullet line | channel hardening | 0; reject assertions | - |
| T18n | two sections named `## Operator Constraints`, the token only in the second | documented behaviour | 42 (the first token in ANY such section wins; the writer keeps one) | - |
| T18o | ASCII words: a control character before position 198, distinct markers at positions 198-200 (present) and 201 (absent), `$(...)`, a backtick and `"` (stripped, never evaluated); `run_gate_out` | sanitize + byte cut | 42; output has the markers and lacks the control character, the quote and the sentinel | - |
| T18p | writer/reader parity: `parity_rc "$REF"` extracts the heading and the example token line from the reference's FENCED example (line-anchored `^## Operator Constraints$` and `^- ci-is-the-gate:`, first match inside the fence), commits them as the fixture's session-state with contexts ABSENT and a clean tree (so a no-token fall-through is OWED, never the CI-evidence 42), and runs the real gate; an explicit `[[ -r "$REF" ]]` guard and a separate non-empty-extraction row name a failure's cause | parity | 42 with `operator ci-is-the-gate`; and 0 for a COPY of the reference whose heading is renamed | - |
| T18q-s | three committed mutants of a COPY of the gate (own `mut18` helper taking the fixture and stub as arguments, grading the EXACT mutant rc and a reason needle, never "any non-zero", `bash -n` on the mutant, plus one pristine-copy control row): (q) the arm's `if [[ -n "$OPERATOR_CI_WORDS" ]]; then` dispatch plus its first line replaced so the arm never fires (T18d must return rc 0 with `required context(s) not present`); (r) the line `grep -qE "$INFRA_RE" <<<"$_all"; _g=$?` replaced by `true; _g=1` (T18e must return 42); (s) the complete condition-2 text `[[ -z "$OPERATOR_CI_WORDS" ]] && ! git merge-base --is-ancestor refs/remotes/origin/main HEAD` reverted to the original (T18b must return rc 0 with `not an ancestor of HEAD`) | mutants | graded exactly, real gate green |

Dropped after plan-review (duplicates of existing pins): the FULL_BATTERY ordering row (T16a-d pin it), the symlink row (CTO F11b), the SKILL.md-link clause of the parity row (`components.test.ts` already requires the basename), and a rename-into-infra row on committed history (T5f/g/h).

Raise `print_results 63` to the exact count of the green run (the floor fails when `ran < expected`; set it equal, not below). Declare ONE edge in `AFFECTED_PLUGINS_SOLEUR_TEST_SHIP_BATTERY_OWED_TEST_SH_PATHS` in `scripts/lib/test-affected-paths.sh`: `plugins/soleur/skills/one-shot/references/operator-constraints.md` (the one new file the suite reads; it must exist as a tracked file in the same commit - `lint-orphan-test-suites.sh` checks; without the edge nothing fails but the suite silently stops being selected when the reference changes). Editing `test-affected-paths.sh` degrades a LOCAL affected run to full (`runner-changed`); that is part of why this PR does not run the local battery to completion. `suite-shard-legs.tsv` and `suite-durations.tsv` are not edited (regeneration owns them; the duration drift gate only fires above 1.5x AND +10 s).

### Architecture Decision (ADR/C4)

#### ADR

Amend ADR-242 (`knowledge-base/engineering/architecture/decisions/ADR-242-the-local-gate-defaults-to-affected-suites-and-always-on-ratchets.md`) via `soleur:architecture`: one short dated section `## Amendment — 2026-11-06 (#12246)` (em dash, matching the corpus) after the last amendment, plus an `amended_by` frontmatter line unless a frontmatter lint rejects it (the newest existing entry is #10198; later amendments carry none). ADR-242 `## Consequences` describe `battery-owed.sh` as a dedup gate ("OWED (or any non-42 verdict) runs `--affected`, and `--full` is an explicit operator opt-in that outranks even a SKIPPABLE verdict ... not a dedup decision"); the amendment records that 42 is no longer only a dedup verdict. Also add a pointer-only amendment to ADR-183 (`knowledge-base/engineering/architecture/decisions/ADR-183-full-suite-runs-at-ship-not-at-implementation-exit.md`), whose existing `## Amendment — 2026-10-28 (P4d, #10924, ADR-196 addendum)` is the sibling "exit 42 = CI is the gate" record and whose decision (one full local battery per PR at `/ship`) the token also waives. Decision: exit 42 of `battery-owed.sh` no longer means only "CI already verified this tree"; it also means "the operator declared CI the gate" (token in `session-state.md`; conditions 1, 2 and 4 stand down; an infra or unresolved diff is still OWED; `--full` outranks). The amendment also (a) lists the four "skip" channels and what each means - `battery-owed.sh` 42 on CI evidence, `battery-owed.sh` 42 on operator intent (new, reads no CI state), `battery-refusal-wait.sh` 42 after a sibling-run refusal, and `affected-tests.sh` rc 6 budget deferral; (b) states that ADR-276's consumer-record sentence (`battery-owed.sh` reads check conclusions and fails toward stall) holds for the no-token path only, and that "CI's required `test` is the gate" is read per the ADR-183 2026-10-14 amendment and ADR-276 (`merge_group` is the full-battery authority, a `pull_request` green may be a reduced run). Add a one-line pointer-only amendment to ADR-276 (its amendments are headed `## Amendment 2026-11-05 (...)`, no em dash) if the ADR lint allows it. Point at `decision-challenges.md` F1, F5, F10 for the rejected alternatives instead of restating them. This is a deliverable of this PR, not a follow-up (`wg-architecture-decision-is-a-plan-deliverable`). No new ADR, so no ordinal question.

#### C4 views

No C4 change. Read `model.c4`, `views.c4`, `spec.c4`: `ship skill` and `one-shot skill` are existing components (`model.c4` `ship = component "ship skill"`, `oneshot = component "one-shot skill"`); the change adds no external human actor, no external system or vendor, no container or data store, and no actor-to-surface access relationship (the file is the existing per-branch `session-state.md` working file in the repo); `battery-owed.sh` is script-level detail below the component grain. Run `bash plugins/soleur/test/c4-count-parity.test.sh` once at implementation to back the no-impact conclusion with a green gate.

#### Sequencing

The ADR amendment lands in the same PR; no soak.

## Guard Contract

### Guard 1 - battery-owed.sh operator CI-is-the-gate arm

**Property.** A `ci-is-the-gate` token in the current branch's `session-state.md` makes `battery-owed.sh` return 42 when neither the committed diff nor the working tree (staged or untracked) touches the infra surface, and never otherwise (no token, token in the wrong section or branch, empty/whitespace-only/non-ASCII-only words, an infra path in any of the three sources including a C-quoted one, an unresolvable diff, a failed git source, a grep error).

**Assembly.** The decision quantifies over: (a) the token reader (branch resolution, path, section boundaries, line anchor with a non-space first character, byte-wise `LC_ALL=C` cut, ASCII-and-markup filter, filter-then-test), (b) the two stand-down guards on conditions 1 and 2 (the only places the token changes an existing refusal), (c) the arm's own `INFRA_RE` grep over the three NUL-delimited sources (committed diff, tracked working-tree changes, untracked files), each with its own failure exit, and the grep's rc handled (0 refuse, 1 pass, else UNDECIDABLE), plus the existing diff-scoping exits that precede it (the chokepoint for the infra/unresolved-diff verdict; the arm must come AFTER them and BEFORE condition 4), (d) the Phase 4 dispatch block in `ship/SKILL.md` where `FULL_BATTERY` precedes the `battery-owed.sh` call (the only caller; `battery-refusal-wait.sh` is a post-launch refusal path with its own independent 42; pinned by existing T16a-d). Out of the assembly: work Phase 2 and review's local gate (#12247).

**Mutation matrix:** rows 1-3 are EXECUTED as committed mutants (T18q-s); rows 4-14 are covered by the named behavioural row and are run once by hand at implementation, not committed.

| # | Mutation | Expected |
|---|---|---|
| 1 | Disable the arm's dispatch (`[[ -n "$OPERATOR_CI_WORDS" ]]` -> false): a guard that reports nothing and falls through is vacuous (executed: T18q) | T18d RED |
| 2 | Remove the arm's own `INFRA_RE` grep (executed: T18r) | T18e RED (returns 42 on an infra diff) |
| 3 | Remove the `-z "$OPERATOR_CI_WORDS"` guard from condition 2 (executed: T18s) | T18b RED (OWED on a behind-main branch) |
| 4 | Remove the `-z` guard from condition 1 | T18c RED |
| 5 | Make the section anchor constant true (any section's token counts) | T18j RED |
| 6 | Stop the awk at the first bullet of the section (a check that stops at the first member) | T18d RED (the token is the LAST of three bullets) |
| 7 | Replace branch scoping by `specs/*/session-state.md` | T18l RED |
| 8 | Drop the second `INFRA_RE` alternative from the script | T18f RED and existing T5b RED |
| 9 | Test the raw words for emptiness instead of the filtered words | T18k RED (control-only and non-ASCII-only sub-rows) |
| 10 | Drop the tracked-working-tree source (`git diff HEAD`) or the untracked source from the arm's path list | T18h and T18g RED |
| 11 | Corrupt `INFRA_RE` (a grep rc 2 must fail closed, not skip) | any arm row returns not-42 (the arm's UNDECIDABLE) |
| 12 | Use the C-quoting `--name-only` output (drop `-z`) in the arm | T18i RED |
| 13 | Run the untracked listing from the cwd instead of `git -C "$_top"` | T18g (subdirectory sub-row) RED |
| 14 | Let the section run to the next heading (drop the blank-line and non-bullet boundaries) | T18m RED |

**Harness rows.** (H1) Edit the SUITE: change T18d's expected value to OWED; the suite must go RED; the raised `print_results` floor makes a deleted T18 block RED. (H2) Must-PASS inputs that are NOT the canonical line: T18o (markup characters, a control character, a boundary-marked 300-byte string) and T18d (token last among other bullets) differ from a bare canonical `- ci-is-the-gate: x` in ways the contract permits; RED rows alone cannot see a guard that rejects everything - T18a-d, T18n, T18o and T18p are the must-PASS side and T18e-T18m the reject side.

**Anchor.** The stored value is a token in a file the same commit can write. What lives OUTSIDE the commit and bounds a planted or wrong token is the live branch ruleset (required `test` context, merge queue) - the local battery was never merge authority - plus the arm's infra refusal, which keeps the local infra shard (scoped to `test-all.sh`'s two `_infra_in_diff` prefixes). The verdict line prints the verbatim words into the transcript and the PR Test plan, so a planted token is visible. The guard proves consistency of the skip with the operator's stated words, not integrity of the words; that is the CTO-accepted trade (F3).

### Guard 2 - writer/reader parity (one-shot reference vs gate)

**Property.** The heading and token strings one-shot is told to write are exactly the strings `battery-owed.sh` reads.

**Assembly.** Two artifacts that must agree: `one-shot/references/operator-constraints.md` (the writer contract, an LLM follows it) and `battery-owed.sh` (the reader). `one-shot/SKILL.md` reachability is enforced elsewhere (`components.test.ts` requires every `references/*.md` to be named by basename). A rename in only one of the two is the defect, and a presence grep of the script cannot see it (the script's own header comment would satisfy it), so T18p runs the real gate on strings derived from the reference.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Rename the token to `ci-gate` in the script's awk only | T18p RED |
| 2 | Rename the section heading in the reference's fenced example only | T18p RED |
| 3 | Remove the fenced example section from the reference (nothing to derive from) | T18p RED (empty fixture, the gate returns OWED not 42) |

## User-Brand Impact

- **If this lands broken, the user experiences:** a lifecycle skill that either skips a local test run the operator did not waive (a red only CI catches later) or keeps running the 45-minute battery they told it to skip; neither reaches an end user of a product.
- **If this leaks, the user's workflow is exposed via:** nothing new; the token's words (operator's own brief text) are echoed into a transcript and PR body the operator already controls.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** `none`, not `aggregate pattern`, because the skip drops only the local run while CI's required `test` check and the merge queue still gate every merge, and the local infra shard (the two `_infra_in_diff` prefixes) is refused by the arm. No touched path matches the preflight sensitive-path regex (checked for all seven planned paths).

## Domain Review

**Domains relevant:** none

No cross-domain implications detected - internal workflow-tooling change (two lifecycle skills, one gate script, tests, one ADR amendment). No user-facing UI, no regulated data, no new infrastructure, no encryption surface.

## Observability

Plan Phase 2.9 alone would skip this (the gate script lives under `plugins/soleur/skills/ship/scripts/`, not `plugins/*/scripts/`), but deepen-plan Phase 4.7 treats any non-docs Files-to-Edit as in scope, so the block is declared. There is no server or runtime surface: the "service" is a skill-run gate script, and its signal is the one verdict line it prints.

```yaml
liveness_signal:
  what: the `battery-owed:` verdict line (SKIPPABLE / OWED / UNDECIDABLE) printed on every ship Phase 4 run; the token case prints `operator ci-is-the-gate ("<words>")`
  cadence: per ship Phase 4 run (first run and each re-run)
  alert_target: the operator's transcript and the PR Test plan line
  configured_in: plugins/soleur/skills/ship/scripts/battery-owed.sh
error_reporting:
  destination: stdout of battery-owed.sh, read by the ship Phase 4 dispatch block
  fail_loud: any status other than 42 runs the affected gate (OWED, UNDECIDABLE rc 2, or a shell abort), so a broken arm falls back to today's behaviour and never to a silent skip
failure_modes:
  - mode: a planted or wrong token skips the local battery
    detection: the verdict line prints the verbatim words; CI's required test context still gates the merge
    alert_route: PR Test plan line plus the required-check result
  - mode: infra path in the diff (committed, staged or untracked) while a token is set
    detection: the arm refuses with `the diff touches the infra surface` (rc 0, OWED)
    alert_route: transcript, local battery runs
  - mode: origin/main unresolvable, git diff failure or grep error while a token is set
    detection: UNDECIDABLE rc 2 with the `operator ci-is-the-gate set but` prefix
    alert_route: transcript, local battery runs
logs:
  where: PR body Test plan and the session transcript
  retention: lifetime of the PR
discoverability_test:
  command: grep -om1 ci-is-the-gate plugins/soleur/skills/ship/scripts/battery-owed.sh
  expected_output: ci-is-the-gate
```

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Propagate a brief's stated constraints from soleur:one-shot to soleur:ship so ship honours them" | One-shot O1 + new reference + `battery-owed.sh` token arm | mapped |
| 2 | "edit plugins/soleur one-shot, ship and battery-owed.sh so the brief's constraints (e.g. \"rely on CI's required test check; do not run the local affected battery to completion\") reach ship and ship skips the local battery accordingly" | `battery-owed.sh` token arm, ship S1-S4, one-shot O1 | mapped |
| 3 | "net bytes must not grow" | S1-S4 / O1-O2 measured -146 B / -3 B; budget JSON untouched | mapped |
| 4 | "send technical forks to the CTO agent ... never to the operator" | `decision-challenges.md` F1-F14 | mapped |
| 5 | "In the PR body reference the learning file; use `Ref #N`, never `Closes #N`" | Phase 5 PR body task | mapped |
| 6 | "Rely on CI's required checks ... read infra-validation and sandbox-canary-capture-gate by hand; do not run the local affected battery to completion" | Phase 5 (targeted single-suite runs only; PR Test plan records the unrun battery) | mapped |
| 7 | "Never push to a PR in the merge queue, never --admin merge, never touch the ruleset. Check a push's real exit code ..." | Phase 5 push rules | mapped |
| 8 | "Registry rows go in sorted position (scripts/ci-pr-affected-audit.accept.tsv, suite-durations.tsv, suite-shard-legs.tsv)" | No new suite file is created, so no registry row is needed; stated in Phase 4 so the implementer does not invent one (a new suite would require the rows in sorted position) | mapped |
| 9 | "Do not touch apps/web-platform/test/claude-pin-lockstep.test.ts. Leave the stale-accept row for real-sdk-ask-probe-workflow.test.sh alone." | Not in Files to Edit; restated in Phase 5 | mapped |
| 10 | "keep your SKILL.md edits minimal and net-negative/zero in bytes so a merge-order conflict is trivial; do not touch that PR [12187]" | S1-S4 are four small hunks, net -146 B; no edit to PR 12187 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `battery-owed.sh` token arm | "ship skips the local battery accordingly" | asked |
| New `operator-constraints.md` | "The design is recorded in the learning file ... (Session Error #3)" ("detail in a new `one-shot/references/operator-constraints.md`" is that design) | asked |
| T18 test rows + floor raise | "new rows in `ship-battery-owed.test.sh`" (learning, Session Error #3) | asked |
| `scripts/lib/test-affected-paths.sh` edge | "Registry rows go in sorted position" (the declared-edge array is the suite's coverage registry) | inferred - justification: the suite starts reading one new file (the reference, parity row T18p), and an undeclared read silently stops selecting it |
| ADR-242 amendment | - | inferred - justification: CTO F8; ADR-242 defines 42 as "CI verified this tree", which would be false otherwise |
| Stand-down guards on conditions 1 and 2 | "unless `--full` or an infra/unresolved diff" (learning: conditions 1 and 2 are not on that list, so the token must bypass them) | asked |
| Issue #12247 (work/review follow-up) | - | inferred - justification: CTO F7 and the plan skill's deferral-tracking rule |

### Split Assessment

- Subsystems touched: 3 - `plugins/soleur/skills`, `plugins/soleur/test` (+ `scripts/lib`), `knowledge-base/engineering/architecture`
- Planned files: 8 edited, 1 created | Estimated changed lines: ~130 (script ~35, tests ~70, reference ~25, SKILL.md/ADR small)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Files to Edit

- `plugins/soleur/skills/ship/scripts/battery-owed.sh` - token read, two stand-down guards, the arm, three undecidable-message prefixes, header contract.
- `plugins/soleur/skills/ship/SKILL.md` - S1-S4 only (net -146 B).
- `plugins/soleur/skills/one-shot/SKILL.md` - O1-O2 only (net -3 B).
- `plugins/soleur/test/ship-battery-owed.test.sh` - T18 block, raised `print_results` floor.
- `scripts/lib/test-affected-paths.sh` - one declared edge (`plugins/soleur/skills/one-shot/references/operator-constraints.md`) in the `SHIP_BATTERY_OWED_TEST_SH` array, sorted position inside the array.
- `knowledge-base/engineering/architecture/decisions/ADR-242-the-local-gate-defaults-to-affected-suites-and-always-on-ratchets.md` - Amendment + `amended_by` line.
- `knowledge-base/engineering/architecture/decisions/ADR-183-full-suite-runs-at-ship-not-at-implementation-exit.md` - pointer-only amendment.
- `knowledge-base/engineering/architecture/decisions/ADR-276-demand-first-hosted-runner-budget-merge-group-is-the-full-battery-authority.md` - one-line pointer-only amendment (only if the ADR lint allows it).
- `plugins/soleur/test/fixture-relative-assert.baseline.txt` - only if the new rows move the count (regenerate, never hand-edit).

## Files to Create

- `plugins/soleur/skills/one-shot/references/operator-constraints.md`.

Not touched: `plugins/soleur/test/skill-body-budget.json` (ceilings only move down; no move needed), `scripts/ci-pr-affected-audit.accept.tsv`, `scripts/suite-durations.tsv`, `scripts/suite-shard-legs.tsv` (no new suite; if one is ever added the rows go in sorted position), `apps/web-platform/test/claude-pin-lockstep.test.ts`, the stale-accept row for `real-sdk-ask-probe-workflow.test.sh`, the rulesets, PR 12187.

## Implementation Phases

### Phase 1 - RED (tests first, `cq-write-failing-tests-before`)

1.1 Add T18a-T18p, the `assert_not_reason` and `parity_rc` helpers, and the `mut18` helper with mutants T18q-s to `ship-battery-owed.test.sh`. 1.2 Run ONLY that suite (`bash plugins/soleur/test/ship-battery-owed.test.sh`, about 20 s; one suite is not the battery) and confirm the new rows are RED for the right reason (T18a returns 2, T18b-d return OWED, T18p has no reference to derive from; the arm rows return OWED/2 because no arm exists).

### Phase 2 - GREEN

2.1 `battery-owed.sh`: token read, the two stand-down guards, the arm, the three message prefixes, the header. 2.2 Create `operator-constraints.md`. 2.3 Apply S1-S4 and O1-O2; run `wc -c` on both files and `python3 scripts/lint-skill-body-budget.py --base origin/main`; reconcile the byte figures in this plan and in `decision-challenges.md` (P1) with the measured ones. 2.4 Re-run the single suite until green; derive the exact `print_results` floor from the green run and set it; run mutation rows 4-14 of Guard 1 once by hand on a copy of the gate (not committed). 2.5 The declared edge in `test-affected-paths.sh`.

### Phase 3 - Document

3.1 ADR-242 amendment through `soleur:architecture`. 3.2 `bash plugins/soleur/test/c4-count-parity.test.sh` for the no-C4-impact conclusion.

### Phase 4 - Targeted checks (single suites, never the whole battery)

`python3 scripts/lint-skill-body-budget.py --base origin/main`; `bash scripts/lint-orphan-test-suites.sh`; `bash plugins/soleur/test/fixture-relative-assert.test.sh`; `bun test plugins/soleur/test/components.test.ts plugins/soleur/test/plan-skeleton-checkpoint.test.ts plugins/soleur/test/fullsuite-merge-gate.test.ts` run from the repo root; and the sibling single suites whose declared edges include files this PR edits (`ship/SKILL.md`, `test-affected-paths.sh`, `one-shot/SKILL.md`): `bash plugins/soleur/test/ship-battery-refusal-wait.test.sh`, `bash plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh`, `bash plugins/soleur/test/ship-prepush-secret-scan.test.sh`, `bash plugins/soleur/test/concurrent-ship.test.sh`. Each is one suite, not the battery; any other suite CI's required `test` runs is left to CI. Registry TSVs are not edited (no new suite).

### Smoke test of the arm on this branch (devex review #4, taste)

Once Phase 2 is green, add a hand-written `- ci-is-the-gate: <the brief's own words>` bullet under `## Operator Constraints` in this branch's `specs/feat-one-shot-brief-constraints-reach-ship/session-state.md` (create the file and section if one-shot has not), run `bash plugins/soleur/skills/ship/scripts/battery-owed.sh`, and paste the real verdict line into the PR Test plan. This exercises the arm end to end on a diff with no infra path, and the planted-by-hand token is visibly the operator's.

### Phase 5 - Ship under the same constraint this PR implements

The brief that produced this plan says: rely on CI's required checks (`test`, `lockfile-sync`, `markdown-lint`, `tenant-integration-required`), read `infra-validation` and `sandbox-canary-capture-gate` by hand, do not run the local affected battery to completion. This PR is not self-hosting (its own one-shot run predates the token), so per the learning's interim rule the implementer skips ship Phase 4's local gate by hand and records in the PR Test plan: `Local battery NOT executed per operator constraint; CI "test" is the gate.`, the brief's constraint words verbatim, the smoke-test verdict line, the targeted single-suite runs from Phase 4, and that the diff touches none of `apps/web-platform/infra/` or `.github/workflows/apply-web-platform-infra.yml` (`git diff --name-only origin/main...HEAD`). "Read by hand" for `infra-validation` and `sandbox-canary-capture-gate` means the `gh pr checks 12246` row for each, quoted in the Test plan. Do not touch `apps/web-platform/test/claude-pin-lockstep.test.ts` and leave the stale-accept row for `real-sdk-ask-probe-workflow.test.sh` alone. PR body: reference the learning file `knowledge-base/project/learnings/2026-11-06-a-cleanup-brief-with-three-items-had-two-already-resolved-on-main.md`; use `Ref #12247` / `Ref #12246`, never `Closes`. Push rules: `cd` into the worktree before git writes; `git add` and `git commit` in separate calls; check a push's real exit code (no `| tail`); never push to a PR in the merge queue; never `--admin` merge; never touch the ruleset; no `rm -rf` inside the worktree; no bare pipe into `grep -q`.

## Acceptance Criteria

<!-- founder-stated check: see plan-founder-check.md -->

- [ ] AC1 `battery-owed.sh` returns 42 when the token is the only reason (each condition isolated: T18a condition 4, T18b condition 2, T18c condition 1) and for the incident shape with all of them at once (T18d).
- [ ] AC2 It returns 0 with the arm's own infra reason for a token plus an infra path - committed (T18e, T18f), untracked or unstaged-modified, from the repo root and from a subdirectory (T18g), renamed in (T18h), or C-quoted (non-ASCII, tab; T18i) - and 2 with the `operator ci-is-the-gate set but` prefix for an unresolvable `origin/main` (T18i); a corrupted `INFRA_RE` (rc 2) does not skip (Guard 1 row 11, by hand).
- [ ] AC3 With no token, a token in the wrong section or branch, empty/two-space/control-only words, a brief line written as `- constraint: ci-is-the-gate: x`, or a token only in a second section, behaviour is exactly today's, asserted by the fall-through reason AND the absence of `operator ci-is-the-gate` from the verdict line (T18j-n); all pre-existing T1-T17 rows still pass.
- [ ] AC4 The Phase 4 dispatch block still tests `FULL_BATTERY` before `battery-owed.sh` (existing T16a-d, unchanged).
- [ ] AC5 Against the merge base, neither lifecycle skill grew: `[ "$(wc -c < plugins/soleur/skills/ship/SKILL.md)" -le "$(git show "$(git merge-base origin/main HEAD)":plugins/soleur/skills/ship/SKILL.md | wc -c)" ]` and the same for `one-shot` (merge-base form, because PR #12187 also edits `ship/SKILL.md`); `python3 scripts/lint-skill-body-budget.py --base origin/main` exits 0; `git diff --quiet origin/main...HEAD -- plugins/soleur/test/skill-body-budget.json` exits 0.
- [ ] AC6 `operator-constraints.md` exists and is named by basename in `one-shot/SKILL.md` (`components.test.ts` reachability); the real gate returns 42 on a session-state built from the heading and token line taken from the reference's fenced example (T18p).
- [ ] AC7 The three committed mutants (T18q-s) go RED against a copy of the gate and the real gate stays green; the `print_results` floor equals the green run's count; Guard 1 rows 4-14 were run once by hand and the results are in the PR Test plan.
- [ ] AC8 `grep -c '^## Amendment — 2026-11-06 (#12246)$'` prints 1 for ADR-242 (listing the four skip channels and the ADR-276 qualification) and a pointer amendment exists in ADR-183 (and in ADR-276 if the lint allows); `git diff --quiet origin/main...HEAD -- knowledge-base/engineering/architecture/diagrams` exits 0 and `bash plugins/soleur/test/c4-count-parity.test.sh` is green.
- [ ] AC9 `bash plugins/soleur/skills/ship/scripts/technical-ruling-gate.sh --branch` exits 0 (the F1-F14 and PR rows are classified) and `gh issue view 12247 --json state --jq .state` prints `OPEN`.
- [ ] AC10 `gh pr checks 12246 --required` exits 0 on the final head (every context in the live required set, which is larger than the four the brief names: `test`, `lockfile-sync`, `markdown-lint`, `tenant-integration-required`); the `infra-validation` and `sandbox-canary-capture-gate` rows were read by hand and quoted; the PR Test plan records the unrun local battery.
- [ ] AC11 Diff scope: `git diff --name-only origin/main...HEAD` is a subset of the 7 edited files, the 1 created file, `knowledge-base/project/plans/2026-11-06-feat-propagate-brief-constraints-to-ship-plan.md`, `knowledge-base/project/specs/feat-one-shot-brief-constraints-reach-ship/**` and `knowledge-base/project/learnings/**` (the pipeline-written set); and `git diff --quiet origin/main...HEAD -- scripts/ci-pr-affected-audit.accept.tsv scripts/suite-durations.tsv scripts/suite-shard-legs.tsv apps/web-platform/test/claude-pin-lockstep.test.ts` exits 0.

## Test Scenarios

- Given a brief with "rely on CI's required test check" and a branch behind main with no CI, when ship Phase 4 runs `battery-owed.sh`, then it exits 42 and prints the operator's words (unit/integration - shell fixture repo with a `gh` stub that would fail if consulted).
- Given the same token and a diff touching `apps/web-platform/infra/`, when the gate runs, then OWED (integration).
- Given a brief that is silent on the battery, when one-shot writes `## Operator Constraints`, then it contains the constraint bullets (as `- constraint: ...`) and NO `ci-is-the-gate` line (documented behaviour in the reference; the LLM write itself is not unit-testable - residual risk accepted by CTO F5; T18p pins that the strings the reference teaches are the strings the gate reads).
- Given `/ship --full` and a token, when Phase 4 runs, then the full battery runs (existing T16a-d pin the dispatch order).
- Given a token planted in a PR diff, when the gate runs on a non-infra diff, then it skips only the local battery and prints the planted words (T18i shows the printing path; merge authority is CI).

## Dependencies & Risks

- **Merge-order with PR #12187** (edits `ship/SKILL.md`, `scripts/lib/test-affected-paths.sh`, the two duration/shard TSVs and `fixture-relative-assert.baseline.txt`): S1-S4 are four small hunks in the Phase 4 region and the checklist line, 12187's content is the legal-acceptance hold gate elsewhere; the `test-affected-paths.sh` hunk is one entry in a different array; the baseline file is touched here only if the count moves. Net -146 B here only widens ship's headroom for 12187.
- **LLM-judged trigger** (F5): a missed token is today's behaviour; a spurious token is bounded by CI. Mitigation: phrase list + "when in doubt, no token" + verbatim words printed.
- **Prose compression** can drop a condition (2026-09-23 learning): every trimmed clause was classified as rationale; the implementer diffs the clauses after editing.
- **Editing `test-affected-paths.sh`** degrades a local affected run to full: accepted, and the reason local batteries are not run to completion here.
- **Dirty-tree skip** is by design (F2, F11a): the untracked `session-state.md` makes the first run dirty by construction.
- **Token lifetime** ends at ship Phase 6.45 archival (F12 rule A); a later re-run uses the existing CI-evidence path.
- **Resumed one-shot runs** rewrite `session-state.md` with the whole-file template; the reference tells the writer to save and restore the section (kept-line echo), so a resumed run with an empty brief keeps the earlier token instead of silently losing operator intent (architecture pass #1).
- **Pre-existing blind spot, not fixed here:** the non-token infra check in `battery-owed.sh` reads C-quoted paths (tracked as #12251, `Ref #12246`); the new arm does not inherit it.
- **Byte margins:** one-shot has only -3 B of margin; if the implementer's measurement disagrees, trim more rationale from the same Step 0a.5 paragraph, never a condition.

## References

- Learning: `knowledge-base/project/learnings/2026-11-06-a-cleanup-brief-with-three-items-had-two-already-resolved-on-main.md` (Session Error #3).
- Archived ruling D7: `knowledge-base/project/specs/archive/20261106-100947-feat-one-shot-bun-pair-ratchet-accept-cleanup/decision-challenges.md`.
- This run's rulings: `knowledge-base/project/specs/feat-one-shot-brief-constraints-reach-ship/decision-challenges.md`.
- Gate and caller: `plugins/soleur/skills/ship/scripts/battery-owed.sh`, `plugins/soleur/skills/ship/SKILL.md` Phase 4; suite `plugins/soleur/test/ship-battery-owed.test.sh`.
- ADR-242, ADR-183, ADR-276; #8247, #8322, #6480; PR #12246 (this), PR #12187 (neighbour), issue #12247 (deferral).
