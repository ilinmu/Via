import AppKit
import CoreLocation
import SwiftUI
import AutoWifiCore

public struct SettingsView: View {
    public static let panelWidth: CGFloat = PanelLayout.width

    @ObservedObject var appState: AppState
    @ObservedObject var wifiManager: WifiManager
    @ObservedObject var metrics: PanelMetrics
    @ObservedObject var model: PanelModel
    @ObservedObject var i18n = LocalizationManager.shared

    var onHeightChange: (CGFloat) -> Void

    @State private var chromeHeight: CGFloat
    @State private var contentHeight: CGFloat = 320

    @MainActor
    public init(
        appState: AppState,
        wifiManager: WifiManager,
        metrics: PanelMetrics,
        model: PanelModel,
        onHeightChange: @escaping (CGFloat) -> Void = { _ in }
    ) {
        self.appState = appState
        self.wifiManager = wifiManager
        self.metrics = metrics
        self.model = model
        self.onHeightChange = onHeightChange
        _chromeHeight = State(initialValue: model.route == .tabs ? 84 : 49)
    }

    public var body: some View {
        VStack(spacing: 0) {
            chrome
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: ChromeHeightKey.self,
                            value: proxy.size.height
                        )
                    }
                )

            ScrollView(.vertical) {
                activeContent
                    .id(contentID)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: ContentHeightKey.self,
                                value: proxy.size.height
                            )
                        }
                    )
            }
            .scrollIndicators(.automatic)
        }
        .frame(width: PanelLayout.width)
        .frame(height: totalHeight)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(
            RoundedRectangle(
                cornerRadius: PanelLayout.cornerRadius,
                style: .continuous
            )
        )
        .overlay(
            RoundedRectangle(
                cornerRadius: PanelLayout.cornerRadius,
                style: .continuous
            )
            .stroke(Color(nsColor: .separatorColor).opacity(0.7), lineWidth: 1)
        )
        .onPreferenceChange(ChromeHeightKey.self) { newValue in
            guard newValue > 1, abs(newValue - chromeHeight) > 0.5 else { return }
            chromeHeight = newValue
        }
        .onPreferenceChange(ContentHeightKey.self) { newValue in
            guard newValue > 1, abs(newValue - contentHeight) > 0.5 else { return }
            contentHeight = newValue
        }
        .onChange(of: totalHeight) { newValue in
            onHeightChange(newValue)
        }
        .onAppear {
            model.refreshAll()
            onHeightChange(totalHeight)
        }
        .onChange(of: wifiManager.locationAuthorizationStatus) { status in
            model.handleAuthorizationChange(status)
        }
    }

    private var totalHeight: CGFloat {
        let availableForContent = max(0, metrics.maxHeight - chromeHeight)
        let visibleContent = min(max(contentHeight, 1), availableForContent)
        return max(
            min(chromeHeight + visibleContent, metrics.maxHeight),
            PanelLayout.minHeight
        )
    }

    private var contentID: String {
        switch model.route {
        case .onboarding:
            return "onboarding-\(model.step.rawValue)"
        case .tabs:
            return "tab-\(model.tab.rawValue)"
        }
    }

    private var chrome: some View {
        VStack(spacing: 0) {
            header

            if model.route == .tabs {
                PanelTabBar(selection: $model.tab)
                    .padding(.horizontal, PanelLayout.horizontalPadding)
                    .padding(.bottom, 8)

                if let permissionMessage {
                    WarningBanner(
                        message: permissionMessage,
                        systemImage: "location.slash",
                        actionTitle: permissionActionTitle
                    ) {
                        handlePermissionAction()
                    }
                    .padding(.horizontal, PanelLayout.horizontalPadding)
                    .padding(.bottom, 8)
                }

                if !model.isConfigurationComplete {
                    WarningBanner(
                        message: i18n.localizedString("setup_required_hint"),
                        actionTitle: i18n.localizedString("continue_setup")
                    ) {
                        model.resumeOnboarding()
                    }
                    .padding(.horizontal, PanelLayout.horizontalPadding)
                    .padding(.bottom, 8)
                }
            }

            Divider()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.tint)

            Text(i18n.localizedString("app_title"))
                .font(.headline)

            Spacer(minLength: 8)

            if model.route == .onboarding {
                Text(stepText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if model.step != .finish {
                    Button(i18n.localizedString("onboarding_skip")) {
                        model.skipOnboarding()
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, PanelLayout.horizontalPadding)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var stepText: String {
        String(
            format: i18n.localizedString("onboarding_step_format"),
            model.step.rawValue + 1,
            SetupStep.allCases.count
        )
    }

    @ViewBuilder
    private var activeContent: some View {
        switch model.route {
        case .tabs:
            switch model.tab {
            case .status:
                StatusTabView(
                    appState: appState,
                    wifiManager: wifiManager,
                    model: model
                )
            case .networks:
                NetworksTabView(
                    appState: appState,
                    model: model
                )
            case .settings:
                SettingsTabView(
                    appState: appState,
                    model: model
                )
            }
        case .onboarding:
            OnboardingView(
                wifiManager: wifiManager,
                model: model
            )
        }
    }

    private var permissionMessage: String? {
        switch wifiManager.locationAuthorizationStatus {
        case .authorizedAlways:
            return nil
        case .notDetermined:
            return i18n.localizedString("permission_required_for_automation")
        case .denied, .restricted, .authorizedWhenInUse:
            return i18n.localizedString("location_permission_hint")
        @unknown default:
            return i18n.localizedString("location_permission_hint")
        }
    }

    private var permissionActionTitle: String {
        wifiManager.locationAuthorizationStatus == .notDetermined
            ? i18n.localizedString("permission_grant")
            : i18n.localizedString("permission_open_settings")
    }

    private func handlePermissionAction() {
        if wifiManager.locationAuthorizationStatus == .notDetermined {
            wifiManager.requestPermissions()
        } else {
            SystemLinks.openLocationSettings()
        }
    }
}

private struct ChromeHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
