import AppKit
import OSLog

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.github.haad.clipsmith",
    category: "ClaudeToolkitService"
)

// MARK: - ClaudeToolkitItem

/// A single installable item from the awesome-claude-code-toolkit.
///
/// Items map to markdown files in the toolkit:
/// - Commands: `commands/<category>/<name>.md` → `~/.claude/commands/<name>.md`
/// - Agents:   `agents/<category>/<name>.md`   → `~/.claude/agents/<name>.md`
/// - Skills:   `skills/<name>/SKILL.md`         → `~/.claude/skills/<name>.md`
struct ClaudeToolkitItem: Sendable, Identifiable, Hashable {

    enum Kind: String, Sendable, CaseIterable {
        case command, agent, skill

        var label: String {
            switch self {
            case .command: return "Commands"
            case .agent:   return "Agents"
            case .skill:   return "Skills"
            }
        }

        /// Subdirectory name under `~/.claude/` where items of this kind are installed.
        var installSubdirectory: String { rawValue + "s" }
    }

    let id: String          // "kind/filename-stem" — globally unique
    let name: String        // human-readable display name
    let description: String // one-line summary from frontmatter or first paragraph
    let kind: Kind
    let category: String    // toolkit category (parent directory name)
    let content: String     // full markdown content
    let sourceURL: URL      // path to the source file in the toolkit
    let fileName: String    // "<stem>.md" — written to the install directory
}

// MARK: - ClaudeToolkitService

/// Scans a local awesome-claude-code-toolkit directory and installs/uninstalls
/// items into `~/.claude/commands/`, `~/.claude/agents/`, `~/.claude/skills/`.
@MainActor
final class ClaudeToolkitService {

    private let claudeDir: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude")

    // MARK: - Scanning

    /// Reads the toolkit directory and returns all discovered items sorted by name.
    func scan(at toolkitURL: URL) -> [ClaudeToolkitItem] {
        var items: [ClaudeToolkitItem] = []
        items += scanCommands(at: toolkitURL)
        items += scanAgents(at: toolkitURL)
        items += scanSkills(at: toolkitURL)
        return items.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    // MARK: - Install / Uninstall

    func install(_ item: ClaudeToolkitItem) throws {
        let destDir = claudeDir.appendingPathComponent(item.kind.installSubdirectory)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        let dest = destDir.appendingPathComponent(item.fileName)
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: item.sourceURL, to: dest)
        logger.info("Installed \(item.kind.rawValue, privacy: .public): \(item.name, privacy: .public)")
    }

    func uninstall(_ item: ClaudeToolkitItem) throws {
        let dest = claudeDir
            .appendingPathComponent(item.kind.installSubdirectory)
            .appendingPathComponent(item.fileName)
        guard FileManager.default.fileExists(atPath: dest.path) else { return }
        try FileManager.default.removeItem(at: dest)
        logger.info("Uninstalled \(item.kind.rawValue, privacy: .public): \(item.name, privacy: .public)")
    }

    func isInstalled(_ item: ClaudeToolkitItem) -> Bool {
        let dest = claudeDir
            .appendingPathComponent(item.kind.installSubdirectory)
            .appendingPathComponent(item.fileName)
        return FileManager.default.fileExists(atPath: dest.path)
    }

    // MARK: - Private Scanners

    private func scanCommands(at toolkitURL: URL) -> [ClaudeToolkitItem] {
        scanTwoLevelDirectory(
            at: toolkitURL.appendingPathComponent("commands"),
            kind: .command
        )
    }

    private func scanAgents(at toolkitURL: URL) -> [ClaudeToolkitItem] {
        scanTwoLevelDirectory(
            at: toolkitURL.appendingPathComponent("agents"),
            kind: .agent
        )
    }

    /// Commands and agents share the same two-level layout: `<dir>/<category>/<name>.md`
    private func scanTwoLevelDirectory(at dirURL: URL, kind: ClaudeToolkitItem.Kind) -> [ClaudeToolkitItem] {
        let fm = FileManager.default
        guard let categoryDirs = try? fm.contentsOfDirectory(
            at: dirURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        ) else { return [] }

        var items: [ClaudeToolkitItem] = []
        for categoryURL in categoryDirs {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: categoryURL.path, isDirectory: &isDir) else { continue }

            if !isDir.boolValue {
                // Top-level .md file with no category subdirectory
                if categoryURL.pathExtension == "md",
                   let item = makeItem(fileURL: categoryURL, category: kind.rawValue, kind: kind) {
                    items.append(item)
                }
                continue
            }

            guard let files = try? fm.contentsOfDirectory(
                at: categoryURL,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            ) else { continue }

            let category = categoryURL.lastPathComponent
            for fileURL in files where fileURL.pathExtension == "md" {
                if let item = makeItem(fileURL: fileURL, category: category, kind: kind) {
                    items.append(item)
                }
            }
        }
        return items
    }

    /// Skills use a different layout: `skills/<name>/SKILL.md`
    private func scanSkills(at toolkitURL: URL) -> [ClaudeToolkitItem] {
        let fm = FileManager.default
        let skillsDir = toolkitURL.appendingPathComponent("skills")
        guard let subdirs = try? fm.contentsOfDirectory(
            at: skillsDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        ) else { return [] }

        return subdirs.compactMap { dirURL in
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dirURL.path, isDirectory: &isDir), isDir.boolValue else { return nil }
            let skillFile = dirURL.appendingPathComponent("SKILL.md")
            guard let content = try? String(contentsOf: skillFile, encoding: .utf8),
                  !content.isEmpty else { return nil }
            let dirName = dirURL.lastPathComponent
            let (fmName, fmDesc) = parseFrontmatter(content)
            let name = humanize(fmName ?? dirName)
            let description = fmDesc ?? firstParagraph(content)
            return ClaudeToolkitItem(
                id: "skill/\(dirName)",
                name: name,
                description: description,
                kind: .skill,
                category: "skills",
                content: content,
                sourceURL: skillFile,
                fileName: "\(dirName).md"
            )
        }
    }

    private func makeItem(
        fileURL: URL,
        category: String,
        kind: ClaudeToolkitItem.Kind
    ) -> ClaudeToolkitItem? {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8),
              !content.isEmpty else { return nil }
        let stem = fileURL.deletingPathExtension().lastPathComponent
        let (fmName, fmDesc) = parseFrontmatter(content)
        let name = humanize(fmName ?? stem)
        let description = fmDesc ?? firstParagraph(content)
        return ClaudeToolkitItem(
            id: "\(kind.rawValue)/\(stem)",
            name: name,
            description: description,
            kind: kind,
            category: category,
            content: content,
            sourceURL: fileURL,
            fileName: "\(stem).md"
        )
    }

    // MARK: - Helpers

    /// Parses YAML frontmatter delimited by `---` lines, extracting `name` and `description`.
    private func parseFrontmatter(_ content: String) -> (name: String?, description: String?) {
        guard content.hasPrefix("---") else { return (nil, nil) }
        let lines = content.components(separatedBy: .newlines)
        // Find the closing ---  (skip index 0 which is the opening ---)
        guard let closeIdx = lines.indices.dropFirst().first(where: {
            lines[$0].trimmingCharacters(in: .whitespaces) == "---"
        }) else { return (nil, nil) }

        var name: String?
        var description: String?
        for line in lines[1..<closeIdx] {
            let lower = line.lowercased()
            if lower.hasPrefix("name:") {
                name = stripped(line.dropFirst(5))
            } else if lower.hasPrefix("description:") {
                description = stripped(line.dropFirst(12))
            }
        }
        return (name, description)
    }

    private func stripped(_ s: some StringProtocol) -> String {
        String(s)
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    }

    /// Returns the first non-empty, non-heading line of content, skipping frontmatter.
    private func firstParagraph(_ content: String) -> String {
        var inFrontmatter = content.hasPrefix("---")
        var passedOpen = false
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if inFrontmatter {
                if trimmed == "---" && passedOpen { inFrontmatter = false }
                passedOpen = true
                continue
            }
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            return String(trimmed.prefix(140))
        }
        return ""
    }

    /// Converts a kebab-case or snake_case slug into Title Case, uppercasing known acronyms.
    private func humanize(_ slug: String) -> String {
        let acronyms: Set<String> = ["tdd", "api", "aws", "ci", "cd", "sql", "ui", "ux", "llm", "mcp", "qa"]
        return slug
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { word in
                let s = String(word).lowercased()
                return acronyms.contains(s)
                    ? s.uppercased()
                    : s.prefix(1).uppercased() + s.dropFirst()
            }
            .joined(separator: " ")
    }
}
