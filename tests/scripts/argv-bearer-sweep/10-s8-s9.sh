# shellcheck shell=bash
# SOURCED FRAGMENT of tests/scripts/test-argv-bearer-sweep.sh -- NOT independently runnable.
# =====================================================================================
# STAGE S8 (argv-bearer sweep, Guard 3, #9757): no registry LOGIN command carries a password on argv.
#
# PROPERTY. No tracked, non-test, non-comment registry login invocation (`crane auth login`, `docker login`, `podman login`, and the variable
# spellings of those binaries: `$CRANE auth login`, `"$DOCKER_BIN" login`) passes a password as an argument: no option token is `-p`, `--password`,
# `--password=<v>`, a glued `-p<value>` or a short cluster holding p (`-up`), in any order relative to the host. `--password-stdin` never matches.
#
# WHY A VARIABLE-AWARE VERB. The restore engine spells its login `$CRANE auth login` (a variable, for the test seam). A scan keyed on the literal
# `crane` sees ZERO engine sites and stays green over the file this stage exists for; the floor row and mutation 8 exist for that.
#
# DERIVATION. One python3 pass (scan.py) over `git ls-files --cached --others --exclude-standard` of a root, minus `*.test.*`, any path with a
# `test`, `tests` or `fixtures` directory, and `knowledge-base/` (the exclusion is by path component at ANY depth: a production script under a directory
# named `test` is invisible); `.md` joins only under `plugins/` (stage S7 treats agent-run markdown as a
# surface). Backslash-continuation lines are joined (a comment line is never continued). Each logical line is TOKENISED with a quote-,
# `$(...)`-, backtick- and `${{ ... }}`-aware splitter: operators (`&&`, `||`, `;`, `|`, `&`, redirections, `)`) end an invocation, a `#` at a word
# start ends the line, and a quoted string is one token, so a prose `docker login` inside an echo, a grep pattern or an alias is not a command. A
# login found INSIDE a `$(...)` or backtick span, or inside a quoted payload that a shell runs (`bash -c`/`-lc`, `eval`, a YAML `run:`/`command:`
# value, `ssh host "..."`, an `exec`-style call), is scanned recursively; any other quoted string is prose. An invocation is a verb, optional
# global flags, an optional `auth`, `login`, then its arguments: it is BAD when any argument is a password option (whatever the host count), and it
# is a SITE (counted against the floor) when it has exactly one host and at least one option. The scan is a FUNCTION OF A ROOT, so the mutation
# rows run the same text on a scratch repository.
#
# NAMED BLIND SPOTS (stated, not hidden): clients that are not crane/docker/podman or a variable named for them (skopeo, oras, regctl, buildah,
# nerdctl, cosign, `helm registry login`; no site exists today), a variable verb with none of those names (`$ENGINE`, `$CTR`), arguments held in a
# variable or array (`"${LOGIN_ARGS[@]}"`), a flag-variable (`$SINK_TLS_FLAG`, anything ending FLAG, FLAGS, OPTS or OPTIONS) that itself carries
# `-p`, a command built by concatenation or an `eval`ed string, a payload inside any other quoted string (e.g. a YAML list item), a YAML folded `>` block, a backslash followed by
# a space or CRLF, a FEEDER that itself carries the token on argv (`/usr/bin/printf '%s' "$T" |`), and the excluded trees. S8 stays full-run-only (CTO ruling D1): its population is the whole tree, so no declared edge could name it. Editing the affected-test array
# degrades a LOCAL `--affected` run to the full battery; S9 (below) accepts that cost once, for its one workflow edge.
#
# FLOOR. The scan sees 12 sites in 7 files on the real tree (measured when this stage was written): 10 already `--password-stdin` (one is a plugin
# doc snippet) and the engine's 2 `$CRANE` lines. A scan that sees fewer (a renamed binary, moved roots, a broken regex) is RED, never a clean bill.
# Retiring a legitimate login site is a floor edit in the same change. No allowlist: there is no residual.
# =====================================================================================
S8_SITE_FLOOR=12; S8_FILE_FLOOR=7
S8="$TMPD/s8"; assert_fixture_dir "$S8"; mkdir -p "$S8/base" "$S8/mut"
cat > "$S8/scan.py" <<'S8PY'
import os, re, subprocess, sys
root = sys.argv[1]
VERB = re.compile(
    r'^(?:.*/)?(?:crane|docker|podman)(?:_[a-z_]*)?$'
    r'|^\$\{?[A-Za-z_]*(?:crane|docker|podman)[A-Za-z_]*(?:\[[@*]\])?\}?$'
    r'|^\$\{[A-Za-z_]+:[-=]?(?:crane|docker|podman)\}$'
    r'|^\$\(command -v (?:crane|docker|podman)\)$', re.I)
VALUED = {"-u", "--username", "-p", "--password", "--config", "--authfile", "--cert-dir", "--registry-config", "-e", "--email"}
# A bare flag-variable (`$SINK_TLS_FLAG`) expands to an option or to nothing: neither the host nor a visible option.
NEUTRAL = re.compile(r'^"?\$\{?[A-Za-z_]*(?:FLAG|FLAGS|OPTS|OPTIONS)\}?"?$', re.I)
PLACEHOLDER = re.compile(r"<[A-Za-z][\w.\- ]*>")
CLUSTER_C = re.compile(r"^-[A-Za-z]*c$")
PAYLOAD_KEYS = ("run:", "command:", "script:", "cmd:", "entrypoint:")
EXEC_CALLS = re.compile(r"^(?:exec|execSync|execFile|system|popen|run|call|check_output|check_call|Popen|Command)$")
REDIRS = {"\0>", "\0>>", "\0<", "\0<<", "\0<<<", "\0&>", "\0>&"}
OPS = ("&&", "||", "<<<", "<<", ">>", "&>", ">&", ";", "|", ">", "<", "&", ")", "(")


def tokens(s):
    """Quote-, $(..)-, ${{..}}- and backtick-aware split. Operators come back as \\0-prefixed tokens; a `#` at a word start ends the line."""
    out, cur, i, n, q, angle = [], [], 0, len(s), None, False

    def flush():
        if cur:
            out.append("".join(cur))
            cur.clear()

    while i < n:
        c = s[i]
        if q:
            cur.append(c)
            if c == "\\" and q == '"' and i + 1 < n:
                cur.append(s[i + 1])
                i += 2
                continue
            if c == q:
                q = None
            i += 1
            continue
        if s.startswith("${{", i):
            j = s.find("}}", i)
            j = n if j < 0 else j + 2
            cur.append(s[i:j])
            i = j
            continue
        if s.startswith("$(", i):
            d, j = 1, i + 2
            while j < n and d:
                d += (s[j] == "(") - (s[j] == ")")
                j += 1
            cur.append(s[i:j])
            i = j
            continue
        if c == "`":
            j = s.find("`", i + 1)
            j = n if j < 0 else j + 1
            cur.append(s[i:j])
            i = j
            continue
        if c in "\"'":
            q = c
            cur.append(c)
            i += 1
            continue
        if c.isspace():
            flush()
            i += 1
            continue
        if c == "#" and not cur:
            break
        if c == "<" and not cur and PLACEHOLDER.match(s, i):
            angle = True  # a `<placeholder>` in a doc, not a redirection
        if angle:
            cur.append(c)
            if c == ">":
                angle = False
            i += 1
            continue
        fd = cur and "".join(cur).isdigit() and s[i:i + 1] in "<>"
        op = next((o for o in OPS if s.startswith(o, i)), None)
        if op:
            if fd:
                cur.clear()
            flush()
            out.append("\0" + op)
            i += len(op)
            continue
        cur.append(c)
        i += 1
    flush()
    return out


def unq(t):
    return t[1:-1] if len(t) > 1 and t[0] in "\"'" and t[-1] == t[0] else t


SHELLS = {"sh", "bash", "zsh", "dash", "ksh", "su"}


def subs(t, md=False):
    """The bodies of every balanced $( ... ) span inside one token, and its backtick spans (never in markdown inline code or single quotes)."""
    out, i = ([] if md or t[:1] == "'" else [x[1:-1] for x in re.findall(r"`[^`]*`", t)]), 0
    while True:
        i = t.find("$(", i)
        if i < 0:
            return out
        d, j = 1, i + 2
        while j < len(t) and d:
            d += (t[j] == "(") - (t[j] == ")")
            j += 1
        out.append(t[i + 2:j - 1])
        i = j


def payload_context(toks, i):
    """Is toks[i] (a quoted string) code that a shell will run, rather than prose?"""
    prev = toks[i - 1] if i else ""
    if prev == "--" and i > 1:
        prev = toks[i - 2]
    start = i
    while start and toks[start - 1][:1] != "\0":
        start -= 1  # the first token of the command this string belongs to
    words = [unq(x) for x in toks[start:i]]
    if CLUSTER_C.match(prev) and any(w in SHELLS for w in words):
        return True
    if prev == "eval" or prev in PAYLOAD_KEYS or ("ssh" in words and not prev.startswith("-")):
        return True
    return prev == "\0(" and i > 1 and bool(EXEC_CALLS.match(toks[i - 2].split(".")[-1]))


def scan_line(code, depth=0, md=False):
    toks, recs, i = tokens(code), [], 0
    while i < len(toks):
        t = toks[i]
        if depth < 3 and t[:1] != "\0" and ("$(" in t or "`" in t):
            for inner in subs(t, md):
                recs += scan_line(inner, depth + 1, md)  # a login inside a command substitution
        if depth < 2 and t[:1] in "\"'" and payload_context(toks, i):
            recs += scan_line(unq(t), depth + 1, md)  # bash -lc "docker login ..." / eval "..." / run: '...' / ssh host "..." / execSync("...")
        if t[:1] == "\0" or not VERB.match(unq(t)):
            i += 1
            continue
        k, found = i + 1, False
        lead = 2 if "_" in unq(t) and t[:1] != "$" else 0  # a wrapper (crane_capture <out> <err> auth login ...) takes two bare words first
        while k < len(toks) and k < i + 8 and toks[k][:1] != "\0":
            u = unq(toks[k])
            if u == "login":
                found = True
                break
            if u == "auth":
                k += 1
                continue
            if not u.startswith("-"):
                if lead:
                    lead -= 1
                    k += 1
                    continue
                break
            k += 1
            if k < len(toks) and toks[k][:1] != "\0" and unq(toks[k]) not in ("auth", "login") and not unq(toks[k]).startswith("-"):
                k += 1
        if not found:
            i += 1
            continue
        j, opts, hosts, bad = k + 1, [], 0, False
        while j < len(toks):
            if toks[j][:1] == "\0":
                if toks[j] in REDIRS:  # a redirection may sit anywhere in the argument list: skip it and its target (never an option)
                    j += 2 if j + 1 < len(toks) and not unq(toks[j + 1]).startswith("-") else 1
                    continue
                break
            u = unq(toks[j])
            if u.startswith("-"):
                opts.append(u)
                glued_user = u.startswith("-u") and not u.startswith("--") and len(u) > 3  # -ujpierre is a username; -up is treated as a cluster (conservative)
                if u in ("-p", "--password") or u.startswith("--password=") or (re.match(r"^-[A-Za-z]*p", u) and not u.startswith("--") and not glued_user):
                    bad = True
                if u in VALUED or (u == "--tls-verify" and j + 1 < len(toks) and unq(toks[j + 1]) in ("true", "false")):
                    j += 1
            elif NEUTRAL.match(toks[j]):
                pass
            else:
                hosts += 1
            j += 1
        if bad or (hosts == 1 and opts):
            recs.append((" ".join(opts), "1" if bad else "0"))
        i = j
    return recs


out = subprocess.run(["git", "-C", root, "ls-files", "-z", "--cached", "--others", "--exclude-standard"], capture_output=True, check=True)
for rel in out.stdout.decode("utf-8", "replace").split("\0"):
    parts = rel.split("/")
    if not rel or rel.endswith(".test.sh") or ".test." in parts[-1] or "test" in parts[:-1] or "tests" in parts[:-1] or "fixtures" in parts[:-1] or parts[0] == "knowledge-base":
        continue
    if rel.endswith(".md") and parts[0] != "plugins":
        continue
    try:
        data = open(os.path.join(root, rel), "rb").read()
    except OSError:
        continue
    if b"\0" in data[:8192] or b"login" not in data.lower():
        continue
    lines = data.decode("utf-8", "replace").split("\n")
    i = 0
    while i < len(lines):
        start, cur = i + 1, lines[i]
        while cur.endswith("\\") and not cur.lstrip().startswith("#") and i + 1 < len(lines):
            i += 1
            cur = cur[:-1] + " " + lines[i].strip()
        i += 1
        if "login" not in cur.lower():
            continue
        for opts, bad in scan_line(cur.strip(), 0, rel.endswith(".md")):
            print("\t".join([rel, str(start), opts, bad, cur.strip()]))
S8PY
s8_scan() { python3 -I "$S8/scan.py" "$1"; } # <root>: one TSV record per invocation: file, line, options, bad(0|1), code
S8_J_REASONS=""; S8_J_SITES=0; S8_J_FILES=0; S8_J_DETAIL=""
s8_judge_text() { # <scan text>: sets S8_J_REASONS (empty = GREEN), S8_J_SITES, S8_J_FILES, S8_J_DETAIL. Reasons: floor, bad:<file>
  local f
  S8_J_REASONS=""
  S8_J_SITES="$(grep -c . <<<"$1" || true)"
  S8_J_FILES="$(cut -f1 <<<"$1" | sort -u | grep -c . || true)"
  S8_J_DETAIL="$(awk -F'\t' '$4 == 1 { print $1 ":" $2 }' <<<"$1" | tr '\n' ' ')"
  [[ "$S8_J_SITES" -ge "$S8_SITE_FLOOR" && "$S8_J_FILES" -ge "$S8_FILE_FLOOR" ]] || S8_J_REASONS+=" floor"
  while IFS= read -r f; do [[ -n "$f" ]] && S8_J_REASONS+=" bad:$f"; done < <(awk -F'\t' '$4 == 1 { print $1 }' <<<"$1" | sort -u)
  S8_J_REASONS="${S8_J_REASONS# }"
}
s8_judge() { s8_judge_text "$(s8_scan "$1")"; } # <root>
( source "$REPO_ROOT/plugins/soleur/test/lib/git-fixture-env.sh" && git_fixture_env "$S8/base" || exit 1; git -C "$S8/base" init -q ) \
  || fatal "S8 could not create the scratch repository"
S8_REAL_SCAN="$(s8_scan "$REPO_ROOT")"
S8_ENGINE="scripts/registry-restore-from-ghcr.sh"
S8_CONT="apps/web-platform/infra/cloud-init-inngest.yml"
# The base copies EVERY file the floor counts (a partial base would trip the floor and turn every mutant RED for the wrong reason).
while IFS= read -r f; do [[ -n "$f" ]] || continue; mkdir -p "$S8/base/$(dirname "$f")"; cp "$REPO_ROOT/$f" "$S8/base/$f"; done < <(cut -f1 <<<"$S8_REAL_SCAN" | sort -u)
s8_fresh() { local d="$S8/mut/$1"; assert_fixture_dir "$d"; rm -rf "${d:?}"; cp -a "$S8/base" "$d" && printf '%s' "$d"; } # <name>: prints a new root
s8_put() { assert_fixture_dir "$1"; mkdir -p "$1/$(dirname "$2")"; printf '%s\n' "$3" > "$1/$2"; } # <root> <relative path> <content>
s8_edit() { s6_edit "$@" || fatal "S8 mutation did not land: $2"; } # <file> <old> <new> [<count>]: replace exactly <count> occurrences or abort the suite
s8_has() { [[ " $S8_J_REASONS " == *" $1 "* ]]; } # <reason>: the last judgement carried that reason
s8_recs() { s8_scan "$1" | awk -F'\t' -v f="$2" -v b="$3" '$1 == f && ($4 == b || b == "") { n++ } END { print n + 0 }'; } # <root> <file> <bad: 0|1|empty>: record count

s8_judge_text "$S8_REAL_SCAN"
S8_REAL_REASONS="$S8_J_REASONS"; S8_REAL_SITES="$S8_J_SITES"; S8_REAL_FILES="$S8_J_FILES"
if [[ -z "$S8_REAL_REASONS" ]]; then row "S8 Guard 3: no tracked registry login (crane, docker, podman, in literal or variable spelling) carries a password on argv ($S8_REAL_SITES invocations in $S8_REAL_FILES files, derived over the whole tracked tree)" ok
else row "S8 Guard 3: a registry login invocation carries a password on argv, or the scan saw fewer sites than its floor" fail "reasons='$S8_REAL_REASONS' at=$S8_J_DETAIL sites=$S8_REAL_SITES files=$S8_REAL_FILES"; fi
if [[ "$S8_REAL_SITES" -ge "$S8_SITE_FLOOR" && "$S8_REAL_FILES" -ge "$S8_FILE_FLOOR" ]]; then row "S8 floor: the scan saw $S8_REAL_SITES invocations in $S8_REAL_FILES files (the floor is $S8_SITE_FLOOR sites in $S8_FILE_FLOOR files: the stdin-form sites plus the engine's 2 \$CRANE lines)" ok
else row "S8 floor: the scan saw fewer than $S8_SITE_FLOOR sites in $S8_FILE_FLOOR files (a renamed binary, moved roots or a broken scanner)" fail "sites=$S8_REAL_SITES files=$S8_REAL_FILES"; fi
S8_ENG_N="$(awk -F'\t' -v f="$S8_ENGINE" '$1 == f { n++ } END { print n + 0 }' <<<"$S8_REAL_SCAN")"
S8_ENG_BAD="$(awk -F'\t' -v f="$S8_ENGINE" '$1 == f && ($4 == 1 || $3 !~ /--password-stdin/) { n++ } END { print n + 0 }' <<<"$S8_REAL_SCAN")"
if [[ "$S8_ENG_N" -eq 2 && "$S8_ENG_BAD" -eq 0 ]]; then row "S8 engine: scripts/registry-restore-from-ghcr.sh holds exactly 2 login invocations (the sink and GHCR, spelled \$CRANE) and both carry --password-stdin and no password flag" ok
else row "S8 engine: the restore engine's two \$CRANE login lines were not both seen in the --password-stdin form" fail "engine-sites=$S8_ENG_N not-stdin-or-bad=$S8_ENG_BAD"; fi

# --- the baseline-GREEN control: the scratch base is judged by the SAME function and must be green ---------------------------------
s8_judge "$S8/base"
if [[ -z "$S8_J_REASONS" && "$S8_J_SITES" -eq "$S8_REAL_SITES" && "$S8_J_FILES" -eq "$S8_REAL_FILES" ]]; then row "S8 control: the scratch base (a copy of every file the floor counts) is judged GREEN with the real tree's site and file counts, so every mutant below is RED for its mutation alone" ok
else row "S8 control: the scratch base is not GREEN with the real counts (every mutant below would be measuring the base)" fail "reasons='$S8_J_REASONS' sites=$S8_J_SITES/$S8_REAL_SITES files=$S8_J_FILES/$S8_REAL_FILES"; fi

# --- mutation 1: either engine login reverted to the password on argv -------------------------------------------------------------
d="$(s8_fresh m1a)"; s8_edit "$d/$S8_ENGINE" '--password-stdin $SINK_TLS_FLAG' '-p "$ZOT_PUSH_TOKEN" $SINK_TLS_FLAG'; s8_judge "$d"; m1a="$S8_J_REASONS"
d="$(s8_fresh m1b)"; s8_edit "$d/$S8_ENGINE" '-u "$GHCR_USER" --password-stdin' '-u "$GHCR_USER" -p "$GHCR_TOKEN"'; s8_judge "$d"; m1b="$S8_J_REASONS"
if [[ "$m1a" == "bad:$S8_ENGINE" && "$m1b" == "bad:$S8_ENGINE" ]]; then row "S8 mutation 1: reverting either engine login (sink, GHCR) to -p \"\$X\" is RED, reason bad:$S8_ENGINE and nothing else" ok
else row "S8 mutation 1: an engine login reverted to -p argv was not judged exactly bad:$S8_ENGINE" fail "sink='$m1a' ghcr='$m1b'"; fi

# --- mutation 2: every spelling of the password option, in the engine's own line and in option orders a regex would miss -------------
m2=""; n2=0
for v in '--password "$ZOT_PUSH_TOKEN"' '--password=$ZOT_PUSH_TOKEN' '-p"$ZOT_PUSH_TOKEN"' '-pXYZ' '-up "$ZOT_PUSH_TOKEN"'; do
  n2=$((n2 + 1)); d="$(s8_fresh m2-$n2)"; s8_edit "$d/$S8_ENGINE" '--password-stdin $SINK_TLS_FLAG' "$v \$SINK_TLS_FLAG"; s8_judge "$d"; [[ "$S8_J_REASONS" == "bad:$S8_ENGINE" ]] || m2+=" [$v => $S8_J_REASONS]"
done
for v in 'docker login -p "$X" -u u registry.example.test:5000' 'docker --config "$D" login -u u -p "$X" registry.example.test:5000' 'crane --insecure auth login -u u -p "$X" registry.example.test:5000'; do
  n2=$((n2 + 1)); d="$(s8_fresh m2-$n2)"; s8_put "$d" scripts/extra-a.sh "$v"; s8_judge "$d"; [[ "$S8_J_REASONS" == "bad:scripts/extra-a.sh" ]] || m2+=" [$v => $S8_J_REASONS]"
done
if [[ -z "$m2" ]]; then row "S8 mutation 2: the long forms, the glued forms, a short cluster (-up), -p before the host and global flags before the subcommand are each RED, reason bad:<that file>" ok
else row "S8 mutation 2: a password-option spelling or an option order was not judged bad" fail "$m2"; fi

# --- mutations 4, 5: a -p on a continuation line, and --password-stdin TOGETHER with -p ------------------------------------------
d="$(s8_fresh m4)"; s8_edit "$d/$S8_CONT" '--password-stdin >/dev/null 2>&1 || verify_fail pull-login' '-p "$ZOT_PULL_TOKEN" >/dev/null 2>&1 || verify_fail pull-login'; s8_judge "$d"
if [[ "$S8_J_REASONS" == "bad:$S8_CONT" ]]; then row "S8 mutation 4: a -p on the CONTINUATION line of a backslash-split \"\$DOCKER_BIN\" login is RED, reason bad:$S8_CONT (the per-file join sees it)" ok
else row "S8 mutation 4: a -p on a continuation line was not judged bad" fail "reasons='$S8_J_REASONS'"; fi
d="$(s8_fresh m5)"; s8_edit "$d/$S8_ENGINE" '--password-stdin $SINK_TLS_FLAG' '--password-stdin -p "$ZOT_PUSH_TOKEN" $SINK_TLS_FLAG'; s8_judge "$d"
if [[ "$S8_J_REASONS" == "bad:$S8_ENGINE" ]]; then row "S8 mutation 5: --password-stdin TOGETHER with -p (the precondition met, the property broken) is RED, reason bad:$S8_ENGINE" ok
else row "S8 mutation 5: --password-stdin alongside -p was not judged bad" fail "reasons='$S8_J_REASONS'"; fi

# --- mutation 7: a SECOND member after a compliant first, on the next line and on the SAME line ----------------------------------
d="$(s8_fresh m7)"
s8_put "$d" scripts/extra-b.sh "$(printf '%s\n%s' "printf '%s' \"\$T\" | docker login h.example.test:5000 -u u --password-stdin" 'docker login h.example.test:5000 -u u -p "$T"')"
s8_judge "$d"
if [[ "$S8_J_REASONS" == "bad:scripts/extra-b.sh" && "$S8_J_SITES" -eq $((S8_REAL_SITES + 2)) ]]; then row "S8 mutation 7: a compliant login followed by a -p login in the same new file is RED for that file, and both are counted (the second member is not shadowed by the first)" ok
else row "S8 mutation 7: the second member of a new file was not judged bad, or the compliant first was not counted" fail "reasons='$S8_J_REASONS' sites=$S8_J_SITES want=$((S8_REAL_SITES + 2))"; fi
m7b=""; n7=0
for v in 'printf %s "$A" | docker login h1.example -u u --password-stdin && docker login h2.example -u u -p "$B"' 'docker login h1.example -u u --password-stdin; docker login h2.example -u u -p "$B"' 'echo "step #1"; docker login h.example -u u -p "$B"'; do
  n7=$((n7 + 1)); d="$(s8_fresh m7b-$n7)"; s8_put "$d" scripts/extra-d.sh "$v"; s8_judge "$d"
  [[ "$S8_J_REASONS" == "bad:scripts/extra-d.sh" && "$(s8_recs "$d" scripts/extra-d.sh "")" -ge 1 && "$(s8_recs "$d" scripts/extra-d.sh 1)" -eq 1 ]] || m7b+=" [$v => $S8_J_REASONS]"
  case "$n7" in 1|2) [[ "$(s8_recs "$d" scripts/extra-d.sh "")" -eq 2 ]] || m7b+=" [$v => the compliant first login was not split off and counted]" ;; esac
done
if [[ -z "$m7b" ]]; then row "S8 mutation 7b: a -p login AFTER a compliant one on the same line (&&, ;) and after a quoted '#' earlier on the line is RED" ok
else row "S8 mutation 7b: a same-line second invocation hid a -p login" fail "$m7b"; fi

# --- evasion shapes the review found: each is a password on argv that a looser scanner reads as clean or as nothing -----------------
m_ev=""; n_ev=0
for v in 'docker login ghcr.io -u $(id -un) -p "$X"' 'crane auth login ghcr.io -u $(< f) -p "$X"' 'docker login ghcr.io -u u -p "$(cat /run/secrets/x)"' 'docker login -u u -p "$X"' 'docker login -u u --password "$X"' \
         'docker login ghcr.io -u ${{ github.actor }} -p "$X"' 'docker login -u "a;b" -p "$X" host' 'docker login host >/tmp/o -p "$X"' 'docker login host &>/dev/null -p "$X"' 'docker login host 2>&1 -p "$X"' \
         'podman login --authfile /x -p "$X" host' 'bash -c "docker login -u u -p $X host"' 'bash -lc "docker login -u u -p $X host"' 'eval "docker login -u u -p $X host"' \
         'ssh h "docker login -u u -p $X host"' 'ssh -o BatchMode=yes root@h "docker login -u u -p $X host"' 'os.system("docker login -u u -p x host")' 'docker login <your registry> -p "$X" host' "run: 'docker login -u u -p \"\$X\" host'" 'OUT=`docker login -u u -p "$X" host`' 'execSync(`docker login -u u -p ${t} host`)' \
         '/usr/bin/docker login -u u -p "$X" host' 'crane_capture o e auth login host -u u -p "$X"' 'X="$(printf %s "$T" | docker login host -u u -p "$T")"'; do
  n_ev=$((n_ev + 1)); d="$(s8_fresh ev-$n_ev)"; s8_put "$d" scripts/extra-e.sh "$v"; s8_judge "$d"; [[ "$S8_J_REASONS" == "bad:scripts/extra-e.sh" ]] || m_ev+=" [$v => $S8_J_REASONS]"
done
if [[ -z "$m_ev" ]]; then row "S8 evasion shapes: each construct sits BEFORE the -p so a mis-tokenised tail loses it: a \$( ) user, a command-substitution password, a host-less login, a \${{ }} expression, a quoted ;, a redirection (>, &>, 2>&1) before -p, a valued option, bash -c and -lc, eval, ssh, a YAML run: value, a backtick span, an exec call, a path verb, a wrapper and a login inside \$( ) are each RED" ok
else row "S8 evasion shapes: a password on argv was judged clean or unseen" fail "$m_ev"; fi

# --- mutation 8: dispatch and floor (scan roots broken, the verb renamed, one site file removed) ------------------------------------
m8=""
d="$(s8_fresh m8a)"; rm -rf "${d:?}/apps" "${d:?}/scripts" "${d:?}/.github" "${d:?}/plugins"; s8_judge "$d"; s8_has floor && [[ "$S8_J_SITES" -eq 0 ]] || m8+=" [roots broken => '$S8_J_REASONS' sites=$S8_J_SITES]"
d="$(s8_fresh m8b)"; s8_edit "$d/$S8_ENGINE" '$CRANE auth login' '$KRANE auth login' 2; s8_judge "$d"; s8_has floor && [[ "$S8_J_SITES" -eq $((S8_REAL_SITES - 2)) ]] || m8+=" [verb renamed => '$S8_J_REASONS' sites=$S8_J_SITES]"
d="$(s8_fresh m8c)"; rm -f "${d:?}/${S8_CONT:?}"; s8_judge "$d"; s8_has floor || m8+=" [site file removed => '$S8_J_REASONS']"
if [[ -z "$m8" ]]; then row "S8 mutation 8: scan roots broken (0 sites), the engine's verb renamed past the verb match (the sites vanish), and one site file removed are each RED, reason floor" ok
else row "S8 mutation 8: a dispatch or floor mutation was not judged floor" fail "$m8"; fi

# --- must-pass inputs that are NOT invocations (prose, patterns, aliases, comments): zero BAD records -----------------------------
d="$(s8_fresh pass1)"
s8_put "$d" scripts/prose.sh "$(cat <<'S8PASS'
description: 'Bring up a cloudflared TCP bridge to the private-net zot registry so a GH runner can reach it, and (unless skipped) docker login to it'
          echo "::error::docker login to zot (127.0.0.1:5000) failed over the CF-tunnel bridge. Read the cloudflared log below."
    logger -t "$LOG_TAG" "ZOT_GATE: active — docker login $ZOT_REGISTRY_URL ok (zot-primary)"
    logger -t "$LOG_TAG" "ZOT_GATE: docker login $ZOT_REGISTRY_URL FAILED class=$zclass http=${zhttp:-none} — no pull path (zot login failed)"
  if grep -qE '(ZOT_GATE|PRELUDE): docker login .* FAILED' <<<"$line" \
     && true; then :; fi
for tok in 'docker push' 'cosign' 'crane' 'id-token' 'docker login' 'login-action'; do :; done
# token free of chars that break `docker login -p` / htpasswd.
echo "Use docker login registry -u me -p secret"
printf 'docker login -u u -p pw r.io\n'
grep -q "docker login -p" file
alias dl='docker login r.io -u u -p t'
echo 'Run `docker login -p x` to see'
grep -qc "docker login -p" file
# docker login r.io -u u -p t
docker login --help
docker logout r.io
S8PASS
)"
s8_put "$d" plugins/prose.md 'Never write `docker login -u u -p "$T"`; use `--password-stdin`'
if [[ "$(s8_recs "$d" scripts/prose.sh 1)" -eq 0 && "$(s8_recs "$d" plugins/prose.md 1)" -eq 0 ]]; then row "S8 must-pass: prose and pattern lines that merely MENTION docker login (the action description, an ::error:: echo, the ci-deploy logger lines, a grep pattern, a token-list loop, an echo, a printf, an alias, a single-quoted backtick, grep -qc, a markdown inline-code warning, a comment, --help, logout) are not invocations, so none is judged bad" ok
else row "S8 must-pass: a prose or pattern mention of docker login was judged a password-on-argv login" fail "$(s8_scan "$d" | awk -F'\t' '$1 == "scripts/prose.sh" && $4 == 1 { print $2 }' | tr '\n' ' ')"; fi
m_ok=""; n_ok=0
for v in 'printf %s "$T" | docker login --insecure -u u h.example.test:5000 --password-stdin' 'printf %s "$T" | docker login h.example.test:5000 -u u --password-stdin && mkdir -p x' \
         'printf %s "$T" | docker login --password-stdin -u u h.example.test:5000' 'printf %s "$T" | docker login h.example.test:5000 -u ${{ github.actor }} --password-stdin' \
         'printf %s "$T" | docker login h.example.test:5000 -u u --password-stdin &>/dev/null' 'printf %s "$T" | docker login h.example.test:5000 -u u --password-stdin 2>&1 | tee x' \
         'aws ecr get-login-password | docker login --username AWS --password-stdin r.io' \
         'podman login --authfile /x -u u --password-stdin h.example.test:5000 < tok.txt' 'podman login --tls-verify false -u u --password-stdin h.example.test:5000' \
         'docker login h.example.test:5000 -u u --password-stdin <tok.txt && mkdir -p out' 'docker login h.example.test:5000 -ujpierre --password-stdin'; do
  n_ok=$((n_ok + 1)); d="$(s8_fresh pass2-$n_ok)"; s8_put "$d" scripts/extra-c.sh "$v"
  n="$(s8_recs "$d" scripts/extra-c.sh "")"; b="$(s8_recs "$d" scripts/extra-c.sh 1)"
  [[ "$n" -eq 1 && "$b" -eq 0 ]] || m_ok+=" [$v => sites=$n bad=$b]"
done
if [[ -z "$m_ok" ]]; then row "S8 must-pass: compliant variants (an extra --insecure, a trailing && mkdir -p x, --password-stdin before the host, a \${{ }} user, &>, 2>&1 | tee, an ECR password feeder, a valued --authfile, --tls-verify false, a <file redirect and a glued -ujpierre username) are each counted once and judged GREEN" ok
else row "S8 must-pass: a compliant --password-stdin variant was mis-counted or judged bad" fail "$m_ok"; fi
# --- exclusion rules: a -p login under each excluded path is not judged; under a similarly named non-excluded path it IS -------------
m_x=""; n_x=0
for pair in 'x/test/a.sh:0' 'x/tests/a.sh:0' 'x/fixtures/a.sh:0' 'a.test.ts:0' 'knowledge-base/a.sh:0' 'docs/a.md:0' 'plugins/a.md:1' 'scripts/testing/a.sh:1' 'apps/web-platform/a.ts:1'; do
  n_x=$((n_x + 1)); d="$(s8_fresh excl-$n_x)"; s8_put "$d" "${pair%%:*}" 'docker login -u u -p "$X" host'
  [[ "$(s8_recs "$d" "${pair%%:*}" 1)" -eq "${pair##*:}" ]] || m_x+=" [${pair%%:*} => want ${pair##*:} bad]"
done
if [[ -z "$m_x" ]]; then row "S8 exclusions: a -p login under test/, tests/, fixtures/, *.test.*, knowledge-base/ or a .md outside plugins/ is not scanned, and the same login under plugins/*.md, scripts/testing/ and apps/ is" ok
else row "S8 exclusions: an exclusion rule hid a login it should not, or missed one it should" fail "$m_x"; fi
echo "=== stage S8: Guard 3 rows (registry login password off argv: tokenised derived census, floor, mutations, evasion shapes, must-pass inputs) done ==="

# =====================================================================================
# STAGE S9 (#9757 item 2): a credential never rides terraform's argv as a `-var` option. Guard 1 is a derived static scan plus two pins (the rehearsal
# workflow's option names; every terraform plan/destroy step exports before its `doppler run` and keeps bare --preserve-env) and a YAML-parsed step-set
# identity; Guard 2 EXECUTES the four rehearsal terraform step bodies (two plans, two destroys) under strict `doppler`/`terraform` stubs and checks the
# token reaches terraform by environment, is masked before terraform runs, and reaches no argv.
#
# GUARD 1 SCAN. Corpus = tracked + untracked non-ignored files minus S8's exclusion predicate (a deliberate copy: keep the two in lockstep), with
# extensions .yml .yaml .sh .bash, plus .md under plugins/ only. Continuations are joined (a comment line is never continued); full-line comments are skipped
# outside markdown. The option regex needs a LEFT boundary and the `NAME=` shape, so `--name-transformer tf-var -- \` and `-var-file` cannot match. There is NO
# terraform-verb requirement (unlike S8): array building and `bash -c "... -var ..."` payloads carry the same exposure. A literal NAME is judged by a credential-name
# regex; a `-var` whose name cannot be read as a literal (`$K`, `api_$x=`, `$'..'`, an escaped quote) is refused as `nonliteral`.
# NAMED BLIND SPOTS and the rejected alternatives (stdin var-file, per-command prefix): ADR-280, the 2026-10-20 addendum. S9 selects on the full run and on an edit of
# the rehearsal workflow; that array entry lives in scripts/lib/test-affected-paths.sh, whose edit degrades a LOCAL `--affected` run to the full battery once (CI is unaffected).
#
# FLOOR. The scan sees S9_VAR_FLOOR `-var` options on the tree (measured, exact like S8's). A scan below it is RED, never a clean bill. Converting or deleting a
# benign `-var` anywhere is a floor edit in the same PR: lower S9_VAR_FLOOR to the new measured count.
# =====================================================================================
S9_VAR_FLOOR=44
S9_WF=".github/workflows/inngest-provision-rehearsal.yml"
S9_IDS_WANT="Teardown only (recovery arm)|Terraform destroy (everything this root owns)|Terraform plan (phase A — NIC absent)|Terraform plan (phase B — NIC attach)"
S9="$TMPD/s9"; assert_fixture_dir "$S9"; mkdir -p "$S9/base" "$S9/mut" "$S9/shim" "$S9/real" "$S9/rows"
cat > "$S9/scan.py" <<'S9PY'
import os, re, subprocess, sys
root = sys.argv[1]
# A terraform/packer `-var` option: left boundary (so `tf-var --` and `-var-file` cannot match), `-var` or `--var`, an optional quote on the
# option word, `=` or whitespace, an optional quote, then NAME= where NAME is a literal identifier or a non-literal ($K, ${K}, $(k)).
OPT = re.compile(r"""(?<![\w-])["']?-{1,2}var["']?(?:=|\s+)["']?(?P<name>[A-Za-z_][A-Za-z0-9_]*|\$[{(]?\w+[})]?)=""")
# A `-var` whose name cannot be read as a literal: a `$`, backtick or backslash right after the option or after a literal prefix (api_$x=, $'..', "$KV", \").
FALLBACK = re.compile(r"""(?<![\w-])["']?-{1,2}var["']?(?:=|\s+)["']?(?:[A-Za-z_][A-Za-z0-9_]*)?[$`\\]""")
CRED = re.compile(r"(token|secret|pass(?:w(?:or)?d|phrase)?|pwd|credential|creds|psk|api_?key|private_?key|bearer|auth|hmac|jwt|dsn|cookie|webhook)|(?:^|_)(?:key|pat|pw)$", re.I)
CRED_CAMEL = re.compile(r"[a-z]Key")
out = subprocess.run(["git", "-C", root, "ls-files", "-z", "--cached", "--others", "--exclude-standard"], capture_output=True, check=True)
for rel in out.stdout.decode("utf-8", "replace").split("\0"):
    parts = rel.split("/")
    if not rel or rel.endswith(".test.sh") or ".test." in parts[-1] or "test" in parts[:-1] or "tests" in parts[:-1] or "fixtures" in parts[:-1] or parts[0] == "knowledge-base":
        continue
    md = rel.endswith(".md")
    if md and parts[0] != "plugins":
        continue
    if not (md or rel.endswith((".yml", ".yaml", ".sh", ".bash"))):
        continue
    try:
        data = open(os.path.join(root, rel), "rb").read()
    except OSError:
        continue
    if b"\0" in data[:8192] or b"-var" not in data:
        continue
    lines = data.decode("utf-8", "replace").split("\n")
    i = 0
    while i < len(lines):
        start, buf = i + 1, [lines[i]]
        while buf[-1].endswith("\\") and not buf[0].lstrip().startswith("#") and i + 1 < len(lines):
            buf[-1] = buf[-1][:-1]
            i += 1
            buf.append(lines[i].strip())
        cur = " ".join(buf)
        i += 1
        if "-var" not in cur or (not md and cur.lstrip().startswith("#")):
            continue
        code = cur.strip()[:200]
        seen = set()
        for m in OPT.finditer(cur):
            seen.add(m.start())
            name = m.group("name")
            verdict = "nonliteral" if name.startswith("$") else ("name" if CRED.search(name) or CRED_CAMEL.search(name) else "ok")
            print("\t".join([rel, str(start), name, verdict, code]))
        for m in FALLBACK.finditer(cur):
            if m.start() not in seen:
                print("\t".join([rel, str(start), "<nonliteral>", "nonliteral", code]))
S9PY
cat > "$S9/steps.py" <<'S9STEPS'
import re, sys, yaml
f, mode = sys.argv[1], sys.argv[2]
d = yaml.safe_load(open(f, encoding="utf-8"))
steps = []
for j in (d.get("jobs") or {}).values():
    steps += [s for s in (j.get("steps") or []) if isinstance(s, dict)] if isinstance(j, dict) else []
TF = re.compile(r"(?<![\w-])terraform\s+(?:-\S+\s+)*(?:plan|destroy)\b")
EXPORT = re.compile(r'^\s*export TF_VAR_zot_pull_token="\$\{?ZOT_PULL\}?"\s*$')


def logical(run):
    out, cur = [], ""
    for ln in run.split("\n"):
        if ln.lstrip().startswith("#") and not cur:
            continue
        if ln.rstrip().endswith("\\"):
            cur += ln.rstrip()[:-1] + " "
            continue
        out.append(cur + ln.strip())
        cur = ""
    return out + ([cur] if cur else [])


tf = [(s.get("name", ""), s["run"]) for s in steps if isinstance(s.get("run"), str) and any(TF.search(x) for x in logical(s["run"]))]
if mode == "ids":
    print("|".join(sorted(n for n, _ in tf)))
else:  # pin: one `<reason>\t<step>` line per violation
    if not tf:
        print("no-steps\t-")
    for n, run in tf:
        lines = [x for x in run.split("\n") if not x.lstrip().startswith("#")]
        if len([x for x in lines if EXPORT.match(x)]) != 1:
            print("export-count\t" + n)
        dr = [x for x in lines if "doppler run" in x]
        if not any(re.search(r"\bdoppler run\b.*\s--preserve-env(?=\s|$)", x) for x in dr):
            print("preserve-env\t" + n)
        if any("--only-secrets" in x for x in dr):
            print("only-secrets\t" + n)
S9STEPS
s9_scan() { python3 -I "$S9/scan.py" "$1"; }   # <root>: one TSV record per -var option: file, line, name, verdict (ok|name|nonliteral), code
s9_pin() { python3 -I "$S9/steps.py" "$1" pin || printf 'steps-crashed\t-\n'; }   # <workflow file>: violation lines, empty = every plan/destroy step exports and keeps bare --preserve-env
s9_ids() { python3 -I "$S9/steps.py" "$1" ids; }   # <workflow file>: the sorted names of the steps that run terraform plan or destroy
S9_J_REASONS=""; S9_J_N=0; S9_J_DETAIL=""
s9_judge_text() { # <scan text>: sets S9_J_REASONS (empty = GREEN), S9_J_N, S9_J_DETAIL. Reasons: floor, name:<file>, nonliteral:<file>
  local f
  S9_J_REASONS=""
  S9_J_N="$(grep -c . <<<"$1" || true)"
  S9_J_DETAIL="$(awk -F'\t' 'NF >= 4 && $4 != "ok" { print $1 ":" $2 " (" $3 ")" }' <<<"$1" | tr '\n' ' ')"
  [[ "$S9_J_N" -ge "$S9_VAR_FLOOR" ]] || S9_J_REASONS+=" floor"
  while IFS= read -r f; do [[ -n "$f" ]] && S9_J_REASONS+=" $f"; done < <(awk -F'\t' 'NF >= 4 && $4 != "ok" { print $4 ":" $1 }' <<<"$1" | sort -u)
  S9_J_REASONS="${S9_J_REASONS# }"
}
s9_judge() { s9_judge_text "$(s9_scan "$1")"; } # <root>
s9_i1_text() { awk -F'\t' -v f="$S9_WF" '$1 == f { print $3 }' <<<"$1" | sort | uniq -c | awk '{ printf "%s%s=%s", s, $2, $1; s = " " }'; } # <scan text>: the rehearsal workflow's option names with counts
s9_bad() { s9_scan "$1" | awk -F'\t' -v f="$2" '$1 == f && $4 != "ok" { n++ } END { print n + 0 }'; } # <root> <file>: BAD record count
s9_put() { assert_fixture_dir "$1"; mkdir -p "$1/$(dirname "$2")"; printf '%s\n' "$3" > "$1/$2"; } # <root> <relative path> <content>
s9_fresh() { local d="$S9/mut/$1"; assert_fixture_dir "$d"; rm -rf "${d:?}"; cp -a "$S9/base" "$d" && printf '%s' "$d"; } # <name>: prints a new root
s9_edit() { s6_edit "$@" || fatal "S9 mutation did not land: $2"; } # <file> <old> <new> [<count>]: replace exactly <count> occurrences or abort the suite
s9_edit1() { python3 -I -c '
import sys
p, old, new = sys.argv[1:4]
t = open(p, encoding="utf-8").read()
if old not in t: sys.exit(1)
open(p, "w", encoding="utf-8").write(t.replace(old, new, 1))' "$@" || fatal "S9 first-occurrence mutation did not land: $2"; } # <file> <old> <new>: replace the FIRST occurrence only
s9_has() { [[ " $S9_J_REASONS " == *" $1 "* ]]; }
( source "$REPO_ROOT/plugins/soleur/test/lib/git-fixture-env.sh" && git_fixture_env "$S9/base" || exit 1; git -C "$S9/base" init -q ) \
  || fatal "S9 could not create the scratch repository"
S9_REAL_SCAN="$(s9_scan "$REPO_ROOT")"
# The base copies EVERY file that carries a -var record (a partial base would trip the floor and turn every mutant RED for the wrong reason).
while IFS= read -r f; do [[ -n "$f" ]] || continue; mkdir -p "$S9/base/$(dirname "$f")"; cp "$REPO_ROOT/$f" "$S9/base/$f"; done < <(cut -f1 <<<"$S9_REAL_SCAN" | sort -u)

# ---- Guard 1 on the real tree ---------------------------------------------------------------------------------------------------------
s9_judge_text "$S9_REAL_SCAN"; S9_REAL_REASONS="$S9_J_REASONS"; S9_REAL_N="$S9_J_N"
if [[ -z "$S9_REAL_REASONS" ]]; then row "S9 Guard 1: no scanned non-test file (tracked, or untracked and not ignored) passes a credential on a -var option ($S9_REAL_N options seen, floor $S9_VAR_FLOOR, derived over the whole tree)" ok
else row "S9 Guard 1: a credential rides a -var option (file:line below), or the scan saw fewer options than its floor ($S9_VAR_FLOOR; lower it to the new measured count in the same PR when a benign -var is converted); the remedy for a credential is TF_VAR_<name> in the step environment" fail "reasons='$S9_REAL_REASONS' at=$S9_J_DETAIL options=$S9_REAL_N"; fi
S9_I1="$(s9_i1_text "$S9_REAL_SCAN")"
if [[ "$S9_I1" == "nic_attached=4 rehearsal_run_id=4" ]]; then row "S9 I1: the rehearsal workflow's -var options are exactly rehearsal_run_id x4 and nic_attached x4 (a new benign -var there is a deliberate edit of this row)" ok
else row "S9 I1: the rehearsal workflow's -var option set changed" fail "got='$S9_I1'"; fi
S9_PIN="$(s9_pin "$REPO_ROOT/$S9_WF")"
if [[ -z "$S9_PIN" ]]; then row "S9 I2: each terraform plan/destroy step exports TF_VAR_zot_pull_token (the read variable) exactly once, keeps bare --preserve-env and has no --only-secrets" ok
else row "S9 I2: a terraform step lost its TF_VAR_zot_pull_token export or its bare --preserve-env (expected: export TF_VAR_zot_pull_token=\"\$ZOT_PULL\" before doppler run --preserve-env)" fail "$S9_WF: $(tr '\t\n' '= ' <<<"$S9_PIN")"; fi
S9_IDS="$(s9_ids "$REPO_ROOT/$S9_WF")"
if [[ "$S9_IDS" == "$S9_IDS_WANT" ]]; then row "S9 step set: the steps that run terraform plan or destroy are exactly the four named steps, the four bodies Guard 2 executes (parsed from the YAML)" ok
else row "S9 step set: a terraform plan/destroy step was added, removed or renamed (Guard 2 executes exactly four named bodies and I2 pins them)" fail "got='$S9_IDS'"; fi

# ---- the baseline-GREEN control: the scratch base is judged by the SAME function and must be green --------------------------------------
s9_judge "$S9/base"
if [[ -z "$S9_J_REASONS" && "$S9_J_N" -eq "$S9_REAL_N" && -z "$(s9_pin "$S9/base/$S9_WF")" ]]; then row "S9 control: the scratch base (a copy of every file with a -var record) is judged GREEN with the real tree's count, so each mutant below is RED for its mutation alone" ok
else row "S9 control: the scratch base is not GREEN with the real count (every mutant below would be measuring the base)" fail "reasons='$S9_J_REASONS' n=$S9_J_N/$S9_REAL_N"; fi
s9_judge_text ""
if s9_has floor; then row "S9 harness: a scanner that prints nothing is RED (reason floor), never a clean bill" ok; else row "S9 harness: an empty scan was not judged floor" fail "reasons='$S9_J_REASONS'"; fi

# ---- Guard 1 mutations ------------------------------------------------------------------------------------------------------------------
m3b=""; n3=0
for v in 'terraform plan --var api_token=$T' 'ARGS=("-var" "api_token=$T")' 'terraform plan -var "$K=$V"' 'terraform plan -var "rehearsal_run_id=1" -var "api_token=$T"' 'VAR_ARGS+=(-var="deploy_token=$T")' 'bash -c "terraform plan -var db_password=$P"' \
         'terraform plan -var=api_key=$T' "terraform plan -var 'client_secret=\$T'" 'echo "step #1"; terraform plan -var auth_header=$H' \
         'terraform plan -var "$KV"' 'terraform plan -var "api_$x=$T"' "terraform plan -var \$'api_token=x'" 'bash -c "terraform plan -var \"api_token=$T\""'; do
  n3=$((n3 + 1)); d="$(s9_fresh m3b-$n3)"; s9_put "$d" scripts/extra.sh "$v"; s9_judge "$d"
  case "$S9_J_REASONS" in "name:scripts/extra.sh"|"nonliteral:scripts/extra.sh") : ;; *) m3b+=" [$v => '$S9_J_REASONS']" ;; esac
done
if [[ -z "$m3b" ]]; then row "S9 mutation 3b: the double-dash spelling, a quoted option word, a non-literal name, a second option on one line, an array append, a bash -c payload (plain and escaped-quote), -var=NAME=v, a single-quoted pair, a quoted '#' earlier on the line, a whole pair in a variable, a partly dynamic name and an ANSI-C quoted pair are each RED for that file" ok
else row "S9 mutation 3b: a credential -var spelling was judged clean" fail "$m3b"; fi
d="$(s9_fresh m7b)"; s9_edit1 "$d/$S9_WF" 'doppler run --preserve-env' 'doppler run'; m7b="$(s9_pin "$d/$S9_WF" | tr '\t\n' '= ')"
if [[ "$m7b" == "preserve-env=Teardown only (recovery arm) " ]]; then row "S9 mutation 7: dropping bare --preserve-env from one step is RED in the static pin" ok
else row "S9 mutation 7: the static pin did not see a dropped --preserve-env" fail "got='$m7b'"; fi
d="$(s9_fresh m8b)"; s9_edit "$d/$S9_WF" '      - name: Assert no rehearsal orphans remain (Hetzner API)' $'      - name: Extra destroy\n        run: |\n          terraform -chdir=x destroy -auto-approve\n      - name: Assert no rehearsal orphans remain (Hetzner API)'; m8b="$(s9_ids "$d/$S9_WF")"
if [[ "$m8b" != "$S9_IDS_WANT" ]]; then row "S9 mutation 8: an added third destroy step (written with a global flag) changes the YAML-derived step set" ok
else row "S9 mutation 8: the step-set identity survived an added destroy step" fail "added='$m8b'"; fi

# ---- credential-name table: one name per regex alternative (and the benign names that must stay clean) ------------------------------------
d="$(s9_fresh names)"
S9_NAMES_BAD="fooKey a_token a_secret a_pass a_password a_passphrase db_pwd a_credential a_creds a_psk apikey api_key privatekey private_key a_bearer a_auth a_hmac x_jwt app_dsn a_cookie a_webhook deploy_key deploy_pat db_pw apiKey"
S9_NAMES_OK="ssh_key_path image_name rehearsal_phase rehearsal_run_id nic_attached key_name admin_ips"
for nm in $S9_NAMES_BAD $S9_NAMES_OK; do printf 'terraform plan -var %s=1\n' "$nm"; done > "$S9/names.txt"
s9_put "$d" scripts/names.sh "$(cat "$S9/names.txt")"
m_nm=""; S9_NM_SCAN="$(s9_scan "$d")"
for nm in $S9_NAMES_BAD; do [[ "$(awk -F'\t' -v n="$nm" '$1 == "scripts/names.sh" && $3 == n { print $4 }' <<<"$S9_NM_SCAN")" == name ]] || m_nm+=" [$nm not judged name]"; done
for nm in $S9_NAMES_OK; do [[ "$(awk -F'\t' -v n="$nm" '$1 == "scripts/names.sh" && $3 == n { print $4 }' <<<"$S9_NM_SCAN")" == ok ]] || m_nm+=" [$nm not judged ok]"; done
if [[ -z "$m_nm" ]]; then row "S9 names: one name per credential-regex alternative (token, secret, pass, pwd, credential, creds, psk, api_key, private_key, bearer, auth, hmac, jwt, dsn, cookie, webhook, _key, _pat, _pw, camelCase Key) is judged a credential, and ssh_key_path, image_name, rehearsal_*, nic_attached, key_name, admin_ips stay clean" ok
else row "S9 names: the credential-name regex mis-judged a name" fail "$m_nm"; fi

# ---- must-pass inputs that are NOT credential -var options: zero BAD records ---------------------------------------------------------
d="$(s9_fresh pass1)"
s9_put "$d" scripts/ok.sh "$(cat <<'S9PASS'
terraform plan -var "ssh_key_path=${CI_SSH_PUB}" -var image_name="$PINNED"
terraform plan -var-file=<(printf 'x=1\n')
doppler run --preserve-env --name-transformer tf-var -- \
  terraform plan -no-color
# terraform plan -var api_token=x
TOKEN="$(doppler secrets get FOO --plain)"
terraform plan -var "image_name=${PINNED}"
S9PASS
)"
s9_put "$d" scripts/bad.test.sh 'terraform plan -var "api_token=$T"'
s9_kb_root=knowledge-base  # built from a variable so test-affected-kb-consumers reads this as a scratch-tree path, not a read of the real tree
s9_put "$d" "$s9_kb_root/runbook.sh" 'terraform plan -var "api_token=$T"'
if [[ "$(s9_bad "$d" scripts/ok.sh)" -eq 0 && "$(s9_scan "$d" | awk -F'\t' '$1 == "scripts/ok.sh" { n++ } END { print n + 0 }')" -eq 3 ]]; then row "S9 must-pass: a clean ssh_key_path/image_name option, -var-file, the tf-var transformer line, a comment, and a file that reads a secret AND passes a clean -var are judged GREEN (3 options counted, 0 bad)" ok
else row "S9 must-pass: a non-credential -var shape was judged bad or mis-counted" fail "bad=$(s9_bad "$d" scripts/ok.sh)"; fi
m_x=""; n_x=0
for pair in 'x/test/a.sh:0' 'x/tests/a.sh:0' 'x/fixtures/a.sh:0' 'a.test.sh:0' 'knowledge-base/a.sh:0' 'docs/a.md:0' 'plugins/a.md:1' 'scripts/testing/a.sh:1' 'apps/a.sh:1'; do
  n_x=$((n_x + 1)); d="$(s9_fresh excl-$n_x)"; s9_put "$d" "${pair%%:*}" 'terraform plan -var "api_token=$T"'
  [[ "$(s9_bad "$d" "${pair%%:*}")" -eq "${pair##*:}" ]] || m_x+=" [${pair%%:*} => want ${pair##*:} bad]"
done
if [[ -z "$m_x" ]]; then row "S9 exclusions: a credential -var under test/, tests/, fixtures/, *.test.*, knowledge-base/ or a .md outside plugins/ is not scanned, and the same under plugins/*.md, scripts/testing/ and apps/ is" ok
else row "S9 exclusions: an exclusion rule hid a credential -var it should not, or missed one it should" fail "$m_x"; fi

# ---- Guard 2: the four rehearsal terraform step bodies EXECUTED under strict stubs --------------------------------------------------
S9_CANARY="S9CANARYzot0123"
for t in date sed; do p="$(type -P "$t" || true)"; [[ "$p" == /* ]] || fatal "stage S9: $t is required"; ln -s "$p" "$S9/real/$t"; done # phase B writes a timestamp with date, the sourced redaction filter (#11294) is sed; every other command in the four bodies is a builtin
{ printf '#!%s\n' "$BASH_BIN"; cat <<'S9DOP'
# Stub doppler: records argv (NUL-delimited) and answers ONLY the two argv shapes the steps use (anything else: exit 64 and a refusal line, so a changed
# flag, config or project is visible). `run` execs the command after `--` and injects NO TF_VAR_* (production inherits an equal value from prd_terraform; the stub
# models the unmeasured case so a dropped export cannot pass by inheritance).
printf '%s\0' "$@" > "$CALLS_DIR/doppler.$$.argv"
case "${1-}" in
  secrets)
    if [[ "$*" != "secrets get ZOT_PULL_TOKEN -p soleur -c prd --plain" ]]; then printf 'S9-STUB-64 unexpected doppler secrets argv\n' >> "$CALLS_DIR/refusals"; exit 64; fi
    printf '%s' "$S9_CANARY_VAL"; exit 0 ;;
  run)
    if [[ "${*:1:9}" != "run --preserve-env -p soleur -c prd_terraform --name-transformer tf-var --" ]]; then printf 'S9-STUB-64 unexpected doppler run argv\n' >> "$CALLS_DIR/refusals"; exit 64; fi
    shift 9; exec "$@" ;;
esac
printf 'S9-STUB-64 unknown doppler verb\n' >> "$CALLS_DIR/refusals"; exit 64
S9DOP
} > "$S9/shim/doppler"
{ printf '#!%s\n' "$BASH_BIN"; cat <<'S9TF'
# Stub terraform: records argv and the value of TF_VAR_zot_pull_token (or the literal <unset>); exits 64 unless argv is EXACTLY the one the harness expects for the step.
printf '%s\0' "$@" > "$CALLS_DIR/terraform.$$.argv"
printf '%s' "${TF_VAR_zot_pull_token-<unset>}" > "$CALLS_DIR/terraform.$$.tfvar"
echo "S9 terraform stub: $1"
if [[ "$*" != "$S9_TF_ARGV" ]]; then printf 'S9-STUB-64 unexpected terraform argv\n' >> "$CALLS_DIR/refusals"; exit 64; fi
S9TF
} > "$S9/shim/terraform"
chmod +x "$S9/shim/doppler" "$S9/shim/terraform"
S9_N=0
s9_run() { # <bodyfile> <expected terraform argv> -> S9_RC S9_DIR
  local r; S9_N=$((S9_N + 1)); r="$S9/rows/r$S9_N"; assert_fixture_dir "$r"; mkdir -p "$r/calls" "$r/cwd"
  S9_RC=0
  # The step bodies source the redaction filter through $GITHUB_WORKSPACE (#11294); this scratch workspace gets a copy of the real one.
  mkdir -p "$r/cwd/tests/scripts/lib" && cp "$REPO_ROOT/tests/scripts/lib/tf-redact-random-ids.sh" "$r/cwd/tests/scripts/lib/"
  ( cd "$r/cwd" && env -i PATH="$S9/shim:$S9/real" HOME="$r" CALLS_DIR="$r/calls" GITHUB_RUN_ID=424242 GITHUB_WORKSPACE="$r/cwd" DOPPLER_TOKEN="default-scope" DOPPLER_TOKEN_PRD="prd-scope" \
      S9_CANARY_VAL="$S9_CANARY" S9_TF_ARGV="$2" "$BASH_BIN" --noprofile --norc -eo pipefail "$1" ) > "$r/out" 2>&1 || S9_RC=$?
  S9_DIR="$r"
}
S9_R_REASONS=""
s9_judge_run() { # sets S9_R_REASONS (empty = GREEN). Reasons, in this order: rc ncalls canary-in-argv env-not-set env-value-differs mask-missing refused
  local f n=0 tv="<none>" mask_ln stub_ln
  S9_R_REASONS=""
  [[ "$S9_RC" == 0 ]] || S9_R_REASONS+=" rc"
  for f in "$S9_DIR"/calls/terraform.*.argv; do [[ -e "$f" ]] || continue; n=$((n + 1)); tv="$(cat "${f%.argv}.tfvar")"; done
  [[ "$n" == 1 ]] || S9_R_REASONS+=" ncalls"
  for f in "$S9_DIR"/calls/*.argv; do [[ -e "$f" ]] || continue; if grep -qF -- "$S9_CANARY" <(tr '\0' '\n' < "$f"); then S9_R_REASONS+=" canary-in-argv"; break; fi; done
  if [[ "$tv" == "<unset>" ]]; then S9_R_REASONS+=" env-not-set"; elif [[ "$n" -ge 1 && "$tv" != "$S9_CANARY" ]]; then S9_R_REASONS+=" env-value-differs"; fi
  mask_ln="$(grep -nxF -- "::add-mask::$S9_CANARY" "$S9_DIR/out" | head -n 1 | cut -d: -f1)"
  stub_ln="$(grep -n '^S9 terraform stub:' "$S9_DIR/out" | head -n 1 | cut -d: -f1)"
  if [[ -z "$mask_ln" || ( -n "$stub_ln" && "$mask_ln" -gt "$stub_ln" ) ]]; then S9_R_REASONS+=" mask-missing"; fi
  [[ ! -s "$S9_DIR/calls/refusals" ]] || S9_R_REASONS+=" refused"
  S9_R_REASONS="${S9_R_REASONS# }"
}
s9_verdict_ok() { [[ "$1" == "$2" ]]; } # <got reasons> <want reasons>: the one comparison every Guard 2 mutation row is judged by
S9_EXP=$'export TF_VAR_zot_pull_token="$ZOT_PULL"\n'; S9_MASK="printf '::add-mask::%s\\n' \"\$ZOT_PULL\""$'\n'
s9_mrow() { # <tag> <id> <want reasons> <old> <new> [<old> <new>]...: copy the body, apply exact edits, run it, judge it
  local tag="$1" id="$2" want="$3" b="$S9/body-$1.sh" m="$S9/m-$1-$2.sh"; shift 3
  cp "$b" "$m" || fatal "S9 could not copy $b"
  while [[ $# -ge 2 ]]; do s9_edit "$m" "$1" "$2"; shift 2; done
  s9_run "$m" "$S9_TF_ARGV"; s9_judge_run
  if s9_verdict_ok "$S9_R_REASONS" "$want"; then row "S9 Guard 2 $id ($tag): judged '$want'" ok
  else row "S9 Guard 2 $id ($tag): wrong verdict" fail "want='$want' got='$S9_R_REASONS'"; fi
}
for spec in 'teardown-only|Teardown only (recovery arm)|destroy -auto-approve -input=false|false' 'teardown-job|Terraform destroy (everything|destroy -auto-approve -input=false|false' \
            'plan-a|Terraform plan (phase A|plan -no-color -input=false -out=tfplan-a|false' 'plan-b|Terraform plan (phase B|plan -no-color -input=false -out=tfplan-b|true'; do
  IFS='|' read -r tag sel argv nic <<<"$spec"
  S9_TF_ARGV="$argv -var rehearsal_run_id=424242 -var nic_attached=$nic"; S9_TAIL="-var nic_attached=$nic 2>&1 | tf_redact_random_ids"$'\n' # the step tail now pipes through the redactor (#11294)
  s3_body "$REPO_ROOT/$S9_WF" "$sel" > "$S9/body-$tag.sh" || fatal "S9 could not extract the $tag step"
  s9_run "$S9/body-$tag.sh" "$S9_TF_ARGV"; s9_judge_run
  if [[ -z "$S9_R_REASONS" ]]; then row "S9 Guard 2 control ($tag): the real step body runs GREEN under the strict stubs: one terraform call with exactly the expected argv, the token masked before terraform runs, in its environment and in no argv" ok
  else row "S9 Guard 2 control ($tag): the real step body is not GREEN under the strict stubs (every mutant below would measure the base)" fail "reasons='$S9_R_REASONS'"; fatal "S9 control not green for $tag: a red baseline voids every mutant"; fi
  s9_mrow "$tag" m1a "rc canary-in-argv env-not-set refused" "$S9_EXP" '' "$S9_TAIL" "-var nic_attached=$nic"$' \\\n    -var "zot_pull_token=${ZOT_PULL}" 2>&1 | tf_redact_random_ids\n'
  s9_mrow "$tag" m2-reorder "env-not-set" "$S9_EXP" '' "$S9_TAIL" "$S9_TAIL$S9_EXP"
  s9_mrow "$tag" m3-mask "mask-missing" "$S9_MASK" ''
  s9_mrow "$tag" m4-doppler-scope "rc ncalls refused" "-c prd_terraform" "-c prd"
done
# The comparison every mutation row is judged by must be able to REJECT: a doctored pair must fail it and an equal pair must pass (reported by row, never through s9_mrow).
if s9_verdict_ok "env-not-set" "env-not-set" && ! s9_verdict_ok "env-not-set" "mask-missing" && ! s9_verdict_ok "" "rc"; then row "S9 harness: the Guard 2 verdict comparison rejects a doctored verdict and accepts an equal one" ok
else row "S9 harness: the Guard 2 verdict comparison accepted a doctored verdict" fail "s9_verdict_ok is not discriminating"; fi
echo "=== stage S9: Guard 1 rows (terraform -var credentials: derived scan, floor, identity, mutations, name table, must-pass inputs) and Guard 2 rows (four step bodies executed under strict stubs) done ==="

