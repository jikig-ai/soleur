#!/usr/bin/env python3
"""S7b J0 reach probe, instrumentation step (SANDBOX COPY ONLY; never run against a live checkout).

    python3 -I j0-instrument.py <sandbox root> <stubs.txt from j0-stubs.py> <fallback log path>

For each stub definition site printed by j0-stubs.py it inserts ONE marker line at the top of the stub:

    [ -p /dev/stdin ] && echo "<file>:<line>|<verb>|$*" >> "${S7B_REACH_LOG:-<fallback>}"

(dash-safe: no [[ ]], no here-strings). The marker records only when stdin of the stub is a pipe.
Sites that are not stub definitions (real functions in non-test files, `rc` text, helper-call text) are skipped
and listed. Line numbers in the marker tag are the ORIGINAL line numbers.
"""
import re
import sys
import os

root, stubs_file, fallback = sys.argv[1:4]
SKIP_VERBS = {'rc'}
sites = {}  # path -> list of (lineno, kind, verb)
verb = None
for raw in open(stubs_file):
    if raw.startswith('## '):
        verb = raw.rstrip('\n').split(' :: ')[1]
        continue
    m = re.match(r'\s+(\S+?):(\d+) \[(\w+)\] (.*)', raw)
    if not m or verb in SKIP_VERBS:
        continue
    path, ln, kind, text = m.group(1), int(m.group(2)), m.group(3), m.group(4)
    sites.setdefault(path, set()).add((ln, kind, verb))

def marker(path, ln, verb, escape):
    s = '[ -p /dev/stdin ] && echo "%s:%d|%s|$*" >> "${S7B_REACH_LOG:-%s}"' % (os.path.basename(path), ln, verb, fallback)
    return s.replace('$', '\\$') if escape else s

done, skipped = [], []
loop_seen = set()
for path, items in sorted(sites.items()):
    full = os.path.join(root, path)
    if not os.path.exists(full):
        skipped.append((path, 0, 'missing'))
        continue
    lines = open(full, errors='surrogateescape').read().split('\n')
    edits = {}  # index -> new text, or ('after', index, text)
    inserts = []  # (after_index, text)
    for ln, kind, verb in sorted(items):
        i = ln - 1
        l = lines[i]
        base = os.path.basename(path)
        is_test = base.endswith('.test.sh') or base.startswith('test-') or '/test/' in path or base.endswith('harness.sh') or 'stub-world' in base
        if kind == 'helper' and not re.search(r'\b(mkstub|make_stub|write_stub|stub_cmd)\b.*<<', l):
            skipped.append((path, ln, 'helper-text'))
            continue
        if kind == 'loop':
            if (path, ln) in loop_seen:
                continue
            loop_seen.add((path, ln))
            # S7c: a loop over verb names whose body writes the stub: mark the FIRST stub body found in the next 15 lines
            # (a heredoc, or a printf with a shebang format). The verb tag is the stub's own name at run time.
            lm = 'echo "%s:%d|loop:${0##*/}|$*" >> "${S7B_REACH_LOG:-%s}"' % (os.path.basename(path), ln, fallback)
            lm = '[ -p /dev/stdin ] && ' + lm
            hit = False
            for j in range(i + 1, min(i + 16, len(lines))):
                if lines[j].strip() == 'done':
                    break
                if '<<' in lines[j]:
                    unq = not re.search(r"<<-?\s*[\\]?['\"]", lines[j])
                    at = j + 1 if (j + 1 < len(lines) and lines[j + 1].startswith('#!')) else j
                    inserts.append((at, lm.replace('$', '\\$') if unq else lm))
                    done.append((path, ln, verb, 'loop-heredoc'))
                    hit = True
                    break
                mm = re.search(r"printf '#!(/bin/sh|/bin/bash|/usr/bin/env bash|%s)\\n", lines[j])
                if mm:
                    lines[j] = lines[j].replace(mm.group(0), mm.group(0) + lm + '\\n', 1)
                    done.append((path, ln, verb, 'loop-printf-fmt'))
                    hit = True
                    break
            if not hit:
                skipped.append((path, ln, 'loop-no-body'))
            continue
        if kind == 'fn':
            if not is_test:
                skipped.append((path, ln, 'real-function'))
                continue
            m = re.search(r'\b%s\(\)\s*\{' % re.escape(verb), l)
            if not m:
                skipped.append((path, ln, 'fn-no-match'))
                continue
            lines[i] = l[:m.end()] + ' ' + marker(path, ln, verb, False) + ';' + l[m.end():]
            done.append((path, ln, verb, 'fn'))
            continue
        # kind path / helper
        if '<<' in l:
            unq = not re.search(r"<<-?\s*[\\]?['\"]", l)
            nxt = i + 1
            at = i
            if nxt < len(lines) and lines[nxt].startswith('#!'):
                at = nxt
            elif re.search(r'mkstub', l):
                at = i  # prelude supplies the shebang
            inserts.append((at, marker(path, ln, verb, unq)))
            done.append((path, ln, verb, 'heredoc' + ('-unquoted' if unq else '')))
        elif "'#!/usr/bin/env bash' " in l:
            lines[i] = l.replace("'#!/usr/bin/env bash' ", "'#!/usr/bin/env bash' '%s' " % marker(path, ln, verb, False), 1)
            done.append((path, ln, verb, 'printf-args'))
        elif re.search(r"printf '#!(/bin/sh|/bin/bash|/usr/bin/env bash|%s)\\n", l):
            # S7c: also the '#!/bin/bash' and '#!%s' (a variable shebang) formats
            lines[i] = re.sub(r"(printf '#!(?:/bin/sh|/bin/bash|/usr/bin/env bash|%s)\\n)", lambda mm: mm.group(1) + marker(path, ln, verb, False) + '\\n', l, count=1)
            done.append((path, ln, verb, 'printf-fmt'))
        else:
            skipped.append((path, ln, 'unrecognised'))
    for at, text in sorted(set(inserts), reverse=True):
        lines.insert(at + 1, text)
    open(full, 'w', errors='surrogateescape').write('\n'.join(lines))
for d in done:
    print('INSTR', *d)
for s in skipped:
    print('SKIP', *s)
