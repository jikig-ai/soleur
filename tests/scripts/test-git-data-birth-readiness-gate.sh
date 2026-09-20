#!/usr/bin/env bash
# Test suite for tests/scripts/lib/git-data-birth-readiness-gate.sh (#6977).
#
# EVERY ASSERTION RUNS AGAINST A SYNTHESIZED FIXTURE, NEVER THE LIVE FILE.
#
# That is the single most important property of this suite, and it is worth stating why
# rather than just doing it. The obvious test — "run the gate on the real
# cloud-init-git-data.yml and assert it HOLDs" — passes today for the wrong reason: it
# passes because the feature is not ready. Its passing condition is "#6982 has not
# shipped yet", so the day the emitter lands, this suite goes red and the person landing
# it deletes the test. A test whose green depends on work being unfinished is not a
# regression guard; it is a countdown timer.
#
# So the fixtures below encode the CONTRACT (sentinel present => release, absent => hold,
# comment does not count, escaped literal does not count), and the contract keeps holding
# after #6982 lands.
#
# AMENDED 2026-08-12 (#7485). #6982 HAS SINCE CLOSED and the live gate now reports RELEASED,
# so the countdown the paragraph above warns about has run out — and the warning was correct:
# a suite asserting `HOLD` on the live template would be red today.
#
# The rule this header states is therefore narrowed to what it always meant: no arm asserts
# the GATE'S VERDICT on the live template. Arm A1 does read the live cloud-init, and it is
# the one exception, deliberately: it asserts that a DIFFERENT function
# (`git_data_rung2_user_data_sha256`) can derive a digest at all from the tree as committed.
# That property is invariant under the emitter landing — it was false before #6982 and false
# after, for the same reason — so its green does not depend on any work being unfinished.
#
# A1 is also the only fixture that can catch an over-broad sibling abort: the live module has
# no `.tf.json` at all, so it is the sole tree exercising the unexpanded-glob path. The suite
# already read the live file as a non-asserting NOTE, so reading it is not new; asserting on
# it is, and this is why.

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# SOLEUR_SUITE_ROOT_OVERRIDE exists for ONE caller: mutate_suite, which runs a mutated copy of
# this file from $TMP. Without it the copy derives ROOT from its own location, fails the
# source guard, and exits 2 — which the parent cannot tell apart from "the injected defect did
# not red the suite". The harness rows would then pass for exactly the wrong reason.
ROOT="${SOLEUR_SUITE_ROOT_OVERRIDE:-$(cd "${DIR}/../.." && pwd)}"
GATE="${ROOT}/tests/scripts/lib/git-data-birth-readiness-gate.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# (#8043 NFR2 / Guard 4) THE FIXTURE GIT ENVIRONMENT, sourced BEFORE any fixture is created.
# The rung-2 fixture tree below is a real git repository from here on (the provenance arm reads
# `git log` on the evidence file), and the Guard 4 rows commit into throwaway repositories under
# $TMP. This file is the #7849 chokepoint: sourcing it ARMS the tripwire that refuses an inherited
# GIT_DIR — in a linked worktree git exports GIT_DIR/GIT_INDEX_FILE to every hook as absolute
# paths, and they override `git -C`, so a fixture's `git init` would initialise nothing and its
# commits would land on the developer's live branch (#7833; precedent: tests/scripts/
# test-weakness-miner.sh; learning 2026-03-24-git-ceiling-directories-test-isolation.md).
# `git_fixture_env` then exports the ceiling (the parent of $TMP), a synthesized identity, and
# config hermeticity into THIS shell, so every `git -C "$fixture"` below is contained.
# shellcheck source=../../plugins/soleur/test/lib/git-fixture-env.sh
source "${ROOT}/plugins/soleur/test/lib/git-fixture-env.sh" \
  || { printf 'FATAL: could not source the fixture git environment\n' >&2; exit 2; }
git_fixture_env "$TMP" || { printf 'FATAL: git_fixture_env refused the fixture root %s\n' "$TMP" >&2; exit 2; }

# Byte-identical copy of the repo-wide fixture-containment guard. It is duplicated per file
# rather than sourced because the consumers are standalone scripts; the P1a suite asserts every
# tracked copy is identical, so do not reformat it. `_authmap_root` writes a fixture tree from a
# caller-supplied path, and a RELATIVE path there would write into the caller's live checkout
# instead of the temp root — the containment class fixture-relative-assert.test.sh ratchets.
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

# ── (#8010) THE RUN-RESOLUTION TEST SEAM, and why it is armed for the WHOLE suite ──
#
# `git_data_rung2_rehearsal_gate` now resolves its evidence URL against the GitHub Actions
# API. Every arm that RELEASES therefore reaches a network step, so the seam is exported at
# suite top rather than prefixed per command: `mutate_r2` and `mutate_g` run their mutants in
# CHILD SHELLS (`bash -c`), and a per-command prefix on the parent would not reach them.
#
# The double gate is the point (mirrors SOLEUR_SENTRY_READER in the capture script):
# SOLEUR_RUNG2_RUN_FETCH is honoured ONLY when SOLEUR_TEST_MODE is also set, so a single
# leaked env var in a workflow cannot redirect the gate's only network call. Arm T-SEAM2
# below asserts the fall-through when the second half is absent.
#
# The SIBLING capture suite deliberately does NOT export it suite-wide: there the double gate
# is itself the property under test.
export SOLEUR_TEST_MODE=1
export SOLEUR_RUNG2_RUN_FETCH="$TMP/api-fetch.sh"
export SOLEUR_RUNG2_RETRY_SLEEP=0

# The stub store is keyed by the URL PATH SUFFIX the gate passes (`runs/<id>` or
# `runs/<id>/artifacts`), so ONE stub serves both endpoints. Its contract is body-then-status,
# matching the real fetch now that no header parsing exists: the last line is the HTTP status,
# everything above it is the body.
#
# A MISSING ENTRY IS A TRANSPORT FAILURE, not an empty 200 — "the endpoint answered with
# nothing" and "nothing answered" are the two states this gate's could-not-measure vocabulary
# exists to keep apart, and a stub that conflated them would make every RUN_OFFLINE arm
# vacuous. rc 7 is curl's connect failure.
mkdir -p "$TMP/api"
assert_fixture_dir "$TMP/api"
cat > "$TMP/api-fetch.sh" <<'STUB'
#!/usr/bin/env bash
# Path-suffix-keyed stub for SOLEUR_RUNG2_RUN_FETCH. Prints body then status; rc 7 = no entry.
set -uo pipefail
store="${SOLEUR_RUNG2_STUB_STORE:?stub store unset}"
suffix="${1:-}"
body="${store}/${suffix}.body"
status="${store}/${suffix}.status"
[[ -f "$body" ]] || exit 7
cat "$body"
# A ONE-SHOT status: the first call gets it, every later call gets 200. This is how the
# anonymous-retry arm is fixtured — the stub cannot see the Authorization header, so the
# retry is expressed as "the second attempt succeeds".
if [[ -f "${status}.once" ]]; then
  cat "${status}.once"; rm -f "${status}.once"
else
  cat "$status" 2>/dev/null || printf '200\n'
fi
STUB
chmod +x "$TMP/api-fetch.sh"
export SOLEUR_RUNG2_STUB_STORE="$TMP/api"

# _stub_run <id> [key=value ...]
#   Seeds BOTH endpoints for one run id. Keys: head_sha conclusion status path event
#   head_branch created_at http artifacts.
#   `artifacts` defaults to one entry named git-data-rung2-boot-evidence — the shape a real
#   capture run produces; a dry_run dispatch is expressed as `artifacts=none`.
#   Re-callable: a later call overwrites, which is how one shared URL serves fixtures in
#   different throwaway repositories (their HEADs differ, and head_sha must resolve in the
#   repository the gate is judging).
_stub_run() {
  local id="$1"; shift
  local head_sha="" conclusion="success" status="completed" http="200"
  local path=".github/workflows/git-data-rung2-rehearsal.yml"
  local event="workflow_dispatch" head_branch="main" created_at artifacts="evidence"
  created_at="$(date -u -d '1 day ago' +%Y-%m-%dT%H:%M:%SZ)"
  local kv
  for kv in "$@"; do
    case "$kv" in
      head_sha=*)    head_sha="${kv#*=}" ;;
      conclusion=*)  conclusion="${kv#*=}" ;;
      status=*)      status="${kv#*=}" ;;
      path=*)        path="${kv#*=}" ;;
      event=*)       event="${kv#*=}" ;;
      head_branch=*) head_branch="${kv#*=}" ;;
      created_at=*)  created_at="${kv#*=}" ;;
      http=*)        http="${kv#*=}" ;;
      artifacts=*)   artifacts="${kv#*=}" ;;
      *) _a_setup_fail "_stub_run: unknown key '${kv}'" ;;
    esac
  done
  mkdir -p "$TMP/api/runs/${id}"
  rm -f "$TMP/api/runs/${id}.status.once"
  if [[ "$http" == "raw" ]]; then
    printf 'not json at all\n' > "$TMP/api/runs/${id}.body"
    printf '200\n' > "$TMP/api/runs/${id}.status"
  elif [[ "$http" == "500once" ]]; then
    jq -n --arg id "$id" --arg sha "$head_sha" --arg c "$conclusion" --arg s "$status" \
          --arg p "$path" --arg e "$event" --arg b "$head_branch" --arg t "$created_at" \
      '{id: ($id|tonumber), head_sha: $sha, conclusion: $c, status: $s, path: $p,
        event: $e, head_branch: $b, created_at: $t}' \
      > "$TMP/api/runs/${id}.body" || _a_setup_fail "_stub_run: jq failed for ${id}"
    printf '200\n' > "$TMP/api/runs/${id}.status"
    printf '500\n' > "$TMP/api/runs/${id}.status.once"
  elif [[ "$http" == "401once" ]]; then
    jq -n --arg id "$id" --arg sha "$head_sha" --arg c "$conclusion" --arg s "$status" \
          --arg p "$path" --arg e "$event" --arg b "$head_branch" --arg t "$created_at" \
      '{id: ($id|tonumber), head_sha: $sha, conclusion: $c, status: $s, path: $p,
        event: $e, head_branch: $b, created_at: $t}' \
      > "$TMP/api/runs/${id}.body" || _a_setup_fail "_stub_run: jq failed for ${id}"
    printf '200\n' > "$TMP/api/runs/${id}.status"
    printf '401\n' > "$TMP/api/runs/${id}.status.once"
  else
    jq -n --arg id "$id" --arg sha "$head_sha" --arg c "$conclusion" --arg s "$status" \
          --arg p "$path" --arg e "$event" --arg b "$head_branch" \
      '{id: ($id|tonumber), head_sha: $sha, conclusion: (if $c == "null" then null else $c end),
        status: $s, path: $p, event: $e, head_branch: $b}' \
      > "$TMP/api/runs/${id}.body" || _a_setup_fail "_stub_run: jq failed for ${id}"
    printf '%s\n' "$http" > "$TMP/api/runs/${id}.status"
  fi
  case "$artifacts" in
    none)    jq -n '{total_count: 0, artifacts: []}' > "$TMP/api/runs/${id}/artifacts.body" ;;
    log)     jq -n --arg t "$created_at" '{total_count: 1, artifacts: [{name: "git-data-rung2-capture-log", expired: false, created_at: $t}]}' > "$TMP/api/runs/${id}/artifacts.body" ;;
    # THE REAL MULTI-ATTEMPT SHAPE. /runs/<id>/artifacts returns artifacts from ALL attempts,
    # so a run whose attempt 1 failed (capture-log) and attempt 2 passed (boot-evidence) is a
    # TWO-element list with the log FIRST. Every other fixture here has population <= 1, which
    # is why reading `.artifacts[0]` instead of the set survived the whole battery.
    both)    jq -n --arg t "$created_at" '{total_count: 2, artifacts: [{name: "git-data-rung2-capture-log", expired: false, created_at: $t}, {name: "git-data-rung2-boot-evidence", expired: false, created_at: $t}]}' > "$TMP/api/runs/${id}/artifacts.body" ;;
    missing) rm -f "$TMP/api/runs/${id}/artifacts.body" ;;
    *)       jq -n --arg t "$created_at" '{total_count: 1, artifacts: [{name: "git-data-rung2-boot-evidence", expired: false, created_at: $t}]}' > "$TMP/api/runs/${id}/artifacts.body" ;;
  esac
  printf '200\n' > "$TMP/api/runs/${id}/artifacts.status"
  # `created_at` on the RUN is what the 90-day branch reads; keep it beside the run body.
  printf '%s\n' "$created_at" > "$TMP/api/runs/${id}.created_at"
  jq --arg t "$created_at" '. + {created_at: $t}' "$TMP/api/runs/${id}.body" \
    > "$TMP/api/runs/${id}.body.tmp" 2>/dev/null \
    && mv "$TMP/api/runs/${id}.body.tmp" "$TMP/api/runs/${id}.body"
}

passes=0
fails=0
pass() { passes=$((passes + 1)); printf '  ok   %s\n' "$1"; }
# THE VERDICT READS AN APPEND-ONLY LEDGER, NOT A COUNTER (#7481 review, V1/V2).
# Measured: swapping one token in fail() — `fails=$((fails+1))` -> `passes=$((passes+1))` —
# left this suite reporting all-green with real defects injected, and the assertion floor
# CANNOT see it because the floor sums both buckets. The runcmd suite already carried this
# hardening; it was never propagated here, which is the single-instance-not-the-class miss.
# The ledger length is asserted against the counter too: deleting just the append leaves an
# accurate FAIL line printed and rc=0 (measured on the sibling suite).
FAILURES=()
fail() {
  FAILURES+=("$1")
  fails=$((fails + 1))
  printf '  FAIL %s\n' "$1"; printf '       rc=%s\n' "${2:-?}"; printf '       out=%s\n' "${3:-}"
}

# shellcheck source=/dev/null
# GUARDED. This suite runs `set -uo pipefail` WITHOUT `-e`, so a failed `source` is
# non-fatal: every arm below would then call an undefined function, and the gate's own
# `command not found` (rc=127) would be reported as a gate VERDICT rather than as the
# instrument never having loaded. Fail closed and name the path instead.
source "$GATE" || { printf 'FATAL: could not source the gate library at %s\n' "$GATE" >&2; exit 2; }
if ! declare -F git_data_authorization_map_gate >/dev/null 2>&1; then
  printf 'FATAL: %s sourced but git_data_authorization_map_gate is not defined\n' "$GATE" >&2
  exit 2
fi

check() {
  local name="$1" want_rc="$2" needle="$3" file="$4"
  local out rc
  out="$(git_data_birth_readiness_gate "$file" 2>&1)"; rc=$?
  if [[ "$rc" -eq "$want_rc" && "$out" == *"$needle"* ]]; then
    pass "$name"
  else
    fail "$name (want rc=$want_rc containing '$needle')" "$rc" "$out"
  fi
}

printf '\n=== git-data-birth-readiness-gate ===\n\n'

# ── HOLD: today's shape — an emitter-less template ────────────────────────────────
cat > "$TMP/no-emitter.yml" <<'YML'
#cloud-config
write_files:
  - path: /usr/local/bin/git-data-bootstrap.sh
    encoding: b64
    content: ${git_data_bootstrap_b64}
runcmd:
  - [ bash, -c, "cryptsetup luksOpen /dev/disk/by-id/${git_data_luks_volume_id} gitdata" ]
YML
check "a template with NO emitter => HOLD" 1 "HOLD" "$TMP/no-emitter.yml"
check "the HOLD names the blocking issue" 1 "#6982" "$TMP/no-emitter.yml"
check "the HOLD names the sentinel it wants" 1 'sentry_dsn' "$TMP/no-emitter.yml"
check "the HOLD names the ADR carrying the full checklist" 1 "ADR-149" "$TMP/no-emitter.yml"
check "the HOLD names the runbook (release record)" 1 "git-data-birth.md" "$TMP/no-emitter.yml"
check "the HOLD warns off the laptop-apply workaround" 1 "laptop" "$TMP/no-emitter.yml"

# ── RELEASE: the emitter wired ────────────────────────────────────────────────────
cat > "$TMP/emitter.yml" <<'YML'
#cloud-config
write_files:
  - path: /etc/soleur/sentry-dsn
    permissions: '0600'
    content: ${sentry_dsn}
runcmd:
  - [ bash, -c, "curl -sf --data-binary @- \"${sentry_dsn}\" </var/log/boot-stage || true" ]
YML
check "a template WITH the sentinel => RELEASED" 0 "RELEASED" "$TMP/emitter.yml"
check "the RELEASE states what it did NOT check" 0 "NOT machine-checked" "$TMP/emitter.yml"

# ── THE COMMENT ARM (task 1.5.4) ──────────────────────────────────────────────────
#
# A comment-only back-reference marker pointing at #6982 is explicitly PERMITTED and
# desirable — it tells the next reader of the file where the emitter work lives. It must
# not release the interlock.
#
# This is not hypothetical fussiness: terraform does not know YAML comments exist, so a
# comment containing `${sentry_dsn}` really would force git-data.tf to supply the
# variable and really would satisfy a naive "does templatefile demand this var" check —
# while emitting exactly nothing. The gate has to be line-aware, and this arm is what
# proves it is.
cat > "$TMP/comment-only.yml" <<'YML'
#cloud-config
# TODO(#6982): wire the off-host emitter here. It will need ${sentry_dsn} threaded
# through git-data.tf's templatefile vars block. Until then this host boots dark and
# the birth route stays interlocked.
write_files:
  - path: /usr/local/bin/git-data-bootstrap.sh
    content: ${git_data_bootstrap_b64}
YML
check "a COMMENT mentioning the sentinel => still HOLD" 1 "HOLD" "$TMP/comment-only.yml"

# Indented comments too — the runcmd block is indented, so an unanchored comment strip
# would miss exactly the place a marker is most likely to be written.
cat > "$TMP/indented-comment.yml" <<'YML'
#cloud-config
runcmd:
    # emitter goes here once #6982 lands: ${sentry_dsn}
  - [ bash, -c, "true" ]
YML
check "an INDENTED comment mentioning the sentinel => still HOLD" 1 "HOLD" "$TMP/indented-comment.yml"

# A TRAILING comment. This is not a hypothetical shape: line 13 of the live
# cloud-init-git-data.yml is `- util-linux # provides flock for the …`, so a trailing
# comment is the single most natural place to write a #6982 back-reference. A whole-line
# strip cannot see it, and MEASURED against the live file, appending
# `TODO(#6982): emit boot status to ${sentry_dsn}` there flipped HOLD to RELEASED — the
# interlock disengaged by prose, which the gate's header claimed was impossible.
cat > "$TMP/trailing-comment.yml" <<'YML'
#cloud-config
packages:
  - util-linux # provides flock; TODO(#6982): emit boot status to ${sentry_dsn}
runcmd:
  - [ bash, -c, "true" ]
YML
check "a TRAILING comment mentioning the sentinel => still HOLD" 1 "HOLD" "$TMP/trailing-comment.yml"

# (#7066 review, P2) A TRAILING COMMENT CONTAINING A QUOTE CHARACTER. The strip was
# `s/[[:space:]]#[^"'"'"']*$//` — it removed a trailing comment only when the tail was
# quote-free, so any comment carrying an apostrophe survived and SATISFIED the sentinel,
# re-entering the defect the arms above exist to close. The intent was to protect a `#` inside
# a QUOTED SCALAR (real template text), which is a claim about whether the `#` is quoted, not
# about what follows it — so the predicate now tests the prefix's quote parity.
cat > "$TMP/quoted-trailing-comment.yml" <<'YML'
#cloud-config
packages:
  - util-linux # TODO emit to ${sentry_dsn} for the host's boot
runcmd:
  - [ bash, -c, "true" ]
YML
check "a trailing comment CONTAINING A QUOTE mentioning the sentinel => still HOLD" 1 "HOLD" \
  "$TMP/quoted-trailing-comment.yml"

# ...and the protection it was written for still holds: a `#` INSIDE a quoted scalar is real
# template text and must NOT be stripped, or a legitimate emitter becomes unreleasable.
cat > "$TMP/hash-in-quoted-scalar.yml" <<'YML'
#cloud-config
runcmd:
  - [ bash, -c, "curl -sf --data 'tag=#boot' ${sentry_dsn}" ]
YML
check "a '#' inside a quoted scalar is NOT stripped => RELEASED" 0 "RELEASED" \
  "$TMP/hash-in-quoted-scalar.yml"

# A trailing comment must not eat REAL template text earlier on the same line.
cat > "$TMP/code-then-comment.yml" <<'YML'
#cloud-config
runcmd:
  - [ bash, -c, "curl -sf ${sentry_dsn}" ] # emit boot status
YML
check "real interpolation with a trailing comment after it => RELEASED" 0 "RELEASED" "$TMP/code-then-comment.yml"

# ── THE ESCAPED-LITERAL ARM ───────────────────────────────────────────────────────
# `$${sentry_dsn}` is how a template writes a LITERAL dollar-brace. Terraform substitutes
# nothing, so the host receives the eight characters and no DSN. Counting it would let a
# shell snippet that happens to reference a same-named shell variable release the gate.
cat > "$TMP/escaped.yml" <<'YML'
#cloud-config
runcmd:
  - [ bash, -c, "echo $${sentry_dsn} > /dev/null" ]
YML
check "an ESCAPED \$\${sentry_dsn} literal => still HOLD" 1 "HOLD" "$TMP/escaped.yml"

# A real interpolation on the SAME line as an escaped one must still release — the
# refusal is of the escaped form specifically, not of any line containing one.
cat > "$TMP/mixed.yml" <<'YML'
#cloud-config
runcmd:
  - [ bash, -c, "echo $${literal} && curl -sf ${sentry_dsn}" ]
YML
check "a real interpolation beside an escaped one => RELEASED" 0 "RELEASED" "$TMP/mixed.yml"

# ── Fail-closed input ─────────────────────────────────────────────────────────────
check "a missing template file => ABORT" 1 "not found" "$TMP/nonexistent.yml"
check "no path supplied => ABORT" 1 "no cloud-init path" ""

# An EMPTY file is readable and simply has no sentinel — it must HOLD, not crash.
: > "$TMP/empty.yml"
check "an empty template => HOLD" 1 "HOLD" "$TMP/empty.yml"

# ── The live-file observation, recorded as CONTEXT and not as a gate ──────────────
#
# Deliberately NOT an assertion. Its result is reported so a reader of the log knows the
# interlock's live state, but the suite's exit status does not depend on it — otherwise
# this file becomes the countdown timer described in the header comment, and the person
# who ships #6982 has to delete a test to land it.
LIVE="${ROOT}/apps/web-platform/infra/cloud-init-git-data.yml"
if [[ -f "$LIVE" ]]; then
  if git_data_birth_readiness_gate "$LIVE" >/dev/null 2>&1; then
    printf '  note live cloud-init-git-data.yml: RELEASED (an emitter is wired — #6982 has landed)\n'
  else
    printf '  note live cloud-init-git-data.yml: HOLD (no emitter yet — expected until #6982)\n'
  fi
else
  printf '  note live cloud-init-git-data.yml not found at the expected path\n'
fi

# ── THE RUNG-2 REHEARSAL GATE (#6982 A3) ─────────────────────────────────────────
#
# Same fixture discipline as above: never the live evidence path. The contract is (a) no
# evidence => HOLD, (b) evidence must CLAIM a pass in non-comment text, (c) it must carry an
# auditable URL, and (d) it must be hash-bound to the template being dispatched, so a
# rehearsal of a since-edited template does not release the route.
#
# (d) is the one worth stating: without it "evidence exists" is satisfied forever by a
# rehearsal of a template that has since changed, and this template changes constantly.
printf '\nrung-2 rehearsal gate\n'

# The gate binds its evidence to EVERY file that composes user_data, not just the template —
# a rehearsal is only meaningful for the payload set that actually boots. So the fixture models
# that set: the render MODULE with nine `file()` bindings, and the nine payloads two levels up.
#
# (#7025, R7) The layout mirrors production: the map lives in
# modules/git-data-userdata/main.tf and reaches its payloads through `${path.module}/../../`,
# because both the production root and the rung-2 rehearsal root call that one module. A
# fixture still shaped like the old inline git-data.tf would exercise a resolution path the
# gate no longer has.
R2="$TMP/r2"; mkdir -p "$R2/modules/git-data-userdata"
cp "$TMP/mixed.yml" "$R2/ci.yml"
_r2_payloads=(git-data-bootstrap.sh git-data-provision.sh git-data-transport-wrapper.sh
              git-data-remove.sh git-data-gc.sh git-data-pre-receive-placeholder.sh
              git-data-gc.service git-data-gc-failure.service git-data-gc.timer)
_r2_write_module() {  # $1 = root dir, remaining args = payload basenames
  local d="$1"; shift
  local p
  mkdir -p "$d/modules/git-data-userdata"
  {
    printf 'locals {\n  git_data_rationale_strip = "/(?m)^[ \\t]*#([^!\\n][^\\n]*)?\\n/"\n}\n\n'
    printf 'locals {\n  rendered = templatefile("${path.module}/../../ci.yml", {\n'
    for p in "$@"; do
      printf '    %s = replace(file("${path.module}/../../%s"), local.git_data_rationale_strip, "")\n' \
        "${p//[-.]/_}" "$p"
    done
    printf '  })\n}\n'
  } > "$d/modules/git-data-userdata/main.tf"
}
_r2_write_module "$R2" "${_r2_payloads[@]}"
for _p in "${_r2_payloads[@]}"; do printf '#!/usr/bin/env bash\n# %s\ntrue\n' "$_p" > "$R2/$_p"; done

# ── fixture git helpers (#8043 NFR2 / Guard 4) ────────────────────────────────────
#
# `_a_setup_fail` lived beside the A-rows; it is hoisted here because the helpers below run
# from THIS point on (the R2 tree is committed a few lines down) and a function is resolved at
# call time, not at definition time.
_a_setup_fail() { printf '\n  HARNESS ABORT: %s\n' "$1" >&2; exit 2; }

# THE COMMIT IS SILENT ON PURPOSE, AND THE CHECK AFTER IT IS THE GUARD (Guard 4 row 7).
#
# A runner with no git identity fails `git commit` with "Author identity unknown" and rc=128.
# Under this suite's `set -uo pipefail` (no -e) that failure is NON-FATAL: HEAD does not move,
# every fixture below then has c1 == c2 with an empty diff, and every provenance row that
# expects a HOLD would read the unchanged tree as "nothing touched a bound file" -- a PASS. The
# suite would go GREEN on a harness that built nothing. So the commit's own exit status is
# deliberately discarded and the invariant is asserted instead: HEAD moved, and the diff between
# the two heads is non-empty. Violated, the HARNESS reds (exit 2) -- not the SUT.
#
# NEVER call this in a command substitution: `_a_setup_fail`'s `exit 2` would terminate only
# the subshell (the hazard `_a_tree` records by name). Read HEAD afterwards with rev-parse.
_g_commit() {  # $1=repo $2=message -- commits EVERYTHING in the work tree as one commit
  local d="$1" msg="$2" before after
  assert_fixture_dir "$d"
  before="$(git -C "$d" rev-parse --verify --quiet HEAD 2>/dev/null || true)"   # empty when unborn
  git -C "$d" add -A >/dev/null 2>&1 || true
  git -C "$d" commit -q -m "$msg" >/dev/null 2>&1 || true
  after="$(git -C "$d" rev-parse --verify --quiet HEAD 2>/dev/null || true)"
  if [[ -z "$after" || "$before" == "$after" ]]; then
    _a_setup_fail "git commit '${msg}' in ${d} landed NO new commit (HEAD before='${before:-unborn}' after='${after:-unborn}'). A runner with no git identity fails exactly this way, silently; the harness reds here so the SUT is never asked about a tree that did not change."
  fi
  if [[ -n "$before" && -z "$(git -C "$d" diff --name-only "$before" "$after" 2>/dev/null)" ]]; then
    _a_setup_fail "git commit '${msg}' in ${d} produced an EMPTY diff between ${before} and ${after}; a provenance row over it would be vacuous."
  fi
}

# Commit ONE file in a commit that touches only it -- the shape a rehearsal PR lands the
# evidence in, and the shape every RELEASED row in the legacy R2 battery now needs, because the
# rehearsal gate reads the evidence's provenance (ARM 1). No-op outside a work tree, and a no-op
# when the file already matches HEAD (rewriting identical evidence is not a change).
_r2_commit_alone() {  # $1 = file inside a fixture repository
  local f="$1" d before after
  d="$(dirname "$f")"
  git -C "$d" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
  [[ -n "$(git -C "$d" status --porcelain --untracked-files=all -- "$f" 2>/dev/null)" ]] || return 0
  before="$(git -C "$d" rev-parse --verify --quiet HEAD 2>/dev/null || true)"
  git -C "$d" add -- "$f" >/dev/null 2>&1 || true
  git -C "$d" commit -q -m "evidence: $(basename "$f")" -- "$f" >/dev/null 2>&1 || true
  after="$(git -C "$d" rev-parse --verify --quiet HEAD 2>/dev/null || true)"
  if [[ -z "$after" || "$before" == "$after" ]]; then
    _a_setup_fail "evidence-only commit of ${f} landed NO new commit (HEAD before='${before:-unborn}' after='${after:-unborn}')."
  fi
}

# THE R2 TREE IS A REPOSITORY, committed as c1 BEFORE any evidence is written, so that every
# evidence file `r2_evidence` writes below lands in its OWN commit (via _r2_commit_alone) --
# the only provenance shape the rehearsal gate's ARM 1 releases. The template, module and
# payloads are in c1; no evidence is.
git -C "$R2" init -q -b main || _a_setup_fail "git init failed in $R2"
_g_commit "$R2" "c1: template, module, payloads"

# Compute the expected hash exactly the way the gate does, so the fixture tracks the gate's
# own definition rather than restating it.
#
# (#7025, R4) BASENAME-NORMALISED, LC_ALL=C. The pre-#7025 derivation piped the resolved
# PATHS through `xargs sha256sum`, whose output embeds each path — so identical bytes hashed
# to three different values depending on the caller's cwd. Measured on the live tree:
#   apps/web-platform/infra/<name>  -> aa1447f2…   (repo-root-relative)
#   <name>                          -> dcaa1281…   (cwd = infra)
#   /abs/path/<name>                -> b77f4998…   (absolute)
# Production invokes the gate with ${GITHUB_WORKSPACE}/… while a rehearsal or a laptop run
# would not, so evidence captured at one cwd would read STALE EVIDENCE forever — blaming a
# template edit that never happened.
_r2_hash() {  # $1 = dir holding ci.yml + modules/git-data-userdata/main.tf + payloads
  local d="$1" md="$1/modules/git-data-userdata" ins=() f
  ins+=("$d/ci.yml")
  # THE MODULE .tf IS AN INPUT (#7066 review, P1). It holds the strip expression applied to
  # every payload, so omitting it was a live fail-open: relaxing that expression changed what
  # boots and left the hash BYTE-IDENTICAL on the live tree. Mirrors the gate's own set, and
  # shares its extraction rule so the two cannot drift.
  ins+=("$md/main.tf")
  # AND THE SIBLING .tf / .tf.json FILES, because the lib binds the whole module directory.
  # This mirror had DRIFTED FROM THE LIB TWICE while its comment above claimed it could not:
  # it had no sibling glob at all, and it matched a bare `file\(` where the lib matches the
  # whole `file(base64|sha256|sha512|md5)?` family. Both are repaired here, and A10 below
  # asserts equivalence against the lib so a third drift is unshippable rather than merely
  # measured once. Measured: this repair is hash-neutral — `R2_SHA` is byte-identical at
  # 6dcbe339… before and after — because no fixture carries a sibling or a `filebase64`
  # binding today. That is exactly why a one-time measurement is not a guard.
  for f in "$md"/*.tf "$md"/*.tf.json; do
    [[ -e "$f" || -L "$f" ]] || continue          # unexpanded glob literal (no nullglob here)
    [[ -r "$f" && "$f" != "$md/main.tf" ]] && ins+=("$f")
  done
  while IFS= read -r f; do
    [[ -n "$f" && -r "$md/$f" ]] && ins+=("$md/$f")
  done < <(sed 's/^[[:space:]]*#.*$//' "$md/main.tf" \
           | grep -oE '(^|[^A-Za-z])file(base64|sha256|sha512|md5)?\("\$\{path\.module\}/[^"]+"' \
           | sed -E 's/.*\("\$\{path\.module\}\///; s/"$//' | sort -u)
  { for f in "${ins[@]}"; do
      printf '%s  %s\n' "$(sha256sum "$f" | cut -d' ' -f1)" "$(basename "$f")"
    done; } | LC_ALL=C sort | sha256sum | cut -d' ' -f1
}
R2_SHA="$(_r2_hash "$R2")"

# (#8010) SEED THE RUN STUBS FOR EVERY ID THE FIXTURES CITE.
#
# The id list is DERIVED, not remembered: `grep -oE 'actions/runs/[0-9]+'` over this file
# yields 1, 2, 3, 4, 5, 17250000001, 17253046871 (the R2 battery) and 17260000001 /
# 17260000002 (the Guard 4 battery, seeded beside their own repositories below). A missed id
# turns a green arm red on merge, because an unseeded id is a TRANSPORT failure by design.
#
# `head_sha` is the R2 repository's c1 — the commit that carries the bound files. Any later
# commit would hash identically (only evidence files are added after c1), but c1 is the one
# that exists before every arm runs, and `git cat-file -e` is evaluated at gate time.
_R2_C1="$(git -C "$R2" rev-parse HEAD)"
for _id in 1 2 3 4 5 17250000001 17253046871; do
  _stub_run "$_id" "head_sha=$_R2_C1"
done

r2check() {
  local name="$1" want_rc="$2" needle="$3" ci="$4" ev="$5"
  local out rc
  out="$(git_data_rung2_rehearsal_gate "$ci" "$ev" 2>&1)"; rc=$?
  if [[ "$rc" -eq "$want_rc" && "$out" == *"$needle"* ]]; then
    pass "$name"
  else
    fail "$name (want rc=$want_rc containing '$needle')" "$rc" "$out"
  fi
}

# A URL that SATISFIES the R8 Actions-run shape, so every arm below tests the refusal it
# names rather than tripping on the URL check first. Hoisted to one place: it is a
# precondition of nine fixtures, not a property of any of them.
R2_URL="https://github.com/jikig-ai/soleur/actions/runs/17250000001"

_r2_evidence_write() {  # $1=dest $2=verdict $3=url $4=sha [$5=divergence "none"] [$6=sentry "CLEAN"] [$7=ack]
  # Defaults to the EXPLICIT `none` rather than omitting the key: an absent key is now
  # refused, because omitting it left the allowlist loop iterating zero times and the CLOSED
  # allowlist refusing nothing (#7066 review). "Nothing diverged" must be declared.
  #
  # (#8010) RUNG2_SENTRY_CROSSCHECK joins the required-key set, so it defaults to the one
  # value that continues — every pre-existing arm keeps testing the refusal it names instead
  # of tripping on a new cardinality HOLD first. The optional ack key is written only when
  # asked: it is at-most-once, so an unconditional empty line would refuse every fixture.
  printf 'RUNG2_BOOT_REHEARSAL=%s\nRUNG2_EVIDENCE_URL=%s\nRUNG2_TEMPLATE_SHA256=%s\nRUNG2_VAR_DIVERGENCE=%s\nRUNG2_SENTRY_CROSSCHECK=%s\n' \
    "$2" "$3" "$4" "${5:-none}" "${6-CLEAN}" > "$1"
  [[ -n "${7:-}" ]] && printf 'RUNG2_SENTRY_CROSSCHECK_ACK=%s\n' "$7" >> "$1"
  return 0
}
# The legacy writer: write, then commit the file ALONE (#8043 NFR2). The Guard 4 fixtures use
# `_r2_evidence_write` directly because they need the evidence in the SAME commit as a bound
# file -- that is the shape they exist to refuse.
r2_evidence() {
  _r2_evidence_write "$@"
  _r2_commit_alone "$1"
}

r2_evidence "$R2/ok.env" PASS "https://github.com/jikig-ai/soleur/actions/runs/1" "$R2_SHA"
r2check "valid, hash-matched evidence => RELEASED" 0 "RELEASED" "$R2/ci.yml" "$R2/ok.env"

r2check "absent evidence => HOLD" 1 "no rung-2 boot evidence" "$R2/ci.yml" "$R2/absent.env"
# Regression pin (green on the pre-#8010 wording too): the no-evidence HOLD must keep naming
# the runbook that carries the release record and the dispatch procedure.
r2check "the no-evidence HOLD names the runbook" 1 "git-data-birth.md" "$R2/ci.yml" "$R2/absent.env"

# Prose must not disengage a mechanical hold — the lesson the sentinel gate learned when a
# trailing comment flipped it from HOLD to RELEASED.
{ printf '# RUNG2_BOOT_REHEARSAL=PASS\n# RUNG2_EVIDENCE_URL=%s\n' "$R2_URL"
  printf '# RUNG2_TEMPLATE_SHA256=%s\n# RUNG2_VAR_DIVERGENCE=none\n' "$R2_SHA"; } > "$R2/comment.env"
# The needle moved from "does not assert" to the exactly-once refusal: with every line
# commented out the key-cardinality check now fires FIRST (0 occurrences of each key). Still
# a HOLD, still for the right reason — prose does not disengage a mechanical hold.
r2check "a fully commented-out evidence file => HOLD" 1 "exactly 1 is required" "$R2/ci.yml" "$R2/comment.env"

r2_evidence "$R2/fail.env" FAIL "$R2_URL" "$R2_SHA"
r2check "evidence claiming FAIL => HOLD" 1 "does not assert" "$R2/ci.yml" "$R2/fail.env"

r2_evidence "$R2/nourl.env" PASS "ask-me-about-it" "$R2_SHA"
r2check "an unauditable non-URL pointer => HOLD" 1 "not an Actions run URL" "$R2/ci.yml" "$R2/nourl.env"

# ── (#7025, R8) THE URL MUST BE AN ACTIONS RUN, NOT MERELY A URL ──────────────────
#
# `^https?://` was satisfied by anything a human could type. That matters more here than it
# would elsewhere: `main` carries NO `pull_request` ruleset (no required approving reviews)
# and `can_approve_pull_request_reviews: true`, so a hand-authored evidence file citing
# https://example.com would release the last mechanical hold on a host that will store every
# connected user's source code. An Actions run URL is not unforgeable, but it names an
# artifact that either exists in this repo's run history or does not.
r2_evidence "$R2/anyurl.env" PASS "https://example.com/i-rehearsed-it" "$R2_SHA"
r2check "a well-formed but NON-ACTIONS URL => HOLD" 1 "not an Actions run URL" \
  "$R2/ci.yml" "$R2/anyurl.env"

# A run URL for a DIFFERENT repository is the same class: it is auditable, just not about us.
r2_evidence "$R2/otherrepo.env" PASS "https://github.com/attacker/soleur/actions/runs/1" "$R2_SHA"
r2check "an Actions run URL for another repo => HOLD" 1 "not an Actions run URL" \
  "$R2/ci.yml" "$R2/otherrepo.env"

# Trailing segments (`/job/123`, `/attempts/2`) are what GitHub actually links to, so the
# shape must be a PREFIX match on the run id and not an anchored-to-end equality.
r2_evidence "$R2/runjob.env" PASS \
  "https://github.com/jikig-ai/soleur/actions/runs/17253046871/job/48972331209" "$R2_SHA"
r2check "an Actions run URL with a /job/ suffix => RELEASED" 0 "RELEASED" \
  "$R2/ci.yml" "$R2/runjob.env"

# ── (#7025, R4) PATH INVARIANCE ───────────────────────────────────────────────────
#
# The SAME tree, addressed two ways, must produce ONE hash. Measured on the live tree before
# this fix, identical bytes hashed to three different values purely by path form
# (aa1447f2… / dcaa1281… / b77f4998…), because the derivation piped resolved paths through
# `xargs sha256sum`, whose output embeds the path. Production invokes the gate with
# ${GITHUB_WORKSPACE}/… ; a rehearsal capture or a laptop run does not. Evidence produced at
# one cwd would then read STALE EVIDENCE forever, and the message would blame a template edit
# that never happened — the worst kind of wrong, because it is actionable and false.
#
# Asserted as an EQUALITY between two invocations rather than against a pinned constant: a
# constant would need updating on every legitimate payload edit and would be re-derived from
# the very function under test.
_rel_hash="$(cd "$R2" && git_data_rung2_user_data_sha256 "ci.yml")"
_abs_hash="$(git_data_rung2_user_data_sha256 "$R2/ci.yml")"
if [[ "$_rel_hash" =~ ^[0-9a-f]{64}$ && "$_rel_hash" == "$_abs_hash" ]]; then
  pass "the hash is PATH-INVARIANT (relative and absolute forms agree)"
else
  fail "path invariance: relative and absolute invocations disagree" "n/a" \
    "rel=${_rel_hash} abs=${_abs_hash}"
fi

# And the helper the gate uses must be the helper the capture script uses — one call, so
# disagreement is structurally impossible. This arm guards the CALL SITE, not the arithmetic:
# it asserts the gate's own verdict agrees with the standalone helper on the same tree.
if [[ "$_abs_hash" == "$R2_SHA" ]]; then
  pass "git_data_rung2_user_data_sha256 agrees with the gate's own evidence binding"
else
  fail "the extracted helper and the gate's binding disagree" "n/a" \
    "helper=${_abs_hash} gate-fixture=${R2_SHA}"
fi

# ── (#7025) THE <10 PAYLOAD FLOOR, exercised rather than asserted in prose ─────────
#
# A shrunken extraction silently narrows what the evidence is bound to — the same fail-open
# the ten-input binding was introduced to close, wearing a different costume. The floor is
# the only thing standing between "the map moved" and "the evidence now attests one file".
R2F="$TMP/r2floor"; cp -r "$R2" "$R2F"
_r2_write_module "$R2F" git-data-bootstrap.sh git-data-gc.sh
r2check "a render module binding fewer than 9 payloads => ABORT" 1 "ABORT" \
  "$R2F/ci.yml" "$R2/ok.env"
r2check "the ABORT names the drifted extraction rather than blaming the evidence" 1 "drifted" \
  "$R2F/ci.yml" "$R2/ok.env"

# The module going missing entirely is the same fail-closed class, and is what a botched
# module move looks like.
R2M="$TMP/r2nomodule"; cp -r "$R2" "$R2M"; rm -rf "$R2M/modules"
r2check "no render module at all => ABORT" 1 "ABORT" "$R2M/ci.yml" "$R2/ok.env"

# ── (#7025, R6) THE RENDER-VAR DIVERGENCE ALLOWLIST ───────────────────────────────
#
# The hash binds the template and the nine payloads. It does NOT bind the templatefile
# ARGUMENTS, so a rehearsal that booted with a different Doppler CLI arch, a different
# checksum, or a different Sentry DSN still produces hash-valid evidence for a boot that is
# not the boot production would get. doppler_arch and doppler_sha256 are the sharp case: they
# select WHICH BINARY is downloaded and WHICH CHECKSUM verifies it, so a mis-derived pair
# verifies the tarball it just chose and passes — the #6570 boot-brick class, rehearsed away.
#
# The gap is closed by DECLARATION: the rehearsal writes what it diverged on, and anything
# outside the declared-divergence allowlist refuses. (Five of its eight members are
# identity-shaped; the three pubkeys are a CAPABILITY divergence -- see the library.)
r2_evidence "$R2/div-ok.env" PASS "https://github.com/jikig-ai/soleur/actions/runs/2" "$R2_SHA" \
  "host_name,git_data_volume_id,git_data_luks_volume_id,doppler_token,doppler_config_name"
r2check "divergence confined to identity-shaped vars => RELEASED" 0 "RELEASED" \
  "$R2/ci.yml" "$R2/div-ok.env"

r2_evidence "$R2/div-arch.env" PASS "https://github.com/jikig-ai/soleur/actions/runs/3" "$R2_SHA" \
  "host_name,doppler_arch"
r2check "divergence on doppler_arch => HOLD" 1 "doppler_arch" "$R2/ci.yml" "$R2/div-arch.env"

r2_evidence "$R2/div-dsn.env" PASS "https://github.com/jikig-ai/soleur/actions/runs/4" "$R2_SHA" \
  "sentry_dsn"
r2check "divergence on sentry_dsn => HOLD" 1 "sentry_dsn" "$R2/ci.yml" "$R2/div-dsn.env"

# An unknown var name is NOT waved through. A typo'd or newly-introduced var is exactly the
# case where "not on the deny list" and "safe" come apart, so the allowlist is closed.
r2_evidence "$R2/div-unknown.env" PASS "https://github.com/jikig-ai/soleur/actions/runs/5" "$R2_SHA" \
  "some_new_var"
r2check "divergence on an UNKNOWN var => HOLD" 1 "some_new_var" "$R2/ci.yml" "$R2/div-unknown.env"

# ── (#7066 review, P1) OMISSION IS NOT A BYPASS ───────────────────────────────────
#
# Measured fail-open: with RUNG2_VAR_DIVERGENCE omitted, `divergence` was empty, the
# allowlist loop iterated zero times, and the CLOSED allowlist refused nothing — a
# hand-authored file evaded R6 entirely by saying LESS.
{ printf 'RUNG2_BOOT_REHEARSAL=PASS\nRUNG2_EVIDENCE_URL=%s\n' "$R2_URL"
  printf 'RUNG2_TEMPLATE_SHA256=%s\n' "$R2_SHA"; } > "$R2/nodivkey.env"
r2check "evidence with NO divergence line => HOLD" 1 "exactly 1 is required" \
  "$R2/ci.yml" "$R2/nodivkey.env"

# The explicit declaration IS accepted — otherwise the fix above would make a genuinely-clean
# rehearsal unreleasable, which is a different bug.
r2check "explicit RUNG2_VAR_DIVERGENCE=none => RELEASED" 0 "RELEASED" "$R2/ci.yml" "$R2/ok.env"

# ── (#7066 review, P1) A PRESENT KEY WITH AN EMPTY VALUE IS NOT A DECLARATION ─────
#
# The arm above closed ABSENT and left EMPTY open. The cardinality loop counts lines matching
# the KEY, so `RUNG2_VAR_DIVERGENCE=` counted as exactly 1; `divergence` came back empty,
# `read -ra` yielded zero tokens, the closed allowlist iterated zero times, and the gate
# RELEASED the birth interlock — while the release message printed `${divergence:-none}`,
# asserting a declaration of "none" that nobody made. Whitespace-only is the same silence
# with extra bytes, and `--divergence` upstream validates with `-z` only, so $'\n' reaches here.
{ printf 'RUNG2_BOOT_REHEARSAL=PASS\nRUNG2_EVIDENCE_URL=%s\n' "$R2_URL"
  printf 'RUNG2_TEMPLATE_SHA256=%s\nRUNG2_VAR_DIVERGENCE=\nRUNG2_SENTRY_CROSSCHECK=CLEAN\n' "$R2_SHA"; } > "$R2/emptydiv.env"
r2check "an EMPTY RUNG2_VAR_DIVERGENCE is refused (silence cannot release)" 1 "EMPTY value" \
  "$R2/ci.yml" "$R2/emptydiv.env"

{ printf 'RUNG2_BOOT_REHEARSAL=PASS\nRUNG2_EVIDENCE_URL=%s\n' "$R2_URL"
  printf 'RUNG2_TEMPLATE_SHA256=%s\nRUNG2_VAR_DIVERGENCE=   \nRUNG2_SENTRY_CROSSCHECK=CLEAN\n' "$R2_SHA"; } > "$R2/wsdiv.env"
r2check "a WHITESPACE-ONLY RUNG2_VAR_DIVERGENCE is refused" 1 "EMPTY value" \
  "$R2/ci.yml" "$R2/wsdiv.env"

# ── (#7066 review, P1) DUPLICATE KEYS ARE REFUSED ─────────────────────────────────
#
# The PASS assertion was `grep -qE` (matches ANY line) while every other key used `head -1`,
# so a file carrying BOTH PASS and FAIL RELEASED — the gate read first-wins while dotenv
# semantics are last-wins, and a merge or append produced a file whose meaning differed
# between the gate and every human reading it.
{ printf 'RUNG2_BOOT_REHEARSAL=PASS\nRUNG2_BOOT_REHEARSAL=FAIL\nRUNG2_EVIDENCE_URL=%s\n' "$R2_URL"
  printf 'RUNG2_TEMPLATE_SHA256=%s\nRUNG2_VAR_DIVERGENCE=none\n' "$R2_SHA"; } > "$R2/duppass.env"
r2check "PASS alongside a second FAIL line => HOLD" 1 "exactly 1 is required" \
  "$R2/ci.yml" "$R2/duppass.env"

# A duplicated divergence key hid a real declaration behind `head -1` taking the first
# (empty) line, so the second line's doppler_arch never reached the allowlist check.
{ printf 'RUNG2_BOOT_REHEARSAL=PASS\nRUNG2_EVIDENCE_URL=%s\n' "$R2_URL"
  printf 'RUNG2_TEMPLATE_SHA256=%s\nRUNG2_VAR_DIVERGENCE=\nRUNG2_VAR_DIVERGENCE=doppler_arch\n' "$R2_SHA"; } > "$R2/dupdiv.env"
r2check "a duplicated divergence key => HOLD" 1 "exactly 1 is required" \
  "$R2/ci.yml" "$R2/dupdiv.env"

# ── (#7066 review, P1) THE STRIP EXPRESSION IS HASH-BOUND ─────────────────────────
#
# The regression guard for this PR's sharpest finding. The module .tf holds
# `local.git_data_rationale_strip`, the transform applied to all nine payloads. Before the
# fix, relaxing it left the hash BYTE-IDENTICAL while the render changed materially — the
# live-tree mutation strips the shebang from three forced-command wrappers, which then
# silently fall back to dash. The suite had NO arm mutating the module .tf, which is exactly
# why the fail-open shipped.
R2ME="$TMP/r2modedit"; cp -r "$R2" "$R2ME"
printf '\n# a later edit to the RENDER TRANSFORM, not to any payload\n' >> "$R2ME/modules/git-data-userdata/main.tf"
r2check "evidence goes stale when the RENDER MODULE is edited" 1 "STALE EVIDENCE" \
  "$R2ME/ci.yml" "$R2/ok.env"
r2check "the RELEASE reports the divergence set it accepted" 0 "divergence" \
  "$R2/ci.yml" "$R2/div-ok.env"

r2_evidence "$R2/badsha.env" PASS "$R2_URL" "deadbeef"
r2check "a malformed template hash => HOLD" 1 "malformed" "$R2/ci.yml" "$R2/badsha.env"

r2_evidence "$R2/stale.env" PASS "$R2_URL" \
  "0000000000000000000000000000000000000000000000000000000000000000"
r2check "a hash for a DIFFERENT template => HOLD" 1 "STALE EVIDENCE" "$R2/ci.yml" "$R2/stale.env"

r2check "a missing cloud-init => ABORT" 1 "missing or not supplied" "$R2/nonexistent.yml" "$R2/ok.env"

# THE SELF-INVALIDATION PROPERTY, asserted end-to-end rather than inferred from (d): the
# SAME evidence file that just released the gate must stop releasing it once the template
# it attests to is edited. This is the whole reason the hash binding exists.
R2E="$TMP/r2edited"; cp -r "$R2" "$R2E"
printf '\n# a later edit to the template\n' >> "$R2E/ci.yml"
r2check "evidence goes stale when the TEMPLATE is edited" 1 "STALE EVIDENCE" \
  "$R2E/ci.yml" "$R2/ok.env"

# THE POINT OF BINDING ALL TEN INPUTS. An earlier version hashed the template ALONE — 1 of the
# 10 files composing user_data — so editing a PAYLOAD left the evidence valid for a boot that
# had changed. This is the arm that pins the fix.
R2P="$TMP/r2payload"; cp -r "$R2" "$R2P"
printf '\n# a later edit to a shipped payload\n' >> "$R2P/git-data-gc.sh"
r2check "evidence goes stale when a PAYLOAD is edited (not just the template)" 1 "STALE EVIDENCE" \
  "$R2P/ci.yml" "$R2/ok.env"

# ── MUTATION SECTION ──────────────────────────────────────────────────────────────
# This gate is a single decision, so every arm is SOLE-GUARD: there is no second line of
# defence to hand off to, and a mutation that still HOLDs means the arm was decorative.
printf '\nmutation checks (each neuters one guard; the arm it protects must flip)\n'

mutate_and_check() {
  local label="$1" sed_expr="$2" want_rc="$3" file="$4"
  local mutated out rc
  mutated="$TMP/mutated-gate.sh"
  sed "$sed_expr" "$GATE" > "$mutated"
  if cmp -s "$mutated" "$GATE"; then
    fail "$label — the mutation matched NOTHING in the gate (byte-identical copy); the guard is missing or the sed expression drifted." "n/a" "no textual change"
    return
  fi
  out="$(bash -c "source '$mutated'; git_data_birth_readiness_gate '$file'" 2>&1)"; rc=$?
  if [[ "$rc" -eq "$want_rc" ]]; then
    pass "$label (arm is load-bearing — neutering it flips the verdict)"
  else
    fail "$label — the arm did NOT change behavior when neutered; it may be dead code" "$rc" "$out"
  fi
}

# Neuter the comment filter (point it at a pattern no line can match, so nothing is
# stripped): the comment-only fixture then RELEASES, which is the precise failure this
# gate exists to prevent — prose satisfying a mechanical hold.
#
# Anchored on the hoisted `strip_comments=` assignment rather than on the grep pipeline.
# A sed aimed at the pipeline has to carry the sentinel regex through both a shell quote
# and sed's own escaping, and a mis-escaped expression matches nothing — which the
# non-vacuity floor correctly reports as a missing guard rather than a real result. It
# did, twice, which is why the gate hoists these onto their own lines.
mutate_and_check "comment-stripping guard" \
  's|^  strip_comments=.*|  strip_comments="s/^$//"|' \
  0 "$TMP/comment-only.yml"

# Neuter the escaped-literal exclusion by widening the sentinel to a bare substring that
# `$${sentry_dsn}` also contains: the escaped fixture then RELEASES.
mutate_and_check "escaped-literal guard" \
  's|^  sentinel_re=.*|  sentinel_re="sentry_dsn}"|' \
  0 "$TMP/escaped.yml"

# Drop the hold branch entirely: the emitter-less template then RELEASES.
mutate_and_check "hold branch" \
  's/^  if \[\[ "\$hits" -eq 0 \]\]; then/  if false; then/' \
  0 "$TMP/no-emitter.yml"

# Drop the missing-file guard: an absent path then RELEASES on a zero count from grep.
mutate_and_check "missing-file guard" \
  's/^  if \[\[ ! -f "\$cloud_init" \]\]; then/  if false; then/' \
  1 "$TMP/nonexistent.yml"

# Rung-2 arms. Same SOLE-GUARD reasoning: that gate is a chain of independent refusals with
# no second line of defence, so a mutation that still HOLDs means the arm was decorative.
printf '\nmutation checks — rung-2 gate\n'

mutate_r2() {
  local label="$1" sed_expr="$2" want_rc="$3" ci="$4" ev="$5" needle="${6:-}"
  local mutated out rc
  mutated="$TMP/mutated-r2.sh"
  sed "$sed_expr" "$GATE" > "$mutated"
  if cmp -s "$mutated" "$GATE"; then
    fail "$label — the mutation matched NOTHING in the gate (byte-identical copy); the guard is missing or the sed expression drifted." "n/a" "no textual change"
    return
  fi
  out="$(bash -c "source '$mutated'; git_data_rung2_rehearsal_gate '$ci' '$ev'" 2>&1)"; rc=$?
  # (#8010) THE OPTIONAL 6th ARGUMENT IS WHAT MAKES A HOLD->HOLD ROW MEAN ANYTHING.
  #
  # Every row here asserted rc ALONE. That is sufficient while the mutation is expected to
  # flip HOLD to RELEASE (rc 1 -> 0), and VACUOUS the moment a row expects HOLD both before
  # and after: the gate is a chain of refusals, so neutering arm N lets the fixture fall
  # through to arm N+1, which HOLDs for a DIFFERENT reason with rc=1 — and the row passes
  # having proven nothing about arm N. The needle pins WHICH refusal spoke.
  if [[ "$rc" -eq "$want_rc" ]] && { [[ -z "$needle" ]] || [[ "$out" == *"$needle"* ]]; }; then
    pass "$label (arm is load-bearing — neutering it flips the verdict)"
  else
    fail "$label — the arm did NOT change behavior when neutered; it may be dead code${needle:+ (wanted '$needle')}" "$rc" "$out"
  fi
}

# mutate_suite <label> <sed_expr> <expect_fails>
#   HARNESS ROW: mutates THIS SUITE, not the gate, and asserts the mutant reports at least
#   <expect_fails> failures. Every guard below owes one — row (a) of the Guard Contract's
#   mutation matrix is "neuter the harness", and no helper did that: `mutate_r2`/`mutate_g`
#   can only edit $GATE. Without it a stub that answers every question identically, or an
#   assertion helper that always takes the pass branch, is indistinguishable from a healthy
#   run (the #7275 shape).
mutate_suite() {
  local label="$1" sed_expr="$2" expect_fails="${3:-1}"
  local mutated out rc got
  # RECURSION BREAKER, and it PASSES rather than returning silently. A mutant that simply
  # skipped these rows would run fewer assertions than the floor, red for THAT reason, and
  # every row here would then pass having proven nothing — the floor would be doing the
  # work the mutation is supposed to do. Passing keeps the mutant's assertion count equal
  # to the parent's, so the only thing that can red it is the injected defect.
  if [[ -n "${SOLEUR_RUNG2_SUITE_MUTANT:-}" ]]; then
    pass "$label (suppressed inside a suite mutant)"
    return
  fi
  mutated="$TMP/mutated-suite.sh"
  sed "$sed_expr" "${BASH_SOURCE[0]}" > "$mutated"
  if cmp -s "$mutated" "${BASH_SOURCE[0]}"; then
    fail "$label — the mutation matched NOTHING in the suite (byte-identical copy)" "n/a" "no textual change"
    return
  fi
  # SOLEUR_RUNG2_SUITE_MUTANT breaks the recursion: the mutant must not re-enter this battery.
  out="$(SOLEUR_RUNG2_SUITE_MUTANT=1 SOLEUR_SUITE_ROOT_OVERRIDE="$ROOT" bash "$mutated" 2>&1)"; rc=$?
  got="$(printf '%s\n' "$out" | sed -n 's/^=== [0-9]* passed, \([0-9]*\) failed ===$/\1/p' | tail -1)"
  if [[ -n "$got" && "$got" -ge "$expect_fails" ]]; then
    pass "$label (harness row: the mutant reports ${got} failure(s), floor ${expect_fails})"
  else
    # REPORT THE MUTANT'S OWN TAIL. Without it a mutant that ABORTED (rc 2, no summary line)
    # is indistinguishable from one that ran green, and the row's message asserts the second —
    # which is a confident wrong diagnosis, the class this suite exists to remove.
    fail "$label — the mutated SUITE did not red; the assertion it guards is vacuous" "$rc" "reported failures='${got:-none}'; mutant tail: $(printf '%s\n' "$out" | tail -4 | tr '\n' ' ')"
  fi
}

# The hash binding is the arm most likely to be "simplified" away by a reader who takes it as
# redundant with the PASS assertion. Neutered, stale evidence releases the birth route.
mutate_r2 "rung-2 hash-binding arm" \
  's/^  if \[\[ "\$claimed_sha" != "\$live_sha" \]\]; then/  if false; then/' \
  0 "$R2/ci.yml" "$R2/stale.env"

# Neutered, an evidence file that says FAIL releases the route.
mutate_r2 "rung-2 PASS-assertion arm" \
  's/^  if ! grep -qE .\^\[\[:space:\]\]\*RUNG2_BOOT_REHEARSAL.*$/  if false; then/' \
  0 "$R2/ci.yml" "$R2/fail.env"

# Neutered, an unauditable pointer releases the route. Anchored on `$url` rather than on the
# URL regex itself: the gate's text contains a LITERAL `?` (`^https?://`), and in sed's BRE
# `\?` means "optional previous character", so the obvious-looking expression matches nothing
# and the mutation reports a missing guard rather than a real result.
# (#8010) The expected verdict MOVED, and the move is the point. Neutering the URL-shape
# check used to RELEASE an unauditable pointer; it now falls through to the run-id parser,
# which refuses the same input by name. The needle is what makes this row mean anything — an
# rc-only assertion would pass on any HOLD from any later arm.
mutate_r2 "rung-2 evidence-URL arm — neutered, the run-id parser is the backstop" \
  's|^  if \[\[ ! "\$url" =~ .*|  if false; then|' \
  1 "$R2/ci.yml" "$R2/nourl.env" "[RUN_UNRESOLVABLE]"

# (#7025, R6) Neutered, evidence declaring a doppler_arch divergence releases the route —
# and doppler_arch is the var that selects WHICH BINARY is downloaded and WHICH CHECKSUM
# verifies it, so the rehearsal would have proven the absence of a boot-brick production
# still has (#6570).
mutate_r2 "rung-2 render-var divergence arm" \
  's/^    if \[\[ "\$_allowed" -eq 0 \]\]; then/    if false; then/' \
  0 "$R2/ci.yml" "$R2/div-arch.env"

# NO PATH-INVARIANCE MUTATION ARM, and the absence is deliberate rather than an oversight.
# Neutering the basename normalisation makes the hash cwd-dependent, which yields a
# MISMATCH — the gate then HOLDs with STALE EVIDENCE. There is no fail-open mutation to
# assert, because the defect it fixes is a false REFUSAL, not a false release. The
# equality assertion above is the guard, and it was measured RED against the pre-#7025
# derivation before this landed.
#
# NO comment-stripping mutation arm here either, and the reason is worth recording rather than
# leaving as an absence. Neutering the `body="$(sed ...)"` line does NOT flip the
# commented-out fixture to RELEASED — the mutation battery said so — because whole-line
# comments are already refused by the `^[[:space:]]*RUNG2_...` ANCHOR in each grep, not by
# the strip. What the strip actually buys is TOLERANCE of a trailing comment on an otherwise
# valid line, which is a permissiveness property: mutating it away makes the gate STRICTER,
# so there is no fail-open mutation to assert. The positive test below is what pins it.
r2_evidence "$R2/trailing.env" PASS "$R2_URL" "$R2_SHA"
sed -i 's|^RUNG2_BOOT_REHEARSAL=PASS$|RUNG2_BOOT_REHEARSAL=PASS   # rehearsed on a throwaway host|' "$R2/trailing.env"
grep -q '#' "$R2/trailing.env" || fail "fixture setup: trailing comment was not applied" "n/a" ""
# Re-commit the edited evidence ALONE: ARM 1 refuses evidence that differs from its committed
# state, and this row is about the trailing comment, not about provenance.
_r2_commit_alone "$R2/trailing.env"
r2check "trailing comments on valid evidence => still RELEASED" 0 "RELEASED" "$R2/ci.yml" "$R2/trailing.env"

# ── A1–A10 — the rung-2 user_data hash input set (#7485) ──────────────────────────────
#
# These arms call `git_data_rung2_user_data_sha256` DIRECTLY, on a SEPARATE COPIED TREE —
# never through `r2check`/`R2_SHA`, whose `_r2_hash` mirror this same commit repairs. That
# independence is the point: a mirror and the thing it mirrors must not be each other's
# only witness.
#
# UNREADABILITY IS INJECTED WITH A DANGLING SYMLINK, NEVER `chmod 000`. Root bypasses the
# DAC mode check, so `[[ -r ]]` is TRUE for a mode-000 file under uid 0 — in any root
# container A4, A5 and A7 would go silently green against the unfixed code, which is the
# exact inverse of what they exist to prove. A dangling symlink is unreadable for every uid
# (measured: `-r` false, `-L` true), so it is the environment-independent mechanism.
#
# SIBLING BASENAMES MUST NOT COLLIDE WITH ANY PAYLOAD BASENAME, or the basename-uniqueness
# check downstream reddens these arms for the wrong reason.
#
# (`_a_setup_fail` is defined beside the fixture git helpers above, since #8043 NFR2 -- the R2
# tree is committed before this point, and the helper that reds on a silent commit uses it.)

# SETS A GLOBAL; IT DOES NOT PRINT. Called as `_aN="$(_a_tree aN)"` the helper runs in a
# COMMAND-SUBSTITUTION SUBSHELL, so `_a_setup_fail`'s `exit 2` terminated only that subshell and
# the suite carried on with `_aN=""` — building fixtures at absolute paths like `/ci.yml` and
# reporting a nonsense cause instead of the loud abort the helper's contract promises. That is
# the same subshell hazard `_a_hash` two helpers down already calls out by name ("Called
# directly, never in a command substitution, so the global survives"); this one had it.
_A_TREE=""
_a_tree() {  # $1 = arm name -> sets _A_TREE to a fresh copy of the R2 fixture tree
  local d="$TMP/a_$1"
  rm -rf "$d" || _a_setup_fail "could not clear $d"
  cp -r "$R2" "$d" || _a_setup_fail "could not copy the R2 fixture into $d"
  [[ -d "$d" ]] || _a_setup_fail "fixture tree $d was not created"
  _A_TREE="$d"
}

_a_sibling_var() { printf 'variable "doppler_config_name" {\n  default = "prd_git_data"\n}\n' > "$1"; }
_a_sibling_out() { printf 'output "rendered" {\n  value = local.rendered\n}\n' > "$1"; }

# Asserts rc=1 and that the diagnostic names the offending file.
_a_abort() {  # $1=name $2=needle $3=cloud-init
  local name="$1" needle="$2" ci="$3" out rc
  out="$(git_data_rung2_user_data_sha256 "$ci" 2>&1)"; rc=$?
  if [[ "$rc" -eq 1 && "$out" == *"$needle"* ]]; then
    pass "$name"
  else
    fail "$name (want rc=1 containing '$needle')" "$rc" "$out"
  fi
}

# Asserts rc=0 and a well-formed digest. A6 does its own before/after comparison with locals,
# so nothing is published here — an earlier draft set a global that no arm ever read.
_a_hash() {  # $1=name $2=cloud-init
  local name="$1" ci="$2" out rc
  out="$(git_data_rung2_user_data_sha256 "$ci" 2>&1)"; rc=$?
  if [[ "$rc" -eq 0 && "$out" =~ ^[0-9a-f]{64}$ ]]; then
    pass "$name"
  else
    fail "$name (want rc=0 and a 64-hex digest)" "$rc" "$out"
  fi
}

# A1 — THE COMMITTED TREE. The header above forbids asserting the GATE'S VERDICT on the live
# template, because that verdict's green depended on #6982 being unfinished. This asserts a
# DIFFERENT function's self-consistency: that the hash derivation can run at all on the tree
# as committed. It is invariant under the emitter landing (#6982 has since closed and the
# live gate now reports RELEASED), so it is not the countdown timer the header rejects. It is
# also the arm that catches an over-broad sibling abort firing on the unexpanded `*.tf.json`
# literal, which the live tree — having no `.tf.json` at all — is the only fixture to exercise.
#
# A MISSING LIVE FILE IS A LOUD FAILURE, never a silently skipped arm: skipping would drop the
# suite one below its floor and report as anti-vacuity rather than as the relocation it is.
_A1_LIVE="${ROOT}/apps/web-platform/infra/cloud-init-git-data.yml"
if [[ ! -f "$_A1_LIVE" ]]; then
  fail "A1: the live cloud-init template exists where this derivation binds it" "n/a" \
       "not found: $_A1_LIVE — if the template moved, this derivation and every consumer move with it"
else
  _a_hash "A1: the committed tree derives a 64-hex digest (rc=0)" "$_A1_LIVE"
fi

# A2 — two siblings, the live module's own shape.
_a_tree a2; _a2="$_A_TREE"
_a_sibling_var "$_a2/modules/git-data-userdata/variables.tf"
_a_sibling_out "$_a2/modules/git-data-userdata/outputs.tf"
_a_hash "A2: a module directory with two sibling .tf files returns 0" "$_a2/ci.yml"

# A3 — sibling-count independence. Three siblings must behave exactly like two.
_a_tree a3; _a3="$_A_TREE"
_a_sibling_var "$_a3/modules/git-data-userdata/variables.tf"
_a_sibling_out "$_a3/modules/git-data-userdata/outputs.tf"
printf 'terraform {\n  required_version = ">= 1.5.0"\n}\n' > "$_a3/modules/git-data-userdata/versions.tf"
_a_hash "A3: sibling-count independence — three siblings also return 0" "$_a3/ci.yml"

# A4 — a present-but-unreadable sibling must ABORT, not be silently dropped. Measured rc=0
# against the first draft's payload-loop-only shape: the hash was well-formed over a NARROWER
# set, which is the fail-open this whole change exists to prevent.
_a_tree a4; _a4="$_A_TREE"
ln -s /nonexistent/dangling-a4 "$_a4/modules/git-data-userdata/variables.tf" \
  || _a_setup_fail "could not create the A4 dangling symlink"
_a_abort "A4: an unreadable .tf sibling aborts, naming the file" \
         "variables.tf' cannot be read" "$_a4/ci.yml"

# A5 — the abort must attach to BOTH glob patterns, not just the first.
_a_tree a5; _a5="$_A_TREE"
ln -s /nonexistent/dangling-a5 "$_a5/modules/git-data-userdata/extra.tf.json" \
  || _a_setup_fail "could not create the A5 dangling symlink"
_a_abort "A5: an unreadable .tf.json sibling aborts, naming the file" \
         "extra.tf.json' cannot be read" "$_a5/ci.yml"

# A6 — a readable .tf.json is HASHED, not merely tolerated. Terraform loads .tf.json, so a
# knob written there decides what boots; asserting rc=0 alone would pass against a glob that
# skipped the file entirely. The digest must MOVE.
_a_tree a6; _a6="$_A_TREE"
_a6_before="$(git_data_rung2_user_data_sha256 "$_a6/ci.yml" 2>&1)"
printf '{"variable":{"extra_knob":{"default":"prd_git_data"}}}\n' \
  > "$_a6/modules/git-data-userdata/extra.tf.json"
_a6_after="$(git_data_rung2_user_data_sha256 "$_a6/ci.yml" 2>&1)"; _a6_rc=$?
if [[ "$_a6_rc" -eq 0 && "$_a6_after" =~ ^[0-9a-f]{64}$ && "$_a6_after" != "$_a6_before" ]]; then
  pass "A6: a readable .tf.json sibling is hashed (digest differs from the tree without it)"
else
  fail "A6: a readable .tf.json sibling is hashed (digest differs from the tree without it)" \
       "$_a6_rc" "before=${_a6_before} after=${_a6_after}"
fi

# A7 — a referenced payload that is present-but-unreadable.
_a_tree a7; _a7="$_A_TREE"
rm -f "$_a7/git-data-gc.timer" || _a_setup_fail "could not remove the A7 payload"
ln -s /nonexistent/dangling-a7 "$_a7/git-data-gc.timer" \
  || _a_setup_fail "could not create the A7 dangling symlink"
# The needle carries the `../../` prefix deliberately: that is the reference AS WRITTEN in
# main.tf, and echoing it back verbatim is what lets a reader grep the module for the failing
# binding. A needle of the bare basename would pass against a message that had lost the
# binding's actual spelling.
_a_abort "A7: an unreadable referenced payload aborts, naming it" \
         "references payload '../../git-data-gc.timer'" "$_a7/ci.yml"

# A8 — a referenced payload DELETED OUTRIGHT. This is the job the deleted referenced-vs-
# resolved counting check used to do, and the one an `-r`-only guard could lose: the abort
# must inherit it rather than let the reference resolve to nothing.
_a_tree a8; _a8="$_A_TREE"
rm -f "$_a8/git-data-gc.service" || _a_setup_fail "could not remove the A8 payload"
_a_abort "A8: a deleted referenced payload aborts, naming it" \
         "references payload '../../git-data-gc.service'" "$_a8/ci.yml"

# A9 — the floor is on the PAYLOAD count, and its message names that count. Siblings are
# present so the arm proves the floor is not merely counting `_inputs` again.
_a_tree a9; _a9="$_A_TREE"
_a_sibling_var "$_a9/modules/git-data-userdata/variables.tf"
_a_sibling_out "$_a9/modules/git-data-userdata/outputs.tf"
_r2_write_module "$_a9" git-data-bootstrap.sh git-data-gc.sh
_a_abort "A9: a module binding only 2 payloads aborts, naming the payload count" \
         "resolved only 2 payload(s)" "$_a9/ci.yml"

# A11 — THE FLOOR'S NEAR BOUNDARY. A9 alone pins the floor only at the far extreme: with every
# floor fixture binding 2 payloads, any literal in 3..9 passes the suite. Measured — changing
# `-lt 9` to `-lt 3` left the suite fully green, so the one literal the lib's own comment
# singles out ("THIS LITERAL IS WHERE THE NEW COUNT GOES") was free to drift more than half its
# range while a real shrink from 9 to 4 bindings produced a well-formed digest over a narrower
# set. The per-reference abort cannot cover this: DELETING a binding leaves every remaining
# reference resolving perfectly. n=8 is the smallest shrink that must still refuse.
_a_tree a11; _a11="$_A_TREE"
_r2_write_module "$_a11" git-data-bootstrap.sh git-data-provision.sh git-data-transport-wrapper.sh \
                         git-data-remove.sh git-data-gc.sh git-data-pre-receive-placeholder.sh \
                         git-data-gc.service git-data-gc-failure.service
_a_abort "A11: losing ONE payload (9 -> 8) still aborts — the floor is pinned at its boundary" \
         "resolved only 8 payload(s)" "$_a11/ci.yml"

# A10 — EQUIVALENCE. `_r2_hash()` is a hand-maintained reimplementation of the lib's input
# set whose comment claims the two "cannot drift" — and it had drifted twice (no sibling glob,
# a bare `file\(` where the lib matches the whole family). Byte-identity was measured once at
# repair time; a one-time measurement is not a guard. This arm makes a third drift unshippable.
#
# THE FIXTURE MUST CARRY A SIBLING, and that is not a detail. Measured: against the bare `$R2`
# tree — which has no sibling and no `filebase64` binding — deleting `_r2_hash`'s sibling glob
# outright leaves this arm GREEN, because neither implementation has anything to disagree
# about. An equivalence arm whose fixture cannot express the difference is the same defect as
# the mirror it guards: a fixture sharing the blind spot of the thing it tests. So the
# comparison runs over a tree with a sibling `.tf` AND a sibling `.tf.json`, which is where the
# two implementations actually had drifted.
_a_tree a10; _a10="$_A_TREE"
_a_sibling_var "$_a10/modules/git-data-userdata/variables.tf"
printf '{"variable":{"a10_knob":{"default":"x"}}}\n' > "$_a10/modules/git-data-userdata/extra.tf.json"
# THE ARM'S OWN PRECONDITION IS ASSERTED, not just stated above. If either write silently
# failed, the comparison would run over a sibling-less tree — which is precisely the fixture
# shape measured to leave this arm GREEN with the mirror's sibling glob deleted. An
# equivalence arm whose fixture cannot express the difference is the defect it exists to catch.
[[ -s "$_a10/modules/git-data-userdata/variables.tf" && -s "$_a10/modules/git-data-userdata/extra.tf.json" ]] \
  || _a_setup_fail "A10 fixture lost a sibling — the equivalence arm would be vacuous"
_a10_mirror="$(_r2_hash "$_a10")"
_a10_lib="$(git_data_rung2_user_data_sha256 "$_a10/ci.yml" 2>&1)"; _a10_rc=$?
if [[ "$_a10_rc" -eq 0 && -n "$_a10_mirror" && "$_a10_mirror" == "$_a10_lib" ]]; then
  pass "A10: _r2_hash equals the lib's derivation over the same fixture (mirror non-drift)"
else
  fail "A10: _r2_hash equals the lib's derivation over the same fixture (mirror non-drift)" \
       "$_a10_rc" "mirror=${_a10_mirror} lib=${_a10_lib}"
fi

# ── A12–A17 — the canonical module-shape gate (#7534) ──────────────────────────────────
#
# Before #7534 each of the four forms below rendered into user_data while the nine literal
# payloads still resolved and every floor still passed — so the evidence digest attested a
# byte set that was not what shipped. The gate now refuses them. A16 and A17 are the
# must-PASS rows constraint 2 requires: a matrix of only-RED rows cannot detect a guard that
# rejects everything, and this gate's whole risk is over-firing on a legitimate module.

# Injects a line INTO the templatefile map, before its `  })` close, so the deviant binding
# sits where a real one would rather than trailing the file.
_a_inject_binding() {  # $1 = main.tf path, $2 = line(s) to inject
  local mt="$1" line="$2"
  awk -v ins="$line" '/^  \}\)$/ && !d { print ins; d=1 } { print }' "$mt" > "$mt.new" \
    || _a_setup_fail "could not inject a binding into $mt"
  mv "$mt.new" "$mt" || _a_setup_fail "could not replace $mt"
  grep -qF "$(printf '%s' "$line" | head -1)" "$mt" \
    || _a_setup_fail "the injected binding did not land in $mt — the map-close anchor has drifted"
}

# A12 — a MULTI-LINE `file(\n "…"\n)`. The occurrence is counted; the strict single-line rule
# cannot resolve it, so the two counts disagree and the gate must name the site.
_a_tree a12; _a12="$_A_TREE"
_a_inject_binding "$_a12/modules/git-data-userdata/main.tf" \
'    a12_multi = replace(file(
      "${path.module}/../../git-data-gc.sh"
    ), local.git_data_rationale_strip, "")'
_a_abort "A12: a multi-line file() binding aborts, naming the site" \
         "in the strict single-line" "$_a12/ci.yml"

# A13 — an INDIRECTED `file(local.p)`. Not statically resolvable at all; this is the form full
# HCL parsing could not have reached either, which is why the gate narrows the shape instead.
_a_tree a13; _a13="$_A_TREE"
_a_inject_binding "$_a13/modules/git-data-userdata/main.tf" \
'    a13_indirect = file(local.a13_path)'
_a_abort "A13: an indirected file(local.p) binding aborts, naming the site" \
         "in the strict single-line" "$_a13/ci.yml"

# A14 — a SECOND `templatefile(`. A second template renders into user_data and is invisible to
# the payload extractor. Note it does NOT move the file-family count: `templatefile(` is
# preceded by `e`, so the extractor's own `(^|[^A-Za-z])` boundary excludes it — which is
# exactly why this needs its own check rather than falling out of the count comparison.
_a_tree a14; _a14="$_A_TREE"
_a_inject_binding "$_a14/modules/git-data-userdata/main.tf" \
'    a14_second = templatefile("${path.module}/../../ci.yml", {})'
_a_abort "A14: a second templatefile() aborts" \
         "templatefile(\` occurrence(s); the canonical shape has exactly 1" "$_a14/ci.yml"

# A14b — TWO `templatefile(` ON ONE PHYSICAL LINE. This is the arm that pins `grep -o | wc -l`
# against `grep -c`: the latter counts LINES, reports 1, and lets a second template through the
# check written to catch it. Measured — swapping the gate to `grep -c` leaves A14 green and
# only this arm reddens. The fixture is deliberately a nested call, the shape a real map value
# would take.
_a_tree a14b; _a14b="$_A_TREE"
python3 - "$_a14b/modules/git-data-userdata/main.tf" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
old = 'rendered = templatefile("${path.module}/../../ci.yml", {\n'
new = 'rendered = templatefile("${path.module}/../../ci.yml", { inner = templatefile("${path.module}/../../ci.yml", {}),\n'
assert old in s, "A14b: the templatefile anchor has drifted"
open(p, "w").write(s.replace(old, new, 1))
PY
[[ $? -eq 0 ]] || _a_setup_fail "A14b: could not build the one-line two-templatefile fixture"
_a_abort "A14b: two templatefile() on ONE line abort — occurrences, not lines" \
         "templatefile(\` occurrence(s); the canonical shape has exactly 1" "$_a14b/ci.yml"

# A15 — a single-line literal whose prefix is NOT `${path.module}/`. The fourth form, and the
# one undocumented until #7534: it resolves in Terraform and renders, but the extractor's
# `${path.module}` anchor cannot see it.
_a_tree a15; _a15="$_A_TREE"
_a_inject_binding "$_a15/modules/git-data-userdata/main.tf" \
'    a15_root = replace(file("${path.root}/../../git-data-gc.sh"), local.git_data_rationale_strip, "")'
_a_abort "A15: a non-\${path.module} single-line literal aborts, naming the site" \
         "in the strict single-line" "$_a15/ci.yml"

# A12b/A13b/A15b — THE "NAMING THE SITE" HALF, which was unpinned. All three arms above are
# named "…aborts, naming the site", but their needle is the count-mismatch HEADER; replacing
# the `_nonstrict_file_sites | sed` listing with `true` left the suite 77/0 green. That
# reduces the gate to exactly what the lib's own comment says the deleted arithmetic could
# only do — "report that two integers disagreed, never WHICH binding".
for _sp in "a12:$_a12:a12_multi" "a13:$_a13:a13_indirect" "a15:$_a15:path.root"; do
  _nm="${_sp%%:*}"; _rest="${_sp#*:}"; _tree="${_rest%%:*}"; _needle="${_rest##*:}"
  _out="$(git_data_rung2_user_data_sha256 "$_tree/ci.yml" 2>&1)"
  if [[ "$_out" == *"$_needle"* ]]; then
    pass "${_nm^^}b: the abort LISTS the offending binding (${_needle}), not just the counts"
  else
    fail "${_nm^^}b: the abort LISTS the offending binding (${_needle}), not just the counts" "" "$_out"
  fi
done

# A16 — MUST-PASS, and the digest must MOVE. A NEW tenth payload FILE, not a second binding to
# an existing one: the payload floor counts distinct files post-`sort -u`, so a duplicate
# binding would test the dedup rather than the growth. Two rungs, because "still produces a
# digest" alone cannot distinguish a gate that hashes the tenth payload from one that ignores
# it — which is the whole failure #7534 names.
_a_tree a16; _a16="$_A_TREE"
printf '#!/usr/bin/env bash\n# a16 extra payload\ntrue\n' > "$_a16/git-data-a16-extra.sh" \
  || _a_setup_fail "could not write the A16 tenth payload"
_r2_write_module "$_a16" "${_r2_payloads[@]}" git-data-a16-extra.sh
_a_hash "A16: a canonical module with a TENTH payload still produces a digest" "$_a16/ci.yml"
_a16_before="$(git_data_rung2_user_data_sha256 "$_a16/ci.yml" 2>&1)"
printf '# a16 edit\n' >> "$_a16/git-data-a16-extra.sh" \
  || _a_setup_fail "could not edit the A16 tenth payload"
_a16_after="$(git_data_rung2_user_data_sha256 "$_a16/ci.yml" 2>&1)"
if [[ -n "$_a16_before" && "$_a16_before" =~ ^[0-9a-f]{64}$ && "$_a16_before" != "$_a16_after" ]]; then
  pass "A16: editing the tenth payload MOVES the digest — it is bound, not merely tolerated"
else
  fail "A16: editing the tenth payload MOVES the digest — it is bound, not merely tolerated" \
       "before=${_a16_before} after=${_a16_after}"
fi

# A17 — MUST-PASS, VALUE-FORM. The templatefile map holds two classes of entry, and the gate
# quantifies over one of them. A value-form entry (`host_name = var.host_name`, and Phase 5's
# `betterstack_logs_token = var.betterstack_logs_token`) is not a `file*(` occurrence, so it
# must not trip this gate — by construction, not by exemption. This row is what proves that
# claim now, rather than discovering the interaction when Phase 5's map entry lands.
_a_tree a17; _a17="$_A_TREE"
_a_inject_binding "$_a17/modules/git-data-userdata/main.tf" \
'    a17_value = var.betterstack_logs_token'
_a_hash "A17: a value-form map entry does not trip the canonical-shape gate" "$_a17/ci.yml"

# MINIMUM-CARDINALITY FLOOR. This suite had none, and it now covers TWO gates: an early
# `exit`, a helper that silently stopped being called, or a fixture-setup failure would
# otherwise report "0 failed" — the vacuous green every guard in this file exists to reject.

# ══════════════════════════════════════════════════════════════════════════════════════
# git_data_authorization_map_gate — CPO condition C1 / #8009.
#
# SYNTHESIZED FIXTURES, per this file's header rule. `_authmap_root` builds a MINIMAL but
# COMPLETE five-link root: a cloud-init template with the three forced-command slots, a
# render module carrying the templatefile argument map, and a git-data.tf carrying the
# module call, the locals, the three tls_private_key resources and the three doppler_secret
# blocks that publish the private halves.
#
# The one live-tree arm (B23) is deliberate and is the D8 decision: it asserts the gate
# RELEASES on the tree as committed. Unlike the countdown-timer shape this file's header
# warns about, its green does not depend on any work being unfinished — the production root
# has always had three distinct keys, and the day it does not is the day this gate is
# supposed to go red.
# ══════════════════════════════════════════════════════════════════════════════════════

printf '\n=== git_data_authorization_map_gate (#8009) ===\n\n'

# Builds a canonical root at $1. Callers mutate one link, then assert.
_authmap_root() {
  local d="$1"
  assert_fixture_dir "$d"
  mkdir -p "$d/modules/git-data-userdata"
  cat > "$d/cloud-init-git-data.yml" <<'YML'
#cloud-config
write_files:
  - path: /home/git/.ssh/authorized_keys
    content: |
      command="/usr/local/bin/git-data-transport-wrapper.sh",no-port-forwarding,no-X11-forwarding,no-agent-forwarding,no-pty ${git_transport_pubkey}
      command="/usr/local/bin/git-data-provision.sh",no-port-forwarding,no-X11-forwarding,no-agent-forwarding,no-pty ${git_provision_pubkey}
      command="/usr/local/bin/git-data-remove.sh",no-port-forwarding,no-X11-forwarding,no-agent-forwarding,no-pty ${git_remove_pubkey}
    owner: root:root
    permissions: '0644'
YML
  cat > "$d/modules/git-data-userdata/main.tf" <<'TF'
locals {
  rendered = templatefile("${path.module}/../../cloud-init-git-data.yml", {
    git_transport_pubkey = var.git_transport_pubkey
    git_provision_pubkey = var.git_provision_pubkey
    git_remove_pubkey    = var.git_remove_pubkey
  })
}
TF
  cat > "$d/git-data.tf" <<'TF'
resource "tls_private_key" "git_transport" {
  algorithm = "ED25519"
}
resource "tls_private_key" "git_provision" {
  algorithm = "ED25519"
}
resource "tls_private_key" "git_remove" {
  algorithm = "ED25519"
}
locals {
  git_transport_pubkey = trimspace(tls_private_key.git_transport.public_key_openssh)
  git_provision_pubkey = trimspace(tls_private_key.git_provision.public_key_openssh)
  git_remove_pubkey    = trimspace(tls_private_key.git_remove.public_key_openssh)
}
module "git_data_userdata" {
  source                 = "./modules/git-data-userdata"
  git_transport_pubkey   = local.git_transport_pubkey
  git_provision_pubkey   = local.git_provision_pubkey
  git_remove_pubkey      = local.git_remove_pubkey
}
resource "hcloud_server" "git_data" {
  name      = "soleur-git-data"
  user_data = base64gzip(module.git_data_userdata.rendered)
}
resource "doppler_secret" "git_transport_ssh_private_key" {
  project    = "soleur"
  config     = "prd"
  name       = "GIT_TRANSPORT_SSH_PRIVATE_KEY"
  value      = tls_private_key.git_transport.private_key_openssh
}
resource "doppler_secret" "git_provision_ssh_private_key" {
  project    = "soleur"
  config     = "prd"
  name       = "GIT_PROVISION_SSH_PRIVATE_KEY"
  value      = tls_private_key.git_provision.private_key_openssh
}
resource "doppler_secret" "git_remove_ssh_private_key" {
  project    = "soleur"
  config     = "prd"
  name       = "GIT_REMOVE_SSH_PRIVATE_KEY"
  value      = tls_private_key.git_remove.private_key_openssh
}
TF
}

# _AM DECIDES ITS OWN VERDICT, SO IT NEEDS ITS OWN CONTROL.
#
# The ledger, the counter reconciliation and the assertion floor all watch pass()/fail().
# None of them can see a helper that takes the WRONG BRANCH and then calls pass() — both
# helpers behave perfectly and every counter reconciles. Measured on this file: replacing
# _am's condition with `if true; then` reported `103 passed, 0 failed`, exit 0, with all 23
# arms "running" and asserting nothing. The floor cannot help: the arms still ran.
#
# So _am is driven once in each direction with a known answer, and the counters are
# snapshotted and unwound so the probe does not pollute the totals it is protecting. This
# reports through printf + exit rather than through the helpers it backstops.
_am_self_test() {
  local _p="$passes" _f="$fails" _n="${#FAILURES[@]}"
  local _d; _d="$TMP/am-selftest"; _authmap_root "$_d"
  # The probes' own output is SUPPRESSED. The negative probe necessarily makes _am print a
  # FAIL line, and a FAIL line on screen next to a green verdict is the exact shape this
  # repo treats as a broken instrument -- it would train a reader (and any log grep) to
  # discount real ones. Only this function's own ok/FAIL line is user-visible.
  # Capture the probe's OWN view of the gate before running it through _am. The failure
  # branches below previously printed "vacuous" and nothing else, which names a conclusion
  # without the measurement behind it -- unactionable on a surface (CI) where nobody can
  # re-run it by hand, and the exact instrument-without-evidence shape this suite exists to
  # reject. Costs one extra gate call (~1s) on a path that runs once.
  local _probe_out _probe_rc
  _probe_out="$(git_data_authorization_map_gate "$_d/cloud-init-git-data.yml" 2>&1)"; _probe_rc=$?
  _am "selftest-must-pass" 0 "pairwise-distinct" "$_d" >/dev/null 2>&1
  local _after_pass="$passes"
  _am "selftest-must-fail" 99 "a needle that cannot appear anywhere" "$_d" >/dev/null 2>&1
  local _after_fail="$fails"
  passes="$_p"; fails="$_f"; FAILURES=("${FAILURES[@]:0:$_n}")
  if [[ "$_after_pass" -ne $((_p + 1)) ]]; then
    printf '  FAIL _am SELF-TEST: the accept branch did not record a pass — every _am arm is vacuous.\n'
    printf '       probe: rc=%s (want 0), needle="pairwise-distinct"\n' "$_probe_rc"
    printf '       probe output was:\n'
    printf '%s\n' "$_probe_out" | sed 's/^/         | /'
    printf '       fixture files under %s:\n' "$_d"
    find "$_d" -type f 2>/dev/null | sed 's/^/         | /'
    printf '       env: bash=%s awk=%s LC_ALL=%s TMPDIR=%s\n' \
      "$BASH_VERSION" "$(awk -W version 2>&1 | head -1)" "${LC_ALL:-unset}" "${TMPDIR:-unset}"
    exit 1
  fi
  if [[ "$_after_fail" -ne $((_f + 1)) ]]; then
    printf '  FAIL _am SELF-TEST: _am did NOT reject an impossible expectation — its condition is disarmed and all 23 arms below assert nothing.\n'
    exit 1
  fi
  printf '  ok   _am self-test: the helper both accepts and REJECTS (its 23 arms are live)\n'
}

# _am <name> <want_rc> <needle> <root-dir>
_am() {
  local name="$1" want="$2" needle="$3" d="$4" out rc
  out="$(git_data_authorization_map_gate "$d/cloud-init-git-data.yml" 2>&1)"; rc=$?
  if [[ "$rc" -eq "$want" && "$out" == *"$needle"* ]]; then
    pass "$name"
  else
    fail "$name (want rc=$want containing '$needle')" "$rc" "$out"
  fi
}


# ── awk-portability arm: every DYNAMIC awk regex must survive gawk ───────────────────
# `_git_data_hcl_block` passes its 2nd argument to awk as `$0 ~ open_re`. The two awk
# implementations disagree about `\(`: mawk keeps it as a literal paren, gawk STRIPS the
# backslash and then cannot compile the bare `(` (fatal: Unmatched `(`). Ubuntu ships mawk,
# GitHub runners ship gawk -- so this class is invisible locally and ABORTs the gate on every
# CI run, including the birth-dispatch interlock, which could then never RELEASE.
#
# Emulate gawk rather than trust a spelling: strip the backslash exactly as gawk does, then
# require the result to still COMPILE. `grep -E` exits 2 on an invalid regex and 1 on a valid
# regex that simply does not match, so the exit code separates the two.
_awk_portability_arm() {
  local _pat _stripped _rc _checked=0
  while IFS= read -r _pat; do
    [[ -n "$_pat" ]] || continue
    _checked=$((_checked + 1))
    _stripped="${_pat//\\(/(}"; _stripped="${_stripped//\\)/)}"
    grep -E "$_stripped" /dev/null >/dev/null 2>&1; _rc=$?
    if [[ "$_rc" -eq 2 ]]; then
      fail "awk-portability: '$_pat' is fatal under gawk (strips to '$_stripped', which will not compile). Use a bracket expression such as [(] instead of \\(." "$_rc" ""
    else
      pass "awk-portability: '$_pat' compiles after gawk strips its backslashes"
    fi
  done < <(grep -oE "_git_data_hcl_block \"[^\"]*\" '[^']*'" "$GATE" | sed "s/.*'\\(.*\\)'/\\1/")
  if [[ "$_checked" -eq 0 ]]; then
    printf '  FAIL awk-portability arm found NO _git_data_hcl_block call sites — the extractor is broken, not the gate clean.\n'
    exit 1
  fi
}
_awk_portability_arm

_am_self_test

# ── B1 — THE CONTROL. Every arm below is void without it. ────────────────────────────
B="$TMP/am-canonical"; _authmap_root "$B"
_am "B1: a canonical five-link root RELEASES" 0 "pairwise-distinct tls_private_key resources" "$B"

# ── The headline collapse, and its near boundary ─────────────────────────────────────
B="$TMP/am-m1"; _authmap_root "$B"
sed -i 's/${git_provision_pubkey}/${git_transport_pubkey}/; s/${git_remove_pubkey}/${git_transport_pubkey}/' "$B/cloud-init-git-data.yml"
_am "B2: all three slots on ONE variable HOLDs (the headline collapse)" 1 "resolve to only 1 distinct key" "$B"

B="$TMP/am-m2"; _authmap_root "$B"
sed -i 's/${git_remove_pubkey}/${git_provision_pubkey}/' "$B/cloud-init-git-data.yml"
_am "B3: TWO of three collapsed still HOLDs (the near boundary, 2 distinct vs 3)" 1 "resolve to only 2 distinct key" "$B"

# ── The rows that separate an ORDERED composition from a cardinality check ───────────
# Both of these are three-distinct, all-resources-present and perfectly bijective. Every
# cardinality predicate passes. Only the per-authority join catches them, and without these
# arms the suite could not tell the shipped gate from the one the plan rejected.
B="$TMP/am-m17"; _authmap_root "$B"
python3 - "$B/cloud-init-git-data.yml" <<'PYX'
import io,sys
p=sys.argv[1]; s=io.open(p,encoding='utf-8').read()
s=s.replace('git-data-transport-wrapper.sh",no-port-forwarding,no-X11-forwarding,no-agent-forwarding,no-pty ${git_transport_pubkey}','git-data-transport-wrapper.sh",no-port-forwarding,no-X11-forwarding,no-agent-forwarding,no-pty ${git_provision_pubkey}')
s=s.replace('git-data-provision.sh",no-port-forwarding,no-X11-forwarding,no-agent-forwarding,no-pty ${git_provision_pubkey}','git-data-provision.sh",no-port-forwarding,no-X11-forwarding,no-agent-forwarding,no-pty ${git_transport_pubkey}')
io.open(p,'w',encoding='utf-8').write(s)
PYX
_am "B4: a 2-SWAP at link 1 HOLDs — bijective, three-distinct, wrong authorities" 1 "PERMUTED" "$B"

B="$TMP/am-m18"; _authmap_root "$B"
python3 - "$B/git-data.tf" <<'PYX'
import io,re,sys
p=sys.argv[1]; s=io.open(p,encoding='utf-8').read()
s=re.sub(r'("git_transport_ssh_private_key".*?value      = )tls_private_key\.\w+', r'\1tls_private_key.git_provision', s, flags=re.S)
s=re.sub(r'("git_provision_ssh_private_key".*?value      = )tls_private_key\.\w+', r'\1tls_private_key.git_remove', s, flags=re.S)
s=re.sub(r'("git_remove_ssh_private_key".*?value      = )tls_private_key\.\w+', r'\1tls_private_key.git_transport', s, flags=re.S)
io.open(p,'w',encoding='utf-8').write(s)
PYX
_am "B5: a 3-CYCLE at link 5 HOLDs — this is the arm that proves predicate 4 is ORDERED" 1 "PERMUTED" "$B"

# ── Link 5: the half with no prior coverage anywhere ─────────────────────────────────
B="$TMP/am-m12"; _authmap_root "$B"
sed -i 's/^  value      = tls_private_key.git_transport.private_key_openssh/  value      = tls_private_key.git_remove.private_key_openssh/' "$B/git-data.tf"
_am "B6: the app's TRANSPORT secret publishing the ERASE key HOLDs" 1 "PERMUTED" "$B"

# ── Attribute predicates: address-distinct, bijective, and still catastrophic ─────────
B="$TMP/am-m19"; _authmap_root "$B"
sed -i 's/git_remove_pubkey    = trimspace(tls_private_key.git_remove.public_key_openssh)/git_remove_pubkey    = trimspace(tls_private_key.git_remove.private_key_openssh)/' "$B/git-data.tf"
_am "B7: a PRIVATE key rendered into user_data HOLDs (Hetzner stores it as metadata)" 1 "bakes the private half into user_data" "$B"

B="$TMP/am-m20"; _authmap_root "$B"
sed -i 's/^  value      = tls_private_key.git_remove.private_key_openssh/  value      = tls_private_key.git_remove.public_key_openssh/' "$B/git-data.tf"
_am "B8: a doppler_secret publishing a PUBLIC key HOLDs" 1 "authenticates with private_key_openssh" "$B"

# ── The slot-shape rows. B9 is the one a script-name assertion cannot see at all. ─────
B="$TMP/am-m26"; _authmap_root "$B"
sed -i 's|^\(      command="/usr/local/bin/git-data-remove.sh".*\)$|\1\n      ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEXAMPLEEXAMPLEEXAMPLEEXAMPLEEXAMPLEEX nobody@example|' "$B/cloud-init-git-data.yml"
_am "B9: a FOURTH key with no forced command at all HOLDs (raw git-shell fall-through)" 1 "ADR-068 pins exactly 3" "$B"

B="$TMP/am-m27"; _authmap_root "$B"
sed -i 's|git-data-remove.sh",no-port-forwarding|git-data-remove.sh",environment="GIT_DATA_REPO_ROOT=/srv",no-port-forwarding|' "$B/cloud-init-git-data.yml"
_am "B10: an EXTRA forced-command option HOLDs (environment= + PermitUserEnvironment)" 1 "not the canonical" "$B"

B="$TMP/am-m21"; _authmap_root "$B"
sed -i '/git-data-remove.sh/d' "$B/cloud-init-git-data.yml"
_am "B11: a DELETED slot HOLDs (two slots, two distinct keys, one missing authority)" 1 "ADR-068 pins exactly 3" "$B"

# ── Root-scope and merge-order rows ──────────────────────────────────────────────────
B="$TMP/am-m23"; _authmap_root "$B"
python3 - "$B/git-data.tf" "$B/git-data-keys.tf" <<'PYX'
import io,sys
p,q=sys.argv[1],sys.argv[2]; s=io.open(p,encoding='utf-8').read()
s=s.replace('  git_remove_pubkey    = trimspace(tls_private_key.git_remove.public_key_openssh)\n','')
io.open(p,'w',encoding='utf-8').write(s)
io.open(q,'w',encoding='utf-8').write('locals {\n  git_remove_pubkey = trimspace(tls_private_key.git_transport.public_key_openssh)\n}\n')
PYX
_am "B12: a local moved to a SIBLING .tf and re-pointed HOLDs (root-scoped, not file-scoped)" 1 "resolve to only 2 distinct key" "$B"

B="$TMP/am-m14"; _authmap_root "$B"
printf 'locals {\n  git_remove_pubkey = trimspace(tls_private_key.git_transport.public_key_openssh)\n}\n' > "$B/locals_override.tf"
_am "B13: an *override.tf present ABORTS — Terraform would merge it and the gate cannot see it" 2 "override file is present" "$B"

B="$TMP/am-m15"; _authmap_root "$B"
cat >> "$B/git-data.tf" <<'TFX'
module "git_data_userdata_v2" {
  source                 = "./modules/git-data-userdata"
  git_transport_pubkey   = local.git_transport_pubkey
  git_provision_pubkey   = local.git_transport_pubkey
  git_remove_pubkey      = local.git_transport_pubkey
}
TFX
_am "B14: a SECOND render module HOLDs (a second module is a second authorization map)" 1 "declare source" "$B"

# ── Premise, dangling-alias and instrument rows ──────────────────────────────────────
B="$TMP/am-m25"; _authmap_root "$B"
sed -i 's/^resource "hcloud_server" "git_data" {/resource "hcloud_server" "git_data" {\n  lifecycle {\n    ignore_changes = [user_data]\n  }/' "$B/git-data.tf"
_am "B15: ignore_changes on user_data HOLDs — it deletes this gate's OWN premise" 1 "ONLY route" "$B"

B="$TMP/am-m11"; _authmap_root "$B"
sed -i 's/^resource "tls_private_key" "git_remove" {/resource "tls_private_key" "git_remove_RENAMED" {/' "$B/git-data.tf"
_am "B16: three DANGLING aliases HOLD — pairwise distinct and creating nothing" 1 "no such resource block exists" "$B"

B="$TMP/am-m10"; _authmap_root "$B"
sed -i 's/git_remove_pubkey    = trimspace(tls_private_key.git_remove.public_key_openssh)/git_remove_pubkey    = var.git_remove_pubkey_default/' "$B/git-data.tf"
_am "B17: a NON-RESOURCE terminal HOLDs (a variable default can hold any key at all)" 1 "NON-RESOURCE terminal" "$B"

B="$TMP/am-m22"; _authmap_root "$B"
sed -i 's/git_remove_pubkey    = trimspace(tls_private_key.git_remove.public_key_openssh)/git_remove_pubkey    = trimspace(local.some_intermediate)/' "$B/git-data.tf"
_am "B18: resolving 2 of 3 slots ABORTS — partial extraction is a broken instrument" 2 "broken instrument" "$B"

B="$TMP/am-m7"; _authmap_root "$B"
sed -i 's|  - path: /home/git/.ssh/authorized_keys|  - path: /home/git/.ssh/authorized_keys_RENAMED|' "$B/cloud-init-git-data.yml"
_am "B19: extracting ZERO slots ABORTS — zero is a broken instrument, never a pass" 2 "broken instrument" "$B"

# ── The stripper's two arms. B21 is the one that keeps this gate from being BORN RED. ─
B="$TMP/am-slashes"; _authmap_root "$B"
printf 'locals {\n  # a comment quoting a URL: https://example.com/x and a glob a//b\n  irrelevant = "https://soleur.ai/api/webhooks/github"\n}\n' > "$B/urls.tf"
_am "B20: // inside a STRING and inside a # comment does NOT abort (81 such live, none a comment)" 0 "pairwise-distinct" "$B"

B="$TMP/am-hclcomment"; _authmap_root "$B"
printf 'locals {\n  irrelevant = "x" // a genuine HCL line comment outside any string\n}\n' > "$B/comment.tf"
_am "B21: a GENUINE // comment outside a string ABORTS rather than being mis-parsed" 2 "outside a string" "$B"

# ── Fail-closed, and the live tree ───────────────────────────────────────────────────
_out="$(git_data_authorization_map_gate 2>&1)"; _rc=$?
if [[ "$_rc" -eq 2 && "$_out" == *"ABORT"* ]]; then
  pass "B22: a bare call with no argument ABORTS — the instrument refuses, fail-closed"
else
  fail "B22: a bare call with no argument ABORTS" "$_rc" "$_out"
fi

# B23 — THE LIVE-TREE ARM (D8). This is what buys PR-time coverage without a new workflow
# step: any pull request that collapses, permutes or re-points the production authorization
# map reddens this suite in CI, at review time, before merge.
_out="$(git_data_authorization_map_gate "${ROOT}/apps/web-platform/infra/cloud-init-git-data.yml" 2>&1)"; _rc=$?
if [[ "$_rc" -eq 0 ]]; then
  pass "B23: the LIVE production root releases — three authorities, three distinct keys"
else
  fail "B23: the LIVE production root releases (rc=$_rc). If this is an ABORT the gate could not PARSE the root; if a HOLD the authorization map itself is wrong. The message distinguishes them." "$_rc" "$_out"
fi


# ══════════════════════════════════════════════════════════════════════════════════════
# B24-B36 — THE ESCAPES A SIX-AGENT REVIEW FOUND, EACH PINNED BY ITS OWN ARM.
#
# Every row below was MEASURED releasing (rc=0) against a copy of the live production root
# before it was closed. They share one shape: a scan that was ROOT-wide where the property
# is BLOCK-scoped, or a predicate applied at one site and not its twin. They are here
# because a fix without a fixture is exactly as unpinned as the blind spot it closed --
# and because the first battery, 26 rows and all killed, could not see any of them: every
# row it had perturbed the SUT toward an obviously-broken spelling, and these are all
# innocuous-looking SIBLING declarations that mask a real defect.
# ══════════════════════════════════════════════════════════════════════════════════════

# --- the two that mask the headline defects this gate exists to catch ------------------
B="$TMP/am-b24"; _authmap_root "$B"
sed -i 's|git_remove_pubkey    = trimspace(tls_private_key.git_remove.public_key_openssh)|git_remove_pubkey    = trimspace(tls_private_key.git_transport.public_key_openssh)|' "$B/git-data.tf"
cat > "$B/zz-outputs.tf" <<'TFX'
output "git_data_key_fingerprints" {
  value = {
    git_remove_pubkey = tls_private_key.git_remove.public_key_openssh
  }
}
TFX
_am "B24: a collapse masked by an unrelated output block still HOLDs (link 4 is locals-scoped)" 1 "resolve to only" "$B"

B="$TMP/am-b25"; _authmap_root "$B"
sed -i 's|^  value      = tls_private_key.git_remove.private_key_openssh|  value      = tls_private_key.git_transport.private_key_openssh|' "$B/git-data.tf"
cat > "$B/zz-dev.tf" <<'TFX'
resource "doppler_secret" "git_remove_dev" {
  project    = "soleur"
  config     = "dev"
  name       = "GIT_REMOVE_SSH_PRIVATE_KEY"
  value      = tls_private_key.git_remove.private_key_openssh
}
TFX
_am "B25: a permutation masked by a dev-config mirror still HOLDs (link 5 keys on config too)" 1 "PERMUTED" "$B"

# --- ambiguity: the gate must not pick a winner it cannot evaluate --------------------
B="$TMP/am-b26"; _authmap_root "$B"
sed -i 's|git_remove_pubkey    = trimspace(tls_private_key.git_remove.public_key_openssh)|git_remove_pubkey    = trimspace(var.x ? tls_private_key.git_remove.public_key_openssh : tls_private_key.git_transport.public_key_openssh)|' "$B/git-data.tf"
_am "B26: a ternary naming two keys ABORTS — which renders is not statically decidable" 2 "references 2 tls_private_key" "$B"

B="$TMP/am-b27"; _authmap_root "$B"
sed -i 's|^  value      = tls_private_key.git_remove.private_key_openssh|  value      = try(tls_private_key.git_remove.private_key_openssh, tls_private_key.git_transport.private_key_openssh)|' "$B/git-data.tf"
_am "B27: try() with a fallback key ABORTS at link 5 — the SAME rule as link 4, both sites" 2 "references 2 tls_private_key" "$B"

B="$TMP/am-b28"; _authmap_root "$B"
sed -i 's|git_remove_pubkey    = trimspace(tls_private_key.git_remove.public_key_openssh)|git_remove_pubkey    = trimspace(coalesce(tls_private_key.git_remove.public_key_openssh, var.emergency))|' "$B/git-data.tf"
_am "B28: a var. fallback beside a valid terminal HOLDs (predicate 2 runs on EVERY rhs)" 1 "NON-RESOURCE terminal" "$B"

# --- scope: the gate must read the right block, and the right file --------------------
B="$TMP/am-b29"; _authmap_root "$B"
sed -i 's|  user_data = base64gzip(module.git_data_userdata.rendered)|  user_data = base64gzip(local.v2)|' "$B/git-data.tf"
printf 'locals {\n  decoy = base64gzip(module.git_data_userdata.rendered)\n}\n' > "$B/zz-decoy.tf"
_am "B29: the user_data pin is scoped to the SERVER block, not grepped over the root" 1 "own user_data" "$B"

B="$TMP/am-b30"; _authmap_root "$B"
sed -i 's|^resource "hcloud_server" "git_data" {|resource "hcloud_server" "git_data_v2" {|' "$B/git-data.tf"
_am "B30: renaming the server ABORTS — its absence made the ignore_changes arm vacuous" 2 "no resource" "$B"

B="$TMP/am-b31"; _authmap_root "$B"
sed -i 's|cloud-init-git-data.yml|cloud-init-git-data-v2.yml|' "$B/modules/git-data-userdata/main.tf"
_am "B31: the module rendering a DIFFERENT template HOLDs — links 1 and 2 are now bound" 1 "never boots" "$B"

# --- population growth: ADD a member rather than editing one --------------------------
B="$TMP/am-b32"; _authmap_root "$B"
cat >> "$B/git-data.tf" <<'TFX'
module "git_data_userdata_b" {
  source                 = "./modules/git-data-userdata-b"
  git_transport_pubkey   = local.git_transport_pubkey
  git_provision_pubkey   = local.git_transport_pubkey
  git_remove_pubkey      = local.git_transport_pubkey
}
resource "hcloud_server" "git_data_b" {
  name      = "soleur-git-data-b"
  user_data = base64gzip(module.git_data_userdata_b.rendered)
}
TFX
_am "B32: a SECOND rendering server HOLDs — a second host is a second unwalked map" 1 "render a module into user_data" "$B"

B="$TMP/am-b33"; _authmap_root "$B"
cat > "$B/zz-stray.tf" <<'TFX'
resource "doppler_secret" "stray_copy" {
  project    = "soleur"
  config     = "prd"
  name       = "SOME_OTHER_NAME"
  value      = tls_private_key.git_remove.private_key_openssh
}
TFX
_am "B33: the erase key republished under ANOTHER name HOLDs (the loop visits 3 names only)" 1 "outside the three-authority map" "$B"

B="$TMP/am-b34"; _authmap_root "$B"
printf '{"module":{"b":{"source":"./modules/git-data-userdata"}}}\n' > "$B/extra.tf.json"
_am "B34: a root *.tf.json ABORTS — Terraform loads it, this gate cannot parse it" 2 "tf.json" "$B"

# --- the template: write_files is not the only writer ---------------------------------
B="$TMP/am-b35"; _authmap_root "$B"
printf 'runcmd:\n  - [ bash, -c, "echo ssh-ed25519 AAAAEVIL x@y >> /home/git/.ssh/authorized_keys" ]\n' >> "$B/cloud-init-git-data.yml"
_am "B35: a runcmd appending a key HOLDs — runcmd runs AFTER write_files" 1 "outside its write_files" "$B"

B="$TMP/am-b36"; _authmap_root "$B"
python3 - "$B/cloud-init-git-data.yml" <<'PYX'
import io,sys
p=sys.argv[1]; s=io.open(p,encoding='utf-8').read()
s=s.replace("""  - path: /home/git/.ssh/authorized_keys
    content: |
""","""  - path: /home/git/.ssh/authorized_keys
    encoding: b64
    content: ${authorized_keys_b64}
  - path: /tmp/decoy
    content: |
""",1)
io.open(p,'w',encoding='utf-8').write(s)
PYX
_am "B36: a base64 authorized_keys ABORTS — the extractor must not latch onto a later block" 2 "literal" "$B"

# --- (#8043 F7) the OWNER of the map: the constrained principal must not own it -----------
# The arm used to REQUIRE git:git on a rationale measured false (a root-owned 0644 map inside a
# root:git 0750 .ssh authenticates in the pinned image). B37 pins the flip in the direction that
# rots: a template that hands the map back to the git account must HOLD, naming root:root.
B="$TMP/am-b37"; _authmap_root "$B"
sed -i 's|^    owner: root:root$|    owner: git:git|' "$B/cloud-init-git-data.yml"
_am "B37: an authorized_keys owned by git:git HOLDs — the constrained principal would own its own map" 1 "root:root" "$B"

# B38 — 0600 under root ownership is UNREADABLE by sshd (it opens the map as the target user;
# measured "Permission denied" in the pinned image), so every push is refused. The mode is
# part of the map, in the direction a "tighten it" edit would take.
B="$TMP/am-b38"; _authmap_root "$B"
sed -i "s|^    permissions: '0644'$|    permissions: '0600'|" "$B/cloud-init-git-data.yml"
_am "B38: a root-owned map at 0600 HOLDs — unreadable by the git uid sshd reads it as" 1 "0644" "$B"

# ── G1–G26 — Guard 4 (#8043 NFR2): a voided attestation cannot be made to look fresh ──────
#
# THE PROPERTY. git-data-rung2-boot-evidence.env is never MODIFIED in the same change as any
# of the 13 hash-bound files; it may only be DELETED there, or CREATED by a rehearsal PR that
# touches none of them. The rehearsal gate cannot see this by itself: its provenance check is
# a URL-shape regex, so a payload edit plus a hand-edited RUNG2_TEMPLATE_SHA256 is hash-valid
# evidence citing a rehearsal that never booted the shipped bytes.
#
# EVERY ROW RUNS AGAINST A THROWAWAY REPOSITORY under $TMP built by `_g_repo` from the same
# `_r2_write_module` writer the R2 battery uses, plus the two module siblings the live tree
# carries -- so the derived roster is 13 entries wide, exactly as in production (G1 asserts
# that before anything else runs). Each fixture is at least two commits deep; `_g_commit`
# reds the HARNESS if a commit silently fails to land (G12 proves that guard fires).
#
# Row numbers in the names are the plan's mutation-matrix rows (§ Guard 4).
printf '\nguard 4 — evidence provenance (#8043 NFR2)\n'

_G_URL="https://github.com/jikig-ai/soleur/actions/runs/17260000001"
_G_URL2="https://github.com/jikig-ai/soleur/actions/runs/17260000002"

# _g_repo <dir> [with-evidence]
#   c1: template + 3 module .tf + 9 payloads (13 files). No evidence.
#   c2 (with-evidence only): hash-matched evidence, committed ALONE -- the rehearsal-PR shape.
_g_repo() {
  local d="$1" ev="${2:-}" p
  assert_fixture_dir "$d"
  rm -rf "$d"; mkdir -p "$d" || _a_setup_fail "could not create $d"
  cp "$TMP/mixed.yml" "$d/ci.yml" || _a_setup_fail "could not seed the template into $d"
  _r2_write_module "$d" "${_r2_payloads[@]}"
  _a_sibling_var "$d/modules/git-data-userdata/variables.tf"
  _a_sibling_out "$d/modules/git-data-userdata/outputs.tf"
  for p in "${_r2_payloads[@]}"; do printf '#!/usr/bin/env bash\n# %s\ntrue\n' "$p" > "$d/$p"; done
  git -C "$d" init -q -b main || _a_setup_fail "git init failed in $d"
  _g_commit "$d" "c1: template, module, payloads"
  if [[ "$ev" == "with-evidence" ]]; then
    _r2_evidence_write "$d/evidence.env" PASS "$_G_URL" "$(_r2_hash "$d")"
    _g_commit "$d" "c2: evidence (rehearsal PR shape)"
  fi
}
_g_head() { git -C "$1" rev-parse HEAD; }

# _g <name> <want_rc> <needle> <fn> <args...> -- run a lib function and assert rc + needle.
_g() {
  local name="$1" want_rc="$2" needle="$3" out rc; shift 3
  out="$("$@" 2>&1)"; rc=$?
  if [[ "$rc" -eq "$want_rc" && "$out" == *"$needle"* ]]; then
    pass "$name"
  else
    fail "$name (want rc=$want_rc containing '$needle')" "$rc" "$out"
  fi
}

# mutate_g <label> <sed_expr> <want_rc> <fn> <args...> -- the mutate_r2 idiom, for any function.
mutate_g() {
  local label="$1" sed_expr="$2" want_rc="$3" mutated out rc
  # The needle rides an ENV var rather than a 4th positional, because every remaining
  # argument is the function-and-args vector this helper forwards.
  local _mg_needle="${MUTATE_G_NEEDLE:-}"
  shift 3
  mutated="$TMP/mutated-g.sh"
  sed "$sed_expr" "$GATE" > "$mutated"
  if cmp -s "$mutated" "$GATE"; then
    fail "$label — the mutation matched NOTHING in the gate (byte-identical copy); the guard is missing or the sed expression drifted." "n/a" "no textual change"
    return
  fi
  out="$(bash -c 'source "$1"; shift; "$@"' _ "$mutated" "$@" 2>&1)"; rc=$?
  # (#8010) Same needle contract as mutate_r2 above — see its comment for why an rc-only
  # assertion is vacuous on any row whose mutation leaves the verdict at HOLD.
  if [[ "$rc" -eq "$want_rc" ]] && { [[ -z "$_mg_needle" ]] || [[ "$out" == *"$_mg_needle"* ]]; }; then
    pass "$label (arm is load-bearing — neutering it flips the verdict)"
  else
    fail "$label — the arm did NOT change behavior when neutered; it may be dead code${_mg_needle:+ (wanted '"'"'$_mg_needle'"'"')}" "$rc" "$out"
  fi
}

# gA — row 1: a template edit and the moved digest, in ONE commit (the squash shape).
_gA="$TMP/gA"; _g_repo "$_gA" with-evidence; _gA_c2="$(_g_head "$_gA")"
printf '\n# a later edit to the template\n' >> "$_gA/ci.yml"
_r2_evidence_write "$_gA/evidence.env" PASS "$_G_URL" "$(_r2_hash "$_gA")"
_g_commit "$_gA" "c3: template edit + hash edit"; _gA_c3="$(_g_head "$_gA")"

# G1 — harness: the roster this guard quantifies over is 13 wide here, as in production. A
# narrower roster would make G6's empty-roster mutation prove less than it claims.
_g_roster_n="$(git_data_rung2_bound_files "$_gA/ci.yml" 2>/dev/null | grep -c . || true)"
if [[ "$_g_roster_n" -ge 13 ]]; then
  pass "G1: harness — the derived bound-file roster has ${_g_roster_n} entries (>= 13)"
else
  fail "G1: harness — the derived bound-file roster has fewer than 13 entries" "n/a" "roster=${_g_roster_n}"
fi

_g "G2: row 1 — template edit + hash edit in one commit => the REHEARSAL GATE holds (ARM 1 is wired in)" \
  1 "ci.yml" git_data_rung2_rehearsal_gate "$_gA/ci.yml" "$_gA/evidence.env"
_g "G3: row 1 — the same shape seen by ARM 2 over the range => HOLD" \
  1 "ci.yml" git_data_rung2_evidence_provenance_gate "$_gA/ci.yml" "$_gA/evidence.env" range "$_gA_c2" "$_gA_c3"

# gB — row 2: a payload edit alongside a NON-hash key (the URL). The hash is left stale on
# purpose: the row is about provenance, so it calls ARM 1 directly rather than through the
# gate's hash check.
_gB="$TMP/gB"; _g_repo "$_gB" with-evidence; _gB_c2="$(_g_head "$_gB")"
printf '\n# a later edit to a shipped payload\n' >> "$_gB/git-data-gc.sh"
_r2_evidence_write "$_gB/evidence.env" PASS "$_G_URL2" "$(_r2_hash "$_gB")"
_g_commit "$_gB" "c3: payload edit + url edit"; _gB_c3="$(_g_head "$_gB")"
_g "G4: row 2 — any other evidence key edited alongside a payload edit => ARM 1 HOLD naming the payload" \
  1 "git-data-gc.sh" git_data_rung2_evidence_provenance_gate "$_gB/ci.yml" "$_gB/evidence.env" birth
_g "G5: row 2 — the same shape seen by ARM 2 => HOLD" \
  1 "git-data-gc.sh" git_data_rung2_evidence_provenance_gate "$_gB/ci.yml" "$_gB/evidence.env" range "$_gB_c2" "$_gB_c3"

# gC — row 10: the squash-shaped commit touching the evidence AND git-data-remove.sh, with
# the digest moved to match. Hash-VALID, provenance-VOID: the exact shape the gate could not
# see before this guard.
_gC="$TMP/gC"; _g_repo "$_gC" with-evidence; _gC_c2="$(_g_head "$_gC")"
printf '\n# a later edit to the erasure path\n' >> "$_gC/git-data-remove.sh"
_r2_evidence_write "$_gC/evidence.env" PASS "$_G_URL" "$(_r2_hash "$_gC")"
_g_commit "$_gC" "c3: remove.sh edit + hash edit (squash shape)"; _gC_c3="$(_g_head "$_gC")"
_g "G17: row 10 — a squash commit touching evidence + git-data-remove.sh => ARM 1 HOLD" \
  1 "git-data-remove.sh" git_data_rung2_evidence_provenance_gate "$_gC/ci.yml" "$_gC/evidence.env" birth
_g "G18: row 10 — the SAME evidence is hash-valid, and the rehearsal gate still HOLDs on provenance" \
  1 "git-data-remove.sh" git_data_rung2_rehearsal_gate "$_gC/ci.yml" "$_gC/evidence.env"

# G6 — row 3: neuter the derivation to an EMPTY bound set. A naive guard intersects nothing
# with the commit and PASSes; this one must refuse a roster below its structural floor.
mutate_g "G6: row 3 — an EMPTY bound-file roster is refused (rc=1), never an empty intersection" \
  's|^  printf '"'"'%s\\n'"'"' "${_inputs\[@\]}"$|  :|' \
  1 git_data_rung2_evidence_provenance_gate "$_gC/ci.yml" "$_gC/evidence.env" birth

# G7 — row 4: bind only the TEMPLATE in the intersection (the roster stays 13 wide, so the
# floor is not what catches it). The remove.sh fixture then PASSes -- which is to say G17/G18
# would go RED under this mutation, so the suite catches a guard that stops at the template.
mutate_g "G7: row 4 — intersecting only the template lets a payload edit + evidence edit PASS (G17 is load-bearing over payloads)" \
  's|^    for _rel in "${_bound_rel\[@\]}"; do$|    for _rel in "${_bound_rel[0]}"; do|' \
  0 git_data_rung2_evidence_provenance_gate "$_gC/ci.yml" "$_gC/evidence.env" birth

# G19 — the WIRING is load-bearing: neuter ARM 1's call inside the rehearsal gate and the
# hash-valid, provenance-void evidence RELEASES the birth route.
_stub_run 17260000001 "head_sha=$(git -C "$_gC" rev-parse HEAD)"   # (#8010) _G_URL, for gC's tree
mutate_g "G19: neutering ARM 1's call inside git_data_rung2_rehearsal_gate releases the voided attestation" \
  's|^  if ! _prov_out="$(git_data_rung2_evidence_provenance_gate .*|  if false; then|' \
  0 git_data_rung2_rehearsal_gate "$_gC/ci.yml" "$_gC/evidence.env"

# gD — row 5 (MUST-PASS): this PR's own shape. Bound files change and the evidence is DELETED.
_gD="$TMP/gD"; _g_repo "$_gD" with-evidence; _gD_c2="$(_g_head "$_gD")"
printf '\n# a later edit to the template\n' >> "$_gD/ci.yml"
printf '\n# a later edit to a shipped payload\n' >> "$_gD/git-data-gc.sh"
rm -f "$_gD/evidence.env"
_g_commit "$_gD" "c3: bound edits + evidence deleted"; _gD_c3="$(_g_head "$_gD")"
_g "G8: row 5 MUST-PASS — bound files change and the evidence is DELETED => ARM 2 passes" \
  0 "PASS" git_data_rung2_evidence_provenance_gate "$_gD/ci.yml" "$_gD/evidence.env" range "$_gD_c2" "$_gD_c3"
_g "G9: row 5 — the deleted evidence is still a HOLD at the birth (absent file), unchanged" \
  1 "no rung-2 boot evidence" git_data_rung2_rehearsal_gate "$_gD/ci.yml" "$_gD/evidence.env"

# gE — row 6 (MUST-PASS): a rehearsal PR that CREATES the evidence and touches none of the 13.
_gE="$TMP/gE"; _g_repo "$_gE"; _gE_c1="$(_g_head "$_gE")"
_r2_evidence_write "$_gE/evidence.env" PASS "$_G_URL" "$(_r2_hash "$_gE")"
_g_commit "$_gE" "c2: evidence created alone"; _gE_c2="$(_g_head "$_gE")"
_g "G10: row 6 MUST-PASS — a rehearsal commit creating the evidence and nothing else => ARM 2 passes" \
  0 "rehearsal-PR shape" git_data_rung2_evidence_provenance_gate "$_gE/ci.yml" "$_gE/evidence.env" range "$_gE_c1" "$_gE_c2"
_stub_run 17260000001 "head_sha=$_gE_c2"   # (#8010) _G_URL, re-seeded for gE's tree
_g "G11: row 6 MUST-PASS — the same tree RELEASES the rehearsal gate (ARM 1 sees an evidence-only commit)" \
  0 "RELEASED" git_data_rung2_rehearsal_gate "$_gE/ci.yml" "$_gE/evidence.env"

# G12 — row 7: the HARNESS row. Strip the identity `git_fixture_env` exported and pin
# user.useConfigOnly so git cannot guess one from the host: `git commit` then fails with
# "Author identity unknown" -- silently, because _g_commit discards its status by design.
# The invariant check inside _g_commit must red the harness (exit 2, "HARNESS ABORT"); it
# must not hand the SUT an unchanged tree. Run in a subshell so the abort is observable.
_gK="$TMP/gK"; _g_repo "$_gK"
printf '\n# an edit that will not be committed\n' >> "$_gK/ci.yml"
_gK_out="$( ( unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
              export GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_1=user.useConfigOnly GIT_CONFIG_VALUE_1=true
              _g_commit "$_gK" "c2: attempted with no identity" ) 2>&1 )"; _gK_rc=$?
if [[ "$_gK_rc" -eq 2 && "$_gK_out" == *"HARNESS ABORT"* && "$_gK_out" == *"NO new commit"* ]]; then
  pass "G12: row 7 harness — a silently failing fixture commit reds the HARNESS, not the SUT"
else
  fail "G12: row 7 harness — a silently failing fixture commit must red the harness (want rc=2 + 'HARNESS ABORT' + 'NO new commit')" "$_gK_rc" "$_gK_out"
fi

# G13/G14/G15 — row 8: an unresolvable base and a shallow clone are NAMED holds, distinct
# from an empty diff. `git diff 000…0 HEAD` fails and prints NOTHING, which a naive reader
# takes for "no changes"; the all-zeros sentinel is what github.event.before carries on a
# branch-create push.
_g "G13: row 8 — the all-zeros branch-create sentinel as a base => a NAMED HOLD" \
  1 "sentinel" git_data_rung2_evidence_provenance_gate "$_gA/ci.yml" "$_gA/evidence.env" range 0000000000000000000000000000000000000000 HEAD
_gS="$TMP/gS"
git clone -q --depth 1 "file://$_gE" "$_gS" 2>/dev/null || _a_setup_fail "could not make a shallow clone of $_gE"
[[ "$(git -C "$_gS" rev-parse --is-shallow-repository)" == "true" ]] || _a_setup_fail "the clone at $_gS is not shallow"
_g "G14: row 8 — a SHALLOW checkout => a NAMED HOLD (provenance cannot be read from depth 1)" \
  1 "SHALLOW" git_data_rung2_evidence_provenance_gate "$_gS/ci.yml" "$_gS/evidence.env" birth
# The control: an EMPTY diff is a pass that says the evidence was untouched -- and the two
# unresolvable-base holds above must not be wearing its words.
_g15_out="$(git_data_rung2_evidence_provenance_gate "$_gA/ci.yml" "$_gA/evidence.env" range "$_gA_c3" "$_gA_c3" 2>&1)"; _g15_rc=$?
_g13_out="$(git_data_rung2_evidence_provenance_gate "$_gA/ci.yml" "$_gA/evidence.env" range 0000000000000000000000000000000000000000 HEAD 2>&1)"
if [[ "$_g15_rc" -eq 0 && "$_g15_out" == *"untouched"* && "$_g13_out" != *"untouched"* ]]; then
  pass "G15: row 8 control — an EMPTY range passes as 'untouched', and the sentinel HOLD does not reuse that word"
else
  fail "G15: row 8 control — empty range must PASS as 'untouched' and the sentinel HOLD must be worded differently" "$_g15_rc" "empty=${_g15_out} | sentinel=${_g13_out}"
fi

# gF — row 9 (MUST-PASS): the last evidence-touching commit touches ONLY the evidence
# (a URL correction on top of an existing attestation).
_gF="$TMP/gF"; _g_repo "$_gF" with-evidence
_r2_evidence_write "$_gF/evidence.env" PASS "$_G_URL2" "$(_r2_hash "$_gF")"
_g_commit "$_gF" "c3: evidence URL edit alone"
_g "G16: row 9 MUST-PASS — the last evidence-touching commit touches only the evidence => ARM 1 passes" \
  0 "PASS" git_data_rung2_evidence_provenance_gate "$_gF/ci.yml" "$_gF/evidence.env" birth

# G20 — a ROOT commit carrying the evidence with everything else. `git diff-tree -r <root>`
# prints NOTHING without --root, so the intersection would be empty and the guard would PASS
# the one commit that provably touched all 14 files. Pins --root.
_gG="$TMP/gG"; assert_fixture_dir "$_gG"; rm -rf "$_gG"; mkdir -p "$_gG"
cp "$TMP/mixed.yml" "$_gG/ci.yml"; _r2_write_module "$_gG" "${_r2_payloads[@]}"
_a_sibling_var "$_gG/modules/git-data-userdata/variables.tf"; _a_sibling_out "$_gG/modules/git-data-userdata/outputs.tf"
for _p in "${_r2_payloads[@]}"; do printf '#!/usr/bin/env bash\n# %s\ntrue\n' "$_p" > "$_gG/$_p"; done
_r2_evidence_write "$_gG/evidence.env" PASS "$_G_URL" "$(_r2_hash "$_gG")"
git -C "$_gG" init -q -b main || _a_setup_fail "git init failed in $_gG"
_g_commit "$_gG" "c1: everything, including the evidence (root commit)"
_g "G20: a ROOT commit carrying evidence + bound files => ARM 1 HOLD (diff-tree --root is load-bearing)" \
  1 "ci.yml" git_data_rung2_evidence_provenance_gate "$_gG/ci.yml" "$_gG/evidence.env" birth

# G21/G22 — evidence with NO readable provenance: a working-tree edit, and a never-committed file.
printf '# an uncommitted edit\n' >> "$_gF/evidence.env"
_g "G21: evidence that differs from its committed state => a NAMED HOLD (a working-tree edit has no provenance)" \
  1 "committed state" git_data_rung2_evidence_provenance_gate "$_gF/ci.yml" "$_gF/evidence.env" birth
_gI="$TMP/gI"; _g_repo "$_gI"
_r2_evidence_write "$_gI/evidence.env" PASS "$_G_URL" "$(_r2_hash "$_gI")"
_g "G22: evidence that was never committed => a NAMED HOLD (no commit touches it)" \
  1 "no commit" git_data_rung2_evidence_provenance_gate "$_gI/ci.yml" "$_gI/evidence.env" birth

# G23/G24 — fail-closed on a malformed call.
_g "G23: an unknown mode => HOLD" \
  1 "mode" git_data_rung2_evidence_provenance_gate "$_gA/ci.yml" "$_gA/evidence.env" sideways
_g "G24: range mode with NO range => HOLD" \
  1 "range" git_data_rung2_evidence_provenance_gate "$_gA/ci.yml" "$_gA/evidence.env" range

# gJ — G25 (MUST-PASS): an ordinary payload PR that leaves the evidence alone. ARM 2 is the
# advisory step on every infra PR; it must not red the PRs whose staleness the hash check
# already reports.
_gJ="$TMP/gJ"; _g_repo "$_gJ" with-evidence; _gJ_c2="$(_g_head "$_gJ")"
printf '\n# a later edit to a shipped payload\n' >> "$_gJ/git-data-gc.sh"
_g_commit "$_gJ" "c3: payload edit, evidence untouched"; _gJ_c3="$(_g_head "$_gJ")"
_g "G25: MUST-PASS — a payload edit that leaves the evidence untouched => ARM 2 passes" \
  0 "untouched" git_data_rung2_evidence_provenance_gate "$_gJ/ci.yml" "$_gJ/evidence.env" range "$_gJ_c2" "$_gJ_c3"

# G26 — a template whose bound files live OUTSIDE the evidence's repository: paths cannot be
# compared, so nothing was measured, so HOLD.
_g "G26: bound files outside the evidence's repository => a NAMED HOLD (nothing measured)" \
  1 "outside" git_data_rung2_evidence_provenance_gate "$_gA/ci.yml" "$_gB/evidence.env" birth

# G27–G29 (#8052 review, test-design seat): three shapes the gate handles that no row pinned —
# each survived a lib mutation with the suite green (G27: `--diff-filter=AM` -> `=M`; G28:
# skipping `*.tf` in the intersection; G29: dropping `-m` from `diff-tree`, under which a merge
# that is the last evidence-touching commit diffs as NOTHING and passes).
# G27 — range mode, evidence CREATED (not modified) in the same commit as a payload edit.
_gX="$TMP/gX"; _g_repo "$_gX"; _gX_c1="$(_g_head "$_gX")"
printf '\n# a later edit to a shipped payload\n' >> "$_gX/git-data-gc.sh"
_r2_evidence_write "$_gX/evidence.env" PASS "$_G_URL" "$(_r2_hash "$_gX")"
_g_commit "$_gX" "c2: evidence CREATED + payload edit"; _gX_c2="$(_g_head "$_gX")"
_g "G27: evidence ADDED alongside a payload edit => ARM 2 HOLD (the A in --diff-filter=AM)" \
  1 "git-data-gc.sh" git_data_rung2_evidence_provenance_gate "$_gX/ci.yml" "$_gX/evidence.env" range "$_gX_c1" "$_gX_c2"
# G28 — birth mode, the co-edited bound file is one of the three MODULE .tf roster members.
_gY="$TMP/gY"; _g_repo "$_gY" with-evidence
printf '\n# a later edit to the module\n' >> "$_gY/modules/git-data-userdata/main.tf"
_r2_evidence_write "$_gY/evidence.env" PASS "$_G_URL" "$(_r2_hash "$_gY")"
_g_commit "$_gY" "c3: main.tf edit + hash edit"
_g "G28: module main.tf edit + evidence edit in one commit => ARM 1 HOLD naming main.tf" \
  1 "main.tf" git_data_rung2_evidence_provenance_gate "$_gY/ci.yml" "$_gY/evidence.env" birth
# G29 — birth mode, a MERGE commit is the last evidence-touching commit: the evidence branch
# is merged onto a main that carries a payload edit, and the merge itself re-touches the
# evidence (a conflict-resolution-style edit). `diff-tree -m` diffs against EACH parent.
_gZ="$TMP/gZ"; _g_repo "$_gZ"
git -C "$_gZ" checkout -q -b ev
_r2_evidence_write "$_gZ/evidence.env" PASS "$_G_URL" "$(_r2_hash "$_gZ")"
_g_commit "$_gZ" "ev: evidence alone"
git -C "$_gZ" checkout -q main
printf '\n# main-side payload edit\n' >> "$_gZ/git-data-gc.sh"
_g_commit "$_gZ" "main: payload edit"
git -C "$_gZ" merge -q --no-ff --no-edit ev >/dev/null 2>&1
_r2_evidence_write "$_gZ/evidence.env" PASS "$_G_URL2" "$(_r2_hash "$_gZ")"
git -C "$_gZ" add -A >/dev/null; git -C "$_gZ" commit -q --amend --no-edit >/dev/null 2>&1
_gZ_last="$(git -C "$_gZ" log -1 --format=%H -- evidence.env)"
_gZ_np="$(git -C "$_gZ" rev-list --parents -n1 "$_gZ_last" | wc -w)"
if [[ "$_gZ_np" -ne 3 ]]; then _a_setup_fail "G29 fixture: the last evidence-touching commit ${_gZ_last} has $((_gZ_np - 1)) parent(s), expected 2 (a merge)"; fi
_g "G29: a MERGE commit touching the evidence, one parent side carrying a payload edit => ARM 1 HOLD (-m is load-bearing)" \
  1 "git-data-gc.sh" git_data_rung2_evidence_provenance_gate "$_gZ/ci.yml" "$_gZ/evidence.env" birth


# ═══════════════════════════════════════════════════════════════════════════════════════
# (#8010) THE LOAD-BEARING ARMS: the resolved run, the head-SHA binding, the Sentry verdict
# ═══════════════════════════════════════════════════════════════════════════════════════
#
# Before this battery the gate checked the SHAPE of an assertion, never that a rehearsal
# passed: a four-line hand-written file naming a nonexistent run released it. Every row below
# names the property it buys, and the mutation rows at the end prove each arm is load-bearing.
#
# PER-FAMILY ROW COUNTS ARE PINNED. The suite-wide floor cannot see a family that silently
# stops running — 13 missing S rows are 13 assertions the floor happily absorbs if any other
# family grew. `_expect_rows` reds at the family's own name instead.
declare -A _FAM=()
_row() {  # <family> <name> <want_rc> <needle> <ci> <ev>
  local fam="$1"; shift
  _FAM[$fam]=$(( ${_FAM[$fam]:-0} + 1 ))
  r2check "$@"
}
_expect_rows() {  # <family> <n>
  local fam="$1" want="$2" got="${_FAM[$1]:-0}"
  if [[ "$got" -eq "$want" ]]; then
    pass "row-count pin: family ${fam} ran ${got} rows"
  else
    fail "row-count pin: family ${fam} ran ${got} rows, expected ${want} — a table was truncated or mis-parsed" "n/a" ""
  fi
}

# _expect_rows SELF-TEST — the probe this helper shipped without, and the measured reason it
# needs one: neutering its condition to `if true` left the suite reporting 217 passed, 0 failed.
#
# A pass()/fail() positive control cannot see this. _expect_rows OWNS a verdict: it compares,
# then calls pass or fail, so a helper that takes the wrong BRANCH still moves both counters,
# still appends to the ledger, and still satisfies the anti-vacuity floor. The four row-count
# pins are themselves the guard that exists BECAUSE the floor cannot see a truncated family —
# so an unbacked _expect_rows silently removes the backstop's backstop.
#
# Reports with printf + exit rather than through pass/fail, because those are the helpers it
# is verifying; and it unwinds every counter AND the ledger so the floor stays exact.
_er_self_test() {
  local _p0=$passes _f0=$fails _l0=${#FAILURES[@]}
  declare -A _FAM_SAVE=()
  local _k
  for _k in "${!_FAM[@]}"; do _FAM_SAVE[$_k]="${_FAM[$_k]}"; done

  _FAM[__selftest]=1
  # Output is suppressed: this drives fail() deliberately, and a FAIL line in the transcript
  # that the unwind then erases from the counters is a transcript that disagrees with itself.
  _expect_rows __selftest 1 >/dev/null 2>&1       # must PASS
  local _p1=$passes _f1=$fails
  _expect_rows __selftest 99 >/dev/null 2>&1      # must FAIL
  local _p2=$passes _f2=$fails _l2=${#FAILURES[@]}

  # Unwind.
  passes=$_p0; fails=$_f0
  while [[ "${#FAILURES[@]}" -gt "$_l0" ]]; do unset "FAILURES[$(( ${#FAILURES[@]} - 1 ))]"; done
  FAILURES=("${FAILURES[@]+"${FAILURES[@]}"}")
  unset '_FAM[__selftest]'
  for _k in "${!_FAM_SAVE[@]}"; do _FAM[$_k]="${_FAM_SAVE[$_k]}"; done

  if [[ "$_p1" -ne $((_p0 + 1)) || "$_f1" -ne "$_f0" ]]; then
    printf '\n  FATAL: _expect_rows did not PASS on a matching count (passes %s -> %s, fails %s -> %s).\n' "$_p0" "$_p1" "$_f0" "$_f1" >&2
    exit 2
  fi
  if [[ "$_f2" -ne $((_f1 + 1)) || "$_l2" -ne $((_l0 + 1)) ]]; then
    printf '\n  FATAL: _expect_rows did not FAIL on a mismatched count (fails %s -> %s, ledger %s -> %s). Every row-count pin in this suite is vacuous.\n' "$_f1" "$_f2" "$_l0" "$_l2" >&2
    exit 2
  fi
}
_er_self_test

# The canonical releasing fixture for this battery: hash-matched, provenance-clean, and now
# also run-resolvable. Every refusal row below is this file with exactly one thing changed.
_S_URL="https://github.com/jikig-ai/soleur/actions/runs/17250000001"

_s_ev() {  # <name> <sentry> [ack] [url] -- write + commit an evidence file alone
  local n="$1" sentry="$2" ack="${3:-}" url="${4:-$_S_URL}"
  _r2_evidence_write "$R2/$n" PASS "$url" "$R2_SHA" none "$sentry" "$ack"
  _r2_commit_alone "$R2/$n"
}

printf '\n(#8010) S — the Sentry cross-check verdict\n'

_s_ev s1.env CLEAN
_row S "S1: CLEAN => RELEASED" 0 "RELEASED" "$R2/ci.yml" "$R2/s1.env"

_s_ev s2.env FATAL
_row S "S2: FATAL is a measured second-channel failure => HOLD, never ack-able" 1 "[SENTRY_VERDICT_FATAL]" "$R2/ci.yml" "$R2/s2.env"

_s_ev s3.env NOT_RUN
_row S "S3: NOT_RUN (the cross-check never ran) => could-not-measure HOLD" 1 "[SENTRY_VERDICT_UNREADABLE]" "$R2/ci.yml" "$R2/s3.env"

_s_ev s4.env BANANA
_row S "S4: an unknown verdict is not a pass => could-not-measure HOLD" 1 "[SENTRY_VERDICT_UNREADABLE]" "$R2/ci.yml" "$R2/s4.env"

_s_ev s5.env ""
_row S "S5: an EMPTY verdict is silence, and silence cannot release" 1 "[SENTRY_VERDICT_UNREADABLE]" "$R2/ci.yml" "$R2/s5.env"

_s_ev s6.env UNAVAILABLE
_row S "S6: UNAVAILABLE with no ack => HOLD (the key that released everything before #8010)" 1 "[SENTRY_UNAVAILABLE_UNACKED]" "$R2/ci.yml" "$R2/s6.env"

_s_ev s7.env UNAVAILABLE "99999999:copied forward from another run"
_row S "S7: an ack naming a DIFFERENT run is an ack copied forward" 1 "[SENTRY_ACK_MISMATCH]" "$R2/ci.yml" "$R2/s7.env"

_s_ev s8.env UNAVAILABLE "17250000001:   "
_row S "S8: an ack with an empty reason acknowledges nothing" 1 "[SENTRY_UNAVAILABLE_UNACKED]" "$R2/ci.yml" "$R2/s8.env"

_s_ev s9.env UNAVAILABLE "17250000001:quiet 90s window; the reopen read on this host answered"
_row S "S9: UNAVAILABLE + a well-formed ack => RELEASED" 0 "RELEASED" "$R2/ci.yml" "$R2/s9.env"

_s_ev s10.env UNAVAILABLE "17250000001:  whitespace after the colon is permitted"
_row S "S10: optional whitespace may follow the colon" 0 "RELEASED" "$R2/ci.yml" "$R2/s10.env"

# The gate's trailing-comment strip (`s/[[:space:]]#.*$//`) truncates anything from ' #'
# onward, so a reason carrying '#' would be silently shortened. Refused by name instead.
_s_ev s11.env UNAVAILABLE "17250000001:see issue #8010 for why"
_row S "S11: a reason containing '#' is refused by name, not silently truncated" 1 "[SENTRY_UNAVAILABLE_UNACKED]" "$R2/ci.yml" "$R2/s11.env"

# An ack beside CLEAN satisfies no property; refusing it would be ceremony.
_s_ev s12.env CLEAN "17250000001:harmless"
_row S "S12: an ack beside CLEAN is IGNORED, not refused" 0 "RELEASED" "$R2/ci.yml" "$R2/s12.env"

# At-most-once on the optional key — it cannot ride the required loop, whose absence-is-a-HOLD
# semantics are wrong here, and whose pattern does not match the _ACK suffix anyway.
_r2_evidence_write "$R2/s13.env" PASS "$_S_URL" "$R2_SHA" none UNAVAILABLE "17250000001:first"
printf 'RUNG2_SENTRY_CROSSCHECK_ACK=17250000001:second\n' >> "$R2/s13.env"
_r2_commit_alone "$R2/s13.env"
_row S "S13: two ack lines => HOLD (at-most-once on the optional key)" 1 "RUNG2_SENTRY_CROSSCHECK_ACK" "$R2/ci.yml" "$R2/s13.env"

# The required key is absent entirely: the existing exactly-once loop owns this, and the
# row exists to pin that RUNG2_SENTRY_CROSSCHECK actually JOINED that loop.
printf 'RUNG2_BOOT_REHEARSAL=PASS\nRUNG2_EVIDENCE_URL=%s\nRUNG2_TEMPLATE_SHA256=%s\nRUNG2_VAR_DIVERGENCE=none\n' \
  "$_S_URL" "$R2_SHA" > "$R2/s14.env"
_r2_commit_alone "$R2/s14.env"
_row S "S14: the verdict key is REQUIRED — absence is a cardinality HOLD" 1 "RUNG2_SENTRY_CROSSCHECK" "$R2/ci.yml" "$R2/s14.env"

_expect_rows S 14

printf '\n(#8010) R — resolving the run behind RUNG2_EVIDENCE_URL\n'

# Each row re-seeds ONE stub key and points a fresh evidence file at its own run id, so a row
# can never be satisfied by a neighbour's leftover state. The ids are local to this battery.
_r_ev() {  # <name> <id>
  _s_ev "$1" CLEAN "" "https://github.com/jikig-ai/soleur/actions/runs/$2"
}

# R1 — nothing answered. The stub has no entry, which is its transport-failure shape; the
# gate must say the instrument failed, not that the run is absent.
_r_ev r1.env 80000001   # deliberately NOT seeded
_row R "R1: no network path to api.github.com => could-not-measure, and no token advice" 1 "[RUN_OFFLINE]" "$R2/ci.yml" "$R2/r1.env"

_stub_run 80000002 "head_sha=$_R2_C1" http=500
_r_ev r2.env 80000002
_row R "R2: a 5xx that survives the retry is an instrument failure, not a verdict" 1 "[RUN_UNRESOLVABLE]" "$R2/ci.yml" "$R2/r2.env"

_stub_run 80000003 "head_sha=$_R2_C1" http=403
printf '{"message":"API rate limit exceeded for 1.2.3.4."}\n' > "$TMP/api/runs/80000003.body"
_r_ev r3.env 80000003
_row R "R3: a rate limit is read from status+body, with no header parsing" 1 "[RUN_RATE_LIMITED]" "$R2/ci.yml" "$R2/r3.env"

_stub_run 80000004 "head_sha=$_R2_C1" http=404
_r_ev r4.env 80000004
_row R "R4: a 404 with no bearer in play is a MEASURED absence" 1 "[RUN_NOT_FOUND]" "$R2/ci.yml" "$R2/r4.env"

_stub_run 80000005 "head_sha=$_R2_C1" http=raw
_r_ev r5.env 80000005
_row R "R5: a non-JSON body is unusable, not empty" 1 "[RUN_UNRESOLVABLE]" "$R2/ci.yml" "$R2/r5.env"

# jq/bash both lose precision on ids this size, so the comparison is a STRING comparison.
_stub_run 80000006 "head_sha=$_R2_C1"
jq '.id = 99999999' "$TMP/api/runs/80000006.body" > "$TMP/api/runs/80000006.body.t" && mv "$TMP/api/runs/80000006.body.t" "$TMP/api/runs/80000006.body"
_r_ev r6.env 80000006
_row R "R6: an id that does not match the URL is an unusable answer" 1 "[RUN_UNRESOLVABLE]" "$R2/ci.yml" "$R2/r6.env"

# The SHAPE regex is unanchored, so `runs/123abc` passes it; a naive ${url##*/} would then
# read the id as `123`. The parser terminates on /?# or end-of-string and validates.
_s_ev r7.env CLEAN "" "https://github.com/jikig-ai/soleur/actions/runs/80000007abc"
_row R "R7: a trailing-garbage id is refused, never silently truncated to a valid one" 1 "[RUN_UNRESOLVABLE]" "$R2/ci.yml" "$R2/r7.env"

_stub_run 80000008 "head_sha=$_R2_C1" "path=.github/workflows/apply-web-platform-infra.yml"
_r_ev r8.env 80000008
_row R "R8: a run of a DIFFERENT workflow proves nothing about a boot" 1 "[RUN_WRONG_WORKFLOW]" "$R2/ci.yml" "$R2/r8.env"

# A future schedule/push trigger on the rehearsal workflow would produce identity-passing
# runs that boot nothing.
_stub_run 80000009 "head_sha=$_R2_C1" event=push
_r_ev r9.env 80000009
_row R "R9: only a workflow_dispatch is a rehearsal" 1 "[RUN_WRONG_EVENT]" "$R2/ci.yml" "$R2/r9.env"

_stub_run 80000010 "head_sha=$_R2_C1" head_branch=feat-something
_r_ev r10.env 80000010
_row R "R10: a run dispatched off a branch is not the main-branch rehearsal the route requires" 1 "[RUN_NOT_MAIN]" "$R2/ci.yml" "$R2/r10.env"

_stub_run 80000011 "head_sha=$_R2_C1" status=in_progress conclusion=null
_r_ev r11.env 80000011
_row R "R11: an in-flight run is WAIT-and-re-run, not re-dispatch" 1 "[RUN_NOT_COMPLETED]" "$R2/ci.yml" "$R2/r11.env"

_stub_run 80000012 "head_sha=$_R2_C1" conclusion=failure
_r_ev r12.env 80000012
_row R "R12: a failed run releases nothing (the teardown-after-capture case is named)" 1 "[RUN_NOT_SUCCESS]" "$R2/ci.yml" "$R2/r12.env"

_stub_run 80000013 head_sha=not-a-sha
_r_ev r13.env 80000013
_row R "R13: a malformed head_sha is an unusable answer" 1 "[RUN_UNRESOLVABLE]" "$R2/ci.yml" "$R2/r13.env"

# The operative CI path today: no call site grants `actions: read`, so a rejected bearer must
# fall through to the anonymous read the data is public for.
_stub_run 80000014 "head_sha=$_R2_C1" http=401once
_r_ev r14.env 80000014
# SOLEUR_RUNG2_STUB_BEARER declares "a bearer was in play" — the stub cannot observe a
# header, and without a bearer there is no rejected credential to fall back FROM, so the
# arm would pass for the wrong reason (a bare 401 with no token is RUN_UNRESOLVABLE).
_r14_out="$(SOLEUR_RUNG2_STUB_BEARER=1 git_data_rung2_rehearsal_gate "$R2/ci.yml" "$R2/r14.env" 2>&1)"; _r14_rc=$?
_FAM[R]=$(( ${_FAM[R]:-0} + 1 ))
if [[ "$_r14_rc" -eq 0 && "$_r14_out" == *"RELEASED"* ]]; then
  pass "R14: a rejected bearer retries ONCE anonymously — the operative CI path"
else
  fail "R14: a rejected bearer must retry once anonymously and release" "$_r14_rc" "$_r14_out"
fi
# R14-control: the SAME one-shot 401 with NO bearer in play must NOT release — otherwise R14
# would pass against an implementation that simply ignores a 401.
_stub_run 80000015 "head_sha=$_R2_C1" http=401once
_r_ev r15.env 80000015
# THE NO-BEARER CONDITION IS ESTABLISHED HERE, NOT ASSUMED — and the difference is the whole
# arm. The gate takes its bearer from GH_TOKEN then GITHUB_TOKEN. This row was written on a
# workstation where neither is set, so "no bearer" was true by accident of the environment; in
# CI, GITHUB_TOKEN IS exported, the gate therefore HAD a credential to drop, the 401once was
# retried anonymously, and the row RELEASED. Measured on PR #8388: 236/0 locally, 235/1 in CI,
# and this was the one. An arm whose premise is ambient is not a control — it is a coin flip
# that happens to land the same way on the machine where it was written.
_r15_saved_gh="${GH_TOKEN:-}"; _r15_saved_ght="${GITHUB_TOKEN:-}"
unset GH_TOKEN GITHUB_TOKEN
if [[ -n "${GH_TOKEN:-}${GITHUB_TOKEN:-}" ]]; then
  fail "R14-control: could not clear GH_TOKEN/GITHUB_TOKEN, so the no-bearer premise does not hold" "n/a" ""
fi
_row R "R14-control: a 401 with no bearer to drop is could-not-measure, not a free pass" 1 "[RUN_UNRESOLVABLE]" "$R2/ci.yml" "$R2/r15.env"
[[ -n "$_r15_saved_gh" ]] && export GH_TOKEN="$_r15_saved_gh"
[[ -n "$_r15_saved_ght" ]] && export GITHUB_TOKEN="$_r15_saved_ght"
unset _r15_saved_gh _r15_saved_ght

# R16 — THE 5xx RETRY'S FAR SIDE. R2 is always-500, so it yields the same refusal whether the
# retry exists or not — measured, deleting the retry arm survived the whole battery. The
# `.once` machinery already existed for the anonymous retry and was never applied here.
_stub_run 80000016 "head_sha=$_R2_C1" http=500once
_r_ev r16.env 80000016
_row R "R16: a transient 5xx is retried, and the second attempt releases" 0 "RELEASED" "$R2/ci.yml" "$R2/r16.env"

_expect_rows R 16

printf '\n(#8010) A — the capture discriminator (an evidence artifact exists)\n'

_stub_run 80000101 "head_sha=$_R2_C1" artifacts=none
_s_ev a1.env CLEAN "" "https://github.com/jikig-ai/soleur/actions/runs/80000101"
_row A "A1: a dry_run/teardown_only dispatch uploads nothing => HOLD" 1 "[RUN_NO_EVIDENCE_ARTIFACT]" "$R2/ci.yml" "$R2/a1.env"

# Name matching is EXACT: the capture-log artifact is what a NON-PASS run uploads.
_stub_run 80000102 "head_sha=$_R2_C1" artifacts=log
_s_ev a2.env CLEAN "" "https://github.com/jikig-ai/soleur/actions/runs/80000102"
_row A "A2: git-data-rung2-capture-log is the FAILURE artifact and must not satisfy the check" 1 "[RUN_NO_EVIDENCE_ARTIFACT]" "$R2/ci.yml" "$R2/a2.env"

# Artifact-record retention past 90 days is undocumented and measured once, so an old run
# with no record must not masquerade as a measured refusal.
_stub_run 80000103 "head_sha=$_R2_C1" artifacts=none "created_at=$(date -u -d '200 days ago' +%Y-%m-%dT%H:%M:%SZ)"
_s_ev a3.env CLEAN "" "https://github.com/jikig-ai/soleur/actions/runs/80000103"
_row A "A3: past the retention window an empty list is could-not-measure, not a refusal" 1 "[RUN_ARTIFACT_RECORD_UNREADABLE]" "$R2/ci.yml" "$R2/a3.env"

_stub_run 80000104 "head_sha=$_R2_C1" artifacts=missing
_s_ev a4.env CLEAN "" "https://github.com/jikig-ai/soleur/actions/runs/80000104"
_row A "A4: an unreadable artifacts endpoint is could-not-measure" 1 "[RUN_ARTIFACT_RECORD_UNREADABLE]" "$R2/ci.yml" "$R2/a4.env"

# Measured on run 27579149955 (~110 days): the RECORD survives expiry even though the bytes
# do not, which is precisely why the record — not the download — is the discriminator.
_stub_run 80000105 "head_sha=$_R2_C1"
jq '.artifacts[0].expired = true' "$TMP/api/runs/80000105/artifacts.body" > "$TMP/api/runs/80000105/artifacts.t" \
  && mv "$TMP/api/runs/80000105/artifacts.t" "$TMP/api/runs/80000105/artifacts.body"
_s_ev a5.env CLEAN "" "https://github.com/jikig-ai/soleur/actions/runs/80000105"
_row A "A5: an EXPIRED record still proves the capture happened => RELEASED" 0 "RELEASED" "$R2/ci.yml" "$R2/a5.env"

# A6 — THE FAR SIDE. Every other A fixture has an artifact population of 0 or 1, so
# `1-of-1` cannot be told apart from `all-of-1` OR from `index-0-of-1` — measured, reading
# `.artifacts[0]` instead of the set survived the entire battery. This is the real
# multi-attempt shape (attempt 1 failed and uploaded the capture-LOG, attempt 2 passed), and
# an ordering-dependent read would HOLD a genuinely passing rehearsal: the too-aggressive
# direction no fixture covered.
_stub_run 80000106 "head_sha=$_R2_C1" artifacts=both
_s_ev a6.env CLEAN "" "https://github.com/jikig-ai/soleur/actions/runs/80000106"
_row A "A6: the evidence artifact is found even when a failed attempt's log is listed FIRST" 0 "RELEASED" "$R2/ci.yml" "$R2/a6.env"

# A7/A8 — THE WINDOW'S NEAR BOUNDARY. The only fixtures were 1 day and 200 days, so any
# literal in roughly 2..199 satisfied them. `12 hours` rather than `1 day` for the in-window
# side: `date -d '1 day ago'` sits exactly on the 86400s boundary and flips on elapsed seconds.
_stub_run 80000107 "head_sha=$_R2_C1" artifacts=none "created_at=$(date -u -d '89 days ago' +%Y-%m-%dT%H:%M:%SZ)"
_s_ev a7.env CLEAN "" "https://github.com/jikig-ai/soleur/actions/runs/80000107"
_row A "A7: INSIDE the retention window, an empty list is a measured refusal" 1 "[RUN_NO_EVIDENCE_ARTIFACT]" "$R2/ci.yml" "$R2/a7.env"

_stub_run 80000108 "head_sha=$_R2_C1" artifacts=none "created_at=$(date -u -d '91 days ago' +%Y-%m-%dT%H:%M:%SZ)"
_s_ev a8.env CLEAN "" "https://github.com/jikig-ai/soleur/actions/runs/80000108"
_row A "A8: one day PAST the window, the same empty list is could-not-measure" 1 "[RUN_ARTIFACT_RECORD_UNREADABLE]" "$R2/ci.yml" "$R2/a8.env"

_expect_rows A 8

printf '\n(#8010) H — binding the run to the bytes, via its head_sha\n'

# WHY THIS ARM EXISTS AT ALL. Every R row above proves the run is REAL. None of them proves
# the run booted THESE bytes: RUNG2_TEMPLATE_SHA256 is a pure function of tracked files, so a
# payload author who re-derives it locally produces evidence that passes the live-hash check
# while naming a run that rehearsed something else. The head_sha binding is what closes that:
# the gate re-hashes the tree AT THE COMMIT THE RUN RAN and requires it to equal the live hash.
#
# HX is a repository with three shapes in its history: c1 carries THREE payloads (below the
# roster floor), c2 carries a DIFFERENT template, c3 is the canonical current tree.
_HX="$TMP/hx"
assert_fixture_dir "$_HX"
mkdir -p "$_HX"
_r2_write_module "$_HX" git-data-bootstrap.sh git-data-provision.sh git-data-gc.sh
for _p in git-data-bootstrap.sh git-data-provision.sh git-data-gc.sh; do
  printf '#!/usr/bin/env bash\n# %s\ntrue\n' "$_p" > "$_HX/$_p"
done
cp "$TMP/mixed.yml" "$_HX/ci.yml"
git -C "$_HX" init -q -b main || _a_setup_fail "git init failed in $_HX"
_g_commit "$_HX" "c1: a three-payload module — below the roster floor"
_HX_C1="$(git -C "$_HX" rev-parse HEAD)"
_r2_write_module "$_HX" "${_r2_payloads[@]}"
_a_sibling_var "$_HX/modules/git-data-userdata/variables.tf"
_a_sibling_out "$_HX/modules/git-data-userdata/outputs.tf"
for _p in "${_r2_payloads[@]}"; do printf '#!/usr/bin/env bash\n# %s\ntrue\n' "$_p" > "$_HX/$_p"; done
printf '\n# a divergent template line\n' >> "$_HX/ci.yml"
_g_commit "$_HX" "c2: the canonical roster, but a DIFFERENT template"
_HX_C2="$(git -C "$_HX" rev-parse HEAD)"
# c3 restores the canonical template, so the WORKING TREE hash (what the gate computes live)
# differs from c2's.
cp "$TMP/mixed.yml" "$_HX/ci.yml"
_g_commit "$_HX" "c3: the canonical tree"
_HX_SHA="$(_r2_hash "$_HX")"

_hx_ev() {  # <name> <id>
  _r2_evidence_write "$_HX/$1" PASS "https://github.com/jikig-ai/soleur/actions/runs/$2" "$_HX_SHA" none CLEAN
  _r2_commit_alone "$_HX/$1"
}

# H1 — the named commit is not in this clone. The gate must NOT fetch: a gate that mutates
# the repository it judges is a different thing, and an unbounded fetch is an offline stall.
_stub_run 80000201 head_sha=0000000000000000000000000000000000000000
_hx_ev h1.env 80000201
_row H "H1: an unreachable head_sha names the fetch, and the gate does not fetch for you" 1 "[RUN_SHA_UNREACHABLE]" "$_HX/ci.yml" "$_HX/h1.env"

# H2 — THE FORGERY THIS WHOLE ARM EXISTS FOR: hash-valid, provenance-clean evidence naming a
# real, successful, main-branch rehearsal of DIFFERENT bytes.
_stub_run 80000202 "head_sha=$_HX_C2"
_hx_ev h2.env 80000202
_row H "H2: a real run that rehearsed different bytes => HOLD, naming both hashes" 1 "[RUN_HASH_MISMATCH]" "$_HX/ci.yml" "$_HX/h2.env"

# H3 — the repo-ROOT shape (`git archive <sha>:`). The repo-relative directory is the empty
# string here, and `git archive <sha> -- ""` is fatal, so the tree-ish form is load-bearing.
_stub_run 80000203 "head_sha=$(git -C "$_HX" rev-parse HEAD)"
_hx_ev h3.env 80000203
_row H "H3: a cloud-init at the repository ROOT re-hashes via the <sha>: tree-ish form" 0 "RELEASED" "$_HX/ci.yml" "$_HX/h3.env"

# H4 — the SUBDIRECTORY shape (`git archive <sha>:<dir>`). Production is this shape
# (apps/web-platform/infra/), and it is the one a root-only fixture cannot exercise.
_HS="$TMP/hsub"
assert_fixture_dir "$_HS"
mkdir -p "$_HS/infra"
cp "$TMP/mixed.yml" "$_HS/infra/ci.yml"
_r2_write_module "$_HS/infra" "${_r2_payloads[@]}"
_a_sibling_var "$_HS/infra/modules/git-data-userdata/variables.tf"
_a_sibling_out "$_HS/infra/modules/git-data-userdata/outputs.tf"
for _p in "${_r2_payloads[@]}"; do printf '#!/usr/bin/env bash\n# %s\ntrue\n' "$_p" > "$_HS/infra/$_p"; done
printf 'placeholder\n' > "$_HS/README.md"
git -C "$_HS" init -q -b main || _a_setup_fail "git init failed in $_HS"
_g_commit "$_HS" "c1: a cloud-init in a SUBDIRECTORY"
_HS_C1="$(git -C "$_HS" rev-parse HEAD)"
_r2_evidence_write "$_HS/infra/evidence.env" PASS "https://github.com/jikig-ai/soleur/actions/runs/80000204" "$(_r2_hash "$_HS/infra")" none CLEAN
_r2_commit_alone "$_HS/infra/evidence.env"
_stub_run 80000204 "head_sha=$_HS_C1"
_row H "H4: a cloud-init in a SUBDIRECTORY re-hashes via the <sha>:<dir> tree-ish form" 0 "RELEASED" "$_HS/infra/ci.yml" "$_HS/infra/evidence.env"

# H5 — the archived tree cannot be hashed at all (a historical module below the roster floor).
# That is could-not-measure, and it must carry the ABORT's own first line rather than
# masquerading as a mismatch.
_stub_run 80000205 "head_sha=$_HX_C1"
_hx_ev h5.env 80000205
_row H "H5: a sub-floor historical tree is UNCOMPUTABLE, not a mismatch" 1 "[RUN_HASH_UNCOMPUTABLE]" "$_HX/ci.yml" "$_HX/h5.env"

# H6 — ORDER PIN. A stale local hash and a run-binding failure are different defects with
# different remedies; the payload author's ordinary case is STALE EVIDENCE, and it must still
# be the thing that speaks first.
_row H "H6: the live-hash check still reports BEFORE any run resolution" 1 "STALE EVIDENCE" "$R2/ci.yml" "$R2/stale.env"

_expect_rows H 6

printf '\n(#8010) F — Guard 5: the monotonic run floor (the downgrade shape)\n'

# WHY THIS FAMILY EXISTS. Steps D and E are hash-EQUALITY checks. Revert the payload tree to an
# older revision, cite the genuine older run that rehearsed exactly those bytes, and every
# asserted fact is TRUE while the host ends up running older code. The exploit payload is
# already in this repository's history (the pre-#8312 evidence at f64b0ebc2^), so this is a
# two-command attack, not a hypothetical.
#
# FX is a repo with a COMMITTED evidence history, which the R2/HX fixtures deliberately lack:
# every other fixture writes a fresh filename, so the floor is empty and this arm never fires.
_FX="$TMP/fx"
assert_fixture_dir "$_FX"
mkdir -p "$_FX"
cp "$TMP/mixed.yml" "$_FX/ci.yml"
_r2_write_module "$_FX" "${_r2_payloads[@]}"
_a_sibling_var "$_FX/modules/git-data-userdata/variables.tf"
_a_sibling_out "$_FX/modules/git-data-userdata/outputs.tf"
for _p in "${_r2_payloads[@]}"; do printf '#!/usr/bin/env bash\n# %s\ntrue\n' "$_p" > "$_FX/$_p"; done
git -C "$_FX" init -q -b main || _a_setup_fail "git init failed in $_FX"
_g_commit "$_FX" "c1: template, module, payloads"
_FX_C1="$(git -C "$_FX" rev-parse HEAD)"
_FX_SHA="$(_r2_hash "$_FX")"

# c2: the HIGH-water evidence (run 80000900). This is the version a downgrade replaces.
_r2_evidence_write "$_FX/evidence.env" PASS "https://github.com/jikig-ai/soleur/actions/runs/80000900" "$_FX_SHA" none CLEAN
_r2_commit_alone "$_FX/evidence.env"
for _id in 80000900 80000800; do _stub_run "$_id" "head_sha=$_FX_C1"; done

_row F "F1: evidence at the current high-water mark releases (the floor costs nothing when nothing moves)" 0 "RELEASED" "$_FX/ci.yml" "$_FX/evidence.env"

# c3: the DOWNGRADE — an OLDER run id replacing the committed one, every other fact true.
_r2_evidence_write "$_FX/evidence.env" PASS "https://github.com/jikig-ai/soleur/actions/runs/80000800" "$_FX_SHA" none CLEAN
_r2_commit_alone "$_FX/evidence.env"
_row F "F2: an OLDER run id than the version it replaces => HOLD, with every other fact true" 1 "[RUN_ID_REGRESSED]" "$_FX/ci.yml" "$_FX/evidence.env"

# The deliberate-replay escape hatch, with the same grammar as the Sentry ack.
_r2_evidence_write "$_FX/evidence.env" PASS "https://github.com/jikig-ai/soleur/actions/runs/80000800" "$_FX_SHA" none CLEAN
printf 'RUNG2_EVIDENCE_DOWNGRADE_ACK=80000800:reinstating the pre-regression payload while the fix is prepared\n' >> "$_FX/evidence.env"
_r2_commit_alone "$_FX/evidence.env"
_row F "F3: a well-formed, run-bound downgrade ack releases the deliberate replay" 0 "RELEASED" "$_FX/ci.yml" "$_FX/evidence.env"

# F3b — THE DOWNGRADE ACK OBEYS THE '#' RULE ITS OWN HOLD MESSAGE STATES. The helper reads the
# COMMENT-STRIPPED body, so `...:see #8399 for why` arrives as the reason "see" -- non-empty,
# therefore ACCEPTED, and the deliberate-replay hatch would authorise a replay on text nobody
# wrote. The Sentry ack refuses this by name and is pinned by M3c; this arm had the rule in its
# message and not in its code until #8010's ship-time consult measured it. Same class as the P1
# the panel caught: a documented property that was not there.
#
# THE MARK IS RE-ESTABLISHED FIRST, for the reason the F4/F5 note below states in full: F3's ack
# was ACCEPTED, so 80000800 legitimately became the floor, and without this commit F3b would
# compare 80000800 against 80000800, never reach the downgrade branch at all, and RELEASE --
# measured exactly that on the first draft of this arm.
_r2_evidence_write "$_FX/evidence.env" PASS "https://github.com/jikig-ai/soleur/actions/runs/80000900" "$_FX_SHA" none CLEAN
_r2_commit_alone "$_FX/evidence.env"
_r2_evidence_write "$_FX/evidence.env" PASS "https://github.com/jikig-ai/soleur/actions/runs/80000800" "$_FX_SHA" none CLEAN
printf 'RUNG2_EVIDENCE_DOWNGRADE_ACK=80000800:see #8399 for why the older bytes go back\n' >> "$_FX/evidence.env"
_r2_commit_alone "$_FX/evidence.env"
_row F "F3b: a downgrade ack whose reason contains '#' is REFUSED, not silently truncated" 1 "[RUN_ID_REGRESSED]" "$_FX/ci.yml" "$_FX/evidence.env"

# RE-ESTABLISH THE HIGH-WATER MARK BEFORE F4/F5, and the reason is a property worth stating:
# F3's ack was ACCEPTED, so its downgrade legitimately became the new floor. That is the
# ratchet working — an acknowledged replay is the attested state from then on — and it means
# F4/F5 would otherwise compare 80000800 against 80000800 and detect nothing. Measured: both
# rows RELEASED before this commit was added, testing the ack grammar against a fixture that
# could never have regressed in the first place.
_r2_evidence_write "$_FX/evidence.env" PASS "https://github.com/jikig-ai/soleur/actions/runs/80000900" "$_FX_SHA" none CLEAN
_r2_commit_alone "$_FX/evidence.env"

# An ack keyed to a DIFFERENT run is an ack copied forward — the property the run binding buys.
_r2_evidence_write "$_FX/evidence.env" PASS "https://github.com/jikig-ai/soleur/actions/runs/80000800" "$_FX_SHA" none CLEAN
printf 'RUNG2_EVIDENCE_DOWNGRADE_ACK=80000900:copied forward from the previous file\n' >> "$_FX/evidence.env"
_r2_commit_alone "$_FX/evidence.env"
_row F "F4: a downgrade ack naming a different run does not release" 1 "[RUN_ID_REGRESSED]" "$_FX/ci.yml" "$_FX/evidence.env"

_r2_evidence_write "$_FX/evidence.env" PASS "https://github.com/jikig-ai/soleur/actions/runs/80000900" "$_FX_SHA" none CLEAN
_r2_commit_alone "$_FX/evidence.env"
_r2_evidence_write "$_FX/evidence.env" PASS "https://github.com/jikig-ai/soleur/actions/runs/80000800" "$_FX_SHA" none CLEAN
printf 'RUNG2_EVIDENCE_DOWNGRADE_ACK=80000800:   \n' >> "$_FX/evidence.env"
_r2_commit_alone "$_FX/evidence.env"
_row F "F5: a downgrade ack with an empty reason acknowledges nothing" 1 "[RUN_ID_REGRESSED]" "$_FX/ci.yml" "$_FX/evidence.env"

# THE DELETION CASE, and it is the one that makes the floor real rather than decorative.
# Guard 4 states that a voided attestation is DELETED, never rewritten — so the last commit
# touching this path is routinely the one that REMOVED it. Without the `^:` fallback the floor
# would reset on exactly that commit, and voiding an attestation would itself be the bypass.
_FY="$TMP/fy"
assert_fixture_dir "$_FY"
mkdir -p "$_FY"
cp "$TMP/mixed.yml" "$_FY/ci.yml"
_r2_write_module "$_FY" "${_r2_payloads[@]}"
_a_sibling_var "$_FY/modules/git-data-userdata/variables.tf"
_a_sibling_out "$_FY/modules/git-data-userdata/outputs.tf"
for _p in "${_r2_payloads[@]}"; do printf '#!/usr/bin/env bash\n# %s\ntrue\n' "$_p" > "$_FY/$_p"; done
git -C "$_FY" init -q -b main || _a_setup_fail "git init failed in $_FY"
_g_commit "$_FY" "c1: template, module, payloads"
_FY_C1="$(git -C "$_FY" rev-parse HEAD)"
_FY_SHA="$(_r2_hash "$_FY")"
_r2_evidence_write "$_FY/evidence.env" PASS "https://github.com/jikig-ai/soleur/actions/runs/80000900" "$_FY_SHA" none CLEAN
_r2_commit_alone "$_FY/evidence.env"
# Void it the permitted way: delete, in its own commit.
git -C "$_FY" rm -q -- evidence.env
git -C "$_FY" -c user.name=t -c user.email=t@t commit -q -m "void the attestation by deleting it" >/dev/null 2>&1
# Now re-add an OLDER run. The floor must still come from the pre-deletion version.
_r2_evidence_write "$_FY/evidence.env" PASS "https://github.com/jikig-ai/soleur/actions/runs/80000800" "$_FY_SHA" none CLEAN
_r2_commit_alone "$_FY/evidence.env"
for _id in 80000900 80000800; do _stub_run "$_id" "head_sha=$(git -C "$_FY" rev-parse HEAD)"; done
_row F "F6: DELETING the evidence does not reset the floor (the ^: fallback; otherwise voiding is the bypass)" 1 "[RUN_ID_REGRESSED]" "$_FY/ci.yml" "$_FY/evidence.env"

# A first-ever evidence file has no prior version, so there is no floor and that is not a failure.
_stub_run 80000700 "head_sha=$_HX_C2"
_hx_ev f7.env 80000700
_row F "F7: a first-ever evidence file has no floor to regress against" 1 "[RUN_HASH_MISMATCH]" "$_HX/ci.yml" "$_HX/f7.env"

_expect_rows F 8

printf '\n(#8010) T/E — tooling, the seam, and the gate'"'"'s own CI annotation\n'

# T1 — TOOLING BEFORE ANYTHING THAT CAN STALL. A missing jq must be reported as a toolchain
# gap, not discovered after a network timeout. The farm drops ONLY jq; everything else the
# gate needs stays reachable, so a pass here cannot come from a broken PATH in general.
_T1="$TMP/t1bin"
mkdir -p "$_T1"
for _b in bash sed grep awk sort tr cut git curl tar sha256sum date printf dirname basename cmp mktemp rm cat head wc; do
  _p="$(command -v "$_b" 2>/dev/null)" && ln -sf "$_p" "$_T1/$_b"
done
_t1_out="$(PATH="$_T1" bash -c "source '$GATE'; git_data_rung2_rehearsal_gate '$R2/ci.yml' '$R2/s1.env'" 2>&1)"; _t1_rc=$?
if [[ "$_t1_rc" -ne 0 && "$_t1_out" == *"[TOOLING_MISSING]"* && "$_t1_out" == *"jq"* ]]; then
  pass "T1: a missing jq is an ABORT naming the binary, raised before any network call"
else
  fail "T1: a missing jq must ABORT [TOOLING_MISSING] naming jq" "$_t1_rc" "$_t1_out"
fi
# T1's POSITIVE CONTROL. Without it T1 passes for any reason the farm breaks the gate — an
# unset PATH entry, a missing sed — and proves nothing about the tooling check.
_t1c_out="$(PATH="$_T1:$PATH" bash -c "source '$GATE'; git_data_rung2_rehearsal_gate '$R2/ci.yml' '$R2/s1.env'" 2>&1)"; _t1c_rc=$?
if [[ "$_t1c_rc" -eq 0 ]]; then
  pass "T1-control: the same farm WITH jq reachable releases — T1 measured the tooling check"
else
  fail "T1-control: the farm itself breaks the gate, so T1 proves nothing" "$_t1c_rc" "$_t1c_out"
fi

# T1-ORDER — the tooling check's POSITION, not just its token. T1 proves a missing binary is
# reported; it says nothing about WHEN, and the position is load-bearing: the live-hash step
# calls git_data_rung2_user_data_sha256, which runs `sha256sum`, and it runs BEFORE Guard 4.
# The plan's FR14 pinned tooling AFTER Guard 4 — at that position the gate would hash the
# template with an UNCHECKED sha256sum, which is P1 #3 (`find` absent from the list) one step
# further along. So drop ONLY sha256sum: if tooling runs first the verdict is
# ABORT [TOOLING_MISSING] naming sha256sum; if it ran late, the hash step speaks first with a
# different token and this arm reds. Nothing else pins this ordering.
_T1O="$TMP/t1obin"
mkdir -p "$_T1O"
for _b in bash sed grep awk sort tr cut git curl tar jq date printf dirname basename cmp mktemp rm cat head wc find; do
  _p="$(command -v "$_b" 2>/dev/null)" && ln -sf "$_p" "$_T1O/$_b"
done
_t1o_out="$(PATH="$_T1O" bash -c "source '$GATE'; git_data_rung2_rehearsal_gate '$R2/ci.yml' '$R2/s1.env'" 2>&1)"; _t1o_rc=$?
if [[ "$_t1o_rc" -ne 0 && "$_t1o_out" == *"[TOOLING_MISSING]"* && "$_t1o_out" == *"sha256sum"* ]]; then
  pass "T1-ORDER: tooling is checked BEFORE the live hash consumes sha256sum"
else
  fail "T1-ORDER: dropping sha256sum must ABORT [TOOLING_MISSING] naming it, proving tooling runs before the hash step" "$_t1o_rc" "$_t1o_out"
fi


# T-SEAM1 — the seam ANNOUNCES ITSELF on every verdict line. infra-validation.yml triggers on
# pull_request, so a PR author controls that step's env: block; without the announcement two
# innocuous env lines would produce a RELEASED line indistinguishable from a real one.
_seam_out="$(git_data_rung2_rehearsal_gate "$R2/ci.yml" "$R2/s1.env" 2>&1)"
if [[ "$_seam_out" == *"SEAM ACTIVE"* ]]; then
  pass "T-SEAM1: an honoured seam is named on the verdict line"
else
  fail "T-SEAM1: a RELEASED line produced through the seam must say so" "0" "$_seam_out"
fi
# And on a HOLD, where a silent seam would be just as misleading.
_seam_hold="$(git_data_rung2_rehearsal_gate "$R2/ci.yml" "$R2/s6.env" 2>&1)"
if [[ "$_seam_hold" == *"SEAM ACTIVE"* ]]; then
  pass "T-SEAM1b: an honoured seam is named on HOLD lines too"
else
  fail "T-SEAM1b: a HOLD produced through the seam must say so" "1" "$_seam_hold"
fi

# T-SEAM2 — THE DOUBLE GATE. The fetch override is honoured only when SOLEUR_TEST_MODE is
# also set; with it unset the gate falls through to the real path, and it must SAY that, so
# the intended fall-through does not read as a flaky test.
_seam2="$(env -u SOLEUR_TEST_MODE bash -c "source '$GATE'; git_data_rung2_rehearsal_gate '$R2/ci.yml' '$R2/s1.env'" 2>&1)"; _seam2_rc=$?
if [[ "$_seam2_rc" -ne 0 && "$_seam2" == *"SOLEUR_TEST_MODE"* ]]; then
  pass "T-SEAM2: the fetch override alone does not arm the seam, and the message says which half is missing"
else
  fail "T-SEAM2: SOLEUR_RUNG2_RUN_FETCH without SOLEUR_TEST_MODE must not be honoured" "$_seam2_rc" "$_seam2"
fi

# E1/E2 — THE GATE'S OWN ANNOTATION. Three CI call sites print "no rung-2 boot evidence for
# the CURRENT cloud-init-git-data.yml" on ANY non-zero rc, that text is pinned by
# terraform-target-parity.test.ts, and two of the three files cannot be edited this cycle —
# so an instrument failure would tell an operator to commit evidence that already exists.
_e1="$(GITHUB_ACTIONS=true git_data_rung2_rehearsal_gate "$R2/ci.yml" "$R2/r1.env" 2>&1)"
_e1n="$(grep -c '^::error::' <<<"$_e1" || true)"
if [[ "$_e1n" -eq 1 ]]; then
  pass "E1: a could-not-measure token emits exactly one ::error:: annotation under GITHUB_ACTIONS"
else
  fail "E1: expected exactly one ::error:: line for a could-not-measure token, got ${_e1n}" "n/a" "$_e1"
fi
# E2 USED TO BE VACUOUS, and the way it failed is the lesson: its fixture refused at step B,
# which has no annotate call site at all, so it could not observe the three generic sites where
# the defect lived. It reported green while every MEASURED token printed "could not MEASURE".
# It now drives a fixture that reaches step C (r4.env → RUN_NOT_FOUND) and asserts the WORDING,
# not merely the count — the two vocabularies must never share a sentence.
_e2="$(GITHUB_ACTIONS=true git_data_rung2_rehearsal_gate "$R2/ci.yml" "$R2/r4.env" 2>&1)"
if [[ "$_e2" == *"REFUSED the rung-2 evidence [RUN_NOT_FOUND]"* && "$_e2" != *"could not MEASURE"* ]]; then
  pass "E2: a MEASURED refusal annotates as REFUSED, never as could-not-measure"
else
  fail "E2: a measured refusal must annotate as REFUSED and must not say 'could not MEASURE'" "n/a" "$_e2"
fi
# E2b — every member of the MEASURED set, not one sample. A single-token row cannot see a
# filter that classifies six of seven correctly, and the set is exported precisely so this
# loop cannot drift from the gate's own definition.
_e2b_bad=""
for _mt in $(bash -c "source '$GATE' && git_data_rung2_token_sets measured"); do
  _e2b_out="$(GITHUB_ACTIONS=true bash -c "source '$GATE'; _git_data_rung2_annotate '$_mt' 'probe'" 2>&1)"
  [[ "$_e2b_out" == *"could not MEASURE"* ]] && _e2b_bad+="${_mt} "
done
if [[ -z "$_e2b_bad" ]]; then
  pass "E2b: NO member of the measured set annotates as could-not-measure"
else
  fail "E2b: measured tokens annotated as could-not-measure — ${_e2b_bad}" "n/a" ""
fi
# E2c — and the converse, so the filter cannot be satisfied by classifying everything as
# REFUSED. A one-directional assertion is the shape that let the original defect through.
_e2c_bad=""
for _ct in $(bash -c "source '$GATE' && git_data_rung2_token_sets cannot"); do
  _e2c_out="$(GITHUB_ACTIONS=true bash -c "source '$GATE'; _git_data_rung2_annotate '$_ct' 'probe'" 2>&1)"
  [[ "$_e2c_out" == *"could not MEASURE"* ]] || _e2c_bad+="${_ct} "
done
if [[ -z "$_e2c_bad" ]]; then
  pass "E2c: EVERY member of the could-not-measure set annotates as could-not-measure"
else
  fail "E2c: could-not-measure tokens not annotated as such — ${_e2c_bad}" "n/a" ""
fi
# E2d — the sets are DISJOINT, and every token that appears LITERALLY bracketed in the gate's
# source is in exactly one of them.
#
# CORRECTED 2026-09-20 (#8412). This comment previously claimed "every bracketed token the gate
# can emit" and called itself "the parity mechanism the probe and the runbooks were missing".
# Both were false, and the second was a capability claim about OTHER files that nothing checked
# (hr-verify-repo-capability-claim-before-assert). The haystack below greps the SOURCE for
# `rehearsal_gate: (HOLD|ABORT) [TOKEN]`, so it sees 10 of 21: the 11 tokens reaching the verdict
# line through the generic `HOLD [${_tok}]` sites are invisible to it — and those are precisely
# the sites P1 #2 lived at. What E2d does buy is real but narrower: the literal emits cannot
# drift out of the declared sets.
#
# The CROSS-COPY parity arm is in scripts/followthroughs/git-data-reboot-evidence-landed-8210.test.sh,
# which holds its own expectation and compares it to the gate's declaration, so moving a token
# between the two sets reds there. Neither catches a token emitted through a generic site and
# never declared at all; that residual is tracked in #8397.
_e2d_bad=""
while IFS= read -r _tok_lit; do
  [[ -n "$_tok_lit" ]] || continue
  _n_cannot=0; _n_meas=0
  for _x in $(bash -c "source '$GATE' && git_data_rung2_token_sets cannot"); do [[ "$_x" == "$_tok_lit" ]] && _n_cannot=1; done
  for _x in $(bash -c "source '$GATE' && git_data_rung2_token_sets measured"); do [[ "$_x" == "$_tok_lit" ]] && _n_meas=1; done
  [[ $((_n_cannot + _n_meas)) -eq 1 ]] || _e2d_bad+="${_tok_lit}(${_n_cannot}${_n_meas}) "
done < <(grep -oE 'rehearsal_gate: (HOLD|ABORT) \[[A-Z0-9_]+\]' "$GATE" | grep -oE '\[[A-Z0-9_]+\]' | tr -d '[]' | sort -u)
if [[ -z "$_e2d_bad" ]]; then
  pass "E2d: every bracketed token the gate emits is classified in exactly one set"
else
  fail "E2d: tokens classified in neither or both sets — ${_e2d_bad}" "n/a" ""
fi

# N1 — THE FLAG SET, asserted by source-grep. Under the seam the real fetch never runs, so
# this is the ONLY mechanism that can assert what curl is invoked with.
# N1 ANCHORS ON THE INVOCATION, NOT ON THE FILE. The previous form grepped the whole gate for
# '--disable' and '--noproxy'; both strings also appear in the COMMENT directly above the call
# explaining why they are there, so the arm was satisfied by its own documentation. Measured by
# three reviewers: rewriting the call to `curl -k -sS …` — dropping both flags and turning TLS
# verification OFF — left this arm passing. That is cq-assert-anchor-not-bare-token, in the one
# arm whose own comment calls it "the ONLY mechanism that can assert what curl is invoked with".
#
# The haystack is now the invocation's own lines, comment-stripped: everything from the `curl`
# token to the line carrying the URL.
_n1_call="$(awk '/_resp="\$\(curl /,/GIT_DATA_RUNG2_API_BASE/' "$GATE" | sed 's/^[[:space:]]*#.*$//')"
_n1_fail=""
[[ -n "$_n1_call" ]] || _n1_fail+="EXTRACTION-EMPTY "
for _need in '--disable' "--noproxy '*'" '--max-time' "${GIT_DATA_RUNG2_API_BASE_EXPECT:-GIT_DATA_RUNG2_API_BASE}"; do
  grep -qF -- "$_need" <<<"$_n1_call" || _n1_fail+="missing:${_need} "
done
# The forbid set covers SYNONYMS, not just the spelling that was on my mind: `-k` is
# `--insecure`, and `--proxy`/`--proxy-insecure` re-open what `--noproxy '*'` closed.
for _forbid in '--insecure' ' -k ' '--proxy' '-D -' '-v '; do
  grep -qF -- "$_forbid" <<<"$_n1_call" && _n1_fail+="present:${_forbid} "
done
if [[ -z "$_n1_fail" ]]; then
  pass "N1: the curl INVOCATION carries --disable, --noproxy '*' and a timeout, and no TLS-weakening, proxy or header-dump flag"
else
  fail "N1: the curl invocation drifted — ${_n1_fail}" "n/a" "$_n1_call"
fi
# N1b — the API base is a pinned https constant, not an override. Measured by three seats: as
# `${GIT_DATA_RUNG2_API_BASE:-…}` a single env var redirected the gate's only network call to
# an attacker host, which received the BEARER in cleartext and supplied step C's entire verdict
# while SEAM ACTIVE stayed silent.
# COMMENT-STRIPPED HAYSTACK. The first version of this arm grepped the whole file for
# `GIT_DATA_RUNG2_API_BASE:-` to prove the override is gone — and the comment above the
# constant QUOTES that spelling to explain what was removed, so the arm failed on its own
# documentation. Same collision as N1's, in the opposite direction (a false FAIL rather than a
# false PASS), which is why both haystacks are stripped rather than narrowed.
_n1b_code="$(sed 's/^[[:space:]]*#.*$//' "$GATE")"
if grep -qE '^readonly GIT_DATA_RUNG2_API_BASE="https://api\.github\.com/' <<<"$_n1b_code" \
   && ! grep -qE 'GIT_DATA_RUNG2_API_BASE:-' <<<"$_n1b_code"; then
  pass "N1b: the API base is a readonly https constant with no env override"
else
  fail "N1b: the API base is overridable — one env var redirects the bearer and forges the verdict" "n/a" ""
fi
# N1c — the sanitizer is load-bearing, and nothing pinned it: replacing its body with the
# identity function left the suite fully green (measured). Drive it directly.
_n1c="$(bash -c "source '$GATE'; _git_data_rung2_safe 'a%b' 200")"
_n1c2="$(bash -c "source '$GATE'; _git_data_rung2_safe \"\$(printf 'x\ny')\" 200")"
if [[ "$_n1c" == 'a%25b' && "$_n1c2" == 'xy' ]]; then
  pass "N1c: the sanitizer escapes % and strips control characters (identity body would red this)"
else
  fail "N1c: the sanitizer is not escaping/stripping — got '${_n1c}' and '${_n1c2}'" "n/a" ""
fi

# N2 — A CALLER RUNNING set -x MUST NOT PRINT THE BEARER. The library inherits the caller's
# shell options, so the fetch saves and clears xtrace on entry and restores it before every
# return.
_n2="$(GH_TOKEN=ghp_FAKE_TOKEN_FOR_XTRACE_ARM bash -c "source '$GATE'; set -x; git_data_rung2_rehearsal_gate '$R2/ci.yml' '$R2/s1.env'" 2>&1)"
if [[ "$_n2" != *"ghp_FAKE_TOKEN_FOR_XTRACE_ARM"* ]]; then
  pass "N2: a caller running set -x does not leak the bearer through the gate's trace"
else
  fail "N2: the bearer appeared in the xtrace of a set -x caller" "n/a" "<redacted: the arm's own needle was found>"
fi

# W1 — NO WORKFLOW AND NO DOPPLER CONFIG MAY CARRY THE SEAM. The announcement above is the
# detection; this is the prevention.
_w1="$(grep -rlE 'SOLEUR_TEST_MODE|SOLEUR_RUNG2_' "${ROOT}/.github/workflows" 2>/dev/null || true)"
if [[ -z "$_w1" ]]; then
  pass "W1: no workflow carries SOLEUR_TEST_MODE or a SOLEUR_RUNG2_ override"
else
  fail "W1: a workflow references the test seam — ${_w1}" "n/a" ""
fi



printf '\n(#8010) M — the Guard Contract mutation matrix\n'

# WHY THESE ROWS AND NOT MORE OF THE SAME. A battery's value is the number of DISTINCT things
# it perturbs, and the axes an author omits are the ones they were not thinking about. Row (a)
# of each guard mutates the HARNESS, because every other row scores the SUT through that
# harness and is blind to it. The rest mutate the gate, each on its own axis: the arm itself,
# the arm's ORDER, the arm's own operand (does it fail OPEN when degenerate?), and the
# stub-answers-everything axis.

# ── Guard 1: the resolved run ─────────────────────────────────────────────────────
mutate_r2 "M1a: neutering the run resolution releases evidence naming a nonexistent run" \
  's#_git_data_rung2_check_run "\$_run_id"#printf "OK|%s\\n" "$(git -C "$(dirname "$cloud_init")" rev-parse HEAD)"#' \
  0 "$R2/ci.yml" "$R2/r4.env" "RELEASED"

mutate_r2 "M1b: neutering the conclusion check releases a FAILED run" \
  's|^  if \[\[ "\$_concl" != "success" \]\]; then|  if false; then|' \
  0 "$R2/ci.yml" "$R2/r12.env" "RELEASED"

mutate_r2 "M1c: neutering the workflow-path check releases a run of a DIFFERENT workflow" \
  's|^  if \[\[ "\$_path" != "\$GIT_DATA_RUNG2_WORKFLOW_PATH" \]\]; then|  if false; then|' \
  0 "$R2/ci.yml" "$R2/r8.env" "RELEASED"

# THE GUARD'S OWN OPERAND, not the SUT. Degenerate the id the parser produces and ask whether
# the gate now accepts everything — the axis every SUT-mutating row misses, because they all
# confirm the guard REDS and none of them asks how it fails OPEN.
mutate_r2 "M1d: an EMPTY workflow-path operand must fail CLOSED, not accept every workflow" \
  's#^GIT_DATA_RUNG2_WORKFLOW_PATH=.*#GIT_DATA_RUNG2_WORKFLOW_PATH=""#' \
  1 "$R2/ci.yml" "$R2/r8.env" "[RUN_WRONG_WORKFLOW]"

# ── Guard 2: the head-SHA hash binding ───────────────────────────────────────────
MUTATE_G_NEEDLE="RELEASED" mutate_g "M2a: neutering the head-SHA re-hash releases a real run of DIFFERENT bytes" \
  's|^  if \[\[ "\$_run_sha" != "\$live_sha" \]\]; then|  if false; then|' \
  0 git_data_rung2_rehearsal_gate "$_HX/ci.yml" "$_HX/h2.env"

# The TREE-ISH form is load-bearing and was measured both ways: the pathspec form emits
# repo-root-relative entries, so <tmp>/<basename> does not exist and nothing can be hashed.
MUTATE_G_NEEDLE="[RUN_HASH_UNCOMPUTABLE]" mutate_g "M2b: the <sha>:<dir> tree-ish form is load-bearing — the pathspec form cannot hash at all" \
  's|_treeish="\${_sha}:\${_rel_dir}"|_treeish="${_sha}"|' \
  1 git_data_rung2_rehearsal_gate "$_HS/infra/ci.yml" "$_HS/infra/evidence.env"

# The symlink sweep: without it an attacker-influenceable commit can put a mode-120000 entry
# in the archived tree, which is both an arbitrary read and a same-hash laundering shape.
if grep -q 'find "\$_tmp" ' "$GATE"; then
  pass "M2c: the extraction refuses symlink and hardlink entries before hashing"
else
  fail "M2c: the lstat sweep over the archived tree is gone" "n/a" ""
fi

# ── Guard 3: the Sentry verdict ──────────────────────────────────────────────────
mutate_r2 "M3a: neutering the no-ack arm — the ack parser is the backstop, not a release" \
  's|^      if \[\[ -z "\$_ack" \]\]; then|      if false; then|' \
  1 "$R2/ci.yml" "$R2/s6.env" "[SENTRY_ACK_MISMATCH]"

mutate_r2 "M3b: neutering the ack run-id binding lets an ack copied from another run release" \
  's|^      if \[\[ "\$_ack" != \*:\* \|\| "\$_ack_id" != "\$_run_id" \]\]; then|      if false; then|' \
  0 "$R2/ci.yml" "$R2/s7.env" "RELEASED"

mutate_r2 "M3c: neutering the raw-'#' check releases on a reason the strip invented" \
  's|^      if \[\[ "\$_ack_raw" == \*"#"\* \]\]; then|      if false; then|' \
  0 "$R2/ci.yml" "$R2/s11.env" "RELEASED"

# ── Harness rows (a) — mutate THIS SUITE, because nothing else can ───────────────
#
# A stub that answers every question identically, or an assertion helper that always takes
# the pass branch, is indistinguishable from a healthy run. These are the only rows that
# can see that.
mutate_suite "M0a: a stub that answers 200-with-evidence for EVERY id reds this suite" \
  's|^\[\[ -f "\$body" \]\] \|\| exit 7$|[[ -f "$body" ]] \|\| { printf "{\\\\"id\\\\":1}\\\\n200\\\\n"; exit 0; }|' 1

mutate_suite "M0b: a _stub_run that ignores its conclusion= key reds this suite" \
  's|^      conclusion=\*)  conclusion="\${kv#\*=}" ;;$|      conclusion=*)  : ;;|' 1

mutate_suite "M0c: an evidence writer that ignores the Sentry verdict argument reds this suite" \
  's|"\$2" "\$3" "\$4" "\${5:-none}" "\${6-CLEAN}" > "\$1"|"$2" "$3" "$4" "${5:-none}" "CLEAN" > "$1"|' 1

# A floor, not equality: it is developer-incremented, so `-eq` would redden the suite on every
# legitimately added assertion and train the next person to bump it unread. Counts
# passes+fails, so a genuine failure still counts as HAVING RUN and reports as a failure
# rather than masquerading as an empty suite.
# RAISED 58 -> 69 WITH THE ARMS THAT MADE IT NECESSARY (#7485): A1–A11 above (A11 pins the payload floor at its near boundary).
# RAISED 69 -> 77 (#7534), ITEMISED — the canonical module-shape arms:
#     1  A12   multi-line file()                       -> ABORT
#     1  A13   indirected file(local.p)                -> ABORT
#     1  A14   a second templatefile()                 -> ABORT
#     1  A14b  two templatefile() on ONE line          -> ABORT (pins grep -o over grep -c)
#     1  A15   non-${path.module} single-line literal  -> ABORT
#     2  A16   a tenth payload: still hashes, AND the digest moves when it changes
#     1  A17   a value-form map entry does NOT trip the gate (Phase 5's shape, proved here)
#   ----
#     8
#
# RAISED 77 -> 80 (#7481 review, V9), ITEMISED — A12b/A13b/A15b pin the site-LISTING half
# of A12/A13/A15, which was asserted by their names and by nothing else.
#     3
#
# RAISED 80 -> 103 (#8009), ITEMISED — git_data_authorization_map_gate, CPO condition C1:
#     1  B1        the canonical five-link control (every arm below is void without it)
#     2  B2/B3     the headline collapse and its near boundary (1 and 2 distinct vs 3)
#     2  B4/B5     2-swap at link 1, 3-cycle at link 5 — the ORDERED-vs-bijection arms
#     1  B6        the transport secret publishing the erase key (link 5, no prior coverage)
#     2  B7/B8     attribute predicates: private into user_data, public as auth material
#     3  B9/B10/B11 slot shape: unfenced 4th key, extra option, deleted slot
#     2  B12/B13   sibling-file relocation (root scope) and *override.tf (merge order)
#     1  B14       a second render module
#     2  B15/B16   the ignore_changes premise, and dangling aliases
#     3  B17/B18/B19 non-resource terminal, partial extraction, zero extraction
#     2  B20/B21   the stripper: // in a string/# comment vs a genuine // comment
#     1  B22       fail-closed on a bare call
#     1  B23       the live production root (D8 — this is the PR-time coverage)
#   ----
#    23
#
# RAISED 103 -> 116 (#8009 review) -> 118 (the awk-portability arm), ITEMISED — every row a MEASURED rc=0 escape before it
# was closed, plus the helper self-test. The first battery had 26 rows and killed all 26
# and could see NONE of these: it perturbed the SUT toward obviously-broken spellings,
# while every row here is an innocuous-looking SIBLING declaration masking a real defect.
#   (+0) _am self-test  the helper owns a verdict, so pass()/fail() controls cannot see it.
#                     It contributes NOTHING to this count on purpose: it snapshots and
#                     unwinds the counters, and reports with printf + exit rather than
#                     through the helpers it backstops -- a floor dispatched through the
#                     thing it guards is disarmed by the same edit that disarms the guard.
#     2  B24/B25   a collapse and a permutation, each masked by a benign sibling block
#     3  B26/B27/B28 ambiguous terminals (ternary, try, coalesce) at BOTH link 4 and link 5
#     3  B29/B30/B31 scope: the server block, its existence, and the rendered template
#     3  B32/B33/B34 population growth: a 2nd server, a stray publisher, a *.tf.json
#     2  B35/B36   the template: runcmd as a second writer, and a non-literal content form
#     2  awk-portability: one arm per _git_data_hcl_block call site, asserting the
#                     pattern still COMPILES after gawk strips its backslashes (the
#                     mawk-vs-gawk split that made this gate ABORT on every CI run)
#   ----
#    15
#
# RAISED 118 -> 120 (#8043 F7), ITEMISED:
#     2  B37/B38   the map's OWNER and MODE, in the directions that rot (git:git; root 0600)
#
# RAISED 120 -> 146 (#8043 NFR2 / Guard 4), ITEMISED — the plan's ten mutation-matrix rows plus
# the fail-closed edges each of them implied, every one over a throwaway repository:
#     1  G1        harness: the derived roster is 13 wide here, as in production
#     2  G2/G3     row 1: template edit + hash edit in one commit (rehearsal gate; ARM 2)
#     2  G4/G5     row 2: a non-hash key edited alongside a payload edit (ARM 1; ARM 2)
#     1  G6        row 3: an EMPTY roster is refused, never intersected (mutation)
#     1  G7        row 4: intersecting only the template lets a payload edit pass (mutation)
#     2  G8/G9     row 5 MUST-PASS: bound edits + evidence DELETED (ARM 2 passes; birth still holds)
#     2  G10/G11   row 6 MUST-PASS: a rehearsal commit creating the evidence alone (ARM 2; gate)
#     1  G12       row 7 harness: a silently failing fixture commit reds the HARNESS
#     3  G13/G14/G15 row 8: the all-zeros sentinel and a shallow clone are NAMED holds; the
#                     empty-range control passes as 'untouched' and the holds do not say so
#     1  G16       row 9 MUST-PASS: the last evidence-touching commit touches only the evidence
#     2  G17/G18   row 10: a squash commit touching evidence + git-data-remove.sh (ARM 1; gate)
#     1  G19       the WIRING is load-bearing: neutering ARM 1's call releases the forgery
#     1  G20       a root commit carrying everything: diff-tree --root is load-bearing
#     2  G21/G22   evidence with no readable provenance: a working-tree edit; never committed
#     2  G23/G24   fail-closed on a malformed call: unknown mode; range mode with no range
#     1  G25       MUST-PASS: an ordinary payload PR that leaves the evidence untouched (ARM 2)
#     1  G26       bound files outside the evidence's repository: nothing measured => HOLD
#   ----
#    26
# RAISED 146 -> 149 (#8052 review, test-design seat), ITEMISED — lib mutants that survived 146/146:
#     1  G27       evidence ADDED beside a payload edit, range mode (kills `--diff-filter=AM` -> `=M`)
#     1  G28       a MODULE .tf co-edit, birth mode (kills "skip *.tf in the intersection")
#     1  G29       a merge commit as the last evidence toucher (kills dropping `-m` from diff-tree)
#            G10's needle moved from "PASS" to "rehearsal-PR shape" so it cannot be satisfied by
#            the "untouched" PASS branch.
# RAISED 149 -> 150 (#8010 sweep): +1 regression pin — the rung-2 no-evidence HOLD still
#            names git-data-birth.md after the DO-NOT-DISPATCH wording was retired.
# RAISED 150 -> 217 (#8010), ITEMISED — the gate now resolves the run its evidence names,
# and every row below buys a property that a four-line hand-written file defeated before:
#    14  S1-S14    the Sentry verdict's closed value set and the run-bound ack grammar
#     1  row-count pin for family S
#    15  R1-R15    resolving the run: transport, rate limit, 404, unparseable, id mismatch,
#                  trailing-garbage id, workflow, event, branch, status, conclusion,
#                  head_sha shape, the anonymous retry AND its negative control
#     1  row-count pin for family R
#     5  A1-A5     the capture discriminator: dry_run, the capture-LOG artifact, the
#                  retention window, an unreadable endpoint, and an EXPIRED record
#     1  row-count pin for family A
#     6  H1-H6     the head-SHA binding: unreachable, the forgery (a real run of DIFFERENT
#                  bytes), both tree-ish forms, a sub-floor tree, and the order pin
#     1  row-count pin for family H
#     2  T1        the tooling ABORT, AND its positive control (without it T1 passes for any
#                  reason the PATH farm breaks the gate and proves nothing)
#     3  T-SEAM    the seam announces itself on RELEASED and on HOLD, and the double gate
#                  falls through when only half of it is set
#     2  E1/E2     exactly one ::error:: for a could-not-measure token, none for a refusal
#     3  N1/N2/W1  the curl flag set, the bearer under a `set -x` caller, and the sweep
#                  proving no workflow carries the seam
#    10  M0a-M3c   the Guard Contract matrix. M0a-M0c mutate THIS SUITE, which is the only
#                  axis the other rows are structurally blind to: they all score the gate
#                  THROUGH the stub and the assertion helpers. M1d mutates the guard's own
#                  OPERAND and asserts it fails CLOSED — the axis every SUT-mutating row
#                  misses, because they confirm the guard REDS and never ask how it opens.
#   ----
#    67
# Two pre-existing mutation rows changed their EXPECTED VERDICT rather than their meaning:
# neutering the URL-shape check and neutering the no-ack arm no longer release, because the
# run-id parser and the ack parser refuse the same inputs one step later. Both now carry a
# needle naming the backstop, which is what the new 6th argument to mutate_r2 exists for.
# RAISED 217 -> 234 (#8010 review round), ITEMISED — every row closes a vacuity a nine-seat
# panel MEASURED, not reasoned:
#     1  _er_self_test  the probe _expect_rows shipped without. Neutering its condition left
#                       the suite at 217/0: it owns a verdict, so a wrong BRANCH still moves
#                       both counters and satisfies the floor. Contributes 0 to this count on
#                       purpose (it snapshots and unwinds), like _am_self_test beside it.
#     3  E2b/E2c/E2d    the annotation's two sets, asserted in BOTH directions plus disjoint
#                       coverage of every bracketed token the gate emits. E2 itself was
#                       vacuous — its fixture refused at step B, which has no annotate call.
#     2  N1b/N1c        the API base is a readonly https constant (an env override handed an
#                       attacker the bearer AND step C's verdict); the sanitizer is driven
#                       directly, because replacing its body with the identity left 217/0.
#     3  A6/A7/A8       the multi-attempt artifact list (population > 1, which is why reading
#                       .artifacts[0] survived), and the retention window's 89d/91d boundary.
#     1  R16            the 5xx retry's far side — always-500 could not see the retry at all.
#     7  F1-F7          Guard 5: the monotonic run floor, its ack grammar, and the DELETION
#                       case that makes voiding an attestation not a bypass.
#     1  F3b            the downgrade ack's '#' rule, which the HOLD message stated and the
#                       code did not implement (#8010 ship-time consult, 2026-09-20). The
#                       helper reads the comment-STRIPPED body, so a reason carrying '#'
#                       arrived truncated-but-non-empty and the replay hatch accepted it.
#     1  T1-ORDER       the tooling check's POSITION (#8010 AC sweep, 2026-09-20). T1 pinned
#                       the TOKEN only, so FR14's planned order -- tooling AFTER Guard 4 --
#                       drifted silently against a live-hash step that runs `sha256sum`
#                       BEFORE Guard 4. Dropping only sha256sum discriminates the two.
#   ----
#    19
_FLOOR=236
_ran=$((passes + fails))
if [[ "$_ran" -lt "$_FLOOR" ]]; then
  fails=$((fails + 1))
  # APPEND TO THE LEDGER TOO. The verdict is `exit $(( ${#FAILURES[@]} > 0 ))`, so a floor
  # that only bumps the counter exits non-zero by ACCIDENT — via the reconciliation below
  # tripping — and prints "fail() was tampered with", which is false and misdirects whoever
  # hits it. It also means the natural fix for that false message (relaxing the
  # reconciliation) silently disarms the floor: measured 102 assertions, "1 failed", exit 0.
  FAILURES+=("ANTI-VACUITY: only ${_ran} assertions ran, floor is ${_FLOOR}")
  printf '  FAIL ANTI-VACUITY: only %s assertions ran, floor is %s. Arms were deleted, skipped, or the suite exited early.\n' "$_ran" "$_FLOOR"
else
  printf '  ok   anti-vacuity floor: %s assertions ran (floor %s)\n' "$_ran" "$_FLOOR"
fi

# LEDGER RECONCILIATION. A stalled append or a stalled counter each break this; neither is
# visible to the pass/fail totals or to the floor.
if [[ "${#FAILURES[@]}" -ne "$fails" ]]; then
  printf '  FAIL LEDGER: %s failures counted but %s recorded — fail() was tampered with.\n' \
    "$fails" "${#FAILURES[@]}"
  exit 1
fi
printf '\n=== %d passed, %d failed ===\n\n' "$passes" "$fails"
# THE VERDICT IS AN `exit`, NOT A TRAILING TEST EXPRESSION. A bare `[[ "$fails" -eq 0 ]]` as the
# final statement makes the exit status a property of which line happens to be LAST: measured,
# appending any single command after it (a printf, a stray echo) permanently greens the suite
# while it goes on printing accurate failure text, and run_suite() classifies on the exit code
# alone. Deleting the line has the same effect. An explicit exit cannot be defeated by an append.
exit $(( ${#FAILURES[@]} > 0 ))
