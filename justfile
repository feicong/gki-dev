# Copyright (c) 2025-2026 fei_cong(https://github.com/feicong/feicong-course)

# 统一目录变量
DEPS := "deps"
CVD := "cvd"
GKI := "gki"
SCRIPTS := "scripts"

export GKI_ANDROID_VERSION := env_var_or_default("GKI_ANDROID_VERSION", "android13")
export GKI_KERNEL_VERSION := env_var_or_default("GKI_KERNEL_VERSION", "5.15")

GKI_RELEASE_INFO := GKI + "/release.env"
GKI_AARCH64_DIR := GKI + "/aarch64"
GKI_X86_64_DIR := GKI + "/x86_64"
GKI_BOOT_IMG := GKI_AARCH64_DIR + "/boot.img"
GKI_X86_BOOT_IMG := GKI_X86_64_DIR + "/boot.img"
GKI_BZIMAGE := GKI_X86_64_DIR + "/bzImage"
GKI_VMLINUX := GKI_X86_64_DIR + "/vmlinux"

# 默认命令，列出所有可用命令
default:
    @just --list

# 检查所有依赖命令
doctor:
    #!/usr/bin/env bash
    set -e
    cmds=(tar wget curl 7z unzip xz dpkg apt-get ip getent usermod groupadd gdb fastboot)
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

# 刷新GKI信息
gki-release:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p {{GKI}}
    bash {{SCRIPTS}}/gki-release.sh {{GKI_ANDROID_VERSION}} {{GKI_KERNEL_VERSION}} > {{GKI_RELEASE_INFO}}
    cat {{GKI_RELEASE_INFO}}

# 下载GKI内核
gki-kernel: gki-release
    #!/usr/bin/env bash
    set -euo pipefail
    source {{GKI_RELEASE_INFO}}
    bash {{SCRIPTS}}/ci-android-fetch.sh "$BUILD_ID" "$KERNEL_X86_64_TARGET" "bzImage" "{{GKI_BZIMAGE}}"
    bash {{SCRIPTS}}/ci-android-fetch.sh "$BUILD_ID" "$KERNEL_X86_64_TARGET" "vmlinux" "{{GKI_VMLINUX}}"
    bash {{SCRIPTS}}/ci-android-fetch.sh "$BUILD_ID" "$KERNEL_X86_64_TARGET" "boot.img" "{{GKI_X86_BOOT_IMG}}"

# 下载启动镜像
gki-boot: gki-release
    #!/usr/bin/env bash
    set -euo pipefail
    source {{GKI_RELEASE_INFO}}
    mkdir -p {{DEPS}} {{GKI_AARCH64_DIR}}
    zipfile="{{DEPS}}/$(basename "$BOOT_ZIP_URL")"
    if [ ! -f "$zipfile" ]; then
        wget -O "$zipfile" "$BOOT_ZIP_URL"
    fi
    boot_name="$(unzip -Z -1 "$zipfile" | grep -E '^boot[^/]*\.img$' | head -n1)"
    if [ -z "$boot_name" ]; then
        echo "未在 $zipfile 中找到 boot 镜像"
        exit 1
    fi
    unzip -o "$zipfile" "$boot_name" -d {{GKI_AARCH64_DIR}} >/dev/null
    if [ "$boot_name" != "boot.img" ]; then
        mv -f "{{GKI_AARCH64_DIR}}/$boot_name" "{{GKI_BOOT_IMG}}"
    fi
    test -f "{{GKI_BOOT_IMG}}"

# 准备GKI产物
gki: gki-kernel gki-boot
    @echo "GKI 内核产物已准备完毕。"

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
    set -euo pipefail
    mkdir -p {{DEPS}}
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
            7z x "{{DEPS}}/$pkg_arm64"
        elif [[ "$arch" == "x86_64" ]]; then
            if [ ! -f "{{DEPS}}/$pkg_x86_64" ]; then
                echo "$pkg_x86_64 不存在，正在下载..."
                wget -O "{{DEPS}}/$pkg_x86_64" "$url_x86_64"
            fi
            echo "解压 $pkg_x86_64"
            unzip -n -o "{{DEPS}}/$pkg_x86_64"
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
    else
        echo "cvdnetwork 用户组已存在"
    fi

    # 添加用户到相关组
    join_groups=("cvdnetwork")
    if getent group kvm &>/dev/null; then
        join_groups+=("kvm")
    fi
    if getent group render &>/dev/null; then
        join_groups+=("render")
    fi
    group_list="$(IFS=,; echo "${join_groups[*]}")"
    if id -nG "$USER" | tr ' ' '\n' | grep -qx "cvdnetwork"; then
        echo "$USER 已加入 $group_list"
    else
        sudo usermod -aG "$group_list" "$USER"
        echo "已将 $USER 加入 $group_list"
        echo "如需当前 shell 立即生效，请重新登录后再启动 CVD。"
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

# 运行本地内核
run-kernel: cvd gsi gki-kernel
    #!/usr/bin/env bash
    set -e
    cd {{CVD}} && HOME=$PWD bin/launch_cvd -report_anonymous_usage_stats=n \
        -kernel_path ../{{GKI_BZIMAGE}} \
        --daemon

# 调试本地内核
debug-kernel: cvd gsi gki-kernel
    #!/usr/bin/env bash
    set -e
    cd {{CVD}} && HOME=$PWD bin/launch_cvd -report_anonymous_usage_stats=n \
        -kernel_path ../{{GKI_BZIMAGE}} \
        -gdb_port 1234 -cpus=1 \
        -extra_kernel_cmdline nokaslr \
        --daemon

# 连接CVD内核
attach-cvd: gki-kernel
    #!/usr/bin/env bash
    set -e
    gdb {{GKI_VMLINUX}} -ex "target remote :1234" -ex "hbreak start_kernel" -ex "set pagination off" -ex "bt" -ex "continue"

# 列出连接的设备
devices:
    #!/usr/bin/env bash
    set -e
    ./{{CVD}}/bin/adb devices

# 获取设备内核信息
uname:
    #!/usr/bin/env bash
    set -e
    ./{{CVD}}/bin/adb shell uname -a

# 进入设备的shell
shell:
    #!/usr/bin/env bash
    set -e
    ./{{CVD}}/bin/adb shell

# 重启设备到bootloader模式
bootloader:
    #!/usr/bin/env bash
    set -e
    ./{{CVD}}/bin/adb reboot bootloader

# 使用fastboot命令启动指定内核镜像
boot: gki-boot
    #!/usr/bin/env bash
    set -e
    fastboot boot {{GKI_BOOT_IMG}}

# 准备全部环境
prepare-env: doctor cuttlefish cvd gsi gki
    @echo "全部环境已安装并完成本地配置。"

# 校验CI环境
ci: prepare-env
    #!/usr/bin/env bash
    set -euo pipefail
    test -f "{{CVD}}/bin/adb"
    test -f "{{CVD}}/bin/cvd"
    test -f "{{GKI_RELEASE_INFO}}"
    test -f "{{GKI_BZIMAGE}}"
    test -f "{{GKI_VMLINUX}}"
    test -f "{{GKI_X86_BOOT_IMG}}"
    test -f "{{GKI_BOOT_IMG}}"
    echo "CI 环境校验通过。"

# Frida 环境管理
# --------------------------------------------------
FRIDA_BASE_DIR := "$HOME/.frida_venvs"
PYTHON_BIN := "python3"

# 创建并安装指定版本的 Frida
frida-create version:
    #!/usr/bin/env bash
    set -e
    venv_path="{{FRIDA_BASE_DIR}}/frida-{{version}}"

    if [ -d "$venv_path" ]; then
        echo "虚拟环境 frida-{{version}} 已存在于 $venv_path"
        exit 0
    fi

    echo "创建虚拟环境 frida-{{version}} ..."
    mkdir -p "{{FRIDA_BASE_DIR}}"
    "{{PYTHON_BIN}}" -m venv "$venv_path"
    
    # 在子 shell 中激活环境以安装包
    source "$venv_path/bin/activate"

    echo "安装 frida=={{version}} ..."
    pip install --upgrade pip
    pip install frida=={{version}} frida-tools

    echo "下载 frida-server..."
    for arch in "arm64" "x86_64"; do
        server_url="https://github.com/frida/frida/releases/download/{{version}}/frida-server-{{version}}-android-$arch.xz"
        server_archive="$venv_path/frida-server-{{version}}-android-$arch.xz"
        server_binary="$venv_path/frida-server-{{version}}-android-$arch"
        final_name="$venv_path/frida-server-$arch"

        echo "正在下载 $arch 版本的 frida-server..."
        if ! curl -L "$server_url" -o "$server_archive"; then
            echo "下载失败: $server_url"
            continue
        fi

        echo "正在解压 $arch 版本的 frida-server..."
        if ! xz -d "$server_archive"; then
            echo "解压失败: $server_archive"
            rm -f "$server_archive"
            continue
        fi

        mv "$server_binary" "$final_name"
        chmod a+x "$final_name"
        echo "$arch 版本的 frida-server 已保存至 $final_name"
    done

    echo "Frida {{version}} 安装完成。虚拟环境路径：$venv_path"
    deactivate

# 显示激活 Frida 环境的命令
frida-activate version:
    #!/usr/bin/env bash
    set -e
    venv_path="{{FRIDA_BASE_DIR}}/frida-{{version}}"

    if [ ! -d "$venv_path" ]; then
        echo "未找到 frida-{{version}} 虚拟环境，请先创建："
        echo "  just frida-create {{version}}"
        exit 1
    fi

    echo "要激活 frida-{{version}} 环境，请运行以下命令："
    echo "  source $venv_path/bin/activate"

# 删除 Frida 虚拟环境
frida-delete version:
    #!/usr/bin/env bash
    set -e
    venv_path="{{FRIDA_BASE_DIR}}/frida-{{version}}"

    if [ ! -d "$venv_path" ]; then
        echo "未找到 frida-{{version}} 虚拟环境：$venv_path"
        exit 1
    fi

    read -p "确认删除 frida-{{version}} 的虚拟环境？[y/N]: " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        rm -rf "$venv_path"
        echo "已删除虚拟环境：$venv_path"
    else
        echo "取消删除操作。"
    fi

# 列出所有已创建的 Frida 虚拟环境
frida-list:
    #!/usr/bin/env bash
    set -e
    echo "已有的 frida 虚拟环境："
    for dir in {{FRIDA_BASE_DIR}}/frida-*; do \
        if [ -d "$dir" ]; then
            ver=$(basename "$dir");
            ver=${ver#frida-};
            echo "  - $ver (路径: $dir)";
        fi;
    done
