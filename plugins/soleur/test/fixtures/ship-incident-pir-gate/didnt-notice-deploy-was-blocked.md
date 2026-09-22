# fix: surface a stuck release queue

## Overview

Users didn't notice the deploy was blocked for six hours while production kept serving
the previous build, so the operator only learned of it from the queue depth.
