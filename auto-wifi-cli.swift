#!/usr/bin/env swift

import Foundation
import CoreWLAN

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
        log("Auto-Wifi Monitor Started")
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

// Parse command line arguments or use default values
let monitor = SimpleWifiMonitor()

// Read configuration from command line or use interactive mode
if CommandLine.arguments.count >= 5 {
    monitor.ssidP = CommandLine.arguments[1]
    monitor.passwordP = CommandLine.arguments[2]
    monitor.ssidB = CommandLine.arguments[3]
    monitor.passwordB = CommandLine.arguments[4]
    if CommandLine.arguments.count >= 6 {
        monitor.checkInterval = Double(CommandLine.arguments[5]) ?? 60.0
    }
} else {
    print("Auto-Wifi Monitor - Command Line Version")
    print("=========================================")
    print("Enter Priority Network (P) SSID:")
    monitor.ssidP = readLine() ?? ""
    print("Enter Priority Network (P) Password:")
    monitor.passwordP = readLine() ?? ""
    print("Enter Backup Network (B) SSID:")
    monitor.ssidB = readLine() ?? ""
    print("Enter Backup Network (B) Password:")
    monitor.passwordB = readLine() ?? ""
    print("Enter Check Interval in seconds (default 60):")
    if let input = readLine(), let interval = Double(input) {
        monitor.checkInterval = interval
    }
    print("")
}

monitor.start()
