#!/usr/bin/env python3
"""Require the xtrace refusal in every shell script that binds a live credential.

WHY THIS EXISTS (#7797). Shell tracing echoes commands AFTER expansion, so a
secret leaks the moment it is bound to a variable -- before it reaches any
command. Two live API tokens reached an agent transcript that way. PR #7793
fixed the one affected script with a five-line preamble; this lint makes that
preamble the rule rather than a one-off.

WHY A COMMIT-TIME LINT AND NOT A HARNESS HOOK. `case "$-" in *x*)` tests whether
tracing is ON. A boundary interceptor must instead enumerate the ways to turn it
on -- measured at eight forms, three of which carry no `-x` token at all
(`env SHELLOPTS=xtrace`, `env BASH_ENV=<file with set -x>`, `BASH_XTRACEFD`).
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
SIGNAL_EXPANSION = r"\$\{?[A-Za-z_][A-Za-z0-9_]*_(?:TOKEN|KEY|SECRET|PASSWORD|PAT)\}?"
SIGNAL_CAPTURE = r"[A-Z][A-Z0-9_]*_(?:TOKEN|KEY|SECRET|PASSWORD|PAT)=\$\("
SIGNAL_DOPPLER_GET = r"doppler secrets get"
SIGNAL_GH_AUTH = r"gh auth token"

SECRET_SIGNALS = [
    re.compile(SIGNAL_EXPANSION),
    re.compile(SIGNAL_CAPTURE),
    re.compile(SIGNAL_DOPPLER_GET),
    re.compile(SIGNAL_GH_AUTH),
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
PROLOGUE_MAX_CMDS = 4
PROLOGUE_ALLOWED = re.compile(r"^\s*(?:set|shopt|readonly\s+-\w+)\b")

EXCLUDE_PATTERNS = (
    re.compile(r"\.test\.sh$"),
    re.compile(r"(?:^|/)tests?/"),
    re.compile(r"(?:^|/)fixtures?/"),
    re.compile(r"^scripts/lib/"),
)

REMEDY = """case "$-" in
  *x*)
    if [ -n "${YOUR_CREDENTIAL_VAR:-}" ]; then
      printf '[FATAL] refusing to trace with a live credential in scope (see #7797). Re-run with YOUR_CREDENTIAL_VAR= to trace safely.\\n' >&2
      exit 78
    fi
    ;;
esac"""


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
        return [
            f"{rel}: binds a live credential but carries no xtrace refusal.\n"
            f"  Add this as the first thing after `set …` (see #7797):\n\n{REMEDY}\n"
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
            f"  Move it directly below `set …`:\n\n{REMEDY}\n"
        ]
    return []


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
    baseline = load_baseline()

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

    if cannot_evaluate:
        return 2

    if all_violations:
        for v in all_violations:
            print(v, file=sys.stderr)
        print(
            f"lint-shell-trace-credential-refusal: {len(all_violations)} violation(s) "
            f"in {scanned} scanned file(s)",
            file=sys.stderr,
        )
        return 1

    print(f"OK: {scanned} scanned file(s), {len(offenders)} baselined")
    return 0


if __name__ == "__main__":
    sys.exit(main())
