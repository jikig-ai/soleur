---
title: A tool's "supports docs" is a claim about its EXTRACTOR, not its file-type list
date: 2026-08-03
category: integration-issues
tags: [tool-evaluation, retrieval, knowledge-base, premise-validation, supply-chain, token-efficiency]
issues: [4206, 5708]
---

# Learning: "Supports docs" is a claim about the extractor, not the file-type list

## Problem

Evaluating **Graphify** (Apache-2.0, 101k★) as the implementation for Soleur's open,
unbuilt `kb-search` Stage 3 (#4206). Its tagline advertises turning "any codebase, with
its docs, SQL schemas, configs, and PDFs" into a knowledge graph, and `detect.py` really
does classify `.md`/`.rst`/`.txt` as a first-class `DOCUMENT` type with its own
`DOC_EXTENSIONS` constant. Both the marketing copy and the code's own type layer said
"handles prose."

Accepting that would have routed a multi-day bakeoff — and a $2.68 / 50-minute benchmark
run — at a tool that cannot work on our corpus.

## Solution

**Read what the per-type extractor actually appends to `nodes`/`edges`.**

`graphify/extractors/markdown.py` is 194 lines. It emits:

- one file node,
- one node per `^#{1,6}` heading,
- `contains` edges for heading nesting,
- `references` edges for explicit links only,

and returns `input_tokens: 0` — deterministic precisely **because it never reads
paragraph text**.

Measured against the target corpus in one command each:

| Signal | Measured |
|---|---|
| Corpus composition | **~92% prose** (177,530 lines; 11,020 inside code blocks) |
| Cross-doc `.md` links | 354, across 152 of 2,085 files |
| Files with any extractor-capturable link (incl. wikilinks) | 502 of 2,085 (**24%**) |
| Top headings (anchored) | `## Problem` ×1,868, `## Solution` ×1,644, `## Session Errors` ×1,522 |

So the deterministic path indexes headings + filenames + explicit links — a **strict
subset** of what the existing grep arm already searches (full text) at R@5(heavy) 0.2966,
against a committed ≥0.40 gate. It cannot beat a superset of its own signal.

Then the second half of the answer, from the vendor's own `skill.md`:

> "Code is extracted structurally (AST) with no LLM and no key at all … **Semantic
> extraction (only for docs, papers, and images) uses Gemini only if
> `GEMINI_API_KEY`/`GOOGLE_API_KEY` is already set; otherwise the host agent itself is
> the LLM.**"

The properties that make the tool attractive — $0, deterministic, no vector store — hold
**for code only**. On a prose corpus the tool is an LLM-extraction pipeline whose bill
lands on the host agent's own tokens, and whose named third-party recipient is Google.

## Key Insight

**File-type acceptance and semantic extraction are two different claims.** A tool's
`SUPPORTED_EXTENSIONS` constant, its README, and its type-classification layer can all
affirm the first while the second is false. The only probe that settles it is reading the
per-type extractor's emit lines.

Three corollaries, each of which independently would have reached the verdict faster:

1. **Measure corpus composition before evaluating any code-intelligence tool against a
   knowledge base.** A prose-vs-code line ratio and a link-density count are one command
   each. A ~92%-prose corpus gives 28 AST extractors nothing to parse. Derive the ratio
   with a fence-**state machine**, not a fence count, and check the parts sum to the whole.
2. **A "zero LLM / deterministic / local" claim is usually scoped to one input class.**
   Find which class, and check whether it is *your* class. If the answer is the other
   one, the headline properties invert — a tool adopted for token efficiency can become a
   token cost.
3. **A prior artifact's "routed to X" destination is as perishable as its deferral
   labels.** The 2026-06-29 brainstorm rejected this axis and routed the need to "the
   existing pgvector Stage-3 track (#4119/#4176/#4043)". Two of those are closed, and the
   real Stage-3 issue (#4206) is an unbuilt ADR-trigger with no vector column in any
   migration. The need read as "already handled" while being unserved for ~2.5 months.
   Existing premise-probe rules cover cited *blockers* and *deferral triggers*; this is
   the mirror case — **verify the routed-to destination SHIPPED, not merely that it was
   filed.**

## Session Errors

1. **`extract.py` grep produced a false negative on the prose path.** Searching the 264 KB
   `extract.py` for a markdown extractor returned nothing, which read as "no prose support
   at all" — a claim that would have inverted the brand-axis finding (Graphify has *no*
   vector store, so it does not re-open the 2026-04-07 "no embeddings" objection; it fails
   on extraction depth). The extractor lives in `graphify/extractors/markdown.py`.
   **Prevention:** in a modular codebase, list the `extractors/`-style handler directory
   before concluding a per-type handler is absent from a monolithic dispatch file.

2. **An unverified inference briefly reached the brainstorm document.** A key decision
   asserted the prose path "runs through `llm.py`" — inferred from a subagent finding plus
   the file's existence. The subagent's supporting citation (`references/add-watch.md`)
   404'd, so the quote it carried was never confirmed. Re-probing `graphify/skill.md`
   directly produced the vendor's verbatim statement, which was materially stronger and
   more specific.
   **Prevention:** when a subagent's supporting citation fails to resolve, treat the claim
   it carried as unverified and re-probe from a path you listed yourself — do not let the
   conclusion survive on the subagent's authority.

3. **RETRACTED — I logged a subagent's count as an error when my own pattern was the
   narrower one.** This entry originally recorded a leader's "353 links across 153 files
   (7.3%)" as diverging from my "direct measurement" of 271/122. Review re-derivation
   showed my regex required a `./` or `../` prefix and silently dropped ~83 sibling links;
   the broader pattern gives **354 across 152 (7.29%)**, within one of the leader's figure.
   The subagent was right.
   **Prevention:** re-deriving a subagent's number is only half the check — when the two
   disagree, diff the **patterns** and ask which population each selects before deciding
   who is wrong. A stricter regex is not a more accurate one. This is the failure mode the
   "a subagent's COUNT is a claim to re-derive" habit does *not* cover: it guards against
   trusting the agent, not against trusting yourself.

4. **Three composition figures and all five heading counts shipped wrong; review caught
   them.** Total lines (~111,830 vs **177,530**), code-block lines (~1.1k vs **11,020**,
   ~10× off), and the derived "~98.5% prose" (vs **~92%**) were all wrong, and the heading
   frequencies were each a single whitespace variant read off a truncated
   `sort | uniq -c | head -8` — inverting the true rank order.
   **Prevention:** never take a total from a truncated `uniq -c` listing; count per key
   with an anchored, whitespace-tolerant pattern and sum explicitly.

5. **The sparsity argument ignored what the extractor actually ingests.** Wikilinks were
   tabled separately as if inert; `markdown.py` feeds them through the same `add_link`
   path, making true coverage 24% of files rather than 6%.
   **Prevention:** derive a "corpus too sparse for tool X" claim from X's own extractor
   regex list, not from the link syntax you happened to grep for.

4. **Three different Stage-2 R@5 number sets are in circulation** for one stage: the
   committed `learning-retrieval-metrics-2026-05-20.json` (identity 0.775 / light 0.636),
   the #4206 issue body (0.7528 / 0.5928), and a subagent's (0.802 / 0.675). The committed
   JSON was treated as authoritative.
   **Prevention:** re-baseline before the next Stage-3 evaluation — the bench baseline is
   on a 1,163-file corpus and the corpus is now 2,084. Recorded on #4206.

5. **The `graphifyy` PyPI naming trap was nearly missed.** The distribution name is
   `graphifyy` (double-y); `graphify` is a different package. It surfaced only from reading
   `pyproject.toml`'s `[project].name` directly.
   **Prevention:** for any Python tool adoption, read `[project].name` in `pyproject.toml`
   — the repo name is not the distribution name.

## Tags

category: integration-issues
module: knowledge-base-retrieval
