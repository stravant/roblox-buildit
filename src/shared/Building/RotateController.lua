--!strict

-- Edit-mode Rotate tool: click and hold a composite segment, then drag
-- to swing it about a joint. Joint choice: of all the composite's
-- joints, pick the one whose cut leaves the clicked segment in the
-- SMALLEST connected component — that component rotates. Clicking a
-- hand turns just the hand (wrist); clicking an arm turns arm+hand
-- (shoulder); either side of a lone hinge can be rotated. Release
-- commits (one undo recording); RMB/Esc cancels.

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local kRaycastDistance = 500

type JointInfo = {
	parentPart: BasePart,
	childPart: BasePart,
	childPivot: Attachment,
}

type Session = {
	pivotPosition: Vector3,
	axis: Vector3,
	jointType: string, -- "Hinge" rotates about axis; "Slider" translates along it
	startVector: Vector3,
	startParameter: number,
	initialCFrames: { [BasePart]: CFrame },
	recording: string?,
	connections: { RBXScriptConnection },
}

export type StartOptions = {
	plugin: Plugin?,
}

export type Controller = {
	stop: () -> (),
}

local RotateController = {}

-- Collect the composite's joints from its JointPivot attachments.
local function collectJoints(model: Model): { [number]: JointInfo }
	local bySegment: { [number]: BasePart } = {}
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") then
			local index = child:GetAttribute("JointSegment")
			if type(index) == "number" then
				bySegment[index] = child
			end
		end
	end
	local joints: { [number]: JointInfo } = {}
	for _, part in bySegment do
		for _, attachment in part:GetChildren() do
			if not attachment:IsA("Attachment") or attachment.Name:match("^JointPivot") == nil then
				continue
			end
			local jointIndex = attachment:GetAttribute("JointIndex")
			if type(jointIndex) ~= "number" then
				jointIndex = 1
			end
			local info = joints[jointIndex :: number]
			if info == nil then
				info = { parentPart = part, childPart = part, childPivot = attachment }
				joints[jointIndex :: number] = info
			end
			if attachment:GetAttribute("JointRole") == "child" then
				(info :: JointInfo).childPart = part;
				(info :: JointInfo).childPivot = attachment
			else
				(info :: JointInfo).parentPart = part
			end
		end
	end
	return joints
end

-- Connected component of the joint graph containing `start` when the
-- joint `cutIndex` is removed.
local function componentContaining(
	joints: { [number]: JointInfo },
	cutIndex: number,
	start: BasePart
): { BasePart }
	local component: { [BasePart]: boolean } = { [start] = true }
	local grew = true
	while grew do
		grew = false
		for index, info in joints do
			if index == cutIndex then
				continue
			end
			if component[info.parentPart] and not component[info.childPart] then
				component[info.childPart] = true
				grew = true
			end
			if component[info.childPart] and not component[info.parentPart] then
				component[info.parentPart] = true
				grew = true
			end
		end
	end
	local list = {}
	for part in component do
		table.insert(list, part)
	end
	return list
end

local function componentVolume(parts: { BasePart }): number
	local volume = 0
	for _, part in parts do
		local size = part.Size
		volume += size.X * size.Y * size.Z
	end
	return volume
end

function RotateController.start(options: StartOptions?): Controller
	local opts: StartOptions = options or {}
	local pluginRef = opts.plugin

	local mSession: Session? = nil

	local function mouseRay(): Ray
		local camera = workspace.CurrentCamera
		local mouse = UserInputService:GetMouseLocation()
		local inset = GuiService:GetGuiInset()
		return camera:ViewportPointToRay(mouse.X - inset.X, mouse.Y - inset.Y)
	end

	-- Intersect the mouse ray with the rotation plane; nil when parallel.
	local function planeVector(session: Session): Vector3?
		local ray = mouseRay()
		local denominator = ray.Direction:Dot(session.axis)
		if math.abs(denominator) < 1e-4 then
			return nil
		end
		local t = (session.pivotPosition - ray.Origin):Dot(session.axis) / denominator
		if t < 0 then
			return nil
		end
		local hit = ray.Origin + ray.Direction * t
		local vector = hit - session.pivotPosition
		vector -= session.axis * vector:Dot(session.axis)
		if vector.Magnitude < 0.05 then
			return nil
		end
		return vector.Unit
	end

	-- Parameter along the joint axis of the point on the axis line
	-- closest to the mouse ray; nil when the ray runs parallel to it.
	local function axisParameter(session: Session): number?
		local ray = mouseRay()
		local b = session.axis:Dot(ray.Direction)
		local denominator = 1 - b * b
		if denominator < 1e-6 then
			return nil
		end
		local w = session.pivotPosition - ray.Origin
		return (b * w:Dot(ray.Direction) - w:Dot(session.axis)) / denominator
	end

	local function finishRecording(session: Session, commit: boolean)
		if pluginRef == nil then
			return
		end
		if session.recording ~= nil then
			ChangeHistoryService:FinishRecording(
				session.recording,
				if commit
					then Enum.FinishRecordingOperation.Commit
					else Enum.FinishRecordingOperation.Cancel
			)
			session.recording = nil
		elseif commit then
			ChangeHistoryService:SetWaypoint("BuildIt: Rotate joint")
		end
	end

	local function endSession(commit: boolean)
		local session = mSession
		if session == nil then
			return
		end
		mSession = nil
		for _, connection in session.connections do
			connection:Disconnect()
		end
		if not commit then
			for part, cframe in session.initialCFrames do
				part.CFrame = cframe
			end
		end
		finishRecording(session, commit)
	end

	local function beginSession(hit: BasePart, model: Model)
		local joints = collectJoints(model)
		-- Rotate the SMALLEST component containing the clicked segment:
		-- clicking a hand turns the hand, clicking the arm turns arm+hand.
		local chosen: JointInfo? = nil
		local moving: { BasePart }? = nil
		local bestCount = math.huge
		local bestVolume = math.huge
		for index, info in joints do
			local component = componentContaining(joints, index, hit)
			-- Cutting an unrelated joint leaves the whole model connected
			-- through other joints; only proper splits are candidates.
			if #component == 0 or table.find(component, info.parentPart) and table.find(component, info.childPart) then
				continue
			end
			local volume = componentVolume(component)
			if #component < bestCount or (#component == bestCount and volume < bestVolume) then
				bestCount = #component
				bestVolume = volume
				chosen = info
				moving = component
			end
		end
		if chosen == nil or moving == nil then
			return -- no joint separates this segment from the rest
		end
		local joint = chosen :: JointInfo

		local pivotWorld = joint.childPart.CFrame * joint.childPivot.CFrame
		local session: Session = {
			pivotPosition = pivotWorld.Position,
			axis = pivotWorld.YVector,
			jointType = (joint.childPivot:GetAttribute("JointType") :: string?) or "Hinge",
			startVector = Vector3.xAxis,
			startParameter = 0,
			initialCFrames = {},
			recording = nil,
			connections = {},
		}
		for _, part in moving :: { BasePart } do
			session.initialCFrames[part] = part.CFrame
		end
		if session.jointType == "Slider" then
			local start = axisParameter(session)
			if start == nil then
				return -- looking along the slide axis
			end
			session.startParameter = start :: number
		else
			local start = planeVector(session)
			if start == nil then
				return -- looking edge-on at the rotation plane
			end
			session.startVector = start :: Vector3
		end
		if pluginRef ~= nil then
			session.recording = ChangeHistoryService:TryBeginRecording("BuildIt: Rotate joint")
		end
		mSession = session

		table.insert(session.connections, RunService.RenderStepped:Connect(function()
			if session.jointType == "Slider" then
				local current = axisParameter(session)
				if current == nil then
					return
				end
				local offset = session.axis * ((current :: number) - session.startParameter)
				for part, initial in session.initialCFrames do
					part.CFrame = initial + offset
				end
				return
			end
			local current = planeVector(session)
			if current == nil then
				return
			end
			local vector = current :: Vector3
			local angle = math.atan2(
				session.startVector:Cross(vector):Dot(session.axis),
				session.startVector:Dot(vector)
			)
			local spin = CFrame.new(session.pivotPosition)
				* CFrame.fromAxisAngle(session.axis, angle)
				* CFrame.new(-session.pivotPosition)
			for part, initial in session.initialCFrames do
				part.CFrame = spin * initial
			end
		end))

		table.insert(session.connections, UserInputService.InputEnded:Connect(function(input, _gameProcessed)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				endSession(true)
			end
		end))

		table.insert(session.connections, UserInputService.InputBegan:Connect(function(input, _gameProcessed)
			if
				input.UserInputType == Enum.UserInputType.MouseButton2
				or input.KeyCode == Enum.KeyCode.Escape
			then
				endSession(false)
			end
		end))
	end

	local mPressConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end
		if mSession ~= nil then
			return
		end
		local ray = mouseRay()
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = {}
		local result = workspace:Raycast(ray.Origin, ray.Direction * kRaycastDistance, params)
		if result == nil then
			return
		end
		local model = result.Instance:FindFirstAncestorOfClass("Model")
		if model ~= nil and model:GetAttribute("JointType") ~= nil then
			beginSession(result.Instance, model)
		end
	end)

	local function stop()
		endSession(false)
		mPressConnection:Disconnect()
	end

	return {
		stop = stop,
	}
end

return RotateController
