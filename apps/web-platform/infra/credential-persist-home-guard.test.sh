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
#      /home/deploy/.docker/config.json -> EROFS (class=cred_store kw=errsaving,erofs). Repaired
#      by `export DOCKER_CONFIG=/mnt/data/deploy-docker` (an existing ReadWritePath).
#   2. doppler (2026-04-06 precedent): the Doppler CLI's os.Mkdir(~/.doppler) hit the same EROFS
#      under ProtectHome=read-only; resolved by relocating its config dir.
#
# This guard fails the build if any systemd unit shipping ProtectHome=(read-only|yes) or
# ProtectSystem=strict runs an ExecStart chain that persists a credential to a $HOME path without
# either (a) relocating that tool's config dir off $HOME onto a writable path within the unit's
# ReadWritePaths, or (b) listing the family's home config dir in ReadWritePaths. Boot-time root
# logins (cloud-init runcmd/bootcmd, fresh-boot bootstrap) are NOT flagged — they are un-sandboxed
# `[Service]`-less, so they never enter the sandboxed-unit set (that is exactly why `docker pull`
# kept working throughout #6565: the boot-baked auth was written un-sandboxed).
#
# ANTI-VACUITY IS THE WHOLE POINT (learning 2026-07-17-buy-the-datum… Session Error #3): the FIRST
# attempt at this exact guard shipped TWO vacuous assertions (line-shape pins) that produced a
# dual-false-PASS on three realistic mutations. So every invariant here is paired with a mutation
# that must independently drive RED — applied to a FRESH non-cumulative mktemp copy, asserted GREEN
# BEFORE mutation, gated on the mutation actually landing, AND finding-text-attributed to the
# mutated unit/script so a RED is caused by the mutation, not a pre-existing latent FAIL. Plus an
# in-guard non-empty-scan census (CRED_SITES_DETECTED>=1, webhook->ci-deploy.sh named) so a green
# run cannot mean "scanned nothing".
#
# Self-contained: pure bash + python3. No network, root, docker, terraform, or cloud-init needed.
# Override the scanned tree with CRED_GUARD_INFRA_ROOT (default = this script's dir).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REAL_ROOT="${CRED_GUARD_INFRA_ROOT:-$SCRIPT_DIR}"

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; [[ -n "${2:-}" ]] && echo "        $2"; }

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

# --- the scanner (stages 1-3 + census), written once to a temp OUTSIDE any scanned tree ---------
SCANNER="$TMPROOT/scanner.py"
cat > "$SCANNER" <<'PYEOF'
#!/usr/bin/env python3
# Stages: (1) enumerate sandboxed units [3 shapes: .service / .sh heredoc / cloud-init content:|],
# (2) map unit -> {scripts|NONE} (fail-closed), (3) cred-persist scan + relocation check + census.
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

def _segments(line):
    # Naive split on top-level command separators. Over-splitting is harmless for DETECTION:
    # a real `... | docker login ...` still lands `docker login` at a segment start, and a
    # `logger -t "$T" "...docker login..."` string keeps `docker login` mid-segment (not a start).
    return re.split(r'(?:\|\||&&|[|;&])', line)

def find_docker_sites(text):
    """Yield ('explicit', path) | ('inline', path) | ('global', None) per `docker ... login`."""
    sites = []
    for line in text.split('\n'):
        for seg in _segments(line):
            s = seg.strip()
            env = {}
            m = re.match(r'^((?:\w+=(?:"[^"]*"|\'[^\']*\'|\S+)\s+)+)', s)
            if m:
                for em in re.finditer(r'(\w+)=("[^"]*"|\'[^\']*\'|\S+)', m.group(1)):
                    env[em.group(1)] = em.group(2)
                s = s[m.end():]
            s = re.sub(r'^(?:sudo\s+|exec\s+|timeout\s+\S+\s+)+', '', s)
            if re.match(r'^docker\b', s) and re.search(r'\blogin\b', s):
                cm = re.search(r'--config[= ]("[^"]*"|\'[^\']*\'|\S+)', s)
                if cm:
                    sites.append(('explicit', cm.group(1)))
                elif 'DOCKER_CONFIG' in env:
                    sites.append(('inline', env['DOCKER_CONFIG']))
                else:
                    sites.append(('global', None))
    return sites

# doppler WRITE subcommands only. EXCLUDE reads: bare `doppler run` (token read),
# `doppler secrets get/download`, `doppler configure get|debug` (cla-evidence bootstrap.sh:79).
DOPPLER_WRITE_RE = re.compile(
    r'\bdoppler\s+(?:login\b|setup\b|configure\s+set\b|configure\s+token\b)')

def find_doppler_sites(text):
    sites = []
    for line in text.split('\n'):
        for seg in _segments(line):
            s = seg.strip()
            if DOPPLER_WRITE_RE.search(s):
                cm = re.search(r'--config-dir[= ]("[^"]*"|\'[^\']*\'|\S+)', s)
                sites.append(('explicit', cm.group(1)) if cm else ('global', None))
    return sites

def eval_target(kind, raw, assignments, rwp, default_home, global_var):
    if kind == 'global':
        raw = assignments.get(global_var)
        if raw is None:
            return default_home, False, 'no relocation; default %s' % default_home
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

def is_sandboxed(body):
    if '[Service]' not in body:
        return False
    return bool(re.search(
        r'^\s*(?:ProtectHome=(?:read-only|yes)|ProtectSystem=strict)\s*$', body, re.M))

def mk_unit(name, source, body):
    em = re.search(r'^\s*ExecStart=(.*)$', body, re.M)
    execstart = em.group(1).strip() if em else ''
    rwp = []
    for rm in re.finditer(r'^\s*ReadWritePaths=(.*)$', body, re.M):
        for tok in rm.group(1).split():
            rwp.append(tok[1:] if tok.startswith('-') else tok)  # strip one leading '-'
    return {'name': name, 'source': source, 'execstart': execstart, 'rwp': rwp}

# Heredoc-defined units: `cat > "$VAR" <<'MARKER' ... MARKER` (quoted OR unquoted marker;
# backreference \2 pins the closing marker so adjacent heredocs do not bleed). inngest.test.sh:176.
HEREDOC_RE = re.compile(
    r'cat\s*>\s*"?\$\{?(\w+)\}?"?\s*<<-?\s*\'?(\w+)\'?\n(.*?)\n[ \t]*\2', re.S)

def heredoc_units(src):
    for m in HEREDOC_RE.finditer(src):
        yield m.group(1), m.group(3)

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
            elif fn.endswith('.sh'):
                for var, body in heredoc_units(read(path)):
                    if is_sandboxed(body):
                        units.append(mk_unit(var, os.path.relpath(path, root) + ':heredoc', body))
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
    if 'doppler' in e and re.search(r'\brun\b', e) and not DOPPLER_WRITE_RE.search(e):
        return 'doppler-run'            # token read (redis/inngest/vector); no home-cred write
    return 'unknown'                    # fail-closed: new unit must be classified

def map_scripts(u, root):
    if classify(u) == 'webhook':
        return [os.path.join(root, 'ci-deploy.sh'), os.path.join(root, 'ci-deploy-wrapper.sh')]
    return []

def main():
    units = enumerate_units(ROOT)
    print('CENSUS: sandboxed_units=%d' % len(units))
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
        texts = [('inline:' + u['name'], u['execstart'])]
        for sp in map_scripts(u, ROOT):
            if not os.path.isfile(sp):
                violations.append('MISSING_SCRIPT: unit=%s script=%s (mapped script absent — '
                                  'fail-closed)' % (u['name'], os.path.relpath(sp, ROOT)))
                continue
            texts.append((os.path.relpath(sp, ROOT), strip_comments(read(sp))))
        assignments = gather_assignments([t for _, t in texts])

        unit_has_cred = False
        for site_name, text in texts:
            for cfg in find_docker_sites(text):
                unit_has_cred = True
                cred_sites += 1
                resolved, ok, reason = eval_target(cfg[0], cfg[1], assignments, u['rwp'],
                                                    '~/.docker', 'DOCKER_CONFIG')
                if kind == 'webhook' and ok:
                    webhook_docker = 'relocated'
                if not ok:
                    violations.append('FINDING: unit=%s site=%s family=docker target=%s reason=%s'
                                      % (u['name'], site_name, resolved, reason))
            for cfg in find_doppler_sites(text):
                unit_has_cred = True
                cred_sites += 1
                resolved, ok, reason = eval_target(cfg[0], cfg[1], assignments, u['rwp'],
                                                    '~/.doppler', 'DOPPLER_CONFIG_DIR')
                if not ok:
                    violations.append('FINDING: unit=%s site=%s family=doppler target=%s reason=%s'
                                      % (u['name'], site_name, resolved, reason))

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

scan() { python3 "$SCANNER" "$1"; }  # stdout = census + findings; exit 0 GREEN / non-zero RED

echo "=== credential-persist-home-guard tests (#6633) ==="
echo ""

# ---------------------------------------------------------------------------------------------
# AC2 + AC8 — real tree GREEN + non-empty-scan census (the anti-vacuity positive control)
# ---------------------------------------------------------------------------------------------
echo "--- AC2/AC8: real infra tree GREEN + census ---"
REAL_OUT="$(scan "$REAL_ROOT" 2>&1)" && REAL_RC=0 || REAL_RC=$?
if [[ "$REAL_RC" -eq 0 ]]; then
  pass "guard is GREEN on the real infra tree (relocated docker write + token doppler-run units)"
else
  fail "guard is NOT green on the real tree (exit $REAL_RC)" "$(printf '%s\n' "$REAL_OUT" | grep -E 'FINDING|UNCLASSIFIED|FAIL' | head -5)"
fi
if grep -qE 'CENSUS: sandboxed_units=[5-9]|CENSUS: sandboxed_units=[1-9][0-9]' <<<"$REAL_OUT"; then
  pass "enumeration is non-vacuous (>=5 sandboxed units found)"
else
  fail "enumeration found <5 sandboxed units (extractor broke)" "$(grep 'sandboxed_units' <<<"$REAL_OUT")"
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
# assert-mutated, RED-after, finding-text attribution to the mutated unit/script.
# ---------------------------------------------------------------------------------------------
echo ""
echo "--- AC3: mutation battery (each must independently drive RED, attributed) ---"

expect_red() {
  # expect_red <label> <attribution-substring> <mutate-fn>
  local label="$1" attrib="$2" mutate_fn="$3"
  local sbx; sbx="$(mktemp -d "$TMPROOT/mut.XXXXXX")"
  cp -r "$REAL_ROOT"/. "$sbx"/
  if ! python3 "$SCANNER" "$sbx" >/dev/null 2>&1; then
    fail "$label: fresh copy not GREEN before mutation (latent FAIL — attribution unsafe)"; return
  fi
  "$mutate_fn" "$sbx"
  if diff -rq "$REAL_ROOT" "$sbx" >/dev/null 2>&1; then
    fail "$label: mutation did not change the tree (assert_mutated failed)"; return
  fi
  local out rc
  out="$(python3 "$SCANNER" "$sbx" 2>&1)" && rc=0 || rc=$?
  if [[ "$rc" -eq 0 ]]; then
    fail "$label: guard stayed GREEN on the mutated tree (VACUOUS — pins nothing)"; return
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
expect_red "M1 export DOCKER_CONFIG=\$HOME/.docker (last-wins home)" "site=ci-deploy.sh" m1

# M2 — docker login with the DOCKER_CONFIG export removed (bare default ~/.docker).
m2() { sed -i 's|^export DOCKER_CONFIG="\$DEPLOY_DOCKER_CONFIG_DIR"|# removed by M2|' "$1/$CIDEPLOY"; }
expect_red "M2 no DOCKER_CONFIG export (bare ~/.docker default)" "site=ci-deploy.sh" m2

# M3 / M3b / M3c — detect-form parity: --config space / --config= / inline-env, all home-pointed.
m3()  { printf '\ndocker --config "$HOME/.docker" login ghcr.io -u x --password-stdin\n' >> "$1/$CIDEPLOY"; }
m3b() { printf '\ndocker --config=$HOME/.docker login ghcr.io\n' >> "$1/$CIDEPLOY"; }
m3c() { printf '\nDOCKER_CONFIG="$HOME/.docker" docker login ghcr.io\n' >> "$1/$CIDEPLOY"; }
expect_red "M3 docker --config <home> login (space form)"  "site=ci-deploy.sh" m3
expect_red "M3b docker --config=<home> login (equals form)" "site=ci-deploy.sh" m3b
expect_red "M3c DOCKER_CONFIG=<home> docker login (inline-env, no export)" "site=ci-deploy.sh" m3c

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
expect_red "M5 relocation to /opt/creds (off-home, not in RWP)" "site=ci-deploy.sh" m5
expect_red "M5b /mnt/data dropped from RWP (no blanket /mnt/data allow)" "unit=webhook.service" m5b

# M6 — delete ci-deploy.sh's real DOCKER_CONFIG export + indirection (exact #6565 shape).
m6() { sed -i '/DEPLOY_DOCKER_CONFIG_DIR:-\/mnt\/data\/deploy-docker/d; /^export DOCKER_CONFIG="\$DEPLOY_DOCKER_CONFIG_DIR"/d' "$1/$CIDEPLOY"; }
expect_red "M6 delete relocation (re-introduce #6565 shape)" "site=ci-deploy.sh" m6

# M7 / M7b — flip the ${VAR:-default} default to home / unresolvable var (fail-closed).
m7()  { sed -i 's|:-/mnt/data/deploy-docker|:-$HOME/.docker|' "$1/$CIDEPLOY"; }
m7b() { sed -i 's|^export DOCKER_CONFIG="\$DEPLOY_DOCKER_CONFIG_DIR"|export DOCKER_CONFIG="$SOME_UNSET_VAR"|' "$1/$CIDEPLOY"; }
expect_red "M7 flip \${VAR:-default} default to \$HOME (indirection resolved)" "site=ci-deploy.sh" m7
expect_red "M7b export unresolvable \$SOME_UNSET_VAR (fail-closed)" "site=ci-deploy.sh" m7b

# M8 — heredoc-defined sandboxed unit with an inline `docker login` in ExecStart, no separate
# script (RED either by scanning the inline ExecStart or fail-closed on unclassified+family-action).
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

# ---------------------------------------------------------------------------------------------
echo ""
echo "=== credential-persist-home-guard: PASS=$PASS FAIL=$FAIL ==="
[[ "$FAIL" -eq 0 ]] || exit 1
