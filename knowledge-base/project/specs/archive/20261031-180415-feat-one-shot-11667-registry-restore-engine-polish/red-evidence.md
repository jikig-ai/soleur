# RED evidence (unchanged implementation, new assertions only)

- Wiring suite: `89 passed, 2 failed`. Both new controls failed with `got: <nothing>`:
  `eng-hdr-row1-removed` and `eng-emit-sites1-removed` (the `grep -vx 1` filters hide code 1 on both sides).
- Engine suite: `98 passed, 1 failed`. The new assertion for the phrase `stay in the sink` failed against the old message.

Accepted residue (cited by string, not line): workflow arm 3 text "The store is EMPTY" lives in
`.github/workflows/apply-web-platform-infra.yml`, which this change does not edit.
