# Learning: Verify ADR citation *numbers* before threading them into subagent prompts

## Problem

During the gstack-capability-adoption brainstorm, an "Anthropic-only = ADR-083"
citation carried over from an earlier synthesis into the brainstorm framing. It
was wrong on two counts:

- **ADR-083** is `ADR-083-scoped-strong-model-consult-at-decision-gates.md` — the
  scoped `fable`→`opus` consult at `plan` Step 4.5 / `ship` Phase 5.5.
- The all-Claude **model-selection policy** (the real "Anthropic-only" governance)
  is **ADR-053**, documented in `plugins/soleur/AGENTS.md` §Model Selection Policy.

The wrong number was threaded into BOTH domain-leader prompts (CTO and CLO). Both
leaders dutifully repeated "violates ADR-083 / Anthropic-only" in their
assessments — internally-coherent recommendations premised on a wrong governance
citation. The error was caught only by a premise-validation grep at capture time.

A confounding tooling quirk: an initial
`git ls-files 'knowledge-base/.../decisions/*.md' | grep ADR-083` returned empty
(glob/path resolution from the bare-repo cwd), briefly suggesting the ADR did not
exist at all — when it did.

## Solution

Before letting any ADR reference bound the option space or enter a subagent
prompt, verify the number against the corpus:

1. `git grep -l "ADR-0NN" main -- 'knowledge-base/**/decisions/*.md'` **and** read
   the citing text (e.g. `plugins/soleur/AGENTS.md`) to confirm the number maps to
   the mechanism you think it does — do not trust a number carried from prior prose.
2. If a filename grep comes back empty, cross-check with `git grep "ADR-0NN" main`
   over the whole tree before concluding the ADR is absent — a `git ls-files`/glob
   miss is not proof of non-existence.

Correcting it mid-brainstorm actually *improved* the design: ADR-083's existing
scoped consult is the mechanism the "two-Claude-persona User-Challenge" substitute
should extend, rather than a net-new build.

## Key Insight

A fabricated or misremembered ADR *number* produces internally-coherent
subagent output premised on a wrong governance floor — the leaders can't catch it
because they inherit the citation as a given. This is the citation-integrity
sibling of the existing brainstorm premise-validation rule about grepping the ADR
corpus for the proposed *mechanism*: verify the *number → mechanism* mapping, not
just that "an ADR about X exists."

## Session Errors

- **ADR-083 mis-citation threaded into CTO + CLO prompts.** Recovery: premise grep
  at capture located `ADR-083-scoped-strong-model-consult...` and ADR-053 as the
  real model policy. Prevention: verify ADR number→mechanism against the corpus
  (grep the decisions/ dir + read the citing text) before threading into any
  subagent prompt or letting it bound options.
- **`git ls-files '…/decisions/*.md'` empty-result glob quirk** briefly implied
  ADR-083 was absent. One-off. Prevention: cross-check with a tree-wide
  `git grep "ADR-0NN" main` before concluding non-existence.

## Tags
category: workflow-patterns
module: brainstorm
