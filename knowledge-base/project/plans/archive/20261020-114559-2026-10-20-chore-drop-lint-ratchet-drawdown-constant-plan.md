---
title: "chore(quality): drop the drawdown header and DRAWDOWN constant from lint-ratchet.py once both baselines are empty"
date: 2026-10-20
slug: chore-drop-lint-ratchet-drawdown-constant
branch: feat-one-shot-10583-drop-drawdown-constant
issue: 10583
closes: 10583
type: chore
lane: single-domain
---

# chore(quality): drop the drawdown constant and header from lint-ratchet

## Enhancement Summary

**Deepened on:** 2026-10-20
**Scope of the pass:** proportionate to a one-engine-file, deletion-class change. The full agent fan-out was replaced by the mechanical halt gates, direct verification of every claim against the repo, and the earlier simplicity review plus CTO ruling. No external library, vendor or infrastructure surface is involved, so no framework-docs or best-practices research was spawned.

### Key Improvements

1. Halt gates 4.6 (user-brand impact, threshold `none` with scope-out), 4.7 (observability, probe passes the verb gate), 4.8 (no PAT shapes), 4.11 (`lint-guard-contract.py` green, one entry), 4.12 (one unfenced Scope Check, no BLOCKED marker) all pass. 4.9, 4.10 and 4.55 do not trigger (no UI surface, no store or connection, no downtime class).
2. Verified that the default `recovery` of `render_baseline` equals what `update()` passes for the Soleur scopes: `_recovery(config)` returns `python3 <SCRIPT_REL> <name>` when `recovery_cmd` is unset, and the Soleur `SCOPES` entries set neither `recovery_cmd` nor `header_recovery`. This is what lets the parity test call `render_baseline(name, [])` without building a config.
3. Verified `USER_SCOPES` is a module constant defined before any `render_baseline` call, and that no other `config["drawdown"]` reader exists (only `update()`).
4. The observability probe was changed from running `--check` to a header grep after reasoning about preflight Check 10's sandbox (tmpfs `HOME`, 15-second cap).

### New Considerations Discovered

- Every cited issue, ADR and learning path resolves (`kb paths` sweep found no broken path; the only rule id cited, `cq-write-failing-tests-before`, is active in AGENTS.md).
- The probe command was run through `probe-verb-gate.sh` (rc 0) and its planned output was checked against the planned header text (one matching line).
- Residual risk accepted: a scope added to `SCOPES` later is not covered by the parity test (recorded in the Guard Contract Assembly).

## Overview

Both Soleur lint-ratchet baselines (`scripts/lint-ratchet-ruff.baseline.txt`, `scripts/lint-ratchet-eslint-test-dirs.baseline.txt`) hold no entries, and the tracker the engine names as their drawdown (#10433) is closed. Three things are now dead weight: the `DRAWDOWN = "#10433"` constant in `plugins/soleur/scripts/lint-ratchet.py`, the `drawdown` scope-config key that threads it to `render_baseline`, and the `# Drawdown tracking: #10433` line (plus the provenance wording around it) in the two baseline headers.

One non-obvious coupling shapes the work: `render_baseline` uses `drawdown is None` as its switch between the user-repo baseline form and the Soleur-repo form. Dropping the parameter therefore needs a new switch, not just a deleted line (Research Insights, finding 1).

PR body must carry `Closes #10583` and a non-closing epic reference line (the word Ref, a hash sign and the digits 10331, no closing keyword next to it). #10331 is closed and stays closed.

## Research Insights

**Premise Validation.** #10583 is OPEN with no closing PR. #10433 is CLOSED (the re-evaluation criterion in #10583 is met). #10331 is CLOSED (epic reference only). On `origin/main` the cited symbols exist where the brief says: `DRAWDOWN` at line 93, `drawdown=DRAWDOWN` at line 1447, both baselines are 8 comment lines and zero entries. Both `--check` commands pass on the current tree (`ruff`: `OK (0 findings baselined, 68 files scanned)`). No external premises were stale. The ADR corpus check found ADR-290 only; it does not reject the mechanism (Amendment 2 explicitly defers this exact removal to #10583).

**Property List.**

1. The engine carries no drawdown constant, scope-config key or parameter.
2. The two committed Soleur baselines carry no drawdown text and no tracker or PR provenance, hold zero entries, and still parse.
3. `lint-ratchet.py ruff --check` and `eslint-test-dirs --check` pass.
4. No test or doc pins the removed header text or constant.
5. The user-repo baseline form (`user-ruff`) is byte-identical to before.

**Cut List.** No mechanism beyond the ask is introduced except the CTO-ruled parity test (property 2). Cut: a `--rebaseline` or header-migration flag (the only existing baselines are regenerated once with `--update`); a version marker in the header (nothing reads the header); renaming `scripts/lint-ratchet-*.baseline.txt` (paths are pinned by lefthook globs and tests); touching the user-form header (property 5). No mechanism on `origin/main` covers property 2: `parse_baseline` skips comment lines and `check()` compares entries only, so header text is currently unguarded (grep of `tests/scripts/test_lint_ratchet.py` found no test reading the committed Soleur baselines).

**Findings.**

1. `render_baseline(name, entries, drawdown, recovery=None, header=None)` at `plugins/soleur/scripts/lint-ratchet.py` ~line 298 branches on `drawdown is None` for the user form. `build_user_config` passes `"drawdown": None`; `build_config` passes `drawdown=DRAWDOWN`; the only production caller is `update()` (~line 848).
2. `parse_baseline` ignores blank and `#` lines, so any comment header (or none) is parser-valid; `check()` compares entries, never header text.
3. The suite is `tests/scripts/test_lint_ratchet.py` (not under `plugins/soleur/test`). Sites to change: `make_config` (`"drawdown": "#1"`, line ~162); `render_baseline("fixture"|"ruff", ..., "#1"|"#10433")` at lines ~286, 291, 465, 528, 605, 663, 739, 2334, 2341, 3411; user-form calls with `None, None` at lines ~1880, 2034, 2217, 2229, 2427, 2669, 2980; `test_the_drawdown_reference_is_one_constant` (~1197); `mock.patch.object(lr, "DRAWDOWN", "POISON")` at lines ~2156 and ~2957 (these raise `AttributeError` once the constant is gone); exact-text pins at ~2341-2343 and ~3411-3419; `test_rendered_header_documents_the_recovery_path` asserts `"#1"` (~line 295).
4. Docs: ADR-290 names `drawdown` among scope-config keys in the "PR3b contract" paragraph and ends Amendment 2 with "tracked in #10583". The module docstring (~line 42) lists the key. Other repo hits for "drawdown" are unrelated: `plugins/soleur/skills/work/SKILL.md` and `scripts/lint-shell-trace-credential-refusal*` (a different baseline, never edited here; SKILL.md is at its byte ceiling), `model.c4` (a different drawdown, #7898), generic prose in `plan-sharp-edges.md`, an audit file and learnings (history), and archived specs and plans.
5. Open code-review issues touching the files this plan edits: none (queried `gh issue list --label code-review`).

**Institutional learnings applied.** `2026-10-19-a-per-area-drawdown-cannot-satisfy-a-live-census-gate-and-reindenting-breaks-text-anchored-mutants.md`: the baseline must equal the live census of the working tree, so the engine edit, the test edits and the regenerated baselines land in one commit; run ratchet commands from the worktree (a bare-root run prints a misleading `git diff failed`); run `technical-ruling-gate.sh` on the decision file before handing back. The same learning's re-indent warning does not apply (no indentation changes).

## Technical Rulings

Persisted in `knowledge-base/project/specs/feat-one-shot-10583-drop-drawdown-constant/decision-challenges.md`.

- Ruled by CTO agent, 2026-10-20: user-vs-Soleur form switch is `name in USER_SCOPES` (F1). Amended at review the same day: the switch is `name == "user-ruff"` (`auto` never renders); see `decision-challenges.md`.
- Ruled by CTO agent, 2026-10-20: Soleur header becomes a short zero-findings-gate header keeping the `--list`/`--update`/merge-conflict lines, no tracker or PR3a provenance; baselines regenerated with `--update`; a parity test is added (F2).
- Ruled by CTO agent, 2026-10-20: ADR-290 contract sentence edited in place plus a short Amendment 3; Amendment 2 untouched (F3).

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "remove the DRAWDOWN constant (about line 93, currently `DRAWDOWN = \"#10433\"`, also used at about line 1447 as `drawdown=DRAWDOWN`) and its uses" [brief] | Phase 1 (engine edits 1-5) | mapped |
| 2 | "remove the baseline header lines (the `# lint-ratchet baseline ...`, `# Shrink-only ...` comment header; decide with care what stays so the files remain valid for the ratchet parser)" [brief] | Phase 1 (new Soleur header) + Phase 2 (regenerate baselines) | mapped |
| 3 | "Both baselines must stay empty (no entries)." [brief] | Phase 2 + parity test (zero-entry assertion) | mapped |
| 4 | "run `python3 plugins/soleur/scripts/lint-ratchet.py ruff --check` and `python3 plugins/soleur/scripts/lint-ratchet.py eslint-test-dirs --check`; both must pass" [brief] | Phase 3 + AC3 | mapped |
| 5 | "Update any tests/docs that reference the drawdown header or the DRAWDOWN constant (grep the repo, including ADR-290 and tests under plugins/soleur/test)" [brief] | Phase 1 test edits + Phase 4 ADR-290 (grep found no match under plugins/soleur/test; the suite is tests/scripts/test_lint_ratchet.py) | mapped |
| 6 | "PR body: \"Closes #10583\", plus a non-closing epic reference line" [brief] | Phase 5 (ship) | mapped |
| 7 | "Do not edit plugins/soleur/skills/work/SKILL.md (at its byte ceiling)." [brief] | Non-goals; AC7 | mapped |
| 8 | "Run soleur:ship and soleur:postmerge to completion; if the PR is BEHIND with auto-merge armed, wait for the merge queue" [brief] | Phase 5 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `plugins/soleur/scripts/lint-ratchet.py` (constant, key, parameter, header) | "remove the DRAWDOWN constant ... and its uses" | asked |
| `scripts/lint-ratchet-ruff.baseline.txt` | "remove the baseline header lines" | asked |
| `scripts/lint-ratchet-eslint-test-dirs.baseline.txt` | "remove the baseline header lines" | asked |
| `tests/scripts/test_lint_ratchet.py` (re-pin, drop poison patches) | "Update any tests/docs that reference the drawdown header or the DRAWDOWN constant" | asked |
| `knowledge-base/engineering/architecture/decisions/ADR-290-shrink-only-lint-ratchet-keyed-on-file-rule-anchor.md` | "including ADR-290" | asked |
| `name == "user-ruff"` switch and keyword-only `recovery`/`header` | — | inferred — justification: removing the `drawdown` parameter deletes the only thing `render_baseline` branched on, and the user form must stay byte-identical (a user repo's committed baseline would otherwise churn); keyword-only turns a missed positional call site into a TypeError instead of a silent mis-bind |
| Baseline parity test (zero entries, header equals rendered form) | "decide with care what stays so the files remain valid for the ratchet parser" | asked (CTO F2: the test is what keeps the regenerated headers and the renderer from drifting; the parser cannot see header text) |
| Decision file `decision-challenges.md` | — | inferred — justification: the pipeline's technical-ruling contract requires every CTO ruling to be persisted as a table row |

### Split Assessment

- Subsystems touched: 4 — `plugins/soleur`, `tests`, `scripts`, `knowledge-base`
- Planned files: 6 edited (+ plan, tasks, decision file) | Estimated changed lines: ~110
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — the subsystem-root count is over the threshold only because the change is a rename-class edit: the engine renderer, the suite that pins it, the baselines it regenerates and the ADR that documents its contract cannot be split without leaving the committed baselines disagreeing with the renderer (the new parity test and `--update` would go red between the two PRs).

## Files to Edit

- `plugins/soleur/scripts/lint-ratchet.py`
- `tests/scripts/test_lint_ratchet.py`
- `scripts/lint-ratchet-ruff.baseline.txt` (regenerated via `--update`)
- `scripts/lint-ratchet-eslint-test-dirs.baseline.txt` (regenerated via `--update`)
- `knowledge-base/engineering/architecture/decisions/ADR-290-shrink-only-lint-ratchet-keyed-on-file-rule-anchor.md`

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-10583-drop-drawdown-constant/tasks.md`
- `knowledge-base/project/specs/feat-one-shot-10583-drop-drawdown-constant/decision-challenges.md` (already written)

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` bodies were searched for each path above; no match.

## User-Brand Impact

- **If this lands broken, the user experiences:** a Soleur contributor's `lefthook` ratchet hook or the `scripts/lint-ratchet-ruff-live` CI suite fails on a header mismatch or a `TypeError` from `--update`; a user-repo adopter's `.lint-ratchet/ruff.baseline.txt` would churn on the next `--update` if the user form changed (the byte-pin test prevents this).
- **If this leaks, the user's data / workflow is exposed via:** nothing; no secret, credential, auth or data path is read or written, and the baseline files hold no source text (anchors are hashes).
- **Brand-survival threshold:** none
- **Threshold decision (challengeable):** `none` because the diff removes a cosmetic constant and comment lines and changes no verdict of the ratchet; the next tier would apply only to a change in what the ratchet accepts or rejects.

threshold: none, reason: `plugins/soleur/scripts/lint-ratchet.py` is a shipped script, but this change touches only the baseline header renderer and the config key that fed it, and the user-form output is pinned byte-identical by a test.

## Implementation Phases

Order follows `cq-write-failing-tests-before`: tests first, then the engine, then regeneration, then docs. All edits land in ONE commit because the gate compares the baselines to the live working tree.

### Phase 0 — Setup (verify the starting state)

- From the worktree: `python3 plugins/soleur/scripts/lint-ratchet.py ruff --check` and `eslint-test-dirs --check` pass; `python3 -m unittest tests.scripts.test_lint_ratchet` is green. Record the passing test count (N).

### Phase 1 — Tests first, then the engine

Tests (`tests/scripts/test_lint_ratchet.py`):

1. Delete `"drawdown": "#1"` from `make_config`.
2. Re-shape every `render_baseline` call to the new signature `render_baseline(name, entries, *, recovery=None, header=None)`: drop the `"#1"` third argument from the `"fixture"` and `"ruff"` calls; drop both `None, None` positionals from the `"user-ruff"` calls and pass `header=` by keyword (`recovery=None` is the default).
3. Delete `test_the_drawdown_reference_is_one_constant`; remove `mock.patch.object(lr, "DRAWDOWN", "POISON")` from the two user-scope tests (keep the `SCOPES` patch that proves the user scopes ignore the Soleur tables; the ~2156 patch sits in a backslash-continued `with` chain, so re-join the continuation after removing the middle item).
4. Rewrite the three exact-text pins: `test_rendered_header_documents_the_recovery_path` (drop the `"#1"` assertion; assert `"--update"`, `"--list"`, `"conflict"`); the ~2341 pin (assert the new first line and that `"Drawdown"` and `"PR3a"` are absent); the ~3411 pin (exact text of the new Soleur header plus one entry).
5. Add `test_the_user_form_is_byte_identical` (CTO F1): assert `render_baseline("user-ruff", [])` equals the exact pre-change user-form text, captured from `origin/main` with a one-off `python3 -c` BEFORE the engine edit (the user branch lines themselves are not edited; this pins the new switch).
6. Add `test_the_committed_soleur_baselines_equal_the_rendered_empty_form` (CTO F2): for the two named scopes `("ruff", "eslint-test-dirs")`, assert the committed file text equals `lr.render_baseline(name, [])`. Byte equality covers both zero entries and header parity (the default `recovery` equals what `update()` writes for these scopes), so no helper, synthetic arm or negative pin is added; AC1's grep is the tombstone check.

Run the suite: the new and re-pinned tests must be RED against the unmodified engine (the `render_baseline` signature change makes most fail with `TypeError`).

Engine (`plugins/soleur/scripts/lint-ratchet.py`):

1. Docstring (~line 42): remove `drawdown,` from the scope-config key list.
2. Delete `DRAWDOWN = "#10433"` (line ~93).
3. `render_baseline`: signature `def render_baseline(name: str, entries: list, *, recovery=None, header=None) -> str`; replace `if drawdown is None:` with `if name == "user-ruff":` (the user branch text stays byte-identical; a comment says user baselines are machine-independent and carry no tracker reference). Replace the Soleur header with:

   ```text
   # lint-ratchet scope '<name>' is a zero-findings gate (design in ADR-290): fix findings, never baseline them.
   # List the live findings:  <recovery> --list
   # After fixing findings:   <recovery> --update  (it refuses to add)
   # After a merge conflict, take the base branch's copy of this file and re-run --update.
   ```

   The header must not name a rule code (an existing test pins that) and must not contain the words `Drawdown`, `Shrink-only`, `PR3a` or `#10331`.
4. `update()` (~line 848): `render_baseline(config["name"], entries, recovery=config.get("header_recovery") or _recovery(config), header=header)`.
5. `build_user_config`: delete `"drawdown": None`. `build_config` (~line 1447): drop `drawdown=DRAWDOWN`.
6. `grep -n "drawdown\|DRAWDOWN" plugins/soleur/scripts/lint-ratchet.py` returns nothing.

### Phase 2 — Regenerate the baselines

Run `python3 plugins/soleur/scripts/lint-ratchet.py ruff --update` and `... eslint-test-dirs --update` from the worktree. Each reports `wrote 0 entries`. `git diff` on the two baseline files shows only the header change (4 comment lines replacing 8). Do not hand-edit; if `--update` refuses, stop and investigate rather than editing around it.

### Phase 3 — Verify

- `python3 plugins/soleur/scripts/lint-ratchet.py ruff --check` and `eslint-test-dirs --check`: both exit 0.
- `python3 -m unittest tests.scripts.test_lint_ratchet`: green, with N minus 1 plus 2 tests (AC4).
- `bun test plugins/soleur/test/` is not needed; the vitest arm `apps/web-platform/test/eslint-test-dirs-ratchet.test.ts` shells the same `--check` and is covered by the line above.

### Phase 4 — ADR-290

Edit in place: in the "PR3b contract" paragraph delete `drawdown,` from the key list. Frontmatter: `amended: 2026-10-20`, `related: [10433, 10583]`. Append `## Amendment 3 (2026-10-20, #10583)` in three lines: the `DRAWDOWN` constant, the `drawdown` scope-config key and the `# Drawdown tracking` header line are removed; `render_baseline` now switches on `name == "user-ruff"`; the Soleur baseline header is a short zero-findings-gate header pinned to the committed files by a test. Amendment 2 is not edited and the amendment carries no tracker line (Amendment 2 already does).

### Phase 5 — Ship

Run `soleur:ship` then `soleur:postmerge` to completion. PR body: `Closes #10583` and the non-closing epic reference line (the word Ref, a hash sign and the digits 10331). Run `plugins/soleur/skills/ship/scripts/technical-ruling-gate.sh --branch` before marking ready. If the PR is BEHIND with auto-merge armed, arm the watch and wait for the merge queue; do not re-sync.

## Guard Contract

### Guard 1 — Soleur baseline parity test

**Property.** Each Soleur scope's committed baseline equals what `render_baseline` writes for an empty census, so it holds zero entries and its header is the renderer's, and `--update` on an unchanged tree produces no diff.

**Assembly.** Two named scopes, `ruff` and `eslint-test-dirs`, each read through `lr.SCOPES[name]["baseline"]` (a mistyped scope name or a moved path fails with `KeyError` or a missing file, never a green "0 checked"). The writer chokepoint is the Soleur branch of `render_baseline`, reached from one production call site (`update()`); the reader chokepoint is `parse_baseline`. The user branch is a separate member, pinned by the user-form byte-pin test (Phase 1 step 5), because this test does not reach user repos' `.lint-ratchet/ruff.baseline.txt`. A scope added to `SCOPES` later is not covered automatically; that is accepted for a cosmetic header and recorded here.

**Mutation matrix.**

| # | Edit | Expected |
|---|------|----------|
| 1 | Re-add `# Drawdown tracking: #1` to `scripts/lint-ratchet-ruff.baseline.txt` | parity test RED |
| 2 | With the ruff baseline compliant, add one four-field entry line (path, rule, anchor, n) to `scripts/lint-ratchet-eslint-test-dirs.baseline.txt` (a second member after a compliant first) | parity test RED |
| 3 | Change one word of the Soleur header string in `render_baseline` without regenerating the baselines | parity test RED |
| 4 | Own dispatch: change `SCOPES["ruff"]["baseline"]` to a path that does not exist | parity test RED (missing file), not a vacuous pass |
| 5 | Break the switch (`name == "user-ruff"` replaced by `False`) | user-form byte-pin test RED |

The property has no ordering or lifetime component, so no REORDER row applies.

**Harness rows.** Suite edit that must go RED: weaken the assertion to a bare `assertTrue(text)`; rows 1 and 3 above then stop reddening, which is what shows the real `assertEqual` is the thing driving them. Must-PASS input: the contract permits no byte difference from the rendered form (byte equality IS the contract), so the must-PASS input is the freshly `--update`d committed pair, which differs from the pre-change files in every header line.

**Anchor.** The committed file and the renderer can be edited by one diff, so the test proves consistency, not integrity; acceptable because the header is cosmetic. Integrity of the zero-entries property is carried independently by `check()`'s merge-base rule: an entry cannot be added without growth versus the merge base, which `--update` refuses and `--check` reports.

## Observability

Deletion-only scope: no new error path, log call, cron or infrastructure surface is introduced in `plugins/soleur/scripts/`; the only runtime-visible outputs are the existing ratchet verdict lines.

```yaml
liveness_signal:
  what: the ratchet verdict line printed by the scope check, "lint-ratchet(ruff): OK (0 findings baselined, ...)"
  cadence: every lefthook run touching the ratchet globs and every CI run of the scripts/lint-ratchet-ruff-live suite
  alert_target: a red required CI check on the PR (suite scripts/lint-ratchet-ruff-live and the vitest arm eslint-test-dirs-ratchet)
  configured_in: scripts/test-all.sh (run_suite lines) and lefthook.yml (ruff-ratchet, eslint-test-dirs-ratchet)
error_reporting:
  destination: the check's exit code and stderr, surfaced as a failed required CI check
  fail_loud: exit 1 on drift or vacuity, exit 2 on infrastructure error; never a silent pass
failure_modes:
  - mode: committed baseline header drifts from the renderer
    detection: the new parity test
    alert_route: tests.scripts.test_lint_ratchet red in CI
logs:
  where: CI job logs of the required test shards
  retention: GitHub Actions default retention
discoverability_test:
  command: grep -c -e 'zero-findings gate' scripts/lint-ratchet-ruff.baseline.txt
  expected_output: "1"
```

The probe reads the committed baseline header rather than running `--check`: preflight Check 10 runs probes in a sandbox with a tmpfs `HOME`, where the pinned ruff wheel is not cached and a `--check` run would try to fetch it inside the 15-second cap. `--check` itself is AC3 and the CI suite.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1: `grep -nEi "drawdown" plugins/soleur/scripts/lint-ratchet.py scripts/lint-ratchet-ruff.baseline.txt scripts/lint-ratchet-eslint-test-dirs.baseline.txt` prints nothing and exits 1.
- [ ] AC2: both committed baselines hold zero entries: `grep -vcE '^(#|[[:space:]]*$)' scripts/lint-ratchet-ruff.baseline.txt scripts/lint-ratchet-eslint-test-dirs.baseline.txt` prints `0` for each file; neither file contains the strings `Shrink-only`, `# lint-ratchet baseline`, `PR3a` or `#10331`.
- [ ] AC3: `python3 plugins/soleur/scripts/lint-ratchet.py ruff --check` and `python3 plugins/soleur/scripts/lint-ratchet.py eslint-test-dirs --check` both exit 0, run from the worktree, before the push.
- [ ] AC4: `python3 -m unittest tests.scripts.test_lint_ratchet` exits 0; the parity test and the user-form byte-pin test exist and were observed RED before the engine edit; the passing count is N (Phase 0) minus 1 (deleted `test_the_drawdown_reference_is_one_constant`) plus 2 (the two new tests).
- [ ] AC5: `git grep -n "DRAWDOWN" -- plugins/soleur/scripts tests/scripts` returns no match.
- [ ] AC6: the user-form baseline output is unchanged: the byte-pin test passes, its expected text was captured from `origin/main` before the engine edit, and `git diff origin/main...HEAD -- plugins/soleur/scripts/lint-ratchet.py` shows no change to the user-form header lines.
- [ ] AC7: `git diff --stat origin/main...HEAD -- plugins/soleur/skills/work/SKILL.md` is empty.
- [ ] AC8: ADR-290 no longer names `drawdown` in the PR3b contract sentence, carries Amendment 3, and Amendment 2 is byte-unchanged (`git diff origin/main...HEAD` on the ADR shows no removed or modified line inside the Amendment 2 section). The ADR's historical mentions of drawdown (the Amendment 1 `Tracker: ... Drawdown: #10433.` line and Amendment 2) are deliberately left; AC8 covers the contract sentence only.
- [ ] AC9: `plugins/soleur/skills/ship/scripts/technical-ruling-gate.sh --branch` exits 0.
- [ ] AC10: PR body contains `Closes #10583` and a separate line consisting of `Ref #10331`; `#10331` is not reopened and no closing keyword precedes it.

### Post-merge (operator)

None. `soleur:postmerge` verifies `main` is green and that the merged `scripts/lint-ratchet-*.baseline.txt` files match the PR.

## Test Scenarios

- Given the new engine, when `render_baseline("fixture", [], recovery="x")` runs, then the output starts with the zero-findings-gate line and contains no `Drawdown`.
- Given `name="user-ruff"`, when rendered, then the output equals the pre-change user form byte for byte.
- Given a committed Soleur baseline with a re-added `# Drawdown tracking: #1` line, when the parity test runs, then it fails naming the file.
- Given a clean tree, when `ruff --update` runs, then `git diff` on the baseline is empty.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change.

## Non-Goals

- No change to ratchet semantics (census, growth guard, fingerprint rule, exit codes).
- No edit to `plugins/soleur/skills/work/SKILL.md`, which is at its byte ceiling, or to `scripts/lint-shell-trace-credential-refusal*` (a separate baseline that also says "drawdown").
- No change to the user-repo baseline header.
- No rename of the baseline files.
- No reopening of #10331 or #10433.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold fails `deepen-plan` Phase 4.6; this plan fills it with threshold `none` and the scope-out line.
- The positional shift is the trap: `render_baseline(name, entries, drawdown, recovery, header)` becomes keyword-only after `entries`; a missed `render_baseline("fixture", x, "#1")` would otherwise bind `"#1"` to `recovery` and the old assertions would keep passing. Grep the suite for every `render_baseline(` call after the edit.
- `mock.patch.object(lr, "DRAWDOWN", ...)` raises `AttributeError` once the attribute is gone, so the two user-scope tests fail loudly rather than silently if the patch is left in.
- Run all ratchet commands from the worktree directory, not the bare repo root.
- The baselines must be regenerated with `--update`, never hand-written, so their bytes equal the renderer's output.
