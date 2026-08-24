local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

local oldOverlay = playerGui:FindFirstChild("SpotifyOverlay")
if oldOverlay then oldOverlay:Destroy() end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "SpotifyOverlay"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
mainFrame.Size = UDim2.new(0, 450, 0, 80)
mainFrame.Position = UDim2.new(0.5, -225, 1, -100)
mainFrame.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
mainFrame.BorderSizePixel = 0
mainFrame.Parent = screenGui

local uiCorner = Instance.new("UICorner")
uiCorner.CornerRadius = UDim.new(0, 8)
uiCorner.Parent = mainFrame

local albumArt = Instance.new("ImageLabel")
albumArt.Name = "AlbumArt"
albumArt.Size = UDim2.new(0, 56, 0, 56)
albumArt.Position = UDim2.new(0, 12, 0.5, -28)
albumArt.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
albumArt.BorderSizePixel = 0
albumArt.Image = "rbxassetid://10048101484"
albumArt.Parent = mainFrame

local albumCorner = Instance.new("UICorner")
albumCorner.CornerRadius = UDim.new(0, 4)
albumCorner.Parent = albumArt

local trackLabel = Instance.new("TextLabel")
trackLabel.Name = "TrackLabel"
trackLabel.Size = UDim2.new(0, 240, 0, 20)
trackLabel.Position = UDim2.new(0, 80, 0, 16)
trackLabel.BackgroundTransparency = 1
trackLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
trackLabel.Font = Enum.Font.GothamBold
trackLabel.TextSize = 14
trackLabel.TextXAlignment = Enum.TextXAlignment.Left
trackLabel.TextTruncate = Enum.TextTruncate.AtEnd
trackLabel.Text = "Loading..."
trackLabel.Parent = mainFrame

local artistLabel = Instance.new("TextLabel")
artistLabel.Name = "ArtistLabel"
artistLabel.Size = UDim2.new(0, 240, 0, 16)
artistLabel.Position = UDim2.new(0, 80, 0, 36)
artistLabel.BackgroundTransparency = 1
artistLabel.TextColor3 = Color3.fromRGB(179, 179, 179)
artistLabel.Font = Enum.Font.Gotham
artistLabel.TextSize = 12
artistLabel.TextXAlignment = Enum.TextXAlignment.Left
artistLabel.TextTruncate = Enum.TextTruncate.AtEnd
artistLabel.Text = ""
artistLabel.Parent = mainFrame

local progressBarBg = Instance.new("Frame")
progressBarBg.Name = "ProgressBarBg"
progressBarBg.Size = UDim2.new(0, 240, 0, 4)
progressBarBg.Position = UDim2.new(0, 80, 0, 58)
progressBarBg.BackgroundColor3 = Color3.fromRGB(74, 74, 74)
progressBarBg.BorderSizePixel = 0
progressBarBg.Parent = mainFrame

local barCorner = Instance.new("UICorner")
barCorner.CornerRadius = UDim.new(0, 2)
barCorner.Parent = progressBarBg

local progressBarFill = Instance.new("Frame")
progressBarFill.Name = "ProgressBarFill"
progressBarFill.Size = UDim2.new(0, 0, 1, 0)
progressBarFill.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
progressBarFill.BorderSizePixel = 0
progressBarFill.Parent = progressBarBg

local fillCorner = Instance.new("UICorner")
fillCorner.CornerRadius = UDim.new(0, 2)
fillCorner.Parent = progressBarFill

local timeCurrent = Instance.new("TextLabel")
timeCurrent.Name = "TimeCurrent"
timeCurrent.Size = UDim2.new(0, 40, 0, 14)
timeCurrent.Position = UDim2.new(0, 330, 0, 53)
timeCurrent.BackgroundTransparency = 1
timeCurrent.TextColor3 = Color3.fromRGB(179, 179, 179)
timeCurrent.Font = Enum.Font.Gotham
timeCurrent.TextSize = 11
timeCurrent.TextXAlignment = Enum.TextXAlignment.Right
timeCurrent.Text = "0:00"
timeCurrent.Parent = mainFrame

local timeTotal = Instance.new("TextLabel")
timeTotal.Name = "TimeTotal"
timeTotal.Size = UDim2.new(0, 40, 0, 14)
timeTotal.Position = UDim2.new(0, 375, 0, 53)
timeTotal.BackgroundTransparency = 1
timeTotal.TextColor3 = Color3.fromRGB(179, 179, 179)
timeTotal.Font = Enum.Font.Gotham
timeTotal.TextSize = 11
timeTotal.TextXAlignment = Enum.TextXAlignment.Left
timeTotal.Text = "0:00"
timeTotal.Parent = mainFrame

local httpService = game:GetService("HttpService")
local customRequest = syn and syn.request or http_request or request or (http and http.request)

local function formatTime(seconds)
	local mins = math.floor(seconds / 60)
	local secs = seconds % 60
	return string.format("%d:%02d", mins, secs)
end

local musicUrl = "https://raw.githubusercontent.com/cryptrixz/player/refs/heads/main/music.json?t="

while true do
	local success, response = pcall(function()
		return customRequest({
			Url = musicUrl .. os.time(),
			Method = "GET"
		})
	end)
	
	if success and response and response.Body then
		local jsonSuccess, result = pcall(function()
			return httpService:JSONDecode(response.Body)
		end)
		
		if jsonSuccess and result then
			trackLabel.Text = result.track
			artistLabel.Text = result.artist
			timeCurrent.Text = formatTime(result.position)
			timeTotal.Text = formatTime(result.duration)
			
			local percentage = math.clamp(result.position / result.duration, 0, 1)
			TweenService:Create(progressBarFill, TweenInfo.new(1, Enum.EasingStyle.Linear), {
				Size = UDim2.new(percentage, 0, 1, 0)
			}):Play()
		else
			trackLabel.Text = "Offline"
			artistLabel.Text = ""
		end
	else
		trackLabel.Text = "Offline"
		artistLabel.Text = ""
		timeCurrent.Text = "0:00"
		timeTotal.Text = "0:00"
		progressBarFill.Size = UDim2.new(0, 0, 1, 0)
	end
	
	task.wait(5)
end
