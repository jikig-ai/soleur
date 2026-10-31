#!/usr/bin/env bash
# Mutation battery for Guards 1 (emit allowlist) and 4 (positive control and canary) of the production-HOME census
# (Ref #10455). The REVIEWER runs the full battery, not the author (learning 2026-07-19: a self-graded battery went
# vacuous twice): HOME_CENSUS_MUTATIONS=1 bash apps/web-platform/test/home-census-mutations.test.sh
#
# Every mutation is applied to a SANDBOX COPY of apps/web-platform (never the working tree), is scoped to exact
# content anchors that must each occur exactly once, must LAND (the file changes), and is judged by vitest alone:
# rc 1 = RED (caught), rc 0 = SURVIVED (a defect), anything else = UNRESOLVED (could not measure, never a pass).
#
# Always-on (no env var): the baseline is green, the battery is not vacuous, every edit lands against the current
# source, and the instrument control holds (the pristine copy exits 0; a deliberately broken copy exits 1).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="$(cd "$HERE/.." && pwd)"
REPO_ROOT="$(cd "$APP/../.." && pwd)"
SBR="$(mktemp -d -t home-census-mut.XXXXXXXX)"   # sandbox root: the vitest global setup imports ../../../plugins/soleur/test/lib
SB="$SBR/apps/web-platform"
trap 'rm -rf "$SBR"' EXIT
mkdir -p "$SB"
FULL="${HOME_CENSUS_MUTATIONS:-0}"
TESTS="test/server/home-census.test.ts test/server/internal/home-census-route.test.ts"

command -v python3 >/dev/null || { printf 'home-census-mutations: python3 required\n'; exit 1; }
[[ -d "$APP/node_modules" ]] || { printf 'home-census-mutations: UNRESOLVED (no node_modules; run npm ci in apps/web-platform)\n'; exit 2; }

# ---- sandbox copy ------------------------------------------------------------------------------------------------
tar -C "$APP" --exclude=node_modules --exclude=.next --exclude=dist -cf - . | tar -C "$SB" -xf -
ln -s "$APP/node_modules" "$SB/node_modules"
ln -s "$REPO_ROOT/plugins" "$SBR/plugins"
PRISTINE="$SBR/home-census.pristine.ts"
cp "$SB/server/home-census.ts" "$PRISTINE"

# ---- the mutation table ------------------------------------------------------------------------------------------
cat >"$SBR/mut.py" <<'PY'
import sys
M = [
 # id, guard, [(old, new), ...]
 ("G1-1 path-bearing string field", 1, [('    outer_wrap_cohorts: "unmeasured" as const,\n', '    outer_wrap_cohorts: "unmeasured" as const,\n    leak: "/home/soleur/.claude/projects/x",\n')]),
 ("G1-2 unbucketed integer count", 1, [('      n_entries: bucketCount(scan.classes[c].entries),', '      n_entries: scan.classes[c].entries as unknown as string,')]),
 ("G1-3 second class entry with an extra key", 1, [('      class_result: results[c],\n    })),', '      class_result: results[c],\n      extra: "x",\n    })),')]),
 ("G1-4 error response built from err.message", 1, [('  } catch {\n    // Never rethrow, never print:', '  } catch (e) {\n    return new Response(JSON.stringify({ ...buildFailure("internal"), detail: String((e as Error).message) }), { status: 500 });\n    // Never rethrow, never print:')]),
 ("G1-5 pino base fields restored (pid, hostname)", 1, [('base: undefined, timestamp: false', 'base: { pid: process.pid, hostname: "h" }, timestamp: false')]),
 ("G1-6 Sentry event processor dropped", 1, [('        scope.addEventProcessor((event) => stripToAllowlist(event as Sentry.ErrorEvent, { message, level, tags, extra }));\n', '')]),
 ("G1-7 interpretation dropped from the result", 1, [('    interpretation: INTERPRETATION,\n    claude_config_dir_set', '    claude_config_dir_set')]),
 ("G1-8 pino line at info (Vector drops it)", 1, [('pino({ level: "warn",', 'pino({ level: "info",'), ('.warn({ outcome, ...result }, MESSAGE);', '.info({ outcome, ...result }, MESSAGE);')]),
 ("G1-9 census key named message (Vector drop list)", 1, [('.warn({ outcome, ...result }, MESSAGE);', '.warn({ outcome, message: "x", ...result }, MESSAGE);')]),
 ("G1-10 module allowlist bypassed AND a path-bearing field added (the independent test allowlist alone must catch it)", 1, [('export function assertAllowlisted(body: CensusResult | ReturnType<typeof buildFailure>): void {\n', 'export function assertAllowlisted(body: CensusResult | ReturnType<typeof buildFailure>): void {\n  if (body) return;\n'), ('    outer_wrap_cohorts: "unmeasured" as const,\n', '    outer_wrap_cohorts: "unmeasured" as const,\n    leak: "/home/soleur/.claude/projects/x",\n')]),
 ("G4-1 control comparison always true", 4, [('function controlMatches(scan: InternalScan): boolean {\n', 'function controlMatches(scan: InternalScan): boolean {\n  if (scan) return true;\n')]),
 ("G4-2 control call removed", 4, [('if (!controlMatches(controlScan.scan) || !canary) {', 'if (false) {')]),
 ("G4-3 early exit after the first class", 4, [('    for (const step of STEPS) {\n      for (const root of opts.roots) {', '    for (const step of STEPS.slice(0, 1)) {\n      for (const root of opts.roots) {')]),
 ("G4-4 canary hard-coded true", 4, [('      return (await d.read()) !== null;', '      return true;')]),
 ("G4-5 entry cap disabled", 4, [('        if (total >= entryCap) {', '        if (false) {')]),
 ("G4-6 two classes swapped in the scan plan", 4, [('{ ids: ["debug"], rel: ".claude/debug", kind: "dir" },', '{ ids: ["debug"], rel: ".claude/todos", kind: "dir" },')]),
 ("G4-7 terminal catch dropped on an fs promise", 4, [('const settled = p.then(noop, noop);', 'const settled = p.then(noop);')]),
]
def apply(idx, path):
    name, guard, edits = M[idx]
    s = open(path).read()
    orig = s
    for old, new in edits:
        n = s.count(old)
        if n != 1:
            print(f"ANCHOR-COUNT {n} for {name}: {old[:60]!r}")
            sys.exit(3)
        s = s.replace(old, new, 1)
    if s == orig:
        print(f"DID-NOT-LAND {name}")
        sys.exit(4)
    open(path, "w").write(s)
if sys.argv[1] == "count":
    print(len(M))
elif sys.argv[1] == "name":
    print(M[int(sys.argv[2])][0])
elif sys.argv[1] == "apply":
    apply(int(sys.argv[2]), sys.argv[3])
PY
N="$(python3 "$SBR/mut.py" count)"

run_vitest() { # rc only; output kept for the failure report
  (cd "$SB" && timeout 280 ./node_modules/.bin/vitest run $TESTS >"$SBR/vitest.out" 2>&1)
}

FAILED=0
note() { printf '%s\n' "$*"; }

# ---- always-on: vacuity, landing, baseline, instrument control -----------------------------------------------------
if [[ "$N" -lt 17 ]]; then note "FLOOR: the battery holds $N mutations (expected 17)"; exit 1; fi
for ((i = 0; i < N; i++)); do
  cp "$PRISTINE" "$SBR/probe.ts"
  out="$(python3 "$SBR/mut.py" apply "$i" "$SBR/probe.ts" 2>&1)" || { note "LANDING FAILED: $out"; FAILED=1; }
done
run_vitest; rc=$?
if [[ "$rc" -ne 0 ]]; then note "BASELINE is not green (rc=$rc): the battery cannot be interpreted"; tail -15 "$SBR/vitest.out"; exit 1; fi
note "baseline: green (instrument control: the pristine copy exits 0)"
printf 'export const BROKEN = (\n' >>"$SB/server/home-census.ts"
run_vitest; rc=$?
cp "$PRISTINE" "$SB/server/home-census.ts"
if [[ "$rc" -ne 1 ]]; then note "INSTRUMENT: a deliberately broken copy exited $rc, not 1; rc=1 cannot be trusted as 'caught'"; exit 1; fi
note "instrument control: a broken copy exits 1"

if [[ "$FULL" != "1" ]]; then
  [[ "$FAILED" -eq 0 ]] || exit 1
  note "always-on checks passed ($N mutations landed). Run with HOME_CENSUS_MUTATIONS=1 for the full battery (reviewer)."
  exit 0
fi

# ---- full battery -------------------------------------------------------------------------------------------------
RED=0; SURV=0; UNRES=0; EXEC=0
for ((i = 0; i < N; i++)); do
  cp "$PRISTINE" "$SB/server/home-census.ts"
  name="$(python3 "$SBR/mut.py" name "$i")"
  python3 "$SBR/mut.py" apply "$i" "$SB/server/home-census.ts" >/dev/null 2>&1 || { note "UNRESOLVED  $name (did not land)"; UNRES=$((UNRES + 1)); continue; }
  run_vitest; rc=$?
  EXEC=$((EXEC + 1))
  case "$rc" in
    1) RED=$((RED + 1)); note "RED         $name" ;;
    0) SURV=$((SURV + 1)); note "SURVIVED    $name" ;;
    *) UNRES=$((UNRES + 1)); note "UNRESOLVED  $name (rc=$rc)" ;;
  esac
done
cp "$PRISTINE" "$SB/server/home-census.ts"
note "battery: $RED red, $SURV survived, $UNRES unresolved, $EXEC executed of $N"
if [[ "$EXEC" -ne "$N" ]]; then note "FLOOR: not every mutation executed"; exit 1; fi
[[ "$SURV" -eq 0 && "$UNRES" -eq 0 && "$FAILED" -eq 0 ]]
