#!/usr/bin/env bash
# Suite for plugins/soleur/skills/ship/scripts/ship-pir-action-items-gate.sh — the /ship Phase 5.5
# Incident-PIR shape check (#7941 plan, Thread 1).
#
# Five arms, each pinning a different way the gate can drift from the thing it guards:
#   1. fixtures        — every pass-*/fail-* fixture yields the rc its NAME and its first-line
#                        `expect:` token both demand; fail reasons are asserted on stderr.
#   2. template parity — the sentence pir.md tells authors to "write exactly" is accepted by the
#                        gate, and the two other authoring sites carry it byte-equal. This is the
#                        arm that reds on the 2026-09-09 shape (producer moved, consumer did not).
#   3. corpus          — every shipped PIR the gate's own selector picks still passes.
#   4. branch          — the `--branch` entry point the ship skill calls, exercised against a
#                        fixture repository: every PIR is checked (not just the first), a rename is
#                        checked at its new path, a delete is not read, "no PIR" is exit 3 and
#                        "git unavailable" is exit 2 — never a pass.
#   5. wiring          — ship/SKILL.md invokes the script and branches on its exit codes.
#
# Writes only under `mktemp -d` (preflight Check 10 runs suites with the repo read-only). The
# branch arm runs LAST: `git_fixture_env` exports a discovery ceiling into this shell, and every
# earlier arm needs `git` to see the real repository.

set -euo pipefail
export LC_ALL=C

SUITE_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=./test-helpers.sh
source "$SUITE_DIR/test-helpers.sh"

REPO_ROOT="$(cd -P "$SUITE_DIR/../../.." && pwd -P)"
GATE="$REPO_ROOT/plugins/soleur/skills/ship/scripts/ship-pir-action-items-gate.sh"
FIXTURES="$SUITE_DIR/fixtures/ship-pir-action-items"
PIR_TEMPLATE="$REPO_ROOT/plugins/soleur/skills/incident/templates/pir.md"
INCIDENT_SKILL="$REPO_ROOT/plugins/soleur/skills/incident/SKILL.md"
DRY_RUN="$REPO_ROOT/plugins/soleur/skills/incident/scripts/dry-run.sh"
SHIP_SKILL="$REPO_ROOT/plugins/soleur/skills/ship/SKILL.md"
PIR_DIR="$REPO_ROOT/knowledge-base/engineering/operations/post-mortems"

TMP="$(mktemp -d -t pir-gate-suite.XXXXXXXX)"
assert_fixture_dir "$TMP"
trap 'rm -rf "$TMP"' EXIT

# Every exit 0/1 must carry a verdict line: an rc with no `[PASS]`/`[FAIL]` line is a script that
# died somewhere other than its verdict (the `set -e` shape Guard 1 row 12 names).
assert_verdict_line() {
  local out="$1" err="$2" msg="$3"
  if grep -qE '^\[PASS\] ' "$out" || grep -qE '^\[FAIL\] ' "$err"; then
    echo "  PASS: $msg (verdict line present)"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $msg (no [PASS]/[FAIL] line on either stream)"
    FAIL=$((FAIL + 1))
  fi
}

# ---------------------------------------------------------------------------------------------
echo "=== Arm 1: fixtures ==="
# ---------------------------------------------------------------------------------------------
pass_n=0
fail_n=0
for f in "$FIXTURES"/*.md; do
  name="$(basename "$f")"
  case "$name" in
    pass-*) want_rc=0 ;;
    fail-*) want_rc=1 ;;
    *)
      printf 'FATAL: fixture %s has neither a pass- nor a fail- prefix; refusing to guess.\n' "$name" >&2
      exit 2 ;;
  esac
  # Second, independent declaration: the first line carries `expect: pass` or `expect: fail/<reason>`.
  token="$(head -n1 "$f" | sed -nE 's/^<!-- expect: ([a-z/-]+) -->$/\1/p')"
  case "$want_rc:$token" in
    0:pass)   ;;
    1:fail/*) ;;
    *)
      # Do not `continue`: the name-derived rc assertion below must ALSO red, so a mis-named
      # fixture fails twice over and a suite that dropped either declaration is shown vacuous.
      echo "  FAIL: $name — expect token '$token' disagrees with the filename prefix"
      FAIL=$((FAIL + 1)) ;;
  esac

  out="$TMP/$name.out"; err="$TMP/$name.err"
  set +e; bash "$GATE" "$f" >"$out" 2>"$err"; rc=$?; set -e
  assert_eq "$want_rc" "$rc" "$name exits $want_rc"
  assert_verdict_line "$out" "$err" "$name"
  if [[ "$want_rc" -eq 0 ]]; then
    pass_n=$((pass_n + 1))
  else
    fail_n=$((fail_n + 1))
    reason="${token#fail/}"
    # Exactly one [FAIL] line, naming this file and the reason the fixture declares.
    assert_eq "1" "$(grep -cE '^\[FAIL\] ' "$err" || true)" "$name prints exactly one [FAIL] line"
    assert_eq "1" "$(grep -cF -- "[FAIL] $f: $reason" "$err" || true)" "$name [FAIL] reason is '$reason'"
  fi
done
# Hand-measured floors, not derived from the directory: a directory that lost its fixtures would
# otherwise pass with zero assertions.
if (( pass_n >= 3 )); then PASS=$((PASS + 1)); echo "  PASS: pass-* floor ($pass_n >= 3)"; else FAIL=$((FAIL + 1)); echo "  FAIL: pass-* floor ($pass_n < 3)"; fi
if (( fail_n >= 8 )); then PASS=$((PASS + 1)); echo "  PASS: fail-* floor ($fail_n >= 8)"; else FAIL=$((FAIL + 1)); echo "  FAIL: fail-* floor ($fail_n < 8)"; fi

# The two legacy emphasised forms of the sentence (the 21 shipped PIRs) must still pass. Generated
# from the plain fixture rather than committed, so the fixture directory carries the plain form
# only. Instrument checks first: the variant must differ from its source and carry exactly one
# marker-prefixed sentence line, or the assertion below tests the plain form twice.
for marker in '_' '*'; do
  variant="$TMP/pass-sentence-variant-$([[ "$marker" == "_" ]] && echo underscore || echo asterisk).md"
  sed -E "s/^(No action items — .*\.)$/${marker//\*/\\*}\1${marker//\*/\\*}/" "$FIXTURES/pass-sentence.md" > "$variant"
  if ! cmp -s "$variant" "$FIXTURES/pass-sentence.md"; then PASS=$((PASS + 1)); echo "  PASS: variant '$marker' differs from the plain source"; else FAIL=$((FAIL + 1)); echo "  FAIL: variant '$marker' is byte-identical to the plain source (sed matched nothing)"; fi
  assert_eq "1" "$(grep -cF -- "${marker}No action items — " "$variant" || true)" "variant '$marker' carries exactly one marker-prefixed sentence line"
  set +e; bash "$GATE" "$variant" >"$variant.out" 2>"$variant.err"; rc=$?; set -e
  assert_eq "0" "$rc" "legacy '$marker' form still passes"
done

# Bold is outside the frozen class and is pinned by fail-sentence-bold.md above; a missing path is
# exit 2, never a verdict.
set +e; bash "$GATE" "$TMP/does-not-exist.md" >/dev/null 2>"$TMP/missing.err"; rc=$?; set -e
assert_eq "2" "$rc" "nonexistent path exits 2"

# ---------------------------------------------------------------------------------------------
echo "=== Arm 2: template parity ==="
# ---------------------------------------------------------------------------------------------
sentence_lines="$(grep -oE 'write exactly `[^`]+`' "$PIR_TEMPLATE" | sed -E 's/^write exactly `//; s/`$//' || true)"
assert_eq "1" "$(printf '%s\n' "$sentence_lines" | grep -c . || true)" "pir.md carries exactly one 'write exactly' sentence"
SENTENCE="$(printf '%s\n' "$sentence_lines" | head -n1)"
# The plain form is the contract: without this, reverting all three sites to an emphasised form
# stays green because the gate accepts the legacy markers.
case "$SENTENCE" in
  "No action items — "*) PASS=$((PASS + 1)); echo "  PASS: template sentence is the plain form" ;;
  *) FAIL=$((FAIL + 1)); echo "  FAIL: template sentence is not the plain form: '$SENTENCE'" ;;
esac
synth="$TMP/synth-from-template.md"
printf '%s\n' '---' 'title: "Synthesized from pir.md"' '---' '' '## Action Items & Follow-ups' '' "$SENTENCE" '' '## Timeline' '' '- t0.' > "$synth"
set +e; bash "$GATE" "$synth" >"$synth.out" 2>"$synth.err"; rc=$?; set -e
assert_eq "0" "$rc" "a PIR synthesised from pir.md's sentence passes the gate"
assert_eq "1" "$(grep -cxF -- "$SENTENCE" "$DRY_RUN" || true)" "dry-run.sh carries the sentence byte-equal, as a whole line"
assert_eq "1" "$(grep -cF -- "\`$SENTENCE\`" "$INCIDENT_SKILL" || true)" "incident/SKILL.md carries the sentence byte-equal, backticked"

# ---------------------------------------------------------------------------------------------
echo "=== Arm 3: corpus ==="
# ---------------------------------------------------------------------------------------------
if [[ ! -f "$REPO_ROOT/scripts/test-all.sh" ]]; then
  # Not this repository (a self-hosted plugin snapshot): there is no corpus to examine.
  echo "  SKIP: corpus arm — not the soleur repository (scripts/test-all.sh absent)"
  SKIPPED=$((SKIPPED + 1))
elif [[ ! -d "$PIR_DIR" ]]; then
  echo "  FAIL: corpus arm — this is the soleur repository but $PIR_DIR is missing"
  FAIL=$((FAIL + 1))
else
  set +e; (cd "$REPO_ROOT" && bash "$GATE" --corpus) >"$TMP/corpus.out" 2>"$TMP/corpus.err"; rc=$?; set -e
  assert_eq "0" "$rc" "--corpus exits 0"
  summary="$(grep -E '^PIR-ACTION-ITEMS: corpus selected=[0-9]+ examined=[0-9]+ skipped=[0-9]+ failed=[0-9]+$' "$TMP/corpus.out" || true)"
  assert_eq "1" "$(printf '%s\n' "$summary" | grep -c . || true)" "--corpus prints exactly one anchored summary line"
  if [[ -n "$summary" ]]; then
    selected="$(sed -E 's/.*selected=([0-9]+).*/\1/' <<<"$summary")"
    examined="$(sed -E 's/.*examined=([0-9]+).*/\1/' <<<"$summary")"
    skipped="$(sed -E 's/.*skipped=([0-9]+).*/\1/' <<<"$summary")"
    failed="$(sed -E 's/.*failed=([0-9]+).*/\1/' <<<"$summary")"
    assert_eq "0" "$failed" "corpus failed=0 ($summary)"
    assert_eq "$selected" "$((examined + skipped))" "corpus selected == examined + skipped"
    if (( selected >= 50 )); then PASS=$((PASS + 1)); echo "  PASS: corpus selector floor ($selected >= 50)"; else FAIL=$((FAIL + 1)); echo "  FAIL: corpus selector floor ($selected < 50) — the selector matched almost nothing"; fi
  fi
fi

# ---------------------------------------------------------------------------------------------
echo "=== Arm 5: wiring ==="
# ---------------------------------------------------------------------------------------------
section="$(awk '/^### Incident-PIR Gate/{f=1} /^### /&&!/Incident-PIR/{f=0} f' "$SHIP_SKILL")"
assert_eq "1" "$(grep -cE '^bash "\$\{CLAUDE_PLUGIN_ROOT:-plugins/soleur\}/skills/ship/scripts/ship-pir-action-items-gate\.sh" --branch$' <<<"$section" || true)" \
  "ship/SKILL.md invokes the gate in command position with --branch"
assert_eq "1" "$(grep -cE '^rc=\$\?$' <<<"$section" || true)" "the invocation captures rc=\$?"
assert_eq "1" "$(grep -cE '^[[:space:]]*1\) ' <<<"$section" || true)" "case arm 1) (fix and re-run) present"
assert_eq "1" "$(grep -cE '^[[:space:]]*3\) ' <<<"$section" || true)" "case arm 3) (no PIR in diff) present"
assert_eq "1" "$(grep -cE '^[[:space:]]*\*\) echo "SOLEUR_SHIP_PIR_GATE_HALT reason=unavailable rc=\$rc"' <<<"$section" || true)" "the catch-all case arm prints SOLEUR_SHIP_PIR_GATE_HALT"
assert_eq "0" "$(grep -cF -- '-postmortem\.md$' <<<"$section" || true)" "the file selector ERE no longer appears in the Incident-PIR section"
assert_eq "0" "$(grep -cF -- 'head -n1' <<<"$section" || true)" "the first-PIR-only 'head -n1' is gone from the Incident-PIR section"
for p in 'plugins/soleur/skills/ship/scripts/ship-pir-action-items-gate.sh' \
         'plugins/soleur/test/ship-pir-action-items-gate.test.sh' \
         'plugins/soleur/test/fixtures/ship-pir-action-items/'; do
  # The conjunct-1 list is the region between "ALL THREE hold" and the "2. **Every**" conjunct.
  conjunct1="$(awk '/ALL THREE hold/{f=1} /^[[:space:]]*2\. \*\*Every\*\*/{f=0} f' <<<"$section")"
  assert_eq "1" "$(grep -cF -- "\`$p\`" <<<"$conjunct1" || true)" "meta-case conjunct 1 lists $p"
done

# ---------------------------------------------------------------------------------------------
echo "=== Arm 4: branch (runs last — exports a discovery ceiling into this shell) ==="
# ---------------------------------------------------------------------------------------------
PIR_REL='knowledge-base/engineering/operations/post-mortems'
pir_body() { # $1 = shape: ok | unbacked
  printf '%s\n' '---' 'title: "Fixture"' '---' '' '## Action Items & Follow-ups' ''
  if [[ "$1" == ok ]]; then
    printf '%s\n' '| Issue | Action | Owner |' '|---|---|---|' '| #4242 | Do the thing | ops |'
  else
    printf '%s\n' '| Issue | Action | Owner |' '|---|---|---|' '|  | Do the thing (#4242) | ops |'
  fi
  printf '%s\n' '' '## Timeline' '' '- t0.'
}

REPO_A="$TMP/repo-a"
mkdir -p "$REPO_A"
git_fixture_env "$REPO_A"
git init -q -b main "$REPO_A"
mkdir -p "$REPO_A/$PIR_REL"
pir_body ok > "$REPO_A/$PIR_REL/a-postmortem.md"
pir_body ok > "$REPO_A/$PIR_REL/c-postmortem.md"
pir_body ok > "$REPO_A/$PIR_REL/d-postmortem.md"
printf 'base\n' > "$REPO_A/README.md"
git -C "$REPO_A" add -A
git -C "$REPO_A" commit -q -m base
git -C "$REPO_A" update-ref refs/remotes/origin/main HEAD

# Branch 1: A modified (still passing), B added unbacked, C renamed with an edit, D deleted.
git -C "$REPO_A" checkout -q -b feat
printf '\nAddendum.\n' >> "$REPO_A/$PIR_REL/a-postmortem.md"
pir_body unbacked > "$REPO_A/$PIR_REL/b-postmortem.md"
git -C "$REPO_A" mv "$PIR_REL/c-postmortem.md" "$PIR_REL/c-new-postmortem.md"
printf '\nRenamed addendum.\n' >> "$REPO_A/$PIR_REL/c-new-postmortem.md"
git -C "$REPO_A" rm -q "$PIR_REL/d-postmortem.md"
git -C "$REPO_A" add -A
git -C "$REPO_A" commit -q -m feat
set +e; (cd "$REPO_A" && bash "$GATE" --branch) >"$TMP/branch1.out" 2>"$TMP/branch1.err"; rc=$?; set -e
assert_eq "1" "$rc" "--branch exits 1 when one of several PIRs fails"
assert_eq "1" "$(grep -cF "[PASS] $PIR_REL/a-postmortem.md" "$TMP/branch1.out" || true)" "modified PIR A gets a [PASS] line"
assert_eq "1" "$(grep -cF "[FAIL] $PIR_REL/b-postmortem.md: rows-without-issue" "$TMP/branch1.err" || true)" "added unbacked PIR B gets a [FAIL] line (every PIR is checked, not just the first)"
assert_eq "1" "$(grep -cF "[PASS] $PIR_REL/c-new-postmortem.md" "$TMP/branch1.out" || true)" "renamed PIR C is checked at its new path"
assert_eq "0" "$(cat "$TMP/branch1.out" "$TMP/branch1.err" | grep -cF 'd-postmortem.md' || true)" "deleted PIR D is neither read nor reported"

# Branch 2: no PIR touched → exit 3 with the no-PIR line.
git -C "$REPO_A" checkout -q main
git -C "$REPO_A" checkout -q -b feat-nopir
printf 'more\n' >> "$REPO_A/README.md"
git -C "$REPO_A" add -A
git -C "$REPO_A" commit -q -m nopir
set +e; (cd "$REPO_A" && bash "$GATE" --branch) >"$TMP/branch2.out" 2>"$TMP/branch2.err"; rc=$?; set -e
assert_eq "3" "$rc" "--branch exits 3 when the diff touches no PIR"
assert_eq "1" "$(grep -cF 'PIR-ACTION-ITEMS: no PIR in diff' "$TMP/branch2.out" "$TMP/branch2.err" | awk -F: '{s+=$NF} END{print s+0}')" "--branch prints the no-PIR line"

# Repo B: no refs/remotes/origin/main → exit 2 with the unavailable line, never "no PIR".
REPO_B="$TMP/repo-b"
mkdir -p "$REPO_B"
git_fixture_env "$REPO_B"
git init -q -b main "$REPO_B"
printf 'x\n' > "$REPO_B/README.md"
git -C "$REPO_B" add -A
git -C "$REPO_B" commit -q -m base
set +e; (cd "$REPO_B" && bash "$GATE" --branch) >"$TMP/repob.out" 2>"$TMP/repob.err"; rc=$?; set -e
assert_eq "2" "$rc" "--branch exits 2 when origin/main does not resolve"
assert_eq "1" "$(grep -cE '^PIR-ACTION-ITEMS: unavailable — git diff origin/main\.\.\.HEAD failed \(rc=[0-9]+\)$' "$TMP/repob.err" || true)" "--branch prints the unavailable line on stderr"

# Floor measured on a green run (arm 1: 12 fixtures × 2 + 9 × 2 + 2 floors + 2 variants × 3 + 1;
# arm 2: 5; arm 3: 5; arm 5: 10; arm 4: 9) — a lower bound, not equality.
print_results 60
