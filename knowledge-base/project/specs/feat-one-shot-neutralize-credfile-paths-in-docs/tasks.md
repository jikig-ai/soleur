# Tasks — Neutralize resolvable credential-file paths in tracked docs

Plan: `knowledge-base/project/plans/2026-07-23-fix-neutralize-resolvable-credential-paths-in-docs-plan.md`
Lane: cross-domain · Threshold: single-user incident (requires_cpo_signoff)

> Hygiene: these tasks are a tracked doc. Do NOT write any resolvable home-relative
> credential path or the bare Doppler config filename here — describe or use a
> directory-only form (`~/.doppler/`). The plan's guard scans this file.

## Phase 1 — Neutralize the every-ship trigger (`preflight/SKILL.md`)

- [ ] 1.1 Read the four current literals in `plugins/soleur/skills/preflight/SKILL.md` (lines ~820, ~836, ~843, ~1075) directly from the file.
- [ ] 1.2 Neutralize line ~820 (the `dp.ct.*` token source) → describe the on-disk config via `~/.doppler/` (dir only), no resolvable file path.
- [ ] 1.3 Neutralize line ~836 (the reject `echo` message) → replace the parenthetical home-relative path list with descriptive file names; keep the rest of the message verbatim.
- [ ] 1.4 Neutralize line ~843 (the `curl --data-binary @…` exfil example) → placeholder `@<doppler-config>` preserving attack shape.
- [ ] 1.5 Neutralize line ~1075 (Sharp Edge) → "on-disk token stays reachable".
- [ ] 1.6 Confirm NO change to `CMD_DEQ`, the `CRED_REJECT_RE` verb regex, the SSH reject, or `SUBST_REJECT_RE`.

## Phase 2 — Keep the runtime mirror in lockstep

- [ ] 2.1 Apply the identical neutralization to `plugins/soleur/test/lib/discoverability-test-parser.ts:231` (the returned error string mirrors SKILL.md:836).
- [ ] 2.2 Neutralize the explanatory comments at `discoverability-test-parser.ts:36` and `preflight-discoverability-test.test.ts:882`.
- [ ] 2.3 Run `bun test plugins/soleur/test/preflight-discoverability-test.test.ts` → expect green. If any assertion reddens, it pinned a path substring; update in lockstep and record.

## Phase 3 — Build the guard (`scripts/lint-credential-path-literals.py`)

- [ ] 3.1 Scaffold from `scripts/lint-infra-no-human-steps.py` (arg surface, `--changed --base`, changed-files grandfathering).
- [ ] 3.2 Scope: `*.md` under `plugins/**` + `knowledge-base/**`; exclude `**/archive/**`; do NOT exclude plans/specs.
- [ ] 3.3 Encode the hard-fail regex table: Doppler (home-relative + bare config filename), SSH private keys under `~/.ssh/`, netrc/git-credentials home dotfiles, and AWS/gcloud/Docker filenames only under their credential dir. Anchor so directory-only forms do not match.
- [ ] 3.4 Encode the advisory (report-only) class: `/home/<user>/` and `/root/` credential forms.
- [ ] 3.5 On hard-fail: emit file/line/literal + neutralization recipe; exit non-zero.

## Phase 4 — Non-vacuous unit test (`scripts/lint-credential-path-literals.test.sh`)

- [ ] 4.1 Scaffold from `scripts/lint-infra-no-human-steps.test.sh`; synthesize fixtures at runtime via `mktemp` + heredoc (no committed trigger literal).
- [ ] 4.2 Positive fixtures (guard exits non-zero): resolvable home-relative Doppler config path; bare Doppler config filename; `~/.ssh/` private key.
- [ ] 4.3 Negative fixtures (guard exits zero): the neutralized descriptive forms.
- [ ] 4.4 Boundary fixtures: `~/.doppler/` dir-only, `.pub` key, embedded/suffixed name → no match.
- [ ] 4.5 Advisory-not-fail fixture: `/home/deploy/`-prefixed Docker config → exit zero, listed in report.

## Phase 5 — Register the guard

- [ ] 5.1 `scripts/test-all.sh`: add `run_suite "scripts/lint-credential-path-literals" bash scripts/lint-credential-path-literals.test.sh` near the `lint-infra-no-human-steps` registration.
- [ ] 5.2 `.github/workflows/ci.yml`: add the changed-mode step to the `lint-bot-statuses` job (mirror the `lint-infra-no-human-steps` block).
- [ ] 5.3 Check `scripts/required-checks.txt` + ruleset for `lint-bot-statuses` blocking status; record honestly in PR body; recommend promotion or add to follow-up.
- [ ] 5.4 `bash scripts/lint-orphan-test-suites.sh` passes.

## Phase 6 — Consolidated follow-up

- [ ] 6.1 `gh label list` to verify the label exists.
- [ ] 6.2 File ONE `gh issue create` tracker enumerating the grandfathered home-relative credential-path docs + neutralization recipe; NOT `Closes`.

## Verification (pre-merge ACs)

- [ ] V1 Resolvable Doppler literal + `@`-exfil form gone from `preflight/SKILL.md` (grep = 0).
- [ ] V2 `grep -c 'credentialed CLI' preflight/SKILL.md` unchanged (≥1).
- [ ] V3 Verb denylist regex line byte-identical to `origin/main`.
- [ ] V4 Doppler config filename grep in `discoverability-test-parser.ts` = 0.
- [ ] V5 `bun test …/preflight-discoverability-test.test.ts` passes.
- [ ] V6 `bash scripts/lint-credential-path-literals.test.sh` passes (positive fixture non-vacuous).
- [ ] V7 `python3 scripts/lint-credential-path-literals.py --changed --base origin/main` exits 0.
- [ ] V8 `python3 scripts/lint-credential-path-literals.py <plan> <tasks>` exits 0 (own artifacts clean).
- [ ] V9 `bash scripts/lint-orphan-test-suites.sh` + `grep -q lint-credential-path-literals scripts/test-all.sh`.
