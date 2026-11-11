"""Exercise the real Codex config generator only in a disposable isolated home."""
from pathlib import Path
import subprocess
import sys
import tempfile
import tomllib

root=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='asterhand-mcp-installer-') as folder:
    home=Path(folder).resolve()
    assert home.name.startswith('asterhand-mcp-installer-')
    config=home/'config.toml'
    config.write_text('model_reasoning_effort="low"\n[mcp_servers.fixture]\ncommand="fixture-command"\nargs=[]\n[mcp_servers.asterhand]\ncommand="old-command"\ndisabled_tools=["shell"]\n[mcp_servers.asterhand.env]\nKEEP_ME="fixture-value"\n',encoding='utf-8')
    for _ in range(2):
        before=tomllib.loads(config.read_text(encoding='utf-8'))
        done=subprocess.run([sys.executable,str(root/'scripts/install_asterhand_mcp.py'),'--codex-home',str(home),'--skip-dependencies'],cwd=root,capture_output=True,text=True,encoding='utf-8')
        assert done.returncode==0,done.stderr
        after=tomllib.loads(config.read_text(encoding='utf-8'))
        assert after['mcp_servers']['fixture']==before['mcp_servers']['fixture']
        assert after['model_reasoning_effort']=='low'
        assert after['mcp_servers']['asterhand']['disabled_tools']==['shell']
        assert after['mcp_servers']['asterhand']['env']['KEEP_ME']=='fixture-value'
        assert after['mcp_servers']['asterhand']['tool_timeout_sec']==180
    assert len(list((home/'backups').glob('*.toml')))==2
print('MCP installer: unrelated empty args / settings / tool policy / environment / backups / repeat install preserved')
