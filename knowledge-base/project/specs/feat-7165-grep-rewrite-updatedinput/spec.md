---
title: Rewrite grep to command grep via PreToolUse updatedInput
feature: feat-7165-grep-rewrite-updatedinput
date: 2026-08-02
status: draft
lane: cross-domain
brand_survival_threshold: single-user incident
branch: feat-7165-grep-rewrite-updatedinput
pr: 7167
brainstorm: knowledge-base/project/brainstorms/2026-08-02-grep-rewrite-command-grep-brainstorm.md
closes: [7165]
---

# Feature: Rewrite `grep` → `command grep` via PreToolUse `updatedInput`

**Brainstorm:** [2026-08-02-grep-rewrite-command-grep-brainstorm.md](../../brainstorms/2026-08-02-grep-rewrite-command-grep-brainstorm.md)
**Sibling:** #7166 (memory backstop — covers the residual forms this cannot see)
**Prior art:** `knowledge-base/project/learnings/2026-08-02-ps-named-it-2-1-220-so-a-grep-that-ate-the-box-read-as-a-claude-leak.md`

## Problem Statement

Claude Code's shell snapshot installs a bash **function** named `grep` that re-execs
the `claude` binary with `argv[0]=ugrep`. For patterns whose cost depends on literal
reachability against the subject, ugrep builds a DFA that consumed 9.5 GB RSS in 171 s
against a single 21 kB file on 2026-08-01, freezing a 31 GB desktop and killing six
sessions. `ps` renders the runaway as the claude version directory, so every prior
occurrence read as a Claude Code memory leak and was never root-caused.

PR #7151 attempted to *classify* dangerous regex shapes. Three cost models were each
refuted by measurement; the final refutation is structural — cost is
`class size × bound magnitude × literal reachability against the specific input`, and
a PreToolUse hook cannot observe the third factor because the input is a file it has
not read. #7151 was closed unmerged. **The operator's exposure is unchanged.**

## Goals

1. Route shim-reaching `grep` invocations to GNU grep, which runs the measured
   reproducer in 7.7 MB / 0.10 s versus ugrep's 1.67 GB / 23.4 s.
2. Do it without reading the pattern — no cost model, no threshold, no calibration.
3. Preserve file-selection semantics as far as GNU grep allows, and state the residual
   delta explicitly rather than leaving it implicit.
4. Introduce zero false positives across the measured call-shape population, where a
   grep token appears in 50.5% of all Bash tool calls.

## Non-Goals

- A fourth regex cost model. The prior art forecloses this explicitly.
- The memory backstop — that is #7166, and it is what covers the two residual forms
  below.
- Changing the 54 hook scripts that call `grep`. The shim is not `export -f`'d
  (`bash -c 'grep --version'` returns GNU grep 3.12), so they are structurally out of
  scope.
- Recovering `.gitignore` filtering via a hand-maintained `--exclude-dir` denylist
  (rejected as drift-prone; see D3).
- `ulimit -v` as a backstop — measured categorically incompatible with this toolchain.

## Functional Requirements

- **FR1:** A Bash tool payload containing a shim-reaching `grep` invocation is
  **rewritten** via `updatedInput`, not denied. The measured reproducer completes
  cheaply.
- **FR2:** The rewrite replaces the `grep` token with
  `command grep -I --exclude-dir=.git --exclude-dir=.svn --exclude-dir=.hg
  --exclude-dir=.bzr --exclude-dir=.jj --exclude-dir=.sl`.
- **FR3:** `-G` is **not** injected. GNU grep exits 2 with `conflicting matchers
  specified` when `-G` precedes `-E`/`-F`/`-P`, where ugrep tolerates it. BRE is GNU
  grep's default, so `-G` is redundant as well as fatal.
- **FR4:** `--hidden` and `--ignore-files` are not injected — GNU grep 3.12 rejects
  both. `--hidden` is a no-op against GNU's default (`-r` includes hidden files).
  Losing `--ignore-files` is the single accepted semantic delta: recursive greps no
  longer respect `.gitignore`.
- **FR5:** Rewriting applies **only at command position in unquoted context**.
  Tokens inside quoted strings and heredoc bodies are never rewritten.
- **FR6:** Each of the seven bypass forms has the defined behaviour in the table below,
  each with a fixture.
- **FR7:** Every must-not-touch form in the table below is left byte-identical, each
  with a fixture.
- **FR8:** *(rewritten 2026-08-02 — the original "arming" wording described the v1
  classifier's bug and does not transfer to a rewrite. It also contradicted AC3 below,
  which demanded byte-identity for the same fixture.)* Under the v2 prefix design the
  hook never parses the command, so there is no arming state and no command position:
  a multi-line payload is prefixed once and its body is byte-identical. Every `grep`
  in it — on any line, in any construct — is neutralized by name resolution at
  execution time.

### FR6 — the seven bypass forms

| # | Form | Behaviour |
|---|---|---|
| 1 | `X=$(grep …)` | rewritten |
| 2 | `` `grep …` `` | rewritten |
| 3 | `(grep …)` subshell | rewritten |
| 4 | `G=grep; $G …` | **untouched — documented residual**, covered by #7166 |
| 5 | `P='…'; grep "$P"` | rewritten (pattern opacity is irrelevant to a rewrite) |
| 6 | `eval "grep …"` | **untouched — documented residual**, covered by #7166 (FR5 wins) |
| 7 | `grep -f patternfile` | rewritten (the hook never reads `patternfile`) |

### FR7 — must-not-touch (counts from 6,082 measured Bash calls)

| Form | Count | Why |
|---|---|---|
| `git grep` | 179 | `git command grep` is not a git subcommand |
| `pgrep` / `zgrep` / `ugrep` | 161 | substring match on `grep` |
| quoted `grep` as data | 228 | rewriting corrupts the payload |
| already `command grep` | 31 | double-rewrite |
| `egrep` / `fgrep` | 7 | separate binaries, not shimmed |
| `xargs grep`, `find -exec grep` | 12 | `command` is a shell builtin and cannot be exec'd |
| `/usr/bin/grep` | 1 | already bypasses the function |

**Exception:** `\grep` (1 occurrence) **is** rewritten — backslash suppresses *alias*
expansion, not *function* lookup, so it still reaches the shim.

## Technical Requirements

- **TR1:** Emitted as `hookSpecificOutput.updatedInput` from a PreToolUse hook on the
  `Bash` matcher, registered in `.claude/settings.json`.
- **TR2:** *(superseded 2026-08-02.)* No quoting/heredoc analysis is performed at all.
  The v2 prefix design never inspects the command body, so neither
  `strip_command_bodies` nor any new masking helper is needed —
  `.claude/hooks/lib/incidents.sh` is not modified. A 5-agent panel reproduced four
  distinct quote-lexing corruption bugs in the v1 masking approach; the correct
  response was to delete the lexer, not to fix it.
- **TR3:** The hook file is committed mode `100755`, asserted against the **git index**
  (`git ls-files -s`), not the working tree. #7151's `memory-cap.sh` shipped `100644`
  and never executed once — 26 green assertions, a 7/7 mutation battery and a live
  kernel readback all sat on top of a hook that died at `exec` with `EXIT=126`, because
  the suite ran `bash "$HOOK"`, a path production never uses.
- **TR4:** Fail-open. A malformed payload must not deny — a PreToolUse hook that denies
  every command on a jq hiccup bricks the session. The disarm must **not** be silent:
  emit an incident.
- **TR5:** Do not reintroduce the confirmed `eval "$(… jq -r '@sh …')"` RCE. A
  non-string `.tool_input.command` makes `eval` execute array elements as a command.
  Force a scalar (`| if type=="string" then . else tojson end`) or drop `eval` for
  `mapfile -d ''`.
- **TR6:** Mutation battery — deleting the rewrite turns the suite RED, **and** a
  mutation that over-rewrites (e.g. touches `git grep`) also turns it RED. Under- and
  over-rewriting are separate failure directions and need separate kills.
- **TR7:** No probe may run the reproducer uncapped. Every measurement runs under
  `ulimit -v 2000000` + `timeout`.

## Acceptance Criteria

1. The measured reproducer, submitted as a Bash payload, is rewritten (not denied) and
   completes cheaply (target: single-digit MB, sub-second — GNU grep measured at
   7.7 MB / 0.10 s).
2. All seven bypass forms have a fixtured, defined behaviour (FR6).
3. All must-not-touch forms are fixtured and byte-identical (FR7), including `git grep`.
   *(The "and multi-line payloads (FR8)" clause is struck — it contradicted FR8; see
   the FR8 note. Under v2 every command body is byte-identical, so FR7 holds trivially
   and is verified by the AC5 corpus replay rather than by hand-written fixtures.)*
4. Recursive semantics: explicitly changed, not carved out — recursive greps are
   rewritten (they blow up identically, measured 1.67 GB), and the `--ignore-files`
   delta is fixtured and documented.
5. Mutation battery kills both under- and over-rewriting (TR6).
6. The hook's executable bit is asserted from the git index (TR3).

## Open Questions

1. Mirror the shim's own bypass list (`-[Zz]*`, `--null`, `---*`, `-@*`, …) or rewrite
   uniformly? Leaning uniform.
2. Rewrite observability — ~3,000 rewrites per 6,000 Bash calls is too noisy to emit
   unconditionally. Sample, or emit only on the residual forms?
