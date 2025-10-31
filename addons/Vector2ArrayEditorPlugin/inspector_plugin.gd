@tool
class_name Vector2ArrayInspectorPlugin
extends EditorInspectorPlugin

var _polygon_editor: PolygonEditor
var _property_editors: Array[Vector2ArrayPropertyEditor] = []

func setup(polygon_editor: PolygonEditor) -> void:
	_polygon_editor = polygon_editor

func cleanup() -> void:
	# Clean up all property editors with proper signal disconnection
	for editor: Vector2ArrayPropertyEditor in _property_editors:
		if is_instance_valid(editor):
			# Disconnect our tracking signal first
			if editor.tree_exiting.is_connected(_on_property_editor_removed):
				editor.tree_exiting.disconnect(_on_property_editor_removed)
			# Call the editor's cleanup method
			editor.cleanup()
	
	_property_editors.clear()
	_polygon_editor = null

func _can_handle(object: Object) -> bool:
	return true

func _parse_property(object: Object, type: Variant.Type, name: String, hint_type: PropertyHint, hint_string: String, usage_flags: int, wide: bool) -> bool:
	# skip invalid or remote nodes
	if not is_instance_valid(object) or not object is Node or not object.is_inside_tree():
		return false
	
	# Skip properties that aren't meant to be edited (like dictionary internals)
	if not (usage_flags & PROPERTY_USAGE_EDITOR):
		return false
	
	if type == TYPE_PACKED_VECTOR2_ARRAY:
		var property_editor: Vector2ArrayPropertyEditor = Vector2ArrayPropertyEditor.new()
		property_editor.setup(_polygon_editor, object, name)
		
		_property_editors.append(property_editor)
		property_editor.tree_exiting.connect(_on_property_editor_removed.bind(property_editor))
		
		add_custom_control(property_editor)
		return false
	elif type == TYPE_ARRAY:
		var is_vector2_array: bool = false
		
		# Check for Vector2 (type 5) or Vector2i (type 6)
		if hint_string == "5:" or hint_string.begins_with("5/") or hint_string == "6:" or hint_string.begins_with("6/"):
			is_vector2_array = true
		# Fallback: check actual array contents
		elif hint_string.is_empty() or hint_string.contains("Vector2"):
			var current_value = object.get(name)
			if current_value is Array and not current_value.is_empty():
				var first_item = current_value[0]
				# Accept Vector2 or Vector2i, but not Node2D
				if (first_item is Vector2 or first_item is Vector2i) and not first_item is Node2D:
					is_vector2_array = true
		
		if is_vector2_array:
			var property_editor: Vector2ArrayPropertyEditor = Vector2ArrayPropertyEditor.new()
			property_editor.setup(_polygon_editor, object, name)
			
			_property_editors.append(property_editor)
			property_editor.tree_exiting.connect(_on_property_editor_removed.bind(property_editor))
			
			add_custom_control(property_editor)
			return false
	
	return false

func _on_property_editor_removed(editor: Vector2ArrayPropertyEditor) -> void:
	_property_editors.erase(editor)

func _is_editing() -> bool:
	return _property_editors.any(func (property_editor: Vector2ArrayPropertyEditor) -> bool: return property_editor._is_editing)
