#!/usr/bin/env swift

// Local diagnostic script for exercising the switching rules without UI.
// It is not part of the SwiftPM targets, the app bundle, or the release flow.
import Foundation
import CoreWLAN
import Darwin

// Simple command-line version that doesn't require SwiftUI/Cocoa
class SimpleWifiMonitor {
    private var client: CWWiFiClient
    private var interface: CWInterface?
    
    var ssidP: String = ""
    var passwordP: String = ""
    var ssidB: String = ""
    var passwordB: String = ""
    var checkInterval: Double = 60.0
    
    init() {
        self.client = CWWiFiClient.shared()
        self.interface = client.interface()
    }
    
    func log(_ message: String) {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        let timestamp = formatter.string(from: Date())
        print("[\(timestamp)] \(message)")
    }
    
    func checkAndConnect() {
        guard let interface = self.interface else {
            log("Error: No Wi-Fi interface found.")
            return
        }
        
        if ssidP.isEmpty || ssidB.isEmpty {
            log("Error: SSIDs not configured.")
            return
        }
        
        let currentSSID = interface.ssid()
        log("Current network: \(currentSSID ?? "None")")
        
        // If already connected to P, we are good
        if currentSSID == ssidP {
            log("Connected to preferred network P (\(ssidP)).")
            return
        }
        
        // Scan for networks
        log("Scanning...")
        do {
            let networks = try interface.scanForNetworks(withSSID: nil)
            
            // Check for P
            if let targetNetworkP = strongestNetwork(named: ssidP, from: networks) {
                log("Found network P (\(ssidP)). Connecting...")
                try interface.associate(to: targetNetworkP, password: passwordP)
                log("Successfully connected to \(ssidP).")
                return
            }
            
            // If P not found and not connected to B, check for B
            if currentSSID != ssidB {
                if let targetNetworkB = strongestNetwork(named: ssidB, from: networks) {
                    log("Network P not found. Found network B (\(ssidB)). Connecting...")
                    try interface.associate(to: targetNetworkB, password: passwordB)
                    log("Successfully connected to \(ssidB).")
                    return
                } else {
                    log("Neither network P nor B found.")
                }
            } else {
                log("Connected to backup network B (\(ssidB)). Network P not found.")
            }
            
        } catch {
            log("Error: \(error.localizedDescription)")
        }
    }
    
    func start() {
        checkInterval = max(5.0, checkInterval)
        log("Via Monitor Started")
        log("Priority Network (P): \(ssidP)")
        log("Backup Network (B): \(ssidB)")
        log("Check Interval: \(checkInterval) seconds")
        log("Press Ctrl+C to stop")
        
        // Set up signal handler for clean shutdown
        signal(SIGINT) { _ in
            print("\n[INFO] Stopping monitor...")
            exit(0)
        }
        
        // Run immediately
        checkAndConnect()
        
        // Keep the timer alive on the main run loop.
        _ = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            self?.checkAndConnect()
        }
        RunLoop.current.run()
    }

    private func strongestNetwork(named ssid: String, from networks: Set<CWNetwork>) -> CWNetwork? {
        networks
            .filter { $0.ssid == ssid }
            .max(by: { $0.rssiValue < $1.rssiValue })
    }
}

/// Reads a password without echoing it to the terminal or writing it to shell
/// history. Passwords are never accepted as command-line arguments because
/// those are visible to other local processes through `ps`.
func readPassword(prompt: String) -> String {
    print(prompt, terminator: " ")
    fflush(stdout)

    var original = termios()
    guard tcgetattr(STDIN_FILENO, &original) == 0 else {
        return readLine() ?? ""
    }

    var hidden = original
    hidden.c_lflag &= ~tcflag_t(ECHO)
    tcsetattr(STDIN_FILENO, TCSAFLUSH, &hidden)
    defer {
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &original)
        print("")
    }

    return readLine() ?? ""
}

// Parse command line arguments or use default values
let monitor = SimpleWifiMonitor()
let arguments = Array(CommandLine.arguments.dropFirst())

if arguments.count >= 3, Double(arguments[2]) == nil {
    fputs(
        "Passwords are not accepted as command-line arguments. "
            + "Usage: auto-wifi-cli <SSID-P> <SSID-B> [interval-seconds]\n",
        stderr
    )
    exit(2)
}

if arguments.count >= 2 {
    monitor.ssidP = arguments[0]
    monitor.ssidB = arguments[1]
    if arguments.count >= 3, let interval = Double(arguments[2]) {
        monitor.checkInterval = interval
    }
    monitor.passwordP = readPassword(prompt: "Priority Network (P) Password:")
    monitor.passwordB = readPassword(prompt: "Backup Network (B) Password:")
} else {
    print("Via Monitor - Command Line Version")
    print("=========================================")
    print("Enter Priority Network (P) SSID:")
    monitor.ssidP = readLine() ?? ""
    print("Enter Backup Network (B) SSID:")
    monitor.ssidB = readLine() ?? ""
    monitor.passwordP = readPassword(prompt: "Priority Network (P) Password:")
    monitor.passwordB = readPassword(prompt: "Backup Network (B) Password:")
    print("Enter Check Interval in seconds (default 60):")
    if let input = readLine(), let interval = Double(input) {
        monitor.checkInterval = interval
    }
    print("")
}

monitor.start()
