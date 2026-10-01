#!/usr/bin/env bash
#
# net-issue-flow.sh — BLOCKING per-PR net-issue-flow gate.
#
# Contract
# --------
#   usage:  net-issue-flow.sh [PR_NUMBER]
#   stdout: a human-readable CLOSING / FILED / NET block, always emitted,
#           enumerating the actual issue numbers behind each count.
#   exit 0: NET <= 0, or an override is present, or a transient failure
#           (fail-OPEN — see below).
#   exit 1: NET > 0 and no override. THE BLOCKING PATH.
#
# Threshold
# ---------
# Blocks at NET > 0: every PR must close at least as many issues as it files.
# NOT NET > +1. At the measured ~132 merged PRs/week, a +1 allowance authorizes
# +132 issues/week against an observed +144/week — it would cut backlog growth
# by ~8% and then report success. NET > 0 is the only threshold that flattens
# the queue. Pinned by case 4 of plugins/soleur/test/net-issue-flow.test.sh.
#
# Why the FILED query looks the way it does
# -----------------------------------------
# Five independently-measured defects each make a BLOCKING gate silently
# always-pass — which is strictly worse than the advisory surface it replaces,
# because it also carries the authority of having passed:
#   1. `--search` returns EMPTY cross-repo under a GitHub App / action token.
#   2. `gh issue list` defaults to --limit 30 (measured 30 returned vs 271 real).
#   3. The `(Ref|Closes|Fixes) #N` keyword filter matches only ~40% of real
#      filings; a bare `#N` mention is the common shape.
#   4. `--label deferred-scope-out` covers only ~8% of what PRs actually file.
#   5. (#7759) The FILED query asks the ISSUE side only, so a filing that cites
#      the ORIGINATING ISSUE rather than the PR is invisible: `Filing:`
#      under-counts and the gate passes net-positive. Measured live twice — PR
#      #7702 read `Filing: 0 / Net: -1 / PASS` and, once its three filings named
#      the PR, `Filing: 3 / Net: +2 / BLOCKED`; PR #7841 reproduced it.
#      Remedy: a SECOND attribution arm reading the PR own body. An issue counts
#      when it postdates the PR AND (its body cites #N — unchanged — OR its
#      number is on the PR `Filed:`/`Tracks:`/`Refs:` line). Every OTHER post-PR
#      number the body mentions is REPORTED as a possible unattributed filing
#      and counted toward nothing. Widening the match to issues citing an issue
#      the PR closes was rejected: attribution would run transitively through a
#      third party, so a sibling PR filings would count against this one.
#      Counting bare `#N` was rejected on measurement over 300 PRs — it
#      attributes 9 issues to two different PRs each and flips 25 (8.3%) from
#      PASS to BLOCK with an unmeasured false-positive rate. See ADR-206.
# So: no --search, --limit 500, --state all, no label filter, bare-#N matching,
# a client-side full-ISO createdAt comparison (never `cut -c1-10`, which
# collapses same-day precision), and both attribution arms above.
#
# One interaction worth stating because it collapses an ADR-155 conjunct: a
# `Filed: #N` declaration now BOTH admits a row into FILED and satisfies
# exemption condition 4 (the companion), so for rows admitted via THAT route the
# four conjuncts are no longer independent. Rows admitted via the other arm (the
# issue body cites the PR) still need a separate companion, so the collapse is
# scoped, not total. Condition 2 — the human-gated `[mandates-filing]` corpus
# edit — still bounds the blast radius either way.
#
# An earlier revision of this comment justified that collapse by asserting the
# exemption "was INERT, because 0 of 33 whole-line `Mandated-By:` issues cite a
# PR". That measurement was wrong and the conclusion drawn from it does not
# hold. Re-measured 2026-09-07 by classifying each cited number through the
# GitHub API on `.pull_request` presence, which is the only sound discriminator
# here because issues and PRs share one number space in this repo:
#
#   33 whole-line `Mandated-By:` issues; all 33 cite at least one `#N`
#   66 distinct cited numbers, of which 21 are pull requests
#   20 of the 33 cite at least one PR, over 29 (issue, cited-PR) pairs
#
# One of those pairs is #7710 citing #7702 — the very case #7759 was filed
# about. So the exemption had real candidates before this change; the honest
# statement is that it was under-reached, not dead.
#
# Exits: the general override, and the narrow mandated-filing exemption
# ---------------------------------------------------------------------
# The escape hatch is deliberate, not default. A PR can be legitimately
# net-positive for several unrelated reasons — an architectural pivot, a
# discovered defect in another subsystem that must stay its own issue, or a
# filing forced by a SKILL.md phase mandate that carries no rule id. The
# override covers all of them:
#   - PR body carries `<!-- gate-override: net-issue-flow -->` plus a one-line
#     justification per filed issue, or
#   - SOLEUR_SKIP_NET_ISSUE_FLOW_GATE=1 in the environment.
# Do NOT describe it as an architectural-pivot-only hatch. It was, and the
# result was that every other legitimate use had to be mis-described to fit —
# which trains the reflex of reaching for the override without reading it.
#
# Separately, one narrow case is resolved WITHOUT the blanket hatch: a filing
# another repo rule REQUIRED. `wg-block-pr-ready-on-undeferred-operator-steps`
# mandates a tracking issue before `gh pr ready`, so obeying it forced a
# violation here and neither documented exit applied ("fix inline" is a SIZE
# test; the blocker was AUTHORITY. "close something" needs a superseded issue,
# and a mandated tracker supersedes nothing). Such an issue is subtracted from
# NET when ALL of the following hold — see the derivation block below:
#   1. its body carries `Mandated-By: <rule-id>` on a line of its own,
#   2. that id carries `[mandates-filing]` in the MERGE-BASE corpus,
#   3. the issue is OPEN, and
#   4. the PR body carries a `Tracks|Refs #<issue>` companion.
# It is NOT self-serve: (2) is a human-gated corpus edit under ADR-092, so an
# agent can only ever name one of N already-blessed rules. It is also not
# unforgeable — this gate runs in a process the claimant controls, and
# SOLEUR_SKIP_NET_ISSUE_FLOW_GATE=1 sits a few lines above. What it buys is a
# closed vocabulary and per-rule attribution, not tamper-evidence; do not
# describe it as the latter. Every condition fails CLOSED. See ADR-155.
#
# Fail-open, not fail-silent
# --------------------------
# A gh/API error yields exit 0 so an outage cannot wedge every merge — but each
# fail-open emits telemetry via emit_incident. A gate that fails open silently
# is indistinguishable from a gate that passes.
#
# The fail-open event_type is `warn`, NOT `transient`: rule-metrics-aggregate.sh
# counts only deny/bypass/applied/warn, so a `transient` row would increment
# nothing — and the operator could not tell "gate never fired" from "gate
# fail-opened on every invocation", which is precisely the claim above.
#
set -uo pipefail
export LC_ALL=C

MARKER='<!-- gate-override: net-issue-flow -->'
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# Telemetry. Never wrap emit_incident in $(...) or a pipe — its output IS the
# telemetry write.
# CODE ROOT, not a data root (#7450; ADR-179's classification). Sourced, so it
# executes in THIS shell — never derive it from `git rev-parse --show-toplevel`,
# which on the review path is the contributor's checked-out tree. This is a ship
# gate, so a same-named file in a hostile PR would run with the gate's authority.
# CLAUDE_PROJECT_DIR comes from the harness, not from the tree under review.
#
# REPO_ROOT above is unchanged, but NOT because its other uses are all data-root
# reads — an earlier revision of this comment claimed that and it was FALSE.
# `python3 "$REPO_ROOT/scripts/lint-rule-bodies.py"` below EXECUTES a repo-root
# path, which is a code root by ADR-179's classification table. It is the table's
# "repo-root `scripts/` class: executes, target outside the payload" row, whose
# stated disposition is **route to #7453** — so it is deferred, not resolved, and
# this comment must not read as though the file were finished. The `source` above
# is the part #7450 fixes; the `python3` below is the part #7453 owns.
# Resolution, in trust order, and NEVER from `git rev-parse --show-toplevel`:
#   1. CLAUDE_PROJECT_DIR — supplied by the harness, not by the tree under review.
#      Measured 2026-08-12: unset in a plain Claude Code session and in git hooks,
#      so it cannot be the ONLY arm without silently retiring this telemetry.
#   2. This script's OWN location. Layout-invariant per ADR-178, and crucially NOT
#      CWD-derived: a `gh pr checkout` cannot redirect it, because by the time this
#      line runs the anchor decision has already been made — if a hostile script
#      were executing, sourcing its sibling lib adds nothing. On a plugin INSTALL
#      the walk lands somewhere with no such lib, so it no-ops, which is correct.
# The `-f` test is the safety net for both arms: a wrong root simply no-ops.
_incidents_root="${CLAUDE_PROJECT_DIR:-$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../../../../.." 2>/dev/null && pwd -P)}"
_incidents="${_incidents_root:+${_incidents_root}/.claude/hooks/lib/incidents.sh}"
if [[ -n "$_incidents" && -r "$_incidents" ]]; then
  # shellcheck disable=SC1090
  source "$_incidents" 2>/dev/null || true
fi
# Emit under an explicit rule_id. Per-rule attribution MUST ride in the
# STRUCTURED rule_id, never the free-text prefix — the aggregator keys every
# counter on rule_id and does not parse rule_text_prefix, so an attribution
# written into the prefix is unreadable by construction. See ADR-155 (b).
# Every id here keeps the `net-issue-flow` prefix, which rule-metrics-aggregate.sh
# already exempts from the orphan gate.
_NIF_TMP=()

_emit_as() {
  if declare -F emit_incident >/dev/null 2>&1; then
    emit_incident "$1" "$2" "$3" || true
  fi
}
_emit() { _emit_as "net-issue-flow" "$@"; }

_fail_open() {
  printf '\n'
  printf 'net-issue-flow: TRANSIENT — could not compute net flow (%s).\n' "$1"
  printf '  Failing OPEN so an API outage cannot wedge every merge.\n'
  printf '  This is recorded as telemetry, not swallowed.\n'
  _emit warn "net-issue-flow fail-open: $1"
  exit 0
}

if [[ "${SOLEUR_SKIP_NET_ISSUE_FLOW_GATE:-0}" == "1" ]]; then
  printf 'net-issue-flow: SKIPPED via SOLEUR_SKIP_NET_ISSUE_FLOW_GATE=1.\n'
  _emit bypass "net-issue-flow skipped via env"
  exit 0
fi

PR_NUMBER="${1:-}"
if [[ -z "$PR_NUMBER" ]]; then
  PR_NUMBER="$(gh pr view --json number --jq .number 2>/dev/null)" \
    || _fail_open "could not resolve PR number"
fi
[[ "$PR_NUMBER" =~ ^[0-9]+$ ]] || _fail_open "PR number is not a positive integer: '$PR_NUMBER'"

PR_BODY="$(gh pr view "$PR_NUMBER" --json body --jq .body 2>/dev/null)" \
  || _fail_open "could not read PR #${PR_NUMBER} body"

PR_CREATED_AT="$(gh pr view "$PR_NUMBER" --json createdAt --jq .createdAt 2>/dev/null)" \
  || _fail_open "could not read PR #${PR_NUMBER} createdAt"
[[ -n "$PR_CREATED_AT" ]] || _fail_open "PR #${PR_NUMBER} createdAt was empty"

# --- Fence-strip the PR body ONCE, before anything reads it ------------------
# Every consumer of the PR body must see the stripped form. Computing this
# lazily next to the override check (where it used to live) left CLOSING reading
# the RAW body, so a fenced `Closes #4242` — a quoted commit message, diff, or
# issue body, which is routine in this repo's PR descriptions — bought a unit of
# NET credit against a BLOCKING gate. Measured: raw body yields CLOSING=1 on a
# fenced keyword, stripped yields 0. Same self-override class the marker match
# already guards, reached through the CLOSING path instead.
# `END { if (in_fence) exit 2 }` mirrors ship-operator-step-gate.sh and
# ship-soak-followthrough-gate.sh. Without it an unbalanced fence degrades to
# "strip nothing after the opener" — and the jq stripper in this same file
# already fails closed, so the two halves disagreed.
PR_FENCE_RC=0
PR_BODY_SCAN="$(printf '%s\n' "$PR_BODY" | awk '
  /^[[:space:]]*```/ { in_fence = !in_fence; next }
  !in_fence { print }
  END { if (in_fence) exit 2 }
')" || PR_FENCE_RC=$?

# An unbalanced fence is NOT a degraded read to be swallowed. Both strippers
# yield the empty string on it, and the two halves fail in OPPOSITE directions:
# CLOSING drops to 0 (fail-closed, harmless), while `$declared` drops to empty —
# which deletes the entire declared-filing arm. For a filing that cites the
# originating ISSUE rather than the PR, that arm is the ONLY one that can see it,
# so a single unclosed ``` turns a net-positive PR into `Filing: 0 / PASS`, with
# no residual line and no telemetry. Measured on the pristine gate (#7896 review).
#
# The header above used to claim this path "fails closed" by analogy with the two
# sibling ship gates. That is true of the EXEMPTION (a claim that cannot match
# grants nothing) and exactly backwards for FILED. Abort instead: the body is
# unparseable, and a gate that cannot read its input must not report a verdict.
if [[ "$PR_FENCE_RC" -ne 0 ]]; then
  printf '\nnet-issue-flow: BLOCKED — PR #%s has an unbalanced code fence.\n\n' "$PR_NUMBER"
  printf 'The body cannot be parsed, so neither the closing keywords nor the\n'
  printf '`Filed:` declaration can be read, and a verdict computed from an\n'
  printf 'unreadable body would be meaningless. Close the fence and re-run.\n'
  _emit_as net-issue-flow-unbalanced-fence deny "PR body has an unbalanced code fence"
  exit 1
fi

# --- CLOSING: issues this PR closes via close-keywords in its body -----------
# WORD-BOUNDARY the keywords, and drop the PR own number.
#
# Without `\b` the alternation matches INSIDE a longer word: `unclosed #4242`,
# `disclosed #N` and `foreclosed #N` each bought a full -1 of NET credit for a
# close GitHub will never perform. Measured (#7896 review): a body reading
# "This is unclosed #4242." reported `Closing: 1 (#4242)`.
#
# `$prnum` is stripped here for the same reason the declared arm strips it: #N
# inside PR N is a self-reference, and `Closes #<own PR>` was a free unit of
# credit. The declared arm already had this guard; CLOSING did not.
#
# Both are pre-existing, and both got materially cheaper to exploit with this
# change: before the declared-filing arm, FILED was usually 0 on the shapes that
# matter, so there was nothing for a bogus CLOSING to neutralise.
CLOSING_NUMS="$(printf '%s\n' "$PR_BODY_SCAN" \
  | grep -oiE '(^|[^A-Za-z])(close[sd]?|fix(e[sd])?|resolve[sd]?) #[0-9]+' \
  | grep -oE '[0-9]+' \
  | grep -vxF "$PR_NUMBER" \
  | sort -un || true)"
CLOSING=0
[[ -n "$CLOSING_NUMS" ]] && CLOSING="$(printf '%s\n' "$CLOSING_NUMS" | grep -c . || true)"

# --- Mandating rules: the qualifying set, DERIVED from the corpus ------------
# Not a list in this script. A restated list is a second pin, and the copy that
# drifts is the one that runs. The set is every rule line in AGENTS.rules.md
# carrying the `[mandates-filing]` marker.
#
# Read from the MERGE-BASE, never the worktree and never a bare `:path`:
#   * the worktree is author-controlled, so a PR could tag a rule and exempt
#     itself in the same diff;
#   * `git show ":AGENTS.rules.md"` (no ref) reads the STAGED INDEX — also
#     author-controlled, and measured to return rc=0 with a full id list, so
#     the read "succeeds" and no empty-set warning fires. That is the worst
#     shape: a fail-open that looks like a successful read.
# Hence the explicit SHA guard: nothing reaches `git show` unless the base
# resolved to something that looks like an object name.
#
# Extraction is restricted to `^(hr|wg)-` so the derived set is BY CONSTRUCTION
# a subset of the ADR-092 ack gate's coverage (`GATED_PREFIX_RE` in
# lint-rule-bodies.py). Without it, a `cq-*` rule could carry the marker and
# grant exemption authority with no ack required — 27 of 101 ids sit outside
# that gate.
#
# Per-LINE matching (marker and id on the same line), not adjacency: robust to
# tag placement and to a trailing `**Why:**` clause.
MANDATING_IDS=""
CORPUS_NOTE=""
MB="$(git merge-base origin/main HEAD 2>/dev/null || true)"
if [[ ! "$MB" =~ ^[0-9a-f]{7,40}$ ]]; then
  CORPUS_NOTE="corpus unreadable: merge-base did not resolve — exemption unavailable"
  _emit_as net-issue-flow-mandated-filing-corpus-unreadable warn "merge-base did not resolve pr=${PR_NUMBER}"
else
  CORPUS_TEXT="$(git show "${MB}:AGENTS.rules.md" 2>/dev/null || true)"
  if [[ -z "$CORPUS_TEXT" ]]; then
    CORPUS_NOTE="corpus unreadable: AGENTS.rules.md absent at merge-base — exemption unavailable"
    _emit_as net-issue-flow-mandated-filing-corpus-unreadable warn "AGENTS.rules.md absent at merge-base pr=${PR_NUMBER}"
  else
    # Derived by the ADR-092 gate's OWN parser, not by a second grep here.
    # `parse_bodies` requires four conjuncts (gated `## SECTION`, `- ` at column
    # 0, not pointer-shaped, `^(hr|wg)-`); a shell grep enforces only the last,
    # so it is a strict SUPERSET along the line-shape axis — an indented
    # sub-bullet or a prose line carrying the marker would be honoured here
    # while being invisible to the ack gate, the manifest and lint-rule-ids.py.
    # Measured on the shipped corpus: the grep form derived 4 ids to
    # parse_bodies' 2. Fails CLOSED on any error (missing python3, parse
    # failure, non-zero exit) — an empty set means the exemption is unavailable.
    MANDATING_IDS="$(printf '%s\n' "$CORPUS_TEXT" \
      | python3 "$REPO_ROOT/scripts/lint-rule-bodies.py" --emit-mandating-ids 2>/dev/null \
      || true)"
    if [[ -z "$MANDATING_IDS" ]]; then
      CORPUS_NOTE="corpus read OK, zero rules tagged — exemption inactive"
      _emit_as net-issue-flow-mandated-filing-zero-tagged warn "zero rules tagged at base=${MB:0:12} pr=${PR_NUMBER}"
    fi
  fi
fi

# "read failed" and "read OK, nothing tagged" get DIFFERENT rule_ids above.
# Collapsing them is the same defect this gate's header condemns: the operator
# could not tell "never fired" from "fail-opened on every invocation".
MANDATING_JSON="$(printf '%s\n' "$MANDATING_IDS" \
  | jq -R -s -c 'split("\n") | map(select(length > 0))' 2>/dev/null)" \
  || _fail_open "could not encode the mandating-rule set"

# --- FILED: issues created after this PR that bare-reference it --------------
# No --search, no label filter, --state all, --limit 500. See header.
# `state` is new: the exemption requires the issue to be OPEN, and an ABSENT
# state must fail closed rather than read as OPEN.
ISSUES_JSON="$(gh issue list --state all --limit 500 --json number,body,createdAt,state 2>/dev/null)" \
  || _fail_open "could not list issues"
[[ -n "$ISSUES_JSON" ]] || _fail_open "issue list returned empty"

# ONE jq pass over the ~2 MB payload. A per-issue subprocess loop for the
# fence-strip measured >=1.7 s of fork overhead alone against ~1.0 s for this;
# the gate's total budget is what the hook's timeout has to clear.
# The PR body goes to jq via --rawfile, NOT --arg. Linux caps a single argv
# element at MAX_ARG_STRLEN (32 * PAGESIZE = 131072 bytes on this host, measured:
# 131000 bytes runs, 131072 exits 126 "Argument list too long"). Past that jq is
# never exec-ed, the capture fails, and control lands on _fail_open -- which
# prints TRANSIENT and exits 0. A PR author padding their own body past the cap
# therefore turned this BLOCKING gate into an unconditional PASS, indistinguishable
# in telemetry from a real GitHub outage. That is a sixth member of the
# always-pass family this file header enumerates, and it sat on the very jq call
# the declared-filing arm was added to. A file has no such cap.
_PRBODY_FILE="$(mktemp -t net-issue-flow-prbody.XXXXXXXX)"
_NIF_TMP+=("$_PRBODY_FILE")
trap 'rm -f -- "${_NIF_TMP[@]}"' EXIT
printf '%s' "$PR_BODY" > "$_PRBODY_FILE"

GATE_ROWS="$(printf '%s' "$ISSUES_JSON" | jq -r \
  --arg pr "$PR_NUMBER" \
  --arg since "$PR_CREATED_AT" \
  --rawfile prbody "$_PRBODY_FILE" \
  --arg closing "$CLOSING_NUMS" \
  --argjson ok "$MANDATING_JSON" '
  # Fenced blocks are stripped from BOTH corpora before matching. An UNBALANCED
  # fence yields the empty string, so nothing can match and the issue fails
  # closed — matching the two sibling ship gates, which end with
  # `END { if (in_fence) exit 2 }`. This gate previously had neither.
  def sf:
    (. // "") | split("\n")
    | reduce .[] as $l ({inf: false, out: []};
        if ($l | test("^[ \t]*```")) then .inf = (.inf | not)
        elif .inf then .
        else .out += [$l] end)
    | if .inf then "" else (.out | join("\n")) end;

  # A claim is a WHOLE LINE. `\r` is mandatory: GitHub returns CRLF bodies for
  # web-authored text, and a [ \t]-only anchor fails closed on a correct claim.
  # The KEY tolerates only `Mandated-By:`/`mandated-by:` case variants on its
  # first letters (NOT `MANDATED-BY:`); the ID is matched case-insensitively and
  # downcased, so `Mandated-By: WG-BLOCK-...` resolves.
  def claims:
    sf | split("\n")
    | map(select(test("^[ \t\r]*[Mm]andated-[Bb]y:[ \t\r]*[A-Za-z0-9-]+[ \t\r]*$")))
    | map(capture("[Mm]andated-[Bb]y:[ \t\r]*(?<id>[A-Za-z0-9-]+)").id | ascii_downcase);

  # --- #7759: the DECLARED filing set, derived from the PR own body -------
  #
  # Both sets are derived HERE, inside the pass that already receives $prbody —
  # never in bash. A bash form (`grep -oE … | jq … || _fail_open`) fails the gate
  # OPEN under `set -uo pipefail` on every PR whose body names no issue, because
  # grep exits 1 on no-match; measured at 46 of 300 PRs. It would also invert the
  # deliberately fail-CLOSED unbalanced-fence path into a fail-open.
  #
  # LOOKBEHIND, not a consuming boundary group: `(^|[^0-9A-Za-z])` consumes the
  # separator, so `#1#2` yields only [1] — the second member of every adjacent
  # pair is dropped. Measured.
  def refs: [ scan("(?<![0-9A-Za-z])#([0-9]+)") | .[0] | tonumber ];

  ($prbody | sf) as $pb
  | ($closing | split("\n") | map(select(length > 0) | tonumber)) as $closenums
  | ($pr | tonumber) as $prnum

  # DECLARED — the only set that COUNTS. A whole-line assertion of the filing
  # relationship, produced by /ship Phase 6, not inferred from prose.
  #
  # ONE keyword, and the colon is MANDATORY. The first cut of this arm accepted
  # `(Filed|Tracks|Refs):?`, which reads as generous and is not: `Tracks #N` and
  # `Refs #N` are PRE-EXISTING vocabulary in this repo (the
  # wg-block-pr-ready-on-undeferred-operator-steps companion, and ~15 script
  # headers citing provenance), and `Refs:` is ordinary prose. Measured on a real
  # line in this repo — `Refs: #6588, #6897, #6604, #6570. Prior decision: #6918`
  # — the wide form admitted FIVE issues as this filings of this PR, including the one
  # the line itself labels "Prior decision". That is the sibling-attribution failure
  # (P4) the ADR uses to reject option 2 of the issue, reintroduced through the
  # arm that replaced it. `Filed:` is the one shape with a producer behind it.
  #
  # A leading list marker and surrounding emphasis are tolerated because they are
  # what an author actually writes; the anchor still forbids mid-line prose, so a
  # sentence mentioning the word cannot declare anything. Case-insensitive on the
  # keyword only.
  #
  # `$closenums` is deliberately NOT subtracted. It used to be, and that let one
  # `Closes #N` line delete a declared filing from FILED *and* claim a close
  # credit for it — a two-unit NET swing, with the number then absent from every
  # printed line. Measured: `Filed: #7001` + `Closes #7001` reported
  # `Closing: 1 / Filing: 0 / Net: -1 / PASS`. A number on both lines is a
  # contradiction in the PR body; it is surfaced below and left in BOTH terms, so
  # it nets to zero honestly instead of buying credit.
  | ( [ $pb | split("\n")[]
        | select(test("^[ \t\r]*([-*+][ \t]+)?[*_]*[Ff][Ii][Ll][Ee][Dd][*_]*:[*_]*[ \t]*#[0-9]"))
        | refs[] ]
      | unique | map(select(. != $prnum)) ) as $declared

  # CONTRADICTORY — declared as filed AND named by a close keyword. Reported, and
  # left in both terms rather than cancelled.
  | ( $declared | map(select(IN($closenums[]))) ) as $contradictory

  | [ .[]
      | select((.createdAt // "") >= $since)
      # SIBLING DISJUNCTION over the same array, with the createdAt guard kept
      # as its own conjunct above. The body-cites-PR arm is unchanged.
      | select(
            ((.body // "") | test("(^|[^0-9A-Za-z])#" + $pr + "([^0-9]|$)"))
          # `.number | IN($declared[])`, NOT `$declared | index(.number)`:
          # the pipe re-binds `.` to $declared, so `.number` would index an
          # ARRAY with a string and abort the whole pass into _fail_open.
          or (.number | IN($declared[]))
        )
    ]
  | unique_by(.number) | sort_by(.number)
  | map(
      . as $i
      | ($i.body | claims) as $c
      | (
          # This rung FIRST: with an empty set every claim would otherwise be
          # reported as "names a rule that does not carry [mandates-filing]",
          # which is false and actively misleading during rollout — the rule
          # usually DOES carry it, the corpus just was not readable at this
          # merge-base. Telling an agent its correct claim is wrong sends it to
          # guess another id, which the help text explicitly warns against.
          if   ($ok | length) == 0 then "exemption inactive here (no qualifying rules at this merge-base)"
          elif ($c | length) == 0 then "no Mandated-By: claim"
          elif ($c | length) > 1  then "multiple Mandated-By: claims"
          elif ($ok | index($c[0])) == null then "claim names a rule that does not carry [mandates-filing]: " + $c[0]
          elif ($i.state // "") != "OPEN" then "issue is not OPEN: " + ($i.state // "<absent>")
          # The companion asks one question: does the PR body positively name
          # this issue? A `Filed:` declaration answers it — it is a STRONGER,
          # whole-line assertion of the same relationship. Before this was
          # widened, `Filed: #N` (the exact line /ship Phase 6 instructs) was the
          # one shape that admitted a mandated filing to FILED while denying it
          # the exemption, and the rejection printed "PR body has no Tracks/Refs
          # #N companion" over a body that declared #N verbatim. The remediation
          # then looped: the help text says to add `Tracks #N`, and an agent that
          # wrote `Tracks: #N` got the identical message. Measured (#7896 review).
          elif ((($i.number | IN($declared[]))
                 or ($pb | test("(^|[^A-Za-z])(Tracks|Refs)[ \t]+#" + ($i.number | tostring) + "([^0-9]|$)"))) | not)
            then "PR body neither declares `Filed: #" + ($i.number | tostring) + "` nor carries a `Tracks #" + ($i.number | tostring) + "` companion"
          else "" end
        ) as $why
      # FOUR fields now. `attribution` goes BEFORE `detail` because detail is
      # FREE TEXT and must stay last — a rejected row detail contains spaces,
      # and @tsv + `read` would otherwise shift every later field.
      | [ ($i.number | tostring),
          (if $why == "" then "exempt" else "rejected" end),
          (if (($declared | index($i.number)) != null)
              and (((.body // "") | test("(^|[^0-9A-Za-z])#" + $pr + "([^0-9]|$)")) | not)
           then "pr-body" else "issue-body" end),
          (if $why == "" then $c[0] else $why end) ]
      | @tsv
    )
  | . as $rows
  | ($rows | map(split("\t")[0] | tonumber)) as $counted
  | $rows[],
    # Two trailing sentinel rows. Both are report-only, both are consumed by the
    # loop below and never counted, and `_num` is non-numeric on each so neither
    # can be mistaken for an issue row.
    #
    # SENTINEL every field, never emit one empty. Tab is IFS-WHITESPACE, so
    # `read -r a b c d` COLLAPSES an empty middle field and every later field
    # shifts left.
    #
    # UNDELIVERED replaces an earlier "possible unattributed filings" set that was
    # computed from the PR body ALONE — it never joined the issue array, so it had
    # no recency filter, no existence check, and no exclusion of rows the gate had
    # already counted. Live on merged PR #7702 it printed five numbers of which
    # FOUR were simultaneously in `Filing: 4`, alongside a prose cross-reference to
    # an unrelated merged PR; the parenthetical "not counted" was false for most of
    # the line. It reported every issue number a body happened to mention, so the
    # drift metric built on it sat at ceiling and could not rise informatively.
    #
    # What replaces it is true by construction: numbers the PR DECLARED that did
    # not become a counted row. Those are the declarations the gate could not
    # honour — the issue predates the PR, is outside the fetched window, is in
    # another repo, or does not exist — and every one of them was previously
    # dropped from FILED *and* suppressed from the residual, i.e. silent.
    ("__UNDELIVERED__\t"
     + (($declared | map(select(IN($counted[]) | not)))
        | if length == 0 then "NONE" else (map(tostring) | join(" ")) end)
     + "\t-\t-"),
    ("__CONTRADICTORY__\t"
     + ($contradictory
        | if length == 0 then "NONE" else (map(tostring) | join(" ")) end)
     + "\t-\t-")' 2>/dev/null)" \
  || _fail_open "could not parse issue list"

FILED=0
EXEMPT=0
FILED_NUMS=""
EXEMPT_DETAIL=""
REJECTED_DETAIL=""
ATTRIBUTED_NUMS=""
UNDELIVERED_NUMS=""
CONTRADICTORY_NUMS=""
while IFS=$'\t' read -r _num _verdict _attr _detail; do
  [[ -z "$_num" ]] && continue
  # The report-only sentinel. Non-numeric by construction so it can never be
  # mistaken for an issue row, and handled BEFORE the FILED increment so it
  # cannot touch the count.
  if [[ "$_num" == "__UNDELIVERED__" ]]; then
    [[ "$_verdict" == "NONE" ]] || UNDELIVERED_NUMS="$_verdict"
    continue
  fi
  if [[ "$_num" == "__CONTRADICTORY__" ]]; then
    [[ "$_verdict" == "NONE" ]] || CONTRADICTORY_NUMS="$_verdict"
    continue
  fi
  FILED=$((FILED + 1))
  FILED_NUMS+="$_num "
  # Derived from the rows ACTUALLY COUNTED, never from $declared — otherwise the
  # report and the count can desynchronise and the line becomes a second claim
  # rather than a view of the first.
  [[ "$_attr" == "pr-body" ]] && ATTRIBUTED_NUMS+="$_num "
  if [[ "$_verdict" == "exempt" ]]; then
    EXEMPT=$((EXEMPT + 1))
    EXEMPT_DETAIL+="#${_num} via ${_detail}; "
    # Per-rule attribution lives in the STRUCTURED rule_id, not the free-text
    # prefix field, so `summary.gate_exemptions` can group by rule without
    # parsing prose. Still covered by the aggregator's net-issue-flow* prefix.
    # Safe to interpolate: on the exempt path $_detail is a corpus-derived id,
    # constrained to [a-z0-9-] by parse_bodies. Rejected rows carry free text and
    # never reach here.
    _emit_as "net-issue-flow-mandated-filing--${_detail}" bypass "exempt pr=${PR_NUMBER} issue=${_num}"
  else
    REJECTED_DETAIL+="#${_num} (${_detail}); "
  fi
done <<< "$GATE_ROWS"

NET=$(( FILED - EXEMPT - CLOSING ))

# --- Display: always emitted, enumerating the actual numbers -----------------
# `Filing:` keeps its TRUE count. An exemption that silently reduces it is worse
# than the blanket override, which at least leaves a marker in the PR body.
_fmt() { if [[ -z "$1" ]]; then printf 'none'; else printf '%s' "$(printf '#%s ' $1 | sed 's/ $//')"; fi; }
_fmt_pairs() { if [[ -z "$1" ]]; then printf 'none'; else printf '%s' "${1%%'; '}"; fi; }
printf '\n'
printf 'PR #%s net-issue-flow:\n' "$PR_NUMBER"
if [[ -n "$CORPUS_NOTE" ]]; then
  printf '  Mandating rules: 0  (%s)\n' "$CORPUS_NOTE"
else
  printf '  Mandating rules: %s  (%s, merge-base %s)\n' \
    "$(printf '%s\n' "$MANDATING_IDS" | grep -c . || true)" \
    "$(printf '%s' "$MANDATING_IDS" | tr '\n' ' ' | sed 's/ $//')" \
    "${MB:0:12}"
fi
printf '  Closing: %s  (%s)\n' "$CLOSING" "$(_fmt "$CLOSING_NUMS")"
printf '  Filing:  %s  (%s)\n' "$FILED" "$(_fmt "$FILED_NUMS")"
printf '  Exempt:  %s  (%s)\n' "$EXEMPT" "$(_fmt_pairs "$EXEMPT_DETAIL")"
# #7759: attribution provenance, and the report-only residual.
if [[ -n "$ATTRIBUTED_NUMS" ]]; then
  printf '  Attributed: %s  (subset of Filing:, admitted via the PR declared filing line)\n' \
    "$(_fmt "$ATTRIBUTED_NUMS")"
  _emit_as net-issue-flow-body-attributed applied \
    "declared-arm fired pr=${PR_NUMBER} issues=$(printf '%s' "$ATTRIBUTED_NUMS" | tr -s ' ' ',' | sed 's/,$//')"
fi
if [[ -n "$UNDELIVERED_NUMS" ]]; then
  printf '  Undelivered declarations: %s  (declared on the Filed: line, no matching issue in range)\n' \
    "$(_fmt "$UNDELIVERED_NUMS")"
  _emit_as net-issue-flow-undelivered-declaration warn \
    "declared but not counted pr=${PR_NUMBER} issues=$(printf '%s' "$UNDELIVERED_NUMS" | tr -s ' ' ',' | sed 's/,$//')"
fi
if [[ -n "$CONTRADICTORY_NUMS" ]]; then
  printf '  Contradictory: %s  (on BOTH the Filed: line and a close keyword — counted in both terms)\n' \
    "$(_fmt "$CONTRADICTORY_NUMS")"
  _emit_as net-issue-flow-contradictory-declaration warn \
    "declared filed and closed pr=${PR_NUMBER} issues=$(printf '%s' "$CONTRADICTORY_NUMS" | tr -s ' ' ',' | sed 's/,$//')"
fi
if [[ -n "$REJECTED_DETAIL" ]]; then
  printf '  Rejected: %s\n' "$(_fmt_pairs "$REJECTED_DETAIL")"
fi
printf '  Net:     %+d  (positive = backlog growth)\n' "$NET"

if [[ "$NET" -le 0 ]]; then
  printf '\nnet-issue-flow: PASS (net <= 0).\n'
  _emit applied "net-issue-flow pass net=${NET} pr=${PR_NUMBER}"
  exit 0
fi

# --- NET > 0: override or block ---------------------------------------------
# $PR_BODY_SCAN is the fence-stripped body, computed once near the top. The
# BLOCKED message below PRINTS the literal marker, so an agent that pastes a
# gate failure into the PR description as context would otherwise smuggle in its
# own override — reported as OVERRIDDEN with a bypass event, while nothing in
# the body reads as a deliberate decision. Same self-override class the hook
# header guards against for spec files, via a different corpus path.
if printf '%s' "$PR_BODY_SCAN" | grep -qF -- "$MARKER"; then
  printf '\nnet-issue-flow: OVERRIDDEN via the gate-override marker in the PR body.\n'
  printf '  Net is +%d; the override is recorded as a deliberate decision.\n' "$NET"
  _emit bypass "net-issue-flow overridden net=${NET} pr=${PR_NUMBER}"
  exit 0
fi

printf '\n'
printf 'net-issue-flow: BLOCKED — this PR is net-positive (+%d) on the issue queue.\n' "$NET"
printf '\n'
printf 'Every PR must close at least as many issues as it files. Filing is free;\n'
printf 'closing is expensive, and the queue grows by roughly the difference.\n'
printf '\n'
printf 'Resolve via one of:\n'
printf '  (a) Fix inline — fold the filed work into THIS PR. The cost-of-filing\n'
printf '      auto-flip (<=100 lines AND <=4 files) already covers most of it.\n'
printf '      NOTE this is a SIZE test. If the blocker is AUTHORITY (an\n'
printf '      operator-only credential or production decision), (a) does not\n'
printf '      apply no matter how small the diff would be — see (d).\n'
printf '  (b) Close something — if a filed issue supersedes an open one, close it\n'
printf '      AND add the `Closes #N` keyword to the PR body. CLOSING is parsed\n'
printf '      from the body only; closing on GitHub alone changes nothing here.\n'
printf '  (c) Override — add to the PR body:\n'
printf '        %s\n' "$MARKER"
printf '      plus a one-line justification per filed issue, or run with\n'
printf '      SOLEUR_SKIP_NET_ISSUE_FLOW_GATE=1.\n'
printf '      This is the general escape hatch, NOT an architectural-pivot-only\n'
printf '      one. Real uses include architectural pivots, but also filings from\n'
printf '      SKILL.md phase mandates that carry no rule id to cite in (d), and\n'
printf '      discovered defects in another subsystem that must stay separate.\n'
printf '      Describe the actual reason; do not reach for a criterion that does\n'
printf '      not fit. A hatch that has to be mis-described gets taken reflexively.\n'
printf '  (d) Mandated filing — the issue was REQUIRED by a rule that carries\n'
printf '      [mandates-filing] in AGENTS.rules.md. Put on its own line in the\n'
printf '      ISSUE body:\n'
printf '        Mandated-By: <rule-id>\n'
printf '      and a `Tracks #<issue>` / `Refs #<issue>` companion in the PR body,\n'
printf '      and keep the issue OPEN. The exemption is shown on its own line in\n'
printf '      the report above; it never reduces the Filing: count.\n'
if [[ -n "$MANDATING_IDS" ]]; then
  printf '      Rules that currently qualify:\n'
  printf '%s\n' "$MANDATING_IDS" | sed 's/^/        /'
  printf '      If the rule that forced your filing is NOT in that list, (d) is\n'
  printf '      unavailable to you — do not guess another id, it will be rejected.\n'
  printf '      Use (c) and say so, or propose tagging the rule in its own PR.\n'
else
  printf '      No rules currently qualify (%s),\n' "${CORPUS_NOTE:-none tagged}"
  printf '      so (d) is unavailable on this run — use (c).\n'
fi
_emit deny "net-issue-flow blocked net=${NET} pr=${PR_NUMBER}"
exit 1
