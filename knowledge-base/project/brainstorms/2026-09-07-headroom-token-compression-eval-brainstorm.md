---
title: "Headroom token-compression layer — adopt for Soleur dev usage and/or Soleur users?"
date: 2026-09-07
status: decided-verified
lane: cross-domain
brand_survival_threshold: single-user incident
tags: [token-cost, context-engineering, external-tool-eval, vendor-review]
related_adrs: [ADR-151, ADR-056, ADR-041, ADR-155]
related_issues: []
---

# Headroom — token-compression layer evaluation

## The question

> "I saw this project <https://github.com/headroomlabs-ai/headroom>. Is this something we
> could use to effectively save tokens for our usage and any soleur users?"

Two halves, different answers. Both resolve to **no**, for independent reasons.

## What Headroom actually is (verified, not summarised from the pitch)

Apache-2.0, Python, 69,783 stars, created 2026-01-07 (242 days old), pushed same-day.
Compresses tool outputs, logs, RAG chunks and files *before* they reach the LLM.
Compression runs locally; no prompt or file content is sent out to be compressed.

- **Modes:** library `compress(messages)`; local proxy; `headroom wrap claude`; MCP server.
- **Live-zone compression:** only new bytes are compressed; the frozen prefix stays
  byte-identical, so the provider KV-cache prefix survives. This is a genuinely good design
  and it disposes of the obvious "it will bust your prompt cache" objection.
- **CCR:** originals cached locally, retrievable by the model on demand.
- **Vendor's own caveat:** "prose and already-dense payloads see little or no reduction";
  blocks under `min_input_words` return byte-identical.
- **Telemetry:** anonymous beacon **on by default** (`README:592`), reporting ratios,
  counters, provider/model IDs, OS/arch — never prompts or code. Off via `HEADROOM_BEACON=off`.

This is a competently engineered project. The verdict below is about fit, not quality.

## Why it does not pay off for us

### 1. Economics — weaker than first stated (operator correction, 2026-09-07)

ADR-056 records the billing shape: local Claude Code autonomous loops (`one-shot`,
`drain-labeled-backlog`, `test-fix-loop`) run on the operator's **flat Max 20x
subscription — $0 marginal per run**. The only metered path is two CI
`claude-code-action` jobs on `ANTHROPIC_API_KEY`, and
`knowledge-base/finance/api-spend-ledger.jsonl` has **0 entries**.

**This argument was originally overstated in two directions. Corrected:**

1. **Flat subscription ≠ free.** Tokens on Max 20x convert into *rate-limit
   exhaustion* — hitting the 5-hour window sooner is a real throughput cost to the
   operator, just denominated in wall-clock rather than dollars. "$0 marginal" is true of
   the invoice and false of the constraint that actually binds.
2. **The argument does not transfer to the user half at all.** Soleur users run
   **BYOK** (ADR-041): tokens are billed to *their own* Anthropic key. For them token
   reduction is real money saved. Any claim of the form "there is no cost to reduce" is an
   operator-side fact and must not be reused as a reason to reject a user-facing
   optimisation.

So economics is **not** a load-bearing ground for rejecting the user half. That half
stands on §3 (correctness), the BYOK-credential-path defect, and surface mismatch. On the
operator half economics is weakened but survives, because §2 caps the reachable benefit —
including the rate-limit benefit — at 2–3%.

### 2. Mechanics — the compressible surface is ~2–3% of our tokens

Measured independently over 42 local transcripts, 44,620 assistant messages
(`~/.claude/projects/…/*.jsonl`, verified twice — once by the CTO agent, once directly):

| Token class | Share |
|---|---:|
| `cache_read_input_tokens` | **98.17%** |
| `cache_creation_input_tokens` | 1.60% |
| `output_tokens` | 0.23% |
| uncached input | 0.00% |

Three compounding reasons the reachable share is tiny:

- **The frozen prefix is untouchable by design.** `AGENTS.md` + `AGENTS.rules.md` = 46,000 B
  (~11.5k tokens) re-read every turn (ADR-151, unconditionally loaded). Live-zone
  compression deliberately never rewrites it.
- **Our tool output is small.** `tool_result` is 29.1% of content bytes, median **410 B**,
  p90 2,350 B — most of it below any plausible `min_input_words`, so it comes back
  byte-identical.
- **Our payload is prose.** `knowledge-base/` is 1.75 MB of markdown; the four skill bodies a
  one-shot run loads (`plan`+`work`+`review`+`ship`) are 1.14 MB ≈ 286k tokens of English.
  Prose is precisely the class Headroom itself says compresses least.

Theoretical ceiling ≈ 0.291 × 0.551 × 0.35 ≈ **5.6%** of conversation bytes; realistic
**2–3%**. Against that, any perturbation near the cache prefix costs a full 2× re-write of
~11.5k tokens. Break-even is roughly one cache invalidation per two turns.

### 3. Correctness — this is the disqualifier

Soleur's workflow is a verbatim-string machine. Lossy compression of **tool output** would
manufacture false negatives in exactly the gates written to prevent false negatives:

| Gate | Failure under compressed tool output |
|---|---|
| `hr-verify-repo-capability-claim-before-assert` | Discharged by "grep the source". A summarised empty-looking result *is* the false negative the rule exists to stop. |
| `hr-third-party-content-grep-on-undertaking` | A missed grep hit ships a privacy violation. |
| `hr-type-widening-cross-consumer-grep` | A dropped call site is a silent widening bug. |
| `cq-assert-anchor-not-bare-token`, `cq-cite-content-anchor-not-line-number` | Convention-only, **no gate enforces them** — nothing downstream catches the miss. |
| `eval-harness/scripts/extract-block.cjs` | `indexOf()` on `<!-- eval-gate:block:*:start -->` across 65 sites; one rewritten comment → fail-closed throw or wrong projection. |

**CCR retrieval does not mitigate this — it relocates it.** Retrieval is model-initiated, and
the failure mode is an agent *confident it already has the answer*. A compressor that makes an
absence look like a result gives the model no signal to retrieve. That is ADR-151's
"appears enforced, is absent" class, re-introduced one layer down.

Trading a small token reduction for a non-zero chance of a silent gate miss is a bad trade at
any price.

### 3b. Measured — the falsification test was run, and both conditions failed

The §3 argument was a prediction. It was then **tested empirically** (2026-09-07), per the
pre-registered falsification criteria: adopt only if measured reduction **>15%** AND **zero
gate divergence**.

**Method.** `headroom-ai==0.37.0`, Python 3.12.9, **library mode only** (`compress()`), offline
— no proxy, no `wrap`, no `~/.claude.json` write, `HEADROOM_BEACON=off`. Corpus: **2,252 unique
`tool_result` payloads ≥2 kB** extracted from 42 local Claude Code transcripts (10.2 MB;
median 3,353 B, p90 8,124 B). Payloads were replayed inside a realistic agent conversation
(`tool_use`/`tool_result` blocks interleaved with assistant turns) so they fell outside the
`protect_recent` window. Token counts via `tiktoken` `cl100k_base`.

| Falsification condition | Threshold | Measured | Verdict |
|---|---|---|---|
| Token reduction | > 15% | **6.69%** (2,816,205 → 2,627,824) | **FAIL** |
| Gate divergence | zero | **244 of 581 modified payloads lose ≥1 gate-relevant literal** | **FAIL** |

581/2,252 payloads (25.8%) were modified at all. Losses among the modified set:

| Gate-relevant literal | Instances lost |
|---|---:|
| `file.ext:line` citations | **2,367** |
| commit SHAs / `#PR` refs | 256 |
| `SOLEUR_*` observability markers | 8 (incl. `SOLEUR_TEST_ALL_CEILING_UNAVAILABLE`) |
| `<!-- eval-gate:block:*-->` markers | 0 |
| `[id: rule-slug]` anchors | 0 |

**The mechanism is worse than truncation — it is restructuring.** On `grep -rn` output
Headroom factors the repeated filename into a header and leaves bare line numbers beneath it:

```
before:  ./apps/web-platform/infra/inngest-server-flip-guard.test.sh:125:  "ExecStart=…
after:   ./apps/web-platform/infra/inngest-server-flip-guard.test.sh
         125:  "ExecStart=…
```

Information is fully preserved; the **literal token is destroyed**. A human or model reading it
loses nothing. A gate discharged by `grep "<file>:<line>"` returns *no match* — and because the
output still reads complete and authoritative, nothing anywhere signals that a CCR retrieval is
warranted. This is precisely the "confident false negative" shape §3 predicted, arrived at by a
route (helpful reformatting) that no reviewer would flag as lossy.

Two honest caveats, neither of which rescues the verdict:

- **The prose model was not exercised.** `headroom-ai[ml]` (Kompress-v2-base) pulls torch 2.14
  plus the full CUDA toolkit (~30 packages, multiple GB) and was not installed. So 6.69% is
  SmartCrusher + CodeCompressor only, and the true reduction is **higher** than measured.
  It does not matter: the second condition is *zero* divergence, and a lossy prose compressor
  can only raise divergence, never drive it to zero. The test is conclusive on condition 2
  regardless of condition 1.
- Two literal classes survived intact (`eval-gate:block` markers, rule-id anchors), so the
  damage is not universal. It is, however, concentrated exactly on `file:line` citations —
  the single most common evidence form in our review and verification loops.

Reproduction artifacts: `/tmp/…/scratchpad/hr-eval/` (`run_eval.py`, `divergence.py`, corpus).
Not committed — transcript-derived payloads contain operator paths and session content.

### 4. `headroom learn` — separable, and must stay unused

It mines failed sessions and writes corrections into `CLAUDE.local.md` (default), `CLAUDE.md`
or `AGENTS.md`. Our rule corpus sits at **exactly 46,000 B**, the critical ratchet in
`scripts/lint-agents-rule-budget.py`; one appended line trips it. It would also bypass
`cq-agents-md-tier-gate` placement, `cq-rule-ids-are-immutable`, ADR-155 exemption markers,
and `scripts/lint-rule-bodies.py`'s WORM ack manifest. Separable only by never running it.

## Why it does not reach Soleur users

Structural, not ergonomic. Per `roadmap.md`, the product pivoted plugin-first → **cloud-first**:
end users run agents in a **server-side sandbox** (`apps/web-platform/server/agent-runner.ts`,
Agent SDK). There is no local machine in the loop — no `~/.claude.json`, no port, no `uv`.
`business-validation.md:48` records that most founders interviewed do not use Claude Code at
all and want a visual UI.

The only way to insert Headroom on that surface is `ANTHROPIC_BASE_URL` → a sidecar proxy
inside the sandbox. That is currently **unset anywhere in the codebase** (verified), and it
would place a third-party proxy in the **BYOK credential path**, where users' own Anthropic
keys flow. It would also desynchronise ADR-041's fail-closed cap accounting (which counts
tokens for a hard spend cap) from the bill the user actually receives. That is a
billing-integrity defect, not an optimisation.

Automating local install for a user would also convert "user misconfigured it" into
"**Soleur** broke it": dead proxy → all agent calls fail; stale wrap after a `uv` upgrade;
port conflict; corrupted `~/.claude.json`. `headroom wrap` writes Serena at **user scope**,
so the blast radius reaches the founder's unrelated repos. Single-user incident, pre-beta,
with no support org.

## Legal — not the blocker

- **Anthropic ToS: no violation, either auth mode.** Consumer Terms §3 carves out API-key
  access; `code.claude.com/docs/en/llm-gateway` explicitly documents `ANTHROPIC_BASE_URL`
  with a saved claude.ai login remaining the active credential. Headroom's shape is a
  *documented* configuration. Guardrail: if it ever strips or forges the OAuth capability in
  `anthropic-beta` to keep subscription sessions alive, that crosses into §3 circumvention.
- **Not a sub-processor.** `article-30-register.md:747` (Posture A, re-keyed 2026-08-06 /#7331
  onto *whose credential effects the processing*): software on the user's machine, under the
  user's credential, for the user's purposes creates no Art. 28 relationship. No register row.
  Do not over-claim one.
- **Apache-2.0:** §4 obligations trigger on distribution, not use. **Depend; do not vendor.**
- **Supply chain:** 242 days old, 63% of commits from one contributor, sits in both the auth
  path and the full content path. Stars are not a control.

## Key Decisions

| # | Decision | Rationale |
|---|---|---|
| 1 | **Do not adopt Headroom for Soleur dev usage.** | Reachable surface 2–3% (caps both the dollar and the rate-limit benefit); correctness risk to verbatim-grep gates is unbounded. Flat Max 20x means the benefit is throughput, not money — but 2–3% does not move throughput either. |
| 2 | **Do not recommend, bundle, or automate it for Soleur users.** | Users have no local agent — cloud sandbox. Proxy insertion would sit in the BYOK credential path and desync ADR-041 cap accounting. **Not** rejected on cost grounds: BYOK users pay real dollars per token, so the operator's "$0 marginal" fact does not apply to them. |
| 2b | **BYOK token reduction remains an open, legitimate user-value goal** — just not via a third-party proxy in the credential path. | Corrected 2026-09-07: users are billed on their own key, so reducing their token spend is real money saved for them. The rejection is of *this mechanism*, not of the goal. Any future work here must measure the sandbox's own traffic profile rather than extrapolating from operator transcripts. |
| 3 | **`headroom learn` is never run against this repo**, in any pilot. | Trips the 46,000 B ratchet; bypasses the tier gate, immutable rule IDs, and the WORM ack manifest. |
| 4 | **The real gap is measurement, not compression.** | The CFO's P0 from the 2026-04-13 brainstorm ("instrument token usage") was never done; `api-spend-ledger.jsonl` is empty. We were about to evaluate a fix without a baseline. |
| 5 | Re-evaluation trigger recorded (see below). | Keeps the door open on evidence, not vibes. |
| 6 | Serena MCP is separable and may be considered on its own merits. | Semantic code navigation, project scope, no proxy, no base-URL override, no auth-path insertion. Not evaluated here. |

## Re-evaluation criteria (ALL must hold)

1. Soleur has metered per-token spend that is material — i.e. `api-spend-ledger.jsonl` is
   non-empty and monthly spend exceeds a threshold worth optimising; **and**
2. a measured offline run over archived `tool_result` payloads ≥2 kB shows **>15% reduction**
   **and zero divergence** across `extract-block.cjs` plus the four grep-based gates in §3; **and**
3. compression can be confined to tool output that no gate greps, or the gates are made
   compression-safe first.

## Non-Goals

- Vendoring Headroom source into this repo.
- Any change to `AGENTS.md` / `AGENTS.rules.md` byte budget as part of this evaluation.
- Evaluating Serena MCP (separable; its own decision).

## Open Questions

- **The 2–3% figure is measured on operator transcripts and extrapolated to the sandbox.**
  Sandbox sessions may have a materially different profile (shorter, less cache-warm, more
  tool-output-heavy), and that is where BYOK dollars are actually spent. Nothing here
  measured it. Any future BYOK cost work must measure the sandbox directly rather than
  inheriting this number.
- Rate-limit exhaustion on Max 20x is the binding operator constraint, not dollars. At 2–3%
  reachable, compression is not the lever that relieves it — but the question of what *is*
  the lever remains open (agent-spawn gating from the 2026-04-13 brainstorm is the
  standing candidate).
- Token instrumentation is the prerequisite for every future token-cost decision, this one
  included. Already tracked by #1055, #6297, #5692 — no new issue filed.

## User-Brand Impact

- **Artifact:** the Soleur agent's tool-output path — the channel every workflow gate reads
  its evidence from — plus, in the rejected user-facing variant, the sandbox BYOK credential path.
- **Vector:** a lossy compressor between a gate and its evidence turns a *detected* violation
  into a *silent* one: a missed third-party-content grep ships a privacy breach with all gates
  reporting green. In the user-facing variant, a proxy in the BYOK path desyncs the spend cap
  from the real bill, so a founder is charged past a cap the product told them was enforced.
- **Threshold:** single-user incident.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering (CTO)

NO-GO. Measured ceiling 5.6% of conversation bytes, realistic 2–3%, against 98.17% cache-read
traffic and a frozen prefix that live-zone compression never touches. The disqualifier is
correctness: lossy tool-output rewriting manufactures false negatives in the grep-discharged
gates, and CCR retrieval relocates rather than mitigates the failure because retrieval is
model-initiated. Hard NO on `headroom learn`.

### Product (CPO)

Our usage: SCOPED at most (one machine, timeboxed, `unwrap` on exit), gated on instrumenting a
baseline first. End users: NO-GO across all three shapes (silent use / docs recommendation /
bundling) — wrong surface entirely, since users run server-side with no local agent, and
bundling carries single-user-incident blast radius via user-scope `~/.claude.json` mutation.
Cheaper answer already decided and unexecuted: token instrumentation and context-aware agent
gating, both zero-dependency.

### Legal (CLO)

Not the blocker. Anthropic ToS permits it in both auth modes — `ANTHROPIC_BASE_URL` with a
preserved claude.ai login is a documented configuration, not a tolerated hack. No Art. 28
sub-processor relationship arises for local software under the user's own credential; no
Article 30 register change. Apache-2.0 obligations trigger on distribution, not use — depend,
do not vendor. PROHIBITED for bundling/auto-install pending vendor review, and for any use
against customer content under a Jikigai credential. Beacon defaults on; disclosure would be
required if ever bundled.

## Session Errors

None. The prior-art sweep, the premise probes, and the independent re-derivation of the
subagent's cache-read figure (98.17% vs. the reported 98.2%) all held.
