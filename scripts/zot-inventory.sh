#!/usr/bin/env bash
# zot-inventory.sh — READ-ONLY blob inventory of the prd zot registry, over the existing
# CF-Access-gated `registry.` ingress (#7278).
#
# WHAT THIS ANSWERS. `SOLEUR_ZOT_DISK` reports `pcent` and `fs_size_gb` and nothing about
# WHERE the bytes are. The store has been at `pcent=100` continuously while zot restarts
# ~4.8/min, and the open question — recorded as explicitly unmeasured in the #7278 spec —
# is whether the 59 GB is actually policy-KEPT blobs. This script produces the one number
# that bounds it: the total bytes referenced by every manifest reachable from `/v2/_catalog`,
# deduplicated BY DIGEST (zot runs with `"dedupe": true`, so a shared base layer is one blob
# on disk and must be counted once).
#
# WHAT IT DOES NOT ANSWER, stated up front so the number is not over-read:
#
#   `delta_gb` is an UPPER BOUND on unreferenced blob bytes. It is NOT a measurement of them
#   and it names NO cause. The two candidates that would produce the same number with
#   completely different remedies are zot's dedupe cache DB (implied by `"dedupe": true`) and
#   orphaned `blobs/uploads/` staging sessions. This script does not discriminate them.
#
#   `fs_used_gb` is derived as `fs_size_gb * pcent/100`, and that derivation carries a
#   SYSTEMATIC ~5 % overstatement: `df --output=pcent` is used/(used+avail), which EXCLUDES
#   root-reserved blocks, while `fs_size_gb` is `df --output=size`, which is TOTAL. On the
#   59 GB store that is ext4's default reserve ~= 2.95 GB baked straight into `delta_gb`.
#   `df --output=used` is not in the `SOLEUR_ZOT_DISK` marker and adding it is a cloud-init
#   change, i.e. a host replace, which is blocked. So: A DELTA UNDER ~3 GB IS NOT
#   DISTINGUISHABLE FROM ZERO.
#   # MEASURED-BY: knowledge-base/project/specs/feat-one-shot-7278-registry-restart-lever/session-state.md §"Phase 0 — preconditions MEASURED" (task 0.4, A2)
#
#   `enumeration_complete=false` licenses NO conclusion at all. A prototype sweep run from a
#   workstation on 2026-08-06 returned unique_blobs=266 / 15,867,729,779 bytes with 12 of 45
#   manifest fetches failing — consistent with the restart loop interrupting it. That is a
#   LOWER BOUND from an incomplete sweep, not a result. Bounded per-request retry exists here
#   for exactly that condition.
#
# READ-ONLY, AND CONFINED AT THE WIRE. Every registry request is GET. There is no write-shaped
# verb against `/v2/` anywhere in this file, and the accompanying suite proves it against a
# recording origin that 405s anything but GET/HEAD rather than by grepping this text. The pull
# credential holds `read` only; no user in the registry's accessControl holds `delete`.
#
# SELF-ENFORCEMENT. If `ZOT_PUSH_USER` / `ZOT_PUSH_TOKEN` are populated in the environment this
# script refuses to start. GitHub Actions does not fail on an undeclared input key, so a
# mistyped `skip_docker_login` would silently hand this job push credentials; the YAML gate
# cannot catch that and this runtime assertion can.
#
# THE REPO IS PUBLIC. Job logs are world-readable and `doppler secrets get --plain` values are
# NOT auto-masked (only `${{ secrets.* }}` are). Every secret this script reads is
# `::add-mask::`ed immediately, before any use, and no credential is ever placed on argv —
# `/proc/*/cmdline` and `set -x` both publish argv. The registry credential rides in a netrc
# inside a 0700 scratch dir removed by an EXIT trap; the ingest bearer token rides in a curl
# config file in the same dir.
#
# ERREXIT IS NEVER ENABLED HERE, and that is load-bearing rather than stylistic (AP-022 /
# ADR-170). Every failure in this script is DATA — an HTTP status the verdict taxonomy keys
# on — so every `rc=$?` site must be reachable. `set -e` would kill the shell at the failing
# curl and every line below it (the rc read, the retry, the marker, the ingest POST) would
# never run. The suite asserts mechanically that no `set -e` appears in this file.
#
# ENV CONTRACT (all read, none written):
#   ZOT_PULL_USER / ZOT_PULL_TOKEN     REQUIRED. Registry basic auth (Doppler soleur/prd).
#   BETTERSTACK_LOGS_TOKEN             REQUIRED. Ingest bearer (Doppler soleur/prd).
#   ZOT_PUSH_USER / ZOT_PUSH_TOKEN     MUST BE ABSENT. Populated => refuse to start.
#   GITHUB_RUN_ID / GITHUB_SHA         Marker provenance (`run_id`, `commit_sha`).
#   ZOT_DISK_PCENT, ZOT_DISK_FS_SIZE_GB, ZOT_DISK_BOOT_ID, ZOT_DISK_SAMPLE_AGE_S,
#   ZOT_RESTARTS_AT_START, ZOT_RESTARTS_AT_END
#                                      From the caller's two `SOLEUR_ZOT_DISK` self-pulls,
#                                      taken either side of the sweep.
#   ZOT_INVENTORY_*                    Test seams; every one has a production default.
#
# Exit: 0 for outcome ok|degraded, 1 for outcome partial|failed, 2 for a precondition refusal.
set -uo pipefail

# Globbing OFF. Repository names, tag names and digests arrive FROM THE REGISTRY and are
# iterated by word splitting (they contain `/` but never whitespace). With globbing on, a
# name containing `*` or `?` would be pathname-expanded against the runner's working
# directory, silently substituting local filenames for registry identifiers. This script
# performs no filename globbing of its own, so turning it off costs nothing.
set -f

# Locale-pinned: every numeric shape gate below uses [[ =~ ]] with [0-9], and under a UTF-8
# locale bash's collation makes the FULLWIDTH digits match that class.
export LC_ALL=C

readonly MARKER_NAME="SOLEUR_ZOT_INVENTORY"
readonly MARKER_SCHEMA=1

# The four OCI/Docker manifest + index media types. A registry that is not offered all four
# can legally answer a manifest request with a media type this script would not recurse into.
readonly MANIFEST_ACCEPT='application/vnd.oci.image.manifest.v1+json,application/vnd.oci.image.index.v1+json,application/vnd.docker.distribution.manifest.v2+json,application/vnd.docker.distribution.manifest.list.v2+json'

REGISTRY_URL="${ZOT_INVENTORY_REGISTRY_URL:-http://127.0.0.1:5000}"
INGEST_URL="${ZOT_INVENTORY_INGEST_URL:-https://s2457081.eu-fsn-3.betterstackdata.com/}"
RETRIES="${ZOT_INVENTORY_RETRIES:-3}"
RETRY_SLEEP_S="${ZOT_INVENTORY_RETRY_SLEEP_S:-2}"
MAX_PAGES="${ZOT_INVENTORY_MAX_PAGES:-50}"
HTTP_TIMEOUT_S="${ZOT_INVENTORY_HTTP_TIMEOUT_S:-30}"
# The MEASURED floor. `/v2/_catalog` returned exactly 2 repositories on 2026-08-06. A 200
# carrying fewer is a permissions or truncation artifact, not a smaller registry, and must
# never be presented as a complete enumeration.
REPO_FLOOR="${ZOT_INVENTORY_REPO_FLOOR:-2}"
# `SOLEUR_ZOT_DISK` lands every 5 min; 15 min allows two missed samples before the disk
# figures stop being usable as a same-window comparison.
DISK_SAMPLE_MAX_AGE_S="${ZOT_INVENTORY_DISK_SAMPLE_MAX_AGE_S:-900}"

# The CLOSED reason vocabulary. Pinned as data, not prose: a `reason` outside this set would
# both defeat the marker's allow-list and turn any interpolated error string into an
# unscrubbed egress path. Validated before the line is emitted.
REASON_ENUM=(
  none
  origin_unreachable
  catalog_unreadable
  catalog_empty
  catalog_undercount
  link_unfollowed
  enumeration_yielded_nothing
  tag_list_incomplete
  manifest_incomplete
  referrer_incomplete
  restart_during_sweep
  disk_sample_stale
  disk_sample_missing
)

die() { printf '%s\n' "zot-inventory: $1" >&2; exit "${2:-2}"; }

# ---------------------------------------------------------------------------------
# Preconditions. All of these refuse BEFORE a single request is issued.
# ---------------------------------------------------------------------------------

# D7 self-enforcement. This is the runtime half of the fail-closed `skip-docker-login`
# contract, and it holds independently of the YAML.
if [[ -n "${ZOT_PUSH_USER:-}" || -n "${ZOT_PUSH_TOKEN:-}" ]]; then
  die "refusing to start: ZOT_PUSH_USER/ZOT_PUSH_TOKEN are populated in this environment. This job issues GET only and must not hold a credential that can write to the registry."
fi

[[ -n "${ZOT_PULL_USER:-}" ]]  || die "ZOT_PULL_USER is unset. The registry read needs the pull credential from Doppler soleur/prd."
[[ -n "${ZOT_PULL_TOKEN:-}" ]] || die "ZOT_PULL_TOKEN is unset. The registry read needs the pull credential from Doppler soleur/prd."
# No stub, no silent skip: a run that cannot ship its marker has produced nothing durable,
# and reporting success for it is how a dark channel gets read as a clean one.
[[ -n "${BETTERSTACK_LOGS_TOKEN:-}" ]] || die "BETTERSTACK_LOGS_TOKEN is unset, so the marker could not be shipped. Refusing to run a sweep whose result would exist only in a 90-day run log."

for tool in curl jq; do
  command -v "$tool" >/dev/null 2>&1 || die "$tool is not on PATH."
done

# C1 — mask immediately, before any use.
# STDERR, not stdout. The runner parses workflow commands from BOTH streams, but
# the caller redirects our stdout to a file (`zot-inventory.sh > "$MARKER_FILE"`)
# and then posts that file verbatim into a comment on PUBLIC issue #7339. On
# stdout these two lines therefore did two wrong things at once: the runner never
# saw them (so masking never registered during the run at all), and the raw token
# bytes were carried into a world-readable issue body. `::add-mask::` scrubs the
# log STREAM — it does not scrub bytes on disk and it does not touch the HTTP
# body of a `gh` API call.
#
# Pinned by the "no credential sentinel anywhere in captured stdout" assertion in
# tests/scripts/test-zot-inventory.sh — which must read the WHOLE stream, not the
# marker line (the marker was always clean; the leak was everything around it).
printf '::add-mask::%s\n' "$ZOT_PULL_TOKEN" >&2
printf '::add-mask::%s\n' "$BETTERSTACK_LOGS_TOKEN" >&2

# C3 — credentials live in files inside a private scratch dir, never on argv.
umask 077
SCRATCH="$(mktemp -d)"
[[ -d "$SCRATCH" ]] || die "could not create a scratch directory for the credential files."
trap 'rm -rf "$SCRATCH"' EXIT
chmod 700 "$SCRATCH"

REGISTRY_HOST="$(printf '%s' "$REGISTRY_URL" | sed -E 's#^[a-zA-Z]+://##; s#[:/].*$##')"
NETRC="$SCRATCH/netrc"
printf 'machine %s\nlogin %s\npassword %s\n' "$REGISTRY_HOST" "$ZOT_PULL_USER" "$ZOT_PULL_TOKEN" > "$NETRC"
chmod 600 "$NETRC"

# ---------------------------------------------------------------------------------
# HTTP. GET only.
# ---------------------------------------------------------------------------------
HTTP_CODE=""
HTTP_BODY=""
HTTP_HDR=""

http_get() {  # $1 url, $2 accept (may be empty). Sets HTTP_CODE/HTTP_BODY/HTTP_HDR.
  local url="$1" accept="${2:-}" rc
  HTTP_BODY="$(mktemp "$SCRATCH/body.XXXXXX")"
  HTTP_HDR="$(mktemp "$SCRATCH/hdr.XXXXXX")"
  local -a args=(
    --silent --show-error
    --netrc-file "$NETRC"
    --request GET
    --max-time "$HTTP_TIMEOUT_S"
    --output "$HTTP_BODY"
    --dump-header "$HTTP_HDR"
    --write-out '%{http_code}'
  )
  [[ -n "$accept" ]] && args+=(--header "Accept: $accept")
  # AP-022: errexit is provably clear here — this file never enables it (asserted by the
  # suite), so the rc read below is reachable when curl fails.
  HTTP_CODE="$(curl "${args[@]}" "$url" 2>>"$SCRATCH/curl.err")"
  rc=$?
  if [[ $rc -ne 0 && -z "$HTTP_CODE" ]]; then HTTP_CODE="000"; fi
  [[ "$HTTP_CODE" =~ ^[0-9]{3}$ ]] || HTTP_CODE="000"
  return 0
}

http_get_retry() {  # $1 url, $2 accept. Returns 0 on 2xx, 1 otherwise. Sets HTTP_*.
  local attempt=1
  while :; do
    http_get "$1" "${2:-}"
    if [[ "$HTTP_CODE" =~ ^2[0-9][0-9]$ ]]; then return 0; fi
    if [[ "$attempt" -ge "$RETRIES" ]]; then return 1; fi
    attempt=$((attempt + 1))
    if [[ "$RETRY_SLEEP_S" != "0" ]]; then sleep "$RETRY_SLEEP_S"; fi
  done
}

# Returns the `rel="next"` target of a Link header, relative to the registry root, or empty.
# `[^>]*` rather than a negated-newline class: `[^\n]` in a POSIX ERE excludes a backslash
# and the letter n, which is not what it reads as.
# Sets LINK_NEXT_PATH (empty = no next page). It does NOT print the path.
#
# This function mutates LINK_UNFOLLOWED, so it must run in the CALLER'S shell. Returning the
# path on stdout forced every call site into `$(link_next …)`, a subshell, where the increment
# below was discarded — the rejection arm was refused correctly and then counted nowhere, so a
# truncated sweep emitted enumeration_complete=true. The MAX_PAGES arms in the callers always
# worked because they increment in the parent, which is exactly why the suite stayed green.
# Global-out mirrors http_get's HTTP_CODE/HTTP_BODY contract.
link_next() {  # $1 header-dump path
  LINK_NEXT_PATH=""
  local raw
  raw="$(grep -iE '^Link:' "$1" 2>/dev/null | tail -1 | tr -d '\r')"
  [[ -z "$raw" ]] && return 0
  grep -qE 'rel="?next"?' <<<"$raw" || return 0
  local nxt
  nxt="$(sed -E 's/^[Ll]ink:[[:space:]]*<([^>]*)>.*/\1/' <<<"$raw")"

  # The Link header is REGISTRY-CONTROLLED and is concatenated onto $REGISTRY_URL,
  # so an unvalidated value is an egress escape, not a formatting bug. curl parses
  # everything before an `@` as USERINFO, so a header of
  #
  #     Link: <@attacker.tld/v2/_catalog>; rel="next"
  #
  # yields http://127.0.0.1:5000@attacker.tld/v2/_catalog — a real off-box request
  # from a runner holding production credentials, whose response is then parsed as
  # a catalog and drives further requests. Measured against curl 8.18.0: the
  # request resolved to attacker.tld, not to the loopback bridge.
  #
  # The canary test could not catch this: every fixture Link is a relative path, so
  # the "reaches exactly two destinations" assertion was never exercised on the one
  # input class able to falsify it.
  #
  # Accept only a ROOTED PATH — no scheme, no authority, and no `@` anywhere. A
  # rejection is not silent: it is an incomplete enumeration, so it must reach
  # enumeration_complete the same way an unfollowed Link does.
  if [[ ! "$nxt" =~ ^/[A-Za-z0-9._~/?=\&%:+-]*$ ]] || [[ "$nxt" == *@* ]]; then
    printf 'the registry returned a Link "next" target that is not a rooted path (verdict=link_rejected_non_rooted). Refusing to follow it; this sweep is incomplete.\n' >&2
    LINK_UNFOLLOWED=$((LINK_UNFOLLOWED + 1))
    return 0
  fi
  LINK_NEXT_PATH="$nxt"
}

# ---------------------------------------------------------------------------------
# Accumulators.
# ---------------------------------------------------------------------------------
declare -A BLOB_SIZE=()
declare -A VISITED=()
declare -A REFERRERS_DONE=()

REPOS=0
REPOS_ENUMERATED=0
TAGS=0
MANIFESTS_FETCHED=0
CATALOG_ERRORS=0
TAG_LIST_ERRORS=0
MANIFEST_ERRORS=0
REFERRER_ERRORS=0
LINK_UNFOLLOWED=0
LINK_NEXT_PATH=""   # link_next's out-parameter; see its header for why it is not stdout

# THE DEDUP RULE, in one place so exactly one substitution can falsify it. The key IS the
# digest: zot deduplicates by content address, so the same digest under two tags and two
# repositories is ONE blob on disk. Keying by size instead would silently merge two distinct
# blobs of equal length; keying per-repo would double-count every shared base layer.
add_blob() {  # $1 digest, $2 size
  BLOB_SIZE["$1"]="$2"
}

fetch_manifest() {  # $1 repo, $2 ref (tag or digest), $3 "1" if reached via the referrers API
  local repo="$1" ref="$2" via_referrer="${3:-0}" rc digest size mybody nkids blobs children child bd bs

  http_get_retry "$REGISTRY_URL/v2/$repo/manifests/$ref" "$MANIFEST_ACCEPT"
  rc=$?
  if [[ $rc -ne 0 ]]; then
    MANIFEST_ERRORS=$((MANIFEST_ERRORS + 1))
    printf 'manifest read failed after %s attempts: repo=%s ref=%s http_code=%s verdict=manifest_incomplete\n' \
      "$RETRIES" "$repo" "$ref" "$HTTP_CODE" >&2
    return 1
  fi
  MANIFESTS_FETCHED=$((MANIFESTS_FETCHED + 1))

  mybody="$(mktemp "$SCRATCH/mf.XXXXXX")"
  cp "$HTTP_BODY" "$mybody"

  # A 2xx is not the same fact as "the body is a manifest". http_get_retry keys only on the
  # status code, and every extraction below is `2>/dev/null` — so a body truncated mid-response
  # (this store restarts ~4.8x/min, which is the failure mode the lever exists to survive)
  # parses as nothing, contributes ZERO layer bytes, and increments NO counter. The sweep then
  # reports enumeration_complete=true over a manifest whose 3 GB of layers it never saw, which
  # inflates delta_gb toward "there is more garbage, recut the store". Fail it into the
  # incomplete arm instead: unmeasurable is not measured-zero.
  if ! jq -e . <"$mybody" >/dev/null 2>&1; then
    MANIFEST_ERRORS=$((MANIFEST_ERRORS + 1))
    printf 'manifest body did not parse as JSON despite http_code=%s: repo=%s ref=%s (verdict=manifest_incomplete)\n' \
      "$HTTP_CODE" "$repo" "$ref" >&2
    return 1
  fi

  digest="$(grep -iE '^Docker-Content-Digest:' "$HTTP_HDR" 2>/dev/null | tail -1 | tr -d '\r' | awk '{print $2}')"
  if [[ ! "$digest" =~ ^sha256:[0-9a-f]{64}$ ]]; then
    digest="sha256:$(sha256sum <"$mybody" | awk '{print $1}')"
  fi
  # The manifest is itself a blob in the store, and its own bytes are the bytes received.
  size="$(wc -c <"$mybody" | tr -d ' ')"

  if [[ -n "${VISITED[$digest]:-}" ]]; then return 0; fi
  VISITED["$digest"]=1
  add_blob "$digest" "$size"

  blobs="$(jq -r '((if .config then [.config] else [] end) + (.layers // []))
                  | .[] | select(.digest != null) | "\(.digest) \(.size // 0)"' <"$mybody" 2>/dev/null)"
  while read -r bd bs; do
    [[ -n "$bd" ]] || continue
    [[ "$bs" =~ ^[0-9]+$ ]] || bs=0
    add_blob "$bd" "$bs"
  done <<<"$blobs"

  nkids="$(jq -r '(.manifests // []) | length' <"$mybody" 2>/dev/null)"
  if [[ "$nkids" =~ ^[0-9]+$ && "$nkids" -gt 0 ]]; then
    children="$(jq -r '(.manifests // [])[] | select(.digest != null) | .digest' <"$mybody" 2>/dev/null)"
    for child in $children; do
      [[ -n "${VISITED[$child]:-}" ]] && continue
      fetch_manifest "$repo" "$child" "$via_referrer"
    done
  fi

  if [[ "$via_referrer" != "1" ]]; then
    fetch_referrers "$repo" "$digest"
  fi
  return 0
}

# Referrers are INVISIBLE to `/v2/<repo>/tags/list` — measured 2026-08-06: zero `sha256-*`
# entries in either repository's tag list, while `/v2/<repo>/referrers/<digest>` returns 200
# with a sigstore bundle referrer. So referrer coverage is a first-class input to
# `enumeration_complete`: a sweep that could not read them has not enumerated the store, even
# though at ~876 bytes each their contribution to the total is negligible.
fetch_referrers() {  # $1 repo, $2 digest
  local repo="$1" digest="$2" rc children child
  [[ -n "${REFERRERS_DONE[$digest]:-}" ]] && return 0
  REFERRERS_DONE["$digest"]=1

  http_get_retry "$REGISTRY_URL/v2/$repo/referrers/$digest" ""
  rc=$?
  if [[ $rc -ne 0 ]]; then
    REFERRER_ERRORS=$((REFERRER_ERRORS + 1))
    printf 'referrers read failed after %s attempts: repo=%s digest=%s http_code=%s verdict=referrer_incomplete\n' \
      "$RETRIES" "$repo" "$digest" "$HTTP_CODE" >&2
    return 1
  fi
  children="$(jq -r '(.manifests // [])[] | select(.digest != null) | .digest' <"$HTTP_BODY" 2>/dev/null)"
  for child in $children; do
    [[ -n "${VISITED[$child]:-}" ]] && continue
    fetch_manifest "$repo" "$child" 1
  done
  return 0
}

# ---------------------------------------------------------------------------------
# Marker assembly and emission. Every exit path below goes through here.
# ---------------------------------------------------------------------------------
SWEEP_STARTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
SECONDS=0

RUN_ID="$(printf '%s' "${GITHUB_RUN_ID:-0}" | tr -cd '[:alnum:]')"
[[ -n "$RUN_ID" ]] || RUN_ID=0
COMMIT_SHA="$(printf '%s' "${GITHUB_SHA:-unknown}" | tr -cd '[:alnum:]')"
[[ -n "$COMMIT_SHA" ]] || COMMIT_SHA=unknown
BOOT_ID="$(printf '%s' "${ZOT_DISK_BOOT_ID:-unknown}" | tr -cd '[:alnum:].:_-')"
[[ -n "$BOOT_ID" ]] || BOOT_ID=unknown
PCENT="${ZOT_DISK_PCENT:-}"
FS_SIZE_GB="${ZOT_DISK_FS_SIZE_GB:-}"
DISK_SAMPLE_AGE_S="${ZOT_DISK_SAMPLE_AGE_S:-}"
ZOT_RESTARTS_AT_START_V="${ZOT_RESTARTS_AT_START:-}"
ZOT_RESTARTS_AT_END_V="${ZOT_RESTARTS_AT_END:-}"
[[ "$PCENT" =~ ^[0-9]+$ ]] || PCENT=unknown
[[ "$FS_SIZE_GB" =~ ^[0-9]+(\.[0-9]+)?$ ]] || FS_SIZE_GB=unknown
[[ "$DISK_SAMPLE_AGE_S" =~ ^[0-9]+$ ]] || DISK_SAMPLE_AGE_S=unknown
[[ "$ZOT_RESTARTS_AT_START_V" =~ ^[0-9]+$ ]] || ZOT_RESTARTS_AT_START_V=unknown
[[ "$ZOT_RESTARTS_AT_END_V" =~ ^[0-9]+$ ]] || ZOT_RESTARTS_AT_END_V=unknown

ORIGIN_VERDICT=unmeasured
ENUMERATION_COMPLETE=false

reason_is_known() {  # $1 candidate
  local r
  for r in "${REASON_ENUM[@]}"; do [[ "$r" == "$1" ]] && return 0; done
  return 1
}

emit_and_exit() {  # $1 outcome, $2 reason
  local outcome="$1" reason="$2" exit_code
  reason_is_known "$reason" || die "internal: reason '$reason' is outside the closed vocabulary this marker pins." 2

  # ok ==> enumeration_complete. Without this the two fields can disagree in the durable row,
  # and `outcome` is the one a future reader greps. Enforced HERE rather than at each call site
  # so a new early-return cannot reintroduce the contradiction by omission — the guarded
  # property is "no such row can be emitted", not "these N sites remembered to check".
  if [[ "$outcome" == "ok" && "$ENUMERATION_COMPLETE" != "true" ]]; then
    die "internal: refusing to emit outcome=ok with enumeration_complete=${ENUMERATION_COMPLETE}. A summary field that says clean beside a completeness field that says nothing was measured is the contradiction this marker exists to make impossible." 2
  fi

  local unique_blobs=0 total_bytes=0 d
  for d in "${!BLOB_SIZE[@]}"; do
    unique_blobs=$((unique_blobs + 1))
    total_bytes=$((total_bytes + BLOB_SIZE[$d]))
  done

  # 1 GB == 2^30 bytes throughout, matching `df`'s GiB-denominated `fs_size_gb`.
  local referenced_gb fs_used_gb delta_gb
  referenced_gb="$(awk -v b="$total_bytes" 'BEGIN{printf "%.2f", b/1073741824}')"
  if [[ "$FS_SIZE_GB" == "unknown" || "$PCENT" == "unknown" ]]; then
    fs_used_gb=unknown
    delta_gb=unknown
  else
    fs_used_gb="$(awk -v s="$FS_SIZE_GB" -v p="$PCENT" 'BEGIN{printf "%.2f", s*p/100}')"
    delta_gb="$(awk -v u="$fs_used_gb" -v r="$referenced_gb" 'BEGIN{printf "%.2f", u-r}')"
  fi

  local sweep_duration_s="$SECONDS"

  MARKER_FIELDS=(
    "run_id=$RUN_ID"
    "commit_sha=$COMMIT_SHA"
    "marker_schema=$MARKER_SCHEMA"
    "outcome=$outcome"
    "reason=$reason"
    "origin_verdict=$ORIGIN_VERDICT"
    "repos=$REPOS"
    "repos_enumerated=$REPOS_ENUMERATED"
    "tags=$TAGS"
    "manifests_fetched=$MANIFESTS_FETCHED"
    "catalog_errors=$CATALOG_ERRORS"
    "tag_list_errors=$TAG_LIST_ERRORS"
    "manifest_errors=$MANIFEST_ERRORS"
    "referrer_errors=$REFERRER_ERRORS"
    "link_unfollowed=$LINK_UNFOLLOWED"
    "enumeration_complete=$ENUMERATION_COMPLETE"
    "unique_blobs=$unique_blobs"
    "manifest_referenced_bytes=$total_bytes"
    "manifest_referenced_gb=$referenced_gb"
    "fs_size_gb=$FS_SIZE_GB"
    "pcent=$PCENT"
    "fs_used_gb=$fs_used_gb"
    "delta_gb=$delta_gb"
    "disk_sample_age_s=$DISK_SAMPLE_AGE_S"
    "boot_id=$BOOT_ID"
    "zot_restarts_at_start=$ZOT_RESTARTS_AT_START_V"
    "zot_restarts_at_end=$ZOT_RESTARTS_AT_END_V"
    "sweep_started_at=$SWEEP_STARTED_AT"
    "sweep_duration_s=$sweep_duration_s"
  )

  # A space in any value would split one field into two and corrupt the parse of everything
  # after it. Refuse rather than ship a line whose later fields cannot be trusted.
  local f
  for f in "${MARKER_FIELDS[@]}"; do
    case "$f" in
      *[[:space:]]*) die "internal: marker field '$f' carries whitespace." 2 ;;
      *=) die "internal: marker field '$f' has an empty value." 2 ;;
    esac
  done

  local line="$MARKER_NAME ${MARKER_FIELDS[*]}"

  # The accumulated digest:size set. On an arithmetic surprise this is what discriminates the
  # defect shape; a bare total cannot tell dedup-by-size from dedup-by-digest.
  for d in "${!BLOB_SIZE[@]}"; do
    printf '  %s:%s\n' "$d" "${BLOB_SIZE[$d]}"
  done
  printf '%s\n' "$line"

  # C2 — the payload is BUILT, never interpolated. `jq -Rn --arg` is what makes a registry
  # controlled string incapable of changing the JSON's shape.
  local payload="$SCRATCH/payload.json"
  # `-c` so the request body is ONE line: the sink stores the record verbatim, and a
  # pretty-printed body puts literal newlines inside the shipped payload.
  jq -c -Rn --arg m "$line" '{message:$m}' > "$payload" || die "could not build the ingest payload." 2

  local conf="$SCRATCH/ingest.conf"
  {
    printf 'url = "%s"\n' "$INGEST_URL"
    printf 'header = "Authorization: Bearer %s"\n' "$BETTERSTACK_LOGS_TOKEN"
    printf 'header = "Content-Type: application/json"\n'
    printf 'data-binary = "@%s"\n' "$payload"
  } > "$conf"
  chmod 600 "$conf"

  local ingest_code rc
  ingest_code="$(curl --silent --show-error --request POST --config "$conf" \
    --max-time "$HTTP_TIMEOUT_S" --output /dev/null --write-out '%{http_code}' 2>>"$SCRATCH/curl.err")"
  rc=$?
  if [[ $rc -ne 0 && -z "$ingest_code" ]]; then ingest_code="000"; fi
  [[ "$ingest_code" =~ ^[0-9]{3}$ ]] || ingest_code="000"

  printf '%s_INGEST ingest_http_code=%s\n' "$MARKER_NAME" "$ingest_code"
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    printf 'ingest_http_code=%s\n' "$ingest_code" >> "$GITHUB_OUTPUT"
    printf 'marker_run_id=%s\n' "$RUN_ID" >> "$GITHUB_OUTPUT"
  fi

  case "$outcome" in
    ok|degraded) exit_code=0 ;;
    partial|failed) exit_code=1 ;;
    *) die "internal: outcome '$outcome' is outside {ok,degraded,partial,failed}." 2 ;;
  esac

  if [[ ! "$ingest_code" =~ ^2[0-9][0-9]$ ]]; then
    # The status IS the verdict — `verdict=ingest_rejected_http_<code>`. A region-pin refusal
    # answers 401 here, which is what distinguishes it from a marker that shipped and was not
    # yet queryable. The round-trip gate reads this code and attaches H6 to it.
    printf 'the ingest POST returned http_code=%s (verdict=ingest_rejected_http_%s). The marker above was NOT accepted by the sink.\n' \
      "$ingest_code" "$ingest_code" >&2
    exit 1
  fi

  exit "$exit_code"
}

# ---------------------------------------------------------------------------------
# B2 — origin reachability FIRST. The composite's readiness check is a local-listener probe
# and its own header records that it cannot distinguish a working bridge from a dead one;
# skipping `docker login` removes the only step that dialled the origin. Without this probe a
# crash-looping origin surfaces as a failed catalog read and gets reported as
# `catalog_unreadable` — an application-layer verdict for a transport-layer failure.
# `catalog_unreadable` is claimable ONLY below this gate.
# ---------------------------------------------------------------------------------
http_get "$REGISTRY_URL/v2/" ""
case "$HTTP_CODE" in
  200|401) ORIGIN_VERDICT=answered ;;
  *)       ORIGIN_VERDICT=dial_failed ;;
esac
printf 'origin probe: GET /v2/ http_code=%s origin_verdict=%s\n' "$HTTP_CODE" "$ORIGIN_VERDICT"

if [[ "$ORIGIN_VERDICT" != "answered" ]]; then
  printf 'the registry origin did not answer GET /v2/ (http_code=%s, origin_verdict=%s). No application-layer verdict is claimed for this run.\n' \
    "$HTTP_CODE" "$ORIGIN_VERDICT" >&2
  emit_and_exit failed origin_unreachable
fi

# ---------------------------------------------------------------------------------
# Catalog, with hand-rolled Link pagination. Hand-rolled is what makes an UNFOLLOWED Link
# observable at all — a client that follows pagination internally cannot report that it ran
# out of budget, and a truncated catalog is not a fetch error.
# ---------------------------------------------------------------------------------
REPO_LIST=""
next_path="/v2/_catalog"
page=0
while :; do
  http_get_retry "${REGISTRY_URL}${next_path}" ""
  rc=$?
  if [[ $rc -ne 0 ]]; then
    CATALOG_ERRORS=$((CATALOG_ERRORS + 1))
    printf 'the catalog read returned http_code=%s after %s attempts (verdict=catalog_unreadable).\n' "$HTTP_CODE" "$RETRIES" >&2
    emit_and_exit failed catalog_unreadable
  fi
  REPO_LIST+="$(jq -r '(.repositories // [])[]' <"$HTTP_BODY" 2>/dev/null)"$'\n'
  page=$((page + 1))
  link_next "$HTTP_HDR"          # sets LINK_NEXT_PATH in THIS shell — never $(…), see link_next
  nxt="$LINK_NEXT_PATH"
  [[ -z "$nxt" ]] && break
  if [[ "$page" -ge "$MAX_PAGES" ]]; then
    LINK_UNFOLLOWED=$((LINK_UNFOLLOWED + 1))
    break
  fi
  next_path="$nxt"
done

REPO_LIST="$(printf '%s' "$REPO_LIST" | grep -E '.' | sort -u || true)"
REPOS="$(printf '%s' "$REPO_LIST" | grep -cE '.' || true)"
[[ "$REPOS" =~ ^[0-9]+$ ]] || REPOS=0

if [[ "$REPOS" -eq 0 ]]; then
  # V2. A 200 carrying an empty repository list is not a result: under deny-by-default
  # accessControl that is what a credential without read scope looks like. Presenting it as a
  # complete enumeration would manufacture a `delta_gb` equal to the whole filesystem.
  printf 'the catalog answered 2xx with zero repositories (verdict=catalog_empty). No enumeration is claimed.\n' >&2
  emit_and_exit failed catalog_empty
fi

# ---------------------------------------------------------------------------------
# Tags, then manifests.
# ---------------------------------------------------------------------------------
for repo in $REPO_LIST; do
  tag_list=""
  next_path="/v2/$repo/tags/list"
  page=0
  repo_ok=1
  while :; do
    http_get_retry "${REGISTRY_URL}${next_path}" ""
    rc=$?
    if [[ $rc -ne 0 ]]; then
      TAG_LIST_ERRORS=$((TAG_LIST_ERRORS + 1))
      repo_ok=0
      printf 'tags/list read failed after %s attempts: repo=%s http_code=%s verdict=tag_list_incomplete\n' \
        "$RETRIES" "$repo" "$HTTP_CODE" >&2
      break
    fi
    tag_list+="$(jq -r '(.tags // [])[]' <"$HTTP_BODY" 2>/dev/null)"$'\n'
    page=$((page + 1))
    link_next "$HTTP_HDR"        # sets LINK_NEXT_PATH in THIS shell — never $(…), see link_next
    nxt="$LINK_NEXT_PATH"
    [[ -z "$nxt" ]] && break
    if [[ "$page" -ge "$MAX_PAGES" ]]; then
      LINK_UNFOLLOWED=$((LINK_UNFOLLOWED + 1))
      break
    fi
    next_path="$nxt"
  done
  [[ "$repo_ok" -eq 1 ]] && REPOS_ENUMERATED=$((REPOS_ENUMERATED + 1))

  for tag in $(printf '%s' "$tag_list" | grep -E '.' | sort -u || true); do
    TAGS=$((TAGS + 1))
    fetch_manifest "$repo" "$tag" 0
  done
done

# ---------------------------------------------------------------------------------
# Completeness and the verdict.
# ---------------------------------------------------------------------------------
# `TAGS -ge 1` is load-bearing and was missing. Without it the V2 `catalog_empty`
# failure — "a permissions artifact dressed up as a complete enumeration" — simply
# re-enters one layer down: a credential with CATALOG scope but no per-repo read
# gets `200 {"repositories":[…]}` then `200 {"tags":[]}` for every repo, which
# trips no error counter and clears the repo floor. Measured on the unmutated
# script: `repos=2 repos_enumerated=2 tags=0 manifests_fetched=0 unique_blobs=0
# enumeration_complete=true delta_gb=59.00`, exit 0 — i.e. the lever certifies
# "59 GB unreferenced" as a licensed conclusion, the round-trip gate passes it
# (it keys only on run_id + enumeration_complete), and the comment publishes it.
#
# zot's accessControl is deny-by-default and per-repo, so this is a REACHABLE
# production state, not a synthetic one. A store with zero tags is also a real
# state — but it is indistinguishable from the permissions artifact at this layer,
# and between "report incomplete on a genuinely empty store" and "publish a false
# 59 GB finding", only the first is survivable.
if [[ "$CATALOG_ERRORS" -eq 0 && "$TAG_LIST_ERRORS" -eq 0 && "$MANIFEST_ERRORS" -eq 0 \
      && "$REFERRER_ERRORS" -eq 0 && "$LINK_UNFOLLOWED" -eq 0 && "$REPOS" -ge "$REPO_FLOOR" \
      && "$TAGS" -ge 1 && "$MANIFESTS_FETCHED" -ge 1 ]]; then
  ENUMERATION_COMPLETE=true
else
  ENUMERATION_COMPLETE=false
fi

if [[ "$TAGS" -eq 0 || "$MANIFESTS_FETCHED" -eq 0 ]]; then
  printf 'the catalog listed %s repositories but the sweep enumerated %s tags and fetched %s manifests (verdict=enumeration_yielded_nothing). This is what a catalog-scoped credential with no per-repo read looks like; no delta is claimed.\n' \
    "$REPOS" "$TAGS" "$MANIFESTS_FETCHED" >&2
  # This used to print and FALL THROUGH to `emit_and_exit ok none`, so the durable row read
  # `outcome=ok reason=none enumeration_complete=false` — a summary field saying clean beside a
  # completeness field saying nothing was measured. The round-trip gate reds the run either way,
  # but the row persists in the warehouse and `outcome` is what a future reader greps.
  emit_and_exit partial enumeration_yielded_nothing
fi

if [[ "$REPOS" -lt "$REPO_FLOOR" ]]; then
  printf 'the catalog returned %s repositories, below the measured floor of %s (verdict=catalog_undercount).\n' \
    "$REPOS" "$REPO_FLOOR" >&2
  emit_and_exit partial catalog_undercount
fi
if [[ "$ZOT_RESTARTS_AT_START_V" != "unknown" && "$ZOT_RESTARTS_AT_END_V" != "unknown" \
      && "$ZOT_RESTARTS_AT_START_V" != "$ZOT_RESTARTS_AT_END_V" ]]; then
  printf 'zot restarted during the sweep: zot_restarts_at_start=%s zot_restarts_at_end=%s (verdict=restart_during_sweep).\n' \
    "$ZOT_RESTARTS_AT_START_V" "$ZOT_RESTARTS_AT_END_V" >&2
  emit_and_exit partial restart_during_sweep
fi
if [[ "$LINK_UNFOLLOWED" -gt 0 ]]; then
  printf 'a Link header was left unfollowed after %s pages (link_unfollowed=%s, verdict=link_unfollowed).\n' \
    "$MAX_PAGES" "$LINK_UNFOLLOWED" >&2
  emit_and_exit partial link_unfollowed
fi
if [[ "$TAG_LIST_ERRORS" -gt 0 ]]; then emit_and_exit partial tag_list_incomplete; fi
if [[ "$MANIFEST_ERRORS" -gt 0 ]]; then emit_and_exit partial manifest_incomplete; fi
if [[ "$REFERRER_ERRORS" -gt 0 ]]; then emit_and_exit partial referrer_incomplete; fi

# E9 — the disk-sample arms are `degraded` (exit 0), NOT `partial`. `partial` is exit 1 and
# means the ENUMERATION is incomplete; a stale or absent disk sample leaves the enumeration
# intact and only widens the error bar on `delta_gb`. Overloading one outcome across an exit-1
# and an exit-0 arm is what made the v1 taxonomy unusable to a caller.
if [[ "$FS_SIZE_GB" == "unknown" || "$PCENT" == "unknown" ]]; then
  emit_and_exit degraded disk_sample_missing
fi
if [[ "$DISK_SAMPLE_AGE_S" == "unknown" || "$DISK_SAMPLE_AGE_S" -gt "$DISK_SAMPLE_MAX_AGE_S" ]]; then
  emit_and_exit degraded disk_sample_stale
fi

emit_and_exit ok none
