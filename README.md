# DYLANFREE.github.io

统一的公开网站发布仓库。

## 目录

- `luxreport/`：硅基智能体报告
- `AI-Luxreport/`：AI 非理性繁荣深度研究
- `AI-Luxreport/waiting-for-overreaction/`：等，不是猜
- `sites.json`：网站、发布路径和公网地址清单
- `scripts/sync_sites.rb`：本地统一同步与发布前检查

## 本地更新

在本仓库运行：

复制当前已经确认的线上版本：

```bash
ruby scripts/sync_sites.rb
```

明确需要从权威源刷新正文时：

```bash
ruby scripts/sync_sites.rb --refresh
```

`--refresh` 会执行本仓库内三个独立同步工具，直接从权威源重建对应发布目录。研究源文件、私密备份和本地 QA 记录不会进入公开仓库。刷新可能带来正文变化，必须先审阅差异再发布。

发布前必须检查：

```bash
git status --short
git diff --stat
git diff --check
```

提交推送后，逐一验证 `sites.json` 中的公网地址。
