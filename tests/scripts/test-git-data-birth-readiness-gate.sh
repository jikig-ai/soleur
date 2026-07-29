#!/usr/bin/env bash
# Test suite for tests/scripts/lib/git-data-birth-readiness-gate.sh (#6977).
#
# EVERY ASSERTION RUNS AGAINST A SYNTHESIZED FIXTURE, NEVER THE LIVE FILE.
#
# That is the single most important property of this suite, and it is worth stating why
# rather than just doing it. The obvious test — "run the gate on the real
# cloud-init-git-data.yml and assert it HOLDs" — passes today for the wrong reason: it
# passes because the feature is not ready. Its passing condition is "#6982 has not
# shipped yet", so the day the emitter lands, this suite goes red and the person landing
# it deletes the test. A test whose green depends on work being unfinished is not a
# regression guard; it is a countdown timer.
#
# So the fixtures below encode the CONTRACT (sentinel present => release, absent => hold,
# comment does not count, escaped literal does not count), and the contract keeps holding
# after #6982 lands.

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${DIR}/../.." && pwd)"
GATE="${ROOT}/tests/scripts/lib/git-data-birth-readiness-gate.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

passes=0
fails=0
pass() { passes=$((passes + 1)); printf '  ok   %s\n' "$1"; }
fail() {
  fails=$((fails + 1))
  printf '  FAIL %s\n' "$1"; printf '       rc=%s\n' "${2:-?}"; printf '       out=%s\n' "${3:-}"
}

# shellcheck source=/dev/null
source "$GATE"

check() {
  local name="$1" want_rc="$2" needle="$3" file="$4"
  local out rc
  out="$(git_data_birth_readiness_gate "$file" 2>&1)"; rc=$?
  if [[ "$rc" -eq "$want_rc" && "$out" == *"$needle"* ]]; then
    pass "$name"
  else
    fail "$name (want rc=$want_rc containing '$needle')" "$rc" "$out"
  fi
}

printf '\n=== git-data-birth-readiness-gate ===\n\n'

# ── HOLD: today's shape — an emitter-less template ────────────────────────────────
cat > "$TMP/no-emitter.yml" <<'YML'
#cloud-config
write_files:
  - path: /usr/local/bin/git-data-bootstrap.sh
    encoding: b64
    content: ${git_data_bootstrap_b64}
runcmd:
  - [ bash, -c, "cryptsetup luksOpen /dev/disk/by-id/${git_data_luks_volume_id} gitdata" ]
YML
check "a template with NO emitter => HOLD" 1 "HOLD" "$TMP/no-emitter.yml"
check "the HOLD names the blocking issue" 1 "#6982" "$TMP/no-emitter.yml"
check "the HOLD names the sentinel it wants" 1 'sentry_dsn' "$TMP/no-emitter.yml"
check "the HOLD names the ADR carrying the full checklist" 1 "ADR-149" "$TMP/no-emitter.yml"
check "the HOLD names the runbook banner to clear" 1 "git-data-birth.md" "$TMP/no-emitter.yml"
check "the HOLD warns off the laptop-apply workaround" 1 "laptop" "$TMP/no-emitter.yml"

# ── RELEASE: the emitter wired ────────────────────────────────────────────────────
cat > "$TMP/emitter.yml" <<'YML'
#cloud-config
write_files:
  - path: /etc/soleur/sentry-dsn
    permissions: '0600'
    content: ${sentry_dsn}
runcmd:
  - [ bash, -c, "curl -sf --data-binary @- \"${sentry_dsn}\" </var/log/boot-stage || true" ]
YML
check "a template WITH the sentinel => RELEASED" 0 "RELEASED" "$TMP/emitter.yml"
check "the RELEASE states what it did NOT check" 0 "NOT machine-checked" "$TMP/emitter.yml"

# ── THE COMMENT ARM (task 1.5.4) ──────────────────────────────────────────────────
#
# A comment-only back-reference marker pointing at #6982 is explicitly PERMITTED and
# desirable — it tells the next reader of the file where the emitter work lives. It must
# not release the interlock.
#
# This is not hypothetical fussiness: terraform does not know YAML comments exist, so a
# comment containing `${sentry_dsn}` really would force git-data.tf to supply the
# variable and really would satisfy a naive "does templatefile demand this var" check —
# while emitting exactly nothing. The gate has to be line-aware, and this arm is what
# proves it is.
cat > "$TMP/comment-only.yml" <<'YML'
#cloud-config
# TODO(#6982): wire the off-host emitter here. It will need ${sentry_dsn} threaded
# through git-data.tf's templatefile vars block. Until then this host boots dark and
# the birth route stays interlocked.
write_files:
  - path: /usr/local/bin/git-data-bootstrap.sh
    content: ${git_data_bootstrap_b64}
YML
check "a COMMENT mentioning the sentinel => still HOLD" 1 "HOLD" "$TMP/comment-only.yml"

# Indented comments too — the runcmd block is indented, so an unanchored comment strip
# would miss exactly the place a marker is most likely to be written.
cat > "$TMP/indented-comment.yml" <<'YML'
#cloud-config
runcmd:
    # emitter goes here once #6982 lands: ${sentry_dsn}
  - [ bash, -c, "true" ]
YML
check "an INDENTED comment mentioning the sentinel => still HOLD" 1 "HOLD" "$TMP/indented-comment.yml"

# A TRAILING comment. This is not a hypothetical shape: line 13 of the live
# cloud-init-git-data.yml is `- util-linux # provides flock for the …`, so a trailing
# comment is the single most natural place to write a #6982 back-reference. A whole-line
# strip cannot see it, and MEASURED against the live file, appending
# `TODO(#6982): emit boot status to ${sentry_dsn}` there flipped HOLD to RELEASED — the
# interlock disengaged by prose, which the gate's header claimed was impossible.
cat > "$TMP/trailing-comment.yml" <<'YML'
#cloud-config
packages:
  - util-linux # provides flock; TODO(#6982): emit boot status to ${sentry_dsn}
runcmd:
  - [ bash, -c, "true" ]
YML
check "a TRAILING comment mentioning the sentinel => still HOLD" 1 "HOLD" "$TMP/trailing-comment.yml"

# A trailing comment must not eat REAL template text earlier on the same line.
cat > "$TMP/code-then-comment.yml" <<'YML'
#cloud-config
runcmd:
  - [ bash, -c, "curl -sf ${sentry_dsn}" ] # emit boot status
YML
check "real interpolation with a trailing comment after it => RELEASED" 0 "RELEASED" "$TMP/code-then-comment.yml"

# ── THE ESCAPED-LITERAL ARM ───────────────────────────────────────────────────────
# `$${sentry_dsn}` is how a template writes a LITERAL dollar-brace. Terraform substitutes
# nothing, so the host receives the eight characters and no DSN. Counting it would let a
# shell snippet that happens to reference a same-named shell variable release the gate.
cat > "$TMP/escaped.yml" <<'YML'
#cloud-config
runcmd:
  - [ bash, -c, "echo $${sentry_dsn} > /dev/null" ]
YML
check "an ESCAPED \$\${sentry_dsn} literal => still HOLD" 1 "HOLD" "$TMP/escaped.yml"

# A real interpolation on the SAME line as an escaped one must still release — the
# refusal is of the escaped form specifically, not of any line containing one.
cat > "$TMP/mixed.yml" <<'YML'
#cloud-config
runcmd:
  - [ bash, -c, "echo $${literal} && curl -sf ${sentry_dsn}" ]
YML
check "a real interpolation beside an escaped one => RELEASED" 0 "RELEASED" "$TMP/mixed.yml"

# ── Fail-closed input ─────────────────────────────────────────────────────────────
check "a missing template file => ABORT" 1 "not found" "$TMP/nonexistent.yml"
check "no path supplied => ABORT" 1 "no cloud-init path" ""

# An EMPTY file is readable and simply has no sentinel — it must HOLD, not crash.
: > "$TMP/empty.yml"
check "an empty template => HOLD" 1 "HOLD" "$TMP/empty.yml"

# ── The live-file observation, recorded as CONTEXT and not as a gate ──────────────
#
# Deliberately NOT an assertion. Its result is reported so a reader of the log knows the
# interlock's live state, but the suite's exit status does not depend on it — otherwise
# this file becomes the countdown timer described in the header comment, and the person
# who ships #6982 has to delete a test to land it.
LIVE="${ROOT}/apps/web-platform/infra/cloud-init-git-data.yml"
if [[ -f "$LIVE" ]]; then
  if git_data_birth_readiness_gate "$LIVE" >/dev/null 2>&1; then
    printf '  note live cloud-init-git-data.yml: RELEASED (an emitter is wired — #6982 has landed)\n'
  else
    printf '  note live cloud-init-git-data.yml: HOLD (no emitter yet — expected until #6982)\n'
  fi
else
  printf '  note live cloud-init-git-data.yml not found at the expected path\n'
fi

# ── THE RUNG-2 REHEARSAL GATE (#6982 A3) ─────────────────────────────────────────
#
# Same fixture discipline as above: never the live evidence path. The contract is (a) no
# evidence => HOLD, (b) evidence must CLAIM a pass in non-comment text, (c) it must carry an
# auditable URL, and (d) it must be hash-bound to the template being dispatched, so a
# rehearsal of a since-edited template does not release the route.
#
# (d) is the one worth stating: without it "evidence exists" is satisfied forever by a
# rehearsal of a template that has since changed, and this template changes constantly.
printf '\nrung-2 rehearsal gate\n'

R2="$TMP/r2"; mkdir -p "$R2"
cp "$TMP/mixed.yml" "$R2/ci.yml"
R2_SHA="$(sha256sum "$R2/ci.yml" | cut -d' ' -f1)"

r2check() {
  local name="$1" want_rc="$2" needle="$3" ci="$4" ev="$5"
  local out rc
  out="$(git_data_rung2_rehearsal_gate "$ci" "$ev" 2>&1)"; rc=$?
  if [[ "$rc" -eq "$want_rc" && "$out" == *"$needle"* ]]; then
    pass "$name"
  else
    fail "$name (want rc=$want_rc containing '$needle')" "$rc" "$out"
  fi
}

r2_evidence() {  # $1=dest $2=verdict $3=url $4=sha
  printf 'RUNG2_BOOT_REHEARSAL=%s\nRUNG2_EVIDENCE_URL=%s\nRUNG2_TEMPLATE_SHA256=%s\n' \
    "$2" "$3" "$4" > "$1"
}

r2_evidence "$R2/ok.env" PASS "https://github.com/jikig-ai/soleur/actions/runs/1" "$R2_SHA"
r2check "valid, hash-matched evidence => RELEASED" 0 "RELEASED" "$R2/ci.yml" "$R2/ok.env"

r2check "absent evidence => HOLD" 1 "no rung-2 boot evidence" "$R2/ci.yml" "$R2/absent.env"

# Prose must not disengage a mechanical hold — the lesson the sentinel gate learned when a
# trailing comment flipped it from HOLD to RELEASED.
{ printf '# RUNG2_BOOT_REHEARSAL=PASS\n# RUNG2_EVIDENCE_URL=https://x/1\n'
  printf '# RUNG2_TEMPLATE_SHA256=%s\n' "$R2_SHA"; } > "$R2/comment.env"
r2check "a fully commented-out evidence file => HOLD" 1 "does not assert" "$R2/ci.yml" "$R2/comment.env"

r2_evidence "$R2/fail.env" FAIL "https://x/1" "$R2_SHA"
r2check "evidence claiming FAIL => HOLD" 1 "does not assert" "$R2/ci.yml" "$R2/fail.env"

r2_evidence "$R2/nourl.env" PASS "ask-me-about-it" "$R2_SHA"
r2check "an unauditable non-URL pointer => HOLD" 1 "not a URL" "$R2/ci.yml" "$R2/nourl.env"

r2_evidence "$R2/badsha.env" PASS "https://x/1" "deadbeef"
r2check "a malformed template hash => HOLD" 1 "malformed" "$R2/ci.yml" "$R2/badsha.env"

r2_evidence "$R2/stale.env" PASS "https://x/1" \
  "0000000000000000000000000000000000000000000000000000000000000000"
r2check "a hash for a DIFFERENT template => HOLD" 1 "STALE EVIDENCE" "$R2/ci.yml" "$R2/stale.env"

r2check "a missing cloud-init => ABORT" 1 "missing or not supplied" "$R2/nonexistent.yml" "$R2/ok.env"

# THE SELF-INVALIDATION PROPERTY, asserted end-to-end rather than inferred from (d): the
# SAME evidence file that just released the gate must stop releasing it once the template
# it attests to is edited. This is the whole reason the hash binding exists.
cp "$R2/ci.yml" "$R2/ci-edited.yml"
printf '\n# a later edit to the template\n' >> "$R2/ci-edited.yml"
r2check "evidence goes stale when the template is edited" 1 "STALE EVIDENCE" \
  "$R2/ci-edited.yml" "$R2/ok.env"

# ── MUTATION SECTION ──────────────────────────────────────────────────────────────
# This gate is a single decision, so every arm is SOLE-GUARD: there is no second line of
# defence to hand off to, and a mutation that still HOLDs means the arm was decorative.
printf '\nmutation checks (each neuters one guard; the arm it protects must flip)\n'

mutate_and_check() {
  local label="$1" sed_expr="$2" want_rc="$3" file="$4"
  local mutated out rc
  mutated="$TMP/mutated-gate.sh"
  sed "$sed_expr" "$GATE" > "$mutated"
  if cmp -s "$mutated" "$GATE"; then
    fail "$label — the mutation matched NOTHING in the gate (byte-identical copy); the guard is missing or the sed expression drifted." "n/a" "no textual change"
    return
  fi
  out="$(bash -c "source '$mutated'; git_data_birth_readiness_gate '$file'" 2>&1)"; rc=$?
  if [[ "$rc" -eq "$want_rc" ]]; then
    pass "$label (arm is load-bearing — neutering it flips the verdict)"
  else
    fail "$label — the arm did NOT change behavior when neutered; it may be dead code" "$rc" "$out"
  fi
}

# Neuter the comment filter (point it at a pattern no line can match, so nothing is
# stripped): the comment-only fixture then RELEASES, which is the precise failure this
# gate exists to prevent — prose satisfying a mechanical hold.
#
# Anchored on the hoisted `strip_comments=` assignment rather than on the grep pipeline.
# A sed aimed at the pipeline has to carry the sentinel regex through both a shell quote
# and sed's own escaping, and a mis-escaped expression matches nothing — which the
# non-vacuity floor correctly reports as a missing guard rather than a real result. It
# did, twice, which is why the gate hoists these onto their own lines.
mutate_and_check "comment-stripping guard" \
  's|^  strip_comments=.*|  strip_comments="s/^$//"|' \
  0 "$TMP/comment-only.yml"

# Neuter the escaped-literal exclusion by widening the sentinel to a bare substring that
# `$${sentry_dsn}` also contains: the escaped fixture then RELEASES.
mutate_and_check "escaped-literal guard" \
  's|^  sentinel_re=.*|  sentinel_re="sentry_dsn}"|' \
  0 "$TMP/escaped.yml"

# Drop the hold branch entirely: the emitter-less template then RELEASES.
mutate_and_check "hold branch" \
  's/^  if \[\[ "\$hits" -eq 0 \]\]; then/  if false; then/' \
  0 "$TMP/no-emitter.yml"

# Drop the missing-file guard: an absent path then RELEASES on a zero count from grep.
mutate_and_check "missing-file guard" \
  's/^  if \[\[ ! -f "\$cloud_init" \]\]; then/  if false; then/' \
  1 "$TMP/nonexistent.yml"

# Rung-2 arms. Same SOLE-GUARD reasoning: that gate is a chain of independent refusals with
# no second line of defence, so a mutation that still HOLDs means the arm was decorative.
printf '\nmutation checks — rung-2 gate\n'

mutate_r2() {
  local label="$1" sed_expr="$2" want_rc="$3" ci="$4" ev="$5"
  local mutated out rc
  mutated="$TMP/mutated-r2.sh"
  sed "$sed_expr" "$GATE" > "$mutated"
  if cmp -s "$mutated" "$GATE"; then
    fail "$label — the mutation matched NOTHING in the gate (byte-identical copy); the guard is missing or the sed expression drifted." "n/a" "no textual change"
    return
  fi
  out="$(bash -c "source '$mutated'; git_data_rung2_rehearsal_gate '$ci' '$ev'" 2>&1)"; rc=$?
  if [[ "$rc" -eq "$want_rc" ]]; then
    pass "$label (arm is load-bearing — neutering it flips the verdict)"
  else
    fail "$label — the arm did NOT change behavior when neutered; it may be dead code" "$rc" "$out"
  fi
}

# The hash binding is the arm most likely to be "simplified" away by a reader who takes it as
# redundant with the PASS assertion. Neutered, stale evidence releases the birth route.
mutate_r2 "rung-2 hash-binding arm" \
  's/^  if \[\[ "\$claimed_sha" != "\$live_sha" \]\]; then/  if false; then/' \
  0 "$R2/ci.yml" "$R2/stale.env"

# Neutered, an evidence file that says FAIL releases the route.
mutate_r2 "rung-2 PASS-assertion arm" \
  's/^  if ! grep -qE .\^\[\[:space:\]\]\*RUNG2_BOOT_REHEARSAL.*$/  if false; then/' \
  0 "$R2/ci.yml" "$R2/fail.env"

# Neutered, an unauditable pointer releases the route. Anchored on `$url` rather than on the
# URL regex itself: the gate's text contains a LITERAL `?` (`^https?://`), and in sed's BRE
# `\?` means "optional previous character", so the obvious-looking expression matches nothing
# and the mutation reports a missing guard rather than a real result.
mutate_r2 "rung-2 evidence-URL arm" \
  's|^  if \[\[ ! "\$url" =~ .*|  if false; then|' \
  0 "$R2/ci.yml" "$R2/nourl.env"

# NO comment-stripping mutation arm here, and the reason is worth recording rather than
# leaving as an absence. Neutering the `body="$(sed ...)"` line does NOT flip the
# commented-out fixture to RELEASED — the mutation battery said so — because whole-line
# comments are already refused by the `^[[:space:]]*RUNG2_...` ANCHOR in each grep, not by
# the strip. What the strip actually buys is TOLERANCE of a trailing comment on an otherwise
# valid line, which is a permissiveness property: mutating it away makes the gate STRICTER,
# so there is no fail-open mutation to assert. The positive test below is what pins it.
r2_evidence "$R2/trailing.env" PASS "https://x/1" "$R2_SHA"
sed -i 's|^RUNG2_BOOT_REHEARSAL=PASS$|RUNG2_BOOT_REHEARSAL=PASS   # rehearsed on a throwaway host|' "$R2/trailing.env"
grep -q '#' "$R2/trailing.env" || fail "fixture setup: trailing comment was not applied" "n/a" ""
r2check "trailing comments on valid evidence => still RELEASED" 0 "RELEASED" "$R2/ci.yml" "$R2/trailing.env"

# MINIMUM-CARDINALITY FLOOR. This suite had none, and it now covers TWO gates: an early
# `exit`, a helper that silently stopped being called, or a fixture-setup failure would
# otherwise report "0 failed" — the vacuous green every guard in this file exists to reject.
# A floor, not equality: it is developer-incremented, so `-eq` would redden the suite on every
# legitimately added assertion and train the next person to bump it unread. Counts
# passes+fails, so a genuine failure still counts as HAVING RUN and reports as a failure
# rather than masquerading as an empty suite.
_ran=$((passes + fails))
if [[ "$_ran" -lt 30 ]]; then
  fails=$((fails + 1))
  printf '  FAIL ANTI-VACUITY: only %s assertions ran, floor is 30. Arms were deleted, skipped, or the suite exited early.\n' "$_ran"
else
  printf '  ok   anti-vacuity floor: %s assertions ran (floor 30)\n' "$_ran"
fi

printf '\n=== %d passed, %d failed ===\n\n' "$passes" "$fails"
[[ "$fails" -eq 0 ]]
