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

# AP-025 / #7797 — a self-refusal the artifact CARRIES, because the hazard is a
# property of runtime STATE and not of this file's text. This script binds a
# live credential (`gh auth`, and the token `gh` holds) and under `-x` bash
# echoes every expanded word, so a trace would print it. Placed immediately
# after `set` so nothing credential-bearing can run ahead of it.
case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace: this script handles a live credential and -x would print it (see #7797)\n' >&2; exit 78 ;;
esac

usage() {
  cat >&2 <<'USAGE'
Usage:
  ccla-add.sh add    --record-ref CCLA-0001
                     (--org "Legal Name" | --sole-trader)
                     --signed-at 2026-09-04T00:00:00Z
                     --authorized-from 2026-09-04T00:00:00Z
                     (--instrument-file /abs/path | --instrument-sha256 <64-hex>)
                     --login <github-login> [--login <github-login> ...]
                     [--cla-git-sha <sha>]

  ccla-add.sh remove --record-ref CCLA-0001 --login <github-login>
                     --withdrawn-at 2026-09-04T00:00:00Z

  CCLA_ADD_DRY_RUN=1 ccla-add.sh ...   # resolve + validate, write nothing

Notes:
  --instrument-file and --instrument-sha256 are MUTUALLY EXCLUSIVE and exactly
  one is required. Prefer --instrument-file: it hashes the executed instrument
  itself, so no one retypes 64 hex characters into a permanent, world-readable
  record about a third party. The path must be ABSOLUTE and must resolve
  OUTSIDE this repository -- the instrument is held on the encrypted operator
  drive, never committed. --instrument-sha256 remains for the case where only
  the digest is to hand.

  Note that the path is echoed to stderr and lands in your shell history and in
  /proc/<pid>/cmdline; the instrument's filename may carry a legal name.

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

# TEST SEAMS ARE DRY-RUN ONLY. Each of these three overrides substitutes one of
# the gate's operands, so leaving them live on the write path makes the whole
# mechanism bypassable with one environment variable:
#   CCLA_ADD_LEDGER  replaces Guard 3's REFERENCE SET
#   CCLA_ADD_ID_MAP  replaces login -> id resolution, so any login can be bound
#                    to any signed id and published as a false association
#   CCLA_ADD_ROSTER  retargets the write to a file CI does not watch
# The CI half checks one hardcoded path, so a retargeted write is unguarded on
# both sides. Refuse them unless this is a dry run.
if [[ "${CCLA_ADD_DRY_RUN:-0}" != "1" ]]; then
  for _seam in CCLA_ADD_LEDGER CCLA_ADD_ID_MAP CCLA_ADD_ROSTER; do
    [[ -z "${!_seam:-}" ]] || die "$_seam is a TEST SEAM and is refused on the write path — it substitutes one of the gate's own operands. Re-run with CCLA_ADD_DRY_RUN=1, or unset it." 2
  done
fi

ROSTER_REL="${CCLA_ADD_ROSTER:-apps/cla-evidence/roster/ccla-roster.json}"
ROSTER="$ROSTER_REL"
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
# Initialised HERE and not only in the parse arm. Under `set -euo pipefail` the
# first `[[ -n "$INSTRUMENT_FILE" ]]` on an UNSET variable aborts with a bare
# rc=1 and no message at all -- which is not one of the documented exit codes,
# and is the same class the `need()` comment below was written about.
INSTRUMENT_FILE=""; RESOLVED_INSTRUMENT=""
LOGINS=()
# `shift 2` returns non-zero when there is no value to shift, and a `case` body
# is NOT exempt from `set -e` — so a trailing `--record-ref` aborted with exit 1
# and ZERO output, which is not one of the documented codes. Check arity first.
need() { [[ $# -ge 2 ]] || { echo "::error::$1 requires a value" >&2; usage; }; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --record-ref)         need "$@"; RECORD_REF="$2"; shift 2 ;;
    --org)                need "$@"; ORG="$2"; shift 2 ;;
    --sole-trader)        SOLE_TRADER=1; shift ;;
    --signed-at)          need "$@"; SIGNED_AT="$2"; shift 2 ;;
    --authorized-from)    need "$@"; AUTHORIZED_FROM="$2"; shift 2 ;;
    --instrument-sha256)  need "$@"; INSTRUMENT_SHA="$2"; shift 2 ;;
    # A repeated --instrument-file would silently last-wins, i.e. quietly change
    # WHICH file's bytes become the permanent record. Every other flag here is
    # last-wins too, but this is the one where the loser is a legal artifact.
    --instrument-file)    need "$@"
                          [[ -z "$INSTRUMENT_FILE" ]] \
                            || die "--instrument-file given more than once (already: $INSTRUMENT_FILE) -- pass it once, so which file was hashed is unambiguous" 64
                          INSTRUMENT_FILE="$2"; shift 2 ;;
    --cla-git-sha)        need "$@"; CLA_GIT_SHA="$2"; shift 2 ;;
    --withdrawn-at)       need "$@"; WITHDRAWN_AT="$2"; shift 2 ;;
    --login)              need "$@"; LOGINS+=("$2"); shift 2 ;;
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
# Preflight EVERY external binary the instrument path uses, not just jq. Without
# this a missing `realpath` fails the `realpath -e` line and reports rc 64 -- a
# USAGE error naming the operator's path -- for a broken toolchain. That is the
# measured-bad-for-could-not-measure collapse the -e/-f split four screens down
# exists to refuse, reintroduced at the top of the same script. rc 2, matching
# the runbook's pre-flight row.
for _bin in jq realpath sha256sum stat date; do
  command -v "$_bin" >/dev/null 2>&1 \
    || die "$_bin is required and is not on PATH -- this is a toolchain problem, not a problem with the arguments you passed" 2
done
[[ -x "$TSX" ]] || die "tsx not found at $TSX — run 'npm ci' in apps/web-platform"

# Refuse the instrument flags OUTSIDE `add`, rather than accepting and ignoring
# them. `remove` records the end of a designation and writes no hash, so
# `--instrument-file` there is either a misremembered command line or an operator
# who believes they are amending a hash. Both deserve a message; silence tells
# them the write did what they meant.
if [[ "$MODE" != "add" ]]; then
  [[ -z "$INSTRUMENT_FILE" ]] \
    || die "--instrument-file is only meaningful for \`add\`; \`$MODE\` records no instrument hash. If you meant to correct a landed hash, there is no mode for that -- see #7925." 64
  [[ -z "$INSTRUMENT_SHA" ]] \
    || die "--instrument-sha256 is only meaningful for \`add\`; \`$MODE\` records no instrument hash. If you meant to correct a landed hash, there is no mode for that -- see #7925." 64
fi

if [[ "$MODE" == "add" ]]; then
  [[ -n "$SIGNED_AT" ]] || die "--signed-at is required" 64
  [[ -n "$AUTHORIZED_FROM" ]] || die "--authorized-from is required" 64
  # ---- the executed instrument's hash: computed, or supplied ---------------
  # Mutual exclusion FIRST, so an operator who passes both is told that rather
  # than being told the second one won. Mirrors the --org/--sole-trader pair.
  if [[ -n "$INSTRUMENT_FILE" && -n "$INSTRUMENT_SHA" ]]; then
    die "--instrument-file and --instrument-sha256 are mutually exclusive. --instrument-file hashes the executed instrument itself and is of record; --instrument-sha256 records a digest you supply. Pass exactly one, so which artifact the published hash describes is never ambiguous." 64
  fi
  if [[ -z "$INSTRUMENT_FILE" && -z "$INSTRUMENT_SHA" ]]; then
    die "one of --instrument-file (preferred: an absolute path to the executed instrument, hashed here) or --instrument-sha256 (64-hex, when only the digest is to hand) is required" 64
  fi
  if [[ -n "$INSTRUMENT_FILE" ]]; then
    # ONE resolution, then every check AND the hash run against that same
    # string. Checking the argument and hashing an independent second
    # resolution leaves nothing asserting that the thing hashed is the thing
    # checked -- and between the two a symlink can be repointed.
    [[ "$INSTRUMENT_FILE" = /* ]] \
      || die "--instrument-file must be an absolute path (got: $INSTRUMENT_FILE) -- the executed instrument lives on the encrypted operator drive, outside this repository, and a relative path would be resolved against a working directory this script has already changed" 64
    # `-e` before `-f`, deliberately: `-f` ALONE reports a DIRECTORY as "no such
    # file", which is the measured-bad-for-could-not-measure collapse this
    # script exists to refuse. Two checks buy two true messages.
    [[ -e "$INSTRUMENT_FILE" ]] \
      || die "no such instrument file: $INSTRUMENT_FILE" 64
    RESOLVED_INSTRUMENT="$(realpath -e -- "$INSTRUMENT_FILE")" \
      || die "could not resolve --instrument-file to a real path: $INSTRUMENT_FILE" 64
    [[ -f "$RESOLVED_INSTRUMENT" ]] \
      || die "not a regular file: $INSTRUMENT_FILE -- pass the executed instrument itself, not a directory or a device" 64
    [[ -s "$RESOLVED_INSTRUMENT" ]] \
      || die "instrument file is empty: $INSTRUMENT_FILE -- an empty file hashes to a well-known constant and evidences nothing" 64
    [[ -r "$RESOLVED_INSTRUMENT" ]] \
      || die "instrument file is not readable: $INSTRUMENT_FILE" 64
    # Custody (P10): the bytes of record are the instrument as received on the
    # encrypted drive, never a copy inside this repository. The trailing slash
    # is load-bearing -- without it a sibling directory such as
    # /home/x/soleur-backup reads as inside /home/x/soleur.
    #
    # This is a TYPO CATCHER, not a boundary. A bind mount, a hardlink or a
    # sibling worktree defeats any path comparison, and none of them is what
    # this refusal exists to catch.
    _repo_real="$(realpath -e -- "$REPO_ROOT")" \
      || die "could not resolve the repository root for the custody check" 2
    case "$RESOLVED_INSTRUMENT" in
      "$_repo_real"/*)
        die "the instrument at $INSTRUMENT_FILE resolves INSIDE this repository ($RESOLVED_INSTRUMENT). The executed instrument is held off-repo on the encrypted operator drive -- committing it would publish the counterparty's identity, which is the whole reason the roster carries a hash and not a document." 2 ;;
    esac
    # `sha256sum < "$f"`, NOT `sha256sum "$f"`. GNU sha256sum PREFIXES its output
    # line with a backslash when the filename contains a backslash or a newline,
    # which shifts the awk fields and yields something that is not 64 hex.
    # Reading stdin prints no filename at all, so the shape cannot vary.
    INSTRUMENT_SHA="$(sha256sum < "$RESOLVED_INSTRUMENT" | awk '{print $1}')" \
      || die "could not hash the instrument at $INSTRUMENT_FILE" 2
    # --instrument-file closes TRANSCRIPTION error. It cannot close SELECTION
    # error -- the wrong file is hashed perfectly, and nothing downstream can
    # tell. Size and mtime are what make that reviewable: a re-export of the
    # same instrument differs in both. stderr, because stdout carries the
    # emitted roster on a dry run.
    # ONE stat, not a wc plus a date: two extra opens are two extra chances to
    # describe a different state of the file than the one that was hashed.
    _istat="$(stat -c '%s %Y' -- "$RESOLVED_INSTRUMENT" 2>/dev/null || echo 'unknown unknown')"
    _isize="${_istat%% *}"
    _imtime="${_istat##* }"
    [[ "$_imtime" == "unknown" ]] \
      || _imtime="$(date -u -d "@$_imtime" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)"
    printf 'instrument file: %s bytes=%s mtime=%s sha256=%s\n' \
      "$RESOLVED_INSTRUMENT" "$_isize" "$_imtime" "$INSTRUMENT_SHA" >&2
    printf 'CHECK THIS IS THE RIGHT INSTRUMENT: this script proves the hash matches the file, never that the file is the one that was executed.\n' >&2
    # The PASTE-SAFE half. The runbook asks the operator to put provenance in the
    # pull request; the line above cannot be that line, because the resolved path
    # may itself BE a legal name and a pull request body is public and permanent
    # -- the same reason nothing else about the counterparty is published here.
    # Everything that makes provenance reviewable (a re-export differs in size
    # and mtime) survives dropping the path.
    printf 'provenance: bytes=%s mtime=%s sha256=%s  # paste THIS line into the pull request, not the one above\n' \
      "$_isize" "$_imtime" "$INSTRUMENT_SHA" >&2
  fi
  # LOAD-BEARING for both arms, and the reason it is not written as two checks.
  # It is the single chokepoint every value of INSTRUMENT_SHA passes before it
  # reaches the roster, so a third source added later is covered without editing
  # anything. On the --instrument-file path it fires when field extraction went
  # wrong -- a `\`-prefixed sha256sum line, a truncated read -- which is exactly
  # the failure that would otherwise publish a malformed hash.
  [[ "$INSTRUMENT_SHA" =~ ^[0-9a-f]{64}$ ]] || die "the executed-instrument hash is not 64 lowercase hex chars: $INSTRUMENT_SHA" 64
  if [[ "$SOLE_TRADER" -eq 0 && -z "$ORG" ]]; then
    die "one of --org or --sole-trader is required. Use --sole-trader when the counterparty's legal name IS a natural person's name; the name is then held off-repo (CLO amendment B1-c-2)." 64
  fi
  [[ "$SOLE_TRADER" -eq 1 && -n "$ORG" ]] && die "--org and --sole-trader are mutually exclusive" 64
else
  [[ -n "$WITHDRAWN_AT" ]] || die "--withdrawn-at is required for remove" 64
  # The remove filter withdraws ONE login. Accepting more and acting on the
  # first silently leaves an ex-employee designated while the PR body lists
  # them as withdrawn — a partial write reported as complete, in the one
  # direction this script's header calls security-relevant.
  [[ ${#LOGINS[@]} -eq 1 ]] || die "remove takes exactly one --login (got ${#LOGINS[@]}: ${LOGINS[*]}) — run it once per account so each withdrawal is its own reviewable record" 64
fi
if [[ -n "$CLA_GIT_SHA" ]]; then
  [[ "$CLA_GIT_SHA" =~ ^[0-9a-f]{7,40}$ ]] || die "--cla-git-sha must be 7-40 lowercase hex (got: $CLA_GIT_SHA) — a revision expression such as HEAD~3 would silently hash a different instrument" 64
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
  # Fetch the ref rather than telling the operator to. `hr-never-label-any-step-as-manual-without`
  # applies to a one-line `git fetch` as much as to anything larger: the script
  # knows the exact refspec, so making the operator type it is an invented step.
  # The three sibling consumers (validate-roster.ts, roster-entry-gate.test.ts,
  # the shell harness) all recover it the same way; this was the last one that
  # did not.
  if ! git show "origin/cla-signatures:signatures/cla.json" > "$LEDGER_FILE" 2>/dev/null; then
    # --no-tags: `git fetch` auto-follows tags, and writing 157 of them into the
    # caller's repository to read one JSON file is a side effect nobody asked for.
    git fetch --no-tags --depth=1 -q origin \
      '+refs/heads/cla-signatures:refs/remotes/origin/cla-signatures' 2>/dev/null
  fi
  if ! git show "origin/cla-signatures:signatures/cla.json" > "$LEDGER_FILE" 2>/dev/null; then
    die "could not read origin/cla-signatures:signatures/cla.json, even after a shallow fetch. That branch is maintained by the upstream CLA action; without it the ICLA signature ledger is unavailable and contribution-triggered entry cannot be evaluated" 2
  fi
fi
[[ -s "$LEDGER_FILE" ]] || die "ICLA signature ledger is empty or unreadable at $LEDGER_FILE"
# Non-empty is not parseable. Assert the SHAPE once, loudly, before the gate
# reads it — otherwise a truncated fetch or an HTML error page is reported as
# "these people have not signed", which sends the operator to ask a contributor
# to re-sign when the actual fault is the reference set. That is the
# could-not-measure / measured-bad collapse AP-021 forbids.
jq -e 'type == "object" and (.signedContributors | type) == "array"' "$LEDGER_FILE" >/dev/null 2>&1 \
  || die "the ICLA signature ledger at $LEDGER_FILE is not a JSON object carrying a \`signedContributors\` array — the reference set is UNUSABLE, so contribution-triggered entry cannot be evaluated at all. This is NOT a finding about any account." 2

# ---- resolve logins to numeric ids ------------------------------------------
# The ledger keys on the numeric id, not the login: a login can be renamed and
# reused, an id cannot. Matching on the login would let a renamed account
# inherit a stranger's signature.
declare -a IDS=()
for login in "${LOGINS[@]}"; do
  created=""
  if [[ -n "${CCLA_ADD_ID_MAP:-}" ]]; then
    # Two accepted shapes. A bare number is the legacy form and carries no
    # created_at, so the handle-reuse check below is SKIPPED for it -- said out
    # loud rather than silently, because a skipped check that prints nothing is
    # indistinguishable from a passing one.
    id="$(jq -r --arg l "$login" '(.[$l] | if type == "object" then .id else . end) // empty' <<<"$CCLA_ADD_ID_MAP")"
    created="$(jq -r --arg l "$login" '(.[$l] | if type == "object" then (.created_at // empty) else empty end) // empty' <<<"$CCLA_ADD_ID_MAP")"
  else
    command -v gh >/dev/null 2>&1 || die "gh CLI is required to resolve logins to numeric ids"
    _u=""
    if ! _u="$(gh api "/users/${login}" --jq '[.id, .created_at] | @tsv' 2>/dev/null)"; then
      die "could not resolve GitHub login to a numeric id: $login"
    fi
    id="${_u%%$'\t'*}"
    created="${_u#*$'\t'}"
    [[ "$created" == "$id" ]] && created=""
  fi
  [[ "$id" =~ ^[0-9]+$ ]] || die "resolved id for $login is not numeric: '${id}'"
  # THE HANDLE-REUSE CHECK. GitHub releases a deleted account's login for
  # re-registration. The designation list names USERNAMES; the roster stores
  # IDS; and the operator reading the instrument cannot see that the handle
  # changed hands. An account created AFTER the grant took effect cannot be the
  # account the counterparty designated, so this is decidable and is refused.
  #
  # It is NECESSARY AND NOT SUFFICIENT, and the message says so: a long-lived
  # account that later took a freed handle passes it. It removes the cheapest
  # failure, not the failure class -- the current designation list is still the
  # authority (runbook s 10.1).
  reuse_checked=0
  if [[ "$MODE" == "add" && -n "$created" && -n "$AUTHORIZED_FROM" ]]; then
    reuse_checked=1
    _c_e="$(date -u -d "$created" +%s 2>/dev/null || echo "")"
    _a_e="$(date -u -d "$AUTHORIZED_FROM" +%s 2>/dev/null || echo "")"
    if [[ -z "$_c_e" || -z "$_a_e" ]]; then
      die "could not compare the account creation date ($created) with --authorized-from ($AUTHORIZED_FROM) -- refusing rather than recording an unchecked designation" 2
    fi
    if (( _c_e > _a_e )); then
      die "$login was created at $created, AFTER --authorized-from $AUTHORIZED_FROM. GitHub releases a deleted account's login for re-registration, so this handle may not be the account the counterparty designated -- and a roster row is permanent and world-readable. Check the counterparty's CURRENT designation list (instrument s 4(c) as amended by any s 5 notice) before retrying. This check is necessary and NOT sufficient: an older account that later took a freed handle would pass it." 2
    fi
  fi
  # stderr: stdout carries the emitted roster on a dry run, and a caller must be
  # able to pipe it to jq without reconstructing the document with sed.
  # The line asserts only what was actually done. Claiming "not created after
  # --authorized-from" whenever a date happened to be available would assert a
  # comparison on the `remove` path, where none is made.
  if [[ "$reuse_checked" == "1" ]]; then
    echo "resolved ${login} -> ${id} (created ${created}; not created after --authorized-from)" >&2
  else
    echo "resolved ${login} -> ${id} (the handle-reuse check was NOT run — no creation date, or no --authorized-from to compare against)" >&2
  fi
  IDS+=("$id")
done

# ---- Guard 3, write side: refuse any id absent from the ICLA ledger ---------
# This is the check whose deletion is mutation row G3-M5. Every id is checked
# and every offender reported — stopping at the first is itself the defect.
# Scoped to `add`. Gating REMOVAL on it means the more broken the ICLA record
# is, the harder it becomes to revoke an ex-employee's authorization — and the
# refusal message would tell the operator to obtain a signature in order to
# RETIRE a row. Every row already in the roster is still gated by the validator
# below and by the CI half, so scoping the write-side check loses no coverage.
MISSING=()
if [[ "$MODE" == "add" ]]; then
for i in "${!LOGINS[@]}"; do
  id="${IDS[$i]}"
  # NOT `[[ "$(jq ...)" == "0" ]]`. A command substitution inside `[[ ]]` is
  # exempt from `set -e`, so ANY jq failure yielded "" — and "" != "0" meant the
  # account was silently NOT added to MISSING and the gate PASSED it. The
  # write-side guard failed OPEN on exactly the malformed input it should refuse.
  # The `?` is gone too: it turns "not an array" into "empty", which is the same
  # collapse one level down.
  hits=""
  hits="$(jq --argjson id "$id" '[.signedContributors[] | select(.id == $id)] | length' "$LEDGER_FILE")" \
    || die "ledger query failed for ${LOGINS[$i]} (id ${id}) — the reference set could not be read, so no conclusion about this account is available" 2
  [[ "$hits" =~ ^[0-9]+$ ]] || die "ledger query for ${LOGINS[$i]} produced a non-numeric count: '${hits}'" 2
  [[ "$hits" -eq 0 ]] && MISSING+=("${LOGINS[$i]} (id ${id})")
done
fi
if [[ ${#MISSING[@]} -gt 0 ]]; then
  die "refusing to write: ${#MISSING[@]} account(s) have not signed the Individual CLA: ${MISSING[*]}. Contribution-triggered entry — an account enters the roster only at or after that person has signed the ICLA on a pull request here. Ask them to sign first; the roster catches up afterwards." 4
fi

# ---- build the new roster ---------------------------------------------------
NEW_ROSTER="$(mktemp -t ccla-roster.XXXXXXXX.json)"
TMP_FILES+=("$NEW_ROSTER")

if [[ "$MODE" == "add" ]]; then
  # `VAR=$(cmd)` DOES take the substitution's exit status, so `set -e` aborts
  # here on a tool failure — with a raw exit code and no message, and the
  # assertion on the next line never runs. That is a silent-to-the-operator
  # abort at a step whose failure modes are all actionable, so each one names
  # itself instead.
  CLA_DOC_PATH="$("$TSX" apps/web-platform/scripts/cla-evidence/cla-doc-path.ts corporate)" \
    || die "could not resolve the Corporate CLA path — is apps/web-platform/node_modules installed? (npm ci --prefix apps/web-platform)" 2
  [[ -n "$CLA_DOC_PATH" ]] || die "discriminant emitted an empty Corporate CLA path" 2
  [[ -f "$REPO_ROOT/$CLA_DOC_PATH" ]] || die "the Corporate CLA is not at $CLA_DOC_PATH" 2
  if [[ -z "$CLA_GIT_SHA" ]]; then
    CLA_GIT_SHA="$(git log -1 --format=%H -- "$CLA_DOC_PATH")" \
      || die "could not read git history for $CLA_DOC_PATH" 2
  fi
  [[ -n "$CLA_GIT_SHA" ]] || die "could not determine the Corporate CLA git sha — $CLA_DOC_PATH has no commit touching it" 2
  CLA_CONTENT_SHA="$(git show "${CLA_GIT_SHA}:${CLA_DOC_PATH}" | sha256sum | awk '{print $1}')" \
    || die "could not hash ${CLA_DOC_PATH} at ${CLA_GIT_SHA} — is that sha in this clone? (git fetch --unshallow)" 2
  [[ "$CLA_CONTENT_SHA" =~ ^[0-9a-f]{64}$ ]] || die "computed Corporate CLA content sha is not 64 hex: $CLA_CONTENT_SHA" 2

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
      else . end
      # An id already designated — under THIS record_ref or any other — is
      # refused rather than appended. Two live rows for one account make
      # "which organisation vouches for this contributor" unanswerable from the
      # record, and the roster is the artifact that is supposed to answer it.
      # A WITHDRAWN row is not a conflict: that is exactly how a person moves
      # between employers.
      | ([.organizations[]?.representatives[]? | select(.removed_at == null) | .id]) as $live
      | ([$org.representatives[].id] | map(select(. as $i | $live | index($i)))) as $dupes
      | if ($dupes | length) > 0
        then error("already designated under a live roster row: id(s) " + ($dupes | join(", "))
                   + " — withdraw the existing designation first")
        else . end
      | ([$org.representatives[].id] | group_by(.) | map(select(length > 1) | .[0])) as $self
      | if ($self | length) > 0
        then error("the same id was passed twice in one invocation: " + ($self | join(", ")))
        else . end
      | .organizations += [$org]' "$ROSTER" > "$NEW_ROSTER" \
    || die "the roster edit was refused (see the jq error above) — nothing written" 2
else
  jq --arg ref "$RECORD_REF" --arg login "${LOGINS[0]}" --arg at "$WITHDRAWN_AT" '
      ([.organizations[]? | select(.record_ref == $ref)] | length) as $n
      | if $n == 0 then error("no such record_ref in roster: " + $ref) else . end
      | .organizations |= map(
          if .record_ref == $ref then
            (([.representatives[] | select(.login == $login)] | length) as $m
             | if $m == 0 then error("login not designated under " + $ref + ": " + $login) else . end)
            # A recorded withdrawal date is the LEGALLY OPERATIVE one and is not
            # rewritten. Re-running `remove` on an already-withdrawn account
            # would silently move the date forward, changing the record of when
            # a designation ended — on a surface whose whole point is that the
            # record is durable. Refuse and say what is already on file.
            | (([.representatives[] | select(.login == $login and .removed_at != null)] | first) as $w
               | if $w != null
                 then error("already withdrawn under " + $ref + ": " + $login
                            + " on " + $w.removed_at
                            + " — a recorded withdrawal date is the operative one and is not rewritten")
                 else . end)
            | .representatives |= map(if .login == $login then .removed_at = $at else . end)
          else . end)' "$ROSTER" > "$NEW_ROSTER" \
    || die "the withdrawal was refused (see the jq error above) — nothing written" 2
fi

# ---- validate BEFORE anything is written or pushed --------------------------
# CI does not run this CLI — it calls the same two modules directly from
# `roster-entry-gate.test.ts`. What is shared is the IMPLEMENTATION
# (`schema.ts` + `roster-entry-gate.ts`), which is the part that matters: a
# shell reimplementation of the checks would drift from the schema it claims to
# enforce, and the write path and the merge gate would disagree.
rc=0
"$TSX" "$VALIDATOR" "$NEW_ROSTER" "$LEDGER_FILE" || rc=$?
if [[ "$rc" -ne 0 ]]; then
  die "the roster this would write does not validate (validator exit ${rc}) — nothing written" "$rc"
fi

if [[ "$DRY_RUN" == "1" ]]; then
  echo "--- CCLA_ADD_DRY_RUN=1: the roster that WOULD be written ---" >&2
  cat "$NEW_ROSTER"
  echo "--- no PR opened, nothing written, nothing pushed ---" >&2
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
if ! git push --quiet -u origin "$BRANCH"; then
  # The commit is safe on "$BRANCH" and the base branch was never touched, but
  # leaving the operator on a branch they did not create, with no idea what
  # state they are in, is how a half-finished legal record gets re-run from
  # scratch and duplicated. Say exactly where the work is and how to resume.
  printf '::error::push failed. The change is committed locally on branch %s and NOTHING was published.\n' "$BRANCH" >&2
  printf 'Resume with:  git push -u origin %s && gh pr create --base %s --head %s\n' "$BRANCH" "$BASE_BRANCH" "$BRANCH" >&2
  printf 'Abandon with: git switch - && git branch -D %s\n' "$BRANCH" >&2
  exit 2
fi
# A failure handler, mirroring the push above. Without one this exits non-zero
# with gh's own message and no statement of where the work is -- and the state
# here is WORSE than a failed push: the branch carrying the association is
# already on the public remote, so "nothing was published" is not true and an
# operator who re-runs from scratch duplicates a legal record.
if ! gh pr create --repo "$REPO" --base "$BASE_BRANCH" --head "$BRANCH" \
  --title "chore(ccla): ${MODE} ${RECORD_REF} in the corporate coverage map" \
  --body "Single-file change to \`${ROSTER_REL}\`, written by \`ccla-add.sh\`.

Contribution-triggered entry was enforced at write time: every account below was verified present in \`origin/cla-signatures:signatures/cla.json\` before the roster was written. The roster was schema-validated (\`.strict()\`) before this branch existed.

Accounts: ${LOGINS[*]}

Ref #3210."; then
  printf '::error::the branch was PUSHED but `gh pr create` failed. %s is on the remote and the roster change is committed on it; nothing has merged.\n' "$BRANCH" >&2
  printf 'Resume with:  gh pr create --repo %s --base %s --head %s\n' "$REPO" "$BASE_BRANCH" "$BRANCH" >&2
  printf 'Abandon with: git switch - && git branch -D %s && git push origin --delete %s\n' "$BRANCH" "$BRANCH" >&2
  printf 'Do NOT re-run this script from scratch: it would create a SECOND branch recording the same designation.\n' >&2
  exit 2
fi
echo "PR opened from ${BRANCH}"
