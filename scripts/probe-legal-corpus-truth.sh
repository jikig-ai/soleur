#!/usr/bin/env bash
# Discoverability probe for the CLA-evidence third-country-transfer disclosure (#7624).
#
# Asserts, against BOTH the canonical corpus (docs/legal/) and the published
# mirror (plugins/soleur/docs/pages/legal/), that:
#   POSITIVE  the Chapter V safeguard is still disclosed on all three documents;
#   NEGATIVE  none of the three superseded claims is ASSERTED on either surface.
#
# Why this is a script and not an inline command: preflight Check 10 executes the
# plan's `discoverability_test.command` via `bash -c` inside a bwrap sandbox and
# rejects every shell-active token first -- `;`, `|`, `>`, `&` and `&&` included.
# The original inline probe chained two greps with `&&`, so it was structurally
# unrunnable by the gate it was written for. `bash <script>` is the remedy the
# skill itself prescribes.
#
# Why correction notes are stripped before the negative arm: each corrected bullet
# carries an audit trail of the form `*(Corrected YYYY-MM-DD, ref #NNNN: ... this
# bullet previously described the archive as EU-region with intra-EU processing
# ...)*`, which QUOTES the superseded wording. Grepping the raw text conflates the
# mention with the assertion and reds on a corpus that is in fact correct -- the
# mention-vs-invocation trap. legal-doc-consistency.test.ts avoids the same
# collision only because its literals happen to be case-sensitive and the notes
# quote in lower case; that is an accident, not a design, so this probe removes
# the notes outright and can then match case-insensitively, which is strictly
# stronger.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 2
exec python3 scripts/probe_legal_corpus_truth.py
