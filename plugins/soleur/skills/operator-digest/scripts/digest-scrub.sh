#!/usr/bin/env bash
# Tuned fail-closed scrub gate for the operator weekly digest (#5085, plan §L3).
#
# Runs as a deterministic GitHub Actions post-step on the rendered digest.md,
# BEFORE the issue is posted. It is DISTINCT from incident/redact-sentinel.sh:
# that gate is tuned for human-reviewed PIRs and aborts on email/UUID/IPv4 — which
# would silently kill a business digest on benign first-party content (ops@jikigai.com
# is in the ledger) while still missing named PII. This gate is tuned for the
# digest's content profile: abort on true secrets, abort on a FOREIGN email
# (the customer-email leak class), but only WARN on UUID/IPv4 (legitimate in prose).
# Named PII ("Jane Doe") cannot be caught by a regex — that control is upstream
# (the skill emits incident SUMMARIES from PIR frontmatter/title only, never bodies).
#
# Exit codes:
#   0 = clean — no abort-class match (UUID/IPv4/first-party-email warns are allowed)
#   1 = abort — a secret, a foreign email, OR a grep error (real fail-closed)
#   2 = invalid arguments — missing or unreadable file
#
# Output is meta-redacted (never the full token), mirroring redact-sentinel.sh.
set -uo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: digest-scrub.sh <path-to-digest.md>" >&2
  exit 2
fi
FILE="$1"
if [[ ! -r "${FILE}" ]]; then
  echo "digest-scrub: file not readable: ${FILE}" >&2
  exit 2
fi

# First-party email domains: a digest summarizing the operator's own ledger legitimately
# names the operator's own contact address. A foreign domain in the digest is the
# customer-email leak class and MUST abort.
FIRST_PARTY_DOMAINS=(jikigai.com soleur.ai)

# Secret classes — any match ABORTS. Class-name set + bodies synced with redact-engine.py
# 2026-07-06 (#6045); NAME-level parity is CI-enforced by plugins/soleur/test/redact-class-parity.test.sh.
# Regex-BODY parity is a named non-goal (ERE here vs Python `re` in the engine — not cheaply
# comparable); bodies below are a superset of the engine's shared classes as of the sync date and
# pattern edits get manual cross-review. The engine's email/UUID/IPv4 classes are handled OUTSIDE
# this map (email via first-party domain logic below; UUID/IPv4 as WARN-only), so the parity guard
# allowlists them.
declare -A SECRET=(
  [JWT]='eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}'
  [stripe_key]='\b(sk|pk|rk)_(live|test)_[A-Za-z0-9]{16,}\b'
  [stripe_whsec]='\bwhsec_[A-Za-z0-9]{16,}\b'
  [stripe_acct]='\bacct_[A-Za-z0-9]{16,}\b'
  [stripe_cust_pi_seti_sub_in]='\b(cus|pi|seti|sub|in)_[A-Za-z0-9]{14,}\b'
  [env_var]='\b(DOPPLER|SENTRY|STRIPE|SUPABASE|OPENAI|ANTHROPIC|GITHUB|VERCEL|CLOUDFLARE|HETZNER|FLAGSMITH|RESEND|TAILSCALE)_[A-Z_]+=[^[:space:]]+'
  [github_token]='\b(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{30,}\b|\bgithub_pat_[A-Za-z0-9_]{20,}\b'
  [anthropic_key]='\bsk-ant-[A-Za-z0-9_-]{32,}\b'
  [openai_key]='\bsk-(proj-)?[A-Za-z0-9_-]{20,}\b'
  [supabase_pat]='\bsbp_[a-z0-9]{20,}\b|\b(sb_secret|sb_publishable)_[A-Za-z0-9]{20,}\b'
  [pem_private_key]='-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----'
  [doppler_token]='\bdp\.(st|pt|ct|sa|scim|audit)\.[A-Za-z0-9._-]{16,}'
  [slack_token]='\bxox[baprsce]-[A-Za-z0-9-]{10,}'
)
SECRET_ORDER=(JWT stripe_key stripe_whsec stripe_acct stripe_cust_pi_seti_sub_in env_var github_token anthropic_key openai_key supabase_pat pem_private_key doppler_token slack_token)

EMAIL_RE='\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b'
UUID_RE='\b[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\b'
IPV4_RE='\b(([0-9]{1,3})\.){3}[0-9]{1,3}\b'

abort=0

emit() { printf 'digest-scrub %s: %s\n' "$1" "$2" >&2; }

# scan_secret <class> <pattern> — abort on any match; abort on grep error (fail-closed).
scan_secret() {
  local class="$1" pattern="$2" out
  # INVARIANT: `local rc=$?` MUST be the statement immediately after the grep assignment.
  # Anything between them (even another `local`) resets $? to that statement's exit (0) and
  # silently defeats the grep-error fail-closed path. Do not insert code here.
  out="$(grep -oE -e "$pattern" "$FILE")"
  local rc=$?
  if (( rc >= 2 )); then
    emit ABORT "grep error (rc=$rc) scanning ${class} — fail-closed"
    abort=1
    return
  fi
  if (( rc == 0 )) && [[ -n "$out" ]]; then
    emit ABORT "secret-class ${class} matched (post withheld)"
    abort=1
  fi
}

for class in "${SECRET_ORDER[@]}"; do
  scan_secret "$class" "${SECRET[$class]}"
done

# Email: abort on a FOREIGN domain; warn (allow) on first-party.
emails="$(grep -oE -e "$EMAIL_RE" "$FILE")"; erc=$?
if (( erc >= 2 )); then
  emit ABORT "grep error (rc=$erc) scanning email — fail-closed"; abort=1
elif (( erc == 0 )); then
  while IFS= read -r addr; do
    [[ -z "$addr" ]] && continue
    domain="${addr##*@}"; domain="${domain,,}"
    first_party=0
    for d in "${FIRST_PARTY_DOMAINS[@]}"; do [[ "$domain" == "$d" ]] && first_party=1 && break; done
    if (( first_party )); then
      emit WARN "first-party email (${domain}) — allowed"
    else
      emit ABORT "foreign email domain (${domain}) — possible customer PII"
      abort=1
    fi
  done <<< "$emails"
fi

# UUID / IPv4: WARN only (legitimate in incident/build prose). grep error still aborts.
for pair in "UUID:${UUID_RE}" "IPv4:${IPV4_RE}"; do
  cls="${pair%%:*}"; pat="${pair#*:}"
  out="$(grep -oE -e "$pat" "$FILE")"; rc=$?
  if (( rc >= 2 )); then emit ABORT "grep error (rc=$rc) scanning ${cls} — fail-closed"; abort=1
  elif (( rc == 0 )) && [[ -n "$out" ]]; then emit WARN "${cls} present in prose — allowed (not a secret)"; fi
done

exit "$abort"
