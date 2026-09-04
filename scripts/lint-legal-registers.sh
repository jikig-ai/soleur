#!/usr/bin/env bash
# lint-legal-registers.sh -- integrity predicate over the legal registers.
#
# WHY THIS EXISTS (#7717). No lint covered the legal REGISTER FILES. Every other wired legal lint
# targets `docs/legal/` and its Eleventy mirror; the KB-legal reach is a 3-site list in
# `apps/web-platform/test/legal-doc-consistency.test.ts` plus the single-file
# `tenant-dpa-register-guard.sh`, and `scripts/lint-infra-no-human-steps.py` reaches
# `knowledge-base/legal/runbooks` through its SCAN_DIRS.
#
# This header claimed "nothing structurally lints knowledge-base/legal/** ... the first
# corpus-level gate over that tree" until review falsified both halves -- the runbooks ARE
# scanned, and the six-site figure measured 3. The narrower claim is the true one and is the
# load-bearing one. Being first over the registers is why it lands ADVISORY (see --advisory
# below) rather than straight onto the one required context that cannot be un-required.
#
# THREE ASSERTIONS.
#
#   (a) TOKEN CLASS, scoped to the REGISTER FILES -- not the whole corpus.
#       `knowledge-base/legal/audits/` is a WORKING-DOCUMENT tree: 41 files on `main` (24 of them
#       named `*counsel-review*`; "41 counsel reviews" was the wrong noun for the right number)
#       at 2026-09-03 (42 at this PR's HEAD, which adds one) that
#       legitimately use an unresolved marker for an open counsel question. A corpus-wide gate
#       would red the required context on every future counsel review, and would contradict
#       assertion (c) below, which deliberately scopes its own producer to `audits/**`. One
#       script taking opposite scoping decisions in its two halves is the defect; narrowing (a)
#       to the registers resolves both.
#       Measured 2026-09-03 on `main`: 8 hits across 4 files (a review seat reported 6; re-measured
#       against `origin/main` it is 8, so the original figure stood). Three are outside the
#       register scope by construction and are NOT waived, because they are not in scope to
#       begin with -- two live in a signed, dated counsel-review instrument (one of them a
#       backticked meta-reference reading "`#<TBD>` correctly resolved to #7500", which cannot
#       be made token-free without falsifying its own sentence), and one is an honest open
#       marker in a runbook.
#       INLINE CODE IS EXEMPT. The predicate is STANDALONE unresolved markers. A corpus that
#       documents its own convention must remain writable, and a register explaining that
#       `__TBD_X__` is a placeholder must not be red on its own gate.
#
#   (b) EVERY CANONICAL-SOURCE POINTER RESOLVES ON DISK.
#       A determination register whose pointers rot is worse than none: it asserts to a
#       supervisory authority that the documentation exists and can be produced. Row counting
#       is DELEGATED to `tenant-dpa-register-guard.sh` (parameterised at #7717) rather than
#       re-derived -- a second copy of a fail-closed table parser is how two parsers drift into
#       disagreeing about what a row is. That script already solves the vacuity trap its own
#       header records: `grep -c '^|' | test {} -ge 3` is vacuously true on an EMPTY register,
#       because the empty-state placeholder is itself a pipe-line.
#       NO COMMITTED ROW FLOOR, deliberately. Assertion (c) reds on any deleted row whose
#       source still exists, so a floor would uniquely cover only the single out-of-`audits/`
#       post-mortem row. That one path is asserted literally instead -- cheaper, and it names
#       what it protects.
#
#   (c) DECLARED-SET INTEGRITY, not discovered-set coverage.
#       Asserting coverage of a DISCOVERED set is not implementable here: 104 post-mortems
#       carry `art_33_triggered: false` from `templates/pir.md` as a SCREENING OUTPUT, and six
#       `audits/` files carry prose determinations with no such frontmatter. Any keyword
#       producer either captures the 102 or misses the prose -- the discriminator is semantic
#       and no regex makes a legal judgement. So the gate asserts integrity of the DECLARED
#       set: every `audits/**` file matching the determination-shaped pattern is either cited
#       by the register or carries a committed NOT_TRANSCRIBED waiver with a reason and an
#       issue citation.
#       PRODUCER SCOPED TO `audits/**`, WITH `post-mortems/**` EXCLUDED -- and the reason is
#       committed here rather than left to inference: 104 post-mortems carry the screening
#       frontmatter, so a producer that reaches them reds on all 102. The register legitimately
#       indexes ONE post-mortem; that is why membership is asserted by the waiver list rather
#       than by the producer's reach.
#
# FAIL-CLOSED. Exit 2 for "cannot decide" -- never a vacuous 0. A zero meaning "nothing
# matched" and a zero meaning "I could not read the corpus" are the same byte to the caller.
#
# Exit codes:  0 ok   1 assertion failed   2 cannot decide   (0 under --advisory unless 2)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# The guard's OWN operand, asserted rather than trusted. An empty or relative REPO_ROOT would
# degenerate every path below into a repo-relative glob that silently matches a different tree,
# and a guard that accepts everything is indistinguishable from a healthy run.
case "$REPO_ROOT" in
  /*) : ;;
  *)  echo "::error::lint-legal-registers: REPO_ROOT did not resolve to an absolute path" >&2; exit 2 ;;
esac
readonly REPO_ROOT

ADVISORY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    # ADVISORY FOR ONE MERGE CYCLE (#7717). This is the first lint over the legal REGISTER
    # FILES -- narrower than "the first lint over knowledge-base/legal/**", which this comment
    # claimed until self-review falsified it: `scripts/lint-infra-no-human-steps.py` already
    # scans `knowledge-base/legal/runbooks` via its SCAN_DIRS. No lint covered the registers.
    # Its scope was DESIGNED rather than measured. One cycle
    # advisory measures it; promotion is then deleting this flag at the `run_suite` call site
    # in scripts/test-all.sh, with evidence behind it. PROMOTION TRIGGER: one green merge cycle
    # with no unexplained finding. Tracked at #7787 with its checklist -- a follow-up with a
    # trigger, not a hope.
    --advisory) ADVISORY=1; shift ;;
    -h|--help)  echo "usage: lint-legal-registers.sh [--advisory]"; exit 0 ;;
    *)          echo "::error::lint-legal-registers: unknown option: $1" >&2; exit 2 ;;
  esac
done

die2() { echo "::error::lint-legal-registers: $1" >&2; exit 2; }

fails=0
checks=0
pass() { checks=$((checks + 1)); echo "[ok] $1"; }
fail() { checks=$((checks + 1)); fails=$((fails + 1)); echo "::error::$1" >&2; }

# INSTRUMENT SELF-TEST. A suite whose only gate is a failure counter can report success having
# asserted nothing. Drive both helpers once each and refuse to continue unless both counters
# moved (ADR-193).
_st_checks_before=$checks
{ pass "instrument self-test"; fail "instrument self-test"; } >/dev/null 2>&1
[[ $checks -eq $((_st_checks_before + 2)) ]] || die2 "instrument self-test: checks counter did not move twice"
[[ $fails -eq 1 ]] || die2 "instrument self-test: fails counter did not move"
fails=0; checks=$_st_checks_before

BREACH_REGISTER="$REPO_ROOT/knowledge-base/legal/breach-register.md"
AUDITS_DIR="$REPO_ROOT/knowledge-base/legal/audits"

# The register files (a) scans. Scoped, not corpus-wide -- see the header.
REGISTER_FILES=(
  "knowledge-base/legal/article-30-register.md"
  "knowledge-base/legal/article-30-2-register.md"
  "knowledge-base/legal/breach-register.md"
  "knowledge-base/legal/compliance-posture.md"
)

# Determination-shaped pattern for (c). Pinned literally: its cardinality decides the gate's
# character. The producer walks `audits/` RECURSIVELY (`find`, not a `*.md` glob): a bash `*` does
# not descend, so `mkdir audits/archive/` and filing the next determination there removed coverage
# with no signal at all -- `produced` simply stopped growing while the floor stayed satisfied by
# the top-level files. The repo already runs an `archive/` convention in other knowledge-base
# trees, so that was the plausible next move rather than a contrived one. At this pattern the producer matched 8 of 41 audits/ files on `main` at 2026-09-03,
# and 9 of 42 at this PR's HEAD (the guard's own summary prints `produced=`, which is the
# figure to trust; both numbers here were stated before the pattern was widened and were not
# recomputed after it) -- the extra is this PR's own implementation record, which quotes
# the article numbers and is therefore waived rather than indexed. Both figures are stated
# because a lone post-PR count reads as though it were the pre-existing corpus.
# WIDENED at review (#7782). The original `Art\. 33` missed the FORMAL spelling the corpus also
# uses -- `audits/sentry-migration-audit-2026-05-15.md:61` records "No personal data left the EEA.
# Article 33 (72-hour breach notification) does not trigger", an express notifiability
# determination INSIDE the scanned directory that the producer could not see, so the guard
# printed "all 7 determination-shaped files are indexed or waived" over it. Tolerates the
# abbreviation with or without the period, the spelled-out form, and internal spacing.
DETERMINATION_PATTERN='4[[:space:]]*\(12\)|33[[:space:]]*\(5\)|Art\.?[[:space:]]*33|Article[[:space:]]+33|Article[[:space:]]+4[[:space:]]*\(12\)'

# NOT_TRANSCRIBED waivers, in the repo's existing `path | reason citing #NNNN` shape -- the same
# shape as EXCLUSIONS, DENY and ALLOWLIST elsewhere, not a tenth novel one, so adding an entry
# is a diff a reviewer sees. Ruled per #7717; ADR-200 governs. A waiver with no issue citation
# is a REFUSAL, not a pass.
NOT_TRANSCRIBED=(
  "knowledge-base/legal/audits/2026-05-12-gdpr-gate-plan-phase-2-7-outcome.md | No Art. 4(12) assessment: never cites Art. 4(12), matched solely on one Art. 33 occurrence, and its non-notifiable statement is expressly attributed to the operator's framing rather than recorded as a controller determination (#7717)"
  "knowledge-base/legal/audits/2026-06-counsel-review-5103.md | No event and no determination: the sole Art. 33 occurrence verifies the accuracy of a statutory-deadline catalog entry, not a fact pattern (#7717)"
  "knowledge-base/legal/audits/2026-08-counsel-review-7440.md | Express Art. 4(12) assessment, but of a prospective PA-8 amendment with no fact pattern; a row would dilute the register with routine change approvals (#7717)"
  "knowledge-base/legal/audits/2026-05-17-sentry-ingest-window-auth-users-audit.md | Not a determination of its own: evidence INSIDE an already-indexed determination -- its frontmatter classifies it art-30-5-accountability-evidence and its incident_pir names the post-mortem the 2026-05-16 row indexes, and what it records is a population count. Indexing it would enter one incident twice. The producer match is a filing-posture reference, not a fact pattern assessed against Art. 4(12) -- true but thinner. Ruled #7717 B1, attested #7791 (#7717)"
  "knowledge-base/legal/audits/2026-09-03-implementation-record-7717-art-33-5-register.md | Not a determination: an implementation record ABOUT this register, which necessarily quotes the article numbers and so matches the producer pattern. It assesses no fact pattern and records no controller determination (#7717)"
  "knowledge-base/legal/audits/2026-09-counsel-review-7717.md | Not a determination: the COUNSEL REVIEW of this register (ship Phase 5.5 gate, 2026-09-03). It quotes Art. 4(12) and Art. 33(5) in order to rule on the inclusion predicate and so matches the producer, but it assesses no fact pattern and records no controller determination. Every future counsel review of this register needs the same waiver -- a known cost of scoping the producer to audits/**, not a defect (#7717)"
  "knowledge-base/legal/audits/2026-09-counsel-review-7625.md | Not a determination: the counsel review for the Art. 30 PA-7 §(c) / Art. 9 amendment (#7625). It cites Art. 4(12) only to record the NEGATIVE — that an Art. 30(1) record-keeping incompleteness is not a personal-data breach and triggers no Art. 33/34 duty — and assesses no fact pattern: nothing was destroyed, lost, altered or disclosed. Same shape as the #7440 waiver above (#7717)"
  "knowledge-base/legal/audits/2026-09-03-clo-review-7622-pa7-r2-evidence-layer.md | Not a determination: a retrospective record, written 2026-09-03, of the 2026-08-20 CLO review of PR #7622. It matches the producer because it transcribes that review's §(d) finding, which cites Art. 4(12) to conclude the omission was NOT a breach. The Art. 4(12) citation is quoted history, and the underlying matter was an Art. 30 Recipients-cell omission over processing that was contractually covered throughout (#7717)"
)

# The one indexed determination that lives outside the producer's scope. Asserted literally
# rather than by a row floor -- see the header, assertion (b).
OUT_OF_SCOPE_ROW="knowledge-base/engineering/operations/post-mortems/sentry-phantom-ingest-destination-unreachable-postmortem.md"

# ---------------------------------------------------------------------------------------
# (a) token class over the register files, standalone markers only
# ---------------------------------------------------------------------------------------
token_hits_total=0
scanned_registers=0
for rel in "${REGISTER_FILES[@]}"; do
  abs="$REPO_ROOT/$rel"
  [[ -f "$abs" && -r "$abs" ]] || die2 "register not readable: $rel"
  scanned_registers=$((scanned_registers + 1))
  # Strip inline-code spans before matching, so a backticked marker is exempt by construction.
  hits="$(sed 's/`[^`]*`//g' "$abs" \
    | grep -nEo '(__TBD_[A-Za-z_]*__|\bTBD\b|\bTODO\b|\bXXX\b|\bFIXME\b)' || true)"
  if [[ -n "$hits" ]]; then
    token_hits_total=$((token_hits_total + $(printf '%s\n' "$hits" | wc -l)))
    fail "unresolved marker in $rel:"
    printf '%s\n' "$hits" | sed 's/^/           /' >&2
  fi
done
[[ $scanned_registers -eq ${#REGISTER_FILES[@]} ]] || die2 "scanned $scanned_registers of ${#REGISTER_FILES[@]} registers"
if [[ $token_hits_total -eq 0 ]]; then
  pass "(a) no standalone unresolved marker in ${scanned_registers} register file(s)"
else
  # THE ACCEPTED-RESOLUTION SHAPE LIVES HERE, in the failure message, not in a note in another
  # file the engineer who trips this gate will never read. Without it the gate creates pressure
  # to substitute plausible text for an unresolved question -- and both of #7717's honest
  # resolutions are PROSE, not numbers, so the gate would otherwise cause the next fabricated
  # date. A note also could not live under knowledge-base/legal/** while naming these tokens:
  # it would be red on its own gate. The failure message is outside the scanned scope by
  # construction.
  {
    echo "::error::"
    echo "::error::HOW TO RESOLVE ONE. A number you cannot source is NOT the answer."
    echo "::error::  Art. 30(1)(f) says 'where possible'. An honest record of a gap is compliant;"
    echo "::error::  a plausible guess is not. Accepted resolutions:"
    echo "::error::    NOT RECORDED  -- with the reason it cannot be established, and the"
    echo "::error::                     unblocking condition (an issue, a verify_by date)."
    echo "::error::    NOT EXECUTED  -- for an instrument that does not exist. Drop any"
    echo "::error::                     adjacent word ('signed') that the token was carrying."
    echo "::error::    a cross-reference -- when the token was standing in for another cell."
    echo "::error::    a sourced value  -- with the producing source cited inline as Art. 5(2)"
    echo "::error::                     evidence."
    echo "::error::  If the marker is a meta-reference that cannot be removed without"
    echo "::error::  falsifying its sentence, put it in inline code -- backticked spans are"
    echo "::error::  exempt by construction."
  } >&2
fi

# ---------------------------------------------------------------------------------------
# (b) row count is decidable, and every canonical-source pointer resolves on disk
# ---------------------------------------------------------------------------------------
[[ -f "$BREACH_REGISTER" && -r "$BREACH_REGISTER" ]] || die2 "breach register not readable: $BREACH_REGISTER"

row_count="$(bash "$REPO_ROOT/scripts/tenant-dpa-register-guard.sh" \
  --register "$BREACH_REGISTER" \
  --section 'Index of determinations' \
  --anchor-column 'Canonical source' \
  --placeholder '__no_placeholder_row_in_this_register__' \
  count-data-rows)" || die2 "row counting refused on the breach register (delegated guard exited non-zero)"
case "$row_count" in ''|*[!0-9]*) die2 "unparseable row count '$row_count'" ;; esac
pass "(b) breach-register index is decidable: $row_count determination row(s)"

# Every cited canonical source resolves. The walk does NOT stop at the first bad row.
# SECTION-SCOPED, and the column is taken POSITIONALLY. Two honest limits, stated because an
# earlier comment here claimed this was "anchored on the canonical-source column" -- it is not;
# the DELEGATE resolves that column by name, this awk takes the last cell. They agree only while
# that column is last, which the reconciliation below turns into a loud failure rather than a
# silent one. Scoping to the index section stops a dated row elsewhere in the file (a reformatted
# §Excluded records table, say) from being read as an indexed determination.
cited_paths="$(awk -F'|' '
  function trim(s) { gsub(/^[ \t`]+|[ \t`]+$/, "", s); return s }
  /^##[ \t]/ { inblk = ($0 ~ /^##[ \t]+Index of determinations[ \t]*$/) }
  inblk && /^\|[ \t]*20[0-9][0-9]-/ { print trim($(NF-1)) }
' "$BREACH_REGISTER")"
[[ -n "$cited_paths" ]] || die2 "no determination rows parsed from the breach register index"

# CONTAINED, TRACKED, AND NOT A SYMLINK -- `-f` alone was three fail-opens. Assertion (b)'s
# stated purpose is that the documentation "exists AND can be produced", and a bare `-f` satisfies
# that check for things that cannot be produced: `../../../../../../etc/hostname` resolves (and
# survives a naive "must start with knowledge-base/" filter, since
# `knowledge-base/legal/audits/../../../..` also resolves), a committed symlink pointing outside
# the tree resolves, and an untracked or gitignored working-tree file resolves locally while CI
# sees nothing. Measured at review.
resolved=0; broken=0
while IFS= read -r p; do
  [[ -n "$p" ]] || continue
  if [[ "$p" == /* || "$p" == *..* ]]; then
    broken=$((broken + 1))
    fail "(b) breach-register cites a non-contained canonical source: $p
           A pointer must be a repo-relative path with no '..' segment -- a determination register
           whose pointers can leave the repository cannot produce what it cites."
  elif [[ -L "$REPO_ROOT/$p" ]]; then
    broken=$((broken + 1))
    fail "(b) breach-register cites a SYMLINK: $p
           The link target is not governed by this repository's history, so the record it points
           at is not the record a regulator would be shown."
  elif ! git -C "$REPO_ROOT" ls-files --error-unmatch -- "$p" >/dev/null 2>&1; then
    broken=$((broken + 1))
    fail "(b) breach-register cites a path that is not TRACKED: $p
           It may resolve in this working tree and not in a clean checkout, so the local run and
           CI would disagree about whether the documentation exists."
  elif [[ -f "$REPO_ROOT/$p" ]]; then
    resolved=$((resolved + 1))
  else
    broken=$((broken + 1))
    fail "(b) breach-register cites a canonical source that does not resolve: $p"
  fi
done <<< "$cited_paths"
[[ $((resolved + broken)) -eq $row_count ]] \
  || die2 "parsed $((resolved + broken)) canonical-source cells but the delegated guard counted $row_count rows"
[[ $broken -eq 0 ]] && pass "(b) all $resolved canonical-source pointer(s) resolve on disk"

# ANCHORED ON THE PARSED INDEX COLUMN, not on the path appearing anywhere in the file. A
# whole-file grep was satisfied by the register's own `related:` frontmatter, which lists this
# same path -- so deleting the determination ROW left this assertion green and the guard reported
# 6 assertions, 0 failed over a register missing the one row (c)'s producer cannot see. That is
# cq-assert-anchor-not-bare-token, five lines below where this file cites it. Measured at review.
if printf '%s' "$cited_paths" | grep -qxF "$OUT_OF_SCOPE_ROW"; then
  pass "(b) the out-of-producer-scope determination row is present"
else
  fail "(b) the out-of-producer-scope determination row is missing: $OUT_OF_SCOPE_ROW
           It is the one indexed determination the (c) producer cannot see, so nothing else
           would notice its removal."
fi

# ---------------------------------------------------------------------------------------
# (d) the two waiver copies agree
#
# The waiver set exists TWICE by design: machine-readable in NOT_TRANSCRIBED below (the guard
# reads it) and human-readable in the register's §Excluded records table (a supervisory authority
# reads it, and cannot be pointed at a shell script). Both copies are load-bearing, so neither
# can be deleted -- but nothing asserted they AGREE, so the register could silently drop a
# documented exclusion while the guard kept enforcing it. Measured at review: deleting one row
# from the register's table left both this guard and its suite green.
#
# That is this file's own subject one level up -- two copies of one set, no parity assertion --
# and the copy that could silently lose an entry is the one a regulator reads. The comparison is
# NOT a tautology: the two sides are independent artifacts (a shell array and a markdown table),
# so neither derives from the other.
# ---------------------------------------------------------------------------------------
declared_waivers="$(
  for _e in "${NOT_TRANSCRIBED[@]}"; do
    _p="${_e%%|*}"; printf '%s\n' "${_p%"${_p##*[![:space:]]}"}"
  done | sort -u
)"
# `|| true` is load-bearing: grep exits 1 on no match and `set -o pipefail` promotes that, so
# without it the ASSIGNMENT fails and `set -e` aborts here -- making the fail-closed branch
# below unreachable dead code. Measured at review: emptying the table exited 1 at this line
# with the explicit refusal never printed, so "could not read the table" was indistinguishable
# from an ordinary assertion failure.
# ANCHORED ON THE FILE COLUMN, not on a path appearing anywhere in the section. A section-wide
# grep also read the free-text REASON cells, so deleting a waiver ROW while any surviving reason
# cross-referenced its path left (d) green -- measured, and not contrived: a live reason cell
# already cross-references "the row above". This was the last assertion in the file still
# anchored on a bare token, after (b) and (c) were hardened off whole-file greps citing
# cq-assert-anchor-not-bare-token.
documented_waivers="$(
  { awk -F'|' '
      function trim(s) { gsub(/^[ \t`]+|[ \t`]+$/, "", s); return s }
      /^## Excluded records/ { inblk = 1; next }
      inblk && /^## /        { exit }
      inblk && /^\|/ {
        if ($0 ~ /^\|[ \t]*:?-+/) next
        c = trim($2)
        if (c == "File") next
        if (c ~ /^knowledge-base\//) print c
      }
    ' "$BREACH_REGISTER" | sort -u; } || true
)"
# A producer that reaches nothing must not report agreement: an empty table would otherwise
# compare equal to an empty array, and the fail-closed branch below never fires.
if [[ -z "$documented_waivers" ]]; then
  die2 "no §Excluded records rows parsed from the breach register -- cannot compare the waiver \
copies. If the waiver list is genuinely empty, the section must still exist and say so."
fi
if [[ "$declared_waivers" == "$documented_waivers" ]]; then
  pass "(d) the $(printf '%s\n' "$declared_waivers" | wc -l | tr -d ' ') waiver(s) agree between NOT_TRANSCRIBED and the register's §Excluded records"
else
  fail "(d) the waiver copies DISAGREE -- the register and the guard would show a regulator
           different exclusion sets:
$(diff <(printf '%s\n' "$declared_waivers") <(printf '%s\n' "$documented_waivers") \
    | sed 's/^/             /')
           Both copies are load-bearing: the guard reads NOT_TRANSCRIBED in
           scripts/lint-legal-registers.sh, and a supervisory authority reads §Excluded records
           in knowledge-base/legal/breach-register.md. Update whichever is stale; do not delete
           either."
fi

# ---------------------------------------------------------------------------------------
# (c) declared-set integrity over audits/** (post-mortems/** excluded -- see header)
# ---------------------------------------------------------------------------------------
[[ -d "$AUDITS_DIR" ]] || die2 "audits directory not found: $AUDITS_DIR"

waived_paths=""
for entry in "${NOT_TRANSCRIBED[@]}"; do
  wpath="${entry%%|*}"; wpath="$(echo "$wpath" | sed 's/[[:space:]]*$//')"
  wreason="${entry#*|}"
  [[ -n "$wpath" ]] || die2 "NOT_TRANSCRIBED entry has no path: $entry"
  [[ -f "$REPO_ROOT/$wpath" ]] || die2 "NOT_TRANSCRIBED waives a path that does not exist: $wpath"
  # Fail-closed on an uncited waiver -- the same contract EXCLUSIONS already uses.
  echo "$wreason" | grep -qE '#[0-9]+' \
    || die2 "NOT_TRANSCRIBED entry for $wpath has no citing issue (#NNNN): $wreason"
  waived_paths+="$wpath"$'\n'
done

produced=0; uncovered=0
while IFS= read -r f; do
  [[ -n "$f" ]] || continue
  produced=$((produced + 1))
  rel="${f#"$REPO_ROOT/"}"
  # ANCHORED ON THE INDEX TABLE'S CANONICAL-SOURCE COLUMN, not on the path appearing anywhere
  # in the register. A whole-file grep is satisfied by the human-readable §Excluded records
  # table and by the `related:` frontmatter, so a file listed as EXCLUDED counted as INDEXED
  # and its waiver became unfalsifiable -- deleting a waiver left the gate green. Caught by
  # mutation 7b (cq-assert-anchor-not-bare-token).
  if printf '%s' "$cited_paths" | grep -qxF "$rel"; then
    continue
  fi
  if printf '%s' "$waived_paths" | grep -qxF "$rel"; then
    continue
  fi
  uncovered=$((uncovered + 1))
  fail "(c) determination-shaped file is neither indexed nor waived: $rel
           Either add a row to knowledge-base/legal/breach-register.md, or add a
           NOT_TRANSCRIBED entry to scripts/lint-legal-registers.sh with a reason and a
           citing issue. A silent omission is the one option the gate removes."
done < <(find "$AUDITS_DIR" -type f -name '*.md' -print0 2>/dev/null \
           | xargs -0 -r grep -lE "$DETERMINATION_PATTERN" 2>/dev/null || true)

# DISJOINTNESS, computed outside the producer loop. It lived INSIDE the loop as the negation of
# a branch that had already `continue`d on the same predicate, so it was unreachable: a file both
# indexed and waived passed clean, and the suite case named for it reddened only because the
# DONOR row it moved left a different file uncovered. Measured at review -- adding an index row
# citing an already-waived file scored 6 assertions, 0 failed. Computed here, over both sets, it
# is reachable and independent of the producer's reach.
both="$(comm -12 <(printf '%s' "$cited_paths" | grep -v '^$' | sort -u) \
                 <(printf '%s' "$waived_paths" | grep -v '^$' | sort -u) || true)"
if [[ -n "$both" ]]; then
  fail "(c) the indexed and waived sets OVERLAP -- they are disjoint by construction, and a
           regulator would be shown two contradictory answers about the same file:
$(printf '%s\n' "$both" | sed 's/^/             /')
           A file is either a determination in the register or an explained exclusion, never both."
else
  pass "(c) the indexed and waived sets are disjoint"
fi

# A producer that reaches nothing must not report a clean sweep.
[[ $produced -ge 1 ]] || die2 "(c) producer matched 0 files under audits/ -- expected at least 1; \
the pattern, the directory, or the corpus changed and the gate cannot decide"
[[ $uncovered -eq 0 ]] && pass "(c) all $produced determination-shaped audits/ file(s) are indexed or waived"

# ---------------------------------------------------------------------------------------
echo
# `waiver-parity` is DERIVED. It was a literal reading `ok` unconditionally, so a run with (d)
# failing printed `1 failed (... waiver-parity=ok)` -- and every sibling field in that parenthesis
# is a real variable, which is what made the literal read as measured.
if [[ "$declared_waivers" == "$documented_waivers" ]]; then _parity=ok; else _parity=DISAGREE; fi
echo "lint-legal-registers: ${checks} assertion(s), ${fails} failed \
(registers=${scanned_registers} rows=${row_count} produced=${produced} waived=${#NOT_TRANSCRIBED[@]} waiver-parity=${_parity})"

# Assertion floor. Reported with printf + exit rather than through fail(), which is the helper
# it backstops (ADR-193): a floor that calls the function one edit disarms is not a floor.
MIN_CHECKS=7
if [[ $checks -lt $MIN_CHECKS ]]; then
  printf '::error::lint-legal-registers: only %d assertion(s) ran, expected >= %d -- the gate was disarmed, not satisfied\n' \
    "$checks" "$MIN_CHECKS" >&2
  exit 1
fi

if [[ $fails -gt 0 ]]; then
  if [[ $ADVISORY -eq 1 ]]; then
    echo "::warning::lint-legal-registers: ${fails} finding(s) -- ADVISORY this cycle, not blocking." >&2
    exit 0
  fi
  exit 1
fi
echo "=== lint-legal-registers: all assertions passed ==="
