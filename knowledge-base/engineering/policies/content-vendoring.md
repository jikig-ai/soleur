# Content-Vendoring Policy

This policy governs **any content lifted into the Soleur repo from an upstream source under a permissive license** — detection rules, prompt fragments, taxonomy tables, model-card excerpts, fixture data, and similar narrative content. It does **not** govern service-vendor data-processing relationships (those live in `compliance-posture.md` §Vendor DPA Status).

The first registry instance is `gosprinto/compliance-skills`, lifted into `plugins/soleur/skills/gdpr-gate/references/` under MIT.

## 1. Scope

In-scope: any file that originated upstream and was committed verbatim or with documented edits to the Soleur repo, where the upstream project remains the canonical authority for the content.

Out-of-scope:
- Code dependencies installed via package managers (`npm`, `bun`, `cargo`). Those are pinned via lockfiles and audited via `npm audit` / `bun audit`.
- Service-vendor data flows (Hetzner, Supabase, Stripe, Cloudflare, Resend, Doppler) — those are governed by signed DPAs in `compliance-posture.md` §Vendor DPA Status.
- Content the team writes from scratch and credits as inspired-by.

## 2. NOTICE Schema

Every vendored bundle has a `NOTICE` file at the bundle root with YAML frontmatter:

```yaml
---
upstream: github.com/<owner>/<repo>
pinned-commit: <40-char SHA>
last-verified: <YYYY-MM-DD>
registry: knowledge-base/engineering/policies/content-vendoring.md
lifted-files:
  - path: <repo-relative path inside the bundle>
    upstream-path: <repo-relative path in the upstream repo>
    upstream-blob-sha: <upstream `git hash-object --no-filters` value>
    local-blob-sha: <local `git hash-object --no-filters` value>
    status: active|active-verbatim|active-eu-extended|active-soleur-rewritten|deprecated
---
```

Two blob SHAs per file because the lifted file MUST carry an attribution header on line 1, so its local hash necessarily differs from the upstream hash. The `upstream-blob-sha` feeds the drift workflow; the `local-blob-sha` feeds the lefthook integrity gate. **Frontmatter is the canonical machine-readable form.** Any human-readable table in the body of NOTICE is convenience prose; if the two diverge the frontmatter wins and the table is a bug.

## 3. Lifting Procedure

When deciding to lift content from an upstream:

1. Verify the license permits redistribution + modification (MIT, Apache-2.0, BSD, ISC, CC-BY are typically fine; AGPL imposes obligations the operator must accept consciously).
2. Lift the file verbatim first. Each lifted file MUST start with an attribution header on line 1:
   ```text
   <!-- Adapted from <owner>/<repo> (<license>) — see NOTICE -->
   ```
3. Add a row to the bundle NOTICE `lifted-files` block with both blob SHAs computed via `git hash-object --no-filters`.
4. Add the lifted-file path to the lefthook `vendor-pin-integrity` glob — the parity assertion in `plugins/soleur/test/vendor-pin-integrity.test.sh` AC5b ensures NOTICE and lefthook stay in sync.
5. Add a row to `compliance-posture.md` §Vendored Code Provenance with the upstream + license + pinned-commit + lifted-file count + status.
6. Apply Soleur extensions in subsequent commits with `status:` set per the divergence type (`active-verbatim` if zero edits, `active-eu-extended` if EU-specific additions, `active-soleur-rewritten` if structurally changed).

When the upstream is no longer reachable (404, archived, deleted), follow the policy on §6 Re-vendor procedure.

## 4. Drift Detection

Three layers, each catching a distinct failure mode:

### 4.1 Cron-driven content drift (workflow)

`.github/workflows/scheduled-content-vendor-drift.yml` runs weekly at `'17 11 * * MON'` (off-peak / off-cluster). It reads NOTICE frontmatter, fetches current upstream blob SHAs via `gh api repos/<o>/<r>/contents/<path>?ref=main`, classifies any drift via `vendor-drift-classify.sh`, and on classifier exit codes 10–16 opens a re-vendor PR via the `bot-pr-with-synthetic-checks` composite. The PR body links to the runbook; the operator merges after review.

### 4.2 Pre-commit silent-edit detection (lefthook)

`vendor-pin-integrity.sh` is invoked by the lefthook `vendor-pin-integrity` stanza on every commit that touches NOTICE-tracked paths. It compares `git hash-object --no-filters <local-file>` against the `local-blob-sha` pinned in NOTICE and exits non-zero on mismatch. This catches the class of bug where an operator (or agent) silently edits an upstream-vendored file without bumping NOTICE — which would otherwise leave NOTICE attesting to a state that no longer exists in the working tree.

### 4.3 Runtime staleness banner (gdpr-gate.sh)

When the cron pipeline silently breaks (workflow disabled, GH outage, PR queued unmerged), the cron-driven drift signal goes silent — but the in-process risk continues to grow. `gdpr-gate.sh` subshell-execs `notice-frontmatter.sh days-stale` on every invocation:

- `days_stale > 30` → STDOUT banner: `⚠ gdpr-gate rules N days stale (last verified <date>) — output is advisory only and may miss recently-patched detection rules.`
- `days_stale > 90` → additional STDOUT line: `POSTURE_FAIL: gdpr-gate rules >90 days stale — compliance/critical posture row required.`

Banner + POSTURE_FAIL emit to STDOUT (not stderr) because agent runtimes (Claude Code skill harness, MCP servers) commonly swallow stderr. NOTICE missing / parser deletion / future-dated `last-verified` all resolve to `days_stale=999` → banner fires. The gate exits 0 in all paths (advisory contract preserved).

## 5. Severity Classification

`vendor-drift-classify.sh` reads a unified diff on stdin and emits one of seven exit codes (priority order — first match wins):

| Exit | Class | Trigger | Label set |
|---|---|---|---|
| 15 | upstream rollback | new-sha is ancestor of pinned-sha | `vendor/upstream-rollback,needs-human-review` |
| 12 | upstream archived | `--archived` flag (set by workflow `gh api repos/<o>/<r>` disambiguation) | `vendor/upstream-archived,compliance/critical` |
| 16 | upstream renamed | `--renamed` flag | `vendor/upstream-archived,needs-human-review` |
| 11 | LICENSE diff | diff touches a path containing `LICENSE` | `vendor/license-changed,compliance/critical` |
| 10 | security-relevant | regex hit on diff body (added markdown table row, `[CRITICAL]`, `MUST`, `Art. <N>`, `§ <N>`, new file under `references/layers/`) | `vendor/pin-drift,compliance/critical` |
| 13 | batched | non-empty diff with no security signal | `vendor/pin-drift` |
| 0 | no-op | empty / whitespace-only diff | (none) |

The classifier is intentionally crude — its job is to route, not to judge. A human reviewer makes the final call on every PR labeled `compliance/critical`.

## 6. Re-vendor Procedure

The drift workflow performs the re-vendor automatically for classifier exits 10/11/13:

1. Fetch upstream-old blob (NOTICE pin) and upstream-new blob (current HEAD).
2. `git merge-file --diff3 <lifted-path> <upstream-old-tmp> <upstream-new-tmp>` per lifted file.
3. Conflict-marker gate: `grep -l '<<<<<<<' <lifted-paths>` — if any matches, append `needs-human-review` to the label set; the operator resolves manually per the runbook.
4. Bump NOTICE `pinned-commit`, per-file `local-blob-sha` + `upstream-blob-sha`, and `last-verified` in the SAME commit as the lifted-file changes — merging the PR ratifies all bumps.
5. PR body links to this policy and the runbook.

For classifier exits 12/15/16 (archived / rollback / renamed), the workflow opens the PR with `needs-human-review` and does not perform the auto-merge — the operator decides per the runbook.

**Pre-vendor diff scan** (for first-time lifts of new bundles): currently DEFERRED — see scope-out issue. The first re-vendor PR landing under this policy will introduce the scan as a workflow step before this policy section is filled in. Until then, reviewer eyes + the conflict-marker grep are the manual fallback.

## 7. Runtime Staleness Contract

The 30-day banner threshold and 90-day POSTURE_FAIL threshold are stable design parameters, not configurable settings. They are not relaxable without a published Architecture Decision Record. Rationale: the gdpr-gate's "no findings" output is rendered as authoritative narrative claims via the gate's weave-don't-append shape; staleness is the user's only signal that those claims may be based on an outdated rule set, and the threshold is calibrated to the upstream's typical patch cadence (multiple commits per month).

## 8. POSTURE_FAIL Operator Chain

When `gdpr-gate.sh` emits a `POSTURE_FAIL:` line during a regulated PR's `/soleur:gdpr-gate` invocation, the operator:

1. Does **not** pause the current PR. The gate is advisory and exits 0; the staleness signal is a separate cycle.
2. Opens a tracking issue with `gh issue create --label compliance/critical --title "[gdpr-gate] >90d stale rules — N days since last-verified"`.
3. Appends a row to `compliance-posture.md` §Active Compliance Items per the canonical row schema (the gate never writes there directly; this is operator-acknowledged write only).
4. Commits the row with `compliance: register vendor-pin-staleness for #<issue>`.
5. Pings the in-flight `ci/vendor-drift-*` PR (or dispatches the workflow manually via `gh workflow run scheduled-content-vendor-drift.yml`) to drive re-vendor.

The current regulated-data PR can ship; the staleness-driven follow-up is a separate work cycle with its own review + merge.

## 9. Local-Edit Hygiene

`git hash-object --no-filters` is canonical for both NOTICE entries and the integrity gate. The `--no-filters` flag is load-bearing — it skips gitattributes line-ending normalisation that would otherwise diverge from upstream blob SHAs on Windows / CRLF-configured workspaces. On Windows operators using WSL2 or Linux subsystems this is generally moot; native Windows commits should be made via Git for Windows with `core.autocrlf=input` to keep blob SHAs byte-identical across platforms.

## 10. Registry

| Bundle | Upstream | License | Pinned | Last Verified | NOTICE | Status |
|---|---|---|---|---|---|---|
| gdpr-gate references | `github.com/goSprinto/compliance-skills` | MIT | `7b58d68` | 2026-05-10 | `plugins/soleur/skills/gdpr-gate/NOTICE` | active (5 lifted files) |

When a new bundle is added: append a row here, write its NOTICE per §2, register the lefthook glob per §4.2, and add the `compliance-posture.md` row per §3 step 5.

## Cross-references

- Operator runbook: `knowledge-base/engineering/ops/runbooks/vendor-pin-drift-resolution.md`
- Compliance posture: `knowledge-base/legal/compliance-posture.md` §Vendored Code Provenance
- gdpr-gate skill: `plugins/soleur/skills/gdpr-gate/SKILL.md`
- Drift workflow: `.github/workflows/scheduled-content-vendor-drift.yml`
- Helper scripts: `plugins/soleur/skills/gdpr-gate/scripts/{notice-frontmatter,vendor-pin-integrity,vendor-drift-classify}.sh`
