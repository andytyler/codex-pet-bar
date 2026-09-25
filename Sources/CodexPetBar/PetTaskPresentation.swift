import Foundation
import CodexPetBarCore

enum PetTaskProviderPresentation: String, Hashable, Sendable {
    case codex
    case claude
    case cursor
    case other

    var displayName: String {
        switch self {
        case .codex:
            "Codex"
        case .claude:
            "Claude Code"
        case .cursor:
            "Cursor"
        case .other:
            "Agent"
        }
    }

    var systemImageName: String {
        switch self {
        case .codex:
            "sparkles.square.filled.on.square"
        case .claude:
            "command.circle.fill"
        case .cursor:
            "cursorarrow.rays"
        case .other:
            "terminal.fill"
        }
    }
}

enum PetTaskStatePresentation: String, Sendable {
    case running
    case waiting
    case completed
    case failed
    case recent

    var displayName: String {
        switch self {
        case .running:
            "Running"
        case .waiting:
            "Waiting for input"
        case .completed:
            "Completed"
        case .failed:
            "Needs attention"
        case .recent:
            "Recent"
        }
    }

    var systemImageName: String {
        switch self {
        case .running:
            "arrow.triangle.2.circlepath"
        case .waiting:
            "hand.raised.fill"
        case .completed:
            "checkmark"
        case .failed:
            "exclamationmark"
        case .recent:
            "clock.fill"
        }
    }

    var isActive: Bool {
        switch self {
        case .running, .waiting, .failed:
            true
        case .completed, .recent:
            false
        }
    }
}

struct PetTaskPresentation: Identifiable, Equatable, Sendable {
    let id: String
    let sourceID: String
    let navigationSourceID: String?
    let title: String
    let summary: String
    let provider: PetTaskProviderPresentation
    let state: PetTaskStatePresentation
    let deepLinkURL: URL?
    let projectURL: URL?
    var projectName: String = ""
    var updatedAt: Date? = nil

    var accessibilityOpenHint: String {
        switch provider {
        case .codex:
            "Opens this Codex task"
        case .claude:
            "Opens Claude Code when supported, or this project in Finder"
        case .cursor:
            "Opens this project in Cursor"
        case .other:
            "Opens this project"
        }
    }
}

struct PetTaskProjectPresentation: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let tasks: [PetTaskPresentation]
}

struct PetHoverPanelContent: Equatable, Sendable {
    let petName: String
    let statusText: String
    let projects: [PetTaskProjectPresentation]
    let connections: [ProviderIntegrationHealth]
    let installingProvider: String?
    let connectionMessage: String?
    let connectionFailed: Bool
    let petSourceText: String
    let hasPet: Bool
    let selectedPet: PetPackage?
    let availablePets: [PetPackage]
    let assignments: [String: String]
    let displayMode: PetDisplayMode
    let navigationError: String?

    init(
        petName: String, statusText: String, projects: [PetTaskProjectPresentation],
        connections: [ProviderIntegrationHealth] = [], installingProvider: String? = nil,
        connectionMessage: String? = nil, connectionFailed: Bool = false,
        petSourceText: String = "Following your Codex pet", hasPet: Bool = true,
        selectedPet: PetPackage? = nil, availablePets: [PetPackage] = [],
        assignments: [String: String] = [:], displayMode: PetDisplayMode = .companion,
        navigationError: String? = nil
    ) {
        self.petName = petName
        self.statusText = statusText
        self.projects = projects
        self.connections = connections
        self.installingProvider = installingProvider
        self.connectionMessage = connectionMessage
        self.connectionFailed = connectionFailed
        self.petSourceText = petSourceText
        self.hasPet = hasPet
        self.selectedPet = selectedPet
        self.availablePets = availablePets
        self.assignments = assignments
        self.displayMode = displayMode
        self.navigationError = navigationError
    }

    var needsAttention: Bool {
        projects.flatMap(\.tasks).contains { $0.state == .waiting || $0.state == .failed }
    }

    var hasReadyConnection: Bool {
        connections.contains { $0.state == .connected || $0.state == .noSignal }
    }

    var hasConnectionIssue: Bool {
        connections.contains { $0.state == .needsUpdate || $0.state == .deliveryError }
    }

    var attentionProjects: [PetTaskProjectPresentation] {
        filteredProjects { $0.state == .waiting || $0.state == .failed }
    }

    var remainingProjects: [PetTaskProjectPresentation] {
        filteredProjects { $0.state != .waiting && $0.state != .failed }
    }

    private func filteredProjects(_ predicate: (PetTaskPresentation) -> Bool) -> [PetTaskProjectPresentation] {
        projects.compactMap { project in
            let tasks = project.tasks.filter(predicate)
            return tasks.isEmpty ? nil : PetTaskProjectPresentation(id: project.id, name: project.name, tasks: tasks)
        }
    }

    var taskCount: Int {
        projects.reduce(0) { $0 + $1.tasks.count }
    }

    var activeProviders: [PetTaskProviderPresentation] {
        var seen = Set<PetTaskProviderPresentation>()
        return projects
            .flatMap(\.tasks)
            .compactMap { task in
                guard task.state.isActive, seen.insert(task.provider).inserted else {
                    return nil
                }
                return task.provider
            }
    }

    var preferredHeight: CGFloat {
        let activeCount = projects.flatMap(\.tasks).filter { $0.state.isActive }.count
        guard activeCount > 0 else { return taskCount > 0 ? 440 : 340 }
        return min(640, 242 + CGFloat(min(activeCount, 4)) * 116)
    }
}

enum PetTaskPresentationAdapter {
    static func taskGroups(_ groups: [PetTaskProjectGroup]) -> [PetTaskProjectPresentation] {
        groups.map { group in
            let projectFallbackURL = group.project.path.map {
                URL(fileURLWithPath: $0, isDirectory: true)
            }
            return PetTaskProjectPresentation(
                id: group.id,
                name: group.project.name,
                tasks: group.tasks.map { task in
                    PetTaskPresentation(
                        id: task.id,
                        sourceID: task.sourceID,
                        navigationSourceID: task.navigationSourceID,
                        title: task.title,
                        summary: task.detail,
                        provider: provider(task.provider),
                        state: state(task.status),
                        deepLinkURL: task.deepLinkURL,
                        projectURL: projectFallbackURL,
                        projectName: group.project.name,
                        updatedAt: task.updatedAt
                    )
                }
            )
        }
    }

    static func codexThreads(
        _ threads: [CodexThreadSummary],
        activeThreadIDs: Set<String>,
        now: Date = Date()
    ) -> [PetTaskProjectPresentation] {
        let rows = CodexThreadMenuRows.build(threads: threads)
        let datesByID = Dictionary(uniqueKeysWithValues: threads.map { ($0.id, $0.updatedAt) })
        let sections = CodexThreadMenuSections.build(rows: rows)

        return sections.map { section in
            PetTaskProjectPresentation(
                id: section.folderTitle,
                name: section.folderTitle,
                tasks: section.rows.map { row in
                    let isRunning = activeThreadIDs.contains(row.id)
                    return PetTaskPresentation(
                        id: row.id,
                        sourceID: row.id,
                        navigationSourceID: row.id,
                        title: row.title,
                        summary: fallbackSummary(
                            isRunning: isRunning,
                            updatedAt: datesByID[row.id] ?? nil,
                            now: now
                        ),
                        provider: .codex,
                        state: isRunning ? .running : .recent,
                        deepLinkURL: row.deepLinkURL,
                        projectURL: nil
                    )
                }
            )
        }
    }

    private static func fallbackSummary(isRunning: Bool, updatedAt: Date?, now: Date) -> String {
        if isRunning {
            return "Working in Codex"
        }

        guard let updatedAt else {
            return "Recent Codex task"
        }

        let elapsed = max(0, now.timeIntervalSince(updatedAt))
        switch elapsed {
        case ..<60:
            return "Updated just now"
        case ..<3_600:
            return "Updated \(max(1, Int(elapsed / 60)))m ago"
        case ..<86_400:
            return "Updated \(max(1, Int(elapsed / 3_600)))h ago"
        default:
            return "Updated \(max(1, Int(elapsed / 86_400)))d ago"
        }
    }

    private static func provider(_ provider: PetProvider) -> PetTaskProviderPresentation {
        switch provider {
        case .codex:
            .codex
        case .claude:
            .claude
        case .cursor:
            .cursor
        }
    }

    private static func state(_ state: PetTaskStatus) -> PetTaskStatePresentation {
        switch state {
        case .running:
            .running
        case .waiting:
            .waiting
        case .failed:
            .failed
        case .completed:
            .completed
        case .recent:
            .recent
        }
    }
}
