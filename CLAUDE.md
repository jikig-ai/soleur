<!-- OPENSPEC:START -->
# OpenSpec Instructions

These instructions are for AI assistants working in this project.

Always open `@/openspec/AGENTS.md` when the request:
- Mentions planning or proposals (words like proposal, spec, change, plan)
- Introduces new capabilities, breaking changes, architecture shifts, or big performance/security work
- Sounds ambiguous and you need the authoritative spec before coding

Use `@/openspec/AGENTS.md` to learn:
- How to create and apply change proposals
- Spec format and conventions
- Project structure and guidelines

Keep this managed block so 'openspec update' can refresh the instructions.

<!-- OPENSPEC:END -->

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working
with code in this repository.

## Build and Test Commands

```bash
# Build the project
cargo build

# Run all tests
cargo test

# Run a specific test
cargo test test_name

# Watch mode (requires cargo-watch: cargo install cargo-watch)
cargo watch -x check -x test

# Code coverage (requires cargo-llvm-cov: cargo install cargo-llvm-cov)
cargo llvm-cov
```

## Architecture Overview

This is a Merkle tree implementation in Rust, used for learning the
language through implementing a data structure widely used in blockchains
like Bitcoin and Ethereum.

### Core Design Patterns

#### Strategy Pattern for Hashing

- The `Hasher` trait (in `src/hasher/mod.rs`) allows pluggable hash
  algorithms
- Two implementations: `Sha256Hasher` (production) and `SimpleHasher`
  (testing)
- Hashers return `[u8; 32]` arrays for performance (raw bytes, not hex
  strings)

#### Domain Separation for Security

- Leaf nodes: H(0x00 || leaf_bytes)
- Internal nodes: H(0x01 || left_hash || right_hash)
- This prevents collision attacks where different tree structures could
  produce the same root

#### Arc-based Tree Structure for Performance

- Nodes use `Arc<Node>` to avoid deep copying during tree construction
- `InternalNode` stores left/right children as `Arc<Node>`
- The `Hash` trait returns `&[u8]` (not owned `String`) to eliminate
  cloning

### Module Organization

```text
src/
├── hasher/          - Pluggable hash algorithms
│   ├── mod.rs       - Hasher trait definition
│   ├── sha256.rs    - Production hasher
│   └── simple.rs    - Test hasher
├── merkle/          - Tree structure
│   ├── mod.rs       - Public API and MerkleTree trait
│   ├── hash.rs      - Hash trait (for types that have a hash)
│   ├── node.rs      - Node enum (Leaf or Internal)
│   ├── leaf_node.rs - Leaf node (contains raw data)
│   ├── internal_node.rs - Internal node (has two children)
│   └── simple_tree.rs   - SimpleMerkleTree implementation
└── lib.rs           - Public API exports
```

### Tree Construction Algorithm

The `SimpleMerkleTree` rebuilds the entire tree on each `add_leaf()` call:

1. Wrap all leaves in `Arc<Node>`
2. For each level:
   - Process nodes in pairs (chunks of 2)
   - If odd number of nodes, duplicate the last node (clone the Arc
     pointer)
   - Create internal nodes from pairs
   - Store in next level
3. Continue until one node remains (the root)

### Performance Considerations

The codebase has been optimized for:

- **Memory efficiency**: Using raw byte arrays `[u8; 32]` instead of hex
  strings
- **Zero-copy hash access**: `Hash` trait returns `&[u8]` references
- **Minimal cloning**: Arc pointers are cloned, not the underlying data
- **Pre-allocated vectors**: `Vec::with_capacity()` used where sizes are
  known

### Invariants

1. Empty data is rejected (returns `MerkleTreeError::EmptyInput`)
2. Odd number of nodes at a level: duplicate the last node
3. A hash is always 32 bytes (`[u8; 32]`)
4. Domain separation prefixes (0x00 for leaves, 0x01 for internal nodes)
   are mandatory

### Build Configuration

The project uses the `mold` linker for faster linking times (configured
in `.cargo/config.toml`). Install with:

```bash
sudo apt-get install clang mold
```

## Claude Code Agents

This project includes specialized agents:

- `blockchain-developer`: Expert in Merkle tree blockchain applications
- `rust-pro`: Advanced Rust programming assistance

And reusable commands:

- `/audit`: Dependency security and update checks
- `/write_tests <target>`: Generate comprehensive test suites

## Browser Automation

Use `agent-browser` for web automation. Run `agent-browser --help` for all commands.

Core workflow:
1. `agent-browser open <url>` - Navigate to page
2. `agent-browser snapshot -i` - Get interactive elements with refs (@e1, @e2)
3. `agent-browser click @e1` / `fill @e2 "text"` - Interact using refs
4. Re-snapshot after page changes
