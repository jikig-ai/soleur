# Decision challenges — feat-one-shot-8737-rotate-ghcr-minter-token

This is a headless plan run, 2026-09-25. It records where the plan departs from, or argues against,
the brief's stated direction. None of it was applied silently. `ship` Phase 6 renders this file into
the PR body and files an `action-required` issue.

## UC-1 — Retire the token instead of rotating it? (User-Challenge)

- **Stated direction (the issue and the brief):** rotate `doppler_service_token.ghcr_minter` with the
  rename + `create_before_destroy` shape, so that "the replacement token was created after #8705's
  merge apply".
- **Plan does:** exactly that. The stated direction is the default.
- **The challenge.** The token serves a feature that is off, and that cannot come back on in its
  current form:
  - `GHCR_MINTER_DISABLED=true` has been set in prd since 2026-07-05 (#6074).
  - ADR-088 is superseded: a GitHub App installation token cannot pull a private GHCR package.
  - The C4 model records the minter's `GHCR_READ_TOKEN` write as having no consumer since #8036 1d.

  Rotating it mints a fresh **read/write** `soleur/prd` credential and stores it in `soleur/prd`.
  There, every prd read credential can read it: the 13 token-drift read tokens, `github-ci-prd`, the
  web hosts' probe token, and the app container env on each web host's root disk. That keeps a
  read-to-write escalation alive for a credential nothing uses. Retiring the token and its secret
  (the token half of ADR-096 task 5.4, already tracked in **#8714**) removes that escalation
  entirely. It is also safe at runtime: the minter's kill-switch runs before the token is read, so a
  missing value is never reached.
- **Why the plan did not do it.** It contradicts the issue's closing criterion, which requires a
  replacement token, and it widens the scope into #8714's 5.4. It also needs care: the destroying
  apply must keep the two `-target=` lines, and a follow-up PR removes them.
- **The ask.** Prioritize #8714's 5.4 now rather than after the #6122 soak. Or, if the operator
  prefers, amend #8737's closing criterion to "neither slug is listed" and retire the token in this
  PR instead of rotating it.
- **Raised by:** the session model and the CTO domain review (2026-09-25). The CTO: "retiring would
  be the stronger security outcome … but it goes against the issue's close criterion and the
  operator's stated direction … record it as a decision challenge and ask for #8714 to be
  prioritised."
- **Default if nobody objects:** rotate, as planned. #8714 stays open for the retirement.
- **Plan review (2026-09-25).** DHH rated this P0: "change the issue, not the security outcome".
  The closing criterion's "replacement" wording comes from the same stale premise as "minting goes
  dark". Plan-review routing classifies a cut of operator-requested scope as a User-Challenge, not
  Mechanical, so the plan still rotates. If the operator accepts UC-1, the retire variant is:
  - delete both resource blocks;
  - keep the two `-target=` lines for that one merge, and remove them in a follow-up;
  - merge with `[ack-destroy]`;
  - the main verifier run then reads `MISSING` for `61c939b5`, which is the success state;
  - amend #8737's closing criterion to "neither slug is listed".
