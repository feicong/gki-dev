#!/usr/bin/env bash
# Copyright (c) 2025-2026 fei_cong(https://github.com/feicong/feicong-course)

set -euo pipefail

if [[ $# -ne 4 ]]; then
	echo "用法: $0 <build-id> <target> <artifact> <output>" >&2
	exit 1
fi

build_id="$1"
target="$2"
artifact="$3"
output="$4"
viewer_url="https://ci.android.com/builds/submitted/${build_id}/${target}/latest/${artifact}"

if [[ -s "$output" && "${FORCE_DOWNLOAD:-0}" != "1" ]]; then
	echo "已存在，跳过下载: $output"
	exit 0
fi

page_file="$(mktemp)"
tmp_file="${output}.tmp"

cleanup() {
	rm -f "$page_file" "$tmp_file"
}
trap cleanup EXIT

curl -fsSL "$viewer_url" -o "$page_file"

artifact_url="$(
	sed -n 's/.*"artifactUrl":"\([^"]*\)".*/\1/p' "$page_file" \
		| sed 's/\\u0026/\&/g' \
		| head -n1
)"

if [[ -z "${artifact_url}" ]]; then
	echo "未能解析artifact下载地址: ${viewer_url}" >&2
	exit 1
fi

mkdir -p "$(dirname "$output")"
curl -fL "$artifact_url" -o "$tmp_file"
mv -f "$tmp_file" "$output"
echo "已下载: $output"
