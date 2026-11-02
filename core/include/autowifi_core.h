/*
 * AutoWifi policy core — C ABI.
 *
 * The engine is a deterministic state machine. Native shells translate their
 * Wi-Fi events into calls below and execute the returned actions.
 *
 * Ownership:
 *   - AwResult.actions and every `const char *` inside it are owned by the
 *     engine and remain valid only until the next call on that engine.
 *   - Copy any string you need to keep.
 *
 * Threading:
 *   - Call one engine from one thread at a time (the UI/monitoring thread).
 */

#ifndef AUTOWIFI_CORE_H
#define AUTOWIFI_CORE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct AwEngine AwEngine;

typedef enum {
    AW_PERMISSION_UNKNOWN = 0,
    AW_PERMISSION_AUTHORIZED = 1,
    AW_PERMISSION_DENIED = 2
} AwPermission;

typedef enum {
    AW_ROLE_NONE = 0,
    AW_ROLE_PRIORITY = 1,
    AW_ROLE_BACKUP = 2,
    AW_ROLE_OTHER = 3
} AwRole;

typedef enum {
    AW_ACTION_SCAN = 1,
    AW_ACTION_ASSOCIATE = 2,
    AW_ACTION_CHECK_NOW = 3,
    AW_ACTION_STOP = 4,
    AW_ACTION_WAIT_FOR_PERMISSION = 5,
    AW_ACTION_LOG = 6,
    AW_ACTION_REFRESH_STATUS = 7
} AwActionKind;

typedef enum {
    AW_SCAN_PRIORITY = 1,
    AW_SCAN_BACKUP = 2,
    AW_SCAN_PRIORITY_CLASSIFICATION = 3,
    AW_SCAN_BACKUP_FAILOVER = 4,
    AW_SCAN_BACKUP_RECOVERY = 5
} AwScanPurpose;

typedef enum {
    AW_STOP_NOT_CONFIGURED = 1,
    AW_STOP_MANUAL_OVERRIDE_BACKUP = 2,
    AW_STOP_MANUAL_OVERRIDE_UNMANAGED = 3
} AwStopReason;

typedef enum {
    AW_LOG_STARTED = 1,
    AW_LOG_STOPPED = 2,
    AW_LOG_PRIORITY_CONNECTED = 3,
    AW_LOG_PRIORITY_VISIBLE_WAITING = 4,
    AW_LOG_NETWORK_DISCONNECTED_WAITING = 5,
    AW_LOG_AUTOMATIC_FAILOVER = 6,
    AW_LOG_PRIORITY_LOST_CONNECTING_BACKUP = 7,
    AW_LOG_BACKUP_CONNECTED_P_NOT_FOUND = 8,
    AW_LOG_NEITHER_FOUND = 9,
    AW_LOG_BACKUP_NOT_FOUND = 10,
    AW_LOG_BACKUP_NOT_FOUND_WAITING = 11,
    AW_LOG_PREVIOUS_BACKUP_RECONNECT = 12,
    AW_LOG_SYSTEM_JOINED_BACKUP = 13,
    AW_LOG_TREATING_AS_FALLBACK = 14,
    AW_LOG_COOLDOWN_SKIPPED = 15,
    AW_LOG_ASSOCIATION_SUCCESS = 16,
    AW_LOG_ASSOCIATION_TIMEOUT = 17,
    AW_LOG_ASSOCIATION_FAILURE = 18,
    AW_LOG_ASSOCIATION_LATE_SUCCESS = 19,
    AW_LOG_ASSOCIATION_LATE_FAILURE = 20,
    AW_LOG_PERMISSION_REQUIRED = 21
} AwLogEvent;

typedef enum {
    AW_ASSOCIATION_SUCCESS = 0,
    AW_ASSOCIATION_TIMEOUT = 1,
    AW_ASSOCIATION_FAILURE = 2
} AwAssociationOutcome;

typedef struct {
    int32_t kind;
    int32_t role;
    int32_t reason;
    int32_t purpose;
    int64_t delay_ms;
    const char *ssid;
} AwAction;

typedef struct {
    int32_t running;
    int32_t role;
    int32_t permission;
    int32_t is_associating;
    int64_t cooldown_until_ms; /* 0 when there is no cooldown */
    const char *current_ssid;
    const char *cooldown_target;
} AwSnapshot;

typedef struct {
    int32_t count;
    const AwAction *actions;
    AwSnapshot snapshot;
} AwResult;

/* Creates an engine with the initial P/B configuration. Never returns NULL
 * unless allocation fails. */
AwEngine *aw_engine_new(const char *ssid_p, const char *ssid_b);
void aw_engine_free(AwEngine *engine);

void aw_engine_set_config(AwEngine *engine, const char *ssid_p, const char *ssid_b);

/* Restores a cooldown persisted across launches. Pass until_ms <= 0 for none. */
void aw_engine_set_persisted_cooldown(
    AwEngine *engine,
    const char *target,
    int64_t until_ms,
    int64_t now_ms);

void aw_engine_start(
    AwEngine *engine,
    int64_t now_ms,
    int32_t permission,
    const char *current_ssid,
    AwResult *out);

void aw_engine_stop(AwEngine *engine, AwResult *out);

void aw_engine_check_begin(
    AwEngine *engine,
    int64_t now_ms,
    int32_t permission,
    const char *current_ssid,
    AwResult *out);

void aw_engine_scan_result(
    AwEngine *engine,
    int32_t found,
    int64_t now_ms,
    AwResult *out);

void aw_engine_classification_result(
    AwEngine *engine,
    int32_t priority_visible,
    int64_t now_ms,
    AwResult *out);

void aw_engine_backup_scan_result(
    AwEngine *engine,
    int32_t found,
    int64_t now_ms,
    AwResult *out);

/* Returns the generation to pass back with the association result. */
uint64_t aw_engine_association_started(
    AwEngine *engine,
    const char *ssid,
    int64_t now_ms);

void aw_engine_association_result(
    AwEngine *engine,
    const char *ssid,
    uint64_t generation,
    int32_t outcome,
    int64_t now_ms,
    AwResult *out);

void aw_engine_late_association_result(
    AwEngine *engine,
    const char *ssid,
    uint64_t generation,
    int32_t succeeded,
    int64_t now_ms,
    AwResult *out);

void aw_engine_observed_change(
    AwEngine *engine,
    const char *previous_ssid,
    const char *new_ssid,
    int64_t now_ms,
    AwResult *out);

void aw_engine_snapshot(const AwEngine *engine, AwSnapshot *out);

int32_t aw_engine_role(const AwEngine *engine, const char *ssid);

int32_t aw_engine_cooldown_active(
    const AwEngine *engine,
    const char *ssid,
    int64_t now_ms);

int32_t aw_engine_is_recent_programmatic_backup(
    const AwEngine *engine,
    int64_t now_ms);

int32_t aw_engine_is_current_generation(
    const AwEngine *engine,
    uint64_t generation);

#ifdef __cplusplus
}
#endif

#endif /* AUTOWIFI_CORE_H */
