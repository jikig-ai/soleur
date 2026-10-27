# Guardrail corpus audit — `.claude/hooks/` + `scripts/lint-*` (#10404)

Census date: 2026-10-21. Corpus definition (enforced by `test/manifest.test.sh`,
which re-derives this set from `git ls-files` — a new member with no row here is a
CI failure):

- `.claude/hooks/**/*.sh`, excluding `*.test.sh` and files under `/test/` — **57 files**.
- `scripts/lint-*`, excluding `*.test.sh`, `*.baseline.txt`, `*.highwater*` — **47 files**.

## Verdicts

| Verdict | Meaning |
|---|---|
| `generic` | Repo-generic as it stands: no Soleur-domain coupling; could run in an arbitrary repository with at most path arguments. |
| `generic-after-extraction` | The *guard idea* is repo-generic but the file carries couplings (incident machinery, shared libs, Soleur paths or rule ids) that dead-reference in a user repo. Shippable only as a template. |
| `soleur-coupled` | The guard's *purpose* is Soleur's: it enforces a Soleur rule id, a Soleur corpus path, a vendor in Soleur's stack, or Soleur telemetry/workflow machinery. Not shipped. |

**Counts:** hooks — 0 generic / 10 generic-after-extraction / 48 soleur-coupled.
lints — 9 generic / 8 generic-after-extraction / 30 soleur-coupled.

The canonical emit pair `plugins/soleur/scripts/precommit-guard.sh` +
`plugins/soleur/scripts/lib/wrapper-boundary.sh` is NOT in the census set (it
lives under `plugins/`, not `.claude/hooks/` or `scripts/lint-*`); it is the
source the v1 `commit-on-main` guard emits near-verbatim. Likewise
`.claude/hooks/guardrails.sh` is classified as a whole file; the v1 `block-stash`
guard extracts its `block-stash-in-worktrees` arm (guardrails.sh:471) as a
template rather than shipping the monolith.

## Census — `.claude/hooks/` (58)

| File | Verdict | Rationale |
|---|---|---|
| `agent-token-tee.sh` | soleur-coupled | Task telemetry into `.claude/.session-tokens.jsonl`, consumed by Soleur `compound` Phase 1.6. |
| `background-poll-prefer-monitor.sh` | soleur-coupled | Enforces `hr-monitor-not-run-in-background-for-polling` — a Soleur rule keyed to the harness Monitor tool. |
| `bare-head-self-heal.sh` | soleur-coupled | Repairs Soleur's bare-repo+worktree topology; meaningless in an ordinary clone. |
| `bare-root-cwd-guard.sh` | soleur-coupled | Same bare-repo topology guard (cwd under the bare root). |
| `brand-hex-commit-gate.sh` | soleur-coupled | Soleur brand-corpus hex gate. |
| `cla-signed-author-gate.sh` | soleur-coupled | Keys on `noreply@anthropic.com`, the Soleur `cla-check` required status, `wg-cla-signed-author-before-merge`. |
| `context-reviewed-gate.sh` | generic-after-extraction | `last_reviewed:`-trailer audit tripwire is format-generic (v2); couplings = `incidents.sh` + `hook-input.sh` sourcing. |
| `docs-cli-verification.sh` | generic-after-extraction | Advisory "verified CLI" docs lint (v2); couplings = `incidents.sh` + a Soleur file-pattern gate (`apps/**/page.*`). |
| `doppler-secrets-delete-redirect.sh` | soleur-coupled | Doppler vendor redirect. |
| `durable-reminder-prefer-inngest.sh` | soleur-coupled | Inngest vendor preference in Soleur's app stack. |
| `follow-through-directive-gate.sh` | soleur-coupled | Soleur follow-through directive machinery. |
| `git-commit-secret-scan.sh` | generic-after-extraction | **v1 `secret-scan` source.** Couplings: `lib/hook-input.sh`, `incidents.sh` emits, `jq`, the repo `.gitleaks.toml`; the staged-scan predicate and colour pins are repo-generic. **Known divergences from source (the emitted template self-contains its parse and will not follow the source):** it lacks the #10609 commit-target resolution and the #10696 would-be index (`lib/commit-index-sim.sh`), so a command that stages and commits in ONE call (`git add ... && git commit`, `commit -a` / `-am`, `commit -- <path>`) is not covered in a user repo; stage in a separate call. Porting both is tracked in the #10696 follow-up. |
| `grep-rewrite.sh` | soleur-coupled | Neutralizes one observed ugrep `grep` shim — environment remediation, not a general guard (ADR-162). |
| `guardrails.sh` | soleur-coupled | Monolith wired to `lib/freeze-lock.sh` + `incidents.sh` + the Soleur rule corpus. Its `block-stash-in-worktrees` arm (:471) is extracted as v1 `block-stash`; its `block-commit-on-main` arm delegates to `precommit-guard.sh`, which v1 emits instead. `block-rm-rf` arms (:185, :200) stay v2 — they read `lib/freeze-lock.sh` state and are not self-contained. |
| `iac-plan-write-guard.sh` | soleur-coupled | Enforces `hr-all-infrastructure-provisioning` on Soleur plan/spec files. |
| `kb-domain-allowlist-guard.sh` | soleur-coupled | `knowledge-base/` domain allowlist — Soleur corpus structure. |
| `lib/context-sanitize.sh` | generic-after-extraction | Pure display-boundary sanitizer already byte-twinned plugin-side (v2). |
| `lib/freeze-lock.sh` | soleur-coupled | `guardrails.sh` freeze-state machinery. |
| `lib/hook-input.sh` | generic-after-extraction | Harness-generic hook-stdin parser (ADR-156/157). v1 templates self-contain their parse, so it is not emitted; a v2 hook needing it must inline it. |
| `lib/hook-tool-kind.sh` | generic-after-extraction | Devin→Claude tool-kind map (#8205) — harness-generic, not Soleur-domain (v2). |
| `lib/incidents.sh` | soleur-coupled | The `emit_incident` sink — the corpus's named coupling; emitted guards strip its calls. |
| `lib/log-rotation.sh` | generic-after-extraction | `.claude/*.jsonl` rotation util; logic portable, callers Soleur telemetry sinks (v2). |
| `lib/commit-target-roots.sh` | soleur-coupled | Commit-target argv walker for `git-commit-secret-scan.sh` (#10609) and, with a warn-and-allow disposition, `brand-hex-commit-gate.sh` (#10793) — depends on `plugins/soleur/hooks/lib/shell-argv.pl`, the repo's hardened lexer; the emitted `secret-scan` template self-contains its parse instead. Since #10696 it also outputs the staging facts `CTR_COMMIT_STAGES`, `CTR_STAGE_OPAQUE`, `CTR_STAGE_REFUSE`, `CTR_STAGE_UNSIMULABLE`, the parallel arrays `CTR_ADD_EXACT` / `_FORCE` / `_LIT` / `_NW` / `_OFF` / `_OWNC` with `CTR_ADD_ARGV`, `CTR_COMMIT_ALL`, `CTR_COMMIT_PATHS`, `CTR_COMMIT_OWN_C` and `CTR_STAGE_CD_FIRST` (the canonical text dump of these facts lives in the test suite, not here). |
| `lib/commit-index-sim.sh` | soleur-coupled | Builds the would-be index (a temp copy of the real index with the command's own staging replayed) for `git-commit-secret-scan.sh` (#10696); depends on the `CTR_*` facts from `lib/commit-target-roots.sh`, which depend on `plugins/soleur/hooks/lib/shell-argv.pl`. Policy-free, so the brand-hex gate can reuse it (#10793). Not shipped. |
| `lib/monitor-sig.sh` | soleur-coupled | Monitor-ledger signature shared by the two monitor hooks. |
| `lib/technical-fork-cues.sh` | soleur-coupled | Cue vocabulary for `hr-technical-fork-is-not-an-operator-question`. |
| `lib/test-incident-sandbox.sh` | soleur-coupled | Test sandbox for `incidents.sh`. |
| `memory-backstop-mutation-battery.sh` | soleur-coupled | Mutation battery for `memory-backstop.sh`; needs a live systemd user bus. |
| `memory-backstop-resolve.sh` | soleur-coupled | Shim resolving the newest `memory-backstop.sh` across checkouts. |
| `memory-backstop.sh` | soleur-coupled | Soleur `~/.claude` memory protection. |
| `monitor-arm-recorder.sh` | soleur-coupled | Monitor-ledger writer. |
| `monitor-supersede-guard.sh` | soleur-coupled | Monitor-ledger reader. |
| `new-scheduled-cron-prefer-inngest.sh` | soleur-coupled | Inngest vendor preference. |
| `no-memory-write.sh` | soleur-coupled | Soleur memory-directory write ban. |
| `pencil-collapse-guard.sh` | soleur-coupled | Pencil MCP `.pen` recovery. |
| `pencil-open-guard.sh` | soleur-coupled | Pencil MCP + `cq-` rule. |
| `phase-surface-hint.sh` | soleur-coupled | Soleur `.claude/phase-surface-map.json` phase vocabulary (ADR-070). |
| `pkill-self-match-guard.sh` | generic-after-extraction | Universal self-match class (`pkill -f`, `ps\|grep`); couplings = lazy `incidents.sh` emit + a `proc.sh` pointer (v2). |
| `post-dispatch-watch-gate.sh` | soleur-coupled | Soleur monitor/watch ledger (`hr-dispatch-async-must-arm-watch`). |
| `pre-ask-technical-fork-gate.sh` | soleur-coupled | `hr-technical-fork` on AskUserQuestion. |
| `pre-closing-technical-fork-gate.sh` | soleur-coupled | Same rule on the closing carrier. |
| `pre-merge-auto-close-scan.sh` | soleur-coupled | `gh pr merge` close-keyword scan bound to the Soleur `follow-through` label. |
| `pre-merge-rebase.sh` | soleur-coupled | Soleur merge-flow gate. |
| `prod-write-defer-gate.sh` | soleur-coupled | Soleur prod-write surface definitions. |
| `rule-incident-marker-capture.sh` | soleur-coupled | Soleur rule-incident marker capture. |
| `session-rules-loader.sh` | soleur-coupled | Loads `AGENTS.rules.md` — the Soleur rule corpus itself. |
| `ship-kb-archive-gate.sh` | soleur-coupled | `soleur:ship` KB-archive gate. |
| `ship-net-issue-flow-gate.sh` | soleur-coupled | ship flow. |
| `ship-operator-step-gate.sh` | soleur-coupled | ship flow. |
| `ship-runbook-ssh-gate.sh` | soleur-coupled | ship flow. |
| `ship-soak-followthrough-gate.sh` | soleur-coupled | ship flow. |
| `ship-unpushed-commits-gate.sh` | generic-after-extraction | `gh pr merge` denied while `git rev-list origin/<branch>..HEAD` is non-zero — the predicate is repo-generic (v2); couplings = `hook-input.sh`/`jq` stdin parse. |
| `skill-context-queries.sh` | soleur-coupled | Soleur skill-context plumbing. |
| `skill-invocation-logger.sh` | soleur-coupled | Soleur skill-invocation telemetry sink. |
| `skill-security-scan.sh` | soleur-coupled | Invokes the skill-security-scan skill under the payload via a `$PROJECT_DIR` prefix. |
| `skill-security-scan-write.sh` | soleur-coupled | Same scanner plus `plugins/soleur` write paths. |
| `supabase-loopback-warn.sh` | soleur-coupled | Supabase vendor stack check (ADR-153). |
| `worktree-write-guard.sh` | generic-after-extraction | Blocks writes to the main checkout while worktrees exist — repo-generic idea (v2); couplings = `incidents.sh`/`hook-input.sh` sourcing. |

## Census — `scripts/lint-*` (48)

| File | Verdict | Rationale |
|---|---|---|
| `lint-agents-compound-sync.sh` | soleur-coupled | AGENTS budget contract across the plugin corpus. |
| `lint-agents-enforcement-tags.py` | soleur-coupled | AGENTS `[hook-enforced:]`/`[skill-enforced:]` tag registry. |
| `lint-agents-rule-budget.py` | soleur-coupled | `AGENTS.{md,rules.md}` byte budgets. |
| `lint-anthropic-content-position.py` | soleur-coupled | Anthropic-harness reader lint; scans `knowledge-base/` + Soleur call sites. |
| `lint-art30-reverification.sh` | soleur-coupled | GDPR Art.30 register/trigger corpus (`knowledge-base/legal/`). |
| `lint-betterstack-emitter-read.sh` | soleur-coupled | BetterStack emitter corpus. |
| `lint-bot-synthetic-completeness.sh` | generic-after-extraction | Synthetic check-run completeness for bot-authored PRs is generic (v2); coupling = the `pr-quality-guards.yml` exemption name. |
| `lint-bot-synthetic-statuses.sh` | generic-after-extraction | `[skip ci]` ban on bot PRs is generic (v2); same named exemptions. |
| `lint-conversations-update-callsites.sh` | soleur-coupled | `apps/web-platform/server` module boundary. |
| `lint-credential-path-literals.py` | soleur-coupled | SCAN_DIRS = `plugins/` + `knowledge-base/`. |
| `lint-diagnosis-claims.sh` | generic-after-extraction | "CI message may not name a cause the job did not measure" is generic (v2); scope names `apps/web-platform/infra/`. |
| `lint-distribution-content.sh` | soleur-coupled | `knowledge-base/marketing/distribution-content/` marker lint. |
| `lint-doppler-description-length.py` | soleur-coupled | Doppler description contract over `*.tf`. |
| `lint-dual-lockfile.sh` | generic | `git ls-files`-driven npm-lockfile-of-record guard; Soleur mentions are comments only. |
| `lint-encryption-posture.py` | soleur-coupled | Soleur encryption-posture ledger + `apps/*/infra` scope (ADR-140). |
| `lint-feature-map-coverage.sh` | soleur-coupled | `apps/web-platform/app/**` page set + `feature-map.md`. |
| `lint-followthrough-varq-ban.sh` | soleur-coupled | Soleur probe-set/varq conventions. |
| `lint-gh-argv-arg.py` | generic | Repo-wide `gh` argv vs jq-flag-token lint over workflows + `*.sh`; no Soleur coupling. |
| `lint-guard-contract.py` | soleur-coupled | Soleur plan/SKILL.md guard-contract shape (deepen-plan §4.11). |
| `lint-hcloud-token-readonly-no-fallback.sh` | soleur-coupled | Tree scan for the read/write Hetzner token read (ADR-241 D4); the Soleur secret store and its one allowlisted `op=backup` read. |
| `lint-infra-no-human-steps.py` | soleur-coupled | `hr-no-ssh-fallback-in-runbooks` on `knowledge-base` docs. |
| `lint-inngest-step-boundary.py` | soleur-coupled | `apps/web-platform/server/inngest/functions/` step-boundary error-identity census + named allowlist. |
| `lint-integration-env-gates.sh` | soleur-coupled | `apps/web-platform/{test,lib}` env-gate wiring + `scheduled-integration-suites.yml`. |
| `lint-legal-mirror-drift-baseline.sh` | soleur-coupled | Legal mirror corpus (`plugins/soleur/docs/pages/legal`). |
| `lint-legal-registers.sh` | soleur-coupled | `knowledge-base/legal/` registers. |
| `lint-legal-scope-block-placement.sh` | soleur-coupled | Legal scope-block placement + the same mirror dir. |
| `lint-migrated-rule-ids.sh` | soleur-coupled | AGENTS rule-id migration registry. |
| `lint-orphan-test-suites.sh` | generic-after-extraction | **v1 `orphan-test` source.** The `git ls-files '*.test.sh'` producer is generic; couplings = `scripts/test-all.sh` runner name, `TEST_GROUP`/`SCRIPTS_SHARD` labels, `apps/web-platform/infra/` surfaces. |
| `lint-questionnaire-identity.sh` | soleur-coupled | `knowledge-base/project/questionnaires/` identity guard. |
| `lint-rejected-register.sh` | soleur-coupled | `knowledge-base/project/rejected/` no-list guard. |
| `lint-rule-bodies.py` | soleur-coupled | `AGENTS.rules.md` body-hash ledger. |
| `lint-rule-ids.py` | soleur-coupled | `AGENTS.md` rule-id coverage. |
| `lint-scheduled-show-full-output.sh` | soleur-coupled | `scheduled-*.yml` convention + `plugins/soleur/skills/schedule` coupling. |
| `lint-shell-capture-exit.py` | generic | `git ls-files '*.sh'` producer; capture-of-negative-rc class is universal (the `test-all.sh` mention is baseline prose). |
| `lint-shell-trace-credential-refusal.py` | generic-after-extraction | xtrace-with-credential refusal is a universal class (v2); Soleur incidents cited are comments only, but the credential-binding corpus is repo-shaped. |
| `lint-skill-body-budget.py` | soleur-coupled | `plugins/soleur` SKILL.md corpus + `skill-body-budget.json`. |
| `lint-squash-ci-directives.sh` | generic | `[skip ci]` token scan of `gh pr create` bodies in workflows; token set is GitHub-documented. |
| `lint-supabase-deprecated-endpoints.sh` | soleur-coupled | Supabase endpoint corpus + `apps/web-platform/lib/supabase`. |
| `lint-trap-tempfile-ownership.py` | generic-after-extraction | Tempfile-cleanup ownership rules are generic (v2); keys on `SOLEUR_SCRATCH_SESSION_ROOT` markers. |
| `lint-window-closure-assertion.allowlist.txt` | soleur-coupled | Data companion of the window-closure lint (Soleur test roots). |
| `lint-window-closure-assertion.py` | soleur-coupled | TEST_ROOTS = `apps/web-platform`, `plugins/soleur/test`, `test`. |
| `lint-workflow-errexit-capture.py` | generic | Workflow run-body errexit-capture class; scans `.github/workflows`. |
| `lint-workflow-install-sites.sh` | generic-after-extraction | npm-install-site audit is generic (v2); assembly names `plugins/**` and `apps/web-platform` legs. |
| `lint-workflow-issue-write-scope.py` | generic | Issue-write permission lint over `.github/workflows`; Soleur cite is a docstring example. |
| `lint-workflow-local-action-checkout.py` | generic-after-extraction | `uses: ./…`-needs-checkout is generic (v2); third surface names `scripts/lib/bearer-curl.sh`. |
| `lint-workflow-run-body-syntax.py` | generic | Every `run:` body must parse as bash; `.github/workflows` only. |
| `lint-workflow-step-env-refs.py` | generic | Step-env scoping lint over workflow files. |
| `lint-workflows.sh` | generic | actionlint entry point with the 64 KiB hang guard; repo-specific text is comments. |

## The v1 set (and why)

| Guard | Source | Why v1 |
|---|---|---|
| `secret-scan` | `git-commit-secret-scan.sh` | The highest-value generic gate: credential-leak prevention with the colour-pin/`-diff` bypass work already measured. |
| `commit-on-main` | `plugins/soleur/scripts/precommit-guard.sh` + `lib/wrapper-boundary.sh` | Already self-contained by design (the near-verbatim emit). |
| `block-stash` | `guardrails.sh` `block-stash-in-worktrees` arm | Small extractable arm; boundary-regex detection generalizes. |
| `orphan-test` | `lint-orphan-test-suites.sh` | The meta-guard: a scaffolded suite that is never wired invisibly does nothing; generalizes to user-declared runner surfaces. |

`block-rm-rf` was audited for v1 promotion and stays v2: the
`block-rm-rf-worktrees`/`block-recursive-delete` arms read freeze-lock state and
incident machinery inside `guardrails.sh` — not self-contained.

The 9 `generic` lints above are the v2 candidate pool: shipping one is a
`guards.tsv` row + a template + an audit-verdict flip, not new design.
