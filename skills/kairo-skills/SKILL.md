---
name: kairo-skills
description: 帮助用户在 kairo 中安装、更新、列出或移除技能（skills）。当用户提到“安装技能”“添加 skill”“装个技能”等时使用。
---

# kairo 技能管理

kairo 使用与 pi 相同的技能格式：每个技能是一个目录
`~/.config/kairo/agent/skills/<技能名>/SKILL.md`，目录下的内容会被
加载进上下文（Command 模式下生效）。

## 技能的位置与生效

- 技能目录：`~/.config/kairo/agent/skills/<name>/`
- 安装新技能后需要**重启 kairo daemon**（让用户运行 `kairoctl restart`）
  才能被加载；已加载技能在每次会话开始时可用。

## 安装技能（所有命令会先弹确认卡，等用户批准）

1. 询问用户要安装的技能名称或来源（GitHub 仓库 / skills.sh 条目等）。
2. 优先引导用户使用官方生态 CLI：`npx skills add <owner/repo@skill>`，
   装到宿主全局后把生成的 `<name>/` 目录复制到
   `~/.config/kairo/agent/skills/`。若输出的目录结构与技能格式不同，
   对照上面“技能的位置与格式”把 SKILL.md 及其附属文件放好。
3. 也可以直接 `git clone` 仓库后找到技能目录复制过去，或请用户粘贴
   SKILL.md 内容，由你写入 `~/.config/kairo/agent/skills/<name>/SKILL.md`。
4. 装好后：
   - 检查 `ls ~/.config/kairo/agent/skills/` 确认目录存在；
   - 请用户运行 `kairoctl restart`（或手动 `systemctl --user restart kairo-daemon`）；
   - 重启后可在面板侧边栏「扩展」标签的“技能”列表看到新技能。

## 移除技能

删除 `~/.config/kairo/agent/skills/<name>/` 目录，然后同样重启 daemon。

## 安全提示

技能内容会进入模型上下文，等同于执行不受信任的指令：
- 只安装可信来源（skills.sh 高安装量条目、官方/知名仓库、用户自持内容）；
- 安装命令走确认门，用户批准前不要执行任何写操作或命令；
- 发现技能内容可疑时提醒用户不要安装。