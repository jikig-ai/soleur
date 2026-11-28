# shellcheck shell=bash
# SOURCED FRAGMENT of tests/scripts/test-argv-bearer-sweep.sh -- NOT independently runnable.
# =====================================================================================
# STAGE S5 (argv-bearer sweep S5, ADR-280): the last slice. `apply-web-platform-infra.yml` (five sites: three best-effort Better Stack
# heartbeat-status reads and the two Hetzner existence probes of the recovery-posture step) and, in the registry commit, the four
# Better Stack posting scripts of `cloud-init-registry.yml`, leave the process command line. Baseline E then held only the two cla-evidence
# rows owned by #9756; that issue converted them and baseline E is empty, so the set rows below derive the registry row only while it
# still offends and every row of the file needs an owner line. Population and the manifests are DERIVED from the tree; the real step bodies
# are EXECUTED under the S4 recording curl.
#
#   GUARD 1  no curl of either converted file carries a credential header on its own argument list, and the baseline and the ceiling
#            table hold exactly the rows still owned by tracked work (set identity, not a count); every library call of the apply
#            workflow sits after its `source` line inside its own step (an ORDER row, which the lint cannot decide statically).
#   GUARD 2  a refused credential reaches the SAME verdict class as the failure it replaces: the heartbeat reads stay non-gating
#            ("unavailable", exit 0), the gating volume-existence probe reads `unknown-*` and can never read `absent`.
# All credentials are synthesized. A fixture credential is built from pieces, never a contiguous token literal.
# =====================================================================================
S5_WF=".github/workflows/apply-web-platform-infra.yml"
S5_REG="apps/web-platform/infra/cloud-init-registry.yml"
S5_CANARY="S5CANARYsecret0123"
S5_HZ="$(od -An -N32 -tx1 /dev/urandom | tr -d ' \n')"                   # the shape of a Hetzner Cloud token: 64 alphanumerics
S5_BS="synth_s5-$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')-tok_en"   # a Better Stack token with `_` and `-`
S5_BAD="${S5_CANARY}\" x"                                                  # a quote and a space: outside the alphabet, so refused
S5_HB_JSON='{"data":[{"attributes":{"name":"some-other-heartbeat","status":"down"}},{"attributes":{"name":"soleur-registry-disk-prd","status":"up"}}]}'
S5_REFUSALS=0; S5_CANARY_RUNS=0
# A run counts toward the negative-canary floors only when the planted canary is in its arguments (a run that plants none searches for nothing).
s5_run() { [[ "$*" == *"$S5_CANARY"* ]] && S5_CANARY_RUNS=$((S5_CANARY_RUNS + 1)); s4_run "$@"; }
s5_canary_clean() { ! grep -qaF -- "$S5_CANARY" < <(grep -rahv '^::add-mask::' "$S4_ROW" 2>/dev/null); }
# The step body of ONE job (a step name is not unique across the dispatch-only jobs): a copy of the workflow holding only that job.
s5_job_body() { # <job> <step name prefix> <out> [<from> <to>]...
  local job="$1" sel="$2" out="$3"; shift 3
  assert_fixture_dir "$out"
  python3 -I -c 'import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
yaml.safe_dump({"env": d.get("env"), "jobs": {sys.argv[2]: d["jobs"][sys.argv[2]]}}, open(sys.argv[3], "w"))' "$REPO_ROOT/$S5_WF" "$job" "$out.yml" \
    || fatal "S5 could not isolate the job '$job' of $S5_WF"
  s4_body "$out.yml" "$sel" "$out" "$@"
}
S5_B_HB1="$S4/b-s5-hb1.sh"; S5_B_HB2="$S4/b-s5-hb2.sh"; S5_B_HB3="$S4/b-s5-hb3.sh"; S5_B_PST="$S4/b-s5-pst.sh"; S5_B_EMP="$S4/b-s5-emp.sh"
s5_job_body registry_host_replace "Best-effort heartbeat status" "$S5_B_HB1"
s5_job_body registry_region_migrate "Best-effort heartbeat status" "$S5_B_HB2"
s5_job_body registry_luks_recut "Best-effort registry disk heartbeat status" "$S5_B_HB3"
s5_job_body registry_pull_path_gate "Resolve recovery posture" "$S5_B_PST"
s5_job_body git_data_host_replace "Rotate precondition — served store measured empty" "$S5_B_EMP"

# ---- Guard 1: the apply workflow ----
S5_LINT_OUT="$(python3 scripts/lint-shell-trace-credential-refusal.py "$S5_WF" 2>&1)"; S5_LINT_RC=$?
if [[ "$S5_LINT_RC" == 0 && "$S5_LINT_OUT" == OK:* ]]; then row "S5 Guard 1: Rule E on the explicit path of the apply workflow reports no curl with a credential header of its own (the explicit path bypasses the baseline)" ok
else row "S5 Guard 1: the apply workflow still has curl commands that carry a credential header" fail "rc=$S5_LINT_RC $(tail -1 <<<"$S5_LINT_OUT")"; fi
# The ORDER rule the lint cannot decide: in every step that calls the library, the `source` line comes BEFORE the first call.
s5_order_ok() { # <body file> -> rc 0 when a `source ...bearer-curl.sh` line precedes the first bc_curl statement and both exist (comment lines do not count)
  local t src call
  t="$(grep -vn '^[[:space:]]*#' "$1" || true)"
  src="$(grep -m1 'source .*scripts/lib/bearer-curl\.sh' <<<"$t" | cut -d: -f1)"
  call="$(grep -m1 'bc_curl [a-z]' <<<"$t" | cut -d: -f1)"
  [[ -n "$src" && -n "$call" && "$src" -lt "$call" ]]
}
S5_ORDER_BAD=""; S5_BCN=0
for b in "$S5_B_HB1" "$S5_B_HB2" "$S5_B_HB3" "$S5_B_PST" "$S5_B_EMP"; do
  s5_order_ok "$b" || S5_ORDER_BAD+=" ${b##*/}"
  S5_BCN=$((S5_BCN + $(grep -v '^[[:space:]]*#' "$b" | grep -c 'bc_curl [a-z-]* ' || true)))
done
# The derived population: every step of the workflow that calls the library is one of the five bodies built above (a sixth call site that
# nothing here judges is a defect); BOTH operands of the floor are literals on the lines IMMEDIATELY above the `if`.
S5_STEPS_WITH_BC="$(python3 -I -c 'import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
n = 0
for j in d["jobs"].values():
    for s in (j.get("steps") or []):
        if isinstance(s.get("run"), str) and "bc_curl " in s["run"]: n += 1
print(n)' "$REPO_ROOT/$S5_WF")"
S5_BC_FLOOR=6
S5_STEPS_WANT=5
if [[ -z "$S5_ORDER_BAD" && "$S5_BCN" -ge "$S5_BC_FLOOR" && "$S5_STEPS_WITH_BC" == "$S5_STEPS_WANT" ]]; then row "S5 Guard 1 order: in each of the five steps the library is sourced before its first call ($S5_BCN bc_curl statements, $S5_STEPS_WITH_BC steps derived from the workflow; anti-vacuity floor $S5_BC_FLOOR)" ok
else row "S5 Guard 1 order: a step calls the library before sourcing it, or the derived population is empty or unjudged" fail "bad='${S5_ORDER_BAD# }' statements=$S5_BCN steps=$S5_STEPS_WITH_BC floor=$S5_BC_FLOOR"; fi
# Mutation 3 (reorder): move the `source` line below the first call in one step; the order predicate must judge it RED.
python3 -I -c 'import sys, re
t = open(sys.argv[1]).read().split("\n")
code = lambda l: not l.lstrip().startswith("#")
i = next(k for k, l in enumerate(t) if code(l) and re.search(r"source .*scripts/lib/bearer-curl\.sh", l))
line = t.pop(i)
j = next(k for k, l in enumerate(t) if code(l) and re.search(r"bc_curl [a-z]", l))
t.insert(j + 1, line)
open(sys.argv[2], "w").write("\n".join(t))' "$S5_B_HB1" "$S4/b-s5-reorder.sh" || fatal "S5 could not build the reorder mutant"
if ! cmp -s "$S5_B_HB1" "$S4/b-s5-reorder.sh" && s5_order_ok "$S5_B_HB1" && ! s5_order_ok "$S4/b-s5-reorder.sh"; then row "S5 Guard 1 mutation 3: a heartbeat step whose source line is moved below its first call is judged RED by the order predicate (the unmutated step is green)" ok
else row "S5 Guard 1 mutation 3: the order predicate is blind to a reordered step" fail "landed=$(cmp -s "$S5_B_HB1" "$S4/b-s5-reorder.sh" && echo no || echo yes)"; fi

# ---- baseline E and the ceiling table: SET IDENTITY with the rows still owned by tracked work (parametrized on the registry commit) ----
S5_CEIL="scripts/fixtures/shell-trace-refusal/rule-e-census-ceiling.tsv"
S5_REG_OFFENDS=0; S5_REG_LINT="$(python3 scripts/lint-shell-trace-credential-refusal.py "$S5_REG" 2>&1)"; grep -q '^OK:' <<<"$S5_REG_LINT" || S5_REG_OFFENDS=1
S5_WANT_ROWS="$( (( S5_REG_OFFENDS )) && printf '%s\n' "$S5_REG"; true)"
S5_WANT_ROWS="$(sort <<<"$S5_WANT_ROWS")"
S5_GOT_BASE="$( { grep -v '^#' "$BASE_E" || true; } | cut -f1 | sort)"; S5_GOT_CEIL="$( { grep -v '^#' "$S5_CEIL" || true; } | cut -f1 | sort)"
if [[ "$S5_GOT_BASE" == "$S5_WANT_ROWS" && "$S5_GOT_CEIL" == "$S5_WANT_ROWS" ]]; then row "S5 Guard 1: baseline E and the census ceiling each hold exactly the rows still owned by tracked work ($( (( S5_REG_OFFENDS )) && echo 'the registry file, which still carries its argv form' || echo 'none: every Rule E site is converted'))" ok
else row "S5 Guard 1: baseline E or the ceiling table differs from the rows still owned by tracked work" fail "want='${S5_WANT_ROWS//$'\n'/,}' base='${S5_GOT_BASE//$'\n'/,}' ceil='${S5_GOT_CEIL//$'\n'/,}'"; fi
S5_OWN_BASE='# OWNERS (S5, #9597): a row in this file must carry its own owner'
S5_OWN_CEIL='# OWNERS (S5, #9597): a row in this table carries its own owner'
if grep -qF -- "$S5_OWN_BASE" "$BASE_E" && grep -qF -- "$S5_OWN_CEIL" "$S5_CEIL" && grep -qF -- "${S5_OWN_BASE#\# }" scripts/lint-shell-trace-credential-refusal.py \
   && ! grep -qF '#9756' < <(sed -n '1,/^[^#]/p' "$BASE_E"); then row "S5 Guard 1: the headers of baseline E and of the ceiling table state the owner-line rule in state-neutral words (no row is named), and the lint's writer emits the baseline's text" ok
else row "S5 Guard 1: the baseline or the ceiling table header does not state the owner-line rule, or still names a converted row's owner" fail "owner-line header text missing or stale"; fi

# ---- Guard 2: the heartbeat reads (three steps, non-gating) ----
s5_hb_valid_ok() { # <token>: rc 0 when the valid-credential contract holds for the row just run
  [[ "$S4_RC" == 0 && "$(s4_ncalls)" == 1 ]] && s4_calls_ok 1 \
    && [[ "$(s4_stdin_line 1 1)" == "header = \"Authorization: Bearer $1\"" ]] \
    && s4_nowhere_on_argv "$1" && grep -qF -- '**up**' "$S4_ROW/summary" && s5_canary_clean \
    && [[ "$(grep -cxF -- "::add-mask::$1" "$S4_ROW/stdout")" == 1 ]]   # the runner is told to mask THIS token, once
}
s5_hb_refused_ok() { # rc 0 when a refused credential made no request, printed ONE visible marker and left the step green and "unavailable"
  [[ "$S4_RC" == 0 && "$(s4_ncalls)" == 0 && "$(s4_markers)" == 1 ]] \
    && s4_said 'SOLEUR_CREDENTIAL_REFUSED script=apply-web-platform-infra reason=token_shape' && s4_said 'bc_curl: TOKEN unusable' \
    && grep -qF -- 'unavailable' "$S4_ROW/summary" && ! grep -qF -- '**up**' "$S4_ROW/summary" && s5_canary_clean
}
s5_hb_unset_ok() { # an unset or empty credential: the existing arm (no request, no marker), same verdict
  [[ "$S4_RC" == 0 && "$(s4_ncalls)" == 0 && "$(s4_markers)" == 0 ]] && grep -qF -- 'unavailable' "$S4_ROW/summary"
}
S5_HBN=0
for hb in "$S5_B_HB1" "$S5_B_HB2" "$S5_B_HB3"; do
  S5_HBN=$((S5_HBN + 1)); n="hb$S5_HBN"
  s5_run "s5-$n-hz-shape" "$hb" "$S4/real" D_BETTERSTACK_API_TOKEN="$S5_HZ" SHIM_BODY="$S5_HB_JSON"
  if s5_hb_valid_ok "$S5_HZ"; then row "S5 Guard 2 ($n): a 64-character alphanumeric credential is sent once, on curl's stdin config and on no argv, and the step summary reads the heartbeat status" ok
  else row "S5 Guard 2 ($n): a valid credential is not sent on stdin only, or the status is not read" fail "rc=$S4_RC calls=$(s4_ncalls) stdin='$(s4_stdin_line 1 1 | cut -c1-24)...'"; fi
  s5_run "s5-$n-bs-shape" "$hb" "$S4/real" D_BETTERSTACK_API_TOKEN="$S5_BS" SHIM_BODY="$S5_HB_JSON"
  if s5_hb_valid_ok "$S5_BS"; then row "S5 Guard 2 ($n): a Better Stack-shaped credential holding an underscore and hyphens is accepted (the guard's alphabet matches what the vendor issues)" ok
  else row "S5 Guard 2 ($n): a realistic Better Stack credential is refused or mis-sent" fail "rc=$S4_RC calls=$(s4_ncalls)"; fi
  s5_run "s5-$n-hostile" "$hb" "$S4/real" D_BETTERSTACK_API_TOKEN="$S5_BAD" SHIM_BODY="$S5_HB_JSON"; S5_REFUSALS=$((S5_REFUSALS + 1))
  if s5_hb_refused_ok; then row "S5 Guard 2 ($n): a credential holding a quote and a space makes no request, prints one visible refusal marker and leaves the non-gating step green and \"unavailable\" (the old failure class)" ok
  else row "S5 Guard 2 ($n): a refused credential does not land in the old verdict class" fail "rc=$S4_RC calls=$(s4_ncalls) markers=$(s4_markers)"; fi
  s5_run "s5-$n-unset" "$hb" "$S4/real"; S5_REFUSALS=$((S5_REFUSALS + 1))
  if s5_hb_unset_ok && s5_canary_clean; then row "S5 Guard 2 ($n): a credential that cannot be read (doppler fails) keeps the existing arm: no request, no marker, \"unavailable\"" ok
  else row "S5 Guard 2 ($n): an unreadable credential changed verdict" fail "rc=$S4_RC calls=$(s4_ncalls) markers=$(s4_markers)"; fi
done
# Harness row (a): a recording curl that ignores `--config -` is judged RED by the same predicate (the harness cannot be satisfied by a blind shim).
s5_run s5-hb1-blind "$S5_B_HB1" "$S4/real" D_BETTERSTACK_API_TOKEN="$S5_HZ" SHIM_BODY="$S5_HB_JSON" SHIM_NOSTDIN=1
if [[ "$(s4_ncalls)" == 1 ]] && ! s5_hb_valid_ok "$S5_HZ"; then row "S5 harness: a curl that never reads --config - is judged RED by the heartbeat contract (the predicate is not satisfiable by a blind shim)" ok
else row "S5 harness: a blind curl satisfied the heartbeat contract" fail "calls=$(s4_ncalls)"; fi
# Mutation 1 (Guard 1): the argv header restored in a heartbeat step goes RED on the nowhere-on-argv clause.
s5_job_body registry_host_replace "Best-effort heartbeat status" "$S4/b-s5-mut-argv.sh" \
  "bc_curl apply-web-platform-infra 'Authorization:Bearer :TOKEN' -- " 'curl -H "Authorization: Bearer ${TOKEN}" '
s5_run s5-mut-argv "$S4/b-s5-mut-argv.sh" "$S4/real" D_BETTERSTACK_API_TOKEN="$S5_HZ" SHIM_BODY="$S5_HB_JSON"
if ! s5_hb_valid_ok "$S5_HZ" && s4_argv_has "$S5_HZ"; then row "S5 Guard 1 mutation 1: a heartbeat step that puts the header back on curl's argument list is judged RED (token on a recorded argv)" ok
else row "S5 Guard 1 mutation 1: an argv credential header in a heartbeat step is not caught" fail "argv=$(s4_argv_has "$S5_HZ" && echo seen || echo missed)"; fi
# Mutation 6 (Guard 2): silencing a converted call hides the marker; the marker-visible clause must go RED.
s5_job_body registry_host_replace "Best-effort heartbeat status" "$S4/b-s5-mut-silent.sh" \
  'https://uptime.betterstack.com/api/v2/heartbeats)' 'https://uptime.betterstack.com/api/v2/heartbeats 2>/dev/null)'
s5_run s5-mut-silent "$S4/b-s5-mut-silent.sh" "$S4/real" D_BETTERSTACK_API_TOKEN="$S5_BAD" SHIM_BODY="$S5_HB_JSON"; S5_REFUSALS=$((S5_REFUSALS + 1))
if [[ "$(s4_ncalls)" == 0 ]] && ! s5_hb_refused_ok; then row "S5 Guard 2 mutation 6: a converted call silenced with 2>/dev/null is judged RED by the marker-visible clause (the refusal marker never appears)" ok
else row "S5 Guard 2 mutation 6: a silenced converted call is not caught" fail "markers=$(s4_markers) calls=$(s4_ncalls)"; fi

# ---- Guard 2: the gating volume-existence probe (two curls, one step) ----
s5_pst_run() { s5_run "$1" "$2" "$S4/real" EXPECTED_VOLUME_ID=4242 "${@:3}"; }
s5_pst_valid_ok() { # <expected probe_result>
  [[ "$S4_RC" == 0 && "$(s4_ncalls)" == 2 ]] && s4_calls_ok 1 && s4_gho_has "probe_result=$1" \
    && [[ "$(s4_stdin_line 1 1)" == "header = \"Authorization: Bearer $S5_HZ\"" && "$(s4_stdin_line 2 1)" == "header = \"Authorization: Bearer $S5_HZ\"" ]] \
    && s4_nowhere_on_argv "$S5_HZ" && s5_canary_clean \
    && [[ "$(grep -cxF -- "::add-mask::$S5_HZ" "$S4_ROW/stdout")" == 1 ]]
}
s5_pst_refused_ok() { # a refused credential: no request, a visible marker per call, the step green, and the result is NEVER `absent`
  [[ "$S4_RC" == 0 && "$(s4_ncalls)" == 0 && "$(s4_markers)" == 2 ]] && s4_gho_has 'probe_result=unknown-000' && ! s4_gho_has 'probe_result=absent' \
    && s4_said 'SOLEUR_CREDENTIAL_REFUSED script=apply-web-platform-infra reason=token_shape' && s5_canary_clean
}
s5_pst_run s5-pst-present "$S5_B_PST" HCLOUD_TOKEN="$S5_HZ" SHIM_CODE=200 SHIM_BODY='{"volumes":[{"id":4242}]}'
if s5_pst_valid_ok present; then row "S5 Guard 2 (posture): a pinned volume that exists reads \`present\`; both probes send the credential on stdin only and on no argv" ok
else row "S5 Guard 2 (posture): the existing-volume probe changed verdict or leaks the credential" fail "rc=$S4_RC calls=$(s4_ncalls) gho=$(tr '\n' ' ' < "$S4_ROW/gho")"; fi
s5_pst_run s5-pst-absent "$S5_B_PST" HCLOUD_TOKEN="$S5_HZ" SHIM_CODE=404 SHIM_BODY='{"volumes":[]}'
if s5_pst_valid_ok absent; then row "S5 Guard 2 (posture): a 404 on the pinned id with no volume of that name reads \`absent\` (both signals agree)" ok
else row "S5 Guard 2 (posture): the absent verdict changed" fail "rc=$S4_RC calls=$(s4_ncalls) gho=$(tr '\n' ' ' < "$S4_ROW/gho")"; fi
s5_pst_run s5-pst-wrongid "$S5_B_PST" HCLOUD_TOKEN="$S5_HZ" SHIM_CODE=404 SHIM_BODY='{"volumes":[{"id":1}]}'
if [[ "$S4_RC" == 1 ]] && s4_said 'the pinned volume id 4242 returned 404, but a volume named soleur-registry-store still exists'; then row "S5 Guard 2 (posture): a 404 on the pinned id while a volume of that name exists still aborts (the mistyped-id guard is unchanged)" ok
else row "S5 Guard 2 (posture): the mistyped-id abort changed" fail "rc=$S4_RC"; fi
s5_pst_run s5-pst-bs "$S5_B_PST" HCLOUD_TOKEN="$S5_BS" SHIM_CODE=200 SHIM_BODY='{"volumes":[{"id":4242}]}'
[[ "$S4_RC" == 0 && "$(s4_ncalls)" == 2 ]] && row "S5 Guard 2 (posture): a credential holding an underscore and hyphens is accepted by the guard (realistic shape)" ok || row "S5 Guard 2 (posture): a realistic credential shape was refused" fail "rc=$S4_RC calls=$(s4_ncalls)"
# A stub that would answer 404 with an empty name list (the shape that reads `absent`) is never reached by a refused credential.
s5_pst_run s5-pst-hostile "$S5_B_PST" HCLOUD_TOKEN="$S5_BAD" SHIM_CODE=404 SHIM_BODY='{"volumes":[]}'; S5_REFUSALS=$((S5_REFUSALS + 1))
if s5_pst_refused_ok; then row "S5 Guard 2 (posture): a refused credential makes no request, prints a visible marker per call and reads \`unknown-000\`, never \`absent\` (a refusal cannot manufacture the verdict that admits a bare create)" ok
else row "S5 Guard 2 (posture): a refused credential reaches a verdict other than unknown-000" fail "rc=$S4_RC calls=$(s4_ncalls) markers=$(s4_markers) gho=$(tr '\n' ' ' < "$S4_ROW/gho")"; fi
s5_pst_run s5-pst-empty "$S5_B_PST" HCLOUD_TOKEN=; S5_REFUSALS=$((S5_REFUSALS + 1))
if [[ "$S4_RC" == 1 && "$(s4_ncalls)" == 0 ]] && s4_said 'cannot read HCLOUD_TOKEN from Doppler'; then row "S5 Guard 2 (posture): an empty credential keeps the existing fail-closed abort (no request)" ok
else row "S5 Guard 2 (posture): the unreadable-credential abort changed" fail "rc=$S4_RC calls=$(s4_ncalls)"; fi
# Mutation 1 (Guard 2): fold a refusal into the verdict that admits a create. Both folds are applied (a transport failure to 404 and an
# unreadable count to 0), so the refused run reaches `absent`; the refused-verdict clause must go RED.
s5_job_body registry_pull_path_gate "Resolve recovery posture" "$S4/b-s5-mut-absent.sh" \
  '|| PROBE_STATUS="000"' '|| PROBE_STATUS="404"' 'NAME_COUNT="unknown"' 'NAME_COUNT="0"'
s5_pst_run s5-pst-mut-absent "$S4/b-s5-mut-absent.sh" HCLOUD_TOKEN="$S5_BAD" SHIM_CODE=404 SHIM_BODY='{"volumes":[]}'; S5_REFUSALS=$((S5_REFUSALS + 1))
if ! s5_pst_refused_ok; then row "S5 Guard 2 mutation 1: a posture step that maps a refusal to a 404 and an unreadable count to zero is judged RED by the refused-verdict clause" ok
else row "S5 Guard 2 mutation 1: a refusal folded into \`absent\` is not caught" fail "gho=$(tr '\n' ' ' < "$S4_ROW/gho")"; fi
# ---- review-round rows (workflow side): mask before the call, library-absent behaviour, an unreadable name count, owners ----
# The ::add-mask:: line must precede the first call in every step (the canary filter above ignores add-mask lines, so only an ORDER row can pin it).
s5_mask_ok() { # <body file> -> rc 0 when a non-comment ::add-mask:: line precedes the first bc_curl call
  local t m c
  t="$(grep -vn '^[[:space:]]*#' "$1" || true)"
  m="$(grep -m1 'add-mask' <<<"$t" | cut -d: -f1)"
  c="$(grep -m1 'bc_curl [a-z]' <<<"$t" | cut -d: -f1)"
  [[ -n "$m" && -n "$c" && "$m" -lt "$c" ]]
}
S5_MASK_BAD=""
for b in "$S5_B_HB1" "$S5_B_HB2" "$S5_B_HB3" "$S5_B_PST" "$S5_B_EMP"; do s5_mask_ok "$b" || S5_MASK_BAD+=" ${b##*/}"; done
grep -v 'add-mask' "$S5_B_HB1" > "$S4/b-s5-nomask.sh" || true
if [[ -z "$S5_MASK_BAD" ]] && ! s5_mask_ok "$S4/b-s5-nomask.sh"; then row "S5 Guard 1 order: every converted step masks its token before its first call, and a step with the mask line deleted is judged RED" ok
else row "S5 Guard 1 order: a converted step does not mask its token before the call, or the mask predicate is blind" fail "bad='${S5_MASK_BAD# }'"; fi
s5_run s5-hb1-nomask "$S4/b-s5-nomask.sh" "$S4/real" D_BETTERSTACK_API_TOKEN="$S5_HZ" SHIM_BODY="$S5_HB_JSON"
if ! s5_hb_valid_ok "$S5_HZ"; then row "S5 Guard 2 mutation: a heartbeat step with the ::add-mask:: line deleted is judged RED by the valid-credential row (the runner must be told to mask this token, once)" ok
else row "S5 Guard 2 mutation: a deleted ::add-mask:: line is not caught by the executed row" fail "rc=$S4_RC"; fi
# Library absent (an empty workspace): the heartbeat reads skip and stay green and "unavailable"; the gating posture step aborts. Neither falls back to argv.
S5_NOLIB_BAD=""; n=0
for hb in "$S5_B_HB1" "$S5_B_HB2" "$S5_B_HB3"; do
  n=$((n + 1))
  s5_run "s5-hb$n-nolib" "$hb" "$S4/real" D_BETTERSTACK_API_TOKEN="$S5_HZ" SHIM_BODY="$S5_HB_JSON" GITHUB_WORKSPACE="$S4_EMPTYWS"
  [[ "$S4_RC" == 0 && "$(s4_ncalls)" == 0 && "$(s4_markers)" == 0 ]] && grep -qF -- 'unavailable' "$S4_ROW/summary" && s4_said 'could not be loaded' || S5_NOLIB_BAD+=" hb$n"
done
s5_pst_run s5-pst-nolib "$S5_B_PST" HCLOUD_TOKEN="$S5_HZ" GITHUB_WORKSPACE="$S4_EMPTYWS" SHIM_CODE=200 SHIM_BODY='{"volumes":[{"id":4242}]}'
[[ "$S4_RC" == 1 && "$(s4_ncalls)" == 0 ]] && s4_said 'could not be loaded' || S5_NOLIB_BAD+=" posture"
if [[ -z "$S5_NOLIB_BAD" ]]; then row "S5 Guard 2: with the library absent the three heartbeat reads make no request and stay green and \"unavailable\", and the posture step aborts with no request (no argv fallback)" ok
else row "S5 Guard 2: a converted step behaves wrongly with the library absent" fail "bad='${S5_NOLIB_BAD# }'"; fi
s5_job_body registry_pull_path_gate "Resolve recovery posture" "$S4/b-s5-mut-nolib.sh" 'an unsent probe is not evidence of absence."; exit 1; }' 'an unsent probe is not evidence of absence."; }'
s5_pst_run s5-pst-mut-nolib "$S4/b-s5-mut-nolib.sh" HCLOUD_TOKEN="$S5_HZ" GITHUB_WORKSPACE="$S4_EMPTYWS" SHIM_CODE=200 SHIM_BODY='{"volumes":[{"id":4242}]}'
if [[ "$S4_RC" != 1 ]]; then row "S5 Guard 2 mutation: a posture step whose missing-library arm no longer exits is judged RED by the library-absent row" ok
else row "S5 Guard 2 mutation: dropping the exit of the posture step's missing-library arm is not caught" fail "rc=$S4_RC"; fi
# An unreadable name count must read UNKNOWN, never zero: a 404 on the pinned id with a body the count cannot parse still aborts (it never reads `absent`).
S5_NJ_BAD=""
for nb in 'not-json' '{"error":{"code":"rate_limit_exceeded"}}' '{"volumes":null}' '[]'; do
  s5_pst_run s5-pst-nj "$S5_B_PST" HCLOUD_TOKEN="$S5_HZ" SHIM_CODE=404 SHIM_BODY="$nb"
  [[ "$S4_RC" == 1 ]] && ! s4_gho_has 'probe_result=absent' && s4_said 'name_count=unknown' || S5_NJ_BAD+=" $nb"
done
S5_NJ_OK=0; [[ -z "$S5_NJ_BAD" ]] && S5_NJ_OK=1
s5_job_body registry_pull_path_gate "Resolve recovery posture" "$S4/b-s5-mut-count.sh" 'NAME_COUNT="unknown"' 'NAME_COUNT="0"'
s5_pst_run s5-pst-mut-count "$S4/b-s5-mut-count.sh" HCLOUD_TOKEN="$S5_HZ" SHIM_CODE=404 SHIM_BODY='not-json'
s5_job_body registry_pull_path_gate "Resolve recovery posture" "$S4/b-s5-mut-else.sh" 'else "unknown" end' 'else 0 end'
s5_pst_run s5-pst-mut-else "$S4/b-s5-mut-else.sh" HCLOUD_TOKEN="$S5_HZ" SHIM_CODE=404 SHIM_BODY='{"volumes":null}'
if [[ "$S4_RC" == 0 ]] && s4_gho_has 'probe_result=absent'; then row "S5 Guard 2 mutation (posture): a name lookup whose JSON has no volumes array (an error envelope, null) read as zero admits \`absent\` and is judged RED by the error-envelope rows" ok
else row "S5 Guard 2 mutation (posture): an error-envelope name lookup read as zero is not caught" fail "rc=$S4_RC"; fi
if [[ "$S5_NJ_OK" == 1 && "$S4_RC" == 0 ]]; then row "S5 Guard 2 (posture): a 404 on the pinned id with an unparseable, error-envelope, null or array-shaped name lookup aborts as unknown (never absent)" ok
else row "S5 Guard 2 (posture): an unreadable name count is not held at unknown" fail "bad='${S5_NJ_BAD# }'"; fi
s5_pst_run s5-pst-mut-count2 "$S4/b-s5-mut-count.sh" HCLOUD_TOKEN="$S5_HZ" SHIM_CODE=404 SHIM_BODY='not-json'
if [[ "$S4_RC" == 0 ]] && s4_gho_has 'probe_result=absent'; then row "S5 Guard 2 mutation (posture): folding the unreadable count to zero reaches \`absent\` and is judged RED" ok
else row "S5 Guard 2 mutation (posture): the fold of an unreadable count to zero is not caught" fail "rc=$S4_RC"; fi
# Owners: every baseline row carries an owner line (a `#N` comment) directly above it (the two cla-evidence rows were the one exemption; they left
# with #9756 and so did the carve-out), and the header's OWNERS lines are the same text the writer emits (so the committed header cannot drift
# from `--write-baseline-e`).
s5_owner_bad() { # <baseline file> -> prints the paths of rows with no `#N` owner comment directly above
  local line prev="" p bad=""
  while IFS= read -r line; do
    case "$line" in
      '#'*) prev="$line" ;;
      '') prev="" ;;
      *) p="${line%%$'\t'*}"
         [[ "$prev" =~ \#[0-9]+ ]] || bad+=" $p"
         prev="" ;;
    esac
  done < "$1"
  printf '%s' "${bad# }"
}
printf '# header\napps/web-platform/infra/x.yml\t1\n' > "$S4/own-bad.txt"
printf '# header\n# #9757 owner of the row below\napps/web-platform/infra/x.yml\t1\n' > "$S4/own-ok.txt"
printf '# header\napps/cla-evidence/scripts/x.sh\t1\n' > "$S4/own-bad-cla.txt"
printf '# header\n# #9757 owner of the row below\napps/cla-evidence/scripts/x.sh\t1\n' > "$S4/own-ok-cla.txt"
S5_OWNER_BAD="$(s5_owner_bad "$REPO_ROOT/$BASE_E")"
S5_OWNER_CTL=0; [[ "$(s5_owner_bad "$S4/own-bad.txt")" == apps/web-platform/infra/x.yml && -z "$(s5_owner_bad "$S4/own-ok.txt")" \
  && "$(s5_owner_bad "$S4/own-bad-cla.txt")" == apps/cla-evidence/scripts/x.sh && -z "$(s5_owner_bad "$S4/own-ok-cla.txt")" ]] && S5_OWNER_CTL=1
S5_HDR_BAD="$(python3 -I -c '
import sys
base = open(sys.argv[1]).read().split("\n")
src = open(sys.argv[2]).read()
i = next((k for k, l in enumerate(base) if l.startswith("# OWNERS")), None)
if i is None:
    print("anchor-missing"); sys.exit(0)
bad = []
while i < len(base) and base[i].startswith("#"):
    txt = base[i][2:]
    if txt not in src: bad.append(txt[:40])
    i += 1
print(";".join(bad))' "$REPO_ROOT/$BASE_E" "$REPO_ROOT/scripts/lint-shell-trace-credential-refusal.py")"
if [[ -z "$S5_OWNER_BAD" && -z "$S5_HDR_BAD" && "$S5_OWNER_CTL" == 1 ]]; then row "S5 Guard 1: every baseline E row carries an owner line above it (a cla-evidence row without one is refused, with one is accepted), and the header's OWNERS text is the text the lint's writer emits" ok
else row "S5 Guard 1: a baseline E row has no owner, or the header drifted from the writer" fail "unowned='${S5_OWNER_BAD# }' header-drift='$S5_HDR_BAD' owner-control=$S5_OWNER_CTL"; fi
# The operator hints that used to print the argv `curl -H "Authorization: Bearer ..."` form (echo text and the comment above the id pin) stay off argv: Rule E does not read echo text.
S5_HINT_RE="(-H|--header)[ =]*\\\\*[\"']?authorization:? *bearer"
S5_HINT_CTL="$(printf '%s\n' 'x curl -s -H \"Authorization: Bearer y\"' "x curl -H 'Authorization: Bearer y'" 'x curl --header "Authorization: Bearer y"' 'x curl -H "authorization:bearer y"' | grep -ciE -- "$S5_HINT_RE" || true)"
S5_HINTS="$(grep -ciE -- "$S5_HINT_RE" "$REPO_ROOT/$S5_WF" || true)"
if [[ "$S5_HINT_CTL" == 4 && "$S5_HINTS" == 0 ]]; then row "S5 Guard 1: no operator hint or comment in the apply workflow tells the operator to put the token on a curl argument list (the pattern fires on a planted positive)" ok
else row "S5 Guard 1: the apply workflow still prints the argv curl form to the operator" fail "hints=$S5_HINTS control=$S5_HINT_CTL"; fi
S5_REFUSAL_FLOOR=6
if [[ "$S5_CANARY_RUNS" -ge "$S5_REFUSAL_FLOOR" ]]; then row "S5 negative canary: $S5_CANARY_RUNS runs planted the canary and had every captured stream searched for it (anti-vacuity floor $S5_REFUSAL_FLOOR)" ok
else row "S5 negative canary: the planted-canary run population is below its anti-vacuity floor" fail "runs=$S5_CANARY_RUNS floor=$S5_REFUSAL_FLOOR"; fi

# ---- S5 registry rows (the registry commit): the four Better Stack posting scripts of `cloud-init-registry.yml` ----
# The host has no checkout and a user_data budget, so each script carries the inline form of the library: a judge (`_bs_ok`, the
# library's alphabet) before any request, the bearer on curl's stdin config through a PER-COMMAND redirect, and a refusal that prints
# the value-free marker and takes the not-shipped branch. Population and verdicts are DERIVED from the template; the committed bytes of
# each posting region are EXECUTED (rendered the way templatefile() does: TF variables substituted, `$${` and `%%{` unescaped).
S5_REF_BASE="$S5_CANARY_RUNS"
S5R="$S4/s5reg"; assert_fixture_dir "$S5R"; mkdir -p "$S5R/shim"
cp "$S4/shim/curl" "$S4/shim/sleep" "$S5R/shim/"
printf '#!%s\nprintf "soleur-registry\\n"\n' "$BASH_BIN" > "$S5R/shim/hostname"
# `doppler run ... -- CMD...` runs CMD with the environment the harness set (the real wrapper injects the token from the isolated config).
cat > "$S5R/shim/doppler" <<'S5DOP'
#!/usr/bin/env bash
while [[ $# -gt 0 && "$1" != -- ]]; do shift; done
shift
exec "$@"
S5DOP
sed -i "1s|.*|#!${BASH_BIN}|" "$S5R/shim/doppler"; chmod +x "$S5R/shim/curl" "$S5R/shim/sleep" "$S5R/shim/hostname" "$S5R/shim/doppler"
S5_URL="https://s5-ingest.example.invalid/"
s5_reg_py='
import sys, re, yaml
yml, kind, out = sys.argv[1], sys.argv[2], sys.argv[3]
edits = sys.argv[4:]
d = yaml.safe_load(open(yml))
URL = "https://s5-ingest.example.invalid/"
TOK = "TOKEN=\"$${BETTERSTACK_LOGS_TOKEN:-}\""
def wf(path):
    for f in d["write_files"]:
        if f.get("path") == path: return f["content"]
    sys.exit(3)
def render(t):
    t = t.replace("${betterstack_ingest_url}", URL)
    t = re.sub(r"(?<!\$)\$\{[a-z_][a-z0-9_]*\}", "stub", t)
    return t.replace("$${", "${").replace("%%{", "%{")
def region(c, start_pred, end_pred):
    L = c.split("\n")
    i = next(k for k, l in enumerate(L) if start_pred(l))
    j = next(k for k in range(i + 1, len(L)) if end_pred(L[k], L[i]))
    return "\n".join(L[i:j + 1]) + "\n"
ind = lambda l: len(l) - len(l.lstrip())
if kind == "hb":
    c = wf("/usr/local/bin/zot-disk-heartbeat.sh"); L = c.split("\n")
    i = next(k for k, l in enumerate(L) if l.strip() == TOK)
    raw = "\n".join(L[i:]) + "\n"
elif kind == "nic":
    raw = region(wf("/usr/local/bin/soleur-private-nic-guard.sh"), lambda l: l.strip() == TOK, lambda l, s: l.strip() == "fi" and ind(l) == ind(s))
elif kind == "ship":
    c = wf("/usr/local/bin/zot-log-shipper.sh")
    # the judge block ends at the first `fi` AFTER the line that drops the token
    L = c.split("\n"); i = next(k for k, l in enumerate(L) if l.strip() == TOK)
    j = next(k for k in range(i, len(L)) if "TOKEN_REFUSED=1; TOKEN=" in L[k]); e = next(k for k in range(j, len(L)) if L[k].strip() == "fi")
    a = "\n".join(L[i:e + 1]) + "\n"
    s = next(k for k, l in enumerate(L) if l.strip() == "post_body() {"); t = next(k for k in range(s, len(L)) if "CREDENTIAL BACKSTOP" in L[k])
    raw = a + "\n".join(L[s:t]) + "\n"
elif kind == "boot":
    raw = next(r for r in d["runcmd"] if isinstance(r, str) and "ZLSBOOTEOF" in r)
else:
    sys.exit(4)
for k in range(0, len(edits), 2):
    if edits[k] not in raw: sys.exit(5)
    raw = raw.replace(edits[k], edits[k + 1])
open(out + ".raw", "w").write(raw)
open(out, "w").write(render(raw))
'
# s5_reg_body <kind> <out> [<from> <to>]...: the rendered region (an edit that does not land is FATAL: it would report the baseline)
s5_reg_body_try() { local kind="$1" out="$2"; shift 2; assert_fixture_dir "$out"; python3 -I -c "$s5_reg_py" "$REPO_ROOT/$S5_REG" "$kind" "$out" "$@"; }
s5_reg_body() { s5_reg_body_try "$@" || fatal "S5 could not build the registry region '$1' (it could not be extracted or an edit did not land)"; }
# The runner for a rendered region: the harness prefix, then the region. `set -u` and the LINE a script has built by then.
s5_reg_prefix() { # <kind> -> prints the lines that precede the region
  case "$1" in
    hb|nic) printf 'set -u\nLINE=%s\n' "'SOLEUR_FIXTURE_ROW x=1'" ;;
    ship) printf 'set -u\n' ;;
    boot) : ;;
  esac
}
s5_reg_suffix() { # <kind> -> prints the lines that follow the region
  case "$1" in
    ship) printf 'for i in 1 2 3; do ship "row$i" && r=0 || r=$?; echo "ship$i rc=$r"; done\n' ;;
    *) : ;;
  esac
}
s5_reg_make() { # <kind> <rendered region> <out>: the runnable body
  { s5_reg_prefix "$1"; cat "$2"; s5_reg_suffix "$1"; } > "$3"
}
S5R_N=0
s5_reg_exec() { # <label> <kind> <rendered> [NAME=value ...]: run the region under the recording curl
  local label="$1" kind="$2" rend="$3"; shift 3
  S5R_N=$((S5R_N + 1)); local b="$S5R/run-$S5R_N.sh"; assert_fixture_dir "$b"
  s5_reg_make "$kind" "$rend" "$b"
  local sv="$S4_SHIM"; S4_SHIM="$S5R/shim"
  s5_run "s5r-$label" "$b" "$S4/real" "$@"
  S4_SHIM="$sv"
}
s5_reg_ok() { # the valid-credential contract for one posting script: <token> <calls>
  [[ "$S4_RC" == 0 && "$(s4_ncalls)" == "$2" ]] && s4_calls_ok 1 && [[ "$(s4_stdin_line 1 1)" == "header = \"Authorization: Bearer $1\"" ]] \
    && s4_nowhere_on_argv "$1" && s4_argv_has "$S5_URL" && s4_argv_has 'Content-Type: application/json' && [[ "$(s4_markers)" == 0 ]] && s5_canary_clean
}
s5_reg_refused_ok() { # a refused token: no request, ONE marker naming the script, the not-shipped branch and never the egress-FAILED branch
  # <script name> <reason> <not-shipped fragment>
  [[ "$S4_RC" == 0 && "$(s4_ncalls)" == 0 && "$(s4_markers)" == 1 ]] && grep -qxF -- "SOLEUR_CREDENTIAL_REFUSED script=$1 reason=$2" "$S4_ROW/stderr" \
    && ! grep -q '^SOLEUR_CREDENTIAL_REFUSED' "$S4_ROW/stdout" && s4_said "$3" && ! s4_said 'egress' && ! s4_said 'FAILED' && s5_canary_clean
}
# ---- Guard 1: the template's posting population, derived (set identity by script), and the byte-equal judge ----
s5_reg_census_py='
import sys, re, yaml
d = yaml.safe_load(open(sys.argv[1]))
blocks = {}; dups = []
def add(name, c):
    if name in blocks: dups.append(name)
    blocks[name] = c
for f in d.get("write_files", []):
    c = f.get("content", "")
    if "betterstack_ingest_url" in c: add(f["path"].rsplit("/", 1)[-1].removesuffix(".sh"), c)
for r in d.get("runcmd", []):
    if isinstance(r, str) and "betterstack_ingest_url" in r: add("zot-log-boot", r)
for name in dups: print("DUPLICATE-KEY", name)
for name in sorted(blocks):
    text = re.sub(r"\\\n[ \t]*", " ", blocks[name])
    n = 0; bad = []
    for line in text.split("\n"):
        if line.lstrip().startswith("#") or "curl " not in line or "betterstack_ingest_url" not in line: continue
        n += 1
        if re.search(r"-H\s+[\"\x27]?Authorization", line) or re.search(r"(^|\s)(-u|--user)\s", line): bad.append("credential-header-on-argv")
        for need in ("--disable", "--noproxy", "--config -"):
            if need not in line: bad.append("missing " + need)
    live = "\n".join(l for l in text.split("\n") if not l.lstrip().startswith("#"))
    asg = len(re.findall(r"\$+\{?BETTERSTACK_LOGS_TOKEN", live))   # every EXPANSION of the raw variable, in any spelling
    print(name, n, ",".join(sorted(set(bad))) or "-", asg)
'
s5_reg_census() { python3 -I -c "$s5_reg_census_py" "$1"; } # <yml> -> "<script> <posting curls> <violations>" per script
S5_CENSUS_WANT="$(printf '%s\n' 'soleur-private-nic-guard 1 - 1' 'zot-disk-heartbeat 1 - 1' 'zot-log-boot 1 - 1' 'zot-log-shipper 1 - 1')"
S5_CENSUS_GOT="$(s5_reg_census "$REPO_ROOT/$S5_REG")"
S5_CENSUS_N="$(awk '{n += $2} END {print n + 0}' <<<"$S5_CENSUS_GOT")"
S5_CENSUS_FLOOR=4
if [[ "$S5_CENSUS_GOT" == "$S5_CENSUS_WANT" && "$S5_CENSUS_N" -ge "$S5_CENSUS_FLOOR" ]]; then row "S5 Guard 1 (registry): the derived posting population is exactly the four scripts, each with ONE posting curl that carries no credential header of its own and has --disable, --noproxy and --config - ($S5_CENSUS_N statements; anti-vacuity floor $S5_CENSUS_FLOOR)" ok
else row "S5 Guard 1 (registry): the derived posting population differs from the four scripts, or a posting curl carries the credential on argv" fail "got='${S5_CENSUS_GOT//$'\n'/;}'"; fi
S5_REG_LINT2="$(python3 scripts/lint-shell-trace-credential-refusal.py "$S5_REG" 2>&1)"
if grep -q '^OK:' <<<"$S5_REG_LINT2"; then row "S5 Guard 1 (registry): Rule E on the explicit path of the registry template reports no curl with a credential header of its own" ok
else row "S5 Guard 1 (registry): the registry template still has curl commands that carry a credential header" fail "$(tail -1 <<<"$S5_REG_LINT2")"; fi
# Mutation 2: a SECOND credentialed curl in a script (after a compliant first) is judged RED by the census (a per-script set, not "at least one clean").
S5_REG_MUT="$S4/s5reg/mut-census.yml"
python3 -I -c '
import sys
t = open(sys.argv[1]).read()
needle = "        post_body \"$body\" && return 0\n"
if needle not in t: sys.exit(3)
t = t.replace(needle, needle + "        curl -fsS -m 10 -H \"Authorization: Bearer $TOKEN\" -H \"Content-Type: application/json\" \"${betterstack_ingest_url}\" --data-raw \"$body\"\n", 1)
open(sys.argv[2], "w").write(t)' "$REPO_ROOT/$S5_REG" "$S5_REG_MUT" || fatal "S5 could not build the second-curl mutant"
S5_CENSUS_MUT="$(s5_reg_census "$S5_REG_MUT")"
if [[ "$S5_CENSUS_MUT" != "$S5_CENSUS_WANT" && "$S5_CENSUS_MUT" == *'zot-log-shipper 2 credential-header-on-argv'* ]]; then row "S5 Guard 1 mutation 2 (registry): a second, credentialed curl added to the shipper after a compliant first is judged RED by the per-script census" ok
else row "S5 Guard 1 mutation 2 (registry): a second credentialed curl is not caught" fail "got='${S5_CENSUS_MUT//$'\n'/;}'"; fi
# The judge is ONE text in four places: byte-equal (the parity audit), and it is the library's alphabet.
s5_reg_parity() { # <yml> -> prints OK when the four `_bs_ok` lines are byte-equal and the three `post()` lines are byte-equal; else a reason
  python3 -I -c '
import sys, re
t = open(sys.argv[1]).read().split("\n")
ok = [l.strip() for l in t if l.strip().startswith("_bs_ok() {")]
post = [l.strip() for l in t if l.strip().startswith("post() { curl")]
if len(ok) != 4: print("judge-copies=%d" % len(ok)); sys.exit(0)
if len(set(ok)) != 1: print("judge-copies-differ"); sys.exit(0)
if len(post) != 3: print("post-copies=%d" % len(post)); sys.exit(0)
if len(set(post)) != 1: print("post-copies-differ"); sys.exit(0)
trim = [l.strip() for l in t if l.strip().startswith("TOKEN=\"$${TOKEN%")]
if len(trim) != 4 or len(set(trim)) != 1: print("trim-copies-differ"); sys.exit(0)
mk = [re.sub(r"script=[a-z-]+", "script=X", l.strip()) for l in t if l.strip().startswith("printf \x27SOLEUR_CREDENTIAL_REFUSED script=")]
if len(mk) != 4 or len(set(mk)) != 1: print("marker-copies-differ"); sys.exit(0)
print("OK")' "$1"
}
S5_PAR="$(s5_reg_parity "$REPO_ROOT/$S5_REG")"
S5_PAR_MUT="$S4/s5reg/mut-parity.yml"
python3 -I -c '
import sys
t = open(sys.argv[1]).read()
a = "_bs_ok() { local LC_ALL=C; case"
i = t.index(a, t.index(a) + 10)
open(sys.argv[2], "w").write(t[:i] + "_bs_ok() { local LC_ALL=C ; case" + t[i + len(a):])' "$REPO_ROOT/$S5_REG" "$S5_PAR_MUT" || fatal "S5 could not build the parity mutant"
if [[ "$S5_PAR" == OK && "$(s5_reg_parity "$S5_PAR_MUT")" == judge-copies-differ ]] && ! cmp -s "$REPO_ROOT/$S5_REG" "$S5_PAR_MUT"; then row "S5 Guard 1 parity (registry): the four copies of the judge and the three post() copies are byte-equal, and one changed byte in one judge copy is judged RED" ok
else row "S5 Guard 1 parity (registry): the copies differ, or the audit is blind to one changed byte" fail "real='$S5_PAR' mutant='$(s5_reg_parity "$S5_PAR_MUT")'"; fi
S5_JUDGE="$(grep -m1 '_bs_ok() {' "$REPO_ROOT/$S5_REG" | sed 's/^[[:space:]]*//; s/\$\$/$/g')"
S5_CANON="$(grep -m1 '^_bearer_ok() {' apps/web-platform/infra/web-private-nic-guard.sh)"
S5_JUDGE_BAD=""
if [[ "${S5_JUDGE/_bs_ok/_bearer_ok}" != "$S5_CANON" || -z "$S5_CANON" ]]; then S5_JUDGE_BAD+=" not-the-canonical-body"; fi
S5_JD="$(eval "$S5_JUDGE"; for v in 'abc.DEF-1_2~3+/=' 'x'; do _bs_ok "$v" || printf 'rejected-good:%s ' "$v"; done; for v in '' 'a b' 'a"b' $'a\nb' 'a\b' 'a;b' 'a$b' 'é' $'a\tb' 'a#b' "a'b" 'a,b' 'a`b' $'a\rb'; do _bs_ok "$v" && printf 'accepted-bad ' || true; done)"
[[ -z "$S5_JD" ]] || S5_JUDGE_BAD+=" behaviour:$S5_JD"
if [[ -z "$S5_JUDGE_BAD" ]]; then row "S5 Guard 1 (registry): the host judge is byte-identical to the canonical inline _bearer_ok (modulo the template escape and the name), accepts the library's token alphabet and rejects an empty value, a space, a quote, a backslash, a newline, a tab, a semicolon, a dollar sign and a non-ASCII byte" ok
else row "S5 Guard 1 (registry): the host judge differs from the canonical body or misjudges a value" fail "$S5_JUDGE_BAD"; fi

# ---- bash -n over EVERY rendered script and runcmd block (an escape error in the template cannot pass on raw text) ----
S5_SYN="$(python3 -I -c '
import sys, re, yaml, subprocess
d = yaml.safe_load(open(sys.argv[1]))
URL = "https://s5-ingest.example.invalid/"
def render(t):
    t = t.replace("${betterstack_ingest_url}", URL)
    t = re.sub(r"(?<!\$)\$\{[a-z_][a-z0-9_]*\}", "stub", t)
    return t.replace("$${", "${").replace("%%{", "%{")
n = 0; bad = []
for f in d.get("write_files", []):
    c = f.get("content", "")
    if c.startswith("#!") and "bash" in c.split("\n")[0]:
        n += 1
        if subprocess.run(["bash", "-n"], input=render(c).encode(), capture_output=True).returncode: bad.append(f["path"])
for i, r in enumerate(d.get("runcmd", [])):
    if isinstance(r, str) and "\n" in r:
        n += 1
        if subprocess.run(["bash", "-n"], input=render(r).encode(), capture_output=True).returncode: bad.append("runcmd[%d]" % i)
print(n, ",".join(bad) or "-")' "$REPO_ROOT/$S5_REG")"
S5_SYN_N="${S5_SYN%% *}"; S5_SYN_BAD="${S5_SYN#* }"; S5_SYN_FLOOR=12
if [[ "$S5_SYN_BAD" == - && "$S5_SYN_N" -ge "$S5_SYN_FLOOR" ]]; then row "S5 registry render: every rendered bash script and multi-line runcmd block passes bash -n ($S5_SYN_N checked; anti-vacuity floor $S5_SYN_FLOOR)" ok
else row "S5 registry render: a rendered script or runcmd block is not valid bash, or the population is below its floor" fail "n=$S5_SYN_N bad=$S5_SYN_BAD floor=$S5_SYN_FLOOR"; fi

# ---- Guard 2: execute the committed posting regions ----
S5_HOSTILE_NL="${S5_CANARY}"$'\nx'          # an interior newline (the config-injection byte) with the canary planted
for k in hb nic; do
  case "$k" in
    hb)  n="zot-disk-heartbeat";        warn='WARN: BETTERSTACK_LOGS_TOKEN refused';  unset_warn="WARN: BETTERSTACK_LOGS_TOKEN unset" ;;
    nic) n="soleur-private-nic-guard";  warn='WARN: BETTERSTACK_LOGS_TOKEN refused';  unset_warn="WARN: BETTERSTACK_LOGS_TOKEN unset" ;;
  esac
  s5_reg_body "$k" "$S5R/r-$k.sh"
  s5_reg_exec "$k-hz" "$k" "$S5R/r-$k.sh" BETTERSTACK_LOGS_TOKEN="$S5_HZ"
  if s5_reg_ok "$S5_HZ" 1; then row "S5 Guard 2 (registry $n): a 64-character alphanumeric ingest token is posted once, on curl's stdin config only, to the pinned URL, and the script exits 0" ok
  else row "S5 Guard 2 (registry $n): a valid token is not posted on stdin only" fail "rc=$S4_RC calls=$(s4_ncalls) markers=$(s4_markers)"; fi
  s5_reg_exec "$k-bs" "$k" "$S5R/r-$k.sh" BETTERSTACK_LOGS_TOKEN="$S5_BS"
  if s5_reg_ok "$S5_BS" 1; then row "S5 Guard 2 (registry $n): a Better Stack-shaped token holding an underscore and hyphens is accepted" ok
  else row "S5 Guard 2 (registry $n): a realistic token is refused or mis-sent" fail "rc=$S4_RC calls=$(s4_ncalls)"; fi
  s5_reg_exec "$k-hostile" "$k" "$S5R/r-$k.sh" BETTERSTACK_LOGS_TOKEN="$S5_BAD"; S5_REFUSALS=$((S5_REFUSALS + 1))
  if s5_reg_refused_ok "$n" token_shape "$warn"; then row "S5 Guard 2 (registry $n): a token holding a quote and a space makes no request, prints ONE marker naming the script, takes the not-shipped branch (never the egress-FAILED retry branch) and the script still exits 0" ok
  else row "S5 Guard 2 (registry $n): a refused token reaches the wrong branch or changes the exit status" fail "rc=$S4_RC calls=$(s4_ncalls) markers=$(s4_markers) err='$(tr '\n' '|' < "$S4_ROW/stderr" | cut -c1-160)'"; fi
  s5_reg_exec "$k-ctl" "$k" "$S5R/r-$k.sh" BETTERSTACK_LOGS_TOKEN="$S5_HOSTILE_NL"; S5_REFUSALS=$((S5_REFUSALS + 1))
  if s5_reg_refused_ok "$n" control_char "$warn"; then row "S5 Guard 2 (registry $n): a token holding a newline is refused with reason=control_char (the config-injection byte) and makes no request" ok
  else row "S5 Guard 2 (registry $n): a token with a newline is not refused as control_char" fail "rc=$S4_RC calls=$(s4_ncalls) markers=$(s4_markers)"; fi
  s5_reg_exec "$k-unset" "$k" "$S5R/r-$k.sh"
  if [[ "$S4_RC" == 0 && "$(s4_ncalls)" == 0 && "$(s4_markers)" == 0 ]] && s4_said "$unset_warn"; then row "S5 Guard 2 (registry $n): an unset token keeps the existing arm (the unset WARN, no request, no marker, exit 0)" ok
  else row "S5 Guard 2 (registry $n): an unset token changed verdict" fail "rc=$S4_RC calls=$(s4_ncalls) markers=$(s4_markers)"; fi
  # Mutation 5 (dispatch): drop the judge (always true); the hostile token then reaches curl and the no-request clause goes RED.
  s5_reg_body "$k" "$S5R/m-$k-nojudge.sh" '_bs_ok "$TOKEN"; then' 'true; then'
  s5_reg_exec "$k-nojudge" "$k" "$S5R/m-$k-nojudge.sh" BETTERSTACK_LOGS_TOKEN="$S5_BAD"; S5_REFUSALS=$((S5_REFUSALS + 1))
  if ! s5_reg_refused_ok "$n" token_shape "$warn" && [[ "$(s4_ncalls)" -ge 1 ]]; then row "S5 Guard 2 mutation 5 (registry $n): with the judge dropped a hostile token reaches curl and the shape row goes RED" ok
  else row "S5 Guard 2 mutation 5 (registry $n): a dropped judge is not caught" fail "calls=$(s4_ncalls)"; fi
  # Mutation 2: a refusal that skips the refused branch (it falls to the unset arm: no marker, the unset WARN) is judged RED by the not-shipped-branch row. The retry branch itself is reached only with a usable token (the egress-FAILED rows below).
  s5_reg_body "$k" "$S5R/m-$k-retry.sh" 'elif [ -n "$TOKEN" ]; then' 'elif false; then'
  s5_reg_exec "$k-retry" "$k" "$S5R/m-$k-retry.sh" BETTERSTACK_LOGS_TOKEN="$S5_BAD"; S5_REFUSALS=$((S5_REFUSALS + 1))
  if ! s5_reg_refused_ok "$n" token_shape "$warn"; then row "S5 Guard 2 mutation 2 (registry $n): a refusal that skips the refused branch (it falls to the unset arm: no marker, wrong WARN) is judged RED" ok
  else row "S5 Guard 2 mutation 2 (registry $n): a refusal moved into another branch is not caught" fail "markers=$(s4_markers)"; fi
done
# The boot block is fed to `bash -s` on stdin, so a bare `--config -` would read the rest of the script (the per-command redirect is the fix).
s5_reg_body boot "$S5R/r-boot.sh"
s5_reg_exec boot-hz boot "$S5R/r-boot.sh" BETTERSTACK_LOGS_TOKEN="$S5_HZ"
if s5_reg_ok "$S5_HZ" 1; then row "S5 Guard 2 (registry boot block): run through \`doppler run -- bash -s <<heredoc\` the block posts SOLEUR_ZOT_LOG_BOOT once, on stdin config only, and the heredoc is intact" ok
else row "S5 Guard 2 (registry boot block): the boot post is not sent on stdin only" fail "rc=$S4_RC calls=$(s4_ncalls) stdin='$(s4_stdin_line 1 1 | cut -c1-30)'"; fi
s5_reg_exec boot-hostile boot "$S5R/r-boot.sh" BETTERSTACK_LOGS_TOKEN="$S5_BAD"; S5_REFUSALS=$((S5_REFUSALS + 1))
if s5_reg_refused_ok zot-log-boot token_shape 'WARN: BETTERSTACK_LOGS_TOKEN refused'; then row "S5 Guard 2 (registry boot block): a refused token prints one marker naming zot-log-boot, makes no request and takes the not-shipped branch" ok
else row "S5 Guard 2 (registry boot block): a refused token reaches the wrong branch" fail "rc=$S4_RC calls=$(s4_ncalls) markers=$(s4_markers)"; fi
# Mutation 7 (the heredoc row): drop the per-command redirect; `--config -` then reads the heredoc, so the recorded config holds script lines.
s5_reg_body boot "$S5R/m-boot-noredirect.sh" ' < <(printf '"'"'header = "Authorization: Bearer %s"\n'"'"' "$TOKEN")' ''
s5_reg_exec boot-noredirect boot "$S5R/m-boot-noredirect.sh" BETTERSTACK_LOGS_TOKEN="$S5_HZ"
if ! s5_reg_ok "$S5_HZ" 1; then row "S5 Guard 2 mutation 7 (registry boot block): dropping the per-command stdin redirect is judged RED (curl would read the heredoc as its config)" ok
else row "S5 Guard 2 mutation 7 (registry boot block): the dropped redirect is not caught" fail "calls=$(s4_ncalls)"; fi

# The shipper: the credential is judged ONCE per run (a refusal is one marker per five-minute run, not one per row).
s5_ship_valid_ok() { # three ship() calls: three requests, three zero statuses, no marker
  [[ "$S4_RC" == 0 && "$(s4_ncalls)" == 3 && "$(s4_markers)" == 0 ]] && s4_calls_ok 1 && [[ "$(s4_stdin_line 1 1)" == "header = \"Authorization: Bearer $1\"" ]] \
    && s4_nowhere_on_argv "$1" && s4_said 'ship1 rc=0' && s4_said 'ship3 rc=0' && s5_canary_clean
}
s5_ship_refused_ok() { # [reason] three ship() calls over a refused token: no request, ONE marker, three not-shipped returns, the refused wording
  [[ "$S4_RC" == 0 && "$(s4_ncalls)" == 0 && "$(s4_markers)" == 1 ]] && grep -qxF -- "SOLEUR_CREDENTIAL_REFUSED script=zot-log-shipper reason=${1:-token_shape}" "$S4_ROW/stderr" \
    && s4_said 'ship1 rc=1' && s4_said 'ship3 rc=1' && s4_said 'BETTERSTACK_LOGS_TOKEN refused' && ! s4_said 'unset; not shipped' && ! s4_said 'FAILED' && s5_canary_clean
}
s5_reg_body ship "$S5R/r-ship.sh"
s5_reg_exec ship-hz ship "$S5R/r-ship.sh" BETTERSTACK_LOGS_TOKEN="$S5_HZ"
if s5_ship_valid_ok "$S5_HZ"; then row "S5 Guard 2 (registry zot-log-shipper): three rows are posted one request each, on stdin config only, and ship() returns 0" ok
else row "S5 Guard 2 (registry zot-log-shipper): a valid token is not posted on stdin only" fail "rc=$S4_RC calls=$(s4_ncalls) markers=$(s4_markers)"; fi
s5_reg_exec ship-hostile ship "$S5R/r-ship.sh" BETTERSTACK_LOGS_TOKEN="$S5_BAD"; S5_REFUSALS=$((S5_REFUSALS + 1))
if s5_ship_refused_ok; then row "S5 Guard 2 (registry zot-log-shipper): a refused token gives ONE marker for three rows (judged once per run), no request, three not-shipped returns, and the WARN says refused (not unset)" ok
else row "S5 Guard 2 (registry zot-log-shipper): the refusal is not once-per-run or reaches the wrong branch" fail "rc=$S4_RC calls=$(s4_ncalls) markers=$(s4_markers)"; fi
s5_reg_exec ship-unset ship "$S5R/r-ship.sh"
if [[ "$S4_RC" == 0 && "$(s4_ncalls)" == 0 && "$(s4_markers)" == 0 ]] && s4_said 'unset; not shipped' && s4_said 'ship2 rc=1'; then row "S5 Guard 2 (registry zot-log-shipper): an unset token keeps the existing arm (the unset WARN per row, no request, no marker)" ok
else row "S5 Guard 2 (registry zot-log-shipper): an unset token changed verdict" fail "rc=$S4_RC calls=$(s4_ncalls) markers=$(s4_markers)"; fi
# Mutation 3 (once-per-run): move the judge into ship() so each row re-judges; three markers for three rows must be judged RED.
s5_reg_body ship "$S5R/m-ship-perrow.sh" 'if [ -n "$TOKEN" ] && ! _bs_ok "$TOKEN"; then' 'if false; then' \
  'local line="$1" body' 'local line="$1" body; if [ -n "$TOKEN" ] && ! _bs_ok "$TOKEN"; then printf '"'"'SOLEUR_CREDENTIAL_REFUSED script=zot-log-shipper reason=token_shape\n'"'"' >&2; TOKEN_REFUSED=1; fi'
s5_reg_exec ship-perrow ship "$S5R/m-ship-perrow.sh" BETTERSTACK_LOGS_TOKEN="$S5_BAD"; S5_REFUSALS=$((S5_REFUSALS + 1))
if ! s5_ship_refused_ok && [[ "$(s4_markers)" -gt 1 ]]; then row "S5 Guard 2 mutation 3 (registry zot-log-shipper): a judge moved inside ship() prints a marker per row and is judged RED by the once-per-run row" ok
else row "S5 Guard 2 mutation 3 (registry zot-log-shipper): a per-row judge is not caught" fail "markers=$(s4_markers)"; fi
# Mutation 4 (cron must not wedge): a refusal that changes the script's exit status.
s5_reg_body hb "$S5R/m-hb-exit.sh" 'elif [ -n "$TOKEN" ]; then' 'elif [ -n "$TOKEN" ]; then exit 3;'
s5_reg_exec hb-exit hb "$S5R/m-hb-exit.sh" BETTERSTACK_LOGS_TOKEN="$S5_BAD"; S5_REFUSALS=$((S5_REFUSALS + 1))
if ! s5_reg_refused_ok zot-disk-heartbeat token_shape 'WARN: BETTERSTACK_LOGS_TOKEN refused' && [[ "$S4_RC" != 0 ]]; then row "S5 Guard 2 mutation 4 (registry zot-disk-heartbeat): a refusal that changes the exit status is judged RED (the cron job must never wedge)" ok
else row "S5 Guard 2 mutation 4 (registry zot-disk-heartbeat): a changed exit status is not caught" fail "rc=$S4_RC"; fi

# ---- review-round rows (registry side): trailing whitespace, the egress-FAILED branch, control_char for every script, the single token read ----
# A stored value with trailing whitespace worked on the old argv form (curl sent the trimmed header), so it must still post, trimmed, from all four scripts.
for k in hb nic boot ship; do
  case "$k" in hb) n=zot-disk-heartbeat ;; nic) n=soleur-private-nic-guard ;; boot) n=zot-log-boot ;; ship) n=zot-log-shipper ;; esac
  S5_WS_BAD=""
  for ws in "$S5_HZ"$'\n' "$S5_HZ " "$S5_HZ"$'\t' "$S5_HZ"$'\r' "$S5_HZ"$'\r\n'; do
    s5_reg_exec "$k-ws" "$k" "$S5R/r-$k.sh" BETTERSTACK_LOGS_TOKEN="$ws"
    if [[ "$k" == ship ]]; then s5_ship_valid_ok "$S5_HZ" || S5_WS_BAD+=" ws"; else s5_reg_ok "$S5_HZ" 1 || S5_WS_BAD+=" ws"; fi
  done
  if [[ -z "$S5_WS_BAD" ]]; then row "S5 Guard 2 (registry $n): a token stored with a trailing newline, space or tab is trimmed and posted on stdin config (it worked on the old argv form, so it must not silently go dark)" ok
  else row "S5 Guard 2 (registry $n): a token with trailing whitespace is not posted trimmed" fail "bad=$(wc -w <<<"$S5_WS_BAD")"; fi
done
s5_reg_body nic "$S5R/m-nic-notrim.sh" 'TOKEN="$${TOKEN%"$${TOKEN##*[![:space:]]}"}"' ':'
s5_reg_exec nic-notrim nic "$S5R/m-nic-notrim.sh" BETTERSTACK_LOGS_TOKEN="$S5_HZ"$'\n'
if ! s5_reg_ok "$S5_HZ" 1; then row "S5 Guard 2 mutation (registry soleur-private-nic-guard): dropping the trim makes a trailing-newline token go dark, judged RED by the trailing-whitespace row" ok
else row "S5 Guard 2 mutation (registry soleur-private-nic-guard): a dropped trim is not caught" fail "calls=$(s4_ncalls)"; fi
# The egress-FAILED branch is the existing one: a valid token and a failing curl retries once and says so (and a refusal never reaches it, asserted above).
for k in hb nic boot; do
  case "$k" in hb) n=zot-disk-heartbeat ;; nic) n=soleur-private-nic-guard ;; boot) n=zot-log-boot ;; esac
  s5_reg_exec "$k-egress" "$k" "$S5R/r-$k.sh" BETTERSTACK_LOGS_TOKEN="$S5_HZ" SHIM_RC=22
  if [[ "$S4_RC" == 0 && "$(s4_ncalls)" == 2 && "$(s4_markers)" == 0 ]] && s4_said 'FAILED'; then row "S5 Guard 2 (registry $n): a valid token and a failing curl takes the retry-once egress-FAILED branch (two requests, the FAILED line, exit status unchanged)" ok
  else row "S5 Guard 2 (registry $n): the egress-FAILED branch changed" fail "rc=$S4_RC calls=$(s4_ncalls)"; fi
done
# control_char for the two scripts the loop above does not reach, with the canary planted and the exact marker line on stderr only.
s5_reg_exec boot-ctl boot "$S5R/r-boot.sh" BETTERSTACK_LOGS_TOKEN="$S5_HOSTILE_NL"
if s5_reg_refused_ok zot-log-boot control_char 'WARN: BETTERSTACK_LOGS_TOKEN refused'; then row "S5 Guard 2 (registry boot block): a token holding a newline is refused with reason=control_char, exact marker line on stderr, no leak" ok
else row "S5 Guard 2 (registry boot block): a newline token is not refused as control_char" fail "rc=$S4_RC calls=$(s4_ncalls) markers=$(s4_markers)"; fi
s5_reg_exec ship-ctl ship "$S5R/r-ship.sh" BETTERSTACK_LOGS_TOKEN="$S5_HOSTILE_NL"
if s5_ship_refused_ok control_char; then row "S5 Guard 2 (registry zot-log-shipper): a token holding a newline gives ONE control_char marker for three rows and no request" ok
else row "S5 Guard 2 (registry zot-log-shipper): a newline token is not refused as control_char once per run" fail "rc=$S4_RC calls=$(s4_ncalls) markers=$(s4_markers)"; fi
# The shipper (like every posting script) reads the raw token ONCE: a second read after the judge would hand an unjudged value to the config channel.
S5_REG_MUT2="$S4/s5reg/mut-reread.yml"
python3 -I -c '
import sys
t = open(sys.argv[1]).read()
n = "      HOST_NAME_V=\"$(hostname)\"\n"
if t.count(n) != 1: sys.exit(3)
open(sys.argv[2], "w").write(t.replace(n, n + "      TOKEN=\"$${BETTERSTACK_LOGS_TOKEN:-}\"\n"))' "$REPO_ROOT/$S5_REG" "$S5_REG_MUT2" || fatal "S5 could not build the token re-read mutant"
if [[ "$(s5_reg_census "$S5_REG_MUT2")" == *'zot-log-shipper 1 - 2'* ]]; then row "S5 Guard 1 mutation (registry): a second raw read of the token after the judge in the shipper is judged RED by the single-assignment census" ok
else row "S5 Guard 1 mutation (registry): a re-read of the raw token is not caught" fail "got='$(s5_reg_census "$S5_REG_MUT2" | tr '\n' ';')'"; fi
S5_REG_MUT3="$S4/s5reg/mut-reread2.yml"
python3 -I -c '
import sys
t = open(sys.argv[1]).read()
n = "      HOST_NAME_V=\"$(hostname)\"\n"
if t.count(n) != 1: sys.exit(3)
open(sys.argv[2], "w").write(t.replace(n, n + "      TOKEN=\"$${BETTERSTACK_LOGS_TOKEN}\"\n"))' "$REPO_ROOT/$S5_REG" "$S5_REG_MUT3" || fatal "S5 could not build the token re-read mutant (no default operator)"
if [[ "$(s5_reg_census "$S5_REG_MUT3")" == *'zot-log-shipper 1 - 2'* ]]; then row "S5 Guard 1 mutation (registry): a second raw read of the token in a DIFFERENT spelling (no :- default) is judged RED by the every-expansion census" ok
else row "S5 Guard 1 mutation (registry): a differently spelled re-read of the raw token is not caught" fail "got='$(s5_reg_census "$S5_REG_MUT3" | tr '\n' ';')'"; fi
# The marker text is one text in four places too: change one copy's reason computation and the parity audit goes RED.
S5_PAR_MUT2="$S4/s5reg/mut-marker.yml"
python3 -I -c '
import sys
t = open(sys.argv[1]).read()
a = "*[[:cntrl:]]*) echo control_char ;;"
i = t.rindex(a)
open(sys.argv[2], "w").write(t[:i] + "*[[:cntrl:]]*) echo token_shape ;;" + t[i + len(a):])' "$REPO_ROOT/$S5_REG" "$S5_PAR_MUT2" || fatal "S5 could not build the marker parity mutant"
if [[ "$(s5_reg_parity "$S5_PAR_MUT2")" == marker-copies-differ ]]; then row "S5 Guard 1 parity (registry): the trim and the refusal marker are byte-equal across the four scripts, and one changed reason computation is judged RED" ok
else row "S5 Guard 1 parity (registry): a changed marker copy is not caught" fail "got='$(s5_reg_parity "$S5_PAR_MUT2")'"; fi
S5_REG_REFUSAL_FLOOR=14
if [[ $((S5_CANARY_RUNS - S5_REF_BASE)) -ge "$S5_REG_REFUSAL_FLOOR" ]]; then row "S5 negative canary (registry): $((S5_CANARY_RUNS - S5_REF_BASE)) runs of the registry regions planted the canary and had every captured stream searched for it (anti-vacuity floor $S5_REG_REFUSAL_FLOOR)" ok
else row "S5 negative canary (registry): the planted-canary run population is below its anti-vacuity floor" fail "runs=$((S5_CANARY_RUNS - S5_REF_BASE)) floor=$S5_REG_REFUSAL_FLOOR"; fi
echo "=== stage S5: Guard 1 and Guard 2 rows for the apply workflow and the registry template done ==="

