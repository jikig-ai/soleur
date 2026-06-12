# Learning: WebFetch prose summaries fabricate "memorable" verbatim quotes — confirm quotations against the primary source

## Problem

While drafting the loop-engineering blog (#5088), Phase 0 used `WebFetch` to extract verbatim quotes
from Addy Osmani's essay. The fetch returned Osmani's closing line as **"Build the loop. Stay the
engineer."** — a punchy seven-word quote. It was authored into the post inside quotation marks,
bold, attributed to Osmani as his verbatim closing line.

The blocking `fact-checker` gate (which independently re-fetched the primary source) caught it:
Osmani's actual closing is **"Build the loop. But build it like someone who intends to stay the
engineer, not just the person who presses go."** The seven-word version does not appear in the essay
— the WebFetch summarization model had **compressed** the real sentence into a catchier line and
presented it as verbatim. At single-user-incident brand threshold, publishing a fabricated quote
attributed to a named Google director would have been a brand incident.

## Solution

Applied the fact-checker's remediation: replaced the fabricated quote with the true verbatim line
where it was framed as a quotation, and downgraded a second occurrence to a clearly-marked paraphrase
(no quote marks, "Osmani's instinct" not "Osmani's closing line"). The Soleur-authored H2 riff
("Build the loop. Run the company.") was left as-is — it is the company's own framing, not attributed
to Osmani.

## Key Insight

`WebFetch` answers a prompt against fetched content using a **small fast summarization model**. That
model paraphrases and compresses by design — it is NOT a verbatim transcription tool. A WebFetch
result that *looks* like a verbatim quote (even one returned under an explicit "return exact verbatim
text" prompt) can be a fabricated compression of the real sentence. Two rules follow:

1. **Phase-0 "source verification" via a summarizing fetch is necessary but NOT sufficient sourcing
   for quotation.** It confirms a quote *roughly* exists; it does not confirm the exact words.
2. **The blocking fact-check gate against the primary source is the load-bearing check** for any
   named-person quotation — and it must independently re-fetch, not trust the drafting fetch. Here it
   earned its keep: it was the only thing between a fabricated quote and a published brand surface.

Generalizes: treat any verbatim claim sourced from an LLM-summarized fetch (quotes, statute text,
pricing strings, API response shapes) as a hypothesis the primary source must confirm before publish.

## Tags
category: workflow-patterns
module: content-writer, fact-checker
issue: 5088
