# shellcheck shell=bash
# SOURCED FRAGMENT of tests/scripts/test-argv-bearer-sweep.sh -- NOT independently runnable.
# =====================================================================================
# STAGE S2-A part 2: the HMAC key of the deploy webhook off `openssl`'s argument list (D1/D3).
# All 19 `openssl dgst -sha256 -hmac "$WEBHOOK_SECRET"` sites are the CANONICAL SNIPPET: the key rides
# the python3 child's ENVIRONMENT only (per-command prefix). The two sites in the `registry-probe)` and
# `doublefire-probe)` arms were the last holdouts (the infra suite's tool census counted a python3 token in those arms); #9757 converted
# them and moved the allowance into the census's single code view (`_probe_arms_code_of` in
# apps/web-platform/infra/cutover-inngest-workflow.test.sh: exactly the two canonical line forms, fixed-string whole-line). The committed
# oracle is the OTHER implementation, `openssl dgst -hmac`, only ever run here with a synthetic key.
# =====================================================================================
HM_CANON="$(cat <<'HM_EOF'
HMAC_KEY="$WEBHOOK_SECRET" python3 -I -c 'import hashlib,hmac,os,sys;k=os.environb.get(b"HMAC_KEY");k or sys.exit(1);sys.stdout.write(hmac.new(k,sys.stdin.buffer.read(),hashlib.sha256).hexdigest())'
HM_EOF
)"
PYDIR="$TMPD/pybin"; HMBIN="$TMPD/hmbin"
for d in "$PYDIR" "$HMBIN"; do assert_fixture_dir "$d"; mkdir -p "$d"; done
REAL_PY="$(type -P python3 || true)"; REAL_OSSL="$(type -P openssl || true)"
[[ -n "$REAL_PY" && -n "$REAL_OSSL" ]] || fatal "stage S2-A part 2: python3 and openssl are both required (canonical snippet + oracle)"
ln -s "$REAL_PY" "$PYDIR/python3"
# Recording tool shim: argv (NUL-delimited), whether HMAC_KEY was present in the tool's own environment, then the REAL tool.
cat > "$HMBIN/rec" <<'REC_EOF'
#!/usr/bin/env bash
D="${BK_SHIM:-}"; tool="${0##*/}"
if [[ -n "$D" ]]; then
  mkdir -p "$D/tools"; n=0
  [[ -r "$D/tools/$tool.n" ]] && read -r n < "$D/tools/$tool.n"
  n=$((n + 1)); printf '%s\n' "$n" > "$D/tools/$tool.n"
  printf '%s\0' "$@" > "$D/tools/$tool-$n.argv"
  [[ -n "${HMAC_KEY+x}" ]] && printf 'present\n' > "$D/tools/$tool-$n.hmackey"
fi
exec "@REAL@" "$@"
REC_EOF
for t in python3 openssl; do
  real="$REAL_PY"; [[ "$t" == openssl ]] && real="$REAL_OSSL"
  sed "1s|.*|#!${BASH_BIN}|; s|@REAL@|${real}|" "$HMBIN/rec" > "$HMBIN/$t"; chmod +x "$HMBIN/$t"
done
rm -f "$HMBIN/rec"

# hm_sign <key> <bodyfile>: the canonical snippet under a clean environment (no inherited HMAC_KEY / PYTHON*).
hm_sign() { env -i PATH="$PYDIR:$REALBIN" WEBHOOK_SECRET="$1" "$BASH_BIN" -c "$HM_CANON" < "$2" 2>/dev/null; }
hm_oracle() { "$REAL_OSSL" dgst -sha256 -hmac "$1" < "$2" | sed 's/.*= //'; }

# --- the canonical snippet ---------------------------------------------------------------------
if [[ "$(LC_ALL=C; printf '%s' "${#HM_CANON}")" == 198 ]]; then row "canonical snippet: 198 bytes, as measured and oracle-checked in Phase 0" ok
else row "canonical snippet: 198 bytes, as measured and oracle-checked in Phase 0" fail "length=$(LC_ALL=C; printf '%s' "${#HM_CANON}")"; fi
printf '' > "$BKDIR/body-empty"
printf '%s' '{"tenant":"synthetic","n":[1,2,3],"s":"a\"b"}' > "$BKDIR/body-json"
printf '%s\n' '{"x":1}' > "$BKDIR/body-nl"
head -c 100000 /dev/zero | tr '\0' 'x' > "$BKDIR/body-big"
HM_KEYS=("k" "$(printf '%*s' 20 '' | tr ' ' 'a')" "$(printf '%*s' 63 '' | tr ' ' 'b')" "$(printf '%*s' 64 '' | tr ' ' '6')" \
  "$(printf '%*s' 65 '' | tr ' ' 'c')" "$(printf '%*s' 96 '' | tr ' ' 'd')" "$(printf '%*s' 200 '' | tr ' ' 'e')" 'a"b\c $d '"'"'e;f|g&h')
hm_bad=""; hm_n=0
for k in "${HM_KEYS[@]}"; do
  for b in empty json nl big; do
    hm_n=$((hm_n + 1))
    got="$(hm_sign "$k" "$BKDIR/body-$b")"; want="$(hm_oracle "$k" "$BKDIR/body-$b")"
    [[ -n "$want" && "$got" == "$want" && "${#got}" == 64 ]] || hm_bad+=" ${#k}/$b"
  done
done
if [[ -z "$hm_bad" && "$hm_n" == 32 ]]; then row "canonical snippet oracle: equals openssl dgst -hmac for 8 synthetic keys (1, 20, 63, 64, 65, 96, 200 bytes and shell-hostile characters) x 4 bodies (empty, JSON, trailing newline, 100 KB)" ok
else row "canonical snippet oracle: equals openssl dgst -hmac for 8 synthetic keys (1, 20, 63, 64, 65, 96, 200 bytes and shell-hostile characters) x 4 bodies (empty, JSON, trailing newline, 100 KB)" fail "n=$hm_n mismatched (keylen/body):$hm_bad"; fi
hm_out="$(env -i PATH="$PYDIR:$REALBIN" "$BASH_BIN" -c "$HM_CANON" < "$BKDIR/body-empty" 2>/dev/null)"; hm_rc=$?
hm_out2="$(env -i PATH="$PYDIR:$REALBIN" WEBHOOK_SECRET= "$BASH_BIN" -c "$HM_CANON" < "$BKDIR/body-empty" 2>/dev/null)"; hm_rc2=$?
hm_out3="$(env -i PATH="$PYDIR:$REALBIN" "$BASH_BIN" -c "set -u; $HM_CANON" < "$BKDIR/body-empty" 2>/dev/null)"; hm_rc3=$?
if [[ "$hm_rc" -ne 0 && -z "$hm_out" && "$hm_rc2" -ne 0 && -z "$hm_out2" && "$hm_rc3" -ne 0 && -z "$hm_out3" ]]; then
  row "canonical snippet: an unset key, an empty key and an unset key under set -u each exit non-zero and print nothing (no silent signature over an empty key)" ok
else row "canonical snippet: an unset key, an empty key and an unset key under set -u each exit non-zero and print nothing (no silent signature over an empty key)" fail "rc unset=$hm_rc empty=$hm_rc2 set-u=$hm_rc3"; fi
hm_leak="$(env -i PATH="$PYDIR:$REALBIN" WEBHOOK_SECRET=synthetic-key "$BASH_BIN" -c "X=\$(printf '' | $HM_CANON); [[ -z \"\${HMAC_KEY+x}\" ]] && printf clean" 2>/dev/null)"
if [[ "$hm_leak" == clean ]]; then row "canonical snippet: HMAC_KEY is a per-command prefix and does not exist in the calling shell afterwards" ok
else row "canonical snippet: HMAC_KEY is a per-command prefix and does not exist in the calling shell afterwards" fail "out=$hm_leak"; fi
# The key reaches python3 through its environment only: recording python3 shim (argv + HMAC_KEY presence), real python3 behind it.
HM_SK="synthetic-argv-key-$(od -An -N6 -tx1 /dev/urandom | tr -d ' \n')"
mkdir -p "$ROWS/hm-argv"
env -i PATH="$HMBIN:$PYDIR:$REALBIN" BK_SHIM="$ROWS/hm-argv" WEBHOOK_SECRET="$HM_SK" "$BASH_BIN" -c "$HM_CANON" < "$BKDIR/body-json" > "$ROWS/hm-argv/out" 2>&1
if [[ -e "$ROWS/hm-argv/tools/python3-1.argv" && -e "$ROWS/hm-argv/tools/python3-1.hmackey" ]] \
   && ! grep -aqF -- "$HM_SK" "$ROWS/hm-argv/tools/python3-1.argv"; then
  row "canonical snippet: the key is in python3's environment (HMAC_KEY present) and in no recorded argument of python3" ok
else row "canonical snippet: the key is in python3's environment (HMAC_KEY present) and in no recorded argument of python3" fail "argv/env evidence missing or key in argv"; fi

# --- parity: every converted copy equals the canonical string; no -hmac operand is left in the script ---
hm_arm_count() { # <from-arm-regex> <to-arm-regex> <ere> <file> -> count of lines matching <ere> inside the arm range [from, to)
  awk -v from="$1" -v to="$2" -v re="$3" '$0 ~ from {f=1; next} $0 ~ to {f=0} f && $0 ~ re {n++} END {print n+0}' "$4"
}
# hm_audit <script> [default-want]: ONE function reads the parity facts, so the real rows and the mutation rows below judge with the same code.
#   It reads ANY indentation (the cutover script's copies sit at 4 spaces, the workflow-step copies at 10, the two inline scripts at 0), and
#   the body a site signs is derived from the arm's own `_sig_curl <VAR>` request; a file whose request is not an `_sig_curl` call (the two
#   inline scripts, which print their header directives themselves) passes [default-want] (`empty`: a status GET).
#   HM_BAD    space-separated copy indices that differ from the canonical snippet, lost the SIG=$(printf <body> | ...) shape, lost the
#             `|| VAR=""` fallback, or sign a body other than the one their own request carries (derived per site, see below)
#   HM_NCOPY  converted copies; HM_NOLD lines carrying the -hmac operand; HM_RP / HM_DP of those inside the registry-probe) /
#   doublefire-probe) arms; HM_PYARMS python3 tokens inside the registry-probe) .. rearm) range (the two canonical lines, the ONLY ones the
#   infra suite's census allowance lets through)
HM_RE_EMPTY='^[[:space:]]*[A-Z][A-Za-z0-9_]*=\$\(printf '"''"' \| HMAC_KEY='
HM_RE_PAYLOAD='^[[:space:]]*[A-Z][A-Za-z0-9_]*=\$\(printf '"'%s'"' "\$PAYLOAD" \| HMAC_KEY='
hm_audit() {
  local f="$1" dflt="${2:-}" ln rest seg i=0 shape n j k var tail blk want
  local -a L
  HM_BAD=""
  mapfile -t L < "$f"
  for n in "${!L[@]}"; do
    ln="${L[n]}"
    [[ "$ln" == *'HMAC_KEY="$WEBHOOK_SECRET" python3'* ]] || continue
    i=$((i + 1)); shape=0
    # the assigned variable and the fail-safe fallback `|| VAR=""` (an empty WEBHOOK_SECRET or a missing python3 must leave VAR empty so
    # _sig_curl's _bearer_ok refuses with the marker, instead of `set -e` aborting the whole script at the assignment, mute)
    var="${ln%%=*}"; var="${var#"${var%%[![:space:]]*}"}"
    rest="${ln#*| }"; tail=") || ${var}=\"\""; seg=""
    [[ "$rest" == *"$tail" ]] && seg="${rest%"$tail"}"
    # the body this site signs is DERIVED from the arm's own request, never hand-listed: the first `_sig_curl <VAR>` after the site, with its
    # backslash continuations; a request carrying `-d "$PAYLOAD"` / `--data` signs `printf '%s' "$PAYLOAD"`, any other (a GET) signs `printf ''`
    blk=""
    for ((j = n + 1; j < n + 40 && j < ${#L[@]}; j++)); do
      if [[ "${L[j]}" == *"_sig_curl $var "* ]]; then
        k=$j; blk="${L[k]}"
        while [[ "${L[k]}" == *'\' && $((k + 1)) -lt ${#L[@]} ]]; do k=$((k + 1)); blk+=" ${L[k]}"; done
        break
      fi
    done
    want="$dflt"
    if [[ -n "$blk" ]]; then
      if [[ "$blk" == *'-d "$PAYLOAD"'* || "$blk" == *' --data'* ]]; then want=payload; else want=empty; fi
    fi
    case "$want" in
      empty) [[ "$ln" =~ $HM_RE_EMPTY ]] && shape=1 ;;
      payload) [[ "$ln" =~ $HM_RE_PAYLOAD ]] && shape=1 ;;
    esac
    [[ "$seg" == "$HM_CANON" && "$shape" == 1 ]] || HM_BAD+=" $i"
  done
  HM_NCOPY=$i
  HM_NOLD="$(grep -cF -e '-hmac' "$f" || true)"
  HM_RP="$(hm_arm_count '^[[:space:]]+registry-probe[)]$' '^[[:space:]]+doublefire-probe[)]$' 'openssl dgst -sha256 -hmac "[$]WEBHOOK_SECRET"' "$f")"
  HM_DP="$(hm_arm_count '^[[:space:]]+doublefire-probe[)]$' '^[[:space:]]+rearm[)]$' 'openssl dgst -sha256 -hmac "[$]WEBHOOK_SECRET"' "$f")"
  HM_PYARMS="$(hm_arm_count '^[[:space:]]+registry-probe[)]$' '^[[:space:]]+rearm[)]$' 'python3' "$f")"
}
# hm_audit_ok: the whole parity contract at once (19 identical copies, no -hmac operand anywhere, exactly the two canonical python3 lines in the probe-arm range).
hm_audit_ok() { [[ -z "$HM_BAD" && "$HM_NCOPY" == 19 && "$HM_NOLD" == 0 && "$HM_RP" == 0 && "$HM_DP" == 0 && "$HM_PYARMS" == 2 ]]; }
hm_audit "$CUT"
for hm_i in $(seq 1 19); do
  if [[ " $HM_BAD " != *" $hm_i "* && "$hm_i" -le "$HM_NCOPY" ]]; then row "cutover HMAC copy $hm_i equals the canonical snippet, keeps the SIG=\$(printf <body> | ...) || SIG=\"\" shape and signs the body its own request carries" ok
  else row "cutover HMAC copy $hm_i equals the canonical snippet, keeps the SIG=\$(printf <body> | ...) || SIG=\"\" shape and signs the body its own request carries" fail "copy missing or differs from the canonical string, lost its fallback, or signs the wrong body (bad:$HM_BAD copies=$HM_NCOPY)"; fi
done
if [[ "$HM_NCOPY" == 19 && -z "$HM_BAD" ]]; then row "cutover HMAC: exactly 19 converted copies (every one of the 19 sites), no extra or divergent copy" ok
else row "cutover HMAC: exactly 19 converted copies (every one of the 19 sites), no extra or divergent copy" fail "copies=$HM_NCOPY bad:$HM_BAD"; fi
if [[ "$HM_NOLD" == 0 && "$HM_RP" == 0 && "$HM_DP" == 0 && "$HM_PYARMS" == 2 ]]; then
  row "cutover HMAC: zero -hmac operands remain in the script (registry-probe) and doublefire-probe) are converted) and the probe-arm range holds exactly the two canonical python3 lines" ok
else row "cutover HMAC: zero -hmac operands remain in the script (registry-probe) and doublefire-probe) are converted) and the probe-arm range holds exactly the two canonical python3 lines" fail "file=$HM_NOLD registry-probe=$HM_RP doublefire-probe=$HM_DP python3-in-arms=$HM_PYARMS"; fi

# MUTATIONS of the parity contract: one mutant per copy index and per kind, each judged by the SAME hm_audit. A suite that
# only ever audits the first copy, or counts instead of comparing bytes, leaves one of these green.
nth_replace() { # <src> <out> <needle> <repl> <n>: replace the n-th occurrence only; rc 3 when there are fewer than n
  assert_fixture_dir "$2"
  "$REAL_PY" -I -c '
import sys
src, out, needle, repl, n = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], int(sys.argv[5])
s = open(src).read(); i = -1
for _ in range(n):
    i = s.find(needle, i + 1)
    if i < 0:
        sys.exit(3)
open(out, "w").write(s[:i] + repl + s[i + len(needle):])
' "$1" "$2" "$3" "$4" "$5"
}
HM_PFX='HMAC_KEY="$WEBHOOK_SECRET" python3 -I -c'
# hm_touched <original> <mutant>: the changed line RANGES of the mutant (diff normal format, e.g. "1328c1328"); a mutant must touch
# exactly the line it claims to, so a mutation that landed somewhere else cannot satisfy its row.
hm_touched() { diff "$1" "$2" | grep -E '^[0-9,]+c[0-9,]+$' | paste -sd' ' -; }
hm_nth_line() { grep -n -F -e "$3" "$2" | sed -n "${1}p" | cut -d: -f1; } # <n> <file> <literal> -> line number of the n-th match
for idx in $(seq 1 19); do
  nth_replace "$CUT" "$BKDIR/hm-mut-$idx.sh" "$HM_PFX" 'HMAC_KEY="$WEBHOOK_SECRET" python3 -c' "$idx" || fatal "parity mutation $idx did not land"
  hm_audit "$BKDIR/hm-mut-$idx.sh"; hm_ln="$(hm_nth_line "$idx" "$CUT" 'HMAC_KEY="$WEBHOOK_SECRET" python3')"
  if [[ "$HM_BAD" == " $idx" && "$(hm_touched "$CUT" "$BKDIR/hm-mut-$idx.sh")" == "${hm_ln}c${hm_ln}" ]] && ! hm_audit_ok; then row "mutation: dropping -I from copy $idx alone (line $hm_ln only) is caught as exactly copy $idx (parity is per copy, not first copy)" ok
  else row "mutation: dropping -I from copy $idx alone (line $hm_ln only) is caught as exactly copy $idx (parity is per copy, not first copy)" fail "bad:$HM_BAD touched:$(hm_touched "$CUT" "$BKDIR/hm-mut-$idx.sh") want:${hm_ln}c${hm_ln}"; fi
done
nth_replace "$CUT" "$BKDIR/hm-mut-emptykey.sh" 'k or sys.exit(1);' '' 7 || fatal "parity mutation emptykey did not land"
hm_audit "$BKDIR/hm-mut-emptykey.sh"; hm_ln="$(hm_nth_line 7 "$CUT" 'HMAC_KEY="$WEBHOOK_SECRET" python3')"
if [[ "$HM_BAD" == " 7" && "$(hm_touched "$CUT" "$BKDIR/hm-mut-emptykey.sh")" == "${hm_ln}c${hm_ln}" ]]; then row "mutation: dropping the empty-key exit from copy 7 alone (line $hm_ln only) is caught as exactly copy 7" ok
else row "mutation: dropping the empty-key exit from copy 7 alone (line $hm_ln only) is caught as exactly copy 7" fail "bad:$HM_BAD touched:$(hm_touched "$CUT" "$BKDIR/hm-mut-emptykey.sh")"; fi
nth_replace "$CUT" "$BKDIR/hm-mut-argvback.sh" "$HM_CANON" "openssl dgst -sha256 -hmac \"\$WEBHOOK_SECRET\" | sed 's/.*= //'" 5 || fatal "parity mutation argvback did not land"
hm_audit "$BKDIR/hm-mut-argvback.sh"
if [[ "$HM_NCOPY" == 18 && "$HM_NOLD" == 1 ]] && ! hm_audit_ok; then row "mutation: the key put back on openssl's argv in copy 5 is caught (18 copies, a -hmac operand where the script has none)" ok
else row "mutation: the key put back on openssl's argv in copy 5 is caught (18 copies, a -hmac operand where the script has none)" fail "copies=$HM_NCOPY -hmac=$HM_NOLD"; fi
{ cat "$CUT"; printf '%s\n' "    SIGX=\$(printf '' | ${HM_CANON/sha256/sha1})"; } > "$BKDIR/hm-mut-extra.sh"
hm_audit "$BKDIR/hm-mut-extra.sh"
if [[ "$HM_NCOPY" == 20 && " $HM_BAD " == *" 20 "* ]] && ! hm_audit_ok; then row "mutation: a 20th inline copy that differs by one byte is caught (copy count and byte comparison)" ok
else row "mutation: a 20th inline copy that differs by one byte is caught (copy count and byte comparison)" fail "copies=$HM_NCOPY bad:$HM_BAD"; fi
# The two probe arms (copies 2 and 3, in file order) put back on the argv form: each revert is caught by the parity contract AND by the S4 HMAC census
# (the allow-list is empty), pinned to its own arm anchor. The two mutants live on in $BKDIR for the census rows in stage S4.
for hm_rv in "revert1:2:1:0:registry-probe)" "revert2:3:0:1:doublefire-probe)"; do
  IFS=: read -r hm_rvn hm_rvi hm_rvrp hm_rvdp hm_rvarm <<< "$hm_rv"
  nth_replace "$CUT" "$BKDIR/hm-mut-$hm_rvn.sh" "$HM_CANON" "openssl dgst -sha256 -hmac \"\$WEBHOOK_SECRET\" | sed 's/.*= //'" "$hm_rvi" || fatal "parity mutation $hm_rvn did not land"
  hm_audit "$BKDIR/hm-mut-$hm_rvn.sh"; hm_ln="$(hm_nth_line "$hm_rvi" "$CUT" 'HMAC_KEY="$WEBHOOK_SECRET" python3')"
  if [[ "$HM_NCOPY" == 18 && "$HM_NOLD" == 1 && "$HM_RP" == "$hm_rvrp" && "$HM_DP" == "$hm_rvdp" && "$HM_PYARMS" == 1 && "$(hm_touched "$CUT" "$BKDIR/hm-mut-$hm_rvn.sh")" == "${hm_ln}c${hm_ln}" ]] && ! hm_audit_ok; then row "mutation: reverting the $hm_rvarm site to openssl dgst -hmac (line $hm_ln only) is caught, pinned by its arm anchor (registry-probe) count $hm_rvrp, doublefire-probe) count $hm_rvdp)" ok
  else row "mutation: reverting the $hm_rvarm site to openssl dgst -hmac (line $hm_ln only) is caught, pinned by its arm anchor (registry-probe) count $hm_rvrp, doublefire-probe) count $hm_rvdp)" fail "copies=$HM_NCOPY -hmac=$HM_NOLD registry-probe=$HM_RP doublefire-probe=$HM_DP python3-in-arms=$HM_PYARMS touched:$(hm_touched "$CUT" "$BKDIR/hm-mut-$hm_rvn.sh") want:${hm_ln}c${hm_ln}"; fi
done

# Mutants of the two per-site facets hm_audit now owns (the fail-safe fallback and the body each site signs). hm_site_mut rewrites ONLY
# the idx-th converted site line (sets HM_MUT_LN to its line number); every row asserts the mutant touched exactly that line, that the
# audit names exactly that copy, and that the whole-contract check is red.
hm_site_mut() { # <idx> <out> <kind: nofallback|wrongvar|body-empty|body-payload>
  local idx="$1" out="$2" kind="$3" n=0 i ln pe pp
  local -a lines
  assert_fixture_dir "$out"
  mapfile -t lines < "$CUT"
  pe="printf '' |"; pp="printf '%s' \"\$PAYLOAD\" |"
  for i in "${!lines[@]}"; do
    ln="${lines[i]}"
    [[ "$ln" == *'HMAC_KEY="$WEBHOOK_SECRET" python3'* ]] || continue
    n=$((n + 1)); [[ "$n" == "$idx" ]] || continue
    HM_MUT_LN=$((i + 1))
    case "$kind" in
      nofallback) lines[i]="${ln% || *}" ;;
      wrongvar) lines[i]="${ln% || *} || XSIG=\"\"" ;;
      body-empty) lines[i]="${ln/"$pp"/"$pe"}" ;;
      body-payload) lines[i]="${ln/"$pe"/"$pp"}" ;;
    esac
  done
  printf '%s\n' "${lines[@]}" > "$out"
}
hm_first_idx() { # <file> <literal> -> the index, among the converted copies, of the first one whose line holds <literal> (empty when none)
  local n=0 ln
  while IFS= read -r ln; do n=$((n + 1)); [[ "$ln" == *"$2"* ]] && { printf '%s' "$n"; return 0; }; done < <(grep -F 'HMAC_KEY="$WEBHOOK_SECRET" python3' "$1")
  return 0
}
hm_audit "$CUT"; hm_last="$HM_NCOPY"
hm_idx_payload="$(hm_first_idx "$CUT" "printf '%s' \"\$PAYLOAD\" |")"; hm_idx_empty="$(hm_first_idx "$CUT" "printf '' |")"
[[ -n "$hm_idx_payload" && -n "$hm_idx_empty" && "$hm_last" == 19 && -z "$HM_BAD" ]] || fatal "parity mutations: could not derive a payload-body copy and an empty-body copy from the real script"
for hm_k in "nofallback:$hm_last:dropping the || SIG=\"\" fallback from the last copy" "nofallback:1:dropping the || SIG=\"\" fallback from the first copy" \
            "wrongvar:$hm_idx_payload:SHAPE PIN only (behaviourally equivalent to the real fallback, since the assignment has already left its variable empty; not a behaviour catch): a fallback that blanks a different variable (copy $hm_idx_payload)" \
            "body-empty:$hm_idx_payload:signing the empty body in copy $hm_idx_payload, whose request carries -d \"\$PAYLOAD\" (a POST signed over nothing is a 401)" \
            "body-payload:$hm_idx_empty:signing \$PAYLOAD in copy $hm_idx_empty, whose request is a bodyless GET"; do
  IFS=: read -r hm_kind hm_idx hm_desc <<< "$hm_k"
  hm_site_mut "$hm_idx" "$BKDIR/hm-mut-$hm_kind-$hm_idx.sh" "$hm_kind"; hm_audit "$BKDIR/hm-mut-$hm_kind-$hm_idx.sh"
  if [[ "$HM_BAD" == " $hm_idx" && "$(hm_touched "$CUT" "$BKDIR/hm-mut-$hm_kind-$hm_idx.sh")" == "${HM_MUT_LN}c${HM_MUT_LN}" ]] && ! hm_audit_ok; then row "mutation: $hm_desc is caught as exactly copy $hm_idx (line $HM_MUT_LN only)" ok
  else row "mutation: $hm_desc is caught as exactly copy $hm_idx (line $HM_MUT_LN only)" fail "bad:$HM_BAD touched:$(hm_touched "$CUT" "$BKDIR/hm-mut-$hm_kind-$hm_idx.sh") want:${HM_MUT_LN}c${HM_MUT_LN}"; fi
done

# --- the refusal marker on the _sig_curl / _bearer_curl refusal arms ---------------------------------
SC_DRV="$BKDIR/sigdriver.sh"; assert_fixture_dir "$SC_DRV"
{
  printf 'set -euo pipefail\n'
  grep -m1 '^_bearer_ok() {' "$CUT"
  awk '/^_bearer_curl\(\) \{$/,/^}$/' "$CUT"
  awk '/^_sig_curl\(\) \{$/,/^}$/' "$CUT"
  printf 'case "$SC_CALL" in\n  sig) _sig_curl SIG http://127.0.0.1:9/x ;;\n  bearer) _bearer_curl TOK http://127.0.0.1:9/x ;;\nesac\n'
} > "$SC_DRV"
sc_run() { # <rowname> <SIG> <ID> <SECRET> <call> [TOK]
  local row="$ROWS/$1"; assert_fixture_dir "$row"; mkdir -p "$row/shim"
  ( cd "$row" && env -i PATH="$BKBIN:$REALBIN" BK_SHIM="$row/shim" SC_CALL="$5" SIG="$2" CF_ACCESS_CLIENT_ID="$3" CF_ACCESS_CLIENT_SECRET="$4" TOK="${6:-}" \
      "$BASH_BIN" "$SC_DRV" < /dev/null > "$row/stdout" 2> "$row/stderr" )
  SC_RC=$?
}
SC_MARK='SOLEUR_CREDENTIAL_REFUSED script=cutover-inngest reason=token_shape'
SC_HOT="hostile\"value-$BK_CANARY"
sc_ok_sig="$(printf '%*s' 64 '' | tr ' ' 'a')"
for case_spec in "sig-var:sig:$SC_HOT:cfid:cfsecret:" "cf-id:sig:$sc_ok_sig:$SC_HOT:cfsecret:" "cf-secret:sig:$sc_ok_sig:cfid:$SC_HOT:" "bearer-var:bearer:$sc_ok_sig:cfid:cfsecret:$SC_HOT"; do
  IFS=: read -r cname ccall csig cid csecret ctok <<< "$case_spec"
  sc_run "sc-$cname" "$csig" "$cid" "$csecret" "$ccall" "$ctok"
  scbad=""
  [[ "$SC_RC" -eq 2 ]] || scbad+=" rc=$SC_RC"
  [[ "$(bk_calls "$ROWS/sc-$cname")" == 0 ]] || scbad+=" curl-called"
  [[ "$(bk_count "$ROWS/sc-$cname/stderr" "$SC_MARK")" == 1 ]] || scbad+=" marker-count=$(bk_count "$ROWS/sc-$cname/stderr" "$SC_MARK")"
  [[ "$(bk_count "$ROWS/sc-$cname/stderr" "$BK_CANARY")" == 0 && "$(bk_count "$ROWS/sc-$cname/stdout" "$BK_CANARY")" == 0 ]] || scbad+=" value-in-output"
  if [[ -z "$scbad" ]]; then row "refusal arm $cname: a hostile value returns 2 with zero requests, exactly one value-free SOLEUR_CREDENTIAL_REFUSED marker on stderr, the value absent" ok
  else row "refusal arm $cname: a hostile value returns 2 with zero requests, exactly one value-free SOLEUR_CREDENTIAL_REFUSED marker on stderr, the value absent" fail "$scbad"; fi
done
sc_run sc-valid "$sc_ok_sig" cfid cfsecret sig
if [[ "$SC_RC" -eq 0 && "$(bk_calls "$ROWS/sc-valid")" == 1 && "$(bk_count "$ROWS/sc-valid/stderr" SOLEUR_CREDENTIAL_REFUSED)" == 0 ]] \
   && grep -qxF "header = \"X-Signature-256: sha256=$sc_ok_sig\"" "$ROWS/sc-valid/shim/calls/1.stdin"; then
  row "refusal arm control: a well-formed signature and Cloudflare Access pair reach curl on stdin with no marker" ok
else row "refusal arm control: a well-formed signature and Cloudflare Access pair reach curl on stdin with no marker" fail "rc=$SC_RC"; fi
n_sigfn_end="$(awk '/^_sig_curl\(\) \{$/,/^}$/' "$CUT" | grep -c '^}$' || true)"
if [[ "$n_sigfn_end" == 1 ]] && "$BASH_BIN" -n "$SC_DRV" 2>/dev/null; then row "_sig_curl stays one ^_sig_curl() {\$ ... ^}\$ range (the infra suite's awk splice extracts it whole) and the driver parses" ok
else row "_sig_curl stays one ^_sig_curl() {\$ ... ^}\$ range (the infra suite's awk splice extracts it whole) and the driver parses" fail "closers=$n_sigfn_end"; fi

# --- canary sweep: the real script, op=enumerate (the first converted site), shims in failure modes ----
CUTSB="$TMPD/cutsb"; assert_fixture_dir "$CUTSB"; mkdir -p "$CUTSB/scripts"
sed 's|/tmp/|${TMPDIR}/|g' "$CUT" > "$CUTSB/scripts/cutover-inngest.sh"   # same code; scratch paths instead of the shared /tmp
ln -s "$REPO_ROOT/scripts/lib" "$CUTSB/scripts/lib"
printf '%s' '[{"reminder_id":"r1"}]' > "$BODIES/enum_array.json"
printf '%s' '{not json' > "$BODIES/enum_malformed.json"
HM_WH="whcanary-$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')"
HM_CFID="cfid-canary-$(od -An -N6 -tx1 /dev/urandom | tr -d ' \n')"
HM_CFSEC="cfsec-canary-$(od -An -N6 -tx1 /dev/urandom | tr -d ' \n')"
cs_run() { # <rowname> <SHIM_MODE> <SHIM_STATUS or empty> <bodyfile> [NAME=value ...: environment that wins over the defaults; CS_PATH overrides the PATH; CS_NOWH=1 leaves WEBHOOK_SECRET out of the environment altogether]
  local row="$ROWS/$1" mode="$2" status="$3" body="$4"; shift 4
  local -a wh=("WEBHOOK_SECRET=$HM_WH")
  [[ "${CS_NOWH:-}" == 1 ]] && wh=()
  assert_fixture_dir "$row"; mkdir -p "$row/home" "$row/tmp" "$row/shim"
  ( cd "$row" && env -i PATH="${CS_PATH-$HMBIN:$SHIMDIR:$REALBIN:$PYDIR}" HOME="$row/home" TMPDIR="$row/tmp" SHIM_DIR="$row/shim" BK_SHIM="$row/shim" SHIM_FIXTURE_TOKEN="none" \
      SHIM_MODE="$mode" SHIM_STATUS="$status" SHIM_BODY_FILE="$body" OP=enumerate ${wh[@]+"${wh[@]}"} CF_ACCESS_CLIENT_ID="$HM_CFID" CF_ACCESS_CLIENT_SECRET="$HM_CFSEC" \
      "$@" "$BASH_BIN" "$CUTSB/scripts/cutover-inngest.sh" < /dev/null > "$row/stdout" 2> "$row/stderr" )
  CS_RC=$?
}
cs_leaks() { # <rowname> -> names of the places the canaries appear (empty = none): output, curl argv, openssl argv, python3 argv
  local row="$ROWS/$1" c f out=""
  for c in "$HM_WH" "$HM_CFID" "$HM_CFSEC"; do
    grep -aqF -- "$c" "$row/stdout" "$row/stderr" 2>/dev/null && out+=" output"
    for f in "$row"/shim/calls/*.argv "$row"/shim/tools/*.argv; do [[ -e "$f" ]] && grep -aqF -- "$c" "$f" && out+=" argv:${f##*/}"; done
  done
  printf '%s' "$out" | tr ' ' '\n' | awk 'NF && !s[$0]++' | paste -sd' ' -
}
cs_run cs-200 noauth "" "$BODIES/enum_array.json"
cs_expect="$(printf '' | "$REAL_OSSL" dgst -sha256 -hmac "$HM_WH" | sed 's/.*= //')"
cs_bad=""
[[ "$CS_RC" -eq 0 ]] || cs_bad+=" rc=$CS_RC"
[[ "$(bk_calls "$ROWS/cs-200")" -ge 1 ]] || cs_bad+=" no-curl-call"
grep -qxF "header = \"X-Signature-256: sha256=$cs_expect\"" "$ROWS/cs-200/shim/calls/1.stdin" 2>/dev/null || cs_bad+=" signature-on-stdin-differs-from-oracle"
[[ -n "$(cs_leaks cs-200)" ]] && cs_bad+=" leak:$(cs_leaks cs-200)"
if [[ -z "$cs_bad" ]]; then row "canary sweep op=enumerate, shim 200: the real script signs the request (stdin signature equals the openssl oracle) and the webhook key and Cloudflare Access values are in no argv or output" ok
else row "canary sweep op=enumerate, shim 200: the real script signs the request (stdin signature equals the openssl oracle) and the webhook key and Cloudflare Access values are in no argv or output" fail "$cs_bad"; fi
for mode in "401:401:$BODIES/enum_array.json" "500:500:$BODIES/enum_array.json" "malformed-200::$BODIES/enum_malformed.json"; do
  IFS=: read -r mname mstat mbody <<< "$mode"
  cs_run "cs-$mname" noauth "$mstat" "$mbody"
  cs_bad=""
  [[ "$(bk_calls "$ROWS/cs-$mname")" -ge 1 ]] || cs_bad+=" no-curl-call"
  [[ "$CS_RC" -eq 1 ]] || cs_bad+=" rc=$CS_RC"
  [[ -n "$(cs_leaks "cs-$mname")" ]] && cs_bad+=" leak:$(cs_leaks "cs-$mname")"
  if [[ -z "$cs_bad" ]]; then row "canary sweep op=enumerate, shim $mname: the script fails closed (rc 1, a recorded call) with no canary in any argv or output" ok
  else row "canary sweep op=enumerate, shim $mname: the script fails closed (rc 1, a recorded call) with no canary in any argv or output" fail "$cs_bad"; fi
done
cs_run cs-fail7 fail7 "" "$BODIES/enum_array.json"
cs_bad=""
[[ "$(bk_calls "$ROWS/cs-fail7")" -ge 1 ]] || cs_bad+=" no-curl-call"
[[ "$CS_RC" -eq 1 ]] || cs_bad+=" rc=$CS_RC"
[[ -n "$(cs_leaks cs-fail7)" ]] && cs_bad+=" leak:$(cs_leaks cs-fail7)"
if [[ -z "$cs_bad" ]]; then row "canary sweep op=enumerate, shim transport failure (curl exit 7): the script fails closed (rc 1) with no canary in any argv or output" ok
else row "canary sweep op=enumerate, shim transport failure (curl exit 7): the script fails closed (rc 1) with no canary in any argv or output" fail "$cs_bad"; fi
# --- the FAILURE MODE of the converted sites, driven at the call site: an empty WEBHOOK_SECRET, a missing python3 ----------------
# `SIG=$(... python3 ... k or sys.exit(1) ...)` under the script's `set -euo pipefail` ABORTS THE WHOLE SCRIPT SILENTLY when the substitution
# fails: no ::error::, no marker, only "Process completed with exit code 1" (measured; the #5492 class, and the old `openssl dgst -hmac ""` path
# printed a digest and an HTTP 401/403 diagnosis instead). Every site therefore ends `|| VAR=""`, so _sig_curl's _bearer_ok refuses WITH the
# marker and the arm's own ::error:: speaks. Two drivers: every converted site, extracted verbatim from the real script and run under
# `set -euo pipefail` with _bearer_ok/_sig_curl and the recording curl; and the real script (op=enumerate), end to end.
hf_drv() { # <idx> <out>: the idx-th converted site line verbatim, then a call that uses its variable
  local idx="$1" out="$2" n=0 ln="" var
  assert_fixture_dir "$out"
  while IFS= read -r ln; do n=$((n + 1)); [[ "$n" == "$idx" ]] && break; done < <(grep -F 'HMAC_KEY="$WEBHOOK_SECRET" python3' "$CUT")
  var="${ln%%=*}"; var="${var#"${var%%[![:space:]]*}"}"
  {
    printf 'set -euo pipefail\n'
    grep -m1 '^_bearer_ok() {' "$CUT"
    awk '/^_sig_curl\(\) \{$/,/^}$/' "$CUT"
    printf '%s\n' "$ln"
    printf 'echo DRV-ASSIGNED\n'
    printf '_sig_curl %s -s http://127.0.0.1:9/x || echo "DRV-REFUSED rc=$?"\n' "$var"
  } > "$out"
}
HF_RC=0
hf_run() { # <rowname> <driver> <mode: ok|empty|unset|nopy> [the HTTP status the recording curl answers with, default 200]
  local row="$ROWS/$1" drv="$2" mode="$3" pth="$BKBIN:$REALBIN:$PYDIR" status="${4:-200}"
  local -a wh=("WEBHOOK_SECRET=$HM_WH")
  [[ "$mode" == nopy ]] && pth="$BKBIN:$REALBIN"
  [[ "$mode" == empty ]] && wh=("WEBHOOK_SECRET=")
  [[ "$mode" == unset ]] && wh=()   # the variable is ABSENT from the environment (set -u), a third state next to empty and python3-absent
  assert_fixture_dir "$row"; mkdir -p "$row/shim" "$row/tmp"
  ( cd "$row" && env -i PATH="$pth" BK_SHIM="$row/shim" BK_TMP="$row/tmp" BK_HTTP_STATUS="$status" ${wh[@]+"${wh[@]}"} PAYLOAD='{"x":1}' CF_ACCESS_CLIENT_ID="$HM_CFID" CF_ACCESS_CLIENT_SECRET="$HM_CFSEC" \
      "$BASH_BIN" "$drv" < /dev/null > "$row/stdout" 2> "$row/stderr" )
  HF_RC=$?
}
hf_check() { # <rowname> <mode> -> HF_BAD (empty = held)
  local row="$ROWS/$1" mode="$2"
  HF_BAD=""
  [[ "$HF_RC" -eq 0 ]] || HF_BAD+=" rc=$HF_RC"
  [[ "$(bk_count "$row/stdout" DRV-ASSIGNED)" == 1 ]] || HF_BAD+=" aborted-at-the-assignment"
  if [[ "$mode" == ok ]]; then
    [[ "$(bk_calls "$row")" == 1 ]] || HF_BAD+=" calls=$(bk_calls "$row")"
    [[ "$(bk_count "$row/stderr" SOLEUR_CREDENTIAL_REFUSED)" == 0 ]] || HF_BAD+=" marker-on-success"
    [[ "$(bk_count "$row/stdout" DRV-REFUSED)" == 0 ]] || HF_BAD+=" refused"
  else
    [[ "$(bk_calls "$row")" == 0 ]] || HF_BAD+=" curl-called"
    [[ "$(bk_count "$row/stderr" "$SC_MARK")" == 1 ]] || HF_BAD+=" marker-count=$(bk_count "$row/stderr" "$SC_MARK")"
    [[ "$(bk_count "$row/stdout" 'DRV-REFUSED rc=2')" == 1 ]] || HF_BAD+=" not-refused-with-rc-2"
  fi
  [[ "$(bk_count "$row/stdout" "$HM_WH")$(bk_count "$row/stderr" "$HM_WH")$(bk_count "$row/stdout" "$HM_CFSEC")$(bk_count "$row/stderr" "$HM_CFSEC")" == 0000 ]] || HF_BAD+=" secret-in-output"
}
hf_n=0
for hf_i in $(seq 1 "$hm_last"); do hf_drv "$hf_i" "$BKDIR/hf-$hf_i.sh"; hf_n=$((hf_n + 1)); done
for hf_mode in ok empty unset nopy; do
  hf_bad=""
  for hf_i in $(seq 1 "$hm_last"); do
    hf_run "hf-$hf_mode-$hf_i" "$BKDIR/hf-$hf_i.sh" "$hf_mode"; hf_check "hf-$hf_mode-$hf_i" "$hf_mode"
    [[ -z "$HF_BAD" ]] || hf_bad+=" [copy $hf_i:$HF_BAD]"
  done
  [[ "$hf_n" -ge 1 && "$hf_n" == "$hm_last" ]] || hf_bad+=" [drivers=$hf_n of $hm_last]"
  case "$hf_mode" in
    ok)    hf_label="control: with a valid key and python3 present every one of the converted sites runs under set -euo pipefail, reaches its request (one recorded call) and prints no marker" ;;
    empty) hf_label="an EMPTY WEBHOOK_SECRET at every converted site does not abort the script at the assignment: the site's variable is left empty and _sig_curl refuses with rc 2, the marker once, zero requests, no secret in the output" ;;
    unset) hf_label="an UNSET WEBHOOK_SECRET (absent from the environment under set -u, not merely empty) at every converted site does not abort the script at the assignment: the site's variable is left empty and _sig_curl refuses with rc 2, the marker once, zero requests, no secret in the output" ;;
    nopy)  hf_label="a MISSING python3 at every converted site does not abort the script at the assignment: the site's variable is left empty and _sig_curl refuses with rc 2, the marker once, zero requests, no secret in the output" ;;
  esac
  if [[ -z "$hf_bad" ]]; then row "$hf_label" ok
  else row "$hf_label" fail "$hf_bad"; fi
done
# --- the same states with the arm's OWN error line, for every site whose arm is a single request followed by its own `if ... ::error:: ... fi` ----------
# The line driver above stops at the request, so for the sites past the first it never saw the arm's ::error::. This driver takes the site line AND the
# arm text after it VERBATIM up to the first column-4 `fi` (a poll or retry loop closes with `done` first and is skipped: its verdict sits after the loop,
# and the rows above plus the real-script rows cover those sites), for every site with that shape. The set is DERIVED from the real script, never hand-listed,
# and the status the arm expects on success is read from its own `!= "NNN"` test. A refused signature must end in the arm's `::error::` line naming HTTP 000
# and exit 1 with no bash error: a `CAUSE="$(tr ... < file)"` on a file that was never written ended the script under set -e BEFORE that line (sites 12 and 16).
text_mut() { # <text> <from> <to> -> TM_OUT (fatal unless <from> is present and the replacement changed exactly one line) and TM_LINE (that line, as it was)
  local text="$1" from="$2" to="$3" d
  [[ "$text" == *"$from"* ]] || fatal "text_mut: '${from:0:60}' is not in the text"
  TM_OUT="${text/"$from"/"$to"}"
  d="$(diff <(printf '%s\n' "$text") <(printf '%s\n' "$TM_OUT") || true)"
  [[ "$(grep -c '^< ' <<< "$d" || true)" == 1 && "$(grep -c '^> ' <<< "$d" || true)" == 1 ]] || fatal "text_mut: replacing '${from:0:60}' did not change exactly one line"
  TM_LINE="$(grep '^< ' <<< "$d")"; TM_LINE="${TM_LINE#< }"
}
hfa_drv() { # <idx> <out> -> prints the HTTP status the arm expects on success; prints nothing (and writes nothing) for a site without the single-shot shape
  local idx="$1" out="$2" n=0 i j blk want
  local -a L
  mapfile -t L < "$CUT"
  for i in "${!L[@]}"; do
    [[ "${L[i]}" == *'HMAC_KEY="$WEBHOOK_SECRET" python3'* ]] || continue
    n=$((n + 1)); [[ "$n" == "$idx" ]] || continue
    for ((j = i + 1; j < i + 21 && j < ${#L[@]}; j++)); do
      [[ "${L[j]}" == '    done' || "${L[j]}" == '    fi' ]] && break
    done
    [[ "${L[j]:-}" == '    fi' ]] || return 0
    blk="$(printf '%s\n' "${L[@]:i:j-i+1}")"
    [[ "$blk" == *'::error::'* && "$blk" == *'_sig_curl '* && "$blk" =~ \!=\ \"([0-9]{3})\" ]] || return 0
    want="${BASH_REMATCH[1]}"
    assert_fixture_dir "$out"
    {
      printf 'set -euo pipefail\nBASE=https://deploy.example.test/hooks\n'
      grep -m1 '^_bearer_ok() {' "$CUT"
      grep -m1 '^_body_head() {' "$CUT"   # the re-arm arm prints the first line of the host response through it (#9757 lead (g))
      awk '/^_sig_curl\(\) \{$/,/^}$/' "$CUT"
      printf '%s\n' "$blk" | sed 's|/tmp/|${BK_TMP}/|g'
      printf 'echo DRV-DONE\n'
    } > "$out"
    printf '%s' "$want"
    return 0
  done
  return 0
}
hfa_check() { # <rowname> <mode> -> HFA_BAD (empty = held)
  local row="$ROWS/$1" mode="$2"
  HFA_BAD=""
  if [[ "$mode" == ok ]]; then
    [[ "$HF_RC" -eq 0 ]] || HFA_BAD+=" rc=$HF_RC"
    [[ "$(bk_count "$row/stdout" DRV-DONE)" == 1 ]] || HFA_BAD+=" arm-did-not-complete"
    [[ "$(bk_calls "$row")" == 1 ]] || HFA_BAD+=" calls=$(bk_calls "$row")"
    [[ "$(bk_count "$row/stderr" SOLEUR_CREDENTIAL_REFUSED)" == 0 ]] || HFA_BAD+=" marker-on-success"
    [[ "$(bk_count "$row/stdout" '::error::')" == 0 ]] || HFA_BAD+=" error-line-on-success"
  else
    [[ "$HF_RC" -eq 1 ]] || HFA_BAD+=" rc=$HF_RC"
    [[ "$(bk_count "$row/stdout" DRV-DONE)" == 0 ]] || HFA_BAD+=" arm-continued"
    [[ "$(bk_calls "$row")" == 0 ]] || HFA_BAD+=" curl-called"
    [[ "$(bk_count "$row/stderr" "$SC_MARK")" == 1 ]] || HFA_BAD+=" marker-count=$(bk_count "$row/stderr" "$SC_MARK")"
    [[ "$(bk_count "$row/stdout" '::error::')" == 1 && "$(bk_count "$row/stdout" 'HTTP 000')" == 1 ]] || HFA_BAD+=" no-arm-error-line-naming-HTTP-000"
  fi
  # a bash diagnostic ("...: line N: ...") other than the CAUSE the mode itself creates (the unbound variable, the missing interpreter) is the script dying
  # inside the arm, which is what a `CAUSE="$(tr ... < file)"` on a never-written file did under set -e before the arm's own line could print
  case "$mode" in unset) cause='WEBHOOK_SECRET: unbound variable' ;; nopy) cause='python3: command not found' ;; *) cause='@@no-expected-diagnostic@@' ;; esac
  [[ "$(grep -F ': line ' "$row/stderr" | grep -cvF -- "$cause" || true)" == 0 ]] || HFA_BAD+=" bash-error"
  [[ "$(bk_count "$row/stdout" "$HM_WH")$(bk_count "$row/stderr" "$HM_WH")$(bk_count "$row/stdout" "$HM_CFSEC")$(bk_count "$row/stderr" "$HM_CFSEC")" == 0000 ]] || HFA_BAD+=" secret-in-output"
}
hfa_n=0; hfa_idx=(); hfa_want=()
for hf_i in $(seq 1 "$hm_last"); do
  hfa_st="$(hfa_drv "$hf_i" "$BKDIR/hfa-$hf_i.sh")"
  if [[ -n "$hfa_st" ]]; then hfa_n=$((hfa_n + 1)); hfa_idx+=("$hf_i"); hfa_want+=("$hfa_st"); fi
done
[[ "$hfa_n" -ge 9 ]] || fatal "arm-level HMAC drivers: only $hfa_n of $hm_last sites have the single-shot arm shape (nine did when this was written)"
for hf_mode in ok empty unset nopy; do
  hfa_bad=""
  for ((hf_k = 0; hf_k < hfa_n; hf_k++)); do
    hf_i="${hfa_idx[hf_k]}"
    hf_run "hfa-$hf_mode-$hf_i" "$BKDIR/hfa-$hf_i.sh" "$hf_mode" "${hfa_want[hf_k]}"; hfa_check "hfa-$hf_mode-$hf_i" "$hf_mode"
    [[ -z "$HFA_BAD" ]] || hfa_bad+=" [copy $hf_i:$HFA_BAD]"
  done
  case "$hf_mode" in
    ok)    hfa_label="control: with a valid key every single-request arm (site line plus its own status test, taken verbatim) completes: one recorded call, no marker, no ::error:: line" ;;
    empty) hfa_label="an EMPTY WEBHOOK_SECRET at every single-request arm ends in the arm's own ::error:: line naming HTTP 000 and exit 1: the marker once, zero requests, no bash error, no secret in the output" ;;
    unset) hfa_label="an UNSET WEBHOOK_SECRET (absent from the environment) at every single-request arm ends in the arm's own ::error:: line naming HTTP 000 and exit 1: the marker once, zero requests, no bash error, no secret in the output" ;;
    nopy)  hfa_label="a MISSING python3 at every single-request arm ends in the arm's own ::error:: line naming HTTP 000 and exit 1: the marker once, zero requests, no bash error, no secret in the output" ;;
  esac
  if [[ -z "$hfa_bad" ]]; then row "$hfa_label" ok
  else row "$hfa_label" fail "$hfa_bad"; fi
done
# the arm check's own clauses, each driven by a doctored copy of the first single-request driver (the first line that changes is the only change)
hfa_bad=""; hfa_k=0; hfa_txt="$(cat "$BKDIR/hfa-${hfa_idx[0]}.sh")"
while IFS='|' read -r hfa_name hfa_mode hfa_from hfa_to hfa_exp; do
  [[ -n "$hfa_name" ]] || continue
  text_mut "$hfa_txt" "$hfa_from" "$hfa_to"
  assert_fixture_dir "$BKDIR/hfa-mut-$hfa_name.sh"
  printf '%s\n' "$TM_OUT" > "$BKDIR/hfa-mut-$hfa_name.sh"
  hf_run "hfa-mut-$hfa_name" "$BKDIR/hfa-mut-$hfa_name.sh" "$hfa_mode" "${hfa_want[0]}"; hfa_check "hfa-mut-$hfa_name" "$hfa_mode"; hfa_k=$((hfa_k + 1))
  [[ "$HFA_BAD" == "$hfa_exp" ]] || hfa_bad+=" [$hfa_name: got '${HFA_BAD:-<none>}' want '$hfa_exp']"
done <<'HFA_MUTANTS'
request-skipped|ok|CODE=$(_sig_curl SIG|CODE=$(: SIG| rc=1 arm-did-not-complete calls=0 error-line-on-success
marker-on-success|ok|echo DRV-DONE|echo DRV-DONE; echo "SOLEUR_CREDENTIAL_REFUSED script=cutover-inngest reason=token_shape" >&2| marker-on-success
guard-permissive|empty|_bearer_ok() { local LC_ALL=C;|_bearer_ok() { return 0; local LC_ALL=C;| rc=0 arm-continued curl-called marker-count=0 no-arm-error-line-naming-HTTP-000
HFA_MUTANTS
[[ "$hfa_k" == 3 ]] || hfa_bad+=" [ran $hfa_k of 3 mutants]"
if [[ -z "$hfa_bad" ]]; then row "single-request arm check, clause by clause: a request that is never made, a marker printed on success and a signature guard that accepts an empty signature (the request goes out and the arm carries on) are each caught, and only by the clauses that name them" ok
else row "single-request arm check, clause by clause: a request that is never made, a marker printed on success and a signature guard that accepts an empty signature (the request goes out and the arm carries on) are each caught, and only by the clauses that name them" fail "$hfa_bad"; fi
# hfa_check's clauses, EACH driven to FAIL alone by a FABRICATED row (green except for exactly one doctored fact; the three real-driver mutants above reach
# only some of them: the bash-error, secret-in-output and HTTP-000 clauses were deletable with the battery green). A clause with several alternatives gets one
# variant per alternative (the two conjuncts of the arm's error line, the four secret/stream pairs, both allowed causes and a different diagnostic carrying the
# allowed cause's words). The un-doctored row of every mode must come out GREEN first, so a check that fails everything cannot satisfy a single variant.
hfac_mk() { # <variant> <mode: ok|empty|unset|nopy> -> HFAC_ROW (name under $ROWS) and HF_RC
  local v="$1" mode="$2" d="$ROWS/hfac-$1-$2"
  HFAC_ROW="hfac-$1-$2"; HF_RC=0
  assert_fixture_dir "$d"; mkdir -p "$d/shim/calls"
  : > "$d/stdout"; : > "$d/stderr"
  if [[ "$mode" == ok ]]; then
    printf 'DRV-DONE\n' > "$d/stdout"; printf 'curl\0' > "$d/shim/calls/1.argv"
  else
    HF_RC=1
    printf '::error::the deploy hook returned HTTP 000\n' > "$d/stdout"; printf '%s\n' "$SC_MARK" > "$d/stderr"
    case "$mode" in
      unset) printf 'x.sh: line 9: WEBHOOK_SECRET: unbound variable\n' >> "$d/stderr" ;;
      nopy)  printf 'x.sh: line 9: python3: command not found\n' >> "$d/stderr" ;;
    esac
  fi
  case "$v" in
    good) ;;
    rc)            if [[ "$mode" == ok ]]; then HF_RC=1; else HF_RC=0; fi ;;
    no-done)       : > "$d/stdout" ;;
    continued)     printf 'DRV-DONE\n' >> "$d/stdout" ;;
    no-call)       rm -f "$d/shim/calls/1.argv" ;;
    two-calls)     printf 'curl\0' > "$d/shim/calls/2.argv" ;;
    call)          printf 'curl\0' > "$d/shim/calls/1.argv" ;;
    marker)        printf 'SOLEUR_CREDENTIAL_REFUSED script=cutover-inngest reason=token_shape\n' >> "$d/stderr" ;;
    no-marker)     : > "$d/stderr" ;;
    two-markers)   printf '%s\n' "$SC_MARK" >> "$d/stderr" ;;
    error-line)    printf '::error::the deploy hook returned HTTP 000\n' >> "$d/stdout" ;;
    no-error)      printf 'the deploy hook returned HTTP 000\n' > "$d/stdout" ;;
    two-errors)    printf '::error::a second error line\n' >> "$d/stdout" ;;
    no-http000)    printf '::error::the deploy hook failed\n' > "$d/stdout" ;;
    two-http000)   printf 'HTTP 000 again\n' >> "$d/stdout" ;;
    bash-error)    printf 'x.sh: line 3: boom: command not found\n' >> "$d/stderr" ;;
    other-cause)   if [[ "$mode" == unset ]]; then printf 'x.sh: line 4: OTHER_VARIABLE: unbound variable\n' >> "$d/stderr"; else printf 'x.sh: line 4: openssl: command not found\n' >> "$d/stderr"; fi ;;
    out-wh)        printf 'leaked %s\n' "$HM_WH" >> "$d/stdout" ;;
    err-wh)        printf 'leaked %s\n' "$HM_WH" >> "$d/stderr" ;;
    out-cfsec)     printf 'leaked %s\n' "$HM_CFSEC" >> "$d/stdout" ;;
    err-cfsec)     printf 'leaked %s\n' "$HM_CFSEC" >> "$d/stderr" ;;
  esac
}
hfac_run() { # <spec...>: each "<variant>:<mode>:<expected HFA_BAD>" is built, judged by hfa_check and compared -> hfac_bad / hfac_k
  local spec v mode exp
  for spec in "$@"; do
    v="${spec%%:*}"; mode="${spec#*:}"; exp="${mode#*:}"; mode="${mode%%:*}"
    hfac_mk "$v" "$mode"; hfa_check "$HFAC_ROW" "$mode"; hfac_k=$((hfac_k + 1))
    [[ "$HFA_BAD" == "$exp" ]] || hfac_bad+=" [$v/$mode: got '${HFA_BAD:-<none>}' want '${exp:-<none>}']"
  done
}
hfac_bad=""; hfac_k=0
hfac_run 'good:ok:' 'rc:ok: rc=1' 'no-done:ok: arm-did-not-complete' 'no-call:ok: calls=0' 'two-calls:ok: calls=2' 'marker:ok: marker-on-success' 'error-line:ok: error-line-on-success' \
  'bash-error:ok: bash-error' 'other-cause:ok: bash-error'
hfac_run 'good:empty:' 'rc:empty: rc=0' 'continued:empty: arm-continued' 'call:empty: curl-called' 'no-marker:empty: marker-count=0' 'two-markers:empty: marker-count=2' \
  'no-error:empty: no-arm-error-line-naming-HTTP-000' 'two-errors:empty: no-arm-error-line-naming-HTTP-000' 'no-http000:empty: no-arm-error-line-naming-HTTP-000' \
  'two-http000:empty: no-arm-error-line-naming-HTTP-000'
hfac_run 'good:unset:' 'good:nopy:' 'bash-error:empty: bash-error' 'bash-error:unset: bash-error' 'bash-error:nopy: bash-error' 'other-cause:unset: bash-error' 'other-cause:nopy: bash-error' \
  'other-cause:empty: bash-error'
hfac_run 'out-wh:ok: secret-in-output' 'err-wh:ok: secret-in-output' 'out-cfsec:ok: secret-in-output' 'err-cfsec:ok: secret-in-output' \
  'out-wh:empty: secret-in-output' 'err-wh:unset: secret-in-output' 'out-cfsec:nopy: secret-in-output' 'err-cfsec:empty: secret-in-output'
hfac_label="arm check, every clause driven to FAIL alone by a fabricated row (control row green first): rc, arm completion, call count, marker on success, ::error:: on success; in the refusal modes rc, arm-continued, curl-called, the marker count (none and two), the arm's ::error:: line (absent, doubled) and its HTTP 000 (absent, doubled), a bash diagnostic in every mode, a different diagnostic that borrows the allowed cause's words, and the webhook secret and the Cloudflare Access secret on each stream"
[[ "$hfac_k" == 35 ]] || hfac_bad+=" [ran $hfac_k of 35 variants]"
if [[ -z "$hfac_bad" ]]; then row "$hfac_label" ok
else row "$hfac_label" fail "$hfac_bad"; fi
# ...and the real script, end to end, op=enumerate: the operator-facing result of the same two failures is the arm's own ::error:: line plus the marker
# (never the silent exit), with zero requests and a non-zero rc.
cs_arm_check() { # <rowname> -> cs_bad
  local row="$ROWS/$1"
  cs_bad=""
  [[ "$CS_RC" -ne 0 ]] || cs_bad+=" rc=$CS_RC"
  [[ "$(bk_calls "$row")" == 0 ]] || cs_bad+=" curl-called"
  [[ "$(bk_count "$row/stderr" "$SC_MARK")" == 1 ]] || cs_bad+=" marker-count=$(bk_count "$row/stderr" "$SC_MARK")"
  [[ "$(bk_count "$row/stdout" '::error::enumerate returned HTTP')" == 1 ]] || cs_bad+=" no-arm-error-line"
  [[ -z "$(cs_leaks "$1")" ]] || cs_bad+=" leak:$(cs_leaks "$1")"
}
cs_run cs-emptykey noauth "" "$BODIES/enum_array.json" WEBHOOK_SECRET=; cs_arm_check cs-emptykey
if [[ -z "$cs_bad" ]]; then row "canary sweep op=enumerate with an empty WEBHOOK_SECRET: non-zero rc, the arm's own ::error:: line, the marker once, zero requests, no canary in any output (not a silent abort)" ok
else row "canary sweep op=enumerate with an empty WEBHOOK_SECRET: non-zero rc, the arm's own ::error:: line, the marker once, zero requests, no canary in any output (not a silent abort)" fail "$cs_bad"; fi
CS_NOWH=1 cs_run cs-unsetkey noauth "" "$BODIES/enum_array.json"; cs_arm_check cs-unsetkey
if [[ -z "$cs_bad" ]]; then row "canary sweep op=enumerate with WEBHOOK_SECRET UNSET (absent from the environment, not merely empty): non-zero rc, the arm's own ::error:: line, the marker once, zero requests, no canary in any output (not a silent abort)" ok
else row "canary sweep op=enumerate with WEBHOOK_SECRET UNSET (absent from the environment, not merely empty): non-zero rc, the arm's own ::error:: line, the marker once, zero requests, no canary in any output (not a silent abort)" fail "$cs_bad"; fi
CS_PATH="$SHIMDIR:$REALBIN" cs_run cs-nopython noauth "" "$BODIES/enum_array.json"; cs_arm_check cs-nopython
if [[ -z "$cs_bad" ]]; then row "canary sweep op=enumerate with python3 absent from PATH: non-zero rc, the arm's own ::error:: line, the marker once, zero requests, no canary in any output (not a silent abort)" ok
else row "canary sweep op=enumerate with python3 absent from PATH: non-zero rc, the arm's own ::error:: line, the marker once, zero requests, no canary in any output (not a silent abort)" fail "$cs_bad"; fi
# --- behavioural: the operator-facing text of the two places a credential-shape refusal surfaces in the cutover script -----------------------
# (1) _bs_read_remedy's rc 2/64/78 arm used to describe only the destination pin / usage / trace and send the operator to "file an issue"; a
# rotation-class failure (a re-minted Better Stack credential holding a quote or backslash) is the same exit 2 and needs "re-mint it".
# (2) the rollback heartbeat lookup discards the wrapper's stderr, so an unusable BS_API shape was reported as "could not resolve the heartbeat
# id"; the shape is now checked first and the marker plus a value-free warning say the real cause (and the value is masked only after the check).
# Both are DRIVEN, not grepped: the function and the heartbeat block are extracted verbatim from the real script and run under its own
# `set -euo pipefail`, so a comment, a no-op or a redirect to the wrong stream cannot satisfy a row. Each clause of the text is then
# doctored ALONE in a copy of the extracted text (text_mut is fatal unless the edit landed and changed exactly one line).
br_fn="$(awk '/^_bs_read_remedy\(\) \{$/,/^}$/' "$CUT")"
[[ "$br_fn" == *'2|64|78)'* && "$br_fn" == *'bs_read_classify'* ]] || fatal "_bs_read_remedy was not extracted from $CUT"
br_run() { # <rowname> <rc> <function text> -> BR_RC and $ROWS/<rowname>/{stdout,stderr}
  local row="$ROWS/$1" rc="$2" fn="$3"
  assert_fixture_dir "$row"; mkdir -p "$row"
  printf "'SYNTHMARK0001x' rejected by betterstack-query.sh\n" > "$row/err"; : > "$row/rows"
  { printf 'set -euo pipefail\n%s\n' "$fn"; printf '_bs_read_remedy Q %s "%s" "%s" 3.7\n' "$rc" "$row/err" "$row/rows"; } > "$row/drv.sh"
  ( cd "$row" && env -i PATH="$REALBIN" "$BASH_BIN" "$row/drv.sh" < /dev/null > stdout 2> stderr )
  BR_RC=$?
}
br_check() { # <rowname> <rc> -> BR_BAD (space-separated failed clause names, empty = held)
  local row="$ROWS/$1" rc="$2" out arm
  BR_BAD=""; out="$row/stdout"
  [[ "$BR_RC" -eq 0 ]] || BR_BAD+=" rc=$BR_RC"
  [[ "$(wc -l < "$out" | tr -d ' ')" == 2 ]] || BR_BAD+=" stdout-lines"
  arm="$(head -n1 "$out")"
  [[ "$arm" == "::error::3.7 Q read: betterstack-query.sh refused (rc=$rc:"* ]] || BR_BAD+=" arm-line"
  [[ "$arm" == *'credential shape'* ]] || BR_BAD+=" credential-shape"
  [[ "$arm" == *SOLEUR_CREDENTIAL_REFUSED* ]] || BR_BAD+=" marker-name"
  [[ "$arm" == *'re-mint'* ]] || BR_BAD+=" remint"
  [[ "$arm" == *BETTERSTACK_QUERY_USERNAME* ]] || BR_BAD+=" names-username"
  [[ "$arm" == *BETTERSTACK_QUERY_PASSWORD* ]] || BR_BAD+=" names-password"
  [[ "$arm" == *"stderr: '<redacted>'"* ]] || BR_BAD+=" stderr-redaction"
  [[ "$(tail -n1 "$out")" == *'NOTHING about the dedicated host was measured'* ]] || BR_BAD+=" closing-line"
  [[ ! -s "$row/stderr" ]] || BR_BAD+=" text-on-stderr"
  [[ "$(bk_count "$out" SYNTHMARK0001)" == 0 ]] || BR_BAD+=" value-in-output"
  [[ "$(bk_count "$out" unclassified)" == 0 ]] || BR_BAD+=" unclassified"
}
br_bad=""
for br_rc in 2 64 78; do
  br_run "br-rc$br_rc" "$br_rc" "$br_fn"; br_check "br-rc$br_rc" "$br_rc"
  [[ -z "$BR_BAD" ]] || br_bad+=" [rc $br_rc:$BR_BAD]"
done
if [[ -z "$br_bad" ]]; then row "cutover _bs_read_remedy driven with rc 2, 64 and 78: its own ::error:: arm line (stdout, nothing on stderr) names the credential-shape refusal, the SOLEUR_CREDENTIAL_REFUSED marker, both credential variables and the re-mint remedy, the quoted stderr value is redacted, and the closing 'nothing was measured' line follows" ok
else row "cutover _bs_read_remedy driven with rc 2, 64 and 78: its own ::error:: arm line (stdout, nothing on stderr) names the credential-shape refusal, the SOLEUR_CREDENTIAL_REFUSED marker, both credential variables and the re-mint remedy, the quoted stderr value is redacted, and the closing 'nothing was measured' line follows" fail "$br_bad"; fi
# control: the driver reaches DIFFERENT arms for other codes (a driver that printed one fixed text for every rc would satisfy the row above)
br_bad=""
for br_rc in 3 1 99; do
  br_run "br-ctl$br_rc" "$br_rc" "$br_fn"
  br_arm="$(head -n1 "$ROWS/br-ctl$br_rc/stdout")"
  [[ "$BR_RC" -eq 0 && "$br_arm" != *'credential shape'* && "$br_arm" != *SOLEUR_CREDENTIAL_REFUSED* ]] || br_bad+=" [rc $br_rc printed the credential-shape arm]"
done
[[ "$(head -n1 "$ROWS/br-ctl3/stdout")" == *'not injected'* ]] || br_bad+=" [rc 3 lost its credentials-absent arm]"
[[ "$(head -n1 "$ROWS/br-ctl1/stdout")" == *'doppler run or the reader exited 1'* ]] || br_bad+=" [rc 1 lost its doppler arm]"
[[ "$(head -n1 "$ROWS/br-ctl99/stdout")" == *'(unclassified)'* ]] || br_bad+=" [rc 99 lost its unclassified arm]"
if [[ -z "$br_bad" ]]; then row "cutover _bs_read_remedy control: rc 3, rc 1 and an unknown rc each print their own arm and none of them the credential-shape text or the marker name" ok
else row "cutover _bs_read_remedy control: rc 3, rc 1 and an unknown rc each print their own arm and none of them the credential-shape text or the marker name" fail "$br_bad"; fi
# each clause of the arm doctored ALONE (the arm line is the only line that changes; the doctored clause is the only one that goes red)
br_bad=""; br_n=0
while IFS='~' read -r br_name br_from br_to br_want; do
  [[ -n "$br_name" ]] || continue
  text_mut "$br_fn" "$br_from" "$br_to"; [[ "$TM_LINE" == *'2|64|78)'* || "$TM_LINE" == *'read failed'* || "$TM_LINE" == *'err1='* ]] || fatal "br mutant $br_name changed a line outside the rc 2/64/78 arm, the closing line and the stderr scrub"
  br_run "br-mut-$br_name" 2 "$TM_OUT"; br_check "br-mut-$br_name" 2; br_n=$((br_n + 1))
  [[ "$BR_BAD" == "$br_want" ]] || br_bad+=" [$br_name: got '${BR_BAD:-<none>}' want '$br_want']"
done <<'BR_MUTANTS'
no-op-arm~2|64|78) echo "::error::~2|64|78) : "::error::~ stdout-lines arm-line credential-shape marker-name remint names-username names-password stderr-redaction
to-stderr~2|64|78) echo "::error::~2|64|78) echo >&2 "::error::~ stdout-lines arm-line credential-shape marker-name remint names-username names-password stderr-redaction text-on-stderr
credential-shape~credential shape~credential form~ credential-shape
marker-name~(marker SOLEUR_CREDENTIAL_REFUSED)~(marker SOLEUR_REFUSED)~ marker-name
remint~re-mint that credential~replace that credential~ remint
names-username~names BETTERSTACK_QUERY_USERNAME or~names the username or~ names-username
names-password~or BETTERSTACK_QUERY_PASSWORD (marker~or the password (marker~ names-password
aborts~2|64|78) echo "::error::~2|64|78) return 3; echo "::error::~ rc=3 stdout-lines arm-line credential-shape marker-name remint names-username names-password stderr-redaction closing-line
closing-line~NOTHING about the dedicated host was measured~something was measured~ closing-line
no-redaction~s/'[^']*'/'<redacted>'/g; ~~ stderr-redaction value-in-output
says-unclassified~re-mint that credential~unclassified that credential~ remint unclassified
BR_MUTANTS
[[ "$br_n" == 11 ]] || br_bad+=" [ran $br_n of 11 mutants]"
if [[ -z "$br_bad" ]]; then row "cutover _bs_read_remedy mutants: a no-op arm, an arm that writes to stderr, an arm that aborts, a lost closing line, a lost redaction, an arm that says 'unclassified', and the credential-shape, marker-name, re-mint, username and password clauses each removed are caught, and only by the clauses that name them" ok
else row "cutover _bs_read_remedy mutants: a no-op arm, an arm that writes to stderr, an arm that aborts, a lost closing line, a lost redaction, an arm that says 'unclassified', and the credential-shape, marker-name, re-mint, username and password clauses each removed are caught, and only by the clauses that name them" fail "$br_bad"; fi

# the rollback heartbeat resolution: the block from the Doppler read to the end of its if/elif/else, extracted verbatim and run with the script's
# own _bearer_ok/_bearer_curl, the recording curl and a doppler that returns the token under test.
hb_txt="$(awk '/^    BS_API=\$\(doppler secrets get BETTERSTACK_API_TOKEN/{f=1} /^    # ---- Half \(B\)/{f=0} f' "$CUT")"
[[ "$hb_txt" == *'_bearer_curl BS_API'* && "$hb_txt" == *'HB_ID'* && "$hb_txt" == *'elif ! _bearer_ok "$BS_API"; then'* ]] || fatal "the rollback heartbeat block was not extracted from $CUT"
HB_TOK="bstoken-$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')"
HB_MARK='SOLEUR_CREDENTIAL_REFUSED script=cutover-inngest reason=token_shape'
HB_RC=0
hb_run() { # <rowname> <block text> <token> [permissive: 1 replaces _bearer_ok with one that accepts everything, so a mutant can reach the request] -> HB_RC and $ROWS/<rowname>/{stdout,stderr,shim/}
  local row="$ROWS/$1"
  assert_fixture_dir "$row"; mkdir -p "$row/shim"
  { printf 'set -euo pipefail\n'; grep -m1 '^_bearer_ok() {' "$CUT"; awk '/^_bearer_curl\(\) \{$/,/^}$/' "$CUT"; [[ "${4:-}" == 1 ]] && printf '_bearer_ok() { return 0; }\n'; printf '%s\n' "$2"; printf 'echo DRV-AFTER\n'; } > "$row/drv.sh"
  ( cd "$row" && env -i PATH="$BKBIN:$REALBIN" BK_SHIM="$row/shim" BK_TOKEN="$3" "$BASH_BIN" "$row/drv.sh" < /dev/null > stdout 2> stderr )
  HB_RC=$?
}
hb_check() { # <rowname> <mode: ok|empty|bad> <token> -> HB_BAD (space-separated failed clause names, empty = held)
  local row="$ROWS/$1" mode="$2" tok="$3" o e f n_mask
  HB_BAD=""; o="$row/stdout"; e="$row/stderr"
  [[ "$HB_RC" -eq 0 ]] || HB_BAD+=" rc=$HB_RC"
  [[ "$(bk_count "$o" DRV-AFTER)" == 1 ]] || HB_BAD+=" arm-did-not-finish"
  n_mask="$(grep -c '^::add-mask::' "$o" || true)"
  case "$mode" in
    ok)
      [[ "$n_mask" == 1 && "$(grep -cxF -- "::add-mask::$tok" "$o" || true)" == 1 ]] || HB_BAD+=" mask-line"
      [[ "$(bk_calls "$row")" == 1 ]] || HB_BAD+=" calls=$(bk_calls "$row")"
      [[ "$(grep -cxF -- "header = \"Authorization: Bearer $tok\"" "$row/shim/calls/1.stdin" 2>/dev/null || true)" == 1 ]] || HB_BAD+=" token-not-on-stdin"
      for f in "$row"/shim/calls/*.argv; do [[ -e "$f" ]] && grep -aqF -- "$tok" "$f" && HB_BAD+=" token-in-argv"; done
      [[ "$(bk_count "$e" "$HB_MARK")$(bk_count "$o" "$HB_MARK")" == 00 ]] || HB_BAD+=" marker-on-success"
      [[ "$(bk_count "$o" 'has an unusable shape')" == 0 ]] || HB_BAD+=" shape-warning-on-success" ;;
    empty)
      [[ "$n_mask" == 0 ]] || HB_BAD+=" mask-line"
      [[ "$(bk_calls "$row")" == 0 ]] || HB_BAD+=" curl-called"
      [[ "$(bk_count "$e" "$HB_MARK")$(bk_count "$o" "$HB_MARK")" == 00 ]] || HB_BAD+=" marker-on-empty"
      [[ "$(bk_count "$o" 'BETTERSTACK_API_TOKEN unreadable from prd_terraform')" == 1 ]] || HB_BAD+=" unreadable-warning"
      [[ "$(bk_count "$o" 'has an unusable shape')" == 0 ]] || HB_BAD+=" shape-warning-on-empty" ;;
    bad)
      [[ "$n_mask" == 0 ]] || HB_BAD+=" mask-before-shape-check"
      [[ "$(bk_calls "$row")" == 0 ]] || HB_BAD+=" curl-called"
      [[ "$(bk_count "$e" "$HB_MARK")" == 1 ]] || HB_BAD+=" marker-on-stderr"
      [[ "$(bk_count "$o" "$HB_MARK")" == 0 ]] || HB_BAD+=" marker-on-stdout"
      [[ "$(bk_count "$o" '::warning::op=rollback: BETTERSTACK_API_TOKEN read from prd_terraform has an unusable shape')" == 1 ]] || HB_BAD+=" shape-warning"
      [[ "$(bk_count "$e" '::warning::')" == 0 ]] || HB_BAD+=" warning-on-stderr"
      [[ "$(bk_count "$o" 'could not resolve')" == 0 ]] || HB_BAD+=" generic-lookup-warning"
      [[ "$(bk_count "$o" 'unreadable')" == 0 ]] || HB_BAD+=" unreadable-warning"
      [[ "$(bk_count "$o" SYNTHMARK0001)$(bk_count "$e" SYNTHMARK0001)" == 00 ]] || HB_BAD+=" value-in-output" ;;
  esac
}
hb_run hb-ok "$hb_txt" "$HB_TOK"; hb_check hb-ok ok "$HB_TOK"
if [[ -z "$HB_BAD" ]]; then row "cutover rollback heartbeat driven with a well-formed token (control): the value is masked once with exactly '::add-mask::<token>', the lookup is one request carrying the bearer on stdin only, no marker, no shape warning" ok
else row "cutover rollback heartbeat driven with a well-formed token (control): the value is masked once with exactly '::add-mask::<token>', the lookup is one request carrying the bearer on stdin only, no marker, no shape warning" fail "$HB_BAD"; fi
hb_run hb-empty "$hb_txt" ""; hb_check hb-empty empty ""
if [[ -z "$HB_BAD" ]]; then row "cutover rollback heartbeat driven with an unreadable (empty) token: the 'unreadable from prd_terraform' warning on stdout, no mask line, no marker, zero requests, the block ends normally" ok
else row "cutover rollback heartbeat driven with an unreadable (empty) token: the 'unreadable from prd_terraform' warning on stdout, no mask line, no marker, zero requests, the block ends normally" fail "$HB_BAD"; fi
hb_bad=""; hb_n=0
for hb_cls in $TOK_CLASSES; do
  hb_run "hb-bad-$hb_cls" "$hb_txt" "$(tok_for "$hb_cls")"; hb_check "hb-bad-$hb_cls" bad ""; hb_n=$((hb_n + 1))
  [[ -z "$HB_BAD" ]] || hb_bad+=" [$hb_cls:$HB_BAD]"
done
[[ "$hb_n" -eq "$(wc -w <<< "$TOK_CLASSES")" && "$hb_n" -ge 8 ]] || hb_bad+=" [ran $hb_n classes]"
if [[ -z "$hb_bad" ]]; then row "cutover rollback heartbeat driven with an unusable token of every hostile class (quote+newline+url, newline, non-ASCII, quote, space, backslash, tab, CR): the marker once on STDERR (not stdout), the value-free 'unusable shape' ::warning:: once on STDOUT (not stderr), no mask line (the shape is checked BEFORE the value reaches ::add-mask::), zero requests, no 'could not resolve' message, the value in no output, the block ends normally" ok
else row "cutover rollback heartbeat driven with an unusable token of every hostile class (quote+newline+url, newline, non-ASCII, quote, space, backslash, tab, CR): the marker once on STDERR (not stdout), the value-free 'unusable shape' ::warning:: once on STDOUT (not stderr), no mask line (the shape is checked BEFORE the value reaches ::add-mask::), zero requests, no 'could not resolve' message, the value in no output, the block ends normally" fail "$hb_bad"; fi
# each clause of the block doctored ALONE: mode, token, expected failed clauses
hb_bad=""; hb_n=0
while IFS='|' read -r hb_name hb_mode hb_tokcls hb_from hb_to hb_want hb_perm; do
  [[ -n "$hb_name" ]] || continue
  if [[ -n "$hb_from" ]]; then text_mut "$hb_txt" "$hb_from" "$hb_to"; else TM_OUT="$hb_txt"; fi   # an empty edit = the permissive guard alone
  case "$hb_mode" in ok) hb_tok="$HB_TOK" ;; empty) hb_tok="" ;; *) hb_tok="$(tok_for "$hb_tokcls")" ;; esac
  hb_run "hb-mut-$hb_name" "$TM_OUT" "$hb_tok" "$hb_perm"; hb_check "hb-mut-$hb_name" "$hb_mode" "$hb_tok"; hb_n=$((hb_n + 1))
  [[ "$HB_BAD" == "$hb_want" ]] || hb_bad+=" [$hb_name: got '${HB_BAD:-<none>}' want '$hb_want']"
done <<'HB_MUTANTS'
marker-commented-out|bad|quote|      echo "SOLEUR_CREDENTIAL_REFUSED script=cutover-inngest reason=token_shape" >&2|      : "SOLEUR_CREDENTIAL_REFUSED script=cutover-inngest reason=token_shape" >&2| marker-on-stderr
marker-to-stdout|bad|quote|reason=token_shape" >&2|reason=token_shape"| marker-on-stderr marker-on-stdout
warning-no-op|bad|quote|      echo "::warning::op=rollback: BETTERSTACK_API_TOKEN read from prd_terraform has an unusable shape|      : "::warning::op=rollback: BETTERSTACK_API_TOKEN read from prd_terraform has an unusable shape| shape-warning
warning-to-stderr|bad|quote|echo "::warning::op=rollback: BETTERSTACK_API_TOKEN read from prd_terraform has an unusable shape|echo >&2 "::warning::op=rollback: BETTERSTACK_API_TOKEN read from prd_terraform has an unusable shape| shape-warning warning-on-stderr
mask-before-shape-check|bad|newline-only|_bearer_ok "$BS_API" && [[ -n "$BS_API" ]] && printf|[[ -n "$BS_API" ]] && printf| mask-before-shape-check value-in-output
shape-arm-removed|bad|quote|elif ! _bearer_ok "$BS_API"; then|elif false; then| marker-on-stderr shape-warning generic-lookup-warning
mask-dropped|ok||printf '::add-mask::%s\n' "$BS_API"|: '::add-mask::%s\n' "$BS_API"| mask-line
unreadable-warning-no-op|empty||    echo "::warning::op=rollback: BETTERSTACK_API_TOKEN unreadable from prd_terraform|    : "::warning::op=rollback: BETTERSTACK_API_TOKEN unreadable from prd_terraform| unreadable-warning
aborts-exit3|bad|quote|elif ! _bearer_ok "$BS_API"; then|elif ! _bearer_ok "$BS_API"; then exit 3| rc=3 arm-did-not-finish marker-on-stderr shape-warning
aborts-exit0|bad|quote|elif ! _bearer_ok "$BS_API"; then|elif ! _bearer_ok "$BS_API"; then exit 0| arm-did-not-finish marker-on-stderr shape-warning
lookup-dropped|ok||HB_ID=$(_bearer_curl BS_API -fsS|HB_ID=$(: BS_API -fsS| calls=0 token-not-on-stdin
token-in-argv|ok||HB_ID=$(_bearer_curl BS_API -fsS --max-time 20 \|HB_ID=$(curl --disable -fsS -H "Authorization: Bearer $BS_API" --max-time 20 \| token-not-on-stdin token-in-argv
shape-test-inverted|ok||elif ! _bearer_ok "$BS_API"; then|elif _bearer_ok "$BS_API"; then| calls=0 token-not-on-stdin marker-on-success shape-warning-on-success
bare-mask-on-empty|empty||_bearer_ok "$BS_API" && [[ -n "$BS_API" ]] && printf|printf| mask-line
empty-arm-removed|empty||if [[ -z "$BS_API" ]]; then|if false; then| marker-on-empty unreadable-warning shape-warning-on-empty
empty-reaches-request|empty||if [[ -z "$BS_API" ]]; then|if false; then| curl-called unreadable-warning|1
bad-reaches-request|bad|quote||| mask-before-shape-check curl-called marker-on-stderr shape-warning generic-lookup-warning value-in-output|1
unreadable-in-shape-arm|bad|quote|has an unusable shape|has an unreadable shape| shape-warning unreadable-warning
HB_MUTANTS
[[ "$hb_n" == 18 ]] || hb_bad+=" [ran $hb_n of 18 mutants]"
if [[ -z "$hb_bad" ]]; then row "cutover rollback heartbeat mutants: the marker commented out or sent to stdout, the shape warning no-op'd or sent to stderr, the mask moved back before the shape check, the shape arm removed or inverted, the mask dropped, the unreadable warning no-op'd, an arm that exits, a lookup that is dropped or puts the token in argv, an empty or unusable token that reaches the request, and a shape arm that says 'unreadable' are each caught, and only by the clauses that name them" ok
else row "cutover rollback heartbeat mutants: the marker commented out or sent to stdout, the shape warning no-op'd or sent to stderr, the mask moved back before the shape check, the shape arm removed or inverted, the mask dropped, the unreadable warning no-op'd, an arm that exits, a lookup that is dropped or puts the token in argv, an empty or unusable token that reaches the request, and a shape arm that says 'unreadable' are each caught, and only by the clauses that name them" fail "$hb_bad"; fi
# =====================================================================================
# #9757 review leads (a) and (g) of scripts/cutover-inngest.sh (lead (b), the five op=arm mask sites, was retired with op=arm by #9927), each driven through a recording curl / doppler and the script's own text:
#   (a1) _inngest_server_created_epoch judges its token with _bearer_ok BEFORE it masks it or feeds it to `-H @-`: a refusal takes the empty-token arm's verdict
#        class (one ::warning::, `__UNREADABLE__`, rc 0), prints the marker on stderr, and makes zero requests;
#   (a2) the op=verify zero-run discovery call judges $SIG and both Cloudflare Access values before its own `--config -`;
#   (g)  the four response-body echoes print a bounded (160), scrubbed (printable ASCII) FIRST line, mid-line in the arm's own ::error:: text, never the raw body.
# The text under test is EXTRACTED from the real script; mutants doctor exactly one clause (text_mut refuses a replacement that changes more than one line).
# =====================================================================================
LD_REAL="$TMPD/ldreal"
assert_fixture_dir "$LD_REAL"; mkdir -p "$LD_REAL"
for t in bash cat grep sed tr awk head cut sha256sum jq mktemp rm mkdir env wc sort true false printf; do
  p="$(type -P "$t" || true)"; [[ -n "$p" ]] && ln -s "$p" "$LD_REAL/$t"
done
LD_MARK='SOLEUR_CREDENTIAL_REFUSED script=cutover-inngest reason=token_shape'
LD_RC=0; LD_BAD=""
ld_caught() { # <bad clauses string> <must-name clause> -> rc 0 when the mutant was caught AND the named clause is among the failures
  [[ -n "$1" && " $1 " == *" $2"* ]]
}

# ---- (a1) _inngest_server_created_epoch ------------------------------------------------------------------------
ie_fn="$(awk '/^_inngest_server_created_epoch\(\) \{$/,/^\}$/' "$CUT")"
[[ "$ie_fn" == *'if ! _bearer_ok "$tok"; then'* && "$ie_fn" == *'-H @-'* && "$ie_fn" == *"add-mask"* ]] || fatal "lead (a1): the token read of _inngest_server_created_epoch was not extracted from $CUT"
ie_run() { # <row> <function text> <token>: combined stdout+stderr in $ROWS/<row>/out (stderr keeps its order against the recording curl's SHIMCALL line)
  local row="$ROWS/$1"
  assert_fixture_dir "$row"; mkdir -p "$row/shim"
  { printf 'set -euo pipefail\n'; grep -m1 '^_bearer_ok() {' "$CUT"; awk '/^_hcloud_created_epoch\(\) \{$/,/^\}$/' "$CUT"; printf '%s\n' "$2"
    printf 'INNGEST_HOST=soleur-inngest\nDRV_OUT="$(_inngest_server_created_epoch)"\necho "DRV-OUT=$DRV_OUT"\necho DRV-AFTER\n'; } > "$row/drv.sh"
  ( cd "$row" && env -i PATH="$BKBIN:$REALBIN" BK_SHIM="$row/shim" BK_TOKEN="$3" "$BASH_BIN" "$row/drv.sh" < /dev/null > "$row/out" 2>&1 )
  LD_RC=$?
}
ie_check() { # <row> <mode: ok|bad|empty> <token>
  local row="$ROWS/$1" mode="$2" tok="$3" f m c
  LD_BAD=""; local o="$row/out"
  [[ "$LD_RC" -eq 0 ]] || LD_BAD+=" rc=$LD_RC"
  [[ "$(bk_count "$o" DRV-AFTER)" == 1 ]] || LD_BAD+=" did-not-finish"
  case "$mode" in
    ok)
      [[ "$(grep -cxF -- "::add-mask::$tok" "$o" || true)" == 1 ]] || LD_BAD+=" mask-line"
      [[ "$(head -n1 "$o")" == "::add-mask::$tok" ]] || LD_BAD+=" mask-not-first"   # the curl's own stderr is discarded by the function, so the order against the request is the code order: the mask is the FIRST output line
      [[ "$(bk_calls "$row")" == 1 ]] || LD_BAD+=" calls=$(bk_calls "$row")"
      [[ "$(grep -cxF -- "Authorization: Bearer $tok" "$row/shim/calls/1.stdin" 2>/dev/null || true)" == 1 ]] || LD_BAD+=" token-not-on-stdin"
      for f in "$row"/shim/calls/*.argv; do [[ -e "$f" ]] && grep -aqF -- "$tok" "$f" && LD_BAD+=" token-in-argv"; done
      [[ "$(bk_count "$o" "$tok")" == 1 ]] || LD_BAD+=" token-printed-beyond-the-mask"
      [[ "$(bk_count "$o" "$LD_MARK")" == 0 ]] || LD_BAD+=" marker-on-success" ;;
    bad)
      [[ "$(bk_count "$o" '::add-mask::')" == 0 ]] || LD_BAD+=" mask-line"
      [[ "$(bk_calls "$row")" == 0 ]] || LD_BAD+=" calls=$(bk_calls "$row")"
      [[ "$(bk_count "$o" "$LD_MARK")" == 1 ]] || LD_BAD+=" marker-count=$(bk_count "$o" "$LD_MARK")"
      [[ "$(bk_count "$o" '::warning::G3 generation anchor: the HCLOUD_TOKEN_READONLY read from prd_terraform has an unusable shape')" == 1 ]] || LD_BAD+=" shape-warning"
      [[ "$(grep -cxF 'DRV-OUT=__UNREADABLE__' "$o" || true)" == 1 ]] || LD_BAD+=" verdict-class"
      [[ "$(bk_count "$o" SYNTHMARK0001)$(bk_count "$o" SYNTHMARK0002)" == 00 ]] || LD_BAD+=" value-in-output" ;;
    empty)
      [[ "$(bk_count "$o" '::add-mask::')" == 0 ]] || LD_BAD+=" mask-line"
      [[ "$(bk_calls "$row")" == 0 ]] || LD_BAD+=" calls=$(bk_calls "$row")"
      [[ "$(bk_count "$o" "$LD_MARK")" == 0 ]] || LD_BAD+=" marker-on-empty"
      [[ "$(bk_count "$o" 'doppler returned nothing for HCLOUD_TOKEN_READONLY in prd_terraform')" == 1 ]] || LD_BAD+=" empty-warning"
      [[ "$(grep -cxF 'DRV-OUT=__UNREADABLE__' "$o" || true)" == 1 ]] || LD_BAD+=" verdict-class" ;;
  esac
}
LD_TOK="hztoken-$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')"
ie_run ie-ok "$ie_fn" "$LD_TOK"; ie_check ie-ok ok "$LD_TOK"
if [[ -z "$LD_BAD" ]]; then row "lead (a1) _inngest_server_created_epoch driven with a well-formed token (control): masked once as the first output line, one request, the bearer on the -H @- stdin only, no marker" ok
else row "lead (a1) _inngest_server_created_epoch driven with a well-formed token (control): masked once as the first output line, one request, the bearer on the -H @- stdin only, no marker" fail "$LD_BAD"; fi
ie_run ie-empty "$ie_fn" ""; ie_check ie-empty empty ""
if [[ -z "$LD_BAD" ]]; then row "lead (a1) _inngest_server_created_epoch driven with an empty token: the existing 'doppler returned nothing' warning, no mask, no marker, zero requests, __UNREADABLE__" ok
else row "lead (a1) _inngest_server_created_epoch driven with an empty token: the existing 'doppler returned nothing' warning, no mask, no marker, zero requests, __UNREADABLE__" fail "$LD_BAD"; fi
ld_bad=""; ld_n=0
for ld_cls in $TOK_CLASSES; do
  ie_run "ie-bad-$ld_cls" "$ie_fn" "$(tok_for "$ld_cls")"; ie_check "ie-bad-$ld_cls" bad ""; ld_n=$((ld_n + 1))
  [[ -z "$LD_BAD" ]] || ld_bad+=" [$ld_cls:$LD_BAD]"
done
[[ "$ld_n" -ge 8 ]] || ld_bad+=" [ran $ld_n classes]"
if [[ -z "$ld_bad" ]]; then row "lead (a1) _inngest_server_created_epoch driven with an unusable token of every hostile class: the marker once on stderr, one value-free 'unusable shape' warning, __UNREADABLE__ with rc 0 (the empty-token verdict class), no mask line, ZERO requests" ok
else row "lead (a1) _inngest_server_created_epoch driven with an unusable token of every hostile class: the marker once on stderr, one value-free 'unusable shape' warning, __UNREADABLE__ with rc 0 (the empty-token verdict class), no mask line, ZERO requests" fail "$ld_bad"; fi
ld_bad=""; ld_n=0
while IFS='|' read -r ld_name ld_mode ld_cls ld_from ld_to ld_must; do
  [[ -n "$ld_name" ]] || continue
  text_mut "$ie_fn" "$ld_from" "$ld_to"
  if [[ "$ld_mode" == ok ]]; then ld_tok="$LD_TOK"; else ld_tok="$(tok_for "$ld_cls")"; fi
  ie_run "ie-mut-$ld_name" "$TM_OUT" "$ld_tok"; if [[ "$ld_mode" == ok ]]; then ie_check "ie-mut-$ld_name" ok "$ld_tok"; else ie_check "ie-mut-$ld_name" bad ""; fi
  ld_n=$((ld_n + 1)); ld_caught "$LD_BAD" "$ld_must" || ld_bad+=" [$ld_name: got '${LD_BAD:-<none>}' wanted a failure naming '$ld_must']"
done <<'IE_MUTANTS'
check-removed|bad|quote-newline-url|  if ! _bearer_ok "$tok"; then|  if false; then|mask-line
marker-dropped|bad|quote|    echo "SOLEUR_CREDENTIAL_REFUSED script=cutover-inngest reason=token_shape" >&2|    : "SOLEUR_CREDENTIAL_REFUSED script=cutover-inngest reason=token_shape" >&2|marker-count
warning-dropped|bad|quote|    echo "::warning::G3 generation anchor: the HCLOUD_TOKEN_READONLY read|    : "::warning::G3 generation anchor: the HCLOUD_TOKEN_READONLY read|shape-warning
check-inverted|ok||  if ! _bearer_ok "$tok"; then|  if _bearer_ok "$tok"; then|calls=0
mask-dropped|ok||  printf '::add-mask::%s\n' "$tok" >&2|  : '::add-mask::%s\n' "$tok" >&2|mask-line
IE_MUTANTS
[[ "$ld_n" == 5 ]] || ld_bad+=" [ran $ld_n of 5 mutants]"
if [[ -z "$ld_bad" ]]; then row "lead (a1) mutants: the shape check removed or inverted, the marker or the warning dropped, the mask dropped are each caught by the clause that names them" ok
else row "lead (a1) mutants: the shape check removed or inverted, the marker or the warning dropped, the mask dropped are each caught by the clause that names them" fail "$ld_bad"; fi

# ---- (a2) the op=verify zero-run discovery call -----------------------------------------------------------------
dc_txt="$(awk '/^            # All three values are judged BEFORE the config is built/{f=1} f{print} f&&/^            DISC_BODY=/{exit}' "$CUT" | sed 's|/tmp/verify-zero-run|${BK_TMP}/verify-zero-run|g')"
[[ "$dc_txt" == *'if _bearer_ok "$SIG" && _bearer_ok "$CF_ACCESS_CLIENT_ID" && _bearer_ok "$CF_ACCESS_CLIENT_SECRET"; then'* && "$dc_txt" == *'--config -'* ]] || fatal "lead (a2): the discovery call was not extracted from $CUT"
dc_run() { # <row> <block text> <SIG> <CF id> <CF secret>
  local row="$ROWS/$1"
  assert_fixture_dir "$row"; mkdir -p "$row/shim" "$row/tmp"
  { printf 'set -euo pipefail\n'; grep -m1 '^_bearer_ok() {' "$CUT"
    printf 'DISC_URL="https://deploy.example.test/hooks/inngest-doublefire-probe?from=x"\n'; printf '%s\n' "$2"; printf 'echo "DRV-CODE=$DISC_CODE"\n'; } > "$row/drv.sh"
  ( cd "$row" && env -i PATH="$BKBIN:$REALBIN" BK_SHIM="$row/shim" BK_TMP="$row/tmp" SIG="$3" CF_ACCESS_CLIENT_ID="$4" CF_ACCESS_CLIENT_SECRET="$5" "$BASH_BIN" "$row/drv.sh" < /dev/null > "$row/stdout" 2> "$row/stderr" )
  LD_RC=$?
}
dc_check() { # <row> <mode: ok|bad> <SIG> <CF id> <CF secret>
  local row="$ROWS/$1" mode="$2" v f; LD_BAD=""
  [[ "$LD_RC" -eq 0 ]] || LD_BAD+=" rc=$LD_RC"
  if [[ "$mode" == ok ]]; then
    [[ "$(bk_calls "$row")" == 1 ]] || LD_BAD+=" calls=$(bk_calls "$row")"
    [[ "$(grep -cxF -- "header = \"X-Signature-256: sha256=$3\"" "$row/shim/calls/1.stdin" 2>/dev/null || true)" == 1 && "$(grep -cxF -- "header = \"CF-Access-Client-Id: $4\"" "$row/shim/calls/1.stdin" 2>/dev/null || true)" == 1 \
      && "$(grep -cxF -- "header = \"CF-Access-Client-Secret: $5\"" "$row/shim/calls/1.stdin" 2>/dev/null || true)" == 1 && "$(wc -l < "$row/shim/calls/1.stdin" 2>/dev/null | tr -d ' ')" == 3 ]] || LD_BAD+=" headers-not-on-stdin"
    for f in "$row"/shim/calls/*.argv; do [[ -e "$f" ]] && for v in "$3" "$4" "$5"; do grep -aqF -- "$v" "$f" && LD_BAD+=" credential-in-argv"; done; done
    [[ "$(grep -cxF 'DRV-CODE=200' "$row/stdout" || true)" == 1 ]] || LD_BAD+=" code"
    [[ "$(bk_count "$row/stderr" "$LD_MARK")" == 0 ]] || LD_BAD+=" marker-on-success"
  else
    [[ "$(bk_calls "$row")" == 0 ]] || LD_BAD+=" calls=$(bk_calls "$row")"
    [[ "$(bk_count "$row/stderr" "$LD_MARK")" == 1 ]] || LD_BAD+=" marker-count=$(bk_count "$row/stderr" "$LD_MARK")"
    [[ "$(grep -cxF 'DRV-CODE=000' "$row/stdout" || true)" == 1 ]] || LD_BAD+=" verdict-class"
    [[ "$(bk_count "$row/stdout" SYNTHMARK0001)$(bk_count "$row/stderr" SYNTHMARK0001)$(bk_count "$row/stdout" SYNTHMARK0002)$(bk_count "$row/stderr" SYNTHMARK0002)" == 0000 ]] || LD_BAD+=" value-in-output"
  fi
}
dc_run dc-ok "$dc_txt" "$HM_WH" "$HM_CFID" "$HM_CFSEC"; dc_check dc-ok ok "$HM_WH" "$HM_CFID" "$HM_CFSEC"
if [[ -z "$LD_BAD" ]]; then row "lead (a2) op=verify zero-run discovery driven with well-formed values (control): one request, the signature and both Cloudflare Access headers on the --config - stdin only, HTTP 200, no marker" ok
else row "lead (a2) op=verify zero-run discovery driven with well-formed values (control): one request, the signature and both Cloudflare Access headers on the --config - stdin only, HTTP 200, no marker" fail "$LD_BAD"; fi
ld_bad=""; ld_n=0
for ld_slot in sig id secret; do
  for ld_cls in $TOK_CLASSES; do
    ld_h="$(tok_for "$ld_cls")"; ld_s="$HM_WH"; ld_i="$HM_CFID"; ld_x="$HM_CFSEC"
    case "$ld_slot" in sig) ld_s="$ld_h" ;; id) ld_i="$ld_h" ;; secret) ld_x="$ld_h" ;; esac
    dc_run "dc-bad-$ld_slot-$ld_cls" "$dc_txt" "$ld_s" "$ld_i" "$ld_x"; dc_check "dc-bad-$ld_slot-$ld_cls" bad "$ld_s" "$ld_i" "$ld_x"; ld_n=$((ld_n + 1))
    [[ -z "$LD_BAD" ]] || ld_bad+=" [$ld_slot/$ld_cls:$LD_BAD]"
  done
done
[[ "$ld_n" -ge 24 ]] || ld_bad+=" [ran $ld_n cases]"
if [[ -z "$ld_bad" ]]; then row "lead (a2) op=verify zero-run discovery driven with an unusable signature, Cloudflare Access id or secret of every hostile class: zero requests, the marker once on stderr, the advisory failure class (HTTP 000), nothing of the value in any stream" ok
else row "lead (a2) op=verify zero-run discovery driven with an unusable signature, Cloudflare Access id or secret of every hostile class: zero requests, the marker once on stderr, the advisory failure class (HTTP 000), nothing of the value in any stream" fail "$ld_bad"; fi
ld_bad=""; ld_n=0
while IFS='|' read -r ld_name ld_slot ld_cls ld_from ld_to ld_must; do
  [[ -n "$ld_name" ]] || continue
  text_mut "$dc_txt" "$ld_from" "$ld_to"
  ld_s="$HM_WH"; ld_i="$HM_CFID"; ld_x="$HM_CFSEC"; ld_h="$(tok_for "$ld_cls")"
  case "$ld_slot" in sig) ld_s="$ld_h" ;; id) ld_i="$ld_h" ;; secret) ld_x="$ld_h" ;; esac
  dc_run "dc-mut-$ld_name" "$TM_OUT" "$ld_s" "$ld_i" "$ld_x"; dc_check "dc-mut-$ld_name" bad "" "" ""; ld_n=$((ld_n + 1))
  ld_caught "$LD_BAD" "$ld_must" || ld_bad+=" [$ld_name: got '${LD_BAD:-<none>}' wanted a failure naming '$ld_must']"
done <<'DC_MUTANTS'
guard-removed|sig|quote-newline-url|            if _bearer_ok "$SIG" && _bearer_ok "$CF_ACCESS_CLIENT_ID" && _bearer_ok "$CF_ACCESS_CLIENT_SECRET"; then|            if true; then|calls=
secret-unjudged|secret|tab|_bearer_ok "$SIG" && _bearer_ok "$CF_ACCESS_CLIENT_ID" && _bearer_ok "$CF_ACCESS_CLIENT_SECRET"; then|_bearer_ok "$SIG" && _bearer_ok "$CF_ACCESS_CLIENT_ID"; then|calls=
id-unjudged|id|cr|_bearer_ok "$SIG" && _bearer_ok "$CF_ACCESS_CLIENT_ID" && _bearer_ok "$CF_ACCESS_CLIENT_SECRET"; then|_bearer_ok "$SIG" && _bearer_ok "$CF_ACCESS_CLIENT_SECRET"; then|calls=
marker-dropped|sig|quote|              echo "SOLEUR_CREDENTIAL_REFUSED script=cutover-inngest reason=token_shape" >&2|              : "SOLEUR_CREDENTIAL_REFUSED script=cutover-inngest reason=token_shape" >&2|marker-count
code-dropped|sig|quote|              DISC_CODE="000"|              DISC_CODE="200"|verdict-class
DC_MUTANTS
[[ "$ld_n" == 5 ]] || ld_bad+=" [ran $ld_n of 5 mutants]"
if [[ -z "$ld_bad" ]]; then row "lead (a2) mutants: the guard removed, either Cloudflare Access value left unjudged, the marker dropped and a refusal that reads as success are each caught" ok
else row "lead (a2) mutants: the guard removed, either Cloudflare Access value left unjudged, the marker dropped and a refusal that reads as success are each caught" fail "$ld_bad"; fi

# ---- (g) the four response-body echoes ------------------------------------------------------------------------
# Each statement is taken verbatim from the script and run with a BODY whose first line is hostile (an ESC sequence, a CR, a forged `::error::` start, 300
# characters) and whose second line is a canary: the output is ONE line that starts with the arm's own text, holds the bounded scrubbed first line and not the canary.
gb_canary="BODYCANARY-$(od -An -N6 -tx1 /dev/urandom | tr -d ' \n')"
gb_first="::error::forged-first-line"$'\e[31m'$'\r'"$(printf 'x%.0s' $(seq 1 300))"
gb_body="$gb_first"$'\n'"$gb_canary"
gb_stmt() { # <grep anchor> -> the single script line
  grep -m1 -F -- "$1" "$CUT" | sed -E 's/^[[:space:]]+//'
}
gb_fn="$(grep -m1 '^_body_head() {' "$CUT")"
[[ -n "$gb_fn" ]] || fatal "lead (g): _body_head is missing from $CUT"
gb_run() { # <row> <statement> <body> [function text, default the script's own _body_head] -> $ROWS/<row>/out
  local row="$ROWS/$1"; assert_fixture_dir "$row"; mkdir -p "$row/tmp"
  { printf 'set -euo pipefail\n'; printf '%s\n' "${4:-$gb_fn}"; printf '%s\n' "$2" | sed 's|/tmp/rearm-body|${BK_TMP}/rearm-body|g'; } > "$row/drv.sh"
  printf '%s' "$3" > "$row/tmp/rearm-body"
  ( cd "$row" && env -i PATH="$LD_REAL" BK_TMP="$row/tmp" BODY="$3" "$BASH_BIN" "$row/drv.sh" < /dev/null > "$row/out" 2>&1 )
  LD_RC=$?
}
gb_want="$(printf '%s' "$gb_first" | LC_ALL=C tr -c ' -~' '?' | cut -c1-160)"
gb_check() { # <row> <text the one output line must start with> -> LD_BAD
  local o="$ROWS/$1/out" want="$2" first; LD_BAD=""
  first="$(head -n1 "$o")"
  [[ "$(wc -l < "$o" | tr -d ' ')" == 1 ]] || LD_BAD+=" not-one-line"
  [[ "$first" == "$want"* ]] || LD_BAD+=" arm-text"
  [[ "$(bk_count "$o" "$gb_canary")" == 0 ]] || LD_BAD+=" second-line-leaked"
  [[ -z "$(LC_ALL=C tr -d '\n -~' < "$o")" ]] || LD_BAD+=" non-printable"
  [[ "$first" == *"$gb_want" || "$first" == *"$gb_want)" ]] || LD_BAD+=" head-not-bounded-and-scrubbed"
  [[ "$first" != *"${gb_want}x"* ]] || LD_BAD+=" head-longer-than-160"
}
gb_bad=""; gb_n=0
while IFS='~' read -r gb_name gb_anchor gb_text; do
  [[ -n "$gb_name" ]] || continue
  gb_line="$(gb_stmt "$gb_anchor")"; [[ -n "$gb_line" ]] || { gb_bad+=" [$gb_name: statement not found]"; continue; }
  [[ "$gb_line" == *'_body_head'* ]] || gb_bad+=" [$gb_name: no _body_head]"
  gb_run "gb-$gb_name" "$gb_line" "$gb_body"; gb_check "gb-$gb_name" "$gb_text"; gb_n=$((gb_n + 1))
  [[ -z "$LD_BAD" ]] || gb_bad+=" [$gb_name:$LD_BAD]"
done <<'GB_SITES'
enumerate~echo "::error::enumerate did not return a JSON array~::error::enumerate did not return a JSON array (first line of the response, bounded and scrubbed: 
registry-probe~echo "::error::registry-probe did not return a {registry_empty,function_count,function_ids} object~::error::registry-probe did not return a {registry_empty,function_count,function_ids} object (first line of the response, bounded and scrubbed: 
doublefire-probe~echo "::error::doublefire-probe did not return a {runs:[...]} object~::error::doublefire-probe did not return a {runs:[...]} object (first line of the response, bounded and scrubbed: 
rearm~echo "re-arm response (first line, bounded and scrubbed)~re-arm response (first line, bounded and scrubbed): 
GB_SITES
[[ "$gb_n" == 4 ]] || gb_bad+=" [ran $gb_n of 4 sites]"
if [[ -z "$gb_bad" ]]; then row "lead (g) the enumerate, registry-probe, doublefire-probe and re-arm body echoes, driven with a body whose first line holds an ESC sequence, a CR, a forged ::error:: start and 300 characters, print ONE line: the arm's own text, then the first line cut at 160 characters with every non-printable byte replaced, and never the second line" ok
else row "lead (g) the enumerate, registry-probe, doublefire-probe and re-arm body echoes, driven with a body whose first line holds an ESC sequence, a CR, a forged ::error:: start and 300 characters, print ONE line: the arm's own text, then the first line cut at 160 characters with every non-printable byte replaced, and never the second line" fail "$gb_bad"; fi
gb_line="$(gb_stmt 'echo "::error::enumerate did not return a JSON array')"
gb_run gb-ctl "$gb_line" 'HTTP 502 Bad Gateway'$'\n'"$gb_canary"
if [[ "$(head -n1 "$ROWS/gb-ctl/out")" == '::error::enumerate did not return a JSON array (first line of the response, bounded and scrubbed: HTTP 502 Bad Gateway)' && "$(wc -l < "$ROWS/gb-ctl/out" | tr -d ' ')" == 1 ]]; then row "lead (g) control: a short plain first line is printed intact (the scrub does not eat a readable cause)" ok
else row "lead (g) control: a short plain first line is printed intact (the scrub does not eat a readable cause)" fail "$(head -c 200 "$ROWS/gb-ctl/out")"; fi
gb_bad=""; gb_n=0
while IFS='|' read -r gb_name gb_kind gb_from gb_to gb_must; do
  [[ -n "$gb_name" ]] || continue
  case "$gb_kind" in
    fn)      text_mut "$gb_fn" "$gb_from" "$gb_to"; gb_run "gb-mut-$gb_name" "$gb_line" "$gb_body" "$TM_OUT" ;;
    fnshort) text_mut "$gb_fn" "$gb_from" "$gb_to"; gb_run "gb-mut-$gb_name" "$gb_line" 'HTTP 502 Bad Gateway'$'\n'"$gb_canary" "$TM_OUT" ;;
    *)       text_mut "$gb_line" "$gb_from" "$gb_to"; gb_run "gb-mut-$gb_name" "$TM_OUT" "$gb_body" ;;
  esac
  if [[ "$gb_kind" == fnshort ]]; then   # a SHORT first line (the cut at 160 cannot hide a kept second line): only the canary clause applies
    LD_BAD=""; [[ "$(bk_count "$ROWS/gb-mut-$gb_name/out" "$gb_canary")" == 0 ]] || LD_BAD+=" second-line-leaked"
  else gb_check "gb-mut-$gb_name" '::error::enumerate did not return a JSON array (first line of the response, bounded and scrubbed: '; fi
  gb_n=$((gb_n + 1))
  ld_caught "$LD_BAD" "$gb_must" || gb_bad+=" [$gb_name: got '${LD_BAD:-<none>}' wanted a failure naming '$gb_must']"
done <<'GB_MUTANTS'
raw-body|line|$(_body_head "$BODY")|$BODY|second-line-leaked
unbounded|fn|${_h:0:160}|${_h:0:400}|head-not-bounded-and-scrubbed
unscrubbed|fn|_h="${_h//[^ -~]/?}"; ||non-printable
whole-body|fnshort|_h="${1%%$'\n'*}"|_h="$1"|second-line-leaked
GB_MUTANTS
[[ "$gb_n" == 4 ]] || gb_bad+=" [ran $gb_n of 4 mutants]"
if [[ -z "$gb_bad" ]]; then row "lead (g) mutants: the raw body printed, a head that is not cut at 160, a head that is not scrubbed and a head that keeps every line are each caught" ok
else row "lead (g) mutants: the raw body printed, a head that is not cut at 160, a head that is not scrubbed and a head that keeps every line are each caught" fail "$gb_bad"; fi
echo "=== stage S2-A part 2: cutover HMAC copies, refusal marker, canary sweep done ==="

