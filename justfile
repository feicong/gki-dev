# Copyright (c) 2025-2026 fei_cong(https://github.com/feicong/feicong-course)

# 默认命令，列出所有可用命令
default:
    @just --list

# 检查所有依赖命令
doctor:
    #!/usr/bin/env bash
    set -e
    cmds=(tar wget 7z unzip dpkg apt-get ip getent usermod groupadd)
    missing=()
    for cmd in "${cmds[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done
    if [ ${#missing[@]} -eq 0 ]; then
        echo "所有依赖命令均已安装。"
    else
        echo "缺少如下命令，请手动安装：${missing[*]}"
        exit 1
    fi

# 下载CVD镜像
cvd:
    #!/usr/bin/env bash
    set -e
    mkdir -p bin
    need_download=0
    # 检查 bin/adb 和 bin/cvd
    if [ ! -f "bin/adb" ] || [ ! -f "bin/cvd" ]; then
        arch=$(uname -m)
        if [[ "$arch" == "aarch64" ]]; then
            tarfile="cvd-host_package_arm64.tar.gz"
        elif [[ "$arch" == "x86_64" ]]; then
            tarfile="cvd-host_package_x86_64.tar.gz"
        else
            echo "不支持的架构: $arch"; exit 1
        fi
        url="https://github.com/feicong/feicong-course/releases/download/android-course/$tarfile"
        # 检查本地 tar.gz 文件
        if [ ! -f "$tarfile" ]; then
            echo "$tarfile 不存在，正在下载..."
            wget -O "$tarfile" "$url"
        fi

        echo "正在解压 $tarfile ..."
        tar -xzvf "$tarfile"
    else
        echo "cvd 已存在，无需下载。"
    fi

# 下载安卓GSI镜像
gsi:
    #!/usr/bin/env bash
    set -e
    arch=$(uname -m)
    imgs=(super.img boot.img)
    missing=()
    for img in "${imgs[@]}"; do
        if [ ! -f "$img" ]; then
            missing+=("$img")
        fi
    done
    if [ ${#missing[@]} -eq 0 ]; then
        echo "所有 img 文件已存在: ${imgs[*]}"
        exit 0
    fi
    # 选择 zip 文件名和下载地址
    if [[ "$arch" == "aarch64" ]]; then
        zipfile="aosp_cf_arm64_phone-img-13823094.zip"
    elif [[ "$arch" == "x86_64" ]]; then
        zipfile="aosp_cf_x86_64_phone-img-13823094.zip"
    else
        echo "不支持的架构: $arch"; exit 1
    fi
    url="https://github.com/feicong/feicong-course/releases/download/android-course/$zipfile"
    # 检查本地 zip 文件
    if [ ! -f "$zipfile" ]; then
        echo "$zipfile 不存在，正在下载..."
        wget -O "$zipfile" "$url"
    fi
    # 检查解压工具
    if ! command -v 7z &>/dev/null; then
        echo "未检测到 7z，请先安装：sudo apt-get install p7zip-full"; exit 1
    fi
    # 解压缺失的 img 文件
    for img in "${missing[@]}"; do
        echo "正在从 $zipfile 解压 $img ..."
        7z e "$zipfile" "$img"
    done
    echo "img 文件已准备好: ${imgs[*]}"

# 检查并安装cuttlefish所需环境
cuttlefish:
    #!/usr/bin/env bash
    set -e
    # 检查 cvd-ebr 网络接口
    if ! ip link show cvd-ebr &>/dev/null; then
        echo "cvd-ebr 网络接口不存在"
        arch=$(uname -m)
        pkg_arm64="cuttlefish_packages_arm64.7z"
        pkg_x86_64="cuttlefish_packages_x86_64.zip"
        url_arm64="https://github.com/feicong/feicong-course/releases/download/android-course/cuttlefish_packages_arm64.7z"
        url_x86_64="https://github.com/feicong/feicong-course/releases/download/android-course/cuttlefish_packages_x86_64.zip"
        if [[ "$arch" == "aarch64" ]]; then
            if [ ! -f "$pkg_arm64" ]; then
                echo "$pkg_arm64 不存在，正在下载..."
                wget -O "$pkg_arm64" "$url_arm64"
            fi
            if ! command -v 7z &>/dev/null; then
                echo "未检测到 7z，请先安装：sudo apt-get install p7zip-full"; exit 1
            fi
            echo "解压 $pkg_arm64"
            7z x "$pkg_arm64"
        elif [[ "$arch" == "x86_64" ]]; then
            if [ ! -f "$pkg_x86_64" ]; then
                echo "$pkg_x86_64 不存在，正在下载..."
                wget -O "$pkg_x86_64" "$url_x86_64"
            fi
            if ! command -v unzip &>/dev/null; then
                echo "未检测到 unzip，请先安装：sudo apt-get install unzip"; exit 1
            fi
            echo "解压 $pkg_x86_64"
            unzip "$pkg_x86_64"
        else
            echo "不支持的架构: $arch"
            exit 1
        fi
        # 安装 deb 包
        sudo dpkg -i ./cuttlefish-base_*_*64.deb || sudo apt-get install -f -y
        sudo dpkg -i ./cuttlefish-user_*_*64.deb || sudo apt-get install -f -y
    else
        echo "cvd-ebr 网络接口已存在"
    fi

    # 检查 cvdnetwork 用户组
    if ! getent group cvdnetwork &>/dev/null; then
        echo "cvdnetwork 用户组不存在，正在添加"
        sudo groupadd cvdnetwork
    else
        echo "cvdnetwork 用户组已存在"
    fi

    # 添加用户到相关组
    sudo usermod -aG kvm,cvdnetwork,render $USER
    
    echo "请执行 sudo reboot 以使更改生效"

# 启动 cvd（待实现）
start:
    echo "启动 cvd 功能待实现"

# 停止 cvd（待实现）
stop:
    echo "停止 cvd 功能待实现"
