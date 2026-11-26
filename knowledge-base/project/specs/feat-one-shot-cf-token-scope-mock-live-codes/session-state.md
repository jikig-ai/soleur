# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-11-26-test-cf-token-scope-mock-live-grant-codes-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)

### Errors
None (collision pre-check flagged draft #12958, no file overlap).

### Decisions
- Only the shared authorized-grant default models zone-rest; mock answers per URL (settings 1006, bot_management 10400), redirects-dns rows keep 10026 with an unmeasured note.
- Probe script unchanged: any non-6007 400 already classifies as authorized.
- M2 tightened to two whole-line pins; MIN_ASSERTIONS 680 -> 681.
- CTO cut the committed mutation row; a scratch-copy mutation check runs at work time.
- SKILL.md "not yet measured" sentence: recorded operator (scope) row.

### Components Invoked
soleur:plan, soleur:deepen-plan, soleur:engineering:cto (x2), learnings-researcher, code-simplicity-reviewer, test-design-reviewer

## Operator Constraints
- Ref #12931 only, never Closes/Fixes. Never print token values. No SSH. No live Cloudflare calls from tests. Leave the old zone read-only. No gh-pages cert reissue with probeOnly:false.
