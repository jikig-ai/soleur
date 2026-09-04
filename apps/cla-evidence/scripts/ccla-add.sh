#!/usr/bin/env bash
# ccla-add.sh — record (or withdraw) a Corporate CLA designation in the public
# coverage map at apps/cla-evidence/roster/ccla-roster.json.
#
# A script rather than a skill, matching the two operator-facing CLA
# affordances that already live in this directory (gdpr-override.sh,
# inspect-evidence.sh), each with a runbook section.
#
# WHAT THIS ENFORCES, AND WHY IT IS HERE AND NOT ONLY IN CI
# ---------------------------------------------------------
# Contribution-triggered entry: an account enters the roster only at or after
# that person has themselves signed the Individual CLA on a pull request here.
# The CLO ruling of 2026-09-04 makes this load-bearing — the Art. 6(1)(f)
# balancing, the Art. 13 notice route and the Art. 17(3)(e) ground all rest on
# it. It is enforced at BOTH the write path (here) and in CI, deliberately:
# CI alone would catch the violation only after the association had been
# committed, and the surface is a public git repository from which nothing can
# be erased. Refusing to write it is the only real remedy.
#
# WHAT THE ROSTER MAY NOT CARRY
# -----------------------------
# No name, title, email address or postal address — ever, and permanently
# rather than pending a decision. Identity rests in the executed instrument,
# held off-repo on the encrypted operator drive. The schema is `.strict()`, so
# an attempt to add such a field fails validation below rather than landing.
#
# Modes:
#   add     — record an organisation and its designated accounts
#   remove  — record a withdrawal of designation (CCLA §5 makes this an email;
#             leaving it unbuilt would make withdrawing an ex-employee's
#             authorization a hand-edit of a legal record, which is the one
#             direction where a missing affordance is security-relevant)
#
# Dry run: CCLA_ADD_DRY_RUN=1 resolves logins, enforces the ledger check,
# emits the roster it WOULD write, and opens no PR and pushes nothing.
#
# Exit codes:
#   0  — roster written (PR opened, or dry-run emitted)
#   2  — pre-flight failure (gh unavailable/unauthed, dirty tree, bad input)
#   3  — roster failed schema validation
#   4  — contribution-triggered entry violation (an account has not signed the ICLA)
#   64 — usage error

set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage:
  ccla-add.sh add    --record-ref CCLA-0001
                     (--org "Legal Name" | --sole-trader)
                     --signed-at 2026-09-04T00:00:00Z
                     --authorized-from 2026-09-04T00:00:00Z
                     --instrument-sha256 <64-hex>
                     --login <github-login> [--login <github-login> ...]
                     [--cla-git-sha <sha>]

  ccla-add.sh remove --record-ref CCLA-0001 --login <github-login>
                     --withdrawn-at 2026-09-04T00:00:00Z

  CCLA_ADD_DRY_RUN=1 ccla-add.sh ...   # resolve + validate, write nothing

Notes:
  --sole-trader omits the organisation's legal name (published as null), for a
  counterparty whose legal name IS a natural person's name. The name is held
  off-repo with the instrument. See the CLO ruling, amendment B1-c-2.
USAGE
  exit 64
}

# $1 = message, $2 = exit code. Note $1, NOT $* — "$*" would splice the exit
# code onto the end of the operator-facing message.
die() { echo "::error::$1" >&2; exit "${2:-2}"; }

MODE="${1:-}"
case "$MODE" in
  add|remove) shift ;;
  "") usage ;;
  *) echo "::error::unknown mode: $MODE" >&2; usage ;;
esac
[[ "$MODE" =~ ^(add|remove)$ ]] || die "internal: mode passed case but failed regex" 64

DRY_RUN="${CCLA_ADD_DRY_RUN:-0}"
REPO="${CCLA_ADD_REPO:-jikig-ai/soleur}"
BASE_BRANCH="${CCLA_ADD_BASE_BRANCH:-main}"

REPO_ROOT="$(git rev-parse --show-toplevel)"
[[ -n "$REPO_ROOT" ]] || die "not inside a git repository"
cd "$REPO_ROOT"

ROSTER="${CCLA_ADD_ROSTER:-apps/cla-evidence/roster/ccla-roster.json}"
# Resolve to an ABSOLUTE path. We cd to the repo root above, so the default
# would resolve correctly today — but `cp`/`jq` operands that are only
# conditionally absolute are the class `fixture-relative-assert` exists to
# catch: an overridden CCLA_ADD_ROSTER, or any future cd, silently retargets
# the write. Being provably absolute costs one line.
case "$ROSTER" in
  /*) ;;
  *) ROSTER="$REPO_ROOT/$ROSTER" ;;
esac
VALIDATOR="apps/web-platform/scripts/cla-evidence/validate-roster.ts"
TSX="apps/web-platform/node_modules/.bin/tsx"

# ---- argument parsing -------------------------------------------------------
RECORD_REF=""; ORG=""; SOLE_TRADER=0; SIGNED_AT=""; AUTHORIZED_FROM=""
INSTRUMENT_SHA=""; CLA_GIT_SHA=""; WITHDRAWN_AT=""
LOGINS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --record-ref)         RECORD_REF="${2:-}"; shift 2 ;;
    --org)                ORG="${2:-}"; shift 2 ;;
    --sole-trader)        SOLE_TRADER=1; shift ;;
    --signed-at)          SIGNED_AT="${2:-}"; shift 2 ;;
    --authorized-from)    AUTHORIZED_FROM="${2:-}"; shift 2 ;;
    --instrument-sha256)  INSTRUMENT_SHA="${2:-}"; shift 2 ;;
    --cla-git-sha)        CLA_GIT_SHA="${2:-}"; shift 2 ;;
    --withdrawn-at)       WITHDRAWN_AT="${2:-}"; shift 2 ;;
    --login)              LOGINS+=("${2:-}"); shift 2 ;;
    -h|--help)            usage ;;
    *) echo "::error::unknown flag: $1" >&2; usage ;;
  esac
done

[[ -n "$RECORD_REF" ]] || die "--record-ref is required" 64
[[ "$RECORD_REF" =~ ^CCLA-[0-9]{4,}$ ]] || die "--record-ref must look like CCLA-0001, got: $RECORD_REF" 64
[[ ${#LOGINS[@]} -gt 0 ]] || die "at least one --login is required" 64
for l in "${LOGINS[@]}"; do
  # GitHub login grammar: alphanumeric plus hyphens, no leading hyphen, <= 39.
  # The pattern is held in a variable: an unquoted `(` on the right of `=~` is
  # parsed by bash as a grouping operator, not as part of the regex.
  login_re='^[A-Za-z0-9][A-Za-z0-9-]{0,38}$'
  [[ "$l" =~ $login_re ]] || die "invalid GitHub login: $l" 64
done
[[ -f "$ROSTER" ]] || die "roster not found at $ROSTER"
command -v jq >/dev/null 2>&1 || die "jq is required"
[[ -x "$TSX" ]] || die "tsx not found at $TSX — run 'npm ci' in apps/web-platform"

if [[ "$MODE" == "add" ]]; then
  [[ -n "$SIGNED_AT" ]] || die "--signed-at is required" 64
  [[ -n "$AUTHORIZED_FROM" ]] || die "--authorized-from is required" 64
  [[ -n "$INSTRUMENT_SHA" ]] || die "--instrument-sha256 is required (SHA-256 of the executed instrument as received)" 64
  [[ "$INSTRUMENT_SHA" =~ ^[0-9a-f]{64}$ ]] || die "--instrument-sha256 must be 64 lowercase hex chars" 64
  if [[ "$SOLE_TRADER" -eq 0 && -z "$ORG" ]]; then
    die "one of --org or --sole-trader is required. Use --sole-trader when the counterparty's legal name IS a natural person's name; the name is then held off-repo (CLO amendment B1-c-2)." 64
  fi
  [[ "$SOLE_TRADER" -eq 1 && -n "$ORG" ]] && die "--org and --sole-trader are mutually exclusive" 64
else
  [[ -n "$WITHDRAWN_AT" ]] || die "--withdrawn-at is required for remove" 64
fi

# ---- the ICLA signature ledger (the reference set) --------------------------
LEDGER_FILE="${CCLA_ADD_LEDGER:-}"
# Only files WE created are cleaned up. A caller-supplied --ledger must never be
# deleted by our own trap.
TMP_FILES=()
# MUST return 0. An EXIT trap whose last command fails replaces the script's
# exit status with that failure — so a `[[ ... ]] && rm` here (false whenever
# there is nothing to clean up) silently rewrote every documented exit code
# (2 pre-flight, 3 schema, 4 entry-gate) to a bare 1.
cleanup() {
  if [[ ${#TMP_FILES[@]} -gt 0 ]]; then
    rm -f "${TMP_FILES[@]}"
  fi
  return 0
}
trap cleanup EXIT
if [[ -z "$LEDGER_FILE" ]]; then
  LEDGER_FILE="$(mktemp -t ccla-ledger.XXXXXXXX.json)"
  TMP_FILES+=("$LEDGER_FILE")
  if ! git show "origin/cla-signatures:signatures/cla.json" > "$LEDGER_FILE" 2>/dev/null; then
    die "could not read origin/cla-signatures:signatures/cla.json — fetch the branch first"
  fi
fi
[[ -s "$LEDGER_FILE" ]] || die "ICLA signature ledger is empty or unreadable at $LEDGER_FILE"

# ---- resolve logins to numeric ids ------------------------------------------
# The ledger keys on the numeric id, not the login: a login can be renamed and
# reused, an id cannot. Matching on the login would let a renamed account
# inherit a stranger's signature.
declare -a IDS=()
for login in "${LOGINS[@]}"; do
  if [[ -n "${CCLA_ADD_ID_MAP:-}" ]]; then
    id="$(jq -r --arg l "$login" '.[$l] // empty' <<<"$CCLA_ADD_ID_MAP")"
  else
    command -v gh >/dev/null 2>&1 || die "gh CLI is required to resolve logins to numeric ids"
    id=""
    if ! id="$(gh api "/users/${login}" --jq .id 2>/dev/null)"; then
      die "could not resolve GitHub login to a numeric id: $login"
    fi
  fi
  [[ "$id" =~ ^[0-9]+$ ]] || die "resolved id for $login is not numeric: '${id}'"
  echo "resolved ${login} -> ${id}"
  IDS+=("$id")
done

# ---- Guard 3, write side: refuse any id absent from the ICLA ledger ---------
# This is the check whose deletion is mutation row G3-M5. Every id is checked
# and every offender reported — stopping at the first is itself the defect.
MISSING=()
for i in "${!LOGINS[@]}"; do
  id="${IDS[$i]}"
  if [[ "$(jq --argjson id "$id" '[.signedContributors[]? | select(.id == $id)] | length' "$LEDGER_FILE")" == "0" ]]; then
    MISSING+=("${LOGINS[$i]} (id ${id})")
  fi
done
if [[ ${#MISSING[@]} -gt 0 ]]; then
  die "refusing to write: ${#MISSING[@]} account(s) have not signed the Individual CLA: ${MISSING[*]}. Contribution-triggered entry — an account enters the roster only at or after that person has signed the ICLA on a pull request here. Ask them to sign first; the roster catches up afterwards." 4
fi

# ---- build the new roster ---------------------------------------------------
NEW_ROSTER="$(mktemp -t ccla-roster.XXXXXXXX.json)"
TMP_FILES+=("$NEW_ROSTER")

if [[ "$MODE" == "add" ]]; then
  CLA_DOC_PATH="$("$TSX" apps/web-platform/scripts/cla-evidence/cla-doc-path.ts corporate)"
  [[ -n "$CLA_DOC_PATH" ]] || die "discriminant emitted an empty Corporate CLA path"
  if [[ -z "$CLA_GIT_SHA" ]]; then
    CLA_GIT_SHA="$(git log -1 --format=%H -- "$CLA_DOC_PATH")"
  fi
  [[ -n "$CLA_GIT_SHA" ]] || die "could not determine the Corporate CLA git sha"
  CLA_CONTENT_SHA="$(git show "${CLA_GIT_SHA}:${CLA_DOC_PATH}" | sha256sum | awk '{print $1}')"
  [[ "$CLA_CONTENT_SHA" =~ ^[0-9a-f]{64}$ ]] || die "computed Corporate CLA content sha is not 64 hex: $CLA_CONTENT_SHA"

  REPS="$(jq -n '[]')"
  for i in "${!LOGINS[@]}"; do
    REPS="$(jq --argjson reps "$REPS" --arg login "${LOGINS[$i]}" --argjson id "${IDS[$i]}" \
      --arg from "$AUTHORIZED_FROM" \
      -n '$reps + [{id: $id, login: $login, authorized_from: $from, removed_at: null}]')"
  done

  ORG_JSON="$(jq -n \
    --arg ref "$RECORD_REF" --arg signed "$SIGNED_AT" --arg path "$CLA_DOC_PATH" \
    --arg gsha "$CLA_GIT_SHA" --arg csha "$CLA_CONTENT_SHA" --arg isha "$INSTRUMENT_SHA" \
    --argjson reps "$REPS" --argjson soletrader "$SOLE_TRADER" --arg org "$ORG" \
    '{
       legal_name: (if $soletrader == 1 then null else $org end),
       record_ref: $ref,
       signed_at: $signed,
       cla_doc: {path: $path, git_sha: $gsha, content_sha256: $csha},
       executed_instrument_sha256: $isha,
       representatives: $reps
     }')"

  jq --argjson org "$ORG_JSON" --arg ref "$RECORD_REF" '
      if ([.organizations[]? | select(.record_ref == $ref)] | length) > 0
      then error("record_ref already present: " + $ref + " — use `remove`, or pick the next free ref")
      else .organizations += [$org] end' "$ROSTER" > "$NEW_ROSTER"
else
  jq --arg ref "$RECORD_REF" --arg login "${LOGINS[0]}" --arg at "$WITHDRAWN_AT" '
      ([.organizations[]? | select(.record_ref == $ref)] | length) as $n
      | if $n == 0 then error("no such record_ref in roster: " + $ref) else . end
      | .organizations |= map(
          if .record_ref == $ref then
            (([.representatives[] | select(.login == $login)] | length) as $m
             | if $m == 0 then error("login not designated under " + $ref + ": " + $login) else . end)
            | .representatives |= map(if .login == $login then .removed_at = $at else . end)
          else . end)' "$ROSTER" > "$NEW_ROSTER"
fi

# ---- validate BEFORE anything is written or pushed --------------------------
# One validation implementation, shared with CI. A shell reimplementation would
# drift from the schema it claims to enforce.
rc=0
"$TSX" "$VALIDATOR" "$NEW_ROSTER" "$LEDGER_FILE" || rc=$?
if [[ "$rc" -ne 0 ]]; then
  die "the roster this would write does not validate (validator exit ${rc}) — nothing written" "$rc"
fi

if [[ "$DRY_RUN" == "1" ]]; then
  echo "--- CCLA_ADD_DRY_RUN=1: the roster that WOULD be written ---"
  cat "$NEW_ROSTER"
  echo "--- no PR opened, nothing written, nothing pushed ---"
  exit 0
fi

# ---- write + single-file PR -------------------------------------------------
command -v gh >/dev/null 2>&1 || die "gh CLI is required to open the PR"
gh auth status >/dev/null 2>&1 || die "gh is not authenticated"
[[ -z "$(git status --porcelain)" ]] || die "working tree is dirty — commit or stash first (this script opens a single-file PR and will not sweep up unrelated changes)"

BRANCH="ccla-${MODE}-$(tr '[:upper:]' '[:lower:]' <<<"$RECORD_REF")-$(date -u +%Y%m%d%H%M%S)"
git switch -c "$BRANCH" >/dev/null
cp "$NEW_ROSTER" "$ROSTER"
git add -- "$ROSTER"
git commit --quiet --file - <<COMMITEOF
chore(ccla): ${MODE} ${RECORD_REF} in the corporate coverage map

Written by apps/cla-evidence/scripts/ccla-add.sh. Every account was verified
present in the Individual CLA signature ledger before this was written
(contribution-triggered entry), and the roster was schema-validated before the
branch was created.

Ref #3210.
COMMITEOF
git push --quiet -u origin "$BRANCH"
gh pr create --repo "$REPO" --base "$BASE_BRANCH" --head "$BRANCH" \
  --title "chore(ccla): ${MODE} ${RECORD_REF} in the corporate coverage map" \
  --body "Single-file change to \`${ROSTER}\`, written by \`ccla-add.sh\`.

Contribution-triggered entry was enforced at write time: every account below was verified present in \`origin/cla-signatures:signatures/cla.json\` before the roster was written. The roster was schema-validated (\`.strict()\`) before this branch existed.

Accounts: ${LOGINS[*]}

Ref #3210."
echo "PR opened from ${BRANCH}"
