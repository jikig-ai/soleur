#!/usr/bin/env python3
"""resolve-debt — read + close half of the technical-debt ledger loop.

Modes:
  --list                 Print a deterministic markdown table of open entries.
  --no-verify            Skip `gh issue view` round-trip when closing.
  --ledger <path>        Override ledger root (testing).
  --help                 Print usage and exit.
  (default)              Interactive close flow.

Frontmatter parsing uses `scripts/frontmatter_lib.py` from the repo root
(shared helper module — also consumed by `scripts/backfill-frontmatter.py`).
Close mutation does surgical line-level edits to preserve key order.
"""

import argparse
import hashlib
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any, Callable

LEDGER_DEFAULT = "knowledge-base/project/learnings/technical-debt"
SEVERITY_RANK = {"high": 0, "medium": 1, "low": 2}
LINKED_ISSUE_MIN = 1
LINKED_ISSUE_MAX = 9_999_999
GH_TIMEOUT_SECONDS = 5
MAX_PROMPT_ATTEMPTS = 3
VALID_STATUSES = ("open", "resolved", "wont-fix")
CLOSE_STATUSES = ("resolved", "wont-fix")


def repo_root() -> Path:
    """Find the repo root by walking up to an AGENTS.md + plugins/ anchor."""
    here = Path(__file__).resolve()
    for parent in [here, *here.parents]:
        if (parent / "AGENTS.md").exists() and (parent / "plugins").is_dir():
            return parent
    sys.exit(
        "ERROR: cannot locate repo root (AGENTS.md + plugins/ anchor missing). "
        "resolve-debt must run from inside a Soleur checkout."
    )


def load_frontmatter_helpers() -> Callable[[str], tuple]:
    """Load parse_frontmatter from scripts/frontmatter_lib.py via sys.path."""
    scripts_dir = repo_root() / "scripts"
    lib = scripts_dir / "frontmatter_lib.py"
    if not lib.exists():
        sys.exit(f"ERROR: required helper not found: {lib}")
    if str(scripts_dir) not in sys.path:
        sys.path.insert(0, str(scripts_dir))
    from frontmatter_lib import parse_frontmatter  # noqa: E402

    return parse_frontmatter


def list_open_entries(
    ledger: Path, parse_frontmatter: Callable[[str], tuple]
) -> list[tuple[Path, dict]]:
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


def render_table(entries: list[tuple[Path, dict]]) -> str:
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


def prompt_with_retry(
    prompt: str,
    validate: Callable[[str], tuple[bool, Any]],
    *,
    attempts: int = MAX_PROMPT_ATTEMPTS,
) -> Any:
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
    print("  too many invalid attempts; aborting.", file=sys.stderr)
    sys.exit(2)


def validate_selection(raw: str, n: int) -> tuple[bool, Any]:
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


def validate_status(raw: str) -> tuple[bool, Any]:
    raw = raw.strip().lower()
    if raw in CLOSE_STATUSES:
        return True, raw
    return False, f"'{raw}' is not 'resolved' or 'wont-fix'"


def validate_linked_issue(raw: str, *, required: bool) -> tuple[bool, Any]:
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


def find_frontmatter_block(lines: list[str]) -> tuple[int, int] | None:
    """Return (start, end) line indices of `---` boundaries, or None."""
    if not lines or lines[0].strip() != "---":
        return None
    for i in range(1, min(len(lines), 30)):
        if lines[i].strip() == "---":
            return (0, i)
    return None


def mutate_entry(fp: Path, new_status: str, linked_issue: int | None) -> None:
    """Rewrite the entry's frontmatter: replace status:, optionally insert linked_issue:.

    Atomic via tempfile + os.replace. Asserts body MD5 unchanged (defense
    against CRLF/EOL drift and accidental body mutation). Raises on
    structural failure or prior-status-not-in-enum.
    """
    if new_status == "open" and linked_issue is not None:
        sys.exit(
            "ERROR: linked_issue is forbidden when status=open "
            "(see knowledge-base/project/learnings/technical-debt/README.md)."
        )

    text = fp.read_text()
    lines = text.split("\n")
    bounds = find_frontmatter_block(lines)
    if bounds is None:
        sys.exit(f"ERROR: cannot locate frontmatter block in {fp.name}")
    start, end = bounds

    # Capture body hash BEFORE mutation. Mutations are line-level inside the
    # frontmatter block; the body (lines after the closing `---`) must round-
    # trip byte-for-byte.
    body_before = "\n".join(lines[end + 1 :])
    body_hash_before = hashlib.md5(body_before.encode()).hexdigest()

    new_lines = list(lines)
    status_idx = None
    linked_idx = None
    prior_status_value = None
    for i in range(start + 1, end):
        stripped = new_lines[i].lstrip()
        if stripped.startswith("status:"):
            status_idx = i
            prior_status_value = stripped.split(":", 1)[1].strip()
        elif stripped.startswith("linked_issue:"):
            linked_idx = i

    if status_idx is None:
        sys.exit(f"ERROR: no status: line in {fp.name} (Phase 1 backfill skipped?)")

    if prior_status_value not in VALID_STATUSES:
        sys.exit(
            f"ERROR: {fp.name} has out-of-enum prior status "
            f"'{prior_status_value}' (expected one of {VALID_STATUSES}). "
            "Inspect manually before mutating."
        )

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

    # Re-locate frontmatter boundary in the mutated lines so we can verify
    # body integrity by hash. If insertion shifted the closing ---, end+1
    # → end+2 in new_lines.
    new_bounds = find_frontmatter_block(new_lines)
    if new_bounds is None:
        sys.exit(f"ERROR: post-mutation frontmatter block missing in {fp.name}")
    _, new_end = new_bounds
    body_after = "\n".join(new_lines[new_end + 1 :])
    body_hash_after = hashlib.md5(body_after.encode()).hexdigest()
    if body_hash_before != body_hash_after:
        sys.exit(
            f"ERROR: body hash drift on {fp.name} "
            f"(before={body_hash_before}, after={body_hash_after}). "
            "Mutation aborted; no file written."
        )

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


def print_diff(fp: Path) -> None:
    """Print `git diff -- <fp>` to stdout. Warn loudly on git failure.

    Silent on FileNotFoundError (git missing) since the script's contract
    is "mutate atomically + print diff for review"; if git is unreachable
    the operator can run `diff` themselves, but we must SAY SO rather than
    leave the call site believing the diff was rendered.
    """
    try:
        result = subprocess.run(
            ["git", "diff", "--", str(fp)],
            check=False,
        )
    except FileNotFoundError:
        print(
            f"WARN: git not on PATH. Mutation succeeded; inspect {fp} manually.",
            file=sys.stderr,
        )
        return
    if result.returncode != 0:
        print(
            f"WARN: git diff failed (rc={result.returncode}). "
            f"Mutation succeeded; inspect {fp} manually.",
            file=sys.stderr,
        )


def render_json(entries: list[tuple[Path, dict]]) -> str:
    """Render entries as a JSON array (for agent/loop consumption).

    PyYAML returns `datetime.date` for ISO dates; coerce all values to
    JSON-safe primitives so the default encoder doesn't raise.
    """
    def _safe(v: Any) -> Any:
        if v is None or isinstance(v, (str, int, float, bool, list, dict)):
            return v
        return str(v)

    rows = []
    for i, (fp, fm) in enumerate(entries, start=1):
        rows.append(
            {
                "idx": i,
                "file": fp.name,
                "date": _safe(fm.get("date")),
                "severity": _safe(fm.get("severity")),
                "component_or_category": _safe(fm.get("component") or fm.get("category")),
                "title": _safe(fm.get("title") or fp.stem),
                "status": _safe(fm.get("status")),
            }
        )
    return json.dumps(rows, indent=2)


def cmd_list(
    ledger: Path, parse_frontmatter: Callable[[str], tuple], *, as_json: bool
) -> int:
    entries = list_open_entries(ledger, parse_frontmatter)
    if as_json:
        print(render_json(entries))
    else:
        print(render_table(entries))
    return 0


def cmd_close_noninteractive(
    ledger: Path,
    parse_frontmatter: Callable[[str], tuple],
    *,
    close_idx: int,
    new_status: str,
    linked_issue: int | None,
    verify: bool,
    allow_fixture: bool,
) -> int:
    """Close a single entry without prompts. For /loop and agent composition.

    Reuses the same validation surface as interactive mode (status enum,
    linked_issue range, fixture-path refusal, gh verify, atomic mutation,
    body MD5). Re-resolves the entry index against the current sorted
    --list ordering so external `--list --json` → `--close N` pipelines
    are coherent.
    """
    ledger_str = str(ledger.resolve())
    if "/test/fixtures/" in ledger_str and not allow_fixture:
        sys.exit(
            f"ERROR: refusing to mutate fixtures under {ledger_str}. "
            "Pass --allow-fixture to override (test smoke-runs only)."
        )
    if new_status not in CLOSE_STATUSES:
        sys.exit(
            f"ERROR: --status must be one of {CLOSE_STATUSES}; got '{new_status}'."
        )
    if new_status == "resolved" and linked_issue is None:
        sys.exit("ERROR: --linked-issue is required when --status=resolved.")
    entries = list_open_entries(ledger, parse_frontmatter)
    if not entries:
        sys.exit("ERROR: no open entries to close.")
    if not (1 <= close_idx <= len(entries)):
        sys.exit(
            f"ERROR: --close index {close_idx} out of range 1..{len(entries)}."
        )
    fp, _fm = entries[close_idx - 1]
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


def cmd_interactive(
    ledger: Path,
    parse_frontmatter: Callable[[str], tuple],
    *,
    verify: bool,
    allow_fixture: bool,
) -> int:
    # Refuse to mutate fixtures by default — the interactive flow rewrites
    # files in place, and an operator running smoke tests against fixture
    # paths under plugins/**/test/fixtures/** would otherwise create a
    # mutated-fixture commit risk (see #3645 review F6).
    ledger_str = str(ledger.resolve())
    if "/test/fixtures/" in ledger_str and not allow_fixture:
        sys.exit(
            f"ERROR: refusing to mutate fixtures under {ledger_str}. "
            "Pass --allow-fixture to override (test smoke-runs only)."
        )
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
            "  --list --json          Print open entries as JSON (for agents).\n"
            "  --close N --status S [--linked-issue N]   Non-interactive close.\n"
            "  --no-verify            Skip `gh issue view` when closing.\n"
            "  --ledger <path>        Override ledger root (testing).\n"
            "  --allow-fixture        Permit mutation under test/fixtures/.\n"
            "  (no flags)             Interactive close flow.\n"
            "\n"
            "The skill never auto-commits. After mutation, it prints the diff\n"
            "and stops. To undo: `git checkout -- <file>` (pre-commit) or\n"
            "`git revert` (post-commit).\n"
        ),
    )
    parser.add_argument("--list", action="store_true", help="list open entries; no prompts")
    parser.add_argument(
        "--json",
        action="store_true",
        help="with --list, emit JSON instead of markdown (for agents / /loop)",
    )
    parser.add_argument("--no-verify", action="store_true", help="skip `gh issue view` validation")
    parser.add_argument(
        "--ledger",
        default=None,
        help=f"ledger directory (default: {LEDGER_DEFAULT})",
    )
    parser.add_argument(
        "--allow-fixture",
        action="store_true",
        help="allow mutation against test/fixtures/ paths (smoke-runs only)",
    )
    parser.add_argument(
        "--close",
        type=int,
        default=None,
        metavar="IDX",
        help="non-interactive close: target the IDX-th open entry (1-based, same order as --list)",
    )
    parser.add_argument(
        "--status",
        default=None,
        choices=list(CLOSE_STATUSES),
        help="with --close: new status (resolved|wont-fix)",
    )
    parser.add_argument(
        "--linked-issue",
        type=int,
        default=None,
        help="with --close: linked GitHub issue number (required for resolved)",
    )
    args = parser.parse_args()

    parse_frontmatter = load_frontmatter_helpers()
    ledger = Path(args.ledger) if args.ledger else (repo_root() / LEDGER_DEFAULT)

    if args.list:
        return cmd_list(ledger, parse_frontmatter, as_json=args.json)
    if args.close is not None:
        if args.status is None:
            sys.exit("ERROR: --status is required with --close.")
        if args.linked_issue is not None:
            ok, msg = validate_linked_issue(str(args.linked_issue), required=False)
            if not ok:
                sys.exit(f"ERROR: --linked-issue invalid: {msg}")
        return cmd_close_noninteractive(
            ledger,
            parse_frontmatter,
            close_idx=args.close,
            new_status=args.status,
            linked_issue=args.linked_issue,
            verify=not args.no_verify,
            allow_fixture=args.allow_fixture,
        )
    return cmd_interactive(
        ledger,
        parse_frontmatter,
        verify=not args.no_verify,
        allow_fixture=args.allow_fixture,
    )


if __name__ == "__main__":
    sys.exit(main())
