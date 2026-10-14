#!/usr/bin/env bash
DRIFT_TEST_PARTS=AB exec bash "$(dirname "$0")/prod-version-drift-check.test.sh"
