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

# Positive control for the dispatch helpers: an assert_eq that MUST fail has to move FAIL, and
# assert_verdict_line on empty streams has to fail too. An always-pass helper keeps the floor
# intact (it counts), so the floor alone cannot see it — this can.
( assert_eq a b "control" >/dev/null; [[ $FAIL -eq 1 ]] ) || { printf 'FATAL: assert_eq cannot fail — dispatch is neutered\n' >&2; exit 2; }
( : > "$TMP/c.out"; : > "$TMP/c.err"; assert_verdict_line "$TMP/c.out" "$TMP/c.err" "control" >/dev/null; [[ $FAIL -eq 1 ]] ) \
  || { printf 'FATAL: assert_verdict_line cannot fail — dispatch is neutered\n' >&2; exit 2; }

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
  # Second, independent declaration: the first line after the frontmatter block carries
  # `expect: pass` or `expect: fail/<reason>` (after the fence, so every fixture is still a
  # well-formed frontmatter document if the frontmatter check is ever scripted into the gate).
  token="$(awk 'NR==1 && $0!="---"{exit} NR>1 && $0=="---"{getline; print; exit}' "$f" | sed -nE 's/^<!-- expect: (pass|fail\/[a-z][a-z-]*) -->$/\1/p')"
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
    assert_eq "1" "$(grep -cF -- "[FAIL] $f: $reason — " "$err" || true)" "$name [FAIL] reason is '$reason'"
  fi
done
# Hand-measured floors, not derived from the directory: a directory that lost its fixtures would
# otherwise pass with zero assertions.
assert_eq "1" "$(( pass_n >= 6 ))" "pass-* floor ($pass_n >= 6: plain, two legacy marker forms, sub-heading, table, fence-inside-section)"
assert_eq "1" "$(( fail_n >= 17 ))" "fail-* floor ($fail_n >= 17)"
# The two legacy emphasised forms (the 21 shipped PIRs) are committed fixtures
# (pass-sentence-legacy-{underscore,asterisk}.md) — the fixture directory is lint-ignored, so MD049
# cannot restyle them, and they ride the loop above. Pin that they are really the marker forms:
assert_eq "1" "$(grep -cF -- '_No action items — ' "$FIXTURES/pass-sentence-legacy-underscore.md" || true)" "legacy underscore fixture carries the _ marker form"
assert_eq "1" "$(grep -cF -- '*No action items — ' "$FIXTURES/pass-sentence-legacy-asterisk.md" || true)" "legacy asterisk fixture carries the * marker form"

# Bold is outside the frozen class and is pinned by fail-sentence-bold.md above; a missing path is
# exit 2, never a verdict.
set +e; bash "$GATE" "$TMP/does-not-exist.md" >/dev/null 2>"$TMP/missing.err"; rc=$?; set -e
assert_eq "2" "$rc" "nonexistent path exits 2"
ln -s "$FIXTURES/pass-sentence.md" "$TMP/link-postmortem.md"
set +e; bash "$GATE" "$TMP/link-postmortem.md" >/dev/null 2>"$TMP/link.err"; rc=$?; set -e
assert_eq "1" "$rc" "a symlink to a passing PIR is refused (not-a-regular-file)"
assert_eq "1" "$(grep -cF -- ": not-a-regular-file — " "$TMP/link.err" || true)" "symlink refusal names its reason"
set +e; bash "$GATE" >/dev/null 2>&1; rc=$?; set -e
assert_eq "2" "$rc" "no argument is a usage error (exit 2)"
set +e; bash "$GATE" --bogus >/dev/null 2>&1; rc=$?; set -e
assert_eq "2" "$rc" "an unknown flag is a usage error (exit 2)"

# ---------------------------------------------------------------------------------------------
echo "=== Arm 2: template parity ==="
# ---------------------------------------------------------------------------------------------
sentence_lines="$(grep -oE 'write exactly `[^`]+`' "$PIR_TEMPLATE" | sed -E 's/^write exactly `//; s/`$//' || true)"
assert_eq "1" "$(printf '%s\n' "$sentence_lines" | grep -c . || true)" "pir.md carries exactly one 'write exactly' sentence"
SENTENCE="$(printf '%s\n' "$sentence_lines" | head -n1)"
# The plain form is the contract: without this, reverting all three sites to an emphasised form
# stays green because the gate accepts the legacy markers.
case "$SENTENCE" in "No action items — "*) plain=1 ;; *) plain=0 ;; esac
assert_eq "1" "$plain" "template sentence is the plain form (got: '$SENTENCE')"
synth="$TMP/synth-from-template.md"
printf '%s\n' '---' 'title: "Synthesized from pir.md"' '---' '' '## Action Items & Follow-ups' '' "$SENTENCE" '' '## Timeline' '' '- t0.' > "$synth"
set +e; bash "$GATE" "$synth" >"$synth.out" 2>"$synth.err"; rc=$?; set -e
assert_eq "0" "$rc" "a PIR synthesised from pir.md's sentence passes the gate"
assert_eq "1" "$(grep -cxF -- "$SENTENCE" "$DRY_RUN" || true)" "dry-run.sh carries the sentence byte-equal, as a whole line"
assert_eq "1" "$(grep -cF -- "\`$SENTENCE\`" "$INCIDENT_SKILL" || true)" "incident/SKILL.md carries the sentence byte-equal, backticked"
assert_eq "1" "$(grep -cF -- "\`$SENTENCE\`" "$SHIP_SKILL" || true)" "ship/SKILL.md's Exit-0 arm quotes the sentence byte-equal, backticked"

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
    assert_eq "1" "$(( examined >= 50 ))" "corpus examined floor ($examined >= 50; a swapped or collapsed field reads far lower)"
  fi
fi

# ---------------------------------------------------------------------------------------------
echo "=== Arm 5: wiring ==="
# ---------------------------------------------------------------------------------------------
section="$(awk '/^### Incident-PIR Gate/{f=1} /^### /&&!/Incident-PIR/{f=0} f' "$SHIP_SKILL")"
assert_eq "1" "$(grep -cE '^bash "\$\{CLAUDE_PLUGIN_ROOT\}/skills/ship/scripts/ship-pir-action-items-gate\.sh" --branch$' <<<"$section" || true)" \
  "ship/SKILL.md invokes the gate in command position with --branch (bare anchor, ADR-179)"
assert_eq "1" "$(awk 'prev ~ /ship-pir-action-items-gate\.sh" --branch$/ && $0 == "rc=$?" {n++} {prev=$0} END{print n+0}' <<<"$section")" "the line after the --branch invocation is rc=\$?"
# The signal scan (upstream of the shape check) branches on ITS rc the same way; the earlier
# `if`/`else` read exit 127 as "no signal" (#7941 review). Both blocks capture rc; each has a HALT.
assert_eq "2" "$(grep -cE '^[[:space:]]*rc=\$\?$' <<<"$section" || true)" "both gate blocks capture rc=\$? (signal scan + shape check)"
assert_eq "1" "$(grep -cE '^[[:space:]]*\*\) echo "SOLEUR_SHIP_PIR_GATE_HALT reason=signal-scan-unavailable rc=\$rc"' <<<"$section" || true)" "the signal scan's catch-all arm halts (not 'no signal')"
assert_eq "1" "$(grep -cE '^[[:space:]]*1\) echo "gate: no incident signal\."' <<<"$section" || true)" "the signal scan's exit-1 arm is the only 'no signal' line"
assert_eq "1" "$(grep -cE '^[[:space:]]*1\) echo "gate: \[FAIL\]' <<<"$section" || true)" "case arm 1) (fix and re-run) present"
assert_eq "1" "$(grep -cE '^[[:space:]]*3\) echo "gate: no PIR in the diff' <<<"$section" || true)" "case arm 3) (no PIR in diff) present"
assert_eq "1" "$(grep -cE '^[[:space:]]*\*\) echo "SOLEUR_SHIP_PIR_GATE_HALT reason=unavailable rc=\$rc"' <<<"$section" || true)" "the catch-all case arm prints SOLEUR_SHIP_PIR_GATE_HALT"
assert_eq "0" "$(grep -cF -- '-postmortem\.md$' <<<"$section" || true)" "the file selector ERE no longer appears in the Incident-PIR section"
assert_eq "0" "$(grep -cF -- 'head -n1' <<<"$section" || true)" "the first-PIR-only 'head -n1' is gone from the Incident-PIR section"
# The conjunct-1 list is the region between "ALL THREE hold" and the "2. **Every**" conjunct.
conjunct1="$(awk '/ALL THREE hold/{f=1} /^[[:space:]]*2\. \*\*Every\*\*/{f=0} f' <<<"$section")"
for p in 'plugins/soleur/skills/ship/scripts/ship-pir-action-items-gate.sh' \
         'plugins/soleur/test/ship-pir-action-items-gate.test.sh' \
         'plugins/soleur/test/fixtures/ship-pir-action-items/'; do
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
# Advance origin/main past the branch point with a PIR edit: two-dot would list main's PIR as
# the branch's and turn "no PIR" into a verdict; three-dot keeps it exit 3.
git -C "$REPO_A" checkout -q main
printf '\nMain-side addendum.\n' >> "$REPO_A/$PIR_REL/a-postmortem.md"
git -C "$REPO_A" commit -q -am main-moved
git -C "$REPO_A" update-ref refs/remotes/origin/main HEAD
git -C "$REPO_A" checkout -q feat-nopir
set +e; (cd "$REPO_A" && bash "$GATE" --branch) >"$TMP/branch2.out" 2>"$TMP/branch2.err"; rc=$?; set -e
assert_eq "3" "$rc" "--branch exits 3 when the diff touches no PIR (origin/main ahead: three-dot, not two-dot)"
assert_eq "1" "$(grep -cF 'PIR-ACTION-ITEMS: no PIR in diff' "$TMP/branch2.out" "$TMP/branch2.err" | awk -F: '{s+=$NF} END{print s+0}')" "--branch prints the no-PIR line"

# Branch 3: every touched PIR passes → exit 0 with a [PASS] line (the Match arm's input).
git -C "$REPO_A" checkout -q -b feat-allpass origin/main
printf '\nAnother addendum.\n' >> "$REPO_A/$PIR_REL/c-postmortem.md"
git -C "$REPO_A" commit -q -am allpass
set +e; (cd "$REPO_A" && bash "$GATE" --branch) >"$TMP/branch3.out" 2>"$TMP/branch3.err"; rc=$?; set -e
assert_eq "0" "$rc" "--branch exits 0 when every touched PIR passes"
assert_eq "1" "$(grep -cF "[PASS] $PIR_REL/c-postmortem.md" "$TMP/branch3.out" || true)" "the passing PIR gets its [PASS] line"

# Corpus negative controls in the fixture repo (the real corpus is green, so arm 3 alone can
# never see a --corpus that stops counting failures). On feat (A ok, B unbacked, C-new ok):
git -C "$REPO_A" checkout -q feat
set +e; (cd "$REPO_A" && bash "$GATE" --corpus) >"$TMP/corpus-neg.out" 2>"$TMP/corpus-neg.err"; rc=$?; set -e
assert_eq "1" "$rc" "--corpus exits 1 when a tracked PIR fails"
assert_eq "1" "$(grep -cE '^PIR-ACTION-ITEMS: corpus selected=3 examined=3 skipped=0 failed=1$' "$TMP/corpus-neg.out" || true)" "--corpus counts the one failing PIR"
assert_eq "1" "$(grep -cF "[FAIL] $PIR_REL/b-postmortem.md: rows-without-issue — " "$TMP/corpus-neg.err" || true)" "--corpus names the failing PIR"
if [[ $EUID -eq 0 ]]; then
  echo "  SKIP: unreadable-file corpus control (root reads everything)"; SKIPPED=$((SKIPPED + 1))
else
  chmod 000 "$REPO_A/$PIR_REL/a-postmortem.md"
  set +e; (cd "$REPO_A" && bash "$GATE" --corpus) >"$TMP/corpus-unr.out" 2>"$TMP/corpus-unr.err"; rc=$?; set -e
  chmod 644 "$REPO_A/$PIR_REL/a-postmortem.md"
  assert_eq "2" "$rc" "--corpus exits 2 (not 1, not SKIP) on an unreadable tracked PIR"
  assert_eq "1" "$(grep -cE '^PIR-ACTION-ITEMS: corpus selected=3 examined=3 skipped=0 failed=1$' "$TMP/corpus-unr.out" || true)" "the unreadable PIR is examined, not skipped, and not counted as failed"
fi

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

# A red run must show WHICH file failed and why: the captured streams live under $TMP, which the
# EXIT trap removes. Print them first.
if (( FAIL > 0 )); then
  for e in "$TMP"/*.err; do
    [[ -s "$e" ]] || continue
    printf -- '--- %s\n' "$(basename "$e")"; sed 's/^/    /' "$e"
  done
fi
# Floor set at the measured green count — ratchet it in lockstep with every added assertion
# (arm 1: 23 fixtures × 2 + 17 × 2 + 2 floors + 2 legacy pins + 5; arm 2: 6; arm 3: 5;
# arm 5: 13; arm 4: 18; measured 129).
print_results 129
