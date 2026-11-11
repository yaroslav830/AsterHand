#ifndef PC_VOICE_IDLE_H
#define PC_VOICE_IDLE_H
#include <math.h>

/* Monotonic, input-only idle timing. No audio, permissions, or wall-clock API. */
typedef struct { double since,limit; int waiting; } PCVoiceIdleClock;
static inline double PCVoiceIdleLimit(double seconds){return isfinite(seconds)&&seconds>=1&&seconds<=3600?floor(seconds):0;}
static inline double PCVoiceIdleConfiguredLimit(double seconds){double value=PCVoiceIdleLimit(seconds);return value>0?value:5;}
static inline int PCVoiceIdleTick(PCVoiceIdleClock *clock,double now,double seconds,int waitingForUser,int receivedInput){
    double limit=PCVoiceIdleLimit(seconds);
    if(!isfinite(now)||now<0){clock->waiting=0;return 0;}
    if(limit!=clock->limit){clock->limit=limit;clock->waiting=0;}
    if(!waitingForUser){clock->waiting=0;return 0;}
    if(!clock->waiting||receivedInput||now<clock->since){clock->waiting=1;clock->since=now;}
    return limit>0&&now-clock->since>=limit;
}
#endif
