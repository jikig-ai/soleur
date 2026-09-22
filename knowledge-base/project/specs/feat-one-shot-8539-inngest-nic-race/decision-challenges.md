# Decision challenges: feat-one-shot-8539-inngest-nic-race

Plan-review taste findings that the headless planning run did NOT apply. The plan's own choice
stands until someone decides otherwise. Recorded for `ship` to render.

## T1: keep the new `inngest_private_ip` template var (code-simplicity #3)

- **Challenge:** drop the var. Hardcode `10.0.1.40` at the call site, as the existing `net-health`
  diag does, and add one test assert that the literal equals `local.inngest_private_ip`. That
  saves four render-site edits.
- **Plan's choice:** keep the var. ADR-115 makes single-sourcing the private IP "part of the
  decision, not an implementation detail". A var gives one definition by construction; a test
  gives it only by check. The ripple is four stub maps, each a one-line addition.
- **Cost of being wrong:** four extra one-line edits and one AC.

## T2: keep `networkctl reload` as its own early runcmd item (code-simplicity #4)

- **Challenge:** move the reload into the helper's first line, which removes one runcmd item and
  two Guard 1 rows.
- **Plan's choice:** keep it separate and early. The reload is what makes the fallback live for
  the rest of the boot, whether or not the helper runs. The helper stays a pure reporter that
  writes nothing and reloads nothing, which keeps its "never mutates network state" contract
  checkable from the stub call log.
- **Cost of being wrong:** one runcmd item and two guard rows.

## T3: keep the harness rows and the token-vs-construct row (DHH #5, code-simplicity #5)

- **Challenge:** drop the harness rows, Guard 1 rows 4, 8 and 10, and the must-PASS inputs.
- **Plan's choice:** keep them. The plan skill's Guard Contract gate (Phase 2.12) requires both a
  second-member row and harness rows. Row 10 is the bare-token-grep class this repo has shipped
  before (`2026-07-19-my-own-mutation-battery-was-the-false-confidence.md`). Row 8 is the census
  principle from the sharp-edges catalogue. It was fixed to exclude the call's own `10.0.1.40`,
  per DHH #1.
- **Cost of being wrong:** about six extra mutation rows in an existing battery.

## T4: the `Spec lacks valid lane:` line in the plan body (DHH #8)

- **Challenge:** delete it as pipeline leftover.
- **Plan's choice:** keep it. The plan skill requires this note when no spec carries `lane:`.
