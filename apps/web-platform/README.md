# Web Platform

The Soleur Command Center — a Next.js 15 web app that hosts the chat router (`/soleur:go`), KB Concierge sidebar, and the Claude Agent SDK runners.

## Requirements

- **Node.js ≥ 22.3** (`engines.node` in `package.json`). The PDF text extractor lazy-imports `pdfjs-dist@5`, which calls `process.getBuiltinModule()` during module init — that API was added in Node 22.3 / 20.16. The production Dockerfile uses `node:22-slim`, so the floor is pinned to 22.3 to keep contributor and runtime matrices aligned. Node 21.x will fail with `process.getBuiltinModule is not a function` on any code path that exercises the in-process PDF extractor.

## Running locally

From `apps/web-platform`, with Node ≥ 22.3 active and Doppler available:

```bash
doppler run -p soleur -c dev -- npm run dev
```

If port 3000 is bound, set `PORT=3099` (the user may have a parallel dev server running).

## Testing

```bash
./node_modules/.bin/vitest run            # unit + integration suite
./node_modules/.bin/vitest run path/to/file.test.ts
npx tsc --noEmit                          # type-check (covers test files vitest skips)
```

See `test/README.md` for the integration suite's env flags.
