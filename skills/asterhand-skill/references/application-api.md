# Application control, version 0.10.21+

Use native MCP tools first: `application(action:"capabilities")`, `projects(action:"list")`, and `phone_ai(action:"status")`, each with an exact `device`. Application fields below go into the grouped MCP tool's `parameters` object; do not prepare CLI files when MCP already exposes the operation. The receiver may require AsterHand to be open. Discovery, Windows settings and Windows AI need the control-center server; ordinary paired phone RPC does not.

The CLI examples are optional compatibility syntax for the same API fields. Read [cli-fallback.md](cli-fallback.md) only when CLI is needed; `<cli>` then means the installed skill's absolute `scripts/asterhand.mjs` launcher. MCP and CLI use the same `shared/asterhand-client.mjs` and encrypted protocol, not separate implementations.

## Devices and video

```
node <cli> devices discover
node <cli> devices pair --host 192.168.1.34 --port 18769
node <cli> devices code --code 123456
node <cli> devices poll --id REQUEST_UUID
node <cli> --device PAIR_UUID stream --seconds 5 --out NEW_FILE.mjpg
```

Pairing only submits an application. The receiver chooses once, always or deny. Poll the returned request ID and verify the reported stable identity. Do not automatically accept or change trust. For discovery initiated by an already paired phone, use `app device.discover`; `app device.begin` takes `{host,device_id,port}` (iOS requires the full expected device ID). `app device.poll` takes `{id}`. `app device.pending` lists requests. `app device.decide` takes `{id,mode,confirm:true}`; it is an authorization change and needs explicit user instruction. `app device.list` returns outgoing pair metadata without keys, and `app device.app` can forward `{id,arguments:{action,...}}` to an existing outgoing pairing; recursive forwarding is refused.

Video is concatenated JPEG frames in an MJPEG file; it is a bounded recording, not a full-screen interactive viewer. Existing files are never overwritten. Frame authentication, lengths and sequence are checked. Metadata reports actual frames and elapsed time. A partial file can remain after an interrupted recording.

## Projects and conversations

```
node <cli> --device PAIR_UUID project list
node <cli> --device PAIR_UUID project create --name "Example"
node <cli> --device PAIR_UUID project select --id PROJECT_UUID
node <cli> --device PAIR_UUID chat create
node <cli> --device PAIR_UUID chat rename --id CHAT_UUID --name "Investigate"
node <cli> --device PAIR_UUID chat read --id CHAT_UUID --out NEW_CHAT.json
node <cli> --device PAIR_UUID project export --out NEW_PROJECT.json
```

`project` and `chat` support `list`, `create`, `select`, `rename`, `delete`. Delete requires an explicit `--id UUID --confirm true`; the user must have authorized deletion of that target. Mutations are refused while an AI task is running. `chat read` reads only the selected chat, so explicitly select it first. `project export` exports the selected project's conversation data, not its entire workspace or account credentials. Use file/terminal commands for separately authorized workspace files. Exported user messages can themselves contain sensitive information. Project record deletion does not recursively erase workspace files. Do not delete a workspace just because its project record was deleted.

## Phone AI

```
node <cli> --device PAIR_UUID phone-ai status
node <cli> --device PAIR_UUID phone-ai send --project PROJECT_UUID --chat CHAT_UUID --text-file TASK.txt
node <cli> --device PAIR_UUID phone-ai stop --job JOB_UUID
node <cli> --device PAIR_UUID phone-ai continue --job JOB_UUID
node <cli> --device PAIR_UUID phone-ai answer --args-file ANSWER.json
```

Keep the returned job ID. `status` returns progress, latest reply and pending question, not private model reasoning. Sending requires explicit current project and chat IDs. Appending context to a running task also requires its current `job`. Messages never grant permissions. A normal answer uses `{job,question,chat,text}`; Android option answers also use `selections:["exact current option"]`. On iOS `phone-ai approve` takes `{job,question,chat,allow:true|false}` for a pending tool approval, and requires the user's explicit approval. Root questions use the exact offered option through `answer`, not a generic approval. Recheck IDs before responding. Do not automatically answer permission questions.

iOS supports pause and resume of an active paused task using `phone-ai pause|continue --job`. Android has stop and continue; it does not implement an in-place pause. Do not present stopping as an in-place pause. A completed iOS task cannot be resumed with the active-task command; send a new, scoped continuation message instead. Phone AI task submission currently requires the app UI to be responsive. Windows AI communication remains `ai status|send|read|stop` as described in SKILL.md; it is a separate agent and job channel.

## Attachments

```
node <cli> --device PAIR_UUID attachment upload --file LOCAL_FILE --project PROJECT_UUID --chat CHAT_UUID
node <cli> --device PAIR_UUID attachment list
node <cli> --device PAIR_UUID attachment clear
```

Upload uses encrypted chunks with explicit byte offsets, at most 8 MiB per file and four pending files. The selected project/chat must stay unchanged and no AI task may be running. Repeated or out-of-order offsets fail; there are no automatic chunk retries. Failed transfers request cleanup. Upload completion attaches the file to the next `phone-ai send`; it does not submit an AI task. `attachment add --args-file JSON` imports an existing absolute on-device `{path}` using the application's file access. It does not borrow Root to read inaccessible files. `clear` removes the pending selection; imported project files remain until separately deleted.

## Settings and voice

`settings get` exposes only supported non-secret settings. `settings set --args-file JSON` takes `{values:{...}}`; it does not support enabling Root, changing ADB tier, automatic operation approval or granting remote screen permissions. Changes are refused while an AI task runs.

iOS keys: `provider` (`openai` or `chatgpt`), `model.openai`, `model.chatgpt`, `reasoningEffort.openai`, `reasoningEffort.chatgpt`, `apiBase.openai`, `overlayEnabled`, `allowBackground`, `capsuleLocked`, `hapticStyle`, `voiceIdleTimeoutSeconds`, `edgeWidth`, `edgeOpacity`, `effectAI`, `effectRemoteInput`, `effectRemoteConnected`, `effectScreenEdge`. Width is 4–28 points, opacity .2–1, idle timeout 1–3600 seconds. Reasoning choices remain dependent on the provider/model.

Android keys: `provider` (0 API, 3 ChatGPT), `model`, `base`, `reasoningEffort`, `background`, `appearance` (`system|light|dark`), `capsuleLocked`, `hapticStyle`, `overlay`. Overlay must already have Android's permission. Custom API bases require HTTPS and cannot contain user info, query or fragment. Settings only cover values listed by this receiver; unsupported values are rejected.

`settings api-key --args-file PRIVATE_JSON` takes `{key:"..."}`. It writes the generic API key and returns only saved status. An empty key deletes it and requires `confirm:true` plus explicit user authorization. Never print the parameter file or include credentials in chat; do not read back keys or OAuth tokens. Interactive ChatGPT/Google/Apple login still requires the human's account authentication.

`voice status|start|stop|mute` controls the existing voice session. Mute takes `{microphone:true|false,speech:true|false}`. Starting the microphone requires explicit user intent and existing/system consent; a pending permission prompt is not successful recording. A start reply means requested, so check `voice status` for actual listening state. No speech recording is needed merely to test API connectivity.

## UI routes and recovery

For settings without a dedicated remote interface, `app ui.open --args-file JSON` opens `{page:"settings"}` or projects/voice. iOS also supports devices and diagnostics. Android supports remote and effects. Use screenshots and existing taps for further navigation; the user completes account/system authorization. Opening a page does not complete the action on it. The `voice` route can initiate the microphone session (Android starts voice directly); use it only for an explicitly requested voice task, not for read-only navigation.

`services status|restart|stop|start|result` exposes native service recovery. Commands may disconnect the current transport and do not replay interrupted tools. iOS returns a `request` UUID; use `services result --id UUID` to inspect completion when reachable. Android returns requested status and exposes its recovery snapshot. After stopping the listener, remote start/result cannot reach that phone; use the local app recovery switch. Do not silently switch to SSH after refusal. Keep any separately authorized local recovery explicit.

## Windows control-center settings

`desktop state` and `desktop guide` are read-only. `desktop name`, `background`, `enable`, `pair-code`, and `ai-connection` take the same JSON values as the control-center settings. Examples: `{name:"Work PC"}`, `{enabled:true}`, `{fixed:true,code:"123456"}`; these examples are notation, use valid quoted JSON in parameter files. AI connection accepts `enabled`, `base`, `model`, `effort`, `key`, `autoApprove`; only write credentials when explicitly requested and use a private parameter file, never print its contents. Responses do not include keys. The desktop `enable` switch controls the receiver, not the entire Windows server process.

`desktop trust`, `revoke`, `decision` require `--confirm true` and explicit user authorization. Arguments are `{device_id,mode}`, `{id}`, `{id,mode}` respectively. They do not automatically accept new devices. Use `desktop state` to inspect pending requests before deciding; use once/always/deny only as instructed. Do not silently grant permissions to resolve a failed command.
