import SwiftUI
import CodexPetBarCore

/// Compact contents for the task panel's parent-owned connection disclosure.
/// Installing is owned by the controller so closing the panel cannot cancel it.
struct ProviderConnectionsView: View {
    let health: [ProviderIntegrationHealth]
    let installingProvider: String?
    let resultMessage: String?
    let resultIsError: Bool
    let onConnect: (PetProvider) -> Void

    static func estimatedHeight(resultMessage: String?) -> CGFloat {
        222 + (resultMessage?.isEmpty == false ? 42 : 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(PetProvider.allCases, id: \.self) { provider in
                let providerHealth = health.first { $0.provider == provider }
                    ?? ProviderIntegrationHealth(provider: provider, state: .notInstalled)
                ProviderConnectionRow(
                    presentation: ProviderConnectionPresentation(health: providerHealth),
                    isInstalling: installingProvider == provider.rawValue || installingProvider == "all",
                    isBusy: installingProvider != nil,
                    onConnect: { onConnect(provider) }
                )
                if provider != PetProvider.allCases.last {
                    Divider().padding(.leading, 30)
                }
            }

            if let resultMessage, !resultMessage.isEmpty {
                Label(resultMessage, systemImage: resultIsError ? "exclamationmark.circle" : "checkmark.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(resultIsError ? Color.orange : Color.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
                    .help(resultMessage)
                    .accessibilityLabel(resultIsError ? "Connection issue: \(resultMessage)" : resultMessage)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Agent connections")
    }
}

private struct ProviderConnectionRow: View {
    let presentation: ProviderConnectionPresentation
    let isInstalling: Bool
    let isBusy: Bool
    let onConnect: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            providerIcon

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(presentation.providerName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(isInstalling ? "Connecting…" : presentation.label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isInstalling ? Color.secondary : stateColor)
                }
                Text(presentation.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isInstalling {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 68)
                    .accessibilityLabel("Connecting \(presentation.providerName)")
            } else if let action = presentation.action {
                Button(action.title, action: onConnect)
                    .font(.system(size: 12))
                    .controlSize(.small)
                    .disabled(isBusy)
                    .accessibilityLabel(presentation.accessibilityActionLabel ?? action.title)
            }
        }
        .frame(minHeight: 72)
        .accessibilityElement(children: .contain)
    }

    private var providerIcon: some View {
        Group {
            if let image = ProviderBrandImages.inAppImage(
                for: presentation.provider,
                isDark: colorScheme == .dark
            ) {
                Image(nsImage: image)
                    .resizable()
                    .renderingMode(.original)
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "terminal")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 22, height: 22)
        .accessibilityHidden(true)
    }

    private var stateColor: Color {
        switch presentation.tone {
        case .neutral: .secondary
        case .positive: .green
        case .attention: .orange
        }
    }
}
