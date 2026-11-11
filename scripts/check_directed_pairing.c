#include "../Sources/PCDirectedPairing.h"
#include <assert.h>
#include <stdio.h>
int main(void){
 const char *id="0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";uint32_t address=0;
 assert(PCDirectedPairingInput("192.168.1.34",id,&address)&&address==0xc0a80122);
 assert(PCDirectedPairingInput("10.190.135.2",id,0)&&PCDirectedPairingInput("100.64.0.1",id,0));
 const char *bad[]={"192.168.001.34","192.168.1.256","192.168.1","192.168.1.34.","192.168.1.34:18769","http://192.168.1.34","192.168.1.34/rpc","192.168.1.34\n"," 192.168.1.34","192.168.1.34;id","127.0.0.1","0.0.0.0","224.0.0.1","255.255.255.255","169.254.1.1","localhost","1.2.3.4.5",""};
 for(unsigned i=0;i<sizeof(bad)/sizeof(*bad);i++)assert(!PCDirectedPairingInput(bad[i],id,0));
 assert(!PCDirectedPairingInput("192.168.1.34","",0)&&!PCDirectedPairingInput("192.168.1.34","abc",0));
 assert(!PCDirectedPairingInput("192.168.1.34","0123456789ABCDEF0123456789abcdef0123456789abcdef0123456789abcdef",0));
 puts("directed pairing input checks passed");return 0;
}
