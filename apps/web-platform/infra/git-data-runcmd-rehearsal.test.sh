#!/usr/bin/env bash
#
# (#6982, W12 rung 1) RUNTIME rehearsal of the git-data runcmd chain, in the pinned
# Ubuntu 24.04 image, against a real capture endpoint.
#
# WHY A RUNTIME TEST WHEN THE STATIC GUARDS ALREADY PASS. Every other gate in #6982 is
# static, and the failure class it defends against — "green apply, dark host" — is only
# observable when the code RUNS. The Phase-0 W0 probe is the proof: a config-scope mismatch
# that passed `terraform validate`, every drift-guard and every mutation arm, and would
# have died silently on first boot. Mutation arms prove the code CAN go red when neutered;
# they never prove the right thing happens when it is intact.
#
# WHAT THIS RUNG CANNOT ANSWER, stated so a green run is not over-read: it does not
# exercise `doppler run` against real Doppler, `luksOpen` against a real volume, the
# private NIC, or whether an event reaches Sentry/Better Stack. Those need the throwaway-
# host rung, which is the banner-clear issue's precondition (#7025) — NOT this file's.
#
# Run: bash apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh
# Registered as a step in .github/workflows/infra-validation.yml.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
passes=0; fails=0
pass() { passes=$((passes + 1)); }
# THE VERDICT DOES NOT RIDE ON A COUNTER (#7565 review). `fails` feeds the terminal line and
# `total`, but BOTH are sums, so a one-token bucket swap — `fail() { passes=$((passes + 1)); … }`
# — disarms every assertion in this file at once: the floor still sees `total == 47`, the run
# still prints accurate `FAIL:` text, and it exits 0. Measured: three real regressions injected,
# `47 passed, 0 failed`, EXIT=0. The floor cannot see it because the floor sums the two buckets.
# FAILURES is append-only and is what the verdict reads, so silencing the suite now requires
# removing the append too — and removing the whole body drops `passes`, which the floor DOES see.
FAILURES=()
fail() { fails=$((fails + 1)); FAILURES+=("$1"); echo "FAIL: $1" >&2; [ -n "${2:-}" ] && echo "      $2" >&2; }

# SKIPPED_ASSERTIONS is denominated in ASSERTION COST, not in arms: a declaring arm increments by
# the number of assertions it would have made, so `passes + fails + SKIPPED_ASSERTIONS` is invariant
# across environments and the floor below can stay absolute. Precedent — counter, denomination,
# sum-floor and degraded-run NOTE — is infra-config-apply.test.sh. See ADR-188.
#
# NAMED FOR THE DENOMINATION, deliberately NOT `SKIPPED` (#7291 review). The sibling
# git-lock-chardevice-sweep.test.sh spells its summary `Skipped: N` and this file matches that,
# but its `SKIPPED` counts ARMS — one increment for an arm carrying three assertions — and that
# suite has no assertion floor, so its counter is decorative. Reusing the identifier would import
# no compatibility and would put two DIFFERENT denominations behind one name in one directory,
# which is exactly the collision a shared name is supposed to prevent.
# The execution marker, defined ONCE. Five readers below plus the drive.sh heredoc carry it
# (`grep -c '_T5_MARKER'` = 6 including this definition — the count said "four sites" until a
# review re-derived it); with the literal repeated at every site a partial rename passes the
# structural guard while the verdict grep never matches, so the arm skips on EVERY run behind a
# green check — the exact failure the structural guard exists to prevent. The heredoc is quoted
# (no expansion), so the guard comparing THIS variable against the MOUNTED artifact is what pins
# the two together: rename either side alone and the guard hard-exits.
_T5_MARKER='DRIVER_REACHED_DL'

# THE FIXTURE MARKER GETS THE SAME TREATMENT, and it did not until review. It was a bare literal
# emitted at one site and grepped at another with nothing pinning them, which is the hazard the
# paragraph above describes — but on the HIGHER-consequence rung: `FIXTURE:` is the only thing
# standing between a deterministic capture-server failure and a declared environment skip, so a
# rename on the producer side alone turns two hard FAILs into a GREEN run with a NOTE.
#
# THAT RENAME IS NOT HYPOTHETICAL — IT IS THE NEXT OBVIOUS CLEANUP. Every other fixture marker in
# this file already reads `FIXTURE-FAIL:` (the mktemp guard, `fixture_fail`, the R4/R3 arm), and
# the comment at the R4 driver states the migration explicitly. This emit is the last holdout of
# the old spelling, and `FIXTURE-FAIL:` does not contain `FIXTURE:` — so "make the markers
# consistent" would silently disarm this rung. The structural guard below is what stops that.
_T5_FIXTURE_MARKER='FIXTURE: capture server never bound :8099'

# The rc classes the SKIP verdict is justified for, enumerated ONCE so the routing predicate and
# the operator-facing classification cannot disagree. ADR-188 justifies the decline for a
# precondition nobody owns; these are the two classes measured to produce it:
#   100  apt under the container's outer `set -e` (the archive's state at that instant)
#   125  docker CLI / image pull
# Deliberately NOT a catch-all: see the routing comment at the verdict for why "any non-zero"
# hands the skip bucket every harness defect in this file. Word-split on purpose (read with
# `printf '%s\n' $_T5M_ENV_RCS`), so it stays a plain string under this file's `set -u`.
_T5M_ENV_RCS='100 125'

SKIPPED_ASSERTIONS=0
# The cost is declared at the CALL SITE, never defaulted: a default is a silent 1 for an arm whose
# taken branch made six assertions, and the floor would then under-count by five.
#
# VALIDATED, not left to `set -u`. A bare `$2` aborts at THIS line — naming the definition rather
# than the caller, discarding the floor, the summary and the final `[ "$fails" -eq 0 ]`, and
# (inside a subshell) letting the parent continue with the counter unincremented. An empty or
# non-numeric cost is worse: `$(( ))` reports an arithmetic syntax error, leaves the counter
# unchanged and returns 0, so the arm silently contributes nothing. Arithmetic context also
# evaluates recursively, so a non-literal cost is an injection surface. A counted fail keeps the
# run legible and still cannot be ignored.
arm_skip() {
  case "${2:-}" in
    ''|*[!0-9]*)
      fail "arm_skip: missing or non-numeric assertion cost from ${BASH_SOURCE[0]}:${BASH_LINENO[0]}" \
           "cost=[${2:-<unset>}] — an arm must declare how many assertions its taken branch would have made"
      return ;;
  esac
  SKIPPED_ASSERTIONS=$((SKIPPED_ASSERTIONS + $2)); echo "SKIP (loud): $1" >&2
}

# B5: A SKIP IS NOT A PASS, AND UNDER CI IT IS NOT EVEN A SKIP — FOR A DECLINE WHOSE INPUT IS
# COMPUTABLE. Every guard below exits 0 when a tool is missing, which is right on a laptop and
# wrong in CI: the runner is the one place this suite is REQUIRED to execute, and a missing
# dependency there silently converts a runtime gate into a green no-op that nothing
# distinguishes from a real pass. Under CI=true the absence is a FAILURE of the runner's
# provisioning, reported as such.
#
# AMENDED (#7291, ADR-188). The paragraph above asserted a TWO-VALUED world, and `arm_skip()`
# makes that false, so it is restated rather than left to contradict the code. The line is not
# skip-vs-no-skip; it is WHAT THE DECLINE IS A PROPERTY OF:
#
#   _skip()    whole-suite, a precondition the RUNNER IS CONTRACTED TO SUPPLY (docker,
#              terraform, python3). Its absence is a provisioning defect against that contract,
#              so failing is actionable: it stays a hard exit 1 under CI, exactly as above.
#   arm_skip() per-arm, a precondition NOBODY OWNS — the apt archive's state at that instant.
#              No flag can make it unreachable under CI; forcing it would only restore the
#              false FAIL of #7291.
#
# THE AXIS IS CONTRACTUAL OWNERSHIP, NOT COMPUTABILITY. An earlier draft of this block (and of
# ADR-188) drew the line at whether the input is computable at dispatch. The precedent this file
# borrows its counter from refutes that: infra-config-apply.test.sh declines on two FULLY
# COMPUTABLE inputs and treats them oppositely — a shallow clone hard-FAILs under CI (its message
# names the fetch-depth: 0 contract) while not-root SKIPs ungated, because CI is contracted to
# fetch full history and is not contracted to run as root.
#
# An arm may reach arm_skip() only under all FOUR mechanical conditions, each demonstrated by a
# failing direction in the mutation matrix, LISTED IN THE ORDER THE CODE TESTS THEM (they were
# listed harness-before-fixture until review — the pre-restructure order, and the inverse of both
# the verdict below and the paragraph justifying it; the conditions are conjunctive so nothing
# behaved differently, but this is the first place a reader meets them):
# (1) the SUCCESS marker CHMOD_RAN is absent, so a slow but succeeding run can never be skipped;
# (2) it is past the fixture test, so a deterministic bind failure cannot be absorbed into the
# environment bucket; (3) it is past the harness-defect rung — the container's rc is one of the
# measured environment classes, so a missing measurement is a harness bug and not a skip; and
# (4) the DRIVER'S OWN execution marker is absent.
#
# (4) is an absence test, and calling it "positive corroboration" would be false — the code reads
# `! grep`. What makes it sound is WHICH absence: not the absence of the success marker
# (`CHMOD_RAN`), which is exactly what #7291 misread, but the absence of a DISTINCT, EARLIER
# marker that localises the failure upstream of the download block. Strictly more discriminating
# than the original, still an absence. Genuine positive corroboration would require the failure
# path to EMIT something, which is the deferred /out/setup.log capture.
#
# The count is then capped by a counted ceiling at the floor below.
#
# WHAT THIS DOES NOT CLOSE — REWRITTEN AT THE #7565 REBASE, and the rewrite is the point. As
# authored, this paragraph named a silent false-PASS still open in this arm: a stable environment
# where egress to the tarball host fails while apt SUCCEEDS. Its three premises were that the
# driver still reaches the download block so the marker prints and no skip fires; that the
# instrumentation was `;`-chained, so with `set -e` stripped the marker printed whether or not
# curl succeeded; and that the primary arm asserted only that SOMETHING in the doppler_dl stage
# aborted, never that the CHECKSUM did.
#
# TWO OF THE THREE ARE NOW FALSE. #7565 landed underneath this branch and changed the transform
# to `&&`, so CHMOD_RAN means chmod ran AND succeeded; and it added sha256sum's own
# `<tarball>: FAILED` verdict as a counted assertion in BOTH arms, so a chain stopped by a failed
# download is now distinguished from one stopped by the checksum. Leaving the original text
# standing would have made this file assert a defect it no longer has — the same inherited-claim
# failure this branch exists to fix, committed in its own explanatory prose.
#
# THE RESIDUAL, restated narrowly and honestly: every verdict here is still an ABSENCE test over
# a captured stream, so a failure that produces no output at all is classified by rc alone. That
# is what the deferred /out/setup.log capture addresses. Do not read the four conditions above as
# soundness.
_skip() {
  if [ "${CI:-}" = "true" ]; then
    echo "$1 — and CI=true, so this is a FAILURE: the runner must provide this dependency. A gate that cannot run must not report success." >&2
    exit 1
  fi
  echo "$1" >&2
  exit 0
}

command -v docker >/dev/null 2>&1 || _skip "git-data-runcmd-rehearsal: SKIP — docker absent"
docker info >/dev/null 2>&1 || _skip "git-data-runcmd-rehearsal: SKIP — docker daemon unreachable"
command -v terraform >/dev/null 2>&1 || _skip "git-data-runcmd-rehearsal: SKIP — terraform absent"
command -v python3 >/dev/null 2>&1 || _skip "git-data-runcmd-rehearsal: SKIP — python3 absent"
command -v dash >/dev/null 2>&1 || _skip "git-data-runcmd-rehearsal: SKIP — dash absent (/bin/sh on 24.04; D1 asserts the shipped emitter against it)"

# DEFAULT TMPDIR HERE, not only in the runners. scripts/test-all.sh and run-registered-suites.sh
# both export TMPDIR=/var/tmp, but a DIRECT invocation — the shape this file's own header
# documents, and the one infra-validation.yml uses — inherits the bare /tmp. Without this the
# forensics trees land in /tmp while the age-reaper below sweeps /var/tmp, so the reaper is a
# no-op in exactly the retention case the forensics path creates.
export TMPDIR="${TMPDIR:-/var/tmp}"

TMP="$(mktemp -d -t gdreh.XXXXXXXX)" || { echo "FIXTURE-FAIL: mktemp -d failed" >&2; exit 2; }

# FORENSICS ON ANY NON-ZERO EXIT — and this MODIFIES THE EXISTING HANDLER IN PLACE rather
# than adding a second `trap ... EXIT`. Bash keeps only the LAST handler registered for a
# signal, so a second `trap` here would silently discard the cleanup above it (or be
# discarded by it), which is the shape AC15 pins.
#
# KEYED ON THE EXIT STATUS, NOT ON THE COUNTERS. This suite has hard `exit 1` setup paths
# that fire while `fails == 0`, and those are exactly where forensics matter most: the tree
# is the only evidence of a fixture that never got far enough to assert anything.
# Reproducing #7501 required hand-patching the trap precisely because it removed the tree
# unconditionally.
#
# ON CI THIS IS A LOCAL-ONLY AID: infra-validation.yml has no upload-artifact step, so the
# retained tree does not survive the runner. The CI signal remains the run log.
_reh_cleanup() {
  _rc=$?
  if [ "$_rc" -ne 0 ] || [ -n "${GIT_DATA_REHEARSAL_KEEP_TMP:-}" ]; then
    echo "FORENSICS: retained the rehearsal tree at ${TMP} (exit ${_rc})" >&2
    echo "FORENSICS: container stdout is at ${TMP}/r4out/stdout" >&2
  else
    rm -rf "$TMP"
  fi
  # AGE-REAPER, mirroring the sibling runner's, which records the measured cost of omitting
  # one (414 dirs / 23 MB). GLOB-BOUNDED to this suite's own `gdreh.` prefix and gated on
  # mtime, so it can never reap a CONCURRENT run's tree — parallel worktrees are this repo's
  # documented workflow, and a reaper that takes a live sibling's fixtures out from under it
  # produces exactly the nondeterministic starvation #7501 is about.
  find "${TMPDIR:-/var/tmp}" -maxdepth 1 -type d -name 'gdreh.*' -mmin +720 \
    -exec rm -rf {} + 2>/dev/null || true
}
trap _reh_cleanup EXIT

# ── AC15: exactly ONE executable top-level `trap … EXIT` in this file ──────────────
#
# Bash keeps only the LAST handler registered for a signal, so a second top-level
# `trap … EXIT` silently discards the forensics/cleanup handler above (or is discarded by
# it) — and the retained-tree-on-failure path would then vanish without a single test going
# red. This was specified and, until now, only ever checked by hand.
#
# THE COUNT IS HEREDOC-AWARE, which is the whole difficulty. This file embeds driver scripts
# that legitimately arm their own traps inside quoted heredocs, and the B2SPEC table lists
# `trap on_err EXIT` as DATA. Measured: a naive `grep -cE '^trap .*EXIT'` returns 4 here, so
# an assertion built on it would either fail on a correct file or pass only by accident of
# which copies happen to be indented.
_ac15_traps="$(python3 - "${BASH_SOURCE[0]}" <<'PY'
import re, sys
out, delim = [], None
for l in open(sys.argv[1]).read().splitlines():
    if delim is None:
        out.append(l)
        m = re.search(r"<<-?'?([A-Za-z_][A-Za-z0-9_]*)'?", l)
        if m:
            delim = m.group(1)
    elif l.strip() == delim:
        delim = None
print(sum(1 for l in out if re.match(r'^[ \t]*trap [^\n]*EXIT', l)))
PY
)"
if [ "${_ac15_traps:-0}" -eq 1 ]; then
  pass
else
  fail "AC15: expected exactly 1 executable top-level 'trap … EXIT', found ${_ac15_traps:-?}" \
       "Bash keeps only the last EXIT handler, so a second one silently replaces the forensics handler. Heredoc bodies and table text are excluded from this count by construction."
fi

# Render the REAL template, then extract the emitter and the Doppler-download runcmd block
# from it. Extracting from the render (not from a hand-written fixture) is what makes this
# track the artifact that actually ships.
# TWO ARTIFACTS (#7264). `rendered.yml` is the STRIPPED render — the bytes the host is
# actually handed, and the right corpus for every boot-fidelity predicate below.
# `rendered-raw.yml` is the unstripped one. It is read ONLY by the sanity check just below,
# which asserts the strip actually took effect end-to-end. No predicate arm runs against it —
# an earlier version of this comment claimed it preserved "discriminating power" for the arms,
# and that was never true: the arms all read the stripped render.
bash "$DIR/git-data-userdata-budget.sh" "$TMP/rendered.yml" "$TMP/rendered-raw.yml" >/dev/null 2>&1 \
  || { echo "FAIL: render failed" >&2; exit 1; }

# The strip is load-bearing end-to-end, not just in the budget script's own accounting: the
# raw render MUST still carry rationale comments and the stripped one MUST NOT. If these ever
# converge, either the strip stopped matching (cap regression) or the template lost its
# rationale (a different problem) — both are worth failing on here rather than at apply time.
_raw_comments=$(grep -cE '^[[:space:]]*#[[:space:]]' "$TMP/rendered-raw.yml" || true)
_stripped_comments=$(grep -cE '^[[:space:]]*#[[:space:]]' "$TMP/rendered.yml" || true)
if [ "$_raw_comments" -lt 100 ] || [ "$_stripped_comments" -ne 0 ]; then
  echo "FAIL: render strip did not take effect (raw rationale lines=${_raw_comments} expected >=100; stripped=${_stripped_comments} expected 0)" >&2
  exit 1
fi
# No `head … | grep -q` here: under `set -uo pipefail` grep -q closes the pipe on match and
# the producer takes SIGPIPE (141), which pipefail promotes — so the guard fails OPEN exactly
# when it matches (#7005). Compare the captured string instead.
_first_line=$(head -1 "$TMP/rendered.yml")
if [ "$_first_line" != "#cloud-config" ]; then
  echo "FAIL: stripped render begins with '${_first_line}', not '#cloud-config' — cloud-init would ignore the payload and the host would boot dark" >&2
  exit 1
fi


# THE `.code.sh` STRIP, SINGLE-SOURCED (#7613, 5.0). Both extraction sites and the R3(3b)(ii)
# control read it, so the corpus the arms see and the corpus the control tests are the same
# bytes by construction rather than by two spellings agreeing.
#
# RED VALUE: EMPTY -- i.e. whole-line comments are dropped (as today) and TRAILING ones are
# not touched at all. That is the mechanism #7613 names, and leaving it at the current value
# here is what makes the control's failure the defect rather than a bug in the fixture.
#
# The GREEN value is `[ \t]+#([ \t].*)?$`, which BLANKS THE TAIL IN PLACE rather than deleting
# the line -- line numbers must be preserved because R3(1)/(2)/(2b)/(2d) are ordering
# predicates over them. The `+` prefix (not `*`) is load-bearing: `_b2_strip`'s zero-width
# form destroys `${var#pat}` -> `${var`, `$#` -> `$`, and `#!/bin/sh` -> empty, all measured.
_R3_TAIL_STRIP='[ \t]+#([ \t].*)?$'

R3_TAIL_STRIP="$_R3_TAIL_STRIP" python3 - "$TMP/rendered.yml" "$TMP" <<'PY'
import sys, yaml, re
import os
d = yaml.safe_load(open(sys.argv[1])); out = sys.argv[2]
for wf in d["write_files"]:
    if wf["path"] == "/usr/local/bin/git-data-emit":
        open(f"{out}/git-data-emit", "w").write(wf["content"])
    # (#7025, S1) The hardening drop-in, so the sshd stage is validated against the REAL
    # directives rather than against a stock sshd_config that would exercise nothing.
    if wf["path"] == "/etc/ssh/sshd_config.d/01-hardening.conf":
        open(f"{out}/01-hardening.conf", "w").write(wf["content"])
# The runcmd entry carrying the checksum block — the supply-chain fix (issue item 3).
blocks = [c for c in d["runcmd"] if isinstance(c, str) and "sha256sum -c -" in c]
assert len(blocks) == 1, f"expected exactly 1 checksum runcmd block, found {len(blocks)}"
open(f"{out}/doppler-dl.sh", "w").write(blocks[0])
# The trap-arming preamble (STAGE/on_err/trap + the delivery assertion).
pre = [c for c in d["runcmd"] if isinstance(c, str) and "trap on_err EXIT" in c]
assert len(pre) == 1, f"expected exactly 1 trap-arming block, found {len(pre)}"
open(f"{out}/preamble.sh", "w").write(pre[0])
# (#7025, S1) The sshd_config stage. Extracted from the render for the same reason every
# other block here is: a hand-written copy would keep passing after the shipped one drifted.
# DELIBERATELY LAST of the per-block extractions. Placed above, its assert would abort python
# before doppler-dl.sh was written, and the failure would surface as the `[ -s doppler-dl.sh ]`
# guard's "could not extract the checksum block" — naming an artifact that was fine. That is
# the same misattribution the cloud-init half of this PR is fixing.
sshd = [c for c in d["runcmd"] if isinstance(c, str) and "STAGE=sshd_config" in c]
assert len(sshd) == 1, f"expected exactly 1 sshd_config runcmd block, found {len(sshd)}"
open(f"{out}/sshd-stage.sh", "w").write(sshd[0])
# (#7204) The LUKS stage, for R1/R3/R4. Extracted from the RENDER rather than raw template
# bytes so it tracks what actually ships. `assert len(...) == 1` mirrors the other
# extractions — a stage that split into two runcmd entries must fail loudly rather than
# silently extract the first half.
#
# TWO FILES, AND THE SPLIT IS NOW DEGENERATE — kept for shape, not for discrimination.
#
# HISTORY, because both revisions of this comment were wrong in opposite directions. The
# first claimed "ADR-152 strips whole-line comments at render, so the collision disappears
# here for free"; #7204 corrected that to "FALSE — main.tf states cloud-init-git-data.yml
# itself is NOT stripped", and measured 81 of the luks stage's 117 lines as COMMENTS. Both
# were true when written. NEITHER is true now: #7264 extended the strip to the template, so
# the render this suite slices arrives comment-free and the sentence #7204 quoted no longer
# exists in main.tf.
#
# Measured after that change: the luks stage goes 55 -> 55 lines and the runcmd concatenation
# 170 -> 170. Zero lines removed, so `luks-stage.sh` is byte-identical to `luks-stage.code.sh`
# and `runcmd-all.sh` to `runcmd-all.code.sh`.
#
#   luks-stage.sh       the stage as rendered — now already comment-free
#   luks-stage.code.sh  the same bytes, kept so every predicate below has one stable name
#
# The split is retained rather than collapsed because the predicates are code-anchored and a
# rename would touch every one of them for no behavioural gain; the vacuity it used to guard
# against is now covered by the non-vacuity asserts below and by the strip's own guards in
# git-data-template-strip.test.sh. `_luks_slice()` in git-data-luks.test.sh still slices the
# RAW template on disk, so it is unaffected by any of this.
luks = [c for c in d["runcmd"] if isinstance(c, str) and "STAGE=luks_open" in c]
assert len(luks) == 1, f"expected exactly 1 luks_open runcmd block, found {len(luks)}"
open(f"{out}/luks-stage.sh", "w").write(luks[0])
_tail = os.environ.get("R3_TAIL_STRIP", "")
_tre = re.compile(_tail) if _tail else None
def _strip_code(_t):
    _out = []
    for _l in _t.splitlines():
        if re.match(r'^\s*#', _l):
            continue                      # whole-line comment: dropped, as before
        if _tre is not None:
            _l = _tre.sub("", _l)         # trailing comment: BLANKED IN PLACE, line kept
        _out.append(_l)
    return "\n".join(_out)
_code = _strip_code(luks[0])
assert "mkfs.ext4" in _code, "comment-stripped luks stage lost its mkfs — strip is too aggressive"
open(f"{out}/luks-stage.code.sh", "w").write(_code + "\n")
# The WHOLE runcmd, concatenated the way cloud-init actually runs it. B2 compares against
# THIS, not against the trap-arming entry alone: `trap on_err EXIT` and the `set -e` that
# arms abort-on-error live in DIFFERENT runcmd entries, and it is precisely because
# cloud-init joins every entry into ONE script that the trap covers the later ones. A
# comparison scoped to a single entry reports drift that does not exist.
_all = "\n".join(c for c in d["runcmd"] if isinstance(c, str))
open(f"{out}/runcmd-all.sh", "w").write(_all)
# COMMENT-STRIPPED concatenation, for R3(3b). Same rationale as luks-stage.code.sh one level
# up: this file's prose discusses `git-data-emit … fatal`, `[ -s "$_detail"` and the literal
# log path at length, so any regex predicate reading the raw text can be satisfied by the
# commentary that explains the property instead of the property.
_all_code = _strip_code(_all)
# NON-VACUITY, mirroring luks-stage.code.sh's `mkfs.ext4` assert one level up (#7264).
# luks-stage.code.sh has carried this since it was written; THIS file did not, and its four
# consumers (R3(3b), R3(3c), R3(3d), R3(2d)) are all NEGATIVE-space or ordering predicates —
# the shapes that pass on an EMPTY slice. So a strip that ate the whole concatenation, or an
# upstream change that emptied `runcmd`, would have reported four green arms about a file
# with nothing in it. Assert both a content anchor and a size floor: the anchor catches an
# over-aggressive strip, the floor catches a slice that silently collapsed.
assert "git-data-emit" in _all_code, (
    "comment-stripped runcmd concatenation lost the emitter invocation — strip is too aggressive")
assert len(_all_code.splitlines()) >= 40, (
    f"comment-stripped runcmd concatenation collapsed to {len(_all_code.splitlines())} lines "
    "(floor 40) — the four R3 predicates reading it would pass vacuously")
open(f"{out}/runcmd-all.code.sh", "w").write(_all_code + "\n")
PY
[ -s "$TMP/doppler-dl.sh" ] || { echo "FAIL: could not extract the checksum block" >&2; exit 1; }

# ── B1 — BYTE-IDENTITY of every indent(6, …)-delivered payload ─────────────────────
#
# git-data-luks.test.sh A27 carries the name "BYTE-IDENTITY" but greps for the
# `indent(6, <var>)` call sites and asserts zero `encoding: b64`. That proves the
# DELIVERY MECHANISM is the plain-text one; it never renders and never compares a byte.
# A trailing-whitespace strip, a YAML block-scalar chomp, or an indent() that swallowed a
# blank line inside a heredoc would all pass it — and each ships a script that differs
# from the one in the repo, which is the whole property the name claims.
#
# This is the actual comparison, and it belongs here because this is where the render is
# already parsed.
#
# IT ASSERTS A SET, IN BOTH DIRECTIONS, NOT A COUNT. The first version of this check mapped
# each delivered path to `<srcdir>/<basename>`, `continue`d when no such file existed, and
# floored on `checked >= 9`. Three ways that is narrower than the property it names:
#
#   1. UNCHECKED PAYLOADS. The bare `continue` cannot tell "legitimately inline" from
#      "should have been file-backed, but the basename stopped resolving". A payload that
#      falls out of the mapping is silently not compared, and silence reads as a pass.
#   2. A COUNT IS NOT A SET. Dropping one file-backed payload while any other resolves keeps
#      the total at 9. Measured fail-open.
#   3. DUPLICATE BASENAMES could satisfy the count twice while a real member went missing.
#
# So the expected set is derived from the AUTHORITATIVE producer — the `indent(6, <var>)`
# call sites in the template, resolved through the render module's `<var> = file(".../<name>")`
# bindings — and compared as a set against what was actually delivered. Every inline payload
# is named in an explicit allowlist; an unrecognised path is a FAILURE, not a skip.
_b1_out="$(python3 - "$TMP/rendered.yml" "$DIR" <<'PY'
import sys, yaml, os, re, hashlib
rendered, srcdir = sys.argv[1], sys.argv[2]

# Payloads written inline in the template rather than from a repo file. Explicit, because
# "no source file found" must not be self-certifying. These are NOT exempt from the
# duplicate check below — an attacker-supplied second entry at an allowlisted path (a
# permissive authorized_keys, a relaxed sshd_config) is precisely the escape an exemption
# would open, and cloud-init applies write_files in order so the LAST one wins.
INLINE_ALLOWLIST = {
    "/usr/local/bin/git-data-emit",
    "/home/git/.ssh/authorized_keys",
    "/etc/ssh/sshd_config.d/01-hardening.conf",
}
# An absolute floor, NOT a self-derived one. The first rewrite of this check derived the
# expected roster from cloud-init-git-data.yml — the same artifact that produces the
# delivered set — so deleting a payload shrank BOTH sides and the equality held. Measured:
# deleting the git-data-gc.timer block reported "OK: 8 payloads". That was a net REGRESSION
# against the `checked >= 9` floor it replaced, in the arm whose comment claimed to have
# fixed a measured fail-open. The roster authority is modules/git-data-userdata/main.tf (it
# moved there in #7025/R7 so both roots render from one map); the floor is absolute.
MIN_PAYLOADS = 9

# THE DESTINATION CONTRACT, OWNED BY THIS TEST. Deriving the expected path from the template
# too would re-create the tautology one level down: relocating a payload moves BOTH sides and
# the equality holds. Measured — moving git-data-gc.timer to /tmp/junk/ (same basename, same
# bytes) passed a derivation-based check while systemd would never see the unit again.
#
# These paths are load-bearing, not incidental: /etc/systemd/system is where systemd looks,
# /usr/local/bin is what the authorized_keys forced commands name, and /tmp is where the
# placeholder is staged for the bootstrap to install. A deliberate move must edit this map,
# which is the review point.
EXPECTED_PATHS = {
    "git_data_bootstrap":               "/usr/local/bin/git-data-bootstrap.sh",
    "git_data_provision":               "/usr/local/bin/git-data-provision.sh",
    "git_data_transport_wrapper":       "/usr/local/bin/git-data-transport-wrapper.sh",
    "git_data_remove":                  "/usr/local/bin/git-data-remove.sh",
    "git_data_gc":                      "/usr/local/bin/git-data-gc.sh",
    "git_data_gc_service":              "/etc/systemd/system/git-data-gc.service",
    "git_data_gc_failure_service":      "/etc/systemd/system/git-data-gc-failure.service",
    "git_data_gc_timer":                "/etc/systemd/system/git-data-gc.timer",
    "git_data_pre_receive_placeholder": "/tmp/git-data-pre-receive-placeholder.sh",
}

# (#7025, R7) The templatefile map and the strip expression moved out of git-data.tf and into
# modules/git-data-userdata/main.tf, which BOTH the production root and the rung-2 rehearsal
# root call. `${path.module}` there is the MODULE dir, so every binding reads `../../<name>`
# and must be resolved against moduledir — resolving against srcdir lands two levels too high
# and every payload would fail to open.
moduledir = os.path.join(srcdir, "modules", "git-data-userdata")
tf = open(os.path.join(moduledir, "main.tf")).read()
tpl = open(os.path.join(srcdir, "cloud-init-git-data.yml")).read()

# The payloads are delivered with whole-line `#` comments stripped at render time (ADR-152),
# so the source must be stripped the same way before the bytes are compared. Read the
# expression FROM modules/git-data-userdata/main.tf rather than restating it: a hand-copied
# spelling would drift,
# and a stripper that silently disagreed with production would make this whole check compare
# the wrong bytes while still reporting byte-identity.
# ANCHORED AT LINE START, and non-greedy between the quotes (#7264). The previous form was a
# bare `re.search` over the raw file taking the FIRST match, so a COMMENT naming an old
# expression (`# git_data_rationale_strip = "<old form>"` — exactly the prose this repo
# writes) would be extracted instead of the live assignment, and the probe below passes
# either way: wrong stripper, green suite. `^\s*` before the identifier makes a commented
# line unmatchable, because `#` is neither whitespace nor the identifier's first character.
# `[^"]*` stops the greedy `.*` over-reaching on a line carrying more than one quote pair.
#
# The name is also unambiguous by construction: main.tf now declares a SECOND expression,
# `git_data_template_rationale_strip`, which does not contain this one as a substring — so
# this search cannot pick up the template form, and the template search cannot pick up this
# one. ADR-152 requires them to differ; git-data-render-strip-parity.test.sh asserts it.
m = re.search(r'^\s*git_data_rationale_strip\s*=\s*"([^"]*)"', tf, re.M)
if not m:
    print("B1 FAIL: no git_data_rationale_strip in modules/git-data-userdata/main.tf — cannot mirror the render-time strip")
    sys.exit(1)
_expr = m.group(1)
if not (_expr.startswith("/") and _expr.endswith("/")):
    print("B1 FAIL: git_data_rationale_strip is not a /…/ regex literal: %r" % _expr)
    sys.exit(1)
STRIP = re.compile(_expr[1:-1].replace("\\t", "\t").replace("\\n", "\n"))
if not STRIP.search("#!/bin/sh\n# a comment\n"):
    print("B1 FAIL: the strip expression matches nothing on a known-commented probe — it "
          "would make every payload trivially 'identical'")
    sys.exit(1)

# ROSTER AUTHORITY: the render module's file() bindings. var -> source path, RELATIVE TO
# THE MODULE DIR (it is written `../../<name>`; see the moduledir note above).
bindings = dict(re.findall(
    r'^\s*([a-z_]+)\s*=\s*(?:replace\()?file\("\$\{path\.module\}/([^"]+)"\)', tf, re.M))
if len(bindings) < MIN_PAYLOADS:
    print("B1 FAIL: the render module binds only %d payload file()s (<%d) — the roster extraction "
          "drifted, and a shrunken roster would make every check below vacuous"
          % (len(bindings), MIN_PAYLOADS))
    sys.exit(1)

# PATH AUTHORITY: the template pairs `- path: <P>` with `${indent(6, <var>)}`. This is what
# says WHERE each payload lands; identity is the FULL PATH, never the basename (relocating
# git-data-gc.timer to /tmp/junk/ keeps its basename and its bytes, and systemd never sees it).
delivery = dict((v, pth) for pth, v in re.findall(
    r'-\s*path:\s*(\S+)\s*\n\s*content:\s*\|\s*\n\s*\$\{indent\(6,\s*([a-z_]+)\)\}', tpl))

undelivered = sorted(v for v in bindings if v not in delivery)
if undelivered:
    print("B1 FAIL: %d payload(s) bound by file() in the render module are NOT delivered by any "
          "indent(6, …) block in cloud-init-git-data.yml: %s"
          % (len(undelivered), ", ".join(undelivered)))
    print("  A payload the render module reads but the template never writes is a file the "
          "host will not have. If it is genuinely retired, remove its file() binding too.")
    sys.exit(1)

# The template must deliver each payload to the path this test pins, not merely to SOME path.
misrouted = sorted(
    "%s -> %s (expected %s)" % (v, delivery[v], EXPECTED_PATHS[v])
    for v in bindings if v in EXPECTED_PATHS and delivery[v] != EXPECTED_PATHS[v])
if misrouted:
    print("B1 FAIL: %d payload(s) are delivered to the WRONG PATH — same bytes, same "
          "basename, wrong destination, so the consumer never sees them:" % len(misrouted))
    for mr in misrouted:
        print("  " + mr)
    sys.exit(1)
unpinned = sorted(v for v in bindings if v not in EXPECTED_PATHS)
if unpinned:
    print("B1 FAIL: %d payload(s) have no pinned destination in EXPECTED_PATHS: %s"
          % (len(unpinned), ", ".join(unpinned)))
    print("  Add the destination to EXPECTED_PATHS so a later relocation is a review event.")
    sys.exit(1)

expected = {EXPECTED_PATHS[v]: bindings[v] for v in bindings}   # full path -> source filename

d = yaml.safe_load(open(rendered))
seen_paths, delivered, unknown, bad = [], {}, [], []
for wf in d["write_files"]:
    path = wf["path"]
    seen_paths.append(path)
    if path in expected:
        delivered[path] = wf["content"].encode()
    elif path not in INLINE_ALLOWLIST:
        unknown.append(path)

dupes = sorted({p for p in seen_paths if seen_paths.count(p) > 1})
if dupes:
    print("B1 FAIL: duplicate write_files path(s) %s — cloud-init applies in ORDER, so a "
          "second entry at a delivered or allowlisted path silently overrides the first "
          "(an unrestricted authorized_keys beats three command=-restricted ones)"
          % ", ".join(dupes))
    sys.exit(1)

if unknown:
    print("B1 FAIL: %d delivered payload(s) are neither a known file-backed source nor on "
          "the inline allowlist, so nothing compared their bytes:" % len(unknown))
    for u in unknown:
        print("  " + u)
    sys.exit(1)

missing = sorted(set(expected) - set(delivered))
if missing:
    print("B1 FAIL: %d expected payload path(s) were never delivered: %s"
          % (len(missing), ", ".join(missing)))
    sys.exit(1)

if len(delivered) < MIN_PAYLOADS:
    print("B1 FAIL: only %d file-backed payloads compared (<%d)" % (len(delivered), MIN_PAYLOADS))
    sys.exit(1)

for path in sorted(delivered):
    want = STRIP.sub("", open(os.path.join(moduledir, expected[path])).read()).encode()
    got = delivered[path]
    if hashlib.sha256(got).hexdigest() != hashlib.sha256(want).hexdigest():
        bad.append("%s: rendered sha=%s (%d B) != stripped source sha=%s (%d B)" % (
            path, hashlib.sha256(got).hexdigest()[:12], len(got),
            hashlib.sha256(want).hexdigest()[:12], len(want)))
if bad:
    print("B1 FAIL: %d payload(s) are NOT byte-identical to their stripped source:" % len(bad))
    for b in bad:
        print("  " + b)
    sys.exit(1)

print("B1 OK: %d file-backed payloads delivered at their exact paths, byte-identical to the "
      "stripped source; %d inline payload(s) allowlisted; no duplicate paths"
      % (len(delivered), len(INLINE_ALLOWLIST)))
PY
)"; _b1_rc=$?
if [ "$_b1_rc" -eq 0 ]; then pass; else
  fail "B1: a delivered payload differs from its repo source" "$_b1_out"
fi

# INSTRUMENT the extracted block so T5's "the chain did not continue past the failed
# checksum" assertion can OBSERVE continuation. Nothing in the shipped block prints
# anything, so `grep -q CHMOD_RAN` matched only its own source text — the assertion passed
# identically against a completely unguarded chain. The marker rides on the chmod line
# because chmod is the last of the three commands the abort must prevent (`sha256sum -c -`
# fails => tar, chmod and this echo are all unreached).
#
# THE MARKER IS `&&`-CHAINED, NOT `;`-CHAINED (#7565). With `;` the echo ran no matter what
# chmod did, so in the mutation arm — which strips `set -e` — CHMOD_RAN printed after a failed
# curl, a failed sha256sum, a failed tar AND a failed chmod. That arm exists to prove the
# marker is REACHABLE when the chain runs; the `;` form made it print when the chain had
# collapsed, which is the opposite claim. `&&` makes the marker mean what its name says:
# chmod ran, and chmod succeeded.
#
# WHY A BARE `&&` AND NOT AN ERREXIT-PRESERVING TAIL. bash does NOT fire errexit on a failing
# NON-FINAL member of an AND-OR list — measured: `set -e; false && echo M; echo AFTER` prints
# AFTER and exits 0. So `&&` genuinely does relax errexit on this line. It is not OBSERVABLE
# here, because no arm in this suite can reach a FAILING chmod under `set -e`: the primary arm
# aborts at the checksum by construction (that is the property under test), the mutation arm
# has already had `set -e` stripped, and T17 replaces the block with `printf 'true\n'` and has
# no chmod at all. Do not reach for a `|| { rc=$?; …; ( exit $rc ); }` tail — it buys nothing
# on this line and misfires when the ECHO fails (EPIPE, full disk), attributing echo's status
# to chmod.
python3 - "$TMP/doppler-dl.sh" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
old = "chmod +x /usr/local/bin/doppler"
if s.count(old) != 1:
    sys.stderr.write("expected exactly 1 chmod line in the extracted block, found %d\n" % s.count(old))
    sys.exit(3)
open(p, "w").write(s.replace(old, old + " && echo CHMOD_RAN"))
PY
# ANCHORED ON THE WHOLE EMITTED CONSTRUCT, not on a bare token. The old check was
# `grep -q 'echo CHMOD_RAN'`, which stays GREEN after the transform is reverted to `;` —
# because `; echo CHMOD_RAN` contains `echo CHMOD_RAN` too. Matching the full line is what
# makes a reverted, renamed or non-landing transform detectable at all
# (`cq-assert-anchor-not-bare-token`).
#
# NOT because prose could satisfy it: an earlier draft of this comment said the old grep was
# "satisfied by the comment prose above it", and that was FALSE — the grep target is the
# EXTRACTED block, not this file, and #7264 extended ADR-152's strip to the template, so the
# rendered block carries zero comment lines (measured). The `;`-revert argument carries the
# point on its own; the prose-collision argument was a wrong threat model that would have
# misled the next reader tightening this anchor.
grep -q '^chmod +x /usr/local/bin/doppler && echo CHMOD_RAN$' "$TMP/doppler-dl.sh" || {
  echo "FAIL: CHMOD_RAN instrumentation did not land — T5 would be a tautology again" >&2; exit 1; }

# DERIVED FROM THE ARTIFACT, NOT HAND-COPIED. T5's checksum-verdict assertion needs the tarball
# path sha256sum will name. Hard-coding `/tmp/doppler.tar.gz` duplicates a literal the shipped
# block owns, so a benign rename there would red the supply-chain guard with "the abort was not
# the checksum" — a false diagnosis of a cosmetic change, and the same hand-maintained-constant
# drift this file has already been bitten by twice (the docker-run count below).
_DL_TARBALL="$(sed -n 's#^curl .* -o \([^ ]*\).*#\1#p' "$TMP/doppler-dl.sh" | head -1)"
[ -n "$_DL_TARBALL" ] || {
  echo "FAIL: could not derive the download target from the extracted block — T5's checksum assertion would be unanchored" >&2; exit 1; }

# A capture endpoint inside the container network, standing in for Sentry.
cat > "$TMP/capture.py" <<'PY'
import http.server, socketserver
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(n)
        # CONTEXT-MANAGED, so the bytes are flushed and the file closed BEFORE the response
        # is sent. The round-trip sentinel below polls this file from the same container, so
        # a write left buffered in a CPython file object that only closes at GC would make
        # the poll race the flush -- and a sentinel that intermittently fails to appear is
        # indistinguishable from a capture path that is genuinely dead, which is the exact
        # ambiguity this whole change exists to remove.
        with open("/out/capture.log", "ab") as f:
            f.write(body + b"\n")
        self.send_response(200); self.end_headers(); self.wfile.write(b"{}")
    def log_message(self, *a): pass
socketserver.TCPServer(("127.0.0.1", 8099), H).serve_forever()
PY

# The in-container driver. It arms a MODEL of the shipped trap/STAGE preamble — a
# hand-written copy, not the extracted one — and runs the extracted checksum block under
# `set -e` exactly as runcmd does.
#
# WHY A COPY, AND WHAT KEEPS IT HONEST. The shipped preamble cannot be sourced verbatim here
# because it runs a delivery pre-check against the real DSN. (Until #7227 it ALSO hard-coded
# /var/log/cloud-init-output.log as its detail — absent in the container, so every emit shipped
# an empty detail; `on_err` now passes "$_onerr_detail", so that half of the reason is gone and
# the DSN pre-check is what remains.) So the driver models it.
#
# A model that nothing compares against is how "the SAME preamble" becomes false without
# anyone noticing — this comment said exactly that while `preamble.sh` was extracted,
# asserted to be exactly one block, and then never read by anything. B2 below is the
# comparison that makes the claim true: every load-bearing construct of the shipped
# preamble must appear in BOTH, so a shipped preamble that loses its `set -e`, its trap, or
# its rc guard turns this suite red instead of leaving it green against a stale model.
cat > "$TMP/drive.sh" <<'DRIVE'
#!/bin/bash
set -uo pipefail
python3 /work/capture.py &
# BOUNDED POLL, not a fixed `sleep 1`. Under CPU contention (several of these containers
# run concurrently on a dev box) python3 can miss a 1s window, curl gets connection-refused,
# capture.log stays empty, and R3(3a) fails -- which reads as a substantive finding about
# the emitter rather than as a starved fixture. Fail loud if it never comes up.
for _i in $(seq 50); do (echo > /dev/tcp/127.0.0.1/8099) 2>/dev/null && break; sleep 0.1; done
(echo > /dev/tcp/127.0.0.1/8099) 2>/dev/null || { echo 'FIXTURE: capture server never bound :8099' >&2; exit 2; }
sed -i "s#^DSN='.*'#DSN='https://k@127.0.0.1:8099/1'#" /work/git-data-emit
python3 - <<'FIX'
p="/work/git-data-emit"; s=open(p).read()
s=s.replace('"https://${SHOST}/api/${PROJ}/store/"','"http://${SHOST}/api/${PROJ}/store/"')
open(p,"w").write(s)
FIX
chmod +x /work/git-data-emit
mkdir -p /usr/local/bin && cp /work/git-data-emit /usr/local/bin/git-data-emit

STAGE=gitdata_runcmd_early
# (#7227) MODELS THE SHIPPED HANDLER, which now derives its title from $STAGE and passes a
# seeded, [ -s ]-guarded scoped file rather than the literal "". Kept in step deliberately:
# B2SPEC pins six constructs but NOT the title or the detail source, so a driver left modelling
# the old shape drifts silently from the preamble it exists to mirror.
GIT_DATA_RUNCMD_DETAIL=/run/git-data-runcmd.log
( umask 077; : > "$GIT_DATA_RUNCMD_DETAIL" ) || true
[ -w "$GIT_DATA_RUNCMD_DETAIL" ] || GIT_DATA_RUNCMD_DETAIL=/dev/null
on_err() {
  rc=$?
  trap - EXIT
  [ "$rc" -eq 0 ] && exit 0
  _onerr_detail="$GIT_DATA_RUNCMD_DETAIL.final"
  ( umask 077; : > "$_onerr_detail" ) || true
  { dmesg 2>/dev/null | tail -n 20 || true; } > "$_onerr_detail" 2>/dev/null || true
  [ -s "$_onerr_detail" ] || _onerr_detail="git-data $STAGE rc=$rc: detail capture unavailable"
  /usr/local/bin/git-data-emit "git-data $STAGE FAILED" "$STAGE" fatal \
    "$_onerr_detail" "rc=$rc" || true
  exit 1
}
trap on_err EXIT
set -e
STAGE=gitdata_doppler_dl
# SOURCED, not `bash /work/doppler-dl.sh`. cloud-init concatenates every runcmd entry into
# ONE script, so the `set -e` armed above is in effect for this block. Running it as a
# CHILD bash gives that child its own (unset) options, so a failing `sha256sum -c -` would
# not abort — measured: the checksum failed, the child exited non-zero, and the driver
# still exited 0. A harness that models the block as a subprocess tests the opposite of
# what ships.
#
# EXECUTION MARKER (#7291). Emitted immediately above the source line and BELOW the
# capture-server guard. Its position is the whole point: above the source line it cannot be
# reached by a run that died in apt or at the image pull, and below the :8099 guard it stays
# distinguishable from a fixture failure — which the T5 mutation verdict tests separately, and
# earlier.
#
# STILL AN ABSENCE TEST — corrected at review. This block used to call the resulting verdict a
# "POSITIVE observation", which is the phrasing the header block retracts (the code reads
# `! grep`). What the marker buys is not positivity but DISCRIMINATION: the verdict turns on the
# absence of a distinct, EARLIER marker that localises the failure upstream of the download
# block, rather than on the absence of the success marker. Strictly more informative than the
# original, and still an inference from an absence.
echo DRIVER_REACHED_DL
. /work/doppler-dl.sh
DRIVE

# ── B2 — the driver's arming must not drift from the SHIPPED preamble ──────────────
# Each construct below is load-bearing, and each must appear on BOTH sides:
#   trap on_err EXIT        the arming itself — without it nothing reports
#   set -e                  what makes a failed checksum abort instead of continuing
#   rc=$?                   captured BEFORE `trap - EXIT` clobbers it
#   [ "$rc" -eq 0 ]         the rc guard: without it every HEALTHY boot emits fatal (T17)
#   trap - EXIT             disarm inside the handler, so the handler cannot re-enter
#   git-data-emit           the emit call the whole channel depends on
# ANCHORED ON CODE, NOT ON THE TOKEN — and comments stripped first. Both halves are
# load-bearing, and the first draft of this guard had neither, so it was VACUOUS: deleting
# the shipped `set -e` left B2 green, because `grep -F 'set -e'` still matched the comment
# two lines above it ("Arm `set -e` only AFTER the Phase-0.4 classification") — and would
# equally have matched `set -euo pipefail` as a substring. A body-grep sees comments too
# (cq-assert-anchor-not-bare-token). Each pattern below is line-anchored and `$`-terminated
# where the construct is a whole statement, so prose about it cannot satisfy it.
_b2_strip() { sed -e 's/[[:space:]]*#.*$//' "$1"; }
_b2_missing=""
_b2_pre="$TMP/preamble.nocomment"; _b2_drv="$TMP/drive.nocomment"
_b2_strip "$TMP/runcmd-all.sh" > "$_b2_pre"
_b2_strip "$TMP/drive.sh"    > "$_b2_drv"
# COUNTS, not existence. `rc=$?`, the rc guard and `trap - EXIT` each appear once per trap
# site. An existence check cannot see ONE of them deleted, which is the realistic drift:
# measured, removing on_err's rc guard left an existence-based B2 fully green because the
# other handlers' copies still satisfied it. The driver models a single trap, so its minimum
# is 1 for every construct.
#
# MINIMUMS 3/3/4 -> 2/2/2 (#7227): bootstrap_err was DELETED. It was byte-identical to on_err
# but for a title `$STAGE` already supplies, and it was never disarmed, so a gc_timer failure
# emitted "git-data bootstrap FAILED". Two handlers remain — on_err (parent) and luks_err
# (the doppler child) — so `rc=$?` and the rc guard drop 3 -> 2.
#
# The disarm minimum drops 4 -> 2, losing TWO: bootstrap_err's own `trap - EXIT` AND the bare
# disarm that preceded its definition. That bare disarm + re-arm pair was NOT re-pointed at
# on_err, because it was a no-op — `trap luks_err EXIT` lives inside the heredoc and binds the
# `doppler run` CHILD, so the parent's on_err was never replaced and needed no restoring.
# Derive minimums from the artifact, not from the count you expect the design to have.
while IFS='|' read -r _label _min _re; do
  [ -n "$_label" ] || continue
  _n_pre=$(grep -cE -- "$_re" "$_b2_pre" || true)
  _n_drv=$(grep -cE -- "$_re" "$_b2_drv" || true)
  [ "$_n_pre" -ge "$_min" ] || _b2_missing="${_b2_missing} shipped:[${_label} ${_n_pre}<${_min}]"
  [ "$_n_drv" -ge 1 ]       || _b2_missing="${_b2_missing} driver:[${_label}]"
done <<'B2SPEC'
trap on_err EXIT|1|^[[:space:]]*trap on_err EXIT[[:space:]]*$
set -e (exactly)|1|^[[:space:]]*set -e[[:space:]]*$
rc=$? capture|2|^[[:space:]]*rc=\$\?[[:space:]]*$
rc guard|2|^[[:space:]]*\[ "\$rc" -eq 0 \][[:space:]]*&&[[:space:]]*exit 0[[:space:]]*$
trap - EXIT disarm|2|^[[:space:]]*trap - EXIT[[:space:]]*$
doppler stage name|1|^[[:space:]]*STAGE=gitdata_doppler_dl[[:space:]]*$
emit call|1|/usr/local/bin/git-data-emit[[:space:]]+"
B2SPEC
# DERIVED, NOT FROZEN (review). The 2|2|2 minimums above are a snapshot of a two-handler tree,
# and the comment twenty lines up already prescribes the fix — "Derive minimums from the artifact,
# not from the count you expect the design to have" — while the table three lines below it refuses
# to. A third stage handler added with no rc guard and no disarm keeps every `-ge 2` satisfied, so
# a handler that fires `fatal` on every healthy exit (the T17 defect) ships unwatched. The
# invariant is not a floor at all: EVERY handler that captures `rc=$?` must also guard it and
# disarm its trap, so the three counts must be EQUAL. Folded into _b2_missing rather than added as
# its own assertion, so this costs no floor movement.
_b2_rc=$(grep -cE -- '^[[:space:]]*rc=\$\?[[:space:]]*$' "$_b2_pre" || true)
_b2_grd=$(grep -cE -- '^[[:space:]]*\[ "\$rc" -eq 0 \][[:space:]]*&&[[:space:]]*exit 0[[:space:]]*$' "$_b2_pre" || true)
_b2_dis=$(grep -cE -- '^[[:space:]]*trap - EXIT[[:space:]]*$' "$_b2_pre" || true)
if [ "$_b2_grd" -ne "$_b2_rc" ] || [ "$_b2_dis" -ne "$_b2_rc" ]; then
  _b2_missing="${_b2_missing} derived:[handlers=${_b2_rc} rc-guards=${_b2_grd} disarms=${_b2_dis} — every handler capturing rc must guard and disarm]"
fi
if [ -z "$_b2_missing" ]; then pass; else
  fail "B2: the driver and the shipped preamble have drifted" "missing —${_b2_missing}"
fi

# NOTE on container networking: these runs are NOT `--network none`. The image needs curl
# and python3 from apt, and with no network `apt-get` exits 100 before any assertion runs —
# which presents as every case failing at once rather than as a setup error. The assertion
# stays hermetic regardless: the capture endpoint is on the container's own loopback. With
# real network T5 is also MORE faithful — it downloads the genuine tarball and then fails
# the checksum, which is exactly the supply-chain case being defended against.
run_case() {
  # $1 = case name, $2 = sed applied to the extracted block, $3 = expected driver exit
  local name="$1" mut="$2" want="$3"
  rm -rf "$TMP/out"; mkdir -p "$TMP/out"; : > "$TMP/out/capture.log"
  cp "$TMP/doppler-dl.sh" "$TMP/dl.case.sh"
  [ -n "$mut" ] && sed -i "$mut" "$TMP/dl.case.sh"
  docker run --rm \
    -v "$TMP/dl.case.sh:/work/doppler-dl.sh:ro" \
    -v "$TMP/git-data-emit:/work/git-data-emit-src:ro" \
    -v "$TMP/capture.py:/work/capture.py:ro" \
    -v "$TMP/drive.sh:/work/drive.sh:ro" \
    -v "$TMP/out:/out" \
    ubuntu:24.04 bash -c '
      set -e
      cp /work/git-data-emit-src /work/git-data-emit
      # TWO STATEMENTS, NOT `a && b`. `set -e` does not fire on a failing NON-FINAL member of an
      # AND-OR list (measured), so with `&&` a failed apt-get UPDATE fell through into drive.sh
      # with no python3/curl, the capture server never bound, and the run surfaced as a `FIXTURE:`
      # hard FAIL asserting a deterministic fixture defect that had not occurred. Split, either
      # failure aborts the container with its own rc and the verdict classifies it honestly.
      # The >/dev/null 2>&1 is load-bearing for CONFIDENTIALITY, not only noise: behind an
      # authenticated apt proxy apt error text embeds user:pass@host, and the skip reason tails
      # this capture on a GREEN run.
      apt-get update -qq >/dev/null 2>&1
      apt-get install -y -qq curl python3 >/dev/null 2>&1
      bash /work/drive.sh
    ' >"$TMP/out/stdout" 2>&1
  local rc=$?
  CASE_RC="$rc"; CAPTURE="$TMP/out/capture.log"
  if [ "$rc" -eq "$want" ]; then pass; else fail "$name: exit $rc, expected $want" "$(tail -3 "$TMP/out/stdout")"; fi
}

# ── D1 — the SHIPPED emitter must survive /bin/sh, which is dash on 24.04 ──────────
# cloud-init's util.shellify() emits `#!/bin/sh`, and the emitter itself declares it. bash
# TOLERATES constructs dash kills the shell on — most sharply `shift N` with fewer than N
# args, because `shift` is a POSIX SPECIAL BUILTIN whose error terminates a non-interactive
# shell outright and which `|| true` cannot catch. Asserted DIRECTLY against dash rather
# than inferred from the driver's interpreter, so it holds regardless of how the container
# case is wired.
# DASH IS A RUNNER-CONTRACT DEPENDENCY, GUARDED AT THE TOP WITH THE OTHER FOUR (review).
# This arm used to end in an `else pass; pass` counterweight "to keep the cardinality floor
# honest". It kept the floor honest and the MEASUREMENT dishonest: on a runner without dash the
# summary line was byte-identical to a full run — 49 passed, 0 failed, Skipped: 0, no NOTE — so
# nothing distinguished a run that tested the emitter's dash-compatibility from one that did not.
# Fabricating passes is the vacuity class this whole file is written against, and it was the only
# bare multi-`pass` here. dash ships /bin/sh on Ubuntu and is an essential package, so its absence
# is a provisioning defect in the same class as docker/terraform/python3 — which means `_skip`,
# not a counterweight and not `arm_skip` (nobody-owns-it is false for an essential package).
# Hoisting it up there also keeps the skip ceiling at 2: this arm never becomes skip-eligible.
if dash -n "$TMP/git-data-emit" 2>/dev/null; then pass; else fail "D1: emitter is not valid dash"; fi
# A 3-arg call is what the usage line invites. Under a bare `shift 4` dash exits 2 having
# emitted nothing — silently, on a host whose only diagnostic is this emitter.
( cd "$TMP" && dash ./git-data-emit "m" "s" info >/dev/null 2>&1 )
_d_rc=$?
# PRE-EXISTING HAZARD, TRACKED IN #7570 — deliberately not fixed here (#7565 pins run_case
# unmodified). CAPTURE is first assigned inside run_case, whose first call is T5 BELOW this
# arm, so under this file's `set -u` the expansion below is of an unset variable. `[`
# short-circuits on `||`, so it is reachable ONLY when _d_rc == 2 — precisely D1's failing
# direction. A real emitter regression would therefore abort with "CAPTURE: unbound
# variable" instead of D1's own message. Do not read the green here as coverage of it.
if [ "$_d_rc" -ne 2 ] || [ -s "$CAPTURE" ]; then pass; else
  fail "D1: a 3-arg call died at the shift (dash rc=2) instead of emitting"; fi

# ── T5 — a WRONG checksum must ABORT before tar/chmod ──────────────────────────────
# This is the supply-chain half of issue item 3. Before #6982 there was no `set -e`, so a
# failed `sha256sum -c -` still ran `tar xzf` and `chmod +x /usr/local/bin/doppler` on an
# unverified tarball that then executed as ROOT. Here curl is EXPECTED to succeed (real
# network) and fetch the genuine tarball, so that the checksum is the only thing left that can
# stop the chain — the faithful version of the supply-chain case.
#
# "THE CHECKSUM IS THE ONLY THING THAT CAN STOP THE CHAIN" IS A PROPERTY OF A HEALTHY
# ENVIRONMENT, NOT A GUARANTEE (#7565). If the release CDN is unreachable while apt still
# works, curl fails, `set -e` aborts into `on_err`, and `on_err` emits stage=doppler_dl,
# level=fatal and exits 1 — satisfying every one of the rc/stage/level/no-CHMOD_RAN assertions
# below WITHOUT sha256sum ever having run. Four green assertions, and the supply-chain property
# they are named for was never evaluated. The checksum-verdict assertion is what makes this arm
# say which command actually aborted, instead of merely that something did.
run_case "T5 wrong-checksum aborts" 's#^DOPPLER_SHA256=.*#DOPPLER_SHA256="0000000000000000000000000000000000000000000000000000000000000000"#' 1
# ERREXIT ORDERING IS T5's LOAD-BEARING PRECONDITION TOO — asserted at review, mirroring the
# assertion S1 has carried for its own stage. T5's entire claim is that the `set -e` armed in one
# runcmd entry covers the doppler block in a LATER entry, because cloud-init concatenates them.
# The two live in separate entries and nothing pinned their ORDER: move the shipped `set -e` below
# the doppler entry and every guard here stays green — B2 sees `set -e` present on both sides, T5's
# rc/stage/level/verdict/CHMOD_RAN-absent all still hold because the DRIVER arms errexit itself,
# and S1's inequality is satisfied a fortiori by `set -e` moving LATER. Production would then run
# `tar xzf` and `chmod +x /usr/local/bin/doppler` as root on an unverified tarball with the whole
# suite reporting success. The inequality is the mirror image of S1's: the doppler stage must come
# AFTER the arming, where sshd_config must come BEFORE it.
# `|| true` because a NO-MATCH here is a normal answer, not an error — the `[ -n ]` guards below
# are what decide. Required by `lint-shell-capture-exit`, which is a RATCHET: S1's byte-identical
# captures 380 lines down are grandfathered in its 210-entry baseline, so mirroring S1's shape
# added two NEW findings and rejected. Baselining them was the wrong fix — that grows the accepted
# population, which is the one thing the ratchet exists to stop. (This file runs `set -uo pipefail`
# with no `-e`, so the lint's stated hazard cannot bite here; the guard is for the shape, and
# satisfying it costs nothing.)
_t5_stage_ln=$(grep -n '^[[:space:]]*STAGE=gitdata_doppler_dl[[:space:]]*$' "$TMP/runcmd-all.sh" | head -1 | cut -d: -f1) || true
_t5_sete_ln=$(grep -n '^[[:space:]]*set -e[[:space:]]*$' "$TMP/runcmd-all.sh" | head -1 | cut -d: -f1) || true
if [ -n "$_t5_stage_ln" ] && [ -n "$_t5_sete_ln" ] && [ "$_t5_sete_ln" -lt "$_t5_stage_ln" ]; then pass; else
  fail "T5: the shipped chain does not arm 'set -e' before the doppler stage (set -e=${_t5_sete_ln:-?}, stage=${_t5_stage_ln:-?})" \
       "T5 asserts the checksum aborts the chain; without the arming ordered first, a failed sha256sum runs tar+chmod as root on an unverified tarball."; fi

# THE STAGE LITERAL IS THE SHIPPED ONE (review). The driver modelled the stage as `doppler_dl`
# while the template emits `gitdata_doppler_dl`, so this assertion validated the harness's own
# model and would have failed against the real artifact — and the sibling stage had the same
# divergence with no assertion at all. Both driver names are now the template's, and B2SPEC pins
# the literal on BOTH sides so they cannot drift apart again silently.
# ONE RECORD, NOT A BAG UNION (review). These were two independent greps over the same capture,
# so an emitter shipping `stage=gitdata_doppler_dl level=info` alongside an unrelated
# `stage=other level=fatal` satisfied both while no doppler_dl fatal existed. The property is a
# single-record conjunction and is now asserted as one — which is also why the pair collapses to
# ONE counted assertion rather than two. S1 already does this correctly with a joined pattern.
# `awk` rather than `grep … | grep -q`: field ORDER differs between the two emit shapes (Sentry
# nests stage inside tags AFTER level; the Better Stack body is flat with stage FIRST), so a
# positional regex would pin one shape, and a `grep -q` on a pipe is the SIGPIPE fail-open this
# repo forbids — the producer takes 141 and `pipefail` reports failure on a successful match.
if awk '/"stage":"gitdata_doppler_dl"/ && /"level":"fatal"/ { found = 1 } END { exit !found }' \
     "$CAPTURE" 2>/dev/null; then pass; else
  fail "T5: no single record carried both stage=gitdata_doppler_dl and level=fatal" \
       "$(head -2 "$CAPTURE" 2>/dev/null)"; fi
# THE CHECKSUM'S OWN VERDICT. `sha256sum -c -` writes `<file>: FAILED` to STDOUT (only the
# "WARNING: 1 computed checksum did NOT match" summary goes to stderr, which the shipped block
# redirects into $GIT_DATA_RUNCMD_DETAIL inside the container). run_case captures container
# stdout+stderr into $TMP/out/stdout, so the deciding evidence is already here and needs no
# instrumentation.
#
# WHOLE-LINE MATCH (`-x`), NOT A SUBSTRING. A MISSING tarball — curl never wrote one — makes
# sha256sum print `<path>: FAILED open or read` on the same stream. A substring `: FAILED`
# matches that, so a checksum-specific assertion would be satisfied by a DOWNLOAD failure:
# this exact bug, in a new disguise. `-xF` pins the whole line as a fixed string, so no path
# metacharacter needs escaping and the derived path cannot smuggle a regex in.
#
# HOW LIVE IS THAT HAZARD? Not live as this suite ships, and saying otherwise would be the
# defect this PR closes. Under the primary arm's `set -e` a failed curl aborts BEFORE sha256sum
# runs, so the over-match cell emits no verdict line at all; reaching it took appending
# `|| true` to curl (mutation-transcript G1-2a/G1-2b). This is defence-in-depth against a
# future edit that lets the chain survive a failed download — a weaker claim than "load-bearing
# today", and the true one.
#
# The message names only what was measured — sha256sum did not reject the tarball. It does NOT
# say "the abort was not the checksum", because when the genuine checksum passes there is no
# abort at all and that phrasing would assert a cause the arm never measured (ADR-166). Note
# `scripts/lint-diagnosis-claims.sh` skips `*.test.sh`, so ADR-166 here is prose-enforced.
if grep -qxF "${_DL_TARBALL}: FAILED" "$TMP/out/stdout" 2>/dev/null; then pass; else
  fail "T5: sha256sum's rejection verdict for ${_DL_TARBALL} is absent from container stdout — the checksum is not what stopped this chain (rc/stage asserted separately)" \
       "$(tail -3 "$TMP/out/stdout" 2>/dev/null)"; fi
# The abort must precede the unverified install. If /usr/local/bin/doppler exists the
# chain continued past the checksum, which is the exact pre-#6982 behaviour.
#
# `-x` (whole line), not a bare token: bash ECHOES the offending source line on a syntax error,
# and that line contains the marker — so a malformed block could satisfy a substring grep with
# chmod never having run, which flips the mutation arm below to a false GREEN.
if grep -qx 'CHMOD_RAN' "$TMP/out/stdout" 2>/dev/null; then
  fail "T5: the chain continued past the failed checksum"; else pass; fi
# THE ARTIFACT THIS ARM ACTUALLY MOUNTED. The check at the instrumentation site pins what
# $TMP/doppler-dl.sh IS; run_case then derives $TMP/dl.case.sh from it via `cp` + `sed -i`, and
# nothing had pinned THAT copy. The asymmetry mattered: this arm's CHMOD_RAN assertion is
# NEGATIVE, so a marker lost in transit makes it pass VACUOUSLY — the exact tautology class
# #7565 exists to kill — whereas the mutation arm's is POSITIVE and fails loudly on its own.
# run_case does not delete dl.case.sh on return, so the file is still here; T17 calls run_case
# separately with its own marker-free payload and is unaffected by a check placed here.
grep -q '^chmod +x /usr/local/bin/doppler && echo CHMOD_RAN$' "$TMP/dl.case.sh" || {
  echo "FAIL: the mounted T5 PRIMARY artifact lost the CHMOD_RAN instrumentation — its absence assertion above was vacuous" >&2
  grep -n 'chmod +x /usr/local/bin/doppler' "$TMP/dl.case.sh" >&2 || true; exit 1; }

# MUTATION for T5 — prove the marker is REACHABLE, so its absence above is evidence of the
# abort rather than evidence that nothing ever prints it.
#
# The mutant removes the driver's `set -e`, which is exactly the pre-#6982 boot: curl still
# succeeds (real network, genuine tarball), the checksum still fails, and the chain runs
# `tar xzf` + `chmod +x /usr/local/bin/doppler` on an UNVERIFIED tarball that then executes
# as root. So this arm reproduces the supply-chain defect the fix closes, and CHMOD_RAN
# must appear.
# The T5 PRIMARY arm's execution evidence, read BEFORE the rm below destroys it. EVIDENCE ONLY,
# never a gate. Note it is near-constant `yes` on any green run — the primary passes only via
# on_err's exit 1, which requires passing the marker line — so it discriminates little on its own;
# what it buys is the narrow-window reading: the environment was fine seconds earlier.
_t5_primary_reached=no
grep -q "$_T5_MARKER" "$TMP/out/stdout" 2>/dev/null && _t5_primary_reached=yes

rm -rf "$TMP/out"; mkdir -p "$TMP/out"; : > "$TMP/out/capture.log"
sed 's/^set -e$/true/' "$TMP/drive.sh" > "$TMP/drive.noerrexit.sh"
# STRUCTURAL (hard-exit, uncounted): the marker must be present on the MOUNTED artifact, not
# merely in the source heredoc. This pins the transform's APPLICATION rather than only its
# correctness — a sed that silently dropped the line would make the verdict below read EVERY
# run as a non-execution and skip forever, which is precisely the #7291 defect relocated one
# level up. Anchored on the whole line so prose naming the marker cannot satisfy it.
grep -q "^echo ${_T5_MARKER}\$" "$TMP/drive.noerrexit.sh" || {
  echo "FAIL: the execution marker is absent from the mounted driver — the T5 mutation verdict would read every run as a non-execution" >&2
  exit 1; }
# STRUCTURAL, same class, added at review: pin the FIXTURE marker's producer to its consumer.
# The verdict below greps $_T5_FIXTURE_MARKER against container stdout; the only thing that can
# emit it is drive.sh's :8099 bind guard. Nothing connected the two, so renaming the emit alone
# — which the rest of this file has ALREADY done for every other fixture marker, to
# `FIXTURE-FAIL:` — would leave the rung permanently unmatched and silently reclassify a
# deterministic bind failure as an environment decline: two hard FAILs become a green skip.
# Matched as a fixed string against the mounted artifact, so the emit and the read move together
# or this exits before any verdict is formed.
grep -qF "$_T5_FIXTURE_MARKER" "$TMP/drive.noerrexit.sh" || {
  echo "FAIL: the fixture marker is absent from the mounted driver — the T5 mutation verdict's fixture-defect rung is unreachable, so a deterministic bind failure would be reported as an environment skip" >&2
  grep -n 'FIXTURE' "$TMP/drive.noerrexit.sh" >&2 || true
  exit 1; }
if diff -q "$TMP/drive.sh" "$TMP/drive.noerrexit.sh" >/dev/null; then
  fail "T5 MUTATION did not land: 'set -e' not found in the driver"
else
  cp "$TMP/doppler-dl.sh" "$TMP/dl.case.sh"
  sed -i 's#^DOPPLER_SHA256=.*#DOPPLER_SHA256="0000000000000000000000000000000000000000000000000000000000000000"#' "$TMP/dl.case.sh"
  # THE MOUNTED ARTIFACT, NOT THE SOURCE COPY. The post-transform check up at the
  # instrumentation site pins what $TMP/doppler-dl.sh IS; it cannot pin that the file this
  # container actually mounts still carries the marker. Anything between here and the
  # docker run — this `cp`, this `sed -i`, a future edit — could drop it, and the arm would
  # then fail with "the chain still did not reach chmod", blaming the system under test for
  # a harness defect.
  #
  # WHY HERE AND NOWHERE ELSE. Two placements look natural and both break the suite. At the
  # instrumentation site $TMP/dl.case.sh does not exist yet — it is created inside run_case,
  # and separately right here. Inside run_case it would hard-exit on T17, which deliberately
  # overwrites $TMP/doppler-dl.sh with `printf 'true\n'` before its own run_case call, so
  # T17's mounted copy legitimately carries no chmod and no marker. This arm is the one place
  # where the file provably exists AND provably must carry it.
  grep -q '^chmod +x /usr/local/bin/doppler && echo CHMOD_RAN$' "$TMP/dl.case.sh" || {
    echo "FAIL: the mounted T5 mutation artifact lost the CHMOD_RAN instrumentation" >&2; exit 1; }
  # STRUCTURAL, added at review: every mount SOURCE must exist before the run.
  # This is what makes it safe to keep 125 in _T5M_ENV_RCS. docker exits 125 for BOTH a failed
  # image pull (an environment decline the skip is justified for) and a bad `-v` source (a defect
  # in THIS file), and the rc alone cannot tell them apart — so without this check a mistyped
  # mount path produced no marker, landed on `did-not-run`, and reported a green skip with a NOTE
  # forever. The paths are static and this file owns all of them, so asserting them here removes
  # the harness half of 125 entirely rather than trying to classify docker's error text.
  for _m in "$TMP/dl.case.sh" "$TMP/git-data-emit" "$TMP/capture.py" "$TMP/drive.noerrexit.sh" "$TMP/out"; do
    [ -e "$_m" ] || {
      echo "FAIL: T5 mutation mount source is missing: ${_m} — docker would exit 125 and the verdict would misread a harness defect as an environment decline" >&2
      exit 1; }
  done
  docker run --rm \
    -v "$TMP/dl.case.sh:/work/doppler-dl.sh:ro" \
    -v "$TMP/git-data-emit:/work/git-data-emit-src:ro" \
    -v "$TMP/capture.py:/work/capture.py:ro" \
    -v "$TMP/drive.noerrexit.sh:/work/drive.sh:ro" \
    -v "$TMP/out:/out" \
    ubuntu:24.04 bash -c '
      set -e
      cp /work/git-data-emit-src /work/git-data-emit
      # TWO STATEMENTS, NOT `a && b`. `set -e` does not fire on a failing NON-FINAL member of an
      # AND-OR list (measured), so with `&&` a failed apt-get UPDATE fell through into drive.sh
      # with no python3/curl, the capture server never bound, and the run surfaced as a `FIXTURE:`
      # hard FAIL asserting a deterministic fixture defect that had not occurred. Split, either
      # failure aborts the container with its own rc and the verdict classifies it honestly.
      # The >/dev/null 2>&1 is load-bearing for CONFIDENTIALITY, not only noise: behind an
      # authenticated apt proxy apt error text embeds user:pass@host, and the skip reason tails
      # this capture on a GREEN run.
      apt-get update -qq >/dev/null 2>&1
      apt-get install -y -qq curl python3 >/dev/null 2>&1
      bash /work/drive.sh
    ' >"$TMP/out/stdout" 2>&1; _t5m_rc=$?
  # rc is CAPTURED AND USED. The trailing `|| true` this replaces discarded the one datum that
  # classifies a non-execution — and it was not merely lossy: with `|| true` the status is 0 on
  # EVERY run, so the harness-defect rung below would fire on every degraded run and convert each
  # skip back into a FAIL. The two are mutually exclusive. The assignment is on the
  # SAME LINE as the command deliberately: a comment block between them makes inserting a command
  # there look safe, and any inserted command silently clobbers `$?`. NOT `local` — this arm is
  # top-level, where `local` errors, leaves the variable unset, and `set -u` kills the suite.
  _t5m_tail="$(tail -5 "$TMP/out/stdout" 2>/dev/null)"
  # AP-021/ADR-166: the verdict is derived from MARKER ABSENCE, which is not itself a cause.
  # The rc is therefore OFFERED with its measured classes and never asserted as the reason —
  # this arm did not measure why a download failed and does not claim to.
  # rc=2 (the capture-server guard) is deliberately NOT offered: its message rides this same
  # captured stream and is tested one branch below, so it can never accompany a skip. AP-021
  # asks that offered classifications stay honest, which includes not listing an unreachable one.
  _t5m_rc_note="docker rc=${_t5m_rc} (measured classes: 125 docker CLI/image pull, 100 apt under the container's outer set -e — offered as classification, not asserted as cause)"

  # DID THIS ARM RUN? Decided ONCE, above the assertions, because #7565 gave the arm a SECOND
  # counted assertion (the premise below) and both depend on the same answer. Deciding per
  # assertion would let the two disagree, and would make the arm's contribution vary by route —
  # which is exactly what the absolute floor cannot tolerate.
  #
  # ORDER IS LOAD-BEARING, and each position is the failing direction of the one before:
  #   CHMOD_RAN first — a slow but SUCCESSFUL run must pass, never skip. It is a sufficient
  #                     witness of execution on its own (the marker is echoed upstream of the
  #                     download block), so this rung holds even if marker detection breaks.
  #   FIXTURE:        — the capture server failing to bind is deterministic and actionable, so
  #                     it must FAIL rather than be absorbed into the environment bucket. It is
  #                     above the marker rung because the marker sits BELOW the :8099 guard in
  #                     drive.sh, so a fixture defect also presents as marker-absent.
  #   harness defect  — rc 0 with no marker: the container reported success and left no
  #                     evidence. A missing measurement is a harness bug, never an environment
  #                     skip; skipping here would relocate #7291 rather than close it.
  #   marker absent   — only past all three is absence evidence that the driver never ran.
  #   else            — the driver DID run: both assertions are live and meaningful.
  #
  # WHY `FIXTURE:` SITS WHERE IT DOES — CORRECTED AT REVIEW, because the reason first given here
  # was false and contradicted the note 25 lines above. That draft said a capture-server failure
  # "that still exits 0" would satisfy the harness rung. It cannot: drive.sh's :8099 guard ends in
  # `exit 2`, it fires before that script arms its EXIT trap, and the container runs it as the
  # final command under `set -e`, so `FIXTURE:` present implies rc == 2 — measured. The harness
  # rung's rc-class test and the fixture rung are therefore mutually exclusive, and their relative
  # order is cosmetic. Asserting otherwise was the same inherited-claim defect this branch exists
  # to remove, written into the justification for the change that removes it.
  #
  # THE REAL CONSTRAINT IS THAT `FIXTURE:` MUST SIT ABOVE `did-not-run`, and that one is load
  # bearing. The marker is emitted BELOW the :8099 guard, so a fixture defect presents as
  # marker-absent with rc 2. Put the fixture rung any lower and that run satisfies `did-not-run`
  # exactly — a deterministic, actionable bind failure absorbed into the environment bucket and
  # reported as a green declared skip. That is the outcome the whole arm is built to prevent.
  #
  # The `rc == 0` conjunct on the harness rung stays load-bearing and the claim is deliberately
  # NOT unconditional: a degraded container legitimately exits non-zero AND prints no marker —
  # measured, rc=100 with an empty capture — and firing there regardless of rc would convert
  # that skip back into the false FAIL this arm exists to remove.
  #
  # THE MARKER PREDICATE IS ABSENCE, NOT FILE EMPTINESS. An emptiness test is one byte from
  # never firing: `2>&1` merges stderr into this capture, so rc 0 plus a single `WARNING: apt
  # does not have a stable CLI` line defeats it and the run falls through to a SKIP. Marker
  # absence subsumes emptiness (an empty file has no marker) and closes that hole.
  # `-qx` ON THE MARKER TOO, NOT ONLY ON CHMOD_RAN (review). These two reads were written with
  # different strictness four lines apart, and the loose one is the one that routes the verdict.
  # bash ECHOES the offending source line on an error, so a line like
  #   bash: /work/drive.sh: line 701: echo DRIVER_REACHED_DL: command not found
  # SATISFIES a bare `grep -q` (measured). Both marker rungs then fall through to `else ... =ran`
  # and the arm emits two fails saying "the driver RAN" about a driver that never reached the
  # block — the ADR-166/AP-021 misattribution this whole arm exists to prevent. `-qx` costs
  # nothing on the healthy path: the driver's `echo` produces a line that IS exactly the marker.
  #
  # THE RC CLASSES ARE AN ALLOWLIST, NOT "any non-zero" (review). The skip is justified by
  # ADR-188 for ONE thing: a precondition nobody owns — the apt archive's state at that instant.
  # Reading every non-zero rc as that decline hands the skip bucket every HARNESS defect too: a
  # mistyped `-v` source makes docker exit 125 with no marker, which is a bug in this file, and
  # it would have gone green-with-a-NOTE forever. The measured classes are enumerated ONCE in
  # _T5M_ENV_RCS and both the routing and the offered classification read that list, so they
  # cannot drift apart. Anything outside it with no marker is a harness defect and reds.
  if grep -qx 'CHMOD_RAN' "$TMP/out/stdout" 2>/dev/null; then _t5m_state=ran
  elif grep -q "$_T5_FIXTURE_MARKER" "$TMP/out/stdout" 2>/dev/null; then _t5m_state=fixture-defect
  elif ! grep -qx "$_T5_MARKER" "$TMP/out/stdout" 2>/dev/null \
       && ! printf '%s\n' $_T5M_ENV_RCS | grep -qx "$_t5m_rc"; then
    _t5m_state=harness-defect
  elif ! grep -qx "$_T5_MARKER" "$TMP/out/stdout" 2>/dev/null; then _t5m_state=did-not-run
  else _t5m_state=ran
  fi

  # EXACTLY TWO COUNTED OUTCOMES ON EVERY VERDICT ROUTE — i.e. on each of the four `case` arms
  # below. NOT on "every route": the `did not land` pre-branch at the `diff -q` above contributes
  # ONE and sits outside this invariant (pre-existing, identical on origin/main; itemised at the
  # floor). This heading said "EVERY ROUTE" until review — the same universal the floor stanza
  # and ADR-188 had already retracted, left standing at the third of three sites.
  # The arm asserts a PREMISE (the wrong digest was
  # rejected, #7565) and a RESULT (the chain then reached a succeeding chmod). Both are made, or
  # both are declared-skipped, or both are reported not-demonstrated — never a mix, because a
  # route contributing a different number is indistinguishable at the floor from an arm that
  # partly vanished. The two `fail`s on the defect routes are deliberately not collapsed into
  # one: two assertions went unmade, and saying so once would under-count by exactly one.
  case "$_t5m_state" in
    did-not-run)
      # 2: the premise and the result, neither of which the taken branch got to make.
      arm_skip "T5 MUTATION did not run: the driver never reached the download block, so this arm demonstrated neither that the wrong digest was rejected nor that CHMOD_RAN is reachable. ${_t5m_rc_note}; T5 primary reached the driver: ${_t5_primary_reached}; tail: ${_t5m_tail:-<empty: the container suppresses apt output, so a pre-driver failure leaves no capture — see the deferred /out/setup.log item>}" 2
      ;;
    harness-defect)
      fail "T5 MUTATION: docker exited 0 but the driver's execution marker never printed — harness defect, not an environment skip; the checksum-rejection premise is undemonstrated" \
           "docker rc=${_t5m_rc}; expected ${_T5_MARKER} in $TMP/out/stdout"
      fail "T5 MUTATION: the same harness defect leaves CHMOD_RAN's reachability undemonstrated" \
           "${_t5m_rc_note}; tail: ${_t5m_tail}"
      ;;
    fixture-defect)
      fail "T5 MUTATION: the capture server never bound :8099 — deterministic fixture defect, not an environment skip; the checksum-rejection premise is undemonstrated" \
           "${_t5m_rc_note}; tail: ${_t5m_tail}"
      fail "T5 MUTATION: the same fixture defect leaves CHMOD_RAN's reachability undemonstrated" \
           "${_t5m_rc_note}; tail: ${_t5m_tail}"
      ;;
    ran)
      # THE ARM'S OWN PREMISE, ASSERTED (#7565). Everything here is about a chain that CONTINUED
      # past a REJECTED checksum, and the `sed -i` above is the only thing making the digest
      # wrong. If that sed ever no-ops the genuine checksum PASSES, the chain completes
      # legitimately, CHMOD_RAN prints, and the arm reports a cheerful pass having reproduced
      # nothing. Fail-open, and invisible. It is asserted only on this route because on the
      # others the download block was never reached, where its absence says nothing.
      if grep -qxF "${_DL_TARBALL}: FAILED" "$TMP/out/stdout" 2>/dev/null; then pass; else
        fail "T5 MUTATION: sha256sum's rejection verdict for ${_DL_TARBALL} is absent — this arm's premise (a wrong digest) did not hold, so its CHMOD_RAN result proves nothing" \
             "${_t5m_rc_note}; tail: ${_t5m_tail}"; fi
      # THE RESULT. `-x` (whole line), not a bare token: bash echoes the offending source line on
      # a syntax error and that line contains the marker, so a substring grep could pass with
      # chmod never having run. Reached only when the driver provably ran, so "vacuous" here
      # names a harness defect and not the environment — the misattribution #7291 removed.
      if grep -qx 'CHMOD_RAN' "$TMP/out/stdout" 2>/dev/null; then pass; else
        fail "T5 MUTATION: the driver RAN and without set -e the chain still did not reach a SUCCEEDING chmod — T5's absence check proves nothing" \
             "${_t5m_rc_note}; tail: ${_t5m_tail}"; fi
      ;;
  esac
fi

# ── T17 — a HEALTHY run emits ZERO fatals ──────────────────────────────────────────
# The rc-guard's whole purpose. Without `rc=$?; [ "$rc" -eq 0 ] && exit 0`, `trap … EXIT`
# fires on a SUCCESSFUL exit too and every healthy boot emits level=fatal, inverting the
# channel into noise on day one. Replace the block with a trivially-succeeding one so the
# driver exits 0 through the same armed trap.
printf 'true\n' > "$TMP/doppler-dl.sh.healthy"
cp "$TMP/doppler-dl.sh" "$TMP/doppler-dl.sh.orig"
cp "$TMP/doppler-dl.sh.healthy" "$TMP/doppler-dl.sh"
run_case "T17 healthy run exits 0" "" 0
if [ -s "$CAPTURE" ]; then
  fail "T17: a healthy run emitted $(wc -l < "$CAPTURE") event(s) — the rc guard is not holding" "$(head -2 "$CAPTURE")"
else pass; fi
cp "$TMP/doppler-dl.sh.orig" "$TMP/doppler-dl.sh"

# MUTATION: remove the rc guard and prove T17's assertion can FAIL. Without this arm, an
# emitter that never fires would also produce an empty capture and read as a clean pass.
rm -rf "$TMP/out"; mkdir -p "$TMP/out"; : > "$TMP/out/capture.log"
sed 's#^\s*\[ "\$rc" -eq 0 \] && exit 0$#  true#' "$TMP/drive.sh" > "$TMP/drive.noguard.sh"
cp "$TMP/doppler-dl.sh.healthy" "$TMP/dl.case.sh"
docker run --rm \
  -v "$TMP/dl.case.sh:/work/doppler-dl.sh:ro" \
  -v "$TMP/git-data-emit:/work/git-data-emit-src:ro" \
  -v "$TMP/capture.py:/work/capture.py:ro" \
  -v "$TMP/drive.noguard.sh:/work/drive.sh:ro" \
  -v "$TMP/out:/out" \
  ubuntu:24.04 bash -c '
    set -e
    cp /work/git-data-emit-src /work/git-data-emit
    apt-get update -qq >/dev/null 2>&1 && apt-get install -y -qq curl python3 >/dev/null 2>&1
    bash /work/drive.sh
  ' >/dev/null 2>&1 || true
if [ -s "$TMP/out/capture.log" ]; then pass; else
  fail "T17 MUTATION: removing the rc guard did NOT make a healthy run emit — the check is vacuous"; fi

# ── S1 — the sshd_config stage must SURVIVE a fresh 24.04 boot ─────────────────────
#
# (#7025) THIS ARM EXISTS BECAUSE THE STAGE DID NOT SURVIVE ONE. `sshd -t` validates the
# privilege-separation directory as well as the config text, and ubuntu-24.04 ships ssh
# socket-activated: /run/sshd is created by ssh.service's `RuntimeDirectory=sshd`, which has
# not run at runcmd time. So `sshd -t` exited 255 "Missing privilege separation directory:
# /run/sshd" on every fresh boot, the stage took its fatal branch, and cloud-init aborted
# BEFORE LUKS — a host that answers nothing, on a route whose whole purpose is to catch that.
# Measured on rehearsal hosts -rehearsal-30560266736 and -30581408745; found only because the
# emitter ships `sshd -t`'s stderr and Sentry kept it.
#
# EVERY STATIC GUARD PASSED THE BROKEN VERSION, and would still: the template was well-formed,
# the drop-in was valid, the branch logic was right. The missing precondition is only visible
# when the stage RUNS in the pinned image — which is what this file is for.
#
# The stage is run under `sh` with errexit OFF, matching the shipped chain: the template arms
# `set -e` in a LATER runcmd entry, and production evidence confirms it (the failing `sshd -t`
# was followed by `_sshd_t_rc=$?` and an emit, neither of which runs under errexit).
# S1's rc-class allowlist, enumerated ONCE so the routing and the offered classification
# cannot drift apart -- same construction as _T5M_ENV_RCS. A bare string, not an array, so it
# stays safe under this file's `set -u` when word-split by `printf '%s\n' $_S1_ENV_RCS`.
# 125: docker CLI / image pull. 100: apt under the container's outer `set -e`.
_S1_ENV_RCS='100 125'

# The IN-CONTAINER execution marker. Its whole job is to distinguish "the stage ran and
# exited N" from "nothing ran, so there is no N". It is emitted by the driver AFTER the
# container has reached the point where the stage is about to run, so its absence is
# positive evidence of a pre-stage failure rather than an inference from an empty capture.
_S1_MARKER='S1_DRIVER_REACHED_STAGE'
# The FIXTURE marker, emitted before anything environmental can fail. Its presence means the
# mount worked and the driver started, so a later failure is deterministic -- a defect in
# THIS file -- and must not be laundered into an environment decline.
_S1_FIXTURE_MARKER='S1_FIXTURE_OK'

# THE FOUR-RUNG LADDER, PORTED FROM T5. Pure over its four inputs so the negative controls
# below can drive every rung without docker.
#   $1 container rc   $2 marker seen (yes|no)   $3 fixture marker seen (yes|no)
#   $4 primary reached (yes|no, carried into the skip message only)
#
# ORDER IS LOAD-BEARING AND IS NOT ALPHABETICAL. The fixture rung MUST sit above
# `did-not-run`: docker exits 125 for BOTH a failed image pull (environment) and a bad `-v`
# source (this file's bug), so with the fixture rung any lower a mount typo lands on
# `did-not-run` and reports a green skip forever.
_s1_classify() {
  if [ "$2" = yes ]; then printf 'ran'; return 0; fi
  if [ "$3" = yes ]; then printf 'fixture-defect'; return 0; fi
  if ! printf '%s\n' $_S1_ENV_RCS | grep -qx "$1"; then printf 'harness-defect'; return 0; fi
  printf 'did-not-run'
}

# SNAPSHOT THE GLOBAL COUNTERS AROUND THE ARM so S1's own invariant can be checked without
# re-deriving it from the whole suite. Taken BEFORE the arm, and read by an assertion placed
# after it, so the check does not perturb its own input.
_S1_P0=$passes; _S1_F0=$fails; _S1_S0=$SKIPPED_ASSERTIONS
if [ -s "$TMP/sshd-stage.sh" ] && [ -s "$TMP/01-hardening.conf" ]; then
  cat > "$TMP/sshd-drive.sh" <<'S1DRV'
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null 2>&1
apt-get install -y -qq openssh-server >/dev/null 2>&1
mkdir -p /etc/ssh/sshd_config.d
cp /work/01-hardening.conf /etc/ssh/sshd_config.d/01-hardening.conf
# Stub the emitter: D1/T5/T17 already cover the real one end-to-end. What S1 needs is a
# record of WHICH stage/level fired and the detail file it shipped.
cat > /usr/local/bin/git-data-emit <<'EMIT'
#!/bin/sh
printf '%s|%s|%s\n' "$1" "$2" "$3" >> /out/sshd-capture.log
if [ -n "$4" ] && [ -r "$4" ]; then sed 's/^/detail: /' "$4" >> /out/sshd-capture.log; fi
exit 0
EMIT
chmod +x /usr/local/bin/git-data-emit
# Stub systemctl on /usr/local/bin (ahead of /usr/bin on Ubuntu's default PATH) — the stage
# calls it bare. There is no init in a container; the restart's tolerance is not what S1 tests.
printf '#!/bin/sh\nexit 0\n' > /usr/local/bin/systemctl
chmod +x /usr/local/bin/systemctl
# The fixture marker goes FIRST -- before apt, before anything environmental can fail --
# so its presence proves the mount worked and the driver started.
echo "S1_FIXTURE_OK"
set +e
# The execution marker sits immediately above the stage invocation. Absence of this line is
# positive evidence that nothing reached the stage, which is what STAGE_RC alone could never
# distinguish from "the stage ran and exited".
echo "S1_DRIVER_REACHED_STAGE"
sh /work/sshd-stage.sh
echo "STAGE_RC=$?"
S1DRV

  _s1_run() { # $1 = stage script to mount
    rm -rf "$TMP/s1out"; mkdir -p "$TMP/s1out"; : > "$TMP/s1out/sshd-capture.log"
    docker run --rm \
      -v "$1:/work/sshd-stage.sh:ro" \
      -v "$TMP/01-hardening.conf:/work/01-hardening.conf:ro" \
      -v "$TMP/sshd-drive.sh:/work/sshd-drive.sh:ro" \
      -v "$TMP/s1out:/out" \
      ubuntu:24.04 bash /work/sshd-drive.sh >"$TMP/s1out/stdout" 2>&1
    S1_DOCKER_RC=$?
    S1_RC="$(sed -n 's/^STAGE_RC=//p' "$TMP/s1out/stdout" | tail -1)"
    S1_CAP="$TMP/s1out/sshd-capture.log"
    # `-qx` ON BOTH READS. bash ECHOES the offending source line on an error, so a line like
    #   bash: /work/sshd-drive.sh: line 9: echo S1_DRIVER_REACHED_STAGE: command not found
    # SATISFIES a bare `grep -q` and would route a driver that never reached the stage
    # straight to `ran` -- the misattribution this arm exists to remove. On the healthy path
    # the driver's `echo` produces a line that IS exactly the marker, so `-x` costs nothing.
    S1_MARKER_SEEN=no
    grep -qx "$_S1_MARKER" "$TMP/s1out/stdout" 2>/dev/null && S1_MARKER_SEEN=yes
    S1_FIXTURE_SEEN=no
    grep -qx "$_S1_FIXTURE_MARKER" "$TMP/s1out/stdout" 2>/dev/null && S1_FIXTURE_SEEN=yes
    S1_STATE="$(_s1_classify "$S1_DOCKER_RC" "$S1_MARKER_SEEN" "$S1_FIXTURE_SEEN" "$S1_MARKER_SEEN")"
    S1_NOTE="docker rc=${S1_DOCKER_RC} (measured classes: 125 docker CLI/image pull, 100 apt under the container's outer set -e — offered as classification, not asserted as cause); stage rc=${S1_RC:-<no marker>}; execution marker seen: ${S1_MARKER_SEEN}; fixture marker seen: ${S1_FIXTURE_SEEN}; tail: $(tail -3 "$TMP/s1out/stdout" 2>/dev/null | tr '\n' ' ')"
  }

  # ERREXIT ORDERING IS S1's LOAD-BEARING PRECONDITION, so assert it rather than assume it.
  # S1 models the stage as a CHILD `sh`, which gets errexit OFF for free. That is faithful only
  # while the chain arms `set -e` AFTER this stage. If a later edit moved the arming earlier,
  # production would abort at `sshd -t` BEFORE `_sshd_t_rc=$?` — the stage would never emit its
  # own fatal — while S1 kept modelling the old world and stayed green through the divergence.
  _s1_stage_ln=$(grep -n '^[[:space:]]*STAGE=sshd_config[[:space:]]*$' "$TMP/runcmd-all.sh" | head -1 | cut -d: -f1)
  _s1_sete_ln=$(grep -n '^[[:space:]]*set -e[[:space:]]*$' "$TMP/runcmd-all.sh" | head -1 | cut -d: -f1)
  if [ -n "$_s1_stage_ln" ] && [ -n "$_s1_sete_ln" ] && [ "$_s1_stage_ln" -lt "$_s1_sete_ln" ]; then pass; else
    fail "S1: the shipped chain arms 'set -e' at or before the sshd stage (stage=${_s1_stage_ln:-?}, set -e=${_s1_sete_ln:-?})" \
         "S1's child-sh model runs with errexit OFF and now tests the opposite of what ships."; fi

  # STRUCTURAL GUARD ON THE MOUNTED ARTIFACT, not on this file's variables. Both markers are
  # hand-copied literals: the driver heredoc emits them and the reads above match them. A
  # reword on either side silently makes S1_MARKER_SEEN=no forever, which routes every run to
  # `did-not-run` and converts the whole arm into a permanent green skip -- the exact
  # unpinned-replicated-literal failure T5 spends a hundred lines closing for its own marker.
  # Assert against the file that is actually mounted, so the check cannot pass on a variable
  # the container never sees.
  # SUBSTRING HERE, WHOLE-LINE THERE, and the difference is not an inconsistency. In the
  # mounted DRIVER the marker sits inside `echo "S1_DRIVER_REACHED_STAGE"`, so a whole-line
  # match cannot see it; in the container's STDOUT the echo produces a line that IS exactly
  # the marker, so `-qx` is correct there and is what stops bash's own error echo
  # ("... echo S1_DRIVER_REACHED_STAGE: command not found") from satisfying the read. The
  # first draft used `-qx` in both places and this guard failed against a driver that carried
  # both markers.
  if grep -qF "$_S1_MARKER" "$TMP/sshd-drive.sh" && grep -qF "$_S1_FIXTURE_MARKER" "$TMP/sshd-drive.sh"; then
    pass
  else
    fail "S1: an execution marker is absent from the mounted driver (marker=$(grep -cF "$_S1_MARKER" "$TMP/sshd-drive.sh" 2>/dev/null || true), fixture=$(grep -cF "$_S1_FIXTURE_MARKER" "$TMP/sshd-drive.sh" 2>/dev/null || true))" \
         "The classifier's rungs are then unreachable and every run reports a green skip."; fi

  # ── S1 CLASSIFIER NEGATIVE CONTROLS (#7572) ──────────────────────────────────────
  #
  # THE DEFECT THESE EXIST TO CLOSE. S1_RC is read out of the container's stdout with
  # `sed -n 's/^STAGE_RC=//p' | tail -1`. When the container never ran at all -- image pull
  # failed, apt-get died, docker exited 125 -- there is no marker, S1_RC is empty, and
  # `${S1_RC:-none}` becomes the string "none". "none" is not "0", so the healthy assert
  # fails with "the sshd_config stage exited <no marker> on a fresh 24.04 -- this is the boot
  # abort", and "none" is not "1", so the mutation assert fails with "without the mkdir the
  # stage exited <no marker>, expected 1". Both messages name a CAUSE THAT NEVER OCCURRED:
  # the stage did not exit anything, because it never started. That is the ADR-166/AP-021
  # misattribution T5's four-rung ladder already exists to prevent, one arm over.
  #
  # The ladder is ported here as a PURE FUNCTION so its rungs can be driven directly, without
  # docker and without a container. Mirrors R3(2c)'s in-file negative-control shape: an
  # assertion nobody has ever seen fail is not evidence.
  #
  # THE RC CLASSES ARE AN ALLOWLIST, NOT "any non-zero" -- the same reasoning as _T5M_ENV_RCS.
  # Reading every non-zero rc as an environment decline hands the skip bucket every HARNESS
  # defect too: a mistyped `-v` source makes docker exit 125 with no marker, which is a bug in
  # this file, and it would go green-with-a-NOTE forever.
  _s1c() { _s1_classify "$1" "$2" "$3" "$4"; }

  # rung 1 -- the execution marker is present: the stage RAN, whatever else is true.
  if [ "$(_s1c 1 yes no yes)" = "ran" ]; then pass; else
    fail "S1 CLASSIFIER rung 1: marker present must classify as 'ran', got '$(_s1c 1 yes no yes)'" \
         "Without this rung a healthy mutation run (rc=1, marker present) is reclassified as a skip."; fi

  # rung 2 -- the fixture marker outranks the rc classes. A deterministic bind failure must
  # not be laundered into an environment skip.
  if [ "$(_s1c 125 no yes no)" = "fixture-defect" ]; then pass; else
    fail "S1 CLASSIFIER rung 2: fixture marker must outrank the rc allowlist, got '$(_s1c 125 no yes no)'" \
         "125 is in the env allowlist; if the fixture rung sits below it, a mount typo in THIS file reports as an environment decline forever."; fi

  # rung 3 -- no marker and an rc OUTSIDE the allowlist is a defect in this file, not the
  # environment. This is the rung that keeps the skip bucket honest.
  if [ "$(_s1c 7 no no yes)" = "harness-defect" ]; then pass; else
    fail "S1 CLASSIFIER rung 3: rc outside _S1_ENV_RCS with no marker must be 'harness-defect', got '$(_s1c 7 no no yes)'" \
         "Reading every non-zero rc as an environment decline hands the skip bucket every harness defect too."; fi

  # rung 4 -- no marker and an rc INSIDE the allowlist is the genuine environment decline
  # ADR-188 accepts. This is the ONLY route to a skip.
  if [ "$(_s1c 100 no no no)" = "did-not-run" ]; then pass; else
    fail "S1 CLASSIFIER rung 4: rc inside _S1_ENV_RCS with no marker must be 'did-not-run', got '$(_s1c 100 no no no)'" \
         "This is the only rung ADR-188 justifies a skip on; if it does not fire, the accepted decline reds instead."; fi

  _s1_run "$TMP/sshd-stage.sh"
  # THE HEALTHY RUN'S TWO ASSERTIONS ARE BOTH CONTAINER-DEPENDENT, so they are made together,
  # declared-skipped together, or reported not-demonstrated together -- never a mix. A route
  # contributing a different number is indistinguishable at the floor from an arm that partly
  # vanished. (The errexit-ordering assertion above is container-INDEPENDENT and stays
  # unconditional; so does the mutation-landed check below.)
  case "$S1_STATE" in
    did-not-run)
      # 2: the stage's own exit status, and the emptiness of its capture.
      arm_skip "S1 healthy run did not run: the container never reached the stage, so this arm demonstrated neither that the sshd_config stage survives a fresh 24.04 nor that a healthy stage emits nothing. ${S1_NOTE}" 2
      ;;
    harness-defect)
      fail "S1: docker exited ${S1_DOCKER_RC} with no execution marker and an rc outside _S1_ENV_RCS — harness defect, not an environment skip; the fresh-boot survival premise is undemonstrated" \
           "${S1_NOTE}"
      fail "S1: the same harness defect leaves the healthy-stage-emits-nothing property undemonstrated" \
           "${S1_NOTE}"
      ;;
    fixture-defect)
      fail "S1: the fixture marker printed but the stage was never reached — a deterministic defect in this file, not an environment decline" \
           "${S1_NOTE}"
      fail "S1: the same fixture defect leaves the healthy-stage-emits-nothing property undemonstrated" \
           "${S1_NOTE}"
      ;;
    *)
      if [ "${S1_RC:-none}" = "0" ]; then pass; else
        fail "S1: the sshd_config stage exited ${S1_RC:-<no marker>} on a fresh 24.04 — this is the boot abort" \
             "$(tail -5 "$TMP/s1out/stdout" 2>/dev/null)"; fi
  # EMPTY, not "no fatal". A substring test for `|sshd_config|fatal` is satisfied by the 126/127
  # branch, which emits `sshd_config_warn`/`warning`, forces `_sshd_t_rc=0` and exits 0 — so a
  # container where /usr/sbin/sshd was missing entirely would pass both asserts while the fix
  # under test was never exercised. Measured: a healthy stage emits ZERO bytes (the systemctl
  # stub keeps the restart quiet), so `-s` is strictly stronger and cannot flake. It is also
  # what makes the systemctl stub load-bearing rather than decorative.
      if [ -s "$S1_CAP" ]; then
        fail "S1: a healthy sshd stage emitted $(wc -l < "$S1_CAP") event(s) — a warn here means sshd -t did not actually run (126/127 branch), so the privsep fix was never exercised" \
             "$(head -3 "$S1_CAP" 2>/dev/null)"
      else pass; fi
      ;;
  esac

  # MUTATION — strip the WHOLE privsep preamble so the mutant is the pre-fix stage, and prove
  # S1 reproduces the MEASURED production failure rather than merely "some" failure. Leaving
  # the chmod behind would still fail, but on a `chmod: cannot access` the real boot never had.
  sed -e '/^[[:space:]]*mkdir -p \/run\/sshd[[:space:]]*$/d' \
      -e '/^[[:space:]]*chmod 0755 \/run\/sshd[[:space:]]*$/d' \
      "$TMP/sshd-stage.sh" > "$TMP/sshd-stage.nomkdir.sh"
  # Assert WHAT CHANGED, not merely that something did: an inequality would also be satisfied
  # by a sed that deleted some other line.
  _s1_before=$(grep -c 'mkdir -p /run/sshd' "$TMP/sshd-stage.sh" || true)
  _s1_after=$(grep -c 'mkdir -p /run/sshd' "$TMP/sshd-stage.nomkdir.sh" || true)
  if [ "$_s1_before" != "1" ] || [ "$_s1_after" != "0" ]; then
    fail "S1 MUTATION did not land: 'mkdir -p /run/sshd' count went ${_s1_before} -> ${_s1_after}, expected 1 -> 0" \
         "The fix this arm guards is absent or unrecognised — S1's green above certifies nothing."
    fail "S1 MUTATION: skipped (mutation did not land)"
    fail "S1 MUTATION: skipped (mutation did not land)"
    fail "S1 MUTATION: skipped (mutation did not land)"
  else
    pass
    _s1_run "$TMP/sshd-stage.nomkdir.sh"
    # THE THREE MUTATION ASSERTIONS ARE ALL CONTAINER-DEPENDENT. Before this routing, a
    # container that never ran made S1_RC empty and the third assertion reported
    # "S1 is no longer reproducing the measured failure" -- a statement about the MUTATION,
    # asserted from a run in which no mutation was ever executed. That message is #7572's
    # title, and it is the reason the routing exists: the arm was naming a cause it had not
    # measured. NOTE the deliberate asymmetry with the did-not-land branch above, which
    # already emits three substitute fails of its own -- adding an arm_skip there too would
    # double-count and put the arm at 10 rather than 7.
    case "$S1_STATE" in
      did-not-run)
        # 3: the mutant's exit status, the fatal it should have emitted, and the privsep
        # string that ties this arm to the measured production failure.
        arm_skip "S1 MUTATION did not run: the container never reached the stage, so this arm demonstrated neither that the missing mkdir aborts the stage nor that it reproduces the measured privsep failure. ${S1_NOTE}" 3
        ;;
      harness-defect)
        fail "S1 MUTATION: docker exited ${S1_DOCKER_RC} with no execution marker and an rc outside _S1_ENV_RCS — harness defect, not an environment skip" \
             "${S1_NOTE}"
        fail "S1 MUTATION: the same harness defect leaves the sshd_config fatal undemonstrated" "${S1_NOTE}"
        fail "S1 MUTATION: the same harness defect leaves the privsep reproduction undemonstrated" "${S1_NOTE}"
        ;;
      fixture-defect)
        fail "S1 MUTATION: the fixture marker printed but the stage was never reached — a deterministic defect in this file" \
             "${S1_NOTE}"
        fail "S1 MUTATION: the same fixture defect leaves the sshd_config fatal undemonstrated" "${S1_NOTE}"
        fail "S1 MUTATION: the same fixture defect leaves the privsep reproduction undemonstrated" "${S1_NOTE}"
        ;;
      *)
        if [ "${S1_RC:-none}" = "1" ]; then pass; else
          fail "S1 MUTATION: without the mkdir the stage exited ${S1_RC:-<no marker>}, expected 1" \
               "$(tail -5 "$TMP/s1out/stdout" 2>/dev/null)"; fi
        if grep -q '|sshd_config|fatal' "$S1_CAP" 2>/dev/null; then pass; else
          fail "S1 MUTATION: no sshd_config fatal was emitted" "$(head -3 "$S1_CAP" 2>/dev/null)"; fi
        # The exact string from the rehearsal hosts. Pinning it — rather than "any failure" —
        # is what keeps this arm tied to the defect instead of to sshd being unhappy generally.
        if grep -q 'Missing privilege separation directory' "$S1_CAP" 2>/dev/null; then pass; else
          fail "S1 MUTATION: the captured stderr does not name the privsep directory — S1 is no longer reproducing the measured failure" \
               "$(head -5 "$S1_CAP" 2>/dev/null)"; fi
        ;;
    esac
  fi
else
  # TWELVE, matching S1's assertion count on every other path, so a failed extraction cannot
  # satisfy the anti-vacuity floor by emitting fewer. Was SEVEN; #7572 adds the structural
  # marker guard (1) and the four classifier rung controls (4), both container-INDEPENDENT,
  # so every path grows by five. Re-derived from the success path rather than incremented by
  # memory: 1 errexit + 1 structural + 4 controls + 2 healthy + 1 mutation-landed + 3 mutation.
  fail "S1: could not extract the sshd stage and/or the hardening drop-in from the render"
  fail "S1: skipped (extraction failed)"; fail "S1: skipped (extraction failed)"
  fail "S1: skipped (extraction failed)"; fail "S1: skipped (extraction failed)"
  fail "S1: skipped (extraction failed)"; fail "S1: skipped (extraction failed)"
  fail "S1: skipped (extraction failed)"; fail "S1: skipped (extraction failed)"
  fail "S1: skipped (extraction failed)"; fail "S1: skipped (extraction failed)"
  fail "S1: skipped (extraction failed)"
fi

# S1's OWN INVARIANT, not the suite's. Twelve assertions are made, declared-skipped, or
# reported not-demonstrated on EVERY route through the arm -- healthy, mutation-did-not-land,
# each defect rung, and extraction-failed. A route contributing a different number is
# indistinguishable at the suite floor from an arm that partly vanished, which is exactly the
# hole the classifier would otherwise open: routing assertions into arm_skip moves them out
# of `passes` without moving them out of the total.
_S1_TOTAL=$(( (passes - _S1_P0) + (fails - _S1_F0) + (SKIPPED_ASSERTIONS - _S1_S0) ))
if [ "$_S1_TOTAL" -eq 12 ]; then pass; else
  fail "S1: the arm contributed ${_S1_TOTAL} assertion(s), expected exactly 12 on every route" \
       "A route contributing a different number is indistinguishable at the floor from an arm that partly vanished."; fi

# AND AN S1-SPECIFIC SKIP BOUND. The suite-wide ceiling cannot tell whose skips they are, so
# S1 declaring five (2 healthy + 3 mutation) would silently consume T5's budget too. Bound
# S1's own contribution here: 5 is its maximum -- both container-dependent groups skipping at
# once -- and anything above it means a route is declaring cost it does not have.
_S1_SKIPPED=$(( SKIPPED_ASSERTIONS - _S1_S0 ))
if [ "$_S1_SKIPPED" -le 5 ]; then pass; else
  fail "S1: declared ${_S1_SKIPPED} skipped assertion(s), S1's own ceiling is 5 (2 healthy + 3 mutation)" \
       "A single arm cannot exceed the cost of its own container-dependent groups."; fi

# ══ #7204 — R1 / R3 / R4: the birth filesystem, and the diagnostic that named it ══
#
# WHY THESE ARMS DO NOT MOUNT ANYTHING. #7204 was a mount that failed with ESRCH because
# the birth `mkfs` set the ext4 `quota` feature and the target image has no `quota_v2`
# module to satisfy it. The obvious guard — "mkfs it and mount it in the test" — CANNOT
# go red for that reason, and this is measured, not assumed: a four-arm privileged probe
# (loop file -> luksFormat -> luksOpen -> mkfs -> mount) run 2026-08-03 on kernel
# 7.0.0-28-generic mounted ALL FOUR arms rc=0, including the unfixed `-O quota,project`.
# A container shares the host kernel, so on any runner whose kernel provides `quota_v2`
# the defective filesystem mounts perfectly. Worse, `request_module` reaches the loader via
# `call_usermodehelper`, which runs in the INIT NAMESPACE — so a container-side
# /etc/modprobe.d blacklist is never consulted and cannot simulate the target either.
# Simulating this needs a VM, not a container.
#
# So R1 asserts the PROPERTY THAT MADE THE BOOT FAIL — the created superblock's feature
# set — not the failure itself. That is kernel-independent by construction.
#
# ANYONE PROPOSING "just mount it and see" SHOULD BE SHOWN THE PARAGRAPH ABOVE.
#
# R2 (a real mount) is DELIBERATELY ABSENT. Disposition taken in this PR's Phase 0.7:
# this harness runs plain `docker run --rm` — 6 SOURCE SITES, 8 RUNTIME INVOCATIONS (the two
# wrappers are each called twice: `run_case` for T5-primary and T17, `_s1_run` for S1's two
# arms). Say WHICH measure: the drift here was never a miscount, it was two measures sharing
# one number. "four" was stale; a first correction said "eight" citing `grep -c 'docker run
# --rm'`, which is a THIRD quantity — unanchored hit count, including prose — that happened to
# read 8 before the correction and 9 after, because the correction added two matching comment
# lines to the file it was counting. Derivations, both self-excluding:
#   sites   -> grep -cE '^[[:space:]]*docker run --rm'                     (6)
#   runtime -> sites, +1 per extra call of run_case / _s1_run              (8)
# None of the three is load-bearing: what carries R2's absence is the zero-privileged-flags
# clause below, which is a property of the SITES and is verified. This harness contains zero
# --privileged/--cap-add/--device, so `mount(2)` fails EPERM on the fixed AND the unfixed
# template — an arm that is green on neither, proving nothing about either. Promoting this
# rung to privileged would be an architectural change to the rung-1/rung-2 taxonomy that
# this file's own header declares, and rung 2 already mounts a real mapper on a real host.
# Do not add a mount arm here without revisiting that taxonomy first.

_r1_fix="$DIR/git-data-birth-fs-fingerprint.txt"
if [ -s "$TMP/luks-stage.sh" ] && [ -s "$_r1_fix" ]; then
  # Extract the mkfs invocation FROM THE RENDER (D5). Device path -> __DEV__ so the arms
  # can retarget it at a regular file. `assert len(...) == 1` mirrors every other
  # extraction here: a stage whose mkfs moved or duplicated must fail loudly.
  _r1_extract_rc=0
  python3 - "$TMP/luks-stage.sh" "$TMP" <<'PY' || _r1_extract_rc=$?
import re, sys
src = open(sys.argv[1]).read(); out = sys.argv[2]
lines = [l for l in src.splitlines() if re.match(r'^\s*mkfs\.ext4\b', l)]
assert len(lines) == 1, f"expected exactly 1 mkfs.ext4 invocation in the luks stage, found {len(lines)}"
cmd = lines[0].strip()
# Strip any trailing REDIRECT before touching the device operand. The shipped line ends in
# `2>>"$GIT_DATA_LUKS_DETAIL"` (the #7204 stderr capture), and that variable is unset in this
# harness — so treating it as the device produced a command that silently created no
# filesystem at all, and R1 reported "NOFEATURES" as though the template were broken.
# A guard, not a strip-and-hope: the device operand must still look like a path afterwards.
cmd = re.sub(r'\s+\d*>>?\s*\S+\s*$', '', cmd).strip()
assert re.search(r'/\S+$', cmd), f"mkfs line has no path-shaped device operand after stripping redirects: {cmd!r}"
# Replace the trailing device operand with a placeholder the container retargets.
cmd = re.sub(r'\S+$', '__DEV__', cmd)
open(f"{out}/r1-mkfs-shipped.txt", "w").write(cmd + "\n")
PY
  if [ "$_r1_extract_rc" -eq 0 ] && [ -s "$TMP/r1-mkfs-shipped.txt" ]; then pass; else
    fail "R1: could not extract exactly one mkfs.ext4 invocation from the rendered luks_open stage" \
         "A rename such as mkfs.ext4 -> mke2fs -t ext4 would red B16 while R1 silently failed to extract."; fi

  if [ "$_r1_extract_rc" -eq 0 ] && [ -s "$TMP/r1-mkfs-shipped.txt" ]; then
    _r1_shipped="$(cat "$TMP/r1-mkfs-shipped.txt")"
    # MUTANT: re-introduce the `quota` feature. Candidate-dependent by construction — if the
    # shipped line carries no -O at all, inject one. Asserted to have LANDED before it is
    # used, so a no-op sed reports "the mutation did not land" rather than the far more
    # misleading "the fingerprint held on the mutant" (the S1/T5 misattribution class).
    if printf '%s' "$_r1_shipped" | grep -qE -- '-O '; then
      _r1_mutant="$(printf '%s' "$_r1_shipped" | sed -E 's/-O ([^ ]+)/-O quota,\1/')"
    else
      _r1_mutant="$(printf '%s' "$_r1_shipped" | sed -E 's/^([[:space:]]*mkfs\.ext4)/\1 -O quota/')"
    fi
    _r1_mut_has_quota=$(printf '%s' "$_r1_mutant" | grep -cE -- '-O [^ ]*quota' || true)
    if [ "$_r1_mutant" != "$_r1_shipped" ] && [ "$_r1_mut_has_quota" -ge 1 ]; then pass; else
      fail "R1 MUTATION did not land: injecting 'quota' left the line unchanged or without a quota feature" \
           "shipped=[$_r1_shipped] mutant=[$_r1_mutant] — R1's green below would certify nothing."; fi

    # SECOND negative control (D7): the literal that shipped before #7204, executed directly.
    # Independent of the sed above, so a mutation that silently changes meaning still leaves
    # one control that reproduces the real defect.
    _r1_prefix='mkfs.ext4 -q -O quota,project __DEV__  # what shipped before #7204'
    # THIRD control, for R1(a) specifically. Both controls above inject `quota`, which IS in
    # the allowlist — so they exercise (b) and leave (a) with no demonstrated failing
    # direction at all. `casefold` is a real ext4 feature deliberately absent from the table,
    # so it must trip "unclassified". Without this, (a)'s "fail-closed against any FUTURE
    # flag" framing is aspirational rather than tested.
    _r1_unclass='mkfs.ext4 -q -O casefold __DEV__'

    printf '%s\n' "$_r1_shipped" > "$TMP/r1-arm-shipped.txt"
    printf '%s\n' "$_r1_mutant"  > "$TMP/r1-arm-mutant.txt"
    printf '%s\n' "$_r1_prefix"  > "$TMP/r1-arm-prefix.txt"
    printf '%s\n' "$_r1_unclass" > "$TMP/r1-arm-unclass.txt"

    cat > "$TMP/r1-drive.sh" <<'R1DRV'
set -e
# NO apt HERE, DELIBERATELY (#7535). ubuntu:24.04 already ships e2fsprogs at
# Priority: required — `docker run --rm ubuntu:24.04 dpkg -s e2fsprogs` reports
# 1.47.0-2.4~exp1ubuntu4.1 — so the `apt-get update && apt-get install e2fsprogs`
# this replaced installed a package that was already present, at the cost of a full
# apt cycle against an external mirror. Do not restore it.
#
# What changed is the BINDING, not the value. The install ran AFTER `apt-get update`,
# so it resolved against the LIVE archive and COULD serve a build the image layer does
# not carry; R1's mke2fs now comes from the image layer instead — mirror-current
# narrowed to image-current. Measured 2026-08-13: the archive candidate was identical
# to the image at 1.47.0-2.4~exp1ubuntu4.1 (`apt-get install -s` reported 0 upgraded),
# so today the value is the same either way — only the binding moved.
#
# That is the faithful direction because the e2fsprogs whose output the fingerprint
# must PREDICT is the cloud image's own (git-data-birth-fs-fingerprint.txt, "WHY AN
# ALLOWLIST AND NOT SET-EQUALITY"). The fingerprint asserts nothing about e2fsprogs
# versions — that block is marked CONTEXT FOR FAILURE MESSAGES ONLY — not asserted;
# its subject is the birth filesystem's mount-time module dependency.
#
# This does NOT make R1 bump-immune. The allowlist is FAIL-CLOSED: a bump emitting only
# already-classified features (orphan_file, metadata_csum_seed — both pre-classified
# in-tree) stays green, but a bump emitting a NOVEL feature still reds R1(a) as
# unclassified, by design. The remedy there is a one-line classification with a
# rationale, never a wholesale fixture refresh.
for arm in shipped mutant prefix unclass; do
  img="/tmp/$arm.img"
  # 10G sparse. Measured: a backing file under ~3MB falls into mke2fs's `floppy` bucket and
  # silently drops has_journal, which would make R1's non-vacuity probe fail for a reason
  # that has nothing to do with the template. 100M and 10G are identical; 10G also matches
  # var.git_data_luks_volume_size.
  truncate -s 10G "$img"
  # -F inserted immediately after the binary (never appended after the device operand,
  # where mke2fs would read it as a blocks-count).
  cmd="$(sed -e "s#__DEV__#$img#" -e 's#^\([[:space:]]*mkfs\.ext4\)#\1 -F#' "/work/r1-arm-$arm.txt")"
  sh -c "$cmd" >/dev/null 2>&1 || true
  feats="$(dumpe2fs -h "$img" 2>/dev/null | sed -n 's/^Filesystem features:[[:space:]]*//p')"
  printf 'ARM=%s FEATURES=%s\n' "$arm" "$feats" >> /out/r1-features.txt
done
R1DRV

    rm -rf "$TMP/r1out"; mkdir -p "$TMP/r1out"; : > "$TMP/r1out/r1-features.txt"
    docker run --rm \
      -v "$TMP/r1-arm-shipped.txt:/work/r1-arm-shipped.txt:ro" \
      -v "$TMP/r1-arm-mutant.txt:/work/r1-arm-mutant.txt:ro" \
      -v "$TMP/r1-arm-prefix.txt:/work/r1-arm-prefix.txt:ro" \
      -v "$TMP/r1-arm-unclass.txt:/work/r1-arm-unclass.txt:ro" \
      -v "$TMP/r1-drive.sh:/work/r1-drive.sh:ro" \
      -v "$TMP/r1out:/out" \
      ubuntu:24.04 bash /work/r1-drive.sh >"$TMP/r1out/stdout" 2>&1 || true

    # Classify every arm against the committed allowlist. Three assertions with three
    # DISTINCT messages (D1): unclassified-feature, module-dep-present, non-vacuity.
    _r1_verdict="$(python3 - "$_r1_fix" "$TMP/r1out/r1-features.txt" <<'PY' 2>/dev/null || true
import sys
tbl = {}
for ln in open(sys.argv[1]):
    ln = ln.rstrip("\n")
    if not ln.strip() or ln.lstrip().startswith("#"):
        continue
    parts = ln.split("\t")
    if len(parts) >= 2:
        tbl[parts[0].strip()] = parts[1].strip()
arms = {}
for ln in open(sys.argv[2]):
    if ln.startswith("ARM="):
        head, _, feats = ln.strip().partition(" FEATURES=")
        arms[head[4:]] = feats.split()
def verdict(name):
    f = arms.get(name)
    if not f:
        return f"{name}:NOFEATURES"
    unclassified = [x for x in f if x not in tbl]
    moduledep = [x for x in f if tbl.get(x) == "module-dep"]
    return "%s:unclassified=%s:moduledep=%s:hasjournal=%s" % (
        name, ",".join(unclassified) or "-", ",".join(moduledep) or "-",
        "yes" if "has_journal" in f else "no")
print(" ".join(verdict(a) for a in ("shipped", "mutant", "prefix", "unclass")))
PY
)"
    _r1_ship="$(printf '%s' "$_r1_verdict" | tr ' ' '\n' | grep '^shipped:' || true)"
    _r1_mut="$(printf '%s' "$_r1_verdict"  | tr ' ' '\n' | grep '^mutant:'  || true)"
    _r1_pre="$(printf '%s' "$_r1_verdict"  | tr ' ' '\n' | grep '^prefix:'  || true)"
    _r1_unc="$(printf '%s' "$_r1_verdict"  | tr ' ' '\n' | grep '^unclass:' || true)"

    # (a) fail-closed against any FUTURE flag, not just the one that bit us.
    case "$_r1_ship" in
      *:unclassified=-:*) pass ;;
      # NOFEATURES FIRST, for the same reason the three controls below do it (see the
      # note above them): without it, an arm that produced NO FILESYSTEM AT ALL falls to
      # `*)` and prints the allowlist message with the raw token interpolated — blaming
      # the template for what is an environmental fault (mke2fs absent from the image).
      *NOFEATURES*|"") fail "R1(a): the shipped arm produced no filesystem — R1 makes NO claim about the template here (is mke2fs present in the image?)" \
               "$(tail -5 "$TMP/r1out/stdout" 2>/dev/null)" ;;
      *) fail "R1(a): the birth filesystem carries feature(s) absent from the allowlist: ${_r1_ship#*unclassified=}" \
              "Classify each in $_r1_fix with its mount-time class before shipping. Do NOT 'refresh' the fixture wholesale — the point is the classification, not the diff. (mke2fs measured 1.47.0 in ubuntu:24.04 / 1.47.2 on the authoring host.)" ;;
    esac
    # (b) THE invariant, stated directly.
    case "$_r1_ship" in
      *:moduledep=-:*) pass ;;
      # NOFEATURES FIRST — same reason as (a), and it matters more here: the `*)` message
      # below is the #7204 boots-dark claim, so an absent mke2fs would otherwise be
      # reported as a template regression that never happened.
      *NOFEATURES*|"") fail "R1(b): the shipped arm produced no filesystem — R1 makes NO claim about the template here (is mke2fs present in the image?)" \
               "$(tail -5 "$TMP/r1out/stdout" 2>/dev/null)" ;;
      *) fail "R1(b): the birth filesystem carries a module-dep feature: ${_r1_ship##*moduledep=}" \
              "This is the #7204 defect class: mounting it makes ext4 request a kernel module the target image does not ship, so the host boots dark with mount(8) rc=32. See $_r1_fix." ;;
    esac
    # (c) non-vacuity: also catches an accidentally-tiny backing file.
    case "$_r1_ship" in
      *:hasjournal=yes) pass ;;
      *) fail "R1(c): has_journal absent from the shipped arm — the probe is vacuous" \
              "Either mkfs did not run, or the backing file fell into mke2fs's floppy bucket (<~3MB). verdict=[$_r1_ship]" ;;
    esac
    # NEGATIVE CONTROL 1 — the in-test mutant MUST be rejected.
    # NOFEATURES is checked FIRST and explicitly: the pattern below does not match it, so an
    # arm that produced NO FILESYSTEM AT ALL used to fall through to `*) pass`. Both negative
    # controls were therefore fail-open — if a future e2fsprogs rejects `-O quota`, the
    # "committed pre-fix literal" silently stops reproducing the defect and reports green.
    case "$_r1_mut" in
      *NOFEATURES*|"") fail "R1 MUTATION: the mutant arm produced no filesystem (verdict=[$_r1_mut])" \
              "The control is vacuous — it cannot demonstrate R1 rejects a quota-bearing superblock. Check the container's mkfs accepted the injected flag." ;;
      *:moduledep=-:*) fail "R1 MUTATION: injecting 'quota' did NOT trip the module-dep assertion" \
              "R1 cannot detect the very defect it exists for. verdict=[$_r1_mut]" ;;
      *) pass ;;
    esac
    # NEGATIVE CONTROL 2 — the committed pre-fix literal MUST be rejected.
    case "$_r1_pre" in
      *NOFEATURES*|"") fail "R1 PRE-FIX CONTROL: the pre-fix arm produced no filesystem (verdict=[$_r1_pre])" \
              "The committed pre-#7204 literal no longer reproduces the defect — it is certifying nothing." ;;
      *:moduledep=-:*) fail "R1 PRE-FIX CONTROL: the literal that shipped before #7204 did NOT trip the module-dep assertion" \
              "verdict=[$_r1_pre]. This control is independent of the sed mutation precisely so a mutation that silently changed meaning still leaves one arm reproducing the real defect." ;;
      *) pass ;;
    esac
    # UNCLASSIFIED CONTROL — the failing direction for R1(a). `casefold` is a real ext4
    # feature that is deliberately not in the allowlist, so (a) must reject it. This is the
    # only arm that demonstrates the fail-closed-against-future-flags property; the other two
    # inject `quota`, which is IN the table and therefore exercises (b), not (a).
    case "$_r1_unc" in
      *NOFEATURES*|"") fail "R1 UNCLASSIFIED CONTROL: the arm produced no filesystem (verdict=[$_r1_unc])" \
              "mke2fs may have rejected -O casefold in this image. Pick another feature that is real, producible, and absent from $_r1_fix — the control must be able to run." ;;
      *:unclassified=-:*) fail "R1 UNCLASSIFIED CONTROL: an off-allowlist feature did NOT trip R1(a)" \
              "verdict=[$_r1_unc]. R1(a) has no demonstrated failing direction, so its 'fail-closed against any FUTURE flag' claim is untested." ;;
      *) pass ;;
    esac
  else
    # Identical cardinality to the success path (D9) minus the extraction assert already
    # emitted above, so a drifted extraction cannot satisfy the anti-vacuity floor by
    # emitting fewer assertions and burying the real cause.
    fail "R1: skipped (mkfs extraction failed)"; fail "R1: skipped (mkfs extraction failed)"
    fail "R1: skipped (mkfs extraction failed)"; fail "R1: skipped (mkfs extraction failed)"
    fail "R1: skipped (mkfs extraction failed)"; fail "R1: skipped (mkfs extraction failed)"
  fi
else
  fail "R1: could not extract the luks_open stage from the render, or the fingerprint fixture is missing ($_r1_fix)"
  fail "R1: skipped (precondition missing)"; fail "R1: skipped (precondition missing)"
  fail "R1: skipped (precondition missing)"; fail "R1: skipped (precondition missing)"
  fail "R1: skipped (precondition missing)"; fail "R1: skipped (precondition missing)"
fi

# R1-EXPIRY — its OWN labelled arm, deliberately OUT of R1's pass/fail path (D8). A CI
# failure triggered by a wall-clock date is unrepeatable and its message says nothing about
# the filesystem; worse, a stale date can mask or merge with real feature drift. The
# remediation is tied to the birth, not to an arbitrary +6 months: when the git-data host is
# actually born, re-measure the sibling baseline against the REAL image's e2fsprogs instead
# of the inferred one, then move the date.
_r1_exp="$(sed -n 's/^# expires_on:[[:space:]]*//p' "$_r1_fix" 2>/dev/null | head -1)"
if [ -n "$_r1_exp" ] && [ "$(date -u +%Y-%m-%d)" \< "$_r1_exp" ]; then pass; else
  fail "R1-EXPIRY: the birth-fs fingerprint's provenance is stale (expires_on=${_r1_exp:-<unparseable>})" \
       "Re-measure the sibling baseline (cloud-init-registry.yml / workspaces-cutover.sh mkfs) against the image's own e2fsprogs and move the date. This does not gate R1's feature assertions."; fi

# ── R3 — the detail SOURCE is a readable file, not a literal path ───────────────────
#
# NOT "the failure is diagnosable" — that name over-claimed. What this arm can observe in an
# unprivileged container is narrower and worth stating: `dmesg` is EPERM-blocked here and
# /var/log/cloud-init-output.log does not exist, so the "carries dmesg context" property is a
# DOCUMENTED LIMITATION of this rung, not an assertion. Rung 2 covers it.
#
# The defect being guarded: the emitter branches
#   [ -n "$DETAIL_SRC" ] && [ -r "$DETAIL_SRC" ]  ->  tail the file
#   else                                          ->  _san "$DETAIL_SRC"
# so a NON-EMPTY but UNREADABLE detail source ships THE LITERAL PATH STRING as the
# diagnostic. Measured on the shipped emitter 2026-08-03:
#   _san('/var/log/cloud-init-output.log') -> '/var/log/cloud-init-output.log'
# That is what #7204's fatal actually carried.
# EVERY PREDICATE BELOW READS luks-stage.code.sh (COMMENTS STRIPPED), NOT luks-stage.sh.
# Reading the raw stage is what made the original R3(1)/(2) satisfiable by this PR's own
# prose: measured, a seed relocated BELOW every early append with a comment left behind
# ("# the stage seeds GIT_DATA_LUKS_DETAIL=… before the appends") produced seed=22,
# first-append=55, PASS — with all four early failure modes appending to an unset variable.
# Combined with the same class in R3(3b), the full suite reported 33/0 while the
# boot-critical property was violated.
#
# _r3_ln() also fails LOUD on a missing anchor rather than returning empty, because an empty
# line number silently degrades every comparison below into "skip the check".
_r3_ln() { grep -n "$1" "$TMP/luks-stage.code.sh" 2>/dev/null | head -1 | cut -d: -f1; }

# THE THREE R3 PREDICATES, SINGLE-SOURCED (#7613). Each is used by the production arm AND by
# its negative control below, so the control cannot certify a spelling the arm no longer uses
# -- the hand-copied-fourth-spelling failure this file's B1 comment already warns about, one
# level down. Changing a value here moves the arm and its control together, which is what
# makes the control's RED and GREEN mean anything.
#
# _R3_SEED_PAT is DELIBERATELY the unanchored form at the commit that introduces these
# controls, so their failure is the defect rather than a bug in the fixtures.
# ANCHORED (#7613 finding 1). Was `GIT_DATA_LUKS_DETAIL=`, unanchored, fed to a `head -1`
# over a corpus that still carried trailing comments -- so a comment naming the token above
# the real seed hijacked the line number and R3(1)/(2)/(2b) all reported the seed early while
# it sat after the trap. Its own twin _r2d_ordered has been anchored since it was written; the
# .code.sh split landed and this anchor did not. Now the same shape as the twin.
_R3_SEED_PAT='^[[:space:]]*GIT_DATA_LUKS_DETAIL='
# The guard-shape predicate R3(3b)(ii) uses, exported into the python heredoc rather than
# restated there.
_R3_GUARD_PAT='\[\s+-[rs]\s+"?'
# R3(2d)'s seed anchor. It is ALREADY anchored -- this arm is the reference the other seven
# are being moved to -- so single-sourcing it does not change its value. What it buys is that
# a future de-anchoring reds R3(2d)'s own control instead of silently widening the model.
_R3_R2D_PAT='^[[:space:]]*GIT_DATA_RUNCMD_DETAIL='

# R3(3b)(i)'s reporting-site predicate. RED VALUE: a bare count floor, which is what ships
# today. The property is a SET -- delete one reporting site, add an unrelated one, and the
# count is unchanged while the property is violated. Sub-assertion (iv) already does message-
# set equality for fatals and is the model this is being moved to.
_R3B_EXPECTED_SITES='gitdata_doppler_dl
gc_timer
luks_open
provision
sshd_config
volume_mount'
_r3b_sites_ok() {  # $1 = newline-separated site names; 0 = accept, 1 = reject
  # A SET, NOT A FLOOR (#7613 finding 3). Was `count >= 6`, which holds across the exact
  # mutation that matters: delete one reporting site, add an unrelated one, and the count is
  # unchanged while the property is violated. Sub-assertion (iv) already does message-set
  # equality for fatals and is the model followed here.
  [ "$(printf '%s\n' "$1" | grep -c . || true)" -ge 6 ] || return 1
  [ "$(printf '%s\n' "$1" | sort -u)" = "$(printf '%s\n' "$_R3B_EXPECTED_SITES" | sort -u)" ]
}

if [ -s "$TMP/luks-stage.code.sh" ]; then
  # (1) the stage passes a seeded detail file, not the cloud-init log, to the emitter.
  _r3_seed_ln=$(_r3_ln "$_R3_SEED_PAT")
  _r3_trap_ln=$(_r3_ln '^[[:space:]]*trap luks_err EXIT')
  if [ -n "$_r3_seed_ln" ]; then pass; else
    fail "R3(1): the luks_open stage does not seed a detail file (no GIT_DATA_LUKS_DETAIL= assignment in CODE)" \
         "Without it luks_err falls through to _san and emits the literal path string as the diagnostic."; fi
  # (2) ORDERING, not co-presence (L1). The seed must PRECEDE the first append and the trap.
  # A grep proving both lines exist is exactly the failure mode of
  # knowledge-base/project/learnings/2026-07-26-an-existence-assertion-that-ran-before-the-file-existed-bricked-every-boot.md
  # — assertions sat ~120 lines above the heredocs creating the files they asserted on, and
  # the harness could not see it because it extracts bodies and runs them in isolation.
  _r3_first_append=$(_r3_ln '2>>"\?\$GIT_DATA_LUKS_DETAIL')
  if [ -n "$_r3_seed_ln" ] && [ -n "$_r3_first_append" ] && [ "$_r3_seed_ln" -lt "$_r3_first_append" ]; then pass; else
    fail "R3(2): the detail-file seed does not precede the first append (seed=${_r3_seed_ln:-none} first-append=${_r3_first_append:-none})" \
         "Co-presence is not ordering. A seed placed after an append leaves the trap's detail source unreadable on exactly the early failures it exists to explain."; fi
  # (2b) The seed must ALSO precede the TRAP. A seed between the trap and the first append
  # passes (2) while being strictly worse than #7204: under `set -u` any failure in that
  # window makes luks_err abort on an unbound $GIT_DATA_LUKS_DETAIL BEFORE reaching
  # git-data-emit, so the host dies with NO fatal at all rather than a causeless one.
  if [ -n "$_r3_seed_ln" ] && [ -n "$_r3_trap_ln" ] && [ "$_r3_seed_ln" -lt "$_r3_trap_ln" ]; then pass; else
    fail "R3(2b): the detail-file seed does not precede 'trap luks_err EXIT' (seed=${_r3_seed_ln:-none} trap=${_r3_trap_ln:-none})" \
         "A seed after the trap makes the handler abort on an unbound variable under set -u — the stage then emits NOTHING, which is worse than the causeless fatal this arm exists to prevent."; fi
  # (2c) NEGATIVE CONTROL for the whole R3(2) family — the arm that was missing, and whose
  # absence is why the comment-satisfaction defect survived. Relocate the seed below the
  # first append IN A COPY and assert the ordering check flips. Without this, R3(2) is an
  # assertion nobody has ever seen fail.
  _r3_mut="$TMP/luks-stage.mut.sh"
  sed -e 's|^\([[:space:]]*\)GIT_DATA_LUKS_DETAIL=\(.*\)$|\1: # seed relocated by R3(2c)|' \
    "$TMP/luks-stage.code.sh" > "$_r3_mut"
  printf 'GIT_DATA_LUKS_DETAIL=/run/git-data-luks-stage.log\n' >> "$_r3_mut"
  _mut_seed=$(grep -n "$_R3_SEED_PAT" "$_r3_mut" | head -1 | cut -d: -f1)
  _mut_app=$(grep -n '2>>"\?\$GIT_DATA_LUKS_DETAIL' "$_r3_mut" | head -1 | cut -d: -f1)
  if [ -n "$_mut_seed" ] && [ -n "$_mut_app" ] && [ "$_mut_seed" -gt "$_mut_app" ]; then pass; else
    fail "R3(2c) MUTATION did not land: relocated seed=${_mut_seed:-none} first-append=${_mut_app:-none}, expected seed AFTER append" \
         "R3(2)'s green above certifies nothing — the ordering check has no demonstrated failing direction."; fi
else
  # Cardinality parity with the success path (4), so a failed extraction cannot satisfy the floor.
  fail "R3: skipped (luks stage not extracted)"; fail "R3: skipped (luks stage not extracted)"
  fail "R3: skipped (luks stage not extracted)"; fail "R3: skipped (luks stage not extracted)"
fi

# ── R3 PER-ARM COMMENT-SATISFACTION CONTROLS (#7613) ────────────────────────────────
#
# THE MECHANISM, MEASURED. The `.code.sh` corpora are stripped of WHOLE-LINE comments only
# (`^\s*#` at the two extraction sites; the template's own strip is the same shape). So every
# "a comment cannot satisfy this predicate" argument resting on `.code.sh` is narrower than
# stated, and the shape is live rather than theoretical: the render carries
# `STAGE=volume_mount # (#6982) name the stage …` today.
#
# WHY EIGHT CONTROLS AND NOT ONE. The predicates are shared, so one fix re-flows every
# consumer at once -- which is precisely why a single control would be the wrong evidence.
# Each arm has its own hijackable token and its own failing direction, and an arm that is
# ALREADY anchored must be shown to STAY correct rather than assumed to. The budget is paid
# per arm: one negative control each, over four fixtures plus two variants.
#
# EVERY CONTROL DRIVES THE PRODUCTION PREDICATE, not a restatement of it. They read
# `$_R3_SEED_PAT` / `$_R3_GUARD_PAT` -- the same variables the arms read -- so changing a
# predicate moves the arm and its control together. A control that hard-coded its own spelling
# could certify an anchoring the arms no longer use, which is the hand-copied-fourth-spelling
# failure this file already warns about one level up.
#
# They are pure text over files in $TMP; no container.
_r3c_dir="$TMP/r3controls"; mkdir -p "$_r3c_dir"
_r3_ln_in() { grep -n "$2" "$1" 2>/dev/null | head -1 | cut -d: -f1; }

# ── GUARD 5 — the tail strip's live assertions and its _b2_strip parity check ────────
#
# THIS CHANGE IS PROPHYLACTIC, AND SAYING SO IS THE POINT. Re-measured against a fresh render
# on 2026-08-20: the luks stage goes 55 -> 55 lines with ZERO surviving `#`, and the runcmd
# concatenation 170 -> 170 with exactly ONE -- `STAGE=volume_mount # (#6982) …`, whose token
# `volume_mount` is matched by no predicate in this file. So the tail strip changes one line
# in one artifact and NO arm's verdict. It is retained because the property it buys -- a
# predicate cannot be satisfied by the commentary explaining it -- should not depend on the
# render's own strip continuing to be exhaustive. It is not retained because it fixed
# something live, and the arms' RED/GREEN above is paid on the ANCHORING, which does re-flow
# all eight.
#
# THE `+` PREFIX IS LOAD-BEARING. The suite already contains a stripper -- `_b2_strip`,
# `sed -e 's/[[:space:]]*#.*$//'` -- and #7613's issue body proposed it as the ready-made fix.
# Its zero-width `*` destroys `${var#pat}` -> `${var`, `$#` -> `$`, `#!/bin/sh` -> empty, and a
# URL fragment. Measured, not assumed: the divergence assertion below is that measurement.
_g5_dir="$TMP/g5"; mkdir -p "$_g5_dir"
_g5_new() { R3_TAIL_STRIP="$_R3_TAIL_STRIP" python3 -c '
import os, re, sys
tail = os.environ.get("R3_TAIL_STRIP", "")
tre = re.compile(tail) if tail else None
out = []
for l in open(sys.argv[1]).read().splitlines():
    if re.match(r"^\s*#", l):
        continue
    if tre is not None:
        l = tre.sub("", l)
    out.append(l)
# TRAILING NEWLINE, deliberately. `sed` terminates its last line and `"\n".join()` does not,
# so without this `diff -q` reports a mismatch on two byte-identical corpora — which is
# exactly what the first run of Guard 5(a) did.
sys.stdout.write("\n".join(out) + "\n")
' "$1"; }

# (5a) PARITY ON THE REAL CORPUS. After the strip, B2's `_b2_strip` route and R3's route are
# the same bytes -- which means B2 is now a REDUNDANT-IMPLEMENTATION CROSS-CHECK rather than
# independent evidence, and this file says so rather than claiming a control it no longer has.
# The parity is what makes that statement checkable.
if [ -s "$TMP/runcmd-all.sh" ]; then
  _g5_new "$TMP/runcmd-all.sh" > "$_g5_dir/new.txt" 2>/dev/null
  _b2_strip "$TMP/runcmd-all.sh" > "$_g5_dir/b2.txt" 2>/dev/null
  if diff -q "$_g5_dir/new.txt" "$_g5_dir/b2.txt" >/dev/null 2>&1; then pass; else
    fail "GUARD 5(a): the tail strip and _b2_strip disagree on the real runcmd concatenation — B2's corpus and R3's are no longer the same bytes, so B2's cross-check is measuring a different file" \
         "$(diff "$_g5_dir/b2.txt" "$_g5_dir/new.txt" 2>/dev/null | head -6)"; fi
else
  fail "GUARD 5(a): runcmd-all.sh absent, parity unverifiable"
fi

# (5b) DIVERGENCE ON A SYNTHESIZED FIXTURE. Parity alone is satisfied by two strippers that
# are both wrong in the same way, and by two that are both no-ops. This is the arm that proves
# the new expression is strictly safer -- and it is a SYNTHESIZED fixture precisely because the
# real artifacts contain zero at-risk tokens, which is why (5a) can pass at all.
printf 'base=${path#/prefix/}\nargc=$#\nurl="https://e.com/#anchor"\nplain=1   # trailing\n' > "$_g5_dir/risk.sh"
_g5_new "$_g5_dir/risk.sh" > "$_g5_dir/risk.new" 2>/dev/null
_b2_strip "$_g5_dir/risk.sh" > "$_g5_dir/risk.b2" 2>/dev/null
_g5_keeps=$(grep -cE '\$\{path#/prefix/\}|argc=\$#|#anchor' "$_g5_dir/risk.new" 2>/dev/null || true)
_g5_b2_keeps=$(grep -cE '\$\{path#/prefix/\}|argc=\$#|#anchor' "$_g5_dir/risk.b2" 2>/dev/null || true)
if [ "$_g5_keeps" -eq 3 ] && [ "$_g5_b2_keeps" -eq 0 ]; then pass; else
  fail "GUARD 5(b): on the at-risk fixture the tail strip preserved ${_g5_keeps}/3 tokens and _b2_strip preserved ${_g5_b2_keeps}/3 (expected 3 and 0) — the two strippers no longer differ in the way that justifies not reusing _b2_strip" \
       "new=[$(tr '\n' ' ' < "$_g5_dir/risk.new")] b2=[$(tr '\n' ' ' < "$_g5_dir/risk.b2")]"; fi

# ── FIXTURE A — the real seed relocated BELOW the trap, with a trailing comment naming the
#    token left ABOVE it. Finding (1): with an unanchored `head -1` the comment hijacks the
#    line number and R3(1)/(2)/(2b) report the seed early when it is late.
_fxA="$_r3c_dir/A.code.sh"
if [ -s "$TMP/luks-stage.code.sh" ]; then
  # The seed is held out and re-emitted at END OF FILE, so it sits after BOTH the trap and
  # the first append — the two orderings R3(2b) and R3(2) respectively assert. The decoy
  # comment naming the token is left where the real seed used to be, above the trap, which is
  # what an unanchored `head -1` latches onto.
  awk '
    /^[[:space:]]*GIT_DATA_LUKS_DETAIL=/ && !moved {
      held = $0; moved = 1
      print "  : # seed for GIT_DATA_LUKS_DETAIL= is documented here"
      next
    }
    { print }
    END { if (moved) print held }
  ' "$TMP/luks-stage.code.sh" > "$_fxA"
else
  : > "$_fxA"
fi
_a_seed=$(_r3_ln_in "$_fxA" "$_R3_SEED_PAT")
_a_real=$(_r3_ln_in "$_fxA" '^[[:space:]]*GIT_DATA_LUKS_DETAIL=')
_a_trap=$(_r3_ln_in "$_fxA" '^[[:space:]]*trap luks_err EXIT')
_a_app=$(_r3_ln_in "$_fxA" '2>>"\?\$GIT_DATA_LUKS_DETAIL')

# A1 — R3(1): the ARM's seed lookup must resolve to the real seed, not to prose about it.
if [ -n "$_a_seed" ] && [ "$_a_seed" = "${_a_real:-}" ]; then pass; else
  fail "R3(1) CONTROL: the arm's seed predicate resolves to line ${_a_seed:-none}; the real seed is at line ${_a_real:-none} — a trailing comment naming the token has hijacked it" \
       "An unanchored head -1 over a whole-line-only-stripped corpus cannot tell the seed from prose about the seed."; fi

# A2 — R3(2): with the real seed below the first append, the ARM's ordering check must see
# the violation. It cannot while its own lookup is pointing at the comment.
if [ -n "$_a_seed" ] && [ -n "$_a_app" ] && [ "$_a_seed" -gt "$_a_app" ]; then pass; else
  fail "R3(2) CONTROL: seed=${_a_seed:-none} append=${_a_app:-none} — the ordering check does not report a seed that sits after the first append" \
       "R3(2)'s green certifies nothing if the mutated direction still reads as ordered."; fi

# A3 — R3(2b): same, against the trap.
if [ -n "$_a_seed" ] && [ -n "$_a_trap" ] && [ "$_a_seed" -gt "$_a_trap" ]; then pass; else
  fail "R3(2b) CONTROL: seed=${_a_seed:-none} trap=${_a_trap:-none} — the ordering check does not report a seed that sits after the trap" \
       "A seed after the trap makes luks_err abort on an unbound variable under set -u, so the stage emits NOTHING — strictly worse than the causeless fatal R3(2b) exists to prevent."; fi

# ── FIXTURE A' — R3(2c) is the R3(2) family's own negative control, so it must discriminate
#    on a corpus whose FIRST line is a decoy comment; otherwise it certifies either spelling.
_fxAp="$_r3c_dir/Aprime.code.sh"
{ printf 'x=1 # GIT_DATA_LUKS_DETAIL=/decoy\n'; cat "$_fxA" 2>/dev/null; } > "$_fxAp"
_ap_seed=$(_r3_ln_in "$_fxAp" "$_R3_SEED_PAT")
if [ "${_ap_seed:-0}" != "1" ]; then pass; else
  fail "R3(2c) CONTROL: the arm's predicate resolves to line 1, which is a decoy comment — R3(2c) would certify a spelling that reads prose" \
       "R3(2c) is the negative control for the whole R3(2) family; if it cannot tell code from commentary the family has no model."; fi

# ── FIXTURE B — a real `[ -s "$_luks_detail" ]` guard DELETED, a trailing comment naming it
#    left behind. Finding (2): a regex over the stripped corpus reports GUARDED from prose.
_fxB="$_r3c_dir/B.code.sh"
# NOTE THE `$`. The arm derives its search name as `arg4.strip('"'"'"'"'"')`, which KEEPS the
# leading dollar -- the name is `$_luks_detail`, not `_luks_detail`. The first draft of this
# control dropped it and therefore PASSED against the very defect it was written for: a
# fixture that cannot match real code cannot detect a predicate that matches prose.
printf 'git-data-emit stage level msg "$_luks_detail"   # guarded by [ -s "$_luks_detail" ] upstream\n' > "$_fxB"
# STRIP FIRST, THEN SEARCH -- which is what production does. Feeding gpat a RAW fixture would
# test gpat in isolation and could never be flipped by the stripper change that actually
# closes this. The control therefore runs the arm's own stripper over the fixture and then the
# arm's own guard predicate over the result.
_b_hits=$(R3_GUARD_PAT="$_R3_GUARD_PAT" R3_TAIL_STRIP="$_R3_TAIL_STRIP" python3 -c '
import os, re, sys
tail = os.environ.get("R3_TAIL_STRIP", "")
tre = re.compile(tail) if tail else None
out = []
for l in open(sys.argv[1]).read().splitlines():
    if re.match(r"^\s*#", l):
        continue
    if tre is not None:
        l = tre.sub("", l)
    out.append(l)
pat = re.compile(os.environ["R3_GUARD_PAT"] + re.escape("$_luks_detail"))
print(len(pat.findall("\n".join(out))))
' "$_fxB" 2>/dev/null || echo 0)
if [ "${_b_hits:-1}" = "0" ]; then pass; else
  fail "R3(3b)(ii) CONTROL: the arm's guard predicate found ${_b_hits} match(es) on a corpus whose ONLY occurrence of the guard shape is a trailing comment — deleting a real guard and leaving prose about it reports GUARDED" \
       "That reopens the literal-leak branch the guard exists to close."; fi

# ── FIXTURE B' — R3(3d): a trailing comment matching the deletion sed's shape must not be
#    what the mutation lands on, or the arm's cmp -s did-not-land guard never fires.
_fxBp="$_r3c_dir/Bprime.code.sh"
printf 'keep=1\nother=2   # [ -s "$_luks_detail" ] mentioned only in prose here\n' > "$_fxBp"
_bp_mut="$_r3c_dir/Bprime.mut.sh"
sed -e '/^[[:space:]]*[^#]*\[[[:space:]]\+-s[[:space:]]\+"\?\$\?_luks_detail/d' "$_fxBp" > "$_bp_mut"
if cmp -s "$_fxBp" "$_bp_mut"; then pass; else
  fail "R3(3d) CONTROL: the deletion sed changed a corpus whose only mention of the guard is a trailing comment — the mutation landed on prose, so the did-not-land guard would not fire and the mutant would score as a real deletion" \
       "A mutation that lands on a comment measures nothing about the code."; fi

# ── FIXTURE C — one reporting site deleted and one unrelated site added. Finding (3): a
#    `>= 6` COUNT floor holds across that swap; the property is a SET.
_fxC_b="$_r3c_dir/C_before"; _fxC_a="$_r3c_dir/C_after"
printf 'luks_open\nvolume_mount\nsshd_config\ngitdata_doppler_dl\ngc_timer\nprovision\n' > "$_fxC_b"
printf 'luks_open\nvolume_mount\nsshd_config\ngitdata_doppler_dl\ngc_timer\nZZZ_unrelated\n' > "$_fxC_a"
# Drive the ARM's OWN predicate over both corpora. The complete set must be ACCEPTED and the
# swapped one REJECTED; a count floor accepts both, which is the defect.
_c_ok_before=1; _r3b_sites_ok "$(cat "$_fxC_b")" && _c_ok_before=0
_c_ok_after=1;  _r3b_sites_ok "$(cat "$_fxC_a")" && _c_ok_after=0
if [ "$_c_ok_before" -eq 0 ] && [ "$_c_ok_after" -ne 0 ]; then pass; else
  fail "R3(3b)(i) CONTROL: the arm's site predicate accepted the complete set (rc=${_c_ok_before}) and the swapped set (rc=${_c_ok_after}) alike — one reporting site was deleted and an unrelated one added, and it could not tell" \
       "A floor is not a set. Sub-assertion (iv) already does message-set equality for fatals and is the model this should follow."; fi

# ── FIXTURE D — R3(2d) is the CONTROL PROVING THE ANCHORING STYLE WORKS, so its RED is a
#    mutation of its own anchor and its behaviour must otherwise be unchanged.
_fxD="$_r3c_dir/D.code.sh"
printf 'noise=0 # GIT_DATA_RUNCMD_DETAIL=/decoy\nGIT_DATA_RUNCMD_DETAIL=/run/git-data-runcmd.log\n' > "$_fxD"
_d_anch=$(_r3_ln_in "$_fxD" "$_R3_R2D_PAT")
_d_bare=$(_r3_ln_in "$_fxD" 'GIT_DATA_RUNCMD_DETAIL=')
if [ "${_d_anch:-0}" = "2" ] && [ "${_d_bare:-0}" = "1" ]; then pass; else
  fail "R3(2d) CONTROL: anchored returned ${_d_anch:-none} (expected 2), bare returned ${_d_bare:-none} (expected 1) — the arm that demonstrates the anchoring style is not demonstrating it" \
       "R3(2d) is the reference the other seven arms are being moved to; if it stops discriminating the family loses its model."; fi

# ── R3(3) + R4 — drive the EXTRACTED emitter against the capture endpoint ────────────
#
# R4 is the arm that pins Phase 1's ordering decision. The emitter keeps
# `tail -n 20 "$DETAIL_SRC" | _devalue | _clean`, and `_clean` ENDS in `tail -c 180` — a
# DOUBLE truncation. Measured against the shipped _clean on 2026-08-03:
#   dmesg first, mount stderr last -> the 180-byte survivor ENDS with "No such process."
#   reversed (dmesg last)          -> the mount error is pushed out ENTIRELY
# Nothing pinned that before this arm. It is a one-character regression in the exact code
# path whose absence cost #7204 a hand-written Better Stack query to diagnose.
cat > "$TMP/r4-drive.sh" <<'R4DRV'
#!/bin/bash
set -uo pipefail
export DEBIAN_FRONTEND=noninteractive

# EVERY STEP THAT CAN LEAVE THE CAPTURE PATH DEAD NOW NAMES ITSELF.
#
# Six causes, each a distinct `FIXTURE-FAIL:` marker on stderr followed by a non-zero exit.
# Before this, `apt-get update` and `install` carried no rc check at all under a driver
# running `set -uo pipefail` with no `-e`, so a failed apt continued on to start a capture
# server with no python3 -- and the host discarded the container's rc with `|| true`. The
# three downstream arms then reported that the EMITTER had changed behaviour. It had not; the
# container had never run. That misattribution is #7501, and it cost ~4 hours and two
# confidently-wrong diagnoses in opposite directions.
#
# The marker is `FIXTURE-FAIL:` rather than the old `FIXTURE:` so it matches the nested
# runner's failure-marker regex; the bind marker below is RENAMED to match, which is why this
# is six causes and not five new ones.
fixture_fail() { echo "FIXTURE-FAIL: $1" >&2; exit 2; }

# NAMED FAULT INJECTION, so every Guard 2 mutation row costs one container run instead of a
# hand edit to this heredoc. A row that can only be executed by editing the file under test
# is a row that does not get executed.
INJECT="${GIT_DATA_REHEARSAL_INJECT:-}"

# rc0-dead-capture: exit ZERO having produced no captures at all — a container whose rc says
# "fine" while the capture path is dead, which is the shape that separates the two halves of
# the host-side gate (delete the sentinel check, keep the rc check, and only this class is
# still caught).
#
# An earlier comment here claimed this was the ONLY such shape because "every other injected
# fault also makes the container exit non-zero". That is false: `no-roundtrip` skips the whole
# round-trip block and `sentinel-in-capture-log` skips only the `touch`, and BOTH let the
# container run to completion and exit 0 with sentinel.ok absent — host-observably identical.
# Three of the eight injections produce this verdict shape, not one.
[ "$INJECT" = "rc0-dead-capture" ] && exit 0

# BOUNDED APT. `-o Acquire::Retries=3` covers transient mirror failures inside apt itself;
# the backoff loop covers the ones it does not retry. This does NOT add Ubuntu's mirrors to
# the merge gate -- they were already there, because a dead container yields 0 for all three
# arms and the suite already exited non-zero. What changes is that the failure now says so.
[ "$INJECT" = "apt-update" ] && fixture_fail "apt-get update (injected)"
apt-get update -qq -o Acquire::Retries=3 >/dev/null 2>&1 \
  || fixture_fail "apt-get update failed (mirror unreachable or index corrupt)"

_apt_ok=0
for _try in 1 2 3; do
  if [ "$INJECT" = "apt-install" ]; then break; fi
  if apt-get install -y -qq -o Acquire::Retries=3 curl python3 >/dev/null 2>&1; then
    _apt_ok=1
    [ "$_try" -gt 1 ] && echo "FIXTURE-RETRY: apt-get install succeeded on attempt ${_try}" >&2
    break
  fi
  sleep $(( _try * 2 ))
done
[ "$_apt_ok" -eq 1 ] || fixture_fail "apt-get install curl python3 failed past 3 attempts"

[ "$INJECT" = "no-python3" ] && fixture_fail "python3 absent after install (injected)"
command -v python3 >/dev/null 2>&1 || fixture_fail "python3 absent after a successful apt-get install"
[ "$INJECT" = "no-curl" ] && fixture_fail "curl absent after install (injected)"
command -v curl >/dev/null 2>&1 || fixture_fail "curl absent after a successful apt-get install"

python3 /work/capture.py &
# BOUNDED POLL, not a fixed `sleep 1`. Under CPU contention (several of these containers
# run concurrently on a dev box) python3 can miss a 1s window, curl gets connection-refused,
# capture.log stays empty, and R3(3a) fails -- which reads as a substantive finding about
# the emitter rather than as a starved fixture. Fail loud if it never comes up.
_PORT=8099
[ "$INJECT" = "no-bind" ] && _PORT=8098   # nothing binds here, so the poll must exhaust
for _i in $(seq 50); do (echo > /dev/tcp/127.0.0.1/$_PORT) 2>/dev/null && break; sleep 0.1; done
(echo > /dev/tcp/127.0.0.1/$_PORT) 2>/dev/null \
  || fixture_fail "capture server never bound :${_PORT}"

# THE BIND IS NOT THE ROUND TRIP. A bound socket proves python3 started listening; it does
# not prove a POST is accepted, written and flushed where the host can see it. The bind poll
# was already here and #7501 still happened, so the readiness proof is widened to cover the
# whole path the emitter actually uses.
#
# THE DURABLE ARTIFACT IS `/out/sentinel.ok`, NOT A LINE IN capture.log. The driver truncates
# /out/capture.log THREE times below -- once before each of the A/B/C orderings -- so a
# sentinel written there is wiped long before the host reads anything, and the gate would
# redden on every healthy run. Observe the round trip in capture.log (which happens first,
# and is fine), then touch a file nothing truncates.
if [ "$INJECT" != "no-roundtrip" ]; then
  : > /out/capture.log
  curl -sf --max-time 5 -X POST --data 'SOLEUR_RUNCMD_REHEARSAL_SENTINEL' \
    "http://127.0.0.1:8099/api/1/store/" >/dev/null 2>&1 || true
  _rt=0
  for _i in $(seq 50); do
    if grep -q 'SOLEUR_RUNCMD_REHEARSAL_SENTINEL' /out/capture.log 2>/dev/null; then _rt=1; break; fi
    sleep 0.1
  done
  [ "$_rt" -eq 1 ] || fixture_fail "capture round trip never observed (bound, but a POST never reached the log)"
fi

# THE EMITTER MUST BE INSTALLED BEFORE THE SENTINEL IS TOUCHED, and every step of installing it
# is rc-checked.
#
# This block used to sit BELOW the sentinel with all four steps unchecked. Under `set -uo
# pipefail` with no `-e`, with the three emit calls guarded by `|| true` and the driver's last
# command a `cp` that returns 0, a failure anywhere here yielded docker rc=0 AND sentinel.ok
# present -- so the host gate read the fixture as LIVE and all three arms made emitter-worded
# claims about a container that never had an emitter. That is exactly the #7501 misattribution,
# reachable as shipped, inside the fix for it. The six FIXTURE-FAIL causes covered apt, python3,
# curl, bind and the round trip; they did not cover emit-prep.
cp /work/git-data-emit-src /work/git-data-emit || fixture_fail "could not stage git-data-emit into the container"
sed -i "s#^DSN='.*'#DSN='https://k@127.0.0.1:8099/1'#" /work/git-data-emit \
  || fixture_fail "could not repoint the emitter DSN at the capture server"
python3 - <<'FIX' || fixture_fail "could not rewrite the emitter store URL to http"
p="/work/git-data-emit"; s=open(p).read()
old = '"https://${SHOST}/api/${PROJ}/store/"'
assert old in s, "store-URL anchor not found in git-data-emit"
s = s.replace(old, '"http://${SHOST}/api/${PROJ}/store/"')
open(p,"w").write(s)
FIX
chmod +x /work/git-data-emit || fixture_fail "could not make the staged emitter executable"
[ -x /work/git-data-emit ] || fixture_fail "the staged emitter is not executable after chmod"

# THE SENTINEL IS TOUCHED HERE, LAST — after the round trip is proven AND the emitter is
# installed. It is the host's single proof that this container run was fully live, so it must
# be the final thing that happens on the healthy path; anything it precedes is unproven.
#
# `sentinel-in-capture-log` is Guard 2 row 3: it reproduces the draft-1 shape where the
# sentinel was written into /out/capture.log instead of a durable artifact. The driver
# truncates capture.log three times below, so that shape must redden the host gate on an
# otherwise HEALTHY run.
if [ "$INJECT" != "sentinel-in-capture-log" ]; then
  touch /out/sentinel.ok || fixture_fail "could not create the durable /out/sentinel.ok artifact"
fi

MOUNTERR='mount: /mnt/git-data-luks: mount(2) system call failed: No such process.'
mk_dmesg() { i=1; while [ "$i" -le 20 ]; do echo "[   12.3456$i] EXT4-fs (dm-0): mounting with quota feature but no quota format module line $i"; i=$((i+1)); done; }

# ORDER A — the shipped ordering: dmesg first, failing stderr last.
{ mk_dmesg; printf '%s\n' "$MOUNTERR"; } > /tmp/detail-a.txt
: > /out/capture.log
/work/git-data-emit "probe A" luks_open fatal /tmp/detail-a.txt "rc=32" >/dev/null 2>&1 || true
cp /out/capture.log /out/capture-a.log

# ORDER B — the MUTATION: reversed, so dmesg is what survives the tail.
{ printf '%s\n' "$MOUNTERR"; mk_dmesg; } > /tmp/detail-b.txt
: > /out/capture.log
/work/git-data-emit "probe B" luks_open fatal /tmp/detail-b.txt "rc=32" >/dev/null 2>&1 || true
cp /out/capture.log /out/capture-b.log

# ORDER C — R3(3): non-empty but UNREADABLE detail source. An ABSENT $4 would fall to
# _san "" and pass vacuously; only a non-empty-unreadable path exercises the literal leak.
: > /out/capture.log
/work/git-data-emit "probe C" luks_open fatal /nonexistent/xyzzy "rc=32" >/dev/null 2>&1 || true
cp /out/capture.log /out/capture-c.log
R4DRV

rm -rf "$TMP/r4out"; mkdir -p "$TMP/r4out"; : > "$TMP/r4out/capture.log"
# THE CONTAINER'S VERDICT IS NO LONGER DISCARDED. This was `|| true`, which threw away the rc
# AND any reason to open the stdout file -- referenced only inside failure-message details,
# so nothing ever read it. Reproducing #7501 required patching the EXIT trap by hand.
_r4_rc=0
docker run --rm \
  -e "GIT_DATA_REHEARSAL_INJECT=${GIT_DATA_REHEARSAL_INJECT:-}" \
  -v "$TMP/git-data-emit:/work/git-data-emit-src:ro" \
  -v "$TMP/capture.py:/work/capture.py:ro" \
  -v "$TMP/r4-drive.sh:/work/r4-drive.sh:ro" \
  -v "$TMP/r4out:/out" \
  ubuntu:24.04 bash /work/r4-drive.sh >"$TMP/r4out/stdout" 2>&1 || _r4_rc=$?

_r4_a=$(grep -c 'No such process' "$TMP/r4out/capture-a.log" 2>/dev/null || true)
_r4_b=$(grep -c 'No such process' "$TMP/r4out/capture-b.log" 2>/dev/null || true)
_r3_c=$(grep -c 'xyzzy' "$TMP/r4out/capture-c.log" 2>/dev/null || true)

# ── R4/R3 RUN-LEVEL FIXTURE-LIVENESS GATE ─────────────────────────────────────────
#
# ONE gate, not three per-arm preconditions: there is one container and one capture path, so
# "the fixture was starved" is a RUN-level fact and three copies of it would be three places
# to drift.
#
# IT IS STRUCTURAL, NOT GREP-VERIFIED. An assembly grep counts call sites, so an arm routed
# AROUND the gate leaves the count unchanged and the check green -- cardinality standing in
# for discrimination. Here the gate REPORTS all three arms itself and skips past them on
# failure, so bypassing it is a deletion the assertion count does see.
#
# IT EMITS EXACTLY ONE ASSERTION ON EVERY PATH, and so does each arm below — see `_r4_arm`.
# PATH-INVARIANT CARDINALITY IS THE POINT, and getting it wrong was a live defect: the first
# shape of this gate emitted 1 `pass` when healthy and 3 `fail`s when starved, so a STARVED run
# totalled 44 against a floor of 45 and the suite's terminal line read
# `ran only 44 assertions (<45) — harness did not execute fully`, exiting before the summary.
# That message names a cause the run did not measure — the harness executed fully and the gate
# worked — which is the misattribution class this whole change exists to remove, reproduced by
# the instrument built to remove it. Four review agents converged on it independently.
#
# THERE IS DELIBERATELY NO NON-EMPTINESS CONJUNCT. An empty capture AFTER a proven round trip
# is a genuine emitter finding -- precisely the finding these arms exist to make -- so
# requiring non-emptiness here would suppress it. The gate proves the PATH was live; what came
# down it is the arms' business.
_r4_live=1
[ "$_r4_rc" -eq 0 ] || _r4_live=0
[ -f "$TMP/r4out/sentinel.ok" ] || _r4_live=0

# EVERY EMITTER-CLAIMING ARM ROUTES THROUGH THIS. A bare `if [ "$_r4_live" -eq 0 ]; then :`
# prefix repeated per arm is a convention, not a chokepoint: a fourth arm written without it
# bypasses the gate silently and nothing counts the omission. Routing through one helper makes
# the bypass a visible deviation from the block's only idiom, and keeps cardinality
# path-invariant for free.
# THE STARVED MESSAGE CARRIES A NEUTRAL ID, NEVER THE EMITTER-WORDED NAME.
#
# The arm names below are diagnoses ("the mount error did NOT survive the emitter's tail…",
# "the emitter no longer leaks a literal path…") and they are the right text for a REAL
# finding. Printing them on the starved path put that diagnosis first and the disclaimer
# second, so a reader scanning FAIL lines still saw an emitter accusation for a container that
# never ran — which is verbatim what #7501 reports as the misleading output. Measured by the
# Guard 2 matrix: rows 1, 2 and 3 all surfaced the correct cause AND still led with the
# emitter phrasing. Softening the accusation is not removing it.
#
#   $1 = 1 if the arm's own predicate held, else 0
#   $2 = short neutral id, used ONLY on the starved path
#   $3 = the emitter-worded arm name, used ONLY for a genuine finding
#   $4 = failure detail
_r4_arm() {
  if [ "$_r4_live" -eq 0 ]; then
    fail "$2: fixture starved — no claim made about the emitter" \
         "See the FIXTURE-FAIL lines above for the container's own cause."
    return 0
  fi
  if [ "$1" -eq 1 ]; then pass; else fail "$3" "$4"; fi
}

if [ "$_r4_live" -eq 0 ]; then
  # THE CONTAINER'S OWN STDOUT, ON ITS OWN COLUMN-0 LINES, EACH ONE ITS OWN MARKER MATCH.
  #
  # The prefix is `FIXTURE-FAIL: `, not `FIXTURE-FAIL| `, and that is a measured requirement
  # rather than a style choice. `run-registered-suites.sh` selects excerpt lines with
  #   MARKER_ERE='^[[:space:]]*(\[FAIL\]|[A-Z][A-Z0-9]*-FAIL|FAIL)([[:space:]:_-]|$)'
  # in which `|` is NOT a member of the trailing class, so `FIXTURE-FAIL| ` matches nothing.
  # Under the `| ` spelling only the three header lines below were selected and the tail
  # survived solely through the excerpt's `-A3` window — and because `fixture_fail` prints the
  # cause LAST and exits, the discriminating line was the first thing dropped on any run with
  # preceding output. That is the blind tail this design exists to remove.
  echo "FIXTURE-FAIL: the R4/R3 capture fixture was starved — the three arms below make NO claim about the emitter."
  echo "FIXTURE-FAIL: docker rc=${_r4_rc}; sentinel.ok $( [ -f "$TMP/r4out/sentinel.ok" ] && echo present || echo absent )"
  echo "FIXTURE-FAIL: container stdout tail follows"
  tail -n 25 "$TMP/r4out/stdout" 2>/dev/null | sed 's/^/FIXTURE-FAIL: /'
  fail "R4/R3 fixture liveness gate: the capture path was not proven live for this container run" \
       "docker rc=${_r4_rc}; sentinel.ok $( [ -f "$TMP/r4out/sentinel.ok" ] && echo present || echo absent ). See the FIXTURE-FAIL lines above."
else
  pass
fi

_r4_arm "$( [ "${_r4_a:-0}" -ge 1 ] && echo 1 || echo 0 )" \
  "R4" \
  "R4: the mount error did NOT survive the emitter's tail -n 20 | tail -c 180 under the shipped ordering" \
  "Write dmesg FIRST and the failing command's stderr LAST. capture-a=[$(head -c 300 "$TMP/r4out/capture-a.log" 2>/dev/null)]"
# NON-EMPTINESS FIRST: `grep -c … || true` on a missing or empty capture-b.log yields 0,
# which satisfies "the mount error did not survive" for the wrong reason — the arm would pass
# because nothing was captured at all. Assert the reversed capture DID happen by requiring the
# dmesg marker that must survive under that ordering, then assert the mount error did not.
_r4_b_alive=$(grep -c 'quota feature but no quota format module' "$TMP/r4out/capture-b.log" 2>/dev/null || true)
_r4_arm "$( [ "${_r4_b_alive:-0}" -ge 1 ] && [ "${_r4_b:-0}" -eq 0 ] && echo 1 || echo 0 )" \
  "R4 MUTATION" \
  "R4 MUTATION: reversed-ordering arm is inconclusive (dmesg-marker=${_r4_b_alive:-0} mount-error=${_r4_b:-0})" \
  "Expected marker>=1 (the capture ran) AND mount-error=0 (the ordering pushed it out). marker=0 means the container produced nothing and the arm proves nothing; mount-error>=1 means R4 cannot detect an ordering regression."
# R3(3a) — POSITIVE CONTROL for the hazard, not a defect report. The emitter's
# `[ -n ] && [ -r ]` branch falls through to `_san "$DETAIL_SRC"`, so handing it a
# non-empty-but-unreadable path ships THE LITERAL PATH as the "cause". We deliberately do
# NOT change the emitter here — its redaction/truncation ordering is load-bearing and out of
# this PR's scope. Instead we PROVE the hazard is live, which is what makes the stage-side
# guard in R3(3b) load-bearing rather than decorative. If this control ever stops leaking,
# the emitter changed and R3(3b)'s rationale must be re-derived.
_r4_arm "$( [ "${_r3_c:-0}" -ge 1 ] && echo 1 || echo 0 )" \
  "R3(3a)" \
  "R3(3a) POSITIVE CONTROL: the emitter no longer leaks a literal path for an unreadable detail source" \
  "R3(3b) below guards a hazard that may no longer exist — re-derive it against the emitter's current branch. capture-c=[$(head -c 300 "$TMP/r4out/capture-c.log" 2>/dev/null)]"

# R3(3b) — THE GUARD, WIDENED (#7227) TO EVERY FATAL EMIT SITE IN THE CONCATENATED runcmd.
#
# No emit site may hand the emitter a path it has not proven readable. Pre-#7204 luks_err
# passed the BARE LITERAL /var/log/cloud-init-output.log, which does not exist in this
# container and is exactly how a fatal came to carry a filename instead of a cause.
#
# IT USED TO READ ONE SITE OF FOUR. Scoped to luks-stage.code.sh it asserted the property on
# the one handler that already satisfied it, while on_err, sshd_config and bootstrap_err all
# shipped bare literals, unwatched. Widening it is #7227 item 3.
#
# THREE CORRECTIONS THE WIDENING REQUIRED — each measured, and without them the widened arm
# would have shipped WEAKER than the single-site version it replaces:
#
#  1. REGION-SCOPED GUARD SEARCH. The original `gpat.search(joined)` is file-global and keyed
#     on the VARIABLE'S NAME. Every handler used to call its local `_detail`, so on_err's
#     guard — first in the file — satisfies `gm.start() < epos` for every LATER site: delete
#     luks_err's own guard and the widened arm still reports GUARDED. The search is therefore
#     bounded below by the site's own enclosing window (nearest `name() {` or `STAGE=` above
#     it), and the arg-4 names are asserted PAIRWISE DISTINCT so the next author cannot
#     re-create the alias.
#  2. EMITTER-RELATIVE TOKEN INDEXING, never `toks[4]`. Measured on the `||`-chained gc_timer
#     line, `shlex.split(..., posix=False)[4]` is `'||'` — so an arg-4 check written as
#     `toks[4]` reports a false clean on exactly the call site #7227 names.
#  3. A MESSAGE-LITERAL SET, not a count. `len(sites) == 3` passes a tree where one site was
#     deleted and an unrelated one added.
#
# The `.code.sh` input is comment-stripped for the reason one level up: reading the raw text
# let a comment containing `[ -r "$_detail"` satisfy the guard check while the real guard was
# deleted — measured GUARDED on code with the literal-leak branch reopened.
_R3B_SRC="$TMP/runcmd-all.code.sh"
# A FUNCTION, so R3(3c)/R3(3d) can run the SAME analyzer over deliberately-broken copies.
# A verdict with no demonstrated failing direction certifies nothing — that is the defect
# this whole family exists to correct, and it would be self-defeating to re-create it here.
_r3b_analyze() {  # $1 = comment-stripped shell; one `site|level|isvar|guarded|arg4|msg` row per emit
  R3_GUARD_PAT="$_R3_GUARD_PAT" python3 - "$1" <<'PY' 2>&1 || true
import os, re, sys, shlex
src = open(sys.argv[1]).read()
joined = re.sub(r'\\\n\s*', ' ', src)          # fold line continuations
lines = joined.splitlines()
# One coordinate system for line index -> char offset, so window bounds and the emit position
# are directly comparable.
offs, p = [], 0
for l in lines:
    offs.append(p); p += len(l) + 1
OPENER = re.compile(r'^\s*([A-Za-z_][A-Za-z0-9_]*)\(\)\s*\{')
STAGE  = re.compile(r'^\s*STAGE=([A-Za-z0-9_]+)')
for i, l in enumerate(lines):
    if 'git-data-emit' not in l:
        continue
    try:
        toks = shlex.split(l.strip(), posix=False)
    except ValueError:
        print("UNPARSEABLE|?|?|?|?"); continue
    ei = next((k for k, t in enumerate(toks) if 'git-data-emit' in t), None)
    if ei is None:
        continue
    def arg(n):
        return toks[ei + n] if len(toks) > ei + n else ""
    msg, level, arg4 = arg(1), arg(3), arg(4)
    # ONLY REAL CALLS. The emitter PATH also appears in the delivery assertion
    # (`if [ ! -x /usr/local/bin/git-data-emit ]`), where arg(3) is empty and arg(1) is `]`.
    # Filtering downstream on `level != "info"` admits that row as a bogus LITERAL site;
    # filtering on `level == "fatal"` hid it by accident rather than by intent. A row is a
    # call only if its arg 3 is one of the emitter's three levels.
    if level.strip('"') not in ("fatal", "warning", "info"):
        continue
    # Nearest enclosing handler / stage boundary ABOVE this line — the guard window.
    wname, wstart = "?", 0
    for j in range(i - 1, -1, -1):
        mo = OPENER.match(lines[j])
        if mo:
            wname, wstart = mo.group(1), offs[j]; break
        ms = STAGE.match(lines[j])
        if ms:
            wname, wstart = ms.group(1), offs[j]; break
    isvar = "VAR" if arg4.lstrip('"').startswith("$") else "LITERAL"
    name = arg4.strip('"')
    guarded = "NA"
    if isvar == "VAR":
        # Accept -r OR -s. -s is strictly stronger (a readable but EMPTY file yields
        # DETAIL=[], a verdict with no cause — #7204's defect), so pinning -r alone would
        # red the correct fix. Bounded to [wstart, epos): a guard belonging to a DIFFERENT
        # handler, or one placed after the emit, protects nothing here.
        gpat = re.compile(os.environ.get("R3_GUARD_PAT", r'\[\s+-[rs]\s+"?') + re.escape(name))
        guarded = "GUARDED" if gpat.search(joined, wstart, offs[i]) else "UNGUARDED"
    print("|".join([wname, level.strip('"'), isvar, guarded, arg4, msg]))
PY
}
if [ -s "$_R3B_SRC" ]; then
  _r3b_out="$(_r3b_analyze "$_R3B_SRC")"
  # (i) NON-VACUITY, COUNTED IN THE SHELL. A python `assert` inside the heredoc increments
  # neither passes nor fails, and aborts extraction in a way that surfaces as some OTHER
  # arm's failure. An empty parse must be an assertion that FAILS here, loudly.
  # TWO SCOPES, DELIBERATELY DIFFERENT — and the difference is the point.
  #   _r3b_bound = every REPORTING site (fatal AND warning). (ii)/(iii) quantify over this,
  #     because a warning that ships an unguarded path misleads an operator exactly as a fatal
  #     does — and the gc_timer WARNING is the site #7227 names as having shipped the bare log
  #     literal. Scoped to `fatal` only, this arm's header ("No emit site may hand the emitter
  #     a path it has not proven readable") over-claimed: 3 of 7 sites were bound, and
  #     re-pointing gc_timer at an unguarded path left every arm green.
  #   _r3b_fatal = fatal only. (iv) pins the fatal MESSAGE SET, which is a claim about the
  #     three titles Sentry groups on; folding warnings in would make it a different assertion.
  _r3b_bound="$(printf '%s\n' "$_r3b_out" | awk -F'|' '$2!="info" && $1!=""' || true)"
  _r3b_fatal="$(printf '%s\n' "$_r3b_out" | awk -F'|' '$2=="fatal"' || true)"
  _r3b_n=$(printf '%s\n' "$_r3b_bound" | grep -c . || true)
  if [ "${_r3b_n:-0}" -ge 6 ]; then pass; else
    fail "R3(3b)(i): parsed only ${_r3b_n:-0} reporting emit sites in the concatenated runcmd (expected >= 6)" \
         "The extraction produced nothing usable, so every verdict below is vacuous. out=[$(printf '%s' "$_r3b_out" | head -c 300)]"
  fi

  # (ii) EVERY reporting site passes a GUARDED VARIABLE.
  _r3b_bad="$(printf '%s\n' "$_r3b_bound" | awk -F'|' '$3!="VAR" || $4!="GUARDED"' || true)"
  if [ -z "$_r3b_bad" ]; then pass; else
    fail "R3(3b)(ii): a reporting emit site does not pass a guarded variable as the detail source" \
         "site|level|isvar|guarded|arg4|msg -> $(printf '%s' "$_r3b_bad" | tr '\n' ' ')"
  fi

  # (iii) THE ARG-4 NAMES ARE PAIRWISE DISTINCT. Two handlers sharing a local name silently
  # disable (ii) for the later one — that is correction 1's failure mode, re-created.
  # ACROSS WINDOWS, not across emits. Two emits in the SAME stage sharing one variable is
  # correct and intended — sshd_config's fatal and its 126/127 warning both ship $_sshd_detail.
  # The defect is two DIFFERENT windows sharing a name, because the guard search is name-keyed
  # and bounded to a window: an alias lets one handler's guard satisfy another handler's check.
  # So collapse to unique (site,name) pairs first, then require the NAMES among them to be
  # unique. A flat name-uniqueness check would red the correct tree.
  _r3b_pairs="$(printf '%s\n' "$_r3b_bound" | awk -F'|' '$5 != "" {print $1"|"$5}' | sort -u || true)"
  _r3b_names="$(printf '%s\n' "$_r3b_pairs" | awk -F'|' '{print $2}' | sort || true)"
  _r3b_uniq="$(printf '%s\n' "$_r3b_names" | sort -u | grep -c . || true)"
  _r3b_tot="$(printf '%s\n' "$_r3b_names" | grep -c . || true)"
  if [ "${_r3b_uniq:-0}" -eq "${_r3b_tot:-0}" ]; then pass; else
    fail "R3(3b)(iii): two DIFFERENT emit windows share a detail-variable name (${_r3b_uniq}/${_r3b_tot} distinct)" \
         "The guard search is name-keyed and window-bounded, so an alias makes one site's guard satisfy another's check. pairs=[$(printf '%s' "$_r3b_pairs" | tr '\n' ' ')]"
  fi

  # (iv) THE MESSAGE-LITERAL SET, not a count.
  _r3b_msgs="$(printf '%s\n' "$_r3b_fatal" | awk -F'|' '{print $6}' | sed 's/^"//; s/"$//' | sort || true)"
  _r3b_want="$(printf '%s\n' 'git-data $STAGE FAILED' 'git-data LUKS stage FAILED' 'git-data sshd -t REJECTED the config' | sort)"
  if [ "$_r3b_msgs" = "$_r3b_want" ]; then pass; else
    fail "R3(3b)(iv): the fatal-site message set does not match" \
         "got=[$(printf '%s' "$_r3b_msgs" | tr '\n' '/')] want=[$(printf '%s' "$_r3b_want" | tr '\n' '/')]"
  fi

  # (v) AC6 — NO emit site AT ANY LEVEL passes the shared cloud-init log as its detail
  # source. Evaluated over every level, not just fatal: the gc_timer warning is the site
  # whose `||` chaining defeats `toks[4]`, and it shipped the literal.
  _r3b_lit="$(printf '%s\n' "$_r3b_out" | awk -F'|' '$5 ~ /cloud-init-output\.log/' || true)"
  if [ -z "$_r3b_lit" ]; then pass; else
    fail "R3(3b)(v): an emit site passes /var/log/cloud-init-output.log as its detail source" \
         "That log is shared across every stage and is unbounded; outside \`doppler run\` the emitter's value-redactor degrades to \`cat\`. sites=[$(printf '%s' "$_r3b_lit" | tr '\n' ' ')]"
  fi
  # ── R3(3c) — THE `LITERAL` DIRECTION. Re-point luks_err's detail at a bare path and the
  # analyzer must say LITERAL. Without this, "every site is VAR" has never been shown to be
  # capable of saying anything else on this input.
  _r3c="$TMP/r3c.code.sh"
  sed -E 's#"\$_luks_detail" "rc=\$rc"#/var/log/cloud-init-output.log "rc=$rc"#' "$_R3B_SRC" > "$_r3c"
  if cmp -s "$_R3B_SRC" "$_r3c"; then
    fail "R3(3c) MUTATION DID NOT LAND — luks_err's emit arg was not re-pointed" \
         "Re-anchor against the current text; as written this control certifies nothing."
  elif _r3b_analyze "$_r3c" | awk -F'|' '$1=="luks_err" && $3=="LITERAL"' | grep -q .; then
    pass
  else
    fail "R3(3c): a bare literal in luks_err's emit was NOT reported as LITERAL" \
         "The isvar classification has no demonstrated failing direction. got=[$(_r3b_analyze "$_r3c" | tr '\n' ' ')]"
  fi

  # ── R3(3d) — THE `UNGUARDED` DIRECTION, and the arm that proves the guard search is
  # REGION-SCOPED. Delete luks_err's own `[ -s ]` guards only. Under the previous file-global,
  # name-keyed search this still reported GUARDED whenever ANY earlier handler happened to
  # guard a variable of the same name — which is exactly what widening the arm to four sites
  # sharing the name `_detail` would have produced. It must now say UNGUARDED.
  _r3d="$TMP/r3d.code.sh"
  sed -E '/^[[:space:]]*\[ -s "\$_luks_detail" \]/d' "$_R3B_SRC" > "$_r3d"
  if cmp -s "$_R3B_SRC" "$_r3d"; then
    fail "R3(3d) MUTATION DID NOT LAND — luks_err's [ -s ] guards were not removed" \
         "Re-anchor against the current text; as written this control certifies nothing."
  elif _r3b_analyze "$_r3d" | awk -F'|' '$1=="luks_err" && $4=="UNGUARDED"' | grep -q .; then
    pass
  else
    fail "R3(3d): deleting luks_err's own [ -s ] guard did NOT flip it to UNGUARDED" \
         "The guard search is satisfied by something outside this handler's window — the name-keyed alias defect. got=[$(_r3b_analyze "$_r3d" | tr '\n' ' ')]"
  fi
else
  fail "R3(3b): skipped (concatenated runcmd not extracted)"
fi

# ── R3(2d) (#7227) — THE PARENT SEED IS ORDERED, asserted as an ORDER and not co-presence.
#
# The luks stage already has R3(2)/R3(2b)/R3(2c) for exactly this property; the parent shell
# had a seed with no arm behind it at all. Unseeded, $GIT_DATA_RUNCMD_DETAIL expands EMPTY,
# so on_err's `.final` becomes a RELATIVE path in cloud-init's cwd and the emitter falls
# through to shipping the path string as the cause — #7204's defect, one shell up.
# THE ORDERING CHECK IS A FUNCTION so the mutation arm can RE-RUN IT, exactly as R3(3c)/R3(3d)
# re-run _r3b_analyze. The first cut of this arm applied its sed and then asserted only that
# the seed line was gone — i.e. it verified its own mutation had landed and never evaluated the
# seed/trap/append comparison at all. A pure co-presence check would have "passed" that arm
# identically, so it demonstrated nothing about the ordering-vs-co-presence distinction its
# own comment claims. Echoes 1 when the ordering holds, 0 otherwise.
_r2d_ordered() {  # $1 = comment-stripped concatenated runcmd
  local s t a
  s=$(grep -n "$_R3_R2D_PAT" "$1" | head -1 | cut -d: -f1)
  t=$(grep -n '^[[:space:]]*trap on_err EXIT[[:space:]]*$' "$1" | head -1 | cut -d: -f1)
  a=$(grep -n '2>>"\$GIT_DATA_RUNCMD_DETAIL"' "$1" | head -1 | cut -d: -f1)
  if [ -n "$s" ] && [ -n "$t" ] && [ -n "$a" ] && [ "$s" -lt "$t" ] && [ "$s" -lt "$a" ]; then
    echo 1
  else
    echo "0 seed=${s:-none} trap=${t:-none} first-append=${a:-none}"
  fi
}
if [ -s "$_R3B_SRC" ]; then
  _r2d_real="$(_r2d_ordered "$_R3B_SRC")"
  if [ "$_r2d_real" = "1" ]; then pass; else
    fail "R3(2d): the parent detail seed does not precede BOTH 'trap on_err EXIT' and the first 2>> (${_r2d_real})" \
         "An unseeded handler builds '.final' as a relative path in cloud-init's cwd, and the emitter then ships the path literal as the cause."
  fi
  # RELOCATION MUTATION: move the seed BELOW the trap it must precede, then RE-RUN the check.
  # Not a deletion — a deletion is detectable by co-presence, which is the weaker property this
  # arm exists to distinguish itself from.
  _r2dm="$TMP/r2d.code.sh"
  awk '
    /^[[:space:]]*GIT_DATA_RUNCMD_DETAIL=/ && !moved { held = $0; moved = 1; next }
    { print }
    /^[[:space:]]*trap on_err EXIT[[:space:]]*$/ && moved == 1 { print held; moved = 2 }
  ' "$_R3B_SRC" > "$_r2dm"
  if cmp -s "$_R3B_SRC" "$_r2dm"; then
    fail "R3(2d) MUTATION DID NOT LAND — the seed line was not relocated" \
         "Re-anchor against the current text; as written this arm certifies nothing."
  elif [ "$(_r2d_ordered "$_r2dm")" != "1" ]; then
    pass
  else
    fail "R3(2d) MUTATION: the ordering check still reports ORDERED with the seed moved below the trap" \
         "R3(2d)'s green above certifies nothing — the check has no demonstrated failing direction."
  fi
else
  fail "R3(2d): skipped (concatenated runcmd not extracted)"
fi

# SKIP CEILING — a COUNTED assertion, which is what gives it a failing direction: deleting it
# drops `total` below the floor, so its own removal reddens the suite. Derivation: exactly ONE
# skip-eligible arm exists (the T5 mutation arm) and it declares a cost of 2 assertions — its
# premise and its result — so no legitimate run, healthy or degraded, can exceed 2.
#
# RE-DERIVED AT THE #7567 REBASE, NOT CARRIED. This constant was 1 while the mutation arm made a
# single counted assertion. #7565 gave it a second (the checksum-rejection premise), so the arm's
# declared cost became 2 and a ceiling left at 1 would have failed the very run it exists to
# permit — a false FAIL, which is the defect #7291 opened to remove. The ceiling is a function of
# the arm's assertion count and must be re-read off the arm whenever that changes.
#
# STATED RESIDUAL (ADR-188): RAISING this constant is not mechanically detectable. Any check
# over its value would be text-matching the source, the antipattern this file rejects, so the
# mitigation is procedural and declared rather than pretended: the value and its derivation
# live here, inside the floor's itemisation, where this file's culture already forces review of
# any count change. The evidence that hand-maintained numbers here drift silently is the
# "four plain `docker run`" comment, which was wrong from the moment the count reached six and
# stayed wrong across multiple PRs; #7565 has since corrected it to a pair of stated measures
# with their derivations, which is the shape a count in this file should take.
# RAISED 2 -> 5 (#7572), ITEMISED. The list below is the authority; the number is NOT derived
# from it. Deriving the ceiling from the live SKIPPED_ASSERTIONS count -- or from the arm_skip
# call sites -- would make `SKIPPED_ASSERTIONS <= _SKIP_CEILING` an identity that can never
# fail (AP-023), which is the decision ADR-188 recorded and #7572's issue body proposed
# reversing. It stays absolute; each raise gets its own stanza.
#
#   T5 mutation   2   (pre-existing)
#   S1 healthy    2   (#7572: both container-dependent assertions in the healthy run)
#   S1 mutation   3   (#7572: the mutant's rc, its fatal, and the privsep reproduction)
#   ------------------
#   total         5   -- NOT 7: T5 and S1 cannot both be maximally skipped in a run that
#                        produced any verdict at all, and 5 is the largest single-run cost
#                        actually reachable (S1's two groups together). If a future arm makes
#                        7 reachable, raise it in a new stanza rather than editing this one.
_SKIP_CEILING=5

# THE STANZA'S DECLARED LIST MUST MATCH THE CODE. A ceiling itemised in a comment is a claim
# about arm_skip call sites, and comments do not fail. Count the real call sites and assert
# the number the stanza above declares -- three: T5 mutation, S1 healthy, S1 mutation. This
# is the only thing standing between the stanza and silent drift, and it is deliberately a
# COUNT of call sites rather than a sum of their costs, because summing the costs from the
# code would re-create the identity the paragraph above rejects.
# S1's RESIDUAL, RECORDED AND GUARDED (#7572, 3.6). Before this change S1's healthy run was
# unconditional, so it could not skip and its failure was always a real signal -- S1's primary
# was itself a bound on the suite's vacuity. Routing it through the classifier REMOVES that
# bound: a run where the container never starts now declares five skips and still satisfies
# the floor. The composite bound therefore rests entirely on T5's PRIMARY arm, which is the
# one remaining container-dependent assertion that cannot decline. Assert that -- if a future
# change makes T5's primary skip-eligible too, every container-dependent assertion in the file
# becomes declinable at once and a run in which docker never worked reports green.
# TWO COUNTS COMPARED, not a negative match. The first draft used
#   grep -cE '^[[:space:]]*arm_skip "T5 (?!MUTATION)'
# which is wrong twice over: POSIX ERE has no negative lookahead (grep warns and matches
# nothing), and `grep -c` PRINTS `0` while EXITING 1 on no match -- so the `|| echo 0` guard
# appended a SECOND zero and the comparison saw the two-line string "0\n0". It failed against
# a file with no such call site. Counting both populations and asserting equality needs
# neither lookahead nor an error guard.
_T5_SKIPS=$(grep -cE '^[[:space:]]*arm_skip "T5 ' "$0" || true)
_T5_MUT_SKIPS=$(grep -cE '^[[:space:]]*arm_skip "T5 MUTATION' "$0" || true)
if [ "$_T5_SKIPS" -eq "$_T5_MUT_SKIPS" ]; then
  pass
else
  fail "T5 has ${_T5_SKIPS} arm_skip call site(s) of which only ${_T5_MUT_SKIPS} are MUTATION — its primary arm has become skip-eligible; S1's primary is no longer a bound (it declines via the classifier since #7572), so nothing unconditional remains to red a run in which the container never started" \
       "The composite vacuity bound rests on T5's primary. Re-establish a bound before making it declinable."; fi

_SKIP_CALL_SITES=$(grep -cE '^[[:space:]]*arm_skip ' "$0" || true)
if [ "$_SKIP_CALL_SITES" -eq 3 ]; then pass; else
  fail "skip stanza drift: ${_SKIP_CALL_SITES} arm_skip call site(s) in this file, the itemised stanza declares 3 (T5 mutation; S1 healthy; S1 mutation)" \
       "The ceiling's itemisation is a claim about call sites; an unlisted one silently consumes another arm's budget."; fi
if [ "$SKIPPED_ASSERTIONS" -le "$_SKIP_CEILING" ]; then pass; else
  fail "skip ceiling exceeded: ${SKIPPED_ASSERTIONS} assertion(s) declared-skipped, ceiling is ${_SKIP_CEILING}"; fi

# TOTAL INCLUDES DECLARED SKIPS. A loud skip that declares its assertion cost leaves the floor
# satisfied; an arm that stops running WITHOUT declaring anything still reds. That is the
# distinction `passes + fails` alone could not draw — it read a legitimate declared skip and a
# silently vanished arm as the same number.
total=$((passes + fails + SKIPPED_ASSERTIONS))
# Floor = the ACTUAL assertion count (B1: 1, B2: 1, D1: 2, T5: 4 + 1 mutation, T17: 2 + 1
# mutation, S1: 3 + 4 mutation). THIS LIST IS THE FROZEN 19-ERA BASELINE, not a running total —
# it sums to 19 and is what "19 pre-existing" in the #7204 stanza below is checked against, so
# do NOT update it when raising the floor (#7565 review caught an edit to it that made
# 20 + 14 = 34 ≠ 33 for anyone doing what that stanza invites). Each raise is itemised in its
# own stanza instead. Its job is to catch a silently-empty harness — an early
# `exit 0` from a skip guard, or a docker run that never produced output — not to be an
# aspirational target. S1 emits exactly 7 on ALL THREE of its paths (healthy, mutation-did-
# not-land, extraction-failed) so no short-circuit can satisfy the floor.
#
# RAISED 46 -> 48 WITH THE ARMS THAT MADE IT NECESSARY (#7565), itemised. RESTORED AT REVIEW —
# the #7291 rebase resolved a conflict in this block by taking its own side, which dropped this
# stanza wholesale while keeping the 48 it derives. The chain then read 44 -> 46 -> 48 -> 49 with
# nothing explaining the middle step, in a comment that four lines down tells the next author each
# raise is itemised in its own stanza. Summing the surviving itemisations gave 47, not 49:
#   T5 primary   1  the CHECKSUM'S OWN VERDICT (`<tarball>: FAILED` whole-line, on captured
#                   container stdout). The four assertions that predate it — rc, stage, level,
#                   CHMOD_RAN-absent — are ALL satisfied by the download failing, so the arm
#                   could report 4/4 green with sha256sum never having run. This assertion is
#                   the one that names which command aborted.
#   T5 mutation  1  the same verdict asserted PRESENT. That arm's whole premise is "a wrong
#                   digest was rejected and the chain continued anyway", and its `sed -i` — the
#                   only thing making the digest wrong — had no landing assertion. A no-op sed
#                   meant the genuine checksum passed, the chain completed, CHMOD_RAN printed,
#                   and the arm passed having reproduced nothing.
# Measured after that raise, on #7565's own bytes: 48 passed, 0 failed.
#
# RAISED 48 -> 49 AT REVIEW (#7291), itemised. Base re-read from origin/main at this edit and
# still 48. The review pass moved this literal in BOTH directions before settling, which is the
# argument for re-deriving the whole delta rather than nudging the number per change:
#   T5 errexit ordering  1  the shipped `set -e` and the doppler block are separate cloud-init
#                           runcmd entries and nothing asserted their ORDER. Moving the arming
#                           below the doppler entry left every existing guard green — B2 sees
#                           `set -e` on both sides, T5's other assertions hold because the DRIVER
#                           arms errexit itself, and S1's inequality is satisfied a fortiori —
#                           while production ran tar+chmod as root on an unverified tarball. The
#                           assertion mirrors the one S1 has always carried for its own stage.
#   T5 stage/level      -1  the stage and level assertions were two independent greps over one
#                           capture — a bag union satisfiable by two unrelated records — and are
#                           now ONE single-record conjunction. Strictly stronger coverage from
#                           strictly fewer assertions, so the floor comes back down by one.
# The D1 dash counterweight was removed in the same pass and moves this by ZERO: it contributed
# two either way (two fabricated passes when dash was absent, two real assertions when present),
# and dash is now a top-level `_skip` dependency so only the real pair can run.
#
# RAISED 48 -> 49 WITH THE ARM THAT MADE IT NECESSARY (#7291), itemised. THE BASE WAS RE-DERIVED
# FROM origin/main AT THE #7567 REBASE, NOT CARRIED FORWARD: this stanza previously read
# "46 -> 47", and 46 had itself been rebased from 44. The literal has moved 44 -> 46 -> 47 -> 48
# in four days across #7501, #7291 and #7565, so the only safe form is to re-read the base
# (`git show origin/main:<this file> | grep 'total" -lt'`) and state this raise as a DELTA of +1.
# #7565's own rebase note predicted the composed value independently and also says 49; two
# derivations agreeing is the reason to believe it, not either one alone.
#   skip ceiling 1  SKIPPED_ASSERTIONS <= ceiling, counted so that DELETING it reddens the suite
#                   via this very floor. Nothing else in #7291 adds NET count: the
#                   execution-marker guard on the mounted driver is STRUCTURAL (hard exit,
#                   uncounted); and the rewritten verdict re-shapes the T5 mutation arm's
#                   assertions rather than adding any.
#
#                   THE ARM'S CONTRIBUTION IS 2, NOT 1 — restated because #7565 changed it under
#                   this branch. That PR gave the arm a second counted assertion (the
#                   checksum-rejection premise), so the invariant this floor depends on is that
#                   the T5 mutation arm contributes exactly TWO on each of its four VERDICT
#                   routes: two on the ran route (premise + result), two on the fixture-defect
#                   and harness-defect routes, and a declared skip cost of two. A verdict route
#                   contributing a different number is indistinguishable here from an arm that
#                   partly vanished, which is what the floor exists to catch.
#
#                   NOT "every route" — the arm's `did not land` PRE-BRANCH (the `diff -q` that
#                   checks the errexit strip applied) sits OUTSIDE the verdict branch and
#                   contributes ONE. That is pre-existing and unchanged by this PR; origin/main
#                   has the identical shape. It is sound because that route must be red anyway
#                   and is doubly so: total falls to 48 and this floor fires alongside the
#                   arm's own message. Measured, mutation row 8: two FAIL lines, exit 1. The
#                   earlier wording here said "every route" and was falsified by that row —
#                   a universal asserted over routes that had not all been enumerated.
#
#                   PRECISION about what the floor covers: TWO of the arm's terminations — the
#                   structural `exit 1`s and the EXIT trap on a signal — never reach this line at
#                   all. Those runs are red because the process exits non-zero, NOT because the
#                   floor caught them. The floor's guarantee is over runs that reach it.
#
#                   CORRECTED AT REVIEW: this list previously included "an `arm_skip` cost
#                   rejection" as a third such termination, and that was wrong about the
#                   mechanism. `arm_skip`'s validator calls `fail` and then `return`s — it does
#                   not exit — so control reaches this line and the floor is one of the two
#                   things that catch it (total lands at 48, alongside the FAILURES ledger).
#                   The outcome was right and the stated reason was not; unreachable today
#                   because the sole call site passes a literal, which is exactly why nothing
#                   falsified it.
#
# RAISED 36 -> 44 WITH THE ARMS THAT MADE IT NECESSARY (#7227), itemised. The single old
# R3(3b) arm is REPLACED, so the sum is 36 - 1 + 9 = 44 (measured: 44 passed, 0 failed):
#   R3(3b)(i)   1  non-vacuity, COUNTED IN THE SHELL — a python `assert` inside the
#                  extraction heredoc increments neither passes nor fails, and aborts in a
#                  way that surfaces as some OTHER arm's failure
#   R3(3b)(ii)  1  every fatal emit passes a window-guarded VARIABLE (was: the luks site only)
#   R3(3b)(iii) 1  the arg-4 names are PAIRWISE DISTINCT — the guard search is name-keyed, so
#                  an alias silently satisfies one site's check with another's guard
#   R3(3b)(iv)  1  the message-literal SET, not a count: `len == 3` passes a tree where one
#                  site was deleted and an unrelated one added
#   R3(3b)(v)   1  no emit site AT ANY LEVEL passes /var/log/cloud-init-output.log — this is
#                  the arm that reaches the gc_timer WARNING, whose `||` chaining put `||` at
#                  toks[4] and made the old arg-4 check report a false clean
#   R3(3c)      1  the LITERAL direction, demonstrated
#   R3(3d)      1  the UNGUARDED direction, demonstrated — deleting luks_err's OWN guard must
#                  flip it, which is what proves the search is region-scoped rather than
#                  satisfied by a same-named variable in a different handler
#   R3(2d)      2  the parent seed precedes both `trap on_err EXIT` and the first `2>>`,
#                  plus its relocation mutation (in the plan this AC had no arm at all)
#
# RAISED 33 -> 36 at review (#7204): R3(2b) seed-precedes-TRAP (a seed between the trap and
# the first append passed R3(2) while being strictly worse than #7204 — the handler aborts
# on an unbound var under set -u and emits NOTHING), R3(2c) the ordering arm's first
# negative control, and R1's unclassified control (both prior controls inject `quota`,
# which IS in the allowlist, so R1(a) had no demonstrated failing direction).
#
# RAISED 19 -> 33 WITH THE ARMS THAT MADE IT NECESSARY (#7204), itemised so the next author
# can check the sum rather than trust it:
#   R1        8  extraction, mutation-landed, (a) unclassified, (b) module-dep,
#                (c) non-vacuity, in-test mutation control, committed pre-fix control
#   R1-EXPIRY 1  fixture provenance, deliberately OUTSIDE R1's pass/fail path
#   R3        2  detail-file seed present, seed PRECEDES first append (ordering, not co-presence)
#   R3(3a)    1  positive control: the emitter's literal-path leak is still live
#   R3(3b)    1  the stage passes a readability-guarded VARIABLE, never a bare path literal
#   R4        2  mount error survives the double-truncation, + ordering-reversal mutation
#              = 14 new, 19 pre-existing, 33 total.
# R1 emits 8 on its healthy path and 7 on each degraded one — NOT path-invariant, corrected at
# review. The 33 -> 36 raise added R1's unclassified control without adding a seventh `fail`
# to either else-block, and the claim here was never re-derived. Consequence is not a false
# green (those paths are red anyway) but a misattributed one: on an R1 degradation the total
# lands one short and the run exits with the floor's generic "harness did not execute fully"
# instead of R1's own cause — the misattribution class this file documents elsewhere. The
# fix is one more `fail` in each else-block and belongs with the R3 arm work, not here.
# S1 IS invariant and R3 IS invariant, on all three of THEIR paths (healthy, extraction-failed,
# precondition-missing) for the same reason S1 does. The floor must move with the suite or it
# only ever guards the work that predates it.
#
# WHY `-lt` AND NOT `-ne` (#7291 review, considered and REJECTED). An exact `-ne` would also
# catch an arm that accidentally executes twice, which a floor cannot. It is rejected on two
# grounds, neither of which is "it might break something":
#   1. `-ne`'s only detection over `-lt` is total > floor. The mutation class that motivated the
#      suggestion — a substitution mutant, an arm replaced by a bare `pass` — holds the total
#      CONSTANT and is caught by neither.
#   2. `-lt` fails on deletion; `-ne` fails on deletion OR addition, and addition is the normal
#      course of development here: this count moved 44 -> 46 -> 47 -> 48 -> 49 across #7501,
#      #7291 and #7565 in four days, and #7291 alone had to re-derive its own raise twice as
#      siblings landed underneath it. Every sibling PR would red the suite for everyone until
#      updated in lockstep, to buy the narrow case in (1).
# Note for anyone re-raising it: "I cannot validate -ne across environment variance" is NOT a
# reason — the header above asserts `passes + fails + SKIPPED_ASSERTIONS` IS environment-
# invariant. (The dash branch's `pass; pass` counterweight used to be cited here as what kept
# it so; this PR removed that counterweight and made dash a top-level `_skip` dependency, so
# the invariant now holds because the arm either runs its two real assertions or the suite
# does not start. Leaving the old sentence would have described machinery this same commit
# deleted.)
# RAISED 44 -> 46 (#7501, then +1 for the AC15 trap-count arm added at review): the R4/R3 run-level
# fixture-liveness gate emits on the healthy path. Counting it is the whole point of the instrument
# — a gate that contributes nothing when it succeeds is one that an inversion-to-always-pass leaves
# undetectable, because the old floor of 44 would still be met.
# RAISED 49 -> 58 (#7572), ITEMISED — nine new counted assertions, all container-INDEPENDENT,
# so they are made on every route and cannot be satisfied by a skip:
#     4  the S1 classifier's four rung controls (pure over their inputs; no docker)
#     1  the structural guard that both S1 markers are present in the MOUNTED driver
#     1  S1's own 12-assertions-per-route invariant
#     1  S1's own skip bound (<= 5)
#     1  the arm_skip call-site count matching the ceiling's itemised stanza
#     1  the T5-primary-not-skip-eligible residual guard
#   ----
#     9
# Re-derived from a measured run against the as-written file (58 assertions), not incremented
# by memory — the stanza above records that this count moved 44 -> 46 -> 47 -> 48 -> 49 across
# three PRs in four days, and #7291 had to re-derive its own raise twice as siblings landed
# underneath it. Do NOT edit the frozen 19-era baseline list higher up to reconcile with this;
# each raise is itemised in its own stanza, and that list is what "19 pre-existing" is checked
# against.
# RAISED 58 -> 68 (#7613), ITEMISED — ten new counted assertions, all pure text over $TMP,
# so they are made on every route the suite reaches this far on:
#     3  fixture A: R3(1), R3(2), R3(2b) — the unanchored seed lookup
#     1  fixture A': R3(2c) — the family's own negative control must discriminate
#     1  fixture B: R3(3b)(ii) — the guard predicate reading prose
#     1  fixture B': R3(3d) — the deletion sed must land on code, not a comment
#     1  fixture C: R3(3b)(i) — a count floor where the property is a set
#     1  fixture D: R3(2d) — the anchored reference must stay discriminating
#     2  Guard 5: _b2_strip parity on the real corpus, divergence on the at-risk fixture
#   ----
#    10
# Re-derived from a measured run against the as-written file, not incremented by memory.
if [ "$total" -lt 68 ]; then
  echo "FAIL: ran only ${total} assertions (<49) — harness did not execute fully" >&2
  exit 1
fi
echo "git-data-runcmd-rehearsal: ${passes} passed, ${fails} failed, Skipped: ${SKIPPED_ASSERTIONS} (${total} assertions)"
if [ "$SKIPPED_ASSERTIONS" -gt 0 ]; then
  echo "  NOTE: ${SKIPPED_ASSERTIONS} assertion(s) were declared-skipped by loud SKIP arms — this run is weaker than a full one."
fi
# THE VERDICT IS AN `exit`, NOT A TRAILING TEST EXPRESSION -- a bare test as the final
# statement makes the exit status a property of which line happens to be LAST, so a single
# appended command permanently greens the suite while it still prints accurate failure text.
#
# IT READS THE APPEND-ONLY LEDGER, NOT THE COUNTER (#7565 review). `fails` is a sum and so is
# `total`, so a bucket swap inside fail() satisfies both while silencing every assertion. See
# the FAILURES comment at the top of this file.
exit $(( ${#FAILURES[@]} > 0 ))
