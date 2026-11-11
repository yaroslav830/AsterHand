#ifndef PC_DIRECTED_PAIRING_H
#define PC_DIRECTED_PAIRING_H
#include <stdint.h>

/* Canonical dotted IPv4 + complete public identity hash. No names/ports/paths. */
static inline int PCDirectedPairingInput(const char *host,const char *identifier,uint32_t *address){
    if(!host||!identifier)return 0;
    for(unsigned i=0;i<64;i++){char c=identifier[i];if(!((c>='0'&&c<='9')||(c>='a'&&c<='f')))return 0;}if(identifier[64])return 0;
    uint32_t result=0;const char *cursor=host;
    for(unsigned part=0;part<4;part++){
        if(*cursor<'0'||*cursor>'9')return 0;unsigned value=0,digits=0;int zero=*cursor=='0';
        while(*cursor>='0'&&*cursor<='9'){value=value*10+(unsigned)(*cursor-'0');if(++digits>3||value>255||(zero&&digits>1))return 0;cursor++;}
        result=(result<<8)|value;if(part<3){if(*cursor++!='.')return 0;}else if(*cursor)return 0;
    }
    if((result>>24)==0||(result>>24)==127||(result>>28)>=14||(result>>16)==0xa9fe)return 0;
    if(address)*address=result;return 1;
}
#endif
