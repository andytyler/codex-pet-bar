import CodexPetBarCore
import SwiftUI

struct PetTaskCardView: View {
    let task: PetTaskPresentation
    let pet: PetPackage?
    let availablePets: [PetPackage]
    let onOpen: () -> Void
    let onAssign: (String) -> Void
    @State private var isHovered = false
    @State private var showsPetPicker = false
    var onBeginInteraction: () -> Void = {}

    private var tint: Color {
        switch task.state {
        case .failed: .red
        case .waiting: .orange
        case .running: .teal
        case .completed: .green
        case .recent: .secondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Button {
                    onBeginInteraction()
                    showsPetPicker.toggle()
                } label: {
                    VStack(spacing: 4) {
                        PetPortraitView(pet: pet, size: 48)
                        Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(width: 52, height: 66)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(availablePets.isEmpty)
                .help("Choose a pet for this task")
                .accessibilityLabel("Change pet for \(task.title)")
                .accessibilityValue(pet?.displayName ?? "No pet")
                Button(action: onOpen) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 4) {
                            Text(task.projectName.isEmpty ? task.provider.displayName : task.projectName)
                                .lineLimit(1).truncationMode(.middle)
                            if !task.projectName.isEmpty {
                                Text("·")
                                Text(task.provider.displayName).fixedSize()
                            }
                            Spacer(minLength: 2)
                            if let date = task.updatedAt {
                                Text(date, style: .relative).lineLimit(1).help("Last activity")
                            }
                        }
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        Text(task.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2).multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        if !task.summary.isEmpty {
                            Text(task.summary)
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                                .lineLimit(2).multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        HStack {
                            Label(task.state == .running ? "Working" : task.state.displayName,
                                  systemImage: task.state.systemImageName)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(tint).lineLimit(1).fixedSize()
                            Spacer(minLength: 4)
                            HStack(spacing: 4) {
                                Text(PetTaskNavigator.actionLabel(for: task))
                                Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .semibold))
                            }
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(isHovered ? Color.accentColor : .secondary)
                        }
                        .padding(.top, 2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(task.summary)
                .accessibilityLabel("\(task.title), \(task.state.displayName). \(task.summary)")
                .accessibilityHint(task.accessibilityOpenHint)
            }
            if showsPetPicker {
                Divider()
                HStack {
                    Text("Choose a companion").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    Spacer()
                    Button { showsPetPicker = false } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain).accessibilityLabel("Close pet chooser")
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 72))], spacing: 8) {
                    ForEach(availablePets) { choice in
                        Button {
                            showsPetPicker = false
                            onAssign(choice.id)
                        } label: {
                            VStack(spacing: 4) {
                                PetPortraitView(pet: choice, size: 36)
                                Text(choice.displayName).font(.system(size: 10)).lineLimit(1)
                            }.frame(maxWidth: .infinity).padding(.vertical, 6)
                                .background(choice.id == pet?.id ? Color.accentColor.opacity(0.12) : .clear,
                                            in: RoundedRectangle(cornerRadius: 8))
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityLabel("Assign \(choice.displayName)")
                    }
                }
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(tint.opacity(task.state == .waiting || task.state == .failed ? 0.065 : isHovered ? 0.06 : 0.025))
        }
        .overlay(alignment: .leading) {
            if task.state == .waiting || task.state == .failed {
                Capsule().fill(tint.opacity(0.8)).frame(width: 3, height: 28)
            }
        }
        .onHover { isHovered = $0 }
    }
}
