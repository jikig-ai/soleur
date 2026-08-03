---
title: Neutralize the ugrep grep-shim via a prefixed function redefinition
issue: 7165
branch: feat-7165-grep-rewrite-updatedinput
pr: 7167
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: waived-by-operator-2026-08-02
brainstorm: knowledge-base/project/brainstorms/2026-08-02-grep-rewrite-command-grep-brainstorm.md
spec: knowledge-base/project/specs/feat-7165-grep-rewrite-updatedinput/spec.md
status: plan-v2
---

# Plan v2: neutralize the grep shim by *redefining* `grep`, not by parsing commands

> **v2 supersedes v1 (2026-08-02).** v1 proposed finding `grep` tokens in the command
> string and splicing `command grep` over them. A 5-agent review panel reproduced
> **seven** concrete failures in that mechanic, four of which corrupt commands that
> work today. v2 replaces the parser with a one-line prefix and lets **bash** resolve
> the name. See `## Plan Review Findings`.

## Overview

Claude Code's shell snapshot installs a bash **function** named `grep` that re-execs
the `claude` binary with `argv[0]=ugrep`. For patterns whose cost depends on literal
reachability, ugrep builds a DFA that reached 9.5 GB RSS against a single 21 kB file
and froze a 31 GB desktop, killing six sessions.

A PreToolUse hook prepends a `grep()` redefinition to the Bash command and **leaves
the command itself byte-identical**:

```
grep(){ …command grep…; }; <original command, untouched>
```

Bash resolves the name at execution time. Nothing is parsed, so nothing can be
mis-parsed.

## Why v2 — measured, not argued

| Property | v1 (parse + splice) | v2 (prefix) |
|---|---|---|
| Corrupt quoted data (228 measured calls) | guarded by fixtures | **impossible** — command never edited |
| Corrupt `git grep` (179), `pgrep` (161), `xargs grep` (12) | guarded by fixtures | **unreachable** — different names / binary exec |
| `G=grep; $G …` | **unfixable**, delegated to #7166 | **solved** (measured) |
| `eval "grep …"` | **unfixable**, delegated to #7166 | **solved** (measured) |
| Shell-quoting lexer required | yes (state machine) | **no** |
| Reviewer-reproduced corruption bugs | 7 | 0 |

Measured against a simulated shim this session — `grep`, `$(grep …)`, `G=grep; $G …`
and `eval "grep …"` all returned the real GNU-grep result under the prefix, while
`echo "grep is data"` and `git grep` were untouched.

## Research Reconciliation — v1 claims vs. measurement

| v1 claim | Reality (measured) | v2 response |
|---|---|---|
| `nice` is a shell keyword | **binary** (`type -t nice` → `file`). `nice command grep` → rc=127. `nice grep` never reached the shim. | anchor deleted entirely |
| `\0` mask filler is length-preserving | bash **drops NUL** in `$( )` (3 bytes → 2) | masker deleted entirely |
| prefix-exclusion list is safe belt-and-braces | it makes AC10's over-rewrite mutation pass **vacuously** (second guard disarms the first) | deleted entirely |
| shim bypass predicate (9 arms) | shim has **12** arms; v1 dropped `-*-format-open*`, `-*-save-config*`, `-[!-]*[Zz]*` | full 12 arms, mirrored inside the redefined function |
| D3: losing `.gitignore` has "no latency cost" | **false.** Recursive grep: shim 423 ms → v1 flag set **5,446 ms (12.9×)**; adding `node_modules`/`dist`/`.next` excludes → 590 ms | **D3 reversed** — ship the denylist |
| emit `updatedInput.command` only | `updatedInput` may **replace** `tool_input`, dropping `timeout`/`run_in_background`/`description`/`sandbox` | build as `.tool_input \| .command = $new` — correct under merge **or** replace |
| alert route = weekly aggregator | an untagged rule_id makes `scripts/rule-metrics-aggregate.sh` **exit 5** (`:374`, `:426`) and skip log rotation | add a `grep-rewrite-` exclusion + its test |
| editing `model.c4` is sufficient | `model.likec4.json` (644 KB, committed) contains the falsified string and is byte-diffed by `plugins/soleur/test/c4-model-freshness.test.sh` | regenerate the compiled artifact |
| permission rules match the rewritten command | **no** — matching runs on the **original** (measured with an `allow: ["Bash(echo:*)"]`-only probe) | no allow-rule regression; recorded in the ADR |

## Premise Validation

#7151 CLOSED unmerged · #7163 MERGED (learning file on `main`) · #7166 OPEN ·
`updatedInput` verified by execution · sibling `deny` beats `updatedInput` (measured).

## User-Brand Impact

**If this lands broken, the user experiences:** a corrupted shell command. v2 reduces
this to near-zero by construction — the command is never edited, only prefixed.

**If this fails open, the user's workflow is exposed via:** a one-line search reaching
9.5 GB RSS at 99% CPU, freezing the desktop and killing every concurrent session.

**Brand-survival threshold:** `single-user incident`.

## The mechanic

### The injected prefix

```bash
grep(){ local a; for a in "$@"; do case "$a" in
  -*-filter*|-*-pager*|-*-view*|-*-format-open*|-*-config*|---*|-@*|-*-save-config*|-[Zz]*|-[!-]*[Zz]*|--null|--null-data)
    command grep "$@"; return;; esac; done
  command grep -I --exclude-dir=.git --exclude-dir=.svn --exclude-dir=.hg --exclude-dir=.bzr --exclude-dir=.jj --exclude-dir=.sl --exclude-dir=node_modules --exclude-dir=dist --exclude-dir=.next "$@"; };
```

All 12 shim bypass arms are mirrored so bypass-flag calls receive **exactly** what
they receive today (`command grep "$@"`, no injected flags). The non-bypass arm adds
the six shim `--exclude-dir` values **plus** the three heavy build dirs that recover
the 12.9× recursive regression (D3, reversed by measurement).

### The hook

1. Read stdin; extract `.tool_input.command` forcing a scalar
   (`| if type=="string" then . else tojson end`) — do **not** reproduce the confirmed
   `eval` + `jq @sh` RCE (TR5).
2. **Kill switch first**, before any lib sourcing or subprocess: if
   `SOLEUR_DISABLE_GREP_REWRITE` is set, `exit 0`.
3. **Idempotency:** if the command already contains the sentinel, emit nothing.
4. **Gate:** if the command contains no `grep` substring, emit nothing. This gate may
   be sloppy — a false positive costs one inert function definition, never a corrupted
   command. That property is the entire point of v2.
5. Emit `updatedInput` built from the **whole** `tool_input`, with **no**
   `permissionDecision`.
6. Every exit path is `exit 0`.

## Implementation Phases

### Phase 1 — Preconditions (no code)

- `updatedInput` applies, with no `permissionDecision` (re-probe, isolated `claude -p`).
- Sibling `deny` still wins.
- **New:** does `updatedInput` merge or replace `tool_input`? Submit a payload with
  `run_in_background`, `timeout`, `description`; assert all survive.
- **New:** is the rewritten command re-submitted to PreToolUse (re-entrancy)?
- Confirm GNU grep accepts the injected flags and still errors on `-G` + `-E`.

### Phase 2 — Hook, observe-only (dark launch)

Ship computing the prefix and emitting `emit_incident "grep-rewrite-would-rewrite"`
with the original — **no `updatedInput`**. Satisfies `wg-dark-launch-deploy-gates`.

### Phase 3 — Corpus replay

Replay all ~6,100 real Bash commands from session transcripts through the hook.
Assert every diff is **exactly** the known prefix insertion, byte-for-byte, remainder
unchanged, zero exceptions. This replaces v1's 26 hand-written fixtures as the
primary gate — 26 examples chosen by the regex's author test that author's imagination.

### Phase 4 — Flip live

Emit `updatedInput` once the soak is clean.

### Phase 5 — Differential results test

Over a synthesized tree containing `.git`, a binary file, and a gitignored dir, assert
original vs. prefixed produce identical stdout for a corpus of recursive greps. Every
divergence is enumerated in the ADR as explicitly accepted. **v1's fixtures tested the
command; the risk lives in the results.**

### Phase 6 — Gates

- Exec-bit + **registration-membership** assertion (both, see AC9/AC14), folded into
  the existing `.claude/hooks/hookeventname-coverage.test.sh` meta-suite rather than a
  4th meta-file. Derivation:
  `jq -r '.hooks|to_entries[]|.value[]?|.hooks[]?|.command' | sed 's|^"\$CLAUDE_PROJECT_DIR"/||' | sort -u`
  — note entries are quote-prefixed, `guardrails.sh` appears twice, and at least one
  is `.py`. Assert the derived list is non-empty with a minimum count.
- **Single-rewriter invariant:** exactly one Bash-matcher hook source contains
  `updatedInput`, via a one-entry allowlist; a second goes RED pointing at the ADR.
- **Rewrite-inertness:** feed original and prefixed through every sibling Bash hook;
  assert identical decisions. (Measured today: no sibling's trigger regex contains a
  `grep` token, so nothing flips — this makes it an enforced invariant.)

### Phase 7 — Aggregator, docs, ADR/C4

## Files to Create

| Path | Mode |
|---|---|
| `.claude/hooks/grep-rewrite.sh` (**not** `-guard.sh` — 18 siblings use that suffix for deny-only) | **100755** |
| `.claude/hooks/grep-rewrite.test.sh` | 100644 |
| `.claude/hooks/UPDATED-INPUT-PAYLOAD-SHAPE.md` (matches the two existing payload-shape docs) | 100644 |
| `knowledge-base/engineering/architecture/decisions/ADR-155-pretooluse-hooks-may-rewrite-tool-input.md` (ordinal provisional) | 100644 |

## Files to Edit

| Path | Change |
|---|---|
| `.claude/settings.json` | register on `Bash`; set an explicit `timeout` |
| `.claude/hooks/README.md` | §Hook contract says "decides allow/deny" and "any deviation is a pass-through" — **falsified**; add the rewrite disposition, roster entry, and a row in §Escape-hatch inventory |
| `scripts/rule-metrics-aggregate.sh` | add `grep-rewrite-` prefix exclusion (else exit 5) |
| `scripts/rule-metrics-aggregate.test.sh` | parallel test, per the `incidents.sh` synthetic-prefix contract |
| `.claude/hooks/hookeventname-coverage.test.sh` | exec-bit + membership + single-rewriter assertions |
| `knowledge-base/engineering/architecture/diagrams/model.c4` | `hooks` container technology/description; `hooks -> claude "Guards tool calls"` → names rewriting *before execution* |
| `knowledge-base/engineering/architecture/diagrams/model.likec4.json` | **regenerate** (`scripts/regenerate-c4-model.sh`) or CI goes RED |

**Not created (v1 artifacts, deleted):** `mask_command_bodies`, any edit to
`.claude/hooks/lib/incidents.sh`, `hook-exec-bit.test.sh` as a standalone file.

## Acceptance Criteria

1. **AC1a** — the hook's stdout `.hookSpecificOutput.updatedInput.command` equals a
   byte-exact expected string. **AC1b** — *that exact string*, run under
   `ulimit -v 2000000` + `timeout`, completes in single-digit MB / sub-second.
   (Split deliberately: v1's AC1 passed vacuously if the hook emitted nothing.)
2. **AC2** — sibling `deny` beats `updatedInput`. *Precondition, not acceptance* —
   it tests Claude Code, not this diff; result pasted in the PR body.
3. **AC3** — the emitted JSON contains `permissionDecision` **nowhere at any depth**,
   and no top-level `decision`/`continue`. Assert the empty and non-empty cases
   separately (`jq -e` exits 4 on empty stdin — v1's form was broken *and* vacuous).
4. **AC4** — all `tool_input` sibling keys (`description`, `timeout`,
   `run_in_background`, `sandbox`) survive the rewrite.
5. **AC5** — corpus replay (Phase 3): every one of ~6,100 real commands differs from
   its rewrite by exactly the prefix, zero exceptions.
6. **AC6** — all seven bypass forms fixtured. `$G` and `eval "grep …"` now **rewrite
   successfully** (they did not under v1).
7. **AC7** — the 12 shim bypass arms receive `command grep "$@"` with **no** injected flags.
8. **AC8** — differential results (Phase 5): identical stdout, divergences enumerated.
9. **AC9** — `git ls-files -s` output for the hook is **non-empty** *and* mode is
   exactly `100755`.
10. **AC10** — fail-open triad: empty stdin, non-JSON, JSON with no `.tool_input`,
    1 MB binary garbage, `jq` absent, `perl` absent → **exit 0**, empty stdout, one
    `grep-rewrite-disarm` incident. (A PreToolUse hook exiting 2 blocks the call —
    this hook runs on 100% of Bash calls, not just the 50.5% carrying grep.)
11. **AC11** — idempotency/fixed point: applying the hook to its own output produces
    no second prefix.
12. **AC12** — `SOLEUR_DISABLE_GREP_REWRITE=1` disables the hook, read before any
    subprocess or lib sourcing.
13. **AC13** — single-rewriter invariant test goes RED on a second rewriting hook.
14. **AC14** — registration membership: the hook is present in the settings-derived
    `PreToolUse`/`Bash` list. (Without this, dropping the registration makes the
    exec-bit gate pass green while the hook never runs — #7151's failure, one level up.)
15. **AC15** — `scripts/rule-metrics-aggregate.sh` tolerates a `grep-rewrite-*` id
    (does not exit 5) and still rotates.
16. **AC16** — `bash scripts/test-all.sh` green **on the scripts shard** (`:577` is
    inside `if want_scripts`, so a non-scripts shard passes vacuously); new suites
    asserted by name.
17. **AC17** — p95 hook latency < 50 ms on a 4 KB command (it runs on every Bash call).
18. **AC18** — `model.likec4.json` regenerated; `c4-model-freshness.test.sh` green.

### Post-merge (operator)

None.

## Observability

```yaml
liveness_signal:
  what: grep-rewrite-would-rewrite (Phase 2 soak) then silence steady-state
  cadence: per Bash call carrying a grep substring
  alert_target: none steady-state (volume); soak read manually against the corpus
  configured_in: .claude/settings.json PreToolUse[Bash]
error_reporting:
  destination: emit_incident -> .claude/.rule-incidents.jsonl
  fail_loud: true
failure_modes:
  - mode: malformed payload / jq or perl failure -> fail-open, no rewrite
    detection: emit_incident "grep-rewrite-disarm" (event_type=warn)
    alert_route: summary.grep_rewrite_disarm_count + a stderr WARNING in
      scripts/rule-metrics-aggregate.sh (added after review — the AC15 exclusion
      alone DELETED the only surface this id had, mirroring the hook-input-*
      load-bearing pair). NOT "weekly": that workflow is workflow_dispatch-only;
      the schedule was removed in #6042.
  - mode: hook deregistered from settings.json
    detection: AC14 membership assertion
    alert_route: CI red
  - mode: hook killed by timeout before it can emit
    detection: accepted + documented; fail-open by construction
    alert_route: none
logs: { where: .claude/.rule-incidents.jsonl, retention: per lib/log-rotation.sh }
discoverability_test:
  command: 'printf %s ''{"tool_name":"Bash","tool_input":{"command":"grep -r foo ."}}'' | .claude/hooks/grep-rewrite.sh | jq -r .hookSpecificOutput.updatedInput.command'
  expected_output: hookSpecificOutput.updatedInput.command beginning with the grep() prefix
```

**Residual-form telemetry: dropped.** v1 promised `grep-rewrite-residual` but nothing
implemented it, and #7166 was scoped assuming occurrences would surface. Under v2 the
two residual forms are **solved**, so the signal is moot.

## Architecture Decision (ADR/C4)

**ADR-155 (provisional)** — *PreToolUse hooks may rewrite tool input, under a
single-rewriter invariant.* The decision grants an **authority**, not just its first
use; bound it with clauses: which keys are mutable, one rewriter, never emit
`permissionDecision`, must be idempotent, must fail-open at exit 0, permission
matching happens on the original. `## Alternatives Considered`: classification (three
refuted cost models — **link**, don't restate), the v1 parse-and-splice mechanic and
its seven reproduced failures, and observe-only-first.

**C4:** `hooks = container "Hook Engine"` / `technology "PreToolUse Guards +
PostToolUse hints"` and `hooks -> claude "Guards tool calls"` are both falsified.
Relabel to name the authority (`"Guards, annotates, and rewrites tool input before
execution"`). No new element, so `views.c4` is unchanged. **Regenerate
`model.likec4.json`** and run `c4-model-freshness.test.sh` (the binding gate — not
`c4-code-syntax`/`c4-render`, which v1 named).

## Domain Review

**Domains relevant:** Engineering. Product/UX Gate: **NONE** (no UI-surface path).

**CPO sign-off: WAIVED by the operator (2026-08-02)** — internal dev-harness hook, no
user-facing surface. Threshold **not** lowered; `user-impact-reviewer` remains the
load-bearing review-time gate.

**GDPR:** trigger (b) fired (threshold); no personal data processed. No Article 30 row.
**IaC / Encryption posture:** skipped — no infrastructure, no persistent store.

## Plan Review Findings

Escalated 5-agent panel, run at operator request. **All P0s accepted.**

| Finding | Source | Disposition |
|---|---|---|
| Prefix redefinition beats parsing; solves both residuals | DHH P0-1 | **Adopted — v2's core** |
| `nice` is a binary → rc=127 corruption | DHH, Kieran P0-1, Simplicity S1 | Fixed (anchor deleted) |
| `\0` filler unimplementable in bash | DHH P0-2, Kieran P0-2, Simplicity S2 | Fixed (masker deleted) |
| Quote-lexing bugs: escape-aware single quotes, cross-boundary re-pairing, heredoc `\b` terminator, `<<<` mis-detection, `"$(grep …)"` masked away | Kieran P0-4, P1-8, P1-9 | Dissolved — v2 does not lex |
| `{grep,sed}` brace expansion, `tools=(grep …)` array, `\`+newline continuation, comments, `case` labels | Kieran P1-10, P1-11, P0-7, P2-17, P2-18 | Dissolved — v2 does not parse |
| Replacement had no backreference → `foo \| grep bar` loses the pipe | Kieran P0-3 | Dissolved |
| Byte-vs-character offset desync | Kieran P1-15 | Dissolved |
| `updatedInput` may replace `tool_input` wholesale | Kieran P0-5 | **Adopted** — build from full `tool_input`; AC4 |
| Exit code unpinned → could block 100% of Bash calls | Kieran P0-6, Arch P0-3 | **Adopted** — AC10 |
| Aggregator exits 5 on untagged rule_id | Spec-flow P0-2 | **Adopted** — verified `:374`/`:426`; AC15 |
| `model.likec4.json` byte-diffed → CI red | Arch P1-8(1) | **Adopted** — verified; AC18 |
| No kill switch; no staged rollout | Arch P0-2 | **Adopted** — AC12 + Phase 2 dark launch |
| README hook contract falsified | Arch P0-1 | **Adopted** |
| Registration-membership gap makes exec-bit gate vacuous | Spec-flow P0-3 | **Adopted** — AC14 |
| Single-rewriter invariant needs enforcing, not documenting | Arch P1-9(4) | **Adopted** — AC13 |
| Rewrite is not semantics-preserving; test results not commands | Arch P1-6 | **Adopted** — AC8 |
| D3 justified from the wrong benchmark | Spec-flow P1-14 | **Adopted** — measured 12.9×; D3 reversed |
| Prefix-exclusion list disarms the mutation battery | Simplicity S4 | Dissolved (deleted) |
| Bypass predicate missing 3 of 12 arms | Simplicity S6, Spec-flow P0-1 | **Adopted** — all 12 |
| Spec FR8 vs AC3 demand opposite bytes | Spec-flow P0-4 | **Adopted** — spec edited |
| Test harness uses `bash "$HOOK"` — the path TR3 indicts | Spec-flow P1-9 | **Adopted** — exec directly |
| Fold exec-bit into existing meta-suite, not a 4th file | Simplicity S7 | **Adopted** |
| Corpus replay > 26 hand-written fixtures | DHH P0-3 | **Adopted** — AC5 |
| Name it `-guard.sh` while not being a guard | Arch P1-7 | **Adopted** — `grep-rewrite.sh` |
| Permission matching pre/post rewrite | DHH P1-1, Arch P1-9(1), Spec-flow P1-10 | **Measured** — matches on original |
| Ship #7166's cap first | DHH P1-2 | **Surfaced to operator** — see Risks |
| ADR should bound the authority, not the use | Arch P2-11 | **Adopted** |

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Prefix on ~50% of commands adds transcript noise | Accepted; **487 chars** (measured; an earlier ~330 estimate was wrong, and 453 predates the .env excludes). Kill switch AC12. |
| A command that inspects `type grep` or defines its own `grep` sees ours | Vanishingly rare; ours is overridden by a later user definition. Documented in the ADR. |
| **Coverage window:** #7166 is OPEN | v2 solves both residuals, so this shrinks #7166 from "covers the gap" to defense-in-depth. DHH argues the cap should still land first — the guarantee is then a *bound*, not a lexical bet. **Operator call.** |
| `updatedInput` semantics undocumented for multi-hook | AC13 enforces single-rewriter |
| Hook latency on 100% of Bash calls | AC17 (p95 < 50 ms); no perl, no lib sourcing on the hot path |

## Sharp Edges

- **Never emit `permissionDecision`** — `allow` bypasses permissions for 50.5% of Bash calls.
- **Build `updatedInput` from the whole `tool_input`** — emitting only `command` may drop `run_in_background`/`timeout`.
- **`nice` is a binary, `time` is a keyword.** `nice command grep` → rc=127.
- **bash cannot hold NUL** — any masking design must use `\x01`.
- **An untagged `emit_incident` rule_id exits the weekly aggregator with 5** and skips rotation.
- **`model.c4` edits require regenerating `model.likec4.json`** or CI goes red.
- **`.claude/hooks/grep-q-pipe-guard.test.sh` forbids `| grep -q`** in `.claude/hooks/*.sh` — use herestrings.
- **Never re-run the reproducer uncapped** — `ulimit -v 2000000` + `timeout`.

---

## Implementation Reconciliation (2026-08-03)

Recorded rather than edited into the body above: the plan's predictions stay
visible next to what measurement returned. Every row below changed an artifact.

| Plan said | Measured at /work | Disposition |
|---|---|---|
| ADR-155 (provisional) | 155, 156 **and** 157 landed on `main` before this branch rebased | **ADR-162**; swept across plan, tasks, ACs, README, C4 (task 7.8) |
| Aggregator exits 5 at `:374` / `:426` | The two `exit 5` sites are the **dry-run orphan gate** and the **post-write orphan gate** (both anchored on `ERROR: orphan rule_id(s) in incidents jsonl`) | Mechanism confirmed by a RED probe. Coordinates were stale — and the line numbers this row originally cited went stale again inside this very PR, which inserts lines above them, so it now cites content anchors instead (`cq-cite-content-anchor-not-line-number`) |
| `updatedInput` *may* replace `tool_input` | It **does** replace, wholesale — `timeout`/`description`/`run_in_background` all dropped and a background call ran in the foreground | Built from the whole `tool_input`; AC4 fixtured |
| D3: 423 ms → 5,446 ms → 590 ms (**12.9×**) | ~3,600 ms → ~590 ms (**~6.0×**), spread ~230 ms | D3 **stands**; effect is ~13× the noise floor and the sign is physical. "With" figure reproduces exactly; baseline is machine state |
| Corpus ≈ 6,100 commands, **zero exceptions** | **12,057** unique commands; **0 corrupted**, **4 declined** (0.03%) | See AC5 amendment below |
| AC8: identical stdout | **Not identical.** Four divergence classes, measured against real ugrep | Enumerated in ADR-162 §Accepted divergences |
| AC17: p95 < 50 ms | Unreachable by construction — 14 ms process floor, 20 ms per jq fork, and every sibling Bash hook is **103–124 ms** | Replaced with a relative gate; see below |
| AC10: one `grep-rewrite-disarm` incident | Parse failures are owned by `lib/hook-input.sh` (landed on `main` after the plan was written) | See AC10 amendment below |
| 12 shim bypass arms | **Confirmed byte-exact** against the live snapshot | No change |
| Sibling `deny` beats `updatedInput` | **Confirmed** — nothing executed | No change |
| Re-entrancy unknown | **No re-entrancy** — one PreToolUse invocation per call | Idempotency kept as defense in depth |

### Amended acceptance criteria

**AC5 (corpus replay).** Original: "every one of ~6,100 real commands differs from
its rewrite by exactly the prefix, zero exceptions."

Amended to the invariant that actually protects the user: **no command is ever
altered other than by the exact prefix.** That held **12,057 / 12,057**. Four
commands (0.03%) were *declined* — each contains a literal RS byte (0x1E), the
field separator `lib/hook-input.sh` uses, so the shared parser correctly reports
a boundary forge and the hook fails open. All four are fixtures from the PR that
authored that parser. A decline leaves the command untouched: a missed
optimization, not a defect. "Zero exceptions" was the right instinct pointed at
the wrong quantity — a *non-rewrite* is not a *mis-rewrite*.

**AC8 (differential results).** Original: "identical stdout, divergences
enumerated." The first clause is false and the second is the real deliverable.
Measured against real ugrep (capped) on a synthesized tree: `.gitignore` is no
longer respected; `node_modules`/`dist`/`.next` are now always excluded; a bare
directory argument whose basename is an excluded name returns nothing; and path
rendering differs (`src/a.ts` vs `./src/a.ts`). All four are enumerated and
accepted in ADR-162. **The `.gitignore` one carries a privacy dimension the plan
did not anticipate** and is called out in the PR body: files a repo hides on
purpose (`.env`, credential files) can now surface in a recursive grep.

**AC10 (fail-open triad).** Original: "→ exit 0, empty stdout, one
`grep-rewrite-disarm` incident." Two clauses survive unchanged (exit 0, empty
stdout — fixtured for 9 malformed-input shapes). The third is re-pointed:
`lib/hook-input.sh` landed on `main` after this plan was written and now owns
parse-failure telemetry, emitting `hook-input-<reason>` carrying
`hook=grep-rewrite`. Emitting a second row for the same event would double-count
in the weekly aggregator, so `grep-rewrite-disarm` is reserved for the failure
this hook owns outright — the envelope could not be built. Two further
corrections: "JSON with no `.tool_input`" parses *cleanly* to an empty command
and correctly produces **no** incident (nothing was disarmed), and the "perl
absent" arm is a v1 leftover — v2 does not parse, so it is asserted as a
**mechanism ban** (the hook invokes no perl) rather than a runtime fixture that
would pass whether or not perl were reachable.

**AC17 (latency).** Original: "p95 < 50 ms on a 4 KB command." Refuted as a
*target*, not as a result: a bare `bash -c true` costs 14 ms here, one `jq` fork
20 ms, and **every** sibling PreToolUse Bash hook already registered costs
103–124 ms p95 on the same payload. No hook that sources the input helper and
forks jq can reach 50 ms, so the gate would have red on a correct
implementation. Replaced with the property that actually matters — *this hook
must not make the hot path worse than what is already on it* — asserted
**relative** to `no-memory-write.sh` in the same run, which also makes the gate
machine-independent rather than flaky on a slower CI runner. Measured:
grep-rewrite **89 ms** vs sibling **116 ms**.

### Not done at /work

- **1.6 / 8.3** — precondition results and the AC1–AC18 walk are pasted into the
  PR body at ship time.
- **8.2** — the full `scripts` shard was running against four concurrent
  sibling-worktree `test-all.sh` runs (the documented contention condition);
  result reported in the PR. The five suites this diff touches are green
  individually.

### Late correction — #7166 landed during this pipeline

§Premise Validation recorded `#7166 OPEN` and §Risks carried a "**Coverage window:**
#7166 is OPEN" row escalated to the operator as a **ship-the-cap-first?** call. Both
were true when written and stale by ship time: #7166 closed **COMPLETED on
2026-08-03T15:47Z**, in a sibling worktree running in parallel with this one. The
operator call it asked for is therefore moot — both mitigations shipped, and they
fail independently (lexical rewrite vs. cgroup bound).

Caught at the ship-phase Incident-PIR gate by probing `gh issue view 7166` rather
than reusing the plan's figure — the same "plan-quoted facts are preconditions, not
facts" rule that this branch already applied to the ADR ordinal (three times), the
aggregator line numbers, and the D3 benchmark.
