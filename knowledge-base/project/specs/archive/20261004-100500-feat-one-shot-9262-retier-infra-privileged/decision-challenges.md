# Decision challenges — feat-one-shot-9262-retier-infra-privileged

Headless planning (one-shot). Taste and user-challenge decisions are recorded here for `ship` to
render into the PR body and file as an `action-required` issue. The recorded direction is the
default in every row; nothing here was applied against it.

## DC-1 — Pin-bump identity: `soleur-infra[bot]` (α, adopted) vs keep `soleur-ai[bot]` (β)

- **Class:** taste (with a scope-boundary question).
- **Adopted:** α — mint as the dedicated `soleur-infra` App from the Tier-B project; the pin bump
  authors as `soleur-infra[bot]`; `soleur-infra[bot]` is added to the CLA allowlist and its pin test.
  This is the direction the #8209 plan (Phase 4 item 4) and the C4 pin-bump edge already record; the
  CTO pass concurred ("β only moves the problem to a new place").
- **Alternative β:** generate a fresh `soleur-ai` private key into `soleur-infra-privileged/prd`
  under new names; no identity, script, CLA or `web-platform-release` side effect. Cost: a key of an
  App installed org-wide and on two outside installations stays in CI (#8209 DC-4 marked this shape
  non-recommended), and O13's two-key fingerprint step (U2) becomes three-key.
- **Why it is surfaced:** the operator placed "the legal cluster" out of scope. The CLA allowlist
  edit is legal-adjacent (CLO: no blocker; evidence recorded automatically). If the operator reads
  the allowlist edit as inside the legal cluster, β is the fallback, and switching costs: revert the
  bump-script identity rows, the CLA two-file edit, and add a new operator step to mint the key.

## DC-2 — Build dispatch credential: infra App token (adopted) vs the mint job's `GITHUB_TOKEN`

- **Class:** taste (operator direction is the default).
- **Adopted:** the `soleur-infra` App token scoped to `actions:write`, as ADR-232 §8 records the
  operator's direction ("names the App token", ADR-232 DC1).
- **Alternative:** give the mint job `actions: write` and dispatch with `GITHUB_TOKEN`
  (`workflow_dispatch` is exempt from event suppression). The mint job would then hold no Tier-B
  credential at all, and the infra App would not need `actions:write`. Revisit if the operator
  prefers the smaller App grant over the App-token audit trail.
- **Plan review (code-simplicity) recommended adopting the alternative** as mechanical: it removes
  the mint job's Doppler verify, App step and `environment:` binding, `actions:write` from the
  manifest, O4c and the ADR-241 D5 amendment, and the "first real mint is the first live exercise of
  `actions:write`" risk. Classified **User-Challenge** (it changes the operator's recorded direction
  and #9262's stated scope, which names this job for re-tiering), so it is surfaced here rather than
  applied.

## DC-3 — Split `Decide` into an environment-less job (not adopted)

- **Class:** taste (CTO low-priority concern 3).
- **Today (adopted):** the `mint` job carries `environment: infra-privileged` for its whole run, so
  every carrier-path push to `main` is admitted to the environment and creates a deployment record,
  even when `Decide` returns `noop` and no credential step runs.
- **Alternative:** a `decide` job with no environment feeding a `mint` job that holds the
  environment and runs only on `would-mint`. Fewer environment admissions and the Tier-B secret is
  materialized only when needed; P6 (credentials before `Create tag`) still holds. Not adopted:
  `test-mint-inngest-bootstrap-tag.sh` pins the single-job shape and step order in detail, and the
  noise is the same one every push-apply job on `infra-privileged` already produces.

## DC-4 — Rename the mint composite to `mint-infra-app-token` (adopted)

- **Class:** taste.
- **Adopted:** rename, and make it Tier-B-only (one identity, one source, mandatory scoping). A
  composite named `mint-soleur-ai-app-token` minting the `soleur-infra` App is misleading on a
  security path; the C4 edge, ADR-232 and runbooks are edited in this PR anyway.
- **Alternative:** keep the path and add a closed `app:` enum. Rejected after the advisor consult:
  the legacy arm would have no consumer and would exist only to hold census G4e's floor.

## DC-5 — Step-scoping of `DOPPLER_TOKEN_INFRA_PRIVILEGED` as a guard (cut) vs as a rule (kept)

- **Class:** taste (reviewers disagree).
- **Adopted:** a written rule — the token appears only in the verify step's `env:` and the mint
  composite's `with:`, never job- or workflow-level `env:` or `$GITHUB_ENV` — with the exact-dict
  rows pinning those two steps, but no dedicated absence-guard rows.
- **For a guard (CTO):** the token reads the whole Tier-B project (read/write Hetzner, R2 state keys,
  write tokens), and the bump job handles outside data (registry labels); a guard keeps a future edit
  from widening its exposure inside the job.
- **Against (code-simplicity, adopted):** no P1-P7 property asks for it; every step is `main`-only
  code on a main-only environment; every other Tier-B job's loader already writes all Tier-B keys to
  `$GITHUB_ENV`, so a guard here would hold these two jobs to a stricter standard than the repo
  applies anywhere else. The structural fix is the narrower Doppler source (a Deferral in the plan).

## DC-6 — Arm pin-bump auto-merge only for the auto-mint's own dispatches (not adopted)

- **Class:** taste (security review P1, deferred with the build-job supply-chain issue).
- **Today (kept):** any `main` dispatch of the build (by any repo writer) reaches the Tier-B bump job
  (`infra-privileged` has no reviewers) and may arm auto-merge when the provenance checks pass. This PR
  only withholds auto-merge for `mirror_only` runs.
- **Alternative:** arm auto-merge only when `github.triggering_actor` is the auto-mint App, so a
  human re-publish always needs a manual merge. Tighter, but changes the operator's re-publish flow;
  belongs with the tracked build-job supply-chain fix.
