# Learning: editing cloud-init.yml (a Terraform templatefile) — `$$`/`%{` escaping, and how to test a jq-payload tag in ci-deploy.test.sh

**Date:** 2026-07-14 · **PR:** #6396 (web-host Vector log-shipping + boot-emit trap) · **Category:** best-practices

## Problem

Two recurring foot-guns surfaced while adding infra to `apps/web-platform/infra/`:

1. **`apps/web-platform/infra/cloud-init.yml` is a Terraform `templatefile()`**, so it is parsed by Terraform at render time BEFORE the shell/cloud-init ever sees it. Two edits broke the render (and `cloud-init-inngest-bootstrap.test.sh`, which does a live `terraform console` render):
   - A shell parameter-expansion `${TMPENV:-}` inside a `trap` was read as a Terraform interpolation → `Extra characters after interpolation expression … doesn't expect a colon`.
   - A `%{ if web_colocate_inngest }` written inside a **comment** was parsed as a Terraform template **directive** (unterminated) → `Error in function call`. Terraform's directive scanner does not skip `#`/`//`-style prose; a comment is not a safe place for `%{`.

2. **Testing that `ci-deploy.sh`'s `pull_failure_event` tags `host_id`** via a runtime Sentry-payload capture kept coming back empty. Plain `run_deploy` (default docker mock mode) does NOT honor `MOCK_DOCKER_PULL_FAIL` — only `run_deploy_traced` (trace mode) has the pull-fail branch — and even under trace mode the deploy proceeded past the pull to canary health checks, so the Sentry `/store/` POST was never emitted in that invocation. Multiple debug cycles chased an empty capture file.

## Solution

1. **cloud-init.yml templatefile hygiene:**
   - Shell `${VAR}` / `${VAR:-default}` must be written `$${VAR}` / `$${VAR:-default}` (double-dollar escapes the Terraform interpolation; it renders back to a single `${…}` on the host). `$stage`, `$rc`, `$?` (brace-free `$`) are passed through literally and need no escaping.
   - Never write `%{` in cloud-init.yml at all — including comments. Reword prose to avoid it (e.g. "the web_colocate_inngest gate block", not "the `%{ if web_colocate_inngest }` block").
   - **Verify with a real render after EVERY edit**, don't trust `sh -n`/eyeballing:
     ```bash
     printf 'templatefile("%s", { <full var map> })\n' "$PWD/cloud-init.yml" \
       | terraform -chdir="$(mktemp -d)" console
     ```
     rc=0 + zero `Error` lines = clean. Then validate the RENDERED output (strip terraform console's `<<EOT … EOT` wrapper) with `cloud-init schema -c <rendered>` — running `cloud-init schema` on the RAW template always fails on the un-rendered interpolations (a false alarm, not a real error).

2. **Testing a jq-built Sentry-payload tag in ci-deploy.test.sh:** prefer a **source-level assertion** over a runtime capture. Scope an `awk` range to the function body and AND two tight greps:
   ```bash
   body="$(awk '/^pull_failure_event\(\) \{/,/^\}/' "$DEPLOY_SCRIPT")"
   printf '%s' "$body" | grep -qE -- '--arg h "\$\{HOST_ID:-\}"'   # pins $h = HOST_ID
   printf '%s' "$body" | grep -qE 'host_id: \$h'                    # pins tag-key → var
   ```
   This is deterministic, body-scoped (an unrelated `host_id` elsewhere can't satisfy it), and pins the key→var wiring so a drift that drops either half goes RED. Runtime value/reachability is already covered elsewhere (`host-identity.test.ts` + `assert_soleur_host_id`). If a runtime capture IS wanted: use `run_deploy_traced` (not `run_deploy`) so `MOCK_DOCKER_PULL_FAIL` is honored.

## Key Insight

**A single committed file can be parsed by more than one tool at different lifecycle stages — cloud-init.yml is Terraform-templated at plan time and shell-executed at boot — so an edit must satisfy the EARLIEST parser first, and comments are not exempt from it.** Verify with the earliest parser's own render, not the final consumer's mental model. And when a runtime test harness fights you for a payload assertion, a body-scoped source grep that pins the exact wiring is a reliable, non-vacuous substitute (the value/reachability halves are owned by other tests).

## Session Errors (#6396 one-shot)

1. **Ran `grok-pre-push-gate.sh` on the Claude harness** — it launched full `test-all.sh` and timed out (2m), consuming the push window. **Recovery:** direct `git push`. **Prevention:** `grok-pre-push-gate.sh` is a **Grok-Build-only** step (one-shot SKILL.md labels it "REQUIRED before git push (Grok Build)"); on the Claude harness, push directly (lefthook covers the local gate).
2. **ci-deploy.test.sh runtime host_id capture returned empty (several cycles).** **Recovery:** pivoted to the source-level assertion above. **Prevention:** documented — `run_deploy` ignores `MOCK_DOCKER_PULL_FAIL`; use `run_deploy_traced`, or assert at source.
3. **Debug `sed` corrupted the test file** — patterns containing `/store/` with a `#` delimiter errored (`unknown option to s`), and the cp/mv backup dance reverted an unrelated edit. **Recovery:** manual re-fix. **Prevention:** use `python3` for text edits containing regex metacharacters; run debug mutations on a `/tmp` COPY, never the working file.
4. **cloud-init templatefile render broke twice** (`${TMPENV:-}`, `%{` in a comment). **Recovery:** `$$`-escape + reword. **Prevention:** the templatefile-render check above, run after every cloud-init.yml edit.
5. **`cloud-init schema` on the raw template failed** — expected (TF interpolations); **Prevention:** validate the rendered output, not the raw template.
6. **Two review agents died mid-response** (API connection closed). **Recovery:** re-spawned observability fresh; architecture was covered by the security + user-impact agents. **Prevention:** infra flake — re-spawn the specialized agent type fresh.
7. **`subagent_type: fork` to "resume" a dead agent echoed my own context** (0 tool uses), not an independent review. **Prevention:** to redo a failed specialized review, re-spawn that same specialized `subagent_type` — `fork` inherits the PARENT's context, not the dead agent's.

## Tags
category: best-practices
module: apps/web-platform/infra
