#!/usr/bin/env bash
# (#7922) Is there an ICLA signature at or after the coverage-map notice epoch
# that no roster row already covers?
#
# WHY A PROBE AND NOT A LOOK. Since the coverage-map notice landed, the roster
# entry gate is TEMPORAL, not merely membership-based: an account enters the
# public coverage map only if its Individual CLA signature is dated at or after
# the notice epoch. That epoch is DERIVED FROM GIT — it is written down nowhere
# — and every signature in the ledger today predates it. "Have they signed?" is
# therefore no longer the question, and the question that replaced it cannot be
# answered by eye. Getting it wrong in one direction is an unexplained refusal
# at the write path; in the other it is a false notice claim on a permanent
# public surface about a real person.
#
# ── THIS PROBE NAMES NO ONE ──────────────────────────────────────────────────
# It reports a COUNT and the number of entries it examined. No login, no id, no
# individual timestamp reaches any output stream on any branch — INCLUDING the
# failure paths of its subprocesses, which is where the real leak lives:
# `date -u -d "$bad"` prints `date: invalid date '<value>'` and `jq` echoes the
# offending ledger content in its parse errors. So the rule here is not "the
# probe's own echoes are careful"; it is that every external command which can
# see LEDGER, ROSTER or REMOTE bytes has its stderr suppressed and replaced by a
# line this file authored. `git` alone would otherwise relay a hostile origin's
# sideband verbatim as `remote: <text>`.
#
# The scope is deliberate and it IS the whole claim. A few commands here read
# only git-log output, this repository's own `docs/legal/individual-cla.md`, or
# a `mktemp` path, and are not redirected. An earlier revision asserted "EVERY
# external command", which was false — and a false invariant is worse than a
# narrow one, because the next person adding a pipeline stage reads it as
# licence.
#
# That is a constraint rather than a courtesy: `scripts/sweep-followthroughs.sh`
# captures this script's output with `2>&1` and republishes it into a public
# comment on #7922 every single sweep — near-verbatim: the sweeper neutralises
# an HTML-comment opener and collapses long backtick runs so a probe cannot
# forge its control markers or break out of the code fence, and alters nothing
# else. Treat every byte written here as published. Malformedness is therefore
# reported as a COUNTED PREDICATE — a number — and never as a caught exception
# carrying the value that caused it.
#
# The tracker names no counterparty and no person, and that is worth having —
# but it is a COST INCREASE, not a barrier, and this file must not claim
# otherwise. The ledger this probe measures is public and git-versioned, so a
# dated public transition next to an organisation's name would be a JOIN: a
# reader could diff `signatures/cla.json` at that date and recover the account
# that moved the count. An opaque tracker removes that element from the TRACKER.
#
# It does NOT remove it from the corpus. The first counterparty is named, with
# its city, country and registration identifiers, in
# `knowledge-base/legal/drafts/2026-09-04-convergence-ccla-reply.md` on the
# default branch, and a public issue records that one counterparty is in flight.
# A reader holding those needs only the DATE, and this tracker is where the date
# is. So the residual is recorded rather than assumed away: what opacity buys is
# that the tracker ALONE yields nothing, not that nothing can be joined.
#
# ── EXIT CONTRACT — NOTIFY-ONLY ──────────────────────────────────────────────
#   0  NEVER TAKEN. Exit 0 is the sweeper's CLOSE verb, and this probe cannot
#      establish the fact that would justify closing. See below.
#   1  NEVER TAKEN. Exit 1 is the sweeper's FAIL verb AND its reopen trigger on
#      a closed issue; a not-yet condition must never take it.
#   2  NOT YET  — the measurement was made; no uncovered post-epoch signature.
#   5  ACTION   — the measurement was made and found at least one. Go look.
#   3  CANNOT ESTABLISH — the measurement could not be made.
#   64 usage.
#
# WHY 2 AND 5 ARE DIFFERENT CODES, AND WHY THAT IS NOT DECORATION. The sweeper
# renders `TRANSIENT (exit $rc, <date>)` in the comment HEADING and folds the
# body behind a `<details>`. The exit code is the only signal the operator sees
# without expanding. With one code for both outcomes this probe would post a
# byte-identical heading every day forever, including on the one day the answer
# changed — a silent never-notice whose daily message looks perfectly plausible,
# which is the exact failure mode this file exists to remove.
#
# WHY EXIT 0 IS REFUSED, MEASURED. The epoch is recent and this repository
# requires contributors to sign the ICLA, so EVERY future signature by anyone is
# post-epoch by construction. The first unrelated contributor to sign satisfies
# "a post-epoch signature no roster row covers" — and the condition never
# clears, because that person is not a corporate representative and never will
# be. Exit 0 would make the sweeper post PASS and CLOSE; `closed_precheck` would
# then refuse to re-litigate an issue carrying the sweeper's own PASS block, and
# a reopened tracker would be re-closed on the next sweep. The close is the
# irreversible verb on a legal tracker, and this probe has not earned it: its
# own output says it is not authority to record. The operator closes #7922 when
# they record the row.
#
# ── ORDERING IS LOAD-BEARING: DERIVE THE EPOCH BEFORE FETCHING THE LEDGER ────
# `git fetch --depth=1` writes `.git/shallow` into the COMMON DIR, flipping the
# whole repository — every worktree — to shallow. The epoch derivation walks
# history, so a fetch that ran first would leave it deriving the graft commit's
# own date: a plausible-looking ISO timestamp that is simply wrong, and wrong in
# the direction that refuses everyone. Measured on a `--depth=1` clone: the
# derivation returned HEAD's own commit date instead of the notice commit's, and
# `rev-parse <graft>^` failed.
#
# The ledger branch is exactly one commit, so `--depth=1` buys nothing anyway
# and is omitted. `--no-tags` is NOT the bound that matters — the explicit
# refspec is what confines the write to `refs/remotes/origin/cla-signatures`
# (origin cannot steer it elsewhere). `--no-tags` only stops tag refs, which the
# repo-write-boundary guard treats as FATAL. Two further writes into the shared
# common dir are unbounded by either, and each is one flag:
# `--no-write-fetch-head` (FETCH_HEAD lands in the common dir) and
# `-c gc.auto=0` (a fetch-triggered `gc --auto` runs in the operator's live
# repository and outlives the `timeout`). `--no-recurse-submodules` because the
# default is `on-demand` and `.gitmodules` on the fetched branch is content
# controlled by whoever writes that branch.
#
# ── earliest= ────────────────────────────────────────────────────────────────
# The directive's `earliest=` is the FILING date, per followthrough-convention.
# A far-future `earliest=` would suppress the daily comment across exactly the
# window in which the operator must act, and the convention forbids it in terms.
# The residual cost is noise, and the noise is a substrate defect (one existing
# tracker carries 33 identical sweeper comments) rather than this probe's to fix.
#
# Enrolment (the directive + the `follow-through` label) is applied POST-MERGE by
# `scripts/bootstrap-ccla-watch-7922.sh`, because the sweeper resolves
# `script=` against the DEFAULT BRANCH — a label applied before this file lands
# there yields a daily "script missing" line nobody reads.
# ── WHY `-uo` AND NOT `-euo` ─────────────────────────────────────────────────
# 66 of the 68 probes here use `set -uo pipefail`, including both of the ones
# this file is modelled on, and the reason is specific rather than stylistic.
# Under `-e` any unguarded non-zero command aborts with bash's own status, which
# for most failures is **1** — and 1 is the sweeper's FAIL verb AND its reopen
# trigger on a closed issue. So `-e` hands this file a path to the one exit code
# its contract says it must never take, reachable by adding any future unguarded
# command. Without `-e`, a failure surfaces only as a code this file chose.
# Every failure path below is explicitly `||`-guarded, and the companion suite
# asserts `rc` is never 0 or 1 across the whole fixture family rather than
# leaving that invariant as prose.
set -uo pipefail

# The authority for both constants is
# `apps/web-platform/scripts/cla-evidence/roster-entry-gate.ts`
# (`NOTICE_DOC` / `NOTICE_ANCHOR`). They are restated rather than imported
# because this probe must run under `env -i` with no node toolchain; the
# companion suite pins them to the TypeScript values per fixture, so a drift in
# either direction reddens rather than silently disagreeing.
NOTICE_DOC="docs/legal/individual-cla.md"
NOTICE_ANCHOR="public corporate coverage map"
ROSTER_REL="apps/cla-evidence/roster/ccla-roster.json"
# The acknowledged floor (see the verdict block at the bottom of this file).
ACK_FILE_REL="scripts/followthroughs/ccla-representative-icla-7922.acknowledged"
LEDGER_BRANCH="cla-signatures"
LEDGER_PATH="signatures/cla.json"
NET_TIMEOUT=30

# ONE refusal shape, and every instance ends in an addressee tag. Four of the
# six refusal states have no operator remedy at all, and without the tag they
# read as jargon aimed at someone who cannot act on them.
cannot_establish() {
  printf 'CANNOT ESTABLISH: %s\n' "$1"
  exit "${2:-3}"
}

usage() {
  printf 'usage: %s [--print-epoch]\n' "${0##*/}"
  printf '  (no args)      report the uncovered post-epoch signature count\n'
  printf '  --print-epoch  print the derived coverage-map notice epoch and stop\n'
  exit 64
}

MODE="verdict"
case "${1:-}" in
  "")            MODE="verdict" ;;
  --print-epoch) MODE="epoch" ;;
  # Any unrecognised argv is a usage error, so a mistyped `--print-epock`
  # cannot fall through to the verdict path and be read as a measurement.
  *)             usage ;;
esac
[[ $# -le 1 ]] || usage

# A MISSING BINARY IS NOT A BROKEN LEDGER. Without this, `jq` absent from the
# sweeper's pinned FHS PATH fails the shape check below and reports "the ICLA
# signature ledger is UNUSABLE" — publicly blaming a shared upstream artifact
# for a fault on our side. That is the measured-bad-for-could-not-measure
# collapse this file exists to refuse, and `ccla-add.sh` already preflights jq
# for the same reason.
for _bin in git jq date timeout sha256sum; do
  command -v "$_bin" >/dev/null 2>&1 \
    || cannot_establish "the tool '${_bin}' is not on this probe's PATH, so the measurement could not be attempted. This is NOT a finding about the ledger, the coverage map or any account. Operator: no action — engineering fault, file it." 3
done

REPO_ROOT=""
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" \
  || cannot_establish "this is not a git checkout, so neither the notice epoch nor the ledger can be read. Operator: no action — engineering fault, file it." 3
cd "$REPO_ROOT" \
  || cannot_establish "could not enter the repository root. Operator: no action — engineering fault, file it." 3

# ---------------------------------------------------------------------------
# The epoch, and its single control.
# ---------------------------------------------------------------------------
# NOT a function called through `$( )`. A command substitution runs in a
# SUBSHELL, so `cannot_establish`'s `exit` would end the subshell and the caller
# would sail past it with an empty value.
EPOCH_RAW=""
EPOCH_RAW="$(timeout "$NET_TIMEOUT" git log --first-parent -S"$NOTICE_ANCHOR" \
  --format='%H %cI' -- "$NOTICE_DOC" 2>/dev/null)" \
  || cannot_establish "the git log that derives the coverage-map notice epoch failed. Operator: no action — engineering fault, file it." 3

# A NON-MATCHING PICKAXE EXITS 0 WITH EMPTY STDOUT, so the `||` above cannot
# catch "the anchor was never found". And `date -u -d ""` returns TODAY rather
# than erroring — measured — so an empty line here would silently produce a
# plausible epoch of now. This check is the only thing between those two facts.
EPOCH_LINE="$(printf '%s\n' "$EPOCH_RAW" | sed '/^$/d' | tail -n 1)"
[[ -n "$EPOCH_LINE" ]] \
  || cannot_establish "the coverage-map notice anchor was not found in the history of ${NOTICE_DOC} — either the notice is absent or the anchor was reworded. Operator: no action — engineering fault, file it." 3

# `--format='%H %cI'` and not `%cI`: control B below needs the SHA, and a
# format carrying only the date leaves both `${line%% *}` and `${line#* }`
# returning the whole string.
EPOCH_SHA="${EPOCH_LINE%% *}"
EPOCH_ISO="${EPOCH_LINE#* }"
[[ "$EPOCH_SHA" =~ ^[0-9a-f]{7,40}$ ]] \
  || cannot_establish "the derived notice commit is not a git object id. Operator: no action — engineering fault, file it." 3
[[ "$EPOCH_ISO" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(Z|[+-][0-9]{2}:[0-9]{2})$ ]] \
  || cannot_establish "the derived notice epoch is not an ISO-8601 timestamp. Operator: no action — engineering fault, file it." 3

# CONTROL B — did the commit we found actually INTRODUCE the anchor?
#
# That is what `-S` claims, and it is exactly what a shallow or grafted history
# breaks: the graft boundary makes the oldest reachable commit look like the
# introducing one. A `--is-shallow-repository` test would NOT do: the ledger
# fetch below writes `.git/shallow` into the shared common dir, so an operator's
# checkout is routinely already flagged shallow on a machine where the
# derivation demonstrably works. This measures the property directly, and
# catches strictly more (a `--depth=50` boundary, a `git replace` graft, a
# filtered history, a squash rewrite).
EPOCH_PARENT=""
EPOCH_PARENT="$(git rev-parse --verify --quiet "${EPOCH_SHA}^" 2>/dev/null)" || EPOCH_PARENT=""
[[ -n "$EPOCH_PARENT" ]] \
  || cannot_establish "the commit that appears to introduce the coverage-map notice has NO PARENT in this checkout, so it is a graft boundary and the epoch derived from it would be the graft's own date rather than the notice's. Operator: no action — engineering fault, the checkout needs full history (fetch-depth: 0); file it." 3

# `git show` on a path that did not exist at the parent is a legitimate empty
# answer (the commit added the file), not an error — so a failure degrades to
# the empty string rather than to a refusal.
# ABSENT-AT-PARENT and COULD-NOT-READ are different facts, and collapsing them
# fails OPEN. `N_PARENT` computes to 0 for an empty document, and 0 is control
# B's SUCCESS value — so a corrupt pack, a blobless partial clone with no
# network, or any other real read failure would silently PASS the one control
# whose entire job is catching a wrong epoch. Ask git which case this is.
PARENT_DOC=""
if git cat-file -e "${EPOCH_PARENT}:${NOTICE_DOC}" 2>/dev/null; then
  PARENT_DOC="$(git show "${EPOCH_PARENT}:${NOTICE_DOC}" 2>/dev/null)" \
    || cannot_establish "the parent of the notice commit carries ${NOTICE_DOC} but it could not be read, so the anchor-introduction control could not be evaluated. Operator: no action — engineering fault, file it." 3
else
  # The legitimate case: the commit ADDED the file, so the parent has no copy.
  PARENT_DOC=""
fi
ANCHOR_DOC=""
ANCHOR_DOC="$(git show "${EPOCH_SHA}:${NOTICE_DOC}" 2>/dev/null)" \
  || cannot_establish "could not read ${NOTICE_DOC} at the commit that introduced the notice. Operator: no action — engineering fault, file it." 3

# `grep -c` EXITS 1 WHEN THE COUNT IS ZERO — which is control B's SUCCESS case —
# so neither of these may be chained to a `||` refusal.
N_PARENT="$(printf '%s' "$PARENT_DOC" | grep -cF -- "$NOTICE_ANCHOR" || true)"
N_ANCHOR="$(printf '%s' "$ANCHOR_DOC" | grep -cF -- "$NOTICE_ANCHOR" || true)"
[[ "$N_PARENT" =~ ^[0-9]+$ && "$N_ANCHOR" =~ ^[0-9]+$ ]] \
  || cannot_establish "the anchor-occurrence control produced a non-numeric count. Operator: no action — engineering fault, file it." 3
(( N_ANCHOR >= 1 )) \
  || cannot_establish "the commit the pickaxe named does not itself contain the notice anchor — the history has been rewritten under this derivation. Operator: no action — engineering fault, file it." 3
(( N_PARENT == 0 )) \
  || cannot_establish "the PARENT of the commit the pickaxe named already contains the notice anchor, so that commit did not introduce it and the epoch is not the notice's moment. This is the signature of a grafted or truncated history. Operator: no action — engineering fault, the checkout needs full history (fetch-depth: 0); file it." 3

if [[ "$MODE" == "epoch" ]]; then
  # Byte-equal to `resolveCoverageMapNoticeEpoch()`. Exits 2, not 0: this file's
  # invariant is that it never returns the sweeper's close verb on ANY path,
  # which is cheaper to verify and impossible to regress into.
  printf '%s\n' "$EPOCH_ISO"
  exit 2
fi

EPOCH_S=""
EPOCH_S="$(date -u -d "$EPOCH_ISO" +%s 2>/dev/null)" \
  || cannot_establish "the derived notice epoch could not be converted to a timestamp. Operator: no action — engineering fault, file it." 3
# A parse failure REFUSES; it never defaults to 0. `sweep-followthroughs.sh`
# uses `|| echo 0` for its own `earliest`, which is correct there (an
# unparseable value means "run now") and catastrophic here (it would make every
# signature post-epoch).
[[ "$EPOCH_S" =~ ^[0-9]+$ ]] \
  || cannot_establish "the derived notice epoch converted to a non-numeric value. Operator: no action — engineering fault, file it." 3

# ---------------------------------------------------------------------------
# The ledger and the roster.
# ---------------------------------------------------------------------------
WORK=""
WORK="$(mktemp -d 2>/dev/null)" \
  || cannot_establish "could not create a scratch directory. Operator: no action — engineering fault, file it." 3
cleanup() { rm -rf "$WORK"; return 0; }
trap cleanup EXIT

timeout "$NET_TIMEOUT" git -c gc.auto=0 fetch --no-tags --no-recurse-submodules \
  --no-write-fetch-head -q origin \
  "+refs/heads/${LEDGER_BRANCH}:refs/remotes/origin/${LEDGER_BRANCH}" 2>/dev/null \
  || cannot_establish "could not fetch the ICLA signature ledger ref within ${NET_TIMEOUT}s. Operator: no action — this is a transport or upstream fault, not a finding about any account; it clears by itself or it is ours to file." 3

LEDGER_FILE="$WORK/ledger.json"
git show "origin/${LEDGER_BRANCH}:${LEDGER_PATH}" > "$LEDGER_FILE" 2>/dev/null \
  || cannot_establish "could not read ${LEDGER_PATH} from the fetched ledger branch. Operator: no action — engineering fault, file it." 3
[[ -s "$LEDGER_FILE" ]] \
  || cannot_establish "the ICLA signature ledger is empty. This is NOT a finding about any account. Operator: no action — engineering fault, file it." 3
# Non-empty is not parseable. An HTML error page or a truncated fetch must be
# reported as an unusable reference set, never as "nobody has signed".
jq -e 'type == "object" and (.signedContributors | type) == "array"' "$LEDGER_FILE" >/dev/null 2>&1 \
  || cannot_establish "the ICLA signature ledger is UNUSABLE — it is not a JSON object carrying a signedContributors array. This is NOT a finding about any account. Operator: no action — engineering fault, file it." 3

ACK_FILE="$REPO_ROOT/$ACK_FILE_REL"
ROSTER="$REPO_ROOT/$ROSTER_REL"
[[ -f "$ROSTER" ]] \
  || cannot_establish "the coverage map is missing at ${ROSTER_REL}. Operator: no action — engineering fault, file it." 3

# MATERIALISED AND STATUS-CHECKED, never a process substitution.
#
# The first draft of this probe sourced the roster id set through
# `--slurpfile r <(jq ... "$ROSTER")`. A process substitution's exit status is
# invisible to BOTH `set -e` and `pipefail`: if that inner `jq` failed — roster
# missing, truncated, an HTML error page, `.organizations` not an array — it
# wrote nothing, `$r` bound to `[]`, `$r[0]` was `null`, and `null | index($i)`
# is `null` rather than an error, so EVERY ledger entry read as uncovered.
# Reproduced against a malformed roster and one post-epoch entry: `count=1
# rc=0`. Worse, it is invisible in the output — the legitimate empty roster
# (today's live state) also yields `[]`, so a broken roster and an empty roster
# were byte-identical in the count.
ROSTER_IDS=""
ROSTER_IDS="$(jq -c '[.organizations[]?.representatives[]?.id]' "$ROSTER" 2>/dev/null)" \
  || cannot_establish "the coverage map at ${ROSTER_REL} is not readable as JSON. Operator: no action — engineering fault, file it." 3
[[ "$ROSTER_IDS" == \[* ]] \
  || cannot_establish "the coverage map did not yield an id array. Operator: no action — engineering fault, file it." 3

# "COVERED" MEANS KNOWN TO THE ROSTER AT ALL — LIVE OR WITHDRAWN.
#
# Not `select(.removed_at == null)`. A representative withdrawn under `remove`
# and never re-added is post-epoch and permanently not-live, so a live-only term
# would leave their id in the count forever. The count would then sit at >= 1
# from that day on and could never move, which destroys the only signal this
# probe produces. Withdrawal is a fact about a designation, not about whether
# the roster knows the account.
COUNTS=""
COUNTS="$(jq -r --argjson epoch "$EPOCH_S" --argjson r "$ROSTER_IDS" '
  def wellformed:
    (.created_at | type) == "string"
    and (.created_at | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"));
  (.signedContributors | length) as $total
  | ([ .signedContributors[] | select(wellformed | not) ] | length) as $bad
  # LAST-WINS ON A DUPLICATE ID, because that is what the merge gate does:
  # `roster-entry-gate.ts` builds `new Map(signedContributors.map(c => [c.id,
  # c.created_at]))`, and a Map keeps the LAST entry for a repeated key. Read
  # existentially instead, a duplicated id whose post-epoch entry precedes its
  # pre-epoch one makes this probe say ACTION while the gate then refuses the
  # write — the unexplained write-path refusal this file exists to prevent.
  | (.signedContributors | group_by(.id) | map(.[-1])) as $latest
  | ([ $latest[]
       | select(wellformed)
       | select((.created_at | fromdateiso8601) >= $epoch)
       # `.id` is BOUND FIRST. Written as `select(($r | index(.id)) == null)`
       # the pipe rebinds `.` to $r inside `index(...)`, so `.id` indexes an
       # ARRAY with a string and jq aborts with "Cannot index array with string".
       # That error is unreachable whenever no entry clears the temporal filter
       # above -- which is every fixture whose signatures all predate the epoch,
       # and the live repository today. It would have surfaced for the first
       # time on the one run that mattered.
       | .id as $i
       | select(($r | index($i)) == null) ] | length) as $hits
  | "\($total) \($bad) \($hits)"' "$LEDGER_FILE" 2>/dev/null)" \
  || cannot_establish "the ICLA signature ledger could not be evaluated against the notice epoch. This is NOT a finding about any account. Operator: no action — engineering fault, file it." 3

# `<<<` and not `< <( )`, for the same reason as above.
N_TOTAL=""; N_BAD=""; N_HITS=""
read -r N_TOTAL N_BAD N_HITS <<<"$COUNTS"
[[ "$N_TOTAL" =~ ^[0-9]+$ && "$N_BAD" =~ ^[0-9]+$ && "$N_HITS" =~ ^[0-9]+$ ]] \
  || cannot_establish "the ledger evaluation produced non-numeric counts. Operator: no action — engineering fault, file it." 3

# Reported as a NUMBER and never as the offending value. `fromdateiso8601` on a
# bad value puts that value into jq's error message, and that message would be
# published verbatim — which is why malformedness is a counted predicate here
# rather than a caught exception.
(( N_BAD == 0 )) \
  || cannot_establish "${N_BAD} ledger entr(ies) carry no parseable created_at, so the temporal gate cannot be evaluated for them. This is NOT a finding about any account. Operator: no action — engineering fault, file it." 3

# ── THE ACKNOWLEDGED FLOOR: WHY A BARE `N_HITS >= 1` WOULD LATCH ────────────
# This is the same never-notice the exit contract above refuses exit 0 to
# avoid, one exit code over, and refusing the close verb does NOT remove it.
#
# The predicate is "post-epoch and not in the coverage map". The epoch is
# recent and every contributor to this repository signs the ICLA, so the first
# UNRELATED person to sign after it satisfies the predicate — and satisfies it
# permanently, because they are not a corporate representative and never will
# be rostered. A bare `N_HITS >= 1` would therefore emit ACTION every day
# forever from that moment, with a count that only grows, and the sweeper's
# heading would be byte-identical on the one day a designated representative
# actually signs. That is a level-triggered signal on a monotone quantity,
# which is another way of spelling "no signal".
#
# So the comparison is against an ACKNOWLEDGED FLOOR, making it edge-triggered:
# ACTION fires only when the count EXCEEDS what the operator has already
# triaged. The floor lives in git — the same place the rest of this design
# keeps its state — so the probe needs no credential and no write access to
# read it, and advancing it is a reviewable one-line pull request rather than a
# click. The file is absent until the first triage, which reads as 0.
ACK_FLOOR=0
if [[ -f "$ACK_FILE" ]]; then
  ACK_FLOOR="$(tr -d '[:space:]' < "$ACK_FILE" 2>/dev/null)" || ACK_FLOOR=""
  [[ "$ACK_FLOOR" =~ ^[0-9]+$ ]] \
    || cannot_establish "the acknowledged-floor file ${ACK_FILE_REL} does not contain a plain integer, so a triaged count cannot be distinguished from a new one. Refusing rather than defaulting it to 0, which would re-fire on everything already triaged. Operator: correct that file to a single integer." 3
fi

if (( N_HITS > ACK_FLOOR )); then
  printf 'ACTION: %s signature(s) satisfy the temporal gate and are covered by no roster row (epoch %s; %s entr(ies) checked; %s already triaged).\n' \
    "$N_HITS" "$EPOCH_ISO" "$N_TOTAL" "$ACK_FLOOR"
  printf 'This is NOT authority to record a row. The authority is the counterparty CURRENT designation list -- the executed instrument section 4(c) list AS AMENDED by any section 5 change notice on file -- held off-repo on the encrypted operator drive. Operator: work through runbook section 10.1 before recording anything.\n'
  printf 'If none of these signatures is a designated representative, this was an unrelated signer: raise the count in %s to %s in a pull request, which is how you tell this probe you have looked.\n' \
    "$ACK_FILE_REL" "$N_HITS"
  exit 5
fi

# BOTH counts are carried. "0 uncovered", "0 examined" and "all already
# triaged" are three different facts with three different remedies, and a line
# carrying only one number cannot tell them apart.
printf 'NOT YET: %s signature(s) checked against epoch %s; %s uncovered post-epoch signature(s), %s already triaged.\n' \
  "$N_TOTAL" "$EPOCH_ISO" "$N_HITS" "$ACK_FLOOR"
exit 2
