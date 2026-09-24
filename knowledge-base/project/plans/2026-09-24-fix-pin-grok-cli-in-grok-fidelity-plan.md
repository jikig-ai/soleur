---
title: "ci: pin the Grok CLI in the required grok-fidelity check (exact version + sha256 content pin + version assert)"
type: fix
date: 2026-09-24
slug: pin-grok-cli-in-grok-fidelity
branch: feat-one-shot-8615-pin-grok-cli
issue: 8615
closes: 8615
priority: p2
domain: engineering
brand_survival_threshold: none
lane: cross-domain
---

# ci: pin the Grok CLI in the required `grok-fidelity` check

## Overview

`.github/workflows/ci.yml` job `grok-fidelity` is a **required** check (named in
`infra/github/ruleset-ci-required.tf`), yet it installs the Grok CLI by piping the unversioned
`https://x.ai/cli/install.sh` into `bash` and then prints `grok --version` without comparing it to
anything. An upstream Grok release can therefore change the binary every PR's required check runs
against, and nothing in the job names that as the cause. ADR-245 decision 3 sets the CI vendor-CLI
policy (exact pin, assert the binary reports it, exit 3 on drift) and names `grok-fidelity` as its one
known non-conformance, tracked by #8615.

This plan retrofits `grok-fidelity` to that policy, with the same shape as `harness-discovery`'s
Codex/Devin arms, and records the Grok pin under the pin-freshness criterion #8574 carries. One PR,
one workflow job, plus the three documents that describe the job and would be false after it lands.

**Measured choice (the issue asked to measure before choosing):** the vendor exposes a **versioned
binary URL** but **no versioned installer URL and no checksum file**, so the pin is the versioned
binary plus a sha256 content pin on it. The installer script is not used at all. The details are in
§Research Insights.

## Research Insights

### Premise Validation

- **#8615**: OPEN, not closed by any PR. The premise holds. `ci.yml:1360-1365` still reads
  `curl -fsSL https://x.ai/cli/install.sh | bash` followed by a bare `grok --version`.
- **#8574**: OPEN. Its **body contains only the soak/promotion criteria.** The "monthly pin-freshness
  comparison" appears in **ADR-245 decision 3** (`knowledge-base/engineering/architecture/decisions/ADR-245-retire-openhands-gemini-ports-and-prove-codex-devin-discovery-in-ci.md`,
  "#8574 owns promotion and carries the pin-freshness criterion: a monthly comparison against
  `npm view @openai/codex version` and Devin's current release") and in
  `plugins/soleur/test/README.md` §Vendor-CLI pins. **Nothing runs that comparison.** There is no
  scheduled workflow, script or recurring issue for it. `git grep` for `npm view @openai/codex`,
  `pin-freshness`, `CODEX_PIN` and `DEVIN_PIN` outside plans/specs finds only `ci.yml`, ADR-245 and the
  README. A second sweep for `@openai/codex`, `static.devin.ai` and `x.ai/cli` across
  `.github/workflows/`, `apps/` (including the Inngest crons), `scripts/`, `plugins/soleur/scripts/` and
  `plugins/soleur/skills/` matched only `ci.yml` and the two dogfood bootstraps. `.github/workflows/vendor-pin-verify.yml` looks like it might be this comparison, but it is
  the NOTICE upstream-blob gate (#3521) and is unrelated. **So the comparison is a documented criterion
  that nothing executes.** "Joining" it therefore means adding the Grok pin, and the command that
  checks it, to the documents and to the #8574 issue body, not wiring into a job.
- **"ADR-240 decision 3"** in the issue body is a mis-cite. ADR-240 is
  `shard-assignment-is-checked-in-derived-data`. The policy is **ADR-245** decision 3 (text quoted
  above). This plan cites ADR-245.
- `grok-fidelity` stays in the required set. That is out of scope per the issue, and this plan does
  not touch `infra/github/ruleset-ci-required.tf`.

### Vendor measurements (2026-09-24, from this workstation)

| Probe | Result |
|---|---|
| `curl -fsSL https://x.ai/cli/install.sh` | 200, 517 lines, sha256 `7fd6fdc7…e791`. Header: `curl … \| bash -s 0.1.42  # specific version`. The installer **accepts a version argument** (`TARGET="$1"`, validated `^[0-9]+\.[0-9]+\.[0-9]+(-suffix)?$`) |
| `https://x.ai/cli/stable` / GCS `…/cli/stable` | `1.0.41` (latest stable; what CI installs today) |
| `https://x.ai/cli/grok-1.0.41-linux-x86_64` | **200**, 165,967,424 B, etag `a0ad7ff0132e5a7bb6b661163400e5f5` |
| `…/grok-1.0.41-linux-x86_64.gz` / `.zst` | 200 (67.9 MB / 50.8 MB) |
| `https://storage.googleapis.com/grok-build-public-artifacts/cli/grok-1.0.41-linux-x86_64` | 200, **same etag**. This is the installer's own fallback base (`BASE_URL_FALLBACK`) |
| `…/grok-1.0.41-linux-x86_64.sha256`, `.sha256sum`, `…/cli/SHA256SUMS` | **404**. The vendor publishes no checksum |
| `…/cli/1.0.41/install.sh`, `…/cli/install-1.0.41.sh` | **404**. There is no versioned installer URL |
| downloaded binary | sha256 **`9ce03ed23e16ea01072b4496263d6213a27899e1e3e107f008d36edf82e70407`**, md5 `a0ad7ff0…` (= etag, so a single-part object), ~15 s at local bandwidth |
| `grok --version` | `grok 1.0.41 (4220f3b224a6)`. `grep -oE '[0-9]+\.[0-9]+\.[0-9]+' \| head -1` yields `1.0.41` |
| Auto-update | The binary embeds an auto-updater (`crates/codegen/xai-grok-update/src/auto_update.rs`, "Check for CLI updates on launch"). Its embedded docs name the process knob **`GROK_DISABLE_AUTOUPDATER=1`** ("`cli.auto_update` … Also GROK_DISABLE_AUTOUPDATER to suppress") |
| Binary-only install parity | With `HOME=<fresh>`, the binary copied to `~/.grok/bin/grok`, `GROK_DISABLE_AUTOUPDATER=1`, `ensureGrokFolderTrusted(REPO_ROOT)`, then `grok inspect` from the repo root gives rc 0 and `validateGrokInspectParsed` → **`[]` (zero violations)**: 102 plugin skills, 67 project agents. No `config.toml`, no auth, no installer side effects needed |

**Why the versioned binary is the right pin:** the installer is an unversioned mutable URL. A digest
pin on it (option A) would redden this **required** check on every cosmetic xAI edit to `install.sh`,
and it would still leave the binary it fetches unpinned by content. The versioned binary (option B) is
the bytes that actually execute. A sha256 on them is a content pin, xAI can edit the installer without
touching it, and no third-party script is run. This is a stronger version of the Devin arm, which
content-pins a script and not the binary.

### Relevant files

- `.github/workflows/ci.yml` `grok-fidelity:` (≈L1346-1368). The job to retrofit.
- `.github/workflows/ci.yml` `harness-discovery:` (≈L1370-1474). The shape to mirror: job-level `env`
  pins declared once, `raw="$(… --version 2>&1 || true)"`, then a `grep -oE` semver parse, then
  `::error::…version-mismatch:${got:-<unparsed>}!=${PIN}`, then `exit 3`. There is also the
  `bash -e`-kills-the-assignment warning, which must be honoured the same way.
- `plugins/soleur/scripts/grok-fidelity-gate.sh:45-65`. The live `grok inspect` arm runs `if command -v
  grok`; otherwise it prints a WARNING and **`exit 1`** (fail-closed, since #6325; corrected at plan
  review, where an earlier draft of this plan misread it as fail-open). The install step's exit 3 is
  therefore defence in depth on that path, not its only closure. The gate script is not edited.
- `plugins/soleur/lib/grok-inspect-contract.ts:40` `ensureGrokFolderTrusted`. It creates `~/.grok`
  with `mkdirSync(recursive)` and so works without an installer-created home (measured above).
- `plugins/soleur/test/README.md` §Vendor-CLI pins (L55-81). It describes the pin table and the #8574
  freshness criterion, and currently names `grok-fidelity` as non-conforming.
- ADR-245 decision 3 (L50-54) plus Consequences "Pin staleness" (L74). These name `grok-fidelity` as
  the non-conformance.
- `knowledge-base/engineering/architecture/diagrams/model.c4:703`. The edge
  `github -> platform.grokBuild "CI installs the Grok CLI (x.ai install.sh) …"` becomes false. Its
  generated twin `model.likec4.json` is regenerated by `scripts/regenerate-c4-model.sh` (lefthook
  auto-runs it) and byte-diffed in CI (`plugins/soleur/test/c4-model-freshness.test.sh`).
- Out of scope: two unpinned non-CI sites, `apps/web-platform/infra/cloud-init-grok-dogfood.yml:62`
  and `scripts/dogfood/grok-gpu-bootstrap.sh:168`. These are dogfood host bootstraps, not CI gates,
  and ADR-245 decision 3 binds "any gate that drives a third-party CLI". They are acknowledged here
  and not deferred, because no policy covers them.

### Institutional learnings applied

- `harness-discovery` Codex-step comment (ci.yml): under GitHub's default `bash -e`, a
  `got="$(… | grep …)"` on a banner with no semver kills the step AT the assignment, so the
  diagnostic never prints. Use `raw=…|| true`, then `got=…|| true`.
- `harness-discovery` Devin-step comment: a version in a URL is a NAME the vendor can re-serve. Pin
  the content (sha256) and refuse to execute a changed file.
- `2026-03-19-npm-global-install-version-pinning.md` / `2026-03-19-docker-base-image-digest-pinning.md`:
  name pins drift, digest pins do not.
- f4c5f11b94 (Vector download stall): retry a large download instead of losing the job to one stall.

### Property List (Phase 0.6b)

- **P1**: The `grok` binary that `grok-fidelity` exercises is a specific, named version. A vendor
  release cannot change it.
- **P2**: If the installed binary is not the pinned one, the job exits non-zero and names
  `version-mismatch:<got>!=<pin>`, which is the same shape as `harness-discovery`.
- **P3**: The bytes executed are content-pinned. A re-served artifact under the same version name is
  refused before it runs.
- **P4**: The Grok pin sits under the same refresh criterion/cadence as the Codex/Devin pins (#8574).
- **P5**: The docs and C4 model that describe `grok-fidelity`'s install stop contradicting it.

### Cut List

- *Installer script + sha256 on `install.sh`* → P1/P3 → cut. It pins a mutable, unversioned script,
  would red a required check on installer edits, and does not content-pin the binary. The versioned
  binary + sha256 covers P1 and P3 directly.
- *Building a scheduled pin-freshness workflow* → P4 → cut. The issue asks to **join** #8574's
  comparison, not to build it. #8574 is the tracker that owns the criterion, so this is not an
  untracked deferral. The ownership gap (below) is surfaced on #8574 itself.
- *A static bun/shell test asserting the ci.yml step shape* → P2 → cut. `harness-discovery` has none,
  the job's own first CI run is the end-to-end proof, and the mutation matrix is exercised locally by
  running the step body against a scratch HOME (§Test Scenarios).
- *A post-gate "version still equals pin" re-assert step* → P1 (a self-update mid-gate) → cut in
  favour of `GROK_DISABLE_AUTOUPDATER=1`, the vendor's own process-level knob, set at job `env`. It
  can be revisited if a self-update is ever observed.
- *`.gz`/`.zst` artifact + decompress* → cut. The raw binary is simpler and needs no decompressor, and
  the ~166 MB download is well inside the 15-minute budget.

## Implementation

### Files to Edit

1. **`.github/workflows/ci.yml`**, job `grok-fidelity`:
   - Add job-level `env` (one declaration per pin, like `harness-discovery`):
     `GROK_PIN: "1.0.41"`,
     `GROK_SHA256: "9ce03ed23e16ea01072b4496263d6213a27899e1e3e107f008d36edf82e70407"` (a short comment:
     sha256 of `grok-${GROK_PIN}-linux-x86_64`, measured 2026-09-24; the vendor publishes no checksum,
     so this IS the content pin), `GROK_DISABLE_AUTOUPDATER: "1"` (a short comment: a self-update
     mid-gate would void the pin).
   - Replace step `Install Grok CLI` with `Install Grok CLI (exact pin + sha256 content pin)`:

     ```bash
     # Runs under GitHub's default `bash -e {0}`; `set -uo pipefail` ADDS -u/pipefail, it does not clear -e.
     set -uo pipefail
     tmp="$RUNNER_TEMP/grok-${GROK_PIN}"
     curl -fsSL --retry 2 --retry-delay 5 --connect-timeout 20 --max-time 120 \
       "https://x.ai/cli/grok-${GROK_PIN}-linux-x86_64" -o "$tmp" \
       || { echo "::error::grok-fidelity[grok] download-failed pin=${GROK_PIN}"; exit 3; }
     echo "${GROK_SHA256}  ${tmp}" | sha256sum -c - >/dev/null || {
       echo "::error::grok-fidelity[grok] binary-digest-mismatch — refusing to execute; got $(sha256sum "$tmp" | cut -d' ' -f1)"
       exit 3
     }
     install -D -m 0755 "$tmp" "$HOME/.grok/bin/grok"
     echo "$HOME/.grok/bin" >> "$GITHUB_PATH"
     export PATH="$HOME/.grok/bin:$PATH"
     # NOT got="$(grok --version | grep …)": under bash -e that kills the step at the assignment on a
     # semver-less banner (see harness-discovery's Codex step). `timeout` bounds a launch-time hang.
     raw="$(timeout 30 grok --version 2>&1 </dev/null || true)"
     got="$(printf '%s' "$raw" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
     [ "$got" = "$GROK_PIN" ] || {
       echo "::error::grok-fidelity[grok] version-mismatch:${got:-<unparsed>}!=${GROK_PIN} raw=${raw:0:200}"
       exit 3
     }
     echo "grok-fidelity[grok] pinned ${GROK_PIN} (sha256 ok)"
     ```

   - Update the job's header comment to one line: pinned per ADR-245 decision 3 (#8615), with
     freshness under #8574. Keep the prose short, because workflow files are byte-budgeted (ADR-231)
     and the rationale lives in ADR-245.
   - Leave the `harness-discovery` job untouched.
2. **`plugins/soleur/test/README.md`** §Vendor-CLI pins: retitle the lead-in from
   "`harness-discovery` drives two third-party CLIs" to cover both vendor gates. Add a Grok row
   (`1.0.41`, `https://x.ai/cli/grok-<pin>-linux-x86_64`, depth: "no versioned
   installer and no vendor checksum, so the job content-pins the binary itself by sha256 and never
   runs `install.sh`"). Name `GROK_PIN`/`GROK_SHA256` among the single-declaration env pins. Add the
   Grok freshness probe `curl -fsSL https://x.ai/cli/stable` to the #8574 sentence. **Replace** the
   "`grok-fidelity` … does NOT conform … #8615 tracks the retrofit" paragraph with a statement that it
   now conforms (and note that `grok-fidelity`, unlike `harness-discovery`, is required).
3. **ADR-245**: amend decision 3's non-conformance sentence with a dated amendment note in the
   ADR's existing inline-amendment style: "Amended 2026-09-24 (#8615): `grok-fidelity` now conforms.
   It pins the versioned binary (`GROK_PIN`), content-pins it by sha256 (xAI publishes no versioned
   installer and no checksum), asserts `grok --version`, exits 3 on drift, and sets
   `GROK_DISABLE_AUTOUPDATER=1`." Extend the Consequences "Pin staleness" bullet and the decision 3
   freshness bullet to include the Grok pin (`curl -fsSL https://x.ai/cli/stable`). Do not create a
   new ADR: this is conformance to an existing decision, not a new one.
4. **`knowledge-base/engineering/architecture/diagrams/model.c4:703`**: change the edge text to
   `"CI installs a pinned Grok CLI (versioned x.ai binary, sha256 content pin) and runs the
   inspect-contract + golden-path eval (grok-fidelity, ADR-245)"`. Keep `technology "HTTPS (curl) + CLI"`.
   Also fix the comment block above it (L695-699) if it mentions the installer. Then regenerate with
   `bash scripts/regenerate-c4-model.sh` and commit `model.likec4.json` (lefthook does this on commit
   too).

### GitHub write (work phase, after the PR is open)

5. **#8574 body**: append (preserving the existing body) a `## Pin-freshness criterion` section.
   It is currently stated only in ADR-245/README and not on the tracker. List all three pins with their
   probes: `npm view @openai/codex version`, Devin's current release, `curl -fsSL https://x.ai/cli/stable`.
   Note that a Grok bump must move `GROK_PIN` **and** `GROK_SHA256` together. State the ownership gap
   honestly: nothing executes this comparison today, and closing #8574 on promotion must hand the
   monthly cadence to a standing owner (a scheduled job or a recurring issue), or else the cadence dies
   with the issue. Use `gh issue view 8574 --json body -q .body > …`, append, then
   `gh issue edit 8574 --body-file …`.

### Files to Create

None.

## Plan Review

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

Two reviewers ran (the lead asked for proportionate fan-out): `soleur:engineering:review:kieran-rails-reviewer`
for correctness and `soleur:engineering:review:code-simplicity-reviewer`. Mechanical findings applied:

- The gate script is **fail-closed** (`exit 1`), not fail-open. That claim is corrected.
- The harness runs as `bash -e` and loads the env from `ci.yml`. Row 6 is now in the acceptance
  criteria, and the row-3 `sed` must match.
- There is a `timeout 30` on `grok --version`, and the retry count is consistent across the plan.
- AC1 now checks all three env vars.
- The GCS fallback, the `--resolve` harness row and the `harness-discovery` CR/LF fold-in are cut.

One finding was rejected with measured reasoning: "drop `set -uo pipefail`". It does not clear the
default `-e`, and it matches the Codex/Devin steps. Taste findings are in
`knowledge-base/project/specs/feat-one-shot-8615-pin-grok-cli/decision-challenges.md`.

## User-Brand Impact

- **If this lands broken, the user experiences:** every open PR in the repo shows a red required
  `grok-fidelity` check (for example `binary-digest-mismatch` or `download-failed`), which blocks
  merges until the pin is fixed. No end-user product surface is involved; the blast radius is the
  merge gate.
- **If this leaks, the user's data / workflow / money is exposed via:** no exposure vector. The job
  handles no secrets (no `secrets.*`, no auth: `grok inspect` runs unauthenticated), and the change
  reduces supply-chain exposure by removing a `curl | bash` of an unversioned third-party script.
- **Brand-survival threshold:** `none`

## Guard Contract

### Guard 1 — grok-fidelity vendor-CLI pin

**Property.** The `grok` that `grok-fidelity-gate.sh` executes is byte-identical to the
sha256-pinned `grok-${GROK_PIN}` artifact and reports `GROK_PIN`. Any other state stops the job with
exit 3 and a named reason, before the gate runs.

**Assembly.** There is one chokepoint: the `Install Grok CLI` step of `ci.yml` job `grok-fidelity`,
which is the only writer of `~/.grok/bin/grok` and the only `GITHUB_PATH` export for it. Every later
step resolves `grok` through that PATH entry. The pins (`GROK_PIN`, `GROK_SHA256`) are declared once,
at job `env`, and no step re-declares them. The gate's own
`command -v grok` arm is fail-closed (`exit 1`, grok-fidelity-gate.sh:64-65), and the default
`if: success()` on the gate step also keeps it from running after a red install. The self-update path inside `grok inspect` is closed by
`GROK_DISABLE_AUTOUPDATER=1` at job `env`.

**Mutation matrix:**

| # | Mutation (design-derived) | Expected |
|---|---|---|
| 1 | `GROK_SHA256` altered by one hex char (a re-served artifact) | RED: `binary-digest-mismatch`, exit 3, binary never installed or executed |
| 2 | `GROK_PIN` bumped to a real other version (`1.0.40`) without updating `GROK_SHA256` (a half-bump) | RED: `binary-digest-mismatch`, exit 3 |
| 3 | The digest-verified binary is fine, but a `grok` shim printing `grok 1.0.40` sits at `~/.grok/bin/grok` in place of the verified bytes (the install path reordered or skipped, so a different `grok` answers) | RED: `version-mismatch:1.0.40!=1.0.41`, exit 3 |
| 4 | `grok --version` prints a banner with no semver (a vendor output-format change) | RED: `version-mismatch:<unparsed>!=1.0.41` **with the diagnostic printed** (checks the `bash -e` trap is avoided) |
| 5 | `GROK_PIN=0.0.0` (a nonexistent artifact; 404, measured) | RED: `download-failed pin=0.0.0`, exit 3 |
| 6 | The guard's own dispatch: the `[ "$got" = "$GROK_PIN" ]` comparison deleted or made `|| true` | Rows 3/4 go GREEN, so the harness must report them as FAIL (see harness rows) |

**Harness rows.** The local simulation loads `ci.yml` once with PyYAML (`yq` is not installed) and
takes BOTH the step's `run` body AND `jobs["grok-fidelity"].env` from it. Pins are never retyped, and
the RED rows mutate the loaded env values. It runs the body as **`bash -e body.sh`** (GitHub's
default for an unkeyed `run:`, and the only mode in which row 4 tests the `bash -e` trap) against a
scratch `HOME`/`RUNNER_TEMP`/`GITHUB_PATH`. It asserts **both** `rc == 3` **and** the reason token for
every RED row. Row 3 replaces the `install -D` line with a shim write, and that `sed` must fail the
harness if it matched nothing. (a) A harness mutation that replaces the extracted body with `true`
must fail rows 1-5, which proves the harness reads the real step. (b) The must-PASS row is the
unmodified body with the ci.yml env: rc 0 and `grok-fidelity[grok] pinned 1.0.41` printed. (c) Row 6
is exercised: with the comparison line deleted from the body, the harness must report rows 3 and 4
as FAIL.

**Anchor.** `GROK_SHA256` and `GROK_PIN` live in the same diff as the step, so the guard proves
**consistency** of the checked-in pin, not upstream integrity. The external anchor is the vendor
artifact itself: a PR that changes `GROK_SHA256` must also produce bytes that hash to it at the
fixed version URL, which a PR author cannot forge. Reviewers treat any `GROK_SHA256` change without a
`GROK_PIN` change as suspicious (the same posture as `DEVIN_SETUP_SHA256`).

## Observability

```yaml
liveness_signal:
  what: "grok-fidelity job conclusion on every PR/push (required check row); the install step echoes 'grok-fidelity[grok] pinned <ver> (sha256 ok)'"
  cadence: "per CI run (every PR, every main push, merge_group)"
  alert_target: "PR check list (required check red blocks merge); on a main push the CI run conclusion goes red (web-platform-release.yml ci_not_green then holds that deploy)"
  configured_in: ".github/workflows/ci.yml job grok-fidelity; infra/github/ruleset-ci-required.tf context grok-fidelity"
error_reporting:
  destination: "GitHub Actions ::error:: annotation on the grok-fidelity job"
  fail_loud: "::error::grok-fidelity[grok] <download-failed|binary-digest-mismatch|version-mismatch:<got>!=<pin>> and exit 3"
failure_modes:
  - mode: "vendor re-serves different bytes under the pinned version name"
    detection: "sha256sum -c against GROK_SHA256 fails -> binary-digest-mismatch, exit 3"
    alert_route: "required check red on the PR"
  - mode: "installed/resolved grok is not the pinned version (PATH shadowing, half-bump)"
    detection: "parsed grok --version != GROK_PIN -> version-mismatch:<got>!=<pin>, exit 3"
    alert_route: "required check red on the PR"
  - mode: "pinned artifact unreachable or deleted"
    detection: "curl --retry 2 fails on the versioned x.ai URL -> download-failed, exit 3"
    alert_route: "required check red on the PR"
  - mode: "pin goes stale vs vendor stable"
    detection: "#8574 pin-freshness criterion (curl -fsSL https://x.ai/cli/stable vs GROK_PIN); nothing executes it on a schedule yet (stated on #8574)"
    alert_route: "#8574 tracker"
logs:
  where: "GitHub Actions run log for job grok-fidelity (gh run view --log)"
  retention: "GitHub Actions default log retention (90 days)"
discoverability_test:
  command: "grep -c 'GROK_PIN: \"' .github/workflows/ci.yml"
  expected_output: "1"
```

## Domain Review

**Domains relevant:** none

No cross-domain implications detected. This is an infrastructure/tooling change confined to one CI job
and the documents that describe it.

## Open Code-Review Overlap

None. 78 open `code-review` issues were checked against `grok-fidelity`, `.github/workflows/ci.yml`,
`plugins/soleur/test/README.md`, `ADR-245` and `model.c4`, with zero matches.

## Architecture Decision (ADR/C4)

### ADR

This amends **ADR-245** decision 3 (inline dated amendment). It records that the named
non-conformance is retrofitted, and extends "Pin staleness" to cover the Grok pin. There is no new
ADR, because the decision is unchanged and this is conformance to it.

### C4 views

All three model files were read for the actors and systems involved. The actor is `github` (CI). The
external system `platform.grokBuild` is already modelled, and the edge `github -> platform.grokBuild`
exists (model.c4:703). No new element and no new relationship are needed. The **edge description is
falsified** by this change ("x.ai install.sh"), so it is rewritten (Files to Edit #4). No
cardinalities change, and `plugins/soleur/test/c4-count-parity.test.sh` must stay green.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the
  threshold will fail `deepen-plan` Phase 4.6. It is filled above.
- **Bump both env values together.** A `GROK_PIN` bump without `GROK_SHA256` reds with
  `binary-digest-mismatch` (row 2), which is loud and intended. The bump procedure is
  `curl -fsSL https://x.ai/cli/stable`, then download `grok-<ver>-linux-x86_64`, then `sha256sum`,
  then update both.
- **Suffixed versions.** The installer allows `X.Y.Z-suffix`, but the semver parse extracts only
  `X.Y.Z`. The stable channel returns plain `1.0.41` today. If a pin ever carries a suffix, widen the
  regex in the same change.
- **Remote minimum-version policy.** The binary embeds `required_minimum_version` handling. That is
  applied via a managed config fetched with a deployment key, which this job does not have, so it is
  not active here. If xAI ever enforces a minimum unauthenticated, an old pin fails at `grok inspect`
  with a vendor error rather than at the version assert. The monthly freshness cadence is the
  mitigation.
- **Do not reintroduce `curl | bash`.** The installer also writes shell rc files and `config.toml`,
  and none of that is needed (binary-only parity is measured above).
- **Transport bound (analytical).** 3 attempts × `--max-time 120` + 2 × `--retry-delay 5` ≈ 370 s,
  under `timeout-minutes: 15` (900 s), so a total stall ends in the named `download-failed` exit 3
  rather than an anonymous job timeout. `--retry` without `--retry-all-errors` retries only transient
  classes (timeouts, 408/429/5xx), so a 404 fails fast. **A retry flag cannot turn failure into
  success here** (unlike the #6500 class in the catalogue): green requires `sha256sum -c` to match
  exact bytes, so a truncated or throttled body, or a 200 challenge page, reds as
  `binary-digest-mismatch`.
- **No GCS fallback (cut at plan review).** The installer falls back to
  `storage.googleapis.com/grok-build-public-artifacts/cli` (the same bytes, measured). A single URL
  matches the `harness-discovery` Devin precedent. If x.ai outages ever red this required check, add
  the fallback with the digest check inside the loop.
- **Annotation text.** `raw` is echoed into `::error::` without a CR/LF strip, the same as the
  Codex/Devin arms. The version assert only runs after the digest has pinned the bytes, so the text
  is the pinned binary's fixed output and cannot forge annotation lines.
- Local lints required by the lead, since both reddened CI on b879615671: this diff touches no
  `SKILL.md` and no `.ts`, so `lint-skill-body-budget` and ESLint are expected no-ops, but run them
  anyway in CI form (see Test Scenarios) instead of assuming.

## Acceptance Criteria

- [ ] `ci.yml` job `grok-fidelity` declares `GROK_PIN`, `GROK_SHA256` and `GROK_DISABLE_AUTOUPDATER`
      exactly once each at job `env`: `grep -c 'GROK_PIN: "'`, `grep -c 'GROK_SHA256: "'` and
      `grep -c 'GROK_DISABLE_AUTOUPDATER: "'` over `.github/workflows/ci.yml` each = 1, and
      `grep -c 'x.ai/cli/install.sh' .github/workflows/ci.yml` = 0.
- [ ] The install step downloads `https://x.ai/cli/grok-${GROK_PIN}-linux-x86_64`,
      verifies sha256 **before** installing or executing, installs to `~/.grok/bin/grok`, and asserts
      the parsed `grok --version` equals `GROK_PIN`. On drift it exits **3** with
      `::error::grok-fidelity[grok] version-mismatch:<got>!=<pin>`, and with
      `binary-digest-mismatch` / `download-failed` for the other two failure classes.
- [ ] Guard 1 mutation rows 1-5 are each observed RED locally (rc 3 plus the reason token). The
      must-PASS row is observed GREEN. Harness row (a) (body replaced by `true`) and row 6 (comparison
      deleted, so rows 3 and 4 are reported FAIL) are both observed. Every run is `bash -e`, with the
      body and env loaded from `ci.yml` by PyYAML.
- [ ] The first CI run on the PR shows `grok-fidelity` green, with the log line
      `grok-fidelity[grok] pinned 1.0.41 (sha256 ok)` and the live
      `grok inspect contract OK: … project agents, … plugin skills` line (proves the live arm ran).
- [ ] `plugins/soleur/test/README.md` §Vendor-CLI pins has a Grok row. The "does NOT conform"
      paragraph is replaced, and the #8574 freshness sentence includes `curl -fsSL https://x.ai/cli/stable`.
- [ ] ADR-245 decision 3 carries a dated #8615 amendment. "Pin staleness" covers the Grok pin.
- [ ] `model.c4` edge `github -> platform.grokBuild` no longer says "install.sh". `model.likec4.json`
      is regenerated and committed. `bash plugins/soleur/test/c4-model-freshness.test.sh` and
      `bash plugins/soleur/test/c4-count-parity.test.sh` pass, and
      `apps/web-platform` vitest `test/c4-code-syntax.test.ts test/c4-render.test.ts` passes.
- [ ] The #8574 body has the appended `## Pin-freshness criterion` section listing Codex, Devin and
      Grok probes and the ownership-gap note. The prior body is preserved (diff the before and after
      bodies).
- [ ] `actionlint .github/workflows/ci.yml` is clean. `bun test plugins/soleur/test/workflow-file-size.test.ts` passes.
      `python3 scripts/lint-skill-body-budget.py --base "$(git merge-base HEAD origin/main)"` exits 0.
- [ ] `infra/github/ruleset-ci-required.tf` is unchanged (`git diff --quiet origin/main -- infra/github/ruleset-ci-required.tf`).
- [ ] The PR body uses `Closes #8615` and references #8574 (without closing it).

## Test Scenarios

- Given the real pins, when the extracted install-step body runs against a scratch HOME, then it
  exits 0 and prints `pinned 1.0.41 (sha256 ok)`.
- Given `GROK_SHA256` with one char flipped, when it runs, then it exits 3 with
  `binary-digest-mismatch`, and `~/.grok/bin/grok` does not exist.
- Given `GROK_PIN=1.0.40` with the 1.0.41 digest, then it exits 3 with `binary-digest-mismatch`.
- Given a shim at `~/.grok/bin/grok` printing `grok 1.0.40` (the harness replaces the install line),
  then it exits 3 with `version-mismatch:1.0.40!=1.0.41`.
- Given a shim printing `Grok Build` (no semver), then it exits 3 with
  `version-mismatch:<unparsed>!=1.0.41` and the `raw=` diagnostic is present.
- Given `GROK_PIN=0.0.0`, then it exits 3 with `download-failed pin=0.0.0`.
- Given the pinned binary on PATH and `GROK_DISABLE_AUTOUPDATER=1`, when
  `bash plugins/soleur/scripts/grok-fidelity-gate.sh` runs locally, then it prints
  `grok inspect contract OK` and `grok-fidelity-gate: PASS` (the live arm, measured 2026-09-24 as zero
  violations).
- CI-form lints (lead instruction): `python3 scripts/lint-skill-body-budget.py --base "$(git merge-base HEAD origin/main)"`;
  `npx eslint` on touched `.ts` (none expected, so assert the touched-.ts list is empty with
  `git diff --name-only origin/main... -- '*.ts'`); `actionlint .github/workflows/ci.yml`.

## Dependencies & Risks

- The vendor could delete old artifacts. The pinned URL would 404, giving `download-failed` on every
  PR, which is loud and named. Mitigation: the #8574 monthly bump keeps the pin near current.
- The ~166 MB download adds seconds to a job measured at ≤0.5 min. There is a 15-minute ceiling.
- Honest limitation: the monthly pin-freshness comparison is a **documented criterion with no
  executor**. This PR adds Grok to it; it does not make it run. That is stated on #8574.

## References

- Issue #8615; tracker #8574; ADR-245 decision 3; `harness-discovery` job in `.github/workflows/ci.yml`.
- Vendor installer: `https://x.ai/cli/install.sh` (header documents `bash -s <version>`); artifacts
  `https://x.ai/cli/grok-<ver>-<os>-<arch>`; stable pointer `https://x.ai/cli/stable`.
