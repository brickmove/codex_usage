# 外部事实核验（web-search）

检索日期：2026-10-16。以下只使用官方一手资料。

| 结论 | 类型 / 状态 | 来源与适用边界 |
| --- | --- | --- |
| macos-15 标准 GitHub 托管 runner 当前为 arm64 | 事实，已确认 | https://docs.github.com/en/actions/reference/runners/github-hosted-runners ；workflow 仍以 uname 实际检查，避免标签迁移造成错架构 |
| GitHub Release 可由 gh release create 从既有 tag 创建，附版本说明及产物 | 事实，已确认 | https://cli.github.com/manual/gh_release_create ；采用 draft→附件→公开，不混用推送标签与正式发布 |
| Apple 提供原生 Settings / Popovers 设计指导 | 事实，已确认 | https://developer.apple.com/design/human-interface-guidelines/settings 与 https://developer.apple.com/design/human-interface-guidelines/popovers |
| 本产品设置分类、固定头尾并正文滚动适合短暂查看 | 本项目设计判断 | 来自源代码与审查，不冒称 Apple 逐项认证；仍需原生验证 |

CC Switch 四类 Token 与费用的事实已由 docs/data-sources.md 的固定源码和既有测试覆盖，本轮不变更该契约。公开发布验证结果见最终 summary.md。
