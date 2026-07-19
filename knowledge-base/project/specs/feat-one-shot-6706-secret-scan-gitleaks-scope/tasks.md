# Tasks — fix(secret-scan): ref-scope + DSN placeholder allowlist (#6706)

Plan: `knowledge-base/project/plans/2026-07-19-fix-secret-scan-gitleaks-ref-scope-and-dsn-placeholder-plan.md`
Lane: `cross-domain`

> **Three standing rules for every gitleaks assertion below** (each cost a wrong result during research):
> 1. Gate on **exit codes** — `no leaks found` contains the substring `leaks found`.
> 2. **Never pipe** an invocation whose exit code you assert — `$?` becomes the pipe's last stage.
> 3. Put fixtures in `$(mktemp -d)` **outside the worktree** — repo test dirs are path-allowlisted,
>    which makes negative assertions vacuous and positive ones fail spuriously.

## Phase 0 — Setup & RED baseline

- [ ] 0.1 Install the pinned scanner (same version + SHA the workflow pins):
      `curl -sSLo gitleaks.tgz https://github.com/gitleaks/gitleaks/releases/download/v8.24.2/gitleaks_8.24.2_linux_x64.tar.gz`
      → `echo "fa0500f6b7e41d28791ebc680f5dd9899cd42b58629218a5f041efa899151a8e  gitleaks.tgz" | sha256sum -c -`
      → `tar -xzf gitleaks.tgz gitleaks && chmod +x gitleaks`.
- [ ] 0.2 Ensure the flagged commit is present: `git cat-file -e 871fe6a94c7cbb13ec9badd2247c5b2d86f62b2f^{commit}`
      (else `git fetch origin feat-one-shot-6500-6466-inngest-cutover-blockers`).
- [ ] 0.3 **Capture RED** — `./gitleaks git --no-banner --redact -v -c .gitleaks.toml --log-opts="--no-merges 871fe6a94~1..871fe6a94" .`
      → exit **1**, `RuleID: database-url-with-password`, `File: apps/web-platform/infra/vector.toml`, `Line: 384`.
      The flagged line is the **comment**, not the scrubber regex.
- [ ] 0.4 Confirm the rule is a **Soleur custom rule**, not default-pack:
      `grep -c '^id = "database-url-with-password"' .gitleaks.toml` → **1**; and `./gitleaks dir <fixture>`
      with **no** `--config` → no leaks. (Guards the same-ID shadowing trap.)
- [ ] 0.5 Confirm the current tree is already clean — proves the fix must target *history*:
      `./gitleaks dir apps/web-platform/infra/vector.toml --no-banner --exit-code 1 -c .gitleaks.toml` → **0**.

## Phase 1 — Allowlist the placeholder DSN shape

- [ ] 1.1 In `.gitleaks.toml`, inside the **existing** `[[rules.allowlists]]` block under
      `id = "database-url-with-password"`, extend **only** the password-side alternation to
      `(?:PASSWORD|password|passwd|pass|pw|secret|<[^>]+>|\*+)@`.
      Leave the user-side alternation, the `paths` array, and the rule `id`/`regex` untouched.
- [ ] 1.2 Update the adjacent comment: cite `#6706` and the `@`-anchor property (matches only when the
      password is *exactly* the placeholder token).
- [ ] 1.3 **Do NOT** add a `[[rules]]` block, change the rule id, add a `paths` entry, or create `.gitleaksignore`.
- [ ] 1.4 Rerun 0.3 → exit **0** (GREEN). Re-run against the *unmodified* config → still exit **1** (AC1 both halves).
- [ ] 1.5 No detection regression — each alone in a `$(mktemp -d)` file, must exit **1**:
      `postgres://admin:SuperSecretPassw0rd@db.example.com`, `postgres://prod:passw0rdREALLEAK@db.internal`,
      `postgres://svc:pass-but-longer@host.example`, `postgresql://root:hunter2@10.0.0.5`.
- [ ] 1.6 Placeholders quiet — must exit **0**: `postgres://user:pass@host` (the only discriminating row),
      `postgres://<user>:<pw>@host`, `postgres://user:password@host`.
- [ ] 1.7 Ack gate not silently tripped: added-paths set from `parse-gitleaks-allowlists.mjs`
      (origin/main vs HEAD) is **empty**.
- [ ] 1.8 Commit with an `Allowlist-Widened-By: <name>` trailer — voluntary, because the gate cannot
      see `regexes` edits (#3888).

## Phase 2 — Scope `push:main` to main's ancestry

- [ ] 2.1 Change the `push` step to
      `./gitleaks git --redact --no-banner --exit-code 1 --log-opts="--no-merges HEAD"`.
- [ ] 2.2 Add a comment explaining why (bare form walks every fetched ref because checkout uses
      `fetch-depth: 0`; #6706), and note in-flight branches stay covered by `pull_request` + weekly cron.
- [ ] 2.3 **Correct stale wording** — the workflow must not document behaviour it no longer has:
      - header trigger comment `push: branches: [main]   full-tree scan after merge` → `main-ancestry scan after merge`
      - step name `Scan (full tree, push:main)` → `Scan (main ancestry, push:main)`
      - verify: `grep -c 'full tree' .github/workflows/secret-scan.yml` → **0**
- [ ] 2.4 Add a one-line note to the `on:.merge_group` block: Pattern B's "acked on its own" premise is
      convention-only for `regexes` widenings (#3888).
- [ ] 2.5 **Verify Phase 2 in isolation** (the original AC tested Phase 1 by mistake): in a scratch clone,
      commit a synthetic **non-allowlisted** DSN (`postgres://admin:SuperSecretPassw0rd@db.example.com`)
      on a side branch published as `refs/remotes/origin/6706ac`, `main` clean. Against the **same
      post-fix config**: bare form → exit **1**; `--log-opts="--no-merges HEAD"` → exit **0**. Delete the ref.

## Phase 3 — Weekly cron diagnosability (minimal form)

- [ ] 3.1 Add `-v` to the `schedule` step's invocation; keep its all-refs breadth.
- [ ] 3.2 Comment it: `-v` prints `RuleID`/`File`/`Line`/`Commit`; resolve the owner with
      `git branch -r --contains <Commit>` (#6706).
- [ ] 3.3 **Do NOT** build the JSON-report + `jq` + attribution-loop version. It was designed and verified,
      then cut at review: largest failure surface in the plan serving its smallest consumer, and a failing
      `jq` under `pipefail` replaces the scan verdict with jq's status (turning a *clean* run red).

## Phase 4 — Documentation

- [ ] 4.1 Add a ref-scope subsection to `knowledge-base/engineering/operations/secret-scanning.md`
      (verified: no such section exists today) covering all four events:
      `pull_request` → `base..head`; `merge_group` → candidate diff; `push` → main ancestry;
      `schedule` → all refs.
- [ ] 4.2 Document red-cron triage: `-v` fields + `git branch -r --contains <Commit>`.
- [ ] 4.3 Record the accepted trade-off: a branch pushed with **no PR** is no longer swept by `push:main`;
      its detection window becomes the weekly cron.
- [ ] 4.4 Record the merge-commit blind spot: `gitleaks git` uses `git log -p` with no `-m`/`--cc`, so
      merge-exclusive content is invisible to **every** job (not just the scoped one).

## Phase 5 — Follow-up issue (in-scope deliverable)

- [ ] 5.1 File an issue for the merge-commit blind spot. Include the measurement (`git log -p -1 cbd6c948d`
      → 0 bytes vs 10901 for its parent; `main` carries 35 merge commits; `allow_merge_commit: true`).
      Labels `type/security` + `priority/p3-low`. Verify both labels exist first via `gh label list`.

## Phase 6 — Verification & ship

- [ ] 6.1 `actionlint .github/workflows/secret-scan.yml` passes. Extract each modified `run:` block to a
      file and `bash -n` it. **Never** run `bash -n` on the `.yml` itself, and never `actionlint` a
      composite action.
- [ ] 6.2 Existing suites green (neither should need changes):
      `apps/web-platform/test/__synthesized__/parse-gitleaks-allowlists.test.sh`,
      `plugins/soleur/test/gitleaks-rules.test.sh`.
- [ ] 6.3 Walk every AC in the plan, recording the actual command + output.
- [ ] 6.4 `secret-scan` green on the PR (all five required contexts).
- [ ] 6.5 PR body: `Closes #6706`, references #3888 (why the trailer is manual), links the Phase 5 issue.
- [ ] 6.6 No post-merge operator steps — the merge triggers the `push:main` run that is the real-world
      assertion of the fix; `/soleur:ship` already watches post-merge check status.
