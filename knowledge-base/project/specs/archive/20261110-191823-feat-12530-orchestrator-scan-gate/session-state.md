# Session state — feat-12530-orchestrator-scan-gate

PANEL_SHA: 2be1fd67086b3ce57e8474398fecc1792c194145
FIX_HEAD: fcc094ffe9a16c3efe2f4252e96ecac34414eab7
Tier: single-user incident (source: plan)
Class: code
Design-risk: yes

## Dedup ledger

| raw finding | canonical defect key | reporting seat(s) | planned fix commit |
|---|---|---|---|
| Forged semgrep stub returned `paths.scanned: []`, so disabling the body-line filter still refused via the empty scan. `*.ts`-only kind filter and a one-file `test/` copy stayed green. | test-predicate-not-property: suite refused for the wrong reason | test-design-reviewer | fcc094ffe9 |
| A zero-finding claim accepted `ok` + `findings=0` without `files` equal to the classified source-and-shell count, so a short path list could receipt a clean subset. | claim-narrower-than-range: clean subset reads as a full scan | user-impact-reviewer | fcc094ffe9 |

dedup: 2 raw → 2 unique

## Fix-round receipt

Measured on the fix range `2be1fd6708..fcc094ffe9` before the round spawned:

`SOLEUR_REVIEW_SCAN_GATE ok engine=shellcheck files=1 rules=0 findings=0`

Classified shell target: `plugins/soleur/skills/review/test/review-scan-gate.test.sh`. The other four paths are markdown.

## Fix round

Status: closed. Verifier PASS.
Mapped seats returned closed: test-design-reviewer, user-impact-reviewer, agent-native-reviewer. Shellcheck seat is the receipt above (no agent file).
Trailers: `66ad88069b` Reviewed-Coverage full 11/11. `83d0a46dac` Reviewed-Fix-Range `2be1fd6708..fcc094ffe9`.
Affected battery: waived. `scripts/test-all.sh --capacity` printed CAPACITY_CONTENDED (sibling `feat-one-shot-12514-claude-code-cli-fable-bump`). CI required `test` is the full battery.

## Settled (do not re-open)

- One stdout receipt. Do not wire `review.workflow.js`. Do not add gitleaks. Do not copy HephaestusNG.
- Historical sharp edges in the review skill stay as history.
- Shellcheck has no agent file. The orchestrator receipt is that seat.
