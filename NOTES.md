# NOTES —— 设计要点、踩坑记录与基准方法论

## 设计要点 / 踩坑

### 1. local 路径不能自己拼

绝不要写 `"$toplevel/.git/info/exclude"`：

- linked worktree 的 `.git` 是文件（内容一行 `gitdir: ...`），不是目录；
- submodule / bare 仓库 / 设置了 `GIT_DIR` 时同样不成立；
- 用 `git rev-parse --git-path info/exclude`，以上场景全部通用。

linked worktree 下它解析到主仓库的 common dir——多个 worktree **共享**
同一份 info/exclude（开启 `extensions.worktreeConfig` 也不改变）。

bare 仓库：站在 bare 目录内 git 能自识别（无需 `--git-dir`），`-l`
直接可写；但没有工作树，repo scope 天然不可用。站在 bare 目录外才需要
`--git-dir=<bare>` 或 `GIT_DIR`。

### 2. 路径要转绝对

`git rev-parse --git-dir` / `--git-path` 可能返回相对当前目录的路径。
`--path` 打印前用 fish 内置 `path resolve` 转绝对路径。

`path resolve` **不要求文件/目录存在**（不存在照样给绝对路径，exit 0），
与 GNU realpath 默认行为不同。

### 3. global 用 `git config --path`

只有 `--path` 会展开配置值里的 `~/`，普通 `git config` 原样返回。
未配置时回退 `$XDG_CONFIG_HOME/git/ignore`。

想要 linked worktree "真正私有"的 ignore，唯一路径是

```fish
git config --worktree core.excludesFile <file>
```

（info/exclude 是共享的。）

### 4. 去重用 grep -Fx

整行 + 固定字符串匹配，规则里的 `* ? ! [` 不会被当正则。

### 5. 末尾换行防护

ignore 文件可能没有末尾换行（手工编辑过），追加前检测并补一个，否则
新规则会粘到旧行末。

fish 的命令替换**只剥离末尾换行符**，不对空格/tab 分词：

- 末字节是空格（`0x20`）/TAB（`0x09`）：作为非空元素保留，`test -n`
  为真，正确识别为需要补换行；
- 末字节是换行：被吞掉，结果为空，不补；
- 末字节是普通字符：非空，补。

检测只取决于文件本身，循环外做一次即可，不必每条规则都检测。

### 6. 查看：tty 判断与 pager

- tty 用 `isatty stdout` 判断；`test -t` 只吃数字 FD，不能写
  `test -t stdout`。
- pager 用 `git var GIT_PAGER`：`GIT_PAGER` → `core.pager` → `$PAGER`
  → `less`；值可能带参数，`string split ' '` 拆开。
- 非 tty（管道）走 `cat`，git 自己也是这样。
- 文件不存在时静默成功。

### 7. PATH 入口：薄跳板，不要第二套实现

fish 函数本身不进 PATH，`git ignore`（git 按 PATH 找外部子命令
`git-ignore`）和 git alias 都调不到它。

做法：在 PATH 上放一个 3 行跳板——

```fish
#!/usr/bin/env fish
git-ignore $argv
```

非交互 fish 也会按需 autoload functions/ 下的函数。不要用 sh 重写
整套逻辑，否则双份维护。

### 8. 控制流：解析一次，三处共用

先按 scope 解析出唯一一个 `$file`，之后 `--path` / 查看 / 追加共用它。

错误处理用最简方式：**不捕获 git 的 stderr**（原始 fatal 直接显示），
失败时 app 只补一行 context 再 return。走过的弯路：

- 先解析全部三层、用 `*_err` 变量延迟统一报错：为 `--path` 一个场景
  让所有路径背上检查，过度设计；
- 捕获 git 原话与 context 拼成一行：`2>&1` + `string replace` 成本高，
  收益只是一行而非两行；
- `--path` 的前身 `--list` 曾一次列出三层路径：重复解析，输出也不
  方便直接喂给别的软件。

### 9. fish 其它小坑

- `string replace '^fatal:'` 默认**字面匹配**，正则要加 `-r`。
- `string split -- ' ' -- $input` 两个 `--` 会让第二个变成输入，
  命令名变成 `--`；只需要一个 `--`。

## 基准方法论

- 工具：macOS 自带 `/opt/homebrew` 之外零依赖。计时用
  `perl -MTime::HiRes`，峰值 RSS 用 `/usr/bin/time -l`
  （maximum resident set size，字节 → KB）。
- 场景：
  - `startup`：`$interp -c 'true'`，纯进程启动；
  - `--path`：启动 + 一次 git 子进程 + 路径解析打印；
  - `write`：每次测量前清空 exclude，再 `-l` 写一条规则（grep 去重
    + IO）。写测试只动 local exclude，不碰用户全局文件。
- 每场景 3 次预热，N 次取平均；RSS 两次取最大。
- **公平性说明**：bash/zsh 跑的是刻意精简的等价实现，fish 跑的是根
  目录完整实现（经 `benchmark/git-ignore.fish` source）。所以 fish
  数据代表"当前真实实现"的开销，对实际选型更有意义；若要纯解释器
  对比，三份应统一为最小子集。
- **数据采信**：冷缓存或系统有负载时结果可高出数倍且 RSS 失真，连续
  两轮数字稳定后再记录（README 中为收敛后的数据）。
