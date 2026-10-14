---
title: "fix(security): eval over jq @sh in 10 PreToolUse hooks executes attacker-named commands"
date: 2026-08-02
issue: 7164
type: bug
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
labels: [priority/p0-critical, type/security]
milestone: "Phase 4: Validate + Scale"
adr: [ADR-156, ADR-157]
revision: "v3 — post deepen-plan (6 review passes; 6 of v1's own properties falsified by measurement)"
---

# fix(security): `eval` over `jq @sh` output in 10 PreToolUse hooks executes attacker-named commands

> Spec lacks valid `lane:` — no `knowledge-base/project/specs/feat-one-shot-7164-hook-eval-jq-rce/spec.md`
> exists, so the lane defaulted to `cross-domain` (TR2 fail-closed).

## Overview

Every blocking `PreToolUse` hook in `.claude/hooks/` extracts its input with one line:

```bash
eval "$(echo "$INPUT" | jq -r '@sh "COMMAND=\(.tool_input.command // "") TOOL_NAME=\(.tool_name // "")"' 2>/dev/null || echo 'COMMAND="" TOOL_NAME=""')"
```

`jq @sh` shell-quotes **each array element as a separate word**, so an array `tool_input.command`
renders as `COMMAND='x' 'touch' '/tmp/PWNED' TOOL_NAME='Bash'` — word 1 is an assignment, **words 2+
are a command**, and `eval` runs them before the permission prompt with operator privileges.
Reproduced on all 10 hooks.

**Second defect, same line:** `|| echo 'COMMAND=""'` empties every field on a parse failure, so every
guard no-ops with `exit 0` and **no incident**.

**Third defect, found while planning:** the remedy the issue proposes first — coercing non-strings
with `tojson` — closes the RCE and **leaves the guards evaded**. `["git","stash"]` does not match
`grep -qE '(^|[;&|]|\s)git\s+stash(\s|$)'`. Ship that and #7164 closes while the same one-line
payload still bypasses `hr-never-git-stash-in-worktrees`, the commit-to-main guard, and the merge
gates — a false-negative security close. The 8 sibling hooks that read `.tool_input.command` via
`$( )` are *already* evaded this way, because `jq -r` pretty-prints an array across lines.

### The decision (ADR-157): there is no silent disarm, anywhere

v1 built an eight-cell posture table with a fail-open branch, a size cap, a surrogate-recovery path,
and a per-session counter to bound the resulting oracle. Six review passes falsified most of it. The
design that survives is much smaller because **one choice removes the need for the rest**:

> A hook that cannot fully parse its input emits `permissionDecision: "ask"`. It never continues
> silently, and it never denies.

`ask` is not `deny`: the operator can approve and proceed, so nothing bricks — which is what made
fail-open necessary in the first place. Once `ask` covers every failure, the counter has no oracle
to bound, the surrogate scrub has no disarm to prevent, the size cap has no DoS to mitigate, and the
three-status protocol collapses to two outcomes:

| Input | Outcome |
|---|---|
| parses **and** every contracted field is a string | run the guards, values byte-exact |
| anything else — non-string field, non-object `tool_input` or root, separator in a value, unparseable document, lone surrogate, oversize, `jq` missing, our own jq program broken | **`ask`**, with a `reason` classifier, plus an incident row |

`ask` is available and precedented — **measured, not assumed**:
`.claude/hooks/DEFER-DECISION-PAYLOAD-SHAPE.md` records a CC-2.1.142 probe showing `ask` +
`hookEventName` blocks execution and surfaces a message, and `kb-domain-allowlist-guard.sh` ships it
in production today.

### What the review passes changed

| v1 said | Measured | v3 |
|---|---|---|
| Coerce non-strings with `tojson` | `["git","stash"]` matches no anchored guard | **Type-assert.** Non-string ⇒ `ask` |
| Strip separators with `explode` | 10 MB: **8.55 s / 180 MB** vs 0.70 s / 43 MB for the code being replaced, ×18 parallel hooks | **`contains`-guard** (0.15 s / 23 MB) — then removed entirely (below) |
| Read fields with `read -d` / `mapfile -d` | 200 KB: **14348 ms** vs 5643 ms baseline (bash reads a delimited record byte-at-a-time from a pipe) | **`$( )` capture + `IFS` split** (4880 ms) |
| Scrub a lone surrogate and run the guards **armed** | `git ␦ stash` **does not match** the stash guard — the `tojson` trap, re-committed | **Cut.** Surrogate ⇒ `ask` |
| Cap at 256 KB, oversize ⇒ fail-open | `rm -rf / # <300 KB padding>` is **300,011 bytes, one line**; and `guardrails.sh` also sees `Write` payloads where `.tool_input.content` is a whole file (this repo tracks an 806 KB lockfile) | **Cut.** Any ceiling ⇒ `ask`, never fail-open |
| Bound the oracle with a per-session counter (escalate after 3) | `session-state.sh` is **repo**-scoped; `.session_id` is unreadable on exactly the path that increments; 18 parallel hooks cross a threshold of 3 on the **first** payload | **Cut.** No oracle left to bound |
| Emit an incident and let the aggregator surface it | Phase 1's own orphan-gate exclusion **deletes the only surface** (`$enriched` left-joins over AGENTS.md ids), and compound Phase 3.5 filters `warn` rows out by construction | **Add a real consumer** + make the in-band `ask` the primary channel |
| Per-field `ok`/`anom`/`err` tags, RS scrub, `tojson` rendering | a single leading `all(type=="string")` token computed **before** any value is emitted cannot be forged by a value, and empty values on the bad path need no scrub and no rendering | **One status token, N+1 slots.** Also resolves v1's GDPR self-contradiction: no `tojson` is ever produced |
| `printf '%s'` replaces `echo` — "a second, previously unreported bug" | `echo "$IN"` and `printf '%s' "$IN"` are **byte-identical** for a JSON payload (bash's builtin `echo` does not interpret backslashes without `-e`, and the leading `{` stops the option scan) | **Claim dropped.** Keep `printf` as hygiene. Publishing an unverifiable security claim inside a PR that exists to correct one is the anti-pattern being fixed |

**Closes #7164.**

### Blast radius

`.claude/settings.json` registers **18** `PreToolUse` hooks on the `Bash` matcher — 10 with the
`eval`, 8 reading `.tool_input.command` via `$( )`. One array payload detonates the `eval` in 10
processes *and* evades the anchored guards in all 18. `guardrails.sh` is registered a second time on
`Write|Edit|MultiEdit|NotebookEdit`.

---

## Do Not Skim

Ten constraints whose violation is **invisible** — no test points at them unless the test below
exists. Each is an AC. Everything else in this document is evidence.

1. **Every `ask` envelope carries `hookEventName: "PreToolUse"` in the same object.** Without it CC
   silently ignores the envelope and the tool runs — measured in `DEFER-DECISION-PAYLOAD-SHAPE.md`.
   A naive test asserting `permissionDecision == "ask"` on the emitted JSON passes while production
   is wide open. `hookeventname-coverage.test.sh` is a per-file **count**, not a pairing check, and
   cannot catch this.
2. **The `ask` envelope is a `printf` of a constant string — never `jq -n`.** One of its trigger
   conditions is "jq is missing." Every existing envelope in these hooks uses `jq -n`; `emit_incident`
   builds its row with `jq -nc`, so on that path the telemetry is unrecordable and the `ask` reason
   string is the only surviving channel.
3. **`raw=$(… ; printf 'X'); raw=${raw%X}` — keep the sentinel *and* the trailing separator.** They
   are redundant with each other and load-bearing as a pair: removing either alone is invisible;
   removing both silently truncates trailing newlines from the last field, on the **happy path**.
4. **Catch to a distinguished value (`catch {}`), never `catch ""`.** `catch ""` makes
   `{"tool_input":"oops"}` read as a clean parse of an empty command — rc 0, guards no-op, no
   incident. v1 had exactly this bug.
5. **Source the helper fail-hard — no `|| true`, no `|| :`, no `2>/dev/null` on the `source` line.**
   A fail-soft source leaves `hook_parse_input` undefined; under `set -euo pipefail` the hook dies at
   the call, prints nothing, exits non-zero, and the tool proceeds. Defect 2, one line above where
   every test points.
6. **The slot count is the parse-failure detector, not jq's exit code.** Empty stdin gives jq rc 0
   with zero output. `if ! jq …; then` ships a hook that treats empty input as a successful parse.
7. **`local o=${IFS-}`, never `local o=$IFS`.** Measured: with `IFS` unset under `set -u` the latter
   kills the shell, printing nothing — silent fail-open in the one line whose job is safety. Restore
   with `unset IFS` when it was unset.
8. **Restore globbing conditionally** — `case "$-" in *f*)` before `set -f`. An unconditional
   `set +f` *enables* globbing for a caller that had it off.
9. **`guardrails.sh` is the designated `ask` responder**, so a `settings.json` assertion is
   load-bearing: every `PreToolUse` matcher containing any migrated hook must also contain
   `guardrails.sh`. True today (both registrations); nothing enforces it.
10. **`INCIDENTS_REPO_ROOT` must be honoured by the new emitter** or the tests pollute the working
    tree and the "loud disarm" AC reads the wrong file.

---

## Premise Validation

Every claim re-verified by execution on 2026-08-02, including my own. An independent sweep re-checked
20 repository facts: **20 CONFIRMS, 0 CONTRADICTS.**

| # | Premise | Verification | Result |
|---|---|---|---|
| P1 | 10 files carry the `eval` | `git grep -lE 'eval "\$\(echo "\$INPUT" \| jq -r .@sh' .claude/hooks/*.sh` | **HOLDS** |
| P2 | `jq @sh` splits an array into shell words | ran the issue's jq line | **HOLDS** |
| P3 | The reproducer creates a marker | ran it against **all 10** | **HOLDS** — third independent confirmation |
| P4 | #7164 open on `main` | `gh issue view 7164` | **HOLDS** |
| P5 | The `eval` exists for a one-fork hot path | `git log -S'@sh'` → `8a8b22360` (#2573), closing #2253 | **HOLDS** — preserve fork count, not the idiom |
| P6 | `tojson` coercion suffices | ran the coerced value against the real guard regexes | **FALSIFIED** |
| P7 | `mapfile -d ''` on NUL | `jq -j '"a","\u0000","b"'` → `ab` | **FALSIFIED** — jq drops NUL from literals *and* input values; `--raw-output0` needs jq ≥ 1.7, `mapfile -d` needs bash ≥ 4.4. `\u001e` (RS) is emitted literally and works on jq 1.5 / bash 3.2 |
| P8 | The extractor is not slower | 4 mechanisms × 4 sizes × 100 iters, micro **and** in-situ | **CONDITIONAL** — below |
| P9 | The helper is shellcheck-clean | `shellcheck -s bash` on the prototype | **HOLDS with two justified disables** — `SC2206` (deliberate word-split), `SC2034` (published globals). Without the directives AC15 fails |
| P10 | Sibling scope | authoritative grep minus the eval-10 | **8** in `.claude/hooks/` + **2** in `.openhands/hooks/`. (v1 guessed ~16; a review pass guessed 5) |
| P11 | `ask` is honored | `DEFER-DECISION-PAYLOAD-SHAPE.md` probe table + production use | **HOLDS** — re-probe only on a CC major bump |
| P12 | `bats` / `shellcheck` gate `.sh` in CI | `command -v bats`; read `ci.yml` | **BOTH FALSE** |
| P13 | `.claude/hooks/*.test.sh` auto-discovered | `scripts/test-all.sh` › `want_scripts` glob | **HOLDS** — zero registration; the `test-scripts` shard has **no bun and no node** |
| P14 | AGENTS budget headroom | `lint-agents-rule-budget.py` → `[OK] B_ALWAYS=42547` / 46000 | **HOLDS** — the plan still declines a rule |
| P15 | ADR-131's moratorium blocks a gate | read its frontmatter | **FALSE** — `status: proposed`, "This ADR decides nothing" |
| P16 | Next free ordinals | `git fetch origin main`; highest is ADR-154 | **155/156 free — PROVISIONAL** |
| P17 | The surrogate scrub recovers an armed guard | ran the stash regex against `git ␦ stash` | **FALSIFIED** — no match; control matches |
| P18 | `local o=$IFS` is `set -u`-safe | `bash -c 'set -u; unset IFS; f(){ local o=$IFS; }; f'` | **FALSIFIED** — shell dies |
| P19 | Oversize is exotic | `len('rm -rf / # ' + 'x'*300000)` | **FALSIFIED** — 300,011 bytes |
| P20 | The aggregator surfaces a counts-only `rule_id` | read `rule-metrics-aggregate.sh` | **FALSIFIED** — only `orphan_rule_ids`, which Phase 1 removes. Correct precedent: `drops_jq_fail_count` + the stderr line the script already prints |
| P21 | compound surfaces the fault | `compound/SKILL.md` § 3.5 | **FALSIFIED** — filters to `event_type ∈ {deny,bypass}` |
| P22 | `echo` mangles the payload | ran both forms on a JSON payload with `\\` and `-e -n` | **FALSIFIED** — byte-identical. Claim dropped |
| P23 | 16 of 18 hooks already have a `.test.sh` sibling asserting their characteristic decision | directory listing | **HOLDS** — so a fresh 18-fixture canary largely duplicates ~4,600 existing lines. Only `ship-soak-followthrough-gate.sh` and `doppler-secrets-delete-redirect.sh` lack one |
| P24 | All 18 hooks can produce a decision from a bare stdin payload | probed all 18 empirically | **FALSIFIED** — only **7** can. 8 need a local git fixture, 3 need a `gh` stub. Reshapes AC2 |

### P8 — the measurements that reshaped the design

Micro-benchmark, 100 iterations, ms, bash 5.3.9 / jq 1.8.1, interleaved:

| payload | legacy `eval` | `read -d` | `mapfile -d` | **`$( )` + IFS** | `explode` |
|---|---|---|---|---|---|
| 100 B | 858 | 910 | 969 | **932** | 922 |
| 2 KB | 859 | 992 | 909 | **908** | 1278 |
| 20 KB | 1621 | 2585 | 2237 | **1278** | 4159 |
| 200 KB | 5643 | 14348 | 14620 | **4880** | 33091 |

**The micro-benchmark is not the shipped cost.** Spliced into a real hook and run as a full process,
80 iterations, interleaved:

| payload | orig | orig + a no-op `source` | new | source cost | parse cost |
|---|---|---|---|---|---|
| small | 80.7 ms | 88.4 ms | 91.1 ms | **+9.1 ms** | +2.7 ms |
| 200 KB | 254.4 ms | 273.8 ms | 313.5 ms | **+20.8 ms** | +39.7 ms |

The jq program is faster; the extra `source` dominates and the whole hook lands ~8-16% slower per
invocation. AC8 is written against **these** numbers. A separately-measured simplified variant hit
the same envelope with a third of the code — the complexity was not buying the speed, which is the
finding that governs the cuts above.

---

## Research Reconciliation — Spec vs. Codebase

| Claim | Reality | Response |
|---|---|---|
| Fix with `tojson` | closes RCE, leaves the guard evaded (P6) | type-assert ⇒ `ask` |
| Fix with `mapfile -d ''` on NUL | jq drops NUL; `read -d` is a 2.5× regression (P7, P8) | RS + `$( )` capture + `IFS` split |
| `emit_incident "guardrails-input-parse-failure"` | the orphan gate hard-`ERROR`s on unknown ids **and** Phase 1's exclusion deletes the only surface (P20, P21) | one `hook-input-*` prefix; exclusion **plus** a first-class summary counter **plus** a widened compound filter — and the in-band `ask` as the primary channel |
| "a startup canary fed a known-deny fixture" | a hot-path canary re-pays the cost #2253 removed; and 16 hooks already ship sibling suites doing exactly this (P23) | **run the 16 existing sibling suites**; write the 2 missing ones. Same assurance, ~90% less new fixture code |
| Issue scopes to 10 files | 8 more `.tool_input.command` readers are evaded by the same payload; 12 more read `.tool_input.file_path`/`.skill`, of which 2 (`worktree-write-guard.sh`, `iac-plan-write-guard.sh`) are **blocking write guards** and `pencil-open-guard.sh` sits on an `mcp__*` matcher — exactly the reachability argument the issue makes | sweep 10 + 8 + the 2 write guards; **explicitly exempt** the 10 advisory/PostToolUse hooks with a listed reason and a follow-up issue |
| Learning `2026-03-18-stop-hook-jq-invalid-json-guard.md` justified the `\|\| true` absorb | correct about absorbing, silent about announcing | ADR-157 supersedes that reading |
| `.openhands/hooks/*` mirrors | different envelope (`.working_dir`, `.tool_input.path`) and deny shape; not RCE-vulnerable, is evadable. `pre-merge-rebase-parity.test.sh`'s own header records that silent divergence has happened twice on that host | minimal in-place guard + parity test. Convergence is a follow-up |
| `security_reminder_hook.py` | `json.loads` + `isinstance(new_string, str)` — the only pre-existing type-check on model-controlled input | not vulnerable; say so in the PR body so the sweep reads complete. Cite as the precedent bash converges on |
| — | `2026-05-15-deterministic-permissions-empirical-probes-and-review-gaps.md` records "security-sentinel — confirmed jq @sh-escape neutralizes stdin command injection" | append a **dated correction** citing #7164; do not rewrite the historical finding; never write "input is now safe" |
| — | `grep-q-pipe-guard.test.sh` sweeps `lib/*.sh` for `\| grep -q`, asserting zero | the helper must contain none |
| — | `guardrails.test.sh` documents that CI-on-`main` masks gates (#5192) and ships a non-git-CWD isolation idiom | reuse it verbatim in every git-fixture canary; never reinvent it |

---

## User-Brand Impact

**If this lands broken, the user experiences:** every `Bash` call aborts with a shell error, or hangs
(v1's `explode` would have burned minutes of CPU and gigabytes of RSS across 18 parallel hooks), or —
worst because silent — their session runs ungoverned: no block on `git commit` to `main`, `rm -rf` on
a worktree root, `$HOME`, or `/`, and no freeze edit-lock. The artifact is a destroyed worktree or an
unauthorised commit the operator has no record of refusing.

**If this leaks, the user's workflow and machine are exposed via:** the defect itself — an array
`tool_input.command` runs attacker-named commands as the operator, before any prompt, with their SSH
keys, Doppler session, and `gh` credentials in reach. Secondarily the fault telemetry: **v1
contradicted itself here** (its Observability block logged a `tojson` rendering while its GDPR
section claimed no payload content was persisted, so `["curl","-H","Authorization: Bearer sk-…"]`
would have hit disk). v3 emits **empty values on the failure path by construction** — no rendering
exists to log — and the row carries field name, JSON type, and length only.

**Brand-survival threshold:** `single-user incident`.

**Reachability stays open, deliberately.** Whether the harness type-validates `tool_input` before
dispatch could not be established from inside the repo. The PR body must neither upgrade this to
"confirmed exploitable" nor downgrade it to "theoretical." The issue's framing is correct and is
ADR-156's rationale: *a hook must not depend on an upstream invariant it cannot verify*, and
`PreToolUse` also receives MCP and other tool shapes.

---

## Implementation Phases

### Phase 0 — Preconditions (measure; write no product code)

0.1 Re-run the reproducer against all 10 hooks from a `mktemp -d` CWD with `INCIDENTS_REPO_ROOT`
redirected. **Never from the worktree root** — the payload's trailing words go to `touch`. Use a
fresh per-run temp dir; stale `PWNED*` markers either false-fail or self-satisfy (the planning run
left ten).

0.2 `printf '{}' | jq -j '"a","\u001e","b"' | od -c` must show `a 036 b`. If not, stop.

0.3 Reproduce both P8 tables. AC8 is written against the **in-situ** one.

0.4 `bash -n` all 20 hooks pre-change.

0.5 Confirm the running CC major version has not passed `2.1.142`; re-probe `ask` if it has.

0.6 A validated prototype (23-case matrix, shellcheck-clean, in-situ splice) is in the planning
scratchpad. **Port it; do not re-derive it.**

### Phase 1 — A telemetry surface a human actually reads

The exclusion alone **deletes** the only place a counts-only `rule_id` appears. All four, in order,
before any emit:

1.1 `scripts/rule-metrics-aggregate.sh` — add `map(select(startswith("hook-input-") | not))` to the
`$orphan_ids` pipeline, commented like the existing `context-reviewed-` block.
1.2 **Same file** — add `summary.hook_input_fault_count` + per-`reason` counts mirroring
`drops_jq_fail_count` / `drops_rotation_fail_count`, and print a non-zero count to stderr the way the
script already does for drop sentinels. **This is the replacement surface**; without it 1.1 makes the
fault invisible.
1.3 `plugins/soleur/skills/compound/SKILL.md` § 3.5 — widen the filter to also admit
`kind == "hook_self_fault"`; add the paired test assertion.
1.4 `scripts/rule-metrics-aggregate.test.sh` — cases for 1.1 and 1.2.

### Phase 2 — Both failing tests, RED against `main`

Create `.claude/hooks/hook-input-contract.test.sh` with **two** assertions and observe both fail
(`cq-write-failing-tests-before`).

2.1 **Idiom ban.** For every non-`*.test.sh` file under `.claude/hooks/` and `.openhands/hooks/`,
**any** `eval` is banned — not just the one spelling being deleted (`eval $(…)` unquoted,
`V=$(…); eval "$V"`, and `eval "${x}"` all evade a `eval[[:space:]]+"\$\(` pattern). Allow-list the
two `eval "exec ${fd}>&-"` lines in `lib/session-state.sh` **by exact string**.

2.2 **Guard-still-armed.** An array payload encoding a guarded command must yield `ask`. This is the
assertion that catches a coerce-and-continue fix, and it is **RED on `main` today** (the array
payload currently runs the `eval`, sets `COMMAND='x'`, and the guards allow). v1 authored it after
both migrations, where it could never be seen fail — the `stub-argv-fidelity` failure mode the hooks
README documents. **This is the highest-value ordering change in the review.**

### Phase 3 — The ADRs (before anything cites them)

Re-derive both ordinals from a freshly-fetched `origin/main` immediately before writing.

- **ADR-156 — the trust boundary.** *Hook stdin is model-controlled and untrusted; a hook must not
  depend on an upstream invariant it cannot verify.* Durable, repo-wide, binds ~30 hooks and both
  harnesses. Encoded by the new `claude -> hooks` C4 edge. Must never be superseded.
- **ADR-157 — the response posture.** *A hook that cannot fully parse its input asks; it never
  continues silently and never denies.* Operational and tunable. Cites 155. Owns the Alternatives
  table. Must supersede the silent-absorb reading of `2026-03-18-stop-hook-jq-invalid-json-guard.md`
  and cite ADR-070 as the only prior fail-open sanction — an *additive advisory* hook, the complement
  of this case. Records the surrogate finding (scrubbing changes the bytes the guard matches) as a
  known limitation, and the designated-responder invariant.

Splitting keeps the mechanism (`hook_parse_input`, the `eval` ban, one fork) out of ADR scope — it
lives in the README + the lint — so a future helper refactor cannot supersede the trust boundary
along with it. Add an `AP-NNN` to `principles-register.md` (which has no principle covering untrusted
input) linked to ADR-156.

### Phase 4 — The extractor

Create `.claude/hooks/lib/hook-input.sh`. **Fixed accessors over one constant jq program** — not a
variadic `<VAR> <jq-expr>` API. That alone deletes four of v1's failure modes: no program
interpolation (structurally literal, not literal-by-comment), no odd-argument-count path, no
caller-supplied variable names, no `printf -v`.

```jq
# One CONSTANT program. Field order is the contract.
#   1 .tool_input.command   2 .tool_name   3 .cwd   4 .session_id
#   5 .tool_input.file_path // .tool_input.notebook_path
# The status token is computed BEFORE any value is emitted, so no value can forge it.
# Values on the "bad" path are emitted EMPTY — nothing is coerced, nothing is rendered,
# nothing needs a separator scrub, and no payload content can reach telemetry.
[ (try (.tool_input.command // "") catch {}),
  (try (.tool_name        // "") catch {}),
  (try (.cwd              // "") catch {}),
  (try (.session_id       // "") catch {}),
  (try (.tool_input.file_path // .tool_input.notebook_path // "") catch {}) ]
| (if all(type == "string") then "ok" else "bad" end), "\u001e",
  (.[] | (if type == "string" then . else "" end), "\u001e")
```

```bash
raw=$(printf '%s' "$input" | jq -j "$_HOOK_INPUT_JQ" 2>/dev/null; printf 'X'); raw=${raw%X}
oldifs=${IFS-}; case "$-" in *f*) hadf=1;; *) hadf=0;; esac
set -f; IFS=$'\x1e'
# shellcheck disable=SC2206  # deliberate IFS word-split on RS; globbing disabled above
slots=($raw)
if [[ -n "${oldifs+set}" ]]; then IFS=$oldifs; else unset IFS; fi
(( hadf )) || set +f
(( ${#slots[@]} == 6 )) || return 1        # slot count, NOT jq's exit code
[[ ${slots[0]} == ok ]] || return 1
```

Publishes `HOOK_CMD`, `HOOK_TOOL_NAME`, `HOOK_CWD`, `HOOK_SESSION_ID`, `HOOK_FILE_PATH` and
`HOOK_INPUT_REASON`. **The return code is normative**; the reason is diagnostic. All are initialised
at source time (`set -u`) and reset at the top of every call (a stale `HOOK_INPUT_REASON` inherited
from the environment must not survive).

Properties, each measured:

| Property | Mechanism |
|---|---|
| no `eval` | values read over a pipe, assigned by direct expansion |
| non-string is surfaced, never coerced | leading `all(type=="string")` token ⇒ rc 1 ⇒ `ask` |
| non-object `tool_input` or root ⇒ `ask` | `catch {}` yields an object — non-string — so the same check handles it. No `err` tag, no `has("__e")` branch. **v1 routed this to fail-open: a cheaper payload getting a weaker posture** |
| a value cannot forge a boundary | the program emits exactly 6 records unconditionally; a smuggled separator raises the count and trips the mismatch. Desync is structurally unreachable |
| happy path is byte-exact | `ok` values pass through untouched — no `gsub`, no strip |
| no payload content anywhere | bad-path values are empty by construction |
| NUL needs no handling | jq drops NUL from string values on input and refuses to emit it |
| trailing/empty fields survive | sentinel + trailing separator, as a pair (see Do Not Skim §3) |
| `jq` missing needs no branch | the slot-count check catches it for free; classify by capturing jq's rc |
| `set -u` / glob safety | `${IFS-}`, conditional `set -f` restore, window is exactly two lines with no `return` inside |
| `emit_incident` reachable | source `lib/incidents.sh` **idempotently** from the helper; if still undefined, fall through to `ask` — never continue. v1 deliberately did not source it, so a wrong order made the fault path `command not found` (rc 127) which kills the hook and lets the tool proceed |
| shellcheck clean | `SC2206` + `SC2034` disables, each justified |
| bash 3.2 / jq 1.5 compatible | no `mapfile`, no `declare -n`, no `--raw-output0` |

**Classifiers** (`HOOK_INPUT_REASON`): `nonstring` · `unparseable` · `separator` · `jq_missing` ·
`internal` (our own program broken, or jq present but failing — carry ≤120 bytes of jq stderr, our
bug, no attacker content). Capture jq's exit code for this; discarding it collapses "we shipped a
broken hook" into "the model sent junk".

### Phase 5 — The response

```bash
if ! hook_parse_input "$INPUT"; then
  hook_input_report "<hook-basename>"     # pure; emits incident + stderr; always returns
  hook_input_should_ask && { hook_input_emit_ask "<hook-basename>"; exit 0; }
  exit 0
fi
```

- Three small functions, none of which calls `exit`. The `exit` lives at the call site: explicit,
  greppable, lintable, uniform. v1's single responder sometimes returned and sometimes exited — a
  sourced library terminating its caller invisibly at 20 sites, untestable without a subshell, and
  silently ineffective inside `$( )` or a pipeline. The contract test asserts none of the three is
  ever invoked in a subshell or pipeline.
- **`guardrails.sh` is the designated responder**: it emits the `ask`; the other 17 report and exit 0.
  All-emit turns a persistent condition (`jq_missing`) into an unrecoverable loop — fixing `PATH` is
  itself a Bash call that would ask 18 times. Designated-responder makes `guardrails.sh` load-bearing
  for 17 others, so Do Not Skim §9's `settings.json` assertion is mandatory, not optional.
- **Kill switch:** `SOLEUR_DISABLE_HOOK_INPUT_ASK=1` disables escalation only, never parsing —
  precedent `SOLEUR_DISABLE_SESSION_STATE`. Without it there is no in-band recovery. Document in
  ADR-157 and the README; assert in the suite.
- Telemetry payload: field name, JSON type, length. Nothing else.

### Phase 6 — Migrate the 10 `eval` hooks (commit 1)

`guardrails.sh`, `cla-signed-author-gate.sh`, `context-reviewed-gate.sh`,
`follow-through-directive-gate.sh`, `prod-write-defer-gate.sh`, `ship-net-issue-flow-gate.sh`,
`ship-operator-step-gate.sh`, `ship-runbook-ssh-gate.sh`, `ship-soak-followthrough-gate.sh`,
`ship-unpushed-commits-gate.sh`.

Each maps its locals off the fixed globals, sources the helper fail-hard, keeps `: "${VAR:=}"`.

**Correct the false safety claim in all five places** — the extraction comments in `guardrails.sh`,
`ship-unpushed-commits-gate.sh`, `cla-signed-author-gate.sh`, `prod-write-defer-gate.sh`, and a dated
correction appended to `2026-05-15-deterministic-permissions-empirical-probes-and-review-gaps.md`.
Say "no shell evaluation of hook input" — never "input is now safe".

Do **not** edit `2026-04-18-refactor-drain-pr2213-review-backlog-plan.md` or its archived spec —
point-in-time records holding the risk analysis that missed this bug (it modelled string payloads
only). Cite them in ADR-157.

### Phase 7 — The sibling readers (commit 2)

The 8 `.tool_input.command` readers: `background-poll-prefer-monitor.sh`, `brand-hex-commit-gate.sh`,
`doppler-secrets-delete-redirect.sh`, `git-commit-secret-scan.sh`, `kb-domain-allowlist-guard.sh`,
`no-memory-write.sh`, `pre-merge-auto-close-scan.sh`, `pre-merge-rebase.sh` (the last two read it
inside larger `//` chains — read each before porting), plus the 2 blocking write guards
`worktree-write-guard.sh` and `iac-plan-write-guard.sh`.

**Explicitly exempt, with the reason in the README and a follow-up issue:** the 10 advisory/PostToolUse
hooks reading `.tool_input.file_path` / `.skill` / `.model`. **Scope the README's "mandatory" claim to
Bash-matcher and blocking write hooks** — shipping it unqualified alongside 10 unlisted exemptions is
a claim the lint cannot enforce.

### Phase 8 — The OpenHands mirror (commit 3)

`.openhands/hooks/{guardrails,pre-merge-rebase}.sh`: a minimal in-place non-string guard, **not** the
helper. Extend `tests/hooks/test_openhands_guardrails.sh` with the array payload. File the
convergence follow-up (`domain/engineering`, `type/security`, `priority/p3-low`, `--milestone`).
Separate commit — bisect cleanliness is the plan's own stated reason for splitting.

### Phase 9 — Complete the gate

Finish `hook-input-contract.test.sh` (2.1 and 2.2 already landed RED). Pure bash + `jq`, with the
standard `command -v jq || { echo "SKIP: jq missing"; exit 0; }` preflight.

**Fixtures.** Build **one shared factory** — `git init` + a local bare `origin` + one commit + a
feature branch — reused across the 8 constructible hooks, and prepend a stub-`gh` directory to `PATH`
for all of them (the repo already has the stub convention). This converts the 3 `gh`-gated hooks from
un-canaryable to canaryable and keeps `git fetch origin main` / `gh pr view` / `net-issue-flow.sh`
off the network in the `test-scripts` shard. Every git fixture sets its branch explicitly and runs
from its own CWD — `guardrails.test.sh` documents that CI-on-`main` masks gates (#5192).

Assertions:

1. Idiom ban (any `eval`, two allow-listed exact strings).
2. **Guard-still-armed**, per hook, with the honest coverage split from P24: **7** hooks assert
   end-to-end from a bare payload today; **8** after the git fixture; **3** with the `gh` stub. Do
   not silently degrade the other 11 to "fail-open, as expected".
3. **RCE regression, all 10** — with a **positive control in the same run**: the marker *is* created
   against a pinned vulnerable stub. A bare absence assertion passes if the payload was malformed, the
   path wrong, or stdin never arrived.
4. `permissionDecisionReason` discriminates where normal and anomalous decisions collide —
   `kb-domain-allowlist-guard.sh`'s normal decision is *already* `ask`.
5. Non-object `tool_input`, non-object root, non-string `cwd`, separator-in-value ⇒ `ask`.
6. Lone surrogate ⇒ `ask`. Assert it does **not** silently arm a guard against a scrubbed value.
7. `jq` unusable ⇒ `ask` with **no jq fork** — test by prepending a shim dir with a non-executable
   `jq`, leaving the rest of `PATH` intact (`PATH=/nonexistent` also removes `grep`, `git`, `mktemp`,
   `flock`, so the hook cannot meaningfully run).
8. **Loud disarm, end to end** — the incident row **and** a non-zero `summary.hook_input_fault_count`
   from the aggregator **and** pickup by compound's widened filter. Asserting a line landed in a file
   tests that a write happened, not that anyone is told. Also assert the row honours
   `INCIDENTS_REPO_ROOT` and the worktree ledger is unchanged.
9. No payload content in `command_snippet`.
10. Envelope pairing — every new `permissionDecision` carries `hookEventName` **in the same object**,
    asserted per envelope.
11. `settings.json` designated-responder invariant (Do Not Skim §9).
12. Shell-state hygiene — `IFS` and `$-` byte-identical after every rc path, including `IFS` unset
    under `set -u`, and a `command` whose **entire value** is `*` executed from a temp dir containing
    files (a value of `rm *` cannot catch a missing `set -f`; only a whole-value glob can).
13. No subshell/pipeline invocation of the three response functions; no `$` in any jq expression.
14. Kill switch.
15. **Mechanism ban** (replaces a comparative wall-clock assertion): `lib/hook-input.sh` contains zero
    `explode`, zero `read -d`, zero `mapfile -d`, and exactly one `jq`. Deterministic, milliseconds,
    names the banned construct on failure. Keep the four-size table in the **PR body** — a 14% margin
    does not belong in CI. One loose backstop only: median of 5 interleaved runs at 200 KB,
    `new <= 2 × legacy`, which sits far above the noise and far below the 2.5× minimum regression.
16. Stray-artifact assertion **inside** the test: after each reproducer invocation, the per-run temp
    dir contains exactly the expected file set.
17. Run the **16 existing sibling suites**; write the 2 missing ones
    (`ship-soak-followthrough-gate`, `doppler-secrets-delete-redirect`). This replaces a fresh
    18-fixture canary that would duplicate ~4,600 existing lines.

**Mutation checks**, transcript recorded, each naming *which* protection it removed rather than just
"the suite went RED": type-assert removed · any `eval` restored in a **randomly selected** hook (not
always `guardrails.sh`) · `lib/hook-input.sh` deleted · `lib/incidents.sh` deleted · `catch {}` →
`catch ""` · `${IFS-}` → `$IFS` (with `IFS` unset under `set -u`) · sentinel **and** trailing
separator removed together · `slots=($raw)` → `slots=("$raw")` · `set -f` removed · then restore →
green.

Plus a **static per-file sweep**: each of the 20 hooks has exactly one `source .../hook-input.sh`,
matching neither `|| true` nor `|| :` nor `2>/dev/null`.

### Phase 10 — C4 and README

C4 as below. `.claude/hooks/README.md` gains a "Parsing hook input" section naming
`hook_parse_input`, the **scoped** mandate, the exemption list, the required source order, the
designated responder, the kill switch, and the contract test.

---

## Architecture Decision (ADR/C4)

### ADRs

Two, split by lifetime — Phase 3. Plus `principles-register.md` `AP-NNN`.

### C4 views

All three model files were **read** — `model.c4`, `views.c4`, `spec.c4`. A keyword grep would have
been useless: the gap is a missing *edge*, not a missing noun.

- **External human actors** — `founder`, `emailSender`, `betaContact`, `contributor`. The adversary is
  the model's own tool-call envelope, not a new human role. **No new actor.**
- **External systems** — `anthropic` is modelled and is the envelope's origin, but the envelope is
  *delivered* by the runtime container. **No new system.**
- **Containers / stores** — `platform.engine.hooks` and `platform.engine.claude`, both modelled and
  both already in the L2 `containers` and L3 `components` include-lists.
  `.claude/.rule-incidents.jsonl` is a pre-existing local file, deliberately not modelled (no other
  local telemetry file is). **No new container or store.**
- **Access relationships that change** — exactly one, and it is missing: `model.c4` has
  `hooks -> claude "Guards tool calls"` and **no relationship into `hooks` at all**. The model does
  not represent that the Hook Engine *receives* a model-controlled envelope — the boundary this fix
  establishes, and a gap in an argument the model already makes elsewhere
  (`connectedRepoPlugin -> skillloader` › "IGNORED by the loader (trust boundary)…").

Edit `model.c4` only — both endpoints are already in both views, so LikeC4 renders the edge with no
`views.c4` change:

1. Add `claude -> hooks "Tool-call envelope on stdin — MODEL-CONTROLLED, UNTRUSTED (ADR-156): parsed
   without eval; input that cannot be fully parsed asks, never continues silently (ADR-157)"
   { technology "stdin JSON" }`.
2. Amend `platform.engine.hooks`'s `description`, falsified by omission — it says what hooks *do*,
   never what they *consume*.

Then run `apps/web-platform/test/c4-code-syntax.test.ts` and `c4-render.test.ts`.

---

## Files to Create

- `.claude/hooks/lib/hook-input.sh`
- `.claude/hooks/hook-input-contract.test.sh`
- `.claude/hooks/ship-soak-followthrough-gate.test.sh`
- `.claude/hooks/doppler-secrets-delete-redirect.test.sh`
- `knowledge-base/engineering/architecture/decisions/ADR-156-hook-stdin-is-model-controlled-and-untrusted.md`
- `knowledge-base/engineering/architecture/decisions/ADR-157-a-hook-that-cannot-parse-its-input-asks.md`

## Files to Edit

**Telemetry:** `scripts/rule-metrics-aggregate.sh`, `scripts/rule-metrics-aggregate.test.sh`,
`plugins/soleur/skills/compound/SKILL.md` (+ its tests).

**Commit 1 — the 10:** `.claude/hooks/{guardrails,cla-signed-author-gate,context-reviewed-gate,follow-through-directive-gate,prod-write-defer-gate,ship-net-issue-flow-gate,ship-operator-step-gate,ship-runbook-ssh-gate,ship-soak-followthrough-gate,ship-unpushed-commits-gate}.sh`

**Commit 2 — the 8 + 2 write guards:** `.claude/hooks/{background-poll-prefer-monitor,brand-hex-commit-gate,doppler-secrets-delete-redirect,git-commit-secret-scan,kb-domain-allowlist-guard,no-memory-write,pre-merge-auto-close-scan,pre-merge-rebase,worktree-write-guard,iac-plan-write-guard}.sh`

**Commit 3 — mirror:** `.openhands/hooks/{guardrails,pre-merge-rebase}.sh`,
`tests/hooks/test_openhands_guardrails.sh`

**Docs / model / memory:** `.claude/hooks/README.md`,
`knowledge-base/engineering/architecture/diagrams/model.c4`,
`knowledge-base/engineering/architecture/principles-register.md`,
`knowledge-base/project/learnings/2026-05-15-deterministic-permissions-empirical-probes-and-review-gaps.md`

**Re-run, edit only if genuinely broken:** the 16 existing hook sibling suites;
`hookeventname-coverage.test.sh`; `grep-q-pipe-guard.test.sh`; `stub-argv-fidelity.test.sh`;
`tests/hooks/test_hook_emissions.sh`; `.claude/hooks/pre-merge-rebase-parity.test.sh`.

No `SKILL.md` `description:` changes, so the skill-description budget check does not apply.

---

## Acceptance Criteria

### Pre-merge (PR)

1. **AC1 — RCE closed, all 10**, with a positive control in the same run proving the harness can
   observe a marker. *(Issue AC #1.)*
2. **AC2 — guards still armed.** Array payloads encoding guarded commands yield `ask`, never an allow:
   7 hooks from a bare payload, 8 more via the shared git fixture, 3 via the `gh` stub. Coverage is
   stated per hook; none is silently degraded.
3. **AC3 — the cheap variants also ask.** Non-object `tool_input`, non-object root, non-string `cwd`,
   separator-in-value, lone surrogate, unusable `jq`.
4. **AC4 — no `eval` remains.** Any `eval` under `.claude/hooks/**` and `.openhands/hooks/**` except
   the two allow-listed exact strings.
5. **AC5 — loud disarm, end to end.** Incident row **and** non-zero
   `summary.hook_input_fault_count` **and** compound pickup **and** `INCIDENTS_REPO_ROOT` honoured.
   *(Issue AC #2 — the extra conjuncts are what make it true.)*
6. **AC6 — no payload content persisted.**
7. **AC7 — every mutation in Phase 9 turns the suite RED with a message naming the removed
   protection**, then green after restore. *(Issue AC #3.)*
8. **AC8 — hot path within budget.** The in-situ table reproduced in the PR body; ≤ **+20%** per
   invocation at 100 B / 2 KB / 20 KB / 200 KB. **No 10 MB clause** — v1's was derived from a jq-only
   measurement and applied end-to-end, where neither the new design nor the code it replaces meets it.
9. **AC9 — one jq fork on the happy path**, asserted as a runtime fork count (a grep over-counts:
   `emit_incident` forks jq).
10. **AC10 — the `ask` envelope is built by `printf`**, verified by an unusable-`jq` run.
11. **AC11 — shell-state hygiene** across every rc path, including a whole-value glob and `IFS` unset
    under `set -u`.
12. **AC12 — kill switch** suppresses escalation and nothing else.
13. **AC13 — envelope pairing**, asserted per envelope.
14. **AC14 — designated-responder invariant** over `.claude/settings.json`.
15. **AC15 — syntax + lint.** `bash -n` everywhere; `shellcheck -s bash -x` **zero findings** with
    exactly the two justified `disable=` directives; output in the PR body (CI does not gate `.sh`).
16. **AC16 — suite discovery + non-vacuous execution.** The run output contains the literal
    `--- .claude/hooks/hook-input-contract.test.sh ---` line **and** the suite's own
    `=== hook-input-contract: N/M pass ===` trailer with `M >= <expected>`. (A bare
    `N >= pre-change + 1` count is satisfied by any new suite, is shard-dependent, and passes on a
    jq-skipped or empty file.)
17. **AC17 — no stray artifacts**, asserted inside the test per invocation.
18. **AC18 — false claims corrected.** `git grep -nE '@sh (shell-)?escapes|eval is safe' -- '.claude/hooks/*.sh'`
    is zero; the 2026-05-15 learning carries a dated correction citing #7164 and does not contain
    "input is now safe"; **and the PR body makes no `echo`-vs-`printf` security claim** (P22).
19. **AC19 — C4 valid.** `model.c4` has `claude -> hooks` naming ADR-156 and "UNTRUSTED";
    `cd apps/web-platform && ./node_modules/.bin/vitest run test/c4-code-syntax.test.ts test/c4-render.test.ts` passes.
20. **AC20 — both ADRs exist** with `status: accepted`, a `## Decision`, and ADR-157's
    `## Alternatives Considered` naming fail-closed, coerce-and-continue, per-field `jq -r`,
    `--raw-output0`, the per-session counter, the surrogate scrub, and the size cap.
21. **AC21 — exemptions listed.** The README scopes the mandate and names the 10 exempt hooks and the
    follow-up issue.
22. **AC22 — full suite green.** `bash scripts/test-all.sh` exits 0.
23. **AC23 — `Closes #7164`** in the PR body, not the title.

### Post-merge (operator)

None as an operator action. Verification is `bash scripts/test-all.sh scripts` on `main`, run by the
agent. The kill switch (AC12) is the documented in-band recovery path if the `ask` posture proves
noisy — an escape hatch, not a scheduled step.

---

## Test Scenarios

T1 normal string, byte-exact · T2 metachars/newline/backtick/`$( )`/quotes · T3 a value that is
**exactly** `*` from a temp dir containing files · T4 a last field ending `\n\n` · T5 unicode ·
T6 null/absent `command` (asserted at helper level: rc 0, empty, **no incident row**) · T7 `{}` ·
T8 all-empty fields · T9 array `command` ⇒ ask · T10 object/number/bool ⇒ ask · T11 non-string `cwd`
⇒ ask · T12 non-object `tool_input` ⇒ ask · T13 non-object root ⇒ ask · T14 escaped `\u001e` in a
value ⇒ ask · T15 a **literal** RS byte (0x1e) (invalid JSON) ⇒ ask, distinct row · T16 lone high surrogate
from `python3 json.dumps` carrying **also** a valid escaped pair ⇒ ask, emoji unharmed · T17
unusable `jq` ⇒ ask, no fork · T18 broken jq program ⇒ `internal` ⇒ ask · T19 malformed / empty /
truncated stdin ⇒ ask + incident · T20 200 KB value intact · T21 `IFS` unset under `set -u` · T22
`IFS`/`$-` restored on every rc path · T23 inherited `HOOK_INPUT_REASON` does not survive a call ·
T24 kill switch · T25 the 16 existing sibling suites still pass.

No scenario is satisfied by "the hook exited 0 and printed nothing" — every one asserts a decision, a
helper-level value, or an incident row.

---

## Observability

```yaml
liveness_signal:
  what: "summary.hook_input_fault_count and per-reason counts in the rule-metrics aggregate; zero is healthy"
  cadence: "per PreToolUse fault only (O(0) on the happy path); aggregated by the local compound flow"
  alert_target: "the in-band permissionDecision=ask (synchronous, operator-visible), backed by scripts/rule-metrics-aggregate.sh's stderr line and compound Phase 3.5"
  configured_in: ".claude/hooks/lib/hook-input.sh (emitter); scripts/rule-metrics-aggregate.sh (counter + stderr); plugins/soleur/skills/compound/SKILL.md (Phase 3.5 filter)"
error_reporting:
  destination: "in-band permissionDecision=ask — the only channel a PreToolUse hook provably owns — plus .claude/.rule-incidents.jsonl and headless_or_stderr warn"
  fail_loud: true
failure_modes:
  - mode: "a contracted field is not a string (the attack signature)"
    detection: "reason=nonstring; ask whose reason names the hook and the field"
    alert_route: "operator sees the prompt synchronously; the row is the forensic record"
  - mode: "root or tool_input is not an object"
    detection: "reason=nonstring via catch {}; ask"
    alert_route: "same — this cell fail-opened in v1 and is the cheapest evasion to write"
  - mode: "a value carries the field separator"
    detection: "reason=separator (slot-count mismatch); ask"
    alert_route: "same; distinguishes a boundary-forge attempt from a parse bug"
  - mode: "document unparseable, truncated, or carrying a lone high surrogate"
    detection: "reason=unparseable; ask. NOT scrubbed-and-armed: a scrubbed value no longer matches the guards (measured)"
    alert_route: "a rising count means the harness emits unpaired UTF-16 — worth an upstream report"
  - mode: "jq unusable"
    detection: "reason=jq_missing; ask emitted by printf with NO jq fork — emit_incident itself needs jq, so the ask reason string is the surviving channel"
    alert_route: "operator sees the prompt immediately; the reason names the hook"
  - mode: "our own jq program is broken (a hook shipped with a bad expression)"
    detection: "reason=internal carrying <=120 bytes of jq stderr (our bug, no attacker content); ask"
    alert_route: "never collapses into 'the model sent junk' — a broken hook must not silently disarm"
  - mode: "the eval idiom is reintroduced by a future hook"
    detection: "hook-input-contract.test.sh idiom ban (any eval), test-scripts CI shard, every PR"
    alert_route: "CI red on the PR that reintroduces it"
logs:
  where: ".claude/.rule-incidents.jsonl (flock-guarded, rotated by lib/log-rotation.sh); stderr via headless_or_stderr. NOTE: the headless branch writes to <git-common-dir>/soleur-session-state/logs/$PPID.log, which has NO reader and NO rotation — a forensic tail, not an alert channel. The alert channel is the in-band ask plus the aggregate counter."
  retention: "governed by the existing per-write rotator in .claude/hooks/lib/log-rotation.sh"
discoverability_test:
  command: "R=$(mktemp -d); printf 'not-json' | INCIDENTS_REPO_ROOT=\"$R\" bash .claude/hooks/guardrails.sh | jq -r '.hookSpecificOutput.permissionDecision'; INCIDENTS_REPO_ROOT=\"$R\" bash scripts/rule-metrics-aggregate.sh | jq '.summary.hook_input_fault_count'"
  expected_output: "\"ask\" on the first line, then a non-zero count — proving the operator is told synchronously AND that the fault reaches the surface a human reads later"
```

Per §2.9.2 (blind execution surfaces): a `PreToolUse` hook is operator-blind — stdout is consumed by
the harness, stderr is usually swallowed, and the headless log has no reader. The `ask` envelope is
therefore the **in-surface, synchronous** probe and the `reason` classifier discriminates all seven
hypotheses in one event. v1 routed everything to a fire-and-forget file write that, after its own
orphan-gate exclusion, no consumer surfaced — which is why the discoverability test asserts the
decision **and** the aggregate counter, never the log line alone.

---

## Domain Review

**Domains relevant:** Engineering. Product/UX Gate tier **NONE** — the mechanical UI-surface override
does not fire. Marketing, Sales, Finance, Legal, Operations, Support: not relevant.

Six passes ran: **CTO**, **security-sentinel**, **silent-failure-hunter**, **architecture-strategist**,
**test-design-reviewer**, **code-simplicity-reviewer**, plus a 20-claim verify-the-negative sweep
(20/20 CONFIRMS).

- **CTO** — shared-helper risk LOW; the single-point-of-failure objection fails because the hooks are
  already centralized by byte-identical copy-paste. Folded: fail-hard source, telemetry-before-emit,
  RED-lint-before-migration, mirror gets a parity test not the helper. Its "5 sibling files" count was
  corrected to 8.
- **security-sentinel** — v1 verdict **do not merge as designed**; four properties falsified. All
  resolved. What it could not break and v3 preserves: no code execution, no boundary forge, desync
  structurally unreachable, truncated jq output fails safe, deep nesting returns a parse error.
- **silent-failure-hunter** — v1 verdict **"does not fix defect 2, it relabels it."** The decisive
  finding (the orphan-gate exclusion deletes the only surface) is the reason Phase 1 now has four
  steps and the `ask` is the primary channel.
- **architecture-strategist** — three blocking findings (untraversable ⇒ ask, oversize ⇒ ask, cut the
  counter), all applied, plus the ADR split, the kill switch, the responder split, and the exemption
  list.
- **test-design-reviewer** — scored v1's strategy **5.9/10 (D)**. Folded: assertion 2 must land RED in
  Phase 2, the 18-hook canary was un-runnable for 11 hooks, six mutations were uncaught, AC1/T4/T7/T10
  were vacuous, AC6's 10 MB clause was unreachable, AC11's suite count was weak, and the `echo` claim
  did not reproduce.
- **code-simplicity-reviewer** — measured a simplified alternative at the same performance envelope
  with ~55% less new code. Its leading-status-token move and its "widen `ask` and the other cuts become
  safe" argument are the spine of v3.

---

## GDPR / Compliance Gate

Canonical regulated-surface regex does not match; invoked because trigger (b) fires
(`single-user incident`).

The only data movement is one row type in the pre-existing local `.claude/.rule-incidents.jsonl`,
which never leaves the machine. The material control is structural: **failure-path values are emitted
empty by the jq program**, so no rendering of attacker content exists to log. **This assessment is
made against v3 specifically** — v1's Observability block logged a `tojson` rendering while its GDPR
section claimed the opposite, so an array `["curl","-H","Authorization: Bearer sk-…"]` would have hit
disk. That contradiction is resolved by construction, not by prose. No new processing activity, no
lawful-basis question, no Art. 30 entry. **Advisory only — not legal advice.**

---

## Open Code-Review Overlap

`gh issue list --label code-review --state open` (62 open), then a `contains($path)` scan per planned
path. One incidental match — `#2348: vitest: mock-factory export drift…` — matched only because
`.claude/hooks/` appears in its body. **Disposition: acknowledge**; different concern, different
runner, no shared file. No other open code-review issue names any file in `Files to Create/Edit`.

---

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| **`ask` fatigue** | `ask` now fires only when the input cannot be fully parsed, which should be never in normal operation. The designated responder collapses 18 simultaneous asks to one. `SOLEUR_DISABLE_HOOK_INPUT_ASK=1` is the in-band escape hatch and disables escalation only |
| **Designated responder is a hidden coupling** | Do Not Skim §9 + AC14: a `settings.json` assertion that every matcher containing a migrated hook also contains `guardrails.sh` |
| **A helper bug disarms all 20** | The status quo is 20 copies of the same bug. Discharged by the 16 existing sibling suites plus the mutations that delete the helper *and* `incidents.sh` |
| **Scope: 20 hooks + 2 mirrors across 3 commits** | Split by concern so the P0 half can ship alone. Shipping 10 retires #7164 while the majority of Bash-path gates stay evadable — a false-negative security close |
| **The `source` cost (~9 ms × 18 per Bash call)** | Measured; AC8 pins +20%. The zero-extra-source option (append into the already-sourced `lib/incidents.sh`) is in Alternatives if the budget is missed |
| **jq version drift** | RS avoids the jq ≥ 1.7 `--raw-output0` dependency; only jq ≥ 1.5 features are used. Phase 0.2 measures RS emission on the installed jq |
| **CI wall-clock** | Every network collaborator is stubbed; the comparative perf assertion is replaced by a deterministic mechanism ban plus one loose 2× backstop |
| **Parity guards trip** | Both are in the re-run list; commit 3 touches the mirror deliberately, so expectations are refreshed — never silenced |
| **Aggregator red on the first post-merge run** | Phase 1 lands the exclusion *and* the replacement counter before any emit; AC5 asserts both |
| **Reintroduction** — nine commits copied this idiom into nine hooks over four months | The idiom ban (any `eval`) is the durable control. Prose did not stop copy-paste; a red CI check does |

---

## Alternatives Considered

| Alternative | Verdict |
|---|---|
| **Keep `eval` + `tojson` coercion** (issue suggestion 1) | **Rejected — falsified.** Closes the RCE, leaves every anchored guard evaded, rc 0, no incident |
| **NUL + `mapfile -d ''`** (issue suggestion 2) | **Rejected as written.** jq drops NUL; `--raw-output0` needs jq ≥ 1.7; `mapfile -d` needs bash ≥ 4.4; both delimited-read forms are 2.5× regressions at 200 KB. The direction (drop `eval`) is adopted |
| **`explode` separator strip** (v1) | **Rejected — 8.55 s / 180 MB on 10 MB**, ×18 parallel hooks |
| **`read -d` / `mapfile -d`** (v1) | **Rejected — 14348 ms vs a 5643 ms baseline** at 200 KB |
| **Variadic `<VAR> <jq-expr>` API** (v1) | **Rejected.** The fixed-accessor form is less code and structurally deletes program interpolation, odd argc, caller-supplied names, and `printf -v` failure |
| **Per-field `ok`/`anom`/`err` tags** (v1) | **Rejected.** A leading `all(type=="string")` token computed before any value cannot be forged by a value, halves the slot count, and makes the RS scrub and the `tojson` rendering unnecessary — which also removes the GDPR contradiction |
| **Scrub lone surrogates and run the guards armed** (v1) | **Rejected — measured.** `git ␦ stash` does not match the stash guard. Filed as a follow-up if surrogate rows actually appear |
| **256 KB cap, oversize ⇒ fail-open** (v1) | **Rejected.** One-line padding disarm; fires on routine large `Write` payloads (this repo tracks an 806 KB lockfile); `${#input}` counts characters, not bytes |
| **Per-session counter** (v1) | **Rejected — no session identity, circular key, falsified bound.** With no fail-open cell there is no oracle to bound |
| **Fail closed on parse failure** | **Rejected**, recorded in ADR-157. Bricks the session with no in-band recovery |
| **Fail open with a loud incident** (v1) | **Rejected.** Not loud: a `PreToolUse` hook is operator-blind, the incident is read by an aggregator later, and the operator whose gates just went dark learns nothing now |
| **All-emit `ask`** | **Rejected.** Turns `jq_missing` into an unrecoverable loop — fixing `PATH` is itself a Bash call |
| **Per-field `VAR=$(… jq -r …)`** — the mirror's shape | **Rejected.** N forks per hook per call, reverting #2253 across 20 hooks, and it still needs the type-assert |
| **Runtime startup canary** (issue suggestion, read literally) | **Rejected in the hot path, adopted in the suite** — and largely already present: 16 hooks ship sibling suites asserting their characteristic decision |
| **Append the helper into `lib/incidents.sh`** | **Not taken, recorded.** Removes the ~9 ms/invocation source cost at the price of coupling parsing to telemetry. Revisit only if AC8 is missed |
| **Converge the OpenHands mirror now** | **Rejected for this PR.** Different envelope, different deny shape, not RCE-vulnerable |
| **A new AGENTS.md `cq-*` rule** | **Rejected.** It would fit (`B_ALWAYS=42547` of 46000), but a red CI check is fail-closed and costs zero always-loaded bytes |
| **Fix only `guardrails.sh`** | **Rejected.** All 10 confirmed vulnerable; 18 hooks fire per Bash call |

---

## Sharp Edges

- **A fix that closes an RCE can open a guard evasion in the same line.** Whenever the remedy for
  hostile input is *normalization* — coercion, scrubbing, transliteration, case-folding — re-run the
  downstream matcher against the normalized value. "It can no longer execute" is not "the guard still
  fires". This plan committed the error twice (`tojson`, then the surrogate scrub) and caught it both
  times only because a reviewer ran the real regex.
- **Benchmark the hostile size, not the typical one** — and **a micro-benchmark is not the shipped
  cost.** The design that won every micro cell was ~8-16% *slower* in situ, because an extra `source`
  dominates a hook whose total is ~80 ms.
- **A measurement that produces the same result with and without the mechanism is not evidence for
  the mechanism.** v1 cited "all-empty case → 4 slots" as proof the sentinel was load-bearing; the
  sentinel and the trailing separator are redundant *with each other*, so only removing both loses
  data.
- **A cheaper payload must not get a weaker posture.** v1 routed `{"tool_input":["a"]}` — one
  character cheaper than the array — to fail-open while the array got `ask`.
- **`read -d` on a pipe reads one byte per syscall.** `$( )` capture + `IFS` word-split is the fast
  form and works on bash 3.2.
- **`jq` cannot emit NUL from a string literal and drops it from input string values.**
- **The field count, not jq's exit code, is the parse-failure detector** (empty stdin gives rc 0 with
  no output) — but capture the code anyway, or "we shipped a broken hook" collapses into "the model
  sent junk".
- **`try … catch ""` makes an unreadable field indistinguishable from a clean empty one.** Catch to a
  distinguished value.
- **`local o=$IFS` kills the shell under `set -u` when `IFS` is unset** — silently, exiting non-zero,
  so the tool proceeds. **`set +f` unconditionally *enables* globbing** for a caller that had it off.
  And only a value that is **entirely** a glob (`*`) can catch a missing `set -f`; `rm *` cannot.
- **A sourced library that calls `exit` terminates its caller invisibly**, is untestable without a
  subshell, and silently no-ops inside `$( )` or a pipeline.
- **A lower-layer helper must not call upward into functions it does not source** — `command not
  found` under `set -euo pipefail` kills the hook and the tool proceeds.
- **The emitter needs the very thing that is missing.** `emit_incident` builds its row with `jq -nc`,
  so a `jq_missing` fault cannot be recorded through it, and its fallback sentinel carries no
  `rule_id` — which every consumer is contractually required to discard.
- **Adding an orphan-gate exclusion can delete the only surface a signal has.** The aggregator
  left-joins over AGENTS.md ids. The correct precedent is `drops_jq_fail_count` — a first-class
  summary counter with an stderr line. And **`event_type: warn` is invisible to compound**, which
  filters to `deny|bypass`.
- **A ban pinned to one spelling is not a ban.** `eval "$(` misses `eval $(…)`, `eval "$V"`, and
  `eval "${x}"`.
- **An absence assertion needs a positive control in the same run**, or it passes when the payload was
  malformed, the path wrong, or stdin never arrived.
- **"The suite went RED" is the least atomic mutation signal there is** — it cannot say which
  protection was removed, and one loud failure masks a second silent one.
- **Do not promote a 14% timing margin to a CI assertion.** Ban the mechanism deterministically; keep
  the table in the PR body; use a 2× backstop if you want one.
- **Most hooks cannot deny from a bare stdin payload** — 7 of 18 can; 8 need a git fixture, 3 need a
  `gh` stub. A canary that skips the other 11 silently degrades to "fail-open, as expected".
- **Where a hook's normal decision is already `ask`** (`kb-domain-allowlist-guard.sh`), assert
  `permissionDecisionReason`, not the decision string.
- **CI-on-`main` masks gates** (#5192) — every git fixture sets its branch explicitly and runs from
  its own CWD.
- **Do not run the reproducer from the repo root**, and use a fresh temp dir — stale markers either
  false-fail or self-satisfy.
- **`shellcheck` is not a CI gate for `.sh` here, `bats` is not installed, and the `test-scripts`
  shard has no bun and no node.**
- **Source the helper fail-hard.** The mutation that *deletes* the file is what proves it.
