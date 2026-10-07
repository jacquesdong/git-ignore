# git-ignore —— 在三个层级上管理 git ignore
#
# 层级划分（思路对齐 git config 的 local / global）：
#
# | 层级   | 作用域          | 位置                                         | 随仓库共享 | flag       |
# |--------|-----------------|----------------------------------------------|------------|------------|
# | repo   | 仓库级，受控    | <toplevel>/.gitignore                        | 是         | （默认）   |
# | local  | 本检出私有      | <git-dir>/info/exclude                       | 否         | -l/--local |
# | global | 用户的所有仓库  | core.excludesFile；默认 ~/.config/git/ignore | 否         | -g/--global|
#
# 设计要点 / 踩坑记录：
# 1. local 路径绝不能自己拼 "$toplevel/.git/info/exclude"：
#    - linked worktree 的 .git 是文件（内容一行 "gitdir: ..."），不是目录；
#    - submodule / bare 仓库 / 设置了 GIT_DIR 时同样不成立；
#    - 用 `git rev-parse --git-path info/exclude`，以上场景全部通用。
#    - 注意 linked worktree 下它解析到主仓库的 common dir，即多个 worktree
#      共享同一份 info/exclude（这是 git 的既定行为，开启
#      extensions.worktreeConfig 也不改变）。
#    - bare 仓库：站在 bare 目录内执行 git 能自识别（无需 --git-dir/GIT_DIR），
#      -l 直接可写；但 bare 没有工作树，repo scope 天然不可用（要工作树得另设
#      --work-tree / core.worktree，与本工具无关）。站在 bare 目录外才需要
#      --git-dir=<bare> 或 GIT_DIR 环境变量。
# 2. `git rev-parse --git-dir` 可能返回相对当前目录的路径；要绝对路径用
#    --absolute-git-dir。--git-path 同样可能给相对路径：--path 打印前用
#    fish 内置 `path resolve` 转成绝对路径，方便从别的目录把路径喂给其它
#    编辑器；就地查看/写入时相对路径也安全。
#    注意 `path resolve` 不要求文件/目录存在（不存在照样给绝对路径，exit 0），
#    这点和 GNU realpath 默认要求路径存在不同。
# 3. global 层必须用 `git config --path`：只有 --path 会展开配置值里的 "~/"，
#    普通 `git config` 原样返回字面值。未配置时回退 $XDG_CONFIG_HOME/git/ignore。
#    读"生效值"而不指定 scope，天然覆盖 --system/--global/--worktree 的优先级：
#    仓库开启 extensions.worktreeConfig 后，linked worktree 里用
#    `git config --worktree core.excludesFile <file>` 可给单个 worktree 指定
#    不同的 ignore 文件——这也是 linked worktree 想要"真正私有"ignore 的
#    唯一路径（info/exclude 是共享的）。
# 4. 去重用 grep -Fx（整行 + 固定字符串），规则里的 * ? ! [ 不会被当正则。
# 5. ignore 文件可能没有末尾换行（手工编辑过），追加前检测并补一个，否则
#    新规则会粘到旧行末。
# 6. 无参数查看：stdout 是终端（fish 用 isatty stdout 判断；test -t 只吃
#    数字 FD，不能写 test -t stdout）时走 git 认可的分页器（git var GIT_PAGER，
#    解析顺序 GIT_PAGER -> core.pager -> $PAGER -> less；值可能带参数，
#    string split 拆开），管道里走 cat（git 在非 tty 时同样不分页）；
#    文件不存在时静默成功（git 也允许这些文件不存在）。
# 7. fish 函数本身不进 PATH；PATH 入口由跳板 scripts/.scripts/git-ignore 提供
#    （3 行 fish 脚本：git-ignore $argv；bin/.local/bin/git-ignore 软链到它）。
#    `git ignore`（git 按 PATH 找外部子命令 git-ignore）和直接执行 git-ignore
#    都经跳板进入本函数——非交互 fish 也会按需 autoload functions/ 下的函数。
#    不用 sh 再写第二套逻辑；原始 sh 版保留在 git-ignore.sh 仅作备份。
#    另可自己加 abbr（如 gi）。
# 8. 控制流：先按 scope 解析出唯一一个 $file，之后 --path / 查看 / 追加共用它，
#    不再各自解析。错误处理用最简方式：不捕获 git 的 stderr（git 的原始
#    fatal 直接显示），失败时 app 只补一行 context 再 return——两行输出，
#    但省掉了 2>&1/string join/string replace 一整套。曾走过三个弯路：
#    - 先解析全部三层、用 *_err 变量延迟统一报错：为 --path 一个场景让所有
#      路径背上 test -n err，过度设计；
#    - 捕获 git 原话再与 context 拼成一行：捕获和清洗成本高，收益只是一行
#      而非两行，不值得；
#    - --path 的前身 --list 曾一次列出三层路径：既重复一套解析逻辑，输出也
#      不方便直接喂给别的软件。最终改为跟随 -l/-g/默认 scope，只打印一个
#      （绝对）路径，例如 `edit (git-ignore -l --path)`。
function git-ignore --description 'Add patterns to ignore files at repo/local/global level'
    argparse -x 'l,g' l/local g/global path h/help -- $argv
    or return 1

    if set -ql _flag_help
        echo 'Usage: git-ignore [-l|-g] [pattern ...]
       git-ignore [-l|-g] --path

  (no flag)     <toplevel>/.gitignore — version-controlled, shared via the repo
  -l, --local   .git/info/exclude — private to this checkout
  -g, --global  core.excludesFile — global for your user account
      --path    print the (absolute) ignore file path for the selected scope;
                e.g. edit (git-ignore -l --path), or run --path first and
                append the pipe interactively: git-ignore -g --path | xargs edit
  -h, --help    show this help

Already-present lines are skipped.
Viewer on a terminal follows git pager resolution:
  GIT_PAGER > core.pager > $PAGER > less; piped output uses cat.'
        return 0
    end

    # 按 scope 解析唯一一个文件；失败就地报错立即返回（见踩坑 8）
    set -l file
    if set -ql _flag_local
        set file (git rev-parse --git-path info/exclude)
        or begin
            echo "git-ignore: cannot resolve local ignore file" >&2
            return 1
        end
    else if set -ql _flag_global
        set file (git config --path core.excludesFile)
        if test -z "$file"
            if set -q XDG_CONFIG_HOME[1]
                set file $XDG_CONFIG_HOME/git/ignore
            else
                set file ~/.config/git/ignore
            end
        end
    else
        set -l root (git rev-parse --show-toplevel)
        or begin
            echo "git-ignore: cannot resolve worktree ignore file" >&2
            echo 'git-ignore: use -l/--local (this checkout) or -g/--global (your user account)' >&2
            return 1
        end
        set file $root/.gitignore
    end

    if set -ql _flag_path
        # 绝对路径，方便从任何目录交给其它软件（文件尚不存在也能解析）
        path resolve -- $file
        return 0
    end

    if not set -ql argv[1]
        if test -f $file
            if isatty stdout
                # GIT_PAGER -> core.pager -> $PAGER -> less；值可能带参数
                # 注意只放一个 --：它属于 string split，SEP ' ' 本身不是选项
                set -l pager_cmd (string split ' ' -- (git var GIT_PAGER))
                $pager_cmd -- $file
            else
                cat -- $file
            end
        end
        return 0
    end

    # global 文件的目录可能还没建；local/repo 的目录必然存在
    mkdir -p (dirname -- $file)

    # 缺末尾换行（可能手工编辑过）需要先修复换行。
    #
    # fish 的命令替换 只剥离末尾换行符 ，不会像 bash 那样对空白（空格、tab）做分词——所以：
    # - 末字节是空格()`0x20`)/TAB(`0x09`)：作为一个非空元素保留，`test -n` 为真 → 正确识别为需要补换行
    # - 末字节是换行：被替换机制吞掉，结果为空，`test -n` 为假 → 不补
    # - 末字节是普通字符：非空，补
    if test -s $file && test -n (tail -c 1 -- $file)
        echo >>$file
    end

    for pattern in $argv
        if grep -Fxq -- $pattern $file 2>/dev/null
            echo "git-ignore: already present in $file: $pattern" >&2
        else
            printf '%s\n' $pattern >>$file
        end
    end
end
