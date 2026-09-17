#!/usr/bin/env bash
# 在 NAS 上建一个自建 pacman 仓库（open-vt-bin / openseeface / psd2live-bin），
# 以后能 `pacman -S` 安装、`pacman -Syu` 升级。
#
# 用法: bash vtb_repo_add.sh [包文件...]
#       不给参数就自动从三个归档目录里找所有 *.pkg.tar.zst
set -euo pipefail

REL=/mnt/nas_backup/折腾/vtb-live2d/repo
SRCDIRS=(
	/home/tc191/vtb/归档/open-vt-bin
	/home/tc191/vtb/归档/psd2live-bin
	/home/tc191/opt/openvt-pkg/openseeface
)

shopt -s nullglob
PKGS=("$@")
if [ ${#PKGS[@]} -eq 0 ]; then
	for d in "${SRCDIRS[@]}"; do
		for f in "$d"/*.pkg.tar.zst; do PKGS+=("$f"); done
	done
fi
[ ${#PKGS[@]} -gt 0 ] || { echo "三个归档目录里都没找到 .pkg.tar.zst"; exit 1; }

if ! mountpoint -q /mnt/nas_backup; then
	echo "NAS 未挂载，先触发 automount："
	ls /mnt/nas_backup >/dev/null 2>&1 || { echo "  仍然挂不上，检查网络/凭据"; exit 1; }
fi

mkdir -p "$REL"
echo "== 放入仓库 =="
for f in "${PKGS[@]}"; do
	install -m644 "$f" "$REL/"
	echo "  $(basename "$f")  ($(du -h "$f" | cut -f1))"
done

cd "$REL"
echo
echo "== repo-add =="
# 每次都用当前目录下所有包重建索引，保证旧版本条目不会丢
rm -f vtb.db.tar.gz vtb.files.tar.gz vtb.db vtb.files
repo-add vtb.db.tar.gz ./*.pkg.tar.zst | sed 's/^/  /'

echo
echo "===== 仓库就绪 ====="
ls -lh "$REL"/vtb.db* 2>/dev/null | sed 's/^/  /'
echo "  包总数: $(ls -1 "$REL"/*.pkg.tar.zst 2>/dev/null | wc -l)"
echo
echo "===== 本机接入（要 root，自己跑这三段）====="
echo
echo "  # 1) 追加到 /etc/pacman.conf 末尾"
echo "  [vtb]"
echo "  SigLevel = Optional TrustAll"
echo "  Server = file:///mnt/nas_backup/折腾/vtb-live2d/repo"
echo
echo "  # 2) 整体更新（别只 -Sy）"
echo "  sudo pacman -Syu"
echo
echo "  # 3) 安装"
echo "  sudo pacman -S open-vt-bin openseeface psd2live-bin"
echo
echo "  说明: SigLevel Optional TrustAll 是因为仓库没做 gpg 签名，自己 NAS 上可接受；"
echo "        要给公开分发用，应当 gpg --detach-sign 后 repo-add -s -k <key> 重建。"
