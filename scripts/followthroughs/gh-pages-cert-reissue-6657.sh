#!/usr/bin/env bash
# Follow-through verification for the #6657 GitHub Pages cert reissue.
#
# The reissue routine (cron-gh-pages-cert-reissue) ships in PR #6676, but the
# LIVE remediation is post-merge + post-deploy: it needs (a) the container
# redeploy that carries the new function, (b) the DNS-edit token IaC applied
# (out-of-band JIT apply per infra/cf-cert-reissue-token.tf), then (c) a single
# scripted trigger-cron fire. This script verifies the end state — the cert
# actually recovered — so the remediation cannot be silently forgotten.
#
# Returns:
#   0 = PASS  (cert state ∈ {issued, approved} → remediation complete; sweeper
#              auto-closes #<this issue>)
#   1 = FAIL  (cert still bad_authz/failed → remediation not yet done; sweeper
#              leaves the issue open and comments)
#   2 = TRANSIENT (gh/API error → sweeper retries next day)
#
# Required env: GH_TOKEN (for gh api)

set -uo pipefail

if [[ -z "${GH_TOKEN:-}" ]]; then echo "TRANSIENT: GH_TOKEN not set" >&2; exit 2; fi

STATE=$(gh api /repos/jikig-ai/soleur/pages \
  --jq '.https_certificate.state' 2>/dev/null) || {
  echo "TRANSIENT: gh api /pages failed" >&2
  exit 2
}

case "$STATE" in
  issued|approved)
    echo "PASS: GitHub Pages cert state=${STATE} (remediation complete)"
    exit 0
    ;;
  "")
    echo "TRANSIENT: empty cert state from API" >&2
    exit 2
    ;;
  *)
    echo "FAIL: GitHub Pages cert state=${STATE} — reissue not yet applied" >&2
    echo "      Remediate: apply infra/cf-cert-reissue-token.tf, then fire" >&2
    echo "      cron/gh-pages-cert-reissue.manual-trigger via trigger-cron." >&2
    exit 1
    ;;
esac
