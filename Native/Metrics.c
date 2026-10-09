// SPDX-License-Identifier: GPL-3.0-or-later
// Modified for Houston, 2026-10-09; see THIRD-PARTY-NOTICES.md.
#include "Metrics.h"
#include <libproc.h>
#include <sys/proc_info.h>
#include <sys/resource.h>
#include <sys/sysctl.h>
#include <mach/mach.h>
#include <mach/mach_time.h>
#include <ifaddrs.h>
#include <net/if.h>
#include <net/if_dl.h>
#include <net/route.h>
#include <net/if_types.h>
#include <stdlib.h>
#include <string.h>
int tm_processes(TMProcess *out,int capacity) {
 int bytes=proc_listallpids(NULL,0); int *pids=calloc(bytes+1024,sizeof(int)); int count=proc_listallpids(pids,(bytes+1024)*sizeof(int)); int n=0;
 for(int i=0;i<count && n<capacity;i++) { if(pids[i]<=0)continue; struct proc_bsdinfo b={0}; struct proc_taskinfo t={0};
 if(proc_pidinfo(pids[i],PROC_PIDTBSDINFO,0,&b,sizeof(b))!=sizeof(b))continue;
 TMProcess *p=&out[n++]; memset(p,0,sizeof(*p)); p->pid=pids[i]; p->ppid=b.pbi_ppid;p->uid=b.pbi_uid;p->started=b.pbi_start_tvsec;
 strncpy(p->name,b.pbi_name[0]?b.pbi_name:b.pbi_comm,255); proc_pidpath(p->pid,p->path,sizeof(p->path));
 if(proc_pidinfo(p->pid,PROC_PIDTASKINFO,0,&t,sizeof(t))==sizeof(t)){p->resident=t.pti_resident_size;p->cpu_ns=t.pti_total_user+t.pti_total_system;p->threads=t.pti_threadnum;}
 struct rusage_info_v4 r={0}; if(proc_pid_rusage(p->pid,RUSAGE_INFO_V4,(rusage_info_t*)&r)==0){mach_timebase_info_data_t tb;mach_timebase_info(&tb);p->cpu_ns=(uint64_t)((long double)(r.ri_user_time+r.ri_system_time)*tb.numer/tb.denom);p->resident=r.ri_resident_size;p->read_bytes=r.ri_diskio_bytesread;p->write_bytes=r.ri_diskio_byteswritten;p->io_valid=1;}
 } free(pids);return n;
}
TMSystem tm_system(void) {
 TMSystem s={0};s.cores=1;size_t z=sizeof(s.memory_total);sysctlbyname("hw.memsize",&s.memory_total,&z,NULL,0);z=sizeof(s.cores);sysctlbyname("hw.logicalcpu",&s.cores,&z,NULL,0);
 host_cpu_load_info_data_t c={0};mach_msg_type_number_t count=HOST_CPU_LOAD_INFO_COUNT;static uint64_t previousTotal=0,previousIdle=0,previousKernel=0;
 if(host_statistics(mach_host_self(),HOST_CPU_LOAD_INFO,(host_info_t)&c,&count)==KERN_SUCCESS){uint64_t total=0;for(int i=0;i<CPU_STATE_MAX;i++)total+=c.cpu_ticks[i];uint64_t idle=c.cpu_ticks[CPU_STATE_IDLE];if(previousTotal && total>previousTotal){s.cpu=100.0*(1.0-(double)(idle-previousIdle)/(total-previousTotal));s.kernel=100.0*(double)(c.cpu_ticks[CPU_STATE_SYSTEM]-previousKernel)/(total-previousTotal);}previousTotal=total;previousIdle=idle;previousKernel=c.cpu_ticks[CPU_STATE_SYSTEM];}
 natural_t processorCount=0; processor_info_array_t processorInfo=NULL; mach_msg_type_number_t processorInfoCount=0;
 static uint64_t prevCoreTotal[128]={0},prevCoreIdle[128]={0},prevCoreKernel[128]={0};
 if(host_processor_info(mach_host_self(),PROCESSOR_CPU_LOAD_INFO,&processorCount,&processorInfo,&processorInfoCount)==KERN_SUCCESS){
  for(unsigned int i=0;i<processorCount && i<128;i++){uint64_t total=0;for(int j=0;j<CPU_STATE_MAX;j++)total+=(uint32_t)processorInfo[i*CPU_STATE_MAX+j];uint64_t idle=(uint32_t)processorInfo[i*CPU_STATE_MAX+CPU_STATE_IDLE];if(prevCoreTotal[i] && total>prevCoreTotal[i]){s.core_usage[i]=100.0*(1.0-(double)(idle-prevCoreIdle[i])/(total-prevCoreTotal[i]));s.core_kernel[i]=100.0*(double)((uint32_t)processorInfo[i*CPU_STATE_MAX+CPU_STATE_SYSTEM]-prevCoreKernel[i])/(total-prevCoreTotal[i]);}prevCoreTotal[i]=total;prevCoreIdle[i]=idle;prevCoreKernel[i]=(uint32_t)processorInfo[i*CPU_STATE_MAX+CPU_STATE_SYSTEM];}
  vm_deallocate(mach_task_self(),(vm_address_t)processorInfo,processorInfoCount*sizeof(integer_t));
 }
 vm_statistics64_data_t v={0};count=HOST_VM_INFO64_COUNT;vm_size_t page=0;host_page_size(mach_host_self(),&page);
 if(host_statistics64(mach_host_self(),HOST_VM_INFO64,(host_info64_t)&v,&count)==KERN_SUCCESS){int64_t used=(int64_t)v.active_count+v.inactive_count+v.speculative_count+v.wire_count+v.compressor_page_count-v.purgeable_count-v.external_page_count;s.memory_used=used>0 ? (uint64_t)used*page : 0;if(s.memory_used>s.memory_total)s.memory_used=s.memory_total;s.compressed=(uint64_t)v.compressor_page_count*page;s.memory_active=(uint64_t)v.active_count*page;s.memory_wired=(uint64_t)v.wire_count*page;s.memory_cached=((uint64_t)v.external_page_count+v.purgeable_count)*page;s.memory_free=((uint64_t)v.free_count+v.speculative_count)*page;}
 struct xsw_usage swap={0};z=sizeof(swap);if(sysctlbyname("vm.swapusage",&swap,&z,NULL,0)==0){s.swap_used=swap.xsu_used;s.swap_total=swap.xsu_total;}
 // Stats' NET_RT_IFLIST2 approach uses 64-bit counters, avoiding 4 GiB rollover.
 // Physical Ethernet/Wi-Fi interfaces prevent counting VPN traffic twice.
 int mib[]={CTL_NET,PF_ROUTE,0,0,NET_RT_IFLIST2,0};size_t length=0;
 if(sysctl(mib,6,NULL,&length,NULL,0)==0 && length>0){char *buffer=malloc(length);if(buffer && sysctl(mib,6,buffer,&length,NULL,0)==0){size_t offset=0;while(offset+sizeof(struct if_msghdr)<=length){struct if_msghdr *h=(void*)(buffer+offset);if(!h->ifm_msglen || offset+h->ifm_msglen>length)break;if(h->ifm_type==RTM_IFINFO2 && h->ifm_msglen>=sizeof(struct if_msghdr2)){struct if_msghdr2 *d=(void*)h;if(!(d->ifm_flags&IFF_LOOPBACK) && d->ifm_data.ifi_type==IFT_ETHER){s.net_in+=d->ifm_data.ifi_ibytes;s.net_out+=d->ifm_data.ifi_obytes;}}offset+=h->ifm_msglen;}}free(buffer);}return s;
}
