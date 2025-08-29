@tool
class_name PolygonEditor
extends RefCounted

# Visual constants
const CURSOR_THRESHOLD := 6.0
const VERTEX_RADIUS := 6.0
const VERTEX_EXCLUSION_RADIUS := 20.0  # 2x vertex radius - no ghost hints near existing vertices
const VERTEX_COLOR := Color(0.0, 0.5, 1.0, 0.5)
const VERTEX_ACTIVE_COLOR := Color(1.0, 1.0, 1.0)
const VERTEX_NEW_COLOR := Color(0.0, 1.0, 1.0, 0.5)
const POLYGON_COLOR := Color(0.0, 0.5, 1.0, 0.2)

# Core state
var _plugin: EditorPlugin
var _current_object: Object
var _current_property: String
var _polygon_data: PolygonData

# Track active property editor for proper cleanup
var _current_property_editor: Vector2ArrayPropertyEditor

# Transform caching (like reference plugin)
var _transform_to_screen: Transform2D
var _transform_to_local: Transform2D

# Interaction state
var _active_vertex_index: int = -1
var _can_add_at: int = -1
var _is_dragging: bool = false
var _drag_start_pos: Vector2
var _cursor_pos: Vector2

# NEW: Ghost vertex positioning
var _ghost_vertex_pos: Vector2

# OPTIMIZED: Two-way sync with hash-based change detection
var _sync_timer: Timer
var _last_sync_hash: int = 0

func setup(plugin: EditorPlugin) -> void:
	_plugin = plugin
	_polygon_data = PolygonData.new()
	
	# Setup single consolidated timer
	_sync_timer = Timer.new()
	_sync_timer.wait_time = 0.1  # 10Hz - balanced frequency
	_sync_timer.autostart = false
	_sync_timer.timeout.connect(_on_timer_tick)
	
	# Add timer to plugin so it gets cleaned up properly
	_plugin.add_child(_sync_timer)

func cleanup() -> void:
	# Safe timer cleanup
	if _sync_timer:
		if _sync_timer.is_inside_tree():
			_sync_timer.queue_free()
		else:
			# Timer already removed from tree, just clear reference
			_sync_timer = null
		_sync_timer = null
	
	clear_current()
	_polygon_data = null
	_plugin = null

func _on_timer_tick() -> void:
	if not _is_editing_valid():
		return
	
	# Enhanced selection and scene checking
	var selection: EditorSelection = EditorInterface.get_selection()
	if not selection:
		call_deferred("clear_current")
		return
	
	var selected_nodes: Array[Node] = selection.get_selected_nodes()
	var our_object_selected: bool = false
	
	for node: Node in selected_nodes:
		# Verify node is still valid and properly in the scene tree
		if is_instance_valid(node) and node.is_inside_tree() and node == _current_object:
			our_object_selected = true
			break
	
	if not our_object_selected:
		call_deferred("clear_current")
		return
	
	# Verify current scene hasn't changed
	var current_scene: Node = EditorInterface.get_edited_scene_root()
	if not current_scene:
		call_deferred("clear_current")
		return
	
	# Additional safety: check if we can still access the property
	var current_array = _current_object.get(_current_property)
	if current_array == null:
		call_deferred("clear_current")
		return
	
	# Convert to PackedVector2Array for consistent processing
	var packed_array: PackedVector2Array = _to_packed_array(current_array)
	
	# OPTIMIZED: Hash-based change detection
	var current_hash: int = _hash_array(packed_array)
	
	if current_hash != _last_sync_hash:
		# If array is too small, we should stop editing
		if packed_array.size() < 3:
			call_deferred("clear_current")
			return
		
		# Update our data and refresh display
		_polygon_data.vertices = packed_array
		_last_sync_hash = current_hash
		_request_overlay_update()

# OPTIMIZED: Fast hash-based array comparison
func _hash_array(arr: PackedVector2Array) -> int:
	var hash: int = arr.size()
	for i: int in range(arr.size()):
		var v: Vector2 = arr[i]
		# Simple but effective hash combining x, y coordinates with array index
		hash = hash * 31 + int(v.x * 1000) + int(v.y * 1000) * 1009 + i * 97
	return hash

func set_current(object: Object, property: String, property_editor: Vector2ArrayPropertyEditor = null) -> void:
	# If we're switching to a different property editor, notify the old one to stop
	if _current_property_editor and _current_property_editor != property_editor and is_instance_valid(_current_property_editor):
		_current_property_editor.notify_stop_editing()
	
	# Clear previous state
	clear_current()
	
	# Set new state
	_current_object = object
	_current_property = property
	_current_property_editor = property_editor
	
	if object and property and object is CanvasItem:
		_polygon_data.set_from_object(object, property)
		
		# OPTIMIZED: Initialize sync tracking with hash
		_last_sync_hash = _hash_array(_polygon_data.vertices)
		
		# Start consolidated timer
		if _sync_timer:
			_sync_timer.start()
		
		# Force editor selection - this ensures focus
		EditorInterface.get_selection().clear()
		EditorInterface.get_selection().add_node(object)
		
		# Initialize focus tracking
		var selection: EditorSelection = EditorInterface.get_selection()
	
	_request_overlay_update()

func clear_current() -> void:
	# Stop sync monitoring
	if _sync_timer:
		_sync_timer.stop()
	
	# Notify property editor that we're stopping
	if _current_property_editor and is_instance_valid(_current_property_editor):
		_current_property_editor.notify_stop_editing()
	
	_current_object = null
	_current_property = ""
	_current_property_editor = null
	if _polygon_data:
		_polygon_data.clear()
	_active_vertex_index = -1
	_can_add_at = -1
	_is_dragging = false
	_last_sync_hash = 0
	_request_overlay_update()

func handles(object: Object) -> bool:
	return _current_object != null and object == _current_object

func edit(object: Object) -> void:
	# Handled by set_current
	pass

func draw_overlay(overlay: Control) -> void:
	# CRITICAL: Comprehensive validation before drawing
	if not _is_editing_valid():
		return
	
	# Double-check that our object is still selected and exists in the scene tree
	var selection: EditorSelection = EditorInterface.get_selection()
	var selected_nodes: Array[Node] = selection.get_selected_nodes()
	var our_object_selected: bool = false
	
	for node: Node in selected_nodes:
		# Verify node is still valid and in the scene tree
		if is_instance_valid(node) and node.is_inside_tree() and node == _current_object:
			our_object_selected = true
			break
	
	if not our_object_selected:
		call_deferred("clear_current")
		return
	
	# Verify the current scene hasn't changed
	var current_scene: Node = EditorInterface.get_edited_scene_root()
	if not current_scene:
		call_deferred("clear_current")
		return
	
	# Check if our object is still a descendant of the current scene
	if not _current_object.is_ancestor_of(current_scene) and _current_object != current_scene:
		var node: Node = _current_object
		var is_descendant: bool = false
		while node:
			if node == current_scene:
				is_descendant = true
				break
			node = node.get_parent()
		
		if not is_descendant:
			call_deferred("clear_current")
			return
	
	_update_transforms()
	
	if _polygon_data.vertices.is_empty():
		return
	
	# OPTIMIZED: Pre-transform vertices once for drawing
	var screen_vertices: PackedVector2Array = PackedVector2Array()
	screen_vertices.resize(_polygon_data.vertices.size())
	for i: int in range(_polygon_data.vertices.size()):
		screen_vertices[i] = _transform_to_screen * _polygon_data.vertices[i]
	
	# Only draw polygon if we have at least 3 vertices
	if screen_vertices.size() >= 3:
		overlay.draw_colored_polygon(screen_vertices, POLYGON_COLOR)
	
	# Draw vertices using pre-transformed positions
	for i: int in range(screen_vertices.size()):
		_draw_vertex(overlay, screen_vertices[i], i)
	
	# Only show ghost vertex for adding if we have enough vertices to form a polygon
	if _can_add_at != -1 and _polygon_data.vertices.size() >= 3:
		_draw_ghost_vertex(overlay, _ghost_vertex_pos)

func handle_input(event: InputEvent) -> bool:
	if not _is_editing_valid():
		return false
	
	# Comprehensive selection and scene validation
	var selection: EditorSelection = EditorInterface.get_selection()
	var selected_nodes: Array[Node] = selection.get_selected_nodes()
	var our_object_selected: bool = false
	
	for node: Node in selected_nodes:
		# Verify node is still valid and in the scene tree
		if is_instance_valid(node) and node.is_inside_tree() and node == _current_object:
			our_object_selected = true
			break
	
	if not our_object_selected:
		call_deferred("clear_current")
		return false
	
	# Verify the current scene is still valid
	var current_scene: Node = EditorInterface.get_edited_scene_root()
	if not current_scene or not _current_object.is_inside_tree():
		call_deferred("clear_current")
		return false
	
	var handled: bool = false
	
	if event is InputEventMouseButton:
		handled = _handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		handled = _handle_mouse_motion(event)
	
	if handled:
		_request_overlay_update()
	
	return handled

# Private methods
# Replace _is_editing_valid function:
func _is_editing_valid() -> bool:
	if not _current_object or not _current_property:
		return false
	
	if not is_instance_valid(_current_object):
		call_deferred("clear_current")
		return false
	
	if not _current_object is CanvasItem:
		call_deferred("clear_current")
		return false
	
	if not _current_object.has_method("get") or not _current_object.has_method("set"):
		call_deferred("clear_current")
		return false
	
	# Verify the property exists and is the correct type
	var property_list: Array[Dictionary] = _current_object.get_property_list()
	var property_exists: bool = false
	for prop: Dictionary in property_list:
		if prop.name == _current_property:
			if prop.type == TYPE_PACKED_VECTOR2_ARRAY:
				property_exists = true
				break
			elif prop.type == TYPE_ARRAY:
				# More comprehensive Array[Vector2] detection
				if (prop.hint_string.contains("Vector2") or 
					prop.hint_string == "5:" or
					prop.class_name == "Vector2" or
					prop.hint_string.begins_with("2/2:")):
					property_exists = true
					break
	
	if not property_exists:
		call_deferred("clear_current")
		return false
	
	# Test that we can access the property and it contains Vector2s
	var test_value = _current_object.get(_current_property)
	if test_value is PackedVector2Array:
		return true
	elif test_value is Array:
		# Check if it's an array of Vector2s
		if test_value.is_empty():
			return true
		# Verify first element is Vector2
		if test_value.size() > 0 and test_value[0] is Vector2:
			return true
	
	call_deferred("clear_current")
	return false

func _update_transforms() -> void:
	if not _is_editing_valid():
		return
	
	var node: CanvasItem = _current_object as CanvasItem
	var transform_viewport: Transform2D = node.get_viewport_transform()
	var transform_canvas: Transform2D = node.get_canvas_transform()
	
	# Handle different node types for local transform
	var transform_local: Transform2D
	if node is Node2D:
		# Node2D nodes have a transform property
		transform_local = (node as Node2D).transform
	elif node is Control:
		# Control nodes use position, rotation, scale, and pivot_offset
		var control: Control = node as Control
		transform_local = Transform2D()
		
		# Apply scale
		transform_local = transform_local.scaled(control.scale)
		
		# Apply rotation
		if control.rotation != 0.0:
			transform_local = transform_local.rotated(control.rotation)
		
		# Apply translation (position - pivot_offset, then add pivot_offset back)
		var pivot: Vector2 = control.pivot_offset
		transform_local.origin = control.position + pivot
		if pivot != Vector2.ZERO:
			# Rotate and scale the pivot offset, then subtract it
			var transformed_pivot: Vector2 = transform_local.basis_xform(pivot)
			transform_local.origin -= transformed_pivot
	else:
		# Fallback for other CanvasItem types
		transform_local = Transform2D()
	
	_transform_to_screen = transform_viewport * transform_canvas * transform_local
	_transform_to_local = _transform_to_screen.affine_inverse()

func _handle_mouse_motion(event: InputEventMouseMotion) -> bool:
	_cursor_pos = event.position
	
	if _is_dragging:
		_drag_vertex(_transform_to_local * event.position)
		return true
	else:
		# Update hover states
		var old_active: int = _active_vertex_index
		var old_add: int = _can_add_at
		var old_ghost_pos: Vector2 = _ghost_vertex_pos
		
		_active_vertex_index = _get_active_vertex()
		
		# Only show ghost vertex if we have at least 3 vertices (can form a polygon)
		if _active_vertex_index == -1 and _polygon_data.vertices.size() >= 3:
			var add_result: Dictionary = _get_active_side_optimized()
			_can_add_at = add_result.index
			_ghost_vertex_pos = add_result.position
		else:
			_can_add_at = -1
		
		# Return true if ANY of these changed (including ghost position)
		return (old_active != _active_vertex_index or 
				old_add != _can_add_at or 
				old_ghost_pos != _ghost_vertex_pos)
	
	return false

func _handle_mouse_button(event: InputEventMouseButton) -> bool:
	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if _can_add_at != -1:
				_add_vertex()
				return true
			if _active_vertex_index != -1:
				_is_dragging = true
				_drag_start_pos = _polygon_data.vertices[_active_vertex_index]
				return true
		elif event.is_released() and _active_vertex_index != -1:
			_end_drag()
			return true
	elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_remove_vertex()
		return true
	
	return false

# OPTIMIZED: Cache transformed vertices for active vertex detection
func _get_active_vertex() -> int:
	var vertices_size: int = _polygon_data.vertices.size()
	for i: int in range(vertices_size):
		var screen_pos: Vector2 = _transform_to_screen * _polygon_data.vertices[i]
		if (_cursor_pos - screen_pos).length_squared() < CURSOR_THRESHOLD * CURSOR_THRESHOLD:
			return i
	return -1

# OPTIMIZED: More responsive ghost vertex positioning with exclusion zones
func _get_active_side_optimized() -> Dictionary:
	var result: Dictionary = {"index": -1, "position": Vector2.ZERO}
	
	if _active_vertex_index != -1:
		return result
	
	var size: int = _polygon_data.vertices.size()
	if size < 3:  # Need at least 3 vertices to form sides
		return result
	
	# OPTIMIZED: Pre-transform all vertices once
	var screen_vertices: PackedVector2Array = PackedVector2Array()
	screen_vertices.resize(size)
	for i: int in range(size):
		screen_vertices[i] = _transform_to_screen * _polygon_data.vertices[i]
		
	var min_distance_squared: float = CURSOR_THRESHOLD * CURSOR_THRESHOLD
	var best_index: int = -1
	var best_position: Vector2 = Vector2.ZERO
	
	for i: int in range(size):
		var a: Vector2 = screen_vertices[i]
		var b: Vector2 = screen_vertices[(i + 1) % size]
		
		# Find closest point on line segment to cursor
		var closest_point: Vector2 = _get_closest_point_on_segment(a, b, _cursor_pos)
		var distance_squared: float = (_cursor_pos - closest_point).length_squared()
		
		if distance_squared < min_distance_squared:
			# NEW: Check if ghost vertex would be too close to existing vertices
			var too_close_to_vertex: bool = false
			var exclusion_radius_squared: float = VERTEX_EXCLUSION_RADIUS * VERTEX_EXCLUSION_RADIUS
			
			for j: int in range(size):
				if (closest_point - screen_vertices[j]).length_squared() < exclusion_radius_squared:
					too_close_to_vertex = true
					break
			
			if not too_close_to_vertex:
				min_distance_squared = distance_squared
				best_index = (i + 1) % size
				best_position = closest_point
	
	if best_index != -1:
		result.index = best_index
		result.position = best_position
	
	return result

# Helper function to find closest point on line segment
func _get_closest_point_on_segment(a: Vector2, b: Vector2, point: Vector2) -> Vector2:
	var ab: Vector2 = b - a
	var ap: Vector2 = point - a
	
	# If segment has zero length, return point a
	var ab_length_squared: float = ab.length_squared()
	if ab_length_squared == 0:
		return a
	
	# Project point onto line, clamped to segment
	var t: float = ap.dot(ab) / ab_length_squared
	t = clamp(t, 0.0, 1.0)
	
	return a + t * ab

func _add_vertex() -> void:
	# Use the world position calculated from ghost vertex
	var position: Vector2 = _transform_to_local * _ghost_vertex_pos
	var index: int = _can_add_at
	
	_do_add_vertex(index, position)
	_can_add_at = -1

func _remove_vertex() -> void:
	# Can only remove vertices if we have more than 3 (to maintain polygon)
	if _active_vertex_index == -1 or _polygon_data.vertices.size() <= 3:
		return
	
	var index: int = _active_vertex_index
	_do_remove_vertex(index)

func _force_inspector_update() -> void:
	if _current_property_editor and is_instance_valid(_current_property_editor):
		_current_property_editor.notify_vertex_change(false)  # Allow emit_changed after undo/redo is complete

func _drag_vertex(position: Vector2) -> void:
	if _active_vertex_index == -1:
		return
	_do_update_vertex(_active_vertex_index, position.round())

func _end_drag() -> void:
	if not _is_dragging:
		return
	
	var final_pos: Vector2 = (_transform_to_local * _cursor_pos).round()
	_do_update_vertex(_active_vertex_index, final_pos)
	_is_dragging = false

func _do_add_vertex(index: int, vertex: Vector2) -> void:
	_polygon_data.insert_vertex(index, vertex)
	var original_value = _current_object.get(_current_property)
	_current_object.set(_current_property, _from_packed_array(_polygon_data.vertices, original_value))
	_active_vertex_index = index
	_last_sync_hash = _hash_array(_polygon_data.vertices)
	_force_inspector_update()

func _do_remove_vertex(index: int) -> void:
	_polygon_data.remove_vertex(index)
	var original_value = _current_object.get(_current_property)
	_current_object.set(_current_property, _from_packed_array(_polygon_data.vertices, original_value))
	_active_vertex_index = -1
	_last_sync_hash = _hash_array(_polygon_data.vertices)
	_force_inspector_update()
	
	# Check if we should stop editing due to insufficient points
	if _polygon_data.vertices.size() < 3:
		call_deferred("clear_current")

func _do_update_vertex(index: int, vertex: Vector2) -> void:
	_polygon_data.set_vertex(index, vertex)
	_current_object.set(_current_property, _polygon_data.vertices)
	_last_sync_hash = _hash_array(_polygon_data.vertices)
	
	# Notify property editor for real-time updates
	if _current_property_editor and is_instance_valid(_current_property_editor):
		_current_property_editor.notify_vertex_change(false)

func _draw_vertex(overlay: Control, position: Vector2, index: int) -> void:
	overlay.draw_circle(position, VERTEX_RADIUS, VERTEX_COLOR)
	if index == _active_vertex_index:
		overlay.draw_circle(position, VERTEX_RADIUS - 1.0, VERTEX_ACTIVE_COLOR)
		overlay.draw_string(overlay.get_theme_font("font"), 
			position + Vector2(-16.0, -16.0), str(index), HORIZONTAL_ALIGNMENT_LEFT, 32.0)

func _draw_ghost_vertex(overlay: Control, position: Vector2) -> void:
	overlay.draw_circle(position, VERTEX_RADIUS, VERTEX_NEW_COLOR)

func _request_overlay_update() -> void:
	if _plugin:
		_plugin.update_overlays()

# Helper class for polygon data management
class PolygonData:
	var vertices: PackedVector2Array = PackedVector2Array()
	
	func set_from_object(object: Object, property: String) -> void:
		var value = object.get(property)
		vertices = _to_packed_array(value)
	
	func _to_packed_array(value) -> PackedVector2Array:
		if value is PackedVector2Array:
			return value
		elif value is Array:
			var packed: PackedVector2Array = PackedVector2Array()
			for item in value:
				if item is Vector2:
					packed.append(item)
			return packed
		return PackedVector2Array()
	
	func clear() -> void:
		vertices = PackedVector2Array()
	
	func insert_vertex(index: int, vertex: Vector2) -> void:
		vertices.insert(index, vertex)
	
	func remove_vertex(index: int) -> void:
		vertices.remove_at(index)
	
	func set_vertex(index: int, vertex: Vector2) -> void:
		vertices[index] = vertex

func _to_packed_array(value) -> PackedVector2Array:
	if value is PackedVector2Array:
		return value
	elif value is Array:
		var packed: PackedVector2Array = PackedVector2Array()
		for item in value:
			if item is Vector2:
				packed.append(item)
		return packed
	return PackedVector2Array()

func _from_packed_array(packed_array: PackedVector2Array, original_value) -> Variant:
	if original_value is PackedVector2Array:
		return packed_array
	elif original_value is Array:
		var array: Array[Vector2] = []
		for v in packed_array:
			array.append(v)
		return array
	return packed_array
