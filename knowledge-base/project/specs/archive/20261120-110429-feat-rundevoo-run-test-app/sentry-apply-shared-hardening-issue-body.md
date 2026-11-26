Follow-up from the PR #12968 review panel (rundevoo.run zone onboarding). Several findings apply equally to `apply-sentry-infra.yml` — fixing them only on the rundevoo side would drift the mirrors apart.

User-Impact: These are CI-hardening/cost gaps on guard workflows protecting live infrastructure; each is LOW individually, none is exploitable today, and they share root causes with defects already fixed on the rundevoo side.

Fix-Size: S — each item is a small mechanical mirror.

## Findings (shared sentry + rundevoo)

1. **Single-line credential shape check missing on sentry apply legs** — `apply-sentry-infra.yml`'s two `$GITHUB_ENV` credential-extract steps write Doppler values without the `^[A-Za-z0-9/+=_.-]+$` check that `scheduled-terraform-drift.yml` got in #9362. A multi-line Doppler value would inject `NAME=value` env lines into subsequent steps. (Ported to the rundevoo legs in #12971; sentry still open.)

2. **`detect-changes` pays a `fetch-depth: 0` clone on non-PR events** — the checkout step runs on push/merge_group/workflow_dispatch where the filter step exits before touching git. ~40–90s wasted clone per event. Gate the checkout on `github.event_name == 'pull_request'`. Same shape in both apply workflows.

3. **`preflight` runs on every PR/MQ event** producing `skip` consumed only by the push/dispatch-gated apply job. One runner acquisition per PR for nothing. Gate on `push || workflow_dispatch`. Same in both.

4. **Provisioner-class guard absent on sentry** — a `provisioner "local-exec"` in a covered resource runs arbitrary commands at apply with live credentials and shows as a zero-destroy plan. rundevoo now greps `provisioner|local-exec|remote-exec` in plan_pr + apply; sentry has no equivalent.

5. **Sentry counter-test workflow greps not comment-stripped** — the sentry suite's T23-style pins count `#`-commented lines; a commented-out wiring line keeps the pin green. Fixed on the rundevoo copy (T13/T14); port the `grep -v '^[[:space:]]*#'` pattern.

6. **`terraform show -json tfplan` invoked 4× per gate run** — the saved plan JSON could feed the two address-list jq calls (~1–4s redundant per gated run). Same in both.

7. **Verdict suite `err=$(failing cmd)` under `set -e`** — `test-rundevoo-destroy-gate-verdict.sh`'s T17 was unreachable because the `err=$(...)` assignment killed the suite on the intentional non-zero. Fixed with `|| true` on the rundevoo copy; check whether `test-sentry-destroy-gate-verdict.sh` has the same latent dead case (it likely does — the suites were copied).

## Out of scope

- `sentry-destroy-counts.sh` missing the `plan_ok` check — already filed as #12997.
- The `event.commits` 20-entry cap — documented residual, same in both, by design.
