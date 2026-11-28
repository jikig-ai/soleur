# shellcheck shell=bash
# SOURCED FRAGMENT of tests/scripts/test-argv-bearer-sweep.sh -- NOT independently runnable.
# =====================================================================================
# STAGE S4 (argv-bearer sweep S4, ADR-280): the push-triggered production-class files. The deploy-webhook callers (the HMAC
# signature plus the Cloudflare Access pair), the Supabase, GitHub App, Resend and Hetzner bearer sites, the `openssl dgst -hmac`
# keys that sit on the same calls, one `x-access-token:` push URL and the two sites S3 held back leave the process command line.
# Population and manifests are DERIVED from the tree; the representative real step bodies and scripts are EXECUTED.
#
#   GUARD 1  no production file puts an HMAC key or a credential header on an argument list: the HMAC census (set identity
#            against an explicit allow-list), the library-user manifest judged structurally, and the inline-wrapper copies
#            judged by the S2 parity audit (hm_audit, now over every copy: cutover 19 plus the S4 workflow and script copies).
#   GUARD 2  a refused credential reaches the SAME verdict class as the old failure (red step, soft verdict, warning or degraded
#            proceed) or the honest existing class of the sink table: never `down`, never `inngest_down`, never `unreachable`.
#            The real step body is extracted from the YAML and run under a recording curl that READS `--config -`, with each
#            credential empty, unset and hostile, and with python3 absent at one HMAC site per form (library, inline).
# All credentials are synthesized. A fixture credential is built from pieces, never a contiguous token literal.
# =====================================================================================
S4="$TMPD/s4"; assert_fixture_dir "$S4"; mkdir -p "$S4/shim" "$S4/real" "$S4/real-nopy" "$S4/shimreal" "$S4/rows" "$S4/bodies"
cat > "$S4/shim/curl" <<'S4SHIM'
#!/usr/bin/env bash
# Recording curl for the S4 stage. Synthesized. Models what the S4 sites need and nothing more:
#  - `--config -` is READ (stdin -> <n>.stdin) unless SHIM_NOSTDIN=1 (the blind-shim control);
#  - `-o <path>`: a /tmp path is remapped into the row (the real step bodies write /tmp/...), /dev/null is dropped;
#  - a `-d/--data <literal>` body and a `--data-binary @<file>` body are recorded to <n>.body (the HMAC oracle's input);
#  - the answer is by profile: generic (SHIM_CODE/SHIM_BODY), webhook (by /hooks/ path; a status read AFTER a POST answers
#    SHIM_STATUS_BODY_POST when set, and /health answers SHIM_HEALTH_BODY), rls (the Supabase Management API);
#  - exit SHIM_RC (default 0).
d="${CALLS_DIR:?}"
n=$(( $(find "$d" -name '*.argv' | wc -l) + 1 ))
printf '%s\0' "$@" > "$d/$n.argv"
out=""; wfmt=""; cfg=0; data=""; url=""; hasdata=0
args=("$@"); i=0
while (( i < ${#args[@]} )); do
  a="${args[i]}"; nx="${args[i+1]-}"
  case "$a" in
    -o|--output) out="$nx"; i=$((i + 1)) ;;
    -w|--write-out) wfmt="$nx"; i=$((i + 1)) ;;
    --config) [[ "$nx" == - ]] && cfg=1; i=$((i + 1)) ;;
    -d|--data|--data-raw) data="$nx"; hasdata=1; i=$((i + 1)) ;;
    --data-binary) if [[ "$nx" == @* ]]; then cp "${nx#@}" "$d/$n.body" 2>/dev/null; else data="$nx"; hasdata=1; fi; i=$((i + 1)) ;;
    --url) url="$nx"; i=$((i + 1)) ;;
    -X|--request|--max-time|--noproxy|-H|--header) i=$((i + 1)) ;;
    http://*|https://*) url="$a" ;;
  esac
  i=$((i + 1))
done
(( hasdata )) && printf '%s' "$data" > "$d/$n.body"
if (( cfg )) && [[ "${SHIM_NOSTDIN:-}" != 1 ]]; then cat > "$d/$n.stdin"; fi
code="${SHIM_CODE:-200}"; body="${SHIM_BODY-}"
case "${SHIM_PROFILE:-generic}" in
  webhook)
    body=""
    case "$url" in
      */hooks/deploy-status|*/hooks/infra-config-status) body="${SHIM_STATUS_BODY-}"; [[ -e "$d/posted" ]] && body="${SHIM_STATUS_BODY_POST-$body}" ;;
      */hooks/inngest-liveness) body="${SHIM_LIVE_BODY-}" ;;
      */hooks/deploy|*/hooks/infra-config) code="${SHIM_POST_CODE:-202}"; : > "$d/posted" ;;
      */health) body="${SHIM_HEALTH_BODY-}" ;;
    esac ;;
  rls)
    body='[]'; code=201
    case "$url" in
      */advisors/security) body='{"lints":[]}'; code=200 ;;
      */database/query)
        case "$data" in
          *violations*) body='[{"violations":0}]'; code=200 ;;
          *pg_default_acl*) body='[{"n":0}]'; code=200 ;;
          *"set local role postgres"*) body='[{"n":1}]'; code=200 ;;
          *"set local role anon"*) body='{"message":"ERROR: 42501: permission denied"}'; code=200 ;;
        esac ;;
      */v1/projects/*) body='{"name":"soleur-inngest-prd"}'; code=200 ;;
    esac ;;
esac
if [[ -n "$out" ]]; then
  case "$out" in
    /dev/null) : ;;
    "${RUNNER_TEMP:-/nonexistent}"/*) printf '%s' "$body" > "$out" ;;
    /tmp/*) mkdir -p "$d/tmp"; printf '%s' "$body" > "$d/tmp/${out##*/}" ;;
    *) printf '%s' "$body" > "$out" ;;
  esac
else
  printf '%s' "$body"
fi
if [[ -n "$wfmt" ]]; then fmt="${wfmt//%\{http_code\}/$code}"; printf '%b' "$fmt"; fi
exit "${SHIM_RC:-0}"
S4SHIM
sed -i "1s|.*|#!${BASH_BIN}|" "$S4/shim/curl"
# `sleep` is a no-op (the poll loops would otherwise spend minutes), `doppler` answers by secret NAME from D_<NAME> (set = value, may be
# empty; unset = the read fails), and every other tool a step may call is a real symlink.
printf '#!%s\nexit 0\n' "$BASH_BIN" > "$S4/shim/sleep"
cat > "$S4/shim/doppler" <<'S4DOP'
#!/usr/bin/env bash
var="D_${3:-}"
if [[ "${1:-}" == secrets && "${2:-}" == get && -n "${!var+x}" ]]; then printf '%s' "${!var}"; exit 0; fi
exit 1
S4DOP
sed -i "1s|.*|#!${BASH_BIN}|" "$S4/shim/doppler"
chmod +x "$S4/shim/curl" "$S4/shim/sleep" "$S4/shim/doppler"
# The real-curl wrapper for the transport-failure rows: every http(s) URL goes to a closed loopback port and the REAL curl runs.
cat > "$S4/shimreal/curl" <<'S4REAL'
#!/usr/bin/env bash
args=(); for a in "$@"; do case "$a" in http://*|https://*) args+=("http://127.0.0.1:9/x") ;; *) args+=("$a") ;; esac; done
exec "@REAL_CURL@" "${args[@]}"
S4REAL
sed -i "1s|.*|#!${BASH_BIN}|; s|@REAL_CURL@|${REAL_CURL}|" "$S4/shimreal/curl"
cp "$S4/shim/sleep" "$S4/shim/doppler" "$S4/shimreal/"
chmod +x "$S4/shimreal/curl" "$S4/shimreal/sleep" "$S4/shimreal/doppler"
for t in bash cat date grep sed tr awk head tail jq mktemp rm mkdir env dirname basename cut wc sort tee find seq uniq ls cp mv cmp od base64 sha256sum diff xargs expr id uname paste readlink touch stat true false printf tar gzip chmod; do
  p="$(type -P "$t" || true)"; [[ -n "$p" ]] && ln -s "$p" "$S4/real/$t"
done
for t in "$S4"/real/*; do ln -s "$(readlink "$t")" "$S4/real-nopy/$(basename "$t")"; done
# python3 and openssl are RECORDING WRAPPERS, not symlinks: each logs its argv to $TOOLS_DIR/<tool>-<n>.argv and execs the real binary, so the
# HMAC rows can assert that the credential is on NEITHER tool's argument list (the key rides python3's ENVIRONMENT; a plain symlink would
# leave a regression that moves it onto python3's argv invisible). python3 is absent from real-nopy on purpose (the signature cannot be computed).
cat > "$S4/toolwrap.tmpl" <<'S4WRAP'
#!/usr/bin/env bash
d="${TOOLS_DIR:-}"
if [[ -n "$d" && -d "$d" ]]; then
  n=$(( $(find "$d" -name '@TOOL@-*.argv' | wc -l) + 1 ))
  printf '%s\0' "$@" > "$d/@TOOL@-$n.argv"
fi
exec "@REAL@" "$@"
S4WRAP
for t in python3 openssl; do
  p="$(type -P "$t" || true)"; [[ -n "$p" ]] || fatal "stage S4: python3, jq and openssl are required"
  sed "1s|.*|#!${BASH_BIN}|; s|@TOOL@|$t|g; s|@REAL@|$p|" "$S4/toolwrap.tmpl" > "$S4/real/$t"; chmod +x "$S4/real/$t"
done
cp "$S4/real/openssl" "$S4/real-nopy/openssl"
[[ -x "$S4/real/python3" && -e "$S4/real/jq" && -x "$S4/real/openssl" && ! -e "$S4/real-nopy/python3" ]] || fatal "stage S4: python3, jq and openssl are required"

S4_CANARY="S4CANARYsecret0123"
S4_HEX32="$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')"
S4_HEX64="$(od -An -N32 -tx1 /dev/urandom | tr -d ' \n')"
S4_KEY="synth-s4-webhook-key-$(od -An -N6 -tx1 /dev/urandom | tr -d ' \n')"
S4_CFID="${S4_HEX32}.access"                      # the shape of a Cloudflare Access service-token id
S4_CFSEC="$S4_HEX64"                              # and of its secret
S4_N=0; S4_RC=0; S4_ROW=""; S4_CWD=""; S4_SHIM="$S4/shim"; : > "$S4/dropped.log"
S4_FLAGS=(--noprofile --norc -e)                  # the runner's default step shell: `bash -e {0}`
S4_ARGS=()                                        # arguments after the script (the bump script takes flags)
S4_REFUSAL_RUNS=0                                 # refusal runs whose every captured stream was searched for the planted canary

# s4_run <label> <script> <realdir> [NAME=value ...]: the script under `env -i` with the recording curl first on PATH.
# An argument holding @ROW@ gets the row directory substituted (a status file path the script reads and writes).
s4_run() {
  local label="$1" body="$2" realdir="$3"; shift 3
  S4_N=$((S4_N + 1)); local r="$S4/rows/$S4_N-${label//[^A-Za-z0-9._-]/_}"
  assert_fixture_dir "$r"; mkdir -p "$r/calls" "$r/rt" "$r/tools"
  : > "$r/gho"; : > "$r/genv"; : > "$r/summary"
  set -- "${@//@ROW@/$r}"
  # The step's environment is what the YAML declares, not what this harness would like it to be: when the body was extracted from a workflow
  # step (s4_body wrote <body>.decl: the workflow-level, job-level and step-level `env:` names, plus every name an earlier step of the job
  # writes to $GITHUB_ENV), an injected NAME=value whose NAME nobody declares is DROPPED (and logged), so a step that reads a variable its
  # YAML no longer declares sees it unset and the row goes red. Harness plumbing (SHIM_*, D_* for the doppler stub) and runner-provided
  # names (GITHUB_*, RUNNER_*) and the runner's ambient LC_ALL (the locale rows) are not step env; WEB_HOST_SSH is exported by the cf-tunnel-ssh-bridge composite and HCLOUD_TOKEN by the infra-credentials composite, not by the workflow file.
  if [[ -r "$body.decl" ]]; then
    local -a kept=(); local a nm
    for a in "$@"; do
      nm="${a%%=*}"
      case "$nm" in SHIM_*|D_*|GITHUB_*|RUNNER_*|WEB_HOST_SSH|HCLOUD_TOKEN|LC_ALL) kept+=("$a"); continue ;; esac
      if grep -qxF -- "$nm" "$body.decl"; then kept+=("$a"); else printf '%s %s\n' "$label" "$nm" >> "$S4/dropped.log"; fi
    done
    set -- ${kept[@]+"${kept[@]}"}
  fi
  # #9294 G1: the webhook trio reaches a step as the Tier-B loader composite's env export, not as a doppler read. A row that sets the
  # trio's D_<NAME> (the doppler stub's answer) therefore ALSO sets <NAME> itself, with the same value (set-but-empty stays empty,
  # no D_<NAME> stays unset), so the existing rows keep driving the same credential states through the new source.
  # The D_<NAME> twin is then DROPPED, so the doppler shim answers none of the trio: a step (or a script it calls) that read the
  # trio from a store again would find nothing and the row would go red, instead of passing on the stub's answer.
  local -a trio_env=() rest=(); local ta
  for ta in "$@"; do
    case "${ta%%=*}" in D_WEBHOOK_DEPLOY_SECRET|D_CF_ACCESS_CLIENT_ID|D_CF_ACCESS_CLIENT_SECRET) trio_env+=("${ta#D_}") ;; *) rest+=("$ta") ;; esac
  done
  set -- ${rest[@]+"${rest[@]}"} ${trio_env[@]+"${trio_env[@]}"}
  S4_RC=0
  ( cd "${S4_CWD:-$REPO_ROOT}" && env -i PATH="$S4_SHIM:$realdir" HOME="$r" TMPDIR="$r" RUNNER_TEMP="$r/rt" GITHUB_OUTPUT="$r/gho" GITHUB_ENV="$r/genv" \
      GITHUB_STEP_SUMMARY="$r/summary" GITHUB_WORKSPACE="$REPO_ROOT" CALLS_DIR="$r/calls" TOOLS_DIR="$r/tools" "$@" \
      "$BASH_BIN" "${S4_FLAGS[@]}" "$body" ${S4_ARGS[@]+"${S4_ARGS[@]}"} < /dev/null ) > "$r/stdout" 2> "$r/stderr" || S4_RC=$?
  S4_ROW="$r"
}
# s4_body <yml> <step id|name prefix> <out> [<from> <to>]...: the step's run text, /tmp/ moved under $RUNNER_TEMP (the runner's
# fresh /tmp, never this host's), and any named edit applied; an edit that did not land is FATAL (a mutation that does not
# land reports the baseline, which is indistinguishable from a pass).
# s4_body_try returns 1 (never aborts) when the step cannot be extracted or an edit does not land: a CONTROL that mutates a line of a real step uses it, so a real
# step that later changes the line fails ITS OWN control row instead of aborting the battery before the real rows around it have run.
declare -A S4_BODY_SRC=()   # <built body path> -> "<repo-relative workflow>|<step selector>" (the population rows ask which step a body was built from)
s4_body_try() {
  local f="$1" sel="$2" out="$3"; shift 3
  assert_fixture_dir "$out"
  S4_BODY_SRC["$out"]="${f#"$REPO_ROOT"/}|$sel"
  s3_body "$f" "$sel" > "$out.raw" || return 1
  python3 -I -c '
import sys
t = open(sys.argv[1]).read()
pairs = sys.argv[3:]
for i in range(0, len(pairs), 2):
    if pairs[i] not in t:
        sys.exit(3)
    t = t.replace(pairs[i], pairs[i + 1])
t = t.replace("/tmp/", "${RUNNER_TEMP}/")
open(sys.argv[2], "w").write(t)' "$out.raw" "$out" "$@" || return 1
  python3 -I -c "$s4_decl_py" "$f" "$sel" > "$out.decl" || return 1
}
s4_body() { s4_body_try "$@" || fatal "S4 could not build the step '$2' of $1 (it could not be extracted, an edit did not land or its environment could not be derived)"; }
# The names a step's environment DECLARES: the workflow-level `env:`, the job-level `env:` of its job, its own `env:`, and every NAME an earlier-or-later
# step of the job writes with `echo NAME=... >> $GITHUB_ENV` (a composite action's step has only its own). The same step match as s3_step_py.
s4_decl_py='
import sys, yaml, re
f, sel = sys.argv[1], sys.argv[2]
d = yaml.safe_load(open(f))
names = set()
def add(m):
    if isinstance(m, dict): names.update(str(k) for k in m)
add(d.get("env"))
groups = []
if isinstance(d.get("runs"), dict): groups.append((None, d["runs"].get("steps") or []))
else:
    for j in (d.get("jobs") or {}).values():
        if isinstance(j, dict): groups.append((j, j.get("steps") or []))
for job, steps in groups:
    for s in steps:
        if isinstance(s, dict) and isinstance(s.get("run"), str) and (s.get("id") == sel or str(s.get("name", "")).startswith(sel)):
            if job: add(job.get("env"))
            add(s.get("env"))
            for o in steps:
                if isinstance(o, dict) and isinstance(o.get("run"), str):
                    for line in o["run"].split("\n"):
                        m = re.match(r"^\s*echo\s+[\"\x27]?([A-Za-z_][A-Za-z0-9_]*)=.*>>\s*[\"\x27]?\$\{?GITHUB_ENV", line)
                        if m: names.add(m.group(1))
            print("\n".join(sorted(names))); sys.exit(0)
sys.exit(3)
'
s4_jobenv() { python3 -I -c 'import sys,yaml
d = yaml.safe_load(open(sys.argv[1]))
for k, v in ((d["jobs"][sys.argv[2]].get("env")) or {}).items():
    print("%s=%s" % (k, v))' "$1" "$2"; }
# Facts about the row just run.
s4_ncalls() { find "$S4_ROW/calls" -name '*.argv' 2>/dev/null | wc -l | tr -d ' '; }
s4_markers() { grep -c '^SOLEUR_CREDENTIAL_REFUSED script=' < <(cat "$S4_ROW/stdout" "$S4_ROW/stderr") || true; }
s4_said() { grep -qF -- "$1" < <(cat "$S4_ROW/stdout" "$S4_ROW/stderr"); }                  # a literal line fragment on stdout or stderr
s4_gho_has() { grep -qxF -- "$1" "$S4_ROW/gho"; }
s4_genv_has() { grep -qxF -- "$1" "$S4_ROW/genv"; }
# The planted canary appears in no captured stream (`::add-mask::` is the runner's own masking command and carries the value by design).
s4_canary_clean() { ! grep -qaF -- "$S4_CANARY" < <(grep -rahv '^::add-mask::' "$S4_ROW" 2>/dev/null); }
s4_argv_has() { local f; for f in "$S4_ROW"/calls/*.argv; do [[ -e "$f" ]] || continue; grep -qaF -- "$1" "$f" && return 0; done; return 1; }
# The recorded argv of the two tools besides curl (python3, openssl; the wrappers write $TOOLS_DIR/<tool>-<n>.argv): <tool> <needle>.
s4_tool_argv_has() { local f; for f in "$S4_ROW"/tools/"$1"-*.argv; do [[ -e "$f" ]] || continue; grep -qaF -- "$2" "$f" && return 0; done; return 1; }
s4_tool_ran() { local f; for f in "$S4_ROW"/tools/"$1"-*.argv; do [[ -e "$f" ]] && return 0; done; return 1; }
# The needle is on NO recorded argv of curl, python3 or openssl.
s4_nowhere_on_argv() { ! s4_argv_has "$1" && ! s4_tool_argv_has python3 "$1" && ! s4_tool_argv_has openssl "$1"; }
# s4_calls_ok <headers-per-call>: every recorded call read its stdin config (a blind shim records none), carries exactly that many bare
# `header = "..."` directives and nothing else, and has the confinement prefix (`--disable`, `--noproxy '*'`) and `--config -`.
s4_calls_ok() {
  local want="$1" f c ok=1 cnt=0 w
  local -a av
  for f in "$S4_ROW"/calls/*.argv; do
    [[ -e "$f" ]] || continue
    cnt=$((cnt + 1)); c="${f%.argv}"
    [[ -r "$c.stdin" ]] || { ok=0; continue; }
    [[ "$(grep -c '^header = "[^"\\]*"$' "$c.stdin")" == "$want" && "$(grep -vc '^header = "[^"\\]*"$' "$c.stdin")" == 0 ]] || ok=0
    mapfile -d '' av < "$f"
    [[ "${av[0]:-}" == --disable && "${av[1]:-}" == --noproxy && "${av[2]:-}" == '*' ]] || ok=0
    w=0; for ((i = 0; i + 1 < ${#av[@]}; i++)); do [[ "${av[i]}" == --config && "${av[i+1]}" == - ]] && w=1; done
    (( w )) || ok=0
  done
  (( cnt > 0 && ok ))
}
s4_stdin_line() { sed -n "${2}p" "$S4_ROW/calls/$1.stdin" 2>/dev/null; }  # <call> <line>
s4_oracle() { "$REAL_OSSL" dgst -sha256 -hmac "$1" < "$2" | sed 's/.*= //'; }  # <key> <file>

# ---- instrument controls (the stage aborts with FATAL when the instrument is blind) ----
# C1: the shim READS `--config -`: a directive piped to it is recorded, the body of a --data-binary @file is recorded, /tmp is remapped.
printf '%s\n' 'set -e' \
  'printf "{\"k\":1}" > "$RUNNER_TEMP/payload"' \
  'curl --disable --noproxy "*" -s -o /tmp/s4-ctl-out -w "%{http_code}" --max-time 5 -X POST --data-binary @"$RUNNER_TEMP/payload" --config - https://deploy.invalid/hooks/deploy < <(printf "header = \"X-Test: ctl\"\n")' > "$S4/ctl1.sh"
s4_run ctl1 "$S4/ctl1.sh" "$S4/real" SHIM_PROFILE=webhook
if [[ "$S4_RC" == 0 && "$(s4_ncalls)" == 1 && "$(s4_stdin_line 1 1)" == 'header = "X-Test: ctl"' && "$(cat "$S4_ROW/calls/1.body" 2>/dev/null)" == '{"k":1}' \
      && -e "$S4_ROW/calls/tmp/s4-ctl-out" && "$(cat "$S4_ROW/stdout")" == 202 ]] && s4_calls_ok 1; then
  row "S4 control: the recording curl reads --config -, records the --data-binary @file body, remaps /tmp and answers the webhook profile (202)" ok
else row "S4 control: the recording curl is blind" fail "rc=$S4_RC calls=$(s4_ncalls)"; fatal "S4 control C1: the recording curl does not read --config -"; fi
# C2: a BLIND curl (it never reads its stdin) must be judged RED by the very predicate the rows use.
s4_run ctl2 "$S4/ctl1.sh" "$S4/real" SHIM_PROFILE=webhook SHIM_NOSTDIN=1
if [[ "$(s4_ncalls)" == 1 ]] && ! s4_calls_ok 1; then row "S4 control: a curl that ignores --config - is judged RED by the credential-reaches-stdin predicate (the harness cannot be satisfied by a blind shim)" ok
else row "S4 control: a blind curl is not judged red" fail "calls=$(s4_ncalls)"; fi
# C3: a credential on curl's argv is seen by the argv predicate, and a hostile value planted in a stream is seen by the canary predicate.
printf '%s\n' 'curl -s -o /dev/null -H "X-Signature-256: sha256=$K" --config - https://deploy.invalid/x < <(printf "header = \"X: y\"\n")' 'echo "$K" >&2' > "$S4/ctl3.sh"
s4_run ctl3 "$S4/ctl3.sh" "$S4/real" "K=$S4_CANARY" SHIM_PROFILE=webhook
if s4_argv_has "$S4_CANARY" && ! s4_canary_clean; then row "S4 control: a credential on a recorded argv and a credential echoed to stderr are both seen (argv predicate and negative canary are not blind)" ok
else row "S4 control: the argv or canary predicate is blind" fail "argv=$(s4_argv_has "$S4_CANARY" && echo seen || echo missed)"; fi
# C4: the real-curl oracle behind the transport-failure rows: a closed port is exit 7 and `000`, so `|| echo 000` makes `000000`.
printf '%s\n' 'c=$(curl --disable --noproxy "*" -s -o /dev/null -w "%{http_code}" --max-time 5 https://deploy.invalid/x); echo "rc=$? first=$c"' \
  'c2=$(curl --disable --noproxy "*" -s -o /dev/null -w "%{http_code}" --max-time 5 https://deploy.invalid/x || echo "000"); echo "second=$c2"' > "$S4/ctl4.sh"
S4_SHIM="$S4/shimreal"; S4_FLAGS=(--noprofile --norc); s4_run ctl4 "$S4/ctl4.sh" "$S4/real"; S4_SHIM="$S4/shim"; S4_FLAGS=(--noprofile --norc -e)
if s4_said 'rc=7 first=000' && s4_said 'second=000000'; then row "S4 control: real curl against a closed port exits 7 and prints 000, and the sites' \`|| echo \"000\"\` makes the documented 000000" ok
else row "S4 control: the closed-port oracle drifted" fail "$(tr '\n' ' ' < "$S4_ROW/stdout")"; fi
# C5: the HMAC oracle is the OTHER implementation (the real openssl), and the library signs the same bytes.
printf '%s' '{"command":"synthetic"}' > "$S4/bodies/oracle-body"
S4_ORA_WANT="$(s4_oracle "$S4_KEY" "$S4/bodies/oracle-body")"
S4_ORA_GOT="$(env -i PATH="$S4/real" K="$S4_KEY" "$BASH_BIN" -c 'source "'"$REPO_ROOT"'/scripts/lib/bearer-curl.sh"; bc_hmac_sha256_hex K < "'"$S4"'/bodies/oracle-body"')"
[[ -n "$S4_ORA_WANT" && "$S4_ORA_GOT" == "$S4_ORA_WANT" ]] && row "S4 control: the library's bc_hmac_sha256_hex equals the independent openssl dgst -hmac digest over the same bytes" ok || row "S4 control: the HMAC oracle disagrees with the library" fail "lens=${#S4_ORA_WANT}/${#S4_ORA_GOT}"
# C6: the tool wrappers record argv and the predicate that reads them sees a credential on python3's or openssl's argument list (B5): a wrapper
# that logged nothing, or a predicate that never read the log, would make every HMAC row's "key on no tool argv" clause vacuous.
printf '%s\n' 'python3 -I -c "pass" "$K"' 'openssl dgst -sha256 -hmac "$K" < /dev/null > /dev/null' 'openssl version > /dev/null' > "$S4/ctl6.sh"
s4_run ctl6 "$S4/ctl6.sh" "$S4/real" "K=$S4_CANARY"
if s4_tool_ran python3 && s4_tool_ran openssl && s4_tool_argv_has python3 "$S4_CANARY" && s4_tool_argv_has openssl "$S4_CANARY" && ! s4_nowhere_on_argv "$S4_CANARY" \
   && s4_nowhere_on_argv "no-such-credential"; then
  row "S4 control: the python3 and openssl recording wrappers log argv, and the nowhere-on-argv predicate sees a credential on either tool's argument list (and not an absent one)" ok
else row "S4 control: the python3 or openssl wrapper is blind" fail "py=$(s4_tool_ran python3 && echo ran || echo none) ossl=$(s4_tool_ran openssl && echo ran || echo none)"; fatal "S4 control C6: the tool wrappers are blind"; fi
echo "=== stage S4: instrument controls done ==="

# =====================================================================================
# GUARD 1 (a): the HMAC census. Every tracked non-test, non-documentation file that signs with `openssl dgst ... -hmac <key>` puts
# the KEY on openssl's argv; since #9757 converted the last two (the registry-probe and doublefire-probe arms of the cutover script) NO
# production file does, and the allow-list is EMPTY. The census is DERIVED: every tracked file
# naming `-hmac` or `-macopt` is read STATEMENT by statement (backslash continuation lines joined first), and a statement that runs
# `openssl` with `-hmac` or `-macopt` is a hit WHATEVER the subcommand (`dgst`, `sha256`, `mac`, ...) or the line layout. The hits, minus
# Markdown, *.test.sh, tests/, fixtures, knowledge-base/, comment-only statements and the lint's own docstring, are compared to the
# allow-list by SET IDENTITY (path AND hit count, so a second argv HMAC in an allowed file is an unclassified member, and a deleted
# allow-list row while the file still signs is an unclassified member too). The derivation is itself fed a must-FAIL fixture for each
# spelling it claims to see (`openssl sha256 -hmac`, a continued `dgst`, `-macopt`, `openssl mac`) and must-PASS controls beside them.
# =====================================================================================
S4_HMAC_ALLOW=""
S4_HMAC_MD_ALLOW=""
s4_hmac_filter() { # stdin: grep -n lines (path:line:text) -> "path:count" per file after the exclusions
  awk -F: '{
    p = $1; t = substr($0, length($1) + length($2) + 3)
    if (p ~ /\.md$/ || p ~ /\.test\.(sh|ts)$/ || p ~ /^tests\// || p ~ /\/tests\// || p ~ /(^|\/)fixtures\// || p ~ /^knowledge-base\// || p == "scripts/lint-shell-trace-credential-refusal.py") next
    if (t ~ /^[[:space:]]*#/) next
    c[p]++
  } END { for (p in c) printf "%s:%d\n", p, c[p] }' | sort
}
s4_census_verdict() { # <census> <allow> -> prints "unclassified=... stale=..." and returns 0 when the two sets are identical
  local un st
  un="$(comm -23 <(printf '%s\n' "$1" | grep . | sort) <(printf '%s\n' "$2" | grep . | sort) | paste -sd, -)"
  st="$(comm -13 <(printf '%s\n' "$1" | grep . | sort) <(printf '%s\n' "$2" | grep . | sort) | paste -sd, -)"
  printf 'unclassified=%s stale=%s' "$un" "$st"
  [[ -z "$un" && -z "$st" ]]
}
# s4_hmac_scan <root>: stdin = relative file names; prints `path:line:statement` for every `openssl` statement (continuation lines joined; `line`
# is the statement's first physical line) that carries a `-hmac` or `-macopt` token, i.e. the HMAC key (or a key option) on openssl's argv.
s4_hmac_py='
import sys, re, os
root = sys.argv[1]
for rel in sys.stdin.read().split("\n"):
    if not rel: continue
    try: lines = open(os.path.join(root, rel), errors="replace").read().split("\n")
    except OSError: continue
    i = 0
    while i < len(lines):
        first = i; buf = lines[i]
        while buf.rstrip().endswith("\\") and i + 1 < len(lines):
            i += 1; buf = buf.rstrip()[:-1] + " " + lines[i].strip()
        if re.search(r"(^|[^A-Za-z0-9_.-])openssl([^A-Za-z0-9_-]|$)", buf) and re.search(r"(^|[\s\"\x27])-(hmac|macopt)([\s=\"\x27]|$)", buf):
            print("%s:%d:%s" % (rel, first + 1, buf))
        i += 1
'
s4_hmac_scan() { python3 -I -c "$s4_hmac_py" "$1"; }
S4_HMAC_RAW="$(cd "$REPO_ROOT" && git grep -lIE -e '-hmac' -e '-macopt' | s4_hmac_scan "$REPO_ROOT")"
S4_HMAC_CENSUS="$(printf '%s\n' "$S4_HMAC_RAW" | s4_hmac_filter)"
S4_HMAC_RAW_N="$(printf '%s\n' "$S4_HMAC_RAW" | grep -c . || true)"
S4_CEN_OUT="$(s4_census_verdict "$S4_HMAC_CENSUS" "$S4_HMAC_ALLOW")"; S4_CEN_RC=$?
if [[ "$S4_CEN_RC" == 0 && -z "$S4_HMAC_CENSUS" && -z "$S4_HMAC_ALLOW" ]]; then
  row "S4 HMAC census: the derived set of production files with an argv openssl -hmac equals the (empty) allow-list exactly: no tracked production file puts the HMAC key on openssl's argv" ok
else row "S4 HMAC census: the derived set differs from the allow-list" fail "$S4_CEN_OUT census='${S4_HMAC_CENSUS//$'\n'/,}'"; fi
# The documentation set, asserted separately: no agent-executed Markdown file teaches the argv form any more (an empty set).
S4_MD_SET="$(cd "$REPO_ROOT" && git grep -lIE -e '-hmac' -e '-macopt' -- '*.md' ':!knowledge-base' | s4_hmac_scan "$REPO_ROOT" | cut -d: -f1 | sort -u)"
if [[ "$S4_MD_SET" == "$S4_HMAC_MD_ALLOW" && -z "$S4_HMAC_MD_ALLOW" ]]; then row "S4 HMAC census: no Markdown file teaches the argv form (the documentation exception set is empty)" ok
else row "S4 HMAC census: a Markdown file teaches the argv openssl -hmac form again" fail "set='${S4_MD_SET//$'\n'/,}'"; fi
# Anti-vacuity floor: with the allow-list empty the production census is EMPTY by design, so "empty equals empty" proves nothing by itself. The
# derivation must still SEE what it excludes: the test-owned oracle statements (`openssl dgst -hmac` run with synthetic keys in *.test.sh and
# tests/) are scanned, counted and filtered out. A population that quietly emptied (a renamed pattern, a missing git) reads 0 here and reds.
# BOTH operands are literals on the lines IMMEDIATELY above the `if`.
S4_CENSUS_HITS="$(printf '%s\n' "$S4_HMAC_CENSUS" | awk -F: 'NF > 1 {n += $NF} END {print n + 0}')"
S4_CENSUS_SEEN="$(printf '%s\n' "$S4_HMAC_RAW" | awk -F: '$1 ~ /\.test\.(sh|ts)$/ || $1 ~ /^tests\// {n++} END {print n + 0}')"
S4_CENSUS_SEEN_FLOOR=10
if [[ "$S4_CENSUS_HITS" == 0 && "$S4_CENSUS_SEEN" -ge "$S4_CENSUS_SEEN_FLOOR" && "$S4_HMAC_RAW_N" -gt "$S4_CENSUS_SEEN" ]]; then row "S4 HMAC census: the derivation is not vacuous (0 production lines; it still sees $S4_CENSUS_SEEN test-owned oracle statements among $S4_HMAC_RAW_N tracked matches and excludes them; anti-vacuity floor $S4_CENSUS_SEEN_FLOOR)" ok
else row "S4 HMAC census: the derived population is empty (anti-vacuity floor)" fail "hits=$S4_CENSUS_HITS seen=$S4_CENSUS_SEEN raw=$S4_HMAC_RAW_N floor=$S4_CENSUS_SEEN_FLOOR"; fi
# The structural D4 predicate: none of the 15 S4 files carries `openssl dgst -hmac` in non-comment text (the census says so for the set;
# this names each file so a restored site is reported at its file).
S4_FILES=".github/actions/dispatch-web-redeploy/track.sh .github/actions/mint-infra-app-token/action.yml .github/scripts/bump-inngest-bootstrap-pin.sh
 .github/workflows/apply-deploy-pipeline-fix.yml .github/workflows/apply-github-infra.yml .github/workflows/apply-inngest-rls.yml
 .github/workflows/deploy-inngest-image.yml .github/workflows/restart-inngest-server.yml .github/workflows/scheduled-inngest-health.yml
 .github/workflows/web-platform-release.yml .github/workflows/workspaces-luks-cutover.yml apps/web-platform/infra/infra-config-verify.sh
 apps/web-platform/infra/push-infra-config.sh apps/web-platform/infra/scripts/verify-tunnel-ingress-origin.sh apps/web-platform/scripts/github-app-key-status.sh"
# s4_file_has_argv_hmac <repo-relative file>: a NON-comment statement of the file runs openssl with -hmac or -macopt (the scanner above, so a continued or non-dgst spelling counts).
s4_file_has_argv_hmac() { printf '%s\n' "$1" | s4_hmac_scan "$REPO_ROOT" | awk -F: '{ t = substr($0, length($1) + length($2) + 3); if (t !~ /^[[:space:]]*#/) n++ } END { exit n ? 0 : 1 }'; }
S4_D4_BAD=""; S4_NFILES=0
for f in $S4_FILES; do
  S4_NFILES=$((S4_NFILES + 1))
  [[ -f "$REPO_ROOT/$f" ]] || { S4_D4_BAD+=" $f(missing)"; continue; }
  s4_file_has_argv_hmac "$f" && S4_D4_BAD+=" $f"
done
[[ -z "$S4_D4_BAD" && "$S4_NFILES" == 15 ]] && row "S4 structure: none of the 15 S4 files carries openssl dgst -hmac in non-comment text (the key is never on openssl's argv)" ok || row "S4 structure: an S4 file signs with the key on openssl's argv" fail "$S4_D4_BAD n=$S4_NFILES"
# CONTROL for the wrapper itself (a verdict helper that is a pipe of python3 and awk answers "clean" when python3 crashes, the root is wrong or the awk slice is off by one, so every
# file above would pass for the wrong reason): it must see a SYNTHESIZED positive (no production file is a known positive any more: the cutover script was the last one),
# a synthesized continued `-hmac` spelling and a comment-only mention must NOT count, and converted files (the cutover script included) must be clean.
S4_HF="$S4/hmacfile"; assert_fixture_dir "$S4_HF"; mkdir -p "$S4_HF"
printf '%s\n' 'S=$(printf "" | openssl dgst -sha256 \' '    -hmac "$K")' > "$S4_HF/continued.sh"
printf '%s\n' '# S=$(printf "" | openssl dgst -sha256 -hmac "$K")' > "$S4_HF/comment.sh"
printf '%s\n' 'S=$(printf "" | openssl dgst -sha256 -hmac "$K" | sed s/x/y/)' > "$S4_HF/positive.sh"
S4_HF_BAD=""
s4_file_has_argv_hmac scripts/cutover-inngest.sh && S4_HF_BAD+=" converted-cutover-seen"
s4_file_has_argv_hmac apps/web-platform/infra/push-infra-config.sh && S4_HF_BAD+=" converted-file-seen"
S4_HF_ROOT_SAVE="$REPO_ROOT"; REPO_ROOT="$S4_HF"
s4_file_has_argv_hmac positive.sh || S4_HF_BAD+=" positive-not-seen"
s4_file_has_argv_hmac continued.sh || S4_HF_BAD+=" continued-not-seen"
s4_file_has_argv_hmac comment.sh && S4_HF_BAD+=" comment-seen"
s4_file_has_argv_hmac no-such-file.sh && S4_HF_BAD+=" missing-file-seen"
REPO_ROOT="$S4_HF_ROOT_SAVE"
[[ -z "$S4_HF_BAD" ]] && row "S4 structure control: the per-file argv-HMAC helper sees a synthesized positive and a synthesized backslash-continued -hmac, and does not see a comment-only mention, a missing file or a converted file (the cutover script included)" ok || row "S4 structure control: the per-file argv-HMAC helper is blind or over-matches" fail "$S4_HF_BAD"

# Harness rows for the census: a synthesized tree whose only HMAC is allowed MUST PASS; every other tree MUST FAIL. Both go through
# the SAME s4_hmac_filter / s4_census_verdict the live census uses (a pattern nothing ever fed a known positive and a known negative
# is not a control).
S4_CEN="$S4/cen"; assert_fixture_dir "$S4_CEN"; mkdir -p "$S4_CEN"
s4_cen_tree() { # <name> <variant>
  local t="$S4_CEN/$1"; assert_fixture_dir "$t"; mkdir -p "$t/scripts" "$t/docs" "$t/tests" "$t/knowledge-base" "$t/x"
  printf '%s\n' 'SIG=$(printf "" | openssl dgst -sha256 -hmac "$K" | sed s/x/y/)' '    SIG=$(printf "" | openssl dgst -sha256 -hmac "$K" | sed s/x/y/)' > "$t/scripts/synthetic-signer.sh"
  printf '%s\n' '# SIG=$(printf "" | openssl dgst -sha256 -hmac "$K")' > "$t/x/commented.sh"
  printf '%s\n' 'openssl dgst -sha256 -hmac "$K"' > "$t/docs/teaches.md"
  printf '%s\n' 'openssl dgst -sha256 -hmac "$K"' > "$t/x/a.test.sh"
  printf '%s\n' 'openssl dgst -sha256 -hmac "$K"' > "$t/tests/b.sh"
  printf '%s\n' 'openssl dgst -sha256 -hmac "$K"' > "$t/knowledge-base/c.txt"
  # NOT hits (the scanner must not over-match): a signer with a private KEY FILE, the word in a message, and a statement that is not openssl's.
  printf '%s\n' 'openssl dgst -sha256 -sign "$PEM" -binary' 'echo "pass -hmac to the other tool"' 'python3 -I -c "import hmac" -hmac' > "$t/x/benign.sh"
  case "$2" in
    allowed) ;;
    extra) printf '%s\n' 'S=$(openssl dgst -sha256 -hmac "$K")' > "$t/x/new-production.sh" ;;
    second) printf '%s\n' 'S=$(openssl dgst -sha256 -hmac "$K")' >> "$t/scripts/synthetic-signer.sh" ;;
    sha256) printf '%s\n' 'S=$(printf "" | openssl sha256 -hmac "$K")' > "$t/x/new-sha256.sh" ;;
    multiline) printf '%s\n' 'S=$(printf "" | openssl dgst -sha256 \' '    -hmac "$K")' > "$t/x/new-multiline.sh" ;;
    macopt) printf '%s\n' 'S=$(printf "" | openssl dgst -sha256 -mac HMAC -macopt "key:$K")' > "$t/x/new-macopt.sh" ;;
    mac) printf '%s\n' 'S=$(printf "" | openssl mac -digest SHA256 -macopt "hexkey:$K" HMAC)' > "$t/x/new-mac.sh" ;;
    abspath) printf '%s\n' 'S=$(printf "" | /usr/bin/openssl sha256 -hmac "$K")' > "$t/x/new-abspath.sh" ;;
  esac
  (cd "$t" && grep -rlIE -e '-hmac' -e '-macopt' . | sed 's|^\./||' | s4_hmac_scan "$t" | s4_hmac_filter)
}
# The synthesized tree carries its OWN allow-list (the live one is empty since #9757): the harness exercises the allow-list MECHANISM, not the repo.
S4_CT_ALLOW="scripts/synthetic-signer.sh:2"
S4_CT_OK="$(s4_cen_tree ok allowed)"; s4_census_verdict "$S4_CT_OK" "$S4_CT_ALLOW" > /dev/null; S4_CT_OK_RC=$?
S4_CT_EX="$(s4_cen_tree extra extra)"; s4_census_verdict "$S4_CT_EX" "$S4_CT_ALLOW" > /dev/null; S4_CT_EX_RC=$?
S4_CT_2="$(s4_cen_tree second second)"; s4_census_verdict "$S4_CT_2" "$S4_CT_ALLOW" > /dev/null; S4_CT_2_RC=$?
S4_CT_SHAPE_BAD=""
for cv in sha256 multiline macopt mac abspath; do
  S4_CT_V="$(s4_cen_tree "v-$cv" "$cv")"
  if s4_census_verdict "$S4_CT_V" "$S4_CT_ALLOW" > /dev/null; then S4_CT_SHAPE_BAD+=" $cv"; fi
  [[ "$S4_CT_V" == *"x/new-$cv.sh:1"* ]] || S4_CT_SHAPE_BAD+=" $cv(unnamed:$S4_CT_V)"
done
s4_census_verdict "$S4_CT_OK" "" > /dev/null; S4_CT_DEL_RC=$?
[[ "$S4_CT_OK_RC" == 0 && "$S4_CT_OK" == "scripts/synthetic-signer.sh:2" ]] && row "S4 HMAC census control: a synthesized tree whose only HMAC is allowed (plus a comment-only line, Markdown, test, tests/ and knowledge-base/ copies, an openssl -sign statement and the word -hmac in a message) is GREEN" ok || row "S4 HMAC census control: the allowed tree is not green" fail "got='$S4_CT_OK' rc=$S4_CT_OK_RC"
[[ "$S4_CT_EX_RC" != 0 ]] && row "S4 HMAC census control: an extra unlisted production file with an argv HMAC is RED (unclassified member)" ok || row "S4 HMAC census control: an extra member is accepted" fail "got='$S4_CT_EX'"
[[ -z "$S4_CT_SHAPE_BAD" ]] && row "S4 HMAC census control: each spelling the derivation claims to see is RED when an unlisted production file uses it (openssl sha256 -hmac, a dgst whose -hmac is on a backslash-continuation line, -mac HMAC -macopt, openssl mac -macopt, an absolute-path openssl) and is named at its file" ok || row "S4 HMAC census control: a key-on-argv spelling is accepted by the census" fail "$S4_CT_SHAPE_BAD"
[[ "$S4_CT_2_RC" != 0 ]] && row "S4 HMAC census control: a SECOND argv HMAC after a compliant first, in an allowed file, is RED (the census compares per-file counts, not 'at least one clean')" ok || row "S4 HMAC census control: a second member in an allowed file is accepted" fail "got='$S4_CT_2'"
[[ "$S4_CT_DEL_RC" != 0 ]] && row "S4 HMAC census control: deleting the allow-list row while the file still signs is RED (the allow-list cannot shrink silently)" ok || row "S4 HMAC census control: a deleted allow-list row is accepted" fail ""
# The live census, fed the cutover script with ONE probe arm put back on `openssl dgst -hmac` (the mutants of stage S2-A part 2): each is RED against the
# empty allow-list and is named at its file with exactly one hit. The scan root is the mutant directory, so the same s4_hmac_scan / filter / verdict the live
# census uses judge it.
S4_RV_BAD=""
for rv in revert1 revert2; do
  S4_RV_CEN="$(printf '%s\n' "hm-mut-$rv.sh" | s4_hmac_scan "$BKDIR" | s4_hmac_filter)"
  s4_census_verdict "$S4_RV_CEN" "$S4_HMAC_ALLOW" > /dev/null && S4_RV_BAD+=" $rv(accepted)"
  [[ "$S4_RV_CEN" == "hm-mut-$rv.sh:1" ]] || S4_RV_BAD+=" $rv(census='$S4_RV_CEN')"
done
[[ -z "$S4_RV_BAD" ]] && row "S4 HMAC census mutation: either probe arm of the cutover script reverted to openssl dgst -hmac is RED against the empty allow-list, with exactly one hit named" ok || row "S4 HMAC census mutation: a reverted probe arm is accepted by the census" fail "$S4_RV_BAD"
# The inline copies of the canonical snippet are a DERIVED population too: every tracked non-test file holding it is in this explicit set.
S4_INLINE_FILES="$(printf '%s\n' .github/workflows/deploy-inngest-image.yml .github/workflows/web-platform-release.yml apps/web-platform/infra/infra-config-verify.sh apps/web-platform/infra/scripts/verify-tunnel-ingress-origin.sh scripts/cutover-inngest.sh | sort)"
S4_INLINE_DERIVED="$(cd "$REPO_ROOT" && git grep -lF 'HMAC_KEY="$WEBHOOK_SECRET" python3 -I -c' -- . ':!tests' ':!knowledge-base' ':!*.test.sh' ':!*.md' | sort)"
if [[ "$S4_INLINE_DERIVED" == "$S4_INLINE_FILES" ]]; then row "S4 parity population: the files holding the canonical inline HMAC snippet are exactly the cutover script and the four S4 inline files (derived by git grep, never counted; Markdown is judged by the next row)" ok
else row "S4 parity population: a file holds the canonical inline HMAC snippet that no audit judges" fail "derived='${S4_INLINE_DERIVED//$'\n'/,}'"; fi
# The agent-executed Markdown teaches the SAME snippet (the argv `openssl -hmac` form it used to teach is gone, see the census above): the set of Markdown files that
# carry it is exactly these two, and each carries the canonical snippet BYTE FOR BYTE (a doc that drifted would teach an operator a divergent signer).
S4_MD_CANON_FILES="$(printf '%s\n' plugins/soleur/skills/postmerge/references/deploy-status-debugging.md plugins/soleur/skills/ship/SKILL.md)"
S4_MD_CANON_DERIVED="$(cd "$REPO_ROOT" && git grep -lF 'HMAC_KEY="$WEBHOOK_SECRET" python3 -I -c' -- '*.md' ':!knowledge-base' | sort)"
S4_MD_CANON_BAD=""
for f in $S4_MD_CANON_DERIVED; do [[ "$(grep -cF -- "$HM_CANON" "$REPO_ROOT/$f" || true)" -ge 1 ]] || S4_MD_CANON_BAD+=" $f"; done
if [[ "$S4_MD_CANON_DERIVED" == "$S4_MD_CANON_FILES" && -z "$S4_MD_CANON_BAD" ]]; then row "S4 parity population: the Markdown files that teach the canonical inline HMAC snippet are exactly ship/SKILL.md and postmerge/references/deploy-status-debugging.md, and each carries it byte for byte" ok
else row "S4 parity population: a Markdown file teaches a divergent or unlisted HMAC snippet" fail "derived='${S4_MD_CANON_DERIVED//$'\n'/,}' divergent:$S4_MD_CANON_BAD"; fi

# =====================================================================================
# GUARD 1 (c): the library-user manifest. S3 derives the YAML population (S3_POP: steps and composites that source the library);
# S4 adds the SCRIPTS that source it on a step's behalf (a script file invoked by a `run:` or a terraform provisioner). The set is
# derived from the tree and compared to an explicit manifest; each script is judged structurally (the library sourced before its
# first bc_* use; no credential header literal inside a bc_curl statement; no stderr discard on one; no branch on rc == 2; the marker
# names the file).
# =====================================================================================
S4_SCRIPT_MANIFEST="$(printf '%s\n' .github/actions/dispatch-web-redeploy/track.sh apps/web-platform/infra/push-infra-config.sh apps/web-platform/scripts/github-app-key-status.sh scripts/probe-github-app-mint.sh apps/web-platform/infra/git-data-wipe.sh scripts/inngest-link-flip.sh scripts/inngest-key-rotate.sh scripts/key-rotate.sh scripts/followthroughs/git-data-rehearsal-evidence.sh | sort)"
S4_SCRIPT_POP="$(cd "$REPO_ROOT" && git grep -lE '^[[:space:]]*(source|\.)[[:space:]].*scripts/lib/bearer-curl\.sh' -- '*.sh' ':!*.test.sh' ':!tests' ':!scripts/lib' | sort)"
S4_SU="$(comm -23 <(printf '%s\n' "$S4_SCRIPT_POP" | grep .) <(printf '%s\n' "$S4_SCRIPT_MANIFEST"))"
S4_SS="$(comm -13 <(printf '%s\n' "$S4_SCRIPT_POP" | grep .) <(printf '%s\n' "$S4_SCRIPT_MANIFEST"))"
if [[ -z "$S4_SU" && -z "$S4_SS" && -n "$S4_SCRIPT_POP" ]]; then row "S4 population: every script that sources the library is in the manifest and every manifest member still does ($(printf '%s\n' "$S4_SCRIPT_POP" | grep -c .) scripts)" ok
else row "S4 population: the derived script set differs from the manifest" fail "unclassified='${S4_SU//$'\n'/,}' stale='${S4_SS//$'\n'/,}'"; fi
# The S4 additions to the YAML population (S3_MANIFEST now holds them; the S3 structure rows already judge every member).
S4_YML_NEW=".github/actions/mint-infra-app-token/action.yml .github/workflows/apply-deploy-pipeline-fix.yml .github/workflows/apply-github-infra.yml .github/workflows/apply-inngest-rls.yml .github/workflows/restart-inngest-server.yml .github/workflows/scheduled-inngest-health.yml"
S4_YML_MISS=""; for f in $S4_YML_NEW; do grep -qxF -- "$f" <<<"$S3_POP" || S4_YML_MISS+=" $f"; done
[[ -z "$S4_YML_MISS" ]] && row "S4 population: the five newly converted YAML files and the converted inngest-health probe are all in the derived library-user set ($(printf '%s\n' "$S3_POP" | grep -c .) YAML members in all, judged by the S3 structure rows)" ok || row "S4 population: a converted YAML file is not a derived library user" fail "$S4_YML_MISS"
# Anti-vacuity floor on the two derived populations (BOTH operands are literals on the lines IMMEDIATELY above the `if`).
S4_POP_FLOOR=25
S4_POP_N=$(( $(printf '%s\n' "$S3_POP" | grep -c .) + $(printf '%s\n' "$S4_SCRIPT_POP" | grep -c .) ))
if [[ "$S4_POP_N" -ge "$S4_POP_FLOOR" ]]; then row "S4 population: the derived library-user population holds $S4_POP_N members (anti-vacuity floor $S4_POP_FLOOR)" ok
else row "S4 population: the derived library-user population is below its anti-vacuity floor" fail "n=$S4_POP_N floor=$S4_POP_FLOOR"; fi
# Structural rows over the scripts. Statement-level: continuation lines are joined (the same shape s3_statements_py uses for YAML).
s4_script_stm() { sed -e ':a' -e '/\\$/N; s/\\\n[[:space:]]*/ /; ta' "$1"; }
S4_SRC_BAD=""; S4_ARGV_BAD=""; S4_STDERR_BAD=""; S4_RC2_BAD=""; S4_NAME_BAD=""; S4_SCALLS=0; S4_HMAC_SCRIPT_BAD=""
for f in $S4_SCRIPT_POP; do
  stm="$(s4_script_stm "$REPO_ROOT/$f")"
  first_use="$(printf '%s\n' "$stm" | awk '$0 !~ /^[[:space:]]*#/ && $0 ~ /(^|[^_A-Za-z])bc_(curl|ok_var|refuse|hmac_sha256_hex)[ "$]/ && $0 !~ /^[[:space:]]*(source|\.)[[:space:]]/ {print NR; exit}')"
  first_src="$(printf '%s\n' "$stm" | awk '$0 ~ /^[[:space:]]*(source|\.)[[:space:]]/ && $0 ~ /scripts\/lib\/bearer-curl\.sh/ {print NR; exit}')"
  [[ -n "$first_src" && -n "$first_use" && "$first_src" -le "$first_use" ]] || S4_SRC_BAD+=" $f"
  S4_SCALLS=$((S4_SCALLS + $(printf '%s\n' "$stm" | grep -cE '(^|[^_A-Za-z])bc_curl [A-Za-z]' || true)))
  while IFS= read -r l; do s3_d2_hit "$l" && S4_ARGV_BAD+=" $f"; done < <(printf '%s\n' "$stm" | grep -E '(^|[^_A-Za-z])bc_curl ' || true)
  while IFS= read -r l; do s3_d3_hit "$l" && S4_STDERR_BAD+=" $f"; done < <(printf '%s\n' "$stm" | grep -E '(^|[^_A-Za-z])bc_curl ' | sed -E 's/.*(bc_curl .*)/\1/; s/ \|\| .*//; s/ \| .*//' || true)
  while IFS= read -r l; do s3_d5_hit "$l" && S4_RC2_BAD+=" $f"; done < <(printf '%s\n' "$stm" | grep -v '^[[:space:]]*#' || true)
  want_name="$(basename "$f" .sh)"
  while IFS= read -r nm; do [[ "$nm" == "$want_name" || "$nm" == "$(basename "$f")" ]] || S4_NAME_BAD+=" $f:$nm"; done \
    < <(printf '%s\n' "$stm" | grep -v '^[[:space:]]*#' | grep -oE '(^|[^_A-Za-z])bc_(curl|refuse)[ ]+[A-Za-z0-9._-]+' | awk '{print $NF}' | sort -u || true)
  s4_file_has_argv_hmac "$f" && S4_HMAC_SCRIPT_BAD+=" $f"
done
[[ -z "$S4_SRC_BAD" ]] && row "S4 structure: every script sources the library before its first bc_* call" ok || row "S4 structure: a script uses the library before it sources it" fail "$S4_SRC_BAD"
[[ -z "$S4_ARGV_BAD" ]] && row "S4 structure: no bc_curl statement in a script repeats a credential header on its own argument list" ok || row "S4 structure: a script's bc_curl carries -H credential" fail "$S4_ARGV_BAD"
[[ -z "$S4_STDERR_BAD" ]] && row "S4 structure: no bc_curl statement in a script discards stderr (the marker stays visible)" ok || row "S4 structure: 2>/dev/null on a script's bc_curl" fail "$S4_STDERR_BAD"
[[ -z "$S4_RC2_BAD" ]] && row "S4 structure: no script branches on rc == 2 (the marker is the discriminator)" ok || row "S4 structure: a script branches on rc 2" fail "$S4_RC2_BAD"
[[ -z "$S4_NAME_BAD" ]] && row "S4 structure: every bc_curl / bc_refuse in a script names its own file in the marker" ok || row "S4 structure: a script's marker names another file" fail "$S4_NAME_BAD"
[[ -z "$S4_HMAC_SCRIPT_BAD" ]] && row "S4 structure: no library-user script computes an HMAC with the key on openssl's argv" ok || row "S4 structure: openssl -hmac in a library-user script" fail "$S4_HMAC_SCRIPT_BAD"
# The floor is the realized count (13 bc_curl statements: track.sh x2, push-infra-config x1, github-app-key-status x1, probe-github-app-mint x1, git-data-wipe x2 (the read and the write wrapper), git-data-rehearsal-evidence x1, inngest-link-flip x2 (flip_webhook's POST and GET arms), inngest-key-rotate x1 (kr_hz, the Hetzner read), key-rotate x2 (the deploy-status GET and the vector-restart POST)). BOTH operands are literals above the `if`.
S4_SCALLS_FLOOR=13
if [[ "$S4_SCALLS" -ge "$S4_SCALLS_FLOOR" ]]; then row "S4 structure: the library-user scripts hold $S4_SCALLS bc_curl statements (anti-vacuity floor $S4_SCALLS_FLOOR)" ok
else row "S4 structure: the script population floor" fail "only $S4_SCALLS bc_curl statements derived (floor $S4_SCALLS_FLOOR)"; fi
# The lint's SCRIPT-CONSUMER derivation (scripts/lint-workflow-local-action-checkout.py, SCRIPT CONSUMERS) runs its `git ls-files` arm on the REAL tree only here
# and in one fixture of its suite; the fixtures of the suite have no `.git`. A pathspec that stopped matching (`*.sh` -> `*.shx`) leaves that suite green, the lint at
# rc 0 and the line at `0 derived, 0 step(s)`, so every script consumer would silently stop being checked for a checkout, `pull_request_target` and an untrusted ref.
# The lint runs on the live tree and BOTH numbers of its `script-consumers:` line are held to floors (the REALIZED counts: 23 derived scripts, of which
# 23 are run by a workflow step; a floor below the realized count lets one script consumer drop out of the derivation without a red row), and the arm must be the git one.
S4_LINT_OUT="$(cd "$REPO_ROOT" && python3 scripts/lint-workflow-local-action-checkout.py 2>&1)"; S4_LINT_RC=$?
S4_LINT_N="$(sed -nE 's/^lint-workflow-local-action-checkout: script-consumers: ([0-9]+) derived \(git ls-files\), ([0-9]+) step\(s\) run one$/\1/p' <<<"$S4_LINT_OUT")"
S4_LINT_M="$(sed -nE 's/^lint-workflow-local-action-checkout: script-consumers: ([0-9]+) derived \(git ls-files\), ([0-9]+) step\(s\) run one$/\2/p' <<<"$S4_LINT_OUT")"
S4_LINT_N_FLOOR=23
S4_LINT_M_FLOOR=23
if [[ "$S4_LINT_RC" == 0 && "$S4_LINT_N" =~ ^[0-9]+$ && "$S4_LINT_M" =~ ^[0-9]+$ && "$S4_LINT_N" -ge "$S4_LINT_N_FLOOR" && "$S4_LINT_M" -ge "$S4_LINT_M_FLOOR" ]]; then
  row "S4 lint: the checkout lint run on the real tree is clean and its script-consumer derivation (git ls-files arm) finds $S4_LINT_N scripts and $S4_LINT_M steps that run one (floors $S4_LINT_N_FLOOR and $S4_LINT_M_FLOOR)" ok
else row "S4 lint: the script-consumer derivation of the checkout lint is empty, below its floors, or not on the git arm" fail "rc=$S4_LINT_RC derived='${S4_LINT_N:-<unparsed>}' steps='${S4_LINT_M:-<unparsed>}' floors=$S4_LINT_N_FLOOR/$S4_LINT_M_FLOOR last='$(tail -1 <<<"$S4_LINT_OUT")'"; fi
# The predicates that judge the scripts are the S3 predicates; the script statement joiner is a control of its own: a continued call is one statement.
S4_JOIN="$(printf '%s\n' 'x=$(bc_curl a "A:B:C" -- -sS \' '  -H "Authorization: z" \' '  url)' | sed -e ':a' -e '/\\$/N; s/\\\n[[:space:]]*/ /; ta')"
[[ "$(printf '%s\n' "$S4_JOIN" | grep -c .)" == 1 ]] && s3_d2_hit "$S4_JOIN" && row "S4 structure control: the script statement joiner folds a continued bc_curl into ONE statement and the D2 predicate then sees the credential header on it" ok || row "S4 structure control: the statement joiner or the D2 predicate is blind" fail "joined='$S4_JOIN'"

# track.sh VOCABULARY (mutation 8): an unusable credential reuses the EXISTING credential-absent verdict; no new verdict word.
S4_TRACK=".github/actions/dispatch-web-redeploy/track.sh"
S4_TRACK_WORDS="$(grep -ohE 'verdict=redeploy_[a-z_]+' "$REPO_ROOT/$S4_TRACK" | sort -u)"
S4_TRACK_WANT="$(printf '%s\n' verdict=redeploy_baseline_unreadable verdict=redeploy_credential_absent verdict=redeploy_dispatch_rejected verdict=redeploy_peer_fanout_degraded verdict=redeploy_status_unreadable verdict=redeploy_tag_unresolved verdict=redeploy_terminal_failure verdict=redeploy_timeout verdict=redeploy_tool_absent | sort)"
if [[ "$S4_TRACK_WORDS" == "$S4_TRACK_WANT" ]]; then row "S4 track.sh vocabulary: the verdict words are exactly the nine the consumers (apply-web-platform-infra, git-data-cutover, the runbook) grep for; the refusal reuses redeploy_credential_absent" ok
else row "S4 track.sh vocabulary: a verdict word was added or removed" fail "got='${S4_TRACK_WORDS//$'\n'/,}'"; fi
echo "=== stage S4: Guard 1 census, populations and structure done ==="

# =====================================================================================
# GUARD 1 (d): the inline-wrapper copies, judged by the S2 PARITY AUDIT (hm_audit above, which reads any indentation). S4 adds eight
# copies of the canonical python3 HMAC snippet to the 19 of the cutover script: web-platform-release.yml 4 and deploy-inngest-image.yml
# 2 (workflow steps, 10-space YAML indentation, signing through the inline `_sig_curl`), infra-config-verify.sh 1 and
# verify-tunnel-ingress-origin.sh 1 (scripts at column 0 that print their own header directives; both sign a status GET).
# The cutover script holds all 19 copies (no -hmac operand is left). The inline wrappers are the exception ADR-280 allows only where a
# pinned property of the job or its suite rules out sourcing a repo file; this audit is the mechanical bound on that exception.
# =====================================================================================
S4_HM_SPEC=".github/workflows/web-platform-release.yml:4: .github/workflows/deploy-inngest-image.yml:2: apps/web-platform/infra/infra-config-verify.sh:1:empty apps/web-platform/infra/scripts/verify-tunnel-ingress-origin.sh:1:empty"
S4_HM_TOTAL=0; S4_HM_ALLBAD=""
for spec in $S4_HM_SPEC; do
  IFS=: read -r hf hn hd <<< "$spec"
  hm_audit "$REPO_ROOT/$hf" "$hd"
  S4_HM_TOTAL=$((S4_HM_TOTAL + HM_NCOPY))
  [[ "$HM_NCOPY" == "$hn" ]] || S4_HM_ALLBAD+=" $hf(copies=$HM_NCOPY want=$hn)"
  for ((hi = 1; hi <= HM_NCOPY; hi++)); do
    if [[ " $HM_BAD " != *" $hi "* ]]; then row "S4 inline HMAC copy $(basename "$hf")#$hi equals the canonical snippet, keeps the SIG=\$(printf <body> | ...) || SIG=\"\" shape and signs the body its own request carries" ok
    else row "S4 inline HMAC copy $(basename "$hf")#$hi equals the canonical snippet, keeps the SIG=\$(printf <body> | ...) || SIG=\"\" shape and signs the body its own request carries" fail "differs from the canonical string, lost its fallback, or signs the wrong body (bad:$HM_BAD)"; fi
  done
done
hm_audit "$CUT"; S4_HM_CUT="$HM_NCOPY"; S4_HM_HELD="$HM_NOLD"
# BOTH operands are literals on the lines IMMEDIATELY above the `if`: 19 cutover copies + 8 S4 copies, and no -hmac operand left in the cutover script.
S4_HM_COPIES_WANT=27
if [[ $((S4_HM_CUT + S4_HM_TOTAL)) -eq "$S4_HM_COPIES_WANT" && -z "$S4_HM_ALLBAD" && "$S4_HM_HELD" == 0 ]]; then
  row "S4 parity audit: $S4_HM_COPIES_WANT converted copies in all (19 cutover + 8 inline: release 4, deploy-inngest-image 2, infra-config-verify 1, verify-tunnel 1), no -hmac operand left in the cutover script" ok
else row "S4 parity audit: the converted-copy count moved or a -hmac operand is back" fail "cutover=$S4_HM_CUT inline=$S4_HM_TOTAL want=$S4_HM_COPIES_WANT hmac=$S4_HM_HELD bad:$S4_HM_ALLBAD"; fi
# Mutants of the parity audit on the S4 copies: ONE byte (-I dropped) in ONE inline copy is caught as exactly that copy, touching exactly that line.
for spec in $S4_HM_SPEC; do
  IFS=: read -r hf hn hd <<< "$spec"
  for ((hi = 1; hi <= hn; hi++)); do
    mf="$BKDIR/hm-s4-$(basename "$hf")-$hi"; assert_fixture_dir "$mf"
    nth_replace "$REPO_ROOT/$hf" "$mf" "$HM_PFX" 'HMAC_KEY="$WEBHOOK_SECRET" python3 -c' "$hi" || fatal "S4 parity mutation $hf#$hi did not land"
    hm_audit "$mf" "$hd"; hm_ln="$(hm_nth_line "$hi" "$REPO_ROOT/$hf" 'HMAC_KEY="$WEBHOOK_SECRET" python3')"
    if [[ "$HM_BAD" == " $hi" && "$(hm_touched "$REPO_ROOT/$hf" "$mf")" == "${hm_ln}c${hm_ln}" ]]; then row "mutation: dropping -I from the inline copy $(basename "$hf")#$hi alone (line $hm_ln only) is caught as exactly that copy" ok
    else row "mutation: dropping -I from the inline copy $(basename "$hf")#$hi alone (line $hm_ln only) is caught as exactly that copy" fail "bad:$HM_BAD touched:$(hm_touched "$REPO_ROOT/$hf" "$mf") want:${hm_ln}c${hm_ln}"; fi
  done
done
# The fail-safe fallback and the signed body are per-site facets too: the empty-key abort (a mute `set -e` exit) and a POST signed over nothing.
mf="$BKDIR/hm-s4-nofallback"; assert_fixture_dir "$mf"
{ mapfile -t _ml < "$REPO_ROOT/.github/workflows/web-platform-release.yml"; _mi=0
  for _mn in "${!_ml[@]}"; do [[ "${_ml[_mn]}" == *'HMAC_KEY="$WEBHOOK_SECRET" python3'* ]] || continue; _mi=$((_mi + 1)); [[ "$_mi" == 2 ]] && _ml[_mn]="${_ml[_mn]% || *}"; done
  printf '%s\n' "${_ml[@]}"; } > "$mf"
hm_audit "$mf" ""
if [[ "$HM_BAD" == " 2" ]]; then row "mutation: dropping the || SIG=\"\" fallback from the web-platform-release Deploy-via-webhook copy is caught as exactly that copy (an empty key would abort the step mute)" ok
else row "mutation: dropping the || SIG=\"\" fallback from the web-platform-release Deploy-via-webhook copy is caught as exactly that copy" fail "bad:$HM_BAD"; fi
mf="$BKDIR/hm-s4-wrongbody"; assert_fixture_dir "$mf"
python3 -I -c '
import sys
t = open(sys.argv[1]).read()
old = "SIG=$(printf '"'%s'"' \"$PAYLOAD\" | HMAC_KEY="
new = "SIG=$(printf '"''"' | HMAC_KEY="
if old not in t: sys.exit(3)
open(sys.argv[2], "w").write(t.replace(old, new, 1))' "$REPO_ROOT/.github/workflows/web-platform-release.yml" "$mf" || fatal "S4 parity mutation wrongbody did not land"
hm_audit "$mf" ""
if [[ "$HM_BAD" == " 2" ]]; then row "mutation: signing the empty body in the web-platform-release Deploy-via-webhook copy, whose request carries -d \"\$PAYLOAD\", is caught as exactly that copy (a POST signed over nothing is a 401)" ok
else row "mutation: signing the empty body in the Deploy-via-webhook copy is caught" fail "bad:$HM_BAD"; fi

# --- the inline guard functions are pinned to the canonical text, byte for byte (plan D4) ---
# The pinned populations are DERIVED from the tree (`git grep -l` of the definitions, minus knowledge-base/, tests and *.test.sh), never listed:
#   `_bearer_ok`: EVERY tracked file that defines it (the cutover script is the canonical source and is the comparison base, so it is out of the
#                 pinned set) must carry a definition byte-equal to BEARER_FN, and the pinned definition count equals the count `git grep` finds
#                 (a definition spelled in a form the pin's reader does not see would otherwise be unpinned and uncounted);
#   `_sig_curl` and `_bearer_curl`: the files that define either must be EXACTLY the explicit set below (set identity: a new inline wrapper in
#                 another file is an unclassified member, a vanished one a stale row), and each wrapper must equal the cutover script's after only the
#                 marker's script name and the cutover's own `--max-time 60` are normalized.
S4_GUARD_FILES=".github/workflows/web-platform-release.yml .github/workflows/deploy-inngest-image.yml .github/workflows/workspaces-luks-cutover.yml apps/web-platform/infra/scripts/verify-tunnel-ingress-origin.sh"
S4_WRAP_FILES="$(printf '%s\n' .github/workflows/deploy-inngest-image.yml .github/workflows/web-platform-release.yml | sort)"
S4_DEF_EXCL=(-- . ':!knowledge-base' ':!tests' ':!*.test.sh' ":!$CUT")
S4_WRAP_DERIVED="$(cd "$REPO_ROOT" && git grep -lIE '^[[:space:]]*(function[[:space:]]+)?(_sig_curl|_bearer_curl)[[:space:]]*\(\)' "${S4_DEF_EXCL[@]}" | sort)"
S4_OK_DERIVED="$(cd "$REPO_ROOT" && git grep -lIE '^[[:space:]]*(function[[:space:]]+)?_bearer_ok[[:space:]]*\(\)' "${S4_DEF_EXCL[@]}" | sort)"
S4_OK_DEFS="$(cd "$REPO_ROOT" && git grep -cIE '^[[:space:]]*(function[[:space:]]+)?_bearer_ok[[:space:]]*\(\)' "${S4_DEF_EXCL[@]}" | awk -F: '{n += $NF} END {print n + 0}')"
s4_guard_py='
import sys, re
canon_ok, cut = sys.argv[1], sys.argv[2]
files = sys.argv[3:]
def fn(lines, name):
    out = []
    i = 0
    while i < len(lines):
        if re.match(r"^\s*" + name + r"\(\) \{$", lines[i]):
            j = i
            while not re.match(r"^\s*\}$", lines[j]):
                j += 1
            ind = len(lines[i]) - len(lines[i].lstrip())
            out.append("\n".join(x[ind:] for x in lines[i:j + 1]))
            i = j
        i += 1
    return out
def norm(t):
    return re.sub(r"script=[A-Za-z0-9._-]+", "script=X", t).replace("--max-time 60 ", "")
cl = open(cut).read().split("\n")
canon = {n: norm(fn(cl, n)[0]) for n in ("_sig_curl", "_bearer_curl")}
n_ok = n_sig = n_brr = 0; bad = []
for f in files:
    L = open(f).read().split("\n")
    for ln in L:
        if re.match(r"^\s*_bearer_ok\(\) \{", ln):
            n_ok += 1
            if ln.strip() != canon_ok:
                bad.append("%s:_bearer_ok" % f.rsplit("/", 1)[-1])
    for n in ("_sig_curl", "_bearer_curl"):
        for t in fn(L, n):
            if n == "_sig_curl": n_sig += 1
            else: n_brr += 1
            if norm(t) != canon[n]:
                bad.append("%s:%s" % (f.rsplit("/", 1)[-1], n))
print(n_ok, n_sig, n_brr, ",".join(bad))
'
read -r S4_G_OK S4_G_SIG S4_G_BRR S4_G_BAD < <(cd "$REPO_ROOT" && python3 -I -c "$s4_guard_py" "$BEARER_FN" "$CUT" $S4_OK_DERIVED)
# BOTH operands are literals above the `if`: 74 `_bearer_ok` definitions outside the cutover script (the four S4 inline-wrapper files hold 10 of them: release 6,
# deploy-inngest-image 2, luks 1, verify-tunnel 1; the rest are the ops scripts and followthrough probes converted by S1 to S3; #10546 retired two of those probes, the outer-wrap soak and the sandbox readback, taking the count from 77 to 76, after which later definition changes left it at 78 against this floor of 76; G1 PR-4a, #10937, retired four more, the canary-promotion, infra-config activation, infra-config fatal-channel and workspace-isolation soaks, taking the measured count from 78 to 74, and the floor now equals it), 6 `_sig_curl`, 2 `_bearer_curl`.
S4_GUARD_FLOOR=74
if [[ -z "$S4_G_BAD" && "$S4_G_OK" -ge "$S4_GUARD_FLOOR" && "$S4_G_OK" == "$S4_OK_DEFS" && "$S4_G_SIG" == 6 && "$S4_G_BRR" == 2 ]]; then
  row "S4 inline guard pin: all $S4_G_OK _bearer_ok definitions of the $(printf '%s\n' "$S4_OK_DERIVED" | grep -c .) tracked files that define one equal the canonical text byte for byte (the count equals git grep's), and the $S4_G_SIG _sig_curl and $S4_G_BRR _bearer_curl wrappers equal the cutover script's (marker name and its --max-time normalized); floor $S4_GUARD_FLOOR"  ok
else row "S4 inline guard pin: an inline guard or wrapper differs from the canonical text" fail "ok=$S4_G_OK defs=$S4_OK_DEFS sig=$S4_G_SIG brr=$S4_G_BRR bad=$S4_G_BAD"; fi
# The pinned file sets are populations, so they are judged by SET IDENTITY: the files defining a wrapper are exactly the explicit set, and the four
# inline-wrapper files the marker rows name still each define _bearer_ok (the derived population cannot shrink away from them).
S4_WRAP_OUT="$(s4_census_verdict "$S4_WRAP_DERIVED" "$S4_WRAP_FILES")"; S4_WRAP_RC=$?
S4_OK_GONE=""; for f in $S4_GUARD_FILES; do grep -qxF -- "$f" <<<"$S4_OK_DERIVED" || S4_OK_GONE+=" $f"; done
if [[ "$S4_WRAP_RC" == 0 && -z "$S4_OK_GONE" ]]; then row "S4 inline guard pin population: the files defining _sig_curl or _bearer_curl are exactly the two pinned workflow files, and each of the four inline-wrapper files still defines _bearer_ok (derived by git grep, never counted)" ok
else row "S4 inline guard pin population: an inline wrapper is defined in a file no pin judges, or a pinned file lost its definition" fail "$S4_WRAP_OUT gone='$S4_OK_GONE'"; fi
S4_WRAP_X="$(printf '%s\n' "$S4_WRAP_DERIVED" .github/workflows/zz-new-inline-wrapper.yml | grep . | sort)"; s4_census_verdict "$S4_WRAP_X" "$S4_WRAP_FILES" > /dev/null; S4_WRAP_X_RC=$?
S4_WRAP_M="$(printf '%s\n' "$S4_WRAP_DERIVED" | grep -v 'deploy-inngest-image' | sort)"; s4_census_verdict "$S4_WRAP_M" "$S4_WRAP_FILES" > /dev/null; S4_WRAP_M_RC=$?
s4_census_verdict "$S4_WRAP_FILES" "$S4_WRAP_FILES" > /dev/null; S4_WRAP_G_RC=$?
[[ "$S4_WRAP_X_RC" != 0 && "$S4_WRAP_M_RC" != 0 && "$S4_WRAP_G_RC" == 0 ]] && row "S4 inline guard pin population control: the pinned set is GREEN, a synthesized extra file defining a wrapper is RED (unclassified) and a vanished pinned file is RED (stale)" ok || row "S4 inline guard pin population control: the set identity does not discriminate" fail "extra=$S4_WRAP_X_RC missing=$S4_WRAP_M_RC good=$S4_WRAP_G_RC"
# The same pin must be SEEN to fail: a one-byte change in one definition is reported by that file (a pin nothing ever fed a known negative is not a control).
mf="$BKDIR/guard-mut-release.yml"; assert_fixture_dir "$mf"
python3 -I -c '
import sys
t = open(sys.argv[1]).read()
old = "_bearer_ok() { local LC_ALL=C; case"
if old not in t: sys.exit(3)
open(sys.argv[2], "w").write(t.replace(old, "_bearer_ok() { local LC_ALL=; case", 1))' "$REPO_ROOT/.github/workflows/web-platform-release.yml" "$mf" || fatal "S4 guard pin mutation did not land"
read -r _g1 _g2 _g3 S4_G_MBAD < <(python3 -I -c "$s4_guard_py" "$BEARER_FN" "$REPO_ROOT/$CUT" "$mf")
[[ "$S4_G_MBAD" == "guard-mut-release.yml:_bearer_ok" ]] && row "S4 inline guard pin control: a one-byte change to one _bearer_ok definition is reported at its file" ok || row "S4 inline guard pin control: the pin does not see a one-byte change" fail "got='$S4_G_MBAD'"
# A NEW file nobody listed, defining a permissive _bearer_ok, is a member of the derived population and is reported by name.
mf="$BKDIR/guard-new-script.sh"; assert_fixture_dir "$mf"
printf '%s\n' '#!/usr/bin/env bash' '_bearer_ok() { return 0; }' > "$mf"
read -r _g1 _g2 _g3 S4_G_NBAD < <(python3 -I -c "$s4_guard_py" "$BEARER_FN" "$REPO_ROOT/$CUT" "$mf")
[[ "$S4_G_NBAD" == "guard-new-script.sh:_bearer_ok" && "$_g1" == 1 ]] && row "S4 inline guard pin control: a permissive _bearer_ok in a NEW unlisted file is counted and reported at that file (the pin quantifies over the derived population)" ok || row "S4 inline guard pin control: a new file's _bearer_ok escapes the pin" fail "got='$S4_G_NBAD' n=$_g1"
# infra-config-verify.sh keeps its guard as a subshell case (a function would be an unlisted command to its read-only-allowlist suite): the
# PATTERN is pinned to the library alphabet, and the marker names the file.
S4_PAT="$(sed -E 's/.* in (.*)\) return 1.*/\1/' <<<"$BEARER_FN")"
if grep -qF -- "case \"\${!_cred:-}\" in ${S4_PAT}) exit 1 ;; esac" "$REPO_ROOT/apps/web-platform/infra/infra-config-verify.sh"; then
  row "S4 inline guard pin: infra-config-verify.sh judges the three credentials with exactly the library's token alphabet ($S4_PAT)" ok
else row "S4 inline guard pin: infra-config-verify.sh's shape check differs from the library alphabet" fail "pattern=$S4_PAT"; fi
S4_MARK_BAD=""
for f in .github/workflows/web-platform-release.yml .github/workflows/deploy-inngest-image.yml .github/workflows/workspaces-luks-cutover.yml apps/web-platform/infra/infra-config-verify.sh; do
  want_name="$(basename "$f")"; want_name="${want_name%.*}"
  names="$(grep -oE 'SOLEUR_CREDENTIAL_REFUSED script=[A-Za-z0-9._-]+' "$REPO_ROOT/$f" | sed 's/.*script=//' | sort -u)"
  [[ "$names" == "$want_name" ]] || S4_MARK_BAD+=" $f:${names//$'\n'/,}"
done
[[ -z "$S4_MARK_BAD" ]] && row "S4 structure: every inline wrapper file names ITSELF in the refusal marker (web-platform-release, deploy-inngest-image, workspaces-luks-cutover, infra-config-verify)" ok || row "S4 structure: an inline marker names another file" fail "$S4_MARK_BAD"
echo "=== stage S4: parity audit and guard pins done ==="

# =====================================================================================
# GUARD 2: a refused credential reaches the SAME verdict class as the old failure. The REAL step bodies (extracted from the YAML) and
# the real scripts run under the recording curl, each credential EMPTY, UNSET and HOSTILE (a quote carrying the canary, and a newline
# that tries to open a second `url =` directive on the config channel), with python3 ABSENT at one HMAC site per form. Every row
# reads the step's OWN lines and its GITHUB_OUTPUT / GITHUB_ENV (an exit code alone cannot tell a mute abort from a refusal), asserts
# zero requests, the marker, the sink table's verdict, and the canary in no captured stream. A well-formed run per representative
# proves the arm still SUCCEEDS; transport failures go through REAL curl against a closed port (the 000000 quirk).
# =====================================================================================
: > "$S4/bodies/empty"
S4_BASE=()
S4_SWEEP_BAD=""; S4_SWEEP_N=0; S4_SWEEP_WANT=0
# s4_sweep <label> <script> <realdir> <verdict-fn> "<credential vars>" "<key vars>": reads the global S4_BASE (NAME=value ...).
# A credential is run empty, unset, hostile-quote and hostile-newline; a KEY (an HMAC key, only non-emptiness matters) empty and unset.
s4_sweep() {
  local label="$1" body="$2" realdir="$3" vfn="$4" creds="$5" keys="$6" v st e
  local -a env_
  S4_SWEEP_BAD=""; S4_SWEEP_N=0; S4_SWEEP_WANT=0
  for v in $creds $keys; do
    for st in empty unset hostile-quote hostile-newline; do
      [[ " $keys " == *" $v "* && "$st" == hostile-* ]] && continue
      S4_SWEEP_WANT=$((S4_SWEEP_WANT + 1))
      env_=(); for e in "${S4_BASE[@]}"; do [[ "$e" == "$v="* ]] || env_+=("$e"); done
      case "$st" in
        empty) env_+=("$v=") ;;
        unset) : ;;
        hostile-quote) env_+=("$v=${S4_CANARY}\"x") ;;
        hostile-newline) env_+=("$v=${S4_CANARY}"$'\n'"url = \"http://127.0.0.1:9/\"") ;;
      esac
      s4_run "$label-$v-$st" "$body" "$realdir" "${env_[@]}"
      S4_SWEEP_N=$((S4_SWEEP_N + 1)); S4_REFUSAL_RUNS=$((S4_REFUSAL_RUNS + 1))
      if ! { [[ "$(s4_ncalls)" == 0 ]] && s4_canary_clean && "$vfn" "$v" "$st"; }; then S4_SWEEP_BAD+=" [$v/$st rc=$S4_RC calls=$(s4_ncalls) markers=$(s4_markers)]"; fi
    done
  done
}
s4_sweep_row() { # <description>
  if [[ -z "$S4_SWEEP_BAD" && "$S4_SWEEP_N" == "$S4_SWEEP_WANT" && "$S4_SWEEP_N" -gt 0 ]]; then row "$1 ($S4_SWEEP_N runs)" ok
  else row "$1" fail "${S4_SWEEP_BAD:- ran $S4_SWEEP_N of $S4_SWEEP_WANT}"; fi
}
# s4_nopy_row <description> <script> <verdict-fn>: the same site with python3 ABSENT (the signature cannot be computed): the arm's own verdict, never a mute abort.
s4_nopy_row() {
  s4_run "nopy-$1" "$2" "$S4/real-nopy" "${S4_BASE[@]}"; S4_REFUSAL_RUNS=$((S4_REFUSAL_RUNS + 1))
  if [[ "$(s4_ncalls)" == 0 ]] && s4_canary_clean && "$3" python3 absent; then row "$1" ok
  else row "$1" fail "rc=$S4_RC calls=$(s4_ncalls) markers=$(s4_markers)"; fi
}
# s4_mutant_red <description> <workflow> <step> <tag> <from> <to> <verdict-fn> <hostile NAME=value>: a MUTANT of a real step (the one line <from> replaced by <to>, built from the YAML;
# a line that no longer matches fails THIS row, never the battery) run with a hostile credential on the global S4_BASE must be judged RED by the very verdict function the
# row's sweep uses. This is what makes a verdict function a control: a swallowed refusal (`|| true`, `|| echo 200`) reads as a pass in the old behaviour, so a verdict that
# only has positive and negative text clauses but was never fed a bad step could be satisfied by anything.
s4_mutant_red() {
  local d="$1" wf="$2" step="$3" tag="$4" from="$5" to="$6" vfn="$7" hostile="$8" built=0 e out
  local -a env_=()
  out="$S4/b-ctl-$tag.sh"
  s4_body_try "$wf" "$step" "$out" "$from" "$to" && built=1
  if (( built )); then
    for e in "${S4_BASE[@]}"; do [[ "$e" == "${hostile%%=*}="* ]] || env_+=("$e"); done
    s4_run "ctl-$tag" "$out" "$S4/real" "${env_[@]}" "$hostile"; S4_REFUSAL_RUNS=$((S4_REFUSAL_RUNS + 1))
  fi
  if (( built )) && ! "$vfn" "${hostile%%=*}" hostile-quote; then row "$d" ok
  else row "$d" fail "built=$built rc=$S4_RC calls=$(s4_ncalls) markers=$(s4_markers) (a green verdict means the mutant is accepted; built=0 means the step no longer contains the line the control mutates)"; fi
}
# s4_wh_ok <body file> <call#>: the call carries X-Signature-256 == the independent openssl digest over the request's own body bytes, then
# the Cloudflare Access id and secret, in that order, none of the four values is on any recorded argv of curl, python3 or openssl, and the
# signature really was computed by a python3 child (a wrapper that recorded nothing would let the key check pass on an empty record).
s4_wh_ok() {
  local want; want="$(s4_oracle "$S4_KEY" "$1")"
  [[ -n "$want" && "$(s4_stdin_line "$2" 1)" == "header = \"X-Signature-256: sha256=$want\"" && "$(s4_stdin_line "$2" 2)" == "header = \"CF-Access-Client-Id: $S4_CFID\"" \
     && "$(s4_stdin_line "$2" 3)" == "header = \"CF-Access-Client-Secret: $S4_CFSEC\"" ]] \
    && s4_nowhere_on_argv "$S4_KEY" && s4_nowhere_on_argv "$want" && s4_nowhere_on_argv "$S4_CFID" && s4_nowhere_on_argv "$S4_CFSEC" \
    && s4_tool_ran python3
}
S4_NOW="$(date +%s)"
S4_WH_BASE=(WEBHOOK_SECRET="$S4_KEY" CF_ACCESS_CLIENT_ID="$S4_CFID" CF_ACCESS_CLIENT_SECRET="$S4_CFSEC" SHIM_PROFILE=webhook)
S4_DOP_BASE=(D_WEBHOOK_DEPLOY_SECRET="$S4_KEY" D_CF_ACCESS_CLIENT_ID="$S4_CFID" D_CF_ACCESS_CLIENT_SECRET="$S4_CFSEC" SHIM_PROFILE=webhook)

# ---- row 1 and row 2: restart-inngest-server (library; the poll loop, the lock_contention final re-read and the liveness read) ----
S4_RST=".github/workflows/restart-inngest-server.yml"
s4_body "$REPO_ROOT/$S4_RST" "Trigger restart via webhook" "$S4/b-r1.sh"
s4_body "$REPO_ROOT/$S4_RST" "Verify restart completion" "$S4/b-r2.sh" 'MAX_POLLS=120' 'MAX_POLLS=3'
S4_BASE=("${S4_WH_BASE[@]}")
s4_run r1-ok "$S4/b-r1.sh" "$S4/real" "${S4_BASE[@]}"
if [[ "$S4_RC" == 0 && "$(s4_ncalls)" == 1 && "$(cat "$S4_ROW/calls/1.body")" == '{"command":"restart inngest _ latest"}' ]] && s4_calls_ok 3 && s4_wh_ok "$S4_ROW/calls/1.body" 1 \
   && grep -q '^TRIGGER_TS=' "$S4_ROW/genv" && s4_said 'Restart initiated (HTTP 202)'; then
  row "S4 row 1 restart trigger: a well-formed run sends ONE request whose three stdin headers are the independent digest over the body, the id and the secret; none is on argv" ok
else row "S4 row 1 restart trigger: well-formed run" fail "rc=$S4_RC calls=$(s4_ncalls)"; fi
# The trigger step's failure handler prints ONE message for any rc (no branch on rc == 2: rc 2 is also curl's own exit code): it names the rc, says that a marker line above means
# nothing was sent and otherwise the request may have reached the host, and keeps the exit code. A verdict that only checked "red + marker" would accept a silent abort.
S4_FAILMSG_REFUSED='If a SOLEUR_CREDENTIAL_REFUSED line is printed above, the credential was refused before any request was made and nothing was sent; otherwise the request may have reached the host'
s4_failmsg() { s4_said "::error::$1 webhook call failed (rc=$2). $S4_FAILMSG_REFUSED"; }
s4_v_r1() { [[ "$S4_RC" != 0 && "$(s4_markers)" == 1 ]] && ! s4_said 'Restart initiated' && ! s4_said 'Restart webhook rejected' && s4_failmsg Restart 2 && [[ "$S4_RC" == 2 ]]; }
s4_sweep r1 "$S4/b-r1.sh" "$S4/real" s4_v_r1 "CF_ACCESS_CLIENT_ID CF_ACCESS_CLIENT_SECRET" "WEBHOOK_SECRET"
s4_sweep_row "S4 row 1 restart trigger: an empty, unset or hostile credential is RED (rc 2 aborts under set -e) with ONE marker, zero requests, no 'rejected' line and the canary absent"
s4_nopy_row "S4 row 1 restart trigger (library HMAC site): python3 absent is RED with the marker and zero requests, never a mute abort" "$S4/b-r1.sh" s4_v_r1
S4_SHIM="$S4/shimreal"; s4_run r1-transport "$S4/b-r1.sh" "$S4/real" "${S4_BASE[@]}"; S4_SHIM="$S4/shim"
if [[ "$S4_RC" != 0 && "$(s4_markers)" == 0 ]] && ! s4_said 'Restart initiated' && s4_failmsg Restart 7 && [[ "$S4_RC" == 7 ]]; then row "S4 row 1 restart trigger: a REAL transport failure (closed port) is RED, is not a refusal (no marker), names rc=7 in its one failure line and exits with that code" ok
else row "S4 row 1 restart trigger: transport failure" fail "rc=$S4_RC markers=$(s4_markers) out=$(tail -2 "$S4_ROW/stdout" | tr '\n' '|')"; fi
s4_frame_ok="{\"component\":\"inngest\",\"exit_code\":0,\"reason\":\"success\",\"start_ts\":$((S4_NOW + 5))}"
s4_run r2-ok "$S4/b-r2.sh" "$S4/real" "${S4_BASE[@]}" TRIGGER_TS="$S4_NOW" SHIM_STATUS_BODY="$s4_frame_ok"
if [[ "$S4_RC" == 0 && "$(s4_ncalls)" == 1 && "$(s4_markers)" == 0 ]] && s4_calls_ok 3 && s4_wh_ok "$S4/bodies/empty" 1 && s4_said 'Inngest restart completed successfully'; then
  row "S4 row 2 restart verify: a well-formed poll sends the digest over the EMPTY body plus the Cloudflare pair on stdin and reads the success frame" ok
else row "S4 row 2 restart verify: well-formed run" fail "rc=$S4_RC calls=$(s4_ncalls) markers=$(s4_markers)"; fi
s4_lock_frame="{\"component\":\"inngest\",\"exit_code\":1,\"reason\":\"lock_contention\",\"start_ts\":$((S4_NOW + 5))}"
s4_run r2-lock "$S4/b-r2.sh" "$S4/real" "${S4_BASE[@]}" TRIGGER_TS="$S4_NOW" SHIM_STATUS_BODY="$s4_lock_frame" SHIM_LIVE_BODY='{"functions":[{"name":"synthetic-fn"}]}'
S4_LOCK_OK=1; for ((ci = 1; ci <= $(s4_ncalls); ci++)); do s4_wh_ok "$S4/bodies/empty" "$ci" || S4_LOCK_OK=0; done
if [[ "$S4_RC" == 0 && "$(s4_ncalls)" == 5 && "$S4_LOCK_OK" == 1 && "$(s4_markers)" == 0 ]] && s4_calls_ok 3 && s4_said 'liveness healthy: functions registered'; then
  row "S4 row 2 restart verify: the lock_contention path drives the other three library sites (3 polls, the final STATE re-read, the liveness read): 5 requests, each with its own digest and the pair on stdin, none on argv" ok
else row "S4 row 2 restart verify: lock_contention path" fail "rc=$S4_RC calls=$(s4_ncalls) ok=$S4_LOCK_OK"; fi
s4_v_r2() { [[ "$S4_RC" != 0 && "$(s4_markers)" == 3 ]] && s4_said '::error::Restart did not complete within the' && ! s4_said 'Inngest restart completed'; }
S4_BASE=("${S4_WH_BASE[@]}" TRIGGER_TS="$S4_NOW" SHIM_STATUS_BODY="$s4_frame_ok")
s4_sweep r2 "$S4/b-r2.sh" "$S4/real" s4_v_r2 "CF_ACCESS_CLIENT_ID CF_ACCESS_CLIENT_SECRET" "WEBHOOK_SECRET"
s4_sweep_row "S4 row 2 restart verify: an empty, unset or hostile credential is the poll loop's old terminal RED with ONE marker per attempt (3 here), zero requests and the canary absent"
s4_nopy_row "S4 row 2 restart verify (library HMAC site): python3 absent reaches the same terminal red with the marker per attempt, never a mute abort" "$S4/b-r2.sh" s4_v_r2

# ---- row 4: apply-inngest-rls (library + pre-guard; the four calls had 2>/dev/null, so the marker was invisible) ----
S4_RLS=".github/workflows/apply-inngest-rls.yml"
s4_body "$REPO_ROOT/$S4_RLS" "Apply lockdown" "$S4/b-r4.sh"
S4_SBP="sbp""_$(od -An -N20 -tx1 /dev/urandom | tr -d ' \n')"
S4_RLS_BASE=(SUPABASE_ACCESS_TOKEN="$S4_SBP" PROJECT_REF=pigsfuxruiopinouvjwy PROJECT_NAME=soleur-inngest-prd SQL_FILE=apps/web-platform/infra/inngest-rls/0001_enable_rls_lockdown.sql SHIM_PROFILE=rls)
S4_BASE=("${S4_RLS_BASE[@]}")
s4_run r4-ok "$S4/b-r4.sh" "$S4/real" "${S4_BASE[@]}"
S4_RLS_OK=1; for ((ci = 1; ci <= $(s4_ncalls); ci++)); do [[ "$(s4_stdin_line "$ci" 1)" == "header = \"Authorization: Bearer $S4_SBP\"" ]] || S4_RLS_OK=0; done
if [[ "$S4_RC" == 0 && "$(s4_ncalls)" -ge 6 && "$S4_RLS_OK" == 1 && "$(s4_markers)" == 0 ]] && s4_calls_ok 1 && ! s4_argv_has "$S4_SBP" && s4_said 'Inngest RLS lockdown verified'; then
  row "S4 row 4 apply-inngest-rls: a well-formed run makes $(s4_ncalls) requests (identity, apply, the catalog queries, the advisor), each with the sbp_ token as its only stdin header and none on argv, and verifies the lockdown" ok
else row "S4 row 4 apply-inngest-rls: well-formed run" fail "rc=$S4_RC calls=$(s4_ncalls) ok=$S4_RLS_OK"; fi
s4_v_r4() { # a refusal is the existing secret class, never `identity_unreachable` (an empty HTTP code read as an unreachable API)
  [[ "$S4_RC" != 0 ]] && s4_gho_has 'failure_mode=secret_unset' && ! grep -q 'identity_unreachable' "$S4_ROW/gho" && ! s4_said 'identity_unreachable' || return 1
  case "$2" in hostile-*) [[ "$(s4_markers)" == 1 ]] ;; *) [[ "$(s4_markers)" == 0 ]] ;; esac
}
s4_sweep r4 "$S4/b-r4.sh" "$S4/real" s4_v_r4 "SUPABASE_ACCESS_TOKEN" ""
s4_sweep_row "S4 row 4 apply-inngest-rls: an empty, unset or hostile token is recorded as failure_mode=secret_unset (never identity_unreachable) with zero requests; a hostile one prints the marker ONCE"
S4_EMPTYWS="$S4/emptyws"; assert_fixture_dir "$S4_EMPTYWS"; mkdir -p "$S4_EMPTYWS"
s4_run r4-nolib "$S4/b-r4.sh" "$S4/real" "${S4_BASE[@]}" GITHUB_WORKSPACE="$S4_EMPTYWS"
if [[ "$S4_RC" != 0 && "$(s4_ncalls)" == 0 ]] && s4_said 'scripts/lib/bearer-curl.sh could not be loaded'; then row "S4 row 4 apply-inngest-rls: a checkout without the library is a hard failure with zero requests and no argv fallback" ok
else row "S4 row 4 apply-inngest-rls: library absent" fail "rc=$S4_RC calls=$(s4_ncalls)"; fi
# The marker must stay VISIBLE where a refusal reaches the call itself. The pre-guard normally stands in front of every call, so the row
# neutralizes it in a COPY of the library (bc_ok_var always true) and runs the real step: the first call's own refusal is then the only
# thing that can print the marker, and a `2>/dev/null` on that call would swallow it.
S4_NOGUARD="$S4/ws-noguard"; assert_fixture_dir "$S4_NOGUARD"; mkdir -p "$S4_NOGUARD/scripts/lib"
{ cat "$REPO_ROOT/scripts/lib/bearer-curl.sh"; printf '%s\n' 'bc_ok_var() { return 0; }'; } > "$S4_NOGUARD/scripts/lib/bearer-curl.sh"
s4_run r4-visible "$S4/b-r4.sh" "$S4/real" "${S4_BASE[@]}" "SUPABASE_ACCESS_TOKEN=${S4_CANARY}\"x" GITHUB_WORKSPACE="$S4_NOGUARD"
if [[ "$S4_RC" != 0 && "$(s4_ncalls)" == 0 && "$(s4_markers)" == 1 ]] && s4_canary_clean; then
  row "S4 row 4 apply-inngest-rls: when a refusal reaches the identity call itself it aborts the step RED with the marker VISIBLE (no 2>/dev/null on the call), zero requests, the canary absent" ok
else row "S4 row 4 apply-inngest-rls: marker-visible row" fail "rc=$S4_RC calls=$(s4_ncalls) markers=$(s4_markers)"; fi

# ---- rows 8 to 12: web-platform-release (INLINE wrappers: the jobs are checkout-free by design) ----
S4_WFR=".github/workflows/web-platform-release.yml"
mapfile -t S4_REL_JOBENV < <(s4_jobenv "$REPO_ROOT/$S4_WFR" deploy)
s4_body "$REPO_ROOT/$S4_WFR" "Pre-rerun lock probe" "$S4/b-r8.sh"
s4_body "$REPO_ROOT/$S4_WFR" "Deploy via webhook" "$S4/b-r9.sh"
s4_body "$REPO_ROOT/$S4_WFR" "Verify deploy script completion" "$S4/b-r10.sh"
s4_body "$REPO_ROOT/$S4_WFR" "Verify peer deploy completion" "$S4/b-r10p.sh"
s4_body "$REPO_ROOT/$S4_WFR" "Email notification (deploy FAILED)" "$S4/b-r11.sh"
s4_body "$REPO_ROOT/$S4_WFR" "email" "$S4/b-r12.sh"
# Each step gets ONLY what its YAML declares (s4_run drops the rest and the final "declared environment" row asserts nothing was dropped):
# the job env for the lock probe, plus VERSION for the verify poll, plus VERSION and the peer list for the deploy call.
S4_REL_ENV=("${S4_REL_JOBENV[@]}" VERSION=1.2.3)
# row 9 (red class): Deploy via webhook
S4_BASE=("${S4_WH_BASE[@]}" "${S4_REL_ENV[@]}" WEB_HOST_PRIVATE_IPS=10.0.1.10,10.0.1.11)
s4_run r9-ok "$S4/b-r9.sh" "$S4/real" "${S4_BASE[@]}"
if [[ "$S4_RC" == 0 && "$(s4_ncalls)" == 1 ]] && s4_calls_ok 3 && s4_wh_ok "$S4_ROW/calls/1.body" 1 && s4_said 'Deploy initiated (HTTP 202)' \
   && grep -qF '"peers":"10.0.1.10,10.0.1.11"' "$S4_ROW/calls/1.body" && grep -qF 'soleur-web-platform v1.2.3' "$S4_ROW/calls/1.body"; then
  row "S4 row 9 release deploy (inline): a well-formed run signs the body it sends (independent openssl digest over the recorded bytes) and carries the pair on stdin, none on argv" ok
else row "S4 row 9 release deploy (inline): well-formed run" fail "rc=$S4_RC calls=$(s4_ncalls)"; fi
s4_v_r9() { [[ "$S4_RC" != 0 && "$(s4_markers)" == 1 ]] && ! s4_said 'Deploy initiated' && ! s4_said 'Deploy webhook rejected' && s4_failmsg Deploy 2 && [[ "$S4_RC" == 2 ]]; }
s4_sweep r9 "$S4/b-r9.sh" "$S4/real" s4_v_r9 "CF_ACCESS_CLIENT_ID CF_ACCESS_CLIENT_SECRET" "WEBHOOK_SECRET"
s4_sweep_row "S4 row 9 release deploy (inline, red class): an empty, unset or hostile credential aborts the step RED before any request (production stays on the previous build) with ONE marker and the canary absent"
s4_nopy_row "S4 row 9 release deploy (inline HMAC site): python3 absent is RED with the marker and zero requests, never a mute abort" "$S4/b-r9.sh" s4_v_r9
S4_SHIM="$S4/shimreal"; s4_run r9-transport "$S4/b-r9.sh" "$S4/real" "${S4_BASE[@]}"; S4_SHIM="$S4/shim"
if [[ "$S4_RC" != 0 && "$(s4_markers)" == 0 ]] && ! s4_said 'Deploy initiated' && s4_failmsg Deploy 7 && [[ "$S4_RC" == 7 ]]; then row "S4 row 9 release deploy: a REAL transport failure (closed port) is still RED and is not a refusal (no marker; the one failure line names rc=7 and the process exits with that code)" ok
else row "S4 row 9 release deploy: transport failure" fail "rc=$S4_RC markers=$(s4_markers)"; fi
# CONTROLS for the failure handler: (1) a handler that ends in a SILENT abort (the message line removed) is judged RED by the refusal verdict; (2) a handler that exits 1 for
# `exit "$rc"` is caught by the exit-code clause: a transport failure must exit with curl's own code (7).
S4_SA_BUILT=0; S4_EX_BUILT=0; S4_SA_RED=0; S4_EX_RED=0
s4_body_try "$REPO_ROOT/$S4_WFR" "Deploy via webhook" "$S4/b-ctl-r9-silent.sh" 'echo "::error::Deploy webhook call failed' ': # echo "::error::Deploy webhook call failed' && S4_SA_BUILT=1
s4_body_try "$REPO_ROOT/$S4_WFR" "Deploy via webhook" "$S4/b-ctl-r9-exit1.sh" 'exit "$rc"' 'exit 1' && S4_EX_BUILT=1
if [[ "$S4_SA_BUILT" == 1 ]]; then
  s4_run ctl-r9-silent "$S4/b-ctl-r9-silent.sh" "$S4/real" "${S4_BASE[@]}" "CF_ACCESS_CLIENT_ID=${S4_CANARY}\"x"; S4_REFUSAL_RUNS=$((S4_REFUSAL_RUNS + 1))
  ! s4_v_r9 && S4_SA_RED=1
fi
if [[ "$S4_EX_BUILT" == 1 ]]; then
  S4_SHIM="$S4/shimreal"; s4_run ctl-r9-exit1 "$S4/b-ctl-r9-exit1.sh" "$S4/real" "${S4_BASE[@]}"; S4_SHIM="$S4/shim"
  s4_failmsg Deploy 7 && [[ "$S4_RC" != 7 ]] && S4_EX_RED=1
fi
if [[ "$S4_SA_RED" == 1 && "$S4_EX_RED" == 1 ]]; then row "S4 row 9 release deploy control: a handler that aborts silently (no failure line) is judged RED by the refusal verdict, and one that exits 1 instead of the call's own code is caught by the exit-code clause (a transport failure must exit 7)" ok
else row "S4 row 9 release deploy control: a silent or exit-swallowing handler is not judged red" fail "built=$S4_SA_BUILT/$S4_EX_BUILT red=$S4_SA_RED/$S4_EX_RED"; fi
# CONTROL (the key must be on NO tool's argument list, not only curl's): the same step with the key moved onto python3's argv (an `-X` option python ignores, so the
# signature stays VALID and curl's argv stays clean) is judged RED by the very predicate the HMAC rows use, and only by its python3 clause.
S4_PY_BUILT=0; s4_body_try "$REPO_ROOT/$S4_WFR" "Deploy via webhook" "$S4/b-r9-pyargv.sh" 'python3 -I -c' 'python3 -I -X "k=$WEBHOOK_SECRET" -c' && S4_PY_BUILT=1
if [[ "$S4_PY_BUILT" == 1 ]]; then s4_run ctl-r9-pyargv "$S4/b-r9-pyargv.sh" "$S4/real" "${S4_BASE[@]}"; fi
if [[ "$S4_PY_BUILT" == 1 && "$S4_RC" == 0 && "$(s4_ncalls)" == 1 ]] && s4_calls_ok 3 && ! s4_argv_has "$S4_KEY" && s4_tool_argv_has python3 "$S4_KEY" && ! s4_wh_ok "$S4_ROW/calls/1.body" 1; then
  row "S4 HMAC control: a signer that puts the key on python3's argument list (signature still valid, curl's argv clean) is judged RED by the HMAC rows' predicate" ok
else row "S4 HMAC control: a key on python3's argv is not judged red" fail "built=$S4_PY_BUILT rc=$S4_RC calls=$(s4_ncalls) py=$(s4_tool_argv_has python3 "$S4_KEY" && echo seen || echo missed) wh=$(s4_wh_ok "$S4_ROW/calls/1.body" 1 && echo green || echo red)"; fi
# row 10: Verify deploy script completion (poll loop)
S4_BASE=("${S4_WH_BASE[@]}" "${S4_REL_ENV[@]}" STATUS_POLL_MAX_ATTEMPTS=3 STATUS_POLL_INTERVAL_S=0 SHIM_STATUS_BODY='{"exit_code":0,"reason":"ok","tag":"v1.2.3"}')
s4_run r10-ok "$S4/b-r10.sh" "$S4/real" "${S4_BASE[@]}"
if [[ "$S4_RC" == 0 && "$(s4_ncalls)" == 1 ]] && s4_calls_ok 3 && s4_wh_ok "$S4/bodies/empty" 1 && s4_said 'ci-deploy.sh completed successfully for v1.2.3'; then
  row "S4 row 10 release verify (inline): a well-formed poll carries the digest over the empty body and the pair on stdin and reads the completion" ok
else row "S4 row 10 release verify (inline): well-formed run" fail "rc=$S4_RC calls=$(s4_ncalls)"; fi
s4_v_r10() { [[ "$S4_RC" != 0 && "$(s4_markers)" == 3 ]] && s4_said '::error::ci-deploy.sh did not report completion for v1.2.3'; }
s4_sweep r10 "$S4/b-r10.sh" "$S4/real" s4_v_r10 "CF_ACCESS_CLIENT_ID CF_ACCESS_CLIENT_SECRET" "WEBHOOK_SECRET"
s4_sweep_row "S4 row 10 release verify (inline): an empty, unset or hostile credential is the poll's old terminal RED with ONE marker per attempt, zero requests and the canary absent"
s4_nopy_row "S4 row 10 release verify (inline HMAC site): python3 absent reaches the terminal red with the marker per attempt" "$S4/b-r10.sh" s4_v_r10
# row 8 (soft class): the pre-rerun lock probe is DEGRADED-PERMISSIVE: a refusal proceeds, with the marker visible
S4_BASE=("${S4_WH_BASE[@]}" "${S4_REL_JOBENV[@]}" SHIM_STATUS_BODY='{"exit_code":0}')
s4_run r8-ok "$S4/b-r8.sh" "$S4/real" "${S4_BASE[@]}"
if [[ "$S4_RC" == 0 && "$(s4_ncalls)" == 1 ]] && s4_calls_ok 3 && s4_wh_ok "$S4/bodies/empty" 1 && s4_said 'Pre-rerun probe: no in-flight deploy (exit_code=0)'; then
  row "S4 row 8 release lock probe (inline): a well-formed run reads the idle state through the digest and the pair on stdin" ok
else row "S4 row 8 release lock probe (inline): well-formed run" fail "rc=$S4_RC calls=$(s4_ncalls)"; fi
s4_v_r8() { [[ "$S4_RC" == 0 && "$(s4_markers)" == 1 ]] && s4_said 'Pre-rerun probe: non-JSON or empty body (HTTP 000) — proceeding (degraded-permissive)' && ! s4_said 'Prior deploy'; }
s4_sweep r8 "$S4/b-r8.sh" "$S4/real" s4_v_r8 "CF_ACCESS_CLIENT_ID CF_ACCESS_CLIENT_SECRET" "WEBHOOK_SECRET"
s4_sweep_row "S4 row 8 release lock probe (inline, soft class): an empty, unset or hostile credential PROCEEDS (exit 0, degraded-permissive) with the marker visible once, zero requests and the canary absent"
S4_SHIM="$S4/shimreal"; s4_run r8-transport "$S4/b-r8.sh" "$S4/real" "${S4_BASE[@]}"; S4_SHIM="$S4/shim"
if [[ "$S4_RC" == 0 && "$(s4_markers)" == 0 ]] && s4_said 'Pre-rerun probe: non-JSON or empty body (HTTP 000000)'; then row "S4 row 8 release lock probe: a REAL transport failure keeps the documented 000000 quirk and proceeds, with no marker" ok
else row "S4 row 8 release lock probe: transport failure" fail "rc=$S4_RC markers=$(s4_markers) out=$(tail -2 "$S4_ROW/stdout" | tr '\n' '|')"; fi
# rows 11 and 12 (warning class): the Resend email steps. Hostile = the old delivery failure with the marker; empty/unset = the step's OWN message.
S4_RESEND="re""_$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')"
S4_BASE=(RESEND_API_KEY="$S4_RESEND" MIRROR_VERIFIED=true RUN_URL=https://example.invalid/run VERSION=1.2.3 SHIM_PROFILE=generic)
s4_run r11-ok "$S4/b-r11.sh" "$S4/real" "${S4_BASE[@]}"
if [[ "$S4_RC" == 0 && "$(s4_ncalls)" == 1 && "$(s4_stdin_line 1 1)" == "header = \"Authorization: Bearer $S4_RESEND\"" ]] && s4_calls_ok 1 && ! s4_argv_has "$S4_RESEND" && s4_said 'Deploy-failure email sent to ops@jikigai.com (HTTP 200)'; then
  row "S4 row 11 deploy-failure email (inline): a well-formed run sends the re_ key as the only stdin header and none on argv" ok
else row "S4 row 11 deploy-failure email (inline): well-formed run" fail "rc=$S4_RC calls=$(s4_ncalls)"; fi
s4_v_r11() { [[ "$S4_RC" == 0 ]] || return 1
  case "$2" in
    hostile-*) [[ "$(s4_markers)" == 1 ]] && s4_said '::error::Deploy-failure email FAILED (HTTP 000)' ;;
    *) [[ "$(s4_markers)" == 0 ]] && s4_said '::error::RESEND_API_KEY not set' ;;
  esac; }
s4_sweep r11 "$S4/b-r11.sh" "$S4/real" s4_v_r11 "RESEND_API_KEY" ""
s4_sweep_row "S4 row 11 deploy-failure email (inline, warning class): a hostile key is the old '::error:: Deploy-failure email FAILED (HTTP 000)' line (exit 0, non-fatal) with the marker ONCE and zero requests; an empty or unset key keeps its own message"
S4_SHIM="$S4/shimreal"; s4_run r11-transport "$S4/b-r11.sh" "$S4/real" "${S4_BASE[@]}"; S4_SHIM="$S4/shim"
if [[ "$S4_RC" == 0 && "$(s4_markers)" == 0 ]] && s4_said '::error::Deploy-failure email FAILED (HTTP 000000)'; then row "S4 row 11 deploy-failure email: a REAL transport failure keeps the 000000 quirk and the same non-fatal error line, no marker" ok
else row "S4 row 11 deploy-failure email: transport failure" fail "rc=$S4_RC"; fi
S4_BASE=(RESEND_API_KEY="$S4_RESEND" CLASSIFIER=failure FAILED=live-verify FAILED_HTML='<li>live-verify</li>' R_DEPLOY=failure TAG=v1.2.3 VERSION=1.2.3 RUN_URL=https://example.invalid/run SHIM_PROFILE=generic)
s4_run r12-ok "$S4/b-r12.sh" "$S4/real" "${S4_BASE[@]}"
if [[ "$S4_RC" == 0 && "$(s4_ncalls)" == 1 && "$(s4_stdin_line 1 1)" == "header = \"Authorization: Bearer $S4_RESEND\"" ]] && s4_calls_ok 1 && s4_gho_has 'delivered=1'; then row "S4 row 12 release-outcome email (inline): a well-formed run delivers (delivered=1) with the key on stdin only" ok
else row "S4 row 12 release-outcome email (inline): well-formed run" fail "rc=$S4_RC calls=$(s4_ncalls)"; fi
s4_v_r12() { [[ "$S4_RC" == 0 ]] || return 1
  case "$2" in
    hostile-*) [[ "$(s4_markers)" == 1 ]] && s4_gho_has 'delivered=0' && s4_gho_has 'reason=resend_http_000' ;;
    *) [[ "$(s4_markers)" == 0 ]] && s4_gho_has 'delivered=0' && s4_gho_has 'reason=resend_api_key_unset' ;;
  esac; }
s4_sweep r12 "$S4/b-r12.sh" "$S4/real" s4_v_r12 "RESEND_API_KEY" ""
s4_sweep_row "S4 row 12 release-outcome email (inline, warning class): a hostile key reads as the old delivery failure (delivered=0, reason=resend_http_000, exit 0) so the Sentry fallback still fires; an empty or unset key keeps its own reason"
echo "=== stage S4: Guard 2 rows 1, 2, 4, 8 to 12 done ==="

