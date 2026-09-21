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
BARE_RE='\$\$[A-Za-z_(]'
bare_dollar_hits() { strip_comments < "$1" | grep -nE "$BARE_RE" || true; }

# --- Instrument self-test (H2/H3): the scanner must accept the legitimate PID use and a
# commented-out match, and must reject both offending shapes. Reported with printf + exit,
# never through pass/fail, so a neutered helper cannot hide it.
printf 'tmp=/tmp/x.$$.lock\n' > "$TMP/h2"
printf '      # an explanatory $$FOO in a stripped comment\n' > "$TMP/h3"
printf 'x=$$FOO\n' > "$TMP/r1"
printf 'y=$$((1+1))\n' > "$TMP/r2"
if [ -n "$(bare_dollar_hits "$TMP/h2")" ] || [ -n "$(bare_dollar_hits "$TMP/h3")" ] \
   || [ -z "$(bare_dollar_hits "$TMP/r1")" ] || [ -z "$(bare_dollar_hits "$TMP/r2")" ]; then
  printf 'FATAL: instrument self-test: the bare-dollar scanner misclassified a fixture.\n' >&2
  exit 2
fi

# --- Dispatch: derive the rendered file set from every templatefile( call site ----------------
DERIVED="$TMP/derived.txt"
: > "$DERIVED"
UNRECOGNISED=0
while IFS= read -r tf; do
  tfdir="$(dirname "$tf")"
  while IFS= read -r arg; do
    case "$arg" in
      '${path.module}/'*)
        rel="${arg#\$\{path.module\}/}"
        (cd "$tfdir" && realpath -m "$rel") >> "$DERIVED"
        ;;
      *)
        UNRECOGNISED=$((UNRECOGNISED + 1))
        printf '  unrecognised templatefile() first argument in %s: %s\n' "$tf" "$arg" >&2
        ;;
    esac
  done < <(grep -oE 'templatefile\("[^"]+"' "$tf" | sed -E 's/^templatefile\("//; s/"$//')
done < <(cd "$INFRA" && git ls-files -- '*.tf' | sed "s|^|$INFRA/|")
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

# --- PATH hardening (security review, Phase 4a) ------------------------------------------------
# Once the inherited PATH is actually appended, a command ABSENT from the literal directory list
# would resolve through a PATH the Doppler config can set, as root. So the heartbeat's external
# command set is DERIVED from its rendered text and pinned: adding a command means a reviewer
# adds it here, against the rule below. Each pinned name is an Ubuntu 24.04 apt binary under
# /usr/bin or /usr/sbin (usrmerge makes /bin and /sbin the same trees), all inside the literal
# `/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin`. Resolution on the image itself
# needs a daemon plus the packages cloud-init installs, which this suite does not assume.
HB_PINNED="awk blkid cat cryptsetup curl cut date df docker findmnt grep head hostname htpasswd journalctl jq lsblk readlink sed tail timeout tr"
cat > "$TMP/cmdwords.py" <<'PY'
import re, shlex, sys

TRIG = {';', '|', '||', '&&', '&', '(', 'then', 'do', 'else', 'elif', 'if', 'while', 'until', '!', '{', '\n'}
WRAPPERS = {'timeout', 'nohup', 'env', 'exec', 'command', 'xargs', 'nice', 'ionice'}
NAME = re.compile(r'^[A-Za-z_][A-Za-z0-9_.+-]*$')
ASSIGN = re.compile(r'^[A-Za-z_][A-Za-z0-9_]*(\[[^]]*\])?\+?=')


def close(text, i, op, cl, depth):
    sq = dq = False
    n = len(text)
    while i < n and depth:
        c = text[i]
        if c == '\\' and not sq:
            i += 2; continue
        if c == "'" and not dq:
            sq = not sq
        elif c == '"' and not sq:
            dq = not dq
        elif not sq and not dq:
            if c == op:
                depth += 1
            elif c == cl:
                depth -= 1
        elif dq and text.startswith('$(', i):
            i = close(text, i + 2, '(', ')', 1); continue
        i += 1
    return i


def cut_expansions(text, bodies):
    # Cut $(...) (collecting the body) and ${...} out of the RAW text, quote-aware. Cutting them
    # from lexed tokens would scan bodies whose quotes are already gone.
    out, i, n = [], 0, len(text)
    sq = dq = False
    while i < n:
        c = text[i]
        if c == '\\' and not sq and i + 1 < n:
            out.append(text[i:i + 2]); i += 2; continue
        if c == "'" and not dq:
            sq = not sq; out.append(c); i += 1; continue
        if c == '"' and not sq:
            dq = not dq; out.append(c); i += 1; continue
        if not sq and text.startswith('$((', i):
            i = close(text, i + 3, '(', ')', 2); out.append('__A__'); continue
        if not sq and text.startswith('$(', i):
            j = close(text, i + 2, '(', ')', 1)
            bodies.append(text[i + 2:j - 1]); out.append('__S__'); i = j; continue
        if not sq and text.startswith('${', i):
            i = close(text, i + 2, '{', '}', 1); out.append('__P__'); continue
        out.append(c); i += 1
    return ''.join(out)


def scan(text, ignore, found, funcs):
    bodies = []
    text = cut_expansions(text, bodies)
    for b in bodies:
        scan(b, ignore, found, funcs)
    lex = shlex.shlex(text.replace('\n', ' \n '), posix=True, punctuation_chars=True)
    lex.whitespace = ' \t'
    lex.commenters = '#'
    toks = list(lex)
    pos, wrap = True, False
    case_depth, in_pattern, want_in = 0, False, False
    for idx, t in enumerate(toks):
        nxt = toks[idx + 1] if idx + 1 < len(toks) else ''
        if t == 'case':
            case_depth += 1; want_in = True; pos = False; continue
        if want_in:
            if t == 'in':
                want_in = False; in_pattern = True
            continue
        if t == 'esac':
            case_depth -= 1; in_pattern = False; pos = False; continue
        if in_pattern:
            if t == ')':
                in_pattern = False; pos = True
            continue
        if t == ';;':
            in_pattern = case_depth > 0; pos = not in_pattern; continue
        if t in TRIG:
            pos, wrap = True, False; continue
        if not pos:
            continue
        if ASSIGN.match(t):
            continue
        if wrap and (t.startswith('-') or re.match(r'^[0-9]+[smhd]?$', t)):
            continue
        pos, wrap = False, False
        if not NAME.match(t) or t in ignore:
            continue
        if nxt == '()' or (nxt == '(' and idx + 2 < len(toks) and toks[idx + 2] == ')'):
            funcs.add(t); continue
        found.add(t)
        if t in WRAPPERS:
            pos, wrap = True, True


ignore = set(open(sys.argv[1]).read().split())
found, funcs = set(), set()
scan(sys.stdin.read(), ignore, found, funcs)
print(' '.join(sorted(found - funcs)))
PY
bash --noprofile --norc -c 'compgen -b; compgen -k' | sort -u > "$TMP/ignore.txt"

# The derivation's own self-test: a known script must yield exactly its external commands.
printf 'x=$(foo a | bar "$(baz)")\nqux() { quux; }\nqux\ntimeout -k 2 5 zed arg\ncase "$a" in\n  one|two) three ;;\n  *) four ;;\nesac\nLC_ALL=C sort x\n' > "$TMP/cw-fixture.sh"
CW_SELF="$(python3 "$TMP/cmdwords.py" "$TMP/ignore.txt" < "$TMP/cw-fixture.sh")"
if [ "$CW_SELF" != "bar baz foo four quux sort three timeout zed" ]; then
  printf 'FATAL: instrument self-test: command-word derivation returned [%s].\n' "$CW_SELF" >&2
  exit 2
fi

awk -v want="  - path: /usr/local/bin/zot-disk-heartbeat.sh" '
  $0 == want { found = 1; next }
  found && /^    content: \|$/ { incontent = 1; next }
  incontent {
    if ($0 ~ /^      /) { print substr($0, 7); next }
    if ($0 ~ /^[[:space:]]*$/) { print ""; next }
    exit
  }' "$REG_YML" | strip_comments | sed 's|[$][$][{]|${|g' > "$TMP/hb.sh"
HB_DERIVED="$(python3 "$TMP/cmdwords.py" "$TMP/ignore.txt" < "$TMP/hb.sh")"
cases=$((cases + 1))
if [ "$HB_DERIVED" = "$HB_PINNED" ]; then
  pass "heartbeat external command set equals the pinned, literal-PATH-resolvable set"
else
  fail "heartbeat external command set changed -- review each new name against the literal PATH list: derived [$HB_DERIVED] pinned [$HB_PINNED]"
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
MIN_CASES=17
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
