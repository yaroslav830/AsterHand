#!/bin/sh
# Read-only bootstrap detection. Does not add sources, install packages, or grant permissions.
set -u
base='https://yaroslav830.github.io/AsterHand/ios-apt/'
architecture=$(dpkg --print-architecture 2>/dev/null) || architecture='unknown'
case "$architecture" in
  iphoneos-arm) environment='rootful'; label='Rootful'; minimum=14 ;;
  iphoneos-arm64) environment='rootless'; label='Rootless'; minimum=15 ;;
  iphoneos-arm64e) environment='roothide'; label='RootHide'; minimum=15 ;;
  *) printf '%s\n' '{"environment":"unknown","compatible":false,"reason":"Unsupported or unavailable dpkg architecture"}'; exit 2 ;;
esac
version=$(sw_vers -productVersion 2>/dev/null) || version=''
case "$version" in ''|*[!0-9.]*) version=''; compatible='null' ;;
  *) major=${version%%.*}; if [ "$major" -lt "$minimum" ]; then compatible='false'; else compatible='true'; fi ;;
esac
printf '{"environment":"%s","architecture":"%s","ios_version":"%s","minimum_ios":%s,"compatible":%s,"source":"%s%s/","deb":"%spool/AsterHand-@VERSION@-%s.deb"}\n' "$environment" "$architecture" "$version" "$minimum" "$compatible" "$base" "$environment" "$base" "$label"
[ "$compatible" != 'false' ]
