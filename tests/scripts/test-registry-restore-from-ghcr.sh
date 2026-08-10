#!/usr/bin/env bash
# Test suite for scripts/registry-restore-from-ghcr.sh (#7277).
#
# WHAT THIS SUITE IS FOR. The engine under test is the thing that re-materialises production's
# entire image set into an empty registry after the registry-luks-recut has destroyed the only
# copy. A false GREEN here authorises an irreversible destroy against a restore that does not
# work. So the suite's contract is the same one the D10 gate's suite carries, in both directions:
#
#   1. prove the engine CAN fail, once per enumerated exit code (2/3/4/5/6); and
#   2. prove it CAN succeed (the green row) — the criterion whose absence let an unpassable gate
#      ship with 23 green assertions in the sibling suite.
#
# ANTI-VACUITY MEASURES, each here because the shape it guards against is cheap to write by
# accident and passes on the first run:
#
#   * The `crane` stub DISPATCHES ON ARGV and `exit 64`s when a required flag is absent, so a
#     stub that ignored its arguments — and therefore validated nothing about which refs the
#     engine actually asks for — cannot pass.
#   * Fixtures are keyed PER REF on disk, so an engine that processed only the first entry and
#     broke out of the loop is detectable (the later entries' fixtures go unconsumed).
#   * Every predicate greps a FILE directly. Never `producer | grep -q`: under `set -o pipefail`
#     an early match closes the pipe, the producer takes SIGPIPE (141), and the pipeline reports
#     non-zero even though grep matched — which fails OPEN on every negative assertion.
#   * Harness setup failures ABORT (exit 2) rather than degrading into a confident wrong verdict
#     about the engine.
#
# TMPDIR: scripts/test-all.sh and run-registered-suites.sh both default TMPDIR=/var/tmp, but a
# DIRECT invocation of this file — the documented inner loop while editing the engine — inherits
# the bare machine-global /tmp tmpfs, where a sibling worktree's run can starve it mid-suite.
export TMPDIR="${TMPDIR:-/var/tmp}"

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${DIR}/../.." && pwd)"
ENGINE="${ROOT}/scripts/registry-restore-from-ghcr.sh"

TMP="$(mktemp -d)" || { echo "harness: mktemp -d failed — refusing to report a verdict" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

passes=0
fails=0
pass() { passes=$((passes + 1)); printf '  ok   %s\n' "$1"; }
fail() {
  fails=$((fails + 1))
  printf '  FAIL %s\n' "$1"; printf '       rc=%s\n' "${2:-?}"; printf '       out=%s\n' "${3:-}"
}

# ── fixtures ────────────────────────────────────────────────────────────────────────────────
D1="sha256:1111111111111111111111111111111111111111111111111111111111111111"
D2="sha256:2222222222222222222222222222222222222222222222222222222222222222"
D_OTHER="sha256:9999999999999999999999999999999999999999999999999999999999999999"

WP="jikig-ai/soleur-web-platform"
IB="jikig-ai/soleur-inngest-bootstrap"
IC="jikig-ai/soleur-inngest-config"

# write_manifest <file> — the A0 pin set the PREPARE step hands to the engine.
# `conditional` entries do NOT count toward the floor: soleur-inngest-config is not published at
# GHCR (measured), so counting it would abort forever on a repo that does not exist — the new
# deadlock this whole change exists to avoid.
write_manifest() {
  cat > "$1" <<EOF
{
  "floor": 2,
  "entries": [
    { "repo": "${WP}", "tag": "v0.249.4", "disposition": "required" },
    { "repo": "${IB}", "tag": "v1.1.24",  "disposition": "required" },
    { "repo": "${IC}", "tag": "latest",   "disposition": "conditional" }
  ]
}
EOF
  [[ -s "$1" ]] || { echo "harness: could not write manifest $1" >&2; exit 2; }
}

# key <ref> — filesystem-safe fixture key.
key() { printf '%s' "$1" | tr '/:@' '___'; }

# fixture <dir> <ref> <rc> <stdout> [stderr]
fixture() {
  local d="$1" k; k="$(key "$2")"
  mkdir -p "$d" || { echo "harness: mkdir $d failed" >&2; exit 2; }
  printf '%s' "$3" > "$d/$k.rc"
  printf '%s' "${4:-}" > "$d/$k.out"
  printf '%s' "${5:-}" > "$d/$k.err"
}

# ── OCI manifest fixtures (SYNTHESIZED — never captured from a production artifact). ─────────
# Digests are hand-written and structurally valid (64 hex) but correspond to no real content.
D_AMD64="sha256:a11a11a11a11a11a11a11a11a11a11a11a11a11a11a11a11a11a11a11a11a11a"
D_ATT="sha256:b22b22b22b22b22b22b22b22b22b22b22b22b22b22b22b22b22b22b22b22b22b"
D_ATT_CFG="sha256:c33c33c33c33c33c33c33c33c33c33c33c33c33c33c33c33c33c33c33c33c33c"
D_ATT_LAYER="sha256:d44d44d44d44d44d44d44d44d44d44d44d44d44d44d44d44d44d44d44d44d44d"

# fx_oci_single <dir> <ref> — a NON-index manifest. This is what `soleur-inngest-bootstrap`
# actually is (plain `docker build` -> docker-schema2, no attestations), and it is the shape the
# unchanged code path must keep handling with exactly one `crane validate --remote`.
fx_oci_single() {
  fixture "$1" "manifest:$2" 0 '{
  "schemaVersion": 2,
  "mediaType": "application/vnd.oci.image.manifest.v1+json",
  "config": { "mediaType": "application/vnd.oci.image.config.v1+json", "digest": "'"$D_ATT_CFG"'", "size": 167 },
  "layers": [ { "mediaType": "application/vnd.oci.image.layer.v1.tar+gzip", "digest": "'"$D_AMD64"'", "size": 4096 } ]
}'
}

# fx_oci_index <dir> <ref> [signals] — the PRODUCTION shape: a buildx OCI index carrying one real
# platform child plus one attestation child. The attestation child is what `crane validate` tries
# to gunzip; its layer mediaType is `application/vnd.in-toto+json`, which is never compressed.
#
# `signals` selects WHICH attestation marker the child carries, and it exists because a fixture
# that sets BOTH makes each one individually dead weight — dropping either disjunct from the
# engine left the whole suite green. Worse, the both-signals shape hid a live bug: with only
# `arch`, jq emits `digest<TAB><TAB>unknown`, bash collapses the tab run (tab is IFS-whitespace),
# and the arch value landed in the TYPE field — so the `arch == "unknown"` arm was unreachable
# exactly when it was the only marker, and the in-toto child went to `crane validate`.
#   both  (default) — annotation + platform.architecture:unknown
#   arch            — platform ONLY, no annotations key at all
#   annot           — annotation ONLY, no platform key at all
fx_oci_index() {
  local d="$1" ref="$2" signals="${3:-both}" att_extra=""
  case "$signals" in
    both)  att_extra='"annotations": { "vnd.docker.reference.digest": "'"$D_AMD64"'", "vnd.docker.reference.type": "attestation-manifest" },
      "platform": { "architecture": "unknown", "os": "unknown" }' ;;
    arch)  att_extra='"platform": { "architecture": "unknown", "os": "unknown" }' ;;
    annot) att_extra='"annotations": { "vnd.docker.reference.digest": "'"$D_AMD64"'", "vnd.docker.reference.type": "attestation-manifest" }' ;;
    *) echo "harness: unknown fx_oci_index signals '$signals'" >&2; exit 2 ;;
  esac
  fixture "$d" "manifest:$ref" 0 '{
  "schemaVersion": 2,
  "mediaType": "application/vnd.oci.image.index.v1+json",
  "manifests": [
    {
      "mediaType": "application/vnd.oci.image.manifest.v1+json",
      "digest": "'"$D_AMD64"'",
      "size": 5070,
      "platform": { "architecture": "amd64", "os": "linux" }
    },
    {
      "mediaType": "application/vnd.oci.image.manifest.v1+json",
      "digest": "'"$D_ATT"'",
      "size": 566,
      '"$att_extra"'
    }
  ]
}'
}

# fx_oci_signature <dir> <sink-repo> <sig-tag> — a cosign signature manifest at its referrers tag.
# Its layer is `application/vnd.dev.cosign.simplesigning.v1+json` — plain JSON, never gzipped,
# exactly like the in-toto attestation layer. Handing THIS to `crane validate` would reproduce
# #7378 on the signature path, which is why verification 3 blob-verifies instead.
D_SIG_CFG="sha256:e55e55e55e55e55e55e55e55e55e55e55e55e55e55e55e55e55e55e55e55e55e"
D_SIG_LAYER="sha256:f66f66f66f66f66f66f66f66f66f66f66f66f66f66f66f66f66f66f66f66f66f"
fx_oci_signature() {
  fixture "$1" "manifest:$2@$D_OTHER" 0 '{
  "schemaVersion": 2,
  "mediaType": "application/vnd.oci.image.manifest.v1+json",
  "config": { "mediaType": "application/vnd.oci.image.config.v1+json", "digest": "'"$D_SIG_CFG"'", "size": 233 },
  "layers": [
    { "mediaType": "application/vnd.dev.cosign.simplesigning.v1+json", "digest": "'"$D_SIG_LAYER"'", "size": 251 }
  ]
}'
  fixture "$1" "blob:$2@$D_SIG_CFG"   0 ""
  fixture "$1" "blob:$2@$D_SIG_LAYER" 0 ""
}

# fx_oci_signature_index <dir> <sink-repo> <sig-tag> — THE SHAPE PRODUCTION ACTUALLY HAS.
#
# Measured at GHCR 2026-08-10 against soleur-web-platform:v0.249.4: the referrers tag
# `sha256-<hex>` resolves to an OCI image INDEX (no `.config`, no `.layers`) whose single child
# carries `artifactType: application/vnd.dev.sigstore.bundle.v0.3+json`; that child has an EMPTY
# config (`application/vnd.oci.empty.v1+json`, the well-known
# sha256:44136fa3…aff8a) and one bundle layer. Both child blobs fetch clean.
#
# fx_oci_signature above models the LEGACY simplesigning shape. Keeping both is the point: the
# legacy fixture alone is what let a config+layers-only enumeration ship green and then fail-closed
# on the live artifact, refusing the recut on run 31392395980. Neither fixture may be deleted in
# favour of the other — they are different disjuncts of the same predicate.
D_SIGX_CHILD="sha256:38dc44fe9378484bf59a6ee46ad89788bd66e36bf701942a78ebc2e19fbbd56e"
D_SIGX_CFG="sha256:44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a"
D_SIGX_BUNDLE="sha256:dd39b712b03ad1d2eb9e700ca6cdd9f8f28178c85c052a0aa1b2994f6313473e"
fx_oci_signature_index() { # <dir> <sink-repo> <sig-tag> [subject-digest]
  local _subj="${4:-$D1}"
  fixture "$1" "manifest:$2@$D_OTHER" 0 '{
  "schemaVersion": 2,
  "mediaType": "application/vnd.oci.image.index.v1+json",
  "manifests": [
    { "mediaType": "application/vnd.oci.image.manifest.v1+json", "size": 876, "digest": "'"$D_SIGX_CHILD"'", "artifactType": "application/vnd.dev.sigstore.bundle.v0.3+json" }
  ]
}'
  fixture "$1" "manifest:$2@$D_SIGX_CHILD" 0 '{
  "schemaVersion": 2,
  "mediaType": "application/vnd.oci.image.manifest.v1+json",
  "artifactType": "application/vnd.dev.sigstore.bundle.v0.3+json",
  "subject": { "mediaType": "application/vnd.oci.image.index.v1+json", "size": 856, "digest": "'"$_subj"'" },
  "config": { "mediaType": "application/vnd.oci.empty.v1+json", "digest": "'"$D_SIGX_CFG"'", "size": 2 },
  "layers": [
    { "mediaType": "application/vnd.dev.sigstore.bundle.v0.3+json", "digest": "'"$D_SIGX_BUNDLE"'", "size": 10559 }
  ]
}'
  fixture "$1" "blob:$2@$D_SIGX_CFG"    0 ""
  fixture "$1" "blob:$2@$D_SIGX_BUNDLE" 0 ""
}

# fx_oci_raw <dir> <ref> <json> — an arbitrary sink manifest payload, for the degenerate shapes
# (nested index child, attestation-only index, child with no digest, non-array .manifests).
fx_oci_raw() { fixture "$1" "manifest:$2" 0 "$3"; }

# fx_oci_attestation <dir> <repo> — the attestation child's own manifest, read to enumerate the
# blobs whose PRESENCE (not decompressibility) the engine must verify.
fx_oci_attestation() {
  fixture "$1" "manifest:$2@$D_ATT" 0 '{
  "schemaVersion": 2,
  "mediaType": "application/vnd.oci.image.manifest.v1+json",
  "config": { "mediaType": "application/vnd.oci.image.config.v1+json", "digest": "'"$D_ATT_CFG"'", "size": 167 },
  "layers": [
    {
      "mediaType": "application/vnd.in-toto+json",
      "digest": "'"$D_ATT_LAYER"'",
      "size": 140872,
      "annotations": { "in-toto.io/predicate-type": "https://slsa.dev/provenance/v1" }
    }
  ]
}'
}

# make_crane <path> <fixture-dir> — an argv-dispatching `crane` stub.
#
# It refuses (exit 64) on a call shape the engine must never emit, so the suite pins the CALL
# SHAPE and not merely the outcome. `validate` deliberately has NO default fixture: an engine
# that skipped blob validation would hit the missing-fixture arm and fail loudly rather than
# inheriting a permissive default.
make_crane() {
  local f="$1" fx="$2"
  cat > "$f" <<'STUB'
#!/usr/bin/env bash
# argv-dispatching crane stub. FX and CALLS are injected by the harness.
printf '%s\n' "$*" >> "$CALLS"
sub="${1:-}"; shift || true
# `auth login` is real behaviour now, not ceremony: the engine authenticates before its first
# copy. It used to validate the credentials non-empty and never present them, so every push went
# out anonymously — a guaranteed 401 against a defaultPolicy:[] sink. Fail the login when the
# harness passes the sentinel, so the credential path has a negative control.
if [[ "$sub" == "auth" ]]; then
  [[ "${1:-}" == "login" ]] || { echo "stub: only 'crane auth login' is expected" >&2; exit 64; }
  shift
  host="${1:-}"; shift || true
  u=""; pw=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -u) u="${2:-}"; shift 2 ;;
      -p) pw="${2:-}"; shift 2 ;;
      --insecure) shift ;;
      *) shift ;;
    esac
  done
  [[ -n "$host" && -n "$u" && -n "$pw" ]] || { echo "stub: 'crane auth login' needs a host, -u and -p" >&2; exit 64; }
  [[ "$pw" == "REJECT_ME" ]] && { echo "Error: UNAUTHORIZED: authentication required" >&2; exit 1; }
  exit 0
fi
# The sink is plain HTTP on loopback in both modes, so crane must be told so. Strip the flag
# here, then assert it was PRESENT for every loopback-directed call in the prologue below.
# (This comment used to promise an assertion "further down" that did not exist for any
# subcommand; the prologue check is what makes it true.)
args=(); saw_insecure=0
for a in "$@"; do
  if [[ "$a" == "--insecure" ]]; then saw_insecure=1; else args+=("$a"); fi
done
set -- "${args[@]}"
# Assert the flag ONCE, in the prologue, for EVERY subcommand — mirroring the engine's own rule
# (loopback sink => plain HTTP => --insecure required; anything else => TLS => absent).
# Per-arm checks were the wrong shape: with `digest`, `copy` and `validate` unasserted, dropping
# --insecure from any single call site was satisfied by a SIBLING call site that still had it, so
# each mutation survived 70/0 while production would attempt TLS against a plain-HTTP sink.
for a in "$@"; do
  case "$a" in
    127.0.0.1:*|localhost:*|\[::1\]:*)
      [[ "$saw_insecure" == 1 ]] || { echo "stub: loopback-sink '$sub' needs --insecure, got: $*" >&2; exit 64; }
      break ;;
  esac
done
key() { printf '%s' "$1" | tr '/:@' '___'; }
emit() { # $1 = ref, $2 = what-kind (for the missing-fixture message)
  local k; k="$(key "$1")"
  if [[ ! -f "$FX/$k.rc" ]]; then
    echo "stub: NO FIXTURE for $2 '$1' — the engine asked for a ref this case did not set up" >&2
    exit 70
  fi
  [[ -s "$FX/$k.out" ]] && cat "$FX/$k.out"
  [[ -s "$FX/$k.err" ]] && cat "$FX/$k.err" >&2
  exit "$(cat "$FX/$k.rc")"
}
case "$sub" in
  digest)
    ref="${1:-}"
    [[ -n "$ref" ]] || { echo "stub: 'crane digest' with no ref" >&2; exit 64; }
    emit "$ref" digest
    ;;
  copy)
    src="${1:-}"; dst="${2:-}"
    [[ -n "$src" && -n "$dst" ]] || { echo "stub: 'crane copy' needs src and dst" >&2; exit 64; }
    # A copy FROM the sink or TO ghcr.io is backwards and must never be emitted.
    case "$src" in ghcr.io/*) ;; *) echo "stub: copy source '$src' is not a ghcr.io ref" >&2; exit 64 ;; esac
    case "$dst" in ghcr.io/*) echo "stub: copy destination '$dst' must not be ghcr.io" >&2; exit 64 ;; esac
    # Keyed `copy:<dst>`, NOT bare `<dst>`. Sharing a key with the digest read makes "the copy
    # succeeded but the read-back failed" unfixturable — and that is precisely the state the
    # engine's read-back assertions exist to catch, so a shared key silently converts every
    # read-back test into a copy test. Found by mutation testing: deleting the sink-side
    # signature read-back survived a suite that appeared to cover it.
    emit "copy:$dst" copy
    ;;
  validate)
    # Must be --remote (a tarball validate would prove nothing about the sink).
    seen_remote=""; ref=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --remote) seen_remote=1; ref="${2:-}"; shift 2 ;;
        --fast) echo "stub: --fast skips layers and cannot prove blob completeness" >&2; exit 64 ;;
        *) shift ;;
      esac
    done
    [[ -n "$seen_remote" && -n "$ref" ]] || { echo "stub: 'crane validate' must be --remote <ref>" >&2; exit 64; }
    emit "validate:$ref" validate
    ;;
  manifest)
    # Index enumeration. Keyed `manifest:<ref>` and given NO permissive default — same discipline
    # as `validate`. A default would let an engine that skipped enumeration inherit a benign
    # single-manifest answer and silently stop verifying attestation children.
    ref="${1:-}"
    [[ -n "$ref" ]] || { echo "stub: 'crane manifest' with no ref" >&2; exit 64; }
    # Mirror the engine's OWN rule: --insecure is required for a LOOPBACK sink (plain HTTP) and
    # must be absent otherwise. Requiring it for every non-ghcr ref would wrongly demand it of a
    # non-loopback sink, which the suite separately asserts must stay on TLS.
    emit "manifest:$ref" manifest
    ;;
  blob)
    # Attestation-child blob presence. Must be a DIGEST ref: a tag would not pin the blob the
    # index actually references, so a tag here is a bug in the engine, not a fixture gap.
    ref="${1:-}"
    [[ -n "$ref" ]] || { echo "stub: 'crane blob' with no ref" >&2; exit 64; }
    case "$ref" in *@sha256:*) ;; *) echo "stub: 'crane blob' must take a digest ref, got '$ref'" >&2; exit 64 ;; esac
    emit "blob:$ref" blob
    ;;
  *)
    echo "stub: unexpected crane subcommand '$sub'" >&2; exit 64 ;;
esac
STUB
  chmod +x "$f" || { echo "harness: chmod $f failed" >&2; exit 2; }
  printf '%s' "$fx" > "$f.fxdir"
}

# run_engine <fixture-dir> <calls-file> [extra args...] — always supplies a valid credential
# environment unless the caller overrode it.
run_engine() {
  local fx="$1" calls="$2"; shift 2
  FX="$fx" CALLS="$calls" \
  ZOT_PUSH_USER="${ZOT_PUSH_USER-probeuser}" ZOT_PUSH_TOKEN="${ZOT_PUSH_TOKEN-probepass}" \
  REGISTRY_RESTORE_CRANE_CMD="$CRANE_STUB" \
    bash "$ENGINE" "$@" 2>&1
}

# ok_fixtures <dir> <target> — the all-good world: both required refs resolve, copy, read back
# with matching digests, validate clean, and carry a signature tag.
ok_fixtures() {
  local fx="$1" t="$2"
  fixture "$fx" "ghcr.io/${WP}:v0.249.4" 0 "$D1"
  fixture "$fx" "ghcr.io/${IB}:v1.1.24"  0 "$D2"
  fixture "$fx" "copy:${t}/${WP}:v0.249.4" 0 ""
  fixture "$fx" "copy:${t}/${IB}:v1.1.24"  0 ""
  fixture "$fx" "${t}/${WP}:v0.249.4"    0 "$D1"
  fixture "$fx" "${t}/${IB}:v1.1.24"     0 "$D2"
  # Both refs are NON-index in the baseline world, so verification 2 keeps its pre-existing
  # shape: one `crane validate --remote` per ref and zero `crane blob` calls.
  # Keyed by DIGEST, not tag: the engine reads the sink manifest as `<repo>@<digest>` so crane
  # byte-verifies it (a tag ref is not digest-checked by go-containerregistry).
  fx_oci_single "$fx" "${t}/${WP}@${D1}"
  fx_oci_single "$fx" "${t}/${IB}@${D2}"
  fixture "$fx" "validate:${t}/${WP}@${D1}" 0 "PASS"
  fixture "$fx" "validate:${t}/${IB}@${D2}"  0 "PASS"
  # signature tags (sha256-<hex>, the OCI referrers tag scheme GHCR actually uses)
  fixture "$fx" "ghcr.io/${WP}:sha256-${D1#sha256:}" 0 "$D_OTHER"
  fixture "$fx" "ghcr.io/${IB}:sha256-${D2#sha256:}" 0 "$D_OTHER"
  fixture "$fx" "copy:${t}/${WP}:sha256-${D1#sha256:}" 0 ""
  fixture "$fx" "copy:${t}/${IB}:sha256-${D2#sha256:}" 0 ""
  fixture "$fx" "${t}/${WP}:sha256-${D1#sha256:}"    0 "$D_OTHER"
  fixture "$fx" "${t}/${IB}:sha256-${D2#sha256:}"    0 "$D_OTHER"
  # The signature's own manifest + payload blobs at the sink. `crane digest` above proves only
  # that the signature MANIFEST resolves; zot gc can evict its payload blob while the manifest
  # survives, and that blob is what ci-deploy.sh fetches to run cosign verify.
  fx_oci_signature "$fx" "${t}/${WP}" "sha256-${D1#sha256:}"
  fx_oci_signature "$fx" "${t}/${IB}" "sha256-${D2#sha256:}"
  # the conditional entry is genuinely absent at GHCR (measured 2026-08-05)
  fixture "$fx" "ghcr.io/${IC}:latest" 1 "" \
    "Error: GET https://ghcr.io/v2/${IC}/manifests/latest: MANIFEST_UNKNOWN: manifest unknown"
}

TARGET="127.0.0.1:5555"
MANIFEST="$TMP/pins.json"; write_manifest "$MANIFEST"
CRANE_STUB="$TMP/crane"; make_crane "$CRANE_STUB" "$TMP/unused"

printf '\n=== registry-restore-from-ghcr ===\n\n'

if [[ ! -f "$ENGINE" ]]; then
  printf '  FAIL the engine does not exist at %s\n' "$ENGINE"
  printf '\n=== 0 passed, 1 failed ===\n\n'
  exit 1
fi

# ── THE GREEN ROW. Asserted first, deliberately. ─────────────────────────────────────────────
fx="$TMP/fx-ok"; calls="$TMP/calls-ok"; : > "$calls"
ok_fixtures "$fx" "$TARGET"
out="$(run_engine "$fx" "$calls" --target "$TARGET" --tags-from "$MANIFEST")"; rc=$?
if [[ "$rc" -eq 0 ]]; then
  pass "all-good fixture => rc 0 (THE green row: the engine can succeed)"
else
  fail "the all-good fixture must exit 0" "$rc" "$out"
fi

grep -qF "restore_summary" "$calls" 2>/dev/null # (calls file holds crane argv, not the summary)
if printf '%s' "$out" | grep -qF "restored=2"; then
  pass "the machine-readable summary reports restored=2 (the required floor)"
else
  fail "summary must report restored=2" "$rc" "$out"
fi

# The conditional entry must be a DECLARED SKIP, not a silent omission and not an abort.
if printf '%s' "$out" | grep -qF "skipped=1"; then
  pass "the conditional entry absent at GHCR is a declared skip, not an abort"
else
  fail "an absent conditional entry must record a declared skip" "$rc" "$out"
fi

# ── The anti-fail-open assertion: blobs, not just manifests. ─────────────────────────────────
# 0.9 measured `crane digest` returning rc=0 PASS on an image whose layer blob was evicted. An
# engine that verified with digest alone would certify an unusable restore.
if grep -qE '^validate .*--remote ' "$calls"; then
  pass "verification calls 'crane validate --remote' (blobs), not digest alone"
else
  fail "the engine must verify blob completeness with crane validate --remote" "$rc" "$(cat "$calls")"
fi

n_validate=$(grep -cE '^validate .*--remote ' "$calls" || true)
if [[ "$n_validate" -eq 2 ]]; then
  pass "every required reference is blob-validated (2 of 2), not just the first"
else
  fail "expected 2 validate calls, got $n_validate — an early break would show as 1" "?" "$(cat "$calls")"
fi

# Signature presence per restored digest (Phase 0.3: copy the sha256-<hex> tag; nothing re-signs).
if grep -qF "sha256-${D1#sha256:}" "$calls" && grep -qF "sha256-${D2#sha256:}" "$calls"; then
  pass "a signature tag is copied for each restored digest"
else
  fail "each restored digest needs its sha256-<hex> signature tag copied" "?" "$(cat "$calls")"
fi

# ── AUTHENTICATION — the check that used to be decorative. ──────────────────────────────────
# ZOT_PUSH_USER/ZOT_PUSH_TOKEN were validated non-empty and then never presented to crane, which
# reads only the Docker keychain. Every push therefore went out ANONYMOUSLY, which against a
# defaultPolicy:[] sink is a guaranteed 401 -> exit 5 — a gate that could never pass. Caught by
# three independent reviewers; no stub exercised a real auth path.
if grep -qE '^auth login ' "$calls"; then
  pass "the engine AUTHENTICATES to the sink before copying (the credential check is load-bearing)"
else
  fail "the engine must present ZOT_PUSH_* to crane, not merely check they are non-empty" "?" \
    "$(cat "$calls")"
fi

# The sink is plain HTTP on loopback in both modes (the throwaway listens directly; the real
# target is cloudflared on 127.0.0.1). crane defaults to HTTPS for a host:port, so every
# sink-directed call needs --insecure. The stubs hid this by never speaking a real protocol.
if grep -qE '^copy --insecure ' "$calls" && grep -qE '^validate --insecure ' "$calls"; then
  pass "sink-directed calls carry --insecure (crane would otherwise attempt TLS to loopback)"
else
  fail "copy/validate against a loopback sink must pass --insecure" "?" "$(cat "$calls")"
fi

# A rejected login must exit 5 BEFORE any copy — an authorisation failure is not retryable.
fx="$TMP/fx-badlogin"; calls="$TMP/calls-badlogin"; : > "$calls"
ok_fixtures "$fx" "$TARGET"
out="$(ZOT_PUSH_TOKEN="REJECT_ME" run_engine "$fx" "$calls" --target "$TARGET" --tags-from "$MANIFEST")"; rc=$?
if [[ "$rc" -eq 5 ]] && ! grep -qE '^copy ' "$calls"; then
  pass "a REJECTED sink login => exit 5 before any copy is attempted"
else
  fail "a rejected login must exit 5 and copy nothing" "$rc" "$out ||| $(cat "$calls")"
fi

# ── Idempotence: a second pass over an already-restored target is a clean no-op. ─────────────
# This is what makes a timed-out or cancelled restore recoverable by re-running rather than by
# recovering state — the property Phase 3 leans on when it retries on exit 3.
calls2="$TMP/calls-ok2"; : > "$calls2"
out2="$(run_engine "$fx" "$calls2" --target "$TARGET" --tags-from "$MANIFEST")"; rc2=$?
if [[ "$rc2" -eq 0 ]]; then
  pass "second pass over an already-restored target => rc 0 (resumable by contract)"
else
  fail "the engine must be safely re-runnable" "$rc2" "$out2"
fi

# ── Exit code 2 — source unavailable. ────────────────────────────────────────────────────────
fx="$TMP/fx-src404"; calls="$TMP/calls-src404"; : > "$calls"
ok_fixtures "$fx" "$TARGET"
fixture "$fx" "ghcr.io/${WP}:v0.249.4" 1 "" \
  "Error: GET https://ghcr.io/v2/${WP}/manifests/v0.249.4: MANIFEST_UNKNOWN: manifest unknown"
out="$(run_engine "$fx" "$calls" --target "$TARGET" --tags-from "$MANIFEST")"; rc=$?
if [[ "$rc" -eq 2 ]]; then
  pass "required source ref absent => exit 2 (source unavailable)"
else
  fail "an absent required source must exit 2" "$rc" "$out"
fi

# The message may not claim the image is GONE. Measured 2026-08-05: GHCR masks a repo that exists
# but is not visible to the credential as MANIFEST_UNKNOWN, identical to genuinely-absent — so
# "absent" would name a cause the engine did not measure.
if printf '%s' "$out" | grep -qiE 'not visible|not readable by|credential'; then
  pass "the NOTFOUND message admits 'absent OR not visible to this credential'"
else
  fail "NOTFOUND must not assert the image is gone (GHCR masks permission as MANIFEST_UNKNOWN)" "$rc" "$out"
fi

fx="$TMP/fx-dns"; calls="$TMP/calls-dns"; : > "$calls"
ok_fixtures "$fx" "$TARGET"
fixture "$fx" "ghcr.io/${WP}:v0.249.4" 1 "" \
  'Error: Get "https://ghcr.io/v2/": dial tcp: lookup ghcr.io: no such host'
out="$(run_engine "$fx" "$calls" --target "$TARGET" --tags-from "$MANIFEST")"; rc=$?
if [[ "$rc" -eq 2 ]]; then
  pass "source DNS failure => exit 2, classified NETWORK not NOTFOUND"
else
  fail "a source network failure must exit 2" "$rc" "$out"
fi

# ── Exit code 3 — sink unavailable. ──────────────────────────────────────────────────────────
# This is the code Phase 3 retries on, because a host replace can outrun the Cloudflare Tunnel's
# re-convergence onto the new origin.
fx="$TMP/fx-sink"; calls="$TMP/calls-sink"; : > "$calls"
ok_fixtures "$fx" "$TARGET"
fixture "$fx" "copy:${TARGET}/${WP}:v0.249.4" 1 "" \
  'Error: Patch "http://127.0.0.1:5000/v2/'"${WP}"'/blobs/uploads/": write: connection reset by peer'
out="$(run_engine "$fx" "$calls" --target "$TARGET" --tags-from "$MANIFEST")"; rc=$?
if [[ "$rc" -eq 3 ]]; then
  pass "sink write reset mid-upload => exit 3 (sink unavailable, the retryable code)"
else
  fail "a sink availability failure must exit 3" "$rc" "$out"
fi

# ── THE ABORT/DEGRADE BOUNDARY, pinned in both directions. ──────────────────────────────────
# This is the most dangerous line in the design. A sink that RESETS mid-upload is an availability
# failure and is retryable (exit 3, asserted above) — it is the literal signature of the incident
# this whole change exists to recover from, so classifying it as fatal would re-create the
# deadlock. A sink that REJECTS THE CREDENTIAL is an authorisation failure: retrying it only
# burns the empty-store window, so it must NOT share the retryable code.
fx="$TMP/fx-sinkauth"; calls="$TMP/calls-sinkauth"; : > "$calls"
ok_fixtures "$fx" "$TARGET"
fixture "$fx" "copy:${TARGET}/${WP}:v0.249.4" 1 "" \
  "Error: PUT http://${TARGET}/v2/${WP}/manifests/v0.249.4: DENIED: permission denied"
out="$(run_engine "$fx" "$calls" --target "$TARGET" --tags-from "$MANIFEST")"; rc=$?
if [[ "$rc" -eq 5 ]]; then
  pass "sink REJECTS the credential => exit 5, NOT the retryable 3 (authorisation != availability)"
else
  fail "a rejected sink credential must exit 5; retrying an auth failure wastes the window" "$rc" "$out"
fi

# ── Exit code 4 — verification mismatch, in BOTH of its shapes. ──────────────────────────────
fx="$TMP/fx-mismatch"; calls="$TMP/calls-mismatch"; : > "$calls"
ok_fixtures "$fx" "$TARGET"
fixture "$fx" "${TARGET}/${WP}:v0.249.4" 0 "$D_OTHER"   # copied, but landed a different digest
out="$(run_engine "$fx" "$calls" --target "$TARGET" --tags-from "$MANIFEST")"; rc=$?
if [[ "$rc" -eq 4 ]]; then
  pass "digest parity mismatch => exit 4 (verification mismatch)"
else
  fail "a digest mismatch must exit 4" "$rc" "$out"
fi

fx="$TMP/fx-blob"; calls="$TMP/calls-blob"; : > "$calls"
ok_fixtures "$fx" "$TARGET"
fixture "$fx" "validate:${TARGET}/${WP}@${D1}" 1 "" \
  "Error: validating config: GET http://${TARGET}/v2/${WP}/blobs/sha256:dead: BLOB_UNKNOWN: blob unknown to registry"
out="$(run_engine "$fx" "$calls" --target "$TARGET" --tags-from "$MANIFEST")"; rc=$?
if [[ "$rc" -eq 4 ]]; then
  pass "matching digest but MISSING BLOB => exit 4 (the digest-only fail-open, closed)"
else
  fail "blob-incomplete restore must exit 4 even when digests match" "$rc" "$out"
fi

# A signature that copies "successfully" but is not readable back from the sink leaves the image
# restored UNSIGNED, which fails cosign verify on the host at deploy time. Added after a mutation
# battery: deleting the sink-side signature readback SURVIVED the suite, because every fixture
# had the signature present and no row forced the readback to be the discriminator.
fx="$TMP/fx-sigmissing"; calls="$TMP/calls-sigmissing"; : > "$calls"
ok_fixtures "$fx" "$TARGET"
# The copy REPORTS SUCCESS (rc 0) and the read-back finds nothing — the discriminating shape.
fixture "$fx" "copy:${TARGET}/${WP}:sha256-${D1#sha256:}" 0 ""
fixture "$fx" "${TARGET}/${WP}:sha256-${D1#sha256:}" 1 "" \
  "Error: GET http://${TARGET}/v2/${WP}/manifests/sha256-${D1#sha256:}: MANIFEST_UNKNOWN: manifest unknown"
out="$(run_engine "$fx" "$calls" --target "$TARGET" --tags-from "$MANIFEST")"; rc=$?
if [[ "$rc" -eq 4 ]] && printf '%s' "$out" | grep -qiF "restored UNSIGNED"; then
  pass "signature copy reports ok but read-back is empty => exit 4 (no silent unsigned restore)"
else
  fail "an unverifiable sink-side signature must exit 4 naming the unsigned state" "$rc" "$out"
fi

# The signature absent AT THE SOURCE is a different arm and needs its own row: without it, a
# mutation deleting the GHCR-side signature check survives, because the copy of a nonexistent
# signature would be the thing that failed instead.
fx="$TMP/fx-sigsrc"; calls="$TMP/calls-sigsrc"; : > "$calls"
ok_fixtures "$fx" "$TARGET"
fixture "$fx" "ghcr.io/${WP}:sha256-${D1#sha256:}" 1 "" \
  "Error: GET https://ghcr.io/v2/${WP}/manifests/sha256-${D1#sha256:}: MANIFEST_UNKNOWN: manifest unknown"
out="$(run_engine "$fx" "$calls" --target "$TARGET" --tags-from "$MANIFEST")"; rc=$?
if [[ "$rc" -eq 4 ]] && printf '%s' "$out" | grep -qiF "no unsigned-restore arm"; then
  pass "no signature at GHCR => exit 4 (there is no unsigned-restore arm)"
else
  fail "a missing source signature must exit 4, not warn" "$rc" "$out"
fi

# ── The floor must not be satisfiable by DUPLICATION. ────────────────────────────────────────
# Found by mutation testing: counting is only a non-vacuity guard if the counted things differ.
DUP_MANIFEST="$TMP/pins-dup.json"
cat > "$DUP_MANIFEST" <<EOF
{ "floor": 2, "entries": [
  { "repo": "${WP}", "tag": "v0.249.4", "disposition": "required" },
  { "repo": "${WP}", "tag": "v0.249.4", "disposition": "required" }
] }
EOF
fx="$TMP/fx-dup"; calls="$TMP/calls-dup"; : > "$calls"
ok_fixtures "$fx" "$TARGET"
out="$(run_engine "$fx" "$calls" --target "$TARGET" --tags-from "$DUP_MANIFEST")"; rc=$?
if [[ "$rc" -ne 0 ]] && printf '%s' "$out" | grep -qiE 'distinct|duplicat'; then
  pass "a duplicated required entry cannot satisfy the floor"
else
  fail "duplicate required entries must be rejected by name" "$rc" "$out"
fi

# ── Exit code 5 — credential unreadable. ─────────────────────────────────────────────────────
fx="$TMP/fx-cred"; calls="$TMP/calls-cred"; : > "$calls"
ok_fixtures "$fx" "$TARGET"
out="$(ZOT_PUSH_TOKEN="" run_engine "$fx" "$calls" --target "$TARGET" --tags-from "$MANIFEST")"; rc=$?
if [[ "$rc" -eq 5 ]]; then
  pass "empty ZOT_PUSH_TOKEN => exit 5 (credential unusable)"
else
  fail "a missing sink token must exit 5" "$rc" "$out"
fi

# BOTH credential variables need their own row. With only the token row, a mutation deleting the
# user check survives — the token guard fires first and masks it.
out="$(ZOT_PUSH_USER="" run_engine "$fx" "$calls" --target "$TARGET" --tags-from "$MANIFEST")"; rc=$?
if [[ "$rc" -eq 5 ]] && printf '%s' "$out" | grep -qF "ZOT_PUSH_USER"; then
  pass "empty ZOT_PUSH_USER => exit 5, named separately from the token"
else
  fail "a missing sink user must exit 5 and name ZOT_PUSH_USER" "$rc" "$out"
fi

# An empty credential must be caught BEFORE any network call — otherwise the engine leaks a
# half-restored state and reports a credential fault.
if [[ ! -s "$calls" ]]; then
  pass "the credential check runs before any crane call (no partial restore)"
else
  fail "credentials must be validated before the first crane invocation" "$rc" "$(cat "$calls")"
fi

# ── Exit code 6 — could-not-classify. ────────────────────────────────────────────────────────
# The default arm. An unclassified failure must never read as either 'absent' or 'fine'.
fx="$TMP/fx-unknown"; calls="$TMP/calls-unknown"; : > "$calls"
ok_fixtures "$fx" "$TARGET"
fixture "$fx" "ghcr.io/${WP}:v0.249.4" 1 "" "Error: something nobody has seen before"
out="$(run_engine "$fx" "$calls" --target "$TARGET" --tags-from "$MANIFEST")"; rc=$?
if [[ "$rc" -eq 6 ]]; then
  pass "unrecognised stderr => exit 6 (could-not-classify, never a pass)"
else
  fail "an unclassifiable failure must exit 6" "$rc" "$out"
fi

# ── The non-vacuity floor. ───────────────────────────────────────────────────────────────────
# The single most likely way this engine fails open is an EMPTY inventory: every loop then passes
# and it reports success having restored nothing.
EMPTY_MANIFEST="$TMP/pins-empty.json"
cat > "$EMPTY_MANIFEST" <<'EOF'
{ "floor": 2, "entries": [] }
EOF
fx="$TMP/fx-empty"; calls="$TMP/calls-empty"; : > "$calls"
out="$(run_engine "$fx" "$calls" --target "$TARGET" --tags-from "$EMPTY_MANIFEST")"; rc=$?
# Assert the SPECIFIC guard, not merely a non-zero exit: several guards can reject this manifest,
# and a row that accepts any of them cannot tell which one is still alive.
if [[ "$rc" -ne 0 ]] && printf '%s' "$out" | grep -qiF "ZERO required entries"; then
  pass "empty inventory => rejected BY THE EMPTY-INVENTORY GUARD (named, not incidental)"
else
  fail "an empty inventory must be rejected by its own named guard" "$rc" "$out"
fi

# A manifest whose required count is BELOW its own declared floor is a silently-narrowed restore.
SHORT_MANIFEST="$TMP/pins-short.json"
cat > "$SHORT_MANIFEST" <<EOF
{ "floor": 2, "entries": [ { "repo": "${WP}", "tag": "v0.249.4", "disposition": "required" } ] }
EOF
fx="$TMP/fx-short"; calls="$TMP/calls-short"; : > "$calls"
ok_fixtures "$fx" "$TARGET"
out="$(run_engine "$fx" "$calls" --target "$TARGET" --tags-from "$SHORT_MANIFEST")"; rc=$?
if [[ "$rc" -ne 0 ]]; then
  pass "required count below the declared floor => non-zero (no silent narrowing)"
else
  fail "a below-floor manifest must not report success" "$rc" "$out"
fi

# ── Argument validation. ─────────────────────────────────────────────────────────────────────
fx="$TMP/fx-args"; calls="$TMP/calls-args"; : > "$calls"
out="$(run_engine "$fx" "$calls" --tags-from "$MANIFEST")"; rc=$?
if [[ "$rc" -ne 0 ]] && printf '%s' "$out" | grep -qF -- "--target"; then
  pass "--target is required"
else
  fail "a missing --target must be rejected by name" "$rc" "$out"
fi

out="$(run_engine "$fx" "$calls" --target "$TARGET" --tags-from "$TMP/does-not-exist.json")"; rc=$?
if [[ "$rc" -ne 0 ]]; then
  pass "an unreadable --tags-from manifest is rejected"
else
  fail "a missing manifest must not read as an empty success" "$rc" "$out"
fi

# A target of ghcr.io would make the whole restore a no-op that reports success — it would copy
# GHCR onto itself and verify perfectly, while the registry the recut emptied stayed empty.
#
# Asserting only `rc != 0` here is VACUOUS and was: the crane stub independently refuses a
# ghcr.io copy destination with exit 64, so the engine exited non-zero via the unclassifiable
# arm whether or not its own guard existed — the row passed identically against a mutant with
# the guard deleted. The discriminator is that the engine rejects it ITSELF, by name, BEFORE
# reaching for the network.
calls="$TMP/calls-selftarget"; : > "$calls"
out="$(run_engine "$fx" "$calls" --target "ghcr.io" --tags-from "$MANIFEST")"; rc=$?
if [[ "$rc" -ne 0 ]] && printf '%s' "$out" | grep -qF -- "--target" && [[ ! -s "$calls" ]]; then
  pass "--target ghcr.io rejected by the engine before any crane call (self-copy would verify green)"
else
  fail "the source registry must be rejected by name, before the first crane invocation" "$rc" \
    "$out ||| calls=$(cat "$calls")"
fi

out="$(run_engine "$fx" "$calls" --target "$TARGET" --tags-from "$MANIFEST" --nope)"; rc=$?
if [[ "$rc" -ne 0 ]] && printf '%s' "$out" | grep -qiF "unknown argument"; then
  pass "unknown argument rejected"
else
  fail "an unknown argument must be rejected" "$rc" "$out"
fi

# `--rehearse` was DELETED at Phase 0.3 (nothing signs, so its only defined effect had no
# referent). It must not linger as an accepted no-op that a caller could believe in.
out="$(run_engine "$fx" "$calls" --target "$TARGET" --tags-from "$MANIFEST" --rehearse)"; rc=$?
if [[ "$rc" -ne 0 ]]; then
  pass "--rehearse is not silently accepted (it was deleted, not made a no-op)"
else
  fail "--rehearse must be rejected rather than ignored" "$rc" "$out"
fi

# ── Structural properties of the source. ─────────────────────────────────────────────────────
# AC9: no `docker pull` in any verification path. A local Docker image cache would satisfy a
# docker pull without the sink ever being contacted — the fail-open A2's guard table names.
if grep -qF 'docker pull' "$ENGINE"; then
  fail "AC9: 'docker pull' must not appear in the restore engine" "?" \
    "$(grep -nF 'docker pull' "$ENGINE")"
else
  pass "AC9: no 'docker pull' anywhere in the engine"
fi

# The workflow-command injection guard. Registry stderr is externally-influenced text that gets
# interpolated into `::error::` output; GitHub parses workflow commands per LINE, so a newline
# ── Guards a MUTATION BATTERY found this suite was certifying without testing. ──────────────
# Each row below closes a mutation that survived. They share one shape: deleting the guard still
# produces a NON-ZERO exit — via a later check — so a row asserting only failure cannot see it.
# What actually differs is WHICH EXIT CODE, and here the exit code is operational policy: 3 is
# the retryable arm the workflow re-runs on, 4 and 5 are not. A guard that collapses 3 into 4
# converts a transient tunnel re-convergence into "the registry is NOT fully restored; do not
# treat this run as authorising anything" — after the destroy.

NET_ERR='Error: Get "https://sink/v2/": dial tcp: lookup sink: no such host'

# A value-taking flag with NO value must FAIL, not spin — same class as the gate's. This engine
# runs AFTER the destroy, so a silent hang-then-cancellation there leaves an empty registry and a
# run whose log says nothing about why. `timeout` is the assertion: without the guard this row
# does not fail, it never returns.
for _flag in --target --tags-from; do
  out="$(timeout 10 bash "$ENGINE" "$_flag" 2>&1)"; rc=$?
  if [[ "$rc" -ne 0 && "$rc" -ne 124 ]] && printf '%s' "$out" | grep -qF "requires a value"; then
    pass "argv: ${_flag} with no value => refuses immediately (never spins to a job timeout)"
  else
    fail "a missing flag value must refuse, not hang — rc 124 means it is still spinning" "$rc" "$out"
  fi
done

# last_err must return the last LINE, not the last 400 BYTES. This is the sharpest row in the
# suite, because on the CONDITIONAL entry the two behaviours differ by a silent skip:
# classify() substring-matches, so under a byte-tail the earlier `manifest unknown` wins over the
# whole capture and the entry is recorded "absent, declared skip" — swallowing a credential
# rejection on the inventory that authorises destroying production's only copy. Under a
# line-tail the last line decides and it is DENIED, which aborts.
fx="$TMP/fx-lastline"; calls="$TMP/calls-lastline"; : > "$calls"
ok_fixtures "$fx" "$TARGET"
fixture "$fx" "ghcr.io/${IC}:latest" 1 "" \
  "$(printf 'Error: GET https://ghcr.io/v2/%s/manifests/latest: MANIFEST_UNKNOWN: manifest unknown\nError: GET https://ghcr.io/token: UNAUTHORIZED: authentication required' "$IC")"
out="$(run_engine "$fx" "$calls" --target "$TARGET" --tags-from "$MANIFEST")"; rc=$?
if [[ "$rc" -eq 2 ]] && printf '%s' "$out" | grep -qF "rejected this credential"; then
  pass "last_err: a conditional entry's auth failure ABORTS — never swallowed as a declared skip"
else
  fail "a byte-tail lets an earlier 'manifest unknown' outrank the real verdict and skip silently" "$rc" "$out"
fi

# Read-back failure must stay classified. Without the empty-digest guard the flow falls into the
# parity comparison, where "" != "sha256:…" is a MISMATCH — reporting a corrupt restore (4) for
# what is an unavailable sink (3).
fx="$TMP/fx-readback-net"; calls="$TMP/calls-readback-net"; : > "$calls"
ok_fixtures "$fx" "$TARGET"
fixture "$fx" "${TARGET}/${WP}:v0.249.4" 1 "" "$NET_ERR"
out="$(run_engine "$fx" "$calls" --target "$TARGET" --tags-from "$MANIFEST")"; rc=$?
if [[ "$rc" -eq 3 ]] && printf '%s' "$out" | grep -qF "could not read"; then
  pass "an UNAVAILABLE sink on read-back => exit 3 (retryable), not 4 (corrupt restore)"
else
  fail "an unreadable read-back must classify as availability, not as a digest mismatch" "$rc" "$out"
fi

# Same class, on the signature leg. The signature copy has its own NETWORK arm precisely so a
# tunnel blip during the signature does not read as an unsigned restore.
fx="$TMP/fx-sigcopy-net"; calls="$TMP/calls-sigcopy-net"; : > "$calls"
ok_fixtures "$fx" "$TARGET"
fixture "$fx" "copy:${TARGET}/${WP}:sha256-${D1#sha256:}" 1 "" "$NET_ERR"
out="$(run_engine "$fx" "$calls" --target "$TARGET" --tags-from "$MANIFEST")"; rc=$?
if [[ "$rc" -eq 3 ]] && printf '%s' "$out" | grep -qF "signature"; then
  pass "an UNAVAILABLE sink during the signature copy => exit 3, naming the signature"
else
  fail "a transient failure copying the signature must be retryable, not a permanent verdict" "$rc" "$out"
fi

# A non-numeric floor must be rejected AS a manifest-shape fault. Deleting the check lets the
# value reach an arithmetic context, where bash silently evaluates a non-numeric string as 0 —
# so a corrupt manifest is reported as a restore that came up short.
BADFLOOR="$TMP/pins-badfloor.json"
sed 's/"floor": 2/"floor": "not-a-number"/' "$MANIFEST" > "$BADFLOOR" || { echo "harness: sed failed" >&2; exit 2; }
grep -qF 'not-a-number' "$BADFLOOR" || { echo "harness: the bad-floor fixture did not take" >&2; exit 2; }
fx="$TMP/fx-badfloor"; calls="$TMP/calls-badfloor"; : > "$calls"
ok_fixtures "$fx" "$TARGET"
out="$(run_engine "$fx" "$calls" --target "$TARGET" --tags-from "$BADFLOOR")"; rc=$?
if [[ "$rc" -eq 1 ]] && printf '%s' "$out" | grep -qF "numeric .floor"; then
  pass "a non-numeric manifest floor => exit 1 naming the floor (not an arithmetic 0)"
else
  fail "a corrupt floor must be a manifest fault, not a short restore" "$rc" "$out"
fi

# An unreadable manifest must say so. Without the readability check the failure surfaces as
# "declares no numeric .floor" — telling the operator the inventory is malformed when in fact it
# was never opened, which sends them to inspect a file rather than a path or a permission.
fx="$TMP/fx-noman"; calls="$TMP/calls-noman"; : > "$calls"
ok_fixtures "$fx" "$TARGET"
out="$(run_engine "$fx" "$calls" --target "$TARGET" --tags-from "$TMP/definitely-absent.json")"; rc=$?
if [[ "$rc" -eq 1 ]] && printf '%s' "$out" | grep -qF "not readable"; then
  pass "an unreadable manifest => exit 1 naming READABILITY (never 'treated as empty')"
else
  fail "an unreadable inventory must not be diagnosed as a malformed one" "$rc" "$out"
fi

# TLS is not optional off-loopback. `--insecure` is correct for the throwaway and for the real
# target reached through `cloudflared access tcp` on 127.0.0.1 — and is a downgrade anywhere
# else. Nothing exercised a non-loopback target, so the discrimination was untested.
T_REMOTE="registry.example.com:443"
fx="$TMP/fx-remote"; calls="$TMP/calls-remote"; : > "$calls"
ok_fixtures "$fx" "$T_REMOTE"
out="$(run_engine "$fx" "$calls" --target "$T_REMOTE" --tags-from "$MANIFEST")"; rc=$?
if [[ "$rc" -eq 0 ]] && ! grep -qF -- "--insecure" "$calls"; then
  pass "a NON-loopback sink is addressed over TLS — no --insecure on any call"
else
  fail "a non-loopback sink must not be downgraded to plain HTTP" "$rc" \
    "$(grep -nF -- '--insecure' "$calls" | head -3)"
fi

# The positive direction of the same discrimination, so "never --insecure" and "correct
# discrimination" are not confusable.
if grep -qF -- "--insecure" "$TMP/calls-ok"; then
  pass "a LOOPBACK sink still gets --insecure (the flag is discriminated, not merely absent)"
else
  fail "the loopback sink speaks plain HTTP and needs --insecure" "?" "$(head -5 "$TMP/calls-ok")"
fi

# followed by `::add-mask::` in that stderr would execute. Collapsing newlines makes the whole
# capture one un-parseable payload. Lifted from build-inngest-bootstrap-image.yml.
if sed -n '/^last_err() {/,/^}/p' "$ENGINE" | grep -qE "tr '\\\\n' ' '"; then
  pass "registry stderr is collapsed through tr (workflow-command injection guard)"
else
  fail "captured stderr must be newline-collapsed before interpolation" "?" \
    "$(grep -n 'tr ' "$ENGINE" || true)"
fi

# Digests are read THROUGH A FILE, never $(...), because a retry helper's ::notice:: lands on
# stdout and would be captured AS the digest.
if grep -qE 'grep -oE .\^sha256:\[0-9a-f\]\{64\}\$' "$ENGINE"; then
  pass "digests are filtered to a bare sha256: token before use"
else
  fail "digest reads must be filtered with the ^sha256:[0-9a-f]{64}$ shape" "?" \
    "$(grep -n 'sha256' "$ENGINE" | head -5)"
fi

# ── Buildx attestation manifests (#7378). ────────────────────────────────────────────────────
# `crane validate --remote <index>` walks every child and tries to GUNZIP every layer, so an
# attestation child (`application/vnd.in-toto+json`, never compressed) fails with
# `gzip: invalid header`. Reproduced directly at GHCR, so it is a validator false positive and
# not corruption. Verification 2 must therefore verify the index PER CHILD.

# att_index_fixtures <fx> <target> — ok_fixtures, but the web-platform ref is a buildx INDEX.
att_index_fixtures() {
  local fx="$1" t="$2" signals="${3:-both}"
  ok_fixtures "$fx" "$t"
  fx_oci_index       "$fx" "${t}/${WP}@${D1}" "$signals"
  fx_oci_attestation "$fx" "${t}/${WP}"
  # Drop the whole-index `validate:` fixture ok_fixtures laid down. Without this the positive
  # control is VACUOUS: the pre-fix engine validates the index, finds a PASS fixture, and exits 0
  # for the wrong reason. With it removed, validating the index hits the stub's no-fixture arm
  # (exit 70) — so the rc==0 assertion below can only be satisfied by real per-child verification.
  rm -f "$fx/$(key "validate:${t}/${WP}@${D1}")".rc \
        "$fx/$(key "validate:${t}/${WP}@${D1}")".out \
        "$fx/$(key "validate:${t}/${WP}@${D1}")".err
  # PROVE the delete landed. `rm -f` succeeds silently on a path that never existed, so if key()
  # ever drifts the positive control silently reverts to vacuous — green against a pre-fix engine.
  [[ ! -f "$fx/$(key "validate:${t}/${WP}@${D1}")".rc ]] || {
    echo "harness: the positive control's rm did not land — key() drifted; the control is vacuous" >&2; exit 2; }
  fixture "$fx" "validate:${t}/${WP}@${D_AMD64}" 0 "PASS"
  fixture "$fx" "blob:${t}/${WP}@${D_ATT_CFG}"   0 ""
  fixture "$fx" "blob:${t}/${WP}@${D_ATT_LAYER}" 0 ""
}

# (1) POSITIVE CONTROL — the real production shape must restore green. RED before the per-child
# rewrite: the engine validates the whole index and the stub has no `validate:<index-ref>` arm.
fx="$TMP/fx-att"; calls="$TMP/calls-att"; : > "$calls"
att_index_fixtures "$fx" "$TARGET"
out="$(run_engine "$fx" "$calls" --target "$TARGET" --tags-from "$MANIFEST")"; rc=$?
if [[ "$rc" -eq 0 ]]; then
  pass "an OCI index with an in-toto attestation child restores green (the production shape)"
else
  fail "the buildx-attestation index must verify clean" "$rc" "$out"
fi

if grep -qE "^blob .*${D_ATT_LAYER}" "$calls"; then
  pass "the attestation layer blob is PRESENCE-verified (crane blob), never gunzipped"
else
  fail "the in-toto layer must be verified via crane blob" "$rc" "$(cat "$calls")"
fi

if grep -qE "^validate .*--remote .*@${D_AMD64}( |$)" "$calls"; then
  pass "the real platform child is still blob-validated with crane validate --remote"
else
  fail "platform children must keep crane validate --remote" "$rc" "$(cat "$calls")"
fi

if grep -qE "^validate .*--remote ${TARGET}/${WP}:v0\.249\.4( |$)" "$calls"; then
  fail "the whole index must NOT be handed to crane validate (that is the false positive)" "$rc" "$(cat "$calls")"
else
  pass "the index itself is never handed to crane validate (the gunzip false positive is gone)"
fi

# (2) NEGATIVE CONTROL — a genuinely missing PLATFORM layer must still exit 4. Proves the
# per-child rewrite narrowed the gunzip false positive without weakening BLOBMISSING detection.
fx="$TMP/fx-att-blobmissing"; calls="$TMP/calls-att-blobmissing"; : > "$calls"
att_index_fixtures "$fx" "$TARGET"
fixture "$fx" "validate:${TARGET}/${WP}@${D_AMD64}" 1 "" \
  "Error: fetching layer: GET http://${TARGET}/v2/${WP}/blobs/${D_AMD64}: BLOB_UNKNOWN: blob unknown to registry"
out="$(run_engine "$fx" "$calls" --target "$TARGET" --tags-from "$MANIFEST")"; rc=$?
if [[ "$rc" -eq 4 ]]; then
  pass "a missing PLATFORM layer blob still exits 4 (BLOBMISSING not weakened)"
else
  fail "a blob-incomplete platform child must exit 4" "$rc" "$out"
fi

# (3) An attestation child whose blob is ABSENT must FAIL. Presence is verified, not skipped —
# this is the assertion that stops the fix from degrading into "ignore attestation children".
fx="$TMP/fx-att-absent"; calls="$TMP/calls-att-absent"; : > "$calls"
att_index_fixtures "$fx" "$TARGET"
fixture "$fx" "blob:${TARGET}/${WP}@${D_ATT_LAYER}" 1 "" \
  "Error: GET http://${TARGET}/v2/${WP}/blobs/${D_ATT_LAYER}: BLOB_UNKNOWN: blob unknown to registry"
out="$(run_engine "$fx" "$calls" --target "$TARGET" --tags-from "$MANIFEST")"; rc=$?
if [[ "$rc" -eq 4 ]]; then
  pass "an attestation child with an ABSENT blob still exits 4 (presence is verified, not skipped)"
else
  fail "an absent attestation blob must exit 4, never pass" "$rc" "$out"
fi

# (4) CLASSIFICATION — a residual `gzip: invalid header` on a real platform child is a genuine
# verification failure (exit 4 "do not deploy"), never the unclassifiable exit 6 it produced
# before. Exit 6 stays reserved for shapes the engine truly cannot name.
fx="$TMP/fx-att-gzip"; calls="$TMP/calls-att-gzip"; : > "$calls"
att_index_fixtures "$fx" "$TARGET"
fixture "$fx" "validate:${TARGET}/${WP}@${D_AMD64}" 1 "" \
  "Error: validating layers: gzip: invalid header"
out="$(run_engine "$fx" "$calls" --target "$TARGET" --tags-from "$MANIFEST")"; rc=$?
if [[ "$rc" -eq 4 ]]; then
  pass "'gzip: invalid header' on a platform child classifies to exit 4, not the opaque exit 6"
else
  fail "a layer-format mismatch must exit 4 (named class), not 6" "$rc" "$out"
fi

# (5) NON-INDEX behaviour is unchanged — asserted against the stub's own call log rather than by
# reading the suite. Exactly one validate for the single-manifest ref, and zero blob calls.
fx="$TMP/fx-nonindex"; calls="$TMP/calls-nonindex"; : > "$calls"
ok_fixtures "$fx" "$TARGET"
out="$(run_engine "$fx" "$calls" --target "$TARGET" --tags-from "$MANIFEST")"; rc=$?
# BY DIGEST: the non-index arm now validates ${dst_repo}@${dst_digest}, not the tag, so a
# tag-anchored counter reports 0 and the "drifted" message would blame the engine for the
# assertion having been left behind.
n_ib=$(grep -cE "^validate .*--remote ${TARGET}/${IB}@${D2}( |$)" "$calls" || true)
# Blob calls are EXPECTED here — verification 3 blob-verifies each signature's payload. What must
# NOT happen is any per-INDEX-CHILD work, so pin the attestation digests specifically rather than
# the blob count, which would otherwise just track how many signatures the pin set has.
n_childblob=$(grep -cE "^blob .*@(${D_ATT_CFG}|${D_ATT_LAYER}|${D_AMD64})( |$)" "$calls" || true)
n_sigblob=$(grep -cE "^blob .*@(${D_SIG_CFG}|${D_SIG_LAYER})( |$)" "$calls" || true)
if [[ "$rc" -eq 0 && "$n_ib" -eq 1 && "$n_childblob" -eq 0 && "$n_sigblob" -eq 4 ]]; then
  pass "a non-index ref keeps the unchanged path (1 validate, 0 index-child blobs, 4 signature blobs)"
else
  fail "non-index behaviour drifted: rc=$rc validate=$n_ib childblob=$n_childblob sigblob=$n_sigblob" "$rc" "$(cat "$calls")"
fi

# The signature's payload blob is verified, not just its manifest digest. This is the gap that
# let A2 go green over a signature no host could cosign-verify: crane digest is a HEAD against
# the manifest endpoint, and zot gc can evict the payload while the manifest survives.
fx="$TMP/fx-sigblob"; calls="$TMP/calls-sigblob"; : > "$calls"
ok_fixtures "$fx" "$TARGET"
fixture "$fx" "blob:${TARGET}/${WP}@${D_SIG_LAYER}" 1 "" \
  "Error: GET http://${TARGET}/v2/${WP}/blobs/${D_SIG_LAYER}: BLOB_UNKNOWN: blob unknown to registry"
out="$(run_engine "$fx" "$calls" --target "$TARGET" --tags-from "$MANIFEST")"; rc=$?
if [[ "$rc" -eq 4 ]] && printf '%s' "$out" | grep -qF "cosign signature"; then
  pass "an evicted cosign PAYLOAD blob fails (exit 4), not just an absent signature manifest"
else
  fail "the signature payload blob must be verified, not only its manifest digest" "$rc" "$out"
fi

# ── Each attestation signal must be load-bearing ON ITS OWN (the #7378 near-recurrence). ─────
# With both markers set, dropping either disjunct from the engine left the suite green. Worse,
# the arch-only shape exposed a real bug: `@tsv` emits an EMPTY annotation field, tab is
# IFS-whitespace, bash collapses the run, and `unknown` landed in c_type with c_arch empty — so
# the child took the PLATFORM branch, got gunzipped, and reproduced #7378 with a message denying
# it. These two cases fail on the pre-fix engine and are the regression guard.
for sig in arch annot; do
  fx="$TMP/fx-att-$sig"; calls="$TMP/calls-att-$sig"; : > "$calls"
  att_index_fixtures "$fx" "$TARGET" "$sig"
  out="$(run_engine "$fx" "$calls" --target "$TARGET" --tags-from "$MANIFEST")"; rc=$?
  if [[ "$rc" -eq 0 ]] && grep -qE "^blob .*${D_ATT_LAYER}" "$calls"; then
    pass "an attestation child marked ONLY by '$sig' is still routed to blob-presence, not gunzip"
  else
    fail "attestation detection must not depend on the other signal ($sig-only)" "$rc" "$out
$(cat "$calls")"
  fi
  if grep -qE "^validate .*--remote .*@${D_ATT}( |$)" "$calls"; then
    fail "the attestation child ($sig-only) was handed to crane validate — #7378 reproduced" "$rc" "$(cat "$calls")"
  else
    pass "the attestation child ($sig-only) is never handed to crane validate"
  fi
done

# ── Degenerate index shapes must fail CLOSED, each with its own named verdict. ────────────────
att_shape_case() { # <name> <index-json> <expected-rc> <expected-message-substring>
  local name="$1" json="$2" want="$3" anchor="$4"
  local fx="$TMP/fx-shape-$name" calls="$TMP/calls-shape-$name"; : > "$calls"
  ok_fixtures "$fx" "$TARGET"
  # Lay down the attestation child's manifest + blobs so a shape whose children are individually
  # verifiable reaches the SHAPE guard under test, rather than aborting earlier on a missing
  # fixture (which would make the case pass for the wrong reason).
  fx_oci_attestation "$fx" "${TARGET}/${WP}"
  fixture "$fx" "blob:${TARGET}/${WP}@${D_ATT_CFG}"   0 ""
  fixture "$fx" "blob:${TARGET}/${WP}@${D_ATT_LAYER}" 0 ""
  fixture "$fx" "validate:${TARGET}/${WP}@${D_AMD64}" 0 "PASS"
  fx_oci_raw "$fx" "${TARGET}/${WP}@${D1}" "$json"
  rm -f "$fx/$(key "validate:${TARGET}/${WP}:v0.249.4")".rc
  local out rc
  out="$(run_engine "$fx" "$calls" --target "$TARGET" --tags-from "$MANIFEST")"; rc=$?
  if [[ "$rc" -eq "$want" ]] && printf '%s' "$out" | grep -qF "$anchor"; then
    pass "index shape '$name' => exit $want naming '$anchor'"
  else
    fail "index shape '$name' must exit $want naming '$anchor'" "$rc" "$out"
  fi
}

att_shape_case nested-index '{"schemaVersion":2,"mediaType":"application/vnd.oci.image.index.v1+json","manifests":[{"mediaType":"application/vnd.oci.image.index.v1+json","digest":"'"$D_AMD64"'","size":10,"platform":{"architecture":"amd64","os":"linux"}}]}' 4 "NESTED index child"

att_shape_case attestation-only '{"schemaVersion":2,"mediaType":"application/vnd.oci.image.index.v1+json","manifests":[{"mediaType":"application/vnd.oci.image.manifest.v1+json","digest":"'"$D_ATT"'","size":566,"platform":{"architecture":"unknown","os":"unknown"}}]}' 4 "NO platform image among them"

att_shape_case child-without-digest '{"schemaVersion":2,"mediaType":"application/vnd.oci.image.index.v1+json","manifests":[{"mediaType":"application/vnd.oci.image.manifest.v1+json","size":10,"platform":{"architecture":"amd64","os":"linux"}}]}' 4 "index child with no digest"

att_shape_case manifests-not-array '{"schemaVersion":2,"manifests":{"a":1}}' 4 "is not an array"

# ── The attestation-manifest READ (not just its blobs) must classify, at every arm. ───────────
# Nothing exercised a FAILING `manifest:` fixture anywhere, so NETWORK->3 and DENIED->5 were
# untested at all five new call sites. Exit 3 is the only code the restore job's backoff retries;
# mislabelling it after the store is destroyed is the failure ADR-169's exit table exists to stop.
att_read_case() { # <name> <stub-stderr> <expected-rc>
  local name="$1" err="$2" want="$3"
  local fx="$TMP/fx-read-$name" calls="$TMP/calls-read-$name"; : > "$calls"
  att_index_fixtures "$fx" "$TARGET"
  fixture "$fx" "manifest:${TARGET}/${WP}@${D_ATT}" 1 "" "$err"
  local out rc
  out="$(run_engine "$fx" "$calls" --target "$TARGET" --tags-from "$MANIFEST")"; rc=$?
  if [[ "$rc" -eq "$want" ]]; then
    pass "attestation-manifest read failure '$name' => exit $want"
  else
    fail "attestation-manifest read '$name' must exit $want" "$rc" "$out"
  fi
}
att_read_case network 'Error: Get "http://127.0.0.1:5555/v2/": dial tcp: connection refused' 3
att_read_case denied  'Error: GET http://127.0.0.1:5555/v2/token: UNAUTHORIZED: authentication required' 5
att_read_case absent  'Error: GET http://127.0.0.1:5555/v2/x/manifests/y: MANIFEST_UNKNOWN: manifest unknown' 4

# The attestation CONFIG blob is part of the presence set, not just its layers.
fx="$TMP/fx-att-cfg"; calls="$TMP/calls-att-cfg"; : > "$calls"
att_index_fixtures "$fx" "$TARGET"
fixture "$fx" "blob:${TARGET}/${WP}@${D_ATT_CFG}" 1 "" \
  "Error: GET http://${TARGET}/v2/${WP}/blobs/${D_ATT_CFG}: BLOB_UNKNOWN: blob unknown to registry"
out="$(run_engine "$fx" "$calls" --target "$TARGET" --tags-from "$MANIFEST")"; rc=$?
if [[ "$rc" -eq 4 ]]; then
  pass "an attestation child's CONFIG blob is presence-verified too (absent => exit 4)"
else
  fail "an absent attestation config blob must exit 4" "$rc" "$out"
fi

# ── Operator verdicts must be DISTINGUISHABLE, not merely all-exit-4. ─────────────────────────
# Five distinct causes collapse onto rc 4; without a message anchor a mutation swapping one class
# for another is invisible, and they route to different runbook rows.
verdict_case() { # <name> <stub-stderr> <expected-anchor> <forbidden-anchor>
  local name="$1" err="$2" want="$3" nope="$4"
  local fx="$TMP/fx-verdict-$name" calls="$TMP/calls-verdict-$name"; : > "$calls"
  att_index_fixtures "$fx" "$TARGET"
  fixture "$fx" "validate:${TARGET}/${WP}@${D_AMD64}" 1 "" "$err"
  local out rc
  out="$(run_engine "$fx" "$calls" --target "$TARGET" --tags-from "$MANIFEST")"; rc=$?
  if [[ "$rc" -eq 4 ]] && printf '%s' "$out" | grep -qF "$want" && ! printf '%s' "$out" | grep -qF "$nope"; then
    pass "verdict '$name' names '$want' and not '$nope'"
  else
    fail "verdict '$name' must name '$want' and not '$nope'" "$rc" "$out"
  fi
}
verdict_case layerformat 'Error: validating layers: gzip: invalid header' \
  "could not decompress a layer as gzip" "BLOB-INCOMPLETE"
verdict_case blobmissing 'Error: fetching layer: BLOB_UNKNOWN: blob unknown to registry' \
  "BLOB-INCOMPLETE" "could not decompress"
verdict_case contentmismatch 'Error: error verifying sha256 checksum after reading 1054 bytes; got "sha256:aa", want "sha256:bb"' \
  "CORRUPT AT THE SINK" "BLOB-INCOMPLETE"

# The LAYERFORMAT verdict must hand the operator the discriminating command, not a conclusion.
fx="$TMP/fx-layerfmt-action"; calls="$TMP/calls-layerfmt-action"; : > "$calls"
att_index_fixtures "$fx" "$TARGET"
fixture "$fx" "validate:${TARGET}/${WP}@${D_AMD64}" 1 "" 'Error: validating layers: gzip: invalid header'
out="$(run_engine "$fx" "$calls" --target "$TARGET" --tags-from "$MANIFEST")"; rc=$?
if printf '%s' "$out" | grep -qF 'crane validate --remote ghcr.io/'; then
  pass "the layer-format verdict names the GHCR control read that discriminates the two causes"
else
  fail "a layer-format verdict must give the discriminating command, not just a prohibition" "$rc" "$out"
fi

# ── ref_repo: the port-vs-tag case the helper exists for. ─────────────────────────────────────
# The plan claimed this was 'covered by a unit case'; it was not. Every ref the engine builds
# carries a tag, so the untagged host:port arm was never reached by any other assertion.
rr() { ( set -euo pipefail; . /dev/stdin <<< "$(sed -n '/^ref_repo() {/,/^}/p' "$ENGINE")"; ref_repo "$1" ); }
rr_expect() {
  local got; got="$(rr "$1")"
  if [[ "$got" == "$2" ]]; then pass "ref_repo('$1') => '$2'"; else fail "ref_repo('$1') must be '$2'" "?" "got '$got'"; fi
}
rr_expect "127.0.0.1:5999/jikig-ai/soleur-web-platform:v0.249.4" "127.0.0.1:5999/jikig-ai/soleur-web-platform"
rr_expect "127.0.0.1:5999/jikig-ai/soleur-web-platform"           "127.0.0.1:5999/jikig-ai/soleur-web-platform"
rr_expect "127.0.0.1:5999/jikig-ai/soleur-web-platform@${D1}"     "127.0.0.1:5999/jikig-ai/soleur-web-platform"

# ── The signature is an INDEX at GHCR, not a plain manifest. ─────────────────────────────────
# This is the regression that refused the recut on run 31392395980 with "declares no blobs" on a
# perfectly healthy signature. The suite was green because the only signature fixture modelled the
# LEGACY simplesigning shape. Positive control on the measured shape:
sigx_fixtures() { # <dir> <target> — ok_fixtures, but signatures in the production index shape
  local fx="$1" t="$2"
  ok_fixtures "$fx" "$t"
  # Replace the legacy plain-manifest signature with the measured index shape. `rm` so the plain
  # arm cannot answer for the index arm -- the same vacuity that let the bug ship.
  # key() maps / : @ -> _ and fixture() writes .rc/.out/.err — a raw path deletes NOTHING.
  # Measured before this fix: 69 fixture files before the rm, 69 after.
  local _k
  for _k in "manifest:${t}/${WP}@${D_OTHER}" "manifest:${t}/${IB}@${D_OTHER}"; do
    rm -f "$fx/$(key "$_k")".rc "$fx/$(key "$_k")".out "$fx/$(key "$_k")".err
    [[ ! -f "$fx/$(key "$_k")".rc ]] || {
      echo "harness: rm did not land for ${_k} — key() drifted; the control is vacuous" >&2; exit 2; }
  done
  fx_oci_signature_index "$fx" "${t}/${WP}" "sha256-${D1#sha256:}"
  fx_oci_signature_index "$fx" "${t}/${IB}" "sha256-${D2#sha256:}" "$D2"
}

fx="$TMP/fx-sigx"; calls="$TMP/calls-sigx"; : > "$calls"
sigx_fixtures "$fx" "$TARGET"
out="$(run_engine "$fx" "$calls" --target "$TARGET" --tags-from "$MANIFEST")"; rc=$?
if [[ "$rc" -eq 0 ]]; then
  pass "a cosign signature in the GHCR index shape (sigstore bundle child) verifies and PASSES"
else
  fail "the production signature index shape must pass" "$rc" "$out"
fi

# ...and the legacy plain shape must KEEP passing. Both disjuncts, each alone.
fx="$TMP/fx-sig-legacy"; calls="$TMP/calls-sig-legacy"; : > "$calls"
ok_fixtures "$fx" "$TARGET"
out="$(run_engine "$fx" "$calls" --target "$TARGET" --tags-from "$MANIFEST")"; rc=$?
if [[ "$rc" -eq 0 ]]; then
  pass "the legacy simplesigning signature shape still passes (no shape was traded for the other)"
else
  fail "the legacy plain-manifest signature shape must keep passing" "$rc" "$out"
fi

# The walk must be real, not a shape check: the bundle blob is fetched.
fx="$TMP/fx-sigx-blob"; calls="$TMP/calls-sigx-blob"; : > "$calls"
sigx_fixtures "$fx" "$TARGET"
run_engine "$fx" "$calls" --target "$TARGET" --tags-from "$MANIFEST" >/dev/null 2>&1 || true
# The stub logs full argv, so $SINK_TLS_FLAG sits between the verb and the ref — anchor on the
# verb at line start and the ref anywhere after it, never on the two being adjacent.
if grep -qE "^blob .*${TARGET}/${WP}@${D_SIGX_BUNDLE}\$" "$calls"; then
  pass "the sigstore bundle layer blob is actually fetched (the index walk reaches the child's blobs)"
else
  fail "the index walk must fetch the child's bundle blob" "?" "$(cat "$calls")"
fi

# NEGATIVE: an index-shaped signature whose bundle blob is gone must still FAIL. This is the whole
# point of blob-verifying rather than HEADing the manifest -- gc can evict the payload while the
# manifest survives, and that payload is what ci-deploy.sh feeds to cosign verify.
fx="$TMP/fx-sigx-gone"; calls="$TMP/calls-sigx-gone"; : > "$calls"
sigx_fixtures "$fx" "$TARGET"
fixture "$fx" "blob:${TARGET}/${WP}@${D_SIGX_BUNDLE}" 1 "" \
  "Error: GET http://${TARGET}/v2/${WP}/blobs/${D_SIGX_BUNDLE}: BLOB_UNKNOWN: blob unknown to registry"
out="$(run_engine "$fx" "$calls" --target "$TARGET" --tags-from "$MANIFEST")"; rc=$?
# Anchored on the VERDICT, not just rc 4. The pre-fix engine also exits 4 here — with "declares no
# blobs", i.e. the right code for the wrong reason — so an rc-only assertion passes under both
# engines and discriminates nothing. The evicted-blob path must name BLOB-INCOMPLETE.
if [[ "$rc" -eq 4 ]] && printf '%s' "$out" | grep -qF "BLOB-INCOMPLETE" \
   && ! printf '%s' "$out" | grep -qF "declares no blobs"; then
  pass "an index-shaped signature with an evicted bundle blob exits 4 naming BLOB-INCOMPLETE"
else
  fail "an evicted sigstore bundle blob must exit 4 naming BLOB-INCOMPLETE" "$rc" "$out"
fi

# A signature index declaring zero children references nothing verifiable — fail closed, and say so
# rather than reporting the pass that an empty loop would otherwise produce.
fx="$TMP/fx-sigx-empty"; calls="$TMP/calls-sigx-empty"; : > "$calls"
sigx_fixtures "$fx" "$TARGET"
fx_oci_raw "$fx" "${TARGET}/${WP}@${D_OTHER}" \
  '{"schemaVersion":2,"mediaType":"application/vnd.oci.image.index.v1+json","manifests":[]}'
out="$(run_engine "$fx" "$calls" --target "$TARGET" --tags-from "$MANIFEST")"; rc=$?
if [[ "$rc" -eq 4 ]] && printf '%s' "$out" | grep -qF "no children"; then
  pass "a signature index with zero children exits 4 and names the empty index"
else
  fail "an empty signature index must exit 4 naming the cause" "$rc" "$out"
fi

# Depth 2 fails closed rather than recursing into a shape nothing here produces.
fx="$TMP/fx-sigx-nested"; calls="$TMP/calls-sigx-nested"; : > "$calls"
sigx_fixtures "$fx" "$TARGET"
fx_oci_raw "$fx" "${TARGET}/${WP}@${D_SIGX_CHILD}" \
  '{"schemaVersion":2,"mediaType":"application/vnd.oci.image.index.v1+json","manifests":[{"mediaType":"application/vnd.oci.image.manifest.v1+json","digest":"'"$D_SIGX_BUNDLE"'"}]}'
out="$(run_engine "$fx" "$calls" --target "$TARGET" --tags-from "$MANIFEST")"; rc=$?
if [[ "$rc" -eq 4 ]] && printf '%s' "$out" | grep -qF "nested inside another index"; then
  pass "an index nested inside a signature index fails closed at depth 2"
else
  fail "a depth-2 nested index must fail closed" "$rc" "$out"
fi

# A child carrying no digest cannot be addressed; it must not be silently skipped.
fx="$TMP/fx-sigx-nodigest"; calls="$TMP/calls-sigx-nodigest"; : > "$calls"
sigx_fixtures "$fx" "$TARGET"
fx_oci_raw "$fx" "${TARGET}/${WP}@${D_OTHER}" \
  '{"schemaVersion":2,"mediaType":"application/vnd.oci.image.index.v1+json","manifests":[{"mediaType":"application/vnd.oci.image.manifest.v1+json","size":876}]}'
out="$(run_engine "$fx" "$calls" --target "$TARGET" --tags-from "$MANIFEST")"; rc=$?
if [[ "$rc" -eq 4 ]] && printf '%s' "$out" | grep -qF "declares no digest"; then
  pass "a signature-index child with no digest exits 4 rather than being skipped"
else
  fail "a digest-less signature child must exit 4" "$rc" "$out"
fi

# ── The child-cardinality axis: n=2, because n<=1 cannot discriminate. ───────────────────────
# Every signature fixture above has exactly ONE child, and a review pass proved that both of these
# survive a 78/0 suite:
#   LOOSENING  — verify only the first child; children 2..N are counted (so the equality holds) but
#                never read. A truncated walk that reads as verified: E34's own name.
#   TIGHTENING — refuse any index with >1 child. That reproduces #7410's exact failure mode (a
#                fail-closed abort on a healthy production signature) one cardinality later, in a
#                suite written to prevent precisely that.
# Neither is reachable while 0 and 1 are the only instantiated values.
D_SIGX_CHILD2="sha256:77aa88bb99cc00dd11ee22ff33445566778899aabbccddeeff00112233445566"
D_SIGX_BUNDLE2="sha256:66554433221100ffeeddccbbaa998877665544332211000ffeeddccbbaa99887"
fx_sig_index_2child() { # <dir> <sink-repo> — the production shape, with a SECOND child
  fixture "$1" "manifest:$2@$D_OTHER" 0 '{
  "schemaVersion": 2,
  "mediaType": "application/vnd.oci.image.index.v1+json",
  "manifests": [
    { "mediaType": "application/vnd.oci.image.manifest.v1+json", "size": 876, "digest": "'"$D_SIGX_CHILD"'", "artifactType": "application/vnd.dev.sigstore.bundle.v0.3+json" },
    { "mediaType": "application/vnd.oci.image.manifest.v1+json", "size": 902, "digest": "'"$D_SIGX_CHILD2"'", "artifactType": "application/vnd.dev.sigstore.bundle.v0.3+json" }
  ]
}'
  fixture "$1" "manifest:$2@$D_SIGX_CHILD" 0 '{
  "schemaVersion": 2,
  "mediaType": "application/vnd.oci.image.manifest.v1+json",
  "config": { "mediaType": "application/vnd.oci.empty.v1+json", "digest": "'"$D_SIGX_CFG"'", "size": 2 },
  "layers": [ { "mediaType": "application/vnd.dev.sigstore.bundle.v0.3+json", "digest": "'"$D_SIGX_BUNDLE"'", "size": 10559 } ]
}'
  fixture "$1" "manifest:$2@$D_SIGX_CHILD2" 0 '{
  "schemaVersion": 2,
  "mediaType": "application/vnd.oci.image.manifest.v1+json",
  "config": { "mediaType": "application/vnd.oci.empty.v1+json", "digest": "'"$D_SIGX_CFG"'", "size": 2 },
  "layers": [ { "mediaType": "application/vnd.dev.sigstore.bundle.v0.3+json", "digest": "'"$D_SIGX_BUNDLE2"'", "size": 9931 } ]
}'
  fixture "$1" "blob:$2@$D_SIGX_CFG"     0 ""
  fixture "$1" "blob:$2@$D_SIGX_BUNDLE"  0 ""
  fixture "$1" "blob:$2@$D_SIGX_BUNDLE2" 0 ""
}

sig2_fixtures() { # <dir> <target>
  local fx="$1" t="$2"
  ok_fixtures "$fx" "$t"
  local _k
  for _k in "manifest:${t}/${WP}@${D_OTHER}" "manifest:${t}/${IB}@${D_OTHER}"; do
    rm -f "$fx/$(key "$_k")".rc "$fx/$(key "$_k")".out "$fx/$(key "$_k")".err
    [[ ! -f "$fx/$(key "$_k")".rc ]] || {
      echo "harness: rm did not land for ${_k} — key() drifted; the control is vacuous" >&2; exit 2; }
  done
  fx_sig_index_2child "$fx" "${t}/${WP}"
  fx_oci_signature_index "$fx" "${t}/${IB}" "sha256-${D2#sha256:}" "$D2"
}

# TIGHTENING control: two healthy children must PASS. A `>1 children` refusal would be #7410 again.
fx="$TMP/fx-sig2"; calls="$TMP/calls-sig2"; : > "$calls"
sig2_fixtures "$fx" "$TARGET"
out="$(run_engine "$fx" "$calls" --target "$TARGET" --tags-from "$MANIFEST")"; rc=$?
# ANCHOR ON THE REPO. The bundle digests are shared with the single-child IB fixture, so a
# repo-agnostic grep is satisfied by the IB call even when WP's child 1 was never walked —
# which let "verify only the LAST child" survive at 83/0 until this was tightened.
both_fetched=0
grep -qE "^blob .*${TARGET}/${WP}@${D_SIGX_BUNDLE}\$"  "$calls" && \
grep -qE "^blob .*${TARGET}/${WP}@${D_SIGX_BUNDLE2}\$" "$calls" && both_fetched=1
if [[ "$rc" -eq 0 ]] && [[ "$both_fetched" -eq 1 ]]; then
  pass "a two-child signature index verifies and PASSES, with BOTH children's blobs fetched"
else
  fail "a healthy two-child signature index must pass" "$rc" "$out"
fi

# LOOSENING control: the SECOND child's blob is evicted. Only a walk that REACHES child 2 reds.
fx="$TMP/fx-sig2-gone"; calls="$TMP/calls-sig2-gone"; : > "$calls"
sig2_fixtures "$fx" "$TARGET"
fixture "$fx" "blob:${TARGET}/${WP}@${D_SIGX_BUNDLE2}" 1 "" \
  "Error: GET http://${TARGET}/v2/${WP}/blobs/${D_SIGX_BUNDLE2}: BLOB_UNKNOWN: blob unknown to registry"
out="$(run_engine "$fx" "$calls" --target "$TARGET" --tags-from "$MANIFEST")"; rc=$?
if [[ "$rc" -eq 4 ]] && printf %s "$out" | grep -qF "BLOB-INCOMPLETE"; then
  pass "the SECOND child's evicted blob exits 4 (the walk does not stop at child 1)"
else
  fail "a walk that stops at child 1 must not read as verified" "$rc" "$out"
fi

# A child with a CONFIG but NO layers must not pass by fetching the well-known empty config blob.
fx="$TMP/fx-sig-nolayer"; calls="$TMP/calls-sig-nolayer"; : > "$calls"
sigx_fixtures "$fx" "$TARGET"
fx_oci_raw "$fx" "${TARGET}/${WP}@${D_SIGX_CHILD}" \
  '{"schemaVersion":2,"mediaType":"application/vnd.oci.image.manifest.v1+json","config":{"mediaType":"application/vnd.oci.empty.v1+json","digest":"'"$D_SIGX_CFG"'","size":2},"layers":[]}'
out="$(run_engine "$fx" "$calls" --target "$TARGET" --tags-from "$MANIFEST")"; rc=$?
if [[ "$rc" -eq 4 ]] && printf %s "$out" | grep -qF "NO layers"; then
  pass "a signature child with a config but no layers exits 4 (the empty config is not evidence)"
else
  fail "a layerless signature child must exit 4" "$rc" "$out"
fi

# A signature whose blobs are all valid but which signs a DIFFERENT image must not pass.
fx="$TMP/fx-sig-subject"; calls="$TMP/calls-sig-subject"; : > "$calls"
sigx_fixtures "$fx" "$TARGET"
fx_oci_raw "$fx" "${TARGET}/${WP}@${D_SIGX_CHILD}" \
  '{"schemaVersion":2,"mediaType":"application/vnd.oci.image.manifest.v1+json","artifactType":"application/vnd.dev.sigstore.bundle.v0.3+json","subject":{"digest":"'"$D_OTHER"'"},"config":{"mediaType":"application/vnd.oci.empty.v1+json","digest":"'"$D_SIGX_CFG"'","size":2},"layers":[{"mediaType":"application/vnd.dev.sigstore.bundle.v0.3+json","digest":"'"$D_SIGX_BUNDLE"'","size":10559}]}'
out="$(run_engine "$fx" "$calls" --target "$TARGET" --tags-from "$MANIFEST")"; rc=$?
if [[ "$rc" -eq 4 ]] && printf %s "$out" | grep -qF "signs a DIFFERENT image"; then
  pass "a signature with valid blobs but the WRONG subject exits 4"
else
  fail "a wrong-subject signature must exit 4" "$rc" "$out"
fi

# The signature digest parity guard: GHCR and the sink must serve the SAME signature. Every
# fixture returned the same digest for both reads, so the comparison was a tautology and
# `[[ "$sig_src_digest" == "$sig_src_digest" ]]` left the suite fully green.
fx="$TMP/fx-sig-parity"; calls="$TMP/calls-sig-parity"; : > "$calls"
sigx_fixtures "$fx" "$TARGET"
fixture "$fx" "${TARGET}/${WP}:sha256-${D1#sha256:}" 0 "$D_SIGX_CHILD2"
out="$(run_engine "$fx" "$calls" --target "$TARGET" --tags-from "$MANIFEST")"; rc=$?
if [[ "$rc" -eq 4 ]] && printf %s "$out" | grep -qF "differs between GHCR"; then
  pass "a sink serving a DIFFERENT signature than GHCR exits 4 (digest parity is not a tautology)"
else
  fail "signature digest parity must be enforced" "$rc" "$out"
fi

# ── Anti-vacuity floor for THIS suite. ────────────────────────────────────────────────────────
# Deleting the entire new assertion block left the suite green at 43/0, exit 0 — `fails -eq 0` is
# satisfied by asserting nothing. A floor (never `-eq`, which would make every added assertion a
# spurious failure) makes that deletion loud. Derived from a green run, ratchet upward only.
MIN_ASSERTIONS=83
if (( passes + fails < MIN_ASSERTIONS )); then
  printf '  FAIL harness: %d assertions ran, floor is %d — assertions were deleted or skipped\n' \
    "$((passes + fails))" "$MIN_ASSERTIONS"
  fails=$(( fails + 1 ))
fi

printf '\n=== %d passed, %d failed ===\n\n' "$passes" "$fails"
[[ "$fails" -eq 0 ]]
