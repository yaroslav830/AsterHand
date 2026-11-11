#include "../Sources/PCVoiceIdle.h"
#include <assert.h>
#include <stdio.h>
int main(void){
    PCVoiceIdleClock clock={0};
    assert(PCVoiceIdleLimit(0)==0&&PCVoiceIdleLimit(.9)==0&&PCVoiceIdleLimit(1)==1&&PCVoiceIdleLimit(5)==5&&PCVoiceIdleLimit(10)==10&&PCVoiceIdleLimit(15)==15&&PCVoiceIdleLimit(3600)==3600&&PCVoiceIdleLimit(3601)==0&&PCVoiceIdleLimit(NAN)==0);
    assert(PCVoiceIdleConfiguredLimit(0)==5&&PCVoiceIdleConfiguredLimit(NAN)==5&&PCVoiceIdleConfiguredLimit(-1)==5&&PCVoiceIdleConfiguredLimit(5)==5&&PCVoiceIdleConfiguredLimit(10)==10&&PCVoiceIdleConfiguredLimit(15)==15&&PCVoiceIdleConfiguredLimit(30)==30&&PCVoiceIdleConfiguredLimit(3600)==3600);
    assert(!PCVoiceIdleTick(&clock,10,5,1,0)&&!PCVoiceIdleTick(&clock,14.99,5,1,0)&&PCVoiceIdleTick(&clock,15,5,1,0));clock=(PCVoiceIdleClock){0};
    assert(!PCVoiceIdleTick(&clock,100,0,1,0)&&!PCVoiceIdleTick(&clock,10000,0,1,0));
    assert(!PCVoiceIdleTick(&clock,10000,30,1,0)); /* enabling grants a full new interval */
    assert(!PCVoiceIdleTick(&clock,10029.9,30,1,0)&&PCVoiceIdleTick(&clock,10030,30,1,0));
    clock=(PCVoiceIdleClock){0};assert(!PCVoiceIdleTick(&clock,10,30,1,0));
    assert(!PCVoiceIdleTick(&clock,39,30,1,1)); /* real partial recognition */
    assert(!PCVoiceIdleTick(&clock,68.9,30,1,0)&&PCVoiceIdleTick(&clock,69,30,1,0));
    assert(!PCVoiceIdleTick(&clock,70,30,0,0)); /* AI waiting / reading pause */
    assert(!PCVoiceIdleTick(&clock,500,30,0,0));
    assert(!PCVoiceIdleTick(&clock,501,30,1,0)&&!PCVoiceIdleTick(&clock,530.9,30,1,0)&&PCVoiceIdleTick(&clock,531,30,1,0));
    clock=(PCVoiceIdleClock){0};assert(!PCVoiceIdleTick(&clock,10,120,1,0));
    assert(!PCVoiceIdleTick(&clock,60,120,1,0)); /* recognizer restart is still waiting */
    assert(!PCVoiceIdleTick(&clock,110,120,1,0)&&PCVoiceIdleTick(&clock,130,120,1,0));
    /* Muting the microphone produces no fake input: same wait continues. */
    clock=(PCVoiceIdleClock){0};assert(!PCVoiceIdleTick(&clock,0,10,1,0)&&PCVoiceIdleTick(&clock,10,10,1,0));
    assert(!PCVoiceIdleTick(&clock,5,10,1,0)); /* clock rollback cannot cause false expiry */
    assert(!PCVoiceIdleTick(&clock,6,60,1,0)&&!PCVoiceIdleTick(&clock,65,60,1,0)&&PCVoiceIdleTick(&clock,66,60,1,0));
    puts("voice idle state checks passed");return 0;
}
