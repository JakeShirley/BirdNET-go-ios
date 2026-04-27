# Development Guide

This project should be versioned and released with semantic-release.

## Versioning And Releases

Use semantic-release as the source of truth for release versions, release notes, and Git tags. Do not manually choose release versions or hand-edit generated changelog entries as part of normal feature work.

Expected release model:

- Commits use Conventional Commits.
- semantic-release analyzes commits to decide the next version.
- CI publishes release notes and tags when changes land on the release branch.
- iOS marketing versions should be derived from the semantic-release version during release automation.
- iOS build numbers can remain CI-generated monotonic build identifiers.

The exact semantic-release configuration should be added when the iOS project and CI pipeline are created.

## Commit Message Format

All feature, bug fix, maintenance, documentation, test, and CI commits should use semantic-release-compatible Conventional Commits:

```text
<type>(optional-scope): <description>

optional body

optional footer
```

Common types:

- `feat`: user-visible feature or capability.
- `fix`: user-visible bug fix.
- `perf`: performance improvement.
- `refactor`: code restructuring with no intended behavior change.
- `test`: test-only change.
- `docs`: documentation-only change.
- `build`: build system or dependency change.
- `ci`: CI workflow change.
- `chore`: repository maintenance that does not affect released behavior.

Breaking changes must use either a `!` after the type or a `BREAKING CHANGE:` footer:

```text
feat(api)!: require authenticated station profiles
```

```text
feat(api): require authenticated station profiles

BREAKING CHANGE: unauthenticated saved station profiles must be migrated before use.
```

Examples:

```text
feat(feed): add live detection stream
fix(auth): refresh csrf token after login
docs(release): document semantic-release workflow
test(api): add station config decoding fixtures
ci(release): add semantic-release workflow
```

## Agent And Contributor Expectations

- Do not make a Git commit unless explicitly asked.
- When asked to commit, use a Conventional Commit message that semantic-release can analyze.
- Prefer small commits with one release meaning each.
- Do not manually edit generated release notes, tags, or version bumps unless the release automation itself is being fixed.
- If a change is user-visible, choose `feat`, `fix`, or `perf` instead of hiding it under `chore`.
- Keep release-impacting changes separate from unrelated documentation or cleanup when practical.

## App Structure

The iOS app keeps foundation code in separate source areas so feature work can grow without mixing concerns:

- `BirdNETGo/App`: SwiftUI app entry point, tab shell, and dependency environment wiring.
- `BirdNETGo/Domain`: shared app models and domain state.
- `BirdNETGo/Networking`: BirdNET-Go API client protocols and URLSession implementations.
- `BirdNETGo/Storage`: storage protocols and concrete persistence implementations.
- `BirdNETGo/Features`: user-facing SwiftUI feature modules such as Feed, Species, Stats, and Station.
