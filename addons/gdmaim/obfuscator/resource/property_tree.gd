extends RefCounted


const SymbolTable := preload("../symbol_table.gd")
const Symbol := SymbolTable.Symbol


class ResourceID:
	var _name : String
	var _hash : String
	
	func _init(name : String, hash : String) -> void:
		_name = name
		_hash = hash
	
	static func parse(id : String) -> ResourceID:
		var parts = id.split('_', false, 1)
		if parts.size() != 2:
			push_error("Could not parse ResourceID: ", id)
		return ResourceID.new(parts[0], parts[1])
	
	func set_name(name : String) -> void:
		_name = name
	
	func get_name() -> String:
		return _name
	
	func set_hash(hash : String) -> void:
		_hash = hash
	
	func get_hash() -> String:
		return _hash
	
	func _to_string() -> String:
		return _name+'_'+_hash


class ExtResource:
	var path : String
	var uid : String
	var type : String
	var id : ResourceID
	
	func _to_string() -> String:
		return '[ext_resource type="' + type + '" uid="' + uid + '" path="' + path + '" id="' + id.to_string() + '"]'
	
	func to_ref_string() -> String:
		return 'ExtResource("' + id.to_string() + '")'
	
	func duplicate() -> ExtResource:
		var r := ExtResource.new()
		r.path = path
		r.uid = uid
		r.type = type
		r.id = id
		return r


class SubResource:
	var type : String
	var id : ResourceID
	var _properties : Dictionary
	
	func add_property(name : String, property : ResourceProperty) -> void:
		_properties[name] = property
	
	func get_properties() -> Array:
		return _properties.keys()
	
	func get_property(name : String) -> ResourceProperty:
		return _properties[name]
	
	func _to_string() -> String:
		return '[sub_resource type="' + type + '" id="' + id.to_string() + '"]'
	
	func to_ref_string() -> String:
		return 'SubResource("' + id.to_string() + '")'
	
	# Shallow copy
	func duplicate() -> SubResource:
		var r := SubResource.new()
		r.type = type
		r.id = id
		r._properties = _properties
		return r
	
	func same_ref(other : SubResource) -> bool:
		return _properties == other._properties
	
	func equal(other : SubResource) -> bool:
		return _properties.recursive_equal(other._properties, 2)
	
	func get_hash() -> int:
		return _properties.hash()


class ResourceProperty:
	var _value : String
	
	func _init(v : String) -> void:
		_value = v
	
	func set_value(v : String) -> void:
		_value = v
	
	func get_value() -> String:
		return _value
	
	func make_string() -> String:
		return get_value()


class ResourcePropertySubRef extends ResourceProperty:
	var sub_res : WeakRef
	
	func make_string() -> String:
		return 'SubResource("' + get_value() + '")'


class ResourcePropertyExtRef extends ResourceProperty:
	var ext_res : WeakRef
	
	func make_string() -> String:
		return 'ExtResource("' + get_value() + '")'


# TODO: Support Array[]([]) and Dictionary[,]({})


class SceneData:
	var _nodes : Dictionary
	var _ext_resources : Dictionary
	var _sub_resources : Dictionary
	
	var _dependencies : Dictionary
	var _dependent_nodes : Dictionary
	
	func add_ext_resource(path : String, uid : String, type : String, id : String) -> void:
		var r := ExtResource.new()
		r.path = path
		r.uid = uid
		r.type = type
		r.id = ResourceID.parse(id)
		_ext_resources[id] = r
	
	func get_ext_resource(id : String) -> ExtResource:
		return _ext_resources.get(id)
	
	func get_ext_resource_count() -> int:
		return _ext_resources.size()
	
	func add_sub_resource(type : String, id : String) -> void:
		var r := SubResource.new()
		r.type = type
		r.id = ResourceID.parse(id)
		_sub_resources[id] = r
	
	func get_sub_resource(id : String) -> SubResource:
		return _sub_resources.get(id)
	
	func get_sub_resource_count() -> int:
		return _sub_resources.size()
	
	func add_sub_property(id : String, name : String, property : ResourceProperty) -> void:
		var r : SubResource = _sub_resources.get(id)
		if r == null:
			return
		r.add_property(name, property)
	
	func add_property(node : String, name : String, property : ResourceProperty) -> void:
		if !_nodes.has(node):
			_nodes[node] = {}
		
		_nodes[node][name] = property
	
	func get_property(node : String, name : String) -> ResourceProperty:
		return _nodes.get(node, {}).get(name)
	
	func get_properties(node : String) -> Array:
		return _nodes.get(node, {}).keys()
	
	func add_dependency(node : String, ext_scene : String) -> void:
		_dependencies[node] = ext_scene
	
	func add_dependent_node(root : String, child : String) -> void:
		_dependent_nodes[child] = root
	
	func get_dependent_root(node : String) -> String:
		return _dependent_nodes.get(node, node)
	
	func get_dependent_roots() -> Array:
		return _dependencies.keys()
	
	func get_dependency(node : String) -> String:
		return _dependencies.get(get_dependent_root(node))
	
	func has_dependency(node : String) -> bool:
		return _dependencies.get(get_dependent_root(node)) != null


var _scenes : Dictionary


func get_scene(path : String) -> SceneData:
	if !_scenes.has(path):
		_scenes[path] = SceneData.new()
	
	return _scenes[path]
