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
# The signature is copied, not re-created. GHCR carries it at an OCI referrers tag `sha256-<hex>`.
# CORRECTED 2026-08-10 (#7410), measured against soleur-web-platform:v0.249.4 — the earlier text
# here said the TAG's artifactType is the bundle type. It is not: the tag resolves to an OCI image
# INDEX with neither `.config` nor `.layers`, and it is the index's CHILD that carries
# `artifactType: application/vnd.dev.sigstore.bundle.v0.3+json`. Reading that sentence as though
# the tag were a plain manifest is what shipped a checker that fail-closed on a healthy signature
# and refused the recut on run 31392395980. It is still a Sigstore BUNDLE binding to the image
# DIGEST, and still not the legacy simple-signing payload,
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
# `.entries` MUST BE AN ARRAY, and this is load-bearing rather than defensive. `n_required`
# is an AGGREGATE read (`.entries[] | select(...)`) while the restore loop below is a
# PER-INDEX read (`.entries[$i]`). jq's `.[]` iterates an OBJECT's values too, so an object
# `.entries` yields n_required=1 while every indexed read errors to empty — the loop restores
# nothing, `restored` stays 0, and with `floor: 0` the outcome check `restored != FLOOR` is
# false. Measured: without this guard the engine prints `restored=0 … result=ok` and exits 0,
# a vacuous restore reporting success. Two independent reads of one field must agree on its
# shape before either is trusted.
if ! jq -e '.entries | type == "array"' "$TAGS_FROM" >/dev/null 2>&1; then
  die 1 "the manifest's .entries is not a JSON array. The floor is counted with an aggregate read and the restore loop uses an indexed read; on a non-array those two disagree silently and a restore that copied nothing can report success."
fi

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
    # A layer whose declared mediaType disagrees with its bytes. Deliberately classified AFTER
    # the network and credential arms so their retry semantics (3/5) keep precedence.
    #
    # This used to fall to UNKNOWN -> exit 6 (could-not-classify), which is how #7378 presented:
    # `crane validate --remote <index>` walks every child and tries to gunzip every layer, so a
    # buildx ATTESTATION child (one `application/vnd.in-toto+json` layer, never compressed) failed
    # here and took the whole D10 A2 predicate down with it. Verification 2 now verifies per child
    # and never gunzips an attestation layer, which removes THAT instance.
    #
    # It does NOT make this arm mean "the content is corrupt". crane calls Uncompressed()
    # unconditionally, so `gzip: invalid header` is what it emits for ANY layer that is legitimately
    # not gzip — an uncompressed `…tar` or `…tar+zstd` platform layer produces it on perfectly
    # intact bytes. Measured against a real registry: the identical string comes back for an intact
    # attestation layer. So this arm names TWO causes the engine cannot tell apart, and the message
    # must say so rather than assert corruption. Exit 4 is still right (verification is unproven
    # either way); exit 6 stays reserved for shapes the engine genuinely cannot name.
    # Single pattern on purpose: a `*"unexpected EOF reading gzip"*` alternative would be DEAD —
    # the NETWORK arm's `*"unexpected EOF"*` above already matches it.
    *"gzip: invalid header"*)                                          echo LAYERFORMAT ;;
    # A blob that IS present but whose bytes do not hash to the digest that addressed them. crane
    # verifies at EOF and emits this; it previously fell to UNKNOWN -> exit 6 ("the engine is
    # confused") when it is in fact the single most definitive do-NOT-deploy signal there is.
    *"error verifying sha256 checksum"*)                               echo CONTENTMISMATCH ;;
    *) echo UNKNOWN ;;
  esac
}

# crane_capture <outfile> <errfile> <args...> — run crane, capturing stdout and stderr to files.
#
# Read the digest THROUGH A FILE, never `$(crane digest …)`. A retry helper's `::notice::` lands
# on stdout and would be captured AS the digest, manufacturing a bogus mismatch. Lifted from
# build-inngest-bootstrap-image.yml's mirror block, which records the same three properties.
# `</dev/null` is not decoration: verification 2 drives crane from inside `while read … <<< "$list"`
# loops, so a subcommand that ever consumed stdin would eat the remaining children/blobs and the
# loop would end early — verifying one member and reporting success for all of them. crane does not
# read stdin today; pinning it here means a future version that does cannot silently truncate the
# only enumeration that proves blob completeness.
crane_capture() {
  local out="$1" err="$2"; shift 2
  $CRANE "$@" >"$out" 2>"$err" </dev/null
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
  # The trailing `sed` is NOT tidiness — it is what makes the END-ANCHORED classifier arms
  # reachable at all. `tail -n 1` keeps the line's terminating newline, `tr` rewrites it to a
  # trailing SPACE, and `$( )` strips trailing NEWLINES but not spaces. So a capture ending
  # "…: EOF\n" arrives as "…: EOF " and the `*EOF` arm below — an arm this PR added — never
  # matches. Measured: with the space, a sink EOF classifies UNKNOWN and the engine exits 6
  # (not retryable) instead of 3 (retryable), AFTER the destroy, with the store empty. The
  # suite could not see it because every `.err` fixture is written with `printf '%s'`, i.e.
  # without the terminating newline real crane emits.
  tail -c 400 "$1" 2>/dev/null | tail -n 1 | tr '\n' ' ' | sed 's/[[:space:]]*$//' || true
}

# digest_of <file> — keep only a bare sha256 token.
digest_of() {
  grep -oE '^sha256:[0-9a-f]{64}$' "$1" 2>/dev/null | head -1 || true
}

# ref_repo <ref> — the repository part of an image reference.
#
# Strip a `@sha256:…` digest first, then a trailing `:tag` — but ONLY when the colon falls after
# the LAST `/`. The sink is `127.0.0.1:5555/jikig-ai/soleur-web-platform`, so the obvious
# `${ref%:*}` would eat the PORT on any ref that carries no tag.
ref_repo() {
  local r="${1%%@*}"
  case "${r##*/}" in
    *:*) printf '%s' "${r%:*}" ;;
    *)   printf '%s' "$r" ;;
  esac
}

# manifest_kind <manifest-json-file> — the ONE answer to "what shape is this manifest?".
#
# Single definition on purpose, for the reason this file already gives about verify_die: duplicating
# the case block per call site is how the arms drift. #7410's first cut proved it — it added a
# second classifier 250 lines from this one, described it in a comment as "mirroring verification
# 2's classification", and the two disagreed on three real inputs within the same commit:
#
#   bytes                  second copy   verification 2
#   {"manifests":null}     malformed     manifest
#   {}                     empty         manifest
#   {"schemaVersion":2}    empty         manifest
#
# `has("manifests")` distinguishes an explicitly-serialised null from an absent key; the
# `(.manifests|type) == "null"` form cannot. Both directions failed closed, so nothing was unsafe —
# but a shape vocabulary that answers the same question two ways is the seed of the next #7378, and
# this is the file that forbids exactly that duplication.
#
# Emits one of: index | manifest | malformed | empty | unparseable. Never fails; `unparseable` is
# the jq-error case, so the caller branches on a value rather than on an rc.
manifest_kind() {
  jq -r '
      if   (.manifests | type) == "array"      then "index"
      elif has("manifests")                    then "malformed"
      elif (has("config") or has("layers"))    then "manifest"
      else "empty" end' "$1" 2>/dev/null || printf 'unparseable\n'
}

# verify_blobs_of <sink-repo> <manifest-ref> <what> [depth] — prove the SINK holds every blob the
# manifest at <manifest-ref> declares (its config and every layer), walking one level of index
# indirection.
#
# `depth` is the artifact-graph nesting level and MUST be threaded by every caller that is already
# inside an index walk. #7410's first cut defaulted it at the attestation call site, which reset the
# counter to 0 one level down and let the function walk a SECOND index level while its own comment
# claimed one — turning a shape `origin/main` refused (`declares no blobs`, exit 4) into a PASS,
# measured. The parameter is not a convenience; omitting it is the bug.
#
# Presence AND integrity, not merely presence: `crane blob` streams the whole body and
# go-containerregistry verifies the content digest at EOF, so a blob that is present but whose
# bytes do not hash to the digest addressing it fails here too (classify() maps that to
# CONTENTMISMATCH -> exit 4). It never DECOMPRESSES, which is what makes it correct for layer
# mediaTypes that are plain JSON and never gzipped — `application/vnd.in-toto+json` on a buildx
# attestation child, and the cosign payload on a signature. Handing either of those to
# `crane validate` is #7378.
#
# The body is discarded to /dev/null: only the exit code is consumed, and a provenance blob can
# carry build-time secrets that should not be materialised on the runner's disk.
verify_blobs_of() {
  local repo="$1" ref="$2" what="$3" depth="${4:-0}"
  local out="$WORK/vb.${depth}.out" err="$WORK/vb.${depth}.err" jqerr="$WORK/vb.${depth}.jqerr"
  local blberr="$WORK/vb.${depth}.blob.err"
  local kind blobs b n_declared n_children n_blobs n_layers c_digest children

  if ! crane_capture "$out" "$err" manifest $SINK_TLS_FLAG "$ref"; then
    verify_die "$what" "$err"
  fi

  # A cosign signature is NOT reliably a plain manifest. Measured against GHCR 2026-08-10, the
  # referrers tag `sha256-<hex>` of soleur-web-platform:v0.249.4 resolves to an OCI image INDEX
  # whose single child carries `artifactType: application/vnd.dev.sigstore.bundle.v0.3+json`; the
  # index itself has neither `.config` nor `.layers`. A config+layers-only enumeration therefore
  # finds nothing there and reports "declares no blobs" -- a fail-closed abort on a perfectly
  # healthy signature, which is what refused the recut on run 31392395980.
  kind="$(manifest_kind "$out")"

  case "$kind" in
    index)
      # One level only, and `depth` is threaded by every caller inside a walk (see the header).
      if (( depth > 0 )); then
        die 4 "${what} is an index nested inside another index. This restore verifies one level of indirection, so a deeper nest is unverified — failing closed rather than reporting a pass it did not establish."
      fi
      # rc-checked, matching the identical read in verification 2. The `2>/dev/null || echo 0` this
      # replaces was dead defensively (the arm has already proven `.manifests` is an array) and
      # defaulted to the ONE value that satisfies the equality below when the walk also finds
      # nothing — a fail-open direction guarded only by the ordering of two adjacent lines.
      if ! n_declared="$(jq -r '(.manifests // []) | length' "$out" 2>"$jqerr")"; then
        die 4 "${what}: its child count could not be read, so no completeness claim is possible. jq: $(last_err "$jqerr")"
      fi
      if ! children="$(jq -r '(.manifests // [])[] | [(.digest // "-")] | @tsv' "$out" 2>"$jqerr")"; then
        die 4 "${what}: its child list could not be fully enumerated, so an unknown number of children were never checked. jq: $(last_err "$jqerr")"
      fi
      # Pre-loop, mirroring verification 2: `<<< ""` yields ONE blank iteration, so without this a
      # zero-child index reaches the loop and the in-loop guard has to `continue` past it — which is
      # what forced the empty-digest row to be skipped rather than named.
      [[ -n "$children" ]] || \
        die 4 "${what} is an index with no children, so it references nothing a host could pull."
      n_children=0
      while IFS=$'\t' read -r c_digest; do
        n_children=$((n_children + 1))
        # `-n` as well as `!= "-"`: jq's `//` replaces null and false, NOT "", so an explicitly
        # empty digest string sails past the sentinel. Previously this row was `continue`d and the
        # count guard reported "the remainder were never verified" — naming a truncation that had
        # not happened, on the path that authorises the destroy.
        [[ "$c_digest" != "-" && -n "$c_digest" ]] || \
          die 4 "${what}: child ${n_children} declares no digest, so it cannot be addressed or verified."
        verify_blobs_of "$repo" "${repo}@${c_digest}" "child ${c_digest} of ${what}" "$((depth + 1))"
      done <<< "$children"
      # Equality, not `> 0`: a truncated walk that checked one child of three must not read as a
      # verified index.
      (( n_children == n_declared )) || \
        die 4 "${what}: enumerated ${n_children} children but the index declares ${n_declared}. The remainder were never verified."
      ;;
    manifest)
      # rc, never `|| true`: jq's `.layers[]` streams, so a shape fault partway emits a TRUNCATED
      # list that would otherwise pass the non-empty check with the remaining blobs never checked.
      #
      # `// "-"` on EVERY digest, and a count equality below, for a measured reason: the previous
      # form emitted bare digests, `$( )` strips trailing newlines, and the loop `continue`d on
      # empties — so `{"config":{"digest":"sha256:aaa"},"layers":[{"digest":""},{"digest":""}]}`
      # verified ONE of three declared blobs and reported the manifest complete. On the signature
      # path that is A2 going green with the cosign payload never fetched.
      #
      # The config slot is CONDITIONAL, and that word is load-bearing. An unconditional
      # `[(.config.digest // "-")]` emits a row even when the manifest has no `config` key at all,
      # while the count below is conditional — so a perfectly healthy config-less manifest
      # (`{"layers":[{"digest":"sha256:aa"}]}`) produced rows `-`,`sha256:aa` against a declared
      # count of 1, and died with "blob 1 declares no digest" about a blob the engine's own jq
      # program had invented. That is #7379's defect exactly — a healthy artifact named as
      # defective because the checker's enumeration was wrong — reintroduced by the commit fixing
      # it. The stream and the count must be the same predicate.
      if ! blobs="$(jq -r '[(if has("config") then (.config.digest // "-") else empty end)] + [(.layers // [])[] | (.digest // "-")] | .[]' "$out" 2>"$jqerr")"; then
        die 4 "${what}: its blob list could not be fully enumerated, so an unknown number of blobs were never checked. jq: $(last_err "$jqerr")"
      fi
      if ! n_declared="$(jq -r '((if has("config") then 1 else 0 end)) + ((.layers // []) | length)' "$out" 2>"$jqerr")"; then
        die 4 "${what}: its blob count could not be read, so no completeness claim is possible. jq: $(last_err "$jqerr")"
      fi
      [[ -n "$blobs" ]] || \
        die 4 "${what} declares no blobs, so its presence cannot be verified."
      # A LAYER, not merely a blob. This is the difference between a real check and a ceremonial
      # one, and the config blob is exactly why:
      #
      #   the sigstore bundle child's config is `application/vnd.oci.empty.v1+json`, digest
      #   sha256:44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a — the hash of
      #   `{}`. Every registry holds it by construction; the test suite hardcodes it.
      #
      # So a `has("config") or has("layers")` classification let a signature child whose bundle
      # LAYER had been evicted verify GREEN by fetching a universally-present two-byte blob. The
      # payload `ci-deploy.sh` hands to `cosign verify` would be gone and A2 would report the
      # restore complete — defeating the entire purpose of verifying the signature's blobs, which
      # is the obligation this arm exists to discharge.
      #
      # The evicted-blob test models a layer that is unFETCHABLE. This models a layer that is
      # ABSENT, and nothing else in the engine distinguishes them.
      if ! n_layers="$(jq -r '(.layers // []) | length' "$out" 2>"$jqerr")"; then
        die 4 "${what}: its layer count could not be read, so no completeness claim is possible. jq: $(last_err "$jqerr")"
      fi
      (( n_layers > 0 )) || \
        die 4 "${what} declares NO layers, so it carries no payload. A config alone is not evidence the artifact is intact — for a cosign signature that config is the well-known empty blob (sha256:44136fa3...aff8a) every registry holds by construction."
      n_blobs=0
      while IFS= read -r b; do
        n_blobs=$((n_blobs + 1))
        [[ "$b" != "-" && -n "$b" ]] || \
          die 4 "${what}: blob ${n_blobs} declares no digest, so it cannot be addressed or verified."
        if ! crane_capture /dev/null "$blberr" blob $SINK_TLS_FLAG "${repo}@${b}"; then
          verify_die "the blob ${b} of ${what}" "$blberr"
        fi
      done <<< "$blobs"
      (( n_blobs == n_declared )) || \
        die 4 "${what}: verified ${n_blobs} blobs but the manifest declares ${n_declared}. The remainder were never fetched."
      ;;
    malformed)
      die 4 "${what}: its manifest carries a \`manifests\` field that is not an array, so it is neither a readable index nor a plain manifest. Nothing about it was verified."
      ;;
    empty)
      die 4 "${what} declares neither children nor blobs, so its presence cannot be verified."
      ;;
    unparseable)
      die 4 "${what}: its manifest could not be parsed, so nothing about it was verified."
      ;;
    *)
      # Reached only if manifest_kind() grows a value this case block does not know. Say exactly
      # that, rather than asserting something about the manifest's contents that was never read.
      die 4 "${what}: its manifest classified as an unrecognised shape (${kind}), so nothing about it was verified."
      ;;
  esac
}

# verify_die <what> <errfile> — the ONE classifier for every verification-2 read.
#
# Single definition on purpose: verification 2 now issues several kinds of read (index manifest,
# child manifest, child validate, attestation blob) and each one must map the SAME crane failure
# to the SAME operator action. Duplicating the case block per call site is how the arms drift.
verify_die() {
  local what="$1" err cls
  err="$(last_err "$2")"
  cls="$(classify "$err")"
  case "$cls" in
    NETWORK) die 3 "the sink became unavailable while verifying ${what}. crane: ${err}" ;;
    DENIED)  die 5 "the sink rejected this credential while verifying ${what}. crane: ${err}" ;;
    # Split on purpose. Collapsing these into one sentence produced a message that asserted "the
    # manifest resolves and its digest matches" at the two call sites where the MANIFEST READ is
    # what failed — naming a cause the engine had just disproved, on the path that authorises
    # destroying production's only copy.
    NOTFOUND)
      die 4 "${what} did NOT resolve at the sink: the registry reports it as unknown. Blob completeness is unproven — do NOT deploy. crane: ${err}" ;;
    BLOBMISSING)
      die 4 "${what} is BLOB-INCOMPLETE: a blob it references is missing from the sink, so a host would fail this pull with 'blob unknown'. crane: ${err}" ;;
    CONTENTMISMATCH)
      die 4 "${what} is CORRUPT AT THE SINK: a blob is present but its bytes do not hash to the digest that addressed them. This is not an eviction and re-running will not fix it. Do NOT deploy. crane: ${err}" ;;
    LAYERFORMAT)
      die 4 "${what}: crane could not decompress a layer as gzip. This means ONE OF TWO THINGS and the engine cannot tell them apart — (a) the layer's bytes really do disagree with its declared mediaType (store corruption), or (b) the layer is legitimately not gzip (an uncompressed or zstd layer, or an attestation-shaped child this engine failed to classify), which is a VALIDATOR artifact and not a store problem. Discriminate before acting: re-run the identical check against the SOURCE, which this engine never writes to — 'crane validate --remote ghcr.io/<repo>@<child-digest>'. If GHCR fails the same way, the store is fine and this is #7378's class returning; file it. If GHCR passes, the sink copy is bad — do NOT deploy. crane: ${err}" ;;
    *)       die 6 "verifying ${what} failed in a way this script cannot classify. crane: ${err}" ;;
  esac
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

  # ── verification 2: blob completeness, PER CHILD ───────────────────────────────────────────
  # The digest above proves the sink holds the MANIFEST. This proves it holds the BLOBS. See the
  # measured table in the header: without this, an evicted layer yields a green restore and a
  # `blob unknown` when the host later tries to pull it.
  #
  # Every read below is against the SINK, never GHCR — the property under test is "the sink holds
  # the blobs", and a read that fell back to the source would certify the wrong registry.
  #
  # #7378: this used to be one `crane validate --remote "$dst"` over the whole reference. crane
  # walks an index's children and tries to GUNZIP every layer, so a buildx ATTESTATION child —
  # one `application/vnd.in-toto+json` layer, which is plain JSON and never compressed — failed
  # with `gzip: invalid header`. Reproduced directly against GHCR (a registry this engine never
  # WRITES — it does read from it, on every entry, via `crane digest` and `crane copy`), so it is
  # a validator false positive, not corruption. It made the D10 A2 predicate structurally
  # unpassable and the recut unfireable during a live registry outage.
  #
  # The fix NARROWS the check, it does not skip anything: platform children keep the full
  # `crane validate --remote`, and attestation children have every blob they declare verified for
  # PRESENCE via `crane blob`. An attestation child whose blob is absent still fails.
  #
  # Read the index BY DIGEST, not by tag. `crane manifest <tag>` does NOT verify the returned
  # bytes (go-containerregistry: "Do nothing for tags; I give up."), whereas a digest ref makes
  # `fetchManifest` hash the body and reject a mismatch. The whole-ref `crane validate` this
  # replaced supplied that byte-check via `validateIndexManifest`; reading by tag would have
  # dropped the sink index's only integrity check AND re-resolved the tag a second time, so the
  # children verified might not belong to the manifest verification 1 just proved parity for.
  dst_repo="$(ref_repo "$dst")"
  if ! crane_capture "$WORK/man.out" "$WORK/man.err" manifest $SINK_TLS_FLAG "${dst_repo}@${dst_digest}"; then
    verify_die "the manifest of ${dst}" "$WORK/man.err"
  fi

  # Fail CLOSED on anything we cannot parse. FOUR states, and the fourth is the one an earlier
  # revision got wrong: `.manifests` PRESENT BUT NOT AN ARRAY (`{"manifests":{"a":1}}`) is neither
  # a plain manifest nor an enumerable index, and a two-way `array ? index : manifest` test folded
  # it into the plain-manifest branch — handing a malformed index straight back to the whole-ref
  # `crane validate` this change exists to stop calling. Fail direction was closed (it would gunzip
  # and abort), but that is exactly the unfireable-gate condition of #7378.
  dst_kind="$(manifest_kind "$WORK/man.out")"
  case "$dst_kind" in
    index|manifest) ;;
    malformed)
      die 4 "the sink returned a manifest for ${dst} whose .manifests field is present but is not an array, so it is neither a plain manifest nor an enumerable index. Blob completeness is unproven — do NOT deploy." ;;
    empty)
      # Distinct from `unparseable`, and the distinction is the point: this body IS valid JSON and
      # simply declares neither children nor blobs. Reporting it as a parse failure would name a
      # cause the code did not measure, and would send the operator to the wrong runbook row.
      #
      # Two shapes changed arm when this site adopted manifest_kind(): `{}` and `{"schemaVersion":2}`
      # previously classified `manifest` and were handed to the whole-ref validate. Neither is an
      # image; dying here is the correct direction, and it is now the SAME answer verify_blobs_of
      # gives for the same bytes.
      die 4 "the sink returned a manifest for ${dst} that declares neither children nor blobs, so it is not an image any host could pull. Blob completeness is unproven — do NOT deploy." ;;
    *)
      # A NAMED condition, so NOT exit 6. Exit 6 is reserved for shapes the engine cannot name,
      # and the runbook's exit-6 row tells the operator such a shape is a defect to file rather
      # than a store to distrust — which is the wrong instruction for a sink serving non-JSON.
      die 4 "the sink returned a manifest for ${dst} that could not be parsed as JSON, so blob completeness is unproven. Do NOT deploy." ;;
  esac

  if [[ "$dst_kind" == "manifest" ]]; then
    # Single manifest (this is what soleur-inngest-bootstrap is). Unchanged behaviour.
    if ! crane_capture "$WORK/val.out" "$WORK/val.err" validate $SINK_TLS_FLAG --remote "$dst"; then
      verify_die "$dst" "$WORK/val.err"
    fi
  else
    # SENTINEL every field. `@tsv` emits an EMPTY field for an absent key, tab is IFS-WHITESPACE,
    # and bash `read` collapses runs of IFS whitespace — so `digest<TAB><TAB>unknown` (an
    # attestation child with no annotation) parsed as type="unknown", arch="", and the
    # `arch == "unknown"` disjunct below became unreachable exactly when it was the only signal.
    # That handed the in-toto child to `crane validate` and reproduced #7378 verbatim. A "-"
    # placeholder cannot appear in a real digest, mediaType, annotation or architecture, so no
    # field is ever empty and no collapse is possible.
    # NEVER `|| true` here. `.manifests[]` STREAMS, so a shape fault in element k emits elements
    # 1..k-1 and then exits 5 — swallowing that rc yields a TRUNCATED child list that passes every
    # downstream guard while children k..n are silently never verified. Capture the rc instead.
    if ! children="$(jq -r '(.manifests // [])[] | [(.digest // "-"), (.mediaType // "-"), (.annotations["vnd.docker.reference.type"] // "-"), (.platform.architecture // "-")] | @tsv' "$WORK/man.out" 2>"$WORK/man.jqerr")"; then
      die 4 "${dst}: the sink's index could not be fully enumerated — jq failed partway, so an unknown number of children were never seen. Blob completeness is unproven; do NOT deploy. jq: $(last_err "$WORK/man.jqerr")"
    fi
    if ! n_declared="$(jq -r '(.manifests // []) | length' "$WORK/man.out" 2>"$WORK/man.jqerr")"; then
      die 4 "${dst}: could not read the sink index's child count. jq: $(last_err "$WORK/man.jqerr")"
    fi
    [[ -n "$children" ]] || \
      die 4 "${dst} is an image index whose child list is empty, so no child could be verified."

    n_children=0
    n_platform=0
    while IFS=$'\t' read -r c_digest c_mt c_type c_arch; do
      [[ "$c_digest" != "-" && -n "$c_digest" ]] || \
        die 4 "${dst} declares an index child with no digest, so that child cannot be addressed or verified."
      n_children=$(( n_children + 1 ))
      # A child that is ITSELF an index would be handed to `crane validate` below, which walks its
      # children and gunzips their layers — #7378, one level down. buildx does not emit these
      # today; fail closed rather than recurse into the exact defect this change removes.
      case "$c_mt" in
        *"image.index.v1+json"|*"manifest.list.v2+json")
          die 4 "${dst} contains a NESTED index child ${c_digest} (${c_mt}), which this engine does not verify. Blob completeness is unproven — do NOT deploy." ;;
      esac
      # Detect attestation children by EITHER signal, so a change to one does not silently
      # reclassify an attestation as a real platform image. ASSUMPTION, not a measured invariant:
      # both signals come from the same BuildKit attestation-storage convention. The cost if it is
      # wrong in the other direction — a genuine platform child declaring `architecture: unknown` —
      # is that it gets blob-presence verification instead of decompression checking.
      if [[ "$c_type" == "attestation-manifest" || "$c_arch" == "unknown" ]]; then
        # depth 1, NOT the default: this call is already one level inside the image index's walk.
        # Defaulting it reset the counter and let verify_blobs_of walk a SECOND index level, which
        # turned a shape origin/main refused into a PASS (measured, #7410 review). The parent's
        # declared mediaType is not covered by the child's content digest, so a child that declares
        # image.manifest.v1+json and serves an index body reaches here; at depth 1 it fails closed.
        verify_blobs_of "$dst_repo" "${dst_repo}@${c_digest}" "the attestation manifest ${c_digest} of ${dst}" 1
      else
        n_platform=$(( n_platform + 1 ))
        if ! crane_capture "$WORK/val.out" "$WORK/val.err" validate $SINK_TLS_FLAG --remote "${dst_repo}@${c_digest}"; then
          verify_die "the ${c_arch} child ${c_digest} of ${dst}" "$WORK/val.err"
        fi
      fi
    done <<< "$children"

    # Counting is only a non-vacuity guard if it can detect PARTIAL enumeration. `> 0` cannot:
    # it passes when one child of five was verified. Compare against what the index DECLARES.
    (( n_children == n_declared )) || \
      die 4 "${dst} declares ${n_declared} index children but only ${n_children} were verified, so blob completeness is unproven."
    # An index carrying only attestation children has no image a host could pull. Presence-only
    # verification of provenance metadata must never read as "the pull path is restored".
    (( n_platform > 0 )) || \
      die 4 "${dst} is an image index with ${n_children} children and NO platform image among them, so there is nothing a host could pull."
  fi

  # ── verification 3: signature present in the target ────────────────────────────────────────
  # Not optional and not warned-about. ci-deploy.sh fetches the signature from the registry it
  # pulled from, so an image restored without its signature fails cosign verify on the host.
  sig_tag="sha256-${src_digest#sha256:}"
  crane_capture "$WORK/sigsrc.out" "$WORK/sigsrc.err" digest "ghcr.io/${repo}:${sig_tag}"
  if [[ -z "$(digest_of "$WORK/sigsrc.out")" ]]; then
    # CLASSIFY, like every other read in this file. Unclassified, this arm reported "no cosign
    # signature found at GHCR" for ANY failure to read it — a 503, a DNS blip, a revoked
    # credential — naming a cause it did not measure, on the path that authorises destroying
    # production's only copy. It is also an arm where the mislabel changes the OPERATOR ACTION:
    # exit 4 is documented NOT retryable and the restore job breaks out of its backoff on it, so a
    # transient GHCR fault became "the signature is absent, do not deploy" and suppressed the
    # retry that would have cleared it. Source-side faults take 2, matching the source-resolution
    # block above; only a genuine absence stays 4.
    err="$(last_err "$WORK/sigsrc.err")"
    case "$(classify "$err")" in
      NETWORK) die 2 "GHCR was unreachable reading the signature ${sig_tag} for ${repo} (network/DNS). This does NOT mean the signature is absent. crane: ${err}" ;;
      DENIED)  die 2 "GHCR rejected this credential reading the signature ${sig_tag} for ${repo}. This does NOT mean the signature is absent — check the job's 'packages: read' permission. crane: ${err}" ;;
      *)       die 4 "no cosign signature (${sig_tag}) found at GHCR for ${repo}@${src_digest}. There is no unsigned-restore arm: a restored image whose signature is absent fails verification on the host. crane: ${err}" ;;
    esac
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
    # Classified for the same reason as the source-side read, and note the asymmetry it closes:
    # the signature COPY sitting BETWEEN these two reads already classified NETWORK->3 and
    # DENIED->5, while both reads bracketing it went unconditionally to 4. So a sink that became
    # unavailable one call later reported "restored UNSIGNED" at a NON-retryable code —
    # post-destroy — for a fault the adjacent call would have called retryable.
    err="$(last_err "$WORK/sigdst.err")"
    case "$(classify "$err")" in
      NETWORK) die 3 "the sink became unavailable reading the signature ${sig_tag} back for ${repo}. This does NOT mean the image is unsigned; it is the retryable code. crane: ${err}" ;;
      DENIED)  die 5 "the sink rejected this credential reading the signature ${sig_tag} back for ${repo}. crane: ${err}" ;;
      *)       die 4 "the signature ${sig_tag} is not readable back from the sink, so ${repo}:${tag} is restored UNSIGNED. crane: ${err}" ;;
    esac
  fi

  # The read-back above is `crane digest` — a HEAD against the MANIFEST endpoint. It proves the
  # signature manifest resolves; it proves nothing about the payload blob. That is the identical
  # "a manifest can outlive its layers under zot gc+dedupe" trap this file's header documents at
  # length for image layers, and which verification 2 now defends against per child — left
  # undefended on the one artifact `ci-deploy.sh` fetches at deploy time to run `cosign verify`.
  #
  # Before this, A2 could go green over a signature whose blob was evicted, and the host would
  # then fail cosign verify with no fallback. Tightening verification 2 without this made the
  # gap WORSE in the reporting sense: "every child's blobs verified" is a materially stronger
  # claim, and leaving the signature arm loose sharpens the misrepresentation it carries.
  #
  # PARITY FIRST, then walk from a DIGEST ref.
  #
  # An earlier revision read the signature at its referrers TAG and justified it in this comment
  # with "there is no digest to pin it by". That was false: both digests are read above — GHCR's at
  # the source read, the sink's at the read-back — and both were tested for emptiness and thrown
  # away. So the walk was rooted at an unauthenticated tag, and content-addressing every child
  # below it bought integrity relative to a root nobody had checked. Wrong root, wrong children,
  # each one verified perfectly. This file already spells out why a tag read cannot self-verify
  # (a tag carries no expected digest) and already reads the IMAGE index by digest for exactly
  # that reason; the signature — the one artifact ci-deploy.sh feeds to cosign verify — was the
  # arm left on the weaker read.
  sig_src_digest="$(digest_of "$WORK/sigsrc.out")"
  sig_dst_digest="$(digest_of "$WORK/sigdst.out")"
  [[ "$sig_src_digest" == "$sig_dst_digest" ]] || \
    die 4 "the signature ${sig_tag} for ${repo}:${tag} differs between GHCR (${sig_src_digest}) and the sink (${sig_dst_digest}). The sink is serving a different signature than the one GHCR published — do NOT deploy."

  # Now the root is byte-verified: crane hashes the body of a digest ref and rejects a mismatch, so
  # the children enumerated below are provably the ones GHCR's signature declares. `crane blob`
  # never decompresses, so the cosign payload layer cannot trip the #7378 gunzip class.
  verify_blobs_of "${TARGET}/${repo}" "${TARGET}/${repo}@${sig_dst_digest}" \
    "the cosign signature ${sig_tag} of ${repo}:${tag}"

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
