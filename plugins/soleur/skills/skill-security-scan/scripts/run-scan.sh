#!/usr/bin/env bash
set -euo pipefail
# TODO Phase 3: orchestrate 5 category scripts in parallel via xargs -P 5,
# aggregate verdict (max-severity wins), emit markdown findings + mandatory
# disclaimer footer, write .scan-meta.json with PII redaction.
echo '{"verdict":"REVIEW","findings":[],"category":"unimplemented","reason":"run-scan.sh stub"}'
