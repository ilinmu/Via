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
    var showValidation = false

    @ObservedObject var i18n = LocalizationManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 10) {
                Text(i18n.localizedString("network_scan_hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !canScan {
                Text(i18n.localizedString("permission_required_for_automation"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            NetworkEditor(
                titleKey: "priority_network",
                icon: "arrow.up.circle",
                ssid: $draft.ssidP,
                password: $draft.passwordP,
                networks: availableNetworks,
                isScanning: isScanning,
                canScan: canScan,
                onScan: onScan
            )

            Divider()

            NetworkEditor(
                titleKey: "backup_network",
                icon: "arrow.down.circle",
                ssid: $draft.ssidB,
                password: $draft.passwordB,
                networks: availableNetworks,
                isScanning: isScanning,
                canScan: canScan,
                onScan: onScan
            )

            if showValidation, let errorKey = draft.validation.errorKey {
                Text(i18n.localizedString(errorKey))
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(i18n.localizedString("password_optional_hint"))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var scanMessage: String? {
        switch scanOutcome {
        case .idle, .scanning:
            return nil
        case let .success(count):
            return String(
                format: i18n.localizedString("networks_found_count"),
                count
            )
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
    let isScanning: Bool
    let canScan: Bool
    let onScan: () -> Void

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
                    .font(.subheadline.weight(.semibold))

                Spacer(minLength: 8)

                Text(i18n.localizedString(isConfigured ? "configured" : "not_configured"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                FieldContainer {
                    TextField(i18n.localizedString("ssid_placeholder"), text: $ssid)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .accessibilityLabel(i18n.localizedString("ssid_label"))
                }

                if !networks.isEmpty {
                    Button {
                        showSuggestions.toggle()
                    } label: {
                        Image(systemName: showSuggestions ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 34, height: PanelLayout.controlHeight)
                            .background(
                                Color(nsColor: .textBackgroundColor),
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(i18n.localizedString("select_network"))
                }
            }

            if showSuggestions && !networks.isEmpty {
                VStack(spacing: 0) {
                    // Scan from inside the list, so refreshing does not mean
                    // scrolling back to the scan row at the top of the form.
                    Button(action: onScan) {
                        HStack(spacing: 6) {
                            if isScanning {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "wifi")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            Text(i18n.localizedString("scan_networks"))
                                .font(.system(size: 13))
                            Spacer(minLength: 8)
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!canScan || isScanning)
                    .accessibilityLabel(i18n.localizedString("scan_networks"))

                    Divider()

                    ScrollView(.vertical) {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(networks.enumerated()), id: \.element) { index, network in
                                Button {
                                    ssid = network
                                    showSuggestions = false
                                } label: {
                                    HStack(spacing: 8) {
                                        Text(network)
                                            .font(.system(size: 13))
                                            .lineLimit(1)
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
                    Color(nsColor: .textBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
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
                        .foregroundStyle(.secondary)
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
