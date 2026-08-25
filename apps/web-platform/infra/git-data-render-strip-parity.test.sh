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
# Read by arm 1e: B1 lives in the rehearsal suite and re-reads the payload expression
# out of main.tf, so the shape of ITS extractor is a parity concern.
REHEARSAL="$DIR/git-data-runcmd-rehearsal.test.sh"

if [[ ! -f "$TF" ]]; then
  printf '\n=== git-data-render-strip-parity ===\n\n  FAIL canonical render module not found at %s\n' "$TF"
  printf '\n=== git-data-render-strip-parity: 0 passed, 1 failed ===\n\n'
  exit 1
fi

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
# `$( )` — a subshell discards it and the code still reads as correct. The three CONDITIONAL
# arms (the CI=true skip guard, the render branch, and arm 4's terraform-only probes)
# increment INSIDE the branch that actually reaches a verdict, so a skipped arm costs a case
# and trips the floor rather than silently satisfying conservation.
CASES=0

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
#
# PARAMETERISED BY NAME because main.tf now declares TWO expressions (#7264): the payload
# strip (`#!`-preserving, for the nine file()-bound scripts) and the template strip
# (directive-preserving, for the cloud-init body). ADR-152 rules they are "deliberately not
# shared, and must not be" — so each needs its OWN mirror check, and arm 1c below asserts
# they have not been collapsed into one. The two names cannot cross-match:
# `git_data_template_rationale_strip` does not contain `git_data_rationale_strip` as a
# substring, which is why the template local is named with the qualifier in the MIDDLE and
# not as a `_template` suffix.
extract_strip() { grep -vE '^[[:space:]]*(#|//)' "$2" | grep -oE "$1"'[[:space:]]*=[[:space:]]*".*"' | head -1 | sed 's/^[^=]*=[[:space:]]*//'; }

tf_strip="$(extract_strip git_data_rationale_strip "$TF")"
# The budget script emits its locals block through an UNQUOTED heredoc, so bash halves every
# backslash on the way to the generated main.tf. Compare what terraform will actually see:
# unescape the shell layer before comparing, rather than comparing the two source spellings
# (which legitimately differ) or normalising both to nothing (which would compare no bytes).
budget_raw="$(extract_strip git_data_rationale_strip "$BUDGET")"
# Halve the doubled backslashes ONLY. Do NOT run this through `printf '%b'`: that would
# interpret `\t`/`\n` as a real tab and newline, comparing the expression's MEANING instead of
# the bytes terraform receives — and it would report two genuinely different expressions as
# equal the moment one of them spelled a character literally.
budget_strip="${budget_raw//\\\\/\\}"

CASES=$((CASES + 1))
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

# ── 1b. The TEMPLATE strip expression must be mirrored the same way ────────────────────
tf_tpl="$(extract_strip git_data_template_rationale_strip "$TF")"
budget_tpl_raw="$(extract_strip git_data_template_rationale_strip "$BUDGET")"
budget_tpl="${budget_tpl_raw//\\\\/\\}"

CASES=$((CASES + 1))
if [[ -z "$tf_tpl" ]]; then
  fail "modules/git-data-userdata/main.tf declares a TEMPLATE strip expression" "no git_data_template_rationale_strip assignment found — the cloud-init body would ship unstripped"
elif [[ -z "$budget_tpl_raw" ]]; then
  fail "git-data-userdata-budget.sh mirrors the TEMPLATE strip expression" "no git_data_template_rationale_strip assignment found — the budget would measure a payload no host is given"
elif [[ "$tf_tpl" == "$budget_tpl" ]]; then
  pass "TEMPLATE strip expression is byte-identical in modules/git-data-userdata/main.tf and git-data-userdata-budget.sh"
else
  fail "TEMPLATE strip expression DRIFTED between the two hand-mirrored maps" \
    "module: ${tf_tpl} | budget(as terraform sees it): ${budget_tpl}"
fi

# ── 1c. The two expressions must NOT be the same ───────────────────────────────────────
#
# ADR-152: "The expression is deliberately not shared, and must not be." The payload form
# preserves `#!` and NOTHING else, which deletes `#cloud-config`; the template form preserves
# any `#`-directive. Collapsing them is the exact regression that boots a host dark, and it
# is a one-line edit away at all times.
CASES=$((CASES + 1))
if [[ -z "$tf_tpl" || -z "$tf_strip" ]]; then
  fail "both strip expressions are present to compare" "payload='${tf_strip}' template='${tf_tpl}'"
elif [[ "$tf_strip" == "$tf_tpl" ]]; then
  fail "the payload and TEMPLATE strip expressions have been COLLAPSED into one" \
    "ADR-152 forbids sharing: the payload form deletes '#cloud-config'. Both are: ${tf_strip}"
else
  pass "payload and TEMPLATE strip expressions are distinct (ADR-152: deliberately not shared)"
fi

# ── 1d. The template strip must actually be APPLIED to the render ──────────────────────
#
# Declared-but-unreferenced is the silent form of this defect: the expression is present,
# parity holds, and the render still ships unstripped. Mirrors the registry precedent's
# `never REFERENCES` guard.
# COMMENT-STRIPPED AND CO-LOCATED, because neither property is optional here.
#
# The first form of this arm was two INDEPENDENT unanchored greps over the raw file — one for
# `replace(templatefile(`, one for the local's name. Both tokens appear in this module's own
# rationale prose, so comment rot alone could satisfy it with the render unwrapped. And even
# on stripped text, two independent greps assert only that both strings EXIST somewhere; they
# never assert the close belongs to that open.
#
# This is the only arm anywhere that pins the strip's APPLICATION. The sibling arms assert the
# expression is declared (1/1b), mirrored (1/1b) and distinct from the payload form (1c) —
# every one of which stays green when the `replace(...)` wrap is deleted, because the render
# harness every render-based suite uses carries its own copy and strips regardless. Deleting
# one line in main.tf reverts what a git-data host boots from, on a ForceNew attribute, and
# nothing else in CI can see it.
_tf_code="$(grep -vE '^[[:space:]]*(#|//)' "$TF")"
_open_ln="$(grep -nE '^[[:space:]]*rendered[[:space:]]*=[[:space:]]*replace\(templatefile\(' <<<"$_tf_code" | head -1 | cut -d: -f1)"
CASES=$((CASES + 1))
if [[ -z "$_open_ln" ]]; then
  fail "the render does NOT apply the template strip" \
    "main.tf declares git_data_template_rationale_strip but `rendered` never opens replace(templatefile( — the stored payload is unstripped and the host boots the un-stripped document"
elif ! grep -qE '^[[:space:]]*\}\)[[:space:]]*,[[:space:]]*local\.git_data_template_rationale_strip[[:space:]]*,' <<<"$(tail -n "+${_open_ln}" <<<"$_tf_code")"; then
  fail "the render opens replace(templatefile( but no matching '}), local.git_data_template_rationale_strip,' follows it" \
    "the wrap is applied with some OTHER expression, or the close drifted — either way the shipped payload is not the one this suite measures"
else
  pass "the render APPLIES the template strip: replace(templatefile(...), local.git_data_template_rationale_strip, \"\")"
fi

# ── 1e. B1's extractor must not be shadowed by a comment ───────────────────────────────
#
# git-data-runcmd-rehearsal.test.sh's B1 arm re-reads the strip expression OUT of main.tf and
# recompiles it as a Python regex to mirror the render. Its original form was a bare
# `re.search` over the raw file taking the FIRST match, so a comment naming an old expression
# — exactly the prose this repo writes — would be extracted instead of the live assignment,
# and B1's own `#!/bin/sh\n# a comment\n` probe passes either way. Wrong stripper, green
# suite. The fixture below is the proof the anchored form is required: it prepends a
# shadowing comment and asserts the live expression still wins.
# THE SHIPPED EXTRACTOR, not Python's own regex semantics.
#
# The first form of this arm built its own shadowed fixture and asserted that Python's
# ANCHORED `re.search` beats its UNANCHORED one. That is true of Python whatever the rehearsal
# suite actually contains, so the arm could never fail while still counting toward the floor —
# a tautology wearing a guard's clothes. What matters is which form the rehearsal SHIPS.
#
# B1 re-reads the payload strip expression out of main.tf and recompiles it to mirror the
# render. Unanchored, a COMMENT naming an old expression — exactly the prose this repo writes —
# is extracted instead of the live assignment, and B1's own `#!/bin/sh\n# a comment\n` probe
# passes either way: wrong stripper, green suite.
_b1_anchored=$(grep -cF "re.search(r'^\\s*git_data_rationale_strip" "$REHEARSAL" 2>/dev/null || true)
_b1_bare=$(grep -cE "re\\.search\\(r'git_data_rationale_strip" "$REHEARSAL" 2>/dev/null || true)
CASES=$((CASES + 1))
if [[ ! -f "$REHEARSAL" ]]; then
  fail "the rehearsal suite is readable" "expected it at $REHEARSAL"
elif [[ "$_b1_anchored" -ge 1 && "$_b1_bare" -eq 0 ]]; then
  pass "the rehearsal's B1 extractor is line-anchored, so a shadowing comment cannot displace the live expression"
else
  fail "the rehearsal's B1 extractor is not line-anchored (anchored=${_b1_anchored} bare=${_b1_bare})" \
    "an unanchored re.search takes the FIRST match, so a comment naming an old expression is mirrored instead of the live one — and B1's own probe passes either way"
fi

# And the live form must actually be the anchored one in the rehearsal suite.
CASES=$((CASES + 1))
if [[ -f "$REHEARSAL" ]] && grep -qF "re.search(r'^\\s*git_data_rationale_strip" "$REHEARSAL"; then
  pass "git-data-runcmd-rehearsal.test.sh uses the anchored, line-start extractor"
else
  fail "git-data-runcmd-rehearsal.test.sh does NOT use the anchored extractor" \
    "a comment naming an old expression would shadow the live one (B1 mirrors the wrong strip)"
fi

# ── 2. Downstream-parser invariants (plugins/soleur/test/cloud-init-user-data-size.test.ts) ─
#
# That file finds the templatefile map by counting BRACE DEPTH and parses entries with a
# LINE-BASED regex. A brace inside the strip expression would unbalance the first; wrapping a
# map entry across two physical lines would defeat the second. Both are invisible until that
# suite reds for a reason that looks unrelated.
CASES=$((CASES + 1))
if [[ "$tf_strip" == *'{'* || "$tf_strip" == *'}'* ]]; then
  fail "strip expression contains no brace" "found a brace in: ${tf_strip}"
else
  pass "strip expression contains no brace (brace-depth map scanner stays balanced)"
fi

n_entries=$(grep -cE '^[[:space:]]+git_data_[a-z_]+[[:space:]]*=[[:space:]]*replace\(file\(' "$TF")
CASES=$((CASES + 1))
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
CASES=$((CASES + 1))
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
  "$DIR"/git-data-gc.service "$DIR"/git-data-gc-failure.service "$DIR"/git-data-gc.timer \
  "$DIR"/cloud-init-git-data.yml 2>/dev/null || true)"
CASES=$((CASES + 1))
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
    CASES=$((CASES + 1))
    fail "render-dependent arms cannot be skipped under CI=true" "install terraform + python3 on this runner"
  fi
else
  RENDER="$(mktemp -t gdstrip.XXXXXXXX.yml)" || { echo "mktemp failed" >&2; exit 2; }
  trap 'rm -f "$RENDER"' EXIT
  if ! bash "$BUDGET" "$RENDER" >/dev/null 2>&1; then
    CASES=$((CASES + 1))
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
    CASES=$((CASES + 1))
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
  CASES=$((CASES + 1))
  if [[ "$got" == *'#!/usr/bin/env bash'* ]]; then
    pass "strip preserves the shebang"
  else
    fail "strip ate the shebang" "got: ${got}"
  fi
  CASES=$((CASES + 1))
  if [[ "$got" != *'a rationale line'* ]]; then
    pass "strip removes a whole-line rationale comment (it is not a no-op)"
  else
    fail "strip is a NO-OP — it left a whole-line comment in place" "got: ${got}"
  fi
  CASES=$((CASES + 1))
  if [[ "$got" == *'${PATH#/}'* ]]; then
    pass "strip leaves mid-line # alone (parameter expansion survives)"
  else
    fail "strip damaged a \${var#...} parameter expansion" "got: ${got}"
  fi
  CASES=$((CASES + 1))
  if [[ "$got" == *'cmd  # trailing'* ]]; then
    pass "strip leaves a trailing comment alone (anchored at line start only)"
  else
    fail "strip removed a trailing comment — the expression is not line-anchored" "got: ${got}"
  fi
  rm -rf "$scratch"
fi
rm -f "$probe"

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
  printf '\n=== git-data-render-strip-parity: %d passed, %d failed ===\n\n' "$passes" "$fails"
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
# Zero headroom against the current count (10 unconditional arms + the render arm + arm 4's
# four probes = 15), so any deletion is loud — and so is a silently skipped conditional arm,
# because a skipped arm never increments. Ratchet when adding arms.
if [[ "$CASES" -lt 15 ]]; then
  printf '\n[FATAL] anti-vacuity floor: only %d assertion(s) ran, expected >= 15.\n' "$CASES" >&2
  printf '  Arms were deleted or skipped; a green run here would be a coverage loss.\n' >&2
  printf '\n=== git-data-render-strip-parity: %d passed, %d failed ===\n\n' "$passes" "$fails"
  exit 1
fi
printf '  ok   anti-vacuity floor: %s assertions ran (floor 15)\n' "$CASES"

printf '\n=== git-data-render-strip-parity: %d passed, %d failed ===\n\n' "$passes" "$fails"
[[ "$fails" -eq 0 ]]
