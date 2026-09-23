#!/usr/bin/env python3
"""Fail any tracked `resource "doppler_*"` description over Doppler's 255 cap.

Doppler's API rejects a `description` longer than 255 at create/update time with
`"description" length must be less than or equal to 255 characters long`. Neither
the dopplerhq/doppler provider schema nor `terraform plan` checks it, so without
this lint the first signal is a red push apply: a 273-character
doppler_project.infra_privileged description failed runs 35912754656 and
35921899265 and left the soleur-infra-privileged project uncreated.

Usage:
  lint-doppler-description-length.py            # every tracked *.tf in the repo
  lint-doppler-description-length.py FILE...    # exactly these files (fixtures)

Measurement is the RAW UTF-8 bytes of the source text between the quotes. Every
HCL escape is at least as long in source as decoded (`\\"` is 2 for 1, `\\uXXXX`
is 6 for at most 3, `$${` is 3 for 2), so raw bytes bound decoded bytes, which
bound UTF-16 units: a string that passes here passes whichever counting rule
Doppler's validator uses. Anything that is not one single-line literal (a
reference, interpolation, a directive, a heredoc, an expression) cannot be
measured statically and fails closed.

The scan is line-based and assumes `terraform fmt` layout: top-level blocks open
and close at column 0, nested blocks close at column 2 or deeper. Shapes that
break that assumption (a column-0 attribute, a column-0 nested `}` followed by a
description, a one-line doppler block) fail closed rather than being skipped.
Heredoc bodies and multi-line /* */ comments are text, never structure.
`*.tf.json` is not scanned (none are tracked).
"""

import re
import subprocess
import sys

# Doppler API: `"description" length must be less than or equal to 255 characters long`
# (push applies 35912754656 / 35921899265, doppler_project.infra_privileged).
DOPPLER_DESCRIPTION_MAX_BYTES = 255

DOPPLER_HEADER = re.compile(r'^resource\s+"(doppler_[a-z0-9_]+)"\s+"([^"]+)"\s*\{(.*)$')
DESCRIPTION = re.compile(r"^\s+description\s*=\s*(.*)$")
COL0_ATTRIBUTE = re.compile(r"^[A-Za-z_][A-Za-z0-9_-]*\s*=")
SINGLE_LITERAL = re.compile(r'^"((?:[^"\\]|\\.)*)"\s*(?:(?:#|//).*)?$')
# Unescaped template openers; `$${` and `%%{` are literal text.
TEMPLATE = re.compile(r"(?<!\$)\$\{|(?<!%)%\{")
HEREDOC_START = re.compile(r'<<-?\s*"?([A-Za-z_][A-Za-z0-9_]*)"?\s*$')
UNSAFE_FOR_LOG = re.compile("[\x00-\x1f\x7f-\x9f  ]")


def safe(s):
    """Strip control characters so a crafted path or name cannot inject a CI log command."""
    return UNSAFE_FOR_LOG.sub("", s)


def tracked_tf_files():
    top = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"], check=True, capture_output=True, text=True
    ).stdout.strip()
    out = subprocess.run(
        ["git", "ls-files", "-z", "--", "*.tf"], check=True, capture_output=True, cwd=top
    ).stdout
    rel = [p.decode("utf-8", "surrogateescape") for p in out.split(b"\0") if p]
    return [(f"{top}/{p}", p) for p in rel]


def scan(path, label, findings, stats):
    header = None  # (type, name) while inside a doppler resource, "other" in any other block
    heredoc = None
    in_comment = False
    with open(path, encoding="utf-8", errors="surrogateescape") as fh:
        for lineno, line in enumerate(fh, 1):
            line = line.rstrip("\n")
            where = f"{safe(label)}:{lineno}"
            if heredoc is not None:
                if line.strip() == heredoc:
                    heredoc = None
                continue
            if in_comment:
                if "*/" in line:
                    in_comment = False
                continue
            stripped = line.strip()
            if not stripped:
                continue  # blank lines never change the header
            if stripped.startswith("/*") and "*/" not in stripped:
                in_comment = True
                continue
            if stripped.startswith(("#", "//", "/*")):
                continue

            if not line[0].isspace():
                if line.startswith("}"):
                    header = None
                elif COL0_ATTRIBUTE.match(line):
                    findings.append(f"FAIL: {where}: attribute at column 0; run terraform fmt")
                else:
                    m = DOPPLER_HEADER.match(line)
                    if m:
                        stats["resources"] += 1
                        stats["files"].add(label)
                        rest = m.group(3).strip()
                        if rest and not rest.startswith(("#", "//")):
                            findings.append(
                                f"FAIL: {where}: {m.group(1)}.{safe(m.group(2))} one-line doppler block; "
                                "put description on its own line"
                            )
                            header = None
                        else:
                            header = (m.group(1), safe(m.group(2)))
                    else:
                        header = "other"
            else:
                d = DESCRIPTION.match(line)
                if d:
                    if header is None:
                        findings.append(
                            f"FAIL: {where}: description outside any top-level block; run terraform fmt"
                        )
                    elif header != "other":
                        measure(where, header, d.group(1), findings, stats)

            h = HEREDOC_START.search(line)
            if h:
                heredoc = h.group(1)


def measure(where, header, value, findings, stats):
    rtype, name = header
    lit = SINGLE_LITERAL.match(value.strip())
    if not lit or TEMPLATE.search(lit.group(1)):
        findings.append(
            f"FAIL: {where}: {rtype}.{name} description is not a single-line string literal; "
            "cannot measure. Use one literal; var., interpolation and heredoc are unsupported by design."
        )
        return
    n = len(lit.group(1).encode("utf-8", "surrogateescape"))
    stats["descriptions"] += 1
    stats["max"] = max(stats["max"], n)
    if n > DOPPLER_DESCRIPTION_MAX_BYTES:
        findings.append(
            f"FAIL: {where}: {rtype}.{name} description is {n} bytes (Doppler API cap "
            f"{DOPPLER_DESCRIPTION_MAX_BYTES}). Shorten by {n - DOPPLER_DESCRIPTION_MAX_BYTES} bytes; "
            "a non-ASCII character counts 2-4 bytes (an em dash is 3); "
            "put the rationale in a # comment above the attribute."
        )


def main(argv):
    files = [(p, p) for p in argv] if argv else tracked_tf_files()
    findings = []
    stats = {"resources": 0, "files": set(), "descriptions": 0, "max": 0}
    for path, label in files:
        scan(path, label, findings, stats)
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
    sys.exit(main(sys.argv[1:]))
