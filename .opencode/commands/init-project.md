---
description: Initialize or verify git repo and project tracking files
---

Initialize this project for tracked multi-agent work.

1. If no git repository exists (check `git status`), run `git init` and create an
   initial commit of the current files.
2. Ensure `.opencode/project-state.json` exists with the expected shape (project,
   lastUpdated, activeTasks, completedTasks, agents, lastReview, reviewHistory).
3. Ensure `PROJECT_LOG.md` exists with an Initialization entry noting the commit.
4. Report the current commit hash (`git rev-parse HEAD`) and what was created or skipped.

Do not modify source code. Only initialize/verify the repo and tracking files.
