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

## Accessibility Baseline (FND-007)

Every new view, control, or modification must meet the following baseline. Treat
this as a hard requirement, not a polish pass.

- Dynamic Type: prefer `Font.title/headline/subheadline/body/caption*` over
  `Font.system(size:)`. If a fixed size is unavoidable for layout (heatmap
  cells, etc.), keep it isolated to a leaf view and document why.
- VoiceOver labels:
  - Add `accessibilityLabel` to any `Image`, icon-only `Button`, or chip that
    isn't already self-describing.
  - Use `accessibilityElement(children: .combine)` plus a single
    `accessibilityLabel` for compound rows (commonName + scientific name +
    confidence + time, KPI tiles, metric chips, hearing rows, etc.) so
    VoiceOver speaks one coherent phrase per row.
  - Decorative images (icons inside an already-labeled card) should be marked
    `.accessibilityHidden(true)`.
  - For heavy data visualizations (heatmap rows, hourly bars), expose a
    summarized `accessibilityLabel` and hide the per-cell visuals from
    VoiceOver with `.accessibilityHidden(true)`. Add `.accessibilityValue` to
    individual elements only when each cell carries unique information.
- Contrast: use `Color.primary`, `Color.secondary`, system grouped surfaces, and
  `DS.accent`/`DS.AccentTint` tokens from `App/DesignSystem.swift` rather than
  hand-picked colors. Avoid placing text on translucent overlays without a
  legible material backing.
- Reduced motion: gate spring animations, parallax, scale, and slide
  transitions on `@Environment(\.accessibilityReduceMotion)`. Cross-fades and
  state-only changes are fine.
- Hit targets: keep tappable controls at least 44x44 points; if a chip looks
  smaller, wrap it in a `Button` with appropriate padding.

When implementing a new view, include the accessibility hooks in the same
change rather than as a follow-up.

