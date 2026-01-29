# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Soleur is a Rust project using Edition 2024. The project is in early development with a basic Hello World entry point.

## Build and Development Commands

```bash
# Build
cargo build

# Run
cargo run

# Run tests
cargo test

# Run a single test
cargo test test_name

# Format code
cargo fmt --all

# Lint (with auto-fix)
cargo clippy --fix --allow-dirty --allow-staged -- -D warnings

# Lint (check only)
cargo clippy -- -D warnings

# Security audit
cargo audit

# Run tests with coverage
cargo llvm-cov --lcov --output-path lcov.info
```

## Code Quality

- Pre-commit hooks are managed via lefthook (see `lefthook.yml`)
- Clippy warnings are treated as errors (`-D warnings`)
- Coverage target: 95% for project, 90% for patches
- Test files (`*tests.rs`, `tests/**`) are excluded from coverage metrics

## Browser Automation

Use `agent-browser` for web automation:

1. `agent-browser open <url>` - Navigate to page
2. `agent-browser snapshot -i` - Get interactive elements with refs (@e1, @e2)
3. `agent-browser click @e1` / `fill @e2 "text"` - Interact using refs
4. Re-snapshot after page changes
