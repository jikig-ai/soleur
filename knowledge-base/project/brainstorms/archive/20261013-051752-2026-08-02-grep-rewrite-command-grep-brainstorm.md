# Brainstorm: rewrite `grep` → `command grep` via PreToolUse `updatedInput`

**Date:** 2026-08-02
**Issue:** #7165
**Branch:** `feat-7165-grep-rewrite-updatedinput`
**Sibling:** #7166 (memory backstop via systemd `StartTransientUnit`)
**Prior art:** `knowledge-base/project/learnings/2026-08-02-ps-named-it-2-1-220-so-a-grep-that-ate-the-box-read-as-a-claude-leak.md` (landed #7163); PR #7151 closed unmerged

## What We're Building

A PreToolUse hook that rewrites the `grep` token in top-level Bash-tool command
strings to `command grep`, bypassing the Claude Code shell shim that re-execs
`claude` with `argv[0]=ugrep`. No regex classification, no cost model, no
threshold — the pattern is never read.

## Why This Approach

#7151 tried three cost models and each was refuted by measurement. The final
refutation is structural: real cost is `class size × bound magnitude × literal
reachability against the specific input`, and a PreToolUse hook cannot observe
the third factor because the input is a file it has not read. Rewriting sidesteps
classification entirely.

Two facts make it viable: the shim is **not** `export -f`'d (so the dangerous call
can only originate in a top-level Bash-tool command string — exactly what the hook
sees, and the 54 hook scripts that call `grep` are structurally out of scope), and
PreToolUse supports `updatedInput`.

## Measurements taken this session

All probes hard-capped (`ulimit -v 2000000` + `timeout 25`) per the prior-art sharp
edge — the reproducer was never run uncapped. Synthetic fixture: 32 kB of seeded
random alphanumerics, plus a copy one directory down. Pattern
`[0-9]{0,80}5[0-9]{0,120}` (the literal-reachable row from the prior art).

### M1 — Recursion does not spare the blowup

| Invocation | Peak RSS | Wall |
|---|---|---|
| ugrep shim, single file | 1.67 GB | 23.4 s |
| ugrep shim, **recursive** | **1.67 GB** | 20.5 s |
| GNU grep, single file | 7.7 MB | 0.10 s |
| GNU grep, **recursive** | **7.6 MB** | 0.10 s |

Blowup is DFA-construction cost. The issue's proposed recursive carve-out would
have carved out a population that fails identically — leaving a live OOM path
while reading as protection. This is the same failure shape the prior art warns
about ("a guard that is worse than nothing, because it *reads* as protection").

### M2 — The shim injects more than the issue records

Read from `~/.claude/shell-snapshots/snapshot-bash-*.sh`:

```
-G --ignore-files --hidden -I \
  --exclude-dir=.git --exclude-dir=.svn --exclude-dir=.hg \
  --exclude-dir=.bzr --exclude-dir=.jj --exclude-dir=.sl
```

Six `--exclude-dir` values, not one. The shim also already routes to `command grep`
itself when any argument matches `-[Zz]*`, `--null`, `--null-data`, `---*`, `-@*`,
`-*-filter*`, `-*-pager*`, `-*-view*`, `-*-config*` — that population is already safe.

### M3 — "Replay the shim's flag set" is partly impossible, partly fatal

Against GNU grep 3.12:

| Shim flag | GNU grep | Disposition |
|---|---|---|
| `-G` | supported, but **`-G` + `-E` → `conflicting matchers specified`, rc=2** | **must NOT replay** — ugrep tolerates the combination, GNU grep hard-errors. Redundant anyway: BRE is GNU's default. |
| `-I` | supported | replay |
| `--exclude-dir=X` (×6) | supported, harmless when non-recursive | replay |
| `--hidden` | **rejected** | no-op vs GNU default (`-r` includes hidden) — drop |
| `--ignore-files` | **rejected** | no GNU equivalent — **the one true semantic delta** |

So the residual delta reduces to exactly one thing: recursive greps stop respecting
`.gitignore`. In a hydrated worktree that is 13,087 tracked files vs 101,073 on disk
(`node_modules` is 25 MB) — a noise cost on 3.8% of grep calls, not a latency or
memory cost (M1: GNU grep recursive = 7.6 MB / 0.10 s).

### M4 — Call-shape frequency, measured not assumed

6,082 Bash tool calls across the last 40 session transcripts:

| Form | Count | Share |
|---|---|---|
| any `grep` token | 3,061 | 50.5% |
| piped / stdin | 1,366 | 22.5% |
| command substitution `$(grep …)` | 351 | 5.8% |
| recursive `-r`/`-R` | 228 | 3.8% |
| `xargs grep` / `find -exec grep` | 12 | 0.2% |

Half of all Bash commands contain a grep token, so a false positive is expensive.
Command substitution being the second-largest form corroborates the prior art's
"`count=$(grep -c …)` is a first-class agent idiom".

### M5 — Must-not-touch hazards, measured

| Hazard | Count | Why it breaks |
|---|---|---|
| `git grep` | **179** | `git command grep` is not a git subcommand — **absent from the issue's list** |
| `pgrep` / `zgrep` / `ugrep` | 161 | substring match on `grep` |
| quoted `grep` as data (`echo "…grep…"`, `--body`, `-m`) | 228 | rewriting inside quotes corrupts the payload |
| already `command grep` | 31 | double-rewrite |
| `egrep` / `fgrep` | 7 | separate binaries, not shimmed |
| `xargs grep` / `find -exec grep` | 12 | `command` is a shell builtin — **`xargs command grep` cannot exec** |
| path-qualified `/usr/bin/grep` | 1 | already bypasses the function |
| `\grep` | 1 | **must rewrite** — backslash suppresses *alias*, not *function* lookup |

## Key Decisions

| # | Decision | Rationale |
|---|---|---|
| D1 | **Rewrite all shim-reaching invocations**, not just non-recursive | M1 — recursive fails identically; a carve-out protects 96% and mislabels the rest as safe |
| D2 | Replay `-I` + the six `--exclude-dir` values; **drop `-G`**; drop `--hidden` | M3 — `-G` is fatal with `-E`; `--hidden` is a no-op vs GNU default |
| D3 | Accept losing `--ignore-files`; **no hand-maintained denylist** | A static `node_modules`/`dist` denylist drifts from `.gitignore` and buys noise reduction only (M3: no latency/memory cost). Rejected as YAGNI. |
| D4 | **Rewrite only at command position in unquoted context** | M5 — 228 calls carry `grep` inside quoted data. `guardrails.sh` already has `strip_command_bodies` for exactly this quoted/heredoc-blanking problem |
| D5 | Ship now; **#7166 covers the residual** | Rewrite handles 6 of the 7 bypass forms; the cap catches what no lexical layer can see |
| D6 | Arming resets at newlines and `\|&`, not only spaced `&&`/`\|\|`/`;`/`\|` | Carried from the prior art's review findings |

### Defined behaviour for the seven bypass forms (acceptance #2)

The rewrite **never reads the pattern**, which dissolves the two forms the issue
calls unresolvable-in-any-design. That is true of *classification*, not of rewriting.

| # | Form | Behaviour | Note |
|---|---|---|---|
| 1 | `X=$(grep …)` | **rewritten** | `$(command grep …` |
| 2 | `` `grep …` `` | **rewritten** | |
| 3 | `(grep …)` subshell | **rewritten** | |
| 4 | `G=grep; $G …` | **untouched — documented residual** | command-name indirection is not statically resolvable; covered by #7166 |
| 5 | `P='…'; grep "$P"` | **rewritten** | pattern opacity is irrelevant to a rewrite |
| 6 | `eval "grep …"` | **untouched — documented residual** | rewriting inside quoted strings would corrupt the 228 data-carrying calls in M5; D4 wins over covering this form |
| 7 | `grep -f patternfile` | **rewritten** | the hook never needs to read `patternfile` |

## User-Brand Impact

- **Artifact:** the `grep`-rewrite PreToolUse hook in `.claude/hooks/`.
- **Vector:** a false positive silently corrupts a command's semantics (wrong file
  set searched, or a mangled `git grep` / quoted payload), so an agent acts on an
  answer that is wrong rather than absent; a false negative leaves the operator's
  desktop freezable by a one-line search, killing every concurrent session.
- **Threshold:** `single-user incident`.

## Open Questions

1. **Detection of already-safe invocations.** The shim's own bypass list (M2) means
   some `grep` calls never reach ugrep. Rewriting them anyway is harmless but
   changes file selection — should the hook mirror the shim's bypass list, or
   rewrite uniformly? Leaning uniform (simpler, and the flag replay makes the
   selection delta small).
2. **`updatedInput` observability.** A rewrite is invisible to the operator. Should
   the hook emit a `SOLEUR_*` marker / incident on every rewrite, or only sample?
   Volume would be ~3,000 per 6,000 Bash calls — too noisy to emit unconditionally.
3. **Mutation battery shape** (acceptance #5). Deleting the rewrite must turn the
   suite RED. Confirm the battery also covers *over*-rewriting (a mutation that
   rewrites `git grep` must also turn it RED), not only under-rewriting.

## Capability Gaps

None. Every mechanism this needs exists and was verified this session: the hook
layer (`.claude/hooks/guardrails.sh`, 372 lines, registered on `Bash` in
`.claude/settings.json`), the quoted/heredoc-blanking helper (`strip_command_bodies`
in `.claude/hooks/lib/incidents.sh`), and the hook test harness
(`.claude/hooks/guardrails.test.sh`).

## Domain Assessments

Not run. `wg-zero-agents-until-user-confirms` — findings were presented first and
the operator selected a tight scoping pass over a leader triad, on the basis that
this is an internal hook change with an already-strong measured evidence base.

## Session Errors

1. **Roadmap drift left unfixed, deliberately.** `roadmap-reconcile.sh validate`
   reports `STALE_STATUS|phase 4|roadmap=56o/179c|milestone=77o/192c`. Not corrected
   here: phase 4 is unrelated to this feature, and the script names its own
   remediation (`/soleur:trigger-cron cron/roadmap-review.manual-trigger`, which
   opens a reviewed PR). Folding an unrelated roadmap edit into this PR would be
   scope pollution.
