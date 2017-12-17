tool
extends EditorPlugin

const ToyTerrain = preload('toy_terrain.gd');
const ToyTerrainIcon = preload('icons/toy-terrain.png');
const ToyTerrainBrush = preload('toy_terrain_brush.gd');

var _panel = null;
var _selectedObject = null;

var _brush = null;
var _undoCallbackDisabled = false;
var _textureColors = [];
var _pressed = false;

func _enter_tree():
	add_custom_type('Terrain', 'Node', ToyTerrain, ToyTerrainIcon);

	_brush = ToyTerrainBrush.new();
	_brush.setUndoRedo(true);

	_panel = preload('toy_terrain_editor_plugin_plane.tscn').instance();
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_BOTTOM, _panel);
	_panel.connect('brush_height_changed', self, '_onBrushHeightChanged');
	_panel.connect('brush_opacity_changed', self, '_onBrushOpacityChanged');
	_panel.connect('brush_radius_changed', self, '_onBrushRadiusChanged');
	_panel.connect('brush_shape_changed', self, '_onBrushShapeChanged');
	_panel.connect('brush_texture_changed', self, '_onBrushTextureChanged');
	_panel.connect('landscape_tool_changed', self, '_onLandscapeToolChanged');
	_panel.hide();
	pass;

func _exit_tree():
	_panel.free();
	_panel = null;

	remove_custom_type('Terrain');

func handles(object):
	return object is ToyTerrain;

func edit(object):
	if object is ToyTerrain:
		_selectedObject = object;
		var info = _loadTexturesInfo(_selectedObject);
		if info != null:
			_textureColors = info.colors;
			# TODO These textures should be updated if they are changed on the material
			_panel.setTextures(info.textures);
		else:
			_textureColors = null;
			_panel.setTextures([]);
	else:
		_selectedObject = null;

func forward_spatial_gui_input(camera, event):
	if _selectedObject != null && _selectedObject is ToyTerrain:
		return _editLandscape(camera, event);
	else:
		return false;

func _editLandscape(camera, event):
	if !(event is InputEventMouse):
		return false;

	var rayOrigin = camera.project_ray_origin(event.position);
	var rayDir = camera.project_ray_normal(event.position);

	if _selectedObject.material != null:
		var hitPosition = _selectedObject.raycast(rayOrigin, rayDir);
		if hitPosition != null:
			_selectedObject.material.set_shader_param('cursor_position', Vector2(hitPosition.x + _selectedObject.origin.x, hitPosition.z + _selectedObject.origin.x));
			_selectedObject.material.set_shader_param('cursor_radius', _brush.getRadius());
		else:
			_selectedObject.material.set_shader_param('cursor_position', Vector2(0, 0));
			_selectedObject.material.set_shader_param('cursor_radius', 0);

	var eventCaptured = false;

	if event is InputEventMouseButton && (event.button_index == BUTTON_LEFT || event.button_index == BUTTON_RIGHT):
		if !event.is_pressed():
			_pressed = false;

		# Need to check modifiers before capturing the event because they are used in navigation schemes
		if !event.control && !event.alt:

			if event.is_pressed():
				_pressed = true;
			eventCaptured = true;

			if !_pressed:
				var data = _selectedObject.popUndoRedoData(_brush.getChannel());
				var ur = get_undo_redo();
				ur.create_action("Paint terrain");
				ur.add_undo_method(self, "_paintUndoRedo", _selectedObject, data.undo);
				ur.add_do_method(self, "_paintUndoRedo", _selectedObject, data.redo);
				# Callback is disabled because data is too huge to be executed a second time
				_undoCallbackDisabled = true;
				ur.commit_action();
				_undoCallbackDisabled = false;

	elif _pressed && event is InputEventMouseMotion:
		if _brush.getMode() == ToyTerrainBrush.MODE_ADD && Input.is_mouse_button_pressed(BUTTON_RIGHT):
			_paint(_selectedObject, camera, event.position, ToyTerrainBrush.MODE_SUBTRACT);
			eventCaptured = true;

		elif Input.is_mouse_button_pressed(BUTTON_LEFT):
			_paint(_selectedObject, camera, event.position);
			eventCaptured = true;

	return eventCaptured;

func _paint(landscape, camera, mousePosition, mode=-1):
	var rayOrigin = camera.project_ray_origin(mousePosition);
	var rayDir = camera.project_ray_normal(mousePosition);

	var hitPosition = landscape.raycast(rayOrigin, rayDir);
	if hitPosition != null:
		_brush.paintWorldPosition(landscape, hitPosition, mode);

func _paintUndoRedo(landscape, data):
	if !_undoCallbackDisabled:
		landscape.applyChunksData(data);

func _loadTexturesInfo(terrain):
	var mat = terrain.getMaterial();
	if mat == null:
		return;
	if !(mat is ShaderMaterial):
		print("Terrain material isn't a ShaderMaterial")
		return null

	var material_path = mat.get_path()
	var meta_path = material_path.substr(0, material_path.length() - material_path.extension().length())
	meta_path += "shadermeta"

	var file = File.new()
	if not file.file_exists(meta_path):
		return null

	var ret = file.open(meta_path, File.READ)
	if ret != 0:
		print("Couldn't open ", meta_path, " error ", ret)
		return null

	var json = file.get_as_text()
	file.close()
	var data = {}
	var parseResult = data.parse_json(json)
	if parseResult != 0:
		print("Failed to parse json, error ", parseResult)
		return null

	if data.has("zylann.terrain") == false:
		print("No terrain data in ", meta_path)
		return null
	data = data["zylann.terrain"]

	if data.has("texture_colors") == false:
		print("Terrain meta has no texture info ", meta_path)
		return null
	var textures_data = data.texture_colors

	var textures = []
	var colors = []

	for k in textures_data:
		var v = textures_data[k]
		var color = Color(v[0], v[1], v[2], v[3])
		var texture = mat.get_shader_param(k)
		if typeof(texture) != TYPE_OBJECT or texture is Texture == false:
			print("Shader param ", k, " is not a Texture: ", texture)
			texture = null
		textures.push_back(texture)
		colors.push_back(color)

	return {
		"textures": textures,
		"colors": colors
	}

func make_visible(visible):
	if _panel != null:
		if visible:
			_panel.show();
		else:
			_panel.hide();

func _onBrushHeightChanged(value):
	_brush.setFlattenHeight(value);

func _onBrushOpacityChanged(value):
	_brush.setHardness(value);

func _onBrushRadiusChanged(value):
	_brush.setRadius(value);

func _onBrushShapeChanged(value):
	assert(value is Texture);
	_brush.generateFromImage(value.get_data());

func _onBrushTextureChanged(tex):
	if typeof(tex) == TYPE_INT:
		_brush.setModulate(_textureColors[tex]);

func _onLandscapeToolChanged(name):
	if name == 'raise':
		_brush.setMode(ToyTerrainBrush.MODE_ADD);
	elif name == 'set-height':
		_brush.setMode(ToyTerrainBrush.MODE_FLATTEN);
	elif name == 'blur':
		_brush.setMode(ToyTerrainBrush.MODE_SMOOTH);
	elif name == 'texture':
		_brush.setMode(ToyTerrainBrush.MODE_TEXTURE);
