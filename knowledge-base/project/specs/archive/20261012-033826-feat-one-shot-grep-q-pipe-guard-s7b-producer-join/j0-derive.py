#!/usr/bin/env python3
"""J0 for S7b (tracker #9217, Ref only): measure the producer-side join population.

Run from inside the repository, in a tree with an empty `git status --porcelain`:

    ulimit -v 6000000; python3 -I knowledge-base/project/specs/feat-one-shot-grep-q-pipe-guard-s7b-producer-join/j0-derive.py

Read-only: it lists tracked files and reads them; it writes nothing and runs no suite.

Definitions (one place, so the guard's derivation and this measurement cannot drift apart):

  non-test file   tracked .sh/.bash/.yml/.yaml file that is not test-shaped (see TESTISH) and not under
                  knowledge-base/ or a fixtures/ directory
  test file       tracked .sh file that is test-shaped
  text pipe       a non-comment line holding  (printf|echo|cat) ... | [sudo [-flags]] WORD
  stub of WORD    in a test file OR in a file it sources (one hop, matched by basename): a function definition
                  WORD() {  or a file written to  .../WORD  by cat/printf, or a stub-helper call naming WORD
                  (make_stub, write_stub, stub_cmd, mkstub, stub)
  owner           a test file whose non-comment lines hold the non-test file's basename as a whole token
                  (split on anything outside [A-Za-z0-9_.-], so `ci.yml` does not match inside `fci.yml`)
  pair            (test file, WORD) where the test file is an owner of a non-test file that has a text pipe
                  into WORD and the test file stubs WORD. The verb is DERIVED, never listed.

Funnel A is verb-free (the property). Funnel B repeats the series' earlier measure with a hand-written verb
registry (REGISTRY) so the two can be compared: the registry is exactly the identifier set that is narrower than
the property.
"""
import collections
import re
import subprocess
import sys

TESTISH = re.compile(r'(\.test\.sh$|^tests/|/tests?/|^knowledge-base/|\.md$|/fixtures/|\.test\.ts$|(^|/)test-[^/]*\.sh$)')
EXTS = ('.sh', '.bash', '.yml', '.yaml')
REGISTRY = {'gh', 'curl', 'doppler', 'docker', 'terraform', 'nft', 'ssh', 'sudo', 'systemctl', 'logger',
            'cryptsetup', 'openssl', 'tar', 'aws', 'mount', 'umount'}
PIPE = re.compile(r'(?:^|[^|])(?:printf|echo|cat)\b[^|\n]*?\|[ \t]*(?:sudo[ \t]+(?:-\w+[ \t]+)*)?([A-Za-z_][\w.-]*)')
FN = re.compile(r'^\s*(?:function\s+)?([A-Za-z_][\w-]*)\s*\(\)\s*\{', re.M)
PATHFILE = re.compile(r'(?:cat|printf)[^|\n]*>\s*"?[^ \n"]*/([A-Za-z][\w.-]*)"?(?:\s|$)')
HELPER = re.compile(r'(?:make_stub|write_stub|stub_cmd|mkstub|stub)\s+"?([A-Za-z][\w.-]*)')
SOURCED = re.compile(r'^\s*(?:\.|source)\s+"?([^"\s;]+)"?', re.M)
TOKEN = re.compile(r'[A-Za-z0-9_.-]+')
UNOBSERVED = re.compile(r'\|\|\s*(?:true|:)\b')


def tracked():
    out = subprocess.run(['git', 'ls-files'], capture_output=True, text=True, check=True).stdout
    return [f for f in out.split('\n') if f]


def code_lines(path):
    try:
        text = open(path, errors='replace').read()
    except OSError:
        return []
    return [l for l in text.split('\n') if not l.lstrip().startswith('#')]


def pipefail_in_scope(path, lines):
    body = '\n'.join(lines)
    if 'pipefail' in body:
        return True
    return path.endswith(('.yml', '.yaml')) and re.search(r'shell:\s*bash', body) is not None


def main():
    files = tracked()
    nontest = [f for f in files if f.endswith(EXTS) and not TESTISH.search(f)]
    tests = [f for f in files if f.endswith('.sh') and re.search(r'(\.test\.sh$|^tests/|/tests?/|(^|/)test-[^/]*\.sh$)', f)
             and not f.startswith('knowledge-base/') and '/fixtures/' not in f]
    tcode = {t: '\n'.join(code_lines(t)) for t in tests}
    ttokens = {t: set(TOKEN.findall(c)) for t, c in tcode.items()}
    own = {t: set(FN.findall(c)) | set(PATHFILE.findall(c)) | set(HELPER.findall(c)) for t, c in tcode.items()}
    by_base = collections.defaultdict(list)
    for f in files:
        by_base[f.rsplit('/', 1)[-1]].append(f)
    stubs = {}
    sourced_hits = 0
    for t, c in tcode.items():
        st = set(own[t])
        for ref in SOURCED.findall(c):
            cands = by_base.get(ref.rsplit('/', 1)[-1], [])
            if len(cands) == 1 and cands[0] != t and cands[0].endswith('.sh'):
                extra = set(FN.findall('\n'.join(code_lines(cands[0])))) | set(PATHFILE.findall('\n'.join(code_lines(cands[0]))))
                if extra - st:
                    sourced_hits += 1
                st |= extra
        stubs[t] = st

    sites = []  # (file, lineno, word, pipefail, observed)
    for f in nontest:
        lines = code_lines(f)
        pf = pipefail_in_scope(f, lines)
        for i, l in enumerate(lines):
            for m in PIPE.finditer(l):
                sites.append((f, i, m.group(1), pf, not UNOBSERVED.search(l)))

    owners = collections.defaultdict(list)
    for f in {s[0] for s in sites}:
        base = f.rsplit('/', 1)[-1]
        owners[f] = [t for t in tests if base in ttokens[t]]

    def pairs_for(site_filter):
        pairs = collections.defaultdict(set)
        for f, _, w, pf, obs in sites:
            if not site_filter(w, pf, obs):
                continue
            for t in owners[f]:
                if w in stubs[t]:
                    pairs[(t, w)].add(f)
        return pairs

    print('J0 funnel A: verb-free (the property); test files that gain stubs from a sourced file:', sourced_hits)
    print('  non-test files read:', len(nontest), '| test files read:', len(tests))
    print('  text-pipe lines:', len(sites), 'in', len({s[0] for s in sites}), 'files')
    pa = pairs_for(lambda w, pf, obs: pf and obs)
    print('  pairs (test file, verb) under pipefail with observed status:', len(pa),
          '| distinct non-test files behind them:', len({f for fs in pa.values() for f in fs}),
          '| distinct test files:', len({t for t, _ in pa}))
    print('  by verb:', dict(collections.Counter(w for _, w in pa).most_common()))

    print('J0 funnel B: hand-written registry (the series earlier recipe)')
    reg = [s for s in sites if s[2] in REGISTRY]
    print('  F0 lines:', len(reg), 'in', len({s[0] for s in reg}), 'files')
    f1 = [s for s in reg if s[3]]
    print('  F1 pipefail in file scope:', len(f1), 'in', len({s[0] for s in f1}), 'files')
    f2 = [s for s in f1 if s[4]]
    print('  F2 status observed:', len(f2), 'in', len({s[0] for s in f2}), 'files')
    f3 = [s for s in f2 if any(s[2] in stubs[t] for t in owners[s[0]])]
    print('  F3 an owner stubs the verb:', len(f3), 'in', len({s[0] for s in f3}), 'files')
    pb = pairs_for(lambda w, pf, obs: pf and obs and w in REGISTRY)
    print('  registry pairs (test file, verb):', len(pb), '| distinct test files:', len({t for t, _ in pb}))

    print('PAIRS (test file<TAB>verb<TAB>non-test files)')
    for (t, w), fs in sorted(pa.items()):
        print(f'{t}\t{w}\t{",".join(sorted(fs))}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
