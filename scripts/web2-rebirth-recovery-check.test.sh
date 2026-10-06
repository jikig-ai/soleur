#!/usr/bin/env bash
# Tests for scripts/web2-rebirth-recovery-check.sh (#9372, step S12): every check, every unreadable input, the
# secret-handling properties (the passphrase and the R2 secret never reach any argv, a file or stdout), and a mutation
# battery that removes each rule from a COPY of the script and requires the battery to go red.
# Fixtures are synthesized (cq-test-fixtures-synthesized-only); every tool is a PATH shim.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="${DIR}/web2-rebirth-recovery-check.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

BIN="$TMP/bin"; mkdir -p "$BIN"
# ---- shims -----------------------------------------------------------------------------------------------------
cat > "$BIN/doppler" <<'SH'
#!/usr/bin/env bash
echo "doppler $* [cfgdir=${DOPPLER_CONFIG_DIR:+set} vercheck=${DOPPLER_ENABLE_VERSION_CHECK:-unset}]" >> "$LOG/argv.log"
[[ "${MODE_DOPPLER:-ok}" != fail ]] || exit 1
case "$3" in
  WORKSPACES_HEADER_BUCKET) printf '%s' "$SH_BUCKET" ;;
  WORKSPACES_HEADER_R2_ENDPOINT) printf '%s' "$SH_ENDPOINT" ;;
  WORKSPACES_HEADER_R2_ACCESS_KEY_ID) printf '%s' "$SH_KID" ;;
  WORKSPACES_HEADER_R2_SECRET_ACCESS_KEY) printf '%s' "$SH_SECRET" ;;
  WORKSPACES_LUKS_KEY) printf '%s' "$SH_KEY" ;;
  *) exit 1 ;;
esac
SH
cat > "$BIN/terraform" <<'SH'
#!/usr/bin/env bash
echo "terraform $*" >> "$LOG/argv.log"
[[ "${MODE_TF:-ok}" != fail ]] || exit 1
jq -cn --arg k "$SH_TFKEY" '{resources: [
  {mode: "managed", type: "random_password", name: "other_secret", instances: [{attributes: {result: "OTHERSECRETVALUE0123456789"}}]},
  {mode: "managed", type: "random_password", name: "workspaces_luks_web", instances: [{attributes: {result: $k}}]}]}'
SH
cat > "$BIN/curl" <<'SH'
#!/usr/bin/env bash
echo "curl $*" >> "$LOG/argv.log"
out=""; url=""; cfg=0; prev=""
for a in "$@"; do
  [[ "$prev" == "-o" ]] && out="$a"
  [[ "$prev" == "--config" && "$a" == "-" ]] && cfg=1
  prev="$a"; url="$a"
done
[[ "$cfg" -eq 0 ]] || { printf 'curl-stdin: %s\n' "$(cat)" >> "$LOG/stdin.log"; }
[[ "${MODE_CURL:-ok}" != fail ]] || exit 7
if [[ "$url" == *"list-type=2"* ]]; then
  case "${MODE_LIST:-one}" in
    zero) body='<ListBucketResult><IsTruncated>false</IsTruncated></ListBucketResult>' ;;
    two) body="<ListBucketResult><Contents><Key>workspaces-luks-header-${SH_UUID}.img</Key></Contents><Contents><Key>workspaces-luks-header-aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee.img</Key></Contents></ListBucketResult>" ;;
    stray) body="<ListBucketResult><Contents><Key>workspaces-luks-header-${SH_UUID}.img</Key></Contents><Contents><Key>workspaces-luks-header-notes.txt</Key></Contents></ListBucketResult>" ;;
    badname) body="<ListBucketResult><Contents><Key>workspaces-luks-header-not-a-uuid.img</Key></Contents></ListBucketResult>" ;;
    truncated) body="<ListBucketResult><IsTruncated>true</IsTruncated><Contents><Key>workspaces-luks-header-${SH_UUID}.img</Key></Contents></ListBucketResult>" ;;
    *) body="<ListBucketResult><IsTruncated>false</IsTruncated><Contents><Key>workspaces-luks-header-${SH_UUID}.img</Key><Size>16777216</Size></Contents></ListBucketResult>" ;;
  esac
  printf '%s' "$body" > "$out"; printf '%s' "${CODE_LIST:-200}"
else
  case "${MODE_GET:-ok}" in
    badmagic) printf 'NOTLUKS-header-bytes' > "$out" ;;
    empty) : > "$out" ;;
    *) printf 'LUKS\272\276-header-bytes' > "$out" ;;
  esac
  printf '%s' "${CODE_GET:-200}"
fi
SH
cat > "$BIN/cryptsetup" <<'SH'
#!/usr/bin/env bash
echo "cryptsetup $*" >> "$LOG/argv.log"
case "$1" in
  luksUUID) printf '%s\n' "${SH_UUID_HDR:-$SH_UUID}" ;;
  open)
    cat > "$LOG/cs-stdin"
    # no file under the script's temp root may hold either passphrase at the moment it is used
    grep -rlF -e "$SH_KEY" -e "$SH_TFKEY" "$TMPDIR" > "$LOG/files-with-passphrase" 2>/dev/null || true
    [[ "${MODE_CS:-ok}" == ok ]] ;;
  *) exit 2 ;;
esac
SH
chmod +x "$BIN"/*

UUID=0f8fad5b-d9cb-469f-a165-70867728950e
KEY=correct-horse-battery-staple-9X
KID=AKIDEXAMPLE0123456789ABCDEF
RSECRET=R2SECRETEXAMPLE0123456789abcdefghij
BUCKET=soleur-web-luks-headers
ENDPOINT=https://0123456789abcdef0123456789abcdef.r2.cloudflarestorage.com
# shellcheck disable=SC2034 # read by the eval-ed assertions in battery()
FORBIDDEN='recoverable|restore-tested|Art\. ?32|satisfied'

# battery <script> — prints "FAILED <name>" per failed assertion and "RAN <n>" last.
battery() {
  local script="$1" n=0 out rc
  run() { # <env words...> -> sets out, rc
    rm -rf "$TMP/log" "$TMP/work"; mkdir -p "$TMP/log" "$TMP/work"
    out="$(env -i PATH="$BIN:/usr/bin:/bin" HOME="$TMP" TMPDIR="$TMP/work" LOG="$TMP/log" DOPPLER_TOKEN=tok \
      SH_BUCKET="$BUCKET" SH_ENDPOINT="$ENDPOINT" SH_KID="$KID" SH_SECRET="$RSECRET" SH_KEY="$KEY" SH_TFKEY="$KEY" SH_UUID="$UUID" \
      "$@" bash "$script" 2>&1)"; rc=$?
  }
  chk() { # <name> <want-rc> <substring|-> <env words...>
    local name="$1" want="$2" sub="$3"; shift 3
    run "$@"; n=$((n + 1))
    if [[ "$rc" -ne "$want" ]]; then printf 'FAILED %s (rc=%s want=%s): %s\n' "$name" "$rc" "$want" "${out:0:200}"; return; fi
    if [[ "$sub" != "-" && "$out" != *"$sub"* ]]; then printf 'FAILED %s (rc ok, output lacks %q): %s\n' "$name" "$sub" "${out:0:200}"; fi
  }
  as() { n=$((n + 1)); eval "$2" || printf 'FAILED %s\n' "$1"; } # <name> <test-expression>

  # ---- the happy path and its properties
  chk "PASS: every check green" 0 "PASS birth-time consistency check; restore NOT exercised; open until #7992 and a restore drill"
  as "the success line is the LAST line, verbatim" '[[ "$(tail -n1 <<<"$out")" == "web2-rebirth-recovery-check: PASS birth-time consistency check; restore NOT exercised; open until #7992 and a restore drill" ]]'
  chk "PASS with W2_FACTS_FILE: the non-secret facts are written to the file" 0 "PASS" W2_FACTS_FILE="$TMP/work/facts.txt"
  as "the facts file names the object and the checks, and holds NO secret and no ::add-mask:: line" '[[ -s "$TMP/work/facts.txt" ]] && grep -q "escrow object: key=workspaces-luks-header-" "$TMP/work/facts.txt" && grep -q "escrow checks:" "$TMP/work/facts.txt" && ! grep -qF -e "$KEY" -e "$RSECRET" -e "$KID" -e "::add-mask::" "$TMP/work/facts.txt"'
  chk "PASS without W2_FACTS_FILE" 0 "PASS"
  as "without W2_FACTS_FILE no facts file is written" '[[ ! -e "$TMP/work/facts.txt" ]]'
  as "the output states the passphrase copies agree" '[[ "$out" == *"passphrase copies agree: yes"* ]]'
  as "no forbidden claim in the output" '! grep -qiE "$FORBIDDEN" <<<"$out"'
  as "the passphrase never reaches any shim argv" '! grep -qF -e "$KEY" "$TMP/log/argv.log"'
  as "the R2 secret never reaches any shim argv" '! grep -qF -e "$RSECRET" "$TMP/log/argv.log"'
  as "the R2 pair rode stdin to curl (positive control)" 'grep -qF "curl-stdin: user = \"$KID:$RSECRET\"" "$TMP/log/stdin.log"'
  as "the passphrase arrived on cryptsetup stdin exactly, with no trailing newline" '[[ "$(cat "$TMP/log/cs-stdin")" == "$KEY" && "$(wc -c < "$TMP/log/cs-stdin" | tr -d " ")" == "${#KEY}" ]]'
  as "no file under the temp root held a passphrase while it was in use" '[[ ! -s "$TMP/log/files-with-passphrase" ]]'
  as "the passphrase appears in stdout only on ::add-mask:: lines" '! grep -v "^::add-mask::" <<<"$out" | grep -qF -e "$KEY"'
  as "the state's other secret appears nowhere" '! grep -qF "OTHERSECRETVALUE" <<<"$out$(cat "$TMP/log/argv.log")"'
  as "terraform was only asked to pull state" '[[ "$(grep -c "^terraform " "$TMP/log/argv.log")" == 1 ]] && grep -qx "terraform state pull" "$TMP/log/argv.log"'
  as "every doppler call was a single-secret read with a private config dir and no version check" '[[ "$(grep -c "^doppler " "$TMP/log/argv.log")" == 5 ]] && ! grep "^doppler " "$TMP/log/argv.log" | grep -vqE "^doppler secrets get [A-Z_0-9]+ --plain -p soleur -c prd_workspaces_luks_web \[cfgdir=set vercheck=false\]$"'
  as "curl was always hardened (--disable, --noproxy, --max-time, no -k, no -f)" '! grep "^curl " "$TMP/log/argv.log" | grep -vqE "^curl --disable --noproxy \* --config - --aws-sigv4 aws:amz:auto:s3 -sS --max-time 60 "'
  as "the bucket was listed under the header prefix" 'grep -qF "list-type=2&prefix=workspaces-luks-header-" "$TMP/log/argv.log"'

  # ---- (a) exactly one escrowed header
  chk "REFUSE (a): zero keys" 1 "no escrowed header" MODE_LIST=zero
  chk "REFUSE (a): two keys" 1 "ambiguous" MODE_LIST=two
  chk "REFUSE (a): a stray key under the prefix" 1 "ambiguous" MODE_LIST=stray
  chk "REFUSE (a): a key that is not <uuid>.img" 1 "ambiguous" MODE_LIST=badname
  chk "REFUSE (a): a truncated listing" 1 "truncated" MODE_LIST=truncated
  chk "UNREADABLE (a): the listing answers 403" 3 "not 200" CODE_LIST=403
  chk "UNREADABLE (a): the listing is a transport failure" 3 "000" MODE_CURL=fail

  # ---- (b) the object is a LUKS header image
  chk "REFUSE (b): wrong magic" 1 "LUKS magic" MODE_GET=badmagic
  chk "REFUSE (b): empty object" 1 "empty" MODE_GET=empty
  chk "UNREADABLE (b): the object GET answers 404" 3 "not 200" CODE_GET=404

  # ---- (c) the image's own UUID is the one in its name
  chk "REFUSE (c): the header's UUID differs from its object name" 1 "UUID differs" SH_UUID_HDR=aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee
  chk "PASS (c): the UUID comparison is case-insensitive" 0 "PASS" SH_UUID_HDR=0F8FAD5B-D9CB-469F-A165-70867728950E

  # ---- (d) the two passphrase copies agree
  chk "REFUSE (d): the copies differ" 1 "passphrase copies agree: no" SH_TFKEY=a-different-passphrase-9X
  chk "REFUSE (d): the difference is also named as an error" 1 "copies differ" SH_TFKEY=a-different-passphrase-9X

  # ---- (e) the passphrase opens the header
  chk "REFUSE (e): the header does not accept the passphrase" 1 "test-passphrase" MODE_CS=fail

  # ---- unreadable inputs are exit 3, never a pass
  chk "UNREADABLE: a Doppler read fails" 3 "could not read" MODE_DOPPLER=fail
  chk "UNREADABLE: the Terraform state pull fails" 3 "Terraform state" MODE_TF=fail
  chk "UNREADABLE: no token" 3 "DOPPLER_TOKEN is not set" DOPPLER_TOKEN=
  chk "UNREADABLE: the state holds an empty passphrase" 3 "empty" SH_TFKEY=
  chk "UNREADABLE: an empty Doppler value" 3 "is empty" SH_KID=

  # ---- shapes are checked before anything is sent
  chk "REFUSE: bucket shape" 1 "unexpected shape" SH_BUCKET=Bad_Bucket
  chk "REFUSE: endpoint shape (wrong host)" 1 "unexpected shape" SH_ENDPOINT=https://evil.example.com
  chk "REFUSE: access key id shape" 1 "unexpected shape" SH_KID='AK"ID0123456789ABCDEF'
  chk "REFUSE: secret shape" 1 "unexpected shape" SH_SECRET='short'
  run SH_BUCKET=Bad_Bucket; n=$((n + 1)); [[ ! -s "$TMP/log/argv.log" ]] || [[ "$(grep -c '^curl ' "$TMP/log/argv.log")" == 0 ]] || printf 'FAILED a shape-invalid value still reached curl\n'

  # ---- xtrace is refused while a credential is set
  rm -rf "$TMP/log"; mkdir -p "$TMP/log"; n=$((n + 1))
  env -i PATH="$BIN:/usr/bin:/bin" HOME="$TMP" TMPDIR="$TMP/work" LOG="$TMP/log" DOPPLER_TOKEN=tok bash -x "$script" >/dev/null 2>&1; rc=$?
  [[ "$rc" -eq 78 ]] || printf 'FAILED xtrace with a live token must exit 78 (got %s)\n' "$rc"

  # ---- static properties of the script itself
  as "no doppler run, no download, no insecure curl" '! grep -nE "doppler run|secrets download|--insecure|curl[^#]* -k( |$)" "$script" | grep -v ":[[:space:]]*#" | grep -q .'
  as "the script uses stdin for the key and the R2 pair" 'grep -qF -e "--key-file=-" "$script" && grep -qF -e "--config -" "$script"'
  as "the state is piped into one jq program and never written" '[[ "$(grep -c "terraform state pull" <(grep -v "^[[:space:]]*#" "$script"))" == 1 ]] && grep -v "^[[:space:]]*#" "$script" | grep "terraform state pull" | grep -qF "| jq -er"'
  as "the script claims no recovery property in its success line" '! grep -E "^echo \"web2-rebirth-recovery-check: PASS" "$script" | grep -qiE "$FORBIDDEN"'

  printf 'RAN %s\n' "$n"
}

fails=0; ran=0
report="$(battery "$SCRIPT" 2>&1)"
while IFS= read -r line; do
  case "$line" in FAILED*) fails=$((fails + 1)); printf '  FAIL %s\n' "${line#FAILED }" ;; RAN*) ran="${line#RAN }" ;; *) [[ -z "$line" ]] || printf '       %s\n' "$line" ;; esac
done <<<"$report"
printf 'real script: %s assertions, %s failed\n' "$ran" "$fails"
[[ "$ran" -ge 45 ]] || { echo "  FAIL assertion floor: ran ${ran} < 45"; fails=$((fails + 1)); }

# ---- mutation battery: each mutant is a COPY with one rule removed or one leak introduced; the battery must go red
mutate() { # <name> <sed-script>
  local name="$1" copy="$TMP/mut/scripts/web2-rebirth-recovery-check.sh" after
  rm -rf "$TMP/mut"; mkdir -p "$TMP/mut/scripts" "$TMP/mut/apps/web-platform/infra"
  cp "$SCRIPT" "$copy"
  sed -i -E "$2" "$copy"
  if cmp -s "$SCRIPT" "$copy"; then echo "  FAIL mutation '${name}' did not change the script (the anchor drifted)"; fails=$((fails + 1)); return; fi
  if ! bash -n "$copy" 2>/dev/null; then echo "  FAIL mutation '${name}' does not parse (a dead mutant is not a catch)"; fails=$((fails + 1)); return; fi
  after="$(battery "$copy" 2>&1 | grep -c '^FAILED')"
  if [[ "$after" -gt 0 ]]; then echo "  ok   mutation killed: ${name} (${after} red)"; else echo "  FAIL mutation SURVIVED: ${name}"; fails=$((fails + 1)); fi
}
marker() { printf 's/^(\\s*)[^#]*(# RC:%s)$/\\1: \\2/' "$1"; }
# harmless control: a trailing comment must stay green (a battery that reds on everything proves nothing)
rm -rf "$TMP/mut"; mkdir -p "$TMP/mut/scripts" "$TMP/mut/apps/web-platform/infra"
sed 's/^LUKS_MAGIC_HEX="4c554b53babe"$/LUKS_MAGIC_HEX="4c554b53babe" # harmless/' "$SCRIPT" > "$TMP/mut/scripts/web2-rebirth-recovery-check.sh"
if [[ "$(battery "$TMP/mut/scripts/web2-rebirth-recovery-check.sh" 2>&1 | grep -c '^FAILED')" -eq 0 ]]; then echo "  ok   harmless variant stays green"; else echo "  FAIL harmless variant went red: the battery is not discriminating"; fails=$((fails + 1)); fi

mutate "shape check removed"                    "$(marker SHAPE)"
mutate "zero-key refusal removed"               "$(marker ZERO)"
mutate "exactly-one rule removed"               "$(marker AMBIG)"
mutate "truncated-listing refusal removed"      "$(marker TRUNC)"
mutate "empty-object refusal removed"           "$(marker SIZE)"
mutate "LUKS magic check removed"               "$(marker MAGIC)"
mutate "header-UUID check removed"              "$(marker UUID)"
mutate "passphrase agreement check removed"     "$(marker AGREE)"
mutate "test-passphrase check removed"          "$(marker TESTPASS)"
mutate "state read failure and emptiness ignored" "s/^(\\s*)pass_t=.*# RC:STATE-FAIL\$/\\1pass_t=\"\"   # RC:STATE-FAIL/; $(marker STATE-EMPTY)"
mutate "R2 secret on curl argv (argv leak)"     's/--config - /-u "$kid:$secret" /'
mutate "state passphrase printed"               '/# RC:STATE-EMPTY$/a echo "state value: $pass_t"'
mutate "passphrase written to a file"           '/# RC:AGREE$/a printf "%s" "$pass_d" > "$W/p.txt"'
mutate "passphrase on cryptsetup argv"          's/cryptsetup open --test-passphrase --key-file=- "\$W\/hdr.img"/cryptsetup open --test-passphrase --key-file=- "$W\/hdr.img" --pw "$pass_d"/'
mutate "token-less run no longer refused"       's/^\[\[ -n "\$\{DOPPLER_TOKEN:-\}" \]\] \|\| unreadable .*/:/'

echo
[[ "$fails" -eq 0 ]] && { echo "web2-rebirth-recovery-check: all assertions and mutations passed"; exit 0; }
echo "web2-rebirth-recovery-check: ${fails} FAILED"; exit 1
