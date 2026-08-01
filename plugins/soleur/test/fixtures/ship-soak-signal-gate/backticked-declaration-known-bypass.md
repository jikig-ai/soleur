# plan: a real declaration that hides inside a code span

## Close criteria

The whole criterion was written inside a code span: `closes after a 7-day post-deploy soak`.

This is the accepted residual documented in the script header — the inline-code
strip cannot tell a quoted filename from a quoted claim, and filenames are by
far the commoner case. The bypass is bounded to spans that open and close on
one line, because the strip is line-oriented.
