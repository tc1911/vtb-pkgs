#!/usr/bin/env bash
# 把已经构建好的 OpenVT 产物打成一个 pacman 包：open-vt-bin
#
# 为什么命令叫 open-vt 而不是 openvt：
#   /usr/bin/openvt 已被系统包 **kbd** 占用（kbd 自带的虚拟终端工具，恰好同名）。
#   装包时 pacman 报「文件系统中存在 /usr/bin/openvt （由 kbd 所有）」整批失败。
#   不能写 conflicts=('kbd') 去抢 —— 那会破坏系统控制台工具。
#   上游工程名本来就是 open-vt（project.godot 的 config/name="open-vt"），所以统一用 open-vt。
#
# 为什么是 -bin 而不是从源码编：运行时只需要 ~/项目/openvt/bin/linux 里那 5 个文件（145M）。
# 从源码编要把 AyagamiDev 的 Godot 4.7 fork 用 scons+LLVM 编一遍（小时级），而且产物一模一样。
#
# 用法: bash make_openvt_pkg.sh     → 产出 ~/vtb/归档/open-vt-bin/open-vt-bin-<ver>.pkg.tar.zst
set -euo pipefail

SRC_TREE=/home/tc191/项目/openvt
WORK=/home/tc191/vtb/归档/open-vt-bin
STAGE=/tmp/open-vt-stage

[ -x "$SRC_TREE/bin/linux/openvt.x86_64" ] || { echo "找不到构建产物: $SRC_TREE/bin/linux/"; exit 1; }

# ── 版本：上游没有 tag，用「提交数 + 短哈希」 ───────────────────────────────
CNT=$(git -C "$SRC_TREE" rev-list --count HEAD)
SHORT=$(git -C "$SRC_TREE" rev-parse --short HEAD)
V="0.1.0.r${CNT}.${SHORT}"
echo "版本: $V"

# ── 暂存：产物 + 启动器 + 桌面项 + 单元 + 图标 + 许可 ────────────────────────
rm -rf "$STAGE"; mkdir -p "$STAGE/bin"
cp -a "$SRC_TREE/bin/linux/." "$STAGE/bin/"
cp -a "$SRC_TREE/LICENSE.txt" "$STAGE/"
cp -a "$SRC_TREE/branding/icon.svg" "$STAGE/open-vt.svg"
[ -d "$SRC_TREE/license" ] && cp -a "$SRC_TREE/license" "$STAGE/license"

# 启动器：把 APP 指到安装后的位置（原来是写死的构建树路径）
cat > "$STAGE/open-vt" <<'WRAPPER'
#!/bin/bash
# OpenVT 一键启动：拉起面捕服务 → 启动应用本体 → **应用退出时把面捕一起关掉**。
#
# 注意这里不能用 exec：exec 会让应用本体顶替掉本脚本的 shell，
# 退出后收尾代码跑不到，facetracker.py 会常驻并一直占着摄像头。
# 捕获窗口大小的半配置与 keep_format 由 addon 在初始化时自己完成，这里不传参。
set -u
APP=/opt/open-vt/openvt.x86_64

# 想指定启动时载入的模型：OPENVT_MODEL=$HOME/Live2D/Natori/Natori.model3.json open-vt
# 不指定就用应用自己记住的（settings.json 的 active_model），和原先行为一致
MODEL="${OPENVT_MODEL:-}"

systemctl --user start openseeface.service >/dev/null 2>&1

if [ -n "$MODEL" ] && [ -f "$MODEL" ]; then
	"$APP" "$@" -- --model="$MODEL"
else
	"$APP" "$@"
fi
rc=$?

# 应用退出后把面捕停掉：否则 facetracker.py 会常驻并一直占着摄像头
systemctl --user stop openseeface.service >/dev/null 2>&1
exit $rc
WRAPPER
chmod 755 "$STAGE/open-vt"

# 桌面项：Exec/Icon 改成系统路径（原来 Icon 指向构建树里的 svg，删了构建树图标就没了）
cat > "$STAGE/open-vt.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=OpenVT
Name[zh_CN]=OpenVT 虚拟主播
Comment=Live2D VTuber studio (face tracking via openseeface.service)
Comment[zh_CN]=Live2D 虚拟主播工作室（面捕由 systemd 用户服务托管）
Exec=open-vt
Icon=open-vt
Terminal=false
Categories=AudioVideo;Graphics;
StartupNotify=true
StartupWMClass=open-vt
DESKTOP

cat > "$STAGE/open-vt.service" <<'UNIT'
[Unit]
Description=OpenVT 虚拟主播工作室
After=graphical-session.target
PartOf=graphical-session.target

[Service]
ExecStart=/usr/bin/open-vt
Restart=on-failure
RestartSec=5

[Install]
WantedBy=graphical-session.target
UNIT

# 面捕后端单元：ExecStart 指 /usr/bin/facetracker，也就是 openseeface-git 装出来的入口。
# 随本包安装但默认不 enable —— 由 /usr/bin/open-vt 在启动时 start、退出时 stop。
# 旗标与原先验证过的那套一致：模型 3、发到 127.0.0.1:11573、摄像头 0、1280x720 MJPG、30fps、4 线程。
cat > "$STAGE/openseeface.service" <<'FACEUNIT'
[Unit]
Description=OpenSeeFace 面捕后端（OpenVT 的摄像头数据源）
After=default.target
# 注意：重启限速的两个键属于 [Unit]，写进 [Service] 会被 systemd 忽略并报警
StartLimitIntervalSec=0

[Service]
Type=simple
ExecStart=/usr/bin/facetracker --model 3 --ip 127.0.0.1 --port 11573 -c 0 -F 30 -m 4 --dformat MJPG -W 1280 -H 720
Restart=always
RestartSec=3

[Install]
WantedBy=default.target
FACEUNIT

# ── 打包 ────────────────────────────────────────────────────────────────────
mkdir -p "$WORK"
rm -f "$WORK"/open-vt-bin-*.tar.zst "$WORK"/open-vt-bin-*.pkg.tar.zst
tar --zstd -cf "$WORK/open-vt-bin-${V}.tar.zst" -C "$STAGE" .
SUM=$(sha256sum "$WORK/open-vt-bin-${V}.tar.zst" | cut -d' ' -f1)
echo "源码包: $(du -h "$WORK/open-vt-bin-${V}.tar.zst" | cut -f1)  sha256=${SUM:0:16}…"

cat > "$WORK/PKGBUILD" <<PKGBUILD
# Maintainer: tc191
# 打包的是本地已构建产物（erodozer/open-vt 的导出件）。不重编 Godot。
pkgname=open-vt-bin
pkgver=${V}
pkgrel=2
pkgdesc="Live2D VTuber studio (Godot 4.7 fork) with face tracking via openseeface"
arch=('x86_64')
url="https://github.com/erodozer/open-vt"
license=('MIT')
# ldd 实测：主程序只链 libc/libm（其余 dlopen）；keylogger 扩展要 libinput 那一串
depends=('glibc' 'gcc-libs'
         'libx11' 'libxcursor' 'libxinerama' 'libxi' 'libxrandr' 'mesa' 'alsa-lib'
         'glib2' 'libffi' 'pcre2'
         'libevdev' 'libinput' 'systemd-libs' 'libgudev' 'libwacom' 'mtdev' 'lua54')
optdepends=('openseeface-git: 面捕后端（提供 /usr/bin/facetracker，供 openseeface.service 使用）')
options=('!strip')
source=("open-vt-bin-\${pkgver}.tar.zst")
sha256sums=('${SUM}')

prepare() {
	# makepkg 通常会自己解开 source；这里只做保险
	[ -d "\$srcdir/bin" ] || bsdtar -xf "\$srcdir/open-vt-bin-\${pkgver}.tar.zst" -C "\$srcdir"
}

package() {
	install -d "\$pkgdir/opt/open-vt" \\
	           "\$pkgdir/usr/bin" \\
	           "\$pkgdir/usr/lib/systemd/user" \\
	           "\$pkgdir/usr/share/applications" \\
	           "\$pkgdir/usr/share/icons/hicolor/scalable/apps" \\
	           "\$pkgdir/usr/share/licenses/\$pkgname"

	# 可执行 + pck + 3 个 GDExtension 必须同目录（Godot 按 <exe>.pck 找包）
	install -m755 "\$srcdir/bin/openvt.x86_64" "\$pkgdir/opt/open-vt/"
	install -m644 "\$srcdir/bin/openvt.pck" "\$pkgdir/opt/open-vt/"
	install -m755 "\$srcdir/bin/"*.so "\$pkgdir/opt/open-vt/"

	install -m755 "\$srcdir/open-vt" "\$pkgdir/usr/bin/open-vt"
	install -m644 "\$srcdir/open-vt.service" "\$pkgdir/usr/lib/systemd/user/open-vt.service"
	install -m644 "\$srcdir/openseeface.service" "\$pkgdir/usr/lib/systemd/user/openseeface.service"
	install -m644 "\$srcdir/open-vt.desktop" "\$pkgdir/usr/share/applications/open-vt.desktop"
	install -m644 "\$srcdir/open-vt.svg" "\$pkgdir/usr/share/icons/hicolor/scalable/apps/open-vt.svg"

	install -m644 "\$srcdir/LICENSE.txt" "\$pkgdir/usr/share/licenses/\$pkgname/"
	if [ -d "\$srcdir/license" ]; then
		cp -a "\$srcdir/license" "\$pkgdir/usr/share/licenses/\$pkgname/"
	fi
}
PKGBUILD

cd "$WORK"
echo
echo "=== makepkg ==="
makepkg -f --noconfirm
echo
ls -lh "$WORK"/*.pkg.tar.zst | sed 's/^/  /'
