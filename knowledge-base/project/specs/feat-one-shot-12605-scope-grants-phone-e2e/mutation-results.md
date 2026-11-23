# Mutation results: phone-width e2e for the Scope Grants web-egress disclosures

Run locally against commit `9f5edcfc29` on 2026-11-23, one row at a time, from `apps/web-platform`, with
`CI=1 playwright test e2e/nav-states-scope-grants-web-egress.e2e.ts --project=authenticated --retries=0`.
Each mutation was a temporary edit restored with `git restore`. The unmutated spec passes 2 of 2.

| # | Mutation | Expected | Observed | Failing check |
|---|---|---|---|---|
| 1 | Merge both disclosures into one `<p>` in the dialog | RED | RED | render count |
| 2 | Remove the mock's `/auth/v1/verify` branch | RED | RED | ON test `aria-checked` |
| 3 | `whitespace-nowrap` on the callout's `GH_DISCLOSURE` | RED | RED | `expectFitsPhone` right edge |
| 4 | `whitespace-nowrap` on the ON block's `PUSH_DISCLOSURE` | RED | RED | `expectFitsPhone` right edge |
| 5 | Fixture membership returns `role: "member"` | RED | RED | enabled switch, both tests |
| 6 | Extra `GH_DISCLOSURE` `<p>` inside the section | RED | RED | render count |
| 7 | `PUSH_DISCLOSURE` `<span>` outside the section | RED | RED | render count |
| 8 | Confirm button `fixed -top-24` | RED | RED | `toBeInViewport` |
| 9 | `fixed inset-0 z-50` element over the confirm button | RED | RED | trial click timeout |
| 10 | ON fixture row has `web_egress: false` | RED | RED | ON test `aria-checked` |
| 11 | Range filter `r.width < 0` | RED | RED | `count > 0` |
| 12 | Short unrelated `<p>` in the callout (must pass) | GREEN | GREEN | none, 2 of 2 pass |
| 13 | `hidden md:block` on the callout's `GH_DISCLOSURE` | RED | RED | visible-paragraph check |
| 14 | Dialog `GH_DISCLOSURE` as a `<div>` | RED | RED | visible-paragraph check |
| 15 | `whitespace-nowrap` on the dialog's `GH_DISCLOSURE` | RED | RED | `expectFitsPhone` right edge |

Row 5's first run failed with `ERR_CONNECTION_REFUSED` because the dev server had exited, so it proved nothing. It was
re-run, and the table records the re-run.
