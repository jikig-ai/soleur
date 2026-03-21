# Learning: Blog citation verification before publish

## Problem

The first published blog article ("What Is Company-as-a-Service?") contained 6 factual inaccuracies that passed review:

1. Wrong citation URL (Lovable link pointed to a Cursor CNBC article)
2. Unverifiable statistic ("9,000 Claude Code plugins" -- source didn't support the claim)
3. Wrong number ("six domains" for Anthropic Cowork -- actual count was 10+)
4. Misattributed quote (Sam Altman quote sourced from felloai.com which didn't contain it)
5. Duplicate paragraph (WhatsApp section appeared twice)
6. Wrong factual claim (Instagram "billion users" at acquisition -- actual was 30M users, $1B acquisition price)

All errors were LLM-generated content published without source verification.

## Solution

Applied a "no naked numbers" audit: every statistic, quote, and factual claim was verified against its cited source URL. Unverifiable claims were either corrected with a verified source or softened (e.g., "9,000" became "Thousands"). Misattributed quotes were traced to the actual source. Duplicate paragraphs were consolidated.

## Key Insight

LLMs confabulate fluently -- citations look plausible but may link to wrong articles, invent statistics, or splice quotes from different sources. Every factual claim in published content must be verified against the cited URL before the article leaves draft status. A "no naked numbers" rule (every quantitative claim needs a linked, retrievable source) catches most issues. This verification step is non-negotiable for published content and should be part of the content-writer skill's workflow.

## Tags

category: content-accuracy
module: marketing
