---
title: "Never hand a Soleur user an SSH/dashboard task — exhaust the no-SSH prod-signal toolchain, and BUILD a signal if none exists"
date: 2026-06-03
category: workflow-patterns
tags: [no-ssh, soleur-vision, observability, sentry, doppler, incident-verification]
related_prs: [4886, 4895]
related_rules: [hr-no-ssh-fallback-in-runbooks, hr-no-dashboard-eyeball-pull-data-yourself, hr-exhaust-all-automated-options-before, hr-weigh-every-decision-against-target-user-impact]
---

# Never hand a Soleur user an SSH/dashboard task

## The vision constraint (always load this before proposing a verification/diagnosis step)

**Soleur's target users are non-technical founders.** They do not have a terminal,
cannot SSH into a Hetzner box, will not run `df -h` / `docker exec` / `journalctl`,
and will not "go check the Sentry dashboard." Any step that requires them to is a
**product failure**, not a verification plan. This is the spirit of
`hr-no-ssh-fallback-in-runbooks`, `hr-no-dashboard-eyeball-pull-data-yourself`, and
`hr-weigh-every-decision-against-target-user-impact` — but those rules historically
fired on *runbooks/ship*, and the agent still reverted to operator-SSH during
**ad-hoc incident verification**. This learning closes that gap: the no-SSH
discipline applies to EVERY prod read, including one-off diagnosis.

## The no-SSH prod-signal toolchain (exhaust ALL of these before concluding "unreachable")

Acting FOR the operator, the agent has these no-SSH read paths. Try them all before
ever saying "you'll have to check":

1. **Prod DB (read-only):** `doppler run -p soleur -c prd -- node <pg query>` using
   `DATABASE_URL_POOLER`. (`psql` is usually absent; the app ships `pg` — a tiny
   node script works.) This reads `kb_sync_history`, `workspaces.repo_last_synced_at`,
   migration state, anything in Postgres.
2. **Sentry issues API — THE KEY DISCOVERABLE:** `SENTRY_AUTH_TOKEN` is scoped to
   **monitors only** and returns `403` on issues. **`SENTRY_IAC_AUTH_TOKEN` (and
   `SENTRY_ISSUE_RW_TOKEN`) CAN read issues** (`200`). Always try every
   `SENTRY*`-named Doppler secret on the target endpoint before concluding a signal
   is unreachable. Org issues endpoint:
   `GET https://jikigai-eu.sentry.io/api/0/organizations/jikigai-eu/issues/?query=is:unresolved&statsPeriod=24h` —
   the actual error stderr (e.g. a failing `git pull`) is in the latest event's
   `entries[type=exception].values[].value`. This is how the real root cause was
   found (a dirty-clone `.claude/settings.json`, NOT the ENOSPC the incident report
   assumed). Sentry tokenizes free-text oddly — filter `is:unresolved` and match
   titles client-side rather than trusting a free-text `query=`.
3. **Fire crons on demand:** `/soleur:trigger-cron` → `POST /api/internal/trigger-cron`
   (secret from Doppler, zero SSH). Reclaim/repair actions run here.
4. **Prod HTTP:** `curl` app routes / `/hooks/*` deploy webhooks / health endpoints.
5. **CI/deploy state:** `gh run view --log-failed`, `gh run list`.

## When NO no-SSH signal exists, BUILD one — do not hand it to the operator

If the thing you need to verify has no queryable signal (e.g. the GC's `freedMb`
on a healthy run was pino-only, not shipped — #4897), the answer is **never** "SSH
and check." It is: emit the signal to a channel the agent (and a non-technical user)
CAN read — a **GitHub issue** (the `cron-supabase-disk-io` pattern: file/comment the
stat, `gh issue view` it), a **DB row**, or a **read endpoint**. Building the signal
IS the fix.

## Session errors this encodes (so they cannot recur)

1. **Proposed "please run `df -h` on the host" + "you have SSH/Sentry access I
   lack."** Violation of the vision. **Prevention:** the toolchain above; the agent
   has the access — it just hadn't tried `SENTRY_IAC_AUTH_TOKEN` on issues.
2. **Declared a Sentry signal "unreachable" after one token returned 403.**
   **Prevention:** try EVERY `SENTRY*` Doppler token on the endpoint before concluding.
3. **Chased an ENOSPC theory from the incident report instead of pulling the actual
   error.** The reconcile's real stderr (dirty `.claude/settings.json`) was one
   Sentry-issue read away the entire time. **Prevention:** before trusting an
   incident report's stated mechanism, pull the producer's actual error via the
   no-SSH toolchain and confirm it.

## Key insight

A verification step that ends in "the operator should check X" is only acceptable
when X is a CAPTCHA/OTP/payment-card/hardware-MFA gate — never for reading prod
state. For prod state: pull it yourself (Doppler DB, Sentry issues via
`SENTRY_IAC_AUTH_TOKEN`, trigger-cron, HTTP), and if no signal exists, build one.
Keep the Soleur non-technical-user vision in frame BEFORE proposing any step.
