#!/usr/bin/env python3
"""Mutation battery for doppler-download-error-channel.test.sh (#6969 / ADR-147).

Each entry neuters exactly ONE defence in the shipped code. A mutation that does NOT turn the
suite RED means the corresponding assertion cannot fail — i.e. it is testing nothing.

WHY THIS IS COMMITTED RATHER THAN ASSERTED IN PROSE. An uncommitted matrix is a claim nothing
re-checks, and "mutation-verified" in a comment reads as protection while discouraging the next
reader from checking. This PR is the proof: its first, self-authored 23-mutation battery reported
all-detected while the suite could not see that the `test -x` assertions ran BEFORE the heredocs
that create those files — under `set -e`, that aborted every fresh boot at STAGE=assert and
powered the host off, unpaged, with the whole suite green. A review pass then found 21 further
surviving mutants. A battery only ever covers the mutations its author imagined; this file is the
floor, not the ceiling, and the right response to a new defect class is a new entry here.

Runs against a SANDBOX COPY — the tracked worktree is never mutated (a concurrent in-place
mutation is reported by every file-reading review agent as a false "uncommitted drift" finding).

Anchors must match EXACTLY ONCE. A drifted or duplicated anchor is reported loudly rather than
silently scored as a survivor — a mutation that does not land reports a false result in both
directions.

Usage:  python3 apps/web-platform/infra/doppler-download-error-channel.mutation.py
Runtime ~6 min (30 mutants x a full suite run), so it is NOT wired into CI; run it when changing
the suite or any defence it pins.
"""
import os
import shutil
import subprocess
import sys
import tempfile

# Resolve the repo root from this file's location so the harness is portable.
REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
BOOT = "apps/web-platform/infra/soleur-host-bootstrap.sh"
CI = "apps/web-platform/infra/cloud-init.yml"
WF = ".github/workflows/apply-web-platform-infra.yml"
SUITE = "apps/web-platform/infra/doppler-download-error-channel.test.sh"

MUTATIONS = [
    # ── emitter sanitizer ────────────────────────────────────────────────────────────────
    ("preamble strip (emitter)", BOOT, "DETAIL=$(LC_ALL=C sed -e '/^Using /d' -e", "DETAIL=$(LC_ALL=C sed -e"),
    ("ANSI strip", BOOT, ' -e "s/${ESC}\\\\[[0-9;]*[a-zA-Z]//g"', ""),
    ("newline/CR fold", BOOT, "| LC_ALL=C tr '\\011\\012\\015' '   ' \\", "| LC_ALL=C cat \\"),
    ("post-cap ASCII pass", BOOT, "| LC_ALL=C tr -cd '\\040-\\176')", "| LC_ALL=C cat)"),
    ("whitespace trim", BOOT,
     "| LC_ALL=C sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \\", "| LC_ALL=C cat \\"),
    ("emitter cap value", BOOT, "| tail -c 180 \\", "| tail -c 100 \\"),
    # ── credential redaction ─────────────────────────────────────────────────────────────
    ("dp-token redaction (emitter)", BOOT,
     "| LC_ALL=C sed -e 's/dp\\.\\(st\\|pt\\|sa\\|ct\\|scim\\|audit\\)\\.[A-Za-z0-9._-]\\{10,\\}/dp.REDACTED/g' \\",
     "| LC_ALL=C sed -e 's/ZZZNOMATCH/x/' \\"),
    ("dp-token redaction (helper)", BOOT,
     "-e 's/dp\\.\\(st\\|pt\\|sa\\|ct\\|scim\\|audit\\)\\.[A-Za-z0-9._-]\\{10,\\}/dp.REDACTED/g' \"$ERRF\"",
     "-e 's/ZZZNOMATCH/x/' \"$ERRF\""),
    ("redactor OVER-aggression (emitter)", BOOT,
     "| LC_ALL=C sed -e 's/dp\\.\\(st\\|pt\\|sa\\|ct\\|scim\\|audit\\)\\.[A-Za-z0-9._-]\\{10,\\}/dp.REDACTED/g' \\",
     "| LC_ALL=C sed -e '/dp\\./d' \\"),
    ("URI-userinfo redaction", BOOT,
     "-e 's#://[A-Za-z0-9._%+-]\\{1,\\}:[^@/[:space:]]\\{1,\\}@#://REDACTED@#g'",
     "-e 's/ZZZNOMATCH/x/'"),
    # ── helper control flow ──────────────────────────────────────────────────────────────
    (".d summary write", BOOT,
     "printf 'doppler_download rc=%s cond=%s attempts=%s %s'", "true 'doppler_download'"),
    ("timeout bound (-k)", BOOT, 'timeout -k 5 "$TMO" doppler', "doppler"),
    ("cond= classification", BOOT,
     'if [ "$rc" = 124 ] || [ "$rc" = 137 ]; then COND=timeout', "if false; then COND=timeout"),
    ("retry cardinality", BOOT, '[ "$n" -gt "$ATTEMPTS" ] && break', '[ "$n" -gt 2 ] && break'),
    ("non-prefixing retry stage", BOOT,
     "soleur-boot-emit doppler_retry warning", "soleur-boot-emit doppler_download warning"),
    ("empty-payload guard", BOOT,
     'if [ "$rc" = 0 ] && [ ! -s "$OUT" ]; then', "if false; then"),
    ("stdout injection into $OUT", BOOT,
     '  [ "$rc" = 0 ] && exit 0',
     '  printf \'SOLEUR_INJECTED=pwn\\n\' >> "$OUT"\n  [ "$rc" = 0 ] && exit 0'),
    ("EXIT-trap cleanup", BOOT, "trap 'rm -f \"$ERRF\"' EXIT INT TERM HUP", "true"),
    # ── bake-time wiring ─────────────────────────────────────────────────────────────────
    ("host_name sentinel splice", BOOT,
     'sed -i "s|@@SOLEUR_HOST_NAME@@|${SOLEUR_HOST_NAME:-}|" /usr/local/bin/soleur-boot-emit',
     "true"),
    ("DSN splice typo (channel dark)", BOOT,
     "@@SOLEUR_SENTRY_DSN@@|${SOLEUR_SENTRY_DSN:-}", "@@SOLEUR_SENTRY_DS@@|${SOLEUR_SENTRY_DSN:-}"),
    ("helper test -x assertion", BOOT,
     "FAILED_FILE=soleur-doppler-download\ntest -x /usr/local/bin/soleur-doppler-download", "true"),
    ("assertion ORDER (the P0)", BOOT,
     "STAGE=assert_baked\nFAILED_FILE=soleur-boot-emit\ntest -x /usr/local/bin/soleur-boot-emit",
     "STAGE=assert_baked"),
    # ── cloud-init call site ─────────────────────────────────────────────────────────────
    ("call-site re-raise", CI, '\n    [ "$rc" = 0 ] || exit "$rc"', ""),
    ("rc-capture form", CI,
     'soleur-doppler-download "$TMPENV" && rc=0 || rc=$?',
     'if ! soleur-doppler-download "$TMPENV"; then rc=$?; fi'),
    ("docker stderr NOT captured", CI,
     '      -p 0.0.0.0:3000:3000 \\\n      "$(cat /run/soleur-image-ref',
     '      -p 0.0.0.0:3000:3000 \\\n      2>/run/soleur-stage-detail.d/docker_run \\\n      "$(cat /run/soleur-image-ref'),
    # ── birth-path gate ──────────────────────────────────────────────────────────────────
    ("gate host-scoping", WF,
     '($hn == null or $hn == "" or $hn == $eh)', '($hn == null or $hn != null)'),
    ("::error:: detail interpolation", WF,
     "booted DARK at stage ${FATAL_STAGE:-${LAST_STAGE:-unknown}}: ${FATAL_DETAIL",
     "booted DARK at stage ${FATAL_STAGE:-${LAST_STAGE:-unknown}}: ${NOTHING"),
    ("QUERY message literals", WF,
     'message:"soleur-cloud-init boot stage"', 'message:"soleur-cloud-init boot stages"'),
    ("green-run retry selector", WF,
     '| select(hostok($eh))\n                    | select([ (.tags // [])[]? | select(.key=="stage") | .value ][0] == "doppler_retry") ] | length > 0',
     '| select(hostok($eh))\n                    | select(false) ] | length > 0'),
    ("RETRY_DETAIL capture", WF, 'RETRIED a boot stage (stage=doppler_retry observed). The host is healthy; the underlying fault is not. Detail: ${RETRY_DETAIL:-<none captured>}', 'RETRIED a boot stage (stage=doppler_retry observed). The host is healthy; the underlying fault is not. Detail: ${LAST_DETAIL:-<none>}'),
]


def run(sb):
    p = subprocess.run(["bash", os.path.join(sb, SUITE)], capture_output=True, text=True)
    both = (p.stdout or "") + (p.stderr or "")
    return [l for l in both.splitlines() if l.startswith("[FAIL]")]


def main():
    sb = tempfile.mkdtemp(prefix="mutbat2.")
    for rel in (BOOT, CI, WF, SUITE):
        dst = os.path.join(sb, rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copy(os.path.join(REPO, rel), dst)
    # the suite reads sibling infra files via $DIR
    for extra in ("sentry/issue-alerts.tf",):
        src = os.path.join(REPO, "apps/web-platform/infra", extra)
        dst = os.path.join(sb, "apps/web-platform/infra", extra)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copy(src, dst)

    base = run(sb)
    if base:
        print("CONTROL NOT GREEN — every result below would be noise:")
        for f in base:
            print("   ", f)
        sys.exit(1)
    print(f"control: GREEN  ({len(MUTATIONS)} mutants)\n")

    survived = []
    for name, rel, old, new in MUTATIONS:
        src, dst = os.path.join(REPO, rel), os.path.join(sb, rel)
        shutil.copy(src, dst)
        s = open(dst).read()
        n = s.count(old)
        if n != 1:
            print(f"{name:34s} ANCHOR n={n} (need exactly 1)  <-- fix the harness")
            survived.append(f"{name} (anchor n={n})")
            shutil.copy(src, dst)
            continue
        open(dst, "w").write(s.replace(old, new, 1))
        fails = run(sb)
        shutil.copy(src, dst)
        if fails:
            print(f"{name:34s} RED ({len(fails):2d})  {fails[0][:78]}")
        else:
            print(f"{name:34s} SURVIVED  <-- assertion cannot fail")
            survived.append(name)

    print()
    if survived:
        print("SURVIVING / UNVERIFIED:")
        for s_ in survived:
            print("   ", s_)
        sys.exit(1)
    print(f"all {len(MUTATIONS)} mutations detected")
    shutil.rmtree(sb)


main()
