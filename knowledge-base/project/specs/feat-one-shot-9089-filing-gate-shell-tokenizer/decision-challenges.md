# Decision Challenges: feat-one-shot-9089-filing-gate-shell-tokenizer

## DC-1 (user-challenge / scope): one PR, not the two that the CTO and DHH recommended

- **The brief asked for** one run covering:
  - the hook's shell tokenizer;
  - the `filingShape()` cron gaps;
  - the `$(...)` and `bash -c` shapes.
- **The CTO (domain review) and DHH (plan review) both recommended** splitting into two PRs:
  - **PR1:** the corpus, the cron-mirror fixes, the deny-marker regex import and
    `filing-shape.pl --classify`. This closes the live cron bypass within hours. The bypass is the
    `-ftitle=`, `-X=POST`, `#fragment` and `--input=` spellings under the
    `gh api repos/jikig-ai/soleur/` allowlist.
  - **PR2:** the lexer and the `guardrails.sh` wiring.
- **Decision taken (headless):** keep one PR, because that is the scope the operator stated. The
  plan's Phase 1 lands the cron-mirror fix and its tests as the first commits, so ship can
  cherry-pick them into their own PR if the lexer half stalls in review.
- **What would change it:**
  - the operator asks for the cron fix to ship first; or
  - a lexer review round runs past one cycle.

## DC-2 (taste): an unquoted `echo gh issue create` is gated

- **What happens:** detection at any argv position treats an unquoted `echo gh issue create` as a
  filing. It does the same for `bash -c 'echo gh issue create'`, because the lexer recurses into
  the string. Quoted prose is not affected.
- **Decision taken:** accept this over-fire, for three reasons:
  - it errs toward gating;
  - the refusal names the fix (quote the text);
  - the same rule removes every launcher-table bypass.

  Rows D32 pin the behavior as intended.
- **What would change it:** incident telemetry showing this over-fire on real agent commands.

## DC-3 (taste): the endpoint is any matching token, not the first positional argument

- **Kieran's proposal:** match the endpoint only as the first positional argument after `gh api`,
  parsed with gh's flag table. That would stop a comment POST from counting as a filing when its
  body token ends in `repos/o/r/issues`.
- **Decision taken:** keep the current "any token matches" rule. It is what `filingShape()` already
  does, so the cron mirror keeps parity without a second flag table in JS. If a gh upgrade adds a
  value-taking flag, the rule over-gates instead of missing a filing. The over-fire is listed in
  Non-Goals.
- **What would change it:** a measured false deny from this shape in incident telemetry.

## DC-4 (taste): ADR-256 as a scoped exception, with a pointer from ADR-157

- **History:**
  - The CTO asked for a new ADR.
  - At plan review, DHH and the simplicity reviewer preferred an addendum to ADR-157, and
    revision 3 adopted that.
  - At deepen-plan, the architecture-strategist found two problems with the addendum:
    - ADR-157's decision says a hook "never denies", and its alternatives table rejects fail-closed.
      So the filing gate's deny-on-exit-2 and floor-only deny are an EXCEPTION to ADR-157, not an
      extension of it.
    - The parity contract between the hook and the cron mirror has nothing to do with parse
      failure.
- **Decision taken (revision 4):**
  - Write a new ADR-256 covering three things: lexing instead of blanked-text grepping, the
    corpus-bound predicate parity, and the scoped fail-direction exception.
  - Add a dated one-line pointer from ADR-157 to ADR-256.
- **What would change it:** an operator preference for fewer ADRs. The fallback is the revision-3
  addendum, with the wording corrected to "scoped exception".

## DC-5 (taste): keep a separate perl process for the lexer

- **The recommendation:** the performance-oracle recommended merging the `$SCAN` strip, `_api_pl`
  and the lexer into one perl process under one `alarm`. That would save a fork and put the strip's
  quadratic regex under the same time bound.
- **Decision taken:** keep them separate. `strip_command_bodies` is a shared lib function that 13
  hooks consume. Moving guardrails.sh's `$SCAN` computation into the lexer process changes a
  surface this plan scoped out. Instead:
  - `_api_pl` is made linear in this plan;
  - the quadratic strip gets its own issue at ship.
- **What would change it:** that issue landing a bounded strip, or measurements showing the extra
  fork matters.
