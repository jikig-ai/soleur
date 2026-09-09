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


# --- Rule family 2: accessibility-snapshot credential rendering (#7947) ---
#
# An accessibility snapshot serializes the VALUE of input fields, including a
# value the agent never supplied. Measured on both leaking surfaces; record at
# knowledge-base/project/specs/feat-one-shot-7946-7947-sentry-org-token-and-snapshot-redaction/phase-0-measurement.md
#
# TWO rules, named for what each actually enforces. The first revision had ONE,
# whose implemented predicate was "the string `redact-a11y-snapshot` appears
# somewhere in this document" while its stated property was "no instruction
# directs an unrouted snapshot". Those are different, and the gap was live: one
# mention exempted 26 unrouted instructions across five shipped files, 19 of
# which the PreToolUse hook DENIES at runtime. The plugin shipped commands its
# own guard blocks, with the required check green.
#
#   S1 (routing, per LINE): every `agent-browser ... snapshot` instruction is
#      routed through the redactor ON THAT LINE. Deliberately NOT narrowed by
#      auth context, because the hook it backs is not narrowed either -- it
#      denies every unrouted invocation. A lint narrower than the runtime gate
#      is teeth for a different rule than the one being enforced.
#
#   S2 (disclosure, per FILE): a document instructing a Playwright-MCP snapshot
#      in an authentication context states that the MCP path has no runtime
#      guard. Document scope is correct HERE -- a file states its safety rule
#      once -- and the redactor pipe is deliberately NOT required, because an
#      MCP tool result cannot be piped through a shell script. Requiring it
#      produced two shipped blocks prescribing an inoperable command, which is
#      the lint manufacturing its own compliance.
AGENT_BROWSER_SNAPSHOT_RE = re.compile(r"agent-browser(?:\s+[^\s|;&]+)*\s+snapshot\b")

MCP_SNAPSHOT_RE = re.compile(r"(?:mcp__[a-z_]*__)?browser_snapshot\b")

# An authentication/credential context anywhere in the same document. Used by S2
# only. A snapshot on an ordinary page is not the hazard S2 describes.
AUTH_CONTEXT_RE = re.compile(
    r"(?i)(?<![a-z0-9])(?:log[\s-]?in|sign[\s-]?in|password|passphrase"
    r"|credential|authentication|token|api[\s_-]?key|secret)(?![a-z0-9])"
)

# Anchored on the redactor's FILENAME, so a look-alike command that does not
# redact cannot satisfy the guard (cq-assert-anchor-not-bare-token).
REDACTOR_ANCHOR_RE = re.compile(r"redact-a11y-snapshot")

# The S2 disclosure. Anchored on the claim, not on a bare token, so prose that
# merely mentions "Playwright MCP" does not satisfy it.
# Whitespace-tolerant on purpose. A prose reflow that wraps the sentence would
# otherwise disarm the marker silently, leaving the guard green and looking
# alive while the disclosure it checks for is still present to a human reader.
MCP_GAP_MARKER_RE = re.compile(
    r"no\s+runtime\s+guard\s+on\s+the\s+Playwright-MCP\s+path", re.IGNORECASE
)

S1_RECIPE = (
    "route it through the redactor on the same line "
    '(`agent-browser snapshot -i 2>&1 | python3 '
    '"${CLAUDE_PLUGIN_ROOT}/skills/agent-browser/scripts/redact-a11y-snapshot.py"`) '
    "-- the bare anchor, quoted: ADR-179 rejects the `:-default` form, which "
    "resolves to a repo path that exists on no customer machine. The PreToolUse "
    "hook DENIES this command as written, so shipping it instructs the agent to "
    "run something the guard blocks"
)

S2_RECIPE = (
    "state in this file that the Playwright-MCP path has "
    "'no runtime guard on the Playwright-MCP path' (#7980) -- the redactor "
    "cannot be piped into an MCP tool result, so the honest control here is "
    "disclosure, not routing"
)

# Population for family 2. Deliberately NARROWER than the host lint's walk.
#
# The property quantifies over what the shipped plugin INSTRUCTS an agent to do,
# so it covers skills/ and agents/ under the plugin and nothing else. A
# knowledge-base plan, spec, session-state or post-mortem is a RECORD of what
# happened, not an instruction -- gating those would red on every historical
# document that describes the unsafe form, including the measurement record that
# exists to document it. Measured before scoping: the unscoped walk produced 65
# hits, 8 of them in this issue's own evidence files.
SNAPSHOT_RULE_DIRS = (
    "plugins/soleur/skills/",
    "plugins/soleur/agents/",
)


def scan_snapshot_rule(text: str, posix_path: str) -> list[tuple[int, str]]:
    """Return (1-based line, message) for S1 and S2 violations."""
    if not any(d in posix_path for d in SNAPSHOT_RULE_DIRS):
        return []

    hits: list[tuple[int, str]] = []
    lines = text.splitlines()

    # S1 -- per line, unconditional.
    for i, line in enumerate(lines):
        m = AGENT_BROWSER_SNAPSHOT_RE.search(line)
        if m and REDACTOR_ANCHOR_RE.search(line) is None:
            hits.append(
                (i + 1, f"unrouted `{m.group(0).strip()}` -- {S1_RECIPE}")
            )

    # S2 -- per file.
    if AUTH_CONTEXT_RE.search(text) and MCP_GAP_MARKER_RE.search(text) is None:
        for i, line in enumerate(lines):
            m = MCP_SNAPSHOT_RE.search(line)
            if m:
                hits.append(
                    (
                        i + 1,
                        f"`{m.group(0)}` in an authentication context with no "
                        f"MCP-gap disclosure -- {S2_RECIPE}",
                    )
                )
                break

    return hits


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
    hard_out += [
        f"{path}:{ln}: accessibility-snapshot rule: {msg}."
        for ln, msg in scan_snapshot_rule(text, path.as_posix())
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


def full_scan_files_with_total() -> tuple[list[Path], int]:
    """Return (scannable files, total *.md discovered before archive filtering).

    The two numbers differ only by archived files, and the anti-vacuity floor
    needs BOTH: a repo whose docs are all under archive/ has nothing to scan
    LEGITIMATELY, while a repo where the scan dirs hold no markdown at all is
    the vacuous case (wrong root, broken checkout). Collapsing them would make
    the floor fire on the first and miss nothing on the second.
    """
    picked: list[Path] = []
    total = 0
    for d in SCAN_DIRS:
        root = Path(d)
        if not root.is_dir():
            continue
        for p in sorted(root.rglob("*.md")):
            total += 1
            if "/archive/" in p.as_posix():
                continue
            picked.append(p)
    return picked, total


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
        files, discovered = full_scan_files_with_total()
        # Anti-vacuity floor. A lint that reports "0 checked" and exits 0 is
        # vacuous -- indistinguishable from a clean run. --changed is exempt:
        # an empty changed-set is the normal case there.
        #
        # Keyed on DISCOVERED, not on the post-filter list: a repo whose docs
        # are all under archive/ scans zero files legitimately, and firing on
        # that would red a correct codebase. Only "the scan dirs hold no
        # markdown at all" is the vacuous shape.
        if discovered == 0:
            print(
                "ERROR: full-scan population is empty (no tracked *.md under "
                f"{'/, '.join(SCAN_DIRS)}/). A lint with nothing to check is "
                "vacuous, not clean. Fail-closed.",
                file=sys.stderr,
            )
            return 2

        # Fire only when the rule's directories EXIST and hold no markdown --
        # a real anomaly. A checkout that has no plugin tree at all (a fixture
        # repo, a docs-only sparse checkout) is a different repo shape, not a
        # vacuous run, and keying on the count alone red-lines it. That is the
        # SAME mistake the aggregate floor above already made once, so it is
        # worth stating: a population floor must distinguish "empty" from
        # "absent", and the existing C3 case caught both attempts.
        snapshot_dirs_present = any(Path(d).is_dir() for d in SNAPSHOT_RULE_DIRS)
        snapshot_pop = sum(
            1
            for p in files
            if any(d in p.as_posix() for d in SNAPSHOT_RULE_DIRS)
        )
        if snapshot_dirs_present and snapshot_pop == 0:
            print(
                "ERROR: the accessibility-snapshot rule population is empty (no "
                f"tracked *.md under {', '.join(SNAPSHOT_RULE_DIRS)}). A rule "
                "with nothing to check is vacuous, not clean. Fail-closed.",
                file=sys.stderr,
            )
            return 2

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
        n_snap = sum(1 for e in hard if "accessibility-snapshot rule:" in e)
        n_path = len(hard) - n_snap
        print(
            f"\nFAIL: {n_path} resolvable credential-file path literal(s) and "
            f"{n_snap} unrouted accessibility snapshot(s) in an authentication "
            "flow. A resolvable path makes Claude Code's harness auto-attach the "
            "real file into model context when the doc loads — neutralize each "
            f"one ({RECIPE}). An unrouted snapshot renders input values, "
            "including ones the agent never supplied, into the transcript.",
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
