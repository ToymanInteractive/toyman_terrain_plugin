tool # ONLY because Godot doesn't report errors if I omit it ><'
const Util = preload('toy_terrain_utils.gd');
const Terrain = preload('toy_terrain.gd');

const MODE_ADD = 0;
const MODE_SUBTRACT = 1;
const MODE_SMOOTH = 2;
const MODE_FLATTEN = 3;
const MODE_TEXTURE = 4;
const MODE_COUNT = 5;

var _shape = [];
var _modulate = 1.0;
var _radius = 4;
var _hardness = 1.0;
var _sum = 0.0;
var _mode = MODE_ADD;
#var _mode_secondary = MODE_SUBTRACT;
var _channel = Terrain.DATA_HEIGHT;
var _sourceImage = null;
var _useUndoRedo = false;
var _flattenHeight = 0.0;

func _init():
	# So that it works even if no brush textures exist at all
	generate(_radius);

func generate(radius):
	if _sourceImage == null:
		generateProcedural(radius);
	else:
		generateFromImage(_sourceImage, radius);

func generateProcedural(radius):
	_radius = radius;
	var size = 2 * radius;
	_shape = Util.createGrid(size, size, 0);
	_sum = 0;
	for y in range(-radius, radius):
		for x in range(-radius, radius):
			var distance = Vector2(x, y).distance_to(Vector2(0, 0)) / float(radius);
			var height = clamp(1.0 - distance * distance * distance, 0.0, 1.0);
			_shape[y + radius][x + radius] = height;
			_sum += height;

func generateFromImage(image, radius = -1):
	if image.get_width() != image.get_height():
		print('Brush shape image must be square!');
		return;

	_sourceImage = image;

	if radius >= 0:
		_radius = radius;

	var size = _radius * 2;
	if size != image.get_width():
		image = Image.new();
		image.copy_from(_sourceImage);
		image.resize(size, size, Image.INTERPOLATE_CUBIC);

	_shape = Util.createGrid(size, size, 0);
	_sum = 0;

	image.lock();
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var color = image.get_pixel(x,y)
			var height = color.a;
			_shape[y][x] = height;
			_sum += height;
	image.unlock();

func setRadius(r):
	if r > 0 && r != _radius:
		_radius = r;
		generate(r);

func getRadius():
	return _radius;

func setHardness(hardness):
	_hardness = clamp(hardness, 0.0, 2.0);

func setMode(mode):
	assert(mode >= 0 && mode < MODE_COUNT);
	_mode = mode;
	if _mode == MODE_TEXTURE:
		_channel = Terrain.DATA_COLOR;
	else:
		_channel = Terrain.DATA_HEIGHT;

func getChannel():
	return _channel;

func getMode():
	return _mode;

func setModulate(newValue):
	_modulate = newValue;

func getFlattenHeight():
	return _flattenHeight;

func setFlattenHeight(height):
	_flattenHeight = height;

func setUndoRedo(use):
	_useUndoRedo = use;

func paintWorldPosition(terrain, wpos, overrideMode=-1, channel=0):
	var cellPosition = terrain.worldToCellPosition(wpos);
	var delta = _hardness * 1.0/60.0;

	var mode = _mode;
	if overrideMode != -1:
		mode = overrideMode;

	# Safety checks
	assert(!(_channel == Terrain.DATA_COLOR && typeof(_modulate) != TYPE_COLOR));

	if mode == MODE_ADD:
		_paintHeight(terrain, cellPosition.x, cellPosition.y, 50.0 * delta);
	elif mode == MODE_SUBTRACT:
		_paintHeight(terrain, cellPosition.x, cellPosition.y, -50.0 * delta);
	elif mode == MODE_SMOOTH:
		_smoothHeight(terrain, cellPosition.x, cellPosition.y, 4.0 * delta);
	elif mode == MODE_FLATTEN:
		_flattenHeight(terrain, cellPosition.x, cellPosition.y, _flattenHeight);
	elif mode == MODE_TEXTURE:
		_paintTexture(terrain, cellPosition.x, cellPosition.y, _modulate);
	else:
		error('Unknown paint mode ' + str(mode));

func _foreachXY(terrain, tx0, ty0, operator, channel, modifier=true):
	if modifier:
		terrain.setAreaDirty(tx0, ty0, _radius, _useUndoRedo, channel);

	var data = terrain.getDataChannel(channel);
	var brushRadius = _shape.size() / 2;

	operator.dst = data;

	for by in range(_shape.size()):
		var brushRow = _shape[by];
		for bx in range(brushRow.size()):
			var brushValue = brushRow[bx];
			var tx = tx0 + bx - brushRadius;
			var ty = ty0 + by - brushRadius;
			# TODO We could get rid if this `if` by calculating proper bounds beforehands
			if terrain.cellPositionIsValid(tx, ty):
				operator.exec(tx, ty, brushValue);

# TODO Update this part when Godot will support lambdas

class Operator:
	var dst = null;
	var opacity = 1.0;

class AddOperator extends Operator:
	var factor = 1.0;
	func exec(x, y, value):
		dst[y][x] = dst[y][x] + factor * value;

class LerpOperator extends Operator:
	var targetValue = 0.0;
	func exec(x, y, value):
		dst[y][x] = lerp(dst[y][x], targetValue, value * opacity);

class LerpOperatorColor extends Operator:
	var targetValue = Color(1, 1, 1, 1);
	func exec(x, y, value):
		dst[y][x] = dst[y][x].linear_interpolate(targetValue, value * opacity);

class SumOperator extends Operator:
	var sum = 0.0;
	func exec(x, y, value):
		sum += dst[y][x] * value;

func _paintHeight(terrain, tx0, ty0, factor=1.0):
	var operator = AddOperator.new();
	operator.factor = factor;
	_foreachXY(terrain, tx0, ty0, operator, _channel);

func _flattenHeight(terrain, tx0, ty0, height):
	var operator = LerpOperator.new();
	operator.targetValue = height;
	operator.opacity = clamp(_hardness, 0.0, 1.0);
	_foreachXY(terrain, tx0, ty0, operator,  _channel);

func _smoothHeight(terrain, tx0, ty0, factor=1.0):
	var sumOperator = SumOperator.new();
	_foreachXY(terrain, tx0, ty0, sumOperator, _channel, false);

	var lerpOperator = LerpOperator.new();
	lerpOperator.targetValue = sumOperator.sum / _sum;
	lerpOperator.opacity = clamp(_hardness, 0.0, 1.0);
	_foreachXY(terrain, tx0, ty0, lerpOperator, _channel);

func _paintTexture(terrain, tx0, ty0, factor=Color(1, 1, 1, 1)):
	var operator = LerpOperatorColor.new();
	operator.targetValue = factor;
	operator.opacity = clamp(_hardness, 0.0, 1.0);
	_foreachXY(terrain, tx0, ty0, operator, _channel);
