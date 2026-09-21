# Phase 3.6: Sentry Error-Count Delta — procedure

Loaded by [postmerge SKILL.md](../SKILL.md) Phase 3.6 when the PR body or linked issue names a specific Sentry issue. The trigger, the report vocabulary and the Graceful Degradation rows stay in SKILL.md.

**Prerequisites:** same `SENTRY_AUTH_TOKEN` resolution as Phase 3.5 for the aggregate Discover count. **The single-issue GET below, however, requires the write-scoped `SENTRY_ISSUE_RW_TOKEN`** — the `/organizations/<org>/issues/<id>/` endpoint returns `403` on the `SENTRY_AUTH_TOKEN`/`SENTRY_API_TOKEN` resolved from Doppler `soleur/prd` (they carry Discover/ingest scope, not `event:read` on the issue resource). Using that token here makes the `curl -sfS` GET exit non-zero, leaving `ISSUE_JSON` empty → `ISSUE_STOPPED` stuck `false` → auto-resolve never fires. Resolve the RW token first; if it is absent, skip this phase (warn) since the GET cannot succeed without it.

> **Clarified 2026-09-08 (#7797) — `SENTRY_AUTH_TOKEN` names TWO different
> tokens, and only one of them 403s here.** An earlier revision of this
> block was "corrected" on the premise that the 403 claim above was false. That
> correction was withdrawn: it generalised a measurement taken on the
> `soleur/prd_terraform` token onto the `soleur/prd` token this phase actually
> resolves. Both measured 2026-09-08 against
> `GET /organizations/<org>/issues/<id>/`:
>
> - `soleur/prd` `SENTRY_AUTH_TOKEN` (what the code below reads) → **403**. The
>   requirement above is correct and stays.
> - `soleur/prd_terraform` `SENTRY_AUTH_TOKEN` (the #7797 leaked credential, a
>   personal token carrying org/project/team **admin**) → **200**.
>
> They are two different tokens sharing one variable name — the post-mortem
> records this explicitly. Do not treat a capability measured on one as evidence
> about the other, and do not widen this GET to an admin-scoped token: the
> least-privilege credential for it is `SENTRY_ISSUE_RO_TOKEN`
> (`event:read`, `org:read`, Doppler `soleur/prd`), and [scripts/sentry-issue.sh](../../../../../scripts/sentry-issue.sh)
> already implements the RO → RW ladder for this same URL.

```bash
# ISSUE_ID = the Sentry issue short-id or numeric id from the PR/issue body
# (a bare token: letters, digits, `-`, `_`). DEPLOY_TS = the merge commit's
# committer date (Phase 1 recorded the merge SHA) — the reference point for
# "did the error stop firing post-deploy?".
DEPLOY_TS=$(git show -s --format=%cI "<merge-commit-sha-from-phase-1>")
# The single-issue endpoint needs the write-scoped token: the soleur/prd
# SENTRY_AUTH_TOKEN 403s here (re-measured 2026-09-08, #7797 — the *prd_terraform*
# token of the same name returns 200, but it is a DIFFERENT credential and is not
# what this line resolves). Reused by the auto-resolve PUT below, so resolve it
# once. Absent -> skip phase. Least-privilege alternative if this is ever widened:
# SENTRY_ISSUE_RO_TOKEN (event:read, org:read), never SENTRY_AUTH_TOKEN.
SENTRY_RW_TOKEN=$(doppler secrets get SENTRY_ISSUE_RW_TOKEN -p soleur -c prd --plain 2>/dev/null || true)
if [[ -z "$SENTRY_RW_TOKEN" ]]; then
  echo "WARNING: SENTRY_ISSUE_RW_TOKEN not set — cannot read the issue (the prd SENTRY_AUTH_TOKEN 403s on /issues/<id>/). Skipping error-count delta + auto-resolve."
fi
# Query the issue; capture the response so the auto-resolve guard below can
# read status + lastSeen without a second GET.
ISSUE_JSON=$(curl -sfS -H "Authorization: Bearer ${SENTRY_RW_TOKEN}" \
  "https://${API_HOST}/api/0/organizations/${SENTRY_ORG}/issues/${ISSUE_ID}/")
echo "$ISSUE_JSON" | jq '{shortId, status, count, lastSeen}'
ISSUE_STATUS=$(echo "$ISSUE_JSON" | jq -r '.status')
ISSUE_LASTSEEN=$(echo "$ISSUE_JSON" | jq -r '.lastSeen')
# Mechanical stopped-firing signal — this boolean, NOT the prose below, gates
# the auto-resolve PUT. True only when the issue is already resolved/ignored OR
# lastSeen predates the deploy. Any parse failure leaves it false (fail-safe:
# never auto-resolve on ambiguous data).
ISSUE_STOPPED=false
if [[ "$ISSUE_STATUS" == "resolved" || "$ISSUE_STATUS" == "ignored" ]]; then
  ISSUE_STOPPED=true
elif [[ -n "$ISSUE_LASTSEEN" && "$ISSUE_LASTSEEN" != "null" ]]; then
  LASTSEEN_EPOCH=$(date -d "$ISSUE_LASTSEEN" +%s 2>/dev/null || echo 9999999999)
  DEPLOY_EPOCH=$(date -d "$DEPLOY_TS" +%s 2>/dev/null || echo 0)
  (( LASTSEEN_EPOCH < DEPLOY_EPOCH )) && ISSUE_STOPPED=true
fi
```

Interpretation (all outcomes are **WARN-only — never a merge blocker**):

- `lastSeen` is older than the deploy timestamp **or** `status` is `resolved`/`ignored` (`ISSUE_STOPPED=true`): "Sentry error-count delta: error appears to have stopped firing post-deploy." — the expected good outcome; report `STOPPED` (or `AUTO-RESOLVED` if the write below succeeds). **Auto-resolve runs in this branch only** (see below).
- `lastSeen` is after the deploy timestamp (`ISSUE_STOPPED=false`): "WARNING: Sentry issue `<shortId>` is still firing after the deploy (lastSeen <ts>). The fix may be ineffective or the root cause may differ from the diagnosis — recommend re-opening for investigation rather than closing." Report `STILL-FIRING` and surface it prominently in the Phase 7 report. **Never auto-resolve in this branch.**
- Sentry API unreachable / issue not found / non-200: warn and report `SKIPPED`.

**Auto-resolve (expected-good-outcome branch only).** When the GET above shows the error has stopped firing (`lastSeen` older than the deploy **or** `status` already `resolved`/`ignored`) **and** the issue is not already `resolved`, PUT `status:"resolved"` so the historical issue leaves the active list automatically. This requires a dedicated write-scoped token — the `SENTRY_AUTH_TOKEN`/`SENTRY_API_TOKEN` read tokens resolved from `soleur/prd` lack `event:write`/`event:admin` and return 403 on the write endpoint, so resolve a separate token and **skip (do NOT fall back to a read token)** when it is absent:

```bash
# SENTRY_RW_TOKEN was already resolved in Phase 3.6 above (the issue GET needs
# it too). Reused here for the PUT.

# Fire ONLY when the mechanical ISSUE_STOPPED signal is true (the still-firing
# branch is structurally unreachable here, never prose-gated), a write token is
# present, the issue is not already resolved, and ISSUE_ID is a bare token (the
# regex blocks a crafted id with `/`/`?` from retargeting a different issue on
# this state-mutating PUT). Body is discarded (-o /dev/null) — it returns the
# full issue object, which can carry production event data; only the HTTP code
# is load-bearing.
if [[ -n "$SENTRY_RW_TOKEN" && "$ISSUE_STOPPED" == "true" && "$ISSUE_STATUS" != "resolved" \
      && "$ISSUE_ID" =~ ^[A-Za-z0-9_-]+$ ]]; then
  RESOLVE_HTTP=$(curl -sS -o /dev/null -w '%{http_code}' -X PUT \
    -H "Authorization: Bearer ${SENTRY_RW_TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{"status":"resolved"}' \
    "https://${API_HOST}/api/0/organizations/${SENTRY_ORG}/issues/${ISSUE_ID}/")
  if [[ "$RESOLVE_HTTP" == "200" ]]; then
    echo "Sentry error-count delta: AUTO-RESOLVED issue ${ISSUE_ID}."
  else
    echo "WARNING: Sentry issue auto-resolve failed (${RESOLVE_HTTP}): verify SENTRY_ISSUE_RW_TOKEN has event:admin on ${SENTRY_ORG}; resolve manually in the UI."
  fi
fi
```

The PUT reuses the SAME `API_HOST`/`SENTRY_ORG` resolution as the GET above, so it inherits the env-correct `jikigai-eu` host from Doppler `prd`. On any non-200 (403 under-scoped, transient) it emits a WARN and continues — **never blocks**. Report vocabulary for this phase is `AUTO-RESOLVED` (write succeeded) / `STOPPED` (stopped firing, no token or already resolved) / `STILL-FIRING` / `SKIPPED`.

**Why WARN-only, not a blocker:** a true pre/post delta needs the original error to actually re-fire in the brief post-merge window. Low-frequency bugs (daily-cron failures, rare-path exceptions) legitimately show zero events for hours after a correct fix, so a hard gate here would produce noisy false negatives that erode trust in the pipeline. The signal is a prompt to *look*, not a verdict. For high-frequency errors a continued-firing signal is strong evidence the fix missed; consider a `/loop` re-check 15–30 min out before marking the linked issue resolved.
