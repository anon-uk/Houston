// SPDX-License-Identifier: GPL-3.0-or-later
// Portable CPU tick delta helper for Houston; see THIRD-PARTY-NOTICES.md.
#ifndef HOUSTON_CPU_DELTA_H
#define HOUSTON_CPU_DELTA_H
#include <stdint.h>
#include <string.h>
enum { TM_CPU_USER, TM_CPU_SYSTEM, TM_CPU_IDLE, TM_CPU_NICE, TM_CPU_STATES };
// Mach reports CPU ticks as 32-bit counters that wrap on long uptimes.
// Unsigned 32-bit subtraction yields the correct delta across a wrap, so a
// sample is neither dropped nor reported as a huge or negative percentage.
static inline void tm_cpu_delta(const uint32_t cur[TM_CPU_STATES], uint32_t prev[TM_CPU_STATES], int *primed, double *usage, double *kernel) {
    if (*primed) {
        uint64_t d[TM_CPU_STATES], total = 0;
        for (int j = 0; j < TM_CPU_STATES; j++) { d[j] = (uint32_t)(cur[j] - prev[j]); total += d[j]; }
        if (total) { *usage = 100.0 * (1.0 - (double)d[TM_CPU_IDLE] / (double)total); *kernel = 100.0 * (double)d[TM_CPU_SYSTEM] / (double)total; }
    }
    memcpy(prev, cur, TM_CPU_STATES * sizeof(uint32_t)); *primed = 1;
}
#endif
