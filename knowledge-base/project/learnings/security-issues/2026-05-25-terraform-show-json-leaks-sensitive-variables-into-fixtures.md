---
date: 2026-05-25
category: security-issues
module: ci-workflows / terraform-fixtures
incident_severity: P1
caught_by: security-sentinel (post-implementation review)
caught_at: review-time (not pre-commit)
network_exposure: none (commit was local-only when caught)
tags:
  - terraform-show-json
  - github-app-private-key
  - fixture-redaction
  - secret-scrub
  - rotation-required
related:
  - knowledge-base/project/learnings/2026-05-16-adr-amendment-required-when-reversing-and-destroy-guard-empty-string-bypass.md
  - hr-never-paste-secrets-via-bang-prefix
---

# `terraform show -json` embeds sensitive HCL variables into fixtures verbatim

## Problem

PR `feat-fix-destroy-guard-nested-block-3915` introduced a captured-real Terraform plan fixture at `tests/scripts/fixtures/tfplan-real-ruleset-baseline.json` as a regression anchor against `integrations/github` provider drift. The capture command was:

```bash
doppler run -p soleur -c prd_terraform --name-transformer tf-var -- \
  terraform plan -out=tfplan
terraform show -json tfplan > /tmp/raw.json
jq 'del(.. | .bypass_actors? | .[]?.actor_id?)' /tmp/raw.json > <fixture>
```

The plan's §Phase 1.3 prescribed the redaction filter, and `/work` executed it verbatim. Post-redaction "manual scan" was prescribed as: *"Manual review of the result: no token values, no actor_id integers."*

**What the redaction missed:** the resulting fixture's `.variables` block contained the full `github_app_private_key.value` as a literal `-----BEGIN RSA PRIVATE KEY-----` … `-----END RSA PRIVATE KEY-----` PEM body, paired in plaintext with `github_app_id = "3261325"` and (in another part of the JSON) `installation_id = "122213433"`. The full App-auth triple needed to mint installation tokens for `jikig-ai/soleur` was committed locally.

**Why the variable wasn't redacted by `sensitive = true`:** `terraform-show-json` emits an unconditional top-level `.variables` map carrying every plan-input variable, regardless of the `sensitive` flag on the HCL declaration. `sensitive = true` suppresses CLI output (the `terraform plan` text rendering) — it does NOT redact the JSON serialization. This is documented but easily missed under the framing "we marked it sensitive".

**Detection latency:** caught by `security-sentinel` during post-implementation multi-agent review. By that point, 9 other review agents had also read the fixture (via Read or `jq`), so the PEM bytes had entered each agent's /tmp transcript. The Sentinel's escalation triggered the recovery flow.

## Root cause

Three independent gaps composed to allow the leak:

1. **`terraform-show-json` variable embedding** — the redaction author assumed `sensitive = true` masked HCL variables in JSON output. It does not.
2. **Plan-prescribed redaction was incomplete and downstream work treated it as authoritative.** `/work` executed the jq filter verbatim without asking "does this filter cover every class of secret that could appear in this artifact?" The plan is authoritative for *intent*, never for *redaction completeness* — same shape as `hr-when-a-plan-specifies-relative-paths-e-g`.
3. **No pre-`git add` secret-scan gate.** Lefthook (or any equivalent gitleaks gate) did not scan the staged fixture before the commit landed. The only safety net was post-implementation multi-agent review, which fires too late — by then 10 agents have touched the file.
4. **The "manual scan" step in the plan was a token-shaped regex, not a PEM-shaped one.** Plan §Phase 1.3 step 4 said "no token values, no actor_id integers"; the canonical scan set in the operator's head did not include `BEGIN [A-Z ]*PRIVATE KEY`.

## Solution (recovery)

Bytes never crossed the network boundary (commit was local-only — work skill's Phase 4 entry-guard pushed an unrelated commit later in the chain after the fixture was already cleaned). The full recovery flow:

1. **Rotate the key on the App settings page.** `https://github.com/organizations/<org>/settings/apps/<app>` → Private keys → Generate a private key. UI-only flow (no REST endpoint exists for App private-key creation). Drove via Playwright MCP; operator handled the GitHub Mobile sudo-mode push challenge.
2. **Mirror the new key to Doppler.** `cat <new>.pem | doppler secrets set GITHUB_APP_PRIVATE_KEY -p soleur -c prd_terraform --no-interactive` — stdin pipe so the key body never enters the conversation transcript.
3. **Verify the new key works.** Mint an installation token via JWT-RS256 + `POST /app/installations/{id}/access_tokens`; probe `GET /installation/repositories` → expect HTTP 200.
4. **Verify the old key is revoked.** Repeat the JWT mint with the leaked key → expect HTTP 401 "JSON web token could not be decoded".
5. **Delete the old key from the App settings UI.** Identify by SHA-256 fingerprint of the DER-encoded public key (GitHub format: `openssl rsa -in <pem> -pubout -outform DER | openssl dgst -sha256 -binary | base64`).
6. **Strip `.variables` from the fixture.** `jq 'del(.variables) | del(.. | .bypass_actors? | .[]?.actor_id?)' raw.json > fixture.json`.
7. **Scrub the dead-bytes from local git history.** `git reset --soft HEAD~1 && git commit -m "<clean>" && git reflog expire --expire=now --all && git gc --prune=now` — drops the old commit object so the leaked-key blob is unreachable and reaped.
8. **Shred all local PEM copies + helper scripts** (`shred -uz`).

## Prevention (layered defense)

**Layer 1 — Plan-time redaction template.** When a plan prescribes a "capture real provider output → redact → commit as fixture" workflow, the redaction filter MUST start from a canonical template, not be authored ad-hoc. Canonical jq filter for `terraform-show-json` fixtures:

```jq
del(.variables)                                     # strip ALL plan-input vars (sensitive=true does NOT redact here)
| del(.. | .bypass_actors? | .[]?.actor_id?)       # scrub bypass actor IDs (already common)
| del(.. | .raw_value?, .raw_password?, .private_key?, .password?, .secret?)  # scrub explicit secret-shaped keys at any depth
```

And the post-redaction MANDATORY scan regex:

```bash
! grep -qE 'BEGIN [A-Z ]*PRIVATE KEY|ghp_[A-Za-z0-9_]{20,}|ghs_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk_(test|live)_[A-Za-z0-9]{20,}|sbp_[A-Za-z0-9]{20,}|xoxb-[A-Za-z0-9-]{20,}|AKIA[0-9A-Z]{16}' <fixture>
```

**Layer 2 — `/work` pre-`git add` secret-scan gate.** Before staging any file under `tests/scripts/fixtures/`, `tests/**/*.json`, `**/*tfplan*.json`, or `**/*.pem`/`**/*.key`/`**/*.crt`, run the canonical regex above and refuse to stage on any match. Independent of any plan's redaction prescription — defense-in-depth.

**Layer 3 — Lefthook pre-commit hook.** Block any commit whose staged diff matches the canonical PEM/token regex. Same regex as layer 2; this is the last line before the bytes land in `.git/objects`.

**Layer 4 — CODEOWNERS scope on fixture paths.** When a fixture is load-bearing for a security gate (this PR's destroy-guard counter), CODEOWNERS rows must cover both the gate file AND the fixture path. A fixture mutated to neutralize the gate is identical-blast-radius to mutating the gate itself.

**Layer 5 — Post-implementation multi-agent review.** Already running; `security-sentinel` caught this. But this is too-late detection — the file has been read by sibling review agents and the bytes have entered their transcripts. Treat review-time detection as a **failure mode**, not the safety net.

## Key insight

`terraform show -json` is a **trust-boundary crossing**: it converts in-memory Terraform state (where `sensitive = true` is honored at render time) into a serialized JSON document where the sensitivity flag is not load-bearing. **Any code path that captures the JSON serialization and writes it to a tracked file must redact `.variables` unconditionally, regardless of HCL annotation.** The generalization: when a tool's documentation says "sensitive output is masked", verify that the mask survives every serialization the tool emits, not just the default text output.

## Session Errors

- **Plan-prescribed redaction insufficient (P1):** plan v2's `del(.. | .bypass_actors? | .[]?.actor_id?)` missed the `.variables` block entirely. **Recovery:** rotate key, strip block, git reset --soft + gc. **Prevention:** Layer 1 template above; AGENTS hard rule on terraform-show-json redaction.
- **/work executed plan-prescribed redaction verbatim without independent audit:** the work skill has rules against trusting plan-specified paths (`hr-when-a-plan-specifies-relative-paths-e-g`) but nothing equivalent for plan-specified secret-scrub filters. **Recovery:** same as above. **Prevention:** Layer 2 — work skill pre-stage secret-scan gate, regardless of what the plan prescribed.
- **No pre-`git add` secret scan ran:** lefthook had no PEM/token regex on staged files under `tests/scripts/fixtures/`. **Recovery:** manual cleanup. **Prevention:** Layer 3 — lefthook hook on fixture paths + canonical regex set.
- **Operator "manual scan" used token regex, not PEM regex:** the plan's "no token values" framing biased the scan toward `ghp_`/`ghs_`/`sbp_` prefixes and away from PEM headers. **Recovery:** add `BEGIN [A-Z ]*PRIVATE KEY` to the canonical regex set everywhere it appears (plan template, work hook, lefthook). **Prevention:** Layers 1+2+3.
- **CWD persistence between Bash calls** (`cd infra/github && terraform ...` leaked into next call): cosmetic, recovered with absolute paths. **Prevention:** prefer `git -C <abs>` or `cd <abs> && cmd` chained in single call, never split across Bash calls.
- **`security_reminder_hook` advisory output treated as deny on first attempt:** retry succeeded. **Prevention:** none required — hook behavior was correct as written; the harness's deny-on-any-stderr is the over-broad classifier. Out of scope here.
- **GitHub sudo-mode regenerated push code each navigation:** operator had to approve a fresh code on each `browser_navigate` to the App settings page. **Prevention:** navigate ONCE to a sudo-protected page, perform all UI actions in the same context without re-navigating. Documented as Playwright pattern; not adding to AGENTS.

## Related

- Rotation pattern (UI-only, with API verification) → see vendor-token learning `2026-05-18-vendor-token-mint-and-oci-image-content-carrier-patterns.md` for the `browser_evaluate(filename: ...)` pattern + Doppler stdin-pipe.
- Destroy-guard plan was reviewed by 3 agents at plan time (DHH/Kieran/simplicity), yet none surfaced the fixture's `.variables` exposure — the plan's redaction filter was treated as a black box by plan-reviewers. **Plan-review agents do not deeply audit ad-hoc redaction filters.** This is a known gap, not an agent failure.
