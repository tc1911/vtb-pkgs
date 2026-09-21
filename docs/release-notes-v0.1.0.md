# v0.1.0 — OpenVT + 面捕后端 + PSD2Live 的首个打包版

把三个上游项目打成本地 pacman 包，装完就能跑原生 Live2D VTuber。

| 包 | 上游 | 版本 | 说明 |
|---|---|---|---|
| `open-vt-bin` | [erodozer/open-vt](https://github.com/erodozer/open-vt) | `4919304` | 原生 VTuber 应用（Godot + ayagami 直接解析 moc3）。含桌面项与两个 systemd 用户单元 |
| `openseeface` | [emilianavt/OpenSeeFace](https://github.com/emilianavt/OpenSeeFace) | v1.20.5 | 面捕后端，提供 `/usr/bin/facetracker`（模型随包） |
| `psd2live-bin` | [tsunehimatoi/psd2live](https://github.com/tsunehimatoi/psd2live) | `0.7.1.r1.c8ad876` | PSD → 可绑定 Live2D 的 GUI（Compose Desktop 自带 JRE，MCP 服务监听 127.0.0.1:23871） |

## 安装

```bash
# 1) 追加到 /etc/pacman.conf 末尾
[vtb]
SigLevel = Optional TrustAll
Server = https://github.com/tc1911/vtb-bin/releases/latest/download

# 2) 整体更新（别只 -Sy）
sudo pacman -Syu

# 3) 安装
sudo pacman -S open-vt-bin openseeface psd2live-bin
```

国内直连 GitHub 不稳的话，`Server` 换成 gh-proxy 前缀即可：

```
Server = https://gh-proxy.com/https://github.com/tc1911/vtb-bin/releases/latest/download
```

`SigLevel = Optional TrustAll` 是因为这个仓库不做 gpg 签名。请只在你信任本仓库内容的前提下使用。

## 校验

每个 Release 附带 `SHA256SUMS`，覆盖全部三个 `.pkg.tar.zst` 以及对应源码归档：

```bash
cd /var/cache/pacman/pkg   # 或你下载的目录
sha256sum -c SHA256SUMS
```

## 许可与对应源码

| 上游 | 许可 | 是否修改上游 |
|---|---|---|
| open-vt | MIT（含 Godot 引擎 MIT）+ `license/` 下四个第三方许可 | 否 |
| OpenSeeFace | BSD-2（代码**与模型**）+ `Licenses/` 下 12 个第三方库许可 | 否 |
| psd2live | GPL-3.0-only | **是**，3 行 |

`psd2live-bin` 不是上游原样构建：构建时工作树相对 `c8ad876` 有 3 行改动
（`RigBuilder.kt`、`Moc3RenderOrderLowering.kt`、`gradle/wrapper/gradle-wrapper.properties`，
外加 `gradlew` 权限位），目的是让导出的 moc3 通过 OpenVT 的严格校验。

按 GPL-3 第 6 条，本 Release 同时提供**对应源码**：

```
psd2live-0.7.1.r1.c8ad876-corresponding-source.tar.zst
```

内含 `git archive c8ad876` 的完整源码树 + 覆盖上述改动后的文件 + 补丁副本 +
`README-corresponding-source.txt`（上游地址、基准提交、改动清单、重建命令）。

各包的许可证都装到 `/usr/share/licenses/<pkgname>/`。

> 本仓库不包含任何 Live2D 模型。OpenVT 上游声明它是 *"built in Godot with entirely open source
> solutions"*，未链接 Cubism SDK，因此不涉及 Live2D 的 SDK 授权条款。

## 已知坑

1. **`/usr/bin/openvt` 已被 `kbd` 包占用**（kbd 的虚拟终端工具）。所以这里的命令叫 **`open-vt`**，
   包名是 `open-vt-bin` —— 不能叫 `openvt`，否则 pacman 会以文件冲突拒绝安装整批包。
2. **先删掉用户级遮蔽**，否则装的包不生效：
   ```bash
   rm -f ~/.local/bin/openvt
   rm -f ~/.local/share/applications/openvt.desktop
   rm -f ~/.config/systemd/user/openvt.service ~/.config/systemd/user/openseeface.service
   systemctl --user daemon-reload
   ```
3. **`openseeface` 的依赖名是 `python-onnxruntime-cpu`**。官方仓库没有 `python-onnxruntime`
   （那是 AUR 包），写错会让 `pacman -U` 直接拒绝。
4. `open-vt-bin` 的 `optdepends` 指向 `openseeface-git`（AUR）。本仓库的 `openseeface` 包
   `provides`/`conflicts` 了它，两者装一个即可。

## 从源码重建

```bash
./open-vt-bin/make_openvt_pkg.sh      # 需要一份已编译的 OpenVT 构建树
./psd2live-bin/make_psd2live_pkg.sh   # 需要 psd2live 源码树 + gradle
cd openseeface && makepkg -f
./scripts/release_github.sh           # 汇总 dist/ + repo-add + 生成对应源码 + SHA256SUMS
```
