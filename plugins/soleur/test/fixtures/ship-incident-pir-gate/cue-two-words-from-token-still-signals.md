# fix: surface a stuck release queue

## Overview

We had no idea the deploy was blocked for six hours while production kept serving the
previous build, so this PR adds a queue-depth alert.
