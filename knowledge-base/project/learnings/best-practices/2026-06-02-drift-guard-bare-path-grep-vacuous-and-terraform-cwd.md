---
title: "Infra drift-guard bare-path grep passes vacuously; terraform CWD vs Bash-tool CWD"
date: 2026-06-02
category: best-practices
tags: [infra, terraform, drift-guard, test-design, vacuous-test, bash-cwd, ssh-provisioner]
related_files:
  - apps/web-platform/infra/infra-config-handler-bootstrap.test.sh
  - apps/web-platform/infra/server.tf
related_issues: [#4811, #4804]
related_prs: [#4814]
---

# Infra drift-guard bare-path grep passes vacuously; terraform CWD vs Bash-tool CWD

Two reusable insights from #4811 (adding `terraform_data.infra_config_handler_bootstrap`,
the SSH bootstrap path that delivers the `infra-config-apply.sh` webhook handler to a
running host — closing the #4804 freeze where the handler routed through the very
handler it would replace).

## Insight 1 — A drift-guard that greps a BARE PATH passes vacuously when the path recurs in lifecycle commands

The new resource's load-bearing anti-regression assertion was: "the resource writes
`/usr/local/bin/infra-config-apply.sh`" — the file `deploy_pipeline_fix` cannot deliver.
The first cut asserted it with a bare-path grep against the (correctly block-scoped) resource body:

```bash
grep -qE '/usr/local/bin/infra-config-apply\.sh'   # VACUOUS
```

`test-design-reviewer` ran the mutation the test exists to catch — deleting the
`provisioner "file"` delivery block — and the test **still passed 21/21**. Root cause:
the path string appears **4×** in the block — once as the real `destination =` (the
delivery) and three more times in non-delivery lifecycle lines (`chown`, `chmod 0755`,
`test -x`). The bare-path grep stays green as long as ANY of those survive, so the exact
"resource exists but no longer delivers the handler" regression sails through.

**Fix: anchor the assertion to the DELIVERY CONSTRUCT, not the substring.** For a
`provisioner "file"`, assert the `destination =` (which only ever appears on the scp
block) AND the `source = "${path.module}/..."` pairing:

```bash
grep -qE 'destination[[:space:]]*=[[:space:]]*"/usr/local/bin/infra-config-apply\.sh"'
grep -qE 'source[[:space:]]*=[[:space:]]*"\$\{path\.module\}/infra-config-apply\.sh"'
```

After the fix, deleting the delivery block fails the guard (22/24, rc=1) — verified by
re-running the same mutation.

**Generalize:** when a static guard asserts "behavior B happens" by grepping a string
that B's construct shares with unrelated lines in the same block (a path reused across
`chown`/`chmod`/`test`, an env var named in both a definition and an assertion, a unit
name in both `ExecStart` and `is-active`), the grep is a presence-of-string proxy for
presence-of-behavior and can pass vacuously. Anchor to the construct that ONLY the
behavior produces (`destination =`, `EnvironmentFile=`, the `cat > <file> <<EOF` write),
and prove it by mutating out the construct and watching the guard go red.

## Insight 2 — `terraform` is CWD-sensitive; the Bash tool's CWD persists unpredictably across calls — use `-chdir=` not `cd &&`

Three consecutive terraform failures (`init` "missing or corrupted provider plugins",
`validate` "No such file or directory", `fmt -check` "No file or directory at server.tf")
all traced to the same root cause: terraform resolves config from the process CWD, and the
Bash tool's CWD state across calls is **non-obvious** — it persisted into `apps/web-platform/infra`
after a `cd … && terraform fmt` call (so a later redundant `cd apps/web-platform/infra`
failed as "No such file or directory"), then **reset to the worktree root** after an
intervening `python3`/`cp` mutation step (so a bare `terraform fmt -check server.tf` failed).

**Fix: never rely on a persisted `cd` for terraform. Pass the directory explicitly with
`terraform -chdir=<dir> <subcommand>`** (or chain `cd <abs-dir> && terraform …` in the
SAME Bash call so the CWD is deterministic for that invocation). `-chdir=` is immune to
whatever the tool's CWD happens to be:

```bash
terraform -chdir=apps/web-platform/infra fmt -check server.tf
```

This is the terraform-specific instance of the broader rule (already in the work skill)
that worktree-pipeline commands must establish their CWD in-call, never inherit it.

## Tags
category: best-practices
module: apps/web-platform/infra
