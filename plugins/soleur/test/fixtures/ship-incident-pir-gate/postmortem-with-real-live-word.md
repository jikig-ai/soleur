# Post-mortem — the checkout page served a stale price for one hour

Synthesized fixture. The positive half of the `live` pair: the standalone word is
the only member of the alternation present, so guarding the substrings must not
also delete the token itself.

## What happened

The pricing table went live with a cached value that had already been superseded.
For about an hour the page quoted the old figure.

## Impact

Every session in that window saw the wrong number. No charge was taken at the
stale price; the checkout call re-read the authoritative value before charging.
