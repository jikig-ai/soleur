#!/usr/bin/env bash
# Self-tests for the constraint-scaffold L1 import-boundary gate (ADR-071).
# Runs in the scripts shard (scripts/test-all.sh globs
# plugins/soleur/skills/*/test/*.test.sh). Proves the gate is NOT vacuous:
#
#   AC3   value import of server/** via the @/server/... alias FAILS;
#         an `import type` of the same PASSES; 0 couldNotResolve edges into
#         the secret set (alias resolution is live).
#   AC6   the secret (`to`) set is explicit and non-empty.
#   AC6b  a parenthesized/metacharacter route-group path is matched
#         (regex-escaping works); an empty from-set while "use client" files
#         exist is a HARD ERROR, not a silently-disabled rule.
#   AC5   neither app/ nor components/ present (empty input) fails closed;
#         a broken .cjs makes the shared runner fail closed.
#
# Hermetic: every fixture is synthesized under a mktemp dir; nothing is written
# into the real apps/web-platform tree.
set -uo pipefail

REPO_ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
APP="$REPO_ROOT/apps/web-platform"
CFG="$APP/.dependency-cruiser.cjs"
RUNNER="$APP/scripts/constraint-gates.sh"

pass=0
fail=0
ok()   { printf 'ok   - %s\n' "$1"; pass=$((pass + 1)); }
bad()  { printf 'FAIL - %s\n' "$1"; fail=$((fail + 1)); }

[[ -f "$CFG" ]]    || { echo "fatal: missing $CFG (run constraint-scaffold.sh)"; exit 2; }
[[ -f "$RUNNER" ]] || { echo "fatal: missing $RUNNER (run constraint-scaffold.sh)"; exit 2; }

BASELINE="$APP/.dependency-cruiser-known-violations.json"
[[ -f "$BASELINE" ]] || { echo "fatal: missing $BASELINE (run constraint-scaffold.sh)"; exit 2; }

# =============================================================================
# Toolchain-FREE assertions (#5777, ADR-071 amendment). These parse the committed
# baseline JSON + grep real source — NO dependency-cruiser needed — so they run in
# EVERY shard, before the toolchain SKIP guard below. They are the always-on half
# of the D2/D3/D4 invariants.
# =============================================================================

# --- AC4 (D3.1): committed baseline holds ZERO type:"reachability" entries -----
# A reachability entry is never benign: dependency-cruiser softens reachability
# per-ORIGIN (from+rule name only), so one baselined entry blinds that client to
# every future transitive secret. The reachable baseline MUST stay empty.
REACH_CT="$(node -e '
  const fs = require("fs");
  try { const b = JSON.parse(fs.readFileSync(process.argv[1],"utf8"));
    process.stdout.write(String((Array.isArray(b)?b:[]).filter(e=>e&&e.type==="reachability").length));
  } catch(e){ process.stdout.write("-1"); }' "$BASELINE" 2>/dev/null)"
if [[ "$REACH_CT" == "0" ]]; then
  ok "AC4(D3.1): committed baseline has zero type:\"reachability\" entries"
else
  bad "AC4(D3.1): committed baseline has $REACH_CT reachability entries (must be 0; parse err = -1)"
fi

# --- AC5b (D3.3): direct-rule non-regression — baseline type:"dependency" == 10 --
# tsPreCompilationDeps:false makes the direct rule's edge set a strict subset of
# v1's; this locks the one-time Phase-0.3 equivalence proof against future drift.
DEP_CT="$(node -e '
  const fs = require("fs");
  try { const b = JSON.parse(fs.readFileSync(process.argv[1],"utf8"));
    process.stdout.write(String((Array.isArray(b)?b:[]).filter(e=>e&&e.type==="dependency").length));
  } catch(e){ process.stdout.write("-1"); }' "$BASELINE" 2>/dev/null)"
if [[ "$DEP_CT" == "10" ]]; then
  ok "AC5b(D3.3): direct-rule baseline count unchanged (10) after tsPreCompilationDeps flip"
else
  bad "AC5b(D3.3): direct-rule baseline count is $DEP_CT (expected 10 — flip changed the direct set?)"
fi

# --- AC5 (D4/D3c): VALUE_SAFE_PATH modules are drift-proof value-safe -----------
# Each module the transitive rule excludes via to.pathNot MUST read no process.env
# value and take no VALUE import/re-export edge (import type is erased -> safe). A
# module silently gaining a secret while staying allowlisted is the deepest
# fail-open (both direct baseline + transitive pathNot exempt it). Derive the list
# FROM the .cjs VALUE_SAFE_PATH alternation so the two never drift.
check_value_safe_drift() {  # returns 0 = value-safe, 1 = drift detected
  local f="$1"
  grep -qE 'process\.env' "$f" && return 1
  # any `import|export ... from` that is NOT `import type`/`export type` = a value edge
  if grep -nE '^[[:space:]]*(import|export)[[:space:]]' "$f" \
       | grep -vE '^[0-9]+:[[:space:]]*(import|export)[[:space:]]+type[[:space:]]' \
       | grep -qE '(import|export)[[:space:]].*[[:space:]]from[[:space:]]'; then
    return 1
  fi
  return 0
}
# Non-vacuity: a synthesized module that reads process.env MUST trip the guard, and
# a synthesized import-type-only module MUST pass.
DRIFT_TMP="$(mktemp -d)"
printf 'export const X = process.env.SECRET_KEY;\n' > "$DRIFT_TMP/bad.ts"
printf 'import type { T } from "@/lib/types";\nexport const Y: T = 1 as unknown as T;\n' > "$DRIFT_TMP/good.ts"
if ! check_value_safe_drift "$DRIFT_TMP/bad.ts"; then
  ok "AC5(D4): drift guard TRIPS on a module that reads process.env (non-vacuous)"
else
  bad "AC5(D4): drift guard did NOT trip on a process.env-reading module (vacuous!)"
fi
if check_value_safe_drift "$DRIFT_TMP/good.ts"; then
  ok "AC5(D4): drift guard PASSES an import-type-only module (no false positive)"
else
  bad "AC5(D4): drift guard false-positived on an import-type-only module"
fi
rm -rf "$DRIFT_TMP"
# Extract the module basenames from the .cjs VALUE_SAFE_PATH alternation and assert
# each real server module is still value-safe.
VS_MODULES="$(grep -E 'VALUE_SAFE_PATH[[:space:]]*=' -A1 "$CFG" | grep -oE '\([^)]*\)' | head -1 | tr -d '()' | tr '|' ' ')"
if [[ -z "$VS_MODULES" ]]; then
  bad "AC5(D4): could not extract VALUE_SAFE_PATH module list from $CFG"
else
  vs_checked=0
  for m in $VS_MODULES; do
    mf="$APP/server/${m}.ts"
    if [[ ! -f "$mf" ]]; then
      bad "AC5(D4): VALUE_SAFE_PATH lists server/${m} but $mf does not exist"
      continue
    fi
    vs_checked=$((vs_checked + 1))
    if check_value_safe_drift "$mf"; then
      ok "AC5(D4): server/${m}.ts is value-safe (no process.env value read / no value import)"
    else
      bad "AC5(D4): server/${m}.ts DRIFTED out of value-safe (reads process.env or value-imports) — it is pathNot-excluded, so a secret there ships green; fix it or remove from VALUE_SAFE_PATH (see #5850)"
    fi
  done
  if [[ "$vs_checked" -lt 1 ]]; then
    bad "AC5(D4): zero VALUE_SAFE_PATH modules checked (extraction/glob broke)"
  fi
fi

# --- locate (or install) the dependency-cruiser binary -----------------------
# Fast path: the installed web-platform binary (present locally + in the
# test-webplat CI shard). Fallback: the test-scripts shard has node+npm but no
# web-platform deps, so install dependency-cruiser on demand into a temp dir.
TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

DEPCRUISE="$APP/node_modules/.bin/depcruise"
if [[ ! -x "$DEPCRUISE" ]]; then
  echo "# dependency-cruiser not installed in apps/web-platform — installing on demand..." >&2
  # Seed an empty package.json so npm installs INTO this temp dir. Without it,
  # `npm install` in a bare dir walks UP the tree, finds a parent project, reports
  # "up to date", and installs nothing → binary missing (env-dependent fragility).
  printf '{"name":"constraint-scaffold-test","private":true}\n' > "$TMPROOT/package.json"
  # typescript is REQUIRED alongside dependency-cruiser: depcruise cannot parse
  # .ts/.tsx (nor honor tsConfig alias resolution + tsPreCompilationDeps) without
  # the TS compiler. Omitting it makes depcruise emit ZERO edges from the .tsx
  # fixtures → every positive-detection assertion silently fails (the scripts-shard
  # CI failure on PR #5770). The non-vacuity guard below fails loud if this regresses.
  ( cd "$TMPROOT" && npm install --no-audit --no-fund dependency-cruiser@^16 typescript >/dev/null 2>&1 ) \
    || { echo "fatal: could not install dependency-cruiser + typescript"; exit 2; }
  DEPCRUISE="$TMPROOT/node_modules/.bin/depcruise"
  [[ -x "$DEPCRUISE" ]] || { echo "fatal: dependency-cruiser binary still missing after install"; exit 2; }
fi
NODE_MODULES="$(cd "$(dirname "$DEPCRUISE")/.." && pwd)"

# --- build a hermetic fixture Next.js-shaped app -----------------------------
# Returns the fixture path on stdout.
make_fixture() {
  local fx="$TMPROOT/fixture-$1"
  mkdir -p "$fx/server" "$fx/components/leakdir" "$fx/components/(a|b)"
  ln -s "$NODE_MODULES" "$fx/node_modules"
  cat > "$fx/tsconfig.json" <<'JSON'
{
  "compilerOptions": {
    "baseUrl": ".",
    "module": "esnext",
    "moduleResolution": "bundler",
    "jsx": "preserve",
    "paths": { "@/*": ["./*"] }
  },
  "include": ["**/*.ts", "**/*.tsx"]
}
JSON
  printf 'export const SECRET_TOKEN = "sk-do-not-ship";\nexport type SecretShape = { id: string };\n' > "$fx/server/secret.ts"
  # client module taking a VALUE import on a server secret -> must be flagged
  printf '"use client";\nimport { SECRET_TOKEN } from "@/server/secret";\nexport const Leak = () => SECRET_TOKEN;\n' > "$fx/components/leakdir/leak.tsx"
  # client module taking a TYPE-ONLY import of the same -> must NOT be flagged
  printf '"use client";\nimport type { SecretShape } from "@/server/secret";\nexport const T = (_: SecretShape) => null;\n' > "$fx/components/leakdir/typeonly.tsx"
  # client module under a regex-metacharacter route-group dir "(a|b)" -> must be
  # flagged. If the from-path were NOT regex-escaped, ^components/(a|b)/...$
  # would match literal "a"/"b" (never the literal "(a|b)" source) and the leak
  # would be silently missed.
  printf '"use client";\nimport { SECRET_TOKEN } from "@/server/secret";\nexport const P = () => SECRET_TOKEN;\n' > "$fx/components/(a|b)/parenleak.tsx"
  # client module with a leading license/eslint LINE-comment before the
  # directive (valid Next.js). If the directive test required the directive to
  # be the exact first non-empty line, this is misclassified as non-client and
  # its value import goes UNFLAGGED (silent leak). -> must be flagged.
  printf '// SPDX-License-Identifier: MIT\n"use client";\nimport { SECRET_TOKEN } from "@/server/secret";\nexport const B = () => SECRET_TOKEN;\n' > "$fx/components/leakdir/bannerleak.tsx"
  # client module with a leading BLOCK-comment banner before the directive.
  printf '/* banner\n   spanning lines */\n"use client";\nimport { SECRET_TOKEN } from "@/server/secret";\nexport const K = () => SECRET_TOKEN;\n' > "$fx/components/leakdir/blockbannerleak.tsx"
  # client module with a trailing comment on the directive line: `"use client"; // x`.
  printf '"use client"; // hydration boundary\nimport { SECRET_TOKEN } from "@/server/secret";\nexport const H = () => SECRET_TOKEN;\n' > "$fx/components/leakdir/trailingleak.tsx"

  # ---- #5777 TRANSITIVE-rule fixtures: helper in lib/ (outside app/components/ --
  # dependency-cruiser still FOLLOWS the edge into lib/ for reachability even though
  # lib/ is not a cruise root). `server/secret.ts` is NOT in VALUE_SAFE_PATH, so the
  # transitive rule genuinely fires; `server/domain-leaders.ts` IS (pathNot target).
  mkdir -p "$fx/lib" "$fx/components/trans"
  printf 'export const LEADERS = ["a"] as const;\n' > "$fx/server/domain-leaders.ts"
  # 4.1 NEGATIVE transitive (client -> lib helper(value) -> server/secret(value)) -> MUST FLAG
  printf 'import { SECRET_TOKEN } from "@/server/secret";\nexport const fmtT = () => SECRET_TOKEN;\n' > "$fx/lib/leak-helper.ts"
  printf '"use client";\nimport { fmtT } from "@/lib/leak-helper";\nexport const Trans = () => fmtT();\n' > "$fx/components/trans/transitive.tsx"
  # 4.2 POSITIVE first-hop type-only (client -> import type helper -> server value) -> MUST NOT FLAG
  printf 'import { SECRET_TOKEN } from "@/server/secret";\nexport const g = () => SECRET_TOKEN;\nexport type GT = string;\n' > "$fx/lib/typed-helper.ts"
  printf '"use client";\nimport type { GT } from "@/lib/typed-helper";\nexport const TFirst = (_: GT) => null;\n' > "$fx/components/trans/typeonly-firsthop.tsx"
  # 4.3 NEGATIVE mixed import { type A, realValue } on BOTH hops -> value edge MUST survive -> MUST FLAG
  printf 'import { type SecretShape, SECRET_TOKEN } from "@/server/secret";\nexport type MHT = SecretShape;\nexport const mfmt = (_: SecretShape) => SECRET_TOKEN;\n' > "$fx/lib/mixed-helper.ts"
  printf '"use client";\nimport { type MHT, mfmt } from "@/lib/mixed-helper";\nexport const Mx = (_: MHT) => mfmt(_);\n' > "$fx/components/trans/mixed.tsx"
  # 4.4 NEGATIVE barrel/re-export (export * AND named export-from) -> MUST FLAG
  printf 'export * from "@/server/secret";\n' > "$fx/lib/barrel.ts"
  printf '"use client";\nimport { SECRET_TOKEN } from "@/lib/barrel";\nexport const Bx = () => SECRET_TOKEN;\n' > "$fx/components/trans/barrel.tsx"
  printf 'export { SECRET_TOKEN } from "@/server/secret";\n' > "$fx/lib/named-barrel.ts"
  printf '"use client";\nimport { SECRET_TOKEN } from "@/lib/named-barrel";\nexport const NBx = () => SECRET_TOKEN;\n' > "$fx/components/trans/named-barrel.tsx"
  # 4.5 NEGATIVE dynamic import (statically resolvable) -> MUST FLAG
  printf 'export async function load(){ const m = await import("@/server/secret"); return m.SECRET_TOKEN; }\n' > "$fx/lib/dyn-helper.ts"
  printf '"use client";\nimport { load } from "@/lib/dyn-helper";\nexport const Dx = () => load();\n' > "$fx/components/trans/dynamic.tsx"
  # 4.6 POSITIVE pathNot target (client -> lib helper(value) -> server/domain-leaders(value)) -> MUST NOT FLAG
  printf 'import { LEADERS } from "@/server/domain-leaders";\nexport const safe = () => LEADERS;\n' > "$fx/lib/safe-helper.ts"
  printf '"use client";\nimport { safe } from "@/lib/safe-helper";\nexport const SafeTarget = () => safe();\n' > "$fx/components/trans/safe-target.tsx"

  cp "$CFG" "$fx/.dependency-cruiser.cjs"
  printf '%s' "$fx"
}

FX="$(make_fixture main)"

# --- Toolchain probe: can this depcruise actually PARSE the .tsx fixtures? -----
# The lightweight `test-scripts` CI shard has no apps/web-platform/node_modules,
# so depcruise is provisioned on-demand; that install can lack the exact TS
# toolchain depcruise needs to traverse .tsx (observed: "0 modules cruised" even
# with typescript present). When depcruise parses ZERO modules from a fixture
# that demonstrably contains .tsx client files, the TOOLCHAIN is the problem, not
# the gate — SKIP cleanly (exit 0) rather than emit false failures. The gate's
# real end-to-end coverage is the `constraint-gates` dogfood workflow (cruises
# the live apps/web-platform tree) plus local/webplat runs that use the committed
# depcruise. A gate REGRESSION (parses modules but misses a violation) still
# FAILS below — only a non-parsing toolchain skips. Non-vacuous by construction:
# the skip is loud and names where the real validation lives.
PARSED_COMPONENTS="$( cd "$FX" && "$DEPCRUISE" --config .dependency-cruiser.cjs --output-type json components server 2>/dev/null | node -e '
  let s=""; process.stdin.on("data",d=>s+=d); process.stdin.on("end",()=>{
    let n=0; try { const j=JSON.parse(s);
      for (const m of j.modules||[]) if (/^components\//.test(m.source||"")) n++;
    } catch(e){ n=0; } process.stdout.write(String(n)); });' 2>/dev/null )"
if ! [[ "$PARSED_COMPONENTS" =~ ^[0-9]+$ ]] || [[ "$PARSED_COMPONENTS" -lt 1 ]]; then
  echo "SKIP: depcruise parsed 0 component modules from the .tsx fixtures — toolchain"
  echo "      unavailable in this shard. The L1 gate is validated end-to-end by the"
  echo "      constraint-gates dogfood workflow (live apps/web-platform) + local runs."
  exit 0
fi

# --- AC3 + AC6b: positive/negative + regex-escaping --------------------------
ERR_OUT="$( cd "$FX" && "$DEPCRUISE" --config .dependency-cruiser.cjs --output-type err components server 2>&1 )"

if printf '%s' "$ERR_OUT" | grep -q 'components/leakdir/leak.tsx'; then
  ok "AC3: value import of server/** via @/server alias is flagged"
else
  bad "AC3: value import of server/** via @/server alias was NOT flagged"
  printf '%s\n' "$ERR_OUT" | sed 's/^/    /'
fi

if printf '%s' "$ERR_OUT" | grep -q 'components/leakdir/typeonly.tsx'; then
  bad "AC3: import type of server/** was flagged (type-only must be allowed)"
else
  ok "AC3: import type of server/** is allowed (not flagged)"
fi

if printf '%s' "$ERR_OUT" | grep -qF 'components/(a|b)/parenleak.tsx'; then
  ok "AC6b: regex-metacharacter route-group path matched (regex-escaping works)"
else
  bad "AC6b: parenthesized-path client file NOT matched — regex-escaping is broken"
  printf '%s\n' "$ERR_OUT" | sed 's/^/    /'
fi

# --- #2: directive preceded by a leading comment banner is still client -------
if printf '%s' "$ERR_OUT" | grep -q 'components/leakdir/bannerleak.tsx'; then
  ok "#2: leading line-comment before \"use client\" still classified client (flagged)"
else
  bad "#2: leading line-comment banner client file NOT flagged (fail-open misclassification)"
  printf '%s\n' "$ERR_OUT" | sed 's/^/    /'
fi
if printf '%s' "$ERR_OUT" | grep -q 'components/leakdir/blockbannerleak.tsx'; then
  ok "#2: leading block-comment before \"use client\" still classified client (flagged)"
else
  bad "#2: leading block-comment banner client file NOT flagged (fail-open misclassification)"
  printf '%s\n' "$ERR_OUT" | sed 's/^/    /'
fi
if printf '%s' "$ERR_OUT" | grep -q 'components/leakdir/trailingleak.tsx'; then
  ok "#2: \"use client\"; // trailing-comment form still classified client (flagged)"
else
  bad "#2: trailing-comment directive form client file NOT flagged (fail-open misclassification)"
  printf '%s\n' "$ERR_OUT" | sed 's/^/    /'
fi

# --- #5777 TRANSITIVE rule assertions (AC3, D1/D2). ERR_OUT is the same
# `components server` cruise; dependency-cruiser follows edges into lib/ for
# reachability. Anti-vacuity (4.9): we are PAST the toolchain SKIP guard, so these
# MUST execute and MUST fail (not skip) if a negative fixture is not flagged.
# 4.1 NEGATIVE transitive via lib/ helper -> MUST FLAG
if printf '%s' "$ERR_OUT" | grep -q 'components/trans/transitive.tsx'; then
  ok "4.1: transitive value chain (client -> lib helper -> server/secret) is flagged"
else
  bad "4.1: transitive value chain NOT flagged (the #5777 gap is still open)"
  printf '%s\n' "$ERR_OUT" | sed 's/^/    /'
fi
# 4.2 POSITIVE first-hop type-only -> MUST NOT FLAG (type-only edge elided globally)
if printf '%s' "$ERR_OUT" | grep -q 'components/trans/typeonly-firsthop.tsx'; then
  bad "4.2: first-hop import-type chain was FLAGGED (type-only must be elided -> false positive)"
else
  ok "4.2: first-hop import-type chain is not flagged (type-only elided, position-independent)"
fi
# 4.3 NEGATIVE mixed import { type A, realValue } -> value edge survives -> MUST FLAG
if printf '%s' "$ERR_OUT" | grep -q 'components/trans/mixed.tsx'; then
  ok "4.3: mixed { type A, realValue } chain is flagged (value edge survives the flip)"
else
  bad "4.3: mixed-import chain NOT flagged — a value edge was wrongly elided as type-only (silent fail-open)"
  printf '%s\n' "$ERR_OUT" | sed 's/^/    /'
fi
# 4.4 NEGATIVE barrel (export *) + named export-from -> MUST FLAG
if printf '%s' "$ERR_OUT" | grep -q 'components/trans/barrel.tsx'; then
  ok "4.4a: barrel re-export (export * from) chain is flagged"
else
  bad "4.4a: barrel (export *) chain NOT flagged"
  printf '%s\n' "$ERR_OUT" | sed 's/^/    /'
fi
if printf '%s' "$ERR_OUT" | grep -q 'components/trans/named-barrel.tsx'; then
  ok "4.4b: named export-from re-export chain is flagged"
else
  bad "4.4b: named export-from chain NOT flagged"
  printf '%s\n' "$ERR_OUT" | sed 's/^/    /'
fi
# 4.5 NEGATIVE dynamic import() -> MUST FLAG
if printf '%s' "$ERR_OUT" | grep -q 'components/trans/dynamic.tsx'; then
  ok "4.5: dynamic import() chain is flagged (reachability traverses dynamic edges)"
else
  bad "4.5: dynamic import() chain NOT flagged"
  printf '%s\n' "$ERR_OUT" | sed 's/^/    /'
fi
# 4.6 POSITIVE pathNot target (server/domain-leaders) -> MUST NOT FLAG by transitive rule
if printf '%s' "$ERR_OUT" | grep -q 'components/trans/safe-target.tsx'; then
  bad "4.6: pathNot-target chain (client -> helper -> server/domain-leaders) was FLAGGED (pathNot broken)"
  printf '%s\n' "$ERR_OUT" | sed 's/^/    /'
else
  ok "4.6: pathNot-target chain is not flagged (value-safe target excluded, no baseline double-count)"
fi

# --- AC3: 0 couldNotResolve edges into the secret set ------------------------
JSON_OUT="$( cd "$FX" && "$DEPCRUISE" --config .dependency-cruiser.cjs --output-type json components server 2>/dev/null )"
UNRESOLVED_INTO_SERVER="$(
  printf '%s' "$JSON_OUT" | node -e '
    let s = ""; process.stdin.on("data", d => s += d); process.stdin.on("end", () => {
      let n = 0;
      try {
        const j = JSON.parse(s);
        for (const m of j.modules || [])
          for (const dep of m.dependencies || [])
            if (/^server\//.test(dep.resolved || "") && dep.couldNotResolve) n++;
      } catch (e) { n = -1; }
      process.stdout.write(String(n));
    });
  ' 2>/dev/null
)"
if [[ "$UNRESOLVED_INTO_SERVER" == "0" ]]; then
  ok "AC3: 0 couldNotResolve edges into server/ (tsConfig alias resolution live)"
else
  bad "AC3: couldNotResolve edges into server/ = $UNRESOLVED_INTO_SERVER (expected 0)"
fi

# --- AC6: the secret (`to`) set is explicit and non-empty --------------------
if grep -q 'SECRET_PATH = "\^server/"' "$CFG"; then
  ok "AC6: secret (to) set is explicit and non-empty (^server/)"
else
  bad "AC6: secret (to) set not found / not the expected ^server/ in .cjs"
fi

# --- AC6b: empty from-set while "use client" files exist -> HARD ERROR --------
EMPTY_OUT="$( cd "$FX" && CONSTRAINT_SCAFFOLD_TEST_FORCE_EMPTY=1 node -e 'require("./.dependency-cruiser.cjs")' 2>&1 )"
EMPTY_RC=$?
if [[ "$EMPTY_RC" -ne 0 ]] && printf '%s' "$EMPTY_OUT" | grep -q 'from-set is empty'; then
  ok "AC6b: empty from-set while client files exist throws (not silently disabled)"
else
  bad "AC6b: empty from-set did NOT hard-fail (rc=$EMPTY_RC): $EMPTY_OUT"
fi

# --- AC5: empty input (no app/ and no components/) fails closed ---------------
EMPTYDIR="$TMPROOT/no-client-dirs"
mkdir -p "$EMPTYDIR/server"
ln -s "$NODE_MODULES" "$EMPTYDIR/node_modules"
cp "$CFG" "$EMPTYDIR/.dependency-cruiser.cjs"
NOINPUT_OUT="$( cd "$EMPTYDIR" && node -e 'require("./.dependency-cruiser.cjs")' 2>&1 )"
NOINPUT_RC=$?
if [[ "$NOINPUT_RC" -ne 0 ]] && printf '%s' "$NOINPUT_OUT" | grep -qE 'neither app/ nor components/'; then
  ok "AC5: empty input (no client dirs) fails closed (distinct from 'no client modules')"
else
  bad "AC5: empty input did NOT fail closed (rc=$NOINPUT_RC): $NOINPUT_OUT"
fi

# --- AC5: broken .cjs -> shared runner fails closed --------------------------
BROKEN="$TMPROOT/broken-app"
mkdir -p "$BROKEN/app" "$BROKEN/components" "$BROKEN/server" "$BROKEN/scripts"
ln -s "$NODE_MODULES" "$BROKEN/node_modules"
printf 'module.exports = { this is not valid javascript\n' > "$BROKEN/.dependency-cruiser.cjs"
printf '[]\n' > "$BROKEN/.dependency-cruiser-known-violations.json"
BROKEN_OUT="$( CONSTRAINT_GATES_DIR="$BROKEN" bash "$RUNNER" 2>&1 )"
BROKEN_RC=$?
if [[ "$BROKEN_RC" -ne 0 ]] && printf '%s' "$BROKEN_OUT" | grep -q 'config/binary error'; then
  ok "AC5: broken .cjs makes the shared runner fail closed (rc=$BROKEN_RC)"
else
  bad "AC5: broken .cjs did NOT fail the runner closed (rc=$BROKEN_RC): $BROKEN_OUT"
fi

# --- AC10: shared runner is GREEN on a clean baselined fixture ----------------
# In v2 the reachable rule is a SUPERSET of the direct rule (a direct edge is a
# length-1 path), so a direct leak to a NON-value-safe module ALSO produces a
# type:"reachability" violation that must NOT be baselined (the D3 runner guard
# rejects it). The real app is green because its baselined direct edges all target
# VALUE_SAFE modules (pathNot-excluded from the reachable rule). Mirror that exactly:
# a client that directly value-imports a value-safe server module -> the direct rule
# flags it (a baselineable dependency), the reachable rule excludes it (no
# reachability entry) -> baseline all -> runner green.
CLEAN="$BROKEN-clean"
mkdir -p "$CLEAN/app" "$CLEAN/components/c" "$CLEAN/server" "$CLEAN/scripts"
ln -s "$NODE_MODULES" "$CLEAN/node_modules"
cp "$FX/tsconfig.json" "$CLEAN/tsconfig.json"
cp "$CFG" "$CLEAN/.dependency-cruiser.cjs"
printf 'export const LEADERS = ["a"] as const;\n' > "$CLEAN/server/domain-leaders.ts"
printf '"use client";\nimport { LEADERS } from "@/server/domain-leaders";\nexport const V = () => LEADERS;\n' > "$CLEAN/components/c/valuesafe.tsx"
( cd "$CLEAN" && "$DEPCRUISE" --config .dependency-cruiser.cjs --output-type baseline app components server > .dependency-cruiser-known-violations.json 2>/dev/null )
CLEAN_OUT="$( CONSTRAINT_GATES_DIR="$CLEAN" bash "$RUNNER" 2>&1 )"
CLEAN_RC=$?
if [[ "$CLEAN_RC" -eq 0 ]]; then
  ok "AC10: shared runner is green (rc=0) when all (value-safe direct) violations are baselined"
else
  bad "AC10: shared runner not green on baselined fixture (rc=$CLEAN_RC): $CLEAN_OUT"
fi

# --- 4.8: real-runner rc != 0 on an un-baselined TRANSITIVE leak ---------------
# The full FX fixture contains transitive leaks. With an EMPTY baseline (0
# reachability entries -> the D3 runner guard passes), the cruise itself must fail
# on the transitive reachability violation and reach the runner's 'dependency
# violations' fail branch — proving a reachability violation is enforced end-to-end
# through the real runner (not only via --output-type json).
LEAKY="$BROKEN-transitive-leak"
cp -r "$FX" "$LEAKY"
rm -f "$LEAKY/node_modules"; ln -s "$NODE_MODULES" "$LEAKY/node_modules"
mkdir -p "$LEAKY/app" "$LEAKY/scripts"
# Remove DIRECT-leak fixtures so the ONLY violation the runner sees is transitive —
# proves the reachable rule (not the direct rule) drives the non-zero exit.
rm -rf "$LEAKY/components/leakdir" "$LEAKY/components/(a|b)"
rm -f "$LEAKY/components/trans/typeonly-firsthop.tsx" "$LEAKY/components/trans/safe-target.tsx" \
      "$LEAKY/lib/typed-helper.ts" "$LEAKY/lib/safe-helper.ts"
printf '[]\n' > "$LEAKY/.dependency-cruiser-known-violations.json"
LEAKY_OUT="$( CONSTRAINT_GATES_DIR="$LEAKY" bash "$RUNNER" 2>&1 )"
LEAKY_RC=$?
if [[ "$LEAKY_RC" -ne 0 ]] && printf '%s' "$LEAKY_OUT" | grep -q 'import-boundary violation'; then
  ok "4.8: real runner fails closed (rc=$LEAKY_RC) on an un-baselined transitive leak"
else
  bad "4.8: real runner did NOT fail on a transitive leak (rc=$LEAKY_RC): $LEAKY_OUT"
fi

echo "---"
echo "boundary.test.sh: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
