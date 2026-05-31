--[[=================================================================
  CharacterCustomizationService — ModuleScript (Services)
  -----------------------------------------------------------------
  Responsabilidades:
  1. Clona o character room de ReplicatedStorage.Assets
     .CharacterCustomization para o Workspace (uma vez, no Start).
  2. Ao entrar pela primeira vez (IsFirstTime=true): teletransporta
     o personagem para PlayerStand (dentro do room), bloqueia
     movimento e abre o UI.
  3. Ao confirmar (ApplyCustomization): aplica o look ao personagem
     real, persiste no DataStore e liberta o player.
  4. Em cada respawn: re-aplica o look guardado.

  ESTRUTURA ESPERADA em RS.Assets.CharacterCustomization:
  ├── Hairs/          → Accessories numerados
  ├── Beards/         → Accessories numerados
  ├── Clothes/        → Folders numeradas (Shirt + Pants)
  ├── Manequim        → Model (referência de posição; invisível no server)
  ├── PlayerStand     → BasePart onde o player fica preso
  ├── CameraDefault   → BasePart cujo CFrame é a câmara base
  ├── FaceCamera      → BasePart cujo CFrame é o zoom na cara
  └── [Geometria do room: Parts, Models, etc.]

  INVARIANTE: o room é desenhado em Studio na posição final de mundo.
  Clonamos sem mover (PivotTo seria necessário só se o room estivesse
  na origem). Se o room estiver na origem no RS, ajustar ROOM_OFFSET.
=================================================================]]

local Players = game:GetService("Players")
local RS      = game:GetService("ReplicatedStorage")

local OpenCust  = RS.Events.OpenCustomization
local ApplyCust = RS.Events.ApplyCustomization
local Assets         = RS.Assets.CharacterCustomization
local ClothingAssets = RS.Assets.Clothing

-- Nome do clone no Workspace — usado pelo cliente para encontrar o room.
local ROOM_CLONE_NAME = "_CharCustomizationRoom"

-- Referência ao clone activo. Nil até buildRoom() ser chamado.
local roomModel = nil

-- ─── Room Setup ──────────────────────────────────────────────────
--[[
  buildRoom()
  Clona o room dos Assets para o Workspace.
  • Remove as pastas de dados (Hairs/Beards/Clothes) do clone:
    elas vivem em RS como fonte autoritativa; no Workspace seriam
    banda larga desperdiçada.
  • Torna o Manequim invisível no servidor: é apenas um anchor de
    posição para o cliente. O cliente cria um clone local-only.
  • Idempotente: não cria duplicados se já existir.
]]

-- ─── PlayerStand CFrame ──────────────────────────────────────────
-- Retorna o CFrame onde o player deve ser teleportado.
-- PlayerStand deve ser um BasePart posicionado onde o player fica.
-- Se não existir, usa um fallback razoável.

-- ─── Helpers de look ─────────────────────────────────────────────

local function stripLook(char)
	for _, v in ipairs(char:GetChildren()) do
		if v:IsA("Accessory") or v:IsA("Shirt") or v:IsA("Pants") then
			v:Destroy()
		end
	end
end

--[[
  applyLook — aplica look ao personagem REAL no servidor.
  Nota: não replicamos a cor via Decal no servidor porque o servidor
  não pode alterar o Decal de um Accessory clonado de forma que replique
  correctamente para todos os clientes em todos os casos. A abordagem
  correcta é aplicar a cor no Handle.Decal antes de AddAccessory.
]]
local function applyLook(char, eyesIdx, mrkIdx, mrk2Idx, hairIdx, hairCol, beardIdx, beardCol, clothName, accIdx)
	stripLook(char)
	local hum = char:FindFirstChildWhichIsA("Humanoid")
	if not hum then return end

	-- Rosto: aplicar decals no Head.FacePart
	local head = char:FindFirstChild("Head")
	if head then
		local fp = head:FindFirstChild("FacePart")
		if fp then
			for _, d in ipairs(fp:GetChildren()) do
				if d:IsA("Decal") and d:GetAttribute("_cFace") then d:Destroy() end
			end
			local function putFace(folder, idx, name)
				if idx <= 0 then return end
				local src = folder:FindFirstChild(tostring(idx))
				if src then
					local c = src:Clone()
					c.Name = name
					c:SetAttribute("_cFace", true)
					c.Parent = fp
				end
			end
			putFace(Assets.Face.Eyes,      eyesIdx,  "Eyes")
			putFace(Assets.Face.Markings,  mrkIdx,   "Feature1")
			putFace(Assets.Face.Markings2, mrk2Idx,  "Feature2")
		end
	end

	-- Cabelo
	if hairIdx > 0 then
		local src = Assets.Hairs:FindFirstChild(tostring(hairIdx))
		if src then
			local clone  = src:Clone()
			local handle = clone:FindFirstChild("Handle")
			if handle then
				local decal = handle:FindFirstChild("Decal")
				if decal then decal.Color3 = hairCol end
			end
			hum:AddAccessory(clone)
		end
	end

	-- Barba
	if beardIdx > 0 then
		local src = Assets.Beards:FindFirstChild(tostring(beardIdx))
		if src then
			local clone  = src:Clone()
			local handle = clone:FindFirstChild("Handle")
			if handle then
				local decal = handle:FindFirstChild("Decal")
				if decal then decal.Color3 = beardCol end
			end
			hum:AddAccessory(clone)
		end
	end

	-- Roupa
	if clothName and clothName ~= "" then
		local folder = ClothingAssets:FindFirstChild(clothName)
		if folder then
			local shirt = folder:FindFirstChildWhichIsA("Shirt")
			local pants = folder:FindFirstChildWhichIsA("Pants")
			if shirt then shirt:Clone().Parent = char end
			if pants  then pants:Clone().Parent = char end
		end
	end

	-- Acessório
	if accIdx and accIdx > 0 then
		local accFolder = Assets:FindFirstChild("Accessories")
		if accFolder then
			local src = accFolder:FindFirstChild(tostring(accIdx))
			if src then hum:AddAccessory(src:Clone()) end
		end
	end
end

-- ─── Acesso a dados ──────────────────────────────────────────────
local function getPlayerValues(player)
	local data = player:FindFirstChild("Data")
	if not data then return nil end
	return data:FindFirstChild("PlayerValues")
end

local function loadSavedLook(player, char)
	local pv = getPlayerValues(player)
	if not pv then return end
	local function n(name) local v = pv:FindFirstChild(name); return v and tonumber(v.Value) or 0 end
	local function c(name) local v = pv:FindFirstChild(name); return v and v.Value or Color3.fromRGB(80,50,20) end
	local clothVal  = pv:FindFirstChild("clothing")
	local clothName = (clothVal and clothVal.Value ~= "" and clothVal.Value ~= "None") and clothVal.Value or "Rags"
	applyLook(char,
		n("EyesIndex"), n("MarkingsIndex"), n("Markings2Index"),
		n("HairIndex"),  c("HairColor"),
		n("BeardIndex"), c("BeardColor"),
		clothName, n("AccessoryIndex"))
end

-- ─── Freeze / unfreeze ───────────────────────────────────────────
local function freezeHumanoid(hum)
	hum.WalkSpeed = 0
	hum.JumpPower = 0
end

local function unfreezeHumanoid(hum)
	hum.WalkSpeed = 16
	hum.JumpPower = 50
end

-- ─── Teleporte para spawn ────────────────────────────────────────
local function teleportToSpawn(player, char)
	local spawnLoc = workspace:FindFirstChildWhichIsA("SpawnLocation")
	local hrp      = char:FindFirstChild("HumanoidRootPart")
	if hrp and spawnLoc then
		hrp.CFrame = spawnLoc.CFrame + Vector3.new(0, 5, 0)
	else
		player:LoadCharacter()
	end
end

-- ─── Handler de ApplyCustomization ──────────────────────────────
ApplyCust.OnServerEvent:Connect(function(player, data)
	if typeof(data) ~= "table" then return end
	local char = player.Character
	if not char then return end

	local eIdx  = math.clamp(math.floor(tonumber(data.eyesIndex)      or 1), 0, 100)
	local mIdx  = math.clamp(math.floor(tonumber(data.markingsIndex)  or 0), 0, 100)
	local m2Idx = math.clamp(math.floor(tonumber(data.markings2Index) or 0), 0, 100)
	local hIdx  = math.clamp(math.floor(tonumber(data.hairIndex)      or 0), 0, 100)
	local hCol  = typeof(data.hairColor)  == "Color3" and data.hairColor  or Color3.fromRGB(80,50,20)
	local bIdx  = math.clamp(math.floor(tonumber(data.beardIndex)     or 0), 0, 100)
	local bCol  = typeof(data.beardColor) == "Color3" and data.beardColor or Color3.fromRGB(80,50,20)
	local cName = typeof(data.clothingName) == "string" and data.clothingName or "Rags"
	local aIdx  = math.clamp(math.floor(tonumber(data.accessoryIndex) or 0), 0, 100)

	applyLook(char, eIdx, mIdx, m2Idx, hIdx, hCol, bIdx, bCol, cName, aIdx)

	local pv = getPlayerValues(player)
	if pv then
		local function setV(name, val)
			local v = pv:FindFirstChild(name); if v then v.Value = val end
		end
		setV("EyesIndex",      eIdx)
		setV("MarkingsIndex",  mIdx)
		setV("Markings2Index", m2Idx)
		setV("HairIndex",      hIdx)
		setV("HairColor",      hCol)
		setV("BeardIndex",     bIdx)
		setV("BeardColor",     bCol)
		setV("clothing",       cName)
		setV("AccessoryIndex", aIdx)
		setV("IsFirstTime",    false)
	end

	RS.Save:Fire(player)

	-- Delay de 0.5s: garante que applyLook() completou antes de mover.
	task.delay(0.5, function()
		if not char or not char.Parent then return end
		local hum = char:FindFirstChildWhichIsA("Humanoid")
		if hum then unfreezeHumanoid(hum) end
		teleportToSpawn(player, char)
	end)
end)

-- ─── Setup por jogador ───────────────────────────────────────────
local function setupPlayer(player)
	player.CharacterAdded:Connect(function(char)
		local data        = player:WaitForChild("Data", 30)
		if not data then return end
		local pv          = data:WaitForChild("PlayerValues", 15)
		if not pv then return end
		local isFirstTime = pv:WaitForChild("IsFirstTime", 10)
		if not isFirstTime then return end

		task.wait(1)  -- dar tempo ao MainServer para inicializar atributos

		if isFirstTime.Value == true then
			-- ── Primeira entrada: teleportar para PlayerStand ──────────
			local hrp = char:FindFirstChild("HumanoidRootPart")
			if hrp then
			--	hrp.CFrame = getPlayerStandCFrame()
			end

			local hum = char:FindFirstChildWhichIsA("Humanoid")
			if hum then freezeHumanoid(hum) end

			-- Aplicar roupa predefinida para o player não aparecer nu.
			task.wait(0.3)
			local clothVal  = pv:FindFirstChild("clothing")
			local clothName = (clothVal and clothVal.Value ~= "" and clothVal.Value ~= "None") and clothVal.Value or "Rags"
			local folder = ClothingAssets:FindFirstChild(clothName)
			if folder then
				local s = folder:FindFirstChildWhichIsA("Shirt")
				local p = folder:FindFirstChildWhichIsA("Pants")
				if s then s:Clone().Parent = char end
				if p then p:Clone().Parent = char end
			end

			task.wait(0.3)
			OpenCust:FireClient(player)

		else
			-- ── Jogador recorrente: re-aplicar look guardado ───────────
			task.wait(0.1)
			loadSavedLook(player, char)
		end
	end)
end

-- ─── Módulo ──────────────────────────────────────────────────────
local module = {}

function module.Start()
	--buildRoom()

	Players.PlayerAdded:Connect(setupPlayer)

	-- Edge case: jogadores já em jogo quando o módulo arranca (Studio)
	for _, p in ipairs(Players:GetPlayers()) do
		setupPlayer(p)
	end
end

return module
