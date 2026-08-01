#!/usr/bin/env bash
# Detect Cloudflare API tokens that are DEAD or inconsistent across Doppler configs.
#
# WHY THIS EXISTS (2026-07-29 incident response)
# ----------------------------------------------
# Every `doppler_secret` that carries a Cloudflare token declares
# `lifecycle { ignore_changes = [value] }` (cf-cert-reissue-token.tf,
# tunnel.tf, zot-registry.tf). That rule is deliberate — it stops refresh-time
# churn — but it has a consequence nothing surfaces: **Terraform can never
# propagate a rotated token**. `terraform apply` reports `No changes` while the
# `prd` root config still holds the dead value, and every branch config that
# inherits from root serves it too.
#
# The failure is silent and delayed. Rotating a token in the Cloudflare
# dashboard and updating `prd_terraform` looks completely successful — the
# operator verifies the one config they edited, gets a green result, and moves
# on. The stale copies surface days later as an unrelated-looking 403 in cron,
# GHCR, or the LUKS workflow, with nothing pointing back at the rotation.
#
# Observed three times in a single session, each time only because the fan-out
# was checked by hand:
#   - REGISTRY_PUSH_ACCESS_TOKEN_*  — `prd` root stale after a Terraform replace
#   - CF_API_TOKEN_DNS_EDIT         — 5 of 7 configs stale after a dashboard roll
#   - CF_API_TOKEN_PURGE            — 6 of 7 configs stale after a dashboard roll
#
# This script makes that class fail loudly. It does NOT change the lifecycle
# rules: removing `ignore_changes` would trade a silent-staleness bug for a
# churn bug the comments say was hit before. Detection is the safer fix.
#
# USAGE
#   doppler run -p soleur -c prd_terraform -- bash scripts/check-cloudflare-token-drift.sh
#   bash scripts/check-cloudflare-token-drift.sh --json
#
# COVERAGE
#   CF_API_TOKEN*             Cloudflare API tokens (single value, Bearer-verified).
#   *ACCESS_TOKEN_ID/_SECRET  Cloudflare ACCESS SERVICE TOKENS (client-id/secret pair,
#                             verified against the Access-protected hostname). Added
#                             2026-07-30: this family is the FIRST case the header above
#                             cites, and the original enumeration regex could not match
#                             it, so the script reported a clean bill of health for a
#                             question it never asked.
#
# EXIT CODES
#   0  every token value resolves LIVE, and every enumerated token was verifiable
#   1  at least one DEAD token value found (rotation did not propagate), OR at least one
#      token could not be verified. UNVERIFIABLE has several disjoint causes with
#      different remedies — a missing hostname mapping is only one of them; see the
#      `cause` field in the report and in --json. Unverified never renders as LIVE.
#   2  preconditions missing (doppler CLI, curl, python3), OR the run drew NO conclusion
#      at all (nothing was measured, so a clean fleet cannot be claimed)

set -uo pipefail

PROJECT="${DOPPLER_PROJECT:-soleur}"
JSON_OUT=0
# --only <SUBSTRING> narrows the scan to keys containing SUBSTRING. It exists for the
# release preflight, which cares about exactly one credential (the registry-push Access
# token) and must not spend a full fleet-wide sweep — one curl per distinct value across
# every config — on the critical path of every release.
#
# It narrows the SCAN, never the enumeration source: keys still come from Doppler, so a
# newly-added token in the matched family is still picked up. A hardcoded key list is how
# CF_API_TOKEN_AUDIT was missed during the incident that motivated this script.
ONLY_MATCH=""
# --json-file <PATH> writes the machine-readable verdict to PATH while STILL printing the
# human report to stdout. It exists because the two consumers want different things from
# ONE scan: the run log needs the prose (which remediation applies, and specifically the
# "fix the DETECTOR, not the credential" warning for unverifiable rows), while the caller
# needs counts it can branch on to pick an email body. Running the script twice was the
# obvious alternative and is wrong — it doubles the Cloudflare probes, which the calling
# workflow's own comment forbids for exactly that reason.
JSON_FILE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) JSON_OUT=1; shift ;;
    --json-file)
      # Same arity guard, and for the same reason, as --only below: a bare `shift 2` with
      # $#==1 shifts nothing, returns non-zero, and (with no `set -e`) spins the loop
      # forever with no output.
      [[ $# -ge 2 && -n "${2:-}" ]] || { echo "ERROR: --json-file requires a non-empty path" >&2; exit 2; }
      JSON_FILE="$2"; shift 2 ;;
    --only)
      # `shift 2` with $#==1 shifts NOTHING and returns non-zero. There is no `set -e`
      # here, so the failure is ignored and `while [[ $# -gt 0 ]]` spins forever with no
      # output — a silent hang, in a script three separate error messages tell an operator
      # to run by hand under incident pressure. Measured: still looping at 2001 iterations.
      # An empty value is rejected too: it would silently widen a scoped check back to a
      # full fleet sweep, which is the opposite of what the caller asked for.
      [[ $# -ge 2 && -n "${2:-}" ]] || { echo "ERROR: --only requires a non-empty value" >&2; exit 2; }
      ONLY_MATCH="$2"; shift 2 ;;
    *) shift ;;
  esac
done

for bin in doppler curl python3; do
  command -v "$bin" >/dev/null 2>&1 || { echo "ERROR: $bin not on PATH" >&2; exit 2; }
done

# Enumerate configs from Doppler rather than hardcoding. A hardcoded list is
# exactly how CF_API_TOKEN_AUDIT was missed during the incident: it lived only
# in the dev* configs, which the audit sweep never looked at.
mapfile -t CONFIGS < <(doppler configs -p "$PROJECT" --json 2>/dev/null |
  python3 -c 'import json,sys; [print(c["name"]) for c in json.load(sys.stdin)]' 2>/dev/null)
if [[ ${#CONFIGS[@]} -eq 0 ]]; then
  echo "ERROR: could not enumerate Doppler configs for project '$PROJECT'" >&2
  exit 2
fi

# Enumerate token-shaped keys the same way — never a fixed list.
#
# TWO FAMILIES, because they authenticate completely differently:
#
#   CF_API_TOKEN*            — a Cloudflare API token. One value. Verified as a Bearer
#                              against /user/tokens/verify.
#   *ACCESS_TOKEN_ID/_SECRET — a Cloudflare ACCESS SERVICE TOKEN. A client-id/secret
#                              PAIR. It is not an API token and /user/tokens/verify
#                              cannot say anything about it; it is verified by presenting
#                              the pair to an Access-protected hostname.
#
# The second family was the coverage gap this script shipped with. Its own header cites
# REGISTRY_PUSH_ACCESS_TOKEN_* as the FIRST case that motivated it, and the enumeration
# regex `CF_API_TOKEN[A-Z0-9_]*` cannot match that key — the anchor is at the start, so
# no amount of trailing wildcard reaches a name that does not begin with CF_API_TOKEN.
# The script reported "0 dead" on a fleet where a REGISTRY_PUSH_ACCESS_TOKEN_* rotation
# had not propagated, which is worse than not running at all: it is a green light for a
# question it never asked.
declare -A KEYSET=()          # API tokens:            KEY -> 1
declare -A ACCESS_BASESET=()  # Access service tokens: BASE (no _ID/_SECRET) -> 1
declare -A ALL_ID_KEYS=()     # every *_ACCESS_TOKEN_ID name seen anywhere in the fleet
for cfg in "${CONFIGS[@]}"; do
  # ONE `--only-names` read per config, reused by both families. Two calls doubled the
  # Doppler request count for no benefit (measured: 26 of 53 calls on the release
  # preflight), and a second call is a second chance to silently return empty.
  #
  # The exit status is CAPTURED, not discarded. `2>/dev/null || true` on a read whose
  # emptiness decides the verdict is how a scope-denied token renders as a clean fleet.
  _names=""
  if ! _names="$(doppler secrets -p "$PROJECT" -c "$cfg" --only-names 2>/dev/null)"; then
    echo "ERROR: could not read secret names for config '$cfg' — refusing to report a verdict from a partial enumeration" >&2
    exit 2
  fi
  while read -r k; do
    [[ -z "$k" ]] && continue
    [[ -n "$ONLY_MATCH" && "$k" != *"$ONLY_MATCH"* ]] && continue
    KEYSET["$k"]=1
  done < <(printf '%s\n' "$_names" | grep -oE 'CF_API_TOKEN[A-Z0-9_]*' || true)
  # Record every key name this config carries, so the Access arm below can require that a
  # base's `_ID` half actually EXISTS somewhere in the fleet before treating it as a
  # Cloudflare Access service-token pair (see ACCESS_ID_SEEN).
  while read -r k; do
    [[ -n "$k" ]] && ALL_ID_KEYS["$k"]=1
  done < <(printf '%s\n' "$_names" | grep -oE '[A-Z0-9_]*ACCESS_TOKEN_ID' || true)
  while read -r k; do
    [[ -z "$k" ]] && continue
    [[ -n "$ONLY_MATCH" && "$k" != *"$ONLY_MATCH"* ]] && continue
    # Chained suffix strips, NOT an extglob `_@(ID|SECRET)` pattern: extglob is off by
    # default in a non-interactive shell, and an unmatched extglob silently strips
    # nothing, so the base names would keep their _ID/_SECRET suffix and the pair would
    # never be assembled. Each key ends in exactly one of the two, so chaining is exact.
    _base="${k%_ID}"; _base="${_base%_SECRET}"
    ACCESS_BASESET["$_base"]=1
  done < <(printf '%s\n' "$_names" | grep -oE '[A-Z0-9_]*ACCESS_TOKEN_(ID|SECRET)' || true)
done

# ── NON-VACUITY GATE ────────────────────────────────────────────────────────
# `CONFIGS` emptiness was guarded; key emptiness was not, so every path that enumerated
# NOTHING fell through to `exit 0` — a clean bill of health for a question never asked.
# That is the exact defect this script's own header condemns, one level up, and it was
# reachable two ways: a typo'd/renamed `--only` filter, and a Doppler read the caller is
# not scoped for.
#
# It matters most at the two call sites wired in the same PR as this guard: the release
# preflight prints "verified live" on exit 0, and the twice-daily scheduled arm is the only
# continuous fleet-wide coverage there is.
if (( ${#KEYSET[@]} + ${#ACCESS_BASESET[@]} == 0 )); then
  {
    echo "ERROR: enumerated 0 token-shaped keys across ${#CONFIGS[@]} config(s)${ONLY_MATCH:+ under --only '$ONLY_MATCH'}."
    echo "       This is a COVERAGE GAP, not a clean bill of health — nothing was checked."
    echo "       Likely causes: the --only filter matches no key; or this Doppler token"
    echo "       cannot read secret names in the scanned configs."
  } >&2
  exit 2
fi

declare -A VERDICT=()   # token value -> LIVE|DEAD  (verify each distinct value once)
DEAD_ROWS=()
LIVE_N=0
DEAD_N=0
# Positive-work counter, incremented at every real probe. Declared here, beside the other
# counters, because verify_value below already touches it and `set -u` makes a later
# declaration a fatal ordering bug rather than a silent zero.
PROBES_MADE=0

# Sets REPLY, for the same subshell reason as verify_access_pair below: called as
# `state=$(verify_value ...)` the VERDICT writes never reached the parent, so the
# "verify each distinct value once" promise in the --only rationale was not being kept.
verify_value() {
  local v="$1"
  if [[ -z "${VERDICT[$v]:-}" ]]; then
    local ok
    ok=$(curl -s --max-time 20 -H "Authorization: Bearer $v" \
      "https://api.cloudflare.com/client/v4/user/tokens/verify" |
      python3 -c 'import json,sys
try: print("LIVE" if json.load(sys.stdin).get("success") else "DEAD")
except Exception: print("DEAD")' 2>/dev/null)
    VERDICT[$v]="${ok:-DEAD}"
    PROBES_MADE=$((PROBES_MADE + 1))
  fi
  REPLY="${VERDICT[$v]}"
}

for key in $(printf '%s\n' "${!KEYSET[@]}" | sort); do
  for cfg in "${CONFIGS[@]}"; do
    val=$(doppler secrets get "$key" -p "$PROJECT" -c "$cfg" --plain 2>/dev/null)
    [[ -z "$val" ]] && continue
    verify_value "$val"; state="$REPLY"
    if [[ "$state" == "DEAD" ]]; then
      DEAD_N=$((DEAD_N + 1)); DEAD_ROWS+=("$key|$cfg")
    else
      LIVE_N=$((LIVE_N + 1))
    fi
  done
done

# ── Cloudflare ACCESS SERVICE TOKENS ────────────────────────────────────────
#
# An Access service token is a client-id/secret PAIR, not an API token, so
# verify_value() above is the wrong instrument for it — /user/tokens/verify with a
# `Authorization: Bearer` header cannot say anything about a pair, and the 400/401 it
# returns would be read as DEAD for a perfectly live token. The pair is verified the way
# it is actually used: presented to an Access-protected hostname.
#
# The verdict is drawn from the presence of Cloudflare Access's own denial stamp
# (`cf-access-aud` / `cf-access-domain`), NOT from the status code — see the block above
# verify_access_pair() for the measurement that settled this and why the status code is
# the wrong instrument. Stamp present with credentials attached => DEAD; stamp gone => the
# credentials were accepted => LIVE.
#
# The 200 here is EMPTY, and that is correct, not suspicious. registry.<domain> is a
# `tcp://` tunnel ingress consumable only via `cloudflared access tcp`, so a plain HTTPS
# GET is not the WebSocket upgrade that stream needs and nothing is proxied. Cloudflare
# answers on its own. The response therefore says exactly one thing — whether Access
# ACCEPTED the credentials — which is precisely the question this script asks, and
# nothing about whether the origin is healthy. Misreading that empty 200 as "Cloudflare
# is answering without a working origin" is what consumed the 2026-07-29 incident's
# diagnostic budget; it is called out here so the next reader of this code does not
# repeat it.
#
# HOSTNAME MAPPING: which hostname a given token is authorised for is not derivable from
# its Doppler key name, so it is mapped explicitly. An enumerated token with no mapping
# is reported UNVERIFIABLE and fails the run — never silently counted LIVE. That keeps
# the enumeration Doppler-derived (a new token cannot be missed) while refusing to
# guess: a green light this script has not earned is the exact failure it exists to end.
APP_DOMAIN_BASE="${APP_DOMAIN_BASE:-soleur.ai}"
access_hostname_for() {
  case "$1" in
    REGISTRY_PUSH_ACCESS_TOKEN) printf 'registry.%s' "$APP_DOMAIN_BASE" ;;
    CI_SSH_ACCESS_TOKEN)        printf 'ssh.%s' "$APP_DOMAIN_BASE" ;;
    *) printf '' ;;
  esac
}

# NOTE ON WHY THERE IS NO ORIGIN-PROTOCOL TABLE HERE.
#
# An earlier revision (#7127) graded non-HTTP origins on the status code, mapping 5xx to
# LIVE on the theory that an ADMITTED request reaches cloudflared, which then fails to
# speak HTTP to sshd. That theory is false, and the file already said so ~25 lines above:
# a plain GET to a raw-TCP ingress is not the WebSocket upgrade the stream needs, so
# nothing is proxied and Cloudflare answers on its own.
#
# MEASURED 2026-08-01 against registry.soleur.ai with a LIVE credential — the admitted
# response is `HTTP/2 200`, zero-byte body, and NO cf-access-* header:
#
#   admitted   -> 200, 0 bytes, no Access stamp        (edge answered; origin untouched)
#   rejected   -> 403, ~39 kB, cf-access-aud + -domain (Access's own denial page)
#
# tunnel.tf's own comment records that `ssh://` and `tcp://` are the SAME raw-TCP service
# type, so ssh.<base> answers the same way. A 5xx-means-LIVE rule can therefore never
# fire, and 200 would fall to the catch-all — trading DEAD-forever for UNVERIFIABLE-
# forever. Grading on the status code is the wrong instrument regardless of which codes
# it maps, because the status is a property of the ORIGIN and the question is about the
# GATE.
#
# So the discriminator is the Access stamp, not the status. Cloudflare Access marks its
# own rejections with `cf-access-aud` / `cf-access-domain`; an admitted request is
# answered by the edge or the origin and carries neither. That is a DIFFERENTIAL proof and
# it holds for every origin protocol, which is why the http/opaque taxonomy is gone rather
# than corrected — there is nothing left for it to decide.
# A one-line hint per unmapped base, so the report can say what to DO. Without this the
# remediation printed for an unverifiable row is the DEAD-token one ("set the live value
# on the prd ROOT config"), which is wrong twice over: nothing is stale, and no Doppler
# edit fixes a missing mapping.
access_config_hint() {
  printf 'no probe configured — add a hostname mapping for %s to access_hostname_for() in %s' \
    "$1" "$(basename "${BASH_SOURCE[0]}")"
}

UNVERIFIABLE_ROWS=()

# Probe results. Set as GLOBALS and read by the caller, never returned on stdout.
#
# Every memoised helper in this file used to be invoked as `state=$(verify_...)`. Command
# substitution runs the body in a SUBSHELL, so each `CACHE[key]=...` write was discarded
# before the parent could see it and the caches never held anything: measured 3 curl calls
# for 3 configs holding one byte-identical pair, against a comment promising one. That is
# not merely wasted requests — with no cache each config re-probes independently, so one
# transient blip inside a single run grades the SAME BYTES live in four configs and dead in
# the fifth, and the DEAD remediation then tells the operator to overwrite the ROOT config
# that all five inherit. The suite's own harness comment documents this exact trap for
# run_sut; it was never applied to the code under test.
PROBE_CODE=''
PROBE_STAMPED=''              # 1 = response carries Cloudflare Access's own denial stamp
PROBE_MITIGATED=''            # 1 = Cloudflare stamped it as its OWN block/challenge
PROBE_ACCESS_REDIRECT=''      # 1 = 302 to the Access IdP login (an Access refusal too)
PROBE_SETUP_FAILED=''         # 1 = the probe could not be SET UP; not a network fact

# One HTTPS GET. With no id/secret this is the CONTROL probe.
#
# Deliberately NOT following redirects: there is no -L/--location, and T27 asserts its
# absence. curl APPENDS each response's headers into one -D file, so under -L the stamp
# grep (an OR across the whole file) would see an early block's stamp while %{http_code}
# reports the FINAL response — the two halves of the verdict would come from different
# responses, and an admitted-after-redirect would grade DEAD, the destructive direction.
access_probe() {
  local host="$1" id="${2:-}" secret="${3:-}"
  local hdr rc=0
  PROBE_SETUP_FAILED=0
  # A local disk failure is NOT a network fact. Funnelling it into the same 000 the caller
  # maps to "unreachable" sends the operator to investigate Cloudflare DNS when the real
  # cause is a full runner disk.
  hdr=$(mktemp) || { PROBE_CODE=000; PROBE_STAMPED=0; PROBE_MITIGATED=0; PROBE_ACCESS_REDIRECT=0; PROBE_SETUP_FAILED=1; return 0; }
  local -a args=(-s -o /dev/null -D "$hdr" -w '%{http_code}' --max-time 20)
  [[ -n "$id" ]] && args+=(-H "CF-Access-Client-Id: $id" -H "CF-Access-Client-Secret: $secret")
  # Assigned then normalised, NOT `$(curl ... || printf '000')`. curl prints its -w output
  # AND exits non-zero on a transport failure, so the `||` form CONCATENATES: measured
  # `000000` on a DNS failure, and `200000` when a healthy 200 hits a post-header timeout —
  # which the old three-character `200)` arm then graded DEAD.
  PROBE_CODE=$(curl "${args[@]}" "https://${host}/" 2>/dev/null) || rc=$?
  (( rc != 0 )) && PROBE_CODE=000
  [[ "$PROBE_CODE" =~ ^[0-9]{3}$ ]] || PROBE_CODE=000
  if grep -qiE '^cf-access-(aud|domain):' "$hdr" 2>/dev/null; then PROBE_STAMPED=1; else PROBE_STAMPED=0; fi
  # Cloudflare stamps its OWN blocks and challenges with cf-mitigated. That is a positive
  # discriminator for the whole class the stamp alone is blind to — a rate-limit 429, a
  # managed-challenge 503, a WAF rule with a custom response status. Without it those are
  # unstamped non-refusals and would read as admission.
  if grep -qiE '^cf-mitigated:' "$hdr" 2>/dev/null; then PROBE_MITIGATED=1; else PROBE_MITIGATED=0; fi
  # An Access app with an IDENTITY policy refuses by redirecting to the IdP login rather
  # than 403-ing, and a plain 302 carries no cf-access-* header. Treating that as "no gate"
  # would report a fully-gated host as exposed. The Location host is the discriminator.
  if [[ "$PROBE_CODE" == 30? ]] && grep -qiE '^location:.*(cloudflareaccess\.com|/cdn-cgi/access/)' "$hdr" 2>/dev/null; then
    PROBE_ACCESS_REDIRECT=1
  else
    PROBE_ACCESS_REDIRECT=0
  fi
  rm -f "$hdr"
  PROBES_MADE=$((PROBES_MADE + 1))
}

declare -A PAIR_VERDICT=()   # host\x1fid\x1fsecret -> LIVE | DEAD:<code> | UNVERIFIABLE:<cause>
declare -A HOST_GATE=()      # host -> gated | ungated | blocked | indeterminate | unreachable | setup-failed

# Sets REPLY. Call directly; see the PROBE_CODE comment for why not `$( )`.
verify_access_pair() {
  local host="$1" id="$2" secret="$3"
  # Unit separator, not `|`: `id="a", secret="b|c"` and `id="a|b", secret="c"` collide
  # under a pipe join. Unreachable with real Access credentials (<32hex>.access / 64 hex),
  # but a key that can collide at all is the wrong key for a verdict that authorises an
  # overwrite of production secrets.
  local cache_key="${host}"$'\x1f'"${id}"$'\x1f'"${secret}"
  if [[ -n "${PAIR_VERDICT[$cache_key]:-}" ]]; then
    REPLY="${PAIR_VERDICT[$cache_key]}"; return 0
  fi

  # CONTROL PROBE (no credentials), once per host. Without it, "the origin is broken" and
  # "the Access application is GONE" are the same observation — and the second one grades
  # LIVE under any status-code rule, because an ungated request reaches the origin exactly
  # like an admitted one. LIVE is the only verdict this script emits with no email and no
  # annotation, so that false-LIVE rides the silent channel: the gate protecting host shell
  # access disappears and the detector reports a clean fleet.
  #
  # Classifying the control answer POSITIVELY matters as much here as it does for the
  # credential. "Unstamped" alone is not evidence of a missing gate: an Access app with an
  # IDENTITY policy refuses by 302-ing to the IdP (no stamp), a WAF/rate-limit rule refuses
  # in FRONT of Access (no stamp), and a 530 means the tunnel is down. Calling any of those
  # "nothing is gating this host" puts a fabricated SECURITY claim in an operator email —
  # the same naming-an-unmeasured-cause defect this script exists to drain, aimed at the
  # gate instead of the credential. Only an anonymous request that actually SUCCEEDS is
  # evidence that nothing refused it.
  if [[ -z "${HOST_GATE[$host]:-}" ]]; then
    access_probe "$host"
    if [[ "$PROBE_SETUP_FAILED" == 1 ]]; then HOST_GATE[$host]=setup-failed
    elif [[ "$PROBE_CODE" == 000 ]]; then HOST_GATE[$host]=unreachable
    elif [[ "$PROBE_STAMPED" == 1 || "$PROBE_ACCESS_REDIRECT" == 1 ]]; then HOST_GATE[$host]=gated
    elif [[ "$PROBE_MITIGATED" == 1 ]]; then HOST_GATE[$host]=blocked
    elif [[ "$PROBE_CODE" == 2?? ]]; then HOST_GATE[$host]=ungated
    else HOST_GATE[$host]=indeterminate
    fi
  fi

  case "${HOST_GATE[$host]}" in
    setup-failed)
      # LOCAL fault (mktemp). Not a network fact, and must not be reported as one: telling
      # the operator the host is unreachable sends them to Cloudflare/DNS when the runner
      # disk is full. Zero requests were sent.
      PAIR_VERDICT[$cache_key]="UNVERIFIABLE:detector-env" ;;
    unreachable)
      PAIR_VERDICT[$cache_key]="UNVERIFIABLE:host-unreachable" ;;
    blocked)
      PAIR_VERDICT[$cache_key]="UNVERIFIABLE:control-blocked" ;;
    indeterminate)
      PAIR_VERDICT[$cache_key]="UNVERIFIABLE:gate-indeterminate" ;;
    ungated)
      # An anonymous request SUCCEEDED (2xx, no stamp, no mitigation, no Access redirect).
      # Only that is evidence nothing refused it. Refuse to grade the credential; the
      # finding is the missing gate.
      PAIR_VERDICT[$cache_key]="UNVERIFIABLE:gate-absent" ;;
    gated)
      access_probe "$host" "$id" "$secret"
      if [[ "$PROBE_SETUP_FAILED" == 1 ]]; then
        PAIR_VERDICT[$cache_key]="UNVERIFIABLE:detector-env"
      elif [[ "$PROBE_CODE" == 000 ]]; then
        PAIR_VERDICT[$cache_key]="UNVERIFIABLE:probe-failed"
      elif [[ "$PROBE_STAMPED" == 1 ]]; then
        # Access's own page WITH credentials attached. DEAD is the destructive verdict —
        # its remedy overwrites the prd ROOT secret every branch config inherits — so it
        # requires the answer to actually BE a refusal, not merely to carry the stamp. A
        # stamped 200 is not a rejection whatever else it is; calling it one would print
        # "HTTP 200 ... rejected by Access" and order an overwrite on the strength of it.
        if [[ "$PROBE_CODE" == 401 || "$PROBE_CODE" == 403 ]]; then
          PAIR_VERDICT[$cache_key]="DEAD:${PROBE_CODE}"
        else
          PAIR_VERDICT[$cache_key]="UNVERIFIABLE:stamped-non-refusal"
        fi
      elif [[ "$PROBE_MITIGATED" == 1 || "$PROBE_ACCESS_REDIRECT" == 1 ]]; then
        # Cloudflare's own block/challenge, or an Access IdP redirect. Both are refusals
        # that carry no cf-access-* stamp.
        PAIR_VERDICT[$cache_key]="UNVERIFIABLE:refused-unstamped"
      elif [[ "$PROBE_CODE" == 2?? ]]; then
        # Stamp GONE and the request actually SUCCEEDED. Only admission does that, and this
        # is the MEASURED admitted shape (200, zero-byte body, no cf-access-*).
        #
        # This is an ALLOWLIST, and the first revision of this rewrite got it wrong: it
        # asserted LIVE as the catch-all `else` and narrowed only 401/403 out of it, which
        # certified a rate-limit 429, a challenge 503, an identity-policy 302 and a tunnel
        # 530 as healthy — measured, all rc=0, on the one verdict that emails nobody. That
        # is the absence-based reasoning this whole file rejects, and enumerating refusals
        # cannot work when the refusing layer's status is operator-configurable. LIVE now
        # requires positive evidence of success; everything unrecognised is loud.
        PAIR_VERDICT[$cache_key]="LIVE"
      else
        PAIR_VERDICT[$cache_key]="UNVERIFIABLE:unexpected-status"
      fi ;;
  esac
  REPLY="${PAIR_VERDICT[$cache_key]}"
}

for base in $(printf '%s\n' "${!ACCESS_BASESET[@]}" | sort); do
  # A Cloudflare Access service token is a PAIR. If no `<base>_ID` exists anywhere in the
  # fleet, this base is not one — it is some other vendor's credential whose name merely
  # ends in _ACCESS_TOKEN_SECRET, and treating it as an Access pair invents a key that
  # does not exist.
  #
  # Measured against live Doppler before this guard: `X_ACCESS_TOKEN_SECRET` (an X/Twitter
  # OAuth 1.0a secret, present in 11 of 13 configs) produced base `X_ACCESS_TOKEN`, and the
  # reporting path below rendered a FABRICATED `X_ACCESS_TOKEN_ID/_SECRET` row — a
  # credential name that has never existed — inside an ops email whose entire job is naming
  # a real stale key. The scheduled arm would have sent that twice daily, forever.
  if [[ -z "${ALL_ID_KEYS[${base}_ID]:-}" ]]; then
    continue
  fi
  host=$(access_hostname_for "$base")
  if [[ -z "$host" ]]; then
    UNVERIFIABLE_ROWS+=("${base}_ID/_SECRET|no-probe-configured|$(access_config_hint "$base")")
    continue
  fi
  for cfg in "${CONFIGS[@]}"; do
    tid=$(doppler secrets get "${base}_ID" -p "$PROJECT" -c "$cfg" --plain 2>/dev/null)
    tsec=$(doppler secrets get "${base}_SECRET" -p "$PROJECT" -c "$cfg" --plain 2>/dev/null)
    # Both halves absent = this config simply does not carry the token. ONE half present
    # is a distinct and worse state — a half-propagated rotation, which authenticates as
    # nothing — so it is reported rather than skipped.
    if [[ -z "$tid" && -z "$tsec" ]]; then continue; fi
    if [[ -z "$tid" || -z "$tsec" ]]; then
      DEAD_N=$((DEAD_N + 1)); DEAD_ROWS+=("${base}_ID/_SECRET (only one half present)|$cfg")
      continue
    fi
    verify_access_pair "$host" "$tid" "$tsec"; state="$REPLY"
    if [[ "$state" == LIVE ]]; then
      LIVE_N=$((LIVE_N + 1))
    elif [[ "$state" == UNVERIFIABLE:* ]]; then
      # Kept OUT of DEAD_ROWS deliberately. "the probe measured nothing" and "Cloudflare
      # rejected this pair" are different facts with opposite remedies, and the DEAD
      # heading tells the operator to overwrite the secret — which, on a probe that
      # measured nothing, destroys a working credential to fix an unobserved problem.
      #
      # The CAUSE is a structured field, not prose. UNVERIFIABLE now has four disjoint
      # causes with four different remedies, and the previous revision routed all of them
      # into a section headed "this script has no probe for these keys" whose footer said
      # "add a hostname mapping to access_hostname_for()" — false for every cause except
      # the unmapped one, and reproduced verbatim in the operator's email.
      case "${state#UNVERIFIABLE:}" in
        gate-absent)
          UNVERIFIABLE_ROWS+=("${base}_ID/_SECRET|gate-absent|${host} answered an UNCREDENTIALED request WITHOUT a Cloudflare Access denial — nothing is gating it, so this credential could not be graded and the host may be exposed. Check the Access application for ${host}. Do NOT rotate; rotating changes nothing while the gate is missing. (seen in ${cfg})") ;;
        host-unreachable)
          UNVERIFIABLE_ROWS+=("${base}_ID/_SECRET|host-unreachable|the control probe to ${host} got no answer at all (timeout / DNS / TLS), so nothing is known about the credential. Do NOT rotate on the strength of this row; re-run once ${host} is reachable. (seen in ${cfg})") ;;
        detector-env)
          UNVERIFIABLE_ROWS+=("${base}_ID/_SECRET|detector-env|the detector could not allocate a temp file on this runner, so NOTHING was sent to ${host}. This is a LOCAL fault (full or read-only TMPDIR), not a network or credential one. Do NOT rotate. (seen in ${cfg})") ;;
        gate-indeterminate)
          UNVERIFIABLE_ROWS+=("${base}_ID/_SECRET|gate-indeterminate|${host} answered an uncredentialed request with HTTP ${PROBE_CODE} and no Cloudflare Access stamp, which characterises neither a gate nor its absence — a tunnel outage (530) looks like this. Nothing is known about the credential. Do NOT rotate; re-run. (seen in ${cfg})") ;;
        control-blocked)
          UNVERIFIABLE_ROWS+=("${base}_ID/_SECRET|control-blocked|Cloudflare itself blocked or challenged the uncredentialed probe to ${host} (cf-mitigated), so the request never reached Access and the credential could not be graded. Check the WAF / rate-limit / bot-fight rules for ${host}. Do NOT rotate. (seen in ${cfg})") ;;
        stamped-non-refusal)
          UNVERIFIABLE_ROWS+=("${base}_ID/_SECRET|stamped-non-refusal|${host} returned HTTP ${PROBE_CODE} carrying a Cloudflare Access stamp — a stamp on something that is not a refusal. This is not evidence the credential was rejected, so it is deliberately NOT reported as stale. Do NOT rotate; investigate the Access application for ${host}. (seen in ${cfg})") ;;
        unexpected-status)
          UNVERIFIABLE_ROWS+=("${base}_ID/_SECRET|unexpected-status|${host} returned HTTP ${PROBE_CODE} with no Access stamp and no success. LIVE requires positive evidence of admission (a 2xx), so this is NOT certified — and it is not evidence of a stale credential either. Do NOT rotate; re-run and investigate the edge. (seen in ${cfg})") ;;
        refused-unstamped)
          UNVERIFIABLE_ROWS+=("${base}_ID/_SECRET|refused-unstamped|${host} refused the credentialed request WITHOUT a Cloudflare Access stamp, while the uncredentialed control WAS stamped. Something other than Access is refusing (WAF rule, IP access rule, bot-fight), so the credential could not be graded. Do NOT rotate; investigate the rule set for ${host}. (seen in ${cfg})") ;;
        *)
          UNVERIFIABLE_ROWS+=("${base}_ID/_SECRET|probe-failed|${host} is reachable and gated, but the credentialed probe got no answer, so nothing is known about the credential. Do NOT rotate on the strength of this row; re-run. (seen in ${cfg})") ;;
      esac
    else
      DEAD_N=$((DEAD_N + 1)); DEAD_ROWS+=("${base}_ID/_SECRET (HTTP ${state#DEAD:} from ${host}, rejected by Access)|$cfg")
    fi
  done
done

# An enumerated-but-unmappable token is a real gap in this script's coverage, so it stays
# loud and non-zero (see the exit at the foot of the file).
#
# It is NOT folded into DEAD_ROWS. "Unverified" and "rejected by Cloudflare" are different
# facts with different remedies, and merging them printed unverifiable rows under the
# heading "STALE — these configs hold a token value Cloudflare no longer accepts" followed
# by "set the live value on the prd ROOT config" — sending an operator to rotate a healthy
# credential. Reporting a cause nothing measured is the defect this PR exists to drain;
# the workflow got per-stage `mirror_reason` labels for exactly this reason, and the
# detector should not be the one place that still conflates them.
UNVERIFIABLE_N=${#UNVERIFIABLE_ROWS[@]}

# Extracted so --json (stdout) and --json-file (file, alongside the human report) render
# from ONE code path. Two renderers would be a second unsynchronized pin on the same
# schema, which is how the two sides drift apart silently.
emit_json() {
  # `split("|", 1)` — maxsplit 1, so a diagnostic containing a pipe cannot shift fields.
  # Unverifiable rows get their own key rather than riding in "stale" with the diagnostic
  # sentence mis-rendered into the "config" field.
  python3 - "$LIVE_N" "$DEAD_N" "$UNVERIFIABLE_N" "$PROBES_MADE" "${DEAD_ROWS[@]:-}" "--" "${UNVERIFIABLE_ROWS[@]:-}" <<'PY'
import json, sys
live, dead, unver, probes = int(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])
rest = sys.argv[5:]
sep = rest.index("--")
def rows(xs, second):
    out = []
    for r in xs:
        if not r:
            continue
        k, _, v = r.partition("|")
        out.append({"key": k, second: v})
    return out
def unver_rows(xs):
    # Three fields: key|cause|reason. `cause` is a closed vocabulary the workflow can
    # branch on — the previous shape forced any consumer to pattern-match English prose,
    # so it sent one static remedy for four disjoint causes.
    out = []
    for r in xs:
        if not r:
            continue
        k, _, tail = r.partition("|")
        cause, _, reason = tail.partition("|")
        out.append({"key": k, "cause": cause, "reason": reason})
    return out
print(json.dumps({
    "live": live, "dead": dead, "unverifiable": unver, "probes": probes,
    "stale": rows(rest[:sep], "config"),
    "unverifiable_keys": unver_rows(rest[sep + 1:]),
}, indent=2))
PY
}

if [[ "$JSON_OUT" -eq 1 ]]; then
  emit_json
else
  echo "Cloudflare token drift check — project '$PROJECT'"
  echo "  configs scanned: ${#CONFIGS[@]}   API-token keys: ${#KEYSET[@]}   Access service tokens: ${#ACCESS_BASESET[@]}"
  # `network probes` is reported, not just computed. It is the one number that separates
  # "conclusions drawn from something measured" from "conclusions drawn from Doppler reads
  # alone", and a consumer that has it does not have to re-derive this class.
  echo "  live entries: $LIVE_N   dead entries: $DEAD_N   unverifiable: $UNVERIFIABLE_N   network probes: $PROBES_MADE"
  if [[ "$DEAD_N" -gt 0 ]]; then
    echo
    echo "STALE — these configs hold a token value Cloudflare no longer accepts:"
    for r in "${DEAD_ROWS[@]}"; do echo "  ${r%%|*}  in  ${r##*|}"; done
    echo
    echo "A rotation did not propagate. Terraform will NOT fix this: the"
    echo "doppler_secret resources carry lifecycle.ignore_changes = [value], so"
    echo "'terraform apply' reports 'No changes' while the stale value persists."
    echo "Set the live value on the 'prd' ROOT config; branch configs inherit it."
  fi
  if [[ "$UNVERIFIABLE_N" -gt 0 ]]; then
    echo
    echo "UNVERIFIABLE — no conclusion was drawn about these keys."
    echo "Nothing below is known to be stale; nothing below is known to be live."
    # Rendered per CAUSE. A single static footer is what previously told the operator to
    # "add a hostname mapping" for a key that already had one — naming a cause nothing
    # measured, which is the failure this whole section exists to avoid.
    for r in "${UNVERIFIABLE_ROWS[@]}"; do
      _k="${r%%|*}"; _rest="${r#*|}"; _cause="${_rest%%|*}"; _why="${_rest#*|}"
      echo "  [${_cause}] ${_k}  —  ${_why}"
    done
    echo
    if printf '%s\n' "${UNVERIFIABLE_ROWS[@]}" | grep -q '|no-probe-configured|'; then
      echo "  no-probe-configured: fix the DETECTOR, not the credential — add a hostname"
      echo "    mapping to access_hostname_for(). Do NOT rotate these tokens."
    fi
    if printf '%s\n' "${UNVERIFIABLE_ROWS[@]}" | grep -q '|gate-absent|'; then
      echo "  gate-absent: an UNCREDENTIALED request was not refused by Cloudflare Access."
      echo "    This is a GATE finding, not a credential finding — check the Access"
      echo "    application and policy for the host. Rotating the token changes nothing."
    fi
    if printf '%s\n' "${UNVERIFIABLE_ROWS[@]}" | grep -qE '\|(host-unreachable|probe-failed)\|'; then
      echo "  host-unreachable / probe-failed: the probe measured nothing. Re-run. Do NOT"
      echo "    rotate — an overwrite here destroys a credential no one has shown to be bad."
    fi
    if printf '%s\n' "${UNVERIFIABLE_ROWS[@]}" | grep -qE '\|(refused-unstamped|control-blocked)\|'; then
      echo "  refused-unstamped / control-blocked: something in FRONT of Cloudflare Access"
      echo "    refused the probe. Check the WAF / rate-limit / IP rules for the host, not"
      echo "    the credential."
    fi
    if printf '%s\n' "${UNVERIFIABLE_ROWS[@]}" | grep -qE '\|(unexpected-status|stamped-non-refusal|gate-indeterminate)\|'; then
      echo "  unexpected-status / stamped-non-refusal / gate-indeterminate: the edge gave an"
      echo "    answer this probe cannot classify. LIVE requires positive proof of admission"
      echo "    and DEAD requires positive proof of refusal, so neither was claimed. Do NOT"
      echo "    rotate on the strength of these rows."
    fi
    if printf '%s\n' "${UNVERIFIABLE_ROWS[@]}" | grep -q '|detector-env|'; then
      echo "  detector-env: a LOCAL fault on the runner (could not allocate a temp file)."
      echo "    No request was sent. Nothing about the credential or the host is implied."
    fi
  fi
fi

# --json-file is written AFTER the report above so both consumers see the same scan.
# A write failure is exit 2, not a warning: the caller branches its operator email on
# this file, and a missing file would silently take the "could not determine" arm and
# report a wrong cause — the defect class this whole script exists to prevent.
if [[ -n "$JSON_FILE" ]]; then
  emit_json > "$JSON_FILE" || { echo "ERROR: could not write --json-file '$JSON_FILE'" >&2; exit 2; }
fi

# POSITIVE-WORK FLOOR. The non-vacuity gate above counts enumerated key NAMES, which is a
# different question from whether anything was ever measured. Every value read is
# `doppler secrets get ... 2>/dev/null` followed by a skip-on-empty, so a token scoped to
# read names but not VALUES — or a Doppler 5xx mid-scan — makes every read empty, every
# loop `continue`, and the script fall through to exit 0 with `live: 0  dead: 0`. The
# caller's ladder reads that as `clean`: no email, no annotation, green job, and the
# heartbeat checks in OK. Reproduced: 0 curl invocations, exit 0.
#
# Exit 2 routes to the existing `unavailable` arm, whose email already says the right
# thing ("the detector could not run"); that channel was simply unreachable from here.
# Keyed on CONCLUSIONS DRAWN, not probes made. A half-propagated pair and an unmappable
# base are real findings reached without any probe, and gating on PROBES_MADE alone turned
# both into exit 2 "the detector could not run" — replacing a true finding with a false
# claim of coverage failure, which is the same class of lie in the other direction.
if (( LIVE_N + DEAD_N + UNVERIFIABLE_N == 0 )); then
  echo "ERROR: enumerated ${#KEYSET[@]} API key(s) and ${#ACCESS_BASESET[@]} Access base(s) but PROBED ZERO values." >&2
  echo "       Nothing was measured, so this run cannot report a clean fleet. Most likely the" >&2
  echo "       Doppler token can read secret NAMES but not VALUES, or a read failed mid-scan." >&2
  exit 2
fi

# Either condition is non-zero: a dead token is a live outage waiting, and an unverifiable
# one means this run cannot claim the fleet is clean.
[[ "$DEAD_N" -gt 0 || "$UNVERIFIABLE_N" -gt 0 ]] && exit 1
exit 0
