# Decision challenges: feat-one-shot-infra-privileged-doppler-description

Recorded headless at plan review (2026-09-24). The operator's stated direction is the default and was
kept in each case below. `ship` renders these into the PR body.

## DC-1: keep the by-name required-context count before merge (User-Challenge)

- **Stated direction:** admit the merge only when every required context in
  `scripts/ci-required-ruleset-canonical-required-status-checks.json` is present and green by name
  on the exact head SHA, counted rather than inferred from the absence of red.
- **Challenge (DHH, code-simplicity):** delete the plan's Phase 4 script, because the branch ruleset
  already refuses the merge until the required checks pass.
- **Kept, because:** the operator asked for this explicitly. The script also catches the case where a
  check is missing entirely, which is not the same thing as a check that failed. The count is derived
  from the JSON rather than hard-coded, and only the latest run per name is read.

## DC-2: settle Doppler's description-counting rule empirically (Taste)

- **Suggestion (CTO):** create and delete one throwaway Doppler project whose description is 255
  multibyte characters. That would show whether the API counts UTF-16 units or bytes, and the lint's
  conservative byte rule could then be relaxed.
- **Not taken, because:** it is a write to the Doppler workplace that this fix does not need. The lint
  measures raw UTF-8 bytes, which is an upper bound under either counting rule.
