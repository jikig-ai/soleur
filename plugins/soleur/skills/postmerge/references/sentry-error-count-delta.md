# Phase 3.6: Sentry Error-Count Delta — procedure

Loaded by [postmerge SKILL.md](../SKILL.md) Phase 3.6 when the PR body or linked issue names a specific Sentry issue. The trigger, the report vocabulary and the Graceful Degradation rows stay in SKILL.md.

**Prerequisites:** the same `SENTRY_ORG` / `API_HOST` resolution as Phase 3.5 (the block below repeats it, so it runs on its own). **The single-issue GET needs an `event:read` token** — the `/organizations/<org>/issues/<id>/` endpoint returns `403` on the `SENTRY_AUTH_TOKEN`/`SENTRY_API_TOKEN` resolved from Doppler `soleur/prd` (Discover/ingest scope only). The GET uses the least-privilege `SENTRY_ISSUE_RO_TOKEN`, falling back to `SENTRY_ISSUE_RW_TOKEN` GET-only — the same ladder as [scripts/sentry-issue.sh](../../../../../scripts/sentry-issue.sh). The write-scoped RW token is used for the auto-resolve PUT only. No read token, or a failed GET, is `SKIPPED` — never `STILL-FIRING`.

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
# Same resolution as Phase 3.5 — this block runs on its own.
SENTRY_ORG=$(doppler secrets get SENTRY_ORG -p soleur -c prd --plain 2>/dev/null || echo "jikigai")
API_HOST="${SENTRY_ORG}.sentry.io"
# GET: least-privilege RO token, RW as a GET-only fallback (scripts/sentry-issue.sh's
# ladder). The prd SENTRY_AUTH_TOKEN 403s on /issues/<id>/ (#7797) — never use it here.
# RW is resolved separately: the auto-resolve PUT below needs it and nothing else does.
SENTRY_RO_TOKEN=$(doppler secrets get SENTRY_ISSUE_RO_TOKEN -p soleur -c prd --plain 2>/dev/null || true)
SENTRY_RW_TOKEN=$(doppler secrets get SENTRY_ISSUE_RW_TOKEN -p soleur -c prd --plain 2>/dev/null || true)
SENTRY_READ_TOKEN="${SENTRY_RO_TOKEN:-$SENTRY_RW_TOKEN}"
# Fail-safe defaults: anything below that does not complete leaves the phase SKIPPED
# and ISSUE_STOPPED=false, so the PUT cannot fire on missing data.
SENTRY_DELTA=SKIPPED; ISSUE_STOPPED=false; ISSUE_STATUS=""; ISSUE_JSON=""
if [[ -z "$SENTRY_READ_TOKEN" ]]; then
  echo "WARNING: neither SENTRY_ISSUE_RO_TOKEN nor SENTRY_ISSUE_RW_TOKEN is set (the prd SENTRY_AUTH_TOKEN 403s on /issues/<id>/). Sentry error-count delta: SKIPPED."
elif [[ ! "$ISSUE_ID" =~ ^[A-Za-z0-9_-]+$ ]]; then
  echo "WARNING: issue id '$ISSUE_ID' is not a bare token. Sentry error-count delta: SKIPPED."
else
  # Query the issue; capture curl's rc — a failed GET is SKIPPED, not STILL-FIRING.
  get_rc=0
  ISSUE_JSON=$(curl -sfS -H "Authorization: Bearer ${SENTRY_READ_TOKEN}" \
    "https://${API_HOST}/api/0/organizations/${SENTRY_ORG}/issues/${ISSUE_ID}/") || get_rc=$?
  if (( get_rc != 0 )) || ! ISSUE_STATUS=$(jq -er '.status' <<<"$ISSUE_JSON" 2>/dev/null); then
    echo "WARNING: Sentry issue GET failed (curl rc=$get_rc, or no .status in the body). Sentry error-count delta: SKIPPED."
    ISSUE_STATUS=""
  else
    jq '{shortId, status, count, lastSeen}' <<<"$ISSUE_JSON"
    ISSUE_LASTSEEN=$(jq -r '.lastSeen' <<<"$ISSUE_JSON")
    # Mechanical stopped-firing signal — this boolean, NOT the prose below, gates
    # the auto-resolve PUT. True only when the issue is already resolved/ignored OR
    # lastSeen predates the deploy. Any parse failure leaves it false (fail-safe:
    # never auto-resolve on ambiguous data).
    if [[ "$ISSUE_STATUS" == "resolved" || "$ISSUE_STATUS" == "ignored" ]]; then
      ISSUE_STOPPED=true
    elif [[ -n "$ISSUE_LASTSEEN" && "$ISSUE_LASTSEEN" != "null" ]]; then
      LASTSEEN_EPOCH=$(date -d "$ISSUE_LASTSEEN" +%s 2>/dev/null || echo 9999999999)
      DEPLOY_EPOCH=$(date -d "$DEPLOY_TS" +%s 2>/dev/null || echo 0)
      (( LASTSEEN_EPOCH < DEPLOY_EPOCH )) && ISSUE_STOPPED=true
    fi
    if [[ "$ISSUE_STOPPED" == "true" ]]; then SENTRY_DELTA=STOPPED; else SENTRY_DELTA=STILL-FIRING; fi
  fi
fi
echo "Sentry error-count delta: $SENTRY_DELTA"
```

Interpretation (all outcomes are **WARN-only — never a merge blocker**):

- `lastSeen` is older than the deploy timestamp **or** `status` is `resolved`/`ignored` (`ISSUE_STOPPED=true`): "Sentry error-count delta: error appears to have stopped firing post-deploy." — the expected good outcome; report `STOPPED` (or `AUTO-RESOLVED` if the write below succeeds). **Auto-resolve runs in this branch only** (see below).
- `lastSeen` is after the deploy timestamp (`SENTRY_DELTA=STILL-FIRING` — the GET succeeded and `ISSUE_STOPPED=false`): "WARNING: Sentry issue `<shortId>` is still firing after the deploy (lastSeen <ts>). The fix may be ineffective or the root cause may differ from the diagnosis — recommend re-opening for investigation rather than closing." Report `STILL-FIRING` and surface it prominently in the Phase 7 report. **Never auto-resolve in this branch.**
- No read token, Sentry API unreachable / issue not found / non-200 (`SENTRY_DELTA=SKIPPED`): warn and report `SKIPPED`. A failed GET never reads as `STILL-FIRING`.

**Auto-resolve (expected-good-outcome branch only).** When the GET above shows the error has stopped firing (`lastSeen` older than the deploy **or** `status` already `resolved`/`ignored`) **and** the issue is not already `resolved`, PUT `status:"resolved"` so the historical issue leaves the active list automatically. This requires a dedicated write-scoped token — the `SENTRY_AUTH_TOKEN`/`SENTRY_API_TOKEN` read tokens resolved from `soleur/prd` lack `event:write`/`event:admin` and return 403 on the write endpoint, so resolve a separate token and **skip (do NOT fall back to a read token)** when it is absent:

```bash
# SENTRY_RW_TOKEN, API_HOST and SENTRY_ORG were resolved in the block above; the
# write-scoped RW token is used here and only here.

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

The PUT reuses the SAME `API_HOST`/`SENTRY_ORG` resolution as the GET above (Phase 3.5's, from Doppler `prd`). On any non-200 (403 under-scoped, transient) it emits a WARN and continues — **never blocks**. Report vocabulary for this phase is `AUTO-RESOLVED` (write succeeded) / `STOPPED` (stopped firing, no token or already resolved) / `STILL-FIRING` / `SKIPPED`.

**Why WARN-only, not a blocker:** a true pre/post delta needs the original error to actually re-fire in the brief post-merge window. Low-frequency bugs (daily-cron failures, rare-path exceptions) legitimately show zero events for hours after a correct fix, so a hard gate here would produce noisy false negatives that erode trust in the pipeline. The signal is a prompt to *look*, not a verdict. For high-frequency errors a continued-firing signal is strong evidence the fix missed; consider a `/loop` re-check 15–30 min out before marking the linked issue resolved.
