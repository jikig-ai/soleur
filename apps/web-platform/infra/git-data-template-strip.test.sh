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
# ARM 4, AND WHAT IT DOES *NOT* PROVE. It compares per entry rather than per document, so a
# re-indented block scalar or a Go-RE2-vs-Python divergence reds here where a shape check
# (top-level keys, entry counts) would pass. Its second floor is the load-bearing one: 20 of
# 27 entries are byte-identical raw-vs-stripped, so an entry-count floor alone is satisfiable
# entirely by entries the strip never touched.
#
# It does NOT prove a removed line was a comment rather than DATA. It asserts
# `stripped == B(raw)` — the identity terraform just computed — so a `# `-shaped line that is
# CONTENT (a heredoc writing a file whose body happens to contain one) is removed on both
# sides and compares equal. Measured: adding such a line to a heredoc that writes
# /etc/git-data-banner makes the host write 2 lines instead of 3, and this arm stays green.
# No line of that shape exists in the corpus today; the residual is recorded rather than
# claimed closed.
#
# ARM 5 PINS AN INVARIANT THAT IS CURRENTLY TRUE BY ACCIDENT. The strip runs over the
# RENDERED output, so it sees interpolated values too. Nine interpolation sites sit at the
# start of a line (`      ${indent(6, git_data_bootstrap)}` and its eight siblings), and six
# of those payloads begin with `#!/usr/bin/env bash`. They survive only because `!` is not
# `[ \t]`. Nothing else asserts that, and the day a payload's first surviving line becomes a
# `# ` comment — or a new line-leading interpolation carries one — the strip silently eats
# host content. Arm 5 makes that a CI failure instead of a boot failure.
#
# ITS HEADLINE CHECK IS A TAUTOLOGY UNDER TODAY'S PAIR, and that is worth stating so the arm
# is not over-trusted: TEMPLATE matches `#` + `([ \t]…)?` and PAYLOAD matches `#` +
# `([^!\n]…)?`, and `[ \t] ⊂ [^!\n]`, so TEMPLATE ⊆ PAYLOAD and a post-payload-strip line
# can never match TEMPLATE. It therefore fires on a PAYLOAD-strip change (measured) and can
# never fire on a TEMPLATE-strip change. Its live residue is the "references no known file()
# payload" branch and the ≥9-bindings floor, which catch a NEW line-leading interpolation
# that is not a known payload — the case the arm was actually written for.
#
# COVERAGE BOUNDARY, stated because it is not what it looks like. This suite renders through
# git-data-userdata-budget.sh, which carries its OWN hand-mirrored copy of the expression —
# so mutating only modules/git-data-userdata/main.tf does not change what these arms see.
# Measured: COLLAPSING the template expression in main.tf alone leaves this suite 5/0 green.
# The reason is narrower than "these arms read a different file than the render came from" —
# arm 4 DOES red on a main.tf-only change that alters the match set (verified against the
# one-character narrowing). It survives the collapse specifically because inside runcmd and
# write_files entries the payload and template forms disagree about nothing: those bodies are
# already comment-free by the time the template strip sees them. Coupling the two copies is
# git-data-render-strip-parity.test.sh's job. Both suites are required; neither is sufficient.
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

# The independent case counter (ADR-193 #2). Incremented at each CALL SITE, immediately before
# the block that decides a verdict — never inside pass()/fail(). The floor previously read
# `_ran=$((passes + fails))`, a total DERIVED from the verdicts: it moved WITH the verdict, so
# stubbing fail() dropped the row and its count together and the floor was satisfied under the
# exact fault it exists to catch. This counter does not move when a verdict helper is neutered,
# which is what makes the conservation check below non-tautological. Never increment it inside
# `$( )` — a subshell discards it and the code still reads as correct.
CASES=0

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
  CASES=$((CASES + 1))
  fail "render harness produced both artifacts" "$(tail -3 "$TMP/budget.out" | tr '\n' ' ')"
  printf '\n=== git-data-template-strip: %s passed, %s failed ===\n\n' "$passes" "$fails"
  exit 1
fi

# ── 1. The stripped render still begins with #cloud-config ─────────────────────────────
first_line=$(head -1 "$TMP/stripped.yml")
CASES=$((CASES + 1))
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
CASES=$((CASES + 1))
if [[ "$raw_shebangs" -gt 0 && "$raw_shebangs" -eq "$str_shebangs" ]]; then
  pass "all ${raw_shebangs} shebangs survive the strip"
else
  fail "shebang count changed across the strip: raw=${raw_shebangs} stripped=${str_shebangs}" \
    "a lost '#!' falls back to dash for the authorized_keys command= payloads"
fi

# ── 3. The strip delivers a REAL saving, not merely a non-zero one ─────────────────────
#
# ADR-152's third arm is "assert the strip is not a no-op". A `> 0 bytes` reading of that is
# too weak to be worth having, and this suite shipped it that way: deleting ONE character
# from the expression's character class (`#([ \t]…)` -> `#([\t]…)`, dropping the space, in
# both mirrored copies) collapses the saving from 30,524 B to 68 B — 99.8% lost — and every
# arm here, the parity suite, the budget script and the schema validator all stay GREEN. The
# old arm even PRINTED the evidence and passed: `raw 67479 B -> stripped 67411 B`.
#
# The cap cannot backstop it either: the fully UNSTRIPPED render base64gzips to 30,092 B,
# under the 32,768 B cap, so a total strip failure does not breach the budget.
#
# BOUNDED, NOT PINNED. A pin to today's 30,524 B would red on every comment edit — the
# opposite of useful. The bound is a ratio with real headroom: today's stripped render is
# 54.5% of raw; the one-character narrowing is 99.9%. 60% separates them with room for the
# template's rationale to grow or shrink normally.
raw_bytes=$(wc -c < "$TMP/raw.yml")
str_bytes=$(wc -c < "$TMP/stripped.yml")
max_ratio=60
str_pct=$(( str_bytes * 100 / raw_bytes ))
CASES=$((CASES + 1))
if [[ "$str_bytes" -ge "$raw_bytes" ]]; then
  fail "strip removed nothing (raw ${raw_bytes} B -> stripped ${str_bytes} B)" \
    "a strip that matches nothing satisfies arms 1 and 2 while delivering no saving"
elif [[ "$str_pct" -gt "$max_ratio" ]]; then
  fail "strip delivered only ${str_pct}% reduction (raw ${raw_bytes} B -> stripped ${str_bytes} B)" \
    "expected the stripped render at or under ${max_ratio}% of raw. A near-total loss of the saving is what a one-character narrowing of the character class produces, and it is otherwise SILENT — the cap does not catch it (the unstripped render is under cap)."
else
  pass "strip delivers a real saving: ${str_pct}% of raw (raw ${raw_bytes} B -> stripped ${str_bytes} B, bound ${max_ratio}%)"
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
differing = 0
for key in ("runcmd", "bootcmd"):
    a, b = raw.get(key) or [], stp.get(key) or []
    if len(a) != len(b):
        sys.exit(f"{key}: entry count changed {len(a)} -> {len(b)}")
    for i, (x, y) in enumerate(zip(a, b)):
        if not isinstance(x, str):
            continue
        want = strip_lines(x)
        if y != want:
            sys.exit(f"{key}[{i}]: terraform replace() and this arm's re.sub disagree")
        checked += 1
        if y != x:
            differing += 1

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
        sys.exit(f"write_files[{i}] ({x.get('path')}): terraform replace() and this arm's "
                 "re.sub disagree, or the block scalar was re-indented")
    checked += 1
    if yc != xc:
        differing += 1

# TWO FLOORS, AND THE SECOND IS THE LOAD-BEARING ONE. `checked` counts entries COMPARED; on
# today's corpus 20 of 27 are byte-identical raw-vs-stripped (the strip touches nothing in
# them), so a `checked >= 10` floor was satisfiable ENTIRELY by entries the strip never
# altered -- vacuous in exactly the direction that matters. `differing` counts the entries
# the strip actually changed, which is the population this arm exists to check.
if checked < 20:
    sys.exit(f"only {checked} entries compared (floor 20) -- the corpus collapsed, so this arm is vacuous")
if differing < 5:
    sys.exit(f"only {differing} entries actually differ raw-vs-stripped (floor 5) -- this arm "
             "compared a corpus the strip never touched, which passes without testing anything")
print(f"per-entry: {checked} compared, {differing} actually stripped, each differing only by "
      "strip-matching lines")
PY
arm4_rc=$?
CASES=$((CASES + 1))
if [[ "$arm4_rc" -eq 0 ]]; then
  pass "$(cat "$TMP/arm4.out")"
else
  fail "per-entry: the strip touched something it should not have, or barely stripped at all" \
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
CASES=$((CASES + 1))
if [[ "$arm5_rc" -eq 0 ]]; then
  pass "$(cat "$TMP/arm5.out")"
else
  fail "an interpolated value is reachable by the template strip's '^[ \\t]*#' anchor" \
    "$(cat "$TMP/arm5.out")"
fi

# ── Accounting conservation (ADR-193 #3) ───────────────────────────────────────────────
#
# Ordered BEFORE the floor per ADR-193 #4: a neutered fail() deflates the recorded verdicts, so
# the floor would ALSO trip and would report "arms were deleted" — the misleading diagnosis.
# This says "a verdict was discarded" instead. Reported with printf >&2 + exit 1 DIRECTLY,
# never through fail(): a check that reports by calling the verdict helper increments the very
# counter the exit status reads, so neutering fail() silences the rows AND the check meant to
# notice the silence. The literal `[FATAL] accounting` is load-bearing — guard-vacuity-floor's
# ARM 10 builds its conservation population by grepping that exact string (#7588).
if [[ $((passes + fails)) -ne "$CASES" ]]; then
  printf '\n[FATAL] accounting: passes+fails (%d) != CASES (%d).\n' \
    "$((passes + fails))" "$CASES" >&2
  if [[ $((passes + fails)) -lt "$CASES" ]]; then
    printf '  An assertion was counted but its verdict was not recorded — that is what a neutered pass()/fail() looks like.\n' >&2
  else
    printf '  A verdict was recorded at a call site with no `CASES=$((CASES + 1))` before it. This is a harness bug, not a product failure: add the increment at that call site.\n' >&2
  fi
  printf '\n=== git-data-template-strip: %s passed, %s failed ===\n\n' "$passes" "$fails"
  exit 1
fi

# ── Anti-vacuity floor (ADR-193 #1) ────────────────────────────────────────────────────
#
# Reads the INDEPENDENT case counter, and reports with printf >&2 + exit 1 DIRECTLY. It
# previously read `_ran=$((passes + fails))` and reported by doing `fails=$((fails + 1))` and
# falling through — so with the assertion machinery neutered the floor "fired" into a counter
# nobody read before exit, the suite printed a clean total and exited 0. A floor enforced
# through the suspect cannot witness the suspect.
#
# Zero headroom against the current count, so any deletion is loud. Ratchet when adding arms,
# and read a floor failure on an otherwise-green run as "you added arms, update this number".
if [[ "$CASES" -lt 5 ]]; then
  printf '\n[FATAL] anti-vacuity floor: only %d assertion(s) ran, expected >= 5.\n' "$CASES" >&2
  printf '  Arms were deleted or skipped; a green run here would be a coverage loss.\n' >&2
  printf '\n=== git-data-template-strip: %s passed, %s failed ===\n\n' "$passes" "$fails"
  exit 1
fi
printf '  ok   anti-vacuity floor: %s assertions ran (floor 5)\n' "$CASES"

printf '\n=== git-data-template-strip: %s passed, %s failed ===\n\n' "$passes" "$fails"
[[ "$fails" -eq 0 ]] || exit 1
exit 0
