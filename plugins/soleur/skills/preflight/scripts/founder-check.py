#!/usr/bin/env python3
"""preflight Check 13 -- founder-stated check helper (#9578, ADR-274).

A founder states, in plain words, what proves a piece of work is done. The plan stores it as a
`founder_check:` block under `## Acceptance Criteria`; a freeze commit pins it; a step other than
`work` runs it. This file holds every DECISION in that flow so the decisions are testable and
exist in exactly one place. It never executes the founder's command and carries no sandbox:
the command runs only inside preflight Step 10.5, driven by the Check 13 wrapper.

Subcommands
  verify    resolve the plan, parse the block, compare it with its freeze copy, anchor authorship
  classify  pure verdict over (rc, stdout, expected, polarity, creates, target_present, health)
  log       append one row to the founder-check log (the only writer of outcomes)
  summary   print `founder-check: <N> rows` / `founder-check: no log` (the layer-7 probe)
  text      print one pinned wording constant

Honest limits, restated where they matter and in ADR-274: this is tamper-EVIDENT, not
tamper-proof. The authorship anchor compares identity strings the operator's own agent can also
write; history rewriting is not stopped. `hash:` is an identity shown in the log, never the
integrity control -- the freeze-commit comparison is.
"""
import argparse
import datetime
import hashlib
import json
import os
import re
import shlex
import subprocess
import sys
from typing import NamedTuple

PLANS_DIR = "knowledge-base/project/plans"
CANONICAL_FIELDS = ("kind", "text", "command", "expected", "creates", "pins")
ALLOWED_KEYS = frozenset(CANONICAL_FIELDS) | {"approved_by", "approved_at", "hash"}
KINDS = ("command", "judgement")
INTERPRETERS = ("bash", "python3", "node", "bun")
SCRIPT_EXTS = (".sh", ".py", ".js", ".mjs", ".cjs", ".ts", ".awk")

# Outcomes only an interactive founder can produce. The headless log refuses them.
HEADLESS_REFUSED = frozenset({"OVERRIDDEN", "FOUNDER-CONFIRMED"})
# Outcomes that stop a headless run: nobody is there to ask, and an agent never decides.
HEADLESS_STOPS = frozenset({"FAILED", "INVALID", "CHANGED-SINCE-APPROVAL", "UNTRUSTED", "NEEDS-YOUR-EYES"})

OUTCOMES = (
    "PASSED", "FAILED", "FAILED-AS-EXPECTED", "VACUOUS", "INVALID", "SKIP", "SKIP-NOSANDBOX",
    "NO-BLOCK", "NEEDS-YOUR-EYES", "FOUNDER-CONFIRMED", "OVERRIDDEN", "UNTRUSTED",
    "CHANGED-SINCE-APPROVAL", "STOPPED-AWAITING-FOUNDER",
)

# Wording is a contract (CLO-reviewed, pinned by tests). Never claim more than "ran against the
# sha, finished without an error and printed the expected text". No string uses the words
# "verified", "proven" or "safe" (the CLO ruled the old negation exemption out, #9578).
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
        "environment that can still use your network connection. One check does not cover "
        "everything. The text and command you approve are committed to this repository, which "
        "may be public, so do not put passwords or keys in them."
    ),
    "no-block": "No founder-stated check was defined. Nothing was run on your behalf.",
    "no-sandbox": "Your check did not run on this computer, so nothing was checked.",
    "no-sandbox-ask": (
        "Your check did not run on this computer, so nothing was checked. Continue without it?"
    ),
    "invalid-ask": (
        "Your check could not run properly, so it says nothing about your work. How should this "
        "proceed?"
    ),
    "aggregate-judgement": "Founder check: you confirmed this by looking. No command ran.",
    "overridden-line": "Founder check did not pass and you chose to continue: {reason}",
    "nosandbox-continued": (
        "Your check did not run on this computer, so it has not checked this work. You chose to "
        "continue."
    ),
    "headless-stop": (
        "Your check did not pass, could not run, or needs your decision, and an unattended run "
        "cannot decide that for you. Run this step again with you present to retry, change the "
        "check or continue anyway."
    ),
    "untrusted-ask": (
        "This check was not written by you. Running it executes the command shown above on this "
        "computer, in a limited environment that can still use your network connection. Run it?"
    ),
    "aggregate-pass": "Founder check: ran, returned success against {sha}",
}

LOG_COLUMNS = (
    "kind", "polarity", "command", "rc", "outcome", "underlying", "attempt_n", "tested_sha",
    "block_hash", "time_utc", "output_sha256", "expected_matched", "reason",
)


class ParseError(Exception):
    pass


# ---------------------------------------------------------------------------------------------
# git. The two subprocess call sites in this file are _git and _verb_gate; Guard 4 pins the count.
# ---------------------------------------------------------------------------------------------
def _git(args, cwd):
    r = subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True, errors="replace")
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


def extract_blocks(text):
    """Return the `founder_check:` fences found INSIDE a `## Acceptance Criteria` section.

    A block quoted under any other heading (a Design section, an ADR excerpt) is ignored, and so
    is any heading that sits inside a fence: only structure outside fences decides the section.
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
                in_ac = bool(re.match(r"^##[ \t]+Acceptance Criteria[ \t]*$", line, re.I))
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


def _split_flow(inner):
    parts, cur, quote = [], "", None
    for ch in inner:
        if quote:
            cur += ch
            if ch == quote:
                quote = None
        elif ch in "\"'":
            quote = ch
            cur += ch
        elif ch == ",":
            parts.append(cur)
            cur = ""
        else:
            cur += ch
    if quote:
        raise ParseError("unterminated quote in a flow collection")
    if cur.strip() or parts:
        parts.append(cur)
    return [p.strip() for p in parts if p.strip()]


def _flow_list(v):
    if not v.endswith("]"):
        raise ParseError("unterminated flow list")
    return [_scalar(p) for p in _split_flow(v[1:-1])]


def _flow_map(v):
    if not v.endswith("}"):
        raise ParseError("unterminated flow mapping")
    out = {}
    for p in _split_flow(v[1:-1]):
        if ":" not in p:
            raise ParseError("flow mapping entry without a colon")
        k, val = p.split(":", 1)
        out[_scalar(k)] = _scalar(val)
    return out


def _indent(line):
    return len(line) - len(line.lstrip(" "))


def parse_block(lines):
    """Parse a `founder_check:` block into a dict of its fields. Raises ParseError."""
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
            elif all(k.lstrip().startswith("- ") or k.strip() == "-" for k in kids):
                fields[key] = [_scalar(_strip_comment(k.lstrip()[1:])) for k in kids]
            else:
                mp = {}
                for k in kids:
                    km = re.match(r"^ *([^\s:][^:]*?):[ \t]+(.*)$", k)
                    if not km:
                        raise ParseError(f"not a mapping entry: {k.strip()[:40]}")
                    mp[km.group(1).strip()] = _scalar(_strip_comment(km.group(2)))
                fields[key] = mp
        elif val.startswith("["):
            fields[key] = _flow_list(val)
        elif val.startswith("{"):
            fields[key] = _flow_map(val)
        else:
            fields[key] = _scalar(val)
    return fields


def canonical(block):
    out = {}
    for k in CANONICAL_FIELDS:
        v = block.get(k)
        if k == "creates":
            v = list(v) if isinstance(v, list) else ([] if v in (None, "") else v)
        elif k == "pins":
            v = dict(v) if isinstance(v, dict) else ({} if v in (None, "") else v)
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


def _first_token(command):
    lines = [x for x in command.splitlines() if x.strip() and not x.lstrip().startswith("#")]
    toks = (lines[0].split() if lines else [])
    return toks[0] if toks else ""


def _script_tokens(command):
    """Repo-relative script operands of an interpreter verb. An inline program (-c) names none."""
    try:
        toks = shlex.split(command)
    except ValueError:
        return None
    if any(t == "-c" or (t.startswith("-c") and len(t) > 2 and not t.startswith("--")) for t in toks[1:]):
        return []
    out = []
    for t in toks[1:]:
        if t.startswith("-") or t.startswith("/") or "://" in t:
            continue
        if "/" in t or t.endswith(SCRIPT_EXTS):
            out.append(t[2:] if t.startswith("./") else t)
    return out


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
    for k in ("kind", "text", "command", "expected"):
        if not isinstance(block.get(k, ""), str):
            return "unparseable"
    if not isinstance(block.get("creates", []), list) or not isinstance(block.get("pins", {}), dict):
        return "unparseable"
    if not block.get("text", "").strip():
        return "missing-field"
    if kind == "judgement":
        return None
    cmd = block.get("command", "")
    if not cmd.strip():
        return "missing-field"
    rc, msg = _verb_gate(cmd)
    if rc != 0:
        return "verb-gate"
    first = _first_token(cmd)
    creates = block.get("creates", [])
    pins = {(k[2:] if k.startswith("./") else k): v for k, v in block.get("pins", {}).items()}
    if first in INTERPRETERS:
        if creates:
            return "creates-with-interpreter"
        toks = _script_tokens(cmd)
        if toks is None:
            return "unparseable"
        if any(t not in pins for t in toks):
            return "unpinned-script"
    return None


# ---------------------------------------------------------------------------------------------
# verify
# ---------------------------------------------------------------------------------------------
_COMMAND_OUT = None


def _emit(outcome, **kw):
    doc = {"outcome": outcome}
    doc.update(kw)
    if _COMMAND_OUT and isinstance(doc.get("block"), dict):
        # The raw command goes to a FILE so the Check 13 wrapper never has to quote it into a shell
        # word. Written for every outcome that parsed a block: an UNTRUSTED or CHANGED block must be
        # SHOWN to the founder before anyone decides, and showing needs the exact text.
        with open(_COMMAND_OUT, "w", encoding="utf-8") as fh:
            fh.write(doc["block"].get("command", ""))
    print(json.dumps(doc, sort_keys=True))
    return 0 if outcome in ("OK", "NO-BLOCK") else 1


def _blocks_at(repo, rev, path):
    text = _out(["show", f"{rev}:{path}"], repo)
    return extract_blocks(text) if text is not None else []


def _operator_email(repo):
    out = _out(["var", "GIT_AUTHOR_IDENT"], repo)
    m = re.search(r"<([^>]*)>", out or "")
    return m.group(1).strip().lower() if m else ""


def _verify_candidate(repo, path, lines):
    """Baseline mode: the block is not frozen yet, so there is no freeze to compare with.

    Everything that can be decided from the block and the CURRENT tree still is: parse, the static
    rules, every pin against HEAD's blob, every creates path absent. The freeze commit follows a
    valid baseline run, never precedes it.
    """
    try:
        block = parse_block(lines)
    except ParseError as e:
        return _emit("FAIL", reason="unparseable", plan=path, detail=str(e))
    canon = canonical(block)
    info = {"plan": path, "freeze_sha": "", "freeze_source": "candidate", "hash": canonical_hash(canon),
            "block": {**canon, "approved_by": block.get("approved_by", ""), "approved_at": block.get("approved_at", "")}}
    problem = static_problem(block)
    if problem:
        return _emit("FAIL", reason=problem, **info, detail="the candidate block is not acceptable as written")
    declared = block.get("hash")
    if declared and declared != info["hash"]:
        return _emit("FAIL", reason="hash-mismatch", **info, detail="hash: does not match the block's own fields")
    for pth, sha in canon["pins"].items():
        pth = pth[2:] if pth.startswith("./") else pth
        if (_out(["rev-parse", f"HEAD:{pth}"], repo) or "").strip() != sha:
            return _emit("FAIL", reason="pin-not-at-freeze", **info, detail=f"{pth} is not pinned to its blob in HEAD")
    for pth in canon["creates"]:
        if _git(["cat-file", "-e", f"HEAD:{pth}"], repo)[0] == 0 or os.path.lexists(os.path.join(repo, pth)):
            return _emit("FAIL", reason="creates-exists-at-freeze", **info, detail=f"{pth} already exists, so the check could pass on a stub")
    return _emit("OK", reason="candidate", **info, changed_fields=[], reasons=[], flags=[])


def cmd_verify(a):
    global _COMMAND_OUT
    _COMMAND_OUT = a.command_out
    repo = a.repo or os.getcwd()
    top = (_out(["rev-parse", "--show-toplevel"], repo) or "").strip()
    if not top:
        return _emit("FAIL", reason="not-a-repository", detail="verify must run inside the repository")
    repo = top
    merge_base = (_out(["merge-base", a.base, "HEAD"], repo) or "").strip()
    if not merge_base:
        return _emit("FAIL", reason="base-unresolvable", detail=f"cannot resolve {a.base}")

    commits = [c for c in (_out(["rev-list", "--reverse", "--topo-order", f"{merge_base}..HEAD"], repo) or "").split() if c]

    # Every plan path the branch could have put a block into.
    cands = set(a.plan or [])
    for args in (
        ["diff", "--name-only", "--no-renames", merge_base, "HEAD", "--", PLANS_DIR],
        ["diff", "--name-only", "--no-renames", "HEAD", "--", PLANS_DIR],
        ["ls-files", "--others", "--exclude-standard", "--", PLANS_DIR],
    ):
        cands.update(p for p in (_out(args, repo) or "").splitlines() if p.endswith(".md"))

    # Freeze evidence is found in HISTORY, independently of whether the plan still resolves, so
    # deleting or renaming it cannot turn a FAIL into a SKIP.
    evidence = {}
    for c in commits:
        names = _out(["diff-tree", "--no-commit-id", "--name-only", "-r", "--root", "--no-renames", c], repo) or ""
        for p in names.splitlines():
            if p.startswith(PLANS_DIR + "/") and p.endswith(".md") and p not in evidence and _blocks_at(repo, c, p):
                evidence[p] = c
    mb_evidence = {p: merge_base for p in cands if _blocks_at(repo, merge_base, p)}
    cands.update(evidence)
    freeze_of = {}
    for p in cands:
        if p in mb_evidence:
            freeze_of[p] = (mb_evidence[p], "merge-base")
        elif p in evidence:
            freeze_of[p] = (evidence[p], "branch")

    plans_root = os.path.realpath(os.path.join(repo, PLANS_DIR))
    heads = {}
    for p in sorted(cands):
        full = os.path.join(repo, p)
        if not os.path.lexists(full):
            continue
        try:
            with open(full, encoding="utf-8", errors="replace") as fh:
                text = fh.read()
        except OSError:
            continue
        blocks = extract_blocks(text)
        escaped = os.path.islink(full) or not os.path.realpath(full).startswith(plans_root + os.sep)
        if blocks and escaped:
            return _emit("FAIL", reason="symlinked-plan", plan=p, detail="a plan whose real path leaves the plans directory is never followed")
        if len(blocks) > 1:
            return _emit("FAIL", reason="multiple-blocks", plan=p, detail="more than one founder_check block under Acceptance Criteria")
        if blocks:
            heads[p] = blocks[0]

    if len(heads) > 1:
        return _emit("FAIL", reason="multiple-plans", detail="more than one plan carries a founder_check block: " + ", ".join(sorted(heads)))
    if not heads:
        if freeze_of:
            return _emit(
                "FAIL", reason="freeze-without-block",
                detail="a freeze exists in history for " + ", ".join(sorted(freeze_of)) + " but no block resolves at HEAD",
            )
        return _emit("NO-BLOCK", reason="no-block")

    (path, lines), = heads.items()
    if a.candidate:
        return _verify_candidate(repo, path, lines)
    stale = sorted(p for p in freeze_of if p != path)
    if stale:
        return _emit("FAIL", reason="freeze-without-block", plan=path, detail="a block was frozen at " + ", ".join(stale) + " and is not there at HEAD")
    if path not in freeze_of:
        return _emit("FAIL", reason="no-freeze", plan=path, detail="the block has no freeze commit; commit it before any code")
    freeze_sha, source = freeze_of[path]

    try:
        head_block = parse_block(lines)
    except ParseError as e:
        return _emit("FAIL", reason="unparseable", plan=path, detail=str(e))
    flines = (_blocks_at(repo, freeze_sha, path) or [[]])[0]
    try:
        frozen_block = parse_block(flines)
    except ParseError as e:
        return _emit("FAIL", reason="unparseable", plan=path, detail="freeze copy: " + str(e))

    head_c, frozen_c = canonical(head_block), canonical(frozen_block)
    head_hash = canonical_hash(head_c)
    base_info = {"plan": path, "freeze_sha": freeze_sha, "freeze_source": source, "hash": head_hash, "block": {**head_c, "approved_by": head_block.get("approved_by", ""), "approved_at": head_block.get("approved_at", "")}}

    problem = static_problem(frozen_block)
    if problem:
        return _emit("FAIL", reason=problem, **base_info, detail="the frozen block is not acceptable as written")
    declared = head_block.get("hash")
    if declared and declared != head_hash:
        return _emit("FAIL", reason="hash-mismatch", **base_info, detail="hash: does not match the block's own fields")

    # Pins and creates are facts about the FREEZE tree.
    for pth, sha in frozen_c["pins"].items():
        pth = pth[2:] if pth.startswith("./") else pth
        actual = (_out(["rev-parse", f"{freeze_sha}:{pth}"], repo) or "").strip()
        if actual != sha:
            return _emit("FAIL", reason="pin-not-at-freeze", **base_info, detail=f"{pth} is not pinned to its blob at the freeze")
    for pth in frozen_c["creates"]:
        rc, _o = _git(["cat-file", "-e", f"{freeze_sha}:{pth}"], repo)
        if rc == 0:
            return _emit("FAIL", reason="creates-exists-at-freeze", **base_info, detail=f"{pth} already exists at the freeze, so the check could pass on a stub")

    reasons, flags = [], []

    # Authorship anchor (Guard 3). A freeze reviewed on main needs none.
    if source == "branch":
        operator = _operator_email(repo)
        author = (_out(["log", "-1", "--format=%ae", freeze_sha], repo) or "").strip().lower()
        if not operator or author != operator:
            flags.append("freeze-author")
        if a.pr_author and a.operator_login and a.pr_author.lower() != a.operator_login.lower():
            flags.append("pr-author")

    changed = [k for k in CANONICAL_FIELDS if head_c[k] != frozen_c[k]]
    if changed:
        reasons.append("field-changed")
    for pth, sha in frozen_c["pins"].items():
        pth = pth[2:] if pth.startswith("./") else pth
        rc, h = _git(["hash-object", "--", pth], repo)
        if rc != 0 or h.strip() != sha:
            reasons.append("pinned-script-changed")
            break
    if source == "branch" and freeze_sha in commits:
        fidx = commits.index(freeze_sha)
        for idx, c in enumerate(commits):
            names = (_out(["diff-tree", "--no-commit-id", "--name-only", "-r", "--root", "--no-renames", c], repo) or "").splitlines()
            if any(not n.startswith("knowledge-base/") for n in names):
                if fidx >= idx:
                    reasons.append("ordering")
                break

    info = {**base_info, "changed_fields": changed, "reasons": reasons, "flags": flags}
    if flags:
        return _emit("UNTRUSTED", reason="authorship", **info, detail="the freeze does not anchor to the local operator; show the exact command and ask before running")
    if reasons:
        return _emit("CHANGED-SINCE-APPROVAL", reason=reasons[0], **info, detail="the approved text, a pinned script or the freeze ordering changed")
    return _emit("OK", reason="ok", **info)


# ---------------------------------------------------------------------------------------------
# classify
# ---------------------------------------------------------------------------------------------
class Result(NamedTuple):
    outcome: str
    expected_matched: bool
    reason: str


def classify(rc, stdout, expected, polarity, first_token="", creates=(), target_present=True, sandbox_healthy=True):
    """The one decision chokepoint, shared by baseline and acceptance polarity."""
    matched = (expected == "") or (expected in stdout)
    if not sandbox_healthy:
        return Result("INVALID", matched, "sandbox-unhealthy")
    # A listed creates path that is absent makes any non-zero rc a genuine baseline fail
    # (a python rc 2, a node rc 1, a bash rc 127 all mean "the thing is not there yet").
    # A timeout is never evidence.
    if polarity == "baseline" and creates and not target_present and rc != 0 and rc != 124:
        return Result("FAILED-AS-EXPECTED", matched, "creates-target-absent")
    if rc in (124, 126, 127):
        return Result("INVALID", matched, f"tooling-rc-{rc}")
    if first_token == "curl" and rc in (6, 7, 28):
        return Result("INVALID", matched, f"curl-rc-{rc}")
    if polarity == "baseline":
        # mutation-anchor: baseline-vacuous
        if rc == 0 and matched:
            return Result("VACUOUS", matched, "baseline-passes")
        return Result("FAILED-AS-EXPECTED", matched, "baseline-fails")
    if rc == 0 and matched:
        return Result("PASSED", matched, "ran-returned-success")
    return Result("FAILED", matched, "non-zero-or-expected-absent")


def _bool(v):
    return str(v).lower() in ("1", "true", "yes")


def cmd_classify(a):
    stdout = a.stdout
    if a.stdout_file:
        with open(a.stdout_file, encoding="utf-8", errors="replace") as fh:
            stdout = fh.read()
    r = classify(
        a.rc, stdout or "", a.expected or "", a.polarity, a.first_token or "",
        tuple(a.creates or ()), _bool(a.target_present), _bool(a.sandbox_healthy),
    )
    print(json.dumps({"outcome": r.outcome, "expected_matched": r.expected_matched, "reason": r.reason}, sort_keys=True))
    return 0


# ---------------------------------------------------------------------------------------------
# log / summary / text
# ---------------------------------------------------------------------------------------------
def _cell(v):
    return re.sub(r"\s+", " ", str(v)).replace("|", "\\|").strip()


def cmd_log(a):
    outcome, underlying = a.outcome, ""
    if a.mode == "headless":
        if outcome in HEADLESS_REFUSED:
            print(f"refused: {outcome} is an interactive-only outcome; a headless run cannot record it", file=sys.stderr)
            return 3
        if outcome in HEADLESS_STOPS or (outcome == "SKIP-NOSANDBOX" and _bool(a.block_present)):
            underlying, outcome = outcome, "STOPPED-AWAITING-FOUNDER"
    if outcome == "OVERRIDDEN" and not (a.reason or "").strip():
        print("refused: an override needs a one-line reason", file=sys.stderr)
        return 3
    if a.output_sha256 and not re.fullmatch(r"[0-9a-f]{64}", a.output_sha256):
        print("refused: --output-sha256 must be a sha256 hex digest; the log never holds output text", file=sys.stderr)
        return 3
    row = {
        "kind": a.kind or "", "polarity": a.polarity, "command": a.command or "", "rc": "" if a.rc is None else a.rc,
        "outcome": outcome, "underlying": underlying, "attempt_n": a.attempt_n if a.attempt_n is not None else "",
        "tested_sha": a.tested_sha or "", "block_hash": a.hash or "",
        "time_utc": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "output_sha256": a.output_sha256 or "", "expected_matched": "" if a.expected_matched is None else a.expected_matched,
        "reason": a.reason or "",
    }
    path = os.path.abspath(a.log)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fresh = not os.path.exists(path) or os.path.getsize(path) == 0
    with open(path, "a", encoding="utf-8") as fh:
        if fresh:
            fh.write("| " + " | ".join(LOG_COLUMNS) + " |\n")
            fh.write("| " + " | ".join("---" for _ in LOG_COLUMNS) + " |\n")
        fh.write("| " + " | ".join(_cell(row[c]) for c in LOG_COLUMNS) + " |\n")
    print(f"SOLEUR_FOUNDER_CHECK_RESULT outcome={outcome} hash={a.hash or ''} tested_sha={a.tested_sha or ''}")
    return 0


def _log_rows(path):
    with open(path, encoding="utf-8", errors="replace") as fh:
        lines = [ln.rstrip("\n") for ln in fh if ln.startswith("|")]
    sep = re.compile(r"^\|[\s:|-]+\|?\s*$")
    rows, header = [], None
    for i, ln in enumerate(lines):
        if sep.match(ln):
            continue
        if i + 1 < len(lines) and sep.match(lines[i + 1]):
            header = [c.strip() for c in ln.strip().strip("|").split("|")]
            continue
        rows.append([c.strip() for c in re.split(r"(?<!\\)\|", ln.strip().strip("|"))])
    return header, rows


def cmd_summary(a):
    path = a.log
    if not path:
        top = (_out(["rev-parse", "--show-toplevel"], os.getcwd()) or "").strip() or os.getcwd()
        branch = (_out(["rev-parse", "--abbrev-ref", "HEAD"], top) or "HEAD").strip()
        path = os.path.join(top, "knowledge-base", "project", "specs", branch, "founder-check-log.md")
    if not os.path.isfile(path):
        print("founder-check: no log")
        return 0
    header, rows = _log_rows(path)
    print(f"founder-check: {len(rows)} rows")
    if header and "outcome" in header and "attempt_n" in header:
        oi, ai = header.index("outcome"), header.index("attempt_n")
        failures = 0
        for r in rows:
            if len(r) <= max(oi, ai):
                continue
            if r[oi] in ("FAILED", "INVALID"):
                failures += 1
            elif r[oi] == "PASSED" and failures:
                print(f"PASSED on attempt {r[ai]} after {failures} failures")
                failures = 0
    return 0


def cmd_text(a):
    print(WORDING[a.name].format(sha=a.sha, reason=a.reason))
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
    v.add_argument("--command-out", help="write the block's raw command text to this file")
    v.add_argument("--candidate", action="store_true", help="baseline mode: validate a block that has no freeze commit yet")
    v.set_defaults(fn=cmd_verify)

    c = sub.add_parser("classify", allow_abbrev=False)
    c.add_argument("--rc", type=int, required=True)
    c.add_argument("--polarity", choices=("baseline", "acceptance"), required=True)
    c.add_argument("--stdout")
    c.add_argument("--stdout-file")
    c.add_argument("--expected", default="")
    c.add_argument("--first-token", default="")
    c.add_argument("--creates", action="append")
    c.add_argument("--target-present", default="true")
    c.add_argument("--sandbox-healthy", default="true")
    c.set_defaults(fn=cmd_classify)

    g = sub.add_parser("log", allow_abbrev=False)
    g.add_argument("--log", required=True)
    g.add_argument("--mode", choices=("interactive", "headless"), required=True)
    g.add_argument("--outcome", choices=OUTCOMES, required=True)
    g.add_argument("--kind")
    g.add_argument("--command")
    g.add_argument("--rc", type=int)
    g.add_argument("--attempt-n", type=int)
    g.add_argument("--tested-sha")
    g.add_argument("--hash")
    g.add_argument("--output-sha256")
    g.add_argument("--expected-matched")
    g.add_argument("--reason")
    g.add_argument("--block-present", default="true")
    g.add_argument("--polarity", default="acceptance", choices=("baseline", "acceptance"))
    g.set_defaults(fn=cmd_log)

    s = sub.add_parser("summary", allow_abbrev=False)
    s.add_argument("--log")
    s.set_defaults(fn=cmd_summary)

    t = sub.add_parser("text", allow_abbrev=False)
    t.add_argument("name", choices=sorted(WORDING))
    t.add_argument("--sha", default="<sha>")
    t.add_argument("--reason", default="<reason>")
    t.set_defaults(fn=cmd_text)
    return p


def main(argv=None):
    args = build_parser().parse_args(argv)
    return args.fn(args)


if __name__ == "__main__":
    sys.exit(main())
