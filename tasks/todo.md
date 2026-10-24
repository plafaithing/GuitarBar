# GuitarBar 任务跟踪

> 来源：会话 a3726e7a（2026-10-23 brainstorming，工具受限无法落盘）内容迁移，2026-10-25 由本会话继续执行。

## 已完成

- [x] 第一期「练琴工具箱」需求 brainstorming，设计逐节确认（原会话完成，用户答复"没了，写吧 / 保存吧"）
- [x] 恢复设计文档全文并落盘 `docs/superpowers/specs/2026-10-23-practice-toolbox-design.md`
- [x] git init + 初始提交
- [x] 修复 claude 命令启动器（原会话诊断：npm 临时文件卡住，改名即修复；已验证 `claude --version` → 2.1.310）
- [x] 修复 markitdown MCP（详见本文末尾 review）

## 待办

- [ ] 用户审阅设计文档，确认无误
- [ ] 用 writing-plans 技能编写第一期实现计划
- [ ] 实现第一期：脚手架 → 音频引擎 → 调音器 → 工具箱三功能 → 个人中心打卡

## Review（2026-10-25 本次会话）

1. **markitdown MCP 修复**：根因 = 全局 mcp SDK 已升级 2.3.0，而 pip 清华镜像上的 markitdown-mcp 0.0.1a4 只兼容 mcp 1.x（启动即崩 → CONNECTION_CLOSED）。官方 PyPI 已有 markitdown-mcp 0.0.1a8（兼容 mcp 2.x），镜像同步滞后。方案：独立 venv `C:\Users\plafa\.claude\mcp-venvs\markitdown` 安装 0.0.1a8，`~/.claude.json` 中 command 指向 venv 内可执行文件，不动全局环境。
2. **会话迁移**：从 a3726e7a 会话记录恢复完整设计文档并落盘（该会话因无文件工具，文档只存在于对话中）。
3. **遗留小事项**：markitdown 配置需重启会话 / `/mcp` 后生效；venv 安装若未完成见后台任务输出。
4. **2026-10-25 设计变更（用户提出）**：调弦预设增加分组展示——「标准/降调、Open、特殊、自定义」四组，已同步设计文档第 4/5.1/9/10 节。
5. **2026-10-25 补充**：新增设计文档 3.1 节「iPad 交付路径」——Windows 打样代码可直接编译 iOS，但打包需 macOS + Xcode（本地 Mac / 云 Mac CI + TestFlight ¥688 年 / 自签侧载三条路线）。
