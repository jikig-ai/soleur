---
date: 2026-05-06
session: PR-B agent-runtime-platform — JWT secret onboarding
class: security-issue
severity: high
related-rule: hr-never-paste-secrets-via-bang-prefix
---

# `! ` prefix leaks secrets into Claude Code conversation context

## What happened

During PR-B onboarding I asked the operator to populate `SUPABASE_JWT_SECRET` in Doppler `dev` and `prd` configs. Anticipating the standard Claude Code mental model — "`! cmd` runs in the local shell and the agent only sees an exit code" — I suggested:

```
! doppler secrets set SUPABASE_JWT_SECRET=<paste> -p soleur -c dev
! doppler secrets set SUPABASE_JWT_SECRET=<paste> -p soleur -c prd
```

The harness behavior is **not** what that mental model assumes. Each `! cmd` invocation injects:

- A `<bash-input>` block containing the literal command string, including all argument values.
- A `<bash-stdout>` block containing whatever the command printed — Doppler's `secrets set` confirms by echoing the new value (truncated, but the first 80+ chars of an 88-char base64 secret are usable).

Both blocks land in the model's context window, the Anthropic API request/response logs, the on-disk session transcript at `~/.claude/projects/<project-hash>/`, and any prompt-cache replay of the session. **The operator's "private paste" assumption is wrong.**

In our session both `dev` and `prd` JWT secrets entered context. We chose not to rotate (low realistic blast radius vs. rotation cost: invalidating every legacy anon/service_role JWT, requiring downstream key refresh across all deployed processes), but the cleaner option for a future operator is to never make the choice at all.

## Why it's a hidden constraint (AGENTS.md-eligible)

Per `cq-agents-md-tier-gate`: AGENTS.md hard rules are reserved for hidden constraints with silent-failure or blast-radius risk that no single-file trigger detects.

This qualifies because:

1. **Silent-failure-shaped.** No part of the harness warns "this command's args will be captured." The `! ` prefix has no UX signal for "secret in args."
2. **Blast-radius-shaped.** A single `! doppler secrets set <prod-key>=<value>` paste leaks a credential to multiple persistence surfaces simultaneously (model context, API logs, local transcript). Some of those surfaces (API logs especially) are outside the operator's control to purge.
3. **Cross-cutting.** Affects every Claude Code session, every operator, every secret-bearing CLI. Not domain-scoped to any one skill.
4. **Intuitively-incorrect mental model.** The natural read of `! ` as "shell-out, agent doesn't see" is actively misleading; the rule has to override intuition each session.

## What to do instead

**For any `<cli> set <KEY>=<VALUE>` mutation** (Doppler, `gh secret set`, `vault kv put`, `wrangler secret put`, AWS CLI parameter-store `put-parameter`, etc.):

1. Operator opens a separate terminal that is **not** connected to a Claude Code session.
2. Operator runs the `set` command there.
3. Back in Claude Code, the agent verifies presence with a length-only or hash-only probe:
   ```bash
   doppler secrets get <KEY> -p soleur -c <cfg> --plain | wc -c
   # or
   doppler run -p soleur -c <cfg> -- bash -c 'echo "${#KEY_NAME}"'
   ```
4. Never echo the value, never `cat` an env file, never include the value in a `Read` tool call response.

**For `<cli> get <KEY> --plain`-style reads** that the agent legitimately needs to use a secret value (e.g., to call an API): the harness DOES inject stdout, so even a "read" leaks. Mitigation: pipe the secret directly into the consumer without going through stdout the model sees:

```bash
# Bad — secret hits stdout, lands in conversation:
SECRET=$(doppler secrets get FOO --plain) && curl -H "X: $SECRET" ...

# Good — `doppler run` injects into the child process env without printing:
doppler run -p soleur -c dev -- bash -c 'curl -H "X: $FOO" ...'
```

This pattern (`doppler run -- bash -c '...'` with the secret consumed via env, never substituted into the visible command line) is what we used throughout PR-B's RLS audit and Mgmt API probes — the secrets stayed inside the subprocess.

## What surfaces caught vs. missed it

- **Caught (eventually):** I noticed the leak in the model output and stopped the session before any further use of the leaked values. The catch was reactive, not preventive.
- **Missed (preventive layer):** No hook, no skill instruction, no harness warning fired BEFORE the paste. The natural "use `! ` for one-off shell commands" suggestion in the work skill (where it suggests `! cmd` for interactive logins like `gcloud auth login`) does not warn about argument visibility.
- **Missed (hard rule):** AGENTS.md had a related rule (`hr-the-bash-tool-runs-in-a-non-interactive` covers shell-side limitations) but no rule on input/output capture semantics of the `! ` prefix specifically.

## Followups landed in the same edit cycle

- AGENTS.md hard rule `hr-never-paste-secrets-via-bang-prefix` (this learning's `related-rule`).
- Sentry/pino redaction allowlist extended with `jwt_secret` and `supabase_jwt_secret` field-name coverage in `apps/web-platform/server/sensitive-keys.ts` (defense-in-depth: even if the secret value is later logged with a recognizable field name, redaction strips it).

## Followups deferred

- A harness-level fix would be ideal — e.g., a Claude Code setting that prompts before running `! ` commands containing patterns like `(SECRET|TOKEN|KEY|PASSWORD)=` in argument position. Filed in the agent-native third-party secret capture issue (post-PR-D milestone).
- A pre-commit / pre-tool-call hook that scans `! ` invocations for `(SECRET|TOKEN|KEY|PASSWORD)=` substring and refuses with a remediation message. Soleur could ship this as a plugin-level hook.
