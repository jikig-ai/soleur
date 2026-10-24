# Decision Challenges — feat-one-shot-9703-inngest-alert-delivery

Recorded during `soleur:plan` on the Devin CLI harness (no subagent-spawn
capability). Per the pipeline's technical-ruling delegation rule, technical
forks that could not be ruled by `soleur:engineering:cto` are recorded as
`pending - assumed: <default>`; the plan ships the assumed default and the
ruling is owed at review/ship time.

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| WS1 alert-routing route: GitHub-issue incident mirror (repo-side `GET /api/v2/incidents` poller filing deduped `ci/betterstack-incident` issues) vs Slack integration coverage vs paid-tier escalation policy | technical | pending - assumed: build the GitHub-issue mirror as the primary deliverable (provably-watched channel, zero vendor-tier dependency, reuses BETTERSTACK_API_TOKEN_READONLY + the existing dedupe-issue pattern), plus a Phase-0 measurement of the wired Slack integration's heartbeat coverage and a measured `push = true` flip on the two inngest heartbeats; the Responder-tier escalation policy is named operator-reserved (money) |
| Mirror placement: dedicated `scheduled-betterstack-incident-mirror.yml` + watchdog-dispatch-table row + sentry_cron_monitor vs a job inside the existing scheduled-inngest-probe-heartbeat.yml | technical | pending - assumed: dedicated workflow — the feeder's ADR-248 eligibility and Sentry monitor are scoped to beating the dead-probe heartbeat; a generic all-heartbeats incident mirror is a different property and belongs on its own slug + dispatch row (eligibility clause 1: it reports on the Inngest substrate itself) |
| WS2 serving-verdict delivery: beat `<url>/fail` on `not-serving` (web-bash-synthetic precedent) vs withhold the beat vs a second heartbeat | technical | pending - assumed: `/fail` beat on `classify_dedicated_host` verdict `not-serving`, normal beat on `healthy`, withhold (exit 3 CANNOT ESTABLISH) on `probe-unavailable`, normal beat on `stopped-by-brake` (deliberate state already covered by its own watchdog issue class) — reuses the in-repo `/fail` precedent and keeps one monitor |
| WS3 soak vehicle: postmerge skill phase (point read) + followthrough-enrolled soak script (daily window) vs ship Phase-7 edit (sibling-collision surface) | technical | pending - assumed: postmerge phase + generic followthrough soak script + the WS1 mirror as the always-on surface; ship/SKILL.md is avoided because draft-PR #10966's sibling worktree already edits it |
| Epic #10390 scope: implement WS1+WS2+WS3 in one PR vs split | operator (scope) | pending - assumed: single PR — cohesive alert-delivery arc, ~10 files, under the split thresholds; the sentry-root two-PR rule for the mirror's own cron monitor is the one mechanical reason a second PR may follow (routing half), noted in the plan |
