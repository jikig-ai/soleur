# Pre-merge live baseline — the two frozen rules (#8451)

Read-only `GET /api/0/organizations/jikigai-eu/workflows/<id>/` on 2026-09-21,
token `SENTRY_IAC_AUTH_TOKEN` from Doppler `soleur/prd_terraform` (on stdin, never
argv). Both equal the committed capture
`knowledge-base/project/specs/fix-7650-sentry-alert-migration/phase34-live-workflows-capture-2026-09-09.json`
field for field.

| id | name | enabled | dateUpdated | detectorIds | frequency | trigger | action |
|---|---|---|---|---|---|---|---|
| 566671 | auth-per-user-loop | true | 2026-06-02T07:32:05.293784Z | ["1213799"] | 30 | event_unique_user_frequency_count {value 3, interval 5m} | email issue_owners / ActiveMembers |
| 669246 | sandbox-startup-failure | true | 2026-07-15T17:22:05.816546Z | ["1213799"] | 22 | event_unique_user_frequency_count {value 2, interval 1h} | email issue_owners / ActiveMembers |

Post-merge: re-read both. An unchanged `dateUpdated` is evidence the apply wrote
nothing to them. A moved `dateUpdated` with every compared field still equal to
the capture is NOT a reason to write (Sentry can bump it); restore only when a
compared field differs (see the plan's post-merge ACs).
