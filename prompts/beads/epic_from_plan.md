---
description: Convert the plan into an epic and create issues for each task.
model: claude-opus-4-5
---

Create an epic from this plan. Include the plan in the epic description. 
Then create multiple issues under this epic with correct dependencies between them so that multiple developers can work on them simultaneously, when possible. Only one developer should work on the same file at a time.
The issue description should have enough information to get onboarded and start working on the issue immediately.

```bash
bd create "Child issue of epic" --description="..." -t task -p 1 --deps parent-child:<epic-issue-id> --json
```
