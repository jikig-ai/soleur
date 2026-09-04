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
import re
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
BASELINE_FILE = Path(__file__).resolve().parent / "lint-shell-trace-credential-refusal.baseline.txt"

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


def excluded(rel: str) -> bool:
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
    violations = check_rule_a(rel, lines, preamble_at)
    violations += check_rule_b(rel, lines, preamble_at)
    violations += check_rule_c(rel, lines, preamble_at)
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
    return [REPO_ROOT / p for p in git_out(["ls-files", "*.sh"])]


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


def load_baseline() -> set[str]:
    if not BASELINE_FILE.exists():
        return set()
    return {
        ln.strip()
        for ln in BASELINE_FILE.read_text(encoding="utf-8").splitlines()
        if ln.strip() and not ln.startswith("#")
    }


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("paths", nargs="*")
    ap.add_argument("--changed", action="store_true")
    ap.add_argument("--base", default="origin/main")
    ap.add_argument("--census", action="store_true")
    ap.add_argument("--write-baseline", action="store_true")
    args = ap.parse_args()

    targets = targets_from_args(args)
    # The baseline grandfathers a deferred population for the REPO-WIDE sweep only.
    # In --changed / explicit-path mode it is bypassed, which is what makes the
    # header's drawdown trigger true rather than aspirational -- it was advertised
    # and never implemented.
    baseline = set() if (args.changed or args.paths) else load_baseline()

    scanned = 0
    offenders: list[str] = []
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
            offenders.append(rel)
            if rel not in baseline:
                all_violations.extend(violations)

    if args.census:
        print(f"scanned={scanned} offenders={len(offenders)}")
        for o in sorted(offenders):
            print(o)
        return 0

    if args.write_baseline:
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

    print(f"OK: {scanned} scanned file(s), {len(offenders)} baselined")
    return 0


if __name__ == "__main__":
    sys.exit(main())
