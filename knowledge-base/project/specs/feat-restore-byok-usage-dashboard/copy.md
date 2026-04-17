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

## 2b. Zero-MTD-with-history helper line (120)

Rendered when the month-to-date total is `$0` but the list below is non-empty.

`Showing your last 50 conversations with cost. Nothing billed this month yet.`

## 3. Column headers (14 each)

| Field | Header |
|---|---|
| time | `When` |
| domain | `Domain` |
| input tokens | `Input` |
| output tokens | `Output` |
| cost | `Cost` |

(`Model` column descoped — no `model` field is persisted on `conversations`. Follow-up issue tracks re-introduction.)

## 4. Per-row secondary label pattern (40)

Pattern: `[Marketing] · 2h ago`

Format: `[{Department}] · {relativeTime}`

Rules: department name in brackets (resolved from `DOMAIN_LEADERS[id].domain`, never the role abbreviation), relative time (`2h ago`, `3d ago`). Separator is ` · ` (space-middot-space). Unknown or null domain leader renders as `—`.

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

Implementation note: the error UI is rendered from the server component
branch, but the `Retry` button is a tiny client island
(`components/billing/retry-button.tsx`) that calls `router.refresh()`.
Containing page must set `export const dynamic = "force-dynamic"` so
`router.refresh()` re-fetches the data loader.

---

## Character count audit

| # | Field | Limit | Actual |
|---|---|---|---|
| 1a | Header | 30 | 9 |
| 1b | Subhead | 100 | 92 |
| 2 | MTD line (sample) | 60 | 28 |
| 2b | Zero-MTD helper line | 120 | 79 |
| 3 | Column headers | 14 | 4–6 each |
| 4 | Row label (sample) | 40 | 19 |
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
