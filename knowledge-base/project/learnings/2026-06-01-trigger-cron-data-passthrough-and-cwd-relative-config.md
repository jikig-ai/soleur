# Learning: trigger-cron `data` pass-through + the CWD-relative-config gotcha

## Problem

Two deferred follow-ups from PR #4735's review (#4742): (A) widen
`POST /api/internal/trigger-cron` to forward an optional caller `data` object to
crons, and (B) make the route discoverable to agents (skill + runbook rewrites)
so the SSH `inngest send` loopback was no longer the only documented path.

The route was previously security-signed-off ONLY in its no-data form, so (A)
re-opened a threat surface (caller-controlled payload to mutating/paid crons at
`single-user incident` brand threshold).

## Solution

**A — the merge order IS the security contract.** The dispatched envelope spreads
route-controlled keys LAST: `{ ...callerData, trigger: "manual-api", at: new
Date().toISOString() }`. The issue's prose `{ trigger, at, ...data }` describes
*intent*, not literal spread order — writing it literally would let a caller
forge `trigger`/`at` and defeat the manual-api audit marker (audit-poisoning).
Plain-object validation rejects array/primitive/boolean `data` with 400 before
dispatch; `null`/absent are treated as no-data. The existing 64 KiB
413-before-parse guard already covers the widened body. The route stays a dumb
forwarder — each cron validates its own fields (cron-bug-fixer validates
`issue_number`).

**B — skill, not MCP tool.** No in-repo MCP-tool framework exists; the codebase
convention for "read a Doppler secret + curl an internal route" is a skill+script
(precedents: admin-ip-refresh, flag-create, user-set-role). The skill's `--list`
derives the allowlist from `EXPECTED_CRON_FUNCTIONS` via cron-manifest.ts — the
same source the route's `manual-trigger-allowlist.ts` uses. A parity test
(`plugins/soleur/test/trigger-cron-allowlist-parity.test.ts`) asserts the two
independent extractions (awk text-scrape vs TS import) cannot silently drift.

## Key Insight

When a feature forwards caller-controlled data into a merge, **spread order is a
security property, not a style choice** — route-controlled keys must win.
Encode it as a positive test that is self-gating (assert a non-colliding caller
key survives AND a colliding route key wins), so the test can't silently become
a tautology if a sibling test is later removed.

## Session Errors

1. **plan Write blocked by write-guard hook on literal `doppler secrets set` in prose** — Recovery: rephrased to "read-only; never writes/mutates" + added `iac-routing-ack` comment. Prevention: describe a forbidden command ("a Doppler write command") rather than writing the literal in plan/doc prose.
2. **Task fan-out unavailable in the planning subagent env** — Recovery: deepen-plan ran its hard gates inline. Prevention: environmental; the gates already carry an inline-fallback path.
3. **semgrep exited 7 (`config path does not exist`) after a persisted `cd apps/web-platform`** — Recovery: re-ran from the worktree root. Prevention: the Bash tool persists CWD across calls; run repo-root-relative-path commands (semgrep `--config=plugins/soleur/...`) from the worktree root, or `cd <root> &&` in the same call. **This is the generalizable one — routed to the review skill's semgrep step.**
4. **shellcheck SC2028 on a dry-run `echo "\\n..."`** — Recovery: switched to `printf`. Prevention: use `printf '%s\n'` for any line containing backslash escapes.
5. **broken generated import line in the new parity test** — Recovery: fixed before first run. Prevention: read generated import statements before executing.

## Tags
category: integration-issues
module: apps/web-platform/app/api/internal/trigger-cron, plugins/soleur/skills/trigger-cron
