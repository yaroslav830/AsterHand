# AsterHand LAN control protocol v1

[English](CONTROL_PROTOCOL.md) · [简体中文](CONTROL_PROTOCOL.zh-CN.md)

The implementation covers iOS, Android and modern Windows; see the testing documentation for actual OS coverage. The default listener is TCP 18769. When receiving control is disabled, it only answers unauthenticated `/info` metadata requests and rejects execution requests. The desktop browser console binds only to 127.0.0.1:18767, with a random session path, Host/Origin validation and CSP. Do not forward this local console as an unauthenticated public service.

## Pairing and permissions

Pairing v2 uses a persistent P-256 identity. The device identifier is the SHA-256 of its uncompressed public key. `/info` exposes public metadata only; `/pair` exchanges encrypted requests and decisions. ECDH derives the channel key and the verification code shown to both parties. The receiver chooses Allow once, Always allow or Reject. Grants are stored against the device's public-key identity. IP addresses are used for discovery and routing; an address change does not change identity.

A request expires after 120 seconds. After an unexpected disconnect, a one-time session is retained for up to 600 seconds, renewed by authenticated activity. `session.close` explicitly releases a one-time grant. Persistent grants can be revoked individually. Pairing codes may rotate or remain fixed; they assist discovery and do not authorize execution. Legacy invitation import remains available for migration; invitations contain control credentials and must never enter distribution packages.

API keys and ChatGPT login tokens do not participate in pairing and are never synchronized by this protocol. Shared keys authorize control operations only; there is no API for reading the app Keychain. iOS Root and screen control depend on the receiver's local settings. Windows runs with the current desktop user's permissions and cannot control the lock screen, secure desktop or windows at a higher integrity level.

The Android receiver uses the locally selected Standard, ADB or Root tier and checks the remote-screen switch separately. Execution results report the actual UID. Missing ADB activation or Root authorization causes failure; the receiver does not elevate automatically. Standard-tier screen APIs depend on the user's accessibility grant and Android version. Android's dedicated ADB activation channel binds to loopback only and uses separate HMAC authentication. It is not a LAN pairing credential and is not exposed to remote controllers.

## Command messages

`POST /rpc` accepts a JSON envelope `{v, pair, iv, data, mac}`. Its plaintext payload is `{id, ts, method, args}`; a response contains `{id, ts, result}`.

- Independent keys are derived from the shared secret using HMAC-SHA256 with the labels `AgentGo/v1/encryption/<direction>` and `AgentGo/v1/authentication/<direction>`. The direction is `req` or `res`.
- Encryption uses AES-256-CBC / PKCS#7 with a fresh random 128-bit IV per message.
- HMAC-SHA256 is verified before decryption. The MAC input is UTF-8 `v1\n<direction>\n<pair>\n<iv-base64>\n<data-base64>`, with fixed-length MAC comparison.
- Request timestamps may differ from the receiver by at most 90 seconds. Reused request UUIDs are rejected for 180 seconds. Clients verify the response UUID and pairing channel. Keep device clocks accurate.
- Requests and individual frames are limited to 2 MiB; ordinary file reads and writes have smaller limits. Nested remote forwarding is not allowed. Receivers accept an explicit tool allowlist only.

Control methods include `hello`, `info`, `presence`, `session.close`, `execute` and `terminal.open/read/write/interrupt/close`. `execute` supports file reads, writes and directory operations, `run_shell`, and `screen_capture/tap/swipe/type/home`. Tool errors must be shown as failures. AI approval occurs at the initiating agent layer; manual control and paired incoming requests execute under the receiver's permissions.

## Interactive remote-control compatibility

Desktop control of an iPhone prefers the existing VNC / TLS / WebSocket channel and presents it in the unified control center. An authenticated `vnc.info` request obtains short-lived VNC authentication details bound to the pairing and the public certificate. Local screen permission and the device pairing still apply. This API returns no server private key or AI credentials. The desktop proxy validates the CA, hostname and certificate SHA-256; browser connections retain the random local path and Origin checks. Older phone versions use this compatibility path only when an existing local VNC pairing configuration is complete.

VNC frames, continuous pointer events and keyboard events are forwarded in both directions immediately, instead of delaying a whole drag until release. Revocation or disabling screen permission terminates control-center connections. Full-screen and scaling change the local display only, not the target device's resolution.

## Fallback live screen

An encrypted `stream2` request establishes a persistent HTTP response. Each record contains a four-byte big-endian length followed by an encrypted frame. The frame-key direction label is `stream/<request UUID>`, binding frames to this connection.

A frame record is `IV(16) | AES-CBC ciphertext | HMAC(32)`. The MAC covers the IV and ciphertext with a separately derived authentication key. Decrypted data starts with four big-endian uint32 values: increasing transport sequence number, width, height and capture sequence number, followed by JPEG bytes. Clients reject invalid MACs and non-increasing sequence numbers. The JPEG also carries dimensions; Windows frame-header dimensions may currently be zero.

iOS continuous capture targets 30 FPS and runs only while being watched; resizing uses vImage. The RPC proxy checks permissions and revocation, stopping in approximately 0.5 seconds. Screen frames are not added to persistent conversations. Desktop WebSocket proxies and clients discard queued frames to avoid stale-image backlog. Phone capture resources are released about three seconds after viewing stops.

Android uses the same encrypted `stream2` frame format, but capture currently uses accessibility screenshots or ADB / Root `screencap`, without hardware video encoding. The Android phone-control page retrieves single frames sequentially to avoid queued requests. Protocol compatibility or a successful screenshot does not establish iOS VNC performance.

## Terminals and stopping

Terminal identifiers are random UUIDs bound to the initiating pairing. Other pairings cannot read or write that session. Each process supports up to eight sessions, a 256 KiB buffer and a 20-minute idle timeout. iOS uses a validated persistent non-interactive shell session; Windows uses persistent PowerShell sessions. Interrupting terminates the session's process group or process tree; the user can open another session. Full PTY / VT screen emulation is not provided.

Revocation cleans up the pairing's terminals; disabling Root stops Root terminals. Cancellation attempts to terminate the created process group or process tree, but cannot undo completed file or system changes. The protocol provides no option to ignore the target's permissions.

## Checks

- `node scripts/check_control.mjs`: isolated bidirectional pairing, identity authentication, replay/tamper handling, video-connection binding, terminal isolation, simulated AI tool loops and revocation.
- `node scripts/check_phone_control.mjs <paired-phone-IP>`: read-only marker commands, persistent variables, interruption, reopening/closing sessions and remote cancellation. This temporarily opens test terminals.
- `node scripts/check_stream.mjs <paired-phone-IP-or-local>`: times receipt of 180 frames and records statistics only, without saving screen content.

These are implementation checks and validation on specified devices, not an independent security audit. Network, cryptography, runtime, capture and input implementations still need separate validation before claiming older-platform support.
