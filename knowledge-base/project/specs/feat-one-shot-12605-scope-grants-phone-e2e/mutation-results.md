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

## Addendum — 2026-11-25 (review, #12605)

The review panel predicted false greens. Each was first run against `4c78ef788c`, where the spec PASSED with the
defect present. The fix commit `41a985ff0e` was then run with the same command, one row at a time. The rows above
that touch changed code (3, 5, 11, 12, 13) were re-run against `41a985ff0e`. The unmutated spec passes 2 of 2,
and `settings-kb-sync-held.e2e.ts` still passes 16 of 16 with the changed mock.

| # | Mutation | At `4c78ef788c` | At `41a985ff0e` | Failing check |
|---|---|---|---|---|
| 16 | Remove the ON block from the DOM before measuring | GREEN (false) | RED | ON block is visible |
| 17 | `w-[320px]` on the toggle's label, pushing the switch to x=393 | GREEN (false) | RED | switch right edge, both tests |
| 18 | `h-0 overflow-hidden` on the callout's `GH_DISCLOSURE` | GREEN (false) | RED | visible-paragraph check |
| 19 | Callout's `GH_DISCLOSURE` inside a `hidden md:inline` span | GREEN (false) | RED | visible-paragraph check |
| 20 | The unknown recording notice never renders | GREEN (false) | RED | unknown notice visible |
| 21 | `-mr-12` on the callout, so it escapes the card | not run | RED | callout text right edge vs card |
| 22 | `user_session_state` pointer branch disabled | GREEN | not re-run | none; not load-bearing (ruling R2) |
| 3 | `whitespace-nowrap` on the callout's `GH_DISCLOSURE` | RED | RED | callout text right edge vs card |
| 5 | Fixture membership returns `role: "member"` | RED | RED | enabled switch, both tests |
| 11 | Range filter `r.width < 0` | RED | RED | `count > 0` |
| 12 | Short unrelated `<p>` in the callout (must pass) | GREEN | GREEN | none, 2 of 2 pass |
| 13 | `hidden md:block` on the callout's `GH_DISCLOSURE` | RED | RED | visible-paragraph check |

Row 22 stays green by design: without the pointer, the workspace resolver's error fallback lands on the same id.
The mutation no longer applies at its old anchor, because a comment was added there, so it was not re-run.
