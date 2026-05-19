---
module: Web Platform Infrastructure
date: 2026-05-18
problem_type: integration_issue
component: tooling
symptoms:
  - "Playwright browser_evaluate returns a vendor token into the conversation transcript"
  - "Doppler stores a token with surrounding JSON-string quotes; API tolerates but Terraform rejects"
  - "Container-based OCI deploy script fails at systemctl daemon-reload because the Alpine base lacks systemctl"
  - "Doppler --name-transformer tf-var does not strip an existing TF_VAR_ prefix from secret names"
root_cause: workflow_drift
resolution_type: skill_instruction_change
severity: medium
tags: [playwright, doppler, terraform, oci, alpine, systemctl, betterstack, inngest, vendor-token-mint]
synced_to: []
---

# Vendor-token mint via Playwright + OCI image as host-content-carrier (PR-A / #3960)

## Problem

PR #3973 (PR-F follow-up: IaC for inngest-server) required two operator-only credential mints (BetterStack API token, Doppler workplace personal token) and a containerized bootstrap delivery for inngest-server. Four distinct failure classes surfaced across these surfaces:

1. **Token leakage** when extracting via Playwright's `browser_evaluate` without the `filename` parameter — the return value writes to the conversation transcript by default.
2. **Token corruption** when extracting WITH `filename` — the parameter JSON-encodes the result, surrounding the value with quotes that downstream consumers (Terraform) reject even if some vendors (BetterStack) silently tolerate.
3. **Architectural mismatch** between a containerized bootstrap script and the host-management commands it needs to run (`systemctl daemon-reload`, `enable --now`) — Alpine 3.20's default package set has `bash curl tar coreutils` but NOT `systemctl`.
4. **Naming convention drift** when storing TF vars in Doppler — `--name-transformer tf-var` ADDS the prefix at injection time, so secrets must be stored WITHOUT the prefix.

## Environment

- Module: Web Platform Infrastructure (apps/web-platform/infra/)
- Terraform 1.10.5 with DopplerHQ/doppler 1.21.2 + BetterStackHQ/better-uptime 0.20.17 providers
- Playwright MCP for vendor UI automation
- Self-hosted Inngest server (ADR-030)
- Date: 2026-05-18

## Symptoms

- `browser_evaluate(function: () => document.querySelector(...).textContent)` returned a 24-character BetterStack API token directly into the conversation transcript.
- `browser_evaluate(function: () => ..., filename: ".playwright-mcp/bs-token.txt")` saved 26 bytes (token + 2 quote chars).
- `curl -H "Authorization: Bearer "abc"" ...` returned 200 from BetterStack (vendor silently tolerated extra quotes).
- `terraform plan` returned `Error: No value for required variable` for `doppler_token_tf` and `betterstack_api_token` despite both being stored in Doppler `prd_terraform` (they were stored as `TF_VAR_*` instead of bare names).
- `docker run --rm --net=host --pid=host -v ... --entrypoint /inngest-bootstrap.sh ...` would have failed at `systemctl daemon-reload` (script line 155) because Alpine 3.20 + `apk add bash curl tar coreutils` has no systemd tooling.

## What Didn't Work

**Attempted Solution 1:** Extract token via `browser_evaluate` return value.

- **Why it failed:** The return value writes to the conversation transcript. Even after revoking the token, the transcript retains the value. This is a hard-to-recover information leak.

**Attempted Solution 2:** Extract via `browser_evaluate(filename: ...)`, then `cat` the file and pipe to Doppler.

- **Why it failed:** The `filename` parameter JSON-encodes the function's return value. A 24-character token becomes 26 bytes on disk (with surrounding `"`). `doppler secrets set <KEY> <"...">` stored the quoted form. BetterStack's API tolerated the extra quotes in `Authorization: Bearer "abc"` (this was misleading — it suggested success), but Terraform's HCL string handling would have failed when the provider built its API client.

**Attempted Solution 3:** Run `inngest-bootstrap.sh` inside the container via `docker run --rm --pid=host -v /etc/systemd/system:/etc/systemd/system ...`.

- **Why it failed:** Bind-mounting `/etc/systemd/system` doesn't give the container a `systemctl` binary. Mounting `/usr/bin` would have masked the container's own binaries. The Alpine apk packages don't include systemd (and shouldn't — Alpine uses OpenRC by default; systemd packages are large and unconventional).

**Attempted Solution 4:** Store TF vars in Doppler as `TF_VAR_DOPPLER_TOKEN_TF`.

- **Why it failed:** `doppler run --name-transformer tf-var` converts Doppler secret names to Terraform var names by lowercasing and ADDING the `TF_VAR_` prefix. Secret `DOPPLER_TOKEN_TF` → env var `TF_VAR_doppler_token_tf` ✓. Secret `TF_VAR_DOPPLER_TOKEN_TF` → env var `TF_VAR_tf_var_doppler_token_tf` ✗. The existing learning `knowledge-base/project/learnings/2026-03-21-doppler-tf-var-naming-alignment.md` documented this exact rule; this session's drift was a workflow gap (the convention wasn't enforced at mint time).

## Session Errors

10 errors enumerated at compound Phase 0.5 (see compound output). The top four mapped to workflow proposals below; remaining six are one-offs or already-documented.

**Token leaked via browser_evaluate return** — Recovery: revoked the leaked token via in-page DELETE fetch using the page's CSRF token (`document.querySelector('meta[name="csrf-token"]').content`), then re-minted with `filename` parameter. — **Prevention:** vendor-token extraction via Playwright MUST use `filename` parameter from the first attempt, regardless of how brief the intermediate read seems.

**Double-POST during BetterStack mint** — Recovery: deleted both tokens (58449 + 58450) via in-page DELETE. — **Prevention:** when driving form submissions via `fetch(form.action, {method: 'POST', body: new FormData(form)})`, do NOT also click the submit button; pick one path.

**`filename` saves JSON-encoded result** — Recovery: `doppler secrets get <KEY> --plain | python3 -c "import sys,json; sys.stdout.write(json.loads(sys.stdin.read()))" | doppler secrets set <KEY> --no-interactive`. — **Prevention:** add JSON-decode to the canonical Playwright-token-extract pattern. Belongs in the work skill's vendor-mint section.

**Doppler TF var naming drift** — Recovery: copied `TF_VAR_X` → `X` via `doppler secrets get | doppler secrets set`, deleted the prefixed copy. — **Prevention:** when storing a TF var in Doppler, drop the `TF_VAR_` prefix. The work skill's Phase 0 should reference `2026-03-21-doppler-tf-var-naming-alignment.md`.

**Alpine image lacks systemctl** — Recovery: changed ci-deploy.sh's inngest branch to extract the script + ENV vars from the image (via `docker create + docker cp + docker inspect`) and execute on the HOST via `sudo -E env ... bash <script>`. — **Prevention:** when an OCI image needs to run host-management commands (systemd, dbus, /etc/systemd/system mutations), the image is a CONTENT CARRIER, not an EXECUTION CONTEXT. Extract content; run on host.

**Worktree CWD reset after Bash `cd`** — Already documented; chain `cd <abs-path> && <cmd>` in single Bash call. — No new prevention.

**`doppler secrets delete --no-interactive` is invalid (flag is `--yes`)** — Recovery: re-ran with `--yes`. — **Prevention:** existing Sharp Edge in review skill covers CLI flag verification.

## Solution

### Playwright vendor-token extraction (canonical pattern)

```javascript
// In browser_evaluate, with filename: ".playwright-mcp/<vendor>-token.txt"
() => {
  const el = document.querySelector('p[id^="token-..."]');
  if (!el) return 'COUNT-ERROR:0';
  const txt = el.textContent.trim();
  if (txt.length < 20 || txt.length > 80) return 'LEN-ERROR:' + txt.length;
  return txt;
}
```

Then on the host:
```bash
TOKEN_FILE=.playwright-mcp/<vendor>-token.txt
FIRST6=$(head -c 6 "$TOKEN_FILE")
if [[ "$FIRST6" == "COUNT-" || "$FIRST6" == "LEN-ER" ]]; then
  echo "EXTRACT-FAILED:" >&2; cat "$TOKEN_FILE" >&2; exit 1
fi
# JSON-decode the filename-saved result before piping to Doppler:
python3 -c "import sys,json; sys.stdout.write(json.loads(open('$TOKEN_FILE').read()))" | \
  doppler secrets set <KEY> --project soleur --config prd_terraform --no-interactive >/dev/null
# Validate against vendor API before shredding (token_len check is the trap-detector):
TOKEN=$(doppler secrets get <KEY> --project soleur --config prd_terraform --plain)
HTTP=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $TOKEN" "$VENDOR_API_PING")
echo "api=$HTTP len=${#TOKEN}"
unset TOKEN
shred -u "$TOKEN_FILE"
```

The clipboard-pipe variant (for `●●●`-masked UI tokens like Doppler personal tokens):
```bash
# Click the in-page copy button via browser_evaluate first.
xclip -selection clipboard -o > "$TOKEN_FILE"
# Validate prefix shape:
FIRST=$(head -c 6 "$TOKEN_FILE")
if [[ ! "$FIRST" =~ ^dp\.pt\. ]]; then echo "PREFIX-MISMATCH"; exit 1; fi
# Pipe + shred as above. Also clear clipboard:
xclip -selection clipboard -i </dev/null
```

### OCI image as content-carrier-only (canonical pattern)

When an OCI image bundles a host-execution script + pinned content (binary + SHA), the deploy flow MUST:

1. `docker pull <image>:<tag>` — fetch the content-addressed layer.
2. `docker create --name <ephemeral> <image>:<tag>` (no `--rm`).
3. `docker cp <ephemeral>:/<script> /tmp/<script>` — extract the script.
4. `docker inspect <image>:<tag> -f '{{range .Config.Env}}{{println .}}{{end}}'` — read pinned ENV vars (version, SHA256) baked at build time.
5. `docker rm <ephemeral>` — clean up.
6. `sudo -E env VAR=val ... bash /tmp/<script>` — execute on host.

The Dockerfile becomes:
```dockerfile
FROM alpine:3.20
RUN apk add --no-cache bash curl tar coreutils
ENV PINNED_VERSION=...
ENV PINNED_SHA256=...
COPY script.sh /script.sh
RUN chmod +x /script.sh
# ENTRYPOINT remains for compatibility but is bypassed by the host-extract flow.
ENTRYPOINT ["/script.sh"]
```

This preserves: SHA-pinned binary (image layer is content-addressed), version pinning via image tag, easy rollback, but executes in the host's systemd context. See `apps/web-platform/infra/ci-deploy.sh` `case "inngest")` branch for the canonical implementation.

### Doppler TF var naming

Store TF vars in Doppler WITHOUT the `TF_VAR_` prefix:
```bash
# Correct:
doppler secrets set DOPPLER_TOKEN_TF --project soleur --config prd_terraform --no-interactive
# Wrong (will not resolve via --name-transformer tf-var):
doppler secrets set TF_VAR_DOPPLER_TOKEN_TF ...
```

`doppler run --name-transformer tf-var` performs case-folding + prefix-addition: secret `DOPPLER_TOKEN_TF` → env var `TF_VAR_doppler_token_tf` which matches `variable "doppler_token_tf"` in `variables.tf`.

## Why This Works

1. **`filename` writes to a file outside the conversation transcript**, so the token never enters the LLM's context window — defense against transcript-resident credential leakage.
2. **JSON-decode strips the JSON-string wrapping**, producing the byte-exact original value Terraform's HCL parser expects.
3. **Extract-and-run-on-host** preserves the OCI image's SHA-pinning value (the content layer is what's tag-immutable) while gaining access to the host's systemd-tools — the container's role shrinks to "verified delivery vehicle."
4. **Drop the prefix** because `--name-transformer tf-var` is an ADDITIVE transform, not idempotent: `TF_VAR_FOO` → `TF_VAR_tf_var_foo`.

## Prevention

- **Add to `/work` skill Phase 0 (vendor-token mint section):** the JSON-decode pipeline above + the `filename`-first rule. Reference this learning by path.
- **Add to `/work` skill Phase 0 (Doppler TF var section):** drop the `TF_VAR_` prefix before storing. Reference `2026-03-21-doppler-tf-var-naming-alignment.md`.
- **Add to `/review` skill Sharp Edges:** when reviewing OCI Dockerfile additions, verify the base image ships every binary the entrypoint script calls. `apk add` / `apt-get install` lines should be cross-checked against the script's `command -v` calls or hard-coded paths.
- **Add to `/plan` skill Sharp Edges:** when a plan prescribes "vendor X dashboard for credential mint," verify against the SDK integration code whether the runtime mode actually USES vendor X's cloud-issued credentials (vs. self-hosted operator-chosen randoms).

## Related Issues

- PR #3973 (this PR-A) — IaC for inngest-server
- PR #3940 (PR-F) — Inngest trigger layer + CFO autonomous-draft (parent)
- PR #3963 — plan Phase 2.8 IaC routing gate (first dogfood of)
- Issue #3960 — post-merge operator follow-through
- See also: `knowledge-base/project/learnings/2026-03-21-doppler-tf-var-naming-alignment.md`
- See also: `knowledge-base/project/learnings/integration-issues/2026-04-05-terraform-doppler-dual-credential-pattern.md`
- See also: `knowledge-base/project/learnings/2026-03-20-terraform-base64encode-cloud-init-deduplication.md`

## Plan deviations recorded

Five plan deviations are recorded in `apps/web-platform/infra/inngest.tf` header and the plan's `## Plan Deviations (Phase 1)` section:

1. Inngest 4 secrets → `random_id` resources (was: operator mint).
2. Doppler provider → single workplace token (was: two per-config aliases).
3. `[ack]` operator-mint count: 6 → 2.
4. OCI image tag → plain `vX.Y.Z` (was: `vinngest-vX.Y.Z`).
5. cloud-init embedding + `server.tf triggers_replace` for `inngest-bootstrap.sh` skipped.
