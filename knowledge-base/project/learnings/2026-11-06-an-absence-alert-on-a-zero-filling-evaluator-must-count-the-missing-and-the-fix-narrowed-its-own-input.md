# Learning: an absence alert on a zero-filling evaluator must count what is missing, and my fixes narrowed their own inputs

## Problem

`soleur-egress-gw-probe-silent-prd` (Better Stack, #12180) opened an incident while both probe hosts were emitting. The
first diagnosis ("the incident is just stale") was incomplete: incident 1031046761 was resolved, then incident
1047829421 opened on healthy data. The alert counted PRESENT hosts and fired on "fewer than N"; an evaluator step that is
zero-filled (INFERRED from the behaviour, never observed in the evaluator) reads 0 present hosts and fires on a healthy
fleet. The same alert shape would also read a fully dark window as "0", which is why `on_missing_data = treat_as_zero`
stays.

## Solution

- Invert the metric to the count of MISSING roster hosts, floored at 0 (`greatest(roster - count(DISTINCT host), 0)`),
  alert on `higher_than 0`: a zero-filled step reads healthy, a dead or dark host still fires. Same Terraform resources,
  update-in-place (the only ForceNew on the alert is `exploration_id`).
- A throwaway canary alert pair (`'egress-gw-probe-canary-absent'` swapped into the production SQL) must fire on a
  synthetic silence. It proves non-zero delivery on an empty count, nothing more. A follow-through probe reads the
  incident list and prints a 10-field verdict line; the cron/heartbeat poller (#12190) is only the fallback.
- Both vendor behaviours the pass path depends on are UNVERIFIED (`resolved_by` null on auto-resolve; the canary incident
  still listed after the alert is deleted), so every ambiguous reading maps to `unknown` (exit 3), never to exit 0.

## Key Insight

Three generalisable shapes surfaced in review, each a fix that re-created its own class:

1. An alert that counts the PRESENT thing is wrong on a zero-filling evaluator; count the ABSENT thing against a roster,
   floor at zero, and keep the missing-data policy that makes a fully dark window visible.
2. A fix to an input guard narrowed the accepted shape: round 2 made `SOLEUR_FT_EARLIEST` ISO-only, silently ignoring the
   date-only spelling 42 trackers use; the verification seat caught it. When tightening a regex, grep the repo's real
   spellings of that input first.
3. A warning placed after a downstream truncation never reaches its reader: the canary's "do NOT close its mirror issue"
   started at char 407 and the incident mirror keeps 300. Front-load it, and measure the cap in the consumer.

## Session Errors

1. **Incomplete first diagnosis ("just stale")** — Recovery: the fresh false positive forced the metric inversion —
   Prevention: before resolving an alert as stale, check whether a SECOND open incident on healthy data can be produced by
   the same query shape.
2. **jq `test(` tripped the probe suite's no-fuzzy-match check** — Recovery: `[match(...)] | length` — Prevention: grep
   the suite's banned-construct list before choosing a jq predicate.
3. **Rows output order change broke one expectation; the single-line count check could not assert one line** — Recovery:
   updated the expectation and asserted per-line verdict/message counts — Prevention: change an output's order only after
   grepping the suite for the old order.
4. **Derived referrer check failed for the ADR file (named by number in the header)** — Recovery: key ADR files by
   `ADR-NNN` — Prevention: a derived check needs a naming rule per file class, not one basename rule.
5. **Guard `mutate_green` rows went red (scan hit logs and other rows' mutated copies; population row dropped under the
   floor)** — Recovery: empty `scan-empty` root for single-file rows, population row that always emits — Prevention: a
   scan over a shared mutation directory must be rooted per row.
6. **PROD_NAME mutation row's expected fragment drifted** — Recovery: re-pinned the fragment — Prevention: pin mutation
   expectations on the guard's failure message constant, not a copy of its text.
7. **Bearer-sweep `EXPECTED_TESTS` stale (831 vs 832) after my own manifest row** — Recovery: set 832 — Prevention: a
   repo-global ratchet cannot be seen by file-selected suites; run the ratchets after adding any suite row.
8. **`rm -rf` hook blocked a combined cd+rm call** — Recovery: separate calls — Prevention: keep deletions in their own
   Bash call.
9. **Prose claims refuted by review: hot window "about an hour" (40 minutes elsewhere), Doppler command that needed no
   mapping (read/write token injected), "postmerge runs the probe" (no skill does), "mirror files a new issue every 15
   minutes" (once per close)** — Recovery: corrected at every site — Prevention: grep the claim's subject repo-wide before
   asserting it; for each causal sentence the diff adds, name the falsifying command.
10. **Fix round 2 narrowed `SOLEUR_FT_EARLIEST` to ISO-with-time, ignoring date-only** — Recovery: widened the regex,
    added two rows — Prevention: enumerate real spellings of an input (`grep -rn 'earliest='`) before tightening it.
11. **`$` in a jq `match` anchors before a trailing newline, letting `host\n` through the host fold** — Recovery: `\z` —
    Prevention: use `\z`, not `$`, in any Oniguruma pattern that guards a one-line output contract.
