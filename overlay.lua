-- Meow :3333
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui", 10) or localPlayer.PlayerGui
local oldOverlay = playerGui:FindFirstChild("SpotifyOverlay")
if oldOverlay then
	oldOverlay:Destroy()
end
local RAILWAY_URL = "https://player-production-7e33.up.railway.app"
local musicUrl = RAILWAY_URL .. "/music"
local controlUrl = RAILWAY_URL .. "/control/"
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "SpotifyOverlay"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui
local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
mainFrame.Size = UDim2.new(0, 450, 0, 80)
mainFrame.Position = UDim2.new(0.5, -225, 1, -100)
mainFrame.BackgroundColor3 = Color3.fromRGB(16, 16, 19)
mainFrame.BackgroundTransparency = 0.12
mainFrame.BorderSizePixel = 0
mainFrame.Parent = screenGui
local uiCorner = Instance.new("UICorner")
uiCorner.CornerRadius = UDim.new(0, 18)
uiCorner.Parent = mainFrame
local glassStroke = Instance.new("UIStroke")
glassStroke.Color = Color3.fromRGB(255, 255, 255)
glassStroke.Transparency = 0.78
glassStroke.Thickness = 1
glassStroke.Parent = mainFrame
local glassGradient = Instance.new("UIGradient")
glassGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
	ColorSequenceKeypoint.new(0.4, Color3.fromRGB(180, 180, 190)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(90, 90, 100)),
})
glassGradient.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.88),
	NumberSequenceKeypoint.new(0.5, 0.96),
	NumberSequenceKeypoint.new(1, 0.9),
})
glassGradient.Rotation = 65
glassGradient.Parent = mainFrame
local albumArt = Instance.new("ImageLabel")
albumArt.Name = "AlbumArt"
albumArt.Size = UDim2.new(0, 56, 0, 56)
albumArt.Position = UDim2.new(0, 12, 0.5, -28)
albumArt.BackgroundColor3 = Color3.fromRGB(45, 45, 50)
albumArt.BackgroundTransparency = 0.2
albumArt.BorderSizePixel = 0
albumArt.Image = "rbxassetid://10048101484"
albumArt.Parent = mainFrame
local albumCorner = Instance.new("UICorner")
albumCorner.CornerRadius = UDim.new(0, 12)
albumCorner.Parent = albumArt
local trackLabel = Instance.new("TextLabel")
trackLabel.Name = "TrackLabel"
trackLabel.Size = UDim2.new(0, 240, 0, 20)
trackLabel.Position = UDim2.new(0, 80, 0, 12)
trackLabel.BackgroundTransparency = 1
trackLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
trackLabel.Font = Enum.Font.GothamBold
trackLabel.TextSize = 14
trackLabel.TextXAlignment = Enum.TextXAlignment.Left
trackLabel.TextTruncate = Enum.TextTruncate.AtEnd
trackLabel.Text = "Connecting..."
trackLabel.Parent = mainFrame
local artistLabel = Instance.new("TextLabel")
artistLabel.Name = "ArtistLabel"
artistLabel.Size = UDim2.new(0, 240, 0, 16)
artistLabel.Position = UDim2.new(0, 80, 0, 30)
artistLabel.BackgroundTransparency = 1
artistLabel.TextColor3 = Color3.fromRGB(170, 170, 178)
artistLabel.Font = Enum.Font.Gotham
artistLabel.TextSize = 12
artistLabel.TextXAlignment = Enum.TextXAlignment.Left
artistLabel.TextTruncate = Enum.TextTruncate.AtEnd
artistLabel.Text = ""
artistLabel.Parent = mainFrame
local function makeControlButton(iconText, xPos)
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(0, 22, 0, 22)
	btn.Position = UDim2.new(0, xPos, 0, 50)
	btn.BackgroundTransparency = 1
	btn.Text = iconText
	btn.TextColor3 = Color3.fromRGB(255, 255, 255)
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 16
	btn.AutoButtonColor = false
	btn.Parent = mainFrame
	btn.MouseEnter:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.12), { TextTransparency = 0.3 }):Play()
	end)
	btn.MouseLeave:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.12), { TextTransparency = 0 }):Play()
	end)
	return btn
end
local backBtn = makeControlButton("|<", 80)
local playPauseBtn = makeControlButton("||", 108)
local skipBtn = makeControlButton(">|", 136)
local progressBarBg = Instance.new("Frame")
progressBarBg.Name = "ProgressBarBg"
progressBarBg.Size = UDim2.new(0, 210, 0, 4)
progressBarBg.Position = UDim2.new(0, 168, 0, 58)
progressBarBg.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
progressBarBg.BackgroundTransparency = 0.75
progressBarBg.BorderSizePixel = 0
progressBarBg.Parent = mainFrame
local barCorner = Instance.new("UICorner")
barCorner.CornerRadius = UDim.new(0, 2)
barCorner.Parent = progressBarBg
local progressBarFill = Instance.new("Frame")
progressBarFill.Name = "ProgressBarFill"
progressBarFill.Size = UDim2.new(0, 0, 1, 0)
progressBarFill.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
progressBarFill.BackgroundTransparency = 0
progressBarFill.BorderSizePixel = 0
progressBarFill.Parent = progressBarBg
local fillCorner = Instance.new("UICorner")
fillCorner.CornerRadius = UDim.new(0, 2)
fillCorner.Parent = progressBarFill
local sliderCircle = Instance.new("ImageButton")
local circleCorner = Instance.new("UICorner")
circleCorner.CornerRadius = UDim.new(1, 0)
circleCorner.Parent = sliderCircle
sliderCircle.Size = UDim2.new(0, 12, 0, 12)
sliderCircle.Position = UDim2.new(0, -6, 0.5, -6)
sliderCircle.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
sliderCircle.BorderSizePixel = 0
sliderCircle.ZIndex = 3
sliderCircle.Parent = progressBarBg
local timeCurrent = Instance.new("TextLabel")
timeCurrent.Name = "TimeCurrent"
timeCurrent.Size = UDim2.new(0, 34, 0, 14)
timeCurrent.Position = UDim2.new(0, 166, 0, 64)
timeCurrent.BackgroundTransparency = 1
timeCurrent.TextColor3 = Color3.fromRGB(170, 170, 178)
timeCurrent.Font = Enum.Font.Gotham
timeCurrent.TextSize = 10
timeCurrent.TextXAlignment = Enum.TextXAlignment.Left
timeCurrent.Text = "0:00"
timeCurrent.Parent = mainFrame
local timeTotal = Instance.new("TextLabel")
timeTotal.Name = "TimeTotal"
timeTotal.Size = UDim2.new(0, 34, 0, 14)
timeTotal.Position = UDim2.new(0, 344, 0, 64)
timeTotal.BackgroundTransparency = 1
timeTotal.TextColor3 = Color3.fromRGB(170, 170, 178)
timeTotal.Font = Enum.Font.Gotham
timeTotal.TextSize = 10
timeTotal.TextXAlignment = Enum.TextXAlignment.Right
timeTotal.Text = "0:00"
timeTotal.Parent = mainFrame
local customRequest = customRequest or http_request or request or (syn and syn.request) or (http and http.request)
local function formatTime(seconds)
	if not seconds or seconds < 0 then return "0:00" end
	seconds = math.floor(seconds)
	return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end
local TOTAL_SECONDS = 1
local currentSeconds = 0
local targetSeconds = 0
local isDragging = false
local isPlaying = false
local appOnline = true
local LERP_SPEED = 18
sliderCircle.MouseEnter:Connect(function()
	if isPlaying and appOnline then
		TweenService:Create(sliderCircle, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.new(0, 16, 0, 16)
		}):Play()
	end
end)
sliderCircle.MouseLeave:Connect(function()
	if not isDragging then
		TweenService:Create(sliderCircle, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.new(0, 12, 0, 12)
		}):Play()
	end
end)
local function getRatioFromMouse()
	local absolutePosition = progressBarBg.AbsolutePosition.X
	local absoluteSize = progressBarBg.AbsoluteSize.X
	local mousePosition = UserInputService:GetMouseLocation().X
	local relativeX = mousePosition - absolutePosition
	return math.clamp(relativeX / absoluteSize, 0, 1)
end
sliderCircle.MouseButton1Down:Connect(function()
	if isPlaying and appOnline then
		isDragging = true
	end
end)
UserInputService.InputChanged:Connect(function(input)
	if isDragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
		targetSeconds = getRatioFromMouse() * TOTAL_SECONDS
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		if isDragging then
			isDragging = false
			TweenService:Create(sliderCircle, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Size = UDim2.new(0, 12, 0, 12)
			}):Play()
		end
	end
end)
local function sendControl(action)
	task.spawn(function()
		pcall(function()
			customRequest({
				Url = controlUrl .. action,
				Method = "POST",
			})
		end)
	end)
end
playPauseBtn.MouseButton1Click:Connect(function()
	sendControl(isPlaying and "pause" or "play")
end)
skipBtn.MouseButton1Click:Connect(function()
	sendControl("next")
end)
backBtn.MouseButton1Click:Connect(function()
	sendControl("previous")
end)
RunService.Heartbeat:Connect(function(deltaTime)
	progressBarBg.Visible = appOnline
	timeCurrent.Visible = appOnline
	timeTotal.Visible = appOnline
	playPauseBtn.Text = isPlaying and "||" or "|>"
	if not isDragging and isPlaying and appOnline and TOTAL_SECONDS > 1 then
		if targetSeconds < TOTAL_SECONDS then
			targetSeconds = targetSeconds + deltaTime
		end
	end
	currentSeconds = currentSeconds + (targetSeconds - currentSeconds) * math.clamp(deltaTime * LERP_SPEED, 0, 1)
	local ratio = 0
	if TOTAL_SECONDS > 0 then
		ratio = math.clamp(currentSeconds / TOTAL_SECONDS, 0, 1)
	end
	local halfDotSize = sliderCircle.Size.X.Offset / 2
	progressBarFill.Size = UDim2.new(ratio, 0, 1, 0)
	sliderCircle.Position = UDim2.new(ratio, -halfDotSize, 0.5, -halfDotSize)
	timeCurrent.Text = formatTime(currentSeconds)
	timeTotal.Text = formatTime(TOTAL_SECONDS)
end)
local function splitTitleArtist(raw)
	if not raw or raw == "" then
		return "No Track Playing", ""
	end
	local track, artist = raw:match("^(.-)%s*[·•|]%s*(.+)$")
	if track and artist then return track, artist end
	track, artist = raw:match("^(.-)%s+%-%s+(.+)$")
	if track and artist then return track, artist end
	track, artist = raw:match("^(.-)%s+by%s+(.+)$")
	if track and artist then return track, artist end
	return raw, ""
end
task.spawn(function()
	while screenGui and screenGui.Parent do
		local success, response = pcall(function()
			return customRequest({
				Url = musicUrl .. "?t=" .. os.time(),
				Method = "GET",
			})
		end)
		if success and response and response.Body then
			local jsonSuccess, result = pcall(function()
				return HttpService:JSONDecode(response.Body)
			end)
			appOnline = true
			if jsonSuccess and result then
				local rawTrack = result.track or ""
				local rawArtist = result.artist or ""
				local trackName, artistName
				if rawArtist ~= "" then
					trackName = rawTrack
					artistName = rawArtist
				else
					trackName, artistName = splitTitleArtist(rawTrack)
				end
				if trackName and trackName ~= "" and trackName ~= "No Track Playing" then
					trackLabel.Text = trackName
					artistLabel.Text = (artistName ~= "" and artistName) or "Unknown Artist"
					local newDuration = tonumber(result.duration) or 1
					local newPosition = tonumber(result.position) or 0
					if newDuration < 1 then newDuration = 1 end
					if newPosition < 0 then newPosition = 0 end
					if newPosition > newDuration then newPosition = newDuration end
					if newDuration ~= TOTAL_SECONDS or math.abs(newPosition - targetSeconds) > 2.5 then
						currentSeconds = newPosition
						targetSeconds = newPosition
					end
					TOTAL_SECONDS = newDuration
					isPlaying = string.lower(tostring(result.status or "")) == "playing"
				else
					trackLabel.Text = "Spotify"
					artistLabel.Text = "No track playing"
					isPlaying = false
					TOTAL_SECONDS = 1
					targetSeconds = 0
					currentSeconds = 0
				end
			else
				trackLabel.Text = "Spotify"
				artistLabel.Text = "No track playing"
				isPlaying = false
				TOTAL_SECONDS = 1
				targetSeconds = 0
				currentSeconds = 0
			end
		else
			trackLabel.Text = "Offline (Net Error)"
			artistLabel.Text = "Check network connection"
			isPlaying = false
			appOnline = false
		end
		task.wait(4)
	end
end)
