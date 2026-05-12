#!/usr/bin/env python3
"""resolve-debt — read + close half of the technical-debt ledger loop.

Modes:
  --list                 Print a deterministic markdown table of open entries.
  --no-verify            Skip `gh issue view` round-trip when closing.
  --ledger <path>        Override ledger root (testing).
  --help                 Print usage and exit.
  (default)              Interactive close flow.

Frontmatter mutation goes through `parse_frontmatter` from the repo-root
scripts/ directory (file: backfill-frontmatter.py), loaded via
importlib.util.spec_from_file_location because the source filename uses a
hyphen and is not a valid Python identifier. List parsing uses the helper.
Close mutation does surgical line-level edits to preserve key order.
"""

import argparse
import importlib.util
import os
import subprocess
import sys
import tempfile
from pathlib import Path

LEDGER_DEFAULT = "knowledge-base/project/learnings/technical-debt"
SEVERITY_RANK = {"high": 0, "medium": 1, "low": 2}
LINKED_ISSUE_MIN = 1
LINKED_ISSUE_MAX = 9_999_999
GH_TIMEOUT_SECONDS = 5
MAX_PROMPT_ATTEMPTS = 3


def repo_root() -> Path:
    """Find the repo root by walking up to a .git/AGENTS.md anchor."""
    here = Path(__file__).resolve()
    for parent in [here, *here.parents]:
        if (parent / "AGENTS.md").exists() and (parent / "plugins").is_dir():
            return parent
    return Path.cwd()


def load_frontmatter_helpers():
    """Load parse_frontmatter from scripts/backfill-frontmatter.py via importlib."""
    src = repo_root() / "scripts" / "backfill-frontmatter.py"
    if not src.exists():
        sys.exit(f"ERROR: required helper not found: {src}")
    spec = importlib.util.spec_from_file_location("_bff", src)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod.parse_frontmatter


def list_open_entries(ledger: Path, parse_frontmatter):
    """Walk ledger, parse each *.md, return list of (path, fm) for status==open.

    Sorted by severity desc (high>medium>low>unset), then date asc.
    Warns to stderr on parse failure and skips that file.
    """
    if not ledger.exists():
        return []
    entries = []
    for fp in sorted(ledger.iterdir()):
        if fp.is_dir() or not fp.name.endswith(".md"):
            continue
        try:
            content = fp.read_text()
        except OSError as e:
            print(f"WARN: cannot read {fp.name}: {e}", file=sys.stderr)
            continue
        fm, _body, _raw = parse_frontmatter(content)
        if fm is None:
            print(f"WARN: malformed frontmatter, skipping: {fp.name}", file=sys.stderr)
            continue
        if fm.get("status") != "open":
            continue
        entries.append((fp, fm))

    def sort_key(item):
        _fp, fm = item
        sev = SEVERITY_RANK.get(str(fm.get("severity", "")).lower(), 99)
        return (sev, str(fm.get("date", "")))

    entries.sort(key=sort_key)
    return entries


def render_table(entries) -> str:
    """Render entries as a markdown table (idx, file, date, severity, comp/cat, title)."""
    if not entries:
        return "No open debt entries."
    header = "| idx | file | date | severity | component/category | title |"
    sep = "|-----|------|------|----------|--------------------|-------|"
    rows = [header, sep]
    for i, (fp, fm) in enumerate(entries, start=1):
        comp_or_cat = fm.get("component") or fm.get("category") or "-"
        title = fm.get("title") or fp.stem
        date = fm.get("date", "-")
        sev = fm.get("severity", "-")
        rows.append(
            f"| {i} | {fp.name} | {date} | {sev} | {comp_or_cat} | {title} |"
        )
    return "\n".join(rows)


def prompt_with_retry(prompt: str, validate, *, attempts: int = MAX_PROMPT_ATTEMPTS):
    """Prompt until validate returns (True, value) or attempts exhausted.

    validate(raw_input) -> (ok: bool, value_or_msg).
    Returns the validated value, or sys.exit(2) on exhaustion.
    """
    for _ in range(attempts):
        try:
            raw = input(prompt)
        except EOFError:
            sys.exit(2)
        ok, val_or_msg = validate(raw)
        if ok:
            return val_or_msg
        print(f"  invalid: {val_or_msg}", file=sys.stderr)
    print(f"  too many invalid attempts; aborting.", file=sys.stderr)
    sys.exit(2)


def validate_selection(raw: str, n: int):
    raw = raw.strip()
    if raw.lower() == "q":
        return True, "quit"
    try:
        idx = int(raw)
    except ValueError:
        return False, f"'{raw}' is not an integer"
    if not (1 <= idx <= n):
        return False, f"{idx} out of range 1..{n}"
    return True, idx


def validate_status(raw: str):
    raw = raw.strip().lower()
    if raw in ("resolved", "wont-fix"):
        return True, raw
    return False, f"'{raw}' is not 'resolved' or 'wont-fix'"


def validate_linked_issue(raw: str, *, required: bool):
    raw = raw.strip()
    if not raw:
        if required:
            return False, "linked_issue is required when status=resolved"
        return True, None
    try:
        n = int(raw)
    except ValueError:
        return False, f"'{raw}' is not an integer"
    if not (LINKED_ISSUE_MIN <= n <= LINKED_ISSUE_MAX):
        return False, f"{n} out of range {LINKED_ISSUE_MIN}..{LINKED_ISSUE_MAX}"
    return True, n


def verify_issue_via_gh(issue_n: int) -> None:
    """Call `gh issue view <N>`; exit 1 with --no-verify hint on failure."""
    try:
        result = subprocess.run(
            ["gh", "issue", "view", str(issue_n), "--json", "state,title"],
            capture_output=True,
            text=True,
            timeout=GH_TIMEOUT_SECONDS,
        )
    except FileNotFoundError:
        print(
            "gh issue view failed (gh not on PATH). "
            "Re-invoke with --no-verify to skip validation.",
            file=sys.stderr,
        )
        sys.exit(1)
    except subprocess.TimeoutExpired:
        print(
            f"gh issue view failed (timeout after {GH_TIMEOUT_SECONDS}s). "
            "Re-invoke with --no-verify to skip validation.",
            file=sys.stderr,
        )
        sys.exit(1)
    if result.returncode != 0:
        stderr = result.stderr.strip() or "non-zero exit"
        print(
            f"gh issue view failed ({stderr}). "
            "Re-invoke with --no-verify to skip validation.",
            file=sys.stderr,
        )
        sys.exit(1)


def find_frontmatter_block(lines):
    """Return (start, end) line indices of `---` boundaries, or None."""
    if not lines or lines[0].strip() != "---":
        return None
    for i in range(1, min(len(lines), 30)):
        if lines[i].strip() == "---":
            return (0, i)
    return None


def mutate_entry(fp: Path, new_status: str, linked_issue):
    """Rewrite the entry's frontmatter: replace status:, optionally insert linked_issue:.

    Atomic via tempfile + os.replace. Returns nothing; raises on structural failure.
    """
    text = fp.read_text()
    lines = text.split("\n")
    bounds = find_frontmatter_block(lines)
    if bounds is None:
        sys.exit(f"ERROR: cannot locate frontmatter block in {fp.name}")
    start, end = bounds

    new_lines = list(lines)
    status_idx = None
    linked_idx = None
    for i in range(start + 1, end):
        stripped = new_lines[i].lstrip()
        if stripped.startswith("status:"):
            status_idx = i
        elif stripped.startswith("linked_issue:"):
            linked_idx = i

    if status_idx is None:
        sys.exit(f"ERROR: no status: line in {fp.name} (Phase 1 backfill skipped?)")

    new_lines[status_idx] = f"status: {new_status}"

    if linked_issue is not None:
        line = f"linked_issue: {linked_issue}"
        if linked_idx is not None:
            new_lines[linked_idx] = line
        else:
            new_lines.insert(status_idx + 1, line)
    else:
        # wont-fix with no linked_issue: leave any existing linked_issue alone.
        pass

    new_text = "\n".join(new_lines)

    # Atomic write: tempfile in same dir, then os.replace.
    fd, tmp_path = tempfile.mkstemp(
        prefix=fp.name + ".", suffix=".tmp", dir=str(fp.parent)
    )
    try:
        with os.fdopen(fd, "w") as f:
            f.write(new_text)
        os.replace(tmp_path, str(fp))
    except Exception:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
        raise


def print_diff(fp: Path):
    """Print `git diff -- <fp>` to stdout. Best-effort: silent on git failure."""
    try:
        subprocess.run(
            ["git", "diff", "--", str(fp)],
            check=False,
        )
    except FileNotFoundError:
        pass


def cmd_list(ledger: Path, parse_frontmatter) -> int:
    entries = list_open_entries(ledger, parse_frontmatter)
    print(render_table(entries))
    return 0


def cmd_interactive(ledger: Path, parse_frontmatter, *, verify: bool) -> int:
    entries = list_open_entries(ledger, parse_frontmatter)
    if not entries:
        print("No open debt entries.")
        return 0
    print(render_table(entries))

    sel = prompt_with_retry(
        f"Select entry (1..{len(entries)}) or q to quit: ",
        lambda r: validate_selection(r, len(entries)),
    )
    if sel == "quit":
        return 0
    fp, _fm = entries[sel - 1]

    new_status = prompt_with_retry(
        "Status (resolved | wont-fix): ", validate_status
    )

    linked_issue = None
    if new_status == "resolved":
        linked_issue = prompt_with_retry(
            "linked_issue (integer, e.g., 2723): ",
            lambda r: validate_linked_issue(r, required=True),
        )
    else:  # wont-fix — optional
        linked_issue = prompt_with_retry(
            "linked_issue (integer, optional — press enter to skip): ",
            lambda r: validate_linked_issue(r, required=False),
        )

    if verify and linked_issue is not None:
        verify_issue_via_gh(linked_issue)

    mutate_entry(fp, new_status, linked_issue)
    print_diff(fp)
    print(
        f"Diff above. Review and commit when ready. To undo: git checkout -- {fp}. "
        "No auto-commit by design.",
        file=sys.stderr,
    )
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(
        prog="resolve-debt",
        description="Triage and close entries in the technical-debt ledger.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Modes:\n"
            "  --list                 Print open entries as a markdown table.\n"
            "  --no-verify            Skip `gh issue view` when closing.\n"
            "  --ledger <path>        Override ledger root (testing).\n"
            "  (no flags)             Interactive close flow.\n"
            "\n"
            "The skill never auto-commits. After mutation, it prints the diff\n"
            "and stops. To undo: `git checkout -- <file>` (pre-commit) or\n"
            "`git revert` (post-commit).\n"
        ),
    )
    parser.add_argument("--list", action="store_true", help="list open entries; no prompts")
    parser.add_argument("--no-verify", action="store_true", help="skip `gh issue view` validation")
    parser.add_argument(
        "--ledger",
        default=None,
        help=f"ledger directory (default: {LEDGER_DEFAULT})",
    )
    args = parser.parse_args()

    parse_frontmatter = load_frontmatter_helpers()
    ledger = Path(args.ledger) if args.ledger else (repo_root() / LEDGER_DEFAULT)

    if args.list:
        return cmd_list(ledger, parse_frontmatter)
    return cmd_interactive(ledger, parse_frontmatter, verify=not args.no_verify)


if __name__ == "__main__":
    sys.exit(main())
