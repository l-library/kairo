# kairo 技能（skills）说明

kairo 使用与 pi 相同的技能格式：每个技能是一个目录
`~/.config/kairo/agent/skills/<技能名>/SKILL.md`，其中的指令会在
**Command 模式**下被加载进模型上下文（Chat 模式为纯对话，不加载技能）。

> 面板侧边栏「扩展 → 技能」可查看当前已加载的技能清单（只读）。
> 目前没有“官方”技能渠道（与 pi packages 的包管理机制不同），
> skills 生态为社区维护，安装前请评估来源可信度。

## 自带技能

| 技能 | 说明 |
|------|------|
| `kairo-skills` | 让 kairo 可以帮你安装/更新/列出/移除技能。安装 kairo 时自动同步（install.sh），daemon 启动时也会兜底补装 |

## 手动安装一个新技能

技能来源通常是 GitHub 仓库中的目录或 skills.sh 生态条目，安装分为两步：

### 1. 获取技能内容

任选一种方式（命令请在宿主终端执行，或直接让 kairo 帮你操作）：

```bash
# 方式一：skills.sh 生态（装到宿主全局后需复制到 kairo）
npx skills add <owner/repo@skill> -g -y
#   产物一般在 ~/.pi/agent/skills/<name>/（或提示输出的位置）

# 方式二：直接克隆仓库
git clone <repo-url> /tmp/skill-src
#   在仓库里找到技能的目录（含 SKILL.md）
```

### 2. 复制到 kairo 并在重启后生效

```bash
# <name> 替换为技能名；源目录必须是含 SKILL.md 的那一层
mkdir -p ~/.config/kairo/agent/skills
cp -r <源目录> ~/.config/kairo/agent/skills/<name>

# 重启 daemon 加载新技能
kairoctl restart

# 确认已加载（应能在“扩展 → 技能”列表看到，或直接问 kairo）
```

也可以把 SKILL.md 内容直接粘贴给 kairo（Command 模式），它会帮你写入目录。

## 移除技能

```bash
rm -rf ~/.config/kairo/agent/skills/<name>
kairoctl restart
```

## 安全提示

技能内容会进入模型上下文，等同执行不受信任的指令：

- 只安装可信来源（skills.sh 高安装量条目、官方/知名仓库、自己编写的内容）；
- 关注技能安装量（1K+ 起步，谨慎对待 <100 的）与来源仓库的星标/组织名；
- 若技能内容可疑，直接删除目录并重启 daemon。