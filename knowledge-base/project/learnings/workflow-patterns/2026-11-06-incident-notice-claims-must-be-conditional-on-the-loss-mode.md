---
date: 2026-11-06
pr: 12239
category: workflow-patterns
---

# Incident-notice claims must be conditional on the loss mode that produced them

A pre-drafted user notice for a total loss of the Inngest store shipped its first draft with flat claims ("we lost ... the history of those runs", "Run history ... is not available"). The user-impact seat BLOCKED: run history lives in the dedicated Postgres project, which survives in 4 of the 5 loss modes the runbook enumerates — only a project loss destroys it. A volume-only-loss victim would have been wrongly told recoverable history was gone.

Same class twice more in one file: "your account records were not stored there" was falsifiable comfort (payloads carried founderId, email hashes, invoiceIds), and the 23-hour re-approval window was stated unconditionally though it anchors to the original approval, not to notice receipt.

## Prevention

- In any notice/draft/runbook text that describes what was lost, enumerate the modes the artifact covers and mark each claim with the mode(s) it survives as true under — `[IF-<MODE>: ...]` conditionals with a fill-table row naming the deciding fact (here: whether the Postgres project was lost, whether the restore is verified, whether the notice lands inside the 23h window).
- Never write a comfort claim ("X was not stored there") you cannot verify at the granularity asserted — scope to what is verifiably elsewhere ("repositories and knowledge base content"), or drop it.
- A fill-field template needs its own send-gate line: "search the copied block for `[`; any match means a missed field — do not send" — an unfilled placeholder ships as broken text.
