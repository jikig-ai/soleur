#!/usr/bin/env bash
# Guard 1 (#8417): no file rendered through templatefile() carries a bare `$$` where a shell
# variable was meant.
#
# THE DEFECT CLASS. Terraform's templatefile() has exactly two escapes, `$${` -> `${` and
# `%%{` -> `%{`. A `$$` NOT followed by `{` is passed through VERBATIM, and bash then reads it as
# the PID. So `cs$$_cs_rc` shipped as `cs<pid>_cs_rc` -- a PID where an exit code was meant --
# and `$${PATH:+:$$PATH}` shipped as `${PATH:+:$$PATH}`, which appended `:<pid>PATH` and never
# the inherited PATH. Both sat two lines from a correct `$${…}` in the same block, which is why
# they read as correct. The cloud-init-inngest.yml #7695 comment block records the same class
# biting another host.
#
# PROPERTY. No non-comment line of any file rendered through templatefile() in
# apps/web-platform/infra/**/*.tf contains `$$` immediately followed by an identifier-start
# character or `(`. A `$$` followed by anything else is a legitimate PID use (`/tmp/x.$$.`).
#
# ASSEMBLY. The file set is DERIVED from the templatefile( call sites, resolving
# ${path.module} against EACH .tf file's own directory -- modules/git-data-userdata/main.tf
# renders ../../cloud-init-git-data.yml, which a top-level-only glob would miss. Comment lines
# are removed with the registry_rationale_strip regex, exactly as the render removes them.
#
# Needs only bash, git, grep, sed, awk and python3. No terraform, docker, network or root.

export TMPDIR="${TMPDIR:-/var/tmp}"
set -uo pipefail
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA="$SCRIPT_DIR"
REG_YML="$INFRA/cloud-init-registry.yml"

TMP="$(mktemp -d "${TMPDIR}/tf-bare-dollar.XXXXXXXX")" || { printf 'FATAL: mktemp failed\n' >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

passes=0
fails=0
cases=0
pass() { passes=$((passes + 1)); printf 'ok   - %s\n' "$1"; }
fail() { fails=$((fails + 1)); printf 'FAIL - %s\n' "$1" >&2; }

# The comment strip, replicated from zot-registry.tf's
# registry_rationale_strip = "/(?m)^[ \t]*#([ \t][^\n]*)?\n/".
# [[:blank:]] is exactly space+tab, matching RE2's [ \t].
strip_comments() { sed -E '/^[[:blank:]]*#([[:blank:]].*)?$/d'; }

# bare_dollar_hits <file> -> prints every offending non-comment line, numbered.
# Identifier-start or `(` (the #8417 shapes), plus a digit and the special parameters ? ! # @ * -
# (`$$?` / `$$1` also reach bash as the PID where an exit code or argument was meant).
BARE_RE='\$\$[A-Za-z_(0-9?!#@*-]'
bare_dollar_hits() { strip_comments < "$1" | grep -nE "$BARE_RE" || true; }

# --- Instrument self-test (H2/H3): the scanner must accept the legitimate PID use and a
# commented-out match, and must reject both offending shapes. Reported with printf + exit,
# never through pass/fail, so a neutered helper cannot hide it.
printf 'tmp=/tmp/x.$$.lock\n' > "$TMP/h2"
printf '      # an explanatory $$FOO in a stripped comment\n' > "$TMP/h3"
printf 'x=$$FOO\n' > "$TMP/r1"
printf 'y=$$((1+1))\n' > "$TMP/r2"
printf 'z=$$?\n' > "$TMP/r3"
if [ -n "$(bare_dollar_hits "$TMP/h2")" ] || [ -n "$(bare_dollar_hits "$TMP/h3")" ] \
   || [ -z "$(bare_dollar_hits "$TMP/r1")" ] || [ -z "$(bare_dollar_hits "$TMP/r2")" ] \
   || [ -z "$(bare_dollar_hits "$TMP/r3")" ]; then
  printf 'FATAL: instrument self-test: the bare-dollar scanner misclassified a fixture.\n' >&2
  exit 2
fi

# --- Dispatch: derive the rendered file set from every templatefile( call site ----------------
DERIVED="$TMP/derived.txt"
# Every tracked .tf in the repo (not just this root), parsed with a multi-line-aware regex. Every
# `templatefile(` / `templatestring(` token must resolve to a `${path.module}/<literal>` first
# argument; anything else (a split line the regex still resolves is fine; a variable, a local, a
# templatestring) is counted UNRECOGNISED, so a new call site can never silently leave the set.
REPO_ROOT="$(cd "$INFRA" && git rev-parse --show-toplevel)"
DERIVE_OUT="$(cd "$REPO_ROOT" && git ls-files -z -- '*.tf' | python3 -c '
import os, re, sys
tok = re.compile(r"\b(templatefile|templatestring)\s*\(")
lit = re.compile(r"\btemplatefile\s*\(\s*\"\$\{path\.module\}/([^\"]+)\"", re.S)
def strip_hcl_comments(t):
    # Drop # and // line comments and /* */ blocks, outside double-quoted strings, so prose that
    # names templatefile() is neither a call site nor an unrecognised one.
    out, i, n, q = [], 0, len(t), False
    while i < n:
        c = t[i]
        if q:
            out.append(c)
            if c == "\\" and i + 1 < n:
                out.append(t[i + 1]); i += 2; continue
            if c == "\"":
                q = False
            i += 1; continue
        if c == "\"":
            q = True; out.append(c); i += 1; continue
        if c == "#" or t.startswith("//", i):
            j = t.find("\n", i); i = n if j < 0 else j; continue
        if t.startswith("/*", i):
            j = t.find("*/", i + 2); i = n if j < 0 else j + 2; continue
        out.append(c); i += 1
    return "".join(out)
paths = [p for p in sys.stdin.read().split("\0") if p]
unrec = 0
for p in paths:
    t = strip_hcl_comments(open(p, encoding="utf-8", errors="replace").read())
    n_tok = len(tok.findall(t))
    hits = lit.findall(t)
    unrec += n_tok - len(hits)
    for rel in hits:
        print("F " + os.path.normpath(os.path.join(os.path.abspath(os.path.dirname(p)), rel)))
print("U %d" % unrec)
')" || { printf 'FATAL: templatefile call-site derivation failed.\n' >&2; exit 2; }
printf '%s\n' "$DERIVE_OUT" | sed -n 's/^F //p' > "$DERIVED"
UNRECOGNISED="$(printf '%s\n' "$DERIVE_OUT" | sed -n 's/^U //p')"
[[ "$UNRECOGNISED" =~ ^[0-9]+$ ]] || { printf 'FATAL: derivation printed no unrecognised count.\n' >&2; exit 2; }
sort -u -o "$DERIVED" "$DERIVED"
DERIVED_N="$(wc -l < "$DERIVED" | tr -d ' ')"

cases=$((cases + 1))
if [ "$UNRECOGNISED" -eq 0 ]; then
  pass "every templatefile() call site names its template via \${path.module}/ (0 unrecognised)"
else
  fail "$UNRECOGNISED templatefile() call site(s) use a first argument this guard cannot resolve"
fi

# --- Scan -----------------------------------------------------------------------------------
files_scanned=0
: > "$TMP/scanned.txt"
while IFS= read -r f; do
  cases=$((cases + 1))
  if [ ! -f "$f" ]; then
    fail "derived template does not exist: ${f#"$INFRA"/}"
    continue
  fi
  files_scanned=$((files_scanned + 1))
  printf '%s\n' "$f" >> "$TMP/scanned.txt"
  hits="$(bare_dollar_hits "$f")"
  if [ -z "$hits" ]; then
    pass "no bare \$\$<ident> in ${f#"$INFRA"/}"
  else
    fail "bare \$\$<ident> in ${f#"$INFRA"/} (Terraform passes it through; bash reads the PID):"
    printf '%s\n' "$hits" | sed 's/^/        /' >&2
  fi
done < "$DERIVED"

# Set identity: every derived template was scanned, and nothing else was.
cases=$((cases + 1))
if cmp -s "$DERIVED" "$TMP/scanned.txt"; then
  pass "set identity: the scanned set equals the ${DERIVED_N}-file set derived from the .tf call sites"
else
  fail "set identity: scanned set differs from the derived set"
fi

# --- Rendered-shape assert for store_probe_rc (#8417, P5) ------------------------------------
# Render the shipped assignment the way templatefile does (`$${` -> `${`, a bare `$$` left
# verbatim), then EXECUTE it. Asserting the spelling is what let the defect ship.
PROBE_LINE="$(grep -E '^[[:blank:]]+STORE_PROBE_RC="cs' "$REG_YML" | head -1 | sed -E 's/^[[:blank:]]+//; s/[$][$][{]/${/g')"
cases=$((cases + 1))
if [ -n "$PROBE_LINE" ]; then pass "STORE_PROBE_RC assignment found in the registry template"
else fail "STORE_PROBE_RC assignment not found in the registry template"; fi
render_probe() { # <cs_rc> <bk_rc>
  env -i /bin/bash --noprofile --norc -c "_cs_rc='$1'; _bk_rc='$2'; $PROBE_LINE; printf '%s' \"\$STORE_PROBE_RC\"" 2>/dev/null
}
for pair in '127 na cs127.bkna' '0 0 cs0.bk0' 'na na csna.bkna' '124 2 cs124.bk2'; do
  read -r cs bk want <<<"$pair"
  got="$(render_probe "$cs" "$bk")"
  cases=$((cases + 1))
  if [ "$got" = "$want" ] && [[ "$got" =~ ^cs([0-9]+|na)\.bk([0-9]+|na)$ ]]; then
    pass "rendered STORE_PROBE_RC with _cs_rc=$cs _bk_rc=$bk is exactly $want"
  else
    fail "rendered STORE_PROBE_RC with _cs_rc=$cs _bk_rc=$bk: want '$want', got '$got'"
  fi
done

# _bk_rc must be reset to 0 before blkid runs, as _cs_rc is before cryptsetup: the capture
# only writes on FAILURE, so without the reset a healthy host reports `bkna` ("never ran").
cases=$((cases + 1))
if awk '/^[[:blank:]]+_bk_rc=0$/ { reset = NR } /blkid -o value -s TYPE/ { if (reset && NR > reset && NR - reset <= 3) ok = 1 } END { exit ok ? 0 : 1 }' "$REG_YML"; then
  pass "_bk_rc=0 is set immediately before the blkid call (a healthy host reads bk0, not bkna)"
else
  fail "_bk_rc=0 is not set immediately before the blkid call"
fi

# --- Anti-vacuity floors: printf + exit, never through fail() (ADR-193). -------------------------
# The file floor catches a derivation that silently SHRINKS, which set identity cannot see: the
# identity check measures the scan against the same derivation. 8 is the measured count on
# 2026-09-21, including the git-data module's template.
MIN_FILES=8
if [ "$files_scanned" -lt "$MIN_FILES" ]; then
  printf '\n[FATAL] floor: only %s templatefile() source(s) scanned (expected >= %s).\n' "$files_scanned" "$MIN_FILES" >&2
  exit 1
fi
MIN_CASES=16
if [ "$cases" -lt "$MIN_CASES" ]; then
  printf '\n[FATAL] floor: only %s cases ran (expected >= %s).\n' "$cases" "$MIN_CASES" >&2
  exit 1
fi
if [ $((passes + fails)) -ne "$cases" ]; then
  printf '\n[FATAL] conservation: pass+fail (%s) != cases (%s).\n' "$((passes + fails))" "$cases" >&2
  exit 1
fi

printf '\n%s passed, %s failed (%s cases, %s templates)\n' "$passes" "$fails" "$cases" "$files_scanned"
[ "$fails" -eq 0 ]
