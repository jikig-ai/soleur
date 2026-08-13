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
ACTUATING="terraform ssh systemctl"
if [[ -f "$VERIFY_SH" ]]; then
  checked=0
  for c in $ACTUATING; do
    checked=$((checked + 1))
    n=$(cmd_position_count "$VERIFY_SH" "$c")
    if [[ "$n" -eq 0 ]]; then
      pass "infra-config-verify.sh has no command-position \`$c\` (it verifies; it does not actuate)"
    else
      fail "infra-config-verify.sh runs \`$c\` at $n command position(s) — the verification gate actuates, collapsing the step boundary R22 restored"
    fi
  done
  # `gh issue` specifically: the escalation credentials live in none of these steps
  # (R18.6). A bare `gh` would over-match `gh` in prose; anchor on the subcommand.
  ghn=$(grep -cE '(^|[;&|]|\$\()[[:space:]]*gh[[:space:]]+issue[[:space:]]' "$VERIFY_SH" || true)
  checked=$((checked + 1))
  if [[ "$ghn" -eq 0 ]]; then
    pass "infra-config-verify.sh runs no \`gh issue\` (escalation stays out of the verdict step)"
  else
    fail "infra-config-verify.sh runs \`gh issue\` at $ghn site(s) — escalation credentials do not belong in the verdict step"
  fi
  # Minimum-cardinality guard: a loop whose data source silently empties reports a
  # clean sweep having examined nothing.
  if [[ "$checked" -ge 4 ]]; then
    pass "actuation sweep examined $checked commands"
  else
    fail "actuation sweep examined only $checked commands — the command list emptied"
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
  cat > "$I_TMP/bin/doppler" <<'EOS'
#!/usr/bin/env bash
# Only `secrets get <NAME> --plain` is ever called by the body under test.
echo "stub-secret-value"
EOS
  cat > "$I_TMP/bin/sleep" <<'EOS'
#!/usr/bin/env bash
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
have_w=0; have_maxtime=0; have_sig=0; have_url=0
for a in "$@"; do
  [[ "$prev" == "-o" ]] && out="$a"
  [[ "$a" == "-w" || "$a" == "--write-out" ]] && have_w=1
  [[ "$a" == "--max-time" ]] && have_maxtime=1
  [[ "$a" == X-Signature-256:* ]] && have_sig=1
  [[ "$a" == */hooks/infra-config-status ]] && have_url=1
  prev="$a"
done
if [[ -z "$out" || "$have_w" -ne 1 || "$have_maxtime" -ne 1 || "$have_sig" -ne 1 || "$have_url" -ne 1 ]]; then
  echo "curl-stub: required argv missing (o='${out:-}' w=$have_w max-time=$have_maxtime sig=$have_sig url=$have_url)" >&2
  exit 64
fi
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
    export GITHUB_OUTPUT="$3"
    export VERIFY_PASS="$1"
    export ALLOW_MISSING_STATUS=false
    export DPF_REPLACED=true
    export APPLY_START_EPOCH=2000
    [[ -n "${4:-}" ]] && export REPUSH_BASELINE_TS="$4"
    bash ./infra-config-verify.sh >/dev/null 2>&1 )
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
  if [[ "$p6" -eq 0 ]]; then
    pass "#7104 I3: DPF_REPLACED=false never requests a re-push (rc=$rc6) — no push was expected, so no frame can be stale relative to one"
  else
    fail "#7104 I3: a run that expected no push requested a re-push"
  fi
else
  fail "#7104 AC17: could not build fixtures from the live FILE_MAP — the integration cases are vacuous"
fi

# --- assertion floor --------------------------------------------------------------------------
# Anti-vacuity. Counts assertions that RAN, so a structural break that skips whole
# blocks (an unset file path, an early `else`) reds instead of reporting a clean 0/0.
VERIFY_MIN_ASSERTIONS=23
echo ""
echo "  $PASS passed, $FAIL failed"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
if [[ "$PASS" -lt "$VERIFY_MIN_ASSERTIONS" ]]; then
  echo "  FAIL: assertion-count floor: only $PASS assertions ran, expected >= $VERIFY_MIN_ASSERTIONS — arms were deleted or skipped" >&2
  exit 1
fi
exit 0
