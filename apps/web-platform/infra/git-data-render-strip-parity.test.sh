#!/usr/bin/env bash
#
# (#6982, ADR-152) The render-strip contract for the git-data injected payloads.
#
# WHY THIS SUITE EXISTS. git-data.tf renders nine scripts/units into user_data with whole-line
# `#` comments stripped, so the repo keeps its rationale and Hetzner's hard 32,768 B ForceNew
# cap does not tax it. Two things make that safe rather than clever, and neither is
# self-enforcing:
#
#   1. git-data-userdata-budget.sh carries an INDEPENDENTLY HAND-MIRRORED copy of the same
#      templatefile map, and it is the render harness for git-data-emit.test.sh and
#      git-data-runcmd-rehearsal.test.sh. If the strip expression is changed in one file and
#      not the other, CI renders a DIFFERENT payload than production does — silently, on the
#      gate whose whole job is to be the thing you trust. Nothing else compares them.
#
#      (#7025, R7) THE CANONICAL SIDE MOVED. It was git-data.tf; it is now
#      modules/git-data-userdata/main.tf, which BOTH the production root and the rung-2
#      rehearsal root call. That is why there are still exactly TWO copies and not three:
#      the rehearsal renders through the module rather than duplicating the map. A third
#      copy would have been strictly worse than the second, because the rung-2 evidence
#      hash is over SOURCE FILES — two copies that drift hash IDENTICALLY while rendering
#      differently, so the rehearsal would attest a payload it did not boot and the
#      attestation would verify.
#   2. The strip must never eat a shebang. Three of the nine (`git-data-provision.sh`,
#      `git-data-remove.sh`, `git-data-transport-wrapper.sh`) are invoked through
#      authorized_keys `command="..."`, where a lost `#!` does NOT raise ENOEXEC — the kernel
#      falls back to `sh`, which is dash on 24.04. That is silent bash/dash divergence on a
#      fail-closed host: the same defect class as the gc-unit `. <file>` bug this PR fixes.
#
# Registered as a step in .github/workflows/infra-validation.yml.
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# (#7025, R7) The canonical render lives in the shared module, not git-data.tf. Asserted
# rather than assumed: pointing this suite at a file that no longer carries the map would
# make every arm below vacuous (an empty extraction compared against an empty extraction).
TF="$DIR/modules/git-data-userdata/main.tf"
BUDGET="$DIR/git-data-userdata-budget.sh"

if [[ ! -f "$TF" ]]; then
  printf '\n=== git-data-render-strip-parity ===\n\n  FAIL canonical render module not found at %s\n' "$TF"
  printf '\n=== git-data-render-strip-parity: 0 passed, 1 failed ===\n\n'
  exit 1
fi

passes=0
fails=0
pass() { passes=$((passes + 1)); printf '  ok   %s\n' "$1"; }
fail() { fails=$((fails + 1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '       %s\n' "$2"; }

printf '\n=== git-data-render-strip-parity ===\n\n'

# ── 1. The two hand-mirrored maps must carry a BYTE-IDENTICAL strip expression ─────────
#
# Extracted by shape (`git_data_rationale_strip = <literal>`) rather than by line number, so
# neither file's formatting can silently decouple them.
# COMMENTS STRIPPED FIRST. `grep … | head -1` over an unstripped file will happily pick a
# COMMENT that mentions the assignment — and this repo's house style is dense inline
# rationale, so a line like `# git_data_rationale_strip = "<old form>"` explaining a past
# change is exactly the kind of prose that gets written. Both files would then be compared on
# their comments while their real expressions drifted apart. Latent today (no such comment
# exists); stripped so it stays that way. (cq-assert-anchor-not-bare-token)
extract_strip() { grep -vE '^[[:space:]]*(#|//)' "$1" | grep -oE 'git_data_rationale_strip[[:space:]]*=[[:space:]]*".*"' | head -1 | sed 's/^[^=]*=[[:space:]]*//'; }

tf_strip="$(extract_strip "$TF")"
# The budget script emits its locals block through an UNQUOTED heredoc, so bash halves every
# backslash on the way to the generated main.tf. Compare what terraform will actually see:
# unescape the shell layer before comparing, rather than comparing the two source spellings
# (which legitimately differ) or normalising both to nothing (which would compare no bytes).
budget_raw="$(extract_strip "$BUDGET")"
# Halve the doubled backslashes ONLY. Do NOT run this through `printf '%b'`: that would
# interpret `\t`/`\n` as a real tab and newline, comparing the expression's MEANING instead of
# the bytes terraform receives — and it would report two genuinely different expressions as
# equal the moment one of them spelled a character literally.
budget_strip="${budget_raw//\\\\/\\}"

if [[ -z "$tf_strip" ]]; then
  fail "modules/git-data-userdata/main.tf declares a strip expression" "no git_data_rationale_strip assignment found"
elif [[ -z "$budget_raw" ]]; then
  fail "git-data-userdata-budget.sh mirrors the strip expression" "no git_data_rationale_strip assignment found"
elif [[ "$tf_strip" == "$budget_strip" ]]; then
  pass "strip expression is byte-identical in modules/git-data-userdata/main.tf and git-data-userdata-budget.sh"
else
  fail "strip expression DRIFTED between the two hand-mirrored maps" \
    "module: ${tf_strip} | budget(as terraform sees it): ${budget_strip}"
fi

# ── 2. Downstream-parser invariants (plugins/soleur/test/cloud-init-user-data-size.test.ts) ─
#
# That file finds the templatefile map by counting BRACE DEPTH and parses entries with a
# LINE-BASED regex. A brace inside the strip expression would unbalance the first; wrapping a
# map entry across two physical lines would defeat the second. Both are invisible until that
# suite reds for a reason that looks unrelated.
if [[ "$tf_strip" == *'{'* || "$tf_strip" == *'}'* ]]; then
  fail "strip expression contains no brace" "found a brace in: ${tf_strip}"
else
  pass "strip expression contains no brace (brace-depth map scanner stays balanced)"
fi

n_entries=$(grep -cE '^[[:space:]]+git_data_[a-z_]+[[:space:]]*=[[:space:]]*replace\(file\(' "$TF")
if [[ "$n_entries" -eq 9 ]]; then
  pass "all 9 stripped map entries are each on ONE physical line"
else
  fail "expected 9 single-line stripped map entries in the render module, found ${n_entries}" \
    "a wrapped entry defeats the line-based var parser in cloud-init-user-data-size.test.ts"
fi

# THE SAME COUNT ON THE MIRROR. Arm 1 compares the strip EXPRESSION; nothing checked that the
# budget harness actually APPLIES it to every payload. Measured: removing one `replace()` from
# git-data-userdata-budget.sh alone left this suite 8/8 green while that harness rendered
# git-data-gc.sh UNSTRIPPED (22,920 B vs 20,448 B) — CI measuring and rehearsing a different
# payload than production ships, the exact failure this file's header claims to catch.
n_budget=$(grep -cE '^[[:space:]]+git_data_[a-z_]+[[:space:]]*=[[:space:]]*replace\(file\(' "$BUDGET")
if [[ "$n_budget" -eq "$n_entries" ]]; then
  pass "git-data-userdata-budget.sh applies the strip to the same ${n_entries} payloads"
else
  fail "strip application DRIFTED: the render module wraps ${n_entries}, budget harness wraps ${n_budget}" \
    "CI would measure and rehearse a different payload than production ships"
fi

# ── NO COMMENT DIRECTLY AFTER A LINE CONTINUATION ─────────────────────────────────────
#
# The strip deletes a whole-line comment INCLUDING its newline, so a comment sitting between a
# line ending in `\` and its continuation silently JOINS two commands in the shipped script:
#
#     echo "a" \        renders as   echo "a" \
#     # joined?                       echo "b"
#     echo "b"
#
# Source prints `a` then `b`; rendered prints `a echo b`. `bash -n` is CLEAN on both, so the
# shebang/syntax arm cannot see it, and nothing ever executes the unstripped source — there is
# no second chance. The three units are worse off: CI's `systemd-analyze verify` lints the
# SOURCE files, never the rendered ones.
#
# Latent today (0 hits) across ~20 continuation sites. Guarded because ADR-152 tells
# maintainers comments are now free, which is exactly the belief that trips it.
_cont_hits="$(awk 'prev ~ /\\[ \t]*$/ && $0 ~ /^[ \t]*#/ {printf "%s:%d\n", FILENAME, NR} {prev=$0}' \
  "$DIR"/git-data-bootstrap.sh "$DIR"/git-data-provision.sh "$DIR"/git-data-transport-wrapper.sh \
  "$DIR"/git-data-remove.sh "$DIR"/git-data-gc.sh "$DIR"/git-data-pre-receive-placeholder.sh \
  "$DIR"/git-data-gc.service "$DIR"/git-data-gc-failure.service "$DIR"/git-data-gc.timer 2>/dev/null || true)"
if [[ -z "$_cont_hits" ]]; then
  pass "no comment sits directly after a line continuation in any injected payload"
else
  fail "a comment follows a line continuation — the strip JOINS the two commands on the host" \
    "$(printf '%s' "$_cont_hits" | head -6)"
fi

# ── 3. The rendered payloads: shebang intact, and still valid shell ────────────────────
if ! command -v terraform >/dev/null 2>&1 || ! command -v python3 >/dev/null 2>&1; then
  # NOT a silent skip: an unrenderable harness must be visible, not read as coverage.
  printf '  note terraform or python3 absent — render-dependent arms did not run\n'
  if [[ "${CI:-}" == "true" ]]; then
    fail "render-dependent arms cannot be skipped under CI=true" "install terraform + python3 on this runner"
  fi
else
  RENDER="$(mktemp -t gdstrip.XXXXXXXX.yml)" || { echo "mktemp failed" >&2; exit 2; }
  trap 'rm -f "$RENDER"' EXIT
  if ! bash "$BUDGET" "$RENDER" >/dev/null 2>&1; then
    fail "render succeeded" "git-data-userdata-budget.sh returned non-zero (over cap, or the render itself failed)"
  else
    shebang_out="$(python3 - "$RENDER" <<'PY'
import sys, yaml, os, subprocess, tempfile
d = yaml.safe_load(open(sys.argv[1]))
bad = []
checked = 0
for wf in d["write_files"]:
    path, content = wf["path"], wf["content"]
    if not (path.endswith(".sh") or path == "/usr/local/bin/git-data-emit"):
        continue
    checked += 1
    if not content.startswith("#!"):
        bad.append("%s: line 1 is not a shebang (%r)" % (path, content.split("\n", 1)[0][:40]))
        continue
    with tempfile.NamedTemporaryFile("w", suffix=".sh", delete=False) as f:
        f.write(content)
        tmp = f.name
    r = subprocess.run(["bash", "-n", tmp], capture_output=True, text=True)
    os.unlink(tmp)
    if r.returncode != 0:
        bad.append("%s: bash -n failed: %s" % (path, r.stderr.strip()[:120]))
# A floor, because "found nothing to check" is not "everything passed".
if checked < 7:
    bad.append("only %d shell payloads inspected (<7) — the render lost payloads" % checked)
print("CHECKED=%d" % checked)
for b in bad:
    print("BAD " + b)
PY
)"
    n_checked="$(sed -n 's/^CHECKED=//p' <<<"$shebang_out")"
    n_bad="$(grep -c '^BAD ' <<<"$shebang_out" || true)"
    if [[ "$n_bad" -eq 0 ]]; then
      pass "all ${n_checked} rendered shell payloads keep their shebang and pass bash -n"
    else
      fail "the strip damaged ${n_bad} rendered payload(s)" "$(grep '^BAD ' <<<"$shebang_out" | head -6)"
    fi
  fi
fi

# ── 4. The strip must actually strip, and must NOT touch mid-line `#` ──────────────────
#
# Verify-the-verifier: without this, every arm above is satisfied by a strip expression that
# does nothing at all.
probe="$(mktemp -t gdprobe.XXXXXXXX)" || exit 2
printf '#!/usr/bin/env bash\n# a rationale line\nX=${PATH#/}\ncmd  # trailing\n#\n' > "$probe"
if command -v terraform >/dev/null 2>&1; then
  scratch="$(mktemp -d -t gdstripchk.XXXXXXXX)" || exit 2
  {
    printf 'locals {\n'
    printf '  s = %s\n' "$tf_strip"
    printf '  out = replace(file("%s"), local.s, "")\n' "$probe"
    printf '}\n'
  } > "$scratch/main.tf"
  got="$(printf 'local.out\n' | terraform -chdir="$scratch" console 2>/dev/null)"
  if [[ "$got" == *'#!/usr/bin/env bash'* ]]; then
    pass "strip preserves the shebang"
  else
    fail "strip ate the shebang" "got: ${got}"
  fi
  if [[ "$got" != *'a rationale line'* ]]; then
    pass "strip removes a whole-line rationale comment (it is not a no-op)"
  else
    fail "strip is a NO-OP — it left a whole-line comment in place" "got: ${got}"
  fi
  if [[ "$got" == *'${PATH#/}'* ]]; then
    pass "strip leaves mid-line # alone (parameter expansion survives)"
  else
    fail "strip damaged a \${var#...} parameter expansion" "got: ${got}"
  fi
  if [[ "$got" == *'cmd  # trailing'* ]]; then
    pass "strip leaves a trailing comment alone (anchored at line start only)"
  else
    fail "strip removed a trailing comment — the expression is not line-anchored" "got: ${got}"
  fi
  rm -rf "$scratch"
fi
rm -f "$probe"

# ── Minimum-cardinality floor ──────────────────────────────────────────────────────────
_ran=$((passes + fails))
if [[ "$_ran" -lt 9 ]]; then
  fails=$((fails + 1))
  printf '  FAIL ANTI-VACUITY: only %s assertions ran, floor is 9.\n' "$_ran"
else
  printf '  ok   anti-vacuity floor: %s assertions ran (floor 9)\n' "$_ran"
fi

printf '\n=== git-data-render-strip-parity: %d passed, %d failed ===\n\n' "$passes" "$fails"
[[ "$fails" -eq 0 ]]
