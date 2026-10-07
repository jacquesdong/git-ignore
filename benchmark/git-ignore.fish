#!/usr/bin/env fish
# fish 版基准入口：直接 source 根目录下的完整实现（真正的 single source），
# 再调用函数。与 bash/zsh 最小版相比，fish 跑的是完整逻辑，因此其数据
# 代表"当前真实实现"的开销，而不是裸解释器开销（source 一个 8KB 文件
# 的成本本身可忽略）。
source (status dirname)/../git-ignore.fish
git-ignore $argv
