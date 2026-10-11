#!/usr/bin/env bash
# Follow-through enrolment wrapper for #9776 (epic #9601): the sweeper directive carries no arguments and honours
# one directive per tracker, so each soak window gets its own script that fixes the window and delegates.
# Retired together with hosted-destroy-ask-window-9776.sh when #9776 closes.
exec bash "$(dirname "${BASH_SOURCE[0]}")/hosted-destroy-ask-window-9776.sh" --window 24h
