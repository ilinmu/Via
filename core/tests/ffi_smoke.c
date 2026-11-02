/* Smoke test for the C ABI. Compile with:
 *
 *   cc -I core/include core/tests/ffi_smoke.c \
 *      core/target/release/libautowifi_core.a -o /tmp/autowifi_ffi_smoke
 */

#include "autowifi_core.h"

#include <assert.h>
#include <stdio.h>
#include <string.h>

static void expect_scan(const AwResult *result, int32_t purpose) {
    assert(result->count == 1);
    assert(result->actions[0].kind == AW_ACTION_SCAN);
    assert(result->actions[0].purpose == purpose);
}

int main(void) {
    AwEngine *engine = aw_engine_new("P", "B");
    assert(engine != NULL);

    AwResult result;

    /* Not on P: the engine asks the shell to scan for P. */
    aw_engine_start(engine, 0, AW_PERMISSION_AUTHORIZED, "X", &result);
    expect_scan(&result, AW_SCAN_PRIORITY);

    /* P is visible: associate with the returned role and SSID. */
    aw_engine_scan_result(engine, 1, 10, &result);
    assert(result.count == 1);
    assert(result.actions[0].kind == AW_ACTION_ASSOCIATE);
    assert(result.actions[0].role == AW_ROLE_PRIORITY);
    assert(strcmp(result.actions[0].ssid, "P") == 0);

    /* Association lifecycle. */
    uint64_t generation = aw_engine_association_started(engine, "P", 20);
    assert(generation != 0);
    aw_engine_association_result(
        engine, "P", generation, AW_ASSOCIATION_SUCCESS, 30, &result);
    assert(result.snapshot.running == 1);
    assert(result.snapshot.role == AW_ROLE_PRIORITY);
    assert(result.snapshot.current_ssid != NULL);
    assert(strcmp(result.snapshot.current_ssid, "P") == 0);

    /* A manual switch to B while P is visible stops monitoring. */
    aw_engine_observed_change(engine, "P", "B", 40, &result);
    expect_scan(&result, AW_SCAN_PRIORITY_CLASSIFICATION);
    aw_engine_classification_result(engine, 1, 50, &result);
    assert(result.count == 2);
    assert(result.actions[0].kind == AW_ACTION_STOP);
    assert(result.actions[0].reason == AW_STOP_MANUAL_OVERRIDE_BACKUP);
    assert(result.snapshot.running == 0);

    /* Query helpers. */
    assert(aw_engine_role(engine, "P") == AW_ROLE_PRIORITY);
    assert(aw_engine_role(engine, "B") == AW_ROLE_BACKUP);
    assert(aw_engine_role(engine, "X") == AW_ROLE_OTHER);
    assert(aw_engine_role(engine, NULL) == AW_ROLE_NONE);

    aw_engine_free(engine);
    puts("ffi smoke ok");
    return 0;
}
