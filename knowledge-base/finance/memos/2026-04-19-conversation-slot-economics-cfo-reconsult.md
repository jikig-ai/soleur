---
title: Conversation-Slot Economics (CFO Re-Consult Post Amendment A)
date: 2026-04-19
author: cfo
feature: feat-plan-concurrency-enforcement
amends: "#2626"
---

# Conversation-Slot Economics

Amendment A re-defines a slot as one active conversation, with fan-out to ≤8
specialists inside it. This changes the cost profile per slot; the memo below
answers the five questions in the re-consult prompt.

## 1. Variable cost re-model

Under task-slot framing, peak cost-per-slot ≈ 1× agent token burn. Under
conversation-slot framing, peak cost-per-slot can burst up to **8×** when a
user types `@all`. Empirically, `@all` is a minority of conversations —
assume a blended multiplier of ~2.5× (most conversations fan out to 1–3
specialists; `@all` is ~15% of workstreams based on early qualitative data).

| Tier       | Price  | Slots | $/slot  | Peak burst $/slot (8×) | Blended $/slot (2.5×) |
|------------|--------|-------|---------|------------------------|-----------------------|
| Free       | $0     | 1     | $0      | $0                     | $0                    |
| Solo       | $49    | 2     | $24.50  | subsidized by margin   | $24.50 gross          |
| Startup    | $149   | 5     | $29.80  | risk concentrated here | $29.80 gross          |
| Scale      | $499   | 50    | $9.98   | dilutes across 50      | $9.98 gross           |
| Enterprise | custom | 50+   | custom  | custom                 | custom                |

Key shift: Free/Solo/Startup now carry **per-slot burst exposure 8× higher**
than the task-slot model priced for. Scale/Enterprise are protected by
portfolio averaging across 50 slots — the blended multiplier flattens.

## 2. Solo → Startup per-slot inversion

Under task-slots the inversion ($24.50 < $29.80) was a papercut. Under
conversation-slots it **widens risk** rather than dissolving it: Startup users
are both paying more per slot *and* the most likely demographic to use `@all`
repeatedly (growing team, exploring the product's differentiator). Startup is
the **most exposed tier** on blended CoGS.

**Recommendation: defer to post-ship telemetry (do not adjust in this PR).**
Reasons: (a) the 8× multiplier is a ceiling, not a mean — we have no
production `@all` frequency data; (b) changing pricing in the same release as
enforcement conflates two signals in churn analysis; (c) FR9 telemetry
(`concurrency_cap_hit` + `active_conversation_count`) will let us re-benchmark
in 4–6 weeks with real data. Revisit ladder in #2626 once we have ≥500
cap-hit events.

## 3. Additional telemetry fields needed for #2626

Spec FR9 fields (`tier`, `active_conversation_count`, `effective_cap`,
`action`, `path`) are necessary but insufficient for cost re-benchmarking.
Finance additionally needs, emitted from the same event or a paired
`conversation_completed` event:

- `specialist_fan_out_count` — how many leaders actually dispatched (1–8).
  Primary lever distinguishing 1× vs 8× cost-per-slot.
- `conversation_duration_seconds` — slot-hold time; multiplies variable cost.
- `tokens_in_total` / `tokens_out_total` aggregated across the fan-out.
- `model_mix` — Opus vs Sonnet vs Haiku token split (10× price delta between Opus and Haiku dominates CoGS more than fan-out count).
- `conversation_id` (hashed) — to de-dupe cap-hit retries from the same workstream.

Without `model_mix` and `tokens_*`, fan-out count alone misleads — an 8-leader
Haiku dispatch is cheaper than a 1-leader Opus one.

## 4. Downgrade-grace leakage (24h)

Low concern. Conversation-slot framing actually **tightens** the leak vs
task-slot: a leaked conversation holds one slot, not N. Worst case on a
Startup→Solo downgrade with 5 live conversations: 24h × 5 slots × ~2.5×
blended = ~$10–15 of unbilled CoGS per downgrader. Bounded, de minimis.
Keep 24h; shorter windows punish legitimate long-running workstreams.

## 5. Enterprise `concurrency_override` raise-only via sales

No finance objection. Raise-only means no revenue erosion path. Requiring a
contract amendment for every raise would slow sales velocity on the highest-
ACV tier — unjustified friction when the slot ceiling (50) already bounds
blast radius and override is logged. Recommend: allow sales to raise up to
2× tier default (100) without amendment; anything above requires CFO sign-off
and paper amendment. Document in internal runbook.

## Recommendation to plan phase

Ship Amendment A pricing ladder as-is; add `specialist_fan_out_count`,
`conversation_duration_seconds`, `tokens_in_total`/`tokens_out_total`, and
`model_mix` to the telemetry schema so #2626 can re-benchmark in 4–6 weeks.
