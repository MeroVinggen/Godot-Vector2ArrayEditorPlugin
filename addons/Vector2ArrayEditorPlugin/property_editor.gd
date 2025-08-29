@tool
class_name Vector2ArrayPropertyEditor
extends EditorProperty

var _polygon_editor: PolygonEditor
var _target_object: Object
var _property_name: String
var _edit_button: Button
var _is_editing: bool = false

# Performance: Cache button states
var _last_button_state: bool = false
var _needs_button_update: bool = true

# Hash-based array change detection
var _last_known_hash: int = 0
var _sync_timer: Timer

var _suppress_external_monitoring: bool = false

func _ready() -> void:
	# Force an update when the property editor is ready
	call_deferred("_force_sync_check")

func _force_sync_check() -> void:
	if is_instance_valid(_target_object):
		var current_array: PackedVector2Array = _target_object.get(_property_name)
		var current_hash: int = _hash_array(current_array)
		if current_hash != _last_known_hash:
			_handle_external_array_change(current_array, current_hash)

# Override update_property to catch when Godot updates the property
func update_property() -> void:
	super.update_property()
	call_deferred("_force_sync_check")
	if _is_editing:
		_stop_editing()
	
	# Safe timer cleanup on property update
	if _sync_timer:
		_disconnect_all_signals()  # Clean up before freeing timer
		if _sync_timer.is_inside_tree():
			_sync_timer.queue_free()
		_sync_timer = null

func setup(polygon_editor: PolygonEditor, object: Object, prop_name: String) -> void:
	_polygon_editor = polygon_editor
	_target_object = object
	_property_name = prop_name
	
	_create_ui()
	_setup_sync_monitoring()
	_setup_property_notifications()
	_update_button_state()

func _setup_property_notifications() -> void:
	# Try to connect to the target object's property change signals if available
	if is_instance_valid(_target_object):
		# Many Node types emit changed signal when properties are modified
		if _target_object.has_signal("changed"):
			if not _target_object.changed.is_connected(_on_target_property_changed):
				_target_object.changed.connect(_on_target_property_changed)
		# Some objects have property_list_changed
		elif _target_object.has_signal("property_list_changed"):
			if not _target_object.property_list_changed.is_connected(_on_target_property_changed):
				_target_object.property_list_changed.connect(_on_target_property_changed)

func _create_ui() -> void:
	_edit_button = Button.new()
	_edit_button.pressed.connect(_on_edit_pressed)
	add_child(_edit_button)
	_update_button_text()

func _setup_sync_monitoring() -> void:
	# Create a timer to check for external changes
	_sync_timer = Timer.new()
	_sync_timer.wait_time = 0.2  # 5Hz - reduced frequency
	_sync_timer.autostart = true
	_sync_timer.timeout.connect(_check_for_external_changes)
	add_child(_sync_timer)
	
	# Initialize last known state with hash
	if is_instance_valid(_target_object):
		var current_array: PackedVector2Array = _target_object.get(_property_name)
		_last_known_hash = _hash_array(current_array)

# Fast hash-based array comparison
func _hash_array(arr: PackedVector2Array) -> int:
	var hash: int = arr.size()
	for i: int in range(arr.size()):
		var v: Vector2 = arr[i]
		# Simple but effective hash combining x, y coordinates with array index
		hash = hash * 31 + int(v.x * 1000) + int(v.y * 1000) * 1009 + i * 97
	return hash

func _check_for_external_changes() -> void:
	# Don't check during suppressed periods
	if _suppress_external_monitoring:
		return
	
	# Enhanced object validation
	if not is_instance_valid(_target_object):
		_stop_editing_without_editor_call()
		return
	
	# Check if object is still in the scene tree
	if not _target_object.is_inside_tree():
		_stop_editing_without_editor_call()
		return
	
	# Verify property still exists
	var property_list: Array[Dictionary] = _target_object.get_property_list()
	var property_exists: bool = false
	for prop: Dictionary in property_list:
		if prop.name == _property_name:
			if prop.type == TYPE_PACKED_VECTOR2_ARRAY:
				property_exists = true
				break
			elif prop.type == TYPE_ARRAY:
				# Enhanced Array[Vector2] detection
				if (prop.hint_string.contains("Vector2") or 
					prop.hint_string == "5:" or
					prop.class_name == "Vector2" or
					prop.hint_string.begins_with("2/2:")):
					property_exists = true
					break
	
	if not property_exists:
		_stop_editing_without_editor_call()
		return
	
	# Check if we think we're editing but the polygon editor is not editing us
	if _is_editing and is_instance_valid(_polygon_editor):
		if _polygon_editor._current_property_editor != self:
			notify_stop_editing()
			return
	
	# Safe property access
	var current_value = _target_object.get(_property_name)
	if current_value == null:
		_stop_editing_without_editor_call()
		return
	
	# Convert to PackedVector2Array for consistent processing
	var current_array: PackedVector2Array = _to_packed_array(current_value)
	
	# Hash-based change detection
	var current_hash: int = _hash_array(current_array)
	if current_hash != _last_known_hash:
		_handle_external_array_change(current_array, current_hash)

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

func _handle_external_array_change(new_array: PackedVector2Array, new_hash: int) -> void:
	_last_known_hash = new_hash
	
	# ALWAYS update button text when array changes
	refresh_button_text()
	
	# If we're currently editing, handle the change
	if _is_editing:
		if new_array.size() < 3:
			# Array has been reduced below minimum - stop editing
			_stop_editing()
		else:
			# OPTIMIZED: Direct assignment instead of duplicate
			if is_instance_valid(_polygon_editor):
				_polygon_editor._polygon_data.vertices = new_array
				_polygon_editor._request_overlay_update()

func _update_button_text() -> void:
	if not is_instance_valid(_target_object):
		return
	
	if _edit_button.disabled:
		_edit_button.text = "Unsupported node"
		return
	
	var current_value = _target_object.get(_property_name)
	var current_array: PackedVector2Array = _to_packed_array(current_value)
	
	if current_array.size() < 3:
		var points_needed: int = 3 - current_array.size()
		if current_array.size() == 0:
			_edit_button.text = "Add 3 Default Points"
		else:
			_edit_button.text = "Add %d More Points" % points_needed
	elif _is_editing:
		_edit_button.text = "Stop Editing"
	else:
		_edit_button.text = "Edit in 2D View"

func _on_edit_pressed() -> void:
	if not is_instance_valid(_target_object):
		return
	
	var current_array: PackedVector2Array = _target_object.get(_property_name)
	
	if current_array.size() < 3:
		_add_needed_points()
	elif _is_editing:
		_stop_editing()
	else:
		_start_editing()

func _add_needed_points() -> void:
	if not is_instance_valid(_polygon_editor):
		return
	
	var current_value = _target_object.get(_property_name)
	var current_array: PackedVector2Array = _to_packed_array(current_value)
	var points_needed: int = 3 - current_array.size()
	
	# Create new array with pre-allocated size
	var new_points: PackedVector2Array = PackedVector2Array()
	new_points.resize(3)
	
	# Copy existing points
	for i: int in range(current_array.size()):
		new_points[i] = current_array[i]
	
	# Add points based on what we already have
	match current_array.size():
		0:
			# No existing points - add default triangle
			new_points[0] = Vector2(32.0, 0.0)
			new_points[1] = Vector2(-32.0, 32.0)
			new_points[2] = Vector2(-32.0, -32.0)
		1:
			# One existing point - add two more to form triangle
			var existing_point: Vector2 = current_array[0]
			new_points[1] = existing_point + Vector2(64.0, 0.0)
			new_points[2] = existing_point + Vector2(0.0, 64.0)
		2:
			# Two existing points - add one more to complete triangle
			var p1: Vector2 = current_array[0]
			var p2: Vector2 = current_array[1]
			# Create third point to form a triangle (perpendicular to the line between p1 and p2)
			var midpoint: Vector2 = (p1 + p2) * 0.5
			var direction: Vector2 = (p2 - p1).normalized()
			var perpendicular: Vector2 = Vector2(-direction.y, direction.x) * 32.0
			new_points[2] = midpoint + perpendicular
	
	# Suppress external monitoring during the operation
	_suppress_external_monitoring = true
	
	# Direct operation without undo/redo
	_do_set_points(new_points)
	_complete_point_addition()

func _complete_point_addition() -> void:
	# Update hash and resume monitoring
	if is_instance_valid(_target_object):
		var current_array: PackedVector2Array = _target_object.get(_property_name)
		_last_known_hash = _hash_array(current_array)
	
	_suppress_external_monitoring = false
	refresh_button_text()
	
	# Start editing after adding points (this will properly handle multiple editors)
	call_deferred("_start_editing")

func _do_set_points(points: PackedVector2Array) -> void:
	var original_value = _target_object.get(_property_name)
	var new_value = _from_packed_array(points, original_value)
	_target_object.set(_property_name, new_value)
	# Update hash immediately
	_last_known_hash = _hash_array(points)
	# Force inspector update
	emit_changed(_property_name, new_value, "", false)

func _start_editing() -> void:
	if not is_instance_valid(_polygon_editor):
		return
	
	var current_value = _target_object.get(_property_name)
	var current_array: PackedVector2Array = _to_packed_array(current_value)
	if current_array.size() < 3:
		return  # Can't edit with less than 3 points
	
	# Pass ourselves to the polygon editor so it can manage multiple editors
	_is_editing = true
	_polygon_editor.set_current(_target_object, _property_name, self)
	
	_edit_button.text = "Stop Editing"
	_edit_button.modulate = Color.GREEN

func _stop_editing() -> void:
	if not is_instance_valid(_polygon_editor):
		_stop_editing_without_editor_call()
		return
	
	_polygon_editor.clear_current()
	_stop_editing_without_editor_call()

func _stop_editing_without_editor_call() -> void:
	_is_editing = false
	
	if is_instance_valid(_edit_button):
		_edit_button.modulate = Color.WHITE
		# FORCE button text update when stopping editing
		refresh_button_text()

# Public method that can be called by PolygonEditor to notify this editor to stop
func notify_stop_editing() -> void:
	_stop_editing_without_editor_call()

func notify_vertex_change(suppress_emit: bool = false) -> void:
	if is_instance_valid(_target_object):
		var current_value = _target_object.get(_property_name)
		var current_array: PackedVector2Array = _to_packed_array(current_value)
		
		# Temporarily suppress external monitoring to prevent conflicts
		_suppress_external_monitoring = true
		_last_known_hash = _hash_array(current_array)
		
		# Only emit_changed if not suppressed (to avoid undo/redo conflicts)
		if not suppress_emit:
			# Force the editor to update the property display
			# This is what makes the array values update in real-time in the inspector
			emit_changed(_property_name, current_value, "", false)
		
		# Re-enable monitoring after a short delay
		call_deferred("_resume_external_monitoring")

func _resume_external_monitoring() -> void:
	_suppress_external_monitoring = false

func force_inspector_update() -> void:
	if is_instance_valid(_target_object):
		var current_value = _target_object.get(_property_name)
		var current_array: PackedVector2Array = _to_packed_array(current_value)
		_last_known_hash = _hash_array(current_array)
		emit_changed(_property_name, current_value, "", false)
		refresh_button_text()

func _update_button_state() -> void:
	var should_enable: bool = _target_object and _target_object is CanvasItem
	
	# Performance: Only update if state changed
	if _needs_button_update or should_enable != _last_button_state:
		_edit_button.disabled = not should_enable
		refresh_button_text()
		
		if not should_enable:
			_edit_button.tooltip_text = "This feature only works with CanvasItem objects (Node2D and Control)"
		else:
			var current_value = _target_object.get(_property_name)
			var current_array: PackedVector2Array = _to_packed_array(current_value)
			if current_array.size() < 3:
				var points_needed: int = 3 - current_array.size()
				if current_array.size() == 0:
					_edit_button.tooltip_text = "Click to add 3 default points and start editing"
				else:
					_edit_button.tooltip_text = "Click to add %d more points to complete polygon" % points_needed
			else:
				_edit_button.tooltip_text = "Click to edit this PackedVector2Array as a polygon in the 2D view"
		
		_last_button_state = should_enable
		_needs_button_update = false

# Connect to property change notifications if available
func _on_target_property_changed() -> void:
	if is_instance_valid(_target_object):
		var current_array: PackedVector2Array = _target_object.get(_property_name)
		var current_hash: int = _hash_array(current_array)
		if current_hash != _last_known_hash:
			_handle_external_array_change(current_array, current_hash)

# Called by PolygonEditor when vertices change
func refresh_button_text() -> void:
	call_deferred("_update_button_text")

func cleanup() -> void:
	# Stop editing first
	if _is_editing:
		_stop_editing_without_editor_call()
	
	# Disconnect all signals safely
	_disconnect_all_signals()
	
	# Clean up timer
	if _sync_timer:
		if _sync_timer.is_inside_tree():
			_sync_timer.queue_free()
		_sync_timer = null
	
	# Clear references
	_polygon_editor = null
	_target_object = null
	_property_name = ""
	_edit_button = null

func _disconnect_all_signals() -> void:
	# Safely disconnect from target object
	if is_instance_valid(_target_object):
		if _target_object.has_signal("changed"):
			if _target_object.changed.is_connected(_on_target_property_changed):
				_target_object.changed.disconnect(_on_target_property_changed)
		elif _target_object.has_signal("property_list_changed"):
			if _target_object.property_list_changed.is_connected(_on_target_property_changed):
				_target_object.property_list_changed.disconnect(_on_target_property_changed)
	
	# Disconnect button signal if it exists
	if is_instance_valid(_edit_button) and _edit_button.pressed.is_connected(_on_edit_pressed):
		_edit_button.pressed.disconnect(_on_edit_pressed)
