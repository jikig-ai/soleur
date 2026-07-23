#!/usr/bin/env bash
#
# inngest-config-bundle-pack.sh — deterministic packager for the ADR-135 pull-based
# signed config-refresh channel (#6780). CI-side PRODUCER; runs in the ephemeral GitHub
# Actions runner (build-inngest-config-bundle.yml), never on the host.
#
# WHAT IT DOES: given a monotonic VERSION integer, an output directory, and the host-executed
# refresh-set `*.sh` files, it stages the files and emits a `manifest.txt`:
#
#     VERSION=<n>
#     <sha256>  <basename>          (one line per refresh-set file, LC_ALL=C-sorted by basename)
#
# `manifest.txt` is the SIGNED BLOB — the workflow runs `cosign sign-blob manifest.txt` (keyless)
# next. This is what makes the monotonic VERSION a SIGNED field (HARD-2): the host reads VERSION
# ONLY from the manifest AFTER `cosign verify-blob` succeeds, never from an OCI tag/annotation or
# the Doppler pointer. The per-file sha256 lines bind the refresh-set file contents into the same
# signed bytes, so a swapped file fails the host's per-file check.
#
# DETERMINISM (load-bearing — a non-reproducible manifest defeats digest coherence, ADR-128):
# no timestamps, LC_ALL=C-sorted file order, basename keys. Two runs over the same inputs at the
# same VERSION produce byte-identical output.
#
# FAIL-CLOSED (this is the producer half of HARD-10): a non-integer/≤0 VERSION, a missing/
# unreadable input, a duplicate basename, or zero inputs is a hard non-zero exit — never a
# best-effort partial bundle. `set -euo pipefail` throughout.
#
# Run (local, hermetic): bash inngest-config-bundle-pack.sh 7 /tmp/out fileA.sh fileB.sh
# Tested by: inngest-config-bundle-pack.test.sh (registered in infra-validation.yml).

set -euo pipefail

usage() {
  echo "usage: $0 <version:positive-integer> <output-dir> <refresh-set-file>..." >&2
  exit 2
}

[[ $# -ge 3 ]] || usage

VERSION="$1"
OUT_DIR="$2"
shift 2

# VERSION must be a positive integer with no leading zero (HARD-10: never parse-to-0-accept-all;
# a monotonic version gate is meaningless if "0" or "007" or "v3" slips through). Reject early.
if [[ ! "$VERSION" =~ ^[1-9][0-9]*$ ]]; then
  echo "pack: VERSION must be a positive integer (got: '${VERSION}')" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

# Collect (basename, sha256) pairs, fail-closed on any missing/unreadable input or duplicate
# basename. Duplicate basenames would collide both in the manifest and at the host dest.
declare -A seen_basename=()
manifest_lines=()
for f in "$@"; do
  # Reject symlink members — the refresh-set is real in-repo files only. cp/sha256sum would follow
  # a symlink and sign the TARGET's content under the member's basename (a content-substitution
  # surface even though the result stays signature-bound).
  if [[ -L "$f" ]]; then
    echo "pack: refresh-set member is a symlink (real in-repo files only): ${f}" >&2
    exit 1
  fi
  if [[ ! -f "$f" || ! -r "$f" ]]; then
    echo "pack: refresh-set file missing or unreadable: ${f}" >&2
    exit 1
  fi
  base="$(basename -- "$f")"
  if [[ -n "${seen_basename[$base]:-}" ]]; then
    echo "pack: duplicate basename in refresh-set: ${base} (from ${f} and ${seen_basename[$base]})" >&2
    exit 1
  fi
  seen_basename[$base]="$f"
  sha="$(sha256sum -- "$f" | cut -d' ' -f1)"
  manifest_lines+=("${sha}  ${base}")
  cp -- "$f" "${OUT_DIR}/${base}"
done

MANIFEST="${OUT_DIR}/manifest.txt"
{
  # VERSION is line 1 of the signed blob (HARD-2). The host greps `^VERSION=` from the
  # verified manifest only.
  echo "VERSION=${VERSION}"
  # LC_ALL=C sort by BASENAME (field 2) → reproducible ordering that is also STABLE under
  # file-content edits: only a rename reorders the manifest, whereas a content change (which shifts
  # a sha256) would reorder a whole-line sort. Basenames are unique (dup rejected above) → no ties.
  printf '%s\n' "${manifest_lines[@]}" | LC_ALL=C sort -k2
} > "$MANIFEST"

echo "$MANIFEST"
