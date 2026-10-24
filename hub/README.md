# Pocket Agent Hub × AgentBox

Git Bash 原生的多 agent TUI 启动器。

外壳与入口约定来自 PocketAgentHub，菜单 UI 来自 AgentBox 项目
（YZZ 字标 + 半块 logo + 状态探测）。**底层从 Linux/WSL 改成 Git Bash** ——
不需要 WSL、QEMU、虚拟机或管理员权限。

```
┌──────────────────────────────────────────────────────┐
│  █   █ █████ █████                                   │
│  █   █    █     █                                    │
│   █ █    █     █                                     │
│    █    █     █                                      │
│    █   █████ █████                                   │
│  o p e n - a g e n t            Git Bash · Windows   │
│  ──────────────────────────────────────────────────  │
│   ❯ ✓ OpenCode       开源 · 可自配模型          就绪  │
│     ✓ DSH            DeepSeek Harness 网页端    就绪  │
│     ✗ Oh My Pi       OMP 编码代理              未安装 │
│     ✗ Claude Code    Anthropic 终端代理        未安装 │
│     ✗ Codex CLI      OpenAI 代码代理           未安装 │
│     · Bash           纯终端 · 不启动 agent         —  │
│  ──────────────────────────────────────────────────  │
│    ↑↓ 选择   Enter 进入   s 设置   q 退出             │
└──────────────────────────────────────────────────────┘
```

## 用法

```bash
# 方式一:在项目目录里启动(Git Bash 或 Windows Terminal)
cd /d/Workspace/我的项目
bash "<这个文件夹>/launch.sh"

# 方式二:双击 start.cmd
```

**在被启动 agent 之前先 `cd` 到你的项目目录** —— 启动器不做任何目录切换，
选中的 agent 会继承你当前所在目录。

建议在 **Windows Terminal** 里用 Git Bash profile 跑，而不是默认的 mintty：
mintty 对原生 EXE 的交互式 PTY 支持有限，全屏 TUI 程序可能出问题。

## 移动便携（放 U 盘里带走）

**这是这个项目的初衷**：整个文件夹拷到 U 盘 / 移动硬盘，插到任何一台 Windows
上双击 `start.cmd` 就能用，不装任何东西、不改注册表、不留垃圾。

### 怎么做到的

1. **脚本里没有任何写死的绝对路径。**
   `launch.sh` 用 `HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"` 推导
   自己的位置，所以换盘符（E: → F:）、换目录深度、路径里带中文空格都不影响。
   清单里的命令可以用 `$AGENTBOX_HUB` 引用项目根目录（`launch.sh` 会导出它），
   这样就不会出现「插到别的电脑就废」的绝对路径。

2. **Git Bash 是现场找的，不是写死的。**
   `start.cmd` 按这个顺序找：
   ```
   1. 同目录 PortableGit\bin\bash.exe   ← 免安装,U 盘首选
   2. %ProgramFiles%\Git\bin\bash.exe
   3. %ProgramFiles(x86)%\Git\bin\bash.exe
   4. %LOCALAPPDATA%\Programs\Git\bin\bash.exe
   5. PATH 里的 bash.exe
   6. 注册表 HKLM\SOFTWARE\GitForWindows 的 InstallPath
   ```
   找不到会明确提示两种解决办法，不会闪一下就退。

3. **机器相关的软件不写死路径。**
   DSH 装在哪台机器上都不一定，所以清单里只写
   `!bash "$AGENTBOX_HUB/bin/dsh.sh"`，
   由 `bin/dsh.sh` 在运行时按顺序找：
   `$DSH_BIN` → `bin/dsh.path` → PATH 上的 `dsh` → 常见安装位置 → 项目内 `dsh/`。
   找不到会给出「把路径写进 bin/dsh.path」的明确指引，不会崩。

### 完全免安装的做法（连 Git 都不用装）

1. 下载 [PortableGit](https://github.com/git-for-windows/git/releases)
   的「Portable」版（自解压 exe）。
2. 解压到本文件夹下，目录名必须是 `PortableGit`，结果形如：
   ```
   PocketAgentHub\
   ├── start.cmd
   ├── PortableGit\bin\bash.exe     ← 放这里
   ├── launch.sh
   └── tui\...
   ```
3. 拷到 U 盘，插上任何 Windows 双击 `start.cmd` 即可。

### 哪些东西带不走

可移植的是**启动器和它的配置**，不是 agent 本身：

| 项目 | 能不能跟着 U 盘 |
|---|---|
| 启动器、菜单、YZZ 字标、agent 清单 | ✅ 全部在文件夹里 |
| Git Bash | ✅ 用 PortableGit 就能带 |
| 各个 agent（Claude Code / Codex / Gemini…） | ❌ 必须在那台机器上装 |
| agent 的登录凭据 | ❌ 存在各自主机目录（`~/.claude` 等） |

所以到了新机器，菜单会诚实地告诉你**这台机器上哪些能用**（`✓ 就绪`）、
哪些要装（`✗ 未安装`）—— 这本来就是状态探测存在的意义。

> 也正因为凭据在主机上，**不要把登录 token 拷到 U 盘里**。

## 文件结构

```
PocketAgentHub/
├── start.cmd              Windows 双击入口(多路查找 Git Bash → 调 launch.sh)
├── launch.sh              分发器:调 TUI 拿选择结果 → 读清单 → 执行
├── tui/
│   ├── agentbox-tui.sh    纯 UI。只往 fd 3 打一个 id,不执行任何 agent
│   ├── check-agents.sh    状态探测。输出 8 列 TSV(第 8 列是状态)
│   ├── agents.tsv         agent 清单。改这里 = 改菜单
│   └── logo/              YZZ 块字 + 大号 Y 半块立绘(各尺寸)
├── bin/
│   ├── dsh.sh             DSH 定位器(运行时找 DSH 装在哪,不写死路径)
│   └── dsh.path.example   自动找不到时,照着它写一份 bin/dsh.path
└── PortableGit/           (可选)放 PortableGit 实现完全免安装
```

## 改菜单

只改 `tui/agents.tsv`，不动任何脚本。每行 7 个字段、6 个制表符：

| # | 字段 | 说明 |
|---|---|---|
| 1 | `id` | 稳定标识,UI 把它打到 stdout 作为选择结果 |
| 2 | `name` | 菜单显示名(显示宽度建议 ≤ 14 列) |
| 3 | `desc` | 右侧说明(显示宽度建议 ≤ 26 列) |
| 4 | `cmd` | 执行命令。默认按空格安全切分后 exec;以 `!` 开头 = 交给 shell |
| 5 | `check_cmd` | 探测安装状态。**可写多个候选命令名**(空格或逗号分隔),任一存在即算装上 |
| 6 | `key_env` | 需要的环境变量(逗号分隔) |
| 7 | `key_file` | 替代凭据文件(存在且非空即视为已配置) |

**空字段写 `-`，不要真的留空。** 原因见下。

`check_cmd` 要支持多候选，是因为同一个 agent 在不同发行渠道下命令名不一样，
实测撞到三例：`omp` / `oh-my-pi`、`cbc` / `codebuddy`、`kilo` / `kilocode`。
只认一个名字会漏判成「未安装」。

状态规则：

| 符号 | 状态 | 含义 |
|---|---|---|
| `✓` | 就绪 | 命令存在，且环境变量或凭据文件已配置 |
| `●` | 已安装 | 命令存在，但清单里没声明可查的凭据 —— **不代表登录过** |
| `⚠` | 缺 Key | 命令存在，声明了凭据但都没配 |
| `─` | 无需检查 | `check_cmd` 为 `-`（如 Bash） |
| `✗` | 未安装 | 候选命令一个都找不到 |

`●` 和 `✓` 刻意分开：大部分 agent 装完还要跑一次登录才真能用，
把「命令存在」标成「就绪」是撒谎。

## 支持的 agent（8 个 + Bash）

命令名来自 **npm registry 的 `bin` 字段实测**（2026-10-18），不是凭记忆写的：

| agent | 命令 | 来源 | 说明 |
|---|---|---|---|
| OpenCode | `opencode` | `opencode-ai` | 开源里最活跃的终端 agent |
| DSH | `node …/dsh/lib/bin.js --profile web` | 本机安装 | DeepSeek Harness |
| Claude Code | `claude` | `@anthropic-ai/claude-code` | 目前使用面最广 |
| Codex CLI | `codex` | `@openai/codex` | OpenAI 官方 |
| Gemini CLI | `gemini` | `@google/gemini-cli` | Google 官方 |
| Qwen Code | `qwen` | `@qwen-code/qwen-code` | 通义千问，国内主流 |
| Copilot CLI | `copilot` | `@github/copilot` | GitHub 官方 |
| Aider | `aider` | `aider-chat`（PyPI） | 老牌开源，git 集成好 |
| Bash | `bash -l` | 系统自带 | 纯终端兜底 |

菜单**按状态排序**（就绪 → 已安装 → 无需检查 → 未安装），装好的排最前面。
9 项在 30 行终端里一屏放得下，不需要滚动；更多时自动滚动，页脚显示 `当前/总数`。

### 为什么只有 8 个

这份清单刻意只收**当前最主流、实际有人天天用**的终端 agent。

之前试过扩到 19 个，把 Crush、Amp、Auggie、Goose、Cline、Kilo、Grok CLI、
Oh My Pi、iFlow、CodeBuddy 都列了进来。问题是：

- 它们要么确实小众（Auggie、Grok CLI、Oh My Pi）；
- 要么主要形态不是独立终端 CLI —— Cline 和 Kilo Code 是 VS Code 扩展，
  CodeBuddy 是腾讯云的 IDE 助手，命令行形态用的人很少；
- 结果菜单变成一大片红色的「✗ 未安装」，把真正能用的挤到上面去翻，反而不好用。

想加回来任何一个：照格式在 `tui/agents.tsv` 加一行即可，不用改任何脚本。
**命令名务必查实际来源**（npm registry 的 `bin` 字段或官方文档），
写错了只会一直显示「未安装」。

## 移植过程中修掉的 15 个问题

这些不是猜测，都是实测抓到的。记在这里避免以后重犯。

### 1. bash 的 `read` 会折叠连续 tab，空字段消失

契约要求"空字段留空但不能少 tab"，但实测：

```bash
printf 'a\tb\t\tc' | { IFS=$'\t' read f1 f2 f3 f4; }   # → f3=c, f4=空
```

tab 属于 IFS 空白，连续 tab 被折叠，**后面的字段整体左移**。原 AgentBox 的
`check-agents.sh` 因此把 DSH 的凭据路径读进了 `key_env`，触发
`${!v:-}` 的 "invalid variable name"。

修法：清单里用 `-` 占位，脚本里 `unplaceholder()` 归一化成空串。
（`awk -F'\t'` 不会折叠，但清单同时被 bash 和 awk 读，统一用占位最稳。）

### 2. `$(...)` 吞掉了整个菜单画面

`launch.sh` 用 `choice="$(bash "$TUI")"` 捕获 stdout，而 TUI 原本把菜单也画到
stdout —— 画面全被变量吃掉，终端只剩空白。

修法：TUI 里 `exec 3>&1; exec 1>&2`，UI 走 stderr，**只有 id 走 fd 3**。
`--list` 仍写 stdout（那是给人/管道看的，不是 UI）。

### 3. 颜色检测看错了 fd，导致整片白框

```bash
if [[ -t 1 ]] && ...   # ← 检查 stdout
else C_SEL=$'\e[7m'; C_RST=''   # 反显 + 空复位
```

stdout 是管道时 `-t 1` 为假 → 走降级分支 → `C_SEL` 变反显、**`C_RST` 是空串
永不复位** → 反显泄漏到后面所有行，整片刷白。

修法：检测改看 `[[ -t 2 ]]`（UI 实际写到 stderr）；并且 `C_RST` 放在分支
**外面**永远有效，作为安全网。

### 4. 中文宽度：`printf '%-26s'` 按字符数补，不按显示列

中文占 2 列，所以含中文的描述列会撑成两倍宽，把右侧状态顶飞。

修法：写 `disp_w()`（`wc -L`）、`pad_to()`、`trunc_to()`，全部按显示列宽
计算；不变的字符串（名字/描述）在 `load_agents` 时预算好，绘制时零 `wc` 调用。

### 5. 每次按键整屏 `clear`

`draw_menu` 开头 `clear` → 按方向键就满屏重绘 + 闪烁。

修法：把单行绘制抽成 `draw_row`，布局参数（`LEFT_PAD`/`CW`/`AGENT_TOP`）
存全局；主循环只在选择变化时用光标定位重绘**两行**。
只有窗口尺寸变化才整屏重绘。

### 6. 交互延迟：每次按键 fork 几十个子进程

这一条最隐蔽，也最影响手感。实测本机 Git Bash 的进程创建成本：

```
$(printf 'abc' | wc -L)   ≈ 49 ms   ← 算显示宽度用的
$(echo hi)                ≈ 14 ms   ← 连空子 shell 都这么贵
```

原实现 `draw_row` 每行要跑 10–14 次 `$(...)`（4 个 `mark/label/color`
函数 + 4–6 次 `wc`），一次按键重绘 2 行 = **约 576 ms**，按一下肉眼可见地顿。

修法：**把所有可能变的东西在启动时算成字符串**。

- `compute_layout()` 只算数字（`LEFT_PAD`/`CW`/`AGENT_TOP`）
- `build_frame()` 预生成 `HDR`/`RULE_LINE`/`FOOT` 和每行的
  `ROW_SEL[i]`（选中版）/ `ROW_OFF[i]`（普通版）
- 按键路径上只剩 `printf`（bash 内建）和 ANSI 光标定位，**零 fork**
- 窗口缩放改用 `trap ... WINCH` 通知，不再每次按键都 `tput cols`

结果：单次按键 **576 ms → 0.28 ms**（约 2000×），整屏重绘 22 ms（只在缩放时）。

### 7. 品牌色是紫色 #af5fff（256 色 135）

`C_BRAND=$'\e[38;5;135m'`。之前用的是 Hermes 蓝 20，改成紫色。

### 8. 块字字标各行宽度不同，逐行居中会把字标拆散

给字标加边框后，字标变成「逐行居中对齐」。但 `yzz-banner.txt` 里各行
**显示宽度并不相等**：

```
█   █ █████ █████   ← 17
█   █    █     █    ← 16
 █ █    █     █     ← 15
  █    █     █      ← 14
  █   █████ █████   ← 17
```

因为 Y 的两臂向下收拢、Z 的斜笔也收窄，而**行尾空格在保存时被剥掉了**。
逐行拿自己的宽度算左移量 → 每行被推不同距离 → Y 的左上臂和其余笔画错位，
两个字 Z 变形（实测现象：看起来像「yZZ」而且还缺笔画）。

修法：`pick_banner()` 加载时用显示宽度把所有行右补到统一宽度（17）。
不能指望素材文件本身对齐——编辑器、Git、各种工具都会剥行尾空格。

### 9. 加边框后每行的宽度公式要重新推

加边框后 `ROW_W = CW - 4`，行结构变成 `│` + 空格 + 内容 + 空格 + `│`。
第一版漏了两处，症状都是「某几行比别的行短」：

- agent 行数组里忘了结尾的 `$'\n'` → 6 行被挤成 1 行（实测那一行宽 770）
- 页脚用 `fpad = ROW_W - fw - 1` → 比框架少 1 列，应为 `fpad = CW - 3 - fw`

排查靠的是「逐行 `wc -L` 必须全部等于 `CW + LEFT_PAD`」这条硬指标。

### 10. 增量重绘把左边距加了两次，行被推到框外

加边框后 `ROW_SEL[i]` / `ROW_OFF[i]` 存的是**从第 0 列开始的完整一行**
（开头就带 `$PAD`）。但 `redraw_row` 里还写成了：

```bash
printf '\033[%d;%dH%s' $((AGENT_TOP+i+1)) $((LEFT_PAD+1)) "$txt"
#                                          ^^^^^^^^^^^^^ 多余
```

于是左边距被应用两次：整行右移 `LEFT_PAD` 个字符，右边框跑到框架外面。

**症状很有欺骗性**：首次整屏绘制完全正常，只有按过方向键的那些行才歪，
而且每按一次只歪两行——用方向键上下走一遍，六行就全歪了。
用户看到的就是「一按动成这样了」。

修法：定位到第 1 列，让行字符串自己带边距。

```bash
printf '\033[%d;1H%s' $((AGENT_TOP+i+1)) "$txt"
```

### 11. 字标居中显得飘，改成左对齐

边框里的字标一开始是居中的。但因为下方 agent 列表是左对齐的，
居中的字标和任何东西都不对齐，看着像「浮在框中间」。

改成左对齐（缩进 1 列，正好落在 agent 行 `│ ` 之后的图标位置），
字标起笔和 `❯`/状态标记同一条竖线，整块读起来是一个整体。

### 12. 清单扩到 19 个后，启动画面不再显示大 Y

`pick_logo` 用 `reserved = 8 + agent数` 算「要给菜单留多少行」，剩下的才给 logo。
只有 6 个 agent 时没问题；扩到 19 个后 8+19=27，在 31 行的终端里只剩 4 行，
于是判定「放不下」直接跳过 —— 大 Y 就消失了。

**这个预留逻辑本身就是错的**：闪屏是独立的全屏画面，画完就 `clear` 再画菜单，
两者不共存，闪屏根本不需要替菜单让位。改成只给自己留 6 行（品牌行、展开行、
环境行和上下留白），就正常了。

### 13. 清单变长后启动从 0.6 秒崩到 6.5 秒（子 shell 风暴）

加 agent 只是多几行数据，启动却慢了十倍。原因是**每条路径上都有 `$(...)`**：

| 位置 | 为什么慢 |
|---|---|
| `st="$(printf … \| awk …)"` 每行一次 | 每行一个管道 ≈ 49 ms |
| `NAME_W+=("$(disp_w "$name")")` 每行两次 | 每次一个 `wc` ≈ 34 ms |
| `body_off="$(make_row …)"` 每行两次 | 每次一个子 shell ≈ 14 ms |
| `status_of` 在 `check-agents.sh` 里也是 `$( )` | 每个 agent 一个子 shell |

19 个 agent × 上面几项，合计约 **6.5 秒**。逐项改掉：

- 状态表一次读进 bash **关联数组**，查找零 fork
- 状态样式 `_set_state_style` 只赋值全局 `_MK/_MC/_LB/_LW`，不 echo
- `make_row` 结果写全局 `_ROW`，调用方不再用 `$( )` 包
- 宽度计算换成**纯 bash 的 `_dw()`**（见第 14 条）
- `check-agents.sh` 的 `status_of` 也改成写全局 `_ST`

结果：**6.5 s → 0.6 s**（`load_agents` 5320→430 ms，`build_frame` 986→28 ms），
按键路径仍然是 0.47 ms/次。

### 14. 显示宽度可以用纯 bash 算，但必须修正「窄的非 ASCII 字符」

`wc -L` 每次要起一个外部进程（34 ms），而宽度在启动路径上要算几十次。
其实可以用纯 bash 近似：

```
宽度 ≈ 字符数 + 非 ASCII 字符数        (ASCII 占 1 列,宽字符占 2 列)
```

`${s//[ -~]/}` 删掉所有 ASCII 可打印字符，剩下的长度就是非 ASCII 字符数。

**坑**：一整套字符是非 ASCII 却只占 1 列 —— `·`(U+00B7)、`—`(U+2014)、
以及所有方块和制表字符 `█▀▄▐─│├┤╭╮╰╯` 和 `✓✗●⚠❯◆↑↓`。
不修正的话字标会被算宽一倍（`█   █` 会被当成 10 列而不是 5 列），整个布局崩掉。

修法：`_DW_NARROW` 列出这些字符，逐个扣回 1 列。
实测 **90 条字符串（含全部 Y 立绘行和字标行）与 `wc -L` 完全一致**。

加新的装饰字符时，记得同步补进 `_DW_NARROW`，否则宽度会算错。

### 15. 底边框多一个换行，把顶边框顶出屏幕

整屏最后打印的是底边框 `╰───╯`。它原本也以 `\n` 结尾 —— 多出来的这个换行
让光标越过最后一行，在「刚好排满」的终端里触发滚动，顶边框和字标第一行被吃掉。

实测 120×30 的窗口里正好打 29 行内容，加上这个换行就是 30 行，光标到第 31 行 → 上滚 1 行。

修法：`BOTTOM` 不带结尾换行。改完后 30/24/20/18/12 行各档终端实测都不再溢出。


## YZZ 三词组合

YZZ 是品牌标记（三个单词的首字母）。当前取的是 **your zero-config zone**。

改法：编辑 `tui/agentbox-tui.sh` 里这一行，或直接用环境变量覆盖：

```bash
YZZ_EXPAND="${YZZ_EXPAND:-your zero-config zone}"
```

```bash
YZZ_EXPAND="your zen zone" bash launch.sh     # 临时换一个试试
```

改完顶边框和启动画面会立刻跟着变，不需要动别的地方。

### 候选（英文）

| 组合 | 中文 | 评价 |
|---|---|---|
| **your zero-config zone** | 零配置区 | ★★★ 直接说清差异化：不用 WSL、不用管理员、装上就能跑 |
| **your zen zone** | 静心区 | ★★ 短、气质干净，但没说清这东西是干嘛的 |
| **yoke zero zone** | 套轭区 | ★★ 比喻生动（启动器=给 agent 上轭），但 yoke 偏生僻 |
| **yield zero-zero** | 零等待零成本 | ★★ 顺口，偏营销腔 |
| **your zero-zzz zone** | 不犯困区 | ★ 有梗，但 zzz 容易被读成「睡觉」 |

### 候选（中文，拼音首字母 Y-Z-Z）

| 组合 | 拼音 | 评价 |
|---|---|---|
| **驭智站** | yù zhì zhàn | ★★★ 「站」= 站点/发车站，正好是启动器语义；「驭」= 驾驭 agent |
| **引智站** | yǐn zhì zhàn | ★★ 语义也通，但与「引智工程」这类政策术语撞车 |
| **驿智站** | yì zhì zhàn | ★★ 驿站=中转，意象好，但「驿」偏冷僻 |

## 与原版 PocketAgentHub 的差异

| 项 | 原版 | 本整合版 |
|---|---|---|
| 菜单 | ANSI 手写 / Gum 增强 | AgentBox TUI（字标 + 半块 logo + 状态探测） |
| 执行命令 | `"$cmd"` 整体当一个命令名，带参数的命令找不到 | 安全切分成数组 exec；`!` 前缀走 shell（支持含空格路径） |
| 起始目录 | `pushd "%~dp0"` 切到 hub 目录 | 不切换，agent 继承调用者目录 |
| 清单 | 硬编码在脚本里 | `agents.tsv` 数据驱动 |
| Gum | 可选 | 不需要（内置 UI 已够） |

## 已知限制

- **需要交互式终端**：`launch.sh` 会检查 `-t 0/-t 1`，非 TTY 直接报错。
- **凭据探测是启发式**：只看环境变量或凭据文件是否存在，不验证是否有效。
- **快捷键只有 ↑↓ / j k / Enter / q**。原版页脚里的 `s 设置` 从来没实现过，
  这次已从页脚移除，避免提示一个按了没反应的键。
- **agent 退出后需要按 Enter 回菜单**（这是刻意设计，避免全屏程序清屏后看不到退出码）。
- 本机当前只有 `opencode` 和 `dsh` 是真就绪；其余 6 个显示 `✗ 未安装`，
  点进去会提示「找不到命令」并返回菜单，不会崩。
- **`●` 已安装不等于能登录**：它只说明命令在 PATH 里。
- 装了新 agent 后**重启启动器**才会重新探测状态（状态在启动时算一次）。
