// SPDX-License-Identifier: GPL-3.0-or-later
// Modified for Houston, 2026-10-09; see THIRD-PARTY-NOTICES.md.
#include "Metrics.h"
#include "CPUDelta.h"
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
#include <dlfcn.h>
#include <string.h>
// Private libSystem SPI (used by Chromium); resolved at runtime so a missing symbol only disables attribution.
typedef pid_t (*tm_responsible_fn)(pid_t);
int tm_processes(TMProcess *out,int capacity) {
 static tm_responsible_fn responsible=NULL; static int resolved=0; if(!resolved){responsible=(tm_responsible_fn)dlsym(RTLD_DEFAULT,"responsibility_get_pid_responsible_for_pid");resolved=1;}
 int bytes=proc_listallpids(NULL,0); if(bytes<0)bytes=0; int *pids=calloc(bytes+1024,sizeof(int)); if(!pids)return 0; int count=proc_listallpids(pids,(bytes+1024)*sizeof(int)); int n=0;
 for(int i=0;i<count && n<capacity;i++) { if(pids[i]<=0)continue; struct proc_bsdinfo b={0}; struct proc_taskinfo t={0};
 if(proc_pidinfo(pids[i],PROC_PIDTBSDINFO,0,&b,sizeof(b))!=sizeof(b))continue;
 TMProcess *p=&out[n++]; memset(p,0,sizeof(*p)); p->pid=pids[i]; p->ppid=b.pbi_ppid;p->uid=b.pbi_uid;p->started=b.pbi_start_tvsec; if(responsible){pid_t r=responsible(p->pid);p->responsible=r>0?r:0;}
 /* pbi_name/pbi_comm are not NUL-terminated at full length; p->name was zeroed above. */ if(b.pbi_name[0])memcpy(p->name,b.pbi_name,strnlen(b.pbi_name,sizeof(b.pbi_name)));else memcpy(p->name,b.pbi_comm,strnlen(b.pbi_comm,sizeof(b.pbi_comm))); proc_pidpath(p->pid,p->path,sizeof(p->path));
 if(proc_pidinfo(p->pid,PROC_PIDTASKINFO,0,&t,sizeof(t))==sizeof(t)){p->resident=t.pti_resident_size;p->cpu_ns=t.pti_total_user+t.pti_total_system;p->threads=t.pti_threadnum;}
 struct rusage_info_v4 r={0}; if(proc_pid_rusage(p->pid,RUSAGE_INFO_V4,(rusage_info_t*)&r)==0){static mach_timebase_info_data_t tb={0};if(!tb.denom)mach_timebase_info(&tb);p->cpu_ns=(uint64_t)((long double)(r.ri_user_time+r.ri_system_time)*tb.numer/tb.denom);p->resident=r.ri_resident_size;p->read_bytes=r.ri_diskio_bytesread;p->write_bytes=r.ri_diskio_byteswritten;p->io_valid=1;}
 } free(pids);return n;
}
_Static_assert(CPU_STATE_USER==TM_CPU_USER && CPU_STATE_SYSTEM==TM_CPU_SYSTEM && CPU_STATE_IDLE==TM_CPU_IDLE && CPU_STATE_NICE==TM_CPU_NICE && CPU_STATE_MAX==TM_CPU_STATES,"CPU state layout");
TMSystem tm_system(void) {
 TMSystem s={0};s.cores=1;size_t z=sizeof(s.memory_total);sysctlbyname("hw.memsize",&s.memory_total,&z,NULL,0);z=sizeof(s.cores);sysctlbyname("hw.logicalcpu",&s.cores,&z,NULL,0);
 host_cpu_load_info_data_t c={0};mach_msg_type_number_t count=HOST_CPU_LOAD_INFO_COUNT;static uint32_t previousTicks[TM_CPU_STATES]={0};static int primed=0;
 if(host_statistics(mach_host_self(),HOST_CPU_LOAD_INFO,(host_info_t)&c,&count)==KERN_SUCCESS){uint32_t ticks[TM_CPU_STATES];for(int i=0;i<TM_CPU_STATES;i++)ticks[i]=c.cpu_ticks[i];tm_cpu_delta(ticks,previousTicks,&primed,&s.cpu,&s.kernel);}
 natural_t processorCount=0; processor_info_array_t processorInfo=NULL; mach_msg_type_number_t processorInfoCount=0;
 static uint32_t prevCore[128][TM_CPU_STATES]={{0}};static int primedCore[128]={0};
 if(host_processor_info(mach_host_self(),PROCESSOR_CPU_LOAD_INFO,&processorCount,&processorInfo,&processorInfoCount)==KERN_SUCCESS){
  for(unsigned int i=0;i<processorCount && i<128;i++){uint32_t ticks[TM_CPU_STATES];for(int j=0;j<TM_CPU_STATES;j++)ticks[j]=(uint32_t)processorInfo[i*CPU_STATE_MAX+j];tm_cpu_delta(ticks,prevCore[i],&primedCore[i],&s.core_usage[i],&s.core_kernel[i]);}
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
