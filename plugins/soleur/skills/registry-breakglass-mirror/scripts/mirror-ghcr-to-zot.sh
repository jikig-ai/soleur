#!/usr/bin/env bash
# mirror-ghcr-to-zot.sh — break-glass GHCR→zot mirror, executed ON a private-net
# datacenter host (soleur:registry-breakglass-mirror, #11424; ADR-096 amendment
# 2026-10-28, the sanctioned name-scoped exception to the #9169 hosts-file deny).
#
# WHEN THIS RUNS. The CF-tunnel registry bridge is down, so CI and
# scripts/registry-restore-from-ghcr.sh cannot reach zot at all, and production's
# zot store must be re-materialised from GHCR. Copy this script to a datacenter
# host (default web-1; any 10.0.1.0/24 member), run it there: the pull leg rides
# the datacenter link (~3 min measured for ~2.4 GB during the 2026-10-28 O2
# recovery vs ~1 h+ of failed residential-uplink uploads) and the push leg stays
# on the private layer-2 network.
#
# THE ONE RULE THIS EXISTS FOR: never upload blobs through a forwarded registry
# connection. zot PATCH uploads die mid-stream over `ssh -L` and registries do
# not resume upload sessions. Push only here, on the private net.
#
# THE SINKHOLE BYPASS. The hosts-file ghcr deny sinkholes ghcr.io,
# pkg-containers.githubusercontent.com and docker.pkg.github.com to 0.0.0.0/:: —
# an accident guard on NAME RESOLUTION (enumerated from
# apps/web-platform/infra/server.tf local.ghcr_deny_sh), not an egress control.
# This script's only exception is per-command `curl --resolve <name>:443:<ip>`
# on exactly the two names a GHCR pull needs (docker.pkg.github.com is legacy and
# is never resolved here). /etc/hosts is never edited — there are no writes to it
# anywhere in this file — TLS verification stays ON (--resolve pins only the
# dial address; SNI, the handshake and CA verification still target the
# hostname, so -k/--insecure is forbidden on the pull leg; it appears only on
# crane calls to the plain-HTTP private-net sink, the same posture as the
# standing hetzner -> zotRegistry edge), and every pulled byte is verified at its
# sha256, so a wrong --resolve answer cannot inject content.
#
# NAME RESOLUTION FOR THE BYPASS — one mechanism: DNS-over-HTTPS. The host's own
# getent would return the sinkhole, so the script asks a public resolver over
# HTTPS (cloudflare-dns.com/dns-query, then dns.google/resolve — neither is in
# the deny set and the host's unrestricted OUTPUT chain carries it; the nftables
# egress firewall is docker0-bridge-scoped and does not cover host processes).
# GHCR_IP / PKGC_IP env overrides skip the lookup entirely.
#
# SIGNATURE OBLIGATION. ci-deploy cosign-verifies at deploy time and fetches the
# signature from the SAME registry it pulled from (ADR-087), so the cosign
# referrers tag `sha256-<image-digest-hex>` is mirrored per image. GHCR serves it
# as an OCI INDEX whose CHILD carries artifactType (the #7410 lesson — reading
# the tag as a plain manifest fail-closes a healthy signature). A missing
# signature is a hard failure, never a warning: there is no unsigned-mirror arm.
#
# VERIFICATION. `crane digest` alone is not proof — a manifest can outlive its
# layers under zot gc+dedupe (measured 2026-08-05). Read-back is
# `crane validate --remote` per platform child, blob-presence via `crane blob`
# for attestation/signature children (a whole-index validate would gunzip a
# plain-JSON in-toto/sigstore layer — #7378), per pushed digest.
#
# Usage:
#   mirror-ghcr-to-zot.sh [--dry-run] <repo> <ref> [<ref>...]
#
#   <repo>  GHCR repository path, e.g. jikig-ai/soleur-web-platform
#           (a leading ghcr.io/ is stripped).
#   <ref>   repo@sha256:<64hex> | repo:<tag> | sha256:<64hex> | <tag>
#           (prefixed forms must name <repo>; bare forms bind to it).
#
#   --dry-run   resolve + read manifests, print the plan (refs, blob counts,
#               target) and exit 0 without pulling blobs or pushing.
#   --help      this text.
#
# Env:
#   GHCR_TOKEN        operator-supplied read:packages PAT — required unless
#                     --dry-run. NEVER the Doppler GHCR_READ_TOKEN: revoked by
#                     design (ADR-096 §5.5/B3).
#   GHCR_USER         basic-auth username for the token exchange (the PAT
#                     carries the identity). Default: operator.
#   ZOT_PUSH_USER     sink credential — Doppler soleur/prd.
#   ZOT_PUSH_TOKEN    sink credential — Doppler soleur/prd.
#                     Both validated non-empty BEFORE the first network call.
#   ZOT_TARGET        sink registry host:port (default 10.0.1.30:5000).
#   GHCR_IP, PKGC_IP  optional --resolve overrides (see header).
#   CRANE_CMD         crane binary to invoke (test seam; default: crane, with a
#                     pinned v0.20.2 github-release fetch when absent —
#                     github.com is NOT sinkholed).
#   CRANE_TIMEOUT     seconds bound on every crane invocation (default 900 —
#                     a stalled private-net write dies retryable, never hangs).
#
# Secrets transit via env/stdin only — never argv, never logged; the tokens are
# unset after use and the private DOCKER_CONFIG is removed with the scratch dir.
# Residual: SIGKILL skips the EXIT trap, leaving the 0700 $WORK (token.json,
# dockercfg/config.json) on disk — bounded to same-UID readers; unclosable.
#
# NOTE — deliberate triplication: fetch_artifact / verify_blobs_of /
# count_artifact (and verify_pushed's TSV variant) share the enumerate-children
# / enumerate-blobs / count-check shape. This script is distributed
# self-contained to an incident host, so the copies stay inline — keep all four
# in lockstep when one changes.
#
# Exit codes (one operator action per code, mirroring the restore engine):
#   0  every required reference pushed AND verified (manifest + blobs + signature)
#   1  usage / configuration error
#   2  SOURCE (GHCR) unavailable or rejected — nothing mirrored; also covers the
#      name-resolution and token-exchange legs
#   3  SINK (zot) unavailable — retryable
#   4  verification failed — the copy "succeeded" and the result is unusable
#      (missing blob, digest mismatch, missing signature). NOT retryable.
#   5  CREDENTIAL unusable (absent/empty, or rejected by the sink)
#   6  unclassified — loudest arm; file it
#   78 refused to run under xtrace with a credential set (#7797)
#
# Failure text names only MEASURED causes (ADR-166): the closed verdict
# vocabulary lives in scripts/zot-mirror-diagnosis.sh on the CI path; this engine
# reports the http_code / crane error it actually observed.

set -euo pipefail

# Refuse to run under xtrace while a credential this script expands is in the
# environment — `bash -x` prints expanded values (see #7797). This precedes every
# other command on purpose (the credential-trace lint's Rule A); `set`/`shopt`
# are the only statements allowed ahead of it.
case "$-" in
  *x*)
    # GHCR_READ_TOKEN is never set by design (revoked, ADR-096 §5.5/B3) — naming
    # it keeps this refusal honest if a future edit ever expands it.
    if [ -n "${DEPLOY_SSH_PRIVATE_KEY:+x}${GHCR_READ_TOKEN:+x}${GHCR_TOKEN:+x}${ZOT_PUSH_TOKEN:+x}" ]; then
      printf '[FATAL] refusing to run under xtrace while a credential is set — the trace would print it (see #7797)\n' >&2
      exit 78
    fi
    ;;
esac

ZOT_TARGET="${ZOT_TARGET:-10.0.1.30:5000}"
GHCR_USER="${GHCR_USER:-operator}"
CRANE_VERSION="v0.20.2"
CRANE_SHA256="c14340087103ba9dadf61d45acd20675490fd0ccbd56ac7901fc1b502137f44b"
CRANE="${CRANE_CMD:-crane}"
DRY_RUN=0

usage() {
  cat <<'EOF'
mirror-ghcr-to-zot.sh — break-glass GHCR→zot mirror, run ON a private-net
datacenter host (soleur:registry-breakglass-mirror, #11424).

  mirror-ghcr-to-zot.sh [--dry-run] <repo> <ref> [<ref>...]

  <repo>  GHCR repository path (e.g. jikig-ai/soleur-web-platform;
          a leading ghcr.io/ is stripped)
  <ref>   repo@sha256:<64hex> | repo:<tag> | sha256:<64hex> | <tag>
          (prefixed forms must name <repo>; bare forms bind to it)

  --dry-run   resolve + read manifests, print the plan (refs, blob counts,
              target) and exit 0 without pulling blobs or pushing
  --help      this text

Env: GHCR_TOKEN (required unless --dry-run; operator read:packages PAT — never
the revoked-by-design GHCR_READ_TOKEN), GHCR_USER (default operator),
ZOT_PUSH_USER, ZOT_PUSH_TOKEN (Doppler soleur/prd), ZOT_TARGET (default
10.0.1.30:5000), GHCR_IP / PKGC_IP (optional --resolve overrides), CRANE_CMD
(test seam), CRANE_TIMEOUT (default 900s).

Exit: 0 verified · 1 usage · 2 GHCR/source · 3 sink retryable · 4 verification
(not retryable) · 5 credential · 6 unclassified · 78 xtrace refusal.
EOF
}

die() { # $1 = exit code, rest = message (CR/LF flattened — registry text interpolates)
  local code="$1"; shift
  local msg="$*"
  msg="${msg//[$'\r\n']/ }"
  # Registry/crane error text is interpolated into messages — strip the rest of
  # the C0 range + DEL too, so a hostile response cannot write escape sequences
  # into the operator's terminal.
  msg="$(printf '%s' "$msg" | tr -d '\000-\010\013-\037\177')"
  printf 'mirror-ghcr-to-zot: %s\n' "$msg" >&2
  exit "$code"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --) shift; break ;;
    -*) die 1 "unknown flag '$1' — run with --help" ;;
    *) break ;;
  esac
done

[[ "$ZOT_TARGET" =~ ^[a-zA-Z0-9.-]+:[0-9]+$ ]] \
  || die 1 "ZOT_TARGET must look like host:port (got '${ZOT_TARGET}') — the push and the sink credentials would go to a host you did not name."
[[ "${CRANE_TIMEOUT:-900}" =~ ^[1-9][0-9]*$ ]] \
  || die 1 "CRANE_TIMEOUT must be a positive-integer second count (got '${CRANE_TIMEOUT:-}') — 0 disables the bound."

REPO="${1:-}"
[[ $# -ge 1 ]] || { usage >&2; die 1 "<repo> and at least one <ref> are required."; }
shift
REPO="${REPO#ghcr.io/}"
[[ "$REPO" =~ ^[a-z0-9][a-z0-9._/-]*[a-z0-9]$ && "$REPO" == */* ]] \
  || die 1 "repo must look like owner/name (e.g. jikig-ai/soleur-web-platform); got '${REPO}'"
[[ $# -ge 1 ]] || die 1 "at least one <ref> is required."

# parse_ref <ref> → "tag\t<tag>" or "digest\tsha256:<64hex>"; dies on bad shape.
parse_ref() {
  local ref="${1#ghcr.io/}" v
  case "$ref" in
    */*)
      [[ "$ref" == "$REPO"@* || "$ref" == "$REPO":* ]] \
        || die 1 "ref '$1' names a different repo than '${REPO}'"
      v="${ref#"$REPO"}" ;;
    *) v="$ref" ;;
  esac
  case "$v" in
    @sha256:*|sha256:*)
      v="sha256:${v##*sha256:}"
      [[ "$v" =~ ^sha256:[0-9a-f]{64}$ ]] \
        || die 1 "malformed digest in ref '$1' (expected sha256:<64 lowercase hex>)"
      printf 'digest\t%s' "$v" ;;
    :*|*)
      local t="${v#:}"
      [[ "$t" =~ ^[A-Za-z0-9_][A-Za-z0-9._-]{0,127}$ ]] \
        || die 1 "malformed tag in ref '$1' (OCI tag charset)"
      printf 'tag\t%s' "$t" ;;
  esac
}

REF_KIND=() REF_VAL=()
for a in "$@"; do
  kv="$(parse_ref "$a")"
  REF_KIND+=("${kv%%$'\t'*}")
  REF_VAL+=("${kv#*$'\t'}")
done
N_REFS=${#REF_KIND[@]}

# Re-assert the parsed shapes where the values are consumed: REF_VAL elements
# are argv-derived and reach a credentialed request path, so each must still
# match its strict form at the point of use (the credential-trace lint's
# destination-pin limb — an adjudication, not a shape hint).
for ((i = 0; i < N_REFS; i++)); do
  [[ "${REF_VAL[$i]}" =~ ^sha256:[0-9a-f]{64}$ || "${REF_VAL[$i]}" =~ ^[A-Za-z0-9_][A-Za-z0-9._-]{0,127}$ ]] \
    || die 1 "parsed ref '${REF_VAL[$i]}' escaped its strict shape contract — refusing to use it."
done

command -v curl >/dev/null 2>&1 || die 6 "curl is required on this host."
command -v jq   >/dev/null 2>&1 || die 6 "jq is required on this host."
command -v sha256sum >/dev/null 2>&1 || die 6 "sha256sum is required on this host."
command -v timeout >/dev/null 2>&1 || die 6 "timeout(1) is required on this host (bounds every crane call)."

WORK="$(mktemp -d)" || die 6 "could not create a scratch directory."
case "$WORK" in /*) ;; *) die 6 "scratch dir is not absolute — refusing to own its cleanup" ;; esac
trap 'rm -rf "$WORK"' EXIT

# Credentials first, before any network call: a fault discovered halfway leaves a
# partially populated registry. In --dry-run no push is possible, so the sink
# credentials are not required; GHCR_TOKEN is optional (manifest reads only).
if (( DRY_RUN == 0 )); then
  [[ -n "${ZOT_PUSH_USER:-}" ]]  || die 5 "ZOT_PUSH_USER is unset or empty (Doppler soleur/prd) — cannot authenticate to the sink."
  [[ -n "${ZOT_PUSH_TOKEN:-}" ]] || die 5 "ZOT_PUSH_TOKEN is unset or empty (Doppler soleur/prd) — cannot authenticate to the sink."
fi
ghcr_token_set=0
if [[ -n "${GHCR_TOKEN:-}" ]]; then ghcr_token_set=1; fi
if (( DRY_RUN == 0 )) && (( ghcr_token_set == 0 )); then
  die 5 "GHCR_TOKEN is unset or empty — the operator-supplied read:packages PAT is required at invocation. NEVER Doppler GHCR_READ_TOKEN: it is revoked BY DESIGN (ADR-096 §5.5/B3)."
fi

# ── crane, pinned. github.com is not in the sinkhole set. Only the live path
# invokes crane — a dry-run never needs the binary, so its fetch is skipped there.
if (( DRY_RUN == 0 )) && ! command -v "$CRANE" >/dev/null 2>&1; then
  mkdir -p "$WORK/bin"
  asset="go-containerregistry_Linux_x86_64.tar.gz"
  if ! curl --disable --noproxy '*' -fsSL --proto '=https' --proto-redir '=https' \
       --connect-timeout 10 --max-time 120 \
       -o "$WORK/crane.tgz" \
       "https://github.com/google/go-containerregistry/releases/download/${CRANE_VERSION}/${asset}" \
       2>"$WORK/crane-dl.err"; then
    die 6 "could not download the pinned crane ${CRANE_VERSION} tarball: $(tail -c 200 "$WORK/crane-dl.err" 2>/dev/null | tr '\r\n' ' ')"
  fi
  echo "${CRANE_SHA256}  $WORK/crane.tgz" | sha256sum -c - >/dev/null 2>&1 \
    || die 6 "the crane ${CRANE_VERSION} tarball does not hash to the pinned sha256 — refusing to run it."
  tar -xzf "$WORK/crane.tgz" -C "$WORK/bin" crane \
    || die 6 "could not extract the pinned crane tarball."
  CRANE="$WORK/bin/crane"
fi

# ── IPv4 validation + DoH resolution (the ONE mechanism; see header). ─────────
ipv4_ok() {
  local ip="$1" a b c d
  [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] || return 1
  IFS=. read -r a b c d <<<"$ip"
  (( a <= 255 && b <= 255 && c <= 255 && d <= 255 )) || return 1
  return 0
}

doh_ip() { # $1=name → prints one IPv4, rc 1 if neither resolver yielded one
  local name="$1" body ip
  for ep in "https://cloudflare-dns.com/dns-query?name=${name}&type=A" \
            "https://dns.google/resolve?name=${name}&type=A"; do
    if ! body="$(curl --disable --noproxy '*' -fsS --proto '=https' \
          --connect-timeout 5 --max-time 15 \
          -H 'accept: application/dns-json' "$ep" 2>/dev/null)"; then
      continue
    fi
    ip="$(jq -r '[.Answer[]? | select(.type == 1) | .data][0] // empty' <<<"$body" 2>/dev/null)" || continue
    if ipv4_ok "$ip"; then printf '%s\n' "$ip"; return 0; fi
  done
  return 1
}

resolve_for() { # $1=name $2=env-override $3=env-name → prints IPv4 or dies 2
  if [[ -n "$2" ]]; then
    ipv4_ok "$2" || die 2 "$3 override '$2' is not a dotted-quad IPv4 — refusing it."
    printf '%s\n' "$2"; return 0
  fi
  local ip
  if ip="$(doh_ip "$1")"; then printf '%s\n' "$ip"; return 0; fi
  die 2 "could not resolve a real address for $1 — DoH failed and no $3 override was supplied (the hosts-file answer is the 0.0.0.0 sinkhole BY DESIGN)."
}

# ── curl wrappers: TLS verification intact; credentials ride stdin only. ──────
_bearer_ok() { local LC_ALL=C; case "${1:-}" in ''|*[!A-Za-z0-9._~+/=-]*) return 1 ;; esac; }

RES=()   # per-command --resolve args, populated by resolve_ghcr_names()
TOK=""   # the GHCR pull bearer; unset after the pull phase

resolve_ghcr_names() {
  GHCR_IP="$(resolve_for ghcr.io "${GHCR_IP:-}" GHCR_IP)"
  PKGC_IP="$(resolve_for pkg-containers.githubusercontent.com "${PKGC_IP:-}" PKGC_IP)"
  RES=(--resolve "ghcr.io:443:${GHCR_IP}" --resolve "pkg-containers.githubusercontent.com:443:${PKGC_IP}")
}

# ghcr_get <url> <outfile> → echoes the http_code (000 on transport failure);
# always rc 0 so callers classify the code, never the process status.
ghcr_get() {
  local code
  if ! code="$(curl --disable --noproxy '*' -sSL --proto '=https' --proto-redir '=https' \
        --connect-timeout 10 --max-time 900 --retry 3 \
        "${RES[@]}" \
        -H 'Accept: application/vnd.oci.image.index.v1+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json, application/vnd.docker.distribution.manifest.list.v2+json, application/octet-stream' \
        --config - "$1" \
        < <(printf 'header = "Authorization: Bearer %s"\n' "$TOK") \
        -o "$2" -w '%{http_code}' 2>>"$WORK/curl.err")"; then
    printf '000'
    return 0
  fi
  printf '%s' "$code"
}

classify_code() {
  case "$1" in
    2*)      printf 'OK' ;;
    401|403) printf 'DENIED' ;;
    404)     printf 'NOTFOUND' ;;
    000)     printf 'NETWORK' ;;
    5*)      printf 'HTTP5XX' ;;
    *)       printf 'UNKNOWN' ;;
  esac
}

# die_by_code <what> <code> — measured-cause failure text for the pull leg.
die_by_code() {
  local what="$1" code="$2"
  case "$(classify_code "$code")" in
    NOTFOUND) die 2 "${what} is absent or not visible to this credential on GHCR (http=${code} — GHCR returns 404 for both, so this does not prove it is gone)." ;;
    DENIED)   die 2 "GHCR rejected the credential reading ${what} (http=${code}). Check the PAT's read:packages scope before concluding the object is absent." ;;
    NETWORK)  die 2 "GHCR was unreachable while reading ${what} (transport failure). Retryable." ;;
    HTTP5XX)  die 2 "GHCR returned an error for ${what} (http=${code}). Retryable." ;;
    *)        die 6 "reading ${what} returned http=${code}, a shape this script cannot classify." ;;
  esac
}

token_exchange() {
  local code
  _bearer_ok "${GHCR_TOKEN:-}" \
    || die 5 "GHCR_TOKEN is outside the bearer charset — refusing to feed it to the auth-config channel."
  [[ "$GHCR_USER" =~ ^[A-Za-z0-9._~-]+$ ]] \
    || die 5 "GHCR_USER is outside the user charset — a quote or newline would corrupt the curl auth-config line."
  if ! code="$(curl --disable --noproxy '*' -sS --proto '=https' \
        --connect-timeout 10 --max-time 30 \
        "${RES[@]}" \
        --config - \
        "https://ghcr.io/token?service=ghcr.io&scope=repository:${REPO}:pull" \
        < <(printf 'user = "%s:%s"\n' "$GHCR_USER" "$GHCR_TOKEN") \
        -o "$WORK/token.json" -w '%{http_code}' 2>>"$WORK/curl.err")"; then
    code="000"
  fi
  case "$(classify_code "$code")" in
    OK) ;;
    DENIED)  die 2 "the GHCR token exchange rejected the credential (http=${code}) — the PAT is wrong, expired, or lacks read:packages on ${REPO}." ;;
    NETWORK) die 2 "the GHCR token exchange could not reach ghcr.io (transport failure). Nothing was fetched." ;;
    *)       die 2 "the GHCR token exchange returned http=${code} — an unmeasured failure shape." ;;
  esac
  TOK="$(jq -r '.token // .access_token // empty' "$WORK/token.json" 2>/dev/null || true)"
  _bearer_ok "$TOK" \
    || die 2 "the GHCR pull token came back empty or outside the bearer charset."
  # The PAT is only needed for the exchange; the bearer covers the rest.
  unset GHCR_TOKEN
}

sha256_file() { sha256sum "$1" | cut -d' ' -f1; }

# manifest_kind — the ONE shape answer: index | manifest | malformed | empty |
# unparseable. `.manifests` present-but-not-an-array is its own class: folding it
# into "manifest" hands a malformed index to a blob walk that reads it as empty.
manifest_kind() {
  jq -r 'if   (.manifests | type) == "array"   then "index"
         elif has("manifests")                 then "malformed"
         elif (has("config") or has("layers")) then "manifest"
         else "empty" end' "$1" 2>/dev/null || printf 'unparseable\n'
}

POOL="$WORK/pool/blobs/sha256"
CUR_BLOBS="$WORK/cur.blobs"   # per-artifact record of every materialised digest

# fetch_artifact <sha256:digest> <depth> — pull a manifest/index + everything it
# declares into $POOL, verifying every sha256. Appends each materialised hex to
# $CUR_BLOBS. depth: 0 root only; an index nested in an index fails closed.
fetch_artifact() {
  local dig="$1" depth="$2" hex="${1#sha256:}" mf="$POOL/${1#sha256:}"
  local code kind children n_declared n c blobslist nb b
  if [[ ! -f "$mf" ]]; then
    mkdir -p "$POOL"
    code="$(ghcr_get "https://ghcr.io/v2/${REPO}/manifests/${dig}" "$mf")"
    [[ "$(classify_code "$code")" == "OK" ]] || die_by_code "manifest ${dig}" "$code"
    [[ "$(sha256_file "$mf")" == "$hex" ]] \
      || die 4 "manifest ${dig} bytes do not hash to their digest — refusing to mirror content the pin does not cover."
  fi
  printf '%s\n' "$hex" >> "$CUR_BLOBS"
  kind="$(manifest_kind "$mf")"
  case "$kind" in
    index)
      (( depth == 0 )) \
        || die 4 "${dig} is an index nested inside another index — this engine mirrors one level of indirection, failing closed rather than claiming a deeper walk."
      if ! children="$(jq -r '(.manifests // [])[] | (.digest // "-")' "$mf" 2>"$WORK/jq.err")"; then
        die 4 "${dig}: its child list could not be fully enumerated — a truncated read would silently skip children."
      fi
      n_declared="$(jq -r '(.manifests // []) | length' "$mf" 2>/dev/null || printf '?')"
      [[ "$n_declared" =~ ^[0-9]+$ ]] \
        || die 4 "${dig}: its child count could not be read — no completeness claim is possible."
      [[ -n "$children" || "$n_declared" == "0" ]] \
        || die 4 "${dig}: the index enumerated ZERO child rows but declares ${n_declared} — the enumeration is unusable."
      n=0
      while IFS= read -r c; do
        [[ -n "$c" ]] || continue
        n=$((n + 1))
        [[ "$c" =~ ^sha256:[0-9a-f]{64}$ && "$c" != "-" ]] \
          || die 4 "${dig}: child ${n} carries a digest this engine cannot address ('${c}')."
        fetch_artifact "$c" "$((depth + 1))"
      done <<< "$children"
      (( n == n_declared )) \
        || die 4 "${dig}: enumerated ${n} children but the index declares ${n_declared} — the remainder were never fetched."
      ;;
    manifest)
      if ! blobslist="$(jq -r '[(if has("config") then (.config.digest // "-") else empty end)] + [(.layers // [])[] | (.digest // "-")] | .[]' "$mf" 2>"$WORK/jq.err")"; then
        die 4 "${dig}: its blob list could not be fully enumerated — a truncated read would silently skip blobs."
      fi
      n_declared="$(jq -r '((if has("config") then 1 else 0 end)) + ((.layers // []) | length)' "$mf" 2>/dev/null || printf '?')"
      [[ "$n_declared" =~ ^[0-9]+$ ]] \
        || die 4 "${dig}: its blob count could not be read — no completeness claim is possible."
      local n_layers
      n_layers="$(jq -r '(.layers // []) | length' "$mf" 2>/dev/null || printf '0')"
      (( n_layers > 0 )) \
        || die 4 "${dig} declares NO layers — a config alone carries no payload (the empty-object blob is not evidence an artifact is intact)."
      if [[ -z "$blobslist" ]]; then
        (( n_declared == 0 )) \
          || die 4 "${dig}: enumerated ZERO blob rows but declares ${n_declared} — the enumeration is unusable."
      else
        nb=0
        while IFS= read -r b; do
          [[ -n "$b" ]] || continue
          nb=$((nb + 1))
          [[ "$b" =~ ^sha256:[0-9a-f]{64}$ && "$b" != "-" ]] \
            || die 4 "${dig}: blob ${nb} declares an unaddressable digest ('${b}')."
          fetch_blob "$b"
        done <<< "$blobslist"
        (( nb == n_declared )) \
          || die 4 "${dig}: fetched ${nb} blobs but the manifest declares ${n_declared} — the remainder were never fetched."
      fi
      ;;
    malformed) die 4 "${dig}: its manifest carries a \`manifests\` field that is not an array — neither a readable index nor a plain manifest." ;;
    empty)     die 4 "${dig} declares neither children nor blobs — it is not an artifact a host could pull." ;;
    *)         die 4 "${dig}: its manifest could not be parsed (kind=${kind}) — nothing about it was fetched." ;;
  esac
}

fetch_blob() { # <sha256:digest> — pull into $POOL with digest verification
  local dig="$1" hex="${1#sha256:}" code
  local f="$POOL/$hex"
  if [[ -f "$f" ]]; then printf '%s\n' "$hex" >> "$CUR_BLOBS"; return 0; fi
  code="$(ghcr_get "https://ghcr.io/v2/${REPO}/blobs/${dig}" "$f")"
  [[ "$(classify_code "$code")" == "OK" ]] || { rm -f "$f"; die_by_code "blob ${dig}" "$code"; }
  [[ "$(sha256_file "$f")" == "$hex" ]] \
    || die 4 "blob ${dig} bytes do not hash to their digest — refusing to mirror content outside the pin."
  printf '%s\n' "$hex" >> "$CUR_BLOBS"
}

# assemble_layout <digest> <layoutdir> — hardlink the artifact's blob set into an
# OCI layout dir whose index.json names exactly the artifact digest.
assemble_layout() {
  local dig="$1" ldir="$2" hex="${1#sha256:}" mt size h
  local mf="$POOL/$hex"
  mkdir -p "$ldir/blobs/sha256" || die 6 "could not create $ldir — filesystem fault."
  while IFS= read -r h; do
    [[ -n "$h" ]] || continue
    [[ -f "$POOL/$h" ]] || die 6 "layout assembly references $POOL/$h which was never materialised — a bug, not a registry state."
    ln -f "$POOL/$h" "$ldir/blobs/sha256/$h" || die 6 "could not hardlink $h into the layout — filesystem fault."
  done < <(sort -u "$CUR_BLOBS")
  mt="$(jq -r '.mediaType // empty' "$mf" 2>/dev/null || true)"
  if [[ -z "$mt" ]]; then
    case "$(manifest_kind "$mf")" in
      index) mt="application/vnd.oci.image.index.v1+json" ;;
      *)     mt="application/vnd.oci.image.manifest.v1+json" ;;
    esac
  fi
  size="$(stat -c %s "$mf")" || die 6 "could not stat $mf — filesystem fault."
  printf '{"imageLayoutVersion":"1.0.0"}' > "$ldir/oci-layout"
  jq -cn --arg mt "$mt" --arg d "$dig" --argjson sz "$size" \
    '{schemaVersion:2,mediaType:"application/vnd.oci.image.index.v1+json",
      manifests:[{mediaType:$mt,digest:$d,size:$sz}]}' > "$ldir/index.json"
}

# ── sink side: crane helpers (condensed copies of the restore engine's — this
# script is self-contained on the host; no imports). ────────────────────────────
crane_capture() { # <outfile> <errfile> <crane args...> — bounded: a stalled
  # private-net write must die as retryable NETWORK, never hang the run.
  local out="$1" err="$2" rc; shift 2
  rc=0
  timeout "${CRANE_TIMEOUT:-900}" "$CRANE" "$@" >"$out" 2>"$err" </dev/null || rc=$?
  if (( rc == 124 )); then
    printf 'crane invocation timed out after %ss (i/o timeout)\n' "${CRANE_TIMEOUT:-900}" >>"$err"
  fi
  return "$rc"
}
last_err() { tail -c 400 "$1" 2>/dev/null | tail -n 1 | tr '\r\n' ' ' | sed 's/[[:space:]]*$//' || true; }
classify() {
  local err="$1"
  case "$err" in
    *BLOB_UNKNOWN*|*"blob unknown"*)                                   echo BLOBMISSING ;;
    *MANIFEST_UNKNOWN*|*"manifest unknown"*)                           echo NOTFOUND ;;
    *UNAUTHORIZED*|*DENIED*|*"authentication required"*|*"denied:"*)   echo DENIED ;;
    *"no such host"*|*"dial tcp"*|*"connection refused"*|*"connection reset"*|\
    *"i/o timeout"*|*"TLS handshake"*|*"unexpected EOF"*|*EOF|\
    *"502 "*|*"503 "*|*"504 "*|*" 502"|*" 503"|*" 504")               echo NETWORK ;;
    *) echo UNKNOWN ;;
  esac
}
sink_die() { # <what> <errfile>
  local what="$1" err cls
  err="$(last_err "$2")"; cls="$(classify "$err")"
  case "$cls" in
    NETWORK)      die 3 "the sink became unavailable while handling ${what}. Retryable. crane: ${err}" ;;
    DENIED)       die 5 "the sink rejected this credential handling ${what} — an authorisation fault retrying will not clear. crane: ${err}" ;;
    NOTFOUND|BLOBMISSING) die 4 "${what} is missing from the sink — the mirror is incomplete. crane: ${err}" ;;
    *)            die 6 "handling ${what} failed in a way this script cannot classify. crane: ${err}" ;;
  esac
}

# verify_blobs_of <repo> <digest-ref> <what> <depth> <expect_subject>
# Presence AND integrity: `crane blob` streams the body and go-containerregistry
# verifies the content digest at EOF. Never decompresses — correct for the
# plain-JSON in-toto/sigstore payload layers that trip `crane validate` (#7378).
verify_blobs_of() {
  local repo="$1" ref="$2" what="$3" depth="${4:-0}" expect_subject="${5:-}"
  local out="$WORK/vb.out" kind children n_declared n c_digest blobs b n_decl n_layers subj
  crane_capture "$out" "$WORK/vb.err" manifest --insecure "$ref" \
    || sink_die "the manifest of ${what}" "$WORK/vb.err"
  kind="$(manifest_kind "$out")"
  case "$kind" in
    index)
      (( depth == 0 )) \
        || die 4 "${what} is an index nested inside an index — deeper nesting is unverified, failing closed."
      if ! children="$(jq -r '(.manifests // [])[] | (.digest // "-")' "$out" 2>"$WORK/vb.jqerr")"; then
        die 4 "${what}: its child list could not be fully enumerated — a truncated read would silently skip children."
      fi
      n_declared="$(jq -r '(.manifests // []) | length' "$out" 2>/dev/null || printf '?')"
      [[ "$n_declared" =~ ^[0-9]+$ ]] \
        || die 4 "${what}: its child count could not be read — no completeness claim is possible."
      [[ -n "$children" ]] \
        || die 4 "${what} is an index with no readable children, so it references nothing this mirror could verify."
      n=0
      while IFS= read -r c_digest; do
        [[ -n "$c_digest" ]] || continue
        n=$((n + 1))
        [[ "$c_digest" =~ ^sha256:[0-9a-f]{64}$ && "$c_digest" != "-" ]] \
          || die 4 "${what}: child ${n} declares no usable digest — cannot be addressed or verified."
        verify_blobs_of "$repo" "${repo}@${c_digest}" "child ${c_digest} of ${what}" "$((depth + 1))" "$expect_subject"
      done <<< "$children"
      (( n == n_declared )) \
        || die 4 "${what}: enumerated ${n} children but the index declares ${n_declared} — the remainder were never verified."
      ;;
    manifest)
      if ! blobs="$(jq -r '[(if has("config") then (.config.digest // "-") else empty end)] + [(.layers // [])[] | (.digest // "-")] | .[]' "$out" 2>"$WORK/vb.jqerr")"; then
        die 4 "${what}: its blob list could not be fully enumerated — a truncated read would silently skip blobs."
      fi
      n_decl="$(jq -r '((if has("config") then 1 else 0 end)) + ((.layers // []) | length)' "$out" 2>/dev/null || printf '?')"
      [[ "$n_decl" =~ ^[0-9]+$ ]] \
        || die 4 "${what}: its blob count could not be read — no completeness claim is possible."
      n_layers="$(jq -r '(.layers // []) | length' "$out" 2>/dev/null || printf '0')"
      [[ -n "$blobs" ]] \
        || die 4 "${what} declares no blobs, so its presence cannot be verified."
      (( n_layers > 0 )) \
        || die 4 "${what} declares NO layers — a config alone is not evidence the artifact is intact (the empty-object blob is held by every registry)."
      if [[ -n "$expect_subject" ]]; then
        subj="$(jq -r '.subject.digest // ""' "$out" 2>/dev/null || printf '')"
        if [[ -n "$subj" && "$subj" != "$expect_subject" ]]; then
          die 4 "${what}: its subject digest is ${subj} but the image being mirrored is ${expect_subject} — this signature binds a DIFFERENT image. Do NOT deploy."
        fi
      fi
      n=0
      while IFS= read -r b; do
        [[ -n "$b" ]] || continue
        n=$((n + 1))
        [[ "$b" =~ ^sha256:[0-9a-f]{64}$ && "$b" != "-" ]] \
          || die 4 "${what}: blob ${n} declares no usable digest — cannot be verified."
        crane_capture /dev/null "$WORK/vb.blob.err" blob --insecure "${repo}@${b}" \
          || sink_die "the blob ${b} of ${what}" "$WORK/vb.blob.err"
      done <<< "$blobs"
      (( n == n_decl )) \
        || die 4 "${what}: verified ${n} blobs but the manifest declares ${n_decl} — the remainder were never fetched."
      ;;
    malformed) die 4 "${what}: the sink's manifest carries a \`manifests\` field that is not an array." ;;
    empty)     die 4 "${what}: the sink returned a manifest declaring neither children nor blobs." ;;
    *)         die 4 "${what}: the sink's manifest could not be parsed (kind=${kind})." ;;
  esac
}

# verify_pushed <repo> <digest> <what> <mode:image|signature> <expect_subject>
# Digest-parity is checked by the caller; this proves the SINK holds the blobs:
# platform children via `crane validate --remote`, attestation/signature children
# via blob-presence (never whole-index validate — #7378), every child accounted.
# <expect_subject> is the IMAGE digest a signature must bind — asserted on every
# signature child that carries .subject.digest (a right-blobs/wrong-subject sig
# passes everything else).
verify_pushed() {
  local repo="$1" dig="$2" what="$3" mode="${4:-image}" expect_subject="${5:-}"
  local out="$WORK/vp.out" kind children n_declared n n_platform c_digest c_mt c_type c_arch c_at
  crane_capture "$out" "$WORK/vp.err" manifest --insecure "${repo}@${dig}" \
    || sink_die "the manifest of ${what}" "$WORK/vp.err"
  kind="$(manifest_kind "$out")"
  case "$kind" in
    manifest)
      if [[ "$mode" == "signature" ]]; then
        # A plain-manifest signature root: `crane validate` trips on the
        # sigstore layer shape (#7378) — blob-presence + subject binding
        # instead, same as signature index children.
        verify_blobs_of "$repo" "${repo}@${dig}" "${what}" 0 "$expect_subject"
      else
        crane_capture "$WORK/vp.val.out" "$WORK/vp.val.err" validate --insecure --remote "${repo}@${dig}" \
          || sink_die "${what}" "$WORK/vp.val.err"
      fi
      ;;
    index)
      if ! children="$(jq -r '(.manifests // [])[] | [(.digest // "-"), (.mediaType // "-"), (.annotations["vnd.docker.reference.type"] // "-"), (.platform.architecture // "-"), (.artifactType // "-")] | @tsv' "$out" 2>"$WORK/vp.jqerr")"; then
        die 4 "${what}: its index could not be fully enumerated — an unknown number of children were never seen."
      fi
      n_declared="$(jq -r '(.manifests // []) | length' "$out" 2>/dev/null || printf '?')"
      [[ "$n_declared" =~ ^[0-9]+$ ]] \
        || die 4 "${what}: its child count could not be read — no completeness claim is possible."
      [[ -n "$children" ]] \
        || die 4 "${what} is an index whose child list is empty — no child could be verified."
      n=0
      n_platform=0
      while IFS=$'\t' read -r c_digest c_mt c_type c_arch c_at; do
        [[ -n "$c_digest" ]] || continue
        n=$((n + 1))
        [[ "$c_digest" =~ ^sha256:[0-9a-f]{64}$ && "$c_digest" != "-" ]] \
          || die 4 "${what} declares an index child with no usable digest — cannot be verified."
        case "$c_mt" in
          *"image.index.v1+json"|*"manifest.list.v2+json")
            die 4 "${what} contains a NESTED index child ${c_digest} (${c_mt}) — blob completeness is unproven; do NOT deploy." ;;
        esac
        if [[ "$mode" == "signature" ]]; then
          verify_blobs_of "$repo" "${repo}@${c_digest}" "the signature child ${c_digest} of ${what}" 1 "$expect_subject"
        elif [[ "$c_type" == "attestation-manifest" || "$c_arch" == "unknown" || "$c_at" != "-" ]]; then
          verify_blobs_of "$repo" "${repo}@${c_digest}" "the attestation child ${c_digest} of ${what}" 1
        else
          n_platform=$((n_platform + 1))
          crane_capture "$WORK/vp.val.out" "$WORK/vp.val.err" validate --insecure --remote "${repo}@${c_digest}" \
            || sink_die "the ${c_arch} child ${c_digest} of ${what}" "$WORK/vp.val.err"
        fi
      done <<< "$children"
      (( n == n_declared )) \
        || die 4 "${what} declares ${n_declared} index children but only ${n} were verified — blob completeness is unproven."
      if [[ "$mode" == "image" ]]; then
        (( n_platform > 0 )) \
          || die 4 "${what} is an index with ${n} children and NO platform image among them — there is nothing a host could pull."
      fi
      ;;
    malformed) die 4 "${what}: the sink's manifest carries a \`manifests\` field that is not an array." ;;
    empty)     die 4 "${what}: the sink returned a manifest declaring neither children nor blobs — unverifiable." ;;
    *)         die 4 "${what}: the sink's manifest could not be parsed (kind=${kind})." ;;
  esac
}

# ── plan + dry-run ────────────────────────────────────────────────────────────
count_artifact() { # <digest> <depth> → accumulates DC_MANIFESTS DC_BLOBS DC_BYTES DC_CHILDREN
  local dig="$1" depth="$2" hex="${1#sha256:}" code kind children c sz nb n n_layers
  local mf="$WORK/dry/$hex"
  mkdir -p "$WORK/dry" || die 6 "could not create the dry-run store — filesystem fault."
  if [[ ! -f "$mf" ]]; then
    code="$(ghcr_get "https://ghcr.io/v2/${REPO}/manifests/${dig}" "$mf")"
    [[ "$(classify_code "$code")" == "OK" ]] || die_by_code "manifest ${dig} (dry-run)" "$code"
    [[ "$(sha256_file "$mf")" == "$hex" ]] \
      || die 4 "manifest ${dig} bytes do not hash to their digest (dry-run)."
  fi
  DC_MANIFESTS=$((DC_MANIFESTS + 1))
  kind="$(manifest_kind "$mf")"
  case "$kind" in
    index)
      (( depth == 0 )) || die 4 "${dig} is a nested index (dry-run)."
      if ! children="$(jq -r '(.manifests // [])[] | (.digest // "-")' "$mf" 2>"$WORK/jq.err")"; then
        die 4 "${dig}: its child list could not be fully enumerated (dry-run) — a truncated read would silently skip children."
      fi
      while IFS= read -r c; do
        [[ -n "$c" ]] || continue
        DC_CHILDREN=$((DC_CHILDREN + 1))
        [[ "$c" =~ ^sha256:[0-9a-f]{64}$ ]] || die 4 "${dig}: child carries an unaddressable digest (dry-run)."
        sz="$(jq -r --arg d "$c" 'first(.manifests[] | select(.digest == $d) | .size) // 0' "$mf" 2>/dev/null || printf 0)"
        DC_BYTES=$((DC_BYTES + ${sz:-0}))
        count_artifact "$c" "$((depth + 1))"
      done <<< "$children"
      ;;
    manifest)
      nb="$(jq -r '[ (if has("config") then [.config.size] else [] end), [(.layers // [])[] | .size] ] | flatten | "\(length) \((add // 0))"' "$mf" 2>/dev/null || printf '0 0')"
      read -r n sz <<<"$nb"
      n_layers="$(jq -r '(.layers // []) | length' "$mf" 2>/dev/null || printf '0')"
      (( n_layers > 0 )) \
        || die 4 "${dig} declares NO layers — a config alone carries no payload (dry-run parity with the live path's check)."
      DC_BLOBS=$((DC_BLOBS + ${n:-0}))
      DC_BYTES=$((DC_BYTES + ${sz:-0}))
      ;;
    *) die 4 "${dig}: unreadable manifest shape (kind=${kind}) in dry-run." ;;
  esac
}

if (( DRY_RUN )); then
  printf 'mirror-ghcr-to-zot: DRY RUN — nothing will be pulled or pushed\n'
  printf 'repo=%s target=%s refs=%d\n' "$REPO" "$ZOT_TARGET" "$N_REFS"
  if (( ghcr_token_set == 0 )); then
    i=0
    while (( i < N_REFS )); do
      printf 'ref[%d] %s=%s blobs=unmeasured (no GHCR_TOKEN — supply the PAT to count)\n' \
        "$((i + 1))" "${REF_KIND[$i]}" "${REF_VAL[$i]}"
      i=$((i + 1))
    done
    exit 0
  fi
  resolve_ghcr_names
  printf 'resolve ghcr.io=%s pkg-containers.githubusercontent.com=%s\n' "$GHCR_IP" "$PKGC_IP"
  token_exchange
  i=0
  while (( i < N_REFS )); do
    # resolve the ref to a digest: a digest ref is already pinned; a tag needs one read.
    if [[ "${REF_KIND[$i]}" == "digest" ]]; then
      D="${REF_VAL[$i]}"
      mf="$WORK/dry/${D#sha256:}"
      mkdir -p "$WORK/dry" || die 6 "could not create the dry-run store — filesystem fault."
      if [[ ! -f "$mf" ]]; then
        code="$(ghcr_get "https://ghcr.io/v2/${REPO}/manifests/${D}" "$mf")"
        [[ "$(classify_code "$code")" == "OK" ]] || die_by_code "manifest ${D} (dry-run)" "$code"
        [[ "$(sha256_file "$mf")" == "${D#sha256:}" ]] \
          || die 4 "manifest ${D} bytes do not hash to their digest (dry-run) — every pulled byte is verified at its sha256."
      fi
    else
      rv="${REF_VAL[$i]}"
      mf="$WORK/dry/tag-$rv"
      code="$(ghcr_get "https://ghcr.io/v2/${REPO}/manifests/$rv" "$mf")"
      [[ "$(classify_code "$code")" == "OK" ]] || die_by_code "manifest for tag $rv (dry-run)" "$code"
      D="sha256:$(sha256_file "$mf")"
      # Seed the dry store under the content name so count_artifact reuses it.
      [[ -f "$WORK/dry/${D#sha256:}" ]] || cp "$mf" "$WORK/dry/${D#sha256:}" || die 6 "could not seed the dry-run store — filesystem fault."
      mf="$WORK/dry/${D#sha256:}"
    fi
    DC_MANIFESTS=0 DC_BLOBS=0 DC_BYTES=0 DC_CHILDREN=0
    count_artifact "$D" 0
    sig_tag="sha256-${D#sha256:}"
    code="$(ghcr_get "https://ghcr.io/v2/${REPO}/manifests/${sig_tag}" "$WORK/dry/sig")"
    case "$(classify_code "$code")" in
      OK) sig_state="present" ;;
      NOTFOUND) sig_state="ABSENT (hard failure on a real run)" ;;
      *) sig_state="unmeasured (http=${code})" ;;
    esac
    printf 'ref[%d] %s=%s -> %s kind=%s children=%d blobs=%d declared_bytes=%d sig=%s %s\n' \
      "$((i + 1))" "${REF_KIND[$i]}" "${REF_VAL[$i]}" "$D" "$(manifest_kind "$mf")" \
      "$DC_CHILDREN" "$DC_BLOBS" "$DC_BYTES" "$sig_tag" "$sig_state"
    i=$((i + 1))
  done
  exit 0
fi

# ── live run: resolve → exchange → pull all → push all → verify all ───────────
resolve_ghcr_names
printf 'mirror-ghcr-to-zot: resolved ghcr.io=%s pkg-containers.githubusercontent.com=%s (per-command --resolve only)\n' "$GHCR_IP" "$PKGC_IP"
token_exchange

# Pull phase: one blob list per push unit, into the shared dedupe pool.
UNIT_NAME=() UNIT_DIGEST=() UNIT_BLOBS=() UNIT_IS_SIG=()
SEEN_DIGESTS=" "
i=0
while (( i < N_REFS )); do
  : > "$CUR_BLOBS"
  if [[ "${REF_KIND[$i]}" == "digest" ]]; then
    D="${REF_VAL[$i]}"
  else
    rv="${REF_VAL[$i]}"
    mf="$WORK/tag-${i}.manifest"
    code="$(ghcr_get "https://ghcr.io/v2/${REPO}/manifests/$rv" "$mf")"
    [[ "$(classify_code "$code")" == "OK" ]] || die_by_code "manifest for tag $rv" "$code"
    D="sha256:$(sha256_file "$mf")"
    # Seed the pool under the content name so fetch_artifact reuses, not re-GETs.
    mkdir -p "$POOL" || die 6 "could not create the blob pool — filesystem fault."
    [[ -f "$POOL/${D#sha256:}" ]] || cp "$mf" "$POOL/${D#sha256:}" || die 6 "could not seed the manifest pool — filesystem fault."
  fi
  fetch_artifact "$D" 0
  bl="$WORK/unit-${i}.blobs"; sort -u "$CUR_BLOBS" > "$bl" || die 6 "could not write the unit blob list — filesystem fault."
  case "${REF_KIND[$i]}" in
    digest) UNIT_NAME+=("${REPO}@${D}") ;;
    tag)    UNIT_NAME+=("${REPO}:${REF_VAL[$i]}") ;;
  esac
  UNIT_DIGEST+=("$D")
  UNIT_BLOBS+=("$bl")
  UNIT_IS_SIG+=("0")
  printf 'pulled ref[%d] %s=%s -> %s (%s objects)\n' "$((i + 1))" "${REF_KIND[$i]}" "${REF_VAL[$i]}" "$D" "$(wc -l < "$bl")"
  i=$((i + 1))
done

# Signature phase: per UNIQUE image digest, the cosign referrers tag
# `sha256-<hex>` must exist at GHCR — a missing signature is a hard failure
# (there is no unsigned-mirror arm; ci-deploy verifies against the same registry).
j=0
while (( j < N_REFS )); do
  D="${UNIT_DIGEST[$j]}"
  if [[ "$SEEN_DIGESTS" == *" $D "* ]]; then j=$((j + 1)); continue; fi
  SEEN_DIGESTS+="$D "
  sig_tag="sha256-${D#sha256:}"
  : > "$CUR_BLOBS"
  code="$(ghcr_get "https://ghcr.io/v2/${REPO}/manifests/${sig_tag}" "$WORK/sig-${j}.manifest")"
  case "$(classify_code "$code")" in
    OK) ;;
    NOTFOUND) die 4 "no cosign signature (${sig_tag}) found at GHCR for ${REPO}@${D} — or not visible to this credential; GHCR returns 404 for both. There is no unsigned-mirror arm: a mirrored image whose signature is absent fails cosign verify on the host." ;;
    *) die_by_code "the signature ${sig_tag} for ${REPO}@${D} — this does NOT mean the signature is absent" "$code" ;;
  esac
  SIG_D="sha256:$(sha256_file "$WORK/sig-${j}.manifest")"
  cp "$WORK/sig-${j}.manifest" "$POOL/${SIG_D#sha256:}" || die 6 "could not pool the signature manifest — filesystem fault."
  printf '%s\n' "${SIG_D#sha256:}" >> "$CUR_BLOBS"
  fetch_artifact "$SIG_D" 0
  bl="$WORK/unit-sig-${j}.blobs"; sort -u "$CUR_BLOBS" > "$bl" || die 6 "could not write the sig blob list — filesystem fault."
  UNIT_NAME+=("${REPO}:${sig_tag}")
  UNIT_DIGEST+=("$SIG_D")
  UNIT_BLOBS+=("$bl")
  UNIT_IS_SIG+=("$D")
  printf 'pulled sig[%d] %s -> %s (%s objects)\n' "$((j + 1))" "$sig_tag" "$SIG_D" "$(wc -l < "$bl")"
  j=$((j + 1))
done

# The bearer is only needed for the pull phase.
unset TOK

# Push phase: private keychain; the sink is plain HTTP on the private net.
export DOCKER_CONFIG="$WORK/dockercfg"
mkdir -p "$DOCKER_CONFIG" || die 6 "could not create a private docker config directory."
if ! printf '%s' "$ZOT_PUSH_TOKEN" | "$CRANE" auth login "$ZOT_TARGET" -u "$ZOT_PUSH_USER" --password-stdin --insecure \
     >"$WORK/login.out" 2>"$WORK/login.err"; then
  die 5 "the crane login command for the sink ${ZOT_TARGET} (as '${ZOT_PUSH_USER}') failed locally — crane login stores the credential and never contacts the registry, so a wrong credential surfaces later. crane: $(last_err "$WORK/login.err")"
fi
unset ZOT_PUSH_TOKEN

N_UNITS=${#UNIT_NAME[@]}
u=0
while (( u < N_UNITS )); do
  L="$WORK/layout-$u"
  CUR_BLOBS="${UNIT_BLOBS[$u]}"
  assemble_layout "${UNIT_DIGEST[$u]}" "$L"
  if ! crane_capture "$WORK/push.out" "$WORK/push.err" push --insecure "$L" "${ZOT_TARGET}/${UNIT_NAME[$u]}"; then
    sink_die "the push of ${UNIT_NAME[$u]}" "$WORK/push.err"
  fi
  printf 'pushed %s\n' "${ZOT_TARGET}/${UNIT_NAME[$u]}"
  u=$((u + 1))
done

# Verify phase — AFTER all pushes, per the guard contract: digest parity first
# (a tag must resolve to the pinned digest), then blob completeness.
verified=0
u=0
while (( u < N_UNITS )); do
  D="${UNIT_DIGEST[$u]}"
  SUBJECT=""
  case "${UNIT_IS_SIG[$u]}" in
    0) MODE="image" ;;
    *) MODE="signature"; SUBJECT="${UNIT_IS_SIG[$u]}" ;;
  esac
  if [[ "${UNIT_NAME[$u]}" == *":"* && "${UNIT_NAME[$u]}" != *"@"* ]]; then
    crane_capture "$WORK/dig.out" "$WORK/dig.err" digest --insecure "${ZOT_TARGET}/${UNIT_NAME[$u]}" \
      || sink_die "the read-back of ${UNIT_NAME[$u]}" "$WORK/dig.err"
    dst_digest="$(grep -oE 'sha256:[0-9a-f]{64}' "$WORK/dig.out" | head -1 || true)"
    [[ -n "$dst_digest" ]] \
      || die 4 "could not read ${UNIT_NAME[$u]} back from the sink — the mirror is UNVERIFIED."
    [[ "$dst_digest" == "$D" ]] \
      || die 4 "digest parity FAILED for ${UNIT_NAME[$u]} — pushed=${D} sink=${dst_digest}. A digest-pinned pull would not resolve against this mirror."
  fi
  verify_pushed "${ZOT_TARGET}/${REPO}" "$D" "${UNIT_NAME[$u]}" "$MODE" "$SUBJECT"
  verified=$((verified + 1))
  printf 'verified %s (mode=%s)\n' "${UNIT_NAME[$u]}" "$MODE"
  u=$((u + 1))
done

# Non-vacuity floor: "verified nothing" can never report success.
(( verified > 0 )) \
  || die 4 "verified ZERO references — every loop completed without error, which is exactly how a vacuous mirror reports success. Refusing."
(( verified == N_UNITS )) \
  || die 4 "verified ${verified} of ${N_UNITS} pushed references — the remainder were never read back."

printf 'mirror_summary target=%s refs=%d sigs=%d verified=%d result=ok\n' \
  "$ZOT_TARGET" "$N_REFS" "$((N_UNITS - N_REFS))" "$verified"
exit 0
