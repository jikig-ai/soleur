# Decision challenges: feat-one-shot-8036-1d-retire-boot-ghcr

## DC1 (User-Challenge, operator direction kept): the soak is enrolled on the epic #6122

- **Operator direction (#6122 comment 5811202876):** "The script's START and the enrolment
  directive land in the item 1d PR." The directive goes on #6122, the migration epic.
- **Challenge:** the follow-through sweeper closes the tracker on exit 0, so a soak PASS closes the
  epic while 5.3b-iii, 5.4 and 5.6 are still open. The soak's positive evidence can also be forged
  with the public Sentry DSN (`zot-soak-6122.sh` says so in its PASS line), and the sweeper cannot
  run the Better Stack corroboration itself.
- **Mitigation applied, direction unchanged:** the remaining steps are tracked separately in #8714,
  whose 5.6 line requires Better Stack corroboration before the ADR flips, and #6129 carries the
  same requirement (comment posted 2026-09-24). A premature close of #6122 therefore orphans no
  work.
- **Operator option:** move the directive to a dedicated soak tracker if the epic should stay open
  until 5.6.

## DC2 (Mechanical, auto-decided): soak START anchor fails FAIL, not TRANSIENT, on a late START

The plan (deepen item 5) said TRANSIENT. The implementation exits FAIL (`start-after-anchor`) when
the default START is later than #8660's `mergedAt`, and TRANSIENT only when `mergedAt` cannot be
read. A wrong START is a defect to fix, not a condition that clears on retry; TRANSIENT would retry
it daily forever. Security review confirmed this is stricter, not weaker.
