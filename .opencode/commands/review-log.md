---
description: Manually log a review in the tracking files
---

Record a review that was performed.

Capture the details (use $ARGUMENTS or gather them):
- Review type: code | security | independent
- Reviewer name
- Commit or ref reviewed (run `git rev-parse HEAD` if not given)
- Verdict: approve | request_changes | needs_discussion | pass | issues_found
- One-line summary

Then:
1. Update `.opencode/project-state.json`:
   - Prepend to `reviewHistory`: `{ "type": "<type>", "reviewer": "<name>", "commit": "<sha>", "verdict": "<verdict>", "timestamp": "<now ISO>", "summary": "<summary>" }`.
   - Set `lastReview` and `lastUpdated`.
2. Append a dated line under `## Reviews` in `PROJECT_LOG.md`:
   `- <date> — <type> review by <name> on commit <sha>: <verdict> — <summary>`

Keep the JSON valid. Only these two files may be edited.
