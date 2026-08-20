#!/usr/bin/env bash
# Tests for infra-config-verify.sh — the infra-config apply verification gate.
#
# #7104 PR-B / plan R22.2: this file was the ~240-line `run:` body of the
# "Verify infra-config apply succeeded" step in apply-deploy-pipeline-fix.yml.
# It was moved out verbatim (ADR-150 shape) so that the split recovery can
# invoke the SAME tested artifact twice instead of duplicating 240 lines of
# untestable YAML across two steps.
#
# ADR-150's recorded regret is that scripts/cutover-inngest.sh shipped WITHOUT a
# companion suite. This file is that companion, and it is registered in
# .github/workflows/infra-validation.yml so lint-orphan-test-suites cannot let a
# future edit land unguarded.
#
# What this suite does NOT do: assert byte-identity against the pre-move `run:`
# block. That verification is a COMMIT-1 event, not a standing property — plan
# R22.3's commit 2 deliberately parameterises this script, so a permanent
# byte-identity assert would be RED by the end of this very PR. Worse, the
# prescribed baseline (`git show origin/main:<the workflow>`) FLIPS at merge:
# post-merge that revision carries the one-line `run:`, so the guard would
# either fail or pass vacuously for the next contributor. The move's
# verbatim-ness is instead pinned by the SHA-256 recorded in ADR-189 and in
# commit 1's message (both sides 2a23f958…, 19774 bytes).
set -euo pipefail

# A direct invocation inherits the bare /tmp (a machine-global 4 GiB tmpfs shared
# by parallel worktrees); test-all.sh and run-registered-suites.sh default this to
# /var/tmp. Without it this suite's verdicts become a function of another
# session's disk usage.
export TMPDIR="${TMPDIR:-/var/tmp}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
VERIFY_SH="${SCRIPT_DIR}/infra-config-verify.sh"
GATE_SH="${SCRIPT_DIR}/infra-config-gate.sh"
APPLY_WF="${REPO_ROOT}/.github/workflows/apply-deploy-pipeline-fix.yml"

PASS=0
FAIL=0

# TALLY PROTECTION, MIRRORING THE GATE SUITE (#7104 PR-B review, F7).
#
# The floor at the bottom of this file had exactly ONE producer — the counter `pass()`
# increments — so `PASS=$((PASS + 2))` clears it with half the arms deletable, which is the D2
# shape the gate suite was measured to have. F7's finding is that neither sibling suite got the
# fix. The second producer is this suite's own captured STDOUT, written by the redirection below
# rather than by `pass()`, so no edit to `pass()` can inflate it silently.
STDOUT_LOG="$(mktemp -t verify-suite-stdout.XXXXXXXX.log)"
exec 3>&1
exec 1> >(tee -a "$STDOUT_LOG" >&3)
close_stdout_capture() {
  exec 1>&3 3>&-
  local i=0 prev=-1 now
  while [[ "$i" -lt 50 ]]; do
    now=$(wc -c < "$STDOUT_LOG" 2>/dev/null || echo 0)
    [[ "$now" == "$prev" && "$now" != "0" ]] && return 0
    prev="$now"; i=$((i + 1)); sleep 0.02
  done
  return 0
}

pass() {
  echo "  PASS: $1"
  PASS=$((PASS + 1))
}

fail() {
  echo "  FAIL: $1" >&2
  FAIL=$((FAIL + 1))
}

# Command-position matcher. Anchored on shell syntax (line start, a separator, or
# the head of a command substitution) rather than a bare token: both files carry
# 20+ comment-only occurrences of these words, and a bare grep would match the
# prose that DOCUMENTS the prohibition (cq-assert-anchor-not-bare-token).
#
# Single-quoted so the shell does not eat the backslash in `\$\(` — double
# quoting turns it into `$(`, where `$` is an ERE end-anchor that can never
# match, silently reporting 0 for every input. That exact defect produced a
# false "0 curl occurrences" reading while authoring this suite.
cmd_position_count() {
  local file="$1" cmd="$2"
  grep -cE '(^|[;&|]|\$\()[[:space:]]*(sudo[[:space:]]+)?'"$cmd"'[[:space:]]' "$file" 2>/dev/null || true
}

echo "== infra-config-verify.sh =="

# --- T1: the artifact exists and is a bash script -------------------------------------------
if [[ -f "$VERIFY_SH" ]]; then
  pass "infra-config-verify.sh exists"
  if [[ "$(head -n 1 "$VERIFY_SH")" == "#!/usr/bin/env bash" ]]; then
    pass "carries the bash shebang"
  else
    fail "missing or wrong shebang: $(head -n 1 "$VERIFY_SH")"
  fi
else
  fail "infra-config-verify.sh not found at $VERIFY_SH"
fi

# --- T2: it parses. `bash -n` on the EXTRACTED FILE ------------------------------------------
# Never `bash -n` on the .yml (it is not shell), and never `bash -c`, which would
# RUN the body — and this body reaches a production terraform apply (plan R16.3).
if [[ -f "$VERIFY_SH" ]] && bash -n "$VERIFY_SH" 2>/dev/null; then
  pass "bash -n clean"
else
  fail "bash -n reported a syntax error"
fi

# --- T3: no GitHub expression syntax survived the move ---------------------------------------
# `${{ }}` is interpolated by Actions BEFORE the shell sees it. Inside a standalone
# script it is a literal that bash would mis-parse, so any occurrence means the move
# took something that cannot work outside the workflow.
if [[ -f "$VERIFY_SH" ]]; then
  ghexpr=$(grep -cF '${{' "$VERIFY_SH" || true)
  if [[ "$ghexpr" -eq 0 ]]; then
    pass "no \${{ }} GitHub expressions in the extracted body"
  else
    fail "$ghexpr GitHub expression(s) survived extraction — they cannot evaluate in a standalone script"
  fi
fi

# --- T4: production invokes it ---------------------------------------------------------------
# A tested script no step runs is the vacuity the F1 pin exists to prevent, one
# indirection deeper. The mirror clause lives in infra-config-gate.test.sh.
if [[ -r "$APPLY_WF" ]]; then
  if grep -qE '^[[:space:]]*run:[[:space:]]+bash[[:space:]]+.*infra-config-verify\.sh' "$APPLY_WF"; then
    pass "apply-deploy-pipeline-fix.yml invokes infra-config-verify.sh"
  else
    fail "no step in apply-deploy-pipeline-fix.yml invokes infra-config-verify.sh — the extracted gate is dead in production"
  fi
else
  fail "cannot read $APPLY_WF — the production invocation pin cannot be evaluated"
fi

# --- T5: the verification surface does not ACTUATE -------------------------------------------
# Plan R22.4: "PR-B ships no verification surface that actuates." This converts that
# sentence from a claim in an ADR into a contract. infra-config-verify.sh senses,
# polls and adjudicates; the re-push it triggers is planned, graded and applied in
# SEPARATE workflow steps. A `terraform` here would collapse the boundary the whole
# ruling restored.
#
# curl and `doppler secrets get` are deliberately NOT in this set: polling the status
# endpoint and reading a secret are what a verification gate does. T6 pins the doppler
# half to read-only subcommands.
# AN ALLOW-LIST, NOT A DENY-LIST (#7104 PR-B review, D3).
#
# This was `for c in terraform ssh systemctl` — three names, matched by a grep. D3 ran the
# equivalent deny-list against crafted inputs and it was evaded EIGHT ways out of nine: an
# absolute path, a relative `./` path, a variable in command position, `awk` with system(),
# `awk` piping to "sh", `sed -e ...e`, `sed -i`, and a bare shell redirection. A deny-list can
# only refuse what its author thought of, and this is the HIGHER-privilege of the two files —
# it runs twice in production, holds DOPPLER_TOKEN, and its `repush_needed=true` output is the
# sole authoriser of the production write.
#
# So the sweep is now the same allow-list the library gets, from the same shared scanner. The
# three names above are no longer enumerated because they no longer need to be: anything not on
# the list is a hit, including shapes nobody predicted.
if [[ -f "$VERIFY_SH" ]]; then
  VERIFY_SWEEP=$(python3 - "$VERIFY_SH" "$GATE_SH" "${SCRIPT_DIR}/infra-config-shellscan.py" <<'PYEOF'
import importlib.util, re, sys

verify_path, gate_path, scanner = sys.argv[1], sys.argv[2], sys.argv[3]
_spec = importlib.util.spec_from_file_location('shellscan', scanner)
_m = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_m)

KEYWORDS = {'if','elif','then','else','fi','for','while','until','do','done','case','esac',
            'in','function','time','coproc','return','break','continue'}
# `trap` REMOVED (#7546 review). The comment above says builtins "run in-process and cannot
# reach infrastructure" -- true of `echo` and `printf`, false of `trap`, whose payload is
# arbitrary code that runs later. Measured: `trap 'terraform apply' EXIT` was MISSED in both
# quoting forms, because the payload lives in a quoted span that strip_noise blanks. Neither
# scanned file uses `trap` today, so this costs nothing and closes a trampoline that sat on
# the allow-list under a false premise -- the same shape as `eval`/`source`/`.`/`command`,
# which this set already omits deliberately.
BUILTINS = {'echo','printf','local','declare','typeset','readonly','export','unset','set',
            'shift','exit','true','false','test','read','shopt','let','pwd',
            'type','hash','umask',':','['}
# What a VERIFICATION gate legitimately runs: it polls an endpoint, reads a secret, waits,
# transforms text, and prints. Every one is inert with respect to infrastructure. `terraform`,
# `ssh`, `systemctl` and `gh` are absent by omission rather than by enumeration, which is the
# point of the inversion.
ALLOWED = {'jq','sed','grep','awk','basename','sha256sum','cat','curl','date','doppler',
           'openssl','sleep','source'}

# The gate library's function names, DERIVED from the library rather than listed here, so a
# newly added adjudicator is covered the moment it exists instead of reading as an escape.
gate_src = open(gate_path, encoding='utf-8').read()
LIB_FUNCS = set(re.findall(r'^([A-Za-z_][A-Za-z0-9_]*)\s*\(\)\s*\{', gate_src, re.M))
if len(LIB_FUNCS) < 5:
    print('SWEEP-ERROR: derived only %d function name(s) from infra-config-gate.sh — the '
          'derivation broke, so every library call below would read as an escape' % len(LIB_FUNCS))
    sys.exit(0)

src = open(verify_path, encoding='utf-8').read()
hits = []
for line, tok, raw in _m.raw_command_tokens(_m.strip_noise(src)):
    if tok in KEYWORDS or tok in BUILTINS or tok in ALLOWED or tok in LIB_FUNCS:
        continue
    if tok == '$INDIRECT':
        hits.append((line, '%s (a variable in command position names a command this sweep '
                           'cannot resolve)' % raw))
        continue
    hits.append((line, raw))

for line, kind, detail in _m.find_trampolines(src):
    # `redirect-variable` is ALLOWED HERE and nowhere else: this gate legitimately writes
    # $GITHUB_OUTPUT and its own status-response scratch file. A redirect to a LITERAL path is
    # still a hit — that is `echo pwned > /etc/default/soleur-doppler-token`, which invokes no
    # command at all and is therefore invisible to every allow list above.
    if kind == 'redirect-variable':
        continue
    hits.append((line, '%s: %s' % (kind, detail)))

# `source` is on the allow list because this file must load the adjudicator, and that makes it
# the one allow-listed trampoline. Pin WHAT it sources, or the allowance is a hole.
sourced = re.findall(r'(?:^|[\n;&|])\s*(?:source|\.)\s+(\S+)', _m.strip_noise(src), re.M)
unexpected = [s for s in sourced if s not in ('./infra-config-gate.sh',)]
if unexpected:
    hits.append((0, 'sources %s — `source` is allow-listed only for ./infra-config-gate.sh; '
                    'anything else is an arbitrary-code trampoline' % ', '.join(unexpected)))
if not sourced:
    hits.append((0, 'sources NOTHING — the adjudicator is not loaded, so the `source` allowance '
                    'is unexercised and this pin is vacuous'))

print('OK' if not hits else 'HITS=' + '; '.join('L%d %s' % h for h in hits))
PYEOF
) || VERIFY_SWEEP="SWEEP-ERROR (python3 unavailable)"
  if [[ "$VERIFY_SWEEP" == "OK" ]]; then
    pass "infra-config-verify.sh runs ONLY allow-listed inert commands plus the derived gate-library functions, sources only ./infra-config-gate.sh, and writes no literal path — it verifies; it does not actuate"
  else
    fail "infra-config-verify.sh actuation sweep: $VERIFY_SWEEP"
  fi

  # THE SWEEP'S OWN POSITIVE CONTROL, crossing shapes rather than wrappers. Without it an
  # allow-list that silently stopped matching reports the same clean verdict as a clean file.
  VERIFY_CONTROL=$(python3 - "$GATE_SH" "${SCRIPT_DIR}/infra-config-shellscan.py" <<'PYEOF'
import importlib.util, sys
_spec = importlib.util.spec_from_file_location('shellscan', sys.argv[2])
_m = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_m)
ALLOWED = {'jq','sed','grep','awk','basename','sha256sum','cat','curl','date','doppler',
           'openssl','sleep','source','echo','printf','exit','local','set','if','then','fi','f'}
SHAPES = {
    'bare-binary':   'f() {\n  terraform apply -auto-approve\n}\n',
    'abs-path':      'f() {\n  /usr/bin/terraform apply -auto-approve\n}\n',
    'rel-path':      'f() {\n  ./push-infra-config.sh\n}\n',
    'var-indirect':  'f() {\n  TF=terraform ; $TF apply -auto-approve\n}\n',
    'awk-system':    'f() {\n  awk \'BEGIN{system("terraform apply")}\'\n}\n',
    'awk-pipe-sh':   'f() {\n  awk \'BEGIN{print "terraform apply" | "sh"}\'\n}\n',
    'sed-e-flag':    'f() {\n  sed -e "s/x/terraform apply/e" file\n}\n',
    'sed-inplace':   'f() {\n  sed -i "s/a/b/" ../../../.github/workflows/apply-deploy-pipeline-fix.yml\n}\n',
    'redirect-write':'f() {\n  echo pwned > /etc/default/soleur-doppler-token\n}\n',
    'ssh-actuate':   'f() {\n  ssh host systemctl restart webhook\n}\n',
}
missed = []
for name, code in SHAPES.items():
    toks = [t for _l, t, _r in _m.raw_command_tokens(_m.strip_noise(code)) if t not in ALLOWED]
    tramp = [k for _l, k, _d in _m.find_trampolines(code) if k != 'redirect-variable']
    if not toks and not tramp:
        missed.append(name)
print('OK' if not missed else 'MISSED=' + ','.join(missed))
PYEOF
) || VERIFY_CONTROL="MISSED=control battery could not run"
  if [[ "$VERIFY_CONTROL" == "OK" ]]; then
    pass "the actuation sweep's control battery detects all 10 evasion SHAPES (path, indirect, awk/sed trampoline, bare redirection), not 12 wrappers on one shape"
  else
    fail "the actuation sweep cannot see: $VERIFY_CONTROL — its clean verdict on the real file is a statement about the regex, not about the file"
  fi

  # `gh issue` specifically: the escalation credentials live in none of these steps
  # (R18.6). Kept as its own row because it is a CREDENTIAL-SURFACE claim, not an actuation one:
  # the allow-list above already excludes `gh`, but this row is what names why.
  ghn=$(grep -cE '(^|[;&|]|\$\()[[:space:]]*gh[[:space:]]+issue[[:space:]]' "$VERIFY_SH" || true)
  if [[ "$ghn" -eq 0 ]]; then
    pass "infra-config-verify.sh runs no \`gh issue\` (escalation stays out of the verdict step)"
  else
    fail "infra-config-verify.sh runs \`gh issue\` at $ghn site(s) — escalation credentials do not belong in the verdict step"
  fi
fi

# --- T6: every doppler call is READ-only ------------------------------------------------------
# `doppler secrets get` reads. `doppler secrets set|delete|upload`, `doppler run`,
# and `doppler configure` mutate or execute. The gate may read a secret; it may not
# write one.
if [[ -f "$VERIFY_SH" ]]; then
  dtotal=$(cmd_position_count "$VERIFY_SH" doppler)
  dread=$(grep -cE '(^|[;&|]|\$\()[[:space:]]*doppler[[:space:]]+secrets[[:space:]]+get[[:space:]]' "$VERIFY_SH" || true)
  if [[ "$dtotal" -eq 0 ]]; then
    fail "no command-position doppler call found — the fixture for T6 has drifted, so this assert is vacuous"
  elif [[ "$dtotal" -eq "$dread" ]]; then
    pass "all $dtotal command-position doppler call(s) are read-only \`secrets get\`"
  else
    fail "$((dtotal - dread)) of $dtotal command-position doppler call(s) are not \`secrets get\` — the gate mutates secret state"
  fi
fi

# --- T7: infra-config-gate.sh remains a PURE adjudicator --------------------------------------
# Plan R20.7 §1: the sourced library is invisible to any grep over the workflow, and
# is a pure adjudicator BY CONVENTION ONLY. PR-B adds a function to it, which widens
# exactly that escape — so the sweep scopes to two files, and for the library the
# prohibition is absolute: it adjudicates in-process and touches nothing.
if [[ -f "$GATE_SH" ]]; then
  gchecked=0
  for c in terraform curl ssh systemctl doppler; do
    gchecked=$((gchecked + 1))
    n=$(cmd_position_count "$GATE_SH" "$c")
    if [[ "$n" -eq 0 ]]; then
      pass "infra-config-gate.sh has no command-position \`$c\` (pure adjudicator)"
    else
      fail "infra-config-gate.sh runs \`$c\` at $n command position(s) — it is no longer a pure adjudicator"
    fi
  done
  if [[ "$gchecked" -ge 5 ]]; then
    pass "purity sweep examined $gchecked commands"
  else
    fail "purity sweep examined only $gchecked commands — the command list emptied"
  fi
else
  fail "infra-config-gate.sh not found — the purity contract cannot be evaluated"
fi

# --- #7104 AC17: the hermetic TWO-PASS integration cases (I1, I2) ---------------------------
#
# AC17 is the PRIMARY acceptance criterion, and what it means changed when plan R22 split the
# recovery. Under the old inline design the re-push lived inside this body, so the criterion
# was "the re-push stub was invoked exactly once". Under the split the re-push is a separate
# workflow STEP, so in-script invocation counting would be asserting against a design that was
# not built. Boundedness is now structural — a step cannot run twice in a job — and Guard 3
# plus the terminal-verdict backstop pin the step wiring in infra-config-gate.test.sh.
#
# So what AC17 buys HERE is the thing only a real two-pass drive can prove: that pass 1 and
# pass 2 of the REAL script, on a real fixture, reach the verdicts the split depends on, with
# EACH PASS ASSERTED INDEPENDENTLY (task 4.7) so no case can pass by "the last attempt
# succeeded". No YAML extraction at test time (R22.6): this drives the shipped file.
#
# Hermetic: curl, doppler and sleep are stubbed on PATH. `sleep` matters — the body carries a
# documented 8 s settle preamble plus 5 s inter-attempt waits, and a suite that actually slept
# would take ~20 s per case and get skipped by whoever is iterating.
I_TMP="$(mktemp -d)"
trap 'rm -rf "$I_TMP"' EXIT

mkstubs() {
  mkdir -p "$I_TMP/bin"
  # THE SECRET NAME IS PART OF THE CONTRACT (#7104 PR-B review).
  #
  # This stub used to `echo` a constant for any argv at all, so it answered identically whether
  # the body asked for WEBHOOK_DEPLOY_SECRET, for a typo, or for nothing — the secret NAME shipped
  # unpinned, and a body that read the wrong secret (signing with the wrong key, so every request
  # 401s in production) stayed green here. It now allow-lists the names the body legitimately
  # reads and `exit 64`s on anything else, and it records each name so a case can assert on them.
  cat > "$I_TMP/bin/doppler" <<'EOS'
#!/usr/bin/env bash
# The body only ever calls `secrets get <NAME> --plain`.
if [[ "${1:-}" != "secrets" || "${2:-}" != "get" ]]; then
  echo "doppler-stub: unexpected subcommand '${1:-} ${2:-}' (the gate may only READ secrets)" >&2
  exit 64
fi
name="${3:-}"
printf '%s\n' "$name" >> "${STUB_DOPPLER_LOG:-/dev/null}"
case "$name" in
  APP_DOMAIN_BASE|WEBHOOK_DEPLOY_SECRET|CF_ACCESS_CLIENT_ID|CF_ACCESS_CLIENT_SECRET|\
  CI_SSH_ACCESS_TOKEN_ID|CI_SSH_ACCESS_TOKEN_SECRET) ;;
  *) echo "doppler-stub: unexpected secret name '$name'" >&2; exit 64 ;;
esac
[[ "$name" == "APP_DOMAIN_BASE" ]] && { echo "example.test"; exit 0; }
echo "stub-secret-value"
EOS
  # SLEEP IS RECORDED, NOT JUST SUPPRESSED (#7104 PR-B review).
  #
  # A `sleep` stubbed to a bare `exit 0` makes the suite fast and simultaneously voids the
  # retry/backoff contract: the documented 8 s settle preamble and the 5 s inter-attempt waits
  # could be deleted, or set to 600, and every case would stay green at identical speed. The
  # stub now logs each requested duration so cardinality and budget can be asserted.
  cat > "$I_TMP/bin/sleep" <<'EOS'
#!/usr/bin/env bash
printf '%s\n' "${1:-}" >> "${STUB_SLEEP_LOG:-/dev/null}"
exit 0
EOS
  # curl writes the frame the case wants to the -o path and reports the HTTP code.
  #
  # ARGV FIDELITY, not a fixture-returning shim. A stub that answers identically regardless
  # of its arguments puts the test seam ABOVE the code under test: the query SHAPE then ships
  # unpinned, and corrupting the URL, dropping the HMAC header or losing `-w '%{http_code}'`
  # leaves every case green. So the stub `exit 64`s on a missing REQUIRED argument, which the
  # body's own `|| echo "000"` turns into a transport-failure verdict — loud, and attributable.
  cat > "$I_TMP/bin/curl" <<'EOS'
#!/usr/bin/env bash
out=""
prev=""
have_w=0; have_maxtime=0; have_sig=0; have_url=0; sigval=""; url=""
for a in "$@"; do
  [[ "$prev" == "-o" ]] && out="$a"
  [[ "$a" == "-w" || "$a" == "--write-out" ]] && have_w=1
  [[ "$a" == "--max-time" ]] && have_maxtime=1
  [[ "$a" == X-Signature-256:* ]] && { have_sig=1; sigval="${a#X-Signature-256:}"; }
  [[ "$a" == */hooks/infra-config-status ]] && { have_url=1; url="$a"; }
  prev="$a"
done
if [[ -z "$out" || "$have_w" -ne 1 || "$have_maxtime" -ne 1 || "$have_sig" -ne 1 || "$have_url" -ne 1 ]]; then
  echo "curl-stub: required argv missing (o='${out:-}' w=$have_w max-time=$have_maxtime sig=$have_sig url=$have_url)" >&2
  exit 64
fi
# VALUES, NOT ONLY PRESENCE (#7104 PR-B review). The three checks below were presence-only, so
# the HOST, the signature VALUE and the scheme all shipped unpinned: the body could have polled
# `http://anywhere/hooks/infra-config-status` with `X-Signature-256:` and an empty value and
# every case here would still have been green. Presence-only argv fidelity puts the seam one
# level above the thing that actually matters about this request.
sigval="${sigval# }"
if [[ ! "$sigval" =~ ^(sha256=)?[0-9a-f]{64}$ ]]; then
  echo "curl-stub: X-Signature-256 is '${sigval}', not a 64-hex sha256 HMAC — the request would not authenticate" >&2
  exit 64
fi
if [[ "$url" != https://deploy.*/hooks/infra-config-status ]]; then
  echo "curl-stub: status URL is '${url}', expected https://deploy.<domain>/hooks/infra-config-status" >&2
  exit 64
fi
printf '%s\n' "$url" >> "${STUB_CURL_LOG:-/dev/null}"
[[ -n "${STUB_FRAME:-}" ]] && cp "$STUB_FRAME" "$out"
printf '%s' "${STUB_HTTP_CODE:-200}"
EOS
  chmod +x "$I_TMP/bin/doppler" "$I_TMP/bin/sleep" "$I_TMP/bin/curl"
}

# Build a frame the real adjudicator ACCEPTS: per-dest ok entries whose sha256 equals the
# repo file's, derived from the live FILE_MAP rather than pinned to a snapshot that rots.
# schema_version is left below 2 deliberately — that is the documented staged-adoption
# carve-out, and it keeps this fixture about the freshness/re-push decision rather than about
# the restart-reconciliation block, which has its own coverage.
mkframe() { # $1 = start_ts, $2 = out path
  local ts="$1" out="$2" n=0
  local files="[]"
  while IFS=$'\t' read -r dest base class; do
    local sha
    if [[ "$class" == "comparable" ]]; then
      sha=$(sha256sum "$SCRIPT_DIR/$base" 2>/dev/null | awk '{print $1}')
    else
      sha="0000000000000000000000000000000000000000000000000000000000000000"
    fi
    [[ -z "$sha" ]] && continue
    files=$(printf '%s' "$files" | jq -c --arg f "$dest" --arg s "$sha" '. + [{file:$f,status:"ok",sha256:$s}]')
    n=$((n + 1))
  done < <(cd "$SCRIPT_DIR" && source ./infra-config-gate.sh && infra_config_classify_files infra-config-apply.sh . 2>/dev/null)
  printf '%s' "$files" | jq --argjson ts "$ts" --argjson n "$n" \
    '{exit_code:0, files_failed:0, files_written:$n, files_total:$n, start_ts:$ts, files:.}' > "$out"
  [[ "$n" -gt 0 ]]
}

drive() { # $1 = pass, $2 = frame, $3 = GITHUB_OUTPUT path, $4 = baseline (pass 2 only)
  ( cd "$SCRIPT_DIR" || exit 99
    export PATH="$I_TMP/bin:$PATH"
    export STUB_FRAME="$2" STUB_HTTP_CODE=200
    # Per-case status path (#7104 PR-B). The SUT used to write a machine-global fixed
    # /tmp path, so two concurrent drives clobbered each other's frame — measured by three
    # reviewers at 5-of-6 red under 6-way concurrency, and the mutation battery then aborts
    # on its own mandatory green baseline. Both suites are registered in a runner that
    # fans out, and the battery re-invokes this one, so the collision reaches CI.
    export INFRA_CONFIG_STATUS_RESPONSE="$I_TMP/status-$1-$$.json"
    export GITHUB_OUTPUT="$3"
    export VERIFY_PASS="$1"
    export ALLOW_MISSING_STATUS=false
    export DPF_REPLACED=true
    export APPLY_START_EPOCH=2000
    [[ -n "${4:-}" ]] && export REPUSH_BASELINE_TS="$4"
    bash ./infra-config-verify.sh >/dev/null 2>&1 )
}

# PASS-2 DRIVER WITH THE CLOCK OPERANDS EXPOSED, AND A CAPTURED LOG (#7104 P0-A).
#
# `drive` above hardcodes APPLY_START_EPOCH=2000 and discards stdout/stderr. Both
# omissions are load-bearing: the absolute freshness pin's operands could not be
# varied at all, so the arm had no fixture; and with the output discarded a case can
# only assert THAT pass 2 failed, never WHICH diagnosis fired — and the whole point of
# a distinct `::error::` is that "the frame moved but still predates this apply" and
# "the frame did not move" have different levers.
drive_pass2() { # $1 frame, $2 GITHUB_OUTPUT, $3 baseline, $4 apply_start_epoch, $5 log, [$6 repush_start_epoch]
  ( cd "$SCRIPT_DIR" || exit 99
    export PATH="$I_TMP/bin:$PATH"
    export STUB_FRAME="$1" STUB_HTTP_CODE=200
    export INFRA_CONFIG_STATUS_RESPONSE="$I_TMP/status-p2-$$-${RANDOM}.json"
    export GITHUB_OUTPUT="$2"
    export VERIFY_PASS=2
    export ALLOW_MISSING_STATUS=false
    export DPF_REPLACED=true
    export REPUSH_BASELINE_TS="$3"
    export APPLY_START_EPOCH="$4"
    [[ -n "${6:-}" ]] && export REPUSH_START_EPOCH="$6"
    bash ./infra-config-verify.sh > "$5" 2>&1 )
}

mkstubs
STALE="$I_TMP/stale.json"; MOVED="$I_TMP/moved.json"
if mkframe 1000 "$STALE" && mkframe 3000 "$MOVED"; then
  pass "#7104 AC17: fixtures build from the live FILE_MAP ($(jq -r '.files_total' "$STALE") dests)"

  # --- I1: stale -> re-push -> fresh frame ---
  o1="$I_TMP/o1"; : > "$o1"
  rc1=0; drive 1 "$STALE" "$o1" || rc1=$?
  v1=$(grep -c '^verdict=pending$' "$o1" || true)
  r1=$(grep -c '^repush_needed=true$' "$o1" || true)
  ts1=$(sed -n 's/^observed_start_ts=//p' "$o1")
  if [[ "$rc1" -eq 0 && "$v1" -eq 1 && "$r1" -eq 1 && "$ts1" == "1000" ]]; then
    pass "#7104 I1 pass 1: a stale frame SOFT-FAILS (rc=0) with verdict=pending, repush_needed=true, observed_start_ts=1000"
  else
    fail "#7104 I1 pass 1: rc=$rc1 verdict-pending=$v1 repush_needed=$r1 observed_start_ts='${ts1:-<none>}' (expected 0/1/1/1000)"
  fi
  # Asserted INDEPENDENTLY of pass 1 (task 4.7): its own output file, its own verdict.
  o2="$I_TMP/o2"; : > "$o2"
  rc2=0; drive 2 "$MOVED" "$o2" "$ts1" || rc2=$?
  v2=$(grep -c '^verdict=verified$' "$o2" || true)
  if [[ "$rc2" -eq 0 && "$v2" -eq 1 ]]; then
    pass "#7104 I1 pass 2: the moved frame VERIFIES independently (rc=0, verdict=verified)"
  else
    fail "#7104 I1 pass 2: rc=$rc2 verdict-verified=$v2 (expected 0/1)"
  fi

  # --- I2: stale -> re-push -> STILL stale => terminal red ---
  o3="$I_TMP/o3"; : > "$o3"
  rc3=0; drive 1 "$STALE" "$o3" || rc3=$?
  o4="$I_TMP/o4"; : > "$o4"
  rc4=0; drive 2 "$STALE" "$o4" 1000 || rc4=$?
  v4=$(grep -c '^verdict=failed$' "$o4" || true)
  if [[ "$rc3" -eq 0 && "$rc4" -ne 0 && "$v4" -eq 1 ]]; then
    pass "#7104 I2: an unmoved frame is TERMINALLY RED on pass 2 (rc=$rc4, verdict=failed) — the recovery is spent, not retried"
  else
    fail "#7104 I2: pass1 rc=$rc3 (expected 0), pass2 rc=$rc4 (expected non-zero), verdict-failed=$v4 (expected 1)"
  fi

  # The freshness rule must be STRICTLY greater on pass 2: a frame equal to the baseline
  # means the re-push delivered nothing. Reading equality as success would make the recovery
  # self-certifying, which is the failure this PR exists to prevent.
  o5="$I_TMP/o5"; : > "$o5"
  rc5=0; drive 2 "$MOVED" "$o5" 3000 || rc5=$?
  if [[ "$rc5" -ne 0 ]]; then
    pass "#7104 I2b: pass 2 rejects a frame EQUAL to its baseline (strictly-greater, not >=)"
  else
    fail "#7104 I2b: pass 2 accepted start_ts == baseline — an unchanged frame read as a successful re-push"
  fi

  # Pass 1 must NOT soft-fail when no push was expected: that arm has no recoverable shape.
  o6="$I_TMP/o6"; : > "$o6"
  ( cd "$SCRIPT_DIR" || exit 99
    export PATH="$I_TMP/bin:$PATH" STUB_FRAME="$STALE" STUB_HTTP_CODE=200
    export GITHUB_OUTPUT="$o6" VERIFY_PASS=1 ALLOW_MISSING_STATUS=false
    export DPF_REPLACED=false APPLY_START_EPOCH=2000 PRE_FRAME_STATUS=ok PRE_APPLY_FRAME_START_TS=1000
    bash ./infra-config-verify.sh >/dev/null 2>&1 ) && rc6=0 || rc6=$?
  p6=$(grep -c '^repush_needed=true$' "$o6" || true)
  # POSITIVE, NOT ABSENCE-ONLY (#7546 review). This asserted only that a string was ABSENT from
  # the output file, and absence is exactly what an aborted, crashed or gutted run produces --
  # `rc6` was captured on the line above and rendered into the pass message without ever being
  # asserted. Measured: replacing the no-push arm's body with `exit 1` left this row printing
  # `PASS: ... (rc=1)` and the suite 38 passed, 0 failed. It is the ONLY end-to-end case for the
  # DPF_REPLACED=false arm, which is the arm most production dispatches take.
  v6=$(grep -c '^verdict=verified$' "$o6" || true)
  if [[ "$p6" -eq 0 && "$rc6" -eq 0 && "$v6" -eq 1 ]]; then
    pass "#7104 I3: DPF_REPLACED=false completes (rc=0), renders verdict=verified exactly once, and never requests a re-push — no push was expected, so no frame can be stale relative to one"
  else
    fail "#7104 I3: the no-push arm did not complete cleanly (rc=$rc6, verdict=verified x$v6, repush_needed x$p6). Expected rc=0, exactly one verdict=verified, and no re-push."
  fi

  # I3b — THE NO-PUSH ARM'S REJECT PATH, WHICH NO FIXTURE DROVE (#7546 review).
  #
  # Every DPF_REPLACED=false fixture above is the HEALTHY case, so the whole adjudication could
  # be replaced by a hardcoded `STABILITY=stable` and this suite stayed 38 passed, 0 failed --
  # a suite whose fixtures all sit on one side of a transform cannot see the transform being
  # removed. `unexpected_push` is the cheapest opposite-direction fixture: nothing was pushed,
  # yet the frame moved forward, which the arm must treat as terminal because it means either
  # the applied plan diverged from the graded one or something else wrote to the host's sole
  # credential channel. It is also the one sub-case whose own comment says the red-gate alert
  # would otherwise misreport it as cosmetic.
  o6b="$I_TMP/o6b"; : > "$o6b"
  ( cd "$SCRIPT_DIR" || exit 99
    export PATH="$I_TMP/bin:$PATH" STUB_FRAME="$MOVED" STUB_HTTP_CODE=200
    export GITHUB_OUTPUT="$o6b" VERIFY_PASS=1 ALLOW_MISSING_STATUS=false
    export DPF_REPLACED=false APPLY_START_EPOCH=2000 PRE_FRAME_STATUS=ok PRE_APPLY_FRAME_START_TS=1000
    bash ./infra-config-verify.sh >/dev/null 2>&1 ) && rc6b=0 || rc6b=$?
  sv6b=$(grep -c '^stability_verdict=unexpected_push$' "$o6b" || true)
  vv6b=$(grep -c '^verdict=verified$' "$o6b" || true)
  if [[ "$rc6b" -ne 0 && "$sv6b" -eq 1 && "$vv6b" -eq 0 ]]; then
    pass "#7104 I3b: the no-push arm REJECTS a frame that moved with nothing pushed (rc=$rc6b, stability_verdict=unexpected_push, never verdict=verified) — the reject direction, which every other DPF_REPLACED=false fixture omits"
  else
    fail "#7104 I3b: the no-push arm accepted a frame that advanced when nothing was pushed (rc=$rc6b, stability_verdict=unexpected_push x$sv6b, verdict=verified x$vv6b). Hardcoding the stability adjudication to 'stable' passes every other fixture in this suite; this is the row that catches it."
  fi

  # --- I4: THE EQUALITY BOUNDARY ON PASS 1, AND THE ELSE ARM ------------------------------
  #
  # FIXTURE DIRECTION (#7104 PR-B review). Every case above samples start_ts strictly BELOW
  # APPLY_START_EPOCH (1000 vs 2000, "stale") or strictly ABOVE it (3000, "moved"). The
  # boundary itself — start_ts EXACTLY equal to APPLY_START_EPOCH — was never instantiated on
  # pass 1, and it is the one input that distinguishes `-lt` from `-le`.
  #
  # This matters more than a missing edge case usually would, because of what it revealed:
  # production's inline freshness comparison decides staleness BEFORE delegating to the
  # predicate, so the predicate's own `-lt` is a SECOND, redundant evaluation and the P4
  # equality arm exercised by the unit cases is UNREACHABLE from production. The unit matrix
  # was grading a branch the shipped call path cannot reach. Driving the boundary through the
  # real script is what makes the guard's claim true of production rather than of the unit.
  EQ="$I_TMP/eq.json"
  if mkframe 2000 "$EQ"; then
    o7="$I_TMP/o7"; : > "$o7"
    rc7=0; drive 1 "$EQ" "$o7" || rc7=$?
    p7=$(grep -c '^repush_needed=true$' "$o7" || true)
    # `rc7` ASSERTED, not just rendered (#7546 review). shellcheck flagged it SC2034 -- captured
    # and unused -- and that is not a style nit here: the only assertion was that a string was
    # ABSENT, so this row passed vacuously if the drive CRASHED. Same shape as I3 above, and the
    # sibling I5 twenty lines down already asserts its rc correctly.
    v7=$(grep -c '^verdict=verified$' "$o7" || true)
    if [[ "$p7" -eq 0 && "$rc7" -eq 0 && "$v7" -eq 1 ]]; then
      pass "#7104 I4: pass 1 treats start_ts == APPLY_START_EPOCH as FRESH (no re-push) — equality is a delivered frame, and re-pushing on it writes production for a run that already succeeded"
    else
      fail "#7104 I4: the equality boundary did not verify cleanly (rc=$rc7, verdict=verified x$v7, repush_needed x$p7). Expected rc=0, exactly one verdict=verified, and no re-push: equality is a delivered frame, and re-pushing on it writes production for a run that already succeeded."
    fi
  else
    fail "#7104 I4: could not build the equality fixture — the boundary case is vacuous"
  fi

  # THE ELSE ARM. Every pass-1 case above ends in a soft-fail or a refusal-to-repush on a
  # frame that is stale or unexpected. A frame that is simply FRESH on pass 1 — the ordinary
  # healthy apply, which is what the overwhelming majority of production runs look like — was
  # never driven end to end here, so the arm that renders the ordinary green verdict had no
  # fixture at all. A suite whose fixtures all expect the exceptional path cannot see a change
  # that breaks the normal one.
  o8="$I_TMP/o8"; : > "$o8"
  rc8=0; drive 1 "$MOVED" "$o8" || rc8=$?
  v8=$(grep -c '^verdict=verified$' "$o8" || true)
  r8=$(grep -c '^repush_needed=true$' "$o8" || true)
  if [[ "$rc8" -eq 0 && "$v8" -eq 1 && "$r8" -eq 0 ]]; then
    pass "#7104 I5: a FRESH frame on pass 1 verifies outright (rc=0, verdict=verified, no re-push) — the ordinary healthy apply, which no other case drove"
  else
    fail "#7104 I5: pass 1 on a fresh frame gave rc=$rc8 verdict-verified=$v8 repush_needed=$r8 (expected 0/1/0). The ordinary green path is broken."
  fi

  # --- I6: STUB ARGV FIDELITY, on VALUES rather than presence -----------------------------
  #
  # The stubs log what they were actually asked for; these rows read those logs. Without them
  # the stub contract is enforced only by `exit 64`, which proves the required flags were
  # PRESENT and says nothing about whether the host, the secret names or the retry budget were
  # the intended ones.
  SL="$I_TMP/sleep.log"; DL="$I_TMP/doppler.log"; CL="$I_TMP/curl.log"
  : > "$SL"; : > "$DL"; : > "$CL"
  o9="$I_TMP/o9"; : > "$o9"
  ( cd "$SCRIPT_DIR" || exit 99
    export PATH="$I_TMP/bin:$PATH" STUB_FRAME="$MOVED" STUB_HTTP_CODE=200
    export STUB_SLEEP_LOG="$SL" STUB_DOPPLER_LOG="$DL" STUB_CURL_LOG="$CL"
    export INFRA_CONFIG_STATUS_RESPONSE="$I_TMP/status-argv-$$.json"
    export GITHUB_OUTPUT="$o9" VERIFY_PASS=1 ALLOW_MISSING_STATUS=false
    export DPF_REPLACED=true APPLY_START_EPOCH=1
    bash ./infra-config-verify.sh >/dev/null 2>&1 ) || true

  # The 8 s settle preamble is documented and load-bearing: the async handler takes ~5-8 s, so
  # polling immediately wastes attempt 1. A stubbed-to-nothing sleep let it be deleted silently.
  if grep -qx '8' "$SL"; then
    pass "#7104 I6a: the documented 8 s settle preamble is actually requested (sleep budget is pinned, not merely stubbed away)"
  else
    fail "#7104 I6a: no 8 s sleep was requested (sleep log: $(tr '\n' ' ' < "$SL")). The settle preamble was deleted or retimed, and a no-op sleep stub cannot see that."
  fi
  # A healthy first attempt must not burn inter-attempt waits: exactly one sleep total.
  n_sleep=$(grep -c . "$SL" || true)
  if [[ "$n_sleep" -eq 1 ]]; then
    pass "#7104 I6b: a frame that satisfies the invariant on attempt 1 sleeps exactly once (the preamble) — no retry budget is spent on a healthy apply"
  else
    fail "#7104 I6b: $n_sleep sleep(s) on a first-attempt success (expected exactly 1): $(tr '\n' ' ' < "$SL")"
  fi
  # The signing secret's NAME. A body that read the wrong secret would sign with the wrong key
  # and 401 in production, while a name-agnostic stub kept every case green.
  if grep -qx 'WEBHOOK_DEPLOY_SECRET' "$DL"; then
    pass "#7104 I6c: the body reads WEBHOOK_DEPLOY_SECRET by name (the signing key is pinned, not just 'some secret')"
  else
    fail "#7104 I6c: WEBHOOK_DEPLOY_SECRET was never requested (secrets read: $(tr '\n' ' ' < "$DL")). The request would be signed with the wrong key."
  fi
  # The HOST. The stub's URL check enforces the deploy.<domain> shape; this pins that the
  # domain came from APP_DOMAIN_BASE rather than being hardcoded to something else.
  if grep -q '^https://deploy\.example\.test/hooks/infra-config-status$' "$CL"; then
    pass "#7104 I6d: the status URL is built from APP_DOMAIN_BASE (https://deploy.example.test/...), so the host is pinned and not hardcoded"
  else
    fail "#7104 I6d: the polled URL(s) were '$(tr '\n' ' ' < "$CL")', expected https://deploy.example.test/hooks/infra-config-status built from the stubbed APP_DOMAIN_BASE"
  fi

  # --- I8: THE `unadjudicated` ARM, WHICH HAD ZERO COVERAGE (#7104 PR-B review) -------------
  #
  # This is the 404 first-bootstrap escape hatch: the gate tolerates a missing status endpoint,
  # checks NOTHING — no count invariant, no content assert, no freshness assertion — and exits 0.
  # It is simultaneously the weakest green the design can produce and the only one with no
  # out-of-band report, and it was driven by no fixture at all. Everything downstream keys on the
  # verdict this arm emits, so "it emits `unadjudicated` and not `verified`" is load-bearing for
  # the three production steps now gated on it.
  #
  # STUB_HTTP_CODE is 200 at every other drive site in this file, which is why the 404 branch was
  # unreachable from the suite (F9).
  o10="$I_TMP/o10"; : > "$o10"
  rc10=0
  ( cd "$SCRIPT_DIR" || exit 99
    export PATH="$I_TMP/bin:$PATH" STUB_FRAME="$STALE" STUB_HTTP_CODE=404
    export INFRA_CONFIG_STATUS_RESPONSE="$I_TMP/status-404-$$.json"
    export GITHUB_OUTPUT="$o10" VERIFY_PASS=1 ALLOW_MISSING_STATUS=true
    export DPF_REPLACED=true APPLY_START_EPOCH=2000
    bash ./infra-config-verify.sh >/dev/null 2>&1 ) || rc10=$?
  v10=$(grep -c '^verdict=unadjudicated$' "$o10" || true)
  vv10=$(grep -c '^verdict=verified$' "$o10" || true)
  f10=$(grep -c '^freshness_evidence=none$' "$o10" || true)
  if [[ "$rc10" -eq 0 && "$v10" -eq 1 && "$vv10" -eq 0 && "$f10" -eq 1 ]]; then
    pass "#7104 I8: a tolerated 404 emits verdict=unadjudicated and freshness_evidence=none, and NEVER verdict=verified — the one arm that adjudicates nothing does not claim the strongest result"
  else
    fail "#7104 I8: tolerated 404 gave rc=$rc10 unadjudicated=$v10 verified=$vv10 evidence-none=$f10 (expected 0/1/0/1). An arm that checks nothing must not emit the same terminal verdict as a full count-plus-content-plus-freshness pass."
  fi
  # And WITHOUT the flag the same 404 must be terminal — this is the #4804 false-success freeze
  # vector, so the escape hatch must be opt-in rather than the default shape of a 404.
  o11="$I_TMP/o11"; : > "$o11"
  rc11=0
  ( cd "$SCRIPT_DIR" || exit 99
    export PATH="$I_TMP/bin:$PATH" STUB_FRAME="$STALE" STUB_HTTP_CODE=404
    export INFRA_CONFIG_STATUS_RESPONSE="$I_TMP/status-404b-$$.json"
    export GITHUB_OUTPUT="$o11" VERIFY_PASS=1 ALLOW_MISSING_STATUS=false
    export DPF_REPLACED=true APPLY_START_EPOCH=2000
    bash ./infra-config-verify.sh >/dev/null 2>&1 ) || rc11=$?
  if [[ "$rc11" -ne 0 ]]; then
    pass "#7104 I8b: an UNtolerated 404 is terminal (rc=$rc11) — the escape hatch is opt-in, not the default reading of a missing endpoint (#4804)"
  else
    fail "#7104 I8b: a 404 with ALLOW_MISSING_STATUS=false exited 0 — that is the #4804 false-success freeze vector"
  fi
  # A DEAD LISTENER is not a missing endpoint, and they have opposite levers. 000/502/503 were
  # never driven either (F9), and the escape hatch must not swallow them.
  for code in 000 502 503; do
    oX="$I_TMP/o-$code"; : > "$oX"
    rcX=0
    ( cd "$SCRIPT_DIR" || exit 99
      export PATH="$I_TMP/bin:$PATH" STUB_FRAME="$STALE" STUB_HTTP_CODE="$code"
      export INFRA_CONFIG_STATUS_RESPONSE="$I_TMP/status-$code-$$.json"
      export GITHUB_OUTPUT="$oX" VERIFY_PASS=1 ALLOW_MISSING_STATUS=true
      export DPF_REPLACED=true APPLY_START_EPOCH=2000
      bash ./infra-config-verify.sh >/dev/null 2>&1 ) || rcX=$?
    uX=$(grep -c '^verdict=unadjudicated$' "$oX" || true)
    if [[ "$rcX" -ne 0 && "$uX" -eq 0 ]]; then
      pass "#7104 I8c/$code: a dead listener is terminal even with the 404 escape hatch set — allow_missing_status_endpoint tolerates a MISSING endpoint, not a DOWN one"
    else
      fail "#7104 I8c/$code: HTTP $code gave rc=$rcX unadjudicated=$uX — the escape hatch swallowed a dead listener, whose lever (-replace the handler bootstrap) is the opposite of the first-bootstrap one"
    fi
  done

  # --- I7: THE ABSOLUTE FRESHNESS PIN ON PASS 2 (#7104 P0-A) -------------------------------
  #
  # On origin/main this arm was unconditionally `FRAME_START_TS -lt APPLY_START_EPOCH`.
  # PR-B inserted the `VERIFY_PASS == 2` branch IN FRONT of it, so pass 2's only surviving
  # assertion was RELATIVE — `FRAME_START_TS -gt REPUSH_BASELINE_TS` — and APPLY_START_EPOCH,
  # validated three lines above, was never read again on this path. That reintroduces the
  # exact #7220 shape this PR exists to close, in the TERMINAL verdict: any unrelated frame
  # advance (a queued handler invocation, a concurrent trigger, a lagging host clock) reads
  # as a verified recovery while the frame still predates this workflow's own apply.
  #
  # These fixtures are directional on purpose. I7a drives the defect; I7b drives the far side
  # of the same comparison, because the host-clock-to-host-clock choice on the RELATIVE half is
  # DELIBERATE (skew cancels exactly) and a naive AND against a runner-clock operand would
  # false-red a correct recovery whose host clock lags. A suite carrying only I7a would be
  # satisfied by exactly that regression.
  P1500="$I_TMP/f1500.json"; P1750="$I_TMP/f1750.json"
  P2100="$I_TMP/f2100.json"; P2300="$I_TMP/f2300.json"
  if mkframe 1500 "$P1500" && mkframe 1750 "$P1750" && mkframe 2100 "$P2100" && mkframe 2300 "$P2300"; then
    # I7a — THE P0. Advanced 1000 -> 1500, but 1500 still predates the apply's 2000 start by
    # 500 s, which is beyond the 300 s cross-clock skew allowance. This must be terminal.
    oa="$I_TMP/oa"; la="$I_TMP/la"; : > "$oa"
    rca=0; drive_pass2 "$P1500" "$oa" 1000 2000 "$la" || rca=$?
    va=$(grep -c '^verdict=failed$' "$oa" || true)
    if [[ "$rca" -ne 0 && "$va" -eq 1 ]]; then
      pass "#7104 I7a: pass 2 REJECTS a frame that advanced but still predates this apply (1000 -> 1500 against APPLY_START_EPOCH=2000)"
    else
      fail "#7104 I7a: pass 2 accepted start_ts=1500 as a verified re-push while the apply began at 2000 (rc=$rca verdict-failed=$va). The absolute freshness pin is gone from the terminal verdict — this is the #7220 shape."
    fi
    # The DIAGNOSIS, not merely the verdict. "The frame moved but still predates this apply"
    # and "the frame did not move" have different levers, so an operator handed the wrong one
    # is handed the wrong next action.
    if grep -q 'STALE FRAME AFTER RE-PUSH' "$la" && ! grep -q 'RE-PUSH DID NOT DELIVER' "$la"; then
      pass "#7104 I7a-diag: the advanced-but-stale path emits its OWN ::error::, distinct from 'the frame did not move'"
    else
      fail "#7104 I7a-diag: expected a distinct STALE-FRAME-AFTER-RE-PUSH diagnosis; got: $(tr '\n' '|' < "$la" | tail -c 400)"
    fi
    # I7b — THE OTHER DIRECTION. 1750 is 250 s before the apply's start, inside the 300 s
    # allowance the runner-clock comparison already carries. A host whose clock lags the runner
    # publishes exactly this, and it is a REAL delivery. A naive AND reds it.
    ob="$I_TMP/ob"; lb="$I_TMP/lb"; : > "$ob"
    rcb=0; drive_pass2 "$P1750" "$ob" 1000 2000 "$lb" || rcb=$?
    vb=$(grep -c '^verdict=verified$' "$ob" || true)
    if [[ "$rcb" -eq 0 && "$vb" -eq 1 ]]; then
      pass "#7104 I7b: pass 2 still VERIFIES a delivered frame inside the 300 s cross-clock skew allowance (1750 vs apply start 2000) — the pin is not a naive AND"
    else
      fail "#7104 I7b: pass 2 red-lined a frame 250 s before the apply start, inside the documented 300 s skew allowance (rc=$rcb verdict-verified=$vb). The absolute pin was added without the skew tolerance and will false-red correct recoveries on a lagging host clock."
    fi
    # I7c — THE ADVANCE IS BOUNDED BY THE RE-PUSH, NOT BY PASS 1'S OBSERVATION. A frame that
    # postdates the ORIGINAL apply can still predate the RE-PUSH, in which case it belongs to
    # some other write and the recovery delivered nothing. Without this, a +1 s bump anywhere
    # after APPLY_START_EPOCH reads as VERIFIED.
    oc="$I_TMP/oc"; lc="$I_TMP/lc"; : > "$oc"
    rcc=0; drive_pass2 "$P2100" "$oc" 1000 2000 "$lc" 2500 || rcc=$?
    vc=$(grep -c '^verdict=failed$' "$oc" || true)
    if [[ "$rcc" -ne 0 && "$vc" -eq 1 ]]; then
      pass "#7104 I7c: pass 2 REJECTS a frame that predates the re-push itself (2100 against a re-push that began at 2500) — the advance is bounded by the write that was supposed to cause it"
    else
      fail "#7104 I7c: pass 2 accepted start_ts=2100 for a re-push that began at 2500 (rc=$rcc verdict-failed=$vc). The advance is unbounded: any frame later than the ORIGINAL apply certifies the recovery."
    fi
    # I7d — the bounded-advance positive control. 2300 is inside the 300 s allowance below the
    # re-push's 2500 start, so it is a real post-re-push frame and must verify. Without this row
    # I7c is satisfiable by a pin that reds every run.
    od="$I_TMP/od"; ld="$I_TMP/ld"; : > "$od"
    rcd=0; drive_pass2 "$P2300" "$od" 1000 2000 "$ld" 2500 || rcd=$?
    vd=$(grep -c '^verdict=verified$' "$od" || true)
    if [[ "$rcd" -eq 0 && "$vd" -eq 1 ]]; then
      pass "#7104 I7d: pass 2 VERIFIES a frame inside the skew allowance of the re-push's own start (2300 vs 2500) — I7c's pin discriminates, it does not just red everything"
    else
      fail "#7104 I7d: pass 2 red-lined a genuine post-re-push frame (rc=$rcd verdict-verified=$vd). The bounded-advance pin has no tolerance and will red correct recoveries."
    fi
    # I7e — the UNMOVED frame keeps its own diagnosis. Both predicates are false here (1000 is
    # neither greater than the 1000 baseline nor at/after the apply start), and the operator
    # must be told the re-push delivered nothing, which is the more specific of the two.
    oe="$I_TMP/oe"; le="$I_TMP/le"; : > "$oe"
    rce=0; drive_pass2 "$STALE" "$oe" 1000 2000 "$le" || rce=$?
    if [[ "$rce" -ne 0 ]] && grep -q 'RE-PUSH DID NOT DELIVER' "$le"; then
      pass "#7104 I7e: an UNMOVED frame still reports 'the re-push did not deliver' — the new absolute pin did not swallow the more specific diagnosis"
    else
      fail "#7104 I7e: rc=$rce and the log did not carry 'RE-PUSH DID NOT DELIVER': $(tr '\n' '|' < "$le" | tail -c 400)"
    fi
  else
    fail "#7104 I7: could not build the absolute-freshness-pin fixtures — the whole P0-A arm is vacuous"
  fi
else
  fail "#7104 AC17: could not build fixtures from the live FILE_MAP — the integration cases are vacuous"
fi

# --- assertion floor --------------------------------------------------------------------------
# Anti-vacuity. Counts assertions that RAN, so a structural break that skips whole
# blocks (an unset file path, an early `else`) reds instead of reporting a clean 0/0.
# 35 -> 33: the actuation sweep replaced five deny-list rows (three command names, the `gh issue`
# row, and a cardinality guard over the loop that iterated them) with three allow-list rows. Fewer
# assertions covering strictly more shapes — D3 measured the deny-list as evaded 8 ways out of 9.
# 33 -> 38 for the `unadjudicated` arm (I8/I8b/I8c), which had ZERO coverage: STUB_HTTP_CODE was
# 200 at every drive site, so the 404/000/502/503 branches were unreachable from this suite.
echo ""
echo "  $PASS passed, $FAIL failed"
close_stdout_capture
# `|| true`, NOT `|| echo 0` (caught by scripts/lint-shell-capture-exit): `grep -c` PRINTS `0`
# and THEN exits 1 on no match, so `|| echo 0` appends a SECOND line and the variable becomes
# "0\n0" — which every numeric comparison below then mis-evaluates. `|| true` keeps the zero the
# command already printed.
stdout_passes=$(grep -c '^  PASS: ' "$STDOUT_LOG" 2>/dev/null || true)
rm -f "$STDOUT_LOG"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
# The counter must equal what was actually PRINTED. `PASS=$((PASS + 2))` cannot reach the
# captured stdout, so an inflated tally and a satisfied floor no longer travel together.
if [[ "$stdout_passes" -ne "$PASS" ]]; then
  printf '  FAIL: assertion-count reconciliation (stdout): the counter says %d but %d "  PASS: " lines were printed — the tally is not a count of assertions, so the floor below is meaningless\n' \
    "$PASS" "$stdout_passes" >&2
  exit 1
fi
if ! grep -qE '^VERIFY_MIN_ASSERTIONS=[0-9]+$' "${BASH_SOURCE[0]}"; then
  printf '  FAIL: the assertion-count floor is not a literal integer in the source — a floor derived from the tally it guards is a tautology that can never fail\n' >&2
  exit 1
fi
# THE THRESHOLD BINDING SITS IMMEDIATELY ABOVE ITS FLOOR, and that adjacency is load-bearing
# rather than stylistic (#7104 PR-B, promoting this suite into scripts/guard-vacuity-floor.test.sh's
# covered scope). That guard builds a mutant carrying the floor block plus the CONTIGUOUS SIMPLE
# ASSIGNMENTS directly above it. With the binding declared ~15 lines up, behind `echo`s and a
# command substitution, the widening stops early, the mutant runs with $VERIFY_MIN_ASSERTIONS
# unbound, and the floor is reported as one that cannot be driven red. Measured: this suite was
# the one covered failure the promotion surfaced.

# KNOWN-NEGATIVE SELF-TEST (#7546 review). Ported from infra-config-gate.test.sh, which was the
# ONLY one of the four sibling suites to carry it -- and the only one that survived the mutation
# below. An assertion harness that has never been shown to emit a FAIL has not returned a pass.
#
# MEASURED on a sandbox copy, with a genuine defect present: swapping this suite's fail()
# to record a PASS instead of a FAIL left the suite reporting `38 passed, 0 failed`, rc=0, zero FAIL lines.
# Every existing backstop held, because none of them can see a SWAP:
#   - the `FAIL -eq 0` exit gate  (FAIL never moves)
#   - any assertion-count floor        (the count is unchanged -- the verdict moved buckets)
#   - any passes+fails == cases identity (still balanced: one left one bucket, entered another)
# A swap is invisible to every count and every conservation identity by construction. The only
# thing that sees it is driving the REAL helper and asserting WHICH counter moved.
#
# Runs in a subshell so the side effects stay off the parent's tally.
if ( _p0="$PASS"; _f0="$FAIL"
     fail "self-test (expected -- this line proves fail() records a FAILURE)" >/dev/null 2>&1
     [[ "$FAIL" -eq $((_f0 + 1)) && "$PASS" -eq "$_p0" ]] ); then
  :
else
  echo "harness self-test: the REAL fail() does not record a failure into FAIL -- it is neutered, or it records failures as passes. Every verdict above is unverifiable." >&2
  exit 1
fi

VERIFY_MIN_ASSERTIONS=39
if [[ "$PASS" -lt "$VERIFY_MIN_ASSERTIONS" ]]; then
  printf '  FAIL: assertion-count floor: only %d assertions ran, expected >= %d — arms were deleted or skipped\n' \
    "$PASS" "$VERIFY_MIN_ASSERTIONS" >&2
  exit 1
fi
exit 0
