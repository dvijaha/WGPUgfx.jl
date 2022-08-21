module EventsMod

using WGPU


mutable struct MouseState
	leftClick
	rightClick
	middleClick
	prevPosition
	speed
end

mouseState = MouseState(false, false, false, (0, 0), (0.01, 0.01))

istruthy(::Val{GLFW.PRESS}) = true
istruthy(::Val{GLFW.RELEASE}) = false

function setMouseState(mouse, ::Val{GLFW.MOUSE_BUTTON_1}, state)
	mouse.leftClick = istruthy(Val(state))
end

function setMouseState(mouse, ::Val{GLFW.MOUSE_BUTTON_2}, state)
	mouse.rightClick = istruthy(Val(state))
end

function setMouseState(mouse, ::Val{GLFW.MOUSE_BUTTON_3}, state)
	mouse.middleClick = istruthy(Val(state))
	mat = Matrix{Float32}(I, (4, 4))
	a = camera.uniformData
	a[1:3, 1:3] = mat[1:3, 1:3]
	camera.uniformData = a
end

WGPU.setMouseButtonCallback(
	canvas, 
	(_, button, action, a) -> begin
		@info GLFW.MouseButton button action a mouseState
		setMouseState(mouseState, Val(button), action)
	end
)

WGPU.setScrollCallback(
	canvas,
	(_, xoff, yoff) -> begin
		@info "MouseScroll" xoff, yoff
		camera.scale = camera.scale .+ yoff.*maximum(mouseState.speed)
	end
)


# TODO camera.up will be useful in reasonable movements
WGPU.setCursorPosCallback(
	canvas, 
	(_, x, y) -> begin
		@info "Mouse Position" x, y
		if all(((x, y) .- canvas.size) .< 0)
			if mouseState.leftClick
				delta = (mouseState.prevPosition .- (x, y)).*mouseState.speed
				@info delta
				rot = RotXY(delta...)
				mat = Matrix{Float32}(I, (4, 4))
				mat[1:3, 1:3] = rot
				camera.uniformData = camera.uniformData*mat 
				mouseState.prevPosition = (x, y)
			elseif mouseState.rightClick
				delta = (mouseState.prevPosition .- (x, y)).*mouseState.speed
				mat = Matrix{Float32}(I, (4, 4))
				mat[1:3, 3] .= [delta..., 0]
				camera.uniformData = camera.uniformData*mat
				mouseState.prevPosition = (x, y)
			elseif mouseState.middleClick
				mat = Matrix{Float32}(I, (4, 4))
				camera.uniformData = mat
			else
				mouseState.prevPosition = (x, y)
			end
		end
	end
)

struct Event
end


end
