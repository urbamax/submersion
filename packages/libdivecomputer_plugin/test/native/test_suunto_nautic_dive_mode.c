/* The Suunto Nautic parser did not answer DC_FIELD_DIVEMODE, so the wrapper
   left dive_mode at the dc_divemode_t zero value -- FREEDIVE -- and every
   scuba dive imported as an apnea dive (visible on nandodiver's captures,
   deepsealabs/libdc-swift#29).

   The parser now reads the CHUNK_ACTIVITY (0x08) sport id: 61/62 are the
   apnea sports, anything else -- and a stream with no activity chunk at all,
   since the Nautic/Ocean are recreational OC computers -- is open circuit. */

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

/* Minimal profile with one depth reading, optionally preceded by a
   CHUNK_ACTIVITY chunk carrying sport_id (0 = omit the chunk). */
static unsigned int build_stream(unsigned char **out, unsigned int sport_id) {
    static unsigned char buf[64];
    unsigned char *p = buf;

    memcpy(p, "SBEM0103", 8);
    p += 8;

    if (sport_id) {
        *p++ = 0x08; *p++ = 6;                  /* [delta:2][sportId:1][modeId ascii:3] */
        put_u16le(p, 0); p += 2;
        *p++ = (unsigned char)sport_id;
        *p++ = '5'; *p++ = '1'; *p++ = 0;
    }

    *p++ = 0x1C; *p++ = 3;                      /* DIVE_STATE -> Diving */
    put_u16le(p, 0); p += 2; *p++ = 1;

    *p++ = 0x16; *p++ = 6;                      /* EXTENDED_STATUS: [delta:2][depth:f32] */
    put_u16le(p, 1000); p += 2;
    float depth = 12.0f;
    memcpy(p, &depth, 4); p += 4;

    unsigned int size = (unsigned int)(p - buf);
    *out = (unsigned char *)malloc(size);
    assert(*out != NULL);
    memcpy(*out, buf, size);
    return size;
}

static unsigned int parse_mode(unsigned int sport_id) {
    unsigned char *data = NULL;
    unsigned int size = build_stream(&data, sport_id);

    libdc_parsed_dive_t dive;
    char err[256] = {0};
    int rc = libdc_parse_raw_dive("Suunto", "Nautic", 0, data, size, &dive, err,
                                  sizeof(err));
    free(data);
    if (rc != 0) printf("FAIL: parse rc=%d (%s)\n", rc, err);
    assert(rc == 0);
    unsigned int mode = dive.dive_mode;
    free(dive.samples);
    free(dive.events);
    return mode;
}

int main(void) {
    printf("Running Suunto Nautic dive-mode tests...\n");

    /* 2 == the wrapper's OC (0 freedive, 1 gauge, 2 OC, 3 CCR, 4 SCR). */
    unsigned int no_chunk = parse_mode(0);
    printf("  no activity chunk -> %u\n", no_chunk);
    assert(no_chunk == 2);

    unsigned int scuba = parse_mode(51);
    printf("  sport 51 (scuba) -> %u\n", scuba);
    assert(scuba == 2);

    unsigned int freedive = parse_mode(61);
    printf("  sport 61 (free diving) -> %u\n", freedive);
    assert(freedive == 0);

    printf("PASS\nAll Suunto Nautic dive-mode tests passed\n");
    return 0;
}
