---
title: "bwrap deploy gate rolled back two releases and could not say why — the probe discarded its own exit code and stderr"
date: 2026-09-11
incident_pr: 8026
incident_window: "Two occurrences. First: v0.260.0, 2026-09-04 (per the plan's 28-day Better Stack read). Second, fully measured: 2026-09-09T22:31:56.708Z DEPLOY_ROLLBACK line for v0.264.6 → recovered 2026-09-10T00:25:28Z when the next release (v0.265.x) passed the same gate."
recovery_at: "2026-09-10T00:25:28Z (next release green; no intervention). The DIAGNOSTIC gap closes when #8026 deploys; the ROOT CAUSE stays open on #8016 under sweeper enrollment."
suspected_change: "None identified — that is the incident. The blocking bwrap probe ran `docker exec … bwrap … -- true 2>&1` inside `if !`, which consumed both the exit code and the stderr, so the only record of either rollback is the literal `DEPLOY_ROLLBACK: bwrap sandbox non-functional in <image>` with no reason. #8016's headline (that the gate's reason string contradicts its payload) was a misreading of two canaries sharing the word 'sandbox'; corrected on the issue."
brand_survival_threshold: single-user incident
status: resolved
triggers:
  - availability (release delivery — two releases rolled back by their own safety gate; production
    kept serving the previous image throughout, no user-facing path was affected)
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a"
# Classification rationale: a delivery-path availability event with no personal-data dimension.
# The gate did what it exists to do (reject a canary whose sandbox could not be verified) and the
# next release recovered without intervention; the incident is that the gate could not NAME its
# reason, so the same class will recur undiagnosed until it can. `single-user incident` matches
# the plan/PR threshold: the founder cannot ship while a release is rolled back, and the fix
# captures container stderr that can carry env-formatted secrets — which is why the PR's
# sanitizer, its Art. 30 PA-8 (g) bracket, and the user-impact review exist. No personal data was
# exposed, accessed, altered, or lost in either occurrence; Art. 33/34 do not apply (`n/a`).
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option per `hr-menu-option-ack-not-prod-write-auth`.
- `human` — Operator did this directly.

# Incident Overview

The web-platform release pipeline's blocking bwrap sandbox probe (`apps/web-platform/infra/ci-deploy.sh`,
the `Verifying bwrap sandbox...` block) rolled back two releases in six days — v0.260.0 on 2026-09-04
and v0.264.6 on 2026-09-09 — and in both cases the only durable record was
`DEPLOY_ROLLBACK: bwrap sandbox non-functional in <image>`. The probe ran its `docker exec` inside
`if ! … 2>&1`, which discarded the exit code (`!` consumes `$?`) and the stderr (`2>&1` inside the
condition), so neither the exit-code class (bwrap's own failure vs. exec failure vs. signalled child)
nor the message survived. Each rollback self-healed on the next release. The incident is the
undiagnosability, not the rollback: with 53 deploys/week and a ~2% failure rate, the class recurs and
nothing learns from it.

## Status

resolved — the diagnostic gap is closed by PR #8026 (exit code, duration, container state, raw length
and sanitized stderr now ride the same journald line, plus a `SANDBOX_PROBE_OK` twin on every green
deploy). The root cause of the two rollbacks remains unknown by construction and is tracked on #8016,
whose closing arms are evaluated mechanically by the follow-through sweeper.

## Symptom

A release run fails at the canary stage with `reason=canary_sandbox_failed`; Better Stack shows exactly
one `ci-deploy`-tagged line for it, carrying no bwrap text (`err` was empty on both occurrences). The
next release passes the identical probe. Nothing in the record distinguishes "bwrap printed nothing and
was killed" (rc=137 shape) from "bwrap failed with a message we threw away" (rc=1 shape).

## Incident Timeline

- **Start time (detected):** 2026-09-09T22:31:56Z (second occurrence; the first, 2026-09-04, was found
  retrospectively in the same Better Stack read)
- **End time (recovered):** 2026-09-10T00:25:28Z
- **Duration (MTTR):** 1h 53m (release-to-release; no human action)

Order of events (load-bearing: the redaction sentinel scans this table; the Actor key feeds the Actor column):

| Actor | Time (UTC) | Action |
|---|---|---|
| system | 2026-09-04 | v0.260.0 rolled back by the bwrap probe; no reason recorded. Not noticed as a class. |
| system | 2026-09-09T22:31:56Z | v0.264.6 rolled back by the bwrap probe (`DEPLOY_ROLLBACK: bwrap sandbox non-functional in 10.0.1.30:5000/jikig-ai/soleur-web-platform:v0.264.6`). Release run concluded `failure` at 22:38:18Z. |
| system | 2026-09-10T00:25:28Z | Next release passed the same probe; production on the new image. Recovery. |
| human | 2026-09-10 | Operator filed #8016 with a contradiction reading (reason string vs. payload). |
| agent | 2026-09-10 | Better Stack 48h read: one occurrence, empty message; identified the two-canaries naming collision and the real defect (discarded rc + stderr). Corrected the issue by comment, body untouched. |
| agent | 2026-09-10 | PR #8026: probe self-report + fail-closed sanitizer + Art. 30 PA-8 (g) bracket (CLO-ruled). Review found and fixed a raw stdout re-emit and a self-inflicted over-redaction. |
| agent | 2026-09-11 | Second review round at ship time: order-dependent value-arm leak fixed; runbook section added; #8016 enrolled in the follow-through sweeper. |

## Participants and Systems Involved

- `apps/web-platform/infra/ci-deploy.sh` — the blocking bwrap probe (distinct from the non-blocking
  ADR-079 faithful sandbox canary, which shares the word "sandbox" and nothing else).
- `soleur-web-platform-canary` container, run with `--env-file` (so its `Config.Env` holds prd secrets).
- journald `ci-deploy` → Vector `host_scripts_journald` → Better Stack Logs (the only read path; the
  host is not reachable from a keyboard per `hr-no-ssh-fallback-in-runbooks`).
- `adnanh/webhook -verbose`, which re-logs the script's stdout under `SYSLOG_IDENTIFIER=webhook`.

## Detection (+ MTTD)

- **How detected:** release workflow conclusion `failure` + the operator noticing the rollback reason;
  the class (two occurrences, both reason-less) was detected by the agent's Better Stack read on
  2026-09-10.
- **MTTD (mean time to detect):** minutes for the rollback itself (workflow red); ~5 days for the
  class (2026-09-04 → 2026-09-10), because a reason-less line has nothing to alert on.

## Triggered by

system — the probe's own failure inside the canary; no operator action and no external provider
event is known to be involved (unknown by construction — see 5-Whys).

## Root-cause hypothesis (triage)

Triage-time competing hypotheses; the post-resolution final root cause lives in the 5-Whys section below.

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| H1 — bwrap failed inside a live container (namespace/mount setup) | Every bwrap self-failure returns 1 and prints to stderr | Message was empty both times; the `-- true` argv is unchanged since the June revert | open, discriminated by `rc=1 cstate=running` + message |
| H2 — `docker exec` infra failure (container already gone / not running) | `rc=1` shape shared with H1; canary lifecycle races exist | No `cstate` was recorded, so undecidable on the old line | open, discriminated by `cstate=exited/unknown` |
| H3 — exec'd child signalled (OOM / SIGKILL / timeout) | An empty message is exactly what a signalled child looks like | Kernel OOM channel is dark (not in any Vector allowlist) | open, discriminated by `rc=128+n err_chars=0` and `ms` |
| H4 — immediate refusal mistaken for a killed hang (or the reverse) | — | — | open, discriminated by `ms` |

The old line could not separate any of these. The new line separates all four in one event; the next
occurrence names itself.

## Resolution

PR #8026. The capture became `BWRAP_ERR="$(docker exec …)" || BWRAP_RC=$?` (the only form that keeps the
exit code — `if !` consumes it, measured `rc=137 len=0`), with `ms` from bash `EPOCHREALTIME`
(`date +%s%3N` is broken on this host's uutils coreutils), `cstate` from `docker inspect` taken before
teardown, `err_chars` as the raw length, and `bwrap_err` as the last 200 chars after a fail-closed
sanitizer (`<sanitize_failed>`), shape rules, and a longest-first value arm substituting the env
file's own values. `<empty>` is retained as a sentinel because "bwrap said nothing" and "we discarded it"
were previously indistinguishable, and that distinction is the diagnosis. `BWRAP_RC` now gates the
rollback, so the capture form is a safety property: reverting it to `if !` makes the gate fail OPEN
(measured under mutation — zero rollback lines).

## Recovery verification

Release run created 2026-09-09T22:35:56Z concluded `success` at 2026-09-10T00:25:28Z on the same probe;
prod CURRENT was 0.265.2 at the start of the #8026 session. Verification that the NEW line is live is
the first post-merge `SANDBOX_PROBE_OK` row in Better Stack (query in
`knowledge-base/engineering/operations/runbooks/canary-probe-set.md`, §"Blocking bwrap sandbox probe").

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. **Why did two releases roll back?** The blocking bwrap probe returned non-zero inside the canary.
   Why it did is unknown — see 2.
2. **Why is it unknown?** The probe was written as `if ! docker exec … 2>&1; then`, which discards the
   exit code (`!` sets `$?` to 0 inside the branch) and the stderr (captured into the condition and
   never stored). The rollback line carried the image name and nothing else.
3. **Why was it written that way?** The block was hardened for a different failure (a June change to the
   bwrap argv rolled back every deploy and was reverted; the NOTE block records it). Attention went to
   the argv, not to what the probe reported when it failed; a probe that fails ~2% of the time and
   self-heals on the next release produced no pressure to look.
4. **Why did nothing catch the reason-less line?** The line was queryable in Better Stack, but a
   reason-less line has no field to alert on and no runbook named the probe; the ADR-079 faithful
   canary next to it emits a structured `sandbox_canary` payload, which is what the operator read and
   mistook for this probe's payload (#8016's original framing).
5. **Why could the operator confuse the two?** Two canaries share the word "sandbox" in one block, one
   blocking and one non-blocking, with no cross-reference in either's output. The runbook section added
   in #8026 now states the distinction; the new line's fields make the blocking probe's output
   self-describing.

## Versions of Components

- **Version(s) that triggered the outage:** v0.260.0 (2026-09-04), v0.264.6 (2026-09-09) — both rolled
  back, neither served.
- **Version(s) that restored the service:** the immediately following releases (v0.260.1-class on
  2026-09-04; v0.265.x on 2026-09-10), unchanged probe.

## Impact details

### Services Impacted

Release delivery only. `soleur-web-platform` kept serving the previous image; the canary is pre-cutover.

### Customer Impact (by role)

Per learning `2026-05-06-user-impact-section-by-role-not-surface.md` — enumerate by USER ROLE, not by surface. This is the canonical "Customer Impact"; do NOT add a second free-text Customer Impact block.

- Prospect: none (marketing site and app served throughout).
- Authenticated app user: none — the prior image served; the delayed releases carried no user-facing fix.
- Legal-document signer: none.
- Admin via Access: none.
- Billing customer: none.
- OAuth installation owner: none.

### Revenue Impact

None. Two releases delayed by under two hours each; no paid path was affected.

### Team Impact

The founder could not ship for the duration of each rollback and had no way to learn why; #8016 was
filed on a misreading because the only structured payload nearby belonged to the other canary. One
agent session (#8026) to make the probe self-report, including a review round that caught a raw
stdout re-emit and an order-dependent redaction leak in the fix itself.

## Lessons Learned

### Where we got lucky

- Both rollbacks self-healed on the next release. Had the failure been persistent, the founder would
  have been locked out of shipping with a rollback line that named nothing — and the host is not
  reachable from a keyboard.
- The canary runs with `--env-file`; the fix captures its stderr. Had the review not measured that
  ci-deploy's stdout reaches Better Stack under the `webhook` tag, the first cut of the fix would have
  shipped unsanitized bytes off-box seven lines before sanitizing them.

### What went well

- The gate itself worked: neither broken canary took the production port.
- The Better Stack read path (Vector allowlist for `ci-deploy`) already existed, so the missing datum
  was one capture form away rather than a new pipeline.
- The naming collision was resolved on the issue by comment without rewriting the operator's text.

### What went wrong

- A blocking gate discarded its own diagnosis, and a self-healing ~2% failure rate meant nobody was
  forced to notice for months.
- Two canaries sharing a name in one block produced a false issue framing.
- The fix's first cut introduced two defects of the class it was fixing (raw re-emit; over-redaction
  of `libkeyring.so.1` → `libkeyJ.REDACTED`) and a third at ship time (a shorter public env value
  unmasking a longer composite secret) — each caught by a review seat, none by the suites as first
  written. See `knowledge-base/project/learnings/2026-09-10-my-sanitizer-was-bypassed-by-the-line-above-it.md`.

## Action Items & Follow-ups

Every action item and follow-up so this incident cannot recur (save logs, add tests, set up alerts, automation, documentation, code sweeps, PRs).

**Each row MUST cite a filed GitHub issue number.** A bare bullet or a `TBD`/`(none)` placeholder is not allowed — file the issue first (`gh issue create`, cross-referencing the source PR in the body), then record its number here. An item with no `#NNNN` is shelf-ware that rots the moment the session ends; the `/ship` Incident-PIR gate blocks merge on any item that lacks an issue reference. If there are genuinely zero follow-ups, write exactly `_No action items — incident fully resolved in the source PR with no residual work._` (the only permitted no-item form).

| Issue | Action | Status |
|---|---|---|
| #8016 | Root cause of the two rollbacks. Enrolled in the follow-through sweeper (`scripts/followthroughs/bwrap-probe-selfreport-8016.sh`): a recurrence comments the trusted fields and leaves it open for a fix; ≥20 clean self-reporting deploys close it as environmental. | open |
| #8036 | Adjacent, same deploy: `docker login ghcr.io` fails on every deploy (`stage=relogin_failed`), masked by the zot mirror. Not a cause of the rollbacks; found while reading the same Better Stack window. | open |
| #8037 | Adjacent, same root as #8036: image signature verification has never succeeded (`cosign_absent`), so the `IMAGE_VERIFY_MODE=enforce` soak can never pass. | open |
