# plan: document the matcher used by the enrollment gate

## What the matcher looks like

The gate's own expression is quoted below as data. A plan that documents a
matcher is not a plan that declares a close criterion.

```bash
SOAK_RE='soak|stays? (at )?(~?0|zero)|post-deploy (soak|verif|observ)'
# a 7-day post-deploy soak is what this alternative is for
```

Nothing here is a claim about this change.
