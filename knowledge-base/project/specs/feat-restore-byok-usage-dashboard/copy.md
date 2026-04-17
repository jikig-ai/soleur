# BYOK Usage Dashboard — UI Copy

Location: `/dashboard/settings/billing`, new "API Usage" section below the subscription block.

Voice: Bold, precise, no hedging. BYOK-first positioning — actual cost from the Anthropic SDK, no markup. Forbidden: estimated, approximate, around, roughly, ~.

---

## 1. Section header + subhead

- **Header (30):** `API Usage`
- **Subhead (100):** `Actual spend on your Anthropic key. No markup, no middle layer — you pay the API directly.`

## 2. Month-to-date summary line (60)

Pattern: `$4.27 in April · 38 conversations`

Format: `${total} in {Month} · {n} conversations`

## 3. Column headers (14 each)

| Field | Header |
|---|---|
| time | `When` |
| domain | `Domain` |
| model | `Model` |
| input tokens | `Input` |
| output tokens | `Output` |
| cost | `Cost` |

## 4. Per-row secondary label pattern (40)

Pattern: `[Marketing] · claude-sonnet-4-5 · 2h ago`

Format: `[{Domain}] · {model-id} · {relativeTime}`

Rules: domain in brackets, model ID verbatim from API, relative time (`2h ago`, `3d ago`). Separator is ` · ` (space-middot-space).

## 5. Empty state

- **Headline (40):** `No API calls yet this month.`
- **Body (140):** `Every conversation you run here bills straight to your Anthropic key. Start one and costs show up in this table the moment the response lands.`
- **Primary action (24):** `Start a conversation`

## 6. Tooltip — "What is a token?" (180)

`Tokens are the units Anthropic charges for. One token is about four characters of English. A short reply costs a few hundred; a long document with context can cost tens of thousands.`

## 7. Tooltip — "Why does cost vary per conversation?" (180)

`Cost scales with input and output tokens. Longer prompts, attached documents, and longer replies all push it up. Model choice matters too — Opus costs more per token than Sonnet or Haiku.`

## 8. Footnote / disclaimer (150)

`Figures come straight from the Anthropic SDK response. Cross-check any row in your Anthropic Console under Usage — the numbers will match to the cent.`

## 9. Loading state line (40)

`Loading usage from your key…`

## 10. Error state

- **Headline (40):** `Couldn't load your usage.`
- **Body (120):** `The dashboard couldn't reach the usage service. Your API key and billing are unaffected. Try again in a moment.`
- **Retry action (16):** `Retry`

---

## Character count audit

| # | Field | Limit | Actual |
|---|---|---|---|
| 1a | Header | 30 | 9 |
| 1b | Subhead | 100 | 92 |
| 2 | MTD line (sample) | 60 | 28 |
| 3 | Column headers | 14 | 4–6 each |
| 4 | Row label (sample) | 40 | 38 |
| 5a | Empty headline | 40 | 29 |
| 5b | Empty body | 140 | 138 |
| 5c | Empty CTA | 24 | 19 |
| 6 | Token tooltip | 180 | 178 |
| 7 | Cost tooltip | 180 | 178 |
| 8 | Footnote | 150 | 148 |
| 9 | Loading | 40 | 28 |
| 10a | Error headline | 40 | 24 |
| 10b | Error body | 120 | 118 |
| 10c | Retry | 16 | 5 |
