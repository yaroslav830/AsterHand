#import <Foundation/Foundation.h>
// Read-only LAN discovery. Results are untrusted until pairing verifies identity.
NSDictionary *PCDiscoveryRun(void (^progress)(NSArray *devices, NSString *status));
NSDictionary *PCDiscoveryDecodeJSON(NSData *wire);
// Only probes this on-link IPv4, then checks the advertised public-key hash.
NSDictionary *PCDiscoveryProbeHost(NSString *host,NSString *expectedDeviceID,NSError **error);
