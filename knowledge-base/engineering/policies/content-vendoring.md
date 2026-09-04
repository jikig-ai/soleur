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
soleur-authored:
  - path: <repo-relative path inside the bundle>
    local-blob-sha: <local `git hash-object --no-filters` value>
    status: soleur-authored|soleur-authored-archived
---
```

Two blob SHAs per lifted file because the lifted file MUST carry an attribution header on line 1, so its local hash necessarily differs from the upstream hash. The `upstream-blob-sha` feeds the drift comparison; the `local-blob-sha` feeds the lefthook integrity gate.

`soleur-authored` is the second registry, for reference files written from scratch for the bundle. Same record shape and the same `local-blob-sha` tamper check, but **no upstream provenance**: these never appear in the `upstream-files` view and are never compared against upstream. The split is deliberate rather than a nullable `upstream-path` on one list — provenance must be a DECLARED category, never inferable from a missing field, because a `lifted-files` row for a Soleur-authored file would attest third-party licence provenance for the project's own writing. The attribution header on line 1 is the oracle for which list a file belongs in: every `lifted-files` entry carries it, no `soleur-authored` entry does.

Registering a file in neither list is what the integrity gate rejects; registering it in both is refused outright as ambiguous provenance.

**Frontmatter is the canonical machine-readable form.** Any human-readable table in the body of NOTICE is convenience prose; if the two diverge the frontmatter wins and the table is a bug. That divergence is not hypothetical — the gdpr-gate NOTICE listed eight lifted files in its table and five in its frontmatter for 117 days (`#7710`), so the parity is now asserted by test rather than trusted.

## 3. Lifting Procedure

When deciding to lift content from an upstream:

1. Verify the license permits redistribution + modification (MIT, Apache-2.0, BSD, ISC, CC-BY are typically fine; AGPL imposes obligations the operator must accept consciously).
2. Lift the file verbatim first. Each lifted file MUST start with an attribution header on line 1:

   ```text
   <!-- Adapted from <owner>/<repo> (<license>) — see NOTICE -->
   ```

3. Add a row to the bundle NOTICE with blob SHAs computed via `git hash-object --no-filters`: `lifted-files` (both SHAs) for an upstream-derived file, or `soleur-authored` (`local-blob-sha` only) for one written for the bundle. A file must appear in exactly one of the two — the attribution header on line 1 decides which — and the human-readable table must be updated in the same commit.
4. Add the lifted-file path to the lefthook `vendor-pin-integrity` glob — the parity assertion in `plugins/soleur/test/vendor-pin-integrity.test.sh` AC5b ensures NOTICE and lefthook stay in sync.
5. Add a row to `compliance-posture.md` §Vendored Code Provenance with the upstream + license + pinned-commit + lifted-file count + status.
6. Apply Soleur extensions in subsequent commits with `status:` set per the divergence type (`active-verbatim` if zero edits, `active-eu-extended` if EU-specific additions, `active-soleur-rewritten` if structurally changed).

When the upstream is no longer reachable (404, archived, deleted), follow the policy on §6 Re-vendor procedure.

## 4. Drift Detection

Four layers, each catching a distinct failure mode:

### 4.1 Cron-driven content drift (workflow)

The content-vendor-drift cron (`apps/web-platform/server/inngest/functions/cron-content-vendor-drift.ts`, an Inngest function since the TR9 Phase-2 migration -- it was `.github/workflows/scheduled-content-vendor-drift.yml`, which no longer exists) runs weekly at `'17 11 * * 1'` (off-peak / off-cluster). It reads NOTICE frontmatter, fetches current upstream blob SHAs via `gh api repos/<o>/<r>/contents/<path>?ref=main`, classifies any drift via `vendor-drift-classify.sh`, and on classifier exit codes 10–16 opens a re-vendor PR via the `bot-pr-with-synthetic-checks` composite. The PR body links to the runbook; the operator merges after review.

### 4.2 Pre-commit silent-edit detection (lefthook)

`vendor-pin-integrity.sh` is invoked by the lefthook `vendor-pin-integrity` stanza on every commit that touches NOTICE-tracked paths. It compares `git hash-object --no-filters <local-file>` against the `local-blob-sha` pinned in NOTICE and exits non-zero on mismatch. This catches the class of bug where an operator (or agent) silently edits an upstream-vendored file without bumping NOTICE — which would otherwise leave NOTICE attesting to a state that no longer exists in the working tree.

### 4.3 Runtime staleness banner (gdpr-gate.sh)

When the cron pipeline silently breaks (workflow disabled, GH outage, PR queued unmerged), the cron-driven drift signal goes silent — but the in-process risk continues to grow. `gdpr-gate.sh` subshell-execs `notice-frontmatter.sh days-stale` on every invocation:

- `days_stale > 30` → STDOUT banner: `⚠ gdpr-gate rules N days stale (last verified <date>) — output is advisory only and may miss recently-patched detection rules.`
- `days_stale > 90` → additional STDOUT line: `POSTURE_FAIL: gdpr-gate rules >90 days stale — compliance/critical posture row required.`

Banner + POSTURE_FAIL emit to STDOUT (not stderr) because agent runtimes (Claude Code skill harness, MCP servers) commonly swallow stderr. NOTICE missing / parser deletion / future-dated `last-verified` all resolve to `days_stale=999` → banner fires. The gate exits 0 in all paths (advisory contract preserved).

### 4.4 Pull-request-time upstream verification (CI)

`.github/workflows/vendor-pin-verify.yml` runs `vendor-pin-integrity.sh --verify-upstream` on every pull request touching the vendored tree. It asserts that each `upstream-blob-sha` in NOTICE resolves to a real, fetchable object in the upstream repository, which closes the co-edit bypass: a PR that edits a lifted file AND its NOTICE pin in the same diff satisfies the local hash check tautologically, because both sides move together.

Note what this layer does and does not buy. It proves each pinned blob EXISTS upstream; it does not prove the pin is CURRENT. A pin that resolves is not a pin that matches upstream `main` — that is §4.1's job, and conflating the two is why a "verify" step can read as a freshness guarantee it never made.

This layer was omitted from this section's own count until #7710, which is a small instance of the failure the whole document is about: an enforcement surface that exists, runs, and is not written down is one nobody reasons about.

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

## 6a. Verification-Only Refresh (no drift)

§6 governs the drift-detected path only. It says nothing about the far more common outcome — the comparison ran, every file matched, and there is nothing to re-vendor — and before #7710 no clause covered it. The consequence was not a gap in prose: `last-verified` had no writer at all on the clean path, so the field aged 117 days while the corpus was verified clean every week, and the gdpr-gate's staleness banner fired continuously on a corpus that had never drifted.

**Trigger.** A single run of the content-vendor-drift cron that compared the COMPLETE registry and found every file SAME with zero errors, against an upstream repository that is itself healthy. Formally, the run may advance the field only when all of the following hold:

- the registry is non-empty (`0 of 0` is not evidence of currency);
- every record the NOTICE **declares** was examined — the count comes from the declared records, not from the parser's emitted view, because a record missing its `upstream-blob-sha` is dropped from that view and would otherwise shrink the denominator alongside the numerator, making a partial comparison read as complete;
- zero files drifted;
- zero files errored — a file that could not be fetched is not a file that was verified;
- the upstream repository is neither archived, renamed, nor unreachable.

Two scope limits, stated here because this is the canonical statement and the
other surfaces point at it:

- **The registry compared is the upstream-derived one.** `soleur-authored`
  records carry a `local-blob-sha` checked at commit time; the attestation says
  nothing about them, while `last-verified` is a single scalar the gate reads
  as the age of the whole corpus.
- **A file ADDED upstream is invisible.** The comparison enumerates only the
  paths the NOTICE already declares and never lists the upstream directory, so
  a new upstream rule file is undetectable and every registered file still
  reads SAME.

**Cadence.** A verified-clean run does not write if the field was advanced
recently — the write is suppressed below 21 days. The banner fires at 30, so
the observed age never exceeds 21 on the healthy path: one missed run stays
inside the window, two do not. That 9-day margin is what makes the banner a
genuine early warning rather than a standing condition, so the suppression
constant cannot be raised past the banner threshold without breaking it. This is a separate condition because it is invisible to the per-file result: every file compares SAME against an archived upstream, since the blobs at the pinned SHAs still resolve. Without it a run would escalate a `compliance/critical` "upstream archived" issue and advance the attestation in the same pass.

**What advances.** `last-verified` only. No `pinned-commit` change, no `local-blob-sha` change, no content change. The commit's allowlist is the NOTICE path alone, so a verification-only refresh cannot carry a `references/` edit. Note the allowlist is a path PREFIX rather than an exact path, and it does not constrain the commit to a single FIELD within the NOTICE — nothing else on this path dirties that file, but the guarantee is "one path", not "one line".

**Who advances it.** The cron, via a self-merging bot pull request (`safeCommitAndPr`, `mergeMode: "direct"`). The commit message records the pinned commit compared against and the per-state counts.

Writes to `last-verified` are reserved to that automation **by convention, not by mechanism** — an operator editing the field by hand is asserting a comparison no artifact records, which is the state this section exists to end, but nothing currently rejects such an edit: CODEOWNERS auto-requests a reviewer and no ruleset on this repository's default branch requires the review. Stated as a convention rather than a control, because a prose reservation with no enforcement is the same defect class `#7710` documents.

**What it does NOT assert.** That upstream is healthy, maintained, or still the right dependency. An abandoned-but-unarchived upstream returns SAME forever, and this refresh will keep attesting to it. That residual is recorded in ADR-203 rather than papered over.

## 7. Runtime Staleness Contract

The 30-day banner threshold and 90-day POSTURE_FAIL threshold are stable design parameters, not configurable settings. They are not relaxable without a published Architecture Decision Record. Rationale: the gdpr-gate's "no findings" output is rendered as authoritative narrative claims via the gate's weave-don't-append shape; staleness is the user's only signal that those claims may be based on an outdated rule set, and the threshold is calibrated to the upstream's typical patch cadence (multiple commits per month).

## 8. POSTURE_FAIL Operator Chain

When `gdpr-gate.sh` emits a `POSTURE_FAIL:` line during a regulated PR's `/soleur:gdpr-gate` invocation, the operator:

1. Does **not** pause the current PR. The gate is advisory and exits 0; the staleness signal is a separate cycle.
2. Opens a tracking issue with `gh issue create --label compliance/critical --title "[gdpr-gate] >90d stale rules — N days since last-verified"`.
3. Appends a row to `compliance-posture.md` §Active Compliance Items per the canonical row schema (the gate never writes there directly; this is operator-acknowledged write only).
4. Commits the row with `compliance: register vendor-pin-staleness for #<issue>`.
5. Pings the in-flight `ci/content-vendor-drift-*` PR (or dispatches the cron manually via `/soleur:trigger-cron` with `cron/content-vendor-drift.manual-trigger` -- `gh workflow run` cannot reach it, there is no workflow) to drive re-vendor.

The current regulated-data PR can ship; the staleness-driven follow-up is a separate work cycle with its own review + merge.

## 9. Local-Edit Hygiene

`git hash-object --no-filters` is canonical for both NOTICE entries and the integrity gate. The `--no-filters` flag is load-bearing — it skips gitattributes line-ending normalisation that would otherwise diverge from upstream blob SHAs on Windows / CRLF-configured workspaces. On Windows operators using WSL2 or Linux subsystems this is generally moot; native Windows commits should be made via Git for Windows with `core.autocrlf=input` to keep blob SHAs byte-identical across platforms.

## 10. Registry

| Bundle | Upstream | License | Pinned | Last Verified | NOTICE | Status |
|---|---|---|---|---|---|---|
| gdpr-gate references | `github.com/goSprinto/compliance-skills` | MIT | `7b58d68` | 2026-05-10 | `plugins/soleur/skills/gdpr-gate/NOTICE` | active (8 lifted files) |

When a new bundle is added: append a row here, write its NOTICE per §2, register the lefthook glob per §4.2, and add the `compliance-posture.md` row per §3 step 5.

## Cross-references

- Operator runbook: `knowledge-base/engineering/operations/runbooks/vendor-pin-drift-resolution.md`
- Compliance posture: `knowledge-base/legal/compliance-posture.md` §Vendored Code Provenance
- gdpr-gate skill: `plugins/soleur/skills/gdpr-gate/SKILL.md`
- Drift cron: `apps/web-platform/server/inngest/functions/cron-content-vendor-drift.ts` (Inngest; the Sentry monitor slug keeps the pre-migration name `scheduled-content-vendor-drift`)
- Helper scripts: `plugins/soleur/skills/gdpr-gate/scripts/{notice-frontmatter,vendor-pin-integrity,vendor-drift-classify}.sh`
