#!/usr/bin/env bash
# Pre-write redaction sentinel for /soleur:incident (#2725, plan FR3).
#
# Scans a draft PIR (or any text file) for un-redacted secrets / PII matching
# the regex classes in plan FR3. Runs BEFORE inline-emit to operator transcript
# AND before disk commit (Phase 6 of SKILL.md).
#
# Exit codes (plan FR3):
#   0 = clean — no matches found
#   1 = redaction needed — at least one match found
#   2 = invalid arguments — missing or unreadable file
#
# Output format per FR3:
#   at offset N: <8-prefix>***<8-suffix> matched pattern <class>
# Never emits the full matched token (meta-redaction).
#
# Regex classes (verbatim from plan FR3):
#   JWT         — three-segment JWT
#   email       — RFC 5322 simplified
#   UUID        — version-agnostic v1-v5
#   stripe_key  — sk_/pk_/rk_ live/test
#   stripe_whsec— webhook signing secret (highest-PII)
#   stripe_acct — Connect account
#   stripe_cust_pi_seti_sub_in — customer/payment-intent/setup-intent/subscription/invoice
#   IPv4        — dotted-quad (IPv6 deferred — see TODO below)
#   env_var     — DOPPLER/SENTRY/STRIPE/SUPABASE/OPENAI/ANTHROPIC/GITHUB/VERCEL/CLOUDFLARE prefix=value
#
# TODO(post-MVP, #2725 FR3): IPv6 regex per `wg-when-deferring-a-capability-create-a` — file follow-up after first real-incident.
set -uo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: redact-sentinel.sh <path-to-file>" >&2
  exit 2
fi

FILE="$1"
if [[ ! -r "${FILE}" ]]; then
  echo "redact-sentinel: file not readable: ${FILE}" >&2
  exit 2
fi

declare -A PATTERNS=(
  [JWT]='eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}'
  [email]='\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b'
  [UUID]='\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b'
  [stripe_key]='\b(sk|pk|rk)_(live|test)_[A-Za-z0-9]{16,}\b'
  [stripe_whsec]='\bwhsec_[A-Za-z0-9]{16,}\b'
  [stripe_acct]='\bacct_[A-Za-z0-9]{16,}\b'
  [stripe_cust_pi_seti_sub_in]='\b(cus|pi|seti|sub|in)_[A-Za-z0-9]{14,}\b'
  [IPv4]='\b(([0-9]{1,3})\.){3}[0-9]{1,3}\b'
  [env_var]='\b(DOPPLER|SENTRY|STRIPE|SUPABASE|OPENAI|ANTHROPIC|GITHUB|VERCEL|CLOUDFLARE)_[A-Z_]+=[^[:space:]]+'
  # Added 2026-05-14 (review): the 5 highest-likelihood bare-token classes in a Soleur PIR.
  # security-sentinel + user-impact-reviewer concurred on these as P1 gaps in the original FR3 set.
  [github_token]='\b(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{30,}\b|\bgithub_pat_[A-Za-z0-9_]{20,}\b'
  [anthropic_key]='\bsk-ant-[A-Za-z0-9_-]{32,}\b'
  [openai_key]='\bsk-(proj-)?[A-Za-z0-9_-]{20,}\b'
  [supabase_pat]='\bsbp_[a-z0-9]{20,}\b|\b(sb_secret|sb_publishable)_[A-Za-z0-9]{20,}\b'
  [pem_private_key]='-----BEGIN ((RSA|EC|OPENSSH|PGP|DSA) )?PRIVATE KEY-----'
)

# Iterate in a stable order so callers and tests see deterministic output.
CLASSES=(JWT email UUID stripe_key stripe_whsec stripe_acct stripe_cust_pi_seti_sub_in IPv4 env_var github_token anthropic_key openai_key supabase_pat pem_private_key)

hits=0
for class in "${CLASSES[@]}"; do
  pattern="${PATTERNS[${class}]}"
  while IFS= read -r match; do
    [[ -z "${match}" ]] && continue
    len=${#match}
    if (( len <= 16 )); then
      printf 'at offset %d: %s*** matched pattern %s\n' "${len}" "${match}" "${class}"
    else
      printf 'at offset %d: %s***%s matched pattern %s\n' "${len}" "${match:0:8}" "${match: -8}" "${class}"
    fi
    hits=$((hits + 1))
  done < <(grep -oE -e "${pattern}" "${FILE}" 2>/dev/null || true)
done

if (( hits > 0 )); then
  exit 1
fi
exit 0
