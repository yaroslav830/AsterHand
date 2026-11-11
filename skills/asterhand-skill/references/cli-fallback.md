# Optional CLI adapter

Read only when MCP is unavailable, lacks the requested operation, or the user specifically requests CLI. Do not switch after a permission refusal or uncertain write. The CLI exposes the same receiver permissions and shared client as MCP.

Resolve this installed skill folder and use its absolute `scripts/asterhand.mjs` path as `<cli>`. The launcher locates the AsterHand project through the local project pointer; it contains no separate transport, pairing keys or credentials. The project must still be present. In a source checkout the direct adapter is `cli/asterhand.mjs`.

```
node <cli> --help
node <cli> list
node <cli> --device EXACT_UUID info
node <cli> --device EXACT_UUID screenshot --out NEW_ABSOLUTE_PATH.jpg
node <cli> --device EXACT_UUID control begin --lease 120
node <cli> --device EXACT_UUID tap --x 0.5 --y 0.4
node <cli> --device EXACT_UUID control end
node <cli> --device EXACT_UUID terminal open
```

Inspect screenshot pixels with the image-viewing tool before coordinate actions, verify afterward, and end control presence in finally. Use UTF-8 `--text-file`, `--command-file` and `--args-file` inputs for text, commands and JSON to avoid shell interpolation. Close owned terminal sessions. A nonzero exit code or remote refusal is a failure.

Configuration resolution: explicit `--config`, `ASTERHAND_HOME`/legacy `AGENTGO_HOME`, project ancestor `.private/control/control.json`, then `~/.codex/asterhand.json`/legacy `agentgo.json` (CODEX_HOME respected). Never print those files. Installation writes only the project pointer; it does not copy keys. The launcher resolves code separately from device configuration, so an explicit configuration never selects a different program.

Run `--help` for commands; read [application-api.md](application-api.md) only for relevant application parameters. Windows discovery, pairing/settings and Windows AI need the local control center running. Ordinary paired-phone calls do not. Exports, captures and video use new output paths and never overwrite existing files. Failed writes/uploads are not automatically retried.
