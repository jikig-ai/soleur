# shellcheck shell=bash
# shellcheck disable=SC2034  # the override arrays are consumed by files that SOURCE this one
#   (scripts/test-all.sh, scripts/lib/test-suite-lanes.test.sh); shellcheck analyses one file
#   at a time and cannot see a cross-file consumer.
# test-suite-lanes.sh — per-suite concurrency-lane declarations for
# scripts/test-all.sh's parallel scheduling mode (#8231).
#
# THE MODEL. Every suite carries a set of resource TOKENS. Two suites may not be
# in flight together when their token sets intersect; the token `*` intersects
# EVERYTHING, which is what makes it a drain barrier (the pool must be empty
# before a `*` suite launches and stays empty until it is reaped). An empty
# token set is a fully independent suite.
#
# WHY TOKENS AND NOT LANES. A `parallel` / `serial` / `serial-after:<label>`
# vocabulary cannot express what the collision inventory actually contains:
# `serial` still leaves P-1 siblings in flight (the cf-tunnel battery fails on
# ANY concurrent change under scripts/ or .github/ — it needs a drained pool,
# not a slot), and `serial-after` orders one pair while doing nothing about a
# third writer (ordering is not exclusion). One mechanism — a token set whose
# members are mutually exclusive — expresses both.
#
# DECLARATIONS ARE DERIVED FIRST AND HAND-WRITTEN SECOND. A table that started
# empty against ~680 registrations and defaulted unlisted labels to a barrier
# would ship a parallel mode SLOWER than serial. The classifier below reads the
# suite's own source for the signals it can see; the override table covers what
# a grep cannot see (the collision inventory: whole-box observers, shared
# artifacts, live-worktree assertions). An override WINS — it is the full token
# set for that label, not an addition — because an override exists precisely
# when derivation cannot see the real resource.
#
# FAIL CLOSED, PER SUITE, NEVER PER RUN. A suite the classifier cannot map to a
# readable file resolves to `*` — that suite gets a drain barrier, the run does
# not fall back. Every override entry carries a machine-checked `reason`, the
# exclusion shape scripts/lint-orphan-test-suites.sh already uses (#7076).
#
# CONSUMERS. scripts/test-all.sh calls lane_tokens_for at dispatch. The census
# (scripts/lib/test-suite-lanes.test.sh) walks the same entries against
# --enumerate output: every emitted label resolves, every override names an
# emitted label, every override carries a non-empty reason.
#
# BASH 3.2. No `declare -A`: the runner indexes by linear scan over parallel
# arrays, the same idiom as _SHARD_M_* in test-all.sh. This file may execute no
# command at source time beyond array assignments and function definitions —
# both consumers source it, and a side effect in one lands in the other.

LANE_OVERRIDE_LABELS=()
LANE_OVERRIDE_TOKENS=()
LANE_OVERRIDE_REASONS=()

# lane_declare <label> <tokens> <reason>
#   <label>  the registration label --enumerate emits, NEVER a file path (the
#            two drift: orphan-process-reaper-mutations registers the singular
#            orphan-process-reaper-mutation.test.sh; blog-link-validation names
#            no path at all).
#   <tokens> space-separated resource tokens, or `*` for a drain barrier.
#   <reason> a citation a reviewer can check — the collision-inventory row or
#            the mechanism name. Empty reasons fail the census.
lane_declare() {
  LANE_OVERRIDE_LABELS+=("$1")
  LANE_OVERRIDE_TOKENS+=("$2")
  LANE_OVERRIDE_REASONS+=("$3")
}

# --- The override table ------------------------------------------------------
# Seeded from the collision inventory in
# knowledge-base/project/plans/archive/20261013-051752-2026-09-17-feat-parallel-local-test-all-suites-plan.md
# (C1-C8), each verified against the live tree.

# C1+C2: asserts on the LIVE worktree — TREE_BEFORE/TREE_AFTER are a
# `git -C "$REPO_ROOT" status --porcelain` pair bracketing every mutation arm,
# so ANY suite that creates, modifies or deletes a file under scripts/ or
# .github/ during its window produces a false FAIL reading as a sandbox escape.
# A slot is not enough; it needs a drained pool.
lane_declare "scripts/cf-tunnel-liveness-gate-mutations" "*" \
  "C1/C2: live-worktree TREE_BEFORE/TREE_AFTER assertion over scripts/+.github/, plus a bare git status that rewrites .git/index"

# C8: whole-box observers — a suite whose verdict reads the machine's process
# table observes a population the pool changed. The reaper walks /proc for
# orphans; the capacity suite's subject IS the sibling-run census.
lane_declare "scripts/orphan-process-reaper" "*" \
  "C8: walks /proc and reaps by process-set observation — a worker pool is exactly the population it reads"
lane_declare "scripts/orphan-process-reaper-mutations" "*" \
  "C8: mutation half of the same /proc-observing subject"
lane_declare "scripts/test-all-capacity-signal" "*" \
  "C8: its subject is the host's sibling-run capacity verdict — meaningless beside a worker pool"

# C6: the infra runner is a suite that IS a pool — run-registered-suites.sh
# dispatches at xargs -P min(nproc,6). Beside J workers that is J + 6 processes
# of load, and it is the suite #7376 names. A drain barrier bounds it honestly.
lane_declare "apps/web-platform/infra/run-registered-suites.sh" "*" \
  "C6: carries its own xargs -P min(nproc,6) inner pool — a slot still oversubscribes by its inner width"

# C7: the two vitest registrations share apps/web-platform's node_modules/.vite
# cache and working directory. Mutual exclusion between the pair; the rest of
# the pool cannot reach the cache.
lane_declare "apps/web-platform [repo-wide+component]" "fs:node_modules_vite" \
  "C7: shares apps/web-platform/node_modules/.vite with the [unit] registration"
lane_declare "apps/web-platform [unit]" "fs:node_modules_vite" \
  "C7: shares apps/web-platform/node_modules/.vite with the [repo-wide+component] registration"

# C3: _site/ is a SHARED WRITE TARGET two registrations produce — a
# producer/producer race, invisible to the repo-write boundary because _site/
# is gitignored. The shared token excludes every writer including a third one
# an after= edge could not name. Registration order already launches the
# producer first, so no separate ordering edge is needed.
lane_declare "blog-link-validation" "artifact:_site" \
  "C3: builds the Eleventy _site/ output the bun-side suites can also touch"
lane_declare "plugins/soleur" "artifact:_site" \
  "C3: the bun-test recursion covers seo-aeo-drift-guard.test.ts, which touches repo _site/ under SEO_AEO_SKIP_BUILD=1"

# #6496: the corpus's one wall-clock ASSERTION — `elapsedMs < 500` inside
# scripts/md-to-mrkdwn.test.mjs. Concurrent load is the exact input that fires
# it, and there is no margin: unlike a `timeout N` safety bound on a fixture
# (headroom is built in), an assertion against elapsed time reads the load
# directly.
lane_declare "scripts/md-to-mrkdwn" "*" \
  "#6496: asserts elapsed_ms < 500 — a wall-clock verdict, not a safety bound"

# The scheduler's own suites. They drive sandboxed copies of the runner through
# fixture registrations; the fixtures' scheduling assertions are meaningless if
# the suites themselves are scheduled beside arbitrary load. Keep them on the
# self-SUT lane the classifier would also derive (test-all.sh is in their
# source) — declared so the intent is written, not only grepped.
lane_declare "scripts/test-all-parallel-scheduler" "lock:test-all" \
  "self-SUT: drives sandboxed test-all.sh copies through fixture registrations"
lane_declare "scripts/test-all-parallel-contention" "lock:test-all" \
  "self-SUT: drives the advisory-lock and token-serialization arms"
lane_declare "scripts/test-all-parallel-benchmark" "lock:test-all" \
  "self-SUT: times sandboxed runner arms — wall-clock is the measurement"

# --- The classifier ----------------------------------------------------------

# _lane_suite_file <argv...> — map a registration's argv to the suite's readable
# source file. Prints the repo-relative path on success, nothing on failure.
#
# Covers the measured argv shapes in --enumerate-commands output:
#   bash <path>                      -> $2
#   python3 <path>.py                -> $2
#   python3 -m unittest <a.b.c>      -> a/b/c.py
#   python3 -m pytest <path>         -> $4
#   node --test <path>               -> last element
#   bun test <path-or-dir>           -> last element (a directory maps to itself)
#   env [VAR= ...] bash <script>     -> the bash operand
#   <direct-path>                    -> $1
_lane_suite_file() {
  local a0="${1:-}"
  case "$a0" in
    bash|sh|dash|zsh|ksh)
      [[ -n "${2:-}" ]] && printf '%s\n' "$2"
      return 0
      ;;
    python3|python|pytest)
      if [[ "${2:-}" == "-m" ]]; then
        case "${3:-}" in
          unittest)
            local mod="${4:-}"
            [[ -n "$mod" ]] && printf '%s\n' "${mod//.//}.py"
            return 0
            ;;
          pytest)
            # pytest [flags] <path> — the path is the last argument.
            local last="${!#}"
            [[ "$last" != "-m" && -n "$last" ]] && printf '%s\n' "$last"
            return 0
            ;;
        esac
        return 0
      fi
      [[ -n "${2:-}" ]] && printf '%s\n' "$2"
      return 0
      ;;
    node|bun)
      # `node --test <path>` / `bun test <path>` — the path is the last argument.
      local last="${!#}"
      [[ "$last" != "$a0" && -n "$last" ]] && printf '%s\n' "$last"
      return 0
      ;;
    env)
      # `env [VAR= ...] bash <script>` — the element after `bash`.
      local seen_bash=0 a
      for a in "$@"; do
        if (( seen_bash == 1 )); then printf '%s\n' "$a"; return 0; fi
        [[ "$a" == "bash" ]] && seen_bash=1
      done
      return 0
      ;;
    *)
      # A direct executable path or an unrecognised argv0.
      printf '%s\n' "$a0"
      return 0
      ;;
  esac
}

# lane_tokens_for <label> <argv...> — the suite's resource-token set, printed
# space-separated (empty means fully independent). Consults the override table
# first — an override IS the label's token set, not an addition — then derives
# from the suite's own source.
#
# Derived signals, each conservative in the direction it can be wrong:
#   test-all.sh mentioned in the body        -> lock:test-all  (self-SUT
#       spawner: drives a nested copy of this runner — sandboxed, enumerated or
#       lock-neutered today, and mutually serialized here so two of them never
#       run their nested walks side by side)
#   git -C $REPO_ROOT <state-changing verb>  -> repo:index     (live-repo git
#       that refreshes .git/index — index.lock contention is a measured failure
#       mode of this boundary; read-only verbs ls-files/rev-parse/grep/show/
#       cat-file do not refresh and are not matched)
#   xargs ... -P / --max-pool-size           -> cpu:pool       (the suite carries
#       its own inner pool; mutually serialized so inner widths never multiply)
#   _site/ mentioned in the body             -> artifact:_site (shared build
#       output, gitignored — the boundary cannot see the race)
#   suite file unmappable or unreadable      -> *              (fail closed:
#       a suite the classifier cannot read gets a drain barrier, never a guess)
lane_tokens_for() {
  local label="$1"; shift
  local i
  for (( i = 0; i < ${#LANE_OVERRIDE_LABELS[@]}; i++ )); do
    if [[ "${LANE_OVERRIDE_LABELS[i]}" == "$label" ]]; then
      printf '%s\n' "${LANE_OVERRIDE_TOKENS[i]}"
      return 0
    fi
  done
  local f
  f="$(_lane_suite_file "$@")"
  if [[ -z "$f" || ! -r "$f" || -d "$f" ]]; then
    printf '*\n'
    return 0
  fi
  local toks=""
  grep -qE 'test-all\.sh' "$f" 2>/dev/null && toks+="lock:test-all "
  grep -qE 'git -C ["'"'"']?\$[{]?(REPO_ROOT|REPO)["'"'"']? (status|diff|add|commit|checkout|restore|reset|stash|worktree|tag|merge|rebase|push|pull|fetch)' "$f" 2>/dev/null \
    && toks+="repo:index "
  grep -qE 'xargs[^|]*-P|--max-pool-size' "$f" 2>/dev/null && toks+="cpu:pool "
  grep -qE '_site/' "$f" 2>/dev/null && toks+="artifact:_site "
  printf '%s\n' "${toks% }"
}

# lane_tokens_conflict <setA> <setB> — exit 0 when the two token sets may not be
# in flight together: `*` intersects everything (the drain barrier), any shared
# token intersects pairwise. Pure — no filesystem access, safe in hot loops.
#
# `read -ra` on a herestring, NOT `for x in $1`: word splitting alone leaves the
# `*` token to pathname expansion, which would dissolve the drain barrier into
# the current directory's file list — measured bug, the * arm of the scheduler
# guard caught it.
lane_tokens_conflict() {
  local -a _A _B
  read -ra _A <<<"$1"
  read -ra _B <<<"$2"
  local a b
  for a in "${_A[@]+"${_A[@]}"}"; do
    [[ "$a" == "*" ]] && return 0
    for b in "${_B[@]+"${_B[@]}"}"; do
      [[ "$b" == "*" || "$a" == "$b" ]] && return 0
    done
  done
  for b in "${_B[@]+"${_B[@]}"}"; do [[ "$b" == "*" ]] && return 0; done
  return 1
}
