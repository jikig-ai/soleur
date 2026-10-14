# Learning: a handler-rendered committed file meets the repo's linters only at its own PR (#7122)

## Problem

#9596 moved the community digest from agent-written prose to a handler template. Its tests asserted the
template's content and alphabet, and nothing ran the repo's markdown linter over a rendered digest, so the
first real digest PR failed the required `markdown-lint` check (`MD034/no-bare-urls`, two bare URLs in the
footer) and could not merge. The old agent-written digests had used link syntax, which no test had ever
pinned because the agent produced it unprompted.

## Solution

The committed digest footer no longer contains a URL (an autolink would have widened the closed output
alphabet pinned by test G1-5; the issue body, which is not linted, keeps the links). The regression test
asserts the property (no scheme or `www.` host in the digest) and was mutation-checked. The real rendered
digest was linted with the repo's own config before and after (2 errors, then 0).

## Key Insight

Any file a handler or bot commits is subject to every required check on its PR, so a template that
produces such a file needs one assertion per linter that will read it, and the cheapest instrument is the
linter itself run once over a rendered sample. A closed-alphabet test certifies what can appear, never
that what appears is lint-clean.

## Session Errors

1. **The digest template shipped without being run through markdownlint.** Recovery: the failing digest PR's
   own CI log named the rule; fixed in a follow-up PR. **Prevention:** lint a rendered sample of every
   committed template output in the PR that introduces the template.
2. **An autolink fix was the first attempt and was refused by the alphabet test.** Recovery: dropped the URL
   instead of widening the alphabet. **Prevention:** none beyond the existing G1-5 test, which did its job.
3. **A tracker filing was blocked twice by the filing gate (body file location, then a missing user-visible
   consequence).** Recovery: wrote the body with the Write tool and used the machinery label for a CI
   flake. **Prevention:** none; the gate's messages were accurate.
