---
title: "fixture: YAML-quoted inline discoverability_test.command scalars (#8102, #7548)"
date: 2026-09-25
type: fix
---

# Fixture: quoted inline command scalars

Parity and executed-string corpus for preflight Check 10 (#8102, #7548). Each
Observability section below is ONE case, pure YAML and deliberately UNFENCED:
every section is also a P1 parity fixture, and the P3 row requires parity fixtures
to be Form-A-only (the awk has no Form B to compare). The case ID is the leading
YAML comment line.

Expected values are NOT written here. The test derives them from Bun.YAML (the
pin in .bun-version), except for the named, rule-derived deviations in the
DEVIATIONS map of preflight-discoverability-test.test.ts. Every value is
synthesized. ASCII only: gawk counts characters, mawk counts bytes.

## Observability

# case: DQ1
discoverability_test:
  command: "printf '%s+' \"a b\" c"
  expected_output: "a b+c+"

## Observability

# case: DQ2
discoverability_test:
  command: "printf '%s+' 'a\\b'"
  expected_output: "a\\b+"

## Observability

# case: DQ3
discoverability_test:
  command: "printf '%s+' 'a\\\"b' 'x\\n'"
  expected_output: "ok"

## Observability

# case: SQ1
discoverability_test:
  command: 'printf ''%s+'' ''a b'''
  expected_output: "a b+"

## Observability

# case: NEST
discoverability_test:
  command: "'printf 200'"
  expected_output: "200"

## Observability

# case: PLAIN
discoverability_test:
  command: printf '%s+' \"a\"
  expected_output: "ok"

## Observability

# case: NEG-CROSS-SQ
discoverability_test:
  command: 'printf ''%s+'' \"a\"'
  expected_output: "ok"

## Observability

# case: NEG-CROSS-DQ
discoverability_test:
  command: "printf '%s+' ''"
  expected_output: "ok"

## Observability

# case: NEG-BLOCK
discoverability_test:
  command: |
    "printf '%s+' \"a\""
  expected_output: "ok"

## Observability

# case: NEG-FOLD
discoverability_test:
  command: >-
    "printf '%s+' \"a\""
  expected_output: "ok"

## Observability

# case: NEG-LF
discoverability_test:
  command: "printf 'ok\n'"
  expected_output: "ok"

## Observability

# case: NEG-MISMATCH
discoverability_test:
  command: "printf \"x\"'
  expected_output: "ok"

## Observability

# case: NEG-EMPTY
discoverability_test:
  command: ""
  expected_output: "200"

## Observability

# case: COMMENT-TAIL
discoverability_test:
  command: "printf '%s+' a" # tail "b"
  expected_output: "a+"

## Observability

# case: NEG-UNTERMINATED
discoverability_test:
  command: "printf abc\"
  expected_output: "ok"

## Observability

# case: NEG-HASH-NOSPACE
discoverability_test:
  command: "printf a"#b
  expected_output: "ok"

## Observability

# case: TRAIL-WS
discoverability_test:
  command: "printf a" 	
  expected_output: "a"

## Observability

# case: SQ-EMPTY
discoverability_test:
  command: ''
  expected_output: "200"

## Observability

# case: DQ-BS-CLOSE
discoverability_test:
  command: "printf a\\"
  expected_output: "a"

## Observability

# case: DQ-TAIL-TEXT
discoverability_test:
  command: "printf a" b
  expected_output: "a"

## Observability

# case: HASH-IN-QUOTES
discoverability_test:
  command: "printf 'a #b'"
  expected_output: "a #b"

## Observability

# case: DQ-TAB-KEPT
discoverability_test:
  command: "printf a\tb"
  expected_output: "ok"
