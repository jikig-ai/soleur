#!/usr/bin/env bash
# Synthesized fixtures only. The product script writes nothing.
# shellcheck disable=SC2329
export TMPDIR="${TMPDIR:-/var/tmp}"
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
SUT="$REPO_ROOT/plugins/soleur/scripts/spec-kit-intake.sh"
BRAIN="$REPO_ROOT/plugins/soleur/skills/brainstorm/SKILL.md"
PLAN_SKILL="$REPO_ROOT/plugins/soleur/skills/plan/SKILL.md"
PLAN_REF="$REPO_ROOT/plugins/soleur/skills/plan/references/spec-kit-intake.md"
SPEC="$REPO_ROOT/knowledge-base/project/specs/feat-12531-spec-kit-ingestion/spec.md"

passes=0
fails=0
FAILED=()
pass() { passes=$((passes + 1)); echo "  PASS: $1"; }
fail() { fails=$((fails + 1)); FAILED+=("$1"); echo "  FAIL: $1" >&2; }
_iv_p="$passes"
_iv_f="$fails"
_iv_n="${#FAILED[@]}"
{ pass "self-test"; fail "self-test"; } >/dev/null 2>&1
if [[ "$passes" -ne $((_iv_p + 1)) || "$fails" -ne $((_iv_f + 1)) || "${#FAILED[@]}" -ne $((_iv_n + 1)) ]]; then
  printf '[FATAL] instrument self-test\n' >&2
  exit 1
fi
passes=0
fails=0
FAILED=()

assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY; git -C "" would operate on %s\n' "$PWD" >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}

WORK=""
cleanup() {
  if [[ -n "${WORK}" ]]; then
    assert_fixture_dir "$WORK"
    chmod -R u+rwx "$WORK" 2>/dev/null || true
    rm -rf "$WORK"
  fi
}
trap cleanup EXIT
WORK="$(mktemp -d)"
assert_fixture_dir "$WORK"

run_cmd() {
  local err="$WORK/err" outf="$WORK/out"
  : >"$err"
  rc=0
  if command -v timeout >/dev/null 2>&1; then
    timeout 5 "$@" >"$outf" 2>"$err" || rc=$?
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout 5 "$@" >"$outf" 2>"$err" || rc=$?
  else
    "$@" >"$outf" 2>"$err" || rc=$?
  fi
  out="$(cat "$outf")"
}

want_reason() {
  local label="$1" reason="$2"
  shift 2
  run_cmd "$@"
  if [[ "$rc" -eq 0 ]]; then fail "$label exit 0"; return; fi
  if [[ "$out" != "intake: ${reason}" ]]; then fail "$label stdout=$(printf %q "$out")"; return; fi
  if [[ -s "$WORK/err" ]]; then fail "$label stderr"; return; fi
  pass "$label"
}

want_ok() {
  local label="$1"
  shift
  run_cmd "$@"
  if [[ "$rc" -ne 0 ]]; then fail "$label rc=$rc out=$(printf %q "$out")"; return; fi
  if [[ -s "$WORK/err" ]]; then fail "$label stderr"; return; fi
  pass "$label"
}

projected() {
  printf '%s\n' "$out" | awk 'f{print} /^--- projected ---$/{f=1}'
}

side_only() {
  printf '%s\n' "$out" | awk '/^--- side-evidence ---$/{s=1; next} /^--- projected ---$/{s=0} s{print}'
}

kit_of() {
  local name="$1"
  local d="$WORK/tree/$name"
  assert_fixture_dir "$WORK"
  mkdir -p "$d/specs/001-demo"
  printf '%s' "$d/specs/001-demo"
}

write_spec() {
  local dir="$1"
  local body="$2"
  printf '%s\n' "$body" >"$dir/spec.md"
}

# --- probe and argument shape ---

want_ok "probe" "$SUT" --probe
if [[ "$out" != "spec-kit-intake: ok" ]]; then fail "probe stdout"; else pass "probe stdout"; fi
want_ok "probe ignores missing dir" "$SUT" --probe --dir "$WORK/no-such-dir"
if [[ "$out" != "spec-kit-intake: ok" ]]; then fail "probe still ok"; else pass "probe still ok"; fi
want_reason "neither dir nor probe" "not-a-directory" "$SUT"
want_reason "missing path" "not-a-directory" "$SUT" --cwd "$WORK" --dir "$WORK/missing"
want_reason "file path" "not-a-directory" "$SUT" --cwd "$WORK" --dir "$WORK/err"
want_reason "bad short prefix" "not-a-directory" "$SUT" --cwd "$WORK" --dir "$WORK/does-not-exist/specs/12-demo"
mkdir -p "$WORK/shape/specs/12-demo" "$WORK/shape/specs/001-.dot"
printf 'x\n' >"$WORK/shape/specs/12-demo/spec.md"
printf 'x\n' >"$WORK/shape/specs/001-.dot/spec.md"
want_reason "two-digit prefix" "not-a-directory" "$SUT" --cwd "$WORK/shape" --dir "specs/12-demo"
want_reason "dot short-name" "not-a-directory" "$SUT" --cwd "$WORK/shape" --dir "specs/001-.dot"

# --- happy path ---

D="$(kit_of happy)"
write_spec "$D" "$(cat <<'EOF'
---
title: hidden
SENTINEL-FM
---
```
## User Story fenced P1
FENCED-ONLY
```
User Story setext P1
====================
SETEXT-BODY
## Success Criteria
alpha keeps the lights on
## success criteria
second goal line
## Out of Scope
no billing
## Non-Goals
no sync
## Exclusions
no import
## User Story one P1
the first story
## User Story two P2
later story
## User Story three P3
much later
## User Story plain
no priority
## User Story mixed P2P P1
substring is not a priority
## User Story both P1 P2
two priorities
## User Story soft P1
this needs clarification in other words
## Notes
this body contains NEEDS CLARIFICATION
## User Story blocked P1
blocked NEEDS CLARIFICATION
EOF
)"
printf 'SENTINEL-PLAN-ONLY\n--- projected ---\nMARKER-BODY\n' >"$D/plan.md"
printf 'T001 kit task\n' >"$D/tasks.md"
printf 'SENTINEL-RESEARCH\n' >"$D/research.md"
mkdir -p "$D/contracts"
printf 'SENTINEL-CONTRACT\n' >"$D/contracts/api.md"
printf 'SENTINEL-LINK\n' >"$D/linked.md"
want_ok "happy" "$SUT" --cwd "$WORK/tree/happy" --dir "specs/001-demo"
proj="$(projected)"
side="$(side_only)"
if [[ "$out" == *"$D"* ]]; then fail "absolute path leaked"; else pass "no absolute path"; fi
if [[ "$out" == *SENTINEL-FM* ]]; then fail "frontmatter leaked"; else pass "frontmatter hidden"; fi
if [[ "$proj" == *FENCED-ONLY* || "$proj" == *SETEXT-BODY* ]]; then fail "fenced or setext became a heading"; else pass "fenced and setext ignored"; fi
if [[ "$proj" == *"alpha keeps the lights on"* && "$proj" == *"second goal line"* ]]; then pass "goals mapped"; else fail "goals mapped"; fi
if [[ "$proj" == *"no billing"* && "$proj" == *"no sync"* && "$proj" == *"no import"* ]]; then pass "non-goals mapped"; else fail "non-goals mapped"; fi
if [[ "$proj" == *"the first story"* && "$proj" == *"substring is not a priority"* && "$proj" == *"needs clarification in other words"* ]]; then pass "p1 stories are fr"; else fail "p1 stories are fr"; fi
if [[ "$proj" == *"later story"* || "$proj" == *"much later"* || "$proj" == *"no priority"* || "$proj" == *"two priorities"* || "$proj" == *"blocked NEEDS CLARIFICATION"* ]]; then fail "unmapped story body copied"; else pass "unmapped bodies omitted"; fi
if [[ "$proj" == *"User Story two P2"* && "$proj" == *"Notes"* && "$out" == *"Not a requirement. Not built from."* ]]; then pass "unmapped names listed"; else fail "unmapped names listed"; fi
if [[ "$proj" == *SENTINEL-PLAN-ONLY* || "$proj" == *MARKER-BODY* || "$proj" == *T001* ]]; then fail "side text in projection"; else pass "projection ignores side files"; fi
if [[ "$side" == *SENTINEL-PLAN-ONLY* && "$side" == *"    --- projected ---"* ]]; then pass "side evidence indented"; else fail "side evidence indented"; fi
if [[ "$out" == *SENTINEL-RESEARCH* || "$out" == *SENTINEL-CONTRACT* || "$out" == *SENTINEL-LINK* ]]; then fail "never-read sentinel leaked"; else pass "never-read content absent"; fi
if [[ "$out" == *"never-read"* && "$out" == *"research.md"* && "$out" == *"data-model.md"* && "$out" == *"contracts"* && "$out" == *"quickstart.md"* && "$out" == *"moved"* && "$out" == *"unmapped"* ]]; then pass "receipt sections"; else fail "receipt sections"; fi
if printf '%s' "$out" | python3 -c 'import sys; d=sys.stdin.buffer.read(); bad=[b for b in d if b<32 and b not in (9,10)]; sys.exit(0 if not bad else 1)'; then pass "no extra controls"; else fail "no extra controls"; fi

# control byte inside a mapped section
D="$(kit_of ctrl)"
python3 - "$D/spec.md" <<'PY'
import pathlib, sys
pathlib.Path(sys.argv[1]).write_bytes(b"## Success Criteria\nalpha\x07beta\n")
PY
want_ok "control strip" "$SUT" --cwd "$(dirname "$(dirname "$D")")" --dir "specs/001-demo"
proj="$(projected)"
if [[ "$proj" == *"alphabeta"* && "$proj" != *$'\a'* ]]; then pass "control byte removed"; else fail "control byte removed"; fi

# absent side files
D="$(kit_of absent-both)"
write_spec "$D" $'## Success Criteria\nok\n'
want_ok "both side files absent" "$SUT" --dir "$D"
if [[ "$out" == *"plan.md absent"* && "$out" == *"tasks.md absent"* ]]; then pass "both absent lines"; else fail "both absent lines"; fi

D="$(kit_of absent-plan)"
write_spec "$D" $'## Success Criteria\nok\n'
printf 'T001 only-in-tasks\n' >"$D/tasks.md"
want_ok "plan absent" "$SUT" --dir "$D"
proj="$(projected)"
if [[ "$out" == *"plan.md absent"* && "$proj" != *T001* ]]; then pass "plan absent and task id out of projection"; else fail "plan absent and task id out of projection"; fi

D="$(kit_of absent-tasks)"
write_spec "$D" $'## Success Criteria\nok\n'
printf 'SENTINEL-PLAN-ONLY\n' >"$D/plan.md"
want_ok "tasks absent" "$SUT" --dir "$D"
proj="$(projected)"
if [[ "$out" == *"tasks.md absent"* && "$proj" != *SENTINEL-PLAN-ONLY* ]]; then pass "tasks absent"; else fail "tasks absent"; fi

# timestamp prefix and relative vs absolute
D="$(kit_of ts)"
rmdir "$D"
mkdir -p "$(dirname "$(dirname "$D")")/specs/20261111-120000-demo"
write_spec "$(dirname "$(dirname "$D")")/specs/20261111-120000-demo" $'## Success Criteria\nts ok\n'
want_ok "timestamp prefix" "$SUT" --cwd "$(dirname "$(dirname "$D")")" --dir "specs/20261111-120000-demo"
ABS="$(dirname "$(dirname "$D")")/specs/20261111-120000-demo"
want_ok "absolute dir ignores cwd" "$SUT" --cwd "$WORK" --dir "$ABS"

# missing spec
D="$(kit_of nospec)"
rm -f "$D/spec.md"
want_reason "missing spec" "missing-spec" "$SUT" --dir "$D"

# symlinks
D="$(kit_of link-out)"
printf 'inside\n' >"$D/spec.md"
printf 'SENTINEL-OUTSIDE\n' >"$WORK/outside.txt"
rm -f "$D/spec.md"
ln -s "$WORK/outside.txt" "$D/spec.md"
want_reason "symlink leaves" "symlink-escape" "$SUT" --dir "$D"
if [[ "$out" == *SENTINEL-OUTSIDE* ]]; then fail "outside sentinel read"; else pass "outside sentinel unread"; fi

D="$(kit_of link-same)"
printf 'SENTINEL-RESEARCH\n' >"$D/research.md"
rm -f "$D/spec.md"
ln -s research.md "$D/spec.md"
want_reason "same-dir symlink" "symlink-escape" "$SUT" --dir "$D"
if [[ "$out" == *SENTINEL-RESEARCH* ]]; then fail "research sentinel read"; else pass "research sentinel unread"; fi

D="$(kit_of link-side)"
write_spec "$D" $'## Success Criteria\nONLYINSPEC\n'
printf 'SENTINEL-OUTSIDE\n' >"$WORK/side-outside.txt"
ln -s "$WORK/side-outside.txt" "$D/plan.md"
want_reason "side symlink fails whole intake" "symlink-escape" "$SUT" --dir "$D"
if [[ "$out" == *ONLYINSPEC* ]]; then fail "spec body printed after side symlink"; else pass "spec body withheld"; fi

BASE="$WORK/dirlink-real"
mkdir -p "$BASE/specs/001-demo"
printf '## Success Criteria\nSENTINEL-DIRLINK\n' >"$BASE/specs/001-demo/spec.md"
ln -s "$BASE" "$WORK/dirlink"
want_reason "symlinked directory component" "symlink-escape" "$SUT" --dir "$WORK/dirlink/specs/001-demo"
if [[ "$out" == *SENTINEL-DIRLINK* ]]; then fail "dirlink sentinel read"; else pass "dirlink sentinel unread"; fi

# fifo
D="$(kit_of fifo)"
rm -f "$D/spec.md"
mkfifo "$D/spec.md"
want_reason "fifo" "not-a-regular-file" "$SUT" --dir "$D"

# unreadable
D="$(kit_of mode0)"
write_spec "$D" $'## Success Criteria\nsecret\n'
chmod 000 "$D/spec.md"
if [[ "$(id -u)" -eq 0 ]]; then
  other="$(getent passwd | awk -F: '$3>=1000 && $3<65534 {print $1; exit}')"
  if [[ -z "$other" ]]; then
    fail "unreadable fail closed: no non-root user"
  else
    chmod 755 "$WORK" "$WORK/tree" "$WORK/tree/mode0" "$WORK/tree/mode0/specs" "$D"
    if command -v runuser >/dev/null 2>&1; then
      want_reason "unreadable" "unreadable" runuser -u "$other" -- "$SUT" --dir "$D"
    else
      fail "unreadable fail closed: cannot drop euid"
    fi
  fi
else
  want_reason "unreadable" "unreadable" "$SUT" --dir "$D"
fi
chmod 644 "$D/spec.md" 2>/dev/null || true

# size cap
python3 - "$WORK" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
def write(name, size, marker):
    d = root / "tree" / name / "specs" / "001-demo"
    d.mkdir(parents=True, exist_ok=True)
    prefix = b"## Success Criteria\n" + marker + b"\n"
    if len(prefix) >= size:
        raise SystemExit("prefix longer than cap")
    data = prefix + b"a" * (size - len(prefix))
    if len(data) != size:
        raise SystemExit("size math")
    (d / "spec.md").write_bytes(data)
write("cap-eq", 1048576, b"CAPEQUAL")
write("cap-over", 1048577, b"CAPOVER")
d = root / "tree" / "cap-side" / "specs" / "001-demo"
d.mkdir(parents=True)
(d / "spec.md").write_text("## Success Criteria\nONLYINSPEC\n")
(d / "plan.md").write_bytes(b"P" * 1048577)
PY
D="$WORK/tree/cap-eq/specs/001-demo"
want_ok "size equal cap" "$SUT" --dir "$D"
D="$WORK/tree/cap-over/specs/001-demo"
want_reason "size over cap" "over-cap" "$SUT" --dir "$D"
if [[ "$out" == *CAPOVER* ]]; then fail "over-cap body printed"; else pass "over-cap body absent"; fi
D="$WORK/tree/cap-side/specs/001-demo"
want_reason "side file over cap" "over-cap" "$SUT" --dir "$D"
if [[ "$out" == *ONLYINSPEC* ]]; then fail "spec printed when side over cap"; else pass "side over-cap withholds spec"; fi

# hostile directory entry
D="$(kit_of hostile)"
write_spec "$D" $'## Success Criteria\nok\n'
python3 - "$D" <<'PY'
import os, sys
os.close(os.open(os.path.join(sys.argv[1], "bad\nname"), os.O_CREAT | os.O_WRONLY, 0o644))
PY
want_reason "newline in entry name" "unreadable" "$SUT" --dir "$D"
if [[ "$out" == *"--- projected ---"* ]]; then fail "hostile name still projected"; else pass "hostile name prints no projection"; fi

# script does not write
D="$(kit_of nowrite)"
write_spec "$D" $'## Success Criteria\nok\n'
before="$(python3 - "$D" <<'PY'
import hashlib, os, sys
h = hashlib.sha256()
for dirpath, names, files in os.walk(sys.argv[1]):
    for n in sorted(names + files):
        p = os.path.join(dirpath, n)
        st = os.lstat(p)
        h.update(n.encode())
        h.update(str(st.st_size).encode())
        h.update(str(st.st_mtime_ns).encode())
print(h.hexdigest())
PY
)"
want_ok "no write run" "$SUT" --dir "$D"
after="$(python3 - "$D" <<'PY'
import hashlib, os, sys
h = hashlib.sha256()
for dirpath, names, files in os.walk(sys.argv[1]):
    for n in sorted(names + files):
        p = os.path.join(dirpath, n)
        st = os.lstat(p)
        h.update(n.encode())
        h.update(str(st.st_size).encode())
        h.update(str(st.st_mtime_ns).encode())
print(h.hexdigest())
PY
)"
if [[ "$before" == "$after" ]]; then pass "fixture bytes unchanged"; else fail "fixture bytes unchanged"; fi

# caller prose is in the skills, not a second script
if [[ -f "$BRAIN" ]] && grep -F "An empty spec directory is not the stop." "$BRAIN" >/dev/null \
  && grep -F "including zero bytes, do not run the script and do not replace it." "$BRAIN" >/dev/null \
  && grep -F "do not paste the path as prose." "$BRAIN" >/dev/null \
  && grep -F "scripts/spec-kit-intake.sh" "$BRAIN" >/dev/null \
  && grep -F "One-shot and Plan first arms pass that absolute directory" "$BRAIN" >/dev/null; then
  pass "brainstorm call site"
else
  fail "brainstorm call site"
fi
LINE='**Spec-kit intake, before step 4.** If the branch spec.md is absent and the argument is an existing specs/<prefix>-<short-name>/ directory, Read references/spec-kit-intake.md and follow it. If that spec file exists, including zero bytes, do not run the script and do not replace it.'
if [[ -f "$PLAN_SKILL" ]] && grep -F "$LINE" "$PLAN_SKILL" >/dev/null; then pass "plan call site"; else fail "plan call site"; fi
if [[ -f "$PLAN_REF" ]] && grep -F "do not paste the path as prose" "$PLAN_REF" >/dev/null \
  && grep -F "already absolute" "$PLAN_REF" >/dev/null; then
  pass "plan reference"
else
  fail "plan reference"
fi
if grep -F "A symlink to another name in the same directory fails the whole intake" "$SPEC" >/dev/null \
  && grep -F "The appendix does not copy section bodies." "$SPEC" >/dev/null \
  && grep -F "There is no human-edit detector." "$SPEC" >/dev/null; then
  pass "spec contract"
else
  fail "spec contract"
fi

if [[ "$fails" -ne 0 ]]; then
  printf 'spec-kit-intake: %s failed, %s passed\n' "$fails" "$passes" >&2
  printf '  %s\n' "${FAILED[@]}" >&2
  exit 1
fi
if [[ "$passes" -lt 40 ]]; then
  printf 'spec-kit-intake: pass count %s is under floor 40\n' "$passes" >&2
  exit 1
fi
printf 'spec-kit-intake: %s passed\n' "$passes"
exit 0
