#!/usr/bin/env bash
# The corrupt-ancestry fixture chokepoint (#10921): ONE spelling of the
# never-written-object construction and of the counted SKIP verdict, shared by
# every corrupt-walk row.
#
# ROOT CAUSE (measured on git 2.56.0, four arms). The g1b.B7 fixture corrupted
# its object graph by `rm -f` on a loose-object fanout path. `rm -f` exits 0
# when there is nothing to delete, so on any runner whose git keeps the object
# in a pack rather than at that loose path the deletion was a silent no-op —
# the graph stayed readable and the suite reported five broken-fixture FAILs on
# a REQUIRED check (guard-script-fixture-tests). Repacking before the delete
# (Arm B) reproduced the CI signature exactly. The construction below deletes
# nothing: it writes objects whose PARENT/OBJECT field names a sha that was
# computed and never persisted, so the broken graph exists by construction on
# every store layout.
#
# ONE SPELLING (#7849). The defect census found FIVE sites spelling the same
# rm-the-loose-object construction across TWO suites
# (test-bump-inngest-bootstrap-pin.sh: g1b.B7, g1b.B7c, g1b.B7a, g2b.I6;
# test-mint-inngest-bootstrap-tag.sh: fl.walk). All of them route through this
# file now; the bump suite carries a standing census self-check that fails on
# any under-object-store deletion inside .github/scripts/test/ (two same-shape
# sites outside that directory are tracked in #10956).
#
# THE FORGE IS THE LAST CONSTRUCTION STEP. Anything that walks ancestry —
# commit, repack, fsck, rev-list — hits the dead parent once it exists, and
# `git repack -ad` traverses REFLOGS, which record the forged tip, so even a
# ref-less forge breaks a later repack. Seed every commit, branch and tag that
# must exist BELOW the break FIRST, then forge. (A rev walk from the forged tip
# cannot reach pre-break commits; `git tag <name> <sha>` by literal sha still
# works afterwards because it only needs the object.)
#
# SKIP-PRODUCER REGISTRATION CONTRACT. `corrupt_skip` is the single
# emission/charge site for the ADR-188 counted-skip verdict these rows use when
# a runner's git cannot exhibit the walk contract the row validates. The probe
# is `scripts/followthroughs/t5-skip-persistence-bound-7510.sh` (its fed-log
# test file sits beside it); the carrier that files on its verdicts is
# `.github/workflows/scheduled-rehearsal-skip-monitor.yml`. A call site MUST:
#   * open its row name with a prefix the standing skip-persistence probe
#     enumerates (`SKIP (loud): g1b.` / `g2b.` in the bump suite, `SKIP (loud):
#     fl.` in the mint suite) — an unregistered name is a skip the monitor can
#     never see, and the suites' roster-parity self-checks fail on one;
#   * declare the EXACT assertion cost of the row's taken branch (the floor
#     under-counts by whatever it omits);
#   * stay under the suite's SKIPPED_ASSERTIONS ceiling;
#   * be exercised by a fed-log row in the probe's own test file.
# Construction-invariant checks (a dead oid that reads back, a tag that still
# peels, a ref the forge did not move) are a DIFFERENT rung: they are harness
# defects, fail loudly via fail(), charge NOTHING, and never route to
# corrupt_skip.
#
# ENV KNOBS.
#   SOLEUR_FIXTURE_PACKED=1     the packed-store arm (AC4): each forge helper
#                               `git repack -ad`s the fixture repo between the
#                               caller's seeding and its own forge, so the same
#                               rows run against an all-packed store. DRIVER:
#                               the `guard-script-fixture-tests` job in
#                               pr-quality-guards.yml runs the two corrupt-row
#                               suites once more under this knob every PR.
#   CORRUPT_WALK_PROBE_FORCE=skip   the forced-divergence arm (AC5): every
#                               walk-contract probe reads "contract absent" and
#                               the row takes the skip path. Only `skip` is
#                               wired; any other value is flagged via fail() —
#                               a knob that could force "contract present"
#                               would silently delete the environment gate.
#                               A forced run must only ever be a CAPTURED
#                               exercise: a forced skip's marker is
#                               byte-identical in shape to an organic one, so a
#                               sampled-carrier leg that exported the knob
#                               would file real monitor alerts indistinguishable
#                               from defects. Rows label the forced reason so
#                               a leak reads as what it is.
#
# CALLER CONTRACT. The sourcing suite must define pass()/fail() (the harness
# verdict verbs) and declare SKIPPED_ASSERTIONS=0 before any corrupt_skip call.
# Shellcheck consumers: `# shellcheck source=<relative-path>` as usual.
#
# shellcheck shell=bash

if [[ -n "${_SOLEUR_GIT_CORRUPT_GRAPH_SOURCED:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
_SOLEUR_GIT_CORRUPT_GRAPH_SOURCED=1

# _corrupt_assert_repo <repo> — every forge helper takes the fixture repo as an
# operand; an EMPTY operand makes `git -C ""` operate on the caller's cwd and
# would corrupt the caller's real repo silently (assert_fixture_dir precedent).
# When the suite's stronger assert_fixture_dir is defined it is applied too.
_corrupt_assert_repo() {
  if [[ -z "${1:-}" ]]; then
    printf 'FATAL: %s: <repo> operand is EMPTY; git -C "" would operate on %s\n' \
      "${FUNCNAME[1]:-corrupt-graph helper}" "$PWD" >&2
    return 2
  fi
  if declare -F assert_fixture_dir >/dev/null 2>&1; then assert_fixture_dir "$1"; fi
}

# dead_oid <repo> — print a sha guaranteed ABSENT from the store.
#
# `hash-object --stdin` WITHOUT -w computes the sha a blob of these bytes would
# have, without writing it: absence is a construction invariant, not a race.
# The nonce is a CONSTANT on purpose — the property is absence, not uniqueness,
# so there is no per-call nonce machinery. The constant is EXPORTED
# (CORRUPT_DEAD_NONCE): the suites' readable-dead-oid selftests write exactly
# this blob, and corrupt_invariant_dead_absent re-derives the sha from the same
# bytes — a per-call "uniqueness" change would silently vacuate the invariant
# by checking the WRONG oid. BLOB type, not `-t commit`: a commit-typed hash of
# nonce bytes is refused by format fsck on git 2.56 (`missingTree: invalid
# format`) even without -w — measured by the CTO ruling.
CORRUPT_DEAD_NONCE='soleur-corrupt-graph dead-parent'
dead_oid() {
  _corrupt_assert_repo "${1:-}" || return
  printf '%s\n' "$CORRUPT_DEAD_NONCE" | git -C "$1" hash-object --stdin
}

# _corrupt_maybe_repack <repo> — the packed-store arm. Repacking BEFORE the
# forge packs every seeded object; repacking AFTER would fail on the dead
# parent (repack traverses reflogs, which record the forged tip — measured).
# A FAILED repack must not silently degrade the packed arm to a loose-store
# run reporting green — that is the Arm-B flake's own shape one layer up —
# so it is FATAL and every caller propagates the rc onto the harness-defect
# rung.
_corrupt_maybe_repack() {
  if [[ "${SOLEUR_FIXTURE_PACKED:-0}" == "1" ]]; then
    git -C "$1" repack -adq || {
      printf 'FATAL: _corrupt_maybe_repack: packed-arm repack failed in %s — refusing to run the packed arm against a loose store\n' "$1" >&2
      return 1
    }
  fi
}

# corrupt_walk_break <repo> <ref> — forge a commit whose parent is a dead_oid
# and point <ref> at it. The forged commit carries the ref tip's own tree and
# author/committer headers — only its parent is dangling — so the ref's
# ancestry traverses a never-written object on every store layout: `git tag
# --merged`/`merge-base` report on stderr and exit 0/128 (Arm C, loose AND
# packed). Call AFTER all below-break seeding (see header).
corrupt_walk_break() {
  local repo="${1:-}" ref="${2:-}"
  _corrupt_assert_repo "$repo" || return
  if [[ -z "$ref" ]]; then
    printf 'FATAL: corrupt_walk_break: <ref> operand is EMPTY\n' >&2; return 2
  fi
  _corrupt_maybe_repack "$repo" || return
  local dead tree headers forged
  dead=$(dead_oid "$repo") || return
  tree=$(git -C "$repo" rev-parse -q --verify "${ref}^{tree}") || {
    printf 'FATAL: corrupt_walk_break: %s does not resolve to a commit tree in %s\n' "$ref" "$repo" >&2
    return 1
  }
  # Harvest headers from the commit HEADER BLOCK ONLY — `/^$/q` stops the scan
  # at the blank line before the message, so an `author `/`committer ` line in
  # the message text cannot be copied in as a duplicate header. An EMPTY
  # harvest (e.g. <ref> resolved through a tag to a non-commit) would forge a
  # headerless commit, so it is FATAL, mirroring corrupt_dead_tag's tagger
  # guard.
  headers=$(git -C "$repo" cat-file commit "$ref" | sed -n '/^$/q; /^author /p; /^committer /p')
  [[ -n "$headers" ]] || {
    printf 'FATAL: corrupt_walk_break: no author/committer header found in %s (%s) — refusing to forge a malformed commit\n' "$ref" "$repo" >&2
    return 1
  }
  forged=$({
    printf 'tree %s\n' "$tree"
    printf 'parent %s\n' "$dead"
    printf '%s\n' "$headers"
    printf '\ncorrupt_walk_break (#10921): parent is a never-written object\n'
  } | git -C "$repo" hash-object -w -t commit --stdin) || return
  git -C "$repo" update-ref "$ref" "$forged" || return
  [[ "$(git -C "$repo" rev-parse -q --verify "$ref" 2>/dev/null)" == "$forged" ]] || {
    printf 'FATAL: corrupt_walk_break: update-ref %s did not take in %s\n' "$ref" "$repo" >&2
    return 1
  }
}

# corrupt_dead_tag <repo> <tag> — forge an annotated TAG OBJECT whose `object`
# field names a dead_oid, and point refs/tags/<tag> at it (Arm D, the B7a
# shape): the tag is LISTED, its `^{commit}` peel fails deterministically, and
# a healthy `--merged` walk silently drops it.
corrupt_dead_tag() {
  local repo="${1:-}" tag="${2:-}"
  _corrupt_assert_repo "$repo" || return
  if [[ -z "$tag" ]]; then
    printf 'FATAL: corrupt_dead_tag: <tag> operand is EMPTY\n' >&2; return 2
  fi
  _corrupt_maybe_repack "$repo" || return
  local dead tagger tagobj
  dead=$(dead_oid "$repo") || return
  # Header-block-bound like corrupt_walk_break's harvest (a `committer ` line
  # inside HEAD's message must not be picked up); a commit object carries
  # exactly one committer header, so no `head -1` is needed.
  tagger=$(git -C "$repo" cat-file commit HEAD | sed -n '/^$/q; s/^committer //p')
  [[ -n "$tagger" ]] || {
    printf 'FATAL: corrupt_dead_tag: cannot read a committer header from HEAD in %s\n' "$repo" >&2
    return 1
  }
  tagobj=$({
    printf 'object %s\n' "$dead"
    printf 'type commit\n'
    printf 'tag %s\n' "$tag"
    printf 'tagger %s\n' "$tagger"
    printf '\ncorrupt_dead_tag (#10921): object is a never-written commit\n'
  } | git -C "$repo" hash-object -w -t tag --stdin) || return
  git -C "$repo" update-ref "refs/tags/$tag" "$tagobj" || return
  [[ "$(git -C "$repo" rev-parse -q --verify "refs/tags/$tag" 2>/dev/null)" == "$tagobj" ]] || {
    printf 'FATAL: corrupt_dead_tag: update-ref refs/tags/%s did not take in %s\n' "$tag" "$repo" >&2
    return 1
  }
}

# corrupt_invariant_dead_absent <row> <repo> — the construction-invariant check
# for the never-written parent. A dead oid that READS BACK is a harness defect:
# it means the construction wrote where it must not (e.g. a `-w` drifted onto
# dead_oid's hash-object), so this FAILs — never routes to corrupt_skip —
# per the ADR-188 "harness-bug rung above the skip" property. Fail-only,
# ZERO counted assertions: the charge convention keeps a skipped row at
# exactly its declared cost.
corrupt_invariant_dead_absent() {
  local row="${1:-}" repo="${2:-}" dead
  _corrupt_assert_repo "$repo" || return 2
  dead=$(dead_oid "$repo") || return 2
  if git -C "$repo" cat-file -e "$dead" 2>/dev/null; then
    fail "$row:invariant-dead-oid-absent" \
      "the forged parent $dead is READABLE in the store — the never-written-object construction is broken (a harness defect, never a skip)"
    return 1
  fi
  return 0
}

# corrupt_probe_forced_skip — the verdict of the CORRUPT_WALK_PROBE_FORCE knob
# on a row's walk-contract probe.
#   rc 0: env=skip — the caller must treat the probe as "contract absent"
#         regardless of the measured value (AC5's forced-divergence arm).
#   rc 1: unset — no force; the caller uses the measured value.
#   any other value: flagged via fail(), then rc 0 — a knob that could force
#   "contract present" would make the environment gate unreachable and skip
#   coverage-dead, so an unwired value still degrades toward the loud arm.
corrupt_probe_forced_skip() {
  case "${CORRUPT_WALK_PROBE_FORCE:-}" in
    "")   return 1 ;;
    skip) return 0 ;;
    *) fail 'corrupt-probe-force:value' \
         "CORRUPT_WALK_PROBE_FORCE='${CORRUPT_WALK_PROBE_FORCE}' is not wired — only 'skip' is a defined arm; anything else is a probe that can be forced PRESENT, which would silently delete this row's environment gate"
       return 0 ;;
  esac
}

# corrupt_skip <row-id> <cost> <reason...> — the single emission/charge site
# for a counted, named SKIP verdict (ADR-188's four properties). Streams are
# pinned: `SKIP (loud): <row> <reason>` goes to STDERR (arm_skip convention —
# it reaches the job log and the standing skip-persistence probe greps for it
# there), `::warning::<row> skipped: <reason>` goes to STDOUT because GitHub
# Actions scans workflow commands on stdout only. <reason> AND <row-id> are
# sanitized before either line — `%`→`%25`, every C0 control byte, \x7f and the
# Unicode line separators U+2028/U+2029 stripped (the corpus log-injection
# rule, knowledge-base/project/learnings/security-issues/
# 2026-04-17-log-injection-unicode-line-separators.md) — so observed evidence
# echoed into either field cannot forge a second annotation or marker line
# (the mint suite pins the same contract at its fl-encode row).
#
# <cost> is the row's declared assertion cost, VALIDATED numerically per
# arm_skip: a missing or non-numeric cost fails loudly rather than silently
# contributing nothing to the floor. The `10#` prefix pins base-10: the numeric
# guard admits `08`/`09`, which bash arithmetic would otherwise read as octal
# and error on — the marker would emit with NO charge (measured fail-open, the
# same class the probe's own streak counter documents). The charge lands on
# the caller's SKIPPED_ASSERTIONS, which the suite tail folds into TOTAL.
corrupt_skip() {
  local row="${1:-}" cost="${2:-}" reason="${*:3}"
  case "$cost" in
    ''|*[!0-9]*)
      if declare -F fail >/dev/null 2>&1; then
        fail "corrupt_skip:${row:-<unset>}" \
          "missing or non-numeric assertion cost '${cost:-<unset>}' — a skipped row must declare how many assertions its taken branch would have made"
      else
        printf 'FAIL [corrupt_skip:%s]: missing or non-numeric assertion cost\n' "${row:-<unset>}" >&2
      fi
      return 1 ;;
  esac
  # The `SKIP (loud):` literal is pinned by the probe's own test file: editing
  # it unobserves every guard-suite skip while banners keep the source
  # "observed", so an edit here is a RED there, not silent unobservation.
  # [[:cntrl:]] covers \x00-\x1f and \x7f in one class (measured on bash 5.3 —
  # an ANSI-C range inside a bracket expression does NOT expand). U+2028/9 are
  # stripped by byte sequence.
  reason=${reason//'%'/'%25'}
  reason=${reason//[[:cntrl:]]/}
  reason=${reason//$'\u2028'/}
  reason=${reason//$'\u2029'/}
  row=${row//'%'/'%25'}
  row=${row//[[:cntrl:]]/}
  row=${row//$'\u2028'/}
  row=${row//$'\u2029'/}
  SKIPPED_ASSERTIONS=$((SKIPPED_ASSERTIONS + 10#$cost))
  printf 'SKIP (loud): %s %s\n' "$row" "$reason" >&2
  printf '::warning::%s skipped: %s\n' "$row" "$reason"
}
