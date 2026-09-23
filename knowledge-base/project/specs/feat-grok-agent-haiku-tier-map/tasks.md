# Tasks: drop the Claude model alias from Grok research stubs

## Phase 1: Generator

- [ ] 1.1 In `compatStubMarkdown`, omit the `model` line when the source value is `haiku`, `sonnet`, `opus`, or `fable`.
- [ ] 1.2 Run the generator and confirm the five `soleur-engineering-research-*.md` stubs have no `model` line.
- [ ] 1.3 Confirm `soleur-product-cpo.md` still has `model: inherit` and the Claude research agents still have `model: haiku`.

## Phase 2: Guard and record

- [ ] 2.1 Extend `plugins/soleur/test/grok-inspect-contract.test.ts` so a research stub with a `model` line fails, and an `inherit` stub without `model: inherit` fails.
- [ ] 2.2 Append the 2026-09-23 measurement addendum to ADR-110. Do not change decision 4.
- [ ] 2.3 Run `bun run scripts/sync-grok-agent-compat.ts --check` from `plugins/soleur` and the new test.
