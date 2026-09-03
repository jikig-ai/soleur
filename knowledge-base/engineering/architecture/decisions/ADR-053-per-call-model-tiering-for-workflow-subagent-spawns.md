# ADR-053: Per-call model tiering for workflow subagent spawns

- **Status:** Accepted
- **Date:** 2026-06-10
- **Issue:** #3791 (re-opened by the Fable 5 pricing trigger; deferred 2026-05-15)
- **Supersedes (partially):** the "no exceptions" clause of the Model Selection Policy (PR #295, 2026-02-25) — frontmatter inheritance is unchanged; the workflow call-site tier is new.

## Context

Fable 5 prices at $10/$50 per MTok — 2× Opus 4.8, 3.3× Sonnet 4.6, 10× Haiku 4.5. **(Basis
superseded 2026-09-03 — see the Fable 5.1 re-tier review below. Sonnet 5 bills $2/$10, so the
Fable-vs-Sonnet multiple is now 5×, not 3.3×. The ratios in this paragraph are retained as the
basis the original decision was made on, not as current pricing.)** All 66 plugin agents use `model: inherit` and no workflow script passed `opts.model`, so a Fable 5 session ran every mechanical subagent step (diff classification, GitHub-issue filing, comment fetching, commit-message generation, report assembly) at top-tier rates. Anthropic's agent-design guidance endorses cheaper-model subagents for sub-tasks, and the web platform already tiers in production (Sonnet crons, Haiku routing, deliberate sonnet→opus upgrades for scoring workloads).

## Decision

1. **Frontmatter stays `inherit` for all agents** (operator session-model agency preserved; overrides still need written justification).
2. **Workflow scripts MAY pin `opts.model` at mechanical steps only** — 12 allowlisted call sites at adoption (see `plugins/soleur/test/workflow-model-pins.test.ts`, the mechanical gate). Each pin carries a one-line justification comment. Pin style is single-quoted inline literals (`model: 'sonnet'`) — workflow scripts are self-contained by design, so no shared map or import.
3. **Never-downgrade exemption list** (judgment paths): review dimensions, verify/concur adjudication, synthesis/merge, resolvers/implementers, per-cluster `one-shot`, `agent-native-audit` enumeration scoring, plan-review reviewers/consolidate, deepen-plan research/merge, `resolve-parallel` `plan`. Changing the allowlist is a clo-attestation-class change.

## Semantics

- **Pins are absolute, not session-relative.** A pinned step always runs the pinned tier. Consequence: a pin can run ABOVE a cheaper session (Haiku session + `sonnet` pin = Sonnet, a cost upgrade over the operator's chosen tier). The per-run tier `log()` line in each pinned workflow is the disclosure. Session-relative ("one tier below session") was rejected: the runtime only supports absolute values, and relative tiers make cost/quality non-deterministic per session.
- **No fallback on rejection.** If a pinned model is rejected/rate-limited, `agent()` returns null after retries; fan-outs `.filter(Boolean)`, single steps follow each workflow's existing null-handling (a failed `classify` aborts the review run — pre-existing behavior).

## Telemetry and verification (empirical findings, 2026-06-10 capture)

Phase 0 of the adoption PR captured ground truth with a one-spawn probe workflow:

1. **The PostToolUse `Task` hook does NOT fire for Workflow-runtime `agent()` spawns.** `.claude/.session-tokens.jsonl` (agent-token-tee, #3494) gains no row for workflow spawns; its coverage is direct Agent-tool spawns only. The tee hook's new `model` field (`.tool_input.model // "inherit"`) therefore attributes DIRECT spawns only.
2. **The executed model for workflow spawns IS recorded in the workflow run's transcript** — `<session-transcript-dir>/subagents/workflows/<run-id>/agent-<id>.jsonl` assistant messages carry `"model":"claude-haiku-4-5-20251001"` (probe evidence). This is execution-side evidence, stronger than request-side `tool_input.model`.
3. **Verification recipe (workflow pins):** after a run, `grep -ho '"model":"[^"]*"' <run-transcript-dir>/agent-*.jsonl | sort | uniq -c` — pinned spawns show the pinned tier's concrete ID; judgment spawns show the session model.
4. **Rejected-pin signature:** for direct spawns, absence-of-row (the tee hook drops zero-token envelopes), never `model:"inherit"`; for workflow spawns, the workflow's own null-handling log line.

## Pin-surface lifecycle (three surfaces age differently)

| Surface | Form | At model deprecation |
|---|---|---|
| Plugin workflow pins | harness enum alias (`'sonnet'`, `'haiku'`) | Zero repo maintenance — but subject to **silent retargeting**: the harness re-aiming an alias to a successor generation changes every pin's cost/behavior contract with no repo diff and no CI signal. The transcript grep (above) is the only way to observe which concrete model an alias resolved to. |
| CI pins (`claude_args: '--model claude-sonnet-4-6'`) | concrete ID | Hard-fails loudly (404) at retirement; re-pin is a one-line edit + action-pin sync (learning 2026-04-18). |
| Inngest cron constants (web platform) | concrete IDs, partly dated | Hard-fail loudly; registry consolidation deferred to #5106. |
| SKILL.md prose advisories | harness enum alias in prose | Advisory-only, no mechanical gate; discoverable via `grep -rn 'model: sonnet\|model: haiku' plugins/soleur/skills/*/SKILL.md`; mechanical-step classes only, must cite this ADR. |

#5100 (`model-launch-review` skill) is the re-pin trigger for all three surfaces at each model release.

## Fable 5.1 re-tier review (2026-09-03, #7774)

`model-launch-review` (#5100) is the re-pin trigger for all three pin surfaces at each model
release. Fable 5.1 launched; this section records the review it triggered. **Outcome: no pin
moves.** Recorded because "we looked and changed nothing" is a result, and without it the next
launch re-derives this from scratch.

### What actually changed in the pricing

Fable 5.1 costs **the same per token as Fable 5** — $10 input / $50 output per MTok. The only
delta is the **cache-read** rate: **$1.00 → $0.25 per MTok** (0.1× → 0.025× of base input).
Output and cache writes are unchanged.

The consequence is narrow and easy to overstate: Fable 5.1 is cheaper than Fable 5 **only where
a warm prefix is re-read**. It is not cheaper on input, not cheaper on output, and identical on
a cold call.

Separately, the comparison basis moved underneath this ADR. Sonnet 5 bills $2/$10 (the
2026-08-31 intro-pricing expiry to $3/$15 was **cancelled**), so the tier spread is now:

| tier | $/MTok in-out | vs Fable 5.1 |
|---|---|---|
| Fable 5.1 | 10 / 50 | 1× |
| Opus 5 | 5 / 25 | 2× |
| Sonnet 5 | 2 / 10 | **5×** (was 3.3× vs Sonnet 4.6) |
| Haiku 4.5 | 1 / 5 | 10× |

The Fable-vs-Sonnet gap **widened**. Every judgment in this ADR that leaned on 3.3× is therefore
conservative in the safe direction: the case for pinning mechanical steps down to Sonnet is
*stronger* now, not weaker.

### Surface-by-surface verdict

Six surfaces, after review found surface 5 conflated two populations with different
funding and different protections, and found a sixth the first draft had no row for.

| Surface | Population | Fable candidates | Why |
|---|---|---|---|
| 1. Agent frontmatter | 64 `inherit`, 5 `haiku`, 1 unset (68 agents) | **none** | This ADR rejects upgrade pins here by design — a frontmatter upgrade silently overrides a cheaper session the operator chose. The `haiku` floor is safe precisely *because* it cannot upgrade. |
| 2. Workflow call-site pins | 12 pins (10 `sonnet`, 2 `haiku`) | **none, by construction** | Every pinned site is mechanical — parse, classify, cluster, fetch, commit-message, report, file-issue. This ADR forbids pinning judgment steps, and Fable is a judgment tier. |
| 3. Never-downgrade list | review / security / legal / C-suite / scoring | **none** | Deliberately `inherit` so a stronger session model flows through. Pinning Fable here would *cap* a Fable session at no gain and *upgrade* a Sonnet session without consent. |
| 4. SKILL.md prose (ADR-083) | 2 gates, unchanged | the only place Fable can live | Scoped, curated-payload. A third gate was proposed at `review` findings-synthesis and **shipped unpinned** — it could not clear ADR-083's admission rule (no session-model counterfactual was run), so it runs at the session model and is not an ADR-083 gate. The two-gate bound is now enforced by `plugins/soleur/test/fable-consult-gates.test.ts`. |
| 5a. Product runtime — **founder BYOK** | `claude-sonnet-5` leader loop + routers, `claude-haiku-4-5` domain routing | **none** | Spend is capped by ADR-041's 260¢ per-spawn ceiling. Fable's 5× output multiple would exhaust it far faster for the same work. |
| 5b. Product runtime — **operator-key crons** | `AUDIT_MODEL = claude-opus-5` (`server/inngest/model-tiers.ts`), consumed by 53 `cron-*.ts` functions | **none** | These do **not** run on founder BYOK — `cron-agent-native-audit.ts` states "Operator ANTHROPIC_API_KEY only; never founder BYOK", enforced by `test/server/cron-no-byok-lease-sweep.test.ts`. So the 260¢ ceiling does **not** protect them; they spend Soleur's own uncapped money. Ruled out instead by ADR-053's never-downgrade list (enumeration-scoring is the sonnet→opus upgrade precedent) — Opus is already the deliberate tier, and Fable's 5× output multiple on report-shaped crons lands at 1.6–1.75× Opus with no judgment gain. |
| 6. CI / GitHub Actions | `claude-code-review.yml` pins `--model claude-sonnet-5` and fires **per PR**; `fix-constraints-stage-a.yml` and `test-pretooluse-hooks.yml` pin the same; 13 `scheduled-*.yml` crons default to `claude-sonnet-5` via `schedule/SKILL.md` | **none** | `claude-code-review.yml`'s own comment cites ADR-053 and calls itself "an unbounded per-PR spend surface" — it is a supplementary advisory commenter, exactly the mechanical/advisory class this ADR pins DOWN. Upgrading it would multiply an already-unbounded surface by the PR rate. |

### A Task spawn is cache-read-dominated — measured, after a first draft asserted the opposite

The first draft of this section claimed the consult gates are "cold single-shot spawns with no
reused prefix", so "their cache reads are ≈0" and Fable 5.1's improvement moves Soleur's advisor
spend "by ≈nothing". **That was wrong by roughly six orders of magnitude**, and it is corrected
here rather than quietly replaced because the error is instructive.

Measured 2026-09-03 over the 17 Task-subagent transcripts this session produced, summing
`message.usage` per spawn:

| | tokens |
|---|---|
| spawns | 17 |
| assistant turns | 683 |
| **cache-read input** | **56,998,076** |
| cache-creation input | 4,990,375 |
| uncached input | 1,766 |
| output | 247,275 |

**Cache reads were 100.00% of input volume**, averaging **3.35M tokens per spawn**. The lightest
spawn in the set (7 turns) still read **227,239** cached tokens.

The error was conflating two different propositions:

- **Across spawns** — no reused prefix. True, and defensible: caches are model-scoped and each
  gate fires once with a unique authored payload.
- **Within a spawn** — cache reads ≈0. **False.** A Task subagent is an agentic loop. Turn 1
  writes the cacheable prefix (system prompt + tool definitions + payload); every subsequent turn
  re-sends and reads it. Nothing in ADR-083 or the three gate texts restricts tool access or turn
  count, and the `review` gate's own question ("which file would it live in?") invites file reads.

This repo already contained the refutation. `plugins/soleur/AGENTS.md` justifies avoiding the
built-in advisor because it "re-sends the full transcript **uncached** every call" — which is only
a distinguishing defect if ordinary Task spawns *are* cached. The claim and its counter-evidence
sat in the same corpus on the same day.

### What that does to the tier comparison

Because cache read is the dominant input component, the headline `$10/$50` multiples describe the
*wrong* line item for this workload. At cache-read rates:

| tier | cache read $/MTok | vs Sonnet 5 |
|---|---|---|
| Fable 5 | 1.00 | 5× |
| **Fable 5.1** | **0.25** | **1.25×** |
| Opus 5 | 0.50 | 2.5× |
| Sonnet 5 | 0.20 | 1× |
| Haiku 4.5 | 0.10 | 0.5× |

So the **5× Sonnet** figure holds for output and uncached input, and collapses to **1.25×** on the
component that actually dominates a spawn. A light consult (~250k cache read + ~1k output) costs
≈$0.11 on Fable 5.1 against ≈$0.06 on Sonnet 5 — about **1.8×**, not 5×.

Two conclusions change shape:

1. **Fable 5.1 IS materially cheaper than Fable 5 for Soleur** — roughly 75% off the dominant
   component, ~$2.51 per spawn at the measured 3.35M average, or ~$0.17–0.21 on a light consult.
   The upgrade remains free (the `model: fable` alias is version-agnostic), so this is a saving
   Soleur receives without any pin change.
2. **The case against widening Fable is weaker than the 5× headline suggests.** It does not vanish
   — output stays 5× and a Fable spawn that reads many files is expensive in absolute terms — but
   "5× Sonnet" must not be quoted as the cost of a consult.

### Verdict, restated on the corrected basis

No pin moves, for a different reason than the first draft gave: not "5.1 does not help", but
**"5.1 helps, and the alias delivered it with nothing to change."** Surfaces 1, 2, 3 and 5 are
ruled out by policy and by workload shape, not by pricing — nothing in the corrected numbers
reaches them.

### Re-evaluation trigger

### Aggregate, so the numbers have a denominator

`git log origin/main --since=30.days --oneline | grep -cE '\(#[0-9]+\)$'` → **144 squash-merged
PRs in 30 days**, over **23 active days** (~6.3/active-day, ~4.8/calendar-day). Note the count
needs the `(#N)` form: this repo squash-merges, so `--merges` returns **0** and would read as "no
PRs merged". And
`rf-never-skip-qa-review-before-merging` makes a review mandatory per PR. `review/SKILL.md`
records two measured panel costs — ~880k subagent tokens (one incident) and ~1.2M tokens
(another) — which at session-model rates puts the review line item on the order of
**$300–$1,700/month**. Any per-consult figure argued in this ADR should be quoted against that,
not in isolation. Note that `knowledge-base/finance/api-spend-ledger.jsonl` (the ADR-056 CI spend
ledger) is currently **empty**, so those two token figures are the only measured baseline the
repo has.

Unchanged: `model-launch-review` (#5100) at each model release. The first draft of this section
made the trigger *"does any site re-read a large warm prefix?"* and answered it "false everywhere"
without measuring — which would have enshrined the same error as a standing test. **Replaced with
a measurement, not a premise:**

```bash
# Cache-read share and per-spawn volume, over this session's Task transcripts.
# Aggregate only — never emit transcript content.
python3 - <<'EOF'
import json,glob
cr=ci=n=0
for f in glob.glob("<session-tasks-dir>/*.output"):
    for line in open(f,errors="replace"):
        if not line.startswith("{"): continue
        try: u=(json.loads(line).get("message") or {}).get("usage") or {}
        except Exception: continue
        cr+=u.get("cache_read_input_tokens",0) or 0; ci+=u.get("input_tokens",0) or 0
    n+=1
print(f"spawns={n} cache_read={cr:,} uncached={ci:,} share={100*cr/max(cr+ci,1):.2f}%")
EOF
```

Run it, then ask whether the new model's **cache-read** rate — not its headline input/output rate
— changes any tier decision. On 2026-09-03 that share was 100.00% at 3.35M tokens/spawn.

## Alternatives considered

| Alternative | Rejected because |
|---|---|
| Frontmatter tiering (pin research agents to `sonnet`) | Context-blind (applies in every spawn context), silently upgrades cheap sessions, re-fights the deliberate 2026-02-24 reversal of the one prior tiering attempt |
| Session-relative tiers ("one below session") | Runtime supports absolute values only; non-deterministic cost contract |
| `TIER_PINS` per-workflow map (single source for pins + disclosure log) | Contradicted the allowlist-test/grep gates (map reference vs inline literal); deleted at 5-agent plan review — inline literals + adjacent log line + the standing allowlist test cover the same drift risk mechanically |
| Tee-hook-only telemetry attribution | Empirically impossible for workflow spawns (finding 1 above) |

## Consequences

- BYOK operators save ~65-80% per mechanical fan-out run (CFO estimate); flat-rate operators gain quota headroom.
- The review layer (never pinned) remains the quality safety net for the execution layer — the brand-survival invariant at `single-user incident` threshold.
- The allowlist test converts the prose never-downgrade policy into a CI-blocking gate.
