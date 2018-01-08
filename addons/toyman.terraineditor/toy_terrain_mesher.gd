tool

const TRIANGLE_HEIGHT = 0.866025403784439;

# Note:
# This is a very slow part of this plugin, due to GDScript mostly.
# I tried to optimize it without SurfaceTool to reduce calculations,
# but it didn't improve much.
# This plugin must be converted to C++/GDNative.

# inputHeights: array of arrays of floats
# inputNormals: arrays of arrays of Vector3
# x0, y0, widht, height: sub-rectangle to generate from the above grids
# returns: a Mesh
static func makeHeightmap(inputHeights, inputNormals, inputColors, x0, y0, widht, height):
	var maxX = x0 + widht;
	var maxY = y0 + height;

	var terrainSizeX = inputHeights.size() - 1;
	var terrainSizeY = 0;
	if inputHeights.size() > 0:
		terrainSizeY = inputHeights[0].size() - 1;

	if maxY >= terrainSizeY:
		maxY = terrainSizeY;
	if maxX >= terrainSizeX:
		maxX = terrainSizeX;

	var vertices = PoolVector3Array();
	var normals = PoolVector3Array();
	var colors = PoolColorArray();
	var indices = PoolIntArray();

	for y in range(y0, maxY + 1):
		var heightRow = inputHeights[y];
		var colorRow = inputColors[y];
		var normalRow = inputNormals[y];
		var xShift = 0.0;
		if (y % 2) > 0:
			xShift = 0.5;
		for x in range(x0, maxX + 1):
			vertices.push_back(Vector3(x - x0 + xShift, heightRow[x], (y - y0) * TRIANGLE_HEIGHT));
			colors.push_back(colorRow[x]);
			normals.push_back(normalRow[x]);

	if vertices.size() == 0:
		print('No vertices generated! ', x0, ', ', y0, ', ', widht, ', ', height);
		return null;

	var i = 0;
	for y in range(height):
		for x in range(widht):
			if (y % 2) > 0:
				indices.push_back(i);
				indices.push_back(i + widht + 2);
				indices.push_back(i + widht + 1);
				indices.push_back(i);
				indices.push_back(i + 1);
				indices.push_back(i + widht + 2);
			else:
				indices.push_back(i);
				indices.push_back(i + 1);
				indices.push_back(i + widht + 1);
				indices.push_back(i + 1);
				indices.push_back(i + widht + 2);
				indices.push_back(i + widht + 1);
			i += 1;
		i += 1;

	var arrays = [];
	arrays.resize(9);
	arrays[Mesh.ARRAY_VERTEX] = vertices;
	arrays[Mesh.ARRAY_NORMAL] = normals;
	arrays[Mesh.ARRAY_COLOR] = colors;
	arrays[Mesh.ARRAY_INDEX] = indices;

	var mesh = ArrayMesh.new();
	mesh.add_surface_from_arrays (Mesh.PRIMITIVE_TRIANGLES, arrays);

	return mesh;
