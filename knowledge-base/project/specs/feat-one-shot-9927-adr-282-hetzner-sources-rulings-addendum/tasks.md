# Tasks: ADR-282 second addendum 2026-10-28 (Hetzner sources, CTO and CLO rulings, owner-side asks)

Plan: `knowledge-base/project/plans/2026-10-28-docs-adr-282-hetzner-sources-rulings-addendum-plan.md`
Ref #9927, Ref #10112. No closing keyword. Do not edit the #9927 body; post no comments.

## Phase 1: Read sources (read-only, record the real fetch date)

- 1.1 T&C `https://www.hetzner.com/legal/terms-and-conditions/`: termination, suspension, data after termination; project deletion; delete protection.
- 1.2 Projects documentation: cloud FAQ section "What are Projects and how can I use them" (`https://docs.hetzner.com/cloud/general/faq/`); roles text quoted from the page itself, not from a search summary.
- 1.3 Cloud changelog `https://docs.hetzner.cloud/changelog` (WebFetch with a targeted prompt); else "could not fetch, not measured".
- 1.4 Terraform hcloud provider docs: index "Delete Protection" section, `volume.md`, `server.md`.
- 1.5 Terraform hcloud provider docs: `docs/resources/` listing for a project resource (absence claim scoped to the listing and date).
- 1.6 Per source and per topic (project deletion, closure or suspension, retention, delete protection): short verbatim quote or "not found in the page read". No cross-source inference.

## Phase 2: Re-verify repo and issue facts

- 2.1 `flag_set` anchor in `apps/web-platform/infra/inngest-cutover-flip.sh` and `access = "read/write"` on `doppler_service_token.inngest` in `inngest-host.tf`.
- 2.2 `gh issue view <n> --json title,state` for 6890, 8528, 7671, 11265, 11266, 9927, 10112 (titles only).
- 2.3 #9927 body item 1b text and the 2026-10-15 triage comment rows 1 and 3 (read-only; print only what is needed).

## Phase 3: Write

- 3.1 Append `## Addendum - 2026-10-28 (#9927), second` to ADR-282: source table, result paragraph with claim limits, `Ruled by CTO agent, 2026-10-28:` paragraph, CLO draft ruling (v1 internal attestation, not legal advice) with seven build conditions and six unanswered facts, owner-side follow-ups (capture checklist, support question text verbatim), not started.

## Phase 4: Local checks (CI is the gate)

- 4.1 `bash scripts/markdown-lint.sh <ADR>` (or state the refusal).
- 4.2 `bash scripts/check-adr-ordinals.sh`.
- 4.3 `bash plugins/soleur/test/sole-copy-drift-check.test.sh`.
- 4.4 `bash apps/web-platform/infra/inngest-redis-luks-import-rehearsal.test.sh`.
- 4.5 Append-only proof (0 removed lines vs origin/main), only ADR + plan/spec files changed, leak check on added lines.

## Phase 5: Ship

- 5.1 PR #11434 body: Measured / Not measured with dates; support question text and capture checklist for the owner; `Ref #9927`, `Ref #10112`; no closing keyword; #9927 stays open.
