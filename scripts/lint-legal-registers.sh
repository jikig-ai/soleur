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
# load-bearing one. Being first over the registers is why it LANDED advisory (see --advisory
# below) rather than straight onto the one required context that cannot be un-required.
# PROMOTED TO BLOCKING 2026-09-07 (#7787, PR #7881) after one merge cycle measured clean. The
# flag survives as a supported mode; what changed is that test-all.sh no longer passes it.
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
    # advisory measured it, and the flag was DELETED from the `run_suite` call site in
    # scripts/test-all.sh on 2026-09-07 (#7787, PR #7881) with that evidence behind it: zero
    # findings across the window, two substantive legal amendments inside it. This arm is kept
    # deliberately -- it is how the mode is exercised by the unit suite, and the rc=2 carve-out
    # below is the asymmetry the promotion did NOT change. Tracked at #7787 with its checklist -- a follow-up with a
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
  # #7909: the CCLA register is now joined against the public coverage map by
  # block (f) below, so it must also be inside the generic register scans.
  "knowledge-base/legal/ccla-register.md"
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
  "knowledge-base/legal/audits/2026-05-17-sentry-ingest-window-auth-users-audit.md | Not a determination of its own: evidence INSIDE an already-indexed determination -- its frontmatter classifies it art-30-5-accountability-evidence and its incident_pir names the post-mortem the 2026-05-16 row indexes, and what it records is a population count. Indexing it would enter one incident twice. The producer match is a filing-posture reference, not a fact pattern assessed against Art. 4(12) -- true but thinner. The ground is HELD, not pending. Ruled #7717 B1/A9, attested #7791 (#7717)"
  "knowledge-base/legal/audits/2026-09-03-clo-attestation-7717-art-33-5-register.md | Not a determination: the CLO ATTESTATION of this register (#7791), attested 2026-09-04 under the ship Phase 5.5 Counsel-Review CLO-Attestation Gate. It quotes Art. 4(12) and Art. 33(5) in order to rule on the register's representation of each indexed determination, and so matches the producer pattern, but it assesses no fact pattern and records no controller determination of its own. Same disposition as the audits/2026-09-counsel-review-7717.md row; every future attestation of this register needs the same waiver -- a known cost of scoping the producer to audits/**, not a defect (#7791, #7717)"
  "knowledge-base/legal/audits/2026-09-counsel-review-7717.md | Not a determination: the COUNSEL REVIEW of this register (ship Phase 5.5 gate, 2026-09-03). It quotes Art. 4(12) and Art. 33(5) in order to rule on the inclusion predicate and so matches the producer, but it assesses no fact pattern and records no controller determination. Every future counsel review of this register needs the same waiver -- a known cost of scoping the producer to audits/**, not a defect (#7717)"
  "knowledge-base/legal/audits/2026-09-counsel-review-7625.md | Not a determination: the counsel review for the Art. 30 PA-7 §(c) / Art. 9 amendment (#7625). It cites Art. 4(12) only to record the NEGATIVE — that an Art. 30(1) record-keeping incompleteness is not a personal-data breach and triggers no Art. 33/34 duty — and assesses no fact pattern: nothing was destroyed, lost, altered or disclosed. Same shape as the #7440 waiver above (#7717)"
  "knowledge-base/legal/audits/2026-09-03-clo-review-7622-pa7-r2-evidence-layer.md | Not a determination: a retrospective record, written 2026-09-03, of the 2026-08-20 CLO review of PR #7622. It matches the producer because it transcribes that review's §(d) finding, which cites Art. 4(12) to conclude the omission was NOT a breach. The Art. 4(12) citation is quoted history, and the underlying matter was an Art. 30 Recipients-cell omission over processing that was contractually covered throughout (#7717)"
  "knowledge-base/legal/audits/2026-09-counsel-review-7791.md | Not a determination: the COUNSEL REVIEW of the CLO attestation of this register (#7791 / PR #7838), signed 2026-09-06 under the ship Phase 5.5 Counsel-Review CLO-Attestation Gate. It quotes Art. 4(12) and Art. 33(5) in order to rule on the attestation, on the re-issued 2026-09-03 review and on the deletion of the superseded implementation record, and so matches the producer pattern, but it assesses no fact pattern and records no controller determination of its own. Same disposition as the audits/2026-09-counsel-review-7717.md and audits/2026-09-03-clo-attestation-7717-art-33-5-register.md rows; every future review or attestation of this register needs the same waiver -- a known cost of scoping the producer to audits/**, not a defect (#7791, #7717)"
  "knowledge-base/legal/audits/2026-09-04-betterstack-source-split-7772.md | Not a determination, and it matches only by RULING ONE OUT: the CLO ruling on the #7772 Better Stack Logs source split states in terms that no Art. 33/34 assessment arises, because the split is a re-partitioning of one processor's storage (same recipient, same team, same cluster) and because NO DATA HAS FLOWED to the new source -- the soleur-git-data server has never been provisioned. Prospective PA-8 amendment with no fact pattern and no event; same disposition and same reasoning as the 2026-08-counsel-review-7440.md waiver two entries above. Citing #7772."
  "knowledge-base/legal/audits/2026-09-07-clo-attestation-7786-off-host-log-claims.md | Not a determination: the **CLO attestation of PR #7881** (#7786 / #6474), produced under the ship Phase 5.5 Counsel-Review CLO-Attestation Gate. It quotes Art. 4(12) and Art. 33 only to record that the Better Stack log-aggregation role addition was NOT an Art. 4(12) personal-data breach and therefore triggered no Art. 33/34 notification -- a determination that NO event occurred, about a disclosed processing change rather than about a fact pattern. Indexing it would put a non-event in a breach register. Cited #7786"
  "knowledge-base/legal/audits/2026-09-08-clo-attestation-7500-zot-last-err-redaction.md | Not a determination: the CLO ATTESTATION of the #7500 / ADR-211 redaction change, produced under the ship Phase 5.5 Counsel-Review CLO-Attestation Gate. It quotes Art. 4(12), Art. 33 and Art. 34 in order to record that the audited public egress carried NO personal data and NO credential value, so no Art. 4(12) event occurred and no row is opened -- a determination that NO breach happened, plus the Art. 30(1)(d) recipients-limb omission it closes. Indexing it would enter a non-event in a breach register. Same disposition as the audits/2026-09-07-clo-attestation-7786-off-host-log-claims.md row above. Cited #7500"
  "knowledge-base/legal/audits/2026-09-counsel-review-7947.md | Not a determination: the COUNSEL REVIEW of the PA-8 §(g) / PA-31 §(g) browser-snapshot-credential-guard amendment, produced under the ship Phase 5.5 Counsel-Review CLO-Attestation Gate. It quotes Art. 4(12) and Art. 33 only to record the NEGATIVE -- that preventive hardening of an Art. 32(1)(b) control introduces no processing, produces no fact pattern, and so engages neither Art. 33 nor Art. 34. The one historical event it cites (the 2026-05-19 Sentry token-scope probe) is corroboration for the mechanism being a realized class and was adjudicated on its own already-filed record; this review does not reopen it. Same shape and same disposition as the 2026-08-counsel-review-7440.md, 2026-09-counsel-review-7625.md and 2026-09-07-clo-attestation-7786-off-host-log-claims.md rows above. Cited #7947"
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

# ---------------------------------------------------------------------------
# (f) CCLA REGISTER <-> COVERAGE MAP INTEGRITY (#7909 / P11)
# ---------------------------------------------------------------------------
# `ccla-add.sh --instrument-file` now COMPUTES the executed-instrument hash, and
# the operator transcribes that computed value into ccla-register.md by hand.
# That makes the two stores' agreement MORE load-bearing than before, not less:
# previously one typed value landed in both, so they were wrong together;
# now one is derived and the other is typed, and they can disagree.
#
# THE RELATION IS ASYMMETRIC, and getting that wrong would red a correct tree.
# A register row is written when the INSTRUMENT is executed. The roster row for
# the same counterparty cannot be written until a designated representative has
# signed the Individual CLA -- which is a different event, often months later.
# So:
#     roster.record_ref  SUBSET-OF  register.Record ref     <- asserted
#     register           SUPERSET   roster                  <- legal, never asserted
#     hash equality on the INTERSECTION only                <- asserted
# A symmetric "these two files must match" check would fail on the ordinary
# interim state, and both operator escapes from a red required check (delete the
# register row, or fabricate a roster row) damage a legal record.
jq_ok=1
command -v jq >/dev/null 2>&1 || jq_ok=0
if [[ $jq_ok -eq 0 ]]; then
  # FAIL CLOSED. "jq is missing" must never render as "the two stores agree".
  fail "(f) jq is required to read the coverage map and is not on PATH -- the register/roster join could NOT be evaluated. This is not a finding that they agree."
else
  CCLA_REGISTER="$REPO_ROOT/knowledge-base/legal/ccla-register.md"
  CCLA_ROSTER="$REPO_ROOT/apps/cla-evidence/roster/ccla-roster.json"
  if [[ ! -f "$CCLA_REGISTER" || ! -f "$CCLA_ROSTER" ]]; then
    fail "(f) the CCLA register or the coverage map is missing -- expected $CCLA_REGISTER and $CCLA_ROSTER"
  else
    # Rows under `## Register`, minus the header, the `|---|` separator and the
    # empty-state placeholder. The placeholder is itself a pipe-line, so a naive
    # row count reads it as a counterparty.
    reg_rows="$(awk '
      /^## Register/      { inreg = 1; next }
      inreg && /^## /     { inreg = 0 }
      inreg && /^\|/ {
        if ($0 ~ /^\|[[:space:]]*-+/) next
        if ($0 ~ /Record ref/)        next
        if ($0 ~ /\(none yet\)/)      next
        print
      }' "$CCLA_REGISTER")"

    # The hash is bound to its ref HERE, in the one pass that already parses
    # every register row, instead of re-scanning `$reg_rows` per roster org with
    # a second awk. That re-scan is what needed the awk field-rebuild warning
    # (assigning to `$2` rebuilds `$0` with OFS, so a later -F'|' read takes the
    # wrong column); binding once deletes the hazard rather than documenting it.
    declare -A _reg_hash_by_ref=()
    reg_refs=""; reg_hash_bad=0; reg_ref_bad=0; n_reg=0
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      n_reg=$((n_reg + 1))
      r_ref="$(printf '%s' "$line"  | awk -F'|' '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2}')"
      r_hash="$(printf '%s' "$line" | awk -F'|' '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $5); print $5}')"
      # First wins, so a duplicated ref cannot silently change which hash the
      # join compares; the duplicate itself is reported by its own assertion.
      [[ -n "${_reg_hash_by_ref[$r_ref]:-}" ]] || _reg_hash_by_ref[$r_ref]="$r_hash"
      [[ "$r_ref"  =~ ^CCLA-[0-9]{4,}$   ]] || reg_ref_bad=$((reg_ref_bad + 1))
      [[ "$r_hash" =~ ^[0-9a-f]{64}$     ]] || reg_hash_bad=$((reg_hash_bad + 1))
      reg_refs+="$r_ref"$'\n'
    done <<< "$reg_rows"

    if [[ "$n_reg" -eq 0 ]]; then
      # Distinguish "checked and clean" from "there was nothing to check", the
      # same three-state honesty the roster-empty branch below gets.
      pass "(f) NOT YET EXERCISED: the CCLA register holds 0 counterparty rows, so its Record-ref and Instrument-hash shape checks had nothing to examine. This is not a verified agreement."
    elif [[ $reg_ref_bad -eq 0 ]]; then
      pass "(f) every CCLA register Record ref matches CCLA-NNNN ($n_reg row(s))"
    else
      fail "(f) $reg_ref_bad CCLA register row(s) carry a Record ref that is not CCLA-NNNN -- a malformed ref produces an EMPTY join below, which passes for the wrong reason"
    fi

    # NOT `... | grep -c . || echo 0`: `grep -c` PRINTS `0` and EXITS 1 on no
    # match, so the `||` appends a SECOND value and the variable ends up holding
    # two lines. Materialise the duplicate list, then branch on emptiness.
    _dupe_list="$(printf '%s\n' "$reg_refs" | sed '/^$/d' | sort | uniq -d)"
    if [[ -z "$_dupe_list" ]]; then
      n_dupe=0
    else
      n_dupe="$(printf '%s\n' "$_dupe_list" | wc -l | tr -d '[:space:]')"
    fi
    if [[ "$n_dupe" -eq 0 ]]; then
      pass "(f) CCLA register Record refs are unique"
    else
      fail "(f) $n_dupe duplicated Record ref(s) in the CCLA register -- a duplicate makes 'exactly once' unenforceable and the join ambiguous"
    fi

    if [[ $reg_hash_bad -eq 0 ]]; then
      pass "(f) every CCLA register Instrument hash is 64 lowercase hex ($n_reg row(s))"
    else
      fail "(f) $reg_hash_bad CCLA register row(s) carry an Instrument hash that is not 64 lowercase hex"
    fi

    # NO `?`. `.organizations[]?` turns "not an array" into "zero elements",
    # which renders as the reassuring NOT YET EXERCISED branch below -- the same
    # broken-vs-empty collapse `ccla-add.sh` already documents removing from its
    # own ledger query. A roster that is not shaped like a roster must refuse.
    n_orgs="$(jq -r '[.organizations[]] | length' "$CCLA_ROSTER" 2>/dev/null || echo INVALID)"
    if [[ ! "$n_orgs" =~ ^[0-9]+$ ]]; then
      fail "(f) the coverage map at $CCLA_ROSTER is not readable as JSON, or its .organizations is not an array -- the join could NOT be evaluated. This is NOT a finding that the stores agree."
    elif [[ "$n_reg" -eq 0 && "$n_orgs" -gt 0 ]]; then
      # The register table parsed to nothing while the roster holds rows. That is
      # the PARSER or the heading, never the data -- and saying "add the missing
      # row" here would send the operator to append a duplicate to a public,
      # unerasable record.
      fail "(f) the CCLA register table parsed to ZERO rows while the coverage map holds $n_orgs organisation(s). This is the '## Register' heading or the table shape, NOT missing data -- do NOT add rows. Check that the heading and its pipe-delimited header row are intact."
    elif [[ "$n_orgs" -eq 0 ]]; then
      # THREE-STATE, and this is the state that matters most today. Both sides
      # are empty, so a silent `pass` here would report agreement while
      # comparing nothing -- and the check would then run against real data for
      # the first time on the day it actually matters. Say so instead.
      pass "(f) NOT YET EXERCISED: the coverage map holds 0 organisations, so the register/roster join has no rows to compare (register rows: $n_reg). This is not a verified agreement."
    else
      # MATERIALISED AND STATUS-CHECKED, never a process substitution.
      #
      # `done < <(jq ...)` hides the producer's exit status from BOTH `set -e`
      # and `pipefail`. If that jq aborts mid-stream -- a record_ref that is an
      # object, so `@tsv` refuses the row -- the loop simply stops, `missing`
      # stays 0, and BOTH join assertions pass over rows nobody read. Measured:
      # `{"organizations":[5,{...}]}` gave n_orgs=2 joined=0 missing=0 PASS.
      # This is the identical defect the probe two directories away spends a
      # paragraph documenting; it was reproduced here by three reviewers.
      ros_tsv=""
      ros_tsv="$(jq -r '.organizations[] | [.record_ref, .executed_instrument_sha256] | @tsv' "$CCLA_ROSTER" 2>/dev/null)" \
        || { fail "(f) the coverage map could not be projected to (record_ref, hash) rows -- a row is missing those keys or carries a non-scalar. The join was NOT evaluated; this is NOT a finding that the stores agree."; ros_tsv=""; }

      missing=0; mismatched=0; joined=0; seen=0; dupes_in_roster=0; shared_hashes=0
      declare -A _roster_refs=()
      declare -A _roster_hashes=()
      while IFS= read -r ros_line; do
        [[ -n "$ros_line" ]] || continue
        seen=$((seen + 1))
        # Split on the FIRST tab explicitly. `IFS=$'\t' read -r a b` treats tab
        # as IFS WHITESPACE, so an empty first field is silently collapsed and
        # the HASH lands in `ros_ref` -- which then reports "add the missing
        # register row" for a ref that does not exist.
        ros_ref="${ros_line%%$'\t'*}"
        ros_hash="${ros_line#*$'\t'}"
        if [[ -z "$ros_ref" ]]; then
          missing=$((missing + 1))
          continue
        fi
        [[ -n "${_roster_refs[$ros_ref]:-}" ]] && dupes_in_roster=$((dupes_in_roster + 1))
        _roster_refs[$ros_ref]=1
        # SHARED-INSTRUMENT check. Distinct counterparties cannot have executed
        # the same bytes, so two record_refs carrying one hash is a SELECTION
        # error -- the operator passed the wrong file. `--instrument-file` makes
        # that the likelier remaining mistake, because it closes transcription
        # error and cannot close selection error: the wrong file is hashed
        # perfectly and nothing downstream can tell. Skip the empty hash so a
        # projection gap is reported once, by `missing`, not twice.
        if [[ -n "$ros_hash" ]]; then
          if [[ -n "${_roster_hashes[$ros_hash]:-}" ]]; then
            shared_hashes=$((shared_hashes + 1))
          else
            _roster_hashes[$ros_hash]="$ros_ref"
          fi
        fi
        reg_hash="${_reg_hash_by_ref[$ros_ref]:-}"
        if [[ -z "$reg_hash" ]]; then
          missing=$((missing + 1))
          continue
        fi
        joined=$((joined + 1))
        [[ "$reg_hash" == "$ros_hash" ]] || mismatched=$((mismatched + 1))
      done <<< "$ros_tsv"

      # TOTALITY, and it is a SECOND control rather than an independent one --
      # stated because the difference is measurable and a future reader should
      # not have to re-derive it. When the projection above succeeds jq emits
      # exactly one line per organisation, so `seen == n_orgs` cannot fail; this
      # exists as the backstop for the projection's own `|| fail` being removed.
      # Mutation-measured: deleting THIS check alone leaves the suite green (the
      # explicit failure catches it), deleting the explicit failure alone leaves
      # it green (this catches it), and deleting BOTH reddens the fail-open arm.
      # So the pair is load-bearing and neither half is individually pinned --
      # which is the correct reading of defence in depth, not two guards.
      if [[ "$seen" -eq "$n_orgs" ]]; then
        pass "(f) the join read all $n_orgs coverage-map row(s)"
      else
        fail "(f) the join read only $seen of $n_orgs coverage-map rows -- the map could not be read through. This is NOT a finding that the stores agree."
      fi

      if [[ "$dupes_in_roster" -eq 0 ]]; then
        pass "(f) coverage-map record_refs are unique across organisations"
      else
        fail "(f) $dupes_in_roster duplicated record_ref(s) in the coverage map -- two published rows claiming one executed instrument. The register side is already checked for this; the roster was not."
      fi

      if [[ "$shared_hashes" -eq 0 ]]; then
        pass "(f) no two coverage-map rows share an executed-instrument hash"
      else
        fail "(f) $shared_hashes coverage-map row(s) share an executed-instrument hash with another row. Two counterparties cannot have executed the same bytes, so this is a SELECTION error -- the wrong file was passed to --instrument-file and hashed correctly. Re-hash each instrument on the encrypted operator drive and check which row names the wrong one; do not assume it is the newer."
      fi

      if [[ $missing -eq 0 ]]; then
        pass "(f) every coverage-map record_ref appears exactly once in the CCLA register (joined $joined of $n_orgs)"
      else
        fail "(f) $missing coverage-map record_ref(s) have no matching CCLA register row. The register row is written when the INSTRUMENT is executed and should already exist, so the usual cause is a missing register row -- but check the Record ref spelling on BOTH sides before adding anything, because appending a duplicate to a public unerasable record is worse than the gap."
      fi

      if [[ $mismatched -eq 0 ]]; then
        pass "(f) Instrument hash agrees between register and coverage map on all $joined joined row(s)"
      else
        # The natural repair is the wrong one and must not be suggested: copying
        # one cell into the other makes the two stores stop corroborating each
        # other, and nothing would record that the independence was lost.
        fail "(f) $mismatched joined row(s) disagree on Instrument hash. RE-HASH THE EXECUTED INSTRUMENT on the encrypted operator drive (sha256sum < <instrument>) and correct whichever store is wrong against THAT. Do NOT copy one cell into the other -- the two values exist to corroborate each other independently."
      fi
    fi
  fi
fi

# `waiver-parity` is DERIVED. It was a literal reading `ok` unconditionally, so a run with (d)
# failing printed `1 failed (... waiver-parity=ok)` -- and every sibling field in that parenthesis
# is a real variable, which is what made the literal read as measured.
if [[ "$declared_waivers" == "$documented_waivers" ]]; then _parity=ok; else _parity=DISAGREE; fi
echo "lint-legal-registers: ${checks} assertion(s), ${fails} failed \
(registers=${scanned_registers} rows=${row_count} produced=${produced} waived=${#NOT_TRANSCRIBED[@]} waiver-parity=${_parity})"

# Assertion floor. Reported with printf + exit rather than through fail(), which is the helper
# it backstops (ADR-193): a floor that calls the function one edit disarms is not a floor.
# 7 -> 11 (#7909): block (f)'s register/roster join assertions. ELEVEN, not the
# fifteen the block can emit: the join's own arms are inside the `n_orgs > 0`
# branch and do not run while the coverage map is empty, which it is today. A
# floor set to the maximum would red the live tree on every PR; a floor set to
# the LIVE count is what this is. Raise it in the same commit as the first
# coverage-map row, to the count measured on that tree.
MIN_CHECKS=11
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
