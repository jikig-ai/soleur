---
module: inngest-bound-logger
date: 2026-07-20
problem_type: logic_error
component: web_platform_server
symptoms:
  - "A Proxy get trap that binds methods throws on a frozen logger, and a try/catch inside the trap does not catch it"
  - "Memoising bound methods in a single WeakMap routed one logger instance's calls into another's"
  - "A fail-open guard on the hot path of 65 crons had no signal on any observability layer"
root_cause: fix_for_a_failure_class_reintroduced_the_same_class_on_untested_shapes
severity: high
tags: [proxy-invariants, fail-open, receiver-loss, mutation-testing, middleware, verification-habits]
synced_to: [review, work]
---

# My fix for a crash class reintroduced the crash class — three times

**PR:** #6729 · **Issue:** Ref #6703 · **Builds on:** #6705

## Problem

The bug was receiver loss: inngest's `ProxyLogger.info()` opens `if (!this.enabled) return;`,
so `const f = ctx.logger.info; f(x)` gives strict-mode class code `this === undefined` and
throws `Cannot read properties of undefined (reading 'enabled')`. In #6705 that turned a
*successful* cert-renewal probe into a reported failure.

The fix was to bind every function-valued property at the Inngest middleware boundary — a
`Proxy` whose `get` trap returns `v.bind(target)`. Applied once, it covers all 65 functions.

By every visible signal my implementation was done:

- 14 tests passing, covering all five detachment shapes
- a mutation control (`v.bind(target)` → `v`) that correctly reds the suite
- `tsc --noEmit` clean, full suite 1028 files / 12383 tests green
- SDK claims re-verified against the pinned vendor rather than the plan's quotes

Review found **three ways the fix reintroduced the exact crash class it removes**. Each was
real; each I then reproduced live before fixing.

## What I got wrong

### 1. A Proxy invariant makes `bind` illegal — and `try/catch` cannot save you

For an **own, non-writable, non-configurable data property**, `[[Get]]` requires the trap to
return the target's *exact* value. `bind` returns a different function object, so:

```
TypeError: 'get' on proxy: property 'info' is a read-only and non-configurable
data property on the proxy target but the proxy did not return its actual value
```

`Object.freeze(logger)` is enough to arm it. The throw fires at the log call site inside the
handler, escapes, exhausts retries, fires `onFailure` — the #6705 signature exactly.

The non-obvious part: **the invariant check runs after the trap returns**, so this does not
help:

```js
get(target, prop, receiver) {
  try { const v = Reflect.get(target, prop, receiver);
        return typeof v === "function" ? v.bind(target) : v; }
  catch { /* never reached for this failure */ }
}
```

A reviewer proposed exactly that fix and I nearly took it. It must be **avoided**, not caught:

```js
const own = Reflect.getOwnPropertyDescriptor(target, prop);
if (own && own.writable === false && own.configurable === false) return v; // unbound, by necessity
```

Such a property stays unbound. Not throwing is the guarantee; binding is unavailable at any price.

### 2. `Reflect.get` throws *through* a nested trap

The real `ctx.logger` is itself a Proxy (`ProxyLogger`'s constructor returns one) whose trap
ends `Reflect.get(target.logger, prop, receiver)`. If `logger` is `undefined` — e.g. a pino
`child()` that *returned* undefined, which inngest's own `try/catch` does not guard because it
only catches a throw — any unknown-prop read throws `Reflect.get called on non-object`.
Wrapping a Proxy means inheriting its failure modes.

### 3. Memoising bound methods must key on the *target* first

I added a `WeakMap<fn, bound>` to stabilise identity (`emitter.off(logger.info)` can never
match a freshly-allocated closure). But **class methods live on the shared prototype**:
`ProxyLogger.prototype.info` is one function object for every instance. A cache keyed on the
method alone hands the second logger a method bound to the *first* instance — silently routing
one cron's logs into another's. Verified: `b.who()` returned `"A"`.

The fix is two levels, target first. This is the worst of the three — it would not have thrown,
just quietly mis-attributed logs.

## The meta-lesson: I tested the shapes, not the substrate

My suite covered every way a *caller* can detach a method (extract, destructure, `forEach`,
`setTimeout`, `.catch`). Not one case varied the *logger being wrapped*. All three defects live
there: frozen, nested-proxy, prototype-shared. The mutation battery was green because it only
mutated the code I wrote, against the inputs I imagined — the same failure recorded in
[the 2026-07-19 self-graded-battery learning](2026-07-19-my-mutation-battery-was-green-and-it-only-measured-the-mutations-i-thought-of.md),
one day later, in a different language and layer.

**When wrapping a value you did not construct, enumerate hostile shapes of the value, not just
hostile usages of the wrapper.** For a JS object that means at minimum: frozen/sealed, own vs
prototype properties, already-a-Proxy, callable, getters that throw, and null-prototype.

A related tell: my fake was a plain `class`. The real thing is a **constructor-returned Proxy**,
so the double-Proxy composition my `bind(target)`-vs-`bind(receiver)` comment reasoned about was
never once executed. The real class was importable the whole time (`import { ProxyLogger } from
"inngest"`); I reached for a fake because the deep path `inngest/middleware/logger` is not in
the package's `exports` map, and stopped there instead of trying the root.

## Fail-open and fail-silent are separable — and an exemption's conclusion is not portable

The guard `if (!raw || typeof raw !== "object") return;` must not throw: a throw in
`transformInput` reds every cron on the surface over a logging concern. I cited
`cert-reissue-marker.ts`'s sanctioned "don't mirror to Sentry" exemption to justify staying
*silent* too.

That was borrowing the conclusion without the premise. That exemption is scoped to a `catch`
around an emit that **already failed**, where mirroring would re-enter the broken path. My guard
is an **input-shape check before anything is attempted**, and the mirror target (module-scope
pino → Sentry) is a *disjoint* path from `ctx.logger`. Nothing was broken; nothing would re-enter.

Unreported, that branch reverts all 65 functions to unbound loggers with **no signal on any
layer**: no throw for sentry-correlation, no emit for Vector, and run-log records the run
`completed`. A fleet-wide regression shaped exactly like health.

It now mirrors via `warnSilentFallback`, deduped once per process, inside a `try/catch` — and
*that* catch is the one place the cert-reissue-marker exemption genuinely applies.

Two smaller instances of the same "check the premise" failure in one PR: the guard also rejected
`typeof raw === "function"`, failing open against callable loggers (debug/npmlog/roarr) that are
perfectly wrappable; and the plan's `## Observability` and `## User-Brand Impact` blocks still
described the *rejected* type-only design ("zero runtime emission", worst case "a `tsc` failure
that blocks CI") while what shipped runs a `get` trap on every property access of every logger
call across 65 crons.

## Rules of thumb

- **Proxy `get` traps must respect invariants, not catch them.** Non-writable + non-configurable
  own data properties must be returned as-is. Check the descriptor; a `try/catch` in the trap is
  the wrong tool and creates false confidence.
- **Wrapping a Proxy inherits its failure modes.** Guard `Reflect.get` itself.
- **Memoise per (target, method), never per method.** Prototype methods are shared; a
  single-level cache mis-binds silently.
- **Vary the wrapped value, not only the calling convention.** Frozen, callable, already-proxied,
  prototype-shared, null-prototype.
- **Import the real vendor class in tests when it is exported.** A hand-written class fake cannot
  reproduce a constructor-returned Proxy. If a deep subpath does not resolve, try the package root
  before writing a fake.
- **Fail-open never implies fail-silent.** Ask separately: must this not throw? must this not
  report? The second answer is almost always "it must report."
- **An exemption travels with its premise.** Before citing one, restate the premise and check it
  holds for your shape.
- **When a design pivots mid-plan, re-read the plan's impact sections.** They were written against
  the design you abandoned.
