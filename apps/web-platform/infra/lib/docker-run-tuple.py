#!/usr/bin/env python3
"""docker-run-tuple.py - closed-world check of the web-platform app container's docker run tuples (#10065).

Three `docker run` tuples start the app container on a host: `canary` and `prod` in ci-deploy.sh, `first-boot`
in cloud-init.yml. Each carries the security posture that the /proc mask and the bwrap sandbox depend on
(the soleur-bwrap AppArmor profile, the seccomp profile, a bounded /tmp tmpfs, no added capability, no host
namespace, no environment lever on PATH or the loader). A deny list of option spellings was bypassed every time
a spelling was missed, so this is a CLOSED world: the tuples are tokenized with shlex and every option,
environment name, volume, port and value outside the declared set is a violation, a declared volume, environment name,
port or scalar option that is ABSENT from its tuple is a violation too (MISSING_DECLARED), and every command-position
`docker run|create|...` in the two files is censused so a fourth start site cannot hide.

Usage (stdlib only, run as `python3 -I`):
  docker-run-tuple.py check [--root DIR]
      prints `docker-run-tuple:ok tuples=3 posture=<12 hex>` (exit 0), or one `FAIL <TOKEN>: <detail>` line per
      violation on stdout (exit 1).
  docker-run-tuple.py posture --tuple canary|prod|first-boot [--root DIR]
      runs the same checks, then prints the docker options a suite container should start with, one per line
      (`--init` when the tuple has it, the two `--security-opt` pairs, the `--tmpfs` pair). On a violation it
      prints nothing on stdout, the FAIL lines on stderr, and exits 1.

--root is a repo-root-shaped directory (it holds apps/web-platform/infra/{ci-deploy.sh,cloud-init.yml} and,
optionally, .github/workflows). The layouts <root>/infra and <root> itself (the infra directory) are accepted
too. It defaults to the repo root derived from this file's location.

Tokens: UNKNOWN_OPTION, POSTURE_VALUE, TUPLE_COUNT, POSTURE_DIVERGENCE, ENV_NAME, UNPARSEABLE_OPTION,
UNCLASSIFIED_DOCKER_RUN, TRAILING_ARGS, DUPLICATE_OPTION, MISSING_DECLARED.

What this proves and what it does not: the closed set lives here and the tuples live in the files this parses, and one
diff can edit both, so a green check is CONSISTENCY between the two, not INTEGRITY of the posture. What outside the
commit also has to move for a weakening to pass: the pinned digest literals in docker-run-tuple.test.sh and in
test/docker-run-tuple-posture.test.ts (a second and third file), and, for systempaths=unconfined, the suite's runtime
control arm. The census is a text scan: it covers the two main files plus the app container NAME anywhere under the
infra directory and .github/workflows; a start site of the app image under a variable name in another file is not seen,
and it reads the COMMITTED files only (a container started out of band on a host is not seen). Tracked in #10115.

Stated residuals (outside the closed set by design, not claimed closed): the CONTENT of --env-file (Doppler prd;
ci-deploy.sh overlay_github_app_key refuses runtime-hijack names such as PATH and LD_* only when that overlay
runs; a prd secret SOLEUR_EGRESS_REAPER=1 would give the canary the reaper, and EGRESS_TOKEN_DIR can decouple the
mount from the code, neither of which the argv shows) and the value of -e NODE_OPTIONS (pinned to the
--max-old-space-size assignment lines, not to the flag set). Required-ness (MISSING_DECLARED) covers volumes,
environment NAMES, ports and the scalar options (-d, --restart, --log-driver, --add-host, --env-file, and for the two
deploy starts --init, --memory, --memory-swap) PER TUPLE: the first-boot start has no memory cap or --init by design,
so they are not required there. The scan is a text scan with no control-flow model: a tuple behind an `exit 0`, a start through an indirect docker word (`d=docker; $d run`), a
`docker rename|start|restart|update` of an existing container, and an app start in a file outside the scanned set
are not seen. Containers started on other hosts (the zot registry, the egress gateway) are not part of the closed set.
"""

import argparse
import hashlib
import os
import re
import shlex
import stat
import sys

MAX_LINE = 32768          # a logical line longer than this is never tokenized or regex-scanned
MAX_FILE = 4 << 20        # a scanned file larger than this is skipped (the two main files are far below it)
MAX_FILES = 5000
SCAN_EXT = (".sh", ".bash", ".yml", ".yaml", ".tf", ".tpl", ".service")
SKIP_DIRS = {".git", ".terraform", "node_modules", "fixtures", "test", "tests", "__pycache__"}

MAIN_FILES = ("ci-deploy.sh", "cloud-init.yml")

# --- the declared posture -----------------------------------------------------------------------------------
APPARMOR = "apparmor=soleur-bwrap"
SECCOMP = "seccomp=/etc/docker/seccomp-profiles/soleur-bwrap.json"
TMPFS = "/tmp:rw,nosuid,nodev,size=256m"
LOG_DRIVERS = {"journald"}
ADD_HOSTS = {"host.docker.internal:host-gateway"}
# a positive limit only: `--memory 0` means UNLIMITED in docker, which would pass a bare [0-9]+ pattern
MEM_LITERAL = re.compile(r"^[1-9][0-9]*[bkmgBKMG]?$")

_COMMON_ENV = {
    "INNGEST_BASE_URL": {"http://10.0.1.40:8288"},
    "CRON_WORKSPACE_ROOT": {"/workspaces"},
    "SOLEUR_HOST_ID": {"$HOST_ID"},
}
_VOLS = {"/mnt/data/workspaces:/workspaces", "/mnt/data/plugins/soleur:/app/shared/plugins/soleur:ro"}
# Scalar options a start must CARRY (MISSING_DECLARED); their allowed VALUES are checked separately. The memory cap and
# --init are required on the two deploy starts only: ADR-062 scopes them to ci-deploy.sh's two blocks, and the
# first-boot start has neither today (not required there).
_SCALARS = {"-d", "--log-driver", "--restart", "--env-file", "--add-host"}
_SCALARS_APP = _SCALARS | {"--init", "--memory", "--memory-swap"}
# The host session-token dir (server.tf: 1001:1001, 0711). Prod and first-boot mount it and set SOLEUR_EGRESS_REAPER;
# the canary's argv neither mounts it nor reaps (ADR-278 canary isolation: its /proc cannot see prod forwarders).
_EGRESS_TOKENS_VOL = "/var/lib/soleur/egress-tokens:/var/lib/soleur/egress-tokens"

# tuple name -> declared spec. `file` is the basename of the file the tuple lives in.
TUPLES = {
    "canary": {
        "file": "ci-deploy.sh", "name": "soleur-web-platform-canary", "restart": {"no"},
        "mem_exprs": {"$CANARY_MEMORY_CAP"}, "env_files": {"$ENV_FILE"}, "images": {"$VERIFIED_REF"},
        "env": dict(_COMMON_ENV, NODE_OPTIONS={"$CANARY_NODE_OPTIONS"}),
        "volumes": set(_VOLS), "ports": {"0.0.0.0:3001:3000"}, "scalars": _SCALARS_APP,
    },
    "prod": {
        "file": "ci-deploy.sh", "name": "soleur-web-platform", "restart": {"unless-stopped"},
        "mem_exprs": {"$PROD_MEMORY_CAP"}, "env_files": {"$ENV_FILE"}, "images": {"$VERIFIED_REF"},
        "env": dict(_COMMON_ENV, NODE_OPTIONS={"$PROD_NODE_OPTIONS"}, SOLEUR_EGRESS_REAPER={"1"}),
        "volumes": _VOLS | {_EGRESS_TOKENS_VOL}, "ports": {"0.0.0.0:80:3000", "0.0.0.0:3000:3000"}, "scalars": _SCALARS_APP,
    },
    "first-boot": {
        "file": "cloud-init.yml", "name": "soleur-web-platform", "restart": {"unless-stopped"},
        "mem_exprs": set(), "env_files": {"$TMPENV"}, "images": {"$(cat /run/soleur-image-ref)"},
        "env": {"INNGEST_BASE_URL": {"http://10.0.1.40:8288"}, "SOLEUR_EGRESS_REAPER": {"1"}},
        "volumes": _VOLS | {_EGRESS_TOKENS_VOL},
        "ports": {"0.0.0.0:80:3000", "0.0.0.0:3000:3000"}, "scalars": _SCALARS,
    },
}
TUPLE_ORDER = ("canary", "prod", "first-boot")

# Sites that are allowed to exist next to the app tuples. Matched on (file, verb, name or image expression).
EXEMPT_RUN = {("ci-deploy.sh", "image", "$COSIGN_IMAGE")}      # the cosign verify `docker run --rm`
# Name-keyed exempt runs: (file, --name). The #8743 plugin-mount seed is one
# `docker run --rm --name soleur-plugin-seed -u 0 --entrypoint /bin/sh
# -v $PLUGIN_MOUNT_DIR:/plugin-mount -e SEED_TAG=$TAG $VERIFIED_REF -c <script>`
# — a container-side root seed, not an app tuple.
EXEMPT_RUN_NAMED = {("ci-deploy.sh", "soleur-plugin-seed")}
EXEMPT_CREATE = {
    ("ci-deploy.sh", "$INNGEST_EXTRACT_CONTAINER"),
    ("cloud-init.yml", "soleur-hostscript-seed"),
    ("cloud-init.yml", "soleur-plugin-seed"),
    ("cloud-init.yml", "soleur-inngest-bootstrap-extract"),
}

# option table: name -> kind. Whole-token match only (`-ePATH=x`, `-dit`, `-v/h:/c` match nothing).
FLAGS = {"-d", "--init"}
VALUE_OPTS = {"--name", "--log-driver", "--restart", "--memory", "--memory-swap", "--security-opt", "--tmpfs",
              "--env-file", "--add-host", "-e", "--env", "-v", "-p"}

NAME_RE = re.compile(r"--name(?:=|\s+)[\"']?soleur-web-platform")
HEREDOC_RE = re.compile(r"(?<!<)<<-?\s*([\"']?)([A-Za-z_][A-Za-z0-9_]*)\1")
GLOBAL_OPTS = r"(?:(?:-H|--host|--config|--context|-c|-l|--log-level)(?:\s+|=)\S+|-D|--debug|--tls|--tlsverify)"
DOCKER_WORD = re.compile(r"(?<![\w./$-])(?:/(?:[\w.-]+/)*)?docker(?![\w.-])|(?i:\"?\$\{?\w*DOCKER\w*\}?\"?)")
VERB_RE = re.compile(r"\s+(?:" + GLOBAL_OPTS + r"\s+)*(?P<grp>(?:container|service|compose)\s+)?(?P<verb>run|create|up)\b")
PLAIN_VERB_RE = re.compile(r"\s+(?P<verb>run|create)\b")
INDIRECT_RE = re.compile(r"\b(?:eval|xargs|ssh)\b|\b(?:ba)?sh\s+-\w*c\b")
NODE_ASSIGN_RE = re.compile(r"(?<![\w$])(PROD|CANARY)_NODE_OPTIONS\s*\+?=")
BOUNDARY_WORDS = {"if", "then", "do", "else", "elif", "while", "until", "!", "&&", "||", ";", "|", "&", "(", "{", "time"}
WRAPPERS = {"sudo", "env", "command", "exec", "nohup", "nice", "ionice", "stdbuf", "timeout", "time", "setsid"}
ASSIGN_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=\S*$")
# An exempt site is a named exception to the census, not an exception to the posture, so it is parsed CLOSED-WORLD
# too: a `docker create` is exactly `--name NAME IMAGE` (every real site is), and the cosign verifier run is exactly
# the option set it uses today. Anything else (a volume, a mount, a user, a capability, a privilege flag, a different
# image) is UNCLASSIFIED rather than riding the exemption.
COSIGN_FLAGS = {"--rm", "--quiet"}
COSIGN_VALUE_OPTS = {
    "--network": {"host"},
    "--user": {"$cosign_user"},
    "-e": {"DOCKER_CONFIG=$cosign_cfg_dir"},
    "-v": {"$GHCR_DOCKER_CONFIG:$cosign_cfg_dir/config.json:ro", "$COSIGN_TRUSTED_ROOT_HOST:/etc/cosign/trusted_root.json:ro"},
}
COSIGN_IMAGE = "$COSIGN_IMAGE"
# The #8743 seed run's closed-world option set (image: $VERIFIED_REF, then
# `-c <one script token>` and nothing else).
SEED_RUN_FLAGS = {"--rm"}
SEED_RUN_VALUE_OPTS = {
    "--name": {"soleur-plugin-seed"},
    "-u": {"0"},
    "--entrypoint": {"/bin/sh"},
    "-v": {"$PLUGIN_MOUNT_DIR:/plugin-mount"},
    "-e": {"SEED_TAG=$TAG"},
}
SEED_RUN_IMAGE = "$VERIFIED_REF"
# `case x in a) …`, `a|b) …` and the parenthesised `(a) …` label forms all put a command in command position.
CASE_LABEL_RE = re.compile(r"^\(?[^()\s]*\)$")
TIMEOUT_ARG_RE = re.compile(r"^(?:\d+[smhd]?|-{1,2}[\w-]+(?:=\S*)?)$")


# --- logical lines ----------------------------------------------------------------------------------------
def strip_comment(line):
    """Drop a trailing shell comment: a `#` at a word start, outside quotes."""
    sq = dq = False
    prev = " "
    i = 0
    n = len(line)
    while i < n:
        c = line[i]
        if c == "\\" and not sq:
            i += 2
            prev = "x"
            continue
        if c == "'" and not dq:
            sq = not sq
        elif c == '"' and not sq:
            dq = not dq
        elif c == "#" and not sq and not dq and prev in " \t":
            return line[:i]
        prev = c
        i += 1
    return line


class Logical:
    __slots__ = ("start", "end", "text", "oversize", "heredoc")

    def __init__(self, start, end, text, oversize, heredoc):
        self.start, self.end, self.text, self.oversize, self.heredoc = start, end, text, oversize, heredoc


def heredoc_tags(text, state=(False, False, ())):
    """-> (tags, ambiguous, state). The quote state (sq, dq, stack of enclosing `$(` contexts) is CARRIED in and out so a multi-line quoted string keeps hiding a
    `<<` on its middle lines, and a `$( ... )` substitution has its own quote state. Heredoc tags the line really opens: a `<<` inside quotes or inside `$(( ))` / `(( ))`
    arithmetic is a shift or a string, and treating it as an opener would hide every following line from the census.
    A `<<` met inside a construct this small lexer does not model (`${ }`, `$[ ]`, `$'...'`, `[[ ]]`) cannot be
    decided either way, so it is reported as AMBIGUOUS (a violation) instead of being guessed."""
    tags = []
    ambiguous = False
    sq, dq, stack0 = state
    stack = list(stack0)    # (sq, dq) of the enclosing context for each open `$( ... )`
    arith = 0
    brace = 0       # ${ ... } nesting
    bracket = 0     # $[ ... ] nesting
    cond = 0        # [[ ... ]] nesting
    ansi = False    # $'...' (backslash escapes the quote)
    i = 0
    n = len(text)
    while i < n:
        c = text[i]
        if ansi:
            if c == "\\":
                i += 2
                continue
            if c == "'":
                ansi = False
            elif text.startswith("<<", i):
                ambiguous = True
            i += 1
            continue
        if c == "\\" and not sq:
            i += 2
            continue
        if not sq and text.startswith("$(", i) and not text.startswith("$((", i):
            stack.append((sq, dq))
            sq = dq = False
            i += 2
            continue
        if c == ")" and stack and not sq and not dq:
            sq, dq = stack.pop()
            i += 1
            continue
        if c == "'" and not dq:
            if not sq and i > 0 and text[i - 1] == "$":
                ansi = True
            else:
                sq = not sq
        elif c == '"' and not sq:
            dq = not dq
        elif not sq and not dq:
            if text.startswith("${", i):
                brace += 1
                i += 2
                continue
            if text.startswith("$[", i):
                bracket += 1
                i += 2
                continue
            if text.startswith("[[", i):
                cond += 1
                i += 2
                continue
            if cond and text.startswith("]]", i):
                cond -= 1
                i += 2
                continue
            if brace and c == "}":
                brace -= 1
            elif bracket and c == "]":
                bracket -= 1
            elif text.startswith("((", i):
                arith += 1
                i += 2
                continue
            elif arith and text.startswith("))", i):
                arith -= 1
                i += 2
                continue
            elif text.startswith("<<", i) and not text.startswith("<<<", i):
                if brace or bracket or cond:
                    ambiguous = True
                elif not arith:
                    m = HEREDOC_RE.match(text, i)
                    if m:
                        tags.append(m.group(2))
                        i = m.end()
                        continue
        i += 1
    return tags, ambiguous, (sq, dq, tuple(stack))


def ends_with_continuation(raw):
    k = len(raw) - len(raw.rstrip("\\"))
    return k % 2 == 1


def logical_lines(text):
    """Bash-faithful logical lines. Backslash-newline joins; a comment-only line inside a continuation ends the
    command (bash turns `cmd \\` + `# note` into `cmd # note`); heredoc bodies are yielded as heredoc lines.
    Returns (lines, unterminated, ambiguous): unterminated is a list of (tag, lineno), ambiguous a list of linenos."""
    phys = text.split("\n")
    out = []
    unterminated = []
    ambiguous = []        # line numbers whose `<<` sits in a construct the lexer does not model
    qstate = (False, False, ())     # quote state carried across logical lines (a multi-line quoted string, an open `$(`)
    pending = []          # heredoc tags opened by the current logical line, in order
    active = None         # (tag, opened_at_line)
    i = 0
    n = len(phys)
    while i < n:
        raw = phys[i].rstrip("\r")
        if active is not None:
            if raw.strip() == active[0]:
                active = (pending.pop(0), i + 1) if pending else None
            else:
                out.append(Logical(i + 1, i + 1, raw[:MAX_LINE], len(raw) > MAX_LINE, True))
            i += 1
            continue
        start = i
        cur = strip_comment(raw)
        cont = cur == raw and ends_with_continuation(raw)
        parts = [cur[:-1] if cont else cur]
        size = len(raw)
        while cont and i + 1 < n:
            i += 1
            nraw = phys[i].rstrip("\r")
            nstrip = strip_comment(nraw)
            size += len(nraw)
            if nstrip.strip() == "" and nraw.strip().startswith("#"):
                break
            cont = nstrip == nraw and ends_with_continuation(nraw)
            if size <= MAX_LINE:
                parts.append((nstrip[:-1] if cont else nstrip).strip())
        joined = " ".join(parts)
        out.append(Logical(start + 1, i + 1, joined[:MAX_LINE], size > MAX_LINE, False))
        tags, ambiguous_here, qstate = heredoc_tags(joined[:MAX_LINE], qstate)
        if ambiguous_here:
            ambiguous.append(start + 1)
        if tags:
            active = (tags[0], start + 1)
            pending = tags[1:]
        i += 1
    if active is not None:
        unterminated.append((active[0], active[1]))
    for tag in pending:
        unterminated.append((tag, 0))
    return out, unterminated, ambiguous


# --- census -------------------------------------------------------------------------------------------------
# Words whose arguments are DATA, never a command: a `docker run` after one of these is text (a message, a pattern, a path).
# Every other statement-leading word is treated as a possible wrapper (`flock -n /l docker run`, `sudo -u root docker run`,
# `runuser -u root -- docker run`...), because a wrapper allowlist is open-ended and a miss is a hidden start site.
NON_EXEC_LEADERS = {
    "echo", "printf", "grep", "egrep", "fgrep", "sed", "awk", "cat", "test", "[", "[[", "read", "log", "warn", "die", "info",
    "error", "fail", "pass", "return", "local", "export", "declare", "readonly", "set", "unset", "source", ".", "cd", "jq",
    "curl", "tee", "head", "tail", "wc", "sort", "cut", "tr", "ls", "rm", "mkdir", "mv", "cp", "chmod", "chown", "ln", "touch",
    "sleep", "kill", "logger", "emit", "case", "for", "select", "wait", "trap", "type", "which", "command -v", "diff", "cmp",
    "stat", "find", "xargs", "true", "false", ":", "shift", "getopts", "mapfile", "readarray", "tar", "gzip", "zcat", "sha256sum",
}


def cmd_position(prefix):
    toks = prefix.split()
    i = len(toks)
    while i > 0:
        t = toks[i - 1]
        if t in BOUNDARY_WORDS or t.endswith((";", "(", "{", "|", "&", "`")) or CASE_LABEL_RE.match(t):
            return True
        if t == "-" and i == 1:
            return True            # YAML list marker
        if t in WRAPPERS or ASSIGN_RE.match(t) or t.startswith(("$", '"$', "${", '"${')) or TIMEOUT_ARG_RE.match(t):
            i -= 1
            continue
        return wrapped_command_position(toks)
    return True


def wrapped_command_position(toks):
    """A docker word reached through a wrapper this table does not list: walk back to the statement start and treat the
    word as a command unless the statement leads with a data-taking word or the docker word sits inside an open quote."""
    prefix = " ".join(toks)
    if prefix.count("'") % 2 or prefix.count('"') % 2:
        return False                                  # inside a quoted string
    i = len(toks)
    while i > 0:
        t = toks[i - 1]
        if t in BOUNDARY_WORDS or t.endswith((";", "(", "{", "|", "&", "`")) or CASE_LABEL_RE.match(t) or (t == "-" and i == 1):
            break
        i -= 1
    stmt = [t for t in toks[i:] if not ASSIGN_RE.match(t)]
    if not stmt:
        return True
    return stmt[0].strip("\"'") not in NON_EXEC_LEADERS and not stmt[0].startswith("#")


def tokenize(text):
    lex = shlex.shlex(text, posix=True, punctuation_chars=True)
    lex.whitespace_split = True
    lex.commenters = ""
    return list(lex)


def has_exp(s):
    return "$" in s or "`" in s


class Site:
    pass


QUOTED_DOCKER = re.compile(r"([\"'])docker\1")


def find_sites(lines, fname):
    """Command-position docker sites. Returns a list of Site (prefix, tokens, verb, group, ...)."""
    sites = []
    for lg in lines:
        if lg.heredoc or lg.oversize or "docker" not in lg.text.lower():
            continue
        text = QUOTED_DOCKER.sub("docker", lg.text)      # `"docker" run` is the same command
        for m in DOCKER_WORD.finditer(text):
            if not cmd_position(text[:m.start()]):
                continue
            rest = text[m.end():]
            vm = VERB_RE.match(rest)
            if not vm:
                continue
            s = Site()
            s.file = fname
            s.line = lg.start
            s.end_line = lg.end
            s.prefix = text[:m.start()].split()
            s.verb = vm.group("verb")
            s.group = (vm.group("grp") or "").strip()
            s.plain = PLAIN_VERB_RE.match(rest) is not None and not s.group
            s.text = text[m.start():]
            try:
                s.toks = tokenize(s.text)
            except ValueError as e:
                s.toks = None
                s.tok_error = str(e)
            s.name = None
            if s.toks is not None:
                for k, t in enumerate(s.toks):
                    if t == "--name" and k + 1 < len(s.toks):
                        s.name = s.toks[k + 1]
                        break
                    if t.startswith("--name="):
                        s.name = t.split("=", 1)[1]
                        break
            else:
                nm = re.search(r"--name(?:=|\s+)[\"']?([\w$.{}-]+)", s.text)
                s.name = nm.group(1) if nm else None
            sites.append(s)
    return sites


# --- option walk -------------------------------------------------------------------------------------------
class Record:
    def __init__(self):
        self.apparmor = []
        self.seccomp = []
        self.tmpfs = []
        self.init = False
        self.volumes = set()      # the -v, -e NAME and -p values the tuple actually carries (check_declared)
        self.env = set()
        self.ports = set()
        self.scalars = set()      # the scalar options (-d, --restart, --memory, --env-file, ...) the tuple carries


def walk_options(site, spec, tuple_name):
    """Tokens after `docker run` -> (record, violations). Closed-world: anything not in the table is a violation."""
    rec = Record()
    viols = []
    where = " in %s %s (line %d)" % (site.file, tuple_name, site.line)

    def v(token, detail):
        viols.append("FAIL %s: %s%s" % (token, detail, where))

    toks = site.toks
    # the statement ends at the first punctuation token (`;`, `&&`, `|`, `>`...); only `; then` may follow an app tuple
    end = len(toks)
    for k, t in enumerate(toks):
        if t and all(c in "();<>|&" for c in t):
            end = k
            break
    tail = toks[end:]
    opts = toks[2:end]
    n = len(opts)
    seen = {}
    env_seen = set()
    image = None
    trailing = []
    i = 0
    while i < n:
        t = opts[i]
        if image is not None:
            trailing.append(t)
            i += 1
            continue
        if t.startswith("-") and t != "-":
            long_form = t.startswith("--")
            if long_form and "=" in t:
                name, val = t.split("=", 1)
                has_val = True
            else:
                name, val, has_val = t, None, False
            if name not in FLAGS and name not in VALUE_OPTS:
                v("UNKNOWN_OPTION", name)
                # unknown option: swallow a plain value token (never the image, never an option, never an attached short form)
                if not has_val and (long_form or len(t) == 2) and i + 1 < n - 1 and not opts[i + 1].startswith("-"):
                    i += 1
                i += 1
                continue
            if name in FLAGS:
                if has_val:
                    v("UNKNOWN_OPTION", t)
                else:
                    if name in seen:
                        v("DUPLICATE_OPTION", name)
                    seen[name] = True
                    rec.scalars.add(name)
                    if name == "--init":
                        rec.init = True
                i += 1
                continue
            if not has_val:
                if i + 1 < n:
                    val = opts[i + 1]
                    i += 1
                else:
                    v("UNPARSEABLE_OPTION", "missing value for %s" % name)
                    i += 1
                    continue
            i += 1
            check_value(name, val, spec, rec, seen, env_seen, v)
            continue
        if has_exp(t) and t not in spec["images"]:
            v("UNPARSEABLE_OPTION", "expansion %s in option position" % t)
            i += 1
            continue
        image = t
        i += 1
    if image is None:
        v("UNPARSEABLE_OPTION", "no image")
    elif image not in spec["images"]:
        v("UNPARSEABLE_OPTION", "unknown image %s" % image)
    if trailing:
        v("TRAILING_ARGS", " ".join(trailing))
    if tail:
        if tail[0] != ";" or any(x not in ("then",) for x in tail[1:]):
            v("TRAILING_ARGS", " ".join(tail))
    return rec, viols


def check_value(name, val, spec, rec, seen, env_seen, v):
    rec.scalars.add(name)
    def bad(token, label):
        v("UNPARSEABLE_OPTION" if has_exp(val) else token, label)

    def once(key, label):
        if key in seen:
            v("DUPLICATE_OPTION", label)
        seen[key] = True

    if name == "--name":
        once(name, name)
        if val != spec["name"]:
            bad("POSTURE_VALUE", "--name %s" % val)
    elif name == "--log-driver":
        once(name, name)
        if val not in LOG_DRIVERS:
            bad("POSTURE_VALUE", "--log-driver %s" % val)
    elif name == "--restart":
        once(name, name)
        if val not in spec["restart"]:
            bad("POSTURE_VALUE", "--restart %s" % val)
    elif name in ("--memory", "--memory-swap"):
        once(name, name)
        if not (MEM_LITERAL.match(val) or val in spec["mem_exprs"]):
            bad("POSTURE_VALUE", "%s %s" % (name, val))
    elif name == "--security-opt":
        if val == APPARMOR:
            if rec.apparmor:
                v("DUPLICATE_OPTION", "--security-opt apparmor")
            rec.apparmor.append(val)
        elif val == SECCOMP:
            if rec.seccomp:
                v("DUPLICATE_OPTION", "--security-opt seccomp")
            rec.seccomp.append(val)
        else:
            bad("POSTURE_VALUE", "--security-opt %s" % val)
    elif name == "--tmpfs":
        if rec.tmpfs:
            v("DUPLICATE_OPTION", "--tmpfs")
        rec.tmpfs.append(val)
        if val != TMPFS:
            bad("POSTURE_VALUE", "--tmpfs %s" % val)
    elif name == "--env-file":
        once(name, name)
        if val not in spec["env_files"]:
            bad("POSTURE_VALUE", "--env-file %s" % val)
    elif name == "--add-host":
        if val not in ADD_HOSTS:
            bad("POSTURE_VALUE", "--add-host %s" % val)
    elif name in ("-e", "--env"):
        if "=" not in val:
            v("ENV_NAME", "%s (no value)" % val)
            return
        ename, evalue = val.split("=", 1)
        if ename not in spec["env"]:
            v("ENV_NAME", ename)
            return
        if ename in env_seen:
            v("DUPLICATE_OPTION", "-e %s" % ename)
        env_seen.add(ename)
        rec.env.add(ename)
        if evalue not in spec["env"][ename]:
            if has_exp(evalue):
                v("UNPARSEABLE_OPTION", "-e %s=%s" % (ename, evalue))
            else:
                v("ENV_NAME", "%s value '%s'" % (ename, evalue))
    elif name == "-v":
        rec.volumes.add(val)
        if val not in spec["volumes"]:
            bad("UNKNOWN_OPTION", "-v %s" % val)
    elif name == "-p":
        rec.ports.add(val)
        if val not in spec["ports"]:
            bad("UNKNOWN_OPTION", "-p %s" % val)


# --- the arms (each returns a list of violation lines; the battery stubs them one at a time) ----------------
def check_options(app_sites):
    out = []
    for s in app_sites:
        out.extend(s.option_viols)
    return out


def check_declared(app_sites):
    """Every volume, env name, port and scalar option a tuple DECLARES must be present on its site. check_options only refuses
    members outside the declared set, so a deleted member (the egress-token mount on the prod start) passed."""
    out = []
    for s in app_sites:
        # A site that already reds UNPARSEABLE_OPTION (tokenization failed, or the tuple is truncated so "no image")
        # has an incomplete record: reporting every member after the cut as missing too is noise on top of that red.
        if s.toks is None or any(v.startswith("FAIL UNPARSEABLE_OPTION") for v in s.option_viols):
            continue
        spec = TUPLES[s.tuple]
        for kind, declared, got in (("volume", spec["volumes"], s.rec.volumes),
                                    ("env", set(spec["env"]), s.rec.env),
                                    ("port", spec["ports"], s.rec.ports),
                                    ("option", spec["scalars"], s.rec.scalars)):
            for member in sorted(declared - set(got)):
                out.append("FAIL MISSING_DECLARED: %s %s missing from %s %s (declared in TUPLES)" % (kind, member, s.file, s.tuple))
    return out


def check_count(app_sites, unreadable):
    out = ["FAIL TUPLE_COUNT: cannot read %s (%s)" % (f, why) for f, why in unreadable]
    got = len(app_sites)
    ids = sorted("%s:%d %s" % (s.file, s.line, s.tuple) for s in app_sites)
    if got != 3:
        out.append("FAIL TUPLE_COUNT: want 3 got %d (found: %s)" % (got, ", ".join(ids) or "none"))
    else:
        names = sorted(s.tuple for s in app_sites)
        if names != sorted(TUPLE_ORDER):
            out.append("FAIL TUPLE_COUNT: want one each of %s got %s" % (", ".join(TUPLE_ORDER), ", ".join(names)))
    return out


def projection_of(rec):
    return (tuple(rec.apparmor), tuple(rec.seccomp), tuple(rec.tmpfs))


def check_projection(app_sites):
    out = []
    want = ((APPARMOR,), (SECCOMP,), (TMPFS,))
    for s in app_sites:
        got = projection_of(s.rec)
        if got != want:
            missing = [lbl for lbl, g, w in (("--security-opt %s" % APPARMOR, got[0], want[0]),
                                            ("--security-opt %s" % SECCOMP, got[1], want[1]),
                                            ("--tmpfs %s" % TMPFS, got[2], want[2])) if g != w]
            out.append("FAIL POSTURE_DIVERGENCE: %s %s posture differs from the declared projection, missing or wrong: %s"
                       % (s.file, s.tuple, "; ".join(missing)))
    return out


def check_census_extra(extra):
    return list(extra)


def check_node_options(file_lines):
    """The NODE_OPTIONS assignment lines in ci-deploy.sh are pinned to the --max-old-space-size form, once each."""
    out = []
    found = {"PROD": [], "CANARY": []}
    for lg in file_lines:
        if lg.heredoc:
            continue
        for m in NODE_ASSIGN_RE.finditer(lg.text):
            found[m.group(1)].append((lg.start, lg.text[m.start():]))
    for k in ("PROD", "CANARY"):
        want = '%s_NODE_OPTIONS="--max-old-space-size=$%s_NODE_MAX_OLD_SPACE_MB"' % (k, k)
        entries = found[k]
        ok = len(entries) == 1 and entries[0][1].strip() == want
        if not ok:
            where = ", ".join("line %d" % e[0] for e in entries) or "none found"
            out.append("FAIL ENV_NAME: NODE_OPTIONS assignment of %s_NODE_OPTIONS must be exactly one line %s (got %d: %s) in ci-deploy.sh"
                       % (k, want, len(entries), where))
    return out


# --- scanning ----------------------------------------------------------------------------------------------
def resolve_layout(root):
    """-> (infra_dir, workflows_dir_or_None)"""
    cands = [os.path.join(root, "apps", "web-platform", "infra"), os.path.join(root, "infra"), root]
    infra = cands[0]
    for c in cands:
        if any(os.path.isfile(os.path.join(c, f)) for f in MAIN_FILES):
            infra = c
            break
    wf = os.path.join(root, ".github", "workflows")
    return infra, (wf if os.path.isdir(wf) else None)


def read_text(path):
    try:
        st = os.lstat(path)
        if not stat.S_ISREG(st.st_mode):
            return None, "not a regular file (a symlink or device is never followed)"
        if st.st_size > MAX_FILE:
            return None, "larger than %d bytes" % MAX_FILE
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            data = fh.read(MAX_FILE + 1)
        if len(data) > MAX_FILE:
            return None, "larger than %d bytes" % MAX_FILE
        return data, None
    except OSError as e:
        return None, str(e.strerror or e)


def relname(path, root):
    try:
        return os.path.relpath(path, root)
    except ValueError:
        return path


def scan(root):
    infra, wf = resolve_layout(root)
    app_sites = []
    extra = []        # UNCLASSIFIED_DOCKER_RUN lines
    scan_viols = []   # unterminated heredoc, oversize line (never stubbed: they bound the scan itself)
    unreadable = []
    node_viols = []
    covered = {}      # file -> set of line numbers owned by an accepted app tuple or already reported

    for fname in MAIN_FILES:
        text, why = read_text(os.path.join(infra, fname))
        if text is None:
            unreadable.append((fname, why))
            continue
        lines, unterminated, ambiguous = logical_lines(text)
        for ln in ambiguous:
            scan_viols.append("FAIL UNPARSEABLE_OPTION: a heredoc opener inside ${ }, $[ ], $'...' or [[ ]] in %s:%d cannot be decided "
                              "(bash may or may not open a heredoc there, which would hide every following line); rewrite the line" % (fname, ln))
        for tag, ln in unterminated:
            scan_viols.append("FAIL UNPARSEABLE_OPTION: unterminated heredoc %s in %s:%d" % (tag, fname, ln))
        for lg in lines:
            if lg.oversize and "docker" in lg.text.lower():
                scan_viols.append("FAIL UNPARSEABLE_OPTION: logical line over %d bytes mentions docker in %s:%d (not scanned)"
                                  % (MAX_LINE, fname, lg.start))
        own = covered.setdefault(fname, set())
        for s in find_sites(lines, fname):
            reason = classify_site(s, fname)
            if reason is None:
                if s.kind == "app":
                    own.update(range(s.line, s.end_line + 1))
                    app_sites.append(s)
                # an exempt site does NOT own its lines: the indirect-wrapper and app-name scans below still read them
            else:
                own.update(range(s.line, s.end_line + 1))
                extra.append("FAIL UNCLASSIFIED_DOCKER_RUN: %s:%d %s" % (fname, s.line, reason))
        for lg in lines:
            if lg.heredoc or lg.oversize or lg.start in own or "docker" not in lg.text.lower():
                continue
            if INDIRECT_RE.search(lg.text) and docker_verb_anywhere(lg.text):
                own.update(range(lg.start, lg.end + 1))
                extra.append("FAIL UNCLASSIFIED_DOCKER_RUN: %s:%d docker verb inside an indirect execution wrapper" % (fname, lg.start))
        # the app name anywhere (heredoc bodies and strings included) outside an accepted tuple is a start site we did not parse
        for idx, raw in enumerate(text.split("\n"), 1):
            if len(raw) > MAX_LINE * 8:
                raw = raw[:MAX_LINE * 8]
            if "soleur-web-platform" in raw and NAME_RE.search(strip_comment(raw)) and idx not in own:
                extra.append("FAIL UNCLASSIFIED_DOCKER_RUN: %s:%d --name soleur-web-platform outside a declared tuple" % (fname, idx))
        if fname == "ci-deploy.sh":
            node_viols = check_node_options(lines)

    # wider scope: the app container name in any other deployable text
    seen = 0
    targets = []
    for base in (infra, wf):
        if not base:
            continue
        for dp, dns, fns in os.walk(base):
            dns[:] = sorted(d for d in dns if d not in SKIP_DIRS)
            for fn in sorted(fns):
                if not fn.endswith(SCAN_EXT) or fn.endswith(".test.sh"):
                    continue
                path = os.path.join(dp, fn)
                if os.path.dirname(path) == infra and fn in MAIN_FILES:
                    continue
                targets.append(path)
    for path in targets:
        seen += 1
        if seen > MAX_FILES:
            scan_viols.append("FAIL UNPARSEABLE_OPTION: more than %d files to scan under %s" % (MAX_FILES, root))
            break
        text, why = read_text(path)
        if text is None:
            scan_viols.append("FAIL UNPARSEABLE_OPTION: cannot scan %s (%s); a file that cannot be read cannot be shown free of an app start site"
                              % (relname(path, root), why))
            continue
        if "soleur-web-platform" not in text:
            continue
        for idx, raw in enumerate(text.split("\n"), 1):
            if "soleur-web-platform" in raw and NAME_RE.search(strip_comment(raw[:MAX_LINE * 8])):
                extra.append("FAIL UNCLASSIFIED_DOCKER_RUN: %s:%d --name soleur-web-platform outside a declared tuple" % (relname(path, root), idx))
    return app_sites, extra, scan_viols, unreadable, node_viols


def docker_verb_anywhere(text):
    for m in DOCKER_WORD.finditer(text):
        if VERB_RE.match(text[m.end():]):
            return True
    return False


def classify_site(s, fname):
    """Set s.kind ('app' | 'exempt'); return None when accepted, else the UNCLASSIFIED reason."""
    s.kind = None
    if s.toks is None:
        if s.name and s.name.startswith("soleur-web-platform"):
            # an app tuple we cannot tokenize still counts as a tuple; its tokenization failure is the violation
            ident = identify(s.name, fname)
            if ident and s.plain and s.prefix_ok():
                s.kind, s.tuple = "app", ident
                s.rec = Record()
                s.option_viols = ["FAIL UNPARSEABLE_OPTION: tokenization failed (%s) in %s %s (line %d)"
                                  % (getattr(s, "tok_error", "?"), fname, ident, s.line)]
                return None
        return "docker %s %s whose arguments cannot be tokenized (%s)" % (s.group, s.verb, getattr(s, "tok_error", "?"))
    name = s.name
    if name and name.startswith("soleur-web-platform"):
        ident = identify(name, fname)
        if not s.plain or s.verb != "run":
            return "docker %s%s of the app container name '%s' (only a plain `docker run` start is declared)" % (s.group + " " if s.group else "", s.verb, name)
        if not ident:
            return "undeclared app container name '%s' in %s" % (name, fname)
        if not s.prefix_ok():
            return "app tuple %s run behind an unexpected command prefix '%s'" % (ident, " ".join(s.prefix))
        s.kind, s.tuple = "app", ident
        spec = TUPLES[ident]
        s.rec, s.option_viols = walk_options(s, spec, ident)
        return None
    # exempt sites
    if s.verb == "run" and s.plain and "--rm" in s.toks and any((fname, "image", t) in EXEMPT_RUN for t in s.toks):
        bad = exempt_run_violation(s)
        if bad:
            return "the cosign verifier run %s (an exempt site is parsed closed-world: only its real option set is allowed)" % bad
        s.kind = "exempt"
        return None
    if s.verb == "run" and s.plain and name is not None and (fname, name) in EXEMPT_RUN_NAMED:
        bad = seed_run_violation(s)
        if bad:
            return "exempt `docker run` of %s %s (an exempt site is parsed closed-world: only its real option set is allowed)" % (name, bad)
        s.kind = "exempt"
        return None
    if s.verb == "create" and s.plain and name is not None and (fname, name) in EXEMPT_CREATE:
        bad = exempt_create_violation(s)
        if bad:
            return "exempt `docker create` of %s %s (an exempt create is exactly `--name NAME IMAGE`)" % (name, bad)
        s.kind = "exempt"
        return None
    return "docker %s%s site that is neither a declared app tuple nor a named exemption (name %s)" % (
        s.group + " " if s.group else "", s.verb, name if name is not None else "none")


def _statement(toks):
    """Tokens up to the first punctuation token (`;`, `&&`, `|`, a redirect): the docker command's own words."""
    for k, t in enumerate(toks):
        if t and all(c in "();<>|&" for c in t):
            return toks[:k]
    return toks


# The image words the real exempt creates use (shlex has already removed the quotes). Closed list: a variable that is not
# named here could carry a word-split `--privileged IMG`.
EXEMPT_IMAGES = {"$IMAGE_REF", "$VERIFIED_REF", "$IREF", "$IMAGE:$TAG", "$(cat /run/soleur-image-ref)"}


def exempt_image_ok(word):
    return word in EXEMPT_IMAGES


def exempt_create_violation(s):
    words = _statement(s.toks)
    # docker create --name NAME IMAGE   (nothing between, nothing after the image before the statement ends)
    if len(words) == 5 and words[2] == "--name" and exempt_image_ok(words[4]):
        return None
    if len(words) == 4 and words[2].startswith("--name=") and exempt_image_ok(words[3]):
        return None
    return "carries words beyond `--name NAME IMAGE`: %s" % " ".join(words[2:8])


def exempt_run_violation(s):
    words = _statement(s.toks)
    i = 2
    n = len(words)
    while i < n:
        t = words[i]
        if t in COSIGN_FLAGS:
            i += 1
            continue
        if t in COSIGN_VALUE_OPTS:
            if i + 1 >= n or words[i + 1] not in COSIGN_VALUE_OPTS[t]:
                return "has an unexpected value for %s" % t
            i += 2
            continue
        if t.startswith("-"):
            return "carries the option %s" % t
        if t != COSIGN_IMAGE:
            return "starts a different image or command (%s) instead of %s" % (t, COSIGN_IMAGE)
        return None
    return "has no image"


def seed_run_violation(s):
    words = _statement(s.toks)
    i = 2
    n = len(words)
    while i < n:
        t = words[i]
        if t in SEED_RUN_FLAGS:
            i += 1
            continue
        if t in SEED_RUN_VALUE_OPTS:
            if i + 1 >= n or words[i + 1] not in SEED_RUN_VALUE_OPTS[t]:
                return "has an unexpected value for %s" % t
            i += 2
            continue
        if t.startswith("--name="):
            if t.split("=", 1)[1] != "soleur-plugin-seed":
                return "names a different container (%s)" % t
            i += 1
            continue
        if t.startswith("-"):
            return "carries the option %s" % t
        if t != SEED_RUN_IMAGE:
            return "starts a different image or command (%s) instead of %s" % (t, SEED_RUN_IMAGE)
        # image reached: `-c` plus exactly one script token, then the statement ends
        if i + 2 < n and words[i + 1] == "-c" and i + 3 == n:
            return None
        if i + 1 < n:
            return "carries words beyond `%s -c <script>`: %s" % (SEED_RUN_IMAGE, " ".join(words[i + 1:i + 6]))
        return "has no `-c <script>` command after the image"
    return "has no image"


def _prefix_ok(self):
    return all(t in ("if", "!") for t in self.prefix)


Site.prefix_ok = _prefix_ok


def identify(name, fname):
    for tname, spec in TUPLES.items():
        if spec["file"] == fname and spec["name"] == name:
            return tname
    return None


def run_checks(root):
    app_sites, extra, scan_viols, unreadable, node_viols = scan(root)
    viols = []
    viols.extend(scan_viols)
    viols.extend(check_count(app_sites, unreadable))
    viols.extend(check_options(app_sites))
    viols.extend(check_declared(app_sites))
    viols.extend(check_projection(app_sites))
    viols.extend(check_census_extra(extra))
    viols.extend(node_viols)
    return app_sites, viols


def digest():
    proj = "%s\n%s\n%s\n" % (APPARMOR, SECCOMP, "tmpfs=" + TMPFS)
    return hashlib.sha256(proj.encode()).hexdigest()[:12]


HINTS = {
    "UNKNOWN_OPTION": "remove the option from the tuple; widen the closed set here only with a security review, a posture option is never an allowlist entry",
    "POSTURE_VALUE": "restore the declared value; the declared posture constants are edited only with a security review",
    "ENV_NAME": "remove the environment variable from the tuple (PATH, loader and runtime-hijack names are never allowed)",
    "DUPLICATE_OPTION": "keep exactly one occurrence; docker honours the last, so a second one hides the first",
    "TRAILING_ARGS": "nothing may follow the image except `; then`",
    "TUPLE_COUNT": "a start site was added, moved or renamed: declare it together with the site and keep the three-tuple expectation; never lower the count (when the line says `cannot read`, a scanned file is missing, unreadable or not a regular file: restore it)",
    "UNCLASSIFIED_DOCKER_RUN": "declare it as an app tuple, or add a NAMED non-app exemption (EXEMPT_RUN / EXEMPT_CREATE) ONLY with a security review: an exempt site is closed-world too (a create is exactly `--name NAME IMAGE`)",
    "MISSING_DECLARED": "restore the named volume, env, port or scalar option on the tuple, or remove it from TUPLES in the same commit with the reason (a tuple that drops a declared member silently loses that behaviour)",
    "POSTURE_DIVERGENCE": "restore the apparmor, seccomp and tmpfs options on the named tuple",
    "UNPARSEABLE_OPTION": "make the option literal; a variable, substitution or ambiguous heredoc opener is refused, and a file that cannot be read cannot be shown free of a start site",
}


def hints(viols):
    seen = []
    for line in viols:
        tok = line.split(":", 1)[0].replace("FAIL ", "", 1)
        if tok in HINTS and tok not in seen:
            seen.append(tok)
    return ["HINT %s: %s" % (t, HINTS[t]) for t in seen]


def default_root():
    here = os.path.dirname(os.path.abspath(__file__))
    return os.path.abspath(os.path.join(here, "..", "..", "..", ".."))


def main(argv):
    ap = argparse.ArgumentParser(prog="docker-run-tuple.py", description="closed-world check of the app container docker run tuples")
    sub = ap.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("check")
    c.add_argument("--root", default=None)
    p = sub.add_parser("posture")
    p.add_argument("--tuple", dest="tuple_name", required=True, choices=list(TUPLE_ORDER))
    p.add_argument("--root", default=None)
    args = ap.parse_args(argv)
    root = os.path.abspath(args.root) if args.root else default_root()
    app_sites, viols = run_checks(root)
    if args.cmd == "check":
        if viols:
            for line in viols:
                print(line)
            for line in hints(viols):
                print(line)
            return 1
        print("docker-run-tuple:ok tuples=%d posture=%s" % (len(app_sites), digest()))
        return 0
    if viols:
        for line in viols + hints(viols):
            print(line, file=sys.stderr)
        return 1
    site = [s for s in app_sites if s.tuple == args.tuple_name][0]
    if site.rec.init:
        print("--init")
    print("--security-opt " + APPARMOR)
    print("--security-opt " + SECCOMP)
    print("--tmpfs " + TMPFS)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
