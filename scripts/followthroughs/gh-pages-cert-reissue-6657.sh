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
#   3 = CANNOT ESTABLISH (the API answered but carries no https_certificate object at all —
#       a measured absence, not a failure; see the note at the read below)
#   0 = PASS  (cert state ∈ {issued, approved} → remediation complete; sweeper
#              auto-closes #<this issue>)
#   1 = FAIL  (cert still bad_authz/failed → remediation not yet done; sweeper
#              leaves the issue open and comments)
#   2 = TRANSIENT (gh/API error → sweeper retries next day)
#
# Required env: GH_TOKEN (for gh api)

set -uo pipefail

if [[ -z "${GH_TOKEN:-}" ]]; then echo "TRANSIENT: GH_TOKEN not set" >&2; exit 2; fi

# READ THE WHOLE OBJECT, NOT THE PROJECTED FIELD. `--jq '.https_certificate.state'` collapses
# three different situations into one empty string, and the probe then reported TRANSIENT for
# all of them — a permanent quiet retry that can never resolve. Measured 2026-09-18, live:
#
#   $ gh api repos/jikig-ai/soleur/pages --jq '{cname, https_certificate}'
#   {"cname":"soleur.ai","https_certificate":null}
#   $ gh api repos/jikig-ai/soleur/pages --jq '.https_certificate.state'   # -> empty line
#
# The request SUCCEEDS; Pages simply carries no HTTPS certificate object for this domain. That
# is a measured fact about the world, not a network blip, so it takes exit 3 (CANNOT ESTABLISH
# — the probe could not measure and says why) rather than exit 2 (TRANSIENT — retry, something
# was flaky). Distinguishing them is the whole point: a probe that cannot tell "the API is
# down" from "there is nothing to read" retries forever and alarms never.
RAW=$(gh api /repos/jikig-ai/soleur/pages 2>/dev/null) || {
  echo "TRANSIENT: gh api /pages failed (the request itself did not complete)" >&2
  exit 2
}

# `// "__absent__"` covers BOTH a JSON null and a missing key; a bare `.state` cannot tell them
# apart from a genuinely empty string.
STATE=$(printf '%s' "$RAW" | jq -r '.https_certificate.state // "__absent__"' 2>/dev/null) || {
  echo "TRANSIENT: /pages responded but the body did not parse as JSON" >&2
  exit 2
}

case "$STATE" in
  issued|approved)
    echo "PASS: GitHub Pages cert state=${STATE} (remediation complete)"
    exit 0
    ;;
  __absent__|"")
    echo "CANNOT ESTABLISH: /pages answered, but it carries no https_certificate object" >&2
    echo "      (measured shape: https_certificate = null). Pages has no HTTPS certificate" >&2
    echo "      for this domain, so there is no state to read — this is NOT an API failure" >&2
    echo "      and retrying will not change it. Configure Pages HTTPS for the custom domain," >&2
    echo "      or close this tracker if the remediation has moved off GitHub Pages." >&2
    exit 3
    ;;
  *)
    echo "FAIL: GitHub Pages cert state=${STATE} — reissue not yet applied" >&2
    echo "      Remediate: apply infra/cf-cert-reissue-token.tf, then fire" >&2
    echo "      cron/gh-pages-cert-reissue.manual-trigger via trigger-cron." >&2
    exit 1
    ;;
esac
