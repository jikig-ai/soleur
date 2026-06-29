#!/usr/bin/env bash
# Deterministic completeness test for the gated-skills registry — NO API.
# Asserts bidirectional parity between `eval-gate:block:<id>:start` markers in
# source files and `block_id` entries in gated-skills.json, so a new/renamed
# gated classifier cannot be added without wiring its projection check.
#   DEDUP    — each scanned id appears exactly once in source (sort -u can't hide a dup).
#   PARITY   — source-scanned id set == registry block_id set (block-id level).
#   CHARSET  — every registry block_id matches ^[a-z][a-z0-9-]*$ (scanner-recognizable).
#   NEGATIVE — in-memory injected id/dup is flagged (verify-the-verifier).
# Mirrors test/eval-gate.test.sh: pure bash + node one-liners (no jq), accumulate-then-exit.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$HERE/.." && pwd)"
REPO_ROOT="$(cd "$SKILL_DIR/../../../.." && pwd)"
REGISTRY="$SKILL_DIR/gated-skills.json"
fails=0

pass() { echo "ok   [$1]"; }
fail() { echo "FAIL [$1]: $2"; fails=$((fails + 1)); }

cd "$REPO_ROOT"

# Source-marker scan: ids from `eval-gate:block:<id>:start` across plugins/soleur/, minus the
# eval-harness skill dir itself (its SKILL.md / registry / tests quote the literal markers in
# prose, so including them would false-positive the parity check). `|| true` keeps a
# legitimately-empty scan from aborting under errexit — PARITY then reports it cleanly.
# Scope assumption (fail-open corner, unreachable today): every gated source_file lives under
# plugins/soleur/ and outside eval-harness/. If the registry ever gains a source_file outside
# this scan root (or inside eval-harness/), widen/adjust the pathspec or its marker is invisible.
scan_ids() {
  git grep -hoE 'eval-gate:block:[a-z][a-z0-9-]*:start' \
    -- 'plugins/soleur/' ':(exclude)plugins/soleur/skills/eval-harness/' 2>/dev/null \
    | sed -E 's/eval-gate:block:(.*):start/\1/' || true
}

# Registry block_ids (no jq dependency — node one-liner, mirrors eval-gate.test.sh).
registry_ids() {
  node -e 'JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).forEach(e=>console.log(e.block_id))' "$REGISTRY"
}

# --- DEDUP guard: each source id appears exactly once (BEFORE sort -u would hide a dup) ---
dups="$(scan_ids | sort | uniq -d)"
if [[ -z "$dups" ]]; then
  pass "DEDUP — each gated block_id appears exactly once in source"
else
  fail "DEDUP — duplicate source marker(s)" "gated block '$(echo "$dups" | tr '\n' ' ')' appears more than once in source — each block_id maps to one registry source_file"
fi

# --- PARITY (the feature): source-scanned id set == registry id set, block-id level ---
src_set="$(scan_ids | sort -u)"
reg_set="$(registry_ids | sort -u)"

# Characterize the live scan (Kieran: don't just exit-0; pin the production command's output).
# Sorted set; update when a gated classifier surface is added/removed (PARITY below is the
# robust invariant — this literal is the belt-and-suspenders scanner-output pin).
expected_set=$'go-routing\nincident-threshold\nlane-inference\nticket-triage'
if [[ "$src_set" == "$expected_set" ]]; then
  pass "live scan characterized as exactly {go-routing, ticket-triage}"
else
  fail "live scan characterization" "scanned ids: [$(echo "$src_set" | tr '\n' ' ')] (want: go-routing ticket-triage)"
fi

# `|| true` inside the substitution: diff exits 1 on differences, which would otherwise
# abort the script (set -e + pipefail) BEFORE fail() prints the clear drift message.
parity_diff="$(diff <(echo "$src_set") <(echo "$reg_set") || true)"
if [[ -z "$parity_diff" ]]; then
  pass "PARITY — source markers and registry block_ids match"
else
  fail "PARITY — registry/source drift" "$(echo "$parity_diff" | tr '\n' ' ') ('<' source-only = unregistered marker: add a registry entry + enums/tasks/promptfooconfig + node scripts/gen-skill-prompt.cjs <id>; '>' registry-only = orphan/renamed entry)"
fi

# --- CHARSET guard: every registry block_id is scanner-recognizable ---
bad_ids=""
while IFS= read -r id; do
  [[ "$id" =~ ^[a-z][a-z0-9-]*$ ]] || bad_ids+="$id "
done < <(registry_ids)
if [[ -z "$bad_ids" ]]; then
  pass "CHARSET — every registry block_id matches ^[a-z][a-z0-9-]*\$"
else
  fail "CHARSET — non-conforming block_id" "registry block_id(s) '$bad_ids' must match ^[a-z][a-z0-9-]*\$ — the scanner regex only recognizes lowercase-hyphen ids"
fi

# --- NEGATIVE sanity (in-memory; git grep is tracked-only and cannot see a tmp fixture, so a
#     file-based negative would test a different backend than production and false-pass) ---
# (a) an injected unregistered id must be flagged by the PARITY comparison — exercised through the
#     SAME captured-string idiom the live check uses, and asserting the injected id lands on the
#     source-only ('<') side, so this verifies the verifier rather than just that diff(A+x,A)≠∅.
inj_src="$(printf '%s\nzz-injected-unregistered' "$src_set" | sort -u)"
inj_diff="$(diff <(echo "$inj_src") <(echo "$reg_set") || true)"
if [[ -n "$inj_diff" && "$inj_diff" == *"< zz-injected-unregistered"* ]]; then
  pass "NEGATIVE — injected unregistered id is flagged by PARITY (source-only side)"
else
  fail "NEGATIVE parity sanity" "injected unregistered id was NOT flagged on the source-only side (got: $(echo "$inj_diff" | tr '\n' ' '))"
fi

# (b) an injected duplicate id must be flagged by the DEDUP guard.
inj_dups="$(printf '%s\ngo-routing' "$(scan_ids)" | sort | uniq -d)"
if [[ -n "$inj_dups" ]]; then
  pass "NEGATIVE — injected duplicate id is flagged by DEDUP"
else
  fail "NEGATIVE dedup sanity" "an injected duplicate id was NOT flagged by the dedup check"
fi

if [[ "$fails" -gt 0 ]]; then
  echo "registry-completeness: $fails assertion(s) failed"
  exit 1
fi
echo "registry-completeness: all assertions passed"
