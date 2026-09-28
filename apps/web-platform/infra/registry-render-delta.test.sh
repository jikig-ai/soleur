#!/usr/bin/env bash
# (#7582) Executes the `gate` run: body of .github/workflows/registry-host-replace-dispatch.yml
# under the runner's own shell (`bash --noprofile --norc -eo pipefail`) with a stubbed `gh`, and
# pins what each arm DECIDES about delivering a registry-host replace.
#
# THE DEFECT THIS EXISTS TO CATCH. The gate compared the comment-stripped cloud-init-registry.yml
# at the delivery watermark and at github.sha. The host's user_data is a templatefile() render
# whose inputs also live in zot-registry.tf (zot_image, doppler_sha256, ...) and variables.tf
# (registry_server_type -> the zot cgroup cap and arch). So a zot digest bump changed the bytes the
# host boots while the gate said `deliver=false`. Row G1 is that exact case.
#
# WHY IT LIVES HERE. The render arm runs terraform (registry-userdata-budget.sh renders offline
# via `terraform console`). Suites under apps/web-platform/infra/ are glob-registered into
# `deploy-script-tests`, whose legs carry setup-terraform (#8736); the `test` job has no terraform.
#
# Every fixture is synthesized from the real render inputs by a named, single-purpose mutation
# (cq-test-fixtures-synthesized-only). The `gh` stub REFUSES (exit 64) any request it did not
# expect — a contents read for the wrong ref or an unfixtured path — so a gate that asks for the
# wrong thing cannot read the right fixture.
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/../../.." && pwd)"
WF="$ROOT/.github/workflows/registry-host-replace-dispatch.yml"
INFRA_REL="apps/web-platform/infra"
CFG_REL="$INFRA_REL/cloud-init-registry.yml"
TF_REL="$INFRA_REL/zot-registry.tf"
VARS_REL="$INFRA_REL/variables.tf"

PASS=0; FAIL=0; HARN=0; FAILURES=()
pass() { echo "  pass: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); FAILURES+=("$1"); }

command -v terraform >/dev/null 2>&1 || {
  if [ -n "${CI:-}" ]; then
    echo "registry-render-delta.test: terraform is REQUIRED in CI and is not on PATH" >&2
    exit 2
  fi
  echo "registry-render-delta.test: SKIP — terraform not on PATH (local dev; fails closed in CI)" >&2
  exit 0
}

TMP="$(mktemp -d)" || exit 2
trap 'rm -rf "$TMP"' EXIT

python3 - "$WF" "$TMP/gate.sh" <<'PY' || { echo "  FATAL: could not extract the gate body"; exit 2; }
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
steps = {s.get("id"): s for s in d["jobs"]["dispatch-replace"]["steps"]}
open(sys.argv[2], "w").write(steps["gate"]["run"])
PY
[[ -s "$TMP/gate.sh" ]] || { echo "  FATAL: empty gate body"; exit 2; }

W=cccccccccccccccccccccccccccccccccccccccc   # the delivery watermark (BEFORE)
A=dddddddddddddddddddddddddddddddddddddddd   # github.sha (AFTER)

mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_LOG"
case " $* " in
  *" run list "*) printf '%s\n' "$STUB_WATERMARK"; exit 0 ;;
  *"/compare/"*)
    case " $* " in *"/compare/${STUB_WATERMARK}...${STUB_AFTER} "*) ;; *) echo "stub: compare for an unexpected range: $*" >&2; exit 64 ;; esac
    printf '%s' "$STUB_COMPARE"; exit 0 ;;
  *"/contents/"*)
    url=""; for a in "$@"; do case "$a" in *"/contents/"*) url="$a" ;; esac; done
    p="${url#*/contents/}"; ref="${p##*\?ref=}"; p="${p%%\?ref=*}"
    [[ "$ref" == "$STUB_WATERMARK" ]] || { echo "stub: contents read for unexpected ref '$ref'" >&2; exit 64; }
    f="$STUB_BEFORE/$p"
    [[ -f "$f" ]] || { echo "stub: no BEFORE fixture for $p" >&2; exit 64; }
    # The real API wraps base64 at 60 columns; the gate pipes `.content` through `base64 -d`.
    base64 -w 60 "$f"; exit 0 ;;
esac
echo "stub: unrouted gh call: $*" >&2
exit 64
STUB
chmod +x "$TMP/bin/gh"

SB="$TMP/sb"; BF="$TMP/before"
reset_trees() {
  rm -rf "$SB" "$BF"
  mkdir -p "$SB/$INFRA_REL" "$BF/$INFRA_REL" || exit 2
  for f in cloud-init-registry.yml zot-registry.tf variables.tf registry-userdata-budget.sh; do
    cp "$ROOT/$INFRA_REL/$f" "$SB/$INFRA_REL/$f" || exit 2
    cp "$ROOT/$INFRA_REL/$f" "$BF/$INFRA_REL/$f" || exit 2
  done
}
# mutate <file> <python-expr over s> — asserts the edit LANDED (a no-op mutation would report the
# baseline, which is indistinguishable from a pass).
mutate() {
  python3 - "$1" "$2" <<'PY' || { echo "  FATAL: mutation did not land on $1"; exit 2; }
import re, sys
p, expr = sys.argv[1], sys.argv[2]
s = open(p).read()
n = eval(expr, {"re": re, "s": s})
assert n != s, "mutation changed nothing"
open(p, "w").write(n)
PY
}
compare_of() {  # filenames... -> compare JSON
  printf '%s\n' "$@" | jq -R . | jq -sc '{status:"ahead", total_commits:1, files: map({filename: .})}'
}
# The Actions default shell for a `run:` with no `shell:` key.
run_gate() {  # extra env assignments... ; uses $COMPARE
  : > "$TMP/out"; : > "$TMP/gh.log"
  ( cd "$SB" && env PATH="$TMP/bin:${GATE_PATH:-$PATH}" GH_LOG="$TMP/gh.log" \
      STUB_WATERMARK="$W" STUB_AFTER="$A" STUB_COMPARE="$COMPARE" STUB_BEFORE="$BF" \
      GITHUB_OUTPUT="$TMP/out" GITHUB_REPOSITORY=jikig-ai/soleur GH_TOKEN=x \
      EVENT_NAME=push AFTER_SHA="$A" CFG="$CFG_REL" SELF=registry-host-replace-dispatch.yml "$@" \
      bash --noprofile --norc -eo pipefail "$TMP/gate.sh" > "$TMP/log" 2>&1 ); RC=$?
  if grep -q '^stub: ' "$TMP/log"; then
    HARN=$((HARN+1)); fail "harness: the gate made a request the stub did not expect: $(grep -m1 '^stub: ' "$TMP/log")"
  fi
}
out() { sed -n "s/^$1=//p" "$TMP/out" | tail -1; }
# A PATH with every directory holding a `terraform` removed (the G8 / G3 arms).
NO_TF_PATH=""
IFS=: read -ra _pp <<<"$PATH"
for d in "${_pp[@]}"; do [[ -x "$d/terraform" ]] || NO_TF_PATH="${NO_TF_PATH:+$NO_TF_PATH:}$d"; done

ZOT_AMD64_DIGEST="$(grep -oE '^[[:space:]]*zot_image_amd64[[:space:]]*=[[:space:]]*"[^"]*@sha256:[0-9a-f]{64}"' "$ROOT/$TF_REL" | grep -oE '[0-9a-f]{64}' | head -1)"
[[ "$ZOT_AMD64_DIGEST" =~ ^[0-9a-f]{64}$ ]] || { echo "  FATAL: could not read the amd64 zot digest from $TF_REL"; exit 2; }
DOPPLER_AMD64="$(grep -oE '^[[:space:]]*doppler_sha256[[:space:]]*=.*' "$ROOT/$TF_REL" | grep -oE '"[0-9a-f]{64}"' | tail -1 | tr -d '"')"
[[ "$DOPPLER_AMD64" =~ ^[0-9a-f]{64}$ ]] || { echo "  FATAL: could not read the amd64 doppler_sha256 from $TF_REL"; exit 2; }
OTHER_HEX=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef

echo "gate: render-input rows"

# G1 — THE #7582 CASE: only zot_image_amd64's digest differs at the watermark; the template is
# byte-identical; the compare lists only zot-registry.tf.
reset_trees
mutate "$BF/$TF_REL" "s.replace('$ZOT_AMD64_DIGEST', '$OTHER_HEX')"
COMPARE="$(compare_of "$TF_REL")"; run_gate
[[ "$RC" -eq 0 && "$(out deliver)" == "true" ]] && pass "G1: a zot digest bump alone (template unchanged) delivers" || fail "G1: rc=$RC deliver=$(out deliver) — $(tail -2 "$TMP/log" | tr '\n' ' ')"
[[ "$(out render_changed)" == "true" ]] && pass "G1: render_changed=true is emitted for the consumers" || fail "G1: render_changed=$(out render_changed)"

# G1b — a second render input changed after a compliant first (a comment-only template edit)
# must not mask the digest bump.
reset_trees
mutate "$BF/$TF_REL" "s.replace('$ZOT_AMD64_DIGEST', '$OTHER_HEX')"
mutate "$BF/$CFG_REL" "s.replace('#cloud-config\n', '#cloud-config\n# rationale-only line (G1b)\n', 1)"
COMPARE="$(compare_of "$CFG_REL" "$TF_REL")"; run_gate
[[ "$RC" -eq 0 && "$(out deliver)" == "true" ]] && pass "G1b: digest bump + comment-only template edit still delivers" || fail "G1b: rc=$RC deliver=$(out deliver)"

# G2 — a comment-only template edit renders byte-identical: no delivery.
reset_trees
mutate "$BF/$CFG_REL" "s.replace('#cloud-config\n', '#cloud-config\n# rationale-only line (G2)\n', 1)"
COMPARE="$(compare_of "$CFG_REL")"; run_gate
[[ "$RC" -eq 0 && "$(out deliver)" == "false" ]] && pass "G2: comment-only template edit -> deliver=false" || fail "G2: rc=$RC deliver=$(out deliver) — $(tail -2 "$TMP/log" | tr '\n' ' ')"

# G3 — an unrelated variables.tf edit decides on the server-type compare alone and never renders:
# run with terraform off PATH under CI=1, where any render attempt would fail closed (rc 2).
reset_trees
mutate "$BF/$VARS_REL" "s.replace('soleur-web-platform:latest\"', 'soleur-web-platform:older\"', 1)"
COMPARE="$(compare_of "$VARS_REL")"; GATE_PATH="$NO_TF_PATH" run_gate CI=1
[[ "$RC" -eq 0 && "$(out deliver)" == "false" ]] && pass "G3: unrelated variables.tf edit -> deliver=false with no render (no terraform needed)" || fail "G3: rc=$RC deliver=$(out deliver) — $(tail -2 "$TMP/log" | tr '\n' ' ')"

# G4 — registry_server_type's value differs (the render stubs the cap and arch it derives).
reset_trees
mutate "$BF/$VARS_REL" "re.sub(r'(variable \"registry_server_type\" \\{.*?\n  default = )\"cpx22\"', r'\\1\"cx23\"', s, count=1, flags=re.S)"
COMPARE="$(compare_of "$VARS_REL")"; run_gate
[[ "$RC" -eq 0 && "$(out deliver)" == "true" ]] && pass "G4: registry_server_type change delivers" || fail "G4: rc=$RC deliver=$(out deliver)"

# G4b — registry_server_type unreadable on one side: fail toward delivering.
reset_trees
mutate "$BF/$VARS_REL" "re.sub(r'(variable \"registry_server_type\" \\{.*?\n)  default = \"cpx22\"\n', r'\\1', s, count=1, flags=re.S)"
COMPARE="$(compare_of "$VARS_REL")"; run_gate
[[ "$RC" -eq 0 && "$(out deliver)" == "true" ]] && pass "G4b: unparseable registry_server_type -> deliver=true" || fail "G4b: rc=$RC deliver=$(out deliver)"

# G4c — the SAME arm64 (cax*) type on both sides and a template edit that renders identical on
# the amd64 branch: the offline render only renders amd64, so it cannot vouch for an arm64 host's
# bytes and the gate delivers. (With no render input changed the type alone cannot change bytes —
# that is G3's arm.)
reset_trees
for t in "$SB" "$BF"; do mutate "$t/$VARS_REL" "s.replace('  default = \"cpx22\"', '  default = \"cax21\"', 1)"; done
mutate "$BF/$CFG_REL" "s.replace('#cloud-config\n', '#cloud-config\n# rationale-only line (G4c)\n', 1)"
COMPARE="$(compare_of "$CFG_REL")"; run_gate
[[ "$RC" -eq 0 && "$(out deliver)" == "true" ]] && pass "G4c: an arm64 (cax*) server type delivers (render cannot see it)" || fail "G4c: rc=$RC deliver=$(out deliver)"

# G5 — the watermark's pin has a shape the current budget script cannot parse: BEFORE is
# unmeasurable, which cannot prove "unchanged" -> deliver, with a warning.
reset_trees
mutate "$BF/$TF_REL" "re.sub(r'(zot_image_amd64 = \")[^\"]*(\")', r'\\1not-a-pinned-ref\\2', s, count=1)"
COMPARE="$(compare_of "$TF_REL")"; run_gate
[[ "$RC" -eq 0 && "$(out deliver)" == "true" ]] && grep -q '::warning::' "$TMP/log" && pass "G5: unmeasurable watermark render -> deliver=true + ::warning::" || fail "G5: rc=$RC deliver=$(out deliver)"

# G5b — a doppler_sha256 (amd64 branch) bump alone is a host-visible change.
reset_trees
mutate "$BF/$TF_REL" "s.replace('$DOPPLER_AMD64', '$OTHER_HEX')"
COMPARE="$(compare_of "$TF_REL")"; run_gate
[[ "$RC" -eq 0 && "$(out deliver)" == "true" ]] && pass "G5b: doppler_sha256 bump alone delivers (read from the .tf, not a stub copy)" || fail "G5b: rc=$RC deliver=$(out deliver)"

# G6 — the AFTER render is unmeasurable (pin removed): refuse; never replace blind.
reset_trees
mutate "$SB/$TF_REL" "re.sub(r'(zot_image_amd64 = \")[^\"]*(\")', r'\\1not-a-pinned-ref\\2', s, count=1)"
COMPARE="$(compare_of "$TF_REL")"; run_gate
[[ "$RC" -ne 0 && "$(out deliver)" != "true" ]] && grep -q '::error::' "$TMP/log" && pass "G6: unmeasurable AFTER render -> gate refuses (non-zero, ::error::)" || fail "G6: rc=$RC deliver=$(out deliver)"

# G6b — the AFTER render exceeds Hetzner's 32,768 B stored cap: refuse (hcloud would reject the
# CREATE after the DESTROY). Incompressible padding in a non-comment line.
reset_trees
head -c 36000 /dev/urandom | base64 -w 76 | sed 's/^/  x-pad: /' >> "$SB/$CFG_REL" || exit 2
COMPARE="$(compare_of "$CFG_REL")"; run_gate
[[ "$RC" -ne 0 && "$(out deliver)" != "true" ]] && pass "G6b: over-cap AFTER render -> gate refuses" || fail "G6b: rc=$RC deliver=$(out deliver)"

# G7 — no render input in the compare (a workflow-file registration push): no delivery, no render.
reset_trees
COMPARE="$(compare_of ".github/workflows/registry-host-replace-dispatch.yml")"; GATE_PATH="$NO_TF_PATH" run_gate CI=1
[[ "$RC" -eq 0 && "$(out deliver)" == "false" ]] && pass "G7: registration-only push -> deliver=false, no render" || fail "G7: rc=$RC deliver=$(out deliver)"

# G8 — terraform absent and CI unset on a render arm: the budget script SKIPs with exit 0 and
# writes nothing. Empty-vs-empty must never read as "identical".
reset_trees
mutate "$BF/$TF_REL" "s.replace('$ZOT_AMD64_DIGEST', '$OTHER_HEX')"
COMPARE="$(compare_of "$TF_REL")"; GATE_PATH="$NO_TF_PATH" run_gate CI=
[[ "$(out deliver)" != "false" && "$RC" -ne 0 ]] && pass "G8: an unmeasured render (no terraform) is a refusal, never deliver=false" || fail "G8: rc=$RC deliver=$(out deliver)"

echo "workflow wiring"
wf_tfv="$(python3 -c 'import sys,yaml; print((yaml.safe_load(open(sys.argv[1])).get("env") or {}).get("TERRAFORM_VERSION",""))' "$WF")"
ap_tfv="$(python3 -c 'import sys,yaml; print((yaml.safe_load(open(sys.argv[1])).get("env") or {}).get("TERRAFORM_VERSION",""))' "$ROOT/.github/workflows/apply-web-platform-infra.yml")"
[[ -n "$wf_tfv" && "$wf_tfv" == "$ap_tfv" ]] && pass "P1: TERRAFORM_VERSION ($wf_tfv) matches apply-web-platform-infra.yml" || fail "P1: dispatcher '$wf_tfv' vs apply '$ap_tfv'"
python3 - "$WF" <<'PY' && pass "P2: push.paths lists every render input" || fail "P2: push.paths is missing a render input"
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
on = d.get("on", d.get(True))
paths = set(on["push"]["paths"])
need = {"apps/web-platform/infra/cloud-init-registry.yml", "apps/web-platform/infra/zot-registry.tf", "apps/web-platform/infra/variables.tf"}
sys.exit(0 if need <= paths else 1)
PY
python3 - "$WF" <<'PY' && pass "P3: setup-terraform (wrapper off) runs before the gate step" || fail "P3: setup-terraform missing, wrapped, or after the gate"
import sys, yaml
steps = yaml.safe_load(open(sys.argv[1]))["jobs"]["dispatch-replace"]["steps"]
ids = [s.get("id") for s in steps]
tf = [i for i, s in enumerate(steps) if str(s.get("uses", "")).startswith("hashicorp/setup-terraform@")]
ok = bool(tf) and tf[0] < ids.index("gate") and str((steps[tf[0]].get("with") or {}).get("terraform_wrapper")).lower() == "false"
sys.exit(0 if ok else 1)
PY

# --- anti-vacuity: helper self-test + a floor that reads the append-only ledger ---------------
_cp=$PASS; _cf=$FAIL; _cl=${#FAILURES[@]}
pass "canary: pass() counts"; fail "canary: fail() counts (EXPECTED)"
if [[ "$PASS" -ne $((_cp+1)) || "$FAIL" -ne $((_cf+1)) || "${#FAILURES[@]}" -ne $((_cl+1)) ]]; then
  printf '  FATAL: the assertion helpers are not counting — every verdict above is void.\n' >&2; exit 2
fi
FAIL=$((FAIL-1)); unset 'FAILURES[-1]'
# EQUALITY, not a floor: adding a row must move this literal.
if [[ "$((PASS + FAIL - HARN))" -ne 18 ]]; then
  printf '  FATAL: anti-vacuity: %s assertions ran; exactly 18 are expected (fix the dispatch, do not edit the literal to match).\n' "$((PASS + FAIL - HARN))" >&2
  exit 1
fi
echo "=== Results: $PASS/$((PASS+FAIL)) passed, $FAIL failed ==="
[[ "${#FAILURES[@]}" -eq 0 ]]
