using WGPUCore
using WGPUgfx
using LinearAlgebra
using StaticArrays
using Rotations
using CoordinateTransformations

export defaultLighting, Lighting, lookAtRightHanded, 
	translateLighting, translate, scaleTransform,
	getUniformBuffer, getUniformData


mutable struct Lighting
	gpuDevice
	position
	specularColor
	ambientIntensity
	diffuseIntensity
	specularIntensity
	specularShininess
	uniformData
	uniformBuffer

	function Lighting(
		position,
		specularColor,
		ambientIntensity,
		diffuseIntensity,
		specularIntensity,
		specularShininess,
	)
		lighting = new(
			nothing,
			position,
			specularColor,
			ambientIntensity,
			diffuseIntensity,
			specularIntensity,
			specularShininess,
			nothing, 
			nothing
		)
		uniformData = computeUniformData(lighting)
	end
end


function prepareObject(gpuDevice, lighting::Lighting)
	uniformDataBytes = toByteArray(lighting.uniformData)
	(uniformBuffer, _) = WGPUCore.createBufferWithData(
		gpuDevice,
		"LightingBuffer",
		uniformDataBytes,
		["Uniform", "CopyDst", "CopySrc"] # CopySrc during development only
	)
	setfield!(lighting, :uniformBuffer, uniformBuffer)
	setfield!(lighting, :gpuDevice, gpuDevice)
	return lighting
end


function preparePipeline(gpuDevice, scene, light::Lighting; binding=1)
	uniformBuffer = getfield(light, :uniformBuffer)
	push!(scene.bindingLayouts, getBindingLayouts(light; binding=binding)...)
	push!(scene.bindings, getBindings(light, uniformBuffer; binding=binding)...)
end


function computeUniformData(lighting::Lighting)
	UniformType = getproperty(WGSLTypes, :LightingUniform)
	uniformData = cStruct(UniformType)
	uniformData.position = lighting.position
	uniformData.specularColor = lighting.specularColor
	uniformData.diffuseIntensity = lighting.diffuseIntensity
	uniformData.ambientIntensity = lighting.ambientIntensity
	uniformData.specularIntensity = lighting.specularIntensity
	uniformData.specularShininess = lighting.specularShininess
	return uniformData
end


function defaultLighting()
	position = [1.0, 1.0, 1.0, 1.0] .|> Float32
	specularColor = [1.0, 1.0, 1.0, 1.0] .|> Float32
	ambientIntensity = 1.0 |> Float32
	diffuseIntensity = 1.0 |> Float32
	specularIntensity = 1.0 |> Float32
	specularShininess = 1.0 |> Float32
	return Lighting(
		position,
		specularColor,
		ambientIntensity,
		diffuseIntensity,
		specularIntensity,
		specularShininess,
	)
end

function setVal!(lighting::Lighting, ::Val{N}, v) where N
	setfield!(lighting, N, v)
	UniformType = getproperty(WGSLTypes, :LightingUniform)
	offset = Base.fieldoffset(UniformType, Base.fieldindex(UniformType, N))
	io = getfield(lighting, :uniformData)
	seek(io, offset)
	write(io, v)
	seek(io, 0)
end

function setVal!(lighting::Lighting, ::Val{:uniformData}, v)
	UniformType = getproperty(WGSLTypes, :LightingUniform)
	t = UniformType(v) |> Ref
	io = getfield(lighting, :uniformData)
	seek(io, 0)
	unsafe_write(io, t, sizeof(t))
	seek(io, 0)
end

Base.setproperty!(lighting::Lighting, f::Symbol, v) = begin
	setVal!(lighting, Val(f), v)
	updateUniformBuffer(lighting)
end


function getVal(lighting::Lighting, ::Val{:uniformBuffer})
	return readUniformBuffer(lighting)
end



function getVal(lighting::Lighting, ::Val{:uniformData})
	UniformType = getproperty(WGSLTypes, :LightingUniform)
	t = Ref{UniformType}()
	io = getfield(lighting, :uniformData)
	seek(io, 0)
	unsafe_read(io, t, sizeof(UniformType))
	seek(io, 0)
	t[]
end

function getVal(lighting::Lighting, ::Val{N}) where N
	return getfield(lighting, N)
end

Base.getproperty(lighting::Lighting, f::Symbol) = begin
	getVal(lighting, Val(f))
end


function translateLighting(lighting::Lighting)
	(x, y, z) = (lighting.eye...,)
	return LinearMap(
		@SMatrix(
			[
				1 	0 	0 	x;
				0 	1 	0 	y;
				0 	0 	1 	z;
				0 	0 	0 	1;
			]
		) .|> Float32
	) |> inv
end


"""
# Usage
bb1 = [20, 20, 400, 400]
bb2 = [40, 60, 500, 600]

transform = windowingTransform(bb1, bb2)

transform([upperCoords(bb1)..., 0, 0])

# Should write tests on it
"""


function lookAtRightHanded(lighting::Lighting)
	eye = lighting.eye
	lookat = lighting.lookat
	up = lighting.up
	w = -(eye .- lookat) |> normalize
	u =	cross(up, w) |> normalize
	v = cross(w, u)
	m = Matrix{Float32}(I, (4, 4))
	m[1:3, 1:3] .= (cat([u, v, w]..., dims=2) |> adjoint .|> Float32 |> collect)
	return LinearMap(m) ∘ translateLighting(lighting)
end


function getUniformData(lighting::Lighting)
	return lighting.uniformData
end


function updateUniformBuffer(lighting::Lighting)
	data = getfield(lighting, :uniformData).data
	# @info :UniformBuffer lighting.uniformData
	WGPUCore.writeBuffer(
		lighting.gpuDevice.queue, 
		getfield(lighting, :uniformBuffer),
		data,
	)
end


function readUniformBuffer(lighting::Lighting)
	UniformType = getproperty(WGSLTypes, :LightingUniform)
	data = WGPUCore.readBuffer(
		lighting.gpuDevice,
		getfield(lighting, :uniformBuffer),
		0,
		getfield(lighting, :uniformBuffer).size
	)
	datareinterpret = reinterpret(UniformType, data)[1]
	# @info "Received Buffer" datareinterpret
end


function getUniformBuffer(lighting::Lighting)
	getfield(lighting, :uniformBuffer)
end


function getShaderCode(lighting::Lighting; binding=0)
	shaderSource = quote
		struct LightingUniform
			position::Vec4{Float32}
			specularColor::Vec4{Float32}
			ambientIntensity::Float32
			diffuseIntensity::Float32
			specularIntensity::Float32
			specularShininess::Float32
		end
		@var Uniform 0 $binding lighting::@user LightingUniform
	end
	return shaderSource
end


function getVertexBufferLayout(lighting::Lighting; offset=0)
	WGPUCore.GPUVertexBufferLayout => []
end


function getBindingLayouts(lighting::Lighting; binding=0)
	bindingLayouts = [
		WGPUCore.WGPUBufferEntry => [
			:binding => binding,
			:visibility => ["Vertex", "Fragment"],
			:type => "Uniform"
		],
	]
	return bindingLayouts
end


function getBindings(lighting::Lighting, uniformBuffer; binding=0)
	bindings = [
		WGPUCore.GPUBuffer => [
			:binding => binding,
			:buffer  => uniformBuffer,
			:offset  => 0,
			:size    => uniformBuffer.size
		],
	]
end

