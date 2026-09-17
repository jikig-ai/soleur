#!/usr/bin/env bash
# Mutation battery for the plugin slash-name uniqueness guard.
#
# Restores from a PRISTINE COPY, never `git checkout` — the fix under test is
# uncommitted, so a checkout restore would revert it and every later row would
# score the defect against itself.
#
# Each row: apply -> assert the mutation LANDED (a mutation that does not land
# reports the BASELINE, which is indistinguishable from a pass) -> run -> record
# -> revert -> assert the revert restored byte-for-byte.
set -uo pipefail

export TMPDIR="${TMPDIR:-/var/tmp}"
export PATH="$HOME/.local/share/mise/installs/bun/1.3.14/bin:$PATH"

cd "$(git rev-parse --show-toplevel)" || exit 2

SUITES=(plugins/soleur/test/components.test.ts plugins/soleur/test/slash-name-uniqueness.test.ts)
TOUCHED=(
  plugins/soleur/skills/go/SKILL.md
  plugins/soleur/test/components.test.ts
  plugins/soleur/test/helpers.ts
  plugins/soleur/.claude-plugin/plugin.json
)
CREATED=(
  plugins/soleur/commands/flag-bootstrap.md
  plugins/soleur/commands/qa.md
  plugins/soleur/commands/review.md
  plugins/soleur/devin/skills/review/SKILL.md
)

PRISTINE=$(mktemp -d -t mutbat.XXXXXXXX) || exit 2
for f in "${TOUCHED[@]}"; do
  mkdir -p "$PRISTINE/$(dirname "$f")" || exit 2
  cp "$f" "$PRISTINE/$f" || exit 2
done

restore() {
  for f in "${TOUCHED[@]}"; do cp "$PRISTINE/$f" "$f" || exit 2; done
  for f in "${CREATED[@]}"; do rm -f "$f"; done
  rmdir plugins/soleur/devin/skills/review 2>/dev/null
  for f in "${TOUCHED[@]}"; do
    if ! diff -q "$PRISTINE/$f" "$f" >/dev/null; then
      printf 'FATAL: restore failed for %s\n' "$f"; exit 2
    fi
  done
}
trap restore EXIT

run_suites() {
  local log; log=$(mktemp -t mutrow.XXXXXXXX.log)
  bun test "${SUITES[@]}" > "$log" 2>&1
  local rc=$?
  printf '%s %s' "$rc" "$log"
}

cmd_fixture() {  # $1 = stem
  cat > "plugins/soleur/commands/$1.md" <<EOF
---
name: $1
description: Synthetic mutation fixture for the slash-name uniqueness battery
argument-hint: ""
---

# $1

Synthetic body for mutation testing. Not a real command.
EOF
}

row() {  # $1 = id, $2 = expectation (RED|GREEN), $3 = note
  local id="$1" want="$2" note="$3"
  read -r rc log <<<"$(run_suites)"
  local got; [[ "$rc" == "0" ]] && got=GREEN || got=RED
  local verdict; [[ "$got" == "$want" ]] && verdict="as-expected" || verdict="*** MISMATCH ***"
  printf '\n=== %s  want=%s got=%s  %s\n' "$id" "$want" "$got" "$verdict"
  printf '    %s\n' "$note"
  if [[ "$got" == "RED" ]]; then
    printf '    reddening test(s):\n'
    grep -E '^\(fail\)' "$log" | sed 's/^/      /' | head -5
    printf '    message excerpt:\n'
    grep -oE 'These names render TWICE[^`]*|resolves these skill names from more than one root: [a-z, ]*|Claude Code.s .skills. key is ADDITIVE[^"]*|still declares the live slash[a-z -]*' "$log" \
      | head -2 | cut -c1-200 | sed 's/^/      /'
  fi
}

printf '###### CONTROL (unmutated) — a RED baseline voids every row below\n'
row "M0-control" GREEN "unmutated tree"

# ---------------------------------------------------------------- M1
python3 - <<'PY'
import io
p="plugins/soleur/skills/go/SKILL.md"; s=io.open(p,encoding="utf-8").read()
assert "user-invocable: false\n" in s
io.open(p,"w",encoding="utf-8").write(s.replace("user-invocable: false\n","",1))
PY
grep -qE '^user-invocable: false$' plugins/soleur/skills/go/SKILL.md && { echo "M1 did NOT land"; exit 2; }
row "M1 remove user-invocable from skills/go" RED "the exact state of the tree before this PR"
restore

# ---------------------------------------------------------------- M2
cmd_fixture flag-bootstrap
[[ -f plugins/soleur/commands/flag-bootstrap.md ]] || { echo "M2 did NOT land"; exit 2; }
row "M2 commands/flag-bootstrap.md (must-PASS)" GREEN "skills/flag-bootstrap/ has no SKILL.md so it is not a skill"
restore

# ---------------------------------------------------------------- M3
cmd_fixture qa
[[ -f plugins/soleur/commands/qa.md ]] || { echo "M3 did NOT land"; exit 2; }
row "M3 commands/qa.md" RED "collides from the COMMANDS side against existing skills/qa/"
restore

# ---------------------------------------------------------------- M4
cmd_fixture qa; cmd_fixture review
[[ -f plugins/soleur/commands/qa.md && -f plugins/soleur/commands/review.md ]] || { echo "M4 did NOT land"; exit 2; }
row "M4 commands/qa.md + commands/review.md" RED "must name BOTH, not stop at the first"
restore

# ---------------------------------------------------------------- M5
python3 - <<'PY'
import json,io
p="plugins/soleur/.claude-plugin/plugin.json"; d=json.load(io.open(p,encoding="utf-8"))
assert "skills" not in d
d["skills"]=["./devin/skills"]
io.open(p,"w",encoding="utf-8").write(json.dumps(d,indent=2)+"\n")
PY
grep -q '"skills"' plugins/soleur/.claude-plugin/plugin.json || { echo "M5 did NOT land"; exit 2; }
row "M5 .claude-plugin declares a skills key" RED "clause (c): additive key re-creates the duplicate"
restore

# ---------------------------------------------------------------- M6
mkdir -p plugins/soleur/devin/skills/review
cat > plugins/soleur/devin/skills/review/SKILL.md <<'EOF'
---
name: review
description: Synthetic mutation fixture duplicating skills/review across two roots.
---

Synthetic body for mutation testing.
EOF
[[ -f plugins/soleur/devin/skills/review/SKILL.md ]] || { echo "M6 did NOT land"; exit 2; }
row "M6 devin/skills/review duplicates skills/review" RED "clause (a): the skills-vs-skills class; 'review' is NOT acked"
restore

# ---------------------------------------------------------------- M7
python3 - <<'PY'
import io
p="plugins/soleur/test/helpers.ts"; s=io.open(p,encoding="utf-8").read()
old='new Glob("commands/*.md")'
assert old in s
io.open(p,"w",encoding="utf-8").write(s.replace(old,'new Glob("commands/*.NOPE")',1))
PY
grep -q 'commands/\*.NOPE' plugins/soleur/test/helpers.ts || { echo "M7 did NOT land"; exit 2; }
row "M7 discovery returns nothing" RED "the bounded floor must refuse a clean sweep over an empty corpus"
restore

# ---------------------------------------------------------------- M8
python3 - <<'PY'
import io
p="plugins/soleur/test/components.test.ts"; s=io.open(p,encoding="utf-8").read()
a=s.index('describe("plugin slash-name uniqueness"')
io.open(p,"w",encoding="utf-8").write(s[:a]+'describe("plugin slash-name uniqueness DELETED", () => {});\n')
PY
grep -q 'describe("plugin slash-name uniqueness"' plugins/soleur/test/components.test.ts && { echo "M8 did NOT land"; exit 2; }
row "M8 delete the guard describe block" RED "must red in the OTHER file (slash-name-uniqueness.test.ts)"
restore

printf '\n###### battery complete; pristine restore verified\n'
