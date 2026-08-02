# Decision challenges — feat-one-shot-7159-doppler-prd-read-token-coverage

Recorded per ADR-084 / `decision-principles.md`. This session ran headless, so nothing was
asked interactively; each entry is surfaced by `/ship` into the PR body and filed as an
`action-required` issue.

Both entries concern **the stated direction, not the chosen credential shape.** The shape —
one read-scoped `doppler_service_token` on the `prd` ROOT config, published as
`DOPPLER_TOKEN_DRIFT` and consumed only by the token-drift step — is implemented exactly as
decided. What is challenged is two consequences the decision comment did not have the
measurements to see.

---

## UC-1 — The checklist's swap is implemented as a union, and the Done-when's token changes

**Class:** User-Challenge (the operator's direction is the default).

**Direction as stated (#7159 decision comment, 2026-08-02):**

> - Point the token-drift step's `DOPPLER_TOKEN` at `secrets.DOPPLER_TOKEN_DRIFT`.
> - Verify: a scheduled run reports `coverage: multi-config`, and the
>   `Close the coverage issue once the fan-out is restored` step auto-closes the recurring
>   `token-drift-coverage` issue.

**Measured 2026-08-02** (ephemeral read credentials, revoked in the same command):

1. A `prd`-ROOT read service token enumerates **exactly one** config.
   `GET /v3/configs?project=soleur` returns 1 with `success: true` — a list silently scoped to
   the credential, not an error. `GET /v3/environments?project=soleur` returns `[]`.
   So the scan's config count equals the number of read credentials supplied.

2. The two configs' key sets are **not in a superset relation in either direction**.
   `prd_terraform` carries `CI_SSH_ACCESS_TOKEN_ID/_SECRET` and 10 `CF_API_TOKEN*` keys;
   `prd` root carries `CF_API_TOKEN_DNS_EDIT`, `CF_API_TOKEN_PURGE` and
   `REGISTRY_PUSH_ACCESS_TOKEN_ID/_SECRET`.

**The two consequences:**

- **A literal swap is a coverage regression.** It drops the `CI_SSH_ACCESS_TOKEN` pair — the
  credential whose staleness produced the 63-hour outage recorded in ADR-154 — from continuous
  scanning. It also pins `configs` at 1 forever, so the Done-when's own threshold (which needs
  at least 2) becomes unreachable. The plan therefore **keeps `DOPPLER_TOKEN` and adds
  `DOPPLER_TOKEN_DRIFT`**. This is the only implementation under which the decision's stated
  verification can pass at all, and it is strictly additive: the chosen credential is used
  exactly as decided, nothing is removed.

- **`multi-config` is retired, so the Done-when names a token that no longer exists.** The same
  issue's "Known follow-up" section says a 2-config scan deriving `multi-config` "would go quiet
  while still missing the fan-out class" — which is exactly what this change would produce.
  The replacement closing condition is **`coverage: at-floor`**: every credential the step was
  configured with enumerated successfully. The recurring `token-drift-coverage` issue **does**
  auto-close, as the checklist intends; the residual 11-config gap is reported as
  `coverage_ratio: 2/13` in the annotation, both ops emails and the issue body, and is owned by
  UC-2 rather than by a channel that can never clear.

**What the operator may want to overturn:** if `at-floor` closing at 2-of-13 is judged too
quiet, the alternative is to keep the coverage issue open until UC-2 lands — at the cost of a
permanently red `priority/p1-high` channel, which the review panel argued trains the operator
to skip the label. The plan takes the closing behaviour the checklist asked for.

---

## UC-2 — A fourth credential shape exists that the option table did not consider

**Class:** User-Challenge.

**Direction as stated:** the option table in #7159 lists three shapes — read token on the `prd`
root, `for_each` token per config, and reuse of `DOPPLER_TOKEN_TF` — and states "there is no
single project-scoped read token to mint."

**What was measured:** true for `doppler_service_token`. But the pinned provider
`DopplerHQ/doppler v1.21.2` (`.terraform.lock.hcl`) also ships `doppler_service_account` and
`doppler_service_account_token`: a workplace identity with project-scoped access, minted in-band
by the provider, needing no credential-entry step, and therefore compliant with
`hr-tf-variable-no-operator-mint-default`. A credential of that class can enumerate every config
in the project, which would deliver both true fan-out coverage and an exact denominator without
a committed inventory file.

**Why the plan does not adopt it:** it is outside the settled decision, and its blast radius (a
project-scoped identity rather than a config-scoped token) is a trade-off only the operator
should make.

**What the plan does instead:** records it in `## Alternative Approaches Considered` and creates
a tracking issue with re-evaluation criteria (`wg-when-deferring-a-capability-create-a`). That
issue is the single owner of the residual gap: the scan reads 2 of 13 configs, and no
`doppler_service_token`-shaped credential can raise that number beyond the count of credentials
supplied. Re-evaluation trigger: the `2/13` ratio reported by the first post-merge scan is judged
insufficient, or a fan-out staleness incident recurs in an unread config.

---

## Not challenged

- The credential shape itself (read-scoped, `prd` root, `access = "read"`).
- The dedicated `DOPPLER_TOKEN_DRIFT` secret consumed only by the token-drift step.
- The absence of `lifecycle.ignore_changes` on `plaintext_value`.
- The `-target=` allow-list additions.
- The accepted trade-off that the credential reads the whole `prd` tree.
