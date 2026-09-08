/* Suunto Nautic /Summary decode: water type (DC_FIELD_SALINITY) and the
   per-sample gas time remaining (DC_SAMPLE_RBT).

   Water type is one uint8 in the /Summary SBEM at offset 0x3E, just past the
   gradient factors: 0 = fresh, 1 = EN13319, 2 = salt. Confirmed on 23 real
   /Summary blobs from 6 watches (deepsealabs/libdc-swift#29) against the
   density independently derived from each dive's pressure-vs-depth fit.

   Gas time remaining is a uint32 LE (seconds) at offset +10 of each 18-byte
   cylinder record in the 0x16 extended-status chunk; 0xFFFFFFFF means "not
   computed". It is the app's Cylinders[].GasTime and is surfaced as RBT
   minutes, the same way suunto_eonsteel does.

   These call the parser directly (suunto_nautic_parser_create) so they check
   the libdivecomputer layer without the wrapper. */

#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <libdivecomputer/context.h>
#include <libdivecomputer/parser.h>
#include <libdivecomputer/units.h>

#include "suunto_nautic.h"

static void put_u16le(unsigned char *p, unsigned int v) {
    p[0] = (unsigned char)(v & 0xFF);
    p[1] = (unsigned char)((v >> 8) & 0xFF);
}

static void put_u32le(unsigned char *p, unsigned int v) {
    p[0] = (unsigned char)(v & 0xFF);
    p[1] = (unsigned char)((v >> 8) & 0xFF);
    p[2] = (unsigned char)((v >> 16) & 0xFF);
    p[3] = (unsigned char)((v >> 24) & 0xFF);
}

/* Build a minimal SBEM0103 stream:
     0x1C  DIVE_STATE  -> Diving
     0x16  EXTENDED_STATUS: depth 12 m, cylinder slot 0 with pressure and the
           given gas time remaining (seconds; pass 0xFFFFFFFF for "none")
     <second SBEM0103>  /Summary with water_type at +0x3E
   `water_type` of 0xFF omits the salinity byte's meaning (leaves it 0 = fresh);
   pass 0..3 to exercise the mapping. */
static unsigned int build_stream(unsigned char **out, unsigned int gastime_s,
                                 unsigned int water_type, unsigned int hr_bpm,
                                 unsigned int surf_temp_cK, int gas_switch) {
    static unsigned char buf[512];
    unsigned char *p = buf;

    memcpy(p, "SBEM0103", 8);
    p += 8;

    *p++ = 0x1C; *p++ = 3;                      /* DIVE_STATE -> Diving */
    put_u16le(p, 0); p += 2; *p++ = 1;

    if (surf_temp_cK) {                         /* 0x12 profile: temp (K*100) at +16 */
        *p++ = 0x12; *p++ = 23;
        unsigned char *pr = p;
        memset(pr, 0, 23);
        put_u16le(pr + 0, 100);                 /* delta */
        put_u16le(pr + 16, (unsigned int)surf_temp_cK);
        p += 23;
    }

    if (hr_bpm) {                               /* 0x0F: [delta:2][hr:u8 bpm] */
        *p++ = 0x0F; *p++ = 3;
        put_u16le(p, 0); p += 2;
        *p++ = (unsigned char)hr_bpm;
    }

    if (gas_switch >= 0) {                      /* 0x1F: [delta:2][gasnum:i16 LE] */
        *p++ = 0x1F; *p++ = 4;
        put_u16le(p, 0); p += 2;
        put_u16le(p, (unsigned int)gas_switch); p += 2;
    }

    /* 0x16 extended status: [delta:2][depth:f32 @2] ... cylinder array at +42,
       18 bytes per slot: [idx:1][?:1][pressure:u32 @+2][pressure2:u32 @+6]
       [gastime:u32 @+10][ventilation:f32 @+14]. 64-byte payload covers slot 0. */
    *p++ = 0x16; *p++ = 64;
    unsigned char *body = p;
    memset(body, 0, 64);
    put_u16le(body + 0, 1000);                  /* time delta */
    float depth = 12.0f;
    memcpy(body + 2, &depth, 4);
    body[42] = 0;                               /* slot 0 index */
    put_u32le(body + 42 + 2, 21000000);         /* pressure ~210 bar */
    put_u32le(body + 42 + 10, gastime_s);       /* gas time remaining */
    p += 64;

    /* /Summary section. Offsets (incl. 0x3E, the water type) are relative to
       this second "SBEM0103" signature; everything else stays zero. */
    unsigned char *summary = p;
    memset(summary, 0, 104);
    memcpy(summary, "SBEM0103", 8);
    if (water_type <= 3)
        summary[0x3E] = (unsigned char)water_type;
    p += 104;

    unsigned int size = (unsigned int)(p - buf);
    *out = (unsigned char *)malloc(size);
    assert(*out != NULL);
    memcpy(*out, buf, size);
    return size;
}

static dc_parser_t *make_parser(dc_context_t *ctx, unsigned int gastime_s,
                                unsigned int water_type, unsigned int hr_bpm,
                                unsigned int surf_temp_cK, int gas_switch) {
    unsigned char *data = NULL;
    unsigned int size = build_stream(&data, gastime_s, water_type, hr_bpm,
                                    surf_temp_cK, gas_switch);
    dc_parser_t *parser = NULL;
    dc_status_t rc = suunto_nautic_parser_create(&parser, ctx, data, size);
    free(data);
    if (rc != DC_STATUS_SUCCESS) {
        printf("FAIL: suunto_nautic_parser_create rc=%d\n", rc);
        assert(0);
    }
    return parser;
}

/* ---- salinity ---- */

static void check_salinity(dc_context_t *ctx, unsigned int water_type,
                           int expect_supported, dc_water_t expect_type,
                           double expect_density) {
    dc_parser_t *parser = make_parser(ctx, 0xFFFFFFFF, water_type, 0, 0, -1);
    dc_salinity_t salinity = {0};
    dc_status_t rc = dc_parser_get_field(parser, DC_FIELD_SALINITY, 0, &salinity);

    if (!expect_supported) {
        printf("  water_type %u -> rc=%d (want UNSUPPORTED)\n", water_type, rc);
        assert(rc == DC_STATUS_UNSUPPORTED);
    } else {
        printf("  water_type %u -> type=%d density=%.2f\n", water_type,
               salinity.type, salinity.density);
        assert(rc == DC_STATUS_SUCCESS);
        assert(salinity.type == expect_type);
        assert(fabs(salinity.density - expect_density) < 0.5);
    }
    dc_parser_destroy(parser);
}

/* ---- RBT ---- */

static unsigned int g_rbt_count;
static unsigned int g_rbt_last;
static unsigned int g_hr_count;
static unsigned int g_hr_last;
static unsigned int g_gasmix_count;
static unsigned int g_gasmix_last;

static void sample_cb(dc_sample_type_t type, const dc_sample_value_t *value,
                      void *userdata) {
    (void)userdata;
    if (type == DC_SAMPLE_RBT) {
        g_rbt_count++;
        g_rbt_last = value->rbt;
    } else if (type == DC_SAMPLE_HEARTBEAT) {
        g_hr_count++;
        g_hr_last = value->heartbeat;
    } else if (type == DC_SAMPLE_GASMIX) {
        g_gasmix_count++;
        g_gasmix_last = value->gasmix;
    }
}

static void check_rbt(dc_context_t *ctx, unsigned int gastime_s,
                      unsigned int expect_count, unsigned int expect_minutes) {
    dc_parser_t *parser = make_parser(ctx, gastime_s, 0xFF, 0, 0, -1);
    g_rbt_count = 0;
    g_rbt_last = 0;
    dc_status_t rc = dc_parser_samples_foreach(parser, sample_cb, NULL);
    assert(rc == DC_STATUS_SUCCESS);
    printf("  gastime %us -> %u RBT sample(s), last=%u min\n", gastime_s,
           g_rbt_count, g_rbt_last);
    assert(g_rbt_count == expect_count);
    if (expect_count)
        assert(g_rbt_last == expect_minutes);
    dc_parser_destroy(parser);
}

static void check_hr(dc_context_t *ctx, unsigned int hr_bpm,
                     unsigned int expect_count, unsigned int expect_bpm) {
    dc_parser_t *parser = make_parser(ctx, 0xFFFFFFFF, 0xFF, hr_bpm, 0, -1);
    g_hr_count = 0;
    g_hr_last = 0;
    dc_status_t rc = dc_parser_samples_foreach(parser, sample_cb, NULL);
    assert(rc == DC_STATUS_SUCCESS);
    printf("  hr %u bpm -> %u HEARTBEAT sample(s), last=%u\n", hr_bpm,
           g_hr_count, g_hr_last);
    assert(g_hr_count == expect_count);
    if (expect_count)
        assert(g_hr_last == expect_bpm);
    dc_parser_destroy(parser);
}

static void check_surface_temp(dc_context_t *ctx, unsigned int temp_cK,
                               double expect_c) {
    dc_parser_t *parser = make_parser(ctx, 0xFFFFFFFF, 0xFF, 0, temp_cK, -1);
    double t = -999.0;
    dc_status_t rc = dc_parser_get_field(parser, DC_FIELD_TEMPERATURE_SURFACE, 0, &t);
    printf("  temp %u cK -> rc=%d  surface=%.2f C\n", temp_cK, rc, t);
    assert(rc == DC_STATUS_SUCCESS);
    assert(fabs(t - expect_c) < 0.05);
    dc_parser_destroy(parser);
}

static void check_gas_switch(dc_context_t *ctx, int gas_switch,
                             unsigned int expect_count, unsigned int expect_idx) {
    dc_parser_t *parser = make_parser(ctx, 0xFFFFFFFF, 0xFF, 0, 0, gas_switch);
    g_gasmix_count = 0;
    g_gasmix_last = 0;
    dc_status_t rc = dc_parser_samples_foreach(parser, sample_cb, NULL);
    assert(rc == DC_STATUS_SUCCESS);
    printf("  switch to %d -> %u GASMIX sample(s), last idx=%u\n", gas_switch,
           g_gasmix_count, g_gasmix_last);
    assert(g_gasmix_count == expect_count);
    if (expect_count)
        assert(g_gasmix_last == expect_idx);
    dc_parser_destroy(parser);
}

int main(void) {
    printf("Running Suunto Nautic water-type / RBT / HR tests...\n");

    dc_context_t *ctx = NULL;
    assert(dc_context_new(&ctx) == DC_STATUS_SUCCESS);

    printf("water type:\n");
    check_salinity(ctx, 0, 1, DC_WATER_FRESH, 0.0);
    check_salinity(ctx, 1, 1, DC_WATER_SALT, MSW / GRAVITY); /* EN13319 ~1019.7 */
    check_salinity(ctx, 2, 1, DC_WATER_SALT, 0.0);
    check_salinity(ctx, 3, 0, DC_WATER_FRESH, 0.0);          /* unknown -> unsupported */

    printf("gas time remaining (RBT):\n");
    check_rbt(ctx, 1200, 1, 20);          /* 1200 s -> 20 min */
    check_rbt(ctx, 59, 1, 0);             /* rounds down, still emitted */
    check_rbt(ctx, 0xFFFFFFFF, 0, 0);     /* sentinel -> no sample */
    check_rbt(ctx, 0, 0, 0);              /* zero -> no sample */

    printf("heart rate (0x0F, Ocean):\n");
    check_hr(ctx, 72, 1, 72);             /* 72 bpm -> one HEARTBEAT sample */
    check_hr(ctx, 0, 0, 0);               /* 0 = no chunk -> no sample */

    printf("surface temperature (first 0x12 reading):\n");
    check_surface_temp(ctx, 29715, 24.0); /* 297.15 K -> 24.0 C */

    printf("gas switch (0x1F -> DC_SAMPLE_GASMIX):\n");
    check_gas_switch(ctx, 1, 1, 1);       /* switch to gas 1 */
    check_gas_switch(ctx, -1, 0, 0);      /* no switch chunk -> no sample */

    dc_context_free(ctx);

    printf("PASS\nAll Suunto Nautic water-type / RBT / HR tests passed\n");
    return 0;
}
