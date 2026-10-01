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

## Workflow Cost Breakdown — UI Copy

Added by `feat-per-workflow-agent-cost-observability` (#1055). Renders **between** the
month-to-date summary line (§2) and the conversation list (§3/§4) inside the same
`API Usage` section. Same voice contract as above: bold, precise, no hedging.
Forbidden: `estimated, approximate, around, roughly, ~`. Additionally forbidden here:
any phrasing that invites the reader to hand-add the displayed rows (plan §Phase 4 /
Risk R1 — `formatUsd` rounds each row, so displayed rows need not visibly sum to the
displayed headline even when the NUMERIC partition is exact).

---

## 11. Breakdown block header + subhead

- **Header (20):** `Where it went`
- **Subhead (110):** `Your spend this month, split by the workflow each conversation started in. Nothing is left out.`

Notes:

- `Where it went` is preferred over `By workflow`. The section already sits under
  `API Usage`; a second noun-label header adds a taxonomy word and no meaning, while
  `Where it went` is the founder's actual question. Conservative fallback if review
  wants strict parallelism with `API Usage`: `Workflow breakdown` (18).
- The subhead carries the attribution mechanism (`started in`) so the rule is stated
  once before any number is read, not only in the note below the rows.
- `Nothing is left out` is the completeness claim. It deliberately does **not** say
  "the parts add up to the total" — that wording would invite hand-addition of
  rounded rows and break under `formatUsd` (plan Risk R1).

## 12. Bucket labels (28 each)

The label map is the only source of displayed names. Raw slugs never reach the DOM
(plan AC: `output contains none of drain-labeled-backlog, __unrouted__, __legacy__`).

| Wire value | Label | Len |
|---|---|---|
| `one-shot` | `Idea to shipped` | 15 |
| `brainstorm` | `Exploring an idea` | 17 |
| `plan` | `Planning the work` | 17 |
| `work` | `Doing the work` | 14 |
| `review` | `Reviewing the code` | 18 |
| `drain-labeled-backlog` | `Clearing the backlog` | 20 |
| `__unrouted__` | `No workflow started` | 19 |
| `__legacy__` | `Before workflow tracking` | 24 |

Rationale (replaces the strawman `Explore an idea / Plan the work / Do the work /
Review the code / Ship a change / Clear the backlog`):

1. **Gerunds, not imperatives.** A cost-table row label is a category, not an
   instruction. `$4.27 · Plan the work` reads as a command to the reader; `$4.27 ·
   Planning the work` reads as a line item. Five of the six are gerunds and parallel
   each other exactly.
2. **`one-shot` is not `Ship a change`.** `one-shot` is the whole plan → work →
   review → ship pipeline in one dispatch, so it will usually be the *largest* bucket.
   Labelling the biggest number with the smallest-sounding verb phrase actively
   misinforms. `Idea to shipped` names the full span, and reuses established Soleur
   brand language (brand guide § Example Phrases: "Every department. From idea to
   shipped."). Its deliberate break from the gerund pattern is the signal that this
   bucket is not a peer stage but the composite.
3. **`No workflow started`** beats `Unrouted` / `Not in a workflow`: it states what
   happened in plain past tense rather than naming a system state, and it does not
   read as an error the founder needs to fix.
4. **`Before workflow tracking`** is self-explaining — it tells the reader *why* the
   spend is unattributed in the label itself, so no per-bucket footnote is needed.
5. `Reviewing the code` keeps the word "code". That is not jargon for a founder
   shipping software, and dropping it leaves `Reviewing` ambiguous against
   `Clearing the backlog`.

## 13. Breakdown row (label + amount + secondary line)

- **Primary:** `{Label}` (§12) + `{formatUsd(totalUsd)}`, amount right-aligned,
  `tabular-nums`, matching the conversation rows above.
- **Secondary (44):** `{n} conversations · {formatUsd(avgUsd)} each`
  - Sample: `12 conversations · $0.36 each` (29)
  - `n === 1` → suppress the average entirely: `1 conversation`. The average of one
    conversation is the total restated, and `· $0.36 each` next to `$0.36` reads as a
    rendering bug.
- Rows ordered by spend descending (plan §Phase 4).

## 14. Attribution note (200) — load-bearing

`Every conversation counts under the first workflow it started. One that began in Planning the work and carried on into Doing the work counts entirely under Planning the work.` (174)

Placement: directly beneath the last breakdown row, `text-xs text-soleur-text-muted`,
same treatment as the existing zero-MTD helper line (§2b).

Why this wording and not the alternatives:

- **`Grouped by the workflow each conversation is in now…` is factually wrong.**
  The lock is first-writer-wins: `soleur-go-runner.ts:2162` gates on
  `state.currentWorkflow === null`, and `ws-handler.ts:1084` names the same rule
  ("first-writer-wins") on the concurrent-tab path. Nothing re-attributes a
  conversation to a later workflow. Copy asserting "is in now" would describe a
  mechanism the code does not implement.
- **No hedge.** The sentence states a rule, not an uncertainty. There is no
  `estimated`, no `approximate`, no `~`. The number is exact; the *partition rule* is
  what the reader needs disclosed.
- **The worked example is the disclosure.** "First workflow it started" alone reads
  as a harmless implementation detail; the `plan → work` example is the moment the
  reader understands that `Planning the work` can carry build spend. Naming two
  labels from §12 keeps it concrete without introducing the word "attribution".
- **Totals are not re-litigated here.** Exactness lives in §11's `Nothing is left out`
  and §15's footnote. Repeating it in the limitation note would read defensive.

> **Plan follow-up (not copy):** plan Risk R2 currently reads "attributes **all** its
> accumulated spend to the workflow it is **currently on**". That is the same error as
> the CFO draft and contradicts the code cited in its own mitigation. R2 and the ADR
> text should be corrected to first-writer-wins before Phase 3.

## 15. Footnote — revision of §8 (scoping the cross-check promise)

The Anthropic Console has no workflow dimension, so the breakdown is the one figure on
this surface a user cannot verify upstream. The `match to the cent` promise is the
BYOK positioning and must stay intact for the headline and the conversation rows while
visibly not extending to the breakdown. Minimal edit — one word swapped, one sentence
appended:

**Was (§8, and drifted further in the live component):**

`Figures come straight from the Anthropic SDK response. Cross-check any row in your Anthropic Console under Usage — the numbers will match to the cent.`

**Now (sentences 1 + 2 unchanged except `row` → `conversation`; sentence 3 new):**

`Figures come straight from the Anthropic SDK response. Cross-check any conversation in your Anthropic Console under Usage — the numbers will match to the cent. The Console has no workflow dimension, so it can confirm each conversation, not the split. Its monthly total will also differ: this page groups a conversation into the month it STARTED, while the Console groups spend by the day it was incurred.` (390)

> **Corrected at review, 2026-09-08 (#1055).** The sentence above previously read
> "...so it can confirm **the total and** each conversation, not the split." That was
> false in a way that pointed the user at the wrong culprit. Both RPCs filter
> `created_at >= since`, so this page's month contains conversations that *started*
> in it; the Anthropic Console groups spend by the day it was *incurred*. A
> conversation opened 2026-08-28 that burns $50 on 2026-09-05 is absent from this
> page's September total and present in the Console's — ordinary use on a product
> where one `one-shot` conversation spans days. The old copy invited the user to
> read that difference as Soleur under-reporting their spend.
>
> The per-conversation cross-check is unaffected, so the promise is narrowed rather
> than dropped, and the window semantics are now stated outright instead of being
> a silent premise. The window itself is NOT changed here: it is pre-existing
> (migration 027) and changing it would move a number users already see — tracked
> separately as #7929.

Diff is two words changed and one sentence added:

- `any row` → `any conversation`. `row` was already ambiguous once a second kind of
  row exists on the surface; `conversation` pins the promise to the population the
  Console can actually match.
- The new sentence is framed as **what the Console can confirm**, not as a disclaimer
  about what Soleur can't prove. It enumerates the promise's scope (`the total and
  each conversation`) and therefore reinforces it while excluding the split.
- `match to the cent` is untouched, in the same clause, in the same sentence position.

### 15b. §8 baseline drift (fix before shipping §15)

The live component's footnote is 273 chars against §8's 150 budget and carries an
unspecced third sentence:

`Conversations from before 2026-05-12 may under-reflect cache-read tokens; new conversations capture all three input tiers.`

Two problems, both pre-existing:

1. The spec was never re-baselined when this shipped. Budget for §8 is raised to
   **400** to cover the cache-read sentence plus §15's addition (full string: 375).
2. `may under-reflect` is a hedge construction on the one surface whose entire
   positioning is exactness, and the condition is deterministic — those conversations
   *do* under-report. Replace with: `Conversations from before 2026-05-12 under-report
   cache-read tokens; newer ones capture all three input tiers.`

## 16. Degenerate and empty states

### 16a. Exactly one bucket has spend — breakdown suppressed

**No copy. Render nothing.**

A one-row breakdown restates the headline, and a line explaining its absence would
appear on the most common early-user path — the founder who has run one workflow — as
if something were wrong. Silence is also what makes §16c legible: on this surface,
**absence means "only one workflow", and a line means "something failed"**. Adding
copy here collapses that distinction and forces §16c to carry the whole disambiguation
load in its own wording.

### 16b. All spend is in the `legacy` bucket (120)

`Every conversation with spend this month started before workflow tracking. New ones show up here, split by workflow.` (116)

Renders in place of the table (plan: "A single explanatory line, not an empty table").
Forward-looking rather than apologetic — the state resolves itself on the next
conversation, and the copy says so.

### 16c. Breakdown failed to load; headline and list are fine (120)

`Couldn't load the workflow split. Your total and the conversations below are unaffected — reload to try again.` (110)

- No error banner, no retry button — the section is not in an error state (plan
  §Phase 4: `mtdByWorkflow === null` → "Section renders as it does today"). Muted
  `text-xs` line only.
- `Couldn't` matches the existing error voice (§10a `Couldn't load your usage.`).
- The unaffected clause is the whole point: it stops a reader from doubting the
  headline they just read.
- Distinguishable from §16a by construction: §16a renders nothing.

## 17. Tooltip — "What is a workflow?" (180)

- **Label (24):** `What is a workflow?`
- **Body (180):** `A workflow is one of the routes Soleur runs your work down: exploring an idea, planning it, building it, reviewing it, or all of it in one go. Each conversation takes exactly one.` (179)

**Placement: on the breakdown block header (§11), not the section header.**

A fourth trigger in the section header is one too many. The header's existing three
(`What is a token?`, `Why does cost vary?`, `What about cache tokens?`) are one family
— they all explain *how Anthropic prices a call*. "What is a workflow?" explains a
Soleur concept, and stacking it into that column both breaks the family and turns a
right-aligned help column into a wall. Attaching it to the block it explains keeps the
section header at three and puts the definition where the unfamiliar word first
appears.

The body's closing sentence (`Each conversation takes exactly one`) is doing work: it
is the premise §14's note depends on, and stating it here lets §14 stay one line.

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

### Workflow breakdown (#1055)

| # | Field | Limit | Actual |
|---|---|---|---|
| 11a | Breakdown header | 20 | 13 |
| 11b | Breakdown subhead | 110 | 95 |
| 12 | Bucket labels | 28 each | 14–24 |
| 13 | Row secondary line (sample) | 44 | 29 |
| 14 | Attribution note | 200 | 174 |
| 15 | Footnote, §8 revised (full) | 400 | 375 |
| 16b | Legacy-only line | 120 | 116 |
| 16c | Breakdown-load-failed line | 120 | 110 |
| 17a | Workflow tooltip label | 24 | 19 |
| 17b | Workflow tooltip body | 180 | 179 |

Note: row 8 of the table above is superseded by row 15 here — the live §8 string is
273 chars against a 150 budget (see §15b).
