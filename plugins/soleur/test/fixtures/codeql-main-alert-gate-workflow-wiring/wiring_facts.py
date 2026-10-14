#!/usr/bin/env python3
"""Parse a GitHub Actions workflow with PyYAML and print the facts the wiring suite asserts, as JSON.

Usage: wiring_facts.py <workflow.yml> <gate-script.sh>

Why this exists: the wiring of the CodeQL main alert gate used to be asserted by greps over the workflow text,
which pass against a renamed trigger, a deleted env block or an appended `|| true`. This helper PARSES the file
(PyYAML reads the key `on` as the boolean True, which is handled explicitly) and EVALUATES the `${{ }}`
expressions of the gate step's env for a push and for the dispatch variants, with GitHub's own semantics for
`&&`, `||`, `==`, `!=` and `!` (loose equality, falsy = false/0/''/null, `&&`/`||` return an operand, not a bool).

Any failure to read or parse prints {"parse_ok": false, "error": "..."} and exits 0: the suite's first assertion
turns that into a RED, so an unreadable workflow can never read as green.
"""
import json
import re
import sys

import yaml

SHA = "0123456789abcdef0123456789abcdef01234567"
DISPATCH_SHA = "89abcdef0123456789abcdef0123456789abcdef"


# ---- GitHub expression evaluator (the subset the workflow uses; anything else is an error) ----------
class ExprError(Exception):
    pass


TOKEN = re.compile(r"\s*(?:(\|\||&&|==|!=|!|\(|\))|'((?:[^']|'')*)'|(-?\d+(?:\.\d+)?)|([A-Za-z_][A-Za-z0-9_-]*(?:\.[A-Za-z_][A-Za-z0-9_-]*)*))")


def tokenize(src):
    out, pos = [], 0
    src = src.strip()
    while pos < len(src):
        m = TOKEN.match(src, pos)
        if not m or m.end() == pos:
            raise ExprError("cannot tokenize at %r" % src[pos:])
        if m.group(1) is not None:
            out.append(("op", m.group(1)))
        elif m.group(2) is not None:
            out.append(("str", m.group(2).replace("''", "'")))
        elif m.group(3) is not None:
            out.append(("num", float(m.group(3))))
        else:
            out.append(("id", m.group(4)))
        pos = m.end()
    return out


def truthy(v):
    return not (v is None or v is False or v == 0 or v == "" or (isinstance(v, float) and v != v))


def to_num(v):
    if v is None:
        return 0.0
    if isinstance(v, bool):
        return 1.0 if v else 0.0
    if isinstance(v, (int, float)):
        return float(v)
    s = str(v).strip()
    if s == "":
        return 0.0
    try:
        return float(s)
    except ValueError:
        return float("nan")


def loose_eq(a, b):
    if type(a) is type(b) and not isinstance(a, float):
        if isinstance(a, str):
            return a.lower() == b.lower()
        return a == b
    return to_num(a) == to_num(b)


class Parser:
    def __init__(self, toks, ctx):
        self.t, self.i, self.ctx = toks, 0, ctx

    def peek(self):
        return self.t[self.i] if self.i < len(self.t) else (None, None)

    def eat(self, kind=None, val=None):
        k, v = self.peek()
        if k is None or (kind and k != kind) or (val is not None and v != val):
            raise ExprError("unexpected %r" % ((k, v),))
        self.i += 1
        return v

    def parse(self):
        v = self.p_or()
        if self.i != len(self.t):
            raise ExprError("trailing tokens")
        return v

    def p_or(self):
        v = self.p_and()
        while self.peek() == ("op", "||"):
            self.eat()
            r = self.p_and()
            v = v if truthy(v) else r
        return v

    def p_and(self):
        v = self.p_eq()
        while self.peek() == ("op", "&&"):
            self.eat()
            r = self.p_eq()
            v = r if truthy(v) else v
        return v

    def p_eq(self):
        v = self.p_un()
        while self.peek() in (("op", "=="), ("op", "!=")):
            op = self.eat()
            r = self.p_un()
            v = loose_eq(v, r) if op == "==" else (not loose_eq(v, r))
        return v

    def p_un(self):
        if self.peek() == ("op", "!"):
            self.eat()
            return not truthy(self.p_un())
        return self.p_pr()

    def p_pr(self):
        k, v = self.peek()
        if k == "op" and v == "(":
            self.eat()
            r = self.p_or()
            self.eat("op", ")")
            return r
        if k == "str" or k == "num":
            self.eat()
            return v
        if k == "id":
            self.eat()
            if v == "true":
                return True
            if v == "false":
                return False
            if v == "null":
                return None
            cur = self.ctx
            for part in v.split("."):
                cur = cur.get(part) if isinstance(cur, dict) else None
            return cur
        raise ExprError("unexpected %r" % ((k, v),))


EXPR = re.compile(r"^\s*\$\{\{(.*)\}\}\s*$", re.S)


def evaluate(value, ctx):
    """A whole-`${{ }}` value is evaluated; a plain literal is returned as is; mixed text is an error."""
    if not isinstance(value, str):
        return value
    m = EXPR.match(value)
    if m:
        return Parser(tokenize(m.group(1)), ctx).parse()
    if "${{" in value:
        raise ExprError("mixed literal and expression")
    return value


SCENARIOS = {
    "push": {"event_name": "push", "inputs": None},
    "dispatch_default": {"event_name": "workflow_dispatch", "inputs": {"sha": "", "dry_run": False}},
    "dispatch_sha": {"event_name": "workflow_dispatch", "inputs": {"sha": DISPATCH_SHA, "dry_run": False}},
    "dispatch_dry": {"event_name": "workflow_dispatch", "inputs": {"sha": "", "dry_run": True}},
    "dispatch_dry_false": {"event_name": "workflow_dispatch", "inputs": {"sha": "", "dry_run": False}},
}


def context(sc):
    return {
        "github": {"event_name": sc["event_name"], "sha": SHA, "repository": "example-org/example-repo",
                   "token": "SYNTHETIC-TOKEN", "run_id": "424242", "ref": "refs/heads/main"},
        "inputs": sc["inputs"],
        "secrets": {"GITHUB_TOKEN": "SYNTHETIC-TOKEN"},
    }


def script_defaults(path):
    out = {"poll_interval": None, "max_polls": None, "settle_polls": None, "deadline_seconds": None}
    try:
        text = open(path, encoding="utf-8").read()
    except OSError:
        return out
    for key, var in (("poll_interval", "POLL_INTERVAL"), ("max_polls", "MAX_POLLS"),
                     ("settle_polls", "SETTLE_POLLS"), ("deadline_seconds", "DEADLINE_SECONDS")):
        m = re.search(r'^%s="\$\{%s:-([0-9]+)\}"$' % (var, var), text, re.M)
        out[key] = int(m.group(1)) if m else None
    return out


def main():
    wf_path, script_path = sys.argv[1], sys.argv[2]
    facts = {"parse_ok": False, "script": script_defaults(script_path)}
    try:
        with open(wf_path, encoding="utf-8") as fh:
            doc = yaml.safe_load(fh)
        if not isinstance(doc, dict):
            raise ValueError("the workflow is not a mapping")
    except Exception as exc:  # noqa: BLE001 - any read/parse failure is reported, never swallowed
        facts["error"] = "%s: %s" % (type(exc).__name__, exc)
        print(json.dumps(facts))
        return
    facts["parse_ok"] = True
    # PyYAML (YAML 1.1) reads the bare key `on` as the boolean True.
    facts["on_key_is_bool_true"] = True in doc
    facts["on_key_is_string"] = "on" in doc
    trig = doc.get(True, doc.get("on"))
    facts["trigger_found"] = isinstance(trig, dict)
    trig = trig if isinstance(trig, dict) else {}
    facts["triggers"] = sorted(str(k) for k in trig)
    push = trig.get("push")
    facts["push"] = push if isinstance(push, dict) else None
    disp = trig.get("workflow_dispatch")
    facts["dispatch_inputs"] = (disp or {}).get("inputs") if isinstance(disp, dict) else None
    facts["top_level_keys"] = sorted(str(k) for k in doc if k is not True)
    facts["permissions"] = doc.get("permissions")
    facts["concurrency"] = doc.get("concurrency")
    jobs = doc.get("jobs") if isinstance(doc.get("jobs"), dict) else {}
    facts["job_ids"] = sorted(jobs)
    job = jobs.get("gate") if isinstance(jobs.get("gate"), dict) else {}
    facts["job_keys"] = sorted(job)
    facts["job_timeout"] = job.get("timeout-minutes")
    steps = job.get("steps") if isinstance(job.get("steps"), list) else []
    facts["steps"] = [
        {"name": s.get("name"), "uses": s.get("uses"), "keys": sorted(s), "run": s.get("run"),
         "has_if": "if" in s, "has_continue_on_error": "continue-on-error" in s,
         "with": s.get("with"), "env": s.get("env")}
        for s in steps if isinstance(s, dict)
    ]
    gate = [s for s in steps if isinstance(s, dict) and isinstance(s.get("run"), str) and "scripts/codeql-main-alert-gate.sh" in s["run"]]
    facts["gate_step_count"] = len(gate)
    facts["gate_step_index"] = steps.index(gate[0]) if len(gate) == 1 else None
    env = gate[0].get("env") if len(gate) == 1 and isinstance(gate[0].get("env"), dict) else {}
    facts["gate_env_keys"] = sorted(env)
    # Absence facts: every place an env or a knob could be set, so an EXTRA key is as visible as a missing one.
    facts["workflow_env"] = doc.get("env")
    facts["job_env"] = job.get("env")
    facts["job_permissions"] = job.get("permissions")
    sites = []
    if isinstance(doc.get("env"), dict):
        sites.append({"site": "workflow", "keys": sorted(doc["env"])})
    if isinstance(job.get("env"), dict):
        sites.append({"site": "job", "keys": sorted(job["env"])})
    for i, st in enumerate(steps):
        if isinstance(st, dict) and isinstance(st.get("env"), dict):
            sites.append({"site": "step:%d" % i, "keys": sorted(st["env"])})
    facts["env_sites"] = sites
    evals = {}
    for sname, sc in SCENARIOS.items():
        ctx = context(sc)
        evals[sname] = {}
        for var in ("GH_TOKEN", "GH_REPO", "SHA", "DRY_RUN", "GITHUB_RUN_ID"):
            if var not in env:
                evals[sname][var] = "<<absent>>"
                continue
            try:
                evals[sname][var] = evaluate(env[var], ctx)
            except ExprError as exc:
                evals[sname][var] = "<<expression error: %s>>" % exc
    facts["evals"] = evals
    facts["expected_values"] = {"sha": SHA, "dispatch_sha": DISPATCH_SHA, "repo": "example-org/example-repo", "token": "SYNTHETIC-TOKEN"}
    print(json.dumps(facts))


if __name__ == "__main__":
    main()
