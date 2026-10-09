# Decision challenges: argv-bearer sweep S2 (headless plan run, 2026-10-08)

Taste and user-challenge items from the plan-review panel and the domain leaders. Each states the
default the plan took and the alternative the operator may choose. None blocks the work phase.

## 1. cutover-inngest.sh: two HMAC sites held back (user-challenge)

- Brief: convert the cutover script; the S2 scope text implies no production apply on merge.
- Finding (two review seats, re-read): the infra suite counts `python3` in the read-only probe arms and requires exactly 2 tool calls, so converting the `registry-probe` and `doublefire-probe` HMAC sites reddens it. Fixing the census needs a one-line edit under `apps/web-platform/infra/**`, which fires the production apply on merge.
- Default taken: convert 17 of 19, hold back 2 with a comment, track the suite edit with S4/S5 (operator notice there).
- Alternative: edit the two census regexes now and accept the declared production apply (five consecutive push applies, two of them test-only edits, succeeded on 2026-10-07/08). Choose this if leaving the same secret on `openssl`'s argv at two manually dispatched read-only ops is judged not acceptable.

## 2. Plugin signing key: bash plus openssl over stdin, not python3 or node (taste)

- Brief: python3 reading the key from the environment.
- Finding: python3 is absent from the runner image and `x-community.sh` runs hosted. CTO and one reviewer prefer `node -e` (node is in the image).
- Default taken: pure bash HMAC over `openssl dgst -sha1 -binary` on stdin, oracle-tested against `openssl dgst -hmac`; no new runtime dependency for installed users.
- Alternative: `node -e` with `crypto.createHmac`, key from `process.env`; reversible behind the one function.

## 3. One PR for S2 versus a planned S2a/S2b split (taste)

- Brief: one slice per PR.
- Finding: 30 edited and 14 created files, above all three split thresholds. A reviewer asked to plan the split (plugin commit as S2b) instead of keeping it as a fallback.
- Default taken: single PR, nine commits by blast radius, with the S2b seam pre-agreed if CI shows two red cycles from the plugin rows.

## 4. Sweeper env hop: convert, not document (taste)

- Review suggested documenting the microsecond window (cheaper). Default taken: convert with the python3 `-I` launcher because that one process concentrates every forwarded secret; Phase 5 exit criterion falls back to documenting if the existing T8/G3 rows cannot hold.

## 5. write-env scope (mechanical, applied)

- `linkedin-setup.sh` validation cut from S2 (tracked in Phase 10); `x-setup.sh` kept as `inferred`.

## 6. Exit code 1 versus 2 per surface (applied, deviates from the brief)

- Refusals exit 2 in the Better Stack reader, the parity script and three of the four converted follow-through probes (the soak probe exits 3 through its existing `cannot_establish`, since 2 is a reading for it) because exit 1 means FAIL (probes) or "blame DOPPLER_TOKEN" (reader classifier).

## 7. Follow-up issues consolidated from five to three (mechanical, applied at work time)

- The plan listed five filings. Under the net-issue-flow gate (this PR closes one issue) the related infra-path and small items were consolidated: #9755 (`op=backup` environment gate and O10 re-plumb), #9756 (the two cla-evidence R2 `--user` sites), #9757 (held-back cutover HMAC sites with the census-regex suite edit, heartbeat-URL path secrets, `linkedin-setup.sh` write-env validation, Better Stack reader stderr discarded by two S3 workflows). Each item keeps its own checkbox, owner and trigger.
