# AsterHand 局域网控制协议 v1

[English](CONTROL_PROTOCOL.md) · [简体中文](CONTROL_PROTOCOL.zh-CN.md)

当前实现为 iOS、Android 与现代 Windows；实际系统版本覆盖见 TESTING.md。默认监听 TCP 18769，未开启被控时只响应无凭据的 `/info` 元数据，拒绝执行请求。桌面浏览器控制台仅监听 127.0.0.1:18767，使用随机会话路径、Host/Origin 校验和 CSP。不得将本机浏览器控制台作为无认证公网服务转发。

## 配对与权限

当前配对 v2 使用持久 P-256 身份，设备标识为未压缩公钥的 SHA-256。`/info` 仅返回公开元数据；`/pair` 交换加密申请和决定，ECDH 派生每次申请的通道密钥及双方核对码。接收端允许一次、始终允许或拒绝，授权按设备公钥标识保存。IP 仅用于发现和路由，改地址不改变身份。

申请 120 秒有效；一次会话异常断线最多保留 600 秒，认证活动续期，`session.close` 明确回收一次授权；始终允许可独立撤销。配对码可轮换或固定，仅用于发现，不是执行授权。保留旧版邀请导入用于迁移，邀请本身包含控制凭据，禁止进入发布包。

API Key / ChatGPT 登录令牌不参与配对，不通过此协议同步。共享密钥只授权控制操作；不提供读取应用 Keychain 的接口。iOS Root 与屏幕控制由被控机本地设置决定；Windows 以当前桌面用户权限运行，不能操控锁屏、安全桌面或更高完整性级别的窗口。

Android 的接收端使用本机选择的普通用户、ADB 或 Root 等级，并独立检查远程屏幕开关。执行结果给出实际 UID；未激活 ADB 或未授权 Root 时失败，不自动提权。普通用户屏幕接口依赖用户启用的无障碍服务及 Android 版本。Android 专用 ADB 激活通道只在本机回环监听，使用独立 HMAC 认证，不属于局域网配对凭据，也不提供给远程控制端。

## 命令消息

`POST /rpc` 接收 JSON 信封 `{v, pair, iv, data, mac}`。明文载荷为 `{id, ts, method, args}`，响应为 `{id, ts, result}`。

- 共享密钥以 HMAC-SHA256、标签 `AgentGo/v1/encryption/<direction>` 和 `AgentGo/v1/authentication/<direction>` 派生独立密钥。方向为 `req` 或 `res`。
- AES-256-CBC / PKCS#7，每条消息使用新的 128 位随机 IV。
- 先校验 HMAC-SHA256 再解密；MAC 输入为 UTF-8 的 `v1\n<direction>\n<pair>\n<iv-base64>\n<data-base64>`，比较固定长度 MAC。
- 请求时间与接收机相差最多 90 秒；请求 UUID 在 180 秒内拒绝重用。客户端校验响应 UUID 和配对通道。时钟应保持准确。
- 请求/单帧上限 2 MiB；普通文件读写另有较小上限。嵌套远端转发不允许；执行端只接受显式工具白名单。

控制方法：`hello`、`info`、`presence`、`session.close`、`execute`、`terminal.open/read/write/interrupt/close`。`execute` 的工具为文件读写/目录、run_shell、screen_capture/tap/swipe/type/home。返回工具错误必须按失败呈现。审批在发起端 AI 层进行；手动控制和已配对的入站请求按被控权限直接执行。

## 兼容交互远控

电脑控制 iPhone 时优先使用原 VNC / TLS / WebSocket 通道，同时在统一控制中心显示。已配对请求 `vnc.info` 可获取绑定配对的短期 VNC 认证信息和公开证书；接口受本机屏幕权限和设备配对约束，不返回服务器私钥或 AI 凭据。桌面代理验证 CA、主机名及证书 SHA-256，浏览器连接仍受本机随机路径和 Origin 约束。对旧版手机仅在已有本机 VNC 配对配置完整时使用该兼容路径。

VNC 帧、连续指针和键盘事件直接双向转发，避免将整次拖动延迟到松手后执行。授权撤销和权限关闭会终止控制中心连接。全屏与比例仅改变本机显示，不修改目标设备的分辨率。

## 后备实时屏幕

加密的 `stream2` 请求建立持续 HTTP 响应。每个记录为 4 字节大端长度与加密帧。帧密钥方向标签为 `stream/<本次请求 UUID>`，使帧绑定到本次连接。

帧记录为 `IV(16) | AES-CBC ciphertext | HMAC(32)`。MAC 覆盖 IV 和密文，使用独立派生的认证密钥。解密后为四个大端 uint32：递增传输序号、宽、高、采集序号，然后为 JPEG 字节。客户端拒绝无效 MAC 和非递增序号。JPEG 本身也携带尺寸；Windows 当前帧头尺寸可为 0。

iOS 的持续采集以 30 FPS 为目标，只有观看时运行；缩放使用 vImage。RPC 代理检查权限与配对撤销，最多约 0.5 秒停止。屏幕帧不会加入持久化聊天记录。桌面 WebSocket 代理和客户端丢弃积压帧，避免旧画面排队。停止观看后约 3 秒释放手机采集资源。

Android 接收端实现相同 `stream2` 加密帧格式，但当前采集是无障碍截图或 ADB / Root `screencap`，没有硬件视频编码。Android 手机控制页目前串行获取单帧，避免请求排队；不以协议兼容或截图成功宣称达到 iOS VNC 的流畅度。

## 终端与停止

终端标识为随机 UUID，绑定发起配对，其他配对不可读取/输入该会话。每个进程最多 8 个会话，缓冲最多 256 KiB，闲置 20 分钟回收。iOS 使用经过验证的非交互 shell 持续命令会话；Windows 使用 PowerShell 持续命令会话。中断会终止会话的进程组/进程树，用户可重新打开。暂不包含完整 PTY/VT 屏幕仿真。

撤销授权会清理对应终端；关闭 Root 会终止 Root 终端。取消命令会尽力终止所创建的进程组/进程树，不能撤销已完成的文件或系统改动。远控协议不提供“忽略目标权限”的选项。

## 检查

- `node scripts/check_control.mjs`：隔离目录内的双向配对、身份认证、重放/篡改、视频连接绑定、终端隔离、模拟 AI 工具循环和撤销。
- `node scripts/check_phone_control.mjs <已配对手机IP>`：只读标记命令、变量保留/中断/重开/关闭和远端取消；会临时开启测试终端。
- `node scripts/check_stream.mjs <已配对手机IP或local>`：接收 180 帧计时，只记录统计数据，不保存屏幕内容。

这些是实现检查和指定设备验证，不是独立安全审计。发布旧平台支持前仍需分别验证网络、加密、运行时、采集和输入实现。
