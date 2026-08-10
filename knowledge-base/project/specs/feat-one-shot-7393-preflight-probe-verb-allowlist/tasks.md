# Tasks — preflight Check 10 probe execution boundary (#7393)

Plan: `knowledge-base/project/plans/2026-08-10-fix-preflight-check-10-probe-verb-allowlist-plan.md`
Lane: `cross-domain` · Brand-survival threshold: `single-user incident`

---

## Phase 0 — Preconditions (measure, do not assume)

- [ ] 0.1 Baseline suite: `bun test plugins/soleur/test/preflight-discoverability-test.test.ts plugins/soleur/test/observability-schema-parity.test.ts` → expect **83 pass, 0 fail**.
- [ ] 0.2 `command -v bwrap && bwrap --version` — record in PR body.
- [ ] 0.3 Sandbox efficacy probe. Inside the Step 10.5 sandbox each MUST report *no such file*:
      `wc -c < /home/$USER/.doppler/.doppler.yaml`, `cat /home/*/.doppler/.doppler.yaml`,
      `ls /run/user/$(id -u)/bus`; and `echo x > .git/config` MUST fail.
      Assert the **invariant** (file unreachable), never an exit code.
- [ ] 0.4 Sandbox non-regression probe: `curl` → `200`, `dig +short soleur.ai` non-empty,
      `grep -c . AGENTS.md` matches the host value.
- [ ] 0.5 `readlink -f /etc/resolv.conf`; confirm binding it after `--tmpfs /run` restores DNS.
- [ ] 0.6 Paste 0.2–0.5 output into the PR body (AC2–AC4 evidence).

## Phase 1 — Runtime + mirror + tests (RED → GREEN)

### 1.1 RED — failing tests first (`cq-write-failing-tests-before`)

- [ ] 1.1.1 Allowlist: each of the 11 verbs accepted; a non-allowlisted verb rejected.
- [ ] 1.1.2 Reject reason for a non-allowlisted verb names **both** remedies (repo-relative
      script; `credentials_required` when genuinely credentialed) + the allowlist-extension route.
- [ ] 1.1.3 Inline-program rejects: `bash -c`, `sh -c`, `python3 -c`, `node -e`, `bun -e`.
- [ ] 1.1.4 Execution-equivalent rejects: `awk 'BEGIN{system("…")}'`, `sed -e '1e …'`, `find . -exec … +`.
- [ ] 1.1.5 Path rules: `bash scripts/lint-workflows.sh --help` → `null`;
      `bash /abs/x.sh`, `bash ../x.sh`, `/usr/local/bin/gh api user` → non-null.
- [ ] 1.1.6 `rejectReason` stays a **pure sync** `string → string | null` (no subprocess).
- [ ] 1.1.7 Dequoting: `"doppler" secrets get X` → non-null.
- [ ] 1.1.8 `credentials_required` present ⇒ `SKIP-DECLARED`, executor stub **throws if called**;
      reason carries the declared scope verbatim.
- [ ] 1.1.9 `credentials_required: TBD` ⇒ FAIL (existing placeholder machinery).
- [ ] 1.1.10 `ssh …` + valid declaration ⇒ still FAIL (ssh not overridable).
- [ ] 1.1.11 `bwrap` unavailable ⇒ SKIP; executor stub throws if called (no unsandboxed fallback).
- [ ] 1.1.12 Corpus baseline count of `credentials_required:` across `knowledge-base/project/plans/` (expect 1).

### 1.2 GREEN — authoritative runtime first, mirror second

- [ ] 1.2.1 `preflight/SKILL.md` Step 10.4: delete the denylist gate; add `PROBE_VERB_ALLOWLIST`,
      effective-verb extraction, arg rules, `credentials_required` read (flat sub-field `awk`).
      Keep the gate a column-0 `if [[ "$CMD_DEQ" … ]]` with the assignment within 6 lines above,
      or generalize `gateWindow()`'s anchor in the same PR.
- [ ] 1.2.2 `preflight/SKILL.md` Step 10.5: bwrap sandbox. **`--tmpfs /home` before the repo bind.**
      Bind `$(readlink -f /etc/resolv.conf)` after `--tmpfs /run`. Fail-closed SKIP when bwrap
      is absent/unusable — never an unsandboxed fallback.
- [ ] 1.2.3 Mirror in `plugins/soleur/test/lib/discoverability-test-parser.ts`; delete `CRED_REJECT_RE`.
- [ ] 1.2.4 Step 10.6: matrix 8 → 11 rows incl. `SKIP-DECLARED`; **exactly one `**PASS**`** terminal.
- [ ] 1.2.5 Steps 10.7/10.8 + Result block + the global headless contract (~line 19) + the Phase 2
      aggregate row, so `SKIP-DECLARED` is visible headless and distinct from a path-gate SKIP.
      Never emit `$DT_STDOUT_SAFE` into a filed issue.
- [ ] 1.2.6 Rewrite the two Sharp Edges (denylist; `env -i` limitation). Retarget "do not describe
      this reject as though it closed the class" to **both** layers.
- [ ] 1.2.7 Rewrite the 4 denylist-pinning tests: `R2`, `R2b`, `R3`, and
      `Step 10.4 carries the credentialed-CLI reject` (which pins **three** assertions —
      the verb alternation, `\(\^\|\[\[:space:\]\]\|\/\)`, and `\[\[ "\$CMD_DEQ" =~ `).
- [ ] 1.2.8 Fixtures: `09-verb-not-allowlisted.md`, `10-credentials-required-skip.md` (synthesized).

## Phase 2 — Schema + doc surfaces

- [ ] 2.1 `plan/SKILL.md` §2.9 — canonical block comment + reject conditions.
- [ ] 2.2 `plan-issue-templates.md` — all 3 `## Observability` blocks, kept set-equal.
- [ ] 2.3 `deepen-plan/SKILL.md` §4.7 Steps 3/5 — allowlist check + `credentials_required`.
      **Place the mention outside the `the N required top-level fields (…)` count phrase and
      parenthetical** or parity surface 3 reddens (6 vs 5).
- [ ] 2.4 `deepen-plan/workflows/deepen-plan.workflow.js` — halt string + STEP 1 prose.
- [ ] 2.5 `observability-coverage-reviewer.md` §Step 6 — **body-only**; the `Acceptable shapes`
      sentence itself must carry the `credentials_required` condition. Frontmatter `description:`
      byte-unchanged.
- [ ] 2.6 `observability-schema-parity.test.ts` — new sub-field extractor over the indented
      children of `discoverability_test:`; leave the top-level assertions untouched.

## Phase 3 — ADR, C4, verification

- [ ] 3.1 Write `ADR-172-preflight-probe-execution-boundary.md`. `## Alternatives Considered`
      must defeat: no-execution/ADR-074 Stage A, probe registry, ephemeral `$HOME`.
      `## Consequences` records as **open**: network egress, PR-head trust circularity, and the
      accepted AP-020 violation (cite `principles-register.md` AP-020).
- [ ] 3.2 Re-derive the ADR ordinal against freshly-fetched `origin/main`; if it moves, sweep
      `grep -rn 'ADR-172' knowledge-base/project/{plans,specs}/` in the same edit.
- [ ] 3.3 File the probe-registry successor tracking issue (labels: `domain/engineering`,
      `type/chore`, `priority/p3-low`).
- [ ] 3.4 `model.c4` — amend `contributor` to state the general invariant (untrusted PR-head
      content executes only inside an isolation boundary; name Stage A and preflight's sandbox).
      Do **not** weaken it to match the implementation.
- [ ] 3.5 Run `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts`.
- [ ] 3.6 **Execution replay** over the `bash <script>` corpus class (78 probes): run each inside
      and outside the sandbox, diff verdicts, put the diff in the PR body, file one tracking
      issue per divergent plan. A static verb tally cannot detect this regression class.
- [ ] 3.7 `bash scripts/test-all.sh` → exit 0.
- [ ] 3.8 Verify `AGENTS.md` + `AGENTS.rules.md` byte-unchanged (`B_ALWAYS=44400`), and
      `views.c4` / `spec.c4` byte-unchanged.
- [ ] 3.9 PR body: `Closes #7393`, Phase 0 evidence, replay diff, and the
      `decision-challenges.md` DC-1 render.

---

## Blocking invariants (do not ship without)

1. **No unsandboxed fallback.** If bwrap cannot be established → SKIP.
2. **Exactly one `**PASS**` terminal** in the Step 10.6 matrix.
3. **`AGENTS.md` / `AGENTS.rules.md` byte-unchanged** (~1600 B headroom against the ratchet).
4. **Reviewer-agent `description:` byte-unchanged** (corpus already 347 words over target).
5. **Assert on gate windows, never whole-file greps** (`cq-assert-anchor-not-bare-token`).
