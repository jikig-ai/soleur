#!/usr/bin/env python3
"""Fail any tracked `resource "doppler_*"` description over Doppler's 255 cap.

Doppler's API rejects a `description` longer than 255 at create/update time with
`"description" length must be less than or equal to 255 characters long`. Neither
the dopplerhq/doppler provider schema nor `terraform plan` checks it, so without
this lint the first signal is a red push apply: a 273-character
doppler_project.infra_privileged description failed every push apply after the
credential-tiering merge, and doppler_project.inngest hit the same cap in July.

Usage:
  lint-doppler-description-length.py            # every tracked *.tf / *.tf.json
  lint-doppler-description-length.py FILE...    # exactly these files (fixtures)

Exit 0 = clean, 1 = findings (including "could not measure"), 2 = the lint itself
could not run (git failure, unreadable file) -- never read as a finding.

THE SCAN IS A TOKENIZER, NOT A LINE SCANNER. Strings (with nested `${...}`
templates), `#` / `//` / `/* */` comments and heredocs are lexed, and blocks are
tracked by bracket depth, so layout (column 0, one-line blocks, unquoted labels, a
BOM, inline comments) cannot move a description out of its block. An earlier
line-based version was defeated by five `terraform fmt`-clean layouts; a
formatting assumption is not a guard, because `fmt -check` is not a required check.

A description is measured when it is a DIRECT attribute of a top-level
`resource "doppler_*"` block and its value is exactly one quoted literal with no
template sequence. Anything else -- a reference, interpolation, a directive, a
heredoc, an expression -- cannot be measured statically and fails closed.

The measure is max(raw source bytes, UTF-8 bytes of the NFC-normalised decoded
value). Terraform NFC-normalises string literals, and a few characters EXPAND under
NFC (63 x U+1D160 is 252 source bytes and 756 decoded), so raw bytes alone are not
an upper bound. UTF-8 bytes of the decoded value bound its code points and its
UTF-16 units, so a value that passes here passes whichever counting rule Doppler's
validator uses.

Out of reach, by construction: descriptions sent by the Doppler CLI or REST API,
by remote modules, or by Terraform generated at run time. A tracked *.tf.json
declaring a doppler_* resource fails closed (JSON syntax is not measured).
"""

import re
import subprocess
import sys
import unicodedata

# Doppler API: `"description" length must be less than or equal to 255 characters long`.
DOPPLER_DESCRIPTION_MAX_BYTES = 255

IDENT = re.compile(r"[A-Za-z_][A-Za-z0-9_-]*")
HEREDOC = re.compile(r"<<-?([A-Za-z_][A-Za-z0-9_-]*)[ \t]*\r?\n")
UNSAFE_FOR_LOG = re.compile("[\x00-\x1f\x7f-\x9f\u2028\u2029]")
HCL_ESCAPE = re.compile(r"\\(u[0-9A-Fa-f]{4}|U[0-9A-Fa-f]{8}|.)|\$\$\{|%%\{", re.S)
SIMPLE_ESCAPES = {"n": "\n", "r": "\r", "t": "\t", '"': '"', "\\": "\\"}


class ScanError(Exception):
    def __init__(self, msg, line):
        super().__init__(msg)
        self.msg = msg
        self.line = line


def safe(s):
    """Printable, single-line, and unable to form a runner log command anywhere in it."""
    s = s.encode("utf-8", "surrogateescape").decode("utf-8", "replace")
    s = UNSAFE_FOR_LOG.sub("", s)
    return re.sub(r"#{2,}\[", "#[", s)


def scan_template(text, i, line):
    """Skip a `${ ... }` / `%{ ... }` body; return the index after its closing brace."""
    depth, n = 1, len(text)
    while i < n:
        c = text[i]
        if c == '"':
            i, _, line = scan_string(text, i + 1, line)
            i += 1
            continue
        if c == "\n":
            line += 1
        elif c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return i + 1, line
        i += 1
    raise ScanError("unterminated template sequence", line)


def scan_string(text, i, line):
    """Return (index of the closing quote, has_template, line)."""
    has_template, n = False, len(text)
    while i < n:
        c = text[i]
        if c == "\\":
            i += 2
            continue
        if c == "\n":
            break
        if c == '"':
            return i, has_template, line
        if c in "$%" and text.startswith(c + c + "{", i):
            i += 3  # `$${` / `%%{` are literal text
            continue
        if c in "$%" and text.startswith(c + "{", i):
            has_template = True
            i, line = scan_template(text, i + 2, line)
            continue
        i += 1
    raise ScanError("unterminated string", line)


def tokenize(text):
    """(kind, value, line, has_template) tokens; comments dropped, heredocs collapsed to one token
    carrying the body. has_template is always False for HEREDOC: consumers branch on the kind."""
    toks, i, n, line = [], 0, len(text), 1
    while i < n:
        c = text[i]
        if c == "\n":
            toks.append(("NL", c, line, False))
            line += 1
            i += 1
        elif c in " \t\r\ufeff":
            i += 1
        elif c == "#" or text.startswith("//", i):
            j = text.find("\n", i)
            i = n if j < 0 else j
        elif text.startswith("/*", i):
            j = text.find("*/", i + 2)
            if j < 0:
                raise ScanError("unterminated block comment", line)
            line += text.count("\n", i, j)
            i = j + 2
        elif c == '"':
            j, has_template, end_line = scan_string(text, i + 1, line)
            toks.append(("STR", text[i + 1:j], line, has_template))
            line, i = end_line, j + 1
        elif text.startswith("<<", i) and HEREDOC.match(text, i):
            m = HEREDOC.match(text, i)
            ident, start = m.group(1), line
            i, line = m.end(), line + 1
            body_start = i
            while True:
                j = text.find("\n", i)
                end = n if j < 0 else j
                if text[i:end].strip() == ident:
                    body = text[body_start:i]
                    i = end
                    break
                if j < 0:
                    raise ScanError("unterminated heredoc", start)
                i, line = j + 1, line + 1
            # The value slot carries the BODY (scan() never reads it; consumers such as
            # apps/web-platform/infra/web-probes-token-rotation.test.sh match references inside it).
            toks.append(("HEREDOC", body, start, False))
        elif c.isalpha() or c == "_":
            m = IDENT.match(text, i)
            toks.append(("ID", m.group(0), line, False))
            i = m.end()
        elif c in "{[(":
            toks.append(("OPEN", c, line, False))
            i += 1
        elif c in "}])":
            toks.append(("CLOSE", c, line, False))
            i += 1
        elif c == "=" and text[i + 1:i + 2] not in ("=", ">") and text[i - 1:i] not in ("=", "!", "<", ">"):
            toks.append(("EQ", c, line, False))
            i += 1
        else:
            toks.append(("OTHER", c, line, False))
            i += 1
    return toks


def decode(raw):
    def sub(m):
        tok = m.group(0)
        if tok in ("$${", "%%{"):
            return tok[1:]
        esc = m.group(1)
        if esc[0] in "uU" and len(esc) > 1:
            return chr(int(esc[1:], 16))
        return SIMPLE_ESCAPES.get(esc, esc)

    try:
        return HCL_ESCAPE.sub(sub, raw)
    except ValueError:  # an out-of-range \U escape; terraform rejects it too
        return raw


def measure(where, rtype, name, expr, findings, stats):
    if len(expr) != 1 or expr[0][0] != "STR" or expr[0][3]:
        findings.append(
            f"FAIL: {where}: {rtype}.{name} description is not a single string literal; "
            "cannot measure. Use one literal; var., interpolation and heredoc are unsupported by design."
        )
        return
    raw = expr[0][1]
    decoded = unicodedata.normalize("NFC", decode(raw))
    n = max(len(raw.encode("utf-8", "surrogateescape")), len(decoded.encode("utf-8", "surrogateescape")))
    stats["descriptions"] += 1
    stats["max"] = max(stats["max"], n)
    if n > DOPPLER_DESCRIPTION_MAX_BYTES:
        findings.append(
            f"FAIL: {where}: {rtype}.{name} description is {n} bytes (Doppler API cap "
            f"{DOPPLER_DESCRIPTION_MAX_BYTES}). Shorten by {n - DOPPLER_DESCRIPTION_MAX_BYTES} bytes; "
            "a non-ASCII character counts 2-4 bytes (an em dash is 3); "
            "put the rationale in a # comment above the attribute."
        )


def scan(path, label, findings, stats):
    with open(path, encoding="utf-8", errors="surrogateescape") as fh:
        text = fh.read()
    if label.endswith(".tf.json"):
        if "doppler_" in text:
            findings.append(f"FAIL: {safe(label)}: *.tf.json mentions doppler_*; JSON syntax is not measured")
        return
    try:
        toks = tokenize(text)
    except ScanError as e:
        findings.append(f"FAIL: {safe(label)}:{e.line}: {e.msg}; cannot scan this file")
        return
    stack = []  # one entry per open bracket: (type, name) for a doppler resource body, else None
    at_stmt, k = True, 0
    while k < len(toks):
        kind, val, line, _ = toks[k]
        if kind == "NL":
            at_stmt = True
            k += 1
            continue
        if at_stmt and kind == "ID":
            at_stmt = False
            if not stack:
                j, labels = k + 1, []
                while j < len(toks) and toks[j][0] in ("ID", "STR"):
                    labels.append(toks[j][1])
                    j += 1
                if j < len(toks) and toks[j][:2] == ("OPEN", "{"):
                    body = None
                    if val == "resource" and len(labels) == 2 and labels[0].startswith("doppler_"):
                        stats["resources"] += 1
                        stats["files"].add(label)
                        body = (labels[0], safe(labels[1]))
                    stack.append(body)
                    at_stmt, k = True, j + 1
                    continue
            elif stack[-1] is not None and val == "description" and k + 1 < len(toks) and toks[k + 1][0] == "EQ":
                j, depth, expr = k + 2, 0, []
                while j < len(toks):
                    t = toks[j]
                    if t[0] == "NL" and depth == 0:
                        break
                    if t[0] == "OPEN":
                        depth += 1
                    elif t[0] == "CLOSE":
                        if depth == 0:
                            break
                        depth -= 1
                    if t[0] != "NL":
                        expr.append(t)
                    j += 1
                measure(f"{safe(label)}:{line}", *stack[-1], expr, findings, stats)
                k = j
                continue
        if kind == "OPEN":
            stack.append(None)
            at_stmt = val == "{"
        elif kind == "CLOSE":
            if not stack:
                findings.append(f"FAIL: {safe(label)}:{line}: unbalanced '{val}'; cannot scan this file")
                return
            stack.pop()
        k += 1
    if stack:
        findings.append(f"FAIL: {safe(label)}: unclosed bracket at end of file; cannot scan this file")


def tracked_files():
    top = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"], check=True, capture_output=True, text=True
    ).stdout.strip()
    out = subprocess.run(
        ["git", "ls-files", "-z", "--", "*.tf", "*.tf.json"], check=True, capture_output=True, cwd=top
    ).stdout
    # dict.fromkeys dedupes: mid-merge, `ls-files` lists a conflicted path once per stage.
    rel = list(dict.fromkeys(p.decode("utf-8", "surrogateescape") for p in out.split(b"\0") if p))
    return [(f"{top}/{p}", p) for p in rel]


def main(argv):
    findings = []
    stats = {"resources": 0, "files": set(), "descriptions": 0, "max": 0}
    try:
        files = [(p, p) for p in argv] if argv else tracked_files()
        for path, label in files:
            scan(path, label, findings, stats)
    except (OSError, subprocess.CalledProcessError) as e:
        print(f"ERROR: lint-doppler-description-length could not run: {safe(str(e))}", file=sys.stderr)
        return 2
    if stats["resources"] == 0:
        findings.append("FAIL: vacuous scan: no doppler_* resource found")
    elif stats["descriptions"] == 0:
        findings.append("FAIL: vacuous scan: no description measured")
    for f in findings:
        print(f)
    if findings:
        print(f"{len(findings)} finding(s)")
        return 1
    print(
        f"OK: {stats['resources']} doppler_* resource(s) in {len(stats['files'])} file(s); "
        f"{stats['descriptions']} description(s) measured, max {stats['max']}/"
        f"{DOPPLER_DESCRIPTION_MAX_BYTES} bytes"
    )
    return 0


if __name__ == "__main__":
    sys.stdout.reconfigure(errors="backslashreplace")
    sys.exit(main(sys.argv[1:]))
