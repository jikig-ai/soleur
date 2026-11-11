#!/usr/bin/env bash
# Synthesized fixtures only. The product script writes nothing.
# Pin residuals, stated here so a later sibling is covered by this round:
# - A refusal prefix on the same span can still contain a skill needle.
# - The one-shot arm in the brainstorm options list is not the pinned summary sentence.
# - A fenced copy of the plan line between step 3 and step 4 satisfies the window.
# - Goal text copied into Non-Goals is not denied.
# - The user-story boundary is the ASCII letter and digit class, the same class as the short-name. An underscore or a non-ASCII letter can continue the token.
# - A comment-only second copy of a needle, plus a comment inside the live span, can satisfy the raw check and the stripped check on different copies.
# - `heading none is one entry` lists that name. The empty-list pin is `empty unmapped emits no line`.
# shellcheck disable=SC2329
export TMPDIR="${TMPDIR:-/var/tmp}"
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
SUT="$REPO_ROOT/plugins/soleur/scripts/spec-kit-intake.sh"
BRAIN="$REPO_ROOT/plugins/soleur/skills/brainstorm/SKILL.md"
PLAN_SKILL="$REPO_ROOT/plugins/soleur/skills/plan/SKILL.md"
PLAN_REF="$REPO_ROOT/plugins/soleur/skills/plan/references/spec-kit-intake.md"
SPEC="$REPO_ROOT/knowledge-base/project/specs/archive/20261112-002904-feat-12531-spec-kit-ingestion/spec.md"

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
  # Own variable so the fixture scanner can follow this emit back to mktemp.
  local leaf="$d/specs/001-demo"
  assert_fixture_dir "$WORK"
  mkdir -p "$leaf"
  printf '%s' "$leaf"
}

write_spec() {
  local dir="$1"
  local body="$2"
  assert_fixture_dir "$dir"
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
if OUT="$out" python3 - <<'PY'
import os, sys
text = os.environ["OUT"]
marker = "\n--- projected ---\n"
if text.count(marker) != 1:
    sys.exit("marker count")
prefix, proj = text.split(marker, 1)
if "\n--- projected ---\n" in proj or "\n--- side-evidence ---\n" in proj:
    sys.exit("marker inside projection")
lines = prefix.split("\n")
want_moved = "moved: Goals, Non-Goals, Functional Requirements"
if want_moved not in lines:
    sys.exit("moved line")
unmapped = [ln[len("unmapped: "):] for ln in lines if ln.startswith("unmapped: ")]
if unmapped != [
    "User Story two P2",
    "User Story three P3",
    "User Story plain",
    "User Story both P1 P2",
    "Notes",
    "User Story blocked P1",
]:
    sys.exit("unmapped lines %r" % unmapped)
never = [ln[len("never-read: "):] for ln in lines if ln.startswith("never-read: ")]
if never != ["research.md", "data-model.md", "contracts", "quickstart.md", "linked.md"]:
    sys.exit("never-read lines %r" % never)

def between(src, start, end):
    a = src.find(start)
    b = src.find(end, a + len(start))
    if a < 0 or b < 0:
        sys.exit("missing %s" % start)
    return src[a + len(start):b]

goals = between(proj, "## Goals\n", "\n## Non-Goals")
nongoals = between(proj, "## Non-Goals\n", "\n## Functional Requirements")
frs = between(proj, "## Functional Requirements\n", "\n## Unmapped appendix")
for bit in ("alpha keeps the lights on", "second goal line"):
    if bit not in goals:
        sys.exit("goal missing %s" % bit)
for bit in ("no billing", "no sync", "no import"):
    if bit not in nongoals:
        sys.exit("nongoal missing %s" % bit)
for bit in ("the first story", "substring is not a priority", "needs clarification in other words"):
    if bit not in frs:
        sys.exit("fr missing %s" % bit)
for bit in ("later story", "much later", "the first story", "FENCED-ONLY", "SETEXT-BODY"):
    if bit in goals or bit in nongoals:
        sys.exit("misfiled %s" % bit)
if "later story" in frs or "FENCED-ONLY" in frs or "alpha keeps the lights on" in frs:
    sys.exit("fr misfile")
PY
then pass "receipt slices"; else fail "receipt slices"; fi
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

# caller prose is in the skills, not a second script. Each needle must be
# contiguous in the raw file and after HTML comments are removed.
if missing="$(python3 - "$BRAIN" "$PLAN_SKILL" "$PLAN_REF" <<'PY'
import pathlib, re, sys
def load(path):
    raw = pathlib.Path(path).read_text()
    vis = re.sub(r"<!--.*?-->", "", raw, flags=re.S)
    return raw, vis
brain_raw, brain = load(sys.argv[1])
plan_raw, plan = load(sys.argv[2])
ref_raw, ref = load(sys.argv[3])
missing = []
def need(raw, hay, needle, label):
    if needle not in raw or needle not in hay:
        missing.append(label)
need(brain_raw, brain, "An empty spec directory is not the stop.", "brain-empty")
need(brain_raw, brain, "including zero bytes, do not run the script and do not replace it.", "brain-zero")
need(brain_raw, brain, "do not paste the path as prose.", "brain-paste")
need(brain_raw, brain, 'and run `"${CLAUDE_PLUGIN_ROOT}/scripts/spec-kit-intake.sh"`', "brain-run")
need(brain_raw, brain, "One-shot and Plan first arms pass that absolute directory", "brain-handoff")
need(brain_raw, brain, "One-shot forwards it unchanged as plan's arguments.", "brain-forward")
need(brain_raw, brain, "If the file exists, including a zero-byte file, do not replace it.", "brain-save")
line = "**Spec-kit intake, before step 4.** If the branch spec.md is absent and the argument is an existing specs/<prefix>-<short-name>/ directory, Read plugins/soleur/skills/plan/references/spec-kit-intake.md and follow it. If that spec file exists, including zero bytes, do not run the script and do not replace it."
need(plan_raw, plan, line, "plan-line")
step3 = plan.find("3. Detect feature from current branch")
step4 = plan.find("4. Read `knowledge-base/project/specs/feat-<name>/spec.md`")
at = plan.find(line)
if not (step3 >= 0 and at >= 0 and step4 >= 0 and step3 < at < step4):
    missing.append("plan-before-step-4")
need(ref_raw, ref, '. Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/spec-kit-intake.sh"`', "ref-run")
need(ref_raw, ref, "already absolute", "ref-absolute")
need(ref_raw, ref, "do not paste the path as prose", "ref-paste")
if missing:
    print(",".join(missing))
    raise SystemExit(1)
PY
)"; then
  pass "skill sentences"
else
  fail "skill sentences: $missing"
fi
if grep -F "A symlink to another name in the same directory fails the whole intake" "$SPEC" >/dev/null \
  && grep -F "The appendix does not copy section bodies." "$SPEC" >/dev/null \
  && grep -F "There is no human-edit detector." "$SPEC" >/dev/null; then
  pass "spec contract"
else
  fail "spec contract"
fi

# ordinary heading body is not a requirement
D="$(kit_of ordinary)"
write_spec "$D" $'## Architecture\nbuild the moon\n## Success Criteria\nlamp\n'
want_ok "ordinary heading" "$SUT" --dir "$D"
proj="$(projected)"
if [[ "$proj" == *"build the moon"* ]]; then fail "ordinary body copied"; else pass "ordinary body absent"; fi
if [[ "$out" == *$'\nunmapped: Architecture\n'* && "$proj" == *"- Architecture"* && "$proj" == *"lamp"* ]]; then
  pass "ordinary name listed"
else
  fail "ordinary name listed"
fi

# mapped body cannot repeat a frame line
D="$(kit_of marker-body)"
write_spec "$D" $'## Success Criteria\nkeep the lamp\n--- projected ---\nstolen\n'
want_reason "marker in mapped body" "unreadable" "$SUT" --dir "$D"
D="$(kit_of label-body)"
write_spec "$D" $'## Success Criteria\nkeep the lamp\nnever-read: research.md\n'
want_reason "receipt label in mapped body" "unreadable" "$SUT" --dir "$D"

# dot is a path component, dotdot is not
D="$(kit_of dot)"
write_spec "$D" $'## Success Criteria\ndot ok\n'
want_ok "relative dot component" "$SUT" --cwd "$(dirname "$(dirname "$D")")" --dir "./specs/001-demo"
proj="$(projected)"
if [[ "$proj" == *"dot ok"* ]]; then pass "relative dot projected"; else fail "relative dot projected"; fi
want_ok "absolute dot component" "$SUT" --dir "$(dirname "$(dirname "$D")")/./specs/001-demo"
want_ok "dot between specs and leaf" "$SUT" --cwd "$(dirname "$(dirname "$D")")" --dir "specs/./001-demo"
want_ok "trailing dot component" "$SUT" --dir "$D/."
want_reason "dotdot component" "not-a-directory" "$SUT" --dir "$WORK/tree/dot/specs/../001-demo"
want_reason "dot then dotdot" "not-a-directory" "$SUT" --dir "$WORK/tree/dot/specs/./../specs/001-demo"

# closing hashes are not part of the heading text
D="$(kit_of hashes)"
write_spec "$D" $'## Success Criteria ##\nlamp stays on\n## Out of Scope ##\nno billing\n'
want_ok "closing hashes" "$SUT" --dir "$D"
proj="$(projected)"
if [[ "$proj" == *"lamp stays on"* && "$proj" == *"no billing"* && "$out" != *"Success Criteria ##"* && "$out" != *"Out of Scope ##"* ]]; then
  pass "closing hashes mapped"
else
  fail "closing hashes mapped"
fi

# token boundary, and the plural heading is not a user story
D="$(kit_of tokens)"
write_spec "$D" $'## Superuser story P1\nnot a story\n## User storyboard P1\nnot a board\n## User Stories P1\nplural body\n## User Story real P1\nreal story\n'
want_ok "token boundary" "$SUT" --dir "$D"
proj="$(projected)"
if [[ "$proj" == *"real story"* && "$proj" != *"not a story"* && "$proj" != *"not a board"* && "$proj" != *"plural body"* ]]; then
  pass "token boundary bodies"
else
  fail "token boundary bodies"
fi
if [[ "$out" == *$'\nunmapped: Superuser story P1\n'* && "$out" == *$'\nunmapped: User storyboard P1\n'* && "$out" == *$'\nunmapped: User Stories P1\n'* ]]; then
  pass "token boundary names"
else
  fail "token boundary names"
fi

# empty mapped headings are listed, not dropped
D="$(kit_of empty-head)"
write_spec "$D" $'## Success Criteria\n## User Story one P1\n## Out of Scope\nlater excluded\n'
want_ok "empty mapped heading" "$SUT" --dir "$D"
proj="$(projected)"
if [[ "$out" == "moved: Non-Goals"$'\n'* && "$out" == *$'\nunmapped: Success Criteria\n'* && "$out" == *$'\nunmapped: User Story one P1\n'* && "$proj" == *"later excluded"* ]]; then
  pass "empty headings listed"
else
  fail "empty headings listed"
fi

# a comma stays inside one receipt entry
D="$(kit_of comma)"
write_spec "$D" $'## Notes, assumptions\nstays out\n'
printf 'x\n' >"$D/extra,note.md"
want_ok "comma in names" "$SUT" --dir "$D"
proj="$(projected)"
if [[ "$out" == *$'\nunmapped: Notes, assumptions\n'* && "$out" == *$'\nnever-read: extra,note.md\n'* && "$proj" != *"stays out"* ]]; then
  pass "comma stays one entry"
else
  fail "comma stays one entry"
fi

# U+0085 is stripped from file bytes and refused in a directory name
D="$(kit_of nel)"
python3 - "$D/spec.md" <<'PY'
import pathlib, sys
pathlib.Path(sys.argv[1]).write_bytes(b"## Success Criteria\nkeep\xc2\x85--- projected ---\nstolen\n")
PY
want_ok "nel in file" "$SUT" --dir "$D"
if OUT="$out" python3 - <<'PY'
import os, sys
raw = os.environ["OUT"].encode()
if b"\xc2\x85" in raw:
    sys.exit("nel survived")
text = os.environ["OUT"]
if text.split("\n").count("--- projected ---") != 1:
    sys.exit("marker lines")
if text.splitlines().count("--- projected ---") != 1:
    sys.exit("splitlines marker")
if "keep--- projected ---" not in text:
    sys.exit("glued line missing")
PY
then pass "nel stripped"; else fail "nel stripped"; fi
D="$(kit_of nel-name)"
write_spec "$D" $'## Success Criteria\nok\n'
python3 - "$D" <<'PY'
import os, sys
os.close(os.open(os.path.join(sys.argv[1], "bad\u0085name"), os.O_CREAT | os.O_WRONLY, 0o644))
PY
want_reason "nel in entry name" "unreadable" "$SUT" --dir "$D"
D="$(kit_of ff-name)"
write_spec "$D" $'## Success Criteria\nok\n'
python3 - "$D" <<'PY'
import os, sys
os.close(os.open(os.path.join(sys.argv[1], "bad\x0cname"), os.O_CREAT | os.O_WRONLY, 0o644))
PY
want_reason "form feed in entry name" "unreadable" "$SUT" --dir "$D"

# invalid UTF-8 is a refusal, not a replacement character
D="$(kit_of bad-utf)"
python3 - "$D/spec.md" <<'PY'
import pathlib, sys
pathlib.Path(sys.argv[1]).write_bytes(b"## User Story bad P1\nNEEDS CLARIFICATION\xff\n")
PY
want_reason "invalid utf-8" "unreadable" "$SUT" --dir "$D"

# fence length and character, and frontmatter after a blank or a BOM
D="$(kit_of fence4)"
python3 - "$D/spec.md" <<'PY'
import pathlib, sys
pathlib.Path(sys.argv[1]).write_text("""````
```
## User Story evil P1
EVIL-BODY
```
````
## Success Criteria
lamp from fence
""", encoding="utf-8")
PY
want_ok "four backtick fence" "$SUT" --dir "$D"
proj="$(projected)"
if [[ "$proj" == *"lamp from fence"* && "$proj" != *"EVIL-BODY"* ]]; then pass "long fence holds"; else fail "long fence holds"; fi
D="$(kit_of fence-tilde)"
python3 - "$D/spec.md" <<'PY'
import pathlib, sys
pathlib.Path(sys.argv[1]).write_text("""~~~
## User Story evil P1
TILDE-BODY
```
~~~
## Success Criteria
lamp from tilde
""", encoding="utf-8")
PY
want_ok "tilde fence" "$SUT" --dir "$D"
proj="$(projected)"
if [[ "$proj" == *"lamp from tilde"* && "$proj" != *"TILDE-BODY"* ]]; then pass "tilde fence holds"; else fail "tilde fence holds"; fi
D="$(kit_of fence-indent)"
python3 - "$D/spec.md" <<'PY'
import pathlib, sys
pathlib.Path(sys.argv[1]).write_text("   ```\n## User Story evil P1\nINDENTED-EVIL\n   ```\n## Success Criteria\nlamp indented\n", encoding="utf-8")
PY
want_ok "three space fence" "$SUT" --dir "$D"
proj="$(projected)"
if [[ "$proj" == *"lamp indented"* && "$proj" != *"INDENTED-EVIL"* ]]; then pass "indented fence holds"; else fail "indented fence holds"; fi
D="$(kit_of fence-four-space)"
python3 - "$D/spec.md" <<'PY'
import pathlib, sys
pathlib.Path(sys.argv[1]).write_text("    ```\n## User Story evil P1\nFOURSPACE-EVIL\n    ```\n## Success Criteria\nlamp four\n", encoding="utf-8")
PY
want_ok "four space fence" "$SUT" --dir "$D"
proj="$(projected)"
if [[ "$proj" == *"FOURSPACE-EVIL"* && "$proj" == *"lamp four"* ]]; then pass "four space fence is text"; else fail "four space fence is text"; fi
D="$(kit_of front-blank)"
python3 - "$D/spec.md" <<'PY'
import pathlib, sys
pathlib.Path(sys.argv[1]).write_bytes(b"\xef\xbb\xbf\n---\ntitle: hidden\nSENTINEL-FM\n---\n## Success Criteria\nbom goal\n")
PY
want_ok "bom and leading blank frontmatter" "$SUT" --dir "$D"
proj="$(projected)"
if [[ "$proj" == *"bom goal"* && "$proj" != *"SENTINEL-FM"* && "$out" != *"SENTINEL-FM"* ]]; then
  pass "leading frontmatter hidden"
else
  fail "leading frontmatter hidden"
fi

# a C0 or DEL inside a break sequence must not reassemble that break
D="$(kit_of split-break)"
python3 - "$D" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
root.joinpath("spec.md").write_bytes(
    b"## Success Criteria\nkeep\xc2\x0c\x85--- projected ---\nstolen\n"
    b"## Notes\xe2\x0c\x80\xa8moved: stolen\n"
)
root.joinpath("plan.md").write_bytes(
    b"side\xc2\x0c\xc2\x85\x85nested\nkeep\xe2\x7f\x80\xa8--- projected ---\n"
)
root.joinpath("tasks.md").write_bytes(b"task\xe2\x0b\x80\xa9--- side-evidence ---\n")
PY
want_ok "split break sequences" "$SUT" --dir "$D"
if OUT="$out" python3 - <<'PY'
import os, sys
raw = os.environ["OUT"].encode()
for seq in (b"\xc2\x85", b"\xe2\x80\xa8", b"\xe2\x80\xa9"):
    if seq in raw:
        sys.exit("break bytes %r" % seq)
text = os.environ["OUT"]
if text.splitlines().count("--- projected ---") != 1:
    sys.exit("projected markers")
if text.splitlines().count("--- side-evidence ---") != 1:
    sys.exit("side markers")
if sum(1 for ln in text.splitlines() if ln.startswith("moved:")) != 1:
    sys.exit("moved lines")
if "keep" not in text or "stolen" not in text:
    sys.exit("goal text")
PY
then pass "split breaks stripped"; else fail "split breaks stripped"; fi

# first closed pair, wherever it starts; an unclosed opener does not eat headings
D="$(kit_of fm-pair)"
python3 - "$D/spec.md" <<'PY'
import pathlib, sys
pathlib.Path(sys.argv[1]).write_text(
    "preface\n"
    "## Success Criteria\n"
    "visible goal\n"
    "--- \n"
    "## User Story hidden P1\n"
    "HIDDEN-STORY\n"
    "---\t\n"
    "## Out of Scope\n"
    "later excluded\n"
    "---\n"
    "## User Story later P1\n"
    "LATER-STORY\n"
    "---\n",
    encoding="utf-8",
)
PY
want_ok "frontmatter pair after prefix" "$SUT" --dir "$D"
proj="$(projected)"
if [[ "$proj" == *"visible goal"* && "$proj" == *"later excluded"* && "$proj" == *"LATER-STORY"* && "$proj" != *"HIDDEN-STORY"* && "$out" != *"HIDDEN-STORY"* ]]; then
  pass "first pair hidden later pair kept"
else
  fail "first pair hidden later pair kept"
fi
D="$(kit_of fm-open)"
python3 - "$D/spec.md" <<'PY'
import pathlib, sys
pathlib.Path(sys.argv[1]).write_bytes(
    b"\xef\xbb\xbf\n---\n## Success Criteria\nunclosed goal\n"
)
PY
want_ok "unclosed frontmatter" "$SUT" --dir "$D"
proj="$(projected)"
if [[ "$out" == "moved: Goals"$'\n'* && "$proj" == *"unclosed goal"* ]]; then
  pass "unclosed opener still projects"
else
  fail "unclosed opener still projects"
fi

# a --- inside a fence is not the other half of a frontmatter pair
D="$(kit_of fm-fence)"
python3 - "$D/spec.md" <<'PY'
import pathlib, sys
pathlib.Path(sys.argv[1]).write_text(
    "---\n"
    "```\n"
    "---\n"
    "## User Story fenced P1\n"
    "FENCED-STORY\n"
    "```\n"
    "## Success Criteria\n"
    "goal outside\n",
    encoding="utf-8",
)
PY
want_ok "fenced delimiter is not a closer" "$SUT" --dir "$D"
proj="$(projected)"
if [[ "$out" == "moved: Goals"$'\n'* && "$proj" == *"goal outside"* && "$proj" != *"FENCED-STORY"* ]]; then
  pass "fenced closer ignored"
else
  fail "fenced closer ignored"
fi
D="$(kit_of fm-fence-opener)"
python3 - "$D/spec.md" <<'PY'
import pathlib, sys
pathlib.Path(sys.argv[1]).write_text(
    "```\n"
    "---\n"
    "```\n"
    "## Success Criteria\n"
    "goal outside\n"
    "--- \n"
    "## Out of Scope\n"
    "later excluded\n",
    encoding="utf-8",
)
PY
want_ok "fenced delimiter is not an opener" "$SUT" --dir "$D"
proj="$(projected)"
if [[ "$proj" == *"goal outside"* && "$proj" == *"later excluded"* && "$out" == *"moved: Goals, Non-Goals"* ]]; then
  pass "fenced opener ignored"
else
  fail "fenced opener ignored"
fi

# an empty unmapped list is not the line a heading named none uses
D="$(kit_of mapped-only)"
write_spec "$D" $'## Success Criteria\nonly goal\n## Out of Scope\nnope\n## User Story one P1\nstory\n'
want_ok "fully mapped" "$SUT" --dir "$D"
if [[ "$out" != *"unmapped:"* && "$out" == "moved: Goals, Non-Goals, Functional Requirements"$'\n'* ]]; then
  pass "empty unmapped emits no line"
else
  fail "empty unmapped emits no line"
fi
D="$(kit_of name-none)"
write_spec "$D" $'## none\nstays out\n## Success Criteria\nlamp\n'
want_ok "heading named none" "$SUT" --dir "$D"
proj="$(projected)"
if [[ "$out" == *$'\nunmapped: none\n'* && "$proj" != *"stays out"* && "$proj" == *"lamp"* ]]; then
  pass "heading none is one entry"
else
  fail "heading none is one entry"
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
