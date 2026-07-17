#!/usr/bin/env bash
# shellcheck disable=SC2016  # single-quoted mutation bodies are literal shell text written into
# fixture copies by design ($HOME/$DEPLOY_DOCKER_CONFIG_DIR must NOT expand here — they are the
# source strings the guard scans). Mirrors scan-workflow-mutation.test.sh.
# Author-time guard: no credential-persist to a home dir under a ProtectHome=read-only unit (#6633).
#
# WHY THIS FILE EXISTS
# ====================
# A credential-persist-to-home failure class has recurred TWICE in production, both found only in
# the real service mount namespace (never by `terraform validate`, `cloud-init schema`, or the
# shell suites):
#   1. docker (#6565, repaired by merged PR #6623 / commit 6db2274f3): ci-deploy.sh under
#      webhook.service (ProtectHome=read-only) wrote `docker login` creds to
#      /home/deploy/.docker/config.json → EROFS (class=cred_store kw=errsaving,erofs). Repaired
#      by `export DOCKER_CONFIG=/mnt/data/deploy-docker` (an existing ReadWritePath).
#   2. doppler (2026-04-06 precedent): the Doppler CLI's os.Mkdir(~/.doppler) hit the same EROFS
#      under ProtectHome=read-only; resolved by relocating its config dir.
#
# The failure CLASS is "any tool that persists a credential to $HOME hits EROFS under a sandboxed
# unit" — it is NOT docker-specific (occurrence #2 was a different tool). So the guard scans a
# FAMILY TABLE (docker + OCI-registry logins, doppler, gh, aws) and fails the build if any systemd
# unit shipping ProtectHome=(read-only|yes) or ProtectSystem=strict runs an Exec* chain that
# persists a credential to a $HOME path without either (a) relocating that tool's config dir
# off $HOME onto a writable path within the unit's ReadWritePaths, or (b) listing the family's
# home config dir in ReadWritePaths. Boot-time root logins (cloud-init runcmd/bootcmd, fresh-boot
# bootstrap) are NOT flagged — they are un-sandboxed `[Service]`-less, so they never enter the
# sandboxed-unit set (that is exactly why `docker pull` kept working throughout #6565: the
# boot-baked auth was written un-sandboxed).
#
# DETECTION IS SHAPE-ROBUST BY DESIGN (review #6633: security-sentinel + test-design-reviewer). A
# credential login is detected however the real house style writes it — bare `docker login`,
# absolute path (`/usr/bin/docker login`), privilege wrappers (`sudo -u deploy`, `su … -c`,
# `runuser … --`, `env`, `nice`, `exec`), a shell `-c '…'` body, a global flag before the
# subcommand (`doppler --config-dir X login`), and in ANY Exec* directive (ExecStartPre/Post too),
# not just ExecStart=. A guard that recognizes only ONE syntactic form fails OPEN on the next
# refactor that writes the login differently — the exact #6565 recurrence vector.
#
# ANTI-VACUITY IS THE WHOLE POINT (learning 2026-07-17-buy-the-datum SE#3): the FIRST attempt at
# this guard shipped VACUOUS assertions (line-shape pins). So every invariant here is paired with a
# mutation that must independently drive RED — applied to a FRESH non-cumulative mktemp copy,
# asserted GREEN BEFORE mutation, gated on the mutation actually landing, AND finding-text
# attributed to the mutated unit/script AND its reason/target so a RED is caused by the mutation,
# not a pre-existing latent FAIL. Plus an in-guard non-empty-scan census (CRED_SITES_DETECTED>=1,
# webhook→ci-deploy.sh named) so a green run cannot mean "scanned nothing".
#
# Self-contained: pure bash + python3. No network, root, docker, terraform, or cloud-init needed.
# Override the scanned tree with CRED_GUARD_INFRA_ROOT (default = this script's dir).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REAL_ROOT="${CRED_GUARD_INFRA_ROOT:-$SCRIPT_DIR}"

PASS=0
FAIL=0
# fail() MUST return 0 so `set -e` does not abort the harness at the first failing assertion —
# otherwise the summary never prints and later assertions never run (code-quality review #6633).
# The sole exit chokepoint is the final `[[ "$FAIL" -eq 0 ]] || exit 1`.
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; [[ -n "${2:-}" ]] && echo "        $2"; return 0; }

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT INT TERM HUP

# --- the scanner (stages 1-3 + census), written once to a temp OUTSIDE any scanned tree ---------
SCANNER="$TMPROOT/scanner.py"
cat > "$SCANNER" <<'PYEOF'
#!/usr/bin/env python3
# Stages: (1) enumerate sandboxed units [3 shapes: .service / .sh|.tf heredoc / cloud-init
# content:|], (2) map unit -> {scripts|NONE} (fail-closed), (3) cred-persist scan (family table,
# shape-robust) + relocation check + census.
# Prints `min=<N>` on the census line so the harness single-sources the non-vacuity floor.
# Exit: 0 GREEN | 2 violations | 3 census-fail | 4 enumeration-non-vacuity-fail.
import os, re, sys

ROOT = os.path.abspath(sys.argv[1])
MIN_SANDBOXED_UNITS = 5

def _clean(p):
    return p.strip().strip('"').strip("'")

def is_home(p):
    p = _clean(p)
    if '$HOME' in p or '${HOME}' in p:
        return True
    if p.startswith('~'):
        return True
    if p == '/home' or p.startswith('/home/'):
        return True
    if p == '/root' or p.startswith('/root/'):
        return True
    return False

def is_abs_offhome(p):
    p = _clean(p)
    return p.startswith('/') and not is_home(p)

def in_rwp(target, rwp_tokens):
    t = _clean(target).rstrip('/')
    for tok in rwp_tokens:
        tok = tok.rstrip('/')
        if not tok:
            continue
        if t == tok or t.startswith(tok + '/'):
            return True
    return False

def resolve_value(val, assignments, _depth=0):
    """One level of ${VAR:-default}/$VAR indirection. Return (resolved, ok); ok=False=>fail-closed."""
    v = _clean(val)
    if _depth > 3:
        return v, False
    m = re.fullmatch(r'\$\{(\w+):-(.*)\}', v)
    if m:
        return _clean(m.group(2)), True
    m = re.fullmatch(r'\$\{?(\w+)\}?(/.*)?', v)
    if m and v.startswith('$'):
        var, suffix = m.group(1), (m.group(2) or '')
        if var == 'HOME':
            return '$HOME' + suffix, True
        if var in assignments:
            inner, ok = resolve_value(assignments[var], assignments, _depth + 1)
            if not ok:
                return v, False
            return inner + suffix, True
        return v, False  # unresolvable var -> fail-closed
    return v, True

def strip_comments(text):
    return '\n'.join(l for l in text.split('\n') if not re.match(r'^\s*#', l))

ASSIGN_RE = re.compile(
    r'^\s*(?:readonly\s+|export\s+|declare\s+\S+\s+|local\s+)?'
    r'(\w+)=("[^"]*"|\'[^\']*\'|\S+)')

def gather_assignments(texts):
    a = {}
    for t in texts:
        for line in t.split('\n'):
            m = ASSIGN_RE.match(line)
            if m:
                a[m.group(1)] = m.group(2)  # last-wins
    return a

# --- shape-robust command extraction -----------------------------------------------------------
def _segments(line):
    # Naive split on top-level command separators. Over-splitting is harmless for DETECTION:
    # a real `... | docker login ...` still lands `docker login` at a segment start, and a
    # `logger -t "$T" "...docker login..."` string keeps `docker login` mid-segment (not a start).
    return re.split(r'(?:\|\||&&|[|;&])', line)

def _expand(text):
    """Yield command segments across lines AND one level of shell `-c '...'`/`-c "..."` bodies,
    so `sh -c 'docker login'` / `su deploy -c 'docker login'` are scanned as real commands."""
    for line in text.split('\n'):
        for seg in _segments(line):
            yield seg
            for m in re.finditer(r'-c\s+(\'[^\']*\'|"[^"]*")', seg):
                for inner in _segments(m.group(1)[1:-1]):
                    yield inner

# Leading wrappers that run the following command unchanged (so a login behind them still persists
# creds the same way). `env`/bare VAR= assignments are captured separately (they can relocate).
WRAPPER_RE = re.compile(
    r'^(?:'
    r'sudo(?:\s+-\S+|\s+\w+=(?:"[^"]*"|\'[^\']*\'|\S+))*|'
    r'doas(?:\s+-\S+)*|'
    r'su\s+\S+|'
    r'runuser(?:\s+\S+)*?\s+--|'
    r'nice(?:\s+-\S+|\s+\d+)*|'
    r'ionice(?:\s+-\S+|\s+\d+)*|'
    r'stdbuf(?:\s+-\S+)*|'
    r'nohup|setsid|command|exec|env|'
    r'timeout(?:\s+-\S+)*\s+\S+'
    r')\s+')

def _strip_head(s):
    """Strip leading privilege/exec wrappers and capture inline `VAR=val`/`env VAR=val` into env."""
    env = {}
    while True:
        m = re.match(r'^(?:env\s+)?((?:\w+=(?:"[^"]*"|\'[^\']*\'|\S+)\s+)+)', s)
        if m and m.group(1):
            for em in re.finditer(r'(\w+)=("[^"]*"|\'[^\']*\'|\S+)', m.group(1)):
                env[em.group(1)] = em.group(2)
            s = s[m.end():]
            continue
        m = WRAPPER_RE.match(s)
        if m:
            s = s[m.end():]
            continue
        break
    return s, env

# Family table. Each login site persists a credential to `default_home` unless relocated off-home
# (via cfgflag on the command, an env_relocate var inline or as a global assignment) into an RWP
# entry. gh/aws/OCI-registry tools were added at review time (#6633) — the class is tool-agnostic.
FAMILIES = [
    {  # docker + OCI-registry logins: all persist to $DOCKER_CONFIG / ~/.docker (or ~/.config/containers)
        'name': 'docker',
        'tools': r'docker|podman|nerdctl|cosign|skopeo|crane|helm',
        'verb': r'\blogin\b',
        'cfgflag': r'--config',
        'env_relocate': ['DOCKER_CONFIG', 'REGISTRY_AUTH_FILE'],
        'default_home': '~/.docker',
    },
    {  # doppler WRITE subcommands only (bare `doppler run` / `secrets get` / `configure get` are reads)
        'name': 'doppler',
        'tools': r'doppler',
        'verb': r'\b(?:login|setup|configure\s+set|configure\s+token)\b',
        'verb_exclude': r'\b(?:run|configure\s+(?:get|debug))\b',
        'cfgflag': r'--config-dir',
        'env_relocate': ['DOPPLER_CONFIG_DIR'],
        'default_home': '~/.doppler',
    },
    {
        'name': 'gh',
        'tools': r'gh',
        'verb': r'\bauth\s+login\b',
        'cfgflag': None,
        'env_relocate': ['GH_CONFIG_DIR'],
        'default_home': '~/.config/gh',
    },
    {
        'name': 'aws',
        'tools': r'aws',
        'verb': r'\b(?:configure(?:\s+set)?|sso\s+login)\b',
        'cfgflag': None,
        'env_relocate': ['AWS_CONFIG_FILE', 'AWS_SHARED_CREDENTIALS_FILE'],
        'default_home': '~/.aws',
    },
]

def find_sites(text, fam):
    """Yield ('explicit'|'inline'|'global', path|None) per credential-login command of `fam`."""
    head_re = re.compile(r'^(?:\S*/)?(?:' + fam['tools'] + r')\b(.*)$')
    excl = re.compile(fam['verb_exclude']) if fam.get('verb_exclude') else None
    verb = re.compile(fam['verb'])
    cfg_re = re.compile(fam['cfgflag'] + r'[= ]("[^"]*"|\'[^\']*\'|\S+)') if fam.get('cfgflag') else None
    sites = []
    for seg in _expand(text):
        s, env = _strip_head(seg.strip())
        m = head_re.match(s)
        if not m:
            continue
        rest = m.group(1)
        if not verb.search(rest):
            continue
        if excl and excl.search(rest):
            continue
        cfg = None
        if cfg_re:
            cm = cfg_re.search(rest)
            if cm:
                cfg = ('explicit', cm.group(1))
        if cfg is None:
            for ev in fam['env_relocate']:
                if ev in env:
                    cfg = ('inline', env[ev])
                    break
        if cfg is None:
            cfg = ('global', None)
        sites.append(cfg)
    return sites

def eval_target(kind, raw, assignments, rwp, fam):
    if kind == 'global':
        raw = None
        for gv in fam['env_relocate']:
            if gv in assignments:
                raw = assignments[gv]  # any relocate var set -> use it
        if raw is None:
            return fam['default_home'], False, 'no relocation; default %s' % fam['default_home']
    resolved, ok = resolve_value(raw, assignments)
    if not ok:
        return resolved, False, 'unresolvable relocation target (fail-closed)'
    if is_home(resolved):
        return resolved, False, 'config dir resolves under home'
    if not is_abs_offhome(resolved):
        return resolved, False, 'not an absolute off-home path'
    if not in_rwp(resolved, rwp):
        return resolved, False, 'off-home but not within any ReadWritePaths entry'
    return resolved, True, 'relocated off-home into RWP'

# --- unit enumeration (3 shapes) ---------------------------------------------------------------
def is_sandboxed(body):
    if '[Service]' not in body:
        return False
    return bool(re.search(
        r'^\s*(?:ProtectHome=(?:read-only|yes)|ProtectSystem=strict)\s*$', body, re.M))

EXEC_RE = re.compile(r'^\s*Exec(?:Start|StartPre|StartPost|Stop|StopPost|Reload|Condition)=(.*)$', re.M)

def mk_unit(name, source, body):
    execs = [m.group(1).strip() for m in EXEC_RE.finditer(body)]
    sm = re.search(r'^\s*ExecStart=(.*)$', body, re.M)
    execstart = sm.group(1).strip() if sm else (execs[0] if execs else '')
    rwp = []
    for rm in re.finditer(r'^\s*ReadWritePaths=(.*)$', body, re.M):
        for tok in rm.group(1).split():
            rwp.append(tok[1:] if tok.startswith('-') else tok)  # strip one leading '-'
    return {'name': name, 'source': source, 'execstart': execstart, 'execs': execs, 'rwp': rwp}

# Heredoc-defined units: `cat > <target> <<'MARKER' ... MARKER`. Target may be a $VAR OR a LITERAL
# path (`cat > /etc/systemd/system/x.service <<...`); marker may be single/double-quoted or bare;
# backreference \2 pins the closing marker so adjacent heredocs do not bleed. inngest.test.sh:176.
HEREDOC_RE = re.compile(
    r'cat\s*>\s*("[^"]*"|\'[^\']*\'|\S+)\s*<<-?\s*["\']?(\w+)["\']?\n(.*?)\n[ \t]*\2', re.S)

def _heredoc_name(target):
    t = _clean(target)
    return os.path.basename(t) if ('/' in t and not t.startswith('$')) else t

def heredoc_units(src):
    for m in HEREDOC_RE.finditer(src):
        yield _heredoc_name(m.group(1)), m.group(3)

def cloudinit_blocks(src):
    # cloud-init write_files units are INDENTED YAML block-scalars (content: |), NOT heredocs.
    # A `cat >` regex finds ZERO here -> the non-vacuous-zero false-green the count-assert guards.
    blocks = []
    lines = src.split('\n')
    i = 0
    while i < len(lines):
        m = re.match(r'^(\s*)content:\s*\|', lines[i])
        if m:
            indent = len(m.group(1))
            j = i + 1
            body = []
            while j < len(lines):
                if lines[j].strip() == '':
                    body.append('')
                    j += 1
                    continue
                li = len(lines[j]) - len(lines[j].lstrip())
                if li <= indent:
                    break
                body.append(lines[j])
                j += 1
            blocks.append('\n'.join(body))
            i = j
        else:
            i += 1
    return blocks

def read(path):
    try:
        with open(path, encoding='utf-8', errors='replace') as f:
            return f.read()
    except OSError:
        return ''

def enumerate_units(root):
    units = []
    for dp, _dirs, files in os.walk(root):
        for fn in sorted(files):
            path = os.path.join(dp, fn)
            if fn.endswith('.test.sh'):  # test fixtures build unit strings; never real defs
                continue
            if fn.endswith('.service'):
                body = read(path)
                if is_sandboxed(body):
                    units.append(mk_unit(fn, os.path.relpath(path, root) + ':service', body))
            elif fn.endswith(('.sh', '.tf')):
                # .tf remote-exec provisioners embed unit heredocs with LITERAL \n escapes; unescape
                # so a sandboxed unit defined inline in terraform is enumerated (fail-closed).
                src = read(path)
                if fn.endswith('.tf'):
                    src = src.replace('\\n', '\n')
                for name, body in heredoc_units(src):
                    if is_sandboxed(body):
                        units.append(mk_unit(name, os.path.relpath(path, root) + ':heredoc', body))
            elif fn.endswith(('.yml', '.yaml')):
                for idx, body in enumerate(cloudinit_blocks(read(path))):
                    if is_sandboxed(body):
                        dm = re.search(r'^\s*Description=(.*)$', body, re.M)
                        nm = (dm.group(1).strip()[:40] if dm else 'unit%d' % idx)
                        units.append(mk_unit('%s[%s]' % (fn, nm),
                                             os.path.relpath(path, root) + ':cloud-init', body))
    return units

def classify(u):
    e = u['execstart']
    if '/usr/local/bin/webhook' in e:  # ExecStart is the webhook BINARY; cred logic is via
        return 'webhook'                # hooks.json -> ci-deploy-wrapper.sh -> ci-deploy.sh
    if 'doppler' in e and re.search(r'\brun\b', e) and not re.search(
            r'\bdoppler\s+(?:login|setup|configure\s+set|configure\s+token)\b', e):
        return 'doppler-run'            # token read (redis/inngest/vector); no home-cred write
    return 'unknown'                    # fail-closed: new unit must be classified

def map_scripts(u, root):
    if classify(u) == 'webhook':
        return [os.path.join(root, 'ci-deploy.sh'), os.path.join(root, 'ci-deploy-wrapper.sh')]
    return []

def main():
    units = enumerate_units(ROOT)
    print('CENSUS: sandboxed_units=%d min=%d' % (len(units), MIN_SANDBOXED_UNITS))
    for u in units:
        print('  UNIT: %-45s kind=%-11s src=%s' % (u['name'], classify(u), u['source']))
    if len(units) < MIN_SANDBOXED_UNITS:
        print('ENUM_FAIL: sandboxed_units=%d (<%d) — a broken extractor that matches nothing '
              'reports zero violators and passes forever' % (len(units), MIN_SANDBOXED_UNITS))
        return 4

    violations = []
    cred_sites = 0
    webhook_docker = 'NONE'

    for u in units:
        kind = classify(u)
        # Scan every Exec* directive (ExecStartPre/Post too, not just ExecStart) + mapped scripts.
        texts = [('inline:' + u['name'], e) for e in u['execs']] or [('inline:' + u['name'], u['execstart'])]
        for sp in map_scripts(u, ROOT):
            if not os.path.isfile(sp):
                violations.append('MISSING_SCRIPT: unit=%s script=%s (mapped script absent — '
                                  'fail-closed)' % (u['name'], os.path.relpath(sp, ROOT)))
                continue
            texts.append((os.path.relpath(sp, ROOT), strip_comments(read(sp))))
        assignments = gather_assignments([t for _, t in texts])

        unit_has_cred = False
        for site_name, text in texts:
            for fam in FAMILIES:
                for cfg in find_sites(text, fam):
                    unit_has_cred = True
                    cred_sites += 1
                    resolved, ok, reason = eval_target(cfg[0], cfg[1], assignments, u['rwp'], fam)
                    if fam['name'] == 'docker' and kind == 'webhook' and ok:
                        webhook_docker = 'relocated'
                    if not ok:
                        violations.append(
                            'FINDING: unit=%s site=%s family=%s target=%s reason=%s'
                            % (u['name'], site_name, fam['name'], resolved, reason))

        if not unit_has_cred and kind == 'unknown':
            violations.append('UNCLASSIFIED: unit=%s execstart=%s (sandboxed unit not recognized '
                              'as webhook or bare `doppler run`, and no known cred action — add it '
                              'to the association map)' % (u['name'], u['execstart'][:80]))

    print('CENSUS: cred_sites=%d webhook_docker=%s' % (cred_sites, webhook_docker))
    for v in violations:
        print(v)

    if violations:
        return 2
    if cred_sites < 1:
        print('CENSUS_FAIL: cred_sites=0 — over-strip / anchor-drift / empty resolution '
              '(a GREEN that scanned nothing is a vacuous pass)')
        return 3
    if webhook_docker != 'relocated':
        print('CENSUS_FAIL: webhook.service->ci-deploy.sh docker site not detected+relocated '
              '(got webhook_docker=%s)' % webhook_docker)
        return 3
    return 0

if __name__ == '__main__':
    sys.exit(main())
PYEOF

echo "=== credential-persist-home-guard tests (#6633) ==="
echo ""

# ---------------------------------------------------------------------------------------------
# AC2 + AC8 — real tree GREEN + non-empty-scan census (the anti-vacuity positive control)
# ---------------------------------------------------------------------------------------------
echo "--- AC2/AC8: real infra tree GREEN + census ---"
REAL_OUT="$(python3 "$SCANNER" "$REAL_ROOT" 2>&1)" && REAL_RC=0 || REAL_RC=$?
if [[ "$REAL_RC" -eq 0 ]]; then
  pass "guard is GREEN on the real infra tree (relocated docker write + token doppler-run units)"
else
  fail "guard is NOT green on the real tree (exit $REAL_RC)" "$(printf '%s\n' "$REAL_OUT" | grep -E 'FINDING|UNCLASSIFIED|FAIL' | head -5)"
fi
# Non-vacuity floor single-sourced from the scanner's own `min=` (no re-encoded numeral / 99-ceiling).
SB_N="$(grep -oE 'sandboxed_units=[0-9]+' <<<"$REAL_OUT" | head -1 | grep -oE '[0-9]+' || true)"
SB_MIN="$(grep -oE 'min=[0-9]+' <<<"$REAL_OUT" | head -1 | grep -oE '[0-9]+' || true)"
if [[ -n "$SB_N" && -n "$SB_MIN" && "$SB_N" -ge "$SB_MIN" ]]; then
  pass "enumeration is non-vacuous ($SB_N sandboxed units >= floor $SB_MIN)"
else
  fail "enumeration below the non-vacuity floor" "sandboxed_units=$SB_N min=$SB_MIN"
fi
if grep -qE 'CENSUS: cred_sites=[1-9]' <<<"$REAL_OUT"; then
  pass "AC8 census: cred_sites>=1 (over-strip/anchor-drift/empty-resolution would be RED)"
else
  fail "AC8 census: cred_sites=0 — vacuous GREEN would slip through" "$(grep 'cred_sites' <<<"$REAL_OUT")"
fi
if grep -qF 'webhook_docker=relocated' <<<"$REAL_OUT"; then
  pass "AC8 census: webhook.service -> ci-deploy.sh docker site detected + relocated"
else
  fail "AC8 census: webhook docker site not detected+relocated" "$(grep 'webhook_docker' <<<"$REAL_OUT")"
fi

# ---------------------------------------------------------------------------------------------
# AC3 — mutation battery (RED). Each mutation: FRESH non-cumulative copy, GREEN-before-mutation,
# assert-mutated, RED-after, finding-text attribution to the mutated unit/script + reason/target.
# ---------------------------------------------------------------------------------------------
echo ""
echo "--- AC3: mutation battery (each must independently drive RED, attributed) ---"

expect_red() {
  # expect_red <label> <attribution-substring> <mutate-fn>
  local label="$1" attrib="$2" mutate_fn="$3"
  local sbx; sbx="$(mktemp -d "$TMPROOT/mut.XXXXXX")"
  cp -r "$REAL_ROOT"/. "$sbx"/
  if ! python3 "$SCANNER" "$sbx" >/dev/null 2>&1; then
    fail "$label: fresh copy not GREEN before mutation (latent FAIL — attribution unsafe)"; return 0
  fi
  "$mutate_fn" "$sbx"
  if diff -rq "$REAL_ROOT" "$sbx" >/dev/null 2>&1; then
    fail "$label: mutation did not change the tree (assert_mutated failed)"; return 0
  fi
  local out rc
  out="$(python3 "$SCANNER" "$sbx" 2>&1)" && rc=0 || rc=$?
  if [[ "$rc" -eq 0 ]]; then
    fail "$label: guard stayed GREEN on the mutated tree (VACUOUS — pins nothing)"; return 0
  fi
  if grep -qF "$attrib" <<<"$out"; then
    pass "$label (RED, attributed to '$attrib')"
  else
    fail "$label: RED not attributed to '$attrib' (could be a pre-existing latent FAIL)" \
      "$(printf '%s\n' "$out" | grep -E 'FINDING|UNCLASSIFIED|FAIL' | head -3)"
  fi
}

CIDEPLOY="ci-deploy.sh"

# M1 — relocation points BACK to home (the sneaky dual-false-PASS case; last-assignment-wins).
m1() { printf '\nexport DOCKER_CONFIG="$HOME/.docker"\n' >> "$1/$CIDEPLOY"; }
expect_red "M1 export DOCKER_CONFIG=\$HOME/.docker (last-wins home)" "reason=config dir resolves under home" m1

# M2 — docker login with the DOCKER_CONFIG export removed (bare default ~/.docker).
m2() { sed -i 's|^export DOCKER_CONFIG="\$DEPLOY_DOCKER_CONFIG_DIR"|# removed by M2|' "$1/$CIDEPLOY"; }
expect_red "M2 no DOCKER_CONFIG export (bare ~/.docker default)" "reason=no relocation; default ~/.docker" m2

# M3 / M3b / M3c — detect-form parity: --config space / --config= / inline-env, all home-pointed.
m3()  { printf '\ndocker --config "$HOME/.docker" login ghcr.io -u x --password-stdin\n' >> "$1/$CIDEPLOY"; }
m3b() { printf '\ndocker --config=$HOME/.docker login ghcr.io\n' >> "$1/$CIDEPLOY"; }
m3c() { printf '\nDOCKER_CONFIG="$HOME/.docker" docker login ghcr.io\n' >> "$1/$CIDEPLOY"; }
expect_red "M3 docker --config <home> login (space form)"  "reason=config dir resolves under home" m3
expect_red "M3b docker --config=<home> login (equals form)" "reason=config dir resolves under home" m3b
expect_red "M3c DOCKER_CONFIG=<home> docker login (inline-env, no export)" "reason=config dir resolves under home" m3c

# M4 — a NEW sandboxed unit running a doppler WRITE subcommand with no relocation (class-wide).
m4() {
  cat > "$1/m4-doppler.service" <<'UNITEOF'
[Unit]
Description=M4 doppler cred unit
[Service]
Type=simple
ExecStart=/usr/bin/doppler login --scope /
ProtectSystem=strict
ProtectHome=read-only
PrivateTmp=true
[Install]
WantedBy=multi-user.target
UNITEOF
}
expect_red "M4 new sandboxed unit runs 'doppler login' (no relocation)" "unit=m4-doppler.service" m4

# M5 / M5b — off-home path NOT in RWP / relocation covered only by the dropped /mnt/data blanket.
m5()  { sed -i 's|/mnt/data/deploy-docker|/opt/creds|' "$1/$CIDEPLOY"; }
m5b() { sed -i 's|ReadWritePaths=/mnt/data |ReadWritePaths=|' "$1/webhook.service"; }
expect_red "M5 relocation to /opt/creds (off-home, not in RWP)" "reason=off-home but not within any ReadWritePaths entry" m5
expect_red "M5b /mnt/data dropped from RWP (no blanket /mnt/data allow)" "unit=webhook.service" m5b

# M6 — delete ci-deploy.sh's real DOCKER_CONFIG export + indirection (exact #6565 shape).
m6() { sed -i '/DEPLOY_DOCKER_CONFIG_DIR:-\/mnt\/data\/deploy-docker/d; /^export DOCKER_CONFIG="\$DEPLOY_DOCKER_CONFIG_DIR"/d' "$1/$CIDEPLOY"; }
expect_red "M6 delete relocation (re-introduce #6565 shape)" "reason=no relocation; default ~/.docker" m6

# M7 / M7b — flip the ${VAR:-default} default to home / unresolvable var (fail-closed).
m7()  { sed -i 's|:-/mnt/data/deploy-docker|:-$HOME/.docker|' "$1/$CIDEPLOY"; }
m7b() { sed -i 's|^export DOCKER_CONFIG="\$DEPLOY_DOCKER_CONFIG_DIR"|export DOCKER_CONFIG="$SOME_UNSET_VAR"|' "$1/$CIDEPLOY"; }
expect_red "M7 flip \${VAR:-default} default to \$HOME (indirection resolved)" "reason=config dir resolves under home" m7
expect_red "M7b export unresolvable \$SOME_UNSET_VAR (fail-closed)" "reason=unresolvable relocation target (fail-closed)" m7b

# M8 — heredoc-defined sandboxed unit with an inline `docker login` in ExecStart, no separate
# script (now detected positively via sh -c unwrap, not only the fail-closed UNCLASSIFIED path).
m8() {
  cat > "$1/m8-inline.sh" <<'OUTEREOF'
#!/usr/bin/env bash
cat > "$M8_INLINE_DOCKER_UNIT" <<'M8EOF'
[Unit]
Description=M8 inline docker login unit
[Service]
Type=simple
ExecStart=/bin/sh -c 'docker login ghcr.io -u u --password-stdin'
ProtectSystem=strict
ProtectHome=read-only
PrivateTmp=true
[Install]
WantedBy=multi-user.target
M8EOF
OUTEREOF
}
expect_red "M8 heredoc unit with inline 'docker login' in ExecStart" "M8_INLINE_DOCKER_UNIT" m8

# --- review #6633 additions: shape-robustness fail-open closers ---
# M9 — absolute-path docker + explicit HOME --config appended ALONGSIDE the relocated site
# (the census additive-bypass shape security-sentinel proved GREEN under the old ^docker anchor).
m9() { printf '\n/usr/bin/docker --config "$HOME/.docker" login ghcr.io -u x --password-stdin\n' >> "$1/$CIDEPLOY"; }
expect_red "M9 /usr/bin/docker --config <home> login (abs-path, additive)" "reason=config dir resolves under home" m9

# M10 — a home docker login inside ExecStartPre (a non-ExecStart directive) of the webhook unit,
# wrapped in sudo -u + sh -c (privilege wrapper + shell -c unwrap + non-ExecStart scanning).
m10() { sed -i 's|^ExecStart=/usr/local/bin/webhook|ExecStartPre=/usr/bin/sudo -u deploy /bin/sh -c '"'"'docker --config /root/.docker login ghcr.io'"'"'\n&|' "$1/webhook.service"; }
expect_red "M10 ExecStartPre sudo -u + sh -c docker --config /root login" "reason=config dir resolves under home" m10

# M11 — a LITERAL-PATH heredoc sandboxed unit (cat > /etc/systemd/system/x.service <<) with an
# inline home docker login (P1-A: the $VAR-only heredoc regex used to never enumerate this).
m11() {
  cat > "$1/m11-literal-heredoc.sh" <<'OUTEREOF'
#!/usr/bin/env bash
cat > /etc/systemd/system/m11-evil.service <<'M11EOF'
[Unit]
Description=M11 literal-path heredoc unit
[Service]
Type=simple
ExecStart=/bin/sh -c 'docker login ghcr.io -u u --password-stdin'
ProtectSystem=strict
ProtectHome=read-only
PrivateTmp=true
[Install]
WantedBy=multi-user.target
M11EOF
OUTEREOF
}
expect_red "M11 literal-path heredoc unit with inline docker login" "unit=m11-evil.service" m11

# M12 — family extensibility: a NEW sandboxed unit running `gh auth login` unrelocated (a tool
# outside docker/doppler — the class recurred via a different tool, so the vocabulary must cover it).
m12() {
  cat > "$1/m12-gh.service" <<'UNITEOF'
[Unit]
Description=M12 gh auth login unit
[Service]
Type=simple
ExecStart=/usr/bin/gh auth login --with-token
ProtectSystem=strict
ProtectHome=read-only
PrivateTmp=true
[Install]
WantedBy=multi-user.target
UNITEOF
}
expect_red "M12 new unit runs 'gh auth login' (family extensibility)" "family=gh" m12

# M13 — relocation to an absolute /home/... path that IS added to ReadWritePaths (escape-hatch (b)):
# still RED because a home write-hole is the anti-pattern the precedent argues AGAINST. Pins the
# is_home absolute /home clause (test-design P2-A: deleting that clause was otherwise silent-green).
m13() {
  sed -i 's|:-/mnt/data/deploy-docker|:-/home/deploy/.docker|' "$1/$CIDEPLOY"
  sed -i 's|ReadWritePaths=/mnt/data |ReadWritePaths=/mnt/data /home/deploy/.docker |' "$1/webhook.service"
}
expect_red "M13 relocate to /home/deploy/.docker even with RWP hole (is_home abs clause)" "reason=config dir resolves under home" m13

# M14 — doppler global flag BEFORE the subcommand (doppler --config-dir <home> login) in a new unit
# (test-design P2-B: the subcommand-immediately-after-doppler anchor used to miss this).
m14() {
  cat > "$1/m14-doppler-flagfirst.service" <<'UNITEOF'
[Unit]
Description=M14 doppler flag-first login
[Service]
Type=simple
ExecStart=/usr/bin/doppler --config-dir "$HOME/.doppler" login --scope /
ProtectSystem=strict
ProtectHome=read-only
PrivateTmp=true
[Install]
WantedBy=multi-user.target
UNITEOF
}
expect_red "M14 doppler --config-dir <home> login (flag before subcommand)" "family=doppler" m14

# M15 — pins the census fail-branch itself: strip ci-deploy.sh's login verb so the scan finds ZERO
# cred sites (over-strip / anchor-drift class) -> CENSUS_FAIL, not a vacuous GREEN.
m15() { sed -i 's/docker login/docker version/g' "$1/$CIDEPLOY"; }
expect_red "M15 login verb stripped -> cred_sites=0 (census self-fail pinned)" "CENSUS_FAIL" m15

# AC5 — a NEW sandboxed unit absent from the association map, no cred action (fail-closed).
ac5() {
  cat > "$1/ac5-novel.service" <<'UNITEOF'
[Unit]
Description=AC5 novel unmapped daemon
[Service]
Type=simple
ExecStart=/usr/local/bin/novel-daemon --serve
ProtectSystem=strict
ProtectHome=read-only
PrivateTmp=true
[Install]
WantedBy=multi-user.target
UNITEOF
}
expect_red "AC5 novel sandboxed unit not in the map (fail-closed enumeration)" "unit=ac5-novel.service" ac5

# ---------------------------------------------------------------------------------------------
# AC4 + GREEN pins — boot-immune sites and legitimate relocations must NOT be flagged.
# ---------------------------------------------------------------------------------------------
echo ""
echo "--- AC4 + GREEN pins (no false positives) ---"

expect_green() {
  # expect_green <label> <mutate-fn>
  local label="$1" mutate_fn="$2"
  local sbx; sbx="$(mktemp -d "$TMPROOT/grn.XXXXXX")"
  cp -r "$REAL_ROOT"/. "$sbx"/
  "$mutate_fn" "$sbx"
  local out rc
  out="$(python3 "$SCANNER" "$sbx" 2>&1)" && rc=0 || rc=$?
  if [[ "$rc" -eq 0 ]]; then
    pass "$label (stayed GREEN)"
  else
    fail "$label: guard went RED (false positive, exit $rc)" \
      "$(printf '%s\n' "$out" | grep -E 'FINDING|UNCLASSIFIED|FAIL' | head -3)"
  fi
}

# AC4 boot false-positive probe: an un-relocated `docker login` in a runcmd block stays GREEN
# (it is not a [Service] ExecStart, so it never enters the sandboxed-unit set).
gboot() {
  python3 - "$1/cloud-init.yml" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
s = s.replace('runcmd:', 'runcmd:\n  - docker login ghcr.io -u boot --password-stdin', 1)
open(p, 'w').write(s)
PY
}
expect_green "AC4 boot: un-relocated 'docker login' in runcmd (un-sandboxed, immune)" gboot

# The existing boot sites (cloud-init.yml runcmd logins, cloud-init-inngest.yml, fresh-boot
# bootstrap logins) are already GREEN on the real tree — AC2 above proves it with them present.

# Bare `doppler run` under ProtectHome stays GREEN (named regression pin: guards the current-tree
# redis/inngest/vector token-read false-positive that flagging `doppler run` would introduce).
gdoppler() {
  cat > "$1/green-doppler-run.service" <<'UNITEOF'
[Unit]
Description=Green bare doppler run token read
[Service]
Type=simple
ExecStart=/usr/bin/doppler run --project soleur --config prd -- /usr/local/bin/thing
ProtectSystem=strict
ProtectHome=read-only
PrivateTmp=true
[Install]
WantedBy=multi-user.target
UNITEOF
}
expect_green "bare 'doppler run' token-read under ProtectHome (redis/inngest/vector FP pin)" gdoppler

# Valid relocation into a '-'-prefixed RW entry stays GREEN (proves the '-' ignore-if-absent
# prefix is stripped before RWP membership; without stripping this would false-RED).
greloc() { sed -i 's|/mnt/data/deploy-docker|/var/lib/inngest/deploy-docker|' "$1/$CIDEPLOY"; }
expect_green "relocation into a '-'-prefixed RW entry (/var/lib/inngest, '-'-strip)" greloc

# A relocated docker login written in a shape-robust form (abs-path + sh -c) stays GREEN when the
# global DOCKER_CONFIG relocation applies — proves the broadened detector does not false-positive
# on a legitimately-relocated login just because it is wrapped.
gwrapped() { printf '\n/bin/sh -c '"'"'/usr/bin/docker login ghcr.io -u x --password-stdin'"'"'\n' >> "$1/$CIDEPLOY"; }
expect_green "abs-path + sh -c docker login under a relocated DOCKER_CONFIG (no false positive)" gwrapped

# ---------------------------------------------------------------------------------------------
echo ""
echo "=== credential-persist-home-guard: PASS=$PASS FAIL=$FAIL ==="
[[ "$FAIL" -eq 0 ]] || exit 1
