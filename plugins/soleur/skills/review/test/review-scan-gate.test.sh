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
  assert_fixture_dir "$arm"
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
    python3 - "$arm/targets" <<'PY'
import json, sys
files=[ln.rstrip("\n") for ln in open(sys.argv[1]) if ln.strip()]
print(json.dumps({"paths":{"scanned":files},"results":[]}))
PY
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
  local arm="$1" mode="${2:-clean}"
  assert_fixture_dir "$arm"
  cat >"$arm/bin/shellcheck" <<EOF
#!/bin/sh
printf '%s\\n' "\$*" >>"$arm/shellcheck.args"
mode="$mode"
case "\$mode" in
  clean)
    printf '[]\\n'
    exit 0
    ;;
  hang)
    exec python3 -c 'import time; time.sleep(120)'
    ;;
  malformed)
    printf 'this is not a json array\\n'
    exit 0
    ;;
  emptyout)
    exit 0
    ;;
  exit3)
    printf '[]\\n'
    exit 3
    ;;
  finding-b)
    last=""
    for a in "\$@"; do last="\$a"; done
    case "\$last" in
      *b.sh*)
        printf '[{"file":"%s","line":4,"endLine":4,"column":10,"endColumn":12,"level":"warning","code":2086,"message":"Double quote to prevent globbing."}]\\n' "\$last"
        exit 1
        ;;
      *)
        printf '[]\\n'
        exit 0
        ;;
    esac
    ;;
  *)
    printf 'unhandled shellcheck stub mode\\n' >&2
    exit 2
    ;;
esac
EOF
  chmod +x "$arm/bin/shellcheck"
}

# A hermetic stand-in for GNU timeout: parses `-k <grace> <duration> <cmd...>`,
# forwards the command's exit status when it completes, and kills the command
# then exits 124 when the command outlives the stub's short internal deadline
# (~1.5s, independent of the requested duration so the suite stays fast). Every
# invocation's argv is appended to timeout.args so tests can pin the exact
# `-k 5s 30s` envelope the gate is contractually required to use.
write_timeout() {
  local arm="$1" name="${2:-timeout}"
  assert_fixture_dir "$arm"
  cat >"$arm/bin/$name" <<EOF
#!/usr/bin/env python3
import subprocess, sys

LOG = "$arm/timeout.args"
DEADLINE = 1.5

argv = sys.argv[1:]
with open(LOG, "a") as fh:
    fh.write(" ".join(argv) + "\\n")

i = 0
while i < len(argv):
    a = argv[i]
    if a in ("-k", "--kill-after"):
        i += 2
    elif a.startswith("--kill-after="):
        i += 1
    elif a.startswith("-"):
        i += 1
    else:
        break
rest = argv[i:]
if len(rest) < 2:
    sys.stderr.write("timeout stub: bad argv\\n")
    sys.exit(2)
cmd = rest[1:]
try:
    proc = subprocess.Popen(cmd)
except FileNotFoundError:
    sys.exit(127)
except PermissionError:
    sys.exit(126)
try:
    rc = proc.wait(timeout=DEADLINE)
    if rc < 0:
        rc = 128 - rc
    sys.exit(rc)
except subprocess.TimeoutExpired:
    proc.terminate()
    try:
        proc.wait(timeout=0.5)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait()
    sys.exit(124)
EOF
  chmod +x "$arm/bin/$name"
}

# The host's real timeout binary bounds every gate invocation from OUTSIDE the
# hermetic PATH: a gate that wedges on a pathological input (the defect this
# suite exists to prevent) is a slow RED, never an infinite hang of the suite.
REAL_TIMEOUT="$(command -v timeout 2>/dev/null || command -v gtimeout 2>/dev/null || true)"

run_gate() {
  local arm="$1"
  shift
  if [ -n "$REAL_TIMEOUT" ]; then
    "$REAL_TIMEOUT" -k 5s 30s env -i PATH="$arm/bin" HOME="$arm" /bin/bash "$SUT" "$@"
  else
    env -i PATH="$arm/bin" HOME="$arm" /bin/bash "$SUT" "$@"
  fi
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
DIRS+=("$arm")
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
DIRS+=("$arm")
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
DIRS+=("$arm")
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
DIRS+=("$arm")
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
DIRS+=("$arm")
write_semgrep "$arm" empty
printf 'export const a = 1;\n' >"$arm/work/a.ts"
out="$(run_gate "$arm" "$arm/work/a.ts" "$arm/work/b.ts" 2>/dev/null || true)"
# b.ts is absent (deletion). Only a.ts is a target. Re-run cleanly.
printf 'export const a = 1;\n' >"$arm/work/a.ts"
out="$(run_gate "$arm" "$arm/work/a.ts")"
rc=$?
first="$(printf '%s\n' "$out" | head -n 1)"
if [ "$rc" -eq 1 ] && grep -q '^SOLEUR_REVIEW_SCAN_GATE refuse ' <<<"$first"; then
  ok "empty scan refuses"
else
  no "empty scan refuses (rc=$rc line=$first)"
fi

# --- forged Ran line in a target body refuses ---
arm="$(new_arm)"
DIRS+=("$arm")
write_semgrep "$arm" forged
printf 'Ran 99 rules on 99 files\n' >"$arm/work/a.ts"
out="$(run_gate "$arm" "$arm/work/a.ts")"
rc=$?
first="$(printf '%s\n' "$out" | head -n 1)"
if [ "$rc" -eq 1 ] && [ "$first" = "SOLEUR_REVIEW_SCAN_GATE refuse engine=semgrep files=1 rules=0 findings=0" ]; then
  ok "file body Ran line is not the summary"
else
  no "file body Ran line is not the summary (rc=$rc line=$first)"
fi

# --- short paths.scanned refuses ---
arm="$(new_arm)"
DIRS+=("$arm")
write_semgrep "$arm" short
printf 'export const a = 1;\n' >"$arm/work/a.ts"
printf 'export const b = 2;\n' >"$arm/work/b.ts"
out="$(run_gate "$arm" "$arm/work/a.ts" "$arm/work/b.ts")"
rc=$?
first="$(printf '%s\n' "$out" | head -n 1)"
if [ "$rc" -eq 1 ] && grep -q '^SOLEUR_REVIEW_SCAN_GATE refuse ' <<<"$first"; then
  ok "short paths.scanned refuses"
else
  no "short paths.scanned refuses (rc=$rc line=$first)"
fi

# --- files=0 rules=2 shape is not an ok receipt ---
bad_line="SOLEUR_REVIEW_SCAN_GATE ok engine=semgrep files=0 rules=2 findings=0"
if grep -q 'files=0' <<<"$bad_line"; then
  ok "files=0 on an ok semgrep line is a rejected shape"
else
  no "files=0 on an ok semgrep line is a rejected shape"
fi

# --- a non-ts source suffix is still a target ---
arm="$(new_arm)"
DIRS+=("$arm")
write_semgrep "$arm" plural
printf 'export const a = 1;\n' >"$arm/work/a.ts"
printf 'export const b = 1;\n' >"$arm/work/b.js"
out="$(run_gate "$arm" "$arm/work/a.ts" "$arm/work/b.js")"
rc=$?
first="$(printf '%s\n' "$out" | head -n 1)"
if [ "$rc" -eq 0 ] && [ "$first" = "SOLEUR_REVIEW_SCAN_GATE ok engine=semgrep files=2 rules=2 findings=0" ]; then
  ok "js suffix counts as a source target"
else
  no "js suffix counts as a source target (rc=$rc line=$first)"
fi

# --- test/ copy maps back to ok ---
arm="$(new_arm)"
DIRS+=("$arm")
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

# --- two test files must both be scanned ---
arm="$(new_arm)"
DIRS+=("$arm")
write_semgrep "$arm" plural
mkdir -p "$arm/work/test"
printf 'export const t = 1;\n' >"$arm/work/test/t.ts"
printf 'export const u = 2;\n' >"$arm/work/test/u.ts"
out="$(run_gate "$arm" "$arm/work/test/t.ts" "$arm/work/test/u.ts")"
rc=$?
first="$(printf '%s\n' "$out" | head -n 1)"
if [ "$rc" -eq 0 ] && [ "$first" = "SOLEUR_REVIEW_SCAN_GATE ok engine=semgrep files=2 rules=2 findings=0" ]; then
  ok "both test files map back"
else
  no "both test files map back (rc=$rc line=$first)"
fi
arm="$(new_arm)"
DIRS+=("$arm")
write_semgrep "$arm" short
mkdir -p "$arm/work/test"
printf 'export const t = 1;\n' >"$arm/work/test/t.ts"
printf 'export const u = 2;\n' >"$arm/work/test/u.ts"
out="$(run_gate "$arm" "$arm/work/test/t.ts" "$arm/work/test/u.ts")"
rc=$?
first="$(printf '%s\n' "$out" | head -n 1)"
if [ "$rc" -eq 1 ] && grep -q '^SOLEUR_REVIEW_SCAN_GATE refuse ' <<<"$first"; then
  ok "a short test-file scan refuses"
else
  no "a short test-file scan refuses (rc=$rc line=$first)"
fi

# --- exit 7 refuses ---
arm="$(new_arm)"
DIRS+=("$arm")
write_semgrep "$arm" exit7
printf 'export const a = 1;\n' >"$arm/work/a.ts"
out="$(run_gate "$arm" "$arm/work/a.ts")"
rc=$?
first="$(printf '%s\n' "$out" | head -n 1)"
if [ "$rc" -eq 1 ] && grep -q '^SOLEUR_REVIEW_SCAN_GATE refuse ' <<<"$first"; then
  ok "semgrep exit 7 refuses"
else
  no "semgrep exit 7 refuses (rc=$rc line=$first)"
fi

# --- io_uring retry still empty refuses, and the retry happened ---
arm="$(new_arm)"
DIRS+=("$arm")
write_semgrep "$arm" iouring
printf 'export const a = 1;\n' >"$arm/work/a.ts"
out="$(run_gate "$arm" "$arm/work/a.ts")"
rc=$?
first="$(printf '%s\n' "$out" | head -n 1)"
scan_lines="$(grep -c -- '--json' "$arm/semgrep.args" || true)"
if [ "$rc" -eq 1 ] && grep -q '^SOLEUR_REVIEW_SCAN_GATE refuse ' <<<"$first" && [ "$scan_lines" -ge 2 ]; then
  ok "io_uring retry that stays empty refuses"
else
  no "io_uring retry that stays empty refuses (rc=$rc scans=$scan_lines line=$first)"
fi

# --- finding line has no matched source ---
arm="$(new_arm)"
DIRS+=("$arm")
write_semgrep "$arm" finding
printf 'export const secret = "SECRETVALUE";\n' >"$arm/work/a.ts"
out="$(run_gate "$arm" "$arm/work/a.ts")"
rc=$?
first="$(printf '%s\n' "$out" | head -n 1)"
second="$(printf '%s\n' "$out" | sed -n '2p')"
if [ "$rc" -eq 0 ] && [ "$first" = "SOLEUR_REVIEW_SCAN_GATE ok engine=semgrep files=1 rules=2 findings=1" ] && [ "$second" = "$arm/work/a.ts:4 rule.id" ] && ! grep -q 'SECRETVALUE' <<<"$out"; then
  ok "findings are file:line rule-id and do not stop"
else
  no "findings are file:line rule-id and do not stop (rc=$rc out=$out)"
fi

# --- shellcheck not executed refuses ---
arm="$(new_arm)"
DIRS+=("$arm")
printf 'echo hi\n' >"$arm/work/a.sh"
out="$(run_gate "$arm" "$arm/work/a.sh")"
rc=$?
first="$(printf '%s\n' "$out" | head -n 1)"
second="$(printf '%s\n' "$out" | sed -n '2p')"
if [ "$rc" -eq 1 ] && [ "$first" = "SOLEUR_REVIEW_SCAN_GATE refuse engine=shellcheck files=1 rules=0 findings=0 scanned=0 unscannable=1" ] && [ "$second" = "$arm/work/a.sh:0 unscannable-shellcheck-binary-missing" ]; then
  ok "shell-only without shellcheck refuses"
else
  no "shell-only without shellcheck refuses (rc=$rc line=$first second=$second)"
fi

# --- shellcheck executed receipts ok rules=0 ---
arm="$(new_arm)"
DIRS+=("$arm")
write_shellcheck "$arm"
write_timeout "$arm"
printf 'echo hi\n' >"$arm/work/a.sh"
out="$(run_gate "$arm" "$arm/work/a.sh")"
rc=$?
first="$(printf '%s\n' "$out" | head -n 1)"
if [ "$rc" -eq 0 ] && [ "$first" = "SOLEUR_REVIEW_SCAN_GATE ok engine=shellcheck files=1 rules=0 findings=0 scanned=1 unscannable=0" ] && grep -q "$arm/work/a.sh" "$arm/shellcheck.args"; then
  ok "shellcheck argv includes the shell target"
else
  no "shellcheck argv includes the shell target (rc=$rc line=$first)"
fi

# --- per-file invocation: two shell files, one invocation each, in order, under the timeout envelope ---
arm="$(new_arm)"
DIRS+=("$arm")
write_shellcheck "$arm"
write_timeout "$arm"
printf 'echo a\n' >"$arm/work/a.sh"
printf 'echo b\n' >"$arm/work/b.sh"
out="$(run_gate "$arm" "$arm/work/a.sh" "$arm/work/b.sh")"
rc=$?
first="$(printf '%s\n' "$out" | head -n 1)"
invocations="$(grep -c . "$arm/shellcheck.args" 2>/dev/null || true)"
line1="$(sed -n '1p' "$arm/shellcheck.args" 2>/dev/null)"
line2="$(sed -n '2p' "$arm/shellcheck.args" 2>/dev/null)"
if [ "$rc" -eq 0 ] && [ "$first" = "SOLEUR_REVIEW_SCAN_GATE ok engine=shellcheck files=2 rules=0 findings=0 scanned=2 unscannable=0" ] \
  && [ "$invocations" -eq 2 ] \
  && [ "$line1" = "-f json -- $arm/work/a.sh" ] && [ "$line2" = "-f json -- $arm/work/b.sh" ] \
  && grep -q -- '-k 5s 30s shellcheck' "$arm/timeout.args" \
  && [ "$(grep -c . "$arm/timeout.args")" -eq 2 ]; then
  ok "per-file invocation order, one bounded invocation each"
else
  no "per-file invocation order, one bounded invocation each (rc=$rc line=$first invocations=$invocations l1=$line1 l2=$line2 timeout=$(cat "$arm/timeout.args" 2>/dev/null | tr '\n' '|'))"
fi

# --- findings aggregate across two files in input order ---
arm="$(new_arm)"
DIRS+=("$arm")
write_shellcheck "$arm" finding-b
write_timeout "$arm"
printf 'echo a\n' >"$arm/work/a.sh"
printf 'echo b\n' >"$arm/work/b.sh"
out="$(run_gate "$arm" "$arm/work/a.sh" "$arm/work/b.sh")"
rc=$?
first="$(printf '%s\n' "$out" | head -n 1)"
second="$(printf '%s\n' "$out" | sed -n '2p')"
if [ "$rc" -eq 0 ] && [ "$first" = "SOLEUR_REVIEW_SCAN_GATE ok engine=shellcheck files=2 rules=0 findings=1 scanned=2 unscannable=0" ] && [ "$second" = "$arm/work/b.sh:4 SC2086" ]; then
  ok "a finding in the second file survives per-file aggregation"
else
  no "a finding in the second file survives per-file aggregation (rc=$rc first=$first second=$second)"
fi

# --- hanging shellcheck is a bounded unscannable-timeout refusal, not a wedge ---
arm="$(new_arm)"
DIRS+=("$arm")
write_shellcheck "$arm" hang
write_timeout "$arm"
printf 'echo hi\n' >"$arm/work/a.sh"
out="$(run_gate "$arm" "$arm/work/a.sh")"
rc=$?
first="$(printf '%s\n' "$out" | head -n 1)"
second="$(printf '%s\n' "$out" | sed -n '2p')"
if [ "$rc" -eq 1 ] && [ "$first" = "SOLEUR_REVIEW_SCAN_GATE refuse engine=shellcheck files=1 rules=0 findings=0 scanned=0 unscannable=1" ] && [ "$second" = "$arm/work/a.sh:0 unscannable-timeout" ]; then
  ok "a hanging shellcheck refuses as unscannable-timeout"
else
  no "a hanging shellcheck refuses as unscannable-timeout (rc=$rc first=$first second=$second)"
fi

# --- no timeout binary on PATH refuses before scanning ---
arm="$(new_arm)"
DIRS+=("$arm")
write_shellcheck "$arm"
printf 'echo hi\n' >"$arm/work/a.sh"
out="$(run_gate "$arm" "$arm/work/a.sh")"
rc=$?
first="$(printf '%s\n' "$out" | head -n 1)"
second="$(printf '%s\n' "$out" | sed -n '2p')"
if [ "$rc" -eq 1 ] && [ "$first" = "SOLEUR_REVIEW_SCAN_GATE refuse engine=shellcheck files=1 rules=0 findings=0 scanned=0 unscannable=1" ] && [ "$second" = "$arm/work/a.sh:0 unscannable-timeout-binary-missing" ]; then
  ok "missing timeout binary refuses as unscannable-timeout-binary-missing"
else
  no "missing timeout binary refuses as unscannable-timeout-binary-missing (rc=$rc first=$first second=$second)"
fi
if [ -s "$arm/shellcheck.args" ]; then
  no "a missing timeout binary must not invoke shellcheck unbounded"
else
  ok "a missing timeout binary must not invoke shellcheck unbounded"
fi

# --- gtimeout fallback when timeout is absent ---
arm="$(new_arm)"
DIRS+=("$arm")
write_shellcheck "$arm"
write_timeout "$arm" gtimeout
printf 'echo hi\n' >"$arm/work/a.sh"
out="$(run_gate "$arm" "$arm/work/a.sh")"
rc=$?
first="$(printf '%s\n' "$out" | head -n 1)"
if [ "$rc" -eq 0 ] && [ "$first" = "SOLEUR_REVIEW_SCAN_GATE ok engine=shellcheck files=1 rules=0 findings=0 scanned=1 unscannable=0" ] && grep -q 'shellcheck' "$arm/timeout.args"; then
  ok "gtimeout is the fallback timeout binary"
else
  no "gtimeout is the fallback timeout binary (rc=$rc first=$first)"
fi

# --- malformed scanner JSON refuses rather than reading as zero findings ---
arm="$(new_arm)"
DIRS+=("$arm")
write_shellcheck "$arm" malformed
write_timeout "$arm"
printf 'echo hi\n' >"$arm/work/a.sh"
out="$(run_gate "$arm" "$arm/work/a.sh")"
rc=$?
first="$(printf '%s\n' "$out" | head -n 1)"
second="$(printf '%s\n' "$out" | sed -n '2p')"
if [ "$rc" -eq 1 ] && [ "$first" = "SOLEUR_REVIEW_SCAN_GATE refuse engine=shellcheck files=1 rules=0 findings=0 scanned=0 unscannable=1" ] && [ "$second" = "$arm/work/a.sh:0 unscannable-malformed-json" ]; then
  ok "malformed scanner output refuses as unscannable-malformed-json"
else
  no "malformed scanner output refuses as unscannable-malformed-json (rc=$rc first=$first second=$second)"
fi

# --- empty scanner output is malformed, not zero findings ---
arm="$(new_arm)"
DIRS+=("$arm")
write_shellcheck "$arm" emptyout
write_timeout "$arm"
printf 'echo hi\n' >"$arm/work/a.sh"
out="$(run_gate "$arm" "$arm/work/a.sh")"
rc=$?
first="$(printf '%s\n' "$out" | head -n 1)"
if [ "$rc" -eq 1 ] && grep -q 'unscannable-malformed-json' <<<"$out"; then
  ok "empty scanner output refuses as unscannable-malformed-json"
else
  no "empty scanner output refuses as unscannable-malformed-json (rc=$rc first=$first)"
fi

# --- unexpected scanner status refuses as unscannable-scanner-status ---
arm="$(new_arm)"
DIRS+=("$arm")
write_shellcheck "$arm" exit3
write_timeout "$arm"
printf 'echo hi\n' >"$arm/work/a.sh"
out="$(run_gate "$arm" "$arm/work/a.sh")"
rc=$?
first="$(printf '%s\n' "$out" | head -n 1)"
second="$(printf '%s\n' "$out" | sed -n '2p')"
if [ "$rc" -eq 1 ] && [ "$first" = "SOLEUR_REVIEW_SCAN_GATE refuse engine=shellcheck files=1 rules=0 findings=0 scanned=0 unscannable=1" ] && [ "$second" = "$arm/work/a.sh:0 unscannable-scanner-status" ]; then
  ok "an unexpected scanner status refuses as unscannable-scanner-status"
else
  no "an unexpected scanner status refuses as unscannable-scanner-status (rc=$rc first=$first second=$second)"
fi

# --- ok is impossible when any input is unscannable even if another scanned clean ---
arm="$(new_arm)"
DIRS+=("$arm")
cat >"$arm/bin/shellcheck" <<EOF
#!/bin/sh
printf '%s\\n' "\$*" >>"$arm/shellcheck.args"
last=""
for a in "\$@"; do last="\$a"; done
case "\$last" in
  *b.sh*) printf 'not json\\n'; exit 0 ;;
  *) printf '[{"file":"%s","line":2,"endLine":2,"column":1,"endColumn":3,"level":"warning","code":2086,"message":"Double quote."}]\\n' "\$last"; exit 1 ;;
esac
EOF
chmod +x "$arm/bin/shellcheck"
write_timeout "$arm"
printf 'echo a\n' >"$arm/work/a.sh"
printf 'echo b\n' >"$arm/work/b.sh"
out="$(run_gate "$arm" "$arm/work/a.sh" "$arm/work/b.sh")"
rc=$?
first="$(printf '%s\n' "$out" | head -n 1)"
second="$(printf '%s\n' "$out" | sed -n '2p')"
third="$(printf '%s\n' "$out" | sed -n '3p')"
if [ "$rc" -eq 1 ] && [ "$first" = "SOLEUR_REVIEW_SCAN_GATE refuse engine=shellcheck files=2 rules=0 findings=1 scanned=1 unscannable=1" ] && [ "$second" = "$arm/work/b.sh:0 unscannable-malformed-json" ] && [ "$third" = "$arm/work/a.sh:2 SC2086" ]; then
  ok "one completed scan cannot ok while another input is unscannable"
else
  no "one completed scan cannot ok while another input is unscannable (rc=$rc first=$first second=$second third=$third)"
fi

# --- leading-dash filename still scans because of the -- separator ---
arm="$(new_arm)"
DIRS+=("$arm")
write_shellcheck "$arm"
write_timeout "$arm"
printf 'echo hi\n' >"$arm/work/-x.sh"
out="$(cd "$arm/work" && run_gate "$arm" "-x.sh")"
rc=$?
first="$(printf '%s\n' "$out" | head -n 1)"
if [ "$rc" -eq 0 ] && [ "$first" = "SOLEUR_REVIEW_SCAN_GATE ok engine=shellcheck files=1 rules=0 findings=0 scanned=1 unscannable=0" ] && grep -q -- '-- -x.sh' "$arm/shellcheck.args"; then
  ok "a leading-dash filename is scanned behind the -- separator"
else
  no "a leading-dash filename is scanned behind the -- separator (rc=$rc first=$first args=$(cat "$arm/shellcheck.args" 2>/dev/null))"
fi

# --- no byte-size prefilter: a >512KiB shell input is still attempted ---
arm="$(new_arm)"
DIRS+=("$arm")
write_shellcheck "$arm"
write_timeout "$arm"
python3 -c '
with open("'"$arm"'/work/big.sh", "w") as fh:
    fh.write("#!/bin/sh\necho hi\n")
    pad = "#" * 1000 + "\n"
    while fh.tell() < 600000:
        fh.write(pad)
'
out="$(run_gate "$arm" "$arm/work/big.sh")"
rc=$?
first="$(printf '%s\n' "$out" | head -n 1)"
if [ "$rc" -eq 0 ] && [ "$first" = "SOLEUR_REVIEW_SCAN_GATE ok engine=shellcheck files=1 rules=0 findings=0 scanned=1 unscannable=0" ] && grep -q 'big.sh' "$arm/shellcheck.args"; then
  ok "a 600KB shell input is scanned (no byte-size prefilter)"
else
  no "a 600KB shell input is scanned (no byte-size prefilter) (rc=$rc first=$first)"
fi

# --- mixed without shellcheck refuses ---
arm="$(new_arm)"
DIRS+=("$arm")
write_semgrep "$arm" plural
printf 'export const a = 1;\n' >"$arm/work/a.ts"
printf 'echo hi\n' >"$arm/work/a.sh"
out="$(run_gate "$arm" "$arm/work/a.ts" "$arm/work/a.sh")"
rc=$?
first="$(printf '%s\n' "$out" | head -n 1)"
second="$(printf '%s\n' "$out" | sed -n '2p')"
if [ "$rc" -eq 1 ] && [ "$first" = "SOLEUR_REVIEW_SCAN_GATE refuse engine=mixed files=2 rules=2 findings=0 scanned=0 unscannable=1" ] && [ "$second" = "$arm/work/a.sh:0 unscannable-shellcheck-binary-missing" ]; then
  ok "mixed range without shellcheck refuses"
else
  no "mixed range without shellcheck refuses (rc=$rc line=$first second=$second)"
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
phrase='classified source-and-shell count'
if grep -q "$phrase" "$SKILL" && grep -q "$phrase" "$sentinel" && grep -q "$phrase" "$canon"; then
  ok "zero-finding claim names the classified count"
else
  no "zero-finding claim names the classified count"
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
