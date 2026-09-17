# vtb-pkgs

把 **OpenVT**（原生的 Live2D 运行时）、**openseeface**（摄像头面捕后端）、**psd2live**（PSD → 绑定模型的 GUI）
做成 Arch Linux 的 pacman 包。

没有 `-git` 源码烘焙版：OpenVT 依赖 Godot 4.7 的 AyagamiDev 分支（scons + LLVM 要跑几个小时，
产出的二进制与上游一致），psd2live 的 Compose Desktop 构建同理。这里是 `-bin` 包 ——
把**上游产出的二进制**整理成符合 FHS 的包结构 + systemd 单元 + 桌面项。

## 安装

### 方式 A：pacman 仓库（可以 `pacman -S` / `-Syu` 升级）

把下面三行追加到 `/etc/pacman.conf` 末尾：

```ini
[vtb]
SigLevel = Optional TrustAll
Server = https://github.com/tc1911/vtb-pkgs/releases/latest/download
```

> 没做 gpg 签名，所以是 `Optional TrustAll`。介意的话可以自己拿 `SHA256SUMS` 校验。
>
> 国内直连 GitHub 不通时，把 `Server` 换成代理前缀（`gh-proxy.com` 实测能代理 release 资源）：
>
> ```ini
> Server = https://gh-proxy.com/https://github.com/tc1911/vtb-pkgs/releases/latest/download
> ```

然后：

```bash
sudo pacman -Syu                     # 别只 -Sy，会变成部分升级
sudo pacman -S open-vt-bin openseeface psd2live-bin
```

依赖会拉 19 个包（opencv 顺带带上 vtk/scipy 等），下载约 135 MiB，装好后约 1.1 GiB。

### 方式 B：本地文件

```bash
sudo pacman -U open-vt-bin-*.pkg.tar.zst openseeface-*.pkg.tar.zst psd2live-bin-*.pkg.tar.zst
```

升级时 `pacman -U` 新包即可，不做降级处理。

### 装完必须清掉用户级的旧文件

包会装到 `/usr` 和 `/opt`，但下面这些**用户级**文件优先级更高，留着会盖掉包的版本：

| 文件 | 不清的后果 |
|---|---|
| `~/.local/bin/openvt` | PATH 里 `~/.local/bin` 在 `/usr/bin` 前面，`openvt` 仍走旧包装脚本 |
| `~/.local/share/applications/openvt.desktop` | 应用菜单里那个图标仍指向旧路径（构建树删掉后就打不开了） |
| `~/.config/systemd/user/openvt.service` | 用户单元压过 `/usr/lib/systemd/user/openvt.service` |
| `~/.config/systemd/user/openseeface.service` | 同上，且 `ExecStart` 还指着 `~/.venv/bin/python` —— 那个目录一删，面捕就静默失效 |

```bash
rm -f ~/.local/bin/openvt \
      ~/.local/share/applications/openvt.desktop \
      ~/.config/systemd/user/openvt.service \
      ~/.config/systemd/user/openseeface.service
systemctl --user daemon-reload
```

## 包内容

| 包 | 版本 | 字节数 | 安装大小 | 许可证 |
|---|---|---|---|---|
| `open-vt-bin` | 0.1.0.r1.4919304-2 | 69,192,281 | 148 MiB | MIT |
| `openseeface` | 1.20.5-1 | 74,645,736 | 78 MiB | BSD-2 |
| `psd2live-bin` | 0.7.1.r1.c8ad876-1 | 90,769,067 | 172 MiB | GPL-3.0-only |

`SHA256SUMS`：

```
fe58bbae22230af467524af00194b32281368a7830e44a6e3f96c2fb86190a55  open-vt-bin-0.1.0.r1.4919304-2-x86_64.pkg.tar.zst
8d0db4662b95bb400dbd423133926272e2f11d72731789b046510dcbec4a0dab  openseeface-1.20.5-1-x86_64.pkg.tar.zst
4b55dd9d100d09c9abb13ab19e1ad7adf8e72b478aea8b13726b05d0685cd89a  psd2live-bin-0.7.1.r1.c8ad876-1-x86_64.pkg.tar.zst
```

### open-vt-bin

- `/opt/open-vt/openvt.x86_64`（97M，Godot 导出模板）+ `openvt.pck` + 三个 `.so`（ayagami / keylogger / virtualcamera）
- `/usr/bin/open-vt` —— 包装脚本：起 `openseeface.service` → 跑应用 → 停下服务。这样应用退出后面捕不会残留占摄像头
- `/usr/share/applications/open-vt.desktop`、`/usr/lib/systemd/user/open-vt.service`（`Restart=on-failure`）
- 环境变量 `OPENVT_MODEL=/path/to/foo.model3.json` 可以指定模型；不设则用设置里上次的
- 依赖：`glibc gcc-libs libx11 libxcursor libxinerama libxi libxrandr mesa alsa-lib glib2 libffi pcre2 libevdev libinput systemd-libs libgudev libwacom mtdev lua54`
- 可选依赖：`openseeface`（提供 `/usr/bin/facetracker`）

### openseeface

- `/usr/lib/python3.x/site-packages/openseeface/`（含 `models/`，78M 的 ONNX 模型）
- `/usr/bin/facetracker` —— `import openseeface.facetracker` 的包装
- `provides`/`conflicts` = `openseeface-git`（AUR 那个）

### psd2live-bin

- `/opt/psd2live/{bin,lib}/` —— Compose Desktop `createDistributable` 产出的 app image（自带 88M 的 jRE 运行时）
- `/usr/bin/psd2live` —— **绝对路径**包装脚本（`jpackage` 按 `argv[0]` 的所在目录找 `lib/`，符号链接会找不到）
- 无参数启动 = GUI + MCP 服务（`http://127.0.0.1:23871/mcp`，token 在 `~/.config/psd2live/`）
- 可选依赖：`hicolor-icon-theme`

## 踩过的坑

1. **`/usr/bin/openvt` 已经被 `kbd` 占了。** `kbd` 是 base 组的控制台工具集，里面有同名的 `openvt`（打开虚拟终端）。
   包装成 `openvt-bin` 会在"检查文件冲突"阶段整批失败，而 `conflicts=('kbd')` 是不能接受的。
   上游工程名本来就叫 `open-vt`，所以统一改成 `/usr/bin/open-vt`、`open-vt.desktop`、`open-vt.svg`、`open-vt.service`。
   内部可执行文件仍叫 `openvt.x86_64`（构建产物原名，不冲突）。

2. **检查文件冲突时不要查目录。** `pacman -Qoq /usr/share/applications/` 会列出所有子文件的属主（几百行），
   而共享目录在 pacman 里本来就合法。只查**文件**路径。`pacman -Qlp` 输出是两列，用 `awk '{print $2}'`。

3. **`python-onnxruntime` 是 AUR 包。** 官方仓库里只有 `python-onnxruntime-cpu`。
   写错名字 `pacman -U` 会直接以依赖不满足拒绝。

4. **`pgrep -f <子串>` 会匹配到调用者自己。** 验证脚本里查面捕进程时，
   `pgrep -f '/usr/bin/facetracker'` 匹配到了那条包含该字符串的 shell 命令行本身，导致误报。
   要写 `pgrep -f '^python .*/usr/bin/facetracker'`。

5. **验证"包是否自包含"必须把构建树藏起来。** 什么都不做时应用照样能跑，因为
   `~/项目/openvt` 还在。`openvt_pkg_verify.sh` 的做法是把构建树改名，
   跑一次完整流程（启动 → 聚焦 → 抓帧 → 查面捕 → 收摊），退出时再还原。

6. **抓帧要排在杀进程之前。** 顺序写反会得到"0 帧"，然后被误判成"包依赖构建树"——
   其实只是应用已经被杀了。

7. **pacman 仓库索引的字段是 `%NAME%` 形式的行，不是 `KEY=VALUE`。**
   用 `awk -F'= '` 取字段会两边都取到空串，`[ "" = "" ]` 成立 → 校验**假通过**。
   正确写法：

   ```bash
   field() { bsdtar -xOf vtb.db.tar.gz "$1/desc" | sed -n "/^%$2%$/{n;p}"; }
   field open-vt-bin-0.1.0.r1.4919304-2 SHA256SUM
   ```

   凡是对比两个值是否相等的地方，先确认它们非空。

8. **`openseeface` 的 `facetracker.py` 是 460 行扁平顶层代码**，没有 `main()`、没有 `__main__` 守卫。
   所以 `import openseeface.facetracker` 就会真的开始追踪（命令行参数从 `sys.argv` 读）——
   AUR 那份装的 `/usr/bin/facetracker` 就是这个形式，能用。

9. **分发 `openseeface` 必须带上 `Licenses/` 目录。** 上游 README 第 132 行写明
   *"When distributing it, you should also distribute the `Licenses` folder"* ——
   里面是 12 个第三方库的许可。漏了它程序照跑，但就不算合规分发。

10. **`psd2live` 是 GPL-3，而这里的构建带 3 行改动。** 分发它的二进制时
    必须一并给出对应源码，详见上面「来源与许可」小节 —— 这不是可选项。

## 从源码重建

```bash
# open-vt-bin：需要一个已经编译好的 OpenVT 构建树（bin/linux/ 下有 5 个产物）
bash open-vt-bin/make_openvt_pkg.sh

# psd2live-bin：需要源码 + JDK 21 + gradle（脚本内用 ./gradlew createDistributable）
bash psd2live-bin/make_psd2live_pkg.sh

# openseeface：需要一份 OpenSeeFace 源码树（*.py + models/）
cd openseeface && makepkg -f
```

三个脚本都在本机验证过。`open-vt-bin` 用 `git rev-list --count HEAD` 拼版本号，
浅克隆会得到 `.r1`（上游仓库没有 tag）。

## 验证记录

- `open-vt-bin`：把 7.5G 的构建树改名藏起后，用装好的 `/usr/bin/open-vt` 跑通完整流程 ——
  窗口正常创建、24 帧抓取成功、非黑像素 15.1%、面捕 `/usr/bin/facetracker` 起来了、
  应用退出后 `facetracker` 也随之结束、日志无报错。
- `psd2live-bin`：装机后无参数启动，`/mcp` 端点返回 HTTP 200，
  `serverInfo` = `psd2live 0.7.1`。
- `openseeface`：用 `--model 3 --dformat MJPG` 起，日志 `Took 5.50ms`，正常出帧。
- NAS 仓库与 GitHub Release 上的三个包，`SHA256SUM` 与 `CSIZE` 均与 `vtb.db` 索引一致。

## 来源与许可

| 上游 | 版本/提交 | 许可 | 是否修改上游 |
|---|---|---|---|
| [erodozer/open-vt](https://github.com/erodozer/open-vt) | `4919304` | MIT（含 Godot 引擎 MIT） | 否 |
| [emilianavt/OpenSeeFace](https://github.com/emilianavt/OpenSeeFace) | v1.20.5 | BSD-2（代码**与模型**） | 否 |
| [tsunehimatoi/psd2live](https://github.com/tsunehimatoi/psd2live) | `c8ad876` | GPL-3.0-only | **是**，3 行，见下 |

许可证文件都装到 `/usr/share/licenses/<pkgname>/`：

- `open-vt-bin` —— MIT 全文 + 上游 `license/` 下全部四个第三方许可（ayagami / gdvirtualcamera / godotvrm / keylogger）
- `openseeface` —— BSD-2 全文 + `Licenses/` 下 **12** 个第三方库许可（onnxruntime / OpenCV /
  Pytorch_Retinaface / libsvm / scikit-image / ThunderSVM …）。
  上游 README 明确要求：**分发本程序时要一并分发 `Licenses/` 目录**。
- `psd2live-bin` —— GPL-3.0 全文

### psd2live 的 GPL-3 源码义务

`psd2live-bin` **不是上游原样构建**。构建时的工作树相对 `c8ad876` 有 3 行改动
（`src/main/kotlin/io/github/psd2live/core/RigBuilder.kt`、
`src/main/kotlin/org/umamo/interop/moc3/export/Moc3RenderOrderLowering.kt`、
`gradle/wrapper/gradle-wrapper.properties`）以及 `gradlew` 的权限位变化 ——
目的是让导出的 moc3 能通过 OpenVT 的严格校验。

按 GPL-3 第 6 条，分发该二进制必须同时提供**对应源码**（只给上游链接不满足）。
所以每个 Release 都附一个：

```
psd2live-0.7.1.r1.c8ad876-corresponding-source.tar.zst
```

内含 `git archive c8ad876` 的完整源码树 + 覆盖上述改动后的文件 + 补丁副本 +
`README-corresponding-source.txt`（写明上游地址、基准提交、改动清单和重建方式）。
由 `scripts/make_corresponding_source.sh` 生成，`scripts/release_github.sh` 每次自动重建。

### Live2D / Cubism

OpenVT 上游明确写着它是 *"built in Godot with entirely open source solutions"*，
没有链接 Cubism SDK；moc3 的读取由 ayagami 自己实现。因此本仓库不涉及 Live2D 的 SDK 授权条款，
也不分发任何 Live2D 模型。
