"""Install the local stdio MCP using Codex's CLI; never copies pairing credentials."""
import argparse
import datetime
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import tomllib
import uuid

ROOT = Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--codex-home', type=Path)
    parser.add_argument('--config', type=Path, help='Exact local mcp-bridge.json or legacy control.json path')
    parser.add_argument('--skip-dependencies', action='store_true')
    args = parser.parse_args()
    home = (args.codex_home or Path(os.environ.get('CODEX_HOME', Path.home()/'.codex'))).resolve()
    node, codex = shutil.which('node'), shutil.which('codex')
    if not node or not codex:
        raise SystemExit('Node 20+ and Codex CLI must be available on PATH.')
    server = ROOT/'mcp/server.mjs'
    if not server.is_file():
        raise SystemExit('AsterHand MCP source missing.')
    native = (Path(os.environ.get('APPDATA', Path.home()/'AppData/Roaming'))/'AsterHand/Windows/mcp-bridge.json' if sys.platform=='win32' else Path(os.environ.get('XDG_DATA_HOME',Path.home()/'.local/share'))/'asterhand/mcp-bridge.json' if sys.platform.startswith('linux') else None)
    endpoint=(args.config.resolve() if args.config else native if native and native.is_file() else None)
    if endpoint and not endpoint.is_file():raise SystemExit('Start AsterHand and verify the selected local MCP configuration path.')
    if not args.skip_dependencies:
        bundled = Path(node).parent.parent/'node_modules/pnpm/bin/pnpm.cjs'
        pnpm = shutil.which('pnpm')
        if bundled.is_file():
            command = [node, str(bundled)]
        elif pnpm:
            command = [pnpm]
        else:
            raise SystemExit('Install MCP dependencies first: pnpm --dir mcp install --frozen-lockfile --ignore-scripts; then rerun with --skip-dependencies.')
        subprocess.run(command+['--dir',str(ROOT/'mcp'),'install','--frozen-lockfile','--ignore-scripts'],check=True)
    subprocess.run([node,'--input-type=module','-e',"await import('./mcp/server.mjs')"],cwd=ROOT,check=True)
    home.mkdir(parents=True,exist_ok=True)
    configuration = home/'config.toml'
    before = configuration.read_bytes() if configuration.exists() else b''
    if before:
        tomllib.loads(before.decode('utf-8-sig'))
        backup = home/'backups'/('asterhand-mcp-'+uuid.uuid4().hex+'.toml')
        backup.parent.mkdir(exist_ok=True)
        with os.fdopen(os.open(backup,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600),'wb') as out:
            out.write(before)
    # Codex can normalize unrelated settings when rewriting its whole config.
    # Generate our stanza in isolation, then merge only the owned tables.
    with tempfile.TemporaryDirectory(prefix='asterhand-mcp-config-') as stage:
        assert Path(stage).resolve().name.startswith('asterhand-mcp-config-')
        env = dict(os.environ,CODEX_HOME=stage)
        endpoint_env='ASTERHAND_CONFIG='+str(endpoint) if endpoint else 'ASTERHAND_HOME='+str(ROOT)
        subprocess.run([codex,'mcp','add','asterhand','--env',endpoint_env,'--',node,str(server)],env=env,check=True)
        entry = tomllib.loads((Path(stage)/'config.toml').read_text(encoding='utf-8'))['mcp_servers']['asterhand']
    old = tomllib.loads(before.decode('utf-8-sig')) if before else {}
    existing = old.get('mcp_servers',{}).get('asterhand',{})
    for key in ['enabled','required','enabled_tools','disabled_tools','default_tools_approval_mode','tools','env_vars','cwd']:
        if key in existing:
            entry[key]=existing[key]
    retained_env=dict(existing.get('env',{}))
    if endpoint:retained_env.pop('ASTERHAND_HOME',None)
    entry['env']={**retained_env,**entry.get('env',{})}
    entry.update(startup_timeout_sec=20,tool_timeout_sec=180)
    def key_name(value):
        return value if re.fullmatch(r'[A-Za-z0-9_-]+',value) else json.dumps(value,ensure_ascii=False)
    def stanza(value,keys):
        lines=['['+'.'.join(key_name(k) for k in keys)+']']
        for key,item in value.items():
            if not isinstance(item,dict):
                lines.append(key_name(key)+' = '+json.dumps(item,ensure_ascii=False,allow_nan=False))
        sections=['\n'.join(lines)+'\n']
        for key,item in value.items():
            if isinstance(item,dict):
                sections.append(stanza(item,keys+[key]))
        return '\n'.join(sections)
    text = before.decode('utf-8-sig')
    owned = re.compile(r'''^\[mcp_servers\.(?:asterhand|"asterhand"|'asterhand')(?:\.[^\]]+)?\]\s*$''')
    kept=[];skip=False
    for line in text.splitlines(keepends=True):
        if line.lstrip().startswith('['):
            skip=bool(owned.fullmatch(line.strip()))
        if not skip:
            kept.append(line)
    updated=''.join(kept).rstrip()+'\n\n'+stanza(entry,['mcp_servers','asterhand'])
    parsed = tomllib.loads(updated)
    entry = parsed['mcp_servers']['asterhand']
    assert entry['command']==node and entry['args']==[str(server)] and entry['env']['ASTERHAND_HOME']==str(ROOT)
    other = dict(parsed);other['mcp_servers']=dict(parsed.get('mcp_servers',{}));other['mcp_servers'].pop('asterhand',None)
    previous = dict(old);previous['mcp_servers']=dict(old.get('mcp_servers',{}));previous['mcp_servers'].pop('asterhand',None)
    assert other==previous,'Unrelated Codex settings changed; backup retained for review.'
    with configuration.open('w',encoding='utf-8',newline='') as out:
        out.write(updated)
    assert tomllib.loads(configuration.read_text(encoding='utf-8'))==parsed
    # A disposable installer test must not replace the live installation record.
    default_home = Path(os.environ.get('CODEX_HOME',Path.home()/'.codex')).resolve()
    if home==default_home:
        record = ROOT/'.private/mcp/installation.json';record.parent.mkdir(parents=True,exist_ok=True)
        record.write_text(json.dumps({'name':'asterhand','version':json.loads((ROOT/'version.json').read_text())['version'],'server':str(server),'configuration':str(configuration),'installed_at':datetime.datetime.now(datetime.timezone.utc).isoformat()},indent=2),encoding='utf-8')
    print('AsterHand MCP configured. Reconnect MCP or start a new Codex chat. Pairings and receiver permissions unchanged.')

if __name__=='__main__':
    main()
