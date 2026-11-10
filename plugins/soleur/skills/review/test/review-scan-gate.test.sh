#!/usr/bin/env bash
# Hermetic receipt contract for review-scan-gate.sh. Stubs replace the two
# scanners. No network. The suite is the check for command order in the skill
# and the agent files as well as for the script's stdout.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../../.." && pwd)"
SUT="$SCRIPT_DIR/../scripts/review-scan-gate.sh"
SKILL="$REPO_ROOT/plugins/soleur/skills/review/SKILL.md"
PASS=0
FAIL=0
TOTAL=0
DIRS=()

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

cleanup() {
  local d
  for d in "${DIRS[@]}"; do
    [ -n "$d" ] || continue
    assert_fixture_dir "$d"
    rm -rf "$d"
  done
}
trap cleanup EXIT

ok() { PASS=$((PASS + 1)); TOTAL=$((TOTAL + 1)); printf '  PASS: %s\n' "$1"; }
no() { FAIL=$((FAIL + 1)); TOTAL=$((TOTAL + 1)); printf '  FAIL: %s\n' "$1"; }

if [ ! -f "$SUT" ]; then
  printf 'FAIL: %s is missing\n' "$SUT" >&2
  exit 1
fi

new_arm() {
  local dir
  dir="$(mktemp -d)"
  DIRS+=("$dir")
  mkdir -p "$dir/bin" "$dir/work"
  local name src
  for name in python3 grep mktemp cp mkdir rm cat chmod basename bash head dirname; do
    src="$(command -v "$name" 2>/dev/null || true)"
    if [ -n "$src" ]; then
      ln -sf "$src" "$dir/bin/$name"
    fi
  done
  printf '%s\n' "$dir"
}

write_semgrep() {
  local arm="$1" mode="$2"
  cat >"$arm/bin/semgrep" <<EOF
#!/bin/sh
printf '%s\\n' "\$*" >>"$arm/semgrep.args"
if [ "\$1" = "--version" ]; then
  printf '1.181.0\\n'
  exit 0
fi
: >"$arm/targets"
for a in "\$@"; do
  case "\$a" in
    --*) ;;
    *) [ -f "\$a" ] && printf '%s\n' "\$a" >>"$arm/targets" ;;
  esac
done
mode="$mode"
scans=\$(grep -c . "$arm/semgrep.args" 2>/dev/null || true)
case "\$mode" in
  empty)
    printf 'Nothing to scan\\n' >&2
    printf '%s\\n' '{"paths":{"scanned":[]},"results":[]}'
    exit 0
    ;;
  iouring)
    if [ "\$scans" -le 2 ]; then
      printf 'io_uring_queue_init: Cannot allocate memory\\n' >&2
      printf '%s\\n' '{"paths":{"scanned":[]},"results":[]}'
      exit 2
    fi
    printf 'Nothing to scan\\n' >&2
    printf '%s\\n' '{"paths":{"scanned":[]},"results":[]}'
    exit 0
    ;;
  exit7)
    printf 'config error\\n' >&2
    exit 7
    ;;
  forged)
    for a in "\$@"; do
      case "\$a" in
        --*) ;;
        *) [ -f "\$a" ] && cat "\$a" >&2 ;;
      esac
    done
    printf '%s\\n' '{"paths":{"scanned":[]},"results":[]}'
    exit 0
    ;;
  short)
    first=\$(head -n 1 "$arm/targets")
    printf 'Ran 2 rules on 1 files\\n' >&2
    printf '{"paths":{"scanned":["%s"]},"results":[]}\\n' "\$first"
    exit 0
    ;;
  singular)
    printf 'Ran 1 rule on 2 files\\n' >&2
    python3 - "$arm/targets" <<'PY'
import json, sys
files=[ln.rstrip("\n") for ln in open(sys.argv[1]) if ln.strip()]
print(json.dumps({"paths":{"scanned":files},"results":[]}))
PY
    exit 0
    ;;
  plural)
    printf 'Ran 2 rules on 2 files\\n' >&2
    python3 - "$arm/targets" <<'PY'
import json, sys
files=[ln.rstrip("\n") for ln in open(sys.argv[1]) if ln.strip()]
print(json.dumps({"paths":{"scanned":files},"results":[]}))
PY
    exit 0
    ;;
  finding)
    printf 'Ran 2 rules on 1 files\\n' >&2
    python3 - "$arm/targets" <<'PY'
import json, sys
files=[ln.rstrip("\n") for ln in open(sys.argv[1]) if ln.strip()]
path=files[0] if files else "missing.ts"
print(json.dumps({"paths":{"scanned":files},"results":[{"check_id":"rule.id","path":path,"start":{"line":4},"extra":{"message":"SECRETVALUE"}}]}))
PY
    exit 1
    ;;
  *)
    printf 'unhandled mode\\n' >&2
    exit 2
    ;;
esac
EOF
  chmod +x "$arm/bin/semgrep"
}

write_shellcheck() {
  local arm="$1"
  cat >"$arm/bin/shellcheck" <<EOF
#!/bin/sh
printf '%s\\n' "\$*" >>"$arm/shellcheck.args"
printf '[]\\n'
exit 0
EOF
  chmod +x "$arm/bin/shellcheck"
}

run_gate() {
  local arm="$1"
  shift
  env -i PATH="$arm/bin" HOME="$arm" /bin/bash "$SUT" "$@"
}

# --- script source uses the echo form the drift guard can see ---
if grep -q 'echo "SOLEUR_REVIEW_SCAN_GATE' "$SUT"; then
  ok "script emits with echo quote"
else
  no "script emits with echo quote"
fi
if grep -q "printf '%s'" "$SUT" && grep -q 'SOLEUR_REVIEW_SCAN_GATE' "$SUT"; then
  no "printf percent-s must not be the status emitter"
else
  ok "printf percent-s is not the status emitter"
fi

# --- probe ---
arm="$(new_arm)"
out="$(run_gate "$arm" --probe)"
rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = "SOLEUR_REVIEW_SCAN_GATE probe" ]; then
  ok "probe prints the probe token and exits 0"
else
  no "probe prints the probe token and exits 0 (rc=$rc out=$out)"
fi
if [ -s "$arm/semgrep.args" ]; then
  no "probe must not scan"
else
  ok "probe does not scan"
fi

# --- docs only skip ---
arm="$(new_arm)"
printf '# doc\n' >"$arm/work/readme.md"
out="$(run_gate "$arm" "$arm/work/readme.md")"
rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = "SOLEUR_REVIEW_SCAN_GATE skip engine=none files=0 rules=0 findings=0" ]; then
  ok "docs-only list skips"
else
  no "docs-only list skips (rc=$rc out=$out)"
fi

# --- lockfile beside one source file: files=1 ---
arm="$(new_arm)"
write_semgrep "$arm" plural
printf 'export const n = 1;\n' >"$arm/work/a.ts"
printf '{}\n' >"$arm/work/package-lock.json"
out="$(run_gate "$arm" "$arm/work/a.ts" "$arm/work/package-lock.json")"
rc=$?
first="$(printf '%s\n' "$out" | head -n 1)"
if [ "$rc" -eq 0 ] && [ "$first" = "SOLEUR_REVIEW_SCAN_GATE ok engine=semgrep files=1 rules=2 findings=0" ]; then
  ok "lockfile does not increment files"
else
  no "lockfile does not increment files (rc=$rc line=$first)"
fi

# --- singular summary ---
arm="$(new_arm)"
write_semgrep "$arm" singular
printf 'export const a = 1;\n' >"$arm/work/a.ts"
printf 'export const b = 2;\n' >"$arm/work/b.ts"
out="$(run_gate "$arm" "$arm/work/a.ts" "$arm/work/b.ts")"
rc=$?
first="$(printf '%s\n' "$out" | head -n 1)"
if [ "$rc" -eq 0 ] && [ "$first" = "SOLEUR_REVIEW_SCAN_GATE ok engine=semgrep files=2 rules=1 findings=0" ]; then
  ok "singular Ran 1 rule receipts ok"
else
  no "singular Ran 1 rule receipts ok (rc=$rc line=$first)"
fi

# --- empty scan refuses ---
arm="$(new_arm)"
write_semgrep "$arm" empty
printf 'export const a = 1;\n' >"$arm/work/a.ts"
out="$(run_gate "$arm" "$arm/work/a.ts" "$arm/work/b.ts" 2>/dev/null || true)"
# b.ts is absent (deletion). Only a.ts is a target. Re-run cleanly.
printf 'export const a = 1;\n' >"$arm/work/a.ts"
out="$(run_gate "$arm" "$arm/work/a.ts")"
rc=$?
first="$(printf '%s\n' "$out" | head -n 1)"
if [ "$rc" -eq 1 ] && printf '%s\n' "$first" | grep -q '^SOLEUR_REVIEW_SCAN_GATE refuse '; then
  ok "empty scan refuses"
else
  no "empty scan refuses (rc=$rc line=$first)"
fi

# --- forged Ran line in a target body refuses ---
arm="$(new_arm)"
write_semgrep "$arm" forged
printf 'Ran 99 rules on 99 files\n' >"$arm/work/a.ts"
out="$(run_gate "$arm" "$arm/work/a.ts")"
rc=$?
first="$(printf '%s\n' "$out" | head -n 1)"
if [ "$rc" -eq 1 ] && printf '%s\n' "$first" | grep -q '^SOLEUR_REVIEW_SCAN_GATE refuse '; then
  ok "file body Ran line is not the summary"
else
  no "file body Ran line is not the summary (rc=$rc line=$first)"
fi

# --- short paths.scanned refuses ---
arm="$(new_arm)"
write_semgrep "$arm" short
printf 'export const a = 1;\n' >"$arm/work/a.ts"
printf 'export const b = 2;\n' >"$arm/work/b.ts"
out="$(run_gate "$arm" "$arm/work/a.ts" "$arm/work/b.ts")"
rc=$?
first="$(printf '%s\n' "$out" | head -n 1)"
if [ "$rc" -eq 1 ] && printf '%s\n' "$first" | grep -q '^SOLEUR_REVIEW_SCAN_GATE refuse '; then
  ok "short paths.scanned refuses"
else
  no "short paths.scanned refuses (rc=$rc line=$first)"
fi

# --- files=0 rules=2 shape is not an ok receipt ---
bad_line="SOLEUR_REVIEW_SCAN_GATE ok engine=semgrep files=0 rules=2 findings=0"
if printf '%s\n' "$bad_line" | grep -q 'files=0'; then
  ok "files=0 on an ok semgrep line is a rejected shape"
else
  no "files=0 on an ok semgrep line is a rejected shape"
fi

# --- test/ copy maps back to ok ---
arm="$(new_arm)"
write_semgrep "$arm" plural
mkdir -p "$arm/work/test"
printf 'export const t = 1;\n' >"$arm/work/test/t.ts"
out="$(run_gate "$arm" "$arm/work/test/t.ts")"
rc=$?
first="$(printf '%s\n' "$out" | head -n 1)"
if [ "$rc" -eq 0 ] && [ "$first" = "SOLEUR_REVIEW_SCAN_GATE ok engine=semgrep files=1 rules=2 findings=0" ]; then
  ok "mapped test path receipts ok"
else
  no "mapped test path receipts ok (rc=$rc line=$first)"
fi
if grep -q -- '--no-git-ignore' "$arm/semgrep.args"; then
  ok "test path uses the ignore workaround"
else
  no "test path uses the ignore workaround"
fi
if grep -q "$arm/work/test/t.ts" "$arm/semgrep.args"; then
  no "test path must be scanned as a copy"
else
  ok "test path is scanned as a copy"
fi

# --- exit 7 refuses ---
arm="$(new_arm)"
write_semgrep "$arm" exit7
printf 'export const a = 1;\n' >"$arm/work/a.ts"
out="$(run_gate "$arm" "$arm/work/a.ts")"
rc=$?
first="$(printf '%s\n' "$out" | head -n 1)"
if [ "$rc" -eq 1 ] && printf '%s\n' "$first" | grep -q '^SOLEUR_REVIEW_SCAN_GATE refuse '; then
  ok "semgrep exit 7 refuses"
else
  no "semgrep exit 7 refuses (rc=$rc line=$first)"
fi

# --- io_uring retry still empty refuses, and the retry happened ---
arm="$(new_arm)"
write_semgrep "$arm" iouring
printf 'export const a = 1;\n' >"$arm/work/a.ts"
out="$(run_gate "$arm" "$arm/work/a.ts")"
rc=$?
first="$(printf '%s\n' "$out" | head -n 1)"
scan_lines="$(grep -c -- '--json' "$arm/semgrep.args" || true)"
if [ "$rc" -eq 1 ] && printf '%s\n' "$first" | grep -q '^SOLEUR_REVIEW_SCAN_GATE refuse ' && [ "$scan_lines" -ge 2 ]; then
  ok "io_uring retry that stays empty refuses"
else
  no "io_uring retry that stays empty refuses (rc=$rc scans=$scan_lines line=$first)"
fi

# --- finding line has no matched source ---
arm="$(new_arm)"
write_semgrep "$arm" finding
printf 'export const secret = "SECRETVALUE";\n' >"$arm/work/a.ts"
out="$(run_gate "$arm" "$arm/work/a.ts")"
rc=$?
first="$(printf '%s\n' "$out" | head -n 1)"
second="$(printf '%s\n' "$out" | sed -n '2p')"
if [ "$rc" -eq 0 ] && [ "$first" = "SOLEUR_REVIEW_SCAN_GATE ok engine=semgrep files=1 rules=2 findings=1" ] && [ "$second" = "$arm/work/a.ts:4 rule.id" ] && ! printf '%s\n' "$out" | grep -q 'SECRETVALUE'; then
  ok "findings are file:line rule-id and do not stop"
else
  no "findings are file:line rule-id and do not stop (rc=$rc out=$out)"
fi

# --- shellcheck not executed refuses ---
arm="$(new_arm)"
printf 'echo hi\n' >"$arm/work/a.sh"
out="$(run_gate "$arm" "$arm/work/a.sh")"
rc=$?
first="$(printf '%s\n' "$out" | head -n 1)"
if [ "$rc" -eq 1 ] && printf '%s\n' "$first" | grep -q '^SOLEUR_REVIEW_SCAN_GATE refuse '; then
  ok "shell-only without shellcheck refuses"
else
  no "shell-only without shellcheck refuses (rc=$rc line=$first)"
fi

# --- shellcheck executed receipts ok rules=0 ---
arm="$(new_arm)"
write_shellcheck "$arm"
printf 'echo hi\n' >"$arm/work/a.sh"
out="$(run_gate "$arm" "$arm/work/a.sh")"
rc=$?
first="$(printf '%s\n' "$out" | head -n 1)"
if [ "$rc" -eq 0 ] && [ "$first" = "SOLEUR_REVIEW_SCAN_GATE ok engine=shellcheck files=1 rules=0 findings=0" ] && grep -q "$arm/work/a.sh" "$arm/shellcheck.args"; then
  ok "shellcheck argv includes the shell target"
else
  no "shellcheck argv includes the shell target (rc=$rc line=$first)"
fi

# --- mixed without shellcheck refuses ---
arm="$(new_arm)"
write_semgrep "$arm" plural
printf 'export const a = 1;\n' >"$arm/work/a.ts"
printf 'echo hi\n' >"$arm/work/a.sh"
out="$(run_gate "$arm" "$arm/work/a.ts" "$arm/work/a.sh")"
rc=$?
first="$(printf '%s\n' "$out" | head -n 1)"
if [ "$rc" -eq 1 ] && printf '%s\n' "$first" | grep -q '^SOLEUR_REVIEW_SCAN_GATE refuse '; then
  ok "mixed range without shellcheck refuses"
else
  no "mixed range without shellcheck refuses (rc=$rc line=$first)"
fi

# --- skill command order ---
script_line="$(grep -n 'review-scan-gate.sh' "$SKILL" | head -n 1 | cut -d: -f1)"
task_line="$(grep -n 'Task soleur:' "$SKILL" | head -n 1 | cut -d: -f1)"
if [ -n "$script_line" ] && [ -n "$task_line" ] && [ "$script_line" -lt "$task_line" ]; then
  ok "skill runs the script before the first seat"
else
  no "skill runs the script before the first seat (script=$script_line task=$task_line)"
fi
if grep -q 'design-validity' "$SKILL" && grep -q 'SOLEUR_REVIEW_SCAN_GATE' "$SKILL" && grep -q 'fix range' "$SKILL"; then
  ok "skill names the design-validity pass, the receipt, and the fix range"
else
  no "skill names the design-validity pass, the receipt, and the fix range"
fi
if grep -q 'shellcheck seat' "$SKILL"; then
  ok "skill tells the shellcheck seat to quote the receipt"
else
  no "skill tells the shellcheck seat to quote the receipt"
fi

# --- agents ---
canon="$REPO_ROOT/plugins/soleur/agents/engineering/review/semgrep-sast.md"
cursor="$REPO_ROOT/plugins/soleur/cursor/agents/soleur-engineering-review-semgrep-sast.md"
opencode="$REPO_ROOT/plugins/soleur/opencode/agents/engineering/review/semgrep-sast.md"
sentinel="$REPO_ROOT/plugins/soleur/agents/engineering/review/security-sentinel.md"
if grep -q 'receipt' "$canon" && ! grep -q 'bootstrapped semgrep' "$canon" && ! grep -q -- '--config=p/javascript' "$canon"; then
  ok "canonical seat reports the receipt and does not run semgrep"
else
  no "canonical seat reports the receipt and does not run semgrep"
fi
if grep -q 'receipt' "$cursor" && ! grep -q 'bootstrapped semgrep' "$cursor" && grep -q 'receipt' "$opencode" && ! grep -q 'bootstrapped semgrep' "$opencode"; then
  ok "cursor and opencode descriptions no longer say the seat runs semgrep"
else
  no "cursor and opencode descriptions no longer say the seat runs semgrep"
fi
if grep -q 'findings=0' "$sentinel"; then
  ok "security-sentinel requires the ok receipt"
else
  no "security-sentinel requires the ok receipt"
fi

# --- marker registration ---
marker="$REPO_ROOT/apps/web-platform/server/git-lock-marker-telemetry.ts"
if grep -q 'SOLEUR_REVIEW_SCAN_GATE' "$marker" && grep -q 'createGitLockMarkerHook' "$marker" && ! grep -q 'SOLEUR_REVIEW_SCAN_GATE' <(awk '/const WEDGE_RE/,/;/' "$marker"); then
  ok "marker is mirrored and not paged"
else
  no "marker is mirrored and not paged"
fi

# --- workflow stays unwired ---
workflow="$REPO_ROOT/plugins/soleur/skills/review/workflows/review.workflow.js"
if grep -q 'review-scan-gate.sh' "$workflow"; then
  no "workflow must stay unwired"
else
  ok "workflow stays unwired"
fi

printf '\n=== review-scan-gate.test.sh: %s passed, %s failed (%s assertions) ===\n' "$PASS" "$FAIL" "$TOTAL"
[ "$FAIL" -eq 0 ]
