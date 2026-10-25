# Learning: a credential-tier cutover invalidates runbook recipes asymmetrically — reads stay green, writes 403, so the drift is invisible to every check

## Problem

Issue #10979: after the O5b credential-tier cutover moved the state-bucket write credentials into
`soleur-infra-privileged/prd` as `TF_STATE_AWS_*`, the `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` pair left in
`soleur/prd_terraform` was deliberately demoted to read-only. Every terraform-apply runbook recipe that exported
that pair stayed correct for `plan`/`init`/`state pull` — and silently wrong for `apply`/`import`/`state push`,
which 403 on the read-only pair. Nothing failed loudly: drift workflows and plans kept passing because reads are
what they do, so fourteen documents prescribed a recipe that only a real state-writing invocation could refute.

Three distinct defects hid inside the drift:

1. **The ambient-`AWS_*` leg was undocumented in the canonical reference.** `infra-credential-tiers-8209.md`
   §Local Terraform invocation prescribed the nested `doppler run --name-transformer tf-var` loaders — but the
   transformer renames every injected secret to `TF_VAR_*`, so neither loader ever sets the S3 backend's bare
   `AWS_*`. The backend reads `AWS_*` from the ambient environment, which must be exported explicitly from
   `TF_STATE_AWS_*` (`export AWS_ACCESS_KEY_ID=$(doppler secrets get TF_STATE_AWS_ACCESS_KEY_ID -p soleur-infra-privileged -c prd --plain)`).
   Every annotation-note pointer in the runbooks resolved to a recipe that still 403s.
2. **A `TF_VAR_`-prefixed secret name mis-set.** `TF_VAR_INNGEST_CONFIG_DIGEST` was stored as a literal Doppler
   secret name in `soleur/prd_terraform`; under `tf-var` transformation it lands as
   `TF_VAR_tf_var_inngest_config_digest`, never as `TF_VAR_inngest_config_digest`. The stray secret was deleted
   (operator-approved, outside the PR).
3. **Executable sites are a different defect class than prose.** `apps/cla-evidence/infra/bootstrap.sh` and
   `apps/web-platform/scripts/bootstrap-live-verify.sh` export the read-only pair then run
   `terraform apply -auto-approve` — armed, not documentation. They were descoped to follow-up issue #10990
   (mandatory CTO ship gate), and `bootstrap-live-verify.sh` was initially mislabeled "likely reads" during
   sequential-fallback planning — caught only by the CTO ruling pass.

## Solution

Sweep keyed on the credential *source* name (`secrets get AWS_ACCESS_KEY_ID`, `prd_terraform` `AWS_*`) across the
whole repo — `runbooks/`, `infra/github/README.md`, `apps/**/*.sh` — not just the directory the issue names, then
classify each hit as prose vs. executable. The canonical recipe now prescribes: ambient `export AWS_*` from
`TF_STATE_AWS_*` in `soleur-infra-privileged/prd`, then the nested loader
(`doppler run -p soleur-infra-privileged -c prd --name-transformer tf-var -- doppler run -p soleur -c prd_terraform --name-transformer tf-var --preserve-env -- terraform …`)
so `TF_VAR_*` injection and ambient `AWS_*` coexist. Each of the four dated learnings got a
`Superseded in part (2026-10-24, #10979)` note scoped to state-writing invocations — the old recipe remains correct
for reads by design, so a blanket supersession would have broken valid prescriptions.

## Key Insight

A permission *narrowing* is the quietest breaking change there is: it leaves every read path green, so no CI job,
lint, or drift probe can see it, and the only oracle is the destructive call itself. When a credential tier
changes, the correctness question splits by operation class — enumerate which invocations write vs. read before
declaring a recipe still valid, and sweep by the secret's *name in the source config* rather than by document
location, because stale copies accumulate in READMEs and `.sh` files outside the runbook directory. Executable
sites and prose sites need different remediation lanes (code review vs. docs edit); a sequential-fallback review
is measurably thinner on exactly this discrimination — it mislabeled a state-writing script as "likely reads",
which a panel seat or a `grep -n 'apply\|import\|state push'` per hit would have caught.

## Session Errors

1. **Forwarded (plan phase): no Task/subagent spawn capability** — research fan-out, domain leaders, advisor
   consult, and plan-review panel all ran inline sequentially; disclosed as `Reviewed-Coverage: sequential-fallback`.
   Recovery: sequential execution + disclosure marker. **Prevention:** none — environment constraint; the
   disclosure convention is the mitigation.
2. **Forwarded (plan phase): `bootstrap-live-verify.sh` mislabeled "likely reads"** — the sequential pass
   under-classified an armed state-writing script. Recovery: CTO ruling caught and corrected it before scope-out.
   **Prevention:** when classifying credential-recipe hits as read vs. write, grep each hit site for
   `apply|import|state push` mechanically rather than judging from filename/context.
3. **Forwarded (plan phase): compound exit-gate step not run** — pipeline/Task context skips the interactive exit
   gate per the skill's pipeline-detection rule. **Prevention:** none needed; already covered by an existing rule.
4. **P1 review finding: `lint-infra-no-human-steps` flagged 3 plan lines.** Recovery: fixed inline; lint re-run
   green on the changed files (that mechanical oracle is the fix-round verification). **Prevention:** the lint is
   the enforcement — covered, no new guardrail proposed.
5. **`bash ${CLAUDE_PLUGIN_ROOT}/...` in a `VAR=... cmd` prefix did not expand** (variable assigned in the same
   command line). Recovery: exported the var in its own call first. **Prevention:** one-off; export plugin-root
   env vars before first use in a fresh shell.

## Tags

category: integration-issues
module: infra-credentials, terraform-runbooks
issue: #10979, follow-up: #10990, PR: #10988
