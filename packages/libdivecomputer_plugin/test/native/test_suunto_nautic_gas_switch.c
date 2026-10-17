/* Suunto Nautic #33 (multi-gas): the watch fires a "switch gas?" prompt as a
   NOTIFY event (sub-group 0x1A, type 11, begin/end pairs) that the diver can
   ignore -- nandodiver saw a run of them mid-dive on an all-air dive
   (deepsealabs/libdc-swift#29). The parser mapped every one to
   SAMPLE_EVENT_GASCHANGE, and because a mapped event puts the raw
   (sub-group << 8 | type) in event.value, each surfaced as "gas change to gas
   6667". The real switch comes through CHUNK_GAS_SWITCH (0x1F) with the gas
   number, and is the only one that should produce a gaschange.

   This drives a synthetic stream with one real switch to gas 1 and two NOTIFY
   prompts, and asserts exactly one gaschange, to gas 1. */

#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <libdivecomputer/parser.h>
#include "libdc_wrapper.h"

static void put_u16le(unsigned char *p, unsigned int v) {
    p[0] = (unsigned char)(v & 0xFF);
    p[1] = (unsigned char)((v >> 8) & 0xFF);
}

/* SBEM0103 profile:
     DIVE_STATE   +0       -> Diving
     GAS_SWITCH   +1000    gas number 1        (real switch)
     EVENT_NOTIFY +5000    type 11, Active=1    ("switch gas?" prompt)
     EVENT_NOTIFY +100     type 11, Active=0    (prompt cleared)
     DIVE_STATE   +1000    -> Idling
*/
static unsigned int build_stream(unsigned char **out) {
    static unsigned char buf[128];
    unsigned char *p = buf;

    memcpy(p, "SBEM0103", 8);
    p += 8;

    *p++ = 0x1C; *p++ = 3;                      /* DIVE_STATE */
    put_u16le(p, 0); p += 2; *p++ = 1;

    *p++ = 0x1F; *p++ = 4;                      /* GAS_SWITCH: [delta:2][gasnum:i16] */
    put_u16le(p, 1000); p += 2;
    put_u16le(p, 1); p += 2;

    *p++ = 0x1A; *p++ = 4;                      /* EVENT_NOTIFY: [delta:2][type:1][active:1] */
    put_u16le(p, 5000); p += 2; *p++ = 11; *p++ = 1;

    *p++ = 0x1A; *p++ = 4;
    put_u16le(p, 100); p += 2; *p++ = 11; *p++ = 0;

    *p++ = 0x1C; *p++ = 3;
    put_u16le(p, 1000); p += 2; *p++ = 0;

    unsigned int size = (unsigned int)(p - buf);
    *out = (unsigned char *)malloc(size);
    assert(*out != NULL);
    memcpy(*out, buf, size);
    return size;
}

static void test_only_the_real_switch_is_a_gaschange(void) {
    unsigned char *data = NULL;
    unsigned int size = build_stream(&data);

    libdc_parsed_dive_t dive;
    char err[256] = {0};
    int rc = libdc_parse_raw_dive("Suunto", "Nautic", 0, data, size, &dive, err,
                                  sizeof(err));
    free(data);
    if (rc != 0) {
        printf("FAIL: libdc_parse_raw_dive returned %d (%s)\n", rc, err);
    }
    assert(rc == 0);

    unsigned int gaschanges = 0;
    unsigned int switched_to = (unsigned int)-1;
    for (unsigned int i = 0; i < dive.event_count; i++) {
        printf("  event t=%us  %s  value=%u\n", dive.events[i].time_ms / 1000,
               libdc_event_type_name(dive.events[i].type), dive.events[i].value);
        if (dive.events[i].type == SAMPLE_EVENT_GASCHANGE) {
            gaschanges++;
            switched_to = dive.events[i].value;
        }
    }

    assert(gaschanges == 1);
    assert(switched_to == 1);

    free(dive.samples);
    free(dive.events);
    printf("PASS: test_only_the_real_switch_is_a_gaschange\n");
}

int main(void) {
    printf("Running Suunto Nautic gas-switch tests (#33)...\n");
    test_only_the_real_switch_is_a_gaschange();
    printf("All Suunto Nautic gas-switch tests passed\n");
    return 0;
}
