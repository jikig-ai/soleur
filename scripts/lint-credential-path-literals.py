#!/usr/bin/env python3
"""Lint tracked docs for RESOLVABLE credential-file path literals.

Regression teeth for the credential auto-attach class. Claude Code's harness
auto-attaches a file into model context when a locally-RESOLVABLE filesystem
path to an existing file appears in loaded skill/doc prose (rendered to the
model as a "Read tool result"). `preflight/SKILL.md` Check 10 wrote the literal
home-relative path to the operator's live Doppler CLI config; because preflight
loads on every ship, the harness resolved it and read a live `dp.ct.*` token
into session transcripts. This guard fails any tracked doc that reintroduces a
home-relative-resolvable path to a known credential file, so the trigger cannot
come back.

The distinction that matters is LOCAL RESOLVABILITY, not "mentions a credential":
  * `~/` and `$HOME/` prefixes resolve for ANY loader → HARD FAIL.
  * the bare Doppler config filename resolves via the repo's root project-pointer
    of the same name → HARD FAIL.
  * a hardcoded `/home/<user>/` or `/root/` prefix resolves only on that box and
    is overwhelmingly remote-host runbook documentation → ADVISORY (report-only,
    never gating), to avoid false-positives that erode trust in the gate.

Neutralized forms deliberately PASS: a directory-only `~/.doppler/` (a dir is not
a file → not auto-attached), descriptive names ("SSH private keys", "the Docker
config"), and `<placeholder>` path segments.

Scope: tracked `*.md` under `plugins/**` and `knowledge-base/**`, minus
`**/archive/**` (point-in-time records). Plans/specs are NOT excluded — they load
during `/work`, so they must stay protected.

Modes:
  * full-scan (default): every in-scope `*.md` (used by manual runs).
  * `--changed [--base REF]`: only files changed vs the merge base — grandfathers
    pre-existing historical violations (the CI wiring). New untracked docs count.
    A git error is fail-closed (exit 2).
  * explicit positional paths: scan exactly those files (the test harness).

Exit codes:
    0  no hard-fail resolvable credential path in the scanned set (advisories may
       still be printed)
    1  one or more hard-fail violations (each printed as `file:line: ...`)
    2  argument or git error
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

SCAN_DIRS = ("plugins", "knowledge-base")

# --- Hard-fail regex table (home-relative resolvable credential-file paths). ---
#
# A home prefix that resolves for any loader. The Doppler bare-filename arm is
# the exception: it needs no prefix (the root project-pointer of the same name
# resolves it), so it is a separate pattern below. `${HOME}` (brace form) resolves
# identically to `$HOME` — cover it so a brace-form SSH/aws/etc. path (which has
# no bare-filename arm to fall back on) cannot escape the hard-fail tier.
_HOME = r"(?:~|\$HOME|\$\{HOME\})/"

# Trailing boundary: the match may not be followed by another filename char
# (word char or dot). This blocks `.bak`-suffixed / longer sibling names
# (`id_rsa_backup`, `config.json.tmpl`) and the `.pub` public-key form.
_END = r"(?![\w.])"

HARD_FAIL_RES = tuple(
    re.compile(p)
    for p in (
        # Doppler config, home-relative form: ~/.doppler/.doppler.yaml
        _HOME + r"\.doppler/\.doppler\.yaml" + _END,
        # Doppler config, BARE filename (root project-pointer resolves it).
        # Left boundary: start-or-non-(word|dot) so `app.doppler.yaml` (a
        # different file) does not match, but a bare `.doppler.yaml` in prose or
        # backticks does.
        r"(?:^|[^\w.])\.doppler\.yaml" + _END,
        # SSH private keys under ~/.ssh/ (exclude *.pub via _END on the name).
        _HOME + r"\.ssh/id_(?:ed25519|rsa|ecdsa|dsa)" + _END,
        # netrc / git-credentials home dotfiles.
        _HOME + r"\.netrc" + _END,
        _HOME + r"\.git-credentials" + _END,
        # AWS / gcloud / Docker: the GENERIC filename ONLY under its cred dir.
        _HOME + r"\.aws/credentials" + _END,
        _HOME + r"\.config/gcloud/credentials\.db" + _END,
        _HOME + r"\.docker/config\.json" + _END,
    )
)

# --- Advisory regex table (remote-host prefixes — report-only, never gating). --
#
# The identical credential filenames under a hardcoded /home/<user>/ or /root/
# prefix. These resolve only on that host and are overwhelmingly remote-host
# runbook documentation, so they are surfaced but do not fail the gate.
_REMOTE = r"(?:/home/[^/\s]+|/root)/"

ADVISORY_RES = tuple(
    re.compile(p)
    for p in (
        _REMOTE + r"\.doppler/\.doppler\.yaml" + _END,
        _REMOTE + r"\.ssh/id_(?:ed25519|rsa|ecdsa|dsa)" + _END,
        _REMOTE + r"\.netrc" + _END,
        _REMOTE + r"\.git-credentials" + _END,
        _REMOTE + r"\.aws/credentials" + _END,
        _REMOTE + r"\.config/gcloud/credentials\.db" + _END,
        _REMOTE + r"\.docker/config\.json" + _END,
    )
)

RECIPE = (
    "describe the file without a resolvable path — a directory-only form "
    "(`~/.doppler/`), a descriptive name (\"SSH private keys\", \"the Docker "
    "config\"), or a `<placeholder>` segment"
)


def _first_match(res: tuple[re.Pattern, ...], text: str) -> str | None:
    for r in res:
        m = r.search(text)
        if m:
            return m.group(0).lstrip()
    return None


def scan_text(text: str) -> tuple[list[tuple[int, str]], list[tuple[int, str]]]:
    """Return (hard_hits, advisory_hits) as (1-based line, matched literal)."""
    hard: list[tuple[int, str]] = []
    advisory: list[tuple[int, str]] = []
    for i, line in enumerate(text.splitlines()):
        hit = _first_match(HARD_FAIL_RES, line)
        if hit is not None:
            hard.append((i + 1, hit))
            continue
        adv = _first_match(ADVISORY_RES, line)
        if adv is not None:
            advisory.append((i + 1, adv))
    return hard, advisory


def lint_file(path: Path) -> tuple[list[str], list[str]]:
    """Return (hard_fail_strings, advisory_strings) for a single file."""
    if "/archive/" in path.as_posix():
        return [], []
    try:
        text = path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as exc:  # pragma: no cover - defensive
        return [f"{path}: ERROR reading file: {exc}"], []
    hard, advisory = scan_text(text)
    hard_out = [
        f"{path}:{ln}: resolvable credential-file path `{lit}` — {RECIPE}."
        for ln, lit in hard
    ]
    adv_out = [
        f"{path}:{ln}: advisory (remote-host prefix, not gating) `{lit}`."
        for ln, lit in advisory
    ]
    return hard_out, adv_out


def _git(args: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run(["git", *args], capture_output=True, text=True, check=False)


def _resolve_base(base: str) -> str | None:
    for candidate in (base, "origin/main", "main"):
        if not candidate:
            continue
        mb = _git(["merge-base", candidate, "HEAD"])
        if mb.returncode == 0 and mb.stdout.strip():
            return mb.stdout.strip()
        rp = _git(["rev-parse", "--verify", "--quiet", candidate])
        if rp.returncode == 0 and rp.stdout.strip():
            return candidate
    return None


def changed_files(base_ref: str) -> list[Path] | None:
    diff = _git(["diff", "--name-only", base_ref, "--"])
    if diff.returncode != 0:
        return None
    names: set[str] = {n for n in diff.stdout.splitlines() if n}
    others = _git(["ls-files", "--others", "--exclude-standard"])
    if others.returncode != 0:
        return None
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
        description="Lint tracked docs for resolvable credential-file path literals.",
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
        base_ref = _resolve_base(args.base)
        if base_ref is None:
            print(
                "ERROR: --changed could not resolve a merge base against "
                f"{args.base!r} / origin/main / main (git error). Fail-closed.",
                file=sys.stderr,
            )
            return 2
        picked = changed_files(base_ref)
        if picked is None:
            print(
                "ERROR: --changed could not compute the changed-files set "
                f"(git diff/ls-files failed against {base_ref!r}). Fail-closed.",
                file=sys.stderr,
            )
            return 2
        files = picked
    else:
        files = full_scan_files()

    hard: list[str] = []
    advisory: list[str] = []
    for f in files:
        h, a = lint_file(f)
        hard.extend(h)
        advisory.extend(a)

    # Advisories print but never change the exit code.
    for a in advisory:
        print(a, file=sys.stderr)

    if hard:
        for e in hard:
            print(e, file=sys.stderr)
        print(
            f"\nFAIL: {len(hard)} resolvable credential-file path literal(s). "
            "Such a path makes Claude Code's harness auto-attach the real file "
            "into model context when the doc loads — neutralize each one "
            f"({RECIPE}).",
            file=sys.stderr,
        )
        return 1
    print(
        f"OK: no resolvable credential-file path literals in {len(files)} "
        f"scanned file(s) ({len(advisory)} advisory remote-host mention(s))."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
