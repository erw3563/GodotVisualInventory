# Visual Inventory
README由AI生成

面向 Godot 4.8 的可视化库存插件。它同时提供可在编辑器中配置的物品、库存与界面资源，以及运行时的物品放置、拾取、旋转、堆叠和转移能力。

当前插件版本：**0.5**（见 `addons/visual_inventory/plugin.cfg`）。仓库自带演示项目；实际集成时只需复制 `addons/visual_inventory` 整个目录。

## 功能概览

- **最高集成节点**：高度集成，在InventoryHost一个节点全可完成从零创建一个背包的所有工作。
- **可视化编辑**：在 Inspector 中提供编辑 `ItemData`、`InventoryData`、`InventoryHostDefinition`的可视化面板，并编辑 `Shape` 和 `OccupyMap` 的格子面板。
- **多种布局**：提供网格、目录和环绕布局的 Host 预设。界面布局与可用功能分开配置。
- **物品数据**：物品模板可设置名称、图标、描述、最大堆叠数和可组合的 Part；物品实例保存数量、方向及实例状态。
- **库存操作**：支持放置、移动、拾取、旋转、合并、拆分数量与库存间转移。操作经过规划、规则裁决和提交，结果包含成功状态及失败原因。
- **可选扩展**：目录中还包含嵌套库存、标签、计数、反应、动画与商店相关的 Part、Feature 和运行时实现。按项目需要配置相应资源和依赖。

## 安装

1. 使用 **Godot 4.8** 打开你的项目。本仓库的 `project.godot` 声明了 4.8；其他 Godot 版本尚未在本仓库中证明兼容。
2. 将仓库的 `addons/visual_inventory/` **完整复制**到目标项目的 `res://addons/visual_inventory/`。保留目录结构和其中的资源、场景、图片与脚本。
3. 在 **项目 > 项目设置 > 插件** 中启用 `VisualInventory`。启用时会自动调用 `InventoryInputMapSetup.ensure_bindings()`，把下表动作写入 **项目设置 > 输入映射**（已有绑定不会被覆盖）。也可在 **工具 > 注册库存输入映射** 手动再跑一次；运行时脚本可调用同一 API。

| 输入动作 | 默认输入 |
| --- | --- |
| `inventory_primary` | 鼠标左键 |
| `inventory_primary_single` | Ctrl + 鼠标左键 |
| `inventory_quick_transfer` | Shift + 鼠标左键 |
| `inventory_quick_transfer_single` | Ctrl + Shift + 鼠标左键 |
| `inventory_rotate` | 鼠标右键 |
| `inventory_open` | 鼠标中键 |
| `inventory_describe` | R |

输入动作由 Host 中配置的 Feature 使用；没有配置对应 Feature 时，添加输入映射本身不会启用该行为。

## 先运行演示

克隆本仓库后用 Godot 4.8 打开根目录，运行项目即可进入 `addons/visual_inventory/visual_inventory_dome.tscn`。演示场景把同一份 `visual_inventory_dome_inventory.tres` 显示在网格、目录和环绕布局的 Host 中，适合先观察不同布局及输入行为。

要尝试编辑器：

1. 在文件系统中选中 `addons/visual_inventory/visual_inventory_dome_inventory.tres`，在 Inspector 顶部使用可视化库存编辑器，修改后保存资源。
2. 选中 `addons/visual_inventory/gdbase/inventory/presets/item/` 下的一个物品资源，点击 Inspector 中的 **打开物品创建器**。也可以从编辑器的 **工具 > 新建物品** 开始。
3. 选中 `addons/visual_inventory/gdbase/inventory/presets/host/grid_inventory_host.tres`，点击 **打开可视化编辑器**，查看布局与功能配置；修改后点击 **应用**。

演示资源也是可编辑数据。希望保留原始示例时，先复制对应 `.tres` 再修改。

## 在自己的场景中使用

插件的主要资源与节点关系如下：

| 类型 | 作用 |
| --- | --- |
| `ItemData` | 定义一种物品的固定数据及 Part |
| `ItemInstanceData` | 表示一件或一堆实际物品及其实例状态 |
| `InventoryData` | 保存库存占格与物品实例，提供操作接口 |
| `InventoryHostDefinition` | 组合一个布局 `layout` 和一组功能 `features` |
| `InventoryHost` | 场景中的 `Control` 节点，绑定库存与定义并装配界面、输入和功能 |

最直接的集成方式是复制演示场景中的一个 `InventoryHost` 节点及其子节点，然后替换它的 `inventory_data` 与 `definition`。可先从 `gdbase/inventory/presets/host/` 选择网格、目录或环绕预设，再在 Inspector 中打开定义编辑器调整布局和 Feature。`InventoryHost` 的 **创建背包装配**、**移除背包装配** 工具按钮用于重建或移除其界面装配。

如果需要从脚本绑定运行时数据，可使用 `InventoryHost.apply_runtime_binding(next_inventory, next_owner, next_dependencies, next_transfer_target)`。不需要实体依赖的普通界面也可以直接设置 `inventory_data` 和 `definition`。要连接快捷转移目标，在源 Host 的 `transfer_target_host` 指向目标 Host，并配置相应 Feature。

`InventoryData` 的物品成员以 `occupy_map` 的占用记录为准；`item_instances` 是派生缓存。正常玩法中请通过库存操作接口修改内容，不要只改写 `item_instances`。无界面系统调用需显式使用 `InventoryOperationContext.system()`；由 Host 发起的调用应使用对应的操作端点与策略。

## 目录说明

```text
addons/visual_inventory/
├── plugin.cfg                 # 编辑器插件入口
├── visual_inventory_dome.tscn # 演示场景
├── visual_inventory_dome_inventory.tres
├── item_data/                 # 物品编辑器
├── inventory_data/            # 库存编辑器
├── inventory_host_definition/ # Host 布局和功能编辑器
├── shape/ 与 occupy/          # 格子资源编辑器
└── gdbase/
    ├── inventory/core/       # 物品、库存、操作协议
    ├── inventory/parts/      # 可组合物品 Part 与扩展功能
    ├── inventory/ui/         # Host、布局、输入与呈现
    └── inventory/presets/    # 可复制或修改的预设资源
```
## erw的话

以前专门为库存系统写非常多可视化的编辑面板根本是不可能的事情，它吃力又不讨好。对于我来说，宁愿多敲代码用节点去拼一个背包也不愿意去为这些资源写专门的编辑面板。但AI的出现改变了这一切，为了减轻人类交互的负担，利用AI强大的能力写可视化的资源编辑面板成为了一个可选项。对我而言，它能够减轻许多重复化的配置工作。我能利用它做出非常多样的库存，并且不需要向AI许愿。因为这将许愿的流程转移到了前期。
那为什么不让AI去配置背包人物还有别的东西？我不清楚这个问题的回答，但我觉得这样很Cool

## 许可证

本项目以 [MIT License](LICENSE) 发布。
