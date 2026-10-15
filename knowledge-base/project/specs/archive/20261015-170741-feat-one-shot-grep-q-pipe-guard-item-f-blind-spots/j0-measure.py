#!/usr/bin/env python3
"""Item F plan-time measurement (J0). Read-only; run: python3 -I j0-measure.py [--samples N] [--cat NAME].

It is NOT the guard. It tokenises every logical code line of the swept population (the guard's extension
pathspec, every knowledge-base archive/ directory and the guard file excluded, comment lines and `# sigpipe-demo: intentional`
lines dropped) and classifies the READER stage after each unquoted single bar, so each blind spot of the
line regex is counted by the property it is about instead of by one more regex. Each figure is a
point-in-time count: re-run it before quoting one (counts rot).
"""
import re, subprocess, sys, collections, os

SAMPLES = 4
ONLY = None
a = sys.argv[1:]
while a:
    x = a.pop(0)
    if x == '--samples': SAMPLES = int(a.pop(0))
    elif x == '--cat': ONLY = a.pop(0)

ROOT = subprocess.check_output(['git', 'rev-parse', '--show-toplevel'], text=True).strip()
os.chdir(ROOT)
GUARD = '.claude/hooks/grep-q-pipe-guard.test.sh'
# The population is the guard's own: SWEEP_EXTS is read from the guard text (so a changed list moves this script too), and every knowledge-base archive/
# directory is excluded, nothing else of knowledge-base (the Item F state; the plan-time run used 8 extensions and all of knowledge-base).
EXTS = tuple('.' + e for e in re.search(r'^SWEEP_EXTS=\(([^)]*)\)', open(GUARD).read(), re.M).group(1).split())
files = subprocess.check_output(['git', '-c', 'core.excludesFile=/dev/null', 'ls-files', '-co', '--exclude-standard'], text=True).split('\n')
files = [f for f in files if f.endswith(EXTS) and not re.match(r'knowledge-base/(.*/)?archive/', f) and f != GUARD and os.path.isfile(f)]

MARK = re.compile(r'\s#\s*sigpipe-demo:\s*intentional(\s|$)')
GREPS = {'grep', 'egrep', 'fgrep', 'zgrep', 'zegrep', 'rg', 'ag', 'ack', 'pcregrep', 'ugrep'}
WRAP0 = {'command', 'builtin', 'exec', 'env', 'nice', 'timeout', 'stdbuf', 'sudo', 'time', 'xargs', 'nohup', 'setsid', 'doas', 'ionice', 'chrt'}
ARG_AFTER = {'-e', '-f', '-A', '-B', '-C', '-d', '-D', '--label', '--regexp', '--file', '--include', '--exclude', '--exclude-dir', '--context', '--after-context', '--before-context', '--directories', '--devices', '--binary-files'}
LONG_EARLY = ('quiet', 'silent', 'max-count')
BLOCK = re.compile(r':\s*[|>][-+]?\s*$|^\s*-?\s*[|>][-+]?\s*$')


def bars(s):
    """(index, kind) of unquoted single bars outside $( ) is NOT tracked: quotes only, as the guard's own scan."""
    q = None; i = 0; out = []
    while i < len(s):
        c = s[i]
        if q:
            if c == '\\' and q == '"': i += 2; continue
            if c == q: q = None
        else:
            if c in '\'"': q = c
            elif c == '\\': i += 2; continue
            elif c == '|':
                if i + 1 < len(s) and s[i + 1] == '|': i += 2; continue
                if i > 0 and s[i - 1] == '|': i += 1; continue
                out.append(i)
        i += 1
    return out


def stage_end(s, i):
    q = None
    j = i
    while j < len(s):
        c = s[j]
        if q:
            if c == q: q = None
        else:
            if c in '\'"': q = c
            elif c in '|;)}' or s.startswith('&&', j): return j
        j += 1
    return j


def toks(t):
    import shlex
    try: return shlex.split(t)
    except ValueError: return t.split()


def early_flag(args):
    """True when a grep-family arg list carries an early-exit flag anywhere (GNU permutes). Returns (flag, position)."""
    i = 0; seen_operand = False
    while i < len(args):
        t = args[i]
        if t == '--': break
        if t.startswith('--'):
            name = t[2:].split('=')[0]
            if name and any(l.startswith(name) for l in LONG_EARLY): return (t, 'after-operand' if seen_operand else 'lead')
            if t.split('=')[0] in ARG_AFTER and '=' not in t: i += 1
        elif t.startswith('-') and len(t) > 1:
            cl = t[1:]
            for k, ch in enumerate(cl):
                if ch in 'qm': return (t, 'after-operand' if seen_operand else 'lead')
                if ch in 'efABCdD':
                    if k == len(cl) - 1: i += 1
                    break
        else:
            seen_operand = True
        i += 1
    return None


def classify(stage):
    """-> (category, detail) of one reader stage, or None."""
    tk = toks(stage.strip().lstrip('({ ').strip())
    i = 0; wrapped = []
    while i < len(tk):
        t = tk[i]
        if re.match(r'^[A-Za-z_][A-Za-z0-9_]*=', t): i += 1; continue
        base = t.lstrip('\\').rsplit('/', 1)[-1]
        if base in WRAP0:
            wrapped.append(base); i += 1
            while i < len(tk) and tk[i].startswith('-'):
                i += 1
                if base in ('timeout', 'nice', 'stdbuf', 'sudo', 'xargs', 'ionice', 'env') and i < len(tk) and not tk[i].startswith('-') and tk[i - 1] in ('-k', '-s', '-n', '-u', '-o', '-i', '-e', '-I', '-P', '-c'): i += 1
            if base == 'timeout' and i < len(tk) and re.match(r'^[0-9.]+[smhd]?$', tk[i]): i += 1
            continue
        break
    if i >= len(tk): return None
    b = tk[i]; base = b.lstrip('\\').rsplit('/', 1)[-1]; args = tk[i + 1:]
    if base in GREPS:
        ef = early_flag(args)
        if not ef: return None
        plain = base in ('grep', 'egrep', 'fgrep') and not wrapped and b == base and ef[1] == 'lead'
        # an operand that is a file means the stage does not read stdin: count the non-flag operands after the pattern
        return ('grep-early', 'plain' if plain else ('wrapped:' + '+'.join(wrapped) if wrapped else ('flag-after-operand' if ef[1] != 'lead' else 'spelling:' + b)))
    if base.startswith('$') or b.startswith('"$') or b.startswith('${'):
        return ('var-binary', 'early-flag' if early_flag(args) else 'no-early-flag')
    if base == 'head' and not wrapped:
        n = None
        for k, t in enumerate(args):
            m = re.match(r'^-n?([0-9]+)$', t)
            if m: n = int(m.group(1)); break
            if t == '-n' and k + 1 < len(args) and args[k + 1].isdigit(): n = int(args[k + 1]); break
            m = re.match(r'^-n([0-9]+)$', t)
            if m: n = int(m.group(1)); break
        if n is not None: return ('head-N', 'head-1' if n == 1 else 'head-N')
        return None
    if base in ('awk', 'gawk', 'mawk'):
        if re.search(r"(^|[^A-Za-z_0-9])exit([^A-Za-z_0-9]|$)", stage): return ('awk-exit', 'single-line')
        return None
    if base == 'sed':
        if re.search(r"""(^|[\s;{'"/0-9$])q([\s;'"}]|$)""", ' '.join(args)) and not re.search(r'\bs/', ' '.join(args)[:3]): return ('sed-q', '')
        return None
    if base == 'read' and not wrapped: return ('read', '')
    return ('func-candidate', base)


def ctx(line, bi):
    pre = line[:bi]
    post = line[bi:]
    if re.search(r'(^|\s)(if|elif|while|until)\s|(^|\s)!\s', pre) or '&&' in post or '||' in post: return 'cond'
    if '$(' in pre or '`' in pre: return 'capture'
    return 'bare'


# ---- pass 1: function definitions whose body reads stdin through an early-exit reader (a reader behind a function)
DEF = re.compile(r'^\s*(?:function\s+)?([A-Za-z_][A-Za-z0-9_.:-]*)\s*\(\)\s*\{?\s*(#.*)?$')
funcs = collections.defaultdict(set)   # name -> files
func_reader = {}                        # name -> (file,line,text)
# The flag run is matched as plain clusters (each starts at whitespace, so no two iterations can overlap: no backtracking blow-up) and the early-exit letter is
# tested on the captured run afterwards (every cluster must hold q or m, as before), instead of inside a repeated group whose clusters could split a q or m run more than one way.
GREPQ_STDIN_RUN = re.compile(r'(^|[;&|({]\s*|\s)(e?grep)((?:\s+-[A-Za-z0-9]+)+)(\s+("[^"]*"|\'[^\']*\'|[^\s<>|;&)]+))?\s*(\)|;|&&|\|\||$)')
class _GrepQ:
    def search(self, b):
        for m in GREPQ_STDIN_RUN.finditer(b):
            if all(re.fullmatch(r'-[A-Za-z]*[qm][A-Za-z0-9]*', c) for c in m.group(3).split()): return m
        return None
GREPQ_STDIN = _GrepQ()
for f in files:
    try: L = open(f, encoding='utf-8', errors='replace').read().split('\n')
    except OSError: continue
    n = len(L)
    for idx, ln in enumerate(L):
        m = DEF.match(ln)
        if not m or ln.lstrip().startswith('#'): continue
        name = m.group(1)
        funcs[name].add(f)
        indent = len(ln) - len(ln.lstrip())
        for j in range(idx + 1, min(n, idx + 60)):
            b = L[j]
            if b.strip() and (len(b) - len(b.lstrip())) <= indent and b.lstrip().startswith('}'): break
            if b.lstrip().startswith('#') or '<<<' in b or ' < ' in b: continue
            if GREPQ_STDIN.search(b):
                func_reader.setdefault(name, (f, j + 1, b.strip()[:120]))
                break

# ---- pass 2: classify every reader stage over logical lines
cat = collections.defaultdict(list)        # category -> [(ctx, file, line, text)]
split_pairs = []                           # trailing-bar joins


def logical(L):
    i = 0; n = len(L)
    while i < n:
        raw = L[i]
        if raw.lstrip().startswith('#') or MARK.search(raw): i += 1; continue
        cur = raw; start = i; joined = False
        while True:
            s = cur.rstrip()
            if s.endswith('\\') and i + 1 < n:
                cur = s[:-1] + ' ' + L[i + 1].strip(); i += 1; joined = True; continue
            if s.endswith('|') and not s.endswith('||') and not BLOCK.search(s) and i + 1 < n and not L[i + 1].lstrip().startswith('#'):
                last = bars(s)
                if last and last[-1] == len(s) - 1:
                    cur = s + ' ' + L[i + 1].strip(); i += 1; joined = 'pipe'; continue
            break
        yield start + 1, cur, joined, i
        i += 1


for f in files:
    try: L = open(f, encoding='utf-8', errors='replace').read().split('\n')
    except OSError: continue
    for ln, cur, joined, endi in logical(L):
        if 'sigpipe-demo' in cur and MARK.search(cur): continue
        for bi in bars(cur):
            se = stage_end(cur, bi + 1)
            st = cur[bi + 1:se]
            r = classify(st)
            if r is None:
                # multi-line awk: program quote opens and never closes on this logical line
                if re.match(r'\s*(awk|gawk)\b', st) and st.count("'") % 2 == 1:
                    prog = st[st.index("'") + 1:]
                    k = endi + 1; found = False
                    while k < len(L) and k < endi + 80:
                        prog += '\n' + L[k]
                        if "'" in L[k]: break
                        k += 1
                    if re.search(r"(^|[^A-Za-z_0-9])exit([^A-Za-z_0-9]|$)", prog): cat['awk-exit-multiline'].append((ctx(cur, bi), f, ln, cur.strip()[:140]))
                continue
            c, d = r
            if c == 'func-candidate':
                if d in func_reader: cat['func-reader'].append((ctx(cur, bi), f, ln, cur.strip()[:140] + '  <- ' + d))
                continue
            if c == 'grep-early' and d == 'plain': c = 'grep-early-plain(V2 sees)'
            cat[c + ('/' + d if c in ('grep-early', 'var-binary', 'head-N') else '')].append((ctx(cur, bi), f, ln, cur.strip()[:140]))
            if joined == 'pipe' and bi > 0 and c.startswith('grep-early') and cur.count('|') >= 1:
                pass
        if joined == 'pipe':
            # classify the stage that follows the joined trailing bar
            s = cur
            for bi in bars(s):
                pass
            split_pairs.append((f, ln, cur.strip()[:140]))

# trailing-bar joins whose NEXT stage is a reader (the split-line blind spot proper)
split_readers = [(f, ln, t) for (f, ln, t) in split_pairs if any(classify(t[b + 1:stage_end(t, b + 1)]) and classify(t[b + 1:stage_end(t, b + 1)])[0] not in ('func-candidate',) for b in bars(t))]

print('swept files:', len(files))
print('functions with a stdin early-exit grep body:', len(func_reader))
rows = sorted(cat.items(), key=lambda kv: kv[0])
for k, v in rows:
    if ONLY and ONLY not in k: continue
    byctx = collections.Counter(c for c, *_ in v)
    nf = len({x[1] for x in v})
    print(f'{k:42s} lines={len(v):5d} files={nf:4d} ctx={dict(byctx)}')
hn = [x for k, v in cat.items() if k.startswith('head-N') for x in v]
print(f'head-N total: lines={len(hn)} files(union)={len({x[1] for x in hn})}')
print(f'trailing-bar joined logical lines: {len(split_pairs)}; of those whose joined text holds a reader stage: {len(split_readers)}')
if SAMPLES:
    for k, v in rows:
        if ONLY and ONLY not in k: continue
        if k.startswith(('head-N', 'grep-early-plain')): continue
        print('##', k)
        for c, f, ln, t in v[:SAMPLES]: print(f'   [{c}] {f}:{ln}: {t}')
    print('## trailing-bar joins with reader')
    for f, ln, t in split_readers[:SAMPLES * 2]: print(f'   {f}:{ln}: {t}')
