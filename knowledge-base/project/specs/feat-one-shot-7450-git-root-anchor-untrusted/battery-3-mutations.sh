#!/usr/bin/env bash
# Mutation battery for the THREE assertions added to Guard 2 by the #7450 review
# remediation: Test 21 (B1 invariant), Test 22 (C10 markers), Test 23 (C12/AC5d).
#
# Discipline, per the panel's §G gotchas:
#   - sandbox copy only, never the tracked tree
#   - un-mutated GREEN control FIRST; a red baseline voids every row
#   - every mutation asserted to have LANDED against a PRISTINE BACKUP, never against HEAD
#     (the tree is legitimately dirty during a review pass)
set -uo pipefail

SRC="/home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-7450-git-root-anchor-untrusted"
SBX="$(mktemp -d)"
trap 'rm -rf "$SBX"' EXIT INT TERM HUP

echo "sandbox: $SBX"
# Every REPO_ROOT-relative read the guard performs, enumerated from the guard itself
# (`grep -o '${REPO_ROOT}/...'`) rather than guessed — a sandbox missing one of these
# produces a RED control, which is indistinguishable from a real regression.
mkdir -p "$SBX/apps/web-platform" "$SBX/knowledge-base/engineering/operations/post-mortems"
cp -r "$SRC/plugins" "$SBX/plugins"
cp -r "$SRC/apps/web-platform/test" "$SBX/apps/web-platform/test"
cp "$SRC/knowledge-base/engineering/operations/post-mortems/dashboard-error-postmortem.md" \
   "$SBX/knowledge-base/engineering/operations/post-mortems/"

GUARD="$SBX/plugins/soleur/skills/incident/test/redact-sentinel.test.sh"
INC="$SBX/plugins/soleur/skills/incident/SKILL.md"
LIN="$SBX/plugins/soleur/skills/linear-fetch/SKILL.md"

# Pristine backup — the ONLY thing a "did the mutation land?" check may compare against.
PRISTINE="$SBX/.pristine"
mkdir -p "$PRISTINE"
cp "$GUARD" "$PRISTINE/guard"; cp "$INC" "$PRISTINE/inc"; cp "$LIN" "$PRISTINE/lin"

run_guard() { bash "$GUARD" 2>&1; }
restore() { cp "$PRISTINE/guard" "$GUARD"; cp "$PRISTINE/inc" "$INC"; cp "$PRISTINE/lin" "$LIN"; }

# ---- GREEN CONTROL ---------------------------------------------------------
out="$(run_guard)"; rc=$?
if [[ $rc -ne 0 ]]; then
  echo "CONTROL: RED (rc=$rc) — battery ABORTED, every row below would be meaningless"
  printf '%s\n' "$out" | grep '^FAIL' | head
  exit 1
fi
echo "CONTROL: GREEN — $(printf '%s' "$out" | grep -c '^PASS') PASS, 0 FAIL"
echo

# $1 = id, $2 = human description, $3 = target file var, $4 = expected-to-red test label
mutate() {
  local id="$1" desc="$2" file="$3" expect="$4" backup="$5"
  shift 5
  # apply the mutation (remaining args are a command)
  "$@"
  # ---- did it LAND? compared against the PRISTINE BACKUP, never HEAD ----
  if diff -q "$backup" "$file" >/dev/null 2>&1; then
    echo "$id: NOT APPLIED — file identical to pristine backup. Row VOID (this is the failure mode that silently produces a fake all-red battery)."
    restore; return
  fi
  local o; o="$(run_guard)"; local r=$?
  if [[ $r -ne 0 ]] && printf '%s' "$o" | grep -q "^FAIL: ${expect}"; then
    echo "$id: RED as required  — ${desc}"
    printf '    %s\n' "$(printf '%s' "$o" | grep "^FAIL: ${expect}" | head -1 | cut -c1-150)"
  elif [[ $r -ne 0 ]]; then
    echo "$id: RED but WRONG TEST — ${desc}; expected ${expect}. A mutation caught by an unrelated assertion does not prove the intended one is live."
    printf '%s' "$o" | grep '^FAIL' | head -2
  else
    echo "$id: **SURVIVED** — ${desc}. ${expect} is VACUOUS on this axis."
  fi
  restore
}

# ---- M-A: Test 21 — reintroduce a git-root anchor inside an executable fence.
# This is review-finding §B1's own prescription, applied literally. It MUST redden.
mutate "M-A" "B1's prescribed case-statement added to incident's preflight fence" \
  "$INC" "Test 21" "$PRISTINE/inc" \
  perl -0pi -e 's{(SENTINEL="\$\{CLAUDE_PLUGIN_ROOT\}/skills/incident/scripts/redact-sentinel\.sh")}{case "\$(cd "\$\{CLAUDE_PLUGIN_ROOT\}" && pwd -P)/" in "\$(git rev-parse --show-toplevel 2>/dev/null)/"*) exit 2;; esac\n$1}' "$INC"

# ---- M-B: Test 21 harness mutation — break the fence extractor so it yields nothing.
# The panel's post-mortem named "harness/guard mutation" as one of the seven axes M1-M10
# never touched. The anti-vacuity control must catch this.
mutate "M-B" "fence extractor keyed to a language that never appears (returns empty)" \
  "$GUARD" "Test 21" "$PRISTINE/guard" \
  sed -i 's/```bash(\[\[:space:\]\]|\$)/```zzznotalanguage/' "$GUARD"

# ---- M-C: Test 22 — delete one telemetry marker.
mutate "M-C" "the linear-fetch redaction-ineffective marker deleted" \
  "$LIN" "Test 22" "$PRISTINE/lin" \
  sed -i '/SOLEUR_LINEAR_FETCH_HALT reason=redaction-ineffective/d' "$LIN"

# ---- M-D: Test 22 — redirect a marker to stderr (the silent-degradation shape).
mutate "M-D" "the incident plugin-root-unverified marker redirected to stderr" \
  "$INC" "Test 22" "$PRISTINE/inc" \
  sed -i 's|\(echo "SOLEUR_INCIDENT_HALT reason=plugin-root-unverified root=\[${CLAUDE_PLUGIN_ROOT}\]"\)|\1 >\&2|' "$INC"

# ---- M-E: Test 23 — delete the non-empty check. This is C12's defect VERBATIM:
# "deleting `[ -n "$PERSIST_SAFE" ]` leaves the suite green". It must no longer.
mutate "M-E" "the [ -n \"\$PERSIST_SAFE\" ] non-empty check deleted outright" \
  "$LIN" "Test 23" "$PRISTINE/lin" \
  sed -i '/\[ -n "\$PERSIST_SAFE" \]/d' "$LIN"

# ---- M-F: Test 23 — keep the check, neuter its dispatch (the A2 fail-open shape).
mutate "M-F" "non-empty check retained but its halt arm converted to a no-op" \
  "$LIN" "Test 23" "$PRISTINE/lin" \
  sed -i '/reason=redaction-empty-output/,/exit 2; }/ s/exit 2; }/true; }/' "$LIN"

echo
echo "Battery complete."
