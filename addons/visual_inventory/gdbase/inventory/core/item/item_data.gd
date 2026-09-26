@tool
extends Resource
class_name ItemData
## ItemData是物品的数据文件。它会记录物品长期不变的数据

const SHAPE_PART_TYPE := "Shape"

## 物品名称。
@export var item_name: String
## 物品图标。
@export var icon: Texture2D
## 物品最大可堆叠数量。
@export var max_num: int = 1
## 物品描述（风味/总结文案；精确数值以描述面板自动生成的效果数值块为准，勿在此承诺具体数字）。
@export_multiline var item_description: String
## 功能拼图。
@export var parts: Array[ItemPart] = []

## 获取拼图类型。无法读取时返回空字符串。
func _get_part_type(part: ItemPart) -> String:
	if part == null:
		return ""
	var part_script := part.get_script() as Script
	if part_script == null:
		return ""
	if !part_script.has_method("get_part_type"):
		return ""
	return part_script.call("get_part_type")

## 尝试添加数据。Part 自身声明其类型是否允许重复。
func try_add_part(item_part: ItemPart):
	if item_part == null:
		return
	var part_type := _get_part_type(item_part)
	if !item_part.allows_multiple() and has_type_part(part_type):
		return
	if !parts.has(item_part):
		parts.append(item_part)

## 获取模板轮廓；无形状拼图时返回 null。
func get_shape() -> Shape:
	var shape_part := get_type_part(SHAPE_PART_TYPE) as ItemShapePart
	if shape_part == null:
		return null
	return shape_part.shape

## 获取所有的拼图
func get_all_parts() -> Array[ItemPart]:
	return parts.duplicate()

## 我们没有强制要求parts中每种Part只能有一个。但我们默认在需要一种且单个Part的时候取靠前的Part。
func get_type_part(type: String) -> ItemPart:
	var result_part: ItemPart
	for part in parts:
		if not type.is_empty() and type == _get_part_type(part):
			result_part = part
			break
	return result_part

## 获取所有的 type 类型的数据
func get_all_same_type_parts(type: String) -> Array[ItemPart]:
	var result_part: Array[ItemPart]
	for part in parts:
		if not type.is_empty() and type == _get_part_type(part):
			result_part.append(part)
	return result_part

## 是否有输入种类的拼图
func has_type_part(type: String) -> bool:
	var has_result := false
	for part in parts:
		if not type.is_empty() and type == _get_part_type(part):
			has_result = true
			break
	return has_result
