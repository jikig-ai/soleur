#!/usr/bin/env bash
# Hetzner read-only-token no-fallback scan (#10664, ADR-241 D4 and its 2026-10-23 entry): nothing
# reads the read/write Hetzner credential through a Doppler secrets-get call except the one tracked,
# expiring `op=backup` read. This is a DRIFT RATCHET against re-introducing the removed copy-paste,
# NOT an adversarial defense; the runtime backstop is that the bare name is absent from
# prd_terraform (names-only listing, 2026-10-20), so a stray read returns empty and fails closed.
#
# This file is the SCANNER (live scan only). Its battery is
# tests/scripts/test-hcloud-token-readonly-no-fallback-scan.sh (mutation matrix over synthetic
# fixtures; the live row against the real tree is embedded there, not a separate -live suite).
#
# OWNER AND TRACKERS. The #9755 work owns the allowlisted entry; trackers #9755 and #10664. The
# reviewer-visible anchor is the ADR-241 2026-10-23 entry (it names the entry and its expiry).
#
# PROPERTY. No scanned file reads the bare name through `doppler secrets get`. Per LOGICAL line
# (backslash-newline DELETED as bash does, odd backslash runs only; whole-line comments dropped),
# split into segments on ; | |& && || (a single & is NOT a boundary: 2>&1, &>/dev/null, >&2). In a
# segment find the earliest word `doppler`, the earliest `secrets` after it, the earliest `get`
# after that; the tail is the rest of the segment (the earliest triple has the widest tail). Rule A
# (F-literal): the bare name is in the tail. Rule B (F-sameline): a `$` is in the tail AND the bare
# name is anywhere on the logical line (the `for v in <read-only> <bare>; do ... get "$v"` shape).
# Word-bounded: HCLOUD_TOKEN_READONLY, doppler_ro and dopplerhq do not match. A quoted echo or
# printf recipe is a finding too (rephrase it). Linear time: no regex chain, so no backtracking.
#
# POPULATION. `git ls-files -z --cached --others --exclude-standard`, MINUS a pinned exclusion list:
# test-class paths (a directory segment in {test, tests, __tests__, fixtures} unless a `lib`
# directory segment is also on the path, because tests/scripts/lib/ is sourced by CI at runtime; a
# `.test.` / `.spec.` infix, a `.tftest.hcl` suffix, a `test-*` basename), knowledge-base/, docs (a
# `docs` directory segment), *.md / *.mdx, lockfiles, *.likec4.json and this scanner and its suite.
# .github/workflows/** IS scanned: measured at commit time, removing the old exclusion kept the live
# tree at findings=0 (90 more files), which closes the Tier-B census's narrow-regex gap (its G1g:
# name directly after get plus `-c prd_terraform`). Inverting the selection brings `.claude/hooks`,
# `*.service`, cloud-init*.yml, *.tf, workflows and extensionless files in.
# A path that is not a regular file (directory, submodule, symlink, dangling symlink), is deleted
# from disk, or is over 5 MB is skipped. NUL bytes are stripped (bash drops them) and the rest is
# scanned. FAIL SETUP (rc 2) is only: git failure, root not the top of a work tree, a bad or
# non-absolute root, a bad date, an unreadable regular file.
#
# ALLOWLIST. Keyed on (file, whitespace-normalized logical line text, exact count): exactly one
# entry, the `op=backup` read in scripts/cutover-inngest.sh (#9755, #10664). It must match EXACTLY
# its count (0 = stale and RED, 2 = a re-added copy and RED); a failure prints expected and found.
# The key is not positional: the line can be moved to another arm of the same file.
#
# EXPIRY is WARNING-ONLY. From 21 days before ALLOW_EXPIRY (the day itself and after) one
# ::warning:: is printed per run and the exit code never changes because of the date. Deliberately
# no event or diff decision, unlike the trio census (tests/scripts/test-trio-baseline-census.sh T3):
# a shared 1100-line append-only ADR and a hard stop would block unrelated PRs. Delete the entry
# together with the op=backup read, or renew: edit ALLOW_EXPIRY and append a NEW dated ADR-241 entry
# citing the 2026-10-23 one (an existing entry is never edited). No suite edit is needed to renew.
#
# NAMED BLIND SPOTS (concise; none is claimed covered).
#  - Wrappers, aliases, `${X:-doppler}`, `docker run dopplerhq/cli`: the program word is not `doppler`.
#  - Name before the command (`xargs`, here-string, heredoc) or on another physical line (multi-line
#    argv lists, folded YAML, newline for-loops, a variable assigned on another line).
#  - Quote splicing or ANSI-C quoting of the name; a name from env or argv at runtime; multi-hop
#    indirection; a name assembled from variables; rule B recognises `$` only (no Python/Make interpolation).
#  - Reads that are not `secrets get`: `doppler run -- terraform|hcloud` (env-injected), bare
#    `secrets --json`, `substitute`, `secrets download`, `run -- printenv`, the Doppler REST API,
#    Terraform `data "doppler_secrets"`, and the loader-delivered `$HCLOUD_TOKEN` env
#    (`rw)` in apps/web-platform/infra/git-data-wipe.sh).
#  - Excluded classes production can execute: *.md (agents and runbooks copy-paste; 3 live bare reads
#    exist in knowledge-base runbooks), test-class files CI runs (`test-*`, `*.test.*`, a test dir
#    without a `lib` segment). Files over 5 MB. The allowlist is not positional (above).
#  - It cannot tell that a read/write token was stored UNDER the read-only name; that control is the
#    O5 write-probe of knowledge-base/engineering/operations/runbooks/infra-credential-tiers-8209.md.
#
# SEAMS. HCLOUD_SCAN_ROOT (the tree; default the repo root; refused when GITHUB_ACTIONS is set) and
# HCLOUD_SCAN_TODAY (strict YYYY-MM-DD real date, else FAIL SETUP; default `date -u +%F`; for a valid
# date it can only change the warning). A visible line is printed whenever either is set. No options.
# OUTPUT. FINDING lines, the expiry warning, `live: findings=N allowlisted=M scanned=K`, and (only
# with findings) a final remedy line.
# EXIT. 0 clean; 1 findings; 2 FAIL SETUP or a bad call (usage); 78 xtrace on.
#
# Defensive xtrace refusal. Not required by lint-shell-trace-credential-refusal (no credential is
# bound here); it only keeps a trace of the scan out of a shared transcript.
case "$-" in *x*) printf 'lint-hcloud-token-readonly-no-fallback: refusing to run while xtrace is on\n' >&2; exit 78 ;; esac
set -uo pipefail

HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
[ "$#" -eq 0 ] || { echo "usage: lint-hcloud-token-readonly-no-fallback.sh (no options)" >&2; exit 2; }

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
BARE_RE = re.compile(r"(?<![A-Za-z0-9_])" + NAME_BARE + r"(?![A-Za-z0-9_])")
DOP_RE = re.compile(r"(?<![A-Za-z0-9_.\-])dopp" + r"ler\b")
SECRETS_RE = re.compile(r"\bsecrets\b")
GET_RE = re.compile(r"\bget\b")
BOUNDARY_RE = re.compile(r";|\|&?|&&")
DOP_BYTES = b"dopp" + b"ler"

# The allowlist: (file, whitespace-normalized logical line text, exact count) with an expiry.
# SOLEUR-DEBT: one expiring allowlist entry for the op=backup read (#9755); delete when op=backup is re-plumbed to a Tier-B environment
ALLOW_FILE = "scripts/cutover-inngest.sh"
# split so no other tree scan sees the full read string
ALLOW_TEXT = NAME_BARE + "=$(" + "dopp" + "ler secrets get " + NAME_BARE + " --plain)"
ALLOW_COUNT = 1
ALLOW_EXPIRY = datetime.date(2026, 12, 15)
WARN_DAYS = 21
MAX_BYTES = 5 * 1024 * 1024

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
    if rel in SELF_PATHS or rel.startswith("knowledge-base/") or "docs" in segs[:-1]:
        return False
    if base.endswith((".md", ".mdx", ".markdown", ".lock", ".tftest.hcl", ".likec4.json")) or base in LOCK_NAMES:
        return False
    if base.startswith("test-") or (any(s in TEST_DIRS for s in segs[:-1]) and "lib" not in segs[:-1]):
        return False
    return not re.search(r"\.(?:test|spec)\.[^/]+$", base)


def logical_lines(text):
    """(start_line_no, text) with bash-style continuations (backslash+newline deleted) and whole-line comments dropped."""
    out, parts, start = [], [], 0
    for no, line in enumerate(text.split("\n"), 1):
        if not parts:
            if line.lstrip().startswith("#"):
                continue
            start = no
        if (len(line) - len(line.rstrip("\\"))) % 2 == 1:
            parts.append(line[:-1])
            continue
        parts.append(line)
        out.append((start, "".join(parts)))
        parts = []
    if parts:
        out.append((start, "".join(parts)))
    return out


def classify(lt):
    """(rule A hit, rule B hit) for one logical line: earliest doppler -> secrets -> get per segment."""
    a = b = False
    for seg in BOUNDARY_RE.split(lt):
        d = DOP_RE.search(seg)
        s = SECRETS_RE.search(seg, d.end()) if d else None
        g = GET_RE.search(seg, s.end()) if s else None
        if not g:
            continue
        a = a or bool(BARE_RE.search(seg, g.end()))
        b = b or "$" in seg[g.end():]
    return a, a is False and b and bool(BARE_RE.search(lt))


findings = []
allow_hits = 0
scanned = 0
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
    if not stat.S_ISREG(st.st_mode) or st.st_size > MAX_BYTES:
        continue
    try:
        with open(full, "rb") as fh:
            data = fh.read()
    except OSError as e:
        setup_fail("cannot read %s: %s" % (rel, e))
    scanned += 1
    data = data.replace(b"\0", b"")
    if DOP_BYTES not in data.replace(b"\\\n", b""):
        continue
    for no, lt in logical_lines(data.decode("utf-8", "replace")):
        rule_a, rule_b = classify(lt)
        if not (rule_a or rule_b):
            continue
        nl = " ".join(lt.split())
        if rule_a and rel == ALLOW_FILE and nl == ALLOW_TEXT:
            allow_hits += 1
        elif rule_a:
            findings.append("FINDING F-literal %s:%d: %s" % (rel, no, nl))
        else:
            findings.append("FINDING F-sameline %s:%d: %s" % (rel, no, nl))

if allow_hits != ALLOW_COUNT:
    findings.append("FINDING F-allowlist %s: expected the line %r exactly %d time(s), found %d"
                    % (ALLOW_FILE, ALLOW_TEXT, ALLOW_COUNT, allow_hits))

for f in findings:
    print(f)
days_left = (ALLOW_EXPIRY - TODAY).days
if days_left <= WARN_DAYS:
    when = ("expires %s (%d days left)" % (ALLOW_EXPIRY.isoformat(), days_left) if days_left >= 0
            else "expired %s" % ALLOW_EXPIRY.isoformat())
    print("::warning::hcloud-token-readonly-no-fallback: the allowlist entry for %s %s; delete the entry together "
          "with the op=backup read, or renew per the ADR (renewal = edit ALLOW_EXPIRY and append a NEW dated "
          "ADR-241 entry citing the 2026-10-23 one; an existing entry is never edited) (#9755, #10664)"
          % (ALLOW_FILE, when))
print("live: findings=%d allowlisted=%d scanned=%d" % (len(findings), allow_hits, scanned))
if findings:
    print("see ADR-241 2026-10-23 entry: read HCLOUD_TOKEN_READONLY only, or update ALLOW_TEXT/ALLOW_COUNT "
          "together with the op=backup change")
sys.exit(1 if findings else 0)
PY
