---
description: Show project status, active tasks, and recent reviews
---

Show the current project status.

1. Read `.opencode/project-state.json` and `PROJECT_LOG.md`.
2. Summarize:
   - Active tasks and who they're assigned to
   - Completed tasks
   - Last review: type, reviewer, commit, verdict, and timestamp (from `lastReview` / `reviewHistory`)
   - Whether the working tree is clean or dirty (run `git status` and `git log --oneline -5`)
3. If `lastReview` is null or stale, note that no recent review is recorded.

Keep the summary concise and readable.
