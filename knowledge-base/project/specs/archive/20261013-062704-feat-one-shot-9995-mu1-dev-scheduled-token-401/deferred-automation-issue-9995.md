deferred-automation

## What was deferred

Provisioning the `soleur-ci-fixture` GitHub App for the MU1 AC-2 `dev_scheduled` credential (#9995), and writing its three secrets into `soleur/dev_scheduled` (`GITHUB_APP_ID`, `GITHUB_APP_PRIVATE_KEY`, `MU1_FIXTURE_INSTALLATION_ID`). Everything else landed in PR #10038: the least-privilege App manifest (`apps/web-platform/infra/github-ci-fixture-app-manifest.json`), the in-leg mint canary (`scripts/probe-github-app-mint.sh`, wired ahead of vitest in `scheduled-integration-suites.yml`), and the dev_scheduled shape audit (`scripts/audit-dev-scheduled-shapes.sh`).

Until this issue closes, the mu1 leg fails fast at the probe with `GITHUB_APP_* cannot mint a valid JWT` instead of the opaque in-test 401 — same verdict, better error.

## Why deferred

The three remaining steps are founder clicks on a GitHub session the agent cannot mint (admin-scoped App creation + private-key generation + org install). playwright-attempt: playwright-mcp server unreachable on this host (connection refused); agent-browser CLI reached `https://github.com/login` — a credential-entry gate, canonical operator-only. Verified 2026-10-11 on feat-one-shot-9995-mu1-dev-scheduled-token-401.

## How to run it

auto_command: `bash knowledge-base/project/specs/feat-one-shot-9995-mu1-dev-scheduled-token-401/bootstrap.sh --list` — attended-only staged script (Claude Code + Soleur plugin; the staged contract requires the approval prompt). An agent runs the stages in order:

1. `--stage preflight` (read) — checks tools/auth and prints the current dead-key fingerprint.
2. `--stage create-app` (write) — opens the manifest-POST page; founder clicks **Create GitHub App** then **Generate a private key**.
3. `--stage record-key` (read) — founder supplies the .pem path via `SOLEUR_BOOTSTRAP_PEM_PATH` (must live on tmpfs, e.g. `$XDG_RUNTIME_DIR`).
4. `--stage install-app` (write) — founder installs on `jikig-ai/mu1-fixture` only.
5. `--stage write-doppler` (write) — writes the three secrets, read-back-verifies the fingerprint, deletes the .pem.
6. `--stage verify` (read) — runs the live mint probe; its `GITHUB_APP_MINT status=200 slug=soleur-ci-fixture` output pasted here is the closure evidence.

## What done looks like

- The `verify` stage prints `GITHUB_APP_MINT status=200 slug=soleur-ci-fixture` — paste it in a comment to close.
- The next dispatched `Scheduled: integration suites` run shows the `mu1` step green.

## Re-evaluation criteria

- Any other dev_scheduled credential change is planned, or
- the nightly mu1 leg is red and the probe names a new failure shape.

Refs #9995. Mandated-By: wg-block-pr-ready-on-undeferred-operator-steps
