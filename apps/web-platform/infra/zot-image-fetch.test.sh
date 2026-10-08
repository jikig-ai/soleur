#!/usr/bin/env bash
# (#8714 step 5.3b-iii) The registry host boots zot from a pinned GitHub release asset, with ghcr.io
# name-resolution-denied. Three guards, all executed rather than grepped where execution is possible:
#
#   F  zot-image-fetch.sh (Guard 1 of the plan): the ONLY path to a zot image on the host. Extracted
#      from cloud-init-registry.yml and run against stub curl/docker with a call log. Every verdict
#      arm (ok, config_invalid, download_failed, sha_mismatch, load_failed, id_mismatch) is driven,
#      and each refusal asserts what must NOT have happened (no load after a sha mismatch, no ID on
#      stdout or in the hand-off file after a refusal).
#   R  the RENDERED user_data (terraform's own templatefile, via registry-userdata-budget.sh): the
#      deny runs before the fetch, the fetch before the one `docker run` of zot, the fetch is outside
#      every `doppler run`, zot runs by "$ZOT_IMAGE_ID", and ghcr.io appears on a code line only in
#      the deny itself and the heartbeat's probe of it. Also pins the render <-> preflight parity of
#      the asset URL (P6 and rule-audit derive it in bash; the host derives it in terraform).
#   H  the SOLEUR_ZOT_DISK heartbeat's three new/remapped fields: zot_image_digest (from the running
#      container's image ID), zot_image_fetch (the fetch verdict) and ghcr_blocked (the deny, probed).
#
# Every fixture is synthesized (cq-test-fixtures-synthesized-only). The render rows need terraform:
# SKIP locally without it, FAIL CLOSED in CI, like registry-userdata-budget.test.sh.
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/../../.." && pwd)"
CI_YML="$DIR/cloud-init-registry.yml"   # NOT `CI`: runners export CI=1
PREFLIGHT="$ROOT/scripts/registry-replace-preflight.sh"

PASS=0; FAIL=0; FAILURES=()
pass() { PASS=$((PASS + 1)); printf '  pass: %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); FAILURES+=("$1"); printf '  FAIL: %s\n' "$1"; }
check() { if eval "$2" >/dev/null 2>&1; then pass "$1"; else fail "$1  [expr: $2]"; fi; }

# Instrument self-test BEFORE anything is measured: both helpers must move their counters.
check "instrument: a true condition passes" "true"
check "instrument: a false condition fails (this FAIL line is EXPECTED)" "false"
if [[ "$PASS" -ne 1 || "$FAIL" -ne 1 ]]; then
  printf '[FATAL] instrument: pass/fail counters did not move (pass=%s fail=%s)\n' "$PASS" "$FAIL" >&2; exit 2
fi
PASS=0; FAIL=0; FAILURES=()

TMP="$(mktemp -d)" || exit 2
trap 'rm -rf "$TMP"' EXIT

# extract_block <write_files path> <out> — the content: | body, dedented (zot-log-shipper.test.sh shape).
extract_block() {
  awk -v want="  - path: $1" '
    $0 == want { found = 1; next }
    found && /^    content: \|$/ { incontent = 1; next }
    incontent {
      if ($0 ~ /^      /) { print substr($0, 7); next }
      if ($0 ~ /^[[:space:]]*$/) { print ""; next }
      exit
    }
  ' "$CI_YML" > "$2"
}
# zot-registry.tf's registry_rationale_strip, as the sibling suites replicate it.
apply_rationale_strip() { sed -E '/^[[:blank:]]*#([[:blank:]].*)?$/d' "$1"; }

echo "--- F: zot-image-fetch.sh ---"
RAW="$TMP/fetch.raw.sh"
extract_block /usr/local/bin/zot-image-fetch.sh "$RAW"
check "F0 the fetch script is extracted from the template (non-empty, shebang first)" \
  "[[ -s '$RAW' ]] && head -1 '$RAW' | grep -q '^#!/usr/bin/env bash$'"
# BRACE-FREE: the body is a terraform templatefile; a dollar-brace or percent-brace would be
# consumed (or fail the render). Asserted on the RAW template body, comments included.
check "F0 the fetch body carries no dollar-brace (templatefile interpolation)" "! grep -qF '\${' '$RAW'"
check "F0 the fetch body carries no percent-brace (templatefile directive)" "! grep -qF '%{' '$RAW'"
FETCH="$TMP/fetch.sh"
apply_rationale_strip "$RAW" > "$FETCH"
check "F0 the comment-stripped fetch script is valid bash" "bash -n '$FETCH'"

# Render-time seams (never runtime ones): re-root the three host paths, put the stub dir first, and
# shorten the docker-readiness wait (30 x sleep 2) so the docker_unavailable arm runs in seconds.
FX="$TMP/fx"; BIN="$TMP/bin"; mkdir -p "$FX/state" "$FX/run" "$BIN"
sed -i -e "s|^PATH=.*|PATH=\"$BIN:\$PATH\"|" \
       -e "s|/etc/default/zot-image|$FX/zot-image.env|g" \
       -e "s|/var/lib/soleur|$FX/state|g" \
       -e "s|/run/soleur|$FX/run|g" \
       -e "s|sleep 2; done|sleep 0; done|" "$FETCH"
check "F0 the PATH, path and wait seams landed" \
  "grep -qF 'PATH=\"$BIN:' '$FETCH' && grep -qF '$FX/zot-image.env' '$FETCH' && grep -qF '$FX/state' '$FETCH' && grep -qF '$FX/run' '$FETCH' && grep -qF 'sleep 0; done' '$FETCH' && ! grep -qE '/etc/default/zot-image|/var/lib/soleur|/run/soleur|sleep 2; done' '$FETCH'"

# Stubs. Both VALIDATE argv (exit 64 + a refusal line) so a fetch that asks the wrong question
# cannot read the right fixture, and both append every call to $CALLS. curl also records the state
# verdict it observes when it runs (the `fetching` contract).
cat > "$BIN/curl" <<'EOF'
#!/usr/bin/env bash
printf 'curl %s\n' "$*" >> "$CALLS"
sed -n 1p "$STATE_FILE" > "$SEEN_STATE" 2>/dev/null
first="$1"; out=""; url=""; proto=0; redir=0; fail_flag=0; maxt=0; total=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    --proto) [[ "$2" == "=https" ]] && proto=1; shift 2 ;;
    --proto-redir) [[ "$2" == "=https" ]] && redir=1; shift 2 ;;
    --max-time) maxt=1; shift 2 ;;
    --retry-max-time) total=1; shift 2 ;;
    --connect-timeout|--retry|--retry-delay) shift 2 ;;
    -fsSL) fail_flag=1; shift ;;
    https://*|http://*) url="$1"; shift ;;
    *) shift ;;
  esac
done
if [[ "$first" != "-q" || -z "$out" || "$proto" != 1 || "$redir" != 1 || "$fail_flag" != 1 || "$maxt" != 1 || "$total" != 1 || "$url" != "$WANT_URL" ]]; then
  echo "REFUSED curl: first=$first out=$out proto=$proto redir=$redir fail=$fail_flag maxtime=$maxt total=$total url=$url" >> "$REFUSALS"; exit 64
fi
[[ "${CURL_RC:-0}" == 0 ]] || exit "$CURL_RC"
cp "$ASSET_BYTES" "$out"
EOF
cat > "$BIN/docker" <<'EOF'
#!/usr/bin/env bash
printf 'docker %s\n' "$*" >> "$CALLS"
case "$1" in
  info) exit "${INFO_RC:-0}" ;;
  load)
    [[ "$2" == "-i" && -f "$3" ]] || { echo "REFUSED docker load: $*" >> "$REFUSALS"; exit 64; }
    echo "Loaded image: $WANT_REF"; exit "${LOAD_RC:-0}" ;;
  image)
    if [[ "$2" == "rm" && "$3" == "-f" && "$4" == "$WANT_REF" && $# -eq 4 ]]; then exit 0; fi
    [[ "$2" == "inspect" && "$3" == "-f" && "$4" == '{{.Id}}' && "$5" == "$WANT_REF" && $# -eq 5 ]] \
      || { echo "REFUSED docker image: $*" >> "$REFUSALS"; exit 64; }
    [[ "${INSPECT_RC:-0}" == 0 ]] || exit "$INSPECT_RC"
    printf '%s\n' "$LOADED_ID"; exit 0 ;;
  *) echo "REFUSED docker: $*" >> "$REFUSALS"; exit 64 ;;
esac
EOF
chmod +x "$BIN"/*

# Synthesized OCI-shaped assets (cq-test-fixtures-synthesized-only). C is the sha256 of a synthesized
# config blob; the manifest names it and D is the manifest's sha256; T is the tarball's sha256. The
# digests are therefore NON-repeating, so a heartbeat that reported the wrong 12-hex slice of D is
# distinguishable. Two defective assets: one without the manifest blob, one whose manifest names a
# different config.
mk_asset() {  # $1 out.tar  $2 config-digest-the-manifest-names  $3 include-manifest(1|0)
  local d="$TMP/layout.$RANDOM" m
  mkdir -p "$d/blobs/sha256"
  m="{\"schemaVersion\":2,\"config\":{\"digest\":\"sha256:$2\",\"size\":1},\"layers\":[]}"
  local mh; mh="$(printf '%s' "$m" | sha256sum | cut -d' ' -f1)"
  [[ "$3" == 1 ]] && printf '%s' "$m" > "$d/blobs/sha256/$mh"
  printf 'x' > "$d/oci-layout"
  tar -C "$d" -cf "$1" oci-layout blobs   # member names as the builder writes them (no ./ prefix)
  printf '%s' "$mh"
}
C_OK="$(printf 'synthesized zot config (#8714 test)' | sha256sum | cut -d' ' -f1)"
D_OK="$(mk_asset "$TMP/asset.tar" "$C_OK" 1)"
T_OK="$(sha256sum "$TMP/asset.tar" | cut -d' ' -f1)"
mk_asset "$TMP/nomanifest.tar" "$C_OK" 0 >/dev/null; T_NOMAN="$(sha256sum "$TMP/nomanifest.tar" | cut -d' ' -f1)"
OTHER_C="$(printf 'another config' | sha256sum | cut -d' ' -f1)"
D_WRONGCFG="$(mk_asset "$TMP/wrongcfg.tar" "$OTHER_C" 1)"; T_WRONGCFG="$(sha256sum "$TMP/wrongcfg.tar" | cut -d' ' -f1)"
X_ID="$(printf 'a third, unrelated image id' | sha256sum | cut -d' ' -f1)"
check "F0 fixture digests are distinct and non-repeating" \
  "[[ '$C_OK' != '$D_OK' && '${D_OK:0:12}' != '${D_OK:52:12}' && '$D_WRONGCFG' != '$D_OK' ]]"
URL_OK="https://github.com/example-owner/example-repo/releases/download/zot-image-v9.9.9-${D_OK:0:12}/zot-linux-amd64-v9.9.9.oci.tar"
REF_OK="localhost/soleur-mirror/zot-linux-amd64:v9.9.9"
write_env() {  # $1 url  $2 T  $3 D  $4 C  $5 local ref
  printf 'ZOT_ASSET_URL=%s\nZOT_ASSET_SHA256=%s\nZOT_MANIFEST_DIGEST=%s\nZOT_CONFIG_DIGEST=%s\nZOT_LOCAL_REF=%s\n' \
    "$1" "$2" "$3" "$4" "$5" > "$FX/zot-image.env"
}

# run_fetch <env assignments...> — runs the fetch against a fresh state/run dir (seeded with a STALE
# hand-off file, which every refusal must remove); sets RC OUT STATE STATE_RC IDF SEEN.
run_fetch() {
  rm -rf "$FX/state" "$FX/run"; mkdir -p "$FX/state" "$FX/run"
  printf 'sha256:%s\n' "$X_ID" > "$FX/run/zot-image-id"
  : > "$TMP/calls"; : > "$TMP/refusals"; : > "$TMP/seen"
  env CALLS="$TMP/calls" REFUSALS="$TMP/refusals" ASSET_BYTES="$TMP/asset.tar" \
      STATE_FILE="$FX/state/zot-image-fetch.state" SEEN_STATE="$TMP/seen" \
      WANT_URL="$URL_OK" WANT_REF="$REF_OK" LOADED_ID="sha256:$C_OK" "$@" \
      bash "$FETCH" > "$TMP/out" 2> "$TMP/err"; RC=$?
  # shellcheck disable=SC2034  # read inside check()'s eval'd condition strings
  OUT="$(cat "$TMP/out")"
  STATE="$(sed -n 1p "$FX/state/zot-image-fetch.state" 2>/dev/null || echo __ABSENT__)"
  STATE_RC="$(sed -n 2p "$FX/state/zot-image-fetch.state" 2>/dev/null)"
  IDF="$(cat "$FX/run/zot-image-id" 2>/dev/null || echo __ABSENT__)"
  SEEN="$(cat "$TMP/seen")"
}
loaded() { grep -q '^docker load ' "$TMP/calls"; }
no_refusal() { [[ ! -s "$TMP/refusals" ]]; }
refused_clean() {  # every refusal: rc!=0, no ID on stdout, the stale hand-off file removed
  [[ "$RC" -ne 0 && -z "$OUT" && "$IDF" == __ABSENT__ ]]
}

write_env "$URL_OK" "$T_OK" "$D_OK" "$C_OK" "$REF_OK"

# F1 ok with C (classic image store)
run_fetch LOADED_ID="sha256:$C_OK"
check "F1 ok/C: rc 0, verdict ok, rc line 0" "[[ $RC -eq 0 && '$STATE' == ok && '$STATE_RC' == 0 ]]"
check "F1 ok/C: stdout is EXACTLY the verified ID (one line)" "[[ \"\$OUT\" == 'sha256:$C_OK' ]]"
check "F1 ok/C: the hand-off file carries the ID (the stale one replaced)" "[[ '$IDF' == 'sha256:$C_OK' ]]"
check "F1 ok/C: docker load ran, no stub refused a call" "loaded && no_refusal"
check "F1 ok/C: the downloaded tarball is removed after load" "[[ ! -e '$FX/state/zot-image.oci.tar' ]]"
check "F1 the verdict reads 'fetching' while the download runs (never not_run mid-fetch)" "[[ '$SEEN' == fetching ]]"
# F2 ok with D (containerd store)
run_fetch LOADED_ID="sha256:$D_OK"
check "F2 ok/D: rc 0, verdict ok, ID sha256:D on stdout and in the hand-off" \
  "[[ $RC -eq 0 && '$STATE' == ok && \"\$OUT\" == 'sha256:$D_OK' && '$IDF' == 'sha256:$D_OK' ]] && no_refusal"
# F3 (M1) sha mismatch: never loaded
write_env "$URL_OK" "$T_NOMAN" "$D_OK" "$C_OK" "$REF_OK"
run_fetch
check "F3 sha mismatch: verdict sha_mismatch, refused clean" "[[ '$STATE' == sha_mismatch ]] && refused_clean"
check "F3 sha mismatch: docker load was NEVER invoked (M1: a stub reporting ID C must not rescue it)" "! loaded"
check "F3 sha mismatch: the unverified tarball is deleted" "[[ ! -e '$FX/state/zot-image.oci.tar' ]]"
# F3b/F3c the host anchors C to D BEFORE loading: the manifest blob must be D and name C
write_env "$URL_OK" "$T_NOMAN" "$D_OK" "$C_OK" "$REF_OK"
run_fetch ASSET_BYTES="$TMP/nomanifest.tar"
check "F3b an asset (matching T) without the manifest blob D: manifest_mismatch, never loaded" \
  "[[ '$STATE' == manifest_mismatch ]] && refused_clean && ! loaded"
# F3d a blob NAMED D whose bytes are not D (a valid manifest naming C, re-serialised): the name is
# not the content, so it must still refuse.
dd="$TMP/forged"; mkdir -p "$dd/blobs/sha256"; printf 'x' > "$dd/oci-layout"
printf '{ "schemaVersion": 2, "config": {"digest": "sha256:%s", "size": 1}, "layers": [] }' "$C_OK" > "$dd/blobs/sha256/$D_OK"
tar -C "$dd" -cf "$TMP/forged.tar" oci-layout blobs; T_FORGED="$(sha256sum "$TMP/forged.tar" | cut -d' ' -f1)"
write_env "$URL_OK" "$T_FORGED" "$D_OK" "$C_OK" "$REF_OK"
run_fetch ASSET_BYTES="$TMP/forged.tar"
check "F3d a blob named D whose bytes do not hash to D (though it names C): manifest_mismatch, never loaded" \
  "[[ '$STATE' == manifest_mismatch ]] && refused_clean && ! loaded"
write_env "$URL_OK" "$T_WRONGCFG" "$D_WRONGCFG" "$C_OK" "$REF_OK"
run_fetch ASSET_BYTES="$TMP/wrongcfg.tar"
check "F3c manifest D names a config other than the pinned C: manifest_mismatch, never loaded" \
  "[[ '$STATE' == manifest_mismatch ]] && refused_clean && ! loaded"
write_env "$URL_OK" "$T_OK" "$D_OK" "$C_OK" "$REF_OK"
# F4 (M3) download failure, and curl's own argv contract
run_fetch CURL_RC=22
check "F4 download failure: verdict download_failed with curl's rc 22 recorded, nothing loaded" \
  "[[ '$STATE' == download_failed && '$STATE_RC' == 22 ]] && refused_clean && ! loaded && no_refusal"
run_fetch
check "F4b curl: -q first (no .curlrc), https-only incl. redirects, per-attempt AND total bounds (the stub admitted the argv)" \
  "no_refusal && grep -q '^curl -q ' '$TMP/calls'"
# F5 load failures
run_fetch LOAD_RC=1
check "F5 docker load fails: verdict load_failed, rc 1 recorded" "[[ '$STATE' == load_failed && '$STATE_RC' == 1 ]] && refused_clean"
run_fetch INSPECT_RC=1
check "F5b loaded but not inspectable by the local ref: load_failed" "[[ '$STATE' == load_failed ]] && refused_clean"
run_fetch INFO_RC=1
check "F5c docker never answers: docker_unavailable, never loaded" "[[ '$STATE' == docker_unavailable ]] && refused_clean && ! loaded"
# F6 (M2/M6) a third ID refuses (and is removed); C and D each pass alone (F1/F2)
run_fetch LOADED_ID="sha256:$X_ID"
check "F6 id mismatch: a third ID refuses with verdict id_mismatch" "[[ '$STATE' == id_mismatch ]] && refused_clean"
check "F6 id mismatch: the refused image is removed from the store" "grep -qx 'docker image rm -f $REF_OK' '$TMP/calls'"
run_fetch LOADED_ID="$C_OK"
check "F6b a bare hex ID without the sha256: prefix is not accepted" "[[ '$STATE' == id_mismatch ]] && refused_clean"
run_fetch LOADED_ID="sha256:$C_OK$D_OK"
check "F6c an ID that merely STARTS with C is not accepted" "[[ '$STATE' == id_mismatch ]] && refused_clean"
# F7 config_invalid: nothing is fetched on a malformed pin -- including a valid value EMBEDDED in a
# longer one (every match is whole-value, -x)
cfg_case() {  # $1 name, then write_env args
  local name="$1"; shift
  write_env "$@"; run_fetch
  check "F7 config_invalid ($name): refused before any fetch, stale hand-off removed" \
    "[[ '$STATE' == config_invalid ]] && refused_clean && ! grep -q '^curl ' '$TMP/calls'"
}
cfg_case "http URL" "${URL_OK/https:/http:}" "$T_OK" "$D_OK" "$C_OK" "$REF_OK"
cfg_case "non-github host" "https://example.com/a/b/releases/download/t/zot.oci.tar" "$T_OK" "$D_OK" "$C_OK" "$REF_OK"
cfg_case "valid URL embedded in another" "https://evil.example/?u=$URL_OK" "$T_OK" "$D_OK" "$C_OK" "$REF_OK"
cfg_case "T 63 hex" "$URL_OK" "${T_OK:0:63}" "$D_OK" "$C_OK" "$REF_OK"
cfg_case "T 65 hex" "$URL_OK" "${T_OK}a" "$D_OK" "$C_OK" "$REF_OK"
cfg_case "C uppercase" "$URL_OK" "$T_OK" "$D_OK" "$(printf '%s' "$C_OK" | tr a-f A-F)" "$REF_OK"
cfg_case "D empty" "$URL_OK" "$T_OK" "" "$C_OK" "$REF_OK"
cfg_case "local ref not localhost/" "$URL_OK" "$T_OK" "$D_OK" "$C_OK" "docker.io/library/zot:v1.0.0"
cfg_case "localhost/ ref embedded in another" "$URL_OK" "$T_OK" "$D_OK" "$C_OK" "docker.io/$REF_OK"
rm -f "$FX/zot-image.env"; run_fetch
check "F7 config_invalid (env file absent): refused, verdict recorded" "[[ '$STATE' == config_invalid ]] && refused_clean"
write_env "$URL_OK" "$T_OK" "$D_OK" "$C_OK" "$REF_OK"

echo "--- R: the rendered user_data ---"
RENDERED="$TMP/rendered.yml"
if ! command -v terraform >/dev/null 2>&1; then
  if [[ -n "${CI:-}" ]]; then echo "  FATAL: terraform is REQUIRED in CI for the render rows" >&2; exit 2; fi
  echo "  SKIP: terraform not on PATH (local dev; fails closed in CI) — R rows not run"
  R_RAN=0
else
  R_RAN=1
  bash "$DIR/registry-userdata-budget.sh" "$RENDERED" > "$TMP/budget.log" 2>&1; brc=$?
  check "R0 the budget script renders the user_data under the cap (rc 0)" "[[ $brc -eq 0 && -s '$RENDERED' ]]"
  python3 - "$RENDERED" > "$TMP/runcmd.txt" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
for i, e in enumerate(d["runcmd"]):
    body = e if isinstance(e, str) else " ".join(e)
    print("%d\t%s" % (i, body.replace("\n", "\\n")))
PY
  check "R0 the rendered runcmd parses (non-empty)" "[[ -s '$TMP/runcmd.txt' ]]"
  idx() { grep -E "$1" "$TMP/runcmd.txt" | cut -f1; }
  SINK="$(idx 'for h in ghcr\.io pkg-containers\.githubusercontent\.com')"
  FETCHI="$(idx "^[0-9]+$(printf '\t')env -i PATH=[^ ]+ HOME=/nonexistent /usr/local/bin/zot-image-fetch\\.sh >/dev/null\$")"
  DOCKERI="$(idx "^[0-9]+$(printf '\t')systemctl enable --now docker\$")"
  RUNI="$(idx 'docker run -d --name zot ')"
  check "R1 exactly one deny entry, one fetch entry, one zot launch entry" \
    "[[ \$(grep -c . <<<'$SINK') -eq 1 && \$(grep -c . <<<'$FETCHI') -eq 1 && \$(grep -c . <<<'$RUNI') -eq 1 ]]"
  check "R2 (M5) order: deny < docker enabled < fetch < zot docker run" \
    "[[ -n '$DOCKERI' && '$SINK' -lt '$DOCKERI' && '$DOCKERI' -lt '$FETCHI' && '$FETCHI' -lt '$RUNI' ]]"
  check "R3 (M7) the fetch entry is not inside any doppler run" \
    "! grep -E \"^$FETCHI$(printf '\t')\" '$TMP/runcmd.txt' | grep -q doppler"
  check "R3b the fetch invocation appears in exactly ONE runcmd entry (not also inside ZOTEOF)" \
    "[[ \$(grep -c 'zot-image-fetch\.sh' '$TMP/runcmd.txt') -eq 1 ]]"
  check "R4 exactly one docker run names zot in the whole render" \
    "[[ \$(grep -cE 'docker run [^|]*--name zot' '$RENDERED') -eq 1 ]]"
  check "R4 (M4) zot runs by \"\$ZOT_IMAGE_ID\", never a registry ref" \
    "grep -qE '^[[:space:]]+\"\\\$ZOT_IMAGE_ID\" serve /etc/zot/config\.json$' '$RENDERED' && ! grep -qE \"'[^']*zot-linux-[a-z0-9]+[:@][^']*' serve\" '$RENDERED'"
  check "R4 the launch refuses a missing/malformed ID before docker rm/run" \
    "grep -qF '[[ \"\$ZOT_IMAGE_ID\" =~ ^sha256:[0-9a-f]{64}\$ ]] ||' '$RENDERED'"
  # ghcr.io on a CODE line only in the deny and its probe (2 lines); nothing pulls from it.
  # shellcheck disable=SC2034  # read inside check()'s eval'd condition strings
  GH_CODE="$(grep -vE '^[[:space:]]*#' "$RENDERED" | grep -F 'ghcr.io')"
  check "R5 ghcr.io appears on exactly 2 code lines: the deny's host list and the heartbeat probe" \
    "[[ \$(grep -c . <<<\"\$GH_CODE\") -eq 2 ]] && grep -qF 'for h in ghcr.io pkg-containers.githubusercontent.com docker.pkg.github.com; do' <<<\"\$GH_CODE\" && grep -qF 'getent ahosts ghcr.io' <<<\"\$GH_CODE\""
  check "R5 no project-zot image ref survives anywhere in the render" "! grep -qF 'project-zot' '$RENDERED'"
  # Env file values and the P6/rule-audit parity (the bash derivation must name the SAME asset).
  envv() { sed -n "s/^[[:space:]]*$1=//p" "$RENDERED" | head -1; }
  PA="$(bash "$PREFLIGHT" --print-asset 2>/dev/null)"; parc=$?
  pa() { printf '%s\n' "$PA" | sed -n "s/^$1=//p"; }
  check "R6 preflight --print-asset reads the real .tf (rc 0)" "[[ $parc -eq 0 ]]"
  check "R6 parity: rendered ZOT_ASSET_URL == preflight --print-asset url (P6 checks the asset the host fetches)" \
    "[[ -n \"\$(envv ZOT_ASSET_URL)\" && \"\$(envv ZOT_ASSET_URL)\" == \"\$(pa url)\" ]]"
  check "R6 parity: rendered ZOT_ASSET_SHA256 == preflight sha256 (T)" \
    "[[ \"\$(envv ZOT_ASSET_SHA256)\" =~ ^[0-9a-f]{64}\$ && \"\$(envv ZOT_ASSET_SHA256)\" == \"\$(pa sha256)\" ]]"
  PIN_D="$(grep -oE '^[[:space:]]*zot_image_amd64[[:space:]]*=[[:space:]]*"[^"]*@sha256:[0-9a-f]{64}"' "$DIR/zot-registry.tf" | grep -oE '[0-9a-f]{64}')"
  check "R6 rendered ZOT_MANIFEST_DIGEST is the upstream pin D from zot_image_amd64" \
    "[[ -n '$PIN_D' && \"\$(envv ZOT_MANIFEST_DIGEST)\" == '$PIN_D' ]]"
  check "R6 rendered ZOT_CONFIG_DIGEST is 64 hex and differs from D" \
    "[[ \"\$(envv ZOT_CONFIG_DIGEST)\" =~ ^[0-9a-f]{64}\$ && \"\$(envv ZOT_CONFIG_DIGEST)\" != '$PIN_D' ]]"
  check "R6 rendered ZOT_LOCAL_REF is the builder's fully-qualified localhost/ ref" \
    "[[ \"\$(envv ZOT_LOCAL_REF)\" =~ ^localhost/soleur-mirror/zot-linux-amd64:v[0-9]+\.[0-9]+\.[0-9]+\$ ]]"
  PIN_C="$(grep -oE '^[[:space:]]*zot_config_digest_amd64[[:space:]]*=[[:space:]]*"[0-9a-f]{64}"' "$DIR/zot-registry.tf" | grep -oE '[0-9a-f]{64}')"
  check "R6 rendered ZOT_CONFIG_DIGEST is EXACTLY zot_config_digest_amd64 from the .tf (not T, not D)" \
    "[[ -n '$PIN_C' && \"\$(envv ZOT_CONFIG_DIGEST)\" == '$PIN_C' ]]"
  # The budget script renders through its OWN copy of the map; pin the REAL hcloud_server.registry map
  # to the same local for every zot key, so a swapped wire in the .tf cannot hide behind that copy.
  for kv in zot_asset_url:zot_mirror_asset_url zot_asset_sha256:zot_mirror_asset_sha256_amd64 \
            zot_manifest_digest:zot_manifest_digest zot_config_digest:zot_config_digest_amd64 zot_local_ref:zot_local_ref; do
    check "R8 the real user_data map wires ${kv%%:*} = local.${kv#*:} (exactly once)" \
      "[[ \$(grep -cE '^    ${kv%%:*}[[:space:]]*=[[:space:]]*local\.${kv#*:}[[:space:]]*$' '$DIR/zot-registry.tf') -eq 1 && \$(grep -cE '^    ${kv%%:*}[[:space:]]*=' '$DIR/zot-registry.tf') -eq 1 ]]"
  done
  # The env file's PATH is a contract between three places: write_files, the fetch, the heartbeat.
  # shellcheck disable=SC2034  # read inside check()'s eval'd condition strings
  ENV_PATHS="$(python3 - "$RENDERED" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
print("\n".join(f["path"] for f in d["write_files"] if "ZOT_ASSET_URL=" in f.get("content", "")))
PY
)"
  check "R9 exactly one write_files entry carries the zot image env, at /etc/default/zot-image" "[[ \"\$ENV_PATHS\" == /etc/default/zot-image ]]"
  check "R9 the fetch reads that path (ENV_FILE=) and the heartbeat reads it too" \
    "grep -qx 'ENV_FILE=/etc/default/zot-image' '$RAW' && [[ \$(grep -cF '/etc/default/zot-image 2>/dev/null' '$CI_YML') -eq 2 ]]"
  # R10: EXECUTE the rendered deny entry (not grep it), against a re-rooted hosts file, twice.
  python3 - "$RENDERED" > "$TMP/deny.sh" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
print([e for e in d["runcmd"] if isinstance(e, str) and "for h in ghcr.io" in e][0])
PY
  printf '127.0.0.1 localhost\n' > "$TMP/hosts"
  sed -i -e "s|/etc/hosts|$TMP/hosts|" -e "s|/etc/cloud/templates/hosts.debian.tmpl|$TMP/hosts.tmpl|" "$TMP/deny.sh"
  sh "$TMP/deny.sh"; sh "$TMP/deny.sh"
  check "R10 the executed deny maps ghcr.io, pkg-containers.githubusercontent.com and docker.pkg.github.com to 0.0.0.0 and ::, once each (idempotent)" \
    "[[ \$(grep -cxE '0\.0\.0\.0 (ghcr\.io|pkg-containers\.githubusercontent\.com|docker\.pkg\.github\.com)' '$TMP/hosts') -eq 3 && \$(grep -cxE ':: (ghcr\.io|pkg-containers\.githubusercontent\.com|docker\.pkg\.github\.com)' '$TMP/hosts') -eq 3 && \$(grep -c . '$TMP/hosts') -eq 7 ]]"
  # Per name, not only in total: a count of 3 is also met by one name written three times.
  check "R10 each of the three names is written exactly once as 0.0.0.0 and once as :: (a total of 3 cannot hide a doubled name)" \
    "[[ \$(grep -cxF '0.0.0.0 ghcr.io' '$TMP/hosts') -eq 1 && \$(grep -cxF '0.0.0.0 pkg-containers.githubusercontent.com' '$TMP/hosts') -eq 1 && \$(grep -cxF '0.0.0.0 docker.pkg.github.com' '$TMP/hosts') -eq 1 && \$(grep -cxF ':: docker.pkg.github.com' '$TMP/hosts') -eq 1 ]]"
  printf 'x\n' > "$TMP/hosts.tmpl"; sh "$TMP/deny.sh"
  check "R10 the deny also persists into the cloud hosts template when present" "[[ \$(grep -c 'ghcr.io' '$TMP/hosts.tmpl') -eq 2 ]]"
  # R11: EXECUTE the launch guard: no ID file, a malformed one, and a well-formed one.
  G_READ="$(grep -E '^[[:space:]]+ZOT_IMAGE_ID="\$\(head -1 /run/soleur/zot-image-id' "$RENDERED")"
  # shellcheck disable=SC2016  # literal \$ZOT_IMAGE_ID / \$ in the rendered line, not expansions
  G_TEST="$(grep -E '^[[:space:]]+\[\[ "\$ZOT_IMAGE_ID" =~ \^sha256:\[0-9a-f\]\{64\}\$ \]\] \|\| \{' "$RENDERED")"
  guard() { printf '%s\n%s\necho REACHED\n' "${G_READ//\/run\/soleur/$TMP/grun}" "$G_TEST" | bash 2>/dev/null; }
  rm -rf "$TMP/grun"; mkdir -p "$TMP/grun"
  check "R11 the launch guard lines are extracted (one each)" "[[ \$(grep -c . <<<\"\$G_READ\") -eq 1 && \$(grep -c . <<<\"\$G_TEST\") -eq 1 ]]"
  check "R11 no ID file: the launch refuses (never reaches docker run)" "! guard | grep -q REACHED"
  printf 'ghcr.io/project-zot/zot-linux-amd64:v2.1.22\n' > "$TMP/grun/zot-image-id"
  check "R11 a registry ref in the ID file: the launch refuses" "! guard | grep -q REACHED"
  printf 'sha256:%s\n' "$C_OK" > "$TMP/grun/zot-image-id"
  check "R11 a well-formed verified ID: the launch proceeds" "guard | grep -q REACHED"
  # shellcheck disable=SC2016  # literal \$ZOT_IMAGE_ID in the rendered line
  GL="$(grep -nE '^[[:space:]]+\[\[ "\$ZOT_IMAGE_ID" =~' "$RENDERED" | cut -d: -f1)"
  RL="$(grep -nE '^[[:space:]]+docker rm -f zot ' "$RENDERED" | cut -d: -f1)"
  check "R11 the guard runs BEFORE docker rm -f zot" "[[ -n '$GL' && -n '$RL' && '$GL' -lt '$RL' ]]"
fi

echo "--- H: heartbeat fields ---"
HRAW="$TMP/hb.raw.sh"; HB="$TMP/hb.sh"
extract_block /usr/local/bin/zot-disk-heartbeat.sh "$HRAW"
apply_rationale_strip "$HRAW" > "$HB"
# shellcheck disable=SC2016  # the \${...} are literal template tokens, not shell expansions
sed -i -e 's|\$\${|${|g' -e 's|%%{|%{|g' \
  -e 's|\${betterstack_ingest_url}|http://127.0.0.1:9/ingest|g' -e 's|\${disk_heartbeat_url}|http://127.0.0.1:9/hb|g' \
  -e 's|\${zot_pull_user}|pulluser|g' -e 's|\${zot_push_user}|pushuser|g' -e 's|\${registry_volume_id}|100000003|g' "$HB"
HBIN="$TMP/hbin"; HFX="$TMP/hfx"; mkdir -p "$HBIN" "$HFX/state"
sed -i -e "s|^PATH=.*|PATH=\"$HBIN:\$PATH\"|" \
       -e "s|/etc/default/zot-image|$HFX/zot-image.env|g" \
       -e "s|/var/lib/soleur/|$HFX/state/|g" "$HB"
check "H0 the heartbeat extracts, renders and stays valid bash" "[[ -s '$HB' ]] && bash -n '$HB'"
check "H0 the heartbeat seams landed" "grep -qF '$HFX/zot-image.env' '$HB' && grep -qF '$HFX/state/zot-image-fetch.state' '$HB'"
cat > "$HBIN/docker" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == inspect && "$2" == -f && "$*" == *"{{.Config.Image}}"* && "${!#}" == zot ]]; then
  [[ -n "${HB_INSPECT:-}" ]] && printf '%s\n' "$HB_INSPECT"; exit 0
fi
exit 0
EOF
cat > "$HBIN/getent" <<'EOF'
#!/usr/bin/env bash
[[ "$*" == "ahosts ghcr.io" ]] || { echo "getent stub: unexpected argv: $*" >&2; exit 64; }
[[ -n "${HB_GETENT:-}" ]] && printf '%b' "$HB_GETENT"
exit "${HB_GETENT_RC:-0}"
EOF
cat > "$HBIN/curl" <<'EOF'
#!/usr/bin/env bash
while [[ $# -gt 0 ]]; do [[ "$1" == --data-raw ]] && { printf '%s\n' "$2" >> "$HB_POSTED"; shift; }; shift; done
exit 0
EOF
for _s in htpasswd journalctl findmnt lsblk cryptsetup blkid; do printf '#!/usr/bin/env bash\nexit 1\n' > "$HBIN/$_s"; done
printf '#!/usr/bin/env bash\nprintf "soleur-registry\\n"\n' > "$HBIN/hostname"
chmod +x "$HBIN"/*
printf 'ZOT_ASSET_URL=%s\nZOT_ASSET_SHA256=%s\nZOT_MANIFEST_DIGEST=%s\nZOT_CONFIG_DIGEST=%s\nZOT_LOCAL_REF=%s\n' \
  "$URL_OK" "$T_OK" "$D_OK" "$C_OK" "$REF_OK" > "$HFX/zot-image.env"
SINK_ADDRS='0.0.0.0         STREAM ghcr.io\n0.0.0.0         DGRAM  \n::              STREAM \n'
# run_hb <env...> — ROW is the POSTed SOLEUR_ZOT_DISK message.
run_hb() {
  : > "$TMP/posted"
  env HB_POSTED="$TMP/posted" BETTERSTACK_LOGS_TOKEN=test-token-not-a-secret HB_GETENT="$SINK_ADDRS" "$@" \
    bash "$HB" >/dev/null 2>&1
  ROW="$(sed -n 's/^{"message":"\(SOLEUR_ZOT_DISK .*\)"}$/\1/p' "$TMP/posted" | head -1)"
}
field() { printf '%s\n' "$ROW" | sed 's/ zot_last_err=.*//' | tr ' ' '\n' | sed -n "s/^$1=//p"; }
insp() { printf 'cid 0 running false 0 2026-09-28T00:00:00Z %s' "$1"; }

printf 'ok\n' > "$HFX/state/zot-image-fetch.state"
run_hb HB_INSPECT="$(insp "sha256:$C_OK")"
check "H1 a row is emitted" "[[ -n \"\$ROW\" ]]"
check "H1 ID-ref C maps to D's first 12 hex" "[[ \"\$(field zot_image_digest)\" == '${D_OK:0:12}' ]]"
run_hb HB_INSPECT="$(insp "sha256:$D_OK")"
check "H2 ID-ref D maps to D's first 12 hex" "[[ \"\$(field zot_image_digest)\" == '${D_OK:0:12}' ]]"
run_hb HB_INSPECT="$(insp "ghcr.io/project-zot/zot-linux-amd64:v9.9.9@sha256:$D_OK")"
check "H3 a legacy repo@sha256 reference is NOT mapped (no legacy arm): unknown" "[[ \"\$(field zot_image_digest)\" == unknown ]]"
run_hb HB_INSPECT="$(insp "sha256:$X_ID")"
check "H4 a foreign image ID reports unknown" "[[ \"\$(field zot_image_digest)\" == unknown ]]"
run_hb HB_INSPECT=""
check "H4b no container reports unknown" "[[ \"\$(field zot_image_digest)\" == unknown ]]"
mv "$HFX/zot-image.env" "$HFX/zot-image.env.off"
run_hb HB_INSPECT="$(insp "sha256:$C_OK")"
check "H4c without /etc/default/zot-image even ID C reports unknown (no pin to compare to)" "[[ \"\$(field zot_image_digest)\" == unknown ]]"
mv "$HFX/zot-image.env.off" "$HFX/zot-image.env"
for v in ok fetching config_invalid download_failed sha_mismatch manifest_mismatch docker_unavailable load_failed id_mismatch record_failed; do
  printf '%s\n' "$v" > "$HFX/state/zot-image-fetch.state"; run_hb HB_INSPECT="$(insp "sha256:$C_OK")"
  check "H5 zot_image_fetch reports the verdict '$v'" "[[ \"\$(field zot_image_fetch)\" == '$v' ]]"
done
rm -f "$HFX/state/zot-image-fetch.state"; run_hb HB_INSPECT="$(insp "sha256:$C_OK")"
check "H5 an absent state file reports not_run" "[[ \"\$(field zot_image_fetch)\" == not_run ]]"
printf 'ok" x=1\n' > "$HFX/state/zot-image-fetch.state"; run_hb HB_INSPECT="$(insp "sha256:$C_OK")"
check "H5 a junk verdict (quote, space) reports unknown, not the junk" "[[ \"\$(field zot_image_fetch)\" == unknown ]]"
printf 'download_failed\n22\n' > "$HFX/state/zot-image-fetch.state"; run_hb HB_INSPECT="$(insp "sha256:$C_OK")"
check "H5 zot_image_fetch_rc ships the recorded exit code" "[[ \"\$(field zot_image_fetch_rc)\" == 22 ]]"
printf 'download_failed\n2"2\n' > "$HFX/state/zot-image-fetch.state"; run_hb HB_INSPECT="$(insp "sha256:$C_OK")"
check "H5 a junk rc line reports '-', never the junk" "[[ \"\$(field zot_image_fetch_rc)\" == - ]]"
rm -f "$HFX/state/zot-image-fetch.state"; run_hb HB_INSPECT="$(insp "sha256:$C_OK")"
check "H5 no state file: zot_image_fetch_rc is '-'" "[[ \"\$(field zot_image_fetch_rc)\" == - ]]"
printf 'ok\n' > "$HFX/state/zot-image-fetch.state"
run_hb HB_INSPECT="$(insp "sha256:$C_OK")"
check "H6 sinkhole only (0.0.0.0 / ::) -> ghcr_blocked=1" "[[ \"\$(field ghcr_blocked)\" == 1 ]]"
run_hb HB_INSPECT="$(insp "sha256:$C_OK")" HB_GETENT='140.82.121.34   STREAM ghcr.io\n'
check "H6 a routable address -> ghcr_blocked=0" "[[ \"\$(field ghcr_blocked)\" == 0 ]]"
run_hb HB_INSPECT="$(insp "sha256:$C_OK")" HB_GETENT='0.0.0.0         STREAM ghcr.io\n140.82.121.34   STREAM \n'
check "H6 sinkhole PLUS a routable address -> ghcr_blocked=0 (the deny is not in effect)" "[[ \"\$(field ghcr_blocked)\" == 0 ]]"
run_hb HB_INSPECT="$(insp "sha256:$C_OK")" HB_GETENT='' HB_GETENT_RC=2
check "H6 unresolvable -> ghcr_blocked=unknown (not reported as the deny)" "[[ \"\$(field ghcr_blocked)\" == unknown ]]"
run_hb HB_INSPECT="$(insp "sha256:$C_OK")" HB_GETENT='2606:50c0:8000::154 STREAM ghcr.io\n'
check "H6 a routable IPv6 address containing '::' -> ghcr_blocked=0 (whole-value match)" "[[ \"\$(field ghcr_blocked)\" == 0 ]]"
run_hb HB_INSPECT="$(insp "sha256:$C_OK")"
check "H7 the four fields sit before host= and zot_last_err stays LAST" \
  "[[ \"\$ROW\" =~ \\ zot_image_digest=[^\\ ]+\\ zot_image_fetch=[^\\ ]+\\ zot_image_fetch_rc=[^\\ ]+\\ ghcr_blocked=[^\\ ]+\\ .*\\ host=[^\\ ]+\\ zot_last_err=[^=]*\$ ]]"


# Anti-vacuity floor — printf + exit, never through fail() (ADR-193). F+H rows always run; the R
# rows only where terraform is present. Both are the MEASURED counts (F+H 68 without terraform;
# R 33 = 101 - 68 with it; 32 before #9390 added the per-name R10 row), so deleting any one row
# fires the floor.
FLOOR_FH=68; FLOOR_R=33
N=$((PASS + FAIL))
if (( N < FLOOR_FH + (R_RAN ? FLOOR_R : 0) )); then
  printf '[FATAL] only %d assertions ran (floor %d) -- the suite was gutted\n' "$N" "$((FLOOR_FH + (R_RAN ? FLOOR_R : 0)))" >&2
  exit 1
fi
echo "=== zot-image-fetch: $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
