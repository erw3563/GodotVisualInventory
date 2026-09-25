@tool
class_name Shape
extends Resource
## 通用形状资源：使用格子坐标直接定义形状。
## cells 表示形状占据的格子坐标集合。

## 形状占据的格子集合（注意不要填写重复格子）
@export var cells:Array[Vector2i] = [Vector2.ZERO]:
	set(value):
		cells = _unique_cells(value)

## 获取格子。
func get_cells() -> Array[Vector2i]:
	return cells

## cells格子去重
func _unique_cells(input_cells:Array[Vector2i]) -> Array[Vector2i]:
	var unique:Array[Vector2i] = []
	for cell in input_cells:
		if !unique.has(cell):
			unique.append(cell)
	return unique
