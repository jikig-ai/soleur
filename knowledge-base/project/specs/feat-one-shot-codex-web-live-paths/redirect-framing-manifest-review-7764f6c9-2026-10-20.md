# Bounded token framing diagnostic replacement — 2026-10-20

Source: `7764f6c91eecf6cd11875fc6cfece3faea672c5d`, pushed to draft PR #9051.
Both earlier diagnostic approvals and their one-use markers are consumed.
Their unchanged records are in `redirect-manifest-review-8f2700ed-2026-10-19.md`
and `redirect-classified-manifest-review-deb0f086-2026-10-19.md`.

## Source verification

The separately approved classified attempt stopped before application token
body reading with `content_length_count`. Missing versus duplicate length is
unknown; Config GET was not attempted. The CTO's bounded framing ruling and
dissent are recorded under “Bounded token framing” in
`prebuild-acquisition-2026-10-16.md`.

Only the fixed token endpoint's HTTP-200 JSON response may use a single valid
Content-Length, single chunked transfer coding without Content-Length, or clean
TLS EOF without either framing header. The decoded-body ceiling remains 16,384
bytes. Chunk count, size-line and aggregate framing bounds, absolute deadlines,
ragged-EOF rejection and socket cleanup apply. Duplicate or ambiguous framing,
unsupported encodings, extensions and nonempty trailers remain refused.
Config response bodies are never read, including error and unexpected statuses.
The nine-field Location projection and authority flags are unchanged.

Tests were written first. Focused parser tests pass 20/20; full offline discovery
passes 329/329. The reproduced synthetic cleanup fixture race was tracked in
issue 10621 before its request-coalescing and exception-cleanup repair; its
regression failed first and the fixture suite then passed 13/13. Production
proxy code is unchanged. Ruff passes with 44 baselined findings across 115 files.
Single-worker Semgrep scanned all three changed Python files with 200 applicable
rules, zero findings and no JSON errors. Staged secret scans found no leaks.

Targeted security, code-quality and test-design source seats passed, together
with CTO framing conformance review. These are scoped source reviews, not full
branch review or ship approval. Direct checks ran because the hook path was
`/dev/null` and `lefthook` was unavailable; hook execution is not claimed.

## Fresh file-only bindings

- Manifest: `.soleur/redirect-diagnostic-7764f6c9-20261020/redirect-diagnostic-manifest.json`.
- Canonical SHA-256:
  `325a9334f92ffc105f4f7f15bacf6ada52b31e0987466be80f4b56012d32f36e`.
- Runner SHA-256:
  `172c5f0737b1517c459f8b2b19e2f58d93a137c2f3bc1141c61941abbb73be2b`.
- CA SHA-256:
  `8c97794a899a32666593979dc7adfaec8bda2b420eb092ff0d987e44ad0bf6ea`.
- Platform: 864 retained bytes, SHA-256
  `168f762c218e167ba88ae7e48194126eb5ba5e99ef652063e3f14f9c4f0ee70f`.
- Config descriptor: OCI image config, size 2646, digest
  `sha256:3f56e44ddc1a5655b8f288a2aa812db567b2f5f0b8bc18ef3da63b94a95608d5`.
- Output fingerprint: device 64769, inode 10918824, UID 1000, mode 0700.
  Manifest mode 0600; only the manifest exists, marker and receipt absent.

Preparation regenerated operational and input bindings from pinned source.
It did not assemble/build the proposed candidate or make diagnostic requests.
Independent actual-manifest review passed. At preparation, fresh exact-action
approval had not yet been granted; the completed attempt is recorded below.
Selected interpreter/Git/timeout paths
are identified by path; their bytes are outside the manifest's hash bindings.
No executable or shared-library attestation is claimed.

## Independent actual-manifest review — PASS

Security independently recomputed every binding above. All 13 dependencies
and 29 source references matched regular-file bytes and committed blobs;
pure operational reconstruction exactly matched the retained contract.
Operational contract file hash is
`58811e5e8cf6544b5b178a85aa3aa2dbedf5800a7ca022e22d276655b7d593c7`,
image-input hash is
`6a022afea6f47082a01496a52b52dd83636ab5d79d800e026a09130cbb8cb994`,
and retained-manifest hash is
`e48e6011aef57ddb47b0f575c6eb9ee86f0c73cf02a7544fef249fbff6b888f4`.
The manifest file hash, distinct from its canonical hash, is
`26c8e8bc162bb90ec53fdd4d85d96c36576ca760b6570338a28c42eb1f3538fc`.

Descriptor-relative no-follow checks passed for source, contract, inputs,
retained manifest, CA and platform bytes. The CA bundle contains 185,311 bytes
and 121 parsed certificates. Output identity matches; manifest inode is
10918825, UID 1000, mode 0600. Marker and receipt remain absent. Historical
spent manifests, receipts and markers are unchanged. Source inspection verified
the two fixed requests, header-only Config response, bounded memory-only token
body, pinned CA verification and sanitized receipt projection. No diagnostic
execution, network, build, Docker operation or reviewer file mutation occurred.

Review permits presentation only. Obtain fresh approval for the fully expanded
command before execution; preserve the 90-second outer timeout and five-second
kill grace. Independent review of any resulting evidence remains required.

The exact future command must include `/usr/bin/timeout -k 5 90`,
`/usr/bin/python3.14 -B`, absolute runner/manifest paths and both hashes above.
Internal limits remain 60 seconds overall and ten seconds per request. Token
JSON stays in memory; retain only sanitized evidence. No redirect following,
destination request, Config body read, layer fetch, retry or automatic follow-on.

## Wider gates

Live GitHub state is OPEN/draft, auto-merge off, DIRTY/CONFLICTING. The six
reported checks passed; this is not a full CI verdict. Upstream resync, full CI,
build, Docker/SQL/provider/browser/account operations, recovery, qualification,
Web/CLO matrices, full review, QA, preflight, promotion and ship remain held.
Hosted authentication remains BLOCKED and alternate route PENDING.

Ruled by CTO agent, 2026-10-20: finish independent manifest review and present
the pinned diagnostic for fresh approval before resyncing main. The action
validates local committed source rather than a GitHub merge result; upstream
conflicts do not alter those bytes. Resync would invalidate source identity
and require new preparation and review. This ruling grants no execution or
branch-clearance authority. Dissent: observation can still fail and proves
neither destination authority nor readiness; changed bytes, bindings or command
stop the attempt. Resync and complete CI remain required before later integrated
qualification or shipping.

This review and the discovery learning remained untracked to preserve exact
source HEAD during approval and execution. After the separate evidence review
below, they can be committed as attributable historical records.

## Approved attempt and separate evidence review — PASS

After the operator freshly approved the fully expanded command, it executed
once with `/usr/bin/timeout -k 5 90` and exited 0. The approval and marker are
now consumed; neither permits a retry or any follow-on request.

Separate independent security review verified the immutable receipt:

- Receipt self-hash:
  `4a4d754d0ac5d0da89d9a4c8895d831064b08498b22db23863f9685ff79fdc32`.
- Receipt file SHA-256:
  `3e1960ed6867957f3404af7209af1e959d12874d06e0288e57474ab907ed71c0`.
- Consumed marker file SHA-256:
  `fb63c5259b8645ee1e0ded22b8a7234ae98e7d704872552c7299c1f9808e5612`.

Status is `redirect-headers-observed`, request count two: token HTTP 200 then
pinned Config HTTP 307. The monotonic interval is approximately 0.877 seconds.
The sanitized projection records HTTPS `production.cloudfront.docker.com`,
port 443, Location length 558 bytes, query present, userinfo/fragment absent,
and expected literal Config digest in path false. Location SHA-256 is
`0c47611fb61bc9bdf8d54ef458248066e08329e33fc9b1a89a3c7c8929c5e149`;
path SHA-256 is
`14b6dd043904e8cab519a0a6eafeb4ccc3baa3ba85b1e93aab857d62b9e715a1`.
No raw Location, query, path, token or response body was retained.

Review revalidated exact receipt fields, self-hash, action URL hashes,
source/manifest/context/marker bindings, dependencies, operational/input/CA/
retained/platform/Config bindings and historical spent files. The output
directory has its original identity/mode and exactly three regular UID-1000,
mode-0600 files: manifest, marker, receipt. There were no extra fields/files.

The first action's `token_validation` / `token_shape` annotations are phase
labels, not failure evidence: validation completed before request two. The
receipt does not establish which token framing mode was accepted. Hostname
projection proves neither destination ownership nor publisher provenance,
contents or Config integrity. The missing literal digest in the path proves
neither a wrong resource nor an acceptable alternate route. No redirect was
followed and no destination, Config body or layer was requested. Authority and
profile-admission flags remain false, and immutable review/issuer/publisher
fields remain pending. The external review does not rewrite those fields.

The separate evidence-review gate is discharged. A new engineering/security
ruling is required before any proposal for a constrained destination request.
The sanitized records may now be committed without changing the attribution
of this historical source-bound attempt.

The subsequent CTO ruling keeps destination/body requests held. Its exact next
gate and dissent are recorded in `prebuild-acquisition-2026-10-16.md`, “Reviewed
redirect evidence and next boundary”: a source-only proposal with primary origin
evidence, exact-host acceptance, isolated credentials/network, exact Config
length/digest/schema and a fresh tests/review/manifest/approval chain. Neither
implementation nor execution is authorized by that ruling.
