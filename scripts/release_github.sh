#!/usr/bin/env bash
# 准备 GitHub Release 的发布资源到 dist/：
#   三个 .pkg.tar.zst + vtb.db(.tar.gz) + vtb.files(.tar.gz) + SHA256SUMS
#
# 为什么要同时放 <repo>.db 和 <repo>.db.tar.gz：
#   pacman 会先找 `<repo>.db`，找不到才回落 `<repo>.db.tar.gz`。
#   repo-add 产出的 `.db` 是**符号链接**，而 GitHub Release 存不了符号链接，
#   所以这里额外做一份真实文件副本（内容相同）。
#
# 用法: bash scripts/release_github.sh [tag]
#       默认 tag 直接用三个包的版本拼出来
set -euo pipefail

REPO=/home/tc191/vtb/仓库/vtb-pkgs
DIST="$REPO/dist"
OUT=/home/tc191/vtb/归档
OPENSEEFACE_DIR=/home/tc191/opt/openvt-pkg/openseeface

echo "== 1/5 清空 dist/ =="
rm -rf "$DIST"; mkdir -p "$DIST"

echo "== 2/5 收集包 =="
shopt -s nullglob
PKGS=()
for d in "$OUT/open-vt-bin" "$OUT/psd2live-bin" "$OPENSEEFACE_DIR"; do
	for f in "$d"/*.pkg.tar.zst; do
		install -m644 "$f" "$DIST/"
		PKGS+=("$DIST/$(basename "$f")")
		echo "  + $(basename "$f")  ($(stat -c%s "$f") 字节)"
	done
done
[ ${#PKGS[@]} -eq 3 ] || { echo "只找到 ${#PKGS[@]} 个包，应当是 3 个"; exit 1; }

echo "== 3/5 生成仓库索引 =="
cd "$DIST"
repo-add vtb.db.tar.gz ./*.pkg.tar.zst | sed 's/^/  /'
# GitHub Release 不能存符号链接 → 做成真实副本
for x in db files; do
	[ -f "vtb.$x.tar.gz" ] || { echo "  缺 vtb.$x.tar.gz"; exit 1; }
	rm -f "vtb.$x"          # repo-add 把 .db/.files 做成指向 .tar.gz 的符号链接，
	cp -f "vtb.$x.tar.gz" "vtb.$x"   # 不先删就会 cp 到自己身上（同一文件）
	echo "  vtb.$x  ← vtb.$x.tar.gz 的实体副本"
done

echo "== 4/5 校验索引与文件一致 =="
field() { bsdtar -xOf vtb.db.tar.gz "$1/desc" | sed -n "/^%$2%$/{n;p}"; }
FAIL=0
for p in ./*.pkg.tar.zst; do
	key=$(basename "$p" .pkg.tar.zst)
	key=${key%-x86_64}   # 索引里的目录名是 <name>-<ver>-<rel>，**不带架构**；而文件名带
	idx_sha=$(field "$key" SHA256SUM)
	idx_size=$(field "$key" CSIZE)
	[ -n "$idx_sha" ] || { echo "  ✗ $key 索引里没有 SHA256SUM（字段名写错？）"; FAIL=1; continue; }
	real_sha=$(sha256sum "$p" | cut -d' ' -f1)
	real_size=$(stat -c%s "$p")
	if [ "$idx_sha" = "$real_sha" ] && [ "$idx_size" = "$real_size" ]; then
		echo "  ✓ $key  $(printf '%s' "$idx_sha" | cut -c1-12)…  $idx_size 字节"
	else
		echo "  ✗ $key 索引与实际不符"; FAIL=1
	fi
done
[ "$FAIL" = 0 ] || exit 1

echo "== 4.5/5 生成 psd2live 的对应源码（GPL-3 第 6 条义务，不是可选项）=="
bash "$REPO/scripts/make_corresponding_source.sh" 2>&1 | sed 's/^/  /'

echo "== 5/5 写 SHA256SUMS =="
sha256sum ./*.pkg.tar.zst ./*-corresponding-source.tar.zst > SHA256SUMS
cat SHA256SUMS | sed 's/^/  /'

echo
echo "================ dist/ 就绪 ================"
ls -lh "$DIST" | sed 's/^/  /'
TAG="${1:-$(basename "$(echo "${PKGS[0]}" | sed 's/^.*\///')" | sed 's/-x86_64.*//')}"
echo
echo "  tag: $TAG"
echo
echo "===== 上传：路线 A（命令行，需要 github-cli + token）====="
echo "  sudo pacman -S github-cli"
if command -v gh >/dev/null; then echo "  gh 已安装"; else echo "  （gh 尚未安装）"; fi
echo "  gh auth login            # 选 GitHub.com / HTTPS / 浏览器登录"
echo "  cd $REPO"
echo "  git push -u origin main"
echo "  gh release create $TAG $DIST/* --title \"${TAG}\" --notes-file RELEASE_NOTES.md"
echo
echo "===== 上传：路线 B（网页拖拽，不需要 token）====="
echo "  1. https://github.com/tc1911/vtb-pkgs/releases/new?tag=$TAG"
echo "  2. 把 $DIST/ 里**全部**文件拖进附件区（含 vtb.db / vtb.files 的实体副本、SHA256SUMS）"
echo "  3. 发布后确认这几个 URL 都是 200："
echo "     https://github.com/tc1911/vtb-pkgs/releases/latest/download/vtb.db"
echo "     https://github.com/tc1911/vtb-pkgs/releases/latest/download/vtb.db.tar.gz"
