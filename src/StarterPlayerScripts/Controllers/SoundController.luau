--!strict
-- SoundController: plays one-shot SFX by name and an optional music bed, with
-- separate SFX/Music volume that the settings menu controls. SoundIds come from
-- the shared SoundConfig (best-effort — blocked audio just stays silent).

local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SoundConfig = require(ReplicatedStorage.Shared.SoundConfig)

local SoundController = {}

local sfxVolume = 0.5
local musicVolume = 0.35
local folder: Folder? = nil
local music: Sound? = nil

function SoundController.init()
	local f = Instance.new("Folder")
	f.Name = "BL_SFX"
	f.Parent = SoundService
	folder = f
end

-- play a one-shot sound effect by SoundConfig.SFX key
function SoundController.play(name: string, volumeScale: number?)
	local id = SoundConfig.sfxId(name)
	if id == "" then
		return
	end
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = sfxVolume * (volumeScale or 1)
	s.Parent = folder or SoundService
	s:Play()
	s.Ended:Once(function()
		s:Destroy()
	end)
	task.delay(6, function()
		if s and s.Parent then
			s:Destroy()
		end
	end)
end

function SoundController.playMusic(idName: string)
	local id = SoundConfig.ambienceId(idName)
	if id == "" then
		return
	end
	if not music then
		local m = Instance.new("Sound")
		m.Name = "BL_Music"
		m.Looped = true
		m.Parent = folder or SoundService
		music = m
	end
	local m = music :: Sound
	m.SoundId = id
	m.Volume = musicVolume
	m:Play()
end

function SoundController.setSfxVolume(v: number)
	sfxVolume = math.clamp(v, 0, 1)
end
function SoundController.setMusicVolume(v: number)
	musicVolume = math.clamp(v, 0, 1)
	if music then
		(music :: Sound).Volume = musicVolume
	end
end
function SoundController.getSfxVolume(): number
	return sfxVolume
end
function SoundController.getMusicVolume(): number
	return musicVolume
end

return SoundController
