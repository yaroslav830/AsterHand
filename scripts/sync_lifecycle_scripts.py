"""Generate identical lifecycle rules for the three bootstrap layouts."""
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
LABELS='local.agentgo.agent local.agentgo.control local.pocketagent.remote local.pocketagent.root local.pocketagent.screen local.pocketagent.overlay local.asterhand.recovery'
def scripts(environment):
    prefix='/var/jb' if environment=='rootless' else ''
    shell=prefix+'/bin/sh';app=prefix+'/Applications/PocketCodex.app';launch=prefix+('/usr/bin/launchctl' if prefix else '/bin/launchctl')
    path=(prefix+'/usr/bin:'+prefix+'/bin:'+prefix+'/usr/sbin:'+prefix+'/sbin:') if prefix else ''
    private='/var/pr' if environment=='roothide' else '/var/lib/asterhand' if environment=='rootful' else '/var/jb/var/agentgo'
    common=f'''#!{shell}
PATH={path}/usr/bin:/bin:/usr/sbin:/sbin
export PATH
app='{app}'
maint="$app/pocketmaint"
launch='{launch}'
labels='{LABELS}'
'''
    stop='''for label in $labels; do "$launch" disable "system/$label" >/dev/null 2>&1 || true; done
"$maint" stop || true
for label in $labels; do "$launch" bootout "system/$label" >/dev/null 2>&1 || true; done
"$maint" stop || true
'''
    postinst=common+'''set -e
if [ "$1" != configure ]; then exit 0; fi
for directory in PocketCodexRemote PocketAgentControl AgentGoControl AgentGoTasks; do
    mkdir -p "/var/mobile/Library/$directory"
    chown mobile:mobile "/var/mobile/Library/$directory"
    chmod 0700 "/var/mobile/Library/$directory"
done
'''+f'''mkdir -p '{private}'
chown root:wheel '{private}'
chmod 0711 '{private}'
'''+'''if [ ! -f /var/mobile/Library/PocketAgentControl/state.json ]; then
    printf '{"enabled":true,"visibility_request":"initial","haptic_style":"system"}\\n' > /var/mobile/Library/PocketAgentControl/state.json
    chown mobile:mobile /var/mobile/Library/PocketAgentControl/state.json
    chmod 0600 /var/mobile/Library/PocketAgentControl/state.json
fi
if [ ! -f /var/mobile/Library/PocketCodexRemote/remote-settings.json ]; then
    printf '{"auto_approve":false,"trusted_hosts":[]}\\n' > /var/mobile/Library/PocketCodexRemote/remote-settings.json
    chown mobile:mobile /var/mobile/Library/PocketCodexRemote/remote-settings.json
    chmod 0600 /var/mobile/Library/PocketCodexRemote/remote-settings.json
fi
log=/var/mobile/Library/PocketAgentControl/install.log
printf 'AsterHand configure begin\\n' > "$log"
chown mobile:mobile "$log"
chmod 0600 "$log"
'''+stop+f'''if ! "$maint" recover-configure >>"$log" 2>&1; then
    tail -n 12 "$log"
    exit 1
fi
if ! "$maint" run 30 '{prefix}/usr/bin/uicache' -p "$app" >>"$log" 2>&1; then
    tail -n 12 "$log"
    exit 1
fi
for label in $labels; do
    "$launch" enable "system/$label" >>"$log" 2>&1 || true
    if ! "$maint" run 12 "$launch" bootstrap system '{prefix}/Library/LaunchDaemons/'"$label.plist" >>"$log" 2>&1; then
        tail -n 12 "$log"
        exit 1
    fi
done
printf 'AsterHand configure complete\\n' >> "$log"
exit 0
'''
    prerm=common+'''case "$1" in
    remove|upgrade|deconfigure)
'''+stop+f'''        if [ "$1" = remove ]; then
            "$maint" cleanup || true
            "$maint" run 20 '{prefix}/usr/bin/uicache' -u "$app" || true
        fi
        ;;
esac
exit 0
'''
    postrm=common+f'''if [ "$1" = remove ] || [ "$1" = purge ]; then
    for label in $labels; do "$launch" bootout "system/$label" >/dev/null 2>&1 || true; done
    # Fixed application-owned directory only; never traverse a user workspace.
    case "$app" in
        {app}) rm -rf "$app" ;;
        *) exit 1 ;;
    esac
fi
exit 0
'''
    return {'postinst':postinst,'prerm':prerm,'postrm':postrm}
def main():
    for environment,directory in [('rootful','packaging-rootful'),('rootless','packaging'),('roothide','packaging-roothide')]:
        for name,text in scripts(environment).items():(ROOT/directory/'DEBIAN'/name).write_text(text,encoding='utf8')
if __name__=='__main__':main()
