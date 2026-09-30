# 插件 ZIP 打包与回归

在仓库根目录使用 PowerShell 和本机 Godot 4.8 编辑器：

```powershell
./tools/package.ps1 -Godot 'C:\path\Godot_v4.8-dev4_win64_console.exe'
```

默认输出 `dist/visual_inventory-0.5-host-feature-fix.zip`，可用 `-Output` 指定新路径。输出已存在时拒绝覆盖，仓库原有的 `addons.zip` 不会修改。生成物不提交到 Git；提交源码后可以重建。新插件文件需要先 `git add`，打包只收集 Git 跟踪的 `addons/visual_inventory/` 文件，使用工作区当前内容。请在发布前核对工作区，避免打入其他未提交插件修改。

ZIP 使用固定时间戳、排序后的路径，保留标准 `addons/visual_inventory/...` 结构以及资源 UID/导入描述；不包含 `.git`、`.godot`、测试夹具、凭证或仓库其他内容。文件类型白名单阻止意外文件进入包。ZIP 无须空目录：Host 功能扫描仅允许可选的 `gdbase/integration/component_inventory` 缺失；必需根目录、非目录占位和无效适配器仍会报告错误。

每次打包都会将候选 ZIP 解压到新建的系统临时目录，以真正启用插件的 Godot 编辑器进行导入与自动化验证，只有通过才复制到输出路径。也可独立验证已有包：

```powershell
./tools/test-package.ps1 -Zip './dist/visual_inventory-0.5-host-feature-fix.zip' -Godot 'C:\path\Godot_v4.8-dev4_win64_console.exe'
```

验证需要编辑器正常访问用户配置、缓存和系统证书。在限制环境下应使用经授权的正常执行环境，不能忽略相关错误。输出会提供临时工程位置，保留导入/测试日志及 `applied_host.tres` 供检查；不会清理用户文件。

自动化验证范围：插件启用与输入注册；可选目录缺失、空目录、安装扩展时递归发现；内置目录扫描结果一致；无效适配器、文件占位和缺失必需根目录仍阻止添加；真实 Host 编辑器控件添加“反应效果”、修改延迟、应用、保存重载、撤销与重做。测试运行于无界面编辑器，通过控件信号触发操作，不包含人工鼠标或视觉验收。
