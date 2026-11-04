/*
 * Via policy core — C ABI.
 *
 * The engine is a deterministic state machine. Native shells translate their
 * Wi-Fi events into calls below and execute the returned actions.
 *
 * Ownership:
 *   - ViaResult.actions and every `const char *` inside it are owned by the
 *     engine and remain valid only until the next call on that engine.
 *   - Copy any string you need to keep.
 *
 * Threading:
 *   - Call one engine from one thread at a time (the UI/monitoring thread).
 */

#ifndef VIA_CORE_H
#define VIA_CORE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct ViaEngine ViaEngine;

typedef enum {
    VIA_PERMISSION_UNKNOWN = 0,
    VIA_PERMISSION_AUTHORIZED = 1,
    VIA_PERMISSION_DENIED = 2
} ViaPermission;

typedef enum {
    VIA_ROLE_NONE = 0,
    VIA_ROLE_PRIORITY = 1,
    VIA_ROLE_BACKUP = 2,
    VIA_ROLE_OTHER = 3
} ViaRole;

typedef enum {
    VIA_ACTION_SCAN = 1,
    VIA_ACTION_ASSOCIATE = 2,
    VIA_ACTION_CHECK_NOW = 3,
    VIA_ACTION_STOP = 4,
    VIA_ACTION_WAIT_FOR_PERMISSION = 5,
    VIA_ACTION_LOG = 6,
    VIA_ACTION_REFRESH_STATUS = 7
} ViaActionKind;

typedef enum {
    VIA_SCAN_PRIORITY = 1,
    VIA_SCAN_BACKUP = 2,
    VIA_SCAN_PRIORITY_CLASSIFICATION = 3,
    VIA_SCAN_BACKUP_FAILOVER = 4,
    VIA_SCAN_BACKUP_RECOVERY = 5
} ViaScanPurpose;

typedef enum {
    VIA_STOP_NOT_CONFIGURED = 1,
    VIA_STOP_MANUAL_OVERRIDE_BACKUP = 2,
    VIA_STOP_MANUAL_OVERRIDE_UNMANAGED = 3
} ViaStopReason;

typedef enum {
    VIA_LOG_STARTED = 1,
    VIA_LOG_STOPPED = 2,
    VIA_LOG_PRIORITY_CONNECTED = 3,
    VIA_LOG_PRIORITY_VISIBLE_WAITING = 4,
    VIA_LOG_NETWORK_DISCONNECTED_WAITING = 5,
    VIA_LOG_AUTOMATIC_FAILOVER = 6,
    VIA_LOG_PRIORITY_LOST_CONNECTING_BACKUP = 7,
    VIA_LOG_BACKUP_CONNECTED_P_NOT_FOUND = 8,
    VIA_LOG_NEITHER_FOUND = 9,
    VIA_LOG_BACKUP_NOT_FOUND = 10,
    VIA_LOG_BACKUP_NOT_FOUND_WAITING = 11,
    VIA_LOG_PREVIOUS_BACKUP_RECONNECT = 12,
    VIA_LOG_SYSTEM_JOINED_BACKUP = 13,
    VIA_LOG_TREATING_AS_FALLBACK = 14,
    VIA_LOG_COOLDOWN_SKIPPED = 15,
    VIA_LOG_ASSOCIATION_SUCCESS = 16,
    VIA_LOG_ASSOCIATION_TIMEOUT = 17,
    VIA_LOG_ASSOCIATION_FAILURE = 18,
    VIA_LOG_ASSOCIATION_LATE_SUCCESS = 19,
    VIA_LOG_ASSOCIATION_LATE_FAILURE = 20,
    VIA_LOG_PERMISSION_REQUIRED = 21
} ViaLogEvent;

typedef enum {
    VIA_ASSOCIATION_SUCCESS = 0,
    VIA_ASSOCIATION_TIMEOUT = 1,
    VIA_ASSOCIATION_FAILURE = 2
} ViaAssociationOutcome;

typedef struct {
    int32_t kind;
    int32_t role;
    int32_t reason;
    int32_t purpose;
    int64_t delay_ms;
    const char *ssid;
} ViaAction;

typedef struct {
    int32_t running;
    int32_t role;
    int32_t permission;
    int32_t is_associating;
    int64_t cooldown_until_ms; /* 0 when there is no cooldown */
    const char *current_ssid;
    const char *cooldown_target;
} ViaSnapshot;

typedef struct {
    int32_t count;
    const ViaAction *actions;
    ViaSnapshot snapshot;
} ViaResult;

/* Creates an engine with the initial P/B configuration. Never returns NULL
 * unless allocation fails. */
ViaEngine *via_engine_new(const char *ssid_p, const char *ssid_b);
void via_engine_free(ViaEngine *engine);

void via_engine_set_config(ViaEngine *engine, const char *ssid_p, const char *ssid_b);

/* Restores a cooldown persisted across launches. Pass until_ms <= 0 for none. */
void via_engine_set_persisted_cooldown(
    ViaEngine *engine,
    const char *target,
    int64_t until_ms,
    int64_t now_ms);

void via_engine_start(
    ViaEngine *engine,
    int64_t now_ms,
    int32_t permission,
    const char *current_ssid,
    ViaResult *out);

void via_engine_stop(ViaEngine *engine, ViaResult *out);

void via_engine_check_begin(
    ViaEngine *engine,
    int64_t now_ms,
    int32_t permission,
    const char *current_ssid,
    ViaResult *out);

void via_engine_scan_result(
    ViaEngine *engine,
    int32_t found,
    int64_t now_ms,
    ViaResult *out);

void via_engine_classification_result(
    ViaEngine *engine,
    int32_t priority_visible,
    int64_t now_ms,
    ViaResult *out);

void via_engine_backup_scan_result(
    ViaEngine *engine,
    int32_t found,
    int64_t now_ms,
    ViaResult *out);

/* Returns the generation to pass back with the association result. */
uint64_t via_engine_association_started(
    ViaEngine *engine,
    const char *ssid,
    int64_t now_ms);

void via_engine_association_result(
    ViaEngine *engine,
    const char *ssid,
    uint64_t generation,
    int32_t outcome,
    int64_t now_ms,
    ViaResult *out);

void via_engine_late_association_result(
    ViaEngine *engine,
    const char *ssid,
    uint64_t generation,
    int32_t succeeded,
    int64_t now_ms,
    ViaResult *out);

void via_engine_observed_change(
    ViaEngine *engine,
    const char *previous_ssid,
    const char *new_ssid,
    int64_t now_ms,
    ViaResult *out);

void via_engine_snapshot(const ViaEngine *engine, ViaSnapshot *out);

int32_t via_engine_role(const ViaEngine *engine, const char *ssid);

int32_t via_engine_cooldown_active(
    const ViaEngine *engine,
    const char *ssid,
    int64_t now_ms);

int32_t via_engine_is_recent_programmatic_backup(
    const ViaEngine *engine,
    int64_t now_ms);

int32_t via_engine_is_current_generation(
    const ViaEngine *engine,
    uint64_t generation);

#ifdef __cplusplus
}
#endif

#endif /* VIA_CORE_H */
