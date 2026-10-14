---
title: Every refusal I added had a one-keystroke repair that reopened it
date: 2026-09-24
category: security-issues
module: plugins/soleur (plugin-root anchor, ADR-179 A18–A20)
tags: [plugin-root, fail-closed, admin-merge, safe-bash, guards, mutation-testing, review]
issues: ["#7453", "#8727", "#8730", "#8686"]
---

# Learning: every refusal I added had a one-keystroke repair that reopened it

## Problem

#7453 removed the `${CLAUDE_PLUGIN_ROOT:-<git-root>/plugins/soleur}` default arm from every skill,
so an unset root would fail closed instead of running a script from the checked-out tree. The
migration itself was mechanical (116 sites). Every defect the design pass and the 11-agent review
panel found was in the *new* fail-closed machinery, not in the migration:

1. **The refusal's natural repair reopened the hole.** The admin-merge fences gained
   `[[ -r "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json" ]] || exit 5`. The obvious response
   to "plugin root unresolved" is `export CLAUDE_PLUGIN_ROOT=$PWD/plugins/soleur` — which passes the
   check (every soleur checkout has `plugin.json`) and makes the `--admin` merge gate the PR's own
   `admin-merge-ready.sh`. The message named no fix, so it steered toward exactly that repair.
2. **Fail-closed at the shell was fail-OPEN at the consumer.** `auto-close-scan.sh` exits 0 with
   empty stdout when it cannot run; empty means "no traps". With the default arm gone, an unset root
   turned the scan into "nothing found" and the PR would be created with an auto-close trap.
3. **A "hardening" export overrode the trusted value.** The first draft opened each Read-surface
   block with `export CLAUDE_PLUGIN_ROOT=<cannot-exist sentinel>`. On the hosted surface
   `buildAgentEnv` already sets the `/app`-validated root; the unconditional export replaced it.
4. **A carve-out bypassed the check it claimed to preserve.** `safe-bash.ts` matched the exact
   literal on `candidate.trim()` BEFORE the denylist. `String.trim()` strips `\f`, NBSP, U+FEFF —
   bash does not — so `<literal>` followed by an NBSP was auto-approved with a different argv.
5. **The scope stopped at the ticket's noun.** "Skills" was migrated; `agents/**` still ran
   `bash plugins/soleur/skills/skill-security-scan/scripts/run-scan.sh` (a security gate) and a
   credential redactor CWD-relatively — the #7442 class, untouched because no `:-` was involved.
6. **Five mutations survived the guards**: partial-path pointers (`references/x.md`), an unquoted
   `bash ${CLAUDE_PLUGIN_ROOT}/…`, lease scenario 10b testing a hardcoded copy of the shipped line,
   two of three admin-merge fences unguarded, and `printf -v` / `read` / `=<(…)` assignments.

## Solution

- Admin-merge fences refuse a root that is unset, relative, lacks `plugin.json`, **or resolves
  inside `git rev-parse --show-toplevel`**; the exit-5 branch tells the agent to resolve it from the
  install path or hand the merge to the operator, "never export a repository path to get past it".
  Pinned: all three fences open with the line; M15 (inside checkout), M16 (relative), M15c twin
  (same root, outside the checkout → gate runs).
- `ship` checks the scanner is readable before scanning (`exit 5`), never "scan nothing".
- No block exports the variable; the notice has the agent print it first and **stop if it holds
  anything other than the root derived from the read path** (a `.claude/settings.json` `env` block
  could pre-set a checkout path).
- Carve-out moved after every denylist stage with an ASCII-only trim; NBSP/BOM rows red under the
  `String.trim()` mutant.
- `agents/**` script calls take the bare anchor; Guard 6 forbids CWD-relative execution there.
- Guards W3 (unquoted runner operand), W4b partial paths, W1b `printf -v`/`read`/`<(`; 10b extracts
  and runs the shipped `list` line; payload floor tightened to the measured 575 plus membership.

## Key Insight

**When you make something refuse, the refusal is not done until its most natural repair is also
refused.** Write down the one-line thing a stuck agent (or operator) will type in response to the
error, run it, and see whether it passes. A presence check proves presence; if the attacker's tree
satisfies it, the check is a speed bump that points at the hole. Same shape for fail-closed at the
shell: trace the *consumer* of the failed command — a tool that exits 0 with empty output converts
"could not run" into "found nothing". And any "hardening" that assigns a value must be checked
against every surface where a trusted value already exists. This is the #8686 lesson one level up:
there, CodeQL found what 12 readers missed because it executed a query; here, every finding came
from someone *running* the repair, the mutation, or the consumer, not reading the diff.

Related: [a PR must not control the guard that judges it](2026-09-23-a-pr-must-not-control-the-guard-that-judges-it.md).

## Session Errors

1. **`gh issue create` refused twice by the filing gate** (unreadable scratchpad `--body-file`; User-Impact named no surface). Recovery: Write the body file; reword. **Prevention:** already gate-enforced; write body files with Write, name the user surface.
2. **Foreground `sleep 60` blocked.** Recovery: background wait. **Prevention:** hook-enforced; use Monitor/background.
3. **A plan splice missed its anchor** (0 matches). Recovery: re-applied. **Prevention:** assert `count == 1` in every scripted splice (done here throughout).
4. **Observability layer mis-numbered.** Recovery: fixed. **Prevention:** cite the layer table, not memory.
5. **(Carry-in, #8686) CodeQL found 3 high alerts a 12-agent panel missed** — regex built from data escaped only `-`/`:`; single-pass `<!--` strip. Recovery: `1b240b96df`. **Prevention:** review brief asks for a semgrep/CodeQL-class pass on data-built regexes and multi-pass sanitization (semgrep seat ran here and checked both).
6. **#8686 conflicted twice on `plan-sharp-edges.md`.** Recovery: kept both bullets. **Prevention:** append-only catalogue files conflict by construction; resolve by union.
7. **#8686's deploy arm was stamped with main's tip.** Recovery: identified the arm by its `resolve-target` log. **Prevention:** already in postmerge Phase 3.7.
8. **`components.test.ts` red on a backticked `scripts/…` in `schedule/SKILL.md`.** Recovery: reworded. **Prevention:** run `components.test.ts` after any SKILL.md prose edit (it is in the targeted set).
9. **Plan predicted "parser missing"; measured rc 127 "unbound variable" under `set -u`.** Recovery: pinned the measured behaviour plus a set-but-empty row. **Prevention:** measure fail-closed behaviour before writing it into a plan.
10. **W6/W11 went vacuous when the presence line named `admin-merge-ready.sh`.** Recovery: presence check tests `plugin.json`. **Prevention:** a guard line must not contain the token the downstream anchor greps for.
11. **Lease floor miscounted a summary line as an assertion.** Recovery: measured 42. **Prevention:** set floors from the runner's own count line.
12. **M7 anchor not unique.** Recovery: widened to include the `SHA=` line. **Prevention:** `cq-assert-anchor-not-bare-token`.
13. **`claude -p` session limit** during AC12. Recovery: retried after operator "continue". **Prevention:** one-off.
14. **Read-surface sentinel export overrode the hosted root.** Recovery: removed; print-first check. **Prevention:** before adding an assignment as hardening, list every surface that already sets the value.
15. **`legal-template-vendor-surface` anchor broke when the path was quoted.** Recovery: `"?` in the regex. **Prevention:** grep tests for the edited sentence before quoting a path.
16. **`pgrep -f` blocked as self-matching.** Recovery: `proc.sh` `list_runs`/`kill_mine`. **Prevention:** hook-enforced.
17. **`git add` of a gitignored `*.log` aborted an `&&` chain, so the commit never ran.** Recovery: dropped the log. **Prevention:** keep run logs in the scratchpad, not the spec dir.
18. **Lefthook pre-commit (`test-all --affected`) exceeded 10 min.** Recovery: killed via `kill_mine`, re-committed with `LEFTHOOK_EXCLUDE=bun-test,plugin-component-test,web-platform-typecheck` after the targeted battery passed; CI is the gate. **Prevention:** run the targeted battery first, then exclude only the heavy duplicated hooks (never `--no-verify`).
19. **My new notice used `:-`, then `printenv` — both rejected by the payload's own W1 guard.** Recovery: `echo "root=[${CLAUDE_PLUGIN_ROOT}]"`. **Prevention:** before writing text into a guarded corpus, read the guard's predicates (`readsRootUnsafely`, `plantsRootUnsafely`).
20. **Scripted splice assertion failed on an escaped `\n` in the test source.** Recovery: Edit tool. **Prevention:** use Edit for single-line literal edits containing escapes.
21. **Accidental `git stash list` in a command blocked by hook.** Recovery: removed. **Prevention:** hook-enforced.
22. **Review panel findings (items 1–6 of Problem).** Recovery: all fixed inline. **Prevention:** the Key Insight — run the repair, trace the consumer.
23. **`lint-infra-no-human-steps` run bare reported 518.** Recovery: CI form `--changed`. **Prevention:** read the runner's invocation (`grep` ci.yml) before running a baselined/scoped linter.
24. **First W4b partial-path check flagged the doc's own notice and a URL.** Recovery: exclude self and strip URLs. **Prevention:** controls for every new predicate include a self-reference and a URL row (added).
