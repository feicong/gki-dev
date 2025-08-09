# Copyright (c) 2025-2026 fei_cong(https://github.com/feicong/feicong-course)

# 统一目录变量
DEPS := "deps"
CVD := "cvd"

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
    mkdir -p {{DEPS}} {{CVD}}
    # 检查 cvd 和 adb 是否存在
    if [ ! -f "{{CVD}}/bin/adb" ] || [ ! -f "{{CVD}}/bin/cvd" ]; then
        arch=$(uname -m)
        if [[ "$arch" == "aarch64" ]]; then
            tarfile="{{DEPS}}/cvd-host_package_arm64.tar.gz"
            tarname="cvd-host_package_arm64.tar.gz"
        elif [[ "$arch" == "x86_64" ]]; then
            tarfile="{{DEPS}}/cvd-host_package_x86_64.tar.gz"
            tarname="cvd-host_package_x86_64.tar.gz"
        else
            echo "不支持的架构: $arch"; exit 1
        fi
        url="https://github.com/feicong/feicong-course/releases/download/android-course/$tarname"
        # 检查本地 tar.gz 文件
        if [ ! -f "$tarfile" ]; then
            echo "$tarfile 不存在，正在下载..."
            wget -O "$tarfile" "$url"
        fi
        echo "正在解压 $tarfile 到 {{CVD}}/ ..."
        tar -xzvf "$tarfile" -C {{CVD}} --strip-components=0
    else
        echo "{{CVD}}/bin/adb 和 {{CVD}}/bin/cvd 已存在，无需下载。"
    fi

# 下载安卓GSI镜像
gsi:
    #!/usr/bin/env bash
    set -e
    mkdir -p {{DEPS}} {{CVD}}
    arch=$(uname -m)
    if [[ "$arch" == "aarch64" ]]; then
        zipfile="{{DEPS}}/aosp_cf_arm64_phone-img-13823094.zip"
        zipname="aosp_cf_arm64_phone-img-13823094.zip"
    elif [[ "$arch" == "x86_64" ]]; then
        zipfile="{{DEPS}}/aosp_cf_x86_64_phone-img-13823094.zip"
        zipname="aosp_cf_x86_64_phone-img-13823094.zip"
    else
        echo "不支持的架构: $arch"; exit 1
    fi
    url="https://github.com/feicong/feicong-course/releases/download/android-course/$zipname"
    # 检查本地 zip 文件
    if [ ! -f "$zipfile" ]; then
        echo "$zipfile 不存在，正在下载..."
        wget -O "$zipfile" "$url"
    fi
    # 解压zip文件
    echo "正在解压 $zipfile 到 {{CVD}}/ ..."
    unzip -n -o "$zipfile" -d {{CVD}} || { echo "解压失败，请检查是否安装了 unzip 命令"; exit 1; }
    echo "所有文件已准备好。"

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
            if [ ! -f "{{DEPS}}/$pkg_arm64" ]; then
                echo "$pkg_arm64 不存在，正在下载..."
                wget -O "{{DEPS}}/$pkg_arm64" "$url_arm64"
            fi
            echo "解压 $pkg_arm64"
            7z x "$pkg_arm64"
        elif [[ "$arch" == "x86_64" ]]; then
            if [ ! -f "{{DEPS}}/$pkg_x86_64" ]; then
                echo "$pkg_x86_64 不存在，正在下载..."
                wget -O "{{DEPS}}/$pkg_x86_64" "$url_x86_64"
            fi
            echo "解压 $pkg_x86_64"
            unzip "{{DEPS}}/$pkg_x86_64"
        else
            echo "不支持的架构: $arch"
            exit 1
        fi
        echo "安装 deb 包"
        sudo dpkg -i ./cuttlefish-base_*_*64.deb || sudo apt-get install -f -y
        sudo dpkg -i ./cuttlefish-user_*_*64.deb || sudo apt-get install -f -y
        rm -rf *.deb
    else
        echo "cvd-ebr 网络接口已存在"
    fi

    # 检查 cvdnetwork 用户组
    if ! getent group cvdnetwork &>/dev/null; then
        echo "cvdnetwork 用户组不存在，正在添加"
        sudo groupadd cvdnetwork
        # 添加用户到相关组
        sudo usermod -aG kvm,cvdnetwork,render $USER
        echo "请执行 sudo reboot 以使更改生效"
    else
        echo "cvdnetwork 用户组已存在"
    fi

# 启动 cvd
start: cuttlefish cvd gsi
    #!/usr/bin/env bash
    set -e
    echo "启动 cvd"
    # cd {{CVD}} && HOME=$PWD bin/launch_cvd -vm_manager qemu_cli -report_anonymous_usage_stats=n -enable_audio=false --start_webrtc=false -daemon && cd ..
    cd {{CVD}} && HOME=$PWD bin/launch_cvd -report_anonymous_usage_stats=n -daemon && cd ..

# 停止 cvd
stop:
    #!/usr/bin/env bash
    set -e
    echo "检查是否有在线设备..."
    online=$(./{{CVD}}/bin/adb devices | awk '/\tdevice$/ {print $1}')
    if [ -n "$online" ]; then
        echo "检测到在线设备: $online，执行 stop_cvd"
        cd {{CVD}} && HOME=$PWD bin/stop_cvd && cd ..
    else
        echo "无在线设备，无需停止。"
    fi

# 运行CVD指定内核文件
run-kernel:
    #!/usr/bin/env bash
    HOME=$PWD bin/launch_cvd -report_anonymous_usage_stats=n \
        -kernel_path ../gki-env/android13-5.15-167/bazel-bin/common/kernel_x86_64/bzImage \
        -initramfs_path ../gki-env/android13-5.15-167/bazel-bin/common-modules/virtual-device/virtual_device_x86_64_images_initramfs/initramfs.img \
        --daemon

# 调试CV内核
debug-kernel:
    #!/usr/bin/env bash
    HOME=$PWD bin/launch_cvd -report_anonymous_usage_stats=n \
        -kernel_path ../gki-env/android13-5.15-167/bazel-bin/common/kernel_x86_64/bzImage \
        -initramfs_path ../gki-env/android13-5.15-167/bazel-bin/common-modules/virtual-device/virtual_device_x86_64_images_initramfs/initramfs.img \
        -gdb_port 1234 -cpus=1 \
        -extra_kernel_cmdline nokaslr \
        --daemon

# 构建GKI内核
attach-cvd:
    #!/usr/bin/env bash
    set -e
    gdb ../gki-env/android13-5.15-167/bazel-bin/common/kernel_x86_64/vmlinux -ex "target remote :1234" -ex "hbreak start_kernel" -ex "set pagination off" -ex "bt" -ex "continue"
