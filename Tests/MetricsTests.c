#include "../Native/Metrics.h"
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/resource.h>
#include <assert.h>
#include <math.h>
static TMProcess self(TMProcess *rows){int n=tm_processes(rows,4096);assert(n>0);for(int i=0;i<n;i++)if(rows[i].pid==getpid())return rows[i];assert(0);return rows[0];}
static double timeval_seconds(struct timeval v){return v.tv_sec+v.tv_usec/1e6;}
int main(){TMProcess *rows=calloc(4096,sizeof(TMProcess));TMProcess a=self(rows);assert(a.uid==getuid());assert(a.resident>0);assert(a.threads>0);TMSystem s=tm_system();assert(s.memory_total>0);assert(s.memory_wired>0 && s.memory_wired<=s.memory_total);assert(s.memory_used<=s.memory_total);assert(s.swap_used<=s.swap_total);assert(s.cores>0);struct rusage r1,r2;getrusage(RUSAGE_SELF,&r1);volatile double x=1;for(int i=0;i<100000000;i++)x+=i;getrusage(RUSAGE_SELF,&r2);TMProcess b=self(rows);double cpu=(b.cpu_ns-a.cpu_ns)/1e9;double expected=timeval_seconds(r2.ru_utime)+timeval_seconds(r2.ru_stime)-timeval_seconds(r1.ru_utime)-timeval_seconds(r1.ru_stime);assert(expected>0.01);assert(cpu>expected*0.8 && cpu<expected*1.3);s=tm_system();assert(s.cpu>=0 && s.cpu<=100);assert(s.kernel>=0 && s.kernel<=s.cpu+1);for(int i=0;i<s.cores && i<128;i++){assert(s.core_usage[i]>=0 && s.core_usage[i]<=100);assert(s.core_kernel[i]>=0 && s.core_kernel[i]<=s.core_usage[i]+1);}printf("PASS: PID/UID/RSS/threads; CPU units %.3fs vs getrusage %.3fs; %d logical processors; CPU %.1f%%; kernel %.1f%%\n",cpu,expected,s.cores,s.cpu,s.kernel);free(rows);}
