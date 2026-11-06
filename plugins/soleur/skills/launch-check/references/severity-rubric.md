# Severity rubric

| Severity | Meaning | Who may assign it |
|---|---|---|
| critical | A credential or credential-bearing file is committed. Fix before anything else. | Deterministic checks only (SEC-01, SEC-02). |
| high | A launch blocker for real customers: no tests, no CI, no CI test run, or an AI-reviewed concern with named evidence. | A catalog row, or the AI review for JDG- rows. |
| medium | A gap that raises the cost of an incident or a handover. | A catalog row, or the AI review. |
| low | Hygiene. Worth doing, not worth delaying a launch. | A catalog row, or the AI review. |

The AI-assisted review (JDG- rows) may only choose high, medium or low, must cite the ids of the deterministic facts it relied on, and cannot add free text: its title and remedy come from `checks.tsv`.
