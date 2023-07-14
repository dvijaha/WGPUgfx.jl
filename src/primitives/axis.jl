export defaultAxis, MainAxis

mutable struct MainAxis <: Renderable
	gpuDevice
	topology
	vertexData
	colorData
	indexData
	uniformData
	uniformBuffer
	indexBuffer
	vertexBuffer
	pipelineLayout
	renderPipeline
end


function defaultAxis(; origin=[0, 0, 0], len=1.0)
	vertexData = cat([
		[origin[1], 		origin[2], 			origin[3], 			1],
		[origin[1] + len, 	origin[2], 			origin[3], 			1],
		[origin[1], 		origin[2], 			origin[3], 			1],
		[origin[1], 		origin[2] + len, 	origin[3], 			1],
		[origin[1], 		origin[2], 			origin[3], 			1],
		[origin[1], 		origin[2], 			origin[3] + len, 	1],
	]..., dims=2) .|> Float32

	unitColor = cat([
		[0.8, 0.1, 0.1, 1],
		[0.1, 0.8, 0.1, 1],
		[0.1, 0.1, 0.8, 1],
	]..., dims=2) .|> Float32

	colorData = repeat(unitColor, inner=(1, 2))

	indexData = cat([
		[0, 1],
		[2, 3],
		[4, 5]
	]..., dims=2) .|> UInt32

	MainAxis(
		nothing,
		"LineList",
		vertexData,
		colorData,
		indexData,
		nothing,
		nothing,
		nothing,
		nothing,
		nothing,
		nothing,
	)
end
