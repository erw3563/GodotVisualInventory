@tool
class_name ItemTagPart
extends ItemPart
## 物品标签拼图。用于给物品声明静态标签。

## 物品拥有的标签列表。
@export var tags: PackedStringArray = PackedStringArray()


static func get_part_type() -> String:
	return "Tag"


func allows_multiple() -> bool:
	return false


## 判断当前拼图是否包含指定标签。
func has_tag(tag_id: String) -> bool:
	return tags.has(tag_id)


## 构建标签说明。
func get_description_panel() -> Array[Control]:
	var result_controls: Array[Control] = []
	if tags.is_empty():
		return result_controls
	var label := Label.new()
	label.text = "标签：" + "、".join(tags)
	result_controls.append(label)
	return result_controls
