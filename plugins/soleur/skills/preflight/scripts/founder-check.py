#!/usr/bin/env python3
"""preflight Check 13 -- founder-stated check helper (#9578, ADR-274).

A founder states, in plain words, what proves a piece of work is done. The plan stores it as a
`founder_check:` block under `## Acceptance Criteria`; a freeze commit pins it; a step other than
`work` runs it. This file holds every DECISION in that flow so the decisions are testable and
exist in exactly one place. It never executes the founder's command and carries no sandbox:
the command runs only inside preflight Step 10.5, driven by the Check 13 wrapper.

File-based interface. Text a plan author controls (the command, the expected text, the override
reason) is never typed into a host shell word: `verify` writes its decision record to a file
(`--out`) and the command to another (`--command-out`); `classify` and `log` read the record back
(`--verify-json`) and take only MEASURED inputs (an rc, a stdout file, the health-control rc).
The one free-text value a founder types, an override reason, arrives on stdin through a quoted
heredoc (`--reason-stdin`).

Subcommands
  verify      resolve the plan, parse the block, compare it with its freeze copy, anchor authorship
  classify    pure verdict over (verify record, rc, stdout file, health-control rc, polarity)
  log         append one row to the founder-check log (the only writer of outcomes)
  commit-log  stage and commit the log in one commit (`founder-check: log`)
  summary     print `founder-check: <N> rows` (the layer-7 probe)
  text        print one pinned wording constant (`text --list` names them all)

Honest limits, restated where they matter and in ADR-274: this is tamper-EVIDENT, not
tamper-proof. The authorship anchor compares identity strings the operator's own agent can also
write, `--mode headless` is declared by the caller, and history rewriting is not stopped. A pin
fixes the bytes of the script a command names, never what that script loads. `hash:` is an
identity shown in the log; the freeze-commit comparison is the integrity control.
"""
import argparse
import datetime
import hashlib
import json
import os
import re
import shlex
import stat
import subprocess
import sys
from typing import NamedTuple

PLANS_DIR = "knowledge-base/project/plans"
SPECS_DIR = "knowledge-base/project/specs"
LOG_NAME = "founder-check-log.md"
MAX_PLAN_BYTES = 1 << 20
REFREEZE_PREFIX = "plan: re-freeze founder-stated check"
LOG_COMMIT_MESSAGE = "founder-check: log"

CANONICAL_FIELDS = ("kind", "text", "command", "expected", "pins", "approved_by", "approved_at")
ALLOWED_KEYS = frozenset(CANONICAL_FIELDS) | {"hash"}
KINDS = ("command", "judgement")
INTERPRETERS = ("bash", "python3", "node", "bun")
SCRIPT_EXTS = (".sh", ".py", ".js", ".mjs", ".cjs", ".ts", ".awk")
# Options that make a non-interpreter verb run a program the work could have written.
DENIED_OPTIONS = {"git": ("-c", "--config-env", "--exec-path"), "rg": ("--pre",), "curl": ("-K", "--config")}

# Outcomes only an interactive founder can produce. The headless log refuses them.
HEADLESS_REFUSED = frozenset({"OVERRIDDEN", "FOUNDER-CONFIRMED"})
# Outcomes that stop a headless run: nobody is there to ask, and an agent never decides.
HEADLESS_STOPS = frozenset(
    {"FAILED", "INVALID", "CHANGED-SINCE-APPROVAL", "UNTRUSTED", "NEEDS-YOUR-EYES", "BLOCK-REJECTED"}
)
# What an override can be overriding. Strict, so a row always names its cause.
OVERRIDE_CAUSES = ("FAILED", "INVALID", "CHANGED-SINCE-APPROVAL", "BLOCK-REJECTED")

OUTCOMES = (
    "PASSED", "FAILED", "FAILED-AS-EXPECTED", "VACUOUS", "INVALID", "SKIP-NOSANDBOX",
    "NEEDS-YOUR-EYES", "FOUNDER-CONFIRMED", "OVERRIDDEN", "UNTRUSTED", "CHANGED-SINCE-APPROVAL",
    "BLOCK-REJECTED", "STOPPED-AWAITING-FOUNDER",
)
STOP_CAUSES = {
    "FAILED": "it did not pass",
    "INVALID": "it could not run properly",
    "CHANGED-SINCE-APPROVAL": "it changed after you approved it",
    "UNTRUSTED": "you did not write it",
    "NEEDS-YOUR-EYES": "it needs your own eyes on the result",
    "BLOCK-REJECTED": "it could not be used as written",
    "SKIP-NOSANDBOX": "it could not run on this computer",
}

# Wording is a contract (CLO-reviewed, pinned by tests). Never claim more than "ran against the
# sha, finished without an error and printed the expected text". No string uses the words
# "verified", "proven" or "safe" (the CLO ruled the old negation exemption out, #9578). Every
# founder-facing sentence the references print lives here; the references only name the key.
WORDING = {
    "pass": (
        "Your check passed. This shows only that the check you wrote ran against {sha}, "
        "finished without an error and, if you set an expected result, printed it. It does not "
        "show that the work is correct or complete, or free of problems this check does not look "
        "for. Review the result before relying on it."
    ),
    "judgement": "You confirmed this by looking. No command ran for it.",
    "first-use": (
        "A vague, wrong or risky check can pass broken work or run actions you did not intend. "
        "Read what will run before it runs. The check runs on this computer in a limited "
        "environment that can still use your network connection, reach this computer's own "
        "services and read every file in this project folder, including files you have not "
        "committed. One check does not cover everything. The text and command you approve are "
        "committed to this repository, which may be public, so do not put passwords or keys in "
        "them."
    ),
    "capture-question": "What would you check to know this is done?",
    "approval-ask": (
        "Approve exactly this check as written? Say yes to approve it, or tell me what to change."
    ),
    "no-block": (
        "No founder-stated check guarded this ship. Nothing was run on your behalf."
    ),
    "no-sandbox": "Your check did not run on this computer, so nothing was checked.",
    "failed-ask": "Your check did not pass. How should this proceed?",
    "invalid-ask": (
        "Your check could not run properly, so it says nothing about your work. How should this "
        "proceed?"
    ),
    "changed-ask": "The check you approved has changed since you approved it. How should this proceed?",
    "rejected-ask": "Your check could not be used as written: {detail} How should this proceed?",
    "untrusted-fail": (
        "This check was not written by you, so it was not run. The command and who wrote it are "
        "shown above. To use a check, state your own, or run this one by hand."
    ),
    "eyes-ask": "Does this meet what you stated?",
    "reason-prompt": (
        "In one line, why are you continuing? This is saved in the repository log, which may be "
        "public, so do not put passwords or keys in it."
    ),
    "overridden-failed": "Founder check did not pass and you chose to continue: {reason}",
    "overridden-invalid": (
        "Founder check could not run properly, so it checked nothing, and you chose to continue: {reason}"
    ),
    "overridden-changed": (
        "Founder check changed after you approved it, so it was not run, and you chose to continue: {reason}"
    ),
    "overridden-rejected": (
        "Founder check could not be used as written, so it was not run, and you chose to continue: {reason}"
    ),
    "headless-stop": (
        "Your check was stopped because {cause}, and an unattended run cannot decide that for "
        "you. Run this step again with you present to retry, change the check or continue anyway."
    ),
    "baseline-ok": (
        "Your check fails today, as it should before the work. This shows only that the check can "
        "fail. It does not show that it checks what you care about."
    ),
    "baseline-vacuous": (
        "Your check already passes before any work is done, so it cannot tell you whether the "
        "work is done."
    ),
    "aggregate-judgement": "Founder check: you confirmed this by looking. No command ran.",
    "aggregate-pass": "Founder check: ran, returned success against {sha}",
}

LOG_COLUMNS = (
    "kind", "polarity", "command", "rc", "outcome", "underlying", "attempt_n", "tested_sha",
    "block_hash", "time_utc", "expected_matched", "reason",
)

# Step 10.5's shell-active reject set, applied at verify so a block carrying one is refused before
# anything is shown or run. The sandbox is the control; this is the early, legible refusal.
_SHELL_ACTIVE = re.compile(r"\$\(|`|<\(|>\(|;|&&|\|\||\||>|<|&|\$\{?[A-Za-z_]")
_SUBSTITUTION = re.compile(r"\$\(|`|\$\{|<\(|>\(")
_CONTROL = re.compile("[\x00-\x1f\x7f  ]")
_HARD_CONTROL = re.compile("[\x00-\x08\x0b-\x1f\x7f  ]")  # text may keep \t and \n
_SECRET_SHAPES = (
    re.compile(r"(?i)\bbearer[ \t]+[A-Za-z0-9._~+/=-]{8,}"),
    re.compile(r"(?i)\bauthorization[ \t]*:"),
    re.compile(r"\b(?:ghp|gho|ghs|ghu|github_pat|glpat|sk|pk|rk|xox[abpr])[_-][A-Za-z0-9_-]{16,}"),
    re.compile(r"\bAKIA[0-9A-Z]{16}\b"),
    re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----"),
    re.compile(r"://[^/\s:@]+:[^/\s@]+@"),
    re.compile(r"(?:^|\s)-u[ \t]*\S+:\S+"),
    re.compile(r"(?i)\b(?:password|passwd|secret|api[_-]?key|token)\b[ \t]*[=:][ \t]*\S{6,}"),
)
_HEX = re.compile(r"[0-9a-f]{40}|[0-9a-f]{64}")


class ParseError(Exception):
    pass


# ---------------------------------------------------------------------------------------------
# git. The two subprocess call sites in this file are _git and _verb_gate; Guard 4 pins them by
# walking the AST, not by grepping spellings.
# ---------------------------------------------------------------------------------------------
_LAST_ERR = ""


def _git(args, cwd):
    global _LAST_ERR
    r = subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True, errors="replace")
    _LAST_ERR = (r.stderr or "").strip()
    return r.returncode, r.stdout


def _verb_gate(command):
    """The Step 10.4 verb gate, handed the command as DATA. It is a validator and does not run it."""
    gate = os.path.join(os.path.dirname(os.path.abspath(__file__)), "probe-verb-gate.sh")
    r = subprocess.run(["bash", gate, command], capture_output=True, text=True, errors="replace")
    return r.returncode, (r.stdout or "").strip()


def _out(args, cwd):
    rc, out = _git(args, cwd)
    return out if rc == 0 else None


# ---------------------------------------------------------------------------------------------
# Block extraction and parsing (stdlib only; the block shape is fixed and small).
# ---------------------------------------------------------------------------------------------
_FENCE = re.compile(r"^ {0,3}(`{3,}|~{3,})(.*)$")
_AC_HEADING = re.compile(r"^##[ \t]+Acceptance Criteria(?:[ \t].*)?$", re.I)


def extract_blocks(text):
    """Return the `founder_check:` fences found INSIDE an `## Acceptance Criteria` section.

    A heading that merely STARTS with "Acceptance Criteria" counts (`## Acceptance Criteria
    (testable)`), so a suffixed heading cannot hide a block. A block quoted under any other
    heading (a Design section, an ADR excerpt) is ignored, and so is any heading that sits inside a
    fence: only structure outside fences decides the section.
    """
    blocks = []
    in_fence = None  # (char, length)
    in_ac = False
    cur = None
    for line in text.splitlines():
        m = _FENCE.match(line)
        if in_fence is None:
            if m:
                in_fence = (m.group(1)[0], len(m.group(1)))
                cur = []
                continue
            if re.match(r"^##(?!#)[ \t]+", line):
                in_ac = bool(_AC_HEADING.match(line))
        else:
            if m and m.group(1)[0] == in_fence[0] and len(m.group(1)) >= in_fence[1] and not m.group(2).strip():
                body = cur or []
                first = next((x for x in body if x.strip()), "")
                if in_ac and re.match(r"^founder_check:[ \t]*$", first):
                    blocks.append(body)
                in_fence = None
                cur = None
            else:
                cur.append(line)
    return blocks


def _strip_comment(v):
    quote = None
    for i, ch in enumerate(v):
        if quote:
            if ch == quote:
                quote = None
        elif ch in "\"'":
            quote = ch
        elif ch == "#" and (i == 0 or v[i - 1] in " \t"):
            return v[:i].rstrip()
    return v.rstrip()


def _scalar(v):
    v = v.strip()
    if v.startswith('"'):
        if len(v) < 2 or not v.endswith('"'):
            raise ParseError("unterminated double-quoted scalar")
        try:
            return json.loads(v)
        except ValueError as e:
            raise ParseError(f"bad double-quoted scalar: {e}")
    if v.startswith("'"):
        if len(v) < 2 or not v.endswith("'"):
            raise ParseError("unterminated single-quoted scalar")
        return v[1:-1].replace("''", "'")
    if v.startswith("[") or v.startswith("{"):
        raise ParseError("nested collection where a scalar is required")
    return v


def _indent(line):
    return len(line) - len(line.lstrip(" "))


def parse_block(lines):
    """Parse a `founder_check:` block into a dict of its fields. Raises ParseError.

    Collections are accepted in block form only; the literal `[]` and `{}` stand for "none".
    """
    body = [ln.rstrip() for ln in lines]
    first = next((i for i, x in enumerate(body) if x.strip()), None)
    if first is None or not re.match(r"^founder_check:[ \t]*$", body[first]):
        raise ParseError("block does not start with founder_check:")
    rest = [x for x in body[first + 1:] if x.strip() and not x.lstrip().startswith("#")]
    if not rest:
        raise ParseError("empty block")
    base = _indent(rest[0])
    if base == 0:
        raise ParseError("block fields must be indented")
    fields, i = {}, 0
    while i < len(rest):
        ln = rest[i]
        if _indent(ln) != base:
            raise ParseError(f"unexpected indentation: {ln.strip()[:40]}")
        m = re.match(r"^ *([A-Za-z_][A-Za-z0-9_]*):(?:[ \t]+(.*))?$", ln)
        if not m:
            raise ParseError(f"not a key: value line: {ln.strip()[:40]}")
        key, val = m.group(1), _strip_comment(m.group(2) or "")
        if key in fields:
            raise ParseError(f"duplicate key {key}")
        i += 1
        if val == "":
            kids = []
            while i < len(rest) and _indent(rest[i]) > base:
                kids.append(rest[i])
                i += 1
            if not kids:
                fields[key] = ""
            else:
                mp = {}
                for k in kids:
                    km = re.match(r"^ *([^\s:][^:]*?):[ \t]+(.*)$", k)
                    if not km:
                        raise ParseError(f"not a mapping entry: {k.strip()[:40]}")
                    mp[km.group(1).strip()] = _scalar(_strip_comment(km.group(2)))
                fields[key] = mp
        elif val == "[]":
            fields[key] = []
        elif val == "{}":
            fields[key] = {}
        elif val.startswith("[") or val.startswith("{"):
            raise ParseError("only the literal [] and {} are accepted; write collections in block form")
        else:
            fields[key] = _scalar(val)
    return fields


def canonical(block):
    out = {}
    for k in CANONICAL_FIELDS:
        v = block.get(k)
        if k == "pins":
            v = dict(v) if isinstance(v, dict) else ({} if v in (None, "", []) else v)
        else:
            v = "" if v is None else v
        out[k] = v
    return out


def canonical_hash(canon):
    pins = canon["pins"]
    obj = dict(canon)
    if isinstance(pins, dict):
        obj["pins"] = {k: pins[k] for k in sorted(pins)}
    raw = json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()


def _tokens(command):
    try:
        return shlex.split(command)
    except ValueError:
        return None


def first_token(command):
    """The verb as bash resolves it: quotes and backslashes removed, as probe-verb-gate.sh does."""
    toks = _tokens(command)
    return toks[0] if toks else ""


def _secret_shaped(*values):
    return any(rx.search(v) for v in values if isinstance(v, str) for rx in _SECRET_SHAPES)


def static_problem(block):
    """A reason code when the block is not acceptable as written, else None. Never runs anything."""
    if "credentials_required" in block:
        return "credentials-required"
    for k in block:
        if k not in ALLOWED_KEYS:
            return "unknown-field"
    kind = block.get("kind", "")
    if kind not in KINDS:
        return "invalid-kind"
    for k in ("kind", "text", "command", "expected", "approved_by", "approved_at"):
        if not isinstance(block.get(k, ""), str):
            return "unparseable"
    pins = block.get("pins", {})
    if not isinstance(pins, dict):
        return "unparseable"
    for k, v in pins.items():
        if not isinstance(k, str) or not isinstance(v, str) or not _HEX.fullmatch(v):
            return "unparseable"
        key = k[2:] if k.startswith("./") else k
        if key.startswith("/") or ".." in key.split("/") or not key:
            return "unparseable"
    text, cmd, expected = block.get("text", ""), block.get("command", ""), block.get("expected", "")
    if not text.strip():
        return "missing-field"
    if _HARD_CONTROL.search(text) or _CONTROL.search(expected) or _CONTROL.search(block.get("approved_by", "")):
        return "control-character"
    if _secret_shaped(text, cmd, expected):
        return "secret-shape"
    if kind == "judgement":
        return None
    if not cmd.strip():
        return "missing-field"
    if _CONTROL.search(cmd):
        return "control-character"
    if _SHELL_ACTIVE.search(cmd) or _SUBSTITUTION.search(expected):
        return "shell-active-token"
    rc, _msg = _verb_gate(cmd)
    if rc == 1:
        return "verb-gate"
    if rc != 0:
        return "verb-gate-unavailable"
    toks = _tokens(cmd)
    if not toks:
        return "unparseable"
    verb = toks[0]
    if verb in INTERPRETERS:
        operands = toks[1:]
        if not operands:
            return "script-operand-required"
        first = operands[0]
        if first.startswith("-"):
            return "interpreter-option"
        if first.startswith("/"):
            return "absolute-script-path"
        if ".." in first.split("/"):
            return "script-path-traversal"
        if "/" not in first and not first.endswith(SCRIPT_EXTS):
            return "script-operand-required"
        key = first[2:] if first.startswith("./") else first
        normalised = {(k[2:] if k.startswith("./") else k) for k in pins}
        if key not in normalised:
            return "unpinned-script"
    else:
        for opt in DENIED_OPTIONS.get(verb, ()):
            for t in toks[1:]:
                if t == opt or t.startswith(opt + "=") or (verb == "git" and opt == "-c" and t.startswith("-c") and not t.startswith("--")):
                    return "dangerous-option"
    return None


# ---------------------------------------------------------------------------------------------
# verify
# ---------------------------------------------------------------------------------------------
class _Emitter:
    def __init__(self, a):
        self.command_out = a.command_out
        self.out = a.out
        self.extra = {}

    def __call__(self, outcome, **kw):
        doc = {"outcome": outcome}
        doc.update(self.extra)
        doc.update(kw)
        if outcome == "NO-BLOCK":
            doc["banner"] = WORDING["no-block"]
        block = doc.get("block")
        if isinstance(block, dict):
            doc["kind"] = block.get("kind", "")
            doc["first_token"] = first_token(block.get("command", "")) if block.get("kind") == "command" else ""
            if self.command_out:
                # The raw command goes to a FILE so the Check 13 wrapper never has to quote it into
                # a shell word. Written for every outcome that parsed a block: an UNTRUSTED or
                # CHANGED block must be SHOWN to the founder before anyone decides.
                with open(self.command_out, "w", encoding="utf-8") as fh:
                    fh.write(block.get("command", ""))
        line = json.dumps(doc, sort_keys=True)
        if self.out:
            with open(self.out, "w", encoding="utf-8") as fh:
                fh.write(line + "\n")
        print(line)
        return 0 if outcome in ("OK", "NO-BLOCK") else 1


def _blocks_at(repo, rev, path):
    text = _out(["show", f"{rev}:{path}"], repo)
    if text is None or len(text) > MAX_PLAN_BYTES:
        return []
    return extract_blocks(text)


def _operator_email(repo):
    out = _out(["var", "GIT_AUTHOR_IDENT"], repo)
    m = re.search(r"<([^>]*)>", out or "")
    return m.group(1).strip().lower() if m else ""


def _read_plan(top, rel):
    """Read a plan the safe way: lstat first, never follow a link, never open a non-regular file,
    stay inside the plans directory, and cap the read. Returns (status, text)."""
    full = os.path.join(top, rel)
    plans_root = os.path.realpath(os.path.join(top, PLANS_DIR))
    try:
        st = os.lstat(full)
    except FileNotFoundError:
        return "missing", ""
    except OSError:
        return "unreadable", ""
    if stat.S_ISLNK(st.st_mode):
        return "symlink", ""
    if not stat.S_ISREG(st.st_mode):
        return "not-regular", ""
    if not os.path.realpath(full).startswith(plans_root + os.sep):
        return "outside", ""
    if st.st_size > MAX_PLAN_BYTES:
        return "too-large", ""
    try:
        fd = os.open(full, os.O_RDONLY | os.O_NONBLOCK | getattr(os, "O_NOFOLLOW", 0))
        with os.fdopen(fd, "rb") as fh:
            data = fh.read(MAX_PLAN_BYTES + 1)
    except OSError:
        return "unreadable", ""
    if len(data) > MAX_PLAN_BYTES:
        return "too-large", ""
    return "ok", data.decode("utf-8", errors="replace")


_ARCHIVE_PREFIX = re.compile(r"^\d{8}-\d{6}-")


def _plan_key(path):
    """A plan archived by compound (`plans/archive/<ts>-<name>.md`) is the SAME plan as `plans/<name>.md`."""
    arch = PLANS_DIR + "/archive/"
    if path.startswith(arch):
        return PLANS_DIR + "/" + _ARCHIVE_PREFIX.sub("", path[len(arch):])
    return path


def _branch(repo):
    b = (_out(["rev-parse", "--abbrev-ref", "HEAD"], repo) or "").strip()
    return b if b and b != "HEAD" else ""


def _safe_branch(b):
    return bool(b) and all(re.fullmatch(r"[A-Za-z0-9._-]+", s) and s not in (".", "..") for s in b.split("/"))


def _spec_dirs(top, branch):
    """The live spec directory, then any archived copy (compound moves it after the feature)."""
    live = os.path.join(top, SPECS_DIR, branch)
    arch_root = os.path.join(top, SPECS_DIR, "archive")
    archived = []
    if os.path.isdir(arch_root):
        archived = sorted(
            (os.path.join(arch_root, d) for d in os.listdir(arch_root) if _ARCHIVE_PREFIX.sub("", d) == branch),
            reverse=True,
        )
    return [live, *archived]


def _log_path(top, branch):
    if not _safe_branch(branch):
        return None
    dirs = _spec_dirs(top, branch)
    for d in dirs:
        if os.path.isfile(os.path.join(d, LOG_NAME)):
            return os.path.join(d, LOG_NAME)
    for d in dirs[1:]:
        if os.path.isdir(d):
            return os.path.join(d, LOG_NAME)
    return os.path.join(dirs[0], LOG_NAME)


def _tasks_plan(top, branch):
    """The plan a branch's tasks.md names (`Plan: <path>`), so a plan already merged to main is found."""
    if not _safe_branch(branch):
        return None
    for d in _spec_dirs(top, branch):
        status, text = "missing", ""
        p = os.path.join(d, "tasks.md")
        if os.path.isfile(p) and not os.path.islink(p) and os.path.getsize(p) <= MAX_PLAN_BYTES:
            with open(p, encoding="utf-8", errors="replace") as fh:
                text = fh.read()
            m = re.search(r"^[ \t]*(?:[-*][ \t]+)?\*{0,2}Plan:\*{0,2}[ \t]*`?(knowledge-base/project/plans/[^\s`]+\.md)`?", text, re.M)
            if m:
                return m.group(1)
    return None


def _history(repo, merge_base):
    """One `git log` pass: every branch commit with its author, subject and name-status changes."""
    rc, out = _git(
        ["-c", "core.quotepath=false", "log", "--reverse", "--topo-order", "--name-status", "-M",
         "--format=%x01%H%x01%ae%x01%s", f"{merge_base}..HEAD"],
        repo,
    )
    commits = []
    if rc != 0:
        return commits
    for ln in out.splitlines():
        if ln.startswith("\x01"):
            _, sha, email, subj = (ln.split("\x01") + ["", "", "", ""])[:4]
            commits.append({"sha": sha, "email": email.strip().lower(), "subject": subj, "changes": []})
        elif ln.strip() and commits:
            parts = ln.split("\t")
            st = parts[0]
            if st[:1] in ("R", "C") and len(parts) >= 3:
                commits[-1]["changes"].append((st[:1], parts[1], parts[2]))
            elif len(parts) >= 2:
                commits[-1]["changes"].append((st[:1], "", parts[1]))
    return commits


def _pin_blob(repo, rev, path):
    """(mode, blob) of `path` at `rev`, or ("", "") when absent."""
    out = _out(["ls-tree", rev, "--", path], repo) or ""
    m = re.match(r"^(\d+) \w+ ([0-9a-f]+)\t", out)
    return (m.group(1), m.group(2)) if m else ("", "")


def _head_dirty(repo):
    out = _out(["status", "--porcelain", "--untracked-files=normal"], repo) or ""
    return any(not ln[3:].strip('"').endswith(LOG_NAME) for ln in out.splitlines() if ln.strip())


def _default_bases(repo):
    ok = {"origin/main", "origin/master"}
    head = (_out(["symbolic-ref", "--short", "refs/remotes/origin/HEAD"], repo) or "").strip()
    if head:
        ok.add(head)
    return ok


def _verify_candidate(emit, repo, path, lines, frozen):
    """Baseline mode: the block is not frozen yet, so there is no freeze to compare with.

    Everything that can be decided from the block and the CURRENT tree still is: parse, the static
    rules, every pin against HEAD's blob. The freeze commit follows a valid baseline run, never
    precedes it.
    """
    try:
        block = parse_block(lines)
    except ParseError as e:
        return emit("FAIL", reason="unparseable", plan=path, detail=str(e))
    canon = canonical(block)
    info = {"plan": path, "freeze_sha": "", "freeze_source": "candidate", "hash": canonical_hash(canon),
            "block": canon, "refreeze": bool(frozen)}
    problem = static_problem(block)
    if problem:
        return emit("FAIL", reason=problem, **info, detail="the candidate block is not acceptable as written")
    declared = block.get("hash")
    if declared and declared != info["hash"]:
        return emit("FAIL", reason="hash-mismatch", **info, detail="hash: does not match the block's own fields")
    for pth, sha in canon["pins"].items():
        pth = pth[2:] if pth.startswith("./") else pth
        mode, blob = _pin_blob(repo, "HEAD", pth)
        if mode not in ("100644", "100755") or blob != sha:
            return emit("FAIL", reason="pin-not-at-freeze", **info, detail=f"{pth} is not pinned to its blob in HEAD")
    return emit("OK", reason="candidate", **info, changed_fields=[], reasons=[], flags=[])


def cmd_verify(a):
    emit = _Emitter(a)
    repo = a.repo or os.getcwd()
    top = (_out(["rev-parse", "--show-toplevel"], repo) or "").strip()
    if not top:
        return emit("FAIL", reason="not-a-repository", detail="verify must run inside the repository")
    repo = top
    head_sha = (_out(["rev-parse", "HEAD"], repo) or "").strip()
    emit.extra.update({"head_sha": head_sha, "dirty": _head_dirty(repo) if head_sha else False,
                       "pr_author_checked": False})
    branch = _branch(repo)

    base = a.base[len("refs/remotes/"):] if a.base.startswith("refs/remotes/") else a.base
    if base not in _default_bases(repo):
        return emit("FAIL", reason="base-not-default-branch",
                    detail=f"--base {a.base} is not the remote default branch, so it cannot anchor a freeze")
    merge_base = (_out(["merge-base", base, "HEAD"], repo) or "").strip()

    cands = set()
    for p in (a.plan or []):
        full = p if os.path.isabs(p) else os.path.join(repo, p)
        rel = os.path.relpath(full, repo) if os.path.commonpath([os.path.realpath(repo), os.path.dirname(os.path.realpath(full)) or "/"]) == os.path.realpath(repo) else full
        cands.add(rel)
    tp = _tasks_plan(repo, branch) if branch else None
    if tp:
        cands.add(tp)

    commits, evidence, refreeze, back = [], {}, {}, {}
    operator = _operator_email(repo)
    if merge_base:
        for args in (
            ["diff", "--name-only", merge_base, "HEAD", "--", PLANS_DIR],
            ["diff", "--name-only", "HEAD", "--", PLANS_DIR],
            ["ls-files", "--others", "--exclude-standard", "--", PLANS_DIR],
        ):
            cands.update(p for p in (_out(args, repo) or "").splitlines() if p.endswith(".md"))

        def resolve(p):
            for _ in range(1000):
                if p not in back:
                    break
                p = back[p]
            return _plan_key(p)

        commits = _history(repo, merge_base)
        for c in commits:
            for st, old, new in c["changes"]:
                if st == "R" and old:
                    back[new] = old
            for st, old, p in c["changes"]:
                if st == "D" or not (p.startswith(PLANS_DIR + "/") and p.endswith(".md")):
                    continue
                ident = resolve(p)
                if ident not in evidence and _blocks_at(repo, c["sha"], p):
                    evidence[ident] = {"sha": c["sha"], "path": p}
                if c["subject"].startswith(REFREEZE_PREFIX) and c["email"] == operator and _blocks_at(repo, c["sha"], p):
                    refreeze[resolve(p)] = {"sha": c["sha"], "path": p}
        cands.update(v["path"] for v in evidence.values() if os.path.lexists(os.path.join(repo, v["path"])))
    else:
        resolve = _plan_key  # noqa: F811 -- no history to follow
        # No merge-base: nothing names the plan, so look at every plan on disk. A block found this
        # way is FAIL base-unresolvable below; finding none is NO-BLOCK, so a repo that never used
        # the feature still ships.
        for args in (["ls-files", "--", PLANS_DIR], ["ls-files", "--others", "--exclude-standard", "--", PLANS_DIR]):
            cands.update(p for p in (_out(args, repo) or "").splitlines() if p.endswith(".md"))

    freeze_of = {}
    for p in cands:
        ident = resolve(p)
        if merge_base and _blocks_at(repo, merge_base, ident):
            freeze_of[ident] = {"sha": merge_base, "path": ident, "source": "merge-base"}
        elif ident in refreeze:
            freeze_of[ident] = {**refreeze[ident], "source": "refreeze"}
        elif ident in evidence:
            freeze_of[ident] = {**evidence[ident], "source": "branch"}
    for ident, ev in evidence.items():
        if ident not in freeze_of:
            freeze_of[ident] = {**(refreeze.get(ident) or ev), "source": "refreeze" if ident in refreeze else "branch"}

    heads = {}
    for p in sorted(cands):
        status, text = _read_plan(repo, p)
        if status == "missing":
            continue
        if status != "ok":
            reason = {
                "symlink": "symlinked-plan", "not-regular": "plan-not-regular", "outside": "plan-outside-plans-dir",
                "too-large": "unparseable", "unreadable": "plan-unreadable",
            }[status]
            return emit("FAIL", reason=reason, plan=p, detail=f"the plan is not read: {status.replace('-', ' ')}")
        blocks = extract_blocks(text)
        if len(blocks) > 1:
            return emit("FAIL", reason="multiple-blocks", plan=p, detail="more than one founder_check block under Acceptance Criteria")
        if blocks:
            heads[p] = blocks[0]

    if len(heads) > 1:
        return emit("FAIL", reason="multiple-plans", detail="more than one plan carries a founder_check block: " + ", ".join(sorted(heads)))

    if not merge_base:
        if heads:
            return emit("FAIL", reason="base-unresolvable",
                        detail=f"cannot resolve {a.base}, so a freeze cannot be located for the block in " + ", ".join(sorted(heads)))
        if a.candidate:
            return emit("FAIL", reason="no-block-candidate", detail="no founder_check block was found")
        return emit("NO-BLOCK", reason="no-block", base_note="base-unresolvable")

    if not heads:
        if a.candidate:
            return emit("FAIL", reason="no-block-candidate",
                        detail="no founder_check block under an Acceptance Criteria heading; check the heading and the fence")
        if freeze_of:
            return emit(
                "FAIL", reason="freeze-without-block",
                detail="a freeze exists in history for " + ", ".join(sorted(freeze_of)) + " but no block resolves at HEAD",
            )
        return emit("NO-BLOCK", reason="no-block")

    (path, lines), = heads.items()
    ident = resolve(path)
    if a.candidate:
        if ident in freeze_of and not a.refreeze:
            return emit("FAIL", reason="candidate-refused-frozen", plan=path,
                        detail="a freeze exists for this plan; a candidate run is only for a block that is not frozen (use --refreeze to re-freeze a changed check)")
        return _verify_candidate(emit, repo, path, lines, ident in freeze_of)
    stale = sorted(p for p in freeze_of if p != ident)
    if stale:
        return emit("FAIL", reason="freeze-without-block", plan=path, detail="a block was frozen at " + ", ".join(stale) + " and is not there at HEAD")
    if ident not in freeze_of:
        return emit("FAIL", reason="no-freeze", plan=path, detail="the block has no freeze commit; commit it before any code")
    fz = freeze_of[ident]
    freeze_sha, source = fz["sha"], fz["source"]

    try:
        head_block = parse_block(lines)
    except ParseError as e:
        return emit("FAIL", reason="unparseable", plan=path, detail=str(e))
    flines = (_blocks_at(repo, freeze_sha, fz["path"]) or [[]])[0]
    try:
        frozen_block = parse_block(flines)
    except ParseError as e:
        return emit("FAIL", reason="unparseable", plan=path, detail="freeze copy: " + str(e))

    head_c, frozen_c = canonical(head_block), canonical(frozen_block)
    head_hash, frozen_hash = canonical_hash(head_c), canonical_hash(frozen_c)
    freeze_author = (_out(["log", "-1", "--format=%ae", freeze_sha], repo) or "").strip().lower()
    base_info = {"plan": path, "freeze_sha": freeze_sha, "freeze_source": source, "hash": head_hash,
                 "block": head_c, "frozen": {k: frozen_c[k] for k in ("kind", "text", "command", "expected", "approved_by", "approved_at")},
                 "freeze_author": freeze_author, "refreeze": source == "refreeze"}

    problem = static_problem(frozen_block)
    if problem:
        return emit("FAIL", reason=problem, **base_info, detail="the frozen block is not acceptable as written")
    for blk, h in ((head_block, head_hash), (frozen_block, frozen_hash)):
        declared = blk.get("hash")
        if declared and declared != h:
            return emit("FAIL", reason="hash-mismatch", **base_info, detail="hash: does not match the block's own fields")

    # Pins are facts about the FREEZE tree: a regular file at exactly the pinned blob, never a link.
    for pth, sha in frozen_c["pins"].items():
        pth = pth[2:] if pth.startswith("./") else pth
        mode, blob = _pin_blob(repo, freeze_sha, pth)
        if mode not in ("100644", "100755") or blob != sha:
            return emit("FAIL", reason="pin-not-at-freeze", **base_info, detail=f"{pth} is not pinned to a regular file at its blob at the freeze")

    reasons, flags = [], []

    # Authorship anchor (Guard 3). A freeze reviewed on main needs none.
    if source in ("branch", "refreeze"):
        if not operator or freeze_author != operator:
            flags.append("freeze-author")
        if a.pr_author and a.operator_login:
            emit.extra["pr_author_checked"] = True
            if a.pr_author.lower() != a.operator_login.lower():
                flags.append("pr-author")
        elif not a.no_pr:
            flags.append("pr-author-unmeasurable")

    changed = [k for k in CANONICAL_FIELDS if head_c[k] != frozen_c[k]]
    if changed:
        reasons.append("field-changed")
    for pth, sha in frozen_c["pins"].items():
        pth = pth[2:] if pth.startswith("./") else pth
        full = os.path.join(repo, pth)
        if os.path.islink(full):
            reasons.append("pinned-script-changed")
            break
        rc, h = _git(["hash-object", "--", pth], repo)
        if rc != 0 or h.strip() != sha:
            reasons.append("pinned-script-changed")
            break
    if source == "branch":
        idx = {c["sha"]: n for n, c in enumerate(commits)}
        if freeze_sha in idx:
            for n, c in enumerate(commits):
                paths = [x for ch in c["changes"] for x in (ch[1], ch[2]) if x]
                if any(not x.startswith("knowledge-base/") for x in paths):
                    if idx[freeze_sha] >= n:
                        reasons.append("ordering")
                    break

    info = {**base_info, "changed_fields": changed, "reasons": reasons, "flags": flags}
    if flags:
        return emit("UNTRUSTED", reason="authorship", **info, detail="the freeze does not anchor to the local operator; the command is shown, never run")
    if reasons:
        return emit("CHANGED-SINCE-APPROVAL", reason=reasons[0], **info, detail="the approved text, a pinned script or the freeze ordering changed")
    return emit("OK", reason="ok", **info)


# ---------------------------------------------------------------------------------------------
# classify
# ---------------------------------------------------------------------------------------------
class Result(NamedTuple):
    outcome: str
    expected_matched: bool
    reason: str


def classify(rc, stdout, expected, polarity, first="", sandbox_healthy=True):
    """The one decision chokepoint, shared by baseline and acceptance polarity."""
    matched = (expected == "") or (expected in stdout)
    if not sandbox_healthy:
        return Result("INVALID", matched, "sandbox-unhealthy")
    if rc in (124, 126, 127):
        return Result("INVALID", matched, f"tooling-rc-{rc}")
    if first == "curl" and rc in (6, 7, 28):
        return Result("INVALID", matched, f"curl-rc-{rc}")
    if polarity == "baseline":
        if rc == 0 and matched:
            return Result("VACUOUS", matched, "baseline-passes")
        return Result("FAILED-AS-EXPECTED", matched, "baseline-fails")
    if rc == 0 and matched:
        return Result("PASSED", matched, "ran-returned-success")
    return Result("FAILED", matched, "non-zero-or-expected-absent")


def _read_capped(path):
    with open(path, "rb") as fh:
        data = fh.read(MAX_PLAN_BYTES + 1)
    if len(data) > MAX_PLAN_BYTES:
        raise ValueError("file larger than 1 MiB")
    return data.decode("utf-8", errors="replace")


def _load_json(path, what, digest=None):
    """Read a record file. `digest`, a list, receives the sha256 of exactly the text that was parsed."""
    try:
        text = _read_capped(path)
        doc = json.loads(text)
    except (OSError, ValueError) as e:
        print(f"refused: cannot read {what} {path}: {e}", file=sys.stderr)
        return None
    if not isinstance(doc, dict):
        print(f"refused: {what} {path} is not a JSON object", file=sys.stderr)
        return None
    if digest is not None:
        digest.append(hashlib.sha256(text.encode("utf-8")).hexdigest())
    return doc


def cmd_classify(a):
    dg = []
    v = _load_json(a.verify_json, "the verify record", dg)
    if v is None:
        return 2
    block = v.get("block") if isinstance(v.get("block"), dict) else {}
    if v.get("outcome") != "OK" or block.get("kind") != "command":
        print(f"refused: classify only runs on an OK verify of a command check (outcome={v.get('outcome')!s:.40}, kind={block.get('kind')!s:.20})", file=sys.stderr)
        return 2
    candidate = v.get("reason") == "candidate"
    if (a.polarity == "baseline") != candidate:
        print("refused: baseline polarity needs a --candidate verify record, acceptance needs a frozen one", file=sys.stderr)
        return 2
    approved = block.get("command", "")
    if not approved:
        print("refused: the verify record carries no command to classify a run of", file=sys.stderr)
        return 2
    try:
        ran = _read_capped(a.command_file)
    except (OSError, ValueError) as e:
        print(f"refused: cannot read --command-file: {e}", file=sys.stderr)
        return 2
    if ran != approved:
        print("refused: the command that ran is not the approved command in the verify record", file=sys.stderr)
        return 2
    stdout = ""
    if a.stdout_file:
        try:
            stdout = _read_capped(a.stdout_file)
        except (OSError, ValueError) as e:
            print(f"refused: cannot read --stdout-file: {e}", file=sys.stderr)
            return 2
    r = classify(a.rc, stdout, block.get("expected", ""), a.polarity, str(v.get("first_token", "")), a.control_rc == 0)
    doc = {"outcome": r.outcome, "expected_matched": r.expected_matched, "reason": r.reason,
           "rc": a.rc, "polarity": a.polarity, "hash": str(v.get("hash", "")),
           "head_sha": str(v.get("head_sha", "")), "verify_sha256": dg[0]}
    line = json.dumps(doc, sort_keys=True)
    if a.out:
        with open(a.out, "w", encoding="utf-8") as fh:
            fh.write(line + "\n")
    print(line)
    return 0


# ---------------------------------------------------------------------------------------------
# log / commit-log / summary / text
# ---------------------------------------------------------------------------------------------
def _cell(v):
    s = _CONTROL.sub(" ", str(v))
    return re.sub(r"\s+", " ", s).replace("\\", "\\\\").replace("|", "\\|").strip()


def _resolve_log(a):
    if a.log:
        return os.path.abspath(a.log)
    top = (_out(["rev-parse", "--show-toplevel"], os.getcwd()) or "").strip()
    return _log_path(top, _branch(top)) if top else None


CLASSIFY_OUTCOMES = frozenset({"PASSED", "FAILED", "INVALID", "FAILED-AS-EXPECTED", "VACUOUS"})


def _derivable(v, cl, polarity):
    """The outcomes the records allow a row to carry. `log` records a measurement, it does not
    choose one: an outcome no record supports is refused, whoever asks for it."""
    block = v.get("block") if isinstance(v.get("block"), dict) else {}
    vo = v.get("outcome")
    if vo == "UNTRUSTED":
        return {"UNTRUSTED"}
    if vo == "CHANGED-SINCE-APPROVAL":
        return {"CHANGED-SINCE-APPROVAL"}
    if vo == "FAIL":
        return {"BLOCK-REJECTED"}
    if vo != "OK":
        return set()
    if (polarity == "baseline") != (v.get("reason") == "candidate"):
        return set()
    if cl:
        return {cl["outcome"]}
    if block.get("kind") == "judgement":
        return {"NEEDS-YOUR-EYES", "FOUNDER-CONFIRMED", "FAILED"} if polarity == "acceptance" else {"NEEDS-YOUR-EYES"}
    # a command that never produced an rc: no sandbox, a refused token, or an unreadable wrapper result
    return {"SKIP-NOSANDBOX", "INVALID", "BLOCK-REJECTED"}


def cmd_log(a):
    dg = []
    v = _load_json(a.verify_json, "the verify record", dg)
    if v is None:
        return 2
    cl = {}
    if a.classify_json:
        cl = _load_json(a.classify_json, "the classify record")
        if cl is None:
            return 2
        if (cl.get("outcome") not in CLASSIFY_OUTCOMES or cl.get("polarity") != a.polarity
                or cl.get("verify_sha256") != dg[0] or cl.get("hash") != str(v.get("hash", ""))
                or cl.get("head_sha") != str(v.get("head_sha", ""))):
            print("refused: the classify record does not belong to this verify record and polarity", file=sys.stderr)
            return 3
    block = v.get("block") if isinstance(v.get("block"), dict) else {}
    h = str(v.get("hash", ""))
    sha = str(v.get("head_sha", ""))
    if (h and not re.fullmatch(r"[0-9a-f]{64}", h)) or (sha and not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", sha)):
        print("refused: the verify record carries a hash or sha that is not hex", file=sys.stderr)
        return 3
    outcome, underlying = a.outcome, a.underlying or ""
    reason = ""
    if a.reason_stdin:
        reason = sys.stdin.read(600).strip()
    if a.mode == "headless":
        if outcome in HEADLESS_REFUSED:
            print(f"refused: {outcome} is an interactive-only outcome; a headless run cannot record it", file=sys.stderr)
            return 3
        if outcome in HEADLESS_STOPS or (outcome == "SKIP-NOSANDBOX" and block):
            underlying, outcome = outcome, "STOPPED-AWAITING-FOUNDER"
    allowed = _derivable(v, cl, a.polarity)
    measured = underlying if outcome in ("OVERRIDDEN", "STOPPED-AWAITING-FOUNDER") else outcome
    if measured not in allowed:
        print(f"refused: the records do not support recording {measured or 'this outcome'} here", file=sys.stderr)
        return 3
    if outcome == "OVERRIDDEN":
        if not reason:
            print("refused: an override needs a one-line reason", file=sys.stderr)
            return 3
        if underlying not in OVERRIDE_CAUSES:
            print(f"refused: an override names what it overrides: --underlying {'|'.join(OVERRIDE_CAUSES)}", file=sys.stderr)
            return 3
    if reason and _secret_shaped(reason):
        print("refused: the reason looks like it holds a secret; the log is committed and may be public", file=sys.stderr)
        return 3
    frozen = v.get("frozen") if isinstance(v.get("frozen"), dict) else {}
    cmd = str(block.get("command", ""))
    if frozen.get("command") and frozen.get("command") != cmd:
        reason = (reason + " | frozen command: " + str(frozen["command"])).strip(" |")
    tested = sha[:12] + ("+uncommitted" if v.get("dirty") else "") if sha else ""
    row = {
        "kind": block.get("kind", ""), "polarity": a.polarity, "command": cmd,
        "rc": "" if cl.get("rc") is None else cl.get("rc"), "outcome": outcome, "underlying": underlying,
        "attempt_n": a.attempt_n if a.attempt_n is not None else "", "tested_sha": tested, "block_hash": h,
        "time_utc": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "expected_matched": "" if cl.get("expected_matched") is None else str(bool(cl.get("expected_matched"))).lower(),
        "reason": reason,
    }
    path = _resolve_log(a)
    if not path:
        print("refused: no log path (detached HEAD or an unsafe branch name); pass --log", file=sys.stderr)
        return 3
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fresh = not os.path.exists(path) or os.path.getsize(path) == 0
    with open(path, "a", encoding="utf-8") as fh:
        if fresh:
            fh.write("| " + " | ".join(LOG_COLUMNS) + " |\n")
            fh.write("| " + " | ".join("---" for _ in LOG_COLUMNS) + " |\n")
        fh.write("| " + " | ".join(_cell(row[c]) for c in LOG_COLUMNS) + " |\n")
    print(f"SOLEUR_FOUNDER_CHECK_RESULT outcome={outcome} hash={h} tested_sha={sha[:12]}")
    return 0


def cmd_commit_log(a):
    top = (_out(["rev-parse", "--show-toplevel"], os.getcwd()) or "").strip()
    path = _resolve_log(a) if (a.log or top) else None
    if not top or not path or not os.path.isfile(path):
        print("founder-check: no log to commit")
        return 0
    rel = os.path.relpath(path, top)
    rc, status = _git(["status", "--porcelain", "--", rel], top)
    if rc == 0 and not status.strip():
        print("founder-check: log already committed")
        return 0
    rc, _o = _git(["add", "--", rel], top)
    if rc == 0:
        rc, _o = _git(["commit", "-q", "-m", LOG_COMMIT_MESSAGE, "--", rel], top)
    if rc != 0:
        print(f"founder-check: could not commit the log: {_LAST_ERR[:200]}", file=sys.stderr)
        return 1
    print(f"founder-check: committed {rel}")
    return 0


def _log_rows(path):
    with open(path, encoding="utf-8", errors="replace") as fh:
        lines = [ln.rstrip("\n") for ln in fh if ln.startswith("|")]
    sep = re.compile(r"^\|[\s:|-]*$")
    rows = []
    for i, ln in enumerate(lines):
        if sep.match(ln):
            continue
        if i + 1 < len(lines) and sep.match(lines[i + 1]):
            continue
        rows.append(ln)
    return rows


def cmd_summary(a):
    path = a.log if a.log else _resolve_log(a)
    if not path or not os.path.isfile(path):
        if a.log:
            print(f"founder-check: log not found: {_cell(a.log)}", file=sys.stderr)
            return 1
        print("founder-check: no log")
        return 0
    print(f"founder-check: {len(_log_rows(path))} rows")
    return 0


def cmd_text(a):
    if a.list:
        print("\n".join(sorted(WORDING)))
        return 0
    if not a.name:
        print("text: a name or --list is required", file=sys.stderr)
        return 2
    v = {}
    if a.verify_json:
        v = _load_json(a.verify_json, "the verify record") or {}
    sha = a.sha
    if v.get("head_sha"):
        sha = str(v["head_sha"])[:12] + (" plus uncommitted changes" if v.get("dirty") else "")
    detail = _CONTROL.sub(" ", str(v.get("detail", "")))
    cause = STOP_CAUSES.get(a.underlying, "it could not be used")
    print(WORDING[a.name].format(sha=sha, reason=a.reason, cause=cause, detail=detail))
    return 0


# ---------------------------------------------------------------------------------------------
def build_parser():
    p = argparse.ArgumentParser(prog="founder-check.py", description=__doc__.split("\n")[0], allow_abbrev=False)
    sub = p.add_subparsers(dest="cmd", required=True)

    v = sub.add_parser("verify", allow_abbrev=False)
    v.add_argument("--base", default="origin/main")
    v.add_argument("--repo")
    v.add_argument("--plan", action="append")
    v.add_argument("--pr-author")
    v.add_argument("--operator-login")
    v.add_argument("--no-pr", action="store_true", help="no pull request exists yet, so there is no PR author to compare")
    v.add_argument("--out", help="write the decision record (one JSON line) to this file")
    v.add_argument("--command-out", help="write the block's raw command text to this file")
    v.add_argument("--candidate", action="store_true", help="baseline mode: validate a block that has no freeze commit yet")
    v.add_argument("--refreeze", action="store_true", help="with --candidate: baseline a deliberately changed check")
    v.set_defaults(fn=cmd_verify)

    c = sub.add_parser("classify", allow_abbrev=False)
    c.add_argument("--verify-json", required=True)
    c.add_argument("--polarity", choices=("baseline", "acceptance"), required=True)
    c.add_argument("--rc", type=int, required=True)
    c.add_argument("--control-rc", type=int, required=True, help="rc of the `true` health-control run through the same wrapper")
    c.add_argument("--command-file", required=True, help="the command text the wrapper actually ran; it must equal the approved command")
    c.add_argument("--stdout-file")
    c.add_argument("--out")
    c.set_defaults(fn=cmd_classify)

    g = sub.add_parser("log", allow_abbrev=False)
    g.add_argument("--log")
    g.add_argument("--mode", choices=("interactive", "headless"), required=True)
    g.add_argument("--outcome", choices=OUTCOMES, required=True)
    g.add_argument("--polarity", choices=("baseline", "acceptance"), required=True)
    g.add_argument("--verify-json", required=True)
    g.add_argument("--classify-json")
    g.add_argument("--attempt-n", type=int)
    g.add_argument("--underlying", choices=OVERRIDE_CAUSES)
    g.add_argument("--reason-stdin", action="store_true", help="read the founder's one-line reason from stdin")
    g.set_defaults(fn=cmd_log)

    k = sub.add_parser("commit-log", allow_abbrev=False)
    k.add_argument("--log")
    k.set_defaults(fn=cmd_commit_log)

    s = sub.add_parser("summary", allow_abbrev=False)
    s.add_argument("--log")
    s.set_defaults(fn=cmd_summary)

    t = sub.add_parser("text", allow_abbrev=False)
    t.add_argument("name", nargs="?", choices=sorted(WORDING))
    t.add_argument("--list", action="store_true")
    t.add_argument("--verify-json")
    t.add_argument("--sha", default="<sha>")
    t.add_argument("--reason", default="<reason>")
    t.add_argument("--underlying", choices=tuple(STOP_CAUSES))
    t.set_defaults(fn=cmd_text)
    return p


_OUTPUT_FLAGS = ("--out", "--command-out")


def _clear_outputs(argv):
    """Remove the files a run is about to write, BEFORE argument parsing. A stale decision record or
    command file from an earlier run must never survive a run that dies early (a usage error, a
    crash): an absent file is a refusal downstream, a stale one is somebody else's verdict."""
    if not argv or argv[0] not in ("verify", "classify"):
        return
    paths = []
    for i, tok in enumerate(argv[1:], 1):
        for flag in _OUTPUT_FLAGS:
            if tok == flag and i + 1 < len(argv):
                paths.append(argv[i + 1])
            elif tok.startswith(flag + "="):
                paths.append(tok[len(flag) + 1:])
    for p in paths:
        try:
            if os.path.islink(p) or os.path.isfile(p):
                os.unlink(p)
        except OSError:
            pass


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    _clear_outputs(argv)
    args = build_parser().parse_args(argv)
    try:
        return args.fn(args)
    except Exception as e:  # a traceback is an unreadable verdict: print a one-line FAIL and a distinct rc
        line = json.dumps({"outcome": "FAIL", "reason": "internal-error", "detail": f"{type(e).__name__}: {str(e)[:120]}"})
        out = getattr(args, "out", None)
        if out:
            try:
                with open(out, "w", encoding="utf-8") as fh:
                    fh.write(line + "\n")
            except OSError:
                pass
        print(line)
        return 4


if __name__ == "__main__":
    sys.exit(main())
