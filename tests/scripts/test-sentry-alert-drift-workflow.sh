#!/usr/bin/env bash
# The verdict branching in scheduled-sentry-alert-drift.yml (#7650 §2.9).
#
# WHY THIS EXISTS AS A TEST RATHER THAN A READING. The probe step decides which of
# three things happens to a divergence in 27 live paging rules: file an issue,
# close one, or neither. Two of those three outcomes are SILENT when wrong —
# a verdict that files nothing looks exactly like a clean run, and a wrongly
# closed issue looks exactly like a fixed one. Neither is visible in a green
# workflow list.
#
# The step's shell is EXTRACTED FROM THE SHIPPED YAML and executed, never
# restated here. A restatement passes forever after the workflow changes
# underneath it — the failure mode test-sentry-brownout-retry.sh's header
# records having shipped twice.
#
# TWO ROWS WERE CUT AT REVIEW and the reason is worth keeping. `t_discriminates`
# re-asserted `verdict == drift` and `verdict == unavailable`, which W2 and W3
# already assert — it could not fail unless one of them had already failed. And a
# status-function check on the issue steps duplicated
# `scripts/alarm-issue-filing-guard.test.sh`, which walks EVERY workflow in the
# repo and ratchets against a highwater file; that highwater is unchanged by this
# PR, which is itself the evidence the repo-wide gate already walked this file
# and found it clean. A second implementation of a live gate is not
# defence-in-depth, it is a second thing to keep true.
#
# The one branch that matters most is `unavailable`. If the probe cannot reach
# Sentry, this run establishes NOTHING; closing a real drift issue on that
# basis is the worst outcome the workflow can produce, and it is the outcome a
# `!= drift` condition would have produced.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# Overridable so the in-suite mutation rows (W8-a..e, W9-a) can point the SAME
# check functions at a PyYAML-mutated temp copy and assert they go RED. A check
# that has never been driven red is a reading, not a test.
WF="${SENTRY_DRIFT_WF:-$REPO_ROOT/.github/workflows/scheduled-sentry-alert-drift.yml}"
pass=0; fail=0
EXPECTED_TESTS=20

TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT

_report() {
  local label="$1" status="$2" detail="${3:-}"
  if [[ "$status" == "ok" ]]; then pass=$((pass + 1)); echo "[ok] $label"
  else fail=$((fail + 1)); echo "[FAIL] $label $detail" >&2; fi
}

[[ -f "$WF" ]] || { echo "ERROR: $WF does not exist — RED phase expected this." >&2; exit 1; }

# Extract the shipped `run:` block for the step whose id is `probe`.
if ! python3 - "$WF" "$TMPD/probe-step.sh" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
steps = d["jobs"]["drift-check"]["steps"]
probe = [s for s in steps if s.get("id") == "probe"]
if len(probe) != 1:
    sys.exit(f"expected exactly one step with id 'probe', found {len(probe)}")
open(sys.argv[2], "w").write(probe[0]["run"])
PY
then
  echo "ERROR: could not extract the probe step from $WF — the anchor (id: probe) moved." >&2
  exit 1
fi

# Non-vacuity on the EXTRACTION itself. An empty or truncated slice would let
# every case below "pass" by doing nothing.
if [[ ! -s "$TMPD/probe-step.sh" ]] || ! grep -q 'verdict=' "$TMPD/probe-step.sh"; then
  echo "ERROR: the extracted probe step is empty or carries no verdict assignment." >&2
  exit 1
fi

# _drive <stub-body> — runs the SHIPPED step with the probe script stubbed.
# Sets $_rc (the step's exit) and $_out (its GITHUB_OUTPUT contents).
_rc=0; _out=""
_drive() {
  local dir="$TMPD/run.$RANDOM"
  mkdir -p "$dir/scripts"
  printf '%s' "$1" > "$dir/scripts/sentry-alert-live-fidelity.sh"
  _rc=0
  _out=$( cd "$dir" && RUNNER_TEMP="$dir" GITHUB_OUTPUT="$dir/out.txt" \
          bash "$TMPD/probe-step.sh" >/dev/null 2>&1; echo "rc=$?"; cat "$dir/out.txt" 2>/dev/null )
  _rc=$(sed -n 's/^rc=//p' <<<"$_out" | head -1)
}

STUB_CLEAN='#!/usr/bin/env bash
echo "sentry_alert live fidelity: PASS (all 27 in-scope rules match the committed capture field-for-field)"
exit 0'
STUB_DRIFT='#!/usr/bin/env bash
echo "  DELETED or RENAMED: byok-art-33-breach"
echo "ERROR: sentry_alert live fidelity FAILED — 1 divergence(s)." >&2
exit 1'
STUB_UNAVAIL='#!/usr/bin/env bash
echo "ERROR: Sentry workflows response is not a JSON array." >&2
exit 1'
# The probe has exits other than 0/1: 78 (xtrace refusal), 2 (destination
# refusal), 5 (a raw jq error), 127 (missing binary). The step's branch was
# pinned only by stubs exiting 0 or 1, so an `-eq 0`→`-ne 1` refactor would have
# turned every one of these into verdict=clean (review mutation).
STUB_RC78='#!/usr/bin/env bash
echo "[FATAL] refusing to run under xtrace with a live credential set" >&2
exit 78'

t_clean() {
  _drive "$STUB_CLEAN"
  if [[ "$_rc" == "0" ]] && grep -q '^verdict=clean$' <<<"$_out"; then
    _report "W1 a matching probe yields verdict=clean and a green step" ok
  else _report "W1 clean" fail "rc=$_rc out='$_out'"; fi
}

# The step must SUCCEED on drift. A failing step would skip the filer under its
# own `always()`-less siblings and, more importantly, would conflate "drift
# found" with "probe broken" — the distinction the whole verdict exists to draw.
t_drift() {
  _drive "$STUB_DRIFT"
  if [[ "$_rc" == "0" ]] && grep -q '^verdict=drift$' <<<"$_out"; then
    _report "W2 a divergence yields verdict=drift and a GREEN step, so the filer can run" ok
  else _report "W2 drift" fail "rc=$_rc out='$_out'"; fi
}

# The probe exits 1 for BOTH drift and transport failure. The discriminator is
# the marker it prints, so a transport failure must not be read as drift.
t_unavailable() {
  _drive "$STUB_UNAVAIL"
  if [[ "$_rc" == "1" ]] && grep -q '^verdict=unavailable$' <<<"$_out"; then
    _report "W3 a probe that could not complete yields verdict=unavailable and REDS the step" ok
  else _report "W3 unavailable" fail "rc=$_rc out='$_out'"; fi
}

t_unavailable_on_other_exit_codes() {
  local stub rc bad=""
  for rc in 78 2 5 127; do
    stub="${STUB_RC78/exit 78/exit $rc}"
    _drive "$stub"
    if [[ "$_rc" != "1" ]] || ! grep -q '^verdict=unavailable$' <<<"$_out"; then bad+=" [probe exit $rc → rc=$_rc $(grep '^verdict=' <<<"$_out" | tr '\n' ' ')]"; fi
  done
  if [[ -z "$bad" ]]; then
    _report "W3b probe exits 78/2/5/127 (refusals, jq error, missing binary) all yield verdict=unavailable and a RED step — never clean" ok
  else _report "W3b non-0/1 probe exits are unavailable" fail "$bad"; fi
}

# The close arm must be gated on `clean` ITSELF, never on `!= drift`. Under
# `!= drift`, an `unavailable` run closes a real drift issue because the probe
# could not reach Sentry — a false all-clear on 27 paging rules.
# _close_gated_ok <wf> — PER STEP, by id: a concatenated blob over every "Close"
# step let one closer lose its `== 'clean'` while the other still carried it
# (review mutation). 0 when both closers are gated on clean under always().
_close_gated_ok() {
  local id cond bad=""
  for id in close_unavailable close_drift; do
    if ! cond=$(_step_field "$1" id "$id" if 2>&1); then bad+=" [$id: $cond]"; continue; fi
    cond=$(_collapse <<<"$cond")
    grep -qF -- "verdict == 'clean'" <<<"$cond" || bad+=" [$id lacks == 'clean']"
    grep -qF -- "!=" <<<"$cond" && bad+=" [$id carries an inequality]"
    grep -qF -- "always()" <<<"$cond" || bad+=" [$id lacks always() — implicit success() skips it on every drift run]"
  done
  [[ -z "$bad" ]] && return 0
  echo "$bad"; return 1
}
t_close_gated_on_clean_only() {
  local why
  if why=$(_close_gated_ok "$WF"); then
    _report "W5 both close arms are gated on verdict == 'clean' (never '!= drift'), each under always()" ok
  else
    _report "W5 close arm gating" fail "$why"
  fi
}

# W7 — THE CONTRACT BETWEEN THE STEP AND THE PROBE.
#
# W1-W5 drive the shipped step against STUBS, and `STUB_DRIFT` hard-codes the
# marker `live fidelity FAILED` because that is what the step greps. So the
# suite verifies the step reads its own literal correctly and says NOTHING about
# whether the probe still emits it. Renaming the marker in
# `scripts/sentry-alert-live-fidelity.sh` left this suite AND the probe's own
# suite fully green while, in production, every drift verdict would reclassify as
# `unavailable`: the drift issue would never file, and the close arm would never
# fire. Verified by the review's mutation battery.
#
# This row closes the gap by running the REAL probe on a REAL divergence and
# asserting its output carries the literal the REAL step greps — both sides read
# from the shipped files, neither is restated here.
t_probe_marker_matches_what_the_step_greps() {
  local probe="$REPO_ROOT/scripts/sentry-alert-live-fidelity.sh"
  local capture="$REPO_ROOT/knowledge-base/project/specs/fix-7650-sentry-alert-migration/phase2-live-workflows-capture-2026-09-04.json"
  if [[ ! -f "$probe" || ! -f "$capture" ]]; then
    _report "W7 the probe emits the marker the step greps" fail "probe or capture missing"
    return
  fi
  # The literal the SHIPPED step greps, extracted rather than retyped.
  local marker
  marker=$(grep -oE "grep -q '[^']+' \"\\$\{RUNNER_TEMP\}/probe.txt\"" "$TMPD/probe-step.sh" \
           | sed "s/.*grep -q '//; s/'.*//")
  if [[ -z "$marker" ]]; then
    _report "W7 the probe emits the marker the step greps" fail \
      "could not extract the step's grep literal — the anchor moved"
    return
  fi
  # A REAL divergence through the REAL probe.
  local mut="$TMPD/w7-drift.json"
  jq -c 'map(select(.name != "byok-art-33-breach"))' "$capture" > "$mut" 2>/dev/null
  local out
  out=$(SENTRY_AUTH_TOKEN=fixture SENTRY_ORG=fixture SENTRY_FIXTURE_RULES="$mut" \
        bash "$probe" 2>&1) || true
  if grep -qF "$marker" <<<"$out"; then
    _report "W7 the real probe emits the exact marker the real step greps ('$marker')" ok
  else
    _report "W7 the real probe emits the marker the step greps" fail \
      "the step greps '$marker' and the probe does not emit it — every drift would reclassify as 'unavailable', so no drift issue is ever filed"
  fi
}


# ── W8 / W9 — the dead-man's switch and the title key (#8050) ─────────────────
#
# THE MEASURED FALSE POSITIVE. Run 34573504979 (2026-09-11 07:15 UTC) reached
# `verdict=drift`, filed the drift issue (#8057) — and then ALSO filed #8058,
# "the drift probe could not establish a verdict", whose body read `Verdict
# reached: drift`. The filer was gated `if: always() && failure()`, and the
# drift filer two steps above it ends in a deliberate `exit 1` on every drift
# verdict, so `failure()` was true on exactly the class of run the step was
# written to exclude. The gate below is on the VERDICT pair `(verdict, filed)`,
# never on job status.
#
# These rows read the `if:` TEXT via PyYAML rather than executing it — GitHub's
# expression evaluator is not available locally — so each is paired with an
# in-suite mutation of a temp copy (YAML-level, not `sed`: five other steps in
# this file carry `always() &&`, and a single-line `s///` outside a range hits
# the wrong one first) that must drive the SAME check red. The landing assert
# re-loads the copy and compares the DOCUMENT, not the file bytes.

# _step_field <wf> <selector-kind> <selector> <field> — prints the field of the
# ONE matching step, or exits 3 with a message when the selector does not match
# exactly one step. Selector kinds: `id` (exact) and `name_prefix`.
_step_field() {
  python3 - "$1" "$2" "$3" "$4" <<'PYEOF'
import sys, yaml
wf, kind, sel, field = sys.argv[1:5]
d = yaml.safe_load(open(wf))
steps = d["jobs"]["drift-check"]["steps"]
if kind == "id":
    m = [s for s in steps if s.get("id") == sel]
else:
    m = [s for s in steps if (s.get("name") or "").startswith(sel)]
if len(m) != 1:
    sys.exit(f"expected exactly one step matching {kind}={sel!r}, found {len(m)}")
v = m[0].get(field, "")
print(v if isinstance(v, str) else yaml.safe_dump(v))
PYEOF
}

# _collapse — whitespace-insensitive text for the `if:` assertions. A
# multi-line `if: >-` folds differently from a one-liner and both are the same
# expression to GitHub.
_collapse() { tr -s ' \n\t' ' ' | sed 's/^ //; s/ $//'; }

# _w8_filer_gate_ok <wf> — 0 when the probe-unavailable filer is gated on the
# verdict pair; non-zero with a reason on stdout otherwise.
# The EXACT expressions, whitespace-collapsed. Substring presence let a bare
# `filed != 'true'` (no `verdict == 'drift' &&` pairing — files on every CLEAN
# run), an appended `|| true`, a `&&`→`||` swap, and a wrong `steps.<id>` prefix
# all pass (review mutations). GitHub's evaluator is not available locally, so
# the text IS the contract; the diagnostic names the first missing fragment so a
# legitimate edit still reads as a specific reason.
FILER_IF="always() && !cancelled() && (steps.probe.outputs.verdict == 'unavailable' || steps.probe.outputs.verdict == '' || (steps.probe.outputs.verdict == 'drift' && steps.file_drift.outputs.filed != 'true'))"
CLOSER_IF="always() && (steps.probe.outputs.verdict == 'clean' || (steps.probe.outputs.verdict == 'drift' && steps.file_drift.outputs.filed == 'true'))"
_w8_filer_gate_ok() {
  local cond
  if ! cond=$(_step_field "$1" id file_unavailable if 2>&1); then
    echo "selector floor: $cond"; return 1
  fi
  cond=$(_collapse <<<"$cond")
  [[ "$cond" == "$FILER_IF" ]] && return 0
  local why=()
  grep -qF -- '!cancelled()' <<<"$cond" || why+=("missing !cancelled() — a Stop click or timeout would file a false issue")
  grep -qF -- "verdict == 'unavailable'" <<<"$cond" || why+=("missing the 'unavailable' arm")
  grep -qF -- "verdict == ''" <<<"$cond" || why+=("missing the == '' arm — a run that aborts before the probe writes a verdict would file nothing")
  grep -qF -- "(steps.probe.outputs.verdict == 'drift' && steps.file_drift.outputs.filed != 'true')" <<<"$cond" || why+=("missing the paired drift-not-filed arm (a bare filed != 'true' files on every CLEAN run)")
  grep -qF -- 'failure()' <<<"$cond" && why+=("contains failure() — true on every drift verdict because the drift filer exits 1 by design (#8058)")
  why+=("expression is not exactly: $FILER_IF (got: $cond)")
  printf '%s; ' "${why[@]}"; echo; return 1
}

# _w8_closer_gate_ok <wf> — the probe-unavailable CLOSER must be disjoint from
# the filer on the pair `(verdict, filed)`: without the `filed == 'true'`
# conjunct it runs on the very arm the filer adds (`drift` + not filed) and
# closes the issue the filer just opened in the same run.
_w8_closer_gate_ok() {
  local cond
  if ! cond=$(_step_field "$1" id close_unavailable if 2>&1); then
    echo "selector floor: $cond"; return 1
  fi
  cond=$(_collapse <<<"$cond")
  [[ "$cond" == "$CLOSER_IF" ]] && return 0
  local why=()
  grep -qF -- "verdict == 'clean'" <<<"$cond" || why+=("missing the 'clean' arm")
  grep -qF -- "verdict == 'drift' && steps.file_drift.outputs.filed == 'true'" <<<"$cond" || why+=("the 'drift' arm lacks the filed == 'true' conjunct — the closer would undo the filer's drift-not-filed arm in the same run")
  grep -qF -- "!=" <<<"$cond" && why+=("contains an inequality")
  grep -qF -- "always()" <<<"$cond" || why+=("missing always() — implicit success() skips the closer on every drift run")
  why+=("expression is not exactly: $CLOSER_IF (got: $cond)")
  printf '%s; ' "${why[@]}"; echo; return 1
}

# _w9_title_parity_ok <wf> — the drift TITLE is ONE string, defined once at
# job-level env and referenced (never restated) by the filer and its closer.
# _w9_title_parity_ok <wf> [env-key filer-id closer-id expected-literal]
_w9_title_parity_ok() {
  python3 - "$1" "${2:-DRIFT_TITLE}" "${3:-file_drift}" "${4:-close_drift}" \
    "${5:-[ci/sentry-alert-drift] a migrated Sentry alert has drifted from the committed capture}" <<'PYEOF'
import sys, yaml
wf, key, filer_id, closer_id, want = sys.argv[1:6]
d = yaml.safe_load(open(wf))
job = d["jobs"]["drift-check"]
env = job.get("env") or {}
title = env.get(key)
if title != want:
    sys.exit(f"jobs.drift-check.env.{key} is {title!r}, want the unchanged literal")
steps = job["steps"]
filer = [s for s in steps if s.get("id") == filer_id]
closer = [s for s in steps if s.get("id") == closer_id]
if len(filer) != 1 or len(closer) != 1:
    sys.exit(f"expected one step id={filer_id} and one id={closer_id}, found {len(filer)}/{len(closer)}")
bad = []
for label, s in (("filer", filer[0]), ("closer", closer[0])):
    run = s.get("run", "")
    if f'"${key}"' not in run:
        bad.append(f"{label} does not reference \"${key}\"")
    if want in run:
        bad.append(f"{label} restates the title literal inline — a second copy is a second thing to keep true")
    if "${{ env." in run:
        bad.append(f"{label} interpolates env into the shell string; read it as $VAR")
if bad:
    sys.exit("; ".join(bad))
PYEOF
}
_w9_unavailable_title_parity_ok() {
  _w9_title_parity_ok "$1" UNAVAILABLE_TITLE file_unavailable close_unavailable \
    "[ci/sentry-alert-drift] the drift probe could not establish a verdict"
}
t_w9b_unavailable_title_is_one_string() {
  local why
  if why=$(_w9_unavailable_title_parity_ok "$WF" 2>&1); then
    _report "W9b the UNAVAILABLE TITLE is defined once (env.UNAVAILABLE_TITLE) and referenced by its filer and closer" ok
  else
    _report "W9b unavailable title parity" fail "$why"
  fi
}

t_w8_filer_gated_on_verdict_pair() {
  local why
  if why=$(_w8_filer_gate_ok "$WF"); then
    _report "W8 the probe-unavailable filer is gated on (verdict, filed) with !cancelled(), never on failure()" ok
  else
    _report "W8 probe-unavailable filer gate" fail "$why"
  fi
}

t_w8_closer_disjoint_from_filer() {
  local why
  if why=$(_w8_closer_gate_ok "$WF"); then
    _report "W8c the probe-unavailable closer carries the filed == 'true' conjunct (disjoint from the filer)" ok
  else
    _report "W8c probe-unavailable closer gate" fail "$why"
  fi
}

t_w9_title_is_one_string() {
  local why
  if why=$(_w9_title_parity_ok "$WF" 2>&1); then
    _report "W9 the drift TITLE is defined once (env.DRIFT_TITLE) and referenced by filer and closer" ok
  else
    _report "W9 drift title parity" fail "$why"
  fi
}

# _mutate_wf <label> <python-body> — writes a mutated copy of $WF to
# $TMPD/<label>.yml. The python body receives `steps` (the job's step list) and
# edits in place. The landing assert reloads the copy and requires the DOCUMENT
# to differ from the shipped one — a mutation that did not land would make the
# row below re-test the shipped file and pass for the wrong reason.
# Prints the path, or `NOLAND`/`PYFAIL`.
_mutate_wf() {
  local label="$1" body="$2" out="$TMPD/$1.yml" rc=0
  python3 - "$WF" "$out" "$body" <<'PYEOF' 2>"$TMPD/$label.err" || rc=$?
import sys, yaml, copy
src, out, body = sys.argv[1:4]
d = yaml.safe_load(open(src))
orig = copy.deepcopy(d)
steps = d["jobs"]["drift-check"]["steps"]
exec(body, {"d": d, "steps": steps})
yaml.safe_dump(d, open(out, "w"), sort_keys=False, width=10000)
# exit 7 is the LANDING floor, distinct from any python failure.
if yaml.safe_load(open(out)) == orig:
    sys.exit(7)
PYEOF
  case "$rc" in
    0) echo "$out" ;;
    7) echo "NOLAND" ;;
    *) echo "PYFAIL" ;;
  esac
}

# _red_row <test-label> <mutant-path-or-marker> <check-fn> <expected-substring>
_red_row() {
  local label="$1" f="$2" fn="$3" want="$4" why
  if [[ "$f" == "PYFAIL" || "$f" == "NOLAND" ]]; then
    _report "$label" fail "the mutation did not land ($f) — this row re-tested the shipped file"; return
  fi
  if why=$("$fn" "$f" 2>&1); then
    _report "$label" fail "the mutated copy still passes the check — the assertion cannot see this edit"
  elif grep -qF -- "$want" <<<"$why"; then
    _report "$label" ok
  else
    _report "$label" fail "went red for the wrong reason: '$why' (want '$want')"
  fi
}

t_w8_mutants() {
  local f
  f=$(_mutate_wf w8a 'for s in steps:
    if s.get("id") == "file_unavailable": s["if"] = "always() && failure()"')
  _red_row "W8-a restoring if: always() && failure() reds W8" "$f" _w8_filer_gate_ok "contains failure()"

  f=$(_mutate_wf w8b "for s in steps:
    if s.get('id') == 'file_unavailable': s['if'] = s['if'].replace(\" || steps.probe.outputs.verdict == ''\", '')")
  _red_row "W8-b dropping the verdict == '' arm reds W8" "$f" _w8_filer_gate_ok "missing the == '' arm"

  f=$(_mutate_wf w8c 'for s in steps:
    if s.get("id") == "file_unavailable": s["if"] = s["if"].replace("!cancelled() && ", "")')
  _red_row "W8-c dropping !cancelled() reds W8" "$f" _w8_filer_gate_ok "missing !cancelled()"

  f=$(_mutate_wf w8d 'for s in steps:
    if s.get("id") == "file_unavailable": del s["id"]')
  _red_row "W8-d removing id: file_unavailable trips the exactly-one selector floor" "$f" _w8_filer_gate_ok "selector floor"

  f=$(_mutate_wf w8e "for s in steps:
    if s.get('id') == 'close_unavailable':
        s['if'] = s['if'].replace(\" && steps.file_drift.outputs.filed == 'true'\", '')")
  _red_row "W8-e dropping the closer's filed == 'true' conjunct reds W8c" "$f" _w8_closer_gate_ok "lacks the filed == 'true' conjunct"

  f=$(_mutate_wf w8f "for s in steps:
    if s.get('id') == 'file_unavailable':
        s['if'] = s['if'].replace(\"(steps.probe.outputs.verdict == 'drift' && steps.file_drift.outputs.filed != 'true')\", \"steps.file_drift.outputs.filed != 'true'\")")
  _red_row "W8-f unpairing the drift-not-filed arm (bare filed != 'true' — files on every CLEAN run) reds W8" "$f" _w8_filer_gate_ok "missing the paired drift-not-filed arm"

  f=$(_mutate_wf w8g "for s in steps:
    if s.get('id') == 'close_unavailable':
        s['if'] = s['if'] + ' || true'")
  _red_row "W8-g appending || true to the closer reds W8c" "$f" _w8_closer_gate_ok "expression is not exactly"

  f=$(_mutate_wf w8h "for s in steps:
    if s.get('id') == 'close_unavailable':
        s['if'] = s['if'].replace('always() && ', '')")
  _red_row "W8-h dropping always() from the closer (implicit success() skips it on drift) reds W8c" "$f" _w8_closer_gate_ok "missing always()"

  f=$(_mutate_wf w5a "for s in steps:
    if s.get('id') == 'close_drift':
        s['if'] = 'always()'")
  local why
  if why=$(_close_gated_ok "$f"); then
    _report "W5-a a drift closer reduced to always() reds W5 (per-step, not a concatenated blob)" fail "W5 still passes"
  else
    _report "W5-a a drift closer reduced to always() reds W5 (per-step, not a concatenated blob)" ok
  fi
}

t_w9_mutant() {
  local f
  f=$(_mutate_wf w9a "for s in steps:
    if (s.get('name') or '').startswith('Close the drift issue'):
        s['run'] = s['run'].replace('\"\$DRIFT_TITLE\"', '\"[ci/sentry-alert-drift] a migrated Sentry alert has drifted\"')")
  _red_row "W9-a an inline differing title in the close step reds W9" "$f" _w9_title_parity_ok "does not reference"
}

t_clean
t_drift
t_unavailable
t_close_gated_on_clean_only
t_probe_marker_matches_what_the_step_greps
t_w8_filer_gated_on_verdict_pair
t_w8_closer_disjoint_from_filer
t_w9_title_is_one_string
t_w9b_unavailable_title_is_one_string
t_unavailable_on_other_exit_codes
t_w8_mutants
t_w9_mutant

echo "=== $pass passed, $fail failed ==="
ran=$((pass + fail))
if [[ "$ran" -ne "$EXPECTED_TESTS" ]]; then
  echo "[FAIL] harness: ran $ran test(s), expected $EXPECTED_TESTS" >&2
  exit 1
fi
[[ "$fail" -eq 0 ]]
