#!/usr/bin/env bash
# Mutation battery for the D10 authorization gate and its restore engine (#7277).
#
# ── WHY THIS FILE EXISTS AS A COMMITTED SUITE ───────────────────────────────────────────────
# The two suites this battery mutates against are the only thing standing between an operator
# and an IRREVERSIBLE destroy of production's sole image store. Both are green. Green is not the
# question. The question is whether they would still be green if the guard they certify were
# removed — and the first revision of this gate answered "yes" for its central claim: it had 23
# green assertions and no row asserting the gate could PASS, so a gate rewritten to refuse
# unconditionally kept every assertion.
#
# Earlier runs of this battery existed only as ad-hoc shell in a session transcript. That is the
# defect this file fixes: an uncommitted battery proves something once and protects nothing
# afterwards. Committed and registered, it re-proves every guard on every full-suite run.
#
# ── THE HARNESS CONTRACT, WHICH IS ITSELF A SAFETY BOUNDARY ─────────────────────────────────
# A harness that fails to SET UP must ABORT (exit 2), never continue. A battery that cannot copy
# its sandbox does not degrade into a missing result — it degrades into a CONFIDENT WRONG one,
# reporting "the guard did not detect this" about a tree it never built. Every setup command
# below is checked, and a setup failure exits 2 (harness fault), distinct from exit 1 (a
# surviving mutation, i.e. a real finding).
#
# Three further properties, each learned from a battery that went vacuous:
#
#   1. THE MUTATION MUST BE PROVEN TO LAND. `py_replace` requires the anchor to be present AND
#      UNIQUE, and the caller then asserts the sandbox differs from pristine. A sed that silently
#      matched nothing reports the guard as "caught" while never having removed it.
#   2. THE BASELINE MUST BE GREEN FIRST. If the unmutated sandbox is not green, every subsequent
#      RED is attributable to the sandbox, not to the mutation, and no verdict is reportable.
#   3. RESTORE-TO-PRISTINE BETWEEN MUTATIONS. Without it, mutation N runs against N-1's mutant
#      and the battery measures a tree nobody designed.
#
# `TMPDIR` is defaulted to /var/tmp deliberately: a DIRECT invocation of this file (the inner
# loop while editing the gate) inherits the bare machine-global /tmp tmpfs, which parallel
# worktrees share, so a sandbox copy can fail for want of another session's disk.
#
# Exit codes: 0 = every mutation caught. 1 = at least one SURVIVED (a real gap). 2 = harness
# fault, no verdict.
export TMPDIR="${TMPDIR:-/var/tmp}"

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${DIR}/../.." && pwd)"

harness_die() { printf 'harness: %s\n' "$*" >&2; exit 2; }

SB="$(mktemp -d)" || harness_die "mktemp -d failed — refusing to report a verdict"
PRISTINE="$(mktemp -d)" || harness_die "mktemp -d (pristine) failed — refusing to report a verdict"
trap 'rm -rf "$SB" "$PRISTINE"' EXIT

# ── build the sandbox ────────────────────────────────────────────────────────────────────────
# The suites resolve their SUT as "$(dirname $0)/../../scripts/<name>", so the sandbox must
# reproduce that relative layout rather than flattening it.
mkdir -p "$SB/scripts" "$SB/tests/scripts" "$SB/apps/web-platform/infra" \
  || harness_die "could not create the sandbox layout"

SUT_GATE="scripts/registry-pull-path-health.sh"
SUT_ENGINE="scripts/registry-restore-from-ghcr.sh"
SUITE_GATE="tests/scripts/test-registry-pull-path-health.sh"
SUITE_ENGINE="tests/scripts/test-registry-restore-from-ghcr.sh"

for f in "$SUT_GATE" "$SUT_ENGINE" "$SUITE_GATE" "$SUITE_ENGINE"; do
  [[ -r "${ROOT}/${f}" ]] || harness_die "required file is unreadable: ${ROOT}/${f}"
  cp "${ROOT}/${f}" "${SB}/${f}" || harness_die "could not copy ${f} into the sandbox"
done
# Best-effort companions: the gate SOURCES these when no seam overrides them. Their absence
# changes which arm runs, so copy them when present rather than letting the sandbox differ from
# the real tree in a way no mutation asked for.
for f in scripts/zot-mirror-diagnosis.sh scripts/check-cloudflare-token-drift.sh; do
  [[ -r "${ROOT}/${f}" ]] && { cp "${ROOT}/${f}" "${SB}/${f}" || harness_die "could not copy ${f}"; }
done
[[ -r "${ROOT}/apps/web-platform/infra/cloud-init.yml" ]] && {
  cp "${ROOT}/apps/web-platform/infra/cloud-init.yml" "${SB}/apps/web-platform/infra/cloud-init.yml" \
    || harness_die "could not copy cloud-init.yml"
}
chmod +x "${SB}/${SUT_GATE}" "${SB}/${SUT_ENGINE}" || harness_die "could not chmod the sandboxed SUTs"

cp "${SB}/${SUT_GATE}"   "${PRISTINE}/gate.sh"   || harness_die "could not snapshot the pristine gate"
cp "${SB}/${SUT_ENGINE}" "${PRISTINE}/engine.sh" || harness_die "could not snapshot the pristine engine"

# ── helpers ──────────────────────────────────────────────────────────────────────────────────

# py_replace <file> <old> <new> — replace a UNIQUE anchor, or fail loudly.
#
# Anchor text is passed through the environment, not argv, so bash quoting cannot mangle a
# replacement containing quotes, backslashes or `$`. Uniqueness is required because a
# multi-match anchor makes the mutation ambiguous: the battery would not know what it changed.
py_replace() {
  OLD="$2" NEW="$3" python3 - "$1" <<'PY'
import os, sys
path = sys.argv[1]
old, new = os.environ["OLD"], os.environ["NEW"]
src = open(path).read()
n = src.count(old)
if n == 0:
    sys.stderr.write("anchor not found\n"); sys.exit(3)
if n != 1:
    sys.stderr.write("anchor matched %d times, need exactly 1\n" % n); sys.exit(3)
open(path, "w").write(src.replace(old, new, 1))
PY
}

restore_pristine() {
  cp "${PRISTINE}/gate.sh"   "${SB}/${SUT_GATE}"   || harness_die "could not restore the pristine gate"
  cp "${PRISTINE}/engine.sh" "${SB}/${SUT_ENGINE}" || harness_die "could not restore the pristine engine"
  chmod +x "${SB}/${SUT_GATE}" "${SB}/${SUT_ENGINE}" || harness_die "could not re-chmod the SUTs"
}

run_suite() { # $1 = gate|engine ; echoes nothing, returns the suite's rc
  local which="$1" suite
  case "$which" in
    gate)   suite="${SB}/${SUITE_GATE}" ;;
    engine) suite="${SB}/${SUITE_ENGINE}" ;;
    *) harness_die "run_suite: unknown suite '${which}'" ;;
  esac
  # BOUNDED, because some mutations here are non-terminating by design. Removing an argv
  # value-presence guard reintroduces a `shift 2` that never shifts, so the SUT spins forever —
  # and an unbounded battery would hang on exactly the mutation whose whole point is that a hang
  # is the failure mode. `timeout` returns 124, which is non-zero, so a hang reads as CAUGHT.
  # That is the correct verdict: the suite did detect the mutation, by not completing.
  timeout 300 bash "$suite" > "${SB}/suite.log" 2>&1
}

caught=0
survived=0
expected=0
unexpectedly_caught=0
SURVIVORS=""
MISCLASSIFIED=""

# mutate <label> <gate|engine> <old> <new>
#
# The suite that must go RED is the one owning the mutated SUT. A mutation whose anchor is
# missing is a HARNESS fault (the file drifted), not a survivor — reporting it as "caught" would
# be the battery certifying a guard it never touched.
mutate() {
  local label="$1" which="$2" old="$3" new="$4" target rc
  case "$which" in
    gate)   target="${SB}/${SUT_GATE}" ;;
    engine) target="${SB}/${SUT_ENGINE}" ;;
    *) harness_die "mutate: unknown target '${which}'" ;;
  esac

  restore_pristine
  if ! py_replace "$target" "$old" "$new"; then
    harness_die "mutation '${label}': anchor did not apply cleanly against ${which}. The SUT drifted from this battery — fix the anchor before trusting any verdict below."
  fi
  # Prove the edit actually changed the file. `py_replace` already refuses a missing anchor;
  # this catches the degenerate old==new case, where a mutation is a no-op and its "RED" would
  # be measuring the pristine tree.
  if diff -q "$target" "${PRISTINE}/$( [[ "$which" == gate ]] && echo gate.sh || echo engine.sh )" >/dev/null 2>&1; then
    harness_die "mutation '${label}' produced a file identical to pristine — the mutation is a no-op."
  fi

  run_suite "$which"; rc=$?
  if (( rc != 0 )); then
    caught=$(( caught + 1 ))
    printf '  caught    %s\n' "$label"
  else
    survived=$(( survived + 1 ))
    SURVIVORS="${SURVIVORS}${SURVIVORS:+$'\n'}  SURVIVED  ${label}"
    printf '  SURVIVED  %s\n' "$label"
  fi
}

# expect_survive <label> <gate|engine> <old> <new> <justification>
#
# For a guard that is UNREACHABLE by construction, where no fixture can make the suite go red
# because no input reaches the code. Such a guard is still worth keeping (defense-in-depth against
# a future edit to whatever makes it unreachable), but pretending the battery catches it would be
# a lie, and deleting the mutation would quietly shrink what the battery claims to measure.
#
# The justification is REQUIRED and must be a reachability argument, not a preference. If the
# mutation is caught, that argument has been falsified and the battery fails — see the epilogue.
expect_survive() {
  local label="$1" which="$2" old="$3" new="$4" just="$5" target rc
  [[ -n "$just" ]] || harness_die "expect_survive '${label}' carries no justification. An undocumented exemption is indistinguishable from a dropped mutation."
  case "$which" in
    gate)   target="${SB}/${SUT_GATE}" ;;
    engine) target="${SB}/${SUT_ENGINE}" ;;
    *) harness_die "expect_survive: unknown target '${which}'" ;;
  esac
  restore_pristine
  py_replace "$target" "$old" "$new" \
    || harness_die "expect_survive '${label}': anchor did not apply against ${which}."
  # The same no-op guard mutate() carries. py_replace does not require old != new, so a
  # degenerate entry would report `expected`, print its justification, and increment the
  # honest-looking count while having changed nothing — an exemption that never ran.
  if diff -q "$target" "${PRISTINE}/$( [[ "$which" == gate ]] && echo gate.sh || echo engine.sh )" >/dev/null 2>&1; then
    harness_die "expect_survive '${label}' produced a file identical to pristine — the mutation is a no-op, so the exemption is unverified."
  fi
  run_suite "$which"; rc=$?
  expected=$(( expected + 1 ))
  if (( rc == 0 )); then
    printf '  expected  %s\n' "$label"
    printf '            why: %s\n' "$just"
  else
    unexpectedly_caught=$(( unexpectedly_caught + 1 ))
    MISCLASSIFIED="${MISCLASSIFIED}${MISCLASSIFIED:+$'\n'}  MISCLASSIFIED  ${label} — documented unreachable, but the suite CAUGHT it"
    printf '  MISCLASSIFIED %s (documented unreachable, but CAUGHT)\n' "$label"
  fi
}

# ── baseline: the pristine sandbox must be green, or no verdict is reportable ────────────────
echo "=== baseline (pristine sandbox) ==="
restore_pristine
if ! run_suite gate; then
  tail -20 "${SB}/suite.log" >&2
  harness_die "the pristine gate suite is NOT green in the sandbox. Every RED below would be attributable to the sandbox rather than to a mutation, so no verdict is reportable."
fi
echo "  ok   gate suite green on the pristine sandbox"
if ! run_suite engine; then
  tail -20 "${SB}/suite.log" >&2
  harness_die "the pristine engine suite is NOT green in the sandbox. No verdict is reportable."
fi
echo "  ok   engine suite green on the pristine sandbox"
echo

# ── gate mutations ───────────────────────────────────────────────────────────────────────────
# Each one removes or inverts a guard whose failure mode is FAIL-OPEN: the gate reports
# AUTHORIZED while the property it names is unproven. A survivor here is a guard the suite
# certifies but does not test.
echo "=== gate mutations (scripts/registry-pull-path-health.sh) ==="

# G01-G04 previously mutated A5's abort/degrade arms. A5 was removed by architecture ruling
# (ADR-169), so those anchors are gone. They are replaced by a mutation of the guard that now
# carries the most authority per line: the seam list. Note the shape — this is a PARTIAL
# removal, which is strictly harder to catch than neutering the whole guard (G13) and is the
# realistic drift: someone adds a seam and forgets to list it, or removes the one that matters.
mutate "G01 seam guard silently stops covering REGISTRY_GATE_RESTORE_CMD (A2 becomes replaceable)" gate \
  'REGISTRY_GATE_HEALTH_CMD REGISTRY_GATE_CRANE_CMD REGISTRY_GATE_RESTORE_CMD' \
  'REGISTRY_GATE_HEALTH_CMD REGISTRY_GATE_CRANE_CMD'

mutate "G05 A3 outcome floor weakened to a lower-bound (under-fill passes)" gate \
  'if (( resolved != FLOOR )); then' \
  'if (( resolved > FLOOR )); then'

mutate "G06 A3 declared-vs-FLOOR self-consistency check deleted" gate \
  'if (( declared_required != FLOOR )); then' \
  'if false; then'

mutate "G07 FLOOR silently downgraded to 3" gate \
  'readonly FLOOR=4' \
  'readonly FLOOR=3'

mutate "G08 a required pin silently dropped from the declared set" gate \
  '  "jikig-ai/soleur-web-platform|latest"
' \
  ''

# Anchored on the arm ALONE, not on the arm plus the comment that follows it. The earlier form
# included the next comment line for uniqueness and broke the moment that comment was reworded —
# an anchor that depends on adjacent prose fails on edits that change no behaviour. Uniqueness
# is instead enforced by py_replace, which refuses a multi-match anchor outright.
mutate "G09 classify() default arm reads UNKNOWN as NOTFOUND (unclassified becomes absent)" gate \
  '    *) echo UNKNOWN ;;' \
  '    *) echo NOTFOUND ;;'

mutate "G10 classify() DENIED arm removed (auth failure misclassified)" gate \
  '    *UNAUTHORIZED*|*DENIED*|*"authentication required"*)              echo DENIED ;;
' \
  ''

# G11 is the mutation that found a live fail-open rather than a test gap: `last_err` bounded
# BYTES while classify() and every comment claimed LAST LINE, and classify() substring-matches,
# so its first case arm won over the whole capture. On a conditional pin that turned a credential
# rejection into a silent "absent, skipping". The mutation now removes the line-tail that fixed
# it — which is the drift a future editor would actually introduce, since the byte-tail LOOKS
# sufficient and is indistinguishable on every short fixture.
mutate "G11 last_err drops the line-tail and classifies over the whole byte window" gate \
  'tail -c 400 "$1" 2>/dev/null | tail -n 1 | tr' \
  'tail -c 400 "$1" 2>/dev/null | tr'

expect_survive "G12 workflow-command injection guard dropped from last_err" gate \
  'tail -c 400 "$1" 2>/dev/null | tail -n 1 | tr '"'"'\n'"'"' '"'"' '"'"' | sed '"'"'s/[[:space:]]*$//'"'"' || true; }' \
  'tail -c 400 "$1" 2>/dev/null | tail -n 1 || true; }' \
  'REDUNDANT GIVEN THE LINE-TAIL, same measured reason as its engine twin E22: with tail -n 1 the capture is one line and command substitution strips its trailing newline, so removing the tr+sed chain returns a byte-identical string. An earlier version of this justification claimed the gate and engine differed here because only the engine has an END-ANCHORED classifier arm; that is true of the classifiers and irrelevant to this mutation, and acting on it wrongly promoted E22. Kept as defence-in-depth for the removal of tail -n 1, which G11 mutates.'

# The engine carries the identical last_err and the identical fix, so it carries the identical
# mutations. A guard fixed in two files and mutation-tested in one is half-tested.
mutate "E21 engine last_err drops the line-tail (conditional skip swallows a credential failure)" engine \
  'tail -c 400 "$1" 2>/dev/null | tail -n 1 | tr' \
  'tail -c 400 "$1" 2>/dev/null | tr'

# EXEMPT, and the reasoning here was WRONG ONCE — recorded because the wrong version is the
# intuitive one. It was briefly promoted to mutate() on the theory that the engine's
# END-ANCHORED `*EOF` arm gives the `tr` teeth. It does not: once `last_err` ends in
# `| tail -n 1`, the capture is a single line, and `$( )` strips its trailing newline
# unconditionally. So `tail -n 1 | tr | sed` and a bare `tail -n 1` return BYTE-IDENTICAL
# strings (measured), and no fixture can separate them. The promotion made the battery report a
# survivor for a mutation that is genuinely undetectable.
#
# What the `tr` still buys is defence-in-depth against the REMOVAL of `tail -n 1` — and that
# removal is exactly what E21 mutates. So the injection property is covered; it is covered by
# E21, not here.
expect_survive "E22 engine workflow-command injection guard dropped from last_err" engine \
  "tail -c 400 \"\$1\" 2>/dev/null | tail -n 1 | tr '\\n' ' ' | sed 's/[[:space:]]*\$//' || true" \
  "tail -c 400 \"\$1\" 2>/dev/null | tail -n 1 || true" \
  'REDUNDANT GIVEN THE LINE-TAIL, measured not argued: with tail -n 1 the capture is one line and command substitution strips its trailing newline, so removing the tr+sed chain yields a byte-identical string and no fixture can distinguish the two. Kept as defence-in-depth because it becomes load-bearing the moment tail -n 1 is removed, and THAT removal is what E21 mutates. Do not promote this to mutate() again without first showing a capture where the two implementations differ.'

# Anchored on the CONDITION ALONE. The previous anchor spanned this line and the `for _seam in`
# below it, so inserting a comment between them (which a later fix did) broke the anchor and
# hard-aborted the whole battery — a fragility this file already documents for G09/E17 and then
# reproduced. py_replace enforces uniqueness, so the second line bought nothing.
mutate "G13 GITHUB_ACTIONS seam guard neutered (a seam can manufacture AUTHORIZED)" gate \
  'if [[ -n "${GITHUB_ACTIONS:-}" ]]; then' \
  'if false; then'

mutate "G14 ::add-mask:: emitted unconditionally (prints the prd token locally)" gate \
  'if [[ -n "${GITHUB_ACTIONS:-}" && -n "${ZOT_PUSH_TOKEN:-}" ]]; then' \
  'if [[ -n "${ZOT_PUSH_TOKEN:-}" ]]; then'

mutate "G15 A4 measured-dead credential downgraded from abort to notice" gate \
  '  stale)
    abort A4 ' \
  '  stale)
    echo '

mutate "G16 A4 out-of-vocabulary verdict treated as healthy" gate \
  '  *)
    abort A4 "the credential grader returned' \
  '  *)
    echo "the credential grader returned'

mutate "G17 A4 missing/non-executable detector degrades instead of aborting" gate \
  'if [[ ! -x "$DRIFT" ]]; then' \
  'if false; then'

mutate "G18 A2 rehearsal failure ignored for every enumerated exit code" gate \
  'if (( restore_rc != 0 )); then' \
  'if (( restore_rc > 100 )); then'

mutate "G19 A2 missing restore engine no longer aborts" gate \
  '[[ -x "$RESTORE" ]] || abort A2 ' ': # '

mutate "G20 A0 build_sha assertion removed (a stale cached /health passes)" gate \
  '[[ -n "$PROD_SHA" ]] || abort A0 ' ': # '

mutate "G21 A0 unreadable /health treated as measurable" gate \
  '(( health_rc == 0 )) || abort A0 ' ': # '

mutate "G22 A1 conditional-skip arm widened to required pins" gate \
  'if [[ "$3" == "conditional" && "$cls" == "NOTFOUND" ]]; then' \
  'if [[ "$cls" == "NOTFOUND" ]]; then'

mutate "G23 A0 APP_DOMAIN_BASE guard removed (health URL silently malformed)" gate \
  '[[ -n "${APP_DOMAIN_BASE:-}" ]] || abort A0 ' ': # '

mutate "G24 --rehearse-target no longer required to render a verdict" gate \
  '[[ -n "$REHEARSE_TARGET" ]] || usage_err ' ': # '

# A missing flag VALUE must fail, not spin. `shift 2` with one argument left returns non-zero
# without shifting and there is no `set -e`, so the parse loop re-reads the same `$1` forever. In
# a runner that is a hang to the job timeout — a CANCELLATION, with no ::error:: and no exit code.
mutate "G25 argv value-presence guard removed (missing flag value spins forever)" gate \
  '[[ $# -ge 2 ]] || usage_err "$1 requires a value (none was supplied)."' \
  ': # guard removed'

echo

# ── engine mutations ─────────────────────────────────────────────────────────────────────────
echo "=== engine mutations (scripts/registry-restore-from-ghcr.sh) ==="

mutate "E01 sink authentication skipped entirely (the shipped fail-open)" engine \
  'if ! $CRANE auth login "$TARGET" -u "$ZOT_PUSH_USER" -p "$ZOT_PUSH_TOKEN" $SINK_TLS_FLAG' \
  'if ! true "$TARGET" -u "$ZOT_PUSH_USER" -p "$ZOT_PUSH_TOKEN" $SINK_TLS_FLAG'

mutate "E02 ZOT_PUSH_TOKEN emptiness check removed" engine \
  '[[ -n "${ZOT_PUSH_TOKEN:-}" ]] || die 5 ' ': # '

mutate "E03 blob-completeness verification (crane validate) removed" engine \
  'if ! crane_capture "$WORK/val.out" "$WORK/val.err" validate $SINK_TLS_FLAG --remote "$dst"; then' \
  'if false; then'

mutate "E04 digest parity comparison inverted to always match" engine \
  'if [[ "$src_digest" != "$dst_digest" ]]; then' \
  'if false; then'

mutate "E05 empty read-back digest accepted as verified" engine \
  '  if [[ -z "$dst_digest" ]]; then' \
  '  if false; then'

mutate "E06 outcome floor assertion deleted (restores fewer than declared)" engine \
  'if (( restored != FLOOR )); then' \
  'if (( restored > FLOOR )); then'

# E07 was a survivor, and it is the one survivor that is NOT a test gap. It is recorded through
# `expect_survive` rather than deleted, because a battery that quietly drops the mutations it
# cannot catch is how a battery goes vacuous — the count must stay honest and the reasoning must
# stay auditable and re-checkable.
expect_survive "E07 zero-restore vacuity guard deleted" engine \
  'if (( restored == 0 )); then' \
  'if false; then' \
  'UNREACHABLE BY CONSTRUCTION, proven from the engine`s own earlier guards: reaching `restored == 0` requires FLOOR == 0 (else the preceding `restored != FLOOR` fires first), and FLOOR == 0 with any required entry also fires that check, while FLOOR == 0 with NO required entry is already rejected by the `ZERO required entries` guard. So no manifest reaches it. Kept as defense-in-depth against a future edit to those earlier guards — deliberately, since this suite has just demonstrated that an unreachable assertion is one a later edit can delete with everything still green.'

mutate "E08 distinctness guard removed (duplicates satisfy the floor)" engine \
  'if [[ ! "$n_distinct" =~ ^[0-9]+$ ]] || (( n_distinct != n_required )); then' \
  'if false; then'

mutate "E09 zero-required-entries manifest accepted" engine \
  'if (( n_required == 0 )); then' \
  'if false; then'

mutate "E10 manifest .floor no longer required to be numeric" engine \
  '[[ "$FLOOR" =~ ^[0-9]+$ ]] || die 1 ' ': # '

mutate "E11 signature-presence check at GHCR removed (unsigned restore arm)" engine \
  '  if [[ -z "$(digest_of "$WORK/sigsrc.out")" ]]; then' \
  '  if false; then'

mutate "E12 signature read-back from the sink removed" engine \
  '  if [[ -z "$(digest_of "$WORK/sigdst.out")" ]]; then' \
  '  if false; then'

mutate "E13 signature copy failure ignored" engine \
  '  if ! crane_capture "$WORK/sigcp.out" "$WORK/sigcp.err" copy $SINK_TLS_FLAG "ghcr.io/${repo}:${sig_tag}" "${TARGET}/${repo}:${sig_tag}"; then' \
  '  if false; then'

mutate "E14 copy failure ignored entirely" engine \
  '  if ! crane_capture "$WORK/cp.out" "$WORK/cp.err" copy $SINK_TLS_FLAG "$src" "$dst"; then' \
  '  if false; then'

mutate "E15 unreadable --tags-from manifest treated as an empty inventory" engine \
  '[[ -r "$TAGS_FROM" ]] || die 1 ' ': # '

mutate "E16 ghcr.io accepted as the restore target (a no-op that reports success)" engine \
  '  ghcr.io|ghcr.io/*|*://*) die 1 ' '  __never_matches__) die 1 '

mutate "E17 classify() default arm reads UNKNOWN as NETWORK (retryable)" engine \
  '    *) echo UNKNOWN ;;' \
  '    *) echo NETWORK ;;'

mutate "E18 source-resolution failure no longer aborts on an empty digest" engine \
  '  if [[ -z "$src_digest" ]]; then' \
  '  if false; then'

mutate "E19 non-loopback sink silently downgraded to plain HTTP" engine \
  '  *) SINK_TLS_FLAG="" ;;   # a non-loopback sink must use TLS' \
  '  *) SINK_TLS_FLAG="--insecure" ;;'

mutate "E20 conditional-skip arm widened to required entries" engine \
  '        if [[ "$disp" == "conditional" ]]; then' \
  '        if true; then'

mutate "E23 argv value-presence guard removed (missing flag value spins forever)" engine \
  '[[ $# -ge 2 ]] || die 1 "$1 requires a value (none was supplied)."' \
  ': # guard removed'

restore_pristine

echo
# THE BATTERY'S OWN ANTI-VACUITY FLOOR. Without it, commenting out every mutate/expect_survive
# call yields "0 caught, 0 survived, 0 documented-unreachable" and EXIT 0 — a battery that
# asserted nothing, reported success, and is indistinguishable in CI from a full run. This file
# already argues that "a battery that quietly drops the mutations it cannot catch is how a
# battery goes vacuous"; nothing enforced that on the battery itself. It is a FLOOR, not an
# equality: the count is developer-incremented, so `-eq` would turn every added mutation into a
# spurious failure. Derived from a green run, not from an expected number.
dispatched=$(( caught + survived + expected ))
if (( dispatched < 45 )); then
  echo "harness: only ${dispatched} mutations were dispatched, floor is 45. Either mutations were removed without lowering this floor deliberately, or the dispatch itself is broken — in both cases the verdict below is not reportable." >&2
  exit 2
fi

echo "=== ${caught} caught, ${survived} survived, ${expected} documented-unreachable (${dispatched} dispatched) ==="

rc=0
if (( survived > 0 )); then
  printf '%s\n' "$SURVIVORS"
  echo "A SURVIVING mutation is a guard the suites certify but do not test. Fix the suite (or the guard) before shipping." >&2
  rc=1
fi
# The exemption is two-directional on purpose. A one-directional allowance rots: the guard becomes
# reachable, someone writes the row that catches it, and the battery keeps calling it unreachable
# forever. If an expect_survive mutation IS caught, the justification is now false and must be
# rewritten or the entry promoted to a normal `mutate`.
if (( unexpectedly_caught > 0 )); then
  printf '%s\n' "$MISCLASSIFIED"
  echo "A documented-unreachable mutation was CAUGHT — its justification is now false. Promote it to mutate() or rewrite the reasoning." >&2
  rc=1
fi
exit "$rc"
