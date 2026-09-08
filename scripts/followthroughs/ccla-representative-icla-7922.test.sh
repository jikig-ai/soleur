#!/usr/bin/env bash
# Companion suite for scripts/followthroughs/ccla-representative-icla-7922.sh.
#
# Registered EXPLICITLY in scripts/test-all.sh under `want_webplat`, not by a
# glob: `scripts/followthroughs/` matches no SUITE_GLOBS entry, and this suite
# needs apps/web-platform/node_modules/.bin/tsx for the parity arm, which the
# `test-scripts` shard does not install.
#
# ── WHY THE PARITY ARM RUNS OVER SYNTHETIC FIXTURES AND NOT THE LIVE REPO ────
# The probe's `--print-epoch` must agree with `resolveCoverageMapNoticeEpoch()`,
# the merge gate's authority. Comparing them against THIS repository would be
# vacuous: the live history contains exactly ONE anchor match, so
# `--first-parent` is a no-op and `head -1 == tail -1` — the arm would pass with
# two of the mutations it exists to catch. It is also unrunnable where it would
# run: CI checks out `test-webplat` SHALLOW, where the probe correctly refuses
# and the TypeScript side returns the graft's own date, so a real-repo arm can
# never be green and deleting the refusal to make it green would have both sides
# agreeing on a wrong value.
#
# So the arm is a DIFFERENTIAL over a family of synthetic repositories — one
# touch, two touches, a merge commit, a rebase replay, a squash, and a graft —
# each of whose SHAPE is asserted before it is used, discriminator-first: not
# "did it build" but "does it actually distinguish the thing it exists to
# distinguish". Every drift vector reddens on at least one member.
set -uo pipefail

# Sandbox harnesses build trees under TMPDIR. /tmp is a machine-global tmpfs
# shared with parallel worktrees; a direct invocation of this suite would
# otherwise inherit it and its verdicts would depend on another session's disk.
export TMPDIR="${TMPDIR:-/var/tmp}"

REPO_ROOT="$(git rev-parse --show-toplevel)"
PROBE="$REPO_ROOT/scripts/followthroughs/ccla-representative-icla-7922.sh"
TSX="$REPO_ROOT/apps/web-platform/node_modules/.bin/tsx"
GATE_TS="$REPO_ROOT/apps/web-platform/scripts/cla-evidence/roster-entry-gate.ts"

ANCHOR="public corporate coverage map"
DOC_REL="docs/legal/individual-cla.md"
ROSTER_REL="apps/cla-evidence/roster/ccla-roster.json"

# Pinned so every epoch in this file is a known constant rather than "now".
D_BASE="2026-01-01T00:00:00Z"      # the pre-anchor commit
D_ANCHOR="2026-06-01T12:00:00Z"    # the commit that introduces the anchor -> THE EPOCH
D_SECOND="2026-08-01T09:00:00Z"    # a second touch, strictly later
# git renders `%cI` with a `Z` designator for UTC, not `+00:00` -- measured,
# and it matches what the live repository derives.
EPOCH_EXPECT="2026-06-01T12:00:00Z"

TS_PRE="2026-05-01T00:00:00Z"      # strictly before the epoch
TS_POST="2026-07-01T00:00:00Z"     # strictly after the epoch
TS_EXACT="2026-06-01T12:00:00Z"    # exactly AT the epoch (pins >= and not >)

passes=0
fails=0
cases=0
pass() { passes=$((passes + 1)); echo "[ok]   $1"; }
fail() { fails=$((fails + 1)); echo "[FAIL] $1"; }
abort() { printf 'harness: %s\n' "$1" >&2; exit 2; }

[[ -x "$PROBE" ]] || abort "the probe is missing or not executable at $PROBE"

WORK="$(mktemp -d -t ccla-watch-test.XXXXXXXX)" || abort "mktemp -d failed"
trap 'rm -rf "$WORK"' EXIT
OUT="$WORK/out.txt"
ERR="$WORK/err.txt"

# --- instrument self-test: drive both counters once and refuse to continue ---
# --- unless both actually moved. A suite whose helpers are inert reports a
# --- clean run having asserted nothing.
pass "instrument self-test (pass path)"
fail "instrument self-test (fail path — EXPECTED, discounted below)"
if [[ "$passes" -ne 1 || "$fails" -ne 1 ]]; then
  abort "instrument self-test did not move both counters (passes=$passes fails=$fails)"
fi
passes=0; fails=0
echo "--- instrument verified; counters reset ---"

# ---------------------------------------------------------------------------
# Fixture construction.
# ---------------------------------------------------------------------------
# `git -c` FLAGS ONLY — this suite performs no `git config` write. A fixture
# builder that writes config has, on this repo's history, written into the
# caller's live configuration. GIT_CONFIG_GLOBAL/SYSTEM are pinned to /dev/null
# so the operator's own identity, signing settings, hooks and aliases cannot
# reach a fixture and make its shape depend on the machine.
g() {
  GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null \
  git -c user.name=Fixture -c user.email=fixture@example.invalid \
      -c commit.gpgsign=false -c tag.gpgsign=false \
      -c init.defaultBranch=main -c advice.detachedHead=false \
      -c protocol.file.allow=always "$@"
}

# Commit with BOTH dates pinned. Pinning only the author date leaves the
# committer date at "now", which makes the %cI-vs-%aI mutation invisible on
# every fixture except the rebase one.
gcommit() { # $1=dir $2=author-date $3=committer-date $4=message
  GIT_AUTHOR_DATE="$2" GIT_COMMITTER_DATE="$3" g -C "$1" commit -q -m "$4"
}

write_doc() { # $1=dir $2=occurrences of the anchor
  local d="$1" n="$2" i
  mkdir -p "$d/$(dirname "$DOC_REL")"
  {
    printf '# Individual CLA (fixture)\n\n'
    printf 'Section 0 preamble that carries no anchor at all.\n\n'
    for ((i = 0; i < n; i++)); do
      printf 'Your signature is recorded in the %s, paragraph %s.\n' "$ANCHOR" "$i"
    done
  } > "$d/$DOC_REL"
}

write_roster() { # $1=dir $2=json
  mkdir -p "$1/$(dirname "$ROSTER_REL")"
  printf '%s\n' "$2" > "$1/$ROSTER_REL"
}

# The ledger lives on an orphan branch in a bare origin, exactly as it does
# upstream, so the probe's refspec fetch is exercised for real rather than
# stubbed.
set_ledger() { # $1=fixture-dir $2=ledger-json
  local d="$1" json="$2"
  rm -rf "$d/ledgersrc"
  mkdir -p "$d/ledgersrc/signatures"
  printf '%s\n' "$json" > "$d/ledgersrc/signatures/cla.json"
  g -C "$d/ledgersrc" init -q
  g -C "$d/ledgersrc" add -A
  gcommit "$d/ledgersrc" "$D_BASE" "$D_BASE" "ledger"
  g -C "$d/ledgersrc" branch -q -M cla-signatures
  g -C "$d/ledgersrc" push -q --force "$d/origin.git" cla-signatures
}

LEDGER_EMPTY='{"signedContributors":[]}'
ledger_of() { # $1..$n = "id:created_at" pairs
  local out="" p id ts
  for p in "$@"; do
    id="${p%%:*}"; ts="${p#*:}"
    [[ -n "$out" ]] && out="$out,"
    out="$out{\"id\":$id,\"login\":\"fixture-login-$id\",\"name\":\"Fixture Person $id\",\"created_at\":\"$ts\"}"
  done
  printf '{"signedContributors":[%s]}' "$out"
}
ROSTER_EMPTY='{"schema_version":"1.0","organizations":[]}'
roster_with() { # $1=id $2=removed_at-json-literal
  printf '{"schema_version":"1.0","organizations":[{"legal_name":"Fixture Ltd","record_ref":"CCLA-0001","representatives":[{"id":%s,"login":"fixture-login-%s","authorized_from":"%s","removed_at":%s}]}]}' \
    "$1" "$1" "$D_ANCHOR" "$2"
}

# $1 = dir, $2 = shape
build_fixture() {
  local d="$1" shape="$2"
  mkdir -p "$d/repo"
  g -C "$d/repo" init -q
  g init --bare -q "$d/origin.git"
  g -C "$d/repo" remote add origin "$d/origin.git"

  write_doc "$d/repo" 0
  write_roster "$d/repo" "$ROSTER_EMPTY"
  g -C "$d/repo" add -A
  gcommit "$d/repo" "$D_BASE" "$D_BASE" "base: no anchor yet"

  case "$shape" in
    one-touch|squash)
      write_doc "$d/repo" 1
      g -C "$d/repo" add -A
      gcommit "$d/repo" "$D_ANCHOR" "$D_ANCHOR" "introduce the coverage-map notice"
      ;;
    two-touch)
      write_doc "$d/repo" 1
      g -C "$d/repo" add -A
      gcommit "$d/repo" "$D_ANCHOR" "$D_ANCHOR" "introduce the coverage-map notice"
      write_doc "$d/repo" 2
      g -C "$d/repo" add -A
      gcommit "$d/repo" "$D_SECOND" "$D_SECOND" "a SECOND occurrence of the anchor"
      ;;
    merge)
      # The anchor is introduced on a SIDE BRANCH whose own date is early, and
      # reaches main only through a --no-ff merge dated later. `--first-parent`
      # is the only thing that moves the epoch to the merge.
      g -C "$d/repo" checkout -q -b notice
      write_doc "$d/repo" 1
      g -C "$d/repo" add -A
      gcommit "$d/repo" "2026-03-03T03:03:03Z" "2026-03-03T03:03:03Z" "branch: introduce the notice"
      g -C "$d/repo" checkout -q main
      GIT_AUTHOR_DATE="$D_ANCHOR" GIT_COMMITTER_DATE="$D_ANCHOR" \
        g -C "$d/repo" merge -q --no-ff -m "merge the notice branch" notice
      ;;
    rebase)
      # The anchor commit keeps its old AUTHOR date and is replayed with a new
      # COMMITTER date. GIT_COMMITTER_DATE is pinned ON THE REBASE ITSELF —
      # without that the replayed committer date is "now", both sides of the
      # differential shift together, and the %cI-vs-%aI row cannot redden.
      g -C "$d/repo" checkout -q -b notice
      write_doc "$d/repo" 1
      g -C "$d/repo" add -A
      gcommit "$d/repo" "2026-02-02T02:02:02Z" "2026-02-02T02:02:02Z" "branch: introduce the notice"
      g -C "$d/repo" checkout -q main
      printf 'unrelated main-side change\n' > "$d/repo/UNRELATED.md"
      g -C "$d/repo" add -A
      gcommit "$d/repo" "2026-04-04T04:04:04Z" "2026-04-04T04:04:04Z" "main: unrelated"
      g -C "$d/repo" checkout -q notice
      GIT_COMMITTER_DATE="$D_ANCHOR" g -C "$d/repo" rebase -q main >/dev/null 2>&1
      g -C "$d/repo" checkout -q main
      g -C "$d/repo" merge -q --ff-only notice
      ;;
    no-anchor)
      write_doc "$d/repo" 0
      printf 'a change that never mentions the phrase\n' >> "$d/repo/$DOC_REL"
      g -C "$d/repo" add -A
      gcommit "$d/repo" "$D_ANCHOR" "$D_ANCHOR" "no anchor is ever introduced"
      ;;
  esac

  set_ledger "$d" "$LEDGER_EMPTY"
}

# $1 = repo dir, rest = probe argv. Runs under `env -i`, as the sweeper does.
# PATH and HOME are what the sweeper passes; TMPDIR is added so the probe's own
# scratch lands beside this sandbox rather than on the shared /tmp tmpfs.
# THE INVARIANT, ENFORCED ON EVERY RUN RATHER THAN LEFT AS PROSE. exit 0 is the
# sweeper's CLOSE verb on a legal tracker and exit 1 its FAIL-and-reopen
# trigger; the probe header says it takes neither on any path, and nothing
# asserted it. Folding the check in here means every existing and future arm
# enforces it for free across the whole fixture family.
assert_never_close_verb() {
  if [[ "$1" == "0" || "$1" == "1" ]]; then
    cases=$((cases + 1))
    fail "INVARIANT: the probe returned rc=$1 ($2) — 0 is the sweeper's close verb and 1 its reopen trigger; neither may EVER be taken"
  fi
}

# GIT_CONFIG_* pinned for the SAME reason the fixture builder pins them: without
# it the developer's ~/.gitconfig (url.insteadOf, fetch.prune, core.hooksPath,
# remote.origin.tagOpt) is an uncontrolled operand of every measurement, so the
# FR16 tag arm and the QG10 shallow arm become machine-dependent. The builder
# got this right; the measurement did not.
run_probe() {
  local d="$1"; shift
  local rc=0
  ( cd "$d" && env -i PATH="$PATH" HOME="$HOME" TMPDIR="$TMPDIR" \
      GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null \
      bash "$PROBE" "$@" ) > "$OUT" 2> "$ERR" || rc=$?
  # >&2 is load-bearing: this helper reports through fail(), which writes to
  # STDOUT, and run_probe's stdout IS the returned rc. Without the redirect the
  # violation text is spliced into the value every caller compares against, so
  # the arm still reddens but every message downstream is garbled.
  assert_never_close_verb "$rc" "run_probe $*" >&2
  echo "$rc"
}
# MATERIALISED into a string, never piped into `grep -q`. Under `pipefail` a
# `producer | grep -q` flakes to a FALSE NEGATIVE when the match is early:
# grep closes the pipe on the first hit, the producer takes SIGPIPE (141),
# and pipefail makes the pipeline non-zero -- so a leak that WAS found reads
# as "no leak". Every FR15 arm below depends on that answer.
both() { cat "$OUT" "$ERR"; }

# ---------------------------------------------------------------------------
# Build the family, and assert each member's DISCRIMINATING property.
# ---------------------------------------------------------------------------
FAMILY=(one-touch two-touch merge rebase squash)
for shape in "${FAMILY[@]}" no-anchor; do
  build_fixture "$WORK/$shape" "$shape" >/dev/null 2>&1 \
    || abort "could not build the $shape fixture"
done

fx() { printf '%s/%s/repo' "$WORK" "$1"; }
anchor_matches() { g -C "$1" log --first-parent -S"$ANCHOR" --format=%cI -- "$DOC_REL" | grep -c . || true; }

# one-touch: exactly one match, so it is the baseline every other shape is read
# against.
cases=$((cases + 1))
[[ "$(anchor_matches "$(fx one-touch)")" == "1" ]] \
  && pass "fixture one-touch: exactly one anchor-introducing commit" \
  || fail "fixture one-touch did not build with a single anchor match"

# two-touch: TWO matches AND two DIFFERENT committer dates. Count alone is not
# the discriminator — if both dates were equal, oldest-vs-newest would be
# indistinguishable and mutation row 4 could not redden.
tt_n=$(anchor_matches "$(fx two-touch)")
tt_dates=$(g -C "$(fx two-touch)" log --first-parent -S"$ANCHOR" --format=%cI -- "$DOC_REL" | sort -u | grep -c . || true)
cases=$((cases + 1))
[[ "$tt_n" == "2" && "$tt_dates" == "2" ]] \
  && pass "fixture two-touch: two anchor matches carrying two DISTINCT dates" \
  || fail "fixture two-touch: matches=$tt_n distinct-dates=$tt_dates (need 2 and 2)"

# merge: the merge commit has >= 2 parents AND the non---first-parent walk
# yields a DIFFERENT oldest match. Without the second half, dropping
# --first-parent would change nothing observable.
mg_parents=$(g -C "$(fx merge)" log --format=%P -1 HEAD | wc -w)
mg_fp=$(g -C "$(fx merge)" log --first-parent -S"$ANCHOR" --format=%cI -- "$DOC_REL" | tail -1)
mg_all=$(g -C "$(fx merge)" log -S"$ANCHOR" --format=%cI -- "$DOC_REL" | tail -1)
cases=$((cases + 1))
[[ "$mg_parents" -ge 2 && -n "$mg_fp" && "$mg_fp" != "$mg_all" ]] \
  && pass "fixture merge: a real merge commit whose --first-parent epoch DIFFERS from the plain walk" \
  || fail "fixture merge: parents=$mg_parents first-parent=$mg_fp plain=$mg_all (need >=2 and differing)"

# rebase: the replayed commit has ONE parent and %aI != %cI. Equal dates would
# make the %cI-vs-%aI row vacuous.
rb_sha=$(g -C "$(fx rebase)" log --first-parent -S"$ANCHOR" --format=%H -- "$DOC_REL" | tail -1)
rb_a=$(g -C "$(fx rebase)" log -1 --format=%aI "$rb_sha")
rb_c=$(g -C "$(fx rebase)" log -1 --format=%cI "$rb_sha")
rb_parents=$(g -C "$(fx rebase)" log -1 --format=%P "$rb_sha" | wc -w)
cases=$((cases + 1))
[[ "$rb_parents" == "1" && -n "$rb_a" && "$rb_a" != "$rb_c" ]] \
  && pass "fixture rebase: a replayed commit with one parent whose author and committer dates DIFFER" \
  || fail "fixture rebase: parents=$rb_parents aI=$rb_a cI=$rb_c (need 1 and differing)"

# no-anchor: zero matches, so the empty-pickaxe path is reachable.
cases=$((cases + 1))
[[ "$(anchor_matches "$(fx no-anchor)")" == "0" ]] \
  && pass "fixture no-anchor: the pickaxe matches nothing (the empty-result path is reachable)" \
  || fail "fixture no-anchor built with an anchor match"

# ---------------------------------------------------------------------------
# Epoch parity with the TypeScript authority — per fixture.
# ---------------------------------------------------------------------------
# FAIL, never skip, when tsx is absent: a missing dependency that silently
# removes the only cross-implementation check is worse than a red suite.
cases=$((cases + 1))
[[ -x "$TSX" ]] \
  && pass "the TypeScript authority's runtime is present (the parity arm below is live, not skipped)" \
  || fail "apps/web-platform/node_modules/.bin/tsx is MISSING — the parity arm cannot run; this suite belongs in TEST_GROUP=webplat (npm ci --prefix apps/web-platform)"

if [[ -x "$TSX" ]]; then
  # ONE tsx start for the whole family rather than six cold starts.
  PARITY_JSON="$WORK/parity.json"
  {
    printf 'import {resolveCoverageMapNoticeEpoch} from %s;\n' "\"$GATE_TS\""
    printf 'const out={};\n'
    for shape in "${FAMILY[@]}"; do
      printf 'try{out[%s]=resolveCoverageMapNoticeEpoch(%s);}catch(e){out[%s]="THREW";}\n' \
        "\"$shape\"" "\"$(fx "$shape")\"" "\"$shape\""
    done
    printf 'console.log(JSON.stringify(out));\n'
  } > "$WORK/parity.ts"
  if "$TSX" "$WORK/parity.ts" > "$PARITY_JSON" 2>"$WORK/parity.err"; then
    for shape in "${FAMILY[@]}"; do
      ts_epoch=$(jq -r --arg s "$shape" '.[$s] // "ABSENT"' "$PARITY_JSON")
      sh_rc=$(run_probe "$(fx "$shape")" --print-epoch)
      sh_epoch=$(cat "$OUT")
      cases=$((cases + 1))
      if [[ "$sh_rc" == "2" && -n "$ts_epoch" && "$ts_epoch" != "THREW" && "$sh_epoch" == "$ts_epoch" ]]; then
        pass "parity[$shape]: --print-epoch byte-equals resolveCoverageMapNoticeEpoch ($sh_epoch)"
      else
        fail "parity[$shape]: probe='$sh_epoch' (rc=$sh_rc) vs authority='$ts_epoch'"
      fi
    done
  else
    cases=$((cases + 1))
    fail "the TypeScript authority could not be run over the fixture family: $(head -c 200 "$WORK/parity.err")"
  fi
fi

# The epoch is the pinned constant, not merely "whatever both sides agree on" —
# two implementations sharing one bug would otherwise agree.
rc=$(run_probe "$(fx one-touch)" --print-epoch)
cases=$((cases + 1))
[[ "$rc" == "2" && "$(cat "$OUT")" == "$EPOCH_EXPECT" ]] \
  && pass "the derived epoch is the PINNED fixture constant ($EPOCH_EXPECT), not just a value both sides share" \
  || fail "epoch on one-touch: got '$(cat "$OUT")' rc=$rc, expected $EPOCH_EXPECT"

# ---------------------------------------------------------------------------
# The verdict paths.
# ---------------------------------------------------------------------------
F1="$(fx one-touch)"; D1="$WORK/one-touch"

# all pre-epoch -> NOT YET, carrying the CHECKED count.
set_ledger "$D1" "$(ledger_of "111:$TS_PRE" "222:$TS_PRE")" >/dev/null 2>&1
rc=$(run_probe "$F1")
cases=$((cases + 1))
[[ "$rc" == "2" ]] && pass "all-pre-epoch ledger reports NOT YET (rc=2)" \
  || fail "all-pre-epoch: expected rc=2, got $rc — $(head -c 160 "$OUT")"
cases=$((cases + 1))
grep -q 'NOT YET: 2 signature(s) checked' "$OUT" \
  && pass "the NOT YET line carries the number of entries CHECKED (0-uncovered and 0-examined cannot render alike)" \
  || fail "NOT YET line does not carry the checked count: $(head -c 160 "$OUT")"

# one uncovered post-epoch signature -> ACTION.
set_ledger "$D1" "$(ledger_of "111:$TS_PRE" "222:$TS_POST")" >/dev/null 2>&1
rc=$(run_probe "$F1")
cases=$((cases + 1))
[[ "$rc" == "5" ]] && pass "an uncovered post-epoch signature reports ACTION (rc=5)" \
  || fail "uncovered post-epoch: expected rc=5, got $rc — $(head -c 160 "$OUT")"
cases=$((cases + 1))
grep -q 'ACTION: 1 signature' "$OUT" \
  && pass "the ACTION line carries the count of qualifying signatures" \
  || fail "ACTION line does not carry the count: $(head -c 160 "$OUT")"
cases=$((cases + 1))
grep -q 'NOT authority to record' "$OUT" \
  && pass "the ACTION line says it is NOT authority to record, and names the instrument's designation list (FR13)" \
  || fail "ACTION line does not disclaim recording authority"

# post-epoch but ALREADY a live representative -> NOT YET.
write_roster "$D1/repo" "$(roster_with 222 null)"
rc=$(run_probe "$F1")
cases=$((cases + 1))
[[ "$rc" == "2" ]] && pass "a post-epoch signer already on the roster is COVERED (rc=2)" \
  || fail "already-a-representative: expected rc=2, got $rc — $(head -c 160 "$OUT")"

# covered only by a WITHDRAWN row -> still covered. A live-only term would leave
# a withdrawn id in the count forever, pinning it at >= 1 and destroying the
# only signal this probe produces.
write_roster "$D1/repo" "$(roster_with 222 '"2026-08-09T00:00:00Z"')"
rc=$(run_probe "$F1")
cases=$((cases + 1))
[[ "$rc" == "2" ]] && pass "a WITHDRAWN roster row still counts as covered (rc=2) — the count cannot latch" \
  || fail "withdrawn-designation: expected rc=2, got $rc — $(head -c 160 "$OUT")"

# H4 (must-PASS, non-canonical): created_at EXACTLY at the epoch -> ACTION.
# Pins `>=` rather than `>`; an off-by-one here silently refuses the one person
# who signed at the notice moment.
write_roster "$D1/repo" "$ROSTER_EMPTY"
set_ledger "$D1" "$(ledger_of "333:$TS_EXACT")" >/dev/null 2>&1
rc=$(run_probe "$F1")
cases=$((cases + 1))
[[ "$rc" == "5" ]] && pass "H4 must-PASS: created_at EXACTLY at the epoch qualifies (rc=5) — pins >= and not >" \
  || fail "H4: exact-epoch signature did not qualify (rc=$rc)"

# ---------------------------------------------------------------------------
# The CANNOT ESTABLISH states. Every one asserts the REASON substring, not only
# rc=3 — six branches produce 3, so rc alone does not discriminate between them.
# ---------------------------------------------------------------------------
set_ledger "$D1" "$LEDGER_EMPTY" >/dev/null 2>&1

# unparseable ledger
printf '<!DOCTYPE html><html>gateway error</html>' > "$D1/ledgersrc/signatures/cla.json"
g -C "$D1/ledgersrc" add -A >/dev/null 2>&1
gcommit "$D1/ledgersrc" "$D_BASE" "$D_BASE" "garbage" >/dev/null 2>&1
g -C "$D1/ledgersrc" push -q --force "$D1/origin.git" cla-signatures >/dev/null 2>&1
rc=$(run_probe "$F1")
cases=$((cases + 1))
[[ "$rc" == "3" ]] && pass "an unparseable ledger reports CANNOT ESTABLISH (rc=3)" \
  || fail "unparseable ledger: expected rc=3, got $rc"
cases=$((cases + 1))
grep -q 'CANNOT ESTABLISH: the ICLA signature ledger is UNUSABLE' "$OUT" \
  && pass "the unusable-ledger refusal names the reference set, with its own reason string" \
  || fail "unusable-ledger refusal does not carry its reason: $(head -c 160 "$OUT")"
cases=$((cases + 1))
grep -qE 'have not signed|has not signed' "$OUT" \
  && fail "an unusable ledger was reported as a finding about a person" \
  || pass "an unusable ledger is NOT reported as a finding about any account"

# a malformed created_at -> refuse, and the offending VALUE must appear in
# NEITHER stream. jq puts the value into its own error text, and the sweeper
# republishes that verbatim into a public comment.
POISON="NOTADATE-fixture-login-444-ident"
set_ledger "$D1" "{\"signedContributors\":[{\"id\":444,\"login\":\"fixture-login-444\",\"created_at\":\"$POISON\"}]}" >/dev/null 2>&1
rc=$(run_probe "$F1")
cases=$((cases + 1))
[[ "$rc" == "3" ]] && pass "a malformed created_at reports CANNOT ESTABLISH (rc=3), never a default of 0" \
  || fail "malformed created_at: expected rc=3, got $rc — $(head -c 160 "$OUT")"
cases=$((cases + 1))
grep -q 'CANNOT ESTABLISH: 1 ledger entr' "$OUT" \
  && pass "the malformed-timestamp refusal reports a COUNT" \
  || fail "malformed-timestamp refusal does not report a count: $(head -c 160 "$OUT")"
cases=$((cases + 1))
if grep -qF "$POISON" <<<"$(both)"; then
  fail "FR15: the offending created_at VALUE reached an output stream — the sweeper would publish it"
else
  pass "FR15: the offending created_at value appears in NEITHER stdout nor stderr"
fi
cases=$((cases + 1))
if grep -qE 'fixture-login-444|Fixture Person' <<<"$(both)"; then
  fail "FR15: a ledger login or name reached an output stream"
else
  pass "FR15: no ledger login or name reaches any output stream on the refusal path"
fi

# malformed roster
set_ledger "$D1" "$(ledger_of "111:$TS_POST")" >/dev/null 2>&1
printf 'not json at all' > "$D1/repo/$ROSTER_REL"
rc=$(run_probe "$F1")
cases=$((cases + 1))
[[ "$rc" == "3" ]] && pass "a malformed coverage map reports CANNOT ESTABLISH (rc=3), not 'everyone is uncovered'" \
  || fail "malformed roster: expected rc=3, got $rc — $(head -c 160 "$OUT")"
cases=$((cases + 1))
grep -q 'CANNOT ESTABLISH: the coverage map' "$OUT" \
  && pass "the malformed-roster refusal names the coverage map" \
  || fail "malformed-roster refusal does not name the coverage map: $(head -c 160 "$OUT")"
write_roster "$D1/repo" "$ROSTER_EMPTY"

# the empty pickaxe -> refuse, and specifically do NOT silently take today as
# the epoch (`date -u -d ""` returns today).
rc=$(run_probe "$(fx no-anchor)")
cases=$((cases + 1))
[[ "$rc" == "3" ]] && pass "a reworded/absent anchor reports CANNOT ESTABLISH (rc=3)" \
  || fail "no-anchor fixture: expected rc=3, got $rc — $(head -c 160 "$OUT")"
cases=$((cases + 1))
grep -q 'CANNOT ESTABLISH: the coverage-map notice anchor was not found' "$OUT" \
  && pass "the empty-pickaxe refusal names the missing anchor" \
  || fail "empty-pickaxe refusal does not name the anchor: $(head -c 160 "$OUT")"

# every refusal ends in an addressee tag
cases=$((cases + 1))
grep -q 'Operator:' "$OUT" \
  && pass "every CANNOT ESTABLISH line ends in an addressee tag (FR14)" \
  || fail "a CANNOT ESTABLISH line carries no addressee tag"

# usage
rc=$(run_probe "$F1" --print-epock)
cases=$((cases + 1))
[[ "$rc" == "64" ]] && pass "an unrecognised argv exits 64 and cannot fall through to a verdict (FR17)" \
  || fail "unrecognised argv: expected rc=64, got $rc"

# ---------------------------------------------------------------------------
# Repository-state guarantees (P8 / NFR1 / FR16 / QG10).
# ---------------------------------------------------------------------------
TAGFX="$WORK/tagged"
build_fixture "$TAGFX" one-touch >/dev/null 2>&1 || abort "could not build the tag-origin fixture"
# Tags on the ORIGIN, created BEFORE the probe runs — the pre-condition the
# --no-tags row needs, asserted rather than assumed.
GIT_COMMITTER_DATE="$D_BASE" g -C "$TAGFX/ledgersrc" tag -a -m t v-fixture-1 >/dev/null 2>&1
GIT_COMMITTER_DATE="$D_BASE" g -C "$TAGFX/ledgersrc" tag -a -m t v-fixture-2 >/dev/null 2>&1
g -C "$TAGFX/ledgersrc" push -q --tags "$TAGFX/origin.git" >/dev/null 2>&1
origin_tags=$(g -C "$TAGFX/origin.git" show-ref --tags | grep -c . || true)
cases=$((cases + 1))
[[ "$origin_tags" -ge 2 ]] \
  && pass "fixture tag-origin: the origin carries tags BEFORE the probe runs ($origin_tags)" \
  || fail "fixture tag-origin: the origin carries no tags, so the --no-tags row would be vacuous"

set_ledger "$TAGFX" "$(ledger_of "111:$TS_PRE")" >/dev/null 2>&1
g -C "$TAGFX/ledgersrc" push -q --tags "$TAGFX/origin.git" >/dev/null 2>&1
rc=$(run_probe "$TAGFX/repo")
local_tags=$(g -C "$TAGFX/repo" show-ref --tags | grep -c . || true)
cases=$((cases + 1))
[[ "$local_tags" == "0" ]] \
  && pass "FR16: the ledger fetch creates ZERO tags in the repository it reads" \
  || fail "FR16: the probe's fetch wrote $local_tags tag(s) into the fixture"
cases=$((cases + 1))
[[ ! -e "$TAGFX/repo/.git/shallow" ]] \
  && pass "QG10: the probe leaves no .git/shallow behind (the fetch omits --depth=1)" \
  || fail "QG10: the probe's fetch flipped the fixture repository to shallow"
cases=$((cases + 1))
[[ ! -e "$TAGFX/repo/.git/FETCH_HEAD" ]] \
  && pass "the probe's fetch writes no FETCH_HEAD into the shared common dir" \
  || fail "the probe's fetch wrote FETCH_HEAD"

# grafted: a genuinely shallow clone. `git clone --depth=1` SILENTLY IGNORES
# --depth on a plain local path, so this must go through file:// or the fixture
# is not grafted and its row reports the baseline.
GRAFT="$WORK/graft"
g clone --quiet --depth=1 "file://$WORK/one-touch/repo" "$GRAFT" >/dev/null 2>&1 \
  || abort "could not build the grafted fixture"
graft_shallow=$(g -C "$GRAFT" rev-parse --is-shallow-repository)
graft_parent_rc=0
g -C "$GRAFT" rev-parse --verify --quiet HEAD^ >/dev/null 2>&1 || graft_parent_rc=$?
cases=$((cases + 1))
[[ "$graft_shallow" == "true" && "$graft_parent_rc" != "0" ]] \
  && pass "fixture graft: genuinely shallow (HEAD^ does not resolve) — the file:// clone took" \
  || fail "fixture graft: is-shallow=$graft_shallow HEAD^rc=$graft_parent_rc — --depth was ignored, the row below is vacuous"
g -C "$GRAFT" remote set-url origin "$WORK/one-touch/origin.git" >/dev/null 2>&1
rc=$(run_probe "$GRAFT")
cases=$((cases + 1))
[[ "$rc" == "3" ]] \
  && pass "a grafted checkout is REFUSED (rc=3) rather than deriving the graft's own date" \
  || fail "grafted checkout: expected rc=3, got $rc — $(head -c 160 "$OUT")"
cases=$((cases + 1))
grep -qE 'CANNOT ESTABLISH: the commit that appears to introduce' "$OUT" \
  && pass "the graft refusal names the missing parent and the fetch-depth remedy" \
  || fail "graft refusal does not name the cause: $(head -c 160 "$OUT")"

# ===========================================================================
# Guard 2 MUTATION MATRIX.
#
# Each row copies the probe, edits the copy, ASSERTS THE MUTATION LANDED, and
# then asserts its effect on the fixture that can see it. Every exit-3 row
# asserts the CANNOT ESTABLISH *reason* substring and not merely `rc == 3`: six
# distinct branches produce 3, so rc alone cannot tell them apart and a row that
# checked only rc would pass against a probe refusing for the wrong cause.
# ===========================================================================
MUT="$WORK/probe.mutant.sh"
m_begin() { cp "$PROBE" "$MUT" || abort "could not copy the probe"; }
m_landed() {
  cases=$((cases + 1))
  if diff -q "$PROBE" "$MUT" >/dev/null; then
    fail "$1: the mutation did NOT land (mutant identical to the probe) — its verdict below would be the baseline"
    return 1
  fi
  pass "$1: mutation landed"
  return 0
}
run_any() { # $1=probe $2=repo-dir, rest = argv
  local pr="$1" d="$2"; shift 2
  local rc=0
  ( cd "$d" && env -i PATH="$PATH" HOME="$HOME" TMPDIR="$TMPDIR" \
      GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null \
      bash "$pr" "$@" ) > "$OUT" 2> "$ERR" || rc=$?
  echo "$rc"
}

# Re-seed the canonical fixtures the rows below read.
set_ledger "$D1" "$(ledger_of "111:$TS_PRE" "222:$TS_PRE")" >/dev/null 2>&1
write_roster "$D1/repo" "$ROSTER_EMPTY"

# --- M1: hardcode the epoch to a far-past constant --------------------------
m_begin
python3 - "$MUT" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read()
old='EPOCH_S="$(date -u -d "$EPOCH_ISO" +%s 2>/dev/null)"'
assert s.count(old)==1, s.count(old)
s=s.replace(old,'EPOCH_S="$(date -u -d "1970-01-02T00:00:00Z" +%s 2>/dev/null)"')
open(p,"w").write(s)
PY
if m_landed "G2-M1 (far-past constant epoch)"; then
  rc=$(run_any "$MUT" "$F1")
  cases=$((cases + 1))
  [[ "$rc" == "5" ]] \
    && pass "G2-M1: a hardcoded far-past epoch makes every pre-epoch signature qualify (rc=5 vs the baseline's 2)" \
    || fail "G2-M1: expected the mutant to report ACTION on an all-pre-epoch ledger, got rc=$rc"
fi

# --- M2: drop --first-parent ------------------------------------------------
m_begin
python3 - "$MUT" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read()
old='git log --first-parent -S"$NOTICE_ANCHOR"'
assert s.count(old)==1
s=s.replace(old,'git log -S"$NOTICE_ANCHOR"')
open(p,"w").write(s)
PY
if m_landed "G2-M2 (no --first-parent)"; then
  base=$(run_any "$PROBE" "$(fx merge)" --print-epoch); base_e=$(cat "$OUT")
  mrc=$(run_any "$MUT" "$(fx merge)" --print-epoch); mut_e=$(cat "$OUT")
  cases=$((cases + 1))
  [[ "$base" == "2" && "$base_e" != "$mut_e" ]] \
    && pass "G2-M2: dropping --first-parent moves the epoch on the MERGE fixture ($base_e -> $mut_e)" \
    || fail "G2-M2: the merge fixture did not discriminate (base=$base_e mutant=$mut_e)"
  # ...and it is INVISIBLE on the single-match shape, which is why a live-repo
  # parity arm could not catch this row.
  run_any "$PROBE" "$F1" --print-epoch >/dev/null; b1=$(cat "$OUT")
  run_any "$MUT" "$F1" --print-epoch >/dev/null; m1=$(cat "$OUT")
  cases=$((cases + 1))
  [[ "$b1" == "$m1" ]] \
    && pass "G2-M2 control: the same mutation is INVISIBLE on a one-match history — the live repo could not catch it" \
    || fail "G2-M2 control: the one-touch fixture unexpectedly discriminated (b=$b1 m=$m1)"
fi

# --- M3: %cI -> %aI ---------------------------------------------------------
m_begin
python3 - "$MUT" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read()
old='''  --format='%H %cI' -- "$NOTICE_DOC" 2>/dev/null)" \\'''
assert s.count(old)==1, s.count(old)
s=s.replace(old, old.replace("%H %cI", "%H %aI"))
open(p,"w").write(s)
PY
if m_landed "G2-M3 (%cI -> %aI)"; then
  run_any "$PROBE" "$(fx rebase)" --print-epoch >/dev/null; b=$(cat "$OUT")
  run_any "$MUT" "$(fx rebase)" --print-epoch >/dev/null; m=$(cat "$OUT")
  cases=$((cases + 1))
  [[ -n "$b" && "$b" != "$m" ]] \
    && pass "G2-M3: %aI moves the epoch on the REBASE fixture ($b -> $m)" \
    || fail "G2-M3: the rebase fixture did not discriminate (base=$b mutant=$m)"
fi

# --- M4: newest match instead of oldest -------------------------------------
m_begin
python3 - "$MUT" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read()
old="| tail -n 1)\""
assert s.count(old)==1
s=s.replace(old,"| head -n 1)\"")
open(p,"w").write(s)
PY
if m_landed "G2-M4 (newest match, not oldest)"; then
  run_any "$PROBE" "$(fx two-touch)" --print-epoch >/dev/null; b=$(cat "$OUT")
  run_any "$MUT" "$(fx two-touch)" --print-epoch >/dev/null; m=$(cat "$OUT")
  cases=$((cases + 1))
  [[ -n "$b" && "$b" != "$m" ]] \
    && pass "G2-M4: taking the newest match moves the epoch on the TWO-TOUCH fixture ($b -> $m)" \
    || fail "G2-M4: the two-touch fixture did not discriminate (base=$b mutant=$m)"
fi

# --- M5: drop %H from the format -------------------------------------------
# The plan's matrix predicted this reddens the GRAFTED fixture only. That is
# wrong and the row is restated: without %H both `${line%% *}` and `${line#* }`
# return the WHOLE string, so the SHA assertion fails and the probe refuses on
# EVERY fixture — including the healthy one, where the baseline reports a
# verdict. That is still a discriminating observation; it is just a different
# one, and stating the original expectation would have made the row pass while
# proving something it did not test.
m_begin
python3 - "$MUT" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read()
old='''  --format='%H %cI' -- "$NOTICE_DOC" 2>/dev/null)" \\'''
assert s.count(old)==1, s.count(old)
s=s.replace(old, old.replace("%H %cI", "%cI"))
open(p,"w").write(s)
PY
if m_landed "G2-M5 (no %H in the format)"; then
  rc=$(run_any "$MUT" "$F1")
  cases=$((cases + 1))
  [[ "$rc" == "3" ]] \
    && pass "G2-M5: dropping %H makes the probe refuse on the HEALTHY fixture (rc=3 vs the baseline's 2)" \
    || fail "G2-M5: expected rc=3 on the healthy fixture, got $rc"
  cases=$((cases + 1))
  grep -q 'CANNOT ESTABLISH: the derived notice commit is not a git object id' "$OUT" \
    && pass "G2-M5: and it refuses with the SHA-shape reason, not some other exit-3 branch" \
    || fail "G2-M5: refused for a different reason: $(head -c 160 "$OUT")"
fi

# --- M6: remove the emptiness check and the shape guards --------------------
# The vulnerable form the plan's first draft prescribed. `date -u -d ""` returns
# TODAY rather than erroring, so a missing anchor silently yields an epoch of
# "now" and the probe reports a confident NOT YET forever.
m_begin
python3 - "$MUT" <<'PY'
import sys, re
p=sys.argv[1]; s=open(p).read()
m=re.search(r'\[\[ -n "\$EPOCH_LINE" \]\] \\\n  \|\| cannot_establish [^\n]*\n', s)
assert m, "emptiness check not found"
s=s[:m.start()]+s[m.end():]
for pat in [r'\[\[ "\$EPOCH_SHA" =~ \^\[0-9a-f\]\{7,40\}\$ \]\] \\\n  \|\| cannot_establish [^\n]*\n',
            r'\[\[ "\$EPOCH_ISO" =~ [^\n]*\n  \|\| cannot_establish [^\n]*\n']:
    mm=re.search(pat, s)
    assert mm, pat
    s=s[:mm.start()]+s[mm.end():]
# control B would still refuse (no SHA resolves), so neuter it too -- the row
# is about the EMPTINESS check, and leaving a downstream refusal in place would
# let the mutant pass for a reason unrelated to the mutation.
m2=re.search(r'\[\[ -n "\$EPOCH_PARENT" \]\] \\\n  \|\| cannot_establish [^\n]*\n', s)
assert m2, "control B not found"
s=s[:m2.start()]+s[m2.end():]
s=s.replace('(( N_ANCHOR >= 1 )) \\\n  || cannot_establish', 'true || cannot_establish')
s=s.replace('(( N_PARENT == 0 )) \\\n  || cannot_establish', 'true || cannot_establish')
open(p,"w").write(s)
PY
if m_landed "G2-M6 (no emptiness / shape guards)"; then
  rc=$(run_any "$MUT" "$(fx no-anchor)")
  cases=$((cases + 1))
  [[ "$rc" != "3" ]] \
    && pass "G2-M6: without the emptiness check a MISSING anchor silently yields a verdict (rc=$rc) instead of a refusal" \
    || fail "G2-M6: the mutant still refused — the emptiness check is not what catches an absent anchor"
fi

# --- M7: delete control B ---------------------------------------------------
m_begin
python3 - "$MUT" <<'PY'
import sys, re
p=sys.argv[1]; s=open(p).read()
m=re.search(r'\[\[ -n "\$EPOCH_PARENT" \]\] \\\n  \|\| cannot_establish [^\n]*\n', s)
assert m, "control B parent check not found"
s=s[:m.start()]+s[m.end():]
s=s.replace('(( N_PARENT == 0 )) \\\n  || cannot_establish', 'true || cannot_establish')
open(p,"w").write(s)
PY
if m_landed "G2-M7 (control B deleted)"; then
  rc=$(run_any "$MUT" "$GRAFT")
  cases=$((cases + 1))
  [[ "$rc" != "3" ]] \
    && pass "G2-M7: without control B a GRAFTED checkout derives a false epoch and returns a verdict (rc=$rc)" \
    || fail "G2-M7: the mutant still refused the grafted checkout — control B is not what catches it"
fi

# --- M8: the guard's OWN DISPATCH — verdict before any operand is read ------
m_begin
python3 - "$MUT" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read()
old='MODE="verdict"\ncase "${1:-}" in'
assert s.count(old)==1
s=s.replace(old,'printf \'NOT YET: 0 signature(s) checked\\n\'; exit 2\nMODE="verdict"\ncase "${1:-}" in')
open(p,"w").write(s)
PY
if m_landed "G2-M8 (dispatch disabled: verdict before any operand)"; then
  set_ledger "$D1" "$(ledger_of "222:$TS_POST")" >/dev/null 2>&1
  base=$(run_any "$PROBE" "$F1")
  mrc=$(run_any "$MUT" "$F1")
  cases=$((cases + 1))
  [[ "$base" == "5" && "$mrc" == "2" ]] \
    && pass "G2-M8: a probe that answers before reading its operands reports NOT YET where the real one reports ACTION" \
    || fail "G2-M8: base=$base mutant=$mrc (expected 5 then 2)"
fi

# --- M9: drop the roster term -----------------------------------------------
m_begin
python3 - "$MUT" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read()
old="""       | .id as $i
       | select(($r | index($i)) == null) ] | length) as $hits"""
assert s.count(old)==1
s=s.replace(old,"       ] | length) as $hits")
open(p,"w").write(s)
PY
if m_landed "G2-M9 (roster term dropped)"; then
  set_ledger "$D1" "$(ledger_of "222:$TS_POST")" >/dev/null 2>&1
  write_roster "$D1/repo" "$(roster_with 222 null)"
  base=$(run_any "$PROBE" "$F1")
  mrc=$(run_any "$MUT" "$F1")
  cases=$((cases + 1))
  [[ "$base" == "2" && "$mrc" == "5" ]] \
    && pass "G2-M9: without the roster term an already-designated signer reports ACTION forever (base=2, mutant=5)" \
    || fail "G2-M9: base=$base mutant=$mrc (expected 2 then 5)"
fi

# --- M10: treat a WITHDRAWN row as not covering -----------------------------
# The plan's matrix had this row inverted, because it predated the decision to
# narrow "covered" to live-OR-withdrawn. A live-only term is the mutation now:
# it leaves a withdrawn representative's id uncovered permanently, so the count
# latches at >= 1 and the probe's only signal is destroyed.
m_begin
python3 - "$MUT" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read()
old="jq -c '[.organizations[]?.representatives[]?.id]'"
assert s.count(old)==1
s=s.replace(old,"jq -c '[.organizations[]?.representatives[]? | select(.removed_at == null) | .id]'")
open(p,"w").write(s)
PY
if m_landed "G2-M10 (live-only roster term)"; then
  set_ledger "$D1" "$(ledger_of "222:$TS_POST")" >/dev/null 2>&1
  write_roster "$D1/repo" "$(roster_with 222 '"2026-08-09T00:00:00Z"')"
  base=$(run_any "$PROBE" "$F1")
  mrc=$(run_any "$MUT" "$F1")
  cases=$((cases + 1))
  [[ "$base" == "2" && "$mrc" == "5" ]] \
    && pass "G2-M10: a live-only term makes a WITHDRAWN designation latch the count at >= 1 (base=2, mutant=5)" \
    || fail "G2-M10: base=$base mutant=$mrc (expected 2 then 5)"
  write_roster "$D1/repo" "$ROSTER_EMPTY"
fi

# --- M11: default an unparseable created_at to 0 ----------------------------
m_begin
python3 - "$MUT" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read()
old='(( N_BAD == 0 )) \\\n  || cannot_establish'
assert s.count(old)==1
s=s.replace(old,'true \\\n  || cannot_establish')
old2="""  | ([ $latest[]
       | select(wellformed)"""
assert s.count(old2)==1
s=s.replace(old2,"""  | ([ $latest[]
       | select(wellformed or true)
       | .created_at |= (if (. | type) == "string" and (. | test("^[0-9]{4}")) then . else "1970-01-01T00:00:00Z" end)""")
open(p,"w").write(s)
PY
if m_landed "G2-M11 (unparseable created_at defaulted, not refused)"; then
  set_ledger "$D1" "{\"signedContributors\":[{\"id\":444,\"login\":\"fixture-login-444\",\"created_at\":\"$POISON\"}]}" >/dev/null 2>&1
  base=$(run_any "$PROBE" "$F1")
  mrc=$(run_any "$MUT" "$F1")
  cases=$((cases + 1))
  [[ "$base" == "3" && "$mrc" != "3" ]] \
    && pass "G2-M11: defaulting an unparseable created_at turns a refusal into a verdict (base=3, mutant=$mrc)" \
    || fail "G2-M11: base=$base mutant=$mrc (expected 3 then not-3)"
fi

# --- M12: let jq's runtime error reach the operator ------------------------
# The leak vector is NOT jq's PARSE error -- measured, that carries only a line
# and column and echoes nothing at all. It is jq's RUNTIME error:
# `fromdateiso8601` on a bad value prints `date "<the value>" does not match
# format ...`, and the sweeper republishes this script's output verbatim into a
# public comment.
#
# Two things close it and this row mutates BOTH, because either alone leaves the
# other holding: malformedness is a COUNTED PREDICATE (the `wellformed` guard
# keeps the bad value away from `fromdateiso8601`) AND the evaluation's stderr
# is suppressed and replaced by a line this file authored.
m_begin
python3 - "$MUT" <<'PY2'
import sys
p = sys.argv[1]
s = open(p).read()
old = '       | select(wellformed)\n       | select((.created_at | fromdateiso8601) >= $epoch)'
assert s.count(old) == 1, s.count(old)
s = s.replace(old, '       | select((.created_at | fromdateiso8601) >= $epoch)')
old2 = '"$LEDGER_FILE" 2>/dev/null)" \\\n  || cannot_establish "the ICLA signature ledger could not be evaluated'
assert s.count(old2) == 1, s.count(old2)
s = s.replace(old2, '"$LEDGER_FILE")" \\\n  || cannot_establish "the ICLA signature ledger could not be evaluated')
open(p, "w").write(s)
PY2
if m_landed "G2-M12 (counted predicate + stderr suppression removed)"; then
  set_ledger "$D1" "{\"signedContributors\":[{\"id\":444,\"login\":\"fixture-login-444\",\"created_at\":\"$POISON\"}]}" >/dev/null 2>&1
  run_any "$PROBE" "$F1" >/dev/null; base_leak=0; grep -qF "$POISON" <<<"$(both)" && base_leak=1
  run_any "$MUT"  "$F1" >/dev/null; mut_leak=0;  grep -qF "$POISON" <<<"$(both)" && mut_leak=1
  cases=$((cases + 1))
  [[ "$base_leak" == "0" && "$mut_leak" == "1" ]] \
    && pass "G2-M12: without the counted predicate jq's runtime error publishes the offending VALUE (base clean, mutant leaks)" \
    || fail "G2-M12: base_leak=$base_leak mutant_leak=$mut_leak (expected 0 then 1)"
fi

# --- M13: the fetch must come AFTER the derivation --------------------------
# Asserted on SOURCE ORDER rather than behaviourally: once --depth=1 is gone the
# fetch no longer flips the fixture to shallow, so an execution-order mutation
# has no observable left. Stating it as a source assertion is honest; leaving
# the behavioural row in the matrix would have been a row that cannot fire.
deriv_line=$(grep -n 'git log --first-parent -S' "$PROBE" | head -1 | cut -d: -f1)
fetch_line=$(grep -n 'fetch --no-tags --no-recurse-submodules' "$PROBE" | head -1 | cut -d: -f1)
cases=$((cases + 1))
[[ "$deriv_line" =~ ^[0-9]+$ && "$fetch_line" =~ ^[0-9]+$ ]] \
  && pass "G2-M13 control: both the derivation and the fetch were located in the source (lines $deriv_line and $fetch_line)" \
  || fail "G2-M13 control: could not locate one of the two statements — the order assertion below would be vacuous"
cases=$((cases + 1))
[[ "$deriv_line" =~ ^[0-9]+$ && "$fetch_line" =~ ^[0-9]+$ && "$deriv_line" -lt "$fetch_line" ]] \
  && pass "G2-M13: the epoch derivation precedes the ledger fetch in source order" \
  || fail "G2-M13: the ledger fetch precedes the epoch derivation"

# --- M14: drop --no-tags ----------------------------------------------------
m_begin
python3 - "$MUT" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read()
old="fetch --no-tags --no-recurse-submodules"
assert s.count(old)==1
s=s.replace(old,"fetch --no-recurse-submodules")
open(p,"w").write(s)
PY
if m_landed "G2-M14 (no --no-tags)"; then
  M14="$WORK/m14"
  build_fixture "$M14" one-touch >/dev/null 2>&1 || abort "could not build the M14 fixture"
  GIT_COMMITTER_DATE="$D_BASE" g -C "$M14/ledgersrc" tag -a -m t v-m14 >/dev/null 2>&1
  g -C "$M14/ledgersrc" push -q --tags "$M14/origin.git" >/dev/null 2>&1
  set_ledger "$M14" "$(ledger_of "111:$TS_PRE")" >/dev/null 2>&1
  GIT_COMMITTER_DATE="$D_BASE" g -C "$M14/ledgersrc" tag -a -m t v-m14b >/dev/null 2>&1
  g -C "$M14/ledgersrc" push -q --tags "$M14/origin.git" >/dev/null 2>&1
  run_any "$MUT" "$M14/repo" >/dev/null
  mtags=$(g -C "$M14/repo" show-ref --tags | grep -c . || true)
  cases=$((cases + 1))
  [[ "$mtags" -ge 1 ]] \
    && pass "G2-M14: dropping --no-tags writes $mtags tag(s) into the repository the probe reads" \
    || fail "G2-M14: the mutant created no tags — the tag-carrying origin fixture does not discriminate"
fi

# --- H5 (must-PASS, non-canonical): a DIFFERENT anchor phrase ---------------
# The derivation is not pinned to one literal's presence in this repository.
H5="$WORK/h5"
H5_ANCHOR="entirely different notice phrase"
mkdir -p "$H5"
( ANCHOR="$H5_ANCHOR"; build_fixture "$H5" one-touch ) >/dev/null 2>&1 \
  || abort "could not build the H5 fixture"
m_begin
python3 - "$MUT" "$H5_ANCHOR" <<'PY'
import sys
p, anchor = sys.argv[1], sys.argv[2]
s=open(p).read()
old='NOTICE_ANCHOR="public corporate coverage map"'
assert s.count(old)==1
s=s.replace(old,'NOTICE_ANCHOR="%s"' % anchor)
open(p,"w").write(s)
PY
if m_landed "H5 (probe constant repointed to a different anchor)"; then
  set_ledger "$H5" "$(ledger_of "111:$TS_PRE")" >/dev/null 2>&1
  rc=$(run_any "$MUT" "$H5/repo")
  cases=$((cases + 1))
  [[ "$rc" == "2" ]] \
    && pass "H5 must-PASS: a different anchor phrase works when the constant matches it (rc=2)" \
    || fail "H5: expected rc=2 on the repointed fixture, got $rc — $(head -c 160 "$OUT")"
  # ...and the UNCHANGED probe must refuse there, or H5 proves nothing.
  rc=$(run_any "$PROBE" "$H5/repo")
  cases=$((cases + 1))
  # The reason matters here as much as the code. This is the ONE exit-3 arm that
  # pinned only the number, and it is a CONTROL -- so any other refusal on that
  # fixture (a missing binary, an unreadable roster) satisfied it and quietly
  # decoupled it from the anchor it exists to prove.
  [[ "$rc" == "3" ]] \
    && pass "H5 control: the unmodified probe REFUSES on that fixture, so the arm above is not vacuous" \
    || fail "H5 control: the unmodified probe did not refuse (rc=$rc)"
  cases=$((cases + 1))
  grep -q 'anchor' "$OUT" \
    && pass "H5 control: that refusal is about the ANCHOR, not some unrelated fault" \
    || fail "H5 control: the refusal does not mention the anchor — it may be refusing for another reason: $(head -c 160 "$OUT")"
fi


# ===========================================================================
# Arms added after multi-agent review. Each closes a property the suite
# ASSERTED IN PROSE and did not pin — every one was proven survivable against
# this suite by mutating a sandbox copy.
# ===========================================================================

# --- G2-M13, REBUILT. The old form grepped BARE TOKENS out of an UN-STRIPPED
# --- haystack, on a file that is ~180 lines of comment before its first
# --- statement and whose header is titled "ORDERING IS LOAD-BEARING". Proven:
# --- inserting ONE comment line naming the derivation command, then moving the
# --- fetch above the real derivation, made the row PASS while the regression it
# --- exists to catch landed green. Strip comments, and anchor on constructs a
# --- `#`-prefixed line cannot produce.
m13_src="$(grep -vE '^[[:space:]]*#' "$PROBE")"
m13_deriv=$(grep -nE '^EPOCH_RAW="\$\(timeout' <<<"$m13_src" | head -1 | cut -d: -f1)
m13_fetch=$(grep -nE '^timeout "\$NET_TIMEOUT" git -c gc\.auto=0 fetch' <<<"$m13_src" | head -1 | cut -d: -f1)
cases=$((cases + 1))
[[ "$m13_deriv" =~ ^[0-9]+$ && "$m13_fetch" =~ ^[0-9]+$ ]] \
  && pass "G2-M13 control: both statements located in the COMMENT-STRIPPED source (lines $m13_deriv and $m13_fetch)" \
  || fail "G2-M13 control: could not locate the derivation and/or the fetch after stripping comments — the order assertion below would be vacuous"
cases=$((cases + 1))
[[ "$m13_deriv" =~ ^[0-9]+$ && "$m13_fetch" =~ ^[0-9]+$ && "$m13_deriv" -lt "$m13_fetch" ]] \
  && pass "G2-M13: the epoch derivation precedes the ledger fetch in EXECUTABLE source order" \
  || fail "G2-M13: the ledger fetch precedes the epoch derivation (deriv=$m13_deriv fetch=$m13_fetch)"
# ...and the anchors must be immune to the comment class that defeated the old
# form. A comment naming both commands must not move either line number.
m13_probe_decoy="$WORK/probe.m13decoy.sh"
{ printf '#!/usr/bin/env bash\n'
  printf '# EPOCH_RAW="$(timeout ... git log --first-parent -S ...)" -- prose naming it\n'
  printf '# timeout "$NET_TIMEOUT" git -c gc.auto=0 fetch --no-tags ... -- prose naming it\n'
  tail -n +2 "$PROBE"; } > "$m13_probe_decoy"
d2_src="$(grep -vE '^[[:space:]]*#' "$m13_probe_decoy")"
d2_deriv=$(grep -nE '^EPOCH_RAW="\$\(timeout' <<<"$d2_src" | head -1 | cut -d: -f1)
d2_fetch=$(grep -nE '^timeout "\$NET_TIMEOUT" git -c gc\.auto=0 fetch' <<<"$d2_src" | head -1 | cut -d: -f1)
cases=$((cases + 1))
[[ "$d2_deriv" == "$m13_deriv" && "$d2_fetch" == "$m13_fetch" ]] \
  && pass "G2-M13: comments naming BOTH commands do not move either anchor (the class that re-armed the old row)" \
  || fail "G2-M13: a comment moved an anchor (deriv $m13_deriv->$d2_deriv, fetch $m13_fetch->$d2_fetch) — the row is comment-defeatable again"

# --- FR14, MECHANICAL. The old arm grepped 'Operator:' in ONE leftover $OUT,
# --- i.e. it proved 1 of 24 refusal paths. Assert over the FILE instead: every
# --- cannot_establish call site carries an addressee tag.
fr14_total=$(grep -c 'cannot_establish "' "$PROBE" || true)
fr14_tagged=$(grep -c 'cannot_establish "[^"]*Operator:' "$PROBE" || true)
cases=$((cases + 1))
[[ "$fr14_total" -ge 20 ]] \
  && pass "FR14 control: the probe carries $fr14_total cannot_establish call sites (a non-trivial population)" \
  || fail "FR14 control: only $fr14_total cannot_establish sites found — the assertion below would be near-vacuous"
cases=$((cases + 1))
[[ "$fr14_total" == "$fr14_tagged" ]] \
  && pass "FR14: ALL $fr14_total refusal messages end in an addressee tag, not just the one a leftover run left behind" \
  || fail "FR14: $((fr14_total - fr14_tagged)) of $fr14_total cannot_establish messages carry no 'Operator:' tag"

# --- THE ACKNOWLEDGED FLOOR: the signal must be EDGE-triggered ---------------
# Without this the first unrelated post-epoch signer latches ACTION forever and
# the probe is byte-identical on the day a representative actually signs.
set_ledger "$D1" "$(ledger_of "111:$TS_PRE" "222:$TS_POST")" >/dev/null 2>&1
write_roster "$D1/repo" "$ROSTER_EMPTY"
printf '0\n' > "$D1/repo/scripts/followthroughs/ccla-representative-icla-7922.acknowledged" 2>/dev/null \
  || { mkdir -p "$D1/repo/scripts/followthroughs" && printf '0\n' > "$D1/repo/scripts/followthroughs/ccla-representative-icla-7922.acknowledged"; }
rc=$(run_probe "$F1")
cases=$((cases + 1))
[[ "$rc" == "5" ]] && pass "ack-floor 0: one uncovered post-epoch signature still reports ACTION" \
  || fail "ack-floor 0: expected rc=5, got $rc — $(head -c 140 "$OUT")"
printf '1\n' > "$D1/repo/scripts/followthroughs/ccla-representative-icla-7922.acknowledged"
rc=$(run_probe "$F1")
cases=$((cases + 1))
[[ "$rc" == "2" ]] \
  && pass "ack-floor 1: the SAME uncovered signature, once triaged, reports NOT YET — the signal is edge-triggered, not latched" \
  || fail "ack-floor 1: a triaged count still reports ACTION (rc=$rc) — the latch is not closed"
cases=$((cases + 1))
grep -q '1 already triaged' "$OUT" \
  && pass "the NOT YET line reports the triaged floor, so 'nothing found' and 'all already seen' cannot render alike" \
  || fail "NOT YET line does not carry the triaged floor: $(head -c 140 "$OUT")"
# ...and a SECOND, NEW signature must break through the floor.
set_ledger "$D1" "$(ledger_of "111:$TS_PRE" "222:$TS_POST" "333:$TS_POST")" >/dev/null 2>&1
rc=$(run_probe "$F1")
cases=$((cases + 1))
[[ "$rc" == "5" ]] \
  && pass "ack-floor 1 + a NEW signature: reports ACTION again — the floor suppresses the triaged, not the novel" \
  || fail "ack-floor: a new uncovered signature above the floor did not report ACTION (rc=$rc)"
cases=$((cases + 1))
grep -q 'ACTION: 2 signature' "$OUT" \
  && pass "the ACTION line carries the REAL count (2), not a constant" \
  || fail "ACTION line does not carry the real count: $(head -c 140 "$OUT")"
cases=$((cases + 1))
grep -qE 'ACTION: 2 signature\(s\).*3 entr\(ies\) checked' "$OUT" \
  && pass "the ACTION line carries the CHECKED count too (3), so hits and examined cannot render alike" \
  || fail "ACTION line does not carry the checked count: $(head -c 160 "$OUT")"
# A malformed floor file must REFUSE, never silently default to 0 (which would
# re-fire everything already triaged).
printf 'not-a-number\n' > "$D1/repo/scripts/followthroughs/ccla-representative-icla-7922.acknowledged"
rc=$(run_probe "$F1")
cases=$((cases + 1))
[[ "$rc" == "3" ]] && pass "a malformed acknowledged-floor file REFUSES (rc=3) rather than defaulting to 0" \
  || fail "malformed ack floor: expected rc=3, got $rc"
cases=$((cases + 1))
grep -q 'CANNOT ESTABLISH: the acknowledged-floor file' "$OUT" \
  && pass "the malformed-floor refusal names the file and the reason" \
  || fail "malformed-floor refusal does not name its cause: $(head -c 140 "$OUT")"
rm -f "$D1/repo/scripts/followthroughs/ccla-representative-icla-7922.acknowledged"

# --- FR15 ON THE VERDICT BRANCHES. The old arms asserted the no-naming
# --- property only on the exit-3 path. Publishing every ledger login on the
# --- ACTION line — the line that actually reaches the public comment on the one
# --- day the answer changes — was 73/73 green.
set_ledger "$D1" "$(ledger_of "111:$TS_PRE" "222:$TS_POST")" >/dev/null 2>&1
rc=$(run_probe "$F1")
cases=$((cases + 1))
if [[ "$rc" == "5" ]] && ! grep -qE 'fixture-login-|Fixture Person|2026-07-01' <<<"$(both)"; then
  pass "FR15 on the ACTION branch: no login, name or individual timestamp reaches either stream"
else
  fail "FR15: the ACTION branch leaked a ledger identifier or timestamp (rc=$rc)"
fi
set_ledger "$D1" "$(ledger_of "111:$TS_PRE" "222:$TS_PRE")" >/dev/null 2>&1
rc=$(run_probe "$F1")
cases=$((cases + 1))
if [[ "$rc" == "2" ]] && ! grep -qE 'fixture-login-|Fixture Person|2026-05-01' <<<"$(both)"; then
  pass "FR15 on the NOT YET branch: no login, name or individual timestamp reaches either stream"
else
  fail "FR15: the NOT YET branch leaked a ledger identifier or timestamp (rc=$rc)"
fi

# --- ROSTER CARDINALITY. Every roster fixture held ONE org with ONE
# --- representative, so a first-only read (`.organizations[0]?...[0]?`) was
# --- behaviourally invisible. Cover the SECOND member of both dimensions.
roster_two() { # two orgs, the second holding two representatives
  printf '{"schema_version":"1.0","organizations":[{"legal_name":"First Ltd","record_ref":"CCLA-0001","representatives":[{"id":111,"login":"fixture-login-111","authorized_from":"%s","removed_at":null}]},{"legal_name":"Second Ltd","record_ref":"CCLA-0002","representatives":[{"id":222,"login":"fixture-login-222","authorized_from":"%s","removed_at":null},{"id":333,"login":"fixture-login-333","authorized_from":"%s","removed_at":null}]}]}' \
    "$D_ANCHOR" "$D_ANCHOR" "$D_ANCHOR"
}
set_ledger "$D1" "$(ledger_of "333:$TS_POST")" >/dev/null 2>&1
write_roster "$D1/repo" "$(roster_two)"
rc=$(run_probe "$F1")
cases=$((cases + 1))
[[ "$rc" == "2" ]] \
  && pass "roster cardinality: a signer in the SECOND org's SECOND representative is covered — the read is not first-only" \
  || fail "roster cardinality: a second-org/second-representative signer read as uncovered (rc=$rc) — the roster read is truncated"
write_roster "$D1/repo" "$ROSTER_EMPTY"

# --- DUPLICATE ID: last-wins, matching the merge gate ------------------------
# The gate builds a Map keyed on id, so a repeated id keeps its LAST entry.
# Read existentially, a duplicated id whose post-epoch entry precedes its
# pre-epoch one makes this probe say ACTION while the gate refuses the write.
set_ledger "$D1" '{"signedContributors":[{"id":777,"login":"fixture-login-777","name":"Fixture Person 777","created_at":"2026-07-01T00:00:00Z"},{"id":777,"login":"fixture-login-777","name":"Fixture Person 777","created_at":"2026-05-01T00:00:00Z"}]}' >/dev/null 2>&1
rc=$(run_probe "$F1")
cases=$((cases + 1))
[[ "$rc" == "2" ]] \
  && pass "duplicate id: the LAST entry wins, matching the merge gate's Map semantics (rc=2)" \
  || fail "duplicate id: read existentially (rc=$rc) — the probe would say ACTION where the gate refuses the write"

# --- THE `--` PATHSPEC. Deleting it left all five parity arms green, because
# --- every fixture wrote the anchor into exactly ONE path. Plant a decoy in a
# --- SECOND path with an EARLIER date, so the pathspec is load-bearing.
# The decoy must be an ANCESTOR of the anchor commit, not a descendant: the
# derivation takes the OLDEST match, so a decoy committed AFTER the anchor is
# never selected and the fixture silently stops discriminating. (Measured: built
# the other way round, scoped and unscoped returned the same date and the
# dependent arm passed vacuously — which is what the control arm above is for.)
DEC="$WORK/decoy"
mkdir -p "$DEC/repo"
g -C "$DEC/repo" init -q
g init --bare -q "$DEC/origin.git"
g -C "$DEC/repo" remote add origin "$DEC/origin.git"
write_doc "$DEC/repo" 0
write_roster "$DEC/repo" "$ROSTER_EMPTY"
g -C "$DEC/repo" add -A
gcommit "$DEC/repo" "$D_BASE" "$D_BASE" "base: no anchor yet"
mkdir -p "$DEC/repo/docs/legal"
printf 'A decoy carrying the %s in another file.\n' "$ANCHOR" > "$DEC/repo/docs/legal/decoy.md"
g -C "$DEC/repo" add -A
gcommit "$DEC/repo" "2026-03-01T00:00:00Z" "2026-03-01T00:00:00Z" "decoy: anchor in a SECOND path, EARLIER"
write_doc "$DEC/repo" 1
g -C "$DEC/repo" add -A
gcommit "$DEC/repo" "$D_ANCHOR" "$D_ANCHOR" "introduce the coverage-map notice"
# AND MAKE THE `--` ITSELF LOAD-BEARING. A decoy in a second path proves the
# pathspec is APPLIED; it does not exercise what `--` actually guards, because
# git still treats a trailing non-revision argument as a path without it.
# Measured: deleting `--` from either implementation left this fixture green.
# What `--` guards is AMBIGUITY -- a ref whose name equals the path -- and git
# creates such a ref without complaint, so this is reachable, not contrived:
#   fatal: ambiguous argument 'docs/legal/individual-cla.md': both revision and filename
# rc=128, which both implementations then report as a refusal.
g -C "$DEC/repo" branch "$DOC_REL"
cases=$((cases + 1))
g -C "$DEC/repo" rev-parse --verify --quiet "refs/heads/$DOC_REL" >/dev/null \
  && pass "pathspec fixture control: a ref named exactly \`$DOC_REL\` exists, so the -- separator is now load-bearing" \
  || fail "pathspec fixture control: could not create the ambiguous ref — the -- arms below would prove only scoping"
dec_scoped=$(g -C "$DEC/repo" log --first-parent -S"$ANCHOR" --format=%cI -- "$DOC_REL" | tail -1)
dec_unscoped=$(g -C "$DEC/repo" log --first-parent -S"$ANCHOR" --format=%cI | tail -1)
cases=$((cases + 1))
[[ -n "$dec_scoped" && "$dec_scoped" != "$dec_unscoped" ]] \
  && pass "pathspec fixture: scoped and unscoped pickaxes DISAGREE ($dec_scoped vs $dec_unscoped) — the -- separator is now load-bearing" \
  || fail "pathspec fixture does not discriminate (scoped=$dec_scoped unscoped=$dec_unscoped)"
set_ledger "$DEC" "$(ledger_of "111:$TS_PRE")" >/dev/null 2>&1
rc=$(run_probe "$DEC/repo" --print-epoch)
cases=$((cases + 1))
[[ "$rc" == "2" && "$(cat "$OUT")" == "$dec_scoped" ]] \
  && pass "the probe honours the -- pathspec (derives $dec_scoped, not the decoy's $dec_unscoped)" \
  || fail "the probe ignored the pathspec: got '$(cat "$OUT")', expected $dec_scoped"

# AND THE TYPESCRIPT AUTHORITY, on the same fixture. The parity family above is
# built before this fixture exists, so `--` was pinned on the bash side only --
# while `roster-entry-gate.ts` tells its reader that editing the separator THERE
# reddens a suite two directories away. That was false: every parity fixture
# writes the anchor into exactly one path, so the TS `--` could be deleted with
# all five arms green. This arm is what makes the comment true.
if [[ -x "$TSX" ]]; then
  {
    printf 'import {resolveCoverageMapNoticeEpoch} from %s;\n' "\"$GATE_TS\""
    printf 'try{console.log(resolveCoverageMapNoticeEpoch(%s));}catch(e){console.log("THREW");}\n' \
      "\"$DEC/repo\""
  } > "$WORK/parity-decoy.ts"
  dec_ts="$("$TSX" "$WORK/parity-decoy.ts" 2>"$WORK/parity-decoy.err" || echo RUNFAIL)"
  cases=$((cases + 1))
  [[ "$dec_ts" == "$dec_scoped" ]] \
    && pass "the TypeScript authority honours the -- pathspec too (derives $dec_ts)" \
    || fail "the TS authority ignored the pathspec: got '$dec_ts', expected $dec_scoped ($(head -c 160 "$WORK/parity-decoy.err"))"
fi

# ---------------------------------------------------------------------------
echo "---"
echo "Total: $passes passed, $fails failed ($cases cases)"
# ACCOUNTING CONSERVATION. Catches an assertion site that incremented `cases`
# without reaching a pass/fail helper (or the reverse). It does NOT catch an arm
# that never ran at all — both sides move together then — nor an unconditional
# `pass` after a discarded predicate; the floor below is what carries absence.
if [[ $((passes + fails)) -ne "$cases" ]]; then
  printf 'ACCOUNTING: %s assertions recorded but %s cases counted — an assertion site is unpaired\n' \
    "$((passes + fails))" "$cases" >&2
  exit 1
fi
# Assertion floor, reported with printf + exit rather than through fail(), which
# is the helper it exists to backstop.
MIN_ASSERTIONS=95
if [[ $((passes + fails)) -lt "$MIN_ASSERTIONS" ]]; then
  printf 'ANTI-VACUITY: only %s assertions ran, expected at least %s\n' "$((passes + fails))" "$MIN_ASSERTIONS" >&2
  exit 1
fi
[[ "$fails" -eq 0 ]] || exit 1
exit 0
