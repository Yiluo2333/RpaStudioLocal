# 构建工程

## 环境

- Windows，.NET Framework 4.8，PowerShell 5.1 或更新。
- `Build.ps1` 使用系统 Framework 目录下的 C# 编译器，生成 x86 程序，以匹配原组件和 SQLite 原生库。
- MSI 使用固定的 WiX 3.14.1。`scripts/Get-Wix.ps1` 从 WiX 官方 GitHub Release 下载，并校验固定 SHA256。已有工具可用 `-WixDirectory` 指定。
- Visual Studio 工程目标为 .NET Framework 4.8，需要对应 Developer Pack；这项要求不影响系统编译器构建脚本。
- 原安装必须为 `6.0.20230616.77`。没有原安装时只能构建和测试独立启动器，不能生成完整应用。

## 完整构建与验证

```powershell
.\Build.ps1 -Original 'C:\path\to\YonyouRpaStudio'
.\tests\Test-Launcher.ps1
.\tests\Test-Host.ps1
.\scripts\Get-Wix.ps1
.\scripts\Build-Msi.ps1
.\tests\Test-Msi.ps1
.\scripts\Export-Source.ps1
.\scripts\Package-Release.ps1
```

每次完整构建在新的 `build/<GUID>/payload` 中进行，避免旧配置和测试输出混入。私有构建目录及所有产物都被 `.gitignore` 排除。`artifacts/build-location.txt` 指向最后一次私有构建目录，仅供本机验证使用，不属于公开源代码。

打包范围包括 net461、CommandLibs、Plugins、Languages、Resource、ThirdPart、Version 的静态组件。插件资源的扩展名清单单独声明，避免漏带 JS/HTML 等文件。排除原账号数据库、业务项目、PDB、日志、旧补丁包、NuGet 安装缓存和更新器。所有纳入的原 DLL 都与来源逐项比较 SHA256；任一 DLL 改变或命令库 DLL 缺失会使构建失败。

## Visual Studio / MSBuild

```powershell
msbuild .\src\Host\Host.csproj /p:Configuration=Release /p:VendorRoot='C:\path\to\YonyouRpaStudio'
msbuild .\src\Launcher\Launcher.csproj /p:Configuration=Release /p:PayloadZip='D:\path\to\build\GUID\runtime.zip'
```

Launcher 的 `runtime.zip` 由完整构建脚本生成，内含已编译 Host。只重新编译 IDE 中的 Launcher 不会自动重打包 Host；发布时始终运行根目录的 `Build.ps1`。

## 安装包

MSI 为当前用户安装，不请求管理员权限，不安装服务，不注册浏览器插件，不关联旧 `.proj` 扩展名。默认位置是 `%LOCALAPPDATA%\Programs\RpaStudioLocal`，支持标准修复、卸载和 Major Upgrade。固定 UpgradeCode 用于后续升级，不应随意更换；每次正式升级应提升 `VERSION` 与 `src/Shared/AssemblyInfo.cs` 中的文件版本。

运行数据另存于 `%LOCALAPPDATA%\RpaStudioLocal`，MSI 不拥有其中的业务文件，也不会在卸载时删除它们。组件包不同会产生不同运行目录，旧配置不会自动迁移到新目录。用户可从旧位置打开原项目，迁移配置需要后续单独设计，不能直接删除旧版本目录。

构建会执行 WiX 的 MSI 校验。可在测试账户或隔离安装目录中用 `msiexec /i <包> /qn /l*v <日志>` 安装，用 `/x` 卸载。不要对用户日常使用的安装执行自动卸载测试。

`tests/Test-Msi.ps1` 会在 build 下的临时目录执行真实安装、修复和卸载；检测到已有本地版安装或快捷方式时拒绝运行。它会短暂创建当前用户的快捷方式，请在测试账户中使用。
