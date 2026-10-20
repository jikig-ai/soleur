#!/usr/bin/env python3
"""Shrink-only lint ratchet: ruff over tracked Python, eslint no-unused-vars over test dirs.

    python3 plugins/soleur/scripts/lint-ratchet.py <scope> [--check | --update | --list] [--base <ref>]

Soleur scopes: ``ruff`` and ``eslint-test-dirs`` (see SCOPES); they run only from the Soleur checkout.
User-repository scopes (PR3b): ``user-ruff`` runs the pinned ruff over the CALLING repository with the
user's own ruff configuration and a baseline at ``.lint-ratchet/ruff.baseline.txt``; ``auto`` decides
whether that repository opted in (a tracked root ``ruff.toml``, ``.ruff.toml`` or ``pyproject.toml``
with a ``[tool.ruff`` table AND a baseline file in the working tree, committed or not) and then runs
``user-ruff --check``. Nothing is installed or run for a repository that did not opt in: ``auto`` prints
one line and exits 0 (outside CI, or in CI once a merge base resolves). ``user-ruff --update`` is the
adoption step and also writes the per-user ruff cache.
Design record: ADR-290; tracker #10331.

A baseline file lists the findings that existed when the scope was introduced. Each entry is
``path|rule|anchor|n``: ``anchor`` is a 12-hex fingerprint of the whitespace-normalised source line
of the finding (the line text is never stored) and ``n`` the 1-based ordinal among identical
``(path, rule, anchor)`` triples, so two identical lines are two entries. ``--check`` enforces

1. the baseline file exists (and is neither a symlink nor carries duplicate lines),
2. the tool ran and its report parsed, and (Soleur scopes) every tracked in-scope file was actually
   scanned: a tracked file the tool silently skipped is a failure, not a smaller census. The user scopes
   count the files ruff listed instead and warn about tracked symlinks and untracked files,
3. (Soleur scopes) the scan saw enough files (a floor per scope); the user scopes have no floor, a scan of
   zero files is a WARN and never an OK,
4. the baseline EQUALS the live census: a new finding fails, and so does a stale entry,
5. per ``(path, rule)`` the baseline never holds more entries than at the merge base, after
   applying ``git diff -M`` renames, so the baseline can only shrink. The user scopes lift this only
   when the toolchain fingerprint (ruff pin + tracked ruff configs) differs from the merge base's.

Exit codes: 0 clean; 1 drift or vacuity; 2 infrastructure (tool missing or crashed, unparsable
output, hash mismatch, baseline absent or unsafe, no merge base under ``CI``, any unexpected error).
In the user scopes a content-caused exit 2 carries the stable prefix ``REPO-CONTENT:`` so a caller can
tell a defect in the repository from a defect in the toolchain.

Counting is waiver-proof in the Soleur scopes (ruff ``--ignore-noqa``, eslint ``--no-inline-config``; the
user scopes honour the user's own ``# noqa``) and no tool is ever run in a fix mode: the files under scan include test fixtures that are test INPUT.

Library contract (PR3b): ``check(config, root, base, env)`` takes a plain dict with ``name``,
``baseline``, ``floor``, ``run`` (``run(root) -> (findings, file_count)``, may raise ``Vacuous``,
``InfraError`` or ``Skip``), ``remedy``, and optionally ``script``, ``recovery_cmd``,
``waiver_note``, ``ladder``, ``header`` (a callable giving the toolchain header line, which turns on the
fingerprint rule), ``repo_content`` and ``header_recovery``. ``Skip`` propagates to the caller.

Accepted residual of the fingerprint rule: an agent can edit the ruff config, run ``--update`` and go
green. The control is review of the config diff; the rule makes it visible (``CONFIG CHANGED``).

Residual: anchors are read from the working tree, so a partially staged commit can disagree with
the index; the full-tree CI run is the backstop.

Stdlib only and 3.9-safe: lefthook runs this on contributors' macOS system Python.
"""

from __future__ import annotations

import argparse
import contextlib
import hashlib
import json
import os
import platform
import re
import shlex
import shutil
import stat
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import NamedTuple

if sys.version_info < (3, 9):
    sys.stderr.write("lint-ratchet: needs python>=3.9\n")
    sys.exit(2)

# The Soleur scopes (ruff, eslint-test-dirs) always run against the repository this script is vendored
# in: REPO_ROOT is derived from the script location (plugins/soleur/scripts/), never from the cwd.
# A copy placed shallower than four directories (a bare vendor dir) has no such root: the Soleur scopes
# refuse there (build_config), the user scopes never need it.
_ANCESTORS = Path(__file__).resolve().parents
REPO_ROOT = _ANCESTORS[3] if len(_ANCESTORS) > 3 else None
SCRIPT_REL = "plugins/soleur/scripts/lint-ratchet.py"
RUFF_REQUIREMENTS = Path(__file__).resolve().parent / "ruff-requirements.txt"
ESLINT_CONFIG = "apps/web-platform/eslint.test-dirs.config.mjs"
ESLINT_BIN = "apps/web-platform/node_modules/.bin/eslint"
ESLINT_EXTS = (".js", ".mjs", ".cjs", ".jsx", ".ts", ".tsx", ".mts", ".cts")
# Directory names ruff.toml (extend-exclude) deliberately does not scan, wherever they sit in the
# path; anything else a tracked file is missing from ruff's own file list for is a silent skip and
# fails the scan.
EXCLUDED_DIRS = ("knowledge-base",)

# User scopes (PR3b). These pathspecs are deliberately NOT read from SCOPES: the user scopes must give the
# same verdict whatever the Soleur tables hold.
USER_SCOPES = ("user-ruff", "auto")
USER_BASELINE = ".lint-ratchet/ruff.baseline.txt"
USER_PY_PATHSPECS = ("*.py", "*.pyi", "*.pyw")
USER_RUFF_CONFIGS = ("ruff.toml", ".ruff.toml")
USER_PYPROJECT = "pyproject.toml"
MAX_CONFIG_BYTES = 1 << 20
REPO_CONTENT = "REPO-CONTENT: "
HEADER_PREFIX = "# toolchain: "
CONFIG_CHANGED = "CONFIG CHANGED vs merge base"
# Fully qualified: a bare ``origin/main`` is resolved by git as a tag first, and tags travel with a clone.
BASE_LADDER = ("refs/remotes/origin/HEAD", "refs/remotes/origin/main", "refs/remotes/origin/master",
               "refs/remotes/upstream/main", "refs/remotes/upstream/master", "refs/heads/main", "refs/heads/master")
# The only ruff failures where the pinned version is a plausible cause.
PIN_HINT_RE = re.compile(r"(?i)(required[- ]version|unknown rule selector|unknown (field|key|variant|option))")
MAX_BASELINE_BYTES = 16 << 20
# Per launch; Windows' command line is the tight limit, POSIX has 1 MiB (macOS) or more.
ARGV_BUDGET = 24000 if sys.platform == "win32" else 100000
TOTAL_RUN_BUDGET = 1800  # seconds across every chunked ruff launch of one run
NOTICE_LIMIT = 25
LINE_LIMIT = 600
FIELD_LIMIT = 200
# Variables that redirect git to another repository, index or object store, or change how a pathspec is read.
GIT_SCRUB = ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_COMMON_DIR", "GIT_OBJECT_DIRECTORY",
             "GIT_ALTERNATE_OBJECT_DIRECTORIES", "GIT_NAMESPACE", "GIT_PREFIX", "GIT_LITERAL_PATHSPECS",
             "GIT_GLOB_PATHSPECS", "GIT_NOGLOB_PATHSPECS", "GIT_ICASE_PATHSPECS", "GIT_QUARANTINE_PATH",
             "GIT_REPLACE_REF_BASE", "GIT_GRAFT_FILE", "GIT_SHALLOW_FILE")
RULE_PIN_RE = re.compile(r"ruff ([0-9][0-9A-Za-z.]*)")
GIT_TIMEOUT = 120
RUN_TIMEOUT = 900
PIP_TIMEOUT = 300

ENTRY_RE = re.compile(r"^([^|]+)\|([^|]+)\|([0-9a-f]{12})\|([0-9]+)$")
LINE_SPLIT_RE = re.compile(r"\r\n|\r|\n")
# Invisible or direction-changing characters, listed as code points so this source never holds a raw
# line separator: line/paragraph separators, zero-width and bidi controls, invisible operators,
# the soft hyphen, the Mongolian vowel separator, the byte-order mark, the Unicode tag block and variation
# selectors (an ASCII-smuggling channel into a model's context) and the blank hangul/braille fillers.
INVISIBLE_CODEPOINTS = (0x00ad, 0x034f, 0x061c, 0x115f, 0x1160, 0x180e, 0x2028, 0x2029, 0x2060, 0x2061, 0x2062,
                        0x2063, 0x2064, 0x206a, 0x206b, 0x206c, 0x206d, 0x206e, 0x206f, 0x2800, 0x3164, 0xfeff,
                        0xffa0) + tuple(range(0x200b, 0x2010)) + tuple(range(0x202a, 0x202f)) \
    + tuple(range(0x2066, 0x206a)) + tuple(range(0xfe00, 0xfe10)) + tuple(range(0xfff9, 0xfffd)) \
    + tuple(range(0xe0000, 0xe0080)) + tuple(range(0xe0100, 0xe01f0)) \
    + (0x17b4, 0x17b5, 0x2065) + tuple(range(0x180b, 0x180e)) + tuple(range(0x1bca0, 0x1bca4)) \
    + tuple(range(0x1d173, 0x1d17b))
CONTROL_RE = re.compile("[\x00-\x1f\x7f-\x9f" + "".join(chr(c) for c in INVISIBLE_CODEPOINTS) + "]")
# pip output that means the REQUIREMENTS are wrong or the wheel does not match its hash: never a
# skip, because a skipped integrity failure is exactly how a poisoned index would get through.
PIP_INTEGRITY_MARKERS = (
    "DO NOT MATCH THE HASHES",
    "Hashes are required",
    "Invalid requirement",
    "Could not open requirements file",
    "must be pinned",
    "In --require-hashes mode",
)
# Only a positively identified reachability failure may be skipped locally; any other pip
# failure is infrastructure, so a reworded integrity message cannot turn into a silent skip.
PIP_NETWORK_MARKERS = (
    "Could not fetch URL",
    "Temporary failure in name resolution",
    "Name or service not known",
    "Network is unreachable",
    "No route to host",
    "Max retries exceeded",
    "timed out",
    "Connection",
    "nodename nor servname",
    "NameResolutionError",
    "NewConnectionError",
    "Failed to establish a new connection",
    "Failed to resolve",
)

REMEDY_RUFF = (
    "fix the code: SIM115 use a context manager (with open(...)), S110/S112 handle or log the "
    "exception instead of passing, F401 remove the import, F841 use the value or prefix it with _"
)
REMEDY_USER = ("fix the finding; changing your ruff configuration or running --update to make this pass needs the "
               "user's explicit OK; the baseline is yours and may only shrink")
WAIVER_NOTE_SOLEUR = ("inline waivers (# noqa, eslint-disable) are NOT honoured here, and --update must not be used "
                      "to admit a new finding")
WAIVER_NOTE_USER = "inline waivers (# noqa) are honoured here, and --update must not be used to admit a new finding"
REMEDY_ESLINT = (
    "remove the unused binding or prefix it with _ (arguments and variables only; for an unused "
    "catch parameter write catch {})"
)

SCOPES = {
    "ruff": {
        "baseline": "scripts/lint-ratchet-ruff.baseline.txt",
        "floor": 55,
        "scope": ("*.py", "*.pyi", "*.pyw"),
        "remedy": REMEDY_RUFF,
    },
    "eslint-test-dirs": {
        "baseline": "scripts/lint-ratchet-eslint-test-dirs.baseline.txt",
        "floor": 105,
        "scope": (
            "test/**",
            "plugins/soleur/test/**",
            "plugins/soleur/skills/*/test/**",
            "scripts/*.test.mjs",
        ),
        "remedy": REMEDY_ESLINT,
    },
}


class InfraError(Exception):
    """The tool, its output, the baseline or git could not be trusted: exit 2."""


class ContentError(InfraError):
    """The repository's own content (config, baseline) made the run impossible: exit 2, REPO-CONTENT prefix."""


class Vacuous(Exception):
    """The scan would have looked at nothing: exit 1."""


class Skip(Exception):
    """The tool is unobtainable outside CI: print a loud SKIP and exit 0."""


class Finding(NamedTuple):
    path: str
    rule: str
    row: int
    message: str


# --------------------------------------------------------------------------- process helpers


def _exec(run, argv, timeout, label=None, **kwargs):
    """Run a child process with a bound, UTF-8 text capture, mapping spawn failures to InfraError."""
    kwargs.setdefault("capture_output", True)
    kwargs.setdefault("encoding", "utf-8")
    kwargs.setdefault("errors", "replace")
    name = label or Path(str(argv[0])).name
    try:
        return run(argv, timeout=timeout, **kwargs)
    except subprocess.TimeoutExpired:
        raise InfraError("{} timed out after {}s".format(name, timeout))
    except OSError as exc:
        raise InfraError("could not run {}: {}".format(name, exc))


def _clean(text: str) -> str:
    """Strip terminal control characters from anything echoed from a file name or tool message."""
    return CONTROL_RE.sub(" ", text)


def _clip(text: str, limit: int = FIELD_LIMIT) -> str:
    """Clean and bound a repository-controlled string before it is echoed (a file name has no length cap)."""
    text = _clean(text)
    return text if len(text) <= limit else text[:limit - 3] + "..."


def _is_ci(env) -> bool:
    value = (env if env is not None else os.environ).get("CI", "")
    return value.strip().lower() not in ("", "0", "false", "no")


# --------------------------------------------------------------------------- entries


def normalise(text: str) -> str:
    return " ".join(text.split())


def anchor_of(text: str) -> str:
    return hashlib.sha256(normalise(text).encode("utf-8")).hexdigest()[:12]


def format_entry(path: str, rule: str, anchor: str, n: int) -> str:
    return "{}|{}|{}|{}".format(path, rule, anchor, n)


def parse_baseline(text: str) -> list:
    entries = []
    seen = set()
    for number, raw in enumerate(LINE_SPLIT_RE.split(text), start=1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith(("<<<<<<<", "=======", ">>>>>>>")):
            raise ContentError("baseline line {} is a merge-conflict marker: take the base branch's copy of the "
                               "baseline and re-run --update".format(number))
        match = ENTRY_RE.match(line)
        if not match:
            raise ContentError("baseline line {} is not 'path|rule|anchor|n': {!r}".format(number, _clip(line, 80)))
        entry = (match.group(1), match.group(2), match.group(3), int(match.group(4)))
        if entry in seen:
            raise ContentError("baseline line {} duplicates an earlier entry (re-run --update): {!r}".format(
                number, _clip(line, 80)))
        seen.add(entry)
        entries.append(entry)
    return entries


def render_baseline(name: str, entries: list, *, recovery=None, header=None) -> str:
    recovery = recovery or "python3 {} {}".format(SCRIPT_REL, name)
    # The user form belongs to the one config build_user_config builds ("user-ruff"); "auto" resolves to it
    # before any render, so it never reaches here.
    if name == "user-ruff":
        # User baseline: machine-independent text (no absolute path).
        lines = [
            "# lint-ratchet baseline (ruff) for this repository; engine: the Soleur plugin, design in ADR-290.",
            "# Shrink-only: this file always equals the live census, and per (path, rule) it may never hold more",
            "# entries than the merge base, except when the toolchain line below changed (a ruff pin or config",
            "# change; that run prints CONFIG CHANGED so the config diff gets reviewed). Entry: path|rule|anchor|n,",
            "# where anchor is a 12-hex fingerprint of the normalised source line (the line is never stored).",
            "# List the live findings:  {} --list".format(recovery),
            "# After fixing findings:   {} --update  (it refuses to add, except as above)".format(recovery),
            "# Outside Claude Code, replace ${CLAUDE_PLUGIN_ROOT} with the plugin's install directory.",
            "# After a merge conflict, take the base branch's copy of this file and re-run --update.",
        ]
        if header:
            lines.append(header)
        return "\n".join(lines + [format_entry(*entry) for entry in sorted(entries)]) + "\n"
    # Wording is a property of the two Soleur scopes, whose committed baselines are empty by ADR-290; the
    # shrink-only guard rejects any entry against an empty merge-base copy. A Soleur scope that legitimately
    # holds entries must change this header and its pin test.
    header = [
        "# lint-ratchet scope '{}' is a zero-findings gate (design in ADR-290): "
        "fix findings, never baseline them.".format(name),
        "# List the live findings:  {} --list".format(recovery),
        "# After fixing findings:   {} --update  (it refuses to add)".format(recovery),
        "# After a merge conflict, take the base branch's copy of this file and re-run --update.",
    ]
    body = [format_entry(*entry) for entry in sorted(entries)]
    return "\n".join(header + body) + "\n"


def _check_path(path: str) -> None:
    """Refuse a path the entry format cannot round-trip: --update would write a baseline --check rejects forever."""
    if "|" in path or "\n" in path or "\r" in path:
        raise ContentError("path {!r} contains '|' or a newline; the baseline format cannot carry it".format(
            _clip(path)))
    if path != path.strip() or path.startswith(("#", "<<<<<<<", "=======", ">>>>>>>")):
        raise ContentError("path {!r} starts with whitespace, '#' or a conflict marker, or ends with whitespace; "
                           "the baseline format cannot carry it".format(_clip(path)))


def census_pairs(findings: list, root) -> list:
    """Return ``[(entry, finding)]`` sorted by entry; symlinked paths are skipped."""
    root = Path(root)
    lines_cache = {}
    counts = {}
    pairs = []
    for finding in sorted(findings, key=lambda f: (f.path, f.row, f.rule)):
        _check_path(finding.path)
        full = root / finding.path
        if full.is_symlink():
            continue
        if finding.path not in lines_cache:
            # Findings arrive sorted by path, so only the current file's lines are ever needed.
            lines_cache.clear()
            try:
                text = full.read_text(encoding="utf-8", errors="replace")
                lines_cache[finding.path] = LINE_SPLIT_RE.split(text)
            except OSError:
                lines_cache[finding.path] = []
        lines = lines_cache[finding.path]
        text = lines[finding.row - 1] if 1 <= finding.row <= len(lines) else ""
        anchor = anchor_of(text)
        key = (finding.path, finding.rule, anchor)
        counts[key] = counts.get(key, 0) + 1
        pairs.append(((finding.path, finding.rule, anchor, counts[key]), finding))
    return sorted(pairs, key=lambda pair: pair[0])


def census(findings: list, root) -> list:
    return [entry for entry, _ in census_pairs(findings, root)]


# --------------------------------------------------------------------------- adapters


def _relative(filename: str, root) -> str:
    root = Path(root)
    if not os.path.isabs(filename):
        filename = os.path.join(str(root), filename)
    for base in (str(root), None):
        if base is None:
            base = os.path.realpath(str(root))  # only on the fallback: it is a syscall per path otherwise
        rel = os.path.relpath(filename, base)
        if rel != ".." and not rel.startswith(".." + os.sep):
            return rel
    raise InfraError("tool reported a path outside the repository: {!r}".format(_clip(filename)))


def adapt_ruff(text: str, root) -> list:
    try:
        report = json.loads(text)
    except ValueError as exc:
        raise InfraError("ruff printed output that is not JSON: {}".format(exc))
    if not isinstance(report, list):
        raise InfraError("ruff's JSON report is not a list")
    findings = []
    for item in report:
        try:
            code = item.get("code")
            path = _relative(item["filename"], root)
            if not code:
                raise ContentError("ruff could not parse {} ({}); a file that did not parse hides its findings".format(
                    _clip(path), _clip(str(item.get("message", "syntax error")), 80)))
            findings.append(Finding(path, code, int(item["location"]["row"]), item.get("message", "")))
        except (KeyError, TypeError, AttributeError, ValueError) as exc:
            raise InfraError("ruff report item has an unexpected shape ({}: {})".format(type(exc).__name__, exc))
    return findings


def adapt_eslint(text: str, root, tracked=None, seen=None) -> tuple:
    try:
        report = json.loads(text)
    except ValueError as exc:
        raise InfraError("eslint printed output that is not JSON: {}".format(exc))
    if not isinstance(report, list):
        raise InfraError("eslint's JSON report is not a list")
    findings = []
    file_count = 0
    for result in report:
        try:
            path = _relative(result["filePath"], root)
            if tracked is not None and path not in tracked:
                continue
            file_count += 1
            if seen is not None:
                seen.add(path)
            for message in result.get("messages", []):
                if message.get("fatal") or result.get("fatalErrorCount"):
                    raise InfraError("eslint could not parse {} ({}); a file that did not parse hides its "
                                     "findings".format(path, message.get("message", "fatal error")))
                findings.append(Finding(path, message.get("ruleId") or "(eslint)", int(message.get("line", 0)),
                                        message.get("message", "")))
        except (KeyError, TypeError, AttributeError, ValueError) as exc:
            raise InfraError("eslint report item has an unexpected shape ({}: {})".format(type(exc).__name__, exc))
    return findings, file_count


# --------------------------------------------------------------------------- git


def _git(root, args: list, env=None) -> subprocess.CompletedProcess:
    return _exec(subprocess.run, ["git", "-C", str(root), "-c", "core.fsmonitor=false"] + list(args), GIT_TIMEOUT,
                 env=env)


def tracked_files(root, pathspecs, env=None) -> list:
    result = _git(root, ["ls-files", "-z", "--"] + list(pathspecs), env)
    if result.returncode != 0:
        raise InfraError("git ls-files failed: {}".format(result.stderr.strip()[:200]))
    return [name for name in result.stdout.split("\0") if name]


def resolve_base(root, ref, env=None):
    """Return the SHA of the base to compare against, or None when it cannot be resolved."""
    if ref is None:
        result = _git(root, ["merge-base", "origin/main", "HEAD"], env)
    else:
        if ref.startswith("-"):
            raise InfraError("--base {!r} looks like an option, not a ref".format(ref))
        result = _git(root, ["rev-parse", "--verify", "--end-of-options", ref + "^{commit}"], env)
    return result.stdout.strip() if result.returncode == 0 else None


def resolve_base_ladder(root, ref, env=None, baseline=None) -> tuple:
    """User-mode base resolution: ``(sha | None, notes)``.

    An explicit ``--base`` is compared at its merge base with HEAD, like the default. Without one the ladder
    walks the fully qualified rungs; with ``baseline`` it prefers the first rung whose merge base already
    carries that file, so a stale ``origin/HEAD`` left at a pre-adoption commit cannot read as an adoption.
    """
    if ref is not None:
        tip = resolve_base(root, ref, env)
        if tip is None:
            return None, []
        merged = _git(root, ["merge-base", tip, "HEAD"], env)
        return (merged.stdout.strip() if merged.returncode == 0 else tip), []
    first, carrying = None, []
    for rung in BASE_LADDER:
        # The exact ref: git falls back to a TAG named like a missing ref, and tags travel with a clone.
        if _git(root, ["show-ref", "--verify", "--quiet", rung], env).returncode != 0:
            continue
        verified = _git(root, ["rev-parse", "--verify", "--quiet", "--end-of-options", rung + "^{commit}"], env)
        if verified.returncode != 0:
            continue
        merged = _git(root, ["merge-base", verified.stdout.strip(), "HEAD"], env)
        if merged.returncode != 0:
            continue
        sha = merged.stdout.strip()
        notes = []
        if rung.startswith("refs/heads/"):
            notes.append("WARN: using local {} as merge base".format(rung.rsplit("/", 1)[-1]))
        if baseline is None:
            return sha, notes
        if baseline_at(root, sha, baseline, env) is not None:
            carrying.append((sha, notes, rung.startswith("refs/heads/")))
        else:
            first = first or (sha, notes)
    if carrying:
        # Rungs can disagree (a stale origin/HEAD next to a current origin/main): judge growth against the
        # NEWEST merge base that carries the baseline, the strictest reference.
        # A local branch only counts when no remote rung carries the baseline: on main with unpushed commits the
        # local branch is the newest, and judging growth against your own unpushed work would always pass.
        pool = [c for c in carrying if not c[2]] or carrying
        best = pool[0]
        for candidate in pool[1:]:
            if candidate[0] != best[0] and _git(root, ["merge-base", "--is-ancestor", best[0], candidate[0]],
                                                  env).returncode == 0:
                best = candidate
        return best[0], best[1]
    if first is not None:
        return first
    shallow = _git(root, ["rev-parse", "--is-shallow-repository"], env)
    if shallow.returncode == 0 and shallow.stdout.strip() == "true":
        return None, ["shallow clone: fetch more history (fetch-depth: 0) so the shrink-only comparison can run"]
    return None, []


def rename_map(root, sha: str, env=None) -> dict:
    """Map old -> new for renames between ``sha`` and the working tree (staged renames included)."""
    result = _git(root, ["diff", "-M30%", "--no-ext-diff", "--no-textconv", "-z", "--name-status", "--diff-filter=R",
                         sha, "--"], env)
    if result.returncode != 0:
        raise InfraError("git diff failed: {}".format(result.stderr.strip()[:200]))
    tokens = result.stdout.split("\0")
    return dict(zip(tokens[1::3], tokens[2::3]))


def baseline_at(root, sha: str, path: str, env=None):
    """Return the file's text at ``sha``, or None only when the commit genuinely has no such path."""
    listed = _git(root, ["ls-tree", "--name-only", sha, "--", path], env)
    if listed.returncode != 0:
        raise InfraError("git ls-tree {} failed: {}".format(sha[:12], listed.stderr.strip()[:200]))
    if not listed.stdout.strip():
        return None
    shown = _git(root, ["show", "{}:{}".format(sha, path)], env)
    if shown.returncode != 0:
        raise InfraError("git show {}:{} failed: {}".format(sha[:12], path, shown.stderr.strip()[:200]))
    return shown.stdout


def _counts(entries: list, renames=None) -> dict:
    counts = {}
    for path, rule, _anchor, _n in entries:
        key = ((renames or {}).get(path, path), rule)
        counts[key] = counts.get(key, 0) + 1
    return counts


def growth(head_entries: list, base_entries: list, renames=None) -> list:
    head, base = _counts(head_entries), _counts(base_entries, renames)
    return sorted((p, r, n, base.get((p, r), 0)) for (p, r), n in head.items() if n > base.get((p, r), 0))


# --------------------------------------------------------------------------- check / update


def _prefix(config: dict) -> str:
    return "lint-ratchet({}): ".format(config["name"])


def _recovery(config: dict) -> str:
    return config.get("recovery_cmd") or "python3 {} {}".format(SCRIPT_REL, config["name"])


def _content_prefix(config: dict, exc) -> str:
    """The line prefix for an exit-2 error: the user scopes mark content-caused ones."""
    if config.get("repo_content") and isinstance(exc, ContentError):
        return _prefix(config) + REPO_CONTENT
    return _prefix(config)


def header_of(text):
    """The ``# toolchain:`` line of a baseline text, or None (unknown)."""
    match = re.search(r"(?:^|[\r\n])(" + re.escape(HEADER_PREFIX) + r"[^\r\n]*)", text or "")
    return match.group(1).strip() if match else None


def _pin_of(header):
    match = RULE_PIN_RE.search(header or "")
    return match.group(1) if match else None


def _version_key(version):
    return tuple(int(part) if part.isdigit() else 0 for part in re.split(r"[.]", version or ""))


def _older(live_header, stored_header) -> bool:
    """True when the baseline was written by a newer ruff than this plugin carries."""
    live_pin, stored_pin = _pin_of(live_header), _pin_of(stored_header)
    return bool(live_pin and stored_pin and _version_key(stored_pin) > _version_key(live_pin))


def _exempt(base_header, head_header, live_header) -> bool:
    """Growth is exempt only when the toolchain really changed since the merge base: the merge-base header
    differs from the working-tree header AND the working-tree header equals the live fingerprint. A plugin
    OLDER than the merge-base baseline's ruff never earns the exemption: that is skew, not a config change."""
    return bool(base_header and head_header and live_header and base_header != head_header
                and head_header == live_header and not _older(live_header, base_header))


def _baseline_file(root: Path, config: dict) -> Path:
    """The baseline path, refused when it, its directory or a parent is a symlink or when it is not a bounded
    regular file (it is read and rewritten; a FIFO would hang the tool)."""
    path = root / config["baseline"]
    current = root
    for part in Path(config["baseline"]).parts:
        current = current / part
        if current.is_symlink():
            raise ContentError("baseline {} is (or sits under) a symlink; refusing to read or write through "
                               "it".format(config["baseline"]))
    try:
        info = os.lstat(str(path))
    except FileNotFoundError:
        return path
    except OSError as exc:
        raise ContentError("could not stat baseline {}: {}".format(config["baseline"], exc.strerror or
                                                                   type(exc).__name__))
    if not stat.S_ISREG(info.st_mode):
        raise ContentError("baseline {} is not a regular file; refusing to read it".format(config["baseline"]))
    if info.st_size > MAX_BASELINE_BYTES:
        raise ContentError("baseline {} is over 16 MiB; refusing to read it".format(config["baseline"]))
    return path


def _read_baseline(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        raise ContentError("baseline {} is not valid UTF-8; take the base branch's copy of it and re-run "
                           "--update".format(path.name))
    except OSError as exc:
        raise ContentError("could not read baseline {}: {}".format(path.name, exc.strerror or type(exc).__name__))


def _write_baseline(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(dir=str(path.parent), prefix="{}.tmp-".format(path.name))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(text)
        # mkstemp makes the file 0600; a tracked file should carry the mode the user's umask gives a new file.
        umask = os.umask(0)
        os.umask(umask)
        os.chmod(tmp_name, 0o666 & ~umask)
        os.replace(tmp_name, str(path))
    finally:
        if os.path.lexists(tmp_name):
            os.unlink(tmp_name)


def _base_for(config, root, base, env) -> tuple:
    """``(sha | None, notes)``: the user scopes walk the ladder, the Soleur scopes use origin/main."""
    if config.get("ladder"):
        return resolve_base_ladder(root, base, env, baseline=config["baseline"])
    return resolve_base(root, base, env), []


def _delta(config, root, head_entries, head_text, base, env, out: list) -> tuple:
    """Return ``(exit_code, reason)``; ``reason`` says why the comparison did not run, or ``"compared"``."""
    ci = _is_ci(env)
    pre = _prefix(config)
    sha, notes = _base_for(config, root, base, env)
    out.extend(pre + note for note in notes)
    if sha is None:
        if ci:
            out.append(pre + "no merge base could be resolved under CI; refusing to skip the shrink-only comparison")
            return 2, "no-base"
        out.append(pre + "warning: merge base unresolvable here; the shrink-only comparison was skipped")
        return 0, "no-base"
    base_text = baseline_at(root, sha, config["baseline"], env)
    if base_text is None:
        script = config.get("script")
        base_script = baseline_at(root, sha, script, env) if (ci and script) else None
        if base_script is not None and re.search(r'"{}"\s*:\s*\{{'.format(re.escape(config["name"])), base_script):
            out.append(pre + "the baseline is missing at the merge base {} although the ratchet script there already "
                       "defines this scope: a baseline moved or renamed in this diff cannot be compared".format(
                           sha[:12]))
            return 2, "introduced"
        out.append(pre + "baseline introduced by this diff (absent at {}); shrink-only comparison skipped".format(
            sha[:12]))
        return 0, "introduced"
    if config.get("header"):
        if _exempt(header_of(base_text), header_of(head_text), config["header"](root)):
            out.append(pre + CONFIG_CHANGED + ": shrink-only not enforced; review the config diff")
            return 0, "config-changed"
    grew = growth(head_entries, parse_baseline(base_text), rename_map(root, sha, env))
    for path, rule, now, before in grew[:NOTICE_LIMIT]:
        out.append(pre + "baseline grew for {} [{}]: {} entries now, {} at the merge base".format(
            _clip(path), _clip(rule, 60), now, before))
    if len(grew) > NOTICE_LIMIT:
        out.append(pre + "... and {} more (path, rule) pairs grew".format(len(grew) - NOTICE_LIMIT))
    if grew:
        out.append(pre + "the baseline may only shrink; fix the finding instead of admitting it")
        if config.get("header") and _older(config["header"](root), header_of(base_text)):
            out.append(pre + "the baseline was written by a newer ruff ({}) than this plugin carries: update the "
                       "plugin before judging growth".format(_pin_of(header_of(base_text))))
        return 1, "compared"
    return 0, "compared"


def _more(pre: str, total: int, label: str, config: dict) -> list:
    """The pointer line after a capped class of report lines (an unbounded flood is read in full by the agent)."""
    if total <= NOTICE_LIMIT:
        return []
    return [pre + "... and {} more {} (the full list: `{} --list`)".format(
        total - NOTICE_LIMIT, label, _recovery(config))]


def check(config: dict, root, base=None, env=None) -> tuple:
    root = Path(root)
    pre = _prefix(config)
    out = []
    try:
        baseline_path = _baseline_file(root, config)
    except InfraError as exc:
        return 2, [_content_prefix(config, exc) + str(exc)]
    if not baseline_path.exists():
        return 2, [pre + "baseline {} is missing; create it with {} --update".format(
            config["baseline"], _recovery(config))]
    try:
        # A baseline the repository cannot be judged against is decided before any tool is provisioned or run.
        baseline_text = _read_baseline(baseline_path)
        baseline_entries = parse_baseline(baseline_text)
    except InfraError as exc:
        return 2, [_content_prefix(config, exc) + str(exc)]
    try:
        findings, file_count = config["run"](root)
    except Vacuous as exc:
        return 1, [pre + "vacuous scan: {}".format(exc)]
    except InfraError as exc:
        return 2, [_content_prefix(config, exc) + str(exc)]
    if file_count < config["floor"]:
        return 1, [pre + "the scan saw only {} files, below the floor of {}; a scan of (almost) nothing "
                   "cannot report green".format(file_count, config["floor"])]
    try:
        pairs = census_pairs(findings, root)
    except InfraError as exc:
        return 2, [_content_prefix(config, exc) + str(exc)]
    live = {entry: finding for entry, finding in pairs}
    known = set(baseline_entries)
    new = [entry for entry in sorted(live) if entry not in known]
    stale = [entry for entry in sorted(known) if entry not in live]
    changed_keys = {(e[0], e[1]) for e in new} & {(e[0], e[1]) for e in stale}
    new_lines, stale_lines = [], []
    for entry in new[:NOTICE_LIMIT]:
        finding = live[entry]
        new_lines.append(pre + "NEW {}:{} {} {}".format(_clip(finding.path), finding.row, _clip(finding.rule, 60),
                                                         _clip(finding.message)))
    for entry in stale[:NOTICE_LIMIT]:
        text = _clean(format_entry(_clip(entry[0]), _clip(entry[1], 60), entry[2], entry[3]))
        if (entry[0], entry[1]) in changed_keys:
            stale_lines.append(pre + "STALE {} -- a line carrying this finding changed; if the finding itself is "
                               "unchanged run `{} --update` (it refuses real growth)".format(text, _recovery(config)))
        else:
            stale_lines.append(pre + "STALE {} -- fixed: run `{} --update` and commit the baseline. After a merge "
                               "conflict take the base branch's copy of the baseline and re-run --update.".format(
                                   text, _recovery(config)))
    out.extend(new_lines + _more(pre, len(new), "NEW findings", config))
    out.extend(stale_lines + _more(pre, len(stale), "STALE entries", config))
    if new or stale:
        if new:
            out.append(pre + "remedy: " + config["remedy"])
            out.append(pre + config.get("waiver_note", WAIVER_NOTE_SOLEUR))
        return 1, out
    try:
        code, reason = _delta(config, root, list(live), baseline_text, base, env, out)
    except InfraError as exc:
        return 2, out + [_content_prefix(config, exc) + str(exc)]
    if code == 0 and config.get("header"):
        return _user_verdict(config, root, out, baseline_text, len(live), file_count, reason)
    if code == 0:
        out.append(pre + "OK ({} findings baselined, {} files scanned{})".format(
            len(live), file_count, "" if reason == "compared" else "; shrink-only comparison skipped"))
    return code, out


def _user_verdict(config, root, out, baseline_text, findings, file_count, reason) -> tuple:
    """User-mode green path: a WARN, never an OK, when the census was not compared or the toolchain moved. A
    baseline introduced by this diff is an OK whose second line says the shrink-only comparison starts at merge."""
    pre = _prefix(config)
    if reason == "config-changed":
        return 0, out
    live_header, stored = config["header"](root), header_of(baseline_text)
    stale = stored != live_header
    if stale:
        if _older(live_header, stored):
            out.append(pre + "plugin older than the baseline's ruff {}: update the plugin".format(_pin_of(stored)))
        else:
            out.append(pre + "fingerprint stale: run --update to refresh (ask the user first)")
    if file_count == 0:
        out.insert(0, "WARN " + pre + "no Python files were scanned (0 files in ruff's listing); nothing to ratchet. "
                   "If that is unexpected, check the exclude settings of your ruff configuration")
    elif reason == "no-base":
        out.insert(0, "WARN " + pre + "census matches the baseline ({} findings, {} files) but the shrink-only "
                   "comparison was not performed (no merge base)".format(findings, file_count))
    elif stale:
        out.insert(0, "WARN " + pre + "census matches the baseline ({} findings, {} files) but the ruff config or "
                   "pin changed since it was written, so shrink-only is not judged against the new toolchain until "
                   "the baseline is refreshed".format(findings, file_count))
    else:
        out.insert(0, pre + "OK ({} findings baselined, {} files scanned)".format(findings, file_count))
    return 0, out


def update(config: dict, root, base=None, env=None) -> tuple:
    root = Path(root)
    pre = _prefix(config)
    try:
        path = _baseline_file(root, config)
        findings, file_count = config["run"](root)
        if file_count < config["floor"]:
            return 1, [pre + "the scan saw only {} files, below the floor of {}; refusing to write a baseline from "
                       "a scan of (almost) nothing".format(file_count, config["floor"])]
        if config.get("header") and file_count == 0 and path.exists():
            return 1, [pre + "ruff listed no files, so --update would rewrite the baseline to 0 entries; check the "
                       "exclude settings of your ruff configuration (refusing)"]
        entries = census(findings, root)
        sha, _notes = _base_for(config, root, base, env)
        reference, exempt = None, False
        if sha is None and path.exists():
            return 2, [pre + "no merge base could be resolved, so the shrink-only guard cannot run; fetch "
                       "origin/main or pass --base <ref> (--base HEAD takes the committed baseline as the reference)"]
        if sha is None:
            # Deleting the baseline first must not lift the guard: the committed copy is the reference.
            if config.get("header") and _git(root, ["rev-parse", "--verify", "--quiet", "HEAD^{commit}"],
                                             env).returncode == 0:
                reference = baseline_at(root, "HEAD", config["baseline"], env)
        else:
            reference = baseline_at(root, sha, config["baseline"], env)
            if reference is not None and config.get("header"):
                live_header, base_header = config["header"](root), header_of(reference)
                if _older(live_header, base_header):
                    return 2, [pre + "plugin older than the baseline's ruff {}: update the plugin; not rewriting the "
                               "baseline with an older ruff".format(_pin_of(base_header))]
                # The same predicate check() applies once the live header is written.
                exempt = _exempt(base_header, live_header, live_header)
        if reference is not None and not exempt:
            grew = growth(entries, parse_baseline(reference), rename_map(root, sha or "HEAD", env))
            if grew:
                lines = [pre + "refusing to write: {} [{}] would hold {} entries, {} at the merge base".format(
                    _clip(p), _clip(r, 60), now, before) for p, r, now, before in grew[:NOTICE_LIMIT]]
                return 1, lines + [pre + "fix the new findings instead of baselining them"]
    except Vacuous as exc:
        return 1, [pre + "vacuous scan: {}".format(exc)]
    except InfraError as exc:
        return 2, [_content_prefix(config, exc) + str(exc)]
    header = config["header"](root) if config.get("header") else None
    try:
        _write_baseline(path, render_baseline(config["name"], entries,
                                              recovery=config.get("header_recovery") or _recovery(config), header=header))
    except OSError as exc:
        return 2, [_content_prefix(config, ContentError("")) + "could not write {}: {}".format(
            config["baseline"], exc.strerror or type(exc).__name__)]
    lines = [pre + "wrote {} entries to {}".format(len(entries), config["baseline"])]
    if config.get("header"):
        lines[0] += "; commit it"
        ignored = _git(root, ["check-ignore", "-q", "--", config["baseline"]], env)
        if ignored.returncode == 0:
            lines.append(pre + "{} is git-ignored, so it would never reach the base branch and the shrink-only "
                         "guard stays dark; remove the ignore rule (this tool never edits your .gitignore)".format(
                             config["baseline"]))
    return 0, lines


def list_live(config: dict, root) -> tuple:
    try:
        findings, _count = config["run"](Path(root))
    except Vacuous as exc:
        return 1, [_prefix(config) + "vacuous scan: {}".format(exc)]
    except InfraError as exc:
        return 2, [_content_prefix(config, exc) + str(exc)]
    lines = ["{}:{} {} {}".format(f.path, f.row, f.rule, f.message)
             for f in sorted(findings, key=lambda f: (f.path, f.row, f.rule))]
    return 0, lines


# --------------------------------------------------------------------------- tools


def tool_argv(name: str, root, files: list, ruff_path, user=False) -> list:
    if name == "ruff" and user:
        # The user's own configuration decides the rules and their waivers; --no-fix-only is load-bearing
        # because fix-only = true in a config otherwise rewrites the tree and hides the findings.
        return [str(ruff_path), "check", "--no-cache", "--no-fix", "--no-fix-only", "--force-exclude",
                "--output-format", "json", "--"] + list(files)
    if name == "ruff":
        return [str(ruff_path), "check", "--config", "ruff.toml", "--ignore-noqa", "--no-cache", "--no-fix",
                "--force-exclude", "--output-format", "json", "--"] + list(files)
    return [str(Path(root) / ESLINT_BIN), "--config", ESLINT_CONFIG, "--no-inline-config",
            "--no-error-on-unmatched-pattern", "-f", "json"] + list(SCOPES["eslint-test-dirs"]["scope"])


def show_files_argv(ruff_path, files: list, user=False) -> list:
    if user:
        return [str(ruff_path), "check", "--no-cache", "--force-exclude", "--show-files", "--"] + list(files)
    return [str(ruff_path), "check", "--config", "ruff.toml", "--no-cache", "--force-exclude", "--show-files",
            "--"] + list(files)


def run_ruff(root, env=None, ruff_path=None, run=subprocess.run) -> tuple:
    root = Path(root)
    files = [name for name in tracked_files(root, SCOPES["ruff"]["scope"], env)
             if (root / name).exists() and not (root / name).is_symlink()]
    if not files:
        raise Vacuous("no tracked Python files; refusing to invoke ruff (with no file arguments it lints the "
                      "current directory)")
    exe = ruff_path if ruff_path is not None else ensure_ruff(RUFF_REQUIREMENTS, env=dict(env or os.environ))
    listing = _exec(run, show_files_argv(exe, files), RUN_TIMEOUT, cwd=str(root), env=env)
    if listing.returncode != 0:
        raise InfraError("ruff --show-files failed (rc {}): {}".format(listing.returncode, listing.stderr.strip()[:300]))
    listed = {_relative(line.strip(), root) for line in listing.stdout.splitlines() if line.strip()}
    skipped = sorted(name for name in files if name not in listed and not set(Path(name).parts) & set(EXCLUDED_DIRS))
    if skipped:
        raise InfraError("ruff skipped {} tracked file(s) it was asked to lint (a default exclude such as dist/ or "
                         "venv/ matched): {}".format(len(skipped), ", ".join(_clean(n) for n in skipped[:5])))
    result = _exec(run, tool_argv("ruff", root, files, exe), RUN_TIMEOUT, cwd=str(root), env=env)
    if result.returncode not in (0, 1):
        raise InfraError("ruff exited {}: {}".format(result.returncode, result.stderr.strip()[:300]))
    failed = [line.strip() for line in result.stderr.splitlines() if "Failed to" in line]
    if failed:
        raise InfraError("ruff could not lint a file (a file it cannot read hides its findings): {}".format(
            _clean(failed[0])[:200]))
    return adapt_ruff(result.stdout, root), len(listed)


def run_eslint(root, env=None, run=subprocess.run) -> tuple:
    root = Path(root)
    binary = root / ESLINT_BIN
    if not binary.exists():
        raise InfraError("{} is missing; recover with: npm ci --ignore-scripts --prefix apps/web-platform".format(
            ESLINT_BIN))
    result = _exec(run, tool_argv("eslint-test-dirs", root, [], None), RUN_TIMEOUT, cwd=str(root), env=env)
    if result.returncode not in (0, 1):
        raise InfraError("eslint exited {}: {}".format(result.returncode, result.stderr.strip()[:300]))
    tracked = {n for n in tracked_files(root, (".",), env) if (root / n).exists() and not (root / n).is_symlink()}
    seen = set()
    findings, file_count = adapt_eslint(result.stdout, root, tracked, seen)
    scope = [":(glob)" + g for g in SCOPES["eslint-test-dirs"]["scope"]]
    expected = {n for n in tracked_files(root, scope, env)
                if n.endswith(ESLINT_EXTS) and "node_modules/" not in n and n in tracked}
    missing = sorted(expected - seen)
    if missing:
        raise InfraError("eslint did not report {} tracked in-scope file(s) (an ignore or config gap hides their "
                         "findings): {}".format(len(missing), ", ".join(_clean(n) for n in missing[:5])))
    return findings, file_count


# --------------------------------------------------------------------------- ruff provisioning


def requirements_pin(path) -> str:
    text = Path(path).read_text(encoding="utf-8")
    match = re.search(r"^ruff==([0-9][0-9A-Za-z.]*)", text, re.MULTILINE)
    if not match:
        raise InfraError("{} does not pin ruff==<version>".format(path))
    return match.group(1)


def pip_argv(target, requirements) -> list:
    return [sys.executable, "-I", "-m", "pip", "install", "--isolated", "--no-input", "--no-deps",
            "--disable-pip-version-check", "--index-url", "https://pypi.org/simple", "--only-binary=:all:",
            "--require-hashes", "--target", str(target), "-r", str(requirements), "--quiet"]


def pip_env(env) -> dict:
    return {k: v for k, v in dict(env).items() if not k.startswith(("PIP_", "PYTHON"))}


def _private_cache_dir(root):
    """Return ``root`` if it is a private directory of this user, creating it 0700; else None."""
    root = Path(root)
    try:
        try:
            info = os.lstat(str(root))
        except FileNotFoundError:
            root.parent.mkdir(parents=True, exist_ok=True)
            with contextlib.suppress(FileExistsError):
                os.mkdir(str(root), 0o700)
            info = os.lstat(str(root))
    except OSError:
        return None
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o022:
        return None
    return root


OFFLINE_STAMP = "offline-stamp"
OFFLINE_WINDOW = 600
STALE_INSTALL_AGE = 3600


def _sweep_installs(base: Path) -> None:
    """Remove ``install-*`` temp dirs an interrupted run left behind (up to ~24 MB each)."""
    now = time.time()
    for entry in base.glob("install-*"):
        with contextlib.suppress(OSError):
            if now - entry.stat().st_mtime > STALE_INSTALL_AGE:
                shutil.rmtree(str(entry), ignore_errors=True)


def ensure_ruff(requirements, env, run=subprocess.run, cache_root=None, fallback_root=None, recovery=None) -> Path:
    version = requirements_pin(requirements)
    recovery = recovery or "python3 {} ruff --check".format(SCRIPT_REL)
    env = dict(env)
    if not hasattr(os, "getuid"):
        raise InfraError("unsupported platform: this tool needs a POSIX system (native Windows is not supported)")
    if cache_root is None:
        xdg = env.get("XDG_CACHE_HOME")
        if xdg and not os.path.isabs(xdg):
            xdg = None  # a relative cache home would put the install under the caller's working directory
        home = xdg or os.path.join(env.get("HOME") or os.path.expanduser("~"), ".cache")
        # A directory of our own: the shared `soleur` cache dir is created by other tools under the
        # user's umask and is often group-writable, which this check (rightly) refuses.
        cache_root = Path(home) / "soleur-lint-ratchet"
    if fallback_root is None:
        fallback_root = Path(tempfile.gettempdir()) / "soleur-lint-ratchet-{}".format(os.getuid())
    base = _private_cache_dir(cache_root) or _private_cache_dir(fallback_root)
    if base is None:
        raise InfraError("no private cache directory is usable for ruff ({} and {} are not owned by this user with "
                         "mode 0700)".format(cache_root, fallback_root))
    digest = hashlib.sha256(Path(requirements).read_bytes()).hexdigest()[:12]
    final = base / "ruff-{}-{}-{}".format(digest, sys.platform, platform.machine() or "unknown")
    exe = final / "bin" / "ruff"
    if not exe.exists():
        stamp = base / OFFLINE_STAMP
        if not _is_ci(env) and stamp.exists() and time.time() - stamp.stat().st_mtime < OFFLINE_WINDOW:
            raise Skip("ruff could not be installed (the package index was unreachable moments ago; not retrying "
                       "for {} minutes, or delete {} to retry now); recover with: {}".format(
                           OFFLINE_WINDOW // 60, shlex.quote(str(stamp)), recovery))
        _sweep_installs(base)
        print("lint-ratchet: installing ruff {} (first run only)".format(version), file=sys.stderr)
        target = Path(tempfile.mkdtemp(prefix="install-", dir=str(base)))
        argv = pip_argv(target, requirements)
        if not _is_ci(env):
            # Bounded locally: an unreachable index must cost seconds, not pip's default ~100 s of retries.
            argv = list(argv) + ["--retries", "1", "--timeout", "15"]
        try:
            result = _exec(run, argv, PIP_TIMEOUT, label="pip", env=pip_env(env))
        except InfraError:
            shutil.rmtree(str(target), ignore_errors=True)
            raise
        if result.returncode != 0:
            shutil.rmtree(str(target), ignore_errors=True)
            output = "{}\n{}".format(result.stdout or "", result.stderr or "")
            if any(marker in output for marker in PIP_INTEGRITY_MARKERS):
                raise InfraError("ruff install failed an integrity check: {}".format(output.strip()[-300:]))
            reason = output.strip().splitlines()[-1][:200] if output.strip() else "pip exited {}".format(
                result.returncode)
            if _is_ci(env):
                raise InfraError("ruff could not be installed under CI: {}".format(reason))
            if any(marker in output for marker in PIP_NETWORK_MARKERS):
                with contextlib.suppress(OSError):
                    stamp.touch()
                raise Skip("ruff could not be installed ({}); recover with: {}".format(reason, recovery))
            if "No module named pip" in output:
                raise InfraError("pip is not available for {}: install it (python3-pip) or run from a virtualenv".format(
                    sys.executable))
            raise InfraError("ruff install failed for an unrecognised reason: {}".format(reason))
        try:
            os.rename(str(target), str(final))
        except OSError:
            if not final.exists():
                raise
            shutil.rmtree(str(target), ignore_errors=True)
    if not exe.exists():
        raise InfraError("ruff cache {} exists without bin/ruff; delete it and retry: rm -rf {}".format(final, final))
    probe = _exec(run, [str(exe), "--version"], 60)
    if probe.stdout.strip() != "ruff {}".format(version):
        raise InfraError("installed ruff ({}) reports {!r}, the pin is {!r}; delete {} and retry: rm -rf {}".format(
            exe, probe.stdout.strip(), "ruff " + version, final, final))
    return exe


# --------------------------------------------------------------------------- user scopes (PR3b)


class UserState(NamedTuple):
    kind: str
    code: int
    lines: list
    warnings: list


def user_env(env) -> dict:
    """The environment every user-mode child sees: no variable that redirects git to another repository or
    changes how a pathspec is read, and git's messages in English (the skip classification reads them)."""
    cleaned = {k: v for k, v in dict(env).items() if k not in GIT_SCRUB}
    cleaned["LC_ALL"] = "C"
    cleaned["LANGUAGE"] = "C"
    cleaned["GIT_NO_REPLACE_OBJECTS"] = "1"  # refs/replace/* is repository content; never let it rewrite history we judge
    return cleaned


def resolve_root(env=None) -> Path:
    """The toplevel of the repository the CALLER stands in. Not a repository is a ``Skip``."""
    pinned = user_env(env if env is not None else os.environ)
    result = _exec(subprocess.run, ["git", "-c", "core.fsmonitor=false", "rev-parse", "--show-toplevel"], GIT_TIMEOUT,
                   label="git", env=pinned)
    if result.returncode != 0:
        message = result.stderr.strip()
        if message.startswith("fatal: not a git repository"):
            raise Skip("not a git repository")
        if message.startswith("fatal: this operation must be run in a work tree"):
            raise InfraError("this is a bare repository; run lint-ratchet from a worktree of it")
        raise InfraError("git rev-parse --show-toplevel failed: {}".format(_clip(message)))
    return Path(result.stdout.strip())


def _config_files(root, problems=None) -> dict:
    """Existing ruff config candidates at the repository root (name -> text).

    An unsafe one (symlink, not a regular file, over 1 MiB, unreadable) raises ``ContentError``, or is appended
    to ``problems`` and skipped when a list is given so the caller can decide whether it matters.
    """
    found = {}
    for name in USER_RUFF_CONFIGS + (USER_PYPROJECT,):
        path = Path(root) / name
        if not os.path.lexists(str(path)):
            continue
        try:
            try:
                info = os.lstat(str(path))
                if stat.S_ISLNK(info.st_mode) or not stat.S_ISREG(info.st_mode):
                    raise ContentError("{} is a symlink or not a regular file; refusing to run ruff against "
                                       "it".format(name))
                if info.st_size > MAX_CONFIG_BYTES:
                    raise ContentError("{} is over 1 MiB; refusing to run ruff against it".format(name))
                found[name] = path.read_text(encoding="utf-8", errors="replace")
            except OSError as exc:
                raise ContentError("could not read {}: {}".format(name, exc.strerror or type(exc).__name__))
        except ContentError as exc:
            if problems is None:
                raise
            problems.append(str(exc))
    return found


# A table header, tolerating the TOML spellings a hand-written file uses: inner spaces, quoted keys.
_RUFF_HEADER_RE = re.compile(r"""^[ \t]*\[\[?[ \t]*["']?tool["']?[ \t]*\.[ \t]*["']?ruff["']?(?=[ \t.\]"'])""",
                             re.MULTILINE)
_TABLE_HEADER_RE = re.compile(r"^[ \t]*\[\[?[^\[\]\n]*\]\]?[ \t]*(#.*)?$")


def _has_ruff_table(text: str) -> bool:
    return _RUFF_HEADER_RE.search(text) is not None


def _ruff_tables(text: str) -> str:
    """The ``[tool.ruff*]`` tables of a pyproject.toml, header lines and bodies."""
    keep, out = False, []
    for line in LINE_SPLIT_RE.split(text):
        if _TABLE_HEADER_RE.match(line):
            keep = _RUFF_HEADER_RE.match(line) is not None
        if keep:
            out.append(line)
    return "\n".join(out).rstrip("\n")


CONFIG_GLOBS = tuple(":(glob)**/" + name for name in USER_RUFF_CONFIGS + (USER_PYPROJECT,))


def _tracked_configs(root, env=None) -> dict:
    """Every TRACKED ruff config, root and nested, as ``path -> text``: ruff applies the nearest one to each
    file, so a nested one decides findings the root one never sees. A pyproject.toml counts only through its
    ``[tool.ruff*]`` tables. A nested symlink contributes its target name only."""
    configs = {}
    for name in tracked_files(root, CONFIG_GLOBS, env):
        path = Path(root) / name
        nested = "/" in name
        if not os.path.lexists(str(path)):
            continue  # tracked but deleted in the tree: it contributes nothing to the live toolchain
        try:
            info = os.lstat(str(path))
        except OSError as exc:
            raise ContentError("could not stat {}: {}".format(name, exc.strerror or type(exc).__name__))
        if stat.S_ISLNK(info.st_mode):
            if not nested:
                raise ContentError("{} is a symlink or not a regular file; refusing to run ruff against it".format(
                    name))
            content = "symlink:" + os.readlink(str(path))
            # A dangling or oversized target contributes its link text only; ruff would fail on it and say so.
            if os.path.isfile(str(path)) and os.path.getsize(str(path)) <= MAX_CONFIG_BYTES:
                try:
                    content += "\0" + Path(os.path.realpath(str(path))).read_text(encoding="utf-8", errors="replace")
                except OSError as exc:
                    raise ContentError("could not read {}: {}".format(_clip(name), exc.strerror or type(exc).__name__))
            configs[name] = content
            continue
        if not stat.S_ISREG(info.st_mode):
            raise ContentError("{} is not a regular file; refusing to run ruff against it".format(_clip(name)))
        if info.st_size > MAX_CONFIG_BYTES:
            # An oversized pyproject.toml matters only if it carries a ruff table; look at its head, not all of it.
            with open(str(path), "rb") as handle:
                head = handle.read(MAX_CONFIG_BYTES).decode("utf-8", "replace")
            if name.rsplit("/", 1)[-1] == USER_PYPROJECT and not _has_ruff_table(head):
                continue
            raise ContentError("{} is over 1 MiB; refusing to run ruff against it".format(_clip(name)))
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError as exc:
            raise ContentError("could not read {}: {}".format(name, exc.strerror or type(exc).__name__))
        if name.rsplit("/", 1)[-1] == USER_PYPROJECT:
            if not _has_ruff_table(text):
                continue
            text = _ruff_tables(text)
        configs[name] = text
    return configs


def toolchain_header(root, env=None) -> str:
    """The baseline header line: the pinned ruff plus a hash of every tracked ruff configuration."""
    digest = hashlib.sha256()
    configs = _tracked_configs(root, env)
    for name in sorted(configs):
        digest.update(name.encode("utf-8", "replace") + b"\0" + configs[name].encode("utf-8", "replace") + b"\0")
    return "{}ruff {} ; config sha256:{}".format(HEADER_PREFIX, requirements_pin(RUFF_REQUIREMENTS),
                                               digest.hexdigest()[:16])


def _script_cmd(scope: str, mode: str) -> str:
    return "python3 {} {} {}".format(shlex.quote(str(Path(__file__).resolve())), scope, mode)


def _is_soleur_checkout(root) -> bool:
    """True only when the RUNNING script is the very file inside this repository's plugin tree, reached with
    no symlink on the way: a symlink a pull request plants at the script path must not switch the ratchet off."""
    top = os.path.realpath(str(root))
    current = top
    for part in Path(SCRIPT_REL).parts:
        current = os.path.join(current, part)
        if os.path.islink(current):
            return False
    return os.path.realpath(__file__) == os.path.join(top, SCRIPT_REL)


def _is_untracked_ruff_config(root, name) -> bool:
    base = name.rsplit("/", 1)[-1]
    if base in USER_RUFF_CONFIGS:
        return True
    if base != USER_PYPROJECT:
        return False
    try:
        with open(str(Path(root) / name), "rb") as handle:
            return _has_ruff_table(handle.read(MAX_CONFIG_BYTES).decode("utf-8", "replace"))
    except OSError:
        return False


def _scan_notices(root, env, pre) -> list:
    """What an OK would otherwise hide: tracked .py symlinks and untracked .py files are not scanned."""
    notices = []
    links = [n for n in tracked_files(root, USER_PY_PATHSPECS, env) if (Path(root) / n).is_symlink()]
    if links:
        notices.append(pre + "WARN: {} tracked .py symlink(s) are not scanned: {}".format(
            len(links), ", ".join(_clip(n, 80) for n in links[:3])))
    others = _git(root, ["ls-files", "-z", "--others", "--exclude-standard", "--"] + list(USER_PY_PATHSPECS)
                  + list(CONFIG_GLOBS), env)
    if others.returncode == 0:
        names = [n for n in others.stdout.split("\0") if n]
        configs = [n for n in names if _is_untracked_ruff_config(root, n)]
        python = [n for n in names if n.rsplit("/", 1)[-1] not in USER_RUFF_CONFIGS + (USER_PYPROJECT,)]
        if python:
            notices.append(pre + "WARN: {} untracked .py file(s) are not scanned until they are added to git: "
                           "{}".format(len(python), ", ".join(_clip(n, 80) for n in python[:3])))
        if configs:
            notices.append(pre + "WARN: {} untracked ruff config(s) apply here but not in CI or in the fingerprint: "
                           "{}".format(len(configs), ", ".join(_clip(n, 80) for n in configs[:3])))
    return notices


UNADOPT = ("restore it, or un-adopt on purpose with git rm -r .lint-ratchet (this check stays red on that branch "
           "until the deletion merges)")


def classify_user(root, base, env) -> UserState:
    """Decide the user-mode state without running or provisioning ruff; used by every user verb."""
    root = Path(root)
    pre = "lint-ratchet(user-ruff): "
    if _is_soleur_checkout(root):
        return UserState("SOLEUR", 0, ["lint-ratchet: Soleur repository: scopes run via lefthook and CI; nothing to "
                                       "ratchet here"], [])
    problems = []
    files = _config_files(root, problems)
    tracked = set(tracked_files(root, USER_RUFF_CONFIGS + (USER_PYPROJECT,), env))
    has_config = any(name in tracked for name in USER_RUFF_CONFIGS if name in files) or (
        USER_PYPROJECT in tracked and USER_PYPROJECT in files and _has_ruff_table(files[USER_PYPROJECT]))
    unsafe_baseline = None
    try:
        baseline_path = _baseline_file(root, {"baseline": USER_BASELINE})
    except ContentError as exc:
        baseline_path, unsafe_baseline = None, exc
    in_tree = baseline_path is not None and baseline_path.exists()
    head_ok = _git(root, ["rev-parse", "--verify", "--quiet", "HEAD^{commit}"], env).returncode == 0
    head_text = baseline_at(root, "HEAD", USER_BASELINE, env) if head_ok else None
    sha, notes = resolve_base_ladder(root, base, env, baseline=USER_BASELINE)
    notes = [pre + note for note in notes]
    base_text = baseline_at(root, sha, USER_BASELINE, env) if sha else None
    anywhere = in_tree or head_text is not None or base_text is not None
    # A repository that never opted in pays nothing, so an unsafe file only matters once a baseline exists
    # (or a config is in play): then it is a defect of the repository, exit 2.
    if unsafe_baseline is not None and anywhere:
        raise unsafe_baseline
    if problems and anywhere:
        raise ContentError(problems[0])
    if not has_config:
        if anywhere:
            return UserState("BASELINE_WITHOUT_CONFIG", 1, [
                pre + "baseline exists but no ruff config detected (no tracked ruff config at {}; nested configs "
                "unsupported): restore the config, or un-adopt on purpose with git rm -r .lint-ratchet".format(root)],
                [])
        return UserState("NO_LINTER", 0, ["lint-ratchet: no linter configured (no tracked ruff config at {}; nested "
                                          "configs unsupported); nothing to ratchet".format(root)],
                         [pre + problem for problem in problems])
    if not in_tree and base_text is not None:
        return UserState("DELETED", 1, [pre + "baseline deleted since the merge base: " + UNADOPT], [])
    if not in_tree and head_text is not None:
        if sha is not None:
            return UserState("DELETED", 1, [pre + "baseline deleted from the working tree (it is committed at HEAD): "
                                            + UNADOPT], [])
        text = ("baseline is committed at HEAD but missing from the working tree, and no merge base could be "
                "resolved: cannot tell a deletion from an un-adoption; " + UNADOPT)
        if _is_ci(env):
            return UserState("UNVERIFIED", 2, [pre + text], list(notes))
        return UserState("UNVERIFIED", 0, ["WARN " + pre + text], list(notes))
    if not in_tree:
        if sha is None and _is_ci(env):
            return UserState("UNVERIFIED", 2, [
                pre + "no merge base could be resolved under CI, so a repository that never adopted cannot be told "
                "from one whose baseline this change deleted: fetch more history (fetch-depth: 0)"], list(notes))
        warnings = list(notes) + [pre + problem for problem in problems]
        if unsafe_baseline is not None:
            warnings.append(pre + str(unsafe_baseline))
        if sha is None:
            warnings.append(pre + "base unresolvable: baseline-deletion check not performed")
        return UserState("NOT_ADOPTED", 0, [pre + "not adopted. Ask the user whether to adopt (it installs a pinned "
                                            "ruff, writes .lint-ratchet/ruff.baseline.txt for the current findings, "
                                            "and new findings then block; do not adopt in an unattended run); if "
                                            "yes, run: " + _script_cmd("user-ruff", "--update")], warnings)
    if sha is None and _is_ci(env):
        return UserState("UNVERIFIED", 2, [pre + "no merge base could be resolved under CI; refusing to skip the "
                                           "shrink-only comparison"], list(notes))
    warnings = []
    if _git(root, ["ls-files", "--error-unmatch", "--", USER_BASELINE], env).returncode != 0:
        if _git(root, ["check-ignore", "-q", "--", USER_BASELINE], env).returncode == 0:
            warnings.append(pre + "the baseline is git-ignored, so it never reaches the base branch and the "
                            "shrink-only guard stays dark: remove the ignore rule (git add would refuse it)")
        else:
            warnings.append(pre + "the baseline is not tracked yet: git add .lint-ratchet and commit it")
    return UserState("ADOPTED", 0, [], warnings + _scan_notices(root, env, pre))


def _ruff_failure(label: str, result, exe=None) -> ContentError:
    """A ruff exit 2 in user mode. Only the first stderr line is echoed (normally the literal ``ruff failed``):
    the lines after it quote the failing file, and an ``extend`` can point anywhere on the machine."""
    first = next((line.strip() for line in result.stderr.splitlines() if line.strip()), "")
    text = "{} exited {}: {}".format(label, result.returncode, _clip(first) or "(no message)")
    if first.lower().startswith("ruff failed"):
        text += "; the detail lines are not echoed (an extend can point at any file): run `{} check --no-cache " \
                "--show-settings` in the repository to see them".format(shlex.quote(str(exe)) if exe else "ruff")
    if PIN_HINT_RE.search(result.stderr):
        text += ("; pinned ruff is {}: this is a typo in your config, or a setting newer than the pin".format(
            requirements_pin(RUFF_REQUIREMENTS)))
    return ContentError(text)


def _chunks(files: list, budget=None):
    """Split a file list so no single ruff launch exceeds the platform's argument-size limit."""
    budget = budget or ARGV_BUDGET
    chunk, size = [], 0
    for name in files:
        weight = len(name.encode("utf-8", "replace")) + 1
        if chunk and size + weight > budget:
            yield chunk
            chunk, size = [], 0
        chunk.append(name)
        size += weight
    if chunk:
        yield chunk


def run_user_ruff(root, env=None, ruff_path=None, run=subprocess.run) -> tuple:
    """The census of the user's own ruff findings. The totality checks are in ADR-290 Amendment 1."""
    root = Path(root)
    _config_files(root)  # an unsafe config is refused before any ruff is provisioned
    files = []
    for name in tracked_files(root, USER_PY_PATHSPECS, env):
        if "\ufffd" in name:
            raise ContentError("a tracked file has a name that is not valid UTF-8 ({!r}); it cannot be scanned or "
                               "baselined, rename it".format(_clip(name)))
        if (root / name).exists() and not (root / name).is_symlink():
            files.append(name)
    if not files:
        return [], 0
    base_env = dict(env if env is not None else os.environ)
    exe = ruff_path if ruff_path is not None else ensure_ruff(
        RUFF_REQUIREMENTS, env=dict(base_env), recovery=_script_cmd("user-ruff", "--check"))
    ruff_env = {k: v for k, v in base_env.items() if not k.startswith(("RUFF_", "PYTHON"))}
    deadline = time.monotonic() + TOTAL_RUN_BUDGET

    def launch_timeout() -> float:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise InfraError("ruff exceeded the total budget of {} s across its chunked launches".format(
                TOTAL_RUN_BUDGET))
        return min(RUN_TIMEOUT, remaining)

    listed = set()
    for chunk in _chunks(files):
        listing = _exec(run, show_files_argv(exe, chunk, user=True), launch_timeout(), cwd=str(root), env=ruff_env)
        if listing.returncode != 0:
            raise _ruff_failure("ruff --show-files", listing, exe)
        listed.update(_relative(line.strip(), root) for line in listing.stdout.splitlines() if line.strip())
    if not listed:
        return [], 0
    findings = []
    for chunk in _chunks(files):
        result = _exec(run, tool_argv("ruff", root, chunk, exe, user=True), launch_timeout(), cwd=str(root),
                       env=ruff_env)
        if result.returncode not in (0, 1):
            raise _ruff_failure("ruff", result, exe)
        failed = [line.strip() for line in result.stderr.splitlines() if "Failed to" in line]
        if failed:
            raise ContentError("ruff could not lint a file (a file it cannot read hides its findings): {}".format(
                _clip(failed[0])))
        findings.extend(adapt_ruff(result.stdout, root))
    return findings, len(listed)


def build_user_config(env) -> dict:
    return {
        "name": "user-ruff", "baseline": USER_BASELINE, "floor": 0, "run": lambda root: run_user_ruff(root, env),
        "remedy": REMEDY_USER, "waiver_note": WAIVER_NOTE_USER,
        "ladder": True, "header": lambda root: toolchain_header(root, env), "repo_content": True,
        "recovery_cmd": "python3 {} user-ruff".format(shlex.quote(str(Path(__file__).resolve()))),
        "header_recovery": 'python3 "${CLAUDE_PLUGIN_ROOT}/scripts/lint-ratchet.py" user-ruff',
    }


# --------------------------------------------------------------------------- CLI


def build_config(name: str, env) -> dict:
    own = REPO_ROOT / SCRIPT_REL if REPO_ROOT is not None else None
    if own is None or not own.exists() or not own.samefile(Path(__file__)):
        raise InfraError("the {} scope runs only from the Soleur repository checkout ({} is not it); user "
                         "repositories use the user-ruff or auto scope".format(name, REPO_ROOT))
    runner = (lambda root: run_ruff(root, env)) if name == "ruff" else (lambda root: run_eslint(root, env))
    return dict(SCOPES[name], name=name, run=runner, script=SCRIPT_REL)


def _emit(code: int, lines: list, warnings: list, scope: str) -> int:
    """Print the report: warnings to stderr, then the lines to stdout (exit 0) or stderr. Never exits 120."""
    stream = sys.stdout if code == 0 else sys.stderr
    try:
        for line in warnings:
            print(_clip(line, LINE_LIMIT), file=sys.stderr)
        for line in lines:
            text = _clip(line, LINE_LIMIT)
            # A tracked path can start a --list line; never let it read as a workflow command.
            print((" " + text) if text.startswith(("::", "##[")) else text, file=stream)
        sys.stdout.flush()
        sys.stderr.flush()
    except OSError as exc:
        with contextlib.suppress(OSError):
            print(_clean("lint-ratchet({}): could not write the report: {}".format(scope, exc)), file=sys.stderr)
        return 2
    return code


def main_user(args, env) -> int:
    """The user scopes: ``user-ruff`` (--check, --update, --list) and ``auto`` (check only)."""
    scope = args.scope
    verb = "update" if args.update else "list" if args.list else "check"
    pre = "lint-ratchet({}): ".format(scope)
    env = user_env(env)
    try:
        root = resolve_root(env)
        state = classify_user(root, args.base, env)
        if state.kind == "SOLEUR" or (verb == "check" and state.kind != "ADOPTED"):
            return _emit(state.code, state.lines, state.warnings, scope)
        if state.kind in ("NO_LINTER", "BASELINE_WITHOUT_CONFIG"):
            return _emit(2, [pre + "cannot --{}: no usable tracked ruff config at {}".format(verb, root)], [], scope)
        config = build_user_config(env)
        if verb == "update":
            code, lines = update(config, root, base=args.base, env=env)
        elif verb == "list":
            code, lines = list_live(config, root)
        else:
            code, lines = check(config, root, base=args.base, env=env)
        return _emit(code, lines, state.warnings, scope)
    except Skip as exc:
        if verb == "check":
            print(_clean("SKIP lint-ratchet({}): no scan was performed ({}); no ratchet protection this run".format(
                scope, exc)))
            return 0
        print(_clean(pre + "{} -- cannot --{}".format(exc, verb)), file=sys.stderr)
        return 2
    except InfraError as exc:
        prefix = REPO_CONTENT if isinstance(exc, ContentError) else ""
        print(_clip(pre + prefix + str(exc), LINE_LIMIT), file=sys.stderr)
        return 2
    except Exception as exc:  # the documented contract: nothing unexpected exits 1
        print(_clip(pre + "unexpected {}: {}".format(type(exc).__name__, exc), LINE_LIMIT), file=sys.stderr)
        return 2


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description="Shrink-only lint ratchet (see the module docstring).")
    parser.add_argument("scope", choices=sorted(SCOPES) + list(USER_SCOPES))
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--check", action="store_true", help="verify the live tree against the baseline (default)")
    mode.add_argument("--update", action="store_true", help="rewrite the baseline from the live census (never grows it)")
    mode.add_argument("--list", action="store_true", help="print the live findings")
    parser.add_argument("--base", help="ref to compare the baseline against (default: merge-base with origin/main)")
    args = parser.parse_args(argv)
    env = dict(os.environ)
    if args.scope == "auto" and (args.update or args.list):
        parser.error("auto accepts only --check and --base")
    if args.scope in USER_SCOPES:
        return main_user(args, env)
    verb = "update" if args.update else "list" if args.list else "check"
    try:
        config = build_config(args.scope, env)
        if args.update:
            code, lines = update(config, REPO_ROOT, base=args.base, env=env)
        elif args.list:
            code, lines = list_live(config, REPO_ROOT)
        else:
            code, lines = check(config, REPO_ROOT, base=args.base, env=env)
    except Skip as exc:
        if verb == "check":
            print(_clean("SKIP lint-ratchet({}): {}".format(args.scope, exc)))
            return 0
        print(_clean("lint-ratchet({}): {} -- cannot --{}".format(args.scope, exc, verb)), file=sys.stderr)
        return 2
    except InfraError as exc:
        print(_clip("lint-ratchet({}): {}".format(args.scope, exc), LINE_LIMIT), file=sys.stderr)
        return 2
    except Exception as exc:  # the documented contract: nothing unexpected exits 1
        print(_clip("lint-ratchet({}): unexpected {}: {}".format(args.scope, type(exc).__name__, exc), LINE_LIMIT),
              file=sys.stderr)
        return 2
    return _emit(code, lines, [], args.scope)


if __name__ == "__main__":
    sys.exit(main())
