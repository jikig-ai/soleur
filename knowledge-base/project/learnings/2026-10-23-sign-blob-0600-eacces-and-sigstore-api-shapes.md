# Learning: cosign sign-blob --bundle lands 0600; probe API shapes fail CI before the diff does

Two defects surfaced while fixing the inngest config-bundle producer
(epic #10390, defect 3 — the emitted `.sigstore.json` the pinned verify-blob
could not load). Both are measure-first root causes, not the suspects the
initial framing proposed.

## Problem

1. **EACCES read as "flag a new bundle".** `cosign sign-blob --bundle <path>`
   writes the bundle file **0600** owned by the producing user. The verify
   consumer runs as a different, non-root user (docker `--user`, no `user:` in
   cloud-init, no `if:` fallback), so its open(2) fails EACCES — a
   *permissions* failure surfacing downstream as a bundle-validity flag. The
   initial suspect (a malformed/truncated bundle) was wrong: the bytes were
   loadable; the *reader* could not reach them. A loadability probe run as
   root sees a green the nonroot consumer never sees.
2. **Probe API shape wrong twice before CI ran.** The diagnostic Go probe
   (`diagnose-inngest-verify.yml`) failed its first CI cycle on two
   compile-time facts, not on the defect it was written to observe: (a) `go
   run` on a file importing sigstore-go transitives fails without `go mod
   tidy` first — `go.sum` needs the transitive entries, and `go run` does not
   resolve them; (b) `b.Version()` at sigstore-go **v1.2.0** returns
   `(string, error)`, not a bare `string` — the single-value assignment was a
   compile error.

## Solution

- Producer pins its emit surface: the signing-config emit step in
  `build-inngest-config-bundle.yml` + `inngest-signing-config.json` hard-fails
  pre-push on a bundle the consumer's pinned loader cannot read
  (verify-before-publish at the same uid/mode the consumer will use), and the
  floor-6 ordering gate is documented — no cloud-init-booting dispatch may
  run between merge and `INNGEST_CONFIG_DIGEST` promotion.
- Probe: `go mod tidy` runs before `go run` in the workflow, and the probe
  calls `v, err := b.Version()` with the two-value form pinned by
  `diagnose-inngest-verify-workflow.test.sh`.

## Key Insight

**Verify the reader's execution context, not the artifact's correctness, when
a freshly-produced file "cannot load".** A 0600 producer-side write is
invisible to every root-side check — the failing property lives at the
producer/consumer *boundary* (uid, umask, mode), not inside the bytes. And
**a diagnostic probe is code in the same blast radius as the fix**: check its
dependency-resolution step (`go mod tidy`) and its API signatures against the
*pinned* module version locally before letting CI spend a cycle — both of
these were knowable facts a `go build` would have reported in seconds.

## Tags

category: infra
module: inngest-config-refresh

## Session Errors

1. **Framing suspected the bundle bytes; the defect was the file mode.** A
   root-run load check greened a file the nonroot consumer could not open.
   **Prevention:** when a produced artifact "won't load" for a non-root
   consumer, check `stat` (mode/owner) before parsing — and run
   verify-before-publish under the consumer's uid/mode, not the producer's.
2. **Probe authored against assumed API shapes.** `b.Version()` single-return
   and missing transitive `go.sum` entries both compiled as assumptions and
   failed in CI.
   **Prevention:** `go build`/`go vet` any Go probe against the pinned
   `go.mod`/`go.sum` before pushing; the compile errors are free locally and
   a full CI cycle remote.
