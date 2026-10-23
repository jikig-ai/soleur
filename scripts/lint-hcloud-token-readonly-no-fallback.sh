#!/usr/bin/env bash
# Guard 1 (#10664, ADR-241 D4): nothing reads the read/write Hetzner credential through a
# Doppler secrets-get call except the one tracked, expiring `op=backup` read.
#
# This file is the SCANNER (live scan only). Its battery is
# tests/scripts/test-hcloud-token-readonly-no-fallback-scan.sh (mutation matrix over synthetic
# fixtures; the live row against the real tree is embedded there, not a separate -live suite, R8).
#
# xtrace refusal: this script's source names the Doppler read and the credential it forbids, so it
# carries the repo's xtrace refusal ahead of any command (lint-shell-trace-credential-refusal.py).
case "$-" in *x*) printf 'lint-hcloud-token-readonly-no-fallback: refusing to run while xtrace is on\n' >&2; exit 78 ;; esac
#
# OWNER AND TRACKERS. The #9755 work owns the allowlisted entry; trackers #9755 and #10664. The
# reviewer-visible anchor is the ADR-241 2026-10-23 entry (it names the entry and its expiry).
#
# PROPERTY. No file in the scanned population reads the read/write Hetzner credential through
# `doppler secrets get`. Over the LOGICAL line (backslash continuations joined, whole-line comments
# dropped) two word-bounded regexes decide. Rule A (F-literal): within one shell segment (no | ; &),
# the doppler ... secrets ... get prefix is followed by the bare name. Rule B (F-sameline): the same
# prefix is followed by a non-literal operand ($) AND the bare name is anywhere on the line (the
# `for v in <read-only> <bare>; do ... get "$v"` shape). The bare name is a prefix of the read-only
# one, so the match is word-bounded. A quoted echo or printf recipe is a finding too (rephrase it).
#
# POPULATION. `git ls-files -z --cached --others --exclude-standard`: tracked and untracked-but-not-
# ignored files, MINUS a pinned exclusion list: tests (a directory segment in {test, tests,
# __tests__, fixtures}, a `.test.` / `.spec.` infix, a `.tftest.hcl` suffix, a `test-*` basename),
# knowledge-base/, docs (a `docs` directory segment), *.md / *.mdx, lockfiles, *.likec4.json,
# .github/workflows/** (the Tier-B census owns the workflows) and this scanner and its suite.
# Inverting the selection is what brings `.claude/hooks`, `*.service`, cloud-init*.yml and *.tf in.
# A path that is not a regular file (directory, submodule, symlink, dangling symlink) or is deleted
# from the disk is skipped. FAIL SETUP (rc 2) is only: git failure, root not the top of a work tree,
# a bad or non-absolute root, a bad date, an unreadable regular file.
#
# ALLOWLIST. Keyed on (file, whitespace-normalized logical line text, exact count): exactly one
# entry, the `op=backup` read in scripts/cutover-inngest.sh (#9755, #10664). It must match EXACTLY
# its count (0 = stale and RED, 2 = a re-added copy and RED); a failure prints expected and found.
#
# EXPIRY is WARNING-ONLY. From 21 days before ALLOW_EXPIRY (the day itself and after) one
# ::warning:: is printed per run and the exit code never changes because of the date. Deliberately
# no event or diff decision, unlike the trio census (tests/scripts/test-trio-baseline-census.sh T3):
# a shared 1100-line append-only ADR and a hard stop would block unrelated PRs. Delete the entry
# together with the op=backup read, or renew: edit ALLOW_EXPIRY and append a NEW dated ADR-241 entry
# citing the 2026-10-23 one (an existing entry is never edited).
#
# NAMED BLIND SPOTS. This is a text guard; it does not see: a name that arrives from env or argv at
# runtime; a variable assigned the bare name on another line; multi-hop indirection; wrapper
# functions taking the name as an argument (the runtime backstop is real: the bare name is absent
# from prd_terraform, so such a read returns empty and fails closed); a name assembled from separate
# variables; `doppler run -- printenv`, `--only-secrets` and `secrets download`; a call whose program
# name is not the literal word `doppler`; reads that are not secrets-get calls (the loader-delivered
# `rw) _var=HCLOUD_TOKEN` in apps/web-platform/infra/git-data-wipe.sh). It cannot tell that a
# read/write token was stored UNDER the read-only name; that control is the O5 write-probe of
# knowledge-base/engineering/operations/runbooks/infra-credential-tiers-8209.md. A live run at
# commit time found no hit from F-sameline on an unrelated site.
#
# SEAMS. HCLOUD_SCAN_ROOT (the tree; default the repo root; refused when GITHUB_ACTIONS is set) and
# HCLOUD_SCAN_TODAY (strict YYYY-MM-DD real date, else FAIL SETUP; default `date -u +%F`; it can only
# change the warning). A visible line is printed whenever either is set. No options.
# OUTPUT. FINDING lines, the expiry warning, then `live: findings=N allowlisted=M`.
# EXIT. 0 clean; 1 findings; 2 FAIL SETUP; 64 bad call; 78 xtrace on.
set -uo pipefail

HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
[ "$#" -eq 0 ] || { echo "usage: lint-hcloud-token-readonly-no-fallback.sh (no options)" >&2; exit 64; }

if [ -n "${GITHUB_ACTIONS-}" ] && [ -n "${HCLOUD_SCAN_ROOT+x}" ]; then
  echo "FAIL SETUP: GITHUB_ACTIONS is set and HCLOUD_SCAN_ROOT is inherited; the root seam cannot be set from a workflow environment" >&2
  exit 2
fi

root="${HCLOUD_SCAN_ROOT-$(cd -P "$HERE/.." && pwd -P)}"
if [ -n "${HCLOUD_SCAN_ROOT+x}" ]; then
  printf 'scan: HCLOUD_SCAN_ROOT override active: %s\n' "$HCLOUD_SCAN_ROOT"
fi
case "$root" in
  /?*) : ;;
  *) echo "FAIL SETUP: scan root is empty or not absolute: $root" >&2; exit 2 ;;
esac
[ -d "$root" ] || { echo "FAIL SETUP: scan root is not a directory: $root" >&2; exit 2; }

if [ -n "${HCLOUD_SCAN_TODAY+x}" ]; then
  today="$HCLOUD_SCAN_TODAY"
  printf 'scan: HCLOUD_SCAN_TODAY override active: %s\n' "$HCLOUD_SCAN_TODAY"
else
  today="$(date -u +%F)"
fi

exec python3 -I - "$root" "$today" <<'PY'
import datetime, os, re, stat, subprocess, sys  # noqa: E401

root, today_s = sys.argv[1:3]

NAME_BARE = "HCLOUD_" + "TOKEN"
BARE = r"(?<![A-Za-z0-9_])" + NAME_BARE + r"(?![A-Za-z0-9_])"
BARE_RE = re.compile(BARE)
SEG = r"[^|;&\n]*"
PREFIX = r"(?<![A-Za-z0-9_.\-])dopp" + r"ler\b" + SEG + r"\bsecrets\b" + SEG + r"\bget\b" + SEG
RULE_A = re.compile(PREFIX + BARE)
RULE_B = re.compile(PREFIX + r"\$")

# The allowlist: (file, whitespace-normalized logical line text, exact count) with an expiry.
# SOLEUR-DEBT: one expiring allowlist entry for the op=backup read (#9755); delete when op=backup is re-plumbed to a Tier-B environment
ALLOW_FILE = "scripts/cutover-inngest.sh"
# split so no other tree scan sees the full read string
ALLOW_TEXT = NAME_BARE + "=$(" + "dopp" + "ler secrets get " + NAME_BARE + " --plain)"
ALLOW_COUNT = 1
ALLOW_EXPIRY = datetime.date(2026, 12, 15)
WARN_DAYS = 21

SELF_PATHS = {
    "scripts/lint-hcloud-token-readonly-no-fallback.sh",
    "tests/scripts/test-hcloud-token-readonly-no-fallback-scan.sh",
}
TEST_DIRS = {"test", "tests", "__tests__", "fixtures"}
LOCK_NAMES = {"package-lock.json", "pnpm-lock.yaml", "yarn.lock", "bun.lock", "bun.lockb", "uv.lock",
              "Cargo.lock", "Gemfile.lock", "poetry.lock", ".terraform.lock.hcl", "composer.lock"}


def setup_fail(msg):
    sys.stderr.write("FAIL SETUP: %s\n" % msg)
    sys.exit(2)


if not re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}", today_s):
    setup_fail("HCLOUD_SCAN_TODAY must be YYYY-MM-DD, got %r" % today_s)
try:
    TODAY = datetime.date.fromisoformat(today_s)
except ValueError:
    setup_fail("HCLOUD_SCAN_TODAY is not a real calendar date: %r" % today_s)

GIT_DROP = ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_COMMON_DIR", "GIT_OBJECT_DIRECTORY",
            "GIT_ALTERNATE_OBJECT_DIRECTORIES", "GIT_NAMESPACE", "GIT_CONFIG_COUNT", "GIT_CONFIG_PARAMETERS")
genv = {k: v for k, v in os.environ.items() if k not in GIT_DROP}


def git(*args):
    try:
        return subprocess.run(["git", "-C", root] + list(args), env=genv, capture_output=True)
    except OSError as e:
        setup_fail("cannot run git: %s" % e)


top = git("rev-parse", "--show-toplevel")
if top.returncode != 0:
    setup_fail("root %s is not a git work tree: %s" % (root, top.stderr.decode("utf-8", "replace").strip()[:200]))
if os.path.realpath(top.stdout.decode("utf-8", "replace").strip()) != os.path.realpath(root):
    setup_fail("root %s is not the top of a git work tree" % root)
ls = git("ls-files", "-z", "--cached", "--others", "--exclude-standard")
if ls.returncode != 0:
    setup_fail("git ls-files failed: %s" % ls.stderr.decode("utf-8", "replace").strip()[:200])
paths = sorted(set(os.fsdecode(p) for p in ls.stdout.split(b"\0") if p))


def scan(rel):
    segs = rel.split("/")
    base = segs[-1]
    if rel in SELF_PATHS or rel.startswith(("knowledge-base/", ".github/workflows/")) or "docs" in segs[:-1]:
        return False
    if base.endswith((".md", ".mdx", ".markdown", ".lock", ".tftest.hcl", ".likec4.json")) or base in LOCK_NAMES:
        return False
    if base.startswith("test-") or any(s in TEST_DIRS for s in segs[:-1]):
        return False
    return not re.search(r"\.(?:test|spec)\.[^/]+$", base)


def logical_lines(text):
    """(start_line_no, text) with backslash continuations joined and whole-line comments dropped."""
    out, cur, start = [], "", 0
    for no, line in enumerate(text.split("\n"), 1):
        if not cur:
            if line.lstrip().startswith("#"):
                continue
            start = no
        m = re.search(r"(\\+)$", line)
        if m and len(m.group(1)) % 2 == 1:
            cur += line[:-1] + " "
            continue
        out.append((start, cur + line))
        cur = ""
    if cur:
        out.append((start, cur))
    return out


findings = []
allow_hits = 0
for rel in paths:
    if not scan(rel):
        continue
    full = os.path.join(root, rel)
    try:
        st = os.lstat(full)
    except (FileNotFoundError, NotADirectoryError):
        continue
    except OSError as e:
        setup_fail("cannot stat %s: %s" % (rel, e))
    if not stat.S_ISREG(st.st_mode):
        continue
    try:
        with open(full, "rb") as fh:
            data = fh.read()
    except OSError as e:
        setup_fail("cannot read %s: %s" % (rel, e))
    if b"\0" in data[:8192] or b"dopp" + b"ler" not in data:
        continue
    for no, lt in logical_lines(data.decode("utf-8", "replace")):
        nl = " ".join(lt.split())
        if RULE_A.search(lt):
            if rel == ALLOW_FILE and nl == ALLOW_TEXT:
                allow_hits += 1
            else:
                findings.append("FINDING F-literal %s:%d: %s" % (rel, no, nl))
        elif RULE_B.search(lt) and BARE_RE.search(lt):
            findings.append("FINDING F-sameline %s:%d: %s" % (rel, no, nl))

if allow_hits != ALLOW_COUNT:
    findings.append("FINDING F-allowlist %s: expected the line %r exactly %d time(s), found %d"
                    % (ALLOW_FILE, ALLOW_TEXT, ALLOW_COUNT, allow_hits))

days_left = (ALLOW_EXPIRY - TODAY).days
if days_left <= WARN_DAYS:
    when = ("expires %s (%d days left)" % (ALLOW_EXPIRY.isoformat(), days_left) if days_left >= 0
            else "expired %s" % ALLOW_EXPIRY.isoformat())
    print("::warning::hcloud-token-readonly-no-fallback: the allowlist entry for %s %s; delete the entry together "
          "with the op=backup read, or renew per the ADR (renewal = edit ALLOW_EXPIRY and append a NEW dated "
          "ADR-241 entry citing the 2026-10-23 one; an existing entry is never edited) (#9755, #10664)"
          % (ALLOW_FILE, when))
for f in findings:
    print(f)
print("live: findings=%d allowlisted=%d" % (len(findings), allow_hits))
sys.exit(1 if findings else 0)
PY
