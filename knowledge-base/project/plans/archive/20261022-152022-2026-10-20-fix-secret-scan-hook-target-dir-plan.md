---
title: "fix(hooks): git-commit-secret-scan derives the repo from the commit's target directory"
date: 2026-10-20
slug: fix-secret-scan-hook-target-dir
branch: feat-one-shot-10609-secret-scan-target-dir
issue: 10609
closes: 10609
type: fix
priority: p2
domain: engineering
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

## Enhancement Summary

**Deepened on:** 2026-10-20
**Sections enhanced:** 4 (walker spec, Observability schema, Test Scenarios, Research Insights)
**Verification used (proportionate - the plan already had a five-seat eng review, a CTO panel of four rulings, CPO sign-off and gdpr-gate):** lexer-behaviour measurements on 12 command shapes, live cross-checks of every cited issue / PR / ADR / rule id / learning path, and the mechanical halt gates (4.6 User-Brand Impact, 4.7 Observability, 4.11 Guard Contract via `scripts/lint-guard-contract.py`, 4.12 Scope Check).

### Key Improvements

1. `env -C <dir> git commit` is a directory-changing wrapper the lexer exposes as plain argv (`[env] [-C] [/a] [git] ...`); the walker now adds its `-C` / `--chdir=` operand as a target instead of leaving it a documented gap.
2. The lexer was measured on the hard cases: `eval "$CMD"` and `bash -c "$SCRIPT"` surface the operand with an expansion (so the runner-operand deny is mechanically reachable), an unterminated quote exits 2 with the `E` framing, and `builtin cd` / `command git` arrive as separate leading words that the wrapper skip must drop.
3. An `## Observability` schema block was added so the plan passes the Phase 4.7 gate (the hook path is outside plan Phase 2.9's trigger set, but the deepen gate only skips pure-docs plans).

### New Considerations Discovered

- A quoted `-m "$(cat <<'EOF' ... cd "$WT" ... EOF)"` message lexes as ONE quoted word plus a `cat` substitution record, so the heredoc text never becomes a `cd` record (T35 is reachable and meaningful, not vacuous).
- `commit -C HEAD` arrives as `[commit] [-C] [HEAD]`: the walker must stop reading global options at the subcommand (walker unit row already present).

## Overview

The pre-commit secret-scan hook (`.claude/hooks/git-commit-secret-scan.sh`) resolves its repository
from the hook PROCESS working directory. In this repo the session is often anchored at the bare
repository root (`core.bare=true`, `.git` directory, overlay files). There,
`git rev-parse --is-inside-work-tree` exits 0 while printing `false`, and `git rev-parse
--show-toplevel` fails, so the repo root comes back empty and the hook records
`bypass ".gitleaks.toml absent"` and allows. A command of the shape
`cd <worktree> && git commit ...` is therefore never scanned (incident ledger row
2026-10-19T18:53:38Z; CI gitleaks is the only remaining backstop).

Review of the hook found a second, adjacent skip that the issue's `git -C` ask depends on: the
commit-detection regex (line 113) only matches `git commit` with nothing between `git` and `commit`.
Measured: `git -C /x commit`, `git --work-tree=/x commit`, `git -c a=b commit` and `git --no-pager commit`
do NOT match, so the hook allows them before it scans anything. The `git -C <worktree> commit` fixture the
brief asks for cannot pass without fixing detection too.

The fix: (1) detect `git <global options> commit`; (2) make the hook scan the repository the commit
actually targets. It reuses the repo's existing hardened shell lexer
(`plugins/soleur/hooks/lib/shell-argv.pl`) through a thin bash walker that collects every literal
`cd` / `pushd` / `git -C` target, scans the union of those repos plus the old cwd-derived roots, and
DENIES when the target is not a literal path (never skips).

## Research Reconciliation — Spec vs. Codebase

| Claim | Reality | Plan response |
|---|---|---|
| Issue: "Not verified: the exact working directory the hook saw." | Reproduced in a scratch repo: at a `core.bare=true` root `--is-inside-work-tree` prints `false` with rc 0, so the hook's rc-only guard passes and `--show-toplevel` fails (rc 128), yielding the empty root and the `.gitleaks.toml absent` row. A linked worktree of that root resolves normally via `git -C <wt> rev-parse --show-toplevel`. | Root cause confirmed; the fixture uses the same topology. |
| Issue: "parse a leading `cd <path>` (or `git -C <path>`)". | A "leading" `cd` is too narrow: `cd A && git add x && git commit`, `cd A; cd B && git commit`, `(cd B && git commit)`, `bash -c 'cd B && git commit'` and `git -C A status; git commit` are all plausible agent output. | Scan the union of every literal target, plus fallback roots. |
| Brief/issue imply `git -C <path> commit` reaches the scan. | It does not: the line-113 regex never matches it (measured with `grep -E` on six commands). | Widen detection (Design step 1); this is in scope because the `git -C` fixture is an ask. |
| Existing `resolve_command_cwd` (`.claude/hooks/lib/incidents.sh`) looks like the reusable resolver. | It parses with `sed`/`xargs`, returns one directory, silently falls back to payload `.cwd` / `CLAUDE_PROJECT_DIR` when the directory does not exist (the skip path), and has no "unresolvable" signal; `guardrails.sh` and `context-reviewed-gate.sh` depend on its current behaviour. | Not reused; left untouched. |
| Brief: "resolve the target directory safely (no eval, no command substitution)". | The repo already ships two hardened core-Perl shell lexers (`.claude/hooks/lib/filing-shape.pl`, `plugins/soleur/hooks/lib/shell-argv.pl`, parity-pinned). `learnings/security-issues/2026-09-28-every-grammar-rule-my-lexer-skipped-was-a-bypass-and-my-oracle-explained-its-own-flips.md`: a hand-written first lexer got 31 review findings. | Reuse `shell-argv.pl` directly; no third lexer. CTO ruled (Decision Classes T5). |

## Research Insights

**Premise validation (Phase 0.6).** `gh issue view 10609`: OPEN, no closing PR. `gh issue view 10331`: CLOSED
(code-quality arc epic; reference only, never reopen). The cited file exists on this branch (315 lines; repo/toml
guards at lines 128-138); its suite `.claude/hooks/git-commit-secret-scan.test.sh` is green at baseline (20 passed,
0 failed, 0 skipped, local gitleaks 8.30.1 while CI pins 8.24.2). ADR corpus grep (`bare`, `core.bare`, `worktree`,
hook names): ADR-099 (git surface topology), ADR-173 (bare config polarity for linked worktrees), ADR-156/157 (hook
stdin untrusted; unparseable input asks), ADR-165 (what ask means on a harness with no ask state), ADR-256 and
ADR-277 (the lexers). None rejects the approach. ADR-157 governs the ENVELOPE parse (`hook_parse_input`) and says
"never denies"; this plan's deny is a content-level gate decision about command text the envelope parsed fine, and it
is recorded as an addendum to ADR-157 (Architecture Decision section).

**Property List.**

1. P1: a `git commit` (including `git <global options> commit`) is scanned against the repository it targets, whatever the session cwd.
2. P2: a target that cannot be determined statically never results in a skipped scan.
3. P3: command text is never executed or substituted while resolving (no `eval`, no `$()`, no `xargs`).
4. P4: a command with no directory-affecting token behaves byte-identically to today (same bypass reasons, same order).

**Cut List.**

- Sequential `cd` simulation to ONE effective directory -> buys P1, already bought more safely by the union scan (extra scans only add denies) -> cut.
- Reusing/extending `resolve_command_cwd` -> its silent fallback is the defect -> cut.
- A third, hand-written lexer (bash or perl) -> `shell-argv.pl` buys P3 and is parity-tested -> cut.
- Changing the no-target bare-root bypass -> `git commit` in a bare root cannot stage anything, P4 -> cut.
- New incident-ledger schema / telemetry fields -> existing `deny` / `bypass` rows carry the reason strings -> cut.
- Value parsing of `--git-dir` / `--work-tree` / `GIT_DIR=` / `GIT_WORK_TREE=` (parent-dir mapping, gitdir shapes) -> presence on a commit record is treated as a non-literal target (deny) -> cut (review: DHH, simplicity, architecture all found the mapping wrong or costly).
- `~` expansion, the 8-target cap, the "only records before the LAST commit count" scoping -> cut (simplicity review); any non-literal target in a command that contains a commit record denies.
- Scanning every linked worktree instead of resolving the target (DHH alternative) -> changes the operator-stated direction ("derive the repo root from the commit's target directory") -> kept as the default, recorded as a challenge (Decision Classes T13).

**Institutional learnings applied.**

- `2026-10-19-hook-gates-diff-the-workdir-not-the-inline-cd.md`: gates see the exec workdir (here: the process cwd / payload `.cwd`), not a later `cd` in the text. Both are therefore unioned.
- `2026-09-28-every-grammar-rule-my-lexer-skipped-...`: reuse the lexer; fixture the LANGUAGE (redirects, `$()`, quotes, heredocs, `bash -c`), not only the feature cases.
- `2026-10-06-a-guard-folded-its-probe-error-into-untracked-and-my-fix-broke-the-bare-root.md`: read every non-zero exit of a git probe separately; gate bare-root behaviour on `rev-parse` results, not on guesses.
- `2026-02-24-guardrails-chained-commit-bypass.md`: match at command boundaries.
- `2026-06-09-gitleaks-same-id-custom-rule-shadows-default-pack-rule.md` and AGENTS `cq-test-fixtures-synthesized-only`: build the fake secret by concatenation (`_mk_pem` already does).
- Sharp Edge (plan-sharp-edges): "A fail-closed change is not done until its most natural REPAIR is also refused" and "a plan that segments shell text must fixture every overloaded character" - see S-repair and the walker unit rows.

**Deepen-plan measurements (2026-10-20).** `perl plugins/soleur/hooks/lib/shell-argv.pl --trace` on 12 shapes: `eval "$CMD"` -> `[eval] [$CMD]` (operand carries the expansion flag); `bash -c "$SCRIPT"` -> `[bash] [-c] [$SCRIPT]`; `cd ~/wt` -> `[cd] [~/wt]`; `git -c a=b --no-pager -C ../x commit -C HEAD` -> one record with `-C` appearing both before and after `commit`; `GIT_DIR=/x git commit` -> the assignment is a leading word; `(cd /a && git commit)` and `cd /a 2>&1 && git commit` -> plain `cd` and `git` records (redirects dropped); `builtin cd /a && command git commit` -> `[builtin] [cd] [/a]`, `[command] [git] [commit]`; `env -C /a git commit` -> `[env] [-C] [/a] [git] [commit]`; an unterminated quote -> exit 2; the heredoc-in-`-m` message -> a `cat` substitution record and one quoted `git` word. Run time about 7 ms.

**Cross-checks done live.** Issues #9089 (CLOSED), #10331 (CLOSED), #10609 (OPEN), #10696 (OPEN), PR #9099 (MERGED); ADR-099, 156, 157, 165, 173, 256, 277 exist; every AGENTS rule id cited exists as an active rule; all four plan-cited learning paths exist.

**Sensitive-surface note.** `.claude/hooks/` is not in preflight Check 6's `SENSITIVE_PATH_RE`, but the brief and AGENTS
`hr-weigh-every-decision-against-target-user-impact` treat it as one; the threshold is declared explicitly below.

## Problem Statement

See Overview. Concretely, `git-commit-secret-scan.sh:113` gates detection, `:128-138` computes `repo_root` once from the
process cwd, and `:215-262` (`check-attr` loop, `gitleaks git --pre-commit --staged`, the `-diff` re-scan) all key off
that single `repo_root`, with `allow` / `exit` calls inside the scan block (`:287-289`, `:310`).

## Proposed Solution

### Design (rulings in Decision Classes)

New file `.claude/hooks/lib/commit-target-roots.sh` (bash 3.2 compatible: no `mapfile`, no `declare -n`, no
associative arrays; empty arrays under `set -u` read as `${a[@]+"${a[@]}"}`; `$HOME` read as `${HOME-}`) exposing:

- `ctr_wants_lex <command>` - cheap pre-filter. True when the text contains a directory-affecting token: `cd`,
  `pushd`, `GIT_DIR`, `GIT_WORK_TREE`, `--git-dir`, `--work-tree`, or `git` followed by an option (`git[[:space:]]+-`).
  Over-matching is safe (it only runs the lexer); the token list is pinned by a test (it must never under-match
  a form the walker handles). Commands that do not match skip perl entirely, so the no-token path is unchanged (P4).
- `ctr_collect <command>` - pipes the command (via `printf '%s'`, never interpolated into any program text) to
  `perl "$LEXER"`; `LEXER` is resolved from the hook's OWN directory (`${BASH_SOURCE[0]%/*}/../../../plugins/soleur/hooks/lib/shell-argv.pl`), never from `$PWD`.
  The call is guarded so a non-zero perl status cannot abort the hook under `set -euo pipefail`. Frames are read with
  `IFS= read -r -d ''` (no whitespace stripping of paths), parsed BY COUNT (`argc` validated numeric, the stream checked
  for truncation mid-record). Command substitution cannot carry NUL, so the lexer exit status is not recoverable: the
  terminating `OK` field is the ONLY success signal, and a stream without it is `E`. Sets `CTR_TARGETS`, `CTR_BAD`
  (reason strings), `CTR_COMMIT_SEEN` (a `git ... commit` record exists) and `CTR_LEX_STATE` (`ok` | `unavailable`).
- Record walker (per record, any ctx): skip leading `NAME=value` words (`GIT_DIR=` / `GIT_WORK_TREE=` -> bad) and the
  wrappers `env command builtin exec nohup time` (measured: they arrive as separate leading argv words, e.g. `[builtin] [cd] [/a]`, `[command] [git] [commit]`); `env -C <p>` / `env --chdir=<p>` adds `<p>` as a target (measured: `[env] [-C] [/a] [git] ...`), `env -S` or an expansion operand -> bad; then
  - `cd` / `pushd`: skip options `-L -P -e -@ --`; the first operand is a target; no operand -> `$HOME`; an operand
    flagged `x` (expansion), `-`, or any word starting with `~` -> bad (agents are told to use absolute paths).
  - `git`: loop over global options - `-C <p>` (adds `<p>`; repeated `-C` each resolve against the previous),
    `-c <kv>` (skipped), `--git-dir[=]` / `--work-tree[=]` (presence -> bad), any other leading dash word skipped; an
    operand flagged `x` is bad; the first non-dash word is the subcommand; `commit` sets `CTR_COMMIT_SEEN`. A `-C`
    AFTER the subcommand (`commit -C HEAD`) is not a global option.
  - Runner records (`bash|sh|zsh|dash|ksh` with `-c`, and `eval`) whose script operand is flagged `x`
    (`eval "$CMD"`, `bash -c "$SCRIPT"`) -> bad: the commit may be hidden in a variable the lexer cannot see.
  - `CTR_BAD` only denies when `CTR_COMMIT_SEEN` or the strict detection regex matched; a command where the lexer
    finds no commit record leaves the roots as the fallback roots, exactly today's behaviour.
- `ctr_resolve_roots` - for each literal target: an absolute path stands alone; a relative path is joined against each
  base in {process `$PWD`, payload `.cwd` (`HOOK_CWD`), every earlier absolute candidate}; each existing directory is
  mapped through `env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE git -C <cand> rev-parse --show-toplevel` (stderr
  discarded); unique toplevels (de-duplicated by string membership, no `declare -A`) go to `CTR_ROOTS`. A literal target
  that does not exist, or is not in a work tree, is silently dropped (it cannot stage anything).

Hook flow (`git-commit-secret-scan.sh`), keeping the strict detection regex at line 113 byte-for-byte:

1. Detection. Strict regex (line 113, unchanged) OR, added after line 115, a loose test (`git` ... `commit` as words, and
   `ctr_wants_lex`). Neither -> `allow` as today. A loose-only match is confirmed by the lexer: no commit record -> `allow`
   (not a commit); lexer unavailable -> falls into step 4's deny.
2. Existing: `command -v gitleaks` (absent -> bypass, unchanged).
3. Source the library. If it is missing/unsourceable it is an "undeterminable target" condition handled in step 4 (one rule
   for every undeterminable case, so the exit table has a single ordering).
4. `ctr_wants_lex` false -> legacy path exactly as today (roots = the cwd-derived root; same two bypass reasons in the same
   order; the probe stays after the repo/toml guards). `ctr_wants_lex` true -> `ctr_collect`. Library missing, lexer
   unavailable (perl missing, lexer file missing, exit 2 / 3, `E`, truncated stream) or any `CTR_BAD` while a commit is
   detected: run the memoized gitleaks-runnable probe FIRST (an unrunnable/timed-out gitleaks keeps its allow + bypass
   row), THEN `deny` with the repair text below.
5. Otherwise roots = `CTR_ROOTS` UNION the cwd-derived root UNION the payload-`.cwd` root, de-duplicated. The fallback
   roots are ALWAYS included (a `-C` can belong to a non-commit segment, as in `git -C A status; git commit`; and the
   "separate `cd` call" repair relies on payload `.cwd`). Trade-off accepted (CPO, CTO): an unrelated staged secret in the
   cwd repo can deny a commit aimed elsewhere; the deny reason names the root that held the finding and says to unstage
   or scrub IN THAT ROOT.
6. No roots -> the legacy bypass chain with its legacy reason selection (`not inside git work tree` when
   `--is-inside-work-tree` exits non-zero, else `.gitleaks.toml absent`). The no-target bare-root bypass stays (a `git
   commit` in a bare root cannot succeed).
7. Per root: no `.gitleaks.toml` -> warn + `bypass ".gitleaks.toml absent"` for that root and continue; none with a toml ->
   allow. Otherwise run the (memoized) probe, then the existing scan block refactored into `scan_root <root>`: it
   `return`s a status (never `allow`/`exit` inside the loop), keeps ALL per-root state local (`gl_nodiff`, the `-diff`
   scratch dir and report, `report_file` truncated per root), and the single final `allow` comes after the loop. A finding
   `deny`s with the root path in the reason.

The gitleaks-runnable probe (current lines 140-186) moves into a memoized function `gitleaks_runnable` - same logic, same
two bypass rows. It is called in the main shell (never inside `$(...)`, which would lose the memo flag and could not
`allow`/`exit` the hook), at most once per invocation.

**Deny text (acceptance-tested, S-repair).** For an undeterminable target the reason names the cause and says: (a) the
staged content was NOT scanned and the commit is blocked; (b) two repairs: when the cause is a missing perl or lexer, install perl (the lexer needs it); and run
`cd <absolute worktree path>` as its OWN command first, then run `git commit` with no `cd`/`-C` (this relies on the shell cwd
persisting between Bash calls, which the Bash tool documents but which is unverified for hook payloads - the text must not
rely on it alone, and the post-merge ledger check confirms it); (c) or use a literal absolute path, `git -C /abs/path commit`, or `cd /abs/path && git commit`
(use `git worktree list` for the path); (d) forms that do NOT work and are denied: `$VAR`, `$(...)`, backticks, `~`,
`$(git rev-parse --show-toplevel)`, `GIT_DIR=`/`--git-dir`/`--work-tree`, `bash -c`, `eval`; do not route around the hook
with a script or alias (they skip the scan). There is no operator override variable by design (an override is the skip
path); the separate-`cd` repair is the escape hatch. For a finding in a root other than the cwd, the reason names the
root and says to unstage or scrub in that root.

### Alternatives considered

| Option | Verdict |
|---|---|
| Reuse `resolve_command_cwd` | Rejected: silent fallback is the defect; single directory; xargs-parses untrusted text. |
| Hand-written pure-bash lexer (first CTO ruling) | Reversed after the existing `shell-argv.pl` was found; a hand-written lexer repeats the #9089 failure class. |
| Third vendored copy of the lexer | Rejected: parity burden, no added hardening. |
| Depend on `.claude/hooks/lib/filing-shape.pl` instead | Rejected: its output is filing-specific (`gh issue create` shapes), not generic argv. |
| `ask` on unresolvable target (ADR-157 style) | Rejected: a headless pipeline cannot answer (ADR-165), so an ask degenerates into a skip; the deny is cheap to repair. |
| Simulate sequential `cd` to one effective dir | Rejected: needs shell state modelling; the union over-approximates safely. |
| Scan all linked worktrees with staged content | Rejected as default (changes the stated direction); recorded as T13. |

## Technical Considerations

- **Portability.** The hook runs on stock macOS (bash 3.2, no GNU `timeout`). The walker uses only bash 3.2 features; `perl` ships on macOS and Linux. `env -u` is available in BSD env.
- **Line pin.** `plugins/soleur/test/boundary-prefix.test.sh` exempts `.claude/hooks/git-commit-secret-scan.sh:113` positionally (the strict `git commit` boundary regex). The plan keeps that regex byte-identical and puts all new code AFTER line 115; the header comment edit (fail-open list, lines 25-35) must keep the SAME line count, or the `EXEMPTIONS` entry (line 234) and its comment (line 206) move in the same commit. The same census scans `.claude/hooks/lib/*.sh`, so the new library must not carry a line with both a `(^|` boundary alternation and a gated-command literal; the loose test in the hook must also stay outside that pattern or be exempted by file:line.
- **Inherited git env.** An exported `GIT_DIR` overrides `git -C`; the resolver strips `GIT_DIR`, `GIT_WORK_TREE`, `GIT_INDEX_FILE` for its probes (as `bare-root-cwd-guard.sh` does).
- **Performance.** Measured: `shell-argv.pl` lexes a 3-command string in about 7 ms. Perl runs only when the pre-filter matches.
- **Lexer ownership.** `plugins/soleur/hooks/lib/shell-argv.pl` is plugin-owned and ships to customers; the hook takes a runtime dependency on it from inside the same repo. `shell-argv-parity.test.sh` pins the shared lexer spans and `--trace` argv, NOT the NUL record framing the walker reads; T40 (in the hook's suite) asserts the framing and that the resolved lexer path exists, and the README states the coupling. If the plugin dir moves, the hook fails closed (lexer unavailable -> deny for tokenised commands) with a repair text, never open. The Devin binding (`.devin/config.json`, disposition `bind`) resolves the hook from `$hook_root/.claude/hooks`, and `plugins/soleur/` sits in the same checkout (also in the bare-root `sync_bare_files` overlay of HEAD); T40's path assertion covers it. Cloud sessions run no hooks (INSTRUCTIONS.md Cloud Mode), so they are unaffected.
- **Threat model (documented, not defended).** The adversary is a fallible cooperative agent, not a hostile one. Not modelled: aliases, `xargs git commit`, a script that runs the commit, `find -exec`. Those fall back to the fallback roots (today's behaviour). Also unchanged: a command that stages and commits in one call (`git add -A && git commit`, `git commit -a`) is scanned against the index BEFORE it runs - tracked separately in #10696 (deferred, `deferred-scope-out`).
- **Attack Surface Enumeration.** Ways the commit target can be named in command text: leading/chained `cd` and `pushd`; `git -C` (repeatable); `--git-dir[=]`, `--work-tree[=]`; `GIT_DIR=` / `GIT_WORK_TREE=` assignments; subshell `( ... )`; `$(...)` / backticks; `bash|sh|zsh -c '...'` and `eval`; `builtin cd`; wrappers (`env`, `command`; `env -C <dir>` is parsed as a target). Literal forms are covered by the union + lexer re-lexing; non-literal and git-dir/work-tree forms by the deny. Documented non-goals: `xargs`, `find -exec`, aliases, scripts.

## User-Brand Impact

- **If this lands broken, the user experiences:** (a) a legitimate `git commit` from a worktree is denied with a message naming the repair (a separate `cd`, then a plain commit) - a re-run, not lost work; or (b) worse, the hook errors out or misparses and a commit that stages a credential goes through unscanned, exactly as the 2026-10-19 incident did.
- **If this leaks, the user's credentials / workflow are exposed via:** a secret-shaped string (cloud key, token, PEM) committed to a branch of this public repository before CI's gitleaks job runs; once pushed it is in history and must be treated as burned and rotated.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** `single-user incident`, not `aggregate pattern`: this hook is the pre-commit secret gate, one leaked credential reaching public git history is by itself a reportable incident that cannot be undone by reverting the commit, and `.claude/hooks/` is a sensitive surface that clamps the threshold above `none`; the CI gitleaks backstop narrows but does not remove the window.

`requires_cpo_signoff: true` (frontmatter); sign-off recorded in Domain Review. `soleur:engineering:review:user-impact-reviewer` runs at review time. Artifact / vector pairs for the reviewer:

- Pair 1: a denied legitimate commit -> the repair in the deny text must itself pass the hook (S-repair).
- Pair 2: an unscanned commit -> `cd "$VAR" && git commit`, `git -C <wt> commit` (detection gap), `bash -c`, `eval "$CMD"`, `GIT_DIR=`, a perl-less host, a lexer bound hit; each is a Test Scenario below.

## Observability

The plan Phase 2.9 trigger set does not list `.claude/hooks/`, but the deepen gate (4.7) only skips pure-docs plans, so the schema is declared. The signal exists: every outcome writes an incident-ledger row via `emit` (`.claude/.rule-incidents.jsonl`): `deny` rows for findings and for the new undeterminable-target deny (reason prefix `git-commit-secret-scan: BLOCKED: cannot determine`), and one `bypass` row per root skipped (`.gitleaks.toml absent`) or per environment fault. A drop in `bypass ".gitleaks.toml absent"` rows after bare-root sessions is the field confirmation; the false-deny rate is read from `cannot determine` rows (CTO ruling: flip the fallback-union policy only if it proves material). Whether payload `.cwd` follows a prior separate `cd` call in the real harness is confirmed post-merge from the ledger (the repair path depends on it); the fixture T42 proves the hook side.

```yaml
liveness_signal:
  what: incident-ledger rows (deny and bypass) written by the hook through emit on every commit it evaluates
  cadence: per git commit evaluated by the hook
  alert_target: none automatic (local developer hook); the false-deny and skip rates are read from the ledger after landing
  configured_in: .claude/hooks/git-commit-secret-scan.sh (emit calls) and .claude/hooks/lib/incidents.sh
error_reporting:
  destination: the hook JSON permissionDecisionReason (deny) plus stderr WARN lines and ledger rows for every bypass
  fail_loud: true - every undeterminable-target condition denies with a named cause and repair; no path skips silently
failure_modes:
  - mode: target directory not determinable (non-literal, lexer error, perl or library missing)
    detection: deny reason prefix "git-commit-secret-scan: BLOCKED: cannot determine" in the ledger
    alert_route: the agent sees the deny at once; repeated rows in the ledger surface a false-deny pattern
  - mode: root skipped because it has no .gitleaks.toml
    detection: bypass row ".gitleaks.toml absent" (one per root)
    alert_route: ledger row plus stderr WARN
  - mode: gitleaks unrunnable or probe timed out
    detection: existing bypass rows "gitleaks unrunnable" / probe-timeout
    alert_route: ledger row plus stderr WARN
logs:
  where: .claude/.rule-incidents.jsonl (local) and the hook stderr
  retention: governed by .claude/hooks/lib/log-rotation.sh
discoverability_test:
  command: grep -q 'cannot determine' .claude/hooks/git-commit-secret-scan.sh && printf ok
  expected_output: ok
```

## Architecture Decision (ADR/C4)

### ADR

No new ADR. One addendum to `knowledge-base/engineering/architecture/decisions/ADR-157-a-hook-that-cannot-parse-its-input-asks.md` (via `soleur:architecture`): the ask-not-deny rule governs the hook ENVELOPE; a content-level gate whose purpose is preventing an irreversible leak denies, with a named repair, when it cannot determine its scan target, because an ask has no answerer in a headless pipeline (ADR-165) and degenerates into a skip. Cross-reference ADR-256's existing scoped exception. This is a task in Phase 4, not a deferred issue.

### C4 views

No C4 impact. Checked against all three model files (`model.c4` 993 lines, `views.c4`, `spec.c4`): the only `gitleaks`/`secret-scan` mention is a CI workflow pattern reference inside the Grype description at `model.c4:440`; no element models the repo-local PreToolUse secret-scan hook. This change adds no external human actor, no external system or vendor (gitleaks and perl are local binaries), no data store or container, and changes no actor-to-surface access relationship; the derived cardinalities `c4-count-parity` gates are untouched (`plugins/soleur/test/c4-count-parity.test.sh` is run in Phase 4 to confirm).

### Sequencing

The ADR-157 addendum is authored in this PR describing the final state; nothing is soak-gated.

## Open Code-Review Overlap

None. (`gh issue list --label code-review --state open` filtered by `.claude/hooks/git-commit-secret-scan`, `commit-target-roots`, `boundary-prefix.test.sh` returned no matches.)

## Files to Edit

- `.claude/hooks/git-commit-secret-scan.sh` - detection widened (after line 115), flow above; header comment (fail-open list) updated line-neutrally; scan block -> `scan_root`; probe -> memoized `gitleaks_runnable`.
- `.claude/hooks/git-commit-secret-scan.test.sh` - new fixtures T21+ (below) and a `_run_cmd <cwd> <command> [path]` helper (the existing `_run_stub` hardcodes `git commit -m x`); registers no new suite (already in `scripts/suite-shard-legs.tsv`, weight 4).
- `plugins/soleur/test/boundary-prefix.test.sh` - ONLY if line 113 shifts: the `EXEMPTIONS` entry and the comment naming `git-commit-secret-scan.sh:113`.
- `.claude/hooks/README.md` - one paragraph under the git-commit-secret-scan entry: target resolution, deny-on-undeterminable, the separate-`cd` repair, the lexer coupling.
- `knowledge-base/engineering/architecture/decisions/ADR-157-a-hook-that-cannot-parse-its-input-asks.md` - addendum (above).

## Files to Create

- `.claude/hooks/lib/commit-target-roots.sh` - the walker described above. (Walker unit rows live in the hook's own suite to avoid a new shard registration.)

## Implementation Phases

### Phase 0 - Guard design before code (RED first)

Write the fixtures below as failing tests against the CURRENT hook (every resolution/detection fixture must be RED on the unmodified hook; the must-ALLOW controls GREEN). Confirm the baseline (20 passed) and capture RED counts. Measure first: (a) the strict regex vs six `git` option shapes; (b) the fixture PEM actually triggers gitleaks inside a linked worktree of a `core.bare=true` root (done at plan time: it does, with the `t5_`-style payload).

### Phase 1 - Library

Create `commit-target-roots.sh`. Verify by hand against `perl plugins/soleur/hooks/lib/shell-argv.pl --trace < file` for each Test Scenario command (feed from a FILE, never paste into a double-quoted argument).

### Phase 2 - Hook refactor

Refactor per the flow. Keep behaviour identical for `ctr_wants_lex`-false commands (run the existing 20 arms unchanged first).

### Phase 3 - Fixtures green, mutation battery

Run the matrix mutants against COPIES of the hook/lib in a scratch dir (never mutate the live tree), record each RED, restore.

### Phase 4 - Pins and docs

`boundary-prefix.test.sh` (line pin / census), `c4-count-parity.test.sh`, README paragraph, ADR-157 addendum via `soleur:architecture`, markdownlint on touched markdown.

## Test Scenarios

Fixture topology (helper `_mk_bare_root_with_worktree`): a scratch dir `git init`-ed, seeded with one commit, `git config core.bare true`, NO `.gitleaks.toml` at the root; `git worktree add .worktrees/wt` carries `.gitleaks.toml` (copied from the repo) and a staged fake PEM from `_mk_pem` (assembled by concatenation, using the `t5_`-style payload shape the existing arms use - a payload without an underscore token did not trigger the rule in a scratch run). The hook process cwd is the scratch root unless stated. **Fixture control (mandatory):** a plain `gitleaks git --pre-commit --staged` run inside the worktree must exit non-zero, or the fixture is reported broken (as `_t_nodiff_attr` does).

| ID | Hook cwd | Command | Expected |
|---|---|---|---|
| T21 incident replay | bare root | `cd <wt> && git commit -m x` | deny, reason names the leak file and the worktree root |
| T22 | bare root | `git -C <wt> commit -m x` | deny (RED today for the detection gap alone) |
| T23 no-cd, existing behaviour | bare root | `git commit -m x` | allow + `bypass ".gitleaks.toml absent"` (proves the topology reproduces the old skip) |
| T24 relative | bare root | `cd .worktrees/wt && git commit -m x` | deny |
| T25 second member | clean repo A | `cd <A> && cd <wt> && git commit -m x`; `git -C <A> status && git -C <wt> commit -m x`; and the reverse order with the leaky one FIRST | deny in all three (a first-only or last-only resolver fails one) |
| T26 non-commit `-C` | leaky repo B | `git -C <clean> status; git commit -m x` | deny (fallback roots always unioned) |
| T27 undeterminable | bare root | `cd "$WT" && git commit -m x` | deny, reason contains `cannot determine` and the separate-`cd` repair |
| T27b | bare root | table loop: unquoted `cd $WT`, `cd "$(pwd)/wt"`, `` cd `pwd` ``, `cd -`, `cd ~someone`, `cd ~/wt`, glob `cd .worktrees/*` | each deny |
| T29 runner | bare root | `bash -c 'cd <wt> && git commit -m x'` | deny |
| T29b hidden commit | bare root | `CMD='cd <wt> && git commit -m x'; eval "$CMD"`; `bash -c "$SCRIPT"` | deny (runner operand carries an expansion) |
| T30 git-dir/work-tree | bare root | `GIT_WORK_TREE=<wt> git commit`, `git --work-tree=<wt> commit`, `git --git-dir=<g> commit` | deny with `cannot determine` (presence is treated as non-literal) |
| T31 lexer unavailable | bare root, PATH without perl (stub-path builder) | `cd <wt> && git commit -m x` | deny naming the cause (not allow) |
| T32 lexer error | bare root | `cd "<wt> && git commit -m x` (unbalanced quote) | deny |
| T33 library missing | bare root | any `git commit` with the lib renamed in a COPY of the hook dir | deny; reason contains the literal repair `git checkout -- .claude/hooks/lib` (so it cannot pass via "lexer unavailable"); a non-commit Bash call is untouched |
| T34 must-ALLOW control | bare root | `cd <clean-wt> && git commit -m x` (clean staged) | allow |
| T35 must-ALLOW non-canonical | bare root | `git -C <clean-wt> commit -m "$(cat <<'EOF'` newline `cd "$WT" && git commit` newline `EOF` newline `)"` (message text mentions a non-literal cd) | allow (quoted/heredoc data is not a target) |
| T36 sentinel | bare root | `cd "$(touch <sentinel>)" && git commit -m x` | deny AND the sentinel file does not exist (nothing executed); same for `eval`-shaped text |
| T37 literal missing dir | clean repo | `cd /nonexistent/dir && git commit -m x` | allow (clean staged), no false deny |
| T39 inherited env | bare root, `GIT_DIR` exported to a decoy | `cd <wt> && git commit -m x` | deny (resolver strips GIT_*) |
| T40 lexer contract | n/a | run the lexer on a fixed command; assert the exact leading frame bytes (`C`, ctx, argc, flags, arg, `OK`) and that the hook's resolved `LEXER` path is a readable file | pass; fails if `shell-argv.pl` changes its framing or moves |
| T41 loop does not end early | clean repo A, leaky B | `cd <A> && git -C <B> commit -m x` with A's scan returning a transient error with no report (gitleaks stub on A only) then B leaky | deny (a `scan_root` that `allow`s/exits ends the loop at A) |
| T42 separate-cd repair | process cwd bare root, payload `.cwd` = `<wt>` | `git commit -m x` | deny (the payload-`.cwd` fallback root is scanned) |
| T43 non-commit stays allowed | bare root | `git -C <wt> log --oneline`, `git --no-pager status`, `echo "git -C x commit"` | allow, no scan, no false deny |
| S-repair | bare root | the repairs the deny text recommends: literal absolute `cd /abs/wt && git commit`, `git -C /abs/wt commit`, `cd /abs/wt; git commit`; and the lazily-bound `WT=/abs/wt; cd "$WT" && git commit` | the first three are scanned (deny on the planted leak); the lazily-bound one is still denied; with a clean worktree the literal repairs ALLOW (repair must not reopen the skip and must not dead-end) |

Walker unit rows (source the lib, call `ctr_collect`, assert `CTR_TARGETS` / `CTR_BAD`): redirects (`cd /a 2>&1 && ...`, `cd /a &> /dev/null`), `$(...)` containing `cd`, a `#` comment mid-word, `builtin cd`, `cd -P -- /a`, `pushd /a`, repeated `-C`, `-c k=v`, `git commit -C HEAD` (the `-C` after `commit` is not a global option), quoted path with a space, `env -C /a git commit`, `builtin cd /a && command git commit`, `(cd /a && git commit)`, `eval "$CMD"` and `bash -c "$SCRIPT"` (operand carries an expansion -> bad), and the pre-filter token list (every form the walker handles matches `ctr_wants_lex`).

Commands for verification (run by `soleur:work`, not here): `bash .claude/hooks/git-commit-secret-scan.test.sh`, `bash plugins/soleur/test/boundary-prefix.test.sh`, `bash plugins/soleur/test/shell-argv-parity.test.sh`, `bash plugins/soleur/test/c4-count-parity.test.sh`, `shellcheck` on the touched `.sh` files, `bash .claude/hooks/hook-input-contract.test.sh`.

## Guard Contract

### Guard 1 - git-commit-secret-scan target resolution

**Property.** Every `git commit` the hook is shown (including `git <global options> commit`) is scanned against each repository its command text can target (and the cwd-derived roots), or is denied; it is never allowed unscanned because the target could not be determined.

**Assembly.** The property quantifies over: (1) DETECTION - the strict regex (line 113) plus the loose test; every commit shape flows through these two lines, and T22/T43 pin both directions; (2) the ways a target is named in command text (see Attack Surface Enumeration) - all flow through ONE chokepoint, the lexer's argv records walked by `ctr_collect`; (3) the root SET the scan loop iterates (`CTR_ROOTS` union the two fallback roots) - all flow through ONE loop, `scan_root`; (4) the exits between the commit match and the scan, classified below by position relative to the FIRST scan. Members drift (new global git options, new wrappers); the chokepoints do not. There is more than one chokepoint (detection, walker, loop) and the matrix targets each.

| Exit (position) | Allowed to skip? | Why |
|---|---|---|
| not a commit (strict and loose both fail, or lexer finds no commit record on a loose-only match) | yes | nothing to scan |
| gitleaks not installed (before any lexing) | yes | environment fault, existing, warn + row |
| probe unrunnable / timed out (runs BEFORE every undeterminable deny) | yes | environment fault, existing rows |
| library missing / lexer unavailable / `E` / truncated / non-literal target / runner operand with expansion | NO -> deny | cannot determine target |
| no roots (no target, bare/no work tree) | yes | nothing stageable; legacy bypass |
| a root without `.gitleaks.toml` | yes, that root only | existing policy per root |
| scan_rc != 0 with empty report (a root) | yes, that root only | existing transient policy; the loop continues |
| `-diff` re-scan failed (a root) | yes, that root only | existing, row emitted |

**Mutation matrix:**

| # | Mutation (applied to a COPY) | Expected |
|---|---|---|
| 1 | `ctr_collect` returns no targets and no bad (resolver dispatch made inert) | RED: T21, T24, T27, T27b, T29, T29b, T30 |
| 2 | Roots limited to the FIRST resolved target (stop at first member) | RED: T25 (leaky-second ordering) |
| 3 | Roots limited to the LAST resolved target | RED: T25 (leaky-first ordering) |
| 4 | Fallback roots dropped from the union when a target resolved | RED: T26, T42 |
| 5 | Undeterminable disposition flipped from deny to allow/skip | RED: T27, T27b, T29b, T30, T31, T32 |
| 6 | Undeterminable deny moved AFTER the legacy "no roots" bypass (ordering/reorder row) | RED: T27 (a bare root has no roots, so the bypass would fire first) and T31 |
| 7 | `scan_root` calls `allow` (ends the hook at the first clean root) | RED: T41 |
| 8 | Strict-only detection (loose test removed) | RED: T22, T30 (`--work-tree` form) |
| 9 | Loose test made unconditional on lexer confirmation | RED: T43 (`git -C <wt> log`, the echoed text) |
| 10 | `GIT_*` env strip removed from the resolver probes | RED: T39 |
| 11 | Walker treats the `-C` after `commit` (`commit -C HEAD`) as a global option | RED: walker unit row |
| 12 | Library sourced fail-soft (`|| true`) with no assertion | RED: T33 |
| 13 | `ctr_wants_lex` token list narrowed (drops `pushd` or `git -`) | RED: the pre-filter unit row and T22 |

**Harness rows:**

- H1 (edit the SUITE, must go RED): remove the planted leak from the worktree fixture -> T21 must flip to allow; if it stays deny, the arm is passing for the wrong reason.
- H2: the fixture-control assertion (plain gitleaks in the worktree exits non-zero) removed or inverted -> the suite must report FIXTURE BROKEN rather than pass.
- H3 (must-PASS, non-canonical): T34, T35, T37 and T43 differ from the canonical deny fixtures in a permitted way (clean content; quoted/heredoc data; non-commit git) - a guard that rejects everything reds them.
- H4: a stub gitleaks that always reports a finding must not let T27 pass for the wrong reason; assert the T27 deny reason contains `cannot determine`, not a finding location.

**Anchor.** No stored value is compared (no hash, floor or manifest row); the guard is a behavioural check. The one pinned external contract is `shell-argv.pl`'s record framing, guarded by T40 plus the existing `shell-argv-parity.test.sh`.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "must derive the repo root from the commit's target directory (a leading `cd <path>` or `git -C <path>` in tool_input.command) instead of the hook process cwd" [brief + issue #10609] | Proposed Solution; `.claude/hooks/lib/commit-target-roots.sh`; hook edit | mapped |
| 2 | "so it no longer skips the scan with \".gitleaks.toml absent\" when the session cwd is the bare repo root and the commit targets a worktree" [brief] | T21, T23 | mapped |
| 3 | "Add a fixture to the hook's existing test suite ... command `cd <worktree> && git commit ...`, planted fake secret in the staged index (synthesized shape only, built by concatenation so no contiguous token literal exists in source) must produce a deny" [brief] | T21 using `_mk_pem` | mapped |
| 4 | "Also fixture the `git -C <worktree> commit` form and a no-cd command (existing behaviour unchanged)" [brief] | T22, T23 (T22 needs the detection widening) | mapped |
| 5 | "Treat the command text as untrusted: resolve the target directory safely (no eval, no command substitution)" [brief] | lexer reuse; T36 sentinel | mapped |
| 6 | "fail toward scanning (never toward skipping) when the target cannot be resolved" [brief] | deny dispositions; T27, T29b, T31, T32, T33 | mapped |
| 7 | "PR body: \"Closes #10609\", plus a non-closing epic reference line consisting of the word Ref, a hash sign and the digits 10331" [brief] | Acceptance Criteria (PR body) | mapped |
| 8 | "Do not edit plugins/soleur/skills/work/SKILL.md (at its byte ceiling)" [brief] | AC diff-scope | mapped |
| 9 | "Technical forks are ruled by the soleur:engineering:cto agent, not the operator" [brief] | Decision Classes table | mapped |
| 10 | "Run soleur:ship and soleur:postmerge to completion; if the PR is BEHIND with auto-merge armed, wait for the merge queue" [brief] | pipeline stage; no plan item | mapped (downstream stage) |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `.claude/hooks/lib/commit-target-roots.sh` | asks 1, 5, 6 ("resolve the target directory safely") | asked |
| `.claude/hooks/git-commit-secret-scan.sh` edit | asks 1, 2 | asked |
| `.claude/hooks/git-commit-secret-scan.test.sh` fixtures | asks 3, 4 | asked |
| Union of all targets + always-included fallback roots (cwd root and payload `.cwd` root) | ask 6 ("fail toward scanning") | asked |
| Detection widening for `git <global options> commit` | ask 4 ("the `git -C <worktree> commit` form") | asked - the fixture cannot pass without it |
| `bash -c` / `eval` re-lex and runner-operand deny, `GIT_DIR=` / `--git-dir` / `--work-tree` deny | ask 5 ("untrusted") - the same defect class as the incident | inferred - justification: a leading-`cd`-only resolver is bypassed by the most natural rewrite of the same command (CTO ruling T8) |
| Library-missing deny | ask 6 ("never toward skipping") | inferred - justification: the library is the safety core; a corrupt checkout must not become a silent skip (CTO ruling T9) |
| Memoized `gitleaks_runnable` + ordering | ask 6 | inferred - justification: the undeterminable deny must precede the legacy bypass yet still honour environment-fault allows (CTO ruling T10) |
| `plugins/soleur/test/boundary-prefix.test.sh` pin update | ask 1 | inferred - justification: the line-113 exemption is positional; moving it reddens CI |
| `.claude/hooks/README.md` paragraph | ask 6 | inferred - justification: documents the repair path and the lexer coupling so the next reader is not misled |
| ADR-157 addendum | ask 6 | inferred - justification: plan Phase 2.10 makes the recorded architecture part of the change; ADR-157 otherwise says hooks never deny on parse trouble |
| T40 framing/path test | ask 5 | inferred - justification: the walker depends on `shell-argv.pl`'s record framing, which no other suite pins (CTO addition) |
| Presence-as-bad for `--git-dir`/`--work-tree`/`GIT_*` | ask 6 | inferred - justification: value parsing of gitdir shapes is the costlier and error-prone alternative; deny is the fail-toward-scanning disposition (review: DHH, simplicity, architecture) |

### Split Assessment

- Subsystems touched: 3 - `.claude`, `plugins/soleur` (one pin), `knowledge-base` (ADR addendum)
- Planned files: 7 | Estimated changed lines: about 480 (library ~170, hook refactor ~130 net, suite ~170, docs ~20)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

### Pre-merge (PR)

- [x] AC1: `bash .claude/hooks/git-commit-secret-scan.test.sh` exits 0 with 0 failed and 0 skipped (CI=true skip contract holds); the 20 pre-existing arms are unchanged and green.
- [x] AC2: T21, T22, T24, T25 (all three orderings), T26, T27, T27b, T29, T29b, T30, T31, T32, T33, T36, T39, T41, T42 deny; T23 allows with the legacy `.gitleaks.toml absent` row; T34, T35, T37, T43 and the clean-worktree S-repair forms allow.
- [x] AC3: The fixture control passes (plain gitleaks exits non-zero in the worktree fixture) and the suite prints no `FIXTURE BROKEN`.
- [x] AC4 (rows 1-13 and H1 executed and RED; H2-H4 covered by the suite's fixture control and the T27/T31 reason assertions, not separately mutated): All 13 mutation-matrix rows and H1-H4 are executed against COPIES, each recorded RED in the PR description (one line per mutant: row id and the arms that reddened); the live tree is not mutated.
- [x] AC5: T36 passes: the sentinel file is absent after the hook ran on `cd "$(touch <sentinel>)" && git commit`. `grep -nE '\beval\b|xargs' .claude/hooks/lib/commit-target-roots.sh` returns no code line (comments excluded).
- [x] AC6: `bash plugins/soleur/test/boundary-prefix.test.sh` is green (line-113 pin intact or updated in the same commit; the new lib and the loose test pass the census), `bash plugins/soleur/test/shell-argv-parity.test.sh` is green (lexer untouched), `bash plugins/soleur/test/c4-count-parity.test.sh` is green.
- [x] AC7: `shellcheck` is clean on the touched `.sh` files; `bash .claude/hooks/hook-input-contract.test.sh` is green; markdownlint is clean on the plan, tasks, README, ADR and decision-challenges files.
- [x] AC8: The synthesized secret appears in no source file as a contiguous token: `gitleaks detect --no-git` over the diff reports 0 findings (the CI-side scan of this PR must stay green).
- [ ] AC9: Diff-scope: the changed-file set is a subset of {the files in Files to Edit / Create, `knowledge-base/project/plans/2026-10-20-fix-secret-scan-hook-target-dir-plan.md`, `knowledge-base/project/specs/feat-one-shot-10609-secret-scan-target-dir/*`, `knowledge-base/INDEX.md` if regenerated}. `plugins/soleur/skills/work/SKILL.md` is NOT in the diff.
- [ ] AC10: PR body contains `Closes #10609` and a separate line consisting of the word `Ref`, a space, the hash sign and `10331` with no closing keyword adjacent; #10331 stays closed. The body also names #10696 (deferred add-then-commit gap) without a closing keyword.
- [x] AC11: Perf/P4: the no-token path adds no perl spawn (`ctr_wants_lex` false) - asserted by a PATH without perl still allowing a plain clean `git commit`.
- [x] AC12: The deny text contains each element of the "Deny text" paragraph (not-scanned statement, separate-`cd` repair, literal absolute path form with `git worktree list`, the named non-working forms, the root-naming finding variant) - asserted by substring in T27/T33/T26 reasons.

### Post-merge

- [ ] Run `soleur:postmerge`. Field check from the ledger in a later bare-root session: no new `bypass ".gitleaks.toml absent"` rows for commits whose command carried a `cd`/`-C` target; payload `.cwd` follows a prior separate `cd` call (the repair path); count `cannot determine` rows and file a follow-up issue only if the false-deny rate is material.

## Domain Review

**Domains relevant:** engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Rulings T1-T10 recorded in `decision-challenges.md` (resolver choice reversed once after the existing lexer was found; union scan; deny on non-literal target and on lexer unavailability; loud deny when the library is missing). Dissent: none.

### CPO sign-off (single-user incident threshold)

**Status:** reviewed - sign-off GIVEN (2026-10-20): proceed to implementation.
**Assessment:** `single-user incident` is the right threshold (a credential in public git history cannot be undone by reverting the commit; CI gitleaks narrows but does not close the window). A deny that names its repair beats an unscanned commit. Concerns carried into the plan: (1) the always-unioned fallback roots can false-deny, so the deny reason names the root that held the finding and the ledger false-deny rate is checked after landing, because repeated false denies teach operators to bypass the hook; (2) the S-repair scenario is a hard gate - the repair the deny message recommends must itself pass the hook; (3) a missing gitleaks still gives allow plus a bypass row (existing, out of scope).

### Plan-review panel (eng: DHH, Kieran, simplicity, architecture-strategist, spec-flow)

Findings applied (mechanical): detection regex gap (Kieran P0), `scan_root` early-exit and per-root state (Kieran P1), NUL-frame and bash 3.2 hardening, `--git-dir` mapping removed, `eval "$CMD"` hidden commit, deny-text repair path, ADR-157 addendum, lexer-ownership note, cuts (`~`, 8-cap, last-commit scoping). Surfaced as challenges: T12, T13 in `decision-challenges.md`.

### Compliance

gdpr-gate (trigger (b), declared threshold): no regulated-data path, no schema, no new vendor or transfer; no findings, no Critical. No UI surface (Product/UX NONE), no spend, no marketing or legal surface.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This plan declares `single-user incident`.
- Feed the lexer from a FILE when tracing (`--trace < cmd.txt`); pasting a command into a double-quoted argument runs its substitutions.
- A fixture PEM body that is not shaped like the existing `t5_` payloads may not trigger the `private-key` rule (observed in a scratch run); always keep the fixture control.
- `core.bare=true` in the shared config also reads `true` inside a linked worktree via `git config`, while `--is-bare-repository` is `false` there (ADR-173); the hook never reads `core.bare`, it relies on `rev-parse --show-toplevel` per candidate.
- The local gitleaks is 8.30.1 and CI pins 8.24.2; the matrix must hold on both (the suite's skip contract already handles an absent binary).
- `_run_stub` hardcodes `git commit -m x`; the new fixtures need the `_run_cmd` helper, and every new `mktemp` must register with the suite's `_TMP_DIRS` trap (lint-trap-tempfile-ownership).
- Under `set -euo pipefail` a bare `perl ... | read` pipeline can abort the hook non-zero and let the tool proceed; the lexer call is guarded and the `OK` terminator is the only success signal.
- Do not edit `plugins/soleur/skills/work/SKILL.md`.

## PR Body Reminder (for `soleur:ship`)

`Closes #10609`, plus a separate line: the word Ref, a space, the hash sign and 10331 (non-closing, epic stays closed). Mention #10696 as the deferred add-then-commit gap (no closing keyword). Include a `## Changelog` section (semver:patch).
