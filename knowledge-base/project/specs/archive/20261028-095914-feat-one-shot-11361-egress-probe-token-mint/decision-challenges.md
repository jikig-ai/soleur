---
title: "Decision challenges — feat-one-shot-11361-egress-probe-token-mint"
branch: feat-one-shot-11361-egress-probe-token-mint
issue: 11361
---

# Decision Challenges

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| Test design for the mint-content pin | technical | Ruled by CTO agent, 2026-10-27: the docker stub's --proxy arm replicates the helper auth contract (file content == presented user at CONNECT time) plus static syntax pins and a helper-contract anchor pin — a static grep alone is the mock-green shape that shipped the defect; behavioral replication is the only layer that would have caught it |
| Byte-parity content (printf 'probe', no newline) vs helper tolerance | technical | Ruled by CTO agent, 2026-10-27: byte-parity with the sibling per the issue — deliberately stricter than the helper's $(<file) newline tolerance so any drift is a visible deliberate change |
| Shared mint helper or GW_USER variable extraction | technical | Ruled by CTO agent, 2026-10-27: rejected (YAGNI) — two call sites, a one-line contract; extraction adds a third delivered artifact plus delivery-lockstep surface for a constant, and the test pin binds the contract |
| Auth check in the stub's deny arm | technical | Ruled by CTO agent, 2026-10-27: rejected — 407 and 403 both yield rc != 0, an identical verdict shape; the deny leg's discrimination (rc == 0 means bypassed) needs no auth modeling |
| Follow-through enrollment scope | technical | Ruled by CTO agent, 2026-10-27: include scripts/followthroughs/egress-enforce-probe-11361.sh — the defect shipped mock-green and failed on its first real run, so the close criterion is inherently post-deploy and plan gate 2.9.1 requires the enrollment; sweeper secrets already wired |
