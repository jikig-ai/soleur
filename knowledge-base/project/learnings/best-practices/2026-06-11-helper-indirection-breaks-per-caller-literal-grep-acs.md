# Learning: a consolidation PR's shared helper breaks per-caller literal-grep ACs

## Problem

PR #5186 did two things in one branch: (1) extract a shared `postAnthropicMessage`
transport helper into `_cron-shared.ts` that two crons route through, and (2)
migrate three call sites to structured outputs by adding an `output_config` field
to each Anthropic request body.

The plan's Phase-3 acceptance criterion AC7 was written as:

```
git grep -n "output_config" -- apps/web-platform/server/ | wc -l  ≥ 3
```

intending "each of the three request bodies contains output_config". At /work time
the grep returned **2**, not 3 — a literal-AC "failure" on a correct implementation.

## Root cause

Part 1 (the helper extraction) and Part 2 (the field addition) interact. Two of the
three call sites now pass the field through the helper using the helper's
**camelCase arg name** (`outputConfig`), and the helper is the single place that
serializes it to the snake_case request key (`output_config`). So the literal
`output_config` appears exactly twice in source: once in the helper definition,
once in the third (inline, non-helper) call site. The other two call sites
functionally send `output_config` — but via the arg, so a source-literal grep
across callers can't see it.

The AC author wrote the grep against the *pre-consolidation* mental model (three
inline fetch bodies, each with the literal), but Part 1 of the same PR collapses
two of those into the helper. The two parts are sequenced in the plan, so the AC
for Part 2 has to account for Part 1's centralization — and it didn't.

## Solution

- Don't gate a consolidation-then-migration PR on a per-caller source-literal grep
  for a field the helper centralizes. The literal count is `1 (helper) + N_inline`,
  not `N_total`.
- Assert the **functional contract at the helper boundary** instead: a helper unit
  test that passes `outputConfig` and asserts the serialized request body carries
  `output_config` (the passthrough). That one test covers every caller that routes
  through the helper, regardless of how many there are.
- For the inline (non-helper) site, the source-literal grep is still valid — keep it
  scoped to that file.

In #5186 the passthrough test already existed (`cron-shared.test.ts` →
`postAnthropicMessage` "passes output_config through to the request body"), so the
contract was verified; only the AC's grep count was wrong. The right reconciliation
was to note the AC-literal-vs-reality gap and trust the test, not to "make the grep
say 3" by un-consolidating.

## Key Insight

When one PR both (a) extracts a shared helper and (b) adds a request-shaping field,
any AC that counts that field's literal across callers will under-count by exactly
the number of callers routed through the helper. Centralization is the point of the
helper — so verify the field via the helper's passthrough test, and reserve
literal-greps for genuinely inline sites. Same family as "plan-quoted greps are
preconditions to verify" (`2026-05-18-sweep-class-fixes-grep-enumerated-not-intuited`),
but the mechanism is different: here the literal legitimately *moves*, it isn't
stale.

Adjacent papercut from the same migration: an AC8b-style "prompt no longer says
'JSON array'" grep can false-positive on a **fallback log/message string** (e.g.
`reportSilentFallback(..., message: "Anthropic response is not a JSON array")`),
not a prompt. Scope such greps to the prompt-construction lines, or update the
incidental message string too (the cheaper fix — the message was also now
inaccurate since the parse switched to `parsed.clusters`).

## Session Errors

1. **`gh issue create` for the tracking issue (#5186) was blocked once for a missing
   `--milestone`.** Recovery: re-ran with `--milestone "Post-MVP / Later"`.
   Prevention: already hook-enforced by `guardrails:require-milestone` — the gate
   worked as designed; this was an operator omission, not a workflow gap. No change
   warranted.

## Tags
category: best-practices
module: plan-authoring, review-acceptance-criteria
