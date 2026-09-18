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

## The sourcing invariant

**The library is one file. The skill authors only stages. Never hand-edit the library.**

There is exactly **one distribution mode**: the generated script `source`s the library. There is no
inlined copy, no `STAGES` byte-identity marker, and no regeneration-parity check — because there is
no second copy to drift from. A generated script therefore needs the plugin present at run time,
which is true by definition of a Soleur user.

Three consequences that are easy to get wrong:

1. **The prologue is DUPLICATED above the `source` line, never moved into the library.**
   `PROLOGUE_MAX_CMDS = 0` in the repo-root `lint-shell-trace-credential-refusal.py` linter makes a `source` line
   itself a counted command, and the linter's `find_preamble` scans only a file's own lines — a
   caller that sources a fully compliant library still fails Rule A.
2. **Credential ENTRY stays in the generated script**, not in the library. The prompt string is the
   operator-facing product, and it is the thing a founder reads at the moment they are asked for a
   token.
3. **The library never expands a secret-shaped variable name.** Secrets reach it as positional
   parameters bound to neutral local names. If it ever bound a `*_TOKEN`/`*_KEY`/`*_SECRET` name it
   would enter the credential linter's scope and need its own `exit 78`, which on a `source`
   terminates the caller.

If the library is not found, the generated script emits `SOLEUR_BOOTSTRAP_LIB_MISSING path=<resolved>`
and hard-exits. It never degrades to a stub: ADR-178's Context §1 records what fail-closed stubs did
to `cleanup-merged`, which refused to reap forever while reporting success.

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
  "already satisfied?" check. Re-run is otherwise not idempotent over a non-idempotent create, and
  a founder who is interrupted has no safe action;
- **how it proves it worked** — the verification. A stage that attests without verifying attests
  nothing.

### 3. Author the stages

Copy `template.sh`, keep everything above `main()`, and replace the example stages. Rules:

- **Never echo a secret variable** for progress. That is the documented
  `hr-never-paste-secrets-via-bang-prefix` leak path, whose Why cites a live prd-JWT leak.
- **Write secrets through `soleur_op_gh_secret_set`** (stdin) and non-secrets through
  `soleur_op_gh_variable_set` (argv, and it refuses secret-shaped names). Do not merge them.
- **Write `.env` values through `soleur_op_env_upsert`.** It is exact-key: the trailing `=` is what
  stops an upsert of `X_API_KEY` from removing `X_API_KEY_SECRET`.
- **Call `soleur_op_stage_begin` / `soleur_op_stage_end` around every stage**, so the run ledger
  carries a begin and a settle record and a partial run is decidable from the artifact alone.
- **Open a URL with `soleur_op_open_url`.** It prints the URL first and never branches on the
  opener's exit code, so a headless box degrades to "here is the URL" instead of to a failed stage.

### 4. Verify and hand off

Run the generated script twice: once with every skip variable set (it must complete unattended), and
once with `</dev/null` (it must print `SOLEUR_BOOTSTRAP_INPUT_REQUIRED` and exit 64 — never hang).
Then run [verify-bootstrap-run.sh](./scripts/verify-bootstrap-run.sh) against the ledger:

```bash
bash plugins/soleur/skills/operator-bootstrap/scripts/verify-bootstrap-run.sh \
  --ledger provisioning/<slug>/bootstrap-runs.jsonl --last
```

It prints the last run's stage ledger and exits non-zero when that run is incomplete, naming the
stage index to resume from. Hand the founder the script path and that one command — not a checklist.

## The interactive surface: two carve-outs, three classes

Generated scripts are **non-interactive by default**. The closed set of interactive carve-outs is
**two** (a third requires an ADR amendment): credential **entry**
(`hr-never-label-any-step-as-manual-without`) and per-command **destructive-write acknowledgement**
(`hr-menu-option-ack-not-prod-write-auth`).

Read literally, the acknowledgement carve-out splits into two behaviourally different classes, and
conflating them is a live safety bug rather than a taxonomy quibble — so the library implements
**three**:

| Class | Example | Non-interactive behaviour |
|---|---|---|
| 1 — ladder value (credential entry) | a vendor token prompt | Named skip variable. No TTY + unset ⇒ exit **64** naming the variable |
| 2 — per-command destructive-write ack | the ack that must gate `hcloud server create` | **No skip variable at all.** No TTY ⇒ exit **64** unconditionally. Automation must not be able to supply this |
| 3 — out-of-band completion barrier | `Token created? Type 'yes'` | Named skip variable, **and** the barrier must be followed by an independent verification of the thing attested |

Why class 2 takes no skip variable: an environment variable set once is exactly the "prior approval
extending to a new command" that `hr-menu-option-ack-not-prod-write-auth` forbids. A generated script
that could be handed `SOLEUR_BOOTSTRAP_ACK=yes` would create a real billable resource fully
unattended — introduced by the very machinery that claims to prevent it.

Why class 3's verification is load-bearing: a barrier only attests that a human *says* they did
something outside the script. Skipping it is safe **only** because a `gh api /installation`, a
`doppler projects get` or a `terraform output` runs immediately after and fails if the attestation
was false. A skippable barrier with no downstream verification is a no-op wearing a prompt.

## Total non-interactive path

For every class-1 and class-3 prompt there is a named environment variable that skips it. With stdin
not a TTY **and** the variable unset, the script emits
`SOLEUR_BOOTSTRAP_INPUT_REQUIRED var=<NAME> tty=0` on **stdout** and exits **64** — *before* the read,
never after. Agent runtimes surface stdout and swallow stderr, so a stderr-only refusal is invisible
on the one surface that matters.

The state this replaces is fail-closed but mute: `provision-hetzner.sh` used to read EOF into an empty
`ACK` and exit 1 with `Aborted.` — the right outcome with an unattributed cause.

## Recovering from a bad run

Three founder-facing dead ends the library closes, and the generated script must expose:

- **A wrong credential was permanent.** The value is persisted before it can be validated, and the
  environment-first ladder means a re-run never re-prompts — it fails identically forever. Every
  generated script exposes `--reset <KEY>`, which calls `soleur_op_env_reset`.
- **Re-run was not idempotent.** Step 2's precondition check is what makes it so. This is a rule for
  the author, not a feature of the library.
- **There was no resume.** `SOLEUR_BOOTSTRAP_START_STAGE=<n>` skips stages below `n`;
  `verify-bootstrap-run.sh --last` prints the `n` to use.

SIGINT is **not** handled specially: a founder's Ctrl-C leaves a state byte-identical to a crash, and
the ledger's completed-set-versus-declared-total comparison is what detects both.

## Exit codes

There is no central exit-code table in this repository and code **3** is already overloaded, so the
table lives here and in the library header rather than being re-derived by the next author.

| Code | Meaning in a generated script | Remedy |
|---|---|---|
| 0 | success | — |
| 1 | usage error, or a refused call (e.g. a secret-shaped name handed to the argv variable helper) | fix the invocation |
| 3 | DPA-gate rejection (tenant provisioning only) | sign the DPA first |
| 64 | missing input: a binary, an environment variable, or a prompt with no TTY | the marker line names what to set |
| 78 | refusing to run under shell tracing while holding a live credential (#7797) | re-run without `-x` |

**Conflict, stated rather than renumbered:** `apps/cla-evidence/scripts/sentinel-pr.sh` returns **3**
for *missing tool on PATH* and *not inside a git repository* — a class
`apps/cla-evidence/infra/bootstrap.sh` returns **64** for. Both meanings are live. Do not re-derive 3
as "missing tool".

## Where the artifact lives

One location, not three: `provisioning/<slug>/bootstrap.sh` when the procedure is tenant-scoped,
otherwise `.soleur/bootstrap.sh`. The run ledger sits beside it as `bootstrap-runs.jsonl`.

The ledger is committed in the **founder's** repository, which is where observability layer 7's
"committed to the customer's own repository" condition is satisfied. Both candidate paths are
gitignored in the Soleur repo, so nothing is ever committed here — saying so plainly is the
difference between citing the layer and meeting it. Nothing is transmitted to Soleur infrastructure:
the surface is the founder's own machine, and routing it anywhere else is a data-controller event,
not an observability improvement.

## What protects the founder's credentials

Five vectors, four controls, all inside the library so no generated script re-decides them:

| Vector | Control |
|---|---|
| `.env` written at a default umask into a cloud-synced directory | `umask 077` in the library, `chmod 600` asserted **after** the `mv` that completes each upsert — `mv` replaces the inode and its mode |
| a secret on argv, readable in `/proc/<pid>/cmdline` | the secret helper is stdin-only; the `--body` form is banned |
| a secret echoed for progress, or a run under `set -x` | the xtrace refusal (exit 78) plus the repo-root `lint-shell-trace-credential-refusal.py` linter in CI |
| a third-party CLI dumping unrelated secrets as a side effect of a write | the write's own output is redirected and the result confirmed by a separate read |
| a half-populated `.env` and partly-set secrets after an interrupted run | **not** a library control — it is the precondition/resume/`--reset` work above, and it is the author's job |

The guards behind the first four live in
[`plugins/soleur/test/operator-script.test.sh`](../../test/operator-script.test.sh), whose mutation
matrix drives each one red.

## Related

- [`template.sh`](./template.sh) — the starting point. Copy it; do not copy the library.
- [verify-bootstrap-run.sh](./scripts/verify-bootstrap-run.sh) — `--ledger <path> --last`.
- `soleur:provision-hetzner` — the proving consumer; read its script for a real refactor onto the library.
- `soleur:ship` — invokes this skill when a post-merge deferral carries two or more operator steps.
