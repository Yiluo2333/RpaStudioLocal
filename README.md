# RpaStudioLocal

保留原版 RPA 的界面、嵌套流程图、项目解析器和执行引擎，为原版 `6.0.20230616.77` 添加本地入口及独立配置，提供便携 EXE 和 MSI 打包工程。

**这里包含新增入口、打包器、安装工程和验证代码的完整源码。原厂软件仅有已编译文件，未取得其源码。本仓库不能独立重建原厂编辑器。**

## 使用

- 便携版：运行构建得到的 `RpaStudioLocal.exe`。
- MSI：安装到当前 Windows 用户，创建开始菜单和桌面快捷方式；需要 .NET Framework 4.8。
- 旧项目：打开 `.proj`。迁移时必须携带整个项目文件夹，包括 `.flow`、`.script`、资源及依赖文件。
- DLL 已嵌入 EXE 的压缩包。首次运行展开到 `%LOCALAPPDATA%\RpaStudioLocal\Versions\<组件标识>`，每次启动校验并恢复缺失或损坏的静态文件。
- 卸载 MSI 保留运行配置与用户项目。更换组件包会创建新的运行目录；旧项目仍在旧目录中，升级后请从原位置打开。请勿把 Versions 目录当作普通缓存清理。

本地入口跳过登录页，停用账号、商城、在线推荐、云发布和自动更新，使用原引擎的 Offline 接口。原厂 DLL 未修改。

## 构建

在 Windows PowerShell 5.1 或 PowerShell 7 中执行：

```powershell
# 参数指向您合法持有的、版本匹配的原安装根目录
.\Build.ps1 -Original 'C:\path\to\YonyouRpaStudio'

# 如需 MSI，首次下载固定版本的官方 WiX 工具（校验 SHA256）
.\scripts\Get-Wix.ps1
.\scripts\Build-Msi.ps1

# 也可一步构建 EXE 和 MSI
.\Build.ps1 -Original 'C:\path\to\YonyouRpaStudio' -Msi
```

输出在 `artifacts`，包括 EXE、MSI、组件 SHA256 清单和体积报告。构建不修改原安装。完整步骤见 [BUILD.md](docs/BUILD.md)。

`RpaStudioLocal.sln` 可在安装 .NET Framework 4.8 Developer Pack 的 Visual Studio 中打开。Host 需设置 `VendorRoot`，Launcher 需设置 `PayloadZip`；一键脚本无需 Visual Studio，也不需要 NuGet 还原。


## 验证与限制

- `tests\Test-Launcher.ps1`：无需原厂程序，检查首次展开、参数传递、损坏恢复、保留项目文件及越界路径拒绝；公开 CI 执行此测试。
- `tests\Test-Host.ps1`：需要本地构建的私有组件包，只执行生成的注释示例及新建项目检查。
- `scripts\Diagnose.ps1`：只读检查系统、安装和已展开组件，生成不含业务文件或日志正文的诊断 JSON。
- 当前交付的测试结果与体积核算见 [VERIFICATION.md](docs/VERIFICATION.md)；`scripts\Package-Release.ps1` 生成便携 ZIP、公开源码 ZIP 和最终 SHA256 清单。
- 旧复杂项目的原始保存/重开验证见 `docs\previous-verification.json`；该报告属于 0.1 版本，不代替当前测试结果。

0.1.1 补齐 0.1 打包时漏带的浏览器插件 JS、HTML、CSS、图标、清单和安装辅助文件。保留这些资源不会自动注册扩展。原 ChromeDriver 为 114 版，浏览器自动化仍需匹配目标浏览器；Office、SAP、OCR 等也需要相应软件和合法授权。本次基础测试不代表全部外部命令已在所有电脑上验证。

MSI/EXE 当前未作代码签名。原厂组件版本升级需要重新适配反射入口并重做兼容性验证。

