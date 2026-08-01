#!/usr/bin/env bash
# ship-soak-signal-gate.sh — the soak-signal scan for the Follow-Through
# Enrollment Gate (#7056, #7087).
#
# Reads a PR/plan corpus on stdin. Exit 0 + prints "SOAK-SIGNAL: yes" plus the
# matched lines when the text CLAIMS a post-deploy soak close-criterion; exit 1
# (no output) when it does not; exit 2 when the scan itself could not run.
#
# This script OWNS the regex and every strip stage. Both consumers — the
# PreToolUse hook `.claude/hooks/ship-soak-followthrough-gate.sh` and
# `plugins/soleur/skills/ship/SKILL.md` §Phase 5.5 — pipe raw text in and read
# the exit code. Previously each carried its own copy of SOAK_RE, kept in sync
# by a byte-identity test; one copy makes that drift unrepresentable rather than
# merely asserted (`2026-07-17-a-copy-adapted-gate-drifted-in-the-half-i-did-
# not-parity-pin.md`: "Prefer removing the second copy over pinning it.").
#
# ---------------------------------------------------------------------------
# The two false positives this retires — both are "matched a TOKEN, not a CLAIM"
# ---------------------------------------------------------------------------
# #7056: the old regex led with a bare `soak` alternative, so it fired on a
#   plan's own sentence DISCLAIMING one — `Soak/follow-through enrollment:
#   **not applicable** — no time-gated close criterion`. That inverts the
#   incentive the disposition-recording convention exists to create: the better
#   a plan documents that it needs no soak, the likelier the gate blocks it, and
#   the cheapest way to pass becomes saying nothing.
# #7087: the same bare alternative fired on the FILENAME `sandbox-canary-soak
#   .test.sh` in a plan about deleting orphan test suites. A filename is not a
#   negation, which is why a negation strip alone would not have fixed it.
#
# A gate that fires on correct plans teaches the operator to dismiss it. That
# erosion — not any single override — is what these two bugs cost.
#
# ---------------------------------------------------------------------------
# Why the fix is a DELIMITER plus a SPAN strip, and not the two obvious options
# ---------------------------------------------------------------------------
# #7056 proposed deleting the bare `soak` alternative as the cheapest correct
# change. Measured against the ground-truth positive set — the plans that
# actually enrol a follow-through probe — that collapses recall from 42/50 to
# single digits: the bare noun is what carries nearly all the detection. The
# opposite option (a negation strip alone) leaves #7087 live.
#
# So the bare noun STAYS and gains a structural left-delimiter, and the negation
# strip is added alongside it. Measured: recall 42 -> 41 of 50, false positives
# 21 -> 14 of 40. Re-measure with `scripts/ship-soak-signal-measure.sh both
# scripts/ship-soak-signal-gate.sh`; that runner is the executable form of the
# recall floor, and it exists because the first draft of this fix passed all 21
# of its own acceptance criteria while silencing 28 of 50 real enrolments.
#
# An enumerated whitelist of nouns that may follow `soak` ("claim shaping") was
# also measured and rejected: recall 42 -> 22, and it missed `probe`, which is
# the repo's own word for the deliverable. Stripping the gate's NAME was
# rejected too — `Soak follow-through enrollment` is the canonical heading real
# plans use to DECLARE enrolment, so stripping it deletes a true positive.
#
# ---------------------------------------------------------------------------
# Accepted residual, stated rather than discovered
# ---------------------------------------------------------------------------
# The inline-code strip cannot tell a quoted FILENAME from a quoted CLAIM, so a
# plan that writes its entire close criterion inside a backtick span goes
# undetected. Filenames are by far the commoner case, so the strip earns its
# keep; the residual is pinned by a named fixture
# (`backticked-declaration-known-bypass.md`) so it stays a known bypass.
#
# The residual is BOUNDED to spans opening and closing on the same line: the
# strip is a line-oriented `sed`, so a backtick span wrapped across a newline is
# not stripped and such a claim still fires. That is the safe direction, and it
# is stated here so the bound is a known property rather than a lucky accident.
#
# Consequence worth stating plainly: an unenrolled soak declared in PROSE has no
# other mechanical detector in this repo. Phase 7 Step 3.5 scans only for the ⏳
# marker. If this scan goes dark, nothing else catches the class — which is why
# the exit contract distinguishes "no signal" from "could not scan", and why the
# recall floor is the primary acceptance criterion rather than the precision one.
set -uo pipefail

FAULT=2

# Soak signal. ONE alternative differs from what shipped before this change: the
# bare noun now requires a structural left-delimiter, so it cannot match glued
# inside an identifier (`sandbox-canary-soak.test.sh`, `workspaces-luks-soak-
# 6604.sh`, `web2-standby-soak-6459`). That single character class is the whole
# of #7087's fix. Everything else is byte-identical to the shipped regex.
# Discipline borrowed from `2026-05-07-post-build-token-gates-false-positive-on-
# worktree-paths.md`: "Prefer tokens with structural delimiters over bare
# substrings."
SOAK_RE='(^|[^[:alnum:]_-])soak|stays? (at )?(~?0|zero)|[0-9]+[- ]day[s]?( post-deploy| soak)|post-deploy (soak|verif|observ)|adopting[[:space:]]*(→|->|to)[[:space:]]*accepted|status[[:space:]]+flip'

# Negation. Three shapes, all requiring the negation to actually GOVERN the soak:
#   1. `no <=3 tokens> soak`  — `No post-deploy soak is required`, `no 7-day soak`.
#      The <=3 bound is load-bearing: `no P0 incidents during the 7-day soak`
#      puts five tokens between the two, so the negation governs the incidents,
#      not the soak, and that line must still fire.
#   2. `soak ... not applicable|not needed|not required|n/a` within one sentence.
#   3. `Soak|Follow-through <label>: not applicable|n/a|none` — the disposition
#      line the plan template asks for, which is exactly what #7056 tripped on.
# Case classes are inlined because `sed` has no `-i` equivalent, and the
# expression is applied with `@` as the delimiter because it contains `n/a`.
NEGATION_RE='(^|[[:space:]])[Nn][Oo][[:space:]]+([[:alnum:]#~._-]+[[:space:]]+){0,3}[Ss][Oo][Aa][Kk]|[Ss][Oo][Aa][Kk][^.]{0,50}([Nn]ot applicable|[Nn]ot needed|[Nn]ot required|[Nn]/[Aa])|([Ss][Oo][Aa][Kk]|[Ff]ollow-[Tt]hrough)[^:]{0,40}:[[:space:]]*(\*\*)?[[:space:]]*([Nn]ot applicable|[Nn]/[Aa]|[Nn]one)'

WORK="$(mktemp -d)" || exit "$FAULT"
trap 'rm -rf "$WORK"' EXIT INT TERM

# Read the corpus to a FILE, never a shell variable: command substitution drops
# NUL bytes, and a corpus with a NUL is exactly the case `-a` exists for.
cat > "$WORK/raw" || exit "$FAULT"

# --- Stage 1: fenced code blocks -------------------------------------------
# A regex, config block, or SQL snippet quoted in a plan is DATA, not a claim —
# a plan documenting THIS gate quotes SOAK_RE itself.
#
# Stripped lines are replaced with EMPTY lines rather than dropped, so every
# later stage and the final `grep -n` report line numbers that are true against
# the original corpus. A diagnostic gate that cites wrong line numbers is worse
# than one that cites none (AC16).
#
# The anchor is indent-tolerant and there is an END check. The two existing
# gates in this repo each got exactly one of those halves right: the PIR
# precedent is indent-tolerant but has no END check (so it fails OPEN on an
# unbalanced fence), and the hook has the END check but anchors at column 0.
# Copying either verbatim ships a regression.
awk '
  BEGIN { f = 0 }
  /^[[:space:]]*```/ { f = !f; print ""; next }
  f { print ""; next }
  { print }
  END { if (f) exit 2 }
' < "$WORK/raw" > "$WORK/nofence"
rc=$?
if [[ "$rc" -eq 2 ]]; then
  # Unbalanced fence: an unclosed ``` would otherwise swallow the whole rest of
  # the document, silencing every claim after it. Fail CLOSED — scan the
  # unstripped body and accept the over-production. This is NOT a fault.
  cp "$WORK/raw" "$WORK/nofence" || exit "$FAULT"
elif [[ "$rc" -ne 0 ]]; then
  # awk missing/unrunnable — the scan did not happen. Say so; do not report
  # "no signal", which is what a caller would otherwise read.
  exit "$FAULT"
fi

# --- Stage 2: inline `code` spans ------------------------------------------
# Same reason as stage 1, for backticked tokens. This is what quiets a
# backticked filename; the structural delimiter in SOAK_RE is what quiets the
# BARE one, and #7087's plan wrote it both ways.
# shellcheck disable=SC2016  # the sed backticks are literal, no expansion wanted
sed 's/`[^`]*`//g' < "$WORK/nofence" > "$WORK/nocode" || exit "$FAULT"

# --- Stage 3: negation spans ------------------------------------------------
# SPAN removal, never a whole-line drop. A line drop swallows any real
# declaration sharing a line with a disposition, and PR bodies are not
# hard-wrapped so mixed lines are the norm. Both of these fire correctly under
# span removal and go silently DARK under `grep -v`:
#   `Soak enrollment: none yet — the 14-day soak begins at deploy.`
#   `No soak is needed for the docs half; the runtime half stays at ~0 for 7 days post-deploy`
sed -E "s@${NEGATION_RE}@@g" < "$WORK/nocode" > "$WORK/haystack" || exit "$FAULT"

# --- Match ------------------------------------------------------------------
# `-a` on every grep: grep resolves to GNU grep in the hook but to a ugrep
# wrapper carrying `-I` on the agent's Bash path, and without `-a` the two
# disagree on a corpus containing a NUL byte — the SKILL path then goes silently
# dark while the hook fires. `-m 5` bounds the diagnostic output.
#
# Two locale passes: the UTF-8 pass is what matches the `→` alternative; the C
# pass is the byte-oriented fallback for a corpus that is not valid UTF-8, where
# the first pass can abort mid-file.
HITS="$(LC_ALL=C.UTF-8 grep -naiE -m 5 "$SOAK_RE" "$WORK/haystack" 2>/dev/null)"
g=$?
if [[ "$g" -ne 0 ]]; then
  HITS="$(LC_ALL=C grep -naiE -m 5 "$SOAK_RE" "$WORK/haystack" 2>/dev/null)"
  g=$?
fi

if [[ "$g" -eq 0 ]]; then
  echo "SOAK-SIGNAL: yes"
  # Line numbers are true against the ORIGINAL corpus (stage 1 blanks rather
  # than drops), so the operator can go straight to the line.
  printf '%s\n' "$HITS"
  exit 0
fi

# grep: 1 = no match (a clean result), >1 = grep itself failed (a fault).
if [[ "$g" -gt 1 ]]; then
  exit "$FAULT"
fi
exit 1
