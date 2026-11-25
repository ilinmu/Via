import AppKit
import SwiftUI
import ViaCore

struct NetworkSetupForm: View {
    @Binding var draft: NetworkDraft
    let availableNetworks: [String]
    let isScanning: Bool
    let scanOutcome: ScanOutcome
    let canScan: Bool
    let onScan: () -> Void
    var currentSSID: String? = nil
    var showValidation = false

    @ObservedObject var i18n = LocalizationManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 10) {
                Text(i18n.localizedString("network_scan_hint"))
                    .font(PanelFont.caption)
                    .foregroundStyle(PanelColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)

                ScanButton(
                    isScanning: isScanning,
                    isEnabled: canScan,
                    action: onScan
                )
            }

            if let scanMessage {
                Text(scanMessage)
                    .font(PanelFont.caption)
                    .foregroundStyle(PanelColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !canScan {
                Text(i18n.localizedString("permission_required_for_automation"))
                    .font(PanelFont.caption)
                    .foregroundStyle(PanelColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            NetworkEditor(
                titleKey: "priority_network",
                icon: "arrow.up.circle",
                ssid: $draft.ssidP,
                password: $draft.passwordP,
                networks: availableNetworks,
                currentSSID: currentSSID,
                validationMessage: fieldError(for: .missingPrimary)
            )

            Divider()

            NetworkEditor(
                titleKey: "backup_network",
                icon: "arrow.down.circle",
                ssid: $draft.ssidB,
                password: $draft.passwordB,
                networks: availableNetworks,
                currentSSID: currentSSID,
                validationMessage: fieldError(for: .missingBackup)
            )

            if showValidation, draft.validation == .sameNetwork {
                Text(i18n.localizedString("same_network_error"))
                    .font(PanelFont.caption)
                    .foregroundStyle(PanelColor.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(i18n.localizedString("password_optional_hint"))
                .font(PanelFont.caption)
                .foregroundStyle(PanelColor.textSecondary)
        }
    }

    private func fieldError(for validation: NetworkDraft.Validation) -> String? {
        guard showValidation, draft.validation == validation else { return nil }
        return i18n.localizedString(validation.errorKey ?? "")
    }

    private var scanMessage: String? {
        switch scanOutcome {
        case .idle, .scanning:
            return nil
        case let .success(count):
            return i18n.networksFound(count)
        case .empty:
            return i18n.localizedString("no_networks_found")
        case .permissionPending:
            return i18n.localizedString("permission_pending")
        case .permissionDenied:
            return i18n.localizedString("location_permission_hint")
        }
    }
}

private struct NetworkEditor: View {
    let titleKey: String
    let icon: String
    @Binding var ssid: String
    @Binding var password: String
    let networks: [String]
    var currentSSID: String? = nil
    var validationMessage: String? = nil

    @ObservedObject var i18n = LocalizationManager.shared
    @State private var showPassword = false
    @State private var showSuggestions = false

    private var isConfigured: Bool {
        !ssid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var suggestionListHeight: CGFloat {
        let contentHeight = CGFloat(networks.count) * 31 - 1
        return min(max(contentHeight, 30), 200)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tint)

                Text(i18n.localizedString(titleKey))
                    .font(PanelFont.bodyStrong)

                Spacer(minLength: 8)

                Text(i18n.localizedString(isConfigured ? "configured" : "not_configured"))
                    .font(PanelFont.caption)
                    .foregroundStyle(PanelColor.textSecondary)
            }

            HStack(spacing: 8) {
                FieldContainer {
                    TextField(i18n.localizedString("ssid_placeholder"), text: $ssid)
                        .textFieldStyle(.plain)
                        .font(PanelFont.body)
                        .accessibilityLabel(i18n.localizedString("ssid_label"))
                }

                if !networks.isEmpty {
                    Button {
                        showSuggestions.toggle()
                    } label: {
                        Image(systemName: showSuggestions ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(PanelColor.textSecondary)
                            .frame(width: 34, height: PanelLayout.controlHeight)
                            .background(
                                PanelColor.surface,
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(PanelColor.separator, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(i18n.localizedString("select_network"))
                }
            }

            if showSuggestions && !networks.isEmpty {
                VStack(spacing: 0) {
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(networks.enumerated()), id: \.element) { index, network in
                                Button {
                                    ssid = network
                                    showSuggestions = false
                                } label: {
                                    HStack(spacing: 8) {
                                        Text(network)
                                            .font(PanelFont.body)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                        Spacer(minLength: 8)
                                        if network == ssid {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 11, weight: .semibold))
                                                .foregroundStyle(.tint)
                                        }
                                    }
                                    .padding(.horizontal, 10)
                                    .frame(height: 30)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                if index < networks.count - 1 {
                                    Divider()
                                }
                            }
                        }
                    }
                    .frame(height: suggestionListHeight)
                }
                .background(
                    PanelColor.surface,
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(PanelColor.separator, lineWidth: 1)
                )
            }

            FieldContainer {
                PasswordInputField(
                    text: $password,
                    placeholder: i18n.localizedString("password"),
                    isSecure: !showPassword,
                    accessibilityLabel: i18n.localizedString("password")
                )
                .id(showPassword)
                .frame(maxWidth: .infinity)

                Button(action: { showPassword.toggle() }) {
                    Image(systemName: showPassword ? "eye.slash" : "eye")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(PanelColor.textSecondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    i18n.localizedString(showPassword ? "hide_password" : "show_password")
                )
            }
        }
    }
}
