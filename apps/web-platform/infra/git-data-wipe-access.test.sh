#!/usr/bin/env bash
#
# git-data-wipe-access.test.sh — the census of the `wipe` job of .github/workflows/git-data-cutover.yml and of its
# notify words (#10138 / #6897, ADR-239 DL-2, ADR-241). Plan Phase 4/5 and the Guard Contract (Guards 1-8).
#
# WHAT IT IS. The wipe-specific half of the workflow census. The cross-job rows (job set, mode options on the
# cutover side, N-jobkeys, N-secrets) live in git-data-cutover-access.test.sh. Here: (1) a structural census of
# the wipe job parsed from YAML (exact-string pins, derived populations with live-count floors); (2) MUTANTS of a
# COPY of the workflow, the two local actions and the helper, each asserted to have LANDED (diff lines) before the
# named row is required RED; (3) the REAL `run:` text of the W1 confirm step, of the cutover confirm step and of
# the notify body, EXECUTED under bash with synthesized env; (4) a step-by-step SIMULATOR that runs the real
# `run:` text of the whole wipe job under PATH shims (a Hetzner state machine, doppler, gh, date, env), logging
# every call into one sequenced stream, so order, markers, epochs and token containment are observed, not grepped.
# The expression engine, census, mutator and simulator are one embedded python module (wfsim.py).
#
# Duplication note: the Hetzner `curl` shim is a trimmed copy of the one in git-data-wipe.test.sh, and
# assert_fixture_dir / the instrument self-test are copies of the canonical forms (the old suites do the same).
#
# CLO forbidden-phrase list (Guard 8), widened: erased, wiped, secure(ly), no copies/snapshots/backups, retention closed/ended,
# retention_end, Art. 17 satisfied/compliant, holds no personal data, volume/store (is) empty, irrecoverable, unrecoverable,
# permanently. No step line, notify word or executed summary of the wipe job may contain any of them (only the exact PA-36(f)
# standing sentence is whitelisted); the only claim is that the DEVICE was deleted at (or is absent from) the provider API.
#
# Round 2 (review panel): the fail-closed gates are driven on their NEGATIVE paths (section H: bad origin runs, a rollback after
# the stamp, a boot verdict that is not ok, a detach/attach/detach history, the listing mode), each with a one-line-edit mutant
# that must reach the delete; the workflow-to-script environment contract of the W10 host read is derived from the script and
# EXECUTED against the real git-data-cutover.sh (section I); the copied bridge / key-fetch / ssh_config steps are pinned equal to
# the cutover job's and the ssh_config body is executed (section I); step-level keys and env names are allow-listed.
#
# Platform behaviour (outputs of a cancelled or timed-out step) cannot be observed offline: the simulator keeps
# output files of a killed/cancelled step and the rows say so; the owner confirms on the first wipe_check run.
#
# Seams of the SUITE (not of any script under test): GDWA_WORKFLOW. Run: bash apps/web-platform/infra/git-data-wipe-access.test.sh
# Presence under apps/web-platform/infra/ IS registration (run-registered-suites.sh derives it).

# shellcheck disable=SC2015
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/../../.." && pwd)"
WF="${GDWA_WORKFLOW:-$ROOT/.github/workflows/git-data-cutover.yml}"
LOADER="$ROOT/.github/actions/infra-credentials/action.yml"
BRIDGE="$ROOT/.github/actions/cf-tunnel-ssh-bridge/action.yml"
HELPER="$DIR/git-data-wipe.sh"
LIB="$ROOT/scripts/lib/git-data-wipe-runs.sh"
HOST_ASSERT="$DIR/git-data-wipe-assert.sh"
HOST_VERB="$DIR/git-data-cutover.sh"
PRECHECK="$DIR/git-data-flag-precheck.sh"
BOOT_LIB="$ROOT/scripts/lib/git-data-boot-signal-poll.sh"
RUNBOOK="$ROOT/knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md"

passes=0; fails=0; MUTANTS_RUN=0; SIMS_RUN=0
FAILURES=()
pass() { passes=$((passes + 1)); printf '  ok   %s\n' "$1"; }
fail() { FAILURES+=("$1"); fails=$((fails + 1)); printf '  FAIL %s\n       %s\n' "$1" "${2:-}"; }

# Instrument self-test (ADR-193): drive both helpers once in a subshell and require both counters to move.
_st="$( (pass x >/dev/null; fail y >/dev/null; printf '%s %s %s' "$passes" "$fails" "${#FAILURES[@]}") )"
if [ "$_st" != "1 1 1" ]; then
  printf 'FAIL INSTRUMENT: pass()/fail() self-test read "%s", expected "1 1 1"\n' "$_st" >&2; exit 1
fi

for f in "$WF" "$LOADER" "$BRIDGE" "$HELPER" "$LIB" "$HOST_ASSERT" "$HOST_VERB" "$PRECHECK" "$BOOT_LIB" "$ROOT/scripts/lib/bearer-curl.sh"; do
  [ -f "$f" ] || { printf 'FAIL SETUP: %s not found\n' "$f" >&2; exit 1; }
done
for tool in python3 jq xargs; do
  command -v "$tool" >/dev/null 2>&1 || { printf 'FAIL SETUP: %s unavailable\n' "$tool" >&2; exit 1; }
done
python3 -c 'import yaml' 2>/dev/null || { printf 'FAIL SETUP: python3 yaml module unavailable\n' >&2; exit 1; }

# Canonical copy of plugins/soleur/test/test-helpers.sh's guard (the fixture-dir-operand-assert suite pins every
# tracked copy byte-identical). Executed as a statement before writes under a caller-supplied root.
assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY; git -C "" would operate on %s\n' "$PWD" >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}

T="$(mktemp -d "${TMPDIR}/gdwa-access.XXXXXX")" || { printf 'FAIL SETUP: mktemp\n' >&2; exit 1; }
_REACHED_VERDICT=""; _rc=0
trap '_rc=$?; rm -rf "$T"; if [ "$_rc" -eq 0 ] && [ -z "$_REACHED_VERDICT" ]; then printf "FAIL: suite exited 0 before its verdict\n" >&2; exit 1; fi' EXIT
assert_fixture_dir "$T"
mkdir -p "$T/cz" "$T/mut" "$T/sim" "$T/specs" "$T/cases" || { printf 'FAIL SETUP: mkdir\n' >&2; exit 1; }

printf '\n=== git-data wipe job census (plan Phase 4/5, Guard Contract 1-8) ===\n\n'

MUTANT_FLOOR=181
cat > "$T/wfsim.py" <<'PYEOF'
#!/usr/bin/env python3
# wfsim: a tiny GitHub-Actions expression engine, the wipe-job census, a step-by-step simulator that runs the
# REAL `run:` text of the workflow under PATH shims, and a runner for the notify job's real body.
# This file is written by git-data-wipe-access.test.sh and driven only by it.
import sys, os, re, json, subprocess, shutil, stat, time

try:
    import yaml
except ImportError:
    print("FAIL SETUP: python3 yaml module unavailable", file=sys.stderr); sys.exit(1)
YLOADER = getattr(yaml, "CSafeLoader", yaml.SafeLoader)


def load_yaml(path):
    with open(path) as fh:
        return yaml.load(fh.read(), Loader=YLOADER) or {}


# ---------------------------------------------------------------------------------------------------------
# expression engine (the subset the workflow uses: ctx paths, strings, == != && || ! ( ), format(), status fns)
# ---------------------------------------------------------------------------------------------------------
TOKRE = re.compile(r"\s*(?:('(?:[^']|'')*')|(\d+(?:\.\d+)?)|(==|!=|&&|\|\||[!(),])|([A-Za-z_][\w-]*(?:\.[\w-]+|\[[^\]]*\])*))")
STATUS_RE = re.compile(r"\b(success|failure|always|cancelled)\s*\(")


def tostr(v):
    if v is None:
        return ""
    if v is True:
        return "true"
    if v is False:
        return "false"
    if isinstance(v, float) and v == int(v):
        return str(int(v))
    return str(v)


def truthy(v):
    if v is None or v is False:
        return False
    if isinstance(v, (int, float)) and not isinstance(v, bool):
        return v != 0
    if isinstance(v, str):
        return v != ""
    return True


def eqv(a, b):
    if a is None:
        a = ""
    if b is None:
        b = ""
    if isinstance(a, bool) or isinstance(b, bool):
        return tostr(a).lower() == tostr(b).lower()
    return tostr(a).lower() == tostr(b).lower()


class Ev:
    def __init__(self, text, ctx, state):
        self.text = text
        self.ctx = ctx
        self.state = state
        self.toks = []
        pos = 0
        text = text.strip()
        while pos < len(text):
            m = TOKRE.match(text, pos)
            if not m or m.end() == pos:
                raise ValueError("expression token error at %r in %r" % (text[pos:pos + 20], text))
            for i, g in enumerate(m.groups()):
                if g is not None:
                    self.toks.append((i, g)); break
            pos = m.end()
        self.i = 0

    def peek(self):
        return self.toks[self.i] if self.i < len(self.toks) else (None, None)

    def take(self):
        t = self.peek(); self.i += 1; return t

    def parse(self):
        v = self.p_or()
        if self.i != len(self.toks):
            raise ValueError("trailing tokens in %r" % self.text)
        return v

    def p_or(self):
        v = self.p_and()
        while self.peek() == (2, "||"):
            self.take()
            r = self.p_and()
            v = v if truthy(v) else r
        return v

    def p_and(self):
        v = self.p_eq()
        while self.peek() == (2, "&&"):
            self.take()
            r = self.p_eq()
            v = r if truthy(v) else v
        return v

    def p_eq(self):
        v = self.p_not()
        while self.peek() in ((2, "=="), (2, "!=")):
            op = self.take()[1]
            r = self.p_not()
            e = eqv(v, r)
            v = e if op == "==" else (not e)
        return v

    def p_not(self):
        if self.peek() == (2, "!"):
            self.take()
            return not truthy(self.p_not())
        return self.p_prim()

    def p_prim(self):
        k, g = self.take()
        if k == 2 and g == "(":
            v = self.p_or()
            if self.take() != (2, ")"):
                raise ValueError("missing ) in %r" % self.text)
            return v
        if k == 0:
            return g[1:-1].replace("''", "'")
        if k == 1:
            return float(g) if "." in g else int(g)
        if k == 3:
            if self.peek() == (2, "("):
                self.take()
                args = []
                if self.peek() != (2, ")"):
                    args.append(self.p_or())
                    while self.peek() == (2, ","):
                        self.take(); args.append(self.p_or())
                if self.take() != (2, ")"):
                    raise ValueError("missing ) after call in %r" % self.text)
                return self.call(g, args)
            return self.lookup(g)
        raise ValueError("unexpected token %r in %r" % (g, self.text))

    def call(self, name, args):
        n = name.lower()
        st = self.state or {}
        if n == "always":
            return True
        if n == "success":
            return not st.get("failed") and not st.get("cancelled")
        if n == "failure":
            return bool(st.get("failed"))
        if n == "cancelled":
            return bool(st.get("cancelled"))
        if n == "format":
            s = tostr(args[0])
            return re.sub(r"\{(\d+)\}", lambda m: tostr(args[1 + int(m.group(1))]) if 1 + int(m.group(1)) < len(args) else "", s)
        if n == "contains":
            return tostr(args[1]).lower() in tostr(args[0]).lower()
        if n == "startswith":
            return tostr(args[0]).lower().startswith(tostr(args[1]).lower())
        raise ValueError("unsupported function %s" % name)

    def lookup(self, path):
        parts = re.findall(r"[^.\[\]]+", path)
        cur = self.ctx
        for p in parts:
            if isinstance(cur, dict) and p in cur:
                cur = cur[p]
            else:
                return None
        return cur


def ev(text, ctx, state=None):
    return Ev(text, ctx, state).parse()


def interp(s, ctx, state=None):
    if not isinstance(s, str):
        return s
    m = re.fullmatch(r"\s*\$\{\{(.*?)\}\}\s*", s, re.S)
    if m and s.count("${{") == 1:
        return ev(m.group(1), ctx, state)
    return re.sub(r"\$\{\{(.*?)\}\}", lambda mm: tostr(ev(mm.group(1), ctx, state)), s, flags=re.S)


def step_runs(step, ctx, state):
    cond = step.get("if")
    if cond is None:
        return not state.get("failed") and not state.get("cancelled")
    cond = tostr(cond) if not isinstance(cond, str) else cond
    v = truthy(ev(cond, ctx, state))
    if STATUS_RE.search(cond):
        return v
    return v and not state.get("failed") and not state.get("cancelled")


# ---------------------------------------------------------------------------------------------------------
# step helpers
# ---------------------------------------------------------------------------------------------------------
def skey(s):
    if s.get("id"):
        return s["id"]
    u = str(s.get("uses") or "")
    if u.startswith("actions/checkout@"):
        return "checkout"
    if u:
        return "uses:" + u.split("@")[0]
    return "anon:" + str(s.get("name") or "?")


def code_lines(run):
    """Executable lines of a run: text with whole-line comments and blank lines dropped."""
    return [l for l in (run or "").splitlines() if l.strip() and not l.lstrip().startswith("#")]


def code_text(run):
    return "\n".join(code_lines(run))


XTRACE_LINE = 'case "$-" in *x*) echo "::error::xtrace refused on a credential-bearing step (#7797)"; exit 78;; esac'


def first_statement(run):
    """The first executable statement of a run: continuation lines joined (a trailing backslash), the xtrace prologue
    line skipped. Returns (statement_text, had_prologue)."""
    lines = code_lines(run)
    had = False
    i = 0
    if lines and lines[0].strip() == XTRACE_LINE:
        had = True; i = 1
    if i >= len(lines):
        return "", had
    # the first statement spans backslash continuations and, if it opens a quote, runs on; the assignment region is
    # everything up to the first standalone `bash`, which sits on a continuation line, so joining those is enough.
    parts = [lines[i].strip()]
    while parts[-1].endswith("\\") and i + 1 < len(lines):
        i += 1
        parts[-1] = parts[-1][:-1].rstrip()
        parts.append(lines[i].strip())
    return " ".join(parts), had


CRED_NAME = re.compile(r"^(TF_VAR_.*|AWS_.*|TF_STATE_AWS_.*|DOPPLER_.*|HCLOUD.*|.*(TOKEN|SECRET|PASSWORD|PRIVATE|CREDENTIAL|API_KEY).*)$")
CRED_VAR = re.compile(r"^(tok|dt|token|secret|key|pw)$")
ASSIGN_RE = re.compile(r'(?:(?<=\s)|^)([A-Za-z_][A-Za-z0-9_]*)=("(?:[^"\\]|\\.)*"|\'[^\']*\'|[^\s"\']*)')


def envi_assignments(stmt):
    """Assignments between `env -i` and the first standalone `bash` of an exec env -i statement."""
    m = re.match(r"^exec env -i\s+(.*?)\s+bash(\s|$)", stmt)
    if not m:
        return None
    return ASSIGN_RE.findall(m.group(1))


def check_envi(stmt):
    """(ok, why) for one `exec env -i ...` statement: no credential-named assignment, no value that expands a
    credential-named variable. Order of the assignments and extra non-secret names (LC_ALL) are free."""
    a = envi_assignments(stmt)
    if a is None:
        return False, "not an exec env -i ... bash statement"
    bad = []
    for name, val in a:
        if CRED_NAME.match(name):
            bad.append("name:" + name)
        for ref in re.findall(r"\$\{?([A-Za-z_][A-Za-z0-9_]*)", val):
            if CRED_NAME.match(ref) or CRED_VAR.match(ref):
                bad.append("value:%s=$%s" % (name, ref))
    return (not bad), ",".join(bad)


ENV_PRINT_PATTERNS = [
    (re.compile(r"(^|[;&|(`]|\$\()\s*(printenv)(\s|$|[;&|)>])"), "printenv"),
    (re.compile(r"(^|[;&|(`]|\$\()\s*env\s*($|[;&|)>])"), "bare env"),
    (re.compile(r"(^|[;&|(`]|\$\()\s*set\s*($|[;&|)>])"), "bare set"),
    (re.compile(r"(^|[;&|(`]|\$\()\s*(export|declare|typeset)\s+(-[a-zA-Z]*[px][a-zA-Z]*)(\s|$|[;&|)>])"), "export/declare -p|-x"),
    (re.compile(r"(^|[;&|(`]|\$\()\s*(export|declare|typeset)\s*($|[;&|)>])"), "bare export/declare"),
    (re.compile(r"(^|[;&|(`]|\$\()\s*compgen\s+-[a-z]*e"), "compgen -e"),
    (re.compile(r"/proc/[^\s]*/environ"), "/proc environ"),
]


def env_printers(run):
    hits = []
    for l in code_lines(run):
        for rx, label in ENV_PRINT_PATTERNS:
            if rx.search(l):
                hits.append(label + ": " + l.strip()[:80])
    return hits


# ---------------------------------------------------------------------------------------------------------
# the census
# ---------------------------------------------------------------------------------------------------------
ORDER = ["wipe_confirm", "checkout", "wipe_doppler_install", "wipe_flag_precheck", "wipe_origin_check", "wipe_identity",
         "wipe_boot_read", "wipe_bridge", "wipe_key_fetch", "wipe_ssh_config", "wipe_host_assert", "wipe_flag_reread",
         "wipe_loader", "wipe_detach_gate", "wipe_detach", "wipe_post_detach_read", "wipe_reread", "wipe_delete_gate",
         "wipe_delete", "wipe_readback", "wipe_teardown"]
GUARD2_CHAIN = ["wipe_identity", "wipe_boot_read", "wipe_host_assert", "wipe_flag_reread", "wipe_loader", "wipe_detach_gate",
                "wipe_detach", "wipe_post_detach_read", "wipe_reread", "wipe_delete_gate", "wipe_delete", "wipe_readback"]
POST_LOADER = ["wipe_detach_gate", "wipe_detach", "wipe_post_detach_read", "wipe_reread", "wipe_delete_gate", "wipe_delete",
               "wipe_readback", "wipe_teardown"]
MODE_IS_WIPE = "steps.wipe_confirm.outputs.mode == 'wipe'"
DETACHED_FINISH = "(steps.wipe_confirm.outputs.mode == 'wipe_finish' && steps.wipe_identity.outputs.volume_state == 'detached')"
IF_EXACT = {
    "wipe_confirm": None, "checkout": None, "wipe_doppler_install": None, "wipe_flag_precheck": None,
    "wipe_origin_check": "steps.wipe_confirm.outputs.mode == 'wipe_finish'",
    "wipe_identity": None,
    "wipe_boot_read": "steps.wipe_confirm.outputs.mode != 'wipe_finish'",
    "wipe_bridge": "steps.wipe_confirm.outputs.mode != 'wipe_finish' || steps.wipe_identity.outputs.volume_state == 'detached'",
    "wipe_key_fetch": "steps.wipe_confirm.outputs.mode != 'wipe_finish' || steps.wipe_identity.outputs.volume_state == 'detached'",
    "wipe_ssh_config": "steps.wipe_confirm.outputs.mode != 'wipe_finish' || steps.wipe_identity.outputs.volume_state == 'detached'",
    "wipe_host_assert": "steps.wipe_confirm.outputs.mode != 'wipe_finish' || steps.wipe_identity.outputs.volume_state == 'detached'",
    "wipe_flag_reread": "steps.wipe_confirm.outputs.mode != 'wipe_check'",
    "wipe_loader": MODE_IS_WIPE + " || " + DETACHED_FINISH,
    "wipe_detach_gate": MODE_IS_WIPE,
    "wipe_detach": MODE_IS_WIPE,
    "wipe_post_detach_read": MODE_IS_WIPE + " || " + DETACHED_FINISH,
    "wipe_reread": MODE_IS_WIPE + " || " + DETACHED_FINISH,
    "wipe_delete_gate": MODE_IS_WIPE + " || " + DETACHED_FINISH,
    "wipe_delete": MODE_IS_WIPE + " || " + DETACHED_FINISH,
    "wipe_readback": MODE_IS_WIPE + " || steps.wipe_confirm.outputs.mode == 'wipe_finish'",
    "wipe_teardown": "always()",
}
# run matrix: scenario -> set of step keys that must RUN (all earlier steps succeeding)
SCENARIOS = {
    "wipe": ("wipe", ""),
    "finish_detached": ("wipe_finish", "detached"),
    "finish_absent": ("wipe_finish", "absent"),
    "check": ("wipe_check", ""),
}
ALL = set(ORDER)
RUNS = {
    "wipe": ALL - {"wipe_origin_check"},
    "finish_detached": ALL - {"wipe_boot_read", "wipe_detach_gate", "wipe_detach"},
    "finish_absent": {"wipe_confirm", "checkout", "wipe_doppler_install", "wipe_flag_precheck", "wipe_origin_check", "wipe_identity",
                      "wipe_flag_reread", "wipe_readback", "wipe_teardown"},
    "check": {"wipe_confirm", "checkout", "wipe_doppler_install", "wipe_flag_precheck", "wipe_identity", "wipe_boot_read",
              "wipe_bridge", "wipe_key_fetch", "wipe_ssh_config", "wipe_host_assert", "wipe_teardown"},
}
CUTOVER_IF = "inputs.mode != 'wipe' && inputs.mode != 'wipe_finish' && inputs.mode != 'wipe_check'"
WIPE_IF = "inputs.mode == 'wipe' || inputs.mode == 'wipe_finish' || inputs.mode == 'wipe_check'"
RUN_NAME = "${{ (inputs.mode == 'wipe' || inputs.mode == 'wipe_finish' || inputs.mode == 'wipe_check') && format('git-data {0} {1}', inputs.mode, inputs.volume_id) || format('git-data {0}', inputs.mode) }}"
MODES = ["proof", "flip", "rollback", "unfreeze", "redeploy", "wipe", "wipe_finish", "wipe_check"]
NOTIFY_MODES = MODES + ["wipe_unknown"]
PHASE_CHAIN = "${{ steps.wipe_readback.outputs.phase || steps.wipe_delete.outputs.phase || steps.wipe_delete_gate.outputs.phase || steps.wipe_detach.outputs.phase || steps.wipe_detach_gate.outputs.phase }}"
NIF = "always() && (((needs.cutover.result == 'failure' || needs.cutover.result == 'cancelled') && needs.cutover.outputs.started != 'false') || ((needs.wipe.result == 'failure' || needs.wipe.result == 'cancelled') && needs.wipe.outputs.started != 'false'))"
# The CLO ruling's list (Guard 8), widened (review F-CLO-9). One source for the census, the executed-output scans and the
# must-fire fixtures; the bash side reads the same text out of this module (FORBID_ERE), never a second copy.
FORBIDDEN_SRC = r"\b(erased|wiped|secure(ly)?|no (copies|snapshots|backups)|retention (closed|ended)|retention_end|art\.? ?17 (satisfied|compliant)|holds no personal data|(volume|store) (is )?empty|irrecoverabl\w*|unrecoverable|permanently)\b"
FORBIDDEN = re.compile(FORBIDDEN_SRC, re.I)
# The ONE sentence that is whitelisted: the standing non-claim of the W12 step (PA-36(f)). It is removed (as exact text)
# from a line before the scan; a variant of it is scanned like any other text.
STANDING = "This run does not address provider-side snapshot or backup retention of the volume (Art. 30 PA-36(f), not measured), residue on the served store, or any copy held by someone with prior access."
SECRET_RE = re.compile(r"secrets\.([A-Za-z0-9_]+)")
ECHO_VARS_ALLOWED = {"DOPPLER_CLI_SHA256", "rrc", "cls", "MODE", "RUN_ATTEMPT", "want", "v", "gv", "would", "W3_WOULD", "line", "ORIGIN_RUN", "VOLUME_ID", "reason", "row_epoch",
                     "origin_epoch", "d", "w4", "w7", "srr", "ans", "W3_VARIANT", "verdict", "variant", "sv", "sw", "srv_created", "row_at", "RUN_ID", "RUN_ACTOR", "EPOCHSECONDS", "WIPE_VOLUME_ID", "WIPE_SERVER_ID", "WIPE_LUKS_VOLUME_ID",
                     "WIPE_ROW_EPOCH", "srr_word"}
# The names the wipe run expands in echo/printf output are pinned. A credential-holding variable (`tok`, `dt`) is NOT on the
# list: `printf '::add-mask::%s\n' "$tok"` is excluded by the add-mask scan, and `echo "$tok"` is therefore RED.
STEP_KEYS_RUN = {"name", "id", "if", "env", "run"}
STEP_KEYS_USES = {"name", "id", "if", "uses", "with"}
ENV_DENY = re.compile(r"^(BASH_ENV|ENV|LD_.*|PATH|SHELLOPTS|BASHOPTS|PS4|PROMPT_COMMAND|IFS|BASH_FUNC_.*|BASH_XTRACEFD|CDPATH|GLOBIGNORE)$")
XT2 = re.compile(r'case "\$-" in\n  \*x\*\) echo "::error title=git-data-cutover key::refusing to run under xtrace"; exit 78 ;;\nesac\n')
FINISH_CMD_ORIGIN = 'finish_cmd_origin="gh workflow run git-data-cutover.yml --ref main -f mode=wipe_finish -f confirm=WIPE-FINISH-GIT-DATA -f volume_id=${vid} -f origin_run=ORIGIN_RUN_ID"'
FINISH_CMD = 'finish_cmd_here="gh workflow run git-data-cutover.yml --ref main -f mode=wipe_finish -f confirm=WIPE-FINISH-GIT-DATA -f volume_id=${vid} -f origin_run=${orig}"'


class Census:
    def __init__(self, a):
        self.a = a
        self.rows = []

    def check(self, name, cond, detail=""):
        d = str(detail).replace("\t", " ").replace("\n", " ")[:300]
        self.rows.append(("ok" if cond else "FAIL", name, d))

    def run(self):
        a = self.a
        wf = load_yaml(a["wf"])
        text = open(a["wf"]).read()
        loader = load_yaml(a["loader"])
        bridge = load_yaml(a["bridge"])
        loader_text = open(a["loader"]).read()
        helper_text = open(a["helper"]).read()
        libtext = open(a["lib"]).read()
        phases = a.get("phases") or []
        jobs = wf.get("jobs") or {}
        wipe = jobs.get("wipe") or {}
        steps = wipe.get("steps") or []
        enum = [skey(s) for s in steps]
        if os.environ.get("WS_STUB_ENUM"):
            # harness seam: the step enumerator returns only the named step (anti-vacuity row)
            enum = [k for k in enum if k == os.environ["WS_STUB_ENUM"]]
        by = {skey(s): s for s in steps}
        idx = {k: i for i, k in enumerate(enum)}
        c = self.check
        on = wf.get(True) or wf.get("on") or {}
        inputs = ((on.get("workflow_dispatch") or {}).get("inputs") or {}) if isinstance(on, dict) else {}

        # ---- WS: structure ---------------------------------------------------------------------------------
        c("WS-jobs: the jobs are exactly cutover, notify-failure and wipe", sorted(jobs) == ["cutover", "notify-failure", "wipe"], sorted(jobs))
        c("WS-job-keys: the wipe job carries exactly {if, runs-on, timeout-minutes, environment, concurrency, env, outputs, steps} on ubuntu-24.04 (no name override, permissions, container, services, defaults, continue-on-error, needs)",
          set(wipe) == {"if", "runs-on", "timeout-minutes", "environment", "concurrency", "env", "outputs", "steps"} and wipe.get("runs-on") == "ubuntu-24.04", sorted(wipe))
        orig_job = re.search(r"^readonly WIPE_ORIGIN_JOB=(\S+)$", libtext, re.M)
        det_step = re.search(r"^readonly WIPE_ORIGIN_DETACH_STEP=(\S+)$", libtext, re.M)
        del_step = re.search(r"^readonly WIPE_ORIGIN_DELETE_STEP=(\S+)$", libtext, re.M)
        c("WS-naming-job: the job key equals the run lib's WIPE_ORIGIN_JOB and the job has no name: override (`gh run view --json jobs` exposes the job NAME)",
          bool(orig_job) and orig_job.group(1) in jobs and "name" not in wipe, orig_job.group(1) if orig_job else None)
        dn = [skey(s) for s in steps if det_step and s.get("name") == det_step.group(1)]
        ln = [skey(s) for s in steps if del_step and s.get("name") == del_step.group(1)]
        c("WS-naming-steps: exactly one step of the wipe job has name: == the run lib's WIPE_ORIGIN_DETACH_STEP and it is the detach gate; exactly one has name: == WIPE_ORIGIN_DELETE_STEP and it is the delete gate (`gh run view --json jobs` exposes a step's NAME, not its id: any other name makes every wipe_finish origin check fail closed)",
          dn == ["wipe_detach_gate"] and ln == ["wipe_delete_gate"], (dn, ln, det_step.group(1) if det_step else None, del_step.group(1) if del_step else None))
        c("WS-wipe-if: the wipe job if: is exactly the three-mode OR; the cutover job if: is exactly the three-mode AND-of-!=",
          " ".join(str(wipe.get("if")).split()) == WIPE_IF and " ".join(str((jobs.get("cutover") or {}).get("if")).split()) == CUTOVER_IF,
          (wipe.get("if"), (jobs.get("cutover") or {}).get("if")))
        c("WS-runname: run-name is exactly the closed-pattern expression", wf.get("run-name") == RUN_NAME, wf.get("run-name"))
        titles = {}
        for m in MODES:
            titles[m] = tostr(interp(wf.get("run-name") or "", {"inputs": {"mode": m, "volume_id": "424242"}}))
        want = {m: ("git-data %s 424242" % m if m.startswith("wipe") else "git-data %s" % m) for m in MODES}
        c("WS-runname-eval: the run-name expression, EVALUATED for every mode, yields `git-data <mode> <id>` for the wipe family and `git-data <mode>` (no trailing space or id) for every other mode",
          titles == want, {k: v for k, v in titles.items() if want[k] != v})
        modes_opt = (inputs.get("mode") or {}).get("options")
        c("WS-modes: the mode input is a choice with exactly proof, flip, rollback, unfreeze, redeploy, wipe, wipe_finish, wipe_check in that order",
          modes_opt == MODES and (inputs.get("mode") or {}).get("type") == "choice", modes_opt)
        c("WS-inputs: the dispatch inputs are exactly confirm, lineage, mode, origin_run, volume_id; volume_id and origin_run are optional strings defaulting to the empty string",
          sorted(inputs) == ["confirm", "lineage", "mode", "origin_run", "volume_id"]
          and all((inputs.get(k) or {}).get("type") == "string" and (inputs.get(k) or {}).get("default") == "" and (inputs.get(k) or {}).get("required") is False for k in ("volume_id", "origin_run")),
          sorted(inputs))
        conf_desc = str((inputs.get("confirm") or {}).get("description"))
        c("WS-tokens: the confirm description names the three wipe tokens against their modes",
          all(t in conf_desc for t in ("wipe=WIPE-GIT-DATA", "wipe_finish=WIPE-FINISH-GIT-DATA", "wipe_check=WIPE-CHECK-GIT-DATA")), conf_desc[-160:])
        w1 = by.get("wipe_confirm") or {}
        w1_map = dict(re.findall(r"^\s+(wipe|wipe_finish|wipe_check)\)\s+want=\"([A-Z-]+)\" ;;$", w1.get("run") or "", re.M))
        c("WS-w1-tokens: the W1 step maps exactly wipe to WIPE-GIT-DATA, wipe_finish to WIPE-FINISH-GIT-DATA and wipe_check to WIPE-CHECK-GIT-DATA",
          w1_map == {"wipe": "WIPE-GIT-DATA", "wipe_finish": "WIPE-FINISH-GIT-DATA", "wipe_check": "WIPE-CHECK-GIT-DATA"}, w1_map)
        c("WS-order: the wipe job's steps are exactly the 21 pinned step ids, in order (set identity plus order)", enum == ORDER if not os.environ.get("WS_STUB_ENUM") else False, enum)
        c("WS-floor: the live step count is at least 21 (a floor paired with the identity row above)", len(enum) >= 21, len(enum))
        ifs = {skey(s): (" ".join(str(s["if"]).split()) if "if" in s else None) for s in steps}
        bad_if = {k: (ifs.get(k), v) for k, v in IF_EXACT.items() if ifs.get(k) != v}
        c("WS-if-exact: every step's if: is the exact pinned string (steps 5, 7-17, 18 and 19; the others carry none)", not bad_if and len(ifs) == 21, bad_if)
        # the evaluated run matrix
        sem_bad = []
        for scen, (mode, vs) in SCENARIOS.items():
            ctx = {"steps": {"wipe_confirm": {"outputs": {"mode": mode}}, "wipe_identity": {"outputs": {"volume_state": vs}}}}
            ran = set()
            for s in steps:
                try:
                    if step_runs(s, ctx, {"failed": False, "cancelled": False}):
                        ran.add(skey(s))
                except Exception as e:
                    sem_bad.append("%s:%s:%s" % (scen, skey(s), e))
            if ran != RUNS[scen]:
                sem_bad.append("%s: extra=%s missing=%s" % (scen, sorted(ran - RUNS[scen]), sorted(RUNS[scen] - ran)))
        c("WS-if-matrix: the if: strings, EVALUATED for wipe / wipe_finish (volume detached) / wipe_finish (volume absent) / wipe_check, run exactly the steps the plan table allows (finish makes no detach step run, check runs no loader, detach or delete step)", not sem_bad, sem_bad)
        surf_bad = []
        for m in (modes_opt or MODES):
            ctx = {"inputs": {"mode": m}}
            cu = truthy(ev(CUTOVER_IF_LIVE(wf), ctx, {})); wp = truthy(ev(str(wipe.get("if") or "false"), ctx, {}))
            if cu == wp:
                surf_bad.append("%s: cutover=%s wipe=%s" % (m, cu, wp))
            if wp != m.startswith("wipe"):
                surf_bad.append("%s: wipe=%s but name %s a wipe-family mode" % (m, wp, "is" if m.startswith("wipe") else "is not"))
        c("G4-surface: for EVERY mode option exactly one of the two job if: strings is true, and the wipe job starts for exactly the modes whose name begins `wipe`", not surf_bad and bool(modes_opt), surf_bad)
        timeout = wipe.get("timeout-minutes")
        w4o = re.search(r"^readonly WIPE_W4_OUTER_BOUND_SECONDS=(\d+)$", helper_text, re.M)
        w7b = re.search(r"^readonly WIPE_W7_BOUND_SECONDS=(\d+)$", helper_text, re.M)
        w10 = re.search(r"^readonly WIPE_W10B_BOUND_SECONDS=(\d+)$", helper_text, re.M)
        need = None
        if w4o and w7b and w10:
            need = 5 + -(-int(w4o.group(1)) // 60) + -(-(int(w7b.group(1)) + int(w10.group(1))) // 60) + 5
        c("WS-timeout: the wipe job timeout-minutes is exactly 30 and at least setup 5 + ceil(W4 outer bound / 60) + ceil((W7 bound + W10b bound) / 60) + tail 5 derived from the helper's pinned constants",
          timeout == 30 and need is not None and timeout >= need, (timeout, need))
        conc = wipe.get("concurrency") or {}
        env_name = wipe.get("environment")
        c("WS-conc-env: the wipe job joins concurrency group web-1-swap without cancel-in-progress and runs in environment web-platform-infra-apply",
          conc == {"group": "web-1-swap", "cancel-in-progress": False} and env_name == "web-platform-infra-apply", (conc, env_name))
        c("WS-jobenv: the wipe job env is exactly {VOLUME_ID: inputs.volume_id}", wipe.get("env") == {"VOLUME_ID": "${{ inputs.volume_id }}"}, wipe.get("env"))
        c("WS-no-coe: no wipe step carries continue-on-error and exactly the teardown carries if: always()",
          not any("continue-on-error" in s for s in steps) and [skey(s) for s in steps if s.get("if") == "always()"] == ["wipe_teardown"], [skey(s) for s in steps if s.get("if") == "always()"])
        outs = wipe.get("outputs") or {}
        c("G3-outputs: the job outputs are exactly mode, started, phase, refusal with the pinned expressions (phase is a latest-first || chain)",
          outs == {"mode": "${{ steps.wipe_confirm.outputs.mode }}", "started": "${{ steps.wipe_confirm.outputs.mode != '' }}", "phase": PHASE_CHAIN,
                   "refusal": "${{ steps.wipe_identity.outputs.refusal || steps.wipe_post_detach_read.outputs.refusal }}"}, outs)
        # phase chain: evaluated, a killed run at each marker publishes the LATEST marker
        vocab_latest_first = list(reversed(phases)) if phases else []
        chain_src = ["wipe_readback", "wipe_delete", "wipe_delete_gate", "wipe_detach", "wipe_detach_gate"]
        chain_bad = []
        marks = ["detach_attempted", "detached", "delete_attempted", "delete_sent", "deleted"]
        owners = ["wipe_detach_gate", "wipe_detach", "wipe_delete_gate", "wipe_delete", "wipe_readback"]
        for k in range(1, 6):
            ctx = {"steps": {o: {"outputs": {"phase": m}} for o, m in zip(owners[:k], marks[:k])}}
            got = tostr(interp(outs.get("phase") or "", ctx, {}))
            if got != marks[k - 1]:
                chain_bad.append("after %s -> %r (want %r)" % (owners[k - 1], got, marks[k - 1]))
        # the wipe_finish identity front no longer writes a phase (a volume that was ALREADY detached says nothing about what
        # THIS run did): the chain must not read wipe_identity at all, and a stray identity phase must not leak into the output
        ctx_id = {"steps": {"wipe_identity": {"outputs": {"phase": "detached"}}}}
        if tostr(interp(outs.get("phase") or "", ctx_id, {})) != "":
            chain_bad.append("the phase chain publishes a wipe_identity phase")
        c("G3-phase-chain-eval: with the markers published in order, the phase output EVALUATES to the latest one at every stage (deleted never loses to delete_sent)", not chain_bad, chain_bad)
        c("G3-phase-vocab: the helper's `phases` vocabulary is exactly the five markers the chain owners publish, in order", phases == marks, phases)
        # which steps can publish a phase: the workflow's own marker writes plus the helper verbs that write one
        writers = set()
        for s in steps:
            r = code_text(s.get("run") or "")
            if re.search(r'echo "phase=', r) or re.search(r"git-data-wipe\.sh\"?\s+(detach|delete|readback)\b", r):
                writers.add(skey(s))
        in_chain = set(re.findall(r"steps\.([a-z_]+)\.outputs\.phase", str(outs.get("phase"))))
        c("G3-phase-writers: every step that can publish a phase (a workflow marker write, or a helper call to detach/delete/readback; the identity front publishes none) is read by the phase chain, and the chain reads nothing else",
          writers == in_chain, "writers-not-in-chain=%s chain-not-writers=%s" % (sorted(writers - in_chain), sorted(in_chain - writers)))
        helper_writes = dict()
        for fn, ph in (("do_detach", "detached"), ("do_delete", "delete_sent"), ("do_readback", "deleted")):
            m = re.search(r"^%s\(\) \{\n(.*?)^\}" % fn, helper_text, re.S | re.M)
            helper_writes[fn] = re.findall(r"gho phase (\w+)", m.group(1)) if m else None
        c("G3-helper-phase-writers: the helper publishes detached from detach, delete_sent from delete and deleted from readback and no other phase from those verbs",
          helper_writes == {"do_detach": ["detached"], "do_delete": ["delete_sent"], "do_readback": ["deleted"]}, helper_writes)
        # refusal vocabulary
        wf_ref = sorted(set(re.findall(r'refusal=(\w+)', code_text("\n".join(str(s.get("run") or "") for s in steps)))))
        c("G3-refusal: the workflow writes exactly one refusal word (store_not_serving, from the post-detach host read) and the helper writes volume_already_detached only for wipe_volume_already_detached",
          wf_ref == ["store_not_serving"] and 'if [[ "$word" == wipe_volume_already_detached ]]; then gho refusal volume_already_detached; fi' in helper_text, wf_ref)
        # ---- Guard 1 ---------------------------------------------------------------------------------------
        li = idx.get("wipe_loader")
        post = [k for k in enum if li is not None and idx[k] > li]
        c("G1-floor: the post-loader step list the census DERIVES from the live steps is non-empty (live count reported; a dispatch that derives zero steps is RED)", len(post) >= 8, "%d steps checked: %s" % (len(post), post))
        c("G1-post-set: the post-loader steps are exactly the eight pinned ids (set identity beside the count floor)", post == POST_LOADER, post)
        offenders = []
        for k in post:
            stmt, had = first_statement(by[k].get("run") or "")
            if not stmt.startswith("exec env -i "):
                offenders.append("%s: first statement %r" % (k, stmt[:60]))
            if k == "wipe_teardown" and had:
                offenders.append("wipe_teardown carries a prologue")
            if k != "wipe_teardown" and not had:
                offenders.append("%s lacks the xtrace prologue" % k)
        c("G1-exec-first: the first executable statement of EVERY post-loader run: matches ^exec env -i (the xtrace-refusal case line is the only line permitted before it; the teardown has just the exec)", not offenders and bool(post), offenders)
        envi_bad = []
        envi_n = 0
        for s in steps:
            k = skey(s)
            for l in code_text(s.get("run") or "").splitlines():
                pass
            run = s.get("run") or ""
            # every `env -i` statement in the job (exec form, helper() wrapper, host-assert call): joined continuation lines
            joined = re.sub(r"\\\n\s*", " ", code_text(run))
            for m in re.finditer(r"(?:^|[\s;(])env -i\s+(.*?)\s+bash(\s|$)", joined):
                envi_n += 1
                ok, why = check_envi("exec env -i " + m.group(1) + " bash ")
                if not ok:
                    envi_bad.append("%s: %s" % (k, why))
        c("G1-no-cred-on-envi: no env -i line of the wipe job carries a credential-named assignment (TF_VAR_*, AWS_*, TF_STATE_AWS_*, DOPPLER_*, HCLOUD*, *TOKEN*, *SECRET*...) or a value expanding a credential variable; reordering the allow-list and adding a non-secret name (LC_ALL) stay GREEN",
          not envi_bad and envi_n >= 10, "%d env -i lines checked; %s" % (envi_n, envi_bad))
        # credential flow: write token only on the detach/delete here-strings
        hc_steps = {}
        for s in steps:
            for l in code_lines(s.get("run") or ""):
                for _m in re.finditer(r"HCLOUD_TOKEN(?![A-Za-z_])", l):
                    hc_steps.setdefault(skey(s), []).append(l.strip())
        in_env = [skey(s) for s in steps if "HCLOUD_TOKEN" in json.dumps({k: v for k, v in s.items() if k in ("env", "with")}).replace("HCLOUD_TOKEN_READONLY", "")]
        c("G1-hcloud-write: HCLOUD_TOKEN (the write token) is a value source ONLY in wipe_detach and wipe_delete, each time as the here-string `<<<\"${HCLOUD_TOKEN:-}\"`, and in no env: or with: block",
          sorted(hc_steps) == ["wipe_delete", "wipe_detach"] and all(len(v) == 1 and v[0].endswith('<<<"${HCLOUD_TOKEN:-}"') for v in hc_steps.values()) and not in_env, (hc_steps, in_env))
        ro_steps = sorted({skey(s) for s in steps if re.search(r"HCLOUD_TOKEN_READONLY", code_text(s.get("run") or ""))})
        ro_ok = all(re.search(r"doppler secrets get HCLOUD_TOKEN_READONLY --plain -p soleur -c prd_terraform", code_text(by[k].get("run") or "")) for k in ro_steps)
        c("G1-hcloud-ro: HCLOUD_TOKEN_READONLY is fetched only in wipe_identity, wipe_reread and wipe_readback, each by the single doppler secrets get form",
          ro_steps == ["wipe_identity", "wipe_readback", "wipe_reread"] and ro_ok, ro_steps)
        dt = {}
        for s in steps:
            n = len(re.findall(r"secrets\.DOPPLER_TOKEN(?![A-Za-z_])", json.dumps(s, default=str)))
            if n:
                dt[skey(s)] = n
        total_dt = sum(dt.values())
        c("G1-secret-doppler-token: secrets.DOPPLER_TOKEN is bound in exactly these steps of the wipe job, once each (live total reported)",
          dt == {"wipe_identity": 1, "wipe_boot_read": 1, "wipe_bridge": 1, "wipe_reread": 1, "wipe_readback": 1} and total_dt == 5, "total=%d %s" % (total_dt, dt))
        sec = {}
        for s in steps:
            for n_ in SECRET_RE.findall(json.dumps(s, default=str)):
                sec.setdefault(n_, set()).add(skey(s))
        sec = {k: sorted(v) for k, v in sec.items()}
        c("G1-secret-map: every secrets.* name of the wipe job and the steps that bind it are pinned (INFRA_PRIVILEGED only at the loader; PRD only at the two flag steps; GIT_DATA_ROOT only at the key fetch; no flag-write, Resend or Sentry secret)",
          sec == {"DOPPLER_TOKEN": ["wipe_boot_read", "wipe_bridge", "wipe_identity", "wipe_readback", "wipe_reread"],
                  "DOPPLER_TOKEN_PRD": ["wipe_flag_precheck", "wipe_flag_reread"], "DOPPLER_TOKEN_GIT_DATA_ROOT": ["wipe_key_fetch"],
                  "DOPPLER_TOKEN_INFRA_PRIVILEGED": ["wipe_loader"], "GITHUB_TOKEN": ["wipe_flag_precheck", "wipe_origin_check"]}
          and "secrets" not in json.dumps({k: v for k, v in wipe.items() if k != "steps"}), sec)
        ld = by.get("wipe_loader") or {}
        c("G1-loader-once: the Tier-B loader is used exactly once in the job, with ONLY doppler-token-infra-privileged (bound to secrets.DOPPLER_TOKEN_INFRA_PRIVILEGED), no env: and no other input (a doppler-token-legacy input is RED)",
          [skey(s) for s in steps if s.get("uses") == "./.github/actions/infra-credentials"] == ["wipe_loader"]
          and ld.get("with") == {"doppler-token-infra-privileged": "${{ secrets.DOPPLER_TOKEN_INFRA_PRIVILEGED }}"} and "env" not in ld, (ld.get("uses"), ld.get("with")))
        c("G1-loader-pos: the loader sits directly after the W7b flag re-read and directly before the W9a detach marker",
          idx.get("wipe_flag_reread") is not None and idx.get("wipe_loader") == idx["wipe_flag_reread"] + 1 and idx.get("wipe_detach_gate") == idx.get("wipe_loader", -9) + 1, (idx.get("wipe_flag_reread"), idx.get("wipe_loader"), idx.get("wipe_detach_gate")))
        gate = code_text((by.get("wipe_detach_gate") or {}).get("run") or "")
        i_tier = gate.find('"$LOADER_SOURCE" != "tier_b"'); i_mark = gate.find('echo "phase=detach_attempted"'); i_rc = gate.find("record_check --epoch w7")
        c("G1-tier-b-gate: wipe_detach_gate asserts source == tier_b (from steps.wipe_loader.outputs.source) AFTER the W7 record check and BEFORE it writes the detach marker",
          0 <= i_rc < i_tier < i_mark and (by.get("wipe_detach_gate") or {}).get("env") == {"LOADER_SOURCE": "${{ steps.wipe_loader.outputs.source }}"}, (i_rc, i_tier, i_mark))
        uses = [(skey(s), s.get("uses")) for s in steps if s.get("uses")]
        allowed_uses = {"actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5", "./.github/actions/cf-tunnel-ssh-bridge", "./.github/actions/infra-credentials"}
        c("G1-uses-set: the wipe job's uses: set is exactly actions/checkout (pinned sha) plus the two local actions, once each; any remote uses: is RED",
          sorted(u for _, u in uses) == sorted(allowed_uses), uses)
        def lit(env):
            return (env.get("DOPPLER_CLI_VERSION"), env.get("DOPPLER_CLI_SHA256"))
        l_steps = (loader.get("runs") or {}).get("steps") or []
        l_install = next((s for s in l_steps if "Install Doppler" in str(s.get("name"))), {})
        w_install = by.get("wipe_doppler_install") or {}
        c("G1-install-literals: the inline Doppler install's version and sha256 literals equal the loader's, parsed from action.yml (and are not empty)",
          lit(l_install.get("env") or {}) == lit(w_install.get("env") or {}) and all(lit(w_install.get("env") or {})), (lit(l_install.get("env") or {}), lit(w_install.get("env") or {})))
        pr = []
        for s in steps:
            for h in env_printers(s.get("run") or ""):
                pr.append("%s: %s" % (skey(s), h))
        c("G1-no-env-print: no wipe step prints the environment (env, printenv, bare set, export -p, declare -x, compgen -e, /proc/*/environ)", not pr and len(enum) >= 21, pr)
        acts = {"loader": loader, "bridge": bridge}
        act_bad = [n for n, d in acts.items() if (d.get("runs") or {}).get("using") != "composite" or any(k in (d.get("runs") or {}) for k in ("post", "post-if", "pre", "main"))]
        c("G1-actions-composite: both local actions declare runs.using: composite and neither declares a post:, post-if:, pre: or main: hook", not act_bad, act_bad)
        mask_lines = [i for i, l in enumerate(loader_text.splitlines()) if "::add-mask::" in l and not l.lstrip().startswith("#")]
        ltl = loader_text.splitlines()
        per_line = [i for i in mask_lines if any(re.search(r"while IFS= read -r", ltl[j]) for j in range(max(0, i - 3), i))]
        c("G1-loader-mask: every ::add-mask:: of the loader sits inside a `while IFS= read -r` loop (masking per line, never one blob); live count reported", len(mask_lines) >= 2 and per_line == mask_lines, "%d mask sites, %d per-line" % (len(mask_lines), len(per_line)))
        ge = [skey(s) for s in steps if "GITHUB_ENV" in code_text(s.get("run") or "")]
        early = [k for k in ge if idx.get(k, 99) <= idx.get("wipe_boot_read", -1)]
        c("G1-no-early-github-env: no wipe step at or before wipe_boot_read writes $GITHUB_ENV, and wipe_identity and wipe_boot_read both precede the bridge", not early and idx.get("wipe_identity", 99) < idx.get("wipe_boot_read", 99) < idx.get("wipe_bridge", -1), (early, ge))
        c("G1-no-githubenv-job: no wipe step writes $GITHUB_ENV at all (the loader's whole-project export is the only writer)", not ge, ge)
        # ---- Guard 2 ---------------------------------------------------------------------------------------
        present = [k for k in GUARD2_CHAIN if k in idx]
        ordered = [idx[present[i]] < idx[present[i + 1]] for i in range(len(present) - 1)]
        c("G2-pairs: every adjacent pair of the read-before-destroy chain (derived from the live steps; %d pairs) is in order, and no chain member is missing" % len(ordered),
          len(present) == len(GUARD2_CHAIN) and all(ordered) and len(ordered) == len(GUARD2_CHAIN) - 1, [(present[i], present[i + 1]) for i, o in enumerate(ordered) if not o])
        rc_sites = {}
        for s in steps:
            for m in re.finditer(r"record_check --epoch (\w+) --volume-id \"\$VOLUME_ID\"", code_text(s.get("run") or "")):
                rc_sites.setdefault(skey(s), []).append(m.group(1))
        c("G2-record-check-sites: the workflow's record_check call sites are exactly wipe_detach_gate (w7) and wipe_delete_gate (w10b), each bound to the typed id", rc_sites == {"wipe_detach_gate": ["w7"], "wipe_delete_gate": ["w10b"]}, rc_sites)
        dgate = code_text((by.get("wipe_delete_gate") or {}).get("run") or "")
        c("G2-delete-gate-order: wipe_delete_gate checks the W10b record BEFORE it writes the delete marker",
          0 <= dgate.find("record_check --epoch w10b") < dgate.find('echo "phase=delete_attempted"'), dgate[-160:])
        def fn(name):
            m = re.search(r"^%s\(\) \{\n(.*?)^\}" % name, helper_text, re.S | re.M)
            return m.group(1) if m else ""
        fd, fe = fn("do_detach"), fn("do_delete")
        c("G2-helper-sites: the helper verifies the W7 record before its one detach POST and the W10b record before its one DELETE (record_verify call sites by verb)",
          0 <= fd.find('record_verify w7 "$VID"') < fd.find("hz_write POST") and 0 <= fe.find('record_verify w10b "$VID"') < fe.find("hz_write DELETE")
          and helper_text.count("hz_write POST") == 1 and helper_text.count("hz_write DELETE") == 1, (fd.find('record_verify w7 "$VID"'), fe.find('record_verify w10b "$VID"')))
        di = fn("do_identity")
        c("G2-w10b-restamp: record_verify w10b is bounded from the W10b epoch; identity --record check re-stamps the W10b epoch from the clock, requires the W7 epoch to be stamped, and the stamp verb clears a stale W10b epoch (W11a is bounded from the W10b epoch, never the W7 one)",
          'R_w10b_epoch="$NOW"' in di and 'w10b) e="$R_w10b_epoch"; bound="$WIPE_W10B_BOUND_SECONDS"' in helper_text and 'refuse wipe_assertion_stale reason=w7_unstamped' in di and 'R_w7_epoch="$NOW"\n  R_w10b_epoch=""' in fn("do_stamp"), "")
        rr = code_text((by.get("wipe_reread") or {}).get("run") or "")
        c("G2-reread-binding: wipe_reread re-reads the target as detached against the record (--record check)", "identity --expect detached --volume-id \"$VOLUME_ID\" --record check" in rr, "")
        ident = code_text((by.get("wipe_identity") or {}).get("run") or "")
        c("G2-finish-record: the wipe_finish front writes its own verdict record (identity --expect detached ... --record write), and the wipe front writes it with --expect attached",
          'helper identity --expect detached --volume-id "$VOLUME_ID" --record write' in ident and 'helper identity --expect attached --volume-id "$VOLUME_ID" --record write' in ident, "")
        # ---- Guard 3 ---------------------------------------------------------------------------------------
        marker_sites = {}
        for s in steps:
            for m in re.finditer(r'echo "phase=(\w+)"', code_text(s.get("run") or "")):
                marker_sites.setdefault(skey(s), []).append(m.group(1))
        c("G3-marker-own-steps: the before-call markers are written by their own steps (detach_attempted by wipe_detach_gate, delete_attempted by wipe_delete_gate) and by no other workflow step; neither marker step calls the helper's detach or delete verb",
          marker_sites == {"wipe_detach_gate": ["detach_attempted"], "wipe_delete_gate": ["delete_attempted"]}
          and not re.search(r"git-data-wipe\.sh\"?\s+(detach|delete)\b", gate + dgate), marker_sites)
        c("G3-marker-last: in each marker step the phase write is the last executable statement of the child body (checks first, marker last)",
          gate.rstrip().endswith("echo \"phase=detach_attempted\" >> \"$GITHUB_OUTPUT\"'") and dgate.rstrip().endswith("echo \"phase=delete_attempted\" >> \"$GITHUB_OUTPUT\"'"), (gate[-80:], dgate[-80:]))
        c("G3-started: started is exactly mode != '' from the confirm step, and wipe_confirm writes mode= only as its last executable statement pair",
          outs.get("started") == "${{ steps.wipe_confirm.outputs.mode != '' }}" and code_text(w1.get("run") or "").rstrip().endswith('echo "mode=$MODE"\necho "mode=$MODE" >> "$GITHUB_OUTPUT"'), "")
        # ---- notify ----------------------------------------------------------------------------------------
        notify = jobs.get("notify-failure") or {}
        nif = " ".join(str(notify.get("if") or "").split())
        c("G3-notify-if: notify-failure needs [cutover, wipe] and its if: is exactly two OR-ed clauses, each pairing its own result check with its own started != 'false'", notify.get("needs") == ["cutover", "wipe"] and nif == NIF, (notify.get("needs"), nif))
        nb = next((s for s in (notify.get("steps") or []) if s.get("id") == "body"), {})
        nbe = nb.get("env") or {}
        c("G3-notify-env: the notify body binds the wipe inputs from needs.wipe.outputs (and the typed volume id from inputs.volume_id), merges MODE and RESULT across both jobs and binds CUTOVER_RESULT",
          nbe.get("MODE") == "${{ needs.cutover.outputs.mode || needs.wipe.outputs.mode }}"
          and nbe.get("RESULT") == "${{ needs.cutover.result == 'skipped' && needs.wipe.result || needs.cutover.result }}"
          and nbe.get("CUTOVER_RESULT") == "${{ needs.cutover.result }}"
          and nbe.get("WIPE_STARTED") == "${{ needs.wipe.outputs.started }}" and nbe.get("WIPE_PHASE") == "${{ needs.wipe.outputs.phase }}" and nbe.get("WIPE_REFUSAL") == "${{ needs.wipe.outputs.refusal }}"
          and nbe.get("WIPE_VOLUME_ID") == "${{ inputs.volume_id }}", nbe)
        nrun = nb.get("run") or ""
        m = re.search(r'^\s*case "\$MODE" in ([^)]*)\) ;; \*\) MODE=unknown ;; esac$', nrun, re.M)
        c("G3-notify-case-list: the MODE whitelist of the notify body lists exactly the nine modes, wipe_unknown included (a wipe-family mode dropped from it reads MODE=unknown)", bool(m) and m.group(1).split("|") == NOTIFY_MODES, m.group(1) if m else None)
        c("G3-notify-lost-runner: a wipe job that published no outputs (MODE empty while the cutover job was skipped) becomes MODE=wipe_unknown BEFORE the whitelist, so it is read as a wipe-family failure",
          'if [ -z "$MODE" ] && [ "${CUTOVER_RESULT:-}" = skipped ]; then MODE=wipe_unknown; fi' in nrun and nrun.find('MODE=wipe_unknown') < nrun.find('case "$MODE" in proof'), "")
        wblock = re.search(r'case "\$MODE" in wipe\|wipe_finish\|wipe_check\|wipe_unknown\)\n(.*?)\nesac\nif \[ "\$\{FREEZE_HELD', nrun, re.S)
        wtxt = wblock.group(1) if wblock else ""
        c("G3-notify-wipe-block: the notify body has a wipe-family block, chosen BEFORE the generic FINALIZER_RAN logic, that never mentions the unfreeze remedy", bool(wtxt) and not re.search(r"unfreeze", wtxt, re.I) and nrun.find("wipe_family=1") < nrun.find("FINALIZER_RAN"), len(wtxt))
        arms = re.findall(r"^\s+(\w+)\) words=", wtxt, re.M)
        norm = re.search(r"case \"\$\{WIPE_PHASE:-\}\" in ([^)]*)\) ;; \*\) WIPE_PHASE=unknown ;; esac", wtxt)
        c("G3-notify-phase-map: the notify wipe block has one arm for every phase value of the helper's vocabulary (and the normaliser lists them all); an unmapped phase falls to WIPE_STATE_UNKNOWN",
          bool(phases) and all(p in arms for p in phases) and bool(norm) and all(p in norm.group(1).split("|") for p in phases) and "unknown) words=" in wtxt, (arms, norm.group(1) if norm else None))
        va = [l for l in wtxt.splitlines() if "VOLUME_ALREADY_DETACHED" in l and "words=" in l]
        c("G3-notify-refusal-map: both refusal words are mapped and VOLUME_ALREADY_DETACHED carries the wipe_finish command with the WORD ORIGIN_RUN_ID (finish_cmd_origin, never the refused run's own id, even for mode=wipe)",
          bool(va) and "${finish_cmd_origin}" in va[0] and "${finish_cmd_here}" not in va[0] and "STORE_NOT_SERVING_DO_NOT_FINISH" in wtxt and FINISH_CMD in wtxt and FINISH_CMD_ORIGIN in wtxt, va[:1])
        # the recovery command: plain-word placeholders (no angle bracket: the body is HTML and the issue is markdown), the
        # volume id filled only from a 1-12 digit input, the origin run filled only for a mode=wipe run (its own id)
        fcl = [l for l in wtxt.splitlines() if re.search(r"^\s+(vid|orig|finish_cmd_here|finish_cmd_origin)=|\bvid=|\borig=", l) and "words=" not in l]
        c("G3-notify-finish-cmd: the finish command is built from `vid` (default the word VOLUME_ID; the typed id only when WIPE_VOLUME_ID is digits only and at most 12 long) and `orig` (default the word ORIGIN_RUN_ID; the run's own id only when MODE is wipe), and no line that builds or names it carries an angle bracket",
          'vid=VOLUME_ID' in wtxt and "case \"${WIPE_VOLUME_ID:-}\" in ''|*[!0-9]*) ;; *) if [ \"${#WIPE_VOLUME_ID}\" -le 12 ]; then vid=\"$WIPE_VOLUME_ID\"; fi ;; esac" in wtxt
          and 'orig=ORIGIN_RUN_ID' in wtxt and 'if [ "$MODE" = wipe ]; then orig="$RUN_ID"; fi' in wtxt
          and len(fcl) >= 4 and not any(re.search(r"[<>]", l.replace(">>", "")) for l in fcl) and not re.search(r"gh workflow run[^\n]*[<>]", wtxt),
          fcl[:6])
        # ---- Guard 4 ---------------------------------------------------------------------------------------
        cu = jobs.get("cutover") or {}
        cconf = next((s for s in (cu.get("steps") or []) if s.get("id") == "confirm"), {})
        c("G4-cutover-confirm: the cutover confirm step binds VOLUME_ID and ORIGIN_RUN from the inputs and refuses either for every mode it serves",
          (cconf.get("env") or {}).get("VOLUME_ID") == "${{ inputs.volume_id }}" and (cconf.get("env") or {}).get("ORIGIN_RUN") == "${{ inputs.origin_run }}"
          and 'if [[ -n "${VOLUME_ID:-}" || -n "${ORIGIN_RUN:-}" ]]; then' in (cconf.get("run") or ""), "")
        # ---- Guard 6/7 workflow-side -----------------------------------------------------------------------
        fp = by.get("wipe_flag_precheck") or {}; fr = by.get("wipe_flag_reread") or {}
        c("G6-flag-mode: W3 maps FLAG_MODE to wipe_check or wipe from the confirm step's mode, the re-read pins FLAG_MODE wipe_reread, both bind secrets.DOPPLER_TOKEN_PRD, and the interim rollback-recency guard (gh run list + wipe_last_rollback_epoch) sits in the W3 step",
          (fp.get("env") or {}).get("FLAG_MODE") == "${{ steps.wipe_confirm.outputs.mode == 'wipe_check' && 'wipe_check' || 'wipe' }}"
          and (fr.get("env") or {}) == {"DOPPLER_TOKEN": "${{ secrets.DOPPLER_TOKEN_PRD }}", "FLAG_MODE": "wipe_reread", "WIPE_VARIANT": "${{ steps.wipe_flag_precheck.outputs.variant }}"}
          and (fp.get("env") or {}).get("DOPPLER_TOKEN") == "${{ secrets.DOPPLER_TOKEN_PRD }}"
          and "wipe_last_rollback_epoch" in (fp.get("run") or "") and "gh run list --workflow git-data-cutover.yml" in (fp.get("run") or ""), "")
        c("G7-precheck-first: the soak and rollback-recency precheck runs before the loader, the detach and the delete (it is step 4, no destructive step precedes it)",
          idx.get("wipe_flag_precheck", 99) < idx.get("wipe_loader", -1) < idx.get("wipe_detach_gate", -1) < idx.get("wipe_delete_gate", -1), "")
        # ---- Guard 8 ---------------------------------------------------------------------------------------
        texts = {}
        for s in steps:
            texts[skey(s)] = code_text(s.get("run") or "")
        fb = []
        for k, t in texts.items():
            for l in t.splitlines():
                if FORBIDDEN.search(l.replace(STANDING, "")):
                    fb.append("%s: %s" % (k, l.strip()[:70]))
        for l in wtxt.splitlines():
            if FORBIDDEN.search(l.replace(STANDING, "")):
                fb.append("notify: %s" % l.strip()[:70])
        c("G8-forbidden: no wipe step line and no wipe notify word contains a phrase the CLO ruling forbids (erased, wiped, secure(ly), no copies/snapshots/backups, retention closed/ended, retention_end, Art. 17 satisfied/compliant, holds no personal data, volume/store (is) empty, irrecoverable, unrecoverable, permanently); only the exact PA-36(f) standing sentence is whitelisted", not fb and bool(wtxt) and len(texts) >= 21, fb)
        c("G8-standing: the W12 read-back step carries the PA-36(f) standing sentence ('does not address provider-side snapshot or backup retention ... any copy held by someone with prior access') exactly once, and no other wipe step names PA-36(f)",
          texts.get("wipe_readback", "").count(STANDING) == 1 and not any("PA-36" in t for k, t in texts.items() if k != "wipe_readback") and "PA-36(f), not measured" in STANDING, texts.get("wipe_readback", "").count(STANDING))
        rb12 = texts.get("wipe_readback", "")
        c("G8-w12-conditional: the W12 summary names a delete only when THIS run's delete step wrote phase=delete_sent (DELETE_PHASE from steps.wipe_delete.outputs.phase); otherwise it says the volume is absent at the provider API, that the run made no delete call, and names the origin run",
          (by.get("wipe_readback") or {}).get("env", {}).get("DELETE_PHASE") == "${{ steps.wipe_delete.outputs.phase }}"
          and (by.get("wipe_readback") or {}).get("env", {}).get("ORIGIN_RUN") == "${{ inputs.origin_run }}"
          and 'if [[ "$DELETE_PHASE" == "delete_sent" ]]; then' in rb12 and "the plaintext volume was deleted at the provider API" in rb12
          and "the plaintext volume is absent at the provider API" in rb12 and "This run made no delete call. The delete outcome is in the origin run (run id ${ORIGIN_RUN:-unknown})." in rb12
          and "It does not state that the volume was empty or held no personal data" in rb12, "")
        exp = set()
        for k, t in texts.items():
            for l in t.splitlines():
                # only what follows the echo/printf word is output (a variable in an `if [[ ... ]]; then echo ...` test is not)
                m_ = re.search(r"\b(echo|printf)\b(.*)", l)
                if m_ and "add-mask" not in l:
                    for v in re.findall(r"\$\{?([A-Za-z_][A-Za-z0-9_]*)", m_.group(2).split(">>")[0]):
                        exp.add(v)
        exp -= {"GITHUB_STEP_SUMMARY", "GITHUB_OUTPUT", "RUNNER_TEMP", "GITHUB_PATH", "d", "HOME", "PATH", "GITHUB_WORKSPACE", "keyfile", "kh", "cfg", "key", "tmp"}
        extra = sorted(exp - ECHO_VARS_ALLOWED)
        c("G8-no-names: the variables a wipe step expands into echo/printf output are on the pinned allow-list (verdict words, modes, ids and epochs); a step that echoes anything else, such as a value read from the volume, is RED", not extra, extra)
        ssh_users = [k for k, t in texts.items() if k != "wipe_ssh_config" and re.search(r"(^|\s)(ssh|scp|rsync)\s", t)]
        c("G8-no-host-listing: no wipe step runs ssh itself or reads a store path (the host read is the one pinned verb, whose output the host script bounds)", not ssh_users and not any(re.search(r"repositories|\bls\b|\bfind\b", t) for t in texts.values()), ssh_users)
        # ---- step keys, step env names, transport/credential copies, the workflow-to-script contract (review round 2) ------
        key_bad = []
        for s_ in steps:
            allowed = STEP_KEYS_USES if s_.get("uses") else STEP_KEYS_RUN
            extra = sorted(set(s_) - allowed)
            if extra:
                key_bad.append("%s: %s" % (skey(s_), extra))
        c("G1-step-keys: every wipe step carries only {name, id, if, env, run} (a uses: step only {name, id, if, uses, with}); no shell:, working-directory:, continue-on-error, timeout-minutes or any other step-level key (the runner honours them around the exec env -i)",
          not key_bad and len(steps) >= 21, key_bad)
        env_bad = []
        for s_ in steps:
            for nm in list((s_.get("env") or {}).keys()) + list((s_.get("with") or {}).keys()):
                if ENV_DENY.match(str(nm)):
                    env_bad.append("%s: %s" % (skey(s_), nm))
        for nm in list((wipe.get("env") or {}).keys()) + list((wf.get("env") or {}).keys()):
            if ENV_DENY.match(str(nm)):
                env_bad.append("job/workflow env: %s" % nm)
        c("G1-step-env-names: no step env: or with:, no job env and no workflow env names a variable the shell or the dynamic linker honours before line 1 (BASH_ENV, ENV, LD_*, PATH, SHELLOPTS, BASHOPTS, PS4, PROMPT_COMMAND, IFS, BASH_FUNC_*, BASH_XTRACEFD, CDPATH, GLOBIGNORE)",
          not env_bad and len(steps) >= 21, env_bad)
        xt_bad = []
        xt_n = 0
        for s_ in steps:
            if s_.get("uses") or not s_.get("run"):
                continue
            named = set(SECRET_RE.findall(json.dumps(s_.get("env") or {}))) - {"GITHUB_TOKEN"}
            if named:
                xt_n += 1
                if XTRACE_LINE not in [l_.strip() for l_ in code_lines(s_.get("run"))[:2]]:
                    xt_bad.append(skey(s_))
        c("G1-xtrace-all: every wipe step that binds a secret other than GITHUB_TOKEN refuses xtrace (the #7797 case line is among its first two executable lines); live count reported",
          not xt_bad and xt_n >= 7, "%d steps bind a secret; missing=%s" % (xt_n, xt_bad))
        inst = code_text((by.get("wipe_doppler_install") or {}).get("run") or "")
        i_c, i_s, i_t = inst.find("curl "), inst.find("sha256sum -c"), inst.find("tar xzf")
        c("G1-install-verifies: the inline Doppler install checks the downloaded archive against the pinned sha256 (`sha256sum -c -`, fed from DOPPLER_CLI_SHA256) AFTER the download and BEFORE the unpack",
          0 <= i_c < i_s < i_t and 'echo "${DOPPLER_CLI_SHA256}  $d/doppler.tar.gz" | sha256sum -c -' in inst, (i_c, i_s, i_t))
        inst_curls = re.findall(r"\bcurl\b[^\n]*", re.sub(r"\\\n\s*", " ", inst))
        c("G1-timeout-install: the inline Doppler install is the step's only curl and it is bounded (--connect-timeout 20 and --max-time 120), so a stalled release download cannot hold the job to its 30-minute timeout",
          len(inst_curls) == 1 and bool(re.search(r"--connect-timeout 20(?!\d)", inst_curls[0])) and bool(re.search(r"--max-time 120(?!\d)", inst_curls[0])), inst_curls)
        dop_bad = []
        for k_ in ro_steps:
            t_ = code_text(by[k_].get("run") or "")
            n_all = len(re.findall(r"\bdoppler secrets get HCLOUD_TOKEN_READONLY\b", t_))
            n_to = len(re.findall(r"""(?<![\w-])timeout 60 doppler secrets get HCLOUD_TOKEN_READONLY --plain -p soleur -c prd_terraform 2>/dev/null\)" \|\| tok=""$""", t_, re.M))
            if n_all != 1 or n_to != 1:
                dop_bad.append((k_, n_all, n_to))
        c("G1-timeout-doppler: each of the three read-only token fetches (wipe_identity, wipe_reread, wipe_readback) runs under `timeout 60` and a timeout lands on `|| tok=\"\"` (an absent token: the helper refuses wipe_readonly_token_absent), never on a value",
          ro_steps == ["wipe_identity", "wipe_readback", "wipe_reread"] and not dop_bad, dop_bad)
        gh_all = gh_to = 0
        gh_bad = []
        for s_ in steps:
            t_ = code_text(s_.get("run") or "")
            a_ = len(re.findall(r"\bgh run (?:list|view)\b", t_))
            b_ = len(re.findall(r"(?<![\w-])timeout 60 gh run (?:list|view)\b", t_))
            gh_all += a_; gh_to += b_
            if a_ != b_:
                gh_bad.append(skey(s_))
        c("G1-timeout-gh: every `gh run list` / `gh run view` of the wipe job runs under `timeout 60` (a timeout reads as an unreadable run list or origin run, which both refuse); live count reported",
          gh_all >= 2 and gh_all == gh_to and not gh_bad, "%d calls, %d bounded, unbounded in %s" % (gh_all, gh_to, gh_bad))
        kfr = code_text((by.get("wipe_key_fetch") or {}).get("run") or "")
        c("G1-key-validated: the root-key fetch validates what it fetched (non-empty, an OpenSSH private key per `ssh-keygen -y`) and fails with reason=not_openssh_key / empty / rc_nonzero before the job continues",
          'ssh-keygen -y -f "$keyfile"' in kfr and "reason=not_openssh_key" in kfr and "reason=empty" in kfr and "reason=rc_nonzero" in kfr and kfr.find("ssh-keygen -y") < kfr.rfind("exit 1"), "")
        # the copied bridge / key-fetch / ssh_config steps equal the cutover job's copies modulo ids, if:, the redundant second
        # xtrace guard of the cutover copy, and the `git-data-wipe` / `git-data-cutover` title text
        cj = {(x.get("id") or x.get("uses")): x for x in (jobs.get("cutover") or {}).get("steps") or []}
        def norm(st):
            d = {k: v for k, v in st.items() if k not in ("id", "if")}
            if isinstance(d.get("run"), str):
                d["run"] = re.sub(r"title=git-data-(?:wipe|cutover)", "title=GD", XT2.sub("", d["run"]))
            return d
        pairs = (("./.github/actions/cf-tunnel-ssh-bridge", "wipe_bridge"), ("key_fetch", "wipe_key_fetch"), ("ssh_config", "wipe_ssh_config"))
        par_bad = [b for a_, b in pairs if a_ not in cj or b not in by or norm(cj[a_]) != norm(by[b])]
        c("WS-copy-parity: the wipe job's CF Tunnel SSH bridge, root-key fetch and ssh_config steps equal the cutover job's copies after masking the step id, the if:, the cutover copy's second (title-carrying) xtrace guard and the git-data-wipe / git-data-cutover title text",
          not par_bad and all(a_ in cj for a_, _ in pairs), par_bad)
        # the workflow-to-script environment contract: every name git-data-cutover.sh's wipe_assert path reads is passed by every
        # step that runs it under `exec env -i`
        hv = open(a["host_verb"]).read()
        def fbody(name):
            m_ = re.search(r"^%s\(\) \{\n(.*?)^\}" % name, hv, re.S | re.M)
            return m_.group(1) if m_ else ""
        scr = fbody("access_gate") + fbody("resolve_roster") + fbody("mode_wipe_assert")
        PRE_ONLY = {"WIPE_ROW_DT", "WIPE_LISTING"}
        need = set(re.findall(r"\$\{(WEB_HOST_SSH|GIT_DATA_SSH|WEB_HOSTS|WIPE_[A-Z_]+)[:}-]", scr)) - PRE_ONLY
        need -= set(re.findall(r"^(WIPE_[A-Z_]+)=", hv, re.M))   # script constants, not inputs
        if re.search(r'^MODE="\$\{MODE:-', hv, re.M):
            need.add("MODE")
        cont_bad = []
        cont_steps = []
        for s_ in steps:
            r_ = s_.get("run") or ""
            if "git-data-cutover.sh" not in r_ or not first_statement(r_)[0].startswith("exec env -i "):
                continue
            cont_steps.append(skey(s_))
            joined = re.sub(r"\\\n\s*", " ", r_)
            supplied = set(n_ for n_, _ in ASSIGN_RE.findall(joined))
            for x_ in re.findall(r"\bexport\s+([A-Za-z_ ]+)", joined):
                supplied.update(x_.split())
            miss = sorted(need - supplied)
            leak = sorted(PRE_ONLY & supplied) if "'pre'" not in str((s_.get("env") or {}).get("WIPE_PHASE")) else []
            if miss or leak:
                cont_bad.append("%s: missing=%s pre-only-passed=%s" % (skey(s_), miss, leak))
        c("G10-env-contract: DERIVED from git-data-cutover.sh (the names access_gate, resolve_roster and mode_wipe_assert read: WEB_HOST_SSH, GIT_DATA_SSH, WEB_HOSTS and every WIPE_* input except the pre-only WIPE_ROW_DT / WIPE_LISTING, plus MODE), every wipe step that runs it under `exec env -i` passes each name; live names and steps reported",
          not cont_bad and "wipe_post_detach_read" in cont_steps and {"WEB_HOST_SSH", "GIT_DATA_SSH", "WEB_HOSTS", "WIPE_PHASE", "WIPE_VOLUME_ID", "WIPE_LUKS_VOLUME_ID", "WIPE_SERVER_ID"} <= need,
          "need=%s steps=%s %s" % (sorted(need), cont_steps, cont_bad))
        h7, h10 = code_text((by.get("wipe_host_assert") or {}).get("run") or ""), code_text((by.get("wipe_post_detach_read") or {}).get("run") or "")
        c("G7-record-ids: W7 and W10 take the typed volume id, the server id and the LUKS id from the verdict record W4 wrote (plaintext_id= / server_id= / luks_id=, Hetzner's normalised answer), never from the raw input: a leading-zero id reaches the host as the number",
          all(("s/^plaintext_id=//p" in t) and ("s/^server_id=//p" in t) and ("s/^luks_id=//p" in t) for t in (h7, h10))
          and not re.search(r"WIPE_VOLUME_ID=\"?\$\{?VOLUME_ID", h7 + h10), "")
        c("G7-listing-env: W7 runs the plaintext layout listing for mode=wipe and mode=wipe_check (A1 2026-10-15; WIPE_LISTING is `run` for both and `skip` for wipe_finish), passes the boot row's epoch as WIPE_ROW_DT for the pre phase only, and passes WIPE_PHASE pre|finish",
          ((by.get("wipe_host_assert") or {}).get("env") or {}).get("WIPE_LISTING") == "${{ steps.wipe_confirm.outputs.mode != 'wipe_finish' && 'run' || 'skip' }}"
          and ((by.get("wipe_host_assert") or {}).get("env") or {}).get("WIPE_ROW_EPOCH") == "${{ steps.wipe_boot_read.outputs.row_epoch }}"
          and 'WIPE_ROW_DT="$WIPE_ROW_EPOCH"' in h7 and "unset WIPE_LISTING" in h7
          and ((by.get("wipe_host_assert") or {}).get("env") or {}).get("WIPE_PHASE") == "${{ steps.wipe_confirm.outputs.mode == 'wipe_finish' && 'finish' || 'pre' }}", "")
        tdn = code_text((by.get("wipe_teardown") or {}).get("run") or "")
        c("G10-store-not-serving-rc5: W10 captures the host verb's stdout (wipe-w10.out, printed, shredded by the teardown) and publishes refusal=store_not_serving only when the verb exited 5 AND the output carries no ' verdict=probe_failed' (a read that did not answer is not a store verdict); the access gate's 3 and every other exit fail the step without that claim",
          'bash "$GITHUB_WORKSPACE/apps/web-platform/infra/git-data-cutover.sh" > "$out" || rc=$?' in h10 and 'out="$RUNNER_TEMP/wipe-w10.out"' in h10 and "cat \"$out\"" in h10
          and 'if [[ "$rc" -eq 5 ]] && ! grep -qE "^\\[git-data-cutover\\] STORE probe=[a-z-]+ verdict=probe_failed" "$out"; then echo "refusal=store_not_serving" >> "$GITHUB_OUTPUT"; fi' in h10
          and h10.count("refusal=store_not_serving") == 1 and '"$RUNNER_TEMP/wipe-w10.out"' in tdn, "")
        w10_run = 'bash "$GITHUB_WORKSPACE/apps/web-platform/infra/git-data-cutover.sh" > "$out" || rc=$?'
        c("G10-retry-once: W10 retries its READ-ONLY host check exactly once, after `sleep 10`, and only when the first attempt did not answer (the access gate's 3, or the verb's 5 carrying verdict=probe_failed); the second attempt decides and the refusal is published after it",
          h10.count(w10_run) == 2 and h10.count("sleep 10") == 1 and 'if [[ "$rc" -ne 0 ]] && unanswered; then' in h10
          and '[[ "$rc" -eq 3 ]] && return 0' in h10
          and '[[ "$rc" -eq 5 ]] && grep -qE "^\\[git-data-cutover\\] STORE probe=[a-z-]+ verdict=probe_failed" "$out" && return 0' in h10
          and 0 <= h10.find("sleep 10") < h10.rfind(w10_run) < h10.find("refusal=store_not_serving"), "")
        wr_lim = re.search(r'WIPE_RUNS_LIST_LIMIT:-(\d+)\}', code_text((by.get("wipe_flag_precheck") or {}).get("run") or ""))
        lib_lim = re.search(r"^readonly WIPE_RUNS_LIST_LIMIT=(\d+)$", libtext, re.M)
        c("G6-limit-parity: the W3 `gh run list --limit` default equals the run lib's WIPE_RUNS_LIST_LIMIT (the lib's `list is full` reach test compares against it), and the list asks for exactly the fields the lib reads",
          bool(wr_lim) and bool(lib_lim) and wr_lim.group(1) == lib_lim.group(1)
          and "--json databaseId,displayTitle,createdAt,conclusion,headBranch,event" in code_text((by.get("wipe_flag_precheck") or {}).get("run") or "")
          and "--json databaseId,displayTitle,createdAt,conclusion,headBranch,event" in libtext, (wr_lim.group(1) if wr_lim else None, lib_lim.group(1) if lib_lim else None))
        c("G3-identity-no-phase: the helper's identity verb publishes no phase (a volume that was already detached says nothing about what THIS run did); the phase vocabulary is written only by detach, delete and readback",
          bool(fn("do_identity")) and "gho phase" not in fn("do_identity"), "")
        # ---- parity ----------------------------------------------------------------------------------------
        self.parity(a, wf, text, wtxt, helper_text, libtext)

    def parity(self, a, wf, text, wtxt, helper_text, libtext):
        srcs = [a["helper"], a["host_assert"], a["host_verb"], a["precheck"], a["lib"], a["boot_lib"]]
        words = set()
        for p in srcs:
            t = open(p).read()
            words.update(re.findall(r"verdict=(wipe_[a-z0-9_]+)", t))
            words.update(re.findall(r"(?:_wipe_refuse|\brefuse|\brefuse_)\s+\"?(wipe_[a-z0-9_]+)", t))
            words.update(re.findall(r"wipe_word=(wipe_[a-z0-9_]+)", t))
            words.update(re.findall(r"read_secret\s+\S+\s+(wipe_[a-z0-9_]+)", t))
            words.update(re.findall(r"echo (wipe_boot_[a-z_]+)", t))
            words.update(re.findall(r"read_volume_list\s+\S+\s+(wipe_[a-z_]+)", t))
            words.update(re.findall(r"\"(wipe_(?:precondition|origin_run)_[a-z_]+)\"", t))
            words.update(re.findall(r"printf '(wipe_(?:precondition|origin_run|runs)_[a-z_]+)\\n'", t))
            words.update(re.findall(r"[|(\s](wipe_(?:precondition|origin_run)_[a-z_]+)(?=[|)\s])", t))
            words.update(re.findall(r"^#\s+(wipe_(?:precondition|origin_run|boot)_[a-z_]+)\s", t, re.M))
        words.update(re.findall(r"verdict=(wipe_[a-z0-9_]+)", text))
        words.discard("wipe_boot_field_")
        words.discard("wipe_origin_run_ok")
        notify_words = sorted(set(re.findall(r'swords=" ([A-Z][A-Z_]+)"', wtxt)))
        # completeness: every wipe_* token in those sources is either a derived verdict word or on the explicit non-verdict list
        NONVERDICT = {"wipe_assert", "wipe_check", "wipe_reread", "wipe_soak", "wipe_word", "wipe_family", "wipe_finish", "wipe_listing", "wipe_origin_run_ok",
                      "wipe_last_rollback_epoch", "wipe_run_title_class", "wipe_detach_gate", "wipe_delete_gate", "wipe_other", "wipe_boot_field_", "wipe_unknown", "wipe_variant"}
        alltoks = set()
        for p in srcs:
            alltoks.update(re.findall(r"\bwipe_[a-z0-9_]+\b", open(p).read()))
        alltoks.update(t for t in re.findall(r"\bwipe_[a-z0-9_]+\b", text) if not t.startswith(("wipe_confirm", "wipe_doppler", "wipe_flag", "wipe_origin_check", "wipe_identity", "wipe_boot_read", "wipe_bridge", "wipe_key", "wipe_ssh", "wipe_host", "wipe_loader", "wipe_post", "wipe_readback", "wipe_teardown", "wipe_detach", "wipe_delete", "wipe_reread")))
        unclassified = sorted(t for t in alltoks if t not in words and t not in NONVERDICT and not t.startswith("wipe_boot_field_"))
        self.words = sorted(words); self.notify_words = notify_words
        self.check("G8-words-floor: the verdict words derived from the helper, host verb, host script, precheck, run lib, boot lib and workflow number at least 60 (live count reported), the notify words at least 9, and every other wipe_* token in those files is classified", len(words) >= 60 and len(notify_words) >= 9 and not unclassified,
                   "%d verdict words, %d notify words, unclassified=%s" % (len(words), len(notify_words), unclassified))
        rb = open(a["runbook"]).read() if os.path.exists(a["runbook"]) else ""
        sec = re.search(r"^(#{2,3}) .*[Vv]erdict map.*$", rb, re.M)
        sect = ""
        if sec:
            lvl = len(sec.group(1))
            rest = rb[sec.end():]
            nxt = re.search(r"^#{1,%d} " % lvl, rest, re.M)
            sect = rest[:nxt.start()] if nxt else rest
        missing = sorted(w for w in list(words) + notify_words if not re.search(r"(?<![A-Za-z0-9_])%s(?![A-Za-z0-9_])" % re.escape(w), sect))
        self.check("G8-parity: every wipe_* verdict word and every wipe-family notify word emitted by the helper, host verb, precheck, run lib and workflow appears in the runbook's Verdict map section (derived from the code; RED until the runbook section lists them)",
                   bool(sec) and not missing, ("no Verdict map section" if not sec else "%d of %d missing: %s" % (len(missing), len(words) + len(notify_words), missing[:40])))


def CUTOVER_IF_LIVE(wf):
    return str(((wf.get("jobs") or {}).get("cutover") or {}).get("if") or "false")


def census_main(spec):
    cz = Census(spec)
    cz.run()
    out = open(spec["out"], "w")
    for st, name, d in cz.rows:
        out.write("%s\t%s\t%s\n" % (st, name, d))
    out.close()
    with open(spec["out"] + ".words", "w") as fh:
        fh.write("\n".join(cz.words) + "\n")
    with open(spec["out"] + ".nwords", "w") as fh:
        fh.write("\n".join(cz.notify_words) + "\n")
    wipe_steps = ((load_yaml(spec["wf"]).get("jobs") or {}).get("wipe") or {}).get("steps") or []
    live = [skey(s) for s in wipe_steps]
    with open(spec["out"] + ".chain", "w") as fh:
        fh.write("\n".join(k for k in live if k in GUARD2_CHAIN) + "\n")
    with open(spec["out"] + ".steps", "w") as fh:
        fh.write("\n".join(live) + "\n")



# ---------------------------------------------------------------------------------------------------------
# the mutator: edits a COPY of the workflow text (steps located by id), asserting each edit matched
# ---------------------------------------------------------------------------------------------------------
def wipe_range(lines):
    s = next(i for i, l in enumerate(lines) if l == "  wipe:")
    e = next(i for i, l in enumerate(lines) if l == "  notify-failure:" and i > s)
    return s, e


def step_blocks(lines, s, e):
    starts = [i for i in range(s, e) if re.match(r"^      - ", lines[i])]
    blocks = []
    for n, st in enumerate(starts):
        en = starts[n + 1] if n + 1 < len(starts) else e
        # trailing comment/blank lines belong to the NEXT step
        while en - 1 > st and (lines[en - 1].strip() == "" or lines[en - 1].lstrip().startswith("#")):
            en -= 1
        blocks.append((st, en))
    return blocks


def block_of(lines, s, e, step_id):
    for st, en in step_blocks(lines, s, e):
        body = "\n".join(lines[st:en])
        if re.search(r"^\s+id: %s\s*$" % re.escape(step_id), body, re.M) or (step_id == "checkout" and "uses: actions/checkout@" in body):
            return st, en
    raise SystemExit("mutator: step %s not found" % step_id)


def mutate_main(spec):
    src = open(spec["src"]).read()
    lines = src.split("\n")
    ops = spec["ops"] if "ops" in spec else MUTANTS[spec["named"]]
    for op in ops:
        kind = op["op"]
        s, e = wipe_range(lines) if (op.get("step") or op.get("job") == "wipe" or op.get("job") == "cutover" or kind in ("swap", "delete", "insert_after", "insert_before", "move_after", "dup")) else (0, 0)
        if kind in ("sub", "resub"):
            if op.get("step"):
                a, b = block_of(lines, s, e, op["step"])
            elif op.get("job") == "notify":
                a = next(i for i, l in enumerate(lines) if l == "  notify-failure:"); b = len(lines)
            elif op.get("job") == "cutover":
                a = next(i for i, l in enumerate(lines) if l == "  cutover:"); b = s
            elif op.get("job") == "wipe":
                a, b = s, e
            else:
                a, b = 0, len(lines)
            seg = "\n".join(lines[a:b])
            if kind == "sub":
                cnt = seg.count(op["old"])
                if cnt != op.get("count", 1):
                    raise SystemExit("mutator: %r matched %d times, wanted %d" % (op["old"][:60], cnt, op.get("count", 1)))
                seg = seg.replace(op["old"], op["new"])
            else:
                seg, cnt = re.subn(op["old"], op["new"], seg, flags=re.M)
                if cnt != op.get("count", 1):
                    raise SystemExit("mutator: /%s/ matched %d times, wanted %d" % (op["old"][:60], cnt, op.get("count", 1)))
            lines[a:b] = seg.split("\n")
        elif kind == "swap":
            (a1, b1) = block_of(lines, s, e, op["a"]); (a2, b2) = block_of(lines, s, e, op["b"])
            if a1 > a2:
                (a1, b1), (a2, b2) = (a2, b2), (a1, b1)
            lines = lines[:a1] + lines[a2:b2] + lines[b1:a2] + lines[a1:b1] + lines[b2:]
        elif kind == "move_after":
            a, b = block_of(lines, s, e, op["step"])
            blk = lines[a:b]
            del lines[a:b]
            s, e = wipe_range(lines)
            a2, b2 = block_of(lines, s, e, op["after"])
            lines[b2:b2] = blk
        elif kind == "dup":
            a, b = block_of(lines, s, e, op["step"])
            blk = [l.replace("id: %s" % op["step"], "id: %s" % op["new_id"]) for l in lines[a:b]]
            a2, b2 = block_of(lines, s, e, op["after"])
            lines[b2:b2] = blk
        elif kind == "delete":
            a, b = block_of(lines, s, e, op["step"])
            del lines[a:b]
        elif kind in ("insert_after", "insert_before"):
            a, b = block_of(lines, s, e, op["step"])
            at = b if kind == "insert_after" else a
            lines[at:at] = op["text"].split("\n")
        else:
            raise SystemExit("mutator: unknown op %s" % kind)
    open(spec["dst"], "w").write("\n".join(lines))


# ---------------------------------------------------------------------------------------------------------
# the simulator: runs the REAL run: text of the wipe job step by step under PATH shims. Synthesized ids and tokens only.
# ---------------------------------------------------------------------------------------------------------
LOADED_RE = r"^(HCLOUD_TOKEN|TF_VAR_|AWS_|TF_STATE_AWS_|DOPPLER_TOKEN_TF)"

LIBSH = r'''
ev() { local n; n=$(( $(cat "$W/seq") + 1 )); printf '%s' "$n" > "$W/seq"; printf '%s\t%s\t%s\n' "$n" "$(cat "$W/step" 2>/dev/null)" "$*" >> "$W/events.log"; }
leaks() { env | cut -d= -f1 | grep -E '__LOADED__' | sort | tr '\n' ',' || true; }
'''.replace("__LOADED__", LOADED_RE)

CURL_SH = r'''#!/usr/bin/env bash
W='__W__'
. "$W/lib.sh"
n=$(( $(cat "$W/cn" 2>/dev/null || echo 0) + 1 )); printf '%s' "$n" > "$W/cn"
mkdir -p "$W/calls"
printf '%s\n' "$@" > "$W/calls/$n.argv"
cat > "$W/calls/$n.stdin"
METHOD=GET; OUT=""; URL=""; FMT=""
while [ $# -gt 0 ]; do
  case "$1" in
    -X) METHOD="$2"; shift 2 ;;
    -o) OUT="$2"; shift 2 ;;
    -w) FMT="$2"; shift 2 ;;
    --max-time|--max-filesize|--noproxy|--config) shift 2 ;;
    https://*) URL="$1"; shift ;;
    *) shift ;;
  esac
done
tok="$(sed -nE 's/^header = "Authorization: Bearer (.*)"$/\1/p' "$W/calls/$n.stdin")"
if [ -z "$tok" ]; then cls=NONE
elif [ "$tok" = "$(cat "$W/ro_token")" ]; then cls=RO
elif [ "$tok" = "$(cat "$W/rw_token")" ]; then cls=RW
else cls=OTHER; fi
BASE='https://api.hetzner.cloud/v1'
case "$URL" in "$BASE"*) PQ="${URL#"$BASE"}" ;; *) PQ="BADHOST:$URL" ;; esac
ev "curl $METHOD $PQ $cls env=$(leaks)"
set -a; . "$W/state.env"; set +a
respond() { printf '%s' "$2" > "$OUT"; [ -n "$FMT" ] && printf '%s' "$1"; exit 0; }
vol_json() { local prot; prot="\"protection\":{\"delete\":$4},"; printf '{"id":%s,"name":"%s","server":%s,%s"labels":{"app":"%s"},"location":{"name":"%s"},"created":"2026-10-14T14:33:56+00:00","size":10,"status":"available"}' "$1" "$2" "$3" "$prot" "$5" "$6"; }
srv_json() { printf '{"id":%s,"name":"soleur-git-data","created":"%s","status":"running","volumes":[%s,%s]}' "$SRV_ID" "$SRV_CREATED" "$PT_ID" "$LUKS_ID"; }
NOTFOUND='{"error":{"code":"not_found","message":"x","details":null}}'
list() { local IFS=,; printf '{"volumes":[%s],"meta":{"pagination":{"page":1,"per_page":25,"total_entries":0}}}' "$*"; }
ptsrv() { if [ "$PT_SERVER" = null ]; then echo null; else echo "$PT_SERVER"; fi; }
case "$METHOD $PQ" in
  "GET /servers?name=soleur-git-data") respond 200 "{\"servers\":[$(srv_json)],\"meta\":{}}" ;;
  "GET /servers/$SRV_ID") respond 200 "{\"server\":$(srv_json)}" ;;
  "GET /volumes?name=soleur-git-data-store")
    if [ "$PT_SERVER" = gone ]; then respond 200 "$(list)"; fi
    respond 200 "$(list "$(vol_json "$PT_ID" soleur-git-data-store "$(ptsrv)" "${PT_PROT:-false}" soleur-web-platform hel1)")" ;;
  "GET /volumes?name=soleur-git-data-luks-store")
    respond 200 "$(list "$(vol_json "$LUKS_ID" soleur-git-data-luks-store "$LUKS_SERVER" false soleur-web-platform hel1)")" ;;
  "GET /volumes/$PT_ID")
    [ "$PT_SERVER" = gone ] && respond 404 "$NOTFOUND"
    respond 200 "{\"volume\":$(vol_json "$PT_ID" soleur-git-data-store "$(ptsrv)" "${PT_PROT:-false}" soleur-web-platform hel1)}" ;;
  "GET /volumes/$LUKS_ID")
    respond 200 "{\"volume\":$(vol_json "$LUKS_ID" soleur-git-data-luks-store "$LUKS_SERVER" false soleur-web-platform hel1)}" ;;
  "GET /volumes/$PT_ID/actions?sort=id:desc&per_page=50")
    if [ -f "$W/actions.json" ]; then respond 200 "$(cat "$W/actions.json")"; fi
    respond 200 '{"actions":[],"meta":{"pagination":{"page":1,"per_page":50,"total_entries":0}}}' ;;
  "POST /volumes/$PT_ID/actions/detach")
    [ -f "$W/noflip" ] || printf 'PT_SERVER=null\n' >> "$W/state.env"
    respond 201 '{"action":{"id":777000111,"command":"detach_volume","status":"running","progress":0,"started":"2026-10-14T15:00:00Z","finished":null}}' ;;
  "GET /actions/777000111")
    respond 200 '{"action":{"id":777000111,"command":"detach_volume","status":"success","error":null}}' ;;
  "DELETE /volumes/$PT_ID")
    [ "$PT_SERVER" = gone ] && respond 404 "$NOTFOUND"
    if [ "$PT_SERVER" != null ]; then respond 423 '{"error":{"code":"locked","message":"x"}}'; fi
    printf 'PT_SERVER=gone\n' >> "$W/state.env"
    respond 204 "" ;;
esac
ev "UNEXPECTED $METHOD $PQ"
respond 599 '{"error":{"code":"shim_unexpected"}}'
'''

DOPPLER_SH = r'''#!/usr/bin/env bash
W='__W__'
. "$W/lib.sh"
name=""; [ "${1:-}" = secrets ] && [ "${2:-}" = get ] && name="${3:-}"
ok=0; [ "${DOPPLER_TOKEN:-}" = "$(cat "$W/dt_token")" ] && ok=1
ev "doppler get $name token_ok=$ok env=$(leaks)"
if [ "$name" = HCLOUD_TOKEN_READONLY ] && [ "$ok" = 1 ]; then cat "$W/ro_token"; exit 0; fi
exit 1
'''

GH_SH = r'''#!/usr/bin/env bash
# The gh shim accepts EXACTLY the argv the workflow is modeled to send (subcommand, --workflow, --limit, the --json field
# list, the run id) and answers exit 64 plus a refusal line the suite asserts empty on every golden run. It never decides
# a verdict: the fixtures (runlist.json, origin.json) are the world, the workflow and the run lib judge them.
W='__W__'
. "$W/lib.sh"
ev "gh $1 $2 env=$(leaks)"
refuse() { printf '%s\n' "$*" >> "$W/gh-refusals.log"; ev "gh REFUSED $*"; exit 64; }
if [ "${1:-}" = run ] && [ "${2:-}" = list ]; then
  [ $# -eq 8 ] && [ "${3:-}" = --workflow ] && [ "${4:-}" = git-data-cutover.yml ] && [ "${5:-}" = --limit ] && [ "${6:-}" = "$(cat "$W/runs_limit")" ] \
    && [ "${7:-}" = --json ] && [ "${8:-}" = "$(cat "$W/runs_fields")" ] || refuse "run list argv: $*"
  [ -f "$W/runlist_fail" ] && exit 1
  cat "$W/runlist.json"; exit 0
fi
if [ "${1:-}" = run ] && [ "${2:-}" = view ]; then
  [ $# -eq 5 ] && [ "${3:-}" = "$(cat "$W/origin_id")" ] && [ "${4:-}" = --json ] || refuse "run view argv: $*"
  for f in displayTitle headBranch event createdAt workflowName jobs; do
    case ",${5:-}," in *",$f,"*) ;; *) refuse "run view --json lacks $f: $5" ;; esac
  done
  [ -f "$W/origin.json" ] || exit 1
  jq -c --arg f "${5:-}" '. as $o | ($f | split(",")) | map({key: ., value: $o[.]}) | from_entries' "$W/origin.json"; exit 0
fi
if [ "${1:-}" = api ]; then
  base="repos/jikig-ai/soleur/actions/workflows/git-data-cutover.yml/runs"
  if [ $# -eq 4 ] && [ "${2:-}" = "${base}?per_page=1" ] && [ "${3:-}" = --jq ]; then cat "$W/scan_total"; exit 0; fi
  if [ $# -eq 5 ] && [ "${2:-}" = --paginate ] && [ "${3:-}" = "${base}?per_page=100" ] && [ "${4:-}" = --jq ]; then cat "$W/scan_rows"; exit 0; fi
  if [ $# -eq 2 ] && [[ "${2:-}" =~ ^repos/jikig-ai/soleur/actions/runs/([0-9]+)/attempts/([0-9]+)/jobs\?per_page=100$ ]]; then
    f="$W/scan_${BASH_REMATCH[1]}_${BASH_REMATCH[2]}.json"; [ -f "$f" ] || exit 1; cat "$f"; exit 0
  fi
  refuse "gh api argv: $*"
fi
refuse "gh argv: $*"
'''

DATE_SH = r'''#!/usr/bin/env bash
W='__W__'
if [ "${1:-}" = "+%s" ] && [ $# -eq 1 ]; then cat "$W/clock"; exit 0; fi
exec /usr/bin/date "$@"
'''

SLEEP_SH = r'''#!/usr/bin/env bash
W='__W__'
. "$W/lib.sh"
ev "sleep $*"
'''

TIMEOUT_SH = r'''#!/usr/bin/env bash
# A transparent `timeout`: it logs the bound it was given and runs the command, except that a world which sets
# TIMEOUT_FIRES=<command name> makes the bound expire for that command (exit 124, the command never runs).
W='__W__'
. "$W/lib.sh"
ev "timeout $1 $2"
secs="${1:-}"; shift
fires="$(sed -n 's/^TIMEOUT_FIRES=//p' "$W/state.env" | tail -n 1)"
if [ -n "$fires" ] && [ "${1:-}" = "$fires" ]; then exit 124; fi
real="$(PATH=/usr/bin:/bin command -v timeout)"
exec "$real" "$secs" "$@"
'''

SUDO_SH = r'''#!/usr/bin/env bash
W='__W__'
. "$W/lib.sh"
ev "sudo $1"
exit 0
'''

ENV_SH = r'''#!/usr/bin/env bash
W='__W__'
printf '%s\t%s\t%s\n' "$(( $(cat "$W/seq") + 0 ))" "$(cat "$W/step" 2>/dev/null)" "ENVARGV $*" >> "$W/envargv.log"
exec /usr/bin/env "$@"
'''

HOST_STUB = r'''#!/usr/bin/env bash
# stub for git-data-cutover.sh MODE=wipe_assert: a state machine over the same world the Hetzner shim keeps
W='__W__'
. "$W/lib.sh"
phase="${WIPE_PHASE:-}"; mode="${MODE:-}"; listing="${WIPE_LISTING-unset}"; vid="${WIPE_VOLUME_ID:-}"; sid="${WIPE_SERVER_ID:-}"; lid="${WIPE_LUKS_VOLUME_ID:-}"
set -a; . "$W/state.env"; set +a
refuse() { ev "host phase=$phase REFUSED $1 env=$(leaks)"; echo "[git-data-cutover] STORE probe=wipe-assert verdict=$1"; exit 5; }
[ "$mode" = wipe_assert ] || { ev "host BADMODE $mode"; exit 2; }
# The real script's access_gate reads these before it dials anything (exit 3); the stub reads the same names.
if [ -z "${WEB_HOST_SSH:-}" ]; then ev "host phase=$phase ACCESS web_host_ssh_unset"; echo "[git-data-cutover] ACCESS role=web host=- verdict=web_host_ssh_unset"; exit 3; fi
if [ -z "${GIT_DATA_SSH:-}" ] || [ -z "${WEB_HOSTS:-}" ]; then ev "host phase=$phase ACCESS inputs_unset"; exit 3; fi
[ "${HOST_ACCESS_FAIL:-0}" = 1 ] && { ev "host phase=$phase ACCESS transport_fail"; echo "[git-data-cutover] ACCESS role=git-data-jump host=- verdict=ssh_failed"; exit 3; }
[ "${HOST_PROBE_FAIL:-0}" = 1 ] && { ev "host phase=$phase PROBE_FAILED"; echo "[git-data-cutover] STORE probe=wipe-assert verdict=probe_failed rc=255"; exit 5; }
[ -n "$vid" ] && [ -n "$sid" ] && [ -n "$lid" ] || { ev "host MISSING_RECORD_FIELDS phase=$phase"; exit 2; }
# The ids are the RECORD's (Hetzner's normalised answer): a raw leading-zero input or another volume's id is no input here.
if [ "$vid" != "$PT_ID" ] || [ "$sid" != "$SRV_ID" ] || [ "$lid" != "$LUKS_ID" ]; then ev "host IDMISMATCH phase=$phase vid=$vid sid=$sid lid=$lid"; refuse wipe_device_absent; fi
case "$phase" in
  pre)
    case "${WIPE_RUN_MODE:-}:$listing" in wipe:run|wipe_check:run) ;; *) ev "host BADLISTING mode=${WIPE_RUN_MODE:-} listing=$listing"; exit 2 ;; esac
    [ "${WIPE_ROW_DT:-}" = "$(cat "$W/boot_epoch" 2>/dev/null)" ] || { ev "host BADROWDT row_dt=${WIPE_ROW_DT:-none}"; exit 2; }
    [ "$PT_SERVER" = "$SRV_ID" ] || refuse wipe_device_absent
    ev "host phase=pre ok listing=$listing row_dt=${WIPE_ROW_DT:-none} vid=$vid env=$(leaks)"
    line="wipe_assert pre ok layout_signal=ok journal=clean top_d=0 top_f=0 top_l=0 top_o=0 repos=0 boot_to_row_s=600 lock_residue=0 store_root_repos=${SRR:-0}"
    echo "$line"
    [ -z "${GITHUB_OUTPUT:-}" ] || printf 'wipe_assert=%s\n' "$line" >> "$GITHUB_OUTPUT" ;;
  post_detach|finish)
    [ -z "${WIPE_ROW_DT:-}${WIPE_LISTING:-}" ] || { ev "host BADPRE_ONLY phase=$phase"; exit 2; }
    [ "$PT_SERVER" != "$SRV_ID" ] || refuse wipe_device_still_attached
    [ "${HOST_SERVING:-1}" = 1 ] || refuse wipe_mapper_read_failed
    ev "host phase=$phase ok vid=$vid env=$(leaks)"
    echo "wipe_assert $phase ok byid=gone mapper_read=ok store_root=ok" ;;
  *) ev "host BADPHASE $phase"; exit 2 ;;
esac
'''

PRECHECK_STUB = r'''#!/usr/bin/env bash
W='__W__'
. "$W/lib.sh"
set -a; . "$W/state.env"; set +a
ev "precheck mode=${FLAG_MODE:-} variant_exp=${WIPE_VARIANT:-none} dt_len=${#DOPPLER_TOKEN} gh_token=${GH_TOKEN:+set} env=$(leaks)"
variant="${VARIANT:-flip_chained}"
if [ "${FLAG_MODE:-}" = wipe_reread ]; then
  case "${WIPE_VARIANT:-}" in
    flip_chained)
      if [ "${FLAG_STATE:-true}" != true ]; then echo "[git-data-flag-precheck] verdict=wipe_precondition_flag_not_true"; exit 5; fi
      echo "flag=true mode=wipe_reread"; exit 0 ;;
    separated)
      if [ "$variant" != separated ]; then echo "[git-data-flag-precheck] verdict=wipe_precondition_variant_changed expected=separated got=$variant"; exit 5; fi
      echo "wipe_variant=separated mode=wipe_reread"; exit 0 ;;
    *) echo "[git-data-flag-precheck] verdict=wipe_precondition_variant_changed expected=none"; exit 5 ;;
  esac
fi
case "${FLAG_MODE:-}" in wipe|wipe_check) echo "wipe_variant=$variant" ;; esac
if [ "$variant" = separated ]; then
  [ "${FLAG_MODE:-}" = wipe_check ] && echo "would_refuse=none"
  exit 0
fi
if [ "${FLAG_STATE:-true}" != true ]; then
  if [ "${FLAG_MODE:-}" = wipe_check ]; then echo "would_refuse=wipe_precondition_flag_not_true"; exit 0; fi
  echo "[git-data-flag-precheck] verdict=wipe_precondition_flag_not_true"; exit 5
fi
echo "flag=true mode=${FLAG_MODE:-}"
case "${FLAG_MODE:-}" in
  wipe|wipe_check) [ "${STAMP_ABSENT:-0}" = 1 ] || echo "wipe_soak floor_days=7 stamp_epoch=1700000000 elapsed_s=9999999" ;;
esac
[ "${FLAG_MODE:-}" = wipe_check ] && echo "would_refuse=none"
exit 0
'''

BOOT_STUB = r'''# stub of scripts/lib/git-data-boot-signal-poll.sh (the BetterStack read), logs its calls. The verdict function takes the
# read's rc and the server's created epoch from the WORKFLOW and judges them against the world: a read that failed is
# unreadable, a created epoch that is not the server's own is a row that proves nothing; the world's verdict decides the rest.
git_data_boot_fields_read() {
  . "__W__/lib.sh"; W='__W__'; ev "boot_read env=$(leaks)"
  printf '%s' "$(( $(cat "$W/clock") - 600 ))" > "$W/boot_epoch"
  printf '{"epoch":%s}\n' "$(cat "$W/boot_epoch")" > "$1"; : > "$2"
  return "$(cat "$W/boot_rc" 2>/dev/null || echo 0)"
}
git_data_boot_fields_verdict() {
  . "__W__/lib.sh"; W='__W__'
  local want; want="$(/usr/bin/date -u -d "$(sed -n 's/^SRV_CREATED=//p' "$W/state.env" | tail -n 1)" +%s)"
  ev "boot_verdict rrc=${1-} created=${3-}"
  if [ "${1-}" != 0 ]; then printf 'wipe_boot_unreadable\n'; return 1; fi
  if [ "${3-}" != "$want" ]; then printf 'wipe_boot_row_not_after_server\n'; return 1; fi
  local v; v="$(cat "$W/boot_verdict" 2>/dev/null || echo wipe_boot_ok)"
  printf '%s\n' "$v"; [ "$v" = wipe_boot_ok ]
}
'''


def read_outputs(path):
    out = {}
    if not os.path.exists(path):
        return out
    lines = open(path).read().split("\n")
    i = 0
    while i < len(lines):
        l = lines[i]
        m = re.match(r"^([A-Za-z_][\w-]*)<<(\S+)$", l)
        if m:
            j = i + 1; buf = []
            while j < len(lines) and lines[j] != m.group(2):
                buf.append(lines[j]); j += 1
            out[m.group(1)] = "\n".join(buf); i = j + 1; continue
        m = re.match(r"^([A-Za-z_][\w-]*)=(.*)$", l)
        if m:
            out[m.group(1)] = m.group(2)
        i += 1
    return out


def write_exec(path, text, w):
    with open(path, "w") as fh:
        fh.write(text.replace("__W__", w))
    os.chmod(path, 0o755)


SECRETS = {
    "DOPPLER_TOKEN": "synthdt%s", "DOPPLER_TOKEN_PRD": "synthprd%s", "DOPPLER_TOKEN_GIT_DATA_ROOT": "synthroot%s",
    "DOPPLER_TOKEN_INFRA_PRIVILEGED": "synthtierb%s", "DOPPLER_TOKEN_GIT_DATA_FLAG": "synthflag%s", "GITHUB_TOKEN": "synthgh%s",
    "RESEND_API_KEY": "synthresend%s", "SENTRY_ACTIONS_RO_TOKEN": "synthsentry%s", "DOPPLER_TOKEN_LEGACY_UNUSED": "synthleg%s",
}


def sim_main(spec):
    run = spec["run"].rstrip("/")
    root = spec["root"]
    wf = load_yaml(spec["wf"])
    jobs = wf.get("jobs") or {}
    wipe = jobs.get("wipe") or {}
    steps = wipe.get("steps") or []
    ws = run + "/ws"; W = run + "/world"; BIN = run + "/bin"; RT = run + "/rt"; HOME = run + "/home"; OUTD = run + "/out"
    for d in (ws, W, BIN, RT, HOME, OUTD, ws + "/apps/web-platform/infra", ws + "/scripts/lib", run + "/steps", W + "/calls"):
        os.makedirs(d, exist_ok=True)
    os.chmod(RT, 0o700)
    sec = {k: v % spec.get("tag", "0a1b2c3d4e5f") for k, v in SECRETS.items()}
    ro, rw = "synthro" + spec.get("tag", "0a1b2c3d4e5f"), "synthrw" + spec.get("tag", "0a1b2c3d4e5f")
    loaded = {"HCLOUD_TOKEN": rw, "TF_VAR_hcloud_token": rw, "AWS_ACCESS_KEY_ID": "synthaws" + spec.get("tag", "x"), "AWS_SECRET_ACCESS_KEY": "synthawssecret" + spec.get("tag", "x"),
              "TF_STATE_AWS_ACCESS_KEY_ID": "synthtfstate" + spec.get("tag", "x"), "DOPPLER_TOKEN_TF": "synthtf" + spec.get("tag", "x"), "TF_VAR_web_platform_token": "synthwp" + spec.get("tag", "x")}
    for fname, val in (("ro_token", ro), ("rw_token", rw), ("dt_token", sec["DOPPLER_TOKEN"])):
        open(W + "/" + fname, "w").write(val)
    clock0 = int(spec.get("clock0", 1760457600))
    open(W + "/clock", "w").write(str(clock0) + "\n")
    open(W + "/seq", "w").write("0")
    open(W + "/step", "w").write("-")
    open(W + "/runlist.json", "w").write(spec.get("runlist", "[]"))
    # what the gh shim accepts: derived from the run lib's own contract (limit constant, --json field list), not typed here
    libtxt = open(spec["lib"]).read()
    open(W + "/runs_limit", "w").write(re.search(r"^readonly WIPE_RUNS_LIST_LIMIT=(\d+)$", libtxt, re.M).group(1))
    open(W + "/runs_fields", "w").write(re.search(r"--json (databaseId,[A-Za-z,]+)", libtxt).group(1))
    open(W + "/origin_id", "w").write(str(spec.get("origin_run", "")))
    if spec.get("runlist_fail"):
        open(W + "/runlist_fail", "w").write("1")
    if spec.get("boot_verdict"):
        open(W + "/boot_verdict", "w").write(spec["boot_verdict"])
    if spec.get("boot_rc"):
        open(W + "/boot_rc", "w").write(str(spec["boot_rc"]))
    lib = LIBSH
    if spec.get("mute_events"):
        lib = lib.replace("ev() {", "ev() { return 0; }\nev_real() {")
    open(W + "/lib.sh", "w").write(lib)
    if spec.get("no_flip"):
        open(W + "/noflip", "w").write("1")
    srv, pt, luks = 800000001, int(spec.get("pt_id", 900000001)), 900000002
    st = {"SRV_ID": srv, "SRV_CREATED": "2026-10-14T14:33:56+00:00", "PT_ID": pt, "LUKS_ID": luks, "PT_SERVER": srv, "LUKS_SERVER": srv, "PT_PROT": "false", "FLAG_STATE": "true", "HOST_SERVING": "1"}
    st.update(spec.get("world") or {})
    st = {k: (str(srv) if v == "@SRV" else v) for k, v in st.items()}
    with open(W + "/state.env", "w") as fh:
        for k, v in st.items():
            fh.write("%s=%s\n" % (k, v))
    for nm, txt in (("curl", CURL_SH), ("doppler", DOPPLER_SH), ("gh", GH_SH), ("date", DATE_SH), ("sleep", SLEEP_SH), ("timeout", TIMEOUT_SH), ("sudo", SUDO_SH), ("env", ENV_SH)):
        write_exec(BIN + "/" + nm, txt, W)
    write_exec(ws + "/apps/web-platform/infra/git-data-cutover.sh", HOST_STUB, W)
    write_exec(ws + "/apps/web-platform/infra/git-data-flag-precheck.sh", PRECHECK_STUB, W)
    open(ws + "/scripts/lib/git-data-boot-signal-poll.sh", "w").write(BOOT_STUB.replace("__W__", W))
    for src, dst in ((spec["helper"], ws + "/apps/web-platform/infra/git-data-wipe.sh"), (root + "/scripts/lib/bearer-curl.sh", ws + "/scripts/lib/bearer-curl.sh"),
                     (spec["lib"], ws + "/scripts/lib/git-data-wipe-runs.sh")):
        if os.path.lexists(dst):
            os.unlink(dst)
        os.symlink(src, dst)
    jq = shutil.which("jq")
    path = ":".join([BIN, os.path.dirname(jq) if jq else "/usr/bin", "/usr/bin", "/bin"])
    mode = spec["mode"]
    inputs = {"mode": mode, "confirm": spec.get("confirm", {"wipe": "WIPE-GIT-DATA", "wipe_finish": "WIPE-FINISH-GIT-DATA", "wipe_check": "WIPE-CHECK-GIT-DATA"}.get(mode, "")),
              "lineage": spec.get("lineage", ""), "volume_id": str(spec.get("volume_id", pt)), "origin_run": spec.get("origin_run", "")}
    run_id = str(spec.get("run_id", "9000000123"))
    # The run-record scan (A1, the separated variant) is the REAL library over a gh shim that answers its three `gh api` shapes
    # from these fixtures: this run in progress (excluded by GDSD_SELF_RUN_ID), the two pinned runs completed and clean, and
    # on request a dirty completed run or a second in-progress run.
    sl = ws + "/scripts/lib/git-data-store-dirty-scan.sh"
    if os.path.lexists(sl):
        os.unlink(sl)
    os.symlink(root + "/scripts/lib/git-data-store-dirty-scan.sh", sl)
    clean_jobs = '{"jobs":[{"name":"cutover","conclusion":"skipped","steps":[]}]}'
    dirty_jobs = '{"jobs":[{"name":"cutover","conclusion":"success","steps":[{"name":"Write GIT_DATA_STORE_ENABLED (via the","conclusion":"success"}]}]}'
    scan_rows = []
    scan_world = spec.get("scan") or ""
    if scan_world == "dirty":
        scan_rows.append(("777000001", "completed", "1", "2026-10-10T00:00:00Z")); open(W + "/scan_777000001_1.json", "w").write(dirty_jobs)
    if scan_world == "inflight":
        scan_rows.append(("777000002", "in_progress", "1", "2026-10-15T00:00:00Z"))
    scan_rows.append((run_id, "in_progress", "1", "2026-10-15T01:00:00Z"))
    scan_rows.append(("37823216637", "completed", "1", "2026-10-08T18:18:09Z")); open(W + "/scan_37823216637_1.json", "w").write(clean_jobs)
    scan_rows.append(("36685251588", "completed", "1", "2026-09-30T07:42:29Z")); open(W + "/scan_36685251588_1.json", "w").write(clean_jobs)
    open(W + "/scan_rows", "w").write("".join("\t".join(r) + "\n" for r in scan_rows))
    open(W + "/scan_total", "w").write(str(len(scan_rows)) + "\n")
    gh = {"run_attempt": str(spec.get("run_attempt", "1")), "run_id": run_id, "server_url": "https://github.example", "repository": "example/repo"}
    ctx = {"inputs": inputs, "github": gh, "runner": {"temp": RT}, "secrets": sec, "steps": {}, "env": {}}
    if spec.get("no_tier_b"):
        ctx["secrets"] = dict(sec); ctx["secrets"]["DOPPLER_TOKEN_INFRA_PRIVILEGED"] = ""
    if spec.get("legacy_only"):
        ctx["secrets"] = dict(ctx["secrets"]); ctx["secrets"]["DOPPLER_TOKEN_INFRA_PRIVILEGED"] = ""; ctx["secrets"]["DOPPLER_TOKEN_LEGACY"] = "synthlegacy" + spec.get("tag", "x")
    jobenv = {}
    for k, v in (wf.get("env") or {}).items():
        jobenv[k] = tostr(interp(v, ctx))
    ctx["env"] = dict(jobenv)
    for k, v in (wipe.get("env") or {}).items():
        jobenv[k] = tostr(interp(v, ctx))
    ctx["env"] = dict(jobenv)
    # gh run view fixture, derived from the workflow's own step NAMES (gh exposes names, never ids)
    if mode == "wipe_finish":
        names = []
        for s in steps:
            k = skey(s)
            names.append({"name": (k if spec.get("origin_names") == "ids" else (s.get("name") or ("Run " + str(s.get("uses") or "")))), "conclusion": "success"})
            if k == ("wipe_delete_gate" if spec.get("origin_through") == "delete" else "wipe_detach_gate"):
                break
        if spec.get("gate_conclusion"):
            for nm_ in names:
                nm_["conclusion"] = spec["gate_conclusion"]
        origin = {"displayTitle": "git-data wipe %s" % inputs["volume_id"], "headBranch": "main", "event": "workflow_dispatch", "createdAt": "2026-10-14T14:55:00Z",
                  "workflowName": wf.get("name"), "jobs": [{"name": "wipe", "steps": names}]}
        origin.update(spec.get("origin_override") or {})
        if not spec.get("origin_absent"):
            open(W + "/origin.json", "w").write(json.dumps(origin))
        if st.get("PT_SERVER") == "null":
            open(W + "/actions.json", "w").write(json.dumps({"actions": [{"id": 5, "command": "detach_volume", "status": "success", "started": "2026-10-14T15:00:00Z", "finished": "2026-10-14T15:00:09Z", "progress": 100}], "meta": {"pagination": {"page": 1, "per_page": 50, "total_entries": 1}}}))
    if spec.get("actions_json"):
        open(W + "/actions.json", "w").write(spec["actions_json"])
    gh_env = {}
    state = {"failed": False, "cancelled": False}
    results = []
    summary = run + "/summary.md"
    open(summary, "w").close()
    killed = False
    loader_ran = False
    for n, s in enumerate(steps):
        key = skey(s)
        if spec.get("kill_at") == key:
            killed = True; state["cancelled"] = True
            results.append({"key": key, "outcome": "cancelled", "rc": None})
            break
        cb = (spec.get("clock_before") or {}).get(key)
        if cb:
            _now = int(open(W + "/clock").read())
            open(W + "/clock", "w").write(str(_now + int(cb)) + "\n")
        for k_, v_ in ((spec.get("world_before") or {}).get(key) or {}).items():
            with open(W + "/state.env", "a") as fh:
                fh.write("%s=%s\n" % (k_, str(srv) if v_ == "@SRV" else v_))
        try:
            runs = step_runs(s, ctx, state)
        except Exception as e:
            runs = False
            results.append({"key": key, "outcome": "if-error", "rc": None, "error": str(e)}); state["failed"] = True
            continue
        if not runs:
            ctx["steps"][key] = {"outputs": {}, "outcome": "skipped", "conclusion": "skipped"}
            results.append({"key": key, "outcome": "skipped", "rc": None})
            continue
        open(W + "/step", "w").write(key)
        with open(W + "/events.log", "a") as fh:
            sq = int(open(W + "/seq").read()) + 1
            open(W + "/seq", "w").write(str(sq))
            fh.write("%d\t%s\tSTEP start\n" % (sq, key))
        outfile = OUTD + "/%02d_%s.out" % (n, key)
        open(outfile, "w").close()
        rc = 0
        if s.get("uses"):
            u = str(s["uses"])
            if u.startswith("actions/checkout@"):
                pass
            elif u == "./.github/actions/cf-tunnel-ssh-bridge":
                wi = {k: tostr(interp(v, ctx)) for k, v in (s.get("with") or {}).items()}
                kf = RT + "/ci-key"; open(kf, "w").write("synthetic\n")
                gh_env.update({"SERVER_IP": wi.get("server-ip", ""), "CLOUDFLARED_PID": "", "CI_SSH_KEYFILE": kf,
                               "WEB_HOST_SSH": "ssh -F /dev/null -i %s -o StrictHostKeyChecking=yes -l root" % kf})
                open(W + "/step", "a").close()
                with open(W + "/events.log", "a") as fh:
                    sq = int(open(W + "/seq").read()) + 1; open(W + "/seq", "w").write(str(sq)); fh.write("%d\t%s\tbridge doppler_token_ok=%s\n" % (sq, key, int(wi.get("doppler-token") == sec["DOPPLER_TOKEN"])))
            elif u == "./.github/actions/infra-credentials":
                wi = {k: tostr(interp(v, ctx)) for k, v in (s.get("with") or {}).items()}
                src = "tier_b" if wi.get("doppler-token-infra-privileged") else ("legacy" if wi.get("doppler-token-legacy") else "")
                with open(W + "/events.log", "a") as fh:
                    sq = int(open(W + "/seq").read()) + 1; open(W + "/seq", "w").write(str(sq)); fh.write("%d\t%s\tloader inputs=%s source=%s\n" % (sq, key, ",".join(sorted(k for k, v in wi.items() if v)), src or "none"))
                if not src:
                    rc = 1
                else:
                    gh_env.update(loaded)
                    loader_ran = True
                    with open(outfile, "a") as fh:
                        fh.write("source=%s\n" % src)
            else:
                rc = 0  # an unknown remote action is a no-op in the simulator (the census row owns the uses: set)
                with open(W + "/events.log", "a") as fh:
                    sq = int(open(W + "/seq").read()) + 1; open(W + "/seq", "w").write(str(sq)); fh.write("%d\t%s\tREMOTE_USES %s\n" % (sq, key, u))
        elif key in set(spec.get("stub_steps") or ["wipe_doppler_install", "wipe_key_fetch", "wipe_ssh_config"]):
            with open(W + "/events.log", "a") as fh:
                sq = int(open(W + "/seq").read()) + 1; open(W + "/seq", "w").write(str(sq)); fh.write("%d\t%s\tstub\n" % (sq, key))
            if key == "wipe_key_fetch":
                open(RT + "/gd-root-key", "w").write("synthetic\n")
        else:
            env = {"PATH": path, "HOME": HOME, "RUNNER_TEMP": RT, "GITHUB_WORKSPACE": ws, "GITHUB_OUTPUT": outfile, "GITHUB_STEP_SUMMARY": summary,
                   "GITHUB_ENV": run + "/gh_env", "GITHUB_PATH": run + "/gh_path", "GITHUB_RUN_ID": run_id, "GITHUB_RUN_ATTEMPT": gh["run_attempt"], "GITHUB_REPOSITORY": "jikig-ai/soleur", "CI": "true", "LC_ALL": "C"}
            env.update(jobenv); env.update(gh_env)
            for k, v in (s.get("env") or {}).items():
                env[k] = tostr(interp(v, ctx, state))
            sh = run + "/steps/%02d_%s.sh" % (n, key)
            open(sh, "w").write(s.get("run") or "")
            try:
                p = subprocess.run(["bash", "--noprofile", "--norc", "-eo", "pipefail", sh], cwd=ws, env=env, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=int(spec.get("step_timeout", 90)))
                rc = p.returncode
                open(run + "/steps/%02d_%s.stdout" % (n, key), "wb").write(p.stdout)
                open(run + "/steps/%02d_%s.stderr" % (n, key), "wb").write(p.stderr)
            except subprocess.TimeoutExpired:
                rc = 124
            if os.path.exists(run + "/gh_env"):
                for k_, v_ in read_outputs(run + "/gh_env").items():
                    gh_env[k_] = v_
        if spec.get("fail_after") == key and rc == 0:
            rc = 1
        if spec.get("cancel_after") == key:
            state["cancelled"] = True; killed = True
        outputs = read_outputs(outfile)
        ctx["steps"][key] = {"outputs": outputs, "outcome": "success" if rc == 0 else "failure", "conclusion": "success" if rc == 0 else "failure"}
        results.append({"key": key, "outcome": "success" if rc == 0 else "failure", "rc": rc})
        if rc != 0:
            state["failed"] = True
        if killed:
            break
    job_outputs = {}
    for k, v in (wipe.get("outputs") or {}).items():
        try:
            job_outputs[k] = tostr(interp(v, ctx))
        except Exception as e:
            job_outputs[k] = "EVAL-ERROR:%s" % e
    result = "cancelled" if killed else ("failure" if state["failed"] else "success")
    res = {"steps": results, "job_result": result, "outputs": job_outputs, "killed": killed, "loader_ran": loader_ran,
           "secrets": [v for v in list(sec.values()) + list(loaded.values()) + [ro, rw]]}
    if spec.get("notify"):
        needs = {"cutover": {"result": "skipped", "outputs": {}}, "wipe": {"result": result, "outputs": job_outputs}}
        res["notify"] = notify_run(wf, needs, gh, run + "/notify", sec, {"volume_id": inputs["volume_id"], "mode": mode})
    open(run + "/result.json", "w").write(json.dumps(res))


NOTIFY_ENV_BASE = ["PATH", "HOME"]


def notify_run(wf, needs, gh, d, sec=None, inputs=None):
    os.makedirs(d + "/rt", exist_ok=True)
    nj = (wf.get("jobs") or {}).get("notify-failure") or {}
    ctx = {"needs": needs, "github": gh, "secrets": sec or {}, "steps": {}, "inputs": inputs or {}}
    try:
        cond = truthy(ev(str(nj.get("if") or "false"), ctx, {"failed": False, "cancelled": False}))
    except Exception as e:
        return {"if": None, "error": str(e)}
    body = next((s for s in (nj.get("steps") or []) if s.get("id") == "body"), None)
    if body is None:
        return {"if": cond, "error": "no body step"}
    env = {"PATH": "/usr/bin:/bin", "HOME": d, "RUNNER_TEMP": d + "/rt", "GITHUB_OUTPUT": d + "/gho", "LC_ALL": "C"}
    for k, v in (body.get("env") or {}).items():
        env[k] = tostr(interp(v, ctx))
    open(d + "/gho", "w").close()
    sh = d + "/body.sh"
    open(sh, "w").write(body.get("run") or "")
    p = subprocess.run(["bash", "--noprofile", "--norc", "-eo", "pipefail", sh], env=env, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60)
    nb = open(d + "/rt/notify-body.txt").read() if os.path.exists(d + "/rt/notify-body.txt") else ""
    return {"if": cond, "rc": p.returncode, "stdout": p.stdout.decode("utf-8", "replace"), "stderr": p.stderr.decode("utf-8", "replace"),
            "gho": open(d + "/gho").read(), "notify_body": nb}


def notify_cases_main(spec):
    wf = load_yaml(spec["wf"])
    out = []
    for i, c in enumerate(spec["cases"]):
        d = "%s/n%03d" % (spec["run"], i)
        os.makedirs(d, exist_ok=True)
        gh = {"run_id": c.get("run_id", "9000000123"), "server_url": "https://github.example", "repository": "example/repo"}
        needs = c["needs"]
        r = notify_run(wf, needs, gh, d, None, {"volume_id": c.get("volume_id", "")})
        r["id"] = c["id"]
        out.append(r)
    open(spec["out"], "w").write(json.dumps(out))


def step_cases_main(spec):
    """Run one real step body (job/step) for many synthesized input cases; no shims, an empty workspace."""
    wf = load_yaml(spec["wf"])
    job = (wf.get("jobs") or {}).get(spec["job"]) or {}
    step = next((s for s in (job.get("steps") or []) if skey(s) == spec["step"]), None)
    out = []
    for i, c in enumerate(spec["cases"]):
        d = "%s/c%03d" % (spec["run"], i)
        os.makedirs(d + "/rt", exist_ok=True)
        gho = d + "/gho"
        open(gho, "w").close()
        ctx = {"inputs": c["inputs"], "github": {"run_attempt": c.get("run_attempt", "1"), "run_id": "9000000123"}, "steps": {}, "env": {}}
        jobenv = {k: tostr(interp(v, ctx)) for k, v in (job.get("env") or {}).items()}
        env = {"PATH": "/usr/bin:/bin", "HOME": d, "RUNNER_TEMP": d + "/rt", "GITHUB_OUTPUT": gho, "LC_ALL": "C"}
        env.update(jobenv)
        for k, v in (step.get("env") or {}).items():
            env[k] = tostr(interp(v, ctx))
        sh = d + "/body.sh"
        open(sh, "w").write(step.get("run") or "")
        p = subprocess.run(["bash", "--noprofile", "--norc", "-eo", "pipefail", sh], env=env, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE, cwd=d, timeout=30)
        out.append({"id": c["id"], "rc": p.returncode, "stdout": p.stdout.decode("utf-8", "replace"), "gho": open(gho).read(), "stderr": p.stderr.decode("utf-8", "replace")})
    open(spec["out"], "w").write(json.dumps(out))



def S(step, old, new, count=1):
    return {"op": "sub", "step": step, "old": old, "new": new, "count": count}


def R(step, old, new, count=1):
    return {"op": "resub", "step": step, "old": old, "new": new, "count": count}


def J(job, old, new, count=1):
    return {"op": "sub", "job": job, "old": old, "new": new, "count": count}


def F(old, new, count=1):
    return {"op": "sub", "old": old, "new": new, "count": count}


def PRINT(x):
    return [S("wipe_confirm", '          case "$MODE" in\n', '          %s\n          case "$MODE" in\n' % x)]


EXTRA_BARE_STEP = "      - name: extra\n        id: wipe_extra\n        run: |\n          echo hi"
REMOTE_USES = "      - uses: DopplerHQ/cli-action@5351693ec144fc7f7a2d30025061acfc3c53c47c # v4"
GATE_MARK_FIRST = [
    S("wipe_detach_gate", '\n          echo "phase=detach_attempted" >> "$GITHUB_OUTPUT"\'', "'"),
    S("wipe_detach_gate", "            bash -c 'set -euo pipefail\n", "            bash -c 'set -euo pipefail\n          echo \"phase=detach_attempted\" >> \"$GITHUB_OUTPUT\"\n"),
]
DGATE_MARK_FIRST = [
    S("wipe_delete_gate", '\n          echo "phase=delete_attempted" >> "$GITHUB_OUTPUT"\'', "'"),
    S("wipe_delete_gate", "            bash -c 'set -euo pipefail\n", "            bash -c 'set -euo pipefail\n          echo \"phase=delete_attempted\" >> \"$GITHUB_OUTPUT\"\n"),
]
MODE_LIST = "proof|flip|rollback|unfreeze|redeploy|wipe|wipe_finish|wipe_check|wipe_unknown) ;; *) MODE=unknown ;; esac"

MUTANTS = {
    # Guard 1
    "g1-1-env-u": [S("wipe_detach", "exec env -i PATH=", "exec env -u HCLOUD_TOKEN PATH=")],
    "g1-2-cred-on-envi": [R("wipe_delete", r'(exec env -i [^\n]*VOLUME_ID="\$VOLUME_ID") \\\n', r'\1 HCLOUD_TOKEN="$HCLOUD_TOKEN" \\\n')],
    "g1-3-second-bare-step": [{"op": "insert_after", "step": "wipe_readback", "text": EXTRA_BARE_STEP}],
    "g1-4a-remote-uses-before-loader": [{"op": "insert_after", "step": "wipe_flag_reread", "text": REMOTE_USES}],
    "g1-4b-remote-uses-after-loader": [{"op": "insert_after", "step": "wipe_loader", "text": REMOTE_USES}],
    "g1-4c-install-version": [S("wipe_doppler_install", 'DOPPLER_CLI_VERSION: "3.75.3"', 'DOPPLER_CLI_VERSION: "3.75.4"')],
    "g1-4d-install-sha": [S("wipe_doppler_install", "9c840cdd32cffff06d", "9c840cdd32cffff06e")],
    "g1-5a-printenv": PRINT("printenv"),
    "g1-5b-export-p": PRINT("export -p"),
    "g1-5c-declare-x": PRINT("declare -x"),
    "g1-5d-bare-env": PRINT("env"),
    "g1-5e-bare-set": PRINT("set"),
    "g1-5f-compgen-e": PRINT("compgen -e"),
    "g1-6-first-statement": [S("wipe_delete", "          exec env -i PATH=", "          echo hi\n          exec env -i PATH=")],
    "g1-7a-post-hook": [F("runs:\n  using: composite\n", "runs:\n  using: composite\n  post: cleanup.sh\n")],
    "g1-7b-using-node": [F("  using: composite", "  using: node20")],
    "g1-8-empty-list": [S("wipe_loader", "id: wipe_loader", "id: wipe_loadx")],
    "g1-9-legacy-input": [S("wipe_loader", "doppler-token-infra-privileged: ${{ secrets.DOPPLER_TOKEN_INFRA_PRIVILEGED }}", "doppler-token-legacy: ${{ secrets.DOPPLER_TOKEN }}")],
    "g1-10-mask-blob": [F("while IFS= read -r line; do", "for line in $payload; do")],
    "g1-11-variant-reordered-lc-all": [R("wipe_reread", r'(exec env -i )(PATH="\$PATH" HOME="\$HOME") (RUNNER_TEMP="\$RUNNER_TEMP") (GITHUB_WORKSPACE="\$GITHUB_WORKSPACE") (GITHUB_OUTPUT="\$GITHUB_OUTPUT") (VOLUME_ID="\$VOLUME_ID") \\\n', r'\1VOLUME_ID="$VOLUME_ID" \5 \4 \3 LC_ALL="C" \2 \\\n')],
    # Guard 2
    "g2-2-host-after-detach": [{"op": "move_after", "step": "wipe_host_assert", "after": "wipe_detach"}],
    "g2-2b-host-read-after-detach": [{"op": "dup", "step": "wipe_host_assert", "after": "wipe_detach", "new_id": "wipe_host_assert2"}],
    "g2-3-second-read": [{"op": "dup", "step": "wipe_reread", "after": "wipe_reread", "new_id": "wipe_reread2"}],
    "g2-5a-gate-record-check-removed": [S("wipe_detach_gate", '          bash "$GITHUB_WORKSPACE/apps/web-platform/infra/git-data-wipe.sh" record_check --epoch w7 --volume-id "$VOLUME_ID"\n', "")],
    "g2-5c-dgate-record-check-removed": [S("wipe_delete_gate", '          bash "$GITHUB_WORKSPACE/apps/web-platform/infra/git-data-wipe.sh" record_check --epoch w10b --volume-id "$VOLUME_ID"\n', "")],
    "g2-8-finish-no-record": [S("wipe_identity", 'helper identity --expect detached --volume-id "$VOLUME_ID" --record write', 'helper identity --expect detached --volume-id "$VOLUME_ID"')],
    "g2h-5b-helper-w7-site": [F('  read_token rw\n  record_verify w7 "$VID"\n', "  read_token rw\n")],
    "g2h-5d-helper-w10b-site": [F('  read_token rw\n  record_verify w10b "$VID"\n', "  read_token rw\n")],
    "g2h-6-no-w10b-restamp": [F('      R_w10b_epoch="$NOW"\n      rec_save ;;', "      rec_save ;;")],
    "g2h-6b-w10b-from-w7": [F('w10b) e="$R_w10b_epoch"; bound="$WIPE_W10B_BOUND_SECONDS"', 'w10b) e="$R_w7_epoch"; bound="$WIPE_W10B_BOUND_SECONDS"')],
    # Guard 3
    "g3-1b-marker-before-checks": GATE_MARK_FIRST,
    "g3-1c-dmarker-before-checks": DGATE_MARK_FIRST,
    "g3-1d-marker-after-call-swap": [{"op": "swap", "a": "wipe_detach_gate", "b": "wipe_detach"}],
    "g3-2-merge-gate-into-detach": [{"op": "delete", "step": "wipe_detach_gate"}],
    "g3-3-chain-reordered": [J("wipe", "steps.wipe_readback.outputs.phase || steps.wipe_delete.outputs.phase", "steps.wipe_delete.outputs.phase || steps.wipe_readback.outputs.phase")],
    "g3-4-finish-not-in-list": [J("notify", MODE_LIST, MODE_LIST.replace("wipe|wipe_finish|wipe_check", "wipe|wipe_check"))],
    "g3-5-mode-before-refusal": [S("wipe_confirm", '          if ! [[ "$VOLUME_ID" =~ ^[0-9]{1,12}$ ]]; then\n', '          echo "mode=$MODE" >> "$GITHUB_OUTPUT"\n          if ! [[ "$VOLUME_ID" =~ ^[0-9]{1,12}$ ]]; then\n')],
    "g3-6-unfreeze-in-word": [J("notify", "VOLUME_DETACHED (the volume is detached and not deleted. Finish with:", "VOLUME_DETACHED (the volume is detached and not deleted. Re-dispatch mode=unfreeze. Finish with:")],
    "g3-7a-refusal-dropped": [J("notify", 'elif [ "${WIPE_REFUSAL:-}" = volume_already_detached ]; then', "elif false; then")],
    "g3-7b-no-finish-command": [J("notify", "If a wipe run detached it, finish with: ${finish_cmd_origin}, replacing ORIGIN_RUN_ID by the id of the wipe run that detached it; this run refused and is not that run)", "If a wipe run detached it, finish it.)")],
    "g3-8-phase-arm-removed": [J("notify", 'deleted) words=" VOLUME_DELETED_TEARDOWN_FAILED (the provider API read-back confirmed the volume is no longer listed; only the runner teardown failed afterwards)"; swords=" VOLUME_DELETED_TEARDOWN_FAILED" ;;', "")],
    # Guard 4
    "g4-1-cutover-if-operand": [F("    if: inputs.mode != 'wipe' && inputs.mode != 'wipe_finish' && inputs.mode != 'wipe_check'\n", "    if: inputs.mode != 'wipe' && inputs.mode != 'wipe_finish'\n")],
    "g4-2-fourth-mode": [F("options: [proof, flip, rollback, unfreeze, redeploy, wipe, wipe_finish, wipe_check]", "options: [proof, flip, rollback, unfreeze, redeploy, wipe, wipe_finish, wipe_check, wipe_force]")],
    "g4-3-volume-id-in-flip": [J("cutover", 'if [[ -n "${VOLUME_ID:-}" || -n "${ORIGIN_RUN:-}" ]]; then', 'if [[ ( -n "${VOLUME_ID:-}" || -n "${ORIGIN_RUN:-}" ) && "$MODE" != flip ]]; then')],
    "g4-4-attempt-in-one-mode": [S("wipe_confirm", 'if [[ "$RUN_ATTEMPT" != "1" ]]; then', 'if [[ "$RUN_ATTEMPT" != "1" && "$MODE" != "wipe_check" ]]; then')],
    "g4-5-runname-trailing-id": [F("|| format('git-data {0}', inputs.mode) }}", "|| format('git-data {0} {1}', inputs.mode, inputs.volume_id) }}")],
    "g4h-a-volume-id-input-deleted": [F('      volume_id:\n        description: "wipe modes only: the id of the plaintext volume named soleur-git-data-store (1 to 12 digits; the run refuses unless Hetzner names exactly this volume)."\n        required: false\n        type: string\n        default: ""\n', "")],
    # Guard 6 / 7 workflow side
    "g6-1-flag-mode-mapping": [S("wipe_flag_precheck", "mode == 'wipe_check' && 'wipe_check' || 'wipe' }}", "mode == 'wipe_check' && 'wipe' || 'wipe' }}")],
    "g7-1-precheck-removed": [{"op": "delete", "step": "wipe_flag_precheck"}],
    # Guard 8
    "g8-2a-forbidden-summary": [S("wipe_readback", "It does not state that the volume was empty or held no personal data;", "The volume was erased;")],
    "g8-2b-forbidden-notify-word": [J("notify", "only the runner teardown failed afterwards)", "only the runner teardown failed after the volume was wiped)")],
    "g8-names-echo": [S("wipe_host_assert", "          bash apps/web-platform/infra/git-data-cutover.sh\n", '          bash apps/web-platform/infra/git-data-cutover.sh\n          echo "$listing"\n')],
    "g8-3-helper-new-word": [F("  gho phase deleted\n", "  gho phase deleted\n  refuse wipe_zz_new_word\n")],
    # naming / misc
    "n-1a-detach-gate-name-differs": [S("wipe_detach_gate", "name: wipe_detach_gate", "name: Detach marker and W7-epoch bound (W9a)")],
    "n-1b-delete-gate-name-differs": [S("wipe_delete_gate", "name: wipe_delete_gate", "name: Delete marker and W10b-epoch bound (W11a)")],
    "n-2-chain-with-identity": [J("wipe", "|| steps.wipe_detach_gate.outputs.phase }}", "|| steps.wipe_detach_gate.outputs.phase || steps.wipe_identity.outputs.phase }}")],
    "g3-9a-wipe-unknown-not-in-family": [J("notify", 'case "$MODE" in wipe|wipe_finish|wipe_check|wipe_unknown)\n', 'case "$MODE" in wipe|wipe_finish|wipe_check)\n')],
    "g3-9b-lost-runner-setter-removed": [J("notify", 'if [ -z "$MODE" ] && [ "${CUTOVER_RESULT:-}" = skipped ]; then MODE=wipe_unknown; fi\n', "")],
    "g3-9c-wipe-unknown-not-in-whitelist": [J("notify", "wipe_check|wipe_unknown) ;; *) MODE=unknown ;; esac", "wipe_check) ;; *) MODE=unknown ;; esac")],
    # ---- review round 2: step keys, copies, the workflow-to-script contract, executed negatives ---------------------
    "c-step-env-bash-env": [S("wipe_delete", "        run: |\n          case", "        env:\n          BASH_ENV: ${{ github.workspace }}/hook\n        run: |\n          case")],
    "c-step-shell": [S("wipe_delete", "        run: |\n          case", "        shell: bash {0}\n        run: |\n          case")],
    "c-step-workdir": [S("wipe_delete", "        run: |\n          case", "        working-directory: /tmp\n        run: |\n          case")],
    "d-echo-tok": [S("wipe_delete", "          IFS= read -r tok\n", "          IFS= read -r tok\n          [[ ${#tok} -gt 4096 ]] && echo \"$tok\"\n")],
    "e-shkc-lax": [S("wipe_ssh_config", "StrictHostKeyChecking yes", "StrictHostKeyChecking " + "no", 2)],
    "e-forward-agent": [S("wipe_ssh_config", "ForwardAgent no", "ForwardAgent yes", 2)],
    "e-hostkeyalias": [S("wipe_ssh_config", "HostKeyAlias git-data", "HostKeyAlias web-1")],
    "e-updatehostkeys": [S("wipe_ssh_config", "UpdateHostKeys no", "UpdateHostKeys yes", 2)],
    "e-sha-dropped": [S("wipe_doppler_install", '          echo "${DOPPLER_CLI_SHA256}  $d/doppler.tar.gz" | sha256sum -c -\n', "")],
    "e-keyval-dropped": [S("wipe_key_fetch", '            [[ "$pub" == ssh-* ]] || reason=not_openssh_key\n', "            :\n")],
    "e-xtrace-identity": [S("wipe_identity", '          case "$-" in *x*) echo "::error::xtrace refused on a credential-bearing step (#7797)"; exit 78;; esac\n', "")],
    "b-w10-no-web-host-ssh": [S("wipe_post_detach_read", ' WEB_HOST_SSH="${WEB_HOST_SSH:-}"', "")],
    "g-w7-raw-id": [S("wipe_host_assert", "WIPE_VOLUME_ID=\"$(sed -n 's/^plaintext_id=//p' \"$rec\")\"", 'WIPE_VOLUME_ID="$VOLUME_ID"')],
    "g-w10-raw-id": [S("wipe_post_detach_read", 'WIPE_VOLUME_ID="$(sed -n "s/^plaintext_id=//p" "$rec")"', 'WIPE_VOLUME_ID="$VOLUME_ID"')],
    "a1-origin-exit5": [S("wipe_origin_check", '              echo "::error title=git-data-wipe::verdict=${v//[^a-z_]/?}"\n              exit 5\n', '              echo "::error title=git-data-wipe::verdict=${v//[^a-z_]/?}"\n')],
    "a1-origin-rc0": [S("wipe_origin_check", 'v="$(wipe_origin_run_ok "$j" "$VOLUME_ID" detach)" || rc=$?', 'v="$(wipe_origin_run_ok "$j" "$VOLUME_ID" detach)" || rc=0')],
    "a1-origin-wrong-run": [S("wipe_origin_check", 'gh run view "$ORIGIN_RUN" --json', 'gh run view "$GITHUB_RUN_ID" --json')],
    "a1-origin-no-jobs": [S("wipe_origin_check", "createdAt,workflowName,jobs)", "createdAt,workflowName)")],
    "a1-origin-no-workflowname": [S("wipe_origin_check", "createdAt,workflowName,jobs)", "createdAt,jobs)")],
    "a1-origin-delete-gate-open": [S("wipe_origin_check", 'wipe_origin_run_ok "$j" "$VOLUME_ID" delete >/dev/null || rc2=$?', 'wipe_origin_run_ok "$j" "$VOLUME_ID" delete >/dev/null || rc2=0')],
    "a2-precheck-exit5": [S("wipe_flag_precheck", '                echo "::error title=git-data-wipe::verdict=${gv//[^a-z_]/?}"\n                exit 5\n', '                echo "::error title=git-data-wipe::verdict=${gv//[^a-z_]/?}"\n')],
    "a2-wipemode-check": [S("wipe_flag_precheck", "WIPE_MODE: ${{ steps.wipe_confirm.outputs.mode }}", "WIPE_MODE: wipe_check")],
    "a2-runs-fallback-open": [S("wipe_flag_precheck", '              runs=""\n', '              runs="[]"\n')],
    "a2-limit-10": [S("wipe_flag_precheck", '--limit "${WIPE_RUNS_LIST_LIMIT:-100}"', "--limit 10")],
    "a2-no-event-field": [S("wipe_flag_precheck", "--json databaseId,displayTitle,createdAt,conclusion,headBranch,event)", "--json databaseId,displayTitle,createdAt,conclusion,headBranch)")],
    "a3-boot-exit5": [S("wipe_boot_read", '            echo "verdict=${v//[^a-z_]/?}" >> "$GITHUB_OUTPUT"\n            exit 5\n', '            echo "verdict=${v//[^a-z_]/?}" >> "$GITHUB_OUTPUT"\n')],
    "a3-created-zero": [S("wipe_boot_read", 'git_data_boot_fields_verdict "$rrc" "$rows" "$created"', 'git_data_boot_fields_verdict "$rrc" "$rows" 0')],
    "a3-rrc-zero": [S("wipe_boot_read", 'git_data_boot_fields_verdict "$rrc" "$rows" "$created"', 'git_data_boot_fields_verdict 0 "$rows" "$created"')],
    "a4-no-actions-call": [S("wipe_identity", '                helper actions --volume-id "$VOLUME_ID" --since "$ORIGIN_EPOCH"\n', "                true\n")],
    "a4-no-since": [S("wipe_identity", ' --since "$ORIGIN_EPOCH"', "")],
    "a4-never-detached": [S("wipe_identity", 'if [[ "$vs" == "detached" ]]; then', 'if [[ "$vs" == "never_true" ]]; then')],
    "a5-listing-skip": [S("wipe_host_assert", "WIPE_LISTING: ${{ steps.wipe_confirm.outputs.mode != 'wipe_finish' && 'run' || 'skip' }}", "WIPE_LISTING: skip")],
    "sep-scan-skipped": [S("wipe_flag_precheck", 'sv="$(git_data_store_dirty_list | GDSD_SELF_RUN_ID="$GITHUB_RUN_ID" git_data_store_dirty_scan)" || true', 'sv=store_clean')],
    "sep-srr-ignored": [S("wipe_host_assert", 'elif [[ "$srr" -ne 0 ]]; then', 'elif false; then')],
    "sep-reread-expect-dropped": [S("wipe_flag_reread", ' WIPE_VARIANT="$WIPE_VARIANT"', '')],
    "evidence-run-record-dropped": [S("wipe_readback", 'echo "### git-data wipe evidence, run record"', 'echo "### dropped"')],
    "a5-row-dt-empty": [S("wipe_host_assert", 'WIPE_ROW_DT="$WIPE_ROW_EPOCH"', 'WIPE_ROW_DT=""')],
    "a5-server-from-luks": [S("wipe_host_assert", "WIPE_SERVER_ID=\"$(sed -n 's/^server_id=//p' \"$rec\")\"", "WIPE_SERVER_ID=\"$(sed -n 's/^luks_id=//p' \"$rec\")\"")],
    "w10-rc-any": [S("wipe_post_detach_read", 'if [[ "$rc" -eq 5 ]] && ! grep -qE "^\\[git-data-cutover\\] STORE probe=[a-z-]+ verdict=probe_failed" "$out"; then echo "refusal=store_not_serving" >> "$GITHUB_OUTPUT"; fi', 'echo "refusal=store_not_serving" >> "$GITHUB_OUTPUT"')],
    "w10-probe-excl": [S("wipe_post_detach_read", ' && ! grep -qE "^\\[git-data-cutover\\] STORE probe=[a-z-]+ verdict=probe_failed" "$out"', "")],
    "w10-retry-removed": [S("wipe_post_detach_read", 'if [[ "$rc" -ne 0 ]] && unanswered; then', 'if false; then')],
    "w10-retry-verdict": [S("wipe_post_detach_read", '[[ "$rc" -eq 5 ]] && grep -qE "^\\[git-data-cutover\\] STORE probe=[a-z-]+ verdict=probe_failed" "$out" && return 0', '[[ "$rc" -eq 5 ]] && return 0')],
    "w10-retry-nosleep": [S("wipe_post_detach_read", "            sleep 10\n", "")],
    "w10-retry-first-decides": [S("wipe_post_detach_read", "            sleep 10\n            rc=0\n", "            sleep 10\n")],
    "w10-retry-no-access": [S("wipe_post_detach_read", '            [[ "$rc" -eq 3 ]] && return 0\n', "")],
    "t-install-maxtime-dropped": [S("wipe_doppler_install", " --max-time 120", "")],
    "t-install-connect-dropped": [S("wipe_doppler_install", " --connect-timeout 20", "")],
    "t-doppler-identity-dropped": [S("wipe_identity", "timeout 60 doppler", "doppler")],
    "t-doppler-reread-dropped": [S("wipe_reread", "timeout 60 doppler", "doppler")],
    "t-doppler-readback-dropped": [S("wipe_readback", "timeout 60 doppler", "doppler")],
    "t-gh-list-dropped": [S("wipe_flag_precheck", "timeout 60 gh run list", "gh run list")],
    "t-gh-view-dropped": [S("wipe_origin_check", "timeout 60 gh run view", "gh run view")],
    "nv-already-here": [J("notify", "finish with: ${finish_cmd_origin}, replacing", "finish with: ${finish_cmd_here}, replacing")],
    "w12-always-deleted": [S("wipe_readback", 'if [[ "$DELETE_PHASE" == "delete_sent" ]]; then', "if true; then")],
    "w12-standing-dropped": [S("wipe_readback", "This run does not address provider-side", "This run addresses provider-side")],
    "f-retention-closed": [S("wipe_readback", "It does not state that the volume was empty", "Retention closed. It does not state that the volume was empty")],
    "nv-vid-unvalidated": [J("notify", "case \"${WIPE_VOLUME_ID:-}\" in ''|*[!0-9]*) ;; *) if [ \"${#WIPE_VOLUME_ID}\" -le 12 ]; then vid=\"$WIPE_VOLUME_ID\"; fi ;; esac", 'vid="${WIPE_VOLUME_ID:-VOLUME_ID}"')],
    "nv-orig-always": [J("notify", 'if [ "$MODE" = wipe ]; then orig="$RUN_ID"; fi', 'orig="$RUN_ID"')],
    "nv-angle": [J("notify", "            vid=VOLUME_ID\n", "            vid='<VOLUME_ID>'\n")],
    "h-identity-phase": [F('  gho volume_state "$CLS"\n  gho luks_state attached\n  local ids=""', '  gho volume_state "$CLS"\n  gho phase detached\n  gho luks_state attached\n  local ids=""')],
}

def dump_main(spec):
    """Write one real step body (and its interpolated env:) of a job to <out>.sh / <out>.env.json for a bash-driven row."""
    wf = load_yaml(spec["wf"])
    job = (wf.get("jobs") or {}).get(spec["job"]) or {}
    step = next((s for s in (job.get("steps") or []) if skey(s) == spec["step"]), None)
    if step is None:
        raise SystemExit("dump: step %s not found" % spec["step"])
    ctx = dict(spec.get("ctx") or {})
    ctx["env"] = {k: tostr(interp(v, ctx)) for k, v in (wf.get("env") or {}).items()}
    env = {k: tostr(interp(v, ctx)) for k, v in (step.get("env") or {}).items()}
    open(spec["out"] + ".sh", "w").write(step.get("run") or "")
    json.dump(env, open(spec["out"] + ".env.json", "w"))


def main():
    if len(sys.argv) < 3:
        print("usage: wfsim.py census|mutate|sim|notify|cases|dump SPEC.json", file=sys.stderr); sys.exit(2)
    spec = json.load(open(sys.argv[2]))
    {"census": census_main, "mutate": mutate_main, "sim": sim_main, "notify": notify_cases_main, "cases": step_cases_main, "dump": dump_main}[sys.argv[1]](spec)


if __name__ == "__main__":
    main()
PYEOF
PY=(python3 -I "$T/wfsim.py")
# The forbidden-phrase ERE and the one whitelisted sentence: read out of the module the census uses (one source, two scanners).
FORBID_ERE="$(python3 -I -c 'import importlib.util,sys; sp=importlib.util.spec_from_file_location("w",sys.argv[1]); m=importlib.util.module_from_spec(sp); sp.loader.exec_module(m); print(m.FORBIDDEN_SRC)' "$T/wfsim.py")"
STANDING_TXT="$(python3 -I -c 'import importlib.util,sys; sp=importlib.util.spec_from_file_location("w",sys.argv[1]); m=importlib.util.module_from_spec(sp); sp.loader.exec_module(m); print(m.STANDING)' "$T/wfsim.py")"
[ -n "$FORBID_ERE" ] && [ -n "$STANDING_TXT" ] || { printf 'FAIL SETUP: the forbidden-phrase source is empty\n' >&2; exit 1; }
# forbidden <text>: 0 (true) when the text carries a forbidden phrase once the exact standing sentence is removed
forbidden() { local t="${1-}"; t="${t//"$STANDING_TXT"/}"; grep -qiE -- "$FORBID_ERE" <<<"$t"; }

# jmk <out> k=v ...: a flat JSON object; a value starting json: is spliced as JSON, anything else is a string.
jmk() {
  local out="$1"; shift
  local s='{' sep='' kv k v
  for kv in "$@"; do
    k="${kv%%=*}"; v="${kv#*=}"
    case "$v" in
      json:*) s+="${sep}\"${k}\":${v#json:}" ;;
      *) v="${v//\\/\\\\}"; v="${v//\"/\\\"}"; s+="${sep}\"${k}\":\"${v}\"" ;;
    esac
    sep=,
  done
  assert_fixture_dir "$out"
  printf '%s}\n' "$s" > "$out"
}

PHASES_JSON="$(env -i PATH="$PATH" HOME="$T" RUNNER_TEMP="$T" GITHUB_WORKSPACE="$ROOT" bash "$HELPER" phases 2>/dev/null | jq -R -s -c 'split("\n")|map(select(.!=""))')"
[ -n "$PHASES_JSON" ] || { printf 'FAIL SETUP: helper phases verb unreadable\n' >&2; exit 1; }

# census: run the python census over (a copy of) the workflow/actions/helper; rows land in $CZ_OUT
CZ_OUT=""
cz() { # <name> [k=v ...]
  local name="$1"; shift
  CZ_OUT="$T/cz/$name.out"
  jmk "$T/cz/$name.json" wf="$WF" loader="$LOADER" bridge="$BRIDGE" helper="$HELPER" lib="$LIB" host_assert="$HOST_ASSERT" host_verb="$HOST_VERB" \
    precheck="$PRECHECK" boot_lib="$BOOT_LIB" runbook="$RUNBOOK" phases="json:$PHASES_JSON" out="$CZ_OUT" "$@"
  if ! "${PY[@]}" census "$T/cz/$name.json" 2> "$T/cz/$name.err"; then
    fail "census run $name crashed" "$(tail -c 300 "$T/cz/$name.err")"; return 1
  fi
}
red() { grep -qF -- "FAIL"$'\t'"$2" "$1"; }          # <rows-file> <row-name-prefix incl. colon>
fail_names() { grep -F -- "FAIL"$'\t' "$1" | cut -f2 | cut -d: -f1 | sort | tr '\n' ' '; }

# mutate <name> <src> [ops-json]: a copy of <src> edited by the named (or inline) ops; asserts the edit LANDED
declare -A WANT=(
  [g1-1-env-u]=2 [g1-2-cred-on-envi]=2 [g1-3-second-bare-step]=4 [g1-4a-remote-uses-before-loader]=1 [g1-4b-remote-uses-after-loader]=1
  [g1-4c-install-version]=2 [g1-4d-install-sha]=2 [g1-5a-printenv]=1 [g1-5b-export-p]=1 [g1-5c-declare-x]=1 [g1-5d-bare-env]=1
  [g1-5e-bare-set]=1 [g1-5f-compgen-e]=1 [g1-6-first-statement]=1 [g1-7a-post-hook]=1 [g1-7b-using-node]=2 [g1-8-empty-list]=2
  [g1-9-legacy-input]=2 [g1-10-mask-blob]=2 [g1-11-variant-reordered-lc-all]=2 [g2-2-host-after-detach]=118 [g2-2b-host-read-after-detach]=72 [g2-3-second-read]=14
  [g2-5a-gate-record-check-removed]=1 [g2-5c-dgate-record-check-removed]=1 [g2-8-finish-no-record]=2 [g2h-5b-helper-w7-site]=1
  [g2h-5d-helper-w10b-site]=1 [g2h-6-no-w10b-restamp]=1 [g2h-6b-w10b-from-w7]=2 [g3-1b-marker-before-checks]=4 [g3-1c-dmarker-before-checks]=4
  [g3-1d-marker-after-call-swap]=34 [g3-2-merge-gate-into-detach]=15 [g3-3-chain-reordered]=2 [g3-4-finish-not-in-list]=2
  [g3-5-mode-before-refusal]=1 [g3-6-unfreeze-in-word]=2 [g3-7a-refusal-dropped]=2 [g3-7b-no-finish-command]=2 [g3-8-phase-arm-removed]=2
  [g4-1-cutover-if-operand]=2 [g4-2-fourth-mode]=2 [g4-3-volume-id-in-flip]=2 [g4-4-attempt-in-one-mode]=2 [g4-5-runname-trailing-id]=2
  [g4h-a-volume-id-input-deleted]=5 [g6-1-flag-mode-mapping]=2 [g7-1-precheck-removed]=80 [g8-2a-forbidden-summary]=2
  [g8-2b-forbidden-notify-word]=2 [g8-names-echo]=1 [g8-3-helper-new-word]=1 [n-1a-detach-gate-name-differs]=2 [n-1b-delete-gate-name-differs]=2 [n-2-chain-with-identity]=2 [g3-9a-wipe-unknown-not-in-family]=2 [g3-9b-lost-runner-setter-removed]=3 [g3-9c-wipe-unknown-not-in-whitelist]=2
  [c-step-env-bash-env]=2 [c-step-shell]=1 [c-step-workdir]=1 [d-echo-tok]=1 [e-shkc-lax]=4 [e-forward-agent]=4 [e-hostkeyalias]=2 [e-updatehostkeys]=4
  [e-sha-dropped]=1 [e-keyval-dropped]=2 [e-xtrace-identity]=1 [b-w10-no-web-host-ssh]=2 [g-w7-raw-id]=2 [g-w10-raw-id]=2
  [a1-origin-exit5]=1 [a1-origin-rc0]=2 [a1-origin-wrong-run]=2 [a1-origin-no-jobs]=2 [a1-origin-no-workflowname]=2 [a1-origin-delete-gate-open]=2
  [a2-precheck-exit5]=1 [a2-wipemode-check]=2 [a2-runs-fallback-open]=2 [a2-limit-10]=2 [a2-no-event-field]=2
  [a3-boot-exit5]=1 [a3-created-zero]=2 [a3-rrc-zero]=2 [a4-no-actions-call]=2 [a4-no-since]=2 [a4-never-detached]=2
  [a5-listing-skip]=2 [a5-row-dt-empty]=2 [a5-server-from-luks]=2 [w10-rc-any]=2 [w10-probe-excl]=2 [nv-already-here]=2 [w12-always-deleted]=2 [w12-standing-dropped]=2
  [w10-retry-removed]=2 [w10-retry-verdict]=2 [w10-retry-nosleep]=1 [w10-retry-first-decides]=1 [w10-retry-no-access]=1
  [t-install-maxtime-dropped]=2 [t-install-connect-dropped]=2 [t-doppler-identity-dropped]=2 [t-doppler-reread-dropped]=2 [t-doppler-readback-dropped]=2
  [t-gh-list-dropped]=2 [t-gh-view-dropped]=2 [sep-scan-skipped]=2 [sep-srr-ignored]=2 [sep-reread-expect-dropped]=2 [evidence-run-record-dropped]=2
  [f-retention-closed]=2 [nv-vid-unvalidated]=2 [nv-orig-always]=2 [nv-angle]=2 [h-identity-phase]=1
)
MUT_FILE=""
mutate() { # <name> <src> [ops-json]
  local name="$1" src="$2" ops="${3:-}" dst got want
  dst="$T/mut/$name.${src##*.}"
  assert_fixture_dir "$T/mut"
  if [ -n "$ops" ]; then jmk "$T/mut/$name.json" src="$src" dst="$dst" ops="json:$ops"; want="+"
  else jmk "$T/mut/$name.json" src="$src" dst="$dst" named="$name"; want="${WANT[$name]:-}"; fi
  if ! "${PY[@]}" mutate "$T/mut/$name.json" 2> "$T/mut/$name.err"; then
    fail "M-$name: the mutation did not apply" "$(tail -c 200 "$T/mut/$name.err")"; return 1
  fi
  got="$(diff "$src" "$dst" | grep -cE '^[<>]' || true)"
  if [ "${src%.sh}" != "$src" ] && ! bash -n "$dst" 2>/dev/null; then
    fail "M-$name: the mutant does not parse (bash -n): it would go RED for the wrong reason"; return 1
  fi
  if [ "$want" = "+" ]; then
    [ "$got" -ge 1 ] || { fail "M-$name: the mutation changed nothing (0 diff lines)"; return 1; }
  elif [ "$got" != "$want" ]; then
    fail "M-$name: mutation landed on $got diff line(s), expected ${want:-<unset>}"; return 1
  fi
  MUT_FILE="$dst"; MUTANTS_RUN=$((MUTANTS_RUN + 1))
  pass "M-$name: mutation landed on exactly $got diff line(s) of a pristine copy"
}
# cmut <name> <wf|loader|bridge|helper> <row-prefix>...: the named census rows must go RED against the mutant
cmut() {
  local name="$1" kind="$2" src ov r; shift 2
  case "$kind" in
    wf) src="$WF"; ov=wf ;; loader) src="$LOADER"; ov=loader ;; bridge) src="$BRIDGE"; ov=bridge ;; helper) src="$HELPER"; ov=helper ;;
    *) fail "cmut: bad kind $kind"; return 1 ;;
  esac
  mutate "$name" "$src" || return 1
  cz "m-$name" "$ov=$MUT_FILE" || return 1
  for r in "$@"; do
    if red "$CZ_OUT" "$r"; then pass "M-$name: census row ${r%%:*} goes RED"
    else fail "M-$name: census row ${r%%:*} stayed GREEN against the mutant" "$(fail_names "$CZ_OUT")"; fi
  done
}

echo "-- A. census of the live workflow --"
cz pristine || { printf 'FAIL: the census could not run\n' >&2; exit 1; }
ROWS_N=0
while IFS=$'\t' read -r st name detail; do
  ROWS_N=$((ROWS_N + 1))
  if [ "$st" = ok ]; then pass "$name"; else fail "$name" "$detail"; fi
done < "$CZ_OUT"
PRISTINE_OUT="$CZ_OUT"; PRISTINE_FAILS="$(fail_names "$PRISTINE_OUT")"
STEPS_LIVE="$(wc -l < "$PRISTINE_OUT.steps" | tr -d ' ')"
POST_LIVE="$(awk 'f{n++} $0=="wipe_loader"{f=1} END{print n+0}' "$PRISTINE_OUT.steps")"
WORDS_LIVE="$(wc -l < "$PRISTINE_OUT.words" | tr -d ' ')"
NWORDS_LIVE="$(wc -l < "$PRISTINE_OUT.nwords" | tr -d ' ')"
PAIRS_LIVE=$(( $(wc -l < "$PRISTINE_OUT.chain" | tr -d ' ') - 1 ))
printf '  info steps=%s post-loader=%s verdict-words=%s notify-words=%s chain-pairs=%s census-rows=%s\n' "$STEPS_LIVE" "$POST_LIVE" "$WORDS_LIVE" "$NWORDS_LIVE" "$PAIRS_LIVE" "$ROWS_N"
printf '  info wipe_* verdict words derived from the code:\n'; sed 's/^/    /' "$PRISTINE_OUT.words" | tr '\n' ' ' | fold -w 150 -s; printf '\n  info notify words: %s\n' "$(tr '\n' ' ' < "$PRISTINE_OUT.nwords")"

# the mutator must refuse an edit that does not land (a mutation that silently matched nothing would read as a pass)
jmk "$T/mut/selftest.json" src="$WF" dst="$T/mut/selftest.yml" ops='json:[{"op":"sub","old":"this text is not in the workflow","new":"x","count":1}]'
if ! "${PY[@]}" mutate "$T/mut/selftest.json" 2>/dev/null && [ ! -s "$T/mut/selftest.yml" ]; then pass "H0: the mutator refuses an edit that matches nothing (no silent no-op mutant)"; else fail "H0: a non-matching mutation was accepted"; fi
echo "-- B. harness rows (the census must not be vacuous) --"
# (a) a suite edit that stubs the step enumerator to return only W9 must go RED on the floor row
STUB_OUT="$T/cz/stub-enum.out"
jmk "$T/cz/stub-enum.json" wf="$WF" loader="$LOADER" bridge="$BRIDGE" helper="$HELPER" lib="$LIB" host_assert="$HOST_ASSERT" host_verb="$HOST_VERB" precheck="$PRECHECK" boot_lib="$BOOT_LIB" runbook="$RUNBOOK" phases="json:$PHASES_JSON" out="$STUB_OUT"
if WS_STUB_ENUM=wipe_detach "${PY[@]}" census "$T/cz/stub-enum.json" 2>/dev/null && red "$STUB_OUT" "G1-floor:" && red "$STUB_OUT" "G1-post-set:"; then
  pass "H1a: an enumerator stubbed to return only W9 goes RED on the post-loader floor row and the set-identity row"
else fail "H1a: the stubbed enumerator did not turn the floor RED"; fi
# (b) must-PASS: a differently ordered but compliant allow-list plus an extra non-secret name (LC_ALL)
mutate g1-11-variant-reordered-lc-all "$WF" && {
  cz m-variant wf="$MUT_FILE"
  if [ "$(fail_names "$CZ_OUT")" = "$PRISTINE_FAILS" ] && grep -qF 'LC_ALL' "$MUT_FILE"; then
    pass "H1b: a reordered compliant allow-list with an extra LC_ALL name keeps the census exactly as it was (no new RED row)"
  else fail "H1b: the compliant variant changed the census" "$(fail_names "$CZ_OUT") vs $PRISTINE_FAILS"; fi
}
# unit rows on the allow-list parser itself (both directions)
cat > "$T/unit.py" <<'UEOF'
import importlib.util, sys
sp = importlib.util.spec_from_file_location("w", sys.argv[1]); m = importlib.util.module_from_spec(sp); sp.loader.exec_module(m)
good = ['exec env -i PATH="$PATH" HOME="$HOME" VOLUME_ID="$VOLUME_ID" bash -c x',
        'exec env -i VOLUME_ID="$VOLUME_ID" LC_ALL=C PATH="$PATH" bash -c x',
        'exec env -i PATH="$PATH" LC_ALL="${LC_ALL:-C}" MODE=wipe_assert bash -c x']
bad = ['exec env -i PATH="$PATH" HCLOUD_TOKEN="$HCLOUD_TOKEN" bash -c x', 'exec env -i PATH="$PATH" X="$tok" bash -c x',
       'exec env -i PATH="$PATH" TF_VAR_a=1 bash -c x', 'exec env -i AWS_REGION=x bash -c x', 'exec env -i DOPPLER_TOKEN="$DOPPLER_TOKEN" bash -c x',
       'exec env -u HCLOUD_TOKEN PATH="$PATH" bash -c x', 'exec env -i PATH="$PATH" S="$DOPPLER_TOKEN_TF" bash -c x']
g = [m.check_envi(s)[0] for s in good]; b = [m.check_envi(s)[0] for s in bad]
print("%d/%d %d/%d" % (sum(g), len(g), sum(1 for x in b if not x), len(b)))
UEOF
_u="$(python3 -I "$T/unit.py" "$T/wfsim.py" 2>&1)"
[ "$_u" = "3/3 7/7" ] && pass "H1c: the env -i allow-list parser accepts the 3 compliant variants and rejects all 7 credential variants" || fail "H1c: allow-list parser unit rows" "$_u"
_u2="$(python3 -I - "$T/wfsim.py" <<'UEOF'
import importlib.util, sys
sp = importlib.util.spec_from_file_location("w", sys.argv[1]); m = importlib.util.module_from_spec(sp); sp.loader.exec_module(m)
hit = ["printenv", "env", "env | sort", "set", "export -p", "declare -x", "compgen -e", "x=$(printenv)", "cat /proc/self/environ", "typeset -x", "export"]
miss = ["set -euo pipefail", "set +e", "env -i PATH=x bash", "exec env -i PATH=x bash -c y", "export FOO=1", "echo environment", "doppler secrets get X --plain"]
h = [bool(m.env_printers(s)) for s in hit]; ms = [bool(m.env_printers(s)) for s in miss]
print("%d/%d %d/%d" % (sum(h), len(h), sum(1 for x in ms if not x), len(miss)))
UEOF
)"
[ "$_u2" = "11/11 7/7" ] && pass "H1d: the environment-printer detector flags all 11 printing forms and none of the 7 ordinary forms" || fail "H1d: env-printer unit rows" "$_u2"

echo "-- C. census mutants (Guards 1-8): each mutation must LAND, then the named row must go RED --"
# Guard 1
cmut g1-1-env-u wf "G1-exec-first:"
cmut g1-2-cred-on-envi wf "G1-no-cred-on-envi:"
cmut g1-3-second-bare-step wf "G1-exec-first:" "G1-post-set:" "WS-order:"
cmut g1-4a-remote-uses-before-loader wf "G1-uses-set:"
cmut g1-4b-remote-uses-after-loader wf "G1-uses-set:" "G1-exec-first:"
cmut g1-4c-install-version wf "G1-install-literals:"
cmut g1-4d-install-sha wf "G1-install-literals:"
cmut g1-5a-printenv wf "G1-no-env-print:"
cmut g1-5b-export-p wf "G1-no-env-print:"
cmut g1-5c-declare-x wf "G1-no-env-print:"
cmut g1-5d-bare-env wf "G1-no-env-print:"
cmut g1-5e-bare-set wf "G1-no-env-print:"
cmut g1-5f-compgen-e wf "G1-no-env-print:"
cmut g1-6-first-statement wf "G1-exec-first:"
cmut g1-7a-post-hook loader "G1-actions-composite:"
cmut g1-7b-using-node bridge "G1-actions-composite:"
cmut g1-8-empty-list wf "G1-floor:"
cmut g1-9-legacy-input wf "G1-loader-once:"
cmut g1-10-mask-blob loader "G1-loader-mask:"
# Guard 2 (static halves; the executed halves are in section F)
cmut g2-5a-gate-record-check-removed wf "G2-record-check-sites:"
cmut g2-5c-dgate-record-check-removed wf "G2-record-check-sites:" "G2-delete-gate-order:"
cmut g2-8-finish-no-record wf "G2-finish-record:"
cmut g2h-5b-helper-w7-site helper "G2-helper-sites:"
cmut g2h-5d-helper-w10b-site helper "G2-helper-sites:"
cmut g2h-6-no-w10b-restamp helper "G2-w10b-restamp:"
cmut g2h-6b-w10b-from-w7 helper "G2-w10b-restamp:"
# Guard 3
cmut g3-1b-marker-before-checks wf "G3-marker-last:" "G1-tier-b-gate:"
cmut g3-1c-dmarker-before-checks wf "G3-marker-last:" "G2-delete-gate-order:"
cmut g3-1d-marker-after-call-swap wf "WS-order:" "G2-pairs:"
cmut g3-2-merge-gate-into-detach wf "G3-marker-own-steps:" "WS-order:"
cmut g3-3-chain-reordered wf "G3-outputs:" "G3-phase-chain-eval:"
cmut g3-4-finish-not-in-list wf "G3-notify-case-list:"
cmut g3-6-unfreeze-in-word wf "G3-notify-wipe-block:"
cmut g3-7b-no-finish-command wf "G3-notify-refusal-map:"
cmut g3-8-phase-arm-removed wf "G3-notify-phase-map:"
# Guard 4
cmut g4-1-cutover-if-operand wf "WS-wipe-if:" "G4-surface:"
cmut g4-2-fourth-mode wf "WS-modes:" "G4-surface:"
cmut g4-3-volume-id-in-flip wf "G4-cutover-confirm:"
cmut g4-5-runname-trailing-id wf "WS-runname:" "WS-runname-eval:"
cmut g4h-a-volume-id-input-deleted wf "WS-inputs:"
# Guards 6/7 (workflow side)
cmut g6-1-flag-mode-mapping wf "G6-flag-mode:"
cmut g7-1-precheck-removed wf "G6-flag-mode:" "G7-precheck-first:" "WS-order:"
# Guard 8
cmut g8-2a-forbidden-summary wf "G8-forbidden:"
cmut g8-2b-forbidden-notify-word wf "G8-forbidden:"
cmut g8-names-echo wf "G8-no-names:"
cmut g8-3-helper-new-word helper "G8-parity:"
# the naming contract with the run lib and the identity phase in the chain are permanent pins now
cmut n-1a-detach-gate-name-differs wf "WS-naming-steps:"
cmut n-1b-delete-gate-name-differs wf "WS-naming-steps:"
cmut n-2-chain-with-identity wf "G3-outputs:" "G3-phase-writers:" "G3-phase-chain-eval:"
cmut g3-9a-wipe-unknown-not-in-family wf "G3-notify-wipe-block:"
cmut g3-9b-lost-runner-setter-removed wf "G3-notify-lost-runner:"
cmut g3-9c-wipe-unknown-not-in-whitelist wf "G3-notify-case-list:"
# round 2 (static halves; the executed halves are in sections D, E, F and G): step keys, copies, the env contract, ids
cmut c-step-env-bash-env wf "G1-step-env-names:"
cmut c-step-shell wf "G1-step-keys:"
cmut c-step-workdir wf "G1-step-keys:"
cmut d-echo-tok wf "G8-no-names:"
cmut e-shkc-lax wf "WS-copy-parity:"
cmut e-forward-agent wf "WS-copy-parity:"
cmut e-hostkeyalias wf "WS-copy-parity:"
cmut e-updatehostkeys wf "WS-copy-parity:"
cmut e-sha-dropped wf "G1-install-verifies:"
cmut t-install-maxtime-dropped wf "G1-timeout-install:"
cmut t-install-connect-dropped wf "G1-timeout-install:"
cmut t-doppler-identity-dropped wf "G1-timeout-doppler:"
cmut t-doppler-reread-dropped wf "G1-timeout-doppler:"
cmut t-doppler-readback-dropped wf "G1-timeout-doppler:"
cmut t-gh-list-dropped wf "G1-timeout-gh:"
cmut t-gh-view-dropped wf "G1-timeout-gh:"
cmut w10-retry-removed wf "G10-retry-once:"
cmut w10-retry-verdict wf "G10-retry-once:"
cmut w10-retry-nosleep wf "G10-retry-once:"
cmut w10-retry-no-access wf "G10-retry-once:"
cmut e-keyval-dropped wf "G1-key-validated:" "WS-copy-parity:"
cmut e-xtrace-identity wf "G1-xtrace-all:"
cmut b-w10-no-web-host-ssh wf "G10-env-contract:"
cmut g-w7-raw-id wf "G7-record-ids:"
cmut g-w10-raw-id wf "G7-record-ids:"
cmut a2-limit-10 wf "G6-limit-parity:"
cmut a2-no-event-field wf "G6-limit-parity:"
cmut a5-listing-skip wf "G7-listing-env:"
cmut a5-row-dt-empty wf "G7-listing-env:"
cmut w10-rc-any wf "G10-store-not-serving-rc5:"
cmut w10-probe-excl wf "G10-store-not-serving-rc5:"
cmut nv-already-here wf "G3-notify-refusal-map:"
cmut w12-always-deleted wf "G8-w12-conditional:"
cmut w12-standing-dropped wf "G8-standing:"
cmut f-retention-closed wf "G8-forbidden:"
cmut nv-vid-unvalidated wf "G3-notify-finish-cmd:"
cmut nv-orig-always wf "G3-notify-finish-cmd:"
cmut nv-angle wf "G3-notify-finish-cmd:"
cmut h-identity-phase helper "G3-identity-no-phase:"

echo "-- D. W1 and the cutover confirm step, EXECUTED over the real run: text --"
NCASES=()
addcase() { # <id> <mode> <confirm> <volume_id> <origin_run> <lineage> <attempt>
  NCASES+=("$(jq -nc --arg id "$1" --arg m "$2" --arg c "$3" --arg v "$4" --arg o "$5" --arg l "$6" --arg a "$7" '{id:$id,run_attempt:$a,inputs:{mode:$m,confirm:$c,volume_id:$v,origin_run:$o,lineage:$l}}')")
}
W_OK=(); W_REF=()
declare -A W_MODE=()
okc() { addcase "$@"; W_OK+=("$1"); W_MODE["$1"]="$2"; }
refc() { addcase "$@"; W_REF+=("$1"); }
okc ok-wipe-1 wipe WIPE-GIT-DATA 1 "" "" 1
okc ok-wipe-12 wipe WIPE-GIT-DATA 123456789012 "" "" 1
okc ok-wipe-zeros wipe WIPE-GIT-DATA 000000000001 "" "" 1
okc ok-finish wipe_finish WIPE-FINISH-GIT-DATA 42 777 "" 1
okc ok-finish-15 wipe_finish WIPE-FINISH-GIT-DATA 42 123456789012345 "" 1
okc ok-check wipe_check WIPE-CHECK-GIT-DATA 42 "" "" 1
refc r-mode-proof proof CUTOVER-GIT-DATA 42 "" "" 1
refc r-mode-unknown wipe_all WIPE-GIT-DATA 42 "" "" 1
refc r-tok-wrong wipe WIPE-FINISH-GIT-DATA 42 "" "" 1
refc r-tok-finish wipe_finish WIPE-GIT-DATA 42 777 "" 1
refc r-tok-check wipe_check WIPE-GIT-DATA 42 "" "" 1
refc r-tok-lower wipe wipe-git-data 42 "" "" 1
refc r-tok-empty wipe "" 42 "" "" 1
refc r-lineage-wipe wipe WIPE-GIT-DATA 42 "" cutover-1 1
refc r-lineage-finish wipe_finish WIPE-FINISH-GIT-DATA 42 777 cutover-1 1
refc r-lineage-check wipe_check WIPE-CHECK-GIT-DATA 42 "" cutover-1 1
refc r-vol-empty wipe WIPE-GIT-DATA "" "" "" 1
refc r-vol-13 wipe WIPE-GIT-DATA 1234567890123 "" "" 1
refc r-vol-alpha wipe WIPE-GIT-DATA abc "" "" 1
refc r-vol-mixed wipe WIPE-GIT-DATA 12a "" "" 1
refc r-vol-space wipe WIPE-GIT-DATA "1 2" "" "" 1
refc r-vol-neg wipe WIPE-GIT-DATA -1 "" "" 1
refc r-vol-newline wipe WIPE-GIT-DATA $'1\n2' "" "" 1
refc r-vol-inject wipe WIPE-GIT-DATA '1;touch x' "" "" 1
refc r-vol-finish wipe_finish WIPE-FINISH-GIT-DATA "" 777 "" 1
refc r-vol-check wipe_check WIPE-CHECK-GIT-DATA 1234567890123 "" "" 1
refc r-origin-on-wipe wipe WIPE-GIT-DATA 42 777 "" 1
refc r-origin-on-check wipe_check WIPE-CHECK-GIT-DATA 42 777 "" 1
refc r-origin-empty wipe_finish WIPE-FINISH-GIT-DATA 42 "" "" 1
refc r-origin-alpha wipe_finish WIPE-FINISH-GIT-DATA 42 abc "" 1
refc r-origin-16 wipe_finish WIPE-FINISH-GIT-DATA 42 1234567890123456 "" 1
refc r-attempt-2-wipe wipe WIPE-GIT-DATA 42 "" "" 2
refc r-attempt-2-finish wipe_finish WIPE-FINISH-GIT-DATA 42 777 "" 2
refc r-attempt-2-check wipe_check WIPE-CHECK-GIT-DATA 42 "" "" 2
refc r-attempt-empty wipe WIPE-GIT-DATA 42 "" "" ""
refc r-attempt-0 wipe WIPE-GIT-DATA 42 "" "" 0
refc r-attempt-11 wipe WIPE-GIT-DATA 42 "" "" 11
W1_CASES_N=${#NCASES[@]}
w1_run() { # <name> <workflow>: prints the number of mismatching cases
  local name="$1" wfp="$2" id bad=0 line rc gho want n
  local jf="$T/cases/$name.cases.json"
  printf '%s\n' "${NCASES[@]}" | jq -s . > "$jf"
  jmk "$T/cases/$name.spec.json" wf="$wfp" job=wipe step=wipe_confirm run="$T/cases/$name" out="$T/cases/$name.out" cases="json:$(cat "$jf")"
  mkdir -p "$T/cases/$name"
  if ! "${PY[@]}" cases "$T/cases/$name.spec.json" 2> "$T/cases/$name.err"; then echo "CRASH"; return; fi
  for id in "${W_OK[@]}"; do
    line="$(jq -r --arg id "$id" '.[]|select(.id==$id)|"\(.rc)|\(.gho|@json)"' "$T/cases/$name.out")"
    rc="${line%%|*}"; gho="${line#*|}"
    want="\"mode=${W_MODE[$id]}\\n\""
    if [ "$rc" != 0 ] || [ "$gho" != "$want" ]; then bad=$((bad + 1)); fi
  done
  for id in "${W_REF[@]}"; do
    line="$(jq -r --arg id "$id" '.[]|select(.id==$id)|"\(.rc)|\(.gho|@json)"' "$T/cases/$name.out")"
    rc="${line%%|*}"; gho="${line#*|}"
    if [ "$rc" = 0 ] || [ "$gho" != '""' ]; then bad=$((bad + 1)); fi
  done
  n=$((${#W_OK[@]} + ${#W_REF[@]}))
  echo "$bad"
}
_b="$(w1_run pristine "$WF")"
[ "$_b" = 0 ] && pass "W1: all $W1_CASES_N cases behave (${#W_OK[@]} accepted write exactly one mode= line, ${#W_REF[@]} refused write none; 12 digits with leading zeros pass; lineage, bad ids, origin_run misuse and attempt != 1 refused)" || fail "W1: $_b of $W1_CASES_N executed cases misbehaved" "see $T/cases/pristine.out"
for _m in g3-5-mode-before-refusal g4-4-attempt-in-one-mode; do
  mutate "$_m" "$WF" && { _b="$(w1_run "m-$_m" "$MUT_FILE")"
    if [ "$_b" != 0 ] && [ "$_b" != CRASH ]; then pass "M-$_m: the executed W1 table goes RED ($_b case(s) misbehave)"; else fail "M-$_m: the executed W1 table stayed GREEN" "$_b"; fi; }
done
# the cutover confirm step: volume_id and origin_run refused for EVERY mode it serves
NCASES=(); W_OK=(); W_REF=()
for _pair in proof:CUTOVER-GIT-DATA flip:FLIP-GIT-DATA rollback:ROLLBACK-GIT-DATA unfreeze:UNFREEZE-GIT-DATA redeploy:REDEPLOY-GIT-DATA; do
  _mo="${_pair%%:*}"; _tk="${_pair#*:}"
  okc "ok-$_mo" "$_mo" "$_tk" "" "" "" 1
  refc "r-vol-$_mo" "$_mo" "$_tk" 42 "" "" 1
  refc "r-origin-$_mo" "$_mo" "$_tk" "" 42 "" 1
done
CC_N=${#NCASES[@]}
cc_run() { # <name> <workflow>
  local name="$1" wfp="$2" id bad=0 line rc gho
  printf '%s\n' "${NCASES[@]}" | jq -s . > "$T/cases/$name.cases.json"
  mkdir -p "$T/cases/$name"
  jmk "$T/cases/$name.spec.json" wf="$wfp" job=cutover step=confirm run="$T/cases/$name" out="$T/cases/$name.out" cases="json:$(cat "$T/cases/$name.cases.json")"
  if ! "${PY[@]}" cases "$T/cases/$name.spec.json" 2> "$T/cases/$name.err"; then echo CRASH; return; fi
  for id in "${W_OK[@]}"; do
    rc="$(jq -r --arg id "$id" '.[]|select(.id==$id)|.rc' "$T/cases/$name.out")"; [ "$rc" = 0 ] || bad=$((bad + 1))
  done
  for id in "${W_REF[@]}"; do
    rc="$(jq -r --arg id "$id" '.[]|select(.id==$id)|.rc' "$T/cases/$name.out")"
    gho="$(jq -r --arg id "$id" '.[]|select(.id==$id)|.gho' "$T/cases/$name.out")"
    { [ "$rc" != 0 ] && [ -z "$gho" ]; } || bad=$((bad + 1))
  done
  echo "$bad"
}
_b="$(cc_run cc-pristine "$WF")"
[ "$_b" = 0 ] && pass "G4: the cutover confirm step, executed for all 5 modes, accepts the plain dispatch and refuses volume_id and origin_run ($CC_N cases)" || fail "G4: the cutover confirm table misbehaved" "$_b"
mutate g4-3-volume-id-in-flip "$WF" && { _b="$(cc_run cc-m-g4-3 "$MUT_FILE")"
  if [ "$_b" != 0 ] && [ "$_b" != CRASH ]; then pass "M-g4-3: with volume_id accepted in mode=flip the executed cutover-confirm table goes RED"; else fail "M-g4-3: executed table stayed GREEN" "$_b"; fi; }
CASES_RUN=$((W1_CASES_N + CC_N))

echo "-- E. the notify body and the notify if:, EXECUTED over the real text with synthesized env --"
NC=()
NIDS=()
ncase() { # <id> <wipe result> <mode> <started> <phase> <refusal> [run id] [typed volume id]
  NIDS+=("$1")
  NC+=("$(jq -nc --arg id "$1" --arg r "$2" --arg m "$3" --arg s "$4" --arg p "$5" --arg f "$6" --arg rid "${7-9000000123}" --arg vol "${8-424242}" '{id:$id,run_id:$rid,volume_id:$vol,needs:{cutover:{result:"skipped",outputs:{}},wipe:{result:$r,outputs:{mode:$m,started:$s,phase:$p,refusal:$f}}}}')")
}
ncase_empty() { NIDS+=("$1"); NC+=("$(jq -nc --arg id "$1" --arg r "$2" '{id:$id,run_id:"9000000123",needs:{cutover:{result:"skipped",outputs:{}},wipe:{result:$r,outputs:{}}}}')"); }
ncase_cut() { # <id> <cutover result> <mode> <finalizer_ran> [wipe result]
  NIDS+=("$1")
  NC+=("$(jq -nc --arg id "$1" --arg r "$2" --arg m "$3" --arg f "$4" --arg w "${5:-skipped}" '{id:$id,run_id:"9000000123",needs:{cutover:{result:$r,outputs:{mode:$m,started:"true",finalizer_ran:$f}},wipe:{result:$w,outputs:{}}}}')"); }
ncase_if() { # <id> <cutover result> <cutover started> <wipe result> <wipe started>
  NIDS+=("$1")
  NC+=("$(jq -nc --arg id "$1" --arg cr "$2" --arg cs "$3" --arg wr "$4" --arg ws "$5" '{id:$id,run_id:"9000000123",needs:{cutover:{result:$cr,outputs:{started:$cs,mode:(if $cr=="skipped" then "" else "flip" end)}},wipe:{result:$wr,outputs:{started:$ws,mode:(if $wr=="skipped" then "" else "wipe" end)}}}}')"); }
# wipe-family cases
for _mo in wipe wipe_finish; do
  ncase "$_mo-refused" failure "$_mo" true "" ""
  ncase "$_mo-state-unknown" failure "$_mo" "" "" ""
  ncase "$_mo-cancelled-state-unknown" cancelled "$_mo" "" "" ""
  for _ph in detach_attempted detached delete_attempted delete_sent deleted; do ncase "$_mo-phase-$_ph" failure "$_mo" true "$_ph" ""; done
  ncase "$_mo-phase-cancelled-detached" cancelled "$_mo" true detached ""
  ncase "$_mo-bogus-phase" failure "$_mo" true bogus_phase ""
  ncase "$_mo-bogus-refusal-over-phase" failure "$_mo" true delete_attempted bogus_refusal
  ncase "$_mo-already-detached" failure "$_mo" true "" volume_already_detached
  ncase "$_mo-store-not-serving" failure "$_mo" true detached store_not_serving
done
# the typed volume id reaches the recovery command only as 1 to 12 digits (anything else: the word VOLUME_ID)
ncase v-vid-12 failure wipe true detached "" 9000000123 123456789012
ncase v-vid-zeros failure wipe true detached "" 9000000123 000000012345
ncase h-vid-alpha failure wipe true detached "" 9000000123 12ab
ncase h-vid-13 failure wipe true detached "" 9000000123 1234567890123
ncase h-vid-inject failure wipe true detached "" 9000000123 '1;touch x'
ncase h-vid-newline failure wipe true detached "" 9000000123 $'1\nsubject=evil'
ncase h-vid-empty failure wipe true detached "" 9000000123 ""
ncase h-vid-finish failure wipe_finish true detached "" 9000000123 '$(touch x)'
ncase wipe_check-refused failure wipe_check true "" ""
ncase wipe_check-phase failure wipe_check true deleted ""
ncase wipe_check-unknown failure wipe_check "" "" ""
ncase_empty wipe-lost-runner cancelled
ncase_empty wipe-lost-runner-failure failure
# hostile values
ncase h-mode failure $'wipe\nsubject=evil' true detached ""
ncase h-mode-semi failure 'wipe; touch /tmp/x' true detached ""
ncase h-phase failure wipe true $'detached\nsubject=evil\nbody=evil' ""
ncase h-refusal failure wipe true "" $'volume_already_detached\nsubject=evil'
ncase h-started failure wipe $'true\nbody=evil' "" ""
ncase h-runid failure wipe true detached "" "12;touch"
ncase h-runid-newline failure wipe true detached "" $'123\nsubject=evil'
ncase h-runid-empty failure wipe true detached "" ""
# the cutover side keeps its own words
ncase_cut c-flip-finalizer failure flip 1
ncase_cut c-flip-nofinalizer failure flip ""
ncase_cut c-proof-finalizer failure proof 1
ncase_cut c-lost-cutover cancelled "" ""
# the notify if:, as a table over (cutover result, cutover started, wipe result, wipe started)
ncase_if if-cut-fail failure true skipped ""
ncase_if if-cut-typo failure false skipped ""
ncase_if if-cut-ok success true skipped ""
ncase_if if-cut-cancel-absent cancelled "" skipped ""
ncase_if if-wipe-fail skipped "" failure true
ncase_if if-wipe-typo skipped "" failure false
ncase_if if-wipe-ok skipped "" success true
ncase_if if-wipe-cancel-absent skipped "" cancelled ""
ncase_if if-both-skipped skipped "" skipped ""
ncase_if if-wipe-skipped-cut-typo-wipe-fail failure false failure true
ncase_if if-cut-fail-wipe-typo failure true failure false
NOTIFY_CASES_N=${#NC[@]}
notify_run() { # <name> <workflow>: results in $T/cases/<name>.notify.json
  local name="$1" wfp="$2"
  mkdir -p "$T/cases/$name.n"
  printf '%s\n' "${NC[@]}" | jq -s . > "$T/cases/$name.ncases.json"
  jmk "$T/cases/$name.nspec.json" wf="$wfp" run="$T/cases/$name.n" out="$T/cases/$name.notify.json" cases="json:$(cat "$T/cases/$name.ncases.json")"
  "${PY[@]}" notify "$T/cases/$name.nspec.json" 2> "$T/cases/$name.nerr"
}
NJ=""
nget() { jq -r --arg id "$1" ".[]|select(.id==\$id)|$2" "$NJ"; }
nbody() { nget "$1" '(.gho // "") + "\n" + (.notify_body // "")'; }
nsubj() { nget "$1" '(.gho // "")' | sed -n 's/^subject=//p' | head -n 1; }
nlines() { nget "$1" '(.gho // "")' | sed '/^$/d' | wc -l | tr -d ' '; }
# ncheck <id> <must-regex|-> <must-not-regex|->
ncheck() {
  local id="$1" must="$2" mustnot="$3" b rc
  rc="$(nget "$id" .rc)"; b="$(nbody "$id")"
  [ "$rc" = 0 ] || { echo "rc=$rc"; return 1; }
  if [ "$must" != - ] && ! grep -qE -- "$must" <<<"$b"; then echo "missing /$must/"; return 1; fi
  if [ "$mustnot" != - ] && grep -qE -- "$mustnot" <<<"$b"; then echo "present /$mustnot/"; return 1; fi
  return 0
}
nrow() { # <label> <id> <must> <mustnot>
  local why
  if why="$(ncheck "$2" "$3" "$4")"; then pass "$1"; else fail "$1" "$why | $(nsubj "$2")"; fi
}
RUNID=9000000123
ALLWORDS='WIPE_REFUSED_BEFORE_ANY_CALL|WIPE_STATE_UNKNOWN|VOLUME_ALREADY_DETACHED|STORE_NOT_SERVING_DO_NOT_FINISH|DETACH_ATTEMPTED_UNCONFIRMED|VOLUME_DETACHED|DELETE_ATTEMPTED_UNCONFIRMED|DELETE_SENT_UNCONFIRMED|VOLUME_DELETED_TEARDOWN_FAILED|WIPE_CHECK_FAILED'
only() { # the one wipe word that must appear, and no other
  local w="$1" other
  other="$(tr '|' '\n' <<<"$ALLWORDS" | grep -vx "$w" | tr '\n' '|')"; printf '%s' "${other%|}"
}
notify_rows() { # <label-suffix>: every executed notify row against $NJ
  local sfx="$1" mo ph w
  for mo in wipe wipe_finish; do
    nrow "NB-$mo-refused$sfx: a failed $mo whose job published started=true and no phase reads WIPE_REFUSED_BEFORE_ANY_CALL (no irreversible call; says nothing about earlier runs), and never MODE=unknown" "$mo-refused" "WIPE_REFUSED_BEFORE_ANY_CALL.*no irreversible call.*nothing about earlier runs" "$(only WIPE_REFUSED_BEFORE_ANY_CALL)|cutover unknown| unknown "
    nrow "NB-$mo-state-unknown$sfx: absent phase and absent started reads WIPE_STATE_UNKNOWN (never the refused-before-any-call claim)" "$mo-state-unknown" "WIPE_STATE_UNKNOWN" "$(only WIPE_STATE_UNKNOWN)"
    nrow "NB-$mo-cancelled$sfx: a cancelled $mo with no outputs reads WIPE_STATE_UNKNOWN and names the mode" "$mo-cancelled-state-unknown" "WIPE_STATE_UNKNOWN.*(cancelled|timed out)|\[git-data-cutover $mo cancelled\]" "$(only WIPE_STATE_UNKNOWN)"
    nrow "NB-$mo-phase-detach_attempted$sfx: phase detach_attempted -> DETACH_ATTEMPTED_UNCONFIRMED (read the volume first)" "$mo-phase-detach_attempted" "DETACH_ATTEMPTED_UNCONFIRMED.*read the volume first" "$(only DETACH_ATTEMPTED_UNCONFIRMED)"
    nrow "NB-$mo-phase-detached$sfx: phase detached -> VOLUME_DETACHED with the wipe_finish command carrying the typed volume id" "$mo-phase-detached" "VOLUME_DETACHED.*-f mode=wipe_finish -f confirm=WIPE-FINISH-GIT-DATA -f volume_id=424242 -f origin_run=" "$(only VOLUME_DETACHED)"
    nrow "NB-$mo-phase-delete_attempted$sfx: phase delete_attempted -> DELETE_ATTEMPTED_UNCONFIRMED" "$mo-phase-delete_attempted" "DELETE_ATTEMPTED_UNCONFIRMED" "$(only DELETE_ATTEMPTED_UNCONFIRMED)"
    nrow "NB-$mo-phase-delete_sent$sfx: phase delete_sent -> DELETE_SENT_UNCONFIRMED" "$mo-phase-delete_sent" "DELETE_SENT_UNCONFIRMED" "$(only DELETE_SENT_UNCONFIRMED)"
    nrow "NB-$mo-phase-deleted$sfx: phase deleted plus a later failure -> VOLUME_DELETED_TEARDOWN_FAILED, not DELETE_SENT_UNCONFIRMED" "$mo-phase-deleted" "VOLUME_DELETED_TEARDOWN_FAILED.*only the runner teardown failed" "$(only VOLUME_DELETED_TEARDOWN_FAILED)"
    nrow "NB-$mo-bogus-phase$sfx: an unrecognised phase reads WIPE_STATE_UNKNOWN" "$mo-bogus-phase" "WIPE_STATE_UNKNOWN.*unrecognised phase" "$(only WIPE_STATE_UNKNOWN)"
    nrow "NB-$mo-bogus-refusal$sfx: an unrecognised refusal is ignored and the phase decides" "$mo-bogus-refusal-over-phase" "DELETE_ATTEMPTED_UNCONFIRMED" "$(only DELETE_ATTEMPTED_UNCONFIRMED)"
    nrow "NB-$mo-already-detached$sfx: refusal volume_already_detached -> VOLUME_ALREADY_DETACHED carrying the wipe_finish command with the WORD ORIGIN_RUN_ID (the refused run is not the origin, even when it is a mode=wipe run)" "$mo-already-detached" "VOLUME_ALREADY_DETACHED.*-f mode=wipe_finish -f confirm=WIPE-FINISH-GIT-DATA.*-f origin_run=ORIGIN_RUN_ID" "$(only VOLUME_ALREADY_DETACHED)|origin_run=$RUNID"
    nrow "NB-$mo-store-not-serving$sfx: refusal store_not_serving beats the detached phase -> STORE_NOT_SERVING_DO_NOT_FINISH and offers no finish command" "$mo-store-not-serving" "STORE_NOT_SERVING_DO_NOT_FINISH.*Do NOT dispatch wipe_finish" "$(only STORE_NOT_SERVING_DO_NOT_FINISH)|-f mode=wipe_finish -f"
  done
  # no angle bracket in any recovery command: the notify body is HTML and the issue is markdown, and either swallows <text>
  local ab=0 abn=0 abid
  for abid in "${NIDS[@]}"; do
    case "$abid" in wipe*|v-*|h-vid*) ;; *) continue ;; esac
    # the html body carries <p> tags around the text: drop those, then no angle bracket may remain in a line naming the command
    _pl="$(nbody "$abid" | sed -E 's#</?p>##g')"
    _pg="$(grep -E -- 'gh workflow run' <<<"$_pl" || true)"
    if grep -qE '[<>]' <<<"$_pg"; then ab=$((ab + 1)); fi
    abn=$((abn + $(grep -cE -- 'gh workflow run' <<<"$_pl" || true)))
  done
  [ "$ab" = 0 ] && [ "$abn" -ge 12 ] && pass "NB-no-angle$sfx: none of the $abn recovery commands across the wipe-family notifications carries an angle bracket (plain-word placeholders only)" || fail "NB-no-angle$sfx: $ab notification(s) carry an angle bracket in the recovery command ($abn commands)"
  nrow "NB-wipe-detached-origin$sfx: a wipe run's VOLUME_DETACHED command fills origin_run with THIS run's id" "wipe-phase-detached" "origin_run=$RUNID" -
  nrow "NB-wipe-detach_attempted-origin$sfx: a wipe run's DETACH_ATTEMPTED_UNCONFIRMED command fills origin_run with THIS run's id" "wipe-phase-detach_attempted" "origin_run=$RUNID" -
  nrow "NB-finish-detached-placeholder$sfx: a wipe_finish run's VOLUME_DETACHED keeps the word ORIGIN_RUN_ID (its own id is not the detaching run)" "wipe_finish-phase-detached" "origin_run=ORIGIN_RUN_ID" "origin_run=$RUNID"
  nrow "NB-finish-already-detached-placeholder$sfx: a wipe_finish run's VOLUME_ALREADY_DETACHED keeps ORIGIN_RUN_ID too and tells the reader to replace it" "wipe_finish-already-detached" "origin_run=ORIGIN_RUN_ID, replacing ORIGIN_RUN_ID by the id of the wipe run that detached it" "origin_run=$RUNID"
  nrow "NB-vid-filled$sfx: the typed volume id is filled into the recovery command for a 1-12 digit input (leading zeros as typed)" "v-vid-12" "-f volume_id=123456789012 -f origin_run=$RUNID" "VOLUME_ID"
  nrow "NB-vid-zeros$sfx: 000000012345 is digits and 12 long: filled as typed" "v-vid-zeros" "-f volume_id=000000012345 -f origin_run=" "VOLUME_ID"
  local hv hbad=0
  for hv in h-vid-alpha h-vid-13 h-vid-inject h-vid-newline h-vid-empty h-vid-finish; do
    ncheck "$hv" "-f volume_id=VOLUME_ID -f origin_run=" "touch|12ab|1234567890123|evil" >/dev/null && [ "$(nlines "$hv")" = 2 ] || { hbad=$((hbad + 1)); echo "  vid hostile $hv: $(ncheck "$hv" "-f volume_id=VOLUME_ID" "touch|12ab|evil")"; }
  done
  [ "$hbad" = 0 ] && pass "NB-vid-hostile$sfx: a volume id that is not 1 to 12 digits (letters, 13 digits, a semicolon, a newline, a command substitution, empty) never reaches the recovery command: it reads the word VOLUME_ID and the output keeps its two lines" || fail "NB-vid-hostile$sfx: $hbad hostile volume id(s) reached the command"
  nrow "NB-check-refused$sfx: a failed wipe_check reads WIPE_CHECK_FAILED with read-only wording" "wipe_check-refused" "WIPE_CHECK_FAILED.*read-only: nothing on any host or at the provider was changed" "$(only WIPE_CHECK_FAILED)"
  nrow "NB-check-any-phase$sfx: wipe_check ignores any phase value and stays WIPE_CHECK_FAILED" "wipe_check-phase" "WIPE_CHECK_FAILED" "$(only WIPE_CHECK_FAILED)"
  nrow "NB-check-unknown$sfx: wipe_check with no outputs still reads WIPE_CHECK_FAILED" "wipe_check-unknown" "WIPE_CHECK_FAILED" "$(only WIPE_CHECK_FAILED)"
  nrow "NB-lost-runner$sfx: a wipe job that published no outputs at all (lost runner, rejected approval) reads WIPE_STATE_UNKNOWN and carries no unfreeze remedy" "wipe-lost-runner" "WIPE_STATE_UNKNOWN" "$(only WIPE_STATE_UNKNOWN)|unfreeze|UNFREEZE"
  nrow "NB-lost-runner-failure$sfx: the same with result failure" "wipe-lost-runner-failure" "WIPE_STATE_UNKNOWN" "$(only WIPE_STATE_UNKNOWN)|unfreeze|UNFREEZE"
  nrow "NB-lost-runner-mode$sfx: the lost wipe job is named as the wipe family (mode wipe_unknown in the subject), never as an unknown cutover" "wipe-lost-runner" "\\[git-data-cutover wipe_unknown cancelled\\]" "STATE UNKNOWN|cutover unknown"
  nrow "NB-lost-cutover$sfx: a cutover job that published nothing (wipe skipped) keeps the generic STATE UNKNOWN and gets no wipe word" c-lost-cutover "STATE UNKNOWN" "$ALLWORDS|wipe_unknown"
  nrow "NB-cutover-finalizer$sfx: a cutover flip failure whose finalizer ran keeps its own FAILED word and no wipe word" c-flip-finalizer "FAILED" "$ALLWORDS"
  nrow "NB-cutover-nofinalizer$sfx: a cutover failure with no finalizer output keeps STATE UNKNOWN and no wipe word" c-flip-nofinalizer "STATE UNKNOWN" "$ALLWORDS"
  nrow "NB-cutover-proof$sfx: mode=proof keeps its read-only note" c-proof-finalizer "mode=proof is read-only" "$ALLWORDS"
  # hostile values: the output file is exactly the subject and body lines
  local h bad=0 ln
  for h in h-mode h-mode-semi h-phase h-refusal h-started; do
    ln="$(nlines "$h")"; [ "$(nget "$h" .rc)" = 0 ] && [ "$ln" = 2 ] && [ "$(nget "$h" '(.gho//"")' | sed -n '1p' | cut -c1-8)" = "subject=" ] && [ "$(nget "$h" '(.gho//"")' | sed -n '2p' | cut -c1-5)" = "body=" ] || { bad=$((bad + 1)); echo "  hostile $h: lines=$ln"; }
  done
  [ "$bad" = 0 ] && pass "NB-hostile$sfx: a hostile MODE, phase, refusal or started value (newlines, semicolons) cannot add an output line: the output is exactly subject= and body=" || fail "NB-hostile$sfx: a hostile value changed the output shape ($bad)"
  bad=0
  for h in h-runid h-runid-newline h-runid-empty; do [ "$(nget "$h" .rc)" != 0 ] && [ -z "$(nget "$h" '(.gho//"")')" ] || bad=$((bad + 1)); done
  [ "$bad" = 0 ] && pass "NB-hostile-runid$sfx: a non-numeric, newline-carrying or empty run id aborts the body with no output" || fail "NB-hostile-runid$sfx: a hostile run id was tolerated ($bad)"
  # no wipe-family word ever carries the unfreeze remedy; none carries a forbidden phrase
  local id leak=0 forb=0 n=0
  for id in "${NIDS[@]}"; do
    case "$id" in wipe*|h-*) : ;; *) continue ;; esac
    case "$id" in *lost-runner*|h-mode*|h-runid*) continue ;; esac
    n=$((n + 1))
    if grep -qiE -- 'mode=unfreeze|UNFREEZE-GIT-DATA|freeze sentinel|lineage=' <<<"$(nbody "$id")"; then leak=$((leak + 1)); echo "  unfreeze remedy in $id"; fi
    if forbidden "$(nbody "$id")"; then forb=$((forb + 1)); echo "  forbidden phrase in $id"; fi
  done
  [ "$leak" = 0 ] && [ "$n" -ge 28 ] && pass "NB-no-unfreeze$sfx: none of $n wipe-family notifications carries the unfreeze remedy (mode=unfreeze, UNFREEZE-GIT-DATA, lineage)" || fail "NB-no-unfreeze$sfx: $leak of $n wipe notifications carry the unfreeze remedy"
  [ "$forb" = 0 ] && pass "G8-notify-executed$sfx: none of $n executed wipe notifications contains a forbidden phrase" || fail "G8-notify-executed$sfx: $forb notifications contain a forbidden phrase"
}
notify_run pristine "$WF" || fail "the notify runner crashed" "$(tail -c 300 "$T/cases/pristine.nerr")"
NJ="$T/cases/pristine.notify.json"
notify_rows ""
# the if: table
iftab() { # <id> <expected true|false>
  local got; got="$(nget "$1" '.if')"
  [ "$got" = "$2" ]
}
IFBAD=""
for _r in if-cut-fail:true if-cut-typo:false if-cut-ok:false if-cut-cancel-absent:true if-wipe-fail:true if-wipe-typo:false if-wipe-ok:false if-wipe-cancel-absent:true if-both-skipped:false if-wipe-skipped-cut-typo-wipe-fail:true if-cut-fail-wipe-typo:true; do
  iftab "${_r%%:*}" "${_r#*:}" || IFBAD+=" ${_r%%:*}(got $(nget "${_r%%:*}" .if))"
done
[ -z "$IFBAD" ] && pass "N-if-table: the notify if:, EVALUATED over 11 (cutover, wipe) result/started pairs, emails a failed or cancelled run of either job, never a typo'd (started=false) or successful or skipped one, and pairs each started clause with its own job" || fail "N-if-table: the notify if: misjudged:$IFBAD"
# notify mutants: executed halves
mutate g3-4-finish-not-in-list "$WF" && { notify_run m-g3-4 "$MUT_FILE"; NJ="$T/cases/m-g3-4.notify.json"
  if grep -qE 'cutover unknown|\[git-data-cutover unknown' <<<"$(nsubj wipe_finish-refused)$(nsubj wipe_finish-phase-detached)"; then pass "M-g3-4: with wipe_finish dropped from the MODE list the executed body reads MODE=unknown for a failed wipe_finish"
  else fail "M-g3-4: the executed body did not turn the dropped mode into MODE=unknown" "$(nsubj wipe_finish-refused)"; fi; }
for _m in g3-9a-wipe-unknown-not-in-family g3-9b-lost-runner-setter-removed g3-9c-wipe-unknown-not-in-whitelist; do
  mutate "$_m" "$WF" && { notify_run "m-$_m" "$MUT_FILE"; NJ="$T/cases/m-$_m.notify.json"
    if ! ncheck wipe-lost-runner "WIPE_STATE_UNKNOWN" "unfreeze|UNFREEZE" >/dev/null; then pass "M-$_m: the executed lost-runner row (WIPE_STATE_UNKNOWN, no unfreeze remedy) goes RED"
    else fail "M-$_m: the executed lost-runner row stayed GREEN"; fi; }
done
mutate g3-6-unfreeze-in-word "$WF" && { notify_run m-g3-6 "$MUT_FILE"; NJ="$T/cases/m-g3-6.notify.json"
  if grep -qE 'mode=unfreeze' <<<"$(nbody wipe-phase-detached)"; then pass "M-g3-6: a wipe word carrying the unfreeze remedy is visible to the executed body rows (NB-no-unfreeze goes RED)"
  else fail "M-g3-6: the mutant's word did not reach the executed output"; fi; }
mutate g3-7a-refusal-dropped "$WF" && { notify_run m-g3-7a "$MUT_FILE"; NJ="$T/cases/m-g3-7a.notify.json"
  if ! ncheck wipe-already-detached "VOLUME_ALREADY_DETACHED" - >/dev/null; then pass "M-g3-7a: with the refusal mapping dropped the executed VOLUME_ALREADY_DETACHED row goes RED"
  else fail "M-g3-7a: the executed refusal row stayed GREEN"; fi; }
mutate g3-7b-no-finish-command "$WF" && { notify_run m-g3-7b "$MUT_FILE"; NJ="$T/cases/m-g3-7b.notify.json"
  if ! ncheck wipe-already-detached "VOLUME_ALREADY_DETACHED.*-f mode=wipe_finish" - >/dev/null; then pass "M-g3-7b: with the finish command omitted the executed VOLUME_ALREADY_DETACHED row goes RED"
  else fail "M-g3-7b: the executed row stayed GREEN"; fi; }
mutate g3-8-phase-arm-removed "$WF" && { notify_run m-g3-8 "$MUT_FILE"; NJ="$T/cases/m-g3-8.notify.json"
  if ! ncheck wipe-phase-deleted "VOLUME_DELETED_TEARDOWN_FAILED" - >/dev/null; then pass "M-g3-8: with the deleted arm removed the executed phase row goes RED (it would read WIPE_REFUSED_BEFORE_ANY_CALL)"
  else fail "M-g3-8: the executed phase row stayed GREEN"; fi; }
mutate g8-2b-forbidden-notify-word "$WF" && { notify_run m-g8-2b "$MUT_FILE"; NJ="$T/cases/m-g8-2b.notify.json"
  if forbidden "$(nbody wipe-phase-deleted)"; then pass "M-g8-2b: a forbidden phrase in a wipe word is visible to the executed notify output rows"
  else fail "M-g8-2b: the forbidden phrase did not reach the executed output"; fi; }
mutate nv-vid-unvalidated "$WF" && { notify_run m-nvv "$MUT_FILE"; NJ="$T/cases/m-nvv.notify.json"
  if ! ncheck h-vid-inject "-f volume_id=VOLUME_ID -f origin_run=" "touch" >/dev/null && ! ncheck h-vid-alpha "-f volume_id=VOLUME_ID -f origin_run=" "12ab" >/dev/null; then pass "M-nv-vid: filling the volume id without the 1-12 digit test lets a free-text id into the recovery command (the executed hostile rows go RED)"
  else fail "M-nv-vid: the executed hostile volume-id rows stayed GREEN"; fi; }
mutate nv-orig-always "$WF" && { notify_run m-nvo "$MUT_FILE"; NJ="$T/cases/m-nvo.notify.json"
  if ! ncheck wipe_finish-phase-detached "origin_run=ORIGIN_RUN_ID" "origin_run=$RUNID" >/dev/null; then pass "M-nv-orig: filling the run's own id for a wipe_finish run too puts a non-origin run id into the command (the executed placeholder row goes RED)"
  else fail "M-nv-orig: the executed placeholder row stayed GREEN"; fi; }
mutate nv-angle "$WF" && { notify_run m-nva "$MUT_FILE"; NJ="$T/cases/m-nva.notify.json"
  if ! ncheck h-vid-empty "-f volume_id=VOLUME_ID -f origin_run=" "volume_id=<|origin_run=<" >/dev/null; then pass "M-nv-angle: an angle-bracket placeholder in the recovery command is visible to the executed rows (RED)"
  else fail "M-nv-angle: the executed rows stayed GREEN"; fi; }
mutate nv-already-here "$WF" && { notify_run m-nvh "$MUT_FILE"; NJ="$T/cases/m-nvh.notify.json"
  if ! ncheck wipe-already-detached "origin_run=ORIGIN_RUN_ID" "origin_run=$RUNID" >/dev/null; then pass "M-nv-already: the already-detached word built from the run's own command puts the refused run's id into origin_run (the executed row goes RED)"
  else fail "M-nv-already: the executed row stayed GREEN"; fi; }
mutate "m-if-drop-wipe-started" "$WF" '[{"op":"sub","job":"notify","old":" && needs.wipe.outputs.started != '"'"'false'"'"'","new":"","count":1}]' && { notify_run m-ifw "$MUT_FILE"; NJ="$T/cases/m-ifw.notify.json"
  if ! iftab if-wipe-typo false; then pass "M-if-wipe: dropping the wipe started clause makes a typo'd wipe dispatch email (the if table goes RED)"; else fail "M-if-wipe: the if table stayed GREEN"; fi; }
mutate "m-if-drop-cutover-started" "$WF" '[{"op":"sub","job":"notify","old":" && needs.cutover.outputs.started != '"'"'false'"'"'","new":"","count":1}]' && { notify_run m-ifc "$MUT_FILE"; NJ="$T/cases/m-ifc.notify.json"
  if ! iftab if-cut-typo false; then pass "M-if-cut: dropping the cutover started clause makes a typo'd cutover dispatch email (the if table goes RED)"; else fail "M-if-cut: the if table stayed GREEN"; fi; }
cz m-ifw2 wf="$T/mut/m-if-drop-wipe-started.yml"; red "$CZ_OUT" "G3-notify-if:" && pass "M-if-wipe: the exact-string census row also goes RED" || fail "M-if-wipe: census row stayed GREEN"
cz m-ifc2 wf="$T/mut/m-if-drop-cutover-started.yml"; red "$CZ_OUT" "G3-notify-if:" && pass "M-if-cut: the exact-string census row also goes RED" || fail "M-if-cut: census row stayed GREEN"
NJ="$T/cases/pristine.notify.json"

echo "-- F. the simulator: the real run: text of the whole wipe job under shims (build the runs) --"
SIMS=()
simdef() { # <name> <mode> [k=v ...]
  local name="$1" mode="$2"; shift 2
  assert_fixture_dir "$T/sim"
  mkdir -p "$T/sim/$name"
  jmk "$T/specs/$name.json" wf="$WF" root="$ROOT" helper="$HELPER" lib="$LIB" run="$T/sim/$name" mode="$mode" tag="t$(printf '%04d' "${#SIMS[@]}")abcd" "$@"
  SIMS+=("$name")
}
T_TRUE='json:true'
simdef gold-wipe wipe notify="$T_TRUE"
simdef gold-finish wipe_finish origin_run=8000000555 world='json:{"PT_SERVER":"null"}' origin_names=ids
simdef gold-finish-faithful wipe_finish origin_run=8000000555 world='json:{"PT_SERVER":"null"}'
simdef gold-finish-absent wipe_finish origin_run=8000000555 world='json:{"PT_SERVER":"gone"}' origin_names=ids
simdef gold-check wipe_check
simdef check-flag-false wipe_check world='json:{"FLAG_STATE":"false"}'
simdef gold-noflip wipe no_flip="$T_TRUE"
simdef mute-events wipe mute_events="$T_TRUE"
# Guard 2: every adjacent pair of the live chain swapped (the pair count is derived from the live step list)
mapfile -t CHAIN < "$PRISTINE_OUT.chain"
SWAPS=()
for ((_i = 0; _i + 1 < ${#CHAIN[@]}; _i++)); do
  _a="${CHAIN[$_i]}"; _b="${CHAIN[$((_i + 1))]}"; _n="swap-${_a#wipe_}-${_b#wipe_}"
  if mutate "$_n" "$WF" "[{\"op\":\"swap\",\"a\":\"$_a\",\"b\":\"$_b\"}]"; then simdef "$_n" wipe wf="$MUT_FILE"; SWAPS+=("$_n"); fi
done
mutate g2-2-host-after-detach "$WF" && simdef m-g2-2 wipe wf="$MUT_FILE"
mutate g2-2b-host-read-after-detach "$WF" && { simdef m-g2-2b wipe wf="$MUT_FILE"; simdef m-g2-2b-noflip wipe wf="$MUT_FILE" no_flip="$T_TRUE"; }
mutate g2-3-second-read "$WF" && simdef m-g2-3 wipe wf="$MUT_FILE" world_before='json:{"wipe_reread2":{"PT_PROT":"true"}}'
# time bounds and epochs
simdef stale-w7-gate wipe clock_before='json:{"wipe_detach_gate":1000}'
simdef stale-w7-helper wipe clock_before='json:{"wipe_detach":1000}'
simdef stale-w10b-gate wipe clock_before='json:{"wipe_delete_gate":100}'
simdef stale-w10b-helper wipe clock_before='json:{"wipe_delete":100}'
simdef w10b-binding wipe clock_before='json:{"wipe_reread":200}'
mutate g2-5a-gate-record-check-removed "$WF" && simdef m-g2-5a wipe wf="$MUT_FILE" clock_before='json:{"wipe_detach_gate":1000}'
mutate g2-5c-dgate-record-check-removed "$WF" && simdef m-g2-5c wipe wf="$MUT_FILE" clock_before='json:{"wipe_delete_gate":100}'
mutate g2h-5b-helper-w7-site "$HELPER" && simdef m-g2h-5b wipe helper="$MUT_FILE" clock_before='json:{"wipe_detach":1000}'
mutate g2h-5d-helper-w10b-site "$HELPER" && simdef m-g2h-5d wipe helper="$MUT_FILE" clock_before='json:{"wipe_delete":100}'
mutate g2h-6-no-w10b-restamp "$HELPER" && simdef m-g2h-6 wipe helper="$MUT_FILE"
mutate g2h-6b-w10b-from-w7 "$HELPER" && simdef m-g2h-6b wipe helper="$MUT_FILE" clock_before='json:{"wipe_reread":200}'
mutate g2-8-finish-no-record "$WF" && simdef m-g2-8 wipe_finish wf="$MUT_FILE" origin_run=8000000555 world='json:{"PT_SERVER":"null"}' origin_names=ids
mutate g3-1b-marker-before-checks "$WF" && simdef m-g3-1b wipe wf="$MUT_FILE" clock_before='json:{"wipe_detach_gate":1000}'
mutate g3-1c-dmarker-before-checks "$WF" && simdef m-g3-1c wipe wf="$MUT_FILE" clock_before='json:{"wipe_delete_gate":100}'
mutate g3-1d-marker-after-call-swap "$WF" && simdef m-g3-1d wipe wf="$MUT_FILE" kill_at=wipe_detach_gate
mutate g3-2-merge-gate-into-detach "$WF" && simdef m-g3-2 wipe wf="$MUT_FILE" kill_at=wipe_detach
mutate g1-1-env-u "$WF" && simdef m-g1-1 wipe wf="$MUT_FILE"
mutate g1-2-cred-on-envi "$WF" && simdef m-g1-2 wipe wf="$MUT_FILE"
mutate g1-9-legacy-input "$WF" && simdef m-g1-9 wipe wf="$MUT_FILE" legacy_only="$T_TRUE"
mutate g8-2a-forbidden-summary "$WF" && simdef m-g8-2a wipe wf="$MUT_FILE"
# markers: killed or cancelled runs
simdef kill-detach wipe kill_at=wipe_detach notify="$T_TRUE"
simdef kill-post-detach wipe kill_at=wipe_post_detach_read notify="$T_TRUE"
simdef kill-delete wipe kill_at=wipe_delete notify="$T_TRUE"
simdef cancel-after-gate wipe cancel_after=wipe_detach_gate notify="$T_TRUE"
simdef cancel-after-detach wipe cancel_after=wipe_detach notify="$T_TRUE"
# refusals and failures, each end to end through the notify body
simdef typo-token wipe confirm=WIPE-FINISH-GIT-DATA notify="$T_TRUE"
simdef precheck-refused wipe world='json:{"FLAG_STATE":"false"}' notify="$T_TRUE"
simdef already-detached wipe world='json:{"PT_SERVER":"null"}' notify="$T_TRUE"
simdef store-not-serving wipe world_before='json:{"wipe_post_detach_read":{"HOST_SERVING":"0"}}' notify="$T_TRUE"
simdef delete-sent wipe world_before='json:{"wipe_readback":{"LUKS_SERVER":"null"}}' notify="$T_TRUE"
simdef teardown-fail wipe fail_after=wipe_teardown notify="$T_TRUE"
simdef flag-flip wipe world_before='json:{"wipe_flag_reread":{"FLAG_STATE":"false"}}' notify="$T_TRUE"
simdef reread-protected wipe world_before='json:{"wipe_reread":{"PT_PROT":"true"}}' notify="$T_TRUE"
simdef reread-reattached wipe world_before='json:{"wipe_reread":{"PT_SERVER":"@SRV"}}' notify="$T_TRUE"
simdef target-is-luks wipe volume_id=900000002
simdef no-tier-b wipe no_tier_b="$T_TRUE"
# round 2: the fail-closed gates on their NEGATIVE paths. Each scenario is required REFUSED at its own step with zero detach
# POSTs and zero DELETEs (section G); the one-line-edit mutants that disarm a gate must make the scenario reach the delete.
FIN_W=(wipe_finish origin_run=8000000555 world='json:{"PT_SERVER":"null"}' origin_names=ids)
simdef neg-origin-branch "${FIN_W[@]}" origin_override='json:{"headBranch":"feature-x"}'
simdef neg-origin-event "${FIN_W[@]}" origin_override='json:{"event":"push"}'
simdef neg-origin-title "${FIN_W[@]}" origin_override='json:{"displayTitle":"git-data wipe 1"}'
simdef neg-origin-workflow "${FIN_W[@]}" origin_override='json:{"workflowName":"some other workflow"}'
simdef neg-origin-gate "${FIN_W[@]}" gate_conclusion=failure
simdef neg-origin-createdat "${FIN_W[@]}" origin_override='json:{"createdAt":null}'
simdef neg-origin-unreadable "${FIN_W[@]}" origin_absent="$T_TRUE"
RL_ROLLBACK='[{"databaseId":11,"displayTitle":"git-data rollback","createdAt":"2026-10-10T12:00:00Z","conclusion":"success","headBranch":"main","event":"workflow_dispatch"}]'
simdef neg-rollback wipe runlist="$RL_ROLLBACK"
simdef neg-rollback-check wipe_check runlist="$RL_ROLLBACK"
simdef neg-runlist-unreadable wipe runlist_fail="$T_TRUE"
simdef neg-stamp-absent wipe world='json:{"STAMP_ABSENT":"1"}'
# A1 (2026-10-15): the separated variant, end to end. The run-record scan is the REAL library over the gh shim's fixtures.
simdef gold-sep-check wipe_check world='json:{"VARIANT":"separated","FLAG_STATE":"false"}'
simdef gold-sep-wipe wipe world='json:{"VARIANT":"separated","FLAG_STATE":"false"}'
simdef neg-sep-dirty wipe world='json:{"VARIANT":"separated","FLAG_STATE":"false"}' scan=dirty
simdef neg-sep-inflight wipe world='json:{"VARIANT":"separated","FLAG_STATE":"false"}' scan=inflight
simdef neg-sep-srr wipe world='json:{"VARIANT":"separated","FLAG_STATE":"false","SRR":"2"}'
simdef chk-sep-srr wipe_check world='json:{"VARIANT":"separated","FLAG_STATE":"false","SRR":"1"}'
simdef sep-flip-race wipe world='json:{"VARIANT":"separated","FLAG_STATE":"false"}' world_before='json:{"wipe_flag_reread":{"VARIANT":"flip_chained","FLAG_STATE":"true"}}'
simdef neg-boot-verdict wipe boot_verdict=wipe_boot_row_absent
simdef neg-boot-unreadable wipe boot_rc=1
_act() { jq -nc --argjson a "$1" '{actions:$a,meta:{pagination:{page:1,per_page:50,total_entries:($a|length)}}}'; }
ACT_ATTACH="$(_act '[{"id":9,"command":"detach_volume","status":"success","started":"2026-10-14T15:05:00Z","finished":"2026-10-14T15:05:09Z","progress":100},{"id":8,"command":"attach_volume","status":"success","started":"2026-10-14T15:03:00Z","finished":"2026-10-14T15:03:09Z","progress":100},{"id":7,"command":"detach_volume","status":"success","started":"2026-10-14T15:00:00Z","finished":"2026-10-14T15:00:09Z","progress":100}]')"
ACT_OLD="$(_act '[{"id":7,"command":"detach_volume","status":"success","started":"2026-10-14T14:50:00Z","finished":"2026-10-14T14:50:09Z","progress":100}]')"
ACT_NONE="$(_act '[]')"
simdef neg-actions-attach "${FIN_W[@]}" actions_json="$ACT_ATTACH"
simdef neg-actions-old "${FIN_W[@]}" actions_json="$ACT_OLD"
simdef neg-actions-none "${FIN_W[@]}" actions_json="$ACT_NONE"
simdef lead-zero wipe pt_id=12345 volume_id=000000012345
simdef host-read-access-fail wipe world_before='json:{"wipe_post_detach_read":{"HOST_ACCESS_FAIL":"1"}}' notify="$T_TRUE"
simdef host-read-probe-failed wipe world_before='json:{"wipe_post_detach_read":{"HOST_PROBE_FAIL":"1"}}' notify="$T_TRUE"
# a bounded call that times out reads as an absent token / an unreadable run, never as success
TF_GH_LIST='json:{"wipe_flag_precheck":{"TIMEOUT_FIRES":"gh"}}'; TF_GH_VIEW='json:{"wipe_origin_check":{"TIMEOUT_FIRES":"gh"}}'
TF_DOP_W4='json:{"wipe_identity":{"TIMEOUT_FIRES":"doppler"}}'; TF_DOP_W10B='json:{"wipe_reread":{"TIMEOUT_FIRES":"doppler"}}'; TF_DOP_W12='json:{"wipe_readback":{"TIMEOUT_FIRES":"doppler"}}'
simdef neg-timeout-gh-list wipe world_before="$TF_GH_LIST"
simdef neg-timeout-gh-view "${FIN_W[@]}" world_before="$TF_GH_VIEW"
simdef neg-timeout-doppler-w4 wipe world_before="$TF_DOP_W4"
simdef neg-timeout-doppler-w10b wipe world_before="$TF_DOP_W10B"
simdef neg-timeout-doppler-w12 wipe world_before="$TF_DOP_W12"
simdef m-t-gh-list wipe wf="$T/mut/t-gh-list-dropped.yml" world_before="$TF_GH_LIST"
simdef m-t-gh-view "${FIN_W[@]}" wf="$T/mut/t-gh-view-dropped.yml" world_before="$TF_GH_VIEW"
simdef m-t-doppler-w4 wipe wf="$T/mut/t-doppler-identity-dropped.yml" world_before="$TF_DOP_W4"
simdef m-t-doppler-w10b wipe wf="$T/mut/t-doppler-reread-dropped.yml" world_before="$TF_DOP_W10B"
simdef m-t-doppler-w12 wipe wf="$T/mut/t-doppler-readback-dropped.yml" world_before="$TF_DOP_W12"
# the one-line-edit mutants of those gates, each driven by the scenario that must catch it
mutate a1-origin-exit5 "$WF" && simdef m-a1-exit5 "${FIN_W[@]}" wf="$MUT_FILE" origin_override='json:{"headBranch":"feature-x"}'
mutate a1-origin-rc0 "$WF" && simdef m-a1-rc0 "${FIN_W[@]}" wf="$MUT_FILE" origin_override='json:{"headBranch":"feature-x"}'
mutate a1-origin-delete-gate-open "$WF" && simdef m-a1-delgate "${FIN_W[@]}" wf="$MUT_FILE" origin_override='json:{"headBranch":"feature-x"}'
mutate a1-origin-wrong-run "$WF" && simdef m-a1-wrongrun "${FIN_W[@]}" wf="$MUT_FILE"
mutate a1-origin-no-jobs "$WF" && simdef m-a1-nojobs "${FIN_W[@]}" wf="$MUT_FILE"
mutate a1-origin-no-workflowname "$WF" && simdef m-a1-nowfname "${FIN_W[@]}" wf="$MUT_FILE"
mutate a2-precheck-exit5 "$WF" && simdef m-a2-exit5 wipe wf="$MUT_FILE" runlist="$RL_ROLLBACK"
mutate a2-wipemode-check "$WF" && simdef m-a2-wipemode wipe wf="$MUT_FILE" runlist="$RL_ROLLBACK"
mutate a2-runs-fallback-open "$WF" && simdef m-a2-fallback wipe wf="$MUT_FILE" runlist_fail="$T_TRUE"
mutate a2-limit-10 "$WF" && simdef m-a2-limit wipe wf="$MUT_FILE"
mutate a2-no-event-field "$WF" && simdef m-a2-noevent wipe wf="$MUT_FILE"
mutate a3-boot-exit5 "$WF" && simdef m-a3-exit5 wipe wf="$MUT_FILE" boot_verdict=wipe_boot_row_absent
mutate a3-created-zero "$WF" && simdef m-a3-created wipe wf="$MUT_FILE"
mutate a3-rrc-zero "$WF" && simdef m-a3-rrc wipe wf="$MUT_FILE" boot_rc=1
mutate a4-no-actions-call "$WF" && simdef m-a4-nocall "${FIN_W[@]}" wf="$MUT_FILE" actions_json="$ACT_ATTACH"
mutate a4-no-since "$WF" && simdef m-a4-nosince "${FIN_W[@]}" wf="$MUT_FILE" actions_json="$ACT_ATTACH"
mutate a4-never-detached "$WF" && simdef m-a4-never "${FIN_W[@]}" wf="$MUT_FILE" actions_json="$ACT_ATTACH"
mutate a5-listing-skip "$WF" && simdef m-a5-listing wipe wf="$MUT_FILE"
mutate sep-scan-skipped "$WF" && simdef m-sep-scan wipe wf="$MUT_FILE" world='json:{"VARIANT":"separated","FLAG_STATE":"false"}' scan=dirty
mutate sep-srr-ignored "$WF" && simdef m-sep-srr wipe wf="$MUT_FILE" world='json:{"VARIANT":"separated","FLAG_STATE":"false","SRR":"2"}'
mutate sep-reread-expect-dropped "$WF" && simdef m-sep-reread wipe wf="$MUT_FILE" world='json:{"VARIANT":"separated","FLAG_STATE":"false"}'
mutate evidence-run-record-dropped "$WF" && simdef m-evidence wipe wf="$MUT_FILE"
mutate a5-row-dt-empty "$WF" && simdef m-a5-rowdt wipe wf="$MUT_FILE"
mutate a5-server-from-luks "$WF" && simdef m-a5-server wipe wf="$MUT_FILE"
mutate b-w10-no-web-host-ssh "$WF" && simdef m-b-w10 wipe wf="$MUT_FILE"
mutate g-w7-raw-id "$WF" && simdef m-g-w7 wipe wf="$MUT_FILE" pt_id=12345 volume_id=000000012345
mutate g-w10-raw-id "$WF" && simdef m-g-w10 wipe wf="$MUT_FILE" pt_id=12345 volume_id=000000012345
mutate w10-rc-any "$WF" && simdef m-w10-rc wipe wf="$MUT_FILE" world_before='json:{"wipe_post_detach_read":{"HOST_ACCESS_FAIL":"1"}}' notify="$T_TRUE"
mutate w10-probe-excl "$WF" && simdef m-w10-probe wipe wf="$MUT_FILE" world_before='json:{"wipe_post_detach_read":{"HOST_PROBE_FAIL":"1"}}' notify="$T_TRUE"
mutate w12-always-deleted "$WF" && simdef m-w12-always wipe_finish wf="$MUT_FILE" origin_run=8000000555 world='json:{"PT_SERVER":"gone"}' origin_names=ids
SIMS_RUN=${#SIMS[@]}

# run them, three at a time (the machine is loaded; each run is a few seconds of bash)
# shellcheck disable=SC2016
printf '%s\n' "${SIMS[@]}" | sed "s#^#$T/specs/#; s#\$#.json#" | xargs -P 3 -n 1 bash -c 'python3 -I "$0" sim "$1" 2> "$1.err" || echo CRASH >> "$1.err"' "$T/wfsim.py"

echo "-- G. the simulator: read-before-destroy order, same-session evidence, markers, containment --"
R() { jq -r "$2" "$T/sim/$1/result.json" 2>/dev/null; }
EVL() { printf '%s' "$T/sim/$1/world/events.log"; }
simok() { [ -s "$T/sim/$1/result.json" ]; }
nev() { grep -cE -- "$2" "$(EVL "$1")" 2>/dev/null || true; }
evseq() { awk -F'\t' -v s="$2" -v d="$3" '$2 ~ s && $3 ~ d {print $1; exit}' "$(EVL "$1")"; }
stepseq() { awk -F'\t' '$3=="STEP start"{printf "%s ",$2}' "$(EVL "$1")"; }
callseq() { awk -F'\t' '$3!="STEP start" && $3!="stub" && !s[$2]++ {printf "%s ",$2}' "$(EVL "$1")"; }
ranset() { R "$1" '[.steps[]|select(.outcome!="skipped" and .outcome!="cancelled")|.key]|join(" ")'; }
failed_step() { R "$1" '[.steps[]|select(.outcome=="failure")|.key]|join(" ")'; }
stepout() { cat "$T"/sim/"$1"/steps/*_"$2".stdout 2>/dev/null; }
has_out() { local x; x="$(stepout "$1" "$2")"; grep -qE -- "$3" <<<"$x"; }
crashed=""
for _s in "${SIMS[@]}"; do simok "$_s" || crashed+=" $_s"; done
[ -z "$crashed" ] && pass "SIM: all ${#SIMS[@]} simulator runs produced a result" || fail "SIM: runs without a result:$crashed" "$(for _c in $crashed; do tail -n 2 "$T/specs/$_c.json.err"; done | head -c 400)"
GOLD_SEQ="$(stepseq gold-wipe)"
flow_ok() { # a wipe run that completed exactly like the golden one
  simok "$1" && [ "$(R "$1" .job_result)" = success ] && [ "$(R "$1" .outputs.phase)" = deleted ] && [ "$(stepseq "$1")" = "$GOLD_SEQ" ] \
    && [ "$(nev "$1" 'curl POST .*/actions/detach')" = 1 ] && [ "$(nev "$1" 'curl DELETE')" = 1 ] && [ "$(nev "$1" 'UNEXPECTED|REMOTE_USES')" = 0 ]
}
WIPE_RAN="wipe_confirm checkout wipe_doppler_install wipe_flag_precheck wipe_identity wipe_boot_read wipe_bridge wipe_key_fetch wipe_ssh_config wipe_host_assert wipe_flag_reread wipe_loader wipe_detach_gate wipe_detach wipe_post_detach_read wipe_reread wipe_delete_gate wipe_delete wipe_readback wipe_teardown"
if flow_ok gold-wipe && [ "$(ranset gold-wipe)" = "$WIPE_RAN" ]; then pass "G2-gold: a full mode=wipe run completes (phase=deleted), runs exactly the pinned steps, sends ONE detach POST and ONE DELETE, and meets no unexpected call"
else fail "G2-gold: the golden mode=wipe run did not complete as required" "$(R gold-wipe '[.steps[]|select(.outcome=="failure")|.key]|join(",")') job=$(R gold-wipe .job_result) phase=$(R gold-wipe .outputs.phase)"; fi
_want="wipe_flag_precheck wipe_identity wipe_boot_read wipe_bridge wipe_host_assert wipe_flag_reread wipe_loader wipe_detach wipe_post_detach_read wipe_reread wipe_delete wipe_readback wipe_teardown "
[ "$(callseq gold-wipe)" = "$_want" ] && pass "G2-calls: the stub log shows the calls in the order flag precheck < identity < boot read < bridge < host assert < flag re-read < loader < detach < post-detach read < re-read < delete < read-back < teardown" || fail "G2-calls: call order" "$(callseq gold-wipe)"
_bad=""
for ((_i = 0; _i + 1 < ${#CHAIN[@]}; _i++)); do
  _x="$(evseq gold-wipe "^${CHAIN[$_i]}\$" 'STEP start')"; _y="$(evseq gold-wipe "^${CHAIN[$((_i + 1))]}\$" 'STEP start')"
  { [ -n "$_x" ] && [ -n "$_y" ] && [ "$_x" -lt "$_y" ]; } || _bad+=" ${CHAIN[$_i]}<${CHAIN[$((_i + 1))]}"
done
[ -z "$_bad" ] && [ "${#CHAIN[@]}" -ge 12 ] && pass "G2-pairs-executed: in the stub log with sequence numbers every one of the $PAIRS_LIVE adjacent pairs identity < boot read < host assert < flag re-read < loader < detach gate < detach < post-detach read < re-read < delete gate < delete < read-back holds" || fail "G2-pairs-executed:$_bad (chain ${#CHAIN[@]})"
_p1="$(evseq gold-wipe wipe_host_assert 'host phase=pre ok')"; _p2="$(evseq gold-wipe wipe_detach 'curl POST')"; _p3="$(evseq gold-wipe wipe_post_detach_read 'host phase=post_detach ok')"; _p4="$(evseq gold-wipe wipe_delete 'curl DELETE')"; _p5="$(evseq gold-wipe wipe_readback 'curl GET')"
{ [ -n "$_p1" ] && [ -n "$_p5" ] && [ "$_p1" -lt "$_p2" ] && [ "$_p2" -lt "$_p3" ] && [ "$_p3" -lt "$_p4" ] && [ "$_p4" -lt "$_p5" ]; } && pass "G2-flip: the host read before the detach saw the device, the post-detach read came after the detach POST (the ssh stub flips to device-absent at the detach call), the DELETE after both, the read-back last" || fail "G2-flip: sequence $_p1 $_p2 $_p3 $_p4 $_p5"
_rw="$(awk -F'\t' '$3 ~ / RW /{print $2}' "$(EVL gold-wipe)" | sort -u | tr '\n' ' ')"
[ "$_rw" = "wipe_delete wipe_detach " ] && pass "G1-write-token-use: the write token class reached the Hetzner API only from wipe_detach and wipe_delete (read-only class everywhere else); read-only calls never POSTed or DELETEd" || fail "G1-write-token-use: RW steps: $_rw"
[ "$(nev gold-wipe 'curl (POST|DELETE) .* RO ')" = 0 ] || fail "G1-ro-mutates: a read-only credential issued a mutating call"
_ld="$(evseq gold-wipe '^wipe_loader$' 'loader inputs')"
_inp="$(awk -F'\t' '$3 ~ /^loader inputs=/{print $3}' "$(EVL gold-wipe)")"
[ "$_inp" = "loader inputs=doppler-token-infra-privileged source=tier_b" ] && [ "$(nev gold-wipe 'loader inputs')" = 1 ] && pass "G1-loader-dyn: the loader was called once, with ONLY doppler-token-infra-privileged, and answered source=tier_b" || fail "G1-loader-dyn: $_inp"
_after_leaks="$(awk -F'\t' -v L="$_ld" '$1>L && $3 ~ /env=[A-Za-z]/' "$(EVL gold-wipe)" | wc -l | tr -d ' ')"
_after_obs="$(awk -F'\t' -v L="$_ld" '$1>L && $3 ~ /env=/' "$(EVL gold-wipe)" | wc -l | tr -d ' ')"
{ [ "$_after_leaks" = 0 ] && [ "$_after_obs" -ge 9 ]; } && pass "G1-contain-dyn: of $_after_obs child processes (curl, doppler, host read) observed after the loader, none had a loaded name (HCLOUD_TOKEN, TF_VAR_*, AWS_*, TF_STATE_AWS_*, DOPPLER_TOKEN_TF) in its environment" || fail "G1-contain-dyn: leaks=$_after_leaks observed=$_after_obs"
jq -r '.secrets[]' "$T/sim/gold-wipe/result.json" > "$T/sim/gold-wipe/secrets.txt"
leakscan() { # <sim name>: number of lines holding a synthesized secret value in logs, argv, summaries and outputs
  local n="$1" d="$T/sim/$1" f c=0 x
  jq -r '.secrets[]' "$d/result.json" > "$d/secrets.txt" 2>/dev/null || return 1
  for f in "$d/world/events.log" "$d/world/envargv.log" "$d"/world/calls/*.argv "$d/summary.md" "$d"/out/* "$d"/notify/gho; do
    [ -f "$f" ] || continue
    x="$(grep -cF -f "$d/secrets.txt" "$f" || true)"; c=$((c + x))
  done
  for f in "$d"/steps/*.stdout "$d"/steps/*.stderr; do
    [ -f "$f" ] || continue
    x="$(grep -v '^::add-mask::' "$f" | grep -cF -f "$d/secrets.txt" || true)"; c=$((c + x))
  done
  printf '%s' "$c"
}
_envargv_n="$(wc -l < "$T/sim/gold-wipe/world/envargv.log" | tr -d ' ')"
{ [ "$(leakscan gold-wipe)" = 0 ] && [ "$_envargv_n" -ge 10 ]; } && pass "G1-no-leak-dyn: no synthesized secret (Doppler tokens, Tier-B token, loaded keys, either Hetzner token) appears in $_envargv_n recorded env(1) argv lines, any curl argv, any step output, summary or job output (add-mask lines excluded)" || fail "G1-no-leak-dyn: leaked lines $(leakscan gold-wipe), env argv lines $_envargv_n"
[ "$(R gold-wipe .outputs.refusal)" = "" ] && [ "$(R gold-wipe .outputs.started)" = true ] && [ "$(R gold-wipe .outputs.mode)" = wipe ] && pass "G3-outputs-exec: the success run publishes mode=wipe, started=true, phase=deleted and no refusal" || fail "G3-outputs-exec"
[ "$(R gold-wipe .notify.if)" = false ] && pass "N-if-exec: the notify if: is false for the successful wipe run" || fail "N-if-exec: notify would fire on a success"
# floors and the silent-log harness row
_floor() { [ "$(nev "$1" 'curl ')" -ge 12 ] && [ "$(nev "$1" 'doppler get')" -ge 3 ] && [ "$(nev "$1" 'host phase=')" -ge 2 ] && [ "$(nev "$1" 'precheck mode=')" -ge 2 ]; }
_floor gold-wipe && pass "G2-floor: the order-recording stub log holds $(nev gold-wipe 'curl ') curl, $(nev gold-wipe 'doppler get') doppler, $(nev gold-wipe 'host phase=') host and $(nev gold-wipe 'precheck mode=') precheck records" || fail "G2-floor: the stub log recorded too few calls"
_floor mute-events && fail "M-g2-7: a silent stub log (0 calls recorded) passed the floor row" || pass "M-g2-7: a stub log made silent (0 calls recorded) goes RED on the floor row"
MUTANTS_RUN=$((MUTANTS_RUN + 1))
# every adjacent swap goes RED
_bad=""; _n=0
for _s in "${SWAPS[@]}"; do _n=$((_n + 1)); flow_ok "$_s" && _bad+=" $_s"; done
[ -z "$_bad" ] && [ "$_n" -ge 11 ] && [ "$_n" = "$PAIRS_LIVE" ] && pass "M-g2-1: all $_n adjacent-pair swaps of the live chain (derived, not hard-coded) make the executed flow RED" || fail "M-g2-1: swap mutants that stayed GREEN:$_bad (ran $_n of $PAIRS_LIVE)"
# 2: the host assertion moved after the detach: the unstamped W7 epoch blocks the detach (nothing is sent); a SECOND host read
# placed after the detach reads the post-detach world (the ssh stub flips to device-absent at the detach call) and refuses
if ! flow_ok m-g2-2 && [ "$(nev m-g2-2 'curl POST')" = 0 ] && [ "$(failed_step m-g2-2)" = wipe_detach_gate ]; then pass "M-g2-2: moving the host assertion after the detach leaves the W7 epoch unstamped at W9a, so the detach is refused and nothing is sent (RED)"
else fail "M-g2-2: host-after-detach did not go RED the expected way" "$(failed_step m-g2-2)"; fi
if ! flow_ok m-g2-2b && [ "$(failed_step m-g2-2b)" = wipe_host_assert2 ] && [ "$(nev m-g2-2b 'host phase=pre REFUSED wipe_device_absent')" = 1 ]; then pass "M-g2-2b: a host assertion run after the detach reads the device-absent world and refuses (wipe_device_absent): the ssh stub is a state machine, so a reordered implementation reads the post-detach world, RED"
else fail "M-g2-2b: host-read-after-detach did not go RED the expected way" "$(failed_step m-g2-2b)"; fi
if ! flow_ok m-g2-2b-noflip; then pass "H2a: with the device-absent flip deleted the reordered mutant still goes RED on the recorded order (the order rows do not rest on the flip alone)"; else fail "H2a: the order rows pass without the flip"; fi
if ! flow_ok gold-noflip && [ "$(failed_step gold-noflip)" = wipe_detach ]; then pass "H2a2: with the flip deleted even the golden flow goes RED (the detach cannot be confirmed): the fixture is load-bearing, never stale-tolerant"; else fail "H2a2: golden flow passed without the state flip" "$(failed_step gold-noflip)"; fi
# 3: a second pre-destructive read that returns a changed fact stops the run before the delete
if ! flow_ok m-g2-3 && [ "$(nev m-g2-3 'curl DELETE')" = 0 ] && [ "$(R m-g2-3 .outputs.phase)" = detached ]; then pass "M-g2-3: a second read after a compliant first that returns a changed fact (protection on) refuses before the DELETE; the run ends at phase=detached"
else fail "M-g2-3: the changed-fact read did not stop the delete" "phase=$(R m-g2-3 .outputs.phase) deletes=$(nev m-g2-3 'curl DELETE')"; fi
# 4/5/6: the time bounds
stale_ok() { # <sim> <expected failing step> <expected phase> <mutating-call pattern that must be absent>
  simok "$1" && [ "$(failed_step "$1")" = "$2" ] && [ "$(R "$1" .outputs.phase)" = "$3" ] && [ "$(nev "$1" "$4")" = 0 ]
}
stale_ok stale-w7-gate wipe_detach_gate "" 'curl POST' && has_out stale-w7-gate wipe_detach_gate 'wipe_assertion_stale' && pass "G2-stale-w7-gate: a stub clock past the W7-epoch bound refuses at W9a (wipe_assertion_stale), the detach is NOT sent and no marker is written" || fail "G2-stale-w7-gate" "failed=$(failed_step stale-w7-gate) phase=$(R stale-w7-gate .outputs.phase)"
stale_ok stale-w7-helper wipe_detach detach_attempted 'curl POST' && pass "G2-stale-w7-helper: a clock that jumps between W9a and W9 is refused by the helper's own record_check right before the POST (no POST; phase detach_attempted)" || fail "G2-stale-w7-helper" "failed=$(failed_step stale-w7-helper)"
stale_ok stale-w10b-gate wipe_delete_gate detached 'curl DELETE' && pass "G2-stale-w10b-gate: more than 60 s past the W10b epoch refuses at W11a, the DELETE is NOT sent, no delete marker is written" || fail "G2-stale-w10b-gate" "failed=$(failed_step stale-w10b-gate) phase=$(R stale-w10b-gate .outputs.phase)"
stale_ok stale-w10b-helper wipe_delete delete_attempted 'curl DELETE' && pass "G2-stale-w10b-helper: the helper refuses a stale W10b record right before the DELETE (no DELETE; phase delete_attempted)" || fail "G2-stale-w10b-helper" "failed=$(failed_step stale-w10b-helper)"
flow_ok w10b-binding && pass "G2-w10b-binding: a 200 s gap before the re-read is fine: W11a is bounded from the W10b epoch, never from the W7 one" || fail "G2-w10b-binding" "failed=$(failed_step w10b-binding)"
for _p in "m-g2-5a:stale_ok m-g2-5a wipe_detach_gate '' 'curl POST':M-g2-5:removing the W9a record_check call site lets the marker be written on a stale record" \
          "m-g2-5c:stale_ok m-g2-5c wipe_delete_gate detached 'curl DELETE':M-g2-5c:removing the W11a record_check call site lets the marker be written on a stale record" \
          "m-g2h-5b:stale_ok m-g2h-5b wipe_detach detach_attempted 'curl POST':M-g2-5b:removing the helper's W7 record_check call site lets the POST go out on a stale record" \
          "m-g2h-5d:stale_ok m-g2h-5d wipe_delete delete_attempted 'curl DELETE':M-g2-5d:removing the helper's W10b record_check call site lets the DELETE go out on a stale record" \
          "m-g3-1b:stale_ok m-g3-1b wipe_detach_gate '' 'curl POST':M-g3-1b:writing the detach marker before the checks leaves a marker on a refused gate" \
          "m-g3-1c:stale_ok m-g3-1c wipe_delete_gate detached 'curl DELETE':M-g3-1c:writing the delete marker before the checks leaves a marker on a refused gate"; do
  IFS=: read -r _sim _cmd _label _msg <<<"$_p"
  if eval "$_cmd"; then fail "$_label: $_msg (the stale-clock row stayed GREEN)"; else pass "$_label: $_msg, so the executed stale-clock row goes RED"; fi
done
if ! flow_ok m-g2h-6 && [ "$(failed_step m-g2h-6)" = wipe_delete_gate ]; then pass "M-g2-6: without the W10b re-stamp the delete gate refuses (the record is unstamped), RED"; else fail "M-g2-6: missing re-stamp did not stop the delete" "$(failed_step m-g2h-6)"; fi
if flow_ok m-g2h-6b; then fail "M-g2-6b: bounding W11a from the W7 epoch stayed GREEN"; else pass "M-g2-6b: bounding W11a from the W7 epoch refuses a run whose W10b record is fresh (RED)"; fi
# 8: wipe_finish
finish_ok() { simok "$1" && [ "$(R "$1" .job_result)" = success ] && [ "$(R "$1" .outputs.phase)" = deleted ] && [ "$(nev "$1" 'curl POST')" = 0 ] && [ "$(nev "$1" 'curl DELETE')" = 1 ] && [ "$(nev "$1" 'UNEXPECTED|REMOTE_USES')" = 0 ]; }
FIN_RAN="wipe_confirm checkout wipe_doppler_install wipe_flag_precheck wipe_origin_check wipe_identity wipe_bridge wipe_key_fetch wipe_ssh_config wipe_host_assert wipe_flag_reread wipe_loader wipe_post_detach_read wipe_reread wipe_delete_gate wipe_delete wipe_readback wipe_teardown"
if finish_ok gold-finish && [ "$(ranset gold-finish)" = "$FIN_RAN" ] && [ "$(nev gold-finish 'host phase=finish ok')" = 2 ]; then pass "G2-finish: a wipe_finish run on a detached volume makes ZERO detach POSTs, runs the finish front, the loader, the post-detach read, the re-read, one DELETE and the read-back, and ends phase=deleted"
else fail "G2-finish: golden wipe_finish" "$(R gold-finish '[.steps[]|select(.outcome=="failure")|.key]|join(",")') phase=$(R gold-finish .outputs.phase) ran=$(ranset gold-finish)"; fi
_fo="$(callseq gold-finish)"
case "$_fo" in *"wipe_identity wipe_bridge"*"wipe_host_assert wipe_flag_reread wipe_loader wipe_post_detach_read wipe_reread wipe_delete wipe_readback"*) pass "G2-finish-order: the finish run keeps the order identity < host read < flag re-read < loader < host read < re-read < delete < read-back" ;; *) fail "G2-finish-order: $_fo" ;; esac
if finish_ok gold-finish-faithful; then pass "G2-finish-origin-names: with the gh step names the workflow really has, the wipe_finish origin check passes (the run lib matches step NAMES wipe_detach_gate / wipe_delete_gate)"
else fail "G2-finish-origin-names: with the real step names the origin check refuses (wipe_origin_run_gate_not_success): the gate steps must carry name: wipe_detach_gate / wipe_delete_gate" "$(stepout gold-finish-faithful wipe_origin_check | head -c 200) $(grep -h 'verdict=' "$T"/sim/gold-finish-faithful/steps/*wipe_origin_check.stdout 2>/dev/null | head -c 160)"; fi
if simok gold-finish-absent && [ "$(R gold-finish-absent .job_result)" = success ] && [ "$(R gold-finish-absent .outputs.phase)" = deleted ] && [ "$(nev gold-finish-absent 'loader inputs')" = 0 ] && ! grep -qE ' RW ' "$(EVL gold-finish-absent)" && [ "$(nev gold-finish-absent 'curl (POST|DELETE)')" = 0 ] && [ "$(ranset gold-finish-absent)" = "wipe_confirm checkout wipe_doppler_install wipe_flag_precheck wipe_origin_check wipe_identity wipe_flag_reread wipe_readback wipe_teardown" ]; then
  pass "G2-finish-absent: wipe_finish on an already-absent volume loads NO Tier-B token (the loader step is skipped), uses no write token and sends no mutating call, and ends phase=deleted from the read-back alone"
else fail "G2-finish-absent" "job=$(R gold-finish-absent .job_result) phase=$(R gold-finish-absent .outputs.phase) ran=$(ranset gold-finish-absent)"; fi
if ! finish_ok m-g2-8 && [ "$(R m-g2-8 .job_result)" = failure ]; then pass "M-g2-8: a wipe_finish front that skips writing its own verdict record fails before any delete (RED)"; else fail "M-g2-8: finish without a record stayed GREEN"; fi
# wipe_check
CHK_RAN="wipe_confirm checkout wipe_doppler_install wipe_flag_precheck wipe_identity wipe_boot_read wipe_bridge wipe_key_fetch wipe_ssh_config wipe_host_assert wipe_teardown"
if simok gold-check && [ "$(R gold-check .job_result)" = success ] && [ "$(ranset gold-check)" = "$CHK_RAN" ] && [ "$(nev gold-check 'loader inputs')" = 0 ] && [ "$(nev gold-check 'curl (POST|DELETE)')" = 0 ] && ! grep -qE ' RW ' "$(EVL gold-check)" \
   && [ "$(R gold-check .outputs.phase)" = "" ]; then pass "G2-check: wipe_check makes no loader, detach or delete call (no write token class at all) and ends green with no phase"
else fail "G2-check" "job=$(R gold-check .job_result) ran=$(ranset gold-check)"; fi
grep -qF 'NOT authorization; W3 would be flip_chained/none; layout listing exercised: counts only' "$T/sim/gold-check/summary.md" && grep -qE 'wipe_check elapsed_s=[0-9]+' <<<"$(stepout gold-check wipe_host_assert)" && grep -qE 'host phase=pre ok listing=run' "$(EVL gold-check)" && pass "G2-check-report: wipe_check prints elapsed_s, skips the layout listing and ends with the NOT authorization line carrying the would-be W3 verdict" || fail "G2-check-report" "$(cat "$T/sim/gold-check/summary.md" | head -c 200)"
if simok check-flag-false && [ "$(R check-flag-false .job_result)" = success ] && grep -qF 'W3 would be flip_chained/wipe_precondition_flag_not_true; layout listing exercised' "$T/sim/check-flag-false/summary.md"; then pass "G6-check-report-only: a flag that is not true leaves wipe_check green and reports W3 would be wipe_precondition_flag_not_true"; else fail "G6-check-report-only"; fi
# 7: markers, kills, cancels, end to end through the notify body
snot() { jq -r '(.notify.gho // "") + "\n" + (.notify.notify_body // "")' "$T/sim/$1/result.json"; }
mk_row() { # <label> <sim> <phase> <post-pattern absent> <word> <extra regex>
  local label="$1" s="$2" ph="$3" absent="$4" word="$5" extra="$6" nb
  nb="$(snot "$s")"
  if simok "$s" && [ "$(R "$s" .outputs.phase)" = "$ph" ] && [ "$(nev "$s" "$absent")" = 0 ] && grep -qE -- "$word" <<<"$nb" && grep -qE -- "$extra" <<<"$nb" && [ "$(R "$s" .notify.if)" = true ]; then pass "$label"
  else fail "$label" "phase=$(R "$s" .outputs.phase) job=$(R "$s" .job_result) notify-if=$(R "$s" .notify.if) | $(sed -n 's/^subject=//p' <<<"$nb" | head -1)"; fi
}
mk_row "G3-kill-after-W9a: a run killed after W9a and before W9's detach returns leaves phase=detach_attempted, sent no POST, and pages DETACH_ATTEMPTED_UNCONFIRMED with the finish command for THIS run" kill-detach detach_attempted 'curl POST' 'DETACH_ATTEMPTED_UNCONFIRMED' "origin_run=9000000123"
mk_row "G3-kill-after-W9: a run killed after W9 leaves phase=detached and pages VOLUME_DETACHED with the exact wipe_finish command" kill-post-detach detached 'curl DELETE' 'VOLUME_DETACHED' "mode=wipe_finish.*origin_run=9000000123"
mk_row "G3-kill-after-W11a: a run killed after W11a leaves phase=delete_attempted, sent no DELETE, and pages DELETE_ATTEMPTED_UNCONFIRMED" kill-delete delete_attempted 'curl DELETE' 'DELETE_ATTEMPTED_UNCONFIRMED' "mode=wipe_finish"
mk_row "G3-cancel-after-marker: a marker written by a step that is then cancelled still publishes (stub level: output files of a cancelled step are kept; the platform behaviour is confirmed on the first wipe_check run)" cancel-after-gate detach_attempted 'curl POST' 'DETACH_ATTEMPTED_UNCONFIRMED' "."
mk_row "G3-cancel-after-W9: the same for the detached marker written by the helper in W9" cancel-after-detach detached 'curl DELETE' 'VOLUME_DETACHED' "origin_run=9000000123"
mk_row "G3-delete-sent: a read-back that fails after the DELETE leaves phase=delete_sent and pages DELETE_SENT_UNCONFIRMED" delete-sent delete_sent 'zzzz-never' 'DELETE_SENT_UNCONFIRMED' "read the volume at the provider first"
mk_row "G3-teardown-after-delete: a failing teardown after a confirmed delete pages VOLUME_DELETED_TEARDOWN_FAILED, not DELETE_SENT_UNCONFIRMED" teardown-fail deleted 'zzzz-never' 'VOLUME_DELETED_TEARDOWN_FAILED' "only the runner teardown failed"
_snot="$(snot teardown-fail)"; { [ "$(R teardown-fail .job_result)" = failure ] && ! grep -q 'DELETE_SENT_UNCONFIRMED' <<<"$_snot"; } && pass "G3-teardown-wording: the teardown failure run is red and never says DELETE_SENT_UNCONFIRMED" || fail "G3-teardown-wording"
mk_row "G3-store-not-serving: a post-detach host read that fails publishes refusal=store_not_serving and pages STORE_NOT_SERVING_DO_NOT_FINISH (no finish command)" store-not-serving detached 'curl DELETE' 'STORE_NOT_SERVING_DO_NOT_FINISH' "Do NOT dispatch wipe_finish"
_snot="$(snot store-not-serving)"; grep -q -- '-f mode=wipe_finish -f' <<<"$_snot" && fail "G3-store-not-serving-cmd: DO-NOT-FINISH carried a finish command" || pass "G3-store-not-serving-cmd: the DO-NOT-FINISH page carries no finish command"
[ "$(R store-not-serving .outputs.refusal)" = store_not_serving ] && pass "G3-refusal-exec: refusal=store_not_serving is published by the post-detach read step" || fail "G3-refusal-exec" "$(R store-not-serving .outputs.refusal)"
mk_row "G3-already-detached: mode=wipe against an already-detached volume refuses at W4 with refusal=volume_already_detached and pages VOLUME_ALREADY_DETACHED carrying the wipe_finish command" already-detached "" 'curl (POST|DELETE)' 'VOLUME_ALREADY_DETACHED' "-f mode=wipe_finish.*origin_run="
mk_row "G3-refused-before-any-call: a W3 refusal publishes started=true with no phase and pages WIPE_REFUSED_BEFORE_ANY_CALL; not one Hetzner call was made" precheck-refused "" 'curl ' 'WIPE_REFUSED_BEFORE_ANY_CALL' "no irreversible call"
if simok typo-token && [ "$(R typo-token .outputs.started)" = false ] && [ "$(R typo-token .notify.if)" = false ] && [ "$(nev typo-token 'curl ')" = 0 ]; then pass "G3-typo-silent: a typo'd confirm token leaves mode= unwritten, started=false, the notify if: false (silent), and touches nothing"; else fail "G3-typo-silent" "started=$(R typo-token .outputs.started) if=$(R typo-token .notify.if)"; fi
mk_row "G3-flag-flip: a flag flipped to non-true between W3 and W7b refuses at W7b; no loader, no detach" flag-flip "" 'curl POST|loader inputs' 'WIPE_REFUSED_BEFORE_ANY_CALL' "."
[ "$(failed_step flag-flip)" = wipe_flag_reread ] && pass "G6-flag-flip-step: the refusal is raised by wipe_flag_reread" || fail "G6-flag-flip-step" "$(failed_step flag-flip)"
mk_row "G2-reread-protected: a W10b re-read that finds protection.delete=true refuses before the DELETE" reread-protected detached 'curl DELETE' 'VOLUME_DETACHED' "."
mk_row "G2-reread-reattached: a W10b re-read that finds the volume attached again refuses before the DELETE" reread-reattached detached 'curl DELETE' 'VOLUME_DETACHED' "."
if simok target-is-luks && [ "$(failed_step target-is-luks)" = wipe_identity ] && ! grep -qE ' RW ' "$(EVL target-is-luks)" && has_out target-is-luks wipe_identity 'wipe_target_is_luks'; then pass "G5-target-is-luks: a typed id equal to the LUKS volume refuses at W4 (wipe_target_is_luks) with no write-class call"; else fail "G5-target-is-luks" "$(failed_step target-is-luks)"; fi
if ! flow_ok m-g1-9 && [ "$(failed_step m-g1-9)" = wipe_detach_gate ] && [ "$(nev m-g1-9 'curl POST')" = 0 ] && has_out m-g1-9 wipe_detach_gate 'wipe_loader_not_tier_b'; then pass "G1-tier-b-exec: a loader that answers source=legacy is refused at W9a (wipe_loader_not_tier_b) before any marker or POST"; else fail "G1-tier-b-exec" "$(failed_step m-g1-9)"; fi
if simok no-tier-b && [ "$(failed_step no-tier-b)" = wipe_loader ] && [ "$(nev no-tier-b 'curl POST')" = 0 ] && [ "$(R no-tier-b .outputs.phase)" = "" ]; then pass "G1-no-fallback: a missing Tier-B token fails the loader step closed (no fallback to another token); nothing is sent"; else fail "G1-no-fallback" "$(failed_step no-tier-b)"; fi
# Guard 1 mutants, executed
if [ "$(awk -F'\t' '$3 ~ /env=[A-Za-z]/' "$(EVL m-g1-1)" | wc -l | tr -d ' ')" -ge 1 ]; then pass "M-g1-1: replacing a post-loader env -i child with env -u HCLOUD_TOKEN lets a loaded name (TF_VAR_*, AWS_*...) reach the child: the executed containment row goes RED"; else fail "M-g1-1: the executed containment row stayed GREEN"; fi
if [ "$(leakscan m-g1-2)" -ge 1 ]; then pass "M-g1-2: a credential on an env -i line is visible in the recorded env(1) argv: the executed leak row goes RED"; else fail "M-g1-2: executed leak row stayed GREEN"; fi
if ! flow_ok m-g1-9; then pass "M-g1-9: a loader given doppler-token-legacy answers source=legacy and the W9a gate refuses (executed), RED"; else fail "M-g1-9: legacy input stayed GREEN"; fi
if ! flow_ok m-g3-1d; then pass "M-g3-1: a marker step moved after its call (gate and detach swapped) is RED in the executed flow"; else fail "M-g3-1d"; fi
if [ "$(R m-g3-2 .outputs.phase)" != detach_attempted ]; then pass "M-g3-2: with W9a merged away (no marker of its own) a run killed at W9 leaves no detach_attempted marker (RED against the marker row)"; else fail "M-g3-2: marker row stayed GREEN"; fi
if forbidden "$(cat "$T/sim/m-g8-2a/summary.md")"; then pass "M-g8-2: a forbidden phrase added to a summary line shows in the executed summary the forbidden-phrase row scans (RED)"; else fail "M-g8-2: executed summary scan did not see the phrase"; fi
# Guard 8: every executed summary, stdout and notify body of the green runs is free of the forbidden phrases
_fb=0; _scanned=0
for _s in gold-wipe gold-finish gold-finish-absent gold-check check-flag-false kill-detach kill-post-detach kill-delete delete-sent teardown-fail store-not-serving already-detached precheck-refused; do
  _scanned=$((_scanned + 1))
  _txt="$(cat "$T/sim/$_s/summary.md" "$T"/sim/"$_s"/steps/*.stdout "$T"/sim/"$_s"/steps/*.stderr 2>/dev/null | grep -v '^::add-mask::' || true)"
  if forbidden "$_txt"; then _fb=$((_fb + 1)); fi
  if [ "$(R "$_s" '.notify // empty | .gho // empty')" != "" ] && forbidden "$(snot "$_s")"; then _fb=$((_fb + 1)); fi
done
[ "$_fb" = 0 ] && pass "G8-executed: no summary, step output or notify body of $_scanned executed runs contains a forbidden phrase (the widened CLO list; only the PA-36(f) standing sentence is whitelisted); the summaries claim only that the device was deleted at, or is absent from, the provider API" || fail "G8-executed: $_fb executed outputs contain a forbidden phrase"
_names="$(cat "$T"/sim/gold-wipe/steps/*.stdout 2>/dev/null | grep -v '^::add-mask::' | grep -ciE 'repositories|\.git\b|/srv|/var/lib' || true)"
[ "$_names" = 0 ] && pass "G8-no-names-exec: no executed wipe step output mentions a store path, repository or name" || fail "G8-no-names-exec: $_names lines"

echo "-- H. the fail-closed gates on their NEGATIVE paths, executed (each refused at its own step, zero detach POSTs, zero DELETEs) --"
negsim() { # <sim> <failed step> <verdict regex in that step's own output>
  simok "$1" && [ "$(R "$1" .job_result)" = failure ] && [ "$(failed_step "$1")" = "$2" ] && [ "$(nev "$1" 'curl POST .*/actions/detach')" = 0 ] \
    && [ "$(nev "$1" 'curl DELETE')" = 0 ] && [ "$(nev "$1" 'loader inputs')" = 0 ] && has_out "$1" "$2" "$3"
}
neg_row() { # <label> <sim> <step> <regex>
  if negsim "$2" "$3" "$4"; then pass "$1"
  else fail "$1" "failed=$(failed_step "$2") job=$(R "$2" .job_result) POST=$(nev "$2" 'curl POST .*/actions/detach') DELETE=$(nev "$2" 'curl DELETE') :: $(stepout "$2" "$3" | tail -n 2 | tr '\n' '|' | cut -c1-200)"; fi
}
neg_row "N-origin-branch: a wipe_finish whose origin run ran on another branch is refused at wipe_origin_check (wipe_origin_run_not_main); no detach, no delete" neg-origin-branch wipe_origin_check 'verdict=wipe_origin_run_not_main'
neg_row "N-origin-event: an origin run started by a push (not a dispatch) is refused at wipe_origin_check (wipe_origin_run_not_dispatch)" neg-origin-event wipe_origin_check 'verdict=wipe_origin_run_not_dispatch'
neg_row "N-origin-title: an origin run titled for another volume is refused at wipe_origin_check (wipe_origin_run_title_mismatch)" neg-origin-title wipe_origin_check 'verdict=wipe_origin_run_title_mismatch'
neg_row "N-origin-workflow: an origin run of another workflow is refused at wipe_origin_check (wipe_origin_run_workflow_mismatch)" neg-origin-workflow wipe_origin_check 'verdict=wipe_origin_run_workflow_mismatch'
neg_row "N-origin-gate: an origin run whose detach gate did not succeed (and has no delete gate) is refused at wipe_origin_check (wipe_origin_run_gate_not_success)" neg-origin-gate wipe_origin_check 'verdict=wipe_origin_run_gate_not_success'
neg_row "N-origin-createdat: an origin run whose createdAt is null is refused at wipe_origin_check (wipe_origin_run_unreadable reason=created_at), never an empty --since" neg-origin-createdat wipe_origin_check 'verdict=wipe_origin_run_unreadable reason=created_at'
neg_row "N-origin-unreadable: an origin run gh cannot read is refused at wipe_origin_check (wipe_origin_run_unreadable)" neg-origin-unreadable wipe_origin_check 'verdict=wipe_origin_run_unreadable'
neg_row "N-rollback: a git-data rollback run newer than the soak stamp refuses mode=wipe at wipe_flag_precheck (wipe_precondition_rollback_after_stamp) before any Hetzner call" neg-rollback wipe_flag_precheck 'verdict=wipe_precondition_rollback_after_stamp'
[ "$(nev neg-rollback 'curl ')" = 0 ] && pass "N-rollback-nocall: the rollback refusal happens before the first Hetzner call (0 curl calls)" || fail "N-rollback-nocall" "$(nev neg-rollback 'curl ') curl calls"
neg_row "N-runlist-unreadable: a gh run list that fails reads as unreadable, never as 'no rollback' (wipe_precondition_run_list_unreadable)" neg-runlist-unreadable wipe_flag_precheck 'verdict=wipe_precondition_run_list_unreadable'
neg_row "N-timeout-gh-list: a gh run list that hits its 60 s bound is an unreadable run list, never 'no rollback' (wipe_precondition_run_list_unreadable at wipe_flag_precheck)" neg-timeout-gh-list wipe_flag_precheck 'verdict=wipe_precondition_run_list_unreadable'
neg_row "N-timeout-gh-view: a gh run view that hits its 60 s bound is an unreadable origin run (wipe_origin_run_unreadable at wipe_origin_check); no detach, no delete" neg-timeout-gh-view wipe_origin_check 'verdict=wipe_origin_run_unreadable'
neg_row "N-timeout-doppler-w4: a read-only token fetch that hits its 60 s bound is an absent token (wipe_readonly_token_absent at wipe_identity), nothing sent" neg-timeout-doppler-w4 wipe_identity 'verdict=wipe_readonly_token_absent'
timeout_post() { # <sim> <failed step>: the bound fired at a step after the detach: that step refuses with the absent-token word, no delete call was made
  simok "$1" && [ "$(R "$1" .job_result)" = failure ] && [ "$(failed_step "$1")" = "$2" ] && [ "$(nev "$1" 'curl DELETE')" = 0 ] && has_out "$1" "$2" 'verdict=wipe_readonly_token_absent'
}
timeout_end() { simok "$1" && [ "$(R "$1" .job_result)" = failure ] && [ "$(failed_step "$1")" = wipe_readback ] && has_out "$1" wipe_readback 'verdict=wipe_readonly_token_absent' && [ "$(R "$1" .outputs.phase)" = delete_sent ]; }
timeout_post neg-timeout-doppler-w10b wipe_reread && pass "N-timeout-doppler-w10b: a re-read token fetch that hits its 60 s bound is an absent token (wipe_readonly_token_absent at wipe_reread) and no DELETE follows" || fail "N-timeout-doppler-w10b" "failed=$(failed_step neg-timeout-doppler-w10b)"
timeout_end neg-timeout-doppler-w12 && pass "N-timeout-doppler-w12: a read-back token fetch that hits its 60 s bound is an absent token (wipe_readonly_token_absent at wipe_readback); the phase stays delete_sent, never a success" || fail "N-timeout-doppler-w12" "failed=$(failed_step neg-timeout-doppler-w12)"
_td="$(nev gold-wipe 'timeout 60 doppler')"; _dg="$(nev gold-wipe 'doppler get HCLOUD_TOKEN_READONLY')"; _tg="$(nev gold-wipe 'timeout 60 gh')"; _tf="$(nev gold-finish 'timeout 60 gh')"
[ "$_td" = 3 ] && [ "$_dg" = 3 ] && [ "$_tg" = 1 ] && [ "$_tf" = 2 ] && pass "N-timeout-executed: in the golden runs every read-only token fetch ($_dg of $_dg) and every gh run call (wipe: $_tg, wipe_finish: $_tf) went through the 60 s bound" || fail "N-timeout-executed" "doppler timeout=$_td gets=$_dg gh wipe=$_tg finish=$_tf"
neg_row "N-stamp-absent: an absent soak stamp refuses mode=wipe at wipe_flag_precheck (wipe_precondition_stamp_absent)" neg-stamp-absent wipe_flag_precheck 'verdict=wipe_precondition_stamp_absent'
# ---- A1 (2026-10-15): the separated variant -----------------------------------------------------------------------
if simok gold-sep-wipe && [ "$(R gold-sep-wipe .job_result)" = success ] && [ "$(R gold-sep-wipe .outputs.phase)" = deleted ] \
   && grep -qxF 'wipe_variant=separated' <(stepout gold-sep-wipe wipe_flag_precheck) \
   && [ "$(nev gold-sep-wipe 'gh api')" -ge 3 ] && [ "$(nev gold-sep-wipe 'precheck mode=wipe_reread variant_exp=separated')" = 1 ] \
   && [ "$(nev gold-wipe 'precheck mode=wipe_reread variant_exp=flip_chained')" = 1 ] && [ ! -s "$T/sim/gold-sep-wipe/world/gh-refusals.log" ]; then
  pass "N-sep-gold: a separated mode=wipe run (flag false, no stamp) reads its variant, runs the REAL run-record scan over the gh shim (this run excluded), passes the printed variant to the W7b re-read as an expectation, and completes with phase=deleted; the flip_chained golden run passes flip_chained"
else fail "N-sep-gold" "job=$(R gold-sep-wipe .job_result) phase=$(R gold-sep-wipe .outputs.phase) failed=$(failed_step gold-sep-wipe)"; fi
if simok gold-sep-check && [ "$(R gold-sep-check .job_result)" = success ] && grep -qF 'NOT authorization; W3 would be separated/none; layout listing exercised: counts only' "$T/sim/gold-sep-check/summary.md" \
   && grep -qF '### git-data wipe evidence, pre-state' "$T/sim/gold-sep-check/summary.md" && grep -qF 'inherited, ADR-239 Amendment 2026-10-09' "$T/sim/gold-sep-check/summary.md"; then
  pass "N-sep-check: wipe_check in the separated state is green, reports W3 would be separated/none and prints the labelled pre-state evidence block (measured / inherited)"
else fail "N-sep-check" "job=$(R gold-sep-check .job_result) :: $(head -c 300 "$T/sim/gold-sep-check/summary.md")"; fi
if simok gold-wipe && grep -qF '### git-data wipe evidence, pre-state' "$T/sim/gold-wipe/summary.md" && grep -qF '### git-data wipe evidence, run record' "$T/sim/gold-wipe/summary.md" \
   && grep -qE 'run id 9000000123, dispatched by' "$T/sim/gold-wipe/summary.md" && grep -qF 'newest boot_complete row at 2' "$T/sim/gold-wipe/summary.md"; then
  pass "N-evidence: a completed mode=wipe run prints the labelled pre-state block (W7: ids, variant, boot row glossed as boot-time only, counts only, the inherited residue statement) and the run-record block (W12: run id, dispatcher, the environment approval named as not read here)"
else fail "N-evidence" "$(grep -c 'evidence' "$T/sim/gold-wipe/summary.md" 2>/dev/null) evidence headings"; fi
if simok m-evidence && ! grep -qF '### git-data wipe evidence, run record' "$T/sim/m-evidence/summary.md"; then pass "M-evidence-run-record-dropped: without the W12 run-record echo the golden summary lacks the block (the N-evidence row goes RED)"
else fail "M-evidence-run-record-dropped: the run record is still printed with its echo removed"; fi
neg_row "N-sep-dirty: a separated run whose run records show a flag write refuses at wipe_flag_precheck (wipe_separated_store_dirty) before any Hetzner call" neg-sep-dirty wipe_flag_precheck 'verdict=wipe_separated_store_dirty'
neg_row "N-sep-inflight: a separated run with ANOTHER cutover run in progress refuses (wipe_separated_cutover_in_flight); its own run does not count" neg-sep-inflight wipe_flag_precheck 'verdict=wipe_separated_cutover_in_flight'
neg_row "N-sep-srr: a separated run whose LUKS store root holds entries (store_root_repos=2) refuses at wipe_host_assert (wipe_separated_store_root_populated) before the loader and the detach" neg-sep-srr wipe_host_assert 'verdict=wipe_separated_store_root_populated'
neg_row "N-sep-flip-race: a flip that begins between W3 and W7b refuses at the re-read (wipe_precondition_variant_changed expected=separated got=flip_chained); nothing was detached" sep-flip-race wipe_flag_reread 'verdict=wipe_precondition_variant_changed expected=separated got=flip_chained'
if simok chk-sep-srr && [ "$(R chk-sep-srr .job_result)" = success ] && grep -qF 'W3 would be separated/wipe_separated_store_root_populated; layout listing exercised' "$T/sim/chk-sep-srr/summary.md"; then
  pass "N-sep-check-srr: wipe_check stays green over a populated store root and reports the would-be refusal in its closing line (report-only)"
else fail "N-sep-check-srr" "job=$(R chk-sep-srr .job_result) :: $(head -c 300 "$T/sim/chk-sep-srr/summary.md")"; fi
if simok neg-rollback-check && [ "$(R neg-rollback-check .job_result)" = success ] && grep -qF 'W3 would be flip_chained/wipe_precondition_rollback_after_stamp; layout listing exercised' "$T/sim/neg-rollback-check/summary.md" && [ "$(nev neg-rollback-check 'curl (POST|DELETE)')" = 0 ]; then
  pass "N-rollback-check: the same rollback leaves wipe_check GREEN and reports W3 would be wipe_precondition_rollback_after_stamp (report-only; only mode=wipe is stopped by it)"
else fail "N-rollback-check" "job=$(R neg-rollback-check .job_result) :: $(head -c 200 "$T/sim/neg-rollback-check/summary.md")"; fi
neg_row "N-boot-verdict: a boot-read verdict that is not wipe_boot_ok refuses at wipe_boot_read (the verdict word is the step's own), before the bridge, the host read and the loader" neg-boot-verdict wipe_boot_read 'verdict=wipe_boot_row_absent'
[ "$(nev neg-boot-verdict 'host phase=')" = 0 ] && [ "$(nev neg-boot-verdict 'bridge')" = 0 ] && pass "N-boot-nohost: nothing after the refused boot read ran (no bridge, no host read)" || fail "N-boot-nohost"
neg_row "N-boot-unreadable: a boot-signal read that failed (rc 1) is wipe_boot_unreadable at wipe_boot_read, not an accepted row" neg-boot-unreadable wipe_boot_read 'verdict=wipe_boot_unreadable'
neg_row "N-actions-attach: a detach, then an attach, then a detach after the origin run started is not evidence: refused at wipe_identity (wipe_detach_not_evidenced reason=attach_after)" neg-actions-attach wipe_identity 'wipe_detach_not_evidenced.*reason=attach_after'
neg_row "N-actions-old: the only detach started BEFORE the origin run: refused at wipe_identity (reason=started_before_origin)" neg-actions-old wipe_identity 'wipe_detach_not_evidenced.*reason=started_before_origin'
neg_row "N-actions-none: no detach action at all: refused at wipe_identity (reason=no_detach)" neg-actions-none wipe_identity 'wipe_detach_not_evidenced.*reason=no_detach'
_gh_ref=""; for _s in gold-wipe gold-finish gold-finish-faithful gold-finish-absent gold-check gold-sep-wipe gold-sep-check lead-zero neg-origin-branch neg-rollback neg-boot-verdict neg-actions-attach; do [ ! -s "$T/sim/$_s/world/gh-refusals.log" ] || _gh_ref+=" $_s"; done
[ -z "$_gh_ref" ] && pass "N-gh-argv: the gh shim (which accepts only the modeled argv: subcommand, --workflow, --limit from the run lib, the --json field list, the dispatched origin run id) refused nothing in 10 runs" || fail "N-gh-argv: the gh shim refused an argv in:$_gh_ref" "$(cat "$T"/sim/gold-wipe/world/gh-refusals.log 2>/dev/null | head -3)"
# listing, row epoch and ids reach the host verb as the record and the boot read say
_clk=1760457600
if [ "$(nev gold-wipe "host phase=pre ok listing=run row_dt=$((_clk - 600)) vid=900000001")" = 1 ] && [ "$(nev gold-check 'host phase=pre ok listing=run row_dt=')" = 1 ] && [ "$(nev gold-wipe 'host (IDMISMATCH|BADLISTING|BADROWDT|BADPRE_ONLY)')" = 0 ]; then
  pass "N-host-inputs: the W7 host read of a mode=wipe run asks for the layout listing (run), carries the boot row's epoch as its row date and the record's ids; a wipe_check run now runs it too (A1, counts only)"
else fail "N-host-inputs" "$(grep -a 'host phase=pre' "$(EVL gold-wipe)" | head -2)"; fi
if flow_ok lead-zero && [ "$(nev lead-zero 'host phase=pre ok listing=run row_dt=[0-9]+ vid=12345 ')" = 1 ] && [ "$(nev lead-zero 'host phase=post_detach ok vid=12345 ')" = 1 ] && [ "$(nev lead-zero 'vid=000000012345')" = 0 ]; then
  pass "N-lead-zero: volume_id=000000012345 is normalised in the record (plaintext_id=12345) and W7 and W10 send the RECORD's id (12345) to the host verb; the run completes (phase=deleted)"
else fail "N-lead-zero" "job=$(R lead-zero .job_result) failed=$(failed_step lead-zero) $(grep -a 'host phase' "$(EVL lead-zero)" | head -3 | tr '\t' ' ')"; fi
# W10: the host verb's refusal word is published only for an exit-5 verdict
if simok host-read-access-fail && [ "$(failed_step host-read-access-fail)" = wipe_post_detach_read ] && [ "$(R host-read-access-fail .outputs.refusal)" = "" ] && [ "$(R host-read-access-fail .outputs.phase)" = detached ] \
   && grep -qE 'VOLUME_DETACHED' <<<"$(snot host-read-access-fail)" && ! grep -qE 'STORE_NOT_SERVING' <<<"$(snot host-read-access-fail)" && [ "$(nev host-read-access-fail 'curl DELETE')" = 0 ]; then
  pass "N-w10-rc3: a post-detach host read that did not answer (access gate, exit 3) fails W10 without refusal=store_not_serving: phase detached, VOLUME_DETACHED with the finish command, no DO-NOT-FINISH, no delete"
else fail "N-w10-rc3" "failed=$(failed_step host-read-access-fail) refusal=$(R host-read-access-fail .outputs.refusal) phase=$(R host-read-access-fail .outputs.phase)"; fi
if simok host-read-probe-failed && [ "$(failed_step host-read-probe-failed)" = wipe_post_detach_read ] && [ "$(R host-read-probe-failed .outputs.refusal)" = "" ] && [ "$(R host-read-probe-failed .outputs.phase)" = detached ] \
   && grep -qE 'VOLUME_DETACHED' <<<"$(snot host-read-probe-failed)" && ! grep -qE 'STORE_NOT_SERVING' <<<"$(snot host-read-probe-failed)" && [ "$(nev host-read-probe-failed 'curl DELETE')" = 0 ]; then
  pass "N-w10-probe: a post-detach host read that exits 5 with verdict=probe_failed (unanswered) publishes no refusal: VOLUME_DETACHED with the finish command, no DO-NOT-FINISH"
else fail "N-w10-probe" "refusal=$(R host-read-probe-failed .outputs.refusal) phase=$(R host-read-probe-failed .outputs.phase)"; fi
if simok store-not-serving && [ "$(R store-not-serving .outputs.refusal)" = store_not_serving ] && ! grep -qF 'verdict=probe_failed' "$T/sim/store-not-serving/steps/"*wipe_post_detach_read.stdout; then pass "N-w10-verdict: a real store verdict (exit 5, not probe_failed) still publishes refusal=store_not_serving"; else fail "N-w10-verdict"; fi
if simok m-w10-probe && [ "$(R m-w10-probe .outputs.refusal)" = store_not_serving ]; then pass "M-w10-probe: without the probe_failed exclusion an unanswered read pages DO-NOT-FINISH (N-w10-probe goes RED)"; else fail "M-w10-probe: the mutant did not change the refusal" "$(R m-w10-probe .outputs.refusal)"; fi
# W12 summaries: a delete is claimed only when THIS run's delete step wrote its marker; the standing PA-36(f) sentence closes every summary
_sm() { cat "$T/sim/$1/summary.md" 2>/dev/null; }
_cnt() { grep -cF -- "$STANDING_TXT" <<<"$(_sm "$1")" || true; }
if grep -qF 'the plaintext volume was deleted at the provider API' "$T/sim/gold-wipe/summary.md" && grep -qF 'It does not state that the volume was empty or held no personal data' "$T/sim/gold-wipe/summary.md" \
   && ! grep -qF 'absent at the provider API' "$T/sim/gold-wipe/summary.md" && [ "$(_cnt gold-wipe)" = 1 ] && [ "$(_cnt gold-finish)" = 1 ]; then
  pass "G8-claim: the summary of a run that sent the delete says the volume was deleted at the provider API, disclaims what the volume held ('does not state that the volume was empty or held no personal data'), and ends with the PA-36(f) standing sentence once"
else fail "G8-claim" "$(_sm gold-wipe | tail -n 5 | tr '\n' '|' | cut -c1-300)"; fi
if grep -qF 'git-data wipe: the plaintext volume is absent at the provider API' "$T/sim/gold-finish-absent/summary.md" && grep -qF 'This run made no delete call. The delete outcome is in the origin run (run id 8000000555).' "$T/sim/gold-finish-absent/summary.md" \
   && ! grep -qF 'was deleted at the provider API' "$T/sim/gold-finish-absent/summary.md" && [ "$(_cnt gold-finish-absent)" = 1 ]; then
  pass "G8-claim-absent: a wipe_finish that found the volume already absent says it is ABSENT at the provider API, that it made no delete call, names the origin run (8000000555), and still carries the standing sentence once"
else fail "G8-claim-absent" "$(_sm gold-finish-absent | tail -n 5 | tr '\n' '|' | cut -c1-300)"; fi
grep -qF 'was deleted at the provider API' "$T/sim/gold-finish/summary.md" && ! grep -qF 'absent at the provider API' "$T/sim/gold-finish/summary.md" && pass "G8-claim-finish: a wipe_finish that sent the delete itself (volume detached) says it was deleted" || fail "G8-claim-finish"
if ! grep -qF 'was deleted at the provider API' "$T/sim/m-w12-always/summary.md" 2>/dev/null; then fail "M-w12: the always-deleted mutant did not claim a delete on an absent volume (the row has no teeth)"; else pass "M-w12-always: with the DELETE_PHASE test removed the absent-volume summary claims a delete (G8-claim-absent goes RED)"; fi
# the one-line-edit mutants
mut_neg() { # <label> <sim> <step> <regex>: the scenario is NO LONGER refused at its own step (the gate is disarmed)
  if negsim "$2" "$3" "$4"; then fail "$1 (the negative scenario is still refused: the mutant did not disarm the gate)"; else pass "$1"; fi
}
mut_neg "M-a1-exit5: deleting the exit 5 of the origin check lets a bad origin run through (the negative row goes RED)" m-a1-exit5 wipe_origin_check 'verdict=wipe_origin_run_not_main'
mut_neg "M-a1-rc0: '|| rc=0' on the detach-gate check lets a bad origin run through (RED)" m-a1-rc0 wipe_origin_check 'verdict=wipe_origin_run_not_main'
mut_neg "M-a1-delgate: a delete-gate fallback that always passes lets a bad origin run through (RED)" m-a1-delgate wipe_origin_check 'verdict=wipe_origin_run_not_main'
for _p in "m-a1-wrongrun:gh run view of a different run id" "m-a1-nojobs:dropping jobs from --json" "m-a1-nowfname:dropping workflowName from --json"; do
  _sim="${_p%%:*}"; _msg="${_p#*:}"
  if ! finish_ok "$_sim" && [ -s "$T/sim/$_sim/world/gh-refusals.log" ]; then pass "M-${_sim#m-}: $_msg is refused by the argv-exact gh shim and the golden wipe_finish goes RED"; else fail "M-${_sim#m-}: $_msg stayed GREEN or was not seen by the shim" "job=$(R "$_sim" .job_result)"; fi
done
mut_neg "M-sep-scan-skipped: a run-record scan whose result is discarded lets a separated wipe through over a flip record (RED)" m-sep-scan wipe_flag_precheck 'verdict=wipe_separated_store_dirty'
mut_neg "M-sep-srr-ignored: dropping the store-root comparison lets a populated store root through (RED)" m-sep-srr wipe_host_assert 'verdict=wipe_separated_store_root_populated'
if simok m-sep-reread && [ "$(R m-sep-reread .job_result)" != success ]; then pass "M-sep-reread-expect-dropped: a W7b that no longer passes the printed variant cannot complete a separated wipe (the golden separated run goes RED)"
else fail "M-sep-reread-expect-dropped: the golden separated run still completes without the W7b expectation"; fi
mut_neg "M-a2-exit5: deleting the exit 5 of the rollback-recency refusal lets a rollback after the stamp through (RED)" m-a2-exit5 wipe_flag_precheck 'verdict=wipe_precondition_rollback_after_stamp'
mut_neg "M-a2-wipemode: WIPE_MODE bound to wipe_check turns the refusal into a report for a real wipe (RED)" m-a2-wipemode wipe_flag_precheck 'verdict=wipe_precondition_rollback_after_stamp'
mut_neg "M-a2-fallback: an unreadable run list accepted as '[]' lets the wipe through (RED)" m-a2-fallback wipe_flag_precheck 'verdict=wipe_precondition_run_list_unreadable'
for _p in "m-a2-limit:--limit 10" "m-a2-noevent:dropping event from --json"; do
  _sim="${_p%%:*}"; _msg="${_p#*:}"
  if ! flow_ok "$_sim" && [ -s "$T/sim/$_sim/world/gh-refusals.log" ]; then pass "M-${_sim#m-}: $_msg is refused by the argv-exact gh shim (the lib's list-reach test needs the whole window) and the golden wipe goes RED"; else fail "M-${_sim#m-}: $_msg stayed GREEN" "job=$(R "$_sim" .job_result)"; fi
done
mut_neg "M-t-gh-list: without the 60 s bound on gh run list the timed-out scenario is no longer refused (the N-timeout-gh-list row goes RED)" m-t-gh-list wipe_flag_precheck 'verdict=wipe_precondition_run_list_unreadable'
mut_neg "M-t-gh-view: without the 60 s bound on gh run view the timed-out scenario is no longer refused (the N-timeout-gh-view row goes RED)" m-t-gh-view wipe_origin_check 'verdict=wipe_origin_run_unreadable'
mut_neg "M-t-doppler-w4: without the 60 s bound on the W4 token fetch the timed-out scenario is no longer refused (RED)" m-t-doppler-w4 wipe_identity 'verdict=wipe_readonly_token_absent'
if timeout_post m-t-doppler-w10b wipe_reread; then fail "M-t-doppler-w10b: the unbounded re-read fetch stayed GREEN"; else pass "M-t-doppler-w10b: without the 60 s bound on the W10b token fetch the timed-out scenario is no longer refused (RED)"; fi
if timeout_end m-t-doppler-w12; then fail "M-t-doppler-w12: the unbounded read-back fetch stayed GREEN"; else pass "M-t-doppler-w12: without the 60 s bound on the W12 token fetch the timed-out scenario is no longer refused (RED)"; fi
mut_neg "M-a3-exit5: deleting the exit 5 of the boot-verdict refusal lets a missing boot row through (RED)" m-a3-exit5 wipe_boot_read 'verdict=wipe_boot_row_absent'
mut_neg "M-a3-rrc: passing 0 for the boot read's rc lets a failed read through (RED)" m-a3-rrc wipe_boot_read 'verdict=wipe_boot_unreadable'
if ! flow_ok m-a3-created && [ "$(failed_step m-a3-created)" = wipe_boot_read ]; then pass "M-a3-created: passing 0 for the server's created epoch is refused by the boot verdict (the stub checks the argument against the server's own created time) and the golden wipe goes RED"; else fail "M-a3-created: the created-epoch argument is unchecked" "failed=$(failed_step m-a3-created)"; fi
mut_neg "M-a4-nocall: dropping the 'helper actions --since' call lets an attach-after-detach history through (RED)" m-a4-nocall wipe_identity 'wipe_detach_not_evidenced'
mut_neg "M-a4-nosince: dropping --since lets an attach-after-detach history through (report mode accepts it) (RED)" m-a4-nosince wipe_identity 'wipe_detach_not_evidenced'
mut_neg "M-a4-never: a '\$vs == detached' test that is never true skips the evidence call (RED)" m-a4-never wipe_identity 'wipe_detach_not_evidenced'
for _p in "m-a5-listing:WIPE_LISTING=skip for a real wipe (the plaintext-not-empty check never runs)" "m-a5-rowdt:an empty WIPE_ROW_DT" "m-a5-server:the server id read from luks_id" "m-b-w10:dropping WEB_HOST_SSH from the W10 allow-list"; do
  _sim="${_p%%:*}"; _msg="${_p#*:}"
  if ! flow_ok "$_sim"; then pass "M-${_sim#m-}: $_msg refuses at the host stub (it reads the same inputs the real verb does) and the golden wipe goes RED"; else fail "M-${_sim#m-}: $_msg stayed GREEN"; fi
done
for _m in m-g-w7 m-g-w10; do
  if ! flow_ok "$_m" && { [ "$(nev "$_m" 'vid=000000012345')" -ge 1 ] || [ "$(nev "$_m" 'host IDMISMATCH')" -ge 1 ]; }; then pass "M-${_m#m-}: sending \$VOLUME_ID (000000012345) instead of the record's id to the host verb is refused by the id-exact host stub (RED)"; else fail "M-${_m#m-}: the raw id reached the host unnoticed" "$(grep -a 'host' "$(EVL "$_m")" | head -2 | tr '\t' ' ')"; fi
done
if simok m-w10-rc && [ "$(R m-w10-rc .outputs.refusal)" = store_not_serving ] && grep -qE 'STORE_NOT_SERVING' <<<"$(snot m-w10-rc)"; then pass "M-w10-rc: publishing the refusal for any non-zero exit pages DO-NOT-FINISH for an access-gate failure (the N-w10-rc3 row goes RED)"; else fail "M-w10-rc: the any-exit mutant did not change the published refusal" "refusal=$(R m-w10-rc .outputs.refusal)"; fi

echo "-- I. the wipe job's copied ssh_config and the workflow-to-script contract, EXECUTED over the real step bodies --"
mkdir -p "$T/dump" "$T/exec"
dump_step() { # <name> <workflow> <job> <step> <ctx-json>: the step's real run: text to $T/dump/<name>.sh, its env: to .env.json
  jmk "$T/dump/$1.json" wf="$2" job="$3" step="$4" ctx="json:$5" out="$T/dump/$1"
  "${PY[@]}" dump "$T/dump/$1.json" 2> "$T/dump/$1.err"
}
ssh-keygen -q -t ed25519 -N '' -C gdw-pin-fixture -f "$T/gdw-pin-key" || { printf 'FAIL SETUP: ssh-keygen gd pin\n' >&2; exit 1; }
GDW_PIN="$(cut -d' ' -f1,2 "$T/gdw-pin-key.pub")"
cat > "$T/scw.py" <<'UEOF'
import sys, re, subprocess
cfg, kh = sys.argv[1], sys.argv[2]
try: lines = open(cfg).read().splitlines()
except Exception as e: print("unreadable"); sys.exit()
blocks = {}; cur = None; problems = []
for l in lines:
    t = l.strip()
    if not t: continue
    kw = t.split(None, 1)[0].lower()
    if kw in ("host", "match"):
        cur = t; blocks[cur] = []; continue
    if cur is None: problems.append("option outside a block"); continue
    blocks[cur].append(t)
if sorted(blocks) != ["Host 10.0.1.10", "Host 10.0.1.20"]: problems.append("hosts %r" % sorted(blocks))
want = {"Host 10.0.1.10": "web-1", "Host 10.0.1.20": "git-data"}
for h, alias in want.items():
    o = blocks.get(h, [])
    for need in ("StrictHostKeyChecking yes", "ForwardAgent no", "ClearAllForwardings yes", "UpdateHostKeys no", "HostKeyAlias " + alias, "GlobalKnownHostsFile /dev/null", "UserKnownHostsFile " + kh, "IdentitiesOnly yes", "BatchMode yes"):
        if need not in o: problems.append("%s lacks %s" % (h, need))
    for k in ("stricthostkeychecking", "forwardagent", "clearallforwardings", "updatehostkeys", "hostkeyalias"):
        if sum(1 for x in o if x.lower().split()[0] == k) != 1: problems.append("%s: %s not exactly once" % (h, k))
if not any(x.startswith("ProxyCommand ssh -F %s -W 10.0.1.20:22 10.0.1.10" % cfg) for x in blocks.get("Host 10.0.1.20", [])): problems.append("no ProxyCommand through web-1")
try:
    for host, alias in (("10.0.1.10", "web-1"), ("10.0.1.20", "git-data")):
        g = subprocess.run(["ssh", "-G", "-F", cfg, host], capture_output=True, text=True, timeout=20).stdout.lower().splitlines()
        want_g = {"stricthostkeychecking true", "forwardagent no", "clearallforwardings yes", "updatehostkeys false", "hostkeyalias " + alias, "globalknownhostsfile /dev/null"}
        miss = sorted(w for w in want_g if w not in g)
        if miss: problems.append("ssh -G %s: %s" % (host, miss))
except FileNotFoundError:
    problems.append("ssh unavailable")
print("OK" if not problems else "; ".join(problems))
UEOF
scw_check() { # <name> <workflow>: OK, or the problems found in the config the wipe job's real ssh_config body writes
  local n="$1" wfp="$2" sr="$T/exec/scw-$1"
  assert_fixture_dir "$sr"; rm -rf "$sr"; mkdir -p "$sr/rt"
  dump_step "scw-$n" "$wfp" wipe wipe_ssh_config '{}' || { echo "dump failed"; return; }
  printf 'fixture-root-key\n' > "$sr/rt/gd-root-key"; printf 'fixture-ci-key\n' > "$sr/ci-key"; printf '%s\n' "$GDW_PIN" > "$sr/rt/git-data.pin"
  if ! env -i PATH=/usr/bin:/bin HOME="$sr" RUNNER_TEMP="$sr/rt" GITHUB_WORKSPACE="$ROOT" CI_SSH_KEYFILE="$sr/ci-key" bash --noprofile --norc -eo pipefail "$T/dump/scw-$n.sh" > "$sr/stdout" 2>&1; then
    echo "writer failed: $(tr '\n' '|' < "$sr/stdout" | cut -c1-200)"; return
  fi
  python3 -I "$T/scw.py" "$sr/rt/gd-ssh-config" "$sr/rt/gd-known-hosts"
}
_r="$(scw_check pristine "$WF")"
[ "$_r" = OK ] && pass "SCW: the wipe job's REAL ssh_config body, executed, writes both Host blocks with StrictHostKeyChecking yes, ForwardAgent no, ClearAllForwardings yes, UpdateHostKeys no, HostKeyAlias web-1 / git-data, GlobalKnownHostsFile /dev/null and the web-1 ProxyCommand, and real OpenSSH (ssh -G) resolves them the same way" || fail "SCW: the wipe ssh_config writer" "$_r"
for _m in e-shkc-lax e-forward-agent e-hostkeyalias e-updatehostkeys; do
  mutate "$_m" "$WF" && { _r="$(scw_check "m-$_m" "$MUT_FILE")"
    if [ "$_r" != OK ]; then pass "M-$_m: the executed ssh_config row goes RED ($(cut -c1-70 <<<"$_r"))"; else fail "M-$_m: the executed ssh_config row stayed GREEN"; fi; }
done

# W10 under exactly its exec env -i allow-list, against the REAL git-data-cutover.sh with an ssh PATH shim
envrow_run() { # <name> <workflow> <shim mode: ok|verdict|accessfail>: prints "rc|refusal|ssh-calls|has-unset|last-call"
  local n="$1" wfp="$2" mode="$3" d="$T/exec/w10-$1" rc=0
  assert_fixture_dir "$d"; rm -rf "$d"; mkdir -p "$d/ws/apps/web-platform/infra" "$d/bin" "$d/rt"
  ln -s "$HOST_VERB" "$d/ws/apps/web-platform/infra/git-data-cutover.sh"; ln -s "$HOST_ASSERT" "$d/ws/apps/web-platform/infra/git-data-wipe-assert.sh"
  printf 'server_id=800000001\nplaintext_id=12345\nluks_id=900000002\n' > "$d/rt/git-data-wipe-record"
  : > "$d/out"; : > "$d/sum"; : > "$d/ssh.log"; printf '%s' "$mode" > "$d/shim.mode"
  cat > "$d/bin/ssh" <<SHIM
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$d/ssh.log"
mode="\$(cat "$d/shim.mode")"
last="\${*: -1}"
if [[ " \$* " == *" -W "* ]]; then echo "SSH-2.0-OpenSSH_shim"; exit 0; fi
if [[ "\$last" == true ]]; then
  [ "\$mode" = accessfail ] && exit 255
  if [ "\$mode" = accessfail_once ] && [ ! -e "$d/af.done" ]; then : > "$d/af.done"; exit 255; fi
  exit 0
fi
if [[ "\$last" == WIPE_PHASE=*" bash -s" ]]; then
  cat > /dev/null
  [ "\$mode" = verdict ] && exit 41
  [ "\$mode" = probefail ] && { echo "something else entirely"; exit 0; }
  if [ "\$mode" = probefail_once ] && [ ! -e "$d/pf.done" ]; then : > "$d/pf.done"; echo "something else entirely"; exit 0; fi
  ph="\${last#WIPE_PHASE=}"; ph="\${ph%% *}"
  echo "wipe_assert \$ph ok byid=gone mapper_read=ok store_root=ok"; exit 0
fi
exit 255
SHIM
  chmod +x "$d/bin/ssh"
  : > "$d/sleep.log"
  printf '#!/usr/bin/env bash\nprintf "sleep %%s\\n" "$*" >> "%s/sleep.log"\n' "$d" > "$d/bin/sleep"; chmod +x "$d/bin/sleep"
  dump_step "w10-$n" "$wfp" wipe wipe_post_detach_read "{\"runner\":{\"temp\":\"$d/rt\"},\"steps\":{\"wipe_confirm\":{\"outputs\":{\"mode\":\"wipe\"}},\"wipe_identity\":{\"outputs\":{}}}}" || { echo "dump failed"; return; }
  local -a ev_=()
  mapfile -t ev_ < <(jq -r 'to_entries[] | "\(.key)=\(.value)"' "$T/dump/w10-$n.env.json")
  # the OUTER environment is what the runner gives the step: the step env:, the job env, and what the bridge wrote to GITHUB_ENV
  # (WEB_HOST_SSH) plus a loaded credential decoy that the env -i must not pass on
  env -i PATH="$d/bin:/usr/bin:/bin" HOME="$d" RUNNER_TEMP="$d/rt" GITHUB_WORKSPACE="$d/ws" GITHUB_OUTPUT="$d/out" GITHUB_STEP_SUMMARY="$d/sum" VOLUME_ID=12345 \
    WEB_HOST_SSH="ssh -F /dev/null -i $d/ci-key -l root" HCLOUD_TOKEN=synthdecoyW10 "${ev_[@]}" \
    bash --noprofile --norc -e "$T/dump/w10-$n.sh" > "$d/stdout" 2>&1 || rc=$?
  printf '%s|%s|%s|%s|%s' "$rc" "$(sed -n 's/^refusal=//p' "$d/out" | tr '\n' ',')" "$(wc -l < "$d/ssh.log" | tr -d ' ')" "$(grep -c 'web_host_ssh_unset' "$d/stdout" || true)" "$(tail -n 1 "$d/ssh.log")"
}
_r="$(envrow_run pristine "$WF" ok)"
IFS='|' read -r _rc _ref _calls _unset _last <<<"$_r"
if [ "$_rc" = 0 ] && [ -z "$_ref" ] && [ "$_calls" -ge 4 ] && [ "$_unset" = 0 ] && grep -qF 'WIPE_PHASE=post_detach WIPE_TYPED_ID=12345 WIPE_LUKS_ID=900000002 WIPE_SERVER_ID=800000001' <<<"$_last"; then
  pass "H-W10-contract: the W10 body, run as the runner runs it (job env + bridge env in, its own exec env -i allow-list between) against the REAL git-data-cutover.sh, passes the access gate (web, jump, git-data-auth) and the host read ($_calls ssh calls) carrying the record's ids, exit 0"
else fail "H-W10-contract: the real W10 body did not get past the access gate" "$_r :: $(tr '\n' '|' < "$T/exec/w10-pristine/stdout" | cut -c1-240)"; fi
mutate b-w10-no-web-host-ssh "$WF" && { _r="$(envrow_run m-b-w10 "$MUT_FILE" ok)"; IFS='|' read -r _rc _ref _calls _unset _last <<<"$_r"
  if [ "$_rc" = 3 ] && [ "$_unset" -ge 1 ] && [ -z "$_ref" ]; then pass "M-b-w10-exec: without WEB_HOST_SSH in the allow-list the REAL access gate refuses web_host_ssh_unset (exit 3) before dialing, and publishes no store verdict"
  else fail "M-b-w10-exec: the executed contract row stayed GREEN against the allow-list without WEB_HOST_SSH" "$_r"; fi; }
_r="$(envrow_run verdict "$WF" verdict)"; IFS='|' read -r _rc _ref _calls _unset _last <<<"$_r"
if [ "$_rc" = 5 ] && [ "$_ref" = "store_not_serving," ]; then pass "H-W10-verdict: a real store verdict from the host (the remote script's exit 41, wipe_mapper_read_failed) is the verb's exit 5 and W10 publishes refusal=store_not_serving"; else fail "H-W10-verdict" "$_r"; fi
_r="$(envrow_run probefail "$WF" probefail)"; IFS='|' read -r _rc _ref _calls _unset _last <<<"$_r"
if [ "$_rc" = 5 ] && [ -z "$_ref" ] && grep -qF 'verdict=probe_failed' "$T/exec/w10-probefail/stdout"; then pass "H-W10-probefail: an answer that does not match the fixed shape is the verb's exit 5 with verdict=probe_failed (an unanswered read) and W10 publishes NO store_not_serving refusal"; else fail "H-W10-probefail" "$_r"; fi
mutate w10-probe-excl "$WF" && { _r="$(envrow_run m-probe "$MUT_FILE" probefail)"; IFS='|' read -r _rc _ref _calls _unset _last <<<"$_r"
  if [ "$_ref" = "store_not_serving," ]; then pass "M-w10-probe-exec: without the probe_failed exclusion the unanswered read is published as store_not_serving (the executed row goes RED)"; else fail "M-w10-probe-exec: the executed probe_failed row stayed GREEN" "$_r"; fi; }
_r="$(envrow_run accessfail "$WF" accessfail)"; IFS='|' read -r _rc _ref _calls _unset _last <<<"$_r"
if [ "$_rc" = 3 ] && [ -z "$_ref" ]; then pass "H-W10-access: a web host that does not answer is the access gate's exit 3 and W10 publishes NO store_not_serving refusal (the store was not read)"; else fail "H-W10-access" "$_r"; fi

# the one retry of the read-only host check (executed against the REAL git-data-cutover.sh; sleep and ssh are PATH shims)
w10_reads() { grep -c 'bash -s' "$T/exec/w10-$1/ssh.log" || true; }
w10_sleeps() { tr '\n' ',' < "$T/exec/w10-$1/sleep.log"; }
w10_retry_probe() { local r rc ref calls un last; r="$(envrow_run "$1" "$2" probefail_once)"; IFS='|' read -r rc ref calls un last <<<"$r"
  [ "$rc" = 0 ] && [ -z "$ref" ] && [ "$(w10_reads "$1")" = 2 ] && [ "$(w10_sleeps "$1")" = "sleep 10," ]; }
w10_retry_access() { local r rc ref calls un last; r="$(envrow_run "$1" "$2" accessfail_once)"; IFS='|' read -r rc ref calls un last <<<"$r"
  [ "$rc" = 0 ] && [ -z "$ref" ] && [ "$(w10_reads "$1")" = 1 ] && [ "$(w10_sleeps "$1")" = "sleep 10," ]; }
w10_retry_twice() { local r rc ref calls un last r2 rc2 ref2; r="$(envrow_run "$1" "$2" probefail)"; IFS='|' read -r rc ref calls un last <<<"$r"
  [ "$rc" = 5 ] && [ -z "$ref" ] && [ "$(w10_reads "$1")" = 2 ] && [ "$(w10_sleeps "$1")" = "sleep 10," ] || return 1
  r2="$(envrow_run "$1-a" "$2" accessfail)"; IFS='|' read -r rc2 ref2 calls un last <<<"$r2"
  [ "$rc2" = 3 ] && [ -z "$ref2" ] && [ "$(w10_reads "$1-a")" = 0 ] && [ "$(w10_sleeps "$1-a")" = "sleep 10," ]; }
w10_noretry_verdict() { local r rc ref calls un last; r="$(envrow_run "$1" "$2" verdict)"; IFS='|' read -r rc ref calls un last <<<"$r"
  [ "$rc" = 5 ] && [ "$ref" = "store_not_serving," ] && [ "$(w10_reads "$1")" = 1 ] && [ -z "$(w10_sleeps "$1")" ]; }
w10_retry_probe retryprobe "$WF" && pass "H-W10-retry-probe: a first host read that did not answer (verdict=probe_failed) is retried once after 10 s; a second attempt that answers ok ends the step green with NO refusal output (2 host reads, one sleep 10)" || fail "H-W10-retry-probe" "$(tr '\n' '|' < "$T/exec/w10-retryprobe/stdout" | cut -c1-200)"
w10_retry_access retryaccess "$WF" && pass "H-W10-retry-access: a first attempt refused by the access gate (exit 3) is retried once after 10 s; a second attempt that passes ends the step green with NO refusal output (1 host read, one sleep 10)" || fail "H-W10-retry-access" "$(tr '\n' '|' < "$T/exec/w10-retryaccess/stdout" | cut -c1-200)"
w10_retry_twice retrytwice "$WF" && pass "H-W10-retry-twice: probe_failed twice is exit 5 and an access refusal twice is exit 3, each after exactly ONE retry (one sleep 10), and neither publishes a store_not_serving refusal (the second attempt decides, and it did not answer)" || fail "H-W10-retry-twice"
w10_noretry_verdict noretry "$WF" && pass "H-W10-noretry-verdict: a real store verdict (exit 5 without probe_failed) is NOT retried (1 host read, no sleep) and publishes refusal=store_not_serving" || fail "H-W10-noretry-verdict"
mutate w10-retry-removed "$WF" && { if w10_retry_probe m-rr "$MUT_FILE" || w10_retry_access m-rra "$MUT_FILE"; then fail "M-w10-retry-removed-exec: an executed retry row stayed GREEN without the retry"; else pass "M-w10-retry-removed-exec: with the retry branch disabled both executed retry rows go RED"; fi; }
mutate w10-retry-verdict "$WF" && { w10_noretry_verdict m-rv "$MUT_FILE" && fail "M-w10-retry-verdict-exec: a store verdict was retried and the executed row stayed GREEN" || pass "M-w10-retry-verdict-exec: retrying a store verdict (exit 5 without probe_failed) turns the executed no-retry row RED"; }
mutate w10-retry-nosleep "$WF" && { w10_retry_probe m-rn "$MUT_FILE" && fail "M-w10-retry-nosleep-exec: the retry without its 10 s pause stayed GREEN" || pass "M-w10-retry-nosleep-exec: dropping the 10 s pause turns the executed retry row RED"; }
mutate w10-retry-first-decides "$WF" && { w10_retry_probe m-rf "$MUT_FILE" && fail "M-w10-retry-first-decides-exec: a first-attempt rc that survives a good second attempt stayed GREEN" || pass "M-w10-retry-first-decides-exec: letting the first attempt keep deciding turns the executed retry row RED"; }
mutate w10-retry-no-access "$WF" && { w10_retry_access m-ra "$MUT_FILE" && fail "M-w10-retry-no-access-exec: an access refusal that is not retried stayed GREEN" || pass "M-w10-retry-no-access-exec: dropping the exit-3 retry turns the executed access row RED"; }

echo "-- J. forbidden-phrase fixtures: every alternative of the widened regex fires; the retained lines do not --"
FIRE=("the volume was erased" "the volume was wiped clean" "the store is secure" "securely deleted" "no copies remain" "no snapshots remain" "no backups remain" "retention closed" "retention ended" "retention_end=2026-11-12" "Art. 17 satisfied" "art 17 compliant" "the volume holds no personal data" "the volume is empty" "store empty" "irrecoverable" "irrecoverably gone" "unrecoverable" "permanently deleted")
CLEAN=("the plaintext volume was deleted at the provider API" "It does not state that the volume was empty or held no personal data" "wipe_check wipe_finish wipe" "an insecure default" "permanent and recoverable are other words" "backup retention is not addressed" "$STANDING_TXT")
_miss=""; for _f in "${FIRE[@]}"; do forbidden "$_f" || _miss+=" [$_f]"; done
_over=""; for _f in "${CLEAN[@]}"; do forbidden "$_f" && _over+=" [$_f]"; done
[ -z "$_miss" ] && [ "${#FIRE[@]}" -ge 19 ] && pass "G8-fixtures-fire: all ${#FIRE[@]} must-fire fixtures (one per alternative, secure and securely and irrecoverably included) are caught by the widened regex" || fail "G8-fixtures-fire: not caught:$_miss"
[ -z "$_over" ] && [ "${#CLEAN[@]}" -ge 7 ] && pass "G8-fixtures-clean: all ${#CLEAN[@]} retained lines (the delete claim, the disclaimer, the standing sentence, ordinary words that merely contain a stem) are NOT flagged" || fail "G8-fixtures-clean: wrongly flagged:$_over"
forbidden "${STANDING_TXT}, permanently" && pass "G8-standing-exact: the whitelist is the exact sentence only: the same sentence with an appended forbidden word is still flagged" || fail "G8-standing-exact: an extended sentence slipped through the whitelist"

echo
echo "=== verdict ==="
printf 'census rows %s | W1+cutover cases %s | notify cases %s | simulator runs %s | mutants executed %s | passes %s | fails %s\n' "$ROWS_N" "$CASES_RUN" "$NOTIFY_CASES_N" "$SIMS_RUN" "$MUTANTS_RUN" "$passes" "$fails"
# Anti-vacuity floors (ADR-193): reported with printf + exit, never through pass()/fail(). Each is a floor on a LIVE count.
floor_bad=0
chk_floor() { # <label> <live> <min>
  if ! [[ "$2" =~ ^[0-9]+$ ]] || [ "$2" -lt "$3" ]; then printf 'FAIL FLOOR: %s is %s, floor %s\n' "$1" "$2" "$3" >&2; floor_bad=1; fi
}
chk_floor "census rows executed" "$ROWS_N" 88
chk_floor "wipe steps checked" "$STEPS_LIVE" 21
chk_floor "post-loader steps checked" "$POST_LIVE" 8
chk_floor "adjacent chain pairs" "$PAIRS_LIVE" 11
chk_floor "verdict words derived" "$WORDS_LIVE" 60
chk_floor "notify words derived" "$NWORDS_LIVE" 10
chk_floor "W1 and cutover cases executed" "$CASES_RUN" 52
chk_floor "notify cases executed" "$NOTIFY_CASES_N" 62
chk_floor "simulator runs" "$SIMS_RUN" 125
MIN_ASSERTIONS=618
if [ "$passes" -lt "$MIN_ASSERTIONS" ]; then
  printf '[FATAL] anti-vacuity floor: only %s assertions passed, floor is %s — rows were deleted, skipped, or the suite exited early\n' "$passes" "$MIN_ASSERTIONS" >&2
  exit 1
fi
if [ "$MUTANTS_RUN" != "$MUTANT_FLOOR" ]; then printf 'FAIL FLOOR: mutants executed %s, expected exactly %s\n' "$MUTANTS_RUN" "$MUTANT_FLOOR" >&2; floor_bad=1; fi
[ "$floor_bad" = 0 ] || { _REACHED_VERDICT=1; exit 1; }
_REACHED_VERDICT=1
if [ "$fails" -gt 0 ]; then
  printf '\nFAIL: %s of %s assertions failed:\n' "$fails" "$((passes + fails))"
  printf '  - %s\n' "${FAILURES[@]}"
  exit 1
fi
printf '\nOK: %s assertions passed\n' "$passes"
exit 0
