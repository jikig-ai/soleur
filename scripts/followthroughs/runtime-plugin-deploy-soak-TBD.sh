#!/usr/bin/env bash
# Follow-through soak for the runtime-plugin deploy gap
# (plan 2026-07-02-fix-runtime-plugin-deploy-to-concierge-host, ADR-080).
#
# This fix makes a runtime-plugin merge (plugins/soleur/** minus docs/ and test/)
# rebuild+deploy the web-platform image so the Concierge host mount re-seeds. This
# soak PROVES the pipeline end-to-end: after the FIRST post-fix runtime-plugin
# merge, the production host's baked build SHA must catch up to that merge's SHA.
#
# NOTE: this fix's OWN merge does NOT deploy — it touches only .github/workflows,
# plugins/soleur/test/ (excluded by the denylist), knowledge-base, and this script.
# So the soak deliberately keys on the NEXT runtime-plugin merge, not this one.
#
# Signal is observable WITHOUT any secret:
#   - gh: find the latest successful web-platform-release run on main whose head
#         commit touched a RUNTIME plugin path (plugins/soleur/** minus docs/test).
#   - curl: app.soleur.ai/health is a PUBLIC endpoint exposing .build_sha.
#   PASS iff such a run exists AND health .build_sha == that run's headSha
#   (the host re-seeded from the freshly built image).
#
# Exit codes (scripts/sweep-followthroughs.sh contract):
#   0 = PASS      (a runtime-plugin merge deployed and the host caught up → close)
#   1 = FAIL      (a runtime-plugin merge's run succeeded but health build_sha
#                  never matched → the deploy/re-seed did NOT reach the host)
#   * = TRANSIENT (no runtime-plugin merge has deployed yet, or a network/API
#                  error → leave open, retry next sweep)
#
# Ship-phase enrollment (issue filed at ship time — frontmatter `issue: TBD`):
#   1. rename TBD → the real tracking-issue number in this filename.
#   2. add `<!-- soleur:followthrough runtime-plugin-deploy-soak-<issue> -->`
#      and the `follow-through` label to the tracking issue.

set -uo pipefail

# soleur:followthrough runtime-plugin-deploy-soak-TBD

HEALTH_URL="${SOLEUR_HEALTH_URL:-https://app.soleur.ai/health}"
RUNTIME_RE='^plugins/soleur/(?!docs/|test/)'  # PCRE denylist (grep -P)

# Latest successful web-platform-release runs on main (newest first).
runs_json=$(gh run list --workflow=web-platform-release.yml --branch main \
  --status success --limit 20 --json headSha,databaseId 2>/dev/null) || {
  echo "TRANSIENT: gh run list failed for web-platform-release.yml" >&2
  exit 2
}
if ! printf '%s' "$runs_json" | jq -e 'type=="array" and length>0' >/dev/null 2>&1; then
  echo "TRANSIENT: no successful web-platform-release runs on main yet" >&2
  exit 2
fi

# Find the newest run whose head commit touched a runtime plugin path.
watch_sha=""
while IFS= read -r sha; do
  [[ -z "$sha" ]] && continue
  files=$(gh api "repos/{owner}/{repo}/commits/${sha}" \
    --jq '.files[].filename' 2>/dev/null) || continue
  if printf '%s\n' "$files" | grep -qP "$RUNTIME_RE"; then
    watch_sha="$sha"
    break
  fi
done < <(printf '%s' "$runs_json" | jq -r '.[].headSha')

if [[ -z "$watch_sha" ]]; then
  echo "TRANSIENT: no post-fix runtime-plugin merge has deployed yet — pipeline unexercised" >&2
  exit 2
fi

health_build_sha=$(curl -sS --max-time 30 "$HEALTH_URL" 2>/dev/null | jq -r '.build_sha // empty' 2>/dev/null)
if [[ -z "$health_build_sha" ]]; then
  echo "TRANSIENT: could not read .build_sha from ${HEALTH_URL}" >&2
  exit 2
fi

echo "Runtime-plugin deploy watch SHA: ${watch_sha}"
echo "Production health build_sha:      ${health_build_sha}"

# Compare on the common prefix length (health may expose a short SHA).
len=${#health_build_sha}
if [[ "${watch_sha:0:$len}" == "$health_build_sha" ]]; then
  echo "PASS: production host build_sha matches the runtime-plugin merge — pipeline re-seeded the mount. Close the tracking issue."
  exit 0
fi

echo "FAIL: a runtime-plugin merge (${watch_sha}) built+deployed successfully but production build_sha (${health_build_sha}) never caught up — the image rebuild did NOT re-seed the host. Investigate ci-deploy.sh seed + ADR-080." >&2
exit 1
