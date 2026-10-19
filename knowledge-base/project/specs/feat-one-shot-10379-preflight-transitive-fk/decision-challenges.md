# Decision Challenges — feat-one-shot-10379-preflight-transitive-fk

| # | Decision | Options | Ruling |
|---|----------|---------|--------|
| 1 | Severity for RESTRICT/NO ACTION FK on a WORM table pointing to an in-cone non-users parent (the #10254 wedge class) | error vs warning | `soleur:engineering:cto` |
| 2 | Census scope: WORM-gated tables only vs all tables | worm-only vs all-tables | `soleur:engineering:cto` |
| 3 | `confdeltype='d'` (SET DEFAULT) grouping: fold into write-firing classes vs separate class vs ignore | fold vs separate vs ignore | `soleur:engineering:cto` |
| 4 | Warn-only vs fail-closed split (allowlist file vs disposition matrix) | matrix (no allowlist) vs allowlist file | Ruled by plan analysis, 2026-10-15: matrix — dormant anchors are all out-of-cone today so they emit warnings only; an allowlist would have suppressed the #10254 signal itself - reviewed diff of literals convention already exists |
| 5 | CODEOWNERS pin for gate script + test | yes vs no | `operator (scope)` |
| 6 | Ride-along: `account-delete.ts` comment fix RESTRICT→NO ACTION for grant_id | include vs defer | Ruled by plan, 2026-10-15: include if uncontested; drop if review contests - zero-blast-radius comment-only fix |
| 7 | Sign-off requirement | cpo+user-impact per `single-user incident` threshold in plan frontmatter | `soleur:product:cpo` |
