#!/usr/bin/env bash
# wrapper-boundary.sh — canonical inter-boundary prefix grammar (#10248).
#
# Boundary-anchored gates grep for a gated command anchored at a shell chain
# boundary (`(^|&&|\|\||;|\s--\s)` and siblings). That anchor is blind to
# command wrappers: `rtk gh pr merge`, `sudo git commit`, `X=1 gh pr merge`
# all sit between the boundary and the gated command. ONE shared fragment —
# interpolated by every site — replaces ~18 per-site prefix lists so the
# wrapper set cannot silently drift (#10248; same argv-prefix class as PR
# #3689's `with_lock` bypass, learnings
# 2026-05-12-cross-session-lock-lease-bash-primitives.md SE1).
#
# Consumption idiom — insert between the boundary alternation and the gated
# command:
#   (<boundary-alternation>)[[:space:]]*(${SOLEUR_BOUNDARY_PFX:-}[[:space:]]+)*<gated-cmd>
# The `:-` default is load-bearing: several hooks run `set -u`, and an unset
# fragment degrades to pre-fix matching (status quo), never a hard error and
# never a new hole. The required trailing `[[:space:]]+` after each atom is the
# right-edge word boundary: `rtk-foo`, `artk`, `sudox`, `FOO` (no `=`) can never
# partially consume — the wrapper word must be a whole word between the boundary
# and the gated command.
#
# Restatement pin: the rtk atom below restates exec-subcommand and global-flag
# rows of lib/ext-filter-grammar.tsv (the argv[0]-unwrap class's canonical
# grammar, #10230); test/rtk-grammar-parity.test.sh asserts set equality by
# extraction — edit the TSV and this atom together. The atom admits ONLY inert
# grammar words (counted-verbose globals, --skip-env, the six exec subcommands);
# a string-payload flag (-c|--command|--shell) is NOT an atom, so
# `rtk run -c 'gh pr merge'` stops the prefix at `run` and cannot match — the
# opaque-payload class joins the pre-existing `bash -c '…'` lexical limit every
# boundary gate already declares (#10248 CTO ruling, decision-challenges row 2).

SOLEUR_ENV_ASN_RE='[A-Za-z_][A-Za-z_0-9]*=[^[:space:]]+'
SOLEUR_LAUNCHER_RE='(sudo|command|nice|env|xargs)'
# Globals: -v/-vv/-vvv/--verbose (counted) and --skip-env (takes an optional
# =value — the argv[0]-unwrap SUT accepts both spellings). Exec subcommands:
# run|err|test|proxy|bypass|summary (canonical TSV, class=exec).
SOLEUR_RTK_RE='rtk([[:space:]]+(-v|-vv|-vvv|--verbose|--skip-env(=[^[:space:]]+)?|run|err|test|proxy|bypass|summary))*'
SOLEUR_BOUNDARY_PFX="(${SOLEUR_ENV_ASN_RE}|${SOLEUR_LAUNCHER_RE}|${SOLEUR_RTK_RE})"

# Load sentinel — suites assert this, never `[[ -n "$SOLEUR_BOUNDARY_PFX" ]]`,
# which an inherited environment value would satisfy even after a failed source.
SOLEUR_BOUNDARY_PFX_LOADED=1
