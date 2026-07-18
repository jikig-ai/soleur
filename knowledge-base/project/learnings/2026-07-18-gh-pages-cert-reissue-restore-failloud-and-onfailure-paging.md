# Learning: an auto-remediation's restore/onFailure path is the load-bearing surface — it must fail LOUD and always page

**Date:** 2026-07-18
**Issue:** #6657 (PR #6676) — event-triggered GitHub Pages cert `bad_authz` reissue routine
**Category:** integration-issues / security-issues

## Problem

Built an Inngest routine (`cron-gh-pages-cert-reissue`) that transiently flips the apex+www
Cloudflare `proxied` flag false→true (a DNS-only window that drops CF WAF/DDoS + origin-IP hiding)
to re-issue a stuck GitHub Pages TLS cert, then restores the declared steady state. The forward
path was correct and well-tested. Multi-agent review (8 agents) found **three P1s all clustered on
the failure/restore/observability surface** — the part that only runs when something goes wrong,
i.e. exactly when it matters most and is hardest to test:

1. **`restoreState` failed OPEN on a Cloudflare read error.** The live `listToggleRecords` coalesced
   a failed CF GET to `[]` (`(res.body).result ?? []`). So a CF 403/429/5xx during restore →
   `records=[]` → the for-loop restored nothing → the convergence assert (`stillWrong.length > 0`)
   passed vacuously over the empty set (and cname, read via GitHub, was still healthy) →
   `restoreState` returned success having re-proxied ZERO records. Origins stayed exposed
   indefinitely, `outcome=issued` shipped as a green info log, and NO exception → no `onFailure` →
   no P0 page. The dangerous CF error classes (a CF control-plane incident, a token problem) are
   exactly when you most want the restore to fail loud.

2. **The `onFailure` success branch paged nobody.** A persistent Octokit throw during the poll loop
   → retries exhausted → `onFailure` self-healed the restore and emitted only `logger.info` (which
   mirrors to Sentry only at ≥warn, and never as an issue-firing event). So a retries-exhausted body
   throw left the cert still `bad_authz` and origins transiently exposed, and the founder was paged
   NOTHING.

3. **The production handler was untested.** The unit tests thoroughly exercised a pure `runReissue`
   twin that was NEVER called in production; the real Inngest handler re-implemented the same
   orchestration inline and diverged (wall-clock poll vs fixed-count). The tests advertised
   remediation coverage the shipping code did not have.

## Solution

- **Restore/convergence guards must fail LOUD on a READ failure, never coalesce to empty.**
  `listToggleRecords` now `throw`s (+ `reportSilentFallback`) on a non-ok CF GET instead of `?? []`;
  `restoreState` asserts an expected lower-bound record count (`>= EXPECTED_TOGGLE_RECORDS`, the
  4 apex A + 1 www CNAME) before AND after the writes, so a partial/empty read can't "restore" a
  subset and silently leave origins exposed. The final re-read convergence assert stays (catches a
  PATCH that returns success but doesn't stick).
- **A self-healing `onFailure` must ALWAYS page.** Even when the restore succeeds, a retries-exhausted
  body throw means the remediation did NOT complete — emit a feature-tagged `reportSilentFallback`
  (`outcome=reissue_incomplete_restore_ok`) so it's never silent; the restore-fail branch keeps
  `proxy_restore_failed`.
- **Test the code that ships.** Extracted the production step-orchestration into `runReissueSteps(step,
  deps, logger)` (drivable by a fake `step` + fake `deps`) and DELETED the parallel `runReissue`/
  `pollCertState` twin. The tests now drive the production control flow and cover the convergence
  brake, the short-read throw, the `approved` poll branch, and the settle-sleep window.
- **Benign vs page-worthy.** A not-yet-provisioned config (the DNS-edit token IaC not applied) is
  `config_missing` → `logger.warn`, NOT a page. Only genuine remediation failures emit to Sentry, so
  the feature-scoped issue-alert has no false-positive arm.

## Key Insight

For any auto-remediation that transiently degrades a protected surface (drops WAF, opens a window,
takes a lock), the **restore path and the retries-exhausted `onFailure` path are the load-bearing
security surface** — and they are the least-exercised code. Review/test them adversarially:
- a guard that READS state to decide what to restore must fail CLOSED when the read itself fails
  (coalescing a failed read to "nothing to do" is a silent-open-window vector — the render-sink
  sibling of `hr-write-boundary-sentinel-sweep-all-write-sites`);
- a self-heal that SUCCEEDS after a body throw must still page (silence == "nothing happened",
  which is false);
- test the orchestration that runs in production, not a pure twin that diverges (a green suite over
  a dead mirror is untested prod code).

## Session Errors

- **`-target` allowlist misread (recurring).** Concluded `cloudflare_record.github_pages`/`.www` were
  NOT in `apply-web-platform-infra.yml`'s `-target` list by reading only the first part of the list
  (`:323-332`); they were at `:343-345`. The wrong "records can't be reverted mid-window" claim
  propagated into ADR-125, session-state, #6677, the parity-test comment, and the plan; caught by
  architecture-strategist. **Recovery:** corrected all five artifacts + a #6677 comment. **Prevention:**
  when asserting a resource IS / IS NOT in a workflow allowlist, `grep -n '<resource>' <workflow>`
  the WHOLE file (or `grep -c`), never eyeball a head slice — same class as `hr-when-a-plan-specifies-relative-paths-e-g` (verify against the artifact, don't assume from a partial read).
- **Inngest handler poll used `Date.now()` for loop control (recurring, self-caught).** A wall-clock
  `while (Date.now() - start < MAX)` in the handler body is non-deterministic across Inngest replays
  (a resume re-stamps `start`) → shifting `step.run` names on resume. **Recovery:** fixed-count `for
  (i < MAX_POLLS)` loop; memoized `startedAt` via `step.run("mark-start")` for correct `elapsedMs`.
  **Prevention:** Inngest handler control flow + any emitted timing must be deterministic across
  resumes — fixed iteration counts, and stamp `Date.now()` INSIDE a `step.run`, never in the body.
- **`.env.example` permission deny (one-off).** Read/Bash/Edit all denied by a path rule; the entry is
  documentation-only (runtime reads Doppler), surfaced to the operator to add manually. No recurrence
  vector for the workflow.
- **`iac-plan-write-guard` hook blocks ×2 (one-off, plan phase).** Missing `<!-- iac-routing-ack -->`
  comment + a literal "out-of-band" tripping the guard regex; both resolved in the plan phase.
- **tsc union-narrowing error (one-off).** `"blocked" in pre` did not discriminate a 3-variant union;
  fixed with an explicit `status: "not_stuck"|"blocked"|"ok"` discriminant. Prevention: use an explicit
  discriminant field for multi-variant step-return unions, not `in`-narrowing.

## Tags
category: integration-issues
module: apps/web-platform/server/inngest
