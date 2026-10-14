#!/usr/bin/env bash
# check-pa-22.test.sh -- behavioural suite for the PA-22 register sentinel.
#
# WHY THIS EXISTS (#7717). check-pa-22.sh was written to guard the PA-22 register entry and then
# ran in ZERO runners -- one of the five documented instances in
# knowledge-base/project/learnings/2026-07-16-a-gate-that-proves-it-cannot-fail-open-shipped-its-own-proof-unwired.md.
# It is registered in scripts/test-all.sh at #7717. Wiring it without driving it red would
# reproduce that learning rather than discharge it, so every assertion is mutation-pinned here.
#
# The SUT does `cd "$(git rev-parse --show-toplevel)"`, so each case runs inside a throwaway git
# repo holding a copy of the register. A sandbox that is not a git repo makes the SUT resolve to
# the REAL worktree, which would both void the case and read the live corpus.
export TMPDIR="${TMPDIR:-/var/tmp}"
set -uo pipefail

SRC_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUT="$SRC_ROOT/scripts/check-pa-22.sh"
REG_SRC="$SRC_ROOT/knowledge-base/legal/article-30-register.md"

fails=0; checks=0
pass() { checks=$((checks + 1)); echo "[ok] $1"; }
fail() { checks=$((checks + 1)); fails=$((fails + 1)); echo "[FAIL] $1" >&2; }
_b=$checks; { pass x; fail x; } >/dev/null 2>&1
[[ $checks -eq $((_b + 2)) && $fails -eq 1 ]] || { echo "::error::instrument self-test failed" >&2; exit 2; }
fails=0; checks=$_b

# One owning sandbox root, removed on exit (ADR-129 rule (c)). Each case allocates INSIDE it
# rather than calling `mktemp -d` at top level, so N cases leak zero directories even when the
# suite dies mid-case. Guarded so the trap can never expand to a bare `rm -rf ""`.
SANDBOX_ROOT="$(mktemp -d -t pa22-suite-root.XXXXXXXX)" \
  || { echo "::error::mktemp -d failed" >&2; exit 2; }
cleanup_sandbox() { [[ -n "${SANDBOX_ROOT:-}" && -d "$SANDBOX_ROOT" ]] && rm -rf "$SANDBOX_ROOT"; return 0; }
trap cleanup_sandbox EXIT INT TERM

[[ -f "$SUT"     ]] || { echo "::error::SUT not found: $SUT" >&2; exit 2; }
[[ -f "$REG_SRC" ]] || { echo "::error::register not found: $REG_SRC" >&2; exit 2; }

mkrepo() {
  local d
  d="$(mktemp -d "$SANDBOX_ROOT/case.XXXXXXXX")" || return 2
  mkdir -p "$d/scripts" "$d/knowledge-base/legal" || return 2
  cp "$SUT" "$d/scripts/check-pa-22.sh" || return 2
  cp "$REG_SRC" "$d/knowledge-base/legal/article-30-register.md" || return 2
  ( cd "$d" && git init -q -b main . && git config user.email t@t && git config user.name t \
      && git add -A && git commit -qm init ) >/dev/null 2>&1 || return 2
  printf '%s' "$d"
}
run_in() { ( cd "$1" && bash scripts/check-pa-22.sh >/dev/null 2>&1 ); echo $?; }
expect() { local g; g="$(run_in "$3")"; if [[ "$g" == "$2" ]]; then pass "$1 (rc=$g)"; else fail "$1: expected rc=$2, got rc=$g"; fi; }

# Remove a literal from INSIDE the PA-22 block only, asserting the mutation landed. Shared by the
# TOMs and Zero-Retention arms: both patterns also match lines under other Processing Activities,
# so a global rename is "empty the table" and cannot be told apart from "drop the row".
strip_in_pa22() {
  python3 - "$1/knowledge-base/legal/article-30-register.md" "$2" "$3" <<'PY'
import io, sys
p, needle, repl = sys.argv[1], sys.argv[2], sys.argv[3]
L = io.open(p, encoding="utf-8").read().split("\n")
s = next(i for i, l in enumerate(L) if l.startswith("## Processing Activity 22"))
e = next(i for i, l in enumerate(L) if i > s and l.startswith("## "))
n = 0
for i in range(s, e):
    if needle in L[i]:
        L[i] = L[i].replace(needle, repl); n += 1
assert n >= 1, f"expected >=1 {needle!r} inside the PA-22 block, found {n}"
io.open(p, "w", encoding="utf-8").write("\n".join(L))
PY
}

# Remove PA-22's own (g) TOMs row, in-block, asserting the mutation landed.
strip_pa22_toms() {
  python3 - "$1/knowledge-base/legal/article-30-register.md" <<'PY'
import io, sys
p = sys.argv[1]; L = io.open(p, encoding="utf-8").read().split("\n")
s = next(i for i, l in enumerate(L) if l.startswith("## Processing Activity 22"))
e = next(i for i, l in enumerate(L) if i > s and l.startswith("## "))
n = 0
for i in range(s, e):
    if "TOMs" in L[i]:
        L[i] = L[i].replace("(g) TOMs (Art. 32)", "(g) REMOVED (Art. 32)"); n += 1
assert n == 1, f"expected exactly 1 TOMs row inside the PA-22 block, found {n}"
io.open(p, "w", encoding="utf-8").write("\n".join(L))
PY
}

D="$(mkrepo)" || { echo "::error::setup failed" >&2; exit 2; }
expect "baseline: the live register passes all four assertions" 0 "$D"

# (i) header present exactly once
D="$(mkrepo)" || exit 2
# The first form of this mutation renamed the heading to `22-RENAMED`, which the ORIGINAL bare
# prefix grep still counted as present -- the assertion could not see its own subject leave.
# Both the guard's anchor and this fixture were corrected at #7717; the suffix arm below pins it.
sed -i 's/^## Processing Activity 22 /## Processing Activity 99 /' "$D/knowledge-base/legal/article-30-register.md" || exit 2
expect "(i) a missing PA-22 header is caught" 1 "$D"

D="$(mkrepo)" || exit 2
sed -i 's/^## Processing Activity 22 /## Processing Activity 22-RENAMED /' "$D/knowledge-base/legal/article-30-register.md" || exit 2
expect "(i) a heading renamed to a SUFFIX of PA-22 does not count as present" 1 "$D"

D="$(mkrepo)" || exit 2
printf '\n## Processing Activity 22 — duplicate\n' >> "$D/knowledge-base/legal/article-30-register.md" || exit 2
expect "(i) a DUPLICATE PA-22 header is caught (exactly once, not at-least-once)" 1 "$D"

# (iv) TOMs inside the block -- the non-vacuity arm
D="$(mkrepo)" || exit 2
strip_pa22_toms "$D" || exit 2
expect "(iv) removing PA-22's own (g) TOMs row is caught" 1 "$D"

# (iv) THE RANGE ARM. Before #7717 the awk range terminated on `## Processing Activity 23`, but
# `## Vendor / Sub-Processor Mapping` and `## Cross-Cutting Technical & Organisational Measures`
# sit between PA-22 and PA-23, so the range spanned four headings. That was LATENT rather than
# live -- the only TOMs literal in the over-spanned region was PA-22's own -- so this arm plants
# one and re-runs the removal. Under the old range it passed vacuously; under the tightened
# range it must still red. Without this arm the range defect is invisible.
D="$(mkrepo)" || exit 2
python3 - "$D/knowledge-base/legal/article-30-register.md" <<'PY'
import io, sys
p = sys.argv[1]; L = io.open(p, encoding="utf-8").read().split("\n")
i = next(i for i, l in enumerate(L) if l.startswith("## Cross-Cutting"))
L.insert(i + 1, "A sentence mentioning TOMs outside the PA-22 block.")
io.open(p, "w", encoding="utf-8").write("\n".join(L))
PY
strip_pa22_toms "$D" || exit 2
expect "(iv) a TOMs literal OUTSIDE the block cannot satisfy the in-block assertion" 1 "$D"

# The range is bounded to the PA-22 block.
n="$(awk '/^## Processing Activity 22/{b=1; next} b && /^## /{exit} b' "$REG_SRC" | grep -cE '^## ')"
if [[ "$n" == "0" ]]; then pass "(iv) the extracted range contains no further '## ' heading"
else fail "(iv) the range still spans $n further heading(s) -- it is not bounded to PA-22"; fi

# (ii) THE VENDOR MAPPING ROW. This assertion had NO fixture at all: neutering it left the suite
# 9/9 green, on a suite whose own preamble says every assertion is mutation-pinned. Two arms --
# the row removed, and the row removed while prose elsewhere still says the same words.
D="$(mkrepo)" || exit 2
python3 - "$D/knowledge-base/legal/article-30-register.md" <<'PY2' || exit 2
import io, re, sys
p = sys.argv[1]; s = io.open(p, encoding="utf-8").read()
s2 = re.sub(r'(?m)^\| \*\*Anthropic PBC\*\*.*\n', '', s)
assert s2 != s, "anchor: Anthropic PBC vendor row"
io.open(p, "w", encoding="utf-8").write(s2)
PY2
expect "(ii) removing the Anthropic Vendor Mapping row is caught" 1 "$D"

D="$(mkrepo)" || exit 2
python3 - "$D/knowledge-base/legal/article-30-register.md" <<'PY3' || exit 2
import io, re, sys
p = sys.argv[1]; s = io.open(p, encoding="utf-8").read()
s2 = re.sub(r'(?m)^\| \*\*Anthropic PBC\*\*.*\n', '', s)
assert s2 != s, "anchor"
# ...and plant the same words far outside the Vendor Mapping section.
s2 = s2.replace("## Register Maintenance",
  "Narrative note: Anthropic is discussed at PA-22 as an autonomous runtime dependency.\n\n## Register Maintenance", 1)
io.open(p, "w", encoding="utf-8").write(s2)
PY3
expect "(ii) prose OUTSIDE the Vendor Mapping section cannot satisfy the in-section assertion" 1 "$D"

# (iii) ZERO-RETENTION, IN-BLOCK. File-wide the pattern matches 8 lines and only 1 is PA-22's, so
# the old global-rename fixture emptied the table rather than dropping the row.
D="$(mkrepo)" || exit 2
strip_in_pa22 "$D" "Zero-Retention" "ZeroRetentionREMOVED" || exit 2
expect "(iii) removing Zero-Retention from the PA-22 block ALONE is caught" 1 "$D"

D="$(mkrepo)" || exit 2
strip_in_pa22 "$D" "Zero-Retention" "ZeroRetentionREMOVED" || exit 2
python3 - "$D/knowledge-base/legal/article-30-register.md" <<'PY5' || exit 2
import io, sys
p = sys.argv[1]; s = io.open(p, encoding="utf-8").read()
s = s.replace("## Register Maintenance",
  "Narrative: the Anthropic Zero-Retention amendment is signed and recorded elsewhere.\n\n## Register Maintenance", 1)
io.open(p, "w", encoding="utf-8").write(s)
PY5
expect "(iii) a Zero-Retention line OUTSIDE the PA-22 block cannot satisfy it" 1 "$D"

# (ii) Vendor Mapping row, (iii) Zero-Retention status
D="$(mkrepo)" || exit 2
sed -i 's/Zero-Retention/ZeroRetentionRENAMED/g' "$D/knowledge-base/legal/article-30-register.md" || exit 2
expect "(iii) losing the Zero-Retention status record is caught" 1 "$D"

# Fail-closed on an unreadable register.
D="$(mkrepo)" || exit 2
rm -f "$D/knowledge-base/legal/article-30-register.md" || exit 2
expect "a missing register is caught, not treated as vacuously clean" 1 "$D"

echo
echo "passed: $((checks - fails)) failed: $fails total: $checks"
MIN_ASSERTIONS=13
if [[ $checks -lt $MIN_ASSERTIONS ]]; then
  printf '::error::check-pa-22.test.sh: only %d assertion(s) ran, expected >= %d\n' "$checks" "$MIN_ASSERTIONS" >&2
  exit 1
fi
[[ $fails -eq 0 ]] || exit 1
echo "=== check-pa-22.test.sh: all assertions passed ==="
