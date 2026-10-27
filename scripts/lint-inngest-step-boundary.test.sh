#!/usr/bin/env bash
# Self-test for scripts/lint-inngest-step-boundary.py (#8764).
set -euo pipefail

LINT="scripts/lint-inngest-step-boundary.py"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
fails=0
n=0
check() { # name want_exit filename fixture-content
  local name="$1" want="$2" file="$3" content="$4"
  n=$((n+1)); local d="$WORK/case$n"; mkdir -p "$d"
  printf '%s\n' "$content" >"$d/$file"
  if python3 "$LINT" "$d" >/dev/null 2>&1; then got=0; else got=$?; fi
  if [[ "$got" != "$want" ]]; then echo "FAIL: $name (want $want, got $got)"; fails=$((fails+1)); else echo "pass: $name"; fi
}

check "boundary instanceof flagged" 1 bad.ts 'export async function h({ step }: { step: { run<T>(n: string, c: () => Promise<T>): Promise<T> } }) {
  try { await step.run("x", async () => 1); } catch (err) { if (err instanceof DeployErr) return 1; return 0; }
}
class DeployErr extends Error {}'

check "boundary .status flagged" 1 bad.ts 'export async function h({ step }: { step: { run<T>(n: string, c: () => Promise<T>): Promise<T> } }) {
  try { await step.run("x", async () => 1); } catch (err) { return err.status === 401 ? 1 : 0; }
}'

check "boundary .name === flagged" 1 bad.ts 'export async function h({ step }: { step: { run<T>(n: string, c: () => Promise<T>): Promise<T> } }) {
  try { await step.run("x", async () => 1); } catch (err) { return err.name === "X" ? 1 : 0; }
}'

check "instanceof Error exempt" 0 good.ts 'export async function h({ step }: { step: { run<T>(n: string, c: () => Promise<T>): Promise<T> } }) {
  try { await step.run("x", async () => 1); } catch (err) { const e = err instanceof Error ? err : new Error("x"); return e.message.length; }
}'

check "step-internal unlisted flagged" 1 unlisted.ts 'export async function h({ step }: { step: { run<T>(n: string, c: () => Promise<T>): Promise<T> } }) {
  return step.run("x", async () => { try { return 1; } catch (err) { if (err instanceof ApiErr) return 2; throw err; } });
}
class ApiErr extends Error {}'

check "step-internal allowlisted exempt" 0 cron-anthropic-credit-probe.ts 'export async function h({ step }: { step: { run<T>(n: string, c: () => Promise<T>): Promise<T> } }) {
  return step.run("x", async () => { try { return 1; } catch (err) { if (err instanceof ApiErr || err.status === 401) return 2; throw err; } });
}
class ApiErr extends Error {}'

check "catch without step.run not flagged" 0 nostep.ts 'export function f() { try { JSON.parse("x"); } catch (err) { return (err as SyntaxError).message ? 1 : 0; } }'

check "real corpus clean" 0 real.ts 'export function g() { return 1; }'
# and the live tree itself stays clean
python3 "$LINT" >/dev/null && echo "pass: live corpus clean" || { echo "FAIL: live corpus"; fails=$((fails+1)); }

[[ $fails -eq 0 ]] && { echo "lint-inngest-step-boundary.test.sh: all checks passed"; exit 0; }
echo "lint-inngest-step-boundary.test.sh: $fails FAILURES"; exit 1
