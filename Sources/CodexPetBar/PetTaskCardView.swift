import CodexPetBarCore
import SwiftUI

/// One destination, one click target. Pet choices belong in the context menu.
struct PetTaskCardView: View {
    let task: PetTaskPresentation
    let pet: PetPackage?
    let availablePets: [PetPackage]
    let onOpen: () -> Void
    let onAssign: (String) -> Void
    @State private var isHovered = false
    var onBeginInteraction: () -> Void = {}

    private var subtitle: String {
        let context = task.projectName.isEmpty || task.projectName == "Other" ? task.provider.displayName : task.projectName
        switch task.state {
        case .waiting: return "Needs your input · \(context)"
        case .failed: return "Needs attention · \(context)"
        case .running: return "Working · \(context)"
        case .completed: return "Finished · \(context)"
        case .recent: return context
        }
    }

    private var needsAttention: Bool { task.state == .waiting || task.state == .failed }

    var body: some View {
        Button {
            onBeginInteraction()
            onOpen()
        } label: {
            HStack(spacing: 10) {
                PetPortraitView(pet: pet, size: 32).frame(width: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text(task.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary).lineLimit(1)
                    HStack(spacing: 4) {
                        if needsAttention {
                            Circle().fill(Color.orange).frame(width: 4, height: 4)
                        }
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(needsAttention ? Color.primary : .secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary).opacity(isHovered ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 8).frame(height: 56)
            .background(isHovered ? Color.primary.opacity(0.055) : .clear, in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help([task.title, task.summary, PetTaskNavigator.actionLabel(for: task)].filter { !$0.isEmpty }.joined(separator: "\n"))
        .accessibilityLabel("\(task.title), \(subtitle)")
        .accessibilityHint(task.accessibilityOpenHint)
        .onHover { isHovered = $0 }
        .contextMenu {
            Button(PetTaskNavigator.actionLabel(for: task), action: onOpen)
            if !availablePets.isEmpty {
                Menu("Choose pet") {
                    ForEach(availablePets) { choice in
                        Button {
                            onBeginInteraction()
                            onAssign(choice.id)
                        } label: {
                            if choice.id == pet?.id {
                                Label(choice.displayName, systemImage: "checkmark")
                            } else {
                                Text(choice.displayName)
                            }
                        }
                    }
                }
            }
        }
    }
}
