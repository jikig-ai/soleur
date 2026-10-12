#!/usr/bin/env bash
# Follow-through enrolment wrapper for #9776 (epic #9601): the sweeper directive carries no arguments and honours
# one directive per tracker, so each soak window gets its own script that fixes the window and delegates.
# Retired together with hosted-destroy-ask-window-9776.sh by the flip PR (ADR-284 'Flip checklist').
exec bash "$(dirname "${BASH_SOURCE[0]}")/hosted-destroy-ask-window-9776.sh" --window 7d
