/* Smoke test for the C ABI. Compile with:
 *
 *   cc -I core/include core/tests/ffi_smoke.c \
 *      core/target/release/libvia_core.a -o /tmp/via_ffi_smoke
 */

#include "via_core.h"

#include <assert.h>
#include <stdio.h>
#include <string.h>

static void expect_scan(const ViaResult *result, int32_t purpose) {
    assert(result->count == 1);
    assert(result->actions[0].kind == VIA_ACTION_SCAN);
    assert(result->actions[0].purpose == purpose);
}

int main(void) {
    ViaEngine *engine = via_engine_new("P", "B");
    assert(engine != NULL);

    ViaResult result;

    /* Not on P: the engine asks the shell to scan for P. */
    via_engine_start(engine, 0, VIA_PERMISSION_AUTHORIZED, "X", &result);
    expect_scan(&result, VIA_SCAN_PRIORITY);

    /* P is visible: associate with the returned role and SSID. */
    via_engine_scan_result(engine, 1, 10, &result);
    assert(result.count == 1);
    assert(result.actions[0].kind == VIA_ACTION_ASSOCIATE);
    assert(result.actions[0].role == VIA_ROLE_PRIORITY);
    assert(strcmp(result.actions[0].ssid, "P") == 0);

    /* Association lifecycle. */
    uint64_t generation = via_engine_association_started(engine, "P", 20);
    assert(generation != 0);
    via_engine_association_result(
        engine, "P", generation, VIA_ASSOCIATION_SUCCESS, 30, &result);
    assert(result.snapshot.running == 1);
    assert(result.snapshot.role == VIA_ROLE_PRIORITY);
    assert(result.snapshot.current_ssid != NULL);
    assert(strcmp(result.snapshot.current_ssid, "P") == 0);

    /* A manual switch to B while P is visible stops monitoring. */
    via_engine_observed_change(engine, "P", "B", 40, &result);
    expect_scan(&result, VIA_SCAN_PRIORITY_CLASSIFICATION);
    via_engine_classification_result(engine, 1, 50, &result);
    assert(result.count == 2);
    assert(result.actions[0].kind == VIA_ACTION_STOP);
    assert(result.actions[0].reason == VIA_STOP_MANUAL_OVERRIDE_BACKUP);
    assert(result.snapshot.running == 0);

    /* Query helpers. */
    assert(via_engine_role(engine, "P") == VIA_ROLE_PRIORITY);
    assert(via_engine_role(engine, "B") == VIA_ROLE_BACKUP);
    assert(via_engine_role(engine, "X") == VIA_ROLE_OTHER);
    assert(via_engine_role(engine, NULL) == VIA_ROLE_NONE);

    via_engine_free(engine);
    puts("ffi smoke ok");
    return 0;
}
