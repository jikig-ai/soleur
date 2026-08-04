#!/usr/bin/env bash
# (#7144 task 5b) Tests registry-userdata-budget.sh — the terraform-byte-exact user_data gate for
# the zot registry host.
#
# WHAT THIS SUITE IS FOR. The registry host has ~616 B of real headroom under Hetzner's 32,768 B
# user_data cap, and `hcloud_server.registry` carries no `lifecycle.ignore_changes = [user_data]`,
# so user_data is ForceNew. It is also the SOLE pull path for both platform images since the GHCR
# read PAT was revoked 2026-07-30. Blowing the budget is therefore learned from a failed apply on
# the host whose failure is a cold-boot outage — which is exactly the situation an OPTIMISTIC
# measurement makes worse than no measurement at all.
#
# So the assertions here are mostly about the gate's HONESTY, not just its verdict:
#   * it measures with terraform's own base64gzip, never node/`gzip -9`;
#   * its stub values carry real ENTROPY as well as real length (a same-length low-entropy stub
#     gzips away and silently restores the optimism the script exists to remove);
#   * its committed-value stubs still equal zot-registry.tf's locals (a digest bump must move the
#     model with it);
#   * both failure arms (over-cap, over-sub-cap) and the fail-closed render arm are REACHABLE —
#     each is driven behaviorally against a sandbox copy, not asserted from source text.
#   * the node-space REGISTRY_BUDGET in plugins/soleur/test/cloud-init-user-data-size.test.ts and
#     this script's sub-cap trip at the same REAL size, and the offset between them is not
#     under-stated.
#
# Needs terraform (skips cleanly without it). Run:
#   bash apps/web-platform/infra/registry-userdata-budget.test.sh

set -uo pipefail

# /tmp is a machine-global 4 GiB tmpfs shared by every parallel worktree; the sandbox copies below
# want somewhere with room. Matches test-all.sh / run-registered-suites.sh, which a DIRECT
# invocation of this file (the inner loop while editing the script) does not inherit.
export TMPDIR="${TMPDIR:-/var/tmp}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
BUDGET="$SCRIPT_DIR/registry-userdata-budget.sh"
TEMPLATE="$SCRIPT_DIR/cloud-init-registry.yml"
REGISTRY_TF="$SCRIPT_DIR/zot-registry.tf"
NODE_TEST="$REPO_ROOT/plugins/soleur/test/cloud-init-user-data-size.test.ts"

PASS=0
FAIL=0
assert() {
  local desc="$1" cond="$2"
  if eval "$cond"; then PASS=$((PASS + 1)); echo "  PASS: $desc"
  else FAIL=$((FAIL + 1)); echo "  FAIL: $desc"; echo "        condition: $cond"; fi
}

echo "=== registry-userdata-budget.sh (#7144 task 5b) tests ==="

assert "registry-userdata-budget.sh exists" "[ -f '$BUDGET' ]"
assert "registry-userdata-budget.sh is executable" "[ -x '$BUDGET' ]"
assert "cloud-init-registry.yml exists" "[ -f '$TEMPLATE' ]"
assert "zot-registry.tf exists" "[ -f '$REGISTRY_TF' ]"
assert "the node-side budget test exists" "[ -f '$NODE_TEST' ]"

if ! command -v terraform >/dev/null 2>&1; then
  echo "  SKIP: terraform not on PATH — the behavioral half of this suite cannot run." >&2
  echo ""
  echo "=== registry-userdata-budget.test.sh: ${PASS} passed, ${FAIL} failed (terraform absent) ==="
  [ "$FAIL" -eq 0 ] || exit 1
  exit 0
fi

# --- Source-shape assertions: the gate must not be a second optimistic model -------------------
# Anchored on syntax a comment cannot produce (a comment line here starts with `#`), per
# cq-assert-anchor-not-bare-token: this file's own prose names `gzip -9` and `base64gzip`, and a
# bare-token grep over the SUT would match the SUT's header prose just as happily.
assert "the gate measures with terraform's base64gzip" \
  "grep -qE '^[[:space:]]*stored[[:space:]]*=[[:space:]]*base64gzip\(' '$BUDGET'"
assert "the gate renders with templatefile(), not a hand-rolled substitution" \
  "grep -qE '^[[:space:]]*rendered[[:space:]]*=[[:space:]]*templatefile\(' '$BUDGET'"
# The negative that matters: no shell/node gzip anywhere in the measurement path. Restricted to
# non-comment lines so the header's own explanation of WHY not `gzip -9` cannot false-FAIL it.
nc_budget="$(mktemp -t regbudget-nc.XXXXXXXX)"
grep -vE '^[[:space:]]*#' "$BUDGET" > "$nc_budget"
assert "no 'gzip -9' in the measurement path (that is the overstating tool git-data warns about)" \
  "! grep -qE 'gzip[[:space:]]+-9' '$nc_budget'"
assert "no node/zlib fallback in the measurement path" \
  "! grep -qE 'gzipSync|node -e|zlib' '$nc_budget'"
rm -f "$nc_budget"

# --- Stub-entropy assertions ------------------------------------------------------------------
# Two IDENTICAL heartbeat URLs would let gzip's back-reference eat the second, under-measuring by
# ~a full token. Extract both by shape and compare.
# The SUT builds these as `"${local.hb_base}<token>"`, with hb_base itself split across a join()
# so the file carries no contiguous heartbeat-URL literal (inngest.test.sh 1.6.2 forbids that
# shape outside `*.test.sh`). So reconstruct the effective value the way terraform will: glue the
# join()'s string parts, then substitute for the interpolation. Reconstructing rather than
# hardcoding 48 keeps this measuring the SUT instead of restating it.
# Scope the quoted-string scan to the join()'s BRACKET LIST first. Scanning the whole line pairs
# quotes off the empty `""` separator argument and yields `, [` / `, ` fragments instead of the
# two real parts — measured, and it silently produced a 5-char "base".
hb_list="$(grep -E '^[[:space:]]*hb_base[[:space:]]*=' "$BUDGET" | sed -E 's/.*\[([^]]*)\].*/\1/')"
hb_base="$(grep -oE '"[^"]*"' <<<"$hb_list" | tr -d '"' | tr -d '\n')"
assert "hb_base reconstructed from the join() parts" "[ -n '$hb_base' ]"
# 48 is asserted, not assumed, so a typo'd prefix cannot quietly rebalance the token-length checks
# below into passing against a wrong total.
assert "reconstructed hb_base is the 48-char Better Stack heartbeat prefix" "[ ${#hb_base} -eq 48 ]"
HB_NEEDLE='${local.hb_base}'
hb_expand() { # <raw-rhs> -> the value terraform renders
  printf '%s' "${1//"$HB_NEEDLE"/$hb_base}"
}
disk_hb="$(hb_expand "$(grep -oE '^[[:space:]]*disk_hb[[:space:]]*=[[:space:]]*"[^"]*"' "$BUDGET" | sed 's/.*"\(.*\)"/\1/')")"
liveness_hb="$(hb_expand "$(grep -oE '^[[:space:]]*liveness_hb[[:space:]]*=[[:space:]]*"[^"]*"' "$BUDGET" | sed 's/.*"\(.*\)"/\1/')")"
assert "disk heartbeat stub extracted" "[ -n '$disk_hb' ]"
assert "liveness heartbeat stub extracted" "[ -n '$liveness_hb' ]"
assert "the two heartbeat stubs are DISTINCT (identical ones compress away)" \
  "[ '$disk_hb' != '$liveness_hb' ]"
# 72 B is the measured live length (48-char prefix + 24-char credential segment). Asserting the
# exact length rather than a floor: too SHORT under-measures, too LONG over-measures, and on a
# sub-1 KB margin both are defects.
assert "disk heartbeat stub is the measured live length (72)" "[ ${#disk_hb} -eq 72 ]"
assert "liveness heartbeat stub is the measured live length (72)" "[ ${#liveness_hb} -eq 72 ]"

# --- Drift guard: committed-value stubs must equal zot-registry.tf's locals --------------------
# A zot version bump moves local.zot_image_amd64; if this model keeps the old digest it keeps
# measuring a render nobody boots. Same for the Doppler CLI checksum.
tf_zot_image="$(grep -oE '^[[:space:]]*zot_image_amd64[[:space:]]*=[[:space:]]*"[^"]*"' "$REGISTRY_TF" | sed 's/.*"\(.*\)"/\1/')"
sut_zot_image="$(grep -oE '^[[:space:]]*zot_image[[:space:]]*=[[:space:]]*"[^"]*"' "$BUDGET" | sed 's/.*"\(.*\)"/\1/')"
assert "zot-registry.tf's amd64 image ref extracted" "[ -n '$tf_zot_image' ]"
assert "the budget model's zot_image matches zot-registry.tf's amd64 local" \
  "[ '$sut_zot_image' = '$tf_zot_image' ]"

# doppler_sha256 sits behind a ternary in zot-registry.tf; take the amd64 (second) arm, which is
# the one local.registry_arch selects for the cx23 default.
tf_doppler_sha="$(grep -E '^[[:space:]]*doppler_sha256[[:space:]]*=' "$REGISTRY_TF" | grep -oE '"[0-9a-f]{64}"' | tail -1 | tr -d '"')"
sut_doppler_sha="$(grep -oE '^[[:space:]]*doppler_sha256[[:space:]]*=[[:space:]]*"[0-9a-f]{64}"' "$BUDGET" | grep -oE '[0-9a-f]{64}')"
assert "zot-registry.tf's amd64 doppler sha256 extracted" "[ -n '$tf_doppler_sha' ]"
assert "the budget model's doppler_sha256 matches zot-registry.tf's amd64 arm" \
  "[ '$sut_doppler_sha' = '$tf_doppler_sha' ]"

# --- Behavioral: the live measurement ----------------------------------------------------------
json="$("$BUDGET" --json 2>/dev/null)"
rc=$?
assert "the gate exits 0 on the current tree" "[ $rc -eq 0 ]"
assert "the gate emits JSON" "grep -q '\"stored\"' <<<'$json'"

field() { grep -oE "\"$1\":[0-9]+" <<<"$json" | grep -oE '[0-9]+'; }
stored="$(field stored)"
cap_json="$(field cap)"
subcap_json="$(field subcap)"
headroom="$(field headroom)"
subcap_headroom="$(field subcap_headroom)"

assert "stored is an integer" "[[ '$stored' =~ ^[0-9]+$ ]]"
assert "cap is an integer" "[[ '$cap_json' =~ ^[0-9]+$ ]]"
assert "subcap is an integer" "[[ '$subcap_json' =~ ^[0-9]+$ ]]"
assert "cap is Hetzner's 32768, not a self-chosen number" "[ '$cap_json' -eq 32768 ]"
assert "subcap sits strictly below cap" "[ '$subcap_json' -lt '$cap_json' ]"
assert "stored is under the sub-cap" "[ '$stored' -lt '$subcap_json' ]"
assert "headroom is consistent with stored/cap" "[ \$(( cap_json - stored )) -eq '$headroom' ]"
assert "subcap_headroom is consistent with stored/subcap" "[ \$(( subcap_json - stored )) -eq '$subcap_headroom' ]"
# Non-vacuity: a broken render that measured near-nothing would sail under every budget above.
# The registry template is ~65 KB raw; anything that gzips below 20 KB is a broken model.
assert "stored is a real measurement, not a collapsed render (>20000)" "[ '$stored' -gt 20000 ]"

echo "--- measured: stored=${stored} B, subcap=${subcap_json} B, cap=${cap_json} B ---"

# --- The cross-gate lockstep -------------------------------------------------------------------
# Extract both node-space operands BY SHAPE from the TS file (never a hardcoded copy here — that
# is the drift this guard exists to catch). `const X = N;` cannot be produced by a `//` comment.
# NB: capture the value with sed rather than piping to `grep -oE '[0-9_]+'`. The constant NAMES
# contain underscores, so a `[0-9_]+` class matches the `_` in REGISTRY_BUDGET first and `tr -d _`
# turns that hit into an empty leading line — which bash arithmetic then silently coerces, so the
# lockstep assertions below would still have PASSED against a malformed extraction. Caught by the
# `=~ ^[0-9]+$` shape assertions, which is why they are here and not merely decorative.
node_budget="$(sed -nE 's/^const REGISTRY_BUDGET = ([0-9_]+);.*/\1/p' "$NODE_TEST" | tr -d '_')"
node_offset="$(sed -nE 's/^const REGISTRY_NODE_OFFSET = ([0-9_]+);.*/\1/p' "$NODE_TEST" | tr -d '_')"
assert "REGISTRY_BUDGET extracted from the node test" "[[ '$node_budget' =~ ^[0-9]+$ ]]"
assert "REGISTRY_NODE_OFFSET extracted from the node test" "[[ '$node_offset' =~ ^[0-9]+$ ]]"
assert "the node budget + offset equals this script's sub-cap (both gates trip at one real size)" \
  "[ \$(( node_budget + node_offset )) -eq '$subcap_json' ]"
# The safety direction, and the reason the offset is pinned at all: if the node model drifts
# further from terraform than the recorded offset admits, a node-passing render could still be
# over-cap. This reds instead. One-sided on purpose — an offset that is too GENEROUS is merely
# conservative, an offset that is too small is unsound.
assert "the recorded offset is not an under-statement (terraform_stored <= budget + offset)" \
  "[ '$stored' -le \$(( node_budget + node_offset )) ]"
assert "a node-passing render is provably under the vendor cap" \
  "[ \$(( node_budget + node_offset )) -lt 32768 ]"

# --- Behavioral: every failure arm is REACHABLE -------------------------------------------------
# Driven against sandbox copies (script + template only — the script resolves the template from
# its own BASH_SOURCE dir, so a two-file copy is a faithful environment). Asserting these from
# source text would prove the branches EXIST, never that they FIRE.
SANDBOX="$(mktemp -d -t regbudget-sbx.XXXXXXXX)"
trap 'rm -rf "$SANDBOX"' EXIT
cp "$BUDGET" "$SANDBOX/budget.sh" || { echo "FATAL: sandbox setup failed (cp budget)" >&2; exit 2; }
cp "$TEMPLATE" "$SANDBOX/cloud-init-registry.yml" || { echo "FATAL: sandbox setup failed (cp template)" >&2; exit 2; }

# Control FIRST: the untouched copy must still pass in the sandbox, or every mutant verdict below
# is a statement about the sandbox rather than about the mutation.
# rc captured into a named variable rather than read as `$?` in the assert argument: `$?` there is
# correct only while nothing is inserted between the two lines, which is precisely the edit a
# future contributor makes without noticing. The named form cannot silently start asserting on
# some other command's status.
bash "$SANDBOX/budget.sh" >/dev/null 2>&1; rc_ctl=$?
assert "control: the unmutated copy passes in the sandbox" "[ $rc_ctl -eq 0 ]"

mutate() { # <name> <sed-expr>  -> writes $SANDBOX/<name>.sh
  cp "$SANDBOX/budget.sh" "$SANDBOX/$1.sh" || { echo "FATAL: sandbox setup failed (cp $1)" >&2; exit 2; }
  sed -i "$2" "$SANDBOX/$1.sh" || { echo "FATAL: sandbox setup failed (mutate $1)" >&2; exit 2; }
  # Prove the mutation LANDED — a sed that silently matched nothing yields a mutant identical to
  # the control, which then "passes" and reads as a guard that cannot fire.
  if cmp -s "$SANDBOX/budget.sh" "$SANDBOX/$1.sh"; then
    echo "FATAL: mutation '$1' did not land (sed matched nothing)" >&2; exit 2
  fi
}

# (a) OVER SUB-CAP — drop the sub-cap below the measured size; cap untouched.
mutate m_subcap 's/^subcap=[0-9]*$/subcap=100/'
out_a="$(bash "$SANDBOX/m_subcap.sh" 2>&1)"; rc_a=$?
assert "(a) an over-sub-cap render exits non-zero" "[ $rc_a -ne 0 ]"
assert "(a) and says OVER SUB-CAP, not OVER CAP" "grep -q 'OVER SUB-CAP' <<<\"\$out_a\""

# (b) OVER CAP — drop the cap below the measured size. Cap is checked first, so this must report
# the fatal arm even though the sub-cap is also exceeded.
mutate m_cap 's/^cap=[0-9]*$/cap=100/'
out_b="$(bash "$SANDBOX/m_cap.sh" 2>&1)"; rc_b=$?
assert "(b) an over-cap render exits non-zero" "[ $rc_b -ne 0 ]"
assert "(b) and reports OVER CAP (the fatal arm outranks the sub-cap arm)" \
  "grep -q 'OVER CAP' <<<\"\$out_b\""

# (c) FAIL-CLOSED on an unrenderable template. An unmeasurable template must never read as one
# that fits — the arm git-data's script documents and this one inherits.
cp "$SANDBOX/budget.sh" "$SANDBOX/m_render.sh"
printf '\n${this_var_is_not_in_the_map}\n' >> "$SANDBOX/cloud-init-registry.yml"
out_c="$(bash "$SANDBOX/m_render.sh" 2>&1)"; rc_c=$?
assert "(c) an unrenderable template exits 2 (fail-closed, distinct from over-cap's 1)" "[ $rc_c -eq 2 ]"
assert "(c) and says RENDER FAILED" "grep -q 'RENDER FAILED' <<<\"\$out_c\""
# Restore so any later case sees a good template.
cp "$TEMPLATE" "$SANDBOX/cloud-init-registry.yml"

# (d) terraform absent -> SKIP 0, never a false RED in an environment that cannot measure.
#
# A bare `PATH=` does NOT test this: the script resolves its own directory with `dirname`, an
# external binary, so an empty PATH kills it at line 1 with 127 and the run reads as "the
# terraform guard failed" when the terraform guard never executed. Filtering terraform's own
# directory out of PATH is no better — on a runner where terraform lives in /usr/bin that strips
# coreutils too, and the same 127 comes back wearing a different hat.
#
# So: build a bin dir holding symlinks to exactly the externals the script uses, minus terraform.
# Coreutils present, terraform genuinely absent, independent of where either happens to live.
mkdir -p "$SANDBOX/bin" || { echo "FATAL: sandbox setup failed (mkdir bin)" >&2; exit 2; }
# `bash` is in the list because the invocation below sets PATH for the command itself — without
# it the interpreter is what goes missing and the case fails 127 for the same reason a bare
# `PATH=` did, one layer out.
for b in bash env dirname mktemp cat sed grep wc cp rm tr; do
  src="$(command -v "$b")" || { echo "FATAL: sandbox setup failed — '$b' not on PATH" >&2; exit 2; }
  ln -sf "$src" "$SANDBOX/bin/$b" || { echo "FATAL: sandbox setup failed (ln $b)" >&2; exit 2; }
done
# Precondition self-check: if a refactor ever drops the terraform probe, this case must fail as a
# clear FIXTURE error rather than as a phantom SUT regression.
if PATH="$SANDBOX/bin" command -v terraform >/dev/null 2>&1; then
  echo "FATAL: sandbox bin still resolves terraform — case (d) would be vacuous" >&2; exit 2
fi
out_d="$(PATH="$SANDBOX/bin" bash "$SANDBOX/budget.sh" 2>&1)"; rc_d=$?
assert "(d) a terraform-less environment SKIPs with exit 0" "[ $rc_d -eq 0 ]"
assert "(d) and says SKIP" "grep -q 'SKIP' <<<\"\$out_d\""

# Anti-vacuity floor (the inngest-inventory.test.sh / registry-boot-guard.test.sh shape): without
# it, unhooking a whole block exits 0 at a smaller, entirely green count.
MIN_ASSERTIONS=45
if [ "$((PASS + FAIL))" -lt "$MIN_ASSERTIONS" ]; then
  echo "FATAL: only $((PASS + FAIL)) assertions ran, expected >= $MIN_ASSERTIONS — suite silently truncated." >&2
  exit 1
fi

echo ""
echo "=== registry-userdata-budget.test.sh: ${PASS} passed, ${FAIL} failed ==="
[ "$FAIL" -eq 0 ] || exit 1
