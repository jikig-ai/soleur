#!/usr/bin/env bash
# Test: apps/web-platform/infra/run-registered-suites.sh
#
# Pins the runner's OWN logic — derivation from the workflow, the fail-closed
# zero-guard, and the orphan scan — via `--list`, so none of it requires the
# ~25-minute full run. The runner exists because a green test-all was mistaken
# for infra coverage (#6730); a runner whose own correctness were merely
# asserted would reproduce that defect one level up.
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT" || exit 1

# SUT seam. Exists ONLY so the mutation matrix (T7) can point these assertions at a MUTATED
# COPY of the CURRENT runner. It is deliberately NOT for pointing at a pre-change copy: the old
# runner lacks the INFRA_DIR seam, so it derives ZERO and exits 2 — which satisfies every
# "no dump appeared" assertion trivially, red for the wrong reason.
#
# Fail-closed: a typo in SUT must not silently fall back to testing the real runner and
# reporting a green mutation matrix.
SUT="${SUT:-apps/web-platform/infra/run-registered-suites.sh}"
[[ -x "$SUT" ]] || { echo "[FAIL] SUT=$SUT is not executable" >&2; exit 2; }

# Read the cap OUT of the runner rather than hardcoding a bound. AC2 asks for exactly this
# ("put the number in the runner and assert against it"); a hand-picked ceiling silently
# decouples from DUMP_CAP, so raising the cap would leave the assertion passing for a reason
# no reader could reconstruct. +6 is the banner/label/blank-line slop around one suite's excerpt.
DUMP_CAP_SUT=$(sed -n 's/^DUMP_CAP=\([0-9][0-9]*\)$/\1/p' "$SUT")
[[ "$DUMP_CAP_SUT" =~ ^[0-9]+$ ]] || { echo "[FAIL] could not read DUMP_CAP from $SUT" >&2; exit 2; }
DUMP_CEIL=$(( DUMP_CAP_SUT + 6 ))
WF=".github/workflows/infra-validation.yml"

pass=0; fail=0
ok() { pass=$((pass + 1)); echo "[ok] $1"; }
no() { fail=$((fail + 1)); echo "[FAIL] $1" >&2; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Snapshot the live infra directory listing. T5c asserts it is byte-identical at the end:
# this suite runs CONCURRENTLY with every sibling suite, so anything it creates or deletes, it
# does while they are reading it (#7376).
INFRA_LS_BEFORE="$(ls -A apps/web-platform/infra/ | sort)"

# ── T1: the script exists and is executable ───────────────────────────────────
if [[ -x "$SUT" ]]; then ok "T1: $SUT exists and is executable"
else no "T1: $SUT missing or not executable"; fi

# ── T2: --list derives the real registered set and runs NOTHING ───────────────
# Bound the runtime: if --list ever started executing suites this would blow the
# timeout rather than quietly taking 25 minutes.
OUT="$(timeout 60 bash "$SUT" --list 2>&1)"; rc=$?
if (( rc == 0 )); then ok "T2a: --list exits 0"
else no "T2a: --list exited $rc (60s timeout = it executed suites instead of listing)"; fi

# Count ONLY the derived section — the orphan report below it also prints
# two-space-indented suite paths, so a whole-output grep double-counts (it read
# 79 = 70 derived + 9 orphans on the first run of this test).
DERIVED=$(printf '%s\n' "$OUT" \
  | awk '/^Derived [0-9]+ registered infra suite/{f=1;next} /^$/{f=0} f' \
  | grep -cE '^  apps/web-platform/infra/[A-Za-z0-9._-]+\.test\.sh$')
EXPECTED=$(grep -oE 'run: bash apps/web-platform/infra/[A-Za-z0-9._-]+\.test\.sh' "$WF" \
  | sed 's/run: bash //' | sort -u | wc -l)
# The header's own count must agree with the lines it introduces — otherwise a
# future edit could print a plausible header over a truncated list.
HEADER_N=$(printf '%s\n' "$OUT" | sed -nE 's/^Derived ([0-9]+) registered infra suite.*/\1/p')
# Equality against the workflow, not a hardcoded count: the whole point of
# deriving is that runner and CI cannot drift, so the test asserts the identity
# rather than a number that would need editing every time a suite is added.
if (( DERIVED > 0 )) && (( DERIVED == EXPECTED )); then
  ok "T2b: --list derives exactly the workflow's registered set ($DERIVED)"
else
  no "T2b: --list derived $DERIVED, workflow registers $EXPECTED"
fi

if [[ "$HEADER_N" == "$DERIVED" ]]; then
  ok "T2d: the header count matches the list it introduces ($HEADER_N)"
else
  no "T2d: header says $HEADER_N but $DERIVED suites are listed"
fi

# ── T2e: the derived set vs an INDEPENDENT oracle ────────────────────────────
# Skipped in mutation children: this asserts which suites the WORKFLOW registers, a property of
# the repo that no mutation of the runner can change. Re-running it 7x only costs wall clock.
if [[ -z "${SOLEUR_MUTATION_CHILD:-}" ]]; then
# T2b's oracle is the SAME regex the runner uses, so it agrees by construction and cannot see
# a suite the regex structurally cannot match. This oracle is deliberately more permissive
# (`\S+` accepts subdirectories) and therefore CAN disagree.
#
# It disagrees today: 8 suites are registered in CI and NEVER run by this runner. Seven are
# `run: bash <subdir>/…` (the derivation ERE has no `/` in its tail); the eighth is registered
# as `sudo bash …` (infra-validation.yml:912), a shape the ERE's `run: bash` anchor cannot see
# either. That falsifies the header's "a suite added to the workflow is picked up here
# automatically" and "runner and CI cannot drift". Tracked for remediation by #7076.
#
# The oracle below therefore matches BOTH invocation shapes. An earlier version anchored on
# `run: bash` alone — i.e. it shared the SUT's own blind spot for the sudo form, so a future
# `sudo bash` registration would have landed green while the comment claimed "reds if an 8th
# appears". It reds when a NEW one appears in either shape.
#
# Pinned as an ENUMERATED ratchet rather than a count: a bare "8 known gaps" comment is
# documentation, not a guard. This list must SHRINK — it reds both when a new underived suite
# is registered AND when one is fixed but left listed.
KNOWN_UNDERIVED=(
  apps/web-platform/infra/workspaces-luks-loopback.test.sh
  apps/web-platform/infra/inngest-rls/apply-inngest-rls-dev-workflow.test.sh
  apps/web-platform/infra/inngest-rls/inngest-rls-mutation.test.sh
  apps/web-platform/infra/inngest-rls/inngest-rls.test.sh
  apps/web-platform/infra/scripts/gen-github-egress-cidr.test.sh
  apps/web-platform/infra/scripts/sigpipe-triage-feasibility.test.sh
  apps/web-platform/infra/supabase-advisor/scan-workflow-mutation.test.sh
  apps/web-platform/infra/supabase-advisor/scan-workflow.test.sh
)
_perm=$(mktemp); _der=$(mktemp); _known=$(mktemp)
grep -oE '(run:|sudo) bash apps/web-platform/infra/[^ ]+\.test\.sh' "$WF" \
  | sed -E 's/^(run:|sudo) bash //' | LC_ALL=C sort -u > "$_perm"
printf '%s\n' "$OUT" \
  | awk '/^Derived [0-9]+ registered infra suite/{f=1;next} /^$/{f=0} f' \
  | sed -n 's|^  \(apps/web-platform/infra/.*\.test\.sh\)$|\1|p' | LC_ALL=C sort -u > "$_der"
printf '%s\n' "${KNOWN_UNDERIVED[@]}" | LC_ALL=C sort -u > "$_known"
_gap=$(comm -23 "$_perm" "$_der")
if [[ "$_gap" == "$(cat "$_known")" ]]; then
  ok "T2e: the ${#KNOWN_UNDERIVED[@]} registered-but-underived suites are exactly the known set (#7076)"
else
  no "T2e: the registered-but-underived set CHANGED — fix the derivation (#7076), or update KNOWN_UNDERIVED"$'\n'"$(diff <(cat "$_known") <(printf '%s\n' "$_gap") | head -8)"
fi
rm -f "$_perm" "$_der" "$_known"
fi

if printf '%s\n' "$OUT" | grep -qE '^(PASS|RED) '; then
  no "T2c: --list executed suites (found PASS/RED lines)"
else
  ok "T2c: --list executed nothing"
fi

# ── T3: zero-derivation is FATAL, not a silent green ──────────────────────────
# The defect this guards: a workflow whose 'run: bash …' shape changed derives
# zero suites, and an unguarded runner prints "0 passed, 0 failed" and exits 0 —
# a false green that looks exactly like success.
printf 'jobs:\n  noop:\n    steps:\n      - run: echo nothing here\n' > "$TMP/empty.yml"
OUT_ZERO="$(INFRA_WF="$TMP/empty.yml" bash "$SUT" --list 2>&1)"; rc_zero=$?
if (( rc_zero == 2 )); then ok "T3a: zero-derivation exits 2"
else no "T3a: zero-derivation exited $rc_zero, expected 2"; fi

if printf '%s\n' "$OUT_ZERO" | grep -q 'derived ZERO suites'; then
  ok "T3b: zero-derivation names the cause"
else
  no "T3b: zero-derivation did not explain itself: $OUT_ZERO"
fi

if printf '%s\n' "$OUT_ZERO" | grep -qE '0 (passed|failed)'; then
  no "T3c: zero-derivation printed a pass/fail summary (reads as success)"
else
  ok "T3c: zero-derivation prints no pass/fail summary"
fi

# ── T4: a missing workflow is FATAL, not an empty run ─────────────────────────
rc_missing=0
INFRA_WF="$TMP/does-not-exist.yml" bash "$SUT" --list >/dev/null 2>&1 || rc_missing=$?
if (( rc_missing == 2 )); then ok "T4: missing workflow exits 2"
else no "T4: missing workflow exited $rc_missing, expected 2"; fi

# ── T5: the orphan scan reports suites nothing references ─────────────────────
# Asserted against an INJECTED candidate list rather than a file created in the live
# `apps/web-platform/infra/` directory (#7376).
#
# WHY THE INJECTION SEAM EXISTS. This suite is itself registered
# (infra-validation.yml), so it runs CONCURRENTLY with every sibling suite. The previous
# form created `zzz-run-registered-suites-fixture.test.sh` in the live infra dir,
# `git add -N`d it and deleted it — while `credential-persist-home-guard.test.sh`
# was copying that same directory and `diff -rq`ing the copy against the STILL-LIVE
# source. A file appearing or vanishing inside that window yields `Only in …` → RED,
# in a suite that has nothing to do with this one. That is one of the two defects
# #7376 is about, and a test that recreates the bug it guards is worse than no test.
#
# The seam injects only the CANDIDATE LIST. The cross-reference logic that T5
# actually asserts — `git grep` for each basename across workflows/ and scripts/ —
# still runs for real against a basename nothing references.
ORPHAN_FIXTURE="apps/web-platform/infra/zzz-orphan-fixture-not-on-disk.test.sh"
printf '%s\n' "$ORPHAN_FIXTURE" > "$TMP/orphan-candidates.txt"
OUT_ORPH="$(INFRA_ORPHAN_LIST="$TMP/orphan-candidates.txt" timeout 60 bash "$SUT" --list 2>&1)"

if printf '%s\n' "$OUT_ORPH" | grep -qF "zzz-orphan-fixture-not-on-disk.test.sh"; then
  ok "T5a: orphan scan reports an unreferenced suite"
else
  no "T5a: orphan scan missed a suite nothing references"
fi

if printf '%s\n' "$OUT_ORPH" | grep -q 'referenced by NO workflow or script'; then
  ok "T5b: orphan scan explains what the list means"
else
  no "T5b: orphan scan printed no explanation"
fi

# T5c — the live-tree invariant itself, asserted rather than assumed. Snapshot the infra
# directory listing across the whole suite and require it unchanged. This is the assertion
# that keeps a future contributor from reintroducing the collision by "just" touching the
# live tree again.
INFRA_LS_AFTER="$(ls -A apps/web-platform/infra/ | sort)"
if [[ "$INFRA_LS_AFTER" == "$INFRA_LS_BEFORE" ]]; then
  ok "T5c: this suite created/removed no file under apps/web-platform/infra/"
else
  no "T5c: the live infra dir changed during this suite — the #7376 collision is back"$'\n'"$(diff <(printf '%s\n' "$INFRA_LS_BEFORE") <(printf '%s\n' "$INFRA_LS_AFTER") | head -5)"
fi

# ─────────────────────────────────────────────────────────────────────────────
# T6 — the instrument (#7376). A RED suite's own output must reach the operator.
#
# Every assertion below runs against ONE fixture that combines all three traps
# the plan identified, because split across fixtures the conjunction does not
# hold: the RED suite fails EARLY, writes its marker to STDERR at column 0, and
# then emits 120 further PASSING lines. A blind `tail` shows only the passes.
# ─────────────────────────────────────────────────────────────────────────────
FIXDIR="$TMP/fix6"; mkdir -p "$FIXDIR"

mkfixture_wf() {  # mkfixture_wf <workflow-path> <suite-path>...
  local wf="$1"; shift
  { echo "jobs:"; echo "  deploy-script-tests:"; echo "    steps:"
    for s in "$@"; do echo "      - run: bash $s"; done
  } > "$wf"
}

# The RED suite: marker on stderr, at column 0, EARLY — then 120 passing lines.
cat > "$FIXDIR/aaa-red.test.sh" <<'FIXEOF'
#!/usr/bin/env bash
# The marker is BRACKETED, not first. With it on line 1, `head -n 5` and marker-anchored
# selection are indistinguishable — measured: a head-selection mutant survived the whole suite.
# The runner's own motivating case is a failure at arm 5 of 43, i.e. far from BOTH ends.
for i in $(seq 1 60); do echo "ok   - leading pass $i"; done
# `[FAIL]` shape deliberately: it is what 10 of the 93 real suites print at column 0, and it is
# the shape the monitor's `^RED |^[FAIL]` anchor matches — so T6k's count is a real measurement
# rather than 1-by-construction. A prior `FAIL:` fixture could never trip that anchor.
echo "[FAIL] T6-EARLY-SENTINEL the assertion that actually broke" >&2
echo "RED  fake/decoy-not-a-real-suite.test.sh" >&2
for i in $(seq 1 120); do echo "ok   - trailing pass $i"; done
exit 1
FIXEOF
cat > "$FIXDIR/bbb-green.test.sh" <<'FIXEOF'
#!/usr/bin/env bash
echo "ok   - nothing to see here"
exit 0
FIXEOF
chmod +x "$FIXDIR"/*.test.sh
mkfixture_wf "$FIXDIR/wf.yml" "$FIXDIR/aaa-red.test.sh" "$FIXDIR/bbb-green.test.sh"

rc6=0
OUT6="$(INFRA_WF="$FIXDIR/wf.yml" SOLEUR_INFRA_DIR="$FIXDIR" timeout 120 bash "$SUT" 2>&1)" || rc6=$?

if (( rc6 != 0 )); then ok "T6a: a RED suite makes the runner exit non-zero (rc=$rc6)"
else no "T6a: runner exited 0 with a RED suite"; fi

if printf '%s\n' "$OUT6" | grep -qF "RED  ${FIXDIR}/aaa-red.test.sh"; then
  ok "T6b: the RED summary line keeps its exact byte shape (\`RED  <path>\`, two spaces)"
else
  no "T6b: the \`RED  <path>\` summary line changed shape"
fi

# The core of the instrument: the failing assertion — emitted early, on stderr — is present.
if printf '%s\n' "$OUT6" | grep -qF "T6-EARLY-SENTINEL"; then
  ok "T6c: the EARLY failing assertion appears in the dump (anchored selection, not a blind tail)"
else
  no "T6c: the early failing assertion is absent — selection fell back to a blind tail, or stderr was lost"
fi

# Capture ORDER: `2>&1 >"$f"` would send stderr to the OLD stdout and lose every marker.
# T6c is what detects that, but state it separately so the mutation matrix can name it.
if printf '%s\n' "$OUT6" | grep -qE '^SOLEUR\| .*T6-EARLY-SENTINEL'; then
  ok "T6d: the dumped assertion is PREFIXED with the sentinel"
else
  no "T6d: the dumped assertion is not sentinel-prefixed — it would reach the public issue body"
fi

if printf '%s\n' "$OUT6" | grep -qE '^SOLEUR\| .*rc=1'; then
  ok "T6e: the dump banner records the suite's exit code"
else
  no "T6e: the dump banner has no rc"
fi

if printf '%s\n' "$OUT6" | grep -qE '^SOLEUR\| .*elapsed='; then
  ok "T6f: the dump banner records elapsed time"
else
  no "T6f: the dump banner has no elapsed time"
fi

# start offset — without it "which neighbours overlapped the failure window" is unanswerable,
# so H2-as-victim is not falsifiable.
if printf '%s\n' "$OUT6" | grep -qE '^SOLEUR\| .*start_offset='; then
  ok "T6g: the dump banner records a start offset"
else
  no "T6g: the dump banner has no start offset"
fi

# NOTE: there is deliberately no "dump is bounded" assertion here. An earlier draft asserted
# `DUMPED <= 60` on this fixture, which emits ~10 prefixed lines — it could not fail whether the
# cap existed or not, and the row that actually pins the cap is T6p (10,000 marker lines).
# The green suite must NOT be dumped.
if printf '%s\n' "$OUT6" | grep -qF "bbb-green.test.sh" \
   && ! printf '%s\n' "$OUT6" | grep -E '^SOLEUR\| ' | grep -qF "bbb-green.test.sh"; then
  ok "T6i: only the RED suite is dumped"
else
  no "T6i: a PASSing suite was dumped (or the PASS line vanished)"
fi

# Log dir retained on failure, and its path printed — prefixed, like everything else the
# parent emits after xargs (an unprefixed path would reach the monitor's tail).
if printf '%s\n' "$OUT6" | grep -qE '^SOLEUR\| .*(retained|log dir)'; then
  ok "T6j: the retained log dir path is printed, prefixed"
else
  no "T6j: no retained log dir path in the output"
fi

# EXCERPT INVARIANT (AC3). Over the whole output, `^(RED |\[FAIL\])` must count ONLY genuine
# RED lines. The fixture emits 1 RED suite, so the literal expectation is 1 — never recomputed
# by grepping the same output, which would be `x == x`.
#
# The ERE alternation MUST be a bare `|`. `'^(RED \|\[FAIL\])'` is a literal pipe in an ERE:
# it matches nothing, exits 1, and passes vacuously.
# Expected count is a LITERAL derived from the fixture, never recomputed from this output:
# 1 genuine `RED  <path>` from the runner. The fixture's own `[FAIL]` and decoy `RED ` lines
# are dumped, so they MUST arrive sentinel-prefixed and therefore MUST NOT match this anchor.
# That is the whole property: 3 here means dumped bytes reached the monitor's title derivation.
N_ANCHOR=$(printf '%s\n' "$OUT6" | grep -cE '^(RED |\[FAIL\])' || true)
if (( N_ANCHOR == 1 )); then
  ok "T6k: excerpt invariant — exactly 1 line matches the monitor's anchor (the genuine RED)"
else
  no "T6k: ${N_ANCHOR} lines match the monitor's anchor, expected exactly 1 (dumped bytes leaked past the prefix)"
fi

# ── T6m: a suite that dies with NO marker still reports, and says which selection it used ──
FIXDIR2="$TMP/fix6m"; mkdir -p "$FIXDIR2"
cat > "$FIXDIR2/aaa-nomarker.test.sh" <<'FIXEOF'
#!/usr/bin/env bash
echo "some output that carries no failure marker at all"
exit 7
FIXEOF
chmod +x "$FIXDIR2"/*.test.sh
mkfixture_wf "$FIXDIR2/wf.yml" "$FIXDIR2/aaa-nomarker.test.sh"
OUT6M="$(INFRA_WF="$FIXDIR2/wf.yml" SOLEUR_INFRA_DIR="$FIXDIR2" timeout 60 bash "$SUT" 2>&1)" || true
if printf '%s\n' "$OUT6M" | grep -qE '^SOLEUR\| .*rc=7'; then
  ok "T6m: a non-1 exit code is recorded verbatim (rc=7)"
else
  no "T6m: rc=7 not recorded — exit codes 137/124 would be unreadable"
fi
if printf '%s\n' "$OUT6M" | grep -qiE '^SOLEUR\| .*(selection|fallback|tail)'; then
  ok "T6n: the runner names which excerpt selection it used"
else
  no "T6n: the runner does not say whether the excerpt was anchored or a blind tail"
fi

# ── T6p: the cap binds AFTER selection ────────────────────────────────────────
FIXDIR3="$TMP/fix6p"; mkdir -p "$FIXDIR3"
cat > "$FIXDIR3/aaa-flood.test.sh" <<'FIXEOF'
#!/usr/bin/env bash
for i in $(seq 1 10000); do echo "FAIL: flood line $i"; done
exit 1
FIXEOF
chmod +x "$FIXDIR3"/*.test.sh
mkfixture_wf "$FIXDIR3/wf.yml" "$FIXDIR3/aaa-flood.test.sh"
OUT6P="$(INFRA_WF="$FIXDIR3/wf.yml" SOLEUR_INFRA_DIR="$FIXDIR3" timeout 60 bash "$SUT" 2>&1)" || true
# Assert on what DUMP_CAP ACTUALLY governs — the selection block — not the total prefixed
# line count, which also carries a banner and footer and so drifts with unrelated edits.
FLOOD_SEL=$(printf '%s\n' "$OUT6P" | grep -cE '^SOLEUR\| FAIL: flood line ' || true)
if (( FLOOD_SEL > DUMP_CAP_SUT )); then
  no "T6p: the selection block is ${FLOOD_SEL} lines, above DUMP_CAP=${DUMP_CAP_SUT} — the cap does not bind after selection"
else
  ok "T6p: 10,000 marker lines capped to ${FLOOD_SEL} <= DUMP_CAP=${DUMP_CAP_SUT} (binds AFTER selection)"
fi

# And the dump as a whole stays bounded. On failure, PRINT the unexpected lines — a bare count
# mismatch is not self-diagnosing, and this bound is the one that drifted between local and CI.
FLOOD=$(printf '%s\n' "$OUT6P" | grep -cE '^SOLEUR\| ' || true)
if (( FLOOD > 0 && FLOOD <= DUMP_CEIL )); then
  ok "T6p-total: dump bounded at ${FLOOD} <= ${DUMP_CEIL} lines"
else
  no "T6p-total: dump is ${FLOOD} lines, ceiling ${DUMP_CEIL} = DUMP_CAP ${DUMP_CAP_SUT} + 6 banner/footer lines"$'\n'"$(printf '%s\n' "$OUT6P" | grep -E '^SOLEUR\| ' | grep -vE '^SOLEUR\| FAIL: flood line ' | cut -c1-100)"
fi

# ── T6q: two suites failing at once — both dumped, deterministic order ────────
FIXDIR4="$TMP/fix6q"; mkdir -p "$FIXDIR4"
# `aaa` is deliberately the SLOWEST. With both fixtures exiting instantly, completion order
# happens to equal alphabetical order, so dropping `| sort` from dump_reds survived the whole
# suite. Making the alphabetically-first suite finish LAST is what makes T6r discriminate.
cat > "$FIXDIR4/aaa-red.test.sh" <<'FIXEOF'
#!/usr/bin/env bash
echo "FAIL: marker-from-aaa" >&2
sleep 3
exit 1
FIXEOF
cat > "$FIXDIR4/bbb-red.test.sh" <<'FIXEOF'
#!/usr/bin/env bash
echo "FAIL: marker-from-bbb" >&2
exit 1
FIXEOF
chmod +x "$FIXDIR4"/*.test.sh
mkfixture_wf "$FIXDIR4/wf.yml" "$FIXDIR4/aaa-red.test.sh" "$FIXDIR4/bbb-red.test.sh"
OUT6Q="$(INFRA_WF="$FIXDIR4/wf.yml" SOLEUR_INFRA_DIR="$FIXDIR4" timeout 60 bash "$SUT" 2>&1)" || true
if printf '%s\n' "$OUT6Q" | grep -qF "marker-from-aaa" && printf '%s\n' "$OUT6Q" | grep -qF "marker-from-bbb"; then
  ok "T6q: both concurrently-failing suites are dumped"
else
  no "T6q: a concurrently-failing suite was not dumped"
fi
ORDER_A=$(printf '%s\n' "$OUT6Q" | grep -nF "marker-from-aaa" | head -1 | cut -d: -f1)
ORDER_B=$(printf '%s\n' "$OUT6Q" | grep -nF "marker-from-bbb" | head -1 | cut -d: -f1)
if [[ -n "$ORDER_A" && -n "$ORDER_B" ]] && (( ORDER_A < ORDER_B )); then
  ok "T6r: dump order is deterministic (sorted), not completion order"
else
  no "T6r: dump order follows COMPLETION order, not sorted order (aaa finishes last here)"
fi

# ── T6s: one log file per derived suite (filename-collision probe) ────────────
# Keying the per-suite log on `basename` instead of the sanitised full path would
# collide the moment two suites share a basename across subdirectories.
if printf '%s\n' "$OUT6Q" | grep -qE '^SOLEUR\| .*log dir: '; then
  LD=$(printf '%s\n' "$OUT6Q" | grep -oE 'log dir: .*' | head -1 | sed 's/^log dir: //')
  if [[ -d "$LD" ]] && (( $(find "$LD" -name '*.log' | wc -l) == 2 )); then
    ok "T6s: one log file per derived suite (no filename collision)"
  else
    no "T6s: log file count != derived suite count in $LD"
  fi
else
  no "T6s: could not locate the retained log dir"
fi

# ── T6t: an all-green run emits NO dump and reaps its log dir ─────────────────
FIXDIR5="$TMP/fix6t"; mkdir -p "$FIXDIR5"
cat > "$FIXDIR5/aaa-green.test.sh" <<'FIXEOF'
#!/usr/bin/env bash
echo "ok   - all good"
exit 0
FIXEOF
chmod +x "$FIXDIR5"/*.test.sh
mkfixture_wf "$FIXDIR5/wf.yml" "$FIXDIR5/aaa-green.test.sh"
rc6t=0
OUT6T="$(INFRA_WF="$FIXDIR5/wf.yml" SOLEUR_INFRA_DIR="$FIXDIR5" timeout 60 bash "$SUT" 2>&1)" || rc6t=$?
if (( rc6t == 0 )); then ok "T6t: an all-green run exits 0"
else no "T6t: an all-green run exited $rc6t"; fi
if ! printf '%s\n' "$OUT6T" | grep -qE '^SOLEUR\| '; then
  ok "T6u: an all-green run emits no dump at all"
else
  no "T6u: an all-green run emitted prefixed dump lines"
fi
if printf '%s\n' "$OUT6T" | grep -q '=== registered infra suites: 1 passed, 0 failed, 0 unaccounted (of 1) ==='; then
  ok "T6v: the summary line survives unchanged and unprefixed"
else
  no "T6v: the summary line changed shape — the monitor's tail depends on it"
fi

# ── T7: the accounting assertion closes the pre-existing FALSE GREEN ──────────
# A child whose wrapping `bash -c` is KILLED (OOM under -P 4) emits neither PASS nor
# RED. Before this change RED=0 and the runner exited 0 while printing
# "N passed, 0 failed (of M)" — two numbers that visibly disagree, with nothing
# asserting they must match. A suite could vanish and the gate went green.
FIXDIR6="$TMP/fix7"; mkdir -p "$FIXDIR6"
cat > "$FIXDIR6/aaa-suicide.test.sh" <<'FIXEOF'
#!/usr/bin/env bash
# Kill the wrapping shell the way the OOM killer would: no PASS/RED line is ever emitted.
kill -9 $PPID 2>/dev/null
# 1s, not 5. The wrapper is dead the instant SIGKILL lands; this sleep only has to outlive it.
# But the fixture holds the write end of the xargs pipe open while it sleeps, so `tee` blocks
# for the full duration — and T7 runs once here plus once in each of the 7 mutation children,
# so every second costs 8. Measured: 5s made this suite the slowest registered suite there is.
sleep 1
FIXEOF
cat > "$FIXDIR6/bbb-green.test.sh" <<'FIXEOF'
#!/usr/bin/env bash
exit 0
FIXEOF
chmod +x "$FIXDIR6"/*.test.sh
mkfixture_wf "$FIXDIR6/wf.yml" "$FIXDIR6/aaa-suicide.test.sh" "$FIXDIR6/bbb-green.test.sh"
rc7=0
OUT7="$(INFRA_WF="$FIXDIR6/wf.yml" SOLEUR_INFRA_DIR="$FIXDIR6" timeout 60 bash "$SUT" 2>&1)" || rc7=$?
if (( rc7 != 0 )); then
  ok "T7a: a suite that emits NEITHER PASS nor RED makes the runner exit non-zero (rc=$rc7)"
else
  no "T7a: FALSE GREEN — a vanished suite still exited 0"
fi
if printf '%s\n' "$OUT7" | grep -qiE 'accounting|did not report|unaccounted'; then
  ok "T7b: the runner names the accounting failure"
else
  no "T7b: the runner does not explain that a suite failed to report"
fi
if printf '%s\n' "$OUT7" | grep -qF "aaa-suicide.test.sh"; then
  ok "T7c: the runner names the suite that never reported"
else
  no "T7c: the unaccounted suite is not named"
fi

# ── T8: corpus-conformance — every registered suite's failure marker is readable ──
# Converts a silent degradation into a red test the day a 94th suite lands with a new
# marker shape. Needs no suite execution.
#
# EXTRACTION MUST FOLLOW THE FIVE REAL EMIT SHAPES, measured 2026-08-10 across the 93:
#   double-quoted echo/printf   .................. the majority
#   SINGLE-quoted printf ......................... git-data-rung2-rehearsal, workspaces-luks-*
#   an embedded PYTHON heredoc ................... web-host-provisioner-parity (`print(f"[FAIL] …")`)
#   a SOURCED helper ............................. workspaces-luks-freeze -> workspaces-luks-harness.sh
#   a `SETUP-FAIL:` prefix ....................... zot-image-staleness-mutation
# A double-quote-only scan reports 85/93 and names 8 CONFORMING suites as broken.
#
# EXTRACT PAYLOAD STARTS, NOT ANY QUOTED FRAGMENT. Both assertions below anchor on `^`,
# so they need the text that actually lands at column 0 — the payload of an echo/printf/print,
# not every quoted run in the file. Measured: a whole-file `grep -oE "'[^']*'"` lifts the
# nested fragment out of `ok "A3-nopipe: no '| grep -q' predicate …"`
# (workspaces-luks-verify-root-mtime.test.sh:461) and reports it as a sentinel emitter, when
# the line that suite actually prints begins `[ok] `. An ABSENCE check cannot use a permissive
# extractor: the over-match is indistinguishable from the real thing it exists to find.
# With payload-start extraction + source-following: 93/93 markers, 0 sentinel emitters.
MARKER_ERE='^[[:space:]]*(\[FAIL\]|[A-Z][A-Z0-9]*-FAIL|FAIL)([[:space:]:_-]|$)'
# INFRA_ORPHAN_LIST=/dev/null skips report_orphans' 93 `git grep` calls, which cost ~3.2s and
# contribute nothing here — T5 already covers the orphan scan. Measured: 3.26s -> 0.05s, and
# because T9 re-runs this file in 7 mutation children the saving is paid 8 times.
mapfile -t CORPUS < <(INFRA_ORPHAN_LIST=/dev/null bash "$SUT" --list 2>/dev/null \
  | sed -n 's|^  \(apps/web-platform/infra/.*\.test\.sh\)$|\1|p')

# Non-vacuity floor. Without it, a `--list` that fails or derives nothing leaves both loops
# below empty and BOTH assertions pass — T8a would even print "all 0 registered suites
# conform". That matters most inside T9, where each mutant child runs with SUT=<mutant>: a
# mutation touching derivation would otherwise make T8 pass vacuously in the child.
if (( ${#CORPUS[@]} == 0 )); then
  no "T8: derived ZERO suites — T8a/T8b below would pass vacuously"
fi

payload_starts() {
  { grep -hoE '(echo|printf|print|print[[:space:]]*\()[[:space:]]*(-e[[:space:]]+)?f?"[^"]*"' "$@" \
      | sed -E 's/^[^"]*"//; s/"$//'
    grep -hoE "(echo|printf|print|print[[:space:]]*\()[[:space:]]*(-e[[:space:]]+)?f?'[^']*'" "$@" \
      | sed -E "s/^[^']*'//; s/'\$//"
  } 2>/dev/null
}

# Same reasoning as T2e: this walks all 93 registered suites' SOURCE, which no mutation of the
# runner alters. Skipped in mutation children.
nonconforming=(); sentinel_emitters=()
if [[ -z "${SOLEUR_MUTATION_CHILD:-}" ]]; then
for f in "${CORPUS[@]}"; do
  files=("$f")
  while IFS= read -r inc; do
    [[ -f "apps/web-platform/infra/$inc" ]] && files+=("apps/web-platform/infra/$inc")
  done < <(grep -hoE '^[[:space:]]*(\.|source)[[:space:]]+"?\$\{?SCRIPT_DIR\}?/[A-Za-z0-9._-]+' "$f" 2>/dev/null \
             | grep -oE '[A-Za-z0-9._-]+\.sh$')
  lits="$(payload_starts "${files[@]}")"
  grep -qE "$MARKER_ERE" <<<"$lits" || nonconforming+=("$f")
  grep -qE '^SOLEUR\| ' <<<"$lits" && sentinel_emitters+=("$f")
done

fi
if [[ -n "${SOLEUR_MUTATION_CHILD:-}" ]]; then
  :
elif (( ${#nonconforming[@]} == 0 )); then
  ok "T8a: all ${#CORPUS[@]} registered suites emit a failure marker the runner's ERE can anchor on"
else
  no "T8a: ${#nonconforming[@]} suite(s) emit no marker matching the runner's ERE — their failures would degrade to a blind tail:"$'\n'"$(printf '  %s\n' "${nonconforming[@]}")"
fi

if [[ -n "${SOLEUR_MUTATION_CHILD:-}" ]]; then
  :
elif (( ${#sentinel_emitters[@]} == 0 )); then
  ok "T8b: no registered suite emits the \`| \` sentinel at column 0"
else
  no "T8b: ${#sentinel_emitters[@]} suite(s) emit the \`SOLEUR| \` sentinel at column 0 — the monitor's filter would strip real output:"$'\n'"$(printf '  %s\n' "${sentinel_emitters[@]}")"
fi

# The ERE the test asserts against MUST be the one the runner uses. Otherwise T8a pins a
# regex nothing consumes — the drift-guard-extraction trap.
if grep -qF "$MARKER_ERE" "$SUT"; then
  ok "T8c: the conformance ERE is the literal one the runner uses"
else
  no "T8c: this test's marker ERE has drifted from the runner's"
fi

# ─────────────────────────────────────────────────────────────────────────────
# T9 — MUTATION MATRIX. Every assertion above is a claim that some property holds;
# this is the claim that those assertions could NOTICE it failing.
#
# Why a matrix and not "run against the pre-change runner": that is vacuous by
# construction. The pre-change runner lacks the INFRA_DIR seam, so it derives ZERO
# suites and exits 2 — satisfying every "no dump appeared" assertion trivially, red
# for the wrong reason. Mutating a copy of the CURRENT runner is the only form that
# tests what it claims to.
#
# Runs inside the suite, so it stays a CI gate rather than a one-off done at review.
# ─────────────────────────────────────────────────────────────────────────────
if [[ -z "${SOLEUR_MUTATION_CHILD:-}" ]]; then
  MUTDIR="$TMP/mut"; mkdir -p "$MUTDIR"
  MATRIX_RAN=0
  PRISTINE="$MUTDIR/pristine.sh"; cp "$SUT" "$PRISTINE"

  # mutate <id> <expected-failing-assertion> <python-mutator>
  #
  # Each mutant must (a) LAND — verified by diffing against the pristine copy, because a
  # mutator whose pattern silently stopped matching produces a green child that reads exactly
  # like a killed mutant — and (b) be killed by the NAMED assertion, not merely by some
  # failure somewhere.
  run_mutant() {
    local id="$1" expect="$2" mutator="$3"
    MATRIX_RAN=$(( MATRIX_RAN + 1 ))
    local m="$MUTDIR/$id.sh"
    cp "$PRISTINE" "$m"
    python3 -c "
import sys
p = sys.argv[1]
s = open(p).read()
$mutator
open(p,'w').write(s)
" "$m" || { no "T9[$id]: mutator errored"; return 0; }

    if diff -q "$PRISTINE" "$m" >/dev/null 2>&1; then
      no "T9[$id]: MUTATION DID NOT LAND — this row proves nothing (its pattern stopped matching)"
      return 0
    fi
    chmod +x "$m"

    local out
    out="$(SOLEUR_MUTATION_CHILD=1 SUT="$m" timeout 180 bash "${BASH_SOURCE[0]}" 2>&1)" || true
    # Anchor on the `no()` prefix, not the bare id. `ok()` emits "[ok] <id>: …", so
    # `grep -qF "T6k:"` matched the PASSING line — two rows scored "killed" against a runner
    # that was never mutated (proven with the noop-control row below).
    if grep -qF "[FAIL] $expect" <<<"$out"; then
      if [[ "$id" == noop-control ]]; then
        no "T9[$id]: a comment-only mutation reddened \"$expect\" — the matrix scores noise"
      else
        ok "T9[$id]: killed by \"$expect\""
      fi
    else
      if [[ "$id" == noop-control ]]; then
        ok "T9[$id]: a comment-only mutation is correctly NOT scored as a kill"
      else
        no "T9[$id]: SURVIVED — expected \"$expect\" to fail and it did not"
      fi
    fi
  }

  # Selection anchored on the failure marker → a blind tail. The trap this exists to catch:
  # the RED suite fails EARLY and emits 120 passing lines after, so a tail shows only passes.
  run_mutant anchored-to-tail "T6c: the early failing assertion is absent" \
    "s = s.replace('sel=\"\$(grep -E -A3 --no-group-separator \"\$MARKER_ERE\" \"\$f\" 2>/dev/null)\"; grc=\$?', 'sel=\"\$(tail -n 5 \"\$f\")\"; grc=0')"

  # Selection by position rather than by marker. `tail` was already covered; `head` was not,
  # and it survived the whole suite while the fixture put the marker on line 1.
  run_mutant anchored-to-head "T6c: the early failing assertion is absent" \
    "s = s.replace('sel=\"\$(grep -E -A3 --no-group-separator \"\$MARKER_ERE\" \"\$f\" 2>/dev/null)\"; grc=\$?', 'sel=\"\$(head -n 5 \"\$f\")\"; grc=0')"

  # Drop the sentinel prefix → dumped [FAIL] lines reach the monitor's anchor and its title.
  run_mutant drop-prefix "T6k:" \
    "s = s.replace('} 2>&1 | sed \"s/^/\${SENTINEL_PREFIX}/\"', '} 2>&1')"

  # Skip the dump entirely.
  run_mutant skip-dump "T6c: the early failing assertion is absent" \
    "s = s.replace('  dump_reds\n', '  :\n')"

  # Invert retain/reap → the evidence is deleted on exactly the runs that matter.
  run_mutant invert-reap "T6s:" \
    "s = s.replace('if (( RED == 0 && \${#UNACCOUNTED[@]} == 0 )); then\n  rm -rf \"\$SOLEUR_SUITE_LOGDIR\"\nelse\n  SOLEUR_KEEP_LOGDIR=1\nfi', 'rm -rf \"\$SOLEUR_SUITE_LOGDIR\"')"

  # Drop the cap → one suite with 10,000 marker lines dumps all of them.
  run_mutant drop-cap "T6p: the selection block is" \
    "s = s.replace('mapfile -t -n \"\$DUMP_CAP\" _capped <<<\"\$sel\"', 'mapfile -t _capped <<<\"\$sel\"')"

  # Invert the capture order → `2>&1 >"$f"` sends stderr to the OLD stdout, so the per-suite
  # log holds only stdout and every failure marker is lost from the file the selector reads.
  #
  # KEYED ON T6d, NOT T6c, and the reason is worth recording because it is counter-intuitive:
  # T6c ("the failing assertion appears in the output") does NOT discriminate here. The
  # redirected stderr lands on the runner's INHERITED stdout — the xargs pipe — so the marker
  # text still shows up somewhere in the output and T6c passes. What actually changes is that
  # it arrives UNPREFIXED, by a path that bypasses the dump entirely, which is precisely the
  # dangerous shape: an unprefixed marker reaching the monitor's `^RED |^[FAIL]` anchor and
  # its issue TITLE. Verified 2026-08-10: the inverted runner fails T6d and passes T6c.
  run_mutant invert-capture-order "T6d: the dumped assertion is not sentinel-prefixed" \
    "s = s.replace('bash \"\$s\" >\"\$SOLEUR_SUITE_LOGDIR/\$key.log\" 2>&1; rc=\$?', 'bash \"\$s\" 2>&1 >\"\$SOLEUR_SUITE_LOGDIR/\$key.log\"; rc=\$?')"

  # Delete the accounting assertion → the pre-existing FALSE GREEN returns.
  run_mutant drop-accounting "T7a: FALSE GREEN" \
    "s = s.replace('(( RED == 0 && \${#UNACCOUNTED[@]} == 0 ))\n', '(( RED == 0 ))\n')"

  # POSITIVE CONTROL for the scorer. A comment-only edit changes no behaviour, so every
  # assertion must stay green — if this row reports a kill, the matcher is matching noise and
  # every other row's verdict is worthless.
  run_mutant noop-control "T6c: the early failing assertion is absent" \
    "s = s.replace('# Cap per RED suite.', '# Cap per RED suite (noop-control mutation).')"

  # Anti-vacuity floor for the matrix itself. This counts rows that actually DISPATCHED
  # (incremented inside run_mutant), not `run_mutant` lines in this file — an earlier draft
  # grepped its own source text, which still counts 7 after gutting run_mutant's body to
  # `return 0`, i.e. it could not detect the failure mode its own comment named.
  MATRIX_CALLS=$(grep -c '^  run_mutant ' "${BASH_SOURCE[0]}" || true)
  if (( MATRIX_RAN >= 7 && MATRIX_RAN == MATRIX_CALLS )); then
    ok "T9: mutation matrix dispatched ${MATRIX_RAN} rows (all ${MATRIX_CALLS} call sites ran)"
  else
    no "T9: matrix dispatched ${MATRIX_RAN} of ${MATRIX_CALLS} call sites (expected >= 7, all run)"
  fi
fi

# POSITIVE CONTROL. The floor below counts pass+fail, so it catches a dispatch layer that stops
# emitting — but NOT an `ok()`/`no()` neutered to a no-op, which keeps the count while making
# the suite structurally incapable of reddening. Exercise both and prove each moved.
_p0=$pass; _f0=$fail
ok "positive-control probe" >/dev/null
no "positive-control probe" 2>/dev/null
if (( pass == _p0 + 1 && fail == _f0 + 1 )); then
  pass=$(( _p0 + 1 )); fail=$_f0     # keep the ok, retract the deliberate failure
  echo "[ok] positive control: ok() and no() both mutate their counters"
else
  echo "[FAIL] positive control: ok()/no() do not mutate their counters" >&2
  exit 1
fi

# ANTI-VACUITY FLOOR. Deliberately OUTSIDE the SOLEUR_MUTATION_CHILD guard: with the floor
# inside it, a stray SOLEUR_MUTATION_CHILD in the ambient environment removed the whole matrix
# AND its own floor together, taking the suite from 46 assertions to 38 with exit 0 and nothing
# noticing. A FLOOR, not equality — a new assertion must not require editing this number — but
# set to the current count so it cannot silently absorb a deletion.
# Parent runs the full set; a mutation child legitimately skips the repo-level assertions
# (T2e, T8a/T8b) and the matrix itself, so it carries its own lower floor. Both derived from a
# green run, not from an expectation.
if [[ -n "${SOLEUR_MUTATION_CHILD:-}" ]]; then MIN_ASSERTIONS=36; else MIN_ASSERTIONS=44; fi
TOTAL=$(( pass + fail ))
if (( TOTAL < MIN_ASSERTIONS )); then
  echo "[FAIL] anti-vacuity: only ${TOTAL} assertion(s) ran, expected >= ${MIN_ASSERTIONS}" >&2
  fail=$(( fail + 1 ))
else
  ok "anti-vacuity: ${TOTAL} assertions ran (floor ${MIN_ASSERTIONS})"
fi

echo ""
echo "=== run-registered-suites: ${pass} passed, ${fail} failed ==="
(( fail == 0 ))
