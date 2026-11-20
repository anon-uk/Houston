// SPDX-License-Identifier: GPL-3.0-or-later
// Portable: builds with any C11 compiler, no macOS SDK required.
#include "../Native/CPUDelta.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
static int near(double a, double b) { return fabs(a - b) < 1e-9; }
int main(void) {
    uint32_t prev[TM_CPU_STATES] = {0}; int primed = 0; double usage = -1, kernel = -1;
    uint32_t a[TM_CPU_STATES] = {100, 50, 850, 0};
    tm_cpu_delta(a, prev, &primed, &usage, &kernel);
    assert(primed && usage == -1 && kernel == -1); // first sample only primes
    uint32_t b[TM_CPU_STATES] = {130, 60, 910, 0}; // 30 user, 10 system, 60 idle
    tm_cpu_delta(b, prev, &primed, &usage, &kernel);
    assert(near(usage, 40) && near(kernel, 10));
    // Idle and system counters wrap past UINT32_MAX between samples.
    uint32_t c[TM_CPU_STATES] = {200, UINT32_MAX - 4, UINT32_MAX - 69, 0};
    uint32_t d[TM_CPU_STATES] = {220, 15, 10, 0}; // 20 user, 20 system, 80 idle
    tm_cpu_delta(c, prev, &primed, &usage, &kernel);
    tm_cpu_delta(d, prev, &primed, &usage, &kernel);
    assert(near(usage, 100.0 * 40 / 120) && near(kernel, 100.0 * 20 / 120));
    // No elapsed ticks: keep the previous reading rather than dividing by zero.
    usage = 7; kernel = 3;
    tm_cpu_delta(d, prev, &primed, &usage, &kernel);
    assert(usage == 7 && kernel == 3);
    printf("PASS: CPU tick deltas, first-sample priming, 32-bit counter wraparound, idle intervals\n");
    return 0;
}
