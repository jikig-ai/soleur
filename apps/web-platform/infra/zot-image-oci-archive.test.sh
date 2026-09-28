#!/usr/bin/env bash
# zot-image-oci-archive.test.sh — offline suite for zot-image-oci-archive.sh (#8714 step 5.3b-iii).
#
# The builder turns the upstream zot image pinned in zot-registry.tf (`zot_image_amd64`, manifest
# digest D) into the release asset the registry host boots from. Its whole value is that the asset
# carries EXACTLY the upstream bytes, so every row here is about what it refuses:
#   - a blob whose bytes do not hash to the digest the manifest names (a tampered blob);
#   - a manifest that does not hash to D;
#   - a tar whose members are not exactly the layout (extra member, tampered second blob, wrong D).
# Must-PASS rows: a canonical 2-layer fixture, a 1-layer fixture (layer count is not hard-coded),
# and two independent builds that must be byte-identical (the pinned tarball sha256 T depends on
# it). No network: a stub `curl` on PATH serves synthesized fixtures and REFUSES any URL it was not
# told to expect, writing the refusal to a file the rows check.
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$DIR/zot-image-oci-archive.sh"

PASS=0; FAIL=0; FAILURES=()
pass() { echo "  pass: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); FAILURES+=("$1"); }

[[ -f "$SUT" ]] || { echo "  FAIL: $SUT does not exist"; exit 1; }

TMP="$(mktemp -d)" || exit 2
trap 'rm -rf "$TMP"' EXIT

# ── fixture: a synthesized OCI image (config + N gzip layers + manifest) ─────────────────────────
# make_image <dir> <n_layers> — writes blobs/<hex> files and prints the manifest digest (hex).
make_image() {
  python3 - "$1" "$2" <<'PY'
import gzip, hashlib, io, json, os, sys, tarfile
d, n = sys.argv[1], int(sys.argv[2])
os.makedirs(os.path.join(d, "blobs"), exist_ok=True)
def put(b):
    h = hashlib.sha256(b).hexdigest()
    open(os.path.join(d, "blobs", h), "wb").write(b)
    return h, len(b)
layers, diff_ids = [], []
for i in range(n):
    raw = io.BytesIO()
    with tarfile.open(fileobj=raw, mode="w") as t:
        data = ("synthesized layer %d\n" % i).encode()
        ti = tarfile.TarInfo("f%d.txt" % i); ti.size = len(data); ti.mtime = 0
        t.addfile(ti, io.BytesIO(data))
    diff_ids.append("sha256:" + hashlib.sha256(raw.getvalue()).hexdigest())
    gz = gzip.compress(raw.getvalue(), mtime=0)
    h, s = put(gz)
    layers.append({"mediaType": "application/vnd.oci.image.layer.v1.tar+gzip", "digest": "sha256:" + h, "size": s})
cfg = json.dumps({"architecture": "amd64", "os": "linux", "config": {"Entrypoint": ["/zot"]},
                  "rootfs": {"type": "layers", "diff_ids": diff_ids}}, separators=(",", ":")).encode()
ch, cs = put(cfg)
man = json.dumps({"schemaVersion": 2, "mediaType": "application/vnd.oci.image.manifest.v1+json",
                  "config": {"mediaType": "application/vnd.oci.image.config.v1+json", "digest": "sha256:" + ch, "size": cs},
                  "layers": layers}, separators=(",", ":")).encode()
mh, _ = put(man)
# The SAME manifest re-serialised: valid JSON naming the same real blobs, but bytes != D. A builder
# that skips the manifest==D check would accept it and build a complete archive.
alt, _ = put(json.dumps(json.loads(man), indent=2).encode())
open(os.path.join(d, "manifest-alt.hex"), "w").write(alt)
open(os.path.join(d, "manifest.hex"), "w").write(mh)
open(os.path.join(d, "config.hex"), "w").write(ch)
open(os.path.join(d, "layers.hex"), "w").write("\n".join(l["digest"][7:] for l in layers) + "\n")
print(mh)
PY
}

# write_tf <file> <manifest-hex> — a minimal zot-registry.tf carrying the upstream pin record.
write_tf() {
  cat > "$1" <<EOF
locals {
  zot_image_arm64 = "ghcr.io/project-zot/zot-linux-arm64:v9.9.9@sha256:$(printf 'a%.0s' {1..64})"
  zot_image_amd64 = "ghcr.io/project-zot/zot-linux-amd64:v9.9.9@sha256:$2"
}
EOF
}

# ── stub curl: serves $STUB_IMG, refuses anything it was not told to expect ──────────────────────
mkdir -p "$TMP/bin"
cat > "$TMP/bin/curl" <<'STUB'
#!/usr/bin/env bash
url=""; for a in "$@"; do case "$a" in https://*) url="$a" ;; esac; done
printf '%s\n' "$url" >> "$STUB_LOG"
refuse() { printf 'stub-curl: %s\n' "$*" >> "$STUB_ERR"; exit 22; }
case "$url" in
  "https://ghcr.io/token?scope=repository:project-zot/zot-linux-amd64:pull") printf '{"token":"synthetic"}'; exit 0 ;;
  https://ghcr.io/v2/project-zot/zot-linux-amd64/manifests/sha256:*)
    h="${url##*/sha256:}"
    [[ "$h" == "$(cat "$STUB_IMG/manifest.hex")" ]] || refuse "manifest for unexpected digest $h"
    f="$STUB_IMG/blobs/${STUB_MANIFEST_OVERRIDE:-$h}"; cat "$f"; exit 0 ;;
  https://ghcr.io/v2/project-zot/zot-linux-amd64/blobs/sha256:*)
    h="${url##*/sha256:}"
    [[ -f "$STUB_IMG/blobs/$h" ]] || refuse "no blob $h"
    if [[ "$h" == "${STUB_TAMPER:-none}" ]]; then printf 'tampered'; exit 0; fi
    cat "$STUB_IMG/blobs/$h"; exit 0 ;;
esac
refuse "unrouted url: $url"
STUB
chmod +x "$TMP/bin/curl"

export STUB_LOG="$TMP/curl.log" STUB_ERR="$TMP/stub.err"
run_build() { # run_build <img-dir> <tf> <out> → rc; stdout+stderr to $TMP/out.txt
  : > "$STUB_ERR"
  STUB_IMG="$1" ZOT_REGISTRY_TF="$2" PATH="$TMP/bin:$PATH" bash "$SUT" build "$3" > "$TMP/out.txt" 2>&1
}
run_verify() { # run_verify <tf> <tar>
  ZOT_REGISTRY_TF="$1" bash "$SUT" verify "$2" > "$TMP/vout.txt" 2>&1
}
no_stub_refusals() { [[ ! -s "$STUB_ERR" ]]; }

IMG2="$TMP/img2"; D2="$(make_image "$IMG2" 2)" || exit 2
IMG1="$TMP/img1"; D1="$(make_image "$IMG1" 1)" || exit 2
TF2="$TMP/tf2/zot-registry.tf"; mkdir -p "$TMP/tf2"; write_tf "$TF2" "$D2"
TF1="$TMP/tf1/zot-registry.tf"; mkdir -p "$TMP/tf1"; write_tf "$TF1" "$D1"
C2="$(cat "$IMG2/config.hex")"
L2A="$(sed -n 1p "$IMG2/layers.hex")"; L2B="$(sed -n 2p "$IMG2/layers.hex")"
[[ -n "$D2" && -n "$D1" && -n "$L2B" ]] || { echo "  FATAL: fixture synthesis failed"; exit 2; }

echo "== build =="
# B1 — canonical 2-layer build succeeds, prints C and T, and the layout is exactly right.
if run_build "$IMG2" "$TF2" "$TMP/a.tar" && no_stub_refusals; then
  T_A="$(sha256sum "$TMP/a.tar" | cut -d' ' -f1)"
  grep -qx "C=$C2" "$TMP/out.txt" && grep -qx "T=$T_A" "$TMP/out.txt" \
    && pass "B1 canonical build prints C (upstream config digest) and T (tarball sha256)" \
    || fail "B1 build output lacks exact C=/T= lines: $(tr '\n' ' ' < "$TMP/out.txt")"
  members="$(tar -tf "$TMP/a.tar" | LC_ALL=C sort | tr '\n' ' ')"
  want="$(printf '%s\n' blobs/ blobs/sha256/ "blobs/sha256/$C2" "blobs/sha256/$D2" "blobs/sha256/$L2A" "blobs/sha256/$L2B" index.json manifest.json oci-layout | LC_ALL=C sort | tr '\n' ' ')"
  [[ "$members" == "$want" ]] && pass "B2 tar members are exactly the OCI layout + manifest.json" \
    || fail "B2 tar members: got [$members] want [$want]"
  # Order is fixed, not readdir-dependent: the three top-level operands in argument order, then the
  # blobs/ subtree sorted by name (GNU tar --sort=name sorts WITHIN directories only).
  raw="$(tar -tf "$TMP/a.tar" | tr '\n' ' ')"
  blobs_sorted="$(tar -tf "$TMP/a.tar" | grep '^blobs/' | LC_ALL=C sort | tr '\n' ' ')"
  [[ "$raw" == "oci-layout index.json manifest.json $blobs_sorted" ]] \
    && pass "B2b member order is fixed (operands, then blobs/ sorted) — the bytes cannot depend on readdir order" \
    || fail "B2b member order is not the fixed order: [$raw]"
  x="$TMP/x"; mkdir -p "$x"; tar -xf "$TMP/a.tar" -C "$x"
  python3 - "$x" "$D2" "$C2" "$L2A" "$L2B" <<'PY' && pass "B3 index.json names D + the fully-qualified local ref; manifest.json names C and the layers in order" || fail "B3 index.json/manifest.json content wrong"
import json, sys
x, d, c, la, lb = sys.argv[1:]
idx = json.load(open(x + "/index.json"))
m = idx["manifests"]
assert len(m) == 1 and m[0]["digest"] == "sha256:" + d
assert m[0]["annotations"]["io.containerd.image.name"] == "localhost/soleur-mirror/zot-linux-amd64:v9.9.9"
assert m[0]["annotations"]["org.opencontainers.image.ref.name"] == "v9.9.9"
mj = json.load(open(x + "/manifest.json"))
assert mj == [{"Config": "blobs/sha256/" + c, "RepoTags": ["localhost/soleur-mirror/zot-linux-amd64:v9.9.9"],
               "Layers": ["blobs/sha256/" + la, "blobs/sha256/" + lb]}], mj
assert json.load(open(x + "/oci-layout")) == {"imageLayoutVersion": "1.0.0"}
PY
else
  fail "B1 canonical build failed: $(tr '\n' ' ' < "$TMP/out.txt") $(cat "$STUB_ERR")"
fi

# B4 — two independent builds are byte-identical (T is pinned, so the bytes must be a function of D).
sleep_free_touch() { find "$IMG2" -type f -exec touch -d '2001-01-01' {} +; }
sleep_free_touch
if run_build "$IMG2" "$TF2" "$TMP/b.tar" && cmp -s "$TMP/a.tar" "$TMP/b.tar"; then
  pass "B4 a second build (fixture mtimes changed) is byte-identical"
else
  fail "B4 two builds differ"
fi

# B5 — a 1-layer image builds too (layer count is not hard-coded).
if run_build "$IMG1" "$TF1" "$TMP/one.tar" && no_stub_refusals && run_verify "$TF1" "$TMP/one.tar"; then
  pass "B5 a 1-layer image builds and verifies"
else
  fail "B5 1-layer image: $(tr '\n' ' ' < "$TMP/out.txt") $(tr '\n' ' ' < "$TMP/vout.txt" 2>/dev/null)"
fi

# B6 — a tampered layer blob is refused and no archive is written.
rm -f "$TMP/t.tar"
if STUB_TAMPER="$L2B" run_build "$IMG2" "$TF2" "$TMP/t.tar"; then
  fail "B6 a tampered layer blob was accepted"
else
  [[ ! -e "$TMP/t.tar" ]] && grep -q "$L2B" "$TMP/out.txt" \
    && pass "B6 a tampered (second) layer blob is refused, names the blob, writes no archive" \
    || fail "B6 refused but left an archive or did not name the blob: $(tr '\n' ' ' < "$TMP/out.txt")"
fi

# B7 — a manifest that does not hash to D is refused, even though it is a VALID manifest naming
# real blobs (the registry answered with other bytes). Serving a non-manifest here would be refused
# by the digest-shape check instead and prove nothing about the D comparison.
rm -f "$TMP/m.tar"
if STUB_MANIFEST_OVERRIDE="$(cat "$IMG2/manifest-alt.hex")" run_build "$IMG2" "$TF2" "$TMP/m.tar"; then
  fail "B7 a manifest != D was accepted"
else
  [[ ! -e "$TMP/m.tar" ]] && pass "B7 a manifest whose bytes do not hash to D is refused" || fail "B7 left an archive"
fi

# B8 — a malformed pin in the tf is refused before any network call.
mkdir -p "$TMP/tfbad"; printf 'locals {\n  zot_image_amd64 = "ghcr.io/project-zot/zot-linux-amd64:latest"\n}\n' > "$TMP/tfbad/zot-registry.tf"
: > "$STUB_LOG"
if run_build "$IMG2" "$TMP/tfbad/zot-registry.tf" "$TMP/bad.tar"; then
  fail "B8 an unpinned (tag-only) ref was accepted"
else
  [[ ! -s "$STUB_LOG" ]] && pass "B8 a tag-only pin is refused before any network call" || fail "B8 refused only after contacting the registry"
fi

echo "== verify =="
# V1 — the canonical archive verifies.
run_verify "$TF2" "$TMP/a.tar" && pass "V1 the canonical archive verifies against D" || fail "V1 canonical archive failed verify: $(tr '\n' ' ' < "$TMP/vout.txt")"

# retar <src-dir> <out> — re-pack an extracted layout with the builder's normalisation.
retar() { tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner --format=ustar -C "$1" -cf "$2" oci-layout index.json manifest.json blobs; }
mut() { rm -rf "$TMP/mut"; mkdir -p "$TMP/mut"; tar -xf "$TMP/a.tar" -C "$TMP/mut"; }

# V2 — first layer blob tampered.
mut; printf 'x' >> "$TMP/mut/blobs/sha256/$L2A"; retar "$TMP/mut" "$TMP/v2.tar"
run_verify "$TF2" "$TMP/v2.tar" && fail "V2 a tampered first blob verified" || pass "V2 a tampered first blob is refused"
# V3 — SECOND blob tampered, first intact (a verifier that stops after one blob must red here).
mut; printf 'x' >> "$TMP/mut/blobs/sha256/$L2B"; retar "$TMP/mut" "$TMP/v3.tar"
run_verify "$TF2" "$TMP/v3.tar" && fail "V3 a tampered second blob verified" || pass "V3 a tampered second blob (first intact) is refused"
# V4 — the archive is for a different D than the tf pins.
run_verify "$TF1" "$TMP/a.tar" && fail "V4 an archive for another D verified" || pass "V4 an archive whose index names another digest is refused"
# V5 — an extra member rides along.
mut; printf 'x' > "$TMP/mut/blobs/sha256/$(printf 'b%.0s' {1..64})"; retar "$TMP/mut" "$TMP/v5.tar"
run_verify "$TF2" "$TMP/v5.tar" && fail "V5 an archive with an extra blob verified" || pass "V5 an archive carrying an unreferenced extra member is refused"
# V6 — manifest.json (the classic-store load path) points at a different config than the manifest.
mut; python3 - "$TMP/mut/manifest.json" "$L2A" <<'PY'
import json, sys
p = sys.argv[1]; m = json.load(open(p)); m[0]["Config"] = "blobs/sha256/" + sys.argv[2]; open(p, "w").write(json.dumps(m))
PY
retar "$TMP/mut" "$TMP/v6.tar"
run_verify "$TF2" "$TMP/v6.tar" && fail "V6 a manifest.json disagreeing with the manifest verified" || pass "V6 a manifest.json that disagrees with the OCI manifest is refused"

# --- anti-vacuity: helper self-test + an exact count ----------------------------------------------
_cp=$PASS; _cf=$FAIL; _cl=${#FAILURES[@]}
pass "canary: pass() counts"; fail "canary: fail() counts (EXPECTED)"
if [[ "$PASS" -ne $((_cp+1)) || "$FAIL" -ne $((_cf+1)) || "${#FAILURES[@]}" -ne $((_cl+1)) ]]; then
  printf '  FATAL: the assertion helpers are not counting — every verdict above is void.\n' >&2; exit 2
fi
PASS=$((PASS-1)); FAIL=$((FAIL-1)); unset 'FAILURES[-1]'
# EQUALITY, not a floor: adding a row must move this literal.
if [[ "$((PASS + FAIL))" -ne 15 ]]; then
  printf '  FATAL: anti-vacuity: %s assertions ran; exactly 15 are expected.\n' "$((PASS + FAIL))" >&2
  exit 1
fi
echo "=== Results: $PASS/$((PASS+FAIL)) passed, $FAIL failed ==="
[[ "${#FAILURES[@]}" -eq 0 ]]
