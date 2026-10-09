// SPDX-License-Identifier: GPL-3.0-or-later
// Modified for Houston, 2026-10-09; see THIRD-PARTY-NOTICES.md.
#include <stdint.h>
typedef struct { int pid, ppid, uid, threads; uint64_t resident, cpu_ns, read_bytes, write_bytes, started; int io_valid; char name[256]; char path[4096]; } TMProcess;
typedef struct { double cpu, kernel; uint64_t memory_used, memory_total, compressed, memory_active, memory_wired, memory_cached, memory_free, swap_total, swap_used, net_in, net_out; int cores; double core_usage[128], core_kernel[128]; } TMSystem;
int tm_processes(TMProcess *out, int capacity);
TMSystem tm_system(void);
