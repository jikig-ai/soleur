#!/usr/bin/env bash
# Install-time bite-proof + README/pointer coverage for constraint-scaffold.sh (#8288, ADR-071
# amendment 2026-09-19). Proves that every scaffold run that reports success has observed the
# emitted gate, on a detached worktree of the target's HEAD, go pass -> fail -> pass — naming
# `no-client-to-server-secret` on the direct probe edge AND `no-client-to-server-secret-transitive`
# on the one-hop probe edge — and that a run which cannot prove it leaves the founder's tree as it
# found it. Also covers the append-once README block and the agent-instructions pointer, which are
# the LAST writes of a default-mode run (after the bite), never a refresh-mode write.
#
# Suite order (test-design): source pins -> stub-driven -> locate-or-install -> toolchain probe ->
# real. An `npm install` failure in the scripts shard therefore cannot `exit 2` before the
# toolchain-free segments have run and carried their own floor.
#
# ZERO PRODUCTION SEAMS. The script honours no CONSTRAINT_SCAFFOLD_TEST_* variable (a pin below
# asserts the literal is absent). Every failure arm is driven by a FIXTURE-OWNED stub `depcruise`
# reached through the fixture's `apps/web-platform/node_modules` symlink. The stub implements the
# three-branch table from the plan (D6): `--output-type baseline` -> `[]`; `--output-type json` ->
# `{"modules":[]}`; `--output-type err` -> the probe arm iff
# `components/__constraint_scaffold_bite_probe__/direct.tsx` exists in cwd (the runner `cd`s to
# the app dir), else the clean arm. It appends its argv to `calls.log` and exits 64 on an argv
# shape it does not recognise, and its `dependency-cruiser/package.json` carries the distinctive
# version `0.0.0-stub` so the real-toolchain case can prove it did NOT run the stub.
#
# Every fixture is synthesized under a mktemp root (cq-test-fixtures-synthesized-only); nothing
# is written into the real apps/web-platform tree or into this repository's CLAUDE.md.
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

# Refuses an empty, relative, root or synthetic-fs fixture dir (byte-identical copy; the
# fixture-dir-operand-assert suite pins every tracked copy).
assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY; git -C "" would operate on %s\n' "$PWD" >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}

REPO_ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
assert_fixture_dir "$REPO_ROOT"
SKILL="$REPO_ROOT/plugins/soleur/skills/constraint-scaffold"
GEN="$SKILL/scripts/constraint-scaffold.sh"
REF="$SKILL/references"
APP="$REPO_ROOT/apps/web-platform"

RULE_DIRECT="no-client-to-server-secret"
RULE_TRANSITIVE="no-client-to-server-secret-transitive"
PROBE_DIR="components/__constraint_scaffold_bite_probe__"
POINTER_MARKER="<!-- constraint-scaffold:pointer -->"
README_START="<!-- constraint-scaffold:readme:start -->"
README_END="<!-- constraint-scaffold:readme:end -->"
VERDICT_RE="^constraint-scaffold: bite-proof pass -> fail\(${RULE_DIRECT}@direct, ${RULE_TRANSITIVE}@via-hop\) -> pass depcruise=[^ ]+$"

pass=0
fail=0
# The INDEPENDENT case counter (ADR-193 #2). Incremented at every CALL SITE, and NEVER inside
# ok()/bad() — the VERDICT helpers, which touch only the verdict counters. A counter bumped inside
# the verdict helpers moves WITH the verdict, so stubbing bad() drops the row and its count together
# and `pass + fail == cases` still holds under the exact fault it exists to catch. Incremented at
# top level only, never inside a `$( … )` command substitution.
cases=0
# Anti-vacuity thresholds (TOOLCHAIN_FREE_MIN_ASSERTIONS at the toolchain-SKIP door,
# MIN_ASSERTIONS at the trailer). Each literal is bound on the line DIRECTLY above its `if`,
# because guard-vacuity-floor's backward slice carries only contiguous simple assignments into
# its neutered-machinery mutant; bound anywhere else, the mutant dies unbound and the floor
# scores CONSTRUCTION instead of FIRES.
#
# Derived at commit time, never hand-summed: each constant is
# `grep -cE '^\s*cases=\$\(\(cases \+ 1\)\)$'` over its segment of THIS file (the anchored form
# skips the two prose mentions inside the accounting messages), minus the sites that are
# legitimately conditional, so the floor is a genuine LOWER BOUND rather than a snapshot:
#   TOOLCHAIN_FREE_MIN_ASSERTIONS = 75 call sites above the locate-or-install block, minus the 2
#                                   C-chmod sites that only run when not root         = 73
#   MIN_ASSERTIONS                = that + the 18 call sites of the real segment      = 91
ok()   { printf 'ok   - %s\n' "$1"; pass=$((pass + 1)); }
bad()  { printf 'FAIL - %s\n' "$1"; fail=$((fail + 1)); }
# Instrument self-test — DIRECTION, not only presence: conservation (`pass + fail == cases`) and
# both floors count verdicts, so a bad() misrouted to the pass counter keeps every gate green while
# printing FAIL rows. Drive each helper once, require the RIGHT counter moved, reset. Reported via
# printf >&2 + exit 1, never through the helper it checks (ADR-193).
bad "instrument self-test (expected — proves bad() records a FAILURE)" >/dev/null
ok  "instrument self-test (expected — proves ok() records a PASS)" >/dev/null
if [[ "$fail" != "1" || "$pass" != "1" ]]; then
  printf '[FATAL] HELPER CONTROL BROKEN: after one bad() and one ok(), fail=%s pass=%s (want 1/1)\n' "$fail" "$pass" >&2
  exit 1
fi
pass=0; fail=0

[[ -f "$GEN" ]] || { echo "fatal: missing $GEN"; exit 2; }
[[ -f "$REF/depcruise-config.template" ]] || { echo "fatal: missing depcruise-config.template"; exit 2; }
command -v node >/dev/null 2>&1 || { echo "fatal: node is required (the emitted runner parses JSON with it)"; exit 2; }

TMPROOT="$(mktemp -d)" || { echo "FATAL: cannot create scratch root" >&2; exit 1; }
: "${TMPROOT:?scratch root must be non-empty}"
[[ "$TMPROOT" == /* && -d "$TMPROOT" && ! -L "$TMPROOT" ]] || {
  echo "FATAL: scratch root is not a plain absolute directory: '$TMPROOT'" >&2; exit 1; }
# EXIT **INT TERM**: a ^C during the on-demand `npm install` below must still remove the root.
trap 'rm -rf -- "${TMPROOT:-}"' EXIT INT TERM
assert_fixture_dir "$TMPROOT"

# =============================================================================================
# Segment 1 — SOURCE PINS (no fixture run). Shape facts about constraint-scaffold.sh that the
# behavioural cases below rely on and that one diff could otherwise silently move.
# =============================================================================================
echo "# --- source pins ---"

# Pin: the default-mode failure-cleanup list names exactly the artifacts the refuse-if-exists
# guard protects (the script owns one list; a new artifact cannot be left behind on a failed bite
# without also being left out of the refuse loop, and vice-versa).
vars_of() { grep -oE '\$[A-Z_]+' | sort -u | tr '\n' ' '; }
REFUSE_VARS="$( { grep -E '^for f in .*"\$CFG".*; do$' "$GEN"; grep -oE '^\[\[ -e "\$BASELINE" \]\] && die "refuse-if-exists' "$GEN"; } | vars_of )"
CLEANUP_VARS="$( awk '/^remove_emitted_artifacts\(\)/{f=1} f && /^}/{f=0} f' "$GEN" | grep -E '^\s*for f in .*"\$CFG"' | vars_of )"
cases=$((cases + 1))
if [[ -n "$CLEANUP_VARS" && "$CLEANUP_VARS" == "$REFUSE_VARS" && "$REFUSE_VARS" == *'$BASELINE'* && "$REFUSE_VARS" == *'$FIXWORKFLOW_B'* ]]; then
  ok "pin: default-mode cleanup list == refuse-if-exists list ($CLEANUP_VARS)"
else
  bad "pin: cleanup list [$CLEANUP_VARS] != refuse-if-exists list [$REFUSE_VARS]"
fi

# Pin: inside with_detached_worktree(), the `trap '_wt_cleanup` line PRECEDES `worktree add
# --detach` (ADR-129 — the trap owns the dir before the operation that can fail). Matched on the
# specific handler so a `trap - EXIT` line cannot satisfy it.
# Comment-STRIPPED: the script documents the very constructs these pins look for.
WT_BODY="$(awk '/^with_detached_worktree\(\)/{f=1} f{print} f && /^}/{exit}' "$GEN" | grep -vE '^\s*#')"
TRAP_LN="$(printf '%s\n' "$WT_BODY" | grep -nF "trap '_wt_cleanup" | head -1 | cut -d: -f1)"
ADD_LN="$(printf '%s\n' "$WT_BODY" | grep -n 'worktree add --detach' | head -1 | cut -d: -f1)"
cases=$((cases + 1))
if [[ -n "$TRAP_LN" && -n "$ADD_LN" && "$TRAP_LN" -lt "$ADD_LN" ]]; then
  ok "pin: trap '_wt_cleanup' (line $TRAP_LN of the helper) precedes worktree add --detach (line $ADD_LN)"
else
  bad "pin: trap '_wt_cleanup' must precede worktree add --detach inside with_detached_worktree (trap=$TRAP_LN add=$ADD_LN)"
fi

# Pin: the INT/TERM arm clears EXIT inside itself and exits 143 (cleanup runs once; a TERM is a
# property, not an accident).
cases=$((cases + 1))
if printf '%s\n' "$WT_BODY" | grep -qF "trap '_wt_cleanup interrupted; trap - EXIT; exit 143' INT TERM"; then
  ok "pin: INT/TERM arm is '_wt_cleanup interrupted; trap - EXIT; exit 143'"
else
  bad "pin: INT/TERM arm missing or not the prescribed shape"
fi

# Pin: the two rule-name literals in the script equal the `name:` fields of the config template,
# in order (a rename in the template reds here before it reds in a founder repo).
TEMPLATE_RULES="$(grep -oE 'name: "[^"]+"' "$REF/depcruise-config.template" | sed -E 's/name: "([^"]+)"/\1/' | tr '\n' ' ')"
SCRIPT_RULES="$( { grep -E '^RULE_DIRECT=' "$GEN"; grep -E '^RULE_TRANSITIVE=' "$GEN"; } | sed -E 's/^[A-Z_]+="([^"]+)"$/\1/' | tr '\n' ' ')"
cases=$((cases + 1))
if [[ -n "$SCRIPT_RULES" && "$SCRIPT_RULES" == "$TEMPLATE_RULES" && "$TEMPLATE_RULES" == "$RULE_DIRECT $RULE_TRANSITIVE " ]]; then
  ok "pin: script rule literals == template name: fields ($TEMPLATE_RULES)"
else
  bad "pin: script rule literals [$SCRIPT_RULES] != template name: fields [$TEMPLATE_RULES]"
fi

# Pin: verdict_fail prints its stdout line BEFORE it dies (agent runtimes surface stdout and
# swallow stderr), and the stdout line is not itself redirected to stderr.
VF_BODY="$(awk '/^verdict_fail\(\)/{f=1} f{print} f && /^}/{exit}' "$GEN" | grep -vE '^\s*#')"
VF_PRINT_LN="$(printf '%s\n' "$VF_BODY" | grep -n "bite-proof FAILED" | grep -v '>&2' | head -1 | cut -d: -f1)"
VF_DIE_LN="$(printf '%s\n' "$VF_BODY" | grep -nE '^\s*(die |exit ")' | head -1 | cut -d: -f1)"
cases=$((cases + 1))
if [[ -n "$VF_PRINT_LN" && -n "$VF_DIE_LN" && "$VF_PRINT_LN" -lt "$VF_DIE_LN" ]]; then
  ok "pin: verdict_fail prints 'bite-proof FAILED' on stdout (line $VF_PRINT_LN) before it exits (line $VF_DIE_LN)"
else
  bad "pin: verdict_fail must print on stdout before it exits (print=$VF_PRINT_LN exit=$VF_DIE_LN)"
fi

# Pin: the default-mode tail ARMS the cleanup handler (top-level `trap '_wt_cleanup' EXIT`) before
# the first write (`mkdir -p "$TARGET/scripts"`) and DISARMS it (top-level `trap - EXIT INT TERM`)
# after the last prove_bite and before emit_readme — the window every 66..74 / mktemp / set -e
# failure falls inside. Column-0 call forms on a comment-stripped copy; the helper's own (indented)
# trap lines cannot satisfy them.
GEN_NOCOMMENT="$(grep -vE '^\s*#' "$GEN")"
ARM_LN="$(printf '%s\n' "$GEN_NOCOMMENT" | grep -nF "trap '_wt_cleanup' EXIT" | grep -vE '^[0-9]+:\s' | head -1 | cut -d: -f1)"
MKDIR_LN="$(printf '%s\n' "$GEN_NOCOMMENT" | grep -nE '^mkdir -p "\$TARGET/scripts"' | head -1 | cut -d: -f1)"
NC_PB_LN="$(printf '%s\n' "$GEN_NOCOMMENT" | grep -nE '^prove_bite\s*$' | tail -1 | cut -d: -f1)"
DISARM_LN="$(printf '%s\n' "$GEN_NOCOMMENT" | grep -nE '^trap - EXIT INT TERM$' | head -1 | cut -d: -f1)"
NC_ER_LN="$(printf '%s\n' "$GEN_NOCOMMENT" | grep -nE '^emit_readme\s*$' | head -1 | cut -d: -f1)"
cases=$((cases + 1))
if [[ -n "$ARM_LN" && -n "$MKDIR_LN" && -n "$NC_PB_LN" && -n "$DISARM_LN" && -n "$NC_ER_LN" \
      && "$ARM_LN" -lt "$MKDIR_LN" && "$MKDIR_LN" -lt "$NC_PB_LN" && "$NC_PB_LN" -lt "$DISARM_LN" && "$DISARM_LN" -lt "$NC_ER_LN" ]]; then
  ok "pin: cleanup armed ($ARM_LN) < first write ($MKDIR_LN) < prove_bite ($NC_PB_LN) < disarmed ($DISARM_LN) < emit_readme ($NC_ER_LN)"
else
  bad "pin: default-mode cleanup window wrong: arm=$ARM_LN mkdir=$MKDIR_LN prove_bite=$NC_PB_LN disarm=$DISARM_LN emit_readme=$NC_ER_LN (want ascending)"
fi

# Pin: no test seam — the script honours no CONSTRAINT_SCAFFOLD_TEST_* variable.
SEAMS="$(grep -c 'CONSTRAINT_SCAFFOLD_TEST_' "$GEN" || true)"
cases=$((cases + 1))
if [[ "$SEAMS" == "0" ]]; then
  ok "pin: no CONSTRAINT_SCAFFOLD_TEST_ seam in the script"
else
  bad "pin: $SEAMS CONSTRAINT_SCAFFOLD_TEST_ occurrence(s) in the script (must be 0)"
fi

# Pin: prove_bite is called at BOTH mode exits, and the README/pointer emits come AFTER the
# default-mode prove_bite (R1 — written last so the clean-tree guard never sees them).
PB_CALLS="$(grep -cE '^\s*prove_bite\s*(#|$)' "$GEN" || true)"
PB_LAST_LN="$(grep -nE '^\s*prove_bite\s*(#|$)' "$GEN" | tail -1 | cut -d: -f1)"
ER_LN="$(grep -nE '^\s*emit_readme\s*(#|$)' "$GEN" | head -1 | cut -d: -f1)"
EP_LN="$(grep -nE '^\s*emit_pointer\s*(#|$)' "$GEN" | head -1 | cut -d: -f1)"
cases=$((cases + 1))
if [[ "$PB_CALLS" == "2" && -n "$ER_LN" && -n "$EP_LN" && "$PB_LAST_LN" -lt "$ER_LN" && "$ER_LN" -lt "$EP_LN" ]]; then
  ok "pin: prove_bite called twice; emit_readme ($ER_LN) and emit_pointer ($EP_LN) follow the default-mode prove_bite ($PB_LAST_LN)"
else
  bad "pin: prove_bite calls=$PB_CALLS (want 2); prove_bite=$PB_LAST_LN emit_readme=$ER_LN emit_pointer=$EP_LN (want ascending)"
fi

# Pin: the header exit matrix lists 71, 72, 73 and 74.
MATRIX_OK=1
for code in 71 72 73 74; do
  grep -qE "^#   $code  " "$GEN" || MATRIX_OK=0
done
cases=$((cases + 1))
if [[ "$MATRIX_OK" -eq 1 ]]; then
  ok "pin: header exit matrix lists 71/72/73/74"
else
  bad "pin: header exit matrix is missing one of 71/72/73/74"
fi

# Pin: the emitter's strip/substitute expression is the one literal expression the parity suite
# also pins (one transform, two copies).
# Anchored on the ASSIGNMENT form (`content="$(sed …`), so a stale comment quoting the expression
# cannot stand in for the live one.
STRIP_EXPR="sed -e '1{/^<!-- Inspired by /d}' -e \"s|__TARGET_DIR__|\$TARGET_REL|g\""
STRIP_CT="$(grep -E '^\s*content="\$\(sed ' "$GEN" | grep -cF -- "$STRIP_EXPR" || true)"
cases=$((cases + 1))
if [[ "$STRIP_CT" == "1" ]]; then
  ok "pin: the README strip/substitute sed expression appears exactly once, on the content= assignment"
else
  bad "pin: README strip/substitute sed expression on a content= assignment count=$STRIP_CT (want 1)"
fi

# =============================================================================================
# Fixture + stub builders.
# =============================================================================================

# make_repo <name> [opts...] -> prints the fixture repo root. A throwaway git repo carrying an
# apps/web-platform-shaped Next.js app, committed clean, with refs/remotes/origin/main == HEAD so
# the merge-base capture resolves. Options:
#   --no-components     omit components/ (drives the three-dirs precondition, 65)
#   --claude            commit a CLAUDE.md with prior content
#   --agents            commit an AGENTS.md with prior content
#   --readme            commit a server/README.md with prior content
#   --populated         an unrelated "use client" module with a TYPE-ONLY server import plus a
#                       client module value-importing a VALUE-SAFE server module (the direct rule
#                       baselines it; the transitive rule excludes it via pathNot)
#   --claude-symlink    commit CLAUDE.md as a symlink to a file OUTSIDE the repo
make_repo() {
  local name="$1"; shift
  local fx="$TMPROOT/$name"
  assert_fixture_dir "$fx"
  local app="$fx/apps/web-platform"
  local want_components=1 claude=0 agents=0 readme=0 populated=0 claude_symlink=0
  local o
  for o in "$@"; do
    case "$o" in
      --no-components) want_components=0 ;;
      --claude) claude=1 ;;
      --agents) agents=1 ;;
      --readme) readme=1 ;;
      --populated) populated=1 ;;
      --claude-symlink) claude_symlink=1 ;;
      *) echo "make_repo: unknown option $o" >&2; exit 2 ;;
    esac
  done
  mkdir -p "$app/app" "$app/server"
  [[ "$want_components" -eq 1 ]] && mkdir -p "$app/components"
  git -C "$fx" init -q
  git -C "$fx" config user.email "test@example.com"
  git -C "$fx" config user.name "test"
  printf 'node_modules\n' > "$fx/.gitignore"
  printf 'module.exports = {};\n' > "$app/next.config.js"
  printf '{ "name": "fixture", "private": true, "dependencies": { "next": "15.0.0" } }\n' > "$app/package.json"
  cat > "$app/tsconfig.json" <<'JSON'
{
  "compilerOptions": {
    "baseUrl": ".",
    "module": "esnext",
    "moduleResolution": "bundler",
    "jsx": "preserve",
    "paths": { "@/*": ["./*"] }
  },
  "include": ["**/*.ts", "**/*.tsx"],
  "exclude": ["node_modules"]
}
JSON
  printf 'export default function Page() { return null; }\n' > "$app/app/page.tsx"
  printf 'export const APP_NAME = "fixture";\nexport type Shape = { id: string };\n' > "$app/server/config.ts"
  if [[ "$want_components" -eq 1 ]]; then
    printf '"use client";\nexport const Greeting = () => "hello";\n' > "$app/components/greeting.tsx"
  fi
  if [[ "$populated" -eq 1 ]]; then
    printf '"use client";\nimport type { Shape } from "@/server/config";\nexport const Typed = (_: Shape) => null;\n' > "$app/components/typed.tsx"
    printf 'export const LEADERS = ["a"] as const;\n' > "$app/server/domain-leaders.ts"
    printf '"use client";\nimport { LEADERS } from "@/server/domain-leaders";\nexport const Leaders = () => LEADERS;\n' > "$app/components/leaders.tsx"
  fi
  [[ "$claude" -eq 1 ]] && printf '# Fixture project\n\nPrior instructions.\n' > "$fx/CLAUDE.md"
  [[ "$agents" -eq 1 ]] && printf '# Agents\n\nPrior agent notes.\n' > "$fx/AGENTS.md"
  [[ "$readme" -eq 1 ]] && printf '# Server\n\nPrior README prose.\n' > "$app/server/README.md"
  if [[ "$claude_symlink" -eq 1 ]]; then
    mkdir -p "$TMPROOT/elsewhere-$name"
    printf '# Global instructions (must stay untouched)\n' > "$TMPROOT/elsewhere-$name/CLAUDE.md"
    ln -s "$TMPROOT/elsewhere-$name/CLAUDE.md" "$fx/CLAUDE.md"
  fi
  git -C "$fx" add -A
  git -C "$fx" commit -q -m "seed app"
  git -C "$fx" update-ref refs/remotes/origin/main HEAD
  printf '%s' "$fx"
}

# point_node_modules <fixture-root> <node_modules-dir>: (re)point the untracked symlink.
point_node_modules() {
  local fx="$1" nm="$2"
  assert_fixture_dir "$fx"
  rm -f -- "$fx/apps/web-platform/node_modules"
  ln -s "$nm" "$fx/apps/web-platform/node_modules"
}

# make_stub_depcruise <dir> <clean-out> <clean-rc> <probe-out> <probe-rc> [<kill-pid-file>]
# Builds a node_modules-shaped dir whose `.bin/depcruise` implements the three-branch table (D6).
# <clean-out>/<probe-out> are files whose bytes the stub cats on the `err` clean/probe arms. With
# <kill-pid-file>, the `err`-without-probe arm first sends TERM to the pid in that file (the
# pre-probe pass runs after the scaffold's trap is installed; the `baseline` call precedes it).
# Two flag FILES a case may touch in <dir> after building: `stateful` makes the clean arm fail
# (probe bytes + probe rc) once a probe arm has run — a gate that stays red after the revert
# (drives 73); `reach-baseline` makes the `baseline` arm emit a reachability entry, which the
# emitted RUNNER refuses on its pre-probe pass (drives 71 through runner logic, not stub output).
make_stub_depcruise() {
  local dir="$1" clean_out="$2" clean_rc="$3" probe_out="$4" probe_rc="$5" pidfile="${6:-}"
  assert_fixture_dir "$dir"
  mkdir -p "$dir/.bin" "$dir/dependency-cruiser"
  cp "$clean_out" "$dir/clean.out"
  cp "$probe_out" "$dir/probe.out"
  printf '{ "name": "dependency-cruiser", "version": "0.0.0-stub" }\n' > "$dir/dependency-cruiser/package.json"
  : > "$dir/calls.log"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'STUB_DIR=%q\n' "$dir"
    printf 'CLEAN_RC=%q\nPROBE_RC=%q\nPIDFILE=%q\n' "$clean_rc" "$probe_rc" "$pidfile"
    cat <<'STUB'
printf '%s\n' "$*" >> "$STUB_DIR/calls.log"
case " $* " in
  *" --output-type json "*)     printf '{"modules":[]}\n' ;;
  *" --output-type baseline "*)
    if [[ -e "$STUB_DIR/reach-baseline" ]]; then
      printf '[{"type":"reachability","rule":{"name":"no-client-to-server-secret-transitive"}}]\n'
    else
      printf '[]\n'
    fi ;;
  *" --output-type err "*)
    if [[ -e components/__constraint_scaffold_bite_probe__/direct.tsx ]]; then
      touch "$STUB_DIR/probed"
      cat "$STUB_DIR/probe.out"; exit "$PROBE_RC"
    fi
    if [[ -e "$STUB_DIR/stateful" && -e "$STUB_DIR/probed" ]]; then
      cat "$STUB_DIR/probe.out"; exit "$PROBE_RC"
    fi
    if [[ -n "$PIDFILE" && -s "$PIDFILE" ]]; then kill -TERM "$(cat "$PIDFILE")" 2>/dev/null || true; fi
    cat "$STUB_DIR/clean.out"; exit "$CLEAN_RC" ;;
  *) echo "stub depcruise: unhandled argv: $*" >&2; exit 64 ;;
esac
STUB
  } > "$dir/.bin/depcruise"
  chmod +x "$dir/.bin/depcruise"
}

# run_gen <fixture-root> <tag> [args...] -> RC, and stdout/stderr in $TMPROOT/<tag>.out / .err.
# RUN_TMPDIR (optional) is exported as TMPDIR for the scaffold so a leftover mktemp dir is observable.
run_gen() {
  local root="$1" tag="$2"; shift 2
  assert_fixture_dir "$root"
  RC=0
  CONSTRAINT_SCAFFOLD_REPO_ROOT="$root" TMPDIR="${RUN_TMPDIR:-$TMPDIR}" bash "$GEN" "$@" \
    >"$TMPROOT/$tag.out" 2>"$TMPROOT/$tag.err" || RC=$?
}
worktree_count() { git -C "$1" worktree list 2>/dev/null | grep -c . || true; }
porcelain() { git -C "$1" status --porcelain 2>/dev/null || true; }
count_marker() { grep -cF -- "$2" "$1" 2>/dev/null || true; }

# Canned depcruise outputs — copied VERBATIM from the one-hop measurement on a scratch fixture with
# the real toolchain (dependency-cruiser 16.10.4, task 0.5), then edited per case.
CANNED="$TMPROOT/canned"
mkdir -p "$CANNED"
printf '\n\xe2\x9c\x94 no dependency violations found (1 modules, 0 dependencies cruised)\n\n' > "$CANNED/clean.txt"
cat > "$CANNED/real.txt" <<'EOF'

  error no-client-to-server-secret-transitive: components/__constraint_scaffold_bite_probe__/via-hop.tsx → server/__constraint_scaffold_bite_probe__.ts
      components/__constraint_scaffold_bite_probe__/hop.ts →
      server/__constraint_scaffold_bite_probe__.ts
  error no-client-to-server-secret-transitive: components/__constraint_scaffold_bite_probe__/direct.tsx → server/__constraint_scaffold_bite_probe__.ts
      server/__constraint_scaffold_bite_probe__.ts
  error no-client-to-server-secret: components/__constraint_scaffold_bite_probe__/direct.tsx → server/__constraint_scaffold_bite_probe__.ts

x 3 dependency violations (3 errors, 0 warnings). 5 modules, 3 dependencies cruised.
EOF
# S-real-minus-direct-transitive: today's real output minus the direct-edge transitive block (the
# shape a reachability-semantics change would produce). Must still PASS the bite.
cat > "$CANNED/real-minus-direct-transitive.txt" <<'EOF'

  error no-client-to-server-secret-transitive: components/__constraint_scaffold_bite_probe__/via-hop.tsx → server/__constraint_scaffold_bite_probe__.ts
      components/__constraint_scaffold_bite_probe__/hop.ts →
      server/__constraint_scaffold_bite_probe__.ts
  error no-client-to-server-secret: components/__constraint_scaffold_bite_probe__/direct.tsx → server/__constraint_scaffold_bite_probe__.ts

x 2 dependency violations (2 errors, 0 warnings). 5 modules, 3 dependencies cruised.
EOF
# S-direct-only: only the direct-rule line on direct.tsx — the transitive rule is silent.
cat > "$CANNED/direct-only.txt" <<'EOF'

  error no-client-to-server-secret: components/__constraint_scaffold_bite_probe__/direct.tsx → server/__constraint_scaffold_bite_probe__.ts

x 1 dependency violations (1 errors, 0 warnings). 5 modules, 3 dependencies cruised.
EOF
# S-bare-tokens: both rule names and both probe filenames, WITHOUT the `error <rule>: ` call-form.
cat > "$CANNED/bare-tokens.txt" <<'EOF'

  no-client-to-server-secret no-client-to-server-secret-transitive components/__constraint_scaffold_bite_probe__/direct.tsx components/__constraint_scaffold_bite_probe__/via-hop.tsx

x 2 dependency violations (2 errors, 0 warnings). 5 modules, 3 dependencies cruised.
EOF
# S-ansi: today's real output as a FORCE_COLOR environment decorates it (chalk: red `error`, bold
# from-path) — a correct gate whose stream carries escapes. Must still PASS the bite.
sed -e 's/^  error \(no-client-to-server-secret[a-z-]*\): \([^ ]*\)/  \x1b[31merror\x1b[39m \1: \x1b[1m\2\x1b[22m/' "$CANNED/real.txt" > "$CANNED/real-ansi.txt"
# S-preprobe-violation: the CLEAN arm carries a real violation on a non-probe file.
cat > "$CANNED/preprobe-violation.txt" <<'EOF'

  error no-client-to-server-secret: components/other.tsx → server/secret.ts

x 1 dependency violations (1 errors, 0 warnings). 4 modules, 2 dependencies cruised.
EOF

STUB_CLEAN="$TMPROOT/stub-clean"
make_stub_depcruise "$STUB_CLEAN" "$CANNED/clean.txt" 0 "$CANNED/real.txt" 3

# =============================================================================================
# Segment 2 — STUB-DRIVEN (needs node + git, no depcruise — runs in every shard).
# =============================================================================================
echo "# --- stub-driven: S-clean ---"

# --- C2: three-dirs precondition -> 65, nothing emitted ---------------------------------------
FX="$(make_repo c2-nocomponents --no-components)"
assert_fixture_dir "$FX"
point_node_modules "$FX" "$STUB_CLEAN"
run_gen "$FX" c2
cases=$((cases + 1))
if [[ "$RC" == "65" ]]; then
  ok "C2: fixture without components/ exits 65"
else
  bad "C2: expected 65 for a target lacking components/, got rc=$RC"
fi
cases=$((cases + 1))
if [[ ! -e "$FX/apps/web-platform/.dependency-cruiser.cjs" && ! -e "$FX/apps/web-platform/scripts" && -z "$(porcelain "$FX")" ]]; then
  ok "C2: nothing emitted before the precondition (tree clean)"
else
  bad "C2: artifacts present after 65: $(porcelain "$FX")"
fi
cases=$((cases + 1))
if grep -q 'lacks components/ (the emitted runner cruises app/ components/ server/' "$TMPROOT/c2.out"; then
  ok "C2: the 65 message names the MISSING dir and the three required ones on STDOUT"
else
  bad "C2: 65 message not on stdout (stdout: $(head -c 200 "$TMPROOT/c2.out"))"
fi

# --- C3a: CLAUDE.md present -> pointer appended there only; README block emitted -------------
FX_A="$(make_repo c3a-claude --claude)"
assert_fixture_dir "$FX_A"
point_node_modules "$FX_A" "$STUB_CLEAN"
run_gen "$FX_A" c3a
cases=$((cases + 1))
if [[ "$RC" == "0" ]]; then
  ok "C3a: default mode exits 0 under the clean stub"
else
  bad "C3a: expected 0, got rc=$RC (stdout: $(tail -3 "$TMPROOT/c3a.out" | tr '\n' ' ')) (stderr: $(tail -3 "$TMPROOT/c3a.err" | tr '\n' ' '))"
fi
cases=$((cases + 1))
if grep -qE "$VERDICT_RE" "$TMPROOT/c3a.out" && grep -qF 'depcruise=0.0.0-stub' "$TMPROOT/c3a.out"; then
  ok "C3a: verdict line on stdout carries the stub version (read through the node_modules symlink)"
else
  bad "C3a: verdict line missing or wrong version: $(grep -F 'bite-proof' "$TMPROOT/c3a.out" | head -2 | tr '\n' ' ')"
fi
cases=$((cases + 1))
if [[ "$(count_marker "$FX_A/CLAUDE.md" "$POINTER_MARKER")" == "1" && ! -e "$FX_A/AGENTS.md" ]]; then
  ok "C3a: pointer appended to CLAUDE.md exactly once; AGENTS.md not created"
else
  bad "C3a: pointer count=$(count_marker "$FX_A/CLAUDE.md" "$POINTER_MARKER") AGENTS.md exists=$([[ -e "$FX_A/AGENTS.md" ]] && echo yes || echo no)"
fi
cases=$((cases + 1))
if head -1 "$FX_A/CLAUDE.md" | grep -qF '# Fixture project' && grep -qF 'Prior instructions.' "$FX_A/CLAUDE.md"; then
  ok "C3a: prior CLAUDE.md content preserved (append, not replace)"
else
  bad "C3a: prior CLAUDE.md content lost"
fi
POINTER_LINE="$(grep -F -- "$POINTER_MARKER" "$FX_A/CLAUDE.md" | head -1)"
cases=$((cases + 1))
if [[ "$POINTER_LINE" == *"apps/web-platform/server/README.md"* && "$POINTER_LINE" != *"@apps/"* && "$POINTER_LINE" != @* && "$POINTER_LINE" == *"$POINTER_MARKER" ]]; then
  ok "C3a: pointer line is plain prose naming apps/web-platform/server/README.md, no @-import, marker at end"
else
  bad "C3a: pointer line shape wrong: '$POINTER_LINE'"
fi
cases=$((cases + 1))
if [[ "$(count_marker "$FX_A/apps/web-platform/server/README.md" "$README_START")" == "1" && "$(count_marker "$FX_A/apps/web-platform/server/README.md" "$README_END")" == "1" ]]; then
  ok "C3a: README block emitted once (start + end markers)"
else
  bad "C3a: README block markers start=$(count_marker "$FX_A/apps/web-platform/server/README.md" "$README_START") end=$(count_marker "$FX_A/apps/web-platform/server/README.md" "$README_END")"
fi
cases=$((cases + 1))
if [[ -s "$FX_A/apps/web-platform/server/README.md" ]] && ! grep -q 'Inspired by' "$FX_A/apps/web-platform/server/README.md" && ! grep -q '__TARGET_DIR__' "$FX_A/apps/web-platform/server/README.md" && grep -qF 'apps/web-platform' "$FX_A/apps/web-platform/server/README.md"; then
  ok "C3a: emitted README has no attribution line, no __TARGET_DIR__ placeholder, names the target dir"
else
  bad "C3a: emitted README carries the attribution line or an unsubstituted placeholder"
fi
EXPECTED_README="$(sed -e '1{/^<!-- Inspired by /d}' -e "s|__TARGET_DIR__|apps/web-platform|g" "$REF/boundary-readme.template" 2>/dev/null)"
cases=$((cases + 1))
if [[ -n "$EXPECTED_README" ]] && diff -q <(printf '%s\n' "$EXPECTED_README") "$FX_A/apps/web-platform/server/README.md" >/dev/null 2>&1; then
  ok "C3a: emitted README == emitter transform of boundary-readme.template"
else
  bad "C3a: emitted README differs from the template transform"
fi
cases=$((cases + 1))
if [[ -f "$FX_A/apps/web-platform/.dependency-cruiser-known-violations.json" && "$(worktree_count "$FX_A")" == "1" && ! -e "$FX_A/apps/web-platform/$PROBE_DIR" ]]; then
  ok "C3a: baseline present, worktree list clean, no probe dir in the founder tree"
else
  bad "C3a: baseline=$([[ -f "$FX_A/apps/web-platform/.dependency-cruiser-known-violations.json" ]] && echo y || echo n) worktrees=$(worktree_count "$FX_A") probe-dir=$([[ -e "$FX_A/apps/web-platform/$PROBE_DIR" ]] && echo present || echo absent)"
fi
# The README/pointer are written LAST: the clean-tree guard inside baseline capture must never
# see them. Observable: the run exited 0 (a pre-capture write would have produced 67).
cases=$((cases + 1))
if ! grep -q 'working tree is dirty' "$TMPROOT/c3a.err"; then
  ok "C3a: no 67 (README/pointer were not written before the clean-tree guard)"
else
  bad "C3a: clean-tree guard saw an early write (67)"
fi
# The stub recorded the runner's three passes: baseline + (err, json) + err + (err, json).
ERR_CALLS="$(grep -c -- '--output-type err' "$STUB_CLEAN/calls.log" || true)"
cases=$((cases + 1))
if [[ "$ERR_CALLS" -ge 3 ]]; then
  ok "C3a: stub argv log shows >= 3 'err' passes (pass -> fail -> pass) — got $ERR_CALLS"
else
  bad "C3a: stub argv log shows only $ERR_CALLS 'err' passes (want >= 3)"
fi

# --- C4: idempotency — re-install after removing the gate; README block + pointer stay at 1 ----
rm -f -- "$FX_A/apps/web-platform/.dependency-cruiser.cjs" "$FX_A/apps/web-platform/scripts/constraint-gates.sh" \
  "$FX_A/apps/web-platform/.github/workflows/constraint-gates.yml" "$FX_A/apps/web-platform/.github/workflows/fix-constraints-stage-a.yml" \
  "$FX_A/apps/web-platform/.github/workflows/fix-constraints-stage-b.yml" "$FX_A/apps/web-platform/.dependency-cruiser-known-violations.json"
git -C "$FX_A" add -A
git -C "$FX_A" commit -q -m "keep README + pointer, drop the gate"
git -C "$FX_A" update-ref refs/remotes/origin/main HEAD
run_gen "$FX_A" c4
cases=$((cases + 1))
if [[ "$RC" == "0" && "$(count_marker "$FX_A/CLAUDE.md" "$POINTER_MARKER")" == "1" && "$(count_marker "$FX_A/apps/web-platform/server/README.md" "$README_START")" == "1" ]]; then
  ok "C4: second default-mode run (rc=$RC) leaves pointer and README block at exactly 1 each"
else
  bad "C4: rc=$RC pointer=$(count_marker "$FX_A/CLAUDE.md" "$POINTER_MARKER") readme-start=$(count_marker "$FX_A/apps/web-platform/server/README.md" "$README_START")"
fi

# --- C6: commit, then --refresh-baseline -> rc 0, verdict, README/pointer byte-identical --------
git -C "$FX_A" add -A
git -C "$FX_A" commit -q -m "install gate"
git -C "$FX_A" update-ref refs/remotes/origin/main HEAD
cp "$FX_A/CLAUDE.md" "$TMPROOT/c6-claude.before"
cp "$FX_A/apps/web-platform/server/README.md" "$TMPROOT/c6-readme.before"
run_gen "$FX_A" c6 --refresh-baseline
cases=$((cases + 1))
if [[ "$RC" == "0" ]] && grep -qE "$VERDICT_RE" "$TMPROOT/c6.out"; then
  ok "C6: --refresh-baseline exits 0 and prints the verdict line (bite runs in refresh mode too)"
else
  bad "C6: rc=$RC verdict=$(grep -cE "$VERDICT_RE" "$TMPROOT/c6.out" || true) (stderr: $(tail -2 "$TMPROOT/c6.err" | tr '\n' ' '))"
fi
cases=$((cases + 1))
if cmp -s "$FX_A/CLAUDE.md" "$TMPROOT/c6-claude.before" && cmp -s "$FX_A/apps/web-platform/server/README.md" "$TMPROOT/c6-readme.before"; then
  ok "C6: refresh mode touched neither CLAUDE.md nor server/README.md"
else
  bad "C6: refresh mode modified CLAUDE.md or server/README.md"
fi
cases=$((cases + 1))
if [[ "$(worktree_count "$FX_A")" == "1" ]]; then
  ok "C6: worktree list clean after refresh"
else
  bad "C6: $(worktree_count "$FX_A") worktrees registered after refresh"
fi

# --- C3b: only AGENTS.md -> appended there; CLAUDE.md not created --------------------------------
FX="$(make_repo c3b-agents --agents)"
assert_fixture_dir "$FX"
point_node_modules "$FX" "$STUB_CLEAN"
run_gen "$FX" c3b
cases=$((cases + 1))
if [[ "$RC" == "0" && "$(count_marker "$FX/AGENTS.md" "$POINTER_MARKER")" == "1" && ! -e "$FX/CLAUDE.md" ]]; then
  ok "C3b: pointer appended to AGENTS.md once; CLAUDE.md not created (rc=$RC)"
else
  bad "C3b: rc=$RC AGENTS pointer=$(count_marker "$FX/AGENTS.md" "$POINTER_MARKER") CLAUDE.md exists=$([[ -e "$FX/CLAUDE.md" ]] && echo yes || echo no)"
fi
cases=$((cases + 1))
if grep -qF 'Prior agent notes.' "$FX/AGENTS.md"; then
  ok "C3b: prior AGENTS.md content preserved"
else
  bad "C3b: prior AGENTS.md content lost"
fi

# --- C3c: neither -> AGENTS.md created with exactly the one line ---------------------------------
FX="$(make_repo c3c-neither)"
assert_fixture_dir "$FX"
point_node_modules "$FX" "$STUB_CLEAN"
run_gen "$FX" c3c
AGENTS_LINES="$(grep -c . "$FX/AGENTS.md" 2>/dev/null || true)"
cases=$((cases + 1))
if [[ "$RC" == "0" && -f "$FX/AGENTS.md" && "$AGENTS_LINES" == "1" && "$(count_marker "$FX/AGENTS.md" "$POINTER_MARKER")" == "1" && ! -e "$FX/CLAUDE.md" ]]; then
  ok "C3c: AGENTS.md created carrying exactly the pointer line (rc=$RC)"
else
  bad "C3c: rc=$RC AGENTS.md lines=$AGENTS_LINES pointer=$(count_marker "$FX/AGENTS.md" "$POINTER_MARKER")"
fi

# --- C-symlink: CLAUDE.md -> elsewhere: refused, nothing written through the link, rc 0 -----------
FX="$(make_repo csymlink --claude-symlink)"
assert_fixture_dir "$FX"
point_node_modules "$FX" "$STUB_CLEAN"
cp "$TMPROOT/elsewhere-csymlink/CLAUDE.md" "$TMPROOT/csymlink-global.before"
run_gen "$FX" csymlink
cases=$((cases + 1))
if [[ "$RC" == "0" ]] && cmp -s "$TMPROOT/elsewhere-csymlink/CLAUDE.md" "$TMPROOT/csymlink-global.before" && [[ ! -e "$FX/AGENTS.md" ]]; then
  ok "C-symlink: run exits 0; nothing written through the CLAUDE.md symlink; no AGENTS.md fallback"
else
  bad "C-symlink: rc=$RC link-target-changed=$(cmp -s "$TMPROOT/elsewhere-csymlink/CLAUDE.md" "$TMPROOT/csymlink-global.before" && echo no || echo YES) AGENTS.md=$([[ -e "$FX/AGENTS.md" ]] && echo created || echo absent)"
fi
cases=$((cases + 1))
if grep -qiE 'WARNING.*symlink' "$TMPROOT/csymlink.out"; then
  ok "C-symlink: refusal is a WARNING on stdout naming the symlink"
else
  bad "C-symlink: no symlink warning on stdout: $(grep -i warn "$TMPROOT/csymlink.out" | head -1)"
fi
cases=$((cases + 1))
if grep -qE "$VERDICT_RE" "$TMPROOT/csymlink.out" && [[ -f "$FX/apps/web-platform/.dependency-cruiser.cjs" ]]; then
  ok "C-symlink: the gate stayed installed and proven (verdict line present, prose is not the gate)"
else
  bad "C-symlink: gate not installed/proven after the pointer refusal"
fi

# --- C-tmpdir: TMPDIR inside the fixture repo -> 69 before any worktree ---------------------------
FX="$(make_repo ctmpdir)"
assert_fixture_dir "$FX"
point_node_modules "$FX" "$STUB_CLEAN"
mkdir -p "$FX/tmp-inside"
RUN_TMPDIR="$FX/tmp-inside" run_gen "$FX" ctmpdir
cases=$((cases + 1))
if [[ "$RC" == "69" && "$(worktree_count "$FX")" == "1" ]]; then
  ok "C-tmpdir: TMPDIR inside the repo is refused with 69 before any worktree is created"
else
  bad "C-tmpdir: rc=$RC worktrees=$(worktree_count "$FX") (want 69 / 1)"
fi
cases=$((cases + 1))
if [[ -z "$(porcelain "$FX")" && -z "$(ls -A "$FX/tmp-inside" 2>/dev/null)" ]]; then
  ok "C-tmpdir: founder tree clean afterwards (emitted artifacts removed, no mktemp residue inside the repo)"
else
  bad "C-tmpdir: residue after 69: $(porcelain "$FX" | tr '\n' ' ') tmp-inside=[$(ls -A "$FX/tmp-inside" | tr '\n' ' ')]"
fi

# --- C-chmod (non-root): worktree add fails -> 69, no mktemp dir left ----------------------------
if [[ "$(id -u)" != "0" ]]; then
  FX="$(make_repo cchmod)"
  assert_fixture_dir "$FX"
  point_node_modules "$FX" "$STUB_CLEAN"
  mkdir -p "$TMPROOT/cchmod-tmp"
  chmod a-w "$FX/.git"
  RUN_TMPDIR="$TMPROOT/cchmod-tmp" run_gen "$FX" cchmod
  chmod u+w "$FX/.git"
  cases=$((cases + 1))
  if [[ "$RC" == "69" ]]; then
    ok "C-chmod: a failing worktree add exits 69"
  else
    bad "C-chmod: expected 69 when worktree add fails, got rc=$RC"
  fi
  cases=$((cases + 1))
  if [[ -z "$(ls -A "$TMPROOT/cchmod-tmp" 2>/dev/null)" ]]; then
    ok "C-chmod: no mktemp dir left behind (trap installed BEFORE worktree add)"
  else
    bad "C-chmod: mktemp residue after a failed worktree add: $(ls -A "$TMPROOT/cchmod-tmp" | tr '\n' ' ')"
  fi
else
  echo "# C-chmod skipped (running as root: chmod a-w does not block writes)"
fi

echo "# --- stub-driven: per-case stubs ---"

# stub_case <name> <clean-out> <clean-rc> <probe-out> <probe-rc> -> FX, RC, files in $TMPROOT/<name>.*
stub_case() {
  local name="$1"
  local stub="$TMPROOT/stub-$name"
  make_stub_depcruise "$stub" "$2" "$3" "$4" "$5"
  FX="$(make_repo "$name")"
  assert_fixture_dir "$FX"
  point_node_modules "$FX" "$stub"
  run_gen "$FX" "$name"
}

# --- S-direct-only -> 72 (the transitive assertion is live on its own edge) ----------------------
stub_case s-direct-only "$CANNED/clean.txt" 0 "$CANNED/direct-only.txt" 1
cases=$((cases + 1))
if [[ "$RC" == "72" ]]; then
  ok "S-direct-only: only the direct-rule line -> 72"
else
  bad "S-direct-only: expected 72, got rc=$RC"
fi
cases=$((cases + 1))
if grep -qF 'bite-proof FAILED (72)' "$TMPROOT/s-direct-only.out" && grep -qF 'depcruise=0.0.0-stub' "$TMPROOT/s-direct-only.out"; then
  ok "S-direct-only: failure line on STDOUT names the code and the depcruise version"
else
  bad "S-direct-only: stdout lacks 'bite-proof FAILED (72)' + version: $(grep -F FAILED "$TMPROOT/s-direct-only.out" | head -1)"
fi
cases=$((cases + 1))
if grep -qF 'no-client-to-server-secret@direct' "$TMPROOT/s-direct-only.out" && ! grep -qF 'no-client-to-server-secret-transitive@via-hop' "$TMPROOT/s-direct-only.out"; then
  ok "S-direct-only: the failure names which rule WAS seen on its edge (direct) and not the missing one"
else
  bad "S-direct-only: rules-named list wrong: $(grep -F 'rules named' "$TMPROOT/s-direct-only.out" | head -1)"
fi
# S-fail72 (same stub, default mode): the founder tree is as it was.
cases=$((cases + 1))
if [[ -z "$(porcelain "$FX")" ]]; then
  ok "S-fail72: git status --porcelain empty after a 72 in default mode (every emitted artifact removed)"
else
  bad "S-fail72: residue after 72: $(porcelain "$FX" | tr '\n' ' ')"
fi
cases=$((cases + 1))
if [[ ! -e "$FX/apps/web-platform/scripts" && ! -e "$FX/apps/web-platform/.github/workflows" ]]; then
  ok "S-fail72: scripts/ and .github/workflows/ dirs removed (rmdir of the two mkdir -p dirs)"
else
  bad "S-fail72: scripts=$([[ -e "$FX/apps/web-platform/scripts" ]] && echo present || echo gone) workflows=$([[ -e "$FX/apps/web-platform/.github/workflows" ]] && echo present || echo gone)"
fi
cases=$((cases + 1))
if grep -qF 'removed the artifacts this run emitted' "$TMPROOT/s-direct-only.out" && grep -qF 'git worktree prune' "$TMPROOT/s-direct-only.out"; then
  ok "S-fail72: stdout says the artifacts were removed and names 'git worktree prune'"
else
  bad "S-fail72: cleanup message missing on stdout"
fi
cases=$((cases + 1))
if [[ "$(worktree_count "$FX")" == "1" ]]; then
  ok "S-fail72: worktree removed after the failed bite"
else
  bad "S-fail72: $(worktree_count "$FX") worktrees registered after a 72"
fi
cases=$((cases + 1))
if grep -qE '^\s*error no-client-to-server-secret: ' "$TMPROOT/s-direct-only.out"; then
  ok "S-fail72: the captured runner log tail is echoed to stdout as evidence"
else
  bad "S-fail72: no log tail on stdout"
fi

# --- S-lines-rc0 -> 72 (runner stopped failing on rc>0: both lines printed, exit 0) --------------
stub_case s-lines-rc0 "$CANNED/clean.txt" 0 "$CANNED/real.txt" 0
cases=$((cases + 1))
if [[ "$RC" == "72" ]]; then
  ok "S-lines-rc0: both call-form lines but rc 0 -> 72 (the rc check is live)"
else
  bad "S-lines-rc0: expected 72, got rc=$RC"
fi
cases=$((cases + 1))
if grep -qE 'bite-proof FAILED \(72\).*rc=0' "$TMPROOT/s-lines-rc0.out"; then
  ok "S-lines-rc0: failure line reports rc=0"
else
  bad "S-lines-rc0: failure line does not report rc=0: $(grep -F FAILED "$TMPROOT/s-lines-rc0.out" | head -1)"
fi

# --- S-bare-tokens -> 72 (bare rule names + filenames without the call-form) ---------------------
stub_case s-bare-tokens "$CANNED/clean.txt" 0 "$CANNED/bare-tokens.txt" 1
cases=$((cases + 1))
if [[ "$RC" == "72" ]]; then
  ok "S-bare-tokens: bare tokens without 'error <rule>: ' -> 72 (call-form anchored)"
else
  bad "S-bare-tokens: expected 72, got rc=$RC"
fi

# --- S-real-minus-direct-transitive -> verdict, rc 0 ---------------------------------------------
stub_case s-real-minus "$CANNED/clean.txt" 0 "$CANNED/real-minus-direct-transitive.txt" 2
cases=$((cases + 1))
if [[ "$RC" == "0" ]] && grep -qE "$VERDICT_RE" "$TMPROOT/s-real-minus.out"; then
  ok "S-real-minus-direct-transitive: the direct-edge transitive line is neither required nor forbidden (rc=0, verdict)"
else
  bad "S-real-minus-direct-transitive: rc=$RC verdict=$(grep -cE "$VERDICT_RE" "$TMPROOT/s-real-minus.out" || true)"
fi
cases=$((cases + 1))
if grep -qF 'depcruise=0.0.0-stub' "$TMPROOT/s-real-minus.out"; then
  ok "S-real-minus-direct-transitive: verdict version read through the symlink chain (0.0.0-stub)"
else
  bad "S-real-minus-direct-transitive: verdict does not carry the stub version"
fi

# --- S-preprobe-violation -> 74 naming the file ----------------------------------------------------
stub_case s-preprobe "$CANNED/preprobe-violation.txt" 1 "$CANNED/real.txt" 3
cases=$((cases + 1))
if [[ "$RC" == "74" ]]; then
  ok "S-preprobe-violation: a real violation on the clean pass -> 74 (not 71)"
else
  bad "S-preprobe-violation: expected 74, got rc=$RC"
fi
cases=$((cases + 1))
if grep -qF 'bite-proof FAILED (74)' "$TMPROOT/s-preprobe.out" && grep -qF 'components/other.tsx' "$TMPROOT/s-preprobe.out"; then
  ok "S-preprobe-violation: stdout lists the violating file (components/other.tsx)"
else
  bad "S-preprobe-violation: stdout does not list the file: $(grep -F FAILED "$TMPROOT/s-preprobe.out" | head -1)"
fi
cases=$((cases + 1))
if grep -qE '1 real client->server-secret violation' "$TMPROOT/s-preprobe.out"; then
  ok "S-preprobe-violation: the count of violations is reported"
else
  bad "S-preprobe-violation: violation count missing"
fi
cases=$((cases + 1))
if [[ -z "$(porcelain "$FX")" ]]; then
  ok "S-preprobe-violation: default-mode 74 also leaves the tree clean"
else
  bad "S-preprobe-violation: residue after 74: $(porcelain "$FX" | tr '\n' ' ')"
fi

# --- S-term: stub TERMs the scaffold during the pre-probe pass -> 143, cleanup, one worktree -----
STUB_TERM="$TMPROOT/stub-term"
PIDFILE="$TMPROOT/s-term.pid"
: > "$PIDFILE"
make_stub_depcruise "$STUB_TERM" "$CANNED/clean.txt" 0 "$CANNED/real.txt" 3 "$PIDFILE"
FX="$(make_repo s-term)"
assert_fixture_dir "$FX"
point_node_modules "$FX" "$STUB_TERM"
mkdir -p "$TMPROOT/s-term-tmp"
CONSTRAINT_SCAFFOLD_REPO_ROOT="$FX" TMPDIR="$TMPROOT/s-term-tmp" bash "$GEN" >"$TMPROOT/s-term.out" 2>"$TMPROOT/s-term.err" &
TERM_PID=$!
printf '%s' "$TERM_PID" > "$PIDFILE"
RC=0
wait "$TERM_PID" || RC=$?
cases=$((cases + 1))
if [[ "$RC" == "143" ]]; then
  ok "S-term: TERM during the pre-probe pass exits 143"
else
  bad "S-term: expected 143, got rc=$RC (stdout: $(tail -2 "$TMPROOT/s-term.out" | tr '\n' ' '))"
fi
cases=$((cases + 1))
if grep -qF 'interrupted; removed:' "$TMPROOT/s-term.out"; then
  ok "S-term: stdout carries the 'interrupted; removed: <list>' line"
else
  bad "S-term: no 'interrupted; removed:' line on stdout"
fi
cases=$((cases + 1))
if [[ "$(worktree_count "$FX")" == "1" && -z "$(porcelain "$FX")" ]]; then
  ok "S-term: one worktree registered, git status --porcelain empty"
else
  bad "S-term: worktrees=$(worktree_count "$FX") porcelain=[$(porcelain "$FX" | tr '\n' ' ')]"
fi
cases=$((cases + 1))
if [[ -z "$(ls -A "$TMPROOT/s-term-tmp" 2>/dev/null)" ]]; then
  ok "S-term: no leftover mktemp dir"
else
  bad "S-term: mktemp residue: $(ls -A "$TMPROOT/s-term-tmp" | tr '\n' ' ')"
fi
cases=$((cases + 1))
if grep -q -- '--output-type baseline' "$STUB_TERM/calls.log" && grep -q -- '--output-type err' "$STUB_TERM/calls.log"; then
  ok "S-term: the stub saw the baseline call and then the err call that delivered the TERM"
else
  bad "S-term: stub argv log unexpected: $(tr '\n' '|' < "$STUB_TERM/calls.log")"
fi

# --- S-ansi: ANSI-decorated real output on the probe arm -> still PASSES (the anchors read a
# stripped stream; the runner exports NO_COLOR=1 as the first line of defence) ---------------------
stub_case s-ansi "$CANNED/clean.txt" 0 "$CANNED/real-ansi.txt" 3
cases=$((cases + 1))
if [[ "$RC" == "0" ]] && grep -qE "$VERDICT_RE" "$TMPROOT/s-ansi.out"; then
  ok "S-ansi: colour-decorated \`error <rule>:\` lines still satisfy both anchors (rc 0, verdict line present)"
else
  bad "S-ansi: rc=$RC verdict=$(grep -cE "$VERDICT_RE" "$TMPROOT/s-ansi.out" || true) — an ANSI-decorated stream must not read as 72 (stdout: $(grep -F FAILED "$TMPROOT/s-ansi.out" | head -1))"
fi

# --- S-73: the gate stays red after the revert -> 73, tree clean ---------------------------------
STUB_73="$TMPROOT/stub-s-73"
make_stub_depcruise "$STUB_73" "$CANNED/clean.txt" 0 "$CANNED/real.txt" 3
touch "$STUB_73/stateful"
FX="$(make_repo s-73)"
assert_fixture_dir "$FX"
point_node_modules "$FX" "$STUB_73"
run_gen "$FX" s-73
cases=$((cases + 1))
if [[ "$RC" == "73" ]] && grep -qF 'bite-proof FAILED (73)' "$TMPROOT/s-73.out"; then
  ok "S-73: a gate that does not return to green after the probes are removed exits 73 (verdict on stdout)"
else
  bad "S-73: expected 73 + stdout verdict, got rc=$RC (stdout: $(grep -F FAILED "$TMPROOT/s-73.out" | head -1))"
fi
cases=$((cases + 1))
if [[ -z "$(porcelain "$FX")" ]]; then
  ok "S-73: default-mode 73 leaves the tree clean"
else
  bad "S-73: residue after 73: $(porcelain "$FX" | tr '\n' ' ')"
fi

# --- S-71: the emitted RUNNER refuses a reachability baseline entry on the pre-probe pass -> 71 ---
# (Runner logic, not stub bytes: the only stub shape that distinguishes "ran the emitted runner"
# from "called depcruise directly with the runner's argv".)
STUB_71="$TMPROOT/stub-s-71"
make_stub_depcruise "$STUB_71" "$CANNED/clean.txt" 0 "$CANNED/real.txt" 3
touch "$STUB_71/reach-baseline"
FX="$(make_repo s-71)"
assert_fixture_dir "$FX"
point_node_modules "$FX" "$STUB_71"
run_gen "$FX" s-71
cases=$((cases + 1))
if [[ "$RC" == "71" ]] && grep -qF 'bite-proof FAILED (71)' "$TMPROOT/s-71.out" && grep -qF 'suppress the transitive rule' "$TMPROOT/s-71.out"; then
  ok "S-71: the runner's own pre-probe refusal surfaces as 71 with the runner's reason in the stdout log tail"
else
  bad "S-71: expected 71 + runner reason on stdout, got rc=$RC (stdout: $(grep -F FAILED "$TMPROOT/s-71.out" | head -1))"
fi
cases=$((cases + 1))
if [[ -z "$(porcelain "$FX")" ]]; then
  ok "S-71: default-mode 71 leaves the tree clean"
else
  bad "S-71: residue after 71: $(porcelain "$FX" | tr '\n' ' ')"
fi

# --- S-int130: the runner exits 130 (terminal Ctrl-C reached the node child) -> treated as an
# interrupt, never as a 71/72 verdict; cleanup; exit 130 ----------------------------------------------
stub_case s-int130 "$CANNED/clean.txt" 130 "$CANNED/real.txt" 3
cases=$((cases + 1))
if [[ "$RC" == "130" ]] && grep -qF 'interrupted; removed:' "$TMPROOT/s-int130.out" && ! grep -qF 'bite-proof FAILED' "$TMPROOT/s-int130.out"; then
  ok "S-int130: runner rc 130 exits 130 with the interrupted line and NO verdict"
else
  bad "S-int130: rc=$RC (want 130) stdout: $(tail -2 "$TMPROOT/s-int130.out" | tr '\n' ' ')"
fi
cases=$((cases + 1))
if [[ -z "$(porcelain "$FX")" && "$(worktree_count "$FX")" == "1" ]]; then
  ok "S-int130: tree clean, no worktree left registered"
else
  bad "S-int130: porcelain=[$(porcelain "$FX" | tr '\n' ' ')] worktrees=$(worktree_count "$FX")"
fi

# --- S-noorigin: neither origin/main nor origin/HEAD -> 69 BEFORE any write; re-run is not 66 ------
FX="$(make_repo s-noorigin)"
assert_fixture_dir "$FX"
point_node_modules "$FX" "$STUB_CLEAN"
git -C "$FX" update-ref -d refs/remotes/origin/main
run_gen "$FX" s-noorigin
cases=$((cases + 1))
if [[ "$RC" == "69" ]] && grep -qF 'FAILED (69): no origin/main and no origin/HEAD' "$TMPROOT/s-noorigin.out"; then
  ok "S-noorigin: no base ref exits 69 with the fetch instruction on STDOUT"
else
  bad "S-noorigin: rc=$RC (want 69) stdout: $(tail -2 "$TMPROOT/s-noorigin.out" | tr '\n' ' ')"
fi
cases=$((cases + 1))
if [[ -z "$(porcelain "$FX")" && ! -e "$FX/apps/web-platform/scripts" ]]; then
  ok "S-noorigin: nothing was written (porcelain empty, no scripts/ dir)"
else
  bad "S-noorigin: residue after 69: $(porcelain "$FX" | tr '\n' ' ')"
fi
run_gen "$FX" s-noorigin-2
cases=$((cases + 1))
if [[ "$RC" == "69" ]]; then
  ok "S-noorigin: the re-run is the same 69, not a 66 on a half-installed gate"
else
  bad "S-noorigin: re-run rc=$RC (want 69; 66 means a half-installed gate was left behind)"
fi

# --- S-originhead: a founder repo on master (origin/HEAD -> origin/master, no origin/main) -> 0 ---
FX="$(make_repo s-originhead)"
assert_fixture_dir "$FX"
point_node_modules "$FX" "$STUB_CLEAN"
git -C "$FX" update-ref refs/remotes/origin/master HEAD
git -C "$FX" update-ref -d refs/remotes/origin/main
git -C "$FX" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/master
run_gen "$FX" s-originhead
cases=$((cases + 1))
if [[ "$RC" == "0" ]] && grep -qF 'against origin/master merge-base' "$TMPROOT/s-originhead.err"; then
  ok "S-originhead: falls back to the remote default branch (origin/master) and completes"
else
  bad "S-originhead: rc=$RC (want 0) stderr: $(grep -F 'merge-base' "$TMPROOT/s-originhead.err" | head -1)"
fi

# --- S-mktemp: TMPDIR that does not exist -> mktemp fails -> 69, tree clean (not a raw set -e abort) --
FX="$(make_repo s-mktemp)"
assert_fixture_dir "$FX"
point_node_modules "$FX" "$STUB_CLEAN"
RUN_TMPDIR="$TMPROOT/does-not-exist/nested" run_gen "$FX" s-mktemp
cases=$((cases + 1))
if [[ "$RC" == "69" ]] && grep -qF 'FAILED (69): cannot create a temp dir' "$TMPROOT/s-mktemp.out"; then
  ok "S-mktemp: an unusable TMPDIR exits 69 with the cause on STDOUT"
else
  bad "S-mktemp: rc=$RC (want 69) stdout: $(tail -2 "$TMPROOT/s-mktemp.out" | tr '\n' ' ')"
fi
cases=$((cases + 1))
if [[ -z "$(porcelain "$FX")" && ! -e "$FX/apps/web-platform/scripts" ]]; then
  ok "S-mktemp: every emitted artifact removed (the cleanup was armed before the first write)"
else
  bad "S-mktemp: residue after 69: $(porcelain "$FX" | tr '\n' ' ')"
fi

# --- S-symlink-server: server/ is a committed symlink to a dir OUTSIDE the repo -> the bite refuses
# to write probes through it (71), tree clean, external dir untouched ---------------------------------
FX="$(make_repo s-symlink-server)"
assert_fixture_dir "$FX"
point_node_modules "$FX" "$STUB_CLEAN"
mkdir -p "$TMPROOT/ext-server"
printf 'export const X = 1;\n' > "$TMPROOT/ext-server/config.ts"
rm -rf -- "$FX/apps/web-platform/server"
ln -s "$TMPROOT/ext-server" "$FX/apps/web-platform/server"
git -C "$FX" add -A && git -C "$FX" commit -q -m "server as symlink" && git -C "$FX" update-ref refs/remotes/origin/main HEAD
run_gen "$FX" s-symlink-server
cases=$((cases + 1))
if [[ "$RC" == "71" ]] && grep -qF 'server is a symlink' "$TMPROOT/s-symlink-server.out"; then
  ok "S-symlink-server: probes are never written through a symlinked server/ (71, reason on stdout)"
else
  bad "S-symlink-server: rc=$RC (want 71) stdout: $(grep -F FAILED "$TMPROOT/s-symlink-server.out" | head -1)"
fi
cases=$((cases + 1))
if [[ -z "$(porcelain "$FX")" && "$(ls -A "$TMPROOT/ext-server" | tr '\n' ' ')" == "config.ts " ]]; then
  ok "S-symlink-server: tree clean and the external directory holds only its own file"
else
  bad "S-symlink-server: porcelain=[$(porcelain "$FX" | tr '\n' ' ')] ext=[$(ls -A "$TMPROOT/ext-server" | tr '\n' ' ')]"
fi

# --- locate (or install) the dependency-cruiser binary -----------------------
# Fast path: the installed web-platform binary (present locally + in the
# test-webplat CI shard). Fallback: the test-scripts shard has node+npm but no
# web-platform deps, so install dependency-cruiser on demand into a temp dir.
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
REAL_VERSION="$(node -p 'require(process.argv[1] + "/dependency-cruiser/package.json").version' "$NODE_MODULES" 2>/dev/null || true)"

# --- Toolchain probe: can this depcruise actually PARSE the .tsx fixtures? -----
# Same probe as boundary.test.sh: when depcruise parses ZERO modules from a fixture that
# demonstrably contains .tsx client files, the TOOLCHAIN is the problem, not the gate — SKIP
# cleanly (exit 0). Everything above this point is toolchain-FREE and carries its own floor.
PROBE_FX="$(make_repo toolchain-probe --populated)"
assert_fixture_dir "$PROBE_FX"
point_node_modules "$PROBE_FX" "$NODE_MODULES"
cp "$REF/depcruise-config.template" "$PROBE_FX/apps/web-platform/.dependency-cruiser.cjs"
PARSED_COMPONENTS="$( cd "$PROBE_FX/apps/web-platform" && "$DEPCRUISE" --config .dependency-cruiser.cjs --output-type json components server 2>/dev/null | node -e '
  let s=""; process.stdin.on("data",d=>s+=d); process.stdin.on("end",()=>{
    let n=0; try { const j=JSON.parse(s);
      for (const m of j.modules||[]) if (/^components\//.test(m.source||"")) n++;
    } catch(e){ n=0; } process.stdout.write(String(n)); });' 2>/dev/null )"
if ! [[ "$PARSED_COMPONENTS" =~ ^[0-9]+$ ]] || [[ "$PARSED_COMPONENTS" -lt 1 ]]; then
  echo "SKIP: depcruise parsed 0 component modules from the .tsx fixtures — toolchain"
  echo "      unavailable in this shard. The bite-proof is validated end-to-end by the"
  echo "      real-toolchain cases in the test-webplat shard + local runs."
  # This `exit 0` is a SECOND clean-exit door, so the trailer's conservation check and floor
  # are repeated here rather than referenced: a guarantee that only guards one of two exits is
  # not a guarantee. Everything above this point is toolchain-FREE and runs in EVERY shard, so
  # it carries its own floor. Conservation FIRST (ADR-193 #4), both reported directly.
  if [[ $((pass + fail)) -ne "$cases" ]]; then
    printf '\n[FATAL] accounting: pass+fail (%d) != cases (%d).\n' "$((pass + fail))" "$cases" >&2
    if [[ $((pass + fail)) -lt "$cases" ]]; then
      printf '  An assertion was counted but its verdict was not recorded — that is what a neutered ok()/bad() looks like.\n' >&2
    else
      printf '  A verdict was recorded at a call site with no `cases=$((cases + 1))` before it. This is a harness bug, not a product failure: add the increment at that call site.\n' >&2
    fi
    echo "bite-proof.test.sh: $pass passed, $fail failed ($cases assertions, SKIPPED at the toolchain probe)"
    exit 1
  fi
  TOOLCHAIN_FREE_MIN_ASSERTIONS=73
  if [[ "$cases" -lt "$TOOLCHAIN_FREE_MIN_ASSERTIONS" ]]; then
    printf '\n[FATAL] anti-vacuity floor (toolchain-free half): only %d assertion(s) ran, expected >= %d.\n' \
      "$cases" "$TOOLCHAIN_FREE_MIN_ASSERTIONS" >&2
    printf '  Arms were deleted or skipped before the toolchain probe; skipping the depcruise half is sanctioned, asserting nothing at all is not.\n' >&2
    echo "bite-proof.test.sh: $pass passed, $fail failed ($cases assertions, SKIPPED at the toolchain probe)"
    exit 1
  fi
  echo "bite-proof.test.sh: $pass passed, $fail failed ($cases assertions, SKIPPED at the toolchain probe)"
  [[ "$fail" -eq 0 ]]
  exit
fi

# =============================================================================================
# Segment 3 — REAL TOOLCHAIN.
# =============================================================================================
echo "# --- real toolchain (dependency-cruiser $REAL_VERSION) ---"

# --- C1: default mode, full run against the real depcruise ----------------------------------------
FX="$(make_repo c1-real --claude)"
assert_fixture_dir "$FX"
point_node_modules "$FX" "$NODE_MODULES"
run_gen "$FX" c1
cases=$((cases + 1))
if [[ "$RC" == "0" ]]; then
  ok "C1: default mode exits 0 with the real toolchain"
else
  bad "C1: expected 0, got rc=$RC (stdout: $(tail -3 "$TMPROOT/c1.out" | tr '\n' ' ')) (stderr: $(tail -3 "$TMPROOT/c1.err" | tr '\n' ' '))"
fi
# C1-color: the same run with FORCE_COLOR=1 in the environment (some CI images, some shells set
# it) — the real depcruise decorates its `error <rule>:` lines; the runner's NO_COLOR=1 plus the
# scaffold's strip must keep this a pass, never a 72 that rolls a correct install back.
FX_COLOR="$(make_repo c1-color)"
assert_fixture_dir "$FX_COLOR"
point_node_modules "$FX_COLOR" "$NODE_MODULES"
FORCE_COLOR=1 run_gen "$FX_COLOR" c1-color
cases=$((cases + 1))
if [[ "$RC" == "0" ]] && grep -qE "$VERDICT_RE" "$TMPROOT/c1-color.out"; then
  ok "C1-color: FORCE_COLOR=1 in the environment still proves the bite (rc 0, verdict line)"
else
  bad "C1-color: rc=$RC verdict=$(grep -cE "$VERDICT_RE" "$TMPROOT/c1-color.out" || true) (stdout: $(grep -F FAILED "$TMPROOT/c1-color.out" | head -1))"
fi
C1_VERDICT="$(grep -E "$VERDICT_RE" "$TMPROOT/c1.out" | head -1)"
cases=$((cases + 1))
if [[ -n "$C1_VERDICT" && "$C1_VERDICT" == *"${RULE_DIRECT}@direct"* && "$C1_VERDICT" == *"${RULE_TRANSITIVE}@via-hop"* ]]; then
  ok "C1: verdict line names both rules on their edges: $C1_VERDICT"
else
  bad "C1: verdict line missing or malformed: $(grep -F 'bite-proof' "$TMPROOT/c1.out" | head -1)"
fi
C1_VER="${C1_VERDICT##*depcruise=}"
cases=$((cases + 1))
if [[ -n "$REAL_VERSION" && "$C1_VER" == "$REAL_VERSION" && "$C1_VER" != "0.0.0-stub" && "$C1_VER" =~ ^[0-9]+\. ]]; then
  ok "C1: depcruise=$C1_VER equals the real dependency-cruiser/package.json version (not the stub)"
else
  bad "C1: verdict version '$C1_VER' != real '$REAL_VERSION' (or looks like the stub)"
fi
cases=$((cases + 1))
if [[ "$(count_marker "$FX/apps/web-platform/server/README.md" "$README_START")" == "1" && "$(count_marker "$FX/CLAUDE.md" "$POINTER_MARKER")" == "1" ]]; then
  ok "C1: README block once, pointer once"
else
  bad "C1: readme-start=$(count_marker "$FX/apps/web-platform/server/README.md" "$README_START") pointer=$(count_marker "$FX/CLAUDE.md" "$POINTER_MARKER")"
fi
cases=$((cases + 1))
if [[ -f "$FX/apps/web-platform/.dependency-cruiser-known-violations.json" ]] && node -e 'const b=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")); process.exit(Array.isArray(b)?0:1)' "$FX/apps/web-platform/.dependency-cruiser-known-violations.json"; then
  ok "C1: baseline present and a JSON array"
else
  bad "C1: baseline missing or not a JSON array"
fi
cases=$((cases + 1))
if [[ "$(worktree_count "$FX")" == "1" && ! -e "$FX/apps/web-platform/$PROBE_DIR" && ! -e "$FX/apps/web-platform/server/__constraint_scaffold_bite_probe__.ts" ]]; then
  ok "C1: worktree list clean; no probe file in the founder tree"
else
  bad "C1: worktrees=$(worktree_count "$FX") probe residue=$(ls -d "$FX/apps/web-platform/$PROBE_DIR" "$FX/apps/web-platform/server/__constraint_scaffold_bite_probe__.ts" 2>/dev/null | tr '\n' ' ')"
fi
# The emitted gate is green on the founder tree afterwards (the runner's own invocation).
C1_GATE_RC=0
CONSTRAINT_GATES_DIR="$FX/apps/web-platform" bash "$FX/apps/web-platform/scripts/constraint-gates.sh" >"$TMPROOT/c1-gate.log" 2>&1 || C1_GATE_RC=$?
cases=$((cases + 1))
if [[ "$C1_GATE_RC" -eq 0 ]]; then
  ok "C1: the emitted runner is green on the founder tree after install"
else
  bad "C1: emitted runner rc=$C1_GATE_RC on the founder tree: $(tail -2 "$TMPROOT/c1-gate.log" | tr '\n' ' ')"
fi

# --- C8: populated tree (harness row d) ----------------------------------------------------------
# An unrelated "use client" module with a TYPE-ONLY server import, plus a client module
# value-importing a VALUE-SAFE server module: the direct rule baselines it (one `dependency`
# entry captured at the merge-base), the transitive rule excludes it via pathNot, and the bite
# must still report pass -> fail(both) -> pass on top of that baseline.
FX="$(make_repo c8-populated --populated)"
assert_fixture_dir "$FX"
point_node_modules "$FX" "$NODE_MODULES"
run_gen "$FX" c8
cases=$((cases + 1))
if [[ "$RC" == "0" ]] && grep -qE "$VERDICT_RE" "$TMPROOT/c8.out"; then
  ok "C8: populated tree -> rc 0 with the verdict line"
else
  bad "C8: rc=$RC verdict=$(grep -cE "$VERDICT_RE" "$TMPROOT/c8.out" || true) (stdout: $(grep -F FAILED "$TMPROOT/c8.out" | head -1))"
fi
C8_DEP_CT="$(node -e 'const b=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")); process.stdout.write(String((Array.isArray(b)?b:[]).filter(e=>e&&e.type==="dependency").length))' "$FX/apps/web-platform/.dependency-cruiser-known-violations.json" 2>/dev/null || echo -1)"
C8_REACH_CT="$(node -e 'const b=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")); process.stdout.write(String((Array.isArray(b)?b:[]).filter(e=>e&&e.type==="reachability").length))' "$FX/apps/web-platform/.dependency-cruiser-known-violations.json" 2>/dev/null || echo -1)"
cases=$((cases + 1))
if [[ "$C8_DEP_CT" == "1" && "$C8_REACH_CT" == "0" ]]; then
  ok "C8: baseline carries exactly one direct value-safe entry and zero reachability entries"
else
  bad "C8: baseline dependency entries=$C8_DEP_CT reachability entries=$C8_REACH_CT (want 1 / 0)"
fi

# --- C-e: committed CLAUDE.md + server/README.md (harness row e — the P0 fixture) ----------------
FX="$(make_repo ce-instructions --claude --readme)"
assert_fixture_dir "$FX"
point_node_modules "$FX" "$NODE_MODULES"
run_gen "$FX" ce
cases=$((cases + 1))
if [[ "$RC" == "0" ]]; then
  ok "C-e: default mode succeeds with a committed CLAUDE.md and server/README.md (no 67)"
else
  bad "C-e: rc=$RC (stderr: $(tail -2 "$TMPROOT/ce.err" | tr '\n' ' '))"
fi
cases=$((cases + 1))
if [[ "$(count_marker "$FX/apps/web-platform/server/README.md" "$README_START")" == "1" && "$(count_marker "$FX/CLAUDE.md" "$POINTER_MARKER")" == "1" ]] \
   && grep -qF 'Prior README prose.' "$FX/apps/web-platform/server/README.md" && grep -qF 'Prior instructions.' "$FX/CLAUDE.md"; then
  ok "C-e: appended once to each, prior content intact"
else
  bad "C-e: readme-start=$(count_marker "$FX/apps/web-platform/server/README.md" "$README_START") pointer=$(count_marker "$FX/CLAUDE.md" "$POINTER_MARKER")"
fi
# Both committed files lacked no trailing newline; check the append started on its own line.
cases=$((cases + 1))
if grep -qE "^$README_START\$" "$FX/apps/web-platform/server/README.md" && grep -qE "^The client/server import boundary.*$POINTER_MARKER\$" "$FX/CLAUDE.md"; then
  ok "C-e: each appended block starts on its own line"
else
  bad "C-e: an append landed mid-line"
fi
# Re-running refresh after committing must be a no-op on both prose files.
git -C "$FX" add -A
git -C "$FX" commit -q -m "install gate"
git -C "$FX" update-ref refs/remotes/origin/main HEAD
cp "$FX/CLAUDE.md" "$TMPROOT/ce-claude.before"
run_gen "$FX" ce-refresh --refresh-baseline
cases=$((cases + 1))
if [[ "$RC" == "0" ]] && cmp -s "$FX/CLAUDE.md" "$TMPROOT/ce-claude.before" && grep -qE "$VERDICT_RE" "$TMPROOT/ce-refresh.out"; then
  ok "C-e: --refresh-baseline afterwards is rc 0 with the verdict and leaves CLAUDE.md untouched"
else
  bad "C-e: refresh rc=$RC claude-changed=$(cmp -s "$FX/CLAUDE.md" "$TMPROOT/ce-claude.before" && echo no || echo YES)"
fi

# --- C-warn: committed config with the transitive rule at severity "warn" -> 72 (real) -----------
FX="$(make_repo cwarn)"
assert_fixture_dir "$FX"
point_node_modules "$FX" "$NODE_MODULES"
mkdir -p "$FX/apps/web-platform/scripts"
node -e '
  const fs=require("fs"); let s=fs.readFileSync(process.argv[1],"utf8");
  const i=s.indexOf("name: \"no-client-to-server-secret-transitive\"");
  const j=s.indexOf("severity: \"error\"", i);
  if (i<0||j<0) process.exit(3);
  s=s.slice(0,j)+"severity: \"warn\""+s.slice(j+"severity: \"error\"".length);
  fs.writeFileSync(process.argv[2], s);' "$REF/depcruise-config.template" "$FX/apps/web-platform/.dependency-cruiser.cjs"
cp "$REF/shared-runner.template" "$FX/apps/web-platform/scripts/constraint-gates.sh"
chmod +x "$FX/apps/web-platform/scripts/constraint-gates.sh"
printf '[]\n' > "$FX/apps/web-platform/.dependency-cruiser-known-violations.json"
git -C "$FX" add -A
git -C "$FX" commit -q -m "gate with the transitive rule softened to warn"
git -C "$FX" update-ref refs/remotes/origin/main HEAD
run_gen "$FX" cwarn --refresh-baseline
cases=$((cases + 1))
if [[ "$RC" == "72" ]]; then
  ok "C-warn: a 'warn' transitive line is rejected by the '^\\s*error ' anchor -> 72 with the real toolchain"
else
  bad "C-warn: expected 72, got rc=$RC (stdout: $(grep -F 'bite-proof' "$TMPROOT/cwarn.out" | head -1))"
fi
cases=$((cases + 1))
if grep -qE '^\s*warn no-client-to-server-secret-transitive: .*via-hop\.tsx' "$TMPROOT/cwarn.out"; then
  ok "C-warn: the echoed log tail shows the 'warn' call-form on via-hop.tsx (the real output shape)"
else
  bad "C-warn: log tail does not show the warn line"
fi
cases=$((cases + 1))
if grep -qF 'refresh mode' "$TMPROOT/cwarn.out" && [[ -f "$FX/apps/web-platform/.dependency-cruiser.cjs" && -f "$FX/apps/web-platform/scripts/constraint-gates.sh" ]]; then
  ok "C-warn: refresh mode removes nothing (artifacts are committed) and says the baseline was rewritten"
else
  bad "C-warn: refresh-mode failure message or artifacts wrong"
fi
cases=$((cases + 1))
if [[ "$(worktree_count "$FX")" == "1" ]]; then
  ok "C-warn: worktree removed after the failed bite"
else
  bad "C-warn: $(worktree_count "$FX") worktrees registered"
fi

echo "---"

# --- Accounting conservation (ADR-193 #3) --------------------------------------------------
# Ordered BEFORE the floor (ADR-193 #4): a neutered bad()/ok() deflates the verdict counters, so
# the floor below would ALSO trip and would report the misleading "arms were deleted". This says
# "a verdict was discarded" instead. Reported with `printf >&2` + `exit 1` DIRECTLY, never
# through bad(): a check that reports by calling the verdict helper increments the very counter
# the exit status reads, so neutering bad() silences the rows AND the check meant to notice the
# silence. Every assertion records exactly one verdict, so pass+fail MUST equal cases; because
# `cases` moves at the CALL SITE and not inside the verdict helpers, the identity is a real
# constraint rather than a tautology. The literal `[FATAL] accounting` is load-bearing —
# guard-vacuity-floor's ARM 10 builds its conservation population by grepping that exact string.
if [[ $((pass + fail)) -ne "$cases" ]]; then
  printf '\n[FATAL] accounting: pass+fail (%d) != cases (%d).\n' "$((pass + fail))" "$cases" >&2
  if [[ $((pass + fail)) -lt "$cases" ]]; then
    printf '  An assertion was counted but its verdict was not recorded — that is what a neutered ok()/bad() looks like.\n' >&2
  else
    printf '  A verdict was recorded at a call site with no `cases=$((cases + 1))` before it. This is a harness bug, not a product failure: add the increment at that call site.\n' >&2
  fi
  echo "bite-proof.test.sh: $pass passed, $fail failed ($cases assertions)"
  exit 1
fi

# --- Anti-vacuity floor (ADR-193 #1) -------------------------------------------------------
# Reads the INDEPENDENT `cases` counter, and reports with `printf >&2` + `exit 1` DIRECTLY.
# A harness that silently asserted nothing (a fixture generator that no-ops, an editing slip that
# drops a block) would otherwise print a clean smaller total and exit 0. See MIN_ASSERTIONS above
# for how the number is derived and when to ratchet it.
MIN_ASSERTIONS=91
if [[ "$cases" -lt "$MIN_ASSERTIONS" ]]; then
  printf '\n[FATAL] anti-vacuity floor: only %d assertion(s) ran, expected >= %d.\n' \
    "$cases" "$MIN_ASSERTIONS" >&2
  printf '  Arms were deleted or skipped; a green run here would be a coverage loss.\n' >&2
  echo "bite-proof.test.sh: $pass passed, $fail failed ($cases assertions)"
  exit 1
fi

echo "bite-proof.test.sh: $pass passed, $fail failed ($cases assertions)"
[[ "$fail" -eq 0 ]]
