#!/usr/bin/env bash
# Manifest consistency for verification-scaffold (#10404):
#   1. every guards.tsv v1 row's templates exist under references/, and every
#      references/guards/*.template is named by some v1 row (no orphans either way);
#   2. every audit corpus member (.claude/hooks/**/*.sh non-test + scripts/lint-*
#      minus .test.sh/.baseline.txt/.highwater) appears in guardrail-audit.md —
#      the census is git-ls-files driven, so a NEW unclassified member reds CI;
#   3. one-hunk parity (AC11): precommit-guard.sh.template renders byte-identical
#      to plugins/soleur/scripts/precommit-guard.sh under the default
#      main|master substitution and the VERIFICATION_->SOLEUR_ rename; the
#      wrapper-boundary pair is the same rename-normalized cmp;
#   4. emitted-content hygiene (AC8): zero SOLEUR_/knowledge-base//plugins/soleur
#      refs and zero curl|wget|https?:// tokens outside comments in templates;
#   5. portability floor: no GNU-only tokens (sed -i, readlink -f, stat -c,
#      date -d, bc, /usr/bin/time, unguarded `timeout`) in emitted templates;
#   6. the emitted verification-gates.yml renders actionlint-clean (when
#      actionlint is on PATH).
# Runs in the scripts shard. Accumulate-then-exit.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../../.." && pwd)"
SKILL="$REPO_ROOT/plugins/soleur/skills/verification-scaffold"
TSV="$SKILL/references/guards.tsv"
AUDIT="$SKILL/references/guardrail-audit.md"

passes=0; fails=0
pass() { printf 'ok   - %s\n' "$1"; passes=$((passes + 1)); }
fail() { printf 'FAIL - %s\n' "$1"; fails=$((fails + 1)); }

# --- 1. guards.tsv v1 rows <-> templates -----------------------------------------
missing=0
while IFS=$'\t' read -r name verdict surfaces templates dmode deps src emits tier; do
  case "$name" in \#*|name) continue ;; esac
  [[ "$tier" == "v1" ]] || continue
  [[ -n "$name" && -n "$templates" && -n "$emits" ]] || { fail "guards.tsv row malformed: $name"; missing=1; continue; }
  IFS=';' read -ra tp <<<"$templates"
  for t in "${tp[@]}"; do
    [[ -f "$SKILL/$t" ]] || { fail "guards.tsv $name names missing template: $t"; missing=1; }
  done
done < "$TSV"
[[ "$missing" -eq 0 ]] && pass "every v1 row's templates exist"

orphaned=0
while IFS= read -r t; do
  rel="${t#"$SKILL/"}"
  # A template is owned by a guards.tsv row (guard artifacts) or by the
  # generator itself (the doc block: verification-readme.template).
  grep -qF "$rel" "$TSV" || grep -qF "$rel" "$SKILL/scripts/verification-scaffold.sh" \
    || { fail "orphaned template (named by nothing): $rel"; orphaned=1; }
done < <(find "$SKILL/references" -name '*.template' | sort)
[[ "$orphaned" -eq 0 ]] && pass "every template is named by a guards.tsv row or the generator"

# --- 2. audit census over the live tree -------------------------------------------
# The producer is git ls-files — identical to this file's own corpus definition,
# so a new member lacking an audit row is caught here, not by review.
uncov=0
while IFS= read -r f; do
  base="$(basename "$f")"
  grep -qF "$base" "$AUDIT" || { fail "audit has no row for $f"; uncov=1; }
done < <(git -C "$REPO_ROOT" ls-files '.claude/hooks/*.sh' | grep -v '\.test\.sh$' | grep -v '/test/')
while IFS= read -r f; do
  base="$(basename "$f")"
  grep -qF "$base" "$AUDIT" || { fail "audit has no row for $f"; uncov=1; }
done < <(git -C "$REPO_ROOT" ls-files 'scripts/lint-*' | grep -v '\.test\.sh$\|\.baseline\.txt$\|\.highwater')
[[ "$uncov" -eq 0 ]] && pass "audit covers every corpus member (git ls-files census)"

# --- 3. one-hunk parity (AC11) ------------------------------------------------------
SRC_GUARD="$REPO_ROOT/plugins/soleur/scripts/precommit-guard.sh"
SRC_WRAP="$REPO_ROOT/plugins/soleur/scripts/lib/wrapper-boundary.sh"
rendered="$(mktemp)"; trap 'rm -f "$rendered"' EXIT
sed -e 's/VERIFICATION_/SOLEUR_/g' -e 's/@DEFAULT_BRANCHES@/main|master/g' \
    "$SKILL/references/guards/precommit-guard.sh.template" > "$rendered"
cmp -s "$rendered" "$SRC_GUARD" \
  && pass "precommit-guard template renders byte-identical to source under main|master" \
  || fail "precommit-guard template/source drifted (run: diff <(sed -e s/VERIFICATION_/SOLEUR_/g -e s/@DEFAULT_BRANCHES@/main\\\\|master/g .../precommit-guard.sh.template) plugins/soleur/scripts/precommit-guard.sh)"
sed 's/VERIFICATION_/SOLEUR_/g' "$SKILL/references/guards/wrapper-boundary.sh.template" > "$rendered"
cmp -s "$rendered" "$SRC_WRAP" \
  && pass "wrapper-boundary template is rename-normalized byte-identical to source" \
  || fail "wrapper-boundary template/source drifted"

# --- 4. emitted-content hygiene (AC8) ----------------------------------------------
# Templates contain @PLACEHOLDER@ markers; the runtime text must carry zero
# Soleur couplings and zero network egress.
hyg=0
while IFS= read -r t; do
  if grep -nE 'SOLEUR_|knowledge-base/|plugins/soleur' "$t" >/dev/null; then
    fail "Soleur coupling in template $(basename "$t"): $(grep -nE 'SOLEUR_|knowledge-base/|plugins/soleur' "$t" | head -3 | tr '\n' ';')"
    hyg=1
  fi
  # egress tokens outside comments: strip comment lines then grep.
  if grep -vE '^[[:space:]]*#' "$t" | grep -nE 'curl|wget|https?://' >/dev/null; then
    fail "network egress token in template $(basename "$t")"
    hyg=1
  fi
done < <(find "$SKILL/references" -name '*.template' | sort)
[[ "$hyg" -eq 0 ]] && pass "zero Soleur couplings + zero egress tokens in emitted templates"

# --- 5. portability floor ----------------------------------------------------------
# GNU-only forms banned in emitted templates (stock macOS must run them).
port=0
while IFS= read -r t; do
  case "$t" in *.yml.template) continue ;; esac
  if grep -nE 'sed -i|readlink -f|realpath|stat -c|date -d|/usr/bin/time|(^|[;&| ]|^[^#]*[;&| ])bc |mapfile' "$t" | grep -vE '^[0-9]+:[[:space:]]*#' >/dev/null; then
    fail "GNU-only token in template $(basename "$t"): $(grep -nE 'sed -i|readlink -f|realpath|stat -c|date -d|/usr/bin/time|bc |mapfile' "$t" | grep -vE '^[0-9]+:[[:space:]]*#' | head -3 | tr '\n' ';')"
    port=1
  fi
  if grep -nE '(^|[^_a-zA-Z])timeout [0-9]' "$t" | grep -v 'command -v timeout\|gtimeout' >/dev/null; then
    fail "unguarded timeout invocation in $(basename "$t")"
    port=1
  fi
done < <(find "$SKILL/references" -name '*.template' | sort)
[[ "$port" -eq 0 ]] && pass "portability floor: no GNU-only forms in emitted templates"

# --- 6. actionlint on the RENDERED workflow ------------------------------------------
if command -v actionlint >/dev/null 2>&1; then
  WF="$(mktemp -d)"
  # Render like the generator does: keep both job blocks, stamp continue-on-error.
  awk '{print}' "$SKILL/references/guards/verification-gates.yml.template" \
    | sed 's/@CI_CONTINUE_ON_ERROR@/true/g' > "$WF/verification-gates.yml"
  if actionlint -oneline "$WF/verification-gates.yml" >"$WF/lint.log" 2>&1; then
    pass "rendered verification-gates.yml is actionlint-clean"
  else
    fail "actionlint reds on rendered workflow: $(cat "$WF/lint.log" | head -5 | tr '\n' ';')"
  fi
  rm -rf "$WF"
else
  pass "actionlint not on PATH — workflow lint arm skipped (CI must provide it)"
fi

# --- 7. SKILL.md + audit + tsv exist and are non-empty -------------------------------
for f in "$SKILL/SKILL.md" "$AUDIT" "$TSV" "$SKILL/references/verification-readme.template" "$SKILL/references/gitleaks.toml.template"; do
  [[ -s "$f" ]] || fail "missing/empty: ${f#"$REPO_ROOT"/}"
done
pass "required skill files exist (SKILL.md presence asserted by the file list)"

# guards.tsv: the emitted .gitleaks.toml is a default-ruleset pointer (Guard 1
# mutation-6 anchor — the template's declared ruleset shape is pinned here).
grep -q 'useDefault = true' "$SKILL/references/gitleaks.toml.template" \
  && pass "gitleaks.toml.template is the default-ruleset pointer guards.tsv declares" \
  || fail "gitleaks.toml.template lost its useDefault=true ruleset shape"

printf '\n%d pass(es), %d fail(s)\n' "$passes" "$fails"
[[ "$fails" -eq 0 ]]
