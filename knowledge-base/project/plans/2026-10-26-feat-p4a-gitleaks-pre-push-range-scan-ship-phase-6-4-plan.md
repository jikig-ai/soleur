---
title: "feat: P4a gitleaks per-commit pre-push range scan wired into ship Phase 6.4"
type: feat
date: 2026-10-26
slug: p4a-gitleaks-pre-push-range-scan-ship-phase-6-4
branch: feat-one-shot-10924-p4a-gitleaks-pre-push
issue: 10924
closes: []
lane: cross-domain
brand_survival_threshold: aggregate pattern
---

# feat: P4a gitleaks per-commit pre-push range scan wired into ship Phase 6.4

## Enhancement Summary

**Deepened on:** 2026-10-26
**Sections enhanced:** Proposed Solution, Guard Contract, Phase 0/1, Acceptance Criteria, Test Scenarios, Risks
**Research agents used:** repo-research-analyst, learnings-researcher, functional-discovery, CTO (5 forks), plan-review (DHH, Kieran, code-simplicity), security-sentinel, test-design-reviewer, spec-flow-analyzer

### Key Improvements
1. Re-scoped the locus: Phase 6.4's hook fires post-push, so the scan is a script at the Phase 6 push preamble with a Phase 6.4 pointer (CTO-ruled), inside a 116-byte SKILL.md budget (net about -100 bytes, measured).
2. CLEAN can only come from rc 0 AND a report of exactly `[]`; every other path is FINDINGS, NOT_RUN (43, continue) or STOP; a crash can never read as "continue".
3. Hardened against bypass and leakage: validated `--base`, scrubbed environment, sanitized output, private temp dir; limitations (merge-only content, PR-controlled config, `-diff`) measured and documented rather than claimed away.

### New Considerations Discovered
- `gitleaks git` exits 0 with `[]` for an unresolvable ref and `--no-merges` misses conflict-resolution-only content (both measured).
- Under one-shot the branch is already on origin before Phase 6, and later push sites are prose-only (hook deferred to a filed follow-up).

Spec lacks valid `lane:` (no spec.md for this branch) — defaulted to `cross-domain` (TR2 fail-closed).

## Overview

Item P4a of the four-part ship/CI hygiene follow-up list (#10924, umbrella #9757; this PR carries
`Ref #9757` only and ticks the P4a checkbox in #10924's body, it closes nothing). Give the ship skill
a local, per-commit secret scan over the commits a push would publish (`origin/main..HEAD`), run
BEFORE the push, so a secret-bearing commit is caught while its history is still local and fixable by
rewriting an unpublished commit, instead of after it has reached this public repository and a CI
range scan that a later "fix" commit cannot clear.

The read-first step re-scoped the brief in one load-bearing way (see Research Reconciliation): the
brief names "Phase 6.4 (Unpushed-Commits Gate)" as the home, but Phase 6.4's mechanical enforcement
(`.claude/hooks/ship-unpushed-commits-gate.sh`) fires on `gh pr merge`, which is AFTER the commits
are pushed and after CI has scanned them. A scan inside that hook would be post-push and redundant.
The scan therefore lives in a script that the skill runs at the Phase 6 push preamble, with Phase 6.4
carrying the pointer for "every later push in this skill". Ruled by CTO agent, 2026-10-26 (Fork 1).

## Research Reconciliation — Spec vs. Codebase

| Brief / issue claim | Reality (checked) | Plan response |
|---|---|---|
| "add ... to ship Phase 6.4 (Unpushed-Commits Gate)" as if 6.4 runs before the push | 6.4 is a pre-`gh pr merge` gate; its hook denies when `origin/<branch>..HEAD` is non-empty and says "run `git push`". Pushes happen at SKILL.md Phase 6 (`git push -u origin BRANCH_NAME`) and at later sites (Phase 6.45 archive push, Phase 6.5 conflict path and re-verify push, Phase 7 test-failure branch, plus `sync-pr-behind.sh`). | Scan runs at the Phase 6 push preamble; Phase 6.4 gets a one-line pointer "run it before any later `git push`". The hook is left untouched (CTO Fork 4). |
| "any existing gitleaks wiring" is directional | Wiring is dense: CI `secret-scan.yml` (PR + merge_group range scan, `gitleaks dir .`, main ancestry, weekly), lefthook `gitleaks-staged` (pre-commit), `.claude/hooks/git-commit-secret-scan.sh` (PreToolUse on `git commit`, staged index). Nothing scans the range locally BEFORE a push. | The gap is real and narrow: commits that never passed the staged scan (conflict-resolution/rebase/amend/script commits, a commit made while gitleaks was unrunnable) and the "red range scan cannot be fixed by a later commit" property documented in `secret-scanning.md`. |
| lefthook / `scripts/hooks/pre-push` could host a pre-push scan | The shared repo config sets `core.hooksPath=/dev/null` (`git config --show-origin core.hooksPath` -> `.git/config`), so no git hook fires on this host, and fresh worktrees do not get lefthook installed (header of `git-commit-secret-scan.sh`). | Not used. A skill-run script is the only locus that fires on every host the ship skill runs on. |
| Local scan mirrors CI so it can claim "closes the merge-resolution gap" | Measured 2026-10-26 in a scratch repo: a secret that exists only in a conflict-resolution merge commit is MISSED by `--no-merges origin/main..HEAD` (rc 0, 1 commit scanned), found by `-m` and by `gitleaks dir .`. CI's range arm has the same hole; CI's `gitleaks dir .` step is what covers it. | The script mirrors CI's range arm exactly (no silent divergence). Docs and receipt do NOT claim merge-only content; the limitation is pinned by a known-answer test row and a deferred follow-up is filed (tracked-files tip scan). |
| SKILL.md can take a new section | `plugins/soleur/skills/ship/SKILL.md` is 273,839 bytes against a merge-base-anchored ceiling of 273,955 (`plugins/soleur/test/skill-body-budget.json`, `scripts/lint-skill-body-budget.py`): 116 bytes of headroom, and raising a ceiling is a separate reviewed PR. | Contract lives in the script header plus one subsection of `secret-scanning.md`; SKILL.md edit is pointer-only, net target <= 0 bytes, funded by trimming existing Phase 6.4 prose (exact trims below). |
| CI and local gitleaks are the same version | CI pins 8.24.2; this host has 8.30.1 (`gitleaks version`). | Receipt prints the version; a local-only finding from a newer pack is still a STOP (conservative). No version enforcement (would make the check host-fragile). |

## Research Insights

**Premise validation.** Checked: #10924 is OPEN, Ref-only umbrella #9757, P4a unticked; the classifier
PR (#10968) is merged on `origin/main`; the cited files exist (`ship/SKILL.md` Phase 6.4,
`ship-unpushed-commits-gate.sh`, `secret-scan.yml`, `.gitleaks.toml`, `lefthook.yml`). Held: the gap
(no local range scan) is real. Stale/partly wrong: "Phase 6.4" as the pre-push locus (see above) and
"lefthook" as a candidate host. ADR corpus grep (`gitleaks`, `pre-push`, `secret`): ADR-032, -116,
-157, -180, -188, -242, -276, -281 mention gitleaks only incidentally; none rejects a skill-run local
scan. ADR-188 supplies the test-suite rule: a guard that can silently disarm FAILs under `CI=true`
and SKIPs only locally.

**Property List.**
1. A secret-shaped string in any non-merge commit of `origin/main..HEAD` stops the ship flow before the Phase 6 push (the flow's first push; later pushes carry the same pointer, but only the deferred `git push` hook would make them mechanical), naming commit, file, line and rule id but never the secret.
2. A scan that did not or could not run is distinguishable from a clean scan (a receipt line carries verdict, range size, scanned count when readable, base SHA, fetch state, gitleaks version).
3. The flow tolerates an unavailable scanner the same way the commit hook does (record "not run", CI remains the gate) without letting a script crash read as "continue".
4. Local range semantics equal CI's range arm (`--no-merges BASE..HEAD`), so a local PASS predicts CI's range-arm verdict.

**Cut List (mechanisms the ask or issue named, with what already covers the property).**
- Hook extension of `ship-unpushed-commits-gate.sh` (brief: "Phase 6.4") -> cut: fires post-push; covered by the Phase 6 preamble script (CTO Fork 1/4).
- lefthook `pre-push` entry -> cut: dead under `core.hooksPath=/dev/null` and absent in fresh worktrees; the existing pre-push mirrors there serve a different purpose.
- New PreToolUse `git push` hook (the only fully mechanical locus) -> deferred, not cut: filed as a follow-up with a re-evaluation criterion (Deferral Tracking below).
- `-diff` gitattribute blob re-scan (the commit hook has one) and the one-line `-diff` warning -> cut for P4a: the local-only vector is the operator's own `.git/info/attributes`; committed attributes are covered by CI's `gitleaks dir .`; documented as a limitation (CTO Fork 3, warning dropped at plan-review).
- `SOLEUR_RULE_APPLIED` marker, separate `references/prepush-secret-scan.md`, `git branch -r --contains` remedy branching, colour-pin textual parity test, `context-sanitize.sh` dependency -> cut at plan-review: each answers none of the four properties (see Plan Review Revisions).
- AGENTS.rules.md rule / new rule id -> cut: `wg-ship-push-before-merge` already names Phase 6.4; a new always-loaded rule costs every session and the rule-body hash gate; the pointer plus `[skill-enforced]` text is the right tier (`cq-agents-md-tier-gate`).

**Institutional learnings applied** (paths under `knowledge-base/project/learnings/`):
- `2026-09-18-every-instrument-i-waited-on-was-counting-itself.md`: pin `color.*` through BOTH `GIT_CONFIG_COUNT` and `GIT_CONFIG_PARAMETERS`; fixture-test it.
- `best-practices/2026-07-11-gitleaks-shared-non-test-helper-not-in-test-allowlist-and-scans-whole-diff-range.md`: whole-range scan, a later removal does not clear; the verification command is exactly this scan.
- `integration-issues/2026-07-30-the-step-that-could-not-report-and-the-guard-that-worked-in-one-scan-mode.md`: test in the scan mode CI uses; under `set -e`, `|| rc=$?` disarms; re-raise the code after writing outputs.
- `2026-09-07-my-instruments-reported-green-while-measuring-nothing.md`: count of zero is weak evidence; the receipt carries `scanned`.
- `2026-05-12-ship-unpushed-commits-fail-open-class.md`: three-layer gate precedent; fetch failure was flipped to fail-closed there, but for a different property (stale ref hides unpushed commits). Here a stale base only widens the range (over-scan), so fetch failure is a warning (CTO Fork 5).
- `2026-05-12-anticipatory-hook-bypass-and-leader-substrate-cross-check.md`: no env-var escape hatch that skips the scan.
- `2026-04-23-hostname-prefix-guard-and-strict-mode-pipefail.md`: capture scan output and exit codes in separate statements.
- `.../battery-owed.sh` header (#8247): an exit code a crash can produce must never mean "continue" (a `set -u` abort exits 1; a syntax error exits 2). Hence NOT_RUN is 43, and only 0 and 43 continue.

**Community overlap.** `functional-discovery` found nothing that scans `origin/main..HEAD` per commit inside a ship flow (closest: `openqodex`, a hook-based pre-push secret reviewer; nothing installed). Build in-house.

**Measured facts (commands run during planning).** `gitleaks version` -> 8.30.1; `gitleaks git --redact --no-banner --exit-code 1 --log-opts="--no-merges origin/main..HEAD"` on this branch -> rc 0, "0 commits scanned" in 0.37 s (the single commit in range is empty, so a legitimate scanned=0 with range=1 exists and `scanned=0` alone cannot mean NOT_RUN); `gitleaks dir .` on the 409 MB worktree -> 3.0 s wall. Merge-commit experiment above. `gitleaks git --log-opts="--no-merges nonexistentref..HEAD"` exits 0 with a report of `[]` (an unresolvable ref scans nothing silently), so the script's own `git rev-parse --verify` precondition is load-bearing. CLI flags verified via `gitleaks git --help`: `--log-opts`, `--redact`, `--exit-code`, `--report-path`, `-c/--config`, `--no-banner`.

## Plan Review Revisions

Panel: DHH, Kieran, code-simplicity (aggregate-pattern threshold, 3-agent baseline). Named CEO/design/devex panel not spawned: no product/UI surface, and the CTO already ruled the five forks. Mechanical findings applied:

- R1 (DHH P0, Kieran P0-1): CLEAN is derived from `rc 0` AND a report that is exactly `[]`; the `N commits scanned.` line is read best-effort and only cross-checked when it parses (`scanned=?` on a parse miss), so gitleaks output-format drift cannot silently turn every run into NOT_RUN. rc 1 with a non-empty report is FINDINGS even if the report does not parse; only rc 1 with a missing or zero-byte report is NOT_RUN; rc 0 with a non-`[]` report is FINDINGS defensively.
- R2 (Kieran P0-2): when the scanned count parses AND `git log --no-merges --format= --name-only BASE..HEAD` is non-empty, `scanned == 0` or `scanned > range` is NOT_RUN `reason=scanned-mismatch` (a mis-ranged or no-op scan cannot print CLEAN). Measured during review: gitleaks exits 0 with `[]` for an unresolvable ref, so the `git rev-parse --verify` precondition is load-bearing.
- R3 (Kieran P0-3): mutation row 4 split; removal of the `GIT_CONFIG_PARAMETERS` pin goes RED under `GIT_CONFIG_PARAMETERS='color.diff=always'`; the `GIT_CONFIG_COUNT` pin is an equivalent mutant while the PARAMETERS pin exists (PARAMETERS wins), so it is kept as defense in depth and excluded from the matrix.
- R4 (Kieran P1-4): byte arithmetic re-measured (the #3624 sentence is 252 bytes -> ~58, saving ~194; additions ~335): extra trims named so the net target is <= 0, with the hard ceiling +116.
- R5 (Kieran P1-5): pointer carries the runnable `bash "${CLAUDE_PLUGIN_ROOT}/skills/ship/scripts/prepush-secret-scan.sh"` command, says "check the exit code explicitly, no pipe", and Phase 6.4 says "Phase 6's secret scan" (6.4 precedes Phase 6 in the file).
- R6 (Kieran P1-6): `timeout` resolved once (timeout -> gtimeout -> unbounded) with the `${a[@]+"${a[@]}"}` idiom; the timeout suite row SKIPs on a host with neither.
- R7 (DHH P1-4, Kieran P2-9): Property 1 reworded to the first push (structural) plus pointer for later pushes (prose).
- R8 (DHH P1-3, simplicity): the `SOLEUR_RULE_APPLIED` marker is cut (it fired on NOT_RUN and mis-attributed `wg-ship-push-before-merge`); the receipt is the liveness signal.
- R9 (DHH P1-5, simplicity): remedy is one static two-sentence text (no `git branch -r --contains`).
- R10 (DHH P1-7, simplicity): the colour-pin textual parity test against the hook is cut; the behavioural PARAMETERS row is the oracle.
- R11 (simplicity): separate `references/prepush-secret-scan.md` cut; the contract lives in the script header and one subsection of `secret-scanning.md`. SKILL.md links the script only.
- R12 (DHH P2-8, simplicity): affected-paths array trimmed to what the suite reads.
- R13 (DHH P2-11): `context-sanitize.sh` dependency dropped; receipt fields are controlled tokens or integers and the gitleaks version string is passed through `tr -cd '[:alnum:].-'`.
- R14 (DHH P0-2, P2-10): the "NOT_RUN over 1 in 20 ships" re-evaluation criterion and the unowned post-merge AC are deleted (nothing persists a count to measure).
- R15 (simplicity hidden assumption): `SOLEUR_PREPUSH_SCAN_TIMEOUT` is honoured only when it is an integer in 1..600; anything else falls back to 120.
- R16 (Kieran P2-10): bash pitfalls pinned in Phase 1 (no `local x=$(...)`, explicit `exit "$final_rc"`, never echo raw gitleaks output because it carries author emails).
- R17 (simplicity gap): an AC asserts the SKILL.md pointer carries the "secret-scan: not run" instruction.

**Deepen-plan findings applied (2026-10-26; agents: security-sentinel, test-design-reviewer, spec-flow-analyzer; mechanical gates 4.6/4.7/4.8/4.11/4.12 passed; 4.5, 4.9, 4.10, 4.13 not triggered):**

- D1 (security P1-2, spec-flow 6): `--base` validated by regex, resolved to a 40-hex SHA with `--end-of-options`, only the SHA reaches `--log-opts`; default spelled `refs/remotes/origin/main`.
- D2 (security P1-3): ambient git/gitleaks environment scrubbed, `GIT_NO_REPLACE_OBJECTS=1`, absolute gitleaks path refused if under the repo, probe from cwd `/`.
- D3 (security P1-1, P2-4): PR-controlled config kept for CI parity; `cfg_changed` and full `base=`/`head=` in the receipt; stale-vs-advanced base claim corrected.
- D4 (security P2-1, P2-2): ASCII allowlist on every printed field; `umask 077` `mktemp -d`; zero-byte-report-before-content evaluation order made explicit.
- D5 (spec-flow 1, 4): pointer names the unset `CLAUDE_PLUGIN_ROOT` (127) case; the script's last line `secret-scan: not run (<reason>)` is the PR-body line.
- D6 (spec-flow 2, 5): remedy rewritten to what an agent can run (`reset --soft`, `--force-with-lease`, false-positive allowlist route); headless FINDINGS aborts and never rewrites history unasked.
- D7 (spec-flow 3): depth-1 clone -> NOT_RUN `no-merge-base`, suite row on the hosted-ship shallow fixture.
- D8 (test-design 1-3, 5, 6-9): rows 6/4 reworked into measured separate mutants, new rows 7 (`--config`) and 8 (base validation), argv-strict stubs captured from the real binary, anchored REORDER check on a sandbox SKILL copy, skip-aware FLOOR with CI-fail, `jq` precondition, instrument control, process-group reaping of the sleeping stub, hermetic env also passed to the script under test.
- D9 (byte measurement): additions 482 vs trims 438; the Hook-ordering trim is now required (net about -100).
- Rejected: separate STOP code for incomplete scans (security P2-3) - contradicts CTO Fork 2; loud WARN only. Stopgap `gitleaks dir .` at the Phase 6.5 push (spec-flow 8) - no byte budget; covered by the deferred follow-up.

Taste items not applied (recorded in decision-challenges.md): fetch step kept per CTO Fork 5 (simplicity asked to drop it); `-diff` warning dropped (CTO Fork 3 permitted dropping it if noisy; two reviewers asked to cut it); mutation rows reduced from 8 to 6 mutants plus 2 direct assertions.

## Technical Rulings

All recorded in `knowledge-base/project/specs/feat-one-shot-10924-p4a-gitleaks-pre-push/decision-challenges.md`.

- Ruled by CTO agent, 2026-10-26: Fork 1 - skill-run script at the Phase 6 push preamble with a Phase 6.4 pointer; a PreToolUse `git push` hook is deferred to a filed follow-up - Phase 6.4's hook fires post-push so scanning there is redundant, and a push hook needs target resolution, settings wiring and hook tests beyond P4a's scope.
- Ruled by CTO agent, 2026-10-26: Fork 2 - scanner unavailable (absent/unrunnable/timeout/missing config/unresolvable base) exits "not run" and the skill records `secret-scan: not run (<reason>)` and continues - CI's `secret-scan.yml` is the load-bearing gate and the commit hook already fails open; findings always block.
- Ruled by CTO agent, 2026-10-26: Fork 3 - accept the `-diff` limitation and document it (the ruling allowed a one-line warning and said to drop it if noisy; plan-review dropped it, see R-notes) - no blob re-scan.
- Ruled by CTO agent, 2026-10-26: Fork 4 - leave `ship-unpushed-commits-gate.sh` untouched - it fires after the push, so naming a pre-push scan there is misleading.
- Ruled by CTO agent, 2026-10-26: Fork 5 - best-effort `git fetch origin main`, tolerate failure with `fetch=stale`, scan exactly `origin/main..HEAD`; unresolvable base is "not run", never CLEAN. Caveat adopted: `--no-merges` misses merge-only content (measured), so P4a does not claim to close that gap.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "add a gitleaks per-commit pre-push check over origin/main..HEAD to ship Phase 6.4 (Unpushed-Commits Gate) in plugins/soleur/skills/ship/SKILL.md" [brief] | Phase 1 script, Phase 2 SKILL.md pointers | mapped |
| 2 | "Start with a read: ... read ship SKILL.md Phase 6.4, any existing gitleaks wiring in the repo (CI secret-scan workflow, lefthook, scripts) and the unpushed-commits gate hook before designing, and re-scope if the premise is wrong" [brief] | Research Reconciliation, Premise Validation | mapped |
| 3 | "Spawn soleur:engineering:cto only for a genuine design fork (technical ruling; record \"Ruled by CTO agent\")" [brief] | Technical Rulings + decision-challenges.md | mapped |
| 4 | "PR body uses `Ref #9757` only, never a closing keyword. Do not close #10924 until all four P4 items have merged; tick the P4a checkbox in its body instead." [brief] | Phase 5 (PR body, checkbox tick) | mapped |
| 5 | "Merge through the merge queue with `gh pr merge <N> --squash --auto`, never `--admin`." [brief] | Phase 5 | mapped |
| 6 | "P4a should not touch that workflow." / "Keep apps/** and scripts/registry-restore-from-ghcr.sh unchanged." [brief] | Non-Goals; AC diff-scope | mapped |
| 7 | "Do not read or print secrets; do not run doppler or any live credentialed probe." [brief] | Test design (synthesized fixtures), redaction | mapped |
| 8 | "Items P4b, P4c and P4d of #10924 come after, one PR each, in that order; this PR is P4a only." [brief] | Non-Goals | mapped |
| 9 | the hazard list (registries, floors, mktemp, ordinals, queue rules) [brief] | Phase 3 registries, Phase 5 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `prepush-secret-scan.sh` | "gitleaks per-commit pre-push check over origin/main..HEAD" (ask 1) | asked |
| SKILL.md pointers (Phase 6 preamble, Phase 6.4) | "to ship Phase 6.4 (Unpushed-Commits Gate)" (ask 1) | asked |
| Contract text in the script header and a subsection of `secret-scanning.md` | — | inferred — justification: SKILL.md has 116 bytes of headroom under the merge-base ceiling, so the contract text must live outside it, and `secret-scanning.md` is the canonical statement of which layer scans what |
| Test suite `ship-prepush-secret-scan.test.sh` | "Run lint-orphan-test-suites.sh ... pipe-guard test locally before pushing" (ask 9, implies a suite exists) | inferred — justification: a guard with no mutation-checked suite is the vacuity class `cq-write-failing-tests-before` and the Guard Contract gate forbid |
| Receipt line + exit-code contract (0/1/43) | — | inferred — justification: without a receipt a skipped scan is indistinguishable from a clean one, and a crash must not read as "continue" |
| Selector/baseline registry rows | "New files a test sources or reads must be registered in the selector arrays ..." (ask 9) | asked |
| Follow-up issue for the `git push` hook and tip-tree scan | CTO Fork 1 ruling (deferral must be tracked per `wg-when-deferring-a-capability-create-a`) | inferred — justification: the ruling deferred the mechanical locus and an untracked deferral is invisible |

### Split Assessment

- Subsystems touched: 3 — `plugins/soleur` (script, SKILL.md, test), `scripts` (selector/shard registries), `knowledge-base` (runbook subsection, plan/spec artifacts)
- Planned files: ~9 | Estimated changed lines: ~500 (script ~150, test ~260, registries ~15, docs ~40)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Proposed Solution

One script, three outcomes, one receipt.

`plugins/soleur/skills/ship/scripts/prepush-secret-scan.sh [--base REF] [--no-fetch]` (run from inside the work tree; default base `refs/remotes/origin/main`, spelled out because a tag named `origin/main` outranks the short form, see the SKILL.md note near line 272; `--no-fetch` exists for the offline discoverability probe and the suite):

1. Hardening before anything else: `cd` to `git rev-parse --show-toplevel`; `umask 077`; `TMP=$(mktemp -d)` with an EXIT/INT/TERM trap that removes it (report, stdout/stderr capture, nothing else lives outside it); scrub the ambient git/gitleaks environment for every child: unset `GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_EXTERNAL_DIFF GIT_REPLACE_REF_BASE` and every `GITLEAKS_*`, set `GIT_NO_REPLACE_OBJECTS=1`, `GIT_CONFIG_GLOBAL=/dev/null`, `GIT_CONFIG_NOSYSTEM=1`, `GIT_TERMINAL_PROMPT=0`, then append the `color.ui`/`color.diff=never` pins through BOTH `GIT_CONFIG_COUNT` entries and `GIT_CONFIG_PARAMETERS` (the pattern in `git-commit-secret-scan.sh`).
2. `--base` validation: must match `^[A-Za-z0-9._/-]+$` and not start with `-`; resolve with `git rev-parse --verify --end-of-options "$BASE^{commit}"` to a 40-hex SHA and put ONLY that SHA in `--log-opts` (gitleaks splits `--log-opts` on whitespace, so a revision expression with spaces would smuggle `git log` options). Unresolvable -> NOT_RUN `base-unresolvable` (gitleaks itself exits 0 with `[]` for an unresolvable ref, measured, so this precondition is load-bearing). `git merge-base BASE_SHA HEAD` failing (a depth-1 hosted clone, see `plugins/soleur/test/hosted-ship-shallow-merge-base.test.sh`) -> NOT_RUN `no-merge-base`: an over-scan of main's cut-off history would attribute other commits to this PR.
3. Preconditions, each a NOT_RUN with a named `reason=`: inside a git work tree; `.gitleaks.toml` at the top-level; a RUNNABLE gitleaks: resolve `gitleaks` once to an absolute path, refuse a path whose `realpath` is under the repo top-level (`gitleaks-in-repo`: a PR-controlled shim), probe by running `gitleaks version` from cwd `/` bounded by `timeout`, retry once wider on 124/137 (as `git-commit-secret-scan.sh` does; `command -v` alone is not enough, an unpinned mise shim resolves and exits non-zero).
4. Refresh: `git fetch --no-tags origin main` bounded at 10 s (skipped by `--no-fetch`); failure sets `fetch=stale` and continues. Both SHAs are recorded in full. Caveat stated in the header: a stale base widens the range, but a locally advanced `refs/remotes/origin/main` (`update-ref`, `branch -f`) narrows it, so the receipt prints `base=` and `head=` unabbreviated.
5. Range: `N=$(git rev-list --count --no-merges BASE_SHA..HEAD)`; `E=$(git log --no-merges --format= --name-only BASE_SHA..HEAD)` (non-empty means at least one commit has a patch); `cfg_changed=1` when `git diff --name-only BASE_SHA..HEAD` lists `.gitleaks.toml`, `.gitleaksignore` or `.gitattributes` (the scan uses the working-tree config, matching CI, so a PR that widens its own allowlist can scan itself clean; CI's `allowlist-diff` job is the backstop, the receipt flag makes the local blind spot visible).
6. Scan: `gitleaks git --redact --no-banner --exit-code 1 --config <top>/.gitleaks.toml --report-format json --report-path $TMP/report.json --log-opts="--no-merges BASE_SHA..HEAD"`, stdout and stderr captured to `$TMP` and never echoed (raw gitleaks output carries author emails), `timeout` resolved once (timeout -> gtimeout -> unbounded, `${a[@]+"${a[@]}"}` idiom for bash 3.2), default bound 120 s (`SOLEUR_PREPUSH_SCAN_TIMEOUT` honoured only as an integer in 1..600), stdin closed.
7. Verdict, rc and output captured in separate statements (no `|| rc=$?`, no `local x=$(...)`); evaluation ORDER is part of the contract because `mktemp` pre-creates an empty report: rc 124/137 -> NOT_RUN `timeout`; a missing or zero-byte report -> NOT_RUN `empty-report` (evaluated BEFORE any report-content branch, so rc 0 with no report can never reach CLEAN); rc 1 with a non-empty report -> FINDINGS (summary of up to 5 as `commit File:Line (RuleID)` when `jq` is present, else the `RuleID` count with `commit=?`); rc 0 and a report that is exactly `[]` -> CLEAN, subject to the cross-check: if the `N commits scanned.` line parses (anchored regex, last match) and `E` is non-empty, `scanned == 0` or `scanned > N` -> NOT_RUN `scanned-mismatch`; a parse miss leaves `scanned=?` and does NOT block CLEAN; rc 0 with a non-`[]` report -> FINDINGS; any other rc -> NOT_RUN `gitleaks-rc-N`. Every NOT_RUN also prints a loud one-line stderr WARN naming the reason.
8. Output hygiene: every printed field (File, RuleID, Commit, reason, version) is passed through an ASCII allowlist `tr -cd '[:alnum:]._/@+=-'` with a length cap (File and RuleID come from PR content and a possibly hostile toml: ANSI, newlines and prompt-injection text must not reach the transcript); Commit is printed only if it matches `^[0-9a-f]{7,40}$`.
9. Always last: the receipt `PREPUSH_SECRET_SCAN verdict=<CLEAN|FINDINGS|NOT_RUN> base=<40hex|none> head=<40hex|none> fetch=<ok|stale|skipped> range=<N> scanned=<M|?> cfg_changed=<0|1> gitleaks=<ver|none> reason=<token>`, and on NOT_RUN a final ready-made line `secret-scan: not run (<reason>)` for the PR body. The script ends in an explicit `exit "$final_rc"`.

Exit contract (the caller branches on this; it lives in the script header): `0` CLEAN; `1` FINDINGS (STOP; also what a `set -u` abort produces, which is the safe direction); `43` NOT_RUN (record and continue); any other value is a STOP, including `127` (script not found because `CLAUDE_PLUGIN_ROOT` is unset in a cloud shell: the pointer names this case). Only `0` and `43` continue. 43 is deliberately outside every status bash produces by accident (1 set -u/generic, 2 syntax, 126, 127, 128+N), the same reasoning as `battery-owed.sh`'s 42.

`--base` is a range selector, not a skip switch (`--base HEAD` yields `range=0`); no environment variable or file skips the scan (the only env knob is the clamped timeout).

### Remedy text (static; printed with FINDINGS, mirrored in the runbook subsection)

Printed by the script, in this order: (1) commit still local: `git reset --soft origin/main`, remove the secret from the files, recommit (this squashes the range and re-runs the commit hook); tip commit only: `git commit --amend`. (2) A commit already on `origin`: the secret is published, rotate it first, then the same reset, then `git push --force-with-lease`, then follow knowledge-base/engineering/operations/secret-scanning.md. (3) False positive: add a per-rule allowlist to `.gitleaks.toml` (review applies) and re-run. Interactive ship asks before rewriting history; headless ship aborts with the receipt and never rewrites history unasked (no `git rebase -i`: not executable by an agent). Version skew (8.30.1 local vs 8.24.2 CI) can flag an already-published commit that CI accepts; route (3) is the way out, so the check cannot deadlock a push.

### SKILL.md edit (pointer-only; target net <= 0 bytes, hard ceiling +116)

Measured 2026-10-26 on `origin/main` content (UTF-8 bytes, Python `len(str.encode())`): additions 414 (Phase 6 line incl. blank-line separator) + 68 (Phase 6.4 sentence) = 482; trims 192 (#3624 sentence 252 -> 60) + 186 (fail-closed clause) + 60 (chained-forms parenthetical) = 438; the 500-byte "Hook ordering" paragraph is now a REQUIRED trim of at least 150 bytes, giving a net of about -100. Re-measure with `wc -c` before pushing.

- Add before "Push the branch to remote." in Phase 6 (after the Pipeline tally gate paragraph): `**Secret scan — BEFORE the push and every later push:** \`bash "${CLAUDE_PLUGIN_ROOT}/skills/ship/scripts/prepush-secret-scan.sh"\` ([contract](./scripts/prepush-secret-scan.sh)); check the exit code, no pipe: 0 continue; 43 append the printed \`secret-scan:\` line to the PR body and continue (CI gates); else STOP (127: plugin root unset, see Cloud Mode). Headless FINDINGS: abort, never rewrite history unasked.`
- Add one sentence in Phase 6.4: `Run Phase 6's secret scan before any \`git push\` this gate asks for.` (6.4 precedes Phase 6 in the file, so it cannot say "above").
- Trims (all inside Phase 6.4): the PR #3624 narrative sentence (252 bytes) -> `(PR #3624 → #3627 → #3630: 2 of 5 commits never landed.)` (60 bytes); the whole "**Fail-closed on fetch failure** — ..." clause (186 bytes, keep the fail-open list sentence it follows); the "(including chained forms like `gh pr ready && gh pr merge`)" parenthetical (60 bytes); and at least 150 bytes out of the "Hook ordering" paragraph. Net <= 0 is the target because another PR landing in the queue first consumes the shared 116-byte headroom. Links are markdown links or an explicit command, never bare backtick refs (`components.test.ts` convention). The `[skill-enforced: ship Phase 6.4 + hook ship-unpushed-commits-gate.sh]` tag is unchanged.

## Non-Goals

- No change to `.claude/hooks/ship-unpushed-commits-gate.sh`, `.claude/settings.json`, lefthook, `scripts/hooks/pre-push`, any workflow (in particular not `apply-web-platform-infra.yml`, so merging fires no production apply), `AGENTS.rules.md`, `apps/**`, or `scripts/registry-restore-from-ghcr.sh`.
- No `git push` PreToolUse hook, no tip-tree scan of tracked files, no merge-commit (`-m`) range arm, no `-diff` re-scan or warning: documented limitations, with the first two filed as one follow-up (below).
- No P4b/P4c/P4d work.
- No gitleaks version enforcement; no install of gitleaks.

## Deferral Tracking

One follow-up issue (milestone `Post-MVP / Later`, labels `priority/p3-low`, `domain/engineering`, `meta/machinery`): "Local secret-scan hardening after P4a: (1) PreToolUse `git push` hook so every push by any skill is scanned mechanically (Phase 6.45, 6.5, 7 and `sync-pr-behind.sh` pushes are prose-covered only); (2) tracked-files tip-tree scan so merge-commit-only content is covered locally (measured miss: `--no-merges` rc 0, `-m` and `dir` find it); (3) optional `-diff` blob re-scan". Re-evaluation criterion: re-open when a secret-bearing commit reaches `origin` that the Phase 6 script would have caught had it been run (a push made outside the ship flow or at a later push site), or when a merge-commit-only leak is observed. Filed during planning as #11126 (milestone Post-MVP / Later, labels verified to exist); cite it in the PR body as `Filed: #11126`, with a gate-override comment if the net-issue-flow gate requires one (P4a closes no issue).

## Guard Contract

### Guard 1 — prepush-secret-scan.sh range scan

**Property.** A secret-shaped string in any non-merge commit of `origin/main..HEAD` makes the script exit 1 before the push, and any run that did not actually scan that range exits 43 or 1, never 0.

**Assembly.** Chokepoints the property quantifies over: (a) the single `gitleaks git` invocation and its `--log-opts` range string; (b) the verdict derivation (rc, report, scanned cross-check) — the only place `CLEAN` / exit 0 is produced; (c) the exit-code contract consumed by SKILL.md (only 0 and 43 continue); (d) the colour pins, the environment scrub and the `timeout` bound wrapped around the call; (d2) the `--base` validation and SHA resolution that feed `--log-opts`; (e) the call sites in SKILL.md — the Phase 6 pointer must precede `git push -u origin BRANCH_NAME`, and the Phase 6.4 pointer must exist; (f) CI parity: the range string must equal the `--log-opts="--no-merges ${BASE_SHA}..${HEAD_SHA}"` shape in `.github/workflows/secret-scan.yml`. Members drift, so the suite derives (a), (b), (d), (d2) from the script text and (f) from the workflow text rather than listing today's values.

**Mutation matrix:**

| # | Mutation (edit that must drive the suite RED; each mutates ONE argument of the gitleaks call, never a shared BASE variable that would also move N and E) | Expected |
|---|---|---|
| 1 | Range string replaced by an empty range (`HEAD..HEAD`) so nothing is scanned | RED (fixture with a secret in commit 1 expects exit 1) |
| 2 | Own dispatch: gitleaks invocation replaced by `true`; the `true` mutant writes no report, so the real script yields 43 `empty-report` and the mutant must be caught by the missing-report branch; a second variant treats a missing report as CLEAN | RED (known-answer secret fixture; stub gitleaks that exits 0 with a missing report must yield 43) |
| 3 | Second member: fixture has two secret commits after a compliant first; mutant stops reporting after the first finding | RED (findings must name both commits; needs `jq`, a CI-fail / local-skip precondition) |
| 4 | Colour pin removed, measured as THREE separate mutants (PARAMETERS pin only, COUNT pin only, both) on the local gitleaks; any mutant that stays green is recorded as equivalent WITH the measurement and kept as defense in depth, not assumed equivalent | RED for at least the both-removed mutant under `GIT_CONFIG_PARAMETERS='color.diff=always'` |
| 5 | REORDER: the Phase 6 pointer line moved after the `git push -u origin` line in a sandbox copy of SKILL.md (a property about order, so a delete row alone would not prove it); the check is anchored to the Phase 6 heading range, not a global grep for the push command, and asserts the line number moved | RED (structural check asserts pointer line < push line within the Phase 6 block) |
| 6 | `-m` added to the range (flips the merge-only known-answer row to FINDINGS); separately, `--no-merges` dropped (behaviourally equivalent on its own because `git log -p` emits no diff for a merge without `-m`, so it is caught ONLY by the CI-parity string pin) | RED (6a: merge-only row; 6b: parity pin against `secret-scan.yml`) |
| 7 | `--config` argument dropped from the call | RED (a fixture secret of the repo-custom `sk-soleur-` rule, defined at `.gitleaks.toml` and needing no entropy, is found only when the repo pack is in use) |
| 8 | Base validation weakened: a `--base` value containing a space or a leading `-` accepted | RED (argument-injection row expects exit 43 `base-unresolvable`, not a scan) |

Realized as direct assertions rather than mutant runs (exact-code arms, each asserting the exact exit code so a collapse of NOT_RUN to 0/1 or FINDINGS to 0 fails, and rc discrimination: only rc 1 counts as "caught", rc 2/127/126 means the harness or script is broken): every NOT_RUN reason; the sleeping-stub timeout row (`SOLEUR_PREPUSH_SCAN_TIMEOUT=2`; the stub answers `version` instantly, then `exec sleep`; reaped by process group on EXIT; SKIPs on a host with neither `timeout` nor `gtimeout`); the scanned-mismatch row; the no-merge-base row built on the hosted-ship shallow fixture.

**Stub fidelity.** Stub gitleaks binaries accept exactly the argv shape the script is specified to send and exit 64 on anything else (with the refusal log asserted empty on the pristine run), so a selector mutation cannot hide behind a lenient stub; the stub's `N commits scanned.` line is captured from the real binary's output once, not hand-written.

**Harness rows.** (i) Suite edit that must drive it RED: change the secret fixture to a shape the repo `.gitleaks.toml` allowlists (so the "positive" fixture cannot be found) -> the suite's precondition (`gitleaks dir` over the fixture tip must report a finding BEFORE any RED assertion is trusted) must fail loudly rather than let the RED row pass vacuously. (ii) Must-PASS inputs that are NOT the canonical clean case: a 3-commit range including a binary file and a benign string with no keyword context (a SHA-256 hex or base64 blob; default-pack entropy rules differ between 8.24 and 8.30), and an empty-commit range (`range=1 scanned=0`, no patch so no cross-check) must both exit 0 with `verdict=CLEAN`, proving a guard that rejects everything fails; plus a stub whose scanned line is unparseable must still yield CLEAN with `scanned=?` (format drift must not disable the scan). (iii) Instrument control: the pristine script exits 0 on the clean fixture under the same hermetic env, before any mutant result is read. The suite binds `FLOOR=N` on the line directly above `if [ "$PASS" -lt "$FLOOR" ]` so `scripts/guard-vacuity-floor.test.sh` can build its mutant; `FLOOR` counts only the always-run stub arms, and the real-binary arms FAIL (not skip) under `CI=true` per ADR-188, so a locally skipped arm can never lower a fixed floor below its contract.

**Anchor.** (1) The SKILL.md byte ceiling is anchored to the merge base by `lint-skill-body-budget.py` (a same-diff raise cannot pass); (2) CI parity (f) is anchored to `secret-scan.yml`, an independent file the same diff would have to edit in lockstep, and the suite asserts the workflow still contains the `--no-merges` range shape; (3) fixtures are synthesized at runtime and validated against the repo's own `.gitleaks.toml`, so the pack the script uses is the pack the test proved. The real-binary known-answer rows are the anti-vacuity anchor: they run in CI, where gitleaks is contracted to be present (ADR-188 FAIL-in-CI, SKIP-locally). (4) The config the script scans with is the PR's own, so the receipt carries `cfg_changed` and CI's `allowlist-diff` job stays the independent anchor for allowlist widening.

## User-Brand Impact

- **If this lands broken, the user experiences:** a ship run that either blocks a clean push with a spurious finding (a delay and a rewrite of an unpublished commit) or, worse, prints CLEAN for a range it did not scan, so a secret-bearing commit is published to the public repository before CI's range scan flags it; the existing CI floor still gates the merge.
- **If this leaks, the user's data / workflow is exposed via:** a platform credential committed to this public repository's history (the receipt and findings output never include the secret body or author emails: `--redact`, raw gitleaks output is never echoed, the report is read only for `RuleID`/`File`/`StartLine`/`Commit`, and the temp report is removed on exit).
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** the change only ADDS a pre-push layer; every existing floor (CI range arm, `gitleaks dir .`, staged scan) is unchanged, so a broken script cannot make the baseline worse, which is why it is not `single-user incident`; flip it if the reviewer judges a false CLEAN to be the incident.

## Observability

```yaml
liveness_signal:
  what: "PREPUSH_SECRET_SCAN receipt line on stdout on every run"
  cadence: "per ship run, once before each push"
  alert_target: "the ship transcript and the PR-body line secret-scan: not run (<reason>) when NOT_RUN"
  configured_in: "plugins/soleur/skills/ship/scripts/prepush-secret-scan.sh"
error_reporting:
  destination: "stdout receipt plus stderr findings summary in the ship session"
  fail_loud: "verdict=FINDINGS exit 1 names commit, file, line, rule id; any unknown exit code is a STOP"
failure_modes:
  - mode: "gitleaks absent, unrunnable or timed out"
    detection: "receipt verdict=NOT_RUN reason=gitleaks-absent|gitleaks-unrunnable|timeout"
    alert_route: "ship PR-body line; CI secret-scan.yml remains the gate"
  - mode: "scan ran but looked at nothing (mis-ranged or no-op)"
    detection: "scanned-mismatch cross-check yields verdict=NOT_RUN reason=scanned-mismatch, never CLEAN; real-binary known-answer rows fail in CI if the range or config breaks"
    alert_route: "same receipt; required test check on the PR that changes the script"
  - mode: "CI parity drift (workflow range arm changes)"
    detection: "suite parity pin against .github/workflows/secret-scan.yml fails in CI"
    alert_route: "required test check on the PR that changes the workflow"
logs:
  where: "ship session transcript; no persistent log is written"
  retention: "session lifetime"
discoverability_test:
  command: bash plugins/soleur/skills/ship/scripts/prepush-secret-scan.sh --no-fetch
  expected_output: PREPUSH_SECRET_SCAN
```

## Implementation Phases

### Phase 0 — RED first (`cq-write-failing-tests-before`)

Write `plugins/soleur/test/ship-prepush-secret-scan.test.sh` (it fails: script absent). Layer: integration by content (real gitleaks, real git, PATH-stub processes); the repo classifies a `*.test.sh` as `unit`, so no `e2e` marker is needed. Fixtures: bare `mktemp -d` roots registered in one owning EXIT trap installed before sourcing `test-helpers.sh`, deleted with `rm -rf "${VAR:?}"`; temp repos built with the hermetic env from `plugins/soleur/test/lib/git-fixture-env.sh`, passed to the script under test as well (it is a transitive git spawn, and its own `GIT_CONFIG_COUNT` export must not clobber the hermetic identity); a copy of the repo's `.gitleaks.toml`; the secret is assembled at runtime from split `printf` arguments so the suite source never contains a contiguous secret shape (the suite lives under `plugins/soleur/test/`, which `.gitleaks.toml` does not allowlist, so CI scans it; model: `_mk_pem` in `.claude/hooks/git-commit-secret-scan.test.sh`; validate every chosen body against the repo `.gitleaks.toml`, because a body that triggers under the default pack can be clean under the repo config, observed during planning with a "synthetic"-worded body). Two fixture shapes: a PEM-shaped key and a `sk-soleur-` custom-rule token. The fixture file path inside the temp repo must not match the copied toml's path allowlists. Unreachable origin = a nonexistent local path, never a network host. `jq` and a real gitleaks are preconditions that SKIP locally with the cause and FAIL under `CI=true` (ADR-188; `plugins/soleur/test/lib/gitleaks-probe.sh` `gl_probe`/`gl_run` record skips but do not enforce this, so the suite adds the CI-fail). Bind `FLOOR=N` directly above the `-lt "$FLOOR"` test, counting stub arms only.

### Phase 1 — the script

Implement per Proposed Solution. `set -uo pipefail` (no `-e`); header carries the exit contract, the receipt grammar, the documented limitations (merge-only content, `-diff`, version skew 8.30.1 local vs 8.24.2 CI, PR-controlled config, shallow clones, `--base` is a selector) and the reason 43 is odd. Bash pitfalls pinned: no `local x=$(...)`, rc and output in separate statements, explicit `exit "$final_rc"`, never echo raw gitleaks output, bash 3.2 empty-array idiom.

### Phase 2 — wiring and docs

SKILL.md pointer edits with exact byte accounting (`wc -c` before/after; `python3 scripts/lint-skill-body-budget.py --base "$(git merge-base origin/main HEAD)"`); one subsection plus one layering-table row in `knowledge-base/engineering/operations/secret-scanning.md` ("Local pre-push range scan": what it scans, exit contract pointer to the script header, remedy, the limitations).

### Phase 3 — registries (measured, not guessed)

- `scripts/lib/test-affected-paths.sh`: add `AFFECTED_PLUGINS_SOLEUR_TEST_SHIP_PREPUSH_SECRET_SCAN_TEST_SH_PATHS` with only what the suite reads: the script, SKILL.md, the suite, `plugins/soleur/test/test-helpers.sh`, `plugins/soleur/test/lib/gitleaks-probe.sh`, `plugins/soleur/test/lib/git-fixture-env.sh`, `.gitleaks.toml`, `.github/workflows/secret-scan.yml` (parity pin), `scripts/lib/scratch-root.sh` if `test-helpers.sh` pulls it (use the `_CLOSURE_LEAF_SCRATCH_ROOT` closure as `battery-owed` does), and itself. Editing this file escalates the local affected gate to the full battery (rc=4 on a contended host): run the covering suites directly and let CI be the gate.
- `plugins/soleur/test/fixture-relative-assert.baseline.txt`: regenerate with `--write-baseline` only if the suite has counted operands (the comparable #8255 commit added one row); use bare `mktemp -d` (a path-bearing template adds sites).
- `scripts/suite-shard-legs.tsv` (+ `.n`) via `regenerate-shard-manifest.py`; `scripts/suite-durations.tsv` (+ `.n`) is warn-only for unmeasured rows.
- `scripts/ci-pr-affected-audit.baseline.tsv` is a shrink-only ratchet: add no rows there; `affected-index-ratchet` is advisory and already red from main's drift, but a new suite or a changed file a suite names adds pairs: add anchor-keyed rows to `scripts/ci-pr-affected-audit.accept.tsv` ONLY for pairs where the suite merely names the file, enumerating uncovered boundary lines with `scripts/ci-pr-affected-replay.py pair_anchors` (CI prints only 3 refs per pair).
- `scripts/test-affected-kb-consumers.baseline.txt`: only if the suite names `knowledge-base` (avoid naming it); otherwise regenerate detached with `--write-baseline` and confirm the diff adds only our rows.
- `.claude/hooks/grep-q-pipe-guard.test.sh` PJ_TRIPLES: avoid piping into `grep -q`; if unavoidable, add the triple (conflicts often).
- Run `bash scripts/lint-orphan-test-suites.sh`, `bash scripts/markdown-lint.sh --repo-sweep` and the pipe-guard test locally before pushing.

### Phase 4 — verify

Suite green with the mutation rows (run detached, watch an rc file; foreground commands time out at 120 s); `shellcheck` on the script and suite; the measured merge-only row; the script over this branch's own range prints `verdict=CLEAN`; `bun test plugins/soleur/test/components.test.ts`; the merge-base `lint-skill-body-budget.py`; `bash scripts/guard-vacuity-floor.test.sh`; `python3 scripts/lint-guard-contract.py`.

### Phase 5 — ship

Before any commit or merge run `git config user.name; git config user.email` and remove `t`/`t@t` from the shared bare-repo config if present. PR body: `Ref #9757`, no closing keyword (assert `gh pr view --json closingIssuesReferences` is `[]` after every body edit), `Filed: #<follow-up>` line, `## Changelog`, `semver:patch`. Tick the P4a checkbox in #10924's body (do not close it). No ADR in this PR, so no ordinal race. Merge via `gh pr merge <N> --squash --auto` (never `--admin`); once queued, do not push or sync.

## Files to Create

- `plugins/soleur/skills/ship/scripts/prepush-secret-scan.sh`
- `plugins/soleur/test/ship-prepush-secret-scan.test.sh`
- `knowledge-base/project/specs/feat-one-shot-10924-p4a-gitleaks-pre-push/tasks.md`
- `knowledge-base/project/specs/feat-one-shot-10924-p4a-gitleaks-pre-push/decision-challenges.md`

## Files to Edit

- `plugins/soleur/skills/ship/SKILL.md` (pointer-only, net target <= 0 bytes)
- `knowledge-base/engineering/operations/secret-scanning.md` (one subsection + one layering-table row)
- `scripts/lib/test-affected-paths.sh`
- `scripts/suite-shard-legs.tsv` and `scripts/suite-shard-legs.tsv.n` (generated)
- `scripts/suite-durations.tsv` (+ `.n`) (a measured row for the new suite)
- `plugins/soleur/test/fixture-relative-assert.baseline.txt` (only if counted operands)
- `scripts/ci-pr-affected-audit.accept.tsv` (only for merely-named pairs, measured)

Deliberately NOT edited: `.claude/hooks/*`, `.claude/settings.json`, `AGENTS.rules.md`, `.github/workflows/*`, `apps/**`, `scripts/registry-restore-from-ghcr.sh`, `plugins/soleur/test/skill-body-budget.json`.

## Open Code-Review Overlap

None. (`gh issue list --label code-review --state open` searched for `ship/SKILL.md`, `ship/scripts`, `ship-unpushed-commits-gate.sh`, `skill-body-budget.json`: zero matches.)

## Domain Review

**Domains relevant:** Engineering (CTO consulted as technical-ruling authority; no other domain implicated)

### Engineering

**Status:** reviewed
**Assessment:** Five design forks ruled by the CTO agent on 2026-10-26 (see Technical Rulings). Cross-domain sweep: no product/UI surface (no `components/`, `app/` paths), no marketing/legal/finance/sales/support implication; GDPR gate not triggered (no schema, auth, API route, or personal-data processing; fixtures are synthesized; the script never echoes author emails).

## Architecture Decision (ADR/C4)

No ADR and no C4 change. The test applied: would a competent engineer reading only the existing ADRs and C4 be misled about the system after this ships? No. This adds a skill-run gate and a script; no ownership/tenancy boundary, substrate, trust boundary or ADR reversal. C4 completeness: external actors/systems (GitHub remote, gitleaks binary) and the CI secret-scan edge already exist in `model.c4` (grep of `gitleaks`/`secret` hits `model.c4`); no new container, store, or actor-surface relationship. `c4-count-parity` is not moved (no workflow, monitor, or heartbeat added).

## Acceptance Criteria

### Pre-merge (PR)

- [x] `prepush-secret-scan.sh` exits `1` with `verdict=FINDINGS` for a range whose FIRST commit adds a secret and whose second commit removes it, printing commit/file/line/rule id and no secret bytes or author email; both a PEM-shaped and a `sk-soleur-` fixture are found (the second proves `--config` is the repo pack).
- [x] Exits `0` with `verdict=CLEAN range=<N> scanned=<M|?>` for a clean range, an empty range (`range=0`), an empty-commit range (`range=1 scanned=0`), a 3-commit range with a binary file and a keyword-free high-entropy string, and a clean range whose gitleaks scanned line is unparseable (`scanned=?`).
- [x] Exits `43` with `verdict=NOT_RUN`, a loud stderr WARN and a final `secret-scan: not run (<reason>)` line for: gitleaks absent, gitleaks unrunnable, gitleaks resolving inside the repo, timeout, `.gitleaks.toml` absent, `base-unresolvable`, `no-merge-base` (depth-1 clone), a missing or zero-byte report (including rc 0 with no report), `scanned-mismatch`, and any other gitleaks rc. No other path exits `0` or `43`; rc 1 with a non-empty report is FINDINGS even when the report does not parse.
- [x] `--base` containing a space, a leading `-` or a revision expression is rejected without running a scan; only a 40-hex SHA reaches `--log-opts`.
- [x] The script scrubs the ambient git/gitleaks environment (`GIT_DIR`, `GIT_INDEX_FILE`, `GIT_EXTERNAL_DIFF`, `GIT_REPLACE_REF_BASE`, `GITLEAKS_*` unset; `GIT_NO_REPLACE_OBJECTS=1`); a suite row exports a hostile value for at least two of them and still gets the right verdict. Temp files live in one `umask 077` `mktemp -d` removed on EXIT/INT/TERM (suite asserts the dir is gone after both a clean and a FINDINGS run).
- [x] Every printed field passes the ASCII allowlist with a length cap: a fixture file name containing an ANSI escape and a newline appears sanitized in the output.
- [x] Failed `git fetch` yields `fetch=stale` and still scans; `--no-fetch` yields `fetch=skipped`; the receipt prints full `base=` and `head=` SHAs; `cfg_changed=1` when the range touches `.gitleaks.toml`, `.gitleaksignore` or `.gitattributes`.
- [x] Findings still exit `1` under `GIT_CONFIG_PARAMETERS='color.diff=always'`; the three colour-pin mutants are MEASURED (RED, or recorded equivalent with the measurement).
- [x] The merge-commit-only secret case is pinned as a known answer: the `--no-merges` range exits `0`, a `-m` mutant exits `1`, and the same fixture's tip is shown to contain the secret by a `gitleaks dir` positive control; the script header and the runbook subsection state the limitation and no doc claims merge-resolution coverage.
- [x] Range string parity: the suite asserts `.github/workflows/secret-scan.yml` still contains `--log-opts="--no-merges ${BASE_SHA}..${HEAD_SHA}"` and the script uses `--no-merges BASE_SHA..HEAD`.
- [x] SKILL.md: the Phase 6 pointer line precedes `git push -u origin BRANCH_NAME` within the Phase 6 block (structural check on a sandbox copy); it carries the runnable `bash "${CLAUDE_PLUGIN_ROOT}/skills/ship/scripts/prepush-secret-scan.sh"` command, "check the exit code, no pipe", the 0/43/else rule, the `127` plugin-root note, the "append the printed `secret-scan:` line to the PR body" instruction and the headless-FINDINGS-aborts rule; Phase 6.4 carries the pointer ("Phase 6's secret scan"); `wc -c plugins/soleur/skills/ship/SKILL.md` <= 273,839 (net <= 0; hard ceiling 273,955) and `python3 scripts/lint-skill-body-budget.py --base "$(git merge-base origin/main HEAD)"` passes; `bun test plugins/soleur/test/components.test.ts` passes.
- [x] Every Guard Contract mutation row (1-8) is realized in the suite as a mutant run that the suite's assertions turn RED (row 4 and 6b as measured above); stubs are argv-strict; the direct-assertion arms, harness rows (i)-(iii) are realized; `FLOOR=N` is on the line directly above `if [ "$PASS" -lt "$FLOOR" ]`; the real-binary arms FAIL under `CI=true` when skipped; `bash scripts/guard-vacuity-floor.test.sh` does not grow its ratchet. **Measured at work time: rows 7 (`--config` dropped) and 8 (`--base` regex removed) are EQUIVALENT mutants** (gitleaks auto-discovers `.gitleaks.toml` from the repo it scans; the SHA resolution that follows rejects the same inputs), recorded with their measurements in the suite rather than asserted RED; row 4's COUNT-pin-only mutant is likewise equivalent while the PARAMETERS pin exists.
- [x] `python3 scripts/lint-guard-contract.py` passes on this plan; `bash scripts/lint-orphan-test-suites.sh`, `bash scripts/markdown-lint.sh --repo-sweep` and the pipe-guard test pass locally; `scripts/suite-durations.tsv` carries a measured row for the new suite. **`scripts/suite-durations.tsv` was NOT edited:** it is generated from CI timing artifacts (`generated-from-runs=`), hand rows conflict with its generator, and unmeasured rows are warn-only.
- [x] Diff scope: `git diff --name-only origin/main...HEAD` contains none of `.claude/hooks/`, `.claude/settings.json`, `AGENTS.rules.md`, `.github/workflows/`, `apps/`, `scripts/registry-restore-from-ghcr.sh`, `plugins/soleur/test/skill-body-budget.json`.
- [ ] PR body has `Ref #9757`, no closing keyword (`gh pr view --json closingIssuesReferences` -> `[]`), a `Filed: #11126` line for the follow-up, and `## Changelog`; #10924's P4a checkbox ticked, issue left open.

## Test Scenarios

(Layers: integration by content — real gitleaks, real temp git repos, PATH-stub processes; mutants are copies of the script; no `e2e`. The repo classifies `*.test.sh` as `unit`.)

- Given a range whose first commit adds a synthesized secret and second removes it, when the script runs, then exit 1, `verdict=FINDINGS`, output names commit/file/rule, output contains no secret bytes.
- Given two secret commits after a clean first, then both are named.
- Given a `sk-soleur-` token commit, then FINDINGS (repo pack in use).
- Given an empty range, then exit 0 `range=0`; given one empty commit, then exit 0 `range=1 scanned=0`.
- Given a 3-commit clean range with a binary file and a keyword-free high-entropy string, then exit 0.
- Given `PATH` without gitleaks (constructed PATH of symlinks), then exit 43 `reason=gitleaks-absent`; given a shim that exits 127 on `version`, then exit 43 `reason=gitleaks-unrunnable`; given a gitleaks that resolves inside the repo, then 43 `gitleaks-in-repo`.
- Given a stub gitleaks that answers `version` then `exec sleep` with `SOLEUR_PREPUSH_SCAN_TIMEOUT=2`, then exit 43 `reason=timeout` (SKIP where neither `timeout` nor `gtimeout` exists); given a stub that exits 1 with no/zero-byte report, then 43 `empty-report`; given a stub that exits 0 with no report, then 43; given a stub that exits 1 with a non-parseable non-empty report, then exit 1 FINDINGS; given a stub that prints `0 commits scanned.` for a range with a patch, then 43 `scanned-mismatch`; given a stub whose scanned line is unparseable and report `[]`, then exit 0 `scanned=?`; given a stub invoked with an unexpected argv, then it exits 64 and the pristine run's refusal log is empty.
- Given no `.gitleaks.toml`, `--base nonexistent`, `--base "a b"`, `--base -x`, then 43 and no scan; given a depth-1 clone fixture (hosted-ship shape), then 43 `no-merge-base`.
- Given an unreachable `origin` (nonexistent local path), then `fetch=stale` and the scan still runs.
- Given `GIT_CONFIG_PARAMETERS='color.diff=always'`, `GIT_EXTERNAL_DIFF` and `GIT_INDEX_FILE` pointing elsewhere exported, then the secret fixture still exits 1 (and the foreign index is untouched).
- Given a secret only in a conflict-resolution merge commit, then exit 0 (documented limitation), a `-m` mutant exits 1, and `gitleaks dir` over the fixture finds it.
- Given a range that edits `.gitleaks.toml`, then `cfg_changed=1`.
- Given a fixture file name with an ANSI escape and a newline, then the printed finding is sanitized.
- Given the SKILL.md text, then pointer line < push line in the Phase 6 block; Phase 6.4 pointer present; the script path in the pointer exists.
- Regression: `.claude/hooks/ship-unpushed-commits-gate.sh` and the Phase 6.4 headless snippet are unchanged versus origin/main.

## Dependencies & Risks

- **Byte ceiling (116 bytes), shared with every PR touching ship SKILL.md.** Mitigation: pointer-only edit with named trims and a net <= 0 target; verify with the merge-base lint before pushing; a queue collision with another SKILL.md edit is the residual risk.
- **False reassurance.** A CLEAN receipt does not mean "no secret in the PR": merge-only content and `-diff` paths are outside it; CI's `gitleaks dir .` remains the net. The script header and runbook say so.
- **Version skew (8.30.1 local vs 8.24.2 CI).** A newer local pack can flag something CI does not; treated as a STOP, and the receipt prints the version.
- **Registry churn.** `scripts/lib/test-affected-paths.sh` edits escalate the local affected gate (rc=4 on a contended host); run the covering suites directly and rely on CI.
- **Fixture trap.** The suite file itself is scanned by CI's secret scan; secrets are assembled at runtime and fixtures validated against the repo config.
- **Only the first push is structural.** Later push sites rely on the pointer; the deferred hook is the mechanical answer. Under one-shot the branch is already on `origin` (the `draft-pr` step pushed an init commit), so the Phase 6 push is the first push of real commits and the PR-exists arm is the common one. The Phase 6.5 conflict-resolution push (a merge commit, the documented blind spot) is prose-only; the deferred tip-tree scan covers it.
- **PR-controlled config.** The scan uses the working-tree `.gitleaks.toml`/`.gitleaksignore` (CI parity); a PR that widens its own allowlist can scan itself clean locally. Receipt `cfg_changed` plus CI's `allowlist-diff` job are the backstops. Ruled: keep parity rather than scanning with the base config, which would block every legitimate allowlist PR.
- **Attacker-inducible NOT_RUN.** A huge blob or long range can force `timeout`/`scanned-mismatch` and so exit 43 ("continue"). Accepted per CTO Fork 2 (CI is the load-bearing gate) with a loud stderr WARN; flip to a STOP code if a real case is observed.
- **Detached HEAD / no `origin/main` (default branch `master`, fork remote).** Detached HEAD is not handled specially (`git push origin BRANCH_NAME` fails first); a missing `origin/main` is NOT_RUN `base-unresolvable` on every run, visible in the receipt.

## References

- `plugins/soleur/skills/ship/SKILL.md` Phase 6.4 and Phase 6 push preamble; `.claude/hooks/ship-unpushed-commits-gate.sh`; `.claude/hooks/git-commit-secret-scan.sh`; `.github/workflows/secret-scan.yml`; `knowledge-base/engineering/operations/secret-scanning.md` (Ref scope per event; why only the cron gets `-m`); `plugins/soleur/skills/ship/scripts/battery-owed.sh` (exit-contract precedent); `plugins/soleur/test/lib/gitleaks-probe.sh`.
- Issues: #10924, #9757. Preceding art: #8247 (battery-owed), #8266 (runnable probe), #3121 (the "Secret-scanning floor" cited by the `secret-scan.yml` and `lefthook.yml` headers).
