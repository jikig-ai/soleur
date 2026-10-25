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

## Enhancement Summary

**Deepened on:** 2026-10-23
**Agents used:** learnings-researcher; plan-review panel (code-simplicity, strict-correctness on shell, spec-flow); deepen panel (security-sentinel, performance-oracle, test-design-reviewer, architecture-strategist); the CTO agent three times (ship decision and mechanism; plan-review forks; deepen forks). Deviation from the skill's "run every agent" rule: the Rails-specific reviewers, the UI/legal/marketing/finance leaders and the 40-agent sweep were not run - the surface is one bash hook with no UI, schema, or regulated-data content - and the four other gates (4.6 to 4.12) were run by hand.

### Key improvements from deepening

1. The "proven directory" rule was unsound (the walker's target union cannot prove a `cd` took effect; `HOOK_CWD` is never empty). Replaced by an explicit proof rule (decision row 15).
2. `pathspec-missing` is no longer allowed outright: a file created earlier in the same command is a trivially steerable bypass of the very incident this hook exists for. Superset rebuild plus a producer check (row 16).
3. Hook-time code execution: `git add` on a temp index runs configured clean filters and, with `core.splitIndex`, writes into the REAL `.git`. Every sim git call is pinned (row 18); config-transforming staging arguments are refused (row 17).
4. Measured performance hazards: `scan_root`'s per-path `git check-attr` loop costs 83 s at 5,000 paths (one batched edit, row 19); gitleaks costs about 1.3 s per MB of high-entropy untracked text and was unbounded in sim mode (row 20).
5. The library API was re-cut so the brand-hex gate (#10793) can reuse construction without inheriting the secret-scan policy (row 21).
6. Test design: several planned RED arms were already green (fixtures staged the leak); the TERM arm, the PATH shim, the snapshot helper and the suite-runtime budget are now specified.

### New considerations discovered

- The INT/TERM trap does not end a bash script (measured), `--ignore-errors` still exits 1 (measured), `env gitleaks` bypasses a shell-function shadow (the bound is a PATH wrapper), `timeout 0` is unbounded (measured), the harness default hook timeout is 600 s (documentation), and the existing suite takes about 187 s locally against a 6.9 s duration-table weight.

## Overview

Spec lacks valid lane: - defaulted to cross-domain (TR2 fail-closed); there is no `spec.md` for this branch.

The commit-time secret scan (`.claude/hooks/git-commit-secret-scan.sh`, a PreToolUse hook on Bash) runs gitleaks over the staged index before the Bash command it guards has executed. A single command that stages and commits (a chained `git add ... && git commit`, `git commit -a`, `git commit -am`, `git commit -- <path>`) is therefore scanned against an index that does not yet hold the content the commit will record. A secret in the working tree passes unscanned. Staging in a separate earlier call is the only fully covered shape.

The CTO ruled (2026-10-23, recorded in `knowledge-base/project/specs/feat-one-shot-10696-secret-scan-staging-gap/decision-challenges.md`) that this ships now as its own PR, and rejected the issue's `git diff HEAD` candidate (it misses untracked files and over-scans). The mechanism is a **simulated would-be index**: the hook copies the real index to a temp file, replays the command's own staging verbs onto the copy (exact replay when every word is literal and the directory is proven, superset `git add -A` otherwise), and runs the existing `scan_root` with `GIT_INDEX_FILE` and a quarantined object directory exported around it. Nothing in the real index, real object store, real git directory or working tree is touched.

Measured motivation (ruling evidence): about 77 percent of roughly 2,900 sampled agent `git commit` Bash lines are chained add-then-commit, about 1 percent use `commit -a`, 16 use a `--` pathspec. lefthook runs `gitleaks-staged` only at pre-commit (no pre-push) and the CI `secret-scan` workflow only runs after a push, so for an agent this hook is the only pre-history gate.

## Research Reconciliation — Spec vs. Codebase

| Claim in the brief / issue | Reality (verified) | Plan response |
|---|---|---|
| Issue candidate: scan `git diff HEAD` of the resolved roots | `git diff HEAD` does not list untracked files, so `git add -A && git commit` of a new file passes; it also over-scans unstaged edits the commit will not record | Rejected by the CTO ruling; the would-be index is the design |
| "Plain `git commit -m x` pays nothing" | `ctr_wants_lex` currently SKIPS the lexer for `git add -A && git commit -m "fix: tidy"` and the suite pins that as a must-skip row (T39 pre-filter table). Detecting staging needs the lexer's argv | Phase 1 widens `ctr_wants_lex` (anchored; measured 5 percent incremental lexer rate on 400 real commit messages with the anchored positional clause versus 33 percent unanchored); the must-skip row flips to must-match |
| Replay `git add\|rm\|mv\|stage` argv | `git rm` and `git mv` act on the WORKING TREE and add no new blob content | CTO rows 2 and 9: the walker recognises and ignores them |
| Pathspec commit falls back to superset `git add -A` | `commit -- p` records exactly the working-tree content of tracked `p` | CTO row 3: `git add -u -- <literal paths>`, then `git add -u`, then `git add -A` only if both fail |
| Exact replay of literal add args in "the" directory | The walker keeps a UNION of cd / `-C` targets: `false && cd /tmp/x; git add f`, `(cd /tmp/x); git add f` and `cd /tmp/x \|\| true; git add f` each yield one absolute target; `HOOK_CWD` falls back to `DEVIN_PROJECT_DIR` / `CLAUDE_PROJECT_DIR` / `PWD` (`lib/hook-input.sh:403`) so it is never empty | CTO rows 4, 8, 15: exact replay only with one scanned root AND the explicit directory proof of Design 4 |
| A missing pathspec is the user's own error | The lexer drops redirects (`printf x > leak.json && git add leak.json && git commit` lexes to three plain records), so a file created earlier in the same command is missing at hook time and present at run time | CTO row 16: superset rebuild, plus a DENY when an earlier producer exists |
| `scan_root` stays byte-identical | `scan_root` runs `git check-attr` and `sed` once per staged path: 83 s at 5,000 paths, a batched `git check-attr -z --stdin diff` takes 43 ms (same result) | CTO row 19: ONE behaviour-preserving edit (batch the loop) is permitted; the rest stays byte-identical |
| `_mk_pem` yields a detectable fixture | Measured with the pinned `.gitleaks.toml`: the default `_mk_pem` body (a sequential-alphabet run) is allowlisted by stopwords and scans clean (rc 0); a body such as `t5_syntheticpayload_1234` is detected (rc 1) | Every new leak fixture passes an explicit non-sequential body |
| Reused leak fixtures give RED arms | `_mk_leaky_repo` and `_mk_bare_root_with_worktree leak` both `git add leak.json`, so the unmodified hook already denies | New fixture modes `untracked` and `tracked-modified`; every deny arm gets a gap-witness control (plain `git commit -m x` on the same shape allows) |
| The hook's own mktemp calls are covered by its trap | `scripts/lint-trap-tempfile-ownership.py` rule (c) flags a NEW file that calls `mktemp` with no `trap ... EXIT` | The lib calls no `mktemp`; the hook allocates the sim directory and its EXIT trap removes it |
| New hook libs need no registration | `plugins/soleur/skills/verification-scaffold/test/manifest.test.sh` fails when a `.claude/hooks/**/*.sh` basename has no row in `guardrail-audit.md` | Files to Edit gains the audit row |
| gitleaks honours `GIT_INDEX_FILE` / `GIT_OBJECT_DIRECTORY` | Measured (gitleaks 8.30.1): a synthetic PEM present only in the sim index is found (rc 1); real index bytes and loose-object count unchanged; `git check-attr` and `git show :path` read the sim index. CI pins 8.24.2 | Design stands; the canary arms are also run against the pinned 8.24.2 tarball before pushing (Phase 5) |
| The `INT`/`TERM` trap ends the hook | Measured: bash runs the handler and CONTINUES, so `trap '...' EXIT INT TERM` would delete the sim dir mid-run and the hook could end in `allow` | Phase 3 splits the trap: `EXIT` cleans up, `INT`/`TERM` call `exit 130`/`exit 143` |
| `git add -A --ignore-errors` tolerates unreadable files | Measured: indexes the readable files and still exits 1 | Not used; a failing superset denies and quotes a sanitised first error line (row 14) |
| Lexer flag `q` means "contains a glob" | `shell-argv.pl` defines `q` as "some part of the word was quoted or backslash-escaped" | Literalness: reject flag `x`; reject `* ? [ { ~` only in an unquoted word |
| `git add` on a temp index is side-effect free | With `core.splitIndex=true` it writes `sharedindex.<sha>` into the REAL git dir (measured); it runs `filter.*.clean` (new hook-time execution, measured); `core.fsmonitor` can start a daemon | CTO row 18: pin every sim git call; real-gitdir listing becomes a Guard 2 invariant |
| The `timeout` wrapper bounds the work | `timeout 0` means unbounded (measured); stock macOS has neither `timeout` nor `gtimeout`; `scan_root` calls `env ... gitleaks`, which bypasses a shell-function shadow | CTO row 20: integer ceiling of at least 1, perl `alarm` fallback, PATH wrapper for gitleaks |

## Research Insights

**Premise validation (Phase 0.6).** `gh issue view 10696`: OPEN, title matches. `gh issue view 10331`: CLOSED (the code-quality epic; reference only, never reopened). Draft PR 10893 is open. `gh issue view 10793` (brand-hex-commit-gate resolves its repo from the process cwd): OPEN, the named later consumer of the shared sim library. No ADR in `knowledge-base/engineering/architecture/decisions/` mentions a would-be index or a quarantined object directory; ADR-156/157/165 govern the deny-not-ask posture. Open code-review issues touching any planned file: none.

**Property List (Phase 0.6b).**

1. Content the command's own staging verbs or commit flags will record is in the index gitleaks scans (scoped to content in the working tree; see the named residual for content a verb brings from outside it).
2. A plain `git commit -m x` costs no more than today (no simulation, no new git call).
3. The simulation never changes the real index, the real object store, the real git directory or the working tree.
4. When the simulation cannot be built, or its scan cannot be bounded, a commit that could not be scanned is blocked; only the provably-benign missing pathspec warns.
5. The shared library is reusable by the brand-hex gate (#10793) without edits to its construction logic.

**Cut List.** `git diff HEAD` candidate (misses untracked files; CTO). A bash-only fast path or cache for the lexer (a second parser; CTO row 7). A new override variable for the deny (an override is the skip). Replaying `rm`/`mv` (mutates the working tree, adds no content). `--ignore-errors`, a "last commit wins" add-count snapshot, `CTR_DIRS` and an edit to `ctr_resolve_roots`, a lazily sourced sim lib, `umask 077`, a content-size proxy, an in-band record delimiter: each bought no property after review.

**Measured cost (Phase 0.6c; commands in the scratchpad scripts the reviewers named).** This host, 19,855 tracked files, 3.29 MB index, git 2.56.0, gitleaks 8.30.1, host load 15 to 41 during measurement:

- Lexer: about 16 to 21 ms per call, `ctr_collect` about 30 ms at 10 KB and about 80 ms at 80 KB.
- Index copy 23 ms p50; `add -A` on the copy: clean tree 131 ms, 8 changed files 161 ms, 5,000 untracked 699 ms, one 50 MB file about 2 s; `add -u` 47 to 132 ms; `add <file>` 34 to 95 ms.
- gitleaks floor about 0.55 s even with nothing staged; scanning the sim index is as fast as scanning a real one (908 versus 900 ms for 8 files). High-entropy untracked text costs about 1.3 s per MB (1 MB 1.4 s, 5 MB 6.8 s, 10 MB 13 s, 20 MB 21 s); binaries cost only the `add` hash time.
- Added work on the small path: about +350 ms p50 and +500 ms p95 (summed pieces), well under the 1.5 s gate; end-to-end hook baseline under load was 3.5 s p50 with a spread of about 1 s, so a separate-batch p95 subtraction is noise-limited: the AC13 method is interleaved (Phase 5).
- Pre-filter regexes: about 5 ms typical, about 10 ms worst case at 10 to 13 KB, no quadratic blow-up.
- The existing suite takes about 187 s locally (about 2.3 s per real-gitleaks hook run) against a 6,938 ms weight in `scripts/suite-durations.tsv`.

**Institutional learnings applied.**

- `2026-10-22-a-closed-world-recogniser-in-a-fail-open-hook-and-a-depth-bound-that-did-not-bound-work.md`: the walker over-recognises; every cap in the new path denies rather than skips.
- `2026-09-04-a-10-of-10-mutation-score-and-ten-escapes-it-could-not-see.md` and `2026-04-03-git-env-var-leak-resolve-git-root-test.md`: a hook in a linked worktree exports absolute `GIT_DIR` / `GIT_INDEX_FILE`; the sim sets its own variables and the tests scrub ambient `GIT_*`.
- `2026-07-05-composite-safety-hook-authoring-pitfalls.md`: a bare `source` under `set -e` aborts the hook (fail-open); every new call is explicitly checked.
- `2026-09-14-git-hook-env-prefix-scrub-and-anchored-recovery-grep.md`: a replay arm must not be gated on env the hook's own environment can set or unset.
- Plan-sharp-edges items applied (the catalogue was read in full for its first 60 entries and keyword-scanned for the rest: the file is 238 KB): a tool's effect on a sandbox is the oracle, not its report; `cmd | grep -q` under `pipefail`; every mutation row needs a must-PASS control; the orphan-suite and trap-ownership lints; markdownlint on plan and tasks.

## Problem Statement

`git-commit-secret-scan.sh` ends with `gitleaks git --pre-commit --staged` against the real index. For `git add -A && git commit -m x`, `git commit -a`, `git commit -am x` and `git commit -- <path>`, the index the commit will record does not exist yet when the hook runs. Result: a credential in a new or modified file is committed to local history and caught, if at all, by CI after the push, when rotation or a history rewrite is already required.

## Proposed Solution

> **Superseded by the review-round rulings (decision rows 22 to 46); ADR-300 is the shipped contract.** There is no
> producer detection (`CTR_STAGE_PRODUCER`), no return code 10 and no `git-commit-secret-scan-sim-failed` bypass row: a
> trusted `pathspec-missing` always DENIES (`cause=pathspec-missing`, row 25). `CTR_ADD_META` is six parallel arrays plus
> `CTR_ADD_ARGV`; `ctr_stage_dump` lives in the test suite (row 38). There is no `timeout`/`gtimeout` ladder, wrapper
> or stale sweep: one perl fork/waitpid/kill bound (row 30) and a marker-gated sweep (row 45). Every strict commit is
> lexed where perl exists and a perl-less host reads only a single simple commit unread (rows 22, 46). With a proven
> directory only the root of `CIS_TOP` is simulated and the other roots are scanned on their real index (row 33). A
> finding keeps the rule id `git-commit-secret-scan`; only a simulation failure is `-sim-deny` (row 34).

### Design (CTO-ruled; refinements are in the decision rows)

1. **Walker records staging** (`.claude/hooks/lib/commit-target-roots.sh`). `_ctr_git_walk` learns:
   - `add` / `stage`: one record per command, validated in the walker (where the lexer flag per word is in hand). Stored as scalar metadata plus a flat word array (no in-band delimiter): `CTR_ADD_META[i]="tgt_known:exact:force:nwords:own_C"` and the flat words in `CTR_ADD_ARGV`. `exact=0` when: any word has lexer flag `x`; an unquoted word contains `* ? [ { ~`; any word contains a byte below 0x20 or 0x7f; any option before `--` is outside the allowlist (checked on EVERY word before `--`, including words after the pathspec, per character for short bundles); a pathspec-semantics global option or `git -c` precedes the verb; the record was reached through a launcher that is not in the pass-through allowlist (`rtk timeout nice sudo env command exec flock`; everything else, including `mise exec`, `xargs`, `parallel`, `find`, `watch`, `su`, `ssh`, is non-exact). `force=1` for `-f`/`--force` including bundles like `-fA`. `own_C` is the absolute `-C` path attached to that record, if any.
   - `rm` / `mv`: recognised and ignored (rows 2, 9).
   - Stage-unknown verbs `apply|update-index|checkout|cherry-pick|merge|revert|stash|am|read-tree|restore|pull|switch|rebase|submodule|sparse-checkout`, and an `x`-flagged command word followed by a staging word: set `CTR_STAGE_OPAQUE` (superset).
   - Config-transforming staging arguments (row 17): set `CTR_STAGE_REFUSE` with `CTR_STAGE_REFUSE_WHY`; the glue denies "stage in its own call".
   - Producer facts (row 16): `CTR_STAGE_PRODUCER=1` when `_CTR_TEXT` contains an output redirect, `tee`, `sed -i` or `--write`, or any command word before the first add outside git / cd / pushd / env / pass-through launchers / true / test / echo.
   - The commit's own flags (`_ctr_commit_flags`): short bundles scanned character by character - `a` and `p` -> all (`add -u` covers `-p`), `o`/`i` -> paths mode, `m F C c t` consume the rest of the word as their operand or the next word if nothing is attached (so `-malpha` is a message, not `-a`), `S` and `u` take only an attached remainder and end the bundle. Long options: an exact table of staging options (`--all --only --include --patch --interactive --pathspec-from-file`) and an exact table of benign options from `git commit -h` (separate-operand ones: `--message --file --author --date --reuse-message --reedit-message --fixup --squash --trailer --template --cleanup --unified --inter-hunk-context`; `--no-all|--no-only|--no-include|--no-patch` clear the fact); any other `--long` option, including a unique-prefix abbreviation, sets `CTR_STAGE_OPAQUE` (row 10). `--` starts the pathspec; positional words are paths.
   - Outputs: `CTR_STAGE_API=1`, `CTR_COMMIT_STAGES`, `CTR_STAGE_OPAQUE`, `CTR_STAGE_REFUSE(_WHY)`, `CTR_STAGE_PRODUCER`, `CTR_ADD_META`, `CTR_ADD_ARGV`, `CTR_COMMIT_ALL`, `CTR_COMMIT_PATHS`, `CTR_COMMIT_PATHS_LITERAL`, `CTR_STAGE_CD_FIRST` (the shape of row 15 (iii)). One `_ctr_reset_stage` initialises them at library top level (next to `CTR_COMMIT_SEEN=0`) and is called again from `ctr_collect` - an unset variable under `set -u` on the lexer-skipped plain-commit path would otherwise abort the hook, which fails open; the hook reads `${CTR_COMMIT_STAGES:-0}`. `ctr_stage_dump` prints a canonical text form that the tests assert on, so the encoding can change later. Every add record in the command is replayed regardless of position (an add after the last commit is merely over-scanned; row 14). `ctr_resolve_roots` is NOT edited.
2. **Pre-filter** (`ctr_wants_lex`) also returns true for: a stage-capable git verb with a word boundary (`git[[:space:]]+(add|stage|apply|update-index|checkout|cherry-pick|merge|revert|stash|am|read-tree|restore|pull|switch|rebase|submodule|sparse-checkout)([[:space:]]|$)`); a commit short bundle `[[:space:]]-[^-[:space:]]*[aoip]` after `commit`; a long option beginning `--(al|o|in|pa)`; a bare ` -- `; and, anchored to git, `git[[:space:]]+commit[[:space:]]+[^-"'$&|;)[:space:]]` (a bare non-option first word). A positional after a `-m "..."` is NOT detected (row 11: a named residual). It over-matches by design; a pinned must-match / must-skip table covers each form, including `git commit -m "fix the commit scan"` and `git addr` as must-skip.
3. **Simulation is conditional**: runs only when `CTR_COMMIT_STAGES=1` (any add/stage record, `CTR_STAGE_OPAQUE`, or a commit-flag fact). A plain `git commit -m x` reaches no new code and allocates nothing.
4. **New shared library** `.claude/hooks/lib/commit-index-sim.sh` (no `mktemp`, no `trap`, no hook response, never calls `exit`, never called inside `$(...)`; header lists its documented inputs; sourced in the same checked `if` as the walker lib, row 13). API (row 21):
   - `cis_plan <dir>`: pure over the `CTR_*` facts plus an explicit directory; sets `CIS_MODE` (`exact` or `superset`) and `CIS_WHY`. **Exact replay conditions** (all must hold, else superset): exactly ONE scanned root; every add record `exact=1`; `CTR_STAGE_OPAQUE=0`; no loop or function in the text; and the directory is proven (row 15): (i) the command names no cd / pushd / `-C` / `--git-dir` / `--work-tree` and the payload `.cwd` (read by the glue directly from the payload, not `HOOK_CWD`) is present, absolute and an existing directory; or (ii) every add record and the commit carry the same absolute existing `-C <abs>`; or (iii) `cd <abs>` is the first record (`CTR_STAGE_CD_FIRST`) followed only by `&&`-joined git records. Relative targets go to the superset.
   - `cis_build <root> <dir> <workdir>`: prepare (copy `$(git -C root rev-parse --git-path index)` into `<workdir>/index`, a missing index meaning an empty one; resolve the objects path with `--git-path objects`; both made absolute by hand against the root when relative; a `:` in the objects path is a prepare failure; `mkdir -m 700` for `<workdir>/objs`; needs `cp`), export the three variables, run the plan, and return exactly 0 (built), 10 (built, a trusted `pathspec-missing` occurred) or 20 (failure; any other non-zero maps to 20; `CIS_ERR` holds a sanitised first error line); on failure it removes its workdir. `CIS_ENV=(GIT_INDEX_FILE=... GIT_OBJECT_DIRECTORY=... GIT_ALTERNATE_OBJECT_DIRECTORIES=...)` is exposed so a consumer that is not a shell-function-that-exits can run `env "${CIS_ENV[@]}" git diff --cached`. `cis_export` / `cis_unexport` export and restore prior values (distinguishing unset from empty) and set/clear `CIS_ACTIVE`, so the flag cannot outlive the env window.
   - **Pins** on every sim git call: `-c core.fsmonitor=false -c core.untrackedCache=false -c core.splitIndex=false`, plus `-c filter.<n>.clean= -c filter.<n>.process= -c filter.<n>.smudge= -c filter.<n>.required=false` for each filter enumerated with `git config --get-regexp '^filter\..*\.(clean|process|smudge|required)$'` (suffix stripped with `${k%.*}`; filter names may contain dots); `LC_ALL=C`; the verb is always the literal `add` (aliases cannot hijack it); the replay forwards NOTHING from the command except validated options and paths: `git -C <dir> add <validated opts> -- <paths>` (row 18).
   - **Replay**: failure classes (rows 8, 16): the trusted error is rc 128 AND a first line matching `^fatal: pathspec '.*' did not match any files$` (the `beyond a symbolic link` variant is not it). On that error: rebuild with the superset and scan it; if `CTR_STAGE_PRODUCER=1` the glue DENIES with the existing `create` repair, otherwise the run returns 10 and the glue allows if clean with a `git-commit-secret-scan-sim-failed` row (cause `pathspec-missing`). ANY other failure (timeout, deadline, ENOSPC, other exit 128) abandons the exact replay and rebuilds from a fresh copy with the superset.
   - **Superset**: `git add -A` (no `--ignore-errors`). When any add record had `force=1` and the exact replay was not used, additionally `git add -f -- <the literal path words of those records>`; non-literal words -> DENY "run the force-add as its own call, then commit" (row 12). A failed superset (non-zero, timeout, deadline) DENIES, quoting the sanitised first error line.
   - **Commit step** after the replay, unless `add -A` already ran: `-a` / `-p` -> `git add -u`; paths / `-o` / `-i` -> `git add -u -- <literal paths>`, falling back to `git add -u` for non-literal paths or a failure, then `git add -A` (row 3).
   - **Bound** (row 20): one total sim deadline of 30 s for the whole simulation across roots, including gitleaks, tracked with `$SECONDS`; each call runs under `timeout -k 2 <integer ceiling >= 1>` (never 0), with `perl -e 'alarm N; exec @ARGV'` where neither `timeout` nor `gtimeout` exists; none of the three available, or `remaining <= 0` before a call, means DENY. Expiry always denies, never bypasses. The harness default hook timeout is 600 s (Claude Code hooks documentation, to be re-confirmed in Phase 5), so 30 s is not harness-constrained; the existing hook already allows about 70 s in its gitleaks probe alone.
5. **Hook glue** (`git-commit-secret-scan.sh`) is policy only: when `CTR_COMMIT_STAGES=1`, after `gitleaks_runnable`, apply `CTR_STAGE_REFUSE` (deny), allocate `sim_dir=$(mktemp -d -t commit-sim-XXXXXX) || deny ...` (declare `sim_dir=""` before the trap; opportunistically sweep stale `commit-sim-*` directories owned by the caller older than 60 minutes first), then per root in `toml_roots`: `cis_build`, map the code to allow / deny / bypass row and rule id, call the unchanged-but-for-check-attr `scan_root` inside the export window, `cis_unexport`, clear the root's files. The trap becomes `trap cleanup EXIT; trap 'exit 130' INT; trap 'exit 143' TERM`, with `cleanup` removing the report files, `nodiff_dir`, and `sim_dir` only when it is non-empty, a directory (not a symlink), matches `*/commit-sim-*` and is owned by the caller. Every `cis_*` call and the `mktemp` are explicitly checked (`if ! cis_build ...; then deny ...; fi`; multi-step bodies end each step in `|| return 1`) because a bare failing call under `set -e` exits 1, which the harness treats as non-blocking (fail-open). In sim mode gitleaks resolves to a generated wrapper script `sim_dir/bin/gitleaks` first on PATH (the real `scan_root` calls `env ... gitleaks`, which bypasses shell functions); the wrapper applies the bound and, on expiry, touches `sim_dir/gl-timeout`; the glue DENIES after `scan_root` returns when the marker exists. `deny()` (outside `scan_root`) gains one behaviour when `CIS_ACTIVE=1`: it truncates the reason at the stable anchor `The default action is to scrub` and appends a sim-specific recovery text (for an untracked file: scrub, delete or `.gitignore` it, or stage only intended paths in a separate call; for a tracked file under `-a` or a pathspec commit: scrub it - `.gitignore` does not help), names why the superset was used when it was, sanitises and caps (200 characters, control characters and U+2028/2029 removed) any quoted git error line, and emits under rule id `git-commit-secret-scan-sim-deny` with the row text `mode=exact|superset|pathspec cause=<CIS_WHY>` (enumerated causes only: `pathspec-missing`, `sim-timeout`, `superset-failed`, ...; git's own line never goes into the ledger). A test pins that the anchor still exists in the `scan_root` body; a missing anchor would silently no-op the truncation.
6. **`scan_root`**: byte-identical except ONE behaviour-preserving edit (row 19): the per-path `git check-attr` + `sed` loop becomes a single `git diff --cached --name-only -z --diff-filter=ACMR | git check-attr -z --stdin diff` pass. In sim mode a batch failure DENIES; on the plain path it falls back to the old loop. An old-vs-new equivalence test covers paths with spaces, quotes and newlines and attribute values set, unset, unspecified and valued.
7. **Failure posture** (no `ask`, ADR-165):

   | Situation | Result |
   |---|---|
   | Trusted `pathspec-missing` in a proven directory | DENY `cause=pathspec-missing`, naming the path and git's line (row 25 deleted the producer rule and the bypass row) |
   | Any other replay failure | rebuild with the superset; a failed superset denies |
   | Failed superset, non-literal force-add, temp dir / index copy / `:`-in-path failure, deadline or gitleaks timeout, no bounding tool available, `check-attr` batch failure | DENY, repair "run git add as its own call, then commit" (sanitised first error line where there is one) |
   | Config-transforming staging argument | DENY "stage in its own call" |
   | Sim lib missing or unreadable | DENY every strict commit through the existing `lib` repair (same `if` as the walker lib) |
   | Lexer unavailable on a chained add-then-commit (about 77 percent of commits now reach the lexer) | existing `tooling` / `parse` / `bound` denies; their repair text no longer says "a plain git commit still works" for chained adds and adds "run git add in one call, the commit in the next" |
   | gitleaks missing / unrunnable / probe timeout | unchanged (those exits precede the sim) |

### Alternative Approaches Considered

| Approach | Verdict |
|---|---|
| `git diff HEAD` of the resolved roots | Rejected by the CTO ruling (misses untracked files, over-scans) |
| Run the real `git add` in the hook | Rejected: mutates the real index/store before the user's command and before allow/deny |
| Scan the working tree with `gitleaks dir` | Rejected: scans everything, not what the commit records |
| Lexer for every commit | Rejected: puts perl on the no-staging path (property 2) |
| Always-superset (never replay) | Rejected by the ruling: an unrelated untracked file would deny `git add clean.txt && git commit` |
| Cap on the number of new paths instead of batching `check-attr` | Rejected (row 19): would deny legitimate large commits |
| Content-size proxy (`du` of the sim objects) | Rejected (row 20): the wrapper bound is the cleaner control |

## Technical Considerations

- **Portability**: bash 3.2 (no `mapfile`, no `declare -n`, no associative arrays; empty arrays read as `${a[@]+"${a[@]}"}`; truncation guarded like the existing `[ "$_CTR_BAD_MARK" -eq 0 ]`); one perl fork / waitpid / kill bound for every host (CTO row 30: `timeout` is absent on a stock macOS and a perl `alarm` + `exec` does not stop gitleaks); `cp -p` is needed (add it to the stub PATH); no `sha256sum`, `stat -c`, `setsid` or `date +%s%N` in the suite arms (use `cmp`, `ls -ld`/`find -perm`, bash `kill`, and label the Linux-only timing command as such).
- **Telemetry**: ledger ids `git-commit-secret-scan` (a finding, `cause=finding`) and `git-commit-secret-scan-sim-deny` (a simulation failure); `sim-failed` was retired, emitted through the existing `emit`; no registry lists the sibling ids. Treat both ids as permanent once emitted. Layer: the local incident ledger `.claude/.rule-incidents.jsonl` (a dev-machine hook, not a server surface).
- **Secret residue**: the quarantined object directory and the `-diff` re-scan directory hold blobs of working-tree files that may be secrets. `mktemp -d` is 0700, per-root dirs use `mkdir -m 700`, the hook runs under `umask 077`, the EXIT trap removes both, INT/TERM exit through the trap, and a marker-bearing `commit-sim-*` / `gitleaks-nodiff-*` stale-directory sweep (older than 60 minutes) bounds the SIGKILL case.
- **Residuals named in the hook header** (rows 5, 11, 18; one follow-up issue lists them all): a script that runs `git add` inside; content created or changed earlier in the same command (a producer, `sed -i` / `prettier --write` before `commit -a` or `add -u`) is invisible - producer detection was dropped (rows 16, 25) and the scan sees pre-execution state; the pinned sim scans raw bytes, so a clean filter / Git LFS may record bytes the sim never saw; content a verb brings from outside the working tree (`apply --index`, `cherry-pick -n`, `stash pop`, `merge`, `checkout <ref> --`) is NOT covered (the superset scans the working tree only - Property 1 is scoped accordingly); other tools that stage (an IDE, a user-config git alias; an INLINE alias is a deny, rows 40 and 49); a configured `core.fsmonitor` daemon is not started by the sim (pinned off); the pre-existing gitleaks textconv / external-diff execution is unchanged.
- **Superset trade-offs**: `add -A` scans unrelated untracked, non-ignored files, so an unrelated finding (or a 5 MB untracked JSON dump, about 7 s) in the cwd repo can deny or slow a commit aimed elsewhere; a stray unreadable file or an unborn nested repo makes `add -A` fail and the real `git add -A` would fail the same way. The exact replay and the `-u`-based paths avoid this. Two scanned roots (a main-checkout session that `cd`s into a worktree) force the superset; Phase 5 tabulates how often.
- **Pathspec commit and other staged content**: `commit -- p` records only `p`, but the sim index keeps other staged changes, so a staged leak elsewhere still denies it (the existing conservative behaviour; pinned by a row).
- **Reuse by #10793**: the brand-hex gate's worktree-versus-HEAD branch for `-a` is subsumed by the superset `add -u` plus `git diff --cached` under `CIS_ENV`; when #10793 lands, "is this a commit" should move into the lib so the two hooks cannot diverge again.
- **Template drift**: the emitted verification-scaffold `secret-scan` template self-contains its parse, already lacks the #10609 target resolution, and will lack the would-be index. The audit row records the known divergences, the template header and `verification-readme.template` each gain one sentence ("a chained `git add ... && git commit` in one command is not covered; stage in a separate call"), and the follow-up issue also tracks porting the would-be index to the template.

## Observability

Included because deepen-plan Phase 4.7 gates any plan whose files are not pure docs; plan Phase 2.9's server-side trigger set does not name `.claude/hooks/`. This is a developer-machine hook, so the server observability layers do not apply; the surface is the local rule-incident ledger written by `.claude/hooks/lib/incidents.sh`. The Phase 4.5 network-outage trigger word `timeout` here means the simulation deadline, not a network symptom (git and gitleaks run locally).

```yaml
liveness_signal:
  what: "one ledger row per deny or bypass the hook emits (rule ids git-commit-secret-scan and git-commit-secret-scan-sim-deny); a hook that never fires leaves no row, so liveness is the suite's real-gitleaks canary arms plus the CI secret-scan workflow"
  cadence: "per git commit Bash call"
  alert_target: "the local ledger .claude/.rule-incidents.jsonl read by the weekly rule-utility aggregator; CI secret-scan on push is the paging backstop"
  configured_in: ".claude/hooks/git-commit-secret-scan.sh (emit calls) and .claude/hooks/lib/incidents.sh"

error_reporting:
  destination: "the local ledger via emit_incident; the deny JSON reason on stdout for the agent; stderr WARN lines for bypasses"
  fail_loud: "permissionDecision deny with a repair message for every unscanned-commit case (a missing pathspec included, row 25)"

failure_modes:
  - mode: "simulation cannot be built, is not boundable, or the superset fails (temp dir, index copy, add -A, deadline, gitleaks timeout)"
    detection: "deny returned to the agent with a sanitised git error line; a git-commit-secret-scan-sim-deny ledger row with mode and cause (local incident ledger, not a server layer)"
    alert_route: "the agent sees the deny immediately; the aggregator reads the ledger"
  - mode: "exact replay hits a path that does not exist (superseded: this is a deny since row 25)"
    detection: "git-commit-secret-scan-sim-deny row with cause pathspec-missing"
    alert_route: "the agent sees the deny immediately; the local ledger"
  - mode: "a staging form the walker does not recognise is scanned as before (silent gap)"
    detection: "named residuals in the hook header; the lexer-failure and form census run in Phase 5; CI secret-scan on push"
    alert_route: "CI secret-scan workflow failure on the pushed branch"

logs:
  where: ".claude/.rule-incidents.jsonl (flock-guarded, rotated by lib/log-rotation.sh)"
  retention: "the rotation policy of lib/log-rotation.sh"

discoverability_test:
  command: "grep -m1 -o git-commit-secret-scan-sim-deny .claude/hooks/git-commit-secret-scan.sh"
  expected_output: "git-commit-secret-scan-sim-deny"
```

## Architecture Decision (ADR/C4)

No ADR or C4 change. The test applied: would an engineer reading the existing ADRs and C4 be misled after this ships? No. This adds an internal mechanism to one hook inside the existing "PreToolUse hook scans before the command" posture (ADR-156/157/165 unchanged); no ownership/tenancy boundary, substrate, trust boundary or ADR reversal moves. C4 files read for the check: `knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}` model the web platform, not the repo's developer hooks; actors/systems/relationships checked: no human actor, vendor system, container or access relationship is added or changed by a local hook, and `plugins/soleur/test/c4-count-parity.test.sh` is unaffected (no workflow or monitor count moves). The design record is the decision-challenges file plus the hook header.

## User-Brand Impact

- **If this lands broken, the user experiences:** either a commit denied with a repair message they can follow (run `git add` as its own call, then commit), or, in the worst bug, a secret in a freshly added file committed to local history and caught only by CI after the push.
- **If this leaks, the user's workflow data is exposed via:** a leftover temp directory holding blobs of working-tree files (a secret-bearing file's content) after a hard kill; mitigated by mode 0700, a trap that removes it on EXIT / INT / TERM, and a stale-directory sweep.
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** the gap is narrow and CI-backstopped (the post-push `secret-scan` workflow remains the load-bearing gate), and the verification-scaffold template that ships to user repos self-contains its own parse and is not changed in behaviour here (its known divergence is disclosed and tracked), so a defect in this hook reaches Soleur's own repo, not a user's.

## Guard Contract

### Guard 1 — would-be index coverage

**Property.** Every file content in the working tree that the Bash command's own staging verbs or commit flags would record in the commit is present in the index that gitleaks scans before the command runs.

**Assembly.** Not a list of verbs; the chokepoints every staging form must flow through, in order: (1) the pre-filter `ctr_wants_lex` (a form it misses never reaches the walker; the must-match table pins each form), (2) the walker records in `_ctr_git_walk` for `add|stage`, the stage-unknown verbs and the commit-flag parser (a verb or option it does not classify is invisible; an unknown `--long` option forces the superset), (3) the classification into `CTR_COMMIT_STAGES` / `CTR_STAGE_OPAQUE` / `CTR_STAGE_REFUSE`, (4) the single exactness predicate `cis_plan` (one root, proven directory, every record exact, no loop), (5) `cis_build` and the commit step (every git call through one wrapper that carries the pins and the bound), (6) the export window around `scan_root` (every read inside `scan_root`: `gitleaks git`, `git diff --cached --name-only`, `git check-attr`, `git show :path` for the `-diff` re-scan; one export covers all four injection sites), (7) the failure branches (only the benign missing pathspec warns; everything else rebuilds with the superset or denies).

**Mutation matrix** (every row maps to a named Phase 0 test):

| # | Mutation | Expected | Named test |
|---|---|---|---|
| 1 | Delete the staging-verb clause from `ctr_wants_lex` | RED: the flipped pre-filter row fails and the chained leak case is allowed | G1 pre-filter table; group 1 |
| 2 | Force `CTR_COMMIT_STAGES=0` in the walker (dispatch of the sim) | RED: groups 1, 2 and 4 allow; the shim row expecting exactly one sim `add` sees none | groups 1, 2, 4; shim-dispatch row |
| 3 | After a compliant first record, add a second: `git add clean.txt && git add leak.json && git commit`; mutate the replay to stop after the first record | RED: the second record's leak is not scanned | group 3b |
| 4 | REORDER: move `cis_export` to after the `scan_root` call (or `cis_unexport` before it) | RED: a recording gitleaks stub capturing `$GIT_INDEX_FILE` inside the call sees it unset, and the real-gitleaks canary allows | group 8 canary; env-window row |
| 5 | Treat `-p` as a replayable option | RED: the PATH shim sees `add -p` executed instead of the superset `add -A` | group 7 |
| 6 | Make a failed superset (shim fails `add -A`) allow | RED: the deny-on-failed-superset case allows | group 11 |
| 7 | Drop the one-root rule (replay exactly with two roots: root A clean, root B holds the untracked leak) | RED: the replay misses root B's leak | multi-root row |
| 8 | Skip the `commit -a` step (`add -u`) | RED: `commit -am` with a tracked modified leak is allowed | group 4 |
| 9 | Treat any replay failure (not just the anchored pathspec error) as warn-and-allow | RED: a shim making the replay `add` exit 128 with another message ends in allow instead of the superset deny | group 11 |
| 10 | Trust the directory proof loosely: accept `false && cd /abs; git add leak.json && git commit` as proven | RED: the four wrong-directory commands (F1 set) allow | group 10b |
| 11 | Allow `pathspec-missing` when the text has a redirect producer | RED: `printf x > leak.json && git add leak.json && git commit` allows | group 11 |
| 12 | Forward `-c core.fsmonitor=...` / an env prefix into the replay | RED: the canary config creates its marker file at hook time | pin row |
| 13 | Drop the stage-unknown verb list entry for `checkout` (over-scan witness only: the leak is an untracked file already in the working tree; the test proves the superset ran, not coverage of the checked-out blobs) | RED: `git checkout <ref> -- . && git commit` allows | stage-unknown row |

**Harness rows:**

| # | Edit to the SUITE | Expected |
|---|---|---|
| H1 | Make the `git` PATH shim stop logging (empty log) or key on `$1` only | RED: the "log lines > 0 and one sim add (found after `-C <dir>` / `-c k=v`) with a non-real index" assertions fail instead of passing vacuously |
| H3 | Replace a deny arm's fixture with one that stages the leak (the old `_mk_leaky_repo` shape) | RED: the gap-witness control (plain `git commit -m x` on the same shape must allow) fails |

The must-PASS controls that are NOT the canonical shape are group 3 (`git add clean.txt && git commit` with an unrelated untracked leak, its quoted-name and `rtk` variants) and the plain-commit allow twin on every deny fixture: they differ from the canonical `add -A` leak case in ways the contract permits and they fail if the hook simply denies everything. Every allow arm has a deny twin on the same fixture differing only in the command.

**Anchor.** No stored value is compared to a protected artifact. The suite's `MIN_ASSERTIONS` count floor is the only stored number; it equals the measured count with all arms run (nothing skipped), is raised in the same edit that adds rows, and is itself pinned by the existing floor-contract truth table.

### Guard 2 — the simulation never mutates the real repository

**Property.** Running the simulation leaves the real index bytes, the real object store, the real git directory file listing and the working tree unchanged, and leaves no temp directory behind.

**Assembly.** Every git invocation in `commit-index-sim.sh` passes through one wrapper (the pins, `LC_ALL=C`, the bound); the only verb the replay may run is the literal `add`; the three variables are exported before any write and restored after; the temp directory is allocated by the hook and removed by the `cleanup` EXIT trap on the allow path, the deny path (`deny` exits inside `scan_root`) and signals (INT/TERM exit through the trap).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Run the copy step against the real index (skip `cp`, point `GIT_INDEX_FILE` at the real file) | RED: `cmp` of the real index against its saved copy fails |
| 2 | Omit `GIT_OBJECT_DIRECTORY` | RED: the real store's loose-object count grows |
| 3 | Remove the sim directory from `cleanup` | RED: the private `TMPDIR` is non-empty after an allow, after a deny, and after a TERM |
| 4 | Revert the INT/TERM handlers to the old `trap '...' EXIT INT TERM` | RED: after TERM the hook continues and prints a decision (the signal arm asserts rc 143, empty stdout and an empty `TMPDIR`) |
| 5 | Drop `-c core.splitIndex=false` | RED: in a `core.splitIndex=true` repo the real git directory listing gains a `sharedindex.*` file |

**Harness rows:**

| # | Edit to the SUITE | Expected |
|---|---|---|
| H2 | Take the snapshot AFTER the hook instead of before | RED: the structural helper `_assert_repo_untouched <repo> -- <run>` (snapshot taken inside, then the run) is self-tested around a command that mutates the index and must fail |

**Anchor.** None stored; the invariants are measured against a snapshot taken by the test before the hook runs (index via `cmp` against a saved copy, never `sha256sum`; working tree via `git status --porcelain -uall` plus a file hash; real git directory via a sorted file listing).

## Files to Edit

- `.claude/hooks/lib/commit-target-roots.sh` - walker: staging records, commit-flag parser, new `CTR_*` outputs, `ctr_stage_dump`, widened and anchored `ctr_wants_lex`.
- `.claude/hooks/git-commit-secret-scan.sh` - header comment (posture, residuals), split trap and `cleanup`, `sim_dir` allocation and stale sweep, sim-lib source in the existing checked `if`, the policy glue, the PATH wrapper for gitleaks, the `deny()` mode behaviour, the one batched-`check-attr` edit inside `scan_root`, updated `tooling`/`parse`/`bound` repair text.
- `.claude/hooks/git-commit-secret-scan.test.sh` - the thirteen ruled test groups plus the extra rows, new fixture modes, the recording gitleaks stub, the `git` PATH-shim helper, `_rows_since_mark`, `_assert_repo_untouched`, `cp` and `sleep` in `_mk_stub_path`, the flipped pre-filter row, the consumer stub test, `MIN_ASSERTIONS`.
- `knowledge-base/engineering/operations/secret-scanning.md` - one-line note after the Architecture table that the PreToolUse hook scans the would-be index for same-command staging.
- `.claude/hooks/README.md` - rewrite the sentence that says the hook scans the index "BEFORE the command runs (#10696)" in the accepted-residuals paragraph, move the new named residuals into that list, and add a short pointer paragraph.
- `plugins/soleur/skills/verification-scaffold/references/guardrail-audit.md` - add the `lib/commit-index-sim.sh` row (`soleur-coupled`: it depends on the walker's `CTR_*` facts, which depend on `shell-argv.pl`), a "Known divergences from source" note on the `git-commit-secret-scan.sh` row (#10609 and #10696), the new walker outputs on the `commit-target-roots.sh` row, and the census count (56 files) updated.
- `plugins/soleur/skills/verification-scaffold/references/guards/secret-scan-hook.sh.template` and `plugins/soleur/skills/verification-scaffold/references/verification-readme.template` - one disclosure sentence each (a chained `git add ... && git commit` in one command is not covered; stage in a separate call); prose only, no behaviour change; the manifest hygiene rules (no `knowledge-base/`, no `plugins/soleur`, no URLs outside comments) still apply.
- `scripts/lib/test-affected-paths.sh` - review round (finding F): declare the `AFFECTED_CLAUDE_HOOKS_GIT_COMMIT_SECRET_SCAN_TEST_SH_PATHS` edge so the orphan-suite lint passes and a change to either library selects the suite.
- `knowledge-base/engineering/architecture/decisions/ADR-157-a-hook-that-cannot-parse-its-input-asks.md` - review round (row 36): a three-line pointer addendum.
- `scripts/suite-durations.tsv` - NOT hand-edited in the review round (`regenerate-shard-manifest.py --incremental --write` adds unrelated rows); refresh the suite's weight (`regenerate-shard-manifest.py --incremental --write`) once the final arm set is measured.

## Files to Create

- `.claude/hooks/lib/commit-index-sim.sh` - the shared would-be-index library.
- `knowledge-base/engineering/architecture/decisions/ADR-300-scan-the-would-be-index-of-a-chained-git-commit.md` - review round (row 36): the single index of the simulation contract, deny causes, the no-bypass deadline and the named residuals.
- `knowledge-base/project/specs/feat-one-shot-10696-secret-scan-staging-gap/decision-challenges.md` - created at plan time (rows 1 to 21).
- `knowledge-base/project/specs/feat-one-shot-10696-secret-scan-staging-gap/tasks.md` - derived from this plan.

Do NOT edit `plugins/soleur/skills/work/SKILL.md` (explicit rule), `.claude/settings.json`, `.claude/hooks/lib/hook-input.sh` (shared by about 20 hooks; the glue reads the payload `cwd` itself), or `brand-hex-commit-gate.sh` (its adoption of the shared library is #10793).

## Open Code-Review Overlap

None. All planned paths were queried against open `code-review` issues; no body names any of them.

## Implementation Phases

### Phase 0 - RED (tests first, `cq-write-failing-tests-before`)

Write the new arms in `git-commit-secret-scan.test.sh` and confirm each is RED against the unmodified hook for the right reason. Reuse the suite's helpers (`_mk_pem` with an explicit non-sequential body, `_mk_repo_with_toml`, `_run`, `_decision`, `_reason`, `_mk_stub_path`, the #10609 bare-root and linked-worktree fixtures, `_needs_gl`, `_report`). Secret shapes are built by concatenation at run time; never read or print real credentials (`cq-test-fixtures-synthesized-only`).

Suite-design rules (from the test-design review):

- **Fixtures**: add modes `untracked` and `tracked-modified` to `_mk_leaky_repo` and `_mk_bare_root_with_worktree` so the leak is NOT in the index; a fixture control per mode runs `gitleaks detect --no-git --source <leak dir>` and expects rc 1; every deny group carries a gap-witness control (plain `git commit -m x` on the same shape allows); every allow arm has a deny twin differing only in the command.
- **Stub tiers**: structural arms (groups 3, 5, 7, 9's no-sim rows, 11, 12, the walker/flag tables, multi-root, directory-proof, force-add, producer, pin rows) run with a recording gitleaks stub (about 50 ms per run) that also copies `$GIT_INDEX_FILE` and logs `git ls-files -s` of it; real gitleaks is kept for a short canary set (groups 1, 2, 4, 6, 8 and one linked-worktree case), each using `_needs_gl "<label>" || return 0`. Budget: added suite wall time at most about 60 s locally; record before and after in the PR body.
- **PATH `git` shim**: resolves the real git by absolute path before PATH is replaced, `exec`s it, logs one line per call with `printf %q` (never to stdout/stderr), mutates nothing; failure modes are selected by env vars read at call time (`SHIM_FAIL=addA`, `replay128`, ...) keyed on "sim index set and different from the real index path", so fixture and gitleaks-internal git calls pass through; finds the verb after `-C <dir>` / `-c k=v`; logs `LC_ALL`, `GIT_INDEX_FILE`, `GIT_OBJECT_DIRECTORY`, `GIT_ALTERNATE_OBJECT_DIRECTORIES` per call. Liveness controls: log line count > 0 on every run (the hook always runs `git rev-parse`).
- **Ledger helper**: `_rows_since_mark <rule_id>` returns count and text (the existing `_last_prefix` cannot count rows); `_run_cmd` with a stub-PATH variant carrying `perl`, `cp`, `sleep`; new arms go after `_t_lexer_contract` and before `_t_ci_contract`, outside the T20 priming.
- **Isolation**: every hook run gets its own `TMPDIR="$SUITE_TMP/tmp.N"`; leftover checks assert the private `TMPDIR` is empty (never a glob on shared `/tmp`); never `chmod 000` (root ignores it) - unreadable-file cases use the shim.
- **TERM arm contract**: `( cd "$repo"; exec env ... bash "$HOOK" <payload >out 2>err ) & hp=$!`; the stub gitleaks (for the `git` subcommand only) writes a `started` marker and loops `while [ ! -e "$RELEASE" ] && [ $n -lt 100 ]; do sleep 0.1; ...; done` (the bounded loop self-terminates an orphan, so no fixed sleep is unexplained), then writes a findings report and exits 1; the test polls for `started` with a bounded loop, runs `kill -TERM $hp`, creates `$RELEASE`, `wait`s, and asserts rc 143, empty stdout (allow and deny both print JSON), empty private `TMPDIR`, and (positive control) that the stub saw the sim directory while it ran. No `setsid`.
- **Differential oracle** for "the sim stages a superset of what the command stages": for each row of the command table, apply the literal staging words with real git to a clone of the fixture, take `git ls-files -s`, and assert every (path, blob) entry appears in the sim index captured by the recording stub; no real gitleaks needed.
- **Fixed-count tables**: the benign-long-option table has a fixed number of entries and fails loudly if the installed git rejects one (no assertion count that varies with the git version); `MIN_ASSERTIONS` equals the measured count with nothing skipped.
- **`scan_root` equivalence**: an old-vs-new test of the batched `check-attr` pass (paths with spaces, quotes, newlines; attribute set / unset / unspecified / valued). The byte-identity check of the rest of `scan_root` is a Phase 5 command, not a permanent suite arm (it would fail on the next legitimate edit and on shallow CI checkouts).

Test groups (pyramid layer in brackets; this is a unit-layer `*.test.sh` with declared subprocess use):

1. [integration] `git add -A && git commit -m x` with an untracked leak -> deny, reason names `leak.json`, carries the sim recovery text and not the `restore --staged` clause (the `deny()` truncation replaced it); an exact-replay finding carries rule id `git-commit-secret-scan-sim-deny` too; a non-sim deny keeps `git-commit-secret-scan`.
2. [integration] `git add leak.json && git commit -m x` -> deny.
3. [integration, must-PASS control] `git add clean.txt && git commit -m x` with an UNRELATED untracked leak -> allow, shim log shows an exact replay (`add clean.txt`), not `add -A`; same for the quoted `git add "my file.md"` and `rtk git add clean.txt && rtk git commit`. 3b: `git add clean.txt && git add leak.json && git commit`, and an add after the last commit (`git commit -m x; git add leak.json`), are still replayed.
4. [integration] `git commit -am x`, `-a -m x`, `-sam x` with a tracked modified leak -> deny.
5. [integration] `git commit -a -m x` with an untracked leak -> allow.
6. [integration] `git commit -m x -- tracked.json` (modified, leak) -> deny; the same with the leak in a different tracked file -> allow; `commit tracked.json -m x` (bare first word) -> deny; `-o` and `-i` forms.
7. [integration] `git add $F`, `git add -p`, `git add *.json`, brace and tilde forms, `ls | xargs git add`, `find . -name '*.json' -exec git add {} \;`, `mise exec -- git add clean.txt`, `git add f -e` / `-p` / `--chmod=+x` / `--pathspec-from-file=-` (with `EDITOR`/`GIT_EDITOR` set to a marker script; the marker must stay absent) -> superset (shim shows `add -A`, never `-p`); an untracked leak -> deny.
8. [integration] `.git/info/attributes` with `leak.json -diff` plus `git add leak.json && git commit` -> deny with the `-diff` message (real-gitleaks canary; the shim env log shows the sim variables on the `diff --cached`, `check-attr` and `show :` calls).
9. [integration] invariants: real index `cmp`, real loose-object count, real git directory listing and working tree unchanged (via `_assert_repo_untouched`), a `core.splitIndex=true` fixture; private `TMPDIR` empty after allow, deny and TERM; sim dir mode 0700; the shim shows NO sim call for plain `git commit -m x` and `git commit -n -m x` (log lines > 0, zero sim adds) and the lexer-skipped path still allows with the new `CTR_*` variables unset.
10. [integration] `cd <wt> && git add -A && git commit` from a bare-root cwd (the #10609 incident shape) -> deny. 10b (directory proof): `false && cd /abs; git add leak.json && git commit`, `(cd /abs); git add leak.json && git commit`, `pushd /abs && popd && git add ...`, `cd /abs || true; git add ...`, each with a leak at the repo root and a clean `docs/leak.json` present, then absent -> all deny; `git -C <abs wt> add clean.txt && git -C <abs wt> commit` with an unrelated leak -> allow via proof (ii); a payload with no `cwd` and `CLAUDE_PROJECT_DIR` set -> superset; a relative single target -> superset.
11. [integration] failures: `git add no-such-file && git commit` (no producer) -> superset scanned, bypass row (cause `pathspec-missing`, exactly one, asserted with `_rows_since_mark`), allow; `printf x > leak.json && git add leak.json && git commit` and `terraform show -json > f && git add f && git commit` -> deny with the `create` repair; a shim making the replay `add` exit 128 with another message -> superset; a shim failing `add -A` -> deny with "run git add as its own call, then commit" and a sanitised error line; the shim `mktemp` or `cp` failing -> deny; an objects path containing `:` -> deny; a sleeping gitleaks stub past the (test-shortened, clamp-only) deadline -> deny; remaining <= 0 -> deny; no `timeout`/`gtimeout` -> perl path; none of the three -> deny; a sim lib that is missing (deleted in a copied hooks tree via the hook override, never `chmod`) -> deny for a chained AND a plain strict commit; perl absent -> `tooling` deny with the corrected repair text; a filename with a newline and U+2028 and a 300-character name never reach the deny text unsanitised.
12. [integration] linked worktree: index at `.git/worktrees/<name>/index`, tracked blobs only in the common object store; assert the index and objects paths are absolute and resolve; a symlinked directory, a symlinked file and a symlinked `.gitleaks.toml` each behave as designed.
13. [measurement, run once, not a suite arm] latency and lexer-failure ceiling (Phase 5).

Extra rows:

- Pre-filter must-match / must-skip table with the expected result stated per form (`git add -A && git commit -m x` flips to must-match; `git commit -m x`, `git commit -n -m x`, `git status && git commit -m x`, `git log --oneline && git commit -m x`, `git log --grep=commit`, `git commit -m "fix the commit scan"` and `git addr` are must-skip; must-match for each form in Design 2 including `--inc` and `--on`; a heredoc message containing `git add` over-matches only).
- Walker output table through `ctr_stage_dump` (not the raw encoding): add / stage / rm / mv / stage-unknown / refuse / producer / loop / pass-through launcher (`rtk` exact) / unknown launcher (`mise exec` non-exact) / `xargs` / `x`-flagged command word; commit-flag table `-mall` (message, not `-a`), `-am"x"`, `-sam x`, `-Sa`, `-Sabc`, `-uall`, `-m -a`, `-m --`, `-m -p`, `--no-all`, every benign long option, an unknown/abbreviated long option -> opaque; control bytes in a word -> non-exact.
- `git rm --cached f && git commit` still reaches the existing scan with no sim; `git rm a.txt && git mv b.txt c.txt && git commit` leaves both working-tree files in place.
- Two scanned roots (A clean, B leak), a mixed-directory command (`git -C sub add f && git add g && git commit`): superset. `git add -f ignored.pem && git commit` (exact replay finds it); `git add -f $F && git commit` -> superset plus the literal-word force-add or the deny.
- `-c core.fsmonitor='touch MARK' add x && git commit` -> refused, MARK never created; a configured `filter.x.clean` marker never runs at hook time (pin row).
- A hook run with `core.fsmonitor=true` configured does not start a daemon.
- Consumer stub test (about 15 lines): sources `commit-index-sim.sh`, runs `cis_build`, then `env "${CIS_ENV[@]}" git diff --cached --name-only`, with no secret-scan code - proves property 5.
- Anchor test: the string `The default action is to scrub` exists in the `scan_root` body and the sim deny text contains no `restore --staged`; a separate-call commit (add in one call, commit in the next) still shows the `restore --staged` text.
- Stale sweep: a `commit-sim-*` directory older than 60 minutes is removed at sim start, a fresh one is kept, a symlink is never followed.
- Residual pins: `sed -i` before `commit -a` (allowed, header residual), a positional after `-m "..."` (not covered), `git checkout <ref> -- . && git commit` (superset, over-scan witness only).

### Phase 1 - walker (`commit-target-roots.sh`)

Implement Design 1. `_ctr_reset_stage` at top level and in `ctr_collect`; keep the existing refusal logic and `ctr_resolve_roots` untouched. Widen `ctr_wants_lex` per Design 2.

### Phase 2 - `commit-index-sim.sh`

Implement Design 4. Header states the contract, the documented inputs, the allowlist, the failure classes, the bash 3.2 rules, the "no mktemp, no trap, no exit, no `$(...)`" rules, and that the deadline is only checked between git calls when no bounding tool exists (and then the hook denies).

### Phase 3 - hook glue and `scan_root` edit

Implement Design 5 to 7. Update the header comment: new behaviour, posture table, residuals, the meaning of the bypass row, and that gitleaks resolves to a bounded wrapper in sim mode.

### Phase 4 - docs

`secret-scanning.md` note; `.claude/hooks/README.md` rewrite and pointer; `guardrail-audit.md` rows and count; template and readme disclosure sentences. Re-run the verification-scaffold manifest test.

### Phase 5 - verification and measurements

Run the suite (raise `MIN_ASSERTIONS` to the measured total in the same edit), `shellcheck` on the four shell files (hook, walker, sim lib, test), `python3 scripts/lint-trap-tempfile-ownership.py` on the changed files, `bash plugins/soleur/skills/verification-scaffold/test/manifest.test.sh`, `bash plugins/soleur/test/c4-count-parity.test.sh` (expected unchanged), markdownlint on the plan and tasks. Run the canary arms against the pinned gitleaks 8.24.2 tarball (the sha-verified URL used by the CI step in `.github/workflows/ci.yml`, extracted into a scratch directory) before pushing. Verify the `scan_root` diff: extract `awk '/^scan_root\(\) \{/,/^}/'` from `git show origin/main:.claude/hooks/git-commit-secret-scan.sh` and from the working file; the diff must show only the batched-`check-attr` hunk. Re-confirm the Claude Code default hook timeout (600 s per the documentation) and the `onFailure` setting from the documentation before relying on either. Refresh the suite weight with `regenerate-shard-manifest.py --incremental --write`; record before/after suite wall time.

Measurements (results into the PR body):

- **Latency (AC13)**: in a scratch worktree of this repo (created under the scratchpad, removed afterwards) with 5 modified tracked files and 3 untracked files, run at least 30 INTERLEAVED pairs of (a) today's hook on `git commit -m x` with the files already staged and (b) the new hook on `git add -A && git commit -m x`, timing each with `date +%s%N` (Linux-only; label it). Gate on `p95(b) - p95(a) <= 1.5 s` (p95 = the 29th of 30 sorted samples) and report the paired p50 difference, `uptime` load and the filesystem; add a second baseline, (c) the same chained command on an unstaged tree under today's hook (what users feel today). Non-gating but reported caps: 5,000 untracked files (about 3.4 s measured, cap 5 s) and a 5 MB high-entropy untracked file (about 7 s, expected). If the gate fails the decision flips to KEEP-OPEN: do not ship, record a row in `decision-challenges.md` and report.
- **Lexer-failure ceiling (AC14)**: extract only the command text of the sampled local `git commit` Bash lines from session transcripts with a read-only `jq` script (counts only, no content printed), run each through the new pre-filter and `ctr_collect`, and report how many land in `lex_state=unavailable` or a `CTR_BAD` deny that did not before (ceiling: under 0.5 percent) and the incremental lexer rate (measured 5 percent on 400 commit messages with the anchored clause). Also tabulate how often `scan_roots` has more than one entry across the three topologies (bare-root-anchored, worktree-anchored, main-checkout-anchored with `cd` into a worktree), since two roots forces the superset.

### Phase 6 - ship items

PR body: `Closes #10696`; a separate line `Ref #10331` (non-closing, the epic stays closed); the latency, ceiling and suite-wall-time numbers; one follow-up issue listing the named residuals (script-wrapped staging, content created or changed earlier in the same command, positional path after `-m`, content brought from outside the working tree, filters/LFS, porting the would-be index to the emitted template), milestone from `knowledge-base/product/roadmap.md`; the `## Changelog` section; the ending line `🤖 Generated with [Claude Code](https://claude.com/claude-code)`. Commit messages end with `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`. No `git stash` anywhere.

## Domain Review

**Domains relevant:** Engineering (CTO)

### Engineering

**Status:** reviewed
**Assessment:** The CTO ruled four times on 2026-10-23: the ship decision and mechanism, seven residual forks, seven forks from plan review, and seven forks from deepening (rows 1 to 21 of the decision file). No Product/UX surface (no file under a UI path), no legal or regulated-data surface (no schema, auth flow, API route or `.sql`; no new processing of personal data; the only data touched is the developer's own working tree, written to a mode-0700 temp directory and removed), no marketing, finance, sales or support implication. Infrastructure gate: no server, secret, vendor or DNS change. Encryption posture gate: no persistent store and no network connection (an ephemeral local temp directory only).

## Plan Review Revisions

Panel: code-simplicity, strict-correctness (Kieran lens on shell), spec-flow; then, at deepen time, security-sentinel, performance-oracle, test-design-reviewer and architecture-strategist. The Rails-specific DHH reviewer and the named CEO/design panel were not run (a bash hook with no UI or market surface; the CTO had already ruled). Mechanical findings applied across both passes include: unset `CTR_*` aborting the lexer-skipped path; every `cis_*` call and `mktemp` explicitly checked; the INT/TERM trap not ending the script; `--ignore-errors` dropped; the `q` flag misread; absolute objects path and `:` rejection; `cp` and `sleep` in the stub PATH; hard p95 definition and interleaved method; `rm`/`mv` out of the walker; `CTR_DIRS` and the `ctr_resolve_roots` edit dropped; lazy source dropped; add-count snapshot dropped; the contradictory `restore --staged` advice replaced by anchor truncation; a distinct deny rule id carrying mode and cause; US-delimited records replaced by metadata plus flat words; launcher exactness as an allowlist defaulting to non-exact; control-byte and after-pathspec option validation; anchored error classification; sanitised error text; cleanup guards and the stale sweep; the fixture, shim, TERM-arm, snapshot and ledger-helper specifications; the structural-versus-canary stub tiers; the differential oracle; the byte-identity check moved to Phase 5; mutation matrices re-mapped to named tests; documentation (README sentence rewrite, audit census, template disclosure). Taste and technical forks went to the CTO (decision rows 8 to 21).

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Implement and ship issue #10696 (hooks: git-commit-secret-scan scans the index before the same command's git add / commit -a runs)." [brief] | Phases 0-6; Files to Edit / Create | mapped |
| 2 | "Closes #10696 in the PR body." [brief] | Phase 6, AC15 | mapped |
| 3 | "add a non-closing reference line to the closed code-quality epic (number 10331) in the PR body, written as "Ref #" followed by 10331, no closing keyword. Do not reopen that epic." [brief] | Phase 6, AC15 | mapped |
| 4 | "Extend `_ctr_git_walk` in `.claude/hooks/lib/commit-target-roots.sh` to record per commit record: flags/pathspec ... Export `CTR_COMMIT_STAGES` ... and `CTR_ADD_ARGV`." [brief design 1] | Phase 1, Design 1 | mapped |
| 5 | "Simulation runs only when CTR_COMMIT_STAGES=1; plain `git commit -m x` pays nothing." [brief design 2] | Design 2-3, Phase 3, AC8 | mapped |
| 6 | "New `.claude/hooks/lib/commit-index-sim.sh` (shared; a later brand-hex-gate follow-up reuses it)." [brief design 3] | Phase 2, Design 4, Files to Create, consumer stub test | mapped |
| 7 | "Call existing `scan_root` unchanged with GIT_INDEX_FILE exported around it" [brief design 4] | Design 5-6, Phase 3, AC9 (one CTO-ruled behaviour-preserving edit, row 19) | mapped |
| 8 | "Failure: failed exact replay -> scan what was built + emit a `git-commit-secret-scan-sim-failed` bypass row; failed superset or temp-dir failure -> DENY ... No `ask`" [brief design 5] | Design 7, AC11 | mapped |
| 9 | "Files: `.claude/hooks/lib/commit-target-roots.sh`, new `.claude/hooks/lib/commit-index-sim.sh`, `.claude/hooks/git-commit-secret-scan.sh`, `.claude/hooks/git-commit-secret-scan.test.sh`, the header comment in git-commit-secret-scan.sh, and a one-line note in `knowledge-base/engineering/operations/secret-scanning.md`." [brief] | Files to Edit / Create | mapped |
| 10 | "Tests (TDD first; reuse the suite's synthesized-fixture helpers ...) (1) ... (13) latency" [brief] | Phase 0 groups 1-13, Phase 5, AC1-AC13 | mapped |
| 11 | "Also record the decision-challenge entry in the feature's decision-challenges.md ..." [brief] | `decision-challenges.md` row 1 (created at plan time) | mapped |
| 12 | "Never edit plugins/soleur/skills/work/SKILL.md. No git stash. Commit messages end with ... PR body ends with ..." [brief] | Files section note, Phase 6, AC15 | mapped |
| 13 | "Fix-Size medium." [brief] | Split Assessment | mapped |
| 14 | "never ask the operator a technical question ... spawn `soleur:engineering:cto` ... Persist every decision as a row" [brief] | `decision-challenges.md` rows 2-21 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `commit-target-roots.sh` walker changes | "Extend `_ctr_git_walk` in `.claude/hooks/lib/commit-target-roots.sh`" | asked |
| `commit-index-sim.sh` | "New `.claude/hooks/lib/commit-index-sim.sh`" | asked |
| Hook glue and header comment | "the header comment in git-commit-secret-scan.sh" | asked |
| Test suite arms | "Tests (TDD first ...)" | asked |
| `secret-scanning.md` note | "a one-line note in `knowledge-base/engineering/operations/secret-scanning.md`" | asked |
| `decision-challenges.md` | "record the decision-challenge entry in the feature's decision-challenges.md" | asked |
| Pre-filter widening (`ctr_wants_lex`) | "plain `git commit -m x` pays nothing" | inferred - justification: detecting a chained add needs the lexer's argv; without widening the pre-filter the walker never runs for 77 percent of commits (CTO row 7) |
| `rm`/`mv` ignored by the walker | "any earlier `git add\|rm\|mv\|stage` argv" | inferred - justification: replaying them mutates the working tree and they add no content (CTO rows 2, 9) |
| Stage-unknown verbs forcing the superset | "otherwise ... fall back to superset `git add -A`" | inferred - justification: staging the replay cannot see would leave the hole this hook exists to close (CTO row 5) |
| Pathspec ladder `add -u -- paths` | "`commit -- path` scanned" | inferred - justification: a strict subset of the ruled superset that avoids false denies (CTO row 3) |
| One-root and directory-proof exactness rule, producer check | "exact replay" | inferred - justification: a misapplied replay or a missing-because-not-yet-created pathspec hides content from the scan (CTO rows 4, 8, 15, 16) |
| Unknown `--long` option forces the superset; force-add of literal words | "otherwise ... fall back to superset `git add -A`" | inferred - justification: git accepts unique abbreviations of staging options and `add -A` never sees ignored files (CTO rows 10, 12) |
| Config-transforming refusal, sim git pins, real-gitdir invariant | "failed superset or temp-dir failure -> DENY" | inferred - justification: `git add` on a temp index runs configured filters before permission evaluation and can write into the real git directory (measured; CTO rows 17, 18) |
| Batched `check-attr` edit in `scan_root` | "Call existing `scan_root` unchanged" | inferred - justification: the per-path loop costs 83 s at 5,000 paths and the superset makes that reachable; the edit is behaviour-preserving and ruled (CTO row 19) |
| 30 s total deadline, gitleaks wrapper, perl fallback | "failed superset or temp-dir failure -> DENY" | inferred - justification: an unbounded scan or `timeout 0` turns resource exhaustion into an unscanned commit (CTO row 20) |
| `cis_plan` / `cis_build` / `CIS_ENV` API and the consumer stub test | "(shared; a later brand-hex-gate follow-up reuses it)" | asked (the reuse requirement; shape ruled in row 21) |
| Split trap, `deny()` mode behaviour, distinct deny rule id | "failed superset or temp-dir failure -> DENY" | inferred - justification: the INT/TERM trap does not end the hook (measured), a would-be finding is not staged so `restore --staged` advice loops, and the ledger must separate superset-caused denies from real findings |
| `.claude/hooks/README.md` rewrite | — | inferred - justification: the README states the hook scans the index "BEFORE the command runs (#10696)"; after this PR that is false |
| `guardrail-audit.md` rows and count | — | inferred - justification: `verification-scaffold/test/manifest.test.sh` reds CI for any hook file without an audit row; the census count and the template divergence note would otherwise rot |
| Template and readme disclosure sentences | — | inferred - justification: user repos receive a template that lacks this feature while its readme says the staged index is scanned |
| `scripts/suite-durations.tsv` refresh | — | inferred - justification: the suite weighs 6.9 s in the table and about 187 s in reality; the added arms make the shard-leg balance wrong |
| `MIN_ASSERTIONS` bump | — | inferred - justification: the floor is exactly the current 405; without raising it in the same edit the floor stops guarding the new rows |
| Follow-up issue listing the residuals | — | inferred - justification: CTO rows 5 and 11 require a tracked residual; a deferral without an issue is invisible |

### Split Assessment

- Subsystems touched: 4 - `.claude`, `knowledge-base`, `plugins`, `scripts`
- Planned files: 13 | Estimated changed lines: about 1,100 (tests ~550, sim lib ~230, walker ~220, hook glue ~100)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: split considered and rejected - single PR. The thresholds are crossed on subsystem roots (4, with `scripts/` being a one-row table refresh) and on lines (the test file dominates). A split along the walker / library / glue seam would leave the hook half-wired and the walker outputs unconsumed, and the CTO ruled "ship as its own PR" (Fix-Size medium); the new helpers and arms are the cost of the CTO's own failure-posture rulings, not scope growth. If the work phase finds the line count above about 1,400, split the documentation and template disclosure into a trailing PR.

## Acceptance Criteria

- [x] AC1 (groups 1, 2, 7, 10): each of `git add -A && git commit -m x`, `git add leak.json && git commit -m x`, `git add $F && git commit -m x`, the glob form, the `xargs`, `find -exec` and `mise exec` forms, the four wrong-directory commands (10b) and `cd <wt> && git add -A && git commit -m x` from a bare-root cwd returns `permissionDecision: deny` with a reason naming `leak.json`; each has a gap-witness control (plain `git commit -m x` on the same shape allows). Verify: `bash .claude/hooks/git-commit-secret-scan.test.sh`.
- [x] AC2 (group 3, must-PASS control): `git add clean.txt && git commit -m x`, the quoted `git add "my file.md"` form and the `rtk` form, each with an unrelated untracked leak, are allowed, and the shim log shows an exact replay and no `add -A`; each has a deny twin on the same fixture.
- [x] AC3 (groups 4, 5): `commit -am` / `-a -m` / `-sam` with a tracked modified leak denies; `commit -a` with an untracked leak is allowed (`add -u`, falling back to `add -A` only on failure).
- [x] AC4 (group 6): `commit -- tracked.json` denies when that file holds the leak and allows when the leak is in a different tracked file; the bare-first-word and `-o` / `-i` forms behave the same. A positional path after `-m "..."` is documented as a residual, not tested as covered.
- [x] AC5 (group 7): `git add -p`, `$F`, glob/brace/tilde, `xargs`, `find -exec`, `mise exec` forms and options after the pathspec use the superset: the shim log shows `add -A` and never `add -p`, and the `EDITOR` marker is absent.
- [x] AC6 (group 8): a `-diff` gitattribute plus a chained add is still denied, with the `-diff` message (real-gitleaks canary), and the shim env log shows the sim variables on the `diff --cached`, `check-attr` and `show :` calls.
- [x] AC7 (group 9): after every hook run (allow, deny, TERM), the real index (`cmp`), the real loose-object count, the real git directory listing (including a `core.splitIndex=true` fixture) and the working tree are identical to their pre-run snapshots, and the private `TMPDIR` is empty; the sim directory is mode 0700; after TERM the hook exits 143 with empty stdout.
- [x] AC8 (group 9): for plain `git commit -m x` and `git commit -n -m x` the PATH shim logs lines (> 0) and no sim call, the lexer-skipped path still allows with the new `CTR_*` variables unset, and `ctr_wants_lex 'git commit -m x'` and `'git commit -m "fix the commit scan"'` return false. SUPERSEDED by CTO rows 22 and 46: where perl exists the lexer runs on EVERY strict commit (one lexer run, no sim call for a plain commit), and `ctr_wants_lex` is only the positive allowlist of the perl-less path (`'git status && git commit -m x'` is a tooling deny there, not a skip).
- [x] AC9: the diff of the `scan_root` bodies (extracted with `awk '/^scan_root\(\) \{/,/^}/'` from `origin/main` and from the working file) shows only the batched-`check-attr` hunk; the old-vs-new equivalence test passes (spaces, quotes, newlines, attribute values); the exported variables reach `gitleaks`, `git diff --cached`, `git check-attr` and `git show` (per-invocation env log in the shim plus a recording gitleaks stub capturing `$GIT_INDEX_FILE` inside the call). **Amended by the review-round rulings 29 to 31:** the `scan_root` diff is the batched-`check-attr` hunk plus the `core.fsmonitor` pin, the one-call `-diff` re-scan, the bound prefix on the two gitleaks calls, and the sim-mode failure denies.
- [x] AC10 (group 12): in a linked worktree the sim copies `.git/worktrees/<name>/index` and resolves blobs that exist only in the common object store; the index and objects paths are absolute; symlinked directory / file / `.gitleaks.toml` rows behave as designed.
- [x] AC11 (group 11; as shipped, rows 25 and 34): a path that does not exist -> DENY `cause=pathspec-missing` naming the path and git's line (no producer rule, no bypass row, no `sim-failed` id); any other replay failure -> superset; failed superset, `mktemp` / `cp` failure, `:` in the objects path, deadline, gitleaks timeout, `check-attr` batch failure -> deny with the retry that fits the command's staging style (`git add -u` and WITHOUT `-a`; the staged-list check and WITHOUT the paths; or add then commit as a second call) and a sanitised error line; a missing, mismatched or truncated sim lib or walker denies chained and plain strict commits; perl absent denies everything but a single simple commit with the `tooling` text.
- [x] AC12: `git rm a.txt && git mv b.txt c.txt && git commit -m x` leaves both working-tree files in place and runs no sim; a stage-unknown verb, a loop in the text, a relative single target, a mixed-directory command, a payload without `cwd`, an unknown launcher and two scanned roots each force the superset (shim log); a config-transforming staging argument is refused and its canary marker is never created; a configured filter marker never runs at hook time; a force-added ignored file is covered by the exact replay and denied-with-repair when its words are non-literal.
- [x] AC13 (group 13): at least 30 interleaved pairs on a scratch worktree of this repo (about 19.9k tracked files); `p95(b) - p95(a)` at most 1.5 s (p95 = the 29th of 30 sorted samples); the paired p50 difference, `uptime` load, filesystem, the unstaged-baseline figure, the 5,000-untracked figure (cap 5 s) and the 5 MB figure are in the PR body. If the gate fails: STOP, decision flips to KEEP-OPEN, not shipped, reported to the operator.
- [x] AC14: suite green with `MIN_ASSERTIONS` raised to the measured total (nothing skipped); added suite wall time at most about 60 s; the canary arms also pass against gitleaks 8.24.2; `shellcheck` clean on the four shell files; `python3 scripts/lint-trap-tempfile-ownership.py` clean on the changed files; `bash plugins/soleur/skills/verification-scaffold/test/manifest.test.sh` green; markdownlint clean on the plan and tasks; the lexer-failure ceiling measured and under 0.5 percent, with the count in the PR body.
- [x] AC15: PR body contains `Closes #10696` and a separate `Ref #10331` line with no closing keyword, ends with `🤖 Generated with [Claude Code](https://claude.com/claude-code)`; every commit ends with `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`; `plugins/soleur/skills/work/SKILL.md` is absent from `git diff --name-only origin/main...HEAD`; `knowledge-base/project/specs/feat-one-shot-10696-secret-scan-staging-gap/decision-challenges.md` has the forty-seven rows (rows 1-21 plus the review-round rows 22-47; `grep -c '^| [0-9]' ...` returns 47). Verified 2026-10-25: two tool-written commits (`chore: initialize ...`, the `review-fix-round` trailer commit) carry no Co-Authored-By line; the PR squash-merges, so neither reaches main. decision-challenges.md now has 56 rows and the gate passes.
- [x] AC16 (diff scope): the final diff is a subset of the Files to Edit / Create above plus the files the pipeline itself writes (`knowledge-base/INDEX.md` if regenerated, `specs/<branch>/session-state.md`, the plan and tasks).
- [x] AC17 (reuse): the consumer stub test passes (about 15 lines, sources the lib, `cis_build`, `env "${CIS_ENV[@]}" git diff --cached --name-only`, no secret-scan code); the follow-up issue exists and is linked from the PR body. Verified 2026-10-25: follow-up issue #11100, consumer stub test in the suite (_t_sim_consumer).

## Test Scenarios

- Given an untracked file holding a synthetic PEM and the command `git add -A && git commit -m x`, when the hook runs, then it denies and names the file (integration).
- Given the same untracked file and the command `git add clean.txt && git commit -m x`, when the hook runs, then it allows (exact replay does not pull the unrelated file in) (integration).
- Given a tracked file modified to hold the PEM and `git commit -am x`, then deny; given the PEM in an untracked file and `git commit -a -m x`, then allow (integration).
- Given `git add no-such-file && git commit -m x`, when the replay hits the benign missing pathspec in a proven directory, then the hook scans the superset, emits the bypass row and allows if clean; given `printf x > leak.json && git add leak.json && git commit`, then it denies with the `create` repair (integration).
- Given a shim that fails `git add -A`, when a superset is needed, then the hook denies with the repair text (integration).
- Given `git add -A && git commit` in a linked worktree whose blobs are only in the common store, then the sim builds and the leak is found (integration).
- Given a plain `git commit -m x`, then no sim code runs (integration with the PATH shim, plus unit rows on `ctr_wants_lex`).
- Properties that must never break (the differential oracle over a generated command table, not an example list): for every row the sim index contains every (path, blob) that the literal staging words produce with real git; no row lets the real index, real object count, real git directory listing or working tree change (unit + integration).
- Regression: the full pre-existing 405 assertions still pass (the #10609 target-resolution arms, T5 to T20 and the walker table).

## Success Metrics

- The thirteen ruled groups pass, with every mutation-matrix row driven RED at least once during Phase 5 (apply the mutation, observe the named red, revert).
- Added p95 latency at most 1.5 s on this repo, interleaved method.
- Zero change in the allow/deny decision for the pre-existing 405 assertions.

## Dependencies & Risks

- **Dependency**: `perl` and `plugins/soleur/hooks/lib/shell-argv.pl` (already required by the #10609 walker); `cp`; `timeout`, `gtimeout` or perl; gitleaks 8.24.2 in CI (the pin). Behaviour with `GIT_INDEX_FILE` was measured on 8.30.1; the canary arms are run against 8.24.2 before pushing, and a CI failure there is a design-level signal, not a flake.
- **Risk - false denies and slow commits**: the superset scans unrelated untracked, non-ignored files (about 1.3 s per MB of high-entropy text, 3.4 s for 5,000 small files). Accepted by the ruling for the fallback shapes; the deny text names the cause and the repair, and the `sim-deny` ledger id with mode and cause makes the rate measurable. Two scanned roots force the superset; Phase 5 tabulates how often.
- **Risk - deadline under load**: 30 s total with gitleaks bounded; expiry denies. The probe has needed 60 s retries at high load before, so a loaded host can produce a deny where the old hook would have passed through; the repair text says to re-run when the machine is quieter.
- **Risk - lexer failure modes now reach most commits**: about 77 percent of commits now take the lexer path, so a lexer error, the 2 s alarm under parallel-suite load, a bound, or a missing perl now denies a chained commit that used to skip it. Mitigated by the corrected repair text and the ceiling measurement (AC14).
- **Risk - walker under-recognition**: a staging form the pre-filter or walker does not classify keeps today's behaviour (not a regression, still a gap). The over-matching pre-filter, the stage-unknown verb list, the unknown-option rule and the launcher allowlist are the mitigation; the named residuals are in the header and the follow-up issue.
- **Risk - suite runtime**: the existing suite takes about 187 s locally (CI shard leg 4 of `scripts/suite-shard-legs.tsv`); the structural-stub / canary split and the 60 s budget keep the added arms cheap.
- **Risk - agents learn the deny wording**: the repair texts and the two new ledger ids become sticky once emitted; they are fixed in this plan (rows 14, 16, 17) before any row exists.
- **Rollback**: revert the PR; no data or state outside the repo is created.

## References & Research

- Issue #10696; closed epic #10331 (reference only); draft PR #10893; follow-up consumer #10793 (brand-hex gate cwd binding).
- `.claude/hooks/git-commit-secret-scan.sh` (`scan_root`, `deny`, `deny_undeterminable`, the trap), `.claude/hooks/lib/commit-target-roots.sh` (`_ctr_git_walk`, `ctr_wants_lex`, `ctr_resolve_roots`, `_ctr_has_loop`), `.claude/hooks/lib/hook-input.sh:403` (the `HOOK_CWD` fallback), `plugins/soleur/hooks/lib/shell-argv.pl` (output contract: per-word flags `-`, `q`, `x`, `qx`).
- `.claude/hooks/README.md` section "git-commit-secret-scan target resolution (#10609)".
- ADR-156, ADR-157, ADR-165 (hook input untrusted; ask when unparseable; what `ask` means headless), ADR-129 (tempfile ownership).
- Learnings listed under Research Insights.
