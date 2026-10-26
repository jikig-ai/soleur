# Purpose of http-retry-backoff

## Origin

Several unrelated sessions rediscovered the same retry mistakes.

## Patterns addressed

- synthetic-retry-pattern

Retries without caps and retries of unsafe requests recurred across sessions.

## Nearest existing skill and why not patched

Nearest existing skill: ship.

The ship skill covers release preparation, not the retry policy of arbitrary outbound calls, so a patch would bury it.

## Merge and retire candidates

- Retire this skill if a workflow skill grows a retry section

## Evolution history

- 2026-10-26: created as a draft by the automated proposer from the pattern page named above, pending human review.

## Attribution

Provenance and attribution: the prompt and structure text behind this skill's creation is adapted from the paper WikiSkill (Google Research), arXiv:2608.27454, licensed under CC BY 4.0 (<https://creativecommons.org/licenses/by/4.0/>). The authors are credited on the source page at <https://arxiv.org/abs/2608.27454>. Changes made: the text was adapted to this repository's learnings corpus and rendered by an automated proposer; no endorsement by the authors or Google Research is implied.
