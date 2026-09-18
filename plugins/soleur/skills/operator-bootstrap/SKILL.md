---
name: operator-bootstrap
description: "This skill should be used when a merge leaves two or more operator steps blocked on one credential: generate a runnable bootstrap.sh on the shared library, not a prose checklist."
---

<!-- Inspired by mattpocock/skills/skills/engineering/wizard/ (MIT, Copyright (c) 2026 Matt Pocock). -->

# Operator Bootstrap — generate the script, not the checklist

Two hard rules already mandate the artifact this skill produces.
`hr-multi-step-post-merge-bootstrap-script` says a post-merge deferral with two or more steps ships
as a runnable script; `hr-ship-message-no-operator-checklist` says the ship message does not hand the
founder a checklist. Until now nothing implemented either one — there was no generator and no
template, only references to infrastructure scripts that happen to be called `bootstrap.sh`.

This skill authors that script. It does **not** author the machinery: every script it produces
`source`s `plugins/soleur/scripts/lib/operator-script.sh`, which is where the progress counter, the
secret handling, the `.env` upsert, the prompt classes and the run ledger live.

## The library header is the contract

**The library is one file. The skill authors only stages. Never hand-edit the library.**

Everything a generated script may rely on is documented **once**, in the header of
`plugins/soleur/scripts/lib/operator-script.sh`, and is not restated here:

- **Sourcing preconditions** (`set -euo pipefail` first; the xtrace/TLS prologue duplicated
  *above* the `source` line; required binaries) — header §"SOURCING PRECONDITIONS".
- **The library invariant** (it never expands a secret-shaped name; secrets arrive as positional
  parameters; credential *entry* stays in the generated script) — header §"LIBRARY INVARIANT".
- **The three prompt classes** and their non-interactive behaviour — header §"Prompts — R8's
  THREE carve-out classes".
- **Exit codes and stdout markers**, including `SOLEUR_BOOTSTRAP_LIB_MISSING` and
  `SOLEUR_BOOTSTRAP_LIB_INCOMPATIBLE` — header §"EXIT CODES" and §"STDOUT MARKERS".
- **The API contract** (`SOLEUR_OP_LIB_API`) — header §"API CONTRACT".

When the header and this file disagree, the header is right and this file has drifted.

## Process

### 1. Scope the procedure

Read the deferral that triggered this. Name, in order, every step the founder must take before the
merged change is live. Stop when the list is complete, not when it is convenient.

Then apply the ladder **before** deciding anything is a step at all:
**environment variable → Doppler → MCP/CLI/REST → prompt.** `hr-exhaust-all-automated-options-before`
ends with *"prompt for creds not in Doppler"* — the prompt is the last rung of the ladder, not an
exception to it. A value that is missing and is not a credential is a hard failure with a named
remedy, never a prompt.

If fewer than two steps survive the ladder, do not generate a script. Say so.

### 2. Map each stage's journey

One stage per step. For each, write down four things before writing any code:

- **what the founder sees** — the exact prompt or progress line;
- **what it needs** — the value, and where on the ladder it comes from;
- **how it knows it is already done** — the precondition. Every stage opens with an
  "already satisfied?" check. This is what makes re-run idempotent over a non-idempotent create,
  and it is why there is **no resume index**: re-running from stage 1 *is* resume, because every
  satisfied stage skips itself;
- **how it proves it worked** — the verification. A stage that attests without verifying attests
  nothing.

### 3. Author the stages

Copy [`template.sh`](./template.sh) to the location in §Where, keep everything above `main()`, and
replace the example stages. Rules:

- **Bake the library path.** The template carries a placeholder line
  `SOLEUR_OP_LIB_BAKED="__SOLEUR_OP_LIB_BAKED__"`. The generator MUST replace it with the absolute
  path of the library resolved at generation time, because a founder's terminal has no
  `CLAUDE_PLUGIN_ROOT` and the generated script's home has no relative path to the plugin:

  ```bash
  LIB="$(realpath "${CLAUDE_PLUGIN_ROOT}/scripts/lib/operator-script.sh")"
  sed -i "s|^SOLEUR_OP_LIB_BAKED=.*|SOLEUR_OP_LIB_BAKED=\"${LIB}\"|" knowledge-base/project/specs/feat-<name>/bootstrap.sh
  ```

  Anchor on the assignment line, as above — a global replace of the placeholder would be harmless
  today (the resolution loop deliberately does not spell it) but is not the documented form.
- **Never echo a secret variable** for progress. That is the documented
  `hr-never-paste-secrets-via-bang-prefix` leak path, whose Why cites a live prd-JWT leak.
- **Credential entry is a `read -rs` in the generated script**, behind the library's TTY gate —
  copy the shape from `provision-hetzner.sh`. `soleur_op_value` is for non-secret ladder values
  (a region, an account id); it echoes its input.
- **Write secrets through `soleur_op_gh_secret_set`** (stdin) and non-secrets through
  `soleur_op_gh_variable_set` (argv, and it refuses secret-shaped names). Do not merge them.
- **Write `.env` values through `soleur_op_env_upsert`.** It is exact-key: the trailing `=` is what
  stops an upsert of `X_API_KEY` from removing `X_API_KEY_SECRET`.
- **Run every stage through the template's `run_stage <index> <name> <function>`.** It calls
  `soleur_op_stage_begin` / `soleur_op_stage_end` and records the stage the template's one `EXIT`
  trap reports on: a stop inside a stage prints `Stopped during stage N (<name>). Nothing else was
  changed. Run: bash <path> — already-done steps are skipped.` and settles the stage in the ledger
  as `failed` with the exit code. A stage called outside `run_stage` is invisible to both.
- **A destructive stage's precondition asks the vendor, never only a local marker written after the
  create.** Between "create succeeded" and "marker written" a Ctrl-C leaves a resource the next run
  cannot see, and it creates a second one. Keep the template's two controls: the vendor-side read
  and the `*_ATTEMPTED` marker written *before* the create, which stops a re-run and sends the
  founder to the console (`--reset <KEY>_ATTEMPTED` clears it once they have looked).
- **Open a URL with `soleur_op_open_url`.** It prints the URL first and never branches on the
  opener's exit code, so a headless box degrades to "here is the URL" instead of to a failed stage.

### 4. Verify and hand off

Run the generated script twice:

1. with every class-1 and class-3 skip variable set and stdin **not** a TTY (`</dev/null`). It must
   run unattended **up to the first class-2 destructive-write ack** and exit 64 there, printing
   `SOLEUR_BOOTSTRAP_INPUT_REQUIRED var=destructive-write-ack(no-skip-variable-by-design) tty=0` —
   the ack has no skip variable by rule, so a fully unattended complete run is impossible by
   design, and the script must say so rather than hang or proceed;
2. with no skip variables and `</dev/null`. It must print `SOLEUR_BOOTSTRAP_INPUT_REQUIRED` naming
   the **first** skip variable and exit 64 — before any read, never after.

Then read the ledger beside the script (`bootstrap-runs.jsonl`): every stage that ran has a
`begin` and a `settle` line, and `total_stages` matches the number of stages authored. Hand the
founder the script path and `bash <path>` — not a checklist.

## The interactive surface: two carve-outs

Generated scripts are **non-interactive by default** (ADR-227). The closed set of interactive
carve-outs is **two** (a third requires an ADR amendment): credential **entry**
(`hr-never-label-any-step-as-manual-without`) and per-command **destructive-write acknowledgement**
(`hr-menu-option-ack-not-prod-write-auth`).

The library implements these as three prompt classes — see the header section named above for
the table. The two rulings an author must not undo:

- **Class 2 takes no skip variable.** An environment variable set once is exactly the "prior
  approval extending to a new command" that `hr-menu-option-ack-not-prod-write-auth` forbids. A
  generated script that could be handed `SOLEUR_BOOTSTRAP_ACK=yes` would create a real billable
  resource fully unattended — introduced by the very machinery that claims to prevent it.
- **Class 3 must be followed by an independent verification.** A barrier only attests that a human
  *says* they did something outside the script. Skipping it is safe **only** because a
  `gh api /installation`, a `doppler projects get` or a `terraform output` runs immediately after
  and fails if the attestation was false. A skippable barrier with no downstream verification is a
  no-op wearing a prompt.

## Recovering from a bad run

Two founder-facing dead ends the library closes, and the generated script must expose:

- **A wrong credential was permanent.** The value is persisted before it can be validated, and the
  environment-first ladder means a re-run never re-prompts — it fails identically forever. Every
  generated script exposes `--reset <KEY>`, which calls `soleur_op_env_reset`.
- **Re-run was not idempotent.** Step 2's precondition check is what makes it so, and it is also
  what makes re-run the resume mechanism. This is a rule for the author, not a feature of the
  library.

SIGINT is **not** handled specially: a founder's Ctrl-C leaves a state byte-identical to a crash, and
the ledger's completed-set-versus-declared-total comparison is what detects both. What every
non-zero exit *inside a stage* gets is the template's single `EXIT` trap: one sentence naming the
stage, the fact that nothing else was changed, and the resume command; plus a `failed` settle line
in the ledger. Every library refusal prints its marker **and** one plain sentence
(`INPUT_REQUIRED` → what to type or set, or that only a person at a terminal can answer;
`ABORTED` → "Stopped. Nothing was created."; `MISSING_BINARY` → "Install <bin> first, then run
again."), and writes a `run_halt` ledger line before exiting.

## Where the artifact lives

**One location:** `knowledge-base/project/specs/feat-<name>/bootstrap.sh`, with the run ledger
beside it as `knowledge-base/project/specs/feat-<name>/bootstrap-runs.jsonl`.

That is the rule's own `<feature>/` prefix (`hr-multi-step-post-merge-bootstrap-script` names
`<feature>/bootstrap.sh`, and the feature's tracked artifact home is its spec directory); it is
tracked, so the script survives `ship` reaping the worktree and is visible to the credential linter
and to review; and a gitignored path (`provisioning/`, `.soleur/` — both are) would leave the
follow-through issue's `auto_command:` pointing at a file that stops existing at ship Phase 7.

The ledger is written on the founder's machine and is committable in the founder's repository,
which is where observability layer 7's "committed to the customer's own repository" condition is
satisfied. Nothing is transmitted to Soleur infrastructure: the surface is the founder's own
machine, and routing it anywhere else is a data-controller event, not an observability improvement.

## What protects the founder's credentials

Five vectors, four controls, all inside the library so no generated script re-decides them:

| Vector | Control |
|---|---|
| `.env` written at a default umask into a cloud-synced directory | `umask 077` in the library, `chmod 600` asserted **after** the `mv` that completes each upsert — `mv` replaces the inode and its mode |
| a secret on argv, readable in `/proc/<pid>/cmdline` | the secret helper is stdin-only; the `--body` form is banned |
| a secret echoed for progress, or a run under `set -x` | the xtrace refusal (exit 78) plus the repo-root `lint-shell-trace-credential-refusal.py` linter in CI |
| a third-party CLI dumping unrelated secrets as a side effect of a write | the write's own output is redirected and the result confirmed by a separate read |
| a half-populated `.env` and partly-set secrets after an interrupted run | **not** a library control — it is the precondition/`--reset` work above, and it is the author's job |

The guards behind the first four live in
[`plugins/soleur/test/operator-script.test.sh`](../../test/operator-script.test.sh), whose mutation
matrix drives each one red. The same suite proves the bake in §3 is load-bearing: the unbaked
template, placed at the documented location with no `CLAUDE_PLUGIN_ROOT`, exits 64.

## Related

- [`template.sh`](./template.sh) — the starting point. Copy it; do not copy the library.
- `plugins/soleur/scripts/lib/operator-script.sh` — the library; its header is the contract.
- `soleur:provision-hetzner` — the proving consumer; read its script for a real refactor onto the library.
- `soleur:ship` — invokes this skill when a post-merge deferral carries two or more operator steps.
