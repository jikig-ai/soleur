#!/usr/bin/env python3
"""Write a one-edit mutant of the proxy for the suite (#7980). stdlib only.

    make-proxy-mutant.py <proxy.py> <out.py> <function> <old> <new>

<old> must occur EXACTLY once in the source, and the line it lives on must fall
inside <function>'s `ast` line range (module-level constants use function
"<module>"). The mutant is asserted landed by the caller with `diff -q`; this
script's own exit is the second half: exit 3 if <old> is absent or not unique,
exit 4 if the hunk is outside the named function. Prints `MUTANT <function> line N`.
"""
import ast
import sys


def main(argv):
    if len(argv) != 5:
        sys.stderr.write(__doc__)
        return 2
    src_path, out_path, func, old, new = argv
    src = open(src_path, encoding="utf-8").read()
    if src.count(old) != 1:
        sys.stderr.write(f"make-proxy-mutant: <old> occurs {src.count(old)} times, need exactly 1: {old!r}\n")
        return 3
    pos = src.index(old)
    line_no = src.count("\n", 0, pos) + 1
    tree = ast.parse(src)
    if func == "<module>":
        lo, hi = 1, src.count("\n") + 1
    else:
        node = next((n for n in ast.walk(tree) if isinstance(n, (ast.FunctionDef, ast.ClassDef)) and n.name == func), None)
        if node is None:
            sys.stderr.write(f"make-proxy-mutant: no function {func}\n")
            return 4
        lo, hi = node.lineno, node.end_lineno
    if not (lo <= line_no <= hi):
        sys.stderr.write(f"make-proxy-mutant: hunk at line {line_no} is outside {func} ({lo}-{hi})\n")
        return 4
    mutated = src.replace(old, new)
    ast.parse(mutated)  # a mutant must still be a program, not a syntax error
    open(out_path, "w", encoding="utf-8").write(mutated)
    print(f"MUTANT {func} line {line_no}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
