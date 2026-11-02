//! Shared, platform-neutral Wi-Fi switching policy.
//!
//! The crate is deliberately dependency-free and does no I/O. Native shells
//! (macOS/CoreWLAN, Windows/WlanAPI, Android/WifiManager, iOS/NetworkExtension)
//! translate their events into [`Engine`] calls and execute the returned
//! [`Action`]s.

pub mod engine;
pub mod model;

pub use engine::Engine;
pub use model::{
    Action, AssociationOutcome, Config, LogEvent, Permission, Role, ScanPurpose, Snapshot,
    StopReason,
};
