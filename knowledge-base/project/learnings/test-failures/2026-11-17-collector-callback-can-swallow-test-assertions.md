# Collector callbacks can swallow test assertions

## Problem

A synthetic late-cursor test put its write-fence assertion inside a collector
callback. The collector converted callback exceptions into its expected failed
inspection, so a broken guard could leave the test green. The initial Python
test command also used module discovery on a hyphenated filename and failed to
import; running the file directly invokes the intended fixture.

## Solution

Record the attempted operation, its result and any error inside the callback,
then assert all three after the underlying transaction settles. Force the
guard operation to throw and confirm the outer test fails. Include an active
epoch positive control so an implementation that rejects every write fails.
Run a hyphenated Python test filename directly rather than passing it as a
module name to `python -m unittest`.
The disposable PostgreSQL harness also requires a locally present
`postgres:17-alpine` image and deliberately refuses to pull one itself. If
image inspection reports it missing, restore the test image before rerunning;
do not mistake a fixture setup error for a passing collector test.

## Limits

A disposable synthetic SQLite guard exercises only its tested ordering. It
does not prove a live authority, backend termination, or a production vault
fence. Fixture timing observations also need enough budget for startup and an
explicit check that the database operation is still active after the deadline.

## Tags
category: test-failures
module: holder-evidence-collector
