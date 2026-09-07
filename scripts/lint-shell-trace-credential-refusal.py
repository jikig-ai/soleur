#!/usr/bin/env python3
"""Require the xtrace refusal in every shell script that binds a live credential.

WHY THIS EXISTS (#7797). Shell tracing echoes commands AFTER expansion, so a
secret leaks the moment it is bound to a variable -- before it reaches any
command. Two live API tokens reached an agent transcript that way. PR #7793
fixed the one affected script with a five-line preamble; this lint makes that
preamble the rule rather than a one-off.

WHY A COMMIT-TIME LINT AND NOT A HARNESS HOOK. `case "$-" in *x*)` tests whether
tracing is ON. A boundary interceptor must instead enumerate the ways to turn it
on -- measured at eight forms, two of which carry no `-x` token at all
(`env SHELLOPTS=xtrace`, `env BASH_ENV=<file with set -x>`). `BASH_XTRACEFD`
only REDIRECTS an already-enabled trace; measured, it enables nothing.
That list cannot be proven complete; the state test needs no list. The
interceptor is the COMPLEMENT, scoped to what is never committed (ad-hoc
`bash -c`, scripts the model wrote but never committed) -- filed separately.

TWO RULES, because the preamble is a point-in-time assertion and not an
invariant:
  Rule A (prologue) -- the refusal must appear before any command other than
      set/shopt. Stated as a prologue rule rather than "before the first bind"
      because the latter couples the ORDER dimension to the drifting signal list
      (adding a class could retroactively fail a file that passed yesterday) and
      is undecidable anyway: function hoisting, a `source` above the preamble,
      and quoted heredocs defeat a static bind-detector in BOTH directions.
  Rule B (below)    -- no trace-enabling token after the preamble. Measured: a
      `set -x` below a compliant preamble leaks every subsequent bind, and the
      five hand-written `set -x` warnings across three workflows are warning
      about exactly this shape.

SCOPE EXCLUSIONS, each with a reason:
  *.test.sh / tests/  -- suites synthesize fake tokens per
      cq-test-fixtures-synthesized-only, and the file you most need `bash -x` on
      is the failing suite.
  scripts/lib/*.sh    -- a sourced `exit` terminates the SOURCING parent.

EXIT CODES (mirroring lint-credential-path-literals.py):
  0  clean
  1  violations found
  2  cannot evaluate -- unreadable/unparseable input, or a git error. Fail
     closed: a gate that cannot evaluate must not silently pass (ADR-157).
"""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
BASELINE_FILE = Path(__file__).resolve().parent / "lint-shell-trace-credential-refusal.baseline.txt"
# Rule D gets its OWN baseline, and that separation is the whole reason it can
# ever fail. The A/B/C baseline suppresses by FILE (`if rel not in baseline`),
# which drops every rule's findings for that file -- and all seven of Rule D's
# target sites are already in it, because they were baselined for the xtrace
# refusal. Inheriting it would have shipped a guard that is green over precisely
# the population it was written for, on the repo-wide run that is the blocking arm.
BASELINE_D_FILE = Path(__file__).resolve().parent / "lint-shell-trace-credential-refusal-d.baseline.txt"
# Rule D also carries a ratchet, which this lint had for no rule: it has --census
# and --write-baseline but no .highwater, so the deferred population could grow
# silently. Modelled on lint-supabase-deprecated-endpoints / lint-diagnosis-claims
# / lint-trap-tempfile-ownership / alarm-issue-filing-guard -- one integer plus a
# provenance header, ratcheting DOWN only.
HIGHWATER_D_FILE = Path(__file__).resolve().parent / "lint-shell-trace-credential-refusal-d.highwater"

# --- SECRET_SIGNALS ----------------------------------------------------------
# A file is IN SCOPE when it binds or expands a live credential. Each class is
# named so a mutation row can target it individually; a guard that stops at the
# first member of a drifting list is the defect this separation exists to catch.
#
# `doppler run --` is deliberately ABSENT. It binds nothing in the PARENT: under
# trace the parent emits `+ doppler run -- ./child.sh` and nothing else. The
# secret enters the CHILD, which is scored on its own row. Measured: including
# it added 87 files of which 39 had no secret expansion at all.
SIGNAL_EXPANSION = (
    r"\$\{?[A-Za-z_][A-Za-z0-9_]*_(?:TOKEN|KEY|SECRET|PASSWORD|PAT)\}?(?![A-Za-z0-9_])"
)
SIGNAL_CAPTURE = r"[A-Z][A-Z0-9_]*_(?:TOKEN|KEY|SECRET|PASSWORD|PAT)=\"?\$\("
SIGNAL_DOPPLER_GET = r"doppler secrets get"
SIGNAL_GH_AUTH = r"gh auth token"
# `${!name}` expands a variable chosen at RUNTIME, so a static reader cannot
# know which. Under trace it prints the VALUE. `sweep-followthroughs.sh`
# materialises every declared secret of every probe through exactly this form
# (`env_args+=("$name=${!name}")`) and was out of scope until this class existed
# -- the one process concentrating the whole credential surface, declared clean.
SIGNAL_INDIRECT = r"\$\{!"

SECRET_SIGNALS = [
    re.compile(SIGNAL_EXPANSION),
    re.compile(SIGNAL_CAPTURE),
    re.compile(SIGNAL_DOPPLER_GET),
    re.compile(SIGNAL_GH_AUTH),
    re.compile(SIGNAL_INDIRECT),
]

# --- TRACE_TOKENS (Rule B only) ----------------------------------------------
# Rule A quantifies over NO list of trace spellings -- the preamble tests state.
# Rule B cannot: it reads text, so it needs this list and the list can drift.
# Naming it explicitly is the honest statement of the guard's one drifting
# dimension.
TRACE_SHORT = r"^\s*set\s+-[a-z]*x[a-z]*(?:\s|$)"
TRACE_XTRACE_LONG = r"^\s*set\s+-o\s+xtrace\b"
TRACE_SHELLOPTS = r"^\s*(?:export\s+)?SHELLOPTS=.*xtrace"
TRACE_BASH_ENV = r"^\s*(?:export\s+)?BASH_ENV="

TRACE_TOKENS = [
    re.compile(TRACE_SHORT),
    re.compile(TRACE_XTRACE_LONG),
    re.compile(TRACE_SHELLOPTS),
    re.compile(TRACE_BASH_ENV),
]

# The refusal's SHAPE: a `case` on `$-` with an `*x*` arm that exits non-zero.
# Matched on shape, never on a fixed string -- a lint that pins the exact wording
# forces 21 byte-identical copies and rejects any legitimate variation.
CASE_ON_DASH = re.compile(r'^\s*case\s+"?\$-"?\s+in\b')
XTRACE_ARM = re.compile(r"^\s*\*x\*\s*\)")
NONZERO_EXIT = re.compile(r"\bexit\s+([1-9][0-9]*)\b")

# How many executable commands may precede the refusal. `set`/`shopt` are carved
# out explicitly so the rule stays mechanical; everything else counts.
PROLOGUE_MAX_CMDS = 0
PROLOGUE_ALLOWED = re.compile(r"^\s*(?:set|shopt|readonly\s+-\w+)\b")

EXCLUDE_PATTERNS = (
    re.compile(r"\.test\.sh$"),
    re.compile(r"(?:^|/)tests?/"),
    re.compile(r"(?:^|/)fixtures?/"),
    re.compile(r"^scripts/lib/"),
)



def strip_comment(line: str) -> str:
    """Drop a full-line comment. Deliberately conservative: a naive `#` strip
    breaks `${VAR#prefix}` and `${VAR##*/}`, which are common in these scripts,
    so only a line whose first non-space char is `#` is removed."""
    return "" if line.lstrip().startswith("#") else line


# `tests/` is excluded because test files legitimately synthesize tokens
# (cq-test-fixtures-synthesized-only). But `tests/scripts/lib/*-gate.sh` are NOT
# tests -- they are production CI gates that ADR-136/ADR-148 place there by
# convention, and one of them binds a live Cloudflare token whose `2>&1` capture
# `apply-web-platform-infra.yml` posts VERBATIM into a public issue comment.
#
# Carve back in only the EXECUTED units. The discriminator is a positive
# identity the role owns -- a shebang plus the exec bit -- not the absence of
# something. A gate with neither is SOURCED: it runs in the caller's shell under
# the caller's `$-`, so the caller's preamble already governs it and a second
# refusal there would guard nothing new.
#
# Measured 2026-09-04: of 17 files in tests/scripts/lib, exactly one is an
# executed unit (preapply-entrypoint-gate.sh, executed at 2 workflow sites,
# sourced at 0); the other 16 are sourced libraries with neither shebang nor
# exec bit.
PRODUCTION_GATE = re.compile(r"^tests/scripts/lib/[^/]*-gate\.sh$")


def is_executed_unit(rel: str) -> bool:
    """A shebang AND the exec bit -- i.e. something run as its own process."""
    path = REPO_ROOT / rel
    try:
        with path.open("rb") as fh:
            if fh.read(2) != b"#!":
                return False
    except OSError:
        return False
    return os.access(path, os.X_OK)


def excluded(rel: str) -> bool:
    if PRODUCTION_GATE.search(rel) and is_executed_unit(rel):
        return False
    return any(p.search(rel) for p in EXCLUDE_PATTERNS)


def in_scope(body_lines: list[str]) -> bool:
    """True when the file binds or expands a live credential."""
    for raw in body_lines:
        line = strip_comment(raw)
        if not line:
            continue
        if any(sig.search(line) for sig in SECRET_SIGNALS):
            return True
    return False


def find_preamble(lines: list[str]) -> int | None:
    """Index of the `case "$-"` line whose `*x*` arm exits non-zero, or None."""
    for i, raw in enumerate(lines):
        if not CASE_ON_DASH.search(strip_comment(raw)):
            continue
        # Scan the case block for an *x*) arm that exits non-zero.
        in_arm = False
        for j in range(i + 1, min(i + 14, len(lines))):
            body = strip_comment(lines[j])
            if not in_arm and XTRACE_ARM.search(body):
                in_arm = True
            if in_arm and NONZERO_EXIT.search(body):
                return i
            if in_arm and re.search(r"^\s*esac\b", body):
                break
    return None


def check_rule_a(rel: str, lines: list[str], preamble_at: int | None) -> list[str]:
    """The refusal must sit in the prologue."""
    if preamble_at is None:
        # The remedy must name THIS file's credentials. A placeholder leaves the
        # developer red under Rule C after pasting it verbatim -- a guard that
        # tells you how to satisfy it and then rejects that is a dead end.
        creds = sorted(referenced_credentials(lines))
        body_a = "".join(strip_comment(l) for l in lines)
        # `not creds` is the fail-closed arm: if no credential can be NAMED, the
        # only representable guard is the unconditional one. Emitting a
        # placeholder variable name here would hand the developer a remedy that
        # can never guard anything real.
        if unconditional_reason(body_a, lines) or not creds:
            remedy = UNCONDITIONAL_REMEDY
        else:
            cond = "".join(f'${{{c}:+x}}' for c in creds)
            remedy = (
                'case "$-" in\n  *x*)\n'
                f'    if [ -n "{cond}" ]; then\n'
                "      printf '[FATAL] refusing to trace with a live credential set "
                "(see #7797)\\n' >&2\n      exit 78\n    fi\n    ;;\nesac"
            )
        return [
            f"{rel}: binds a live credential but carries no xtrace refusal.\n"
            f"  Add this as the first thing after `set …` (see #7797):\n\n{remedy}\n"
        ]
    cmds_before = 0
    for raw in lines[:preamble_at]:
        line = strip_comment(raw).strip()
        if not line or line.startswith("#!"):
            continue
        if PROLOGUE_ALLOWED.search(line):
            continue
        cmds_before += 1
    if cmds_before > PROLOGUE_MAX_CMDS:
        return [
            f"{rel}:{preamble_at + 1}: xtrace refusal is not in the prologue "
            f"({cmds_before} commands run before it, all of them traced).\n"
            f"  Move it directly below `set …` (keep the refusal you already have).\n"
        ]
    return []


# A file that ACQUIRES a credential at runtime cannot use the conditional escape
# hatch: at preamble time the variable is empty by construction, so the hatch
# opens and the acquisition itself is traced. Measured live --
# `+ SENTRY_AUTH_TOKEN=<value>` with the guard fully "passing". These files must
# refuse unconditionally; the hatch is sound only for an INHERITED credential.
ACQUIRES = re.compile(
    r"doppler secrets get"
    r"|gh auth token"
    r"|[A-Za-z_][A-Za-z0-9_]*_(?:TOKEN|KEY|SECRET|PASSWORD|PAT)=\"?\$\("
)

INDIRECT_RE = re.compile(SIGNAL_INDIRECT)

# The one remedy text for every file whose credential set is not statically
# knowable. Single-sourced so Rule A's "add this" and Rule C's "use this
# instead" can never drift apart.
UNCONDITIONAL_REMEDY = (
    'case "$-" in\n'
    "  *x*) printf '[FATAL] refusing to run under xtrace: this script handles a live "
    "credential and -x would print it (see #7797)\\n' >&2; exit 78 ;;\n"
    "esac"
)


def unconditional_reason(body: str, lines: list[str]) -> tuple[str, str] | None:
    """Why this file cannot use the conditional escape hatch, or None.

    Two distinct causes, one consequence -- the guard cannot name the credential
    it must cover, so any `${VAR:+x}` hatch is open at guard time and the
    credential is traced anyway:

      ACQUIRES  the credential is FETCHED at runtime, so the variable is empty
                at the preamble by construction.
      INDIRECT  the credential is NAMED at runtime (`${!name}`), so no literal
                name exists for the guard to test.

    Measured for the INDIRECT case in `sweep-followthroughs.sh`: the forwarded
    secrets do NOT leak at the array append (bash prints `arr+=(...)`
    unexpanded) but DO leak at the invocation --
    `++ env -i ... SENTRY_AUTH_TOKEN=<value> <script>` -- putting every secret
    the sweeper forwards onto a single trace line.
    """
    if ACQUIRES.search(body):
        return (
            "ACQUIRES a credential at runtime",
            "The variable is empty at this line by construction, the hatch opens, "
            "and the acquisition is then traced.",
        )
    if INDIRECT_RE.search(body) and not referenced_credentials(lines):
        return (
            "names its credentials indirectly (`${!name}`)",
            "The credential set is determined at runtime, so no literal name exists "
            "for the hatch to test and it is open by construction.",
        )
    return None

CREDENTIAL_NAME = re.compile(r"\b([A-Z][A-Z0-9_]*_(?:TOKEN|KEY|SECRET|PASSWORD|PAT))\b")
GUARDED_NAME = re.compile(r"\$\{([A-Za-z_][A-Za-z0-9_]*):?\+[^}]*\}")
# Any expansion of a credential inside the arm that is NOT the `:+`/`+` form
# puts the VALUE on the command line, which xtrace then prints -- so the refusal
# leaks the thing it is refusing over. This is the PR's own headline defect
# (`[ -n "${VAR:-}" ]` traced as `+ '[' -n <TOKEN> ']'`), and without this check
# a one-character revert in any of 22 production copies re-ships it, lint-green.
EXPANDING_IN_ARM = re.compile(
    r"\$\{([A-Z][A-Z0-9_]*_(?:TOKEN|KEY|SECRET|PASSWORD|PAT))(?::?-[^}]*)?\}"
    r"|\$([A-Z][A-Z0-9_]*_(?:TOKEN|KEY|SECRET|PASSWORD|PAT))\b"
)


def arm_window(lines: list[str], preamble_at: int) -> str:
    """The refusal's own text, bounded at `esac`.

    A fixed-size slice runs past the block into the script body, where ordinary
    credential USE then reads as a leaking guard -- the window-scoping defect
    this repo has recorded twice. The window must end where the construct does.
    """
    out = []
    for raw in lines[preamble_at : preamble_at + 20]:
        out.append(raw)
        if re.match(r"^\s*esac\b", strip_comment(raw)):
            break
    return "".join(out)


def referenced_credentials(lines: list[str]) -> set[str]:
    """Every credential-shaped variable name the file references, comments
    stripped so prose cannot inflate the set."""
    out: set[str] = set()
    for raw in lines:
        line = strip_comment(raw)
        if line:
            out.update(CREDENTIAL_NAME.findall(line))
    return out


def guarded_credentials(lines: list[str], preamble_at: int | None) -> set[str]:
    """Names the refusal actually tests, via the `${NAME:+x}` form."""
    if preamble_at is None:
        return set()
    return set(GUARDED_NAME.findall(arm_window(lines, preamble_at)))


def check_rule_c(rel: str, lines: list[str], preamble_at: int | None) -> list[str]:
    """The refusal must cover EVERY credential the file references.

    WHY THIS RULE EXISTS. Rules A and B verify the refusal's PLACEMENT and that
    nothing re-enables tracing below it. Neither checks that it guards the right
    variable -- so a script can carry a perfectly-placed refusal naming one
    credential while binding a different one, and leak it. That is not
    hypothetical: six of the 21 scripts remediated in this PR shipped with
    exactly that mismatch, lint-green, and one of them printed a Better Stack
    password in cleartext under `bash -x` (`+ [[ -z <password> ]]`). A guard
    whose assembly is narrower than the property it names is the defect this
    whole lint exists to prevent, so it needed a rule of its own.
    """
    if preamble_at is None:
        return []  # Rule A already reported the absence.
    referenced = referenced_credentials(lines)
    guarded = guarded_credentials(lines, preamble_at)
    out: list[str] = []
    body = "".join(strip_comment(l) for l in lines)
    window = arm_window(lines, preamble_at)

    # BEFORE the `not referenced` return: a file that names its credentials
    # indirectly has an EMPTY referenced set, so an early return here would make
    # this rule structurally unable to see the very class it exists to catch.
    reason = unconditional_reason(body, lines)
    if reason and ":+" in window:
        label, why = reason
        indented = "\n".join("    " + l for l in UNCONDITIONAL_REMEDY.splitlines())
        out.append(
            f"{rel}:{preamble_at + 1}: this script {label}, so a conditional refusal "
            f"cannot protect it.\n"
            f"  {why}\n"
            f"  Refuse unconditionally instead:\n\n{indented}\n"
        )
    if not referenced:
        return out

    # Predicate form: a guard that expands the value is worse than none,
    # because it leaks WHILE refusing and reads as protection.
    expanding = sorted(
        {m[0] or m[1] for m in EXPANDING_IN_ARM.findall(window)}
    )
    if expanding:
        out.append(
            f"{rel}:{preamble_at + 1}: the xtrace refusal EXPANDS the credential it "
            f"guards ({', '.join(expanding)}).\n"
            f"  Under `set -x` that prints the value while the script refuses to run.\n"
            f"  Use the `:+x` form, which tests non-emptiness without expanding:\n"
            f'    if [ -n "${{{expanding[0]}:+x}}" ]; then\n'
        )

    # An UNCONDITIONAL refusal (no `${VAR:+x}` test in the arm) covers every
    # credential by construction -- there is nothing for it to be narrower than.
    # Without this, the strongest possible guard reports as the weakest.
    if ":+" not in window:
        return out

    missing = sorted(referenced - guarded)
    if not missing:
        return out
    every = "".join(f'${{{n}:+x}}' for n in sorted(referenced))
    out.append(
        f"{rel}:{preamble_at + 1}: the xtrace refusal does not cover every credential "
        f"this file references. Unguarded: {', '.join(missing)}.\n"
        f"  Tracing is permitted whenever the guarded names happen to be empty, so an\n"
        f"  unguarded credential is still printed after expansion. Test them all:\n\n"
        f'    if [ -n "{every}" ]; then\n'
    )
    return out


def check_rule_b(rel: str, lines: list[str], preamble_at: int | None) -> list[str]:
    """No trace-enabling token below the refusal. The preamble is a
    point-in-time assertion; this is what makes it hold for the whole file."""
    if preamble_at is None:
        return []
    out = []
    for i in range(preamble_at, len(lines)):
        line = strip_comment(lines[i])
        if not line:
            continue
        for tok in TRACE_TOKENS:
            if tok.search(line):
                out.append(
                    f"{rel}:{i + 1}: enables shell tracing BELOW the xtrace refusal, "
                    f"which the refusal cannot see: {line.strip()[:80]}\n"
                    f"  Remove it, or wrap only the credential-free region.\n"
                )
                break
    return out


# --- Rule D: credential-forwarding destination and transport confinement ------
# (#7873) A URL pin is NOT on its own enough to pin a destination. `curl` reads
# `ALL_PROXY`/`HTTPS_PROXY` from the environment and `~/.curlrc` from disk BEFORE
# it honours the pinned host -- reproduced against a local listener while the pin
# stayed fully intact. So a credentialed request whose destination is "pinned" can
# still be redirected by anything that can set an env var or drop a dotfile.
#
# The property, in one sentence: EVERY credentialed `curl` carries `--disable`
# (skip ~/.curlrc) as its LITERAL FIRST argument and `--noproxy '*'`; and where its
# destination comes from an env-settable variable, an exact-equality pin.
#
# `--disable` must be first because curl only honours it in that position -- it is
# not a normal flag, it aborts config-file parsing, and parsing has already
# happened by the time a later flag is read. Asserting mere PRESENCE would pass a
# script where it is last and does nothing.
#
# Model: scripts/supabase-logs-query.sh, the repo's one complete instance.

# A credential reaches curl three ways, and only the first is visible in argv.
CURL_CRED_FLAGS = re.compile(
    r"(?:^|\s)(?:-u\s|--user\s|--netrc\b|--netrc-file\b|--oauth2-bearer\b"
    r"|--proxy-user\s|-E\s|--cert\s|--config\s|-K\s)"
)
# `--config <file>` is a credential channel and the one this repo's most careful
# call site uses: zot-inventory.sh writes `header = "Authorization: Bearer …"`
# into a 0600 file so the token never reaches argv. A classifier blind to it
# scores that site as credential-free -- and it is the site #7873 is about.
#
# It is NOT redundant with --disable. --disable suppresses ~/.curlrc (attacker-
# controlled); --config names a file WE wrote. Both can be true at once.
# `--header @-` / `-H @-` reads the header from STDIN, so the credential is in the
# PIPELINE feeding curl, not in its own argv. That is the shape this repo prefers
# (it keeps the token out of argv), so a classifier blind to it would miss the
# most careful call sites and flag only the careless ones.
CURL_STDIN_HEADER = re.compile(r"(?:^|\s)(?:--header|-H)\s+@-")
CURL_AUTH_HEADER = re.compile(r"(?:Authorization|X-API-Key|Private-Token)\s*:", re.I)

CURL_INVOKE = re.compile(r"(?:^|[|;&(]|\s)curl(?:\s|$)")
CURL_DISABLE_FIRST = re.compile(r"\bcurl\s+--disable(?:\s|$)")
CURL_NOPROXY = re.compile(r"--noproxy\s+'?\*'?")

# An env-settable destination: `X="${X:-default}"` or `X="${SOME_ENV:-default}"`.
ENV_SETTABLE = re.compile(
    r"^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)=\"?\$\{([A-Za-z_][A-Za-z0-9_]*):-"
)
# An exact-equality pin on that variable, in either test syntax.
def _pin_re(var: str) -> re.Pattern:
    v = re.escape(var)
    return re.compile(
        r"\[\[?[^]]*\$\{?" + v + r"\}?\"?\s*(?:==|!=|=)\s"
        r"|case\s+\"?\$\{?" + v + r"\}?\"?\s+in"
    )


def _curl_commands(lines: list[str]) -> list[tuple[int, str]]:
    """Assemble each curl invocation into ONE logical string.

    Two joins are needed and both are load-bearing. Backslash continuations,
    because these calls are always wrapped; and the pipeline ABOVE the call, so a
    `printf 'Authorization: Bearer %s' | curl --header @-` is classified on the
    credential it is actually fed. Reading only the curl line would score that
    call as credential-free -- the exact opposite of the truth.
    """
    out: list[tuple[int, str]] = []
    for i, raw in enumerate(lines):
        line = strip_comment(raw)
        if not line or not CURL_INVOKE.search(line):
            continue
        # Walk back over the pipeline feeding this curl (bounded: 4 lines).
        start = i
        for j in range(i - 1, max(-1, i - 5), -1):
            prev = strip_comment(lines[j]).rstrip()
            if prev.endswith("|") or prev.endswith("\\"):
                start = j
            else:
                break
        # Walk forward over backslash continuations.
        end = i
        while end < len(lines) - 1 and strip_comment(lines[end]).rstrip().endswith("\\"):
            end += 1
        cmd = " ".join(strip_comment(x).strip().rstrip("\\").strip() for x in lines[start:end + 1])
        cmd = _inline_arrays(cmd, lines)
        cmd = _inline_config_file(cmd, lines)
        out.append((i, cmd))
    return out


# The surrounding quotes are consumed too: substituting inside them leaves
# `curl "--disable ...`, and the position check would miss a compliant call site.
ARRAY_EXPANSION = re.compile(r"\"?\$\{([A-Za-z_][A-Za-z0-9_]*)\[@\]\}\"?")
CONFIG_FLAG = re.compile(r"(?:--config|-K)\s+\"?\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?\"?")


def _inline_config_file(cmd: str, lines: list[str]) -> str:
    """Splice in the block that WRITES a `--config` file.

    Same indirection as the array, one level further out: zot-inventory.sh puts
    both the credential AND the destination (`url = "$INGEST_URL"`) into a config
    file, so the curl line names neither. Without this the destination-pin clause
    is structurally unable to see the very variable #7873 is about.
    """
    for name in set(CONFIG_FLAG.findall(cmd)):
        redirect = re.compile(r">\s*\"?\$\{?" + re.escape(name) + r"\}?\"?\s*$")
        for i, raw in enumerate(lines):
            if not redirect.search(strip_comment(raw).rstrip()):
                continue
            # Walk back to the opening `{` of the group being redirected.
            for j in range(i, max(-1, i - 25), -1):
                seg = strip_comment(lines[j])
                cmd += " " + seg.strip()
                if seg.strip().startswith("{"):
                    break
    return cmd


def _array_body(name: str, lines: list[str]) -> tuple[str, str]:
    """-> (body of the `=(` declaration, bodies of any `+=(` appends).

    Split because POSITION is part of Rule D's property: only the initial
    declaration can supply curl's FIRST argument, so a later `+=` append must not
    be able to satisfy the --disable-is-first check.
    """
    decl = re.compile(
        r"^\s*(?:local\s+-a\s+|declare\s+-a\s+|readonly\s+-a\s+)?"
        + re.escape(name) + r"=\("
    )
    append = re.compile(r"^\s*" + re.escape(name) + r"\+=\(")
    first, extra = "", ""
    for i, raw in enumerate(lines):
        seg0 = strip_comment(raw)
        is_decl, is_app = bool(decl.search(seg0)), bool(append.search(seg0))
        if not (is_decl or is_app):
            continue
        depth, chunk = 0, []
        for j in range(i, len(lines)):
            seg = strip_comment(lines[j])
            depth += seg.count("(") - seg.count(")")
            chunk.append(seg.strip())
            if depth <= 0:
                break
        body = " ".join(chunk)
        body = body[body.find("(") + 1:]
        if body.endswith(")"):
            body = body[:-1]
        if is_decl and not first:
            first = body
        else:
            extra += " " + body
    return first, extra


def _inline_arrays(cmd: str, lines: list[str]) -> str:
    """Substitute each expanded array's body AT ITS POSITION in the invocation.

    Appending it instead is wrong in a way that matters: the flags of
    `curl "${args[@]}" "$url"` really ARE first at runtime, so a rule that reads
    them at the end reports a false positive on a compliant call site -- which is
    how a guard teaches its reader to baseline files that are already correct.
    Measured: zot-inventory.sh's http_get was flagged that way until this became
    positional.
    """
    def repl(m):
        first, extra = _array_body(m.group(1), lines)
        return (first + " " + extra).strip() if (first or extra) else m.group(0)

    return ARRAY_EXPANSION.sub(repl, cmd)



def check_rule_d(rel: str, lines: list[str], preamble_at: int | None) -> list[str]:
    """Transport confinement + destination pin on every credentialed curl."""
    del preamble_at  # Rule D is independent of the xtrace refusal.
    body = "\n".join(strip_comment(x) for x in lines)
    out: list[str] = []
    for lineno, cmd in _curl_commands(lines):
        credentialed = bool(
            CURL_CRED_FLAGS.search(cmd)
            or CURL_STDIN_HEADER.search(cmd)
            or (CURL_AUTH_HEADER.search(cmd) and any(s.search(cmd) for s in SECRET_SIGNALS))
            or any(s.search(cmd) for s in SECRET_SIGNALS)
        )
        if not credentialed:
            continue
        if not CURL_DISABLE_FIRST.search(cmd):
            out.append(
                f"{rel}:{lineno + 1}: credentialed curl without `--disable` as its FIRST "
                f"argument, so ~/.curlrc can redirect it before any pin is read.\n"
                f"  Add `--disable` immediately after `curl` (position is load-bearing).\n"
            )
        if not CURL_NOPROXY.search(cmd):
            out.append(
                f"{rel}:{lineno + 1}: credentialed curl without `--noproxy '*'`, so "
                f"ALL_PROXY/HTTPS_PROXY can redirect it with the destination pin intact.\n"
                f"  Add `--noproxy '*'`.\n"
            )
        # Destination pin: only when the URL comes from an env-settable variable.
        for var in set(re.findall(r"\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?", cmd)):
            if not re.search(
                r"^\s*(?:export\s+)?" + re.escape(var) + r"=\"?\$\{" + re.escape(var)
                + r":-|^\s*(?:export\s+)?" + re.escape(var) + r"=\"?\$\{[A-Za-z_][A-Za-z0-9_]*:-",
                body, re.M,
            ):
                continue
            if not re.search(r"(?:URL|URI|ENDPOINT|HOST)\b", var):
                continue
            if not _pin_re(var).search(body):
                out.append(
                    f"{rel}:{lineno + 1}: credentialed curl sends to ${var}, which is "
                    f"env-settable and never compared against a literal.\n"
                    f"  Pin it: refuse unless ${var} equals the expected destination.\n"
                )
    return out


def check_file(path: Path) -> tuple[int, list[str]]:
    """-> (status, violations). status 2 means cannot-evaluate."""
    try:
        rel = str(path.relative_to(REPO_ROOT))
    except ValueError:
        rel = str(path)
    if excluded(rel):
        return 0, []
    try:
        text = path.read_text(encoding="utf-8")
    except (UnicodeDecodeError, OSError):
        print(f"{rel}: cannot evaluate (unreadable or not UTF-8)", file=sys.stderr)
        return 2, []  # unparseable
    lines = text.splitlines()
    if not in_scope(lines):
        return 0, []
    preamble_at = find_preamble(lines)
    abc = check_rule_a(rel, lines, preamble_at)
    abc += check_rule_b(rel, lines, preamble_at)
    abc += check_rule_c(rel, lines, preamble_at)
    d = check_rule_d(rel, lines, preamble_at)
    # Tagged by rule so main() can apply the correct baseline to each. An
    # untagged list would force one baseline over both populations, which is the
    # vacuity Rule D's own baseline exists to avoid.
    violations = [("abc", v) for v in abc] + [("d", v) for v in d]
    return (1 if violations else 0), violations


def git_out(args: list[str]) -> list[str]:
    try:
        res = subprocess.run(
            ["git", "-C", str(REPO_ROOT), *args],
            capture_output=True, text=True, check=True,
        )
    except (subprocess.CalledProcessError, OSError) as exc:
        print(f"git error: {exc}", file=sys.stderr)
        sys.exit(2)
    return [ln for ln in res.stdout.splitlines() if ln.strip()]


def all_shell_files() -> list[Path]:
    # `git ls-files` lists the INDEX, which still names a file deleted from the
    # working tree. Without this filter such a path reaches check_file, which
    # fail-closes at rc=2 and reds the required `test` shard for an ordinary
    # deletion. Fail-closed is right for an UNREADABLE file and wrong for an
    # ABSENT one -- they are different conditions.
    return [p for p in (REPO_ROOT / q for q in git_out(["ls-files", "*.sh"])) if p.exists()]


def changed_shell_files(base: str) -> list[Path]:
    merge_base = git_out(["merge-base", "HEAD", base])
    if not merge_base:
        print("git error: no merge base", file=sys.stderr)
        sys.exit(2)
    changed = git_out(["diff", "--name-only", f"{merge_base[0]}...HEAD"])
    untracked = git_out(["ls-files", "--others", "--exclude-standard", "*.sh"])
    names = {c for c in changed if c.endswith(".sh")} | set(untracked)
    return [REPO_ROOT / n for n in sorted(names) if (REPO_ROOT / n).exists()]


def targets_from_args(args: argparse.Namespace) -> list[Path]:
    if args.paths:
        return [Path(p).resolve() for p in args.paths]
    if args.changed:
        return changed_shell_files(args.base)
    return all_shell_files()


def _load_list(path: Path) -> set[str]:
    if not path.exists():
        return set()
    return {
        ln.strip()
        for ln in path.read_text(encoding="utf-8").splitlines()
        if ln.strip() and not ln.startswith("#")
    }


def load_baseline() -> set[str]:
    return _load_list(BASELINE_FILE)


def load_baseline_d() -> set[str]:
    return _load_list(BASELINE_D_FILE)


def load_highwater_d() -> int | None:
    """The ratchet's current ceiling, or None when unreadable.

    None is NOT zero. An unreadable/absent highwater must not read as a ceiling
    of zero (which every population exceeds, reddening CI for the wrong reason)
    nor as infinity (which disarms the ratchet silently). Callers branch on it.
    """
    if not HIGHWATER_D_FILE.exists():
        return None
    for ln in HIGHWATER_D_FILE.read_text(encoding="utf-8").splitlines():
        ln = ln.strip()
        if not ln or ln.startswith("#"):
            continue
        if re.fullmatch(r"[0-9]+", ln):
            return int(ln)
        return None
    return None


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("paths", nargs="*")
    ap.add_argument("--changed", action="store_true")
    ap.add_argument("--base", default="origin/main")
    ap.add_argument("--census", action="store_true")
    ap.add_argument("--write-baseline", action="store_true")
    ap.add_argument("--write-baseline-d", action="store_true",
                    help="rewrite Rule D's baseline AND its highwater from a full-tree scan")
    ap.add_argument("--check-highwater", action="store_true",
                    help="fail when Rule D's offender count exceeds the recorded highwater")
    args = ap.parse_args()

    targets = targets_from_args(args)
    # The baseline grandfathers a deferred population for the REPO-WIDE sweep only.
    # In --changed / explicit-path mode it is bypassed, which is what makes the
    # header's drawdown trigger true rather than aspirational -- it was advertised
    # and never implemented.
    scoped = args.changed or args.paths
    baseline = set() if scoped else load_baseline()
    baseline_d = set() if scoped else load_baseline_d()

    scanned = 0
    offenders: list[str] = []
    offenders_d: list[str] = []
    all_violations: list[str] = []
    cannot_evaluate = False

    for path in targets:
        scanned += 1
        status, violations = check_file(path)
        if status == 2:
            cannot_evaluate = True
            continue
        if violations:
            try:
                rel = str(path.relative_to(REPO_ROOT))
            except ValueError:
                rel = str(path)
            if any(rule == "abc" for rule, _ in violations):
                offenders.append(rel)
            if any(rule == "d" for rule, _ in violations):
                offenders_d.append(rel)
            for rule, v in violations:
                supp = baseline if rule == "abc" else baseline_d
                if rel not in supp:
                    all_violations.append(v)

    if args.census:
        print(f"scanned={scanned} offenders={len(offenders)} offenders_d={len(offenders_d)}")
        for o in sorted(offenders):
            print(o)
        print("--- rule D ---")
        for o in sorted(offenders_d):
            print(o)
        return 0

    if args.write_baseline_d:
        if scoped:
            print(
                "--write-baseline-d rewrites the ENTIRE Rule D baseline and must scan "
                "the whole tree. Re-run it without --changed and without explicit paths.",
                file=sys.stderr,
            )
            return 2
        BASELINE_D_FILE.write_text(
            "# Rule D (#7873): credentialed curl without --disable first / --noproxy '*',\n"
            "# or sending to an env-settable destination that is never pinned.\n"
            "# SEPARATE from the A/B/C baseline ON PURPOSE: that one suppresses by FILE\n"
            "# across all rules, and every Rule D target site is already in it.\n"
            "# DRAWDOWN: --changed bypasses this file, so touching a listed script must\n"
            "# remediate it. The .highwater sibling ratchets the count DOWN only.\n"
            + "".join(f"{o}\n" for o in sorted(offenders_d)),
            encoding="utf-8",
        )
        HIGHWATER_D_FILE.write_text(
            "# Rule D offender count. Ratchets DOWN only (see --check-highwater).\n"
            "# Regenerate: python3 scripts/lint-shell-trace-credential-refusal.py --write-baseline-d\n"
            f"{len(offenders_d)}\n",
            encoding="utf-8",
        )
        print(f"rule D baseline written: {len(offenders_d)} entries; highwater={len(offenders_d)}")
        return 0

    if args.check_highwater:
        # The ratchet reads the FULL population, so it is meaningless on a scoped
        # run -- a --changed scan sees a handful of files and would "prove" a
        # drawdown that never happened.
        if scoped:
            print(
                "--check-highwater measures the whole population and cannot run with "
                "--changed or explicit paths.",
                file=sys.stderr,
            )
            return 2
        hw = load_highwater_d()
        if hw is None:
            print(
                f"lint-shell-trace-credential-refusal: Rule D highwater at "
                f"{HIGHWATER_D_FILE.name} is missing or not a bare integer -- refusing to "
                f"report a ratchet result it cannot read (observed {len(offenders_d)} offenders)",
                file=sys.stderr,
            )
            return 2
        if len(offenders_d) > hw:
            print(
                f"lint-shell-trace-credential-refusal: Rule D offenders GREW "
                f"{hw} -> {len(offenders_d)}. The ratchet is one-way: fix the new site, or "
                f"justify it and re-run --write-baseline-d.",
                file=sys.stderr,
            )
            for o in sorted(offenders_d):
                print(f"  {o}", file=sys.stderr)
            return 1
        if len(offenders_d) < hw:
            print(
                f"rule D drawdown: {hw} -> {len(offenders_d)}. "
                f"Re-run --write-baseline-d to lower the ratchet."
            )
        else:
            print(f"rule D highwater held: {len(offenders_d)}/{hw}")
        return 0

    if args.write_baseline:
        # The baseline is the WHOLE deferred population. Writing it from a
        # --changed or explicit-path run would silently truncate it to whatever
        # that run happened to scan, discarding the rest and reporting success.
        if args.changed or args.paths:
            print(
                "--write-baseline rewrites the ENTIRE baseline and must scan the "
                "whole tree. Re-run it without --changed and without explicit paths.",
                file=sys.stderr,
            )
            return 2
        BASELINE_FILE.write_text(
            "# Files that bind a live credential without the xtrace refusal (#7797).\n"
            "# ENUMERATED, not a count: a bare integer cannot say WHICH files, so\n"
            "# nobody can pick up the next ten. DRAWDOWN TRIGGER: any PR that edits a\n"
            "# listed script must remediate it -- enforced by --changed.\n"
            + "".join(f"{o}\n" for o in sorted(offenders)),
            encoding="utf-8",
        )
        print(f"baseline written: {len(offenders)} entries")
        return 0

    # A scan of zero files is the vacuity this lint exists to prevent; reporting
    # OK would be the guard certifying its own absence.
    if scanned == 0 and not args.changed:
        print(
            "lint-shell-trace-credential-refusal: scanned 0 files -- refusing to report "
            "a clean result for a scan that inspected nothing",
            file=sys.stderr,
        )
        return 2

    if all_violations:
        for v in all_violations:
            print(v, file=sys.stderr)
        print(
            f"lint-shell-trace-credential-refusal: {len(all_violations)} violation(s) "
            f"in {scanned} scanned file(s)",
            file=sys.stderr,
        )
        # Report violations BEFORE the cannot-evaluate exit: one unreadable byte
        # anywhere previously discarded every real finding in the run.
        return 2 if cannot_evaluate else 1

    if cannot_evaluate:
        return 2

    print(
        f"OK: {scanned} scanned file(s), {len(offenders)} baselined (A/B/C), "
        f"{len(offenders_d)} baselined (D)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
