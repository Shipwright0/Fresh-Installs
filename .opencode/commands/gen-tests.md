---
description: Generate tests for specified source files
---

Generate comprehensive tests for: $ARGUMENTS

Follow the testing conventions in AGENTS.md.
Tests go in `tests/` mirroring the `src/` directory structure.
Cover: happy path, error cases, edge cases, boundary conditions.
Use Vitest globals and supertest for HTTP assertions.
After writing tests, run `pnpm typecheck` and `pnpm test` to verify.
