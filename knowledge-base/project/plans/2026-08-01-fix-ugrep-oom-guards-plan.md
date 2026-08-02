---
title: "fix: guard against runaway ugrep OOM that crashes the operator's terminal"
type: fix
lane: procedural
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
branch: feat-one-shot-ugrep-oom-guards
pr: 7151
created: 2026-08-01
---

# fix: guard against runaway ugrep OOM that crashes the operator's terminal

## Overview

Claude Code's shell snapshot installs a bash **function** named `grep` that transparently
re-execs the `claude` binary with `argv[0]=ugrep`. Certain regex shapes make ugrep's DFA
construction allocate without bound. On 2026-08-01 a parallel session's one-liner against a
single 21 kB markdown file reached **9.5 GB RSS in 171 s at 99% CPU and was still climbing**,
driving a 31 GB box to 691 MB free with swap at 88.5%. The operator confirms prior Warp
crashes match this signature.

The process is invisible as a cause: `ps` shows `COMMAND 2.1.220` (the claude version
directory), not `ugrep`, so every prior occurrence read as "Claude Code is leaking memory."
That misattribution is why it went un-root-caused across multiple crashes.

Two guards:

- **Guard 1 (primary):** a `guardrails.sh` PreToolUse rule that blocks the dangerous regex
  shape pre-flight, telling the agent to use `command grep`.
- **Guard 2 (backstop):** a memory cap so an unpredicted blowup dies alone.

## Research Reconciliation — Spec vs. Codebase

Both prescribed mechanisms were measured against reality. **Both required correction.**
All numbers below are from hard-capped probes run in this worktree on 2026-08-01
(`ulimit -v` + `timeout` on every run; the reproducer was never run uncapped).

| Prescribed | Reality (measured) | Plan response |
|---|---|---|
| Guard 1 detects "bounded repeat `{n,m}` **AND** alternation `\|`" | **Wrong on both sides.** `.{0,80}cannot[^.]{0,120}` — *no alternation* — blows up (870 MB, killed at cap). `.{0,8}(NEVER\|MUST NOT)` — bounded repeat *and* alternation — costs 8.8 MB / 0.1 s. Alternation is nearly irrelevant; the driver is **≥2 bounded repeats**, cost scaling with the product of their upper bounds. | Replace the heuristic with a measured cost model (below). |
| Guard 2 caps processes via `ulimit -v ~4 GB` | **Categorically incompatible.** vitest dies instantly at **every** cap tested — 6, 8, 12, 16, 24, **32 GB** — at only 97 MB actual RSS, with `WebAssembly.instantiate(): Out of memory`. Uncapped it passes (12702 tests, 898 MB peak). V8/WASM *reserves* vast virtual address space; `ulimit -v` counts reservations, not usage. A 32 GB cap on a 31 GB box still fails. | Reject `ulimit -v`. Ship a **cgroup v2 `memory.max`** cap, which limits RSS not VA. |
| `command grep` bypasses the shim | Confirmed. `command grep` and `/usr/bin/grep` → GNU grep 3.12. | Block message may safely recommend `command grep`. |
| (not specified) | **`\grep` does NOT bypass the shim.** Backslash suppresses *alias* expansion, not *function* lookup — verified: `\foo` still ran the function. | Guard must treat `\grep` as shimmed, not as an escape hatch. |

### Measured cost model (Guard 1)

Two-bounded-repeat patterns, product of upper bounds vs. observed cost:

| Pattern | Product | Peak RSS | Verdict |
|---|---|---|---|
| `.{0,10}(6-alt)[^.]{0,10}` | 100 | 12 MB | safe |
| `.{0,20}(6-alt)[^.]{0,20}` | 400 | 44 MB | safe |
| `.{0,25}(6-alt)[^.]{0,25}` | 625 | 162 MB | elevated |
| `.{0,30}(6-alt)[^.]{0,30}` | 900 | 672 MB | bad |
| `.{0,35}(6-alt)[^.]{0,35}` | 1225 | killed at cap | blowup |
| `.{0,40}cannot[^.]{0,40}` (**no alternation**) | 1600 | killed at cap | blowup |
| `.{0,80}(6-alt)[^.]{0,120}` (**the reproducer**) | 9600 | killed at cap | blowup |

A **single** bounded repeat is always cheap, regardless of size: `.{0,10000}cannot` = 60 MB /
0.6 s; `.{0,2000}(6-alt)` = 97 MB / 0.9 s. GNU grep runs the reproducer in 7 MB / 0.1 s.

**Model:** parse every bounded quantifier (`{n,m}`, `{,m}`, `{n}`; treat `{n,}` as unbounded
and ignore). If fewer than two are bounded → allow. Otherwise cost = ∏(upper+1); block when
cost ≥ **500**. Calibration: highest observed-safe product is 441 (44 MB); lowest clearly-bad
is 961 (672 MB). 500 sits between, on the safe side.

> **SUPERSEDED at review (2026-08-02). The model above is wrong in BOTH
> directions and was NOT shipped.** Re-measured hard-capped (`ulimit -v
> 2000000` + `timeout`), the bound product is not predictive — the **width of
> the repeated class** is:
>
> | Pattern | ∏(upper+1) | Peak RSS | Model above says |
> |---|---|---|---|
> | `[0-9]{0,80}x[0-9]{0,120}` | 9801 | 7.5 MB | deny ❌ |
> | `[0-9a-f]{8}-…-[0-9a-f]{12}` (UUID) | 14625 | 7.5 MB | deny ❌ |
> | `[0-9]{4}-[0-9]{2}-[0-9]{2}T…` (ISO ts) | 1215 | 7.5 MB | deny ❌ |
> | `^\+(<{7}\|={7}\|>{7})` | 512 | 7.4 MB | deny ❌ |
> | `.{0,16}q[^.]{0,16}` | 289 | **BLOWUP** | allow ❌ |
> | `.{0,20}(a\|b\|c\|d\|e\|f)[^.]{0,20}` | 441 | **BLOWUP** | allow ❌ |
>
> The last row is this table's own "highest observed-safe" datapoint, and it
> **does not reproduce** — so the 500 threshold sat ABOVE the real danger point
> and would have shipped a guard that misses genuine blowups while denying **22
> benign call sites in this repo**, including the conflict-marker regex inside
> `guardrails.sh` itself.
>
> **Shipped model:** count only bounded repeats over a WIDE atom (`.`, a negated
> class `[^…]`, or a group close, counted conservatively). Fewer than two →
> allow; else deny at ∏(upper+1) ≥ **150**. Wide-class ladder: 25→7.7 MB,
> 49→8.3 MB, 81→12 MB, 121→30 MB, 169→103 MB, 289→BLOWUP; 150 sits between the
> 121 knee and the 169 elbow. Pinned by fixtures G9/G10/G17–G24 and by mutations
> M11 (revert to bound-product) and M12 (global backslash strip).

## User-Brand Impact

**If this lands broken, the user experiences:** a false block on a legitimate `grep`, costing
one retry with `command grep` (the block message states the fix). A Guard 2 mis-sizing is more
serious: too low a cap kills the agent's own toolchain mid-run.

**If this leaks, the user's data is exposed via:** no new data surface. Both guards are local
process-control; the hook reads only the command string it is already handed and writes no
new artifact beyond the existing incident ledger.

**Brand-survival threshold:** `single-user incident` — the failure this fixes already froze the
operator's desktop repeatedly, and a wrongly-sized Guard 2 could break every build on the box.

## Implementation Phases

### Phase 1 — Guard 1: `guardrails:block-catastrophic-grep-repeat` (contract first)

Add to `.claude/hooks/guardrails.sh`, following the `block-stash-in-worktrees` pattern
(prose-rule comment at the top, `emit_incident` + `permissionDecision: deny` JSON).

Load-bearing implementation constraints, each derived from reading the existing hook:

1. **Scan `$COMMAND`, not `$SCAN`.** `strip_command_bodies` blanks quoted bodies, and a grep
   pattern is *always* inside quotes — scanning `$SCAN` would see nothing and the guard would
   never fire.
2. **Tokenize with `xargs -n1`** (the pattern the `require-milestone` and `block-recursive-delete`
   gates already use). This strips quotes so the pattern arrives as one token, *and* it removes
   the false-positive class that scanning raw `$COMMAND` would create: in
   `git commit -m "... grep -noE '.{0,80}(a|b)' ..."` the whole message is a single token whose
   command word is `git`, so no `grep` token exists to trigger on.
3. **Only fire on shimmed invocations.** Skip when the `grep` token is preceded by `command`, or
   is path-qualified (`/usr/bin/grep`, `/bin/grep`). Do **not** skip on `\grep` — measured to
   still hit the function.
4. **Verify at implementation time** whether the snapshot also shims `egrep`/`fgrep`
   (`declare -f egrep fgrep`); include them only if shimmed.
5. The guard's own detection regex and its test fixtures must not themselves embed a
   ≥500-cost pattern.

Tests in `.claude/hooks/guardrails.test.sh` (auto-discovered by `scripts/test-all.sh` via the
`.claude/hooks/*.test.sh` glob), reusing the existing `mk_payload`/`decision_of` harness and its
non-git-CWD isolation. Cases: the reproducer → `deny`; the no-alternation blowup
`.{0,80}cannot[^.]{0,120}` → `deny`; `.{0,8}(A|B)` → allow; `.{0,10000}foo` (single bound) → allow;
`command grep` + reproducer → allow; `/usr/bin/grep` + reproducer → allow; `\grep` + reproducer
→ deny; a `git commit -m` whose *message* quotes the reproducer → allow.

### Phase 2 — Guard 2: cgroup RSS cap (fail-soft)

`ulimit -v` is rejected by Phase 0 measurement. Ship a cgroup v2 cap instead.

Verified feasible on this box: cgroup v2 (`cgroup2fs`), the parent `app.slice` has
`subtree_control=memory pids`, and a probe `mkdir` + `echo … > memory.max` succeeded and was
readable back. No `sudo` required (the Bash tool has none).

Cap value from measurement: heaviest real workload is `tsc --noEmit` at **2.45 GB** peak RSS
(66 s); full vitest peaks at **898 MB**. A **12 GB** cap is ~4.9× the heaviest observed
workload while bounding a runaway to ~38% of the 31 GB box — the reproducer would have died
there instead of reaching 9.5 GB and climbing.

Applied idempotently and **fail-soft** at SessionStart: any error (no delegation, controller
absent, write refused) logs and continues. A guard that can block a session is worse than the
bug it prevents.

**Known residual, to be stated in the PR body:** under a cap the blowup dies by **SIGSEGV**
after ~45 s at 2.7 GB (measured at a 3 GB cap) — ugrep does not handle allocation failure
gracefully. Guard 2 bounds damage; it does not prevent 45 s of 100% CPU. Guard 1 is the real fix.

### Phase 3 — Rule + learning

- New hard rule in `AGENTS.md` (index pointer) + `AGENTS.rules.md` (body), annotated
  `[hook-enforced: guardrails.sh guardrails:block-catastrophic-grep-repeat]`, following
  `cq-agents-md-why-single-line` and `cq-rule-ids-are-immutable`. **Budget verified:** the
  authority (`python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.rules.md`) reports
  `[OK] B_ALWAYS=42547` against the 46000 cap — ~3.4 kB headroom, so the rule fits. Re-run
  after the edit.
- Learning file under `knowledge-base/project/learnings/` documenting the diagnosis chain,
  **including the `COMMAND 2.1.220` red herring** — the reason this survived multiple crashes
  un-diagnosed — and both measured corrections (alternation is not the trigger; `ulimit -v` is
  incompatible with V8/WASM).

## Acceptance Criteria

### Pre-merge

1. `bash .claude/hooks/guardrails.test.sh` passes, including all eight cases in Phase 1.
2. The reproducer, submitted as a Bash payload, returns `permissionDecision: "deny"`.
3. `.{0,8}(NEVER|MUST NOT)` and `.{0,10000}foo` both return no decision (allow) — the guard is
   not the noisy "bounded + alternation" rule that was originally prescribed.
4. A `git commit -m` payload whose message quotes the reproducer returns allow (no
   false-positive on documentation of the pattern).
5. `python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.rules.md 2>&1` reports `[OK]`
   after the rule lands (stderr captured — WARN/REJECT print there).
6. `bash scripts/test-all.sh` is green, modulo the pre-existing failure recorded below.
7. Guard 2 verification, all three: (a) the cap is applied and `memory.max` reads back the
   intended value; (b) `cd apps/web-platform && ./node_modules/.bin/vitest run test/` passes
   **under the cap** — the check `ulimit -v` failed; (c) a deliberate hog dies at the cap while
   the session survives.
8. Guard 2 fail-soft: with cgroup writes forced to fail, the session still starts.

### Pre-existing (not introduced here)

Baseline `vitest run test/` on this worktree's merge-base reports **1 failed / 12702 passed /
354 skipped**. The single failure is pre-existing on `origin/main` and out of scope; per
`wg-when-tests-fail-and-are-confirmed-pre` it must be identified by name in the PR body and,
if not already tracked, filed.

## Observability

```yaml
liveness_signal:
  what: guardrails.sh emit_incident "guardrails-block-catastrophic-grep-repeat" deny
  cadence: on each blocked invocation
  alert_target: existing incident ledger (lib/incidents.sh), weekly rule-usage aggregator
  configured_in: .claude/hooks/guardrails.sh
error_reporting:
  destination: incident ledger; hook stderr
  fail_loud: Guard 1 fails closed (deny on match). Guard 2 fails OPEN by design —
    a cap that cannot be applied must never block a session.
failure_modes:
  - mode: guard blocks a legitimate grep (false positive)
    detection: deny incidents for this rule id in the ledger
    alert_route: weekly aggregator; threshold breach → retune the cost model
  - mode: guard misses a blowup shape (false negative)
    detection: Guard 2 cap hit; process dies at memory.max
    alert_route: cgroup memory.events oom counter
  - mode: cgroup cap unapplied (no delegation)
    detection: SessionStart logs the fail-soft branch
    alert_route: session log
logs:
  where: incident ledger + hook stderr (local, operator machine)
  retention: as per existing ledger rotation
discoverability_test:
  # CORRECTED at /work. The originally planned probe used a single-quoted
  # `printf` whose `\"` sequences printf itself unescapes, emitting INVALID
  # JSON. guardrails.sh's jq extraction then fails and falls back to
  # COMMAND="" — so every guard no-ops and the probe returns empty. As
  # written it could never have produced a deny, for ANY rule: a fail-open
  # verification. Build the payload with jq so the quoting is machine-made.
  command: >-
    jq -nc --arg c 'grep -noE ".{0,80}(a|b)[^.]{0,120}" f.md'
    '{tool_name:"Bash",tool_input:{command:$c}}'
    | bash .claude/hooks/guardrails.sh
  expected_output: JSON with permissionDecision "deny"
```

No SSH anywhere; both guards are local to the operator machine.

## Domain Review

**Domains relevant:** none

Infrastructure/tooling change confined to agent-harness guardrails on the operator's own
machine. No user-facing surface, no data model, no vendor, no UI file in Files to Edit — the
Product/UX mechanical override does not fire.

## Architecture Decision (ADR/C4)

No ADR. This adds a guardrail rule to an existing hook and a local resource cap; it establishes
no new ownership boundary, substrate, or trust boundary.

**C4:** checked all three of `model.c4`, `views.c4`, `spec.c4` for impact — the change adds no
external human actor (operator is already modeled), no external system or vendor, no container
or data store, and no actor↔surface access relationship. Local process-control on an existing
developer-harness surface. No C4 edit required.

## Encryption Posture

Not applicable — no persistent store and no new cross-component connection.

## Files to Edit

- `.claude/hooks/guardrails.sh` — add the rule + its prose-rule comment
- `.claude/hooks/guardrails.test.sh` — add the eight fixtures
- `AGENTS.md` — index pointer
- `AGENTS.rules.md` — rule body
- Guard 2: SessionStart hook + an idempotent cap script (exact paths resolved at `/work` after
  reading the SessionStart wiring)

## Files to Create

- `knowledge-base/project/learnings/2026-08-01-<topic>.md` (date chosen at write time)

## Open Code-Review Overlap

None — no open `code-review` issue references `guardrails.sh`, `AGENTS.rules.md`, or the
SessionStart hook path.

## Risks & Mitigations

- **Guard 1 false positives.** Mitigated by the measured threshold (nothing under 441 product
  is blocked) and by the block message naming the one-word fix (`command grep`).
- **Guard 2 breaks the toolchain.** This is precisely what `ulimit -v` would have done — the
  reason it is rejected. The cgroup cap is validated against a real vitest run (AC7b) before
  merge, not assumed.
- **Guard 2 invasiveness.** Applying a cgroup to the live Claude Code process tree touches
  process supervision under the terminal's scope. Fail-soft on every error; never modify the
  terminal's own scope.

## Sharp Edges

- A guard scanning `$SCAN` instead of `$COMMAND` silently never fires — the pattern lives
  inside quotes, which `strip_command_bodies` blanks. This is the single easiest way to ship a
  guard that tests green in principle and protects nothing; assert the deny path, not just the
  allow path.
- `\grep` is not an escape hatch. Backslash suppresses alias expansion, not function lookup.
- Do not "verify" Guard 2 by re-running the reproducer uncapped. It will take the machine down
  again. Every probe in this plan ran under `ulimit -v` + `timeout`, and the plan's own
  measurements were obtained that way.
- A single bounded repeat, however large, is cheap. Blocking on one bound would be pure noise.
