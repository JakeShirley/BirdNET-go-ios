import SwiftUI

struct ChangelogView: View {
    @StateObject private var viewModel = ChangelogViewModel()

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.entries.isEmpty {
                ProgressView("Loading changelog")
            } else if let error = viewModel.loadError {
                ContentUnavailableView(
                    "Changelog Unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else if viewModel.entries.isEmpty {
                ContentUnavailableView(
                    "No Release Notes Yet",
                    systemImage: "doc.text",
                    description: Text("Release notes will appear here once the first version of Onpa ships.")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(Array(viewModel.entries.enumerated()), id: \.element.id) { index, entry in
                            ReleaseCard(entry: entry, isLatest: index == 0)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .background(DS.Surface.grouped)
            }
        }
        .navigationTitle("Changelog")
        .toolbar(.hidden, for: .tabBar)
        .task {
            await viewModel.load()
        }
    }
}

// MARK: - Release card

private struct ReleaseCard: View {
    let entry: ChangelogViewModel.Entry
    let isLatest: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            ChangelogEntryBody(markdown: entry.body)
        }
        .padding(16)
        .background(DS.Surface.card, in: DS.Shape.xlarge)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    VersionPill(version: entry.version, highlighted: isLatest)
                    if isLatest {
                        Text("Latest")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(DS.accent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(DS.AccentTint.soft, in: Capsule())
                    }
                }

                if let dateLabel {
                    Text(dateLabel)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            if let url = entry.compareURL {
                Link(destination: url) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.title3)
                        .foregroundStyle(DS.accent)
                }
                .accessibilityLabel("View release \(entry.version) on GitHub")
            }
        }
    }

    private var dateLabel: String? {
        guard let date = entry.date else { return nil }
        return Self.dateFormatter.string(from: date)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter
    }()
}

private struct VersionPill: View {
    let version: String
    let highlighted: Bool

    var body: some View {
        Text(version)
            .font(.headline.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(highlighted ? Color.white : .primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                highlighted
                    ? AnyShapeStyle(DS.accent)
                    : AnyShapeStyle(Color(.tertiarySystemGroupedBackground)),
                in: Capsule()
            )
    }
}

// MARK: - Release body

private struct ChangelogEntryBody: View {
    let markdown: String

    var body: some View {
        if markdown.isEmpty {
            Text("No notes for this release.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                    SectionView(section: section)
                }
            }
        }
    }

    /// Groups the release body into named sections (e.g. "Features",
    /// "Bug Fixes"). Bullet points without a preceding `### ` heading are
    /// gathered into an implicit "Notes" section so they still render.
    /// Sections are returned in source order; semantic-release controls
    /// the upstream ordering (Features before Bug Fixes, etc.).
    private var sections: [Section] {
        var sections: [Section] = []
        var currentTitle: String?
        var currentBullets: [Bullet] = []

        func flush() {
            guard !currentBullets.isEmpty || currentTitle != nil else { return }
            sections.append(Section(title: currentTitle ?? "Notes", bullets: currentBullets))
            currentBullets.removeAll(keepingCapacity: true)
        }

        for rawLine in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = String(rawLine).trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            if trimmed.hasPrefix("### ") {
                flush()
                currentTitle = String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("* ") || trimmed.hasPrefix("- ") {
                currentBullets.append(Bullet(rawLine: String(trimmed.dropFirst(2))))
            } else {
                // Treat free-form paragraphs as a bullet without a hash so
                // they still appear in the rendered list.
                currentBullets.append(Bullet(rawLine: trimmed))
            }
        }
        flush()

        return sections
    }

    struct Section: Identifiable {
        let id = UUID()
        let title: String
        let bullets: [Bullet]

        var iconName: String {
            switch title.lowercased() {
            case let s where s.contains("break"): return "exclamationmark.octagon.fill"
            case let s where s.contains("feature"): return "sparkles"
            case let s where s.contains("bug") || s.contains("fix"): return "ladybug.fill"
            case let s where s.contains("perf"): return "bolt.fill"
            case let s where s.contains("doc"): return "book.fill"
            case let s where s.contains("refactor"): return "arrow.triangle.2.circlepath"
            case let s where s.contains("revert"): return "arrow.uturn.backward"
            case let s where s.contains("style"): return "paintbrush.fill"
            case let s where s.contains("test"): return "checkmark.seal.fill"
            case let s where s.contains("chore") || s.contains("build") || s.contains("ci"):
                return "gearshape.fill"
            default: return "circle.fill"
            }
        }

        var tint: Color {
            switch title.lowercased() {
            case let s where s.contains("break"): return .red
            case let s where s.contains("feature"): return .teal
            case let s where s.contains("bug") || s.contains("fix"): return .orange
            case let s where s.contains("perf"): return .yellow
            case let s where s.contains("doc"): return .blue
            case let s where s.contains("refactor"): return .purple
            case let s where s.contains("revert"): return .pink
            default: return .secondary
            }
        }
    }
}

// MARK: - Section + bullet rendering

private struct SectionView: View {
    let section: ChangelogEntryBody.Section

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: section.iconName)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(section.tint)
                Text(section.title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(section.bullets) { bullet in
                    BulletRow(bullet: bullet, tint: section.tint)
                }
            }
        }
    }
}

private struct BulletRow: View {
    let bullet: Bullet
    let tint: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle()
                .fill(tint.opacity(0.45))
                .frame(width: 5, height: 5)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 4) {
                Text(bullet.attributedMessage)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let scope = bullet.scope {
                    HStack(spacing: 6) {
                        Text(scope)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(DS.Surface.inset, in: Capsule())

                        if let commit = bullet.commit {
                            CommitBadge(commit: commit)
                        }
                    }
                } else if let commit = bullet.commit {
                    CommitBadge(commit: commit)
                }
            }
        }
    }
}

private struct CommitBadge: View {
    let commit: Bullet.Commit

    var body: some View {
        Group {
            if let url = commit.url {
                Link(destination: url) { content }
            } else {
                content
            }
        }
        .accessibilityLabel("Commit \(commit.shortHash)")
    }

    private var content: some View {
        HStack(spacing: 3) {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: 9, weight: .semibold))
            Text(commit.shortHash)
                .font(.caption2.monospaced())
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(DS.Surface.inset, in: Capsule())
    }
}

// MARK: - Bullet model

private struct Bullet: Identifiable {
    let id = UUID()
    let scope: String?
    let message: String
    let commit: Commit?

    struct Commit {
        let shortHash: String
        let url: URL?
    }

    init(rawLine: String) {
        var line = rawLine.trimmingCharacters(in: .whitespaces)

        // Pull the optional scope prefix (`**scope:**` or `**scope**:`).
        if let match = line.range(of: #"^\*\*([^*]+?)\*\*:?\s*"#, options: .regularExpression) {
            let raw = String(line[match])
            let scopeText = raw
                .replacingOccurrences(of: "*", with: "")
                .replacingOccurrences(of: ":", with: "")
                .trimmingCharacters(in: .whitespaces)
            scope = scopeText.isEmpty ? nil : scopeText
            line.removeSubrange(match)
        } else {
            scope = nil
        }

        // Pull the trailing `([abc1234](url))` commit reference.
        if let match = line.range(of: #"\s*\(\[([0-9a-f]{6,40})\]\(([^)]+)\)\)\s*$"#,
                                   options: [.regularExpression, .caseInsensitive]) {
            let raw = String(line[match])
            let hash = raw.range(of: #"\[([0-9a-f]+)\]"#, options: [.regularExpression, .caseInsensitive])
                .map { String(raw[$0]).trimmingCharacters(in: CharacterSet(charactersIn: "[]")) } ?? ""
            let urlString = raw.range(of: #"\(([^)]+)\)\s*$"#, options: .regularExpression)
                .map { String(raw[$0]).trimmingCharacters(in: CharacterSet(charactersIn: "() ")) } ?? ""
            let shortHash = String(hash.prefix(7))
            commit = Commit(shortHash: shortHash, url: URL(string: urlString))
            line.removeSubrange(match)
        } else if let match = line.range(of: #"\s*\(([0-9a-f]{6,40})\)\s*$"#,
                                          options: [.regularExpression, .caseInsensitive]) {
            let hash = String(line[match])
                .trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "()")))
            commit = Commit(shortHash: String(hash.prefix(7)), url: nil)
            line.removeSubrange(match)
        } else {
            commit = nil
        }

        message = line.trimmingCharacters(in: .whitespaces)
    }

    var attributedMessage: AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        return (try? AttributedString(markdown: message, options: options))
            ?? AttributedString(message)
    }
}

#Preview("Populated") {
    NavigationStack {
        ChangelogView()
    }
}
