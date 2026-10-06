#!/usr/bin/env python3
"""Census of curl call sites that carry a bearer token in their own argument list (#7843).

Measured procedure behind the plan's inventory (derivation 2). Run from the repo root:
    python3 knowledge-base/project/specs/feat-one-shot-7843-argv-bearer-to-config-stdin/census-argv-bearer.py
Prints `<sites>\t<path>` per file and a TOTAL line on stderr. Reads tracked files only; prints
no value other than paths and counts.

A SITE is one logical shell command (backslash continuations joined) that
  (a) contains a header flag (-H / --header) whose value is `Authorization: Bearer ...` and is not
      an `@file` / `@-` stdin form, or
  (b) passes a header flag whose value is a variable that the same file assigns from an
      `Authorization: Bearer ...` string (the seed-* scripts), counted once per `-H "$var"` use.
Comment lines are skipped. Test files, tests/ (except production gate libs matching
tests/scripts/lib/*-gate.sh), fixtures and knowledge-base/ are not scanned.
"""
import re, subprocess, sys

def tracked():
    out = subprocess.run(["git", "ls-files", "*.sh"], capture_output=True, text=True, check=True).stdout.split("\n")
    keep = []
    for f in out:
        if not f or f.endswith(".test.sh") or "/fixtures/" in f or f.startswith("knowledge-base/"):
            continue
        if f.startswith("tests/") and not re.match(r"tests/scripts/lib/[^/]*-gate\.sh$", f):
            continue
        if "/test/" in f:
            continue
        keep.append(f)
    return keep

BEARER = re.compile(r"Authorization:\s*Bearer")
HFLAG = re.compile(r"(?:-H|--header)\s+\\?[\"']?")
STDIN_FORM = re.compile(r"(?:-H|--header)\s+@")
CFG_LINE = re.compile(r"header\s*=\s*\"Authorization:\s*Bearer")

def logical(lines):
    i = 0
    while i < len(lines):
        j, buf = i, lines[i]
        while buf.rstrip().endswith("\\") and j + 1 < len(lines):
            j += 1
            buf = buf.rstrip()[:-1] + " " + lines[j].strip()
        yield i, buf
        i = j + 1

total = 0
rows = []
for f in tracked():
    try:
        lines = open(f, encoding="utf-8").read().split("\n")
    except Exception as e:  # unreadable -> report, never skip silently
        print("ERR", f, e, file=sys.stderr); continue
    body = "\n".join(l for l in lines if not l.lstrip().startswith("#"))
    held = set(re.findall(r"^\s*(?:local\s+)?(\w+)=[\"']Authorization:\s*Bearer", body, re.M))
    n = 0
    for _, buf in logical(lines):
        if buf.lstrip().startswith("#"):
            continue
        if BEARER.search(buf) and HFLAG.search(buf) and not STDIN_FORM.search(buf) and not CFG_LINE.search(buf):
            n += 1
            continue
        for v in held:
            n += len(re.findall(r"(?:-H|--header)\s+\"\$\{?%s\}?\"" % re.escape(v), buf))
    if n:
        rows.append((f, n)); total += n
for f, n in sorted(rows):
    print(f"{n}\t{f}")
print(f"TOTAL sites={total} files={len(rows)}", file=sys.stderr)
