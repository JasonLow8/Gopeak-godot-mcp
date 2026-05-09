@tool
extends RefCounted
class_name MCPSceneUtils

static func refresh_and_reload(plugin: EditorPlugin, scene_path: String) -> void:
	_refresh_filesystem(plugin)
	_reload_scene_in_editor(plugin, scene_path)


static func _refresh_filesystem(plugin: EditorPlugin) -> void:
	if plugin:
		plugin.get_editor_interface().get_resource_filesystem().scan()


static func _reload_scene_in_editor(plugin: EditorPlugin, scene_path: String) -> void:
	if not plugin:
		return
	var ei := plugin.get_editor_interface()
	var edited := ei.get_edited_scene_root()
	if edited and edited.scene_file_path == scene_path:
		ei.reload_scene_from_path(scene_path)


static func ensure_res_path(path: String) -> String:
	if not path.begins_with("res://"):
		return "res://" + path
	return path


static func to_scene_res_path(project_path: String, scene_path: String) -> String:
	var p := scene_path.strip_edges()
	if p.begins_with("res://"):
		return p

	if project_path.strip_edges() != "":
		var normalized_project := project_path.replace("\\", "/")
		var normalized_scene := p.replace("\\", "/")
		if normalized_scene.begins_with(normalized_project):
			var rel := normalized_scene.substr(normalized_project.length())
			if rel.begins_with("/"):
				rel = rel.substr(1)
			return ensure_res_path(rel)

	return ensure_res_path(p)


static func load_scene(scene_path: String) -> Array:
	if scene_path.strip_edges().is_empty():
		return [null, {"ok": false, "error": "Missing scenePath"}]
	if not FileAccess.file_exists(scene_path):
		return [null, {"ok": false, "error": "Scene not found: " + scene_path}]
	var packed := load(scene_path) as PackedScene
	if not packed:
		return [null, {"ok": false, "error": "Failed to load: " + scene_path}]
	var root := packed.instantiate()
	if not root:
		return [null, {"ok": false, "error": "Failed to instantiate: " + scene_path}]
	return [root, {}]


static func save_scene(scene_root: Node, scene_path: String, plugin: EditorPlugin) -> Dictionary:
	var packed := PackedScene.new()
	if packed.pack(scene_root) != OK:
		scene_root.queue_free()
		return {"ok": false, "error": "Failed to pack scene"}
	if ResourceSaver.save(packed, scene_path) != OK:
		scene_root.queue_free()
		return {"ok": false, "error": "Failed to save scene"}
	scene_root.queue_free()
	refresh_and_reload(plugin, scene_path)
	return {}


static func find_node(root: Node, path: String) -> Node:
	if path == "." or path.is_empty():
		return root
	return root.get_node_or_null(path)


static func parse_value(value, expected_type: int = TYPE_NIL):
	if typeof(value) == TYPE_DICTIONARY:
		var type_tag := ""
		if value.has("type"):
			type_tag = str(value["type"])
		elif value.has("_type"):
			type_tag = str(value["_type"])

		if not type_tag.is_empty():
			match type_tag:
				"Vector2":
					return Vector2(value.get("x", 0), value.get("y", 0))
				"Vector3":
					return Vector3(value.get("x", 0), value.get("y", 0), value.get("z", 0))
				"Color":
					return Color(value.get("r", 1), value.get("g", 1), value.get("b", 1), value.get("a", 1))
				"Vector2i":
					return Vector2i(value.get("x", 0), value.get("y", 0))
				"Vector3i":
					return Vector3i(value.get("x", 0), value.get("y", 0), value.get("z", 0))
				"Rect2":
					return Rect2(value.get("x", 0), value.get("y", 0), value.get("width", 0), value.get("height", 0))
				"Transform2D":
					if value.has("x") and value.has("y") and value.has("origin"):
						var xx: Dictionary = value["x"]
						var yy: Dictionary = value["y"]
						var oo: Dictionary = value["origin"]
						return Transform2D(
							Vector2(xx.get("x", 1), xx.get("y", 0)),
							Vector2(yy.get("x", 0), yy.get("y", 1)),
							Vector2(oo.get("x", 0), oo.get("y", 0))
						)
				"Transform3D":
					if value.has("basis") and value.has("origin"):
						var b: Dictionary = value["basis"]
						var o: Dictionary = value["origin"]
						var basis := Basis(
							Vector3(b.get("x", {}).get("x", 1), b.get("x", {}).get("y", 0), b.get("x", {}).get("z", 0)),
							Vector3(b.get("y", {}).get("x", 0), b.get("y", {}).get("y", 1), b.get("y", {}).get("z", 0)),
							Vector3(b.get("z", {}).get("x", 0), b.get("z", {}).get("y", 0), b.get("z", {}).get("z", 0))
						)
						return Transform3D(basis, Vector3(o.get("x", 0), o.get("y", 0), o.get("z", 0)))
				"NodePath":
					return NodePath(value.get("path", ""))
				"Resource":
					var resource_path: String = str(value.get("path", ""))
					if resource_path.is_empty():
						return null
					return load(resource_path)

		match expected_type:
			TYPE_VECTOR2:
				if value.has("x") and value.has("y"):
					return Vector2(value.get("x", 0), value.get("y", 0))
			TYPE_VECTOR2I:
				if value.has("x") and value.has("y"):
					return Vector2i(value.get("x", 0), value.get("y", 0))
			TYPE_VECTOR3:
				if value.has("x") and value.has("y") and value.has("z"):
					return Vector3(value.get("x", 0), value.get("y", 0), value.get("z", 0))
			TYPE_VECTOR3I:
				if value.has("x") and value.has("y") and value.has("z"):
					return Vector3i(value.get("x", 0), value.get("y", 0), value.get("z", 0))
			TYPE_COLOR:
				if value.has("r") and value.has("g") and value.has("b"):
					return Color(value.get("r", 1), value.get("g", 1), value.get("b", 1), value.get("a", 1))
			TYPE_RECT2:
				if value.has("x") and value.has("y") and value.has("width") and value.has("height"):
					return Rect2(value.get("x", 0), value.get("y", 0), value.get("width", 0), value.get("height", 0))
			TYPE_NODE_PATH:
				if value.has("path"):
					return NodePath(value.get("path", ""))
	if typeof(value) == TYPE_ARRAY:
		match expected_type:
			TYPE_VECTOR2:
				if value.size() >= 2:
					return Vector2(value[0], value[1])
			TYPE_VECTOR2I:
				if value.size() >= 2:
					return Vector2i(value[0], value[1])
			TYPE_VECTOR3:
				if value.size() >= 3:
					return Vector3(value[0], value[1], value[2])
			TYPE_VECTOR3I:
				if value.size() >= 3:
					return Vector3i(value[0], value[1], value[2])
		var result: Array = []
		for item in value:
			result.append(parse_value(item))
		return result
	return value


static func get_property_type(node: Node, prop_name: String) -> int:
	for prop in node.get_property_list():
		if str(prop.get("name", "")) == prop_name:
			return int(prop.get("type", TYPE_NIL))
	return TYPE_NIL


static func serialize_value(value) -> Variant:
	match typeof(value):
		TYPE_VECTOR2:
			return {"type": "Vector2", "x": value.x, "y": value.y}
		TYPE_VECTOR3:
			return {"type": "Vector3", "x": value.x, "y": value.y, "z": value.z}
		TYPE_COLOR:
			return {"type": "Color", "r": value.r, "g": value.g, "b": value.b, "a": value.a}
		TYPE_VECTOR2I:
			return {"type": "Vector2i", "x": value.x, "y": value.y}
		TYPE_VECTOR3I:
			return {"type": "Vector3i", "x": value.x, "y": value.y, "z": value.z}
		TYPE_RECT2:
			return {"type": "Rect2", "x": value.position.x, "y": value.position.y, "width": value.size.x, "height": value.size.y}
		TYPE_NODE_PATH:
			return {"type": "NodePath", "path": str(value)}
		TYPE_TRANSFORM2D:
			return {
				"type": "Transform2D",
				"x": {"x": value.x.x, "y": value.x.y},
				"y": {"x": value.y.x, "y": value.y.y},
				"origin": {"x": value.origin.x, "y": value.origin.y}
			}
		TYPE_TRANSFORM3D:
			return {
				"type": "Transform3D",
				"basis": {
					"x": {"x": value.basis.x.x, "y": value.basis.x.y, "z": value.basis.x.z},
					"y": {"x": value.basis.y.x, "y": value.basis.y.y, "z": value.basis.y.z},
					"z": {"x": value.basis.z.x, "y": value.basis.z.y, "z": value.basis.z.z}
				},
				"origin": {"x": value.origin.x, "y": value.origin.y, "z": value.origin.z}
			}
		TYPE_OBJECT:
			if value and value is Resource and value.resource_path:
				return {"type": "Resource", "path": value.resource_path}
			return null
		_:
			return value


static func set_node_properties(node: Node, properties: Dictionary) -> void:
	for prop_name in properties:
		var expected_type := get_property_type(node, str(prop_name))
		var val = parse_value(properties[prop_name], expected_type)
		node.set(prop_name, val)


static func parse_properties_arg(raw_properties) -> Dictionary:
	if typeof(raw_properties) == TYPE_DICTIONARY:
		return raw_properties
	if typeof(raw_properties) == TYPE_STRING:
		var text := String(raw_properties)
		if text.strip_edges().is_empty():
			return {}
		var parsed = JSON.parse_string(text)
		if typeof(parsed) == TYPE_DICTIONARY:
			return parsed
	return {}


static func ensure_parent_dir_for_scene(scene_path: String) -> void:
	var base_dir := scene_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(base_dir):
		DirAccess.make_dir_recursive_absolute(base_dir)


static func set_owner_recursive(node: Node, scene_owner: Node) -> void:
	node.owner = scene_owner
	for child in node.get_children():
		if child is Node:
			set_owner_recursive(child as Node, scene_owner)