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

RULES A and B, because the preamble is a point-in-time assertion and not an
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
  Rules C and D are documented at their definitions below. Rule E (#9597) is the
  argv-credential ratchet: no curl command carries a credential header (the six names in
  `E_CREDENTIAL_HEADERS`; any `Authorization:` scheme) or a basic-auth pair (`-u`/`--user`) in its
  own argument list, in tracked
  shell, workflow/composite-action YAML or cloud-init YAML (see the Rule E block for the
  members, safe forms, scope and blind spots), with its own `path<TAB>site-count` baseline
  compared by equality in the repo-wide run.

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
import functools
import os
import re
import shlex
import subprocess
import sys
from collections import namedtuple
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
#
# `${!arr[@]}` AND `${!arr[*]}` ARE EXCLUDED, and they are a different construct
# entirely. `${!name}` yields a VALUE chosen at runtime; `${!arr[@]}` yields the
# array's KEYS. Be precise about why that is safe, because the obvious reason is
# wrong: an ASSOCIATIVE array's key is an arbitrary string, so a key CAN be a
# secret and `echo "${!m[@]}"` will print it under trace (measured). What makes
# the construct safe is that it does not BIND a credential -- whatever line put
# the secret into that key is itself a binding line, and catching binding lines
# is what SECRET_SIGNALS is for. In the `for` form this tree actually uses, bash
# traces the word list UNEXPANDED (`+ for k in "${!seen[@]}"`), so even that
# case emits nothing. And it is
# the only way bash can iterate an associative array, so every script that uses
# one was in scope. The bare `\$\{!` spelling flagged a since-retired script
# (#7935) for `for rel in "${!merged[@]}"`, a loop over knowledge-base row paths,
# in a script that binds no credential at all. Both ways out of that -- an xtrace
# refusal announcing a credential the script does not have, or a baseline entry
# calling it a known violation -- write a false statement into the tree, which is
# the exact failure `_inline_arrays` and `_adjudicated` below were each written
# to avoid: a false positive teaches its reader to baseline files that are
# already correct. `${!prefix@}` / `${!prefix*}` (name listing) stay IN scope --
# conservative, and no script here uses them.
SIGNAL_INDIRECT = r"\$\{!(?![A-Za-z_][A-Za-z0-9_]*\[[@*]\]\})"

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


def excluded_for_rule_d(rel: str) -> bool:
    """Rule D's exclusions are its OWN, because the inherited reasons are xtrace-only.

    `^scripts/lib/` is excluded above because a sourced `exit` terminates the
    SOURCING parent -- a fact about the xtrace REFUSAL, which Rule D does not use:
    Rule D requires argv flags, and a `curl -u …` in a sourced library forwards a
    credential exactly as a top-level script does. Inheriting that exclusion made
    every credentialed curl under scripts/lib/ unconditionally invisible.

    `tests/`, `fixtures/` and `*.test.sh` stay excluded for Rule D too, and for a
    reason that DOES transfer: those files deliberately synthesize violations
    (this rule's own must-fail fixtures live there), so scanning them would make
    the guard fail on its own test data.
    """
    if PRODUCTION_GATE.search(rel) and is_executed_unit(rel):
        return False
    return any(
        p.search(rel) for p in EXCLUDE_PATTERNS
        if p.pattern != r"^scripts/lib/"
    )


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
# The alternate must be NON-EMPTY: `${VAR:+}` expands to "" whether or not VAR is set,
# so `[ -n "${VAR:+}" ]` can never be true -- it is `[ -n "" ]` wearing the variable's
# name. EMPTY_ALTERNATE reports that residue; GUARDED_NAME does not count it as a guard.
GUARDED_NAME = re.compile(r"\$\{([A-Za-z_][A-Za-z0-9_]*):?\+[^}]+\}")
EMPTY_ALTERNATE = re.compile(r"\$\{([A-Za-z_][A-Za-z0-9_]*):?\+\}")
# `-z "${VAR:+x}"` is the guard INVERTED: it refuses only while the credential is EMPTY
# and traces freely once it is set -- the exact opposite of the property, and a
# one-character edit away from the correct form.
INVERTED_GUARD = re.compile(r"(?:-z|!\s+-n)\s+\"?\$\{([A-Za-z_][A-Za-z0-9_]*):?\+[^}]*\}\"?")
# Any expansion of a credential inside the arm that is NOT the `:+`/`+` form
# puts the VALUE on the command line, which xtrace then prints -- so the refusal
# leaks the thing it is refusing over. This is the PR's own headline defect
# (`[ -n "${VAR:-}" ]` traced as `+ '[' -n <TOKEN> ']'`), and without this check
# a one-character revert in any of 22 production copies re-ships it, lint-green.
# Guard 2 (#7946): an empty-string non-emptiness test in the refusal arm -- the residue of
# deleting a single-credential file's only `${VAR:+x}` limb during a rename. `[ -n "" ]`
# can never be true, so the refusal reads as protection and never fires. Either test
# syntax (`[`, `[[`, `test`), either quote style, `-n ""`, `! -z ""` or the bare `[ "" ]`.
# Checked BEFORE the `not referenced` return (a file whose only literal credential name was
# deleted in the same edit has an empty referenced set) and BEFORE the `":+" not in window`
# early return, which would otherwise classify this as an unconditional refusal.
EMPTY_PREDICATE = re.compile(
    r"(?:\[\[?|\btest)\s+(?:-n\s+|!\s+-z\s+)?(?:\"\"|'')(?:\s+\]\]?|\s*(?:$|;|&&|\|\|))",
    re.M,
)
EXPANDING_IN_ARM = re.compile(
    r"\$\{([A-Z][A-Z0-9_]*_(?:TOKEN|KEY|SECRET|PASSWORD|PAT))(?::?-[^}]*)?\}"
    r"|\$([A-Z][A-Z0-9_]*_(?:TOKEN|KEY|SECRET|PASSWORD|PAT))\b"
)


def arm_window(lines: list[str], preamble_at: int) -> str:
    """The refusal's own text, bounded at `esac`.

    A fixed-size slice runs past the block into the script body, where ordinary
    credential USE then reads as a leaking guard -- the window-scoping defect
    this repo has recorded twice. The window must end where the construct does.

    Comment lines are dropped: a `${VAR:+x}` that survives only in a comment (a
    commented-out limb, a note quoting the canonical form) is not a guard, and
    counting it as one is how a two-credential file passes with one limb deleted.
    """
    out = []
    for raw in lines[preamble_at : preamble_at + 20]:
        line = strip_comment(raw)
        out.append(line)
        if re.match(r"^\s*esac\b", line):
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
    # Guard 2 (#7946): predicates that can NEVER fire or fire INVERTED. Reported before
    # the `not referenced` return (the deleted-name case has an empty referenced set) and
    # before the `":+" not in window` return (which would read them as unconditional).
    if EMPTY_PREDICATE.search(window):
        out.append(
            f"{rel}:{preamble_at + 1}: the xtrace refusal tests an empty string and can "
            f"never fire -- `[ -n \"\" ]` is the residue of deleting the only `${{VAR:+x}}` "
            f"limb.\n"
            f"  Restore the `${{VAR:+x}}` limb naming the credential this file consumes, or\n"
            f"  refuse unconditionally (drop the `if` and exit 78 in the arm).\n"
        )
        return out
    empty_alt = sorted(set(EMPTY_ALTERNATE.findall(window)))
    if empty_alt:
        out.append(
            f"{rel}:{preamble_at + 1}: the xtrace refusal tests `${{{empty_alt[0]}:+}}`, whose "
            f"alternate is EMPTY -- it expands to \"\" whether or not the credential is set, so "
            f"the refusal can never fire.\n"
            f"  Give the alternate a value: `[ -n \"${{{empty_alt[0]}:+x}}\" ]`.\n"
        )
        return out
    # A `-z` under an OUTER negation is the correct guard spelled differently:
    # `! [ -z "${V:+x}" ]` and `[ -z "${V:+x}" ] || exit 78` both refuse when V is
    # SET. Only an un-negated `-z` whose branch is the refusal is inverted.
    inverted = sorted({
        m.group(1) for m in INVERTED_GUARD.finditer(window)
        if not re.search(r"!\s*(\[\[?|test)\s*-z", window[max(0, m.start() - 12):m.end()])
        and not re.search(r"\]\]?\s*\|\|", window[m.end():m.end() + 12])
    })
    if inverted:
        out.append(
            f"{rel}:{preamble_at + 1}: the xtrace refusal is INVERTED -- `-z \"${{{inverted[0]}:+x}}\"` "
            f"refuses only while the credential is EMPTY and traces freely once it is set.\n"
            f"  Test non-emptiness: `[ -n \"${{{inverted[0]}:+x}}\" ]`.\n"
        )
        return out
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
    r"|--proxy-user\s|-E\s|--cert\s|--config\s|-K\s"
    # A client KEY is a credential even when --cert names only the public half,
    # and a cookie jar is a session credential in a file.
    r"|--key\s|--pass\s|-b\s|--cookie\s|--cookie-jar\s)"
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

# An absolute or relative PATH to curl is still curl. The previous class
# `(?:^|[|;&(]|\s)` excluded `/`, so `/usr/bin/curl` -- live twice in
# apps/web-platform/infra/inngest-bootstrap.sh -- was not recognised as a curl
# invocation at all, and the file scored entirely out of scope.
CURL_INVOKE = re.compile(r"(?:^|[|;&(`$]|\s)(?:[\w./-]*/)?curl(?:\s|$)")
# One shell variable reference inside a single token. Shared by the destination
# derivation and the per-call-site variable sweep so the two cannot drift.
# curl's config-file destination key: `url = \"...\"`. Anchored on the KEY, so a
# `printf 'url = \"%s\"' \"$X\"` hands its next token over as the destination.
# NOTE the class: `[:space:]` is a POSIX class, valid only inside a bracket
# expression in a POSIX ERE and NOT a Python one -- written that way this
# silently required a literal `]` before `url`, so the key matched nothing
# and the --config channel went dark. Use `\s`.
# An assignment whose ENTIRE right-hand side is one expansion: `VAR="$OTHER"`,
# `VAR=$OTHER`, `VAR="${OTHER}"`. Named so the mutation battery has a clean
# target -- this limb is otherwise a fragment spliced into a built pattern.
BARE_ASSIGN_RHS = r"=\"?\$\{?[A-Za-z_][A-Za-z0-9_]*\}?\"?\s*$"
CONFIG_URL_KEY = re.compile(r"(?:^|['\"\s])url\s*=", re.I)
VAR_IN_TOKEN = re.compile(r"\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?")
CURL_DISABLE_FIRST = re.compile(r"\bcurl\s+--disable(?:\s|$)")
CURL_NOPROXY = re.compile(r"--noproxy\s+'?\*'?")

def _pin_re(var: str) -> re.Pattern:
    """A pin ADJUDICATES the destination against a literal.

    The first version accepted `case "$VAR" in` with the arms unexamined, so a
    vacuous `case "$X" in *) : ;; esac` satisfied it -- and accepted any RHS on
    the equality form, so `[[ "$URL" == "$SOMETHING_ELSE" ]]` counted as a pin.
    Both now require a LITERAL on the other side: a quoted string, a `$`-free
    bare word, or (for `case`) an arm that is not bare `*`.
    """
    v = re.escape(var)
    return re.compile(
        # [[ "$VAR" == "literal" ]] -- the RHS must be a LITERAL. `$` is
        # deliberately OUT of the class: with it in, `[[ "$URL" == "$OTHER" ]]`
        # and even `[ "$URL" = "$URL" ]` counted as pins -- verbatim the case
        # this docstring claimed to have closed, which is worse than a missing
        # check because it reports a satisfied property that does not hold.
        # A comparison against another VARIABLE is reached instead by
        # _adjudicated()'s derivation walk, where the literal is at the end of it.
        r"\[\[?[^]]*\$\{?" + v + r"\}?\"?\s*(?:==|!=|=)\s*\"?[A-Za-z0-9_./:-]"
        # case "$VAR" in <non-`*` arm>) -- the arm carries the literal.
        r"|case\s+\"?\$\{?" + v + r"\}?\"?\s+in[^)]*?[A-Za-z0-9./:_-][^)]*\)"
        # =~ against an anchored ERE, with at least one literal character AFTER
        # the anchor. A bare `^` matches every string, so requiring only `=~ ^`
        # accepted a regex that adjudicates nothing.
        r"|\$\{?" + v + r"\}?\"?\s*=~\s*\^[A-Za-z0-9(\[\\]"
    )


TRAILING_COMMENT = re.compile(r"""(?:^|[ \t])\#(?=(?:[^'"]|'[^']*'|"[^"]*")*$).*$""")


def strip_trailing_comment(line: str) -> str:
    """Drop a trailing `#` comment when it is OUTSIDE quotes.

    `strip_comment` deliberately removes only WHOLE-line comments, to protect
    `${VAR##*/}`. That conservatism made comment text classifier input, and a
    trailing comment then satisfied every Rule D limb at once:

        curl -u "svc:$TOK" "$SINK"   # curl --disable --noproxy '*'

    reported clean. This is `cq-assert-anchor-not-bare-token` inside the guard
    itself. The lookahead counts quotes to the end of the line, so a `#` inside a
    quoted argument (a fragment URL, a colour literal) is preserved; `${VAR#...}`
    is preserved because it is not preceded by whitespace or line-start.
    """
    return TRAILING_COMMENT.sub("", line)


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
        line = strip_trailing_comment(strip_comment(raw))
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
        cmd = " ".join(
            strip_trailing_comment(strip_comment(x)).strip().rstrip("\\").strip()
            for x in lines[start:end + 1]
        )
        # TWO SCOPES, because the two questions have different extents.
        #
        # A CREDENTIAL legitimately arrives from across a pipeline
        # (`printf 'Authorization: …' | curl --header @-`), so classification
        # reads the whole assembly. FLAGS cannot: they must be on the invocation
        # itself. Reading both from one string let a compliant neighbour launder
        # a credentialed call -- measured on both `curl --disable …; curl -u …`
        # (same line) and a two-line pipeline whose FIRST stage was compliant.
        segments = [x for x in re.split(r";|&&|\|\||\|", cmd) if x.strip()]
        invocation = cmd
        for seg in reversed(segments):
            if CURL_INVOKE.search(seg):
                invocation = seg
                break
        cmd = _inline_arrays(cmd, lines, i)
        cmd = _inline_config_file(cmd, lines)
        # The inliners must run on the STRING, before the scope split -- an
        # earlier revision built the pair first and the inliners then received a
        # tuple, so the linter raised TypeError on every file with an expanded
        # array. It surfaced as "0 findings", which is byte-identical to clean.
        invocation = _inline_arrays(invocation, lines, i)
        invocation = _inline_config_file(invocation, lines)
        out.append((i, (cmd, invocation)))
    return out


# The surrounding quotes are consumed too: substituting inside them leaves
# `curl "--disable ...`, and the position check would miss a compliant call site.
ARRAY_EXPANSION = re.compile(r"\"?\$\{([A-Za-z_][A-Za-z0-9_]*)\[[@*]\]\}\"?")
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


# A declaration may carry ANY declaration builtin and flags, or none at all:
# `local -a x=(`, `declare -ar x=(`, `readonly x=(` and a plain `local x=(` are the same
# array. The prefix once knew only `local -a` / `declare -a` / `readonly -a`, so
# `local curl_args=(` in discord-setup.sh lost its declaration (only the later `+=(`
# append was inlined) and an `Authorization: Bot` header in it went unreported, while a
# compliant `local x=(--disable ...)` read as a FALSE Rule D finding. Shared by Rule D, Rule E
# and the wrapper analysis. To reproduce the Rule D census over the tracked tree, run
# `python3 scripts/lint-shell-trace-credential-refusal.py --census` (it prints the offender
# set per rule); the before/after of this change is not kept as a repo artifact.
_ARRAY_DECL_PREFIX = r"^\s*(?:(?:local|declare|readonly|typeset)(?:\s+-[A-Za-z]+)*\s+)?"


def _array_body(name: str, lines: list[str], before: int | None = None) -> tuple[str, str]:
    """-> (body of the `=(` declaration, bodies of any `+=(` appends).

    Split because POSITION is part of Rule D's property: only the initial
    declaration can supply curl's FIRST argument, so a later `+=` append must not
    be able to satisfy the --disable-is-first check.
    """
    decl = re.compile(_ARRAY_DECL_PREFIX + re.escape(name) + r"=\(")
    append = re.compile(r"^\s*" + re.escape(name) + r"\+=\(")
    first, extra = "", ""
    # Resolve the declaration NEAREST ABOVE the invocation. A file-global scan
    # let a compliant `local -a args=(--disable …)` in one function satisfy Rule D
    # for every other `curl "${args[@]}"` in the same file -- and `local -a args=(`
    # is already this repo's idiom, so the evasion was one function away.
    candidates = range(len(lines)) if before is None else range(before, -1, -1)
    for i in candidates:
        raw = lines[i]
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
            if before is not None:
                # Nearest-above wins; stop rather than let a later (or earlier)
                # same-named array in another function speak for this call site.
                break
        else:
            extra += " " + body
    return first, extra


def _inline_arrays(cmd: str, lines: list[str], at: int | None = None) -> str:
    """Substitute each expanded array's body AT ITS POSITION in the invocation.

    Appending it instead is wrong in a way that matters: the flags of
    `curl "${args[@]}" "$url"` really ARE first at runtime, so a rule that reads
    them at the end reports a false positive on a compliant call site -- which is
    how a guard teaches its reader to baseline files that are already correct.
    Measured: zot-inventory.sh's http_get was flagged that way until this became
    positional.
    """
    def repl(m):
        first, extra = _array_body(m.group(1), lines, at)
        return (first + " " + extra).strip() if (first or extra) else m.group(0)

    return ARRAY_EXPANSION.sub(repl, cmd)



DERIVES_FROM = r"^\s*(?:local\s+)?([A-Za-z_][A-Za-z0-9_]*)=\"?\$\{%s(?:[#%%/^,]|:[0-9])"


LITERAL_CONST = r"^\s*(?:readonly\s+|declare\s+-r\s+|export\s+)?%s=\"?([^\"$`\n]+)\"?\s*$"


def _compared_to_literal_const(var: str, body: str) -> bool:
    """True when `$var` is compared against a variable holding a LITERAL.

    Removing `$` from _pin_re's RHS class closed the indirect-pin bypass and, on
    its own, also rejected the idiom this repo PREFERS -- single-sourcing the
    expected value into one `readonly` constant and comparing against that:

        readonly INGEST_URL_PINNED="https://…/"
        [ "$INGEST_URL" != "$INGEST_URL_PINNED" ] && die

    A rule that rejects that rewards duplicating the literal at both sites, which
    is a drift seam. So the comparand is followed one step: it counts as a pin
    only when its own assignment is a literal with NO expansion in it (`$` and
    backtick are excluded from the value class), which is exactly what makes it a
    constant rather than a second env-settable variable.
    """
    for m in re.finditer(
        r"\$\{?" + re.escape(var) + r"\}?\"?\s*(?:==|!=|=)\s*\"?\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?",
        body,
    ):
        rhs = m.group(1)
        if re.search(LITERAL_CONST % re.escape(rhs), body, re.M):
            return True
    return False


def _adjudicated(var: str, body: str) -> bool:
    """True when the destination is adjudicated against a literal.

    ONE HOP of derivation is followed, because the repo's careful validators do
    not compare the destination variable itself -- they strip it down and check
    the pieces. scripts/betterstack-ingest-probe.sh derives `_bs_rest` -> `_bs_auth`
    -> `_bs_host` and refuses on each, and reading only `$VAR` scored that file as
    UNPINNED: a false positive on the best destination validator in the tree,
    which would have taught the next reader to baseline it.
    """
    if _pin_re(var).search(body) or _compared_to_literal_const(var, body):
        return True
    seen = {var}
    frontier = [var]
    for _ in range(3):  # bounded: the real idiom is 3 strips deep
        nxt = []
        for v in frontier:
            for m in re.finditer(DERIVES_FROM % re.escape(v), body, re.M):
                d = m.group(1)
                if d in seen:
                    continue
                seen.add(d)
                nxt.append(d)
                if _pin_re(d).search(body):
                    return True
        if not nxt:
            break
        frontier = nxt
    return False


_SUBST_OPEN = ("$(", "<(", ">(")
# A redirection operator token (`<`, `<<<`, `>`, `>>`, `2>`, `&>`): the word
# AFTER it is a file / here-string / process substitution, not a curl operand.
_REDIR_OP = re.compile(r"^(?:\d*|&)(?:<<<|<<|<|>>|>)$")


def _mask_cmdsubs(cmd: str) -> tuple[str, dict[str, list[str]]]:
    """Replace every `$( ... )`, `<( ... )` and `>( ... )` span with an opaque placeholder.

    Process substitution (`< <(printf ... "$TOK")`) is masked the same way: its
    body is data on a file descriptor, one shell word, never a curl operand.

    A command substitution is ONE curl argument, but `shlex` splits inside it,
    so its internals surface as free-standing tokens. Measured: `--data "$(jq -nc
    --arg q "$1" '{query:$q}')"` in scripts/supabase-advisor-scan.sh handed the
    JQ variable `$q` to the operand rule as if it were a curl destination -- the
    single false positive the widened derivation produced across 992 files.

    The vars inside are KEPT against the placeholder rather than discarded, so
    masking buys the tokenization fix without paying a fail-open: a destination
    genuinely built by substitution (`curl "$(build_url "$SINK")"`) still yields
    $SINK if -- and only if -- the enclosing argument is an operand.
    """
    subs: dict[str, list[str]] = {}
    out: list[str] = []
    i, n = 0, len(cmd)
    while i < n:
        if cmd.startswith(_SUBST_OPEN, i):
            depth, j = 1, i + 2
            while j < n and depth:
                if cmd.startswith(_SUBST_OPEN, j):
                    depth += 1
                    j += 2
                    continue
                if cmd[j] == ")":
                    depth -= 1
                j += 1
            key = f"CMDSUB{len(subs)}X"
            subs[key] = VAR_IN_TOKEN.findall(cmd[i:j])
            out.append(key)
            i = j
        else:
            out.append(cmd[i])
            i += 1
    return "".join(out), subs


def _tok_vars(tok: str, subs: dict[str, list[str]]) -> list[str]:
    """Variables a single token carries, resolving any masked substitution."""
    found = list(VAR_IN_TOKEN.findall(tok))
    for key, inner in subs.items():
        if key in tok:
            found.extend(inner)
    return found


def _destination_vars(cmd: str) -> set[str]:
    """Variables curl would read as (part of) a destination. POSITIONAL, not name-based.

    The first cut gated this on the variable's NAME -- `(?:URL|URI|ENDPOINT|HOST)\\b`
    -- which is a fail-OPEN in the guard's own operand, and of exactly the class
    Rule D exists to close. `curl --disable --noproxy '*' -u "svc:$TOK" "$SINK"`
    scored fully compliant while the bearer went wherever $SINK said; so did
    $TARGET, $DEST and $BASE, and `\\b` after HOST rejects $INGEST_HOSTNAME. A name
    is a claim about what an author called something, never a property of the code.

    Three channels, because curl has three ways to be told where to go, and the
    fix for one blinded another until each was named:

    (a) a token carrying a scheme (`://`), wherever it sits;
    (b) the config key `url =` -- this is the `--config` channel that
        zot-inventory.sh uses, where the value arrives as the NEXT token of a
        `printf 'url = "%s"' "$INGEST_URL"`, and it is the site #7873 is about;
    (c) an OPERAND of the curl invocation itself: a token not immediately
        preceded by a `-`-leading token. That is what excludes the arguments of
        `-u`, `-H`, `--data-raw` and `-o` without an option table to drift.
        Confined to the curl segment, because `cmd` is the whole PIPELINE --
        unconfined, `printf '...' "$TOKEN" | curl ...` read $TOKEN as an operand.

    (a) and (b) are deliberately NOT confined to that segment: `_inline_config_file`
    appends the config-writing block to the end of `cmd`, past the `|| true` that
    terminates the invocation, so a segment-scoped scan cannot see it. Getting
    this wrong in each direction was caught by a fixture, not by reading.

    Unknown constructs fall toward COUNTING a token, i.e. toward demanding a pin.
    For a guard that is the safe direction: a false positive costs one baseline
    entry a human reads; a false negative costs a credential leaving the host.
    """
    masked, subs = _mask_cmdsubs(cmd)
    try:
        toks = shlex.split(masked, posix=False)
    except ValueError:
        toks = masked.split()
    dest: set[str] = set()

    for i, tok in enumerate(toks):
        # (a) anything carrying a scheme is a destination wherever it sits.
        if "://" in tok:
            dest.update(_tok_vars(tok, subs))
        # (b) the curl config `url =` key, and the explicit --url flag.
        if CONFIG_URL_KEY.search(tok):
            dest.update(_tok_vars(tok, subs))
            if i + 1 < len(toks):
                dest.update(_tok_vars(toks[i + 1], subs))

    # (c) operands of the curl invocation.
    at = next((i for i, t in enumerate(toks)
               if t == "curl" or t.endswith("/curl")), None)
    if at is None:
        return dest
    stop = len(toks)
    for i in range(at + 1, len(toks)):
        if toks[i] in ("|", "||", "&&", ";", "|&"):
            stop = i
            break
    for i in range(at + 1, stop):
        tok = toks[i]
        found = _tok_vars(tok, subs)
        if not found:
            continue
        # A bare `-` is stdin (`--config - "$URL"`), not a flag: what follows IS an operand.
        if toks[i - 1].startswith("-") and toks[i - 1] != "-":
            continue  # the argument of some flag, not an operand
        if _REDIR_OP.match(toks[i - 1]):
            continue  # the target of a redirection, not an operand
        dest.update(found)
    return dest


def check_rule_d(rel: str, lines: list[str], preamble_at: int | None) -> list[str]:
    """Transport confinement + destination pin on every credentialed curl.

    ADR-214 corollary, recorded here because this is where an author sent by the
    "add an equality pin" message below is actually standing: **a test seam for a
    destination pin must never be env-declared.** On this surface the environment
    IS the adversary -- anyone who can substitute the destination variable can set
    the opt-out to match in the same breath, so an env-declared seam
    (`*_TEST_PIN`, `*_ALLOW_*`) is a bypass available to precisely the actor the
    pin defends against. A test that needs a non-vendor destination shims `curl`,
    which exercises the guard, rather than declaring its way past it.
    """
    del preamble_at  # Rule D is independent of the xtrace refusal.
    body = "\n".join(strip_comment(x) for x in lines)
    out: list[str] = []
    for lineno, scopes in _curl_commands(lines) + _wrapper_commands(lines):
        cmd, invocation = scopes
        credentialed = bool(
            CURL_CRED_FLAGS.search(cmd)
            or CURL_STDIN_HEADER.search(cmd)
            # An auth-shaped header on the invocation plus a credential anywhere
            # in the FILE. Reading both from `cmd` made this `(A and B) or B`,
            # which is just `B` -- provably dead (deleting it left --census over
            # 989 files byte-identical). The file-scoped read is the channel it
            # was reaching for: a header assembled from a variable set far above.
            or (CURL_AUTH_HEADER.search(cmd)
                and any(s.search(body) for s in SECRET_SIGNALS))
            or any(s.search(cmd) for s in SECRET_SIGNALS)
        )
        if not credentialed:
            continue
        # ONE finding per call site. Measured across the tree, the two transport
        # limbs fire as a perfectly correlated pair (133/133) because nothing had
        # either flag before #7873 -- two messages doubled the reported volume of
        # the deferred population without adding information.
        missing = []
        if not CURL_DISABLE_FIRST.search(invocation):
            missing.append("`--disable` as its FIRST argument (position is load-bearing: "
                           "it aborts ~/.curlrc parsing, and later is too late)")
        if not CURL_NOPROXY.search(invocation):
            missing.append("`--noproxy '*'` (ALL_PROXY/HTTPS_PROXY redirect it with the "
                           "destination pin fully intact)")
        if missing:
            out.append(
                f"{rel}:{lineno + 1}: credentialed curl is not transport-confined -- missing "
                + " and ".join(missing) + ".\n"
                f"  Model: scripts/supabase-logs-query.sh -- `curl --disable --noproxy '*' …`\n"
            )
        # Destination pin: only when the URL comes from an env-settable variable.
        dest_vars = _destination_vars(cmd)
        for var in set(re.findall(r"\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?", cmd)):
            v = re.escape(var)
            # THREE env-settable spellings, not one. The `: "${VAR:=default}"`
            # form is what scripts/betterstack-ingest-probe.sh uses -- so the limb
            # that IS #7873 was blind to one of #7873's own sites.
            env_settable = (
                r"^\s*(?:export\s+)?" + v + r"=\"?\$\{" + v + r":-"          # VAR="${VAR:-x}"
                r"|^\s*(?:export\s+)?" + v + r"=\"?\$\{[A-Za-z_][A-Za-z0-9_]*:-"  # VAR="${OTHER:-x}"
                r"|^\s*:\s*\"?\$\{" + v + r":="                                # : "${VAR:=x}"
                # VAR="$OTHER" / VAR=$OTHER / VAR="${OTHER}" -- an assignment
                # whose whole RHS is one expansion is env-settable TRANSITIVELY.
                # All three spellings above contain `:-` or `:=`, so dropping the
                # default was a ONE-TOKEN evasion of this limb that kept the file
                # green: `INGEST_URL="${ZOT_INGEST_URL:-...}"` is caught and
                # `INGEST_URL="$ZOT_INGEST_URL"` was not, for the same destination.
                r"|^\s*(?:export\s+|readonly\s+|local\s+)?" + v + BARE_ASSIGN_RHS
            )
            assigned_anywhere = re.search(
                r"^\s*(?:export\s+|readonly\s+|local\s+)?" + v + r"=", body, re.M
            )
            # A variable READ from the environment and never assigned is
            # env-settable BY DEFINITION -- and it is the most env-settable form
            # there is. All three spellings above are assignments, so this case
            # matched none of them: scripts/betterstack-query.sh sends Basic auth
            # to `https://${BETTERSTACK_QUERY_HOST}` behind a non-empty check
            # only, which is #7873's exact shape.
            if not re.search(env_settable, body, re.M) and assigned_anywhere:
                continue
            if var not in dest_vars:
                continue
            if not _adjudicated(var, body):
                out.append(
                    f"{rel}:{lineno + 1}: credentialed curl sends to ${var}, which is "
                    f"env-settable and never compared against a literal.\n"
                    f"  Pin it: refuse unless ${var} equals the expected destination.\n"
                )
    return list(dict.fromkeys(out))


# --- Rule E: no credential header in a curl command's own argument list -------
# (#9597, sweep #7843) A credential passed as `-H "Authorization: Bearer $TOK"` is an
# ARGUMENT of the curl process: every local user reads it from /proc/<pid>/cmdline
# and `ps` for the life of the request, and it lands in any argv audit log. Rule D
# confines WHERE a credentialed curl may send it and says nothing about HOW the
# credential travels, so it accepts this form -- which is why this is its own rule.
#
# The canonical form keeps the credential on curl's STDIN:
#     curl --disable --noproxy '*' ... --config - "$URL" < <(printf 'header = "Authorization: Bearer %s"\n' "$TOK")
# (`-H @-` fed by a pipe and `--header @<(...)` are the other safe spellings).
#
# The property: no executed curl command carries a credential header in its OWN arguments, and
# `--config -` calls do not re-expose it. Rule E runs on every logical command from
# `_curl_commands()`, on that command's INVOCATION SEGMENT only -- never on the whole
# pipeline assembly, which would flag the safe `printf 'Authorization: ...' | curl -H @-`.
#
# Members the property quantifies over:
#   * VOCABULARY: ONE constant, `E_CREDENTIAL`, read at five sites (held-name capture, array
#     capture, `_e_scan`, the call-level check, the wrapper-site check). It matches the header
#     NAME, never a scheme list: ANY `Authorization:` value (Bearer, Bot, Basic, Digest, Token,
#     `${SCHEME}`), plus the other five names listed in `E_CREDENTIAL_HEADERS` (six in all;
#     that tuple is the source of truth, this prose is not), in any case. `apikey:` keeps its
#     own semantics (below). Basic auth (`-u`/`--user`) is the USER ARM (below), a second
#     vocabulary read at the same sites. NAMING: the locals
#     `bearer_*` / `f["bearer"]` / `_e_bearer_arrays` predate the six-name vocabulary and mean
#     "any E_CREDENTIAL header", not "an Authorization: Bearer one"; the suite seds two of them
#     (`bearer_in_call`, `bearer_ctx`), so they are not renamed;
#   * the short `-H` and long `--header` flags, with or without a space (`-H"..."`),
#     double- or single-quoted, any case, the header before OR after the URL, and any
#     number of curl commands per script;
#   * a header held in a VARIABLE (`h="Authorization: Bearer $T"` ... `-H "$h"`),
#     resolved file-wide, and in an ARRAY (`=(`/`+=(`, inlined at the call site by
#     `_inline_arrays`; the declaration may be `local -a x=(`, `declare -ar x=(`, a plain
#     `local x=(` or a bare `x=(`, see `_ARRAY_DECL_PREFIX`);
#   * a second credential header (`apikey:`) on argv in a call that also carries a
#     credential header, on argv or on stdin. A standalone anon-key `apikey:` call is safe;
#   * the hazards of the stdin form itself, on a `--config -` / `-K -` call:
#     `-v`/`--verbose`/`--trace*`/`-D -` print the config's headers to the terminal,
#     a stdin body (`-d @-`, `--data-binary @-`, `-T -`, `--json @-`) cannot share a
#     stdin that is already the config, and a here-string/heredoc feeding the header
#     writes it to a temp file under bash.
# NOT flagged: `-H @-`, `--header @<(...)`, `--config -`, `-K -`, `--config <(...)`,
# a credential inside a trailing comment, printed command text (`echo`/`printf` of a
# curl command: curl is not in command position) and a YAML step whose `shell:` is not bash.
#
# USER ARM (#9597 S2, decision D5). `-u USER:PASSWORD` / `--user USER:PASSWORD` is a credential
# pair on the same /proc/<pid>/cmdline, so it is judged exactly like a header: two constants,
# `E_USER_FLAG` (the value is the NEXT word; covers a bundle ending in the `u`, `-sSu`) and
# `E_USER_ATTACHED` (the value is glued: `-uU:P`, `--user=U:P`), set one flag, `f["user"]`, in
# `_e_scan`, which the call-level check, the wrapper-site check (a `-u` handed to a file-local
# wrapper) and the second-credential rule (`-u` plus an argv `apikey:` reports both reasons) read.
# Array-held `-u` flows through `_inline_arrays` like any other word. The match is case-sensitive
# and whole-word: `-U`/`--proxy-user` (a PROXY credential, pinned as a gap by an xfail fixture),
# `--url` and `--user-agent` are not read, and only the curl invocation segment is scanned, so
# `sort -u`, `docker run --user`, `git push -u` and `sudo -u` are not. The pinned finding grammar
# (`credential header on curl argv`) is UNCHANGED; the basic-auth wording is in the reason clause.
# The safe form is the stdin config: `--config - < <(printf 'user = "%s:%s"\n' "$U" "$P")` behind
# a guard that refuses `"`, a backslash and a newline (measured on curl 8.22 over bytes 0x01-0x7f:
# those are the only three that change how a quoted `user = "..."` value parses).
# Census effect when the arm landed: exactly three curl sites, scripts/betterstack-query.sh
# (converted in the same slice, never baselined) and two R2 SigV4 uploads in apps/cla-evidence
# (`infra/bootstrap.sh`, `scripts/r2-conditional-put.sh`: `--aws-sigv4 ... --user "$ID:$SECRET"`).
# The two cla-evidence sites are NOT converted here: that upload path is the legal-evidence
# pipeline with its own suites and owner, outside the S2 file list, and a defect there would be a
# legal-record regression rather than an ops one. They are baselined in the S2 diff (path and
# count, ceiling row) and tracked in issue #9756; the +2 is census widening, not a regression.
#
# BLIND SPOTS OF THE -u ARM (documented, NOT implemented; each is E=0 on a synthesized file):
#   * an array that is declared in ANOTHER function than the curl call that expands it: `_inline_arrays`
#     resolves a declaration only at the call site's own scope and there is no file-wide fallback for a
#     `-u` array (the bearer arrays have one, `E_ARRAY_WORD`);
#   * option text held in a SCALAR: `OPTS="-s -u $U:$P"; curl $OPTS "$URL"` (the word `$OPTS` is not
#     expanded, so the `-u` inside it is never a word of the curl invocation);
#   * a quoted flag word: `curl "-u" "$U:$P"` / `curl '-u' ...` (the whole-word match reads the quotes);
#   * the match is word-shaped, not operand-aware: `curl -d -u` reads the data value `-u` as the flag
#     (a conservative false positive that curl itself would not treat as basic auth).
#
# SCOPE (decision D1 of the argv-bearer sweep, tier 3). `rule_e_files()` is tracked `*.sh`
# PLUS `.github/**/*.yml|*.yaml` and the direct `.github/*.yml|*.yaml` spellings (workflows,
# composite actions, FUNDING.yml) PLUS
# `apps/**/cloud-init*.yml`. Rules A to D key on a shebang/preamble and stay `*.sh`-only,
# and so does `--changed`: if YAML were in `--changed`, any unrelated edit to a baselined
# workflow (apply-web-platform-infra.yml sits under a byte gate) would force that workflow's
# FULL remediation in the same PR. Growth in YAML is blocked by the repo-wide run's equality
# on path AND count (subject to the limits stated at "Baseline E" below: reviewer-gated, a
# diff can edit the baseline), and an explicit path bypasses the baseline, so a conversion PR
# proves its files clean by naming them. An explicit YAML path
# runs Rule E only. TWO FEEDERS (see check_yaml_file): workflows and composite actions are
# parsed with PyYAML and every `run` string value is scanned (reporting the step name and a
# best-effort line: exact for `run: |`, the first content line for a folded scalar, the key
# line otherwise); cloud-init files are scanned as RAW LINES (list markers stripped; only
# `cloud-init.yml` is Terraform-templated and fails to parse, but one feeder serves all five).
# A `.github` YAML file PyYAML cannot parse is exit 2,
# and so is a missing PyYAML (imported lazily, only when a workflow is about to be parsed).
#
# S3 (#9597, ADR-280): the workflow YAML that cannot fire production on merge, and the two composite
# actions (`notify-ops-email`, `anthropic-preflight`), send their credential through the shared
# `scripts/lib/bearer-curl.sh` (`bc_curl`, `bc_hmac_sha256_hex`), so Rule E sees no argv site in them. Every
# file S3 converts LEAVES baseline E entirely, which is why per-site FINGERPRINT keying was decided "not
# adopted": a re-added argv site in a converted file is an unlisted offender and fails the equality check,
# and the still-listed population is deleted by the later slices, so a keying mechanism would be built for rows that are
# about to go. Residual, stated: while a file is still listed, a PR that converts one site and adds another inside it
# is count-neutral and is a reviewer's catch, as before.
#
# S4 (#9597, ADR-280 addendum): the push-triggered, production-class files (the deploy-webhook callers, the Supabase,
# GitHub App, Resend and Hetzner bearer sites) also leave baseline E, through the shared library or, where a pinned
# property of the job or its suite rules out sourcing a repo file, through the S2 inline wrapper. The two sites S3 held
# back are CLOSED: `workspaces-luks-cutover.yml` (inline wrapper; its infra suite's curl stub gained `--disable` and
# `--noproxy` arms) and the `probe` step of `scheduled-inngest-health.yml` (library; its infra suite now places the
# library beside the classifier in its fake workspace). What stays listed in baseline E after S4 is the S5 population
# (`apply-web-platform-infra.yml`, `cloud-init-registry.yml`) and the two cla-evidence files (#9756).
#
# KNOWN BLIND SPOTS (census-only; a reviewer, not this lint, judges them): message BODIES
# that carry a secret (`-d` operands; the bsky password JSON moved to stdin in this sweep,
# the generic point stands); a secret in a URL (heartbeat
# path secrets, `x-access-token:` userinfo in git remotes; HEARTBEAT-URL DECISION, S2/D9:
# a URL path secret is not decidable from syntax, so it is documented, not detected; a pattern
# census over `curl ... $*HEARTBEAT*|*PING*|*CHECKIN*` and the heartbeat variable names found
# the real carriers only in host files under apps/web-platform/infra/ -- `inngest-bootstrap.sh`
# (a heredoc unit), `web-git-data-probe.sh` and `luks-monitor.sh` -- where a conversion fires the
# production apply, so they are an S4/S5-class change with operator notice and are tracked there;
# the other hits of the pattern are the `$HBODY` response-body variable of the Hetzner helpers,
# not a heartbeat; a later conversion is `url = "..."` on the stdin config behind a shape guard); `doppler --token`; `jq --arg`
# (a value on jq's argv); `openssl dgst -hmac "$KEY"` (the key is on openssl's argv, which Rule E does not see:
# it reads curl's argument list). After S4 no production signer in a converted file does this: S4 moved the key to a
# python3 child's environment (`bc_hmac_sha256_hex`, or the canonical inline snippet at the sites that cannot source
# the library) at 20 sites, on top of ci-deploy.sh's fan-out signer and the converted copies in
# scripts/cutover-inngest.sh. WHAT REMAINS, measured 2026-10-09 with `git grep -nE 'dgst .*-hmac'` minus `*.test.sh`,
# fixtures, `tests/`, knowledge-base/ and this file (and no hit is a `#` comment line): TWO sites in
# scripts/cutover-inngest.sh (the registry-probe and doublefire-probe signatures), HELD BACK deliberately because
# converting them edits the census regexes of cutover-inngest-workflow.test.sh, a suite an open draft PR also edits;
# owner #9757 item 1, taken after that draft merges. And two Markdown files that agents EXECUTE and that teach the argv
# form (plugins/soleur/skills/ship/SKILL.md and the postmerge skill's deploy-status-debugging.md reference): plugin
# files, outside S4, tracked under #9757. A stdin or env form EXISTS (the library, the converted signers in
# scripts/cutover-inngest.sh, the community skill's lib/hmac-sha1-b64.sh and the Python signers) and is not detected
# here: the population-derived guard that bounds the remainder to exactly those two arms is a stage of
# tests/scripts/test-argv-bearer-sweep.sh, not this lint);
# header VALUES held in `env:` and passed as `-H "$H"` (the assignment is not in the scanned
# body); `env -i`; `wget`; `gh api -H`; `-K file` configs written with the default umask;
# cookies (`-b`, `Cookie:`) and vendor-specific custom headers (`x-gitlab-token`), pinned by
# an xfail row in the suite. Two
# populations carry argv credentials, are not scanned, and are owned by no S2-S5 slice (tracked
# on the #9597 restatement): `apps/cla-evidence/infra/object_lock.tf` (a `local-exec` curl with
# an `Authorization` header) and Markdown that agents EXECUTE (`infra-security.md`,
# `api-security.md`, the postmerge/ship/preflight skill docs; `flag-bootstrap/SETUP.md` was
# converted by hand and nothing now protects it). Cloud-init folded, flow-list and quoted
# `runcmd` items are census-only too (see `_cloud_init_lines`).
#
# VOCABULARY GAPS (measured E=0 on a synthesized one-line `curl ... -H "<name>: $TOK" "$URL"`;
# NOT added to the vocabulary because the baseline impact of adding them is unmeasured; Rule D
# still classifies some of them): the `--oauth2-bearer` operand (Rule D's CURL_CRED_FLAGS lists
# it, Rule E does not; no measured site), `-U`/`--proxy-user` (a proxy credential; pinned by an
# xfail fixture), and the header names
# `x-hub-signature-256`, `X-Auth-Token`, `X-Auth-Key`, `PRIVATE-TOKEN` (Rule D's
# CURL_AUTH_HEADER lists `Private-Token`, Rule E does not), `Doppler-Token`,
# `CF-Access-Jwt-Assertion` and `x-amz-security-token`.
#
# EVASION SHAPES (each measured E=0 on a synthesized file; pre-existing and S3 scope, detection
# is NOT changed here, so a reviewer must read for them):
#   * an interpreter fed a heredoc (`bash <<'EOF'`, `python3 - <<'EOF'`) is masked unless the
#     heredoc is written to a file (`cat > f <<EOF`, which IS scanned); `node -e "...curl..."`
#     and `python3 -c "...curl..."` never have curl in command position;
#   * only the LAST curl of a logical command is judged (inherited from Rule D):
#     `curl -H "Authorization: ..." a; curl b`, `... && curl b` and `... | curl b` all pass,
#     while the same two commands on separate lines are each judged;
#   * curl inside `<(...)` or `>(...)` (`diff <(curl ...)`, `tee >(curl ...)`); `$(...)` is read;
#   * command-word spellings that are not the literal word `curl` (or an absolute path to
#     it): `\curl`, `"curl"`, `$CURL_BIN`, `"$CURL_BIN"`. The two live `x-api-key` argv sites that hid
#     behind the last one (scripts/compound-promote.sh, scripts/learning-retrieval-bench.sh) are
#     converted to the stdin config in S2 (#9597), so no live member of this spelling remains and
#     the detector (a command-word widening) is not built; the blind spot stays and is tracked
#     under #7898's CURL_BIN scope gap;
#   * launcher prefixes that take an option ARGUMENT or run curl indirectly: `sudo -n`,
#     `sudo -u U`, `timeout -s SIG N`, `env -u NAME`, `command -p`, `stdbuf -oL`, `xargs`,
#     `ssh host`, `bash -c '...'`, `eval "..."`, `docker run IMG` and a retry wrapper (a bare
#     `sudo`, `timeout N`, `env`, `command`, `nohup`, `exec`, `time` and `nice -n N` are read);
#   * held-header capture limits (`_e_held_names`): a header NAME assembled from parts
#     (`k=Authorization; -H "$k: ..."`), a value read in (`read -r h < <(printf ...)`), produced
#     by a function (`-H "$(auth_header)"`), supplied by the environment, or defined in a
#     sourced file;
#   * flag spellings: `-sSH"..."` (a bundle with the value glued on; `-sSH "..."` IS read),
#     `--expand-header` and `--proxy-header` (a different flag carrying a header), and the
#     `--oauth2-bearer` credential flag above;
#   * YAML keys other than `run:`: `with: script:` (actions/github-script) and `with: args:`
#     (a docker action's command line) are never read, only `run` scalars are;
#   * `run:` bodies that are not bash: `shell: python` / `shell: node ...` steps are skipped on
#     purpose (SKIP_SHELLS), and a `python3 -c` / `node -e` / `python3 - <<EOF` body inside a
#     bash step falls under the first bullet;
#   * paths excluded by EXCLUDE_PATTERNS: `*.test.sh` and anything under a `test/`, `tests/`,
#     `fixture/` or `fixtures/` directory; and Markdown, which is never scanned (354 tracked
#     `.md` files hold both `curl` and a vocabulary header name, 14 of them outside
#     knowledge-base/; reproduce with a Python walk of `git ls-files '*.md'`);
#   * `apps/cla-evidence/infra/object_lock.tf` (a `local-exec` curl, see above): `.tf` is not
#     a scanned suffix.
#
# HEADER RULINGS (measured with `git grep -il`, 2026-10-07): `X-Soleur-Kb-Drift-Signature`
# (1 site, kb-drift-walker.yml; a body HMAC, the same class as `X-Signature-256`) IS in the
# vocabulary; `X-Sentry-Auth` (22 files, measured as
# `git grep -il x-sentry-auth -- . ':!*.md' ':!knowledge-base' | wc -l`, this lint's own files
# included) is NOT: it carries the Sentry DSN PUBLIC key
# (`sentry_key=`), public by design; `X-Environment-Key` (flip.sh) is NOT: it is the Flagsmith
# CLIENT-side environment key, shipped to browsers, and flip.sh's own comment says so.
# `Proxy-Authorization:` matches the unanchored `authorization` alternate on purpose.
#
# WHY THE STDIN CONFIG FORM (measured, curl 8.22, bash 5.3): (1) `printf ... | curl --config -`
# returns 141 under `set -o pipefail` when the consumer never reads stdin (a 100 KB payload
# reproduces it reliably), so the form is a process substitution
# (`curl ... --config - < <(printf ...)`), which keeps curl the only observed command; (2) a
# token holding a newline plus `url = "..."` makes curl issue a SECOND request, env-sourced
# tokens included, so every converted call carries a token-shape guard first; (3) an unset
# token inside the process substitution yields a headerless request, not an abort. The
# battery tests/scripts/test-argv-bearer-sweep.sh (C3 real-curl oracle, mutation 8) pins (1)-(3).
#
# WRAPPERS: a call to a file-local function that runs curl is judged on the spliced command
# (file-wide wrapper table, transitive closure, `"$@"` replaced by the call's words).
# DOCUMENTED BLIND SPOTS: a wrapper defined in a SOURCED library, a header passed
# positionally (`-H "$2"` inside a wrapper), a bearer in a script SOURCED from a library, a
# second curl on the SAME physical line (the last one is judged, as in Rule D), and
# multi-line quoted strings that print a curl command.
#
# Baseline E is `path<TAB>site-count`. Unlike the other baselines it is compared by
# EQUALITY in the repo-wide run. WHAT IS ENFORCED, precisely: for each listed file the live
# site count must equal the listed count (a file that stops offending, or whose count moves
# either way, fails until the row is regenerated), and an offending file with no row fails.
# WHAT IS NOT: the baseline is an ordinary file in the same diff, so a PR can lower a row,
# raise one or add one (`--write-baseline-e`) and stay green; keeping it shrink-only is a
# REVIEWER gate, not a machine one. Equality also cannot see a net-zero swap: a SITE is a
# whole curl command (not a header line), so converting one command and adding another in the
# same file leaves the count equal and passes. Keying rows on a per-site fingerprint instead
# of a count is an S3 decision (not built here).
BASELINE_E_FILE = Path(__file__).resolve().parent / "lint-shell-trace-credential-refusal-e.baseline.txt"

# The credential-header vocabulary, ONE constant read at five sites (held-name capture,
# array capture, `_e_scan`, the call-level check and the wrapper-site check). It matches the
# header NAME, never a scheme list, so `Authorization: Bearer|Bot|Basic|Digest|${SCHEME}` are
# all credentials. One alternate per line: the suite deletes them one at a time.
E_CREDENTIAL_HEADERS = (
    r"authorization",
    r"cf-access-client-id",
    r"cf-access-client-secret",
    r"x-signature-256",
    r"x-soleur-kb-drift-signature",
    r"x-api-key",
)
E_CREDENTIAL = re.compile(r"(?:" + "|".join(E_CREDENTIAL_HEADERS) + r")\s*:", re.I)
E_APIKEY = re.compile(r"^\s*apikey\s*:", re.I)
# `-H"..."`: the value is glued to the flag. A flag whose value is the NEXT word is E_HDR_FLAG.
E_HDR_ATTACHED = re.compile(r"^-H(?=.)")
E_HDR_FLAG = re.compile(r"^(?:--header|-[A-Za-z]*H)$")
# Basic auth (#9597 S2): `-u USER:PASSWORD` / `--user USER:PASSWORD`. A flag whose value is the NEXT word is
# E_USER_FLAG (covers a short-flag bundle that ends in the `u`: `-sSu`, `-fu`, `-4u`); a value glued to the
# flag is E_USER_ATTACHED (`-uU:P`, `--user=U:P`, and a glued value behind a bundle: `-sSu"U:P"`,
# `-fsSLusvc:$TOK`, `-suU:P`). Both are CASE-SENSITIVE and whole-word on purpose: `-U` / `--proxy-user` is a
# different (proxy) credential, `--url` and `--user-agent` are different flags. One constant per line so the
# suite can delete each on its own.
# THE BUNDLE ALPHABET is curl's short options that take NO argument (measured on curl 8.22.0 from
# `curl --help all`, the entries printed without a `<...>` operand): 0 1 2 3 4 6 B G I J L M N O R S V Z
# a f g i j k l n p q s v, plus `#` (--progress-bar). `u` is inside a bundle only when every letter before
# it is one of these: a letter that takes an argument (`o`, `c`, `e`, `X`, `A`, `H`, `d`, ...) swallows the
# REST of the word as its value, so `-oupload.log` and `-cuser.jar` are an output file and a cookie jar,
# not a `-u`. The suite pins the alphabet against the real curl (`--libcurl` shows CURLOPT_USERPWD) over
# EVERY character of [0-9A-Za-z#:] in both the spaced (`-Xu "U:P"`) and glued (`-XuU:P`) spelling. Measured
# on 8.22.0, four members are CONSERVATIVE on purpose: `-V` and `-M` print and exit before any request, and
# `-2` / `-3` (deprecated SSLv2/3) end the bundle in this curl so the `u` behind them is not seen -- an older
# curl may still read it. In each case the credential is not sent by THIS curl, and a lint that reads
# the spelling as a `-u` can only cost a baseline entry, never hide a leak. `-:` (`--next`) is the opposite
# case and is absent: curl also ends the bundle there, so `-:u` sets no user.
E_SHORT_NOARG = r"[0-46BGIJLMNORSVZafgijklnpqsv#]"
E_USER_FLAG = re.compile(r"^(?:--user|-" + E_SHORT_NOARG + r"*u)$")
E_USER_ATTACHED = re.compile(r"^(?:-" + E_SHORT_NOARG + r"*u(?=.)|--user=)")
E_VERBOSE = re.compile(r"^(?:--verbose|--trace[A-Za-z-]*|-[A-Za-z]*v[A-Za-z]*)$")
E_STDIN_BODY = re.compile(
    r"^(?:-d|--data|--data-binary|--data-raw|--data-ascii|--data-urlencode|--json|-F|--form|--form-string)$"
)
E_HEREDOC = re.compile(r"^<<")
# An array EXPANSION word left over after `_inline_arrays` (declared in another
# function, or assigned after `&&`, which the inliner's line-start anchor cannot see).
E_ARRAY_WORD = re.compile(r"^\"?\$\{([A-Za-z_]\w*)\[[@*]\]\}\"?$")

_E_BODY_AT_STDIN = re.compile(r"^(?:[^=@]*=)?@-$|^[^=@]+@-$")
_E_KEYWORDS = frozenset({
    "if", "then", "elif", "else", "while", "until", "do", "!", "{", "time",
    "command", "exec", "builtin", "sudo", "nohup",
})
_E_ASSIGN_WORD = re.compile(r"^[A-Za-z_]\w*(?:\[[^\]]*\])?\+?=")
_E_HELD_ASSIGN = re.compile(
    r"^\s*(?:(?:local|export|readonly|declare|typeset)(?:\s+-[A-Za-z]+)*\s+)*([A-Za-z_]\w*)\+?=(.*)$"
)
_E_PRINTF_V = re.compile(r"^\s*printf\s+-v\s+([A-Za-z_]\w*)\s+(.*)$")
# A heredoc WRITTEN TO A FILE (`cat > f <<EOF`, `... | tee f`) is code or config that is
# deployed and run later, not printed text, so its body stays in scope.
_HEREDOC_TO_FILE = re.compile(r"(?:^|[^<>&\d])\d*>>?\s*(?!&|/dev/(?:stderr|stdout|null|tty)\b)[^\s<>|;&]|\btee\b")
_HEREDOC_OPEN = re.compile(r"(?<!<)<<(?!<)(-?)\s*\\?(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\2")


def excluded_for_rule_e(rel: str) -> bool:
    """Rule E's scope is Rule D's WITHOUT the exec-bit carve-out.

    A bearer on argv is a hazard in a SOURCED library exactly as in an executed
    script (the process table does not care how the shell got there), so every
    `tests/scripts/lib/*-gate.sh` is in scope, not only the one that carries a
    shebang and the exec bit. `*.test.sh`, `tests/` and `fixtures/` stay out for
    Rule D's reason: they synthesize violations on purpose.
    """
    if PRODUCTION_GATE.search(rel):
        return False
    return any(
        p.search(rel) for p in EXCLUDE_PATTERNS
        if p.pattern != r"^scripts/lib/"
    )


def _heredoc_body_lines(lines: list[str]) -> set[int]:
    """Indexes of lines that are the BODY of a heredoc that is printed, never executed.

    A heredoc whose delimiter is never found is NOT treated as one: masking to the
    end of the file on a `<<` that was really an arithmetic shift would hide every
    later curl. A heredoc written to a FILE is not masked either (see _HEREDOC_TO_FILE).
    """
    masked: set[int] = set()
    i = 0
    while i < len(lines):
        raw = lines[i]
        opener = "" if raw.lstrip().startswith("#") else strip_trailing_comment(raw)
        m = _HEREDOC_OPEN.search(opener)
        if not m or _HEREDOC_TO_FILE.search(opener):
            i += 1
            continue
        delim, dash = m.group(3), m.group(1)
        end = None
        for j in range(i + 1, len(lines)):
            cand = lines[j].lstrip("\t") if dash else lines[j]
            if cand.rstrip() == delim:
                end = j
                break
        if end is None:
            i += 1
            continue
        masked.update(range(i + 1, end + 1))
        i = end + 1
    return masked


def _e_held_names(lines: list[str]) -> set[str]:
    """Variables the file assigns a string containing ANY `E_CREDENTIAL` header name
    (`Authorization: ...` of any scheme, `X-API-Key: ...`, ...), file-wide. Matched on the
    assignment's right-hand side as written: a name assembled from parts is not seen."""
    held: set[str] = set()
    for raw in lines:
        line = strip_trailing_comment(strip_comment(raw))
        if not line:
            continue
        m = _E_HELD_ASSIGN.match(line) or _E_PRINTF_V.match(line)
        if m and E_CREDENTIAL.search(m.group(2)):
            held.add(m.group(1))
    return held


def _e_skip_paren(s: str, i: int) -> int:
    """Index just past the `)` that closes a `(` whose body starts at `i` (quote-aware)."""
    n, q, depth = len(s), None, 1
    while i < n:
        c = s[i]
        if c == "\\":
            i += 2
            continue
        if q == "'":
            if c == "'":
                q = None
            i += 1
            continue
        if q == '"':
            if c == '"':
                q = None
            elif s.startswith("$(", i):
                i = _e_skip_paren(s, i + 2)
                continue
            i += 1
            continue
        if c in "'\"":
            q = c
        elif s.startswith(("$(", "<(", ">("), i):
            i = _e_skip_paren(s, i + 2)
            continue
        elif c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    return n


def _e_split_pos(cmd: str, keep_subs: bool = False, base: int = 0) -> list[tuple[str, str, int]]:
    """Split a logical command into (segment, separator-before, start-offset) at the
    shell's own command boundaries, QUOTE- and SUBSTITUTION-aware.

    `_curl_commands` splits on every `;`/`|` including inside quotes and process
    substitutions, which cuts a `< <(printf ... | ...)` feed in half. Here nothing
    inside a quote splits, `<(`/`>(` stay inside one word, and a `$(...)`/backtick
    substitution is replaced in its ENCLOSING command by an opaque placeholder while
    its body is split recursively into segments of its own. That keeps
    `curl "$base/x?e=$(jq ... '$v|@uri')" -H "$auth"` ONE command (the `-H` after the
    substitution is still curl's argument) and still finds `x=$(curl ...)`.

    `keep_subs=True` keeps the substitution's RAW text in the enclosing segment instead
    of the placeholder (its body is still split into segments of its own). Wrapper
    awareness needs that: a call's arguments are spliced into a wrapper's curl line as
    TEXT, and `-d "$(jq ... "$SINK")"` must not lose the variable it carries. In that
    mode a segment's text is exactly `cmd[start:start + len(segment)]`, which is what
    lets a command word be located and replaced in place.
    """
    out: list[tuple[str, str, int]] = []
    cur: list[str] = []
    seg_at = [0]
    q: str | None = None
    pending = ""
    n = len(cmd)
    i = 0

    def put(text: str, at: int) -> None:
        if not cur:
            seg_at[0] = at
        cur.append(text)

    def flush(next_sep: str) -> None:
        nonlocal pending
        out.append(("".join(cur), pending, base + seg_at[0]))
        cur.clear()
        pending = next_sep

    def body(start: int, end: int) -> str:
        return cmd[start:end - 1] if end > start and cmd[end - 1] == ")" else cmd[start:end]

    while i < n:
        c = cmd[i]
        if q == "'":
            put(c, i)
            if c == "'":
                q = None
            i += 1
            continue
        if c == "\\" and i + 1 < n:
            put(cmd[i:i + 2], i)
            i += 2
            continue
        if cmd.startswith("$(", i):
            j = _e_skip_paren(cmd, i + 2)
            out.extend(_e_split_pos(body(i + 2, j), keep_subs, base + i + 2))
            put(cmd[i:j] if keep_subs else "__CMDSUB__", i)
            i = j
            continue
        if c == "`":
            j = cmd.find("`", i + 1)
            j = n if j < 0 else j
            out.extend(_e_split_pos(cmd[i + 1:j], keep_subs, base + i + 1))
            put(cmd[i:j + 1] if keep_subs else "__CMDSUB__", i)
            i = j + 1
            continue
        if q == '"':
            put(c, i)
            if c == '"':
                q = None
            i += 1
            continue
        if c in "'\"":
            q = c
            put(c, i)
            i += 1
            continue
        if cmd.startswith(("<(", ">("), i):
            j = _e_skip_paren(cmd, i + 2)
            put(cmd[i:j], i)
            i = j
            continue
        if c == "(":
            j = _e_skip_paren(cmd, i + 1)
            flush("")
            out.extend(_e_split_pos(body(i + 1, j), keep_subs, base + i + 1))
            i = j
            continue
        if c in ";|" or cmd.startswith("&&", i):
            j = i + 1
            while j < n and cmd[j] in ";|&":
                j += 1
            flush(cmd[i:j])
            i = j
            continue
        put(c, i)
        i += 1
    flush("")
    return [(s, sep, at) for s, sep, at in out if s.strip()]


def _e_split(cmd: str) -> list[tuple[str, str]]:
    """`_e_split_pos` without offsets and with substitutions masked (Rule E's own view)."""
    return [(s, sep) for s, sep, _at in _e_split_pos(cmd)]


def _e_words_pos(seg: str) -> list[tuple[str, int]]:
    """Shell words of one segment as (RAW word, start offset). `<(...)` is part of one word."""
    words: list[tuple[str, int]] = []
    cur: list[str] = []
    cur_at = 0
    q: str | None = None
    depth = 0
    i, n = 0, len(seg)
    while i < n:
        c = seg[i]
        if q:
            cur.append(c)
            if c == "\\" and q == '"' and i + 1 < n:
                cur.append(seg[i + 1])
                i += 2
                continue
            if c == q:
                q = None
            i += 1
            continue
        if c == "\\" and i + 1 < n:
            if not cur:
                cur_at = i
            cur.append(seg[i:i + 2])
            i += 2
            continue
        if c in "'\"":
            q = c
        elif c == "(":
            depth += 1
        elif c == ")":
            depth = max(0, depth - 1)
        elif c.isspace() and depth == 0:
            if cur:
                words.append(("".join(cur), cur_at))
                cur = []
            i += 1
            continue
        if not cur:
            cur_at = i
        cur.append(c)
        i += 1
    if cur:
        words.append(("".join(cur), cur_at))
    return words


def _e_words(seg: str) -> list[str]:
    """Shell words of one segment, RAW (quotes kept). `<(...)` is part of one word."""
    return [w for w, _at in _e_words_pos(seg)]


def _e_unq(word: str) -> str:
    """A word with its quote characters removed (adequate for classification)."""
    return re.sub(r"[\"']", "", word)


_E_FUNC_HEADER = re.compile(r"^[A-Za-z_][\w:.-]*\(\)$")


def _e_cmd_index(words: list[str]) -> int:
    """Index of the COMMAND word of a segment (len(words) when there is none).

    Only assignments, control keywords, a function header (`name()` / `name ()` /
    `function name`, so a one-line `f() { curl ...; }` body is reached) and the usual
    wrappers (`env`, `timeout`, `nice`) may precede it.
    """
    n = len(words)
    i = 0
    while i < n:
        w = words[i]
        if w in _E_KEYWORDS or _E_ASSIGN_WORD.match(w) or _E_FUNC_HEADER.match(w):
            i += 1
        elif w == "function":
            i += 2
        elif i + 1 < n and words[i + 1] == "()":
            i += 2
        elif w == "env":
            i += 1
            while i < n and (words[i].startswith("-") or "=" in words[i]):
                i += 1
        elif w in ("timeout", "nice"):
            i += 1
            while i < n and (words[i].startswith("-") or re.fullmatch(r"\d+[smhd]?", words[i])):
                i += 1
        else:
            break
    return i


def _e_curl_args(seg: str) -> list[str] | None:
    """The words after `curl` when curl is in COMMAND POSITION in this segment, else None.

    Command position is what separates an executed curl from printed text:
    `echo "curl -H 'Authorization: Bearer $T' ..."` has `echo` in front of it.
    """
    words = _e_words(seg)
    i = _e_cmd_index(words)
    if i < len(words) and re.fullmatch(r"(?:[\w./-]*/)?curl", words[i]):
        return words[i + 1:]
    return None


def _e_header_value(args: list[str], i: int) -> tuple[str | None, int]:
    """If `args[i]` is a header flag, -> (its RAW value, index of the next word); else (None, i)."""
    w = args[i]
    if E_HDR_ATTACHED.match(w):
        return w[2:], i + 1
    if w.startswith("--header="):
        return w[len("--header="):], i + 1
    if E_HDR_FLAG.match(w):
        return (args[i + 1] if i + 1 < len(args) else ""), i + 2
    return None, i


def _e_bearer_arrays(lines: list[str], held_re: re.Pattern | None) -> set[str]:
    """Arrays any assignment of which (`=(` or `+=(`, anywhere in a line) holds a credential
    header (any `E_CREDENTIAL` name; the `bearer` in the name is historical)."""
    text = "\n".join(strip_trailing_comment(strip_comment(x)) for x in lines)
    names: set[str] = set()
    for m in re.finditer(r"(?<![\w$])([A-Za-z_]\w*)\+?=\(", text):
        words = _e_words(text[m.end():_e_skip_paren(text, m.end())])
        i = 0
        while i < len(words):
            val, nxt = _e_header_value(words, i)
            if val is None:
                i += 1
                continue
            hv = _e_unq(val)
            if not hv.startswith("@") and (E_CREDENTIAL.search(hv) or (held_re and held_re.search(hv))):
                names.add(m.group(1))
            i = nxt
    return names


def _e_span(lines: list[str], i: int) -> tuple[int, int]:
    """Physical-line span of the logical command `_curl_commands` builds for line `i`."""
    start = i
    for j in range(i - 1, max(-1, i - 5), -1):
        prev = strip_comment(lines[j]).rstrip()
        if prev.endswith("|") or prev.endswith("\\"):
            start = j
        else:
            break
    end = i
    while end < len(lines) - 1 and strip_comment(lines[end]).rstrip().endswith("\\"):
        end += 1
    return start, end


# --- Wrapper awareness (Rules D and E) -----------------------------------------
# A curl call hidden behind a file-local function is invisible to a scan for the word
# `curl`: `curl_retry -s -H "Authorization: Bearer $T" "$URL"` has no `curl` word, and
# the wrapper's own curl line (`"$CURL_BIN" ... "$@"`) names neither the credential nor
# the destination. Four rules make the call site the unit of analysis:
#   (a) wrapper NAMES are collected FILE-WIDE first -- a function whose body invokes
#       curl (a literal `curl` or a curl-binary variable such as `"$CURL_BIN"`), plus
#       the transitive closure to a fixpoint -- so a wrapper defined AFTER its call
#       site counts, and so does `sb_get() { sb_curl ...; }`;
#   (b) a name matches only in COMMAND position (line start, after `|`, `;`, `&&`,
#       `||`, `(`, `$(`, a backtick, `!`), never as an argument (`echo api_get ...`);
#   (c) the logical command for a call is the wrapper's curl line with `"$@"` (and
#       `$1`..`$9`) replaced by the call's arguments, recursively through wrappers;
#   (d) Rule D's flag/credential/destination checks run on that spliced command; the
#       pin check therefore sees the call's `"$URL"`. Rule E's argv check runs on the
#       call-site ARGUMENTS only (the wrapper's own line is already judged where it is
#       written), and its stdin hazards on the spliced words.
_E_FUNC_DEF = re.compile(
    r"^\s*(?:function\s+([A-Za-z_][\w:.-]*)(?:\s*\(\s*\))?|([A-Za-z_][\w:.-]*)\s*\(\s*\))\s*(.*)$"
)
_E_CURL_LITERAL = re.compile(r"(?:[\w./-]*/)?curl")
_E_CURL_VAR = re.compile(r"\$\{?\w*(?:CURL|curl)\w*(?::[-=][^}]*)?\}?")
# Positional parameters spliced into a wrapper's curl line. A WHOLE-quoted `"$@"` /
# `"$1"` token is replaced together with its quotes (the call's own words carry theirs);
# an embedded `$1` is replaced bare.
_SPLICE_ARG = re.compile(
    r"(?<!\S)\"\$(?:\{(?P<qb>[@*]|[1-9])\}|(?P<qa>[@*]|[1-9]))\"(?![^\s)])"
    r"|\$(?:\{(?P<b>[@*]|[1-9])\}|(?P<a>[@*]|[1-9]))"
)
_FORWARDS_ARGS = re.compile(r"\$(?:[@*1-9]|\{[@*1-9]\})")
_PREFIX_TAIL = re.compile(
    r"(?:(?:[A-Za-z_]\w*\+?=)?\$\(|`|\(|\{|!|\b(?:if|then|elif|else|do|while|until)\b"
    r"|(?:function\s+)?[A-Za-z_][\w:.-]*\s*\(\s*\))\s*$"
)
_Wrapper = namedtuple("_Wrapper", "start end uses")


def _is_curl_word(word: str) -> bool:
    """A command word that runs curl: `curl`, `/usr/bin/curl`, or a curl-binary variable
    (`"$CURL_BIN"`, `"${CURL_BIN:-curl}"`) -- the transport-seam spelling wrappers use."""
    w = _e_unq(word)
    return bool(_E_CURL_LITERAL.fullmatch(w) or _E_CURL_VAR.fullmatch(w))


def _logical_raw(lines: list[str], i: int) -> str:
    """The raw logical command containing physical line `i`, joined as `_curl_commands` does."""
    start, end = _e_span(lines, i)
    return " ".join(
        strip_trailing_comment(strip_comment(x)).strip().rstrip("\\").strip()
        for x in lines[start:end + 1]
    )


def _brace_delta(text: str) -> int:
    t = re.sub(r"\\.", "", text)
    t = re.sub(r"'[^']*'|\"[^\"]*\"", "", t)
    t = re.sub(r"\$\{[^}]*\}", "", t)
    return t.count("{") - t.count("}")


def _function_extents(lines: list[str]) -> list[tuple[str, int, int]]:
    """(name, definition line, last line) of every brace-bodied shell function."""
    out: list[tuple[str, int, int]] = []
    for d, raw in enumerate(lines):
        line = strip_trailing_comment(strip_comment(raw))
        m = _E_FUNC_DEF.match(line)
        if not m:
            continue
        name = m.group(1) or m.group(2)
        rest = m.group(3).strip()
        first = d
        if not rest.startswith("{"):
            if rest:
                continue
            first = d + 1
            while first < len(lines) and not strip_comment(lines[first]).strip():
                first += 1
            if first >= len(lines) or not strip_comment(lines[first]).strip().startswith("{"):
                continue
            rest = strip_trailing_comment(strip_comment(lines[first])).strip()
        depth, end = 0, len(lines) - 1
        for j in range(first, len(lines)):
            depth += _brace_delta(rest if j == first else strip_trailing_comment(strip_comment(lines[j])))
            if depth <= 0:
                end = j
                break
        out.append((name, d, end))
    return out


def _cmd_hits(raw: str, wnames) -> list[dict]:
    """Every command-position `curl` / wrapper call in one logical command."""
    hits: list[dict] = []
    segs = _e_split_pos(raw, keep_subs=True)
    for idx, (seg, sep, start) in enumerate(segs):
        wp = _e_words_pos(seg)
        words = [w for w, _at in wp]
        k = _e_cmd_index(words)
        if k >= len(words):
            continue
        word = words[k]
        if _is_curl_word(word):
            kind, callee = "curl", None
        elif _e_unq(word) in wnames:
            kind, callee = "call", _e_unq(word)
        else:
            continue
        at = start + wp[k][1]
        hits.append({
            "kind": kind, "callee": callee, "word": word,
            "cmd_at": at, "args_at": at + len(word), "seg_end": start + len(seg),
            "heredoc_prev": bool(
                sep.startswith("|") and idx > 0
                and any(E_HEREDOC.match(x) for x in _e_words(segs[idx - 1][0]))
            ),
        })
    return hits


def _hit_qualifies(h: dict, raw: str) -> bool:
    """A curl run always counts; a call to another wrapper counts only when it FORWARDS its
    own arguments (`"$@"`, `$1`). Otherwise an orchestrating `main`/`run_all` that merely
    calls wrappers would become a wrapper itself and duplicate every finding at its own
    call -- its in-body calls are already call sites in their own right."""
    return h["kind"] == "curl" or bool(_FORWARDS_ARGS.search(raw[h["args_at"]:h["seg_end"]]))


def _wrapper_table(lines: list[str]) -> dict[str, "_Wrapper"]:
    """name -> _Wrapper(start, end, uses) for every function that reaches curl.

    `uses` are the body lines that run curl or call another wrapper. The set grows to a
    FIXPOINT: each pass reads the wrappers the PREVIOUS pass found (a snapshot, not the
    live set, so the result never depends on definition order).
    """
    funcs = _function_extents(lines)
    if not funcs:
        return {}
    in_heredoc = _heredoc_body_lines(lines)
    wnames: set[str] = set()
    table: dict[str, _Wrapper] = {}
    changed = True
    while changed:
        known = frozenset(wnames)
        name_re = (re.compile(r"(?<![\w.-])(?:" + "|".join(map(re.escape, sorted(known, key=len, reverse=True)))
                              + r")(?![\w.-])") if known else None)
        table = {}
        for name, d, e in funcs:
            if _is_curl_word(name):
                continue
            uses = []
            for L in range(d, e + 1):
                if L in in_heredoc:
                    continue
                text = strip_trailing_comment(strip_comment(lines[L]))
                if not text or not (re.search("curl", text, re.I) or (name_re and name_re.search(text))):
                    continue
                raw = _logical_raw(lines, L)
                if any(_hit_qualifies(h, raw) for h in _cmd_hits(raw, known)):
                    uses.append(L)
            if uses:
                prev = table.get(name)
                table[name] = _Wrapper(min(d, prev.start) if prev else d, max(e, prev.end) if prev else e,
                                       (prev.uses if prev else []) + uses)
        new = set(table) - wnames
        changed = bool(new)
        wnames |= new
    return table


def _splice_args(region: str, args: list[str]) -> tuple[str, bool]:
    """-> (region with `"$@"`/`$1`.. replaced by the call's argument words, forwards?)."""
    def repl(m):
        tok = m.group("qb") or m.group("qa") or m.group("b") or m.group("a")
        if tok in ("@", "*"):
            return " ".join(args)
        k = int(tok)
        return args[k - 1] if k <= len(args) else ""
    return _SPLICE_ARG.sub(repl, region), bool(_FORWARDS_ARGS.search(region))


def _clean_prefix(prefix: str) -> str:
    """Drop what opens the command (`x=$(`, `if`, `(`, a backtick) so a masked
    substitution does not hide the curl that follows it; pipeline stages stay."""
    p = prefix.rstrip()
    while True:
        q = _PREFIX_TAIL.sub("", p).rstrip()
        if q == p:
            break
        p = q
    return p + " " if p else ""


def _wrapper_expand(lines: list[str], table: dict, name: str, args: list[str],
                    depth: int = 0, trail: tuple = ()) -> list[dict]:
    """Every curl invocation reachable from a call of wrapper `name` with `args`.

    Each result carries the SPLICED logical command and invocation (what Rule D reads),
    the spliced curl argument words (what Rule E's stdin hazards read), whether the
    chain forwards the call's arguments at every step, and how many steps it took.
    """
    if depth > 4 or name in trail or name not in table:
        return []
    out: list[dict] = []
    seen: set[tuple[int, int]] = set()
    names = set(table)
    for L in table[name].uses:
        span = _e_span(lines, L)
        if span in seen:
            continue
        seen.add(span)
        raw = _logical_raw(lines, L)
        for h in _cmd_hits(raw, names):
            if not _hit_qualifies(h, raw):
                continue
            region = _inline_arrays(raw[h["args_at"]:h["seg_end"]], lines, L)
            spliced, fwd = _splice_args(region, args)
            prefix = _clean_prefix(raw[:h["cmd_at"]])
            if h["kind"] == "curl":
                inv = ("curl " + spliced.strip()).strip()
                cmd = prefix + inv + " ; " + raw[h["seg_end"]:]
                out.append({
                    "cmd": _inline_config_file(cmd, lines),
                    "inv": _inline_config_file(inv, lines),
                    "words": _e_words(spliced), "fwd": fwd, "steps": 1,
                    "heredoc": h["heredoc_prev"],
                    "direct": bool(_E_CURL_LITERAL.fullmatch(_e_unq(h["word"]))),
                })
            else:
                for r in _wrapper_expand(lines, table, h["callee"], _e_words(spliced), depth + 1, trail + (name,)):
                    out.append({**r, "fwd": r["fwd"] and fwd, "steps": r["steps"] + 1,
                                "cmd": prefix + r["cmd"]})
    return out


def _wrapper_sites(lines: list[str]) -> list[tuple[int, str, list[str], list[dict]]]:
    """(line, wrapper, call-site argument words, expansions) for every wrapper CALL."""
    table = _wrapper_table(lines)
    if not table:
        return []
    in_heredoc = _heredoc_body_lines(lines)
    name_re = re.compile(r"(?<![\w.-])(?:" + "|".join(map(re.escape, sorted(table, key=len, reverse=True)))
                         + r")(?![\w.-])")
    sites: list[tuple[int, str, list[str], list[dict]]] = []
    seen_spans: set[tuple[int, int]] = set()
    for i, raw in enumerate(lines):
        if i in in_heredoc:
            continue
        text = strip_trailing_comment(strip_comment(raw))
        if not text or not name_re.search(text):
            continue
        span = _e_span(lines, i)
        if span in seen_spans:
            continue
        seen_spans.add(span)
        names = set(table)
        logical = _logical_raw(lines, i)
        for h in _cmd_hits(logical, names):
            if h["kind"] != "call":
                continue
            call_words = _e_words(_inline_arrays(logical[h["args_at"]:h["seg_end"]], lines, i))
            full = _wrapper_expand(lines, table, h["callee"], call_words)
            base = _wrapper_expand(lines, table, h["callee"], [])
            for r, b in zip(full, base):
                r["base"] = b["words"]
            if full:
                sites.append((i, h["callee"], call_words, full))
    return sites


@functools.lru_cache(maxsize=8)
def _wrapper_sites_cached(lines_t: tuple) -> list:
    return _wrapper_sites(list(lines_t))


def _wrapper_commands(lines: list[str]) -> list[tuple[int, tuple[str, str]]]:
    """Spliced (cmd, invocation) pairs for Rule D, one per curl reachable from a call.

    A one-step wrapper whose curl line forwards nothing and is a literal `curl` is skipped:
    it is the very line `_curl_commands` already judges, so splicing adds nothing.
    """
    out: list[tuple[int, tuple[str, str]]] = []
    for lineno, _callee, _call_words, results in _wrapper_sites_cached(tuple(lines)):
        for r in results:
            if r["steps"] == 1 and not r["fwd"] and r["direct"]:
                continue
            out.append((lineno, (r["cmd"], r["inv"])))
    return out


def _e_scan(args: list[str], held_re, bearer_arrays: set[str]) -> dict:
    """Classify the words after `curl` (or after a wrapper name): what travels on argv and
    which stdin-form hazards the words carry."""
    f = {"bearer": False, "apikey": False, "cfg": False, "hdr_stdin": False,
         "verbose": False, "body": False, "heredoc": False, "user": False}
    i = 0
    while i < len(args):
        w = args[i]
        nxt = _e_unq(args[i + 1]) if i + 1 < len(args) else ""
        val, after = _e_header_value(args, i)
        am = E_ARRAY_WORD.match(w)
        if am and am.group(1) in bearer_arrays:
            f["bearer"] = True
        if val is not None:
            hv = _e_unq(val)
            if hv.startswith("@"):
                f["hdr_stdin"] = f["hdr_stdin"] or hv.startswith("@-")
            elif E_CREDENTIAL.search(hv) or (held_re and held_re.search(hv)):
                f["bearer"] = True
            elif E_APIKEY.match(hv):
                f["apikey"] = True
            i = after
            continue
        if E_USER_ATTACHED.match(w):
            f["user"] = True
        elif E_USER_FLAG.match(w):
            f["user"] = True
        if w in ("-K", "--config") and nxt == "-":
            f["cfg"] = True
        elif w == "-K-":
            f["cfg"] = True
        if E_VERBOSE.match(w) or (w in ("-D", "--dump-header") and nxt == "-") or w == "-D-":
            f["verbose"] = True
        if E_STDIN_BODY.match(w) and _E_BODY_AT_STDIN.match(nxt):
            f["body"] = True
        elif re.match(r"^-d@-$|^--data[\w-]*=@-$", w):
            f["body"] = True
        elif (w in ("-T", "--upload-file") and nxt == "-") or w == "-T-":
            f["body"] = True
        if E_HEREDOC.match(w):
            f["heredoc"] = True
        i += 1
    return f


# The finding grammar is PINNED (the suite's E_MSG_RE and its self-check row key on it):
# `<path>:<LINE>: credential header on curl argv<where> -- <reasons>`. Change the wording
# only together with E_MSG_RE in scripts/lint-shell-trace-credential-refusal.test.sh.
E_FINDING = "credential header on curl argv"
# The -u/--user reasons keep the pinned finding phrase and carry the wording in the reason clause.
E_USER_REASON = ("basic-auth credentials (`-u`/`--user USER:PASSWORD`) are an argument of {what}, "
                 "readable by every local user in /proc/<pid>/cmdline and `ps`")
E_USER_REMEDY = ("  Basic auth: put the pair on the stdin config as a `user` key, behind a guard that refuses `\"`, a "
                 "backslash and a newline first (they break the config line): "
                 "`curl … --config - {dest} < <(printf 'user = \"%s:%s\"\\n' \"$USER_NAME\" \"$PASSWORD\")`\n")
# Derived from the vocabulary tuple (one source of truth); the names print as the tuple spells them.
E_HEADER_NAMES = ", ".join(f"`{h}:`" for h in E_CREDENTIAL_HEADERS)


def check_rule_e(rel: str, lines: list[str], line_of=None, where: str = "") -> list[str]:
    """One finding per curl call site that carries a credential header on argv (see the Rule E block).

    `line_of` maps a 0-based index into `lines` to the 1-based line REPORTED (a `run` body
    extracted from YAML reports a line of the workflow file); `where` is text appended after
    the finding phrase (` (step "<name>")`).
    """
    if line_of is None:
        def line_of(n: int) -> int:
            return n + 1
    held = _e_held_names(lines)
    held_re = re.compile(r"\$\{?(?:" + "|".join(map(re.escape, sorted(held))) + r")\b") if held else None
    bearer_arrays = _e_bearer_arrays(lines, held_re)
    in_heredoc = _heredoc_body_lines(lines)
    seen_spans: set[tuple[int, int]] = set()
    out: list[str] = []
    for lineno, scopes in _curl_commands(lines):
        if lineno in in_heredoc:
            continue
        # `_curl_commands` yields one entry per physical line that mentions curl, so a
        # wrapped command whose continuation lines also say "curl" (`|| echo "(curl
        # error)"`) is yielded twice with the same assembly. One site, one finding.
        span = _e_span(lines, lineno)
        if span in seen_spans:
            continue
        cmd, _invocation = scopes
        segs = _e_split(cmd)
        at, args = None, None
        for k in range(len(segs) - 1, -1, -1):
            found = _e_curl_args(segs[k][0])
            if found is not None:
                at, args = k, found
                break
        if args is None or at is None:
            continue
        seen_spans.add(span)

        f = _e_scan(args, held_re, bearer_arrays)
        bearer_argv, apikey, cfg_stdin, hdr_stdin = f["bearer"], f["apikey"], f["cfg"], f["hdr_stdin"]
        verbose, body, heredoc = f["verbose"], f["body"], f["heredoc"]
        user_argv = f["user"]
        # A heredoc/here-string on the PRECEDING pipeline stage feeds the same stdin.
        if segs[at][1].startswith("|") and at > 0:
            if any(E_HEREDOC.match(w) for w in _e_words(segs[at - 1][0])):
                heredoc = True

        bearer_in_call = bearer_argv or bool(E_CREDENTIAL.search(cmd)) or bool(held_re and held_re.search(cmd))
        reasons: list[str] = []
        if bearer_argv:
            reasons.append(f"a credential header ({E_HEADER_NAMES}) is an argument of this curl, "
                           "readable by every local user in /proc/<pid>/cmdline and `ps`")
        if user_argv:
            reasons.append(E_USER_REASON.format(what="this curl"))
        if apikey and (bearer_in_call or user_argv):
            reasons.append("a second credential header (`apikey:`) travels on argv beside the credential")
        if cfg_stdin and verbose:
            reasons.append("config-stdin hazard: -v/--verbose/--trace*/-D - prints the config's "
                           "headers, Authorization included, to the terminal")
        if cfg_stdin and body:
            reasons.append("config-stdin hazard: a stdin body (`@-`, `-T -`) cannot share a stdin "
                           "that is already the config")
        if (cfg_stdin or hdr_stdin) and heredoc:
            reasons.append("config-stdin hazard: a here-string/heredoc feeding the header writes it "
                           "to a temp file; use a process substitution")
        if reasons:
            out.append(
                f"{rel}:{line_of(lineno)}: {E_FINDING}{where} -- " + "; ".join(reasons) + ".\n"
                + ("" if user_argv and len(reasons) == 1 else
                   "  Feed the header on stdin instead (any header name above, any scheme): "
                   "`curl … --config - \"$URL\" < <(printf 'header = \"Authorization: Bearer %s\"\\n' \"$TOKEN\")`\n")
                + (E_USER_REMEDY.format(dest='"$URL"') if user_argv else "")
            )
    # Wrapper CALL sites. The bearer/apikey judgement reads the arguments the author wrote
    # at THIS call; the stdin hazards read the spliced words, and count only when the call
    # adds them (a hazard already present in the wrapper's own line is reported there).
    for lineno, callee, call_words, results in _wrapper_sites_cached(tuple(lines)):
        cf = _e_scan(call_words, held_re, bearer_arrays) if any(r["fwd"] for r in results) else {}
        bearer_argv, apikey = cf.get("bearer", False), cf.get("apikey", False)
        user_argv = cf.get("user", False)
        verbose = body = heredoc = bearer_ctx = False
        for r in results:
            sf = _e_scan(r["words"], held_re, bearer_arrays)
            bf = _e_scan(r["base"], held_re, bearer_arrays)
            hdr = sf["hdr_stdin"] or sf["cfg"]
            bhdr = bf["hdr_stdin"] or bf["cfg"]
            verbose = verbose or (sf["cfg"] and sf["verbose"] and not (bf["cfg"] and bf["verbose"]))
            body = body or (sf["cfg"] and sf["body"] and not (bf["cfg"] and bf["body"]))
            heredoc = heredoc or (hdr and (sf["heredoc"] or r["heredoc"])
                                  and not (bhdr and (bf["heredoc"] or r["heredoc"])))
            bearer_ctx = bearer_ctx or bool(E_CREDENTIAL.search(r["cmd"])) or bool(held_re and held_re.search(r["cmd"]))
        reasons = []
        if bearer_argv:
            reasons.append(f"a credential header ({E_HEADER_NAMES}) is an argument of this call to `{callee}`, "
                           "which hands it to curl on argv, readable by every local user in "
                           "/proc/<pid>/cmdline and `ps`")
        if user_argv:
            reasons.append(E_USER_REASON.format(what=f"this call to `{callee}`, which hands it to curl on argv"))
        if apikey and (bearer_argv or user_argv or bearer_ctx):
            reasons.append("a second credential header (`apikey:`) travels on argv beside the credential")
        if verbose:
            reasons.append("config-stdin hazard: -v/--verbose/--trace*/-D - prints the config's "
                           "headers, Authorization included, to the terminal")
        if body:
            reasons.append("config-stdin hazard: a stdin body (`@-`, `-T -`) cannot share a stdin "
                           "that is already the config")
        if heredoc:
            reasons.append("config-stdin hazard: a here-string/heredoc feeding the header writes it "
                           "to a temp file; use a process substitution")
        if reasons:
            out.append(
                f"{rel}:{line_of(lineno)}: {E_FINDING}{where} -- " + "; ".join(reasons) + ".\n"
                + ("" if user_argv and len(reasons) == 1 else
                   "  Feed the header on stdin instead, inside the wrapper (any header name above, any scheme): "
                   "`curl … --config - \"$@\" < <(printf 'header = \"Authorization: Bearer %s\"\\n' \"$TOKEN\")`\n")
                + (E_USER_REMEDY.format(dest='"$@"') if user_argv else "")
            )
    return out


# --- Rule E over YAML (#9597 S1, decision D1) ----------------------------------
# Two feeders, because the two YAML populations are different languages:
#   * workflows and composite actions (`.github/**`) are scanned by EXTRACTING every `run`
#     string value with PyYAML, so a folded scalar (`run: >-`) and an inline quoted
#     `run: "curl ..."` step reach `check_rule_e` exactly as bash will see them. Raw YAML
#     lines are blind to both (measured 0 of 4 flagged, against 3 of 3 literal blocks).
#   * cloud-init files (`#cloud-config`, `cloud-init*.yml`) are scanned by RAW LINES:
#     `cloud-init.yml` is Terraform-templated (`%{ if }`, `${...}`) and does not parse as YAML
#     (the other four parse), their embedded scripts are literal blocks (`content: |`,
#     `- |`) EXCEPT plain `runcmd` items (`- curl ...`), whose list marker is stripped first
#     (`_cloud_init_lines`); one raw feeder serves all of them so a templated file is never
#     a special case.
# Dispatch keys on SUFFIX and CONTENT, never on a repo-relative `.github/` prefix: explicit
# paths (the suite's out-of-repo fixture copies) are absolute.
# A YAML file PyYAML cannot parse is exit 2 (cannot evaluate, ADR-157) -- never a skip and
# never a raw-line fallback. PyYAML is imported LAZILY, at the first YAML file about to be
# parsed, so the stdlib-only `--changed` path (shell only) never needs it; a missing PyYAML
# is exit 2 as well, and ONLY yaml.YAMLError is the unparseable-file path (a blanket
# `except Exception` would turn a broken loader into "this file did not parse").
YAML_SUFFIXES = (".yml", ".yaml")
# `.github/**/*.yml` needs a second slash, so a file DIRECTLY under `.github/` (FUNDING.yml)
# matches only the `.github/*.yml` spellings; git's `*` also crosses `/`, so those two also match
# the deep files and `rule_e_files` dedupes. Measured: 103 -> 104 discovered YAML files.
E_YAML_PATHSPECS = (".github/**/*.yml", ".github/**/*.yaml", ".github/*.yml", ".github/*.yaml",
                    "apps/**/cloud-init*.yml")
SKIP_SHELLS = frozenset({"python", "pwsh", "powershell", "cmd", "node", "ruby"})
_YAML_STR_TAG = "tag:yaml.org,2002:str"
YamlRun = namedtuple("YamlRun", "text line style name")


def _feeds_raw_lines(path: Path, text: str) -> bool:
    """True for a cloud-init file: named `cloud-init*` or opening with `#cloud-config`."""
    first = next((ln for ln in text.splitlines() if ln.strip()), "")
    return path.name.startswith("cloud-init") or first.startswith("#cloud-config")


def _node_kind(node) -> str:
    return type(node).__name__  # ScalarNode | SequenceNode | MappingNode


def _scalar_text(node) -> str | None:
    return node.value if _node_kind(node) == "ScalarNode" else None


def _yaml_default_shell(node) -> str | None:
    """`defaults.run.shell` of a mapping node, or None."""
    for k1, v1 in node.value:
        if _scalar_text(k1) == "defaults" and _node_kind(v1) == "MappingNode":
            for k2, v2 in v1.value:
                if _scalar_text(k2) == "run" and _node_kind(v2) == "MappingNode":
                    for k3, v3 in v2.value:
                        if _scalar_text(k3) == "shell":
                            return _scalar_text(v3)
    return None


def _yaml_runs(node, default_shell: str | None = None, _seen: set | None = None):
    """Yield a YamlRun for every `run` string scalar at ANY depth, unless a non-bash shell is declared.

    The walk is structural, not path-keyed and not semantic: a `run:` scalar anywhere in the
    tree is scanned, whether or not GitHub would execute it as a step (a `run:` key under
    `with:` or a matrix value is read too), unless the mapping's own `shell:` (or the
    enclosing `defaults.run.shell`) names a SKIP_SHELLS interpreter, as
    lint-workflow-run-body-syntax.py does; no `shell:` at all means bash. Workflow steps
    (`jobs.<id>.steps[*]`) and composite-action steps (`runs.steps[*]`) are just mappings
    holding a `run` scalar. Keys other than `run` (`with: script:`, `args:`) are never read.

    The composed node graph can be cyclic or a fan-out DAG (aliases), so each CONTAINER is
    walked once per inherited default shell; an unbounded-depth flow nest still exceeds the
    recursion limit, which `check_yaml_file` turns into exit 2 (cannot evaluate).

    A `run` scalar is yielded ONCE per node: a `<<: *common` merge key or a `run: *snip` alias
    makes the composer hand back the SAME node object, and one textual site must not be reported
    per reference (the second report would also carry the anchor's line, not its own).
    """
    if _seen is None:
        # Two kinds of key: `(id(container), inherited default shell)` for every sequence/mapping
        # already walked, and `id(run scalar)` for every `run` already yielded (see the alias notes).
        _seen = set()
    kind = _node_kind(node)
    if kind != "ScalarNode":
        # A CONTAINER is walked once per (node, inherited default shell). The composed graph is a
        # graph, not a tree: a cyclic alias (`a: &a [*a]`) would recurse forever and a fan-out DAG
        # (each anchor aliased nine times, forty levels deep) would walk 9**40 paths. The shell is
        # part of the key because a shared anchor can sit under a bash and a non-bash default.
        key = (id(node), default_shell)
        if key in _seen:
            return
        _seen.add(key)
    if kind == "SequenceNode":
        for item in node.value:
            yield from _yaml_runs(item, default_shell, _seen)
    elif kind == "MappingNode":
        default_shell = _yaml_default_shell(node) or default_shell
        run_node = shell_node = name_node = None
        for k_node, v_node in node.value:
            k = _scalar_text(k_node)
            if k == "run":
                run_node = v_node
            elif k == "shell":
                shell_node = v_node
            elif k == "name":
                name_node = v_node
        if (run_node is not None and _node_kind(run_node) == "ScalarNode" and run_node.tag == _YAML_STR_TAG
                and id(run_node) not in _seen):
            shell = (_scalar_text(shell_node) or default_shell or "bash")
            if (shell.split() or [""])[0] not in SKIP_SHELLS:
                name = (_scalar_text(name_node) or "").strip().splitlines()
                _seen.add(id(run_node))
                yield YamlRun(run_node.value, run_node.start_mark.line, run_node.style,
                              name[0][:80] if name else "")
        for key_node, val_node in node.value:
            yield from _yaml_runs(val_node, default_shell, _seen)


# Cloud-init list items. A `runcmd` item is `- <command>`: the marker puts `-` in command
# position, so a raw line `- curl -H "Authorization: ..."` would never be read as a curl call.
# The raw feeder therefore strips a leading list-item marker from every line (line numbers are
# unchanged). Deliberately NOT read: a folded item (`- >-` plus continuation lines), a
# flow-list item (`- [curl, -H, ...]`), a quoted item (`- "curl ..."`) and a `sh -c '...'`
# payload -- each needs a YAML-ish parser for a templated file that does not parse as YAML,
# and a heuristic one is where fresh bypasses come from. They are census-only blind spots.
_CI_ITEM_MARK = re.compile(r"^\s*(?:-\s+)+")


def _cloud_init_lines(text: str) -> list[str]:
    return [_CI_ITEM_MARK.sub("", ln) for ln in text.splitlines()]


def _check_yaml_raw(rel: str, text: str) -> tuple[int, list]:
    e = check_rule_e(rel, _cloud_init_lines(text))
    return (1 if e else 0), [("e", v) for v in e]


def check_yaml_file(path: Path, rel: str) -> tuple[int, list]:
    """Rule E (only) over one YAML file -> (status, violations); status 2 = cannot evaluate."""
    if excluded_for_rule_e(rel):
        return 0, []
    try:
        text = path.read_text(encoding="utf-8")
    except (UnicodeDecodeError, OSError):
        print(f"{rel}: cannot evaluate (unreadable or not UTF-8)", file=sys.stderr)
        return 2, []
    if _feeds_raw_lines(path, text):
        return _check_yaml_raw(rel, text)
    try:
        import yaml
    except ImportError as exc:
        print(f"lint-shell-trace-credential-refusal: PyYAML is required to scan workflow YAML "
              f"({exc}); install it (python3 -m pip install pyyaml) or run where it is available",
              file=sys.stderr)
        sys.exit(2)
    loader = getattr(yaml, "CSafeLoader", yaml.SafeLoader)
    out: list[str] = []
    # ONE guard over the compose AND the walk: PyYAML's composer (the pure-Python loader, used
    # whenever libyaml is absent) recurses on a deep flow nest just as the walk does, so a
    # RecursionError from either is the same "cannot evaluate" (exit 2, ADR-157), never a
    # traceback that exits 1 and reads as "violations found".
    try:
        docs = list(yaml.compose_all(text, Loader=loader))
        for doc in docs:
            if doc is None:
                continue
            for run in _yaml_runs(doc):
                start = run.line
                if run.style == "|":
                    def line_of(n: int, start=start) -> int:
                        return start + 2 + n
                elif run.style == ">":
                    def line_of(n: int, start=start) -> int:
                        return start + 2
                else:
                    def line_of(n: int, start=start) -> int:
                        return start + 1
                where = f' (step "{run.name}")' if run.name else " (unnamed step)"
                out += check_rule_e(rel, run.text.splitlines(), line_of, where)
    except yaml.YAMLError as exc:
        first = (str(exc).strip().splitlines() or ["?"])[0]
        print(f"{rel}: cannot evaluate (YAML did not parse: {first})", file=sys.stderr)
        return 2, []
    except RecursionError:
        print(f"{rel}: cannot evaluate (YAML nesting too deep to walk)", file=sys.stderr)
        return 2, []
    return (1 if out else 0), [("e", v) for v in out]


def check_file(path: Path) -> tuple[int, list[str]]:
    """-> (status, violations). status 2 means cannot-evaluate."""
    try:
        rel = str(path.relative_to(REPO_ROOT))
    except ValueError:
        rel = str(path)
    if path.suffix in YAML_SUFFIXES:
        return check_yaml_file(path, rel)
    d_excluded = excluded_for_rule_d(rel)
    e_excluded = excluded_for_rule_e(rel)
    if excluded(rel) and d_excluded and e_excluded:
        return 0, []
    try:
        text = path.read_text(encoding="utf-8")
    except (UnicodeDecodeError, OSError):
        print(f"{rel}: cannot evaluate (unreadable or not UTF-8)", file=sys.stderr)
        return 2, []  # unparseable
    lines = text.splitlines()
    preamble_at = find_preamble(lines)
    # in_scope() asks "does this file bind a live credential NAME" -- a predicate
    # written for the xtrace refusal, where a credential must be in a VARIABLE for
    # `set -x` to leak it. Rule D's hazard does not need one: `curl --netrc-file
    # /etc/zot.netrc https://…` forwards a credential with no token variable
    # anywhere, and would be scored credential-free. Gating Rule D on it made
    # --netrc/-u/-E/--config -- most of its own classifier -- unreachable.
    abc: list[str] = []
    if in_scope(lines) and not excluded(rel):
        abc = check_rule_a(rel, lines, preamble_at)
        abc += check_rule_b(rel, lines, preamble_at)
        abc += check_rule_c(rel, lines, preamble_at)
    d = [] if d_excluded else check_rule_d(rel, lines, preamble_at)
    e = [] if e_excluded else check_rule_e(rel, lines)
    # Tagged by RULE, never by baseline file. `main()` owns the rule -> baseline
    # map; a tag like "abc" would encode the forgiveness partition in the
    # checker's return type, so splitting the A/B/C baseline later would mean
    # editing this function and every caller's vocabulary.
    violations = [("abc_rule", v) for v in abc] + [("d", v) for v in d] + [("e", v) for v in e]
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


def rule_e_files() -> list[Path]:
    """Rule E's repo-wide file set: tracked `*.sh` plus tracked workflow, composite-action
    and cloud-init YAML. Rules A to D and `--changed` stay shell-only (decision D1: an
    unrelated edit to a baselined workflow must not force its full remediation)."""
    shell = all_shell_files()
    tracked = sorted({REPO_ROOT / q for q in git_out(["ls-files", "--", *E_YAML_PATHSPECS])})
    yaml_files = [p for p in tracked if p.exists()]
    return shell + yaml_files


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
    return rule_e_files()


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


def load_baseline_e() -> dict[str, int]:
    """Baseline E: `path<TAB>site-count` per line. A malformed line is a hard error
    (exit 2): a baseline that cannot be read must not silently suppress nothing."""
    out: dict[str, int] = {}
    if not BASELINE_E_FILE.exists():
        return out
    for n, ln in enumerate(BASELINE_E_FILE.read_text(encoding="utf-8").splitlines(), 1):
        if not ln.strip() or ln.startswith("#"):
            continue
        path, sep, cnt = ln.partition("\t")
        if not sep or not cnt.strip().isdigit() or int(cnt) < 1 or not path.strip():
            print(f"{BASELINE_E_FILE.name}:{n}: malformed baseline E line (want `path<TAB>site-count`, "
                  f"count >= 1): {ln!r}", file=sys.stderr)
            sys.exit(2)
        out[path.strip()] = int(cnt)
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("paths", nargs="*")
    ap.add_argument("--changed", action="store_true")
    ap.add_argument("--base", default="origin/main")
    ap.add_argument("--census", action="store_true")
    ap.add_argument("--write-baseline", action="store_true")
    ap.add_argument("--write-baseline-d", action="store_true",
                    help="rewrite Rule D's baseline from a full-tree scan")
    ap.add_argument("--write-baseline-e", action="store_true",
                    help="rewrite Rule E's baseline (path<TAB>site-count) from a full-tree scan")
    args = ap.parse_args()

    targets = targets_from_args(args)
    # The baseline grandfathers a deferred population for the REPO-WIDE sweep only.
    # In --changed / explicit-path mode it is bypassed, which is what makes the
    # header's drawdown trigger true rather than aspirational -- it was advertised
    # and never implemented.
    scoped = args.changed or args.paths
    baseline = set() if scoped else load_baseline()
    baseline_d = set() if scoped else load_baseline_d()
    # Rule E's baseline is {path: site-count} and suppresses by EQUALITY, not by file:
    # `baseline_e_ok` collects the files whose live count equals the listed one and
    # is what the rule -> suppression map below consults. A listed file that no
    # longer offends, or whose count moved, is NOT in it and is reported instead.
    baseline_e = {} if scoped else load_baseline_e()
    baseline_e_ok: set[str] = set()
    # The rule -> suppression map lives HERE, in main(), which is the layer that
    # owns policy. check_file() only reports what it found.
    baselines_by_rule = {"abc_rule": baseline, "d": baseline_d, "e": baseline_e_ok}
    BASELINE_FOR = baselines_by_rule

    scanned = 0
    offenders: list[str] = []
    offenders_d: list[str] = []
    offenders_e: list[str] = []
    e_counts: dict[str, int] = {}
    unevaluated: set[str] = set()
    all_violations: list[str] = []
    cannot_evaluate = False

    for path in targets:
        scanned += 1
        status, violations = check_file(path)
        if status == 2:
            cannot_evaluate = True
            try:
                unevaluated.add(str(path.relative_to(REPO_ROOT)))
            except ValueError:
                unevaluated.add(str(path))
            continue
        if violations:
            try:
                rel = str(path.relative_to(REPO_ROOT))
            except ValueError:
                rel = str(path)
            if any(rule == "abc_rule" for rule, _ in violations):
                offenders.append(rel)
            if any(rule == "d" for rule, _ in violations):
                offenders_d.append(rel)
            e_n = sum(1 for rule, _ in violations if rule == "e")
            if e_n:
                offenders_e.append(rel)
                e_counts[rel] = e_n
                if baseline_e.get(rel) == e_n:
                    baseline_e_ok.add(rel)
            for rule, v in violations:
                supp = BASELINE_FOR.get(rule, baselines_by_rule["abc_rule"])
                if rel not in supp:
                    all_violations.append(v)

    if args.census:
        print(f"scanned={scanned} offenders={len(offenders)} offenders_d={len(offenders_d)} "
              f"offenders_e={len(offenders_e)}")
        for o in sorted(offenders):
            print(o)
        print("--- rule D ---")
        for o in sorted(offenders_d):
            print(o)
        print("--- rule E ---")
        for o in sorted(offenders_e):
            print(o)
        return 0

    if args.write_baseline_e:
        if scoped:
            print(
                "--write-baseline-e rewrites the ENTIRE Rule E baseline and must scan "
                "the whole tree. Re-run it without --changed and without explicit paths.",
                file=sys.stderr,
            )
            return 2
        BASELINE_E_FILE.write_text(
            "# Rule E (#9597): curl commands that carry a credential header in their OWN argument\n"
            "# list (readable by every local user in /proc/<pid>/cmdline), plus the hazards of\n"
            "# the `--config -` form that replaces it. Format: `path<TAB>site-count`.\n"
            "# ENFORCED: the repo-wide run compares this file to the live offender set by\n"
            "# EQUALITY on path AND count -- a listed file must still offend, its count must\n"
            "# match, and an offender not listed here fails the run. NOT ENFORCED: this file is\n"
            "# in the same diff as the code, so a PR can edit it; keeping it shrink-only is a\n"
            "# REVIEWER gate. A site is a whole curl command (not a header line), so converting\n"
            "# one command and adding another in the same file keeps the count equal and passes.\n"
            "# `--changed` and explicit paths bypass it. Regenerate with `--write-baseline-e`\n"
            "# ONLY after converting sites; a diff that raises or adds a row needs a reviewer.\n"
            + "".join(f"{o}\t{e_counts[o]}\n" for o in sorted(e_counts)),
            encoding="utf-8",
        )
        print(f"rule E baseline written: {len(e_counts)} entries, {sum(e_counts.values())} sites")
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
            "# remediate it. GROWTH is blocked by the repo-wide run itself: a NEW offender\n"
            "# is not in this file, so its violations are reported and the run exits 1.\n"
            + "".join(f"{o}\n" for o in sorted(offenders_d)),
            encoding="utf-8",
        )
        print(f"rule D baseline written: {len(offenders_d)} entries")
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

    if not scoped:
        # Equality, not suppression: report every baseline E entry the live scan
        # contradicts. (A file that could not be read is reported by its own rc=2.)
        for path_e, listed in sorted(baseline_e.items()):
            if path_e in unevaluated:
                continue
            live = e_counts.get(path_e, 0)
            if live == 0:
                all_violations.append(
                    f"{path_e}: listed in baseline E (#9597) but no longer carries a credential header on "
                    f"curl argv (or no longer exists).\n  Delete the entry: baseline E is shrink-only.\n"
                )
            elif live != listed:
                all_violations.append(
                    f"{path_e}: baseline E (#9597) lists {listed} site(s) but the live count is {live}.\n"
                    f"  Baseline E is compared by equality and is shrink-only: convert the sites and "
                    f"lower the entry; never raise it.\n"
                )

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
        f"{len(offenders_d)} baselined (D), {len(baseline_e_ok)} baselined (Rule E: "
        f"{sum(e_counts[p] for p in baseline_e_ok)} site(s))"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
