# Features

## Feature schema

Each feature is a JSON file in `.projd/progress/`. The filename should match the `id` (e.g., `.projd/progress/user-auth.json`).

```json
{
  "id": "user-auth",
  "name": "User Authentication",
  "description": "JWT-based login and registration with email/password.",
  "acceptance_criteria": [
    "POST /auth/register creates a user and returns a JWT",
    "POST /auth/login returns a JWT for valid credentials, 401 for invalid",
    "Protected routes return 401 without a valid token"
  ],
  "priority": 1,
  "status": "pending",
  "branch": "",
  "blocked_by": [],
  "notes": ""
}
```

## Writing good features

- **Independently shippable**: Each feature should leave the codebase in a working state even if the next feature never gets built.
- **Observable criteria**: "returns a 200" not "is well-designed." Things you can verify by running a command or hitting an endpoint.
- **One session scope**: If a feature is too big for one session, split it into smaller features and use `blocked_by` to order them.
- **Explicit dependencies**: If feature B requires feature A's code to exist, add `"blocked_by": ["feature-a"]`. This lets agents and operators see what can be parallelized.

## Session continuity

Long-running work often spans multiple sessions. projd handles this through `.projd/HANDOFF.md`:

- When a session ends with incomplete work, `projd-end` writes `.projd/HANDOFF.md` with what was accomplished, current state, and prioritized next steps.
- When the next session starts, `projd-start` reads `.projd/HANDOFF.md` and orients the agent with full context from where the previous session left off.
- When a feature is completed, `.projd/HANDOFF.md` is deleted -- there's nothing to hand off.

`.projd/HANDOFF.md` is ephemeral (listed in `.gitignore`). It exists only between sessions and is never committed.
