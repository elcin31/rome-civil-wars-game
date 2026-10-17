extends RefCounted
## Validate JSON shapes before models replace their live state.


static func matches(value: Variant, example: Variant, depth: int = 0) -> bool:
	if depth > 8:
		return false
	if example is Dictionary:
		return _dictionary(value, example, depth)
	if example is Array:
		return _array(value, example, depth)
	if example is float or example is int:
		return (value is float or value is int) and is_finite(float(value))
	return typeof(value) == typeof(example)


static func _dictionary(value: Variant, example: Dictionary, depth: int) -> bool:
	if not value is Dictionary or value.size() > 64:
		return false
	for key in example:
		if not value.has(key) or not matches(value[key], example[key], depth + 1):
			return false
	return true


static func _array(value: Variant, example: Array, depth: int) -> bool:
	if not value is Array or value.size() > 128:
		return false
	if not example.is_empty():
		for item in value:
			if not matches(item, example[0], depth + 1):
				return false
	return true
