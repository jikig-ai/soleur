#!/usr/bin/env bash
# Sentry Monitors/Alerts migration audit (one-shot, idempotent).
#
# Lists every Sentry Monitor, every org Workflow (issue-alert routing) and
# every org Detector (metric/cron alert definitions), joins monitors to
# detectors by slug and detectors to workflows by `workflowIds`, and writes a
# Markdown report to
# knowledge-base/legal/audits/sentry-migration-audit-<YYYY-MM-DD>.md
# (or to AUDIT_OUT_DIR if set).
#
# Endpoint provenance (#7590) — Sentry deprecated the alert-rule API family
# on 2026-05-14 and serves it under scheduled BROWNOUTS (HTTP 410 for a short
# window on a recurring schedule), which is why this audit alternated green
# and red on an unchanged script. The family was NOT removed outright. Each
# replacement below is the one Sentry names in its own
# `x-sentry-replacement-endpoint` response header, read off a live 410:
#
#   projects/{org}/{proj}/rules/   -> organizations/{org}/workflows/
#   organizations/{org}/alert-rules/ -> organizations/{org}/detectors/
#
# The mapping is PER-ENDPOINT. Pointing both at `workflows/` would silently
# mis-map metric alerts onto issue-alert routing. See ADR-031 amendment 13.
#
# Idempotency: the report path is keyed by date; same-day re-runs OVERWRITE
# the prior report at the same path (no append, no duplicate header).
#
# Match-by-id: monitors and rules are addressed by their immutable id/slug
# fields, never by name (Sentry API allows duplicate names — see
# 2026-04-29-supabase-auth-probe-and-sentry-rule-api-quirks.md).
#
# Required env: SENTRY_AUTH_TOKEN, SENTRY_ORG (SENTRY_PROJECT optional).
#
# TOKEN-NAMING TRAP: `sentry-audit-gate.yml` feeds the repo secret
# `SENTRY_IAC_AUTH_TOKEN` into the env var `SENTRY_AUTH_TOKEN`, while Doppler
# `prd` ALSO holds a genuinely different secret literally named
# `SENTRY_AUTH_TOKEN`. Reproducing a CI failure locally with Doppler's
# `SENTRY_AUTH_TOKEN` therefore exercises a different credential than CI uses.
# Use `SENTRY_IAC_AUTH_TOKEN` when reproducing this gate. (#7590 — this cost a
# full investigation that concluded, wrongly, that secrets had drifted.)
#
# Test injection (used by sentry-monitors-audit.test.sh ONLY):
#   SENTRY_API_HOST           — bypass region probe; force this host
#   SENTRY_FIXTURE_MONITORS   — file path; serve as monitors GET response
#   SENTRY_FIXTURE_RULES      — file path; serve as org workflows response
#   SENTRY_FIXTURE_DETECTORS  — file path; serve as org detectors response.
#                               When _MONITORS/_RULES are set and this is not,
#                               the detectors fetch serves `[]` rather than
#                               reaching the network, so fixture runs stay
#                               hermetic without every test declaring it.
#   SENTRY_TF_DIR             — read Class D `.tf` declarations from here
#   AUDIT_OUT_DIR             — write report here instead of repo legal dir
#   CURL_BIN                  — transport seam; the binary curl_retry invokes.
#                               The SENTRY_FIXTURE_* seams `cat` a file and
#                               return BEFORE curl runs, so they cannot express
#                               an HTTP status, a response header or a retry
#                               sequence — the three things #7590's defects all
#                               live in. Tests that need those stub `curl` on
#                               PATH (see sentry-monitors-audit.test.sh
#                               `mk_curl_stub`), matching the established repo
#                               dialect in apps/cla-evidence/scripts/*.test.sh.
#
# Class D state half (PRODUCTION input, not test-only):
#   SENTRY_STATE_SLUGS_FILE — path to a file of newline-separated monitor slugs
#     that Terraform state tracks. Class D = live AND undeclared AND *not in
#     state*: a monitor in state with no .tf block is a PENDING DESTROY the next
#     apply reclaims, not an orphan. Without this file the two are
#     indistinguishable and the script only WARNS (failing on an unresolvable set
#     deadlocks the apply — see the gate at the foot of this file).
#
#     A FILE PATH, not a value, so that "state is empty" (a legitimate state with
#     zero cron monitors, in which every live monitor IS a true orphan) is
#     distinguishable from "state was never read". A bare value cannot express
#     that: empty-string and unset are the same thing to the shell, so an empty
#     state would silently downgrade to a warning — fail-open on exactly the case
#     where every live monitor is unreclaimable. Mirrors the SENTRY_FIXTURE_*
#     file-path convention above.
#
#     Produced after `terraform init` by:
#       terraform show -json | jq -r '
#         .values.root_module.resources[]?
#         | select(.type=="sentry_cron_monitor") | .values.name'
#
# Dual-path output by caller (plan OQ1; PR #3811 review P1-H):
#   - Operator runs (Phase 2.1 baseline, local re-runs): AUDIT_OUT_DIR
#     unset → tracked dir `knowledge-base/legal/audits/`. Produces the
#     canonical pre-import snapshot in git history.
#   - CI release runs (Phase 2.2 — `reusable-release.yml`): override
#     AUDIT_OUT_DIR to `$RUNNER_TEMP/sentry-audit/`; the workflow then
#     uploads the resulting report as a per-release GitHub release
#     asset. Avoids commit-storm + write-to-main authorization surface.
#
# Plan: knowledge-base/project/plans/2026-05-15-feat-sentry-monitors-alerts-adapt-plan.md
# Phase: 1 (script) + 2.1 (operator run) + 2.2 (CI re-run on release)

set -euo pipefail

: "${SENTRY_AUTH_TOKEN:?SENTRY_AUTH_TOKEN must be set}"
: "${SENTRY_ORG:=jikigai}"
SENTRY_PROJECT="${SENTRY_PROJECT:-}"

# Transport seam. Tests override this (or shadow `curl` on PATH) to script a
# status sequence, response headers and a body — see the header's CURL_BIN note.
CURL_BIN="${CURL_BIN:-curl}"

# Scratch for per-call header dumps. curl_retry publishes the header-file PATH
# to its caller, so the file must outlive the call; it is reaped on exit.
AUDIT_SCRATCH="$(mktemp -d)"
trap 'rm -rf "$AUDIT_SCRATCH"' EXIT

# ── curl_retry metadata contract — FILE-backed, deliberately ──────────────
# Every call site is `x=$(curl_retry …)`, which runs the function in a
# SUBSHELL. A shell-variable global-out (zot-inventory's HTTP_CODE shape)
# therefore does NOT work here: the assignments happen in the child and are
# discarded on return, leaving the parent with an empty status and a tripwire
# that warned on stderr while its escalation flag silently reset to 0. That
# regression was live in this file until the T16/T17b transport-seam tests
# caught it — the same subshell trap zot-inventory's link_next documents, one
# level up, because there the FUNCTION was moved out of `$( )` whereas here the
# call shape is fixed by the callers (Gates 2/3 need the substitution).
#
# Files cross the boundary. These live in AUDIT_SCRATCH, which is set before
# any call, so the child writes and the parent reads.
CURL_LAST_STATUS_FILE="$AUDIT_SCRATCH/last_status"
CURL_LAST_HDR_FILE="$AUDIT_SCRATCH/last_hdr"
DEPRECATION_SEEN_FILE="$AUDIT_SCRATCH/dep_seen"
DEPRECATION_FATAL_FILE="$AUDIT_SCRATCH/dep_fatal"
: > "$CURL_LAST_STATUS_FILE"
: > "$CURL_LAST_HDR_FILE"
: > "$DEPRECATION_SEEN_FILE"
: > "$DEPRECATION_FATAL_FILE"

# Status of the most recent curl_retry call, readable from the parent shell.
curl_retry_status() { cat "$CURL_LAST_STATUS_FILE" 2>/dev/null || true; }
# Fail once a deprecation date is within this many days (or already past).
# A perpetual warning is what failed in 2026-07: versions.tf records this
# family answering 410 on 2026-07-17, written off as transient, because a
# warning on a green check has no teeth. Escape hatch: raise the window (or
# set it to a negative value) when an endpoint is deprecated with no
# replacement shipped yet.
DEPRECATION_FAIL_WINDOW_DAYS="${SENTRY_DEPRECATION_FAIL_WINDOW_DAYS:-30}"
# ESCALATION IS OFF BY DEFAULT, and that is a deliberate caller-scoped choice.
#
# The tripwire runs inside curl_retry, which Gates 1-3 also call. So its reach
# is NOT limited to the endpoints this audit migrated: a deprecation header on
# `/organizations/{org}/` — which this script must read to prove org
# controllability, and cannot migrate away from — would reach it too.
#
# `apply-sentry-infra.yml` runs this script BEFORE `terraform plan`. A hard
# failure there is a vendor-scheduled freeze on Sentry infra deploys, possibly
# including the deploy that would ship the migration. That is the same
# "detector blocks its own cure" deadlock the Class D state-half block below
# spends twenty lines avoiding, and the escape hatch named in the error text
# is set in NO workflow, so the apply path cannot clear it without merging a
# workflow edit first.
#
# So the teeth belong on the ADVISORY caller (sentry-audit-gate.yml), where a
# red costs a comment thread and a human is already reading the PR. The
# unconditional ::warning:: fires everywhere regardless.
DEPRECATION_FAIL_ENABLED="${SENTRY_DEPRECATION_FAIL:-0}"

# Emit a deprecation warning for any response carrying the header, on ANY
# status — including 200. This is the whole point: the endpoints that broke
# #7590 were serving 200 with a deprecation header for three months.
# Classify only; never exit from here (see curl_retry's contract below).
sentry_deprecation_tripwire() {  # $1 header-dump path, $2 url
  local hdr="$1" url="$2" dep repl endpoint now_s dep_s days
  [[ -s "$hdr" ]] || return 0
  # `-D` preserves wire casing, so the match must be case-insensitive.
  dep=$( { grep -iE '^x-sentry-deprecation-date:' "$hdr" 2>/dev/null || true; } | tail -1 \
    | tr -d '\r' | awk '{print $2}')
  [[ -z "$dep" ]] && return 0
  repl=$( { grep -iE '^x-sentry-replacement-endpoint:' "$hdr" 2>/dev/null || true; } | tail -1 \
    | tr -d '\r' | awk '{print $2}')
  # Dedupe on the path, not the full URL — a cursor query string would
  # otherwise make every page of a paginated fetch a distinct "endpoint".
  endpoint="${url%%\?*}"
  if ! grep -qFx -- "$endpoint" "$DEPRECATION_SEEN_FILE" 2>/dev/null; then
    printf '%s\n' "$endpoint" >> "$DEPRECATION_SEEN_FILE"
    echo "::warning::Sentry endpoint ${endpoint} is DEPRECATED (x-sentry-deprecation-date: ${dep}${repl:+; replacement: ${repl}}). Migrate before it sunsets — this header is served on successful responses too, and ignoring it is what made #7590 present as an intermittent flake." >&2
  fi
  now_s=$(date -u +%s)
  dep_s=$(date -u -d "$dep" +%s 2>/dev/null || echo "")
  if [[ -z "$dep_s" ]]; then
    # `date -u -d` is GNU-only; on BSD/macOS it fails. Returning here would
    # leave the warning firing while the escalation silently never arms —
    # a platform-conditional downgrade to exactly the toothless warning this
    # tripwire exists to replace, and indistinguishable from "no deprecation".
    # A date we cannot read is a finding, not an all-clear.
    echo "::warning::Sentry sent x-sentry-deprecation-date '${dep}' for ${endpoint} but this host cannot parse it (GNU \`date -d\` unavailable?). Escalation cannot be evaluated — treating as IN-WINDOW." >&2
    printf '%s %s\n' "$endpoint" "${dep} (unparseable — escalated conservatively)" >> "$DEPRECATION_FATAL_FILE"
    return 0
  fi
  days=$(( (dep_s - now_s) / 86400 ))
  if (( days <= DEPRECATION_FAIL_WINDOW_DAYS )); then
    # A marker file, not a variable: this runs inside the `$( )` subshell.
    printf '%s %s\n' "$endpoint" "$dep" >> "$DEPRECATION_FATAL_FILE"
  fi
  return 0
}

# Retry wrapper for Sentry API calls — the org-subdomain intermittently
# returns 500/timeout on GET /organizations/{org}/ and POST /releases/.
# Three attempts with 5s/10s backoff covers the transient 500 pattern
# observed since 2026-05-19. Returns the last attempt's output, ALWAYS exit 0.
#
# CAPTURE WITH `-D` ONLY. Never add `-w` or `-o` inside this wrapper.
# curl_retry's stdout is polymorphic: Gates 2/3 pass their own
# `-o /dev/null -w '%{http_code}'` and read stdout as the STATUS, while Gate 1
# and every fetch read it as the BODY. A wrapper `-w` placed after "$@" wins
# (duplicate -w is last-wins) and corrupts every body into `[...]200`, failing
# the shape check on a healthy 200 — i.e. firing the new diagnostic against a
# working endpoint. Placed before "$@" it is overridden and classifies nothing.
# `-D` is stdout-neutral: it writes headers to a file and leaves the caller's
# own `-w` intact.
#
# NEVER EXIT FROM HERE. Every call site is `x=$(curl_retry …)` under
# `set -euo pipefail`, so a non-zero return aborts at the assignment — the
# cryptic exit-28 failure the comment block above fetch_monitors exists to
# prevent. Classification is published through the globals and acted on at the
# shape check, which knows which fetch it is talking about.
curl_retry() {
  local max_attempts=3
  local attempt=1
  local backoff=5
  local result=""
  local rc=0
  local status=""
  local hdr url arg prev

  # A FIXED path, not a mktemp: the caller must be able to find this file after
  # the command substitution returns, and a per-call random name computed in
  # the child is unknowable to the parent. Callers that need it beyond the next
  # call snapshot it (see sentry_fetch_collection).
  hdr="$CURL_LAST_HDR_FILE"

  # Idempotency: a NON-IDEMPOTENT request is never repeated, by EITHER path.
  #
  # Gate 3 is a POST /releases/ whose `probe_ver` is computed ONCE, outside
  # this wrapper, and whose check is `!= 201`. Sentry returns 208 when the
  # release already exists, so re-sending a write that DID land server-side
  # yields a deterministic 208 and a false "token may lack project:releases
  # scope" diagnosis — halting the apply before `terraform plan`.
  #
  # The guard covers the TRANSPORT path as well as the status path, and that
  # is the half that matters most: a `--max-time 10` timeout on a POST whose
  # write already landed is the live case (curl exit 28 on this exact script
  # is recorded in the fetch_monitors comment below as having actually
  # happened), whereas a status-bearing 5xx at least proves the server
  # answered. An earlier revision of this block consulted `safe` only inside
  # the `rc == 0` branch, so a timed-out POST was re-sent three times while
  # this comment and ADR-031 both asserted it could not be.
  #
  # Safety is DECLARED by the call site AND inferred from argv — both, because
  # each alone fails open in a different direction.
  #
  # Declaration alone: a future author who adds a write and forgets the prefix
  # gets it retried. That is the failure this guard exists to prevent, and it
  # would be reintroduced by the very change meant to make the guard exact.
  # Inference alone: the previous scan matched only `-X <verb>`, so it missed
  # `--request POST` and read a bare `curl -d …` (a POST, to curl) as safe —
  # correct only by coincidence of Gate 3's writing style.
  #
  # So: the declaration is authoritative for intent, and the inference is a
  # backstop completed to cover every shape curl treats as a write. Either one
  # marking the request unsafe is enough. A false POSITIVE here costs one
  # un-retried transient failure; a false negative costs a duplicated write.
  local safe=1
  [[ "${CURL_RETRY_UNSAFE:-0}" == "1" ]] && safe=0
  prev=""
  url=""
  for arg in "$@"; do
    case "$prev" in
      -X|--request) case "$arg" in GET|HEAD) ;; *) safe=0 ;; esac ;;
    esac
    # Any body-bearing flag makes this a write to curl even with no -X.
    case "$arg" in
      -d|--data|--data-raw|--data-binary|--data-urlencode|-F|--form|-T|--upload-file) safe=0 ;;
      --data=*|--data-raw=*|--data-binary=*|--data-urlencode=*|--form=*) safe=0 ;;
      https://*|http://*) url="$arg" ;;
    esac
    prev="$arg"
  done

  while (( attempt <= max_attempts )); do
    : > "$hdr"
    if result=$("$CURL_BIN" -D "$hdr" "$@" 2>/dev/null); then rc=0; else rc=$?; fi
    # Parse the LAST `HTTP/` line — a redirect chain emits several. A transport
    # failure produces no status line at all; normalise that to `000` rather
    # than the empty string, so it renders the same way `-w '%{http_code}'`
    # renders it at Gates 2/3 and never prints as `returned HTTP `.
    status=$(awk '/^HTTP\//{c=$2} END{print c}' "$hdr" 2>/dev/null | tr -d '\r')
    [[ -z "$status" ]] && status="000"
    printf '%s' "$status" > "$CURL_LAST_STATUS_FILE"
    sentry_deprecation_tripwire "$hdr" "$url"

    if (( rc == 0 )); then
      # Transport succeeded. Retry only transient statuses. 410/404/401/403
      # are permanent: retrying a 410 would mask a post-sunset removal as a
      # flake, which is precisely the ambiguity #7590 spent an investigation
      # failing to resolve.
      [[ "$status" =~ ^(429|5[0-9][0-9])$ ]] || break
    fi

    # Unsafe requests stop here regardless of WHY the attempt failed.
    (( safe == 1 )) || break

    if (( attempt < max_attempts )); then
      echo "::warning::Sentry API attempt $attempt/$max_attempts failed (rc=${rc} status=${status}) — retrying in ${backoff}s" >&2
      sleep "$backoff"
      backoff=$(( backoff * 2 ))
    fi
    attempt=$(( attempt + 1 ))
  done
  printf '%s' "$result"
}

# ── Cursor extraction (Guard 1 / AC11a) ───────────────────────────────────
# Sets SENTRY_NEXT_CURSOR (empty = no next page). Mutates LINK_UNFOLLOWED, so
# it must run in the CALLER'S shell — never `$(sentry_next_cursor …)`.
#
# THE LINK TARGET IS NEVER FOLLOWED AS GIVEN. Only the `cursor` parameter is
# extracted; the URL is rebuilt from the already-validated $api_host. Two
# independent reasons, and the second is why a host-equality check would be
# WRONG here:
#
#  1. Security. curl parses everything before an `@` as userinfo, so a header
#     of `Link: <@attacker.tld/api/0/…>; rel="next"` resolves to attacker.tld
#     — a real off-box request carrying SENTRY_AUTH_TOKEN, whose response then
#     drives further requests. Measured against curl 8.18.0 in
#     scripts/zot-inventory.sh, which documents the same attack.
#  2. Correctness. Sentry's Link targets are absolute and point at
#     `sentry.io` even when the request went to `<org>.sentry.io` (verified
#     live 2026-08-17). So "reject any target whose host != $api_host" would
#     refuse EVERY real pagination and silently truncate the audit. Rebuild is
#     the only form that is both safe and correct.
LINK_UNFOLLOWED=0
MAX_PAGES="${SENTRY_AUDIT_MAX_PAGES:-50}"

sentry_next_cursor() {  # $1 header-dump path
  SENTRY_NEXT_CURSOR=""
  local hdr="$1" raw seg target cursor
  [[ -s "$hdr" ]] || return 0
  raw=$( { grep -iE '^link:' "$hdr" 2>/dev/null || true; } | tail -1 | tr -d '\r')
  [[ -z "$raw" ]] && return 0

  # Split the header into its comma-separated link-values. Herestrings, not
  # pipes: `producer | grep -q` takes SIGPIPE on an early match under
  # `set -o pipefail` and flakes to a false negative.
  local IFS_SAVE="$IFS"
  local -a segs=()
  IFS=',' read -r -a segs <<<"$raw"
  IFS="$IFS_SAVE"

  for seg in "${segs[@]}"; do
    grep -qE 'rel="?next"?' <<<"$seg" || continue
    # Three states, not two. `results="false"` means the next page is empty —
    # skipping it is correct, not a truncation. But `results` ABSENT is a
    # PARSE failure, and collapsing it into "done" is the fail-open this
    # mechanism exists to prevent: the sweep would silently stop and the
    # report would still say "Enumeration complete: yes". Its sibling failure
    # ten lines down (an unparseable cursor) already warns and counts; these
    # are the same class and must agree.
    if ! grep -qE 'results=' <<<"$seg"; then
      echo "::warning::Sentry returned a Link 'next' with no 'results' field; cannot tell an empty next page from a truncated sweep. Refusing to follow it. This sweep is INCOMPLETE." >&2
      LINK_UNFOLLOWED=$(( LINK_UNFOLLOWED + 1 ))
      return 0
    fi
    grep -qE 'results="?true"?' <<<"$seg" || continue

    target=$(sed -E 's/^[[:space:]]*<([^>]*)>.*/\1/' <<<"$seg")
    if [[ "$target" == *@* ]]; then
      echo "::warning::Sentry returned a Link 'next' target containing '@' (userinfo-injection shape); refusing it. This sweep is INCOMPLETE." >&2
      LINK_UNFOLLOWED=$(( LINK_UNFOLLOWED + 1 ))
      return 0
    fi

    cursor=""
    if [[ "$seg" =~ cursor=\"([^\"]+)\" ]]; then
      cursor="${BASH_REMATCH[1]}"
    fi
    # The cursor is interpolated into a URL, so it is validated too. Sentry
    # cursors are colon-delimited integers (`100:1:0`).
    if [[ -z "$cursor" || ! "$cursor" =~ ^[A-Za-z0-9:_.~=+-]+$ ]]; then
      echo "::warning::Sentry returned a Link 'next' with no parseable cursor; refusing to follow it. This sweep is INCOMPLETE." >&2
      LINK_UNFOLLOWED=$(( LINK_UNFOLLOWED + 1 ))
      return 0
    fi
    SENTRY_NEXT_CURSOR="$cursor"
    return 0
  done
  return 0
}

# --- Region detection (skipped if SENTRY_API_HOST is set) -----------------
# Probe order (PR-β §10.2 widened from `de.sentry.io sentry.io` baseline):
#   1. ${SENTRY_ORG}.sentry.io — org-subdomain is the ONLY host that works
#      for slug-scoped paths when the org slug ends in a region code (e.g.
#      `jikigai-eu`), per learning
#      `2026-05-17-sentry-eu-region-host-rewrites-slugs-with-eu-suffix.md`.
#   2. eu.sentry.io — EU regional API; works for slug-less endpoints only.
#   3. de.sentry.io — DE ingest cluster; no `/api/0/` surface but kept as a
#      back-compat probe for legacy personal tokens against the EU footprint.
#   4. sentry.io — US/global legacy.
# Region-probe target is still `/users/me/` (returns 200 for personal tokens
# regardless of org scope); internal-integration tokens 401 on `/users/me/`
# but the 4-gate block below catches that via the org-GET probe.
api_host="${SENTRY_API_HOST:-}"
if [[ -z "$api_host" ]]; then
  for candidate in "${SENTRY_ORG}.sentry.io" eu.sentry.io de.sentry.io sentry.io; do
    http=$(curl -s --max-time 10 -o /dev/null -w '%{http_code}' \
      -H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}" \
      "https://${candidate}/api/0/users/me/" 2>/dev/null || echo 000)
    if [[ "$http" == "200" ]]; then
      api_host="$candidate"
      break
    fi
  done
  if [[ -z "$api_host" ]]; then
    echo "ERROR: Sentry token not valid against any candidate host (${SENTRY_ORG}.sentry.io, eu.sentry.io, de.sentry.io, sentry.io). For internal-integration tokens (which 401 on /users/me/), set SENTRY_API_HOST explicitly to the org-subdomain." >&2
    exit 1
  fi
fi

# --- 4-gate destination-controllability check (PR-β §10 / C5) -------------
# Recurrence-prevention controls per #3861 Branch C. Gates verify the auth
# token can both READ and WRITE against the target org+project, and that the
# runtime DSN's encoded org-id matches the token's org-id (catches the
# split-state where audit token rotated but runtime DSN didn't).
#
# Additive to the L+30ish DSN cluster substring residency check below
# (Architecture F2: existing check is load-bearing for the SDK-DSN-vs-token-
# org-id split that the gates alone cannot catch — see plan §C5).
#
# Skipped under test mode (SENTRY_FIXTURE_MONITORS set) — the gates issue
# real HTTP calls that fixtures cannot mock without recursive
# fixture-of-fixtures complexity.
if [[ -z "${SENTRY_FIXTURE_MONITORS:-}" ]]; then
  # Gate 1: audit_destination_admin_controllable (org GET returns 200)
  gate1_body=$(curl_retry -s --max-time 10 \
    -H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}" \
    "https://${api_host}/api/0/organizations/${SENTRY_ORG}/")
  if ! jq -e '.id' <<<"$gate1_body" >/dev/null 2>&1; then
    echo "ERROR: Gate 1 (audit_destination_admin_controllable) failed — org ${SENTRY_ORG} not reachable at ${api_host}. Token may lack org:read scope, OR the host rewrites slugs ending in '-eu' (use the org-subdomain ${SENTRY_ORG}.sentry.io as SENTRY_API_HOST instead — see learning 2026-05-17-sentry-eu-region-host-rewrites-slugs-with-eu-suffix.md). Refs #3861." >&2
    exit 1
  fi

  # Gate 2: audit_project_scope (project GET returns 200) — skipped if no project set
  if [[ -n "$SENTRY_PROJECT" ]]; then
    gate2_http=$(curl_retry -s --max-time 10 -o /dev/null -w '%{http_code}' \
      -H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}" \
      "https://${api_host}/api/0/projects/${SENTRY_ORG}/${SENTRY_PROJECT}/")
    if [[ "$gate2_http" != "200" ]]; then
      echo "ERROR: Gate 2 (audit_project_scope) failed — project ${SENTRY_ORG}/${SENTRY_PROJECT} returned HTTP ${gate2_http}. Token may lack project:read scope. Refs #3861." >&2
      exit 1
    fi
  fi

  # Gate 3: audit_write_probe (POST release, expect 201 only — Kieran P1-4
  # dropped the 208 branch). Cleans up via DELETE on best-effort.
  probe_ver="audit-probe-$(date +%s)-$$"
  # The ONLY non-idempotent call in this file. Declared, not inferred — see
  # the idempotency block in curl_retry.
  gate3_http=$(CURL_RETRY_UNSAFE=1 curl_retry -s --max-time 10 -o /dev/null -w '%{http_code}' \
    -X POST \
    -H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{\"version\":\"${probe_ver}\",\"projects\":[\"${SENTRY_PROJECT:-web-platform}\"]}" \
    "https://${api_host}/api/0/organizations/${SENTRY_ORG}/releases/")
  if [[ "$gate3_http" != "201" ]]; then
    echo "ERROR: Gate 3 (audit_write_probe) failed — POST release returned HTTP ${gate3_http}, expected 201 (208 branch dropped per Kieran P1-4). Token may lack project:releases scope (Admin level required). Refs #3861." >&2
    exit 1
  fi
  curl -s --max-time 10 -X DELETE \
    -H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}" \
    "https://${api_host}/api/0/organizations/${SENTRY_ORG}/releases/${probe_ver}/" \
    -o /dev/null 2>/dev/null || true

  # Gate 4: audit_dsn_org_id_matches_token_org_id — extract `o<id>` from DSN
  # (e.g. `o4523123` from `https://k@o4523123.ingest.de.sentry.io/789`) and
  # compare to `.id` from Gate 1's org body. Catches destination-controllability
  # drift where the audit token's org-id and the runtime DSN's org-id diverge
  # (#3861 — originally framed as "phantom-ingest to unowned third-party org"
  # before the 2026-05-19 token-scope reframe; the gate remains useful as a
  # general DSN/token org-id-matches check regardless of ownership framing).
  #
  # `|| true` braces keep `set -o pipefail` happy when the DSN env is unset
  # (callers like `reusable-release.yml`'s release-time audit step do not
  # pass `NEXT_PUBLIC_SENTRY_DSN`). The `[[ -n "$dsn_org_id" && ... ]]` guard
  # below already handles empty `dsn_org_id` correctly — but without `|| true`
  # the pipeline itself fails before reaching the guard, exiting the script
  # with no visible error. Mirrors the same pattern on `dsn_cluster` below.
  dsn_org_id=$(printf '%s' "${NEXT_PUBLIC_SENTRY_DSN:-${SENTRY_DSN:-}}" \
    | { grep -oE 'o[0-9]+' || true; } | head -1 | tr -d 'o')
  token_org_id=$(jq -r '.id // empty' <<<"$gate1_body")
  if [[ -n "$dsn_org_id" && -n "$token_org_id" && "$dsn_org_id" != "$token_org_id" ]]; then
    echo "ERROR: Gate 4 (audit_dsn_org_id_matches_token_org_id) failed — DSN encodes org id ${dsn_org_id} but audit token authenticates against org id ${token_org_id}. Runtime DSN and audit token are pointing at different orgs (split-state). Refs #3861." >&2
    exit 1
  fi
fi

# --- DSN cluster + residency mismatch detector ----------------------------
# DSN cluster substring is the authoritative residency signal (per learning
# 2026-05-15-sentry-dsn-cluster-substring-authoritative-residency.md): the
# SDK ingests events at the cluster encoded in `NEXT_PUBLIC_SENTRY_DSN` /
# `SENTRY_DSN`, not at the API host the auditor happens to probe.
#
# Extract the cluster segment (e.g., `de` from
# `https://abc@o123.ingest.de.sentry.io/456`). Fail-closed default `us`
# covers bare `ingest.sentry.io` DSNs and missing-DSN envs (which means a
# DE-host probe against an unset DSN env will trip the mismatch detector
# below — the right failure mode for §5(2) accountability).
# `|| true` keeps `set -e` happy when the DSN env is unset or US-shaped
# (both `grep -oE` calls exit 1 on no-match). The fallback below resolves
# to `us`, which is the correct US-cluster default.
dsn_cluster=$(printf '%s' "${NEXT_PUBLIC_SENTRY_DSN:-${SENTRY_DSN:-}}" \
  | { grep -oE 'ingest\.[a-z0-9]{2,}\.sentry\.io' || true; } \
  | { grep -oE '\.[a-z0-9]{2,}\.' || true; } \
  | tr -d '.')
[[ -z "$dsn_cluster" ]] && dsn_cluster="us"

# Mismatch detector: if the region segment of the probed host differs from
# the DSN cluster, refuse to emit the audit artifact. The audit workflow's
# `set +e` + `::warning::` branch handles the non-zero exit gracefully (no
# `gh release upload`). Refs #3861.
#
# Host shapes:
#   `sentry.io`          → US legacy global (`host_region=us`)
#   `de.sentry.io`       → DE ingest (no /api/0/, but historically probed)
#   `eu.sentry.io`       → EU regional API (slug-less endpoints only)
#   `us.sentry.io`       → US regional API
#   `<org-slug>.sentry.io` → org-subdomain — region NOT encoded in host;
#                            the slug may or may not end in a region code.
#                            `host_region=""` and the comparison is skipped
#                            because there's no host-region signal to
#                            compare. The 4-gate block above already
#                            verified org-controllability against this
#                            host; the DSN's `ingest.<cluster>.sentry.io`
#                            substring remains the residency signal but
#                            the host-vs-DSN comparison is meaningless
#                            here (PR-β §10 / 2026-05-17).
#   Anything else        → unknown — pass through as-is.
case "$api_host" in
  sentry.io)    host_region="us" ;;
  de.sentry.io) host_region="de" ;;
  eu.sentry.io) host_region="eu" ;;
  us.sentry.io) host_region="us" ;;
  *.sentry.io)  host_region="" ;;  # org-subdomain — see comment block above
  *)            host_region="$api_host" ;;
esac
if [[ -n "$host_region" && "$host_region" != "$dsn_cluster" ]]; then
  echo "ERROR: residency mismatch — probed=${api_host} DSN cluster=${dsn_cluster} — refusing to emit audit artifact (refs #3861)" >&2
  exit 2
fi

# --- Fetch monitors (org-wide) -------------------------------------------
# Both fetches use curl_retry (not bare curl): a transient timeout here under
# `set -euo pipefail` would propagate curl's exit 28 and abort the whole audit
# step, which in the apply-sentry-infra.yml workflow SKIPS the plan+apply steps —
# a transient Sentry-EU blip silently darks the apply (observed on the #5325
# go-live: the #5380 apply failed exit 28 on this exact path and only succeeded
# on re-run). curl_retry always returns 0 (last attempt's output), so a genuine
# persistent failure surfaces at the JSON-shape validation below with a clear
# "response is not a JSON array" message + exit 1 — never a cryptic exit 28.
# Per-fetch metadata, so the shape check below can name WHICH fetch failed and
# against what URL. Without this the diagnostic cannot tell a 410 on the
# detectors path from a 500 on the workflows path.
declare -A FETCH_STATUS=()
declare -A FETCH_URL=()
declare -A FETCH_HDR=()

# Global-out, NOT stdout. This function mutates FETCH_* and LINK_UNFOLLOWED,
# so calling it as `x=$(sentry_fetch_collection …)` would run it in a subshell
# and silently discard every one of those mutations — a truncated sweep that
# still renders the clean-state string. Sets FETCH_BODY in the caller's shell.
FETCH_BODY=""
sentry_fetch_collection() {  # $1 label, $2 path after /api/0/
  local label="$1" path="$2"
  local page=1 body url qs=""
  # Accumulate pages in a FILE, never in an argv-passed variable.
  #
  # The previous form was `acc=$(jq -n --argjson a "$acc" --argjson b "$body" '$a + $b')`.
  # `--argjson` passes the whole accumulator as ONE argv entry, and Linux caps
  # a single entry at MAX_ARG_STRLEN (32 * 4096 = 131072 B) — a kernel constant
  # unrelated to ARG_MAX, so `getconf ARG_MAX` (2097152 here) gives no warning.
  # Measured: 128640 B accumulates fine, 134000 B dies with
  # `jq: Argument list too long` and rc=126.
  #
  # That fails UPSTREAM of the shape check, so it bypasses the entire
  # self-naming diagnostic this change exists to build — the operator gets one
  # cryptic line and no report. It also fires well below the advertised
  # MAX_PAGES ceiling: at realistic Sentry object sizes the real limit was a
  # few hundred rows, not 50 pages. `jq -s` reads the file directly, so no
  # argv is involved and the O(pages^2) re-serialisation goes away too.
  local pages_file="$AUDIT_SCRATCH/pages.$label"
  : > "$pages_file"
  local base="https://${api_host}/api/0/${path}?per_page=100"
  while :; do
    url="${base}${qs}"
    body=$(curl_retry -s --max-time 10 \
      -H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}" "$url")
    # Snapshot the shared last-header file under this label. Without the copy
    # the shape check below would read whichever fetch ran LAST, and would
    # report the wrong endpoint's deprecation headers against a failure.
    if ! cp -f "$CURL_LAST_HDR_FILE" "$AUDIT_SCRATCH/hdr.$label" 2>/dev/null; then
      # Silent here would make the diagnostic drop x-sentry-deprecation-date
      # and x-sentry-replacement-endpoint — the two fields the release caller
      # now tells the operator to read FIRST — and make "no deprecation
      # header" indistinguishable from "header lost".
      echo "::warning::could not snapshot response headers for ${label}; the failure diagnostic will omit deprecation headers." >&2
      : > "$AUDIT_SCRATCH/hdr.$label"
    fi
    FETCH_STATUS["$label"]="$(curl_retry_status)"
    FETCH_URL["$label"]="$url"
    FETCH_HDR["$label"]="$AUDIT_SCRATCH/hdr.$label"
    if ! jq -e 'type == "array"' >/dev/null 2>&1 <<<"$body"; then
      # Hand the raw body back untouched so the shape check can render the
      # self-naming diagnostic against it, then exit. There is deliberately no
      # "partial fetch" state: a failed collection means no report is written
      # at all, which is stronger than writing one that says it did not check.
      FETCH_BODY="$body"
      return 0
    fi
    printf '%s\n' "$body" >> "$pages_file"

    sentry_next_cursor "${FETCH_HDR[$label]}"
    [[ -z "$SENTRY_NEXT_CURSOR" ]] && break
    if (( page >= MAX_PAGES )); then
      echo "::warning::Sentry ${label} pagination hit the MAX_PAGES ceiling (${MAX_PAGES}); refusing to follow further cursors. This sweep is INCOMPLETE." >&2
      LINK_UNFOLLOWED=$(( LINK_UNFOLLOWED + 1 ))
      break
    fi
    page=$(( page + 1 ))
    # `&` not `?`: the base already carries per_page.
    qs="&cursor=${SENTRY_NEXT_CURSOR}"
  done
  FETCH_BODY=$(jq -c -s 'add // []' "$pages_file")
}

# Cursor-following is MANDATORY for monitors and detectors, not optional.
# `detectors/` grows 1:1 with cron monitors (55 of 62 rows are
# monitor_check_in_failure) and monitors went 8 -> 49 -> 55 in two months, so a
# loud-fail-on-truncation arm would, by ordinary growth, fail this audit BEFORE
# the terraform plan step in apply-sentry-infra.yml — the only path that
# deploys the fix. That is the same "detector blocks its own cure" deadlock the
# Class D state-half comment spends twenty lines avoiding. Monitors additionally
# feed Class D, the only class with teeth, where silent truncation fails OPEN on
# unreclaimable spend.
fetch_monitors() {
  if [[ -n "${SENTRY_FIXTURE_MONITORS:-}" ]]; then
    FETCH_BODY="$(cat "$SENTRY_FIXTURE_MONITORS")"
    return
  fi
  sentry_fetch_collection monitors "organizations/${SENTRY_ORG}/monitors/"
}

# Issue-alert routing. `projects/{org}/{proj}/rules/` -> `organizations/{org}/workflows/`
# per Sentry's own x-sentry-replacement-endpoint header. The replacement is
# ORG-scoped, so the old SENTRY_PROJECT branch has no reason to exist and is
# gone; SENTRY_PROJECT still feeds Gates 2 and 3 and the report frontmatter.
fetch_workflows() {
  if [[ -n "${SENTRY_FIXTURE_RULES:-}" ]]; then
    FETCH_BODY="$(cat "$SENTRY_FIXTURE_RULES")"
    return
  fi
  sentry_fetch_collection workflows "organizations/${SENTRY_ORG}/workflows/"
}

# Alert definitions. `organizations/{org}/alert-rules/` -> `.../detectors/`,
# again per Sentry's own header — a DIFFERENT successor than workflows/.
#
# Fixture inheritance: when a test supplies the monitors/workflows fixtures but
# not this one, serve `[]` rather than reaching the network. Without it every
# pre-existing test (which sets only MONITORS+RULES) would start making live
# calls and go red.
fetch_detectors() {
  if [[ -n "${SENTRY_FIXTURE_DETECTORS:-}" ]]; then
    FETCH_BODY="$(cat "$SENTRY_FIXTURE_DETECTORS")"
    return
  fi
  if [[ -n "${SENTRY_FIXTURE_MONITORS:-}" || -n "${SENTRY_FIXTURE_RULES:-}" ]]; then
    # Hermetic default for the tests that predate detectors. Test-injection
    # only: SENTRY_FIXTURE_* are never set in production (see the header), so
    # this branch cannot fire on a real run.
    FETCH_BODY='[]'
    return
  fi
  sentry_fetch_collection detectors "organizations/${SENTRY_ORG}/detectors/"
}

fetch_monitors;  monitors_json="$FETCH_BODY"
fetch_workflows; rules_json="$FETCH_BODY"
fetch_detectors; detectors_json="$FETCH_BODY"

# Validate JSON shape; fail closed on garbage.
#
# The diagnostic must NAME ITS OWN CAUSE. Before #7590 every one of these
# failure modes rendered as the identical `<label> response is not a JSON
# array` line: a brownout 410, a scope failure, an empty project and an
# exhausted 5xx retry were indistinguishable, and that ambiguity is what made
# the original investigation spend a full session and reach the wrong
# conclusion. Emit status, host, URL, the deprecation headers when present, and
# a VERDICT — because "5xx exhausted" (re-run) and "410 deprecated" (migrate)
# need different next actions.
for label in monitors workflows detectors; do
  case "$label" in
    monitors)  payload="$monitors_json" ;;
    workflows) payload="$rules_json" ;;
    detectors) payload="$detectors_json" ;;
  esac
  if ! jq -e 'type == "array"' >/dev/null 2>&1 <<<"$payload"; then
    status="${FETCH_STATUS[$label]:-unknown}"
    url="${FETCH_URL[$label]:-unknown}"
    hdr="${FETCH_HDR[$label]:-}"
    dep=""; repl=""
    if [[ -n "$hdr" && -s "$hdr" ]]; then
      dep=$( { grep -iE '^x-sentry-deprecation-date:' "$hdr" 2>/dev/null || true; } | tail -1 | tr -d '\r' | awk '{print $2}')
      repl=$( { grep -iE '^x-sentry-replacement-endpoint:' "$hdr" 2>/dev/null || true; } | tail -1 | tr -d '\r' | awk '{print $2}')
    fi
    case "$status" in
      410) verdict="endpoint is GONE (deprecation brownout or post-sunset removal) — MIGRATE to the replacement below; re-running will not help" ;;
      401|403) verdict="token rejected — check SENTRY_AUTH_TOKEN scopes (note: sentry-audit-gate.yml feeds SENTRY_IAC_AUTH_TOKEN into this var)" ;;
      404) verdict="endpoint or org/project not found at this host — check SENTRY_API_HOST and SENTRY_ORG" ;;
      429|5*) verdict="transient upstream failure, retries exhausted — RE-RUN" ;;
      *) verdict="unclassified — inspect the body head below" ;;
    esac
    {
      echo "ERROR: ${label} response is not a JSON array"
      echo "  http_status:  ${status:-none}"
      echo "  api_host:     ${api_host}"
      echo "  url:          ${url}"
      echo "  fetch:        ${label}"
      [[ -n "$dep" ]]  && echo "  x-sentry-deprecation-date:    ${dep}"
      [[ -n "$repl" ]] && echo "  x-sentry-replacement-endpoint: ${repl}"
      echo "  verdict:      ${verdict}"
      echo "  body (first 500 bytes):"
    } >&2
    # NOT `printf … | head -c 500`: once the payload exceeds the 64 KiB pipe
    # buffer, head exits, printf takes SIGPIPE, and under `set -o pipefail`
    # the pipeline returns 141 — which `set -e` raises BEFORE the `exit 1`
    # below. The plan declares the non-zero exit as the load-bearing signal,
    # and 141 vs 1 is a distinction a caller keying on exit codes gets wrong.
    # Parameter expansion needs no subprocess and cannot SIGPIPE.
    printf '%s\n' "${payload:0:500}" >&2
    echo "  --- end body ---" >&2
    exit 1
  fi
done

# Deprecation escalation (Decision 5). Warned above on every response; fails
# only once the date is inside the window. After this migration the target
# endpoints carry no deprecation headers at all, so this is dormant unless
# Sentry deprecates one of them too.
if [[ -s "$DEPRECATION_FATAL_FILE" ]] && [[ "$DEPRECATION_FAIL_ENABLED" == "1" ]]; then
  echo "ERROR: a Sentry endpoint this audit depends on is deprecated and its date is within ${DEPRECATION_FAIL_WINDOW_DAYS} days (or already past). This caller opted into escalation via SENTRY_DEPRECATION_FAIL=1; widen the window with SENTRY_DEPRECATION_FAIL_WINDOW_DAYS only if the endpoint has no shipped replacement yet. Refs #7590." >&2
  echo "  affected endpoints (endpoint deprecation-date):" >&2
  sort -u "$DEPRECATION_FATAL_FILE" | sed 's/^/    /' >&2
  exit 1
elif [[ -s "$DEPRECATION_FATAL_FILE" ]]; then
  echo "::warning::A Sentry endpoint this audit depends on is deprecated and its date is within ${DEPRECATION_FAIL_WINDOW_DAYS} days (or already past). NOT failing: this caller has not set SENTRY_DEPRECATION_FAIL=1. Affected:" >&2
  sort -u "$DEPRECATION_FATAL_FILE" | sed 's/^/    /' >&2
fi

# --- Compute orphans ------------------------------------------------------
# REMAPPED IN #7590 onto the binding that actually exists.
#
# The old jq targeted `monitor.slug` keys inside rule `.conditions[]`/
# `.filters[]`. Measured against the live org: that binding matches 0 rows and
# 0 of 55 monitor slugs appear anywhere in the rules payload. It did not fail
# to survive the API migration — IT NEVER MATCHED. Class A has therefore
# flagged every monitor in the org since the day it shipped.
#
# The real routing graph is: monitor <- (name) - cron detector -(workflowIds)-> workflow.
#
# Class A: `monitor_check_in_failure` detector whose `workflowIds` is empty
#          (a monitor whose failures route nowhere).
# Class B: cron detector naming a monitor that does not exist live.
# Class C: workflow with no actions at all across triggers + actionFilters
#          (paging route silently removed via the Sentry UI).
#
# Detectors carry NO `slug` field — the binding is `.name`, which Sentry
# slugifies to the monitor slug. Every cron monitor in this root already uses a
# kebab-case name, so slugification is the identity; the same relation the
# Class D block below relies on, verified live: 55 detector names, 55 monitor
# slugs, exact set match in both directions.

# `sort -u`: pagination concatenates pages, and Sentry's offset cursors shift
# under concurrent mutation — a monitor deleted between page N and N+1 repeats
# a row. Undeduped, that double-counts Class D and doubles the dollar figure
# rendered into the Article 30 artifact. (Unreachable before this change: a
# single unpaginated page cannot repeat a slug.)
monitor_slugs=$(jq -r '.[].slug // empty' <<<"$monitors_json" | sort -u)

# A synthetic `[]` (the hermetic default for tests that predate detectors) is
# NOT evidence of a clean org and must not be reported as one. This is the only
# state that can reach here: a FAILED fetch never gets this far, because the
# shape check above exits first and writes no report.
detectors_evaluated=1
if [[ -z "${SENTRY_FIXTURE_DETECTORS:-}" ]] \
   && [[ -n "${SENTRY_FIXTURE_MONITORS:-}" || -n "${SENTRY_FIXTURE_RULES:-}" ]]; then
  detectors_evaluated=0
fi

cron_detectors=$(jq -c '[ .[] | select(.type == "monitor_check_in_failure") ]' <<<"$detectors_json")
cron_detector_count=$(jq 'length' <<<"$cron_detectors")

# Monitor binding: STRUCTURED pass first, substring-free FALLBACK second.
#
# `dataSources[].queryObj.slug` is the real binding — an actual slug field on
# the data source the detector watches. `.name` is a display name that Sentry
# happens to slugify to the same value; verified live, both give an exact 55/55
# set match against the live monitors AND are identical to each other today.
# They are NOT the same thing: renaming a detector in the UI moves `.name` and
# leaves `queryObj.slug` alone, so preferring the display name would invent a
# Class B orphan out of a cosmetic edit.
#
# The fallback is only consulted when the structured pass yields NOTHING, which
# preserves the "structured first, fall back once" safety property the old
# code had (rebased onto the new schema — the old fallback was a substring
# sweep over a serialized payload, which has no meaning here). The
# structured-pass count is emitted into the report so that "the structured pass
# found it" is distinguishable from "the fallback found it"; without that the
# property is unverifiable by any fixture.
# PER-DETECTOR, not all-or-nothing. An earlier revision only fell back when the
# structured pass returned ZERO across the whole payload, which is silently
# wrong under a PARTIAL rollout: if Sentry ships queryObj.slug on some cron
# detectors and not others, the count is non-zero, the fallback never engages,
# and every detector WITHOUT the structured field drops out of the set — so
# Class B under-reports a real orphan with no signal anywhere. Resolving per
# detector removes that state by construction rather than warning about it.
cron_detector_slugs=$(jq -r '.[] | (.dataSources[]?.queryObj.slug // .name // empty)' <<<"$cron_detectors" | sort -u)
# `select(.dataSources[]?.queryObj.slug)` emits the input ONCE PER truthy
# value, so one detector with two structured data sources counts as 2 — the
# report could print `MIXED — 2/1 structured`, which discredits the very
# counter that exists to make the binding auditable. `any(...)` collapses it.
structured_slug_count=$(jq '[ .[] | select(any(.dataSources[]?; .queryObj.slug)) ] | length' <<<"$cron_detectors")
if (( structured_slug_count == cron_detector_count )) && (( cron_detector_count > 0 )); then
  binding_source="structured (dataSources[].queryObj.slug) for all ${cron_detector_count}"
elif (( structured_slug_count == 0 )); then
  binding_source="fallback (.name) for all ${cron_detector_count} — no detector carries a structured slug"
else
  binding_source="MIXED — ${structured_slug_count}/${cron_detector_count} structured, remainder via .name"
fi
cron_detector_names="$cron_detector_slugs"

# Fail-closed extraction guard, carried from Class D's declared_slugs check.
# Under the OLD predicate an auth/scope/endpoint regression returning `[]`
# produced a loud artifact (all 55 flagged). Under the new one it would produce
# zero orphans, a clean report and exit 0 — a quiet, green, WRONG answer. Zero
# cron detectors against a non-empty live monitor list is an extraction
# failure, not a clean org.
if (( detectors_evaluated == 1 )) \
   && [[ "$cron_detector_count" == "0" ]] \
   && [[ "$(jq 'length' <<<"$monitors_json")" != "0" ]]; then
  echo "ERROR: zero \`monitor_check_in_failure\` detectors parsed from ${FETCH_URL[detectors]:-the detectors endpoint} while the API returned live monitors — orphan extraction is broken; refusing to emit a clean report that checked nothing. Refs #7590." >&2
  exit 1
fi

orphan_alerts=()          # Class B
empty_action_rule_ids=()  # Class C
class_a_count=0
class_a_unrouted=0

# Class A — cron detectors whose failures route to no workflow.
#
# Reported as a COUNT plus a machine-checked invariant, not a per-slug list.
# 55 bullets on every run is noise, and the report's `## Monitors` table
# already names every slug. The INVARIANT is the signal: a literal baseline of
# 55 goes stale the moment monitor 56 lands and cannot distinguish ordinary
# growth from a real routing attachment (54) from an extraction failure (0).
# `class_a_count == cron_detector_count` distinguishes all three, and it lives
# in the suite — where something actually reads it — rather than as prose in an
# ADR nothing reads.
if (( detectors_evaluated == 1 )); then
  class_a_unrouted=$(jq '[ .[] | select(((.workflowIds // []) | length) == 0) ] | length' <<<"$cron_detectors")
  class_a_count="$class_a_unrouted"
fi

# Class B — a cron detector naming a monitor that does not exist live.
# `cron_detector_slugs` is slug-first with a `.name` fallback (see the binding
# block above). The slug-shape guard stays, but a discard is now COUNTED and
# surfaced: silently dropping a non-slug-shaped binding is a fail-open on
# exactly the event Class B exists to catch. The guard's premise is that
# `.name` slugifies to the monitor slug — so the trigger for a non-slug-shaped
# value is not a hypothetical Sentry change, it is a human renaming a detector
# in the UI to "Nightly Backup Check", which is precisely when that detector's
# monitor binding is most likely to be broken.
class_b_discarded=0
if (( detectors_evaluated == 1 )); then
  monitor_slug_set=$(printf '%s\n' "$monitor_slugs" | sort -u)
  while IFS= read -r ref; do
    [[ -z "$ref" ]] && continue
    if ! [[ "$ref" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
      class_b_discarded=$(( class_b_discarded + 1 ))
      echo "::warning::cron detector binding '${ref}' is not slug-shaped; Class B cannot be evaluated for it (a UI rename produces exactly this)." >&2
      continue
    fi
    if ! printf '%s\n' "$monitor_slug_set" | grep -qFx -- "$ref"; then
      orphan_alerts+=("$ref")
    fi
  done <<<"$cron_detector_names"
fi

# Class C — workflows with no actions anywhere.
# Workflow routing lives in TWO places and a workflow needs only one of them:
# `.triggers.actions[]` (an OBJECT, not an array — verified live) and
# `.actionFilters[].actions[]`. Checking only one would flag every workflow
# that routes via the other, drowning real orphans — the same defect the old
# Metric-Alert shape branch existed to avoid.
while IFS= read -r rid; do
  [[ -z "$rid" ]] && continue
  empty_action_rule_ids+=("$rid")
done < <(jq -r '
  .[] | select(
    (([.triggers.actions[]?] + [.actionFilters[]?.actions[]?]) | length) == 0
  ) | .id | tostring
' <<<"$rules_json")

# --- Class D: live monitor with no declaring .tf resource block -----------
# The live→IaC direction (A/B/C all run IaC→live or live→live). Since #6589
# deleted the `-target=` allow-list from apply-sentry-infra.yml, the plan runs
# against the FULL ROOT — so an undeclared live monitor is no longer a
# harmless bookkeeping gap: it is spend Terraform will never reclaim, because
# only a resource that once existed in the config can be destroyed by removing
# it. Live monitors grew 8 → 49 → 55 and never decreased while
# deletion was a silent no-op; each undeclared monitor bills $0.78/mo forever.
#
# Slug↔declaration relation: Sentry derives the monitor slug by slugifying the
# resource's `name`. Every `sentry_cron_monitor` in this root already sets a
# kebab-case `name`, so slugification is the identity and `name` == live slug
# — re-verified 2026-08-19 against the live org: 55 `resource
# "sentry_cron_monitor"` blocks, 55 `name =` attributes, 55 live monitors,
# exact set match in both directions. (This comment read 49 until #7590; the
# figure had gone stale while reading as "verified".) Re-derive rather than
# trusting it:  grep -c '^resource "sentry_cron_monitor"' ../infra/sentry/*.tf
CRON_MONITOR_MONTHLY_USD="0.78"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tf_dir="${SENTRY_TF_DIR:-${script_dir}/../infra/sentry}"

# TR3: liveness comes from `environments[].lastCheckIn`, NOT a top-level
# `.lastCheckIn`. The list endpoint has NO top-level lastCheckIn field, so
# `.[].lastCheckIn` reads `null` for every monitor and reports the whole org
# as never-checked-in (the 2026-07-17 research agent hit exactly this: it
# claimed 50 never-checked-in; the true count was 2). A monitor carries one
# entry per environment, each with its own check-in, so the newest across
# environments is the monitor's liveness. `max` over the empty array yields
# null → the `never` sentinel; an empty field would make the marker below
# unparseable for any consumer splitting on `=`.
monitor_last_checkin() {
  jq -r --arg s "$1" '
    [ .[] | select(.slug == $s) | .environments[]?.lastCheckIn // empty ] | max // "never"
  ' <<<"$monitors_json"
}

monitor_created() {
  jq -r --arg s "$1" '
    [ .[] | select(.slug == $s) | .dateCreated // empty ] | first // "unknown"
  ' <<<"$monitors_json"
}

orphan_live_monitors=()   # Class D — live, undeclared, AND not in state (unreclaimable)
class_d_unresolved=()     # live + undeclared, but state unknown -> cannot classify
class_d_state_unknown=0
# Class D compares two halves — the live monitor list and the .tf root that
# declares it. A synthetic monitor list judged against the REAL tf root makes
# every fixture slug "undeclared" by construction: noise, not a finding. So the
# comparison runs only when both halves agree on their source. Same skip
# predicate the 4-gate block above uses, and it cannot fail open in production:
# SENTRY_FIXTURE_MONITORS is test-injection only (see the header), so with it
# unset the gate always runs; a fixture run that supplies SENTRY_TF_DIR pairs
# coherently and gets the full gate.
if [[ -z "${SENTRY_FIXTURE_MONITORS:-}" || -n "${SENTRY_TF_DIR:-}" ]]; then
  if [[ ! -d "$tf_dir" ]]; then
    echo "ERROR: Sentry Terraform root not found at ${tf_dir} — cannot prove any live monitor is declared, and flagging all of them as Class D would be a false positive. Refs #6589." >&2
    exit 1
  fi

  # Anchor on the declaration construct, NOT a bare slug grep. These .tf files
  # name monitor slugs in prose comments (e.g. the CLAUDE-EVAL COHORT block
  # lists 12 of them), so `grep -F "$slug" *.tf` matches a comment and silently
  # suppresses a real orphan. Scoping to the `sentry_cron_monitor` block header
  # also keeps `name =` from a sibling `sentry_issue_alert` / `sentry_uptime_
  # monitor` block (both carry kebab-case names in this same root) from being
  # read as a cron declaration. `in_block` clears on the first `name =` so a
  # nested block's attribute cannot leak in either.
  declared_slugs=$(awk '
    /^resource[[:space:]]+"sentry_cron_monitor"[[:space:]]/ { in_block=1; next }
    in_block && /^[[:space:]]*name[[:space:]]*=[[:space:]]*"/ {
      if (match($0, /"[^"]*"/)) { print substr($0, RSTART+1, RLENGTH-2); in_block=0 }
    }
    in_block && /^}/ { in_block=0 }
  ' "$tf_dir"/*.tf | sort -u)

  # Zero declarations parsed against a non-empty live org means the anchor broke
  # (e.g. a reformat moved `resource` off column 0), not that every monitor is
  # orphaned. Erroring here is still fail-closed, but it names the real defect
  # instead of flooding the operator with one bogus orphan per live monitor.
  if [[ -z "$declared_slugs" && "$(jq 'length' <<<"$monitors_json")" != "0" ]]; then
    echo "ERROR: no sentry_cron_monitor declarations parsed from ${tf_dir}/*.tf while the API returned live monitors — Class D extraction is broken; refusing to report every live monitor as an orphan. Refs #6589." >&2
    exit 1
  fi

  # ── The state half — load-bearing, and NOT an optimisation ────────────────
  # Class D means "Terraform can never reclaim this". `live AND not declared` is
  # NOT that set: a monitor that is IN STATE with no remaining .tf block is a
  # PENDING DESTROY — the very next full-root apply reclaims it. That is #6589's
  # fix working, not an orphan.
  #
  # Getting this wrong DEADLOCKS the apply. apply-sentry-infra.yml runs this
  # audit BEFORE `terraform plan` (a deliberate gate-call-graph ordering, so the
  # workflow_dispatch path cannot bypass the 4-gate check). So a Class D that
  # fires on a pending destroy fails the job before the plan runs, the destroy
  # never happens, the monitor stays live and billing — and the detector has
  # recreated the exact #6074 end state it exists to prevent, by blocking its own
  # cure. This is not hypothetical: at the time of writing, live=50 declared=49,
  # and the one difference is scheduled-ghcr-token-minter — precisely the orphan
  # #6589 destroys.
  #
  # SENTRY_STATE_SLUGS carries the slugs Terraform tracks (see the header for the
  # producer). Absent, the two cases are INDISTINGUISHABLE from here, so the
  # candidates are reported without failing: failing on a set we cannot resolve
  # is what causes the deadlock, and a gate that cannot be correct should not be
  # the one with teeth. The authoritative fail-closed run is
  # apply-sentry-infra.yml, which inits Terraform first and injects the state
  # half — the caller that can actually know.
  # SENTRY_STATE_REQUIRED=1 lets the authoritative caller DECLARE its own
  # contract. Without it, deleting the workflow's `export
  # SENTRY_STATE_SLUGS_FILE=...` line silently degrades this gate from
  # fail-closed to warn — a green apply that checked nothing, invisible to
  # review. That is a prose-documented invariant with no mechanical check, in a
  # PR whose entire thesis is that those get forgotten.
  if [[ "${SENTRY_STATE_REQUIRED:-0}" == "1" && -z "${SENTRY_STATE_SLUGS_FILE:-}" ]]; then
    echo "ERROR: SENTRY_STATE_REQUIRED=1 but SENTRY_STATE_SLUGS_FILE is unset — this caller declared that it injects Terraform state, and it did not. Refusing to degrade to the warn path: that would silently turn the Class D gate into a green that checked nothing. Refs #6589." >&2
    exit 1
  fi

  state_known=0
  state_slugs=""
  if [[ -n "${SENTRY_STATE_SLUGS_FILE:-}" ]]; then
    if [[ ! -f "$SENTRY_STATE_SLUGS_FILE" ]]; then
      echo "ERROR: SENTRY_STATE_SLUGS_FILE is set to '${SENTRY_STATE_SLUGS_FILE}' but no such file exists. Refusing to silently fall back to the state-unknown warn path — the caller believes it provided state. Refs #6589." >&2
      exit 1
    fi
    state_known=1
    state_slugs=$(grep -vE '^[[:space:]]*$' "$SENTRY_STATE_SLUGS_FILE" | sort -u || true)

  fi

  class_d_candidates=()
  while IFS= read -r slug; do
    [[ -z "$slug" ]] && continue
    printf '%s\n' "$declared_slugs" | grep -qFx -- "$slug" && continue
    class_d_candidates+=("$slug")
  done <<<"$monitor_slugs"

  if (( state_known == 1 )); then
    for slug in ${class_d_candidates[@]+"${class_d_candidates[@]}"}; do
      # In state => Terraform WILL reclaim it on the next apply => not Class D.
      printf '%s\n' "$state_slugs" | grep -qFx -- "$slug" && continue
      orphan_live_monitors+=("$slug")
    done
  else
    class_d_state_unknown=1
    class_d_unresolved=( ${class_d_candidates[@]+"${class_d_candidates[@]}"} )
  fi
fi

# --- Resolve report path --------------------------------------------------
# AUDIT_DATE_OVERRIDE is honored by the test suite to defeat the midnight
# UTC race in T4 idempotency (3 invocations crossing the date boundary
# would produce 2 reports). Production callers should leave it unset.
date_iso="${AUDIT_DATE_OVERRIDE:-$(date -u '+%Y-%m-%d')}"
out_dir="${AUDIT_OUT_DIR:-knowledge-base/legal/audits}"
mkdir -p "$out_dir"
out_file="${out_dir}/sentry-migration-audit-${date_iso}.md"

# --- Render report (overwrite, idempotent per-day) ------------------------
{
  printf '# Sentry Monitors/Alerts Migration Audit\n\n'
  printf -- '- **Date (UTC):** %s\n' "$date_iso"
  printf -- '- **Sentry org:** %s\n' "$SENTRY_ORG"
  printf -- '- **Probed host:** %s\n' "$api_host"
  printf -- '- **DSN cluster:** %s\n' "$dsn_cluster"
  # The fetches are ORG-scoped since #7590, so naming SENTRY_PROJECT as the
  # filter would assert a scope the fetch no longer applies. SENTRY_PROJECT
  # still scopes Gates 2 and 3, which is what this now says.
  printf -- '- **Alert scope:** org-wide (`workflows/` + `detectors/` are org-scoped)\n'
  printf -- '- **Gate project:** %s\n' "${SENTRY_PROJECT:-<none>}"
  # Provenance: a future reader diffing the committed report series must be
  # able to see that the PREDICATE changed rather than the org (Class A goes
  # 8/8 -> 55/55 across this change under a different definition).
  printf -- '- **Source endpoints:** `organizations/{org}/monitors/`, `organizations/{org}/workflows/`, `organizations/{org}/detectors/`\n'
  printf -- '- **Orphan predicate generation:** 2 (#7590 — Class A/B rebound onto cron detectors; generation 1 keyed on `monitor.slug`, which never matched)\n'
  printf -- '- **Class D state half:** %s\n' \
    "$( (( class_d_state_unknown == 1 )) && echo "absent — Class D unresolved" || echo "injected" )"
  printf -- '- **Enumeration complete:** %s\n\n' "$( (( LINK_UNFOLLOWED == 0 )) && echo yes || echo "NO — ${LINK_UNFOLLOWED} unfollowed cursor(s)")"

  printf '## Monitors\n\n'
  if [[ "$(jq 'length' <<<"$monitors_json")" == "0" ]]; then
    printf '_No monitors returned by the API._\n\n'
  else
    printf '| slug | name | type | schedule |\n'
    printf '|---|---|---|---|\n'
    jq -r '.[] | [.slug, .name, .type, (.config.schedule // "")] | @tsv' <<<"$monitors_json" | \
      while IFS=$'\t' read -r slug name typ sched; do
        printf '| %s | %s | %s | %s |\n' "$slug" "$name" "$typ" "$sched"
      done
    printf '\n'
  fi

  printf '## Workflows (issue-alert routing)\n\n'
  if [[ "$(jq 'length' <<<"$rules_json")" == "0" ]]; then
    printf '_No workflows returned by the API._\n\n'
  else
    printf '| id | name |\n'
    printf '|---|---|\n'
    # `// ""` guards a null name column — the workflows shape is not the rules
    # shape, and a bare `.name` would render a literal `null` cell.
    jq -r '.[] | [(.id|tostring), (.name // "")] | @tsv' <<<"$rules_json" | \
      while IFS=$'\t' read -r id name; do
        printf '| %s | %s |\n' "$id" "$name"
      done
    printf '\n'
  fi

  printf '## Detectors (alert definitions)\n\n'
  if (( detectors_evaluated == 0 )); then
    printf '_Not evaluated — the detectors payload was not obtained on this run._\n\n'
  elif [[ "$(jq 'length' <<<"$detectors_json")" == "0" ]]; then
    printf '_No detectors returned by the API._\n\n'
  else
    printf -- '- Cron detectors (`monitor_check_in_failure`): %s\n' "$cron_detector_count"
    printf -- '- Total detectors: %s\n' "$(jq 'length' <<<"$detectors_json")"
    # Emitted so a fallback activation is VISIBLE rather than silent — without
    # it, "the structured pass found the binding" and "the fallback did" are
    # indistinguishable in the artifact and no fixture can tell them apart.
    printf -- '- Monitor binding: %s — %s slug(s) from the structured pass\n\n' \
      "$binding_source" "$structured_slug_count"
  fi

  printf '## Orphans\n\n'
  total_orphans=$(( class_a_count + ${#orphan_alerts[@]} + ${#empty_action_rule_ids[@]} + ${#orphan_live_monitors[@]} ))
  # The clean-state string is suppressed whenever anything went unmeasured.
  # Collapsing "could not check" into "clean" in an Article 30 evidence
  # artifact is the exact failure mode this whole change exists to remove.
  if (( detectors_evaluated == 0 )); then
    printf 'Classes A and B **NOT EVALUATED** — the detectors payload was not obtained on this run, so no statement is made about monitor routing. Classes C and D below were evaluated.\n\n'
  elif [[ -s "$DEPRECATION_FATAL_FILE" ]]; then
    printf 'An endpoint this audit reads is **DEPRECATED and inside the escalation window** (see `## Endpoint deprecation`). The orphan classes below were computed from data served by a sunsetting endpoint, so no clean verdict is issued.\n\n'
  elif (( class_b_discarded > 0 )); then
    printf 'Class B **PARTIALLY EVALUATED** — %d cron detector binding(s) were not slug-shaped and could not be resolved to a monitor. A UI rename produces exactly this, and it is the event Class B exists to catch, so no clean verdict is issued.\n\n' \
      "$class_b_discarded"
  elif (( class_d_state_unknown == 1 )) && (( ${#class_d_unresolved[@]} > 0 )); then
    # Class D is the class with teeth (unreclaimable spend) and it is the one
    # the clean string used to assert hardest. Without the Terraform state half
    # a live-but-undeclared monitor is UNRESOLVED, not clean — and passing no
    # state half is the DEFAULT for two of the three callers, including the one
    # that uploads this file as the Article 30 release asset. So the artifact
    # was asserting "D … clean" in the only configuration where D cannot be
    # measured. Enumerate the candidates here rather than only on stderr.
    printf 'Class D **NOT EVALUATED** — %d live monitor(s) have no declaring `.tf` block, but Terraform state was not provided, so a pending destroy cannot be told from an unreclaimable orphan. Classes A, B and C below were evaluated.\n\n' \
      "${#class_d_unresolved[@]}"
    printf '_Class D candidates (unresolved):_\n\n'
    for slug in "${class_d_unresolved[@]}"; do
      printf -- '- `%s`\n' "$slug"
    done
    printf '\n'
  elif (( LINK_UNFOLLOWED > 0 )); then
    printf 'Enumeration was **INCOMPLETE** (%d unfollowed cursor(s)), so no clean verdict is issued: an unenumerated page can hold an orphan of any class.\n\n' "$LINK_UNFOLLOWED"
  elif (( total_orphans == 0 )); then
    printf 'No orphans detected. All four classes (A: cron detector with no routing workflow; B: cron detector naming a missing monitor; C: workflow with no actions; D: live monitor with no .tf declaration) are clean.\n\n'
  fi

  if (( ${#orphan_alerts[@]} > 0 )); then
    printf '_Class B (cron detector naming a monitor that does not exist):_\n\n'
    for ref in "${orphan_alerts[@]}"; do
      printf -- '- `%s` — a cron detector is named for this monitor; no monitor with this slug exists.\n' "$ref"
    done
    printf '\n**Remediation:** Sentry split likely deleted the monitor; either delete the dangling detector via API or re-create the monitor in `cron-monitors.tf`.\n\n'
  fi

  if (( ${#empty_action_rule_ids[@]} > 0 )); then
    printf '_Class C (workflow with no actions — paging route silently removed):_\n\n'
    for rid in "${empty_action_rule_ids[@]}"; do
      printf -- '- workflow id `%s` — no actions across `triggers` or `actionFilters`; breaches will fire no notification.\n' "$rid"
    done
    printf '\n**Remediation:** restore the action target via the Sentry UI (re-add NotifyEmailAction Team or IssueOwners). The Terraform `actions_v2 lifecycle.ignore_changes` posture means TF cannot self-heal this — UI fix is the only path.\n\n'
  fi

  if (( detectors_evaluated == 1 )); then
    printf '_Class A (cron detector with no routing workflow):_\n\n'
    printf -- '- **%s** of **%s** cron detectors have an empty `workflowIds`.\n' \
      "$class_a_count" "$cron_detector_count"
    if (( class_a_count == cron_detector_count )) && (( cron_detector_count > 0 )); then
      printf -- '- Invariant `class_a_count == cron_detector_count` HOLDS: no cron monitor in this org routes through a workflow. This is a true statement about the org, not a detection bug.\n'
    elif (( cron_detector_count > 0 )); then
      # The interesting state. Without this branch the invariant line simply
      # DISAPPEARS when routing changes, so the one transition worth noticing
      # is the one the report goes quiet about.
      printf -- '- Invariant `class_a_count == cron_detector_count` DOES NOT HOLD: %s of %s cron detectors now route through a workflow. Routing changed since the last report — confirm it was intended.\n' \
        "$(( cron_detector_count - class_a_count ))" "$cron_detector_count"
    fi
    printf -- '\n_Not enumerated per-slug by design: every slug already appears in the `## Monitors` table above, and %s identical bullets per run is noise. The machine-checked invariant lives in `sentry-monitors-audit.test.sh`._\n\n' "$cron_detector_count"
  fi

  if (( ${#orphan_live_monitors[@]} > 0 )); then
    printf '_Class D (live monitor with no declaring `.tf` resource block):_\n\n'
    printf '| slug | created | last check-in | cost/mo (USD) |\n'
    printf '|---|---|---|---|\n'
    for slug in "${orphan_live_monitors[@]}"; do
      printf '| `%s` | %s | %s | %s |\n' \
        "$slug" "$(monitor_created "$slug")" "$(monitor_last_checkin "$slug")" "$CRON_MONITOR_MONTHLY_USD"
    done
    printf '\n**Monthly spend on undeclared monitors:** $%s (%d × $%s).\n\n' \
      "$(printf '%s %s' "${#orphan_live_monitors[@]}" "$CRON_MONITOR_MONTHLY_USD" | awk '{printf "%.2f", $1 * $2}')" \
      "${#orphan_live_monitors[@]}" "$CRON_MONITOR_MONTHLY_USD"
    printf '**Remediation:** these monitors exist only in Sentry. Terraform cannot destroy a resource it never declared, so `terraform apply` will NOT reclaim them. Either add a `sentry_cron_monitor` block to `%s` (adopt via `terraform import`) or delete the monitor via the Sentry API. Refs #6589.\n\n' \
      "apps/web-platform/infra/sentry/cron-monitors.tf"
  fi

  # The deprecation finding must reach the DURABLE artifact, not only a job
  # log. The report is the Article 30 evidence and, as a release asset, is
  # retained indefinitely against GHA's 90 days — and on two of three callers
  # the escalation deliberately does NOT fail, so without this section the only
  # record of "this data came off a sunsetting endpoint" lives in a green job's
  # scrollback. LINK_UNFOLLOWED already gets this treatment; deprecation did not.
  if [[ -s "$DEPRECATION_FATAL_FILE" ]] || [[ -s "$DEPRECATION_SEEN_FILE" ]]; then
    printf '## Endpoint deprecation\n\n'
    if [[ -s "$DEPRECATION_SEEN_FILE" ]]; then
      printf '_Endpoints that returned a deprecation header on this run:_\n\n'
      while IFS= read -r ep; do
        [[ -z "$ep" ]] && continue
        printf -- '- `%s`\n' "$ep"
      done < <(sort -u "$DEPRECATION_SEEN_FILE")
      printf '\n'
    fi
    if [[ -s "$DEPRECATION_FATAL_FILE" ]]; then
      printf '_Inside the %s-day escalation window (endpoint — deprecation date):_\n\n' \
        "$DEPRECATION_FAIL_WINDOW_DAYS"
      while IFS= read -r row; do
        [[ -z "$row" ]] && continue
        printf -- '- `%s`\n' "$row"
      done < <(sort -u "$DEPRECATION_FATAL_FILE")
      printf '\n**Escalation posture on this run:** %s\n\n' \
        "$( [[ "$DEPRECATION_FAIL_ENABLED" == "1" ]] && echo 'ENABLED — this run exits non-zero' || echo 'warn-only (SENTRY_DEPRECATION_FAIL unset) — this run exits 0' )"
    fi
  fi

  printf '## DPA evidence\n\n'
  printf 'Vendor DPA: https://sentry.io/legal/dpa/\n'
  printf 'Article 30 register entry: knowledge-base/legal/article-30-register.md (PA8).\n\n'

  # The `<!-- ids: ... -->` manifest was RETIRED in #7590.
  #
  # It existed to feed a first-time `terraform import` of issue-alert rules.
  # That adoption is complete (29 sentry_issue_alert resources against a full-
  # root plan), so the manifest has no live consumer, and its README runbook
  # was stale by 25 resources. Repointing it at the workflows endpoint would
  # have been worse than deleting it: workflow ids and rule ids are DISJOINT
  # identifier spaces, so the marker would have kept its name and shape while
  # silently changing meaning — a live trap for the next reader who trusted it.
} > "$out_file"

echo "[ok] Wrote audit report: $out_file"

# --- Class D gate ---------------------------------------------------------
# Deliberately NOT the A/B/C posture. Those classes only `printf` into the
# report and let the script exit 0 — that is correct for them (they describe
# routing gaps an operator triages), and changing it would break the callers
# that treat a non-zero audit as a hard stop. Class D is different: it is
# unreclaimable recurring spend, and a detector that only writes a line into
# a report nobody opens is wired to nothing. It must exit non-zero.
#
# Placed last, after the report is written and the markers are emitted, so
# the operator gets the full list — a bare failure with no slugs is not
# actionable. Nothing runs after this point, so the gate cannot be skipped.
#
# Callers — and Class D's teeth exist in EXACTLY ONE of them, so state it
# plainly rather than implying three:
#   - apply-sentry-infra.yml (apply job): runs this under `set -euo pipefail`
#     BEFORE `terraform plan`, WITH SENTRY_STATE_REQUIRED=1 + the state half
#     injected. This is the only caller where a Class D orphan halts anything
#     (the apply, before any state mutation).
#   - sentry-audit-gate.yml: invokes the script with NO state half, so
#     `state_known=0` -> Class D can only WARN here, never fail. (It is also not
#     in scripts/required-checks.txt, so it gates no required context.) Pre-merge
#     Class D is advisory, by construction.
#   - reusable-release.yml: `set +e` + downgrade to `::warning::`. Also passes no
#     state half, so the non-zero it would downgrade is unreachable — releases
#     were never at risk from Class D. The downgrade is belt-and-suspenders, not
#     load-bearing.
#
# ONLY unreclaimable monitors reach here — `live AND undeclared AND not in
# state`. A pending destroy (in state, block removed) is excluded upstream: it
# is not an orphan, and failing on it would halt the apply BEFORE the plan that
# reclaims it, leaving the monitor live and billing. See the state-half comment
# above.
# The SOLEUR_SENTRY_CLASS_D_ORPHAN marker below goes to STDOUT, which on this
# script's actual execution surface (a GitHub Actions runner) is the JOB LOG and
# nothing else. It is NOT shipped to Better Stack: the `SOLEUR_*` marker
# convention is HOST-journald only (apps/web-platform/infra/vector.toml scopes
# every source to the Hetzner host's `SYSLOG_IDENTIFIER`; no vector source reads
# runner stdout, and no workflow ships it). The load-bearing signal is the
# non-zero EXIT (the apply job fails, GitHub Actions notifies); the marker is a
# human-readable detail line in that failed job's log. Do not claim a Better
# Stack route for it without first adding the runner-stdout shipper AND its
# vector-scrub drift fixture.
if (( ${#orphan_live_monitors[@]} > 0 )); then
  for slug in "${orphan_live_monitors[@]}"; do
    printf 'SOLEUR_SENTRY_CLASS_D_ORPHAN: slug=%s created=%s last_checkin=%s cost_usd=%s\n' \
      "$slug" "$(monitor_created "$slug")" "$(monitor_last_checkin "$slug")" "$CRON_MONITOR_MONTHLY_USD"
  done
  echo "ERROR: ${#orphan_live_monitors[@]} live Sentry monitor(s) are unreclaimable (Class D): no declaring resource block in ${tf_dir}/*.tf AND absent from Terraform state, so no apply can ever destroy them — each bills \$${CRON_MONITOR_MONTHLY_USD}/mo. Import them into Terraform, or delete them via the Sentry API. See the Class D table in ${out_file}. Refs #6589." >&2
  exit 1
fi

# State unknown: `live AND undeclared` was computed, but without the state half a
# PENDING DESTROY (which the next apply reclaims) is indistinguishable from a
# genuinely unreclaimable orphan. Report, do not fail — failing on an unresolvable
# set is what deadlocks the apply. The authoritative fail-closed run is
# apply-sentry-infra.yml, which inits Terraform and injects SENTRY_STATE_SLUGS.
if (( class_d_state_unknown == 1 )) && (( ${#class_d_unresolved[@]} > 0 )); then
  echo "::warning::${#class_d_unresolved[@]} live Sentry monitor(s) have no declaring .tf block, but SENTRY_STATE_SLUGS was not provided so this run cannot tell a pending destroy from an unreclaimable orphan. Not failing: see ${out_file}. Candidates: ${class_d_unresolved[*]}" >&2
fi
