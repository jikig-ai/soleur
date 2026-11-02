#!/usr/bin/env bash
# Shared helpers for the launch-check suites (sourced; not itself a suite).
# Fixture repos are BUILT AT TEST TIME under a scratch dir: nested .git directories cannot be
# committed, and a committed secret-shaped string would trip this repository's own gitleaks CI.
SKILL="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
LC="$SKILL/scripts/launch-check.sh"
# shellcheck disable=SC2034
PLUGIN="$(cd "$SKILL/../.." && pwd -P)"
# Test seams (scanner, sentinel and manifest overrides) are honoured only under LAUNCH_CHECK_TEST=1; the suites
# exercise real report writes, so the unattended-run switches are cleared (the headless suite sets them itself).
export LAUNCH_CHECK_TEST=1
unset CI LAUNCH_CHECK_HEADLESS
SCRATCH="$(mktemp -d "${TMPDIR:-/var/tmp}/lc-test.XXXXXX")"
trap 'rm -rf "${SCRATCH:?}"' EXIT
passes=0; fails=0
pass() { printf 'ok   - %s\n' "$1"; passes=$((passes + 1)); }
fail() { printf 'FAIL - %s\n' "$1"; fails=$((fails + 1)); }
check() { local d=$1; shift; if "$@"; then pass "$d"; else fail "$d"; fi }

# git under a constructed environment: no inherited GIT_* location variables, pinned identity.
gitq() {
  local d=$1; shift
  env -u GIT_DIR -u GIT_INDEX_FILE -u GIT_WORK_TREE -u GIT_OBJECT_DIRECTORY -u GIT_COMMON_DIR -u GIT_NAMESPACE \
    GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null \
    GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid \
    git -C "$d" "$@"
}
# lc: run launch-check with the same cleaned git environment.
lc() {
  env -u GIT_DIR -u GIT_INDEX_FILE -u GIT_WORK_TREE -u GIT_OBJECT_DIRECTORY -u GIT_COMMON_DIR -u GIT_NAMESPACE \
    GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null \
    GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid \
    bash "$LC" "$@"
}
mkrepo() { local d="$SCRATCH/$1"; mkdir -p "$d"; gitq "$d" init -q -b main; printf '%s' "$d"; }
commit_all() { gitq "$1" add -A; gitq "$1" -c commit.gpgsign=false commit -q -m fixture; }
put() { local f=$1; shift; mkdir -p "$(dirname "$f")"; printf '%s\n' "$@" > "$f"; }
# sub_in_place <file> <sed args...>: edit via a temp file and mv (no removal commands).
sub_in_place() { local f=$1; shift; sed "$@" "$f" > "$f.new" && mv "$f.new" "$f"; }

fx_minimal() { local d; d=$(mkrepo "$1"); put "$d/README.md" '# app'; put "$d/src/index.js" 'console.log(1)'; put "$d/package.json" '{"name":"app"}'; commit_all "$d"; printf '%s' "$d"; }
fx_healthy() {
  local d; d=$(mkrepo "$1")
  put "$d/package.json" '{"name":"app","dependencies":{"next":"1","@sentry/nextjs":"1"},"devDependencies":{"dependency-cruiser":"1"},"scripts":{"test":"vitest"}}'
  put "$d/package-lock.json" '{}'
  put "$d/.github/workflows/ci.yml" 'name: ci' 'on: [pull_request]' 'jobs:' '  t:' '    runs-on: ubuntu-latest' '    steps:' '      - run: npm test'
  put "$d/.github/dependabot.yml" 'version: 2'
  put "$d/.nvmrc" '22'
  put "$d/docs/adr/0001-record.md" '# ADR 1'
  put "$d/CLAUDE.md" '# conventions'
  put "$d/docs/runbooks/db.md" 'Backup and restore: nightly snapshot.'
  put "$d/src/server.ts" 'app.get("/health", () => "ok")'
  local i; for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21; do put "$d/src/m$i.ts" "export const v$i = $i"; done
  put "$d/src/m1.test.ts" 'test("a", () => {})' ; put "$d/src/m2.test.ts" 'test("b", () => {})'
  commit_all "$d"; printf '%s' "$d"
}
fx_python() { local d; d=$(mkrepo "$1"); put "$d/pyproject.toml" '[project]' 'name="app"'; put "$d/app.py" 'print(1)'; commit_all "$d"; printf '%s' "$d"; }
# The planted secret is assembled from fragments so no contiguous token literal exists in this source.
planted_secret() { printf '%s%s' 'ghp_' 'R7vK2mQ9xT4bN8cL1wZ5eH3jY6uA0dF2gS9p'; }
fx_secret() { local d; d=$(fx_healthy "$1"); put "$d/src/config.js" "module.exports = { token: \"$(planted_secret)\" };"; commit_all "$d"; printf '%s' "$d"; }
fx_envfile() { local d; d=$(fx_minimal "$1"); put "$d/.env" 'DB_URL=postgres://x'; gitq "$d" add -f .env; gitq "$d" -c commit.gpgsign=false commit -q -m env; printf '%s' "$d"; }
fx_markers() { local d i; d=$(fx_minimal "$1"); : > "$d/src/debt.js"; for i in $(seq 1 60); do printf '// TODO item %s\n' "$i" >> "$d/src/debt.js"; done; commit_all "$d"; printf '%s' "$d"; }
fx_next_nogate() { local d; d=$(fx_minimal "$1"); put "$d/package.json" '{"name":"app","dependencies":{"next":"1"}}'; put "$d/vercel.json" '{}'; commit_all "$d"; printf '%s' "$d"; }
fx_symlink() { local d; d=$(fx_minimal "$1"); ln -s /etc/hostname "$d/src/link.js"; put "$d/docs/environment.md" 'doc'; put "$d/key.pem" 'x'; put "$d/data.sql" 'x'; put "$d/terraform.tfstate" '{}'; commit_all "$d"; printf '%s' "$d"; }

# fact <facts-file> <id> -> status
fact() { awk -F'\t' -v id="$2" '$1==id {print $2; exit}' "$1"; }
scan_to() { # scan_to <repo> <facts-out> [extra args]
  local r=$1 out=$2; shift 2
  lc scan --target "$r" --facts "$out" --files-out "$out.files" "$@" > "$out.stdout" 2> "$out.stderr"
}
finish() { # finish <minimum assertion count>
  if [ $((passes + fails)) -lt "$1" ]; then printf 'FAIL - assertion floor: %d ran, %d required\n' $((passes + fails)) "$1"; exit 1; fi
  printf '%d passed, %d failed\n' "$passes" "$fails"
  [ "$fails" -eq 0 ]
}
# Instrument self-test: drive pass() and fail() once each in a subshell and require both counters to move.
selftest() { local p f; p=$(bash -c 'source "$1"; pass x >/dev/null; echo $passes' _ "${BASH_SOURCE[0]}"); f=$(bash -c 'source "$1"; fail x >/dev/null; echo $fails' _ "${BASH_SOURCE[0]}"); [ "$p" = 1 ] && [ "$f" = 1 ]; }
