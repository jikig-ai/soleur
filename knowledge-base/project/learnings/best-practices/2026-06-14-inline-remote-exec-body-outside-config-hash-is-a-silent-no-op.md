---
title: "Terraform: an inline remote-exec assertion body is NOT covered by the resource's config_hash — edits to it are silent no-ops"
date: 2026-06-14
category: best-practices
tags: [terraform, triggers_replace, config_hash, remote-exec, drift-guard, infra]
issue: 5289
pr: 5291
---

# Inline `remote-exec` body outside `config_hash` is a silent no-op

## Problem

`terraform_data.cron_egress_firewall` (`apps/web-platform/infra/server.tf`) keyed its
`triggers_replace.config_hash` on the 9 delivered artifact files + `hcloud_server.web.id`,
but the **post-apply assertion block lived inline in a 2nd `remote-exec`** — content that
is NOT an input to `config_hash`. So an assertion-only edit changed zero hash inputs →
terraform reported `Apply complete! Resources: 0 added, 0 changed` → the new assertions
**never ran on the live host** until an unrelated artifact change or a VM replacement
re-provisioned the resource. PR #5280 demonstrated this exactly: it added `ASSERT-FAILED:`
self-reporting sentinels and merged with `0 changed` — the sentinels sat in the repo,
dormant.

## Solution

Extract the inline assertion body into a **delivered script** and fold its hash in, matching
the established loader/resolver/orphan-reaper pattern in the same root:

1. New `cron-egress-postapply-assert.sh` — `set -e` first, the verbatim assertion body.
2. `file("${path.module}/cron-egress-postapply-assert.sh")` added to the
   `config_hash = sha256(join(",", [ … ]))` list → an edit now changes the hash → re-provision.
3. A `provisioner "file"` delivers it (ordered after the artifact deliveries, before the runner).
4. The 2nd `remote-exec` collapses to a 3-line runner: `set -e` / `chmod +x` / `bash <script>`.
5. Mirror into `cloud-init.yml write_files` (fresh-host artifact parity; NOT executed at
   fresh-host time — no container, the script's own WARN-skip branch handles it).

## Key Insight

**Only what `file()`/`templatefile()`/`local.*` feeds into `triggers_replace` re-provisions a
`terraform_data`.** Inline `remote-exec`/`provisioner` bodies are invisible to the trigger
hash. If a remote-exec block carries logic that must re-run when it changes (assertions,
probes, idempotent installers), that logic belongs in a **delivered file** whose `file()` is
in the hash — never inline. The smell: a remote-exec body that has evolved across multiple PRs
while the resource still shows `0 changed` on those PRs' applies.

## Drift-guard retarget note

When the awk-extracted block moves from `$SERVER_TF` to a real `.sh`, the drift-guard
(`cron-egress-firewall.test.sh`) needs two surgical edits beyond changing the source file:
- The `^[[:space:]]*"curl ` unguarded-command arm loses its HCL leading-quote → anchor on the
  bare `^[[:space:]]*curl ` script form.
- Presence asserts that grepped a bare literal (`egress-probe-negative`) become
  comment-satisfiable once the block is a real file with comments — anchor on the
  `ASSERT-FAILED: <name>` executable-line sentinel instead (mutation-proven non-vacuous).

## Session Errors

- **`terraform fmt -check server.tf cloud-init.yml` exited 2** ("Only .tf, .tfvars, .tftest.hcl
  files can be processed"). `terraform fmt` rejects non-HCL args. **Recovery:** fmt `server.tf`
  only; validate `cloud-init.yml` via `cloud-init schema -c`. **Prevention:** never pass YAML to
  `terraform fmt`; one-off, self-evident from the error.
- **`../../node_modules/.bin/vitest: No such file or directory`** — assumed a vitest binary for
  `plugins/soleur/test/terraform-target-parity.test.ts`. Those suites are `bun:test`.
  **Recovery:** ran via `bun test`. **Prevention:** `plugins/soleur/test/*.ts` run under
  `bun test`, not vitest — the plan's AC prose said "vitest" but the harness is bun.

## Tags
category: best-practices
module: apps/web-platform/infra
