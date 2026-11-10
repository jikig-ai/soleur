#!/usr/bin/env python3
"""GitHub Actions expression interpreter (a subset) for workflow-step tests.

Subset: literals, dotted context refs, ==, !=, !, &&, ||, (), always()/success()/failure()/cancelled().
Semantics per the Actions docs. Only sole-copy-drift-check.test.sh imports this module.
heartbeat-reconcile-issue-step.test.sh still carries its own inline interpreter, semantically identical for
`if` mode; the two differ only in `value` mode, where this module renders a null as the empty string (what
string interpolation does) and the inline copy prints it as `false`. Do not assume a change here reaches the
heartbeat suite. Semantics:
  * `==` across different types coerces both sides to numbers (null -> 0, '' -> 0, a non-numeric
    string -> NaN); same-type strings compare case-insensitively.
  * `&&` / `||` return an operand, not a boolean.
  * A context ref that is not in the (flat, dotted-key) context is null.
  * The job status the status functions read is ctx `__job_status` (default success).
  * Mode `if` models the runner: an expression with no status function is wrapped in an implicit
    `success() && (...)`, and the result is TRUTHY unless it is false/0/''/null -- the STRING 'false'
    is true. Mode `value` returns the expression value; null renders as the empty string (what
    string interpolation does), booleans as true/false.
  * Unknown syntax is a harness error (ExprError / exit 3), never a verdict.

Use: importable (evaluate(mode, src, ctx)) or `python3 gha-expr.py <if|value> <expr> <ctx-json>`.
"""
import json
import math
import re
import sys


class ExprError(Exception):
    pass


_TOK = re.compile(r"\s*(?:('(?:[^']|'')*')|(&&|\|\||==|!=|!|\(|\))|([A-Za-z_][A-Za-z0-9_\-]*(?:\.[A-Za-z_][A-Za-z0-9_\-]*)*)|(\d+(?:\.\d+)?))")


def _tokens(s):
    toks, i = [], 0
    while i < len(s):
        if s[i:].strip() == "":
            break
        m = _TOK.match(s, i)
        if not m or m.end() == i:
            raise ExprError("unparseable expression at %r" % s[i:])
        if m.group(1) is not None:
            toks.append(("str", m.group(1)[1:-1].replace("''", "'")))
        elif m.group(2) is not None:
            toks.append(("op", m.group(2)))
        elif m.group(3) is not None:
            toks.append(("id", m.group(3)))
        else:
            toks.append(("num", float(m.group(4))))
        i = m.end()
    return toks


def _truthy(v):
    if v is None or v is False:
        return False
    if v is True:
        return True
    if isinstance(v, float):
        return not (v == 0 or math.isnan(v))
    return v != ""


def _tonum(v):
    if v is None:
        return 0.0
    if isinstance(v, bool):
        return 1.0 if v else 0.0
    if isinstance(v, float):
        return v
    t = v.strip()
    if t == "":
        return 0.0
    try:
        return float(t)
    except ValueError:
        return math.nan


def _eq(a, b):
    if type(a) is type(b):
        return a.lower() == b.lower() if isinstance(a, str) else a == b
    return _tonum(a) == _tonum(b)


def evaluate(mode, src, ctx):
    s = src.strip()
    if s.startswith("${{") and s.endswith("}}"):
        s = s[3:-2]
    toks = _tokens(s)
    job_status = ctx.get("__job_status", "success")
    funcs = {"always": True, "success": job_status == "success",
             "failure": job_status == "failure", "cancelled": job_status == "cancelled"}
    uses_status_fn = any(t[0] == "id" and t[1] in funcs and k + 1 < len(toks) and toks[k + 1] == ("op", "(")
                         for k, t in enumerate(toks))
    pos = [0]

    def peek():
        return toks[pos[0]] if pos[0] < len(toks) else (None, None)

    def take(kind=None, val=None):
        t = peek()
        if t[0] is None or (kind and t[0] != kind) or (val and t[1] != val):
            raise ExprError("unexpected token %r (wanted %s %s)" % (t, kind, val))
        pos[0] += 1
        return t

    def primary():
        t = peek()
        if t == ("op", "("):
            take()
            v = p_or()
            take("op", ")")
            return v
        if t[0] == "str":
            take()
            return t[1]
        if t[0] == "num":
            take()
            return t[1]
        if t[0] == "id":
            take()
            if peek() == ("op", "("):
                take()
                take("op", ")")
                if t[1] not in funcs:
                    raise ExprError("unsupported function %s" % t[1])
                return funcs[t[1]]
            if t[1] == "true":
                return True
            if t[1] == "false":
                return False
            if t[1] == "null":
                return None
            return ctx.get(t[1])
        raise ExprError("unexpected token %r" % (t,))

    def unary():
        if peek() == ("op", "!"):
            take()
            return not _truthy(unary())
        v = primary()
        if peek() in (("op", "=="), ("op", "!=")):
            op = take()[1]
            r = primary()
            return _eq(v, r) if op == "==" else not _eq(v, r)
        return v

    def p_and():
        v = unary()
        while peek() == ("op", "&&"):
            take()
            r = unary()
            v = r if _truthy(v) else v
        return v

    def p_or():
        v = p_and()
        while peek() == ("op", "||"):
            take()
            r = p_and()
            v = v if _truthy(v) else r
        return v

    out = p_or()
    if pos[0] != len(toks):
        raise ExprError("trailing tokens %r" % (toks[pos[0]:],))
    if mode == "if":
        return "true" if (_truthy(out) and (uses_status_fn or funcs["success"])) else "false"
    if out is True:
        return "true"
    if out is False:
        return "false"
    if out is None:
        return ""
    if isinstance(out, float):
        return str(int(out)) if out == int(out) else str(out)
    return out


if __name__ == "__main__":
    try:
        print(evaluate(sys.argv[1], sys.argv[2], json.loads(sys.argv[3])))
    except ExprError as e:
        sys.stderr.write("%s\n" % e)
        raise SystemExit(3)
