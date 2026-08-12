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
ROOT="$(cd "${DIR}/../.." && pwd)"
GATE="${ROOT}/tests/scripts/lib/git-data-birth-readiness-gate.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

passes=0
fails=0
pass() { passes=$((passes + 1)); printf '  ok   %s\n' "$1"; }
fail() {
  fails=$((fails + 1))
  printf '  FAIL %s\n' "$1"; printf '       rc=%s\n' "${2:-?}"; printf '       out=%s\n' "${3:-}"
}

# shellcheck source=/dev/null
source "$GATE"

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
check "the HOLD names the runbook banner to clear" 1 "git-data-birth.md" "$TMP/no-emitter.yml"
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

r2_evidence() {  # $1=dest $2=verdict $3=url $4=sha [$5=divergence, default "none"]
  # Defaults to the EXPLICIT `none` rather than omitting the key: an absent key is now
  # refused, because omitting it left the allowlist loop iterating zero times and the CLOSED
  # allowlist refusing nothing (#7066 review). "Nothing diverged" must be declared.
  printf 'RUNG2_BOOT_REHEARSAL=%s\nRUNG2_EVIDENCE_URL=%s\nRUNG2_TEMPLATE_SHA256=%s\nRUNG2_VAR_DIVERGENCE=%s\n' \
    "$2" "$3" "$4" "${5:-none}" > "$1"
  return 0
}

r2_evidence "$R2/ok.env" PASS "https://github.com/jikig-ai/soleur/actions/runs/1" "$R2_SHA"
r2check "valid, hash-matched evidence => RELEASED" 0 "RELEASED" "$R2/ci.yml" "$R2/ok.env"

r2check "absent evidence => HOLD" 1 "no rung-2 boot evidence" "$R2/ci.yml" "$R2/absent.env"

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
# outside the identity-shaped allowlist refuses.
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
  printf 'RUNG2_TEMPLATE_SHA256=%s\nRUNG2_VAR_DIVERGENCE=\n' "$R2_SHA"; } > "$R2/emptydiv.env"
r2check "an EMPTY RUNG2_VAR_DIVERGENCE is refused (silence cannot release)" 1 "EMPTY value" \
  "$R2/ci.yml" "$R2/emptydiv.env"

{ printf 'RUNG2_BOOT_REHEARSAL=PASS\nRUNG2_EVIDENCE_URL=%s\n' "$R2_URL"
  printf 'RUNG2_TEMPLATE_SHA256=%s\nRUNG2_VAR_DIVERGENCE=   \n' "$R2_SHA"; } > "$R2/wsdiv.env"
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
  local label="$1" sed_expr="$2" want_rc="$3" ci="$4" ev="$5"
  local mutated out rc
  mutated="$TMP/mutated-r2.sh"
  sed "$sed_expr" "$GATE" > "$mutated"
  if cmp -s "$mutated" "$GATE"; then
    fail "$label — the mutation matched NOTHING in the gate (byte-identical copy); the guard is missing or the sed expression drifted." "n/a" "no textual change"
    return
  fi
  out="$(bash -c "source '$mutated'; git_data_rung2_rehearsal_gate '$ci' '$ev'" 2>&1)"; rc=$?
  if [[ "$rc" -eq "$want_rc" ]]; then
    pass "$label (arm is load-bearing — neutering it flips the verdict)"
  else
    fail "$label — the arm did NOT change behavior when neutered; it may be dead code" "$rc" "$out"
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
mutate_r2 "rung-2 evidence-URL arm" \
  's|^  if \[\[ ! "\$url" =~ .*|  if false; then|' \
  0 "$R2/ci.yml" "$R2/nourl.env"

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

_a_setup_fail() { printf '\n  HARNESS ABORT: %s\n' "$1" >&2; exit 2; }

_a_tree() {  # $1 = arm name -> prints the path to a fresh copy of the R2 fixture tree
  local d="$TMP/a_$1"
  rm -rf "$d" || _a_setup_fail "could not clear $d"
  cp -r "$R2" "$d" || _a_setup_fail "could not copy the R2 fixture into $d"
  printf '%s' "$d"
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

# Asserts rc=0 and a well-formed digest, and publishes it in _A_DIGEST for A6's comparison.
# Called directly, never in a command substitution, so the global survives.
_A_DIGEST=""
_a_hash() {  # $1=name $2=cloud-init
  local name="$1" ci="$2" out rc
  out="$(git_data_rung2_user_data_sha256 "$ci" 2>&1)"; rc=$?
  _A_DIGEST=""
  if [[ "$rc" -eq 0 && "$out" =~ ^[0-9a-f]{64}$ ]]; then
    _A_DIGEST="$out"; pass "$name"
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
_a2="$(_a_tree a2)"
_a_sibling_var "$_a2/modules/git-data-userdata/variables.tf"
_a_sibling_out "$_a2/modules/git-data-userdata/outputs.tf"
_a_hash "A2: a module directory with two sibling .tf files returns 0" "$_a2/ci.yml"

# A3 — sibling-count independence. Three siblings must behave exactly like two.
_a3="$(_a_tree a3)"
_a_sibling_var "$_a3/modules/git-data-userdata/variables.tf"
_a_sibling_out "$_a3/modules/git-data-userdata/outputs.tf"
printf 'terraform {\n  required_version = ">= 1.5.0"\n}\n' > "$_a3/modules/git-data-userdata/versions.tf"
_a_hash "A3: sibling-count independence — three siblings also return 0" "$_a3/ci.yml"

# A4 — a present-but-unreadable sibling must ABORT, not be silently dropped. Measured rc=0
# against the first draft's payload-loop-only shape: the hash was well-formed over a NARROWER
# set, which is the fail-open this whole change exists to prevent.
_a4="$(_a_tree a4)"
ln -s /nonexistent/dangling-a4 "$_a4/modules/git-data-userdata/variables.tf" \
  || _a_setup_fail "could not create the A4 dangling symlink"
_a_abort "A4: an unreadable .tf sibling aborts, naming the file" \
         "variables.tf' is present but cannot be read" "$_a4/ci.yml"

# A5 — the abort must attach to BOTH glob patterns, not just the first.
_a5="$(_a_tree a5)"
ln -s /nonexistent/dangling-a5 "$_a5/modules/git-data-userdata/extra.tf.json" \
  || _a_setup_fail "could not create the A5 dangling symlink"
_a_abort "A5: an unreadable .tf.json sibling aborts, naming the file" \
         "extra.tf.json' is present but cannot be read" "$_a5/ci.yml"

# A6 — a readable .tf.json is HASHED, not merely tolerated. Terraform loads .tf.json, so a
# knob written there decides what boots; asserting rc=0 alone would pass against a glob that
# skipped the file entirely. The digest must MOVE.
_a6="$(_a_tree a6)"
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
_a7="$(_a_tree a7)"
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
_a8="$(_a_tree a8)"
rm -f "$_a8/git-data-gc.service" || _a_setup_fail "could not remove the A8 payload"
_a_abort "A8: a deleted referenced payload aborts, naming it" \
         "references payload '../../git-data-gc.service'" "$_a8/ci.yml"

# A9 — the floor is on the PAYLOAD count, and its message names that count. Siblings are
# present so the arm proves the floor is not merely counting `_inputs` again.
_a9="$(_a_tree a9)"
_a_sibling_var "$_a9/modules/git-data-userdata/variables.tf"
_a_sibling_out "$_a9/modules/git-data-userdata/outputs.tf"
_r2_write_module "$_a9" git-data-bootstrap.sh git-data-gc.sh
_a_abort "A9: a module binding only 2 payloads aborts, naming the payload count" \
         "resolved only 2 payload(s)" "$_a9/ci.yml"

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
_a10="$(_a_tree a10)"
_a_sibling_var "$_a10/modules/git-data-userdata/variables.tf"
printf '{"variable":{"a10_knob":{"default":"x"}}}\n' > "$_a10/modules/git-data-userdata/extra.tf.json"
_a10_mirror="$(_r2_hash "$_a10")"
_a10_lib="$(git_data_rung2_user_data_sha256 "$_a10/ci.yml" 2>&1)"; _a10_rc=$?
if [[ "$_a10_rc" -eq 0 && -n "$_a10_mirror" && "$_a10_mirror" == "$_a10_lib" ]]; then
  pass "A10: _r2_hash equals the lib's derivation over the same fixture (mirror non-drift)"
else
  fail "A10: _r2_hash equals the lib's derivation over the same fixture (mirror non-drift)" \
       "$_a10_rc" "mirror=${_a10_mirror} lib=${_a10_lib}"
fi

# MINIMUM-CARDINALITY FLOOR. This suite had none, and it now covers TWO gates: an early
# `exit`, a helper that silently stopped being called, or a fixture-setup failure would
# otherwise report "0 failed" — the vacuous green every guard in this file exists to reject.
# A floor, not equality: it is developer-incremented, so `-eq` would redden the suite on every
# legitimately added assertion and train the next person to bump it unread. Counts
# passes+fails, so a genuine failure still counts as HAVING RUN and reports as a failure
# rather than masquerading as an empty suite.
# RAISED 58 -> 68 WITH THE ARMS THAT MADE IT NECESSARY (#7485): A1–A10 above.
_ran=$((passes + fails))
if [[ "$_ran" -lt 68 ]]; then
  fails=$((fails + 1))
  printf '  FAIL ANTI-VACUITY: only %s assertions ran, floor is 68. Arms were deleted, skipped, or the suite exited early.\n' "$_ran"
else
  printf '  ok   anti-vacuity floor: %s assertions ran (floor 68)\n' "$_ran"
fi

printf '\n=== %d passed, %d failed ===\n\n' "$passes" "$fails"
[[ "$fails" -eq 0 ]]
