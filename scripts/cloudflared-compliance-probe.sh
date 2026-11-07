#!/usr/bin/env bash
# Offline cloudflared pin-floor census — the observability discoverability probe
# for the 2026-10-27 eMudhra intermediate-CA compromise remediation.
#
# Censuses EVERY cloudflared pin site under .github/ — env-form
# `CLOUDFLARED_VERSION:`/`CLOUDFLARED_SHA256:` pairs AND call-site literal
# `cloudflared-version:`/`cloudflared-sha256:` pairs, in workflows/*.yml and
# actions/*/action.yml alike — and asserts two things:
#   1. every site equals the canonical pin (apply-web-platform-infra.yml's env
#      pair; `${{ env.* }}` self-references resolve through the site's own env
#      pin and count as conformant);
#   2. the canonical version parses and is >= the advisory floor (field-wise
#      NUMERIC compare — lexical lies: `2026.9.0` > `2026.10.2` as strings).
#
# Prints `PINS_OK` and exits 0 when both hold. Otherwise exits non-zero with a
# NAMED verdict per failure, so the signal is never an unnamed rc:
#   PINS_BELOW_FLOOR <ver>        canonical pin is below the advisory floor
#   PINS_DRIFT <file>:<detail>    a site diverges from the canonical pin
#   PINS_HALF_PAIR <loc>:<kind>   version declared with no sha256 (or vice versa)
#   PINS_DANGLING_REF <file>      `${{ env.* }}` ref in a file with no env pin
#   PINS_VACUOUS                  census found fewer sites than the floor
#   PINS_DETECTOR_FAILURE <why>   canonical pin unreadable / inputs missing (rc 2)
#
# Offline by design: reads committed files only, never the network.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GH_DIR="$REPO_ROOT/.github"
CANONICAL_WF="$GH_DIR/workflows/apply-web-platform-infra.yml"
FLOOR="2026.10.2"      # eMudhra advisory floor (Linux); macOS floor is 2026.10.3
MIN_SITES=10           # measured site count on main — a smaller census proves nothing

detector() { echo "PINS_DETECTOR_FAILURE $1" >&2; exit 2; }

[[ -d "$GH_DIR" ]] || detector ".github/ missing at $GH_DIR"
[[ -f "$CANONICAL_WF" ]] || detector "canonical workflow missing at $CANONICAL_WF"

# Field-wise numeric compare: returns 0 iff $1 >= $2, both X.Y.Z (rc 2 = a side
# did not parse — a detector failure, never read as compliant).
version_gte() {
  local a1 a2 a3 b1 b2 b3
  IFS=. read -r a1 a2 a3 <<< "$1"; IFS=. read -r b1 b2 b3 <<< "$2"
  [[ "$a1" =~ ^[0-9]+$ && "$a2" =~ ^[0-9]+$ && "$a3" =~ ^[0-9]+$ ]] || return 2
  [[ "$b1" =~ ^[0-9]+$ && "$b2" =~ ^[0-9]+$ && "$b3" =~ ^[0-9]+$ ]] || return 2
  local i an bn
  for i in 1 2 3; do
    an=$((10#$(eval "echo \$a$i"))); bn=$((10#$(eval "echo \$b$i")))
    (( an > bn )) && return 0
    (( an < bn )) && return 1
  done
  return 0
}

# --- canonical pin ---------------------------------------------------------------
CANON_VER="$(grep -oE '^[[:space:]]*CLOUDFLARED_VERSION:[[:space:]]*"[0-9]+\.[0-9]+\.[0-9]+"' "$CANONICAL_WF" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
CANON_SHA="$(grep -oE '^[[:space:]]*CLOUDFLARED_SHA256:[[:space:]]*"[0-9a-f]{64}"' "$CANONICAL_WF" | grep -oE '[0-9a-f]{64}' | head -1 || true)"
[[ -n "$CANON_VER" && -n "$CANON_SHA" ]] || detector "canonical env pin unreadable in $CANONICAL_WF (version='$CANON_VER' sha='$CANON_SHA')"

# --- census ----------------------------------------------------------------------
# One record per pin TOKEN: file<TAB>form<TAB>kind<TAB>value. A pin declaration
# is a YAML mapping key at line start — a `#`-commented or mid-line mention can
# never satisfy it. `${{ env.X }}` values resolve through the site's own env pin.
PIN_KEY_RE='^[[:space:]]*(CLOUDFLARED_VERSION|CLOUDFLARED_SHA256|cloudflared-version|cloudflared-sha256)[[:space:]]*:'
CENSUS="$({
  find "$GH_DIR/workflows" -maxdepth 1 \( -name '*.yml' -o -name '*.yaml' \) 2>/dev/null
  find "$GH_DIR/actions" -mindepth 2 -maxdepth 2 -name 'action.yml' 2>/dev/null
} | sort | while IFS= read -r f; do
  grep -nE "$PIN_KEY_RE" "$f" 2>/dev/null | while IFS= read -r line; do
    body="${line#*:}"
    # NOTE: the key class must include DIGITS — `SHA256` ends in them; a
    # `[A-Za-z_-]+` class stops at `2` and the strip silently no-ops.
    key="$(printf '%s' "$body" | sed -E 's/^[[:space:]]*([A-Za-z0-9_-]+).*/\1/')"
    val="$(printf '%s' "$body" | sed -E 's/^[[:space:]]*[A-Za-z0-9_-]+[[:space:]]*:[[:space:]]*//; s/[[:space:]]+#.*$//; s/[[:space:]]*$//')"
    # unquote (double or single)
    val="${val%\"}"; val="${val#\"}"; val="${val%\'}"; val="${val#\'}"
    # A bare `key:` with no value is a YAML input DECLARATION (composite
    # action.yml `inputs:` blocks), not a pin site — skip it.
    [[ -z "$val" ]] && continue
    form=env; [[ "$key" =~ ^[a-z] ]] && form=literal
    kind=sha256; [[ "$key" =~ [Vv][Ee][Rr][Ss][Ii][Oo][Nn]$ ]] && kind=version
    printf '%s\t%s\t%s\t%s\n' "${f#$REPO_ROOT/}" "$form" "$kind" "$val"
  done
done)"

LOCATIONS="$(printf '%s\n' "$CENSUS" | grep -c . || true)"

RC=0
emit() { echo "$1"; RC=1; }

if (( LOCATIONS < MIN_SITES )); then
  emit "PINS_VACUOUS only $LOCATIONS pin sites discovered (< $MIN_SITES)"
fi

# Floor check on the canonical pin — before per-site parity, so a coherent
# below-floor fleet reports BELOW_FLOOR rather than a wall of drift.
if ! version_gte "$CANON_VER" "$FLOOR"; then
  emit "PINS_BELOW_FLOOR canonical pin $CANON_VER < advisory floor $FLOOR"
fi

# Per-site parity + dangling-ref detection (herestring — the loop stays in THIS
# shell so emit() moves RC).
while IFS=$'\t' read -r file form kind val; do
  [[ -z "$file" ]] && continue
  if [[ "$val" =~ ^\$\{\{[[:space:]]*env\.(CLOUDFLARED_VERSION|CLOUDFLARED_SHA256)[[:space:]]*\}\}$ ]]; then
    # env.* self-reference: resolves through the file's OWN env pin — conformant
    # iff a CONCRETE (non-${{}}) env token of the same kind exists in that file.
    ref_kind=sha256; [[ "${BASH_REMATCH[1]}" == CLOUDFLARED_VERSION ]] && ref_kind=version
    if ! printf '%s\n' "$CENSUS" | awk -F'\t' -v f="$file" -v k="$ref_kind" '$1==f && $2=="env" && $3==k && $4 !~ /^\$\{\{/ {found=1} END {exit !found}'; then
      emit "PINS_DANGLING_REF $file: $form $kind forwards to env.${BASH_REMATCH[1]} but the file declares no env pin"
    fi
    continue
  fi
  if [[ "$val" =~ ^\$\{\{ ]]; then
    # Any other ${{ }} expression (inputs.*, secrets.*, vars.*) FORWARDS a value
    # supplied elsewhere — conformant by construction; the producer site is
    # itself censused (a caller's literal) or outside the pin-parity property.
    continue
  fi
  want="$CANON_VER"; [[ "$kind" == sha256 ]] && want="$CANON_SHA"
  [[ "$val" == "$want" ]] || emit "PINS_DRIFT $file: $form $kind pin '$val' != canonical '$want'"
done <<< "$CENSUS"

# Pairing: every pin-bearing file+form must carry BOTH kinds. Collected through
# a temp file because the producer loop runs in a pipeline subshell.
PAIR_TMP="$(mktemp)"
trap 'rm -f "$PAIR_TMP"' EXIT
printf '%s\n' "$CENSUS" | cut -f1,2 | sort -u | while IFS=$'\t' read -r file form; do
  [[ -z "$file" ]] && continue
  kinds="$(printf '%s\n' "$CENSUS" | awk -F'\t' -v f="$file" -v m="$form" '$1==f && $2==m {print $3}' | sort -u | tr '\n' ' ')"
  [[ "$kinds" =~ version ]] || echo "$file#$form: version pin missing"
  [[ "$kinds" =~ sha256 ]] || echo "$file#$form: sha256 pin missing"
done > "$PAIR_TMP"
while IFS= read -r p; do
  [[ -n "$p" ]] && emit "PINS_HALF_PAIR $p"
done < "$PAIR_TMP"
rm -f "$PAIR_TMP"

if (( RC == 0 )); then
  echo "PINS_OK sites=$LOCATIONS version=$CANON_VER floor=$FLOOR sha256=${CANON_SHA:0:12}…"
fi
exit "$RC"
