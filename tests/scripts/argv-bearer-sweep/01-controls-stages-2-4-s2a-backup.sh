# shellcheck shell=bash
# SOURCED FRAGMENT of tests/scripts/test-argv-bearer-sweep.sh -- NOT independently runnable.
# =====================================================================================
# INSTRUMENT CONTROLS (abort with FATAL; counted as rows when they pass)
# =====================================================================================
fatal() { printf '[FATAL] instrument control failed: %s\n' "$1" >&2; exit 2; }

# C1: the canonical-compliant synthetic probe must be GREEN.
P_CANON="$(make_synth canonical)"
run_probe c1-canonical "$P_CANON" "SYNTH_TOKEN=$FIXTURE_TOKEN"
C1_RC=$RUN_RC
evaluate "$ROWS/c1-canonical" "$SYN_HOST" 1 "$FIXTURE_TOKEN"
if [[ "$C1_RC" -ne 0 || -n "$EV_FAILED" ]] || ! grep -q '^PASS' "$ROWS/c1-canonical/stdout"; then
  fatal "C1 canonical-compliant synthetic probe is not GREEN (rc=$C1_RC failed='$EV_FAILED')"
fi
row "control C1: canonical-compliant synthetic probe is GREEN (rc 0, PASS, bearer on stdin only)" ok

# C2: an argv-bearer synthetic probe must be RED on the 'token in recorded argv' check.
P_ARGV="$(make_synth argv)"
run_probe c2-argv "$P_ARGV" "SYNTH_TOKEN=$FIXTURE_TOKEN"
evaluate "$ROWS/c2-argv" "$SYN_HOST" 1 "$FIXTURE_TOKEN"
has_check token-in-argv || fatal "C2 argv-bearer synthetic probe was not caught on token-in-argv (failed='$EV_FAILED')"
has_check calls-below-min && fatal "C2 argv-bearer probe made no calls; RED must come from the argv check, not from silence"
row "control C2: argv-bearer synthetic probe is RED on 'token in recorded argv' (not on silence)" ok

# C3: the REAL-CURL ORACLE. The shim's model of the stdin config channel is calibrated against
# curl itself: `--libcurl` writes the C program curl WOULD run. Nothing listens on port 9, so the
# transfer fails with rc 7 -- the generated program is still written.
ORA="$TMPD/oracle"; assert_fixture_dir "$ORA"; mkdir -p "$ORA"
printf 'header = "Authorization: Bearer %s"\n' "$FIXTURE_TOKEN" \
  | "$REAL_CURL" --disable --noproxy '*' -sS --max-time 3 --libcurl "$ORA/ok.c" --config - http://127.0.0.1:9/ >/dev/null 2>&1 || true
HOSTILE="$(printf 'SYNTHMARK0001"\nurl = "http://127.0.0.1:9/second')"
printf 'header = "Authorization: Bearer %s"\n' "$HOSTILE" \
  | "$REAL_CURL" --disable --noproxy '*' -sS --max-time 3 --libcurl "$ORA/hostile.c" --config - http://127.0.0.1:9/ >/dev/null 2>&1 || true
[[ -s "$ORA/ok.c" && -s "$ORA/hostile.c" ]] || fatal "C3 real curl did not write --libcurl output (curl built without --libcurl?)"
ora_appends=$(grep -c 'curl_slist_append(slist1, "Authorization: Bearer' "$ORA/ok.c" || true)
ora_urls_ok=$(grep -c 'CURLOPT_URL' "$ORA/ok.c" || true)
ora_urls_hostile=$(grep -c 'CURLOPT_URL' "$ORA/hostile.c" || true)
[[ "$ora_appends" -eq 1 ]] || fatal "C3 oracle: expected exactly one Authorization append for the stdin config form, saw $ora_appends"
[[ "$ora_urls_ok" -eq 1 ]] || fatal "C3 oracle: expected one CURLOPT_URL for a clean token, saw $ora_urls_ok"
[[ "$ora_urls_hostile" -eq 2 ]] || fatal "C3 oracle: expected a SECOND CURLOPT_URL for the hostile token (config injection), saw $ora_urls_hostile"
# ...and the shim must agree with the oracle on the SAME hostile token: INJECTED recorded.
run_probe c3-shim-hostile "$(make_synth canonical noguard)" "SYNTH_TOKEN=$HOSTILE"
count_calls "$ROWS/c3-shim-hostile"
shim_injected=0; for f in "$ROWS"/c3-shim-hostile/shim/calls/*.injected; do [[ -s "$f" ]] && shim_injected=1; done
[[ "$shim_injected" -eq 1 ]] || fatal "C3 shim did not record INJECTED for the token the real-curl oracle shows injecting a request"
row "control C3: real-curl oracle (--libcurl): 1 Authorization append (stdin config), 2nd CURLOPT_URL for a hostile token, shim records INJECTED for it" ok

# =====================================================================================
# MUTATION ROWS against SYNTHETIC probes (plan matrix #1-#9), so they run before any real
# conversion exists. Each variant differs from the canonical in exactly one place.
# =====================================================================================
canon_env=("SYNTH_TOKEN=$FIXTURE_TOKEN")
sorted_failed() { [[ -n "$EV_FAILED" ]] && printf '%s\n' $EV_FAILED | sort | paste -sd' ' - || true; }

# 1: revert a converted probe to `-H "Authorization: Bearer ${TOK}"` -> RED on check (ii) SPECIFICALLY.
run_probe m1-revert "$P_ARGV" "${canon_env[@]}"
evaluate "$RUN_ROW" "$SYN_HOST" 1 "$FIXTURE_TOKEN"
if has_check token-in-argv && ! has_check calls-below-min && [[ "$(sorted_failed)" == "bearer-not-on-stdin token-in-argv" ]]; then
  row "mutation 1: reverting a converted probe to an argv bearer is RED on token-in-argv (not on 'no calls')" ok
else row "mutation 1: reverting a converted probe to an argv bearer is RED on token-in-argv (not on 'no calls')" fail "failed='$EV_FAILED'"; fi

# 2: a covered script exits before its curl -> RED on the call-count check.
P_EARLY="$SYN/synth-early-exit.sh"; sed '/^RESP=/i exit 0' "$P_CANON" > "$P_EARLY"
grep -q '^exit 0$' "$P_EARLY" || fatal "mutation 2 did not land (no inserted exit)"
run_probe m2-early "$P_EARLY" "${canon_env[@]}"
evaluate "$RUN_ROW" "$SYN_HOST" 1 "$FIXTURE_TOKEN"
if has_check calls-below-min && [[ "$(sorted_failed)" == "calls-below-min" ]]; then
  row "mutation 2: a probe that exits before its curl is RED on calls-below-min (the recorded failing check)" ok
else row "mutation 2: a probe that exits before its curl is RED on calls-below-min (the recorded failing check)" fail "failed='$EV_FAILED'"; fi

# 3: two curls, first converted, second left on argv, 200 mode so the second is reached -> RED.
P_TWO="$(make_synth two-curls-second-argv)"
run_probe m3-two "$P_TWO" "${canon_env[@]}"
evaluate "$RUN_ROW" "$SYN_HOST" 2 "$FIXTURE_TOKEN"
if has_check token-in-argv && [[ "$EV_HOST_CALLS" -eq 2 ]]; then
  row "mutation 3: first call converted, second left on argv (both reached) is RED on token-in-argv" ok
else row "mutation 3: first call converted, second left on argv (both reached) is RED on token-in-argv" fail "calls=$EV_HOST_CALLS failed='$EV_FAILED'"; fi

# 4: harness mutations. The shim stops recording stdin -> RED; the shim stops being auth-gated ->
# a stripped-header probe reaches PASS, which transient_outcome must catch.
run_probe m4a-nostdin "$P_CANON" "${canon_env[@]}" SHIM_MUTATE=nostdin
evaluate "$RUN_ROW" "$SYN_HOST" 1 "$FIXTURE_TOKEN"
if has_check bearer-not-on-stdin; then row "mutation 4a: a shim that stops recording stdin turns the canonical probe RED" ok
else row "mutation 4a: a shim that stops recording stdin turns the canonical probe RED" fail "failed='$EV_FAILED'"; fi
P_STRIP="$SYN/synth-stripped.sh"; sed 's/Authorization: Bearer/X-Stripped: Bearer/g' "$P_CANON" > "$P_STRIP"
grep -q 'X-Stripped' "$P_STRIP" || fatal "mutation 4 (stripped copy) did not land"
run_probe m4b-noauth "$P_STRIP" "${canon_env[@]}" SHIM_MUTATE=noauth
if transient_outcome "$RUN_ROW" "$RUN_RC"; then
  row "mutation 4b: a shim that stops being auth-gated lets a stripped header reach PASS, and the check sees it" fail "stripped probe still read as TRANSIENT"
else row "mutation 4b: a shim that stops being auth-gated lets a stripped header reach PASS, and the check sees it" ok; fi

# 5: must-PASS shapes that are NOT the canonical: `-H @-` fed by printf, a wrapper (form B), and a
# realistic JWT-shaped token in the allowed charset that must reach the call with the bearer on stdin.
for v in hdrfile wrapper; do
  p="$(make_synth "$v")"
  run_probe "m5-$v" "$p" "${canon_env[@]}"
  rc=$RUN_RC; evaluate "$RUN_ROW" "$SYN_HOST" 1 "$FIXTURE_TOKEN"
  if [[ "$rc" -eq 0 && -z "$EV_FAILED" ]] && grep -q '^PASS' "$RUN_ROW/stdout"; then row "mutation 5: must-PASS shape '$v' is GREEN" ok
  else row "mutation 5: must-PASS shape '$v' is GREEN" fail "rc=$rc failed='$EV_FAILED'"; fi
done
b64u() { printf '%s' "$1" | base64 | tr -d '=\n' | tr '+/' '-_'; }
JWT="$(b64u '{"alg":"HS256","typ":"JWT"}').$(b64u '{"sub":"synthetic-subject-0001"}').$(b64u 'synthetic-signature-0001')"
run_probe m5-jwt "$P_CANON" "SYNTH_TOKEN=$JWT" "SHIM_FIXTURE_TOKEN=$JWT"
rc=$RUN_RC; evaluate "$RUN_ROW" "$SYN_HOST" 1 "$JWT"
if [[ "$rc" -eq 0 && -z "$EV_FAILED" ]] && grep -q '^PASS' "$RUN_ROW/stdout"; then row "mutation 5: a JWT-shaped token in the allowed charset reaches the call, bearer on stdin only" ok
else row "mutation 5: a JWT-shaped token in the allowed charset reaches the call, bearer on stdin only" fail "rc=$rc failed='$EV_FAILED'"; fi

# 6: negative paths: header stripped by a mutated copy, and a 401 from the shim -> TRANSIENT, never PASS.
run_probe m6-stripped "$P_STRIP" "${canon_env[@]}"
if transient_outcome "$RUN_ROW" "$RUN_RC"; then row "mutation 6: a probe copy with the header stripped is TRANSIENT (rc 2, marker on stderr), never PASS" ok
else row "mutation 6: a probe copy with the header stripped is TRANSIENT (rc 2, marker on stderr), never PASS" fail "rc=$RUN_RC"; fi
run_probe m6-401 "$P_CANON" "${canon_env[@]}" SHIM_MODE=deny
if transient_outcome "$RUN_ROW" "$RUN_RC"; then row "mutation 6: a shim 401 on the canonical probe is TRANSIENT (rc 2, marker on stderr), never PASS" ok
else row "mutation 6: a shim 401 on the canonical probe is TRANSIENT (rc 2, marker on stderr), never PASS" fail "rc=$RUN_RC"; fi

# 7: token shapes -> zero calls, no INJECTED, token absent from stderr, TRANSIENT rc.
# MARK is a distinctive substring; grep -F with a multi-line token would match any LINE of it.
tok_for() {
  case "$1" in
    quote-newline-url) printf 'SYNTHMARK0001"\nurl = "http://127.0.0.1:9/second' ;;
    newline-only)      printf 'SYNTHMARK0001\nSYNTHMARK0002' ;;
    non-ascii)         printf 'SYNTHMARK0001\xc3\xa9' ;;
    quote)             printf 'SYNTHMARK0001"x' ;;
    space)             printf 'SYNTHMARK0001 x' ;;
    backslash)         printf 'SYNTHMARK0001\\x' ;;   # 0x5c: one of the three bytes that change real curl's config parse (the Better Stack byte sweep proves it)
    tab)               printf 'SYNTHMARK0001\tx' ;;
    cr)                printf 'SYNTHMARK0001\rx' ;;
    *) fatal "unknown token class $1" ;;
  esac
}
# ONE list of the hostile token classes, so no loop below can carry a narrower population than the guard it exercises
# (a guard admitting a backslash, a tab or a carriage return passed every loop that stopped at the five original classes).
TOK_CLASSES="quote-newline-url newline-only non-ascii quote space backslash tab cr"
# The floor counts DISTINCT, REQUIRED classes, not words: a list of one class, or of eight copies of one class, has eight words and
# narrows every hostile loop to a single shape. class_floor <list> -> rc 0 only when no name repeats and every required class is present.
REQ_TOK_CLASSES="quote-newline-url newline-only non-ascii quote space backslash tab cr"
class_floor() {
  local list="$1" c nwords ndist
  nwords="$(wc -w <<< "$list")"
  ndist="$(tr -s '[:space:]' '\n' <<< "$list" | awk 'NF && !s[$0]++' | wc -l)"
  [[ "$ndist" -eq "$nwords" ]] || return 1
  for c in $REQ_TOK_CLASSES; do [[ " $list " == *" $c "* ]] || return 1; done
  return 0
}
class_floor "$TOK_CLASSES" || { printf '[FATAL] TOK_CLASSES lost a required class or repeats one: %s\n' "$TOK_CLASSES" >&2; exit 2; }
# ...and the floor itself is driven: each of its two clauses (no repeated name, every required class present) fails ALONE.
cf_bad=""
class_floor "$TOK_CLASSES extra-class" || cf_bad+=" [a list with an extra distinct class was rejected]"
class_floor "quote" && cf_bad+=" [one class accepted]"
class_floor "quote quote quote quote quote quote quote quote" && cf_bad+=" [eight copies of one class accepted]"
class_floor "$TOK_CLASSES quote" && cf_bad+=" [a repeated class accepted: the repeat clause is not driven alone]"
class_floor "${TOK_CLASSES/backslash/extra-class}" && cf_bad+=" [a list missing the required backslash class accepted: the presence clause is not driven alone]"
if [[ -z "$cf_bad" ]]; then row "class floor: counts DISTINCT classes and requires every named hostile class (an extra class passes; one class, eight copies of one, a repeated class and a list missing a required class are each rejected alone)" ok
else row "class floor: counts DISTINCT classes and requires every named hostile class (an extra class passes; one class, eight copies of one, a repeated class and a list missing a required class are each rejected alone)" fail "$cf_bad"; fi
# shape_row <label> <probe-script> <tokvar> <class|unset|empty> <rowname> [extra env...]
shape_check() { # sets SHAPE_DETAIL; rc 0 = contract held
  local script="$1" tokvar="$2" cls="$3" name="$4"; shift 4
  local -a e=("$@"); local tv=""
  case "$cls" in
    unset) : ;;
    empty) e+=("$tokvar=") ;;
    *) tv="$(tok_for "$cls")"; e+=("$tokvar=$tv") ;;
  esac
  run_probe "$name" "$script" ${e[@]+"${e[@]}"}
  local rc=$RUN_RC; count_calls "$RUN_ROW"
  SHAPE_DETAIL="rc=$rc calls=$EV_CALLS"
  [[ "$EV_CALLS" -eq 0 ]] || return 1
  [[ ! -e "$RUN_ROW/shim/unexpected" && ! -e "$RUN_ROW/shim/unmodelled" ]] || { SHAPE_DETAIL+=" stub-called"; return 1; }
  transient_outcome "$RUN_ROW" "$rc" || { SHAPE_DETAIL+=" not-TRANSIENT"; return 1; }
  if grep -aq 'SYNTHMARK000' "$RUN_ROW/stdout" "$RUN_ROW/stderr"; then SHAPE_DETAIL+=" token-in-output"; return 1; fi
  return 0
}
for cls in $TOK_CLASSES empty unset; do
  if shape_check "$P_CANON" SYNTH_TOKEN "$cls" "m7-$cls"; then row "mutation 7: synthetic converted probe, token class '$cls': zero calls, TRANSIENT rc 2, token not echoed" ok
  else row "mutation 7: synthetic converted probe, token class '$cls': zero calls, TRANSIENT rc 2, token not echoed" fail "$SHAPE_DETAIL"; fi
done
# ...and the guard-removed mutant is RED: the instrument SEES the injected request line.
P_NOGUARD="$(make_synth canonical noguard)"
run_probe m7-noguard "$P_NOGUARD" "SYNTH_TOKEN=$(tok_for quote-newline-url)"
evaluate "$RUN_ROW" "$SYN_HOST" 1 "SYNTHMARK0001"
if has_check injected; then row "mutation 7: removing the token-shape guard is RED on injected (the shim records the injected config line)" ok
else row "mutation 7: removing the token-shape guard is RED on injected (the shim records the injected config line)" fail "failed='$EV_FAILED'"; fi

# 8: pipe-form mutant under pipefail with a 100,000-byte token and a shim that never reads stdin:
# the converted probe stays rc 0 (the process-substitution writer dies silently); the `printf | curl`
# rewrite can die with 141 (SIGPIPE on the writer, promoted by pipefail; it does at this size, and not for every
# curl that skips its stdin, which is why the row below sizes the token at 100,000 bytes).
BIGTOK="$(head -c 100000 /dev/zero | tr '\0' 'A')"
[[ "${#BIGTOK}" -eq 100000 ]] || fatal "100 KB token was not built (${#BIGTOK})"
run_probe m8-converted "$P_CANON" "SYNTH_TOKEN=$BIGTOK" SHIM_MODE=noread
rc=$RUN_RC
if [[ "$rc" -eq 0 ]] && grep -q '^PASS' "$RUN_ROW/stdout"; then row "mutation 8: converted probe, 100,000-byte token, never-reading shim, pipefail: rc 0" ok
else row "mutation 8: converted probe, 100,000-byte token, never-reading shim, pipefail: rc 0" fail "rc=$rc"; fi
P_PIPE="$(make_synth pipe)"
run_probe m8-pipe "$P_PIPE" "SYNTH_TOKEN=$BIGTOK" SHIM_MODE=noread
rc=$RUN_RC
# 141 is the writer dying of SIGPIPE. A harness that starts this suite with SIGPIPE IGNORED (CI runners do)
# turns the same event into a write error: the builtin printf returns 1 and says "Broken pipe". Both are
# the pipe-form failing where the process-substitution form stayed rc 0, which is the property under test;
# any other non-zero status, or a 1 without the broken-pipe message, is not that event and stays RED.
if [[ "$rc" -eq 141 ]] || { [[ "$rc" -eq 1 ]] && grep -aqi 'broken pipe' "$RUN_ROW/stderr" "$RUN_ROW/stdout" 2>/dev/null; }; then row "mutation 8: pipe-form mutant (printf | curl), same inputs: rc 141 (or 1 with a broken-pipe message when SIGPIPE is ignored)" ok
else row "mutation 8: pipe-form mutant (printf | curl), same inputs: rc 141 (or 1 with a broken-pipe message when SIGPIPE is ignored)" fail "rc=$rc"; fi

# 9: xtrace: SHELLOPTS=xtrace and `bash -x`, token only in env -> refuse rc 78, zero calls, no token on stderr.
xtrace_check() { # <script> <tokvar> <rowname> <mode: env|flag>
  local script="$1" tokvar="$2" name="$3" mode="$4"
  XT_DETAIL=""
  if [[ "$mode" == env ]]; then run_probe "$name" "$script" "$tokvar=$FIXTURE_TOKEN" SHELLOPTS=xtrace
  else RUN_FLAGS=(-x); run_probe "$name" "$script" "$tokvar=$FIXTURE_TOKEN"; RUN_FLAGS=(); fi
  local rc=$RUN_RC; count_calls "$RUN_ROW"
  XT_DETAIL="rc=$rc calls=$EV_CALLS"
  [[ "$rc" -eq 78 && "$EV_CALLS" -eq 0 ]] || return 1
  if grep -aqF -- "$FIXTURE_TOKEN" "$RUN_ROW/stdout" "$RUN_ROW/stderr"; then XT_DETAIL+=" token-on-output"; return 1; fi
  return 0
}
for mode in env flag; do
  if xtrace_check "$P_CANON" SYNTH_TOKEN "m9-$mode" "$mode"; then row "mutation 9: synthetic converted probe refuses xtrace ($mode form): rc 78, zero calls, no token on output" ok
  else row "mutation 9: synthetic converted probe refuses xtrace ($mode form): rc 78, zero calls, no token on output" fail "$XT_DETAIL"; fi
done

# =====================================================================================
# POSITIVE CONTROLS FOR `evaluate`: every failure kind it can name is tripped by a synthetic probe
# that differs from a base probe in exactly one place, and the row asserts that kind fires. Without
# these a kind could be deleted from `evaluate` with the whole battery still green (measured: six of
# the ten kinds had no row that needed them). The exact failed set is asserted too, so a check that
# starts firing on the wrong cause is visible.
# =====================================================================================
# synth_variant <name> <base-probe> <sed args...>: sets SV to a copy of the base probe with ONE edit;
# FATAL if the edit did not land (a variant that equals its base reports the baseline). Sets a global
# rather than printing, because `fatal` inside a command substitution would exit only the subshell.
SV=""
synth_variant() {
  local p="$SYN/synth-var-$1.sh" base="$2"; shift 2
  sed "$@" "$base" > "$p"
  if cmp -s "$p" "$base"; then fatal "synthetic variant $1 did not land (sed $*)"; fi
  SV="$p"
}
# kind_check <probe> <kind> <expected sorted failed set> <rowname>: rc 0 only when the probe is RED on
# `kind` AND the sorted failed set is EXACTLY the expected one. Split from `kind_row` so a control can
# drive it with a probe that trips two kinds and require rc 1 (the exact-set half is otherwise unseen:
# every kind_row probe trips exactly the expected set, so dropping the comparison stayed green).
kind_check() {
  local probe="$1" kind="$2" want="$3" name="$4"
  run_probe "$name" "$probe" "${canon_env[@]}"
  evaluate "$RUN_ROW" "$SYN_HOST" 1 "$FIXTURE_TOKEN"
  has_check "$kind" && [[ "$(sorted_failed)" == "$want" ]]
}
# kind_row <label> <probe> <kind> <expected sorted failed set>
kind_row() {
  local label="$1" probe="$2" kind="$3" want="$4"
  if kind_check "$probe" "$kind" "$want" "k-$kind"; then row "evaluate: $label is RED on '$kind' (failed set exactly '$want')" ok
  else row "evaluate: $label is RED on '$kind' (failed set exactly '$want')" fail "failed='$EV_FAILED'"; fi
}
synth_variant jqarg "$P_CANON" '/^RESP=/i jq -n --arg t "$SYNTH_TOKEN" 1 >/dev/null'
kind_row "a probe that hands the token to jq as --arg" "$SV" token-in-jq-argv "token-in-jq-argv"
synth_variant host "$P_CANON" 's/synthetic\.example\.test/elsewhere.example.test/'
kind_row "a probe that calls a host outside the manifest" "$SV" unexpected-host "calls-below-min unexpected-host"
synth_variant tool "$P_CANON" '/^RESP=/i gh issue list >/dev/null || true'
kind_row "a probe that calls a fail-closed gh/doppler/ssh stub" "$SV" unexpected-tool "unexpected-tool"
synth_variant flag "$P_CANON" 's/--disable /--disable --retry-all-errors /'
kind_row "a probe that uses a curl flag the shim does not model" "$SV" unmodelled-flag "calls-below-min unexpected-host unmodelled-flag"
synth_variant leak "$P_CANON" '/^RESP=/i echo "leak=$SYNTH_TOKEN"'
kind_row "a probe that echoes the token to its output" "$SV" token-in-output "token-in-output"
synth_variant basherr "$P_CANON" '/^RESP=/i synthetic_missing_command_for_bash_error'
kind_row "a probe that trips a bash error" "$SV" bash-error "bash-error"

# CONTROL for kind_row's exact-set assertion: ONE probe that trips TWO kinds. Expecting only one of them
# must be rejected (the set is not exact); expecting both must be accepted (the probe really trips both).
synth_variant twokinds "$P_CANON" -e '/^RESP=/i echo "leak=$SYNTH_TOKEN"' -e '/^RESP=/i gh issue list >/dev/null || true'
kc_one=0; kc_both=0
kind_check "$SV" token-in-output "token-in-output" kc-twokinds-one && kc_one=1
kind_check "$SV" token-in-output "token-in-output unexpected-tool" kc-twokinds-both && kc_both=1
if [[ "$kc_one" -eq 0 && "$kc_both" -eq 1 ]]; then row "evaluate: kind_row's exact-set assertion rejects a probe that trips two kinds when only one is expected (and accepts the full set)" ok
else row "evaluate: kind_row's exact-set assertion rejects a probe that trips two kinds when only one is expected (and accepts the full set)" fail "one-kind-accepted=$kc_one both-kinds-accepted=$kc_both failed='$EV_FAILED'"; fi

# CONTROL for synth_variant's landing guard: an edit whose anchor has drifted (the sed matches nothing)
# must FAIL LOUDLY (rc 2 and a "did not land" message), never hand back a copy equal to its base, which
# would let a mutation row report the baseline. Run in a subshell: `fatal` exits.
sv_rc=0
( synth_variant drifted "$P_CANON" 's/NO-SUCH-ANCHOR-IN-THE-BASE-PROBE/x/' ) > /dev/null 2> "$TMPD/sv-drift.err" || sv_rc=$?
if [[ "$sv_rc" -eq 2 ]] && grep -q 'did not land' "$TMPD/sv-drift.err"; then row "synth_variant: an edit whose anchor drifted (no change) fails loudly (rc 2, 'did not land'), never reports the baseline" ok
else row "synth_variant: an edit whose anchor drifted (no change) fails loudly (rc 2, 'did not land'), never reports the baseline" fail "rc=$sv_rc"; fi

# CONTROLS for the outcome helpers (each check inside them has a row that needs it).
# transient_outcome: one fabricated row dir per case, so every clause is exercised alone.
tc_case() { # <name> <rc> <stdout> <stderr> -> transient_outcome's rc
  local d="$ROWS/tc-$1"; assert_fixture_dir "$d"; mkdir -p "$d"
  printf '%s' "$3" > "$d/stdout"; printf '%s' "$4" > "$d/stderr"
  transient_outcome "$d" "$2"
}
tc_bad=""
tc_case good 2 "" $'TRANSIENT: x\n' || tc_bad+=" good-rejected"
tc_case pass-line 2 $'PASS: 0 events\n' $'TRANSIENT: x\n' && tc_bad+=" PASS-accepted"
tc_case no-marker 2 "" $'something else\n' && tc_bad+=" no-marker-accepted"
tc_case bash-error 2 "" $'TRANSIENT: x\nsynth.sh: line 3: boom: command not found\n' && tc_bad+=" bash-error-accepted"
tc_case rc1 1 "" $'TRANSIENT: x\n' && tc_bad+=" rc1-accepted"
if [[ -z "$tc_bad" ]]; then row "transient_outcome: accepts rc 2 + marker, and rejects a PASS line, a missing TRANSIENT marker, a bash error and rc 1 each on its own" ok
else row "transient_outcome: accepts rc 2 + marker, and rejects a PASS line, a missing TRANSIENT marker, a bash error and rc 1 each on its own" fail "$tc_bad"; fi

# shape_check: a probe that echoes the unusable token into its TRANSIENT message must be refused for THAT
# cause (zero calls, rc 2 and the marker all hold, so only the token-in-output check can reject it).
synth_variant tokecho "$P_CANON" 's/echo "TRANSIENT: token unusable"/echo "TRANSIENT: token unusable $SYNTH_TOKEN"/'
if ! shape_check "$SV" SYNTH_TOKEN quote m7c-tokecho && [[ "$SHAPE_DETAIL" == *token-in-output* ]]; then row "shape_check: a probe that echoes the unusable token on its TRANSIENT path is refused on token-in-output" ok
else row "shape_check: a probe that echoes the unusable token on its TRANSIENT path is refused on token-in-output" fail "$SHAPE_DETAIL"; fi
# shape_check: the token-shape guard removed, so the call is made (a 401 -> TRANSIENT rc 2): only the
# zero-calls check can refuse it.
if ! shape_check "$P_NOGUARD" SYNTH_TOKEN quote m7c-noguard && [[ "$SHAPE_DETAIL" == "rc=2 calls=1" ]]; then row "shape_check: a probe without the token-shape guard that still reaches its TRANSIENT path is refused on the zero-calls check" ok
else row "shape_check: a probe without the token-shape guard that still reaches its TRANSIENT path is refused on the zero-calls check" fail "$SHAPE_DETAIL"; fi
# xtrace_check: a probe that refuses xtrace with zero calls and no token on output but with the WRONG
# status (1, not 78) must be refused: only the rc 78 clause can see it.
synth_variant xt1 "$P_CANON" 's/exit 78/exit 1/'
if ! xtrace_check "$SV" SYNTH_TOKEN m9c-rc1 env && [[ "$XT_DETAIL" == "rc=1 calls=0" ]]; then row "xtrace_check: a probe that refuses xtrace with the wrong status (1, not 78) is refused" ok
else row "xtrace_check: a probe that refuses xtrace with the wrong status (1, not 78) is refused" fail "$XT_DETAIL"; fi

# The stdin bearer check is an EXACT-LINE match (`grep -qxF`), not a substring match: a line that
# merely CONTAINS the expected header text, with trailing junk, must be rejected, in BOTH accepted
# forms (the `--config -` directive and the `-H @-` header line).
synth_variant junk-cfg "$P_CANON" 's/%s"\\n/%s"x\\n/'
run_probe x1-junk-cfg "$SV" "${canon_env[@]}"
grep -aqF -- "header = \"Authorization: Bearer $FIXTURE_TOKEN\"x" "$RUN_ROW/shim/calls/1.stdin" || fatal "junk-cfg variant did not put the junk line on stdin"
evaluate "$RUN_ROW" "$SYN_HOST" 1 "$FIXTURE_TOKEN"
if has_check bearer-not-on-stdin; then row "evaluate: a --config stdin line that merely CONTAINS the expected directive (trailing junk) is rejected (exact-line match)" ok
else row "evaluate: a --config stdin line that merely CONTAINS the expected directive (trailing junk) is rejected (exact-line match)" fail "failed='$EV_FAILED'"; fi
P_HDRFILE="$(make_synth hdrfile)"
synth_variant junk-hdr "$P_HDRFILE" 's/Bearer %s\\n/Bearer %sjunk\\n/'
run_probe x2-junk-hdr "$SV" "${canon_env[@]}"
grep -aqF -- "Authorization: Bearer ${FIXTURE_TOKEN}junk" "$RUN_ROW/shim/calls/1.stdin" || fatal "junk-hdr variant did not put the junk line on stdin"
evaluate "$RUN_ROW" "$SYN_HOST" 1 "$FIXTURE_TOKEN"
if has_check bearer-not-on-stdin; then row "evaluate: a -H @- stdin line that merely CONTAINS the expected header (trailing junk) is rejected (exact-line match)" ok
else row "evaluate: a -H @- stdin line that merely CONTAINS the expected header (trailing junk) is rejected (exact-line match)" fail "failed='$EV_FAILED'"; fi

# =====================================================================================
# STAGE 2: THE MANIFEST, KEYED OFF BASELINE E
# =====================================================================================
BASE_E="scripts/lint-shell-trace-credential-refusal-e.baseline.txt"
[[ -f "$BASE_E" ]] || fatal "baseline E is missing ($BASE_E); the population row reads it"

# DYNAMIC: name | token env var | hosts (regex) | min_calls | canned 200 body. Outcome contract of
# every row: the OK body reaches `^PASS` with rc 0; a 401 / stripped header / unusable token is
# TRANSIENT rc 2. Members hold ONE credentialed curl except accounted-beacon (three queries).
DYN_MANIFEST='ac10-workspace-reconcile-sentry-4246|SENTRY_ACTIONS_RO_TOKEN|sentry\.io|1|sentry_empty
ac8-founder-ambiguous-soak-5673|SENTRY_ACTIONS_RO_TOKEN|sentry\.io|1|sentry_empty
accounted-beacon-live-6462|SENTRY_ACTIONS_RO_TOKEN|sentry\.io|3|sentry_events
community-monitor-checkin-soak-5728|SENTRY_ACTIONS_RO_TOKEN|de\.sentry\.io|1|checkins
dashboard-cold-tiers-8978|SENTRY_ACTIONS_RO_TOKEN|sentry\.io|1|sentry_empty
reconcile-ff-only-sentry-4977|SENTRY_ACTIONS_RO_TOKEN|sentry\.io|1|sentry_empty
autovacuum-thrash-6168|SUPABASE_ACCESS_TOKEN|api\.supabase\.com|1|autovac
concurrency-slot-wal-backoff|SUPABASE_ACCESS_TOKEN|api\.supabase\.com|1|slots
l3-probe-armed-6438|BETTERSTACK_API_TOKEN|uptime\.betterstack\.com|1|bs_up
web2-standby-soak-6459|BETTERSTACK_API_TOKEN|uptime\.betterstack\.com|1|bs_up'

# STATIC-ONLY: name | kind | argument | justification. Each carries a row that goes RED when
# the probe becomes hermetically reachable (so it must move to the dynamic manifest).
#   placeholder  runs under the shim and must make ZERO calls (RED the day the placeholder is pinned)
#   fixed-tmp    must still name the fixed path (RED the day the fixed /tmp write is gone)
#   gh-chained   must still call gh issue/pr/api (the second curl is only reachable through a gh model)
#   bs-chained   must still chain into the named script (a second credentialed tool)
#   env-gated    runs under env -i and must refuse with zero calls + a TRANSIENT marker while still
#                naming its arg as the required-secret gate set (RED the day the credentialed legs
#                are reachable without the env, or the gate set changes)
STATIC_MANIFEST='phase3-ga-soak-5274|placeholder|<POST_CUTOVER_UTC>|exits TRANSIENT on the literal START placeholder before any curl; a hermetic run can never reach its credentialed call
sentry-checkins-3859|fixed-tmp|/tmp/ck.json|writes the fixed path /tmp/ck.json, which a hermetic row must not touch
sync-health-residual-5689|fixed-tmp|/tmp/sh5689.json|writes the fixed path /tmp/sh5689.json, which a hermetic row must not touch
cron-machinery-soak-9272|gh-chained|gh|its second and third credentialed curls (-D header file, paging) are reachable only through a gh issue/pr/api model; the fail-closed gh stub makes it exit TRANSIENT after the first call
zot-soak-6122|gh-chained|gh|its credentialed curl sits behind START-anchor and blocker arms that call gh pr/issue view; unreachable under a fail-closed gh stub
workspaces-luks-soak-6604|bs-chained|betterstack-query.sh|after the Sentry call it chains into betterstack-query.sh, a second credentialed tool with basic auth that this shim does not model
egress-enforce-probe-11361|gh-chained|gh|its second credentialed read (the post-merge birth evidence) is a gh api workflow-runs query, reachable only through a gh model the fail-closed gh stub does not provide
ga-lb-pool-soak-6027|env-gated|CF_API_TOKEN CF_ACCOUNT_ID|its CF and Better Stack credentialed curls sit behind required-secret and deploy-anchor gates; under env -i it exits TRANSIENT (rc 3) before any call — no hermetic path reaches the bearer'

# DELEGATED: name | owning test (extended in place by the conversion; not re-modelled here).
DELEGATED_MANIFEST='post-deploy-incident-soak|scripts/followthroughs/post-deploy-incident-soak.test.sh
anthropic-admin-key-6297|scripts/followthroughs/anthropic-admin-key-6297.test.sh
cwv-field-rum-9178|scripts/followthroughs/cwv-field-rum-9178.test.sh
send-failed-alert-probe-8097|scripts/followthroughs/send-failed-alert-probe-8097.test.sh
betterstack-roundtrip-latency-7855|tests/scripts/test-betterstack-roundtrip-latency.sh
git-data-rehearsal-evidence|scripts/followthroughs/git-data-rehearsal-evidence.test.sh
discord-blog-webhook-fallback|scripts/followthroughs/discord-blog-webhook-fallback.test.sh
dispatch-recovery-sweeper-11211|scripts/followthroughs/dispatch-recovery-sweeper-11211.test.sh
egress-gw-probe-silent-12180|scripts/followthroughs/egress-gw-probe-silent-12180.test.sh'

# HMAC (S2-C): the probes that carry the deploy-webhook triple (X-Signature-256 + the Cloudflare Access pair) on the stdin
# config channel: name | kind | hosts | min_calls | body | owning test. Only `delegated` rows remain, so the hosts, min_calls and
# body columns are reserved and stay empty (the loop below still reads them). `delegated` probes keep their own suite, and the delegation row asserts that the suite RECORDS stdin and asserts the three header lines (a probe cannot
# pass while sending no credential). The `dynamic` kind (no owning suite, run under the `hmac-cf` shim profile) was retired with the
# last probe that used it (G1 PR-4a, #10937; history in git).
HMAC_MANIFEST='inngest-soak-6178|delegated|||none|scripts/followthroughs/inngest-soak-6178.test.sh
sdk-bash-smoke-verdict-10548|delegated|||none|scripts/followthroughs/sdk-bash-smoke-verdict-10548.test.sh'

# --- the DERIVED population: tracked followthrough probes holding a credentialed curl ---------
derive_population() {
  local f
  git ls-files 'scripts/followthroughs/*.sh' | while IFS= read -r f; do
    case "$f" in *.test.sh) continue ;; esac
    [[ -f "$f" ]] || continue
    if grep -qE -e 'Authorization: *Bearer' -e '--config -' -e '-K -' "$f"; then basename "$f" .sh; fi
  done | sort -u
}
POP="$(derive_population)"
CLASSIFIED="$({ printf '%s\n' "$DYN_MANIFEST" | cut -d'|' -f1; printf '%s\n' "$STATIC_MANIFEST" | cut -d'|' -f1; printf '%s\n' "$DELEGATED_MANIFEST" | cut -d'|' -f1; printf '%s\n' "$HMAC_MANIFEST" | cut -d'|' -f1; } | sort)"
DUP="$(printf '%s\n' "$CLASSIFIED" | uniq -d)"
UNCLASSIFIED="$(comm -23 <(printf '%s\n' "$POP") <(printf '%s\n' "$CLASSIFIED" | sort -u))"
STALE_ENTRY="$(comm -13 <(printf '%s\n' "$POP") <(printf '%s\n' "$CLASSIFIED" | sort -u))"
if [[ -n "$POP" && -z "$DUP" && -z "$UNCLASSIFIED" && -z "$STALE_ENTRY" ]]; then
  row "population: every followthrough probe holding a credentialed curl is classified exactly once (dynamic, static-only or delegated)" ok
else
  row "population: every followthrough probe holding a credentialed curl is classified exactly once (dynamic, static-only or delegated)" fail "unclassified='${UNCLASSIFIED//$'\n'/,}' stale='${STALE_ENTRY//$'\n'/,}' duplicated='${DUP//$'\n'/,}' derived=$(printf '%s\n' "$POP" | grep -c . || true)"
fi
# DISJOINTNESS (replaces "baseline E followthrough rows equal the S2-owned list", which only held in the commit that emptied
# the list). A followthrough probe converted to the BEARER or the HMAC form (classified in the dynamic, static-only, delegated
# or HMAC manifest above) must not also be listed in baseline E: a listed one is an argv credential that crept back. Baseline E
# no longer lists the HMAC probes (the baseline-only commit removed them), so the HMAC manifest is part of the converted
# set now; re-adding one probe to baseline E is a red row. The extractor is a function so a positive control can drive it.
be_followthrough_rows() { # <baseline file> -> followthrough probe names listed in it, one per line
  awk -F'\t' '!/^#/ && $1 ~ /^scripts\/followthroughs\// {print $1}' "$1" | sed 's|^scripts/followthroughs/||; s|\.sh$||' | sort -u
}
BEARER_CONVERTED="$({ printf '%s\n' "$DYN_MANIFEST" | cut -d'|' -f1; printf '%s\n' "$STATIC_MANIFEST" | cut -d'|' -f1; printf '%s\n' "$DELEGATED_MANIFEST" | cut -d'|' -f1; printf '%s\n' "$HMAC_MANIFEST" | cut -d'|' -f1; } | sort -u)"
BE_FOLLOWTHROUGH="$(be_followthrough_rows "$BASE_E")"
BE_OVERLAP="$(comm -12 <(printf '%s\n' "$BE_FOLLOWTHROUGH") <(printf '%s\n' "$BEARER_CONVERTED") | grep . || true)"
if [[ -z "$BE_OVERLAP" && -n "$BEARER_CONVERTED" ]]; then row "population: no followthrough probe is both listed in baseline E and classified as converted (disjointness)" ok
else row "population: no followthrough probe is both listed in baseline E and classified as converted (disjointness)" fail "listed AND converted='${BE_OVERLAP//$'\n'/,}'"; fi
# positive control: the extractor really returns a followthrough row from a synthetic baseline (an empty overlap cannot be a broken extractor)
printf '# header\nscripts/followthroughs/synthetic-probe-0001.sh\t2\nscripts/other/not-a-probe.sh\t1\n' > "$TMPD/synthetic-baseline-e.txt"
SYN_BE="$(be_followthrough_rows "$TMPD/synthetic-baseline-e.txt")"
if [[ "$SYN_BE" == "synthetic-probe-0001" ]]; then row "population control: the baseline-E extractor returns the followthrough row of a synthetic baseline and ignores a non-followthrough row" ok
else row "population control: the baseline-E extractor returns the followthrough row of a synthetic baseline and ignores a non-followthrough row" fail "extracted='${SYN_BE//$'\n'/,}'"; fi
# the disjointness check can fire: a synthetic overlap (a bearer-converted probe listed in a synthetic baseline) is reported
SYN_FIRST="$(printf '%s\n' "$BEARER_CONVERTED" | head -n1)"
SYN_OV="$(comm -12 <(printf '%s\n' "$SYN_FIRST") <(printf '%s\n' "$BEARER_CONVERTED") | grep . || true)"
if [[ -n "$SYN_FIRST" && "$SYN_OV" == "$SYN_FIRST" ]]; then row "population control: the overlap comparison reports a converted probe that is listed (it can fire)" ok
else row "population control: the overlap comparison reports a converted probe that is listed (it can fire)" fail "overlap='$SYN_OV'"; fi
# ...and for an HMAC-manifest probe specifically (the case the converted set used to exclude): a synthetic baseline that lists the
# first HMAC probe is extracted and reported as the overlap.
SYN_HM_FIRST="$(printf '%s\n' "$HMAC_MANIFEST" | cut -d'|' -f1 | head -n1)"
printf '# header\nscripts/followthroughs/%s.sh\t2\n' "$SYN_HM_FIRST" > "$TMPD/synthetic-baseline-e-hmac.txt"
SYN_HM_OV="$(comm -12 <(be_followthrough_rows "$TMPD/synthetic-baseline-e-hmac.txt") <(printf '%s\n' "$BEARER_CONVERTED") | grep . || true)"
if [[ -n "$SYN_HM_FIRST" && "$SYN_HM_OV" == "$SYN_HM_FIRST" ]]; then row "population control: an HMAC probe re-added to baseline E is reported by the disjointness comparison (the HMAC manifest is part of the converted set)" ok
else row "population control: an HMAC probe re-added to baseline E is reported by the disjointness comparison (the HMAC manifest is part of the converted set)" fail "hmac-first='$SYN_HM_FIRST' overlap='$SYN_HM_OV'"; fi

# --- DYNAMIC rows ----------------------------------------------------------------------------
N_DYN=0
probe_rows() { # name tokvar hosts min body
  local name="$1" tokvar="$2" hosts="$3" min="$4" body="$5"
  local rel="scripts/followthroughs/$name.sh" script="$REPO_ROOT/scripts/followthroughs/$name.sh" rc
  N_DYN=$((N_DYN + 1))
  if [[ ! -f "$script" ]]; then row "$name: manifest entry names an existing probe" fail "$rel is missing"; return 0; fi
  local -a okenv=("$tokvar=$FIXTURE_TOKEN" "SHIM_BODY_FILE=$BODIES/$body.json")

  # A. the full contract
  run_probe "$name-A" "$script" "${okenv[@]}"
  rc=$RUN_RC; evaluate "$RUN_ROW" "$hosts" "$min" "$FIXTURE_TOKEN"
  local outcome_ok=0; [[ "$rc" -eq 0 ]] && grep -q '^PASS' "$RUN_ROW/stdout" && outcome_ok=1
  if [[ "$outcome_ok" -eq 1 && -z "$EV_FAILED" ]]; then
    row "$name: full contract (every call to the manifest hosts has the bearer on stdin, token in no argv, >= $min call(s))" ok
  else row "$name: full contract (every call to the manifest hosts has the bearer on stdin, token in no argv, >= $min call(s))" fail "rc=$rc calls=$EV_HOST_CALLS failed='$EV_FAILED'"; fi

  # B. a 401 must never reach the PASS outcome
  run_probe "$name-B" "$script" "${okenv[@]}" SHIM_MODE=deny
  if transient_outcome "$RUN_ROW" "$RUN_RC" && [[ ! -e "$RUN_ROW/shim/unexpected" && ! -e "$RUN_ROW/shim/unmodelled" ]]; then
    row "$name: a 401 never reaches PASS (rc 2, TRANSIENT on stderr)" ok
  else row "$name: a 401 never reaches PASS (rc 2, TRANSIENT on stderr)" fail "rc=$RUN_RC"; fi

  # C. header stripped by a mutated COPY of the real probe
  local cdir="$ROWS/$name-C-copy"; assert_fixture_dir "$cdir"; mkdir -p "$cdir"
  sed 's/Authorization: Bearer/X-Stripped: Bearer/g' "$script" > "$cdir/$name.sh"
  if ! grep -q 'X-Stripped' "$cdir/$name.sh"; then row "$name: header-stripped copy" fail "the sed did not land; the probe has no 'Authorization: Bearer' text"
  else
    run_probe "$name-C" "$cdir/$name.sh" "${okenv[@]}"
    if transient_outcome "$RUN_ROW" "$RUN_RC"; then row "$name: a header-stripped copy never reaches PASS (rc 2, TRANSIENT on stderr)" ok
    else row "$name: a header-stripped copy never reaches PASS (rc 2, TRANSIENT on stderr)" fail "rc=$RUN_RC"; fi
  fi

  # D. unset and empty token: zero calls, TRANSIENT rc 2
  local cls d_ok=1 d_detail=""
  for cls in unset empty; do
    shape_check "$script" "$tokvar" "$cls" "$name-D-$cls" "SHIM_BODY_FILE=$BODIES/$body.json" || { d_ok=0; d_detail+=" [$cls: $SHAPE_DETAIL]"; }
  done
  if [[ "$d_ok" -eq 1 ]]; then row "$name: an unset or empty token produces zero calls and a TRANSIENT rc 2" ok
  else row "$name: an unset or empty token produces zero calls and a TRANSIENT rc 2" fail "$d_detail"; fi

  # CONVERTED-ONLY rows: they assert properties a conversion adds, so they switch on when the
  # probe leaves baseline E (rows only grow; EXPECTED_TESTS is a lower bound).

  # E1. hostile token shapes
  local e_ok=1 e_detail=""
  for cls in $TOK_CLASSES; do
    shape_check "$script" "$tokvar" "$cls" "$name-E1-$cls" "SHIM_BODY_FILE=$BODIES/$body.json" || { e_ok=0; e_detail+=" [$cls: $SHAPE_DETAIL]"; }
  done
  if [[ "$e_ok" -eq 1 ]]; then row "$name: hostile tokens (quote+newline+url, newline-only, non-ASCII, quote, space, backslash, tab, CR) produce zero calls, TRANSIENT rc 2, no INJECTED, token not echoed" ok
  else row "$name: hostile tokens (quote+newline+url, newline-only, non-ASCII, quote, space, backslash, tab, CR) produce zero calls, TRANSIENT rc 2, no INJECTED, token not echoed" fail "$e_detail"; fi
  # E2/E3. xtrace refusal
  for mode in env flag; do
    if xtrace_check "$script" "$tokvar" "$name-E-xtrace-$mode" "$mode"; then row "$name: refuses xtrace ($mode form): rc 78, zero calls, no token on output" ok
    else row "$name: refuses xtrace ($mode form): rc 78, zero calls, no token on output" fail "$XT_DETAIL"; fi
  done
  # E4. 100,000-byte token, never-reading shim, pipefail: a converted probe is unaffected
  run_probe "$name-E4" "$script" "$tokvar=$BIGTOK" "SHIM_BODY_FILE=$BODIES/$body.json" SHIM_MODE=noread
  # A 64-byte PREFIX stands in for the 100 KB token in the greps: `grep -F` with a 100,000-byte
  # pattern is pathologically slow (measured: minutes), and the token being in argv implies its
  # prefix is.
  rc=$RUN_RC; evaluate "$RUN_ROW" "$hosts" 0 "${BIGTOK:0:64}"
  if [[ "$rc" -eq 0 ]] && grep -q '^PASS' "$RUN_ROW/stdout" && ! has_check token-in-argv; then
    row "$name: a 100,000-byte token with a never-reading shim under pipefail: rc 0 (no pipe-form SIGPIPE), token in no argv" ok
  else row "$name: a 100,000-byte token with a never-reading shim under pipefail: rc 0 (no pipe-form SIGPIPE), token in no argv" fail "rc=$rc failed='$EV_FAILED'"; fi
  # E5/E6. harness mutations against the real converted probe: RED for every row
  run_probe "$name-E5" "$script" "${okenv[@]}" SHIM_MUTATE=nostdin
  evaluate "$RUN_ROW" "$hosts" "$min" "$FIXTURE_TOKEN"
  if has_check bearer-not-on-stdin; then row "$name: a shim that stops recording stdin turns this row RED" ok
  else row "$name: a shim that stops recording stdin turns this row RED" fail "failed='$EV_FAILED'"; fi
  run_probe "$name-E6" "$cdir/$name.sh" "${okenv[@]}" SHIM_MUTATE=noauth
  if transient_outcome "$RUN_ROW" "$RUN_RC"; then row "$name: a shim that stops being auth-gated lets the stripped copy reach PASS, and the check sees it" fail "stripped copy still TRANSIENT"
  else row "$name: a shim that stops being auth-gated lets the stripped copy reach PASS, and the check sees it" ok; fi
}
while IFS='|' read -r m_name m_tokvar m_hosts m_min m_body; do
  [[ -n "$m_name" ]] || continue
  probe_rows "$m_name" "$m_tokvar" "$m_hosts" "$m_min" "$m_body"
done <<< "$DYN_MANIFEST"

# --- STATIC-ONLY rows -----------------------------------------------------------------------
N_STATIC=0
while IFS='|' read -r s_name s_kind s_arg s_why; do
  [[ -n "$s_name" ]] || continue
  N_STATIC=$((N_STATIC + 1))
  s_script="$REPO_ROOT/scripts/followthroughs/$s_name.sh"
  if [[ ! -f "$s_script" ]]; then row "static-only $s_name: names an existing probe" fail "missing"; continue; fi
  case "$s_kind" in
    placeholder)
      run_probe "$s_name-S" "$s_script" "SENTRY_ACTIONS_RO_TOKEN=$FIXTURE_TOKEN"
      count_calls "$RUN_ROW"
      if grep -qF -- "$s_arg" "$s_script" && [[ "$EV_CALLS" -eq 0 && "$RUN_RC" -eq 2 ]]; then
        row "static-only $s_name: still unreachable (placeholder $s_arg, rc 2, zero calls) -- $s_why" ok
      else row "static-only $s_name: still unreachable (placeholder $s_arg, rc 2, zero calls)" fail "rc=$RUN_RC calls=$EV_CALLS: the probe is now hermetically reachable; move it to the dynamic manifest" ; fi ;;
    fixed-tmp)
      if grep -qF -- "$s_arg" "$s_script"; then row "static-only $s_name: still writes the fixed path $s_arg -- $s_why" ok
      else row "static-only $s_name: still writes the fixed path $s_arg" fail "the fixed path is gone: the probe is now hermetically reachable; move it to the dynamic manifest"; fi ;;
    gh-chained)
      # `grep -q` over a PROCESS SUBSTITUTION, not a pipe: under pipefail the early-exiting -q
      # SIGPIPEs the upstream grep on a large file and reads as "no match" (measured on zot-soak).
      if grep -qE '(^|[^[:alnum:]_-])gh (issue|pr|api)' < <(grep -vE '^[[:space:]]*#' "$s_script"); then row "static-only $s_name: still chained behind gh -- $s_why" ok
      else row "static-only $s_name: still chained behind gh" fail "no gh issue/pr/api call remains: the probe is now hermetically reachable; move it to the dynamic manifest"; fi ;;
    bs-chained)
      if grep -qF -- "$s_arg" < <(grep -vE '^[[:space:]]*#' "$s_script"); then row "static-only $s_name: still chained into $s_arg -- $s_why" ok
      else row "static-only $s_name: still chained into $s_arg" fail "the chain is gone: the probe is now hermetically reachable; move it to the dynamic manifest"; fi ;;
    env-gated)
      # The credentialed legs sit behind required-secret (and deploy-anchor) gates that fire BEFORE
      # any curl; under env -i the probe refuses with zero calls and a TRANSIENT marker. The arg pins
      # the literal gate set (`for v in $s_arg`); a probe that ever reaches the shim or exits 0 is
      # hermetically reachable and must move to the dynamic manifest.
      run_probe "$s_name-S" "$s_script"
      count_calls "$RUN_ROW"
      if grep -qF -- "$s_arg" "$s_script" && [[ "$EV_CALLS" -eq 0 && "$RUN_RC" -ne 0 && ! -e "$RUN_ROW/shim/unexpected" && ! -e "$RUN_ROW/shim/unmodelled" ]] && grep -q 'TRANSIENT' "$RUN_ROW/stderr"; then
        row "static-only $s_name: still unreachable (env gate $s_arg, rc $RUN_RC, zero calls) -- $s_why" ok
      else row "static-only $s_name: still unreachable (env gate $s_arg, zero calls)" fail "rc=$RUN_RC calls=$EV_CALLS: the probe is now hermetically reachable; move it to the dynamic manifest"; fi ;;
    *) row "static-only $s_name: known kind" fail "unknown kind '$s_kind'" ;;
  esac
done <<< "$STATIC_MANIFEST"

# --- DELEGATED rows -------------------------------------------------------------------------
N_DELEGATED=0
while IFS='|' read -r d_name d_test; do
  [[ -n "$d_name" ]] || continue
  N_DELEGATED=$((N_DELEGATED + 1))
  if [[ -f "$d_test" ]] && git ls-files --error-unmatch -- "$d_test" >/dev/null 2>&1 && grep -qF -- "$d_name" "$d_test"; then
    row "delegated $d_name: owning test $d_test exists, is tracked and names the probe" ok
  else row "delegated $d_name: owning test $d_test exists, is tracked and names the probe" fail "the owning test is missing, untracked or no longer names the probe"; fi
done <<< "$DELEGATED_MANIFEST"

echo "=== manifest: $N_DYN dynamic, $N_STATIC static-only, $N_DELEGATED delegated; population $(printf '%s\n' "$POP" | grep -c . || true) ==="

# =====================================================================================
# STAGE 3: THE LIVE-IN-APPLY INFRA SCRIPTS (#9597). Two scripts run by the push-triggered
# infra apply carried a bearer on curl's argv; the changed transport is proven HERE, before
# merge, by running each under the PATH-shim curl:
#   fresh-host-boot-trail.sh   two Sentry reads (org events query + polled project read)
#   verify-tunnel-ingress-origin.sh  two calls: the Cloudflare config read (Bearer) and the
#                              deploy-status read (webhook HMAC + CF Access id/secret headers)
# A failure of the second blocks the apply, so its refusal path is exercised too.
# =====================================================================================
INFRA_SCRIPTS="$REPO_ROOT/apps/web-platform/infra/scripts"
FHBT="$INFRA_SCRIPTS/fresh-host-boot-trail.sh"
VTIO="$INFRA_SCRIPTS/verify-tunnel-ingress-origin.sh"
[[ -f "$FHBT" && -f "$VTIO" ]] || fatal "stage 3: the live-in-apply scripts are missing ($FHBT, $VTIO)"
printf '%s' '[]' > "$BODIES/empty_array.json"
printf '%s' '{"data":[{"timestamp":"2026-10-01T00:00:00+00:00","stage":"app_zot","host_name":"soleur-web-9","detail":"synthetic"}]}' > "$BODIES/origin_event.json"
printf '%s' '{"success":true,"result":{"config":{"ingress":[{"hostname":"deploy.soleur.example","service":"http://10.0.1.10:9000"},{"hostname":"ssh.soleur.example","service":"ssh://10.0.1.10:22"},{"service":"http_status:404"}]}}}' > "$BODIES/cf_tunnel_cfg.json"

# mutated_copy <script> <outfile> <from-literal> <to-literal>: a copy with ONE literal replaced;
# FATAL if the literal is absent (a mutation that does not land reports the baseline, which is
# indistinguishable from a pass).
mutated_copy() {
  local src="$1" out="$2" from="$3" to="$4" text
  text="$(cat "$src"; printf x)"; text="${text%x}"
  [[ "$text" == *"$from"* ]] || fatal "mutation did not land: '${from:0:60}...' not found in $src"
  assert_fixture_dir "$out"
  printf '%s' "${text/"$from"/"$to"}" > "$out"
}
assert_fixture_dir "$SYN"
BEARER_FN='_bearer_ok() { local LC_ALL=C; case "${1:-}" in '"''"'|*[!A-Za-z0-9._~+/=-]*) return 1 ;; esac; }'

# --- fresh-host-boot-trail.sh ------------------------------------------------------------------
trail_env() { # <rowname> -> prints NAME=value args for run_probe (summary file lives in the row dir)
  printf '%s\n' "GITHUB_STEP_SUMMARY=$ROWS/$1/summary" "WEB_HOST_KEY=web-9" "JOB_STATUS=failure" "BOOT_TRAIL_SINCE=0" "SHIM_BODY_FILE=$BODIES/empty_array.json"
}
mkdir -p "$ROWS/t1-origin" "$ROWS/t2-main"
RUN_ARGS=(--image-origin web-9)
run_probe t1-origin "$FHBT" "SENTRY_ACTIONS_RO_TOKEN=$FIXTURE_TOKEN" "SHIM_BODY_FILE=$BODIES/origin_event.json" "BOOT_TRAIL_SINCE=0"
RUN_ARGS=()
rc=$RUN_RC; evaluate "$RUN_ROW" 'de\.sentry\.io' 2 "$FIXTURE_TOKEN"
if [[ "$rc" -eq 0 && -z "$EV_FAILED" ]] && grep -qF 'image-origin: stage=app_zot' "$RUN_ROW/stdout"; then
  row "fresh-host-boot-trail --image-origin: both Sentry org reads carry the bearer on stdin only (>= 2 calls), token in no argv" ok
else row "fresh-host-boot-trail --image-origin: both Sentry org reads carry the bearer on stdin only (>= 2 calls), token in no argv" fail "rc=$rc failed='$EV_FAILED'"; fi

mapfile -t _t2env < <(trail_env t2-main)
run_probe t2-main "$FHBT" "SENTRY_ACTIONS_RO_TOKEN=$FIXTURE_TOKEN" "${_t2env[@]}"
rc=$RUN_RC; evaluate "$RUN_ROW" 'de\.sentry\.io' 2 "$FIXTURE_TOKEN"
if [[ "$rc" -eq 0 && -z "$EV_FAILED" ]]; then
  row "fresh-host-boot-trail main flow: the polled project read AND the image-origin read carry the bearer on stdin only (>= 2 calls)" ok
else row "fresh-host-boot-trail main flow: the polled project read AND the image-origin read carry the bearer on stdin only (>= 2 calls)" fail "rc=$rc failed='$EV_FAILED'"; fi
if ! grep -qF '/tmp/sentry-events.json' "$FHBT"; then row "fresh-host-boot-trail: no fixed /tmp/sentry-events.json path remains (script-owned mktemp)" ok
else row "fresh-host-boot-trail: no fixed /tmp/sentry-events.json path remains (script-owned mktemp)" fail "the fixed path is back"; fi

# hostile token classes: zero calls, the skip is NAMED, the token is never echoed.
ft_ok=1; ft_detail=""
for cls in $TOK_CLASSES; do
  mkdir -p "$ROWS/t3-main-$cls" "$ROWS/t3-origin-$cls"
  mapfile -t _e < <(trail_env "t3-main-$cls"); _e=("${_e[@]/JOB_STATUS=failure/JOB_STATUS=success}")
  run_probe "t3-main-$cls" "$FHBT" "SENTRY_ACTIONS_RO_TOKEN=$(tok_for "$cls")" "${_e[@]}"
  count_calls "$RUN_ROW"
  { [[ "$RUN_RC" -eq 0 && "$EV_CALLS" -eq 0 ]] && grep -aqF 'failed the token-shape check' "$RUN_ROW/stdout" && ! grep -aq 'SYNTHMARK000' "$RUN_ROW/stdout" "$RUN_ROW/stderr" "$RUN_ROW/summary"; } \
    || { ft_ok=0; ft_detail+=" [main/$cls rc=$RUN_RC calls=$EV_CALLS]"; }
  mapfile -t _e < <(trail_env "t3-origin-$cls")
  RUN_ARGS=(--image-origin web-9)
  run_probe "t3-origin-$cls" "$FHBT" "SENTRY_ACTIONS_RO_TOKEN=$(tok_for "$cls")" "${_e[@]}"
  RUN_ARGS=()
  count_calls "$RUN_ROW"
  { [[ "$RUN_RC" -eq 2 && "$EV_CALLS" -eq 0 ]] && grep -aqF 'TRANSIENT' "$RUN_ROW/stdout" && ! grep -aq 'SYNTHMARK000' "$RUN_ROW/stdout" "$RUN_ROW/stderr"; } \
    || { ft_ok=0; ft_detail+=" [origin/$cls rc=$RUN_RC calls=$EV_CALLS]"; }
done
if [[ "$ft_ok" -eq 1 ]]; then row "fresh-host-boot-trail: hostile tokens (quote+newline+url, newline, non-ASCII, quote, space, backslash, tab, CR) make zero calls, name the skip (main: exit 0; --image-origin: TRANSIENT rc 2), never echo the token" ok
else row "fresh-host-boot-trail: hostile tokens (quote+newline+url, newline, non-ASCII, quote, space, backslash, tab, CR) make zero calls, name the skip (main: exit 0; --image-origin: TRANSIENT rc 2), never echo the token" fail "$ft_detail"; fi
for mode in env flag; do
  if xtrace_check "$FHBT" SENTRY_ACTIONS_RO_TOKEN "t4-$mode" "$mode"; then row "fresh-host-boot-trail: refuses xtrace ($mode form): rc 78, zero calls, no token on output" ok
  else row "fresh-host-boot-trail: refuses xtrace ($mode form): rc 78, zero calls, no token on output" fail "$XT_DETAIL"; fi
done
# harness + code mutations against the real script
mapfile -t _e < <(trail_env t5-nostdin)
run_probe t5-nostdin "$FHBT" "SENTRY_ACTIONS_RO_TOKEN=$FIXTURE_TOKEN" "${_e[@]}" SHIM_MUTATE=nostdin
evaluate "$RUN_ROW" 'de\.sentry\.io' 2 "$FIXTURE_TOKEN"
if has_check bearer-not-on-stdin; then row "fresh-host-boot-trail: a shim that stops recording stdin turns the row RED" ok
else row "fresh-host-boot-trail: a shim that stops recording stdin turns the row RED" fail "failed='$EV_FAILED'"; fi
FROM_PS='< <(printf '"'"'header = "Authorization: Bearer %s"\n'"'"' "$SENTRY_ACTIONS_RO_TOKEN")'
mutated_copy "$FHBT" "$SYN/fhbt-argv.sh" "$FROM_PS" '-H "Authorization: Bearer $SENTRY_ACTIONS_RO_TOKEN"'
mapfile -t _e < <(trail_env t6-argv)
run_probe t6-argv "$SYN/fhbt-argv.sh" "SENTRY_ACTIONS_RO_TOKEN=$FIXTURE_TOKEN" "${_e[@]}"
evaluate "$RUN_ROW" 'de\.sentry\.io' 1 "$FIXTURE_TOKEN"
if has_check token-in-argv; then row "fresh-host-boot-trail: restoring the argv bearer on either read is RED on token-in-argv" ok
else row "fresh-host-boot-trail: restoring the argv bearer on either read is RED on token-in-argv" fail "failed='$EV_FAILED'"; fi
mutated_copy "$FHBT" "$SYN/fhbt-noguard.sh" "$BEARER_FN" '_bearer_ok() { return 0; }'
mapfile -t _e < <(trail_env t7-noguard)
run_probe t7-noguard "$SYN/fhbt-noguard.sh" "SENTRY_ACTIONS_RO_TOKEN=$(tok_for quote-newline-url)" "${_e[@]}"
evaluate "$RUN_ROW" 'de\.sentry\.io' 1 "SYNTHMARK0001"
if has_check injected; then row "fresh-host-boot-trail: removing the token-shape guard is RED on injected (the shim records the injected config line)" ok
else row "fresh-host-boot-trail: removing the token-shape guard is RED on injected (the shim records the injected config line)" fail "failed='$EV_FAILED'"; fi

# --- verify-tunnel-ingress-origin.sh ----------------------------------------------------------
VT_STUBS="$TMPD/vt-stubs"; assert_fixture_dir "$VT_STUBS"; mkdir -p "$VT_STUBS"
# S4: the script signs with the canonical python3 snippet (the key rides python3's environment, not openssl's argv), so the
# stub dir needs the real python3 beside the stubs. Without it the HMAC is empty and the shape guard refuses (a correct refusal).
ln -s "$(type -P python3)" "$VT_STUBS/python3" || fatal "stage 3: no python3 to link into the verify-tunnel stub dir"
cat > "$VT_STUBS/doppler" <<'VT_DOPPLER'
#!/usr/bin/env bash
set -u
case "${1:-}" in
  run) printf '"10.0.1.10"\n' ;;
  secrets)
    case "${3:-}" in
      CF_API_TOKEN) printf '%s' "${VT_CF_API_TOKEN:-}" ;;
      CF_ACCOUNT_ID) printf 'acct0001' ;;
      APP_DOMAIN_BASE) printf 'soleur.example' ;;
      # (#9294: the webhook trio is the caller's env, not a doppler answer; a store read of it exits 1 here.)
      *) exit 1 ;;
    esac ;;
  *) exit 1 ;;
esac
VT_DOPPLER
cat > "$VT_STUBS/terraform" <<'VT_TERRAFORM'
#!/usr/bin/env bash
case "${1:-} ${2:-}" in
  "state show") printf '    id = "11111111-2222-3333-4444-555555555555"\n' ;;
  *) exit 1 ;;
esac
VT_TERRAFORM
sed -i "1s|.*|#!${BASH_BIN}|" "$VT_STUBS/doppler" "$VT_STUBS/terraform"
chmod +x "$VT_STUBS/doppler" "$VT_STUBS/terraform"
vt_run() { # <rowname> <script> [env...] -- runs under the stub set; CF token defaults to the fixture
  local name="$1" script="$2"; shift 2
  # #9294 G1: the webhook trio is the caller's env (the Tier-B loader step), not a doppler read; the VT_CF_ACCESS_* knobs override it.
  local acc_id=cfid0001 acc_sec=cfsecret0001 a
  for a in "$@"; do case "$a" in VT_CF_ACCESS_ID=*) acc_id="${a#*=}" ;; VT_CF_ACCESS_SECRET=*) acc_sec="${a#*=}" ;; esac; done
  RUN_EXTRA_PATH="$VT_STUBS"
  run_probe "$name" "$script" "VT_CF_API_TOKEN=$FIXTURE_TOKEN" "SHIM_BODY_FILE=$BODIES/cf_tunnel_cfg.json" SHIM_MODE=noauth "$@" \
    "WEBHOOK_DEPLOY_SECRET=webhook-secret-0001" "CF_ACCESS_CLIENT_ID=$acc_id" "CF_ACCESS_CLIENT_SECRET=$acc_sec"
  RUN_EXTRA_PATH=""
}
vt_stdin() { cat "$ROWS/$1/shim/calls/$2.stdin" 2>/dev/null; }
# The script echoes `::add-mask::<secret>` on purpose (that is how the runner learns to mask it), so
# "never echoed" means: not on stderr, and not on any ::error:: / ::warning:: annotation line.
vt_leaks() { # <rowdir> <marker> -> 0 when the marker leaks outside ::add-mask::
  local ann; ann="$(grep -aE '^::(error|warning|notice)::' "$1/stdout" "$1/stderr" || true)"
  [[ "$ann" == *"$2"* ]] || grep -aqF -- "$2" "$1/stderr"
}
vt_argv_has() { local f; for f in "$ROWS/$1"/shim/calls/*.argv; do [[ -e "$f" ]] && grep -aqF -- "$2" "$f" && return 0; done; return 1; }

vt_run v1-ok "$VTIO"
v_rc=$RUN_RC; count_calls "$RUN_ROW"
v_hmac="$(printf '' | openssl dgst -sha256 -hmac webhook-secret-0001 | sed 's/.*= //')"
v_s1="$(vt_stdin v1-ok 1)"; v_s2="$(vt_stdin v1-ok 2)"
v_want2="$(printf 'header = "X-Signature-256: sha256=%s"\nheader = "CF-Access-Client-Id: cfid0001"\nheader = "CF-Access-Client-Secret: cfsecret0001"' "$v_hmac")"
v_bad=""
[[ "$v_rc" -eq 0 && "$EV_CALLS" -eq 2 ]] || v_bad+=" rc=$v_rc calls=$EV_CALLS"
[[ "$v_s1" == "header = \"Authorization: Bearer $FIXTURE_TOKEN\"" ]] || v_bad+=" call1-stdin"
[[ "$v_s2" == "$v_want2" ]] || v_bad+=" call2-stdin"
for needle in "$FIXTURE_TOKEN" cfid0001 cfsecret0001 "$v_hmac" webhook-secret-0001; do vt_argv_has v1-ok "$needle" && v_bad+=" argv-has-credential"; done
for f in "$ROWS"/v1-ok/shim/calls/*.injected; do [[ -s "$f" ]] && v_bad+=" injected"; done
[[ ! -e "$ROWS/v1-ok/shim/unexpected" && ! -e "$ROWS/v1-ok/shim/unmodelled" ]] || v_bad+=" stub-called"
if [[ -z "$v_bad" ]]; then row "verify-tunnel-ingress-origin: the Cloudflare read carries the bearer on stdin; the deploy-status read carries the HMAC + CF Access id + CF Access secret as three stdin headers in order; no credential in any argv" ok
else row "verify-tunnel-ingress-origin: the Cloudflare read carries the bearer on stdin; the deploy-status read carries the HMAC + CF Access id + CF Access secret as three stdin headers in order; no credential in any argv" fail "$v_bad"; fi

# unusable CF API token: gate failure (exit 1), zero calls, token never echoed
vt_ok=1; vt_detail=""
for cls in $TOK_CLASSES; do
  vt_run "v2-$cls" "$VTIO" "VT_CF_API_TOKEN=$(tok_for "$cls")"
  count_calls "$RUN_ROW"
  { [[ "$RUN_RC" -eq 1 && "$EV_CALLS" -eq 0 ]] && grep -aqF 'CF_API_TOKEN failed the token-shape check' "$RUN_ROW/stdout" "$RUN_ROW/stderr" && ! vt_leaks "$RUN_ROW" 'SYNTHMARK000'; } \
    || { vt_ok=0; vt_detail+=" [$cls rc=$RUN_RC calls=$EV_CALLS]"; }
done
if [[ "$vt_ok" -eq 1 ]]; then row "verify-tunnel-ingress-origin: a malformed CF API token is a gate failure (exit 1) with zero calls and is never echoed" ok
else row "verify-tunnel-ingress-origin: a malformed CF API token is a gate failure (exit 1) with zero calls and is never echoed" fail "$vt_detail"; fi
# unusable CF Access secret: the config read may run, the deploy-status call must NOT, and it is a gate failure
vt_ok=1; vt_detail=""
v3_i=0
for sec in 'SYNTHMARK0001"x' $'SYNTHMARK0001\nheader = "X-Injected: 1"' 'SYNTHMARK0001\x'; do
  v3_i=$((v3_i + 1))
  vt_run "v3-secret-$v3_i" "$VTIO" "VT_CF_ACCESS_SECRET=$sec"
  count_calls "$RUN_ROW"
  { [[ "$RUN_RC" -eq 1 && "$EV_CALLS" -eq 1 ]] && grep -aqF 'header-value check' "$RUN_ROW/stdout" "$RUN_ROW/stderr" && ! vt_leaks "$RUN_ROW" 'SYNTHMARK000'; } \
    || { vt_ok=0; vt_detail+=" [rc=$RUN_RC calls=$EV_CALLS]"; }
done
if [[ "$vt_ok" -eq 1 ]]; then row "verify-tunnel-ingress-origin: a CF Access secret carrying a quote, backslash or injected newline stops BEFORE the deploy-status call (exit 1) and is never echoed" ok
else row "verify-tunnel-ingress-origin: a CF Access secret carrying a quote, backslash or injected newline stops BEFORE the deploy-status call (exit 1) and is never echoed" fail "$vt_detail"; fi
for mode in env flag; do
  RUN_EXTRA_PATH="$VT_STUBS"
  if xtrace_check "$VTIO" CF_API_TOKEN "v4-$mode" "$mode"; then row "verify-tunnel-ingress-origin: refuses xtrace ($mode form): rc 78, zero calls, no token on output" ok
  else row "verify-tunnel-ingress-origin: refuses xtrace ($mode form): rc 78, zero calls, no token on output" fail "$XT_DETAIL"; fi
  RUN_EXTRA_PATH=""
done
# mutations: argv restored on the second call; guards removed
mutated_copy "$VTIO" "$SYN/vtio-argv.sh" '< <(printf '"'"'header = "X-Signature-256: sha256=%s"\nheader = "CF-Access-Client-Id: %s"\nheader = "CF-Access-Client-Secret: %s"\n'"'"' \
          "$HMAC" "$CF_ACCESS_ID" "$CF_ACCESS_SECRET")' '-H "CF-Access-Client-Secret: ${CF_ACCESS_SECRET}"'
vt_run v5-argv "$SYN/vtio-argv.sh"
if vt_argv_has v5-argv cfsecret0001; then row "verify-tunnel-ingress-origin: restoring a CF Access header on argv is RED (the credential shows in a recorded argv)" ok
else row "verify-tunnel-ingress-origin: restoring a CF Access header on argv is RED (the credential shows in a recorded argv)" fail "the mutant's credential did not reach argv"; fi
mutated_copy "$VTIO" "$SYN/vtio-noguard.sh" '_cfg_ok() { local LC_ALL=C; case "${1:-}" in '"''"'|*'"'"'"'"'"'*|*'"'"'\'"'"'*|*[[:cntrl:]]*) return 1 ;; esac; }' '_cfg_ok() { return 0; }'
vt_run v6-noguard "$SYN/vtio-noguard.sh" 'VT_CF_ACCESS_SECRET=SYNTHMARK0001"x'
v6_inj=0; for f in "$ROWS"/v6-noguard/shim/calls/*.injected; do [[ -s "$f" ]] && v6_inj=1; done
if [[ "$v6_inj" -eq 1 ]]; then row "verify-tunnel-ingress-origin: removing the header-value guard is RED (the shim records the injected config line)" ok
else row "verify-tunnel-ingress-origin: removing the header-value guard is RED (the shim records the injected config line)" fail "no INJECTED recorded for the unguarded mutant"; fi
echo "=== stage 3: fresh-host-boot-trail + verify-tunnel-ingress-origin transport rows done ==="

# =====================================================================================
# STAGE 4: SHIM EXTENSIONS for the community-script conversions (#9597, S1 Phase 2). Each
# extension is proven on SYNTHETIC probes first, so a shim that accepts too much cannot make
# the later per-script rows (plugins/soleur/skills/community/test/community-argv.test.sh)
# vacuous:
#   (a) the shim and `evaluate` are parameterised by auth SCHEME (Discord sends `Bot`, and
#       rejects `Bearer`): a Bot-to-Bearer mutation must go RED;
#   (b) the shim records a `--data-binary @-` stdin body, models `-d @-` stripping CR/LF as real
#       curl does, and has a `fail7` transport-failure mode, calibrated against real curl;
#   (c) a `jq` shim records jq's argv (jq's own argv is world-readable too);
#   (d) static rows over the converted sources and docs.
# =====================================================================================
# C4: the real-curl oracle for the body semantics and the transport-failure exit code.
CR_FILE="$ORA/crlf.txt"
printf 'SYNTHA\r\nSYNTHB\n' > "$CR_FILE"
"$REAL_CURL" --disable --noproxy '*' -sS --max-time 3 --libcurl "$ORA/bin.c" --data-binary @- http://127.0.0.1:9/ < "$CR_FILE" >/dev/null 2>&1; REAL_RC7=$?
"$REAL_CURL" --disable --noproxy '*' -sS --max-time 3 --libcurl "$ORA/d.c" -d @- http://127.0.0.1:9/ < "$CR_FILE" >/dev/null 2>&1 || true
[[ -s "$ORA/bin.c" && -s "$ORA/d.c" ]] || fatal "C4 real curl did not write --libcurl output for a stdin body"
grep -qF 'SYNTHA\r\nSYNTHB\n' "$ORA/bin.c" || fatal "C4 oracle: --data-binary @- did not keep CR/LF"
grep -qF 'SYNTHASYNTHB' "$ORA/d.c" || fatal "C4 oracle: -d @- did not strip CR/LF"
[[ "$REAL_RC7" -eq 7 ]] || fatal "C4 oracle: real curl against a refused connection exited $REAL_RC7, the shim's fail7 models 7"
row "control C4: real curl keeps CR/LF for --data-binary @-, strips them for -d @-, and exits 7 on a refused connection" ok

# (a) scheme rows ----------------------------------------------------------------------
P_BOT="$(make_synth bot)"
run_probe s1-bot "$P_BOT" "SYNTH_TOKEN=$FIXTURE_TOKEN" SHIM_SCHEME=Bot
rc=$RUN_RC; evaluate "$RUN_ROW" "$SYN_HOST" 1 "$FIXTURE_TOKEN" Bot
if [[ "$rc" -eq 0 && -z "$EV_FAILED" ]] && grep -q '^PASS' "$RUN_ROW/stdout" \
   && grep -qxF -- "header = \"Authorization: Bot $FIXTURE_TOKEN\"" "$RUN_ROW/shim/calls/1.stdin"; then
  row "scheme: a Bot probe sends exactly the line header = \"Authorization: Bot <tok>\" on stdin and is GREEN under the Bot-aware shim" ok
else row "scheme: a Bot probe sends exactly the line header = \"Authorization: Bot <tok>\" on stdin and is GREEN under the Bot-aware shim" fail "rc=$rc failed='$EV_FAILED'"; fi
P_BOT_AS_BEARER="$SYN/synth-bot-as-bearer.sh"; sed 's/Authorization: Bot /Authorization: Bearer /' "$P_BOT" > "$P_BOT_AS_BEARER"
grep -q 'Authorization: Bearer' "$P_BOT_AS_BEARER" || fatal "scheme mutation did not land"
run_probe s2-bearer "$P_BOT_AS_BEARER" "SYNTH_TOKEN=$FIXTURE_TOKEN" SHIM_SCHEME=Bot
rc=$RUN_RC; evaluate "$RUN_ROW" "$SYN_HOST" 1 "$FIXTURE_TOKEN" Bot
if has_check bearer-not-on-stdin && transient_outcome "$RUN_ROW" "$rc"; then
  row "scheme: swapping Bot for Bearer is RED (the exact-line check fires, and the Bot-aware shim answers 401, never PASS)" ok
else row "scheme: swapping Bot for Bearer is RED (the exact-line check fires, and the Bot-aware shim answers 401, never PASS)" fail "rc=$rc failed='$EV_FAILED'"; fi
evaluate "$ROWS/s1-bot" "$SYN_HOST" 1 "$FIXTURE_TOKEN"
if has_check bearer-not-on-stdin; then row "scheme: evaluating the Bot probe as a Bearer probe is RED (the default scheme did not loosen)" ok
else row "scheme: evaluating the Bot probe as a Bearer probe is RED (the default scheme did not loosen)" fail "failed='$EV_FAILED'"; fi
run_probe s3-bot-default-shim "$P_BOT" "SYNTH_TOKEN=$FIXTURE_TOKEN"
if transient_outcome "$RUN_ROW" "$RUN_RC"; then row "scheme: a default (Bearer) shim rejects a Bot probe with 401, TRANSIENT (the auth gate is scheme-aware)" ok
else row "scheme: a default (Bearer) shim rejects a Bot probe with 401, TRANSIENT (the auth gate is scheme-aware)" fail "rc=$RUN_RC"; fi

# (b)+(c) stdin-body rows ----------------------------------------------------------------
make_body_probe() { # <variant: stdin|dstdin|argv|jqarg> -> path
  local v="$1" p="$SYN/synth-body-$1.sh"
  {
    cat <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
case "$-" in
  *x*)
    if [ -n "${SYNTH_PW:+x}" ]; then
      printf '[FATAL] refusing to run under xtrace with a live credential set (SYNTH_PW).\n' >&2
      exit 78
    fi
    ;;
esac
EOF
    # The body is built by jq and piped to curl's STDIN: no file, no trap. The values reach jq only
    # through its environment (an inline assignment prefix), never `jq --arg` and never `export`.
    case "$1" in
      stdin) printf '%s\n' "RESP=\$(SYNTH_ID_E=\"\$SYNTH_ID\" SYNTH_PW_E=\"\$SYNTH_PW\" jq -n '{identifier:\$ENV.SYNTH_ID_E,password:\$ENV.SYNTH_PW_E}' | curl --disable --noproxy '*' -sS -w '\\nHTTP_STATUS:%{http_code}' -X POST -H 'Content-Type: application/json' --data-binary @- '$SYN_URL')" ;;
      jqarg) printf '%s\n' "RESP=\$(jq -n --arg id \"\$SYNTH_ID\" --arg pw \"\$SYNTH_PW\" '{identifier:\$id,password:\$pw}' | curl --disable --noproxy '*' -sS -w '\\nHTTP_STATUS:%{http_code}' -X POST -H 'Content-Type: application/json' --data-binary @- '$SYN_URL')" ;;
      dstdin) printf '%s\n' "RESP=\$(SYNTH_ID_E=\"\$SYNTH_ID\" SYNTH_PW_E=\"\$SYNTH_PW\" jq -n '{identifier:\$ENV.SYNTH_ID_E,password:\$ENV.SYNTH_PW_E}' | curl --disable --noproxy '*' -sS -w '\\nHTTP_STATUS:%{http_code}' -X POST -H 'Content-Type: application/json' -d @- '$SYN_URL')" ;;
      argv) printf '%s\n' "RESP=\$(curl --disable --noproxy '*' -sS -w '\\nHTTP_STATUS:%{http_code}' -X POST -H 'Content-Type: application/json' -d \"{\\\"identifier\\\":\\\"\$SYNTH_ID\\\",\\\"password\\\":\\\"\$SYNTH_PW\\\"}\" '$SYN_URL')" ;;
    esac
    synth_tail
  } > "$p"
  printf '%s\n' "$p"
}
BODY_PW="SYNTHPW""-aaaa-bbbb-cccc"
BODY_ID="synthetic.bsky.social"
evaluate_body() { # <rowdir> -> EV_FAILED names: pw-in-argv, pw-in-jq-argv, body-not-recorded, body-content, no-calls
  local row="$1" f c
  EV_FAILED=""; count_calls "$row"
  [[ "$EV_CALLS" -ge 1 ]] || EV_FAILED+=" no-calls"
  for f in "$row"/shim/calls/*.argv; do
    [[ -e "$f" ]] || continue
    c="${f%.argv}"
    grep -aqF -- "$BODY_PW" "$f" && EV_FAILED+=" pw-in-argv"
    [[ -s "$c.body" ]] || EV_FAILED+=" body-not-recorded"
    jq -e --arg i "$BODY_ID" --arg p "$BODY_PW" '.identifier == $i and .password == $p' "$c.body" >/dev/null 2>&1 || EV_FAILED+=" body-content"
  done
  for f in "$row"/shim/jq/*.argv; do
    [[ -e "$f" ]] || continue
    grep -aqF -- "$BODY_PW" "$f" && EV_FAILED+=" pw-in-jq-argv"
  done
  EV_FAILED="$(printf '%s\n' $EV_FAILED | awk '!s[$0]++' | paste -sd' ' -)"
  return 0
}
body_env=("SYNTH_PW=$BODY_PW" "SYNTH_ID=$BODY_ID" SHIM_MODE=noauth)

P_BS="$(make_body_probe stdin)"
run_probe b1-stdin "$P_BS" "${body_env[@]}"
rc=$RUN_RC; evaluate_body "$RUN_ROW"
if [[ "$rc" -eq 0 && -z "$EV_FAILED" ]] && grep -q '^PASS' "$RUN_ROW/stdout"; then
  row "body: a jq-to-curl --data-binary @- probe is GREEN (exact stdin body, password in no curl or jq argv)" ok
else row "body: a jq-to-curl --data-binary @- probe is GREEN (exact stdin body, password in no curl or jq argv)" fail "rc=$rc failed='$EV_FAILED' pass-line=$(grep -c '^PASS' "$RUN_ROW/stdout" || true)"; fi
if [[ -s "$ROWS/b1-stdin/shim/jq/counter" ]] && grep -aqF 'ENV.SYNTH_PW_E' "$ROWS/b1-stdin/shim/jq/1.argv"; then
  row "jq shim: records jq's argv (the body writer's program text is on file; recording works)" ok
else row "jq shim: records jq's argv (the body writer's program text is on file; recording works)" fail "no jq argv recorded"; fi

P_BA="$(make_body_probe argv)"
run_probe b2-argv "$P_BA" "${body_env[@]}"
evaluate_body "$RUN_ROW"
if has_check pw-in-argv; then row "body: handing the password to curl as -d \"\$body\" is RED on pw-in-argv" ok
else row "body: handing the password to curl as -d \"\$body\" is RED on pw-in-argv" fail "failed='$EV_FAILED'"; fi

P_BJ="$(make_body_probe jqarg)"
run_probe b3-jqarg "$P_BJ" "${body_env[@]}"
evaluate_body "$RUN_ROW"
if has_check pw-in-jq-argv && ! has_check pw-in-argv; then
  row "body: passing the password to jq as --arg is RED on pw-in-jq-argv, which the curl shim alone cannot see" ok
else row "body: passing the password to jq as --arg is RED on pw-in-jq-argv, which the curl shim alone cannot see" fail "failed='$EV_FAILED'"; fi

run_probe b4-nobody "$P_BS" "${body_env[@]}" SHIM_MUTATE=nobody
evaluate_body "$RUN_ROW"
if has_check body-not-recorded && has_check body-content; then row "body: a shim that stops recording the stdin body turns the body rows RED" ok
else row "body: a shim that stops recording the stdin body turns the body rows RED" fail "failed='$EV_FAILED'"; fi

P_BD="$(make_body_probe dstdin)"
run_probe b5-dstdin "$P_BD" "${body_env[@]}"
nl_bin="$(wc -l < "$ROWS/b1-stdin/shim/calls/1.body")"; nl_d="$(wc -l < "$ROWS/b5-dstdin/shim/calls/1.body")"
if [[ "$nl_bin" -ge 2 && "$nl_d" -eq 0 ]]; then
  row "body: the shim keeps CR/LF for --data-binary @- and strips them for -d @- on stdin, as real curl does (control C4)" ok
else row "body: the shim keeps CR/LF for --data-binary @- and strips them for -d @- on stdin, as real curl does (control C4)" fail "binary-lines=$nl_bin d-lines=$nl_d"; fi

# fail7: the transport-failure mode, calibrated to real curl's exit 7 by control C4.
run_probe b6-fail7 "$P_CANON" "SYNTH_TOKEN=$FIXTURE_TOKEN" SHIM_MODE=fail7
count_calls "$RUN_ROW"
if [[ "$RUN_RC" -eq 7 && "$EV_CALLS" -eq 1 ]] && ! grep -q '^PASS' "$RUN_ROW/stdout" && grep -q 'TRANSIENT' "$RUN_ROW/stderr"; then
  row "fail7: a transport failure (curl exit 7) reaches the probe's TRANSIENT path with the call recorded, never PASS" ok
else row "fail7: a transport failure (curl exit 7) reaches the probe's TRANSIENT path with the call recorded, never PASS" fail "rc=$RUN_RC calls=$EV_CALLS"; fi

# (d) static rows over the converted sources and docs. `git grep` reads TRACKED files by default: on an
# uncommitted tree a new file is invisible, so the helper searches untracked files too (--untracked) and
# requires every operand to exist. It passes ONLY on `git grep -q` rc 1 (no match): rc 128 (not a repo, as
# in a mutation sandbox; a bad pathspec) and rc 0 (a match) are both failures, so `! git grep` can no
# longer pass vacuously.
static_absent() { # <ere> <file...>
  local ere="$1" f rc=0; shift
  for f in "$@"; do [[ -f "$f" ]] || return 1; done
  git grep -q --untracked -E -e "$ere" -- "$@" >/dev/null 2>&1 || rc=$?
  [[ "$rc" -eq 1 ]]
}
# The two production regexes, named so the fixture rows below run the SAME text the real rows do.
ERE_DISCORD_ARGV='-H +"Authorization: *Bot'
ERE_BSKY_PW_ARGV='(-d|--data[a-z-]*)[ =]+"([^"\\]|\\.)*\$\{?BSKY_(APP_PASSWORD|PW)|--arg +[a-z_]+ +"\$\{?BSKY_(APP_PASSWORD|PW)'
COMM="plugins/soleur/skills/community/scripts"
SETUP_MD="plugins/soleur/skills/flag-bootstrap/SETUP.md"
n_apikey_argv="$(grep -cE -e '-H +"?Authorization: *Api-Key' "$SETUP_MD" || true)"
n_apikey_cfg="$(grep -cF 'header = "Authorization: Api-Key %s"' "$SETUP_MD" || true)"
if [[ "$n_apikey_argv" -eq 0 && "$n_apikey_cfg" -ge 5 ]]; then
  row "static: flag-bootstrap/SETUP.md has no -H Authorization: Api-Key curl example left and carries five stdin-config forms" ok
else row "static: flag-bootstrap/SETUP.md has no -H Authorization: Api-Key curl example left and carries five stdin-config forms" fail "argv=$n_apikey_argv stdin-config=$n_apikey_cfg"; fi
if static_absent "$ERE_DISCORD_ARGV" "$COMM/discord-community.sh" "$COMM/discord-setup.sh" \
   && grep -qF 'header = "Authorization: Bot %s"' "$COMM/discord-community.sh" "$COMM/discord-setup.sh"; then
  row "static: neither Discord script carries a -H \"Authorization: Bot ...\" argument (array-held or inline), both build the stdin config line" ok
else row "static: neither Discord script carries a -H \"Authorization: Bot ...\" argument (array-held or inline), both build the stdin config line" fail "an argv Bot header is back, or the stdin config line is gone"; fi
# A password variable inside a -d/--data* operand or a jq --arg of the two bsky scripts (lint equality says
# nothing about a body: it is not a header, so these two files are not in baseline E). The stdin form is
# asserted on its behaviour (a `--data-binary @-` body, the values read from jq's environment), not on how
# the body is assembled.
if static_absent "$ERE_BSKY_PW_ARGV" "$COMM/bsky-community.sh" "$COMM/bsky-setup.sh" \
   && [[ "$(grep -c -F -e '--data-binary @-' "$COMM/bsky-community.sh" "$COMM/bsky-setup.sh" | awk -F: '{s+=$2} END {print s}')" -ge 2 ]] \
   && [[ "$(grep -c -F -e '$ENV.BSKY_PW' "$COMM/bsky-community.sh" "$COMM/bsky-setup.sh" | awk -F: '{s+=$2} END {print s}')" -ge 2 ]]; then
  row "static: neither bsky script puts the app password in a -d/--data operand or a jq --arg, both send the body to curl on stdin (--data-binary @-) with the values read from jq's environment" ok
else row "static: neither bsky script puts the app password in a -d/--data operand or a jq --arg, both send the body to curl on stdin (--data-binary @-) with the values read from jq's environment" fail "the password is back on an argv, or the stdin form is gone"; fi

# `static_absent` ITSELF is proven here, on fixtures, in both directions. Its "absent" half is otherwise a
# dead assertion (a body of `true`, or accepting git's rc 128, would leave every row above green).
SAR="$TMPD/sa-repo"; SAN="$TMPD/sa-nogit"
for d in "$SAR" "$SAN"; do assert_fixture_dir "$d"; mkdir -p "$d"; done
( source "$REPO_ROOT/plugins/soleur/test/lib/git-fixture-env.sh" && git_fixture_env "$SAR" || exit 1; git -C "$SAR" init -q ) || { echo "FATAL: the static_absent fixture repo could not be created" >&2; exit 2; }
printf '%s\n' 'echo clean' > "$SAR/clean.sh"
printf '%s\n' 'echo clean' > "$SAN/clean.sh"
# Each violating fixture is one line the matching production regex must flag.
printf '%s\n' 'curl -H "Authorization: Bot $TOKEN" "$URL"' > "$SAR/viol-discord.sh"
printf '%s\n' 'curl -d "{\"password\":\"${BSKY_APP_PASSWORD}\"}" "$URL"' > "$SAR/viol-bsky-d.sh"
printf '%s\n' 'curl --data "x=${BSKY_PW}" "$URL"' > "$SAR/viol-bsky-data.sh"
printf '%s\n' 'jq -n --arg pw "$BSKY_PW" "{password:\$pw}"' > "$SAR/viol-bsky-arg.sh"
# The compliant bsky shape (env-read jq program, stdin body) must NOT be flagged.
printf '%s\n' "jq -n '{password: \$ENV.BSKY_PW}' | curl --data-binary @- \"\$URL\"" > "$SAR/ok-bsky.sh"
sa_in_repo() { ( cd "$SAR" && static_absent "$@" ); }
sa_in_nogit() { ( cd "$SAN" && GIT_CEILING_DIRECTORIES="$TMPD" static_absent "$@" ); }

if sa_in_repo "$ERE_DISCORD_ARGV" clean.sh && sa_in_repo "$ERE_BSKY_PW_ARGV" clean.sh ok-bsky.sh; then
  row "static_absent: a clean file and the compliant bsky shape are absent (true) in a repository" ok
else row "static_absent: a clean file and the compliant bsky shape are absent (true) in a repository" fail "a clean fixture was flagged"; fi
sa_bad=""
sa_in_repo "$ERE_DISCORD_ARGV" viol-discord.sh && sa_bad+=" discord"
for v in viol-bsky-d.sh viol-bsky-data.sh viol-bsky-arg.sh; do sa_in_repo "$ERE_BSKY_PW_ARGV" "$v" && sa_bad+=" $v"; done
if [[ -z "$sa_bad" ]]; then row "static_absent: a violating fixture is NOT absent (false) for the Discord regex and for each bsky regex alternative (-d, --data, --arg)" ok
else row "static_absent: a violating fixture is NOT absent (false) for the Discord regex and for each bsky regex alternative (-d, --data, --arg)" fail "passed vacuously on:$sa_bad"; fi
if ! sa_in_repo "$ERE_DISCORD_ARGV" clean.sh no-such-file.sh; then row "static_absent: a missing operand is a refusal (false), not a pass" ok
else row "static_absent: a missing operand is a refusal (false), not a pass" fail "a missing file read as absent"; fi
# rc 128 (git could not search) is a refusal: once for a directory that is not a repository, once for an
# unusable regex inside a good repository.
if ! sa_in_nogit "$ERE_DISCORD_ARGV" clean.sh; then row "static_absent: git rc 128 (not a repository) is a refusal (false), not a pass" ok
else row "static_absent: git rc 128 (not a repository) is a refusal (false), not a pass" fail "rc 128 read as absent"; fi
if ! sa_in_repo '(' clean.sh; then row "static_absent: git rc 128 (unusable regex) is a refusal (false), not a pass" ok
else row "static_absent: git rc 128 (unusable regex) is a refusal (false), not a pass" fail "rc 128 read as absent"; fi
echo "=== stage 4: shim extensions (scheme, stdin body, fail7, jq shim, static rows) done ==="

# =====================================================================================
# STAGE S2-A (argv-bearer sweep S2, plan 2026-10-08-fix-argv-bearer-sweep-s2-ops-runner-scripts):
# scripts/cutover-inngest.sh. Part 1 = the `backup)` arm (#8767): the Doppler-read Hetzner token is
# shape-checked, then masked BEFORE its first use, and no response body ever reaches the run log.
# The arm is EXTRACTED from the real script (never re-typed here) and run under a recording `curl`
# and a `doppler` that returns a synthetic canary. The driver runs with stdout and stderr in ONE file
# so the ORDER of events (mask line, then the first curl call) is observable.
# =====================================================================================
CUT="scripts/cutover-inngest.sh"
[[ -f "$CUT" ]] || fatal "stage S2-A: $CUT is missing"
BKBIN="$TMPD/bkbin"; BKDIR="$TMPD/bk"
for d in "$BKBIN" "$BKDIR"; do assert_fixture_dir "$d"; mkdir -p "$d"; done
ln -s "$(type -P seq)" "$BKBIN/seq"
printf '#!%s\nprintf "%%s\\n" "$BK_TOKEN"\n' "$BASH_BIN" > "$BKBIN/doppler"
cat > "$BKBIN/curl" <<'BK_CURL_EOF'
#!/usr/bin/env bash
# Recording curl for the backup-arm rows. Records argv (NUL-delimited) and, for `--config -`, stdin.
# Announces each call on STDERR (SHIMCALL n) so the combined stream orders it against the mask line.
set -u
D="${BK_SHIM:?}"; mkdir -p "$D/calls"
n=0; [[ -r "$D/counter" ]] && read -r n < "$D/counter"
n=$((n + 1)); printf '%s\n' "$n" > "$D/counter"
printf '%s\0' "$@" > "$D/calls/$n.argv"
printf 'SHIMCALL %s\n' "$n" >&2
out=""; wfmt=""; url=""; cfg=0; a=("$@"); i=0
while (( i < ${#a[@]} )); do
  case "${a[i]}" in
    -o) out="${a[i+1]}"; i=$((i + 1)) ;;
    -w) wfmt="${a[i+1]}"; i=$((i + 1)) ;;
    --config) [[ "${a[i+1]}" == "-" ]] && cfg=1; i=$((i + 1)) ;;
    -H) [[ "${a[i+1]}" == "@-" ]] && cfg=1; i=$((i + 1)) ;;
    http*) url="${a[i]}" ;;
  esac
  i=$((i + 1))
done
(( cfg )) && cat > "$D/calls/$n.stdin"
case "$url" in
  *create_image) st="${BK_CREATE_STATUS:-201}"; bodyf="${BK_CREATE_BODY:-}" ;;
  *) st="${BK_HTTP_STATUS:-200}"; bodyf="${BK_ACTION_BODY:-}" ;;
esac
[[ "$st" == 000 ]] && { printf 'curl: (7) Failed to connect\n' >&2; exit 7; }
[[ -n "$out" && -n "$bodyf" ]] && cp "$bodyf" "$out"
[[ "$wfmt" == '%{http_code}' ]] && printf '%s' "$st"
[[ "$wfmt" == '\n%{http_code}' ]] && printf '\n%s' "$st"
exit 0
BK_CURL_EOF
chmod +x "$BKBIN/doppler" "$BKBIN/curl"

# bk_driver <outfile> <script>: _bearer_ok + _bearer_curl + the backup arm, /tmp/backup-* rewritten to
# ${BK_TMP}/backup-* so a row never touches the real /tmp. A positive control below proves the arm ran.
bk_driver() {
  local out="$1" src="$2"
  assert_fixture_dir "$out"
  {
    printf 'set -euo pipefail\n'
    grep -m1 '^_bearer_ok() {' "$src"
    awk '/^_bearer_curl\(\) \{$/,/^}$/' "$src"
    printf 'case backup in\n'
    awk '/^  backup\)$/{f=1} f{print} f&&/^    ;;$/{exit}' "$src" | sed 's|/tmp/backup-|${BK_TMP}/backup-|g'
    printf 'esac\n'
  } > "$out"
}
BKDRV="$BKDIR/driver.sh"
bk_driver "$BKDRV" "$CUT"
printf '%s' '{"image":{"id":111},"action":{"id":222}}' > "$BKDIR/create-ok.json"
printf '%s' '{"action":{"id":222,"status":"success"}}' > "$BKDIR/action-success.json"
BK_CANARY="hcloud-canary-$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')"
BK_BODYCANARY="bodycanary-$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')"
printf '{"error":{"code":"forbidden","message":"%s"}}' "$BK_BODYCANARY" > "$BKDIR/create-err.json"
printf '{"action":{"id":222,"status":"error","error":{"code":"x","message":"%s"}}}' "$BK_BODYCANARY" > "$BKDIR/action-error.json"

BK_RC=0
bk_run() { # <rowname> <token> <create_status> <create_body_file> <action_body_file> [driver]
  local name="$1" row="$ROWS/$1" drv="${6:-$BKDRV}"
  assert_fixture_dir "$row"; mkdir -p "$row/tmp" "$row/home" "$row/shim"
  ( cd "$row" && env -i PATH="$BKBIN:$REALBIN" HOME="$row/home" TMPDIR="$row/tmp" BK_TMP="$row/tmp" BK_SHIM="$row/shim" \
      BK_TOKEN="$2" HCLOUD_TOKEN="$2" BK_CREATE_STATUS="$3" BK_CREATE_BODY="$4" BK_ACTION_BODY="$5" \
      "$BASH_BIN" "$drv" < /dev/null > "$row/out" 2>&1 )
  BK_RC=$?
}
bk_count() { local n; n="$(grep -cF -- "$2" "$1" 2>/dev/null || true)"; printf '%s' "${n:-0}"; }
bk_calls() { local n=0 f; for f in "$1"/shim/calls/*.argv; do [[ -e "$f" ]] && n=$((n + 1)); done; printf '%s' "$n"; }
# Invariants for a run that reached the Hetzner API: sets BK_FAIL (space-separated check names, empty = green).
#   mask-not-first   the first output line is not exactly `::add-mask::<token>`
#   mask-count       the token appears on a number of lines other than exactly one
#   mask-after-curl  the first curl call is announced before the mask line
#   token-in-argv    the token is in any recorded curl argv
#   token-not-stdin  the first curl call's stdin lacks the bearer header
#   body-in-output   the response-body canary reached the output
bk_check() { # <rowname> <token>
  local row="$ROWS/$1" tok="$2" first mline cline
  BK_FAIL=""
  first="$(head -n1 "$row/out")"
  [[ "$first" == "::add-mask::$tok" ]] || BK_FAIL+=" mask-not-first"
  [[ "$(bk_count "$row/out" "$tok")" == 1 ]] || BK_FAIL+=" mask-count"
  mline="$(grep -nFx -m1 -- "::add-mask::$tok" "$row/out" | cut -d: -f1)"
  cline="$(grep -n -m1 '^SHIMCALL ' "$row/out" | cut -d: -f1)"
  [[ -n "$mline" && -n "$cline" && "$mline" -lt "$cline" ]] || BK_FAIL+=" mask-after-curl"
  local f; for f in "$row"/shim/calls/*.argv; do [[ -e "$f" ]] && grep -aqF -- "$tok" "$f" && BK_FAIL+=" token-in-argv"; done
  grep -qxF -- "header = \"Authorization: Bearer $tok\"" "$row/shim/calls/1.stdin" 2>/dev/null || BK_FAIL+=" token-not-stdin"
  [[ "$(bk_count "$row/out" "$BK_BODYCANARY")" == 0 ]] || BK_FAIL+=" body-in-output"
  BK_FAIL="$(printf '%s\n' $BK_FAIL | awk '!s[$0]++' | paste -sd' ' -)"
}

# Positive control: the extracted driver really runs the arm (two curl calls on the 201 path: create + one poll).
bk_run bk-201 "$BK_CANARY" 201 "$BKDIR/create-ok.json" "$BKDIR/action-success.json"
bk_check bk-201 "$BK_CANARY"
if [[ "$(grep -c '_bearer_curl HCLOUD_TOKEN' "$BKDRV")" -ge 2 && "$BK_RC" -eq 0 && "$(bk_calls "$ROWS/bk-201")" == 2 ]] \
   && grep -qF 'backup image id=111 ready' "$ROWS/bk-201/out"; then
  row "backup arm extraction control: the extracted arm runs under the shims (rc 0, create + one poll, image id reported)" ok
else row "backup arm extraction control: the extracted arm runs under the shims (rc 0, create + one poll, image id reported)" fail "rc=$BK_RC calls=$(bk_calls "$ROWS/bk-201")"; fi
if [[ -z "$BK_FAIL" ]]; then
  row "backup arm 201: the mask line is the first output event, appears once, before any curl call; the token is on curl's stdin and in no argv" ok
else row "backup arm 201: the mask line is the first output event, appears once, before any curl call; the token is on curl's stdin and in no argv" fail "checks: $BK_FAIL"; fi

# non-201: exit 1, the code and a fixed class hint, never the body; mask still first and once.
bk_run bk-403 "$BK_CANARY" 403 "$BKDIR/create-err.json" "$BKDIR/action-success.json"
bk_check bk-403 "$BK_CANARY"
n_err="$(bk_count "$ROWS/bk-403/out" '::error::')"
if [[ "$BK_RC" -eq 1 && -z "$BK_FAIL" && "$n_err" == 1 ]] && grep -qF 'HTTP 403' "$ROWS/bk-403/out" \
   && grep -qF 'ADR-241 D4' "$ROWS/bk-403/out" && [[ "$(bk_calls "$ROWS/bk-403")" == 1 ]]; then
  row "backup arm 403: exit 1 with the HTTP code and the ADR-241 D4 class hint, one ::error:: line, the response body canary absent, no poll" ok
else row "backup arm 403: exit 1 with the HTTP code and the ADR-241 D4 class hint, one ::error:: line, the response body canary absent, no poll" fail "rc=$BK_RC errlines=$n_err checks: $BK_FAIL"; fi
bk_run bk-500 "$BK_CANARY" 500 "$BKDIR/create-err.json" "$BKDIR/action-success.json"
bk_check bk-500 "$BK_CANARY"
if [[ "$BK_RC" -eq 1 && -z "$BK_FAIL" ]] && grep -qF 'HTTP 500' "$ROWS/bk-500/out"; then
  row "backup arm 500: exit 1 with the HTTP code only, the response body canary absent" ok
else row "backup arm 500: exit 1 with the HTTP code only, the response body canary absent" fail "rc=$BK_RC checks: $BK_FAIL"; fi
bk_run bk-000 "$BK_CANARY" 000 "$BKDIR/create-err.json" "$BKDIR/action-success.json"
if [[ "$BK_RC" -eq 1 ]] && grep -qF 'HTTP 000' "$ROWS/bk-000/out" && [[ "$(bk_count "$ROWS/bk-000/out" "$BK_BODYCANARY")" == 0 ]] \
   && [[ "$(bk_count "$ROWS/bk-000/out" "$BK_CANARY")" == 1 ]]; then
  row "backup arm transport failure (curl exit 7): exit 1 reporting HTTP 000, the token only on the mask line" ok
else row "backup arm transport failure (curl exit 7): exit 1 reporting HTTP 000, the token only on the mask line" fail "rc=$BK_RC"; fi

# action error: the id is printed, the action document (it carries error text) never is.
bk_run bk-actionerr "$BK_CANARY" 201 "$BKDIR/create-ok.json" "$BKDIR/action-error.json"
bk_check bk-actionerr "$BK_CANARY"
if [[ "$BK_RC" -eq 1 && -z "$BK_FAIL" ]] && grep -qF 'action 222 failed' "$ROWS/bk-actionerr/out"; then
  row "backup arm action error: exit 1 naming the action id, the action document (response body canary) absent from output" ok
else row "backup arm action error: exit 1 naming the action id, the action document (response body canary) absent from output" fail "rc=$BK_RC checks: $BK_FAIL"; fi

# hostile / empty Doppler value: refused before the mask and before any request; the value never appears.
BK_HOSTILE=$'abc\n::error::injected-'"$BK_CANARY"
for hv in "newline-and-workflow-command:$BK_HOSTILE" "space:abc def-$BK_CANARY" "quote:abc\"def-$BK_CANARY" "empty:"; do
  hname="${hv%%:*}"; hval="${hv#*:}"
  bk_run "bk-hostile-$hname" "$hval" 201 "$BKDIR/create-ok.json" "$BKDIR/action-success.json"
  hbad=""
  [[ "$BK_RC" -eq 1 ]] || hbad+=" rc=$BK_RC"
  [[ "$(bk_calls "$ROWS/bk-hostile-$hname")" == 0 ]] || hbad+=" curl-called"
  [[ "$(bk_count "$ROWS/bk-hostile-$hname/out" '::add-mask::')" == 0 ]] || hbad+=" mask-printed"
  [[ "$(bk_count "$ROWS/bk-hostile-$hname/out" "$BK_CANARY")" == 0 ]] || hbad+=" value-in-output"
  [[ "$(bk_count "$ROWS/bk-hostile-$hname/out" 'SOLEUR_CREDENTIAL_REFUSED script=cutover-inngest reason=token_shape')" == 1 ]] || hbad+=" no-marker"
  if [[ -z "$hbad" ]]; then row "backup arm refuses a $hname Doppler value before the mask and before any request (rc 1, zero curl calls, one value-free marker)" ok
  else row "backup arm refuses a $hname Doppler value before the mask and before any request (rc 1, zero curl calls, one value-free marker)" fail "$hbad"; fi
done

# static rows over the real script (pattern compile pre-check first: grep rc 2 must not read as "absent").
BK_ARM="$BKDIR/arm.txt"
awk '/^  backup\)$/{f=1} f{print} f&&/^    ;;$/{exit}' "$CUT" > "$BK_ARM"
ERE_BK_ERRCAT='::error::[^"]*\$\(cat /tmp/backup-'; ERE_BK_CAT='cat /tmp/backup-(action|body)'
bk_pre=0
for ere in "$ERE_BK_ERRCAT" "$ERE_BK_CAT"; do grep -E -e "$ere" /dev/null >/dev/null 2>&1; [[ $? -eq 1 ]] || bk_pre=1; done
n_bodycat="$(grep -cE -e "$ERE_BK_ERRCAT" "$BK_ARM" || true)"
n_actioncat="$(grep -cE -e "$ERE_BK_CAT" "$BK_ARM" || true)"
if [[ "$bk_pre" -eq 0 && "$n_bodycat" == 0 && "$n_actioncat" == 0 ]]; then
  row "static: no cat of the backup body or action document remains in the backup arm (no \$(cat /tmp/backup- in any ::error:: line)" ok
else row "static: no cat of the backup body or action document remains in the backup arm (no \$(cat /tmp/backup- in any ::error:: line)" fail "pre=$bk_pre error-cat=$n_bodycat cat=$n_actioncat"; fi
mask_ln="$(grep -n -m1 "add-mask::" "$BK_ARM" | cut -d: -f1)"
curl_ln="$(grep -n -m1 '_bearer_curl HCLOUD_TOKEN' "$BK_ARM" | cut -d: -f1)"
shape_ln="$(grep -n -m1 '_bearer_ok "\$HCLOUD_TOKEN"' "$BK_ARM" | cut -d: -f1)"
if [[ -n "$mask_ln" && -n "$curl_ln" && -n "$shape_ln" && "$shape_ln" -lt "$mask_ln" && "$mask_ln" -lt "$curl_ln" ]]; then
  row "static: in the backup arm the shape check precedes the ::add-mask:: line, which precedes the first _bearer_curl HCLOUD_TOKEN" ok
else row "static: in the backup arm the shape check precedes the ::add-mask:: line, which precedes the first _bearer_curl HCLOUD_TOKEN" fail "shape=$shape_ln mask=$mask_ln curl=$curl_ln"; fi
# MUTATIONS of the extracted driver (one literal per mutant; mutated_copy is FATAL when the literal is absent). Each
# must turn the named check RED, so the rows above are proven able to fail and not merely observed green.
bk_mut() { # <mutant> <from> <to> [<from2> <to2>] -> $BKDIR/mut-<mutant>.sh
  local out="$BKDIR/mut-$1.sh"
  mutated_copy "$BKDRV" "$out" "$2" "$3"
  [[ -n "${4:-}" ]] && mutated_copy "$out" "$out.2" "$4" "$5" && mv "$out.2" "$out"
  printf '%s' "$out"
}
BK_MASK_LINE='printf '"'"'::add-mask::%s\n'"'"' "$HCLOUD_TOKEN" >&2'
m="$(bk_mut nomask "$BK_MASK_LINE" ':')"
bk_run bk-mut-nomask "$BK_CANARY" 201 "$BKDIR/create-ok.json" "$BKDIR/action-success.json" "$m"; bk_check bk-mut-nomask "$BK_CANARY"
if [[ " $BK_FAIL " == *" mask-not-first "* && " $BK_FAIL " == *" mask-count "* ]]; then row "mutation: the mask line removed turns the 201 row RED (mask-not-first, mask-count)" ok
else row "mutation: the mask line removed turns the 201 row RED (mask-not-first, mask-count)" fail "checks: $BK_FAIL"; fi
m="$(bk_mut maskafter "$BK_MASK_LINE" ':' 'IMAGE_ID=$(jq' "$BK_MASK_LINE"$'\n    IMAGE_ID=$(jq')"
bk_run bk-mut-maskafter "$BK_CANARY" 201 "$BKDIR/create-ok.json" "$BKDIR/action-success.json" "$m"; bk_check bk-mut-maskafter "$BK_CANARY"
if [[ " $BK_FAIL " == *" mask-after-curl "* && " $BK_FAIL " == *" mask-not-first "* ]]; then row "mutation: the mask line moved after the first curl call turns the 201 row RED (mask-after-curl)" ok
else row "mutation: the mask line moved after the first curl call turns the 201 row RED (mask-after-curl)" fail "checks: $BK_FAIL"; fi
m="$(bk_mut bodyecho 'if [[ "$CODE" != "201" ]]; then' 'if [[ "$CODE" != "201" ]]; then echo "::error::body: $(cat ${BK_TMP}/backup-body 2>/dev/null)";')"
bk_run bk-mut-bodyecho "$BK_CANARY" 403 "$BKDIR/create-err.json" "$BKDIR/action-success.json" "$m"; bk_check bk-mut-bodyecho "$BK_CANARY"
if [[ " $BK_FAIL " == *" body-in-output "* ]]; then row "mutation: the response body echoed on non-201 turns the 403 row RED (body-in-output)" ok
else row "mutation: the response body echoed on non-201 turns the 403 row RED (body-in-output)" fail "checks: $BK_FAIL"; fi
m="$(bk_mut actioncat 'error) echo' 'error) cat ${BK_TMP}/backup-action; echo')"
bk_run bk-mut-actioncat "$BK_CANARY" 201 "$BKDIR/create-ok.json" "$BKDIR/action-error.json" "$m"; bk_check bk-mut-actioncat "$BK_CANARY"
if [[ " $BK_FAIL " == *" body-in-output "* ]]; then row "mutation: the action document printed on action error turns the action-error row RED (body-in-output)" ok
else row "mutation: the action document printed on action error turns the action-error row RED (body-in-output)" fail "checks: $BK_FAIL"; fi
m="$(bk_mut noshape 'if ! _bearer_ok "$HCLOUD_TOKEN"; then' 'if false; then')"
bk_run bk-mut-noshape "abc"$'\n'"::error::injected-$BK_CANARY" 201 "$BKDIR/create-ok.json" "$BKDIR/action-success.json" "$m"
if [[ "$(bk_count "$ROWS/bk-mut-noshape/out" "$BK_CANARY")" -ge 1 || "$(bk_calls "$ROWS/bk-mut-noshape")" -ge 1 ]]; then row "mutation: the shape check removed lets a hostile value reach the mask line or curl (the hostile rows go RED)" ok
else row "mutation: the shape check removed lets a hostile value reach the mask line or curl (the hostile rows go RED)" fail "the mutant behaved like the original"; fi
echo "=== stage S2-A part 1: backup arm (#8767) done ==="

