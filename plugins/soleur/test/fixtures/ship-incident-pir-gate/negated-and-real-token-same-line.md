# fix: the tenant API lost its connection pool

## Overview

The pool is sized per production host.

At first this was not an outage, but by noon the tenant API went down for every workspace.
