# Learning: a correctness counter lived in the one store its neighbours evict, and a substring `if:` check passed a dead disjunct

## Problem

`scheduled-rehearsal-skip-monitor.yml` kept its consecutive-TRANSIENT streak in
the GitHub Actions cache. The `Assert the streak state round-trips` step was red
on 24 of the last 30 daily runs. The brief said "the cache is over its cap";
measurement (`gh api repos/.../actions/caches`, grouped by key prefix and ref)
found the cause was not the monitor and not PR refs: 160
`buildkit-blob-1-sha256:*` entries (9.6 GB) written by the release workflow's
`cache-to: type=gha,mode=min` (~1.2 GB per release). GitHub evicts
least-recently-accessed first, so a 192-byte entry read once per 24 hours is
always the next candidate. The monitor's own keys never accumulated, and
hand-deleting caches would be refilled by the next release.

## Solution

Move the counter to a store the neighbours cannot evict: a workflow artifact
(`rehearsal-skip-monitor-streak`, `retention-days: 90`), behind one script
(`scripts/monitor-streak-state.sh`: `fetch`, `seal`, `assert`) so the decision
logic is testable without a hosted runner (ADR-296). The release export churn is
tracked separately (#10917), not fixed here.

Review (10 seats, ~30 findings, no P1) closed edge cases worth keeping:

- **The read side must be bounded as hard as the write side.** A downloaded
  artifact is attacker-plantable by anyone with write access: cap the archive
  size, read through `timeout … unzip -p | head -c`, accept digits only, and make
  a failed or hung listing fatal while only corrupt CONTENT is discardable, and
  only under an explicit `bootstrap` input.
- **A write that is `2>/dev/null || true` needs a read-back.** The probe's own
  streak write could be lost, so `seal` compares against the value `fetch`
  restored (TRANSIENT must equal restored+1) instead of trusting the file.
- **A job-level alert must also fire on a failed STATE step.** A red scheduled
  run has no watcher, which is how 24 red days went unacted. The alert `if:` was
  extended to the four state-step outcomes, and the body lists them.
- **Substring checks of an `if:` expression pass a neutralised disjunct.**
  `"steps.upload.outcome == 'failure'" in cond` stays true after
  `(… && false)`. Compare the whole expression by EXACT equality, then add
  mutation rows that kill dead-disjunct variants (`&& false`, `continue-on-error`).

## Key Insight

State that decides whether an escalation fires belongs in a store whose eviction
policy it does not share with bulk build output. And when a test proves "this
condition reaches the alert", the assertion must be equality on the condition,
never a substring: a substring is satisfied by the dead branch it was meant to
rule out.

## Session Errors

- **`gh api repos/.../actions/artifacts` without `?name=` failed ("unexpected end
  of JSON input").** Recovery: the design only uses the exact-name listing.
  **Prevention:** a one-off API quirk; recorded in the script header.
- **Two `gh issue create` calls blocked by a hook** until the body file was its
  own step and a `Mandated-By:` line was added. **Prevention:** already
  hook-enforced; write the body with the Write tool first.
- **The technical-ruling gate rejected eight `decision-challenges.md` rows**
  (planner calls and a `pending - assumed` placeholder); one batched CTO spawn
  ruled all eight. **Prevention:** rule technical forks at plan time, never leave
  a `pending` row (hr-technical-fork-is-not-an-operator-question).
- **A Bash heredoc nested another heredoc with the same terminator**, so the outer
  one ended early. Recovery: wrote the patch script with the Write tool.
  **Prevention:** multi-line patch scripts go through Write, not nested heredocs.
- **The first panel's substring `if:` checks (P3/P10) and an untested alert body
  were weaker than their names.** Fixed in review round 2. **Prevention:** covered
  by `cq-assert-anchor-not-bare-token`; the new property checks use exact equality.
- **The local affected-tests gate ended rc=6 (budget-deferred).** CI is the
  authoritative gate; recorded as not passed. **Prevention:** none needed; the
  rc is the signal.

## Tags

category: integration-issues
module: ci/scheduled-rehearsal-skip-monitor
