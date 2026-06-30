#!/usr/bin/env bash
# Self-tests for the constraint-scaffold L1 import-boundary gate (ADR-070).
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

# --- locate (or install) the dependency-cruiser binary -----------------------
# Fast path: the installed web-platform binary (present locally + in the
# test-webplat CI shard). Fallback: the test-scripts shard has node+npm but no
# web-platform deps, so install dependency-cruiser on demand into a temp dir.
TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

DEPCRUISE="$APP/node_modules/.bin/depcruise"
if [[ ! -x "$DEPCRUISE" ]]; then
  echo "# dependency-cruiser not installed in apps/web-platform — installing on demand..." >&2
  ( cd "$TMPROOT" && npm install --no-audit --no-fund --no-save dependency-cruiser@^16 >/dev/null 2>&1 ) \
    || { echo "fatal: could not install dependency-cruiser"; exit 2; }
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
  cp "$CFG" "$fx/.dependency-cruiser.cjs"
  printf '%s' "$fx"
}

FX="$(make_fixture main)"

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
CLEAN="$BROKEN-clean"
cp -r "$FX" "$CLEAN"
rm -f "$CLEAN/node_modules"; ln -s "$NODE_MODULES" "$CLEAN/node_modules"
mkdir -p "$CLEAN/app" "$CLEAN/scripts"
( cd "$CLEAN" && "$DEPCRUISE" --config .dependency-cruiser.cjs --output-type baseline app components server > .dependency-cruiser-known-violations.json 2>/dev/null )
CLEAN_OUT="$( CONSTRAINT_GATES_DIR="$CLEAN" bash "$RUNNER" 2>&1 )"
CLEAN_RC=$?
if [[ "$CLEAN_RC" -eq 0 ]]; then
  ok "AC10: shared runner is green (rc=0) when all violations are baselined"
else
  bad "AC10: shared runner not green on baselined fixture (rc=$CLEAN_RC): $CLEAN_OUT"
fi

echo "---"
echo "boundary.test.sh: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
