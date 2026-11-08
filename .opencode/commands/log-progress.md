---
description: Log a task progress entry in the tracking files
---

Log a task progress entry.

Prompt the user for:
- Task title
- Status: in_progress | completed | blocked
- Notes (optional)

Then update the tracking files:

1. Update `.opencode/project-state.json`:
   - Add or move an entry in `activeTasks` / `completedTasks` with an id, title,
     status, and timestamp.
   - Set `lastUpdated`.
2. Append a dated line under `## Task progress` in `PROJECT_LOG.md`:
   `- <date> — <title>: <status> — <notes>`

Keep the JSON valid. Only these two files may be edited.
