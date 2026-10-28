#!/usr/bin/env bash
# Hetzner read-only-token no-fallback scan (#10664, ADR-241 D4 and its 2026-10-23 entry; the
# allowlist was retired by #9755 on 2026-10-28): nothing anywhere reads the read/write Hetzner
# credential through a Doppler secrets-get call. This is a DRIFT RATCHET against re-introducing
# the removed copy-paste, NOT an adversarial defense; the runtime backstop is that the bare name
# is absent from prd_terraform (names-only listing, 2026-10-20; the bare name lives in
# soleur-infra-privileged/prd), so a stray prd_terraform read returns empty and fails closed.
#
# This file is the SCANNER (live scan only). Its battery is
# tests/scripts/test-hcloud-token-readonly-no-fallback-scan.sh (mutation matrix over synthetic
# fixtures; the live row against the real tree is embedded there, not a separate -live suite).
#
# HISTORY. Until #9755 this ratchet carried ONE expiring allowlist entry — the `op=backup`
# `doppler secrets get` of the bare name in scripts/cutover-inngest.sh — because op=backup was
# the one remaining legitimate reader. #9755 re-plumbed that op to the Tier-B loader
# (ADR-241 O10 mechanism, the `inngest-cutover` environment), so the allowance is deleted with
# the read: the missed-deadline retrospective is the ADR-241 2026-10-28 entry. There is no
# allowlist left to renew; a reintroduced read is a plain finding.
#
# PROPERTY. No scanned file reads the bare name through `doppler secrets get`. Per LOGICAL line
# (backslash-newline DELETED as bash does, odd backslash runs only; whole-line comments dropped; a
# physical line holding a comment start `(^|[ \t])#` ends its logical line there, because bash does not
# continue a comment and the deletion join would glue `#a` onto the next line's `doppler`), split into
# segments on ; | |& && || (a single & is NOT a boundary: 2>&1, &>/dev/null, >&2; so a lone `&` stays
# inside a segment and `doppler secrets get X_READONLY & echo HCLOUD_TOKEN` is an ACCEPTED false
# positive). The continuation and comment handling ignores quoting (a `#` inside a string counts). In a
# segment find the earliest word `doppler`, the earliest `secrets` after it, the earliest `get`
# after that; the tail is the rest of the segment (the earliest triple has the widest tail). Rule A
# (F-literal): the bare name is in the tail. Rule B (F-sameline): a `$` is in the tail AND the bare
# name is anywhere on the logical line (the `for v in <read-only> <bare>; do ... get "$v"` shape).
# Word-bounded: HCLOUD_TOKEN_READONLY, doppler_ro and dopplerhq do not match. A quoted echo or
# printf recipe is a finding too (rephrase it). Linear time: no regex chain, so no backtracking.
#
# POPULATION. `git ls-files -z --cached --others --exclude-standard`, MINUS a pinned exclusion list:
# test-class paths (a directory segment in {test, tests, __tests__, fixtures} unless a `lib`
# path is under tests/scripts/lib/, because CI sources it at runtime; a
# `.test.` / `.spec.` infix, a `.tftest.hcl` suffix, a `test-*` basename), knowledge-base/, docs (a
# `docs` directory segment), *.md / *.mdx, lockfiles, *.likec4.json and this scanner and its suite.
# .github/workflows/** IS scanned: measured at commit time, removing the old exclusion kept the live
# tree at findings=0 (90 more files), which closes the Tier-B census's narrow-regex gap (its G1g:
# name directly after get plus `-c prd_terraform`). Inverting the selection brings `.claude/hooks`,
# `*.service`, cloud-init*.yml, *.tf, workflows and extensionless files in.
# A path that is not a regular file (directory, submodule, symlink, dangling symlink), is deleted
# from disk, or is over 5 MB is skipped. NUL bytes are stripped (bash drops them) and the rest is
# scanned. Files skipped for size are counted: `::warning::skipped N file(s) over 5 MB (not scanned)`.
# FAIL SETUP (rc 2) is: git failure, root not the top of a work tree, a bad or non-absolute root,
# the GITHUB_ACTIONS+HCLOUD_SCAN_ROOT refusal, an unreadable regular file, a non-ENOENT stat error.
#
# NAMED BLIND SPOTS (concise; none is claimed covered).
#  - Wrappers, aliases, `${X:-doppler}`, `docker run dopplerhq/cli`: the program word is not `doppler`.
#  - Name before the command (`xargs`, here-string, heredoc) or on another physical line (multi-line
#    argv lists, folded YAML, newline for-loops, a variable assigned on another line).
#  - Quote splicing or ANSI-C quoting of the name; a name from env or argv at runtime; multi-hop
#    indirection; a name assembled from variables; rule B recognises `$` only (no Python or f-string interpolation).
#  - Reads that are not `secrets get`: `doppler run -- terraform|hcloud` (env-injected), bare
#    `secrets --json`, `substitute`, `secrets download`, `run -- printenv`, the Doppler REST API,
#    Terraform `data "doppler_secrets"`, and the loader-delivered `$HCLOUD_TOKEN` env
#    (`<<<"${HCLOUD_TOKEN:-}"` in .github/workflows/git-data-cutover.yml; git-data-wipe.sh `rw)`
#    reads a stdin line).
#  - Excluded classes production can execute: *.md (agents and runbooks copy-paste; 4 live bare reads
#    exist in knowledge-base runbooks: grok-build-hetzner-dogfood.md:20, registry-luks-recut-6929.md:346
#    and :408, the infra-credential-tiers-8209.md O2 row), test-class files CI runs (`test-*`, `*.test.*`, a test dir
#    outside tests/scripts/lib/). Files over 5 MB.
#  - It cannot tell that a read/write token was stored UNDER the read-only name; that control is the
#    O5 write-probe of knowledge-base/engineering/operations/runbooks/infra-credential-tiers-8209.md.
#
# SEAM. HCLOUD_SCAN_ROOT (the tree; default the repo root; refused when GITHUB_ACTIONS is set). A
# visible line is printed when it is set. No options, and no clock: the scanner has no allowlist
# and nothing that expires, so the HCLOUD_SCAN_TODAY seam went out with the expiry machinery.
# OUTPUT. FINDING lines, `live: findings=N scanned=K`, and (only with findings) a final remedy
# line naming the read-only name and the Tier-B loader path.
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

exec python3 -I - "$root" <<'PY'
import os, re, stat, subprocess, sys  # noqa: E401

root = sys.argv[1]

NAME_BARE = "HCLOUD_" + "TOKEN"
BARE_RE = re.compile(r"(?<![A-Za-z0-9_])" + NAME_BARE + r"(?![A-Za-z0-9_])")
DOP_RE = re.compile(r"(?<![A-Za-z0-9_.\-])dopp" + r"ler\b")
COMMENT_RE = re.compile(r"(^|[ \t])#")
SECRETS_RE = re.compile(r"\bsecrets\b")
GET_RE = re.compile(r"\bget\b")
BOUNDARY_RE = re.compile(r";|\|&?|&&")
DOP_STR = "dopp" + "ler"
DOP_BYTES = DOP_STR.encode()

MAX_BYTES = 5 * 1024 * 1024

SELF_PATHS = {
    "scripts/lint-hcloud-token-readonly-no-fallback.sh",
    "tests/scripts/test-hcloud-token-readonly-no-fallback-scan.sh",
}
TEST_DIRS = {"test", "tests", "__tests__", "fixtures"}
LIB_PREFIX = "tests/scripts/lib/"
LOCK_NAMES = {"package-lock.json", "pnpm-lock.yaml", "yarn.lock", "bun.lock", "bun.lockb", "uv.lock",
              "Cargo.lock", "Gemfile.lock", "poetry.lock", ".terraform.lock.hcl", "composer.lock"}


def setup_fail(msg):
    sys.stderr.write("FAIL SETUP: %s\n" % msg)
    sys.exit(2)


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
    if base.startswith("test-") or (any(s in TEST_DIRS for s in segs[:-1]) and not rel.startswith(LIB_PREFIX)):
        return False
    return not re.search(r"\.(?:test|spec)\.[^/]+$", base)


def logical_lines(text):
    """(start_line_no, text): bash-style continuations (backslash+newline deleted, except after a comment start,
    where the logical line ends: bash does not continue a comment; quoting is ignored) and whole-line comments dropped."""
    out, parts, start = [], [], 0
    for no, line in enumerate(text.split("\n"), 1):
        if not parts:
            if line.lstrip().startswith("#"):
                continue
            start = no
        if (len(line) - len(line.rstrip("\\"))) % 2 == 1 and not COMMENT_RE.search(line):
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
scanned = skipped_big = 0
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
    if st.st_size > MAX_BYTES:
        skipped_big += 1
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
        if DOP_STR not in lt:
            continue
        rule_a, rule_b = classify(lt)
        if not (rule_a or rule_b):
            continue
        nl = " ".join(lt.split())
        if rule_a:
            findings.append("FINDING F-literal %s:%d: %s" % (rel, no, nl))
        else:
            findings.append("FINDING F-sameline %s:%d: %s" % (rel, no, nl))

for f in findings:
    print(f)
if skipped_big:
    print("::warning::skipped %d file(s) over 5 MB (not scanned)" % skipped_big)
print("live: findings=%d scanned=%d" % (len(findings), scanned))
if findings:
    print("see ADR-241: the read/write Hetzner name is Tier-B only — read the read-only name "
          "(HCLOUD_TOKEN_READONLY), or take the loader-exported env through infra-credentials "
          "(the ADR-241 O10 mechanism); there is no allowlist")
sys.exit(1 if findings else 0)
PY
