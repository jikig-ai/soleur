#!/usr/bin/env bash
# Tests for scripts/lint-buildarg-secret-channels.py (#7389).
#
# The guard fails any build channel that would record a non-public credential in a
# PUBLISHED artifact: a Docker build-arg (recorded in the SLSA provenance attestation),
# a credential-shaped Dockerfile ARG/ENV/LABEL, or a `--build-arg` in a shell script.
#
# Assert on EXIT CODES per case, never on a summary literal and never on "the suite
# fails" -- the repo-baseline case is legitimately red until Phase 3 lands, so a red
# suite would prove nothing about the other cases being wired.
#
# Exit contract: 0 clean, 1 violation(s), 2 arg/parse error.
#
# Fixtures are SYNTHESIZED (cq-test-fixtures-synthesized-only). No fixture carries a
# real or expired credential -- the value side is irrelevant to this guard by design
# (it flags on the KEY, regardless of the value expression), so every fixture value is
# an obvious placeholder.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SUT="$SCRIPT_DIR/lint-buildarg-secret-channels.py"
ALLOWLIST="$SCRIPT_DIR/buildarg-key-allowlist.txt"

# /tmp is a machine-global 4 GiB tmpfs shared by parallel worktrees; a direct
# invocation of this suite inherits it unless we default TMPDIR ourselves.
export TMPDIR="${TMPDIR:-/var/tmp}"

PASS=0
FAIL=0
TOTAL=0
pass() { echo "PASS: $1"; PASS=$((PASS + 1)); TOTAL=$((TOTAL + 1)); }
fail() {
  echo "FAIL: $1"
  echo "  detail: ${2:-}"
  FAIL=$((FAIL + 1))
  TOTAL=$((TOTAL + 1))
}

WORK="$(mktemp -d -t buildarg-lint.XXXXXXXX)" || { echo "harness: mktemp failed" >&2; exit 2; }
# A harness that cannot set itself up must abort, never continue -- otherwise the next
# case runs against the previous case's fixture and reports a confident wrong verdict.
[[ -d "$WORK" ]] || { echo "harness: work dir missing" >&2; exit 2; }
trap 'rm -rf "$WORK"' EXIT

# mkroot makes a fresh fake repo root and echoes its path.
#
# It SEEDS a benign Dockerfile and shell script on purpose. Without them every case
# would also trip the "scan set matched ZERO files" finding, so each RED case would
# return rc=1 whether or not the behaviour under test worked -- 13 vacuous greens.
# The empty-scan-set case builds its own bare root instead.
# NOTE ON ISOLATION. These are called as `r="$(mkroot)"`, i.e. in a command
# substitution SUBSHELL, so they must not depend on mutating a counter in the parent --
# a `CASE_N=$((CASE_N+1))` here is discarded on return, every call yields the SAME
# path, and all cases silently share one directory. Measured: that made the RED cases
# pass on violations LEFT BEHIND BY OTHER CASES. `mktemp -d` needs no parent state.
mkroot() {
  local d
  d="$(mktemp -d "$WORK/case.XXXXXXXX")" || { echo "harness: mktemp failed" >&2; exit 2; }
  mkdir -p "$d/.github/workflows" "$d/scripts" || { echo "harness: mkdir failed" >&2; exit 2; }
  printf 'FROM busybox\nARG BUILD_SHA\n' > "$d/Dockerfile" || { echo "harness: seed failed" >&2; exit 2; }
  printf '#!/usr/bin/env bash\ntrue\n' > "$d/scripts/benign.sh" || { echo "harness: seed failed" >&2; exit 2; }
  printf '%s' "$d"
}

# mkbareroot: no seeded files, for the empty-scan-set case only.
mkbareroot() {
  local d
  d="$(mktemp -d "$WORK/bare.XXXXXXXX")" || { echo "harness: mktemp failed" >&2; exit 2; }
  mkdir -p "$d/.github/workflows" || { echo "harness: mkdir failed" >&2; exit 2; }
  printf '%s' "$d"
}

# expect_finding: rc must match AND the output must name the given anchor. Without the
# anchor check a case passes on ANY finding, which is how a gate ends up certified by
# a violation it was not testing for.
expect_finding() { # <label> <want_rc> <got_rc> <anchor>
  if [[ "$3" != "$2" ]]; then
    fail "$1" "want rc=$2 got rc=$3 :: ${LAST_OUT:0:400}"; return
  fi
  if [[ "$2" == "1" ]] && ! grep -qF -- "$4" <<<"$LAST_OUT"; then
    fail "$1" "rc matched but output never names '$4' :: ${LAST_OUT:0:400}"; return
  fi
  pass "$1"
}

# run_sut <root> [extra args...] -- sets LAST_OUT and LAST_RC as GLOBALS.
#
# It deliberately does NOT echo the rc for `$(run_sut ...)` capture. Command
# substitution runs the function in a SUBSHELL, so a `LAST_OUT=` assignment inside it
# is discarded and every anchor check would compare against an empty string -- passing
# on rc alone while silently testing nothing. Callers run it as a statement.
LAST_OUT=""
LAST_RC=0
run_sut() {
  local root="$1"; shift
  LAST_OUT="$(python3 "$SUT" --root "$root" --allowlist "$ALLOWLIST" "$@" 2>&1)"
  LAST_RC=$?
}

expect_rc() { # <label> <want> <got>
  if [[ "$3" == "$2" ]]; then pass "$1"; else fail "$1" "want rc=$2 got rc=$3 :: ${LAST_OUT:0:400}"; fi
}

# ---------------------------------------------------------------------------
# Preflight: the SUT and its allowlist must exist. Without this the whole suite
# would report a uniform rc=2 that reads like 22 independent failures.
# ---------------------------------------------------------------------------
if [[ ! -f "$SUT" ]]; then
  echo "FAIL: SUT missing at $SUT (expected during RED)"; exit 1
fi
if [[ ! -f "$ALLOWLIST" ]]; then
  echo "FAIL: allowlist missing at $ALLOWLIST (expected during RED)"; exit 1
fi

wf() { # <root> <name> <body>
  printf '%s\n' "$3" > "$1/.github/workflows/$2"
}

# A minimal build-push-action workflow whose build-args are $1..
mkwf() { # <root> <build-args block, newline separated, already indented 12sp>
  local root="$1" args="$2"
  cat > "$root/.github/workflows/rel.yml" <<EOF
name: rel
on: push
jobs:
  b:
    runs-on: ubuntu-latest
    steps:
      - name: Scan build channels for credentials
        run: python3 scripts/lint-buildarg-secret-channels.py
      - name: Build and push
        id: docker_build
        uses: docker/build-push-action@v6
        with:
          push: true
          provenance: mode=min
          build-args: |
$args
EOF
}

# ===========================================================================
# Source sweep -- RED cases (2.2)
# ===========================================================================

r="$(mkroot)"; mkwf "$r" "            SENTRY_AUTH_TOKEN=\${{ secrets.SENTRY_IAC_AUTH_TOKEN }}"
run_sut "$r"; expect_finding "RED: credential-shaped build-arg from a secrets expression" 1 "$LAST_RC" "SENTRY_AUTH_TOKEN"

# The name asymmetry: the build-arg KEY differs from the secret NAME. A guard that
# keyed on the secret name would miss this; the guard must key on the ARG key.
r="$(mkroot)"; mkwf "$r" "            FOO_TOKEN=\${{ secrets.BAR }}"
run_sut "$r"; expect_finding "RED: name asymmetry (FOO_TOKEN=secrets.BAR)" 1 "$LAST_RC" "FOO_TOKEN"

# Conjunction case 1: BUILD_ is an allowlisted PREFIX, but the key is credential-shaped.
r="$(mkroot)"; mkwf "$r" "            BUILD_DEPLOY_TOKEN=\${{ secrets.X }}"
run_sut "$r"; expect_finding "RED: BUILD_DEPLOY_TOKEN (allowlisted prefix, credential-shaped)" 1 "$LAST_RC" "BUILD_DEPLOY_TOKEN"

# Conjunction case 2: NEXT_PUBLIC_ is an allowlisted PREFIX, but the key is
# credential-shaped. This is the case a prefix-only allowlist admits.
r="$(mkroot)"; mkwf "$r" "            NEXT_PUBLIC_SECRET_KEY=\${{ secrets.X }}"
run_sut "$r"; expect_finding "RED: NEXT_PUBLIC_SECRET_KEY (allowlisted prefix, credential-shaped)" 1 "$LAST_RC" "NEXT_PUBLIC_SECRET_KEY"

# Flag regardless of the VALUE expression -- a literal is as recorded as a secret ref.
r="$(mkroot)"; mkwf "$r" "            SOME_TOKEN=hardcoded-placeholder"
run_sut "$r"; expect_finding "RED: flagged on the key even with a literal value" 1 "$LAST_RC" "SOME_TOKEN"

# Non-allowlisted, non-credential-shaped key is still a finding (default-deny).
r="$(mkroot)"; mkwf "$r" "            RANDOM_THING=whatever"
run_sut "$r"; expect_finding "RED: default-deny on a non-allowlisted key" 1 "$LAST_RC" "RANDOM_THING"

# Credential-shaped Dockerfile ARG.
r="$(mkroot)"; mkwf "$r" "            BUILD_SHA=abc"
printf 'FROM busybox\nARG BUILD_SHA\nARG SENTRY_AUTH_TOKEN\n' > "$r/Dockerfile"
run_sut "$r"; expect_finding "RED: credential-shaped Dockerfile ARG" 1 "$LAST_RC" "ARG SENTRY_AUTH_TOKEN"

# Credential-shaped LABEL.
r="$(mkroot)"; mkwf "$r" "            BUILD_SHA=abc"
printf 'FROM busybox\nARG BUILD_SHA\nLABEL org.acme.api_token="placeholder"\n' > "$r/Dockerfile"
run_sut "$r"; expect_finding "RED: credential-shaped LABEL" 1 "$LAST_RC" "org.acme.api_token"

# Credential-shaped ENV in a Dockerfile (baked into the image config, published).
r="$(mkroot)"; mkwf "$r" "            BUILD_SHA=abc"
printf 'FROM busybox\nARG BUILD_SHA\nENV DEPLOY_SECRET=placeholder\n' > "$r/Dockerfile"
run_sut "$r"; expect_finding "RED: credential-shaped Dockerfile ENV" 1 "$LAST_RC" "ENV DEPLOY_SECRET"

# --build-arg in a shell script.
r="$(mkroot)"; mkwf "$r" "            BUILD_SHA=abc"
mkdir -p "$r/scripts"
# The fixture flag and key are SPLIT across printf arguments so this file never holds
# the contiguous string the guard matches on. The live-repo sweep at the bottom of this
# suite reads every *.sh in the tree INCLUDING THIS ONE, so an inline literal -- even
# inside a comment -- makes the guard report a finding against its own test fixture.
# (Measured: the first version of this very comment did exactly that.) Same class as
# the synthesized secret-SHAPE fixture rule: the runtime value is what matters, not the
# source bytes. Do not "clarify" this by writing the flag out.
printf '#!/usr/bin/env bash\ndocker build --build%s %s="$X" .\n' "-arg" "API_TOKEN" > "$r/scripts/b.sh"
run_sut "$r"; expect_finding "RED: --build-arg with a credential-shaped key in a shell script" 1 "$LAST_RC" "API_TOKEN"

# A push:true build-push-action workflow that never invokes the gate.
r="$(mkroot)"
cat > "$r/.github/workflows/rel.yml" <<'EOF'
name: rel
on: push
jobs:
  b:
    runs-on: ubuntu-latest
    steps:
      - uses: docker/build-push-action@v6
        with:
          push: true
          build-args: |
            BUILD_SHA=abc
EOF
run_sut "$r"; expect_finding "RED: push:true workflow does not invoke the gate" 1 "$LAST_RC" "never invokes"

# Regression pin: a COMMENT naming the gate script must NOT satisfy the invocation
# check. The first implementation used a whole-file substring test, so a workflow whose
# only mention of the script was an explanatory comment was certified as gated -- and
# reusable-release.yml carries exactly such a comment, so deleting the real gate step
# left the sweep green. Anchor on the `run:` body, not on the file text.
r="$(mkroot)"
cat > "$r/.github/workflows/rel.yml" <<'EOF'
name: rel
on: push
jobs:
  b:
    runs-on: ubuntu-latest
    steps:
      # scripts/lint-buildarg-secret-channels.py enforces the build-arg rule.
      - uses: docker/build-push-action@v6
        with:
          push: true
          provenance: mode=min
          build-args: |
            BUILD_SHA=abc
EOF
run_sut "$r"; expect_finding "RED: a comment naming the gate does not count as invoking it" 1 "$LAST_RC" "never invokes"

# `provenance: false` disables the attestation outright -- strictly safer than mode=min,
# so it must be ACCEPTED, and it must not require the attestation gate. Regression pin:
# YAML `false` is falsy, and reading it with `or ""` turned the safest configuration in
# the repo into a finding.
r="$(mkroot)"
cat > "$r/.github/workflows/rel.yml" <<'EOF'
name: rel
on: push
jobs:
  b:
    runs-on: ubuntu-latest
    steps:
      - uses: docker/build-push-action@v6
        with:
          push: true
          provenance: false
          build-args: |
            BUILD_SHA=abc
EOF
printf 'FROM busybox\n' > "$r/Dockerfile"
mkdir -p "$r/scripts"; printf '#!/usr/bin/env bash\ntrue\n' > "$r/scripts/x.sh"
run_sut "$r"; expect_rc "GREEN: provenance:false disables the channel and is accepted" 0 "$LAST_RC"

# Missing the BUILD_SHA positive control -- proves the sweep actually saw the block.
r="$(mkroot)"; mkwf "$r" "            BUILD_VERSION=1.0.0"
run_sut "$r"; expect_finding "RED: positive control BUILD_SHA absent from the scanned block" 1 "$LAST_RC" "positive control"

# Empty scan set: zero files matched a glob set means the sweep is not looking where
# it thinks it is. Silence must not read as clean.
r="$(mkbareroot)"
run_sut "$r"; expect_finding "RED: empty scan set (no workflows at all)" 1 "$LAST_RC" "matched ZERO files"

# ===========================================================================
# Source sweep -- GREEN cases (2.3)
# ===========================================================================

r="$(mkroot)"
mkwf "$r" "            NEXT_PUBLIC_SUPABASE_URL=\${{ secrets.A }}
            NEXT_PUBLIC_SUPABASE_ANON_KEY=\${{ secrets.B }}
            NEXT_PUBLIC_SENTRY_DSN=\${{ secrets.C }}
            NEXT_PUBLIC_VAPID_PUBLIC_KEY=\${{ secrets.D }}
            SENTRY_ORG=\${{ secrets.E }}
            SENTRY_PROJECT=\${{ secrets.F }}
            BUILD_VERSION=1.0.0
            BUILD_SHA=abc
            NEXT_PUBLIC_AGENT_COUNT=12"
run_sut "$r"; expect_rc "GREEN: the real public-by-design build-arg set" 0 "$LAST_RC"

# ===========================================================================
# Credential-shape anchoring (2.3) -- unit-level, via --shape-check.
# These assert the SHAPE regex does not over-match, independent of the allowlist.
# ===========================================================================

shape() { # <key> -- sets LAST_OUT/LAST_RC (globals; see run_sut on subshells)
  LAST_OUT="$(python3 "$SUT" --shape-check "$1" 2>&1)"
  LAST_RC=$?
}

for k in PATH NODE_PATH AUTHOR NEXTAUTH_URL BUILD_SHA BUILD_VERSION NEXT_PUBLIC_AGENT_COUNT; do
  shape "$k"; expect_rc "shape: $k is NOT credential-shaped" 0 "$LAST_RC"
done

for k in SENTRY_AUTH_TOKEN FOO_TOKEN BUILD_DEPLOY_TOKEN NEXT_PUBLIC_SECRET_KEY DB_PASSWORD \
         AWS_CREDENTIALS GH_PAT SOME_DSN API_KEY; do
  shape "$k"; expect_rc "shape: $k IS credential-shaped" 1 "$LAST_RC"
done

# CACHE_KEY: the plan listed this as an anchoring GREEN. It is not -- `_KEY$` matches,
# and that is the correct posture: a cache key can be sensitive, so it must be
# exact-listed with a justification rather than admitted by shape. Pinned so the
# classification is a decision on the record, not an accident.
shape "CACHE_KEY"; expect_rc "shape: CACHE_KEY IS credential-shaped (plan listed it GREEN; corrected)" 1 "$LAST_RC"

# ===========================================================================
# --provenance mode (2.4)
# ===========================================================================

prov() { # <file> [extra] -- sets LAST_OUT/LAST_RC (globals; see run_sut on subshells)
  LAST_OUT="$(python3 "$SUT" --provenance "$1" --allowlist "$ALLOWLIST" "${@:2}" 2>&1)"
  LAST_RC=$?
}

mkprov() { # <args-json> -> path   (two positive controls: .Provenance and .Image)
  local f
  f="$(mktemp "$WORK/prov.XXXXXXXX.json")" || { echo "harness: mktemp failed" >&2; exit 2; }
  cat > "$f" <<EOF
{
  "SLSA": {
    "buildDefinition": {
      "externalParameters": { "request": { "args": $1 } }
    }
  },
  "Image": { "config": { "Env": ["PATH=/usr/bin"], "Labels": {} }, "history": [] }
}
EOF
  printf '%s' "$f"
}

p="$(mkprov '{"build-arg:BUILD_SHA":"abc","build-arg:NEXT_PUBLIC_SUPABASE_URL":"https://x"}')"
prov "$p"; expect_rc "prov GREEN: allowlisted keys only" 0 "$LAST_RC"

p="$(mkprov '{"build-arg:BUILD_SHA":"abc","build-arg:SENTRY_AUTH_TOKEN":"placeholder-value"}')"
prov "$p"; expect_rc "prov RED: credential-shaped key present" 1 "$LAST_RC"

# Non-allowlisted key under a DIFFERENT request-attribute prefix -- deny-by-default
# must cover the whole request-attribute map, not just `build-arg:`.
p="$(mkprov '{"build-arg:BUILD_SHA":"abc","label:acme.token":"placeholder"}')"
prov "$p"; expect_rc "prov RED: non-allowlisted key under a non-build-arg prefix" 1 "$LAST_RC"

# Unparseable input must fail closed, not read as clean.
bad="$(mktemp "$WORK/provbad.XXXXXXXX.json")"; printf 'not json at all' > "$bad"
prov "$bad"; expect_rc "prov RED: unparseable input fails closed" 1 "$LAST_RC"

# A degraded 200 that serialized `null` must fail closed too (jq's null|length == 0).
nul="$(mktemp "$WORK/provnull.XXXXXXXX.json")"; printf '{"SLSA":null,"Image":null}' > "$nul"
prov "$nul"; expect_rc "prov RED: null SLSA fails closed (not 'zero args, clean')" 1 "$LAST_RC"

# Positive controls: BOTH fetches must be present. Either one missing => cannot-inspect.
noimg="$(mktemp "$WORK/provnoimg.XXXXXXXX.json")"
printf '{"SLSA":{"buildDefinition":{"externalParameters":{"request":{"args":{"build-arg:BUILD_SHA":"a"}}}}}}' > "$noimg"
prov "$noimg"; expect_rc "prov RED: .Image positive control missing" 1 "$LAST_RC"

noslsa="$(mktemp "$WORK/provnoslsa.XXXXXXXX.json")"
printf '{"Image":{"config":{"Env":[],"Labels":{}},"history":[]}}' > "$noslsa"
prov "$noslsa"; expect_rc "prov RED: .Provenance positive control missing" 1 "$LAST_RC"

# Image-config channels are mode-independent: a credential-shaped Env/Label/history
# entry leaks regardless of provenance mode.
envleak="$(mktemp "$WORK/provenvleak.XXXXXXXX.json")"
cat > "$envleak" <<'EOF'
{
  "SLSA": { "buildDefinition": { "externalParameters": { "request": { "args": {"build-arg:BUILD_SHA":"a"} } } } },
  "Image": { "config": { "Env": ["SENTRY_AUTH_TOKEN=placeholder"], "Labels": {} }, "history": [] }
}
EOF
prov "$envleak"; expect_rc "prov RED: credential-shaped image-config Env" 1 "$LAST_RC"

# ===========================================================================
# Allowlist SSOT drift (AC6)
# ===========================================================================
if grep -qF 'buildarg-key-allowlist.txt' "$SUT"; then
  pass "allowlist path is resolved from the SUT (single SSOT)"
else
  fail "allowlist path is resolved from the SUT (single SSOT)" "SUT does not reference the allowlist filename"
fi

# ===========================================================================
# Live repo sweep -- the gate must pass against the real tree after Phase 3.
# ===========================================================================
LAST_OUT="$(python3 "$SUT" --root "$REPO_ROOT" --allowlist "$ALLOWLIST" 2>&1)"
live_rc=$?
if [[ "$live_rc" == "0" ]]; then
  pass "live repo sweep is clean"
else
  fail "live repo sweep is clean" "rc=$live_rc :: ${LAST_OUT:0:600}"
fi

# Non-empty scanned count per glob set -- a sweep that matched nothing is not clean.
if grep -qE 'scanned:.*workflows=[1-9]' <<<"$LAST_OUT" && grep -qE 'scanned:.*dockerfiles=[1-9]' <<<"$LAST_OUT"; then
  pass "live sweep reports a non-empty scanned count per glob set"
else
  fail "live sweep reports a non-empty scanned count per glob set" "${LAST_OUT:0:400}"
fi

echo
echo "Total: $TOTAL  Passed: $PASS  Failed: $FAIL"
[[ "$FAIL" -eq 0 ]]
