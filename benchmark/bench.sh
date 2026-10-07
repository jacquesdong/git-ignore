#!/usr/bin/env bash
# bench.sh —— 对比 bash / zsh / fish 三种实现的启动延迟与峰值内存。
#
# 测什么：
#   startup   解释器执行 -c 'true'：纯进程启动 + 解释器初始化
#   --path    解析 ignore 文件路径并打印：启动 + 一次 git 子进程
#   write     -l 写入一条规则（每次测量前清空 exclude）：再加 grep 去重 + 文件 IO
# 内存：
#   用 macOS 自带 /usr/bin/time -l 取 "maximum resident set size"（峰值 RSS，KB），
#   各跑 2 次取最大值；延迟跑 N 次取平均（毫秒），前 3 次预热。
#
# 用法：bench.sh [iterations]
# 可用环境变量覆盖解释器路径：BASH_BIN / ZSH_BIN / FISH_BIN
set -u

N="${1:-50}"
HERE="$(cd "$(dirname "$0")" && pwd)"

BASH_BIN="${BASH_BIN:-/bin/bash}"
ZSH_BIN="${ZSH_BIN:-/bin/zsh}"
FISH_BIN="${FISH_BIN:-$(command -v fish 2>/dev/null || echo /opt/homebrew/bin/fish)}"

# 临时 git 仓库；写测试只动 local exclude，不碰用户全局文件
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
git init -q "$TMP/repo" || { echo "git init failed" >&2; exit 1; }
cd "$TMP/repo"
EXCLUDE="$(git rev-parse --git-path info/exclude)"

now_ms() { perl -MTime::HiRes=time -e 'printf "%.0f", time()*1000'; }

# avg_ms [--reset] cmd...：N 次平均耗时（ms）
avg_ms() {
    local reset=0
    if [ "${1:-}" = "--reset" ]; then reset=1; shift; fi
    local i s e tot=0
    for i in 1 2 3; do
        [ "$reset" -eq 1 ] && : > "$EXCLUDE"
        "$@" >/dev/null 2>&1
    done
    for i in $(seq 1 "$N"); do
        [ "$reset" -eq 1 ] && : > "$EXCLUDE"
        s=$(now_ms); "$@" >/dev/null 2>&1; e=$(now_ms)
        tot=$((tot + e - s))
    done
    awk -v t="$tot" -v n="$N" 'BEGIN { printf "%.2f", t / n }'
}

# peak_kb cmd...：两次测量取峰值 RSS（KB）
peak_kb() {
    local best=0 r i
    for i in 1 2; do
        r=$(/usr/bin/time -l "$@" 2>&1 | awk '/maximum resident set size/ { print int($1 / 1024); exit }')
        [ -n "$r" ] && [ "$r" -gt "$best" ] && best=$r
    done
    echo "$best"
}

# 先冒烟检查，命令本身有问题直接失败
"$BASH_BIN" "$HERE/git-ignore.bash" --path >/dev/null || exit 1
"$ZSH_BIN"  "$HERE/git-ignore.zsh"  --path >/dev/null || exit 1
"$FISH_BIN" "$HERE/git-ignore.fish" --path >/dev/null || exit 1

BASH_VER="$("$BASH_BIN" -c 'printf %s "$BASH_VERSION"')"
ZSH_VER="$("$ZSH_BIN" -c 'printf %s "$ZSH_VERSION"')"
FISH_VER="$("$FISH_BIN" -c 'printf %s "$version"')"

# 数据采集（顺序：每个解释器连续测，减少交替干扰）
declare -a NAME=(bash zsh fish)
declare -a BIN=("$BASH_BIN" "$ZSH_BIN" "$FISH_BIN")
declare -a SCRIPT=("$HERE/git-ignore.bash" "$HERE/git-ignore.zsh" "$HERE/git-ignore.fish")
declare -a VERS=("$BASH_VER" "$ZSH_VER" "$FISH_VER")

for k in 0 1 2; do
    interp="${BIN[$k]}"; script="${SCRIPT[$k]}"
    eval "T_START[$k]=\$(avg_ms \"\$interp\" -c true)"
    eval "T_PATH[$k]=\$(avg_ms \"\$interp\" \"\$script\" --path)"
    eval "T_WRITE[$k]=\$(avg_ms --reset \"\$interp\" \"\$script\" -l bench-pattern)"
    eval "M_START[$k]=\$(peak_kb \"\$interp\" -c true)"
    eval "M_PATH[$k]=\$(peak_kb \"\$interp\" \"\$script\" --path)"
done

echo "iterations per case: $N"
echo
echo "| shell | version | startup (ms) | --path (ms) | write (ms) | RSS startup (KB) | RSS --path (KB) |"
echo "|---|---|---|---|---|---|---|"
for k in 0 1 2; do
    printf "| %s | %s | %s | %s | %s | %s | %s |\n" \
        "${NAME[$k]}" "${VERS[$k]}" \
        "${T_START[$k]}" "${T_PATH[$k]}" "${T_WRITE[$k]}" \
        "${M_START[$k]}" "${M_PATH[$k]}"
done
