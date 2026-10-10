#!/usr/bin/env python3
"""S6 hand tier: applies the 22 base lines of hand-edits.txt (the 2 inserted lines come from the two restructures).

usage: hand_apply.py ROOT          (run AFTER the codemod passes and data_convert.py, BEFORE the guard edit; BASE-side line numbers)

Every replacement asserts that its old text occurs exactly once on the stated base-side line, and the marker appends assert the line does
not end in a continuation backslash. Edits run bottom-up inside a file, so the two inserted lines never shift a later key. Nothing here is
a regexp over the file: a drifted base line aborts with the file and line. After it runs, `verify --hand-edits hand-edits.txt` must print
`unexplained: 0`.
"""
import os
import sys

A = "apps/web-platform/infra/"
S = "apps/web-platform/scripts/"
T = "apps/web-platform/test/infra/"
MARK = "  # sigpipe-demo: intentional"

EQ = []      # (path, line, old, new)  same line count
MARKS = []   # (path, line, reason or None)


def eq(path, line, old, new):
    EQ.append((path, line, old, new))


def mark(path, line, reason=None):
    MARKS.append((path, line, reason))


# -m forms: producer moved into a process substitution
eq(A + "ci-deploy.test.sh", 4184, """$(sh -c "$D9_SCRIPT" soleur-canary-diag 2>/dev/null | grep -m1 '^proc ' || true)""",
   """$(grep -m1 '^proc ' < <(sh -c "$D9_SCRIPT" soleur-canary-diag 2>/dev/null) || true)""")
eq(S + "dev-ledger-parity.test.sh", 3101, """$(sed -n "${l_snap},\\$p" "$XP" | grep -m1 -F 'RAISE EXCEPTION')""",
   """$(grep -m1 -F 'RAISE EXCEPTION' < <(sed -n "${l_snap},\\$p" "$XP"))""")
eq(S + "dev-ledger-parity.test.sh", 3102, """$(sed -n "${l_post},\\$p" "$XP" | grep -m1 -F 'RAISE EXCEPTION')""",
   """$(grep -m1 -F 'RAISE EXCEPTION' < <(sed -n "${l_post},\\$p" "$XP"))""")
eq(A + "workspaces-luks-loopback.test.sh", 1006, """$(head -n1 "$L6KCAP_ERR" "$L6KCAP_ENVERR" 2>/dev/null | grep -m1 fatal:)""",
   """$(grep -m1 fatal: < <(head -n1 "$L6KCAP_ERR" "$L6KCAP_ENVERR" 2>/dev/null))""")
# display labels
eq(A + "cron-egress-self-heal.test.sh", 330, "the OLD 'nft | grep -q' form", "the OLD nft-piped-into-grep-q form")
eq(A + "cron-egress-self-heal.test.sh", 340, "the OLD 'nft | grep -q' form", "the OLD nft-piped-into-grep-q form")
eq(A + "supabase-advisor/scan-workflow-mutation.test.sh", 118, "D2 'printf \\$var | grep -q' false-FAILs", "D2 the printf-then-grep-q form false-FAILs")
# kept and marked in place (a reason with no quote characters: run-registered-suites.test.sh:828 documents the nested-fragment trap)
for p, l, why in [
    (A + "cron-egress-self-heal.test.sh", 329, "the OLD pipeline form the SIGPIPE control must reproduce"),
    (A + "cron-egress-self-heal.test.sh", 339, "the same control with SIGPIPE forced ignored"),
    (A + "supabase-advisor/scan-workflow-mutation.test.sh", 93, "D1 demonstration, the unfixed piped shape"),
    (A + "supabase-advisor/scan-workflow-mutation.test.sh", 94, "D2 demonstration, the printf-fed shape"),
    (A + "supabase-advisor/scan-workflow-mutation.test.sh", 158, "R1 mutation recipe that restores the piped shape"),
    (A + "supabase-advisor/scan-workflow-mutation.test.sh", 178, "needle equal to the companion suite message"),
    (A + "workspaces-luks-freeze.test.sh", 1500, "M3 mutation recipe that re-introduces a piped predicate"),
    (A + "workspaces-luks-freeze.test.sh", 1501, "M3 landing check"),
    (A + "registry-luks-launch-gate.test.sh", 83, "needle for cloud-init-registry.yml bytes; update with that carrier"),
    (A + "registry-luks.test.sh", 181, "needle for cloud-init-registry.yml bytes; update with that carrier"),
    (A + "registry-luks.test.sh", 278, "recipe that deletes a cloud-init-registry.yml line; update with that carrier"),
    (A + "workspaces-luks-verify-root-mtime.test.sh", 461, "message text cited by run-registered-suites.test.sh"),
]:
    mark(p, l, why)

INSERTS = []  # (path, base line to insert BEFORE, new text, [(line, old, new)...])
# self-heal: the mutant text moves into one marked variable placed before the first mut_probe of the pair (base line 533)
INSERTS.append((A + "cron-egress-self-heal.test.sh", 533,
                """MUT_EARLY_PIPE='ip filter DOCKER-USER 2>&1 | grep -m1 "jump SOLEUR-EGRESS")"'""" + MARK + " (the early-exiting capture the mutants below re-introduce)",
                [(534, """'ip filter DOCKER-USER 2>&1 | grep -m1 "jump SOLEUR-EGRESS")"'""", '"$MUT_EARLY_PIPE"'),
                 (537, """'ip filter DOCKER-USER 2>&1 | grep -m1 "jump SOLEUR-EGRESS")"'""", '"$MUT_EARLY_PIPE"')]))
# ghcr-blocked-alert: the needle moves into one marked variable placed immediately before base line 167
INSERTS.append((T + "ghcr-blocked-alert.test.sh", 167, None, None))


def main(root):
    root = os.path.abspath(root)
    per_file = {}
    for p, l, o, n in EQ:
        per_file.setdefault(p, []).append(("eq", l, o, n))
    for p, l, why in MARKS:
        per_file.setdefault(p, []).append(("mark", l, why, None))
    for p, before, text, subs in INSERTS:
        per_file.setdefault(p, []).append(("ins", before, text, subs))
    for p, ops in sorted(per_file.items()):
        fp = os.path.join(root, p)
        with open(fp, encoding="utf-8") as fh:
            src = fh.read().split("\n")
        for kind, l, a, b in sorted(ops, key=lambda x: -x[1]):   # bottom-up
            i = l - 1
            if kind == "eq":
                assert src[i].count(a) == 1, (p, l, a, src[i])
                src[i] = src[i].replace(a, b)
            elif kind == "mark":
                assert not src[i].rstrip().endswith("\\"), (p, l)
                assert "sigpipe-demo" not in src[i], (p, l)
                src[i] = src[i] + MARK + " (" + a + ")"
            elif kind == "ins" and a is not None:
                for sl, so, sn in b:
                    assert src[sl - 1].count(so) == 1, (p, sl, so, src[sl - 1])
                    src[sl - 1] = src[sl - 1].replace(so, sn)
                src.insert(i, a)
            else:   # ghcr-blocked-alert
                line = src[i]
                head, tail = "grep -qE ", ' "$CR" \\'
                assert line.startswith(head + "'^[[:space:]]*if printf .%s") and line.endswith(tail), (p, l, line)
                pat = line[len(head):-len(tail)]
                src[i] = 'grep -qE "$R_EMIT_RE" "$CR" \\'
                src.insert(i, "R_EMIT_RE=" + pat + MARK + " (needle for the registry carrier emitter line; update with that carrier)")
        with open(fp, "w", encoding="utf-8") as fh:
            fh.write("\n".join(src))
        print("%s: %d edit(s)" % (p, len(ops)))
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    sys.exit(main(sys.argv[1]))
