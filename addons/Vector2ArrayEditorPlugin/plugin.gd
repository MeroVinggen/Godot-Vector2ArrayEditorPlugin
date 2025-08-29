@tool
extends EditorPlugin

var _polygon_editor: PolygonEditor
var _inspector_plugin: Vector2ArrayInspectorPlugin

func _enter_tree() -> void:
	# Initialize core editor
	_polygon_editor = PolygonEditor.new()
	_polygon_editor.setup(self)
	
	# Initialize inspector plugin
	_inspector_plugin = Vector2ArrayInspectorPlugin.new()
	_inspector_plugin.setup(_polygon_editor)
	add_inspector_plugin(_inspector_plugin)

func _exit_tree() -> void:
	# Clean shutdown
	if _polygon_editor:
		_polygon_editor.cleanup()
		_polygon_editor = null
	
	if _inspector_plugin:
		_inspector_plugin.cleanup()
		remove_inspector_plugin(_inspector_plugin)
		_inspector_plugin = null

func _has_main_screen() -> bool:
	return false

func _handles(object: Object) -> bool:
	return _polygon_editor.handles(object) if _polygon_editor else false

func _edit(object: Object) -> void:
	if _polygon_editor:
		_polygon_editor.edit(object)
		update_overlays()

func _forward_canvas_draw_over_viewport(overlay: Control) -> void:
	if _polygon_editor and _inspector_plugin._is_editing():
		_polygon_editor.draw_overlay(overlay)

func _forward_canvas_gui_input(event: InputEvent) -> bool:
	return _polygon_editor.handle_input(event) if _polygon_editor else false
