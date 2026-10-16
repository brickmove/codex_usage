# 实施与验收记录

## 已完成基线交付

- 初始提交 feb80a231b778c4cc45e673cc6ec03bb28d6f534，标签 v0.3.3；origin fetch/push 使用 git@github.com:brickmove/codex_usage.git，main 跟踪 origin/main。
- 发布基础设施提交 12c0aa3，未修改基线标签和源码。正式 Release：https://github.com/brickmove/codex_usage/releases/tag/v0.3.3 。Actions：https://github.com/brickmove/codex_usage/actions/runs/38835036364 。
- 本机 93 项测试重新通过；公开安装包 1,705,876 bytes 与 sha256 附件 94 bytes 均可下载，SHA-256 / 包内版本 0.3.3 / arm64 / codesign 验证通过。CI 独立从基线标签测试并构建。

## 当前阶段

T2–T4 已完成，产品实现提交 7d98837 已推送 polish/0.4.0。106 项测试通过（96 Core +10 AppModel），两位独立最终审查者复算指纹并确认 P0/P1/P2 未关闭项为 0。指纹：ef6662c61006603030e39acebdc480858309d7d742d4eb3d19291fdf169a3491。

最终 Release 二进制导出 14 张原生预览；原生 QA 完成三页、Token/AX、分类草稿、取消/保存/排序/恢复默认撤销、日期错误跨分类可见和修正恢复检查。细节见 docs/verification.md。日志和截图保留 build/，不提交生成物。

本地安装包与构建产物逐项哈希一致，SHA-256 / arm64 / 0.4.0 build 7 / codesign 均通过。已安装到 /Applications/Codex Usage.app，并确认安装目录进程运行；安装版 CUA getApp 返回 timeoutReached，不能将隔离 QA 的完整 UI 验收冒称安装版实际窗口检查。用户生产偏好未改变。

文档本地链接 24 份通过，R1–R9 有任务映射；shell/plist/Workflow YAML 及 run 段语法通过，未宣称运行缺失的归档 helper/validator。T5 已完成 GitHub 发布与公开双附件下载核验，详见下文。

## 最终公开发布核验

- v0.4.0 正式 Release：https://github.com/brickmove/codex_usage/releases/tag/v0.4.0 ，已标为 Latest；独立标签指向 3f00276caa900611d679a3845547efa48546c271。基线 v0.3.3 仍指向 feb80a231b778c4cc45e673cc6ec03bb28d6f534。
- 构建发布任务：https://github.com/brickmove/codex_usage/actions/runs/38837353060 。公开双附件在流程测试、打包与校验后发布，安装包 1,759,951 bytes，校验文件 94 bytes。
- 已实际下载公开安装包与校验文件，SHA-256 为 a7a3a4f482a356615f1e4350624a16507ed025cbb65c62972f36d05f1f3a3e0b；解包确认 0.4.0 / build 7 / arm64，codesign 严格校验通过。两版附件均可公开下载。
- T1–T5 全部完成；R1–R9 均有对应自动化、原生交互/预览、独立审查或发布证据。28 项适用技能逐项执行，15 项不适用明确记录；无未完成的本轮实施项。平台与真实硬件验证边界保持上述说明。
- 产品提交 7d98837、交付文档提交 3f00276 已按组推送并快进 main；本次补录只修改交付证据，不重建或覆盖既有标签/附件。
