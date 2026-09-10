# A1 measurement scaffold — Serena MCP evaluation (2026-09-10)

Committed deliberately. The Headroom evaluation (2026-09-07) recorded as Session
Error #5 that it deleted its own reproduction scaffold on the false reasoning
that "the conclusions are already committed". These scripts carry no transcript
content and are the replay harness for criterion A1.

## What each does

| Script | Role |
|---|---|
| `a1_measure.py` | **v1 — KNOWN BROKEN, kept as the error record.** Classifies only Read/Grep/Glob results. Returns `nav_code = 0.00%` because this repo's agents navigate via the Bash tool (`cat`/`sed`/`grep`), which carries 93.19% of tool-result bytes. Do not use for a figure. |
| `a1_v2.py` | **v1 + Bash command classification.** The corrected instrument. Produced `nav_code = 5.86%`. |
| `a1_bracket.py` | Deliberately over-generous upper bound — counts a navigation result as "code" if ANY code extension appears anywhere in the command. Produced **11.13%**, below the 15% threshold, which is what makes the A1 failure conclusive. |

## Running

```bash
python3 a1_v2.py ~/.claude/projects/-home-jean-git-repositories-jikig-ai-soleur/*.jsonl
python3 a1_bracket.py ~/.claude/projects/-home-jean-git-repositories-jikig-ai-soleur/*.jsonl
```

The corpus is NOT committable (operator paths, session content). A future run is
therefore comparing against a different corpus — the denominator (all
`tool_result` bytes) and the code-extension set are specified in both scripts so
the rebuild stays faithful.

## Validate before trusting

Both instruments were driven against synthesized known-positive AND
known-negative fixtures before their output was believed — that is what exposed
v1's 0.00% as a classifier gap rather than a finding. Rebuild the fixtures from
the brainstorm's Session Errors §3 and confirm the classifier reproduces them
before quoting any number.
