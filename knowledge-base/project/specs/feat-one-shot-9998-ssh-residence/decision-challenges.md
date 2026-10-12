# Decision Challenges — feat-one-shot-9998-ssh-residence (#9998)

Decisions recorded during `soleur:plan` (headless one-shot pipeline, no Agent/Task
tool available — technical rulings are `pending - assumed` per
`technical-ruling-delegation.md`; `soleur:ship` renders this table into the PR body
and files unresolved rows as `action-required` issues).

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| Unified `fleet_elsewhere` arm replacing `w2_elsewhere` vs an additive `w1_elsewhere` arm alongside it | technical | pending - assumed: unified `fleet_elsewhere` — one property, one arm, one fail message retaining the `outside server.tf` literal both G2-18 and G2-19..21 anchor on; an additive arm would split the same property across two checks |
| Residence allowance granularity: file-scoped vs (file, resource)-scoped | technical | pending - assumed: (file, resource)-scoped — a file blanket lets a second phantom `terraform_data` hide inside an allowlisted file (the second-member class the Guard Contract exists to catch); cost is one enclosing-resource resolution in the G2 walker |
| Coverage scope: textual `hcloud_server.web["web-N"]` dial vs indirect host spellings (`var.web_hosts`, `local.*`, module outputs, literal IPs) | technical | pending - assumed: textual dials only, matching the existing `dials_web_1`/`dials_web_2` vocabulary; indirect spellings are a named residual gap in the plan's Technical Considerations with the issue's re-evaluation trigger carried forward |
| Stale-allowance arm included in the fix | technical | pending - assumed: included — an `EXT_RESIDENCE` entry that outlives its resource is the "claim that silently outlives the set it described" defect the guard's own header names; the arm plus battery row G2-22 make it a finding |
| `EXT_RESIDENCE` keyed on `terraform_data` only vs any resource type carrying a `connection` block | technical | pending - assumed: keyed on whatever resource type the walker resolves — seeded entries are all `terraform_data`, but the residence question is about the connection block, so an undeclared external dialer reds regardless of resource type |
| Agent-spawn steps (research fan-out, spec-flow analyzer, scoped advisor, plan-review panel, domain leaders, CTO ruling on the forks above) | technical | pending - assumed: all performed inline by the planning agent; no Agent/Task tool exists in this runtime — findings were gathered by direct file reads/greps and recorded in the plan's Research Insights |
