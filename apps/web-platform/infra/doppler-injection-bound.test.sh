#!/usr/bin/env bash
# shellcheck disable=SC2016  # single-quoted mutation bodies are LITERAL shell/unit text written
# into fixture copies by design ($D / ${!KEY} / $VAR must NOT expand here — they are the source
# strings the scanner reads). Mirrors credential-persist-home-guard.test.sh.
#
# Guard 2 (#7761) — every `doppler run` unit BOUNDS its injected secret set.
#
# WHY THIS FILE EXISTS
# ====================
# `doppler run -- <cmd>` injects the WHOLE config into the child's environment. When the child is
# a shell script that takes an environment value in COMMAND POSITION (executes it, or sources a
# path named by it), every unenumerated secret name is a live argv/exec seam: a Doppler secret
# whose name collides with one of the script's seam variables silently redirects what the unit
# executes. That is the class #7761 is about, and `--only-secrets` is the runtime half of the fix
# (the in-script argv gate is Guard 1).
#
# PROPERTY. Every unit in this repo whose ExecStart / ExecStartPre / ExecStartPost passes through
# `doppler run`, AND whose target script uses an environment value in command position (executed
# or sourced) — or which resolves its own secret by INDIRECT expansion (${!NAME_KEY}) — either
# enumerates its secrets with `--only-secrets` (as a `doppler run` FLAG, i.e. before the `--`), or
# appears in ACK_REASONS below with a written reason. ACK_REASONS' cardinality is pinned so the
# escape hatch cannot grow silently.
#
# FOUR SCOPING DECISIONS the naive property gets wrong, each verified against this repo:
#
#   1. ExecStartPre COUNTS. The #6178 arm-atomicity flip-guard ships as
#      `ExecStartPre=/usr/bin/doppler run …`, assigned into FLIP_GUARD_LINE at
#      inngest-bootstrap.sh:1089 and substituted into the inngest-server heredoc at :990. A scan
#      anchored on `^ExecStart=` misses the one instance the plan documented as vulnerable — so
#      the directive regex covers Exec{Start,StartPre,StartPost} AND a fifth extraction surface
#      exists for directives INJECTED by shell assignment rather than written in a heredoc.
#
#   2. THE LITERAL `doppler run` IS NOT THE POPULATION. Five units resolve the binary first:
#        D="$(command -v doppler || true)"; … exec "$D" run --project soleur --config prd -- …
#      (cron-egress-firewall.service, cron-egress-resolve.service, cron-egress-alarm@.service,
#      container-restart-monitor.service, and the web-host vector unit in
#      soleur-host-bootstrap.sh), plus `${DOPPLER_BIN} run` for the heartbeat unit. A grep for the
#      literal misses roughly a third of the population, and a floor row would still pass on the
#      remainder. doppler_run_offset() therefore matches the resolved-variable spelling too.
#
#   3. `runcmd` INVOCATIONS ARE EXCLUDED — structurally, not by predicate. Only `.service` files,
#      `cat > … <<EOF` heredocs and cloud-init `content: |` blocks are enumerated, and a runcmd
#      entry is none of those. The boot isolation self-check at cloud-init-inngest.yml:604-611
#      must see ALL names to do its job; demanding a bound there would self-defeat the
#      provision-time control this guard is the runtime half of. Pinned by a must-PASS row.
#
#   4. AN EXEMPTION CLASS IS REQUIRED, NOT OPTIONAL. Four probe units resolve their own secret by
#      indirect expansion over a per-host key name Terraform bakes in and the tracked unit never
#      contains — `export WEB_ZOT_CONSUMER_URL="${!WEB_ZOT_CONSUMER_URL_KEY}"` — where the key
#      expands to e.g. WEB_ZOT_CONSUMER_URL_WEB_1 (server.tf:683,734; :820 and :871 are identity
#      mappings today — see ACK_REASONS for the measured correction). A literal
#      `--only-secrets` list in a TRACKED unit cannot name a per-host secret, and the flag is
#      fail-closed on a listed-but-absent name, so the same unit on a second web host would break
#      — on the multi-host path the fleet is actively opening. That is a real limit of the
#      invariant, not a false positive to predicate away, so it is an ACK with a reason.
#
# THE LISTS ARE AUTHORED AND COMMENTED, NEVER DERIVED. Two independent exhaustive derivations over
# the same two sibling scripts produced DIFFERENT answers in both directions, and both misses are
# silent under `--no-exit-on-missing-only-secrets`:
#   * cron-egress-resolve.sh:149-157 reads three names by INDIRECT EXPANSION OVER A LITERAL LOOP
#     LIST (`for var in SENTRY_INGEST_DOMAIN NEXT_PUBLIC_SUPABASE_URL SUPABASE_URL; do
#     val="${!var:-}"`). No `$NEXT_PUBLIC_SUPABASE_URL` expansion exists anywhere in that file, so
#     any grep-shaped derivation drops them — and omitting them does not fail loud: :154-155 only
#     warns and forces the tick additive-only with pruning suspended.
#   * git-data-emit's redactor is VALUE-based (cloud-init-git-data.yml:142-150) because the LUKS
#     passphrase is high-entropy and matches no pattern. Under a narrow list `_devalue` degrades
#     to `cat` and repack stderr rides into the emit's detail argument.
# So this guard checks an AUTHORED list against a LOWER BOUND of names the script provably reads.
# It does not, and cannot, reproduce the list. See read_set_lower_bound().
#
# Self-contained: pure bash + python3. No network, root, docker, terraform or cloud-init needed.
# COPIED, NOT SOURCED: infra suites are inlined by policy (ADR-177 §A3) because
# run-registered-suites.sh:422-434 sandboxes a suite with a SINGLE-FILE copy.
set -euo pipefail

# /tmp on the dev host is a 4 GiB tmpfs shared by up to 6 parallel slots of
# run-registered-suites.sh; a DIRECT invocation inherits the bare /tmp. /var/tmp is disk-backed.
export TMPDIR="${TMPDIR:-/var/tmp}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REAL_ROOT="${DOPPLER_BOUND_INFRA_ROOT:-$SCRIPT_DIR}"

# GLOBIGNORE (used by copy_scan_tree) is a COLON-SEPARATED pattern list; a ':' or a glob
# metacharacter in the root silently disables the .terraform exclusion and the 162 MB provider
# cache rides into every sandbox with the run still green. Refuse rather than degrade.
case "$REAL_ROOT" in
  *[][*?:\\]*)
    echo "FATAL: DOPPLER_BOUND_INFRA_ROOT contains ':' or a glob metacharacter: $REAL_ROOT" >&2
    exit 2 ;;
esac

PASS=0
FAIL=0
# fail() MUST return 0 so `set -e` does not abort the harness at the first failing assertion —
# otherwise the summary never prints and later assertions never run. The sole exit chokepoint is
# the final `[[ "$FAIL" -eq 0 ]] || exit 1`.
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; [[ -n "${2:-}" ]] && echo "        $2"; return 0; }

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT INT TERM HUP

copy_scan_tree() {
  local rc=0
  ( GLOBIGNORE="$1/.terraform"; cp -r "$1"/* "$2"/; ) || rc=$?
  [[ "$rc" -eq 0 ]] || {
    echo "FATAL: sandbox copy failed (rc=$rc) — refusing to scan a truncated tree: $1 -> $2" >&2
    exit 1
  }
  find "$2" -mindepth 1 -type d -name .terraform -prune -exec rm -rf {} + 2>/dev/null || true
}
# SINGLE SOURCE of the exclusion for the comparison side, so the copy and the mutation-landed
# check cannot drift.
scan_diff() { diff -rq --exclude=.terraform "$1" "$2"; }
fresh_sbx() { rm -rf "$TMPROOT"/sbx.*; mktemp -d "$TMPROOT/sbx.$1.XXXXXX"; }

# FROZEN_ROOT: the comparison side, snapshotted ONCE. This suite runs concurrently with ~90
# sibling suites, several of which legitimately write into this same directory; a file appearing
# or vanishing inside a copy->diff window would produce a RED here caused entirely by a DIFFERENT
# suite (#7376). Every copy and diff below reads FROZEN_ROOT, never the live $REAL_ROOT.
FROZEN_ROOT="$TMPROOT/frozen"
mkdir -p "$FROZEN_ROOT"
copy_scan_tree "$REAL_ROOT" "$FROZEN_ROOT"

# ── the scanner ───────────────────────────────────────────────────────────────────────────────
SCANNER="$TMPROOT/scanner.py"
cat > "$SCANNER" <<'PYEOF'
#!/usr/bin/env python3
# Guard 2 scanner. Stages:
#   (1) enumerate unit definitions on FOUR authoring surfaces + a fifth injected-directive
#       extraction, with a PER-SURFACE non-vacuity floor;
#   (2) select the `doppler run` population (literal AND resolved-binary spellings);
#   (3) resolve each unit's target scripts across three script-authoring surfaces;
#   (4) decide bound-required membership (exec/source seam in the target, or ${!VAR} indirect
#       expansion in the unit itself);
#   (5) check the bound is a `doppler run` FLAG (before the `--`) and names at least one secret;
#   (6) reconcile against ACK_REASONS and pin its cardinality;
#   (7) check each AUTHORED list against a LOWER BOUND of names its script provably reads.
# Exit: 0 GREEN | 2 violations | 3 census floor | 4 per-surface enumeration floor | 5 ack
#       inconsistency | 6 read-set lower-bound violation.
import os, re, sys

ROOT = os.path.abspath(sys.argv[1])

# ── floors, all DERIVED FROM A GREEN RUN, never guessed ──────────────────────────────────────
# Measured on the tree at 2026-09-03: service=16 sh-heredoc=6 tf-heredoc=4 cloud-init=7,
# injected=1, doppler units=16, bound-required population=8. Set below the measurement so an
# ordinary deletion does not red, but far enough above zero that a broken extractor does.
# RAISE these in lockstep when the population grows; NEVER lower one to make a run pass.
MIN_UNITS_BY_SURFACE = {'service': 12, 'sh-heredoc': 4, 'tf-heredoc': 3, 'cloud-init': 5}
MIN_INJECTED_DIRECTIVES = 1
MIN_DOPPLER_UNITS = 12
MIN_POPULATION = 5

# ── Guard 1's unset list, CONSUMED not re-derived ────────────────────────────────────────────
# Row R3's "non-seam read-set" is the script's read-set MINUS the names Guard 1's in-script argv
# gate unsets. Re-deriving it here would invert the intent: a naive read-set would demand every
# fixture seam appear in `--only-secrets`, i.e. that the unit INJECT the very names the gate
# exists to strip. These are the 15 names Guard 1 unsets (measured 2026-09-03); when Guard 1's
# list changes, this copy moves with it.
GUARD1_UNSET = {
    'CUTOVER_CURL_CMD', 'CUTOVER_DONE_OWNER_MARKER', 'CUTOVER_FLAG_SET_CMD', 'CUTOVER_FLIP_FLAG',
    'CUTOVER_GQL_URL', 'CUTOVER_HEALTH_URL', 'CUTOVER_LOGGER_CMD', 'CUTOVER_REDIS_CLI_CMD',
    'CUTOVER_REDIS_DBSIZE', 'CUTOVER_SYSTEMCTL_CMD', 'CUTOVER_VERIFY_INTERVAL_S',
    'CUTOVER_VERIFY_WINDOW_S', 'INNGEST_CUTOVER_LATCH', 'INNGEST_CUTOVER_LATCH_MOUNT',
    'INNGEST_CUTOVER_STATE',
}
GUARD1_UNSET_CARDINALITY = 15

# ── the ack list: AUTHORED, each entry carrying WHY, cardinality pinned ───────────────────────
ACK_REASONS = {
    # -- exemption class A: indirect expansion over a Terraform-supplied key name ---------------
    # These four resolve their own secret as ${!<NAME>_KEY}: the tracked unit never contains the
    # secret's NAME at all, only the name of a variable holding it, which Terraform writes into
    # /etc/default/<unit> per host. A literal `--only-secrets` list in a TRACKED unit therefore
    # cannot name the secret, and the flag is fail-closed on a listed-but-absent name.
    #
    # MEASURED, and it corrects the plan: only TWO of the four keys are per-host TODAY.
    # server.tf:683 and :734 build the key as `<NAME>_${upper(replace("web-1","-","_"))}`, i.e.
    # WEB_NIC_GUARD_URL_WEB_1 / WEB_ZOT_CONSUMER_URL_WEB_1. server.tf:820 and :871 are IDENTITY
    # mappings ('INNGEST_CONSUMER_URL' / 'GIT_DATA_HEARTBEAT_URL') because there is one dedicated
    # inngest host and one git-data host. The exemption holds for all four regardless: the name is
    # not in the unit, and :820/:871 become per-host on the multi-host path the fleet is opening.
    'web-zot-consumer-probe.service':
        'indirect expansion of WEB_ZOT_CONSUMER_URL_KEY, which server.tf:734 builds PER HOST '
        '(WEB_ZOT_CONSUMER_URL_WEB_1) — no literal list in a tracked unit can name it',
    'web-private-nic-guard.service':
        'indirect expansion of WEB_NIC_GUARD_URL_KEY, which server.tf:683 builds PER HOST '
        '(WEB_NIC_GUARD_URL_WEB_1) — same fail-closed multi-host break',
    'inngest-consumer-probe.service':
        'indirect expansion of INNGEST_CONSUMER_URL_KEY; server.tf:820 maps it to the identity '
        'name today (one dedicated inngest host), but the unit still never names the secret, so '
        'the list would have to be authored against a variable rather than a name',
    'web-git-data-probe.service':
        'indirect expansion of GIT_DATA_HEARTBEAT_URL_KEY; server.tf:871 is an identity mapping '
        'today for the single git-data host, with the same never-named-in-the-unit limit',
    # -- exemption class B: the read-set is not authorable from the tracked source ---------------
    'cron-egress-resolve.service':
        'read-set is not derivable: cron-egress-resolve.sh:149-157 reads SENTRY_INGEST_DOMAIN / '
        'NEXT_PUBLIC_SUPABASE_URL / SUPABASE_URL by indirect expansion over a literal loop list, '
        'and omitting one is SILENT under --no-exit-on-missing-only-secrets — :154-155 only warns '
        'and forces the tick additive-only with pruning suspended (an egress firewall that '
        'quietly stops pruning). Bounding it needs a hand-authored list, out of scope for #7761.',
    'git-data-gc.service':
        "git-data-emit's redactor is VALUE-based (cloud-init-git-data.yml:142-150) because the "
        'LUKS passphrase is high-entropy and matches no pattern. Under a list that omits '
        'GIT_DATA_LUKS_KEY, _devalue degrades to `cat` and repack stderr rides into the emit '
        'detail (git-data-gc.sh:138,142) — a passphrase could ship unredacted to Sentry and '
        'Better Stack. Bounding this unit is a security-reviewed change, not a hygiene edit.',
    'container-restart-monitor.service':
        'sources an env-named file (a `. "$ENV_FILE"` at container-restart-monitor.sh:61) whose '
        'contents are not in-repo, so the tracked script does not bound the read-set; its Sentry '
        'alarm path also degrades silently on a missing name (:67 returns without emitting).',
}
ACK_CARDINALITY = 7

# ── surface enumeration (LIFTED from credential-persist-home-guard.test.sh:506-605) ───────────
# The two non-obvious behaviours a fresh scanner gets wrong SILENTLY are kept verbatim:
#   * the `.tf` \n-unescape — terraform inline arrays are \n-escaped SINGLE-LINE strings that a
#     naive scanner reads as one line and matches nothing, failing OPEN;
#   * the in-place `.terraform/` prune (dirs[:] assignment; rebinding `dirs` does not prune).
EXEC_RE = re.compile(r'^\s*Exec(?:Start|StartPre|StartPost)=(.*)$', re.M)
# systemd continues any directive whose line ends in a backslash. Every directive regex here is
# line-anchored, so WITHOUT this join a multi-line ExecStart is TRUNCATED at the first backslash
# — and the flip unit's bound lives ENTIRELY on continuation lines, so the guard would read every
# unit as unbounded and every row below would be meaningless. `execs` is the UNION of the joined
# and the raw body so no directive can be lost to the join absorbing its successor.
CONT_RE = re.compile(r'\\\n[ \t]*')
HEREDOC_RE = re.compile(
    r'cat\s*>\s*("[^"]*"|\'[^\']*\'|\S+)\s*<<-?\s*["\']?(\w+)["\']?\n(.*?)\n[ \t]*\2', re.S)
# A directive INJECTED by shell assignment rather than written inside a heredoc — the fifth
# extraction. inngest-bootstrap.sh:1089 is the only real member today.
INJECTED_RE = re.compile(
    r'^\s*(?:readonly\s+|local\s+|export\s+)?(\w+)=(["\'])'
    r'(Exec(?:Start|StartPre|StartPost)=.*?)\2\s*$', re.M)
ASSIGN_RE = re.compile(r'^\s*(?:readonly\s+|local\s+|export\s+)?(\w+)="?(/[^"\'\s]+)"?\s*$', re.M)


def _clean(p):
    return p.strip().strip('"').strip("'")


def mk_unit(name, source, surface, body):
    raw = body
    joined = CONT_RE.sub(' ', body)
    execs = [m.group(1).strip() for m in EXEC_RE.finditer(joined)]
    for m2 in EXEC_RE.finditer(raw):
        t = m2.group(1).strip()
        if t not in execs:
            execs.append(t)
    return {'name': name, 'source': source, 'surface': surface, 'execs': execs}


def _heredoc_name(target, assigns):
    t = _clean(target)
    if t.startswith('$'):
        key = t.lstrip('$').strip('{}')
        if key in assigns:
            return os.path.basename(assigns[key])
        return t
    return os.path.basename(t) if '/' in t else t


def heredoc_units(src, assigns):
    for m in HEREDOC_RE.finditer(src):
        yield _heredoc_name(m.group(1), assigns), _clean(m.group(1)), m.group(3)


def cloudinit_blocks(src):
    """Yield (path, body) for every `content: |` block, tagged with the nearest preceding path:.

    cloud-init write_files units are INDENTED YAML block-scalars, NOT heredocs — a `cat >` regex
    finds ZERO here, which is the non-vacuous-zero false-green the per-surface floor guards.
    """
    out = []
    lines = src.split('\n')
    i = 0
    cur_path = None
    while i < len(lines):
        pm = re.match(r'^\s*-?\s*path:\s*(\S+)', lines[i])
        if pm:
            cur_path = _clean(pm.group(1))
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
            out.append((cur_path, '\n'.join(body)))
            i = j
            continue
        i += 1
    return out


def read(path):
    try:
        with open(path, encoding='utf-8', errors='replace') as f:
            return f.read()
    except OSError:
        return ''


def is_unit_body(body):
    return bool(re.search(r'^\s*\[Service\]', body, re.M)) or bool(EXEC_RE.search(body))


def enumerate_all(root):
    """Return (units, injected, scripts). scripts maps basename -> (origin, body).

    A script can be authored on THREE surfaces and the same basename can appear on more than one
    (git-data-gc.sh is both a tracked file and a cloud-init `content:` copy). The TRACKED FILE
    always wins: the embedded copies are terraform-templated, so their `$` are written `$$` and
    every seam form silently stops matching — a fail-OPEN that measured as "git-data-gc.service
    is not in the population" while the tracked script plainly carries a `"$EMIT"` seam.
    """
    units, injected, tracked, embedded = [], [], {}, {}
    for dp, dirs, files in os.walk(root):
        # `.terraform/modules/` holds real .tf files as soon as any `module {}` block with a
        # registry/git source is added; enumerating vendored third-party units would RED on code
        # the team does not own. `dirs[:]` in-place assignment is required.
        dirs[:] = [d for d in dirs if d != '.terraform']
        for fn in sorted(files):
            path = os.path.join(dp, fn)
            rel = os.path.relpath(path, root)
            if fn.endswith('.test.sh'):  # test fixtures build unit strings; never real defs
                continue
            if fn.endswith('.service'):
                body = read(path)
                if is_unit_body(body):
                    units.append(mk_unit(fn, rel + ':service', 'service', body))
            elif fn.endswith(('.sh', '.tf')):
                src = read(path)
                if fn.endswith('.tf'):
                    src = src.replace('\\n', '\n')
                surface = 'tf-heredoc' if fn.endswith('.tf') else 'sh-heredoc'
                assigns = dict(ASSIGN_RE.findall(src))
                for name, target, body in heredoc_units(src, assigns):
                    if is_unit_body(body):
                        units.append(mk_unit(name, rel + ':heredoc', surface, body))
                        continue
                    key = target.lstrip('$').strip('{}')
                    resolved = target if target.startswith('/') else assigns.get(key)
                    if resolved:
                        embedded.setdefault(os.path.basename(resolved), (rel + ':heredoc', body))
                for m in INJECTED_RE.finditer(src):
                    injected.append(mk_unit('%s[%s]' % (fn, m.group(1)),
                                            rel + ':injected', surface, m.group(3)))
                if fn.endswith('.sh'):
                    tracked[fn] = (rel, src)
            elif fn.endswith(('.yml', '.yaml')):
                for idx, (cpath, body) in enumerate(cloudinit_blocks(read(path))):
                    if is_unit_body(body):
                        dm = re.search(r'^\s*Description=(.*)$', body, re.M)
                        nm = (dm.group(1).strip()[:40] if dm else 'unit%d' % idx)
                        units.append(mk_unit('%s[%s]' % (fn, nm), rel + ':cloud-init',
                                             'cloud-init', body))
                    elif cpath and cpath.startswith('/'):
                        # cloud-init bodies are rendered through terraform templatefile(), which
                        # escapes a literal `$` as `$$`. Un-escape before any expansion-shaped
                        # regex reads them, or every seam and read-set form matches nothing.
                        embedded.setdefault(os.path.basename(cpath),
                                            (rel + ':cloud-init', body.replace('$$', '$')))
    scripts = dict(embedded)
    scripts.update(tracked)
    return units, injected, scripts


# ── stage 2: the `doppler run` population ────────────────────────────────────────────────────
# TWO spellings, because the literal is not the population:
#   a) `doppler run` / `/usr/local/bin/doppler run`
#   b) `"$D" run` / `${DOPPLER_BIN} run` — the binary resolved into a variable first
DOPPLER_LITERAL_RE = re.compile(r'\bdoppler\s+run\b')
DOPPLER_VAR_RE = re.compile(r'(?:"\$\{?(\w+)\}?"|\$\{(\w+)\}|\$(\w+))\s+run\b')


def doppler_run_offset(exec_text):
    """Offset just past the `run` token of a doppler invocation, or None."""
    m = DOPPLER_LITERAL_RE.search(exec_text)
    if m:
        return m.end()
    for m in DOPPLER_VAR_RE.finditer(exec_text):
        var = m.group(1) or m.group(2) or m.group(3)
        # The variable must demonstrably hold the doppler binary somewhere in the SAME directive.
        if re.search(r'\b%s=[^;]*doppler' % re.escape(var), exec_text) or 'DOPPLER' in var.upper():
            return m.end()
    return None


SEP_RE = re.compile(r'(?<=\s)--(?=\s)')
# `--no-exit-on-missing-only-secrets` CONTAINS the substring `only-secrets`. The negative
# lookbehind on [-\w] is what stops it being read as a bound — anchor on the construct, never the
# bare token (cq-assert-anchor-not-bare-token).
ONLY_SECRETS_RE = re.compile(r'(?<![-\w])--only-secrets(?:[= ]+)([^\s]*)')
INDIRECT_RE = re.compile(r'\$\{!(\w+)\}')
PATH_TOKEN_RE = re.compile(r'/usr/(?:local/)?bin/([A-Za-z0-9._-]+)')


def analyse_exec(exec_text):
    """None if not a doppler-run directive, else a dict describing its bound."""
    off = doppler_run_offset(exec_text)
    if off is None:
        return None
    seg = exec_text[off:]
    sep = SEP_RE.search(seg)
    prefix = seg[:sep.start()] if sep else seg
    suffix = seg[sep.end():] if sep else ''
    names, empties = [], 0
    for m in ONLY_SECRETS_RE.finditer(prefix):
        raw = m.group(1).strip().strip('"').strip("'")
        vals = [v for v in raw.split(',') if re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*', v)]
        if vals:
            names.extend(vals)
        else:
            empties += 1
    return {
        'names': names,
        'empty_flags': empties,
        'after_sep_only_secrets': bool(ONLY_SECRETS_RE.search(suffix)),
        'indirect': sorted(set(INDIRECT_RE.findall(exec_text))),
        'targets': sorted(set(PATH_TOKEN_RE.findall(exec_text))),
    }


# ── stage 4: the exec seam predicate ─────────────────────────────────────────────────────────
# "Uses an environment value in COMMAND POSITION (executed or sourced)" — three high-precision
# forms only. Deliberately NARROW: a loose form (matching after `&&`, or inside [[ … ]]) put
# arithmetic and string comparisons into the population when measured, and a false member here is
# a permanently-red guard, not a near miss.
CMD_POS_RE = re.compile(r'^[ \t]*"\$\{?([A-Z_][A-Z0-9_]*)(?:[:#%/][^"]*)?\}?"')
SEAM_FORMS = (
    ('exec-var', re.compile(r'\bexec[ \t]+"?\$\{?([A-Z_][A-Z0-9_]*)', re.M)),
    ('sourced-path', re.compile(r'(?:^|[ \t;])(?:\.|source)[ \t]+"?\$\{?([A-Z_][A-Z0-9_]*)', re.M)),
)


def cmd_position_seam(lines):
    """A leading `"$VAR"` is command position ONLY when the line starts a command.

    The exclusion is load-bearing and was measured: git-data-emit's curl payload continues its
    argument list onto a line beginning `"${MSG}" "${LEVEL}" …`, whose predecessor ends in a
    backslash. Read as command position that put git-data-gc-failure.service into the population
    on the strength of a printf ARGUMENT — a false member, i.e. a permanently-red guard.
    """
    prev = ''
    for ln in lines:
        m = CMD_POS_RE.match(ln)
        if m and not prev.rstrip().endswith('\\'):
            return 'cmd-position:%s' % m.group(1)
        if ln.strip():
            prev = ln
    return None


def strip_comments(src):
    # Only a `#` that STARTS a word is a comment: "${VAR#prefix}" must survive, or the seam forms
    # stop matching parameter-expansion spellings and the guard fails open.
    return '\n'.join(re.sub(r'(^|\s)#.*$', r'\1', ln) for ln in src.split('\n'))


def seam_evidence(body):
    src = strip_comments(body)
    hit = cmd_position_seam(src.split('\n'))
    if hit:
        return hit
    for label, rx in SEAM_FORMS:
        m = rx.search(src)
        if m:
            return '%s:%s' % (label, m.group(1))
    return None


# ── stage 7: the read-set LOWER BOUND ────────────────────────────────────────────────────────
SHELL_BUILTINS = {
    'BASH_SOURCE', 'BASH_VERSION', 'BASH_REMATCH', 'BASHPID', 'BASH_SUBSHELL', 'BASH_LINENO',
    'BASH_COMMAND', 'FUNCNAME', 'LINENO', 'RANDOM', 'SECONDS', 'PIPESTATUS', 'OPTARG', 'OPTIND',
    'REPLY', 'IFS', 'PATH', 'HOME', 'PWD', 'OLDPWD', 'SHELL', 'SHLVL', 'USER', 'LOGNAME', 'UID',
    'EUID', 'HOSTNAME', 'HOSTTYPE', 'OSTYPE', 'MACHTYPE', 'TERM', 'TMPDIR', 'LANG', 'LC_ALL',
    'LC_CTYPE', 'COLUMNS', 'LINES', 'EDITOR', 'PAGER', 'EPOCHSECONDS', 'EPOCHREALTIME',
    'GLOBIGNORE', 'PS1', 'PS2', 'PS4', 'DEBIAN_FRONTEND',
}
READ_RE = re.compile(r'\$\{!?([A-Z][A-Z0-9_]{2,})[:\-+#%/}\[]|\$([A-Z][A-Z0-9_]{2,})\b')
ASSIGNED_RE = re.compile(
    r'^\s*(?:readonly\s+|local\s+|export\s+|declare\s+-\w+\s+)?([A-Z][A-Z0-9_]{2,})=', re.M)
FORVAR_RE = re.compile(r'\bfor\s+([A-Z][A-Z0-9_]{2,})\s+in\b')


def read_set_lower_bound(body):
    src = strip_comments(body)
    reads = set()
    for m in READ_RE.finditer(src):
        reads.add(m.group(1) or m.group(2))
    assigned = set(ASSIGNED_RE.findall(src)) | set(FORVAR_RE.findall(src))
    return sorted(reads - assigned - SHELL_BUILTINS - GUARD1_UNSET)


def main():
    units, injected, scripts = enumerate_all(ROOT)

    by_surface = {}
    for u in units:
        by_surface[u['surface']] = by_surface.get(u['surface'], 0) + 1
    print('CENSUS: units=%d injected_directives=%d scripts_indexed=%d'
          % (len(units), len(injected), len(scripts)))
    for s in sorted(MIN_UNITS_BY_SURFACE):
        print('CENSUS: surface=%-11s scanned=%-3d min=%d'
              % (s, by_surface.get(s, 0), MIN_UNITS_BY_SURFACE[s]))
    print('CENSUS: surface=%-11s scanned=%-3d min=%d'
          % ('sh-injected', len(injected), MIN_INJECTED_DIRECTIVES))

    rc = 0
    # PER-SURFACE FLOOR. A scanner that matches zero units on a surface reports zero violators and
    # passes forever; the .tf \n-unescape and the cloud-init block-scalar walk are each one edit
    # away from that, and neither failure is visible in a total.
    # --- BEGIN PER-SURFACE FLOOR (the H2 anti-vacuity row anchors on these markers) ---
    for s, floor in sorted(MIN_UNITS_BY_SURFACE.items()):
        got = by_surface.get(s, 0)
        if got < floor:
            print('SURFACE_FLOOR_FAIL surface=%s scanned=%d min=%d — the extractor for this '
                  'authoring surface matches nothing; a green run would mean "scanned nothing"'
                  % (s, got, floor))
            rc = 4
    if len(injected) < MIN_INJECTED_DIRECTIVES:
        print('SURFACE_FLOOR_FAIL surface=sh-injected scanned=%d min=%d — an ExecStartPre injected '
              'by shell assignment (inngest-bootstrap.sh:1089) is no longer seen'
              % (len(injected), MIN_INJECTED_DIRECTIVES))
        rc = 4
    # --- END PER-SURFACE FLOOR ---
    if rc:
        return rc

    if len(GUARD1_UNSET) != GUARD1_UNSET_CARDINALITY:
        print('ACK_FAIL guard1_unset_cardinality=%d expected=%d'
              % (len(GUARD1_UNSET), GUARD1_UNSET_CARDINALITY))
        return 5
    if len(ACK_REASONS) != ACK_CARDINALITY:
        print('ACK_FAIL ack_cardinality=%d expected=%d — the ack list is the guard\'s only escape '
              'hatch; changing its size must be a deliberate, visible edit'
              % (len(ACK_REASONS), ACK_CARDINALITY))
        return 5
    for name, reason in sorted(ACK_REASONS.items()):
        if len(reason.strip()) < 40:
            print('ACK_FAIL unit=%s — ack entries carry a written reason, not a bare name' % name)
            return 5

    doppler = []
    for u in units + injected:
        infos = [i for i in (analyse_exec(e) for e in u['execs']) if i]
        if infos:
            doppler.append((u, infos))
    print('CENSUS: doppler_run_units=%d min=%d' % (len(doppler), MIN_DOPPLER_UNITS))
    if len(doppler) < MIN_DOPPLER_UNITS:
        print('CENSUS_FAIL doppler_run_units=%d (<%d) — the population selector matches nothing, '
              'so every bound assertion below is vacuous' % (len(doppler), MIN_DOPPLER_UNITS))
        return 3

    findings = []
    population = []
    for u, infos in doppler:
        reasons, targets = [], []
        for info in infos:
            for ind in info['indirect']:
                reasons.append('indirect-expansion:%s' % ind)
            for t in info['targets']:
                if t in scripts:
                    ev = seam_evidence(scripts[t][1])
                    if ev:
                        reasons.append('seam[%s]:%s' % (t, ev))
                        targets.append(t)
        names, empty, after_sep = [], 0, False
        for info in infos:
            names += info['names']
            empty += info['empty_flags']
            after_sep = after_sep or info['after_sep_only_secrets']
        print('  UNIT: %-46s surface=%-11s bound=%-5s src=%s'
              % (u['name'], u['surface'], bool(names), u['source']))
        if not reasons:
            continue
        population.append(u['name'])
        print('        POPULATION reason=%s' % '; '.join(sorted(set(reasons))))
        if names:
            lower = set()
            for t in targets:
                lower |= set(read_set_lower_bound(scripts[t][1]))
            missing = sorted(lower - set(names))
            if missing:
                findings.append(
                    'READ_SET_FAIL unit=%s missing-from-only-secrets=%s — the script provably '
                    'reads this name and the AUTHORED list omits it; under '
                    '--no-exit-on-missing-only-secrets that is silent at run time. This is a '
                    'LOWER BOUND, not a derivation: add the name to --only-secrets, or to '
                    "Guard 1's unset list if it is a fixture seam."
                    % (u['name'], ','.join(missing)))
            continue
        if u['name'] in ACK_REASONS:
            continue
        if after_sep:
            findings.append(
                'FINDING unit=%s reason=--only-secrets sits AFTER the `--` separator, where it is '
                'an argument to the CHILD command rather than a `doppler run` flag; the whole '
                'config is still injected src=%s' % (u['name'], u['source']))
        elif empty:
            findings.append(
                'FINDING unit=%s reason=--only-secrets carries an EMPTY value, so it enumerates '
                'nothing src=%s' % (u['name'], u['source']))
        else:
            findings.append(
                'FINDING unit=%s reason=no --only-secrets bound on a `doppler run` whose target '
                'takes an environment value in command position (%s) and which is not in the ack '
                'list src=%s' % (u['name'], '; '.join(sorted(set(reasons)))[:120], u['source']))

    print('CENSUS: bound_required_population=%d min=%d' % (len(population), MIN_POPULATION))
    if len(population) < MIN_POPULATION:
        print('CENSUS_FAIL bound_required_population=%d (<%d) — the seam predicate matches nothing'
              % (len(population), MIN_POPULATION))
        return 3

    stale = sorted(set(ACK_REASONS) - set(population))
    if stale:
        print('ACK_FAIL stale=%s — acked units no longer in the population; delete the entry and '
              'lower ACK_CARDINALITY rather than leaving a hole open' % ','.join(stale))
        rc = 5

    for f in findings:
        print(f)
    if any(f.startswith('READ_SET_FAIL') for f in findings):
        rc = 6
    if any(f.startswith('FINDING') for f in findings):
        rc = 2
    return rc


sys.exit(main())
PYEOF

echo ""
echo "--- control: the UNMUTATED tree ---"
CONTROL_OUT="$TMPROOT/control.txt"
if python3 "$SCANNER" "$FROZEN_ROOT" >"$CONTROL_OUT" 2>&1; then
  pass "baseline: the real tree is GREEN (a red baseline would void every mutation row)"
else
  fail "baseline: the real tree is RED — every mutation row below is unattributable" \
    "$(grep -E 'FINDING|_FAIL' "$CONTROL_OUT" | head -5)"
fi

# ── census + identity pins ────────────────────────────────────────────────────────────────────
echo ""
echo "--- census: per-surface breakdown (all four authoring surfaces + injected directives) ---"
grep -E '^CENSUS:' "$CONTROL_OUT" | sed 's/^/  /'

for _s in service sh-heredoc tf-heredoc cloud-init sh-injected; do
  _line="$(grep -E "^CENSUS: surface=${_s}[ ]" "$CONTROL_OUT" || true)"
  if [[ -z "$_line" ]]; then
    fail "census: no scanned count reported for surface '$_s'"
    continue
  fi
  _got="$(sed -E 's/.*scanned=([0-9]+).*/\1/' <<<"$_line")"
  _min="$(sed -E 's/.*min=([0-9]+).*/\1/' <<<"$_line")"
  if (( _got >= _min )) && (( _min >= 1 )); then
    pass "census: surface '$_s' scanned $_got units (floor $_min)"
  else
    fail "census: surface '$_s' scanned $_got units, floor $_min"
  fi
done

# IDENTITY, not just cardinality. `>= N` is satisfied by ANY member, so a scanner that lost the
# ExecStartPre extraction or the `command -v doppler` spelling still clears every floor. Pin the
# members the four scoping decisions are ABOUT, by name.
_pin_seen() {
  if grep -qE "^  UNIT: +$2" "$CONTROL_OUT"; then
    pass "scan saw $1"
  else
    fail "scan did NOT see $1 — the extraction for this shape is gone" \
      "$(grep -cE '^  UNIT:' "$CONTROL_OUT") units enumerated in total"
  fi
}
# Scoping decision 1: ExecStartPre injected by shell assignment (inngest-bootstrap.sh:1089).
_pin_seen "the ExecStartPre flip-guard injected via FLIP_GUARD_LINE" \
  'inngest-bootstrap\.sh\[FLIP_GUARD_LINE\]'
# Scoping decision 2: units that never contain the literal `doppler run`.
_pin_seen "cron-egress-firewall.service (resolved-binary spelling)" 'cron-egress-firewall\.service'
_pin_seen "container-restart-monitor.service (resolved-binary spelling)" \
  'container-restart-monitor\.service'
_pin_seen "the web-host vector unit from soleur-host-bootstrap.sh (heredoc surface)" \
  'soleur-vector-install'
# The unit this change is about.
_pin_seen "inngest-cutover-flip.service" 'inngest-cutover-flip\.service'

# THE JOIN IS LOAD-BEARING. The flip unit's bound lives ENTIRELY on continuation lines; without
# CONT_RE the scanner reads it as unbounded and every row below is meaningless. Assert the
# scanner's own verdict on that unit, not just that it was seen.
if grep -qE '^  UNIT: +inngest-cutover-flip\.service +surface=service +bound=True' "$CONTROL_OUT"
then
  pass "systemd line continuations are joined: the flip unit's multi-line bound is DETECTED"
else
  fail "the flip unit reads as UNBOUNDED — CONT_RE is not joining continuations, so every mutation row pins nothing" \
    "$(grep -E '^  UNIT: +inngest-cutover-flip' "$CONTROL_OUT")"
fi

# Known false positives, each a must-PASS: their targets are vendor binaries, not repo scripts
# with an exec seam, so they must be SEEN but must NOT enter the bound-required population.
_pin_fp() {
  if ! grep -qE "^  UNIT: +$2" "$CONTROL_OUT"; then
    fail "FP pin: $1 was not even enumerated"
    return 0
  fi
  # The POPULATION line is printed directly under its unit; -A1 is the association.
  if grep -A1 -E "^  UNIT: +$2" "$CONTROL_OUT" | grep -q 'POPULATION'; then
    fail "FP pin: $1 entered the bound-required population (false positive)"
  else
    pass "FP pin: $1 is enumerated but not bound-required"
  fi
}
_pin_fp "inngest-server.service (\`inngest start\`, not a repo script)" 'inngest-server\.service'
_pin_fp "inngest-redis.service (redis-server)" 'inngest-redis\.service'
_pin_fp "the inngest-host vector unit" 'vector\.service'
_pin_fp "the web-host vector unit" 'soleur-vector-install'

# ── mutation battery ──────────────────────────────────────────────────────────────────────────
echo ""
echo "--- mutation battery: each row must independently drive RED, attributed ---"

expect_red() {
  # expect_red <label> <attribution-substring> <mutate-fn>
  local label="$1" attrib="$2" mutate_fn="$3"
  local sbx; sbx="$(fresh_sbx mut)"
  copy_scan_tree "$FROZEN_ROOT" "$sbx"
  if ! python3 "$SCANNER" "$sbx" >/dev/null 2>&1; then
    fail "$label: fresh copy not GREEN before mutation (latent FAIL — attribution unsafe)"
    return 0
  fi
  "$mutate_fn" "$sbx"
  # A mutation that does NOT land reports the baseline, which is indistinguishable from a pass.
  if scan_diff "$FROZEN_ROOT" "$sbx" >/dev/null 2>&1; then
    fail "$label: mutation did not change the tree (it pins nothing)"
    return 0
  fi
  local out rc
  out="$(python3 "$SCANNER" "$sbx" 2>&1)" && rc=0 || rc=$?
  if [[ "$rc" -eq 0 ]]; then
    fail "$label: guard stayed GREEN on the mutated tree (VACUOUS)"
    return 0
  fi
  if grep -qF "$attrib" <<<"$out"; then
    pass "$label (RED rc=$rc, attributed)"
  else
    fail "$label: RED (rc=$rc) not attributed to '$attrib' — could be a pre-existing latent FAIL" \
      "$(grep -E 'FINDING|_FAIL' <<<"$out" | head -3)"
  fi
}

expect_green() {
  local label="$1" mutate_fn="$2"
  local sbx; sbx="$(fresh_sbx grn)"
  copy_scan_tree "$FROZEN_ROOT" "$sbx"
  "$mutate_fn" "$sbx"
  if scan_diff "$FROZEN_ROOT" "$sbx" >/dev/null 2>&1; then
    fail "$label: mutation did not change the tree (the GREEN pin is vacuous)"
    return 0
  fi
  local out rc
  out="$(python3 "$SCANNER" "$sbx" 2>&1)" && rc=0 || rc=$?
  if [[ "$rc" -eq 0 ]]; then
    pass "$label (stayed GREEN)"
  else
    fail "$label: guard went RED (false positive, rc=$rc)" \
      "$(grep -E 'FINDING|_FAIL' <<<"$out" | head -3)"
  fi
}

FLIPU="inngest-cutover-flip.service"

# R1 — the flip unit loses its bound entirely.
r1() { sed -i '/^  --only-secrets /d' "$1/$FLIPU"; }
expect_red "R1 --only-secrets dropped from the flip unit" \
  "FINDING unit=$FLIPU reason=no --only-secrets bound" r1

# R2 — a SECOND member: a new doppler-run unit whose target has an exec seam and no bound. The
# one-member population is the shape where the guard only knows about the unit it shipped with.
# Written as ExecStartPre= so this row also covers scoping decision 1 end-to-end.
r2() {
  cat > "$1/r2-seam.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
"$R2_SEAM_CMD" --emit
SH
  cat > "$1/r2-newunit.service" <<'UNIT'
[Unit]
Description=R2 fixture: doppler-run unit with an exec-seam target and no bound
[Service]
Type=oneshot
ExecStartPre=/usr/bin/doppler run --config prd -- /usr/local/bin/r2-seam.sh
ExecStart=/bin/true
UNIT
}
expect_red "R2 new doppler-run ExecStartPre unit with an exec-seam script and no bound" \
  "FINDING unit=r2-newunit.service reason=no --only-secrets bound" r2

# R3 — a name removed from an AUTHORED list while its script demonstrably reads that secret. This
# is the row covering the residual `--no-exit-on-missing-only-secrets` introduces, which is
# otherwise SILENT at run time. It checks the authored list against a LOWER BOUND of names the
# script provably reads; it is not, and cannot be, a complete derivation.
r3() { sed -i '/^  --only-secrets INNGEST_REDIS_PASSWORD /d' "$1/$FLIPU"; }
expect_red "R3 one name removed from the list while the script still reads it" \
  "READ_SET_FAIL unit=$FLIPU missing-from-only-secrets=INNGEST_REDIS_PASSWORD" r3

# R4 — the flag moved AFTER the `--`, where it is an argument to the child command rather than a
# `doppler run` flag. Textually present, semantically absent: the whole config is still injected.
r4() {
  python3 - "$1/$FLIPU" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p).read()
s = re.sub(r'^  --only-secrets \w+ \\\n', '', s, flags=re.M)
s = s.replace('  -- /usr/local/bin/inngest-cutover-flip.sh',
              '  -- /usr/local/bin/inngest-cutover-flip.sh --only-secrets INNGEST_CUTOVER_FLIP')
open(p, 'w').write(s)
PY
}
expect_red "R4 --only-secrets moved after the \`--\` (child argument, not a doppler flag)" \
  'reason=--only-secrets sits AFTER the `--` separator' r4

# R5 — the scan matches zero units on one surface (the guard's own dispatch). Deleting the only
# .tf that carries inline unit heredocs is the cheapest way to reach a zero surface without
# touching the scanner.
r5() { rm -f "$1/server.tf"; }
expect_red "R5 scan matches zero units on the tf-heredoc surface (per-surface floor)" \
  "SURFACE_FLOOR_FAIL surface=tf-heredoc" r5

# R6 — the list replaced with the empty string. `--only-secrets` is still textually present.
r6() {
  python3 - "$1/$FLIPU" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p).read()
s = s.replace('  --only-secrets INNGEST_CUTOVER_FLIP \\\n', '  --only-secrets "" \\\n')
s = re.sub(r'^  --only-secrets INNGEST_REDIS_PASSWORD \\\n', '', s, flags=re.M)
open(p, 'w').write(s)
PY
}
expect_red "R6 secret list replaced with the empty string" \
  'reason=--only-secrets carries an EMPTY value' r6

# ── scanner-side mutations (rows whose system under test is the ack list / the floor) ──────────
expect_red_scanner() {
  # expect_red_scanner <label> <attribution-substring> <program>
  local label="$1" attrib="$2" prog="$3"
  local mut="$TMPROOT/scanner.mut.py"
  cp "$SCANNER" "$mut"
  python3 - "$mut" "$prog" <<'PY'
import re, sys
p, prog = sys.argv[1], sys.argv[2]
s = open(p).read()
ENTRY = r"    'container-restart-monitor\.service':\n(?:        .*\n)+"
if prog == 'drop-ack-entry':
    # Remove the ack entry AND lower the pinned cardinality, so the cardinality pin cannot be what
    # reds — this row must be carried by the now-unacked unbounded unit itself.
    s = re.sub(ENTRY, '', s)
    s = s.replace('ACK_CARDINALITY = 7', 'ACK_CARDINALITY = 6')
elif prog == 'drop-ack-entry-only':
    s = re.sub(ENTRY, '', s)
else:
    raise SystemExit('unknown program %s' % prog)
open(p, 'w').write(s)
PY
  if cmp -s "$SCANNER" "$mut"; then
    fail "$label: scanner mutation did not land (it pins nothing)"
    return 0
  fi
  local out rc
  out="$(python3 "$mut" "$FROZEN_ROOT" 2>&1)" && rc=0 || rc=$?
  if [[ "$rc" -eq 0 ]]; then
    fail "$label: guard stayed GREEN with the mutated scanner (VACUOUS)"
    return 0
  fi
  if grep -qF "$attrib" <<<"$out"; then
    pass "$label (RED rc=$rc, attributed)"
  else
    fail "$label: RED (rc=$rc) not attributed to '$attrib'" \
      "$(grep -E 'FINDING|_FAIL' <<<"$out" | head -3)"
  fi
}

# R7a — an ack entry removed WITHOUT bounding its unit: the unit becomes an unacked violation.
expect_red_scanner "R7a ack entry removed without bounding its unit" \
  "FINDING unit=container-restart-monitor.service reason=no --only-secrets bound" 'drop-ack-entry'
# R7b — the CARDINALITY row proper: the pin refuses a silent change to the escape hatch's size.
expect_red_scanner "R7b ack cardinality pin (a silent ack edit cannot open a hole)" \
  "ACK_FAIL ack_cardinality=6 expected=7" 'drop-ack-entry-only'

# ── harness rows ──────────────────────────────────────────────────────────────────────────────
echo ""
echo "--- harness rows ---"

# H1 — a \n-ESCAPED unit inside a `.tf` heredoc. Terraform inline arrays are \n-escaped
# SINGLE-LINE strings; a scanner without the unescape reads one line, matches nothing and fails
# OPEN. Without this row, R2 and R5 are both satisfiable by a scanner that misses .tf entirely.
h1() {
  cat > "$1/h1-seam.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
"$H1_SEAM_CMD" --go
SH
  cat > "$1/h1-fixture.tf" <<'TF'
resource "null_resource" "h1_fixture" {
  provisioner "remote-exec" {
    inline = [
      "cat > /etc/systemd/system/h1-escaped.service <<'EOF'\n[Unit]\nDescription=H1 tf-heredoc fixture\n\n[Service]\nType=oneshot\nExecStart=/usr/bin/doppler run --config prd -- /usr/local/bin/h1-seam.sh\nEOF",
    ]
  }
}
TF
}
expect_red "H1 escaped unbounded unit inside a .tf heredoc (the surface already burned on)" \
  "FINDING unit=h1-escaped.service reason=no --only-secrets bound" h1

# H2 — remove the per-surface floor assertion itself. Two arms, because a deleted floor makes the
# scanner GREENER, not redder: the ANTI-VACUITY pin (ADR-193) is the source pin in arm (a), and
# arm (b) proves the floor was what caught R5 in the first place.
H2_MUT="$TMPROOT/scanner.nofloor.py"
cp "$SCANNER" "$H2_MUT"
python3 - "$H2_MUT" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p).read()
s = re.sub(r'    # --- BEGIN PER-SURFACE FLOOR.*?    # --- END PER-SURFACE FLOOR ---\n', '', s,
           flags=re.S)
open(p, 'w').write(s)
PY
if cmp -s "$SCANNER" "$H2_MUT"; then
  fail "H2: floor-removal mutation did not land (both arms below pin nothing)"
else
  # Arm (a) — the anti-vacuity source pin: the floor construct must be present in the scanner.
  if grep -qF 'SURFACE_FLOOR_FAIL surface=%s' "$SCANNER" \
     && grep -qF 'MIN_UNITS_BY_SURFACE.items()' "$SCANNER"; then
    if grep -qF 'MIN_UNITS_BY_SURFACE.items()' "$H2_MUT"; then
      fail "H2a: the anti-vacuity source pin does not notice a deleted floor assertion"
    else
      pass "H2a anti-vacuity (ADR-193): deleting the per-surface floor assertion reds this pin"
    fi
  else
    fail "H2a: the per-surface floor construct is missing from the scanner"
  fi
  # Arm (b) — positive control: with the floor gone, R5's zero-unit tree goes GREEN, which is what
  # makes arm (a) worth having.
  _h2sbx="$(fresh_sbx h2)"
  copy_scan_tree "$FROZEN_ROOT" "$_h2sbx"
  rm -f "$_h2sbx/server.tf"
  if python3 "$H2_MUT" "$_h2sbx" >/dev/null 2>&1; then
    pass "H2b positive control: without the floor, a zero-unit surface passes silently"
  else
    fail "H2b positive control did not reproduce — R5's RED may come from something else"
  fi
fi

# H3 — must-PASS non-canonical: the conditional `command -v doppler` wrap with `--only-secrets`
# inside the exec arm. The contract is the BOUND, not one spelling.
h3() {
  cat > "$1/h3-seam.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
H3_SEAM_CMD="${H3_SEAM_CMD:-/bin/true}"
"$H3_SEAM_CMD" --go "$H3_FIXTURE_SECRET"
SH
  cat > "$1/h3-noncanonical.service" <<'UNIT'
[Unit]
Description=H3 fixture: conditional command -v doppler wrap, bound inside the exec arm
[Service]
Type=oneshot
ExecStart=/bin/sh -c 'D="$(command -v doppler || true)"; if [ -n "$D" ] && [ -n "$DOPPLER_TOKEN" ]; then exec "$D" run --project soleur --config prd --only-secrets H3_FIXTURE_SECRET -- /usr/local/bin/h3-seam.sh; else exec /usr/local/bin/h3-seam.sh; fi'
UNIT
}
expect_green "H3 non-canonical \`command -v doppler\` wrap WITH a bound in the exec arm" h3

# H4 — scoping decision 3: a `runcmd` doppler invocation is NOT flagged. The boot isolation
# self-check at cloud-init-inngest.yml:604-611 must see all names; demanding a bound there would
# self-defeat the provision-time control this guard is the runtime half of.
h4() {
  python3 - "$1/cloud-init.yml" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
s = s.replace('runcmd:',
              'runcmd:\n  - doppler run --config prd -- /usr/local/bin/container-restart-monitor.sh',
              1)
open(p, 'w').write(s)
PY
}
expect_green "H4 runcmd doppler invocation is NOT flagged (boot self-check must see all names)" h4

# ── suite-level anti-vacuity floor ────────────────────────────────────────────────────────────
# The sole merge gate is the exit code below, and it reads FAIL alone — so deleting every
# expect_red/expect_green invocation would report FAIL=0 and exit 0. A FLOOR, not equality: bump
# it deliberately when adding assertions; NEVER lower it to make a run pass.
TOTAL=$((PASS + FAIL))
MIN_ASSERTIONS=25
[[ "$PASS" -ge "$MIN_ASSERTIONS" ]] || \
  fail "assertion count $PASS < floor $MIN_ASSERTIONS — the battery silently stopped running" \
    "an assertion was deleted or an early return skipped a block; this is not a count to lower"

echo ""
echo "=== doppler-injection-bound: Results: $PASS/$TOTAL passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]] || exit 1
