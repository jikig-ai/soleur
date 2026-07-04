#!/usr/bin/env python3
"""Lint knowledge-base docs for prescribed *human-run* infra steps.

Enforcement teeth for `hr-no-ssh-fallback-in-runbooks` (AGENTS.core.md): a
plan/spec/runbook that prescribes a human-run terraform / SSH / reboot /
verify-on-private-net infra step must FAIL CI. Soleur users are non-technical
and act only through the web app / CI, so each such step is an automation bug
to close (see also `hr-exhaust-all-automated-options-before`,
`hr-fresh-host-provisioning-reachable-from-terraform-apply`).

Sentinel model — HUMAN-ACTOR + INFRA-IMPERATIVE CO-OCCURRENCE (NOT a bare
token denylist). A line is flagged only when a *human-actor* token AND an
*infra-imperative* token co-occur on the same line (or an actor line is
immediately followed by an imperative line). A bare-token denylist cannot
separate "prescribes a *human* runs terraform apply" (a bug) from "the
dispatch/orchestrator runs terraform apply" (the fix), and would red-line the
de-manualization plan itself plus the retained deferred-orchestrator runbook
steps.

Carve-outs (a matched line is NOT flagged when):
  * inside a `<!-- lint-infra-ignore -->` … `<!-- lint-infra-ignore end -->`
    region (a bare / `start` marker with no `end` grandfathers the rest of the
    file — used to wrap the de-manualization plan + deferred-orchestrator prose);
  * inside a fenced code block (``` / ~~~) or an inline backtick span;
  * under a `## Resolved` or `Last-resort diagnosis` heading (until the next
    heading of equal-or-higher level);
  * in a file whose path contains `/archive/`.

Paren-safety (learning 2026-05-15-ci-sentinel-paren-safety): tokens are short
phrases that span no punctuation boundary; gap phrases use non-greedy `.*?` and
never a literal paren, so prose parentheses can't break a match.

Modes:
  * full-scan (default): every `*.md` under the scan dirs (minus `**/archive/**`).
  * `--changed`: only files changed vs the merge base (grandfathers pre-existing
    violations; the CI/lefthook wiring). New untracked docs are included.
  * explicit positional paths: scan exactly those files (used by lefthook
    `{staged_files}` and the test harness).

Exit codes:
    0  no human-run infra step prescribed in the scanned set
    1  one or more violations (each printed as `file:line: ...` on stderr)
    2  argument or git error

Usage:
    python3 scripts/lint-infra-no-human-steps.py            # full scan
    python3 scripts/lint-infra-no-human-steps.py --changed  # changed vs base
    python3 scripts/lint-infra-no-human-steps.py FILE...     # explicit files
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

# Scan roots (P1-8a: legal/runbooks + architecture/decisions are included so an
# ADR amendment or a legal runbook can't smuggle a human infra step past the gate).
SCAN_DIRS = (
    "knowledge-base/project/plans",
    "knowledge-base/project/specs",
    "knowledge-base/engineering/operations/runbooks",
    "knowledge-base/legal/runbooks",
    "knowledge-base/engineering/architecture/decisions",
)

# Human-actor tokens. Case-insensitive. `\b` word-boundaries keep `operator`
# from matching inside an unrelated identifier only when it truly is a word.
ACTOR_RES = tuple(
    re.compile(p, re.IGNORECASE)
    for p in (
        r"\boperator\b",              # operator, ask the operator
        r"\byou\b",                   # you
        r"\byour laptop\b",           # your laptop
        r"\bssh into\b",              # SSH into
        r"\blog into\b.*?\bconsole\b",  # log into … console
        r"\bby hand\b",               # by hand
        r"\bmanually\b",              # manually
    )
)

# Infra-imperative tokens. Case-insensitive. Gap phrases use non-greedy `.*?`
# so intervening prose (incl. parentheses) can't break the match.
IMPERATIVE_RES = tuple(
    re.compile(p, re.IGNORECASE)
    for p in (
        r"\b(?:terraform|tofu|opentofu) apply\b",  # terraform/tofu/opentofu apply
        r"\breboot\b",                             # reboot
        r"\bpower[- ]cycle\b",                     # power-cycle / power cycle
        r"\battach the volume\b",                  # attach the volume
        r"\bverify\b.*?\bprivate\b.*?\bip\b",      # verify … private … IP
        r"-target\b.*?\bapply\b",                  # -target … apply
    )
)

FENCE_RE = re.compile(r"^\s*(```|~~~)")
HEADING_RE = re.compile(r"^(#{1,6})\s+(.*?)\s*$")
INLINE_CODE_RE = re.compile(r"`[^`]*`")
CARVE_HEADING_RE = re.compile(r"\bResolved\b|Last-resort diagnosis", re.IGNORECASE)
# Region markers. Order matters: an `end` line also contains `lint-infra-ignore`.
IGNORE_END_RE = re.compile(r"lint-infra-ignore\s+end")
IGNORE_START_RE = re.compile(r"lint-infra-ignore")


def _clean(line: str) -> str:
    """Strip inline backtick spans so command references in code don't match."""
    return INLINE_CODE_RE.sub(" ", line)


def _has_actor(text: str) -> bool:
    return any(r.search(text) for r in ACTOR_RES)


def _has_imperative(text: str) -> bool:
    return any(r.search(text) for r in IMPERATIVE_RES)


def scan_text(text: str) -> list[int]:
    """Return the 1-based line numbers that prescribe a human-run infra step.

    A line contributes an (actor, imperative) signal only when it is NOT
    carved out (fenced / ignore-region / Resolved|Last-resort section). A
    violation is a same-line co-occurrence, or an actor line immediately
    followed by an imperative line (adjacent split).
    """
    lines = text.splitlines()
    n = len(lines)
    actor = [False] * n
    imper = [False] * n

    in_fence = False
    in_ignore = False
    carve = False
    carve_level = 0

    for i, raw in enumerate(lines):
        # Ignore-region markers (checked before fence/heading; they are HTML
        # comments that may sit anywhere). `end` first — it also matches start.
        if IGNORE_END_RE.search(raw):
            in_ignore = False
            continue
        if IGNORE_START_RE.search(raw):
            in_ignore = True
            continue
        if in_ignore:
            continue

        if FENCE_RE.match(raw):
            in_fence = not in_fence
            continue
        if in_fence:
            continue

        hm = HEADING_RE.match(raw)
        if hm:
            level = len(hm.group(1))
            title = hm.group(2)
            if CARVE_HEADING_RE.search(title):
                carve = True
                carve_level = level
            elif carve and level <= carve_level:
                carve = False
            # Heading lines never carry a prescribed step.
            continue
        if carve:
            continue

        cleaned = _clean(raw)
        actor[i] = _has_actor(cleaned)
        imper[i] = _has_imperative(cleaned)

    flagged: set[int] = set()
    for i in range(n):
        if actor[i] and imper[i]:
            flagged.add(i + 1)
        elif actor[i] and i + 1 < n and imper[i + 1]:
            # Actor line immediately above an imperative line (adjacent split).
            flagged.add(i + 1)
    return sorted(flagged)


def lint_file(path: Path) -> list[str]:
    """Return `path:line: ...` violation strings for a single file."""
    if "/archive/" in path.as_posix():
        return []
    try:
        text = path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as exc:  # pragma: no cover - defensive
        return [f"{path}: ERROR reading file: {exc}"]
    out: list[str] = []
    for ln in scan_text(text):
        out.append(
            f"{path}:{ln}: prescribes a human-run infra step "
            f"(actor + terraform/SSH/reboot/verify-on-private-net imperative "
            f"co-occur). Route it through CI / Inngest / a workflow_dispatch, "
            f"or wrap deferred-orchestrator prose in a `<!-- lint-infra-ignore -->` "
            f"region. See hr-no-ssh-fallback-in-runbooks."
        )
    return out


def _git(args: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["git", *args], capture_output=True, text=True, check=False
    )


def _resolve_base(base: str) -> str | None:
    """Return a merge-base SHA against `base` (with sensible fallbacks)."""
    for candidate in (base, "origin/main", "main"):
        if not candidate:
            continue
        mb = _git(["merge-base", candidate, "HEAD"])
        if mb.returncode == 0 and mb.stdout.strip():
            return mb.stdout.strip()
        # `candidate` may itself be a usable ref even if merge-base fails.
        rp = _git(["rev-parse", "--verify", "--quiet", candidate])
        if rp.returncode == 0 and rp.stdout.strip():
            return candidate
    return None


def changed_files(base: str) -> list[Path]:
    """Files changed vs the merge base + new untracked files, under scan dirs."""
    mb = _resolve_base(base)
    names: set[str] = set()
    if mb is not None:
        diff = _git(["diff", "--name-only", mb, "--"])
        if diff.returncode == 0:
            names.update(n for n in diff.stdout.splitlines() if n)
    # Untracked new docs (not yet in any commit) still count as "changed".
    others = _git(["ls-files", "--others", "--exclude-standard"])
    if others.returncode == 0:
        names.update(n for n in others.stdout.splitlines() if n)

    prefixes = tuple(d + "/" for d in SCAN_DIRS)
    picked: list[Path] = []
    for name in sorted(names):
        if not name.endswith(".md"):
            continue
        if not name.startswith(prefixes):
            continue
        p = Path(name)
        if p.is_file():
            picked.append(p)
    return picked


def full_scan_files() -> list[Path]:
    """Every `*.md` under the scan dirs, minus `**/archive/**`."""
    picked: list[Path] = []
    for d in SCAN_DIRS:
        root = Path(d)
        if not root.is_dir():
            continue
        for p in sorted(root.rglob("*.md")):
            if "/archive/" in p.as_posix():
                continue
            picked.append(p)
    return picked


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(
        description="Lint knowledge-base docs for prescribed human-run infra steps.",
    )
    parser.add_argument(
        "--changed",
        action="store_true",
        help="Scan only files changed vs the merge base (grandfathering mode).",
    )
    parser.add_argument(
        "--base",
        default="origin/main",
        help="Base ref for --changed merge-base (default: origin/main).",
    )
    parser.add_argument(
        "paths",
        nargs="*",
        type=Path,
        help="Explicit files to scan (overrides scan-dir discovery).",
    )
    args = parser.parse_args(argv)

    if args.paths:
        files = [p for p in args.paths if p.suffix == ".md" and p.is_file()]
    elif args.changed:
        files = changed_files(args.base)
    else:
        files = full_scan_files()

    errors: list[str] = []
    for f in files:
        errors.extend(lint_file(f))

    if errors:
        for e in errors:
            print(e, file=sys.stderr)
        print(
            f"\nFAIL: {len(errors)} prescribed human-run infra step(s). "
            f"Non-technical Soleur users act only through the web app / CI — "
            f"automate the step or wrap deferred-orchestrator prose in a "
            f"lint-infra-ignore region.",
            file=sys.stderr,
        )
        return 1
    print(f"OK: no human-run infra steps in {len(files)} scanned file(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
