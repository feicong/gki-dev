#!/usr/bin/env bash
# Copyright (c) 2025-2026 fei_cong(https://github.com/feicong/feicong-course)

set -euo pipefail

android_version="${1:-android13}"
kernel_version="${2:-5.15}"
kernel_slug="${kernel_version//./_}"
release_url="https://source.android.com/docs/core/architecture/kernel/gki-${android_version}-${kernel_slug}-release-builds"

page_file="$(mktemp)"
section_file="$(mktemp)"

cleanup() {
	rm -f "$page_file" "$section_file"
}
trap cleanup EXIT

curl -fsSL "$release_url" -o "$page_file"

kernel_regex="${kernel_version//./\\.}"
branch_regex="${android_version}-${kernel_regex}-[0-9]{4}-[0-9]{2}"
start_line="$(
	grep -n -m1 -E "Branch: .*${android_version}-${kernel_regex}-" "$page_file" | cut -d: -f1 || true
)"

if [[ -z "${start_line}" ]]; then
	echo "未能在发布页中定位最新GKI分支: ${release_url}" >&2
	exit 1
fi

end_line="$(
	awk -v start="$start_line" 'NR > start && /<h3 id=/{print NR; exit}' "$page_file"
)"

if [[ -z "${end_line}" ]]; then
	end_line="$(wc -l < "$page_file")"
fi

sed -n "${start_line},$((end_line - 1))p" "$page_file" > "$section_file"

branch_name="$(
	grep -Eo "$branch_regex" "$section_file" | head -n1 || true
)"
build_id="$(
	grep -o 'https://ci\.android\.com/builds/submitted/[0-9]\+/kernel_aarch64/latest' "$section_file" \
		| awk -F/ '{print $(NF-2)}' \
		| tail -n1 || true
)"
debug_build_id="$(
	grep -o 'https://ci\.android\.com/builds/submitted/[0-9]\+/kernel_debug_aarch64/latest' "$section_file" \
		| awk -F/ '{print $(NF-2)}' \
		| tail -n1 || true
)"
boot_zip_url="$(
	grep -o 'https://dl\.google\.com/android/gki/gki-certified-boot-[^"]*\.zip' "$section_file" \
		| grep -Ev '(-gz|-lz4)\.zip$' \
		| tail -n1 || true
)"
boot_gz_zip_url="$(
	grep -o 'https://dl\.google\.com/android/gki/gki-certified-boot-[^"]*-gz\.zip' "$section_file" \
		| tail -n1 || true
)"
boot_lz4_zip_url="$(
	grep -o 'https://dl\.google\.com/android/gki/gki-certified-boot-[^"]*-lz4\.zip' "$section_file" \
		| tail -n1 || true
)"

if [[ -z "${branch_name}" || -z "${build_id}" || -z "${boot_zip_url}" ]]; then
	echo "未能从发布页解析最新GKI信息: ${release_url}" >&2
	exit 1
fi

tag_name="$(basename "$boot_zip_url" .zip)"
tag_name="${tag_name#gki-certified-boot-}"

printf 'RELEASE_URL=%q\n' "$release_url"
printf 'BRANCH_NAME=%q\n' "$branch_name"
printf 'TAG_NAME=%q\n' "$tag_name"
printf 'BUILD_ID=%q\n' "$build_id"
printf 'DEBUG_BUILD_ID=%q\n' "${debug_build_id:-$build_id}"
printf 'KERNEL_AARCH64_TARGET=%q\n' "kernel_aarch64"
printf 'KERNEL_DEBUG_AARCH64_TARGET=%q\n' "kernel_debug_aarch64"
printf 'KERNEL_X86_64_TARGET=%q\n' "kernel_x86_64"
printf 'BOOT_ZIP_URL=%q\n' "$boot_zip_url"
printf 'BOOT_GZ_ZIP_URL=%q\n' "$boot_gz_zip_url"
printf 'BOOT_LZ4_ZIP_URL=%q\n' "$boot_lz4_zip_url"
