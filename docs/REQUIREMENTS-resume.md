# 需求：从「清理会话」扩展到「找回并接续会话」

> 2026-11-10 整理。背景：用户在同一项目里因缓存失效反复新开 Claude 会话，名字重复或未命名，resume 时分不清哪条是当前进度。Amnesia 现在只解决「清理」，需要补上「找回 + 一键接上」。

## 配套约定（已在用户 shell 落地，Amnesia 应与之一致）

用户 `~/.zshrc` 里的 `cc` 函数：

| 命令 | 行为 |
|---|---|
| `cc` | cd 到 Git 根；今天该项目有名为 `<项目名小写>-<MMDD>` 开头的会话就 `claude -r <id>` 接上最新那条，否则 `claude -n <项目名小写>-<MMDD>` 新建 |
| `cc new` | 新建 `<项目名小写>-<MMDD>-<HHMM>` |
| `cc ls` | 列出该项目会话：最后修改时间 / customTitle / ID |

数据事实：
- Claude 会话：`~/.claude/projects/<路径中非字母数字替换为 ->/<sessionId>.jsonl`
- 名字：jsonl 中 `{"type":"custom-title","customTitle":"…","sessionId":"…"}`，取最后一条
- 「当前那条」= 该项目目录下 mtime 最新的会话（与 `cc` 的选择保持一致）

## 范围（Claude 侧；Codex 维持按日期，不改）

| # | 功能 | 验收标准 |
|---|---|---|
| R1 | 标出当前会话 | 每个项目分组里 mtime 最新的一条有醒目标记（如「当前」徽标），与 `cc` 会接上的那条一致 |
| R2 | 重名可区分 | 每行显示：名字（无名时用首条消息）+ 最后活动时间（精确到分钟）+ 最后一条用户消息摘要；同名会话肉眼可分 |
| R3 | 一键接上 | 点击/按钮在 Ghostty 新 tab 执行 `cd <项目根> && claude -r <sessionId>`；项目根从会话记录的 `cwd` 字段取，不从目录名反推 |
| R4 | 复制命令 | 右键可复制上面的 resume 命令（Ghostty 不可用时的退路） |
| R5 | 一键清旧 | 按项目「只保留最近 N 条」（N 默认 3，可改），复用现有删除逻辑与「使用中保护」；执行前列出将删除的会话确认 |
| R6 | 无名会话提示 | 未命名会话显示弱提示，可就地重命名（写入 custom-title 记录，格式与 Claude Code `/rename` 一致——实现前先核实 CLI 实际写法） |

## 不做

- Codex 分组方式不变（按日期）
- 不改 Claude Code / Codex 本身的存储格式
- 不做云端同步

## 待实现时核实

- `claude -r <id>` 需要在会话原 cwd 下执行才能找到；确认跨目录行为
- 重命名写 jsonl 是否会与正在运行的会话冲突（正在使用的会话应禁止重命名或走 CLI）
- Ghostty AppleScript 新建 tab 并输入命令的 API（参考 `.agent-handoff/PLAYBOOK.md` 的 osascript 用法）
