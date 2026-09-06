#!/usr/bin/env bash
set -uo pipefail
T="$(gh auth token)"
printf 'len=%s\n' "${#T}"
