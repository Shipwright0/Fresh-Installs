---
description: Run security audit on current changes
subtask: true
---

Audit the uncommitted changes for security issues:

!`git diff`
!`git status`

Check for:
- Hardcoded secrets or credentials
- Missing input validation
- SQL injection, XSS, or other injection vectors
- Insecure configurations
- Exposed sensitive data (paths, tokens, internal details)
- Missing rate limiting
- Path traversal vulnerabilities

Reference the project's security requirements in SPEC.md and AGENTS.md.
Report findings with severity and remediation steps.

## Record your review (required)

After delivering your findings, log the review:

1. Get the current commit: `git rev-parse HEAD`.
2. Update `.opencode/project-state.json`:
   - Prepend to `reviewHistory`: `{ "type": "security", "reviewer": "security-auditor", "commit": "<sha>", "verdict": "pass|issues_found", "timestamp": "<now ISO>", "summary": "<one line>" }`.
   - Set `lastReview` and `lastUpdated`.
3. Append a dated line under `## Reviews` in `PROJECT_LOG.md`:
   `- <date> — security audit by security-auditor on commit <sha>: <verdict> — <one line summary>`
4. Keep the JSON valid. Only these two files may be edited.
