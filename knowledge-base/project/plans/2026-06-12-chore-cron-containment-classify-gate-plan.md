---
issue: 5072
type: chore-infra
lane: cross-domain
brand_survival_threshold: none
requires_cpo_signoff: false
---

# chore(infra): cron-containment-classify gate when adding a new Inngest cron

🛡️ Preventive CI gate. Closes #5072.

## Enhancement Summary

**Deepened on:** 2026-06-12
**Sections enhanced:** Premise Validation, Phase 0, Research Insights (new)
**Verification pass:** 1 sonnet-tier grep agent — 8 load-bearing claims, all CONFIRMS, zero contradictions.

### Key Improvements
1. All three classifier inputs (`CRON_BASH_ALLOWLISTS`, `TIER2_DEFERRED_CRONS`, `EXPECTED_CRON_FUNCTIONS`) verified importable from a vitest test, with exact export lines pinned (Research Insights).
2. The three-class taxonomy is now machine-confirmed: all 12 hook-contained crons (3 allowlist + 9 Tier-2) import `_cron-claude-eval-substrate`; all 6 direct-spawn crons are clean of both maps — so the gate cannot mis-classify the current tree.
3. Precedent-diff recorded: this gate is the source-scan sibling of `function-registry-count.test.ts` (same dir, same idiom) — no novel pattern.

### New Considerations Discovered
- The `vi.hoisted(NEXT_PHASE="phase-production-build")` guard is mandatory (importing the watchdog re-export otherwise throws on missing `INNGEST_SIGNING_KEY`) — pinned into Phase 0/Phase 1.
- The only prose mention of `cron-compound-promote` in `_cron-shared.ts:257` is a comment, NOT Set membership — the gate's membership checks must read the actual Set/object, never grep prose (already the plan's approach via importing the symbols).

## Overview

When a new `cron-*.ts` Inngest function is added, a developer (or one-shot agent)
must declare its **containment class** so the cron cannot ship with an
unbounded shell/network surface. Today that classification is *tribal knowledge*
encoded only in prose comments (`_cron-claude-eval-substrate.ts:130-181`,
`_cron-shared.ts:311-367`) and in two hand-maintained maps (`CRON_BASH_ALLOWLISTS`,
`TIER2_DEFERRED_CRONS`). Nothing mechanically forces a *new* cron to land in the
right map. The failure mode this gate catches: a new cron spawns `claude` (or raw
`bash`) and ships **uncontained** — neither hook-allowlisted, nor Tier-2-deferred,
nor pure-TS — and nobody notices until it egresses in prod.

This is the exact re-evaluation trigger #5072 named ("a future cron ships
uncontained"), now reachable because #5046 (Tier-2 egress firewall + least-priv
token) is **CLOSED** (PR-1 token merged 2026-06-09, PR-2 DOCKER-USER egress
allowlist merged 2026-06-10), so the containment substrate the gate asserts
against is stable.

**Scope (YAGNI):** ONE static-source vitest gate that walks every
`server/inngest/functions/cron-*.ts`, classifies it, and FAILS with a remediation
message naming the containment class + the exact map entry to add. No new runtime
code, no new infra, no new dependency. It is the forcing-function sibling of the
existing `function-registry-count.test.ts` (the "five-registry-lockstep"
mechanism) — this adds a *sixth* lockstep dimension (containment), in the same
test directory, using the same source-scan idiom.

The gate's only job at fire time is to **emit the containment class + required
allowlist entries** for the offending cron — verbatim the deliverable #5072 asks
for.

## Premise Validation

Checked the four cited references against live state (2026-06-12):
- **#5072** (this issue) — OPEN, re-eval criteria met (#5046 landed; gate is now buildable). ✔ premise holds.
- **#5046** (parent, Tier-2 egress firewall) — CLOSED. PR-1/PR-2 both merged per issue body + `_cron-shared.ts:111-138` (least-priv token presets) and `cron-egress-nftables.sh` (egress allowlist) present on branch. ✔
- **#5018** (PreToolUse hook containment) — MERGED; `cron-bash-allowlist-hook.mjs` + `CRON_BASH_ALLOWLISTS` present. ✔
- **#5073** (sibling, move content-publisher to ephemeral GHA) — OPEN, deferred (re-eval condition not met per task brief). The gate must NOT force-fix content-publisher; it must classify it as **direct-spawn** and leave remediation to #5073. ✔
- **Mechanism vs. ADR corpus:** `ADR-033-inngest-cron-functions-invoke-claude-code-via-child-process-spawn.md` and `ADR-054-safe-commit-and-pr-sole-write-path-for-bot-cron-prs.md` both *describe* the spawn-claude + hook containment model the gate asserts; the gate codifies the ADRs, it does not contradict a rejected alternative. ✔
- **Capability self-check:** verified by `git grep` (not memory) that `CRON_BASH_ALLOWLISTS` lives in `_cron-claude-eval-substrate.ts:145` and `TIER2_DEFERRED_CRONS` in `_cron-shared.ts:337`; both are plain exported objects/sets a test can import. ✔

No stale premise. The gate is buildable against current `origin/main` state.

## Research Reconciliation — Spec vs. Codebase

The issue body frames containment as a **binary** ("spawn bash → firewall" vs.
"invoke claude via tool layer → hook"). Code scan reveals **three** observable
classes — the binary framing would mis-classify the 6 direct-`spawn` crons.

| Issue-body claim | Codebase reality | Plan response |
| --- | --- | --- |
| Two classes: `spawn("bash")` vs. claude-via-tool-layer | THREE static classes: (1) hook-contained claude (imports `_cron-claude-eval-substrate`), (2) **direct-spawn trusted-binary** (`spawn("git"\|"bash",[fixedScript])`, no substrate — e.g. `cron-content-publisher`, `cron-rule-prune`), (3) pure-TS (no `spawn`, no substrate) | Gate encodes all three. Class (2) is the `→ firewall / ephemeral-runner` branch the issue means; #5073 acts on it. |
| "required allowlist entries" only for the bash-spawn case | Allowlist entries (`CRON_BASH_ALLOWLISTS`) apply only to class (1) hook-contained claude crons; class (2) carries NO allowlist (the hook isn't in its spawn path) | Gate emits `CRON_BASH_ALLOWLISTS`/`TIER2_DEFERRED_CRONS` requirement for class (1); for class (2) it emits a "declare in a known direct-spawn set or defer per #5073" message. |

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly — this is a CI
gate over infra-internal crons. A *false-negative* (gate misses an uncontained
cron) reopens the pre-#5046 egress-exfil window the founder's GitHub-App
installation token guards; a *false-positive* (gate red on a correctly-contained
cron) blocks an unrelated PR's merge until the new cron is mapped.
**If this leaks, the user's [data / workflow / money] is exposed via:** N/A — the
gate reads only tracked source files; it ships no secret, no token, no network call.
**Brand-survival threshold:** none — the gate is a *preventive* guard on a
substrate (#5046) that is already the brand-survival control; the gate's own
failure is a blocked CI run, not a data incident.
> threshold: none, reason: pure static-source CI test over infra-internal cron files; touches no regulated-data surface, no auth flow, no secret, no runtime path.

## Implementation Phases

### Phase 0 — Preconditions (verify, do not assume)
1. Confirm the three classifier inputs are importable from a vitest test:
   - `CRON_BASH_ALLOWLISTS` (`_cron-claude-eval-substrate.ts:145`)
   - `TIER2_DEFERRED_CRONS` (`_cron-shared.ts:337`)
   - `EXPECTED_CRON_FUNCTIONS` (`cron-manifest.ts:22`, re-exported via watchdog)
   Use the `vi.hoisted(() => { process.env.NEXT_PHASE = "phase-production-build"; })`
   guard from `function-registry-count.test.ts:9-11` so importing the watchdog
   does not throw on the missing `INNGEST_SIGNING_KEY` in the test env.
2. Re-run the direct-spawn enumeration on the live tree (it drifts as crons are
   added). Canonical command (paste output into the test as the grandfather set):
   ```bash
   for f in $(git ls-files 'apps/web-platform/server/inngest/functions/cron-*.ts'); do
     if grep -qE '\bspawn\(' "$f" && ! grep -qE '_cron-claude-eval-substrate|runClaudeEval' "$f"; then
       echo "$(basename "$f" .ts)"
     fi
   done
   ```
   Expected at plan-write time (2026-06-12): `cron-compound-promote`,
   `cron-content-publisher`, `cron-content-vendor-drift`, `cron-rule-prune`,
   `cron-strategy-review`, `cron-weekly-analytics`.

### Phase 1 — RED: write the classifier test first (cq-write-failing-tests-before)
Create `apps/web-platform/test/server/inngest/cron-containment-classify.test.ts`.
The test walks `server/inngest/functions/cron-*.ts` (excluding `_`-prefixed
shared modules and `*.test.ts`), reads each file's source, and classifies:

- **hook-contained** ⇔ source matches `/_cron-claude-eval-substrate|runClaudeEval/`.
  Assertion: `cron ∈ CRON_BASH_ALLOWLISTS` **XOR** `cron ∈ TIER2_DEFERRED_CRONS`
  (a hook-contained cron is either Tier-1 allowlisted or Tier-2-deferred; being in
  BOTH or NEITHER is a misconfiguration). `cron-roadmap-review` is the canonical
  Tier-1 positive; the 9 `TIER2_DEFERRED_CRONS` members are the Tier-2 positives.
- **direct-spawn** ⇔ NOT hook-contained AND source matches `/\bspawn\(/`.
  Assertion: `cron ∈ KNOWN_DIRECT_SPAWN_CRONS` (the grandfather set from Phase 0).
  A *new* direct-spawn cron not in that set FAILS → forces an explicit decision
  (add it to the set with a one-line containment justification, or move it to an
  ephemeral runner per the #5073 pattern).
- **pure-TS** ⇔ neither. Assertion: `cron ∉ CRON_BASH_ALLOWLISTS` AND
  `cron ∉ TIER2_DEFERRED_CRONS` AND `cron ∉ KNOWN_DIRECT_SPAWN_CRONS` (a pure-TS
  cron must carry NO containment entry — a stray entry signals a copy-paste error).

**Failure-message contract (the #5072 deliverable).** Each assertion's message
MUST emit, for the offending cron: (a) the detected containment class, and (b) the
exact remediation — for hook-contained, the literal `CRON_BASH_ALLOWLISTS["<cron>"]
= [...]` or `TIER2_DEFERRED_CRONS.add("<cron>")` line to add; for direct-spawn, the
`KNOWN_DIRECT_SPAWN_CRONS` entry + a pointer to #5073's ephemeral-runner pattern.
Add a Phase-0 self-test row in the test (a synthetic cron name run through the
classifier helper) asserting the message string contains the class + the map name,
so the message contract itself is regression-guarded.

Run RED: the test passes immediately against current state (all crons already
correctly classified) — so to prove the gate BITES, the RED step is a **fixture
mutation**: temporarily delete `cron-roadmap-review` from `CRON_BASH_ALLOWLISTS`
in-test (via a cloned object, not by editing source) and assert the classifier
flags it `hook-contained / uncontained` with the remediation line. This proves the
gate fails-loud on the real failure mode without shipping a broken map.

### Phase 2 — GREEN: confirm clean tree + wire into the suite
1. Run the full file `./node_modules/.bin/vitest run test/server/inngest/cron-containment-classify.test.ts`
   from `apps/web-platform/` — expect green (the codebase is already correctly
   classified; the gate only bites on a *future* drift).
2. Run `./node_modules/.bin/vitest run test/server/inngest/function-registry-count.test.ts`
   to confirm no interaction regression (both walk the same dir).
3. Typecheck: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.

### Phase 3 — Document the gate in the lockstep learning
Append a short "sixth lockstep dimension" note to
`knowledge-base/project/learnings/2026-06-05-new-inngest-cron-requires-five-registry-lockstep.md`:
a new cron must ALSO land in exactly one containment class, and the new gate is the
forcing function. Keep it to ~5 lines; do NOT renumber the existing five
registries (the learning's "FIVE" framing is load-bearing for that file's title —
add containment as an adjacent paragraph, not a sixth numbered item that breaks the
existing prose).

## Research Insights

**Verified facts (sonnet grep agent, 2026-06-12 — all CONFIRMS):**

| Claim | Status | Evidence |
| --- | --- | --- |
| `CRON_BASH_ALLOWLISTS` is a plain importable `Record<string,string[]>` | CONFIRMS | `_cron-claude-eval-substrate.ts:145` (3 keys: roadmap-review, agent-native-audit, legal-audit) |
| `TIER2_DEFERRED_CRONS` is an importable `ReadonlySet<string>`, exactly the 9 named members | CONFIRMS | `_cron-shared.ts:337-347` |
| `EXPECTED_CRON_FUNCTIONS` re-exported via the watchdog path | CONFIRMS | `cron-inngest-cron-watchdog.ts:61` re-exports from `@/server/inngest/cron-manifest` |
| `vi.hoisted(NEXT_PHASE=...)` guard required before the watchdog import | CONFIRMS | `function-registry-count.test.ts:9-11` |
| Taxonomy: all 12 hook-contained crons import the substrate | CONFIRMS | all 3 allowlist + 9 Tier-2 crons grep positive for the substrate import |
| The 6 direct-spawn crons have `spawn(`, no substrate import, and are absent from both maps | CONFIRMS | `cron-compound-promote`'s only appearance in a map-file is a `_cron-shared.ts:257` *comment*, not Set membership |
| Node vitest project collects `test/**/*.test.ts` | CONFIRMS | `vitest.config.ts:43` |
| Gate needs no secret / token / network call | CONFIRMS | both maps are static string literals; `readFileSync` is pure FS I/O |

**Implementation note (membership, not prose):** the gate MUST decide class membership by importing the actual `CRON_BASH_ALLOWLISTS` object and `TIER2_DEFERRED_CRONS` Set and calling `Object.hasOwn(...)` / `.has(...)` — NOT by grepping the map files for the cron name (a prose comment like `_cron-shared.ts:257` would false-positive). Source-text grep is used ONLY for the substrate-import / `spawn(` *class detection* on each `cron-*.ts`, never for map membership.

## Precedent-Diff (Pattern-bound: source-scan CI gate)

This gate is NOT a novel pattern — it is the source-scan sibling of the existing
`function-registry-count.test.ts` (same directory, same `readdirSync` + per-file
`readFileSync` + import-the-canonical-symbol idiom; that test already cross-checks
the cron file list against `EXPECTED_CRON_FUNCTIONS`, the `.tf` monitors, and the
workflow `-target=` list). The new gate adds containment as an adjacent dimension
using the identical mechanics. No new scheduled job is introduced (this is a *gate
over* crons, not a cron), so the ADR-033 Inngest-vs-GH-Actions scheduled-work
precedent check does not fire.

## Files to Create
- `apps/web-platform/test/server/inngest/cron-containment-classify.test.ts` — the gate.

## Files to Edit
- `knowledge-base/project/learnings/2026-06-05-new-inngest-cron-requires-five-registry-lockstep.md` — append the containment-class paragraph (Phase 3).

(No source edits. The gate reads existing maps; it does not modify
`_cron-claude-eval-substrate.ts` or `_cron-shared.ts`.)

## Open Code-Review Overlap
None. Queried 63 open `code-review` issues against the gate's surface
(`function-registry-count.test.ts`, `cron-bash-allowlist-hook`,
`_cron-claude-eval-substrate`, `CRON_BASH_ALLOWLISTS`, `containment`). Only #3453
matched `containment`, and it is an unrelated `isPathInWorkspace` symlink-traversal
review (PR #3442) — no file overlap with this gate.

## Acceptance Criteria

### Pre-merge (PR)
- [x] `apps/web-platform/test/server/inngest/cron-containment-classify.test.ts` exists and is collected by the node vitest project (path under `test/**/*.test.ts` per `vitest.config.ts:44`).
- [x] The test walks `server/inngest/functions/cron-*.ts` via `readdirSync` (NOT a hardcoded list) and excludes `_`-prefixed shared modules + `*.test.ts` — verify by grepping the test for `readdirSync` and the `cron-` filter.
- [x] Each of the three class assertions emits a failure message containing BOTH the detected class string AND the literal remediation map line; a self-test row asserts the message shape for a synthetic cron.
- [x] RED is proven by an in-test fixture mutation (cloned map with `cron-roadmap-review` removed) that makes the classifier flag `hook-contained / uncontained` — confirm the test contains this negative case.
- [x] `./node_modules/.bin/vitest run test/server/inngest/cron-containment-classify.test.ts` is GREEN against the unmutated tree (all current crons classify correctly).
- [x] `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` passes.
- [x] `KNOWN_DIRECT_SPAWN_CRONS` in the test equals the Phase-0 live enumeration (6 crons as of 2026-06-12); `cron-content-publisher` is present (NOT force-fixed — deferred to #5073).
- [x] The lockstep learning carries the appended containment-class paragraph.
- [x] PR body uses `Closes #5072`.

## Observability

```yaml
liveness_signal:    # what: the vitest gate runs on every PR touching apps/web-platform; cadence: per-CI-run; alert_target: CI red on PR / merge-queue; configured_in: apps/web-platform vitest suite (no separate scheduling)
error_reporting:    # destination: CI job log + GitHub checks (PR-blocking); fail_loud: true — assertion failure fails the suite, blocking merge
failure_modes:
  - {mode: new cron ships uncontained (not in any class), detection: this gate's assertion, alert_route: CI red with the class+remediation message}
  - {mode: hook-contained cron in BOTH or NEITHER map, detection: XOR assertion, alert_route: CI red}
  - {mode: pure-TS cron carries a stray containment entry, detection: empty-membership assertion, alert_route: CI red}
logs:               # where: GitHub Actions CI job output (test stdout); retention: per GitHub Actions log retention
discoverability_test:  # command (NO ssh): cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-containment-classify.test.ts ; expected_output: "PASS ... cron-containment-classify" on a clean tree, or a FAIL naming the uncontained cron + its class + remediation line on drift
```

## Domain Review

**Domains relevant:** Engineering (infra/CI tooling)

### Engineering

**Status:** reviewed (inline — nested-agent Task spawn is unavailable inside the one-shot planning subagent per the 2026-06-05 lockstep learning §Session Errors; CTO assessment done inline)
**Assessment:** Pure static-source CI gate; no runtime, no infra, no secret, no
data path. Risk is confined to CI signal quality (false pos/neg over cron
classification). Mitigated by mirroring the proven `function-registry-count.test.ts`
source-scan idiom and grandfathering the current direct-spawn set explicitly. No
architecture concern; codifies ADR-033 + ADR-054 rather than introducing a new
pattern.

No Product/UX surface (no `components/**`, no `app/**/page.tsx`). No GDPR surface
(no schema/auth/API/regulated data). No new infrastructure (Phase 2.8 skip — pure
test file). The Observability gate (2.9) is satisfied above.

## Test Scenarios
1. **New hook-contained cron, unmapped** → gate RED with `CRON_BASH_ALLOWLISTS["<cron>"] = [...]` / `TIER2_DEFERRED_CRONS` remediation.
2. **New direct-spawn cron, not grandfathered** → gate RED pointing to `KNOWN_DIRECT_SPAWN_CRONS` + #5073 ephemeral-runner pattern.
3. **New pure-TS cron** → gate GREEN (no containment entry required).
4. **Existing tree (current 41 crons)** → gate GREEN.
5. **Fixture mutation (roadmap-review removed from allowlist clone)** → classifier flags `hook-contained / uncontained` (proves the gate bites).

## Sharp Edges
- The gate scans **source text** for `_cron-claude-eval-substrate` / `spawn(` —
  a cron that reaches claude or shell through an *indirection* the regex misses
  (e.g. a new shared helper that wraps `spawn`) would mis-classify as pure-TS.
  Mitigation: the gate also asserts the inverse (pure-TS ⇒ no containment entry),
  so an indirection that lands an entry in a map is still caught; and the
  direct-spawn grandfather set is a closed enumeration, so a *new* spawn site in a
  new file fails closed. If a future shared spawn-wrapper is introduced, extend the
  hook-contained / direct-spawn regex in the same PR.
- A plan whose `## User-Brand Impact` section is empty, contains only
  `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan`
  Phase 4.6. This plan's threshold is `none` with a stated reason — keep it.
- Do NOT force-fix `cron-content-publisher` into compliance — it is the deferred
  #5073 target. The gate classifies it (direct-spawn) and leaves remediation to
  that issue; "fixing" it here would step on a separate issue's contract.
