#!/usr/bin/env python3
"""Shrink-only lint ratchet: ruff over tracked Python, eslint no-unused-vars over test dirs.

    python3 scripts/lint-ratchet.py <scope> [--check | --update | --list] [--base <ref>]

Scopes: ``ruff`` and ``eslint-test-dirs`` (see SCOPES). Design record: ADR-290; tracker #10331.

A baseline file lists the findings that existed when the scope was introduced. Each entry is
``path|rule|anchor|n``: ``anchor`` is a 12-hex fingerprint of the whitespace-normalised source line
of the finding (the line text is never stored) and ``n`` the 1-based ordinal among identical
``(path, rule, anchor)`` triples, so two identical lines are two entries. ``--check`` enforces

1. the baseline file exists (and is neither a symlink nor carries duplicate lines),
2. the tool ran and its report parsed, and every tracked in-scope file was actually scanned
   (a tracked file the tool silently skipped is a failure, not a smaller census),
3. the scan saw enough files (a floor per scope), so a scan of nothing cannot read as green,
4. the baseline EQUALS the live census: a new finding fails, and so does a stale entry,
5. per ``(path, rule)`` the baseline never holds more entries than at the merge base, after
   applying ``git diff -M`` renames, so the baseline can only shrink.

Exit codes: 0 clean; 1 drift or vacuity; 2 infrastructure (tool missing or crashed, unparsable
output, hash mismatch, baseline absent or unsafe, no merge base under ``CI``, any unexpected error).

Counting is waiver-proof (ruff ``--ignore-noqa``, eslint ``--no-inline-config``) and no tool is
ever run in a fix mode: the files under scan include test fixtures that are test INPUT.

Library contract (PR3b): ``check(config, root, base, env)`` takes a plain dict with ``name``,
``baseline``, ``floor``, ``run`` (``run(root) -> (findings, file_count)``, may raise ``Vacuous``,
``InfraError`` or ``Skip``), ``remedy``, ``drawdown``, and optionally ``script`` and
``recovery_cmd``. ``Skip`` propagates to the caller.

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
import shutil
import stat
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import NamedTuple

REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT_REL = "scripts/lint-ratchet.py"
RUFF_REQUIREMENTS = REPO_ROOT / "scripts" / "ruff-requirements.txt"
ESLINT_CONFIG = "apps/web-platform/eslint.test-dirs.config.mjs"
ESLINT_BIN = "apps/web-platform/node_modules/.bin/eslint"
ESLINT_EXTS = (".js", ".mjs", ".cjs", ".jsx", ".ts", ".tsx", ".mts", ".cts")
# Tracked Python that ruff.toml (extend-exclude) deliberately does not scan; anything else a
# tracked file is missing from ruff's own file list for is a silent skip and fails the scan.
EXCLUDED_PREFIXES = ("knowledge-base/",)
DRAWDOWN = "#10433"

GIT_TIMEOUT = 120
RUN_TIMEOUT = 900
PIP_TIMEOUT = 300

ENTRY_RE = re.compile(r"^([^|]+)\|([^|]+)\|([0-9a-f]{12})\|([0-9]+)$")
LINE_SPLIT_RE = re.compile(r"\r\n|\r|\n")
CONTROL_RE = re.compile("[\x00-\x1f\x7f-\x9f  ]")
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
)

REMEDY_RUFF = (
    "fix the code: SIM115 use a context manager (with open(...)), S110/S112 handle or log the "
    "exception instead of passing, F401 remove the import, F841 use the value or prefix it with _"
)
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


def _exec(run, argv, timeout, **kwargs):
    """Run a child process with a bound, UTF-8 text capture, mapping spawn failures to InfraError."""
    kwargs.setdefault("capture_output", True)
    kwargs.setdefault("encoding", "utf-8")
    kwargs.setdefault("errors", "replace")
    name = Path(str(argv[0])).name
    try:
        return run(argv, timeout=timeout, **kwargs)
    except subprocess.TimeoutExpired:
        raise InfraError("{} timed out after {}s".format(name, timeout))
    except OSError as exc:
        raise InfraError("could not run {}: {}".format(name, exc))


def _clean(text: str) -> str:
    """Strip terminal control characters from anything echoed from a file name or tool message."""
    return CONTROL_RE.sub(" ", text)


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
            raise InfraError("baseline line {} is a merge-conflict marker: take the base branch's copy of the "
                             "baseline and re-run --update".format(number))
        match = ENTRY_RE.match(line)
        if not match:
            raise InfraError("baseline line {} is not 'path|rule|anchor|n': {!r}".format(number, line[:80]))
        entry = (match.group(1), match.group(2), match.group(3), int(match.group(4)))
        if entry in seen:
            raise InfraError("baseline line {} duplicates an earlier entry: {!r}".format(number, line[:80]))
        seen.add(entry)
        entries.append(entry)
    return entries


def render_baseline(name: str, entries: list, drawdown: str) -> str:
    header = [
        "# lint-ratchet baseline for scope '{}' (PR3a of #10331; design in ADR-290).".format(name),
        "# Shrink-only: this file always equals the live census, and per (path, rule) it may never",
        "# hold more entries than the merge base. Entry: path|rule|anchor|n, where anchor is a 12-hex",
        "# fingerprint of the normalised source line (the line itself is never stored).",
        "# List the live findings:  python3 scripts/lint-ratchet.py {} --list".format(name),
        "# After fixing findings:   python3 scripts/lint-ratchet.py {} --update  (it refuses to add)".format(name),
        "# After a merge conflict, take the base branch's copy of this file and re-run --update.",
        "# Drawdown tracking: {}".format(drawdown),
    ]
    body = [format_entry(*entry) for entry in sorted(entries)]
    return "\n".join(header + body) + "\n"


def _check_path(path: str) -> None:
    if "|" in path or "\n" in path or "\r" in path:
        raise InfraError("path {!r} contains '|' or a newline; the baseline format cannot carry it".format(path))


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
    for base in (str(root), os.path.realpath(str(root))):
        rel = os.path.relpath(filename, base)
        if rel != ".." and not rel.startswith(".." + os.sep):
            return rel
    raise InfraError("tool reported a path outside the repository: {!r}".format(filename))


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
                raise InfraError("ruff could not parse {} ({}); a file that did not parse hides its findings".format(
                    path, item.get("message", "syntax error")))
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
    return _exec(subprocess.run, ["git", "-C", str(root)] + list(args), GIT_TIMEOUT, env=env)


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


def rename_map(root, sha: str, env=None) -> dict:
    """Map old -> new for renames between ``sha`` and the working tree (staged renames included)."""
    result = _git(root, ["diff", "-M30%", "-z", "--name-status", "--diff-filter=R", sha, "--"], env)
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


def _baseline_file(root: Path, config: dict) -> Path:
    """The baseline path, refused when it or its directory is a symlink (it is read and rewritten)."""
    path = root / config["baseline"]
    if path.is_symlink() or path.parent.is_symlink():
        raise InfraError("baseline {} is (or sits under) a symlink; refusing to read or write through it".format(
            config["baseline"]))
    return path


def _write_baseline(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name("{}.tmp-{}".format(path.name, os.getpid()))
    try:
        tmp.write_text(text, encoding="utf-8")
        os.replace(str(tmp), str(path))
    finally:
        if tmp.exists():
            tmp.unlink()


def _delta(config, root, head_entries, base, env, out: list) -> tuple:
    """Return ``(exit_code, compared)``; ``compared`` is False when the comparison did not run."""
    ci = _is_ci(env)
    pre = _prefix(config)
    sha = resolve_base(root, base, env)
    if sha is None:
        if ci:
            out.append(pre + "no merge base could be resolved under CI; refusing to skip the shrink-only comparison")
            return 2, False
        out.append(pre + "warning: merge base unresolvable here; the shrink-only comparison was skipped")
        return 0, False
    base_text = baseline_at(root, sha, config["baseline"], env)
    if base_text is None:
        script = config.get("script")
        if ci and script and baseline_at(root, sha, script, env) is not None:
            out.append(pre + "the baseline is missing at the merge base {} although the ratchet script exists "
                       "there: a baseline moved or renamed in this diff cannot be compared".format(sha[:12]))
            return 2, False
        out.append(pre + "baseline introduced by this diff (absent at {}); shrink-only comparison skipped".format(
            sha[:12]))
        return 0, False
    grew = growth(head_entries, parse_baseline(base_text), rename_map(root, sha, env))
    for path, rule, now, before in grew:
        out.append(pre + "baseline grew for {} [{}]: {} entries now, {} at the merge base".format(
            _clean(path), rule, now, before))
    if grew:
        out.append(pre + "the baseline may only shrink; fix the finding instead of admitting it")
        return 1, True
    return 0, True


def check(config: dict, root, base=None, env=None) -> tuple:
    root = Path(root)
    pre = _prefix(config)
    out = []
    try:
        baseline_path = _baseline_file(root, config)
    except InfraError as exc:
        return 2, [pre + str(exc)]
    if not baseline_path.exists():
        return 2, [pre + "baseline {} is missing; create it with {} --update".format(
            config["baseline"], _recovery(config))]
    try:
        findings, file_count = config["run"](root)
    except Vacuous as exc:
        return 1, [pre + "vacuous scan: {}".format(exc)]
    except InfraError as exc:
        return 2, [pre + str(exc)]
    if file_count < config["floor"]:
        return 1, [pre + "the scan saw only {} files, below the floor of {}; a scan of (almost) nothing "
                   "cannot report green".format(file_count, config["floor"])]
    try:
        pairs = census_pairs(findings, root)
        baseline_entries = parse_baseline(baseline_path.read_text(encoding="utf-8"))
    except InfraError as exc:
        return 2, [pre + str(exc)]
    live = {entry: finding for entry, finding in pairs}
    known = set(baseline_entries)
    new = [entry for entry in sorted(live) if entry not in known]
    stale = [entry for entry in sorted(known) if entry not in live]
    changed_keys = {(e[0], e[1]) for e in new} & {(e[0], e[1]) for e in stale}
    for entry in new:
        finding = live[entry]
        out.append(pre + _clean("NEW {}:{} {} {}".format(finding.path, finding.row, finding.rule, finding.message)))
    for entry in stale:
        text = _clean(format_entry(*entry))
        if (entry[0], entry[1]) in changed_keys:
            out.append(pre + "STALE {} -- a line carrying this finding changed; if the finding itself is unchanged "
                       "run `{} --update` (it refuses real growth)".format(text, _recovery(config)))
        else:
            out.append(pre + "STALE {} -- fixed: run `{} --update` and commit the baseline. After a merge conflict "
                       "take the base branch's copy of the baseline and re-run --update.".format(
                           text, _recovery(config)))
    if new or stale:
        if new:
            out.append(pre + "remedy: " + config["remedy"])
            out.append(pre + "inline waivers (# noqa, eslint-disable) are NOT honoured here, and --update must "
                       "not be used to admit a new finding")
        return 1, out
    try:
        code, compared = _delta(config, root, list(live), base, env, out)
    except InfraError as exc:
        return 2, out + [pre + str(exc)]
    if code == 0:
        out.append(pre + "OK ({} findings baselined, {} files scanned{})".format(
            len(live), file_count, "" if compared else "; shrink-only comparison skipped"))
    return code, out


def update(config: dict, root, base=None, env=None) -> tuple:
    root = Path(root)
    pre = _prefix(config)
    try:
        path = _baseline_file(root, config)
        findings, file_count = config["run"](root)
        if file_count < config["floor"]:
            return 1, [pre + "the scan saw only {} files, below the floor of {}; refusing to write a baseline from "
                       "a scan of (almost) nothing".format(file_count, config["floor"])]
        entries = census(findings, root)
        sha = resolve_base(root, base, env)
        if sha is None and path.exists():
            return 2, [pre + "no merge base could be resolved, so the shrink-only guard cannot run; fetch "
                       "origin/main or pass --base <ref> (--base HEAD takes the committed baseline as the reference)"]
        if sha is not None:
            base_text = baseline_at(root, sha, config["baseline"], env)
            if base_text is not None:
                grew = growth(entries, parse_baseline(base_text), rename_map(root, sha, env))
                if grew:
                    lines = [pre + "refusing to write: {} [{}] would hold {} entries, {} at the merge base".format(
                        _clean(p), r, now, before) for p, r, now, before in grew]
                    return 1, lines + [pre + "fix the new findings instead of baselining them"]
    except Vacuous as exc:
        return 1, [pre + "vacuous scan: {}".format(exc)]
    except InfraError as exc:
        return 2, [pre + str(exc)]
    _write_baseline(path, render_baseline(config["name"], entries, config["drawdown"]))
    return 0, [pre + "wrote {} entries to {}".format(len(entries), config["baseline"])]


def list_live(config: dict, root) -> tuple:
    try:
        findings, _count = config["run"](Path(root))
    except Vacuous as exc:
        return 1, [_prefix(config) + "vacuous scan: {}".format(exc)]
    except InfraError as exc:
        return 2, [_prefix(config) + str(exc)]
    lines = ["{}:{} {} {}".format(f.path, f.row, f.rule, f.message)
             for f in sorted(findings, key=lambda f: (f.path, f.row, f.rule))]
    return 0, lines


# --------------------------------------------------------------------------- tools


def tool_argv(name: str, root, files: list, ruff_path) -> list:
    if name == "ruff":
        return [str(ruff_path), "check", "--config", "ruff.toml", "--ignore-noqa", "--no-cache", "--no-fix",
                "--force-exclude", "--output-format", "json", "--"] + list(files)
    return [str(Path(root) / ESLINT_BIN), "--config", ESLINT_CONFIG, "--no-inline-config",
            "--no-error-on-unmatched-pattern", "-f", "json"] + list(SCOPES["eslint-test-dirs"]["scope"])


def show_files_argv(ruff_path, files: list) -> list:
    return [str(ruff_path), "check", "--config", "ruff.toml", "--no-cache", "--force-exclude", "--show-files",
            "--"] + list(files)


def run_ruff(root, env=None, ruff_path=None, run=subprocess.run) -> tuple:
    root = Path(root)
    files = [name for name in tracked_files(root, SCOPES["ruff"]["scope"], env) if not (root / name).is_symlink()]
    if not files:
        raise Vacuous("no tracked Python files; refusing to invoke ruff (with no file arguments it lints the "
                      "current directory)")
    exe = ruff_path if ruff_path is not None else ensure_ruff(RUFF_REQUIREMENTS, env=dict(env or os.environ))
    listing = _exec(run, show_files_argv(exe, files), RUN_TIMEOUT, cwd=str(root), env=env)
    if listing.returncode != 0:
        raise InfraError("ruff --show-files failed (rc {}): {}".format(listing.returncode, listing.stderr.strip()[:300]))
    listed = {_relative(line.strip(), root) for line in listing.stdout.splitlines() if line.strip()}
    skipped = sorted(name for name in files if name not in listed and not name.startswith(EXCLUDED_PREFIXES))
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
    tracked = {n for n in tracked_files(root, (".",), env) if not (root / n).is_symlink()}
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
        info = os.lstat(str(root))
    except FileNotFoundError:
        root.parent.mkdir(parents=True, exist_ok=True)
        with contextlib.suppress(FileExistsError):
            os.mkdir(str(root), 0o700)
        info = os.lstat(str(root))
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o022:
        return None
    return root


def ensure_ruff(requirements, env, run=subprocess.run, cache_root=None, fallback_root=None) -> Path:
    version = requirements_pin(requirements)
    env = dict(env)
    if cache_root is None:
        home = env.get("XDG_CACHE_HOME") or os.path.join(env.get("HOME") or os.path.expanduser("~"), ".cache")
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
        print("lint-ratchet: installing ruff {} (first run only)".format(version), file=sys.stderr)
        target = Path(tempfile.mkdtemp(prefix="install-", dir=str(base)))
        result = _exec(run, pip_argv(target, requirements), PIP_TIMEOUT, env=pip_env(env))
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
                raise Skip("ruff could not be installed ({}); recover with: {} ruff --check".format(
                    reason, "python3 " + SCRIPT_REL))
            raise InfraError("ruff install failed for an unrecognised reason: {}".format(reason))
        try:
            os.rename(str(target), str(final))
        except OSError:
            if not final.exists():
                raise
            shutil.rmtree(str(target), ignore_errors=True)
    probe = _exec(run, [str(exe), "--version"], 60)
    if probe.stdout.strip() != "ruff {}".format(version):
        raise InfraError("installed ruff ({}) reports {!r}, the pin is {!r}; delete {} and retry".format(
            exe, probe.stdout.strip(), "ruff " + version, final))
    return exe


# --------------------------------------------------------------------------- CLI


def build_config(name: str, env) -> dict:
    runner = (lambda root: run_ruff(root, env)) if name == "ruff" else (lambda root: run_eslint(root, env))
    return dict(SCOPES[name], name=name, run=runner, drawdown=DRAWDOWN, script=SCRIPT_REL)


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description="Shrink-only lint ratchet (see the module docstring).")
    parser.add_argument("scope", choices=sorted(SCOPES))
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--check", action="store_true", help="verify the live tree against the baseline (default)")
    mode.add_argument("--update", action="store_true", help="rewrite the baseline from the live census (never grows it)")
    mode.add_argument("--list", action="store_true", help="print the live findings")
    parser.add_argument("--base", help="ref to compare the baseline against (default: merge-base with origin/main)")
    args = parser.parse_args(argv)
    env = dict(os.environ)
    config = build_config(args.scope, env)
    verb = "update" if args.update else "list" if args.list else "check"
    try:
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
        print(_clean("lint-ratchet({}): {}".format(args.scope, exc)), file=sys.stderr)
        return 2
    except (OSError, ValueError, KeyError, TypeError, AttributeError) as exc:
        print(_clean("lint-ratchet({}): unexpected {}: {}".format(args.scope, type(exc).__name__, exc)),
              file=sys.stderr)
        return 2
    stream = sys.stdout if code == 0 else sys.stderr
    for line in lines:
        print(_clean(line), file=stream)
    return code


if __name__ == "__main__":
    sys.exit(main())
