# shellcheck shell=bash
# SOURCED FRAGMENT of tests/scripts/test-argv-bearer-sweep.sh -- NOT independently runnable.
# =====================================================================================
# STAGE S3 (argv-bearer sweep S3, ADR-280): workflow YAML and the two composite actions send their credential
# through scripts/lib/bearer-curl.sh. The library's own contract (hostile/empty/unset values at every spec position,
# the byte sweep, the HMAC oracle, xtrace, the chokepoint census) is proved in scripts/lib/bearer-curl.test.sh; THIS
# stage proves the SITES: the population is derived from the tree, each member is checked structurally, and the
# representative call sites are EXECUTED (the real `run:` body, or a recorded slice whose drift from the live step
# text is pinned by a row) under a recording curl shim with the credential empty, hostile and well-formed. A row asserts
# the site's verdict class (red step, soft verdict or warning), the marker exactly once, zero requests for a refusal,
# and the planted canary in no output. The scheduled-inngest-health probe step was HELD BACK by S3 (its infra suite builds a
# fake workspace); S4 converted it, so no member of this population may carry an argv site any more. S4 added five more
# members (the Supabase, GitHub App, restart-webhook and deploy-pipeline-fix workflows and the mint composite); the stage
# below this one (STAGE S4) judges the script consumers of the library and the inline-wrapper files.
# =====================================================================================
S3="$TMPD/s3"; assert_fixture_dir "$S3"; mkdir -p "$S3/shim" "$S3/real" "$S3/rows"
cat > "$S3/shim/curl" <<'S3SHIM'
#!/usr/bin/env bash
# Recording curl for the S3 stage. Synthesized: answers SHIM_CODE (default 200) with SHIM_BODY (default {}).
d="${CALLS_DIR:?}"
n=$(( $(find "$d" -name '*.argv' | wc -l) + 1 ))
printf '%s\0' "$@" > "$d/$n.argv"
out=""; wfmt=""; prev=""; cfg=0
for a in "$@"; do
  [[ "$prev" == "-o" ]] && out="$a"
  [[ "$prev" == "-w" ]] && wfmt="$a"
  [[ "$prev" == "--config" && "$a" == "-" ]] && cfg=1
  prev="$a"
done
[[ "$cfg" -eq 1 ]] && cat > "$d/$n.stdin"
code="${SHIM_CODE:-200}"; body="${SHIM_BODY-}"; [[ -n "$body" ]] || body='{}'
if [[ -n "$out" ]]; then
  [[ "$out" == /dev/null ]] || printf '%s' "$body" > "$out"
else
  printf '%s' "$body"
fi
if [[ -n "$wfmt" ]]; then
  fmt="${wfmt//%\{http_code\}/$code}"
  printf '%b' "$fmt"
fi
exit "${SHIM_RC:-0}"
S3SHIM
chmod +x "$S3/shim/curl"
for t in bash cat date grep sed tr awk head tail jq mktemp rm mkdir env dirname basename cut wc sort tee python3 openssl find printf; do
  p="$(type -P "$t" || true)"; [[ -n "$p" ]] && ln -s "$p" "$S3/real/$t"
done
[[ -e "$S3/real/python3" && -e "$S3/real/jq" ]] || fatal "stage S3: python3 and jq are required"
mkdir -p "$S3/real-nopy"
for t in "$S3"/real/*; do [[ "$(basename "$t")" == python3 ]] || ln -s "$(readlink "$t")" "$S3/real-nopy/$(basename "$t")"; done
S3_CANARY="S3CANARYsecret0123"
S3_K_ANTH="synth-anthropic""_key-0123"   # split literal: no contiguous key-shaped string in the source
s3_pop_py='
import sys, re, glob, yaml
files = sorted(glob.glob(".github/workflows/*.yml")) + sorted(glob.glob(".github/actions/*/action.yml"))
for f in files:
    d = yaml.safe_load(open(f))
    steps = []
    if isinstance(d.get("runs"), dict):
        steps = d["runs"].get("steps") or []
    else:
        for j in (d.get("jobs") or {}).values():
            steps += (j.get("steps") or []) if isinstance(j, dict) else []
    if any(isinstance(s.get("run"), str) and "scripts/lib/bearer-curl.sh" in s["run"] for s in steps if isinstance(s, dict)):
        print(f)
'
s3_step_py='
import sys, yaml
f, sel = sys.argv[1], sys.argv[2]
d = yaml.safe_load(open(f))
steps = []
if isinstance(d.get("runs"), dict):
    steps = d["runs"].get("steps") or []
else:
    for j in (d.get("jobs") or {}).values():
        steps += (j.get("steps") or []) if isinstance(j, dict) else []
for s in steps:
    if isinstance(s, dict) and isinstance(s.get("run"), str) and (s.get("id") == sel or str(s.get("name", "")).startswith(sel)):
        sys.stdout.write(s["run"]); sys.exit(0)
sys.exit(3)
'
s3_body() { python3 -I -c "$s3_step_py" "$1" "$2"; } # <file> <step id|name prefix> -> the step's run: text
S3_N=0
s3_run() { # <bodyfile> <realdir> <KEY=VAL>...  -> S3_RC S3_OUT S3_GHO S3_NCALLS
  local body="$1" realdir="$2"; shift 2
  S3_N=$((S3_N + 1)); local r="$S3/rows/r$S3_N"; assert_fixture_dir "$r"; mkdir -p "$r/calls" "$r/rt"
  : > "$r/gho"; : > "$r/summary"
  S3_RC=0
  ( cd "$REPO_ROOT" && env -i PATH="$S3/shim:$realdir" HOME="$r" TMPDIR="$r" RUNNER_TEMP="$r/rt" GITHUB_OUTPUT="$r/gho" GITHUB_STEP_SUMMARY="$r/summary" \
      GITHUB_WORKSPACE="$REPO_ROOT" CALLS_DIR="$r/calls" "$@" \
      "$BASH_BIN" --noprofile --norc -eo pipefail "$body" ) > "$r/out" 2>&1 || S3_RC=$?
  S3_OUT="$r/out"; S3_GHO="$r/gho"; S3_DIR_ROW="$r"
  S3_NCALLS="$(find "$r/calls" -name '*.argv' | wc -l | tr -d ' ')"
}
s3_marker_count() { grep -c '^SOLEUR_CREDENTIAL_REFUSED script=' "$S3_OUT" || true; }
s3_canary_clean() { # the planted canary appears in no captured output, annotation or summary
  ! grep -qF -- "$S3_CANARY" "$S3_OUT" "$S3_GHO" "$S3_DIR_ROW/summary" 2>/dev/null
}
s3_tok_not_in_argv() { # <value>: no recorded argv holds it
  local f; for f in "$S3_DIR_ROW"/calls/*.argv; do [[ -e "$f" ]] || continue; grep -qF -- "$1" < <(tr '\0' '\n' < "$f") && return 1; done; return 0
}
s3_gho_has() { grep -qx -- "$1" "$S3_GHO"; }
s3_argv_has() { grep -qxF -- "$2" < <(tr '\0' '\n' < "$1"); } # <argvfile> <word>: the recorded call carries that exact argument
S3_ACT_PRE=".github/actions/anthropic-preflight/action.yml"
S3_ACT_NOT=".github/actions/notify-ops-email/action.yml"

# ---- instrument controls: the shim records, honours -w/-o, and a run sees the library ----
s3_body "$S3_ACT_PRE" check > "$S3/pre.sh" || fatal "S3 could not extract the anthropic-preflight step"
s3_run "$S3/pre.sh" "$S3/real" ANTHROPIC_API_KEY="$S3_K_ANTH"
[[ "$S3_RC" == 0 && "$S3_NCALLS" == 1 ]] && s3_gho_has "ok=true" || fatal "S3 control: the well-formed anthropic-preflight run is not green under the shim (rc=$S3_RC calls=$S3_NCALLS)"
[[ "$(tr '\0' '\n' < "$S3_DIR_ROW/calls/1.stdin" 2>/dev/null)" == "header = \"x-api-key: ${S3_K_ANTH}\"" ]] || fatal "S3 control: the shim did not record the credential on stdin"
row "S3 control: the real anthropic-preflight body runs under the recording shim; the key reaches stdin as ONE header directive" ok
s3_tok_not_in_argv "$S3_K_ANTH" && row "S3 anthropic-preflight: a well-formed key is absent from the recorded argv" ok || row "S3 anthropic-preflight: a well-formed key is absent from the recorded argv" fail "key found in argv"

# ---- THE POPULATION IS DERIVED from the tree, never counted ----
S3_POP="$(cd "$REPO_ROOT" && python3 -I -c "$s3_pop_py" | sort)"
S3_MANIFEST="$(printf '%s\n' \
  .github/actions/anthropic-preflight/action.yml .github/actions/notify-ops-email/action.yml \
  .github/workflows/board-status-sync.yml .github/workflows/canary-status.yml .github/workflows/git-data-cutover.yml \
  .github/workflows/git-data-rung2-rehearsal.yml .github/workflows/kb-drift-walker.yml .github/workflows/rule-audit.yml \
  .github/workflows/scheduled-inngest-health.yml .github/workflows/scheduled-prod-version-drift.yml \
  .github/workflows/scheduled-terraform-drift.yml .github/workflows/sentry-audit-gate.yml \
  .github/actions/mint-infra-app-token/action.yml .github/workflows/apply-deploy-pipeline-fix.yml \
  .github/workflows/apply-github-infra.yml .github/workflows/apply-inngest-rls.yml \
  .github/workflows/restart-inngest-server.yml .github/workflows/apply-web-platform-infra.yml | sort)"
S3_UNCLASS="$(comm -23 <(printf '%s\n' "$S3_POP") <(printf '%s\n' "$S3_MANIFEST"))"
S3_STALE="$(comm -13 <(printf '%s\n' "$S3_POP") <(printf '%s\n' "$S3_MANIFEST"))"
if [[ -z "$S3_UNCLASS" && -z "$S3_STALE" && -n "$S3_POP" ]]; then
  row "S3 population: every step that sources the library is in the manifest and every manifest member still does ($(printf '%s\n' "$S3_POP" | grep -c .) files)" ok
else
  row "S3 population: the derived set differs from the manifest" fail "unclassified='${S3_UNCLASS//$'\n'/,}' stale='${S3_STALE//$'\n'/,}'"
fi
# Rule E (the lint decides what an argv credential is): every member is clean. S3 declared one held-back site (the
# scheduled-inngest-health probe step); S4 converted it, so the exception is gone and a re-added argv site anywhere turns this red.
S3_E_BAD=""
for f in $S3_POP; do
  n="$(cd "$REPO_ROOT" && python3 scripts/lint-shell-trace-credential-refusal.py "$f" 2>&1 | grep -c 'credential header on curl argv\|HMAC\|-hmac' || true)"
  if [[ "$n" != 0 ]]; then S3_E_BAD+=" $f=$n"; fi
done
if [[ -z "$S3_E_BAD" ]]; then
  row "S3 Rule E: every member is clean (the inngest-health probe left its held-back state in S4)" ok
else
  row "S3 Rule E: members carry argv credentials" fail "bad=$S3_E_BAD"
fi

# ---- structural rows over the derived population (statement-level: continuation lines are joined) ----
s3_statements_py='
import sys, yaml
f = sys.argv[1]
d = yaml.safe_load(open(f))
steps = []
if isinstance(d.get("runs"), dict):
    steps = d["runs"].get("steps") or []
else:
    for j in (d.get("jobs") or {}).values():
        steps += (j.get("steps") or []) if isinstance(j, dict) else []
for i, s in enumerate(steps):
    run = s.get("run") if isinstance(s, dict) else None
    if not isinstance(run, str) or "bc_curl" not in run and "scripts/lib/bearer-curl.sh" not in run:
        continue
    text = run.replace("\\\n", " ")
    for ln in text.split("\n"):
        print("%d\t%s" % (i, ln))
'
# The D2/D3/D5 predicates, as functions over ONE line, so the live sweep below and the fixture table after it run the
# SAME patterns (a pattern nothing ever fed a known positive and a known negative is not a control).
S3_D2_RE='(-H|--header) *["'"'"']?(Authorization|Proxy-Authorization|x-api-key|api-key|apikey|private-token|x-auth-token|x-access-token|Cookie|X-Signature-256|X-Hub-Signature|CF-Access-Client|X-Soleur-Kb-Drift-Signature)'
S3_D3_RE='(2|&)> *(/dev/null|&-)|>& *(/dev/null|-)|> */dev/null +2>&1'
S3_D5_RE='(\[\[? [^]]*(-eq|-ne|==|!=|=) *"?2"? *\]\]?|\(\([^)]*(==|!=|-eq|-ne) *2([^0-9A-Za-z_]|$)[^)]*\)\)|case .*(\$\?|\$\{?[A-Za-z_]*[rR][cC]))'
s3_d2_hit() { grep -qiE -- "$S3_D2_RE" <<<"$1"; }
s3_d3_hit() { grep -qE -- "$S3_D3_RE" <<<"$1"; }
s3_d5_hit() { grep -qE -- "$S3_D5_RE" <<<"$1" && grep -qE '(_RC|rc|\$\?)' <<<"$1" && ! grep -q 'exit 2' <<<"$1"; }
S3_PRED_BAD=""
s3_pred_check() { # <predicate> <HIT|MISS> <line>
  local want="$2" got=MISS
  "$1" "$3" && got=HIT
  [[ "$got" == "$want" ]] || S3_PRED_BAD+=" [$1 wanted $want for: ${3:0:48}]"
}
for l in "bc_curl x 'A:B:C' -- -H 'Authorization: Bearer z' url" 'bc_curl x A -- -H "Authorization: z" url' "bc_curl x A -- --header 'x-api-key: z' url" 'bc_curl x A -- -H "Cookie: a" url' "bc_curl x A -- -H 'Private-Token: z' url"; do s3_pred_check s3_d2_hit HIT "$l"; done
for l in 'bc_curl x A -- -H "Content-Type: application/json" url' "bc_curl x A -- -H 'Accept: x' url" 'bc_curl x A -- -o /dev/null -w %{http_code} url'; do s3_pred_check s3_d2_hit MISS "$l"; done
for l in 'bc_curl x A -- -sS url 2>/dev/null' 'bc_curl x A -- -sS url 2> /dev/null' 'bc_curl x A -- -sS url &>/dev/null' 'bc_curl x A -- -sS url >/dev/null 2>&1' 'bc_curl x A -- -sS url 2>&-'; do s3_pred_check s3_d3_hit HIT "$l"; done
for l in "bc_curl x A -- -sS -o /dev/null -w '%{http_code}' url" 'bc_curl x A -- -sS url 2>"$LOG"' 'bc_curl x A -- -sS url 2>&1'; do s3_pred_check s3_d3_hit MISS "$l"; done
for l in '[[ "$rc" -eq 2 ]]' '[ "$rc" = 2 ]' '[ "$rc" = "2" ]' '(( rc == 2 ))' '(( $rc == 2 ))' '(( rc != 0 && rc == 2 ))' 'case "$rc" in' '[[ "$?" -ne 2 ]]'; do s3_pred_check s3_d5_hit HIT "$l"; done
for l in '[[ "$rc" -eq 0 ]]' '[[ "$rc" -eq 20 ]]' '[[ "$rc" -eq 2 ]] && exit 2' 'echo "got 2 files"' '(( rc == 0 ))'; do s3_pred_check s3_d5_hit MISS "$l"; done
[[ -z "$S3_PRED_BAD" ]] && row "S3 structure: the D2/D3/D5 sweep predicates flag every known-bad spelling (quotes, spacing, the &> and >&2 forms, bracket and arithmetic and case forms) and spare the benign neighbours" ok || row "S3 structure: a D2/D3/D5 predicate misjudges a fixture" fail "$S3_PRED_BAD"
S3_SRC_BAD=""; S3_ARGV_BAD=""; S3_STDERR_BAD=""; S3_HMAC_BAD=""; S3_PATH_BAD=""; S3_RC2_BAD=""; S3_NAME_BAD=""; S3_CALLS=0
for f in $S3_POP; do
  stm="$(cd "$REPO_ROOT" && python3 -I -c "$s3_statements_py" "$f")"
  # D1 the library is sourced (exact pinned form) before the first bc_curl/bc_ok/bc_hmac/bc_refuse of the same step
  steps_with_calls="$(printf '%s\n' "$stm" | grep -E 'bc_(curl|ok|refuse|hmac_sha256_hex)[ "$]' | cut -f1 | sort -u)"
  for st in $steps_with_calls; do
    first_use="$(printf '%s\n' "$stm" | awk -F'\t' -v s="$st" '$1==s && $2 !~ /^[[:space:]]*#/ && $2 ~ /bc_(curl|ok|refuse|hmac_sha256_hex)[ "$]/ && $2 !~ /source / {print NR; exit}')"
    first_src="$(printf '%s\n' "$stm" | awk -F'\t' -v s="$st" '$1==s && $2 ~ /source / && $2 ~ /scripts\/lib\/bearer-curl\.sh/ {print NR; exit}')"
    [[ -n "$first_src" && -n "$first_use" && "$first_src" -le "$first_use" ]] || S3_SRC_BAD+=" $f#$st"
  done
  S3_CALLS=$((S3_CALLS + $(printf '%s\n' "$stm" | grep -cE '(^|[^_A-Za-z])bc_curl [A-Za-z]' || true)))
  # the source token has exactly one accepted spelling
  while IFS= read -r l; do
    grep -qE 'source "\$\{GITHUB_WORKSPACE:\?\}/scripts/lib/bearer-curl\.sh"|source "\$GITHUB_WORKSPACE/scripts/lib/bearer-curl\.sh"|source "\$\{GITHUB_WORKSPACE\}/scripts/lib/bearer-curl\.sh"' <<<"$l" || S3_PATH_BAD+=" $f"
  done < <(printf '%s\n' "$stm" | cut -f2 | grep -E '^[[:space:]]*(if .*)?source .*bearer-curl\.sh|\|\| ! source|! source .*bearer-curl' || true)
  # D2 no credential header literal inside a bc_curl statement (it would be a second, argv copy), and no -H credential on a curl line
  while IFS= read -r l; do s3_d2_hit "$l" && S3_ARGV_BAD+=" $f"; done < <(printf '%s\n' "$stm" | cut -f2 | grep -E '(^|[^_A-Za-z])bc_curl ' || true)
  # D3 no stderr suppression on a bc_curl statement
  # (the statement is the bc_curl call itself: a later pipe stage such as `| jq ... 2>/dev/null` is not its stderr)
  while IFS= read -r l; do s3_d3_hit "$l" && S3_STDERR_BAD+=" $f"; done < <(printf '%s\n' "$stm" | cut -f2 | grep -E '(^|[^_A-Za-z])bc_curl ' | sed -E 's/.*(bc_curl .*)/\1/; s/ \|\| .*//; s/ \| .*//' || true)
  # D4 no openssl -hmac in a converted file (no exception remains: the probe step converted in S4)
  grep -qE 'openssl dgst .*-hmac' < <(grep -v '^[[:space:]]*#' "$REPO_ROOT/$f") && S3_HMAC_BAD+=" $f"

  # D5 no converted statement branches on rc == 2 (curl's own init-failure code; the marker is the discriminator)
  while IFS= read -r l; do s3_d5_hit "$l" && S3_RC2_BAD+=" $f"; done < <(printf '%s\n' "$stm" | cut -f2 || true)
  # D6 every bc_curl / bc_refuse names ITS OWN file in the marker (a copy-pasted donor name makes the marker unfindable)
  want_name="$(basename "$f" .yml)"; [[ "$(basename "$f")" == action.yml ]] && want_name="$(basename "$(dirname "$f")")"
  while IFS= read -r nm; do [[ "$nm" == "$want_name" ]] || S3_NAME_BAD+=" $f:$nm"; done < <(printf '%s\n' "$stm" | cut -f2 | grep -v '^[[:space:]]*#' | grep -oE '(^|[^_A-Za-z])bc_(curl|refuse)[ ]+[A-Za-z0-9._-]+' | awk '{print $NF}' | sort -u || true)
done
[[ -z "$S3_SRC_BAD" ]] && row "S3 structure: every step that calls the library sources it first (exact pinned source form)" ok || row "S3 structure: a step uses the library before it sources it" fail "$S3_SRC_BAD"
[[ -z "$S3_PATH_BAD" ]] && row "S3 structure: the library is sourced only from the job's own workspace (\${GITHUB_WORKSPACE})" ok || row "S3 structure: a non-workspace source path" fail "$S3_PATH_BAD"
[[ -z "$S3_ARGV_BAD" ]] && row "S3 structure: no bc_curl statement repeats a credential header on its own argument list" ok || row "S3 structure: a bc_curl statement carries -H credential" fail "$S3_ARGV_BAD"
[[ -z "$S3_STDERR_BAD" ]] && row "S3 structure: no bc_curl statement discards stderr (the refusal marker must stay visible)" ok || row "S3 structure: 2>/dev/null on bc_curl" fail "$S3_STDERR_BAD"
[[ -z "$S3_NAME_BAD" ]] && row "S3 structure: every bc_curl / bc_refuse call names its own file in the marker" ok || row "S3 structure: a marker names another file" fail "$S3_NAME_BAD"
[[ -z "$S3_HMAC_BAD" ]] && row "S3 structure: no converted file computes an HMAC with the key on openssl's argv" ok || row "S3 structure: openssl -hmac remains" fail "$S3_HMAC_BAD"
[[ -z "$S3_RC2_BAD" ]] && row "S3 structure: no converted statement branches on rc == 2 (the marker is the discriminator)" ok || row "S3 structure: a site branches on rc 2" fail "$S3_RC2_BAD"
# The floor is the realized count (the YAML population after S4 converted the five more files and the inngest-health probe). BOTH operands are literals above the `if`.
S3_CALLS_FLOOR=41
if [[ "$S3_CALLS" -ge "$S3_CALLS_FLOOR" ]]; then row "S3 structure: the derived population holds >= $S3_CALLS_FLOOR bc_curl call statements ($S3_CALLS)" ok; else row "S3 structure: population floor" fail "only $S3_CALLS bc_curl statements derived (floor $S3_CALLS_FLOOR)"; fi

# ---- anthropic-preflight (the soft-skip trap: a refusal must stay RED) ----
s3_run "$S3/pre.sh" "$S3/real" ANTHROPIC_API_KEY="${S3_CANARY}\"x"
if [[ "$S3_RC" == 1 && "$S3_NCALLS" == 0 && "$(s3_marker_count)" == 1 ]] && ! s3_gho_has "ok=false" && ! s3_gho_has "ok=true" && s3_canary_clean; then
  row "S3 anthropic-preflight: a malformed key exits 1 (red), makes zero requests, prints the marker once, and never writes ok=false (the soft-skip arm)" ok
else row "S3 anthropic-preflight: malformed key" fail "rc=$S3_RC calls=$S3_NCALLS markers=$(s3_marker_count) gho=$(tr '\n' ' ' < "$S3_GHO")"; fi
s3_run "$S3/pre.sh" "$S3/real" ANTHROPIC_API_KEY=""
[[ "$S3_RC" == 1 && "$S3_NCALLS" == 0 ]] && grep -q '^::error::ANTHROPIC_API_KEY not set' "$S3_OUT" && row "S3 anthropic-preflight: an empty key keeps its own message and exits 1" ok || row "S3 anthropic-preflight: empty key" fail "rc=$S3_RC"
s3_run "$S3/pre.sh" "$S3/real" ANTHROPIC_API_KEY="$S3_K_ANTH" GITHUB_WORKSPACE="$S3/rows"
[[ "$S3_RC" == 1 && "$S3_NCALLS" == 0 ]] && grep -q '^::error::scripts/lib/bearer-curl.sh could not be loaded' "$S3_OUT" && row "S3 anthropic-preflight: library absent from the checkout is a hard failure with no request and no argv fallback" ok || row "S3 anthropic-preflight: library absent" fail "rc=$S3_RC calls=$S3_NCALLS"
s3_run "$S3/pre.sh" "$S3/real" ANTHROPIC_API_KEY="$S3_K_ANTH" SHIM_CODE=503
[[ "$S3_RC" == 0 && "$S3_NCALLS" == 1 ]] && s3_gho_has "ok=false" && row "S3 anthropic-preflight: a 5xx still soft-skips (ok=false, exit 0): the transient arm is unchanged" ok || row "S3 anthropic-preflight: 5xx" fail "rc=$S3_RC"
s3_run "$S3/pre.sh" "$S3/real" ANTHROPIC_API_KEY="$S3_K_ANTH" SHIM_CODE=000 SHIM_RC=7
[[ "$S3_RC" == 1 ]] && grep -q 'Unexpected Anthropic preflight response' "$S3_OUT" && row "S3 anthropic-preflight: a transport failure keeps the documented 000000 quirk (red), not a refusal" ok || row "S3 anthropic-preflight: transport failure" fail "rc=$S3_RC"

# ---- notify-ops-email (caller contract: warn-only except a missing key / library) ----
s3_body "$S3_ACT_NOT" send > "$S3/not.sh" || fatal "S3 could not extract the notify-ops-email step"
s3_run "$S3/not.sh" "$S3/real" RESEND_API_KEY="synth-resend_key0123" EMAIL_SUBJECT=s EMAIL_BODY=b
[[ "$S3_RC" == 0 && "$S3_NCALLS" == 1 ]] && s3_gho_has "sent=true" && row "S3 notify-ops-email: a well-formed key sends (sent=true) with the key on stdin only" ok || row "S3 notify-ops-email: well-formed" fail "rc=$S3_RC calls=$S3_NCALLS"
s3_tok_not_in_argv "synth-resend_key0123" && row "S3 notify-ops-email: the key is absent from the recorded argv" ok || row "S3 notify-ops-email: key in argv" fail ""
s3_run "$S3/not.sh" "$S3/real" RESEND_API_KEY="${S3_CANARY}\"x" EMAIL_SUBJECT=s EMAIL_BODY=b
if [[ "$S3_RC" == 0 && "$S3_NCALLS" == 0 && "$(s3_marker_count)" == 1 ]] && s3_gho_has "sent=false" && grep -q '^::error::RESEND_API_KEY failed the token-shape guard' "$S3_OUT" && s3_canary_clean; then
  row "S3 notify-ops-email: a malformed key is an ::error:: annotation with the marker, sent=false, exit 0 and NO request (caller contract kept)" ok
else row "S3 notify-ops-email: malformed key" fail "rc=$S3_RC calls=$S3_NCALLS markers=$(s3_marker_count)"; fi
s3_run "$S3/not.sh" "$S3/real" RESEND_API_KEY="synth-resend_key0123" EMAIL_SUBJECT=s EMAIL_BODY=b GITHUB_WORKSPACE="$S3/rows"
[[ "$S3_RC" == 1 && "$S3_NCALLS" == 0 ]] && s3_gho_has "sent=false" && row "S3 notify-ops-email: library absent is a hard failure (exit 1, sent=false, no request)" ok || row "S3 notify-ops-email: library absent" fail "rc=$S3_RC"
s3_run "$S3/not.sh" "$S3/real" RESEND_API_KEY="" EMAIL_SUBJECT=s EMAIL_BODY=b
[[ "$S3_RC" == 1 && "$S3_NCALLS" == 0 ]] && s3_gho_has "sent=false" && row "S3 notify-ops-email: a MISSING key keeps its exit 1" ok || row "S3 notify-ops-email: missing key" fail "rc=$S3_RC"

# ---- canary-status: the HMAC representative (key off openssl's argv, python3 absent, empty and hostile values) ----
s3_body ".github/workflows/canary-status.yml" "Read /hooks/deploy-status" > "$S3/canary.sh" || fatal "S3 could not extract the canary-status step"
CANARY_BODY='{"sandbox_canary":{"verdict":"pass","consecutive_pass":5,"first_pass_at":1,"checked_at":86401,"sdk_version":"1.0.0"}}'
s3_run "$S3/canary.sh" "$S3/real" WEBHOOK_DEPLOY_SECRET="synth-webhook-key-0123" CF_ACCESS_CLIENT_ID="synthid.access" CF_ACCESS_CLIENT_SECRET="synthsecret0123" SHIM_BODY="$CANARY_BODY"
S3_WANT_SIG="$(printf '' | "$REAL_OSSL" dgst -sha256 -hmac "synth-webhook-key-0123" | sed 's/.*= //')"
if [[ "$S3_RC" == 0 && "$S3_NCALLS" == 1 && "$(grep -c . "$S3_DIR_ROW/calls/1.stdin")" == 3 ]] && [[ "$(sed -n 1p "$S3_DIR_ROW/calls/1.stdin")" == "header = \"X-Signature-256: sha256=$S3_WANT_SIG\"" ]]; then
  row "S3 canary-status: the signature equals the independent openssl digest and rides stdin with the Cloudflare Access pair (three directives)" ok
else row "S3 canary-status: well-formed run" fail "rc=$S3_RC calls=$S3_NCALLS"; fi
if s3_tok_not_in_argv "$S3_WANT_SIG" && s3_tok_not_in_argv "synth-webhook-key-0123" && s3_tok_not_in_argv "synthsecret0123"; then row "S3 canary-status: neither the HMAC key, the signature nor the Cloudflare Access secret is in any recorded argv" ok; else row "S3 canary-status: credential in argv" fail ""; fi
s3_run "$S3/canary.sh" "$S3/real-nopy" WEBHOOK_DEPLOY_SECRET="synth-webhook-key-0123" CF_ACCESS_CLIENT_ID="synthid.access" CF_ACCESS_CLIENT_SECRET="synthsecret0123"
if [[ "$S3_RC" == 1 && "$S3_NCALLS" == 0 && "$(s3_marker_count)" == 0 ]] && grep -q '^::error::the request signature could not be computed' "$S3_OUT"; then
  row "S3 canary-status: python3 absent -> the arm's own red verdict (::error::, no credential-refusal marker: the key was never judged), zero requests, no mute abort" ok
else row "S3 canary-status: python3 absent" fail "rc=$S3_RC calls=$S3_NCALLS markers=$(s3_marker_count)"; fi
s3_run "$S3/canary.sh" "$S3/real" WEBHOOK_DEPLOY_SECRET="synth-webhook-key-0123" CF_ACCESS_CLIENT_ID="${S3_CANARY}\"x" CF_ACCESS_CLIENT_SECRET="synthsecret0123"
if [[ "$S3_RC" != 0 && "$S3_NCALLS" == 0 && "$(s3_marker_count)" == 1 ]] && s3_canary_clean; then
  row "S3 canary-status: a hostile Cloudflare Access id is refused (red, zero requests, marker once, canary absent)" ok
else row "S3 canary-status: hostile CF id" fail "rc=$S3_RC calls=$S3_NCALLS markers=$(s3_marker_count)"; fi
s3_run "$S3/canary.sh" "$S3/real" WEBHOOK_DEPLOY_SECRET="synth-webhook-key-0123" CF_ACCESS_CLIENT_ID="synthid.access" CF_ACCESS_CLIENT_SECRET="synthsecret0123" SHIM_CODE=403
[[ "$S3_RC" == 1 ]] && grep -q '^::error::deploy-status returned HTTP 403' "$S3_OUT" && row "S3 canary-status: a non-200 keeps its verdict (::error:: HTTP 403, exit 1)" ok || row "S3 canary-status: 403" fail "rc=$S3_RC"

# ---- kb-drift-walker: the HMAC moved from an inline python3 -c (key exported) to the library (key not exported) ----
# The live step text is executed with two edits that only remove the repo walker and the host-wide /tmp path; each edit is
# asserted to have landed. doppler is a stub that answers by secret NAME.
mkdir -p "$S3/kbstub"
cat > "$S3/kbstub/doppler" <<'KBDOPPLER'
#!/usr/bin/env bash
case "$*" in
  *KB_DRIFT_INGEST_SIGNING_KEY*) [[ "${KB_DOPPLER_FAIL:-}" == 1 ]] && exit 1; printf '%s' "${KB_KEY-}" ;;
  *KB_DRIFT_INGEST_URL*) printf '%s' "https://ingest.invalid/kb" ;;
  *) exit 64 ;;
esac
KBDOPPLER
chmod +x "$S3/kbstub/doppler"
s3_body ".github/workflows/kb-drift-walker.yml" "Run walker" > "$S3/kb.live.sh" || fatal "S3 could not extract the kb-drift-walker step"
KB_FINDINGS='{"findings":[{"id":"synthetic-1"}]}'
sed -e "s#^FINDINGS_JSON=.*#FINDINGS_JSON='$KB_FINDINGS'#" -e 's#/tmp/ingest\.out#"$RUNNER_TEMP"/ingest.out#g' "$S3/kb.live.sh" > "$S3/kb.sh"
if ! grep -q "^FINDINGS_JSON='" "$S3/kb.sh" || grep -q 'scripts/kb-drift-walker.sh' "$S3/kb.sh" || grep -q '/tmp/ingest.out' "$S3/kb.sh"; then fatal "S3 kb-drift-walker row edits did not land"; fi
KB_REALDIR="$S3/kbstub:$S3/real"
KB_WANT_SIG="$(printf '%s' "$KB_FINDINGS" | "$REAL_OSSL" dgst -sha256 -hmac "synth-kb-signing-key-0123" | sed 's/.*= //')"
s3_run "$S3/kb.sh" "$KB_REALDIR" KB_KEY="synth-kb-signing-key-0123"
if [[ "$S3_RC" == 0 && "$S3_NCALLS" == 1 && "$(tr '\0' '\n' < "$S3_DIR_ROW/calls/1.stdin")" == "header = \"X-Soleur-Kb-Drift-Signature: sha256=$KB_WANT_SIG\"" ]]; then
  row "S3 kb-drift-walker: the signature equals the independent openssl digest and is the only line on the stdin config" ok
else row "S3 kb-drift-walker: well-formed run" fail "rc=$S3_RC calls=$S3_NCALLS"; fi
if s3_tok_not_in_argv "$KB_WANT_SIG" && s3_tok_not_in_argv "synth-kb-signing-key-0123"; then row "S3 kb-drift-walker: neither the signing key nor the signature is in any recorded argv" ok; else row "S3 kb-drift-walker: credential in argv" fail ""; fi
s3_run "$S3/kb.sh" "$KB_REALDIR" KB_KEY=""
if [[ "$S3_RC" == 1 && "$S3_NCALLS" == 0 && "$(s3_marker_count)" == 0 ]] && grep -q '^::error::the ingest signature could not be computed' "$S3_OUT"; then
  row "S3 kb-drift-walker: an EMPTY signing key is the arm's own red verdict (::error::, exit 1), zero requests (no mute abort)" ok
else row "S3 kb-drift-walker: empty key" fail "rc=$S3_RC calls=$S3_NCALLS"; fi
s3_run "$S3/kb.sh" "$S3/kbstub:$S3/real-nopy" KB_KEY="synth-kb-signing-key-0123"
if [[ "$S3_RC" == 1 && "$S3_NCALLS" == 0 ]] && grep -q '^::error::the ingest signature could not be computed' "$S3_OUT"; then
  row "S3 kb-drift-walker: python3 absent is the same red verdict with zero requests" ok
else row "S3 kb-drift-walker: python3 absent" fail "rc=$S3_RC calls=$S3_NCALLS"; fi
s3_run "$S3/kb.sh" "$KB_REALDIR" KB_KEY="synth-kb-signing-key-0123" KB_DOPPLER_FAIL=1
if [[ "$S3_RC" != 0 && "$S3_NCALLS" == 0 ]]; then
  row "S3 kb-drift-walker: a failing doppler read aborts the step before any request (the key is no longer swallowed into an empty export)" ok
else row "S3 kb-drift-walker: doppler failure" fail "rc=$S3_RC calls=$S3_NCALLS"; fi
if ! grep -qE '^[[:space:]]*export[[:space:]]+KB_DRIFT_INGEST_SIGNING_KEY' < <(grep -v '^[[:space:]]*#' "$S3/kb.live.sh"); then
  row "S3 kb-drift-walker: the signing key is not exported (no other child of the step inherits it)" ok
else row "S3 kb-drift-walker: the signing key is exported" fail ""; fi

# ---- composites: the branches after the send (non-2xx, billing 400, a real transport failure) ----
s3_run "$S3/not.sh" "$S3/real" RESEND_API_KEY="synth-resend_key0123" EMAIL_SUBJECT=s EMAIL_BODY=b SHIM_CODE=500
if [[ "$S3_RC" == 0 && "$S3_NCALLS" == 1 ]] && s3_gho_has "sent=false" && grep -q '^::warning::Email notification failed (HTTP 500)' "$S3_OUT"; then
  row "S3 notify-ops-email: a non-2xx is a warning with sent=false and exit 0 (the caller contract)" ok
else row "S3 notify-ops-email: non-2xx" fail "rc=$S3_RC calls=$S3_NCALLS"; fi
s3_run "$S3/not.sh" "$S3/real" RESEND_API_KEY="synth-resend_key0123" EMAIL_SUBJECT=s EMAIL_BODY=b SHIM_CODE=000 SHIM_RC=7
if [[ "$S3_RC" == 0 ]] && s3_gho_has "sent=false" && grep -q '^::warning::Email notification failed' "$S3_OUT"; then
  row "S3 notify-ops-email: a transport failure is the same warning, sent=false, exit 0" ok
else row "S3 notify-ops-email: transport failure" fail "rc=$S3_RC"; fi
s3_run "$S3/pre.sh" "$S3/real" ANTHROPIC_API_KEY="$S3_K_ANTH"
[[ "$S3_RC" == 0 && "$S3_NCALLS" == 1 ]] && s3_gho_has "ok=true" && row "S3 anthropic-preflight: a 200 is ok=true" ok || row "S3 anthropic-preflight: 200" fail "rc=$S3_RC calls=$S3_NCALLS"
s3_run "$S3/pre.sh" "$S3/real" ANTHROPIC_API_KEY="$S3_K_ANTH" SHIM_CODE=400 SHIM_BODY='{"error":{"message":"Your credit balance is too low"}}'
[[ "$S3_RC" == 0 ]] && s3_gho_has "ok=false" && row "S3 anthropic-preflight: a billing 400 soft-skips (ok=false, exit 0)" ok || row "S3 anthropic-preflight: billing 400" fail "rc=$S3_RC"

# ---- sentry-audit-gate: the red-class representative ----
s3_body ".github/workflows/sentry-audit-gate.yml" "Verify token scope" > "$S3/sentry.sh" || fatal "S3 could not extract the sentry-audit-gate step"
S3_SENTRY_ENV=(SENTRY_ORG=synthorg SENTRY_API_HOST=synthorg.sentry.io)
s3_run "$S3/sentry.sh" "$S3/real" "${S3_SENTRY_ENV[@]}" SENTRY_AUTH_TOKEN="synth-sentry_token0123"
if [[ "$S3_RC" == 0 && "$S3_NCALLS" == 1 ]] && s3_argv_has "$S3_DIR_ROW/calls/1.argv" '--proto' && s3_argv_has "$S3_DIR_ROW/calls/1.argv" '=https' && s3_argv_has "$S3_DIR_ROW/calls/1.argv" '-g' && s3_tok_not_in_argv "synth-sentry_token0123" \
   && [[ "$(tr '\0' '\n' < "$S3_DIR_ROW/calls/1.stdin" 2>/dev/null)" == 'header = "Authorization: Bearer synth-sentry_token0123"' ]]; then
  row "S3 sentry-audit-gate: a good token passes; the protocol pin and -g survive and the token is on stdin only" ok
else row "S3 sentry-audit-gate: well-formed" fail "rc=$S3_RC calls=$S3_NCALLS"; fi
s3_run "$S3/sentry.sh" "$S3/real" "${S3_SENTRY_ENV[@]}" SENTRY_AUTH_TOKEN="${S3_CANARY}\"x"
if [[ "$S3_RC" == 1 && "$S3_NCALLS" == 0 && "$(s3_marker_count)" == 1 ]] && grep -q '^::error::SENTRY_AUTH_TOKEN scope check failed (HTTP 000' "$S3_OUT" && s3_canary_clean; then
  row "S3 sentry-audit-gate: a malformed token stays RED with the old annotation, the marker once, zero requests, canary absent" ok
else row "S3 sentry-audit-gate: malformed token" fail "rc=$S3_RC calls=$S3_NCALLS markers=$(s3_marker_count)"; fi
s3_run "$S3/sentry.sh" "$S3/real" "${S3_SENTRY_ENV[@]}" SENTRY_AUTH_TOKEN="synth-sentry_token0123" SHIM_CODE=403
[[ "$S3_RC" == 1 ]] && grep -q 'scope check failed (HTTP 403' "$S3_OUT" && row "S3 sentry-audit-gate: a non-200 keeps its verdict (HTTP 403, exit 1)" ok || row "S3 sentry-audit-gate: 403" fail "rc=$S3_RC"

# ---- scheduled-prod-version-drift: the warning/annotation-class representative (and B15c's position) ----
s3_body ".github/workflows/scheduled-prod-version-drift.yml" "Email ops on first detection" > "$S3/drift.sh" || fatal "S3 could not extract the drift email step"
S3_DRIFT_ENV=(DETAIL=d MISSING_COUNT=1 RUN_URL=https://example.invalid/run)
s3_run "$S3/drift.sh" "$S3/real" "${S3_DRIFT_ENV[@]}" RESEND_API_KEY="synth-resend_key0123"
[[ "$S3_RC" == 0 && "$S3_NCALLS" == 1 ]] && s3_gho_has "delivered=1" && [[ "$(tr '\0' '\n' < "$S3_DIR_ROW/calls/1.stdin" 2>/dev/null)" == 'header = "Authorization: Bearer synth-resend_key0123"' ]] && row "S3 prod-version-drift: a well-formed key delivers (delivered=1) with the key on stdin only" ok || row "S3 prod-version-drift: well-formed" fail "rc=$S3_RC calls=$S3_NCALLS"
s3_run "$S3/drift.sh" "$S3/real" "${S3_DRIFT_ENV[@]}" RESEND_API_KEY="${S3_CANARY}\"x"
if [[ "$S3_RC" == 0 && "$S3_NCALLS" == 0 && "$(s3_marker_count)" == 1 ]] && s3_gho_has "delivered=0" && grep -q '^::error::Drift email FAILED (HTTP 000)' "$S3_OUT" && s3_canary_clean; then
  row "S3 prod-version-drift: a malformed key reads as the old delivery failure (::error:: HTTP 000, delivered=0, exit 0) with the marker once and zero requests" ok
else row "S3 prod-version-drift: malformed key" fail "rc=$S3_RC calls=$S3_NCALLS markers=$(s3_marker_count)"; fi
s3_run "$S3/drift.sh" "$S3/real" "${S3_DRIFT_ENV[@]}" RESEND_API_KEY="synth-resend_key0123" GITHUB_WORKSPACE="$S3/rows"
[[ "$S3_RC" == 1 && "$S3_NCALLS" == 0 ]] && s3_gho_has "delivered=0" && row "S3 prod-version-drift: library absent is a hard failure (exit 1, delivered=0)" ok || row "S3 prod-version-drift: library absent" fail "rc=$S3_RC"

# ---- recorded slices (the full step needs a runner): each pinned to the live text by a verbatim-substring row ----
s3_slice() { # <file> <step-prefix> <start-regex> <end-regex> -> prints the inclusive line slice of the step's run text
  # patterns travel by ENVIRON: `awk -v` would process the backslash escapes in them
  s3_body "$1" "$2" | S3_AWK_S="$3" S3_AWK_E="$4" awk '$0 ~ ENVIRON["S3_AWK_S"] {f=1} f {print} f && $0 ~ ENVIRON["S3_AWK_E"] {exit}'
}
S3_CUT_SLICE="$(s3_slice .github/workflows/git-data-cutover.yml "Flip preconditions" 'code="\$\(bc_curl git-data-cutover' '^\[\[ "\$code" == "200" \]\]')"
S3_CUT_LIVE="$(s3_body .github/workflows/git-data-cutover.yml "Flip preconditions")"
if [[ -n "$S3_CUT_SLICE" && "$S3_CUT_LIVE" == *"$S3_CUT_SLICE"* && "$(printf '%s\n' "$S3_CUT_SLICE" | grep -c .)" -ge 3 && "$(printf '%s\n' "$S3_CUT_SLICE" | grep -c .)" -le 6 ]]; then row "S3 cutover flip-precondition slice: extracted from the live step text ($(printf '%s\n' "$S3_CUT_SLICE" | grep -c .) lines)" ok; else row "S3 cutover flip-precondition slice: drifted from the live step" fail "slice lines=$(printf '%s\n' "$S3_CUT_SLICE" | grep -c .)"; fi
{ printf 'fail() { echo "VERDICT=$1"; exit 1; }\nhost="https://sentry.invalid"\nsource "${GITHUB_WORKSPACE:?}/scripts/lib/bearer-curl.sh" || fail lib_missing "x"\n'; printf '%s\n' "$S3_CUT_SLICE"; printf 'echo REACHED_200\n'; } > "$S3/cut.sh"
s3_run "$S3/cut.sh" "$S3/real" SENTRY_ACTIONS_RO_TOKEN="${S3_CANARY}\"x"
if [[ "$S3_RC" == 1 && "$S3_NCALLS" == 0 && "$(s3_marker_count)" == 1 ]] && grep -qx 'VERDICT=pin_fault_paging_absent' "$S3_OUT" && s3_canary_clean; then
  row "S3 cutover flip precondition: a malformed read token fails CLOSED with the old verdict (pin_fault_paging_absent), the marker VISIBLE (stderr no longer discarded) and zero requests" ok
else row "S3 cutover flip precondition: malformed token" fail "rc=$S3_RC calls=$S3_NCALLS markers=$(s3_marker_count)"; fi
s3_run "$S3/cut.sh" "$S3/real" SENTRY_ACTIONS_RO_TOKEN="synth-sentry_ro0123"
[[ "$S3_RC" == 0 ]] && grep -qx 'REACHED_200' "$S3_OUT" && s3_tok_not_in_argv "synth-sentry_ro0123" && [[ "$(tr '\0' '\n' < "$S3_DIR_ROW/calls/1.stdin" 2>/dev/null)" == 'header = "Authorization: Bearer synth-sentry_ro0123"' ]] && row "S3 cutover flip precondition: a well-formed token reaches the 200 branch, token on stdin only" ok || row "S3 cutover flip precondition: well-formed" fail "rc=$S3_RC"

S3_CEN_SLICE="$(s3_slice .github/workflows/scheduled-inngest-health.yml "Census tunnel connectors" 'TUNNEL_ID=\$\(bc_curl' '^fi$')"
S3_CEN_LIVE="$(s3_body .github/workflows/scheduled-inngest-health.yml "Census tunnel connectors")"
if [[ -n "$S3_CEN_SLICE" && "$S3_CEN_LIVE" == *"$S3_CEN_SLICE"* && "$(printf '%s\n' "$S3_CEN_SLICE" | grep -c .)" -ge 5 && "$(printf '%s\n' "$S3_CEN_SLICE" | grep -c .)" -le 12 ]]; then row "S3 inngest-health census slice: extracted from the live step text ($(printf '%s\n' "$S3_CEN_SLICE" | grep -c .) lines)" ok; else row "S3 inngest-health census slice: drifted from the live step" fail "slice lines=$(printf '%s\n' "$S3_CEN_SLICE" | grep -c .)"; fi
{ printf 'set -euo pipefail\nsource "${GITHUB_WORKSPACE:?}/scripts/lib/bearer-curl.sh"\nCF_ACCOUNT_ID=acct\n'; printf '%s\n' "$S3_CEN_SLICE"; printf 'echo REACHED_NEXT\n'; } > "$S3/cen.sh"
s3_run "$S3/cen.sh" "$S3/real" CF_API_TOKEN="${S3_CANARY}\"x"
if [[ "$S3_RC" == 0 && "$S3_NCALLS" == 0 && "$(s3_marker_count)" == 1 ]] && s3_gho_has "verdict=census_unavailable" && ! grep -qx 'REACHED_NEXT' "$S3_OUT"; then
  row "S3 inngest-health census: a malformed Cloudflare token is the SOFT census_unavailable verdict (exit 0), marker visible, zero requests" ok
else row "S3 inngest-health census: malformed token" fail "rc=$S3_RC calls=$S3_NCALLS markers=$(s3_marker_count)"; fi

# ---- Better Stack reader callers (#9757): the reader's refusal marker reaches the run log, with or without the classifier ----
mkdir -p "$S3/ihws/scripts/lib" "$S3/ihstub" "$S3/ihws-nolib/scripts"
cat > "$S3/ihws/scripts/betterstack-query.sh" <<'IHREADER'
#!/usr/bin/env bash
printf 'SOLEUR_CREDENTIAL_REFUSED script=betterstack-query reason=token_shape\nbetterstack-query: a credential was refused\n' >&2
exit 2
IHREADER
cp "$S3/ihws/scripts/betterstack-query.sh" "$S3/ihws-nolib/scripts/betterstack-query.sh"
cp "$REPO_ROOT/scripts/lib/betterstack-read-classify.sh" "$S3/ihws/scripts/lib/"
cat > "$S3/ihstub/doppler" <<'IHDOPPLER'
#!/usr/bin/env bash
printf 'SOLEUR_CREDENTIAL_REFUSED script=betterstack-query reason=token_shape\nbetterstack-query: a credential was refused\n' >&2
exit 2
IHDOPPLER
chmod +x "$S3/ihws/scripts/betterstack-query.sh" "$S3/ihws-nolib/scripts/betterstack-query.sh" "$S3/ihstub/doppler"
S3_IH_SLICE="$(s3_slice .github/workflows/scheduled-inngest-health.yml "Dedicated inngest host probe consumer" '^BS_ERR=' 'rm -f "\$BS_ERR" "\$BS_ERR\.rows"')"
S3_IH_LIVE="$(s3_body .github/workflows/scheduled-inngest-health.yml "Dedicated inngest host probe consumer")"
if [[ -n "$S3_IH_SLICE" && "$S3_IH_LIVE" == *"$S3_IH_SLICE"* && "$(printf '%s\n' "$S3_IH_SLICE" | grep -c .)" -ge 8 && "$(printf '%s\n' "$S3_IH_SLICE" | grep -c .)" -le 24 ]]; then
  row "S3 inngest-health dedicated-host reader slice: extracted from the live step text ($(printf '%s\n' "$S3_IH_SLICE" | grep -c .) lines)" ok
else row "S3 inngest-health dedicated-host reader slice" fail "slice missing or drifted from the live step"; fi
{ printf 'set -euo pipefail\nrc=0\nPROBE_WINDOW=1h\nPROBE_LIMIT=500\n'; printf '%s\n' "$S3_IH_SLICE"; printf 'echo REACHED_NEXT\necho "rc_seen=$rc"\n'; } > "$S3/ih.sh"
s3_run "$S3/ih.sh" "$S3/real" GITHUB_WORKSPACE="$S3/ihws"
if [[ "$S3_RC" == 0 && "$(s3_marker_count)" == 1 ]] && grep -qx 'REACHED_NEXT' "$S3_OUT" && grep -qx 'rc_seen=2' "$S3_OUT" && grep -q '^::warning::#9757 dedicated-host arm: the Better Stack read failed (rc=2, class=' "$S3_OUT"; then
  row "S3 inngest-health dedicated-host arm: a reader refusal (rc 2) surfaces its marker once and ONE classified ::warning::, and the step goes on with rc=2" ok
else row "S3 inngest-health dedicated-host arm: reader refusal" fail "rc=$S3_RC markers=$(s3_marker_count)"; fi
s3_run "$S3/ih.sh" "$S3/real" GITHUB_WORKSPACE="$S3/ihws-nolib"
if [[ "$S3_RC" == 0 && "$(s3_marker_count)" == 1 ]] && grep -qx 'rc_seen=2' "$S3_OUT" && ! grep -q '^::warning::#9757' "$S3_OUT"; then
  row "S3 inngest-health dedicated-host arm: with the classifier library absent the marker still reaches the log, only the warning is dropped" ok
else row "S3 inngest-health dedicated-host arm: classifier absent" fail "rc=$S3_RC markers=$(s3_marker_count)"; fi

S3_GC_SLICE="$(s3_slice .github/workflows/git-data-cutover.yml "Per-host git_data_store= assertion" '^[[:space:]]*rows_rc=0' '^[[:space:]]*fi$')"
S3_GC_LIVE="$(s3_body .github/workflows/git-data-cutover.yml "Per-host git_data_store= assertion")"
if [[ -n "$S3_GC_SLICE" && "$S3_GC_LIVE" == *"$S3_GC_SLICE"* && "$(printf '%s\n' "$S3_GC_SLICE" | grep -c .)" -ge 5 && "$(printf '%s\n' "$S3_GC_SLICE" | grep -c .)" -le 14 ]]; then
  row "S3 cutover per-host assertion reader slice: extracted from the live step text ($(printf '%s\n' "$S3_GC_SLICE" | grep -c .) lines)" ok
else row "S3 cutover per-host assertion reader slice" fail "slice missing or drifted from the live step"; fi
{ printf 'set -uo pipefail\nBS_ERR="$RUNNER_TEMP/bs-err"\nname_in="'"'"'h1'"'"'"\nleg=blue\ni=1\n'; printf 'source "%s/scripts/lib/betterstack-read-classify.sh"\n' "$REPO_ROOT"; printf '%s\n' "$S3_GC_SLICE"; printf 'echo REACHED_NEXT\necho "rows_rc_seen=$rows_rc"\n'; } > "$S3/gc.sh"
{ printf 'set -uo pipefail\nBS_ERR="$RUNNER_TEMP/bs-err"\nname_in="'"'"'h1'"'"'"\nleg=blue\ni=1\n'; printf '%s\n' "$S3_GC_SLICE"; printf 'echo REACHED_NEXT\necho "rows_rc_seen=$rows_rc"\n'; } > "$S3/gc-nolib.sh"
s3_run "$S3/gc.sh" "$S3/ihstub:$S3/real"
if [[ "$(s3_marker_count)" == 1 ]] && grep -qx 'REACHED_NEXT' "$S3_OUT" && grep -qx 'rows_rc_seen=2' "$S3_OUT" && grep -q '^::warning::host blue: the Better Stack read failed (attempt 1, rc=2, class=' "$S3_OUT"; then
  row "S3 cutover per-host assertion: a reader refusal (rc 2) surfaces its marker and the classified warning, and the loop's rc is kept" ok
else row "S3 cutover per-host assertion: reader refusal" fail "markers=$(s3_marker_count) rc=$S3_RC"; fi
s3_run "$S3/gc-nolib.sh" "$S3/ihstub:$S3/real"
if [[ "$(s3_marker_count)" == 1 ]] && grep -qx 'rows_rc_seen=2' "$S3_OUT" && ! grep -q '^::warning::host blue' "$S3_OUT"; then
  row "S3 cutover per-host assertion: with the classifier library absent the marker still reaches the log, only the warning is dropped" ok
else row "S3 cutover per-host assertion: classifier absent" fail "markers=$(s3_marker_count) rc=$S3_RC"; fi

# ---- the held-back site left its held-back state (S4): the declaration is gone, not forgotten ----
if ! printf '%s\n' .github/workflows/scheduled-inngest-health.yml | python3 -I -c 'import sys,re
for rel in sys.stdin.read().split():
    for l in open(sys.argv[1] + "/" + rel):
        if not l.lstrip().startswith("#") and re.search(r"openssl\b.*-(hmac|macopt)\b", l): sys.exit(0)
sys.exit(1)' "$REPO_ROOT" \
   && grep -qF 'bc_hmac_sha256_hex WEBHOOK_SECRET' "$REPO_ROOT/.github/workflows/scheduled-inngest-health.yml"; then
  row "S3 held-back: the inngest-health probe step left its held-back state (no argv HMAC; the signature comes from bc_hmac_sha256_hex) and S3 declares no exception any more" ok
else row "S3 held-back: the inngest-health probe step carries an argv HMAC again, or no longer signs through the library" fail "restore bc_hmac_sha256_hex or re-declare the exception with its reason"; fi

