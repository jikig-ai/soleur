#!/usr/bin/env bash
#
# (#7772, plan task 5.4) SYNTAX-VALIDATE git-data's metadata-egress ruleset BEFORE the host exists.
#
# WHAT THIS CATCHES THAT NOTHING ELSE DOES. `git-data-runcmd-rehearsal.test.sh` asserts the two
# nftables payloads are DELIVERED and that the ruleset carries `169.254.169.254`, `skuid` and the
# `delete table` idiom. None of that is a parse. A ruleset that ships with a typo'd family, a
# malformed address or an unbalanced brace satisfies every one of those checks and then fails at
# `nft -f` on a host that costs a destructive replace to fix — leaving the metadata endpoint open
# to every non-root UID on the box holding every connected user's source code.
#
# The failure IS observable after the fact: the runcmd arm emits `stage:gitdata_nftables_metadata`
# on death and `..._warn` on a soft failure, and #7772 item C routes both. But "observable on a
# paid rehearsal host" is not the same as "caught in CI", and this control exists to be the second.
#
# THE MEASUREMENT THAT SHAPES THIS FILE, and it is why the check is not a bare `nft -c -f`:
# `nft -c -f` NEEDS PRIVILEGE. Measured on this image (nftables v1.0.9): as an unprivileged user
# BOTH a valid ruleset and a deliberately-invalid one exit 1 with the identical message
# `netlink: Error: cache initialization failed: Operation not permitted`. So an unprivileged
# `nft -c -f` cannot tell a syntax error from its own lack of privilege — it is a check that
# reports FAIL on correct input and would be "fixed" by deleting it.
#
# Hence the DISCRIMINATOR SELF-TEST below: before trusting the checker on the real ruleset, it is
# driven over a known-good and a known-bad fixture and must disagree about them. If it cannot,
# this suite SKIPS LOUDLY rather than passing — and REFUSES (rc 1) under CI, where privilege is
# available and an inability to discriminate means something is wrong rather than absent.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TPL="${GIT_DATA_CLOUD_INIT:-$HERE/cloud-init-git-data.yml}"
TMP="$(mktemp -d "${TMPDIR:-/var/tmp}/gdnft.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

passes=0; fails=0; skipped=0
FAILURES=()
pass() { passes=$((passes + 1)); printf '  ok   %s\n' "$1"; }
fail() { fails=$((fails + 1)); FAILURES+=("$1"); printf '  FAIL %s\n' "$1" >&2; [ -n "${2:-}" ] && printf '       %s\n' "$2" >&2; return 0; }
skip() { skipped=$((skipped + 1)); printf '  SKIP %s\n' "$1" >&2; }

# ── 1. Extract the ruleset from the template's heredoc ────────────────────────────
# ANCHORED ON THE HEREDOC DELIMITERS, not on a line count or a byte offset: the payload is inline
# in cloud-init `write_files` at a fixed indent, and anything positional would silently extract the
# wrong span after any edit above it.
RULES="$TMP/ruleset.nft"
python3 - "$TPL" "$RULES" <<'PY'
import re, sys, textwrap
src = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"^(\s*)nft -f - <<'NFTEOF'\n(.*?)^\s*NFTEOF\s*$", src, re.M | re.S)
if not m:
    print("EXTRACT FAIL: no `nft -f - <<'NFTEOF'` heredoc in the template", file=sys.stderr)
    sys.exit(2)
open(sys.argv[2], "w", encoding="utf-8").write(textwrap.dedent(m.group(2)))
PY
if [ ! -s "$RULES" ]; then
  fail "the nft ruleset could not be extracted from ${TPL}" \
       "Every check below quantifies over this file; an empty extraction would make them all vacuous."
  printf '\n=== git-data-nftables-syntax: %d passed, %d failed ===\n' "$passes" "$fails"
  exit 1
fi
pass "the ruleset extracts from the template's NFTEOF heredoc ($(wc -l < "$RULES") lines)"

# NON-VACUITY. An extraction that produced SOMETHING but not the control is worse than an empty
# one, because every syntax check below would then pass over the wrong bytes.
_missing=()
for tok in 'table inet soleur_git_data' 'delete table inet soleur_git_data' \
           'hook output' 'skuid' '169.254.169.254'; do
  grep -qF "$tok" "$RULES" || _missing+=("$tok")
done
if [ "${#_missing[@]}" -eq 0 ]; then
  pass "the extracted ruleset carries every load-bearing token of the control"
else
  fail "the extracted ruleset is missing: ${_missing[*]}" \
       "This is an extraction defect or a real regression in the control; either way the syntax checks below would be measuring the wrong bytes."
fi

# ── 2. Build the checker, then PROVE it discriminates ─────────────────────────────
NFT_BIN="$(command -v nft || true)"
SUDO=""
if [ -n "$NFT_BIN" ] && [ "$(id -u)" -ne 0 ]; then
  sudo -n true >/dev/null 2>&1 && SUDO="sudo -n"
fi
_check() { $SUDO "$NFT_BIN" -c -f "$1" >/dev/null 2>&1; }

GOOD="$TMP/good.nft"; BAD="$TMP/bad.nft"
cat > "$GOOD" <<'EOF'
table inet soleur_probe_ok {
  chain output {
    type filter hook output priority -10; policy accept;
    meta skuid != 0 ip daddr 169.254.169.254 drop
  }
}
EOF
# Deliberately invalid: `NOT.AN.IP` is not an address. Kept to ONE defect so a rejection is
# attributable, and chosen inside the same construct the real ruleset uses.
cat > "$BAD" <<'EOF'
table inet soleur_probe_bad {
  chain output {
    type filter hook output priority -10; policy accept;
    meta skuid != 0 ip daddr NOT.AN.IP drop
  }
}
EOF

_discriminates=0
if [ -n "$NFT_BIN" ] && _check "$GOOD" && ! _check "$BAD"; then _discriminates=1; fi

if [ "$_discriminates" -eq 1 ]; then
  pass "the nft checker DISCRIMINATES (accepts a valid probe ruleset, rejects an invalid one)"
  if _check "$RULES"; then
    pass "the shipped git-data ruleset PARSES under \`nft -c -f\`"
  else
    fail "the shipped git-data ruleset does NOT parse under \`nft -c -f\`" \
         "$($SUDO "$NFT_BIN" -c -f "$RULES" 2>&1 | head -3)"
  fi
else
  _why="nft binary absent"
  if [ -n "$NFT_BIN" ]; then
    _why="\`nft -c -f\` cannot discriminate here — it needs privilege (measured: an unprivileged run reports \`cache initialization failed: Operation not permitted\` for VALID and INVALID rulesets alike), and no root or passwordless sudo is available"
  fi
  # THE CI REFUSAL IS SCOPED TO THE CASE THAT IS ACTUALLY A DEFECT. `nft` PRESENT but unable to
  # discriminate means privilege is missing where the workflow has passwordless sudo — that is a
  # broken step and must red. `nft` ABSENT is a capability the runner genuinely may not carry, and
  # this suite is auto-discovered by run-registered-suites.sh on hosts that never installed it;
  # refusing there would red CI for a reason unrelated to the diff. The workflow step that owns
  # this check installs nftables first, so the discriminating run happens in exactly one place and
  # a silent absence everywhere else is still LOUD.
  if [ -n "${CI:-}" ] && [ -n "$NFT_BIN" ]; then
    fail "the nft syntax check could not run under CI: ${_why}" \
         "nft is installed here and CI has passwordless sudo, so an inability to discriminate is a defect in this step, not an absent capability. Refusing rather than reporting a pass over an unparsed ruleset."
  else
    skip "nft syntax check: ${_why} (a PRESENT-but-undiscriminating nft is a hard FAIL under CI)"
  fi
fi

# ── 3. Instrument self-test ───────────────────────────────────────────────────────
# The floor below is a passive count and cannot see a neutered helper. Drive both once, require
# each counter to move, then unwind so the reported totals are untouched.
_p0=$passes; _f0=$fails; _l0=${#FAILURES[@]}
pass "CANARY — instrument self-test, not a real assertion" >/dev/null
fail "CANARY — instrument self-test, not a real failure" >/dev/null 2>&1
if [ "$passes" -ne $((_p0 + 1)) ] || [ "$fails" -ne $((_f0 + 1)) ] || [ "${#FAILURES[@]}" -ne $((_l0 + 1)) ]; then
  printf 'FAIL CANARY: passes %d->%d, fails %d->%d, ledger %d->%d (each wants +1) — an assertion helper has been neutered.\n' \
    "$_p0" "$passes" "$_f0" "$fails" "$_l0" "${#FAILURES[@]}" >&2
  exit 1
fi
passes=$_p0; fails=$_f0
if [ "$_l0" -eq 0 ]; then FAILURES=(); else FAILURES=("${FAILURES[@]:0:$_l0}"); fi

# ── 4. Floor and verdict ──────────────────────────────────────────────────────────
# Two assertions always run (extraction, non-vacuity). The third pair runs only where the checker
# discriminates, which is why the floor is 2 and not 4 — and why the SKIP above is loud.
_ran=$((passes + fails))
if [ "$_ran" -lt 2 ]; then
  printf 'FAIL: ran only %d assertion(s) (floor 2) — the suite did not execute fully\n' "$_ran" >&2
  exit 1
fi
if [ "${#FAILURES[@]}" -ne "$fails" ]; then
  printf 'FAIL LEDGER: %d failure(s) counted but %d recorded — fail() was tampered with.\n' "$fails" "${#FAILURES[@]}" >&2
  exit 1
fi
printf '\n=== git-data-nftables-syntax: %d passed, %d failed, %d skipped ===\n' "$passes" "$fails" "$skipped"
exit $(( ${#FAILURES[@]} > 0 ))
