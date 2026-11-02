#!/usr/bin/env bash
# launch-check scanner: statuses per fixture, redaction of locations, never-read list.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
check "instrument self-test: pass() and fail() both move their counters" selftest
command -v gitleaks >/dev/null 2>&1 || { echo "FAIL - gitleaks is required for this suite"; exit 1; }

M=$(fx_minimal minimal); scan_to "$M" "$SCRATCH/m.tsv"
check "minimal: scan wrote facts" test -s "$SCRATCH/m.tsv"
check "minimal: CI-01 is a gap" test "$(fact "$SCRATCH/m.tsv" CI-01)" = gap
check "minimal: CI-02 (no tests) is a gap" test "$(fact "$SCRATCH/m.tsv" CI-02)" = gap
check "minimal: SEC-03 (no lockfile) is a gap" test "$(fact "$SCRATCH/m.tsv" SEC-03)" = gap
check "minimal: SEC-01 is ok" test "$(fact "$SCRATCH/m.tsv" SEC-01)" = ok

H=$(fx_healthy healthy); scan_to "$H" "$SCRATCH/h.tsv"
for id in CI-01 CI-02 CI-03 SEC-01 SEC-02 SEC-03 SEC-04 DEBT-02 DEBT-03 DEBT-04 DEBT-05 REL-01 REL-02 REL-03 REL-04; do
  check "healthy: $id is ok" test "$(fact "$SCRATCH/h.tsv" "$id")" = ok
done
check "healthy: CI-04 (no deploy/rollback path) is a gap" test "$(fact "$SCRATCH/h.tsv" CI-04)" = gap
check "healthy: evidence is path:line, never file content" grep -qE '^REL-02	ok	src/server.ts:1$' "$SCRATCH/h.tsv"

P=$(fx_python py); scan_to "$P" "$SCRATCH/p.tsv"
check "python: node-only DEBT-05 is unsupported-stack" test "$(fact "$SCRATCH/p.tsv" DEBT-05)" = unsupported-stack
check "python: scan reports a non-node stack" grep -q 'stack=python' "$SCRATCH/p.tsv.stdout"

S=$(fx_secret secret); scan_to "$S" "$SCRATCH/s.tsv"
check "secret: SEC-01 is a gap" test "$(fact "$SCRATCH/s.tsv" SEC-01)" = gap
check "secret: facts never contain the token" bash -c '! grep -q "ghp_" "$1"' _ "$SCRATCH/s.tsv"
check "secret: neither facts nor stdout contain the location" bash -c '! grep -q "config.js" "$1" "$2"' _ "$SCRATCH/s.tsv" "$SCRATCH/s.tsv.stdout"
scan_to "$S" "$SCRATCH/s2.tsv" --show-secrets
check "secret: --show-secrets prints the location to stdout only" grep -q 'config.js' "$SCRATCH/s2.tsv.stdout"
check "secret: --show-secrets still keeps the location out of the facts file" bash -c '! grep -q "config.js" "$1"' _ "$SCRATCH/s2.tsv"

E=$(fx_envfile envrepo); scan_to "$E" "$SCRATCH/e.tsv"
check "envfile: SEC-02 is a gap" test "$(fact "$SCRATCH/e.tsv" SEC-02)" = gap
check "envfile: the file name is withheld from the facts" bash -c '! grep -q "\.env" "$1"' _ "$SCRATCH/e.tsv"

K=$(fx_markers markers); scan_to "$K" "$SCRATCH/k.tsv"
check "markers: DEBT-01 (60 markers) is a gap" test "$(fact "$SCRATCH/k.tsv" DEBT-01)" = gap
N=$(fx_next_nogate nextgate); scan_to "$N" "$SCRATCH/n.tsv"
check "next without a boundary gate: DEBT-05 is a gap" test "$(fact "$SCRATCH/n.tsv" DEBT-05)" = gap

L=$(fx_symlink sym); scan_to "$L" "$SCRATCH/l.tsv"
check "never-read: symlink is excluded from the readable list" bash -c '! grep -qx "src/link.js" "$1"' _ "$SCRATCH/l.tsv.files"
for bad in key.pem data.sql terraform.tfstate; do
  check "never-read: $bad is excluded from the readable list" bash -c '! grep -qx "$2" "$1"' _ "$SCRATCH/l.tsv.files" "$bad"
done
check "never-read: docs/environment.md (contains 'env', is not .env*) is read" grep -qx 'docs/environment.md' "$SCRATCH/l.tsv.files"
check "never-read: exclusions are counted in the run marker" grep -qE 'excluded=[1-9]' "$SCRATCH/l.tsv.stdout"

mkdir -p "$SCRATCH/nocommit"; gitq "$SCRATCH/nocommit" init -q -b main; put "$SCRATCH/nocommit/a.js" 'x'
scan_to "$SCRATCH/nocommit" "$SCRATCH/nc.tsv"
check "no commits: SEC-01 is not-applicable, not a false clean" test "$(fact "$SCRATCH/nc.tsv" SEC-01)" = na

LAUNCH_CHECK_GITLEAKS=gitleaks-does-not-exist lc scan --target "$M" --facts "$SCRATCH/x.tsv" > "$SCRATCH/x.out" 2>&1; rc=$?
check "missing gitleaks: exit 2 with reason=scanner-missing" bash -c '[ "$1" = 2 ] && grep -q "reason=scanner-missing" "$2"' _ "$rc" "$SCRATCH/x.out"
check "missing gitleaks: nothing was read or written" test ! -e "$SCRATCH/x.tsv"
lc scan --target "$SCRATCH" --facts "$SCRATCH/y.tsv" > "$SCRATCH/y.out" 2>&1; rc=$?
check "target that is not a git repo: exit 2" test "$rc" = 2
# Triage fixes found by the self-test (Phase 3): public certs are not credentials; monorepo Next.js; original-form guards.
C=$(fx_minimal certs); put "$C/certs/cacert.pem" 'public CA'; commit_all "$C"; scan_to "$C" "$SCRATCH/c.tsv"
check "a public CA certificate (cacert.pem) is not a credential-bearing file" test "$(fact "$SCRATCH/c.tsv" SEC-02)" = ok
C2=$(fx_minimal keys); put "$C2/deploy-key.pem" 'x'; commit_all "$C2"; scan_to "$C2" "$SCRATCH/c2.tsv"
check "a key-named .pem is a credential-bearing file" test "$(fact "$SCRATCH/c2.tsv" SEC-02)" = gap
MO=$(fx_minimal mono); put "$MO/apps/web/package.json" '{"dependencies":{"next":"1"}}'; commit_all "$MO"; scan_to "$MO" "$SCRATCH/mo.tsv"
check "monorepo: nested Next.js package without a gate is a DEBT-05 gap" test "$(fact "$SCRATCH/mo.tsv" DEBT-05)" = gap
put "$MO/apps/web/.dependency-cruiser.cjs" 'module.exports = {}'; commit_all "$MO"; scan_to "$MO" "$SCRATCH/mo2.tsv"
check "monorepo: a nested dependency-cruiser config clears DEBT-05" test "$(fact "$SCRATCH/mo2.tsv" DEBT-05)" = ok
OG=$(fx_minimal orig); put "$OG/.claude/hooks/git-commit-secret-scan.sh" '#!/bin/sh'; commit_all "$OG"; scan_to "$OG" "$SCRATCH/og.tsv"
check "original-form guard (the source repo's own hook) counts as present, still advisory/unverified" grep -qE '^BASE-secret-scan	ok	original form present, advisory/unverified' "$SCRATCH/og.tsv"
finish 45
