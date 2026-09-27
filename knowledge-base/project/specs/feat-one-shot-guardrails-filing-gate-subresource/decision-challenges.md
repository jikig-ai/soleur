# Decision Challenges: feat-one-shot-guardrails-filing-gate-subresource

## DC-1 (taste / scope): split the escape closures into their own PR

- **Raised by:** DHH plan review (P1).
- **Challenge:** The reported bug turns a deny into an allow (sub-resource POSTs denied). The plan
  also closes collection-endpoint escapes that exist on `main`, which turns allows into denies:
  quoted and partially quoted paths, `-XPOST`, `--method=POST`, `--input`, `-F`/`--raw-field`/attached
  `title=`, and quoted multi-word `title=`. The review argued this PR should do the narrowing only,
  and that the closures should go to #9089.
- **Default kept:** the escapes stay closed in this PR. The brief said the narrowing must not leave
  a bypass for real issue creation, and it named the quoted path `"repos/o/r/issues"` explicitly. The
  closures are also small: one transform plus the extra spellings, and the redesign removed the
  false positive that motivated the P1.
- **What would change it:** an operator decision to keep this PR strictly deny → allow.

## DC-2 (taste): the list-then-label over-fire stays out of scope

- **Raised by:** Kieran plan review (P2).
- **Challenge:** `for n in $(gh api "repos/R/issues?labels=x" --jq …); do gh api -X POST repos/R/issues/$n/labels …; done`
  is denied before and after this change. This is the same symptom the brief reported, adding labels
  to existing issues, when it is done in a loop.
- **Default kept:** deferred to #9089. Per-segment scoping over a string opens a split-the-flags
  escape. The recommended fix is a `shellwords` tokenizer.
- **What would change it:** operators hitting this loop shape often enough to warrant promoting
  #9089 now.
