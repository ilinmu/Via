import AppKit
import SwiftUI
import AutoWifiCore

struct PanelTabBar: View {
    @Binding var selection: PanelTab
    @ObservedObject var i18n = LocalizationManager.shared

    var body: some View {
        Picker("", selection: $selection) {
            ForEach(PanelTab.allCases) { tab in
                Text(i18n.localizedString(tab.titleKey))
                    .tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityLabel(i18n.localizedString("tab_accessibility_label"))
    }
}

struct FieldContainer<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 6) {
            content
        }
        .padding(.horizontal, 10)
        .frame(height: PanelLayout.controlHeight)
        .background(
            Color(nsColor: .textBackgroundColor),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }
}

struct ScanButton: View {
    let isScanning: Bool
    let isEnabled: Bool
    let action: () -> Void
    @ObservedObject var i18n = LocalizationManager.shared

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isScanning {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
                Text(i18n.localizedString(isScanning ? "scanning" : "scan_networks"))
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(isScanning || !isEnabled)
        .accessibilityLabel(i18n.localizedString(isScanning ? "scanning" : "scan_networks"))
    }
}
