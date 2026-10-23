---
title: "hooks: git-commit-secret-scan scans the index before the same command's git add / commit -a runs"
date: 2026-10-23
slug: fix-commit-secret-scan-would-be-index
branch: feat-one-shot-10696-secret-scan-staging-gap
issue: 10696
closes: 10696
type: fix
lane: cross-domain
brand_survival_threshold: aggregate pattern
---

## Overview

Spec lacks valid lane: - defaulted to cross-domain (TR2 fail-closed); there is no `spec.md` for this branch.

The commit-time secret scan (`.claude/hooks/git-commit-secret-scan.sh`, a PreToolUse hook on Bash) runs gitleaks over the staged index before the Bash command it guards has executed. A single command that stages and commits (a chained `git add ... && git commit`, `git commit -a`, `git commit -am`, `git commit -- <path>`) is therefore scanned against an index that does not yet hold the content the commit will record. A secret in the working tree passes unscanned. Staging in a separate earlier call is the only fully covered shape.

The CTO ruled (2026-10-23, recorded in `knowledge-base/project/specs/feat-one-shot-10696-secret-scan-staging-gap/decision-challenges.md`) that this ships now as its own PR, and rejected the issue's `git diff HEAD` candidate (it misses untracked files and over-scans). The mechanism is a **simulated would-be index**: the hook copies the real index to a temp file, replays the command's own staging verbs onto the copy (exact replay when every word is literal and the directory is proven, superset `git add -A` otherwise), and runs the existing `scan_root` with `GIT_INDEX_FILE` and a quarantined object directory exported around it. Nothing in the real index, real object store or working tree is touched.

Measured motivation (ruling evidence): about 77 percent of roughly 2,900 sampled agent `git commit` Bash lines are chained add-then-commit, about 1 percent use `commit -a`, 16 use a `--` pathspec. lefthook runs `gitleaks-staged` only at pre-commit (no pre-push) and the CI `secret-scan` workflow only runs after a push, so for an agent this hook is the only pre-history gate.

## Research Reconciliation — Spec vs. Codebase

| Claim in the brief / issue | Reality (verified) | Plan response |
|---|---|---|
| Issue candidate: scan `git diff HEAD` of the resolved roots | `git diff HEAD` does not list untracked files, so `git add -A && git commit` of a new file passes; it also over-scans unstaged edits the commit will not record | Rejected by the CTO ruling; the would-be index is the design |
| "Plain `git commit -m x` pays nothing" | `ctr_wants_lex` currently SKIPS the lexer for `git add -A && git commit -m "fix: tidy"` and the suite pins that as a must-skip row (T39 pre-filter table). Detecting staging needs the lexer's argv, so the pre-filter must widen | Phase 1 widens `ctr_wants_lex`; the must-skip row flips to must-match; `git commit -m x` and `git status && git commit -m x` stay must-skip. CTO accepted the ~45 ms perl cost (decision row 7) |
| Replay `git add\|rm\|mv\|stage` argv | `git rm` and `git mv` act on the WORKING TREE even with a temp index, and add no new blob content | CTO rows 2 and 9: the walker recognises and ignores them; they never replay and do not set `CTR_COMMIT_STAGES` |
| Pathspec commit falls back to superset `git add -A` | `commit -- p` records exactly the working-tree content of tracked `p` | CTO row 3: `git add -u -- <literal paths>`, then `git add -u`, then `git add -A` only if both fail |
| Exact replay of literal add args | The walker keeps a UNION of cd / `-C` targets, so it cannot say which root or directory an add ran in | CTO rows 4 and 8: exact replay only with ONE scanned root and a proven directory (rule in Design 4); otherwise the superset |
| `_mk_pem` yields a detectable fixture | Measured with the pinned `.gitleaks.toml`: the default `_mk_pem` body (a sequential-alphabet run) is allowlisted by stopwords and scans clean (rc 0); a body such as `t5_syntheticpayload_1234` is detected (rc 1) | Every new leak fixture passes an explicit non-sequential body, as the existing T5 does |
| The hook's own mktemp calls are covered by its trap | `scripts/lint-trap-tempfile-ownership.py` rule (c) flags a NEW file that calls `mktemp` with no `trap ... EXIT` | The lib calls no `mktemp`; the hook allocates the sim directory and its EXIT trap removes it |
| New hook libs need no registration | `plugins/soleur/skills/verification-scaffold/test/manifest.test.sh` fails when a `.claude/hooks/**/*.sh` basename has no row in `guardrail-audit.md` | Files to Edit gains the audit row |
| gitleaks honours `GIT_INDEX_FILE` / `GIT_OBJECT_DIRECTORY` | Measured here (gitleaks 8.30.1): a synthetic PEM present only in the sim index is found (rc 1) by `gitleaks git --pre-commit --staged`; real index bytes and real loose-object count unchanged; `git check-attr` and `git show :path` (the `-diff` re-scan) read the sim index. The CI pin is 8.24.2, exercised by the suite's real-gitleaks arms in CI | Design stands; the real-gitleaks arms are the cross-version check |
| The `INT`/`TERM` trap ends the hook | Measured by the correctness reviewer: bash runs the trap handler and CONTINUES the script, so the existing `trap '...' EXIT INT TERM` would delete the sim dir mid-run and the hook could end in `allow` | Phase 3 splits the trap: `EXIT` cleans up, `INT`/`TERM` call `exit 130`/`exit 143` |
| `git add -A --ignore-errors` tolerates unreadable files | Measured: it indexes the readable files and still exits 1 | `--ignore-errors` is not used; a failing superset denies and quotes git's first error line (CTO row 14) |
| Lexer flag `q` means "contains a glob" | `shell-argv.pl` defines `q` as "some part of the word was quoted or backslash-escaped"; `git add "my file.md"` is `q` and a literal | Literalness rule: reject flag `x`; reject `* ? [ { ~` only in an unquoted word; a quoted word replays verbatim (git globs pathspecs itself) |

## Research Insights

**Premise validation (Phase 0.6).** `gh issue view 10696`: OPEN, title matches. `gh issue view 10331`: CLOSED (the code-quality epic; reference only, never reopened). Draft PR 10893 is open. `gh issue view 10793` (brand-hex-commit-gate resolves its repo from the process cwd): OPEN, the named later consumer of the shared sim library. No ADR in `knowledge-base/engineering/architecture/decisions/` mentions a would-be index or a quarantined object directory; ADR-156/157/165 (hook stdin untrusted, ask-on-unparseable, no `ask` state on a headless harness) govern the deny-not-ask posture. Open code-review issues touching any planned file: none.

**Property List (Phase 0.6b).**

1. Content the command's own staging verbs or commit flags will record is in the index gitleaks scans.
2. A plain `git commit -m x` costs no more than today (no simulation, no new git call).
3. The simulation never changes the real index, the real object store or the working tree.
4. When the simulation cannot be built, a commit that could not be scanned is blocked (superset / temp failure) or warned about with a ledger row (only the user's own missing-pathspec error).
5. The shared library is reusable by the brand-hex gate (#10793) without edits to its replay logic.

**Cut List.** `git diff HEAD` candidate: buys property 1 but misses untracked files (CTO rejected). A bash-only fast path or cache for the lexer: buys property 2 for staged forms only at the cost of a second parser (CTO row 7). A new override environment variable for the deny: buys nothing (an override is the skip). Replaying `rm`/`mv`: buys no property and mutates the working tree. `--ignore-errors`, a "last commit wins" add-count snapshot, `CTR_DIRS`/an edit to `ctr_resolve_roots`, a lazily sourced sim lib, `umask 077`, and the revert rehearsal: each bought no property after plan review (see Plan Review Revisions).

**Measured cost (Phase 0.6c).** Commands run on this host in this worktree (19,852 tracked files): lexer `for i in 1..10; printf 'git add -A && git commit -m "fix: x"' | perl plugins/soleur/hooks/lib/shell-argv.pl` = 0.436 s wall for ten, about 44 ms per call. Index copy plus `GIT_INDEX_FILE=<tmp> GIT_OBJECT_DIRECTORY=<tmp> GIT_ALTERNATE_OBJECT_DIRECTORIES=<real> git add -A` on an unchanged tree = 0.09 to 0.11 s. The scan itself is not doubled: the would-be index is a superset of the real one, so gitleaks runs ONCE, against it. The p95 gate (AC13) is measured, not asserted, in Phase 5. Baseline for the existing suite: 405 passed, 0 failed (the `MIN_ASSERTIONS` floor is exactly 405).

**Institutional learnings applied.**

- `2026-10-22-a-closed-world-recogniser-in-a-fail-open-hook-and-a-depth-bound-that-did-not-bound-work.md`: the walker over-recognises; every cap in the new path denies rather than skips.
- `2026-09-04-a-10-of-10-mutation-score-and-ten-escapes-it-could-not-see.md` and `2026-04-03-git-env-var-leak-resolve-git-root-test.md`: a hook in a linked worktree exports absolute `GIT_DIR` / `GIT_INDEX_FILE`; the sim sets its own variables explicitly and the tests scrub ambient `GIT_*`.
- `2026-07-05-composite-safety-hook-authoring-pitfalls.md`: a bare `source` of a new helper under `set -e` aborts the hook (fail-open). The sim lib is sourced in the same checked `if` as the walker lib (CTO row 13).
- `2026-09-14-git-hook-env-prefix-scrub-and-anchored-recovery-grep.md`: a replay arm must not be gated on env that the hook's own environment can set or unset.
- Plan-sharp-edges items applied (the catalogue was read in full for its first 60 entries and keyword-scanned for the rest: the file is 238 KB): a tool's effect on a sandbox is the oracle, not its report; `cmd | grep -q` under `pipefail` and SIGPIPE; every mutation row needs a must-PASS control; run the orphan-suite and trap-ownership lints; markdownlint the plan and tasks.

## Problem Statement

`git-commit-secret-scan.sh` ends with `gitleaks git --pre-commit --staged` against the real index. For `git add -A && git commit -m x`, `git commit -a`, `git commit -am x` and `git commit -- <path>`, the index the commit will record does not exist yet when the hook runs. Result: a credential in a new or modified file is committed to local history and caught, if at all, by CI after the push, when rotation or a history rewrite is already required.

## Proposed Solution

### Design (CTO-ruled; refinements are in the decision rows)

1. **Walker records staging** (`.claude/hooks/lib/commit-target-roots.sh`). `_ctr_git_walk` learns:
   - `add` / `stage`: one pre-validated record per command (validation happens in the walker, where the lexer flag per word is in hand). A record carries `tgt_known` (1 when at least one cd / `-C` target had been collected by the time the record was processed, including its own `-C`), `exact` (0 when any word is non-literal, any option is outside the allowlist, a pathspec-semantics global option or `git -c` precedes the verb, a `GIT_*PATHSPECS=` assignment prefixes it, or it was reached through a multiplying launcher such as `xargs`, `parallel`, `find`, `watch`, `su`, `ssh`; pass-through launchers such as `rtk`, `timeout`, `nice`, `sudo`, `env`, `command`, `exec`, `flock` keep it exact), `force` (1 when `-f`/`--force`, including bundles like `-fA`), then the words.
   - `rm` / `mv`: recognised and ignored (CTO row 9): no replay, no `CTR_COMMIT_STAGES`, no pre-filter clause.
   - Stage-unknown verbs `apply|update-index|checkout|cherry-pick|merge|revert|stash|am|read-tree|restore|pull|switch|rebase|submodule|sparse-checkout`, and an `x`-flagged command word followed by a staging word: set `CTR_STAGE_OPAQUE`.
   - The commit's own flags (`_ctr_commit_flags`): short bundles scanned character by character, `a` -> all, `o`/`i` -> paths mode, `p` -> all (`add -u` covers `-p`), `m F C c t` consume the rest of the word as their operand or, if nothing is attached, the next word (so `-malpha` is a message, not `-a`); `S` and `u` take only an attached remainder (`-Sabc`, `-uall`) and end the bundle. Long options: an exact table of staging options (`--all`, `--only`, `--include`, `--patch`, `--interactive`, `--pathspec-from-file`) and an exact table of benign options taken from `git commit -h` at implementation time (with separate-operand ones: `--message --file --author --date --reuse-message --reedit-message --fixup --squash --trailer --template --cleanup --unified --inter-hunk-context`; `--no-all|--no-only|--no-include|--no-patch` clear the fact); any other `--long` option, including a unique-prefix abbreviation, sets `CTR_STAGE_OPAQUE` (CTO row 10). `--` starts the pathspec; positional words are paths.
   - Outputs, all initialised at library top level next to `CTR_COMMIT_SEEN=0` and reset in `ctr_collect` (the hook reads `${CTR_COMMIT_STAGES:-0}`; an unset variable under `set -u` on the lexer-skipped plain-commit path would otherwise abort the hook, which fails open): `CTR_COMMIT_STAGES`, `CTR_STAGE_OPAQUE`, `CTR_ADD_ARGV` (one record per element, fields joined by the ASCII unit separator), `CTR_COMMIT_ALL`, `CTR_COMMIT_PATHS`, `CTR_COMMIT_PATHS_LITERAL`. Every add record in the command is replayed regardless of position relative to the last commit (an add after the last commit is merely over-scanned; CTO row 14). `ctr_resolve_roots` is NOT edited.
2. **Pre-filter** (`ctr_wants_lex`) also returns true for: a stage-capable git verb in the text (`git (add|stage|apply|update-index|checkout|cherry-pick|merge|revert|stash|am|read-tree|restore|pull|switch|rebase|submodule|sparse-checkout)`); a commit short bundle `[[:space:]]-[^-[:space:]]*[aoip]`; a long option beginning `--(al|o|in|pa)` (covers `--all`, `--only`, `--include`, `--interactive`, `--patch`, `--pathspec-from-file` and their abbreviations; over-matches `--allow-empty`, which only costs a perl spawn); a bare ` -- `; and a bare non-option first word right after `commit` (`commit[[:space:]]+[^-"'$&|;)[:space:]]`). A positional that follows a `-m "..."` is NOT detected (CTO row 11: a named residual). It over-matches by design; a pinned must-match / must-skip table covers each form.
3. **Simulation is conditional**: runs only when `CTR_COMMIT_STAGES=1` (any add/stage record, or `CTR_STAGE_OPAQUE`, or a commit-flag fact). A plain `git commit -m x` reaches no new code and allocates nothing.
4. **New shared library** `.claude/hooks/lib/commit-index-sim.sh` (no `mktemp`, no `trap`, no hook response; returns codes and the first stderr line; the caller decides; never call its functions inside `$(...)`, because the exports and globals would be lost in the subshell). Sourced in the same checked `if` as the walker lib (CTO row 13). For each scanned root:
   - `cis_prepare <root> <dir>`: copy `$(git -C root rev-parse --git-path index)` into `<dir>/index` (a missing index means an empty one; the path is made absolute against the root by hand when relative, no `--path-format=absolute`, which needs git 2.31); create `<dir>/objs` with `mkdir -m 700`; resolve `CIS_ALT` the same way from `--git-path objects`; a `:` in the real objects path (the env-var separator) is a prepare failure. Needs `cp` on the PATH.
   - `cis_export` / `cis_unexport`: export or unset `GIT_INDEX_FILE`, `GIT_OBJECT_DIRECTORY`, `GIT_ALTERNATE_OBJECT_DIRECTORIES` ONCE per root, covering prepare-to-scan, so the replay and the scan see the same index. `_cis_git` is only the timeout wrapper: `LC_ALL=C`, stderr captured (first line kept), `timeout` -> `gtimeout` -> bare.
   - One total deadline for the whole simulation, tracked with `$SECONDS` (15 s, shared across roots; each call gets `min(remaining, 15)`). Exhaustion counts as "any other failure" below. The work phase confirms the harness default hook timeout against the Claude Code hooks documentation; `.claude/settings.json` has no `timeout` for this hook and a hook that outlives the default lets the call proceed.
   - **Exact replay conditions** (all must hold, otherwise the superset is used directly): exactly ONE scanned root; the replay directory is proven: either the command names no cd / `-C` / `env -C` target (`CTR_TARGETS` empty) and `HOOK_CWD` is set and is a directory (an empty `HOOK_CWD`, the Devin case, means superset), or `CTR_TARGETS` has exactly one entry that is an absolute existing directory and every add record and the commit have `tgt_known=1`; every add record has `exact=1`; `CTR_STAGE_OPAQUE=0`; no loop or function in the text (`_ctr_has_loop`). The directory is derived in the hook glue, not in the walker.
   - **Replay**: for each record, `git -C <dir> add <words>` (only the `add`/`stage` verbs). Allowed options: `-A -u -f -N -v --all --update --force --intent-to-add --renormalize`, `--`, pathspec words (including `:` magic and `.`). Failure classes (CTO row 8): git's own `pathspec ... did not match any files` is trusted as the user's own error only because the directory was proven; it is noted as cause `pathspec-missing`, the replay continues with later records, and the run ends with a `git-commit-secret-scan-sim-failed` bypass row (allow if clean). ANY other failure (timeout, deadline, ENOSPC, exit 128 with another message) abandons the exact replay and rebuilds from a fresh index copy with the superset.
   - **Superset**: `git add -A` (no `--ignore-errors`). When any add record had `force=1` and the exact replay was not used, additionally `git add -f -- <the literal path words of those records>` on the copy; if any such word is non-literal, DENY "run the force-add as its own call, then commit" (CTO row 12). A failed superset (non-zero, timeout, deadline) DENIES, quoting git's first error line.
   - **Commit step** after the replay, unless `add -A` already ran: `-a` / `-p` -> `git add -u`; paths / `-o` / `-i` -> `git add -u -- <literal paths>`, falling back to `git add -u` for non-literal paths or a failure, then `git add -A` if that fails too (CTO row 3).
5. **Hook glue** (`git-commit-secret-scan.sh`): when `CTR_COMMIT_STAGES=1`, after `gitleaks_runnable`, allocate the sim directory with `sim_dir=$(mktemp -d -t commit-sim-XXXXXX) || deny ...` (declare `sim_dir=""` before the trap line), then per root in `toml_roots`: build the would-be index, `cis_export`, call the unchanged `scan_root`, `cis_unexport`, and clear the root's sim files; otherwise call `scan_root` exactly as today. The trap becomes `trap cleanup EXIT; trap 'exit 130' INT; trap 'exit 143' TERM`, with `cleanup` removing the report files, `nodiff_dir` and `${sim_dir:-}`. Every `cis_*` call and the `mktemp` are explicitly checked (`if ! cis_prepare ...; then deny ...; fi`; multi-step bodies end each step in `|| return 1`), because a bare failing call under `set -e` exits 1 and the harness treats exit 1 as non-blocking (fail-open). `deny()` (outside `scan_root`) gains one behaviour when `SIM_ACTIVE=1`: it appends a note ("this file is not staged yet; the command would stage it ... do not run git restore --staged; scrub or delete the file or add it to .gitignore, or stage only the intended paths in a separate call, then commit"), names why the superset was used when it was, and emits under the distinct ledger rule id `git-commit-secret-scan-sim-deny`. `scan_root` itself stays byte-identical, and the `-diff` re-scan inherits the exported variables.
6. **Failure posture** (no `ask`, ADR-165):

   | Situation | Result |
   |---|---|
   | User's own missing pathspec during a proven-directory exact replay | scan what was built; bypass row `git-commit-secret-scan-sim-failed` (cause `pathspec-missing`); allow if clean |
   | Any other replay failure | rebuild with the superset; a failed superset denies |
   | Failed superset, force-add with non-literal words, temp dir / index copy failure, deadline exhausted in the superset | DENY, repair "run git add as its own call, then commit" (quoting git's first error line where there is one) |
   | Sim lib missing or unreadable | DENY every strict commit through the existing `lib` repair (same `if` as the walker lib) |
   | Lexer unavailable on a chained add-then-commit (about 77 percent of commits now reach the lexer) | existing `tooling` / `parse` / `bound` denies, whose repair text is updated: it no longer says "a plain git commit still works" for chained adds, and adds "run git add in one call, the commit in the next" |
   | gitleaks missing / unrunnable / probe timeout | unchanged (those exits precede the sim) |

### Alternative Approaches Considered

| Approach | Verdict |
|---|---|
| `git diff HEAD` of the resolved roots | Rejected by the CTO ruling (misses untracked files, over-scans) |
| Run the real `git add` in the hook | Rejected: mutates the real index/store before the user's command and before allow/deny |
| Scan the working tree with `gitleaks dir` | Rejected: scans everything, not what the commit records |
| Lexer for every commit | Rejected: puts perl on the no-staging path (property 2) |
| Always-superset (never replay) | Rejected by the ruling: an unrelated untracked file would deny `git add clean.txt && git commit` |

## Technical Considerations

- **Portability**: bash 3.2 (no `mapfile`, no `declare -n`, no associative arrays; empty arrays read as `${a[@]+"${a[@]}"}`; truncation guarded like the existing `[ "$_CTR_BAD_MARK" -eq 0 ]`); only `timeout` -> `gtimeout` -> bare; `cp` needed (add it to the stub PATH in the suite).
- **Telemetry**: ledger ids `git-commit-secret-scan-sim-failed` (bypass) and `git-commit-secret-scan-sim-deny` (deny), emitted through the existing `emit`; no registry lists the sibling ids. Layer: the local incident ledger `.claude/.rule-incidents.jsonl` (a dev-machine hook, not a server surface; the server observability layers do not apply). The distinct deny id exists so superset-caused false denies can be measured separately from real findings.
- **Secret residue**: the quarantined object directory holds blobs of working-tree files that may be secrets. `mktemp -d` is mode 0700 and per-root directories use `mkdir -m 700`; the EXIT trap removes it and INT/TERM now exit through that trap (a SIGKILL leaves residue; accepted, documented in the header).
- **Residuals named in the hook header** (CTO rows 5 and 11; one follow-up issue lists them all): a script that runs `git add` inside; content created or changed earlier in the same command (`terraform show -json > f && git add f && git commit`, `sed -i`, `prettier --write`, `cat > f <<EOF`): the file does not exist at hook time, the exact replay reports `pathspec-missing`, and the commit is allowed with a bypass row; a positional pathspec after a `-m "..."` (`git commit -m "x" path`); a clean filter (`filter.*.clean`, Git LFS) that writes outside the quarantined object directory; other tools that stage (an IDE, a git alias); `restore --staged` and `checkout` branch switches force the superset (slower, rare false denies).
- **Superset trade-off**: `add -A` scans unrelated untracked, non-ignored files, so an unrelated finding in the cwd repo can deny a commit aimed elsewhere (the same trade-off the hook already documents for the cwd roots). The exact replay and the `-u`-based paths avoid it.
- **Pathspec commit and other staged content**: `commit -- p` records only `p`, but the sim index keeps other staged changes, so a staged leak elsewhere still denies it (the existing conservative behaviour; pinned by a row).

## Architecture Decision (ADR/C4)

No ADR or C4 change. The test applied: would an engineer reading the existing ADRs and C4 be misled after this ships? No. This adds an internal mechanism to one hook inside the existing "PreToolUse hook scans before the command" posture (ADR-156/157/165 unchanged); no ownership/tenancy boundary, substrate, trust boundary or ADR reversal moves. C4 files read for the check: `knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}` model the web platform, not the repo's developer hooks; actors/systems/relationships checked: no human actor, vendor system, container or access relationship is added or changed by a local hook, and `plugins/soleur/test/c4-count-parity.test.sh` is unaffected (no workflow or monitor count moves). The design record is the decision-challenges file plus the hook header.

## User-Brand Impact

- **If this lands broken, the user experiences:** either a commit denied with a repair message they can follow (run `git add` as its own call, then commit), or, in the worst bug, a secret in a freshly added file committed to local history and caught only by CI after the push.
- **If this leaks, the user's workflow data is exposed via:** a leftover temp directory holding blobs of working-tree files (a secret-bearing file's content) after a hard kill; mitigated by mode 0700 and a trap that removes it on EXIT / INT / TERM.
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** the gap is narrow and CI-backstopped (the post-push `secret-scan` workflow remains the load-bearing gate), and the verification-scaffold template that ships to user repos self-contains its own parse and is not changed here, so a defect in this hook reaches Soleur's own repo, not a user's.

## Guard Contract

### Guard 1 — would-be index coverage

**Property.** Every file content the Bash command's own staging verbs or commit flags would record in the commit is present in the index that gitleaks scans before the command runs.

**Assembly.** Not a list of verbs; the chokepoints every staging form must flow through, in order: (1) the pre-filter `ctr_wants_lex` (a form it misses never reaches the walker; the must-match table pins each form), (2) the walker records in `_ctr_git_walk` for `add|stage`, the stage-unknown verbs and the commit-flag parser (a verb or option it does not classify is invisible; an unknown `--long` option forces the superset), (3) the classification into `CTR_COMMIT_STAGES` / `CTR_STAGE_OPAQUE`, (4) the single exactness predicate (one root, proven directory, every record exact, no loop), (5) `cis_replay` and the commit step (every git call through `_cis_git`), (6) the export window around `scan_root` (every read inside `scan_root`: `gitleaks git`, `git diff --cached --name-only`, `git check-attr`, `git show :path` for the `-diff` re-scan; one export covers all four injection sites, not one per call), (7) the failure branches (only the user's own missing pathspec warns; everything else rebuilds with the superset or denies).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete the staging-verb clause from `ctr_wants_lex` | RED: the flipped pre-filter row fails and the chained leak case is allowed |
| 2 | Force `CTR_COMMIT_STAGES=0` in the walker (dispatch of the sim) | RED: cases 1, 2 and 4 allow; the PATH-shim row that expects exactly one sim `add` sees none |
| 3 | After a compliant first record, add a second: `git add clean.txt && git add leak.json && git commit`; mutate the replay to stop after the first record | RED: the second record's leak is not scanned |
| 4 | REORDER: move `cis_export` to after the `scan_root` call (or `cis_unexport` before it) | RED: a gitleaks stub recording `$GIT_INDEX_FILE` inside the call sees it unset, and the real-gitleaks leak case is allowed |
| 5 | Treat `-p` as a replayable option | RED: the PATH shim sees `add -p` executed instead of the superset `add -A` |
| 6 | Make a failed superset (`add -A` returns 1 via the shim) allow | RED: the deny-on-failed-superset case allows |
| 7 | Drop the one-root rule (replay exactly with two roots) | RED: the two-root case replays an add in the wrong root and misses a leak |
| 8 | Skip the `commit -a` step (`add -u`) | RED: `commit -am` with a tracked modified leak is allowed |
| 9 | Treat any replay failure (not just `pathspec ... did not match`) as warn-and-allow | RED: a shim that makes the replay `add` exit 128 with another message ends in allow instead of the superset deny |
| 10 | Treat a stage-unknown verb as non-staging | RED: `git checkout <ref> -- . && git commit` with a leak is allowed |

**Harness rows:**

| # | Edit to the SUITE | Expected |
|---|---|---|
| H1 | Make the `git` PATH shim stop logging (empty log) | RED: the "one sim add, with a non-real index file" assertion fails instead of passing vacuously |

The must-PASS control that is NOT the canonical shape is group 3 (`git add clean.txt && git commit` with an unrelated untracked leak, plus its quoted-name variant `git add "my file.md"`): it differs from the canonical `add -A` leak case in a way the contract permits and it fails if the hook simply denies everything.

**Anchor.** No stored value is compared to a protected artifact. The suite's `MIN_ASSERTIONS` count floor is the only stored number; it is raised in the same edit that adds rows and is itself pinned by the existing floor-contract truth table.

### Guard 2 — the simulation never mutates the real repository

**Property.** Running the simulation leaves the real index bytes, the real object store and the working tree unchanged, and leaves no temp directory behind.

**Assembly.** Every git invocation in `commit-index-sim.sh` passes through `_cis_git` (one chokepoint); the only verbs the replay may run are `add` and `stage`; the three variables are exported before any write and unset after; the temp directory is allocated by the hook and removed by the `cleanup` EXIT trap on the allow path, the deny path (`deny` exits inside `scan_root`) and signals (INT/TERM exit through the trap).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Run the copy step against the real index (skip `cp`, point `GIT_INDEX_FILE` at the real file) | RED: real index sha256 differs after the hook |
| 2 | Omit `GIT_OBJECT_DIRECTORY` | RED: the real store's loose-object count grows |
| 3 | Remove the sim directory from `cleanup` | RED: a `commit-sim-*` directory remains after an allow, after a deny (two observation points) and after a TERM sent to a hook blocked in a sleeping gitleaks stub |
| 4 | Revert the INT/TERM handlers to the old `trap '...' EXIT INT TERM` | RED: after TERM the hook continues and prints a decision (the signal arm asserts no decision is printed and the directory is gone) |

**Harness rows:**

| # | Edit to the SUITE | Expected |
|---|---|---|
| H2 | Snapshot the real index AFTER the hook instead of before | RED: a self-test that runs the snapshot helper against a deliberately mutated index fails |

**Anchor.** None stored; the invariants are measured against a snapshot taken by the test before the hook runs.

## Files to Edit

- `.claude/hooks/lib/commit-target-roots.sh` - walker: staging records, commit-flag parser, new `CTR_*` outputs, widened `ctr_wants_lex`.
- `.claude/hooks/git-commit-secret-scan.sh` - header comment (posture, residuals), split trap and `cleanup`, lazy `sim_dir`, the sim-lib source in the existing checked `if`, the per-root build/export/scan/unexport loop, the `deny()` note and rule id, the failure branches, updated `tooling`/`parse` repair text.
- `.claude/hooks/git-commit-secret-scan.test.sh` - the thirteen ruled test groups plus the extra rows below, the flipped pre-filter row, `cp` in `_mk_stub_path`, a new `git` PATH-shim helper, `MIN_ASSERTIONS` bump.
- `knowledge-base/engineering/operations/secret-scanning.md` - one-line note after the Architecture table that the PreToolUse hook scans the would-be index for same-command staging.
- `.claude/hooks/README.md` - a short pointer paragraph in the `git-commit-secret-scan` section (the design lives in the hook header and the decision file).
- `plugins/soleur/skills/verification-scaffold/references/guardrail-audit.md` - add the `lib/commit-index-sim.sh` row (required by `manifest.test.sh` census) and mention the new walker outputs in the `commit-target-roots.sh` row.

## Files to Create

- `.claude/hooks/lib/commit-index-sim.sh` - the shared would-be-index library.
- `knowledge-base/project/specs/feat-one-shot-10696-secret-scan-staging-gap/decision-challenges.md` - created at plan time (rows 1 to 14).
- `knowledge-base/project/specs/feat-one-shot-10696-secret-scan-staging-gap/tasks.md` - derived from this plan.

Do NOT edit `plugins/soleur/skills/work/SKILL.md` (explicit rule), `.claude/settings.json`, or `brand-hex-commit-gate.sh` (its adoption of the shared library is #10793).

## Open Code-Review Overlap

None. All planned paths were queried against open `code-review` issues; no body names any of them.

## Implementation Phases

### Phase 0 - RED (tests first, `cq-write-failing-tests-before`)

Write the new arms in `git-commit-secret-scan.test.sh` and confirm they fail against the unmodified hook (the leak cases allow; the pre-filter row fails). Reuse the suite's helpers (`_mk_pem` with an explicit non-sequential body, `_mk_repo_with_toml`, `_run`, `_decision`, `_reason`, `_mk_stub_path`, the #10609 bare-root and linked-worktree fixtures, `_needs_gl`, `_report`). Secret shapes are built by concatenation at run time; never read or print real credentials (`cq-test-fixtures-synthesized-only`). Each case that checks for leftover directories uses a private `TMPDIR` (`mktemp -t` honours it).

Test groups (pyramid layer in brackets):

1. [integration] `git add -A && git commit -m x` with an untracked leak -> deny, reason names `leak.json`, carries the would-be note and not `restore --staged`.
2. [integration] `git add leak.json && git commit -m x` -> deny.
3. [integration, must-PASS control] `git add clean.txt && git commit -m x` with an UNRELATED untracked leak -> allow; the shim log shows an exact replay (`add clean.txt`), not `add -A`; same for the quoted `git add "my file.md"` and `rtk git add clean.txt && rtk git commit`.
4. [integration] `git commit -am x`, `-a -m x`, `-sam x` with a tracked modified leak -> deny.
5. [integration] `git commit -a -m x` with an untracked leak -> allow.
6. [integration] `git commit -m x -- tracked.json` (modified, leak) -> deny; the same command with the leak in a different tracked file -> allow; `commit tracked.json -m x` (bare first word) -> deny; `-o` and `-i` forms.
7. [integration] `git add $F && git commit`, `git add -p && git commit`, `git add *.json && git commit`, brace and tilde forms, `ls | xargs git add && git commit`, `find . -name '*.json' -exec git add {} \; && git commit` -> superset (shim shows `add -A`, never `-p`); an untracked leak -> deny.
8. [integration] `.git/info/attributes` with `leak.json -diff` plus `git add leak.json && git commit` -> deny with the `-diff` message (the re-scan reads the would-be index; the shim logs the env on the `diff --cached` and `show :` lines).
9. [integration] invariants: real index sha256 unchanged, real loose-object count unchanged, working tree unchanged, no `commit-sim-*` directory left after an allow, after a deny and after a TERM (hook run against a sleeping gitleaks stub, TERM sent to the hook pid, assert no decision printed); the PATH shim shows NO sim call for plain `git commit -m x` and `git commit -n -m x` (must-PASS controls) and the lexer-skipped plain-commit path still allows (unset `CTR_*` variables do not abort the hook).
10. [integration] `cd <wt> && git add -A && git commit` from a bare-root cwd (the #10609 incident shape) -> deny; `git -C <abs wt> add clean.txt && git -C <abs wt> commit` with an unrelated leak -> allow via the proven-directory rule.
11. [integration] failures: `git add no-such-file && git commit` -> allow plus one `git-commit-secret-scan-sim-failed` bypass row (cause `pathspec-missing`), and deny when a real staged leak exists; a shim making the replay `add` exit 128 with another message -> superset; a shim failing `add -A` -> deny with "run git add as its own call, then commit" and git's first error line; the shim `mktemp` failing for the sim template -> deny; the shim `cp` failing -> deny; a sim lib that is missing -> deny for a chained commit AND a plain strict commit; perl absent -> `tooling` deny with the corrected repair text.
12. [integration] linked worktree: index at `.git/worktrees/<name>/index`, tracked blobs only in the common object store; assert the alternates path (objects) and the index path are absolute and resolve.
13. [measurement, run once, not a suite arm] latency and lexer-failure ceiling (see Phase 5).

Extra rows:

- Pre-filter must-match / must-skip table (`git add -A && git commit -m x` flips to must-match; `git commit -m x`, `git status && git commit -m x`, `git log --grep=commit` stay must-skip; must-match rows for each form in Design 2 including `--inc`, `--on`, `commit -mall` skip-vs-match pinned, heredoc message containing `git add` over-matches only).
- Walker output table: `CTR_COMMIT_STAGES`, `CTR_STAGE_OPAQUE`, records and their `tgt_known`/`exact`/`force` fields for add / stage / rm / mv / stage-unknown / loop / launcher (`rtk` exact, `xargs` not) / `x`-flagged command word forms; commit-flag table `-mall` (message, not `-a`), `-am"x"`, `-sam x`, `-Sa`, `-Sabc`, `-uall`, `-m -a`, `-m --`, `-m -p`, `--no-all`, every benign long option (each also accepted by the installed git), an unknown/abbreviated long option -> opaque.
- `git rm --cached f && git commit` still reaches the existing scan with no sim; `git rm a.txt && git mv b.txt c.txt && git commit` leaves both working-tree files in place.
- Two scanned roots, a hook cwd with no payload `cwd`, a relative single target, `git -C sub add f && git add g && git commit` (mixed directories): all superset.
- `git add -f ignored.pem && git commit` (exact replay finds it); `git add -f $F && git commit` with `$F` literal-looking ignored file -> deny "run the force-add as its own call"; `git add -f ignored.pem` with an `x` word elsewhere -> force-add of the literal word.
- A `.gitignore`d file is never added by the superset; a stray unreadable-file shim (`add -A` rc 1) -> deny naming git's first error line.
- `git add leak.json || true; git commit` (replayed), `false && git add leak.json; git commit` (scanned, over-scan direction), `bash -c 'git add -A && git commit -m x'`, a heredoc commit message containing `git add`, `git add x && git commit --amend --no-edit`, `git commit --amend -a`, `git add a && git commit -m1 && git add b && git commit -m2`.
- `terraform show -json > f && git add f && git commit` pins today's behaviour (bypass row, allow).
- Superset-caused denies carry rule id `git-commit-secret-scan-sim-deny`; pathspec commit with another staged leak still denies (pinned).
- A clean-filter marker file in the repo (`filter=` attribute): documents the residual.

### Phase 1 - walker (`commit-target-roots.sh`)

Implement Design 1. Initialise and reset the new variables; keep the existing refusal logic and `ctr_resolve_roots` untouched. Widen `ctr_wants_lex` per Design 2.

### Phase 2 - `commit-index-sim.sh`

Implement Design 4. Header states the contract, the allowlist, the failure classes, the bash 3.2 rules and the "no mktemp, no trap, no hook response, never in `$(...)`" rules.

### Phase 3 - hook glue

Implement Design 5 and the failure table. Update the header comment: new behaviour, posture table, residuals, and the bypass-row meaning.

### Phase 4 - docs

`secret-scanning.md` one-line note; `.claude/hooks/README.md` pointer; `guardrail-audit.md` rows. Re-run the verification-scaffold manifest test.

### Phase 5 - verification and measurements

Run the suite (raise `MIN_ASSERTIONS` to the measured total in the same edit), `shellcheck` on the four shell files (hook, walker, sim lib, test), `python3 scripts/lint-trap-tempfile-ownership.py` on the changed files, `bash plugins/soleur/skills/verification-scaffold/test/manifest.test.sh`, `bash plugins/soleur/test/c4-count-parity.test.sh` (expected unchanged), markdownlint on the plan and tasks. Confirm the Claude Code default hook timeout from its documentation and record it next to the 15 s deadline.

Measurements (results into the PR body):

- **Latency (AC13)**: in a scratch worktree of this repo (created under the scratchpad, removed afterwards) with 5 modified tracked files and 3 untracked files, time 20 runs each of (a) today's hook on `git commit -m x` with the files already staged and (b) the new hook on `git add -A && git commit -m x`, using `date +%s%N` around `bash .claude/hooks/git-commit-secret-scan.sh < payload`. p95 = the 19th of the 20 sorted samples. Report the added p95 (b minus a) and p50; also one superset run with about 5,000 untracked files. If the added p95 exceeds 1.5 s the decision flips to KEEP-OPEN: do not ship, record a row in `decision-challenges.md` and report.
- **Lexer-failure ceiling (AC14)**: extract only the command text of the sampled local `git commit` Bash lines from session transcripts with a read-only `jq` script (counts only, no content printed), run each through the new pre-filter and `ctr_collect`, and report how many land in `lex_state=unavailable` or a `CTR_BAD` deny that did not before (ceiling: under 0.5 percent). Also tabulate how often `scan_roots` has more than one entry across the three topologies (bare-root-anchored, worktree-anchored, main-checkout-anchored with `cd` into a worktree), since two roots forces the superset.

### Phase 6 - ship items

PR body: `Closes #10696`; a separate line `Ref #10331` (non-closing, the epic stays closed); the latency and ceiling numbers; one follow-up issue listing the named residuals (script-wrapped staging, content created earlier in the same command, positional path after `-m`, filters/LFS), milestone from `knowledge-base/product/roadmap.md`; the `## Changelog` section; the ending line `🤖 Generated with [Claude Code](https://claude.com/claude-code)`. Commit messages end with `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`. No `git stash` anywhere.

## Domain Review

**Domains relevant:** Engineering (CTO)

### Engineering

**Status:** reviewed
**Assessment:** The CTO ruled three times on 2026-10-23: the ship decision and mechanism, seven residual forks, and seven forks from plan review (rows 1 to 14 of the decision file). No Product/UX surface (no file under a UI path), no legal or regulated-data surface (no schema, auth flow, API route or `.sql`; no new processing of personal data; the only data touched is the developer's own working tree, written to a mode-0700 temp directory and removed), no marketing, finance, sales or support implication. Infrastructure gate: no server, secret, vendor or DNS change. Encryption posture gate: no persistent store and no network connection (an ephemeral local temp directory only).

## Plan Review Revisions

Panel: code-simplicity, strict-correctness (Kieran lens on shell), spec-flow; the Rails-specific DHH reviewer and the named CEO/design panel were not run (a bash hook with no UI or market surface; the CTO had already ruled three times). Mechanical findings applied: unset `CTR_*` aborts the lexer-skipped path (initialise at top level, read with `:-0`); every `cis_*` call and `mktemp` explicitly checked, `sim_dir` declared before the trap; INT/TERM trap does not terminate (split trap); `--ignore-errors` exits 1 (dropped); `q` flag misread (fixed); object path made absolute, `:` rejected; `scan_root` byte-identity check via function-body extraction and per-invocation env logging in the git shim; `cp` in the stub PATH; hard 1.5 s p95 definition; `rm`/`mv` out of the walker; `CTR_DIRS` and the `ctr_resolve_roots` edit dropped (directory derived in the glue); lazy source dropped; add-count snapshot dropped; wrong `restore --staged` advice on a would-be finding replaced by the `deny()` note; distinct deny rule id; one total deadline; commit-flag parser completed (attached operands, optional-argument flags, benign-option table, `--no-` forms); stage-unknown list extended (`pull switch rebase submodule sparse-checkout`); non-literal command word; the lexer-failure ceiling AC and corrected `tooling`/`parse` repair text; mutation matrices trimmed (14 plus 4 rows to 10 plus 1 and 4 plus 1); README reduced to a pointer; revert rehearsal and `umask 077` removed. Taste and technical forks went to the CTO (decision rows 8 to 14).

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Implement and ship issue #10696 (hooks: git-commit-secret-scan scans the index before the same command's git add / commit -a runs)." [brief] | Phases 0-6; Files to Edit / Create | mapped |
| 2 | "Closes #10696 in the PR body." [brief] | Phase 6, AC15 | mapped |
| 3 | "add a non-closing reference line to the closed code-quality epic (number 10331) in the PR body, written as "Ref #" followed by 10331, no closing keyword. Do not reopen that epic." [brief] | Phase 6, AC15 | mapped |
| 4 | "Extend `_ctr_git_walk` in `.claude/hooks/lib/commit-target-roots.sh` to record per commit record: flags/pathspec ... Export `CTR_COMMIT_STAGES` ... and `CTR_ADD_ARGV`." [brief design 1] | Phase 1, Design 1 | mapped |
| 5 | "Simulation runs only when CTR_COMMIT_STAGES=1; plain `git commit -m x` pays nothing." [brief design 2] | Design 2-3, Phase 3, AC8 | mapped |
| 6 | "New `.claude/hooks/lib/commit-index-sim.sh` (shared; a later brand-hex-gate follow-up reuses it)." [brief design 3] | Phase 2, Files to Create | mapped |
| 7 | "Call existing `scan_root` unchanged with GIT_INDEX_FILE exported around it" [brief design 4] | Design 5, Phase 3, AC9 | mapped |
| 8 | "Failure: failed exact replay -> scan what was built + emit a `git-commit-secret-scan-sim-failed` bypass row; failed superset or temp-dir failure -> DENY ... No `ask`" [brief design 5] | Design 6, AC11 | mapped |
| 9 | "Files: `.claude/hooks/lib/commit-target-roots.sh`, new `.claude/hooks/lib/commit-index-sim.sh`, `.claude/hooks/git-commit-secret-scan.sh`, `.claude/hooks/git-commit-secret-scan.test.sh`, the header comment in git-commit-secret-scan.sh, and a one-line note in `knowledge-base/engineering/operations/secret-scanning.md`." [brief] | Files to Edit / Create | mapped |
| 10 | "Tests (TDD first; reuse the suite's synthesized-fixture helpers ...) (1) ... (13) latency" [brief] | Phase 0 groups 1-13, Phase 5, AC1-AC13 | mapped |
| 11 | "Also record the decision-challenge entry in the feature's decision-challenges.md ..." [brief] | `decision-challenges.md` row 1 (created at plan time) | mapped |
| 12 | "Never edit plugins/soleur/skills/work/SKILL.md. No git stash. Commit messages end with ... PR body ends with ..." [brief] | Files section note, Phase 6, AC15 | mapped |
| 13 | "Fix-Size medium." [brief] | Split Assessment | mapped |
| 14 | "never ask the operator a technical question ... spawn `soleur:engineering:cto` ... Persist every decision as a row" [brief] | `decision-challenges.md` rows 2-14 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `commit-target-roots.sh` walker changes | "Extend `_ctr_git_walk` in `.claude/hooks/lib/commit-target-roots.sh`" | asked |
| `commit-index-sim.sh` | "New `.claude/hooks/lib/commit-index-sim.sh`" | asked |
| Hook glue and header comment | "the header comment in git-commit-secret-scan.sh" | asked |
| Test suite arms | "Tests (TDD first ...)" | asked |
| `secret-scanning.md` note | "a one-line note in `knowledge-base/engineering/operations/secret-scanning.md`" | asked |
| `decision-challenges.md` | "record the decision-challenge entry in the feature's decision-challenges.md" | asked |
| Pre-filter widening (`ctr_wants_lex`) | "plain `git commit -m x` pays nothing" | inferred - justification: detecting a chained add needs the lexer's argv; without widening the pre-filter the walker never runs for 77 percent of commits and the feature is dead code (CTO row 7) |
| `rm`/`mv` ignored by the walker | "any earlier `git add\|rm\|mv\|stage` argv" | inferred - justification: replaying them mutates the working tree and they add no content (CTO rows 2, 9) |
| Stage-unknown verbs forcing the superset | "otherwise ... fall back to superset `git add -A`" | inferred - justification: staging the replay cannot see would leave the hole this hook exists to close (CTO row 5) |
| Pathspec ladder `add -u -- paths` | "`commit -- path` scanned" | inferred - justification: a strict subset of the ruled superset that avoids false denies (CTO row 3) |
| One-root and proven-directory exactness rule | "exact replay" | inferred - justification: a misapplied replay hides content from the scan (CTO rows 4, 8) |
| Failure-class split on replay failure | "failed exact replay -> scan what was built + emit a ... bypass row" | inferred - justification: an infrastructure failure must not become an allow (CTO row 8) |
| Unknown `--long` commit option forces the superset | "otherwise ... fall back to superset" | inferred - justification: git accepts unique abbreviations of staging options (CTO row 10) |
| Force-add of literal words in the superset | "fall back to superset `git add -A`" | inferred - justification: `add -A` never sees ignored files, where `.env` and key files live (CTO row 12) |
| Split trap, `deny()` note, distinct deny rule id, one total deadline | "failed superset or temp-dir failure -> DENY" | inferred - justification: the INT/TERM trap does not end the hook (measured), a would-be finding is not staged so `restore --staged` advice loops, and per-call timeouts can exceed the harness hook timeout |
| `.claude/hooks/README.md` pointer | — | inferred - justification: the README documents this hook's behaviour (the #10609 section); leaving it stale makes the docs lie about what is scanned |
| `guardrail-audit.md` row | — | inferred - justification: `verification-scaffold/test/manifest.test.sh` reds CI for any hook file without an audit row |
| `MIN_ASSERTIONS` bump | — | inferred - justification: the floor is exactly the current 405; without raising it in the same edit the floor stops guarding the new rows |
| Follow-up issue listing the residuals | — | inferred - justification: CTO rows 5 and 11 require a tracked residual; a deferral without an issue is invisible |

### Split Assessment

- Subsystems touched: 3 - `.claude`, `knowledge-base`, `plugins`
- Planned files: 9 | Estimated changed lines: about 800 (tests ~400, sim lib ~170, walker ~170, hook glue ~60)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR (cohesive; the CTO ruled Fix-Size medium and "ship as its own PR"; at the 800-line edge the test file dominates and the library/walker split would leave the hook half-wired)

## Acceptance Criteria

- [ ] AC1 (cases 1, 2, 7, 10): each of `git add -A && git commit -m x`, `git add leak.json && git commit -m x`, `git add $F && git commit -m x`, the glob form, the `xargs` and `find -exec` forms and `cd <wt> && git add -A && git commit -m x` from a bare-root cwd returns `permissionDecision: deny` with a reason naming `leak.json`. Verify: the new suite arms pass (`bash .claude/hooks/git-commit-secret-scan.test.sh`).
- [ ] AC2 (case 3, must-PASS control): `git add clean.txt && git commit -m x`, the quoted `git add "my file.md"` form and the `rtk` form, each with an unrelated untracked leak, are allowed, and the shim log shows an exact replay and no `add -A`.
- [ ] AC3 (cases 4, 5): `commit -am` / `-a -m` / `-sam` with a tracked modified leak denies; `commit -a` with an untracked leak is allowed (`add -u`, falling back to `add -A` only on failure).
- [ ] AC4 (case 6): `commit -- tracked.json` denies when that file holds the leak and allows when the leak is in a different tracked file; the bare-first-word and `-o` / `-i` forms behave the same. A positional path after `-m "..."` is documented as a residual, not tested as covered.
- [ ] AC5 (case 7): `git add -p`, `$F`, glob/brace/tilde, `xargs` and `find -exec` forms use the superset: the shim log shows `add -A` and never `add -p`.
- [ ] AC6 (case 8): a `-diff` gitattribute plus a chained add is still denied, with the `-diff` message, and the shim env log shows the sim variables on the `diff --cached` and `show :` calls.
- [ ] AC7 (case 9): after every hook run (allow, deny, TERM), the real index sha256, the real loose-object count and the working tree are identical to their pre-run snapshots, and no `commit-sim-*` directory remains; the sim directory is mode 0700; after TERM no decision is printed.
- [ ] AC8 (case 9): for plain `git commit -m x` and `git commit -n -m x` the PATH shim logs no sim call, the lexer-skipped path still allows with the new `CTR_*` variables unset, and `ctr_wants_lex 'git commit -m x'` and `'git status && git commit -m x'` return false.
- [ ] AC9: the body of `scan_root` is byte-identical to its pre-change body (extract `awk '/^scan_root\(\) \{/,/^}/'` from `git show origin/main:.claude/hooks/git-commit-secret-scan.sh` and from the working file, `diff` is empty); the exported variables reach `gitleaks`, `git diff --cached`, `git check-attr` and `git show` (per-invocation env log in the git shim plus a gitleaks stub that records `$GIT_INDEX_FILE` inside the call).
- [ ] AC10 (case 12): in a linked worktree the sim copies `.git/worktrees/<name>/index` and resolves blobs that exist only in the common object store; the index and objects paths are absolute.
- [ ] AC11 (case 11): the user's own missing pathspec -> allow (when clean) plus one `git-commit-secret-scan-sim-failed` row; any other replay failure -> superset; failed superset, `mktemp` failure, `cp` failure -> deny with "run git add as its own call, then commit" (and git's first error line when there is one); a missing sim lib denies chained and plain strict commits; perl absent denies a chained commit with the `tooling` text.
- [ ] AC12: `git rm a.txt && git mv b.txt c.txt && git commit -m x` leaves both working-tree files in place and runs no sim; a stage-unknown verb, a loop in the text, a relative single target, a mixed-directory command, a missing payload `cwd` and two scanned roots each force the superset (shim log); a force-added ignored file is covered by the exact replay and denied-with-repair when its words are non-literal.
- [ ] AC13 (case 13): measured added p95 (19th of 20 sorted samples) on a scratch worktree of this repo (about 19.9k tracked files) is at most 1.5 s; the numbers (and the 5k-untracked superset run) are in the PR body. If above, STOP: decision flips to KEEP-OPEN, not shipped, reported to the operator.
- [ ] AC14: suite green with `MIN_ASSERTIONS` raised to the measured total; `shellcheck` clean on the four shell files; `python3 scripts/lint-trap-tempfile-ownership.py` clean on the changed files; `bash plugins/soleur/skills/verification-scaffold/test/manifest.test.sh` green; markdownlint clean on the plan and tasks; the lexer-failure ceiling measured and under 0.5 percent, with the count in the PR body.
- [ ] AC15: PR body contains `Closes #10696` and a separate `Ref #10331` line with no closing keyword, ends with `🤖 Generated with [Claude Code](https://claude.com/claude-code)`; every commit ends with `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`; `plugins/soleur/skills/work/SKILL.md` is absent from `git diff --name-only origin/main...HEAD`; `knowledge-base/project/specs/feat-one-shot-10696-secret-scan-staging-gap/decision-challenges.md` has the fourteen rows (`grep -c '^| [0-9]' ...` returns 14).
- [ ] AC16 (diff scope): the final diff is a subset of the Files to Edit / Create above plus the files the pipeline itself writes (`knowledge-base/INDEX.md` if regenerated, `specs/<branch>/session-state.md`, the plan and tasks).

## Test Scenarios

- Given an untracked file holding a synthetic PEM and the command `git add -A && git commit -m x`, when the hook runs, then it denies and names the file (integration).
- Given the same untracked file and the command `git add clean.txt && git commit -m x`, when the hook runs, then it allows (exact replay does not pull the unrelated file in) (integration).
- Given a tracked file modified to hold the PEM and `git commit -am x`, then deny; given the PEM in an untracked file and `git commit -a -m x`, then allow (integration).
- Given `git add no-such-file && git commit -m x`, when the replay fails with the user's own pathspec error, then the hook scans the built index, emits the bypass row and allows if clean (integration).
- Given a shim that fails `git add -A`, when a superset is needed, then the hook denies with the repair text (integration).
- Given `git add -A && git commit` in a linked worktree whose blobs are only in the common store, then the sim builds and the leak is found (integration).
- Given a plain `git commit -m x`, then no sim code runs (integration with the PATH shim, plus unit rows on `ctr_wants_lex`).
- Properties that must never break (a generated command table in the suite, not an example list): for every row the (`CTR_COMMIT_STAGES`, exact-vs-superset) choice stages a superset of what the command's literal words stage; no row lets the real index sha256, real object count or working tree change (unit + integration).
- Regression: the full pre-existing 405 assertions still pass (the #10609 target-resolution arms, T5 to T20 and the walker table).

## Success Metrics

- The thirteen ruled groups pass, with the mutation matrices above driven RED at least once each during Phase 5 (apply the mutation, observe the named red, revert).
- Added p95 latency at most 1.5 s on this repo.
- Zero change in the allow/deny decision for the pre-existing 405 assertions.

## Dependencies & Risks

- **Dependency**: `perl` and `plugins/soleur/hooks/lib/shell-argv.pl` (already required by the #10609 walker); `cp`; gitleaks 8.24.2 in CI (the pin). Behaviour with `GIT_INDEX_FILE` was measured on 8.30.1 locally, so the real-gitleaks arms in CI are the cross-version proof. A CI failure there is a design-level signal, not a flake.
- **Risk - false denies**: the superset (`add -A`) scans unrelated untracked, non-ignored files. Accepted by the ruling for the fallback shapes (`$F`, `-p`, globs, stage-unknown verbs, multi-root, unknown options); the deny text names the root and the repair, and the distinct `sim-deny` ledger id makes the rate measurable. Two scanned roots (a main-checkout session `cd`-ing into a worktree) force the superset; Phase 5 tabulates how often.
- **Risk - hook timeout**: the 15 s total deadline is deliberate and sits under the harness default, which Phase 5 confirms from the documentation; an expiry is a deny (superset) or a rebuild (exact).
- **Risk - lexer failure modes now reach most commits**: about 77 percent of commits now take the lexer path, so a lexer error, the 2 s alarm under parallel-suite load, a bound, or a missing perl now denies a chained commit that used to skip it. Mitigated by the corrected repair text, the ceiling measurement (AC14) and the unchanged "a plain `git commit` with no staging verb" fast path.
- **Risk - walker under-recognition**: a staging form the pre-filter or walker does not classify keeps today's behaviour (not a regression, still a gap). The over-matching pre-filter, the stage-unknown verb list and the unknown-option rule are the mitigation; the named residuals are in the header and the follow-up issue.
- **Risk - suite runtime**: the existing suite already takes minutes locally under load (CI shard leg 4 of `scripts/suite-shard-legs.tsv`); the new arms add real-gitleaks runs. Keep new arms on small temp repos.
- **Rollback**: revert the PR; no data or state outside the repo is created.

## References & Research

- Issue #10696; closed epic #10331 (reference only); draft PR #10893; follow-up consumer #10793 (brand-hex gate cwd binding).
- `.claude/hooks/git-commit-secret-scan.sh` (`scan_root`, `deny_undeterminable`, the trap), `.claude/hooks/lib/commit-target-roots.sh` (`_ctr_git_walk`, `ctr_wants_lex`, `ctr_resolve_roots`, `_ctr_has_loop`), `plugins/soleur/hooks/lib/shell-argv.pl` (output contract: per-word flags `-`, `q`, `x`, `qx`).
- `.claude/hooks/README.md` section "git-commit-secret-scan target resolution (#10609)".
- ADR-156, ADR-157, ADR-165 (hook input untrusted; ask when unparseable; what `ask` means headless), ADR-129 (tempfile ownership).
- Learnings listed under Research Insights.
