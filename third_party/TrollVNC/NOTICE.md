PocketCodex launches pocketremote as a separate process. The remote backend is a
modified TrollVNC, Copyright (c) 2025 82Flex and contributors, GPL-2.0.

Upstream: https://github.com/owngoal-dev/TrollVNC
Exact revision: cfdb737e72977d961eb7d0a8110d2fe1a58551d7
Source archive: https://github.com/yaroslav830/AsterHand/releases/download/v1.0-build82-monorepo/TrollVNC-cfdb737-source.zip (unmodified git archive).
License: COPYING alongside this notice.

Changes are in pocketremote.patch and scripts/build_remote_helper.py:
require TLS WebSockets, accept explicit client clipboard writes without watching
the device clipboard, exit after owning app exits, handle absent IOSurface
accelerator/runloop sources and allocation failures on the tested iOS 16 device.
The helper receives its own entitlements from remote-entitlements.plist.

Matching build 82 helper source, generated source files, build scripts, headers
and entitlements accompany the release at:
https://github.com/yaroslav830/AsterHand/releases/download/v1.0-build82-monorepo/AsterHand-build82-remote-helper-source.zip

Upstream's checked-in static dependencies and headers are used unchanged.
Their upstream build recipes are archived in https://github.com/yaroslav830/AsterHand/releases/download/v1.0-build82-monorepo/BuildVNCServer-4a87482-source.zip,
revision 4a874820ad8db49cc03690b8fc95e65696ac45b8.
Dependency projects: LibVNCServer (GPL-2.0-or-later), LZO 2.10 (GPL-2.0-or-later),
OpenSSL, libjpeg-turbo, libpng and Cyrus SASL. See those projects and the original
build scripts for dependency source revisions and licensing. The Windows build
links the exact archives present in the retained TrollVNC source snapshot; it
does not claim those archives were rebuilt locally from every dependency source.

The browser client uses upstream noVNC (MPL-2.0), copied unchanged from this
TrollVNC snapshot. Its license is in desktop/public/novnc/LICENSE.txt; pako's
license is retained in desktop/public/novnc/vendor/pako/LICENSE.
The desktop WebSocket transport uses ws 8.18.3 (MIT), installed from the npm
registry with SHA-512 archive verification by scripts/bootstrap_desktop.py.

Pairing certificates, passwords and SSH credentials are not part of source or
binary release archives.
