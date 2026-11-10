# Phase R and 2.6-2.13a evidence (#12514, 2026-11-10)

Verdict: **PROCEED**. Every red is explained by a pin shape (version literal, `measuredVersion`) or by the
container posture (identical on the 2.1.311 control); no `EDUPLICATEPKG` / `EUNREADABLEPKG` anywhere.

- Treatment tree: worktree head `3021791cb6` plus the uncommitted pin edits (2.1.321 / 0.3.321), copied to
  `/var/tmp/soleur-run.aTd9Q6/phaseR/tree-t`.
- Control tree: `git archive 3021791cb6` (pins 2.1.311 / 0.3.311; its `package.json` and lock are byte-identical
  to `origin/main` `b258336e`), copied to `.../phaseR/tree-c`.
- `T` = `426c33815ca6645a772f722fbff10dbf2cbdb124a8aeab733c1365dbf8bbf61f` (2.1.321 / 0.3.321, both packages).
  `C` = `86dc1fcc69498159eaf15f446613e847010f9036bfbbdffd4c49350be8489ada` (2.1.311 / 0.3.311).
  Each hash was checked by comparison and the step failed on a mismatch.
- Logs live under `/var/tmp/soleur-run.aTd9Q6/phaseR/`. The table below gives log names only.

## Containment (CTO F15)

- No 321 code ran on the host. Every `npm ci`, binary spawn and SDK suite ran in a throwaway container. The image was
  `node:22-slim@sha256:4b150b48...` (the Dockerfile base) plus Debian `bubblewrap` 0.8.0, `socat`, `perl`,
  `python3`, `jq`, `git`, `curl`, `openssl`, `qpdf`, `openssh-client`, `libcap2-bin` and `procps`. One suite also
  needed bun 1.4.4, so it ran on a variant image that adds it.
- Docker flags: `--rm -u 1000:1000` (root `0:0` only for the `--omit=dev` install and the raw-argv diagnostic),
  `--security-opt seccomp=<copy of infra/seccomp-bwrap.json>` (the production profile) and
  `--tmpfs /home/t` as `HOME`. The only mounts were the scratch tree copy (rw), the scratch scripts (ro), and the
  0600 key file (ro, real-key runs only).
- Never used: `--cap-add`, `--privileged`, `systempaths=unconfined`, an AppArmor option (the host has no AppArmor),
  the docker socket, `~/.doppler`, `~/.ssh`, `~/.config/gh` or `~/.claude`. The repository itself was never mounted.
- Key: `doppler secrets get ANTHROPIC_API_KEY --plain -p soleur -c ci` (read-only, never `prd`), written to a 0600
  file in a fresh `mktemp -d`. A `bash -c` wrapper inside the container read it, with `set +x` and `env -i`; the key
  never appeared on argv. Only `.modelUsage|keys` and `.permission_denials` were recorded. The key dir was
  `rm -rf`'d afterwards.
- Key check on the logs: the only `sk-ant-api` hit is the test fixture `CANARY_KEY` in
  `agent-auth-failure-sentry-path.test.ts`. No log contains the real key.

## Verdict table

| Step | Command (short) | Binary | Result | Log |
|---|---|---|---|---|
| 1.1r | `npm ci` (scripts on), treatment | T | rc 0; 1381 pkgs; 0 EDUPLICATE/EUNREADABLE | `1.1r-npmci-t.log` |
| 1.1r | `npm ci` (scripts on), control | C | rc 0 | `1.1r-npmci-c.log` |
| 1.1r | `npm audit signatures` | T tree | rc 0; 1380 verified signatures, 460 attestations | `1.1r-audit-signatures.log` |
| 1.1r-a | fresh copy `npm ci --omit=dev` as root | T | rc 0; both platform bins = T; 1 copy each; `.bin/claude` and `cli-wrapper.cjs --version` = 2.1.321 | `1.1r-a-omitdev-root.log` |
| 1.2 | assert sha256 + Bun + version + copies, treatment | T | `claude-code-linux-x64/claude`, `claude-agent-sdk-linux-x64/claude`, `.bin/claude` -> `bin/claude.exe` all = T; Bun v1.4.4; 2.1.321; 1 copy each | `1.2-assert-t.log` |
| 1.2 | same, control | C | all = C; Bun v1.4.4; 2.1.311 | `1.2-assert-c.log` |
| 1.2 | Guards 4/5 (`claude-cli-pin-knows-models`), treatment | T | 64 pass / 0 fail / 1 skip (CI-only row) | `1.2-guards-t.log` |
| 1.2 | Guards 4/5, control | C | 62 / **2 fail** (expected): Guard 4 `MODEL_ID_ABSENT` names both packages; Guard 5 `EFFORT_NO_ROW` fable-5-2 in both | `1.2-guards-c.log` |
| 1.3 | RED baseline, 8 pin suites unchanged | T | 366 pass / 4 fail / 0 skip; see the classification below | `1.3-red-baseline.log`, `1.3-rerun-{t,c}.log` |
| 1.4 | 5 runtime suites, `C4_BWRAP_REQUIRED=1` (a skip would throw) | T | 51 pass / 0 fail / 0 skip: credential-deny-behavioural 1, bwrap-userns-seccomp 30 (real-bwrap and unixdeny rows), wrapped-command 11 (prod config, AF_UNIX-deny ON/OFF + egress arm, G2, floors), credential-deny-runtime 1, proc-mask-runtime 8 | `1.4-runtime.log` |
| 1.4 | `sandbox-masked-proc-docker.test.sh` from host, unprivileged, `SOLEUR_SANDBOX_DOCKER_APPARMOR=unconfined` | T (/app = tree-t) | 54 pass / 0 fail; wrapped control + treatment, variant, census, isolation; AppArmor half NOT run | `1.4-masked-proc-docker.log` |
| 1.5 | cron hook probe on 2.1.321: original-name hook, `*` matcher, `--model claude-sonnet-5-5`; deny arm (allowlist `git status`) + allow arm (allowlist `echo`) | T | deny arm: `echo cronprobe12514deny` in `.permission_denials`, hook `cron-containment:` reason present. Allow arm: 0 denials, echo output seen (proves the hook ran; default mode alone would deny). modelUsage `["claude-sonnet-5-5"]` | `1.5-cron-probe-t.log` |
| 1.5 | same on 2.1.311 (control) | C | same outcome in both arms | `1.5-cron-probe-c.log` |
| 1.6 | invalid-key `--model fable` init probe, both platform bins | T | `claude-fable-5-2`, `claude_code_version` 2.1.321 (both) | `1.6-alias-t.log` |
| 1.6 | same, control | C | `claude-fable-5-1`, 2.1.311 (both) | `1.6-alias-c.log` |
| 1.6b | authenticated `-p hi --model fable --max-turns 1` (ci key) | T | modelUsage keys `["claude-fable-5-2"]`: PASS | `1.6b-auth-alias.log` |
| 1.7 | Write then Edit through the real SDK `query()`, stub API, `canUseTool` returns `{behavior:"allow", updatedInput}` | T | canUseTool asked `Write,Edit`; 2 non-error tool_results; final file `beta-12514`: PASS (2.1.311 control also PASS) | `1.7-write-edit.log`, `1.7-write-edit-c.log` |
| 1.8 | re-measure from binaries (python `-I`, mmap) | T vs C | helper strings 21 (same set both versions); `allowAllUnixSockets:` 12, `network.allowAllUnixSockets` 4, `TCP6-LISTEN:${` 1 (unchanged); `default_effort` opus-5-5, sonnet-5-5, haiku-5-5, fable-5-2 = medium (fable-5-2 absent in C); fable-5-1 = high. Census, mount-table, helper-selection and bridge rows green on T unchanged | `1.8-measure-{t,c}.log`, `1.8-measure2-{t,c}.log` |
| 1.9 / 1.9a | stop condition | - | not hit: no non-pin red, no EDUPLICATEPKG / EUNREADABLEPKG in any install or build log | - |
| 2.7 | `SANDBOX_CANARY_MODE=capture bash scripts/sandbox-canary-verify-in-image.sh` (run from tree-t, ci key) | in-image `npm ci` of 0.3.321 | `{"verdict":"captured","sdkVersion":"0.3.321","tokenCount":134}`. Canonical argv byte-identical; only `sdkVersion` and `droppedForDeterminism.hostBind` 6 -> 7 changed. Fixture sha256 `20c54be1...`, copied unedited into the worktree | `2.7-capture.log` |
| 2.7 (diag) | raw-argv diff via `doCapture()` against the stub (no key), both trees | T vs C | the one new raw token: `--ro-bind <cli-tmp>/claude-0/plugin-tool-staging` (read-only, under the already-bound CLI temp root; the normalizer drops it as host-specific) | `2.7-rawargv-{t,c}.log`, `2.7-binds-{t,c}.txt` |
| 2.12 | `bash plugins/soleur/test/c4-count-parity.test.sh` | - | 13 pass / 0 fail. No C4 element names a version or Fable | `2.12-c4-parity.log` |
| 2.13 | `vitest related --run` over the 20 changed or Phase R files | T | 240 files: 5717 pass / 1 fail / 34 skip. Fail = the container proc_mask row (below). Skips = DB-gated integration suites plus `compound-promote-create-dry-render` (no bun in the image); that suite re-run with bun: 11 / 0 / 1 | `2.13-affected.log`, `2.13-compound-promote-rerun.log` |
| 2.13 | `tsc --noEmit` | - | rc 0 | `2.13-tsc.log` |
| 2.13 | `node scripts/sandbox-canary.mjs --replay` with the shipped shim at `/usr/local/bin/bwrap` + both BPF env vars, new fixture | T | `{"verdict":"pass","sdkVersion":"0.3.321"}` (control fixture also pass) | `2.13-replay-shim-{t,c}.log` |
| 2.13 | docker replay arm: masked-proc suite again on the re-captured fixture | T | 54 / 0; treatment replay pass, non-vacuity reads fixture 0.3.321 | `2.13-masked-proc-docker.log` |
| 2.13 | `docker build --target cli-tools` | - | rc 0 | `2.13-build-cli-tools.log` |
| 2.13a | `docker build --target deps` | - | rc 0; 0 EDUPLICATE/EUNREADABLE; both `/app` platform bins = T, 1 copy each | `2.13a-build-deps.log`, `2.13a-deps-probe.log` |
| 2.13a | cli-tools global `claude` | T | `/usr/local/bin/claude` -> `bin/claude.exe` = T; exactly 1 `claude-code-linux-x64/package.json` under `npm root -g` (0 musl/arm64); Bun v1.4.4; 2.1.321; invalid-key alias `claude-fable-5-2` | `2.13a-cli-tools-probe.log` |

### 1.3 red classification

1. `adhoc-npm-install-pin-table`, 2 rows: the Dockerfile literal is still `2.1.311`. Version literal; fixed in 2.6
   (8 / 0 after).
2. `sandbox-vendored-argv-tail`, the lock row: `measuredVersion` 0.3.311 against the lock's 0.3.321. Pin shape;
   fixed in 2.6 (64 / 0 after).
3. `broker-mechanism-spike`, the version row: `0.3.311` expected, `0.3.321` installed. Version literal; fixed in 2.6
   (19 / 0 after). Its first run errored only because the image lacked `curl` and `openssl`; after adding them the
   control ran 19 / 0.
4. `sandbox-canary`, the row `proc_mask live drive ... a restored --proc /proc` (expects `sandbox_broken`, gets
   `canary_infra_error`). The cause is environmental: real `/usr/bin/bwrap` with no SDK and no 321 code, under docker's
   default masked `/proc`, where a fresh procfs mount is refused. The row reds identically on the 2.1.311 control, so it
   is not a pin shape and not a builder shape. On CI it runs on the bare runner.

## Not validated

- AppArmor half of the masked-`/proc` docker suite. `sudo` needs a password and the host has no AppArmor, so the run
  used the documented unprivileged local override. The CI stand-in is `infra-validation` `deploy-script-tests-fixed`
  on a head that carries the pin commit.
- CI `sandbox-canary-capture-gate` in-image `--verify` against the committed fixture (Phase 3.2).
- A server-side alias override for production or tenant accounts. 1.6b proves only the ci key's account on
  2026-11-10.
- The non-x64 platform binaries (lock version equality only).
- Whether a `model: fable` Task inherits the parent session's effort. Only the bundled row default (medium) is
  measured.
- How a hosted session in flight at the image swap behaves.
- The full runner stage. Its `npm ci --omit=dev` ran only as a scratch-copy install as root, not inside the runner
  build, so the release build (4.1) is what validates the runner stage.
- The `sandbox-canary.test.ts` `--proc /proc` live-drive row. It is unrunnable under docker masks; CI runs it on the
  runner.
- The plain-PATH form of `node scripts/sandbox-canary.mjs --replay` (no shim) gives `sandbox_broken` /
  `proc_mask_defeated` on BOTH fixtures. That is by design: the vendor tail bind is what the shim drops, so only the
  shim-on-PATH run (pass) is the production shape.

## Files edited in 2.6 / 2.7 / 2.12

- `apps/web-platform/test/sandbox-vendored-argv-tail.test.ts`: both `PINS` `measuredVersion` rows 0.3.321 / 2.1.321,
  re-measured dates, header binary sha.
- `apps/web-platform/test/helpers/vendored-bwrap-tail.ts`: measured comments (history kept, 2026-11-10
  re-measurement added).
- `apps/web-platform/test/adhoc-npm-install-pin-table.test.ts`: Dockerfile literal 2.1.321.
- `apps/web-platform/test/broker-mechanism-spike.test.ts`: declared and installed version 0.3.321, plus the comment.
  The row title dropped "the ADR names".
- `apps/web-platform/server/sandbox-startup-classifier.ts` and `apps/web-platform/test/sandbox-startup-classifier.test.ts`:
  measured-version comments only (step list unchanged).
- `apps/web-platform/server/untrusted-content.ts`: typings comment (Bash and PostToolUse typings re-read, unchanged
  at 0.3.321).
- `apps/web-platform/scripts/sandbox-canary.mjs` and `apps/web-platform/test/sandbox-canary.test.ts`: the
  `seed-admin` comments note that 2.1.321 / 0.3.321 still covers it.
- `apps/web-platform/test/sandbox-credential-deny-argv.test.ts`, `apps/web-platform/test/sandbox-credential-deny-runtime.test.ts`,
  `apps/web-platform/test/sandbox-wrapped-command-runtime.test.ts`: version-mention comments.
- `apps/web-platform/infra/sandbox-canary-argv.json`: re-captured by 2.7, never hand-edited.
- `knowledge-base/engineering/architecture/decisions/ADR-079-faithful-sandbox-canary-and-profile-redeploy-verification.md`:
  appended `## Addendum — 2026-11-10 (#12514)`.

Residual `2.1.311` / `0.3.311` hits outside `knowledge-base/` and the locks are all kept on purpose:

- History: `betterstack-logs-alerts.tf`, `claude-pin-lockstep.test.ts:63`, `home-census.test.ts:835`, the
  "added in" and "pre-0.3.311" helper notes, the `claude-cli-pin-knows-models` measurement notes, and the
  `plugins/soleur` AGENTS / SKILL / test notes.
- A `>=` floor: `scripts/followthroughs/ci-claude-cli-pins-bun-12073.sh`.
- An open-ended `2.1.311+` claim: `sandbox-canary.mjs:1683`.

Not edited, flagged instead: `knowledge-base/engineering/operations/runbooks/plugin-delivery-recovery.md:303` says
the scheduled canary installs CLI 2.1.311, which `CLI_VERSION` 2.1.321 now contradicts. ADR-311 has no 0.3.321
addendum; #12026 added one.
