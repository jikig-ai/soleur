# Recovery evidence — 2026-10-25

## Scope and authorization

The missing worktree was recreated from the existing branch at
`a4cd9861eefedef458727c28cef2e0f57c6db7fb`. GitHub subsequently confirmed the same
remote head, OPEN/draft state and disabled auto-merge. Committed files were
restored; missing private evidence was not recovered by checkout. The operator's
later `approved to all` instruction renews non-production investigation,
coordination and preparation without per-read prompts. The explicit draft hold,
provider/legal gates and exact destructive production authorization remain.

The [writer coordination request](https://github.com/jikig-ai/soleur/pull/9051#issuecomment-6399889468)
is a request, not clearance. A bounded recent-run list is not a complete writer
census or an exclusion mechanism.

## Fresh metadata capture

The private capture at `2026-10-25T18:53:31.624887Z` has SHA-256
`c6a42366c6eae1879a983edcabb1f27032fa3e4e5b4b97f7c8d1744da589dd0b`.
The earlier capture at `18:49:41.330705Z`, independently inspected by the CTO,
has SHA-256 `5668bad4ffbadd34ad49ad135e3ff6d0ee3e69e6f16e1b0e3de5ad714c1c8d35`.
Both are metadata-only observations, not recovery executions.

- Doppler `soleur/dev_scheduled` resolved to environment `dev`. The pooler
  username's project ref matched the canonical dev public URL, including DNS
  alias resolution; dev and production public project refs differed. The only
  production setting read was its public URL, not a production DB credential.
- Certificate and hostname verification used Supabase's public root, obtained
  over HTTPS from the certificate URL in its official Studio configuration.
  PEM SHA-256: `700723581420dd1ac98fd7e9ac529f0ef210eadcaf87fc868a3ad7d114c2f3b7`.
  The CA was scoped to this collector; no host trust configuration changed.
- Both identity and catalog queries used explicit READ ONLY transactions; the
  catalog used REPEATABLE READ. Server-reported read-only state was checked.
  Application rows read: **0**. Database mutations: **0**.
- The capture contains **194** ledger rows, **64** public tables and **14**
  Codex/engine functions. Raw catalog/session metadata remains private in the
  ignored `.soleur/dev-recovery-evidence-20261025/` directory, mode 0600 files
  under a mode 0700 directory. No connection credential is retained there.
- A granted advisory lock was attributed to `ti-40222601072`; the corresponding
  GitHub read identified a tenant-integration run on main. This is an observed
  CI holder, not proof that every writer is coordinated. The earlier collector
  returned only the `ti` prefix; that earlier field cannot identify a run.

Fresh capture attribution does not establish the origin of the missing earlier
catalog capture. That historical uncertainty remains.

## Ledger comparison and containment

At the restored source there are **193** forward migrations. Live rows retain
the ten legacy names 143–152, while renamed 163–172 and notice issuance 173 are
absent. Every non-null hash for a same-named forward migration matches source.
The CTO independently verified that all ten applied legacy blobs are identical
to their proposed renamed source blobs. This supports preparing an honest
filename-only mapping; it does not prove live-schema equivalence.

The extra `051_action_class_widening_and_action_sends.down.sql` and
`164_git_data_erasure_pending.sql` rows are outside that mapping. They are not
authorized cleanup targets. Source resync and independent classification remain
necessary before a final mapping is generated.

The authenticated two-argument acknowledgment overload remains executable in
the capture; the one-use notice-issuance replacement is genuinely unapplied.
Do not exercise it against real conversations. Qualification remains blocked;
prepare and verify containment within the coordinated recovery sequence.

## Offline runner review

Independent data-integrity and security review reproduced two inherited runner
defects and tracked them before implementation in
[issue 11096](https://github.com/jikig-ai/soleur/issues/11096): credential leakage
under xtrace and raw-file SHA-1 fallback in a Git-blob hash field. Synthetic
regressions ran RED before implementation and GREEN after. The corrected runner
hash is `cca2cd3a9b7268a57198ccd10a27e018c42e9ea3e56a26d052f97451ad951aa1`.
Its injected SQL guard remains
`7b36f9438ae5772a5b05ff0ec47302e6ac068a0ecb0d9f144cd1162058fb27b8`.

Both reviewers support this exact runner for source-only admission after final
validation. Neither review grants runtime, image/profile, shared-writer,
reconciliation, provider, legal, authenticated QA or shipping clearance. The
broader database-URL tracing scan also required six existing-script fixes;
baseline files remain unchanged.

## Required continuation

Preserve the source fixes, resync main and resolve migration-number collisions
before producing the final source-bound ten-row mapping and isolated
transaction rehearsal. Every renumbered tie/acknowledgment guard and test must
move with its migration. Live reconciliation requires fresh target evidence,
independently validated schema equivalence, successful isolated rehearsal,
agreed/enforced writer coordination, an actually acquired mutex, transactional
ledger locking/CAS and independent exact-command review. Keep migration 173
pending until genuinely applied through its own reviewed path. Full review,
QA, preflight, provider/legal, qualification and draft/readiness holds remain.

## Focused validation addendum — 2026-10-25

The final credential-tracing suite passed **653/653** with unchanged start/end
source hashes; the repository scan passed across **1,800** files with unchanged
baselines. Mutex tests passed **54/54**, WORM preflight tests **28/28**, and the
updated fake-Git/psql runner tests **8/8**. Independent guard-removal and regex-arm
mutants failed their intended assertions. Both reviewers rechecked the final
correction and accepted the exact source-only runner hash above. ShellCheck and
the scoped whitespace check passed.

The canonical source-review pin was refreshed to that independently reviewed
hash; all **8** rehearsal assertions now pass. The full offline wrapper then
refused its preparation phase because runtime source was still uncommitted.
This is a clean-source refusal, not a complete wrapper pass. Preserve the
reviewed fixes in a commit and rerun the complete wrapper on clean source.

## Clean-source validation and recovery addendum — 2026-10-26

The complete offline qualification wrapper subsequently passed on clean commit
`fac3acfd2839135992c80fa1a62c323d3c5481ea`, with exit 0 and unchanged HEAD.
That result belongs to this exact pre-resync source; it is not transferred to
the main merge or later renumbering. The commit is now pushed to PR 9051.

After interruption the original worktree and Git registration were absent.
Recreation preserved the committed fixes but not ignored evidence or the
uncommitted merge. A second disappearance occurred before a pending installer
could start, despite a current branch lease. Cause is unverified and tracked in
[issue 11162](https://github.com/jikig-ai/soleur/issues/11162). Recovery now uses
the same branch in `.worktrees/pr9051-recovery-20261026`, with an explicit Git
worktree lock while active. This is protection against ordinary removal/prune,
not proof of the removing mechanism. Earlier private captures are currently
unavailable; their committed digests and summaries remain historical evidence.

The retained CTO ruling requires adding exact
`167_codex_auth_mode_rebind.sql` protection while retaining historical exact
145 and 165 identities. Do not protect unrelated migrations solely by ordinal.
The all-paired-down and malformed-row barriers apply to every protected alias.
The provisional allocation is 165–175 after main's 163 and the independently
owned 164 reservation; remeasure before final source binding. Runner guards
must follow their semantics: tie/backfill 165→167, grant barrier 169→171,
owner-scope barrier 170→172, notice issuance 173→175. Preserve all SQL bytes.
Those runner changes require a fresh full-runner source review and hash pin.
