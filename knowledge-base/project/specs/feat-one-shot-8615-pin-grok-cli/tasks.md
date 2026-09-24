# Tasks: pin the Grok CLI in grok-fidelity (#8615)

Plan: `knowledge-base/project/plans/2026-09-24-fix-pin-grok-cli-in-grok-fidelity-plan.md`

## Phase 1: Setup

- [ ] 1.1 Re-measure the vendor pin: `curl -fsSL https://x.ai/cli/stable` (expect `1.0.41`); download `https://x.ai/cli/grok-1.0.41-linux-x86_64` and confirm sha256 `9ce03ed23e16ea01072b4496263d6213a27899e1e3e107f008d36edf82e70407`. If stable moved, keep 1.0.41 (the pin is deliberate) unless the artifact is gone.

## Phase 2: Core Implementation

- [ ] 2.1 `.github/workflows/ci.yml` job `grok-fidelity`: add job `env` `GROK_PIN`, `GROK_SHA256`, `GROK_DISABLE_AUTOUPDATER: "1"`
- [ ] 2.2 Replace the `Install Grok CLI` step with the plan's step body (versioned x.ai binary, then `sha256sum -c` before install, then a `timeout 30` version assert that exits 3 on mismatch)
- [ ] 2.3 `plugins/soleur/test/README.md` §Vendor-CLI pins: add a Grok row and replace the "does NOT conform" paragraph. Add the Grok probe to the #8574 freshness sentence.
- [ ] 2.4 ADR-245: add a dated #8615 amendment to decision 3. Extend "Pin staleness" to cover the Grok pin.
- [ ] 2.5 `model.c4` edge `github -> platform.grokBuild`: rewrite the description (no "install.sh"), then run `bash scripts/regenerate-c4-model.sh` and stage `model.likec4.json`

## Phase 3: Testing

- [ ] 3.1 Local simulation harness: load the step body AND `jobs.grok-fidelity.env` from `ci.yml` with PyYAML, and run the body as `bash -e` against a scratch HOME/RUNNER_TEMP/GITHUB_PATH. Cover Guard 1 rows 1-5 (rc 3 plus the reason token), the must-PASS row, harness row (a) (body replaced by `true`, which must fail rows 1-5), and row 6 (comparison deleted, so rows 3 and 4 are reported FAIL). The row 3 sed must fail if it matched nothing.
- [ ] 3.2 With the pinned binary on PATH and `GROK_DISABLE_AUTOUPDATER=1`, run `bash plugins/soleur/scripts/grok-fidelity-gate.sh` and confirm `grok inspect contract OK` and `grok-fidelity-gate: PASS`
- [ ] 3.3 `actionlint .github/workflows/ci.yml`; `bun test plugins/soleur/test/workflow-file-size.test.ts`
- [ ] 3.4 C4: `bash plugins/soleur/test/c4-model-freshness.test.sh`, `bash plugins/soleur/test/c4-count-parity.test.sh`, and apps/web-platform vitest `test/c4-code-syntax.test.ts test/c4-render.test.ts`
- [ ] 3.5 CI-form lints: `python3 scripts/lint-skill-body-budget.py --base "$(git merge-base HEAD origin/main)"`; confirm there is no touched `.ts` (`git diff --name-only origin/main... -- '*.ts'` is empty), otherwise run eslint on each touched file
- [ ] 3.6 `npx markdownlint-cli2` on the touched `.md` files

## Phase 4: Ship-time

- [ ] 4.1 PR body: `Closes #8615` and `Ref #8574`
- [ ] 4.2 Append `## Pin-freshness criterion` to the #8574 body (preserving the existing body): list the Codex, Devin and Grok probes, the rule that `GROK_PIN` and `GROK_SHA256` are bumped together, and the note that nothing executes the comparison today
- [ ] 4.3 First CI run: `grok-fidelity` is green, with `pinned 1.0.41 (sha256 ok` and `grok inspect contract OK` in its log
