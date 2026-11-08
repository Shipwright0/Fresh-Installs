---
description: Become familiar with the project directory you are in
---

Use the following tools to explore and understand the repository structure as a first step:

## Directory Structure
- `glob` with pattern `**/*` to list all files and directories
- `glob` with pattern `**/*.{ts,js,json,md}` to find source files
- `read` on key directories like `src/`, `tests/`, `.opencode/` to understand layout

## Key Files to Examine
- `package.json` - dependencies, scripts, project metadata
- `tsconfig.json` - TypeScript configuration
- `SPEC.md` - project specification and acceptance criteria
- `ROADMAP.md` - phased plan with exit criteria
- `PROJECT_LOG.md` - human-readable activity log
- `.opencode/project-state.json` - machine-readable project state
- `AGENTS.md` - project conventions and agent definitions

## Git Context
- `git log --oneline -10` - recent commits
- `git status` - working tree status
- `git branch -a` - all branches

## Code Exploration
- `grep` for patterns like `export`, `import`, `interface`, `type` to understand code structure
- `read` on `src/routes/`, `src/models/`, `src/middleware/` to understand API structure

Start with a broad directory listing, then examine key configuration and documentation files to build a mental model of the project.--
