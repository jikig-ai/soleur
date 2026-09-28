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

## DC-4 (taste): amend ADR-157 instead of writing a new ADR-256

- **The disagreement:** the CTO asked for a new ADR. DHH and the simplicity reviewer said an
  addendum to ADR-157 ("a hook that cannot parse its input asks") covers the fail-direction rule,
  and that the parity contract belongs in the header of `filing-shape.pl`.
- **Decision taken:** amend ADR-157 with a dated addendum that records:
  - the fail direction;
  - lex-not-grep;
  - corpus-bound parity;
  - the build-vs-buy alternatives (`shfmt`, `tree-sitter-bash`, `bashlex`, `bash -n`,
    `Text::ParseWords`).
- **What would change it:** an architecture reviewer ruling that the parity contract needs its own
  record.
