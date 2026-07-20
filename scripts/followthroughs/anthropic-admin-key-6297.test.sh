#!/usr/bin/env bash
# Fixture tests for the #6297 follow-through probe.
#
# The load-bearing arms are CONTAMINATION: `betterstack-query.sh --grep`
# compiles to an unanchored `raw LIKE '%…%'` over the single Better Stack
# source every host multiplexes into, and GitHub webhook payloads reach it — so
# a probe that matched by substring could PASS on an echo of the PR/issue body
# that merely QUOTES the marker, auto-closing #6297 with the key unminted.
# Tests 5/5b/5c assert it does not; tests 6 and 7 MUTATE each guard out and
# require the corresponding fixture to flip, so neither arm is vacuous.
set -uo pipefail

# Single owning trap (ADR-129 / #6734). This suite allocates a sandbox dir plus a
# fixture file PER TEST — the set is built dynamically, so the trap owns an
# accumulator rather than a fixed list of names. Without it a mid-suite abort
# (a failing assertion under `set -e` in a future edit, or an operator ^C) leaks
# ~20 sandbox trees per run into TMPDIR.
#
# `rm -rf` is correct here and not over-broad: every registered path came from
# `mktemp`/`mktemp -d`, so each is a fresh private path this script created.
TMP_PATHS=()
cleanup_tmp() {
  local p
  for p in "${TMP_PATHS[@]:-}"; do
    [[ -n "$p" ]] && rm -rf -- "$p" 2>/dev/null
  done
}
trap cleanup_tmp EXIT INT TERM

# Allocate + register in one step. Every mktemp in this file goes through these.
mktmp()  { local p; p=$(mktemp "$@");    TMP_PATHS+=("$p"); printf '%s' "$p"; }
mktmpd() { local p; p=$(mktemp -d "$@"); TMP_PATHS+=("$p"); printf '%s' "$p"; }

PROBE_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/anthropic-admin-key-6297.sh"
fails=0
pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; fails=$((fails + 1)); }
# if/else, not `cond && pass || fail` (SC2015): under that form a non-zero
# return from pass() would silently run fail() too and corrupt the count.
check() { # check <actual> <expected> <label>
  if [[ "$1" == "$2" ]]; then pass "$3"; else fail "$3 — expected exit $2, got $1"; fi
}

# Build a sandbox git repo with a stubbed betterstack-query.sh that replays a
# fixture file, so the probe runs its real logic against synthetic rows.
# `mktemp -d` (not a name derived from this script) — parallel worktrees are
# this repo's documented workflow and a fixed name would collide.
make_sandbox() {
  local fixture="$1" probe="${2:-$PROBE_SRC}"
  local d
  d=$(mktmpd -t ft6297.XXXXXXXX)
  git -C "$d" init -q 2>/dev/null
  mkdir -p "$d/scripts/followthroughs"
  cp "$probe" "$d/scripts/followthroughs/anthropic-admin-key-6297.sh"
  chmod +x "$d/scripts/followthroughs/anthropic-admin-key-6297.sh"
  cp "$fixture" "$d/rows.jsonl"
  cat > "$d/scripts/betterstack-query.sh" <<'STUB'
#!/usr/bin/env bash
cat "$(git rev-parse --show-toplevel)/rows.jsonl"
STUB
  chmod +x "$d/scripts/betterstack-query.sh"
  echo "$d"
}

# Wrap a bare pino log line into the JSONEachRow envelope the query emits
# (`raw` is a JSON *string*, so every inner quote is escaped on stdout).
# Second arg is the row's `dt`. Every fixture used to hardcode ONE timestamp,
# which made row ORDER — the thing the newest-row verdict depends on — entirely
# unsampled. Pass distinct dts so ordering is a property under test.
envelope() { jq -c -n --arg raw "$1" --arg dt "${2:-2026-07-19 06:17:00}" '{dt:$dt, raw:$raw}'; }
T1="2026-07-19 06:17:00"   # older
T2="2026-07-20 06:17:00"   # newer

# `env -i` — hermetic, mirroring how the sweeper actually runs probes. With a
# plain `env VAR=…` an ambient SENTRY_AUTH_TOKEN/GH_TOKEN leaks in from the
# developer or CI shell and the zero-rows fixture makes a LIVE 25s network call
# to sentry.io, so the suite's result depends on the machine it runs on.
run_probe() {
  local dir="$1"
  ( cd "$dir" && env -i \
      PATH="$PATH" HOME="$HOME" \
      BETTERSTACK_QUERY_HOST=h \
      BETTERSTACK_QUERY_USERNAME=u \
      BETTERSTACK_QUERY_PASSWORD=p \
      bash scripts/followthroughs/anthropic-admin-key-6297.sh >/dev/null 2>&1 )
  echo $?
}

OK_ROW='{"level":40,"component":"claude-cost","SOLEUR_CLAUDE_COST_DAILY":true,"status":"ok","date":"2026-07-19","cost_usd":12.5}'
DARK_ROW='{"level":40,"component":"claude-cost","SOLEUR_CLAUDE_COST_DAILY":true,"status":"key-missing","date":"2026-07-19","days_since_first_dark":10}'
# A realistic webhook echo: the marker text appears ONLY as nested string
# content of a payload field. Top-level `component` is the webhook producer.
ECHO_ROW='{"level":30,"component":"inngest","msg":"github webhook","body":"Fix: the probe requires \"SOLEUR_CLAUDE_COST_DAILY\":true and \"component\":\"claude-cost\" with \"status\":\"ok\" to pass."}'
# The ADVERSARIAL echo: everything the PASS path reads is present and correct at
# TOP LEVEL except `component`. This isolates the component guard as the single
# discriminator, so the mutation in test 6 proves that guard specifically. The
# realistic fixture above cannot prove it — it is also rejected for lacking a
# top-level `status`, so it would pass the test even with the guard removed.
ECHO_ADVERSARIAL='{"level":30,"component":"inngest","SOLEUR_CLAUDE_COST_DAILY":true,"status":"ok","msg":"webhook echo of the PR body"}'
# The MULTI-LINE echo. A stack trace / journald entry whose `raw` embeds a
# forged producer line. This is the shape that broke an earlier two-stage
# `jq -R | jq -R` guard: stage 1 materialized the \n as a real newline and
# stage 2 re-tokenized on physical lines, so the embedded line was evaluated
# as a top-level log line and the probe PASSed with the key unminted. Every
# other fixture here is single-line, so nothing else covers this boundary.
ECHO_MULTILINE='inngest: unhandled error while logging webhook body
{"SOLEUR_CLAUDE_COST_DAILY":true,"component":"claude-cost","status":"ok"}
    at handler (/app/server.js:1)'

echo "== #6297 follow-through probe fixtures =="

# 1 — healthy report → PASS
f=$(mktmp -t ft.XXXXXXXX); envelope "$OK_ROW" > "$f"
d=$(make_sandbox "$f"); rc=$(run_probe "$d")
check "$rc" 0 "healthy ok row → exit 0"

# 2 — still un-minted → TRANSIENT (never PASS, never FAIL)
f=$(mktmp -t ft.XXXXXXXX); envelope "$DARK_ROW" > "$f"
d=$(make_sandbox "$f"); rc=$(run_probe "$d")
check "$rc" 2 "key-missing only → exit 2"

# 3 — regression: worked, then stopped → FAIL (this is what makes the
#     sweeper's closed-set reopen path reachable rather than structurally inert)
f=$(mktmp -t ft.XXXXXXXX); { envelope "$OK_ROW" "$T1"; envelope "$DARK_ROW" "$T2"; } > "$f"
d=$(make_sandbox "$f"); rc=$(run_probe "$d")
check "$rc" 1 "ok(old) then key-missing(new) → exit 1"

# 3b — SAME rows, emitted newest-first. The verdict must be identical: it is a
#      function of `dt`, not of the order the query happened to return. Without
#      this, `tail -1` silently trusts an upstream ORDER BY that no test pins,
#      and a flip there would inverts a live revocation into PASS.
f=$(mktmp -t ft.XXXXXXXX); { envelope "$DARK_ROW" "$T2"; envelope "$OK_ROW" "$T1"; } > "$f"
d=$(make_sandbox "$f"); rc=$(run_probe "$d")
check "$rc" 1 "same rows emitted newest-first → still exit 1 (order-independent)"

# 4 — producer silent → TRANSIENT (positive-liveness rule: zero rows is never PASS)
f=$(mktmp -t ft.XXXXXXXX); : > "$f"
d=$(make_sandbox "$f"); rc=$(run_probe "$d")
check "$rc" 2 "zero producer rows → exit 2"

# 5 — CONTAMINATION (P0): a webhook echo quoting every literal, including
#     "status":"ok", must NOT close the issue.
f=$(mktmp -t ft.XXXXXXXX); envelope "$ECHO_ROW" > "$f"
d=$(make_sandbox "$f"); rc=$(run_probe "$d")
check "$rc" 2 "webhook echo quoting the marker → exit 2 (not closed)"

# 5b — adversarial echo: correct at top level in every field the PASS path
#      reads, except `component`. Only the structural guard rejects this.
f=$(mktmp -t ft.XXXXXXXX); envelope "$ECHO_ADVERSARIAL" > "$f"
d=$(make_sandbox "$f"); rc=$(run_probe "$d")
check "$rc" 2 "adversarial echo (wrong component only) → exit 2"

# 5c — MULTI-LINE CONTAMINATION (P1 regression guard). Fails against the
#      two-stage jq form; passes only with the single-pass filter.
f=$(mktmp -t ft.XXXXXXXX); envelope "$ECHO_MULTILINE" > "$f"
d=$(make_sandbox "$f"); rc=$(run_probe "$d")
check "$rc" 2 "multi-line raw embedding a forged producer line → exit 2"

# 5d — RECOVERY: dark first, then the key starts working. Must PASS. Without
#      this, a FAIL predicate like `ROWS > HAS_OK` satisfies every other
#      fixture while reopening the issue at the moment the key begins working.
f=$(mktmp -t ft.XXXXXXXX); { envelope "$DARK_ROW" "$T1"; envelope "$OK_ROW" "$T2"; } > "$f"
d=$(make_sandbox "$f"); rc=$(run_probe "$d")
check "$rc" 0 "key-missing(old) then ok(new) — recovery → exit 0"

# 6 — MUTATION: prove 5b is non-vacuous. Strip the structural component guard;
#     the adversarial fixture must then wrongly PASS (exit 0). If it still
#     exits 2, the guard is not what is rejecting it and 5b proves nothing.
MUT=$(mktmp -t ft-mut.XXXXXXXX.sh)
sed 's/and .component == "claude-cost"//' "$PROBE_SRC" > "$MUT"
if ! grep -q 'select(.SOLEUR_CLAUDE_COST_DAILY == true )' "$MUT"; then
  fail "mutation did not apply — the jq selector text drifted; 5b is unproven"
else
  f=$(mktmp -t ft.XXXXXXXX); envelope "$ECHO_ADVERSARIAL" > "$f"
  d=$(make_sandbox "$f" "$MUT"); rc=$(run_probe "$d")
  check "$rc" 0 "mutation makes the adversarial echo PASS (guard is load-bearing)"
fi

# 7 — MUTATION: prove 5c is non-vacuous. Split the single-pass filter back into
#     the two-stage form that shipped the defect; the multi-line fixture must
#     then wrongly PASS. This pins the tokenization boundary itself, not just
#     the selector text — test 6's mutation survives a two-stage refactor, so
#     without this arm the single-pass property has no guard at all.
MUT2=$(mktmp -t ft-mut2.XXXXXXXX.sh)
python3 - "$PROBE_SRC" "$MUT2" <<'PY'
import re, sys
src, dst = sys.argv[1], sys.argv[2]
s = open(src).read()
# Swap the single-pass filter for the two-stage `jq -R | jq -R` form that
# shipped the defect, keeping the "<dt>\t<status>" output contract so only the
# tokenization boundary changes. A stray `sed` supplies a placeholder dt.
two = (
    "| jq -R -r 'fromjson? | .raw // empty' 2>/dev/null "
    "| jq -R -r 'fromjson? | select(.SOLEUR_CLAUDE_COST_DAILY == true and .component == \"claude-cost\") "
    "| .status // \"unknown\"' 2>/dev/null | sed 's/^/2026-01-01\\t/' \\"
)
# lambda, not a replacement string — `two` contains backslashes that re would
# otherwise interpret as escapes.
out, n = re.subn(r"\| jq -R -r 'fromjson\? \| \. as \$r.*?' 2>/dev/null \\", lambda _m: two, s, flags=re.S)
assert n == 1, f"expected exactly 1 filter match, got {n}"
open(dst, "w").write(out)
PY
if ! grep -q "jq -R -r 'fromjson? | .raw // empty' 2>/dev/null" "$MUT2"; then
  fail "mutation 2 did not apply — the jq filter text drifted; 5c is unproven"
else
  f=$(mktmp -t ft.XXXXXXXX); envelope "$ECHO_MULTILINE" > "$f"
  d=$(make_sandbox "$f" "$MUT2"); rc=$(run_probe "$d")
  check "$rc" 0 "two-stage mutation makes the multi-line echo PASS (single-pass is load-bearing)"
fi

# ---------------------------------------------------------------------------
# 8-12 — the ZERO-ROW mitigations (AC14b).
#
# Tests 1-7 all run `run_probe`, which is `env -i` with only BETTERSTACK_QUERY_*
# and discards stdout. So GH_TOKEN/SENTRY_AUTH_TOKEN are ALWAYS unset there and
# every zero-row run takes the two "skipped/unavailable" arms — the Sentry
# DIVERGENCE branch and the STALLED branch were reachable code that no fixture
# ever executed, and no arm's output was asserted at all.
#
# That is the same defect class this suite already guards twice over: a branch
# whose green proves nothing about the property it names. Both mitigations exit
# 2 exactly like the plain TRANSIENT, so an exit-code-only harness structurally
# CANNOT tell them apart — these arms must assert on stdout.
#
# Hermeticity is preserved: the stubs are explicit files in a sandbox-local
# bin/ prepended to PATH inside the same `env -i`, never an ambient binary.

# Install stub `gh` / `curl` into the sandbox and run with tokens set,
# capturing stdout. Passing a token here is what selects the live arm.
run_probe_out() { # run_probe_out <dir> <gh-stub-body> <curl-stub-body>
  local dir="$1" gh_body="$2" curl_body="$3"
  mkdir -p "$dir/bin"
  printf '#!/usr/bin/env bash\n%s\n' "$gh_body" > "$dir/bin/gh"
  printf '#!/usr/bin/env bash\n%s\n' "$curl_body" > "$dir/bin/curl"
  chmod +x "$dir/bin/gh" "$dir/bin/curl"
  ( cd "$dir" && env -i \
      PATH="$dir/bin:$PATH" HOME="$HOME" \
      BETTERSTACK_QUERY_HOST=h \
      BETTERSTACK_QUERY_USERNAME=u \
      BETTERSTACK_QUERY_PASSWORD=p \
      GH_TOKEN=t SENTRY_AUTH_TOKEN=s \
      bash scripts/followthroughs/anthropic-admin-key-6297.sh 2>&1 )
}

# Assert a substring is present (or absent) in captured stdout.
check_out() { # check_out <haystack> <needle> <label>
  if grep -qF -- "$2" <<<"$1"; then pass "$3"; else fail "$3 — stdout lacked: $2"; fi
}
check_no_out() { # check_no_out <haystack> <needle> <label>
  if grep -qF -- "$2" <<<"$1"; then fail "$3 — stdout unexpectedly had: $2"; else pass "$3"; fi
}

GH_ZERO='echo 0'
CURL_ZERO='echo "{\"data\":[{\"count()\":0}]}"'

# 8 — Sentry reports events while Better Stack has none: the shipping path is
#     broken. This is failure mode #5, invisible to the Sentry cron monitor.
f=$(mktmp -t ft.XXXXXXXX); : > "$f"
d=$(make_sandbox "$f")
out=$(run_probe_out "$d" "$GH_ZERO" 'echo "{\"data\":[{\"count()\":42}]}"')
check_out "$out" "DIVERGENCE: Sentry shows 42 event(s) in 48h" "zero rows + Sentry events → DIVERGENCE reported"
check_out "$out" "shipping path is dropping rows" "DIVERGENCE names the shipping path as the fault"

# 9 — Sentry reports zero. Must NOT be stated as evidence the cron is dead:
#     the tag is emitted only on the dark branch, so 0 is consistent with a
#     healthy cron whose rows are not shipping.
f=$(mktmp -t ft.XXXXXXXX); : > "$f"
d=$(make_sandbox "$f")
out=$(run_probe_out "$d" "$GH_ZERO" "$CURL_ZERO")
check_out "$out" "NOT decisive" "zero rows + zero Sentry events → hedged, not concluded"
check_no_out "$out" "DIVERGENCE" "zero Sentry events does not claim DIVERGENCE"

# 10 — Sentry auth failure must read as inconclusive, NOT as a substantive
#      zero. `--fail` on the curl is the single thing that makes this true, so
#      the stub MODELS REAL CURL rather than hardcoding a non-zero exit:
#      given a 401, real curl WITHOUT --fail prints the error body and exits 0
#      (jq then maps {"detail":"Invalid token"} through `// 0` to a false
#      "0 events"), and WITH --fail exits 22 printing nothing. A stub that just
#      `exit 22`s passes either way and proves nothing about the flag.
CURL_401='if [[ " $* " == *" --fail "* ]]; then exit 22; fi
echo "{\"detail\":\"Invalid token\"}"'
f=$(mktmp -t ft.XXXXXXXX); : > "$f"
d=$(make_sandbox "$f")
out=$(run_probe_out "$d" "$GH_ZERO" "$CURL_401")
check_out "$out" "Sentry cross-check inconclusive" "Sentry 401 → inconclusive, not a substantive zero"
check_no_out "$out" "NOT decisive" "a 401 does not render the zero-events verdict"

# 11 — the stall bound actually fires. A probe that shrugs identically forever
#      is the decayed-dark-state defect #6297 exists to remove.
f=$(mktmp -t ft.XXXXXXXX); : > "$f"
d=$(make_sandbox "$f")
out=$(run_probe_out "$d" 'echo 9' "$CURL_ZERO"); rc=$?
check_out "$out" "STALLED: 9 consecutive sweeps" "9 prior zero-row sweeps → STALLED fires"
# Still TRANSIENT, never FAIL — STALLED escalates attention, not the verdict.
check "$rc" 2 "STALLED still exits 2 (attention, not verdict)"

# 11b — boundary: 6 prior sweeps is below the >=7 bound and must stay silent,
#       so the threshold is pinned rather than "any positive count fires".
f=$(mktmp -t ft.XXXXXXXX); : > "$f"
d=$(make_sandbox "$f")
out=$(run_probe_out "$d" 'echo 6' "$CURL_ZERO")
check_no_out "$out" "STALLED" "6 prior sweeps → below the >=7 bound, stays silent"

# 12 — a dead counter must sentinel loudly. `|| echo 0` as the failure path
#      would make a broken counter look identical to "first sweep" forever.
f=$(mktmp -t ft.XXXXXXXX); : > "$f"
d=$(make_sandbox "$f")
out=$(run_probe_out "$d" 'exit 1' "$CURL_ZERO")
check_out "$out" "Stall counter query FAILED" "gh failure → loud sentinel, not a silent 0"
check_no_out "$out" "STALLED" "a failed counter does not also claim STALLED"

echo
if (( fails > 0 )); then echo "FAILED: $fails"; exit 1; fi
echo "All fixtures passed."
