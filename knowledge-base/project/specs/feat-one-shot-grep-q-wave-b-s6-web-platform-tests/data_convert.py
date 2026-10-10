#!/usr/bin/env python3
"""S6 throwaway: convert the data-tier lines the codemod routes to its hand queue, one token per early-exit span.

usage: data_convert.py ROOT FILE LINE [LINE ...]        (BASE-side line numbers; run once per file, BEFORE any line-count change)
       data_convert.py --check ROOT FILE LINE [LINE ...]   (dry run: print what would change)

It reuses scripts/grep-q-drain-codemod.py's own span finder and token rewrite (parse_span, rewrite_span_token), so a converted line is
exactly transform(removed line) and `verify` counts it as a plain transform. It differs from the codemod in ONE decision only: it does
not stop at the tokenizer's `data` verdict for the lines a human has read and listed on the command line (each is an eval-ed assertion
string or a stub body: see data-conversions.txt). Every span on a listed line must be rewritable; anything else aborts with rc 3 and
writes nothing for that file. Never run it on a line that was not read in context.
"""
import importlib.util
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def load_codemod(root):
    spec = importlib.util.spec_from_file_location("cm", os.path.join(root, "scripts", "grep-q-drain-codemod.py"))
    cm = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(cm)
    return cm


def main(argv):
    check = False
    if argv and argv[0] == "--check":
        check, argv = True, argv[1:]
    if len(argv) < 3:
        print(__doc__, file=sys.stderr)
        return 2
    root, path, lines = os.path.abspath(argv[0]), argv[1], [int(x) for x in argv[2:]]
    cm = load_codemod(root)
    pat, pathspec, marker, _rows = cm.load_guard(os.path.join(root, cm.GUARD))
    pop = cm.population(root, pat, pathspec, marker)
    if path not in pop:
        print("UNRESOLVED: %s has no early-exit site in the guard's population" % path, file=sys.stderr)
        return 3
    with open(cm.fpath(root, path), "rb") as fh:
        src = fh.read().decode("latin-1").split("\n")
    out = list(src)
    for ln in lines:
        hits = pop[path].get(ln)
        if not hits:
            print("UNRESOLVED: %s:%d is not a site" % (path, ln), file=sys.stderr)
            return 3
        new = out[ln - 1]
        for col0, span in sorted(hits, reverse=True):
            verdict = cm.parse_span(span)
            if verdict[0] != "T0":
                print("UNRESOLVED: %s:%d span %r is %s %s, not a plain transform" % (path, ln, span, verdict[0], verdict[1]), file=sys.stderr)
                return 3
            res = cm.rewrite_span_token(new, col0, span, verdict[1])
            if res is None:
                print("UNRESOLVED: %s:%d span %r does not line up" % (path, ln, span), file=sys.stderr)
                return 3
            new = res
        assert new != out[ln - 1], (path, ln)
        print("%s:%d: %d span(s)" % (path, ln, len(hits)))
        out[ln - 1] = new
    if not check:
        with open(cm.fpath(root, path), "wb") as fh:
            fh.write("\n".join(out).encode("latin-1"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
