# Decision Challenges: feat-one-shot-guardrails-filing-gate-subresource

## DC-1 (user-challenge / scope): the quoted-endpoint escape is NOT closed by this PR

- **The brief said:** make sure the narrowing does not open a bypass for real issue creation, and it
  named `"repos/o/r/issues"` (quoted) as an example.
- **What was measured:** the quoted form (and partial quoting, and a quoted multi-word `title=`)
  **already bypasses the gate on `main`**. `$SCAN` blanks every quoted span. The narrowing does not
  open it.
- **What was tried:** two string-level designs that closed it. Both were measured to add
  regressions:
  - v1: a nested-quote false positive, found by DHH and Kieran.
  - v2: six regressions where main denies a create and v2 allows it, plus new false positives on
    routine list-then-comment commands, all found by the security review.
- **Decision taken (headless):** close the class properly on #9089 with a shell tokenizer rather
  than ship a third regex attempt. The DHH plan review recommended this split independently.
- **What would change it:** an operator decision that the quoted form must be closed in this PR,
  accepting a tokenizer-sized change (`Text::ParseWords::shellwords`, per-token matching as in
  `filingShape()`).

## DC-2 (resolved): the list-then-label loop

- Raised by Kieran and the security review. v3's per-segment matching fixes the unquoted form, and
  the quoted form (`gh api "repos/R/issues?…"` beside a labels POST) is allowed as on main. Rows pin
  both. No operator action needed.
