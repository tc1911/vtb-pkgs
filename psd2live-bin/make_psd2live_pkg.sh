#!/usr/bin/env bash
# 把 psd2live 的 Compose Desktop app image 打成 pacman 包 psd2live-bin。
#
# 为什么这么打：
#   - app image 自带 88M JRE（lib/runtime）→ 不需要 java 运行时依赖，也不需要 gradle 或源码目录
#   - MCP 服务（ktor-server-*，127.0.0.1:23871）在打包版里**已实测可用**（initialize → HTTP 200）
#   - jpackage 启动器按 argv[0] 所在目录定位 lib/，所以 /usr/bin/psd2live 必须是包装脚本给绝对路径，
#     不能做符号链接（符号链接会让它去 /usr/lib 找，直接起不来）
set -euo pipefail

SRC=/home/tc191/opt/probe-psd2live/psd2live
APP="$SRC/build/compose/binaries/main/app/PSD2Live"
OUT=/home/tc191/vtb/归档/psd2live-bin
STAGE=/tmp/psd2live-stage
V=0.7.1

if [ ! -x "$APP/bin/PSD2Live" ]; then
	echo "缺少 app image。先跑："
	echo "  cd $SRC && JAVA_HOME=/usr/lib/jvm/zulu-21 ./gradlew --no-daemon createDistributable"
	exit 1
fi

CNT=$(git -C "$SRC" rev-list --count HEAD 2>/dev/null || echo 1)
COMMIT=$(git -C "$SRC" rev-parse --short HEAD 2>/dev/null || echo unknown)
PKGVER="$V.r$CNT.$COMMIT"
echo "== 版本: $PKGVER  (commit $COMMIT) =="

echo "== 1/4 暂存到 $STAGE =="
rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -a "$APP/bin" "$APP/lib" "$STAGE/"
install -m644 "$SRC/LICENSE" "$STAGE/LICENSE"

# jpackage 启动器靠 argv[0] 的目录找 lib/，所以必须是绝对路径的包装脚本
cat > "$STAGE/psd2live" <<'WRAP'
#!/bin/sh
exec /opt/psd2live/bin/PSD2Live "$@"
WRAP
chmod 755 "$STAGE/psd2live"

cat > "$STAGE/psd2live.desktop" <<'DESK'
[Desktop Entry]
Type=Application
Name=PSD2Live
Comment=PSD 到 Live2D 的绑定工作台（内置 MCP 服务）
Exec=psd2live
Icon=psd2live
Terminal=false
Categories=Graphics;
StartupWMClass=PSD2Live
DESK

echo "  暂存大小: $(du -sh "$STAGE" | cut -f1)"

echo "== 2/4 打源 tar.zst =="
mkdir -p "$OUT"
rm -f "$OUT/psd2live-$PKGVER.tar.zst"
tar -C "$STAGE" --zstd -cf "$OUT/psd2live-$PKGVER.tar.zst" .
SUM=$(sha256sum "$OUT/psd2live-$PKGVER.tar.zst" | cut -d' ' -f1)
echo "  源包 $(du -h "$OUT/psd2live-$PKGVER.tar.zst" | cut -f1)  sha256=$SUM"

echo "== 3/4 写 PKGBUILD =="
P=/tmp/psd2live-pkgbuild; rm -rf "$P"; mkdir -p "$P"
cp "$OUT/psd2live-$PKGVER.tar.zst" "$P/"
cat > "$P/PKGBUILD" <<PKGBUILD
# 由 /home/tc191/opt/make_psd2live_pkg.sh 生成
pkgname=psd2live-bin
pkgver=$PKGVER
pkgrel=1
pkgdesc='PSD 到 Live2D 的绑定工作台（Compose Desktop app image，自带 JRE，内置 MCP 服务）'
arch=('x86_64')
url='https://github.com/tsunehimatoi/psd2live'
license=('GPL-3.0-only')
# 直接依赖取自 libskiko-linux-x64.so / libawt_xawt.so / libfontmanager.so 的 ldd 结果。
# 不依赖 java：lib/runtime 里自带 88M JRE。
depends=('glibc' 'gcc-libs' 'libx11' 'libxext' 'libxi' 'libxrender' 'libxtst' 'libglvnd' 'fontconfig' 'freetype2')
optdepends=('hicolor-icon-theme: 桌面图标')
options=('!strip')
source=("psd2live-$PKGVER.tar.zst")
sha256sums=('$SUM')

prepare() {
	# 源包是 GNU tar 打的（--zstd），makepkg 默认不认，自己解
	bsdtar -xf "\$srcdir/psd2live-$PKGVER.tar.zst" -C "\$srcdir"
}

package() {
	install -dm755 "\$pkgdir/opt/psd2live"
	cp -a "\$srcdir/bin" "\$srcdir/lib" "\$pkgdir/opt/psd2live/"
	install -Dm755 "\$srcdir/psd2live" "\$pkgdir/usr/bin/psd2live"
	install -Dm644 "\$srcdir/psd2live.desktop" "\$pkgdir/usr/share/applications/psd2live.desktop"
	install -Dm644 "\$srcdir/lib/PSD2Live.png" "\$pkgdir/usr/share/icons/hicolor/1024x1024/apps/psd2live.png"
	install -Dm644 "\$srcdir/LICENSE" "\$pkgdir/usr/share/licenses/psd2live-bin/LICENSE"
}
PKGBUILD

echo "== 4/4 makepkg =="
cd "$P"
makepkg -f --nodeps
ls -lh "$P"/*.pkg.tar.zst | sed 's/^/  /'

# /tmp 是 tmpfs，重启就没了 —— 成品包也拷进归档目录
cp -f "$P"/*.pkg.tar.zst "$OUT/"
echo "  成品包已拷到归档目录"
echo
echo "产物目录: $P"
echo "归档副本: $OUT"
