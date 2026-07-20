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
*infra-imperative* token co-occur on the same line, or an actor line and an
imperative line are adjacent in the non-blank line sequence (either ordering,
across blank lines). A bare-token denylist cannot separate "prescribes a
*human* runs terraform apply" (a bug) from "the dispatch/orchestrator runs
terraform apply" (the fix), and would red-line the de-manualization plan itself
plus the retained deferred-orchestrator runbook steps.

Detection is on the RAW line (inline backticks are NOT stripped): a human step
hidden behind an inline `terraform apply` span, or an actor named as
`` `operator` ``, still counts. Only *fenced* code blocks (``` / ~~~) are
skipped wholesale — a runnable multi-line example, never prose.

The one exception is a `*.yml` / `*.yaml` FILENAME, blanked before the scan
(#6771). This is not a contradiction of "raw line": a backtick span can contain
a command, so stripping backticks would hide real imperatives — but a filename
never can. It NAMES automation, it does not instruct. Citing
`apply-web-platform-infra.yml` is how this repo documents a CI-driven apply, yet
`apply-` satisfied `\bappl(y|ies|ied)\b` (the `-` is a word boundary), so the
sentinel flagged the very automation that makes the step non-human.

Carve-outs (a matched line is NOT flagged when):
  * inside a paired `<!-- lint-infra-ignore start -->` … `<!-- lint-infra-ignore
    end -->` region. The markers MUST be HTML comments (a bare `lint-infra-ignore`
    token in prose or inside a fence never opens a region). A `start` with no
    matching `end` is fail-closed: it does NOT grandfather the file tail — it is
    reported as an error (exit non-zero);
  * inside a fenced code block (``` / ~~~). An unterminated fence is reported as
    an error (fail-closed) rather than silently disabling the tail;
  * under an exact `## Resolved` (or `## Resolved (…)` / `— …`) or a
    `Last-resort diagnosis` heading, until the next heading of equal-or-higher
    level. A heading like `## Resolved questions` does NOT carve;
  * in a file whose path contains `/archive/`.

Paren-safety (learning 2026-05-15-ci-sentinel-paren-safety): tokens are short
phrases that span no punctuation boundary; gap phrases use non-greedy `.*?` and
never a literal paren, so prose parentheses can't break a match.

Modes:
  * full-scan (default): every `*.md` under the scan dirs (minus `**/archive/**`).
  * `--changed`: only files changed vs the merge base (grandfathers pre-existing
    violations; the CI/lefthook wiring). New untracked docs are included. If the
    merge base or the diff cannot be resolved, this is fail-closed (exit 2).
  * explicit positional paths: scan exactly those files (used by lefthook
    `{staged_files}` and the test harness).

Exit codes:
    0  no human-run infra step prescribed in the scanned set
    1  one or more violations (each printed as `file:line: ...` on stderr)
    2  argument or git error
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
        r"\boperator\b",                      # operator, ask the operator
        r"\byou\b",                           # you
        r"\byourself\b",                      # do it yourself
        r"\byour laptop\b",                   # your laptop
        r"\bfounder\b",                       # the founder
        # ssh into / onto / to / `ssh -i` — a human opening a remote shell.
        r"\bssh(?:\s+into|\s+onto|\s+to|\s+-i)\b",
        r"\blog into\b.*?\bconsole\b",        # log into … console
        r"\bby hand\b",                       # by hand
        r"\bmanually\b",                      # manually
        # "<human role> runs …" — the founder runs, the admin runs, etc.
        r"\b(?:founder|operator|admin|maintainer|sysadmin|engineer)\s+runs?\b",
    )
)

# Infra-imperative tokens. Case-insensitive, with verb inflection (lemma + s /
# ing / ed / -ies) so "reboots"/"is rebooting"/"applies"/"power-cycles" match,
# not only the bare lemma. Gap phrases use non-greedy `.*?` so intervening prose
# (incl. parentheses) can't break the match.
IMPERATIVE_RES = tuple(
    re.compile(p, re.IGNORECASE)
    for p in (
        r"\b(?:terraform|tofu|opentofu)\s+appl(?:y|ies|ied)\b",       # apply/applies/applied
        r"\b(?:terraform|tofu|opentofu)\s+destroy(?:s|ed|ing)?\b",    # destroy
        r"\b(?:terraform|tofu|opentofu)\s+taint(?:s|ed|ing)?\b",      # taint
        r"\b(?:terraform|tofu|opentofu)\s+import(?:s|ed|ing)?\b",     # import
        r"\breboot(?:s|ing|ed)?\b",                                   # reboot(s|ing|ed)
        r"\bpowers?[- ]cycl(?:e|es|ed|ing)\b",                        # power-cycle(s|d|ing)
        r"\bpowers?[- ]off\b",                                        # power off / power-off
        r"\bshut(?:s|ting)?\s+down\b",                                # shut/shuts/shutting down
        r"\bshutdown\b",                                              # shutdown
        r"\bsystemctl\s+restart\b",                                   # systemctl restart
        r"\bdocker\s+restart\b",                                      # docker restart
        r"\bcryptsetup\b",                                            # cryptsetup (LUKS)
        r"\bmount(?:s|ing|ed)?\b",                                    # mount(s|ing|ed)
        r"\battach(?:es|ing|ed)?\s+the\s+volume\b",                   # attach the volume
        r"\bverif(?:y|ies|ied)\b.*?\bprivate\b.*?\bip\b",             # verify … private … IP
        # -target … apply. Deliberately NOT anchored on terraform/tofu/opentofu,
        # unlike the siblings above (ADR: infra-sentinel detection semantics).
        # Anchoring was measured to silence 41 corpus lines, ~40% of them GENUINE
        # human steps — "a FULL operator apply", "the operator applies the new
        # resource manually" — because the natural phrasing omits the tool name.
        # False positive = author friction; false negative = a non-technical
        # operator meets an un-automated infra step. Resolve toward sensitivity.
        r"-target\b.*?\bappl(?:y|ies|ied)\b",
    )
)

# A `*.yml` / `*.yaml` filename NAMES automation; it never instructs. `*` is in
# the class so a globbed workflow name (`reboot-*.yml`) is covered too.
YAML_FILENAME_RE = re.compile(r"\b[\w.*-]+\.ya?ml\b", re.IGNORECASE)

# UNAMBIGUOUS human-agency signals. A line carrying one of these is scanned RAW
# (no filename neutralization) — otherwise an imperative that lives ONLY inside
# a workflow filename gets eaten and a genuine human step goes silent:
#
#     you ssh into the web host and run the
#     `cryptsetup-unlock-workspaces.yml` playbook by hand
#
# `cryptsetup` is the only imperative there; neutralizing the filename drops it
# and the line passes. That is the false-NEGATIVE mirror of the #6771 defect,
# and it lands on runbooks — the artifact class this sentinel exists to police.
#
# Bare `operator` / `you` / `founder` are deliberately ABSENT: those are the
# weak, incidental mentions the filename false positive is actually made of
# ("the operator's value", "paged by reboot-web-hosts.yml"). Including them
# would re-open #6771. Measured at production scan scope, this suppression
# costs ZERO false positives (its one corpus hit is under `/archive/`, which
# the scanner already excludes).
STRONG_ACTOR_RE = re.compile(
    r"\bby hand\b"
    r"|\bmanually\b"
    r"|\byourself\b"
    r"|\byour laptop\b"
    r"|\bssh(?:\s+into|\s+onto|\s+to|\s+-i)\b"
    r"|\b(?:founder|operator|admin|maintainer|sysadmin|engineer)\s+runs?\b",
    re.IGNORECASE,
)

FENCE_RE = re.compile(r"^\s*(```|~~~)")
HEADING_RE = re.compile(r"^(#{1,6})\s+(.*?)\s*$")
# Region markers must be HTML comments (`<!-- lint-infra-ignore start|end … -->`).
# A bare `lint-infra-ignore` token in prose or inside a fence never opens/closes
# a region. Order matters: an `end` line also contains `lint-infra-ignore`.
IGNORE_START_RE = re.compile(r"<!--\s*lint-infra-ignore\s+start\b", re.IGNORECASE)
IGNORE_END_RE = re.compile(r"<!--\s*lint-infra-ignore\s+end\b", re.IGNORECASE)


def _is_carve_heading(title: str) -> bool:
    """True for an exact `Resolved`/`Resolved (…)`/`Resolved — …` or a
    `Last-resort diagnosis` heading — NOT for `Resolved questions` etc."""
    # Strip leading decoration (emoji, ✅, whitespace) before the first letter.
    t = re.sub(r"^[^A-Za-z]+", "", title)
    # `Resolved` at start, followed by end-of-title OR a non-word separator
    # (space+`(`, `—`, `:`, `-`) — but NOT another word like "questions".
    if re.match(r"Resolved(?=$|\s*[^\w\s])", t, re.IGNORECASE):
        return True
    if re.match(r"Last-resort diagnosis\b", t, re.IGNORECASE):
        return True
    return False


def _neutralize_filenames(text: str) -> str:
    """Blank out `*.yml`/`*.yaml` filenames so a workflow NAME can't match."""
    lowered = text.lower()
    if ".yml" not in lowered and ".yaml" not in lowered:
        return text
    # Substitute `_`, never `""` — deleting the span can splice the surrounding
    # tokens together and CREATE a match absent from the source (e.g.
    # "terraform pipeline.yml applies" → "terraform  applies").
    return YAML_FILENAME_RE.sub("_", text)


def _has_actor(text: str) -> bool:
    return any(r.search(text) for r in ACTOR_RES)


def _has_imperative(text: str) -> bool:
    return any(r.search(text) for r in IMPERATIVE_RES)


def scan_text(text: str) -> tuple[list[int], list[str]]:
    """Return (flagged 1-based line numbers, structural errors).

    A line contributes an (actor, imperative) signal only when it is NOT carved
    out (fenced / ignore-region / Resolved|Last-resort section). A violation is
    a same-line co-occurrence, or an actor line adjacent (in the non-blank line
    sequence, either ordering) to an imperative line. Structural errors
    (unterminated ignore region / unterminated fence) are fail-closed.
    """
    lines = text.splitlines()
    n = len(lines)
    actor = [False] * n
    imper = [False] * n

    in_fence = False
    fence_start_line = 0
    in_ignore = False
    ignore_start_line = 0
    carve = False
    carve_level = 0

    for i, raw in enumerate(lines):
        # 1. Inside an ignore region: only the terminating end marker matters.
        if in_ignore:
            if IGNORE_END_RE.search(raw):
                in_ignore = False
            continue

        # 2. Fence toggling. Content (and any markers) inside a fence are skipped
        #    wholesale — so a marker cannot be smuggled inside a code block.
        if FENCE_RE.match(raw):
            if not in_fence:
                in_fence = True
                fence_start_line = i + 1
            else:
                in_fence = False
            continue
        if in_fence:
            continue

        # 3. Ignore-region markers (HTML-comment shape, outside fences only).
        #    `end` before `start` — an `end` line also matches `lint-infra-ignore`.
        if IGNORE_END_RE.search(raw):
            # Stray `end` with no open region: no suppression to toggle.
            continue
        if IGNORE_START_RE.search(raw):
            in_ignore = True
            ignore_start_line = i + 1
            continue

        # 4. Headings drive the Resolved / Last-resort-diagnosis section carve.
        hm = HEADING_RE.match(raw)
        if hm:
            level = len(hm.group(1))
            title = hm.group(2)
            if _is_carve_heading(title):
                carve = True
                carve_level = level
            elif carve and level <= carve_level:
                carve = False
            # Heading lines never carry a prescribed step.
            continue
        if carve:
            continue

        # 5. Actor / imperative on the RAW line (inline backticks NOT stripped),
        #    minus any `*.yml`/`*.yaml` filename. Computed ONCE and fed to both
        #    predicates — substituting inside each predicate re-scans the line
        #    per regex and was measured at ~2.3x the full-scan cost.
        #    A line with an unambiguous human-agency signal keeps its filenames
        #    (see STRONG_ACTOR_RE) so a filename can still supply the imperative.
        scan = raw if STRONG_ACTOR_RE.search(raw) else _neutralize_filenames(raw)
        actor[i] = _has_actor(scan)
        imper[i] = _has_imperative(scan)

    flagged: set[int] = set()
    # Same-line co-occurrence.
    for i in range(n):
        if actor[i] and imper[i]:
            flagged.add(i + 1)
    # Adjacent split: pair each non-blank line with the next non-blank line
    # (skipping blank lines), either ordering. Flag the actor-bearing line.
    content = [i for i in range(n) if lines[i].strip() != ""]
    for k in range(len(content) - 1):
        a, b = content[k], content[k + 1]
        if actor[a] and imper[b]:
            flagged.add(a + 1)
        elif imper[a] and actor[b]:
            flagged.add(b + 1)

    errors: list[str] = []
    if in_ignore:
        errors.append(
            f"unterminated `<!-- lint-infra-ignore start -->` region (opened at "
            f"line {ignore_start_line}); fail-closed — add a matching "
            f"`<!-- lint-infra-ignore end -->`."
        )
    if in_fence:
        errors.append(
            f"unterminated code fence (opened at line {fence_start_line}); "
            f"malformed markdown disables tail scanning — fail-closed."
        )
    return sorted(flagged), errors


def lint_file(path: Path) -> list[str]:
    """Return `path:line: ...` violation strings for a single file."""
    if "/archive/" in path.as_posix():
        return []
    try:
        text = path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as exc:  # pragma: no cover - defensive
        return [f"{path}: ERROR reading file: {exc}"]
    flagged, errors = scan_text(text)
    out: list[str] = []
    for ln in flagged:
        out.append(
            f"{path}:{ln}: prescribes a human-run infra step "
            f"(actor + terraform/SSH/reboot/verify-on-private-net imperative "
            f"co-occur). Route it through CI / Inngest / a workflow_dispatch, "
            f"or wrap deferred-orchestrator prose in a "
            f"`<!-- lint-infra-ignore start -->` … `<!-- lint-infra-ignore end -->` "
            f"region. See hr-no-ssh-fallback-in-runbooks."
        )
    for e in errors:
        out.append(f"{path}: {e} See hr-no-ssh-fallback-in-runbooks.")
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


def changed_files(base_ref: str) -> list[Path] | None:
    """Files changed vs `base_ref` + new untracked files, under scan dirs.

    Returns None on a git error (fail-closed → the caller exits 2)."""
    diff = _git(["diff", "--name-only", base_ref, "--"])
    if diff.returncode != 0:
        return None
    names: set[str] = {n for n in diff.stdout.splitlines() if n}
    # Untracked new docs (not yet in any commit) still count as "changed".
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

    errors: list[str] = []
    for f in files:
        errors.extend(lint_file(f))

    if errors:
        for e in errors:
            print(e, file=sys.stderr)
        print(
            f"\nFAIL: {len(errors)} prescribed human-run infra step(s) / "
            f"structural error(s). Non-technical Soleur users act only through "
            f"the web app / CI — automate the step or wrap deferred-orchestrator "
            f"prose in a lint-infra-ignore region.",
            file=sys.stderr,
        )
        return 1
    print(f"OK: no human-run infra steps in {len(files)} scanned file(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
