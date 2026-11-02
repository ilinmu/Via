import Combine
import CoreLocation
import Foundation
import AutoWifiCore

@MainActor
public final class PanelModel: ObservableObject {
    let appState: AppState
    let wifiManager: WifiManager

    @Published var route: PanelRoute
    @Published var tab: PanelTab = .status
    @Published var step: SetupStep = .permission
    @Published var draft: NetworkDraft
    @Published var intervalDraft: String
    @Published private(set) var availableNetworks: [String] = []
    @Published private(set) var isScanning = false
    @Published private(set) var scanOutcome: ScanOutcome = .idle
    @Published var isStarting = false

    init(appState: AppState, wifiManager: WifiManager) {
        self.appState = appState
        self.wifiManager = wifiManager

        let configured = !appState.ssidP.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !appState.ssidB.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        route = configured ? .tabs : .onboarding
        step = wifiManager.locationAuthorizationStatus == .authorizedAlways ? .networks : .permission
        draft = NetworkDraft(appState: appState)
        intervalDraft = Self.intervalText(appState.checkInterval)
    }

    var isConfigurationComplete: Bool {
        !appState.ssidP.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !appState.ssidB.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var permissionReady: Bool {
        wifiManager.locationAuthorizationStatus == .authorizedAlways
    }

    var canAutomate: Bool {
        isConfigurationComplete && permissionReady
    }

    var canScan: Bool {
        permissionReady
    }

    var hasUnsavedDraft: Bool {
        draft.hasChanges
    }

    func scan() {
        guard !isScanning else { return }

        switch wifiManager.locationAuthorizationStatus {
        case .authorizedAlways:
            break
        case .notDetermined:
            scanOutcome = .permissionPending
            wifiManager.requestPermissions()
            return
        case .denied, .restricted, .authorizedWhenInUse:
            scanOutcome = .permissionDenied
            return
        @unknown default:
            scanOutcome = .permissionDenied
            return
        }

        isScanning = true
        scanOutcome = .scanning
        appState.log(LocalizationManager.shared.localizedString("scanning"))

        Task { @MainActor in
            let networks = await wifiManager.getAvailableNetworks()
            isScanning = false

            if networks.isEmpty {
                scanOutcome = .empty
                appState.log(LocalizationManager.shared.localizedString("permission_hint"))
            } else {
                availableNetworks = networks
                scanOutcome = .success(networks.count)
                appState.log(LocalizationManager.shared.localizedString("scan_success"))
            }
        }
    }

    func startMonitoring() {
        guard !isStarting, canAutomate else { return }

        isStarting = true
        Task { @MainActor in
            await wifiManager.startMonitoring()
            isStarting = false
        }
    }

    func stopMonitoring() {
        guard !isStarting else { return }
        wifiManager.stopMonitoring()
    }

    @discardableResult
    func commitDraft() -> Bool {
        guard draft.isValid else { return false }
        draft.commit(to: appState)
        return true
    }

    func commitInterval() {
        let trimmed = intervalDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if let value = Double(trimmed), value.isFinite {
            appState.checkInterval = value
        }
        intervalDraft = Self.intervalText(appState.checkInterval)
    }

    func syncIntervalDraft() {
        intervalDraft = Self.intervalText(appState.checkInterval)
    }

    func refreshAll() {
        wifiManager.refreshStatus()
        appState.refreshLaunchAtLoginStatus()
    }

    func handleAuthorizationChange(_ status: CLAuthorizationStatus) {
        switch status {
        case .authorizedAlways:
            guard availableNetworks.isEmpty, !isScanning, !appState.isRunning else { return }
            scan()
        case .denied, .restricted, .authorizedWhenInUse:
            if scanOutcome == .permissionPending {
                scanOutcome = .permissionDenied
            }
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }

    func advanceStep() {
        switch step {
        case .permission:
            step = .networks
        case .networks:
            step = .finish
        case .finish:
            break
        }
    }

    func goBack() {
        switch step {
        case .permission:
            break
        case .networks:
            step = .permission
        case .finish:
            step = .networks
        }
    }

    func startOnboarding(step: SetupStep) {
        draft.reload(from: appState)
        self.step = step
        route = .onboarding
    }

    func resumeOnboarding() {
        step = permissionReady ? .networks : .permission
        route = .onboarding
    }

    func skipOnboarding() {
        route = .tabs
        tab = .networks
    }

    @discardableResult
    func finishOnboarding(enableMonitoring: Bool) -> Bool {
        guard commitDraft() else { return false }

        route = .tabs
        tab = .status

        if enableMonitoring {
            startMonitoring()
        }
        return true
    }

    static func intervalText(_ value: Double) -> String {
        String(Int(value.rounded()))
    }
}
