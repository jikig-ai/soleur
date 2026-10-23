# Classified diagnostic replacement — 2026-10-19

Source: `deb0f086bca2bef39dedda2a4491f72059ac9b54`, pushed to draft PR #9051.
The original approved attempt is consumed. Its incomplete evidence and separate
review remain in `redirect-manifest-review-8f2700ed-2026-10-19.md`.

## Source verification

The source-only correction adds six fixed token-header failure categories while
preserving existing framing/media acceptance, shared generic reasons, body limits,
socket cleanup, absolute deadlines and Config body non-consumption. It changes no
request URL, authorization, profile admission or routing projection field.

Targeted security, code-quality and test-design reviews passed implementation
commit `674b28a93f`. Security compared 5,760 synthesized header cases with the
original predicate and observed identical acceptance/refusal. Final test
refinements were pushed in `deb0f086bc`; no implementation code changed there.
CTO fresh-eyes verification passed the final source against its classification-only
ruling. This is scoped correction review, not full-branch ship approval.

Focused tests: 12 pass after the final refinements. Full offline discovery:
320 pass on the same implementation before those test-only refinements. Ruff:
44 existing findings, 115 files, pass. Staged secret scans found no leaks.
Semgrep with one worker scanned both final Python files using 200 applicable
rules: zero findings, no JSON errors. The parallel engine's io_uring allocation
failure is resolved by the verified `--jobs 1` workaround for this scan.
Markdown selector excluded the four KB paths by repository configuration.
The shell hook path is `/dev/null`; `lefthook` was unavailable, so these relevant
checks ran directly. No hook execution is claimed.

## Replacement bindings

- Manifest: `.soleur/redirect-diagnostic-deb0f086-20261019/redirect-diagnostic-manifest.json`.
- Canonical SHA-256:
  `52c67f0987adbf05b38515e0558b13613fb8ff879ed23fca4aa55e0f9ed20fe6`.
- Runner SHA-256:
  `d7a531015acb092f3f6322638776829033d1cd14e097a64583590f6b004290ff`.
- Preparation regenerated the operational contract and source references from
  committed current HEAD, created new input/attempt bindings, re-read the exact
  unchanged CA/platform bytes and Config descriptor, and created a new private
  output directory. No candidate was assembled or built, and no request ran.
- Independent actual replacement-manifest review is pending.
- Fresh exact-command approval has neither been requested nor granted for this
  replacement. The original approval does not cover this attempt.

The future command must use `/usr/bin/timeout -k 5 90 /usr/bin/python3.14 -B`, the
absolute runner and manifest paths, and both replacement hashes above. Internal
limits remain 60 seconds total and at most ten seconds per request. Token JSON
may be read in memory within its original bound; Config response body must never
be read. No retry, redirect follow, destination request or layer fetch is allowed.

All build, Docker/SQL, provider/browser/account, recovery, qualification, Web/CLO,
promotion and ship holds persist. Hosted auth remains BLOCKED; alternate route
PENDING. PR remains draft, disarmed and customer-blocked. CI is pending, not green.

This record and the marker-discovery learning remain untracked until evidence
work permits a new source commit; tracked HEAD must stay pinned before the attempt.

## Independent actual-manifest review — PASS

Security independently verified the replacement manifest without execution:
all 13 dependencies and 29 contract source references match committed current
source; contract/input/pairing/operational/retained hashes match. CA, platform
bytes and exact Config descriptor remain unchanged. Private output fingerprint
is device 64769, inode 10699823, UID 1000; no-follow path checks and 0700/0600
modes pass. Only the manifest exists; replacement marker/receipt are absent.
Historical manifest, spent marker and incomplete receipt remain unchanged.

The exact bounded two-GET plan is unchanged. Classification is confined to six
diagnostic-local constants, routing projection remains the original nine fields,
and authority/admission flags remain false/pending. Interpreter/Git/timeout
binary bytes are outside the manifest hashes; the command identifies selected
interpreter and timeout paths. This review grants no execution authorization.

The pending actual-manifest-review item above is now discharged. Present the
fully expanded replacement command and obtain fresh approval before execution.

## Final refined-test review — PASS

The test-design reviewer read the exact `674b28a` to `deb0f086` test diff and
found no blockers. The refinements cover size-before-media precedence, accepted
parameterized JSON/identity encoding, successful-action category absence and
forged receipt-boundary exclusions. No implementation code changed. All scoped
source-review requirements are discharged; execution approval remains pending.

## Approved classified attempt — 2026-10-20

The operator approved the exact replacement command. It executed once, exited 1,
and consumed its marker. Separate security review passed integrity of the
incomplete evidence: receipt self-hash
`6d70e81f2b4e11a6d1c74dceb3063e3d274dce22a8281315291be5257b5c0ad8`,
receipt file SHA-256
`edacf7c5cbc10734ee9d8586d523c76434698fea11abe3964732172f5dd0045a`,
marker SHA-256
`6738256c5f1b82d0733a45907483af9c3b0ac9273d6140389f28549ff4b8fe4c`.
Original source, manifest/context/action bindings, private fingerprint and
0700/0600 output modes match; no extra files or raw values were retained.

The receipt records one token HTTP-200 response and fixed
`token_header_failure: content_length_count`. This means the parsed Content-Length
count was not exactly one; missing versus duplicate is unknown. Later framing,
encoding and media predicates were not reached. No application token body was
read, Config GET was not attempted, and no Location, destination request or layer
fetch occurred. The approval is spent. No retry or follow-on is authorized.
