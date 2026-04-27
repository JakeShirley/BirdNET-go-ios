# Copilot Instructions

This repository is planned as a native iOS companion app for BirdNET-Go. Follow the project plan in `docs/BIRDNET_GO_IOS_PROJECT_PLAN.md` and the developer guide in `docs/DEVELOPMENT.md`.

## Release And Commit Discipline

This project should be versioned with semantic-release. Any commits made by an agent or contributor must use semantic-release-compatible Conventional Commits.

Use these commit types when appropriate:

- `feat`: user-visible feature or capability.
- `fix`: user-visible bug fix.
- `perf`: performance improvement.
- `refactor`: code restructuring without intended behavior change.
- `test`: test-only change.
- `docs`: documentation-only change.
- `build`: build system or dependency change.
- `ci`: CI workflow change.
- `chore`: repository maintenance with no released behavior change.

Include one or more project plan step IDs from `docs/BIRDNET_GO_IOS_PROJECT_PLAN.md` near the start of the commit subject. Use `type(scope): [PLAN-ID] description` when a scope helps, for example:

```text
feat(feed): [DET-002] add live detection stream
fix(auth): [CON-005] refresh csrf token after login
docs(release): [NO-PLAN] document semantic-release workflow
```

If a commit spans multiple planned steps, include each ID in separate brackets, for example `feat: [CON-001] [CON-002] validate manual station connection`. For repository-only work that does not map to a planned backlog step, use `[NO-PLAN]` and explain why in the commit body.

Mark breaking changes with `!` or a `BREAKING CHANGE:` footer.

Do not manually choose release versions, create release tags, or hand-edit generated changelog entries during normal feature work. semantic-release owns those outputs.

Do not commit unless the user explicitly asks for a commit. When the user does ask for a commit, keep it focused, include the relevant project plan step tag, and use the Conventional Commit type that matches the release impact.
