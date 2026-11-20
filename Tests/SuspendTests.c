// SPDX-License-Identifier: GPL-3.0-or-later
// Suspended (SIGSTOP) processes must be reported as stopped, and resumed ones as not stopped.
#include "../Native/Metrics.h"
#include <assert.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/wait.h>
#include <unistd.h>
static int stopped(TMProcess *rows, pid_t pid) {
    int n = tm_processes(rows, 4096);
    for (int i = 0; i < n; i++) if (rows[i].pid == pid) return rows[i].stopped;
    assert(!"child not listed"); return -1;
}
int main(void) {
    TMProcess *rows = calloc(4096, sizeof(TMProcess)); assert(rows);
    pid_t child = fork(); assert(child >= 0);
    if (child == 0) { for (;;) pause(); }
    int status;
    assert(stopped(rows, child) == 0);
    assert(kill(child, SIGSTOP) == 0); assert(waitpid(child, &status, WUNTRACED) == child && WIFSTOPPED(status));
    assert(stopped(rows, child) == 1);
    assert(kill(child, SIGCONT) == 0); assert(waitpid(child, &status, WCONTINUED) == child && WIFCONTINUED(status));
    assert(stopped(rows, child) == 0);
    kill(child, SIGKILL); waitpid(child, &status, 0); free(rows);
    printf("PASS: suspended processes reported as stopped, resumed as running\n");
}
