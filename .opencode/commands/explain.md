---
description: Walk through and explain code one piece at a time — a file, a diff, or a commit
agent: explain
---

Walk the user through an explanation of code, one piece at a time.

- If `$ARGUMENTS` is a path to a file in the repo, do a full-file walkthrough.
- If `$ARGUMENTS` is a git ref (commit, branch, or PR number), explain that diff
  using `git show` / `git diff`.
- If `$ARGUMENTS` is empty, walk through the uncommitted diff (`git diff` and
  `git status`).

Follow your walkthrough method exactly: one piece at a time, wait for the user to
say `next` or ask questions before continuing, and finish by saving the full
explanation to `docs/explain/` and showing it in the chat.