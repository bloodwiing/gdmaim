extends RefCounted


const _Logger := preload("../../logger.gd")
const _Settings := preload("../../settings.gd")
const SymbolTable := preload("../symbol_table.gd")
const PropertyTree := preload("property_tree.gd")

var path : String

var _source_data : String
var _data : String

var _property_tree : PropertyTree
var _dependency_roots : Dictionary
var _dependency_tree : Dictionary
var _ext_resources : Dictionary


func _init(path : String) -> void:
	self.path = path


func parse(source_data : String, property_tree : PropertyTree) -> void:
	_source_data = source_data
	_property_tree = property_tree
	_dependency_roots.clear()
	_ext_resources.clear()
	
	var lines : PackedStringArray = _source_data.split("\n")
	var i : int = 0
	while i < lines.size():
		var line : String = lines[i]
		
		if line.begins_with("[ext_resource") and line.contains('type="PackedScene"'):
			var tokens : PackedStringArray = line.split(" ", false)
			
			var resource_path : String
			var resource_id : String
			
			var token_i : int = 0
			while token_i < tokens.size():
				var token : String = tokens[token_i]
				token_i += 1
				
				var token_j : int = token_i
				if token.begins_with('path="'):
					while !token.ends_with('"') and token_j < tokens.size(): token += ' ' + tokens[token_j]; token_j += 1
					resource_path = _get_string_value(token)
					if resource_path.is_empty(): continue
				elif token.begins_with('id="'):
					while !token.ends_with('"') and token_j < tokens.size(): token += ' ' + tokens[token_j]; token_j += 1
					resource_id = _get_string_value(token)
					if resource_id.is_empty(): continue
			
			if not resource_path.is_empty() and not resource_id.is_empty():
				_ext_resources[resource_id] = resource_path
				_Logger.write(str(i+1) + " detected scene import " + resource_path + ' as "' + resource_id + '"')
			
			i += 1
		
		elif line.begins_with("[node"):
			var tokens : PackedStringArray = line.split(" ", false)
			
			var node_name : String = ""
			var node_parent : String = ""
			var node_instance : String = ""
			
			var token_i : int = 0
			while token_i < tokens.size():
				var token : String = tokens[token_i]
				token_i += 1
				
				var token_j : int = token_i
				if token.begins_with('name="'):
					while !token.ends_with('"') and token_j < tokens.size(): token += ' ' + tokens[token_j]; token_j += 1
					node_name = _get_string_value(token)
					if node_name.is_empty(): continue
				
				elif token.begins_with('parent="'):
					while !token.ends_with('"') and token_j < tokens.size(): token += ' ' + tokens[token_j]; token_j += 1;
					node_parent = _get_string_value(token)
					if node_parent.is_empty(): continue
				
				elif token.begins_with('instance=ExtResource("'):
					while !token.ends_with(')') and token_j < tokens.size(): token += ' ' + tokens[token_j]; token_j += 1;
					node_instance = _get_string_value(token)
					if node_instance.is_empty(): continue
			
			if node_parent.is_empty(): node_name = '.'
			elif node_parent != '.': node_parent = './' + node_parent
			
			var node_path : String = node_parent+'/'+node_name
			if node_parent.is_empty():
				node_path = node_name
			
			var j : int = i + 1
			
			while j < lines.size():
				if lines[j].begins_with('['):
					break
				
				line = lines[j]
				j += 1
				
				tokens = line.split(" = ", false, 1)
				if tokens.size() == 2:
					property_tree.save_property(path, node_path, tokens[0], tokens[1])
			
			if node_instance.is_empty():
				var tree_parent : String = ""
				for root in _dependency_roots.keys():
					if node_path.begins_with(root):
						tree_parent = root
						break
				
				if !tree_parent.is_empty():
					_dependency_tree[node_path] = tree_parent
					_Logger.write(str(i+1) + " processed edited node " + node_path + " of " + _dependency_roots[tree_parent])
				
				else:
					_Logger.write(str(i+1) + " processed node " + node_path)
			else:
				var node_instantiates_scene : String = _ext_resources[node_instance]
				_dependency_roots[node_path] = node_instantiates_scene
				_Logger.write(str(i+1) + " processed instantiated scene root node " + node_path + " as " + node_instantiates_scene)
			
			i = j
		
		else:
			i += 1


func run(symbol_table : SymbolTable) -> bool:
	_data = ""
	
	var lines : PackedStringArray = _source_data.split("\n")
	var i : int = 0
	while i < lines.size():
		var line : String = lines[i]
		if line.begins_with("\""):
			_data += line + "\n"
			i += 1
			continue
		
		if line.begins_with('[connection signal="') or line.begins_with('[node name="'):
			var node_paths : bool = false
			var tokens : PackedStringArray = line.split(" ", false)
			var token_i : int = 0
			while token_i < tokens.size():
				var token : String = tokens[token_i]
				token_i += 1
				
				if token.begins_with('signal="') or token.begins_with('method="') or token.begins_with('node_paths=PackedStringArray("') or node_paths:
					node_paths = (token.begins_with("node_paths") or node_paths) and token[-1] == ","
					
					var token_j : int = token_i
					if token.begins_with('signal="') or token.begins_with('method="'):
						while !token.ends_with('"') and token_j < tokens.size(): token += ' ' + tokens[token_j]; token_j += 1
					if token.begins_with('node_paths=PackedStringArray("'):
						while !token.ends_with(')') and token_j < tokens.size(): token += ' ' + tokens[token_j]; token_j += 1
					var name : String = _get_string_value(token)
					if name.is_empty(): continue
					
					var new_symbol : SymbolTable.Symbol = symbol_table.find_global_symbol(name)
					if new_symbol:
						line = _replace_first(line, name, str(new_symbol.name))
						_Logger.write(str(i+1) + " found symbol '" + name + "' = " + str(new_symbol.name))
		
		_data += line + "\n"
		i += 1
		
		if line.begins_with("[node") or line.begins_with("[sub_resource") or line.begins_with("[resource"):
			var node_name : String
			var node_parent : String
			
			var tokens : PackedStringArray = line.split(" ", false)
			var token_i : int = 0
			while token_i < tokens.size():
				var token : String = tokens[token_i]
				
				var token_j : int = token_i
				
				if token.begins_with('name="'):
					while !token.ends_with('"') and token_j < tokens.size(): token += ' ' + tokens[token_j]; token_j += 1
					node_name = _get_string_value(token)
					if node_name.is_empty(): continue
				elif token.begins_with('parent="'):
					while !token.ends_with('"') and token_j < tokens.size(): token += ' ' + tokens[token_j]; token_j += 1;
					node_parent = _get_string_value(token)
					if node_parent.is_empty(): continue
				
				token_i += 1
			
			if node_parent.is_empty(): node_name = '.'
			elif node_parent != '.': node_parent = './' + node_parent
			
			var node_path : String = node_parent+'/'+node_name
			if node_parent.is_empty():
				node_path = node_name
			
			var is_edited : bool = !line.contains("type=") and line.begins_with("[node")
			
			var tmp_lines : String
			var has_script : bool = line.contains("instance=") or line.contains('type="Animation"')
			var j : int = i
			var script_i : int = i
			var overwritten_keys : Dictionary = {}  # bootleg set
			while j < lines.size():
				if lines[j].begins_with("["):
					break
				
				tmp_lines += lines[j] + "\n"
				
				tokens = lines[j].split(" = ", false, 1)
				if tokens.size() == 2:
					if tokens[0] == "script":
						has_script = true
						script_i = j
						_Logger.write(str(i+1) + " found script " + line + " " + tokens[1])
					overwritten_keys[tokens[0]] = null
				
				j += 1
			
			# Rewrite export vars from instantiated scenes to the parent scenes
			if is_edited and _Settings.current.strip_editor_annotations:
				var inst_scene_path_root : String = node_path
				
				if _dependency_tree.has(node_path):
					inst_scene_path_root = _dependency_tree[node_path]
				
				if inst_scene_path_root == "." and not _dependency_roots.has("."):
					push_error(_dependency_roots, ' ', _dependency_tree, ' ', inst_scene_path_root, ' ', node_path, ' ', str(i+1), ' ', node_parent, ' ', node_name, ' ', path)
					push_error("hi")
					push_error("\n\n\n\n\n")
					
				var inst_scene : String = _dependency_roots[inst_scene_path_root]
				var inst_scene_prefix : String = inst_scene_path_root.rsplit("/", false, 1)[0]
				var inst_scene_relative_path : String = node_path.substr(inst_scene_prefix.length()+1)
				
				for key in _property_tree.get_key_list(inst_scene, inst_scene_relative_path):
					if !overwritten_keys.has(key):
						lines.insert(script_i+1, key + " = " + _property_tree.get_property(inst_scene, inst_scene_relative_path, key))
			
			if !has_script:
				_data += tmp_lines
				i = j
			else:
				j = mini(j, lines.size())
				
				while i < j:
					line = lines[i]
					tokens = line.split(" = ", false, 1)
					if tokens.size() == 2:
						if tokens[1].begins_with("NodePath(") and tokens[1].contains(":"):
							var node_path_ref : String = _read_string(tokens[1])
							var properties : PackedStringArray = node_path_ref.split(":", false)
							var new_path : String = properties[0]
							for property in properties.slice(1):
								var new_symbol : SymbolTable.Symbol = symbol_table.find_global_symbol(property)
								new_path += ":" + (str(new_symbol.name) if new_symbol else property)
							tokens[1] = 'NodePath("' + new_path + '")'
							line = tokens[0] + " = " + tokens[1]
							if node_path_ref != new_path:
								_Logger.write(str(i+1) + " found node path '" + node_path_ref + "' = " + new_path)
						
						var new_symbol : SymbolTable.Symbol = symbol_table.find_global_symbol(tokens[0])
						if new_symbol:
							line = str(new_symbol.name) + " = " + tokens[1]
							_Logger.write(str(i+1) + " found export var '" + tokens[0] + "' = " + str(new_symbol.name))
					elif line.begins_with('"method":'):
						var method : String = _read_string(line.trim_prefix('"method":'))
						var new_symbol : SymbolTable.Symbol = symbol_table.find_global_symbol(method)
						if new_symbol:
							line = '"method": &"' + str(new_symbol.name) + '"'
							_Logger.write(str(i+1) + " found method '" + method + "' = " + str(new_symbol.name))
					
					_data += line + "\n"
					i += 1
	
	_data = _data.strip_edges(false, true) + "\n"
	
	return true


func get_dependencies(source_data : String) -> Array[String]:
	var dependencies = []
	
	var lines : PackedStringArray = source_data.split("\n")
	var i : int = 0
	while i < lines.size():
		var line : String = lines[i]
		
		if line.begins_with('[ext_resource') and line.contains('type="PackedScene"'):
			var tokens : PackedStringArray = line.split(" ", false)
			var token_i : int = 0
			while token_i < tokens.size():
				var token : String = tokens[token_i]
				token_i += 1
				
				if token.begins_with('uid="'):
					var token_j : int = token_i
					
					while !token.ends_with('"') and token_j < tokens.size(): token += ' ' + tokens[token_j]; token_j += 1
					var uid : String = _get_string_value(token)
					if uid.is_empty(): continue
					
					dependencies.append(uid)
	
	return dependencies


func get_uid(source_data : String) -> String:
	# The First UID seems to be the resource's UID
	#if source_data.begins_with("[gd_scene") or source_data.begins_with("[gd_resource"):
	var tokens : PackedStringArray = source_data.split(" ", false)
	for token in tokens:
		if token.begins_with('uid="'):
			var uid : String = _get_string_value(token)
			if uid.is_empty(): continue
			
			return uid
	
	return ""


func _get_string_value(token : String) -> String:
	var start : int = token.find('"')
	var end : int = token.find('"', start + 1)
	if end == -1:
		return ""
	
	return token.substr(start + 1, end - (start + 1))


func get_source_data() -> String:
	return _source_data


func get_data() -> String:
	return _data


func set_data(custom : String) -> void:
	_data = custom


func _replace_first(str : String, replace : String, with : String) -> String:
	var idx : int = str.find(replace)
	if idx == -1:
		return str
	elif idx == 0:
		return with + str.substr(idx + replace.length())
	else:
		return str.substr(0, idx) + with + str.substr(idx + replace.length())


func _read_string(input : String) -> String:
	var out : String
	var str_end : String
	for char in input:
		if char == "'" or char == '"':
			if str_end:
				return out
			str_end = char
		elif str_end:
			out += char
	return out
