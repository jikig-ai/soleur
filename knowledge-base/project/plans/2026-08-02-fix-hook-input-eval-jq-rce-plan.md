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
adr: ADR-155
---

# fix(security): `eval` over `jq @sh` output in 10 PreToolUse hooks executes attacker-named commands

> Spec lacks valid `lane:` — no `knowledge-base/project/specs/feat-one-shot-7164-hook-eval-jq-rce/spec.md`
> exists, so the lane defaulted to `cross-domain` (TR2 fail-closed).

## Overview

Every blocking `PreToolUse` hook in `.claude/hooks/` extracts its input fields with one line:

```bash
eval "$(echo "$INPUT" | jq -r '@sh "COMMAND=\(.tool_input.command // "") TOOL_NAME=\(.tool_name // "")"' 2>/dev/null || echo 'COMMAND="" TOOL_NAME=""')"
```

`jq`'s `@sh` shell-quotes **each element of an array as a separate word**. A `tool_input.command`
that is an array renders as `COMMAND='x' 'touch' '/tmp/PWNED' TOOL_NAME='Bash'` — bash reads word 1
as an environment assignment and **words 2 and onward as a command**, which `eval` executes. This
runs on every matching tool call, **before the permission prompt**, with full operator privileges.

A **second, independent defect** sits in the same line: `|| echo 'COMMAND=""'` means a `jq` parse
failure empties every field, so every guard in that file no-ops with `exit 0` and **no incident is
emitted**. Fail-open is the right *direction* for a blocking gate — one that denies on a `jq` hiccup
bricks the session with no in-band recovery (editing the hook is itself gated by `guardrails.sh` on
`Write|Edit`) — but the *invisibility* of the disarm is the defect.

**A third defect, found during this plan's design review, is the one that decides the shape of the
fix:** the remedy the issue proposes first — coercing non-strings with `tojson` — closes the RCE and
**leaves the guards evaded**. `["git","stash"]` becomes the string `["git","stash"]`, which
`grep -qE '(^|[;&|]|\s)git\s+stash(\s|$)'` does not match. Ship that and #7164 closes while
`hr-never-git-stash-in-worktrees`, the commit-to-main guard, and the `gh pr merge` gates all remain
bypassable by the identical one-line payload — a false-negative security close. The same payload
*already* evades the 8 sibling hooks that read `.tool_input.command` with plain command
substitution, because `jq -r` pretty-prints an array across multiple lines.

So the fix is not "stop using `eval`". It is a **posture**, recorded in ADR-155:

| Input condition | Posture | Rationale |
|---|---|---|
| parses, every contracted field is a string | run the guards normally | the happy path, and it must get *faster*, not slower |
| parses, a contracted field is **not** a string | **`permissionDecision: "ask"`** + incident | a non-string `command` has no legitimate caller; this is the attack signature itself, and must never reach a regex guard as a JSON blob |
| does not parse (malformed, truncated, lone surrogate) | fail **open** + incident + stderr | no adjudicable payload exists; denying bricks the session |
| repeated parse failure in one session (> 3) | escalate to `ask` for the session | bounds the disarm oracle |
| `jq` not executable | **`ask`** immediately | a missing interpreter is categorically different from malformed input and must not silently disarm 18 gates |

**Closes #7164.**

### Blast radius

`.claude/settings.json` registers **18** `PreToolUse` hooks on the `Bash` matcher — 10 with the
`eval`, 8 reading `.tool_input.command` via `$( )`. One crafted array payload detonates the `eval`
in 10 processes *and* evades the anchored guards in all 18. `guardrails.sh` is registered a second
time on `Write|Edit|MultiEdit|NotebookEdit`, so the freeze edit-lock is on the same payload's path.

---

## Premise Validation

Every claim was re-verified by execution in this worktree on 2026-08-02. Nothing was taken on
paraphrase, including my own.

| # | Premise | Verification | Result |
|---|---|---|---|
| P1 | `git grep -lE 'eval "\$\(echo "\$INPUT" \| jq -r .@sh' .claude/hooks/*.sh` returns 10 | ran verbatim | **HOLDS** — exactly the issue's 10 files |
| P2 | `jq @sh` splits an array into separate shell words | ran the issue's jq line | **HOLDS** — `COMMAND='x' 'touch' '/tmp/P'` |
| P3 | The reproducer creates a marker file | ran it against **all 10** hooks, `INCIDENTS_REPO_ROOT` redirected | **HOLDS** — `RCE CONFIRMED` ×10 (third independent confirmation) |
| P4 | Issue #7164 open, unfixed on `main` | `gh issue view 7164` | **HOLDS** — `OPEN`, `priority/p0-critical`, `type/security` |
| P5 | The `eval` exists to preserve a one-fork hot path | `git log -S'@sh' -- .claude/hooks/guardrails.sh` → `8a8b22360` (#2573), closing #2253 | **HOLDS** — the motivation is **one jq fork**, not the `eval`. Fork count must be preserved; the idiom need not be |
| P6 | "force a scalar with `tojson`" is a sufficient fix | ran the coerced value against the real guard regexes | **FALSIFIED** — closes the RCE, leaves the guard evaded. Drives the whole design (see Overview) |
| P7 | "read NUL-delimited fields via `mapfile -d ''`" | `jq -j '"a","\u0000","b"'` → `ab` | **FALSIFIED as written** — jq **silently drops `\u0000`** from string literals *and* from input string values. NUL is reachable only via `jq --raw-output0` (jq ≥ 1.7); `mapfile -d` also needs bash ≥ 4.4. `\u001e` (U+001E, RS) **is** emitted literally and works on old jq and bash 3.2 |
| P8 | The proposed extractor is not slower than the `eval` | benchmarked 4 read mechanisms × 4 payload sizes × 100 iters, plus a 10 MB single-shot | **CONDITIONAL — see the table below.** Two of the four candidate designs are severe regressions. Only one beats the baseline |
| P9 | `shellcheck` is clean on the candidate helper | `shellcheck -s bash` | **FALSIFIED** — `SC2034: n appears unused`. Fixed in the design below |
| P10 | Phase 4 is "~16 files" (my first draft) / "5 files" (CTO review) | `git grep -l 'tool_input\.command'` over every non-test hook, minus the eval-10 | **BOTH WRONG.** It is **8** in `.claude/hooks/` (`background-poll-prefer-monitor`, `brand-hex-commit-gate`, `doppler-secrets-delete-redirect`, `git-commit-secret-scan`, `kb-domain-allowlist-guard`, `no-memory-write`, `pre-merge-auto-close-scan`, `pre-merge-rebase`) plus **2** in `.openhands/hooks/`. 10 eval + 8 = the 18 Bash-matcher hooks |
| P11 | `permissionDecision: "ask"` is honored by the harness | `.claude/hooks/DEFER-DECISION-PAYLOAD-SHAPE.md` › probed comparison table (CC 2.1.142): `ask` + `hookEventName` → **bash NOT executed**, agent-visible message. `kb-domain-allowlist-guard.sh` ships it in production today | **HOLDS — no new probe needed.** Re-probe trigger is a CC major bump, per that document |
| P12 | `bats` is available / `shellcheck` gates `.sh` in CI | `command -v bats`; read `.github/workflows/ci.yml` | **BOTH FALSE.** No bats, zero `.bats` files. `shellcheck` runs in CI only via `actionlint` on workflow `run:` bodies — repo `.sh` files are **not** gated. The de-facto syntax gate is a per-test `bash -n` |
| P13 | `.claude/hooks/*.test.sh` is auto-discovered | read `scripts/test-all.sh` › the `want_scripts` suite loop | **HOLDS** — the glob list includes `.claude/hooks/*.test.sh`; zero registration needed. It runs in the `test-scripts` CI shard, which has **no bun and no node** |
| P14 | There is room for a new AGENTS.md rule | `python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.rules.md` → `[OK] B_ALWAYS=42547` vs the 46000 cap | **HOLDS** (~3.4 kB headroom) — the plan still declines it, see Alternatives |
| P15 | ADR-131's gate moratorium blocks a new CI gate | read `ADR-131` frontmatter + preamble | **FALSE** — `status: proposed`, and its own preamble says "This ADR decides nothing." |
| P16 | Next free ADR ordinal | highest is `ADR-154-repair-the-credential-channel-not-the-host.md` | **155 free — PROVISIONAL.** `/ship`'s ADR-Ordinal Collision Gate re-verifies against `origin/main`; a renumber must sweep this plan, `tasks.md`, and every AC naming it |

### P8 in full — the hot-path measurement that reshaped the design

100 iterations per cell, ms, `bash 5.3.9` / `jq 1.8.1`, interleaved to control for machine load.
"legacy" is the `eval` form being replaced.

| payload | legacy `eval` | `read -d` loop | `mapfile -d` | **`$( )` capture + IFS** | `explode` strip |
|---|---|---|---|---|---|
| 100 B | 858 | 910 | 969 | **932** | 922 |
| 2 KB | 859 | 992 | 909 | **908** | 1278 |
| 20 KB | 1621 | 2585 | 2237 | **1278** | 4159 |
| 200 KB | 5643 | 14348 | 14620 | **4880** | 33091 |

Single 10 MB `command`, one shot, `/usr/bin/time`:

| jq program | wall | maxRSS |
|---|---|---|
| `contains`-guarded strip (**chosen**) | **0.15 s** | **23 MB** |
| legacy `@sh` | 0.70 s | 43 MB |
| `explode \| map(select(...)) \| implode` | 8.55 s | 180 MB |

Two conclusions, both load-bearing:

1. **`explode` is out.** It materializes a boxed integer per codepoint. At 10 MB × 18 parallel
   hooks that is minutes of CPU and gigabytes of RSS from one model-emitted tool call — a
   self-inflicted session hang the *current vulnerable code does not have*. The plan's first draft
   contained it; the security review measured it; it is deleted.
2. **`read -d` on a pipe is out.** Bash reads a delimited record from a non-seekable fd
   byte-at-a-time; at 200 KB it is a 2.5× regression. `mapfile -d` is no better. The `$( )` capture
   + `IFS`-splitting form (with globbing disabled) is the **only** mechanism that beats the baseline
   at every size, and it works on bash 3.2.

The resulting hook is therefore **faster and leaner than the code it replaces**, not merely
not-slower.

---

## Research Reconciliation — Spec vs. Codebase

| Issue / prior-art claim | Codebase reality | Plan response |
|---|---|---|
| Fix by forcing a scalar with `tojson` | Closes RCE, **leaves the guard evaded** (P6) | Type-**assert**, do not coerce. Non-string ⇒ `ask` + incident |
| Fix by `mapfile -d ''` on NUL | jq cannot emit NUL without `--raw-output0` (jq ≥ 1.7); `mapfile -d` needs bash ≥ 4.4; `read -d` on a pipe is a 2.5× regression (P7, P8) | RS (`\u001e`) delimiter + `$( )` capture + `IFS` split |
| `emit_incident "guardrails-input-parse-failure"` | `scripts/rule-metrics-aggregate.sh` › orphan-gate **hard-`ERROR`s** on any `rule_id` absent from AGENTS.md unless its prefix is allow-listed (`te-`, `gdpr-gate-`, `context-reviewed-`, `net-issue-flow`, `cost-of-filing-`) | One repo-wide prefix `hook-input-*`; extend the exclusion **and its test** in the same PR, ordered **before** the first emit |
| "a startup canary fed a known-deny fixture" | A canary in the `PreToolUse` hot path re-runs a full hook on every tool call — the exact cost #2253 removed | Canary lands as a **suite** gate, not a runtime probe. Runtime signal is the incident, O(0) on the happy path |
| Issue scopes the defect to 10 files | 8 more hooks read `.tool_input.command` via `$( )` and are evaded by the same payload; total Bash-matcher surface is 18 (P10) | Sweep all 18 in one PR, as two commits (eval sites, then `$( )` sites) so review and bisect stay clean |
| The fallback is justified by learning `2026-03-18-stop-hook-jq-invalid-json-guard.md` ("the parse-error exit code must be explicitly absorbed with `\|\| true`") | Correct about *absorbing*, silent about *announcing* | ADR-155 must explicitly supersede that reading, or the next author reinstates the silent disarm |
| `.openhands/hooks/guardrails.sh` mirrors `guardrails.sh` | Reads a **different envelope** (`.working_dir`, `.tool_input.path`) and a different deny shape (`{"decision":"deny"}`). Not RCE-vulnerable; **is** evadable. Parity guards: `tests/hooks/test_openhands_guardrails.sh`, `.claude/hooks/pre-merge-rebase-parity.test.sh` | Do **not** converge the mirror on the helper under P0 time pressure — making `hook_parse_input` envelope-agnostic is real abstraction bought with security urgency. Apply a minimal in-place non-string guard to the 2 mirror files + extend the parity test. Convergence is a follow-up |
| `security_reminder_hook.py` is the Python sibling | `json.loads` + `.get()`, and `isinstance(new_string, str)` — the **only** pre-existing explicit type-check on model-controlled input in the repo | Not vulnerable; **state that in the PR body** so the sweep reads as complete rather than partial. Cite it in the ADR as the precedent bash is converging on |
| — | **A knowledge-base learning records the false claim as confirmed:** `knowledge-base/project/learnings/2026-05-15-deterministic-permissions-empirical-probes-and-review-gaps.md` › "security-sentinel — confirmed jq @sh-escape neutralizes stdin command injection" | Institutional memory that will re-authorize this idiom. Append a dated correction pointing at #7164/ADR-155 — do not rewrite the historical finding, and do not let the correction overstate ("no shell evaluation of hook input", never "input is now safe") |
| — | `ship-soak-followthrough-gate.sh` is the one hook of the 10 with **no** `.test.sh` sibling | Covered by the new matrix test; a dedicated sibling is out of scope |
| — | `grep-q-pipe-guard.test.sh` sweeps `.claude/hooks/*.sh` **and** `.claude/hooks/lib/*.sh` for `\| grep -q`, asserting **zero** | The new `lib/hook-input.sh` will be swept — it must contain no pipe-into-`grep -q` |

---

## User-Brand Impact

**If this lands broken, the user experiences:** every `Bash` tool call either aborts with a bash
error printed into the transcript, or hangs — the `explode` design the first draft carried would
have burned minutes of CPU and gigabytes of RSS across 18 parallel hooks on a single large command.
Or, worse because it is silent, their session runs ungoverned: `guardrails.sh` stops blocking
`git commit` on `main`, `rm -rf` on a worktree root, `$HOME`, or `/`, and the freeze edit-lock stops
holding. The concrete artifact is a destroyed worktree or an unauthorised commit to `main` that the
operator has no record of refusing.

**If this leaks, the user's workflow and machine are exposed via:** the defect itself — any
`tool_input.command` that is an array (crafted by prompt injection reaching the model, or emitted by
a harness/MCP tool whose `tool_input` shape differs from `Bash`'s) runs attacker-named commands as
the operator, before any permission prompt, on their own laptop, with their SSH keys, Doppler
session, and `gh` credentials in reach. Secondarily, the new parse-failure telemetry writes to
`.claude/.rule-incidents.jsonl`; the design logs **no payload content**, only a fault classifier, so
a malformed command carrying a credential is never persisted.

**Brand-survival threshold:** `single-user incident`.

One operator, one crafted payload, one destroyed machine or leaked credential set ends a product
whose whole pitch is "the agent is safe to leave running." Hence `requires_cpo_signoff: true` and
`user-impact-reviewer` at review time.

**Reachability stays open, deliberately.** Whether the harness type-validates `tool_input` before
dispatching `PreToolUse` could not be established from inside the repo. The PR body must neither
upgrade this to "confirmed exploitable" nor downgrade it to "theoretical." The issue's own framing
is correct and is also the ADR's core rationale: *a hook must not depend on an upstream invariant it
cannot verify*, and `PreToolUse` also receives MCP and other tool shapes.

---

## Implementation Phases

Ordered by dependency direction — the telemetry exclusion before the first emit, the failing lint
before the migration it gates, the contract before its consumers.

### Phase 0 — Preconditions (measure; write no product code)

0.1 Re-run the reproducer against all 10 hooks with `INCIDENTS_REPO_ROOT` redirected. **Run from a
`mktemp -d`, never the worktree root** — the payload's trailing words are handed to `touch`, which
litters `TOOL_NAME=Bash` / `FILE_PATH=` / `SESSION_ID=` files into the CWD. (This happened during
planning; the strays were removed. AC13 exists to catch it.)

0.2 Confirm the delimiter on the installed jq: `printf '{}' | jq -j '"a","\u001e","b"' | od -c` **must**
show `a 036 b`. If RS is not emitted literally, stop — the design is wrong for that jq.

0.3 Reproduce the P8 benchmark table on the target machine. The chosen mechanism must beat the
legacy form at 100 B, 2 KB, 20 KB, and 200 KB. Record the numbers; they become AC6.

0.4 `bash -n` all 18 hooks pre-change, so a post-change failure is attributable.

0.5 Confirm `permissionDecision: "ask"` is still honored: re-read
`.claude/hooks/DEFER-DECISION-PAYLOAD-SHAPE.md` › comparison table and confirm the running CC major
version has not bumped past the probe's `2.1.142`. If it has, re-probe per that document's
"Re-probe trigger conditions" **before** designing around `ask`.

### Phase 1 — Telemetry first (so the first emit cannot break the aggregator)

Extend `scripts/rule-metrics-aggregate.sh` › the `$orphan_ids` pipeline with
`map(select(startswith("hook-input-") | not))`, commented in the shape of the existing
`context-reviewed-` block, and add the paired cases to `scripts/rule-metrics-aggregate.test.sh`.

`scripts/rule-metrics-aggregate.sh` hard-`ERROR`s on an unrecognised `rule_id`. If the emit shipped
first, the first parse failure would turn the aggregator red for an unrelated reason.

### Phase 2 — The failing lint (RED against `main` before anything is fixed)

Add the idiom-ban assertion to a new `.claude/hooks/hook-input-contract.test.sh` and **observe it
fail on `main`** (`cq-write-failing-tests-before`). Landing it after the migration means it is
written against already-clean code and has never been seen to fail — the `stub-argv-fidelity`
failure mode the hooks README already documents.

The ban: for every non-`*.test.sh` file under `.claude/hooks/` and `.openhands/hooks/`,
`grep -vE '^[[:space:]]*#' "$f" | grep -cE 'eval[[:space:]]+"\$\('` must be 0. Allow-list the two
`eval "exec ${fd}>&-"` calls in `lib/session-state.sh` **by exact string**, not by file — they act
on a numeric fd, never on hook input.

### Phase 3 — The extractor (contract)

Create `.claude/hooks/lib/hook-input.sh`. Two public functions, no `eval`, one jq fork.

```bash
# hook_parse_input <json> <VARNAME> <jq-expr> [<VARNAME> <jq-expr>]...
#   0 = every field parsed and every field is a string
#   1 = transport fault (unparseable / jq missing / field unreadable)
#   2 = anomalous shape (parsed, but a contracted field is not a string)
# On 1 and 2 every named variable is assigned (empty on 1; the sanitized
# tojson rendering on 2, for telemetry only — never for guard matching).
# Sets HOOK_INPUT_STATUS to ok|transport|anomalous and HOOK_INPUT_REASON to a
# classifier: jq_missing | surrogate | structural | oversize | nonstring | argc.
hook_parse_input() { ... }

# hook_input_fault_respond <hook-basename>
#   Reads HOOK_INPUT_STATUS/REASON, emits the incident + stderr line, and for
#   the anomalous / jq-missing / escalated cases prints the `ask` envelope and
#   exits 0. Returns 0 (caller continues fail-open) otherwise.
hook_input_fault_respond() { ... }
```

The jq program (measured shape — `contains`-guarded, never `explode`):

```jq
[ (try ( <expr1> ) catch {__e:true}),
  (try ( <expr2> ) catch {__e:true}) ]
| map(
    if type == "object" and has("__e") then ["err", ""]
    elif type == "string" then
      (if contains("\u001e") then ["anom", (split("\u001e") | join(""))] else ["ok", .] end)
    else ["anom", (tojson | split("\u001e") | join(""))]
    end)
| .[] | .[0], "\u001e", .[1], "\u001e"
```

The bash side (measured shape — `$( )` capture, never `read -d`):

```bash
raw=$(printf '%s' "$input" | jq -j "$prog" 2>/dev/null; printf 'X'); raw=${raw%X}
local oldifs=$IFS
set -f; IFS=$'\x1e'; local -a slots=($raw); set +f; IFS=$oldifs
```

Design properties, each measured during planning:

| Property | Mechanism | Evidence |
|---|---|---|
| no `eval` | values assigned with `printf -v` | a quoting bug can no longer become code execution |
| non-string is **surfaced**, not normalized | per-field `ok`/`anom`/`err` tag; `anom` ⇒ rc 2 ⇒ `ask` | the P6 falsification: coercion alone leaves every anchored guard evaded |
| the jq program is **total** | `try (<expr>) catch {__e:true}` → `err` tag | a non-object `tool_input` yields rc 1 (unreadable ≈ unparseable), **not** a normal-looking empty value. My first draft's `catch ""` made `{"tool_input":"oops"}` read as a clean parse — caught by probe |
| a value cannot forge a field boundary | RS stripped **only** on the `anom` branch, before the join | verified: `{"command":"AAA\u001eevil\u001eZZZ"}` → one field, count unchanged. Desync is structurally unreachable — the program emits exactly 2N records unconditionally, so a smuggled separator raises the count and trips the mismatch branch |
| the happy path is **byte-exact** | `ok` values are passed through untouched — no `gsub`, no strip | verified against tabs, newlines, backticks, `$( )`, quotes, backslash, `*`, emoji, CJK |
| the happy path is **faster than the baseline** | `contains` (substring search) not `explode`; `$( )` capture not `read -d` | P8 tables |
| NUL needs no handling | jq drops `\u0000` from string values on input and refuses to emit it | measured twice. The `. != 0` filter my first draft carried was dead code |
| trailing/empty fields survive | `printf 'X'` sentinel + `${raw%X}`; exactly one trailing RS | verified for the all-empty case `{"command":"","cwd":""}` → 4 slots, the case that would silently lose a field |
| safe under `set -e` | `if ! hook_parse_input ...; then` | 7 of the 10 run `set -eo pipefail`, 2 `set -uo pipefail`, `guardrails.sh` `set -euo pipefail` |
| **odd argument count is an error** | `(( $# % 2 == 0 )) \|\| { zero_all; return 1; }` | measured: `while (( $# >= 2 ))` silently drops a trailing odd arg and returns **success**, leaving that variable at its **inherited environment value**. Every call site is hand-edited in this PR, so a dropped expr is a one-character failure |
| **every early return zeroes the names** | zero before each `return` | measured: the bad-variable-name reject path returned 1 **without** assigning, contradicting the docblock and aborting under `set -u` |
| dangerous variable names refused | `^[A-Za-z_][A-Za-z0-9_]*$` **plus** a denylist: `IFS PATH PS4 BASH_ENV SHELLOPTS BASHOPTS CDPATH GLOBIGNORE LD_PRELOAD PROMPT_COMMAND` | measured: all of those pass the regex and get assigned; clobbering `PATH` makes every later hook fail-open |
| oversize input is refused before the fork | `(( ${#input} > 262144 ))` ⇒ `reason=oversize` | nothing legitimate sends a 256 KB `command`; the size is itself the anomaly, and the cap bounds the DoS surface irrespective of jq's constant factors |
| `printf '%s'` replaces `echo "$INPUT"` | — | `echo` interprets backslashes and `-n`/`-e` on some shells. This is a **second, previously unreported input-mangling bug present in all 18 hooks**; call it out in the PR body |
| no `\| grep -q` | by construction | `grep-q-pipe-guard.test.sh` sweeps `lib/*.sh` and asserts zero |
| does **not** source `incidents.sh` | — | the 10 hooks source it independently, and `incidents.sh` conditionally defines a `headless_or_stderr` fallback only if one is not already defined — source ordering is load-bearing |
| sourced **fail-hard** | no `\|\| true` on the `source` line | if the helper were sourced fail-soft, a missing file leaves `hook_parse_input` undefined → the hook dies at the call → **exit non-zero → fail-open, silently**: defect 2 reintroduced one line higher, where no test looks |
| `shellcheck -s bash` clean | drop the unused `n` local | measured `SC2034` on the first draft |
| jq-expr interpolation is literal-only | comment marking exprs as source literals; conservative charset check | `prog+="(try ( $e ) catch ...)"` interpolates unescaped. Not live — every call site passes a literal — but unguarded against future drift |

### Phase 4 — Lone-surrogate handling

A **lone high surrogate makes jq reject the entire document**, disarming all 18 gates. This is not
exotic — it is routine, and it comes from the harness's own serializer:

```
$ node -e 'console.log(JSON.stringify({tool_input:{command:"git \ud800 stash"}}))'
{"tool_input":{"command":"git \ud800 stash"}}
$ ... | jq .
jq: parse error: Invalid \uXXXX\uXXXX surrogate pair escape
```

JS strings permit unpaired surrogates and `JSON.stringify` escapes them faithfully. A truncated
emoji or mangled UTF-16 in pasted content is enough. (Asymmetric: a lone *low* surrogate parses and
becomes U+FFFD; only lone *high* surrogates are fatal.) This affects the current code identically —
it is not a regression — but it is the highest-probability real-world disarm trigger and this PR is
the moment to handle it.

On the **failure path only** (never the hot path), classify and retry once with lone high surrogates
replaced by U+FFFD, using `perl` (already a hook dependency via `strip_command_bodies`):

```bash
perl -pe 's/\\u[dD][89abAB][0-9a-fA-F]{2}(?!\\u[dD][c-fC-F])/\\ufffd/g'
```

Verified end-to-end during planning: the scrub-and-retry recovers `git � stash` from the exact
`JSON.stringify` output above. If the retry succeeds, set `HOOK_INPUT_REASON=surrogate` and proceed
with the guards armed — a recovered parse is strictly better than a disarm. If it still fails, the
transport-fault path runs with `reason=structural`.

### Phase 5 — Migrate the 10 `eval` hooks (commit 1)

Replace the `eval` with a `hook_parse_input` call carrying that file's exact field set, plus the
fault responder. **Keep** the `: "${VAR:=}"` belt-and-braces defaults `guardrails.sh` already
carries and add them where absent — the helper's contract now guarantees assignment, but the
defaults cost nothing and the contract has already been wrong once.

| Hook | Fields |
|---|---|
| `guardrails.sh` | `COMMAND=.tool_input.command`, `TOOL_NAME=.tool_name`, `FILE_PATH=.tool_input.file_path // .tool_input.notebook_path` |
| `cla-signed-author-gate.sh` | `CMD`, `WORK_DIR=.cwd` |
| `context-reviewed-gate.sh` | `CMD` |
| `follow-through-directive-gate.sh` | `CMD`, `WORK_DIR` |
| `prod-write-defer-gate.sh` | `CMD`, `SESSION_ID=.session_id` |
| `ship-net-issue-flow-gate.sh` | `CMD`, `WORK_DIR` |
| `ship-operator-step-gate.sh` | `CMD`, `WORK_DIR` |
| `ship-runbook-ssh-gate.sh` | `CMD`, `WORK_DIR` |
| `ship-soak-followthrough-gate.sh` | `CMD`, `WORK_DIR` |
| `ship-unpushed-commits-gate.sh` | `CMD`, `WORK_DIR` |

**The false safety claim is written into the source in four places and into the knowledge base in
one; all five must be corrected in this commit** — leaving them is how the idiom returns:

- `guardrails.sh` › extraction comment — "*`@sh` shell-escapes each field so eval is safe…*"
- `ship-unpushed-commits-gate.sh` › extraction comment — "*`@sh` shell-escapes every value so any…*"
- `cla-signed-author-gate.sh` › extraction comment — "*Single jq fork via `@sh`-escaped eval…*"
- `prod-write-defer-gate.sh` › extraction comment — "*single jq `@sh`-escape, sibling-hook pattern*"
- `knowledge-base/project/learnings/2026-05-15-deterministic-permissions-empirical-probes-and-review-gaps.md`
  › "*security-sentinel — confirmed jq @sh-escape neutralizes stdin command injection*" — **append a
  dated correction** citing #7164 and ADR-155. Do not delete the historical finding; do not let the
  correction overstate ("no shell evaluation of hook input", not "input is now safe").

The archived `2026-04-18-refactor-drain-pr2213-review-backlog-plan.md` and its spec — which contain
the risk analysis that missed this bug ("*Mitigation: `@sh` already shell-escapes*", a register that
modelled **string** payloads only) — are point-in-time records. **Cite them in the ADR; do not edit
them.**

### Phase 6 — Migrate the 8 `$( )` sibling hooks (commit 2)

`background-poll-prefer-monitor.sh`, `brand-hex-commit-gate.sh`, `doppler-secrets-delete-redirect.sh`,
`git-commit-secret-scan.sh`, `kb-domain-allowlist-guard.sh`, `no-memory-write.sh`,
`pre-merge-auto-close-scan.sh`, `pre-merge-rebase.sh`.

These are simpler than the `eval` sites — no shell-quoting semantics to preserve — and they close
the evasion half of the defect. Note `kb-domain-allowlist-guard.sh` and `no-memory-write.sh` read
`.tool_input.command` inside a larger `//` fallback chain; read each expression before porting it,
do not pattern-match on the others.

Separately, the two `.openhands/hooks/` files (`guardrails.sh`, `pre-merge-rebase.sh`) get a
**minimal in-place non-string guard only** — a few lines, no helper — because their envelope differs
(`.working_dir`, `.tool_input.path`) and their deny shape is `{"decision":"deny"}`. Extend
`tests/hooks/test_openhands_guardrails.sh` with the array-payload case. File helper convergence as a
follow-up issue (`domain/engineering`, `type/security`, `priority/p3-low`).

### Phase 7 — The gate (behavioural assertions)

Complete `.claude/hooks/hook-input-contract.test.sh` (started RED in Phase 2). Pure bash + `jq`, with
the repo's standard `command -v jq >/dev/null 2>&1 || { echo "SKIP: jq missing"; exit 0; }` preflight
— the `test-scripts` CI shard has no bun and no node.

1. **Idiom ban** (from Phase 2).
2. **RCE regression, all 10.** From a `mktemp -d` CWD with `INCIDENTS_REPO_ROOT` redirected, the
   array payload leaves no marker file and creates no `TOOL_NAME=Bash` / `FILE_PATH=` /
   `SESSION_ID=` stray.
3. **Guard-still-armed** (the assertion that would have caught the `tojson` trap): for each of the
   18 hooks, an array payload whose flattened form encodes a command the hook *does* guard produces
   the anomalous-shape `ask` — **not** an allow. A bare "no marker file" assertion passes happily on
   the evaded design.
4. **Loud disarm.** `not-json-at-all` produces a `.rule-incidents.jsonl` line with
   `rule_id == "hook-input-parse-failure"`, `event_type == "warn"`, `schema == 1`,
   `kind == "hook_self_fault"`, a `reason=` classifier, and `command_snippet` **not** containing the
   payload body.
5. **Lone surrogate recovers.** The `JSON.stringify`-shaped payload parses after the scrub-and-retry
   and the guards run armed; `reason=surrogate` is recorded.
6. **`jq` missing ⇒ `ask`.** With `PATH=/nonexistent`, the hook emits the `ask` envelope, not an
   allow.
7. **Known-deny canary, per hook.** One fixture per hook asserting its characteristic
   `permissionDecision`. This is the issue's "startup canary fed a known-deny fixture", relocated
   from the hot path to the suite — and it is what discharges the "one helper bug disarms all 18"
   objection: a helper regression would have to pass 18 canaries.
8. **Helper unit matrix.** T1-T15 below.
9. **Perf floor.** Assert the chosen mechanism is not slower than the legacy form at 200 KB (guards
   against a future "small cleanup" reintroducing `explode` or `read -d`).

Prescribed **mutation checks**, run and recorded as a transcript, not merely asserted:
(a) `sed` the type-assert out of the helper → suite RED; (b) restore the `eval` in `guardrails.sh` →
suite RED; (c) **delete `lib/hook-input.sh` entirely** → suite RED (this is the check that proves
the helper is sourced fail-hard); (d) `git checkout` → suite green.

### Phase 8 — Record the decision

- **ADR-155** (provisional ordinal), titled for the **posture**, not the parser — e.g.
  *"Blocking hooks fail open on transport fault and ask on anomalous input shape."* The decision
  worth recording is the asymmetry, not "we stopped using eval": without it, the next contributor
  who reads `emit_incident … warn; exit 0` calls it a bug and "fixes" it into a deny, and bricks
  sessions. Must record the alternatives (fail-closed, coerce-and-continue, per-field `jq -r`,
  `--raw-output0`), must supersede the `2026-03-18` learning's silent-absorb reading, and must cite
  ADR-070 as the repo's only prior fail-open sanction — which covers an *additive advisory* hook,
  the complement of this case.
- **`.claude/hooks/README.md`** — the file documents the hook contract and the incident API and says
  **nothing** about input parsing. Add a "Parsing hook input" section making `hook_parse_input`
  mandatory and naming the CI gate.
- **C4** — next section.

---

## Architecture Decision (ADR/C4)

This changes a **trust boundary**: it establishes that hook stdin is model-controlled and fixes the
parse posture for 18 hooks across 2 harnesses. The ADR and the C4 edit are deliverables **of this
plan** (`wg-architecture-decision-is-a-plan-deliverable`).

### ADR

`ADR-155-blocking-hooks-fail-open-on-transport-fault-ask-on-anomalous-shape.md`, content per Phase 8.

### C4 views

All three model files were **read** — `model.c4`, `views.c4`, `spec.c4`. A keyword `grep` would have
been useless here: the gap is a missing *edge*, not a missing noun. Enumeration per the completeness
mandate:

- **External human actors** — `founder = actor "Founder / Operator"`, `emailSender`, `betaContact`,
  `contributor`. The adversary is the model's own tool-call envelope, not a new human role.
  **No new actor.**
- **External systems** — `anthropic` is already modelled and is the ultimate origin of the envelope,
  but the envelope is *delivered* by the runtime container, not by Anthropic directly.
  **No new system.**
- **Containers / data stores** — `platform.engine.hooks = container "Hook Engine"` and
  `platform.engine.claude = container "Agent Runtime"`, both already modelled and both already in
  the `containers` (L2) **and** `components` (L3) view include-lists.
  `.claude/.rule-incidents.jsonl` is a pre-existing local file and is deliberately not modelled — no
  other local telemetry file is either. **No new container or store.**
- **Access relationships that change** — exactly one, and it is missing. `model.c4` contains
  `hooks -> claude "Guards tool calls"` (the decision edge *out* of the hook) and **no relationship
  into `hooks` at all**: the model does not represent that the Hook Engine *receives* a
  model-controlled envelope. That is precisely the boundary this fix establishes, and the model
  already reasons carefully about hook trust elsewhere (`connectedRepoPlugin -> skillloader` ›
  "IGNORED by the loader (trust boundary)…"), so this fills a gap in an argument the model is
  already making.

In-scope edit (`model.c4` only — no `views.c4` `include` line is needed, because both endpoints are
already in both views and LikeC4 renders an edge whose endpoints are present):

1. Add `claude -> hooks "Tool-call envelope on stdin — MODEL-CONTROLLED, UNTRUSTED (ADR-155):
   parsed without eval; a non-string contracted field is an anomaly that asks, never a value that is
   coerced" { technology "stdin JSON" }`.
2. Amend `platform.engine.hooks`'s `description`, which is falsified by omission — it says what
   hooks *do* and never what they *consume*. Append the parse posture.

Then run `apps/web-platform/test/c4-code-syntax.test.ts` and `c4-render.test.ts` — a malformed
relationship fails there, not at `tsc`.

### Sequencing

Nothing is soak-gated. ADR-155 is authored `status: accepted`: the decision is true the moment the
helper merges.

---

## Files to Create

- `.claude/hooks/lib/hook-input.sh`
- `.claude/hooks/hook-input-contract.test.sh`
- `knowledge-base/engineering/architecture/decisions/ADR-155-blocking-hooks-fail-open-on-transport-fault-ask-on-anomalous-shape.md`

## Files to Edit

**Telemetry (Phase 1):** `scripts/rule-metrics-aggregate.sh`, `scripts/rule-metrics-aggregate.test.sh`.

**The 10 (Phase 5, commit 1):** `.claude/hooks/guardrails.sh`, `cla-signed-author-gate.sh`,
`context-reviewed-gate.sh`, `follow-through-directive-gate.sh`, `prod-write-defer-gate.sh`,
`ship-net-issue-flow-gate.sh`, `ship-operator-step-gate.sh`, `ship-runbook-ssh-gate.sh`,
`ship-soak-followthrough-gate.sh`, `ship-unpushed-commits-gate.sh`.

**The 8 siblings (Phase 6, commit 2):** `.claude/hooks/background-poll-prefer-monitor.sh`,
`brand-hex-commit-gate.sh`, `doppler-secrets-delete-redirect.sh`, `git-commit-secret-scan.sh`,
`kb-domain-allowlist-guard.sh`, `no-memory-write.sh`, `pre-merge-auto-close-scan.sh`,
`pre-merge-rebase.sh`.

**OpenHands mirror (Phase 6):** `.openhands/hooks/guardrails.sh`, `.openhands/hooks/pre-merge-rebase.sh`,
`tests/hooks/test_openhands_guardrails.sh`.

**Docs / model / memory (Phases 5, 8):** `.claude/hooks/README.md`,
`knowledge-base/engineering/architecture/diagrams/model.c4`,
`knowledge-base/project/learnings/2026-05-15-deterministic-permissions-empirical-probes-and-review-gaps.md`
(dated correction only).

**Existing tests to re-run, and update only if they genuinely break** (do not pre-emptively edit):
`.claude/hooks/guardrails.test.sh` and the `.test.sh` sibling of each migrated hook;
`hookeventname-coverage.test.sh` (per-file `count(hookEventName) >= count(permissionDecision)` — the
new `ask` envelopes **add** `permissionDecision`s, so each must carry its paired `hookEventName` or
this fails); `grep-q-pipe-guard.test.sh` (now sweeps the new `lib/hook-input.sh`);
`stub-argv-fidelity.test.sh`; `tests/hooks/test_hook_emissions.sh` (asserts `schema == 1` on every
captured line — the new row is schema-1 field-additive); `.claude/hooks/pre-merge-rebase-parity.test.sh`.

No `SKILL.md` `description:` is edited, so the skill-description budget check does not apply.

---

## Acceptance Criteria

### Pre-merge (PR)

1. **AC1 — RCE closed, all 10.** From a `mktemp -d` CWD, the array payload leaves the marker file
   non-existent for every one of the 10 hooks. (Issue AC #1.)
2. **AC2 — guards still armed** (the AC that fails on a coerce-and-continue fix). For every one of
   the 18 Bash-matcher hooks, an array payload encoding a command that hook guards yields
   `.hookSpecificOutput.permissionDecision == "ask"`, never an allow. Explicitly includes
   `["git","stash"]` vs `guardrails.sh` and `["gh","pr","merge","--admin"]` vs the merge gates.
3. **AC3 — no `eval` remains.**
   `git grep -nE 'eval[[:space:]]+"\$\(' -- '.claude/hooks/*.sh' '.openhands/hooks/*.sh'` returns
   only the two `eval "exec ${fd}>&-"` lines in `lib/session-state.sh`, matched by exact string.
4. **AC4 — loud disarm.** `not-json-at-all` appends a line with
   `.rule_id == "hook-input-parse-failure"`, `.event_type == "warn"`, `.schema == 1`,
   `.kind == "hook_self_fault"`, a non-empty `reason=` classifier, and
   `(.command_snippet | contains("not-json-at-all")) == false`. (Issue AC #2.)
5. **AC5 — mutation turns the suite RED.** Transcript recorded for all four mutations in Phase 7:
   type-assert removed → RED; `eval` restored → RED; **`lib/hook-input.sh` deleted → RED**;
   restored → green. (Issue AC #3.)
6. **AC6 — hot path not regressed.** The Phase 0.3 table is reproduced in the PR body and the
   shipped mechanism beats the legacy `eval` at 100 B, 2 KB, 20 KB, **and** 200 KB. A 10 MB payload
   completes in under 1 s with maxRSS under 64 MB.
7. **AC7 — one jq fork.** Each migrated hook's extraction path contains exactly one `jq`
   invocation (the helper's), asserted per file.
8. **AC8 — surrogate recovery.** The `node -e 'JSON.stringify({tool_input:{command:"git \ud800 stash"}})'`
   payload parses after the scrub-and-retry, the guards run **armed** (the `git stash` deny fires),
   and `reason=surrogate` is recorded.
9. **AC9 — `jq` missing ⇒ `ask`.** With `PATH=/nonexistent`, each of the 18 emits the `ask`
   envelope, not an allow.
10. **AC10 — orphan gate extended.** `bash scripts/rule-metrics-aggregate.test.sh` passes, and
    running the aggregator over a fixture containing a `hook-input-parse-failure` row yields
    `.summary.orphan_rule_ids | length == 0`.
11. **AC11 — full suite green.** `bash scripts/test-all.sh` exits 0, prints `N/N suites passed`, and
    `N` is **≥ the pre-change count + 1**, proving the new test file was discovered, not skipped.
12. **AC12 — syntax + lint.** `bash -n` passes on every edited `.sh`; `shellcheck -s bash -x` is
    clean (zero findings, including `SC2034`) on `lib/hook-input.sh` and on all 18 migrated hooks,
    with output pasted into the PR body — CI does **not** gate `.sh` with shellcheck, so this is a
    manual gate.
13. **AC13 — no stray artifacts.**
    `git ls-files --others --exclude-standard | grep -E '^(TOOL_NAME|FILE_PATH|SESSION_ID)='`
    returns nothing, and `git status --short` shows only intended changes.
14. **AC14 — false claims corrected.**
    `git grep -nE '@sh (shell-)?escapes|eval is safe' -- '.claude/hooks/*.sh'` returns zero, and
    `2026-05-15-deterministic-permissions-empirical-probes-and-review-gaps.md` contains a dated
    correction citing #7164 that does **not** contain the string "input is now safe".
15. **AC15 — C4 valid.** `model.c4` contains a `claude -> hooks` relationship naming ADR-155 and
    "UNTRUSTED"; `cd apps/web-platform && ./node_modules/.bin/vitest run test/c4-code-syntax.test.ts test/c4-render.test.ts`
    passes.
16. **AC16 — ADR exists and no stale ordinal.** `ADR-155-*.md` exists with `status: accepted`, a
    `## Decision`, and an `## Alternatives Considered` naming fail-closed, coerce-and-continue,
    per-field `jq -r`, and `--raw-output0`; and
    `grep -rn 'ADR-15[0-9]' knowledge-base/project/plans/2026-08-02-fix-hook-input-eval-jq-rce-plan.md knowledge-base/project/specs/feat-one-shot-7164-hook-eval-jq-rce/`
    shows a single consistent ordinal after any renumber.
17. **AC17 — README codified.** `.claude/hooks/README.md` has a "Parsing hook input" section naming
    `hook_parse_input` and `hook-input-contract.test.sh`.
18. **AC18 — `Closes #7164` in the PR body**, not the title
    (`wg-use-closes-n-in-pr-body-not-title-to`). This is a code fix complete at merge, so `Closes`
    is correct — not `Ref`.

### Post-merge (operator)

None. Every step is automatable in-session: the fix is repo-local shell, the tests run in the
`test-scripts` CI shard, and there is no infrastructure, vendor mint, or migration. Post-merge
verification is `bash scripts/test-all.sh scripts` on `main`, run by the agent.

---

## Test Scenarios

| # | Scenario | Expected |
|---|---|---|
| T1 | `command` is `["x","touch","$M"]` | no marker; status `anomalous`; `ask` emitted |
| T2 | `command` is a string with `\n`, backticks, `$( )`, quotes, `\`, `*`, emoji, CJK | status `ok`; value **byte-identical**; nothing executes |
| T3 | `command` is object / number / bool | status `anomalous`; `ask` |
| T4 | `command` is `null` or absent | status `ok`, empty string, no incident, guards run |
| T5 | `tool_input` is a string or an array | status `transport` (field unreadable), fail-open + incident — **not** a clean empty parse |
| T6 | stdin is `not-json-at-all` | status `transport`, `reason=structural`, incident, stderr, guards skipped |
| T7 | stdin is empty | status `transport` (slot count 0 — jq itself returns rc 0 here, so the **count** is the discriminator) |
| T8 | `cwd` is an array | status `anomalous` — a non-string `cwd` silently defeats every worktree-prefix comparison |
| T9 | `command` contains RS (`\u001e`) | RS stripped **on the anomalous branch only**; slot count unchanged; no boundary forged |
| T10 | `command` contains `\u0000` | jq drops it on input; value arrives without the NUL; documented as a jq property, not a guarantee the helper provides |
| T11 | Lone high surrogate from `JSON.stringify` | scrub-and-retry recovers; guards run **armed**; `reason=surrogate` |
| T12 | `jq` absent from `PATH` | `ask`, `reason=jq_missing` |
| T13 | 200 KB and 10 MB `command` | correct value; within the AC6 perf floor |
| T14 | Input > 256 KB | `reason=oversize` before the jq fork |
| T15 | Odd argument count / bad variable name / denylisted name (`PATH`, `IFS`) | rc 1, **every** name zeroed, `reason=argc` |
| T16 | All fields empty (`{"command":"","cwd":""}`) | exactly 2N slots — the case where a trailing empty field can silently vanish |
| T17 | > 3 parse failures in one session | escalates to `ask` for the remainder |
| T18 | Known-deny canary × 18 | each hook's characteristic decision fires, proving it is armed |
| T19 | Mutations (a)-(d) | suite RED / RED / RED / green |

---

## Observability

```yaml
liveness_signal:
  what: "hook-input-* rows in .claude/.rule-incidents.jsonl; zero is the healthy state"
  cadence: "per PreToolUse invocation, emitted only on fault (O(0) on the happy path)"
  alert_target: "scripts/rule-metrics-aggregate.sh summary + the compound Phase 3.5 Deviation Analyst read"
  configured_in: ".claude/hooks/lib/hook-input.sh (emitter); scripts/rule-metrics-aggregate.sh (counter)"
error_reporting:
  destination: ".claude/.rule-incidents.jsonl via emit_incident, plus headless_or_stderr warn"
  fail_loud: true   # this IS the fix for defect 2 — the disarm is announced on both channels
failure_modes:
  - mode: "stdin JSON structurally malformed or truncated"
    detection: "slot count != 2N -> rule_id=hook-input-parse-failure, kind=hook_self_fault, reason=structural"
    alert_route: "rule-metrics summary; a non-zero count is a hook-layer fault, not a rule hit"
  - mode: "lone high surrogate from the harness serializer"
    detection: "same row, reason=surrogate; distinguished from structural because the scrub-and-retry succeeded"
    alert_route: "same; a rising surrogate count means the harness is emitting unpaired UTF-16 and is worth an upstream report"
  - mode: "jq missing or not executable"
    detection: "reason=jq_missing; the hook emits `ask`, never an allow, so a dark gate cannot pass silently"
    alert_route: "operator sees the ask prompt immediately; the row names the hook"
  - mode: "contracted field is not a string (the attack signature)"
    detection: "rule_id=hook-input-anomalous-shape, event_type=warn, reason=nonstring, with the field name and the sanitized tojson rendering"
    alert_route: "operator sees the ask prompt; the row is the forensic record of what was attempted"
  - mode: "payload exceeds the 256 KB cap"
    detection: "reason=oversize, recorded before the jq fork"
    alert_route: "same row; distinguishes a DoS attempt from a parse bug"
  - mode: "the eval idiom is reintroduced by a future hook"
    detection: "hook-input-contract.test.sh idiom ban, run in the test-scripts CI shard on every PR"
    alert_route: "CI red on the PR that reintroduces it"
logs:
  where: ".claude/.rule-incidents.jsonl (flock-guarded, rotated by lib/log-rotation.sh); stderr routed through headless_or_stderr so `claude --bg` sessions capture it to a file"
  retention: "governed by the existing per-write rotator in .claude/hooks/lib/log-rotation.sh"
discoverability_test:
  command: "R=$(mktemp -d); printf 'not-json' | INCIDENTS_REPO_ROOT=\"$R\" bash .claude/hooks/guardrails.sh; jq -r 'select(.rule_id|startswith(\"hook-input-\"))' \"$R/.claude/.rule-incidents.jsonl\""
  expected_output: "one JSON line: rule_id=hook-input-parse-failure, event_type=warn, kind=hook_self_fault, reason=structural, and no payload body in command_snippet"
```

Per §2.9.2 (blind execution surfaces): a `PreToolUse` hook **is** operator-blind — its stdout is
consumed by the harness and its stderr is usually swallowed. The fault row is therefore an
**in-surface** probe emitted from inside the failing hook, and its fields discriminate every
competing hypothesis in **one** event: `reason` separates structural / surrogate / jq_missing /
oversize / nonstring / argc, and the hook basename in the prefix says *which* gate went dark. A
single boolean would have separated none of them — which is exactly why six months of this defect
produced no signal at all.

Deliberately **not** logged: any payload content. If a later revision ever logs it, it must scrub
`\x00-\x1f`, `\x7f`, `\u2028`, and `\u2029` per `cq-regex-unicode-separators-escape-only` — measured,
U+2028/U+2029 survive the helper intact.

---

## Domain Review

**Domains relevant:** Engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Architecture risk of the shared helper rated **LOW — ship it**; the
single-point-of-failure objection fails on its own terms because the 10 hooks are *already*
centralized by byte-identical copy-paste, which is why one defect hit all 10 at once. The named
discharge is the per-hook known-deny canary (Phase 7 assertion 7), which exercises each composed
hook end-to-end rather than the helper in isolation. Findings folded into the plan: the helper must
be sourced **fail-hard** (a `|| true` source reintroduces defect 2 one line higher); the aggregator
exclusion must precede the first emit; the idiom-ban lint must land RED before the migration; the
OpenHands mirror gets a parity **test**, not the helper; the ADR must be titled for the posture, not
the parser. Its "P4 is 5 files" count was checked and corrected to 8 (P10).

Domains assessed and **not** relevant: Product, Marketing, Sales, Finance, Legal, Operations,
Support. Product/UX Gate tier **NONE** — the mechanical UI-surface override does not fire; no path
in `Files to Create/Edit` matches `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx`.

### Security review (security-sentinel)

**Status:** reviewed — **verdict on the first draft: do not merge as designed.** Four stated
properties were falsified by measurement. All are resolved in this revision: P0-1 `explode` DoS
(deleted; the shipped form is faster than the baseline), P0-2 `tojson` guard evasion (replaced with
a type-assert + `ask`), P0-3 lone-surrogate disarm (scrub-and-retry, Phase 4), P1-1 odd-argc
returning success with an inherited-environment value, P1-2 reject path not zeroing, P1-3 the false
claim in institutional memory, P1-4 the two-tier posture + per-session counter + `jq`-missing ⇒
`ask`, plus `SC2034`, the `printf -v` denylist, the jq-expr-literal-only note, and the 18-not-11
blast radius. Its judgement that `bytes=` is not a meaningful oracle was accepted **and improved on**
— the field now carries a fault classifier, which is more diagnostic and no more revealing.

What it could **not** break, and which this revision must preserve: no code execution; no
field-boundary forge; field-to-variable desync structurally unreachable (the program emits exactly
2N records unconditionally, so a smuggled separator raises the count and trips the mismatch branch);
truncated jq output fails safe; `JQ_COLORS`/`JQ_LIBRARY_PATH` are non-issues; 100k-deep nesting hits
jq's own depth limit and returns a parse error rather than a crash.

---

## GDPR / Compliance Gate

The canonical regulated-surface regex does not match (no schema, migration, auth flow, API route, or
`.sql`). The gate is invoked anyway because trigger (b) fires — the plan declares
`brand-survival threshold: single-user incident`.

Assessment: the only data-movement change is one additional row type in the pre-existing local
`.claude/.rule-incidents.jsonl`, which never leaves the operator's machine and is not a
controller-to-processor transfer. The material control is that the design **excludes payload content
by construction** — only a fault classifier and a length are written — so a malformed command
carrying a credential is never persisted in cleartext. No new processing activity, no lawful-basis
question, no Art. 30 entry. **Advisory only — not legal advice.**

---

## Open Code-Review Overlap

Ran `gh issue list --label code-review --state open --json number,title,body --limit 200` (62 open),
then `jq --arg path <p> 'select(.body | contains($path))'` for each planned path.

- `#2348: vitest: mock-factory export drift when mocked module gains new named export` — matched only
  on `.claude/hooks/` appearing incidentally; it is a vitest mock-factory concern in
  `apps/web-platform`. **Disposition: acknowledge.** Different concern, different runner, no shared
  file. Stays open.

No other open code-review issue names any file in `## Files to Create` or `## Files to Edit`.

---

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| **Centralisation single point of failure** — a helper bug disarms all 18 at once | The current state is 18 copies of the same bug, so the copies bought nothing. Discharged by the per-hook known-deny canary (Phase 7 §7): a helper regression must pass 18 end-to-end canaries. Plus the mutation check that **deletes** the helper and requires RED |
| **Fail-open remains reachable** — malformed JSON still disarms, now with a log line | Bounded, not eliminated: the per-session counter escalates to `ask` after 3 faults, turning an unlimited disarm oracle into a 3-shot one; `jq`-missing goes straight to `ask`; the surrogate class — the highest-probability real trigger — is *recovered* rather than tolerated. Recorded in ADR-155 |
| **`ask` prompt storm** — an anomalous payload makes all 18 Bash hooks emit `ask` at once | **Open design question, routed to deepen-plan.** Default is all-emit (no ordering dependency, correct under any registration change). The alternative is a designated responder (`guardrails.sh` only, since it covers both matchers). /work must measure how CC renders 18 concurrent asks and fall back to designated-responder if unusable |
| **Scope: 18 hooks + 2 mirrors in one P0 PR** | Two commits (eval sites, then `$( )` sites) keep review and bisect clean and allow the P0 half to be split if the suite destabilises. Shipping 10 alone is the higher-expected-cost mistake: it retires #7164 while the majority of Bash-path gates stay evadable by the payload the PR was written to stop |
| **A future "cleanup" reintroduces `explode` or `read -d`** | AC6's 200 KB perf floor is asserted **in the suite**, not just in the PR body |
| **jq version drift** | RS was chosen precisely to avoid the jq ≥ 1.7 `--raw-output0` dependency. Phase 0.2 measures RS emission on the installed jq as a hard precondition; T12 covers jq being absent |
| **Parity guards trip** | `tests/hooks/test_openhands_guardrails.sh` and `pre-merge-rebase-parity.test.sh` are in the re-run list. Phase 6 touches the mirror deliberately, so the parity test is expected to need refreshed expectations — refreshed, never silenced |
| **`hookeventname-coverage.test.sh` fails** — the new `ask` envelopes add `permissionDecision`s | Each must carry its paired `hookEventName: "PreToolUse"`, which is also a correctness requirement: `DEFER-DECISION-PAYLOAD-SHAPE.md` measured that without it CC **silently ignores the envelope and the tool runs** |
| **Orphan gate fails on the first post-merge aggregation** | Phase 1 lands the exclusion first; AC10 asserts it against a fixture carrying the new row |
| **Reintroduction** — nine commits copied this idiom into nine more hooks over four months | The idiom ban is the durable control. Prose did not stop copy-paste; a red CI check does |

---

## Alternatives Considered

| Alternative | Verdict |
|---|---|
| **Keep `eval`, add `if type=="string" then . else tojson end`** (the issue's first suggestion) | **Rejected — falsified (P6).** Closes the RCE and leaves every anchored guard evaded by the same payload, with rc 0 and no incident. It would have retired #7164 on a false negative |
| **NUL delimiter + `mapfile -d ''`** (the issue's second suggestion) | **Rejected as written (P7, P8).** jq drops `\u0000`; NUL needs `--raw-output0` (jq ≥ 1.7); `mapfile -d` needs bash ≥ 4.4; and both delimited-read mechanisms are 2.5× regressions at 200 KB. The *direction* — drop `eval` — is adopted |
| **`explode`-based separator strip** (this plan's own first draft) | **Rejected — measured 8.55 s / 180 MB on a 10 MB payload vs 0.70 s / 43 MB for the code it replaces**, times 18 parallel hooks. A fix that hands the model a session-hang primitive is not a fix |
| **`read -d` / `mapfile -d` on a process substitution** (this plan's own first draft) | **Rejected — measured.** Bash reads delimited records byte-at-a-time from a pipe: 14348 ms vs the baseline's 5643 ms at 200 KB |
| **Per-field `VAR=$(… jq -r …)`** — the shape the OpenHands mirror uses | **Rejected.** Safe from RCE but N forks per hook per call, reverting #2253 across 18 hooks — and it still needs the type-assert, so it is strictly worse on both axes |
| **Fail closed on parse failure** | **Rejected**, recorded in ADR-155. Denying on unparseable input turns any systematic malformation — and the surrogate class proves that is routine, not adversarial-only — into a bricked session with no in-band recovery, since editing the hook is itself gated by `guardrails.sh` on `Write\|Edit` |
| **`permissionDecision: "ask"` for everything** | **Rejected.** Prompt fatigue on a transport fault the operator cannot act on. `ask` is reserved for the two conditions where the operator *can* act: an anomalous shape, and a missing `jq` |
| **A runtime startup canary** (the issue's suggestion read literally) | **Rejected in the hot path, adopted in the suite.** Re-running a hook against a fixture on every tool call re-pays the cost #2253 removed; the same assurance at zero runtime cost is Phase 7 §7 |
| **Converge the OpenHands mirror on the helper now** | **Rejected for this PR.** The mirror reads a different envelope and emits a different deny shape; making the helper envelope-agnostic is real abstraction bought with security urgency, on a file that is not RCE-vulnerable. It gets a minimal in-place guard + a parity test; convergence is a follow-up |
| **A new AGENTS.md `cq-*` rule** | **Rejected.** It would fit (`B_ALWAYS=42547` of 46000), but a red CI check is fail-closed, costs zero always-loaded bytes, and prose did not stop nine copy-paste propagations. `hookeventname-coverage.test.sh` and `stub-argv-fidelity.test.sh` are the existing precedent for exactly this class |
| **Fix only `guardrails.sh`** | **Rejected.** All 10 confirmed vulnerable by execution; 18 hooks fire per Bash call |

---

## Sharp Edges

- **A plan whose `## User-Brand Impact` section is empty or placeholder fails `deepen-plan` Phase 4.6.**
  Filled above.
- **A fix that closes an RCE can open a guard evasion in the same line.** `tojson` makes an array
  safe to `eval` and simultaneously makes it unmatchable by every anchored guard regex. When the
  remedy for hostile input is *normalization*, always re-run the downstream matcher against the
  normalized value — "it can no longer execute" is not "the guard still fires".
- **Benchmark the hostile size, not the typical one.** The first draft's benchmark (small payloads,
  200 iterations) said the design was *faster*; at 10 MB the same design was 12× slower and 4× fatter
  than the code it replaced. Any hot-path claim in a security fix must be measured at the size an
  attacker chooses, not the size a developer types.
- **`read -d` on a pipe reads one byte per syscall.** Any "read NUL/RS-delimited fields" design is a
  latent throughput regression; `$( )` capture + `IFS` word-splitting (with `set -f` and `IFS`
  restored) is the fast form and works on bash 3.2.
- **`jq` cannot emit `\u0000` from a string literal, and drops it from input string values.** Any
  design reasoning "NUL is the natural delimiter because it cannot appear in the data" silently
  produces one concatenated field unless it uses `--raw-output0`. Measured: `jq -j '"a","\u0000","b"'` → `ab`.
- **`jq`'s exit code alone is not a parse-failure detector.** Empty stdin gives rc 0 with zero
  output. The **field count** is the discriminator — and `try ... catch ""` is worse than useless
  here, because it makes an unreadable field look like a clean empty parse. Catch to a *distinguished
  value*, never to a value the happy path can produce.
- **`while (( $# >= 2 ))` silently discards a trailing odd argument and returns success.** For a
  variadic name/expr API this leaves a variable at its inherited environment value while reporting a
  clean parse. Assert `$# % 2 == 0`.
- **Every early `return 1` must zero the out-parameters** or the docblock lies and the caller aborts
  under `set -u`. Keep `: "${VAR:=}"` at call sites even when the contract promises assignment — the
  contract has already been wrong once.
- **`printf -v` accepts `PATH`, `IFS`, `PS4`, `BASH_ENV`.** They pass any reasonable identifier regex.
  A denylist is one line.
- **`JSON.stringify` emits lone high surrogates and jq rejects the whole document.** A truncated
  emoji anywhere in a payload disarms every hook that parses it. Lone *low* surrogates parse fine —
  the asymmetry makes this easy to miss in testing.
- **Do not run the reproducer from the repo root.** Its trailing words go to `touch`, creating
  `TOOL_NAME=Bash` / `FILE_PATH=` / `SESSION_ID=` files in the CWD. AC13 catches it.
- **`shellcheck` is not a CI gate for `.sh` in this repo**, and `bats` is not installed. Running
  shellcheck is a manual step whose output belongs in the PR body; the test convention is a plain
  bash script with hand-rolled counters.
- **The `test-scripts` CI shard has no bun and no node.** The new contract test must be pure bash +
  `jq` with the standard `command -v jq || SKIP` preflight.
- **An absence-grep cannot prove a positive control is present.** "`eval` does not appear" passes
  happily on a build where the type-assert was mutated out. AC2 (guard-still-armed) is the assertion
  that actually fails.
- **A `hookSpecificOutput` without `hookEventName` is silently ignored and the tool runs.** Every new
  `ask` envelope must carry it — measured in `DEFER-DECISION-PAYLOAD-SHAPE.md`, and enforced by
  `hookeventname-coverage.test.sh`.
- **Source the helper fail-hard.** `source .../hook-input.sh || true` leaves `hook_parse_input`
  undefined, the hook dies at the call, exits non-zero, and fails open — defect 2 reintroduced one
  line higher, where no test looks. The mutation check that *deletes* the file is what proves this.
