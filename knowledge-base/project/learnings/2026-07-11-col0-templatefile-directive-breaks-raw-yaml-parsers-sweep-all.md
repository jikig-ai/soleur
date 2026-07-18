---
title: "A col-0 templatefile `%{ if }` directive in cloud-init.yml breaks EVERY test that raw yaml.safe_loads it — sweep all raw parsers"
date: 2026-07-11
category: test-failures
module: apps/web-platform/infra
tags: [terraform, templatefile, cloud-init, yaml, orphan-suite, write-boundary-sweep, inngest-cutover]
related_pr: 6344
related_issue: 6178
---

# Learning: col-0 templatefile directives break raw YAML parsers of the same file

## Problem

Gating a cloud-init runcmd block behind a Terraform `templatefile` conditional requires
**column-0** directive lines (`%{ if web_colocate_inngest ~}` / `%{ endif ~}`) — an indented
directive both fails raw-parse AND corrupts the render (verified via `terraform console`).

But a `%` at **column 0** is a YAML *directive indicator* (`%YAML`, `%TAG`), so
`yaml.safe_load(open("cloud-init.yml"))` on the RAW (un-rendered) file now throws
`ScannerError: ... line 636, column 2`.

The plan anticipated ONE such parser — `cloud-init-inngest-bootstrap.test.sh` AC3 — and
fixed it (strip `^%{` before parse). It **missed an orphan sibling**:
`journald-config.test.sh` AC6 independently ran `yaml.safe_load(open($CLOUD_INIT))` and went
red. The touched-file test loop never ran journald (it's a *different* test file); only the
**targeted full-suite exit gate** (run every infra `*.test.sh` referencing `cloud-init.yml`)
surfaced it.

## Solution

1. **Strip col-0 directives before parsing the raw source**, in every test that raw-parses it:
   ```sh
   grep -v '^%{' "$CLOUD_INIT" | python3 -c "import sys,yaml; yaml.safe_load(sys.stdin)"
   ```
2. **Sweep ALL raw parsers**, not just the one the plan named:
   ```sh
   git grep -nE "safe_load|yaml\.load" -- '*.test.sh' '*.test.ts' '*.py'
   ```
   Filter to hits that target the RAW `cloud-init.yml` (not a workflow yaml, not a rendered
   doc). Here: exactly two (`cloud-init-inngest-bootstrap.test.sh`, `journald-config.test.sh`).
   The three TS tests that `readFileSync` cloud-init.yml do NOT `safe_load` it (string
   `toContain` / gzip-size model) — unaffected.
3. **Assert rendered-state YAML validity ONCE, in a terraform-render leg** — not by re-parsing
   the raw file. Render the real production template via `terraform console` in a scratch dir
   (no init/backend needed — `templatefile()` is a built-in function):
   ```sh
   printf 'templatefile("%s", { ...all server.tf map vars..., web_colocate_inngest=%s })\n' \
     "$CLOUD_INIT" "$CASE" | terraform -chdir="$(mktemp -d)" console
   ```
   Assert omission/retention on the rendered output; strip terraform console's `<<EOT … EOT`
   heredoc wrapper before `yaml.safe_load`.

## Key Insight

**A col-0 templatefile directive is a write-boundary-sweep class** (cf. hard rule
`hr-write-boundary-sentinel-sweep-all-write-sites`): any static consumer that parses the RAW
templated file — not its rendered output — must be updated in the same PR. The touched-file
inner loop is blind to sibling test files; the **full-suite / targeted exit gate is the only
thing that catches the orphan**. When you make a syntactic change to a widely-parsed shared
config file, enumerate every parser with `git grep` and treat it as the work-list.

Corollary: the terraform-render leg (rendering the REAL file and asserting the gate's effect)
is the single behavioral authority — it exercises the load-bearing `~}` whitespace-strip that
an awk/regex reimplementation cannot. Give it `terraform` on PATH in CI (a `command -v
terraform` SKIP branch turns it into a "maybe-run", not a gate) and set `terraform_wrapper:
false` on `setup-terraform` so `terraform console` stdout stays byte-clean for the heredoc-strip.

## Session Errors

1. **Guessed a non-existent column** (`"deletedAt"`) on the inngest `functions` table in a
   Supabase `execute_sql` probe. — Recovery: inspected `information_schema.columns`. —
   Prevention: query the schema before assuming column names on an unfamiliar (vendor) table.
2. **`git stash list` denied** by the `hr-never-git-stash-in-worktrees` hook while diagnosing
   the journald failure. — Recovery: used `git show`/`sed` diagnostics instead. — Prevention:
   the hook is correct; never reach for `git stash*` in a worktree (even the read-only `list`).
3. **`journald-config.test.sh` orphan-suite failure** (the learning above). — Recovery:
   targeted exit gate over all `cloud-init.yml`-referencing infra tests; applied the same
   `^%{` strip. — Prevention: `git grep` every raw parser of a shared config file BEFORE
   committing a syntactic change to it; run the full/targeted exit gate, not just touched-file.
4. **Root `./node_modules/.bin/vitest` absent** — the `plugins/soleur/test/*` suite runs under
   `bun test`, not vitest. — Recovery: switched runner. — Prevention: plugins tests = `bun
   test`; app (`apps/web-platform`) tests = the pinned `./node_modules/.bin/vitest`.
