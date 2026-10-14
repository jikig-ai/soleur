---
title: "Cloudflare 524 made every long Inngest step run twice and commit nothing"
date: 2026-09-23
category: integration-issues
module: apps/web-platform/server/inngest
tags: [inngest, cloudflare, 524, claude-eval, cost, anthropic, streaming, observability]
symptom: "A $50 Anthropic top-up drained in ~39h; each long cron spawned two concurrent Claude sessions under one run id; most paid runs committed no output"
root_cause: "serveHost pins execution to the Cloudflare-proxied https://app.soleur.ai; steps over ~100s get a 524, retries:1 re-runs the unmemoized step, the retry also 524s and the run is marked failed"
related: [PR #8611, "#5692", "#8613", "#8614"]
---

# Learning: Cloudflare 524 made every long Inngest step run twice and commit nothing

## Problem

The operator asked about Anthropic's "low prompt cache hit rate" email. The real problem was different:
credit ran out in about a day and a half. Better Stack showed paired `SOLEUR_CLAUDE_COST` markers
sharing one Inngest run id, with overlapping lifetimes: the second `spawn_started_at` came 2.5–4.7
minutes after the first while the first was still running. The inngest-server log explained it:

```text
error handling queue item ... invalid status code: 524      (≈2 min after start)
received event inngest/function.failed  event_id=<run id>   (while both children still ran)
```

## Root cause

`app/api/inngest/route.ts` pins `serveHost` to `https://app.soleur.ai` (#5159), and that record is
Cloudflare-proxied (`dns.tf` `proxied = true`). So the self-hosted Inngest server calls every step
through Cloudflare, which gives up on an origin response after ~100s. A claude-eval step holds its
request for 5–70 minutes:

1. The first attempt gets a 524.
2. `retries: 1` re-invokes the step. Nothing was memoized, so a **second paid session** spawns.
3. The retry gets a 524 too, and the run is marked failed.
4. `verify-output` and `safe-commit-pr` never run.

Measured over 30 days, from the CLI's own `cost_usd`: duplicates were **51%** of cron spend
($82 of $160), and 24 of 33 paid runs committed nothing. The problem only showed once credit
returned. Before that, every run died in seconds on "credit balance is too low" and never reached
the 100s mark.

The prompt-caching email was a red herring for this workload. The direct Messages API calls are
one-offs hours apart (no reuse within the TTL), or below Haiku's 4,096-token minimum. The Claude
Code/Agent SDK traffic, which is excluded from that email, already hits cache at over 97%.

## Solution (shipped — PR #8611, ADR-243)

A Phase 0 spike on the pinned server behind a real Cloudflare tunnel chose **Branch A** over
detach-and-poll:

- **Streaming.** `serve({ streaming: "force" })` answers 201 at once and writes a heartbeat byte
  every 3 s, so the proxy never times out (spike S2: zero 524s on a 3-minute step).
- **The most reusable finding: the SDK's streaming crashes the process on a dropped stream.**
  `inngest` 3.54.2's `createStream` clears its heartbeat only in `finalize()` and has no `cancel()`,
  so a consumer disconnect makes every tick throw from a timer — an `uncaughtException`, which the
  app's crash handler turns into `process.exit(1)`. The spike missed it on plain `next start` (which
  only logs) and measured it once the S7 rows installed the production crash handler.
  `server/inngest/stream-detach.ts` re-streams the body and drains the SDK stream instead of
  cancelling it; `inngest` is pinned exactly and the helper is content-hash-pinned in its test. The v4
  upgrade (#8628) fixes it upstream.
- **Single-flight + settled result.** `spawnClaudeEval` joins a live child for the same
  `(cronName, runId)` and returns a finished child's result for 2 hours, so a dropped-stream retry
  never starts a second paid session (spike S7c/S7e: one spawn).
- **Substrate-owned budget.** `spawnClaudeEval` appends `--max-budget-usd` from the cron's own
  `CLAUDE_BUDGET_USD` entry and refuses a caller-supplied one; a capped run is its own fatal class
  (`budget-capped`), so it turns the cron red instead of reading as a clean exit.
- Also: a 2/hour manual-fire throttle (a rate limit, not a spend bound), Better Stack alerts on
  inngest-server 524s / dropped streams, a $25 trailing-24 h spend floor and a dark-telemetry alarm,
  and `turn`/`attempt` on the founder BYOK leader-loop cost marker so a double-billed turn is
  detectable. The Opus 5 → Opus 5.5 audit-tier re-pin the plan called for landed first on main via
  #8601.

## Key insight

A transport timeout at a proxy between a durable-execution engine and its SDK causes more than a
retry. When the step is not idempotent, the engine re-executes work that is still running, and the
run fails anyway. So you pay twice and get nothing. For any engine that calls back into the app over
HTTP, compare the longest step duration with every proxy timeout on the callback path.

Two corollaries from implementing it:

- **A spike is only as faithful as the production process's FAILURE semantics, not its transport.**
  The spike server mirrored `server/index.ts`'s request path and omitted its `uncaughtException →
  process.exit(1)` handler, so the one behaviour that made raw streaming unshippable read as log
  noise. Likewise, killing a self-hosted `inngest start` (in-memory queue, no Redis) to "cut a
  stream" lost the retry entirely — production runs a durable queue. Cut connections, not
  processes, and install every fatal-error handler the production process installs.
- **A detector must not compare two quantities written by the same step.** The plan's BYOK check
  compared summed cost markers against `cumulativeCents`; a re-run step writes both again, so they
  still match after a double bill. Detect duplication from a field the retry changes (`attempt`,
  a per-turn key) or from an independent count (run history).

## Session Errors

1. **I claimed `cost_usd` was null on every marker from two eyeballed samples.** I built "Fix 4:
   root-cause `cost_usd`" on that claim. It was populated on 118/118 claude-eval markers. Separately,
   the runbook's SQL read a top-level field that has sat under `raw.message` since #8344.
   **Recovery:** the observability reviewer queried live data; I re-counted.
   **Prevention:** count a field's population over the full export before claiming absence, at its
   current nesting path (routed to plan-sharp-edges).
2. **I priced spend from token counts ($107.85) while the authoritative `cost_usd` ($159.81) sat in
   the same records.** Token pricing misses sub-agent spend and the 1h cache-write rate.
   **Recovery:** recomputed every figure.
   **Prevention:** same as 1. Use the emitter's own cost field and treat token math as a cross-check.
3. **My first jq aggregation returned `[]`** because it ran `fromjson` on a field that was already an
   object. **Recovery:** type-guarded parse.
   **Prevention:** one-off. Check `type` before `fromjson` on decoded log rows.
4. **`gh issue create --body-file $D/x.md` was blocked by the filing gate,** which cannot resolve
   variables. **Recovery:** literal path.
   **Prevention:** already documented. Pass a literal repo path to `--body-file`.
5. **Plan v1 rejected SDK streaming as "undocumented, blast radius" without testing it,** then designed
   a detach-and-poll runner. Review found nine defects in the runner, all caused by runs sleeping.
   **Recovery:** a Phase 0 spike decides the branch.
   **Prevention:** when the simplicity and correctness panels both fire on a mechanism, spike the
   rejected one-line alternative before patching. The plan-review skill already says to prefer
   delete over fix.
6. **I picked ADR-238 from `origin/main` only.** 238–240 were already claimed on pushed branches.
   **Recovery:** an all-refs scan found it; renumbered to ADR-241.
   **Prevention:** this is an existing sharp edge (quantify over `origin/*`). Apply it at the first
   pick, not at deepen time.
   **Addendum (implementation, same day):** by the time the ADR file was written, ADR-241 and
   ADR-242 had been claimed by two other branches, so it moved again to ADR-243. The deepen pass
   had also swept "238–240" into the nonsense range "241–240" in the plan. A branch-picked ordinal
   is a lease, not a claim: re-scan `origin/*` right before creating the file and again before merge.
7. **I set brand threshold `none`, reasoning only about the crons.** `serve()` is shared, so the
   transport change also reaches the founder-facing BYOK leader loop, where a misread streamed error
   could double-bill a founder's key. **Recovery:** threshold raised to `single-user incident`, the
   spike given retry/multi-step rows, and a CPO sign-off obtained with conditions.
   **Prevention:** derive the threshold of a handler-level change from every function behind that
   handler (`grep functions:` in the serve call), not from the functions motivating the change.
8. **Some research-agent claims were wrong,** e.g. "private serveHost breaks cron planning per
   ADR-106". **Recovery:** each was verified before use.
   **Prevention:** existing rule. Treat a subagent's claim as a hypothesis to re-derive.
9. **The unkept-promise stop hook fired twice** on "I'll…" closing text while waiting on background
   agents. **Recovery:** emitted `<stop>BLOCKED: …</stop>`.
   **Prevention:** one-off. When waiting on agents, end with the stop marker, not a promise.

Implementation and review (same day):

10. **The spike server omitted the production crash handlers,** so the SDK heartbeat-leak crash was
    found by reading `stream.js`, not by the spike. **Recovery:** S7 re-ran with the handlers and a
    restart loop; the control crashed, the wrapper held. **Prevention:** routed to plan-sharp-edges —
    a spike installs the production process's fatal-error handlers.
11. **The first S7 cut SIGKILLed the self-hosted inngest server,** whose in-memory queue then lost the
    retry. **Recovery:** a TCP proxy that drops live connections. **Prevention:** same sharp edge.
12. **The S7 driver found no proxy pid** (an exact-name `pgrep node` misses processes whose comm is
    `node-MainThread`), so the first control run did nothing. **Recovery:** pid by listening port.
    **Prevention:** one-off; resolve a server's pid from its socket.
13. **A readiness monitor fired on stale log content** from an earlier run. **Prevention:** one-off;
    truncate or timestamp-gate a log before watching it.
14. **A full-command-line process match was blocked by the self-match hook again,** inside the driver
    script. **Prevention:** already hook-enforced.
15. **The issue-filing gate refused a `/tmp` body file,** and the heredoc that wrote it sat inside the
    blocked command, so the file never existed; the filing then needed `Mandated-By:`. **Recovery:**
    body written with the Write tool inside the worktree. **Prevention:** existing guidance (literal
    in-repo path; write the body in its own step).
16. **My route-level disconnect test could not discriminate** — an unsigned request finalizes before
    any cancel. **Recovery:** mutation caught it; replaced with a wiring test. **Prevention:** existing
    rule (drive the mutation that undoes the fix).
17. **The single-`serve()`-mount grep matched my own explanatory comment.** **Recovery:** anchored on
    the `serve` import. **Prevention:** existing rule `cq-assert-anchor-not-bare-token`.
18. **A static import of the substrate broke `vi.mock` hoisting** in two cron suites. **Recovery:**
    dynamic import in `beforeEach`. **Prevention:** one-off.
19. **A Python-heredoc quoting error left a test rewrite unwritten,** and the Write tool refused twice
    on files changed since read. **Prevention:** one-off; write whole files with the Write tool.
20. **A commit failed the typecheck hook** on a fixture edited after my last `tsc`. **Prevention:**
    one-off; re-run `tsc` after the last edit, not the last big one.
21. **I duplicated two changes main already had** — #8601's `AUDIT_MODEL` re-pin and #8599's ledger
    drift fold-in — and resolved seven conflicts at review time. **Recovery:** took main's versions.
    **Prevention:** routed to the work skill — fetch and diff `origin/main` for a shared constant or
    ledger before editing it.
22. **The review panel broke the code 17 ways with every suite green** (settled retention exercised
    only by a synchronous retry; Guard 2 pinned SQL text, not predicates; the budget flag checked by a
    grep a comment satisfied). **Recovery:** the budget moved into the substrate (one enforcement
    point) and the predicates are evaluated on fixtures; 10/10 new-guard mutations killed.
    **Prevention:** existing review rules; this is the recurring class, not a new one.
23. **The BYOK rollback trigger had no working detector.** **Recovery:** `turn`/`attempt` on the
    leader-loop marker. **Prevention:** routed to plan-sharp-edges (Key insight above).
24. **I wrote a derived "~9.4 funded days"** before reading the plan's measured 9.3. **Prevention:**
    one-off; quote the measured figure.
25. **Two small correctness slips:** a markdownlint MD037 in the ledger row, and the spike doc's
    "crashed ~15 s later" where the exit was logged in the same second. **Prevention:** one-off.

## Tags

category: integration-issues
module: apps/web-platform/server/inngest
