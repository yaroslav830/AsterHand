#import "PCMemoryBudget.h"
#include <unistd.h>
#include <errno.h>
extern int memorystatus_control(uint32_t,int32_t,uint32_t,void *,size_t);
BOOL PCEnsureServiceMemoryBudget(void) {
    struct {int32_t active;uint32_t activeFlags;int32_t inactive;uint32_t inactiveFlags;} limits={0};
    int read=memorystatus_control(8,getpid(),0,&limits,sizeof(limits));
    // -1 means the system's default daemon limit, not an unlimited budget.
    if(read==0&&limits.active>=256&&limits.inactive>=256)return YES;
    int result=memorystatus_control(6,getpid(),256,NULL,0);
    NSLog(@"AsterHand service memory budget: pid=%d previous=%d/%d MB requested=256 MB result=%d errno=%d",getpid(),limits.active,limits.inactive,result,result<0?errno:0);
    return result==0;
}
