#!/usr/bin/env python3
"""J0 for S7c (tracker #9217, Ref only): measure the derivation-recall population of the producer-side join.

Run from inside the repository, in a tree with an empty `git status --porcelain`:

    ulimit -v 6000000; python3 -I knowledge-base/project/specs/feat-one-shot-grep-q-pipe-guard-s7c-derivation-recall/j0-derive.py

Read-only: it lists tracked files and reads them; it writes nothing and runs no suite.

The BASE rules are a port of the guard's own derivation (`PJ_AWK` in `.claude/hooks/grep-q-pipe-guard.test.sh`, the
S7b state): the base run MUST print the guard's own numbers (66 pairs, 120 producer triples at 0aae3f8680), or the port
has drifted and every other figure below is void. Each recall ARM then relaxes exactly one rule of the base, so its
increment over the base is attributable to that arm alone; the union row turns every arm on.

  R1 lines    a logical line joined over a trailing backslash or a trailing single pipe, then scanned
  R2 wrap     the verb behind timeout / env / command / nice / stdbuf / exec / builtin / VAR=x (the wrapper stays a verb too)
  R3 prod     a producer other than printf/echo/cat (any stage before a single bar)
  R4 lib      pipefail taken from the process that runs the pipe: (a) forced on, (b) a file that sources the library has it,
              (c) the owning test file has it
  R5 stubs    a stub made by a helper whose verb is not the first argument, or by a loop over verb names
  R6 files    producers in .tf/.tftpl/.tpl/.tmpl/.template/.service files and in extensionless files with a shebang
  R8 annot    an annotation echo is stripped from its token to the closing unescaped quote of its string, not to the end of the line, so a pipe after it (or inside a command substitution in it) is read
  R7 stubname the guard's stub-file arm records `jq";` (quote and semicolon kept) for a stub written `> "$d/jq"; chmod`: found by this J0, not in the brief
"""
import collections
import re
import subprocess
import sys

TESTISH = re.compile(r'(\.test\.sh$|^tests/|/tests?/|^knowledge-base/|\.md$|/fixtures/|\.test\.ts$|(^|/)test-[^/]*\.sh$)')
TESTSHAPE = re.compile(r'(\.test\.sh$|^tests/|/tests?/|(^|/)test-[^/]*\.sh$)')
BASE_EXT = ('.sh', '.bash', '.yml', '.yaml')
ARM_EXT = ('.tf', '.tftpl', '.tmpl', '.template', '.service')   # the guard's extension list (PJ_EXTS); `.tpl` and the extensionless half of R6 were cut with the measure
PIPE = re.compile(r'(^|[^|])(printf|echo|cat)([^A-Za-z0-9_|][^|]*)?\|[ \t]*(sudo[ \t]+(-[A-Za-z0-9_]+[ \t]+)*)?([A-Za-z_][A-Za-z0-9_.-]*)')
UNOBS = re.compile(r'\|\|[ \t]*(true|:)([^A-Za-z0-9_]|$)')
FNRE = re.compile(r'^[ \t]*(function[ \t]+)?([A-Za-z_][A-Za-z0-9_-]*)[ \t]*\(\)[ \t]*\{')
PATHRE = re.compile(r'(cat|printf)[^|]*>[ \t]*"?[^ "]*/([A-Za-z][A-Za-z0-9_.-]*)"?([ \t;]|$)')
HELPERS = r'(?:make_stub|write_stub|stub_cmd|mkstub|stub)'
HELPRE = re.compile(HELPERS + r'[ \t]+"?([A-Za-z][A-Za-z0-9_.-]*)')
HELPCALL = re.compile(r'^[ \t]*' + HELPERS + r'[ \t]+(.*)$')
HELPCALL_ANY = re.compile(r'^[ \t]*(?:make_stub|write_stub|stub_cmd|mkstub|stub|mk_stub|make_shim|mkshim|fake_bin|fake_cmd|make_fake|stub_bin|install_stub|shim)\b[ \t]*(.*)$')
SRCRE = re.compile(r'^[ \t]*(?:\.|source)[ \t]+"?([^" \t;]+)')
TOKRE_BASE = re.compile(r'[A-Za-z0-9_.-]+[.](?:sh|bash|yml|yaml)(?=[^A-Za-z0-9_.-]|$)')
TOKRE_ARM = re.compile(r'[A-Za-z0-9_.-]+[.](?:sh|bash|yml|yaml|tf|tftpl|tmpl|template|service)(?=[^A-Za-z0-9_.-]|$)')
ANNOT = re.compile(r'::(error|warning|notice)::.*$')
ANNOT_STR = re.compile(r'::(error|warning|notice)::(?:[^"\\]|\\.)*(?:"|$)')
YAML_BLOCK = re.compile(r'(:|(^|[ \t])-)[ \t]*[|>][-+]?[ \t]*$')   # `key: |` and the list-item `- |` (decision-challenges item 19)
CASE_ALT = re.compile(r'^[ \t]*[A-Za-z_][A-Za-z0-9_.-]*[ \t]*\)')
WORD = re.compile(r'[A-Za-z_][A-Za-z0-9_.-]*')
FORRE = re.compile(r'^[ \t]*for[ \t]+([A-Za-z_][A-Za-z0-9_]*)[ \t]+in[ \t]+(.*?);?[ \t]*(?:;[ \t]*do\b|$)')

ARMS = ('R1', 'R2', 'R3', 'R4a', 'R4b', 'R4c', 'R5a', 'R5b', 'R6', 'R7', 'R8')


def outside_quotes(text):
    """quote parity of the text before a bar: an even number of unescaped double quotes and of single quotes"""
    t = re.sub(r'\\.', '', text)
    return t.count('"') % 2 == 0 and t.count("'") % 2 == 0


def tracked():
    out = subprocess.run(['git', 'ls-files', '-z'], capture_output=True, check=True).stdout
    return [f.decode('utf-8', 'replace') for f in out.split(b'\0') if f]


def read(path):
    try:
        with open(path, 'rb') as fh:
            return fh.read().decode('utf-8', 'replace')
    except OSError:
        return ''


def base(p):
    return p.rsplit('/', 1)[-1]


def has_shebang(text):
    return text.startswith('#!')


def logical_lines(raw, join):
    """Yield (lineno, text). With join, a code line ending in a backslash or a single pipe absorbs the next line."""
    out = []
    i = 0
    n = len(raw)
    while i < n:
        line = raw[i]
        start = i
        if join:
            while i + 1 < n and not line.lstrip().startswith('#'):
                s = line.rstrip()
                if s.endswith('\\') and not s.endswith('\\\\'):
                    nxt = raw[i + 1]
                    line = s[:-1] + ' ' + nxt.lstrip()
                    i += 1
                elif s.endswith('|') and not s.endswith('||') and not YAML_BLOCK.search(s) and outside_quotes(s[:-1]):
                    j = i + 1
                    while j < n and raw[j].lstrip().startswith('#'):   # a comment line between the stages of a pipe is not code: the pipe goes on past it
                        j += 1
                    if j >= n:
                        break
                    line = s + ' ' + raw[j].lstrip()
                    i = j
                else:
                    break
        out.append((start + 1, line))
        i += 1
    return out


WRAP_SIMPLE = {'command', 'builtin', 'exec', 'env', 'nice', 'stdbuf', 'timeout'}
# per-wrapper flags that take the next token as an operand (the guard's awk carries the same table)
WRAP_ARG = {'timeout': {'-k', '-s', '--kill-after', '--signal'}, 'nice': {'-n'}, 'env': {'-u', '--unset'},
            'stdbuf': {'-i', '-o', '-e'}, 'exec': {'-a'}, 'command': set(), 'builtin': set()}


def unwrap(after):
    """text after a pipe -> list of verb words: the first word, and the word behind wrappers and VAR=x assignments (R2).
    Mirrors the guard's awk: `command -v` and `-V` are queries and name no verb; a wrapper has its own flag arity."""
    toks = after.split()
    verbs = []
    i = 0
    while i < len(toks):
        t = toks[i].strip('"\'(){};')
        if t == 'sudo':
            i += 1
            while i < len(toks) and toks[i].startswith('-'):
                i += 1
            continue
        if re.match(r'^[A-Za-z_][A-Za-z0-9_]*=', t):
            i += 1
            continue
        if not WORD.fullmatch(t):
            return verbs
        verbs.append(t)
        if t not in WRAP_SIMPLE:
            return verbs
        w = t
        i += 1
        while i < len(toks):
            u = toks[i]
            if u.startswith('-'):
                i += 1
                if w == 'command' and u in ('-v', '-V'):
                    return verbs
                if u in WRAP_ARG[w] and i < len(toks):
                    i += 1
                continue
            if re.match(r'^[A-Za-z_][A-Za-z0-9_]*=', u):
                i += 1
                continue
            if w == 'timeout' and re.fullmatch(r'[0-9]+(\.[0-9]+)?[smhd]?', u):
                i += 1
                continue
            break
    return verbs


def sites_in(path, text, arms, forced_pf):
    """-> list of (verb, observed) text-pipe sites, and the file's own pipefail flag."""
    raw = text.split('\n')
    is_yaml = path.endswith(('.yml', '.yaml'))
    pf = False
    out = []
    for _, line in logical_lines(raw, 'R1' in arms):
        if re.match(r'^[ \t]*#', line):
            continue
        l = (ANNOT_STR if 'R8' in arms else ANNOT).sub('', line)
        if 'pipefail' in l:
            pf = True
        if is_yaml and re.search(r'shell:[ \t]*bash', l):
            pf = True
        if '|' not in l:
            continue
        obs = UNOBS.search(l) is None
        if 'R3' in arms:
            # every single bar: the stage after it (a producer of any kind before it)
            for m in re.finditer(r'(?<![|\\])\|(?!\|)&?', l):
                after = l[m.end():]
                if not outside_quotes(l[:m.start()]) or CASE_ALT.match(after):
                    continue
                vs = unwrap(after) if 'R2' in arms else unwrap_first(after)
                for v in vs:
                    out.append((v, obs))
        if 'printf' in l or 'echo' in l or 'cat' in l:
            s = l
            while True:
                m = PIPE.search(s)
                if not m:
                    break
                tail = s[m.end():]
                s = tail
                word = m.group(6)
                vs = [word]
                if 'R2' in arms and (word in WRAP_SIMPLE or tail.startswith('=')):
                    vs = [word] + unwrap(word + ('' if tail.startswith('=') else ' ') + tail.split('|')[0])   # the word itself stays a site, as in the base
                for v in vs:
                    out.append((v, obs))
    return out, pf


def unwrap_first(after):
    toks = after.split()
    i = 0
    while i < len(toks):
        t = toks[i].strip('"\'(){};')
        if t == 'sudo':
            i += 1
            while i < len(toks) and toks[i].startswith('-'):
                i += 1
            continue
        if WORD.fullmatch(t):
            return [t]
        return []
    return []


BARE = re.compile(r'^[a-z][a-z0-9_.-]*$')
WRITE_TO_PARAM = re.compile(r'>>?[ \t]*"?[^ "\n]*/(\$\{?([1-9])\}?|\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?)"?')
LOCALP = re.compile(r'(?:local[ \t]+)?([A-Za-z_][A-Za-z0-9_]*)="?\$\{?([1-9])\}?')


def stub_set(path, text, arms, is_test, extra_helpers=None):
    """-> the set of verbs the file stubs (function definitions, files written to .../WORD, and for a test file helper calls)."""
    st = set()
    raw = text.split('\n')
    for idx, line in enumerate(raw):
        if re.match(r'^[ \t]*#', line):
            continue
        l = ANNOT.sub('', line)
        if '()' in l:
            m = FNRE.match(l)
            if m:
                st.add(m.group(2))
        if '>' in l and ('cat' in l or 'printf' in l):
            for m in PATHRE.finditer(l):
                if 'R7' in arms:
                    st.add(m.group(2))
                else:
                    # the guard's own awk: sub(/"?[ \t]?$/, "") then basename; a trailing ; stays on the name
                    full = re.sub(r'"?[ \t]?$', '', m.group(0), count=1)
                    st.add(full.rsplit('/', 1)[-1])
        if is_test and 'stub' in l:
            for m in HELPRE.finditer(l):
                st.add(re.sub(r'^' + HELPERS + r'[ \t]+"?', '', m.group(0)))
        if is_test and 'R5a' in arms:
            # a stub-helper call at the start of a statement: every bare lowercase argument (the verb is not always the first: mkstub DIR VERB)
            m = re.match(r'^[ \t]*' + HELPERS + r'[ \t]+([^<>;|&)]*)', l)
            if m:
                for w in m.group(1).split():
                    w = w[1:-1] if len(w) > 2 and w[0] == '"' and w[-1] == '"' else w
                    if BARE.match(w):
                        st.add(w)
        if is_test and 'R5b' in arms:
            m = FORRE.match(l)
            if m:
                var = m.group(1)
                words = [w.strip('"\'') for w in m.group(2).split()]
                body = '\n'.join(raw[idx + 1: idx + 16])
                end = body.find('\ndone')
                if end >= 0:
                    body = body[:end]
                pat = r'(\$' + var + r'\b|\$\{' + var + r'\})'
                if re.search(r'(cat|printf)[^\n|]*>>?[ \t]*"?[^ "\n]*/' + pat, body) or re.search(r'^[ \t]*(' + '|'.join(['make_stub', 'write_stub', 'stub_cmd', 'mkstub', 'stub']) + r')\b[^\n]*' + pat, body, re.M):
                    for w in words:
                        if BARE.match(w):
                            st.add(w)
    return st


def derive(files, arms, quiet=True):
    arms = set(arms)
    nontest_ext = BASE_EXT + (ARM_EXT if 'R6' in arms else ())
    ftext = {}

    def get(p):
        if p not in ftext:
            ftext[p] = read(p)
        return ftext[p]

    nontest = []
    for f in files:
        if f.startswith('knowledge-base/') or TESTISH.search(f):
            continue
        if f.endswith(nontest_ext):
            nontest.append(f)
    tests = [f for f in files if f.endswith('.sh') and TESTSHAPE.search(f) and not f.startswith('knowledge-base/') and '/fixtures/' not in f]
    bc = collections.Counter(base(f) for f in files)
    bp = {base(f): f for f in files}
    tokre = TOKRE_ARM if 'R6' in arms else TOKRE_BASE

    ttok = {}
    tstub = {}
    tsrc = {}
    tpf = {}
    for t in tests:
        text = get(t)
        toks = set()
        refs = []
        pf = False
        for line in text.split('\n'):
            if re.match(r'^[ \t]*#', line):
                continue
            l = ANNOT.sub('', line)
            if 'pipefail' in l:
                pf = True
            if any(e in l for e in ('.sh', '.bash', '.yml', '.yaml', '.tf', '.tftpl', '.tmpl', '.template', '.service')):
                for m in tokre.finditer(l):
                    toks.add(m.group(0))
            if re.match(r'^[ \t]*(\.|source)[ \t]', l):
                m = SRCRE.match(l)
                if m:
                    refs.append(base(m.group(1)))
        ttok[t] = toks
        tsrc[t] = refs
        tpf[t] = pf
        tstub[t] = stub_set(t, text, arms, True)

    fstub = {}
    for t in tests:
        st = set(tstub[t])
        for r in tsrc[t]:
            if bc[r] == 1:
                c = bp[r]
                if c != t and c.endswith('.sh'):
                    if c not in fstub:
                        fstub[c] = stub_set(c, get(c), set(), False)
                    st |= fstub[c]
        tstub[t] = st

    # sources map for R4b: library basename -> files that source it
    sourcers = collections.defaultdict(list)
    if 'R4b' in arms:
        for f in files:
            if f.endswith(('.sh', '.bash', '.yml', '.yaml')) and not f.startswith('knowledge-base/'):
                for line in get(f).split('\n'):
                    if re.match(r'^[ \t]*(\.|source)[ \t]', line) and not re.match(r'^[ \t]*#', line):
                        m = SRCRE.match(line)
                        if m:
                            sourcers[base(m.group(1))].append(f)

    fsites = {}
    fpf = {}
    for f in nontest:
        s, pf = sites_in(f, get(f), arms, False)
        fsites[f] = s
        fpf[f] = pf

    def pf_for(f, t):
        if fpf[f]:
            return True
        if 'R4a' in arms:
            return True
        if 'R4b' in arms and any(fpf.get(g, False) or ('pipefail' in get(g)) for g in sourcers.get(base(f), [])):
            return True
        if 'R4c' in arms and tpf.get(t):
            return True
        return False

    triples = set()
    for f in nontest:
        if not fsites[f]:
            continue
        b = base(f)
        for t in tests:
            if not any(tok == b or tok.endswith('/' + b) for tok in ([b] if b in ttok[t] else [])):
                continue
            for v, obs in fsites[f]:
                if obs and v in tstub[t] and pf_for(f, t):
                    triples.add((t, v, f))
    return triples


def main():
    files = tracked()
    results = {}
    plan = [('BASE', ()), ('R1', ('R1',)), ('R2', ('R2',)), ('R3', ('R3',)),
            ('R4a', ('R4a',)), ('R4b', ('R4b',)), ('R4c', ('R4c',)), ('R5a', ('R5a',)), ('R5b', ('R5b',)),
            ('R6', ('R6',)), ('R7', ('R7',)), ('R8', ('R8',)),
            # the sizing rows: U1 is the brief's list without the any-producer arm and with the sourced-library rule only;
            # U2 adds the any-producer arm; ALL turns every arm on (R4a and R4c are the over-inclusive pipefail readings)
            ('U1 = R1+R2+R4b+R5a+R5b+R6+R7+R8', ('R1', 'R2', 'R4b', 'R5a', 'R5b', 'R6', 'R7', 'R8')),
            ('U2 = U1+R3', ('R1', 'R2', 'R3', 'R4b', 'R5a', 'R5b', 'R6', 'R7', 'R8')),
            ('ALL', ('R1', 'R2', 'R3', 'R4a', 'R4b', 'R4c', 'R5a', 'R5b', 'R6', 'R7', 'R8'))]
    for name, arms in plan:
        results[name] = derive(files, arms)
    pairs = lambda s: {(t, v) for t, v, _ in s}
    base_t = results['BASE']
    base_p = pairs(base_t)
    print('J0 S7c: base is the port of the guard derivation (S7b state)')
    print(f'  BASE: {len(base_p)} pairs, {len(base_t)} producer triples (the guard prints 66 and 120 at 0aae3f8680)')
    for name in results:
        if name == 'BASE':
            continue
        new_t = results[name] - base_t
        new_p = pairs(results[name]) - base_p
        lost = base_p - pairs(results[name])
        print(f'  {name}: +{len(new_p)} pairs, +{len(new_t)} triples over base; {len({t for t, _ in new_p})} test files; lost vs base: {len(lost)}')
        print('    by verb:', dict(collections.Counter(v for _, v in sorted(new_p)).most_common(12)))
    print('NEW PAIRS PER ARM (test file<TAB>verb<TAB>producer files)')
    for name in results:
        if name == 'BASE':
            continue
        new_t = results[name] - base_t
        by = collections.defaultdict(set)
        for t, v, f in new_t:
            by[(t, v)].add(f)
        for (t, v), fs in sorted(by.items()):
            if (t, v) in base_p:
                tag = 'new-producer-for-listed-pair'
            else:
                tag = 'new-pair'
            print(f'{name}\t{tag}\t{t}\t{v}\t{",".join(sorted(fs))}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
