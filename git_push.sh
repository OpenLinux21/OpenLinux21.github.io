#!/bin/bash

# Git 快速提交脚本
# 使用方法: ./git-push.sh [可选的提交信息]

# 颜色定义
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 获取当前日期时间
current_date=$(date "+%Y-%m-%d %H:%M:%S")

# 如果提供了参数，使用参数作为提交信息的前缀，否则使用默认的 "website update"
if [ -z "$1" ]; then
    commit_message="website update ! $current_date"
else
    commit_message="$* ! $current_date"
fi

echo -e "${BLUE}=== Git 快速提交工具 ===${NC}"
echo -e "${YELLOW}提交信息: $commit_message${NC}\n"

# 显示当前状态
echo -e "${BLUE}📋 当前更改:${NC}"
git status --short

echo ""
read -p "确认提交这些更改？(Y/n) " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
    # 添加所有更改
    echo -e "${BLUE}📦 添加文件...${NC}"
    git add .
    
    # 提交
    echo -e "${BLUE}💾 提交更改...${NC}"
    git commit -m "$commit_message"
    
    # 推送
    echo -e "${BLUE}🚀 推送到远程仓库...${NC}"
    git push
    
    if [ $? -eq 0 ]; then
        echo -e "\n${GREEN}✅ 成功! 所有更改已推送到远程仓库${NC}"
    else
        echo -e "\n${YELLOW}⚠️  推送失败，请检查错误信息${NC}"
        exit 1
    fi
else
    echo -e "${YELLOW}❌ 已取消提交${NC}"
    exit 0
fi
