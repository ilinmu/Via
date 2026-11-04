import Foundation
import ViaCore

// Minimal executable smoke test for the Rust policy core. It intentionally
// avoids XCTest so it can run with Command Line Tools only.
//
//   cargo build --manifest-path core/Cargo.toml -p via-ffi --release
//   swift run PolicySmoke

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("policy smoke failed: \(message)\n", stderr)
        exit(1)
    }
}

guard let engine = WifiPolicyEngine(ssidP: "P", ssidB: "B") else {
    fputs("policy smoke failed: could not load libvia_core.dylib\n", stderr)
    exit(1)
}

var actions = engine.start(permission: .authorized, currentSSID: "X")
require(actions == [.scan(.priorityCheck)], "expected priority scan, got \(actions)")

actions = engine.scanResult(found: true)
require(
    actions == [.associate(ssid: "P", role: .priority)],
    "expected priority association, got \(actions)"
)

let generation = engine.associationStarted(ssid: "P")
_ = engine.associationResult(ssid: "P", generation: generation, outcome: .success)
require(engine.snapshot().role == .priority, "expected role priority after association")

// A manual switch to B while P is visible must stop monitoring.
actions = engine.observedChange(previous: "P", new: "B")
require(actions == [.scan(.priorityClassification)], "expected classification scan, got \(actions)")

actions = engine.classificationResult(priorityVisible: true)
require(actions.contains(.stop(.manualOverrideBackup)), "expected manual override stop, got \(actions)")
require(!engine.snapshot().running, "engine should be stopped after manual override")

// Cooldown for B must not block a later recovery to P.
let recovery = WifiPolicyEngine(ssidP: "P", ssidB: "B")
require(recovery != nil, "could not create second engine")
if let recovery {
    _ = recovery.start(permission: .authorized, currentSSID: "B")
    recovery.setPersistedCooldown(target: "B", until: Date().addingTimeInterval(120))
    actions = recovery.checkBegin(permission: .authorized, currentSSID: "B")
    require(actions == [.scan(.priorityCheck)], "expected priority scan despite B cooldown, got \(actions)")
    actions = recovery.scanResult(found: true)
    require(
        actions == [.associate(ssid: "P", role: .priority)],
        "expected priority association despite B cooldown, got \(actions)"
    )
}

print("policy smoke ok")
