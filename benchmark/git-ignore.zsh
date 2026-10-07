#!/usr/bin/env zsh
# git-ignore 的最小等价实现（zsh 版），用于跨 shell 性能对比。
# 代码与 git-ignore.bash 完全一致（POSIX 风格，bash/zsh 都能跑），
# 差异只来自解释器本身。详见 git-ignore.bash 顶部说明。
set -u

scope=repo
show_path=0
while [ $# -gt 0 ]; do
    case $1 in
        -l|--local)  scope=local;  shift ;;
        -g|--global) scope=global; shift ;;
        --path)      show_path=1; shift ;;
        --)          shift; break ;;
        *)           break ;;
    esac
done

case $scope in
    local)
        file=$(git rev-parse --git-path info/exclude) || exit 1
        ;;
    global)
        file=$(git config --path core.excludesFile)
        if [ -z "$file" ]; then
            file="${XDG_CONFIG_HOME:-$HOME/.config}/git/ignore"
        fi
        ;;
    repo)
        root=$(git rev-parse --show-toplevel) || exit 1
        file="$root/.gitignore"
        ;;
esac

if [ "$show_path" -eq 1 ]; then
    printf '%s\n' "$file"
    exit 0
fi

if [ $# -eq 0 ]; then
    [ -f "$file" ] && cat -- "$file"
    exit 0
fi

mkdir -p "$(dirname -- "$file")"
for pattern in "$@"; do
    if grep -Fxq -- "$pattern" "$file" 2>/dev/null; then
        echo "git-ignore: already present in $file: $pattern" >&2
    else
        printf '%s\n' "$pattern" >> "$file"
    fi
done
