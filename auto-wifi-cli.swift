#!/usr/bin/env swift

import Foundation
import CoreWLAN

// Simple command-line version that doesn't require SwiftUI/Cocoa
class SimpleWifiMonitor {
    private var client: CWWiFiClient
    private var interface: CWInterface?
    
    var ssidP: String = ""
    var passwordA: String = ""
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
            let networkMap = Dictionary(grouping: networks, by: { $0.ssid ?? "" })
            
            // Check for P
            if let networksP = networkMap[ssidP], let targetNetworkP = networksP.first {
                log("Found network P (\(ssidP)). Connecting...")
                try interface.associate(to: targetNetworkP, password: passwordP)
                log("Successfully connected to \(ssidP).")
                return
            }
            
            // If P not found and not connected to B, check for B
            if currentSSID != ssidB {
                if let networksB = networkMap[ssidB], let targetNetworkB = networksB.first {
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
        
        // Run in loop
        RunLoop.current.run()
        Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            self?.checkAndConnect()
        }
        RunLoop.current.run()
    }
}

// Parse command line arguments or use default values
let monitor = SimpleWifiMonitor()

// Read configuration from command line or use interactive mode
if CommandLine.arguments.count >= 5 {
    monitor.ssidP = CommandLine.arguments[1]
    monitor.passwordA = CommandLine.arguments[2]
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
    monitor.passwordA = readLine() ?? ""
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
