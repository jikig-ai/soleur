#!/usr/bin/env bash
# Post-merge filing bootstrap for #8160 — collapses the scriptable hops of the
# upstream-ask filing into one script (hr-multi-step-post-merge-bootstrap-script).
#
# AUTH BOUNDARY, stated because everything else here is scripted: this script
# cannot send email (no outbound-mail capability — the OPERATOR sends the
# scrubbed body verbatim to support@cognition.ai) and cannot click Devin `/bug`
# (interactive). What it DOES do:
#
#   prepare  — re-scrub the package, resolve the merge-SHA blob permalink,
#              and write the filing artifacts to an output dir:
#                email-body.txt  (package verbatim + the permalink it cites)
#                mailto.txt      (mailto: assist — pointer-body if the verbatim
#                                 body exceeds URL-length limits)
#                bug-body.txt    (the /bug arm: Section-3 defect-class items)
#   log      — append a posting-log entry on #8160 (destination/date/state/note)
#   attest   — record the verbatim-send attestation on #8160. The attestation is
#              honest about its own limit: "sent" proves the operator clicked
#              send, NOT delivery — a bounce would leave the log stale, and that
#              residual is recorded rather than smoothed over.
#   verify   — confirm the watcher is alive: first scheduled-devin-docs-drift
#              run exists, and apply-sentry-infra.yml applied the monitor.
#
# Usage:
#   scripts/file-upstream-ask-8160.sh prepare [--sha <merge-sha>] [--out <dir>]
#   scripts/file-upstream-ask-8160.sh log --dest <channel> --state <state> [--note "…"]
#   scripts/file-upstream-ask-8160.sh attest [--note "…"]
#   scripts/file-upstream-ask-8160.sh verify
#
# Suggested --state vocabulary: pending-send | sent | filed | responded | declined.
# NOTE: --note/--state text lands VERBATIM on a public-repo issue comment — no
# session IDs, customer names, tokens, or other identifiers.
#
# Exit 0 = the step completed (or reported honestly what it could not reach).
# Non-zero = the step could not run at all (missing tool, missing package,
# failed scrub, unreachable gh).

set -euo pipefail

REPO="jikig-ai/soleur"
ISSUE="8160"
BRANCH="feat-devin-upstream-asks-posture"
PACKAGE="knowledge-base/project/specs/feat-devin-upstream-asks-posture/upstream-asks.md"
WATCHER="scheduled-devin-docs-drift.yml"
SENTRY_APPLY="apply-sentry-infra.yml"

die() { echo "FATAL: $*" >&2; exit 1; }

need_gh() {
  command -v gh >/dev/null 2>&1 || die "gh unavailable"
  # GH_TOKEN must be EXPLICITLY available to every GitHub CLI probe — a gh that
  # silently has no auth fails mid-run after earlier steps already posted.
  gh auth status >/dev/null 2>&1 || die "gh not authenticated (GH_TOKEN or gh auth login required)"
}

resolve_sha() { # → prints the merge SHA the permalink should pin to
  local sha="${1:-}"
  if [[ -z "$sha" ]]; then
    sha="$(gh pr list --repo "$REPO" --state merged --head "$BRANCH" --limit 1 \
      --json mergeCommit --jq '.[0].mergeCommit.oid // empty' 2>/dev/null || true)"
  fi
  if [[ -z "$sha" ]]; then
    # Fallback: the newest commit on origin/main that touched the package.
    sha="$(git log origin/main -1 --format=%H -- "$PACKAGE" 2>/dev/null || true)"
  fi
  [[ "$sha" =~ ^[0-9a-f]{40}$ ]] || die "could not resolve a merge SHA — pass --sha <merge-sha>"
  printf '%s' "$sha"
}

permalink_for() { # $1=sha → blob permalink (SHA-pinned: the live spec path re-archives)
  printf 'https://github.com/%s/blob/%s/%s' "$REPO" "$1" "$PACKAGE"
}

cmd_prepare() {
  local sha="" out=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --sha) sha="${2:-}"; [[ -n "$sha" ]] || die "--sha requires a value"; shift 2 ;;
      --out) out="${2:-}"; [[ -n "$out" ]] || die "--out requires a value"; shift 2 ;;
      *) die "unknown prepare arg: $1" ;;
    esac
  done

  need_gh
  # Resolve repo-relative paths from the work tree root — callers may invoke this
  # script from any CWD (the Devin tool envelope omits .cwd, #8254).
  cd "$(git rev-parse --show-toplevel 2>/dev/null)" || die "not inside a git work tree"
  command -v python3 >/dev/null 2>&1 || die "python3 required for the mailto assist"
  [[ -r "$PACKAGE" ]] || die "package not readable: $PACKAGE"

  # Re-scrub BEFORE anything derived from the package is emitted — the scrubbed
  # draft IS the posted body, so the local copy must pass the same predicate the
  # posted body would.
  bash scripts/upstream-report-scrub.sh "$PACKAGE" || die "scrub gate failed — do not file"

  sha="$(resolve_sha "$sha")"
  local permalink; permalink="$(permalink_for "$sha")"

  # --out must be absolute: a relative one would resolve under the repo root
  # after the cd above, and the printed path would not be the one the operator
  # can open.
  if [[ -n "$out" ]]; then
    [[ "$out" == /* ]] || die "--out must be an absolute path"
    mkdir -p "$out"
  else
    # The dir IS the deliverable — email-body.txt, mailto.txt and bug-body.txt
    # must survive script exit for the operator to send them; a trap would
    # delete the artifacts this command exists to write.
    # lint-trap-ownership: ok output dir intentionally outlives the process
    out="$(mktemp -d /tmp/upstream-8160.XXXXXXXX)"
  fi

  # The email body: the verbatim package, prefixed by the permalink it cites.
  {
    printf 'Filing package (permalinks at merge commit %s):\n%s\n\n' "$sha" "$permalink"
    cat "$PACKAGE"
  } > "$out/email-body.txt"

  # mailto assist. URL-length limits vary (~2000 chars is the safe ceiling for
  # broad client compatibility); the package exceeds it, so the assist carries a
  # pointer body and the verbatim body is paste text.
  local subject="Upstream requests: Devin Cloud plugin subagents + hook dispatch (jikig-ai/soleur #8160)"
  local pointer_body="Filing package: ${permalink}
(scrubbed verbatim body pasted below — or see email-body.txt in the filing artifacts)"
  {
    printf 'Full-verbatim body exceeds safe mailto URL length — use paste text.\n\n'
    printf 'Pointer mailto (subject + permalink body):\n\n'
    python3 - "$subject" "$pointer_body" <<'PY'
import sys, urllib.parse
s, b = sys.argv[1], sys.argv[2]
print("mailto:support@cognition.ai?subject=" + urllib.parse.quote(s) + "&body=" + urllib.parse.quote(b))
PY
  } > "$out/mailto.txt"

  # /bug arm — the defect-class items (Section 3 items 2-4): dead SessionStart
  # source matchers + unverified permissionDecision values + the .cwd envelope
  # gap. Section 1 is no longer defect-framed (docs were corrected to match the
  # measurement — see the package's Timeline paragraph).
  # /bug is interactive-only: the OPERATOR pastes this body and reviews whatever
  # else /bug attaches (session diagnostics/transcript) BEFORE submitting — the
  # scrub gate cannot reach a payload we cannot see.
  cat > "$out/bug-body.txt" <<'EOF'
Defect report — Devin CLI hook contract items (from jikig-ai/soleur #8160 filing, Section 3 items 2-4):

1. SessionStart source matchers `startup`, `resume`, `clear`, `compact` are documented but never dispatch — only the empty matcher `""` fires (measured via envelope capture). Hooks registered on any source matcher are dead.

2. `permissionDecision` values `"ask"` and `"defer"` are registered in hook responses but never observed driven — a hook emitting either may be ignored or misrouted. The `PermissionRequest` event is likewise unverified.

3. The tool envelope omits `.cwd` — hooks resolve the working directory via DEVIN_PROJECT_DIR → CLAUDE_PROJECT_DIR → $PWD, which resolves the wrong repository when the hook process's PWD differs from the command's working directory (e.g. a `git commit` issued inside a worktree is evaluated against the main checkout's branch).

Please document which matchers, decision values, and envelope fields are contractually supported on each surface.

Capability-parity request only; any personal-data workflows remain subject to a separate Art. 28 DPA.
EOF

  # Re-scrub the generated /bug body — it is static heredoc text today, but a
  # future edit to it must not slip an exposure past the gate that guards the
  # package.
  bash scripts/upstream-report-scrub.sh "$out/bug-body.txt" || die "bug-body scrub failed — do not file"

  echo "prepared in: $out"
  echo "permalink:   $permalink"
  echo "next (operator steps — this script cannot send mail or click /bug):"
  echo "  1. OPERATOR sends $out/email-body.txt verbatim to support@cognition.ai (mailto assist in mailto.txt)"
  echo "  2. OPERATOR files the Devin /bug arm by pasting $out/bug-body.txt — reviewing the full payload /bug attaches before submit"
  echo "then:"
  echo "  scripts/file-upstream-ask-8160.sh log --dest support@cognition.ai --state pending-send"
  echo "  scripts/file-upstream-ask-8160.sh attest          # after the operator sends"
  echo "  scripts/file-upstream-ask-8160.sh verify          # watcher liveness"
}

cmd_log() {
  local dest="" state="" note=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dest)  dest="${2:-}"; [[ -n "$dest" ]] || die "--dest requires a value"; shift 2 ;;
      --state) state="${2:-}"; [[ -n "$state" ]] || die "--state requires a value"; shift 2 ;;
      --note)  note="${2:-}"; shift 2 ;;
      *) die "unknown log arg: $1" ;;
    esac
  done
  [[ -n "$dest" && -n "$state" ]] || die "log requires --dest and --state"
  need_gh
  local body="**Posting log** — destination: \`${dest}\` · date: $(date -u +%Y-%m-%d) · state: \`${state}\`"
  [[ -n "$note" ]] && body="${body} · note: ${note}"
  gh issue comment "$ISSUE" --repo "$REPO" --body "$body"
  echo "posting log appended to #${ISSUE} (dest=${dest} state=${state})"
}

cmd_attest() {
  local note=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --note) note="${2:-}"; shift 2 ;;
      *) die "unknown attest arg: $1" ;;
    esac
  done
  need_gh
  local body="**Verbatim-send attestation** — $(date -u +%Y-%m-%d): operator confirms the scrubbed \`upstream-asks.md\` draft (scrub gate exit 0) was sent verbatim to \`support@cognition.ai\`. **Delivery is unverifiable** — 'sent' records the send action, not receipt; a bounce would leave this state stale. The posting log is the record."
  [[ -n "$note" ]] && body="${body} Note: ${note}"
  gh issue comment "$ISSUE" --repo "$REPO" --body "$body"
  echo "attestation recorded on #${ISSUE}"
}

cmd_verify() {
  need_gh
  local rc=0 out=""
  echo "== watcher runs (${WATCHER}) =="
  out="$(gh run list --repo "$REPO" --workflow="$WATCHER" --limit 3 \
    --json databaseId,status,conclusion,createdAt \
    --jq '.[] | "\(.databaseId)  \(.status)/\(.conclusion)  \(.createdAt)"' 2>/dev/null)" || rc=$?
  if (( rc != 0 )); then echo "(query failed: gh exited ${rc} — could not confirm)"
  elif [[ -z "$out" ]]; then echo "(no runs returned — watcher has not run yet)"
  else printf '%s\n' "$out"; fi
  rc=0; out=""
  echo "== sentry-infra applies (${SENTRY_APPLY}) =="
  out="$(gh run list --repo "$REPO" --workflow="$SENTRY_APPLY" --limit 3 \
    --json databaseId,status,conclusion,createdAt \
    --jq '.[] | "\(.databaseId)  \(.status)/\(.conclusion)  \(.createdAt)"' 2>/dev/null)" || rc=$?
  if (( rc != 0 )); then echo "(query failed: gh exited ${rc} — could not confirm)"
  elif [[ -z "$out" ]]; then echo "(no runs returned — apply workflow has not run yet)"
  else printf '%s\n' "$out"; fi
  echo
  echo "expected: ≥1 completed ${WATCHER} run, and a successful ${SENTRY_APPLY} run at/after the merge that added sentry_cron_monitor.scheduled_devin_docs_drift."
}

case "${1:-}" in
  prepare) shift; cmd_prepare "$@" ;;
  log)     shift; cmd_log "$@" ;;
  attest)  shift; cmd_attest "$@" ;;
  verify)  shift; cmd_verify "$@" ;;
  *) sed -n '2,33p' "$0"; exit 2 ;;
esac
