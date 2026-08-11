#!/usr/bin/env bash
#
# (#7264, ADR-152) The render-strip contract for the git-data CLOUD-INIT TEMPLATE.
#
# WHY THIS SUITE EXISTS, and why it is separate from git-data-render-strip-parity.test.sh.
# That suite proves the two hand-mirrored copies of each strip EXPRESSION agree. This one
# proves the expression applied to the TEMPLATE does the right thing to the DOCUMENT — a
# different question, and the one whose failure mode is a dark host.
#
# ADR-152 already names the hazard: the payload expression preserves `#!` and nothing else,
# which is correct for the nine injected scripts and WRONG for a cloud-init body, because
# `#cloud-config` is a directive that is a comment by syntax. Deleting it does not fail
# loudly — the apply succeeds, the host boots, and cloud-init never recognises the payload,
# so none of it runs. That is ADR-149's dark-host indistinguishability, reached through the
# mechanism ADR-152 introduced.
#
# THE THREE ARMS ADR-152 PRESCRIBES are 1, 2 and 3 below: the first line survives, every
# shebang survives, and the strip is not a no-op (a strip matching nothing satisfies both
# preservation checks while delivering none of the saving).
#
# ARM 4 IS THE ONE SHAPE-COMPARISON CANNOT DO. Top-level keys and runcmd/write_files entry
# COUNTS are invariant under arbitrary corruption INSIDE a write_files content string or the
# LUKSEOF heredoc body, so a "structure is identical" check passes over a deleted data line.
# Arm 4 asserts the actual invariant per entry: stripped and unstripped differ ONLY by lines
# the strip expression matches.
#
# ARM 5 PINS AN INVARIANT THAT IS CURRENTLY TRUE BY ACCIDENT. The strip runs over the
# RENDERED output, so it sees interpolated values too. Nine interpolation sites sit at the
# start of a line (`      ${indent(6, git_data_bootstrap)}` and its eight siblings), and six
# of those payloads begin with `#!/usr/bin/env bash`. They survive only because `!` is not
# `[ \t]`. Nothing else asserts that, and the day a payload's first surviving line becomes a
# `# ` comment — or a new line-leading interpolation carries one — the strip silently eats
# host content. Arm 5 makes that a CI failure instead of a boot failure.
#
# COVERAGE BOUNDARY, stated because it is not what it looks like. This suite renders through
# git-data-userdata-budget.sh, which carries its OWN hand-mirrored copy of the expression —
# so mutating only modules/git-data-userdata/main.tf does not change what these arms see.
# Measured: collapsing the template expression in main.tf alone leaves this suite 5/0 green.
# Coupling the two copies is git-data-render-strip-parity.test.sh's job, and it reds on that
# mutation. Both suites are required; neither is sufficient. Arms 4 and 5 read the expression
# from main.tf while the render comes from the budget script, which is safe only because
# parity forces them equal — if that suite is ever removed, these arms silently compare a
# render against an expression that did not produce it.
#
# Registered as a step in .github/workflows/infra-validation.yml.
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF="$DIR/modules/git-data-userdata/main.tf"
TPL="$DIR/cloud-init-git-data.yml"

passes=0
fails=0
pass() { passes=$((passes + 1)); printf '  ok   %s\n' "$1"; }
fail() { fails=$((fails + 1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '       %s\n' "$2"; }

printf '\n=== git-data-template-strip ===\n\n'

command -v terraform >/dev/null 2>&1 || {
  printf '  SKIP terraform not on PATH\n\n=== git-data-template-strip: skipped ===\n\n'
  exit 0
}

TMP=$(mktemp -d -t gdtplstrip.XXXXXXXX) || { echo "  FAIL mktemp"; exit 1; }
trap 'rm -rf "$TMP"' EXIT

# Both artifacts come from the ONE render harness. Re-implementing the strip here would be
# the restatement ADR-152's registry precedent records as the defect that produced a phantom
# cap breach — a second implementation that can disagree with production silently.
if ! bash "$DIR/git-data-userdata-budget.sh" "$TMP/stripped.yml" "$TMP/raw.yml" >"$TMP/budget.out" 2>&1; then
  fail "render harness produced both artifacts" "$(tail -3 "$TMP/budget.out" | tr '\n' ' ')"
  printf '\n=== git-data-template-strip: %s passed, %s failed ===\n\n' "$passes" "$fails"
  exit 1
fi

# ── 1. The stripped render still begins with #cloud-config ─────────────────────────────
first_line=$(head -1 "$TMP/stripped.yml")
if [[ "$first_line" == "#cloud-config" ]]; then
  pass "stripped render begins with '#cloud-config'"
else
  fail "stripped render begins with '${first_line}', not '#cloud-config'" \
    "cloud-init would not recognise the payload; the host would boot dark (ADR-149)"
fi

# ── 2. Every shebang in the raw render survives the strip ──────────────────────────────
# Counted, not merely existence-checked: three of the nine payloads are invoked through
# authorized_keys command="...", where a lost `#!` does NOT raise ENOEXEC — the kernel falls
# back to sh, which is dash on 24.04. Silent bash/dash divergence on a fail-closed host.
raw_shebangs=$(grep -cE '^[[:space:]]*#!' "$TMP/raw.yml" || true)
str_shebangs=$(grep -cE '^[[:space:]]*#!' "$TMP/stripped.yml" || true)
if [[ "$raw_shebangs" -gt 0 && "$raw_shebangs" -eq "$str_shebangs" ]]; then
  pass "all ${raw_shebangs} shebangs survive the strip"
else
  fail "shebang count changed across the strip: raw=${raw_shebangs} stripped=${str_shebangs}" \
    "a lost '#!' falls back to dash for the authorized_keys command= payloads"
fi

# ── 3. The strip is not a no-op (ADR-152's third verification arm) ─────────────────────
raw_bytes=$(wc -c < "$TMP/raw.yml")
str_bytes=$(wc -c < "$TMP/stripped.yml")
if [[ "$str_bytes" -lt "$raw_bytes" ]]; then
  pass "strip removed content (raw ${raw_bytes} B -> stripped ${str_bytes} B)"
else
  fail "strip removed nothing (raw ${raw_bytes} B -> stripped ${str_bytes} B)" \
    "a strip that matches nothing satisfies arms 1 and 2 while delivering no saving"
fi

# ── 4. Per-entry: stripped differs from raw ONLY by strip-matching lines ───────────────
python3 - "$TMP/raw.yml" "$TMP/stripped.yml" "$TF" >"$TMP/arm4.out" 2>&1 <<'PY'
import re, sys, yaml

raw_p, str_p, tf_p = sys.argv[1], sys.argv[2], sys.argv[3]

# Read the expression FROM main.tf rather than restating it. Anchored at line start so a
# comment naming an old form cannot shadow the live assignment (the B1 defect, #7264).
tf = open(tf_p).read()
m = re.search(r'^\s*git_data_template_rationale_strip\s*=\s*"([^"]*)"', tf, re.M)
if not m:
    sys.exit("no git_data_template_rationale_strip in main.tf — cannot mirror the render strip")
expr = m.group(1)
if not (expr.startswith("/") and expr.endswith("/")):
    sys.exit(f"template strip is not a slash-delimited terraform regex literal: {expr!r}")
LINE = re.compile(expr[1:-1].replace("\\t", "\t").replace("\\n", "\n"))

def strip_lines(s):
    """Apply the strip the way terraform's replace() does: over the whole string."""
    return LINE.sub("", s)

raw, stp = yaml.safe_load(open(raw_p)), yaml.safe_load(open(str_p))
if sorted(raw.keys()) != sorted(stp.keys()):
    sys.exit(f"top-level keys diverged: {sorted(raw.keys())} vs {sorted(stp.keys())}")

checked = 0
for key in ("runcmd", "bootcmd"):
    a, b = raw.get(key) or [], stp.get(key) or []
    if len(a) != len(b):
        sys.exit(f"{key}: entry count changed {len(a)} -> {len(b)}")
    for i, (x, y) in enumerate(zip(a, b)):
        if not isinstance(x, str):
            continue
        want = strip_lines(x)
        if y != want:
            sys.exit(f"{key}[{i}]: stripped content differs by more than strip-matching lines")
        checked += 1

a, b = raw.get("write_files") or [], stp.get("write_files") or []
if len(a) != len(b):
    sys.exit(f"write_files: entry count changed {len(a)} -> {len(b)}")
for i, (x, y) in enumerate(zip(a, b)):
    xc, yc = x.get("content"), y.get("content")
    if not isinstance(xc, str):
        continue
    if x.get("path") != y.get("path"):
        sys.exit(f"write_files[{i}]: path changed {x.get('path')} -> {y.get('path')}")
    if yc != strip_lines(xc):
        sys.exit(f"write_files[{i}] ({x.get('path')}): stripped content differs by more than "
                 "strip-matching lines — a data line inside the body was altered")
    checked += 1

if checked < 10:
    sys.exit(f"only {checked} entries compared (floor 10) — the corpus collapsed, so this arm is vacuous")
print(f"per-entry byte diff: {checked} entries differ ONLY by strip-matching lines")
PY
arm4_rc=$?
if [[ "$arm4_rc" -eq 0 ]]; then
  pass "$(cat "$TMP/arm4.out")"
else
  fail "per-entry byte diff: stripped content differs by more than strip-matching lines" \
    "$(cat "$TMP/arm4.out")"
fi

# ── 5. No interpolated value can be reached by the strip's line-start anchor ───────────
python3 - "$TPL" "$DIR" "$TF" >"$TMP/arm5.out" 2>&1 <<'PY'
import os, re, sys

tpl_p, infra_dir, tf_p = sys.argv[1], sys.argv[2], sys.argv[3]
tf = open(tf_p).read()

def literal(name):
    m = re.search(r'^\s*' + name + r'\s*=\s*"([^"]*)"', tf, re.M)
    if not m:
        sys.exit(f"no {name} in main.tf")
    e = m.group(1)
    if not (e.startswith("/") and e.endswith("/")):
        sys.exit(f"{name} is not a slash-delimited terraform regex literal: {e!r}")
    return re.compile(e[1:-1].replace("\\t", "\t").replace("\\n", "\n"))

TEMPLATE_STRIP = literal("git_data_template_rationale_strip")
PAYLOAD_STRIP = literal("git_data_rationale_strip")

# The roster: var -> source file, read from the render module's file() bindings so this arm
# cannot drift from what is actually interpolated.
bindings = dict(re.findall(
    r'^\s*([a-z_]+)\s*=\s*(?:replace\()?file\("\$\{path\.module\}/([^"]+)"\)', tf, re.M))
if len(bindings) < 9:
    sys.exit(f"only {len(bindings)} file() bindings found (floor 9) — roster extraction drifted")

lines = open(tpl_p).read().split("\n")
line_leading = []   # (lineno, varnames) for interpolations at the start of a line
for i, ln in enumerate(lines, 1):
    if re.match(r'^[ \t]*\$\{', ln):
        line_leading.append((i, re.findall(r'\b([a-z_]+)\b', ln)))

if not line_leading:
    sys.exit("no line-leading interpolation sites found — the template shape changed and "
             "this arm no longer tests what it was written for")

problems = []
for lineno, names in line_leading:
    hit = [n for n in names if n in bindings]
    if not hit:
        problems.append(f"line {lineno}: line-leading interpolation references no known "
                        f"file() payload ({names}); its value is unaudited and could begin "
                        "with a '# ' line the strip would eat")
        continue
    for var in hit:
        # Bindings are written `${path.module}/../../<name>`, i.e. relative to the MODULE
        # dir — resolving them against the infra dir lands two levels too high and every
        # payload "does not exist", which would turn this arm into a self-satisfying error.
        src = os.path.normpath(os.path.join(
            infra_dir, "modules", "git-data-userdata", bindings[var]))
        if not os.path.exists(src):
            problems.append(f"line {lineno}: payload {bindings[var]} not found")
            continue
        # What actually reaches the render: the payload AFTER its own strip.
        delivered = PAYLOAD_STRIP.sub("", open(src).read())
        eaten = [l for l in delivered.split("\n") if TEMPLATE_STRIP.fullmatch(l + "\n")]
        if eaten:
            problems.append(
                f"line {lineno}: payload {bindings[var]} delivers {len(eaten)} line(s) the "
                f"TEMPLATE strip would delete, e.g. {eaten[0]!r}")

if problems:
    sys.exit("\n       ".join(problems))

print(f"{len(line_leading)} line-leading interpolation sites: every delivered payload line "
      "survives the template strip (shebangs are preserved because '!' is not [ \\t])")
PY
arm5_rc=$?
if [[ "$arm5_rc" -eq 0 ]]; then
  pass "$(cat "$TMP/arm5.out")"
else
  fail "an interpolated value is reachable by the template strip's '^[ \\t]*#' anchor" \
    "$(cat "$TMP/arm5.out")"
fi

_ran=$((passes + fails))
if [[ "$_ran" -lt 5 ]]; then
  fails=$((fails + 1))
  printf '  FAIL ANTI-VACUITY: only %s assertions ran, floor is 5.\n' "$_ran"
else
  printf '  ok   anti-vacuity floor: %s assertions ran (floor 5)\n' "$_ran"
fi

printf '\n=== git-data-template-strip: %s passed, %s failed ===\n\n' "$passes" "$fails"
[[ "$fails" -eq 0 ]] || exit 1
exit 0
