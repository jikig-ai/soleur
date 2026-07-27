#!/usr/bin/env bash
# Tests for scripts/raise-tmp-tmpfs-ceiling.sh.
#
# EVERY case drives the script against a FIXTURE fstab via the RAISE_TMPFS_FSTAB seam.
# The real /etc/fstab is never read and never written. A test that touched it could
# render the machine unbootable, which is the exact outcome the script exists to avoid.
#
# Fixtures are SYNTHESIZED (cq-test-fixtures-synthesized-only), not copies of the host's
# real fstab — a copy would put real device UUIDs into git.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/raise-tmp-tmpfs-ceiling.sh"

# Single owning scratch root (ADR-129 / #6734) — the very discipline this PR is about.
# NOT `set -e`, so guard the allocation explicitly; an empty root would make the trap a
# silent no-op and `export TMPDIR=""` would push fixtures back into a shared /tmp.
TMP_ROOT=$(mktemp -d -t raisetmpfs.XXXXXXXX) || { echo "FATAL: cannot create scratch root" >&2; exit 1; }
: "${TMP_ROOT:?}"
[[ "$TMP_ROOT" == /* && -d "$TMP_ROOT" && ! -L "$TMP_ROOT" ]] || { echo "FATAL: bad scratch root" >&2; exit 1; }
readonly TMP_ROOT
trap 'rm -rf -- "$TMP_ROOT"' EXIT INT TERM
export TMPDIR="$TMP_ROOT"

fails=0
pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; fails=$((fails + 1)); }

# A synthetic 30 GiB MemTotal, so the 25% target is a round 7680M.
MEMINFO="$TMP_ROOT/meminfo"
printf 'MemTotal:       31457280 kB\nMemFree:         3670016 kB\n' > "$MEMINFO"
EXPECTED_SPEC="7680M"

# new_fstab <name> <tmp-line>  -> path to a fresh fixture carrying realistic sibling lines
new_fstab() {
  local f="$TMP_ROOT/$1.fstab"
  {
    echo "# /etc/fstab: static file system information."
    echo "UUID=11111111-2222-3333-4444-555555555555 /         ext4  defaults          0 1"
    echo "UUID=66666666-7777-8888-9999-000000000000 /boot/efi vfat  umask=0077        0 1"
    [[ -n "${2:-}" ]] && echo "$2"
    echo "/swapfile                                 none      swap  sw                0 0"
  } > "$f"
  printf '%s' "$f"
}

# run_sut <fstab> [args...] -> stdout+stderr; sets RC
run_sut() {
  local fstab="$1"; shift
  local out
  OUT=$(RAISE_TMPFS_FSTAB="$fstab" \
        RAISE_TMPFS_MEMINFO="$MEMINFO" \
        RAISE_TMPFS_LOCK="$TMP_ROOT/lock" \
        RAISE_TMPFS_STAMP="20260727T120000Z" \
        bash "$SUT" "$@" 2>&1)
  RC=$?
  printf '%s' "$OUT"
}

tmp_size_of() { awk '$2 == "/tmp" { print $4 }' "$1"; }

echo "raise-tmp-tmpfs-ceiling.test.sh"

# --- 1. unapplied ⇒ rewritten, backup exists ------------------------------------------
f=$(new_fstab applied-none "tmpfs /tmp tmpfs defaults,nosuid,nodev,size=4G 0 0")
run_sut "$f"
if [[ "$RC" -eq 0 && "$(tmp_size_of "$f")" == *"size=${EXPECTED_SPEC}"* ]]; then
  pass "unapplied fstab is rewritten to the derived target ($EXPECTED_SPEC)"
else
  fail "unapplied rewrite — rc=$RC opts=$(tmp_size_of "$f")"
fi
[[ -f "${f}.bak.20260727T120000Z" ]] && pass "a timestamped backup is written" || fail "no backup written"

# --- 2. idempotent: re-running is a no-op ---------------------------------------------
before=$(cat "$f")
run_sut "$f"
if [[ "$RC" -eq 0 && "$(cat "$f")" == "$before" ]]; then
  pass "re-run is a no-op (idempotent)"
else
  fail "second run mutated an already-applied fstab — rc=$RC"
fi

# --- 3. NEVER SHRINK ------------------------------------------------------------------
f=$(new_fstab bigger "tmpfs /tmp tmpfs defaults,size=16G 0 0")
run_sut "$f"
if [[ "$RC" -eq 0 && "$(tmp_size_of "$f")" == *"size=16G"* ]]; then
  pass "a ceiling already above target is left alone (never shrinks)"
else
  fail "shrank an above-target ceiling — opts=$(tmp_size_of "$f")"
fi

# --- 4. unit normalization: 4194304k == 4G, must still be raised ----------------------
f=$(new_fstab units-k "tmpfs /tmp tmpfs defaults,size=4194304k 0 0")
run_sut "$f"
if [[ "$(tmp_size_of "$f")" == *"size=${EXPECTED_SPEC}"* ]]; then
  pass "size=4194304k is parsed as 4G and raised (unit normalization)"
else
  fail "unit normalization — opts=$(tmp_size_of "$f")"
fi

# --- 4b. percent form above target is recognized, not re-applied ----------------------
f=$(new_fstab units-pct "tmpfs /tmp tmpfs defaults,size=50% 0 0")
run_sut "$f"
if [[ "$RC" -eq 0 && "$(tmp_size_of "$f")" == *"size=50%"* ]]; then
  pass "size=50% is parsed against MemTotal and left alone (above target)"
else
  fail "percent-form handling — rc=$RC opts=$(tmp_size_of "$f")"
fi

# --- 5. no /tmp line at all ⇒ LOUD ABORT, never a silent exit 0 -----------------------
f=$(new_fstab no-tmp "")
before=$(cat "$f")
run_sut "$f"
if [[ "$RC" -ne 0 && "$OUT" == *"no active /tmp entry"* && "$(cat "$f")" == "$before" ]]; then
  pass "absent /tmp entry aborts loudly and names tmp.mount (no silent exit 0)"
else
  fail "absent /tmp entry — expected non-zero abort, got rc=$RC"
fi

# --- 6. /tmp line with no size= ⇒ explicit no-op, not an empty-string match -----------
f=$(new_fstab no-size "tmpfs /tmp tmpfs defaults,nosuid,nodev 0 0")
before=$(cat "$f")
run_sut "$f"
if [[ "$RC" -eq 0 && "$OUT" == *"no size= option"* && "$(cat "$f")" == "$before" ]]; then
  pass "a /tmp entry without size= is reported as already-defaulting, file untouched"
else
  fail "no-size handling — rc=$RC"
fi

# --- 7. multiple ACTIVE /tmp lines ⇒ refuse to guess ----------------------------------
f=$(new_fstab multi "tmpfs /tmp tmpfs defaults,size=4G 0 0")
echo "tmpfs /tmp tmpfs defaults,size=2G 0 0" >> "$f"
before=$(cat "$f")
run_sut "$f"
if [[ "$RC" -ne 0 && "$OUT" == *"active /tmp entries"* && "$(cat "$f")" == "$before" ]]; then
  pass "multiple active /tmp entries abort rather than guessing"
else
  fail "multi-entry handling — rc=$RC"
fi

# --- 8. a COMMENTED /tmp line is not mistaken for an active one -----------------------
f=$(new_fstab commented "tmpfs /tmp tmpfs defaults,size=4G 0 0")
sed -i '1i #tmpfs /tmp tmpfs defaults,size=1G 0 0' "$f"
run_sut "$f"
if [[ "$RC" -eq 0 && "$(tmp_size_of "$f")" == *"size=${EXPECTED_SPEC}"* ]]; then
  pass "a commented-out /tmp line is ignored; the active one is rewritten"
else
  fail "commented-line handling — rc=$RC opts=$(tmp_size_of "$f")"
fi

# --- 9. --dry-run writes NOTHING ------------------------------------------------------
f=$(new_fstab dryrun "tmpfs /tmp tmpfs defaults,size=4G 0 0")
before=$(cat "$f")
run_sut "$f" --dry-run
if [[ "$RC" -eq 0 && "$(cat "$f")" == "$before" && "$OUT" == *"no files written"* ]]; then
  pass "--dry-run writes nothing and says so"
else
  fail "--dry-run wrote to the fstab or misreported — rc=$RC"
fi
[[ -e "${f}.bak.20260727T120000Z" ]] && fail "--dry-run created a backup" || pass "--dry-run creates no backup"

# --- 10. NON-TARGET LINES SURVIVE (the only unbootable-machine path) ------------------
#         A rewrite that correctly fixes size= while dropping the `/` or swap line would
#         satisfy every size-focused assertion above and leave the box unbootable.
f=$(new_fstab preserve "tmpfs /tmp tmpfs defaults,size=4G 0 0")
orig_others=$(awk '$2 != "/tmp"' "$f")
orig_lines=$(wc -l < "$f")
run_sut "$f"
new_others=$(awk '$2 != "/tmp"' "$f")
new_lines=$(wc -l < "$f")
if [[ "$orig_others" == "$new_others" ]]; then
  pass "every non-/tmp line survives the rewrite byte-for-byte"
else
  fail "a non-/tmp line changed — THIS IS THE UNBOOTABLE PATH"
fi
[[ "$orig_lines" -eq "$new_lines" ]] && pass "line count is unchanged" || fail "line count changed ($orig_lines -> $new_lines)"
grep -q '/swapfile' "$f" && pass "the swap entry is still present" || fail "the swap entry was dropped"
grep -qE '^UUID=[0-9a-f-]+[[:space:]]+/[[:space:]]' "$f" && pass "the root (/) entry is still present" || fail "the root entry was dropped"

# --- 11. malformed target line (wrong field count) ⇒ refuse ---------------------------
f=$(new_fstab malformed "tmpfs /tmp tmpfs defaults,size=4G")
before=$(cat "$f")
run_sut "$f"
if [[ "$RC" -ne 0 && "$OUT" == *"expected 6"* && "$(cat "$f")" == "$before" ]]; then
  pass "a /tmp line with the wrong field count is refused, not rewritten"
else
  fail "malformed-line handling — rc=$RC"
fi

# --- 12. symlinked fstab ⇒ refuse (mv would swap the LINK, not the target) ------------
real=$(new_fstab symlink-target "tmpfs /tmp tmpfs defaults,size=4G 0 0")
link="$TMP_ROOT/fstab.link"
ln -s "$real" "$link"
run_sut "$link"
if [[ "$RC" -ne 0 && "$OUT" == *"symlink"* ]]; then
  pass "a symlinked fstab is refused"
else
  fail "symlink handling — rc=$RC"
fi

# --- 13. trailing newline is guaranteed ----------------------------------------------
f=$(new_fstab nonewline "tmpfs /tmp tmpfs defaults,size=4G 0 0")
printf '%s' "$(cat "$f")" > "$f"   # strip the trailing newline
run_sut "$f"
if [[ "$(tail -c1 "$f" | wc -l)" -eq 1 ]]; then
  pass "the installed fstab always ends with a newline"
else
  fail "installed fstab has no trailing newline"
fi

# --- 14. backup pruning keeps only the N most recent ----------------------------------
f=$(new_fstab prune "tmpfs /tmp tmpfs defaults,size=4G 0 0")
for i in 1 2 3 4 5 6 7; do
  : > "${f}.bak.2026010${i}T000000Z"
  touch -d "2026-01-0${i}" "${f}.bak.2026010${i}T000000Z"
done
out=$(RAISE_TMPFS_FSTAB="$f" RAISE_TMPFS_MEMINFO="$MEMINFO" RAISE_TMPFS_LOCK="$TMP_ROOT/lock" \
      RAISE_TMPFS_STAMP="20260727T130000Z" RAISE_TMPFS_BACKUP_KEEP=3 bash "$SUT" 2>&1)
kept=$(find "$TMP_ROOT" -maxdepth 1 -name "$(basename "$f").bak.*" | wc -l)
if [[ "$kept" -eq 3 ]]; then
  pass "backup pruning keeps exactly the configured number ($kept)"
else
  fail "backup pruning kept $kept, expected 3"
fi

# --- 15. the real /etc/fstab was never touched ----------------------------------------
# A standing guard: if any case above forgot its seam, this catches it.
if [[ -z "$(find "$TMP_ROOT" -maxdepth 0 -newer /etc/fstab 2>/dev/null; true)" ]] || [[ -r /etc/fstab ]]; then
  # We only assert we created no backups next to the real file.
  if find /etc -maxdepth 1 -name 'fstab.bak.20260727T1*' 2>/dev/null | grep -q .; then
    fail "a test wrote a backup next to the REAL /etc/fstab"
  else
    pass "no test artifact was written next to the real /etc/fstab"
  fi
fi

echo
if (( fails > 0 )); then echo "FAILED: $fails"; exit 1; fi
echo "All raise-tmp-tmpfs-ceiling tests passed."
