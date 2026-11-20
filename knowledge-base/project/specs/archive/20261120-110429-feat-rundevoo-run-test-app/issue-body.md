Purchase `rundevoo.run` (available, ~$21.20/yr at Cloudflare Registrar) as the domain for a future Jikigai product that phase 1 treats as a test app Soleur runs against. Product shape is intentionally undecided — a later brainstorm owns it.

## Scope (phase 1: domain + safe DNS only)

- Operator purchases `rundevoo.run` at Cloudflare Registrar as **Jikigai SARL**, 1-year term, auto-renew ON, org registrant email, WHOIS privacy on (operator-only: payment entry).
- New Terraform root `infra/rundevoo-run/` (R2 `soleur-terraform-state` backend) — NOT inside `apps/web-platform/infra` (a new no-default var wedges the prod merge-apply).
- Import the auto-created `cloudflare_zone`; mint a zone-scoped `Zone:DNS:Edit` token via the bootstrap ephemeral-admin pattern.
- Mail-spoof hardening: null MX (RFC 7505), `v=spf1 -all`, DMARC `p=reject`, DNSSEC on.
- Apply workflow (apply-sentry-infra.yml precedent) + `scheduled-terraform-drift.yml` matrix leg + destroy-guard triple + `encryption-posture-ledger.json` `non_store_types` entry for `cloudflare_zone`.
- Ledger rows: `domains.md` + `expenses.md` (Recurring + One-Time); Article 30 register dated amendment/PA.

## Acceptance criteria

- [ ] Domain purchased and auto-renew enabled; registrant entity is Jikigai SARL.
<!-- lint-infra-ignore start: describes the workflow-driven apply's acceptance property ("zero operator steps" — the apply runs through apply-rundevoo-infra.yml, never a human) -->
- [ ] `terraform apply` on `infra/rundevoo-run/` from empty state reproduces the zone import + hardening records with zero operator steps.
<!-- lint-infra-ignore end -->
- [ ] `dig MX rundevoo.run` returns null MX; TXT shows `v=spf1 -all` and DMARC `p=reject`; DNSSEC enabled.
- [ ] Drift-detection matrix includes the new root; destroy-guard, counter test, CODEOWNERS rows present; `lint-encryption-posture.py` green.
- [ ] `domains.md` and `expenses.md` rows added; Art. 30 register entry recorded.

User-Impact: email sent as @rundevoo.run and any future page served on the domain — an unhardened company-owned domain is spoofable (phishing email) or can serve arbitrary content to third parties attributable to Jikigai SARL; a single-user-incident brand risk.
Fix-Size: 250 lines / 10 files (1 new TF root + apply-workflow + drift-matrix leg + destroy-guard triple + 2 ledger rows).

## Artifacts

- Brainstorm: `knowledge-base/project/brainstorms/2026-11-19-rundevoo-run-test-app-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-rundevoo-run-test-app/spec.md`
- Branch: `feat-rundevoo-run-test-app`
- Draft PR: https://github.com/jikig-ai/soleur/pull/12968

## Non-goals (deferred)

- Product shape decision (dev tool / content / API), app repo placement, hosting substrate, access posture, legal pages — follow-up brainstorm once the operator decides.
- Placeholder site, app scaffold, deploy loop — none in phase 1.
