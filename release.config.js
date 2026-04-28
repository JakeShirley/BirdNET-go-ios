// semantic-release configuration for Onpa.
//
// Uses a JS config so we can pass a custom commitGroupsSort comparator to
// @semantic-release/release-notes-generator. The default Angular preset
// sorts groups alphabetically, which puts "Bug Fixes" before "Features".
// We want the order: Breaking Changes -> Features -> Bug Fixes -> Perf ->
// Reverts -> Code Refactoring -> everything else, so both the GitHub
// Release body and the TestFlight What to Test notes read top-to-bottom
// from most-impactful to least.

const sectionOrder = [
  "Features",
  "Bug Fixes",
  "Performance Improvements",
  "Reverts",
  "Code Refactoring",
];

function rankFor(title) {
  const index = sectionOrder.indexOf(title);
  return index === -1 ? sectionOrder.length : index;
}

module.exports = {
  branches: ["main"],
  tagFormat: "v${version}",
  plugins: [
    "@semantic-release/commit-analyzer",
    [
      "@semantic-release/release-notes-generator",
      {
        preset: "angular",
        presetConfig: {
          types: [
            { type: "feat", section: "Features" },
            { type: "fix", section: "Bug Fixes" },
            { type: "perf", section: "Performance Improvements" },
            { type: "revert", section: "Reverts" },
            { type: "refactor", section: "Code Refactoring", hidden: false },
            { type: "docs", section: "Documentation", hidden: true },
            { type: "style", section: "Styles", hidden: true },
            { type: "test", section: "Tests", hidden: true },
            { type: "build", section: "Build System", hidden: true },
            { type: "ci", section: "Continuous Integration", hidden: true },
            { type: "chore", section: "Chores", hidden: true },
          ],
        },
        writerOpts: {
          commitGroupsSort: (lhs, rhs) => rankFor(lhs.title) - rankFor(rhs.title),
          commitsSort: ["scope", "subject"],
        },
      },
    ],
    [
      "@semantic-release/changelog",
      {
        changelogFile: "CHANGELOG.md",
        changelogTitle:
          "# Changelog\n\nAll notable changes to Onpa are documented here. This file is generated automatically by [semantic-release](https://github.com/semantic-release/semantic-release) on each release.",
      },
    ],
    [
      "@semantic-release/exec",
      {
        prepareCmd:
          "bash scripts/build_testflight_ipa.sh ${nextRelease.version} && mkdir -p build/TestFlight && printf '%s' \"${nextRelease.notes}\" | node scripts/format_testflight_notes.js > build/TestFlight/release-notes.md",
      },
    ],
    [
      "@semantic-release/github",
      {
        successComment: false,
        failComment: false,
        assets: [{ path: "CHANGELOG.md", label: "Changelog" }],
      },
    ],
  ],
};
