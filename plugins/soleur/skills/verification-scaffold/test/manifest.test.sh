#!/usr/bin/env bash
# Manifest/audit/template census for verification-scaffold (#10404).
#   - every guards.tsv v1 row's templates exist; every template is named by a v1 row
#   - every corpus member (.claude/hooks/*.sh non-test + scripts/lint-* non-aux)
#     carries an audit row — census is git-ls-files driven, not a pinned list
#   - precommit-guard.sh.template == rename-normalized source under the
#     @DEFAULT_BRANCHES@ substitution; wrapper-boundary pair is a raw cmp
#   - emitted-content hygiene: no SOLEUR_/knowledge-base//plugins-soleur runtime
#     refs; no curl|wget|https?:// outside comments; no GNU-only portability tokens
#   - emitted workflow is actionlint-clean
set -uo pipefail

REPO_ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
SKILL="$REPO_ROOT/plugins/soleur/skills/verification-scaffold"
TSV="$SKILL/references/guards.tsv"
AUDIT="$SKILL/references/guardrail-audit.md"

passes=0; fails=0
pass() { printf 'ok   - %s\n' "$1"; passes=$((passes + 1)); }
fail() { printf 'FAIL - %s\n' "$1"; fails=$((fails + 1)); }

# --- v1 rows have existing templates; every guards/*.template is named ------
tpl_missing=0; tpl_orphan=0
while IFS=$'\t' read -r name verdict surfaces templates dm deps sf emits tier; do
  [[ "$name" =~ ^#|^name$ || -z "$name" ]] && continue
  [[ "$tier" == "v1" ]] || continue
  for t in ${templates//;/ }; do
    [[ "$t" == "-" ]] && continue
    [[ -f "$SKILL/$t" ]] || { fail "v1 row $name names missing template $t"; tpl_missing=1; }
  done
done < "$TSV"
[[ "$tpl_missing" == "0" ]] && pass "every v1 row's templates exist"

for t in "$SKILL"/references/guards/*.template; do
  rel="references/guards/$(basename "$t")"
  grep -qF "$rel" "$TSV" || { fail "template $rel not named by any guards.tsv row"; tpl_orphan=1; }
done
[[ "$tpl_orphan" == "0" ]] && pass "every guards/*.template is named in guards.tsv"

# --- audit census: every corpus member appears ------------------------------
missing=0
while IFS= read -r f; do
  grep -qF "$(basename "$f")" "$AUDIT" || { fail "audit lacks row for $f"; missing=1; }
done < <( { git -C "$REPO_ROOT" ls-files '.claude/hooks/*.sh' | grep -v '\.test\.sh$';
            git -C "$REPO_ROOT" ls-files 'scripts/lint-*' | grep -vE '\.(test\.sh|baseline\.txt|highwater)$'; } )
[[ "$missing" == "0" ]] && pass "audit covers every corpus member (git-ls-files census)"

# --- parity: precommit-guard template vs rename-normalized source -----------
norm="$(mktemp)"; rend="$(mktemp)"
sed -e 's/SOLEUR_/VERIFICATION_/g' \
    -e 's|if \[\[ "\$BRANCH" == "main" \|\| "\$BRANCH" == "master" \]\]|if [[ "$BRANCH" =~ ^(@DEFAULT_BRANCHES@)$ ]]|' \
    "$REPO_ROOT/plugins/soleur/scripts/precommit-guard.sh" > "$norm"
sed 's/@DEFAULT_BRANCHES@/main|master/' \
    "$SKILL/references/guards/precommit-guard.sh.template" > "$rend"
if diff -q "$norm" "$rend" >/dev/null 2>&1 || cmp -s "$norm" "$rend" 2>/dev/null; then
  # accept either byte-parity or the one-line shape difference
  :
fi
if ! cmp -s "$norm" "$rend"; then
  # Second acceptable form: template keeps the source line shape literally —
  # then the placeholder lives on a config line instead. Fail only if the
  # bodies diverge beyond the branch-check hunk.
  if diff "$norm" "$rend" | grep -vcE '^[0-9]|^---|DEFAULT_BRANCH|BRANCH.*main' | grep -q .; then
    fail "precommit-guard template drifts from rename-normalized source"
  else
    pass "precommit-guard template parity (one-hunk @DEFAULT_BRANCHES@)"
  fi
else
  pass "precommit-guard template byte-parity under substitution"
fi
sed 's/SOLEUR_/VERIFICATION_/g' "$REPO_ROOT/plugins/soleur/scripts/lib/wrapper-boundary.sh" > "$norm"
if cmp -s "$norm" "$SKILL/references/guards/wrapper-boundary.sh.template"; then
  pass "wrapper-boundary template raw parity (rename-normalized)"
else
  fail "wrapper-boundary template diverges from rename-normalized source"
fi
rm -f "$norm" "$rend"

# --- emitted-content hygiene ------------------------------------------------
bad=0
for t in "$SKILL"/references/guards/*.template "$SKILL"/references/gitleaks.toml.template "$SKILL"/references/verification-readme.template; do
  grep -nE 'SOLEUR_|knowledge-base/|plugins/soleur' "$t" | grep -v '^\s*[0-9]*:#' | grep -qE . \
    && { fail "$(basename "$t") carries a Soleur coupling in runtime text"; bad=1; }
  grep -nE 'curl|wget|https?://' "$t" | grep -vE '^\s*[0-9]+:\s*#' | grep -vE ':\s*#.*(curl|wget|http)' \
    | grep -vE 'uses: ' | grep -qE 'curl|wget|https?://' \
    && { fail "$(basename "$t") has network egress outside comments"; bad=1; }
  grep -nE 'sed -i |readlink -f|stat -c |date -d|/usr/bin/time|\bbc \b' "$t" | grep -qE . \
    && { fail "$(basename "$t") carries a GNU-only token"; bad=1; }
done
[[ "$bad" == "0" ]] && pass "emitted-content hygiene: no couplings, egress, or GNU-only tokens"

# --- emitted workflow is actionlint-clean -----------------------------------
if command -v actionlint >/dev/null 2>&1; then
  tmpd="$(mktemp -d)"; mkdir -p "$tmpd/.github/workflows"
  sed -e 's/@MODE@/advisory/g' -e 's/@CI_CONTINUE_ON_ERROR@/true/g' \
      -e 's/@DEFAULT_BRANCHES@/main|master/g' -e '/# @\(job\|\/job\)/d' \
      "$SKILL/references/guards/verification-gates.yml.template" \
      > "$tmpd/.github/workflows/verification-gates.yml"
  ( cd "$tmpd" && actionlint .github/workflows/verification-gates.yml >/dev/null 2>&1 ) \
    && pass "emitted workflow is actionlint-clean" || fail "actionlint flagged the emitted workflow"
  rm -rf "$tmpd"
else
  pass "actionlint absent — skipped (not fatal)"
fi

printf 'manifest.test.sh: %d passed, %d failed\n' "$passes" "$fails"
[[ "$fails" -eq 0 ]]
