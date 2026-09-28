# Decision challenges — feat-one-shot-6604-workspaces-plaintext-wipe

Plan: `knowledge-base/project/plans/2026-09-28-feat-workspaces-plaintext-volume-wipe-plan.md`.
Headless plan run: each Taste / User-Challenge finding is recorded here instead of being asked.

## User-Challenge (sequencing): Terraform convergence and the ADR flip land in a second PR, after the dispatch

**Finding.** The brief asks for one merged PR, then the wipe, then closing #6604/#6588, and lists the
`for_each` narrowing and the ADR-119 flip in the same scope. Terraform (reproduced on 1.10.5) will not
accept the narrowing before the volume is deleted and its state forgotten, and the soak sweeper closes
#6604 the moment ADR-119 reads `accepted`.

**Chosen.** PR A (the mode) merges first; the dispatch runs on the operator's go-ahead; PR B (the
narrowing, ledger, ADR flip, legal-register sweep) follows the same day. The brief's own words ("after
the API delete") already point this way; this records the second PR explicitly.

**Re-evaluate when:** never for this volume; a future retirement can pre-plan the same two-PR shape.

## Taste (plan-review, DHH vs code-simplicity/CTO): pause the push-apply workflows instead of a create-guard

**Finding.** Between the delete and PR B, every push apply would plan `+create` of a fresh plaintext
volume. A new destroy-guard surface would reverse #6919/T55 and needs an edit to a file 725 bytes under
its size cap.

**Chosen.** `gh workflow disable` both push-apply workflows for the window (named in the go-ahead),
re-enable and `manual-rerun` after PR B. Cost: infra merges in the window stay unapplied until the
rerun, and the dispatched apply arms are unavailable.

**Re-evaluate when:** the window cannot be kept to hours, or a second retirement needs the same window.

## Taste (CTO devex): who clicks the environment approval

**Finding.** The environment's only reviewer is the operator's GitHub user, which the agent's `gh` also
authenticates as; the git-data runbook has agents approve via `pending_deployments`.

**Chosen (default).** The operator clicks it, or explicitly delegates it in the go-ahead; a delegated
agent checks the preflight banner's id, name, server and `api_state` against the pin first.

**Re-evaluate when:** the environment gains a second reviewer or a self-review restriction.

## Taste (CTO devex vs DHH/simplicity): duplicate the SSH delivery block rather than extract it

**Finding.** The `wipe` job copies `cutover`'s bridge/bundle/`.env`/run block, so the rehearsal does not
exercise the copy.

**Chosen.** Duplicate; keep the freeze path byte-stable; state the gap in the ADR addendum.

**Re-evaluate when:** a third job needs the same delivery, or the freeze path is retired.

## Taste (DHH): destruction record as a PR-A template, C4 edge in PR A

**Finding.** Both could be written once, in PR B.

**Chosen.** Keep both in PR A: the CLO's Art. 5(2) precedent makes the template a precondition of the
act, and the C4 edge describes a capability PR A ships.

**Re-evaluate when:** no.

## Taste (CTO devex): the `wipe` job remains after PR B

**Finding.** After PR B the mode has no target on web-1.

**Chosen.** PR B deletes the forget workflow (its addresses no longer exist) but keeps the `wipe` job
and script mode: its refusals protect the rollback path, and #6931 may retire web-2's plaintext volume
the same way.

**Re-evaluate when:** #6931 decides web-2's path.
