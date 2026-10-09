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
4. **Re-tier spend gate (standing, added 2026-10-09, #9790).** A class moves to a cheaper tier only after a pre-registered spend gate (threshold, saving factor, window and re-open triggers in the 2026-10-09 addendum) says the saving justifies an evaluation. A class that fails it stays where it is; this gates the evaluation, not the safety case.

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
| Inngest cron constants (web platform) | concrete IDs, partly dated | Hard-fail loudly; registry consolidation deferred to #5106. `AUDIT_EFFORT` (#8603) is the exception: an effort value the pinned CLI does not accept fails **silently** (fallback to the default effort), so it is gated by the CI probe in `claude-cli-pin-knows-models.test.ts` and mirrored to Sentry at runtime. |
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

> **Superseded 2026-10-08 (Haiku 5.5 launch):** the Haiku 4.5 row is replaced by Haiku 5.5, which
> bills $0.10 / $0.50 per MTok for prompts up to 100,000 tokens ($0.50 / $2.50 above), so Fable 5.1
> is 100× Haiku 5.5 on the short card. The table is left as recorded.

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

> **Superseded 2026-09-23 (#8611 review):** row 5b's `AUDIT_MODEL = claude-opus-5` is stale —
> `AUDIT_MODEL` is `claude-opus-5-5` since #8601 (same tier, cheaper on every price axis).
>
> **Superseded 2026-09-29 (#9236):** rows 5a and 6 name `claude-sonnet-5` — the execution tier,
> routers, and CI pins moved to `claude-sonnet-5-5` at the Sonnet 5.5 launch (same tier, same
> $2/$10 pricing, faster). The tiering judgments are unchanged.
>
> **Superseded 2026-10-08 (Haiku 5.5 launch):** row 5a's `claude-haiku-4-5` domain routing now runs
> on `claude-haiku-5-5` (same tier, $0.10/$0.50 per MTok up to a 100K-token prompt). The tiering
> judgment is unchanged; see the Haiku 5.5 addendum below.
>
> **Superseded 2026-10-09 (#9790):** row 6's "`claude-code-review.yml` ... fires **per PR**" is stale.
> The workflow has been `disabled_manually` since 2026-02-12 (workflow id 229704973, last run
> 2026-02-12), so it spends nothing today and is not eligible for a re-tiering evaluation until it is
> re-enabled; see the 2026-10-09 addendum below.

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

> **Superseded 2026-10-08 (Haiku 5.5 launch; Sonnet 5.5 cache-read correction):** two rows of the
> table above are stale, and the table is left as recorded.
>
> - **Haiku 4.5 is replaced by Haiku 5.5.** At cache-read rates Haiku 5.5 reads at $0.01/MTok for
>   prompts up to 100,000 tokens and $0.05/MTok above, against Sonnet 5.5 at $0.10. That is **10×**
>   cheaper than Sonnet 5.5 on the short card and **2×** on the long card. This restates the
>   comparison at the line item that dominates a multi-turn spawn, which is the basis this section
>   established; the headline input gap (20× on the short card, 4× on the long card) is the wrong
>   line item for this workload.
> - **The Sonnet cache-read rate is $0.10, not $0.20.** Anthropic prices Sonnet 5.5 cache hits at
>   0.05× base input, and the repo recorded $0.20 (0.1× base input, Sonnet 5's multiplier) until 2026-10-08. Against Sonnet 5.5 at $0.10,
>   Fable 5.1's $0.25 is **2.5×** (the "1.25×" above, and the "5× collapses to 1.25×" sentence, no
>   longer hold), and the light consult costs ≈$0.11 on Fable 5.1 against ≈$0.035 on Sonnet 5.5,
>   about **3×**. The ruling is unchanged (no pin moves, Fable stays a scoped-consult tier), and the
>   corrected gap is *wider*, which strengthens the case against widening Fable. The Re-evaluation
>   trigger below and the Opus 5.5 addendum's "cache-read rate equals Sonnet 5's" are stale in the
>   same way: Opus 5.5 ($0.20) is now 2× Sonnet 5.5 on cache reads.

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

## Addendum — 2026-09-23 (Opus 5.5 launch, PR #8601)

Claude Opus 5.5 (`claude-opus-5-5`, a dateless pinned snapshot) was released 2026-09-22 at
$4/$20 per MTok, with cache reads at 5% of input ($0.20). Surface 5b's `AUDIT_MODEL` moved
`claude-opus-5` → `claude-opus-5-5` (`server/inngest/model-tiers.ts`), together with the
`@anthropic-ai/claude-code` pin 2.1.219 → 2.1.280, the first CLI whose bundled model table
carries the id (the #6934 half-`max_tokens` class). The 2026-09-03 tables above are left as
recorded; at Opus 5.5 prices the Opus row reads 4 / 20 (2.5× cheaper than Fable 5.1 on input)
and its cache-read rate equals Sonnet 5's. The tiering decision itself is unchanged: the swap
is same-tier and cheaper per token. Opus 5.5's API default effort is `medium` (Opus 5: `high`);
the CLI sets effort itself, so this is a flag for the model-launch-review Thinking-API item,
not a config change. **(Superseded 2026-09-23, #8603 — see Amendment below.)**

## Amendment — 2026-09-23 (#8603)

Surface 5b now pins **effort alongside the model**: `AUDIT_EFFORT = "high"` in
`server/inngest/model-tiers.ts`, paired with `AUDIT_MODEL` in the single tuple `AUDIT_CLI_ARGS`
that the six audit crons spread into their `claude` argv (the "53" in the 2026-09-03 surface
table above is a miscount — measured 6 consumers). The CLI "sets effort itself" from the
per-model `default_effort` in its bundled table, and claude-opus-5-5's row reads `medium`, so
leaving effort unset silently lowered audit reasoning depth at the 5 → 5.5 swap with no argv
change. A tier whose rationale is reasoning depth cannot inherit an unowned default.

- Execution-tier crons stay on the CLI default. Their drift at a future launch is accepted, and it
  cannot happen silently: the CI test pins both tiers' `default_effort` in the installed bundle
  (`REVIEWED_DEFAULT_EFFORT` in `claude-cli-pin-knows-models.test.ts`), so a CLI bump that moves
  either value reds until someone re-decides `AUDIT_EFFORT` and accepts the execution default.
- Changing `AUDIT_EFFORT` is a same-tier tuning change, not re-tiering.
- "The pinned CLI knows every tier id and accepts the effort value" is now a CI invariant
  (`apps/web-platform/test/server/inngest/claude-cli-pin-knows-models.test.ts`), not only a
  hand-run audit item. An unknown `--effort` **value** is a warning plus a silent fallback to the
  default (exit 0), so the CI probe is the gate, and the cron substrate mirrors the warning to
  Sentry (`op: claude-effort-fallback`) at runtime.
- Considered and not taken: an `EXECUTION_CLI_ARGS` tuple for symmetry — it touches nine more
  crons and one event function, and the execution tier already has its chokepoint (every other
  `--model` argv names `EXECUTION_MODEL`, pinned by `model-tiers.test.ts`).
- Known constraint: `model-tiers.ts` now carries CLI argv (`AUDIT_CLI_ARGS`), and
  `model-tiers.test.ts` forbids naming `AUDIT_MODEL` anywhere in `server/inngest/functions/`. A
  future audit-tier caller that uses the Messages API instead of the CLI needs its own carve-out
  and its own effort mapping. Effort is a cron-registry attribute, not part of ADR-110's semantic
  tier map.

## Addendum — 2026-10-08: Haiku 5.5 launch re-evaluation

Claude Haiku 5.5 (`claude-haiku-5-5`, no dated suffix, released 2026-10-07) bills $0.10 / $0.50 per
MTok for prompts up to 100,000 tokens and $0.50 / $2.50 above (cache read $0.01 / $0.05), against
Haiku 4.5 at $1 / $5. It has a 1M-token context window, a 128K output ceiling, a tokenizer that
yields about 30% more tokens, adaptive thinking on by default, `effort` levels `low` to `max`
(default `medium`), no server-side fallback, and can return `stop_reason: "refusal"`. The 2026-09-03
tables are left as recorded (see the dated notes above). Cost-ledger semantics (the long-prompt rate
card, the Sonnet 5.5 cache-read regime boundary, and why the caps cannot see a sub-cent Haiku turn) live
in the [ADR-041 addendum](./ADR-041-byok-cap-enforcement-model.md), not here.

### Verdicts

Every model-selecting site was inventoried and judged against this ADR's Decisions 2 and 3 (mechanical
steps may go cheap; the never-downgrade list is excluded). Those decisions are written for workflow
spawn pins; applying them to server, CI and cron sites is an extension by analogy, stated here
rather than assumed. Two of the "Move now" sites, the domain
router and the email summarizer, read user text and were already Haiku-tier before this launch, so
their tier is unchanged by the verdict.

| Verdict | Sites | Reason |
|---|---|---|
| **Move to 5.5 now** | `domain-router`, email summarize, leader classes `triage.p0p1_issue` and `knowledge.kb_drift`, the CI preflight action, the manual retrieval bench `scripts/learning-retrieval-bench.sh` | Classification shape, same tier. `domain-router` and the summarizer send `effort: "low"`. The leader loop is unchanged: a live probe on 2026-10-08 (N=5 per cell) showed no truncation and 0/5 refusals on a security-flavored issue body, and a refusal ends in the existing `persistFailure` branch. The preflight probe at `max_tokens: 1` returned HTTP 200. |
| **Follows via alias** | Five `engineering/research/*` agents (`model: haiku`); workflow `'cheap'` pins | The `haiku` alias resolves to 5.5 on Claude Code CLIs at or above 2.1.293, so this repo's pin does not control it (the silent-retargeting row of the lifecycle table). Inside the Agent SDK's bundled CLI (0.3.284) the alias still resolves to Haiku 4.5, so product-runtime runs of these agents stay on 4.5 until the SDK bump. Measure with the transcript-grep recipe in a real `/plan` run; no edit. |
| **Candidate, not adopted (eval gate)** | `pdf-chapter-router` (Agent SDK, blocked on the SDK pin); the triage/summarize-shaped execution crons `cron-daily-triage`, `cron-follow-through-monitor`, `cron-campaign-calendar`, `cron-community-monitor`; workflow `'standard'` pins (`classify`, `parse`, `analyze`, `commit`, `report`, `cluster`, `detect-threshold`); CI `claude-code-review.yml` | Mechanical on paper, but the crons are multi-turn tool-using agents on the operator key whose failures are silent, and the pin allowlist and the CI `--model` swap each need their own attested change. Re-tiering a cron is "a separate clo-attestation-class model-bump PR" per the header comment of `apps/web-platform/server/inngest/model-tiers.ts`; this ADR's own clo-attestation clause (Decision item 3) applies to the workflow allowlist. A `claude-code-review.yml` swap also needs the coupled `claude-code-action` pin check. Tracked as the 2026-10-08 comment on #8643 (pdf-chapter-router to Haiku 5.5 after the SDK bump; the trigger is that issue's own bump, so it did not get a separate issue) and #9790 (one eval-gated re-tiering issue covering the execution crons and the `'standard'` to `'cheap'` pins, including `claude-code-review.yml`, so the `eval-harness` arm is built once). |
| **Not a fit** | `cron-compound-promote`, `cron-weekly-release-digest`, the audit tier and Concierge/leader reasoning classes, `cron-bug-fixer`, `fix-constraints-stage-a.yml`, `test-pretooluse-hooks.yml`, leader class `security.cve_alert` | Reads operator-session learnings or writes PRs, deep reasoning, agentic coding (the launch guidance says Haiku 5.5 is not for complex agentic coding), or security-flavored input where Haiku 5.5's cyber safeguards decline pentest-style prompts with no server-side fallback and a refusal would drop a real alert. |
| **Unchanged** | `cron-anthropic-credit-probe` (immaterial: about $0.00002 per call, the value is key liveness); advisor consults ([ADR-083](./ADR-083-scoped-strong-model-consult-at-decision-gates.md)) and the harness tier map ([ADR-110](./ADR-110-harness-semantic-model-tier-map.md)); the effort/model router (#6000, a future consumer of the five effort levels) | ADR-083 gates are judgment steps and stay on the advisor tier. ADR-110's `cheap` tier maps to the `haiku` alias on Claude, which follows the alias row above. |

> **Superseded 2026-10-09 (#9790):** the "Candidate, not adopted (eval gate)" row above is resolved for
> the crons, `claude-code-review.yml` and the `'standard'` pins by the Gate 0 verdicts in the
> 2026-10-09 addendum below: none qualifies for an eval, and nothing moves. `pdf-chapter-router` is
> unchanged (blocked on the SDK pin, recorded on #8643).

### SDK-path carve-out

Two scripts stay on `claude-haiku-4-5` because they call the Agent SDK, whose bundled CLI
(`claude-agent-sdk` 0.3.284) does not know the new id: `apps/web-platform/scripts/sandbox-canary.mjs`
and `apps/web-platform/scripts/plugin-root-sandbox-propagation-probe.mjs`. The tier is Haiku 5.5;
these two are the enumerated exception, so this ADR does not read as saying the tier is 5.5 while
they run 4.5. The carve-out retires when the SDK pin reaches 0.3.293, the first release that knows
the id, tracked on #8643 (whose own trigger, the next model launch, fired on this launch; the SDK gate it asks for was weighed and deferred because this launch puts no new id on the SDK path). Haiku 4.5 has no announced deprecation, so there is no urgency.

### Re-evaluation trigger

Re-run this review at the next Anthropic model launch, when the SDK pin reaches 0.3.293 (retire the
carve-out and take the pdf-chapter-router candidate recorded on #8643), or when an eval shows a candidate site above is safe on
Haiku 5.5 (take #9790). At each, quote cache-read rates, not headline rates, per the
section above.

> **Superseded 2026-10-09 (#9790):** "when an eval shows a candidate site above is safe on Haiku 5.5
> (take #9790)" is replaced by the Gate 0 re-open triggers in the 2026-10-09 addendum below. #9790's
> evaluation was gated on spend, not on an eval result, and no eval ran.

## Addendum — 2026-10-09 (#9790): Gate 0 spend verdicts and the Haiku 5.5 design questions

The 2026-10-08 addendum left five sites as "candidate, eval-gated" and tracked them on #9790. This
addendum applies a spend gate fixed BEFORE any eval exists, so the result cannot choose its own
threshold, and records what it found. The tiering policy above (Decisions 1-3) is unchanged. Gate 0
and the two conditional dispositions below are **standing rules of this ADR (Decision 4)**, not a
one-off verdict: later re-tiering reviews cite them as precedent. Gate 0 gates the *spend case for
running an evaluation*; it says nothing about whether a class would be safe on Haiku 5.5, and a class
that fails it is "not worth evaluating at current spend", never "unsafe". It sets no minimum sample
size for a class to *stay* on Sonnet 5.5 beyond the re-open triggers below.

### Gate 0 — method, assumptions, result

- **Measure.** `S` is the projected Sonnet 5.5 spend per 30 days, from `SOLEUR_CLAUDE_COST` markers
  in Better Stack, over the post-cutover window (2026-10-01 to 2026-10-09, nine days; per-run cost for
  all four crons fell about four to five times between 2026-09-29 and 2026-10-01, coincident with the
  Sonnet 5.5 migration, so windows straddling the change overstate the current regime and are not
  used). Daily crons: window sum / window days x 30. Weekday and weekly crons: mean paid run x runs
  per 30 days (21.4 and 4.3). Null or zero markers and missing days are reported because they bias
  `S` downward, the unsafe direction for a "nothing qualifies" verdict. Command: `scripts/betterstack-query.sh
  --since 20d --grep SOLEUR_CLAUDE_COST --limit 4000`, aggregated in `jq` on the structural
  `component == "claude-cost"` filter; the pull was re-run on the work date and reproduced the plan-time
  figures.
- **Saving factor.** 0.65 of `S` (Haiku may need more turns and retries). The ceiling, 0.87, is the
  cache-read price ratio after tokenizer inflation: 1 - (0.01 x 1.3) / 0.10, from Haiku 5.5's $0.01
  and Sonnet 5.5's $0.10 per MTok cache read (the line that dominates a spawn). It is shown for
  sensitivity only.
- **Threshold.** A class qualifies for an evaluation iff its saving is at least **$12.50 per month**:
  the 12-month saving must be at least three times an **assumed** $50 one-time cost to evaluate and
  move one class (about $10 of eval spend plus one implementer pipeline run). The $50 is an assumption,
  not a measurement.
- **Not eligible, never "not worth it".** A class that is disabled or unmetered is recorded as such.

| Class | `S` (Sonnet 5.5, per month) | Saving at 0.65 | At the 0.87 ceiling | Null or zero markers | Verdict |
|---|---:|---:|---:|---:|---|
| `cron-community-monitor` | $9.08 (13 runs, 9 days) | $5.90 | $7.90 | 0 | Stays on Sonnet 5.5: below the line |
| `cron-daily-triage` | $5.36 (9 runs, 9 days) | $3.48 | $4.66 | 0 | Stays: below the line |
| `cron-follow-through-monitor` | $3.10 (7 runs, 7 days) | $2.01 | $2.69 | 0 | Stays: below the line |
| `cron-campaign-calendar` | $1.56 (1 run, weekly; the five-run all-regime mean gives $5.91) | $1.01 | $1.35 | 0 | Stays: below the line, and a single post-cutover run is weak evidence |
| `claude-code-review.yml` | $0 | $0 | $0 | not applicable | Not eligible: disabled |
| `'standard'` workflow pins (`classify`, `parse`, `analyze`, `commit`, `report`, `cluster`, `detect-threshold`) | unmetered | not applicable | not applicable | not applicable | Not eligible: unmetered |

Nothing reaches $12.50. The only figure that does is the stale pre-cutover 14-day community-monitor
window at the ceiling factor ($15.18), recorded as the reason the regime change matters. Nothing is
moved: `PIN_ALLOWLIST` in `plugins/soleur/test/workflow-model-pins.test.ts` and
`apps/web-platform/server/inngest/model-tiers.ts` are untouched, so this review needs no clo-attestation
change. The `'standard'` pins sit in opt-in `Workflow`-tool ports of the review skill (the prose skill
is the default) and nothing meters workflow spawns (finding 1 above), so there is no spend to project.

**Re-open triggers.** At each `model-launch-review`; whenever any class's post-cutover `S` reaches
$19.23 per month (= $12.50 / 0.65); when `claude-code-review.yml` is re-enabled; or when workflow
spawns become metered. A class that then qualifies moves in its own separately attested PR, with an
`eval-harness` arm of Sonnet 5.5 control against Haiku 5.5, the production prompt constant imported
rather than copied, synthesized fixtures, and every failure mode of the class tied to a production
detector. A capped, rate-limited or under-powered arm is "stays: insufficient evidence", never a pass.

### Which model the claude-code CLI reports (pinned 2.1.293, measured)

Four cells with the spend-limited eval key (about $0.058 in total, one synthesized prompt each):

| Cell | `--model` | Tools | `modelUsage` keys |
|---|---|---|---|
| a | `claude-sonnet-5-5` | none | `claude-sonnet-5-5` |
| b | `claude-sonnet-5-5` | Bash (one `echo`) | `claude-sonnet-5-5` |
| c | `haiku` (alias) | none | `claude-haiku-5-5` |
| d | `claude-sonnet-5-5` | WebFetch of a synthetic page | `claude-sonnet-5-5` and `claude-haiku-5-5` |

The `haiku` alias resolves to Haiku 5.5 on 2.1.293, which confirms the "Follows via alias" row. The
CLI's internal small and fast call (the WebFetch page summarizer) reports Haiku 5.5. Bash-only runs
emit no internal call, and the cron prompts are Bash-only, so the cron cost shift cannot come from
internal calls. Attribution limit: `_cron-claude-eval-substrate.ts` records the first `modelUsage` key
as the marker's `model` while `cost_usd` is the all-model total, so a run that does trigger an internal
call is attributed to whichever key the CLI lists first. No code change.

### Dispositions of the open design questions

- **Leader-loop effort: no change.** A leader turn that truncates dead-letters as
  `leader_response_truncated`, which pages through `spawn-agent-dead-letter` (it is in
  `PAGED_DEAD_LETTER_REASONS`). Rule: on the first such page for a Haiku class, add `effort: "low"` to
  that `LeaderPromptModule` and bump its `promptVersion`, and plan that change at the
  `single-user incident` threshold, because it alters the shared founder BYOK handler's input.
- **Refusal and a Sonnet retry: no retry mechanism.** `leader_refused` already pages on its first
  occurrence. Rule: decide a Sonnet 5.5 retry only if two or more `leader_refused` pages arrive for
  non-adversarial input within 30 days, using that observed rate.
- **`no-text-block` mirrors: alerted.** The router and the summarizer report `op: "no-text-block"`
  when a Haiku turn has no text block, ends at `max_tokens` or is refused, and nothing alerted on it.
  `sentry_alert.haiku_no_text_block_rate` now emails the issue owners (ActiveMembers fallthrough) when
  one such issue accrues four events in an hour, a rate and not a first-seen page because one empty
  turn is expected noise. `test/sentry-no-text-block-alert-op-contract.test.ts` derives the emit sites
  by scanning `server/` and refuses a rule that omits or adds one. The threshold of 4 is
  **provisional**: the emit sites shipped on 2026-10-08 and no baseline exists. Recalibrate it from the
  first 14 days of data (on or after 2026-10-23), or sooner if the first alert email is judged noise
  or an incident is found that it missed. The owner is whoever next edits
  `apps/web-platform/infra/sentry/issue-alerts.tf` or reads an alert email from this rule; the
  threshold's comment in that file carries the same date. The rule counts events across all users per
  issue, so it cannot see one user's streak of degraded turns (for example one founder's inbound
  mail filed as class `other`); that residual is accepted and is not detected by this rule.

## Alternatives considered

| Alternative | Rejected because |
|---|---|
| Frontmatter tiering (pin research agents to `sonnet`) | Context-blind (applies in every spawn context), silently upgrades cheap sessions, re-fights the deliberate 2026-02-24 reversal of the one prior tiering attempt |
| Session-relative tiers ("one below session") | Runtime supports absolute values only; non-deterministic cost contract |
| `TIER_PINS` per-workflow map (single source for pins + disclosure log) | Contradicted the allowlist-test/grep gates (map reference vs inline literal); deleted at 5-agent plan review — inline literals + adjacent log line + the standing allowlist test cover the same drift risk mechanically |
| Tee-hook-only telemetry attribution | Empirically impossible for workflow spawns (finding 1 above) |
| Leave audit-cron effort to the CLI's per-model default (#8603) | The default moved high → medium at the Opus 5 → 5.5 swap with no argv change; a tier whose rationale is reasoning depth cannot inherit an unowned default |

## Consequences

- BYOK operators save ~65-80% per mechanical fan-out run (CFO estimate); flat-rate operators gain quota headroom.
- The review layer (never pinned) remains the quality safety net for the execution layer — the brand-survival invariant at `single-user incident` threshold.
- The allowlist test converts the prose never-downgrade policy into a CI-blocking gate.
- Decision 4 makes future re-tiering a spend question first: the 2026-10-09 addendum applies it and moves nothing.
