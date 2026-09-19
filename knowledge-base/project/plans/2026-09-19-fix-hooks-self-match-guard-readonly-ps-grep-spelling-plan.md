---
title: "fix(hooks): self-match guard also flags the read-only ps|grep poller spelling"
type: fix
date: 2026-09-19
slug: hooks-self-match-guard-readonly-ps-grep-spelling
branch: feat-one-shot-8330-self-match-readonly-spelling
issue: 8330
closes: 8330
priority: p2-medium
domain: engineering
brand_survival_threshold: none
lane: cross-domain
---

# fix(hooks): self-match guard also flags the read-only ps|grep poller spelling

## Enhancement Summary

**Deepened on:** 2026-09-19
**Sections enhanced:** Proposed Solution (steps 0–4), Guard Contract (Assembly gaps, M9/H1 rows, A6 positive control), Test Scenarios (D4, D11, D17–D19, A6, A12, A14), Files to Edit (README roster row), Acceptance Criteria (AC1–AC3, AC10, AC14), Technical Considerations, Research Reconciliation
**Research agents used:** architecture-strategist, security-sentinel, test-design-reviewer, pattern-recognition-specialist, code-quality-analyst, performance-oracle, git-history-analyzer, best-practices-researcher (procps/grep measurement), verify-the-negative sweep (8/8 claims confirmed)

### Key Improvements

1. Missing-lib degrade is now fail-OPEN (skip the read-only arm with a stderr WARN), not an identity shim that would over-detect in a degraded environment — the hook's own invariant wins over the sibling shim precedent (architecture P1).
2. Suite rows that could not go RED were fixed: H1 now deletes four rows (one deletion never breaches an `N − 3` floor); A14's inner pattern is quoted so M9 is actually caught; D11 discriminates on the `-f` reason's `BLOCKED:` prefix; A6 gains a positive control (same text without the heredoc → deny) so its allow is provably from `strip_heredocs` (test-design P0/P1, code-quality HIGH).
3. New rows pin behaviour the design left undecided: self-matching pipeline FIRST (D17), `fgrep` alias (D18), a `;` boundary inside a quoted string is an accepted false deny (D19), `egrep` alias of the safe bracket spelling (A14).
4. `timeout` follows the repo's `TO=()` array precedent (rc 127 on a missing binary is not "grep exited 2"); `command grep`; rc 0 = match, rc 1 = no match, anything else fail-open (pattern + security reviews).
5. Measured facts replace assertions: procps 4.0.7 flag table; grep rc 2 on `[unterminated`; `timeout` rc 124; hook floor 15.5 ms, +0.17 ms on the no-`ps` path, ~8.6 ms per `ps` pipeline; `ps -o args= -p <child>` lists 0 wrapper lines while `-u` lists 4.

### New Considerations Discovered

- The wrapper's real argv carries the `grep-rewrite.sh` prefix and the snapshot preamble, so a pattern matching only that text (`grep -c command`, `grep -c source`) self-matches in reality but not against the model — a false-allow gap, now in the header list.
- Only `guardrails.sh` calls `strip_heredocs` today; the twelve siblings call `strip_command_bodies`. The `while [[ =~ ]]` + `${rest#*…}` consumption loop and `${BASH_REMATCH[n]-}` are new idioms in this hook set, named as such.
- The README roster gains a row: adding a rule id makes the roster's "Rule IDs emitted" column wrong rather than merely incomplete.

## Overview

`.claude/hooks/pkill-self-match-guard.sh` denies the signal-sending spellings of the self-matching-scan class (`pkill -f` / `pgrep -f`). The read-only spelling of the same defect — an args-showing `ps` pipeline into `grep` / `grep -c` / `awk` whose regex matches the Bash tool wrapper's own argv — is unguarded, and a wait-for-quiet poller written that way counts itself forever while reporting "still waiting". This plan widens the hook to detect that spelling, reuses the existing remedy text plus the argv-slot `awk` recipe, adds rows for the read-only spellings to the hook's existing test suite, and verifies the detection against a repo file that documents the pattern so the guard does not fire on documentation about itself.

Work target is #8330 only. The sibling affected-test-gate work stays parked in its own worktree; the umbrella #7994 (guards firing on documentation about themselves) is not folded — this plan closes only the interaction it creates (see §Open Code-Review Overlap and §Research Reconciliation).

## Problem Statement / Motivation

The Bash tool executes every submitted command as a wrapper whose argv carries the whole command text. Measured in this session (`ps -o args= -p $$` from inside the tool):

```text
/usr/bin/bash -c source <snapshot>.sh 2>/dev/null || true && … && eval '<the whole command>' < /dev/null && pwd -P >| …
```

So any `ps -eo args | grep -c '<pat>'` used to poll for a sibling run also scans the poller's own wrapper. When `<pat>` matches the wrapper line the count never reaches zero and the loop reports "still waiting" — indistinguishable from a busy host. Two battery watchers built this way never fired across ~1h05m and ~25m (#8231, learning `2026-09-18-every-instrument-i-waited-on-was-counting-itself.md`). The hook's own header states the class generally ("a scan whose corpus includes the scanner's own text") and then implements two spellings of it — the guard-written-against-one-spelling shape the issue names.

Three facts measured on this host, each in an isolated Bash tool call, fix what the guard must decide (`zzqq-marker.sh` is a literal no process carries):

| Spelling, alone in the command | `ps -eo args \| …` count | Why |
|---|---|---|
| `grep -c 'zzqq-marker.sh'` (unescaped dot) | 3 | the regex `zzqq-marker.sh` matches its own literal text in the wrapper argv and in the grep process |
| `grep -c 'zzqq-marker\.sh'` (escaped dot) | 0 | the wrapper carries `zzqq-marker\.sh`; the regex needs a real `.` after `marker` |
| `awk '/zzqq-marker\.sh/' \| wc -l` (escaped) | 0 | same |
| `grep -c '[t]est-all\.sh'` with `scripts/test-all.sh` mentioned elsewhere in the same command | ≥ 1 | the bracket trick protects only the grep process's own argv; the wrapper carries the un-tricked literal from the other mention (the #8231 incident) |
| `awk '$1=="bash" && $2=="scripts/test-all.sh"' \| wc -l` with a real runner alive | 1 (the runner only) | argv-slot anchor: the wrapper's `$1` is `/usr/bin/bash`, `$2` is `-c` |

The decisive property is therefore not "the pattern appears elsewhere in the command" (the issue's proposed heuristic — it would ALLOW row 1, which self-matches) but **"the pattern, as the regex the stage will run, matches the wrapper line built from the command"**. That is computable inside the hook with one `grep` per stage.

## Proposed Solution

Add a second detection arm to `pkill-self-match-guard.sh`, after the existing `-f` arm, that **simulates the wrapper line through the pipeline**:

0. Cheap pre-trigger on the RAW command before any fork: `[[ "$CMD" =~ (^|[|;&(]|\$\()[[:space:]]*ps[[:space:]] ]] || exit 0`-shaped (a `ps` token at a command boundary anywhere in the text). Commands without one — the overwhelming majority — pay a single bash regex and nothing else.
1. `SCAN="$(strip_heredocs "$CMD")"` (from `.claude/hooks/lib/incidents.sh`, sourced fail-soft; if `strip_heredocs` is still undefined afterwards — `type strip_heredocs >/dev/null 2>&1 || …` — print `WARN: incidents.sh missing — read-only self-match arm skipped` to stderr and `exit 0`. Fail-OPEN, not an identity shim: a shim would make the arm over-detect exactly when the environment is degraded (a doc-writing heredoc would be denied), contradicting the header's "any parse failure exits 0" invariant; the `hook_tool_kind` precedent in this hook degrades toward passthrough too. The WARN is what keeps it from being the 2026-09-15 silent-no-fire class — under `set -u` an undefined function inside `$(…)` would otherwise leave `SCAN` empty and the arm dead without a trace). Heredoc BODIES are prose being written (a learning, a skill file, this hook's own header); quoted spans stay intact because the pattern lives in one. This is the #7994 interaction: the trigger scan must not see documentation.
2. One wrapper model, from the RAW command with newlines preserved: `MODEL="bash -c ${CMD}"`. It is the shape of a `nohup bash -c '…'` sibling watcher and a prefix-free model of the current wrapper — measured on 2026-09-19 with `ps -o args= -p $$` from inside the Bash tool, which begins `/usr/bin/bash -c source <snapshot>.sh … && eval '<cmd>' …`; the header names that command and date so a harness change can be re-measured rather than assumed. Extra wrapper text can only add matches, so the sibling shape is the conservative one for positive stages. Measured (`ps -o args= -p $$ | od -c` on a multi-line command): `ps` prints the wrapper's argv newlines verbatim, so a multi-line command is several `ps` lines and `^` anchors on every continuation line; `grep` over `$MODEL` reproduces that line-wise. Heredoc bodies stay IN the model: the wrapper carries them, which is exactly why a heredoc mentioning `scripts/test-all.sh` re-arms a bracket-tricked poller in the same command (D9). Two measured infidelities are accepted gaps, named in the header: the current wrapper embeds the command through `eval '…'`, so a single quote inside the command is rewritten as `'"'"'` in argv (a literal containing a quote is a fail-open arm), and the current wrapper's argv[0] is `/usr/bin/bash`, so a `-v '^bash -c'` stage filters the model but not the real wrapper (a false allow on a spelling nobody has typed; modelling argv[0] without the snapshot prefix would only move the gap).
3. For every **self-listing, args-showing `ps` stage** in `SCAN` — `ps` at a command boundary (`^`, `|`, `;`, `&`, `(`, `$(`, newline; never `^` alone, per the constitution) whose flags show the full command line (a BSD bare-letter token containing `a`, `x` or `u`; `-f`/`-F` bundled; or `-o`/`-O`/`--format[= ]` naming `args`, `cmd` or `command`; NOT `comm`-only, not bare `ps -e`) and that does NOT restrict to named pids (`-p`/`--pid`/`-q`/`--quick-pid` — the one `ps` that cannot list the wrapper; `-C bash` is not a pid restriction, the wrapper's comm is `bash`) and that is followed by `|` — walk the stages that follow, splitting on `|` and ending the pipeline at `;`, `&&`, `||`, `&`, `)`, newline or end of text. The walk ends, fail-open, at the first stage that is not `grep`/`egrep`/`fgrep`/`awk` (`wc`, `tee`, `head`, `cut`, … — no pass-through list; a stage that may rewrite the text is not simulated). **Trigger, stage walk and pattern extraction all read `SCAN`; only `MODEL` reads `CMD`.** `strip_heredocs` leaves quoted spans intact, so the pattern literal is present in `SCAN` where the walk is; there is no position mapping between the two strings (a mapping was the first draft and is a drift source — advisor consult, Step 4.5). Every optional `BASH_REMATCH` group is read as `${BASH_REMATCH[n]-}` so a non-participating group cannot abort the hook under `set -u` (a first in this hook set — the two existing `BASH_REMATCH` sites, `guardrails.sh` and `kb-domain-allowlist-guard.sh`, read groups that always participate). The stage walk is a `while [[ "$rest" =~ … ]]; do …; rest="${rest#*"${BASH_REMATCH[0]}"}"; done` consumption loop — also new here (siblings iterate `grep -o | while read`), named in the header as the idiom. For each matcher stage:
   - `grep` family: extract the first `'…'`, else first `"…"`, else first bare non-flag token (also after `-e`/`--regexp=`/`--`); flavour `-G` default, `-E` for `egrep`/`-E`/`--extended-regexp`, `-F` for `fgrep`/`-F`/`--fixed-strings`; pass through `-i`/`--ignore-case`, `-w`, `-x`; `-v`/`--invert-match` marks the stage as a filter; `-P` and `-f FILE` are fail-open; only the FIRST `-e` is tested (header note). A `|` inside a quoted pattern splits the stage at the wrong place and leaves an unterminated quote — that resolves to fail-open by the quote rule (A22), and the header says so.
   - `awk`: only the first `/…/` literal, always `-E`; awk's own `-v`/`-F`/`-f` are NOT grep flags and are never parsed as such (`awk -v n=1 '/x/'` is a matcher, `awk -F: '/x\.sh/'` is not fixed-string). An awk program with no `/…/` — the argv-slot recipe — has no regex and ends the walk as "wrapper filtered". No slot grammar beyond that: `$2 ~ /re/` is tested like any regex (an escaped-metacharacter regex cannot match the wrapper anyway, A21) and `/re/ && $1=="bash"` is a matcher (a `bash -c` sibling satisfies both — the D6 class).
   - **fail-open for this pipeline** (`continue` to the next `ps` pipeline — never `exit`) when the literal is unresolvable: contains `$`, a backtick, `'` or `"`, is empty, uses `-f FILE` or `-P`, or the simulation grep returns anything other than 0 (match) or 1 (no match) — 2 is an invalid regex (measured: `grep -q -e '[unterminated'` → 2), 124 is the `timeout` kill (measured), 127 is a missing binary. A later pipeline in the same command still gets its verdict (D10). A newline inside a quoted literal becomes two grep patterns, exactly as runtime grep would treat it — grep-faithful, not injection (header note).
   - test `"${TO[@]}" command grep -q <flavour> -e "$pat" <<<"$MODEL"` — HERESTRING, never a pipe (#6992/#7024, enforced by `grep-q-pipe-guard.test.sh`); `TO=(); command -v timeout >/dev/null 2>&1 && TO=(timeout -k 1 2)` is the repo's guarded-timeout form (`ship-net-issue-flow-gate.sh`, `git-commit-secret-scan.sh`, `memory-backstop.sh`), and `command grep` bypasses any `grep` shell function (learning 2026-08-02). Measured: GNU grep 3.12 backreference pathologies return in ~2 ms; nested counted repetition hits the 2 s kill with RSS growing ~140 MB/s — time-bounded, so `-P` stays fail-open and the bound is the timeout, not memory;
   - a non-`-v` stage that matches keeps the wrapper alive; a `-v` stage that matches, or a non-`-v` stage that does not match, **filters the wrapper** → this pipeline is safe, move to the next pipeline.
4. If the wrapper survived at least one matching stage in any pipeline → `emit`, then deny with the read-only paragraph and the recipes (below) in the same envelope shape as the `-f` arm: `{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: …}}` — `hookeventname-coverage.test.sh` counts `hookEventName >= permissionDecision` per file, so the second envelope must carry the event name. Otherwise exit 0 with no decision. `exit 0` with no envelope is reserved for hook-level failures (empty input, non-Bash tool, missing `jq`); per-pipeline parse failures `continue`. **Arm order and single envelope:** the `-f` arm runs first and, on a hit, prints its envelope and `exit 0`s exactly as today — the read-only arm is never reached, so a command carrying both spellings yields exactly one JSON object (the `-f` reason) and no read-only ledger line (D11, M11).

Why the `-v` honouring is correct and not a loophole: a `-v` stage is simulated like any other — it filters the wrapper only when its regex actually matches the model — and because the wrapper carries every literal the command carries, the everyday `grep -v grep` matches it (and every sibling `bash -c` watcher carrying the same text) while leaving a real `bash scripts/test-all.sh` runner untouched. `ps -ef | grep -E '<substring>' | grep -v grep` — the liveness check `plugins/soleur/skills/work/SKILL.md` prescribes under "Relaunching a long-running background bash before verifying it died" — therefore stays allowed and needs no rewrite.

Two independent prototypes of steps 2–4 (a ~40-line bash stage walk with `[[ =~ ]]`/`BASH_REMATCH`, and spec-flow's Python re-implementation driving ~70 boundary inputs through real `grep`) agreed with the expected verdicts on the original rows; the later rows and the awk-flag, `-p`, terminator and fail-open-per-pipeline rules came from the boundary inputs those prototypes got wrong or left ambiguous, and plan-review then cut a second wrapper model, a continuation join, a pass-through stage list and an awk slot grammar that bought no listed property. The implementer writes the production version against the full row set first (RED), not from either prototype.

**Remedy text** (the read-only arm's reason; the `-f` arm's text is unchanged). Mechanism + remedy only — the #8231 anecdote and the measured counts live in the header, not in a reason an agent reads twenty times a week:

```text
BLOCKED: `ps … | <stage> '<pat>'` is self-matching here. The Bash tool runs your command as
`bash -c '<the whole command>'`, so the process list carries a line containing your pattern —
the wrapper that issued it, and any sibling watcher spawned the same way. `<pat>` matches that
line (checked against `bash -c <your command>`), so a count never reaches zero and a
wait-for-quiet loop reports "still waiting" forever.

The `[t]` bracket trick protects only the grep process's own argv; it does nothing when the
literal appears anywhere else in the same command (an echo, a comment, the runner you launched).

For a one-off look at the box:
  ps … | grep <pat> | grep -v grep     # the wrapper carries "grep" by construction, so it drops out
  pgrep -a <name>                      # without -f, matches the process NAME only

For a wait-for-quiet count:
  source plugins/soleur/scripts/lib/proc.sh; list_runs <pattern>
                            # ownership via /proc/<pid>/cwd; excludes self + ancestry
  n=$(ps -eo args | awk '$1=="bash" && $2=="scripts/test-all.sh"' | wc -l)
                            # argv-SLOT anchor — match the EXACT argv you launched
                            # (`/usr/bin/bash …`, `bash ./scripts/…` are different slots)
  cmd & pid=$!; kill -0 "$pid"    # a captured PID names the process exactly
```

The recipe block sits inside the hook's double-quoted `reason="…"`, so `$1`, `$2`, `$!`, `$pid` and the inner `"` are written `\$1`, `\$2`, `\$!`, `\"\$pid\"` — the shape the existing `cmd & pid=\$!` line already uses (AC5 asserts the rendered text).

**Telemetry** (Phase 2): the read-only arm calls `emit_incident` (fail-soft `emit()` wrapper, the `background-poll-prefer-monitor.sh` precedent) with the hook-local rule id `pkill-self-match-guard-readonly`, so the weekly aggregator can count how often the new arm fires. The `-f` arm is left exactly as it is — adding a ledger write there is a behaviour change on an arm this plan promises not to touch (P6) and is outside #8330. The suite already sources `lib/test-incident-sandbox.sh`, so ledger writes land in the sandbox.

## Research Reconciliation — Spec vs. Codebase

| Issue / spec claim | Reality (verified) | Plan response |
|---|---|---|
| "flag a pipeline whose pattern **also appears elsewhere** in the same submitted command" | Measured: `ps -eo args \| grep -c 'zzqq-marker.sh'` alone returns 3 — it self-matches with NO other mention, because an unescaped regex matches its own literal. The hook's own header records that the same "appears elsewhere" heuristic missed the literal pkill incident. | Replace the heuristic with the exact property: the stage's regex matches the model wrapper line `bash -c <cmd>`. Guard Contract row M2 pins this. |
| `ps -eo args \| grep -c '[t]est-all\.sh'` "counts itself" | True only when the un-tricked literal appears elsewhere in the command (it did in #8231: the runner was launched in the same command). Alone it returns 0 (measured). | Deny the incident shape (literal elsewhere); allow the lone bracket-tricked spelling — it cannot self-match. |
| "the same remedy text plus the argv-slot recipe" | Remedy text exists in the hook; the argv-slot recipe exists in the learning and in `review/SKILL.md`, not in the hook. | Append the recipe to the reason; keep the `-f` arm's text byte-identical. |
| "Its existing test suite already has rows for the signal-sending spellings" | `.claude/hooks/pkill-self-match-guard.test.sh`: 14 verdicts, `MIN_ASSERTIONS=11`, append-only VERDICTS ledger, positive control. Baseline run: `=== 14 verdicts, 0 failed ===`. | Add deny/allow rows for the read-only spellings; raise the floor to `new_total - 3`. |
| "verify the detection against a repo file that documents it" | Three sites document the spelling: `knowledge-base/project/learnings/2026-09-18-every-instrument-i-waited-on-was-counting-itself.md` §"The instruments that were counting themselves", `plugins/soleur/skills/review/SKILL.md` ("A process count that greps its own pattern can never reach zero…"), `plugins/soleur/skills/work/SKILL.md` ("Relaunching a long-running background bash…"). None is an executed poller; `scripts/lib/test-contention.sh` carries only a comment. | Suite row A6 feeds an inline synthetic fixture with the same shape as the learning's paragraph (prose + fenced `ps -eo args \| grep -c '[t]est-all\.sh'` + a `scripts/test-all.sh` mention) through the hook as a heredoc write → allow, so a doc edit cannot break a hook test. The repo files themselves are checked once in Phase 3 (the `review/SKILL.md` bullet, and the learning section with its one signal-spelling line filtered out — that line trips the retained `-f` arm) and the allow is recorded in the PR body (AC4). Row A7 greps docs for the shape → allow. `review/SKILL.md`'s "is unguarded (#8330)" clause is updated; the learning is a point-in-time record and is left as-is. |
| Issue's proposal names `grep` / `grep -c` / `awk` | `ps` flags matter too: `ps -eo comm` shows names only (no self-match, like `pgrep` without `-f`). `egrep`/`fgrep` are the same stage. `-v` stages filter the wrapper. | Args-showing predicate on the `ps` stage; `-v` honoured; `egrep`/`fgrep` covered; awk argv-slot form allowed. |
| The hook reads raw `$CMD` (#7994 row for this hook) | Confirmed; a heredoc writing this hook's own file trips the `-f` arm today. `strip_heredocs` exists in `lib/incidents.sh` for exactly this; today only `guardrails.sh` calls it (the twelve other siblings call `strip_command_bodies`, which also blanks quotes and would blank the pattern). | The NEW arm scans `strip_heredocs "$CMD"`. The `-f` arm keeps raw `$CMD` — routing it through `strip_heredocs` would open a `bash <<'EOF' … pkill -f … EOF` bypass, and that trade is #7994's call, not this plan's. |

## Research Insights

### Premise Validation (Phase 0.6)

- #8330 is OPEN, `closedByPullRequestsReferences: []`, labels `priority/p2-medium type/bug domain/engineering meta/machinery`. Premise holds.
- #7994 (guards fire on docs about themselves) OPEN — umbrella; its row for this hook is acknowledged, not folded. #8231 OPEN (the incident's parent PR-review issue). #7525 CLOSED by PR #7531 — `plugins/soleur/scripts/lib/proc.sh` (`list_runs` / `kill_mine`) exists and is the sanctioned replacement the remedy cites. #8270 MERGED.
- `.claude/hooks/pkill-self-match-guard.sh` and `.test.sh` exist on `origin/main` (`git show origin/main:…` succeeds); the worktree contains `origin/main` (`git merge-base --is-ancestor` true).
- ADR corpus grep for `self-match|pkill` under `knowledge-base/engineering/architecture/decisions/`: zero hits. ADR-162 (exactly one PreToolUse rewriter) is untouched — this hook is a deny hook. ADR-157 (hook-input contract) lists 20 migrated Bash hooks; this hook is not among them today and this plan does not migrate it (out of scope; no rule is violated by leaving it).
- Wrapper shape re-measured from inside the Bash tool (see §Problem Statement) — `hr-verify-repo-capability-claim-before-assert`.

### Property List (Phase 0.6b)

- **P1** — A submitted Bash command containing an args-showing `ps` pipeline whose `grep`/`egrep`/`fgrep`/`awk` regex stage(s) match the command's own `bash -c` wrapper line, and survive every `-v` stage, is denied before execution with remedy text naming the argv-slot recipe and `proc.sh`.
- **P2** — A command whose ps-pipeline regex cannot match the wrapper (bracket trick with no other mention, escaped metacharacter with no other mention, argv-slot `awk`, `^bash scripts/…` anchoring without `.*`, a `-v` filter stage) is allowed — the guard stays a redirect, not a wall.
- **P3** — A command that merely documents the spelling (a heredoc writing a learning/skill file; a `grep -rn` over docs) is allowed.
- **P4** — Every parse failure (variable pattern, `-f FILE`, invalid regex, timeout, missing lib function) exits 0 with no decision.
- **P5** — The suite's append-only ledger gains deny and allow rows for the read-only spellings; the assertion floor rises so deleting a row breaches it.
- **P6** — The `-f` arm's behaviour and reason text are unchanged (the existing 14 verdicts stay green).
- **P7** — Each deny is countable after the fact (incident ledger), so the guard's value is measurable.

### Cut List (Phase 0.6b)

- "pattern also appears elsewhere in the same submitted command" (issue's proposed detector) → buys P1 only partially (misses the unescaped-alone self-match, measured) → replaced by the wrapper-line simulation, which buys P1 and P2 exactly. Not an additional mechanism; a substitution.
- A `SOLEUR_*` escape-hatch env var for the new arm → buys nothing P2/P4 do not already buy (the fail-open arms and the sanctioned spellings are the hatches; the `-f` arm is deliberately hatchless today) → cut.
- A README roster row for this hook → the hook is absent from `.claude/hooks/README.md` today (pre-existing; no test asserts roster completeness — `hookeventname-coverage.test.sh` does not name it) → out of scope; noted for #7994's README pass.
- Routing the existing `-f` arm through `strip_heredocs` (#7994's row) → would fold a `bash <<EOF` bypass trade-off that belongs to #7994 → cut; acknowledged in §Open Code-Review Overlap.
- Cut at plan-review (DHH + code-simplicity fired on the same scope): a second wrapper model (`/usr/bin/bash -c …`) for `-v` stages → bought only a `-v '^bash -c'` spelling nobody has typed and was not the real line either (the snapshot prefix) → header gap instead; a `\`-newline continuation join → bought one prototype-invented row → header gap; a pass-through stage list (`tee`/`head`/`cut`…) → over-approximated stages that rewrite text → the walk ends fail-open at any non-matcher; an awk `$N ~ /re/` slot grammar → an escaped regex cannot match the wrapper anyway; a `sudo`/`command`/`/path/` prefix set on the `ps` boundary → header gap; a second rule id on the `-f` arm → P6 says that arm is unchanged.

### Value-Proposition Measurement (Phase 0.6c)

Not a cost/performance saving — a correctness guard. Baseline: the two #8231 watchers cost ~1h05m + ~25m of wall clock and two operator "check now" turns before the instrument was suspected. After: the deny fires at submit time. Measurement channel post-merge: `INCIDENTS_REPO_ROOT`-aggregated `rule_id == "pkill-self-match-guard-readonly"` counts in `scripts/rule-metrics-aggregate.sh` (Phase 3).

### Relevant files (verified)

- `.claude/hooks/pkill-self-match-guard.sh` — `-f` arm trigger: `grep -qE "\b(pkill|pgrep)\b[^|;&]*[[:space:]]-[a-zA-Z]*f" <<<"$CMD"`; deny envelope `hookSpecificOutput.permissionDecision: deny`; sources `lib/hook-tool-kind.sh` fail-soft with a stderr WARN — the precedent for sourcing `lib/incidents.sh` the same way.
- `.claude/hooks/pkill-self-match-guard.test.sh` — `run_case <name> <cmd> <deny|allow>` feeds `{tool_name:"Bash",tool_input:{command}}` via jq; `VERDICTS` ledger; `MIN_ASSERTIONS=11`; positive control that appends a deliberate FAIL and retracts it; Devin `exec` wire-name row.
- `.claude/hooks/lib/incidents.sh` — `strip_heredocs` (heredoc bodies only; quotes preserved; fail-toward-firing on perl failure), `strip_command_bodies` (also blanks quotes — NOT usable here, the pattern lives in a quote), `emit_incident <rule-id> <deny|bypass> <summary> <cmd>` writing `$INCIDENTS_REPO_ROOT/.claude/.rule-incidents.jsonl` (probed: one JSON line with `rule_id`, `event_type`, `command_snippet`).
- `.claude/hooks/background-poll-prefer-monitor.sh` — `emit() { command -v emit_incident >/dev/null 2>&1 && emit_incident "$@" || true; }` wrapper precedent; also confirms no overlap: it fires only on `run_in_background: true` + remote-read tokens.
- `.claude/hooks/guardrails.sh` — `[[ "$CMD" =~ … ]]` + `BASH_REMATCH` verb extraction precedent.
- `.claude/hooks/pre-merge-auto-close-scan.sh` — precedent for iterating over multiple matches in one command (`while IFS= read -r` over `grep -o`).
- `.claude/hooks/grep-rewrite.sh` — prepends a `grep(){ … command grep … };` prefix to every Bash command carrying `grep`; the runtime wrapper therefore contains that prefix too. It only adds text, so the model line under-approximates the wrapper in a direction that cannot create a false deny.
- `.claude/settings.json` — hook registered under the `Bash` matcher as `"$CLAUDE_PROJECT_DIR"/.claude/hooks/pkill-self-match-guard.sh`; no registration change needed.
- `scripts/test-all.sh` — `SUITE_GLOBS` includes `'.claude/hooks/*.test.sh'`; `want_scripts()` ⇒ the suite runs under `TEST_GROUP=scripts` (CI job `test-scripts`) and `all`. Single suite: `bash .claude/hooks/pkill-self-match-guard.test.sh`.
- `plugins/soleur/scripts/lib/proc.sh` — `list_runs <pattern>` (dry-run enumeration, `<pid>\t<classification>\t<cwd>`), `kill_mine <pattern> [signal]`; ownership via `/proc/<pid>/cwd`, ancestor-chain and same-pgroup exclusion.
- Doc sites of the spelling: learning `2026-09-18-every-instrument-i-waited-on-was-counting-itself.md` §"The instruments that were counting themselves"; `plugins/soleur/skills/review/SKILL.md` bullet "A process count that greps its own pattern can never reach zero"; `plugins/soleur/skills/work/SKILL.md` bullets "A Monitor script must detect completion from rc/marker FILES, never `pgrep -f`" and "Relaunching a long-running background bash before verifying it died".

### Institutional learnings applied

- `2026-09-18-every-instrument-i-waited-on-was-counting-itself.md` — the incident; the argv-slot recipe; "review the matcher against the GRAMMAR, not the one spelling it was written for".
- `best-practices/2026-06-08-command-string-scanning-hook-must-skip-glob-metachar-tokens.md` — command-string hooks cannot tell written from mentioned paths; here solved structurally (`strip_heredocs` + simulate the regex rather than grep for tokens).
- `2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md` and `2026-08-13-every-guard-i-shipped-was-satisfiable-by-a-guard-that-asserts-nothing.md` — the mutation matrix is written from the design before the code; harness rows included; must-PASS rows are non-canonical.
- `2026-07-20-adding-a-second-copy-of-a-guarded-literal-disarms-the-first.md` — the suite must exercise each spelling as a separate row; detecting one must not be what makes the other pass.
- `2026-07-22-a-drift-guard-pr-fails-open-in-the-guard-not-the-guarded-code.md` — a guard's bugs fail open; the fail-open arms (P4) each get an explicit allow row so a future tightening is a deliberate change.
- `2026-09-15-devin-dual-hook-registries-dead-matchers-fires-then-noops.md` — three silent-no-fire layers; the Devin `exec` wire-name row is mirrored for the new arm.
- `2026-03-28-pretooluse-hook-guard-ordering-matters.md` — the new arm runs AFTER the `-f` arm's early `exit 0`? No: the `-f` arm exits 0 when no `-f` use is found, which would skip the new arm. Phase 1 restructures the control flow so the `-f` arm's negative result falls through to the read-only arm (see Files to Edit).
- `2026-08-02-ps-named-it-2-1-220-so-a-grep-that-ate-the-box-read-as-a-claude-leak.md` — `grep` in the Bash tool is a shell function re-exec'ing a shim; the grep PROCESS line may not read `grep`. Irrelevant to the wrapper line (which is what self-matches), noted so nobody "fixes" the model to include the grep process.
- `2026-05-15-plan-ac-verification-commands-awk-self-match-and-marker-conjunction.md` — the doc-fixture extraction in row A6 uses the flag-based awk form with a distinct end anchor and a non-vacuity control.

### Deepen-pass measured facts (2026-09-19, this host)

- **procps-ng 4.0.7 `ps` flags that print the full argv** (measured with a marker present only in the current command): `-f`, `-F`, `-ef`, `-e -o args|cmd|command`, `-O args`, `--forest -o args`, BSD `aux`/`ax`/`x`; **name-only**: bare `-e`/`-A`, `-e -o comm`, `-l`. `ps -o args= -p <child-pid>` lists the child only (0 wrapper lines); the same probe with `-u $(id -u)` lists 4 lines carrying the marker — so `-p`/`--pid`/`-q` is the only restriction that cannot show the wrapper (`-u`, `-t`, `-s`, `-C bash` all can; `-p $$` trivially does, since `$$` IS the wrapper).
- **GNU grep 3.12:** `grep -q -e '[unterminated'` → rc 2; several `-e`/`--regexp=` are OR'd; `-e "-foo"` treats a leading dash as a literal; `-P` works with `-q`. **`timeout`:** rc 124 on kill; rc 127 when the binary is missing (hence the `TO=()` guard).
- **Wrapper argv:** `/usr/bin/bash -c source <snapshot>.sh … && eval '<cmd>' < /dev/null && pwd -P >| …`; newlines in the command are printed verbatim by `ps` (one `ps` line per command line); single quotes are rewritten `'"'"'`; the `grep-rewrite.sh` `grep(){ … }` prefix is part of the argv text. All PreToolUse hooks receive the ORIGINAL `tool_input` — a sibling deny wins over `grep-rewrite`'s `updatedInput` (measured, recorded in `grep-rewrite.sh`), so this hook's `$CMD` is never the rewritten command regardless of matcher order.
- **Hot path:** current hook ≈ 15.5 ms/call; 21 Bash-matcher hooks ≈ 836 ms serial; pre-trigger 0.17 ms (2 kB) / 3.4 ms (135 kB); `strip_heredocs` 4.05 ms (2 kB) / 12.6 ms (100 kB); guarded `timeout grep` 3.25 ms per stage.
- **Existing suite:** 14 verdicts = 6 `-f` deny rows + Devin `exec` row + 5 allow rows + 2 positive-control rows; no test asserts on this hook's reason text; the hook appears in neither `hookeventname-coverage.test.sh` nor the README roster; `devin-dispositions.tsv` binds it by kind (the `exec` row covers the new arm). `command grep -rn -F 'ps -eo args'` over `*.sh`/`*.yml` → 0 executable hits (the ambient `grep` function drops `--include`; `command grep` is required for an accurate sweep).
- **Citations:** all 14 issue/PR references verified live (git-history-analyzer); the hook was introduced in PR #8214 (#8205); the `~1h05m` / `~25m` watcher durations come from the #8330 issue body, not the learning file.

### CLAUDE.md / constitution conventions applied

- Never anchor guardrail patterns to `^` alone; match at command boundaries (`(^|&&|\|\||;)` family) — the `ps` stage boundary set includes `|`, `(`, `$(` and newline.
- Herestring into `grep -q`, never a pipe (`grep-q-pipe-guard.test.sh`).
- Hook fail-open invariant preserved; every new early return is `exit 0` with no envelope.
- Comments cite symbol anchors, not line numbers.
- Test runner: hook suites are plain `bash <file>`; the `.test.sh` convention (no bats).

## Open Code-Review Overlap

Queried `gh issue list --label code-review --state open --limit 200` (65 issues) for `.claude/hooks/pkill-self-match-guard.sh`, `.claude/hooks/pkill-self-match-guard.test.sh`, `pkill-self-match-guard`, `hooks/README.md`: **None** matched.

Non-label overlap, disposition recorded: **#7994** (label `type/bug`, not `code-review`) lists this hook's raw-`$CMD` scan. **Acknowledge** — the new arm scans `strip_heredocs "$CMD"` (so it never inherits the #7994 defect), but the existing `-f` arm is left on raw `$CMD` because the fix #7994 proposes (`$SCAN` for the trigger) opens a `bash <<'EOF' … pkill -f … EOF` bypass that #7994 must weigh across all nine hooks. A comment is left on #7994 at ship time noting the new arm's posture (one `gh issue comment`, no label changes).

## Technical Considerations

- **Architecture:** one hook, one suite, one skill-doc clause, one README roster row. No new files, no new lib, no settings change, no ADR (no new boundary or substrate). `lib/incidents.sh` is sourced fail-soft; if it is absent the read-only arm is skipped with a stderr WARN and `emit` is a no-op — fail-open, never a silent dead arm. No ADR-157 obligation is created: `hook-input-contract.test.sh` discovers hooks by their sourcing of `lib/hook-input.sh`, which this hook does not do; the repo-wide `eval` ban is satisfied (`-e "$pat"`, no eval). Inline is right — no second consumer exists for a stage-walker lib.
- **Control flow:** today the hook `exit 0`s when no `-f` use is found. The read-only arm must run on that path too, so the `-f` check becomes `if …; then <existing reason + envelope>; exit 0; fi` followed by the read-only arm — the `-f` arm keeps its own early exit, which is what guarantees one envelope per call (D11). Do NOT restructure into accumulate-then-emit. The header's opening summary ("when <pat> also appears ELSEWHERE") already contradicts its own later paragraphs and is rewritten; the reason STRING is what stays byte-identical. The `-f` deny text stays byte-identical (`diff` against `origin/main` of the reason string is an AC).
- **Performance (measured, N=50 loop timing):** the current hook costs ≈ 15.5 ms per call (bash startup + lib source + 2× `jq` + one `grep -qE`) inside a ≈ 836 ms serial budget across the 21 Bash-matcher hooks. Step 0's raw-command pre-trigger costs 0.17 ms on a 2 kB command and 3.4 ms on a 135 kB heredoc (linear; cheaper than the existing `grep -qE` herestring trigger at 7 ms on the same input), so commands without a `ps` token pay nothing measurable. A command WITH a `ps` pipeline pays `strip_heredocs` (perl, 4.05 ms at 2 kB, 12.6 ms at 100 kB) plus 3.25 ms per matcher stage (`timeout` doubles the bare 1.6 ms grep — kept as insurance) — ≈ 8.6 ms per pipeline. The honest claim is "no measurable change on commands without a `ps` token", not "no change".
- **Security:** the hook executes `grep` with an attacker-neutral but agent-typed pattern as `-e "$pat"` (never `eval`, never as a command). A pathological BRE/ERE is bounded by `timeout 2` and fails open. No pattern is written anywhere except the incident ledger's 1024-byte `command_snippet`, which already holds full commands today.
- **NFR impact:** none of the `nfr-register.md` runtime NFRs (this is operator-local tooling); the relevant property is the fail-open latency bound above.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing on the product — this hook runs only inside the operator's Claude Code session on this repo. The failure modes are an over-broad deny that blocks a legitimate `ps | grep` diagnostic (visible, self-explaining reason text) or a silent allow (today's state).
- **If this leaks, the user's [data / workflow / money] is exposed via:** no user data flows through the hook; the only write is the operator-local incident ledger, which already stores command snippets.
- **Brand-survival threshold:** `none`

## Observability

```yaml
liveness_signal:
  what: ".claude/hooks/pkill-self-match-guard.test.sh verdict line (=== N verdicts, 0 failed ===) with N >= the raised floor"
  cadence: "every PR (CI job test-scripts via scripts/test-all.sh SUITE_GLOBS '.claude/hooks/*.test.sh') and every local battery run"
  alert_target: "red required check on the PR; local: non-zero exit of the suite"
  configured_in: "scripts/test-all.sh SUITE_GLOBS; .github/workflows/ci.yml test-scripts job"
error_reporting:
  destination: ".claude/.rule-incidents.jsonl via emit_incident (rule id pkill-self-match-guard-readonly), aggregated by scripts/rule-metrics-aggregate.sh"
  fail_loud: "no — every per-pipeline parse failure continues fail-open by the hook's documented contract; the suite's allow rows for each fail-open arm are the counterweight, and a missing lib prints a WARN line to stderr and installs an identity shim, mirroring the existing hook-tool-kind degrade message"
failure_modes:
  - mode: "read-only arm never fires (dispatch regressed or exits early)"
    detection: "suite deny rows D1-D19 go FAIL; the ledger floor does not cover this, the rows do"
    alert_route: "CI red on the PR"
  - mode: "false deny on documentation about the spelling (#7994 class)"
    detection: "suite rows A6 (doc-shaped heredoc) and A7 (grep over docs) go FAIL; Phase 3's one-off run against the two repo docs is recorded in the PR body"
    alert_route: "CI red on the PR; at runtime the deny reason names the hook so the operator can see which guard fired"
  - mode: "false deny on a sanctioned spelling (argv-slot awk, grep -v grep, ^bash scripts/… anchor)"
    detection: "suite rows A2, A4, A5, A18, A19, A20 go FAIL"
    alert_route: "CI red on the PR"
  - mode: "pathological pattern stalls the hook"
    detection: "guarded `timeout -k 1 2` around the simulation grep (rc 124 → fail-open continue); suite row A13 pins the invalid-regex arm (rc 2)"
    alert_route: "none at runtime by design (fail-open); the arm is exercised by the suite"
logs:
  where: ".claude/.rule-incidents.jsonl under the repo root (INCIDENTS_REPO_ROOT in tests)"
  retention: "rotated by .claude/hooks/lib/log-rotation.sh rotate_if_needed (size/age policy of the lib)"
discoverability_test:
  command: "bash .claude/hooks/pkill-self-match-guard.test.sh"
  expected_output: "=== <N> verdicts, 0 failed === with N >= 55 and exit 0"
```

## Guard Contract

### Guard 1 — read-only ps-pipeline self-match arm

**Property.** No submitted Bash command reaches execution if it contains an args-showing `ps` pipeline whose `grep`/`egrep`/`fgrep`/`awk` regex stages, run against the wrapper line `bash -c <the command>`, leave that line alive (at least one non-`-v` stage matched it and no stage filtered it).

**Assembly.** The single chokepoint is the PreToolUse `Bash` matcher entry in `.claude/settings.json` that runs `pkill-self-match-guard.sh` on every Bash tool call (Claude and, via `lib/hook-tool-kind.sh`, the Devin `exec` wire name). Inside the hook the property quantifies over (a) every `ps` stage at a command boundary in `strip_heredocs "$CMD"` — not the first one; (b) every `grep`/`egrep`/`fgrep`/`awk` stage that follows each such `ps`, in order, until a non-matcher stage; (c) the pattern literal of each stage as `SCAN` carries it (quotes intact); (d) the flavour flags `-E`/`-F`/`-i`/`-w`/`-x`/`-v` and their long forms, the `egrep`/`fgrep` aliases, and awk's `/…/` literal. Surfaces the property does NOT reach and says so in the header: the Monitor tool's command (not a Bash tool call — `work/SKILL.md` already records this), a pattern held in a variable, a `-f FILE`/`-P` pattern, a second `-e` literal, a `\`-newline-continued stage, a `sudo`/`command`/`/bin/`-prefixed `ps`, a `-v '^bash -c'` stage (the real wrapper's argv[0] is `/usr/bin/bash`), a pattern that matches only the wrapper's snapshot preamble or `grep-rewrite.sh` prefix text (`grep -c command`, `grep -c source` — self-matches in reality, not in the model: a false allow), a `;`-boundary `ps` inside a quoted string (denied — D19 pins it as an accepted false deny), a pipeline inside a quoted string (`timeout 30 bash -c '…ps…'`, `watch '…'`, `nohup bash -c '…'`), `ps … > file; grep pat file` (not a pipeline), a `|` inside a quoted pattern (A22), and a pipeline inside `bash <<'EOF' … EOF` (heredoc bodies are stripped from the trigger scan by design; A17 pins that arm as a deliberate allow).

**Mutation matrix:**

| # | Mutation (to the hook) | Expected |
|---|---|---|
| M1 | Delete the read-only arm's call site (the `-f` arm's negative path returns to the old `exit 0`) — the guard's OWN DISPATCH | RED: every D row reads allow |
| M2 | Replace the wrapper-line simulation with the issue's "pattern appears elsewhere in the command" test | RED: D2 (`ps -eo args \| grep -c test-all.sh`, alone) reads allow |
| M3 | Stop after the first `ps` pipeline instead of looping — a SECOND member after a compliant first; or let the LAST pipeline's verdict win instead of OR-accumulating | RED: D7 (`ps -eo comm \| grep -c bash; ps -eo args \| grep -c "x-y-z"`) reads allow; D17 (self-matching pipeline FIRST, compliant second) reads allow |
| M4 | Drop the args-showing predicate so only the literal `ps -eo args` triggers | RED: D3 (`ps aux \| grep foo-daemon`) reads allow |
| M5 | Scan raw `$CMD` instead of `strip_heredocs "$CMD"` | RED: A6 (heredoc writing the doc-shaped fixture) reads deny |
| M6 | Treat a `-v` stage as a matching stage | RED: A4 (`ps -ef \| grep -E test-all \| grep -v grep`) reads deny |
| M7 | Ignore the `-F` flag / `fgrep` alias (always regex) | RED: D8 (`ps -eo args \| grep -cF '[t]est-all'` — under `-F` the bracket literal IS in the wrapper) and D18 (`fgrep -c '[t]est-all'`) read allow |
| M8 | Build `MODEL` from `SCAN` instead of from the raw `CMD` (heredoc bodies leave the wrapper model) | RED: D9 (heredoc mentioning `scripts/test-all.sh` followed by the bracket-tricked poller) reads allow |
| M9 | Trigger on `ps` anywhere in the text instead of at a command boundary | RED: A14 (`echo "ps aux \| grep -c 'foo'"` — inner pattern quoted so extraction resolves to `foo`, which the model contains) reads deny |
| M10 | Narrow the args-showing predicate to `-eo args` / `aux` only | RED: D12 (`ps -o pid,cmd \| grep -c x-y-z`), D13 (`ps x \| grep -c test-all.sh`), D14 (`ps --format args -e \| grep -c test-all.sh`) read allow |
| M11 | Swap the two arms (read-only first), or make the read-only arm's per-pipeline fail-open `exit 0` instead of `continue` | RED: D11 (both spellings → exactly one envelope, the `-f` reason) or D10 (fail-open pipeline followed by a self-matching one) reads wrong |
| M12 | Parse awk's `-v`/`-F` as grep flags | RED: D15 (`awk -v n=1 '/test-all.sh/'`) reads allow; A16 (`awk -F: '/test-all\.sh/'`) reads deny |
| M13 | Drop the `-p`/`--pid` exemption | RED: A18 (`ps -o args= -p "$pid" \| grep -c test-all.sh`) reads deny — and D16 (`ps -o args= -C bash \| grep -c x-y-z`) must stay deny so the exemption is never widened to `-C` |

**Harness rows** (edits to the SUITE that must go RED):

| # | Suite mutation | Expected |
|---|---|---|
| H1 | Delete four `run_case` lines (D1, D2, A1, A2) | RED: `[FATAL] assertion floor breached` (floor = total − 3, so four deletions breach it; a single deletion does NOT — the floor's slack is the existing suite's convention, 11 of 14) |
| H1b | Change the hook path assigned to `HOOK` to the wrong basename | RED: every row reads allow (bash cannot exec it) — pairs with H4 |
| H2 | Flip A1's expected verdict from `allow` to `deny` | RED: `FAIL … wanted deny got allow` |
| H3 | Delete the fenced `ps -eo args \| grep -c` line from A6's inline fixture, OR delete its `scripts/test-all.sh` prose line | RED: the non-vacuity control FAILs (first edit); A6's positive control — the same fixture text fed WITHOUT the heredoc wrapper must read deny — FAILs (second edit, the pattern is no longer reachable) |
| H4 | Stub the hook path to `/bin/true` | RED: every D row reads allow |

**Must-PASS, non-canonical inputs** (differ from the canonical shapes in ways the contract permits): A2 argv-slot awk naming a different script (`$2=="scripts/lint.sh"`); A4 the `work/SKILL.md` liveness triple with `-E` and `grep -v grep`; A5 `grep -cE '^bash scripts/test-all\.sh'` with the runner launched in the same command; D-rows spelled with double quotes instead of single quotes and with `egrep` instead of `grep -E`.

**Anchor.** Not applicable — the guard stores no value, hash, manifest row or count floor of its own; nothing outside the commit must move for a weakening to pass, so the harness rows above are the only integrity check.

### Guard 2 — suite assertion floor (existing, re-pinned)

**Property.** The suite cannot report success after losing more than the floor's slack of verdicts (three — the existing suite's `11 of 14` convention, kept so the positive control's retraction path stays green).

**Assembly.** `VERDICTS` append-only array; `MIN_ASSERTIONS` compared to `${#VERDICTS[@]}` at the end; both helpers proven live by the positive control.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Leave `MIN_ASSERTIONS=11` after adding ~40 verdicts | RED at review: AC1 pins `MIN_ASSERTIONS >= N − 3` (a floor 40 below the total is the vacuity the ledger exists to prevent) |
| 2 | Delete three D rows and one A row | RED: floor breached |
| 3 | Change `fail()` to append `PASS` | RED: positive control retraction path reports the helper did not behave (the existing control) |

## Plan Review Revisions

Panel: DHH, Kieran, code-simplicity (per-mechanism, fed the Property/Cut lists), CTO (devex lens); spec-flow-analyzer ran in Phase 3 with a literal prototype of the algorithm; a scoped advisor consult (Step 4.5) ran before review. Spec lacks valid `lane:` — defaulted to `cross-domain` (TR2 fail-closed).

Applied (Mechanical): one wrapper model (the draft's `MODEL_REAL` and its former `-v '^bash -c'` row and mutation cut — the ids D12/M12 now belong to the `-o pid,cmd` row and the awk-flag mutation — DHH + simplicity); no pass-through stage list (walk ends fail-open at any non-matcher — DHH + simplicity); no continuation join (DHH + simplicity); no awk slot grammar (simplicity); no `sudo`/prefix boundary set (DHH + simplicity); single rule id, `-f` arm untouched (simplicity); A6 fixture synthesized inline, repo docs checked once in Phase 3 (DHH); step-0 raw-command pre-trigger before any fork (DHH + CTO); `strip_heredocs` undefined → WARN + skip the arm (Kieran raised the silent-dead-arm class; deepen-plan's architecture review replaced the shim with fail-open); `${BASH_REMATCH[n]-}` (Kieran); stage terminator set + A22 (Kieran); telemetry row on a fresh root (Kieran); AC2/AC3 count on the verdict token (Kieran); AC7 simplified (Kieran); D11 written inline (Kieran); remedy leads with `grep -v grep` / `pgrep -a <name>` for one-off looks and warns that the awk slot must match the exact launch argv (CTO); anecdote moved from reason to header, header summary contradiction fixed, re-verify command + date in header (CTO); `-v` Sharp Edge reworded as a simulation, not a literal rule (DHH); stale row enumerations reconciled (all four).

Surfaced, not applied (Taste / User-Challenge — persisted to `knowledge-base/project/specs/feat-one-shot-8330-self-match-readonly-spelling/decision-challenges.md` for `ship`): CTO's proposal to deny only consumed-count shapes (`grep -c`, `$( )`, `until`/`while`) and allow bare display pipelines; DHH's proposal to drop the PR-body mutation evidence (AC8) and the byte-identity AC6, and to cut the row set to ~19.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change (an operator-local Claude Code hook and its bash test suite). No UI surface, no user data, no vendor, no infrastructure.

## Implementation Phases

### Phase 0 — Preconditions (verify, no edits)

- `bash .claude/hooks/pkill-self-match-guard.test.sh` → `=== 14 verdicts, 0 failed ===` (baseline; recorded during planning).
- `grep -n 'strip_heredocs()' .claude/hooks/lib/incidents.sh` → 1 hit; `grep -n '^emit_incident()' .claude/hooks/lib/incidents.sh` → 1 hit.
- `ps -o args= -p $$` from the Bash tool begins with `/usr/bin/bash -c` (re-measure once; it is the premise, and the header records the command and date).
- Edit the hook and suite with the Write/Edit tools, not a Bash heredoc: both files contain the signal spelling, so a heredoc write is denied by the current hook (this is the #7994 interaction, and the reason the new arm scans `strip_heredocs`). The suite already carries that spelling in six rows, so new rows may spell it inline too — the constraint is the write path, not the file content.

### Phase 1 — RED: suite rows first

Add to `.claude/hooks/pkill-self-match-guard.test.sh`, after the existing `-f` sections and before the positive control:

- Deny rows D1–D19 and allow rows A1–A23 exactly as enumerated in §Test Scenarios (the row names there are the `run_case` names; D11, A6's controls and the telemetry row are dedicated cases that append to `VERDICTS` through `pass`/`fail`).
- A6's fixture is an inline heredoc synthesized in the suite with the learning paragraph's shape — two prose lines, a fenced `n=$(ps -eo args | grep -c '[t]est-all\.sh')` line, and a prose line naming `scripts/test-all.sh` — with (a) a PASS/FAIL non-vacuity control asserting the fixture contains `ps -eo args | grep -c`, (b) a positive control feeding the identical fixture text WITHOUT the heredoc wrapper → deny (proves the allow comes from `strip_heredocs`, not from an unreachable pattern), then (c) the heredoc-wrapped form `cat > /dev/null <<'EOF'\n<fixture>\nEOF` → allow.
- A Devin wire-name row for the read-only arm (`tool_name:"exec"`, D2's command → deny), mirroring the existing `exec` row.
- The telemetry row runs the hook with its own `INCIDENTS_REPO_ROOT=$(mktemp -d)` (plus `mkdir -p "$R/.claude"`) per invocation — the shared suite sandbox already holds lines from earlier deny rows, so "exactly one line" is only meaningful against a fresh root.
- Raise `MIN_ASSERTIONS` to `N − 3` where `N` is the verdict total the run prints (expected around 60; AC1's `N >= 55` is the check).
- Run the suite: every new D row FAILs against the unmodified hook (RED), every A row passes vacuously — that is expected; the D rows are the RED.

### Phase 2 — GREEN: the read-only arm

Edit `.claude/hooks/pkill-self-match-guard.sh`:

- Header: rewrite the opening summary so it no longer says "when <pat> also appears ELSEWHERE" (it contradicts the `-f` paragraphs below it — CTO review); add the read-only spelling, the measured wrapper line with the re-verify command and date (`ps -o args= -p $$`, 2026-09-19), the measured counts from §Problem Statement, the #8231 anecdote, the simulation rule, the `-v` honouring, the fail-open arms, and the accepted gaps from §Guard Contract Assembly — the header is the ONLY place gaps are recorded, and every future row cites it. Keep the `-f` mechanism paragraphs verbatim.
- Step 0 pre-trigger on raw `$CMD` before any fork; source `lib/incidents.sh` fail-soft next to `lib/hook-tool-kind.sh`; if `strip_heredocs` is undefined, WARN to stderr and `exit 0` before the arm (fail-open); define `emit()` (the `background-poll-prefer-monitor.sh` precedent, verbatim in 8 hooks); define `TO=()` with the `command -v timeout` guard.
- Restructure: `if <-f trigger>; then <existing reason + envelope>; exit 0; fi` then the read-only arm; the `-f` reason string stays byte-identical and the `-f` arm gains no `emit`.
- Read-only arm per §Proposed Solution steps 1–4 (trigger/walk/extraction over `SCAN`, model over `CMD`, newlines preserved, `${BASH_REMATCH[n]-}` on every optional group); deny reason = the read-only paragraph + the recipe block with `\$1`/`\$2`/`\$!`/`\"` escaped; `emit "pkill-self-match-guard-readonly" deny "<first 80 chars of the pipeline>" "$CMD"` before the envelope.
- Run the suite: all rows green; run `bash .claude/hooks/grep-q-pipe-guard.test.sh` (the herestring rule) and `bash .claude/hooks/incident-sandbox-coverage.test.sh`.

### Phase 3 — Mutation battery, doc verification, docs

- Drive each Guard Contract row (M1–M13, H1–H4) on a scratch copy (`cp` the hook/suite to `$TMPDIR`, apply the one-line edit, run) and record the RED evidence lines in the PR body (one line per row).
- Verify the detection against the repo files that document it, once, and record both allows in the PR body (AC4): (a) the `plugins/soleur/skills/review/SKILL.md` bullet anchored on `A process count that greps its own pattern can never reach zero` (carries no signal spelling), (b) the learning section `### The instruments that were counting themselves` from `knowledge-base/project/learnings/2026-09-18-every-instrument-i-waited-on-was-counting-itself.md` with its one signal-spelling line removed by `grep -vE` over the `-f` arm's own trigger regex (that line trips the retained `-f` arm by design). Each is wrapped as `cat > /dev/null <<'EOF' … EOF` in a `tool_input.command` and piped through the hook → empty stdout. Build the probe command with the suite's helper shape so the session's own Bash tool call never carries the signal spelling (it would be denied — observed twice during planning).
- `plugins/soleur/skills/review/SKILL.md`: in the bullet beginning "A process count that greps its own pattern can never reach zero", replace the clause "the `ps … | grep` spelling is unguarded (#8330), which is the guard-written-against-one-spelling shape" with "the `ps … | grep` spelling is guarded since #8330 (the hook simulates the pattern against `bash -c <command>`)" (the source file spells the pipe bare; the `\|` in this plan's tables is markdown escaping). `.claude/hooks/README.md` `## Hook roster` table: add the row `| \`pkill-self-match-guard.sh\` | 2 | \`pkill-self-match-guard-readonly\` (the \`-f\` arm emits none) |` after the `worktree-write-guard.sh` row. No other doc edits; the learning is a dated record.
- `TEST_GROUP=scripts bash scripts/test-all.sh` (the shard that registers `.claude/hooks/*.test.sh`).

## Files to Edit

- `.claude/hooks/pkill-self-match-guard.sh` — header (summary rewrite, measured facts, accepted-gap list), step-0 pre-trigger, `strip_heredocs` shim, control-flow restructure, read-only arm, `emit()` telemetry, remedy text.
- `.claude/hooks/pkill-self-match-guard.test.sh` — rows D1–D19 and A1–A23, A6's two controls, the Devin `exec` read-only row, the telemetry row, `MIN_ASSERTIONS`.
- `plugins/soleur/skills/review/SKILL.md` — one clause in the "A process count that greps its own pattern" bullet.
- `.claude/hooks/README.md` — one `## Hook roster` row for this hook (Denies 2, rule id `pkill-self-match-guard-readonly`).
- Written by the pipeline, not this plan (listed so the diff-scope AC is honest): `knowledge-base/INDEX.md` (regenerated), `knowledge-base/project/specs/feat-one-shot-8330-self-match-readonly-spelling/{tasks.md,session-state.md,decision-challenges.md}`, this plan file, and a compound learning under `knowledge-base/project/learnings/`.

## Files to Create

None.

## Acceptance Criteria

- [x] AC1 — `bash .claude/hooks/pkill-self-match-guard.test.sh` exits 0 and prints `=== <N> verdicts, 0 failed ===` with `N >= 55`; `grep -E '^MIN_ASSERTIONS=' .claude/hooks/pkill-self-match-guard.test.sh` shows a value `>= N − 3`.
- [x] AC2 — Every deny row D1–D19 is present (D11 as a dedicated case): `grep -cE '[[:space:]]deny$' .claude/hooks/pkill-self-match-guard.test.sh` ≥ 24 (baseline 6 — four `-f` rows are `\`-continued, so the verdict token, not the line start, is what counts — plus 18 `run_case` rows), and `grep -c 'jq -s length' .claude/hooks/pkill-self-match-guard.test.sh` ≥ 1 (D11).
- [x] AC3 — Every allow row A1–A23 is present: `grep -cE '[[:space:]]allow$' .claude/hooks/pkill-self-match-guard.test.sh` ≥ 28 (baseline 5 plus 23).
- [x] AC4 — Doc verification: the suite output carries an `ok` line for A6's non-vacuity control and an `ok … (=allow)` line for A6; and the PR body carries two lines, one per repo doc named in Phase 3 (the `review/SKILL.md` bullet; the filtered learning section), each quoting the empty-stdout result of piping the heredoc-wrapped section through the hook.
- [x] AC5 — `jq -nc '{tool_name:"Bash",tool_input:{command:"bash scripts/test-all.sh & until [ \"$(ps -eo args | grep -c \"[t]est-all\\.sh\")\" = 0 ]; do sleep 5; done"}}' | bash .claude/hooks/pkill-self-match-guard.sh | jq -r .hookSpecificOutput.permissionDecision` → `deny`; and the same input piped to `jq -r .hookSpecificOutput.permissionDecisionReason | grep -cF -e 'awk '"'"'$1=="bash" && $2=="scripts/test-all.sh"'"'"''` → `1`, and to `grep -cF -e '| grep -v grep'` → `1` (the one-off-look remedy is present).
- [x] AC6 — The `-f` arm's reason text is unchanged (verified working on both sides during planning, 11 lines each): `X(){ sed -n '/^reason="BLOCKED: \\`${TOOL_USED} -f\\`/,/matches the process NAME only"$/p'; }; diff <(X < .claude/hooks/pkill-self-match-guard.sh) <(git show origin/main:.claude/hooks/pkill-self-match-guard.sh | X)` → empty.
- [x] AC7 — `grep -c 'strip_heredocs' .claude/hooks/pkill-self-match-guard.sh` ≥ 2 (the call and the shim) and `grep -cE '<<<"\$MODEL"' .claude/hooks/pkill-self-match-guard.sh` ≥ 1 (herestring, not pipe — `MODEL` is the plan's name for the wrapper model; the pipe-guard suite is the real enforcement); `bash .claude/hooks/grep-q-pipe-guard.test.sh` exits 0.
- [x] AC8 — Mutation evidence: the PR body carries one line per Guard Contract row M1–M13 and H1–H4 naming the row and quoting the FAIL/FATAL line it produced on the scratch copy.
- [x] AC9 — Telemetry: with `R=$(mktemp -d); mkdir -p "$R/.claude"`, running AC5's input with `INCIDENTS_REPO_ROOT="$R"` leaves exactly one line in `"$R/.claude/.rule-incidents.jsonl"` whose `.rule_id` is `pkill-self-match-guard-readonly`; a fresh `$R` with D11's both-spellings command leaves NO line in that file (the `-f` arm does not emit) and exactly one JSON object on stdout.
- [x] AC10 — `bash .claude/hooks/incident-sandbox-coverage.test.sh` and `bash .claude/hooks/hookeventname-coverage.test.sh` exit 0; `grep -c 'hookEventName' .claude/hooks/pkill-self-match-guard.sh` ≥ 2 (both envelopes carry the event name).
- [x] AC11 — `grep -c 'guarded since #8330' plugins/soleur/skills/review/SKILL.md` = 1 and `grep -c 'is unguarded (#8330)' plugins/soleur/skills/review/SKILL.md` = 0.
- [x] AC12 — `TEST_GROUP=scripts bash scripts/test-all.sh` is green (or, if the host refuses a full-gate run, every suite returned by `git grep -l 'pkill-self-match-guard\|incidents.sh' -- '.claude/hooks/*.test.sh'` is green individually).
- [x] AC13 — Diff scope: `git diff --name-only origin/main...HEAD` is a subset of the paths in §Files to Edit (including the pipeline-written set).
- [x] AC14 — README roster: `grep -cF -e 'pkill-self-match-guard.sh` | 2 |' .claude/hooks/README.md` = 1 (the row starts with the backticked basename, a `2` deny count, and the read-only rule id).

## Test Scenarios

Every D/A row except D11 and A6's two controls is a `run_case "<name>" '<command>' <verdict>` in the suite; D11, the Devin `exec` row, A6's controls and the telemetry row are dedicated cases appending to `VERDICTS` via `pass`/`fail`. Given the hook receives the command as a Bash `tool_input.command`, when it runs, then it emits `permissionDecision: deny` (D) or nothing (A).

**Deny (self-matching):**

- D1 — incident shape, bracket trick with the literal elsewhere: `bash scripts/test-all.sh > /tmp/b.log 2>&1 & until [ "$(ps -eo args | grep -c '[t]est-all\.sh')" = 0 ]; do sleep 5; done`
- D2 — unescaped metacharacter, alone: `n=$(ps -eo args | grep -c test-all.sh)`
- D3 — bare literal, `ps aux`: `ps aux | grep foo-daemon`
- D4 — `ps -ef` with `-i` and a trailing `wc` (the flag is load-bearing: the model carries lowercase `nginx`): `ps -ef | grep -i NGINX | wc -l`
- D5 — awk regex literal: `ps -eo args | awk '/test-all.sh/' | wc -l`
- D6 — the #7888 narrowing (`^bash .*`): `bash scripts/test-all.sh & ps -eo args | grep -cE '^bash .*test-all\.sh'`
- D7 — second pipeline after a compliant first: `ps -eo comm | grep -c bash; ps -eo args | grep -c "x-y-z"`
- D8 — fixed-string flag defeats the bracket trick: `ps -eo args | grep -cF '[t]est-all'`
- D9 — the #8231 shape with the literal in a heredoc BODY (the wrapper carries the body): `cat > /tmp/note.md <<'EOF'` newline `waiting on scripts/test-all.sh` newline `EOF` newline `n=$(ps -eo args | grep -c '[t]est-all\.sh')`
- D10 — a fail-open pipeline followed by a self-matching one (fail-open is per pipeline, not per hook): `P=x; ps -eo args | grep -c "$P"; ps -eo args | grep -c test-all.sh`
- D11 — both spellings in one command → exactly ONE JSON object on stdout (`jq -s length` = 1) whose reason begins with the `-f` arm's `BLOCKED:` line (discriminate on that prefix — both reasons contain "matches the process NAME only" once the `pgrep -a <name>` recipe lands): `pgrep -af x; ps -eo args | grep -c test-all.sh` (a dedicated case written inline like the existing `-f` rows, not a bare `run_case`)
- D12 — another args-showing `-o` list: `ps -o pid,cmd | grep -c x-y-z`
- D13 — BSD `x` alone: `ps x | grep -c test-all.sh`
- D14 — long-form format: `ps --format args -e | grep -c test-all.sh`
- D15 — awk's `-v` is not grep's `-v`: `ps -eo args | awk -v n=1 '/test-all.sh/' | wc -l`
- D16 — `-C` is not a pid restriction (the wrapper's comm is `bash`): `ps -o args= -C bash | grep -c x-y-z`
- D17 — self-matching pipeline FIRST, compliant second (verdicts OR-accumulate; "last pipeline wins" is the mutant): `ps -eo args | grep -c test-all.sh; ps -eo comm | grep -c bash`
- D18 — `fgrep` alias is fixed-string: `ps -eo args | fgrep -c '[t]est-all'`
- D19 — `;` boundary inside a quoted string is an ACCEPTED false deny (the boundary regex does not track quotes; the remedy is self-explaining and the header names the gap): `echo "x; ps aux | grep -c 'foo'"`

**Allow (cannot self-match, sanctioned, documentation, or fail-open):**

- A1 — bracket trick + escaped dot, no other mention: `n=$(ps -eo args | grep -c '[t]est-all\.sh')`
- A2 — argv-slot recipe with the runner launched in the same command: `bash scripts/test-all.sh & ps -eo args | awk '$1=="bash" && $2=="scripts/test-all.sh"' | wc -l`
- A3 — name-only `ps`: `ps -eo comm | grep -c bash`
- A4 — the `work/SKILL.md` liveness shape: `ps -ef | grep -E 'test-all' | grep -v grep`
- A5 — start-anchored without `.*`: `bash scripts/test-all.sh & ps -eo args | grep -cE '^bash scripts/test-all\.sh'`
- A6 — heredoc writing a doc-shaped inline fixture (synthesized in the suite: two prose lines, a fenced `n=$(ps -eo args | grep -c '[t]est-all\.sh')` line, a prose line naming `scripts/test-all.sh`), preceded by two controls: the non-vacuity control (fixture contains `ps -eo args | grep -c`) and the positive control (the identical fixture text fed WITHOUT the heredoc wrapper → deny). Then `cat > /dev/null <<'EOF'` + fixture + `EOF` → allow.
- A7 — grepping docs for the shape: `grep -rn 'ps -eo args | grep -c' knowledge-base/`
- A8 — pattern in a variable (fail-open): `P=test-all; ps -eo args | grep -c "$P"`
- A9 — pattern file (fail-open): `ps -ef | grep -c -f pats.txt`
- A10 — no matcher stage: `ps -eo args | wc -l`
- A11 — sanctioned helper: `source plugins/soleur/scripts/lib/proc.sh; list_runs test-all`
- A12 — `ps` mentioned inside a quoted argument with no boundary before it: `grep -n "ps aux | grep -c 'foo'" README.md`
- A13 — invalid regex (fail-open): `ps -eo args | grep -c '[unterminated'`
- A14 — `ps` inside an echoed string, not at a command boundary; inner pattern QUOTED so that under mutation M9 extraction resolves and the row goes RED: `echo "ps aux | grep -c 'foo'"`
- A15 — literal containing a quote (fail-open): `ps -eo args | grep -c "it's-daemon"`
- A16 — awk's `-F` is not grep's `-F`: `ps -eo args | awk -F: '/test-all\.sh/' | wc -l`
- A17 — executed heredoc (deliberate fail-open, documented in the header): `bash <<'EOF'` newline `ps -eo args | grep -c test-all.sh` newline `EOF`
- A18 — pid-restricted `ps` cannot list the wrapper: `cmd & pid=$!; ps -o args= -p "$pid" | grep -c test-all.sh`
- A19 — whole-line match cannot hit the wrapper: `ps -eo args | grep -cx 'bash scripts/test-all.sh'`
- A20 — long-form invert: `ps -ef | grep test-all | grep --invert-match grep`
- A21 — slot-anchored awk regex with an escaped metacharacter (regression row; allowed by the regex, not by a slot grammar): `ps -eo args | awk '$2 ~ /test-all\.sh/' | wc -l`
- A23 — `egrep` alias of the safe bracket spelling (must-PASS, non-canonical): `ps -eo args | egrep -c '[t]est-all\.sh'`
- A22 — `|` inside a quoted pattern splits the stage wrongly and resolves fail-open by the quote rule: `ps -eo args | grep -cE 'test-all|lint' | wc -l`

**Regression (existing rows, unchanged):** the six `-f` deny rows, the Devin `exec` row, the five allow rows, the positive control.

**Wire name:** `tool_name:"exec"` with D2's command → deny (Devin kind map reaches the new arm).

**Telemetry row:** with a fresh `INCIDENTS_REPO_ROOT=$(mktemp -d)` (+ `.claude/` subdir) per invocation — the env-prefix override coexists with the sourced sandbox — D2's command leaves exactly one ledger line with `rule_id == "pkill-self-match-guard-readonly"`, and D11's command leaves none (the `-f` arm does not emit). The single-envelope assertion is D11's, not repeated here.

## Success Metrics

- Suite: `N ≥ 55` verdicts, 0 failed, floor within 3 of the total.
- Every Guard Contract row produced its RED line on the scratch copy (AC8).
- Post-merge (informational, no soak gate): `rule_id == "pkill-self-match-guard-readonly"` appears in the incident ledger the first time an agent types the spelling; the aggregator's weekly counter is the read.

## Dependencies & Risks

- **False denies on legitimate diagnostics** (`ps aux | grep <thing>` typed to look at the box): the reason text is self-explaining and the sanctioned spellings (`grep -v grep`, argv-slot awk, `list_runs`) are one edit away; the guard remains a redirect. Mitigation: A2, A4, A5 are must-PASS rows.
- **Extraction misses a spelling** (a second `-e`, `-P`, `'\''`-escaped quotes, a pipeline inside a quoted `bash -c '…'`, `|&` splitting, `ps … > file; grep pat file`): the arm fails open on anything it cannot resolve, so a miss is today's behaviour, not a new denial. Each accepted gap is named in the header so a future tightening is a deliberate change.
- **`strip_heredocs` blanks a heredoc that is EXECUTED** (`bash <<'EOF'`): a poller written that way escapes the new arm. Accepted: the hook is a redirect against the typed-from-memory shape; the header records the gap.
- **Hot-path cost:** one `[[ =~ ]]` on raw `$CMD` for commands without a `ps` token at a boundary (step 0); `perl` + bounded `grep`s otherwise. No measurable change expected.
- **Monitor tool commands are not Bash tool calls** and are not covered (already documented in `work/SKILL.md`); out of scope.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. Fill it before requesting deepen-plan or `/work`.
- Do NOT write the hook or the suite via a Bash heredoc, and do not type a probe command that carries the signal spelling: the CURRENT hook denies both (the #7994 interaction — it denied two planning-time probes in this session). Use the Edit/Write tools for files and build probe strings from variables. After Phase 2 lands, the same applies to the `-f` arm only; the new arm ignores heredoc bodies.
- The `-v` honouring is a simulation, not a rule about literals: a `-v` stage filters the wrapper exactly when its regex matches the model (`grep -v grep` does, because the wrapper carries "grep"; `grep -v 'test-all\.sh'` does not, because the wrapper carries the backslash). Do not "tighten" it to `grep -v grep` only, and do not paraphrase it as "any literal filters".
- The bracket trick ALONE is allowed (A1) and that is deliberate — it cannot self-match. The incident is the bracket trick PLUS the literal elsewhere (D1). Do not collapse A1 into a deny to "be safe"; that would make the guard a wall for the one spelling that works when the runner is launched in a different tool call.
- `strip_command_bodies` (which also blanks quoted spans) is the WRONG helper here — it would blank the pattern. Use `strip_heredocs`.
- The floor `MIN_ASSERTIONS` must be recomputed from the run (`total − 3`), not carried from the current 11 — Guard 2 row 1.

## References & Research

- Issue #8330; related #8231 (incident), #7994 (docs-about-themselves umbrella), #7525 → PR #7531 (`proc.sh`), PR #7888 (the `^bash .*` narrowing measured as still self-matching), PR #8270.
- `knowledge-base/project/learnings/2026-09-18-every-instrument-i-waited-on-was-counting-itself.md`
- `knowledge-base/project/learnings/best-practices/2026-06-08-command-string-scanning-hook-must-skip-glob-metachar-tokens.md`
- `knowledge-base/project/learnings/2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md`
- `knowledge-base/project/learnings/2026-08-13-every-guard-i-shipped-was-satisfiable-by-a-guard-that-asserts-nothing.md`
- `knowledge-base/project/learnings/2026-07-20-adding-a-second-copy-of-a-guarded-literal-disarms-the-first.md`
- `knowledge-base/project/learnings/2026-07-22-a-drift-guard-pr-fails-open-in-the-guard-not-the-guarded-code.md`
- `knowledge-base/project/learnings/2026-09-15-devin-dual-hook-registries-dead-matchers-fires-then-noops.md`
- `knowledge-base/project/learnings/2026-03-28-pretooluse-hook-guard-ordering-matters.md`
- `knowledge-base/project/learnings/2026-08-02-ps-named-it-2-1-220-so-a-grep-that-ate-the-box-read-as-a-claude-leak.md`
- `knowledge-base/project/learnings/2026-05-15-plan-ac-verification-commands-awk-self-match-and-marker-conjunction.md`
- Precedents: `.claude/hooks/background-poll-prefer-monitor.sh` (`emit()` wrapper, AND-gated detection header), `.claude/hooks/guardrails.sh` (`BASH_REMATCH` extraction), `.claude/hooks/pre-merge-auto-close-scan.sh` (multi-match iteration), `.claude/hooks/lib/incidents.sh` (`strip_heredocs`, `emit_incident`).
- Community discovery (functional-discovery, 3/3 registries): no skill or hook guards self-matching process scans; the nearest cousin (`warden`) splits pipelines per stage, which this design mirrors conceptually. Nothing installed.
