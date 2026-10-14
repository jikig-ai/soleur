# Decision log: feat-ci-pr-selection (PR B of the CI affected-only gating plan)

| Item | Class | Ruling |
|---|---|---|
| `pr-selection` timeout against the release CI budget | technical | Ruled by CTO agent, 2026-10-14: job `timeout-minutes: 3`, in-step `timeout 120`, no `needs: push-dedupe` (a serial edge makes the declared path 76 over the 75 cap) - the release awk sums the longest `needs:` chain and today's path is 73 |
| Dark-mode cost of the selector | technical | Ruled by CTO agent, 2026-10-14: two stages; stage 1 is a pure-bash positive allowlist, stage 2 runs only on doc-only diffs, in dark mode too, with `skip_legs` empty unless `active=true` - code PRs pay no pre-pass and dark runs yield measured `sel_s` evidence |
| Group skip rule and `test-bun` | technical | Ruled by CTO agent, 2026-10-14: a group skips only with a non-empty stream, all `sel=0` or `--pr-gated` declines, `fallback=none` and no `always_on` row; `test-bun` gate built as asked but expected to stay un-skipped; diagrams edits never skip `test-webplat` - ADR-181 makes plain relevance declines unreachable under CI |
| `head_sha` / `base_sha` semantics | technical | Ruled by CTO agent, 2026-10-14: `head_sha := HEAD^2`, `base_sha := HEAD^1` after asserting merge-ref shape; `run_attempt > 1` forces full - a re-run reuses the same payload so the SHA comparison alone cannot detect a moved base |
| Scope trims inside the operator's list (`mode` output, `pr-affected-active`, G2-3/G2-4, `ci-e2e-classify.sh` in the trigger list) | technical | Ruled by CTO agent, 2026-10-14: all five trims confirmed; keep a source-coverage test for `test-all.sh` - every sourced file is under `scripts/lib/` today |
| ADR frontmatter direction | technical | Ruled by CTO agent, 2026-10-14: ADR-276 `amends: [ADR-262, ADR-183]`; ADR-262 gains `amended_by:`; ADR-183's existing `amended_by:` list is appended to - the plan text was inverted |
| Keep `head_sha`/`base_sha`/comma-list `skip_legs` though DHH proposed booleans | operator (scope) | Kept as the operator specified; no cut |

CPO sign-off for PR B: APPROVED-WITH-CONDITIONS by the CPO agent, 2026-10-14 (not an operator item); conditions are folded into the plan's PR B contract.
