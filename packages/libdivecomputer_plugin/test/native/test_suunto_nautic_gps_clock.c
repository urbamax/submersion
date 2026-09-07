/* submersion-libdc#1: a Suunto Nautic/Ocean GPS or GPS-accuracy chunk carries a
   millisecond delta on its own back-dated sub-chain. Read as a plain file-order
   delta it rewinds the shared sample clock a few hundred ms; the next chunk's
   delta (measured from the rewound point) walks it forward again.

   The raw running sum stays usable for span arithmetic, but a sample emitted at
   the rewound value goes backwards in the profile. Downstream, fill_missing_depths
   does unsigned time subtraction, which then wraps to a huge value and
   extrapolates a kilometre-scale depth for that one sample (trustthegoose saw
   212,373 m and 751,979 m on a real Ocean dive).

   The parser now emits every sample time from a monotonic view of the sum, and
   fill_missing_depths clamps its interpolation fraction to [0, 1] as a second,
   independent guard. This test drives the exact shape from the issue through the
   whole wrapper and asserts neither symptom survives. */

#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "libdc_wrapper.h"

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

static void put_f32le(unsigned char *p, float v) {
    unsigned int bits;
    memcpy(&bits, &v, sizeof(bits));
    put_u32le(p, bits);
}

/* Builds a minimal SBEM0103 profile:

     DIVE_STATE  delta=+0      -> Diving
     EXT_STATUS  delta=+20000  depth 0.05 m     (real, t=20000)
     GPS_ACCUR.  delta=-15000  EHPE/EVPE only   (rewinds the raw sum to t=5000)
     EXT_STATUS  delta=+15200  depth 0.08 m     (delta from the rewound point;
                                                 raw sum self-corrects to 20200)
     GPS         delta=+0      absolute UTC     (sets dive datetime)
     DIVE_STATE  delta=+200    -> Idling

   Returns the byte count; caller frees *out. */
static unsigned int build_stream(unsigned char **out) {
    static unsigned char buf[256];
    unsigned char *p = buf;

    memcpy(p, "SBEM0103", 8);
    p += 8;

    /* DIVE_STATE (0x1C): [delta:2][state:1] */
    *p++ = 0x1C; *p++ = 3;
    put_u16le(p, 0); p += 2;
    *p++ = 1; /* DIVE_STATE_DIVING */

    /* EXTENDED_STATUS (0x16): [delta:2][depth:f32 @ +2] */
    *p++ = 0x16; *p++ = 6;
    put_u16le(p, 20000); p += 2;
    put_f32le(p, 0.05f); p += 4;

    /* GPS_ACCURACY (0x0E): fixed length 6, [delta:2][dEHPE:1][dEVPE:1][pad:2] */
    *p++ = 0x0E; *p++ = 6;
    put_u16le(p, (unsigned int)(int)-15000); p += 2;
    *p++ = 1; *p++ = 1; *p++ = 0; *p++ = 0;

    /* EXTENDED_STATUS (0x16) again */
    *p++ = 0x16; *p++ = 6;
    put_u16le(p, 15200); p += 2;
    put_f32le(p, 0.08f); p += 4;

    /* GPS (0x0B): fixed length 20, [delta:2][UTC:8 ms LE][lat:4][lon:4][pad:2] */
    *p++ = 0x0B; *p++ = 20;
    put_u16le(p, 0); p += 2;
    {
        /* 2026-01-15 10:00:00Z + 20200 ms, so start == that instant minus the
           sample's own (monotonic) time. */
        unsigned long long utc_ms = 1768471200000ULL + 20200ULL;
        for (int i = 0; i < 8; i++) { *p++ = (unsigned char)(utc_ms & 0xFF); utc_ms >>= 8; }
    }
    put_u32le(p, (unsigned int)(int)(43.2964 * 1e7)); p += 4; /* lat */
    put_u32le(p, (unsigned int)(int)(5.3699 * 1e7));  p += 4; /* lon */
    *p++ = 0; *p++ = 0;

    /* DIVE_STATE -> Idling */
    *p++ = 0x1C; *p++ = 3;
    put_u16le(p, 200); p += 2;
    *p++ = 0;

    unsigned int size = (unsigned int)(p - buf);
    *out = (unsigned char *)malloc(size);
    assert(*out != NULL);
    memcpy(*out, buf, size);
    return size;
}

static void test_gps_clock_excursion(void) {
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
    assert(dive.sample_count >= 3);

    unsigned int prev = 0;
    for (unsigned int i = 0; i < dive.sample_count; i++) {
        printf("  sample %u: t=%u ms, depth=%.3f m\n", i,
               dive.samples[i].time_ms, dive.samples[i].depth);

        /* 1. Sample times never go backwards. Before the fix the GPS_ACCURACY
              sample landed at t=5000, behind the t=20000 depth sample. */
        assert(dive.samples[i].time_ms >= prev);
        prev = dive.samples[i].time_ms;

        /* 2. Every depth stays between the two real readings. Before the fix the
              wrapped fraction extrapolated one sample to hundreds of km. */
        assert(dive.samples[i].depth >= 0.04);
        assert(dive.samples[i].depth <= 0.09);
    }

    /* 3. The raw sum self-corrects, so the last reading sits at ~20200 ms, not
          the ~35200 ms an "exclude GPS from the clock" fix would overshoot to. */
    unsigned int last = dive.samples[dive.sample_count - 1].time_ms;
    assert(last >= 20000 && last <= 21000);

    free(dive.samples);
    free(dive.events);
    printf("PASS: test_gps_clock_excursion\n");
}

int main(void) {
    printf("Running Suunto Nautic GPS-clock tests (submersion-libdc#1)...\n");
    test_gps_clock_excursion();
    printf("All Suunto Nautic GPS-clock tests passed\n");
    return 0;
}
