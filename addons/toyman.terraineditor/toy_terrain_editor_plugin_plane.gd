tool
extends HBoxContainer

signal brush_height_changed;
signal brush_opacity_changed;
signal brush_radius_changed;
signal brush_shape_changed;
signal brush_texture_changed;
signal landscape_tool_changed;

onready var _landscapeToolBrushRaise = get_node('tools-container/tools/brush-raise');
onready var _landscapeToolBrushSetHeight = get_node('tools-container/tools/brush-set-height');
onready var _landscapeToolBrushBlur = get_node('tools-container/tools/brush-blur');
onready var _landscapeToolBrushTexture = get_node('tools-container/tools/brush-texture');
onready var _landscapeToolsLabel = get_node('tools-container/tool-label');
onready var _brushRadiusSlider = get_node('tool-settings-container/brush-size-slider');
onready var _brushRadiusValue = get_node('tool-settings-container/brush-size-value');
onready var _brushOpacitySlider = get_node('tool-settings-container/brush-opacity-slider');
onready var _brushOpacityValue = get_node('tool-settings-container/brush-opacity-value');
onready var _brushHeightLabel = get_node('tool-settings-container/brush-height-label');
onready var _brushHeightValue = get_node('tool-settings-container/brush-height-value');
onready var _shapeSelector = get_node('tool-shapes');
onready var _textureSelector = get_node('textures');

func _ready():
	_landscapeToolBrushRaise.connect('button_down', self, '_onLandscapeToolChange', [0]);
	_landscapeToolBrushSetHeight.connect('button_down', self, '_onLandscapeToolChange', [1]);
	_landscapeToolBrushBlur.connect('button_down', self, '_onLandscapeToolChange', [2]);
	_landscapeToolBrushTexture.connect('button_down', self, '_onLandscapeToolChange', [3]);
	_brushRadiusSlider.connect('value_changed', self, '_onBrushSizeSliderValueChanged');
	_brushRadiusValue.connect('text_entered', self, '_onBrushSizeLineEditEntered');
	_brushOpacitySlider.connect('value_changed', self, '_onBrushOpacitySliderValueChanged');
	_brushOpacityValue.connect('text_entered', self, '_onBrushOpacityLineEditEntered');
	_brushHeightValue.connect('text_entered', self, '_onBrushHeightLineEditEntered');
	_shapeSelector.connect('item_selected', self, '_onBrushShapeSelected');
	_textureSelector.connect('item_selected', self, '_onTextureSelected');

	_onLandscapeToolChange(0);
	_brushRadiusSlider.set_value(4);
	_brushOpacitySlider.set_value(25);
	_brushHeightValue.set_text('0');
	_onBrushSizeSliderValueChanged(4);
	_onBrushOpacitySliderValueChanged(25);
	_onBrushHeightLineEditEntered('0');

	_buildShapeSelector();
	_buildTextureSelector();
	if _shapeSelector.get_item_count() > 6:
		_shapeSelector.select(6);
		_onBrushShapeSelected(6);

func setTextures(textures):
	_textureSelector.clear();
	for tex in textures:
		_textureSelector.add_icon_item(tex);

func _buildShapeSelector():
	_shapeSelector.clear();
	_shapeSelector.set_same_column_width(true);
	_shapeSelector.set_max_columns(0);

	var brushDir = get_filename().get_base_dir() + '/brushes';
	var brushPaths = _getFileList(brushDir, 'png');
	for path in brushPaths:
		var brushTexture = load(brushDir + '/' + path);
		if brushTexture != null:
			_shapeSelector.add_icon_item(brushTexture);
			_shapeSelector.set_item_tooltip(_shapeSelector.get_item_count() - 1, brushTexture.get_name());

func _buildTextureSelector():
	_textureSelector.set_same_column_width(true);
	_textureSelector.set_max_columns(0);
	_textureSelector.set_fixed_icon_size(Vector2(32,32));

func _onLandscapeToolChange(toolIndex):
	var toolNames = ['raise', 'set-height', 'blur', 'texture'];
	var toolLabels = ['Raise / Lower Terrain', 'Paint Height', 'Smooth Height', 'Paint Texture'];
	var toolButtons = [_landscapeToolBrushRaise, _landscapeToolBrushSetHeight, _landscapeToolBrushBlur, _landscapeToolBrushTexture];

	_landscapeToolsLabel.set_text(toolLabels[toolIndex]);
	_brushHeightLabel.set_visible(toolIndex == 1);
	_brushHeightValue.set_visible(toolIndex == 1);

	for buttonIndex in range(toolButtons.size()):
		if buttonIndex != toolIndex:
			toolButtons[buttonIndex].set_pressed(false);
			toolButtons[buttonIndex].set_disabled(false);
		else:
			toolButtons[buttonIndex].set_disabled(true);

	emit_signal('landscape_tool_changed', toolNames[toolIndex]);

func _onBrushSizeSliderValueChanged(value):
	emit_signal('brush_radius_changed', value);
	_brushRadiusValue.set_text(str(value));

func _onBrushSizeLineEditEntered(text):
	var value = text.to_int();
	_brushRadiusSlider.set_value(value);

func _onBrushShapeSelected(index):
	emit_signal('brush_shape_changed', _shapeSelector.get_item_icon(index));

func _onTextureSelected(index):
	emit_signal('brush_texture_changed', index);

func _onBrushOpacitySliderValueChanged(value):
	emit_signal('brush_opacity_changed', value * 0.01);
	_brushOpacityValue.set_text(str(value));

func _onBrushOpacityLineEditEntered(text):
	var value = text.to_int();
	_brushOpacitySlider.set_value(value);

func _onBrushHeightLineEditEntered(text):
	var value = text.to_int();
	emit_signal('brush_height_changed', value);

static func _getFileList(dirPath, exts):
	if typeof(exts) == TYPE_STRING:
		exts = [exts];
	var dir = Directory.new();
	var openCode = dir.open(dirPath);
	if openCode != 0:
		print('Cannot open directory! Code: ' + str(openCode));
		return null;
	var list = [];
	dir.list_dir_begin();
	for i in range(0, 1000):
		var file = dir.get_next();
		if file == '':
			break;
		if !dir.current_is_dir():
			var fileExtension = file.get_extension();
			for ext in exts:
				if ext == fileExtension:
					list.append(file);
					break;
	return list;
