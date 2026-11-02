import Combine
import CoreLocation
import Foundation
import NetworkExtension

@MainActor
final class WifiController: ObservableObject {
    @Published var ssidP: String
    @Published var ssidB: String
    @Published var passwordP: String
    @Published var passwordB: String
    @Published var language: String {
        didSet { defaults.set(language, forKey: "language") }
    }
    @Published var checkInterval: Int {
        didSet {
            defaults.set(checkInterval, forKey: "checkInterval")
            if isRunning {
                scheduleTimer()
            }
        }
    }
    @Published var isRunning = false
    @Published var currentSSID: String?
    @Published var role: PolicyRole = .none
    @Published var permission: CLAuthorizationStatus
    @Published var message: String
    @Published var showOnboarding: Bool
    @Published var isChecking = false

    private let defaults: UserDefaults
    private let keychain: KeychainStore
    private let locationManager: CLLocationManager
    private var policy: PolicyEngine?
    private var timer: Timer?
    private var lastSSID: String?

    init() {
        let defaults = UserDefaults.standard
        let keychain = KeychainStore()
        let locationManager = CLLocationManager()

        let storedPriority = defaults.string(forKey: "ssidP") ?? ""
        let storedBackup = defaults.string(forKey: "ssidB") ?? ""
        let storedInterval = defaults.integer(forKey: "checkInterval")
        let priority = storedPriority.trimmingCharacters(in: .whitespacesAndNewlines)
        let backup = storedBackup.trimmingCharacters(in: .whitespacesAndNewlines)

        self.defaults = defaults
        self.keychain = keychain
        self.locationManager = locationManager

        ssidP = storedPriority
        ssidB = storedBackup
        passwordP = keychain.string(for: "passwordP") ?? ""
        passwordB = keychain.string(for: "passwordB") ?? ""
        language = defaults.string(forKey: "language") ?? "zh"
        checkInterval = storedInterval == 0 ? 15 : max(5, storedInterval)
        permission = locationManager.authorizationStatus
        message = ""
        showOnboarding = priority.isEmpty || backup.isEmpty

        if !priority.isEmpty, !backup.isEmpty,
           priority.caseInsensitiveCompare(backup) != .orderedSame {
            policy = PolicyEngine(ssidP: storedPriority, ssidB: storedBackup)
        }
    }

    var isComplete: Bool {
        let priority = ssidP.trimmingCharacters(in: .whitespacesAndNewlines)
        let backup = ssidB.trimmingCharacters(in: .whitespacesAndNewlines)
        return !priority.isEmpty
            && !backup.isEmpty
            && priority.caseInsensitiveCompare(backup) != .orderedSame
    }

    @discardableResult
    func save() -> Bool {
        let priority = ssidP.trimmingCharacters(in: .whitespacesAndNewlines)
        let backup = ssidB.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !priority.isEmpty else {
            message = L10n.t("missing_primary", language)
            return false
        }
        guard !backup.isEmpty else {
            message = L10n.t("missing_backup", language)
            return false
        }
        guard priority.caseInsensitiveCompare(backup) != .orderedSame else {
            message = L10n.t("same_network", language)
            return false
        }

        ssidP = priority
        ssidB = backup
        checkInterval = min(3600, max(5, checkInterval))
        defaults.set(ssidP, forKey: "ssidP")
        defaults.set(ssidB, forKey: "ssidB")
        defaults.set(checkInterval, forKey: "checkInterval")
        defaults.set(language, forKey: "language")
        keychain.set(passwordP.isEmpty ? nil : passwordP, for: "passwordP")
        keychain.set(passwordB.isEmpty ? nil : passwordB, for: "passwordB")

        if policy == nil {
            policy = PolicyEngine(ssidP: ssidP, ssidB: ssidB)
        }
        policy?.setConfig(ssidP: ssidP, ssidB: ssidB)
        message = L10n.t("saved", language)
        return true
    }

    func requestPermission() {
        locationManager.requestWhenInUseAuthorization()
    }

    func refreshPermission() {
        permission = locationManager.authorizationStatus
    }

    func startMonitoring() async {
        guard save() else {
            return
        }

        refreshPermission()
        guard permission == .authorizedAlways || permission == .authorizedWhenInUse else {
            requestPermission()
            message = L10n.t("permission_required", language)
            return
        }

        policy = PolicyEngine(ssidP: ssidP, ssidB: ssidB)
        guard let policy else {
            message = L10n.t("permission_required", language)
            return
        }

        isRunning = true
        defaults.set(true, forKey: "isRunning")
        message = L10n.t("monitor_started", language)

        let current = await fetchCurrentSSID()
        currentSSID = current
        lastSSID = current
        await execute(
            policy.start(permission: permissionCode, currentSSID: current),
            policy: policy
        )
        updateRole(policy)
        scheduleTimer()
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        if let policy {
            _ = policy.stop()
        }
        isRunning = false
        defaults.set(false, forKey: "isRunning")
        message = L10n.t("monitor_stopped", language)
    }

    func checkNow() async {
        guard isRunning, !isChecking, let policy else {
            return
        }

        isChecking = true
        defer { isChecking = false }

        refreshPermission()
        let current = await fetchCurrentSSID()
        let actions: [PolicyAction]
        if lastSSID != current {
            actions = policy.observedChange(previous: lastSSID, new: current)
        } else {
            actions = policy.checkBegin(permission: permissionCode, currentSSID: current)
        }

        currentSSID = current
        lastSSID = current
        await execute(actions, policy: policy)
        updateRole(policy)
    }

    func useCurrentNetwork() async {
        guard let current = await fetchCurrentSSID() else {
            message = L10n.t("no_current", language)
            return
        }
        currentSSID = current
        if ssidP.isEmpty {
            ssidP = current
        } else {
            ssidB = current
        }
    }

    private func execute(_ actions: [PolicyAction], policy: PolicyEngine) async {
        for action in actions {
            switch action {
            case .scan(let purpose):
                let target = purpose == .priorityCheck || purpose == .priorityClassification
                    ? ssidP
                    : ssidB
                let visible = currentSSID == target
                let next: [PolicyAction]
                switch purpose {
                case .priorityClassification:
                    next = policy.classificationResult(priorityVisible: visible)
                case .backupFailover, .backupRecovery:
                    next = policy.backupScanResult(found: visible)
                default:
                    next = policy.scanResult(found: visible)
                }
                await execute(next, policy: policy)

            case .associate(let ssid, _):
                let generation = policy.associationStarted(ssid: ssid)
                let joined = await join(ssid: ssid)
                if joined {
                    currentSSID = ssid
                    lastSSID = ssid
                }
                await execute(
                    policy.associationResult(
                        ssid: ssid,
                        generation: generation,
                        outcome: joined ? 0 : 2
                    ),
                    policy: policy
                )

            case .checkNow:
                break

            case .stop:
                timer?.invalidate()
                timer = nil
                isRunning = false
                defaults.set(false, forKey: "isRunning")
                message = L10n.t("monitor_stopped", language)

            case .waitForPermission:
                message = L10n.t("permission_required", language)

            case .log(let event):
                message = logText(event)

            case .refreshStatus:
                updateRole(policy)
            }
        }
    }

    private func join(ssid: String) async -> Bool {
        if currentSSID == ssid {
            return true
        }

        let password = ssid == ssidP ? passwordP : passwordB
        let configuration: NEHotspotConfiguration
        if password.isEmpty {
            configuration = NEHotspotConfiguration(ssid: ssid)
        } else {
            configuration = NEHotspotConfiguration(
                ssid: ssid,
                passphrase: password,
                isWEP: false
            )
        }
        configuration.joinOnce = true

        return await withCheckedContinuation { continuation in
            NEHotspotConfigurationManager.shared.apply(configuration) { error in
                continuation.resume(returning: error == nil)
            }
        }
    }

    private func fetchCurrentSSID() async -> String? {
        await withCheckedContinuation { continuation in
            NEHotspotNetwork.fetchCurrent { network in
                continuation.resume(returning: network?.ssid)
            }
        }
    }

    private func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(
            withTimeInterval: TimeInterval(max(5, checkInterval)),
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.checkNow()
            }
        }
    }

    private func updateRole(_ policy: PolicyEngine) {
        role = policy.snapshot().role
    }

    private var permissionCode: PolicyPermission {
        switch permission {
        case .authorizedAlways, .authorizedWhenInUse:
            return .authorized
        case .denied, .restricted:
            return .denied
        case .notDetermined:
            return .unknown
        @unknown default:
            return .unknown
        }
    }

    private func logText(_ event: PolicyLogEvent) -> String {
        switch event {
        case .started:
            return L10n.t("monitor_started", language)
        case .stopped:
            return L10n.t("monitor_stopped", language)
        case .permissionRequired:
            return L10n.t("permission_required", language)
        case .priorityConnected:
            return L10n.t("role_priority", language)
        case .automaticFailover:
            return L10n.t("role_backup", language)
        default:
            return "\(L10n.t("message", language)): \(event)"
        }
    }
}
