# git-ignore

在 **repo / local / global** 三个层级管理 Git ignore 的小工具，fish 实现，
附 bash / zsh 等价实现与跨 shell 性能/内存对比。

## 三个层级

| 层级 | 作用域 | 位置 | 随仓库共享 | 选项 |
|---|---|---|---|---|
| repo | 仓库级，受版本控制 | `<toplevel>/.gitignore` | 是 | （默认） |
| local | 本检出私有 | `<git-dir>/info/exclude` | 否 | `-l`, `--local` |
| global | 用户的所有仓库 | `core.excludesFile`；未配置时回退 `~/.config/git/ignore` | 否 | `-g`, `--global` |

只有这三层——没有第四层 "private"（local 本身不进版本库，就是私有层），
也没有对应 `git config --system` / `--worktree` 的 ignore 文件。

## 用法

```text
Usage: git-ignore [-l|-g] [pattern ...]
       git-ignore [-l|-g] --path

  (no flag)     <toplevel>/.gitignore — version-controlled, shared via the repo
  -l, --local   .git/info/exclude — private to this checkout
  -g, --global  core.excludesFile — global for your user account
      --path    print the (absolute) ignore file path for the selected scope
  -h, --help    show this help
```

示例：

```fish
git-ignore '*.log'              # 写入仓库级 .gitignore
git-ignore -l .DS_Store         # 仅本检出私有
git-ignore -g '*.swp'           # 当前用户全部仓库
edit (git-ignore -l --path)     # 拿到路径交给编辑器
git-ignore -g --path | xargs edit
```

已存在的规则会整行去重跳过；无参数时查看当前文件（终端走 git pager，
管道走 cat）。

### 在 fish 中加载

本文件本身是一个 fish 函数，放进 fish 的 functions 目录即可自动加载；
若只想试用：

```fish
source ./git-ignore.fish
git-ignore -h
```

想让 `git ignore`（外部子命令）可用，需要在 PATH 上放一个薄跳板
（`git-ignore $argv`），见 [NOTES.md](NOTES.md) 第 7 节。

## 仓库结构

```text
git-ignore.fish          完整实现（fish 函数，single source）
benchmark/
  git-ignore.bash        最小等价实现（bash）
  git-ignore.zsh         最小等价实现（zsh，与 bash 版代码相同）
  git-ignore.fish        fish 基准入口（source 根目录完整实现）
  bench.sh               基准运行器
NOTES.md                 设计要点、踩坑记录、基准方法论
```

## 性能对比

运行：`./benchmark/bench.sh [iterations]`（可用 `FISH_BIN` 等环境变量
覆盖解释器路径）。

热缓存稳态，每例 80 次取平均，环境：macOS / Apple M1（MacBook Air 2020），
bash 3.2（系统自带）、zsh 5.9、fish 4.9.3，2026-10-07 测：

| shell | version | startup (ms) | --path (ms) | write (ms) | RSS startup (KB) | RSS --path (KB) |
|---|---|---|---|---|---|---|
| bash | 3.2.57 | 9.64 | 22.96 | 28.43 | 1648 | 3504 |
| zsh | 5.9 | 10.76 | 15.99 | 21.73 | 2096 | 3952 |
| fish | 4.9.3 | 18.88 | 24.27 | 30.40 | 5040 | 4992 |

解读：

- **纯启动**：bash 与 zsh 相近（约 10 ms），fish 约 2 倍（约 19 ms）。
- **`--path`**（含一次 `git` 子进程）：zsh 最快 16 ms；fish 与 bash
  接近（23–24 ms）——git 子进程成为主要成本后，解释器差距被摊薄。
- **写入**：zsh 22 ms < bash 28 ms ≈ fish 30 ms。fish 跑的是完整实现，
  bash/zsh 是最小子集，实际差距比数字更小。
- **内存**：fish 峰值约 5 MB，bash 1.6–3.5 MB、zsh 2–4 MB；fish 约为
  2–3 倍，但绝对值都很小。
- 所有场景总耗时均 < 31 ms，交互使用无感知差异，选 shell 不必在意
  这点开销。

注意：首轮冷启动/系统有负载时数据可能高出数倍（实测 bash RSS 一度
7.3 MB、startup 45 ms），连续两轮数据稳定后才可采信。

## 相关

- 主 dotfiles 仓库：`~/Config`，本文件随其部署到
  `~/.config/fish/functions/git-ignore.fish`。
