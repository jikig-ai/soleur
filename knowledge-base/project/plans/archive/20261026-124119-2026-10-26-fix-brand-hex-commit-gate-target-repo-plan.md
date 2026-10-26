---
title: "fix(hooks): brand-hex-commit-gate scans the repository a git commit targets, not the hook process cwd"
date: 2026-10-26
slug: brand-hex-commit-gate-target-repo
branch: feat-one-shot-10793-brand-hex-gate-target-repo
issue: 10793
closes: 10793
type: fix
lane: single-domain
priority: p3
domain: engineering
brand_survival_threshold: none
requires_cpo_signoff: false
---

# fix(hooks): brand-hex-commit-gate scans the repository a git commit targets

## Enhancement Summary

**Deepened on:** 2026-10-26
**Sections enhanced:** Scope Check (schema-complete), Observability (5-field block), Research Insights (empirical probe), Sharp Edges
**Research agents used:** CTO ruling agent (5 interpretation forks, carve-outs A-C folded in), scratch-repo probe of the lib, guard-contract lint

### Key Improvements
1. Every Design assumption about `ctr_collect` / `ctr_resolve_roots` / `CTR_COMMIT_ALL` was confirmed on a real bare-root + worktree fixture rather than from the lib header.
2. Scope Check now carries the Ask Mapping / Provenance / Split Assessment tables the deepen halt verifies; the one inferred item is justified.
3. The bare-root cwd toplevel failure (rc 128) is pinned as "no cwd root", not an undeterminable error.

### New Considerations Discovered
- The sibling secret-scan hook blocks inline shell text that pairs a variable path with git commit; fixture probes run from script files.
- The CTO's carve-out A (lexer unavailable, no target-moving token -> unchanged cwd path) prevents a perl-less host from silencing the gate on every plain commit.


## Overview

`.claude/hooks/brand-hex-commit-gate.sh` blocks a commit that adds raw hex colour literals to staged
UI/template files. It finds the repository to inspect from the hook PROCESS working directory
(`git rev-parse --show-toplevel`, then `cd`). When the session is anchored at a `core.bare=true`
root, a commit aimed at a linked worktree through `cd <worktree> && git commit ...` or
`git -C <worktree> commit ...` is never inspected: the toplevel lookup fails and the hook allows.
This is the same defect #10609 fixed for `git-commit-secret-scan.sh`, which solved it with
`.claude/hooks/lib/commit-target-roots.sh` (`ctr_collect` + `ctr_resolve_roots`).

A second, independent hole sits in front of that: the gate's trigger regex needs the two words
`git commit` adjacent, so `git -C <worktree> commit` never even reaches the scan. The hook header
claims the regex is "identical" to the secret scan's, which stopped being true when #10609 widened
the secret scan's trigger.

CTO ruling (issue comment 6411990414, 2026-10-23, not re-litigated): ship as its own small PR;
resolve targets with the existing lib; when the target is undeterminable the gate WARNS AND ALLOWS
(fail-open by design, no secret-leak blast radius); the no-cd path stays unchanged; the header
comment is corrected; `lib/commit-index-sim.sh` is NOT adopted here (follow-up, ADR-301);
`git-commit-secret-scan.sh` and the sim lib are not touched.

PR body lines: `Closes #10793`, a separate non-closing `Ref #10331` (closed code-quality epic, never
reopen) and `Ref #10609`.

## Research Reconciliation — Spec vs. Codebase

| Claim (issue / brief) | Reality (origin/main, this worktree) | Plan response |
|---|---|---|
| "The header comment says the trigger regex is identical to the secret scan's" | Header lines 16-17 already say the regex "began as an identical copy and has not followed that hook's #10609 widening. KNOWN LIMITATION (#10793): cwd-bound." (PR #10893 / #10609 partial edit). The in-body comment above the trigger (lines 116-118) still says "(identical to git-commit-secret-scan.sh)". | Rewrite both: the header names the lib, the loose trigger and the warn-and-allow disposition and drops the KNOWN LIMITATION; the in-body comment states how the trigger now differs from the secret scan's (strict match unchanged, plus a loose both-words test confirmed by the lexer). |
| "`cd <worktree> && git commit` from a bare-root cwd is not scanned" | True. Strict regex matches, then `git rev-parse --show-toplevel` fails at the bare root (`--is-inside-work-tree` prints `false` with rc 0, so the existing "not inside git work tree" guard does not fire either) and `[ -n "$repo_root" ] \|\| allow` ends the hook. | Fix via `ctr_collect` / `ctr_resolve_roots`. |
| "`git -C <worktree> commit` is not scanned" | True and deeper than the issue states: the strict regex does not match `git -C W commit` at all, so the hook allows before any repository lookup, even from inside a work tree (a `-C` that points at a DIFFERENT repo is skipped too). | Add the loose trigger (both words `git` and `commit`) confirmed by the lexer's commit record, exactly as the secret scan does. |
| "Reuse `commit-target-roots.sh`" | The lib is sourced fail-soft and checked explicitly by the secret scan (`declare -f ctr_collect`, `declare -f ctr_resolve_roots`, `CTR_STAGE_API=1`); its denies are the secret scan's policy, not the lib's. The lib itself never denies. | This gate sources the lib the same way but maps every "cannot determine" outcome to warn+allow. It does NOT source `commit-index-sim.sh` and does not test `CIS_API`. |
| `-a` detection `${command#*git commit}` | For `git -C W commit -a` the pattern does not match, so the whole command text would be scanned for a `-a` flag. | Keep the textual regex when the literal words `git commit` are present (no-cd path byte-for-byte unchanged); use the lexer's `CTR_COMMIT_ALL` only when they are not. |

## Research Insights

**Premise Validation (Phase 0.6).** #10793 is OPEN; its CTO comment names "after #10696" and that
landed (PR #10893, ADR-301). #10609 and #10331 are CLOSED (referenced with `Ref` only).
`.claude/hooks/lib/commit-target-roots.sh`, `plugins/soleur/hooks/lib/shell-argv.pl`,
`.claude/hooks/lib/commit-index-sim.sh` all exist on main. ADR corpus: ADR-301 (would-be index) says
the brand-hex gate "reads it first" as a second consumer - consistent with the ruling that sim
adoption is a follow-up; no ADR rejects the cd/-C resolution mechanism (the #10609 CTO table T2/T13
rejected scanning every worktree and rejected denying every no-toplevel commit).

**Property List (Phase 0.6b).**
- P1. A `cd <literal dir> && git commit` or `git [-C <literal dir>] commit` is checked against the staged files of the repository that `<dir>` belongs to, even when the hook process cwd is a bare root.
- P2. The no-cd path (`git commit ...` in the cwd repo) behaves exactly as before.
- P3. When the target repository cannot be determined, the gate warns on stderr, records a bypass row, and allows. It never denies, asks, or silently scans a repository the commit may not target.
- P4. A quoted mention of git commit that is not a commit does not newly trigger a scan.
- P5. The diff base (`--cached` vs `HEAD`) follows the commit's own `-a` flag for the `-C` form as for the plain form.
- P6. The hook header and in-body comment no longer claim an identity with the secret scan's trigger.

**Cut List.** (a) Adopting `commit-index-sim.sh` (scan the would-be index of a chained add-then-commit): buys no property above; explicitly a follow-up per the CTO ruling and ADR-301. (b) Adding the payload-`cwd` (`HOOK_CWD`) root to the scanned set: would change the no-cd path (P2); cut per CTO ruling Q2. (c) A deny/ask disposition for an undeterminable target: contradicts P3 and the ruling. (d) A new shared "resolve roots" helper extracted from the secret scan's `add_root_of`: the secret scan is not to be touched; the gate needs only a 6-line dedup.

**Institutional learnings applied.**
- Hook test suites redirect the incident sink via `lib/test-incident-sandbox.sh` (already sourced by the suite).
- `grep -q` over a pipe under `pipefail` SIGPIPEs the producer (#6992): use herestrings, never `printf | grep -q`, in any new hook code. `grep-q-pipe-guard.test.sh` enforces this.
- Bash 5.2 (CI) vs 5.3 (host): write `return 0` explicitly in any function reached from a trap handler; this change adds no trap, but new functions end in explicit `return 0`.
- Pin `LC_ALL=C` on any git call whose English error text is matched (the lib already does; the gate matches none).
- Text containing the words git commit inside a quoted argument of a shell command trips the commit-on-main guard: commit messages and the PR body go through `-F` / `--body-file`.

**Deepen-pass verification (empirical, scratch repo with a `core.bare=true` root and a linked worktree).** `git rev-parse --is-inside-work-tree` at the bare root prints `false` with rc 0; `git rev-parse --show-toplevel` exits 128 with "this operation must be run in a work tree". `ctr_collect`+`ctr_resolve_roots` returned the worktree toplevel for `cd <abs wt> && git commit`, `git -C <abs wt> commit`, and the relative `cd .worktrees/wt && git commit` (resolved against the bare-root `$PWD`); `CTR_COMMIT_ALL=1` for `git -C <wt> commit -a` and `-p`, 0 otherwise; `cd "$WT" && git commit` -> `CTR_BAD` = "the path '$WT' contains an expansion" with empty roots; a quoted prose mention -> `CTR_COMMIT_SEEN=0`; `cd /nonexistent && git commit` -> empty roots and empty `CTR_BAD` (so it falls to the cwd root). The baseline suite prints `=== 24 passed, 0 failed ===`. All Design assumptions hold.

**Decisions** (full rows in `knowledge-base/project/specs/feat-one-shot-10793-brand-hex-gate-target-repo/decision-challenges.md`): all technical, ruled by the CTO agent on 2026-10-26 on top of the 2026-10-23 issue ruling.

## Open Code-Review Overlap

One open code-review issue names a file this plan edits: #8800 (census sandbox shares inodes/symlinks with the live repo) touches `scripts/lib/test-affected-paths.sh`. **Acknowledge:** a different concern (census sandbox isolation); this PR edits one existing `AFFECTED_*_PATHS` array and does not touch the census. It stays open.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "`cd <worktree> && git commit` and `git -C <worktree> commit` from a bare-root cwd are checked against the worktree's staged files" | Design steps 1-5, 7; Phases 1-2; AC1, AC2 | mapped |
| 2 | "the no-cd path is unchanged" | Design step 6 (textual diff-base regex kept), Cut List (b); AC3; tests T27, T28 | mapped |
| 3 | "When the target is undeterminable the gate WARNS AND ALLOWS" | Design step 4; AC4; tests T33-T35 | mapped |
| 4 | "the header comment is corrected" | Phase 3.1; AC7; test T36 | mapped |
| 5 | "Resolve the commit's target repositories with the existing lib .claude/hooks/lib/commit-target-roots.sh" | Design steps 2-3, 5 | mapped |
| 6 | "Do NOT adopt .claude/hooks/lib/commit-index-sim.sh in this PR ... do not touch git-commit-secret-scan.sh or the sim lib" | Cut List (a); AC9 | mapped |
| 7 | "Tests first (TDD), in the hook's existing suite ... cd form, -C form, bare-root cwd, no-cd unchanged, undeterminable target warns+allows, plus allow twins" | Phase 1; T25-T37 | mapped |
| 8 | "run the repo-global checks a file-selected suite cannot see" and "commit AND PUSH after every logical unit" | Phase 4; AC8, AC10 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Loose both-words trigger | "`git -C <worktree> commit` from a bare-root cwd" (the strict regex cannot see this form) | asked |
| Per-root palette reset and root-basename prefix | "checked against the worktree's staged files" (a second root needs its own palette; CTO Q2/Q5) | asked |
| Lexer-unavailable split on target-moving tokens | "The no-cd path stays unchanged" (a perl-less host must not go silent on plain commits; CTO carve-out A) | asked |
| `CTR_COMMIT_ALL` for the -C diff base | "`git -C <worktree> commit` ... checked against the worktree's staged files" (CTO Q3) | asked |
| README paragraph and guardrail-audit consumer text | — | inferred — justification: the repo keeps hook behaviour documented in .claude/hooks/README.md and the manifest test requires guardrail-audit.md to stay accurate; two short text edits, no code |
| `scripts/lib/test-affected-paths.sh` array edit | "run the repo-global checks a file-selected suite cannot see" (declare real reads in ONE AFFECTED_*_PATHS definition) | asked |

### Split Assessment

- Subsystems touched: 2 - `.claude/hooks/`, `scripts/lib/` (plus one text edit under `plugins/soleur/skills/verification-scaffold/references/` and a possible re-key in `plugins/soleur/test/`)
- Planned files: 7 edited + 2 created | Estimated changed lines: ~420 (about 300 test, 90 hook, 30 other)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Files to Edit

- `.claude/hooks/brand-hex-commit-gate.test.sh` - tests first (Phase 1).
- `.claude/hooks/brand-hex-commit-gate.sh` - target resolution, loose trigger, per-root scan, warn+allow, header/in-body comment (Phases 2-3).
- `scripts/lib/test-affected-paths.sh` - add `.claude/hooks/lib/commit-target-roots.sh` and `plugins/soleur/hooks/lib/shell-argv.pl` to the EXISTING `AFFECTED_CLAUDE_HOOKS_BRAND_HEX_COMMIT_GATE_TEST_SH_PATHS` array (edit in place; a second definition fails the test-all-affected suite).
- `plugins/soleur/test/boundary-prefix.test.sh` - re-key the `.claude/hooks/brand-hex-commit-gate.sh:119` exemption only if the strict-trigger line moves (the plan keeps it at 119 by leaving lines 1-121 line-count-neutral; verify, do not assume).
- `scripts/ci-pr-affected-audit.accept.tsv` - only if the ratchet reports a pair where a suite merely NAMES a file (see Phase 4); real reads are declared in `test-affected-paths.sh` instead.
- `.claude/hooks/README.md` - one short paragraph: the brand-hex gate resolves its target through the same lib and warns-and-allows when it cannot.
- `plugins/soleur/skills/verification-scaffold/references/guardrail-audit.md` - the `lib/commit-target-roots.sh` row names the brand-hex gate as a second consumer (text only; the manifest test checks that every hook/lib file appears, which already holds).

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-10793-brand-hex-gate-target-repo/tasks.md`
- `knowledge-base/project/specs/feat-one-shot-10793-brand-hex-gate-target-repo/decision-challenges.md`

No ADR, no C4 change (see Architecture Decision below).

## Design

Flow of the changed hook (lines after the Bash/`allow` gates; the `(^|...)git commit` strict test keeps its line number):

1. **Trigger.** `strict_match=1` unless the unchanged strict regex fails. If it fails, require both words (`[[ $command == *git* && $command == *commit* ]]`) else `allow` (cheap exit, same as the secret scan's order).
2. **Library.** Resolve `ctr_lib` from `${BASH_SOURCE[0]}` (not `PROJECT_DIR`), source fail-soft, then assert `declare -f ctr_collect`, `declare -f ctr_resolve_roots` and `CTR_STAGE_API=1` (as `git-commit-secret-scan.sh` lines 386-394), setting `ctr_ok`. No `CIS_API` check, no sim lib.
3. **Lex.** If `ctr_ok` and perl exists: `ctr_collect "$command"`.
   - `CTR_LEX_STATE=ok`, `CTR_COMMIT_SEEN=0`: loose-only match (`strict_match=0`) is not a commit -> `allow`; strict match is quoted prose -> drop `CTR_BAD`, skip `ctr_resolve_roots`, continue on the unchanged cwd path.
   - `CTR_LEX_STATE=ok`, `CTR_COMMIT_SEEN=1`: `ctr_resolve_roots`.
   - Lexer unavailable, or lib missing: if the text carries a target-moving token (`cd`, `pushd`, a ` -C`, `--git-dir`, `--work-tree`, `GIT_`) the target is undeterminable; otherwise (strict match, no such token) use the unchanged cwd path, and a loose-only match with no such token allows. This keeps a perl-less host from going silent on every plain commit (CTO carve-out A).
4. **Undeterminable -> warn + allow, no scan.** Undeterminable = `CTR_BAD` non-empty, `CTR_ROOT_ERR` non-empty, lexer unavailable with a target-moving token, or lib missing with one. Print one stderr line `[brand-hex-commit-gate] WARN: cannot determine which repository this git commit targets (<cause, control chars stripped, <=200 chars>) - brand-hex scan skipped.`, `emit brand-hex-commit-gate bypass "target undeterminable: <kind>"`, `allow`. Never `deny`, never an ask envelope.
5. **Roots.** `CTR_ROOTS` (in order) unioned with the process-cwd toplevel (`git rev-parse --show-toplevel`, absent at a bare root), deduped via a small `add_root`. No `HOOK_CWD` root. If the set is empty, keep the existing `emit ... bypass "not inside git work tree"` + `allow`. When roots came from the lexer, `unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR` first (an inherited `GIT_DIR` outranks `cd`).
6. **Diff base (once, applies to every root).** `strict_match=1`: the existing `commit_args="${command#*git commit}"` + quote-stripped `-a/--all` regex, unchanged. `strict_match=0`: `NAME_REF=HEAD` iff `CTR_COMMIT_ALL=1`, else `--cached`.
7. **Per-root scan.** The body from "gather changed files" to the findings loop becomes a function `scan_root <root>` that `cd`s into the root, resets `PALETTE`, `PALETTE_NAME` and `palette_built` (the palette is discovered from THAT repository's committed CSS - a leaked palette would mis-judge email hex), and appends to the global `findings`. When more than one root was scanned, each finding is prefixed with the root's basename (CTO Q5). The deny text and 8-finding cap are unchanged. Functions end in explicit `return 0`.

Known limitation recorded in the header (not fixed here): a commit that stages in the same command (`git add X && git commit`) is judged against the pre-command index; fixing that is the sim-lib follow-up. `git commit <pathspec>` / `-o` / `-i` diff bases are likewise unchanged.

## Implementation Phases

### Phase 0 - Baseline
- 0.1 `cd <worktree> && pwd` (must equal the worktree path). Run `bash .claude/hooks/brand-hex-commit-gate.test.sh`; expect `=== 24 passed, 0 failed ===`. Record it.

### Phase 1 - Tests first (RED), then commit AND push
Add to `.claude/hooks/brand-hex-commit-gate.test.sh` (hex fixtures synthesized inline; no real credentials anywhere):
- Helpers: `_seed_bare_root_with_worktree` (model: `_mk_bare_root_with_worktree` in `git-commit-secret-scan.test.sh`: `git init`, seed globals.css commit, `git config core.bare true`, `git worktree add .worktrees/wt -b wtb`; export PHYSICAL paths with `pwd -P`); `_run_cmd` that sets `OUT`, `ERR`, `RC` and takes an optional PATH-stub dir (model: `_mk_stub_path` there; include `perl` or not); `_expect` that asserts decision, reason substrings, and exit status 0.
- Cases (each deny has an allow twin; ids continue after T24):
  - T25 `cd <wt> && git commit -m x`, cwd = bare root, off-brand hex staged in wt -> deny, reason names the file. T25b same with tokenized content -> allow.
  - T26 `git -C <wt> commit -m x`, cwd = bare root -> deny. T26b clean twin -> allow. T26c `git -C <wt> commit` with cwd INSIDE a different clean repo -> deny (the strict-regex hole).
  - T27 bare-root cwd, plain `git commit -m x` (no cd) -> allow, no WARN (unchanged).
  - T28 no-cd regression: repo cwd, off-brand staged, plain `git commit` -> deny (reason text unchanged); prose `echo "git -C x commit"` with off-brand staged -> allow (CTO carve-out C); `git commit-tree` still allow.
  - T29 diff base: `git -C <wt> commit -a -m x` with an UNSTAGED off-brand edit -> deny; `git -C <wt> commit -m x` same fixture (nothing staged) -> allow; `cd <wt> && git commit -a` unstaged -> deny; `-m 'fix -a flag'` text does not flip the base.
  - T30 two roots: cwd repo clean + `cd <wt>` off-brand -> deny with the wt basename prefix; both clean -> allow. A second case where the CWD repo holds the finding and the named target is clean -> deny (union, not replacement).
  - T31 palette isolation: root A's palette contains the colour `#2563eb`, root B's does not; an email-class file in B using `#2563eb` -> deny (fails if the palette leaks across roots).
  - T32 relative and quoted targets: `cd ./.worktrees/wt && git commit` and `cd "<abs wt>" && git commit` from the bare root -> deny (twin: clean allow); a target that does not exist (`cd /nonexistent-dir && git commit`) falls back to the cwd repo root -> deny when cwd holds off-brand staged content.
  - T33 undeterminable -> warn+allow: `cd "$WT" && git commit`, `cd ~/x && git commit`, `cd wt* && git commit`, `GIT_DIR=/x git commit`, `git --git-dir=/x commit` -> decision allow, exit status 0, stderr contains `WARN` and `cannot determine`, stdout carries NO `deny`/`ask`; with the cwd repo holding off-brand staged content the answer is STILL allow (no scan). Incident ledger gains a `bypass` row naming the gate (read `$SOLEUR_TEST_INCIDENT_ROOT`).
  - T34 no perl: PATH stub without perl; `git -C <wt> commit` -> warn+allow; plain `git commit` in a repo with off-brand staged -> deny (cwd path, silent-gate guard); `cd <wt> && git commit` -> warn+allow.
  - T35 lib missing: copy the hook plus `lib/hook-input.sh` and `lib/incidents.sh` into a temp dir WITHOUT `commit-target-roots.sh`; `git -C <wt> commit` -> warn+allow; plain commit -> unchanged deny.
  - T36 header: `grep -c` the hook for the retired phrase "identical to git-commit-secret-scan" returns 0, and the header names `lib/commit-target-roots.sh` (content anchors, not line numbers).
  - T37 fixture control (harness row): the same off-brand worktree fixture committed from INSIDE the worktree with no cd -> deny; proves a green deny in T25/T26 means the target was resolved, not that the fixture is broken.
- Run: the new cases must FAIL (T25-T26c, T29-T32 deny rows, T33-T36), the allow twins and regression rows pass. Capture the RED list in the commit message file.
- Commit (message via `-F`, ending with the Co-Authored-By line) and **push**.

### Phase 2 - Hook implementation (GREEN), commit AND push
Implement the Design section in `.claude/hooks/brand-hex-commit-gate.sh`. Keep line count of lines 1-121 unchanged where possible (header rewrite is a 2-line for 2-line swap, in-body comment keeps 3 lines) so the boundary-prefix exemption stays at 119. Run the suite until green; run `shellcheck -S warning` on the hook. Commit and push.

### Phase 3 - Comments and ledgers, commit AND push
- Header: replace the "Modelled on ..." paragraph with: modelled on `git-commit-secret-scan.sh` for the JSON contract and fail-open stance; the trigger differs - strict match plus a loose both-words test confirmed by the `commit-target-roots.sh` lexer; the target repositories come from the command text (`cd` / `-C`), and an undeterminable target warns and allows; known limitations (same-command staging, pathspec commits, #10793 follow-up for the sim lib). Update "Fail-open conditions" list accordingly.
- `scripts/lib/test-affected-paths.sh`: add the two paths to the one existing array; `README.md` and `guardrail-audit.md` text.
- Commit and push.

### Phase 4 - Repo-global checks a file-selected suite cannot see (run BEFORE every push from here on; fix, never skip)
1. `bash scripts/check-adr-ordinals.sh`
2. `bash plugins/soleur/test/boundary-prefix.test.sh` - exemptions are keyed on LINE NUMBERS of hook files; if line 119 of the hook moved, re-key `".claude/hooks/brand-hex-commit-gate.sh:119"` to the new strict-trigger line. Also confirm the new loose-trigger and target-moving-token lines do not become unexempt census candidates (they carry no `(^|` + `git `), and that no new variable is named `*BOUNDARY*`/`*PREFIX*` next to a gated literal.
3. `python3 -I scripts/ci-pr-affected-replay.py ratchet` - add an accept row to `scripts/ci-pr-affected-audit.accept.tsv` ONLY for a pair where the suite merely names a file; real reads (the lib, the lexer) are declared in the single array in `test-affected-paths.sh`. Never add a second `AFFECTED_CLAUDE_HOOKS_BRAND_HEX_COMMIT_GATE_TEST_SH_PATHS=` definition.
4. `bash plugins/soleur/skills/verification-scaffold/test/manifest.test.sh`
5. `bash .claude/hooks/grep-q-pipe-guard.test.sh` - if a new stub reads piped text, `PJ_TRIPLES` must equal the derived producer-triple count.
6. `bash .claude/hooks/brand-hex-commit-gate.test.sh` and `bash .claude/hooks/git-commit-secret-scan.test.sh` (the lib is shared; must stay green, unmodified), `bash .claude/hooks/hook-input-contract.test.sh`, `bash scripts/test-all.sh --affected` (or the repo's affected-gate entry) as the local approximation of CI; remember CI runs bash 5.2 and the host 5.3 (write `return 0` explicitly in functions reached from a trap handler).
Commit and push after each fix.

### Phase 5 - Ship notes (executed by the ship phase, listed so nothing is dropped)
PR body via `--body-file`: `Closes #10793`, `Ref #10331`, `Ref #10609`, the test list, the follow-up pointer (sim-lib adoption, ADR-301), and ends with the generated-with line. If the merge queue shows UNMERGEABLE behind another PR, wait for it to merge, then merge origin/main and resolve. Follow-up: the CTO ruling names sim adoption as a follow-up; ship files a tracking issue for it (milestone from the roadmap) if none exists - `gh issue list --search` found none open.

## Acceptance Criteria

Pre-merge (PR):
- [x] AC1 `cd <worktree> && git commit` and `git -C <worktree> commit`, run with the hook process cwd at a `core.bare=true` root, deny when the worktree's staged files carry a raw hex literal (tests T25, T26) and allow when they do not (twins). Verified by `bash .claude/hooks/brand-hex-commit-gate.test.sh`.
- [x] AC2 `git -C <other repo> commit` from inside a clean work tree scans the other repo (T26c); a two-root command scans both and the deny names the offending root (T30).
- [x] AC3 The no-cd path is unchanged: all 24 pre-existing assertions still pass unmodified; T27/T28 regression rows pass; the diff-base regex and deny text are byte-identical (`git diff` of those hunks shows no change).
- [x] AC4 An undeterminable target (variable, `~`, glob, `GIT_DIR=`, `--git-dir`, no perl with a target-moving token, lib missing, `CTR_ROOT_ERR`) yields decision `allow`, exit 0, a stderr `WARN`, and a `bypass` incident row; never `deny`, never `ask` (T33-T35).
- [x] AC5 `-a`/`--all` selects the `HEAD` base for `git -C W commit -a` through `CTR_COMMIT_ALL` and still ignores flag-like text inside `-m` (T29).
- [x] AC6 Palette discovery is per root (T31).
- [x] AC7 The header comment and the in-body trigger comment no longer claim identity with the secret scan's regex (T36 content anchors).
- [x] AC8 Every Phase 4 command exits 0; `scripts/lib/test-affected-paths.sh` has exactly one `AFFECTED_CLAUDE_HOOKS_BRAND_HEX_COMMIT_GATE_TEST_SH_PATHS=` and it names the lib and the lexer; the boundary-prefix exemption is on the right line.
- [x] AC9 `git diff --stat origin/main` shows no change to `.claude/hooks/git-commit-secret-scan.sh`, `.claude/hooks/lib/commit-target-roots.sh`, `.claude/hooks/lib/commit-index-sim.sh`, or `plugins/soleur/skills/work/SKILL.md`; the hook does not reference `commit-index-sim` or `CIS_`.
- [x] AC10 Every phase's work is committed and pushed (`git status` clean, `git log origin/<branch>..HEAD` empty) before the next phase starts.
- [ ] AC11 PR body contains `Closes #10793`, a separate `Ref #10331`, `Ref #10609`, no closing keyword for #10331.

Post-merge: none (hook change takes effect on the next session; no deploy, no migration).

## User-Brand Impact

**If this lands broken, the user experiences:** a commit that should have been blocked for an off-brand colour slips through, or a legitimate commit is wrongly denied with the BLOCKED message (worst realistic case: a false deny from a root named by a `-C` the commit does not target, costing one re-run).

**If this leaks, the user's [data / workflow / money] is exposed via:** nothing - the gate reads staged colour literals, handles no credentials or personal data, and fail-open by design means a defect degrades to the pre-fix behaviour (an unscanned commit), not to a data exposure.

**Brand-survival threshold:** none

threshold: none, reason: the changed file is a brand-colour commit gate under `.claude/hooks/`, not a credential, auth, or user-data path; a failure leaves an off-brand hex in a commit that the review-time frontend-anti-slop scanner still catches.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected - internal developer-tooling (hook) change; no user-facing UI, copy, legal, finance, or marketing surface.

## Architecture Decision (ADR/C4)

No architectural decision: the plan reuses an existing library through its existing public API, in the same fail-soft-load/explicit-check shape ADR-157-class hooks already use, and the disposition is already recorded by the CTO ruling on #10793. C4: checked `diagrams/{model.c4,views.c4,spec.c4}` for external actors, systems, data stores and access relationships touched - the change adds none (it is a local hook reading git state); no element or relationship description is falsified. `plugins/soleur/test/c4-count-parity.test.sh` is not expected to move (no cron/monitor/heartbeat count changes) and is run in Phase 4 only if the affected gate selects it.

## Observability

The hook is its own telemetry surface (it is not under `apps/*/server`, `apps/*/src`, `apps/*/infra` or `plugins/*/scripts`; the block is included because the deepen gate treats any non-docs path as in scope).

```yaml
liveness_signal:
  what: a bypass row in the incident ledger (emit_incident brand-hex-commit-gate bypass "target undeterminable: <kind>") plus one stderr WARN line per undeterminable commit
  cadence: per git commit tool call
  alert_target: .claude/.rule-incidents.jsonl, aggregated weekly by rule-metrics-aggregate.sh
  configured_in: .claude/hooks/brand-hex-commit-gate.sh (the undeterminable arm)
error_reporting:
  destination: stderr WARN (operator-visible in the tool result) and the incident ledger row
  fail_loud: false - fail-open by CTO ruling; a defect degrades to the pre-fix unscanned commit
failure_modes:
  - mode: target undeterminable (variable, glob, tilde, GIT_DIR, no perl, lib missing)
    detection: bypass row with the kind word plus the stderr WARN
    alert_route: weekly rule-metrics aggregate; a rising bypass count on ordinary no-cd commits is the evidence that flips CTO Q1
  - mode: hook crashes before a decision
    detection: tool call proceeds with no JSON; hook-input-contract suite and the explicit declare -f guard cover the missing-helper case
    alert_route: hook-input-contract.test.sh in CI
logs:
  where: stderr of the hook and .claude/.rule-incidents.jsonl
  retention: ledger is git-ignored local state, rotated by the existing incident tooling
discoverability_test:
  command: grep -o 'target undeterminable' .claude/hooks/brand-hex-commit-gate.sh
  expected_output: target undeterminable
```

## Guard Contract

### Guard 1 - brand-hex-commit-gate target resolution

**Property.** Every repository that a `git commit` command text names as its target through a literal `cd` / `pushd` / `git -C` has its staged (or, with `-a`, tracked) diff scanned with THAT repository's own palette; any command whose target cannot be read statically warns, records a bypass row and allows, and never denies, asks, or scans a repository the command may not target.

**Assembly.** The property quantifies over: (1) the TWO trigger sites - the unchanged strict regex and the new loose both-words test; (2) the three ways a target set is produced - `ctr_collect`+`ctr_resolve_roots` roots, the process-cwd toplevel, and the empty-set fallback; (3) the FOUR undeterminable inputs - `CTR_BAD`, `CTR_ROOT_ERR`, lexer unavailable, lib missing; (4) every root in the loop, not the first; (5) the single diff-base decision shared by all roots; (6) per-root state: `PALETTE`, `PALETTE_NAME`, `palette_built`, `cd`. The chokepoint is `scan_root`; the loop over the root set and the single `allow`/`deny` exits are the call sites.

**Mutation matrix.** Each row is an edit that MUST turn the named test(s) RED; derived from the design, written (as tests) in Phase 1 before the hook edit.

| # | Mutation | Must redden |
|---|---|---|
| M1 | Delete the loose both-words trigger (strict only) | T26, T26c, T29 (`-C` rows) |
| M2 | Never call `ctr_collect` (force `ctr_ok=0` or skip the lex block) - the guard's own dispatch | T25, T26, T30 |
| M3 | Scan only `CTR_ROOTS[0]` / only the cwd root (stop after the first member) | T30 (second-root and union rows) |
| M4 | Do not reset `PALETTE`/`palette_built` between roots | T31 |
| M5 | Undeterminable arm denies (or asks) instead of allowing | T33, T34, T35 |
| M6 | Undeterminable arm scans the cwd root before allowing | T33 (cwd-holds-off-brand row) |
| M7 | Always use `--cached` (ignore `CTR_COMMIT_ALL`) | T29 (`-C ... -a`) |
| M8 | Treat a lexer "no commit record" as a commit for a loose-only match | T28 (prose row) |
| M9 | Drop the lexer-unavailable `target-moving token` split (always warn+allow, or always cwd) | T34 (both directions: plain commit must deny, `-C` must warn-allow) |
| M10 | Re-add the retired "identical to git-commit-secret-scan" phrase | T36 |

**Harness rows.** Suite edit that must redden it: remove the `git worktree add` from `_seed_bare_root_with_worktree` (T25/T26 must fail loudly rather than pass vacuously), and the fixture control T37 must redden if the off-brand staging helper stops staging. Must-PASS inputs that are NOT the canonical: `cd "<abs wt>"` with double quotes, `cd ./.worktrees/wt` relative, `git -C <wt> commit --amend --no-edit` and a clean-staged twin for every deny row - each differs from the canonical `cd <abs> && git commit -m x` in a way the contract permits.

**Anchor.** Not applicable: the guard compares no stored value (no hash, manifest or count floor); the palette is rediscovered from each repository's committed CSS on every call.

## Test Scenarios

See Phase 1 (T25-T37). Additionally run the full suite under `bash --version` 5.2 if available (CI) and the host 5.3.

## Sharp Edges

- `${command#*git commit}` does not strip anything for `git -C W commit`; the diff-base regex must stay gated on `strict_match=1` or it scans the whole command text for `-a`.
- At a bare root `git rev-parse --is-inside-work-tree` prints `false` with rc 0: do not use its exit status as the work-tree test.
- `ctr_resolve_roots` returns toplevels PHYSICALLY; fixture paths must come from `pwd -P`, and findings are prefixed with a basename, never a full path, so tmpdir symlinks cannot break assertions.
- Source the lib from `${BASH_SOURCE[0]}`, not `$CLAUDE_PROJECT_DIR`: the suite sets the latter to a temp repo that has no hooks.
- The cwd toplevel lookup is a fail-open probe: at a bare root it exits 128 ("must be run in a work tree"); treat ANY failure of that one call as "no cwd root" (the existing `|| echo ""` behaviour), never as `CTR_ROOT_ERR`. Only an error from `ctr_resolve_roots` (a repository git cannot read) is "undeterminable".
- The sibling secret-scan hook will itself block a shell command whose text carries a variable path next to git commit; run fixture-building probes from a script file, not an inline `bash -c`.
- Do not use `printf ... | grep -q` anywhere in new hook code (SIGPIPE under pipefail, #6992); use herestrings.
- The tests' own commit messages and the PR body must not contain the phrase git commit inside a quoted shell argument; use `-F` / `--body-file`.
- A `## User-Brand Impact` section with `threshold: none` on a sensitive path needs the scope-out line - present above (`.claude/hooks/` is not in the preflight sensitive-path regex, line kept as a belt-and-braces).
