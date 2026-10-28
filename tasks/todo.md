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
- [x] 用 writing-plans 技能编写第一期实现计划（2026-10-25，`docs/superpowers/plans/2026-10-25-practice-toolbox.md`，18 个任务）
- [x] 实现第一期（**已完成**，单分支 `master`，GitHub 已推送至 `42531d8`）：✅Task1 脚手架 ✅Task1.5 音频栈替换 ✅Task2-5 乐理/音频/数据核心（全部 TDD 双审）✅Task5.5 界面品味升级（achromatic-ledger 设计语言）✅Task6-16 数据层/备份/YIN/麦克风管线/声音合成/节拍器引擎/调音器页/和弦库/指板音阶/节拍器页/打卡计时/深色模式/Switch 统一/个人中心（累计 50+ 提交，含十余轮用户现场迭代与全部审查修复）——设计账本见 `docs/design-ledger.md`
- [ ] **用户硬件实测**（电脑在公司，拿回后走 `tasks/acceptance.md` 清单）：真吉他全弦调音实测、和弦听感、节拍器 5 分钟长跑、打卡全流程、导出导入一致性
- [ ] 麦克风调试战役遗留确认：offsetInBytes 真凶修复（fc40c78）+ 48k 优先（117cc0f）+ 音频增强关闭——三项叠加后真吉他也无声音的话，深挖 SST 驱动层（战役记录见 `docs/design-ledger.md`）

## Review（2026-10-25 本次会话）

1. **markitdown MCP 修复（已完成）**：根因 = 全局 mcp SDK 已升级 2.3.0，而清华镜像上的 markitdown-mcp 0.0.1a4 只兼容 mcp 1.x（启动即崩 → CONNECTION_CLOSED）。方案：独立 venv `C:\Users\plafa\.claude\mcp-venvs\markitdown`（官方 PyPI 安装；pip 解析后落定 0.0.1a4 + mcp 1.8.1，因 azure 依赖与 mcp 2.x 冲突回退；另需钉 `pydantic==2.11.7` 修复 mcp 1.8 依赖的内部 API 在 pydantic 2.12+ 被移除的问题），`~/.claude.json` 已指向 venv 内 exe，`--help` 验证通过，JSON 校验通过。改配置前备份：`~/.claude.json.bak-markitdown-fix`。
2. **会话迁移**：从 a3726e7a 会话记录恢复完整设计文档并落盘（该会话因无文件工具，文档只存在于对话中）。
3. **遗留小事项**：markitdown 需重启会话 / `/mcp` 重连后生效（本会话内仍显示连接失败属正常）。
4. **2026-10-25 设计变更（用户提出）**：调弦预设增加分组展示——「标准/降调、Drop、Open、特殊、自定义」五组（Drop 系独立成组），已同步设计文档第 4/5.1/9/10 节。
5. **2026-10-25 补充**：新增设计文档 3.1 节「iPad 交付路径」——Windows 打样代码可直接编译 iOS，但打包需 macOS + Xcode（本地 Mac / 云 Mac CI + TestFlight ¥688 年 / 自签侧载三条路线）。
6. **2026-10-25 竞品调研（恩雅音乐等）**：二期明确「跟练三件套」——多音轨播放、速度调节、选段循环（AB Loop），已写入设计文档第 2 节路线表。一期候选增强（A4 参考音高校准 / 节拍器细分拍+Tap Tempo / 练琴屏幕常亮 / 和弦琶音扫弦试听）用户尚未确认，暂不写入。
7. **2026-10-25 设计变更（A 档全收）**：一期新增四项——A4 参考音高校准、节拍器细分拍+Tap Tempo、练琴屏幕常亮、和弦琶音/扫弦试听（已同步 5.1/5.2/5.4/第 4 节与验收标准 10–13）。B 档确认一项：练习录音回放写入二期。升降调/移调已解释（自研引擎下成本极低，推荐写入二期），待用户确认。
8. **2026-10-25 设计变更**：升降调/移调写入二期（用户确认；自用指弹为主、弹唱少，优先级低但保留）。设计文档收敛，进入实现计划编写（writing-plans 技能）。
9. **2026-10-25 实现计划已编写**：`docs/superpowers/plans/2026-10-25-practice-toolbox.md`（18 个任务：脚手架 → 乐理核心 → 音频引擎 → 数据层 → 四个页面 → 接线 → 打卡 → 验收走查，全程 TDD 小步提交）。**下次会话**：先对计划做快速自查（占位符/类型一致性/规格覆盖），再与用户确认执行方式（子代理驱动 / 会话内执行）后开工。
10. **2026-10-26 实现环境要点（记录给未来会话/CI）**：① `flutter_soloud` 5.2.1 首次原生构建需从 GitHub 拉 Xiph 预编译库，本机直连超时——已用 gh-proxy.com 镜像手动补到 pub cache 的 `flutter_soloud-5.2.1/.dart_tool/flutter_soloud/xiph/prebuild/{include,windows/x64}`（机器级修复，换机/清缓存会复现）；② Windows 开发者模式未开启 → 构建符号链接失败（等用户在 `ms-settings:developers` 开启，Task 9 起必需）；③ 质量审查遗留：Note 值语义（==/hashCode/toString）与 3 个测试断言并入 Task 3 提交；`centsOff` 对 measured<=0 抛异常（上游 detectPitch 保证 null 或正数，实际不可达，作为契约记录）；④ 音频栈已换 record 7.1.2 + flutter_soloud 5.2.1（原 mic_stream/flutter_pcm_sound 不支持 Windows），计划 Task 9-15 已按真实 API 重写（ae884af）。
