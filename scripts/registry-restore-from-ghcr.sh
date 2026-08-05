#!/usr/bin/env bash
# registry-restore-from-ghcr — re-materialise production's pinned image set into a registry,
# reading from GHCR (#7277).
#
# WHAT THIS IS FOR. The registry-luks-recut destroys production's only container image store.
# This engine is what refills it. It runs twice per dispatch, from ONE entrypoint:
#
#   1. as a REHEARSAL against a throwaway zot in the runner, BEFORE anything is destroyed —
#      the D10 gate's A2 predicate, which is what authorises the destroy at all; and
#   2. for REAL against the rebuilt production zot, in a separate needs:-chained job.
#
# The two invocations differ in exactly `--target` and the credential environment. That is not a
# convenience — it is the anti-drift property A2 depends on: a rehearsal that exercised a
# different code path than the real restore would certify nothing. There is deliberately no
# `--rehearse` flag; see "WHY NOTHING SIGNS" below.
#
# ── WHY VERIFICATION IS INTRINSIC, NOT THE CALLER'S JOB ──────────────────────────────────────
# This script does not exit 0 until it has read every reference back OUT of the target and
# validated its BLOBS. A digest-only round-trip is a verification that goes green on an unusable
# restore, and that is measured, not theoretical (2026-08-05, throwaway zot, layer blob evicted
# from the store on disk):
#
#     crane digest            -> rc 0, PASS      <- certifies an image no host can pull
#     crane validate --remote -> rc 1, BLOB_UNKNOWN: blob unknown to registry
#
# zot runs gc + dedupe and `crane digest` is a manifest read, so a manifest can outlive its
# layers. build-inngest-bootstrap-image.yml records the same trap in prose; this is the
# measurement behind it. Verification therefore uses `crane validate --remote`, never `--fast`
# (which skips layers), and never a daemon-side image pull — the runner's local image cache can
# satisfy one of those without the registry being contacted at all, so it proves nothing about
# the sink. (The literal two-word command is spelled out nowhere in this file on purpose: AC9 is
# a whole-file grep, and a comment naming it would false-fail a correct script.)
#
# ── WHY NOTHING SIGNS (Phase 0.3, measured 2026-08-05) ───────────────────────────────────────
# The restore obligation includes signatures: ci-deploy.sh cosign-verifies at deploy time and
# fetches the signature from the SAME registry it pulled the image from, so a restored image
# whose signature is absent fails verification on the host (ADR-087).
#
# The signature is copied, not re-created. GHCR carries it as an OCI referrers tag
# `sha256-<hex>` whose artifactType is `application/vnd.dev.sigstore.bundle.v0.3+json` — a
# Sigstore BUNDLE, which binds to the image DIGEST. It is not the legacy simple-signing payload,
# so there is no `critical.identity.docker-reference` pinning the GHCR ref and nothing to
# mismatch when the same bytes are served from zot. ci-deploy.sh:1993 corroborates: it verifies
# `$repo_digest` with `--certificate-identity-regexp` + `--certificate-oidc-issuer` (identity
# from the Fulcio certificate, never from a registry ref) and already passes
# `--allow-insecure-registry` for the zot case.
#
# Consequences: `crane copy` is digest-preserving, so a copied signature verifies identically at
# the target; the calling job needs NO `id-token: write`; and because nothing signs, no gate run
# writes to the public Rekor transparency log. There is no unsigned-restore arm — a missing
# signature is a verification failure (exit 4), not a warning.
#
# ── EXIT CODES — fully enumerated, each with a distinct operator action ──────────────────────
# A bare `1` for "something went wrong" is not actionable on the path that follows an
# irreversible destroy. The runbook carries one operator action per code.
#
#   0  every required reference restored AND verified (blobs + signature)
#   2  SOURCE unavailable — GHCR could not be read. Classified sub-cause in the message.
#   3  SINK unavailable — the target registry did not accept or serve the write. RETRYABLE:
#      this is the code the chained restore job retries on, because a host replace can outrun
#      the Cloudflare Tunnel's re-convergence onto the replaced origin.
#   4  VERIFICATION failed — digest parity mismatch, missing blob, or missing signature. The
#      copy "succeeded" and the result is not usable. NOT retryable.
#   5  CREDENTIAL unusable — absent, empty, or REJECTED by the sink. NOT retryable: retrying an
#      authorisation failure only wastes the window. Deliberately distinct from 3, mirroring the
#      abort/degrade boundary the D10 gate's removed A5 predicate used: authorisation and
#      availability failures are different classes with different verdicts. (A5 itself was
#      deleted by architecture ruling — ADR-169 — but the boundary it drew was sound, and this
#      engine is where it still lives, post-destroy, against the host that actually applies.)
#   6  COULD NOT CLASSIFY — the failure matched no known shape. Loudest arm. An unclassified
#      failure must never read as either "absent" or "fine".
#
# Usage:
#   scripts/registry-restore-from-ghcr.sh --target <host:port> --tags-from <manifest.json>
#
# Env:
#   ZOT_PUSH_USER, ZOT_PUSH_TOKEN   (required) — sink credentials. Validated BEFORE the first
#                                   network call, so a credential fault cannot leave a
#                                   half-restored registry.
#   REGISTRY_RESTORE_CRANE_CMD      (test seam) — the crane binary to invoke.

set -uo pipefail

TARGET=""
TAGS_FROM=""
CRANE="${REGISTRY_RESTORE_CRANE_CMD:-crane}"

die() { # $1 = exit code, rest = message
  local code="$1"; shift
  echo "::error::registry-restore-from-ghcr: $*" >&2
  exit "$code"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target|--tags-from)
      # A VALUE-TAKING FLAG WITH NO VALUE MUST FAIL LOUDLY, NOT SPIN. `shift 2` with one argument
      # remaining returns non-zero WITHOUT shifting, and there is no `set -e` here — so the loop
      # re-reads the same `$1` forever. In a runner that is a HANG to the job timeout, and a job
      # timeout is a CANCELLATION: no `::error::`, no exit code, no diagnosis. This engine runs
      # AFTER the destroy, so a silent cancellation there leaves an empty registry and a run whose
      # log says nothing about why.
      [[ $# -ge 2 ]] || die 1 "$1 requires a value (none was supplied)."
      case "$1" in
        --target)    TARGET="$2" ;;
        --tags-from) TAGS_FROM="$2" ;;
      esac
      shift 2 ;;
    # `--rehearse` existed in the plan to select `cosign sign --tlog-upload=false`. Phase 0.3
    # resolved the signature mechanism to a copy, so nothing signs and the flag had no referent.
    # It is REJECTED rather than accepted-as-a-no-op: a caller that believed it was rehearsing
    # while writing to production would be the worst possible silent failure here.
    --rehearse)
      die 1 "--rehearse was removed (#7277). Nothing signs — signatures are copied — so the flag had no effect to select. The rehearsal and the real restore differ in --target and credentials only." ;;
    *) die 1 "unknown argument '$1'" ;;
  esac
done

[[ -n "$TARGET" ]]    || die 1 "--target <host:port> is required."
[[ -n "$TAGS_FROM" ]] || die 1 "--tags-from <manifest.json> is required."
[[ -r "$TAGS_FROM" ]] || die 1 "--tags-from manifest '${TAGS_FROM}' is not readable. Refusing to treat an unreadable inventory as an empty one."
# A target that is itself ghcr.io would make this a no-op that reports success.
case "$TARGET" in
  ghcr.io|ghcr.io/*|*://*) die 1 "--target must be a registry host:port, not '${TARGET}'." ;;
esac

# ── CREDENTIALS FIRST, before any network call. ──────────────────────────────────────────────
# A credential fault discovered halfway through leaves a partially populated registry, which is
# worse than an empty one: tag lookups succeed for some refs and not others, so the failure
# presents as a confusing per-image outage rather than an obvious total one.
[[ -n "${ZOT_PUSH_USER:-}"  ]] || die 5 "ZOT_PUSH_USER is unset or empty — cannot authenticate to the sink."
[[ -n "${ZOT_PUSH_TOKEN:-}" ]] || die 5 "ZOT_PUSH_TOKEN is unset or empty — cannot authenticate to the sink."

command -v jq >/dev/null 2>&1 || die 6 "jq is not available, so the pin manifest cannot be parsed."

FLOOR=$(jq -r '.floor // empty' "$TAGS_FROM" 2>/dev/null)
[[ "$FLOOR" =~ ^[0-9]+$ ]] || die 1 "the manifest declares no numeric .floor — refusing to restore against an unbounded inventory."

# The floor is the non-vacuity guard. It is declared in the manifest by the PREPARE step that
# derived the pin set, and asserted here, so a derivation that silently produced fewer required
# entries than production actually depends on cannot report success.
n_required=$(jq -r '[.entries[] | select(.disposition == "required")] | length' "$TAGS_FROM" 2>/dev/null)
[[ "$n_required" =~ ^[0-9]+$ ]] || die 1 "the manifest's .entries could not be parsed."
if (( n_required == 0 )); then
  die 1 "the pin manifest declares ZERO required entries. An empty inventory makes every loop below pass while restoring nothing — refusing to report success on an unrestored registry."
fi

# Required entries must be DISTINCT. Without this, the floor is satisfiable by duplication: a
# manifest listing the same repo:tag twice against floor=2 restores ONE image, counts two, and
# reports success with production still unable to pull the other one. Counting is only a
# non-vacuity guard if the things counted are different things.
n_distinct=$(jq -r '[.entries[] | select(.disposition == "required") | "\(.repo):\(.tag)"] | unique | length' "$TAGS_FROM" 2>/dev/null)
if [[ ! "$n_distinct" =~ ^[0-9]+$ ]] || (( n_distinct != n_required )); then
  die 1 "the manifest declares ${n_required} required entries but only ${n_distinct:-?} distinct repo:tag pairs. A duplicated entry would satisfy the floor while leaving an image unrestored."
fi

# NOTE the floor equality is asserted at the OUTCOME (bottom of this file), not here. Checking it
# in both places made the outcome assertion unreachable — a mutation deleting it survived the
# suite, because the declaration check fired first and masked it. The declaration checks above
# guard shapes that make the run meaningless before it starts; the floor is a statement about
# what was actually restored, so it belongs where that is known.

# classify <last-stderr-line> — the failure vocabulary.
#
# Classify on the LAST line, never the first and never the exit code: crane exits 1 for every
# failure class, and its FIRST line is the same
# `HEAD request failed, falling back on GET: …` for tag-absent, repo-absent AND DNS failure
# (measured 2026-08-05). rc and line 1 are both buckets, not diagnoses.
#
# There is deliberately NO `NAME_UNKNOWN` arm. GHCR emits it only from the TAGS api
# (`crane ls`); every call in this script is a manifest read (`crane digest`), which returns
# `MANIFEST_UNKNOWN` for an absent repo just as it does for an absent tag. An arm for it would
# be dead code. If a `crane ls` call is ever added here, its NAME_UNKNOWN falls to the UNKNOWN
# default below and exits 6 — loud and fail-closed, which is the safe direction.
classify() {
  local err="$1"
  case "$err" in
    *BLOB_UNKNOWN*|*"blob unknown"*)                                   echo BLOBMISSING ;;
    *MANIFEST_UNKNOWN*|*"manifest unknown"*)                           echo NOTFOUND ;;
    *UNAUTHORIZED*|*DENIED*|*"authentication required"*|*"denied:"*)   echo DENIED ;;
    # `*"EOF"*` was an UNANCHORED THREE-CHARACTER SUBSTRING. Any message containing those letters
    # anywhere — in a repo name, a tag, a digest's hex, a vendor sentence — was reclassified as a
    # retryable network fault, which downgrades exit 6's "loudest arm" guarantee into exit 3's
    # "retry, it'll probably clear". Go's transport emits this error as a whole word at the END of
    # the message, so anchor on that: `unexpected EOF` anywhere, or a message ENDING in EOF.
    *"no such host"*|*"dial tcp"*|*"connection refused"*|*"connection reset"*|\
    *"i/o timeout"*|*"TLS handshake"*|*"unexpected EOF"*|*EOF|\
    *"502 "*|*"503 "*|*"504 "*)                                        echo NETWORK ;;
    *) echo UNKNOWN ;;
  esac
}

# crane_capture <outfile> <errfile> <args...> — run crane, capturing stdout and stderr to files.
#
# Read the digest THROUGH A FILE, never `$(crane digest …)`. A retry helper's `::notice::` lands
# on stdout and would be captured AS the digest, manufacturing a bogus mismatch. Lifted from
# build-inngest-bootstrap-image.yml's mirror block, which records the same three properties.
crane_capture() {
  local out="$1" err="$2"; shift 2
  $CRANE "$@" >"$out" 2>"$err"
}

# last_err <errfile> — the classification input, injection-guarded.
#
# The `tr '\n' ' '` is a WORKFLOW-COMMAND INJECTION GUARD, not formatting. This is
# externally-influenced text from a registry and it is interpolated into `::error::` output
# below; GitHub parses workflow commands per LINE, so a newline followed by `::add-mask::` or
# `::error::` inside registry stderr would be EXECUTED. Collapsing newlines makes the whole
# capture a single un-parseable payload.
#
# `tail -n 1` is what makes this the LAST LINE rather than the last 400 BYTES, and the difference
# is not cosmetic: classify() substring-matches, so its FIRST case arm wins over the whole capture
# regardless of line order. A capture carrying `manifest unknown` on an earlier line and
# `authentication required` on the last classified NOTFOUND — which, for a CONDITIONAL entry, is a
# silent skip. A credential failure would have been recorded as "absent". The gate carries the
# identical fix; both were found by the mutation battery, because with short fixtures a byte-tail
# and a line-tail return the same string and no ordinary test can tell them apart.
last_err() {
  tail -c 400 "$1" 2>/dev/null | tail -n 1 | tr '\n' ' ' || true
}

# digest_of <file> — keep only a bare sha256 token.
digest_of() {
  grep -oE '^sha256:[0-9a-f]{64}$' "$1" 2>/dev/null | head -1 || true
}

WORK="$(mktemp -d)" || die 6 "could not create a scratch directory."
trap 'rm -rf "$WORK"' EXIT

# ── AUTHENTICATE. This is why the checks above are not decorative. ──────────────────────────
# Until this was caught at review, ZOT_PUSH_USER/ZOT_PUSH_TOKEN were validated non-empty and
# then NEVER USED: crane resolves credentials only through the Docker keychain
# (~/.docker/config.json), so every copy went out ANONYMOUSLY. Against a sink with
# `defaultPolicy: []` that is a guaranteed 401 -> DENIED -> exit 5, i.e. a gate that could
# never pass — the exact defect this whole change exists to remove, reintroduced in the engine
# that proves the pass condition.
#
# A private DOCKER_CONFIG under $WORK, not the ambient one: it is torn down with the scratch
# dir, it cannot leak the prd credential into a shared keychain another step would inherit, and
# it makes the rehearsal's THROWAWAY credential and the real run's PROD credential structurally
# incapable of being confused for one another.
export DOCKER_CONFIG="${WORK}/dockercfg"
mkdir -p "$DOCKER_CONFIG" || die 6 "could not create a private docker config directory."

# The sink is plain HTTP on loopback in BOTH modes — the throwaway listens directly, and the
# real target is `cloudflared access tcp` on 127.0.0.1 (the TLS leg is the Cloudflare Access
# edge). crane defaults to HTTPS for a host:port, so every call against the sink needs
# --insecure. The stubs in the suite hid this: they never spoke a real protocol.
SINK_TLS_FLAG="--insecure"
case "$TARGET" in
  127.0.0.1:*|localhost:*|"[::1]":*) ;;
  *) SINK_TLS_FLAG="" ;;   # a non-loopback sink must use TLS
esac

if ! $CRANE auth login "$TARGET" -u "$ZOT_PUSH_USER" -p "$ZOT_PUSH_TOKEN" $SINK_TLS_FLAG \
     >"$WORK/login.out" 2>"$WORK/login.err"; then
  die 5 "could not authenticate to the sink ${TARGET} as '${ZOT_PUSH_USER}'. crane: $(tail -c 300 "$WORK/login.err" 2>/dev/null | tr '\n' ' ')"
fi

# GHCR is a PRIVATE package set: an anonymous read 401s. Optional here because the caller may
# already hold a keychain entry (the release path does), but when the vars are supplied we log
# in explicitly rather than hoping an ambient one exists.
if [[ -n "${GHCR_USER:-}" && -n "${GHCR_TOKEN:-}" ]]; then
  if ! $CRANE auth login ghcr.io -u "$GHCR_USER" -p "$GHCR_TOKEN" \
       >"$WORK/ghlogin.out" 2>"$WORK/ghlogin.err"; then
    die 2 "could not authenticate to ghcr.io as '${GHCR_USER}'. crane: $(tail -c 300 "$WORK/ghlogin.err" 2>/dev/null | tr '\n' ' ')"
  fi
fi

restored=0
skipped=0

echo "registry-restore-from-ghcr: target=${TARGET} floor=${FLOOR} entries=$(jq -r '.entries | length' "$TAGS_FROM")"

n_entries=$(jq -r '.entries | length' "$TAGS_FROM")
i=0
while (( i < n_entries )); do
  repo=$(jq -r ".entries[$i].repo" "$TAGS_FROM")
  tag=$(jq -r ".entries[$i].tag" "$TAGS_FROM")
  disp=$(jq -r ".entries[$i].disposition" "$TAGS_FROM")
  i=$(( i + 1 ))

  src="ghcr.io/${repo}:${tag}"
  dst="${TARGET}/${repo}:${tag}"

  # ── source resolution ──────────────────────────────────────────────────────────────────────
  crane_capture "$WORK/src.out" "$WORK/src.err" digest "$src"
  src_digest="$(digest_of "$WORK/src.out")"
  if [[ -z "$src_digest" ]]; then
    err="$(last_err "$WORK/src.err")"
    cls="$(classify "$err")"
    case "$cls" in
      NOTFOUND)
        if [[ "$disp" == "conditional" ]]; then
          # A declared skip, not an abort. soleur-inngest-config is not published at GHCR — the
          # producing workflow (build-inngest-config-bundle.yml) is workflow_dispatch-only and
          # has never been run, which is the credential-INDEPENDENT evidence; an earlier draft
          # cited an uncredentialed `crane ls`, which cannot tell absent from not-visible. A gate
          # that required it would abort forever on a repo that does not exist — the new deadlock
          # this change exists to avoid. The floor counts only `required` entries, so a
          # conditional skip can never make the restore vacuous.
          echo "restore_entry repo=${repo} tag=${tag} disposition=conditional result=skipped_absent"
          skipped=$(( skipped + 1 ))
          continue
        fi
        # NOTE THE WORDING, it is load-bearing. GHCR returns MANIFEST_UNKNOWN for an absent tag,
        # an absent repo, AND a repo that exists but is not visible to this credential (measured
        # 2026-08-05 against a repo proven to exist, with credentials removed). Saying "the image
        # is gone" would name a cause this script did not measure — on the path that authorises
        # destroying production's only copy.
        die 2 "required source ${src} could not be resolved: absent, or NOT VISIBLE TO THIS CREDENTIAL — GHCR reports MANIFEST_UNKNOWN for both, so this does not prove the image is gone. Check the job's 'packages: read' permission before concluding the tag was deleted. crane: ${err}" ;;
      DENIED)
        die 2 "GHCR rejected this credential for ${src}. crane: ${err}" ;;
      NETWORK)
        die 2 "GHCR was unreachable while resolving ${src} (network/DNS). Nothing was copied. crane: ${err}" ;;
      *)
        die 6 "resolving ${src} failed in a way this script cannot classify, so it is neither 'absent' nor 'fine'. crane: ${err}" ;;
    esac
  fi

  # ── copy ───────────────────────────────────────────────────────────────────────────────────
  # Registry-to-registry and digest-preserving, so it needs no local image and cannot be
  # satisfied by a Docker image cache. Idempotent: crane skips blobs the destination already
  # holds, which is what makes a partial pass safely re-runnable.
  if ! crane_capture "$WORK/cp.out" "$WORK/cp.err" copy $SINK_TLS_FLAG "$src" "$dst"; then
    err="$(last_err "$WORK/cp.err")"
    cls="$(classify "$err")"
    case "$cls" in
      DENIED)  die 5 "the sink REJECTED this credential while copying ${dst}. This is an authorisation failure, not an availability one — retrying will not clear it. crane: ${err}" ;;
      NETWORK) die 3 "the sink was unavailable while copying ${dst} (this is the retryable code; a replaced host can outrun the tunnel's re-convergence). crane: ${err}" ;;
      NOTFOUND|BLOBMISSING) die 4 "copying ${dst} reported a missing object. crane: ${err}" ;;
      *)       die 6 "copying ${dst} failed in a way this script cannot classify. crane: ${err}" ;;
    esac
  fi

  # ── verification 1: digest parity ──────────────────────────────────────────────────────────
  # Assert it; never infer it from the copy's zero exit. An empty read counts as failure — a
  # failed capture yields "" and "" == "" would otherwise read as a match and certify nothing.
  crane_capture "$WORK/dst.out" "$WORK/dst.err" digest $SINK_TLS_FLAG "$dst"
  dst_digest="$(digest_of "$WORK/dst.out")"
  if [[ -z "$dst_digest" ]]; then
    err="$(last_err "$WORK/dst.err")"
    cls="$(classify "$err")"
    case "$cls" in
      NETWORK) die 3 "could not read ${dst} back from the sink (unavailable). crane: ${err}" ;;
      DENIED)  die 5 "the sink rejected this credential reading ${dst} back. crane: ${err}" ;;
      *)       die 4 "could not read ${dst} back after copying it, so the restore is UNVERIFIED. crane: ${err}" ;;
    esac
  fi
  if [[ "$src_digest" != "$dst_digest" ]]; then
    die 4 "digest parity FAILED for ${repo}:${tag} — ghcr=${src_digest} sink=${dst_digest}. A cloud-init @sha256 pin on this tag would not resolve against the restored registry."
  fi

  # ── verification 2: blob completeness ──────────────────────────────────────────────────────
  # The digest above proves the sink holds the MANIFEST. This proves it holds the BLOBS. See the
  # measured table in the header: without this, an evicted layer yields a green restore and a
  # `blob unknown` when the host later tries to pull it.
  if ! crane_capture "$WORK/val.out" "$WORK/val.err" validate $SINK_TLS_FLAG --remote "$dst"; then
    err="$(last_err "$WORK/val.err")"
    cls="$(classify "$err")"
    case "$cls" in
      NETWORK) die 3 "the sink became unavailable while validating ${dst}. crane: ${err}" ;;
      DENIED)  die 5 "the sink rejected this credential while validating ${dst}. crane: ${err}" ;;
      BLOBMISSING|NOTFOUND)
        die 4 "${dst} is BLOB-INCOMPLETE: its manifest resolves and its digest matches, but a layer is missing, so a host would fail this pull with 'blob unknown'. crane: ${err}" ;;
      *)       die 6 "validating ${dst} failed in a way this script cannot classify. crane: ${err}" ;;
    esac
  fi

  # ── verification 3: signature present in the target ────────────────────────────────────────
  # Not optional and not warned-about. ci-deploy.sh fetches the signature from the registry it
  # pulled from, so an image restored without its signature fails cosign verify on the host.
  sig_tag="sha256-${src_digest#sha256:}"
  crane_capture "$WORK/sigsrc.out" "$WORK/sigsrc.err" digest "ghcr.io/${repo}:${sig_tag}"
  if [[ -z "$(digest_of "$WORK/sigsrc.out")" ]]; then
    die 4 "no cosign signature (${sig_tag}) found at GHCR for ${repo}@${src_digest}. There is no unsigned-restore arm: a restored image whose signature is absent fails verification on the host. crane: $(last_err "$WORK/sigsrc.err")"
  fi
  if ! crane_capture "$WORK/sigcp.out" "$WORK/sigcp.err" copy $SINK_TLS_FLAG "ghcr.io/${repo}:${sig_tag}" "${TARGET}/${repo}:${sig_tag}"; then
    err="$(last_err "$WORK/sigcp.err")"
    case "$(classify "$err")" in
      NETWORK) die 3 "the sink was unavailable while copying the signature ${sig_tag}. crane: ${err}" ;;
      DENIED)  die 5 "the sink rejected this credential copying the signature ${sig_tag}. crane: ${err}" ;;
      *)       die 4 "the signature ${sig_tag} could not be copied for ${repo}. crane: ${err}" ;;
    esac
  fi
  crane_capture "$WORK/sigdst.out" "$WORK/sigdst.err" digest $SINK_TLS_FLAG "${TARGET}/${repo}:${sig_tag}"
  if [[ -z "$(digest_of "$WORK/sigdst.out")" ]]; then
    die 4 "the signature ${sig_tag} is not readable back from the sink, so ${repo}:${tag} is restored UNSIGNED. crane: $(last_err "$WORK/sigdst.err")"
  fi

  echo "restore_entry repo=${repo} tag=${tag} disposition=${disp} digest=${src_digest} result=restored_verified"
  # ONLY `required` entries count toward the floor, because FLOOR counts only required pins.
  # Counting every restored entry made a CORRECT over-restore look like corruption: once a
  # conditional pin becomes published, restoring 3 against FLOOR=2 exited 4 with "the registry
  # is NOT fully restored — do not deploy", about a registry that was fully restored. Caught at
  # review; the suite fixed the conditional as permanently absent, so no fixture reached it.
  if [[ "$disp" == "required" ]]; then
    restored=$(( restored + 1 ))
  else
    skipped=$(( skipped + 1 ))
  fi
done

# ── the non-vacuity floor, asserted on what was ACTUALLY restored ────────────────────────────
# The check at the top validated the DECLARATION. This one validates the OUTCOME: it is what
# makes "the loop ran and nothing went wrong" different from "the required set is present and
# verified in the target".
if (( restored != FLOOR )); then
  die 4 "restored ${restored} references but the declared floor is ${FLOOR}. The registry is NOT fully restored; do not treat this run as authorising anything."
fi
if (( restored == 0 )); then
  die 4 "restored ZERO references. Every loop above completed without error, which is exactly how a vacuous restore reports success — refusing to."
fi

echo "restore_summary target=${TARGET} restored=${restored} skipped=${skipped} floor=${FLOOR} result=ok"
exit 0
