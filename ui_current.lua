--[[=================================================================
  CharacterCustomizationUI — LocalScript (StarterPlayerScripts)
  -----------------------------------------------------------------
  MUDANÇAS FACE À VERSÃO ANTERIOR:
  ① Câmara estática — sem auto-rotate nem drag. Lê CameraDefault e
     FaceCamera do room no Workspace. Lerp suave entre os dois quando
     a categoria muda (Cabelo/Barba → FaceCamera; Roupa → CameraDefault).
  ② Tabela de itens no lado direito — todos os itens de cada categoria
     listados de uma vez num ScrollingFrame. Clicar selecciona.
  ③ Manequim do character room — clonado de Assets.Manequim e
     posicionado no spot do room (CFrame do Manequim no Workspace).
  ④ Fix de acessórios no manequim — removida a linha `handle.Anchored
     = true` antes de AddAccessory. Era a causa raiz: AddAccessory cria
     um Weld entre o Handle e o body part; se o Handle está Anchored,
     o weld é ignorado pela física e o Handle permanece na posição
     world-space original (normalmente fora do manequim).

  ESTRUTURA ESPERADA no Workspace._CharCustomizationRoom:
  ├── Manequim        → Model (servidor invisible; posição de spawn do clone local)
  ├── PlayerStand     → BasePart (onde o player real está preso)
  ├── CameraDefault   → BasePart (CFrame = câmara base, corpo inteiro)
  └── FaceCamera      → BasePart (CFrame = câmara zoom na cara)

  O cliente cria um clone LOCAL-ONLY do Manequim (não replicado ao
  servidor), posicionado no CFrame do Manequim do room. Outros jogadores
  nunca vêem o clone do cliente.
=================================================================]]

local Players    = game:GetService("Players")
local RS         = game:GetService("ReplicatedStorage")
local UIS        = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local function getCam() return workspace.CurrentCamera end

local Assets      = RS.Assets.CharacterCustomization
local Clothing    = RS.Assets.Clothing
local OpenCust    = RS.Events.OpenCustomization
local ApplyCust   = RS.Events.ApplyCustomization

-- ══════════════════════════════════════════════════════════════════
--  ROUPAS DA CUSTOMIZAÇÃO — editar apenas aqui
--  Os nomes têm de corresponder a pastas em RS.Assets.Clothing
-- ══════════════════════════════════════════════════════════════════
local CLOTH_LIST = {
	"Rags",
	"Rags2",
}
-- ══════════════════════════════════════════════════════════════════

local ROOM_NAME = "_CharCustomizationRoom"
local CHAR = player.Character
local HAIR_CT      = #Assets.Hairs:GetChildren()
local BEARD_CT     = #Assets.Beards:GetChildren()
local ACCS_CT      = Assets:FindFirstChild("Accessories") and #Assets.Accessories:GetChildren() or 0
local FaceFolder   = Assets.Face
local FACE_EYES_CT = #FaceFolder.Eyes:GetChildren()
local FACE_MRK_CT  = #FaceFolder.Markings:GetChildren()
local FACE_MRK2_CT = #FaceFolder.Markings2:GetChildren()

-- ─── Estado global ───────────────────────────────────────────────
local S = {
	cat          = 1,
	faceEyesIdx  = 1,
	faceMrkIdx   = 0,
	faceMrk2Idx  = 0,
	hairIdx      = 1,
	beardIdx     = 0,
	clothIdx     = 1,
	accSlots     = {},
	hairH  = 30/360, hairS = 0.65, hairV = 0.38,
	beardH = 30/360, beardS = 0.65, beardV = 0.38,
}

local function hairCol()  return Color3.fromHSV(S.hairH,  S.hairS,  S.hairV)  end
local function beardCol() return Color3.fromHSV(S.beardH, S.beardS, S.beardV) end

local roomRef = nil
local updateCameraTarget
local mannequin = nil

local function destroyMannequin()
	if mannequin and mannequin.Parent then mannequin:Destroy() end
	mannequin = nil
end

local ROOM_CLONE_NAME = "_CharCustomizationRoom"
local roomModel = nil

local function buildRoom()
	local existing = workspace:FindFirstChild(ROOM_CLONE_NAME)
	if existing then roomModel = existing; return end

	local clone = Assets.CharacterCRoom:Clone()
	clone.Name = ROOM_CLONE_NAME
	roomRef = clone
	warn("RoomBuilt")
	clone.Parent = workspace
	roomModel    = clone

	CHAR.HumanoidRootPart.CFrame = clone:FindFirstChild("PlayerStand").CFrame
end

local function createMannequin()
	destroyMannequin()
	local clone = Assets.Manequim:Clone()

	for _, p in ipairs(clone:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Anchored   = true
			p.CanCollide = false
		end
	end

	for _, v in ipairs(clone:GetChildren()) do
		if v:IsA("Shirt") or v:IsA("Pants") then v:Destroy() end
	end

	clone.Parent = workspace.Camera
	clone:PivotTo(roomModel:FindFirstChild("CharacterPlace").CFrame)
	mannequin = clone
	return clone
end

-- ─── Preview no manequim ─────────────────────────────────────────

local function removeFromMan(tag)
	if not (mannequin and mannequin.Parent) then return end
	for _, v in ipairs(mannequin:GetChildren()) do
		if v:GetAttribute(tag) then v:Destroy() end
	end
end

local function addAccessory(folder, tag, color)
	if not (mannequin and mannequin.Parent) then return end

	task.wait()
	if not (mannequin and mannequin.Parent) then return end

	local c = folder:Clone()
	c:SetAttribute(tag, true)

	local handle = c:FindFirstChild("Handle")
	if handle then
		local decal = handle:FindFirstChild("Decal")
		if decal then decal.Color3 = color end
		handle.CanCollide = false
		handle.Anchored   = true

		local handleAtt = handle:FindFirstChildWhichIsA("Attachment")
		if handleAtt then
			local bodyAtt
			for _, d in ipairs(mannequin:GetDescendants()) do
				if d:IsA("Attachment") and d.Name == handleAtt.Name and d.Parent ~= handle then
					bodyAtt = d
					break
				end
			end
			if bodyAtt then
				handle.CFrame = bodyAtt.Parent.CFrame * bodyAtt.CFrame * handleAtt.CFrame:Inverse()
			end
		end
	end

	c.Parent = mannequin
end

local function previewHair()
	removeFromMan("_cH")
	if S.hairIdx <= 0 then return end
	local src = Assets.Hairs:FindFirstChild(tostring(S.hairIdx))
	if src then task.spawn(addAccessory, src, "_cH", hairCol()) end
end

local function previewBeard()
	removeFromMan("_cB")
	if S.beardIdx <= 0 then return end
	local src = Assets.Beards:FindFirstChild(tostring(S.beardIdx))
	if src then task.spawn(addAccessory, src, "_cB", beardCol()) end
end

local function previewAccessory()
	removeFromMan("_cA")
	if not Assets:FindFirstChild("Accessories") then return end
	for idx in pairs(S.accSlots) do
		local src = Assets.Accessories:FindFirstChild(tostring(idx))
		if src then task.spawn(addAccessory, src, "_cA", Color3.new(1,1,1)) end
	end
end

local function previewCloth()
	removeFromMan("_cC")
	if not (mannequin and mannequin.Parent) then return end
	if S.clothIdx <= 0 then return end
	local folder = Clothing:FindFirstChild(CLOTH_LIST[S.clothIdx] or "")
	if not folder then return end
	local function put(cls)
		local v = folder:FindFirstChildWhichIsA(cls)
		if v then
			local c = v:Clone(); c:SetAttribute("_cC", true); c.Parent = mannequin
		end
	end
	put("Shirt"); put("Pants")
end

local function refreshHairDecal()
	if not (mannequin and mannequin.Parent) then return end
	for _, v in ipairs(mannequin:GetChildren()) do
		if v:GetAttribute("_cH") then
			local h = v:FindFirstChild("Handle")
			if h then local d = h:FindFirstChild("Decal"); if d then d.Color3 = hairCol() end end
		end
	end
end

local function refreshBeardDecal()
	if not (mannequin and mannequin.Parent) then return end
	for _, v in ipairs(mannequin:GetChildren()) do
		if v:GetAttribute("_cB") then
			local h = v:FindFirstChild("Handle")
			if h then local d = h:FindFirstChild("Decal"); if d then d.Color3 = beardCol() end end
		end
	end
end

local function previewFace()
	if not (mannequin and mannequin.Parent) then return end
	local head = mannequin:FindFirstChild("Head")
	if not head then return end
	local fp = head:FindFirstChild("FacePart")
	if not fp then return end
	for _, d in ipairs(fp:GetChildren()) do
		if d:IsA("Decal") and d:GetAttribute("_cFace") then d:Destroy() end
	end
	local function put(folder, idx, name)
		if idx <= 0 then return end
		local src = folder:FindFirstChild(tostring(idx))
		if src then
			local c = src:Clone()
			c.Name = name
			c:SetAttribute("_cFace", true)
			c.Parent = fp
		end
	end
	put(FaceFolder.Eyes,      S.faceEyesIdx, "Eyes")
	put(FaceFolder.Markings,  S.faceMrkIdx,  "Feature1")
	put(FaceFolder.Markings2, S.faceMrk2Idx, "Feature2")
end

local function fullPreview()
	previewFace(); previewHair(); previewBeard(); previewCloth(); previewAccessory()
end

-- ─── Paleta Skyrim / Elder Scrolls ───────────────────────────────
local C = {
	bg           = Color3.fromRGB(8,   6,   4),
	panel        = Color3.fromRGB(18,  14,  10),
	panelDark    = Color3.fromRGB(12,  9,   6),
	gold         = Color3.fromRGB(201, 161, 73),
	goldHover    = Color3.fromRGB(228, 195, 112),
	crimson      = Color3.fromRGB(68,  14,  14),
	crimsonHover = Color3.fromRGB(95,  22,  22),
	selected     = Color3.fromRGB(40,  30,  8),
	text         = Color3.fromRGB(210, 195, 158),
	textDim      = Color3.fromRGB(120, 105, 75),
	stroke       = Color3.fromRGB(100, 75,  25),
}

-- ─── UI helpers ──────────────────────────────────────────────────
local function addCorner(inst, r)
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r or 8); c.Parent = inst
end

local function addStroke(inst, col, thick)
	local s = Instance.new("UIStroke"); s.Color = col or C.stroke; s.Thickness = thick or 1; s.Parent = inst
end

local function mkFrame(parent, size, pos, bg, alpha)
	local f = Instance.new("Frame")
	f.Size = size; f.Position = pos
	f.BackgroundColor3       = bg or C.panelDark
	f.BackgroundTransparency = alpha or 0
	f.BorderSizePixel        = 0
	f.Parent                 = parent
	return f
end

local function mkLabel(parent, size, pos, text, sz, font, col)
	local l = Instance.new("TextLabel")
	l.Size = size; l.Position = pos
	l.BackgroundTransparency = 1
	l.Text = text; l.TextSize = sz or 15
	l.Font = font or Enum.Font.Antique
	l.TextColor3 = col or C.text
	l.Parent = parent
	return l
end

local function mkBtn(parent, size, pos, bg, text, sz, font)
	local b = Instance.new("TextButton")
	b.Size = size; b.Position = pos
	b.BackgroundColor3 = bg; b.BorderSizePixel = 0
	b.Text = text; b.TextSize = sz or 15
	b.Font = font or Enum.Font.Antique
	b.TextColor3 = C.text; b.AutoButtonColor = false
	b.Parent = parent
	addStroke(b, C.gold, 1)
	return b
end

local function addHover(btn, norm, hov)
	btn.MouseEnter:Connect(function() btn.BackgroundColor3 = hov  end)
	btn.MouseLeave:Connect(function() btn.BackgroundColor3 = norm end)
end

-- ─── Build ScreenGui ─────────────────────────────────────────────
local gui = Instance.new("ScreenGui")
gui.Name             = "CharCustGUI"
gui.ResetOnSpawn     = false
gui.IgnoreGuiInset   = true
gui.ZIndexBehavior   = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder     = 50
gui.Enabled          = false
gui.Parent           = player.PlayerGui

-- Overlay de fundo — preto simples, sem gradiente
mkFrame(gui, UDim2.fromScale(1,1), UDim2.fromScale(0,0), Color3.fromRGB(0,0,0), 0.72)

-- Barra de título — preta, linha dourada em baixo, bordas retas
local topBar = mkFrame(gui, UDim2.new(1,0,0,58), UDim2.fromScale(0,0),
	Color3.fromRGB(0,0,0), 0.3)
mkFrame(topBar, UDim2.new(1,0,0,2), UDim2.new(0,0,1,-2), C.gold)

local titleLbl = mkLabel(topBar, UDim2.fromScale(1,1), UDim2.fromScale(0,0),
	"CRIAR PERSONAGEM", 22, Enum.Font.Antique, C.gold)
titleLbl.TextXAlignment        = Enum.TextXAlignment.Center
titleLbl.TextStrokeTransparency = 0.4
titleLbl.TextStrokeColor3      = Color3.fromRGB(0, 0, 0)

-- ─── Painel Direito ───────────────────────────────────────────────
local RIGHT_W = 245

local rightPanel = mkFrame(gui,
	UDim2.new(0, RIGHT_W, 1, -138),
	UDim2.new(1, -(RIGHT_W + 12), 0, 66),
	Color3.fromRGB(0, 0, 0), 0.48)
addStroke(rightPanel, C.stroke, 1)

local CAT_LABELS = {"Rosto", "Cabelo", "Barba", "Roupa", "Acess."}
local CAT_ICONS  = {"◈", "◈", "◈", "◈", "◈"}
local HAS_NONE   = {false, true, true, false, true}
local MAX_IDX    = {0, HAIR_CT, BEARD_CT, #CLOTH_LIST, ACCS_CT}

local TAB_H = 40

-- Tab frame — sem UICorner, linha dourada separadora em baixo
local tabFrame = mkFrame(rightPanel,
	UDim2.new(1, 0, 0, TAB_H),
	UDim2.fromScale(0, 0),
	Color3.fromRGB(0, 0, 0), 0.5)
mkFrame(tabFrame, UDim2.new(1,0,0,1), UDim2.new(0,0,1,-1), C.gold)

local tabBtns = {}
local tabW = 1 / #CAT_LABELS

for i = 1, #CAT_LABELS do
	local btn = Instance.new("TextButton")
	btn.Size                   = UDim2.new(tabW, 0, 1, 0)
	btn.Position               = UDim2.new(tabW * (i-1), 0, 0, 0)
	btn.BackgroundColor3       = Color3.fromRGB(0, 0, 0)
	btn.BackgroundTransparency = 0.6
	btn.BorderSizePixel        = 0
	btn.Text                   = CAT_ICONS[i].." "..CAT_LABELS[i]
	btn.TextSize               = 12
	btn.Font                   = Enum.Font.Antique
	btn.TextColor3             = C.textDim
	btn.AutoButtonColor        = false
	btn.Parent                 = tabFrame
	-- Thin vertical separator between tabs
	if i < #CAT_LABELS then
		local sep = Instance.new("Frame")
		sep.Size                   = UDim2.new(0, 1, 0.55, 0)
		sep.Position               = UDim2.new(tabW * i, 0, 0.22, 0)
		sep.BackgroundColor3       = C.stroke
		sep.BackgroundTransparency = 0.3
		sep.BorderSizePixel        = 0
		sep.Parent                 = tabFrame
	end
	tabBtns[i] = btn
end

-- ScrollingFrame da lista
local listScroll = Instance.new("ScrollingFrame")
listScroll.Size                = UDim2.new(1, 0, 1, -(TAB_H + 2))
listScroll.Position            = UDim2.new(0, 0, 0, TAB_H + 2)
listScroll.BackgroundTransparency = 1
listScroll.BorderSizePixel     = 0
listScroll.ScrollBarThickness  = 4
listScroll.ScrollBarImageColor3 = C.gold
listScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
listScroll.CanvasSize          = UDim2.new(0, 0, 0, 0)
listScroll.Parent              = rightPanel

local listLayout = Instance.new("UIListLayout")
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Padding   = UDim.new(0, 0)
listLayout.Parent    = listScroll

local listPad = Instance.new("UIPadding")
listPad.PaddingTop    = UDim.new(0, 2)
listPad.PaddingBottom = UDim.new(0, 4)
listPad.Parent        = listScroll

local itemButtons = {}

-- ─── Helpers de índice ────────────────────────────────────────────
local function curIdx()
	if S.cat==2 then return S.hairIdx elseif S.cat==3 then return S.beardIdx elseif S.cat==4 then return S.clothIdx else return 0 end
end
local function setIdx(v)
	if S.cat==2 then S.hairIdx=v elseif S.cat==3 then S.beardIdx=v elseif S.cat==4 then S.clothIdx=v end
end

-- ─── Highlight da linha seleccionada ────────────────────────────
local function highlightSelected()
	local ci = curIdx()
	for _, btn in ipairs(itemButtons) do
		local isSelected = btn:GetAttribute("itemIdx") == ci
		btn.BackgroundColor3       = isSelected and C.selected or Color3.fromRGB(0,0,0)
		btn.BackgroundTransparency = isSelected and 0 or 1
		btn.TextColor3             = isSelected and C.gold or C.text
		btn.Text = (isSelected and "> " or "  ")..(btn:GetAttribute("_rawText") or "")
	end
end

-- ─── Construção da lista de itens ────────────────────────────────
local function mkListBtn(text, selected, lo)
	local btn = Instance.new("TextButton")
	btn.Size                   = UDim2.new(1, 0, 0, 32)
	btn.BackgroundColor3       = selected and C.selected or Color3.fromRGB(0,0,0)
	btn.BackgroundTransparency = selected and 0 or 1
	btn.BorderSizePixel        = 0
	btn:SetAttribute("_rawText", text)
	btn.Text                   = (selected and "> " or "  ")..text
	btn.TextSize               = 14
	btn.Font                   = Enum.Font.Antique
	btn.TextColor3             = selected and C.gold or C.text
	btn.TextXAlignment         = Enum.TextXAlignment.Left
	btn.AutoButtonColor        = false
	btn.LayoutOrder            = lo
	-- Thin separator line at bottom
	local sep = Instance.new("Frame")
	sep.Size                   = UDim2.new(0.88, 0, 0, 1)
	sep.Position               = UDim2.new(0.06, 0, 1, -1)
	sep.BackgroundColor3       = C.stroke
	sep.BackgroundTransparency = 0.45
	sep.BorderSizePixel        = 0
	sep.Parent                 = btn
	btn.MouseEnter:Connect(function()
		if btn.BackgroundTransparency ~= 0 then
			btn.BackgroundColor3 = Color3.fromRGB(20,15,5)
			btn.BackgroundTransparency = 0.3
		end
	end)
	btn.MouseLeave:Connect(function()
		local isSelected = (btn:GetAttribute("itemIdx") ~= nil and btn:GetAttribute("itemIdx") == curIdx())
			or (btn:GetAttribute("_faceField") ~= nil and S[btn:GetAttribute("_faceField")] == btn:GetAttribute("_faceVal"))
		if not isSelected then
			btn.BackgroundColor3 = Color3.fromRGB(0,0,0)
			btn.BackgroundTransparency = 1
		end
	end)
	btn.Parent                 = listScroll
	return btn
end

local function mkSectionHeader(text, lo)
	local lbl = Instance.new("TextLabel")
	lbl.Size                   = UDim2.new(1, 0, 0, 26)
	lbl.BackgroundColor3       = Color3.fromRGB(0, 0, 0)
	lbl.BackgroundTransparency = 0.55
	lbl.BorderSizePixel        = 0
	lbl.Text                   = "  ─── "..string.upper(text).." ───"
	lbl.TextSize               = 11
	lbl.Font                   = Enum.Font.Antique
	lbl.TextColor3             = C.gold
	lbl.TextXAlignment         = Enum.TextXAlignment.Left
	lbl.LayoutOrder            = lo
	lbl.Parent                 = listScroll
	return lbl
end

local function buildItemList()
	for _, b in ipairs(itemButtons) do b:Destroy() end
	itemButtons = {}

	if S.cat == 5 then
		local noneSelected = next(S.accSlots) == nil
		local noneBtn = mkListBtn("— Nenhum", noneSelected, 0)
		noneBtn:SetAttribute("itemIdx", 0)
		noneBtn.MouseButton1Click:Connect(function()
			S.accSlots = {}
			buildItemList()
			previewAccessory()
		end)
		table.insert(itemButtons, noneBtn)
		for i = 1, ACCS_CT do
			local sel = S.accSlots[i] == true
			local btn = mkListBtn("Acessório "..i, sel, i)
			btn:SetAttribute("itemIdx", i)
			local ci = i
			btn.MouseButton1Click:Connect(function()
				if S.accSlots[ci] then S.accSlots[ci] = nil else S.accSlots[ci] = true end
				buildItemList()
				previewAccessory()
			end)
			table.insert(itemButtons, btn)
		end
		return
	end

	if S.cat == 1 then
		local SECTIONS = {
			{label="Olhos",    field="faceEyesIdx", ct=FACE_EYES_CT, noNone=true},
			{label="Marcas",   field="faceMrkIdx",  ct=FACE_MRK_CT},
			{label="Marcas II",field="faceMrk2Idx", ct=FACE_MRK2_CT},
		}
		local lo = 0
		for _, sec in ipairs(SECTIONS) do
			table.insert(itemButtons, mkSectionHeader(sec.label, lo)); lo += 1
			for i = (sec.noNone and 1 or 0), sec.ct do
				local txt = (i == 0) and "— Nenhum" or (sec.label.." "..i)
				local btn = mkListBtn(txt, S[sec.field] == i, lo); lo += 1
				btn:SetAttribute("_faceField", sec.field)
				btn:SetAttribute("_faceVal",   i)
				local cf, cv = sec.field, i
				btn.MouseButton1Click:Connect(function()
					S[cf] = cv
					for _, b in ipairs(itemButtons) do
						local f = b:GetAttribute("_faceField")
						local v = b:GetAttribute("_faceVal")
						if f and v ~= nil then
							local sel = S[f] == v
							b.BackgroundColor3       = sel and C.selected or Color3.fromRGB(0,0,0)
							b.BackgroundTransparency = sel and 0 or 1
							b.TextColor3             = sel and C.gold     or C.text
						end
					end
					previewFace()
				end)
				table.insert(itemButtons, btn)
			end
		end
		return
	end

	local ci       = curIdx()
	local catLabel = CAT_LABELS[S.cat]
	local maxIdx   = MAX_IDX[S.cat]

	if HAS_NONE[S.cat] then
		local btn = mkListBtn("— Nenhum", ci == 0, 0)
		btn:SetAttribute("itemIdx", 0)
		btn.MouseButton1Click:Connect(function()
			setIdx(0); highlightSelected()
			if     S.cat == 2 then previewHair()
			elseif S.cat == 3 then previewBeard() end
		end)
		table.insert(itemButtons, btn)
	end

	for i = 1, maxIdx do
		local label = (S.cat == 4 and CLOTH_LIST[i]) or (catLabel.." "..i)
		local btn = mkListBtn(label, ci == i, i)
		btn:SetAttribute("itemIdx", i)
		local capturedI = i
		btn.MouseButton1Click:Connect(function()
			setIdx(capturedI); highlightSelected()
			if     S.cat == 2 then previewHair()
			elseif S.cat == 3 then previewBeard()
			else                    previewCloth() end
		end)
		table.insert(itemButtons, btn)
	end
end

-- ─── Color Picker (lado esquerdo) ────────────────────────────────
local cpanel = mkFrame(gui,
	UDim2.new(0, 215, 0, 318),
	UDim2.new(0, 12, 0.5, -155),
	Color3.fromRGB(0, 0, 0), 0.48)
addStroke(cpanel, C.stroke, 1)
mkFrame(cpanel, UDim2.new(1,0,0,1), UDim2.fromScale(0,0), C.gold)

local cpTitle = mkLabel(cpanel, UDim2.new(1,0,0,30), UDim2.fromScale(0,0),
	"COR DO CABELO", 12, Enum.Font.Antique, C.gold)
cpTitle.TextXAlignment = Enum.TextXAlignment.Center

local svBox = mkFrame(cpanel, UDim2.new(1,-14,0,130), UDim2.new(0,7,0,33),
	Color3.fromHSV(S.hairH,1,1))
addStroke(svBox, C.stroke, 1)

local satGrad = Instance.new("UIGradient")
satGrad.Color = ColorSequence.new(Color3.new(1,1,1), Color3.new(1,1,1))
satGrad.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1),
})
satGrad.Parent = svBox

local valOverlay = mkFrame(svBox, UDim2.fromScale(1,1), UDim2.fromScale(0,0), Color3.new(0,0,0))
local valGrad = Instance.new("UIGradient")
valGrad.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0),
})
valGrad.Rotation = 90
valGrad.Parent   = valOverlay

local svDot = mkFrame(svBox, UDim2.new(0,14,0,14), UDim2.fromScale(S.hairS, 1-S.hairV), Color3.new(1,1,1))
addCorner(svDot, 7); addStroke(svDot, Color3.fromRGB(60,40,10), 2)
svDot.AnchorPoint = Vector2.new(0.5, 0.5)
svDot.ZIndex      = 8

local hueBar = mkFrame(cpanel, UDim2.new(1,-14,0,18), UDim2.new(0,7,0,172), Color3.new(1,0,0))
addStroke(hueBar, C.stroke, 1)

local hueGrad = Instance.new("UIGradient")
hueGrad.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0,    Color3.fromHSV(0,   1,1)),
	ColorSequenceKeypoint.new(1/6,  Color3.fromHSV(1/6, 1,1)),
	ColorSequenceKeypoint.new(2/6,  Color3.fromHSV(2/6, 1,1)),
	ColorSequenceKeypoint.new(3/6,  Color3.fromHSV(3/6, 1,1)),
	ColorSequenceKeypoint.new(4/6,  Color3.fromHSV(4/6, 1,1)),
	ColorSequenceKeypoint.new(5/6,  Color3.fromHSV(5/6, 1,1)),
	ColorSequenceKeypoint.new(1,    Color3.fromHSV(1,   1,1)),
})
hueGrad.Parent = hueBar

local hueLine = mkFrame(hueBar, UDim2.new(0,4,1,8), UDim2.new(S.hairH,0,0.5,0), Color3.new(1,1,1))
addCorner(hueLine, 2)
hueLine.AnchorPoint = Vector2.new(0.5, 0.5)
hueLine.ZIndex      = 8

local swatch = mkFrame(cpanel, UDim2.new(1,-14,0,42), UDim2.new(0,7,0,200), hairCol())
addStroke(swatch, C.stroke, 1)
local swLbl = mkLabel(swatch, UDim2.fromScale(1,1), UDim2.fromScale(0,0),
	"Pré-visualização", 11, Enum.Font.Antique, C.text)
swLbl.TextXAlignment       = Enum.TextXAlignment.Center
swLbl.TextStrokeTransparency = 0.4

-- ─── RGB Input (abaixo do swatch) ────────────────────────────────
local rgbRow = mkFrame(cpanel, UDim2.new(1,-14,0,58), UDim2.new(0,7,0,249),
	Color3.fromRGB(0,0,0), 0.4)
addStroke(rgbRow, C.stroke, 1)

local rgbBoxes = {}
local RGB_CH = {"R","G","B"}

for i = 1, 3 do
	local xPx = 3 + (i-1)*66
	local colF = mkFrame(rgbRow, UDim2.new(0,63,1,-8), UDim2.new(0,xPx,0,4),
		Color3.fromRGB(0,0,0), 0.5)
	addStroke(colF, C.stroke, 1)

	local lbl = mkLabel(colF, UDim2.new(1,0,0,16), UDim2.fromScale(0,0),
		RGB_CH[i], 11, Enum.Font.GothamBold, C.gold)
	lbl.TextXAlignment = Enum.TextXAlignment.Center

	local tb = Instance.new("TextBox")
	tb.Size                   = UDim2.new(1,-4,0,28)
	tb.Position               = UDim2.new(0,2,0,15)
	tb.BackgroundColor3       = Color3.fromRGB(0,0,0)
	tb.BackgroundTransparency = 0.3
	tb.BorderSizePixel        = 0
	tb.Text                   = "0"
	tb.TextSize               = 12
	tb.Font                   = Enum.Font.Code
	tb.TextColor3             = C.gold
	tb.ClearTextOnFocus       = false
	tb.Parent                 = colF
	addStroke(tb, C.stroke, 1)
	rgbBoxes[i] = tb
end

local function syncRgbInputs()
	local col = (S.cat == 2) and hairCol() or beardCol()
	rgbBoxes[1].Text = tostring(math.floor(col.R * 255 + 0.5))
	rgbBoxes[2].Text = tostring(math.floor(col.G * 255 + 0.5))
	rgbBoxes[3].Text = tostring(math.floor(col.B * 255 + 0.5))
end

local function applyRgbInput()
	local r = math.clamp(tonumber(rgbBoxes[1].Text) or 0, 0, 255)
	local g = math.clamp(tonumber(rgbBoxes[2].Text) or 0, 0, 255)
	local b = math.clamp(tonumber(rgbBoxes[3].Text) or 0, 0, 255)
	rgbBoxes[1].Text = tostring(r)
	rgbBoxes[2].Text = tostring(g)
	rgbBoxes[3].Text = tostring(b)
	local h, s, v = Color3.fromRGB(r, g, b):ToHSV()
	if S.cat == 2 then
		S.hairH, S.hairS, S.hairV = h, s, v
		refreshHairDecal()
	else
		S.beardH, S.beardS, S.beardV = h, s, v
		refreshBeardDecal()
	end
	syncColorPanel()
end

for _, tb in ipairs(rgbBoxes) do
	tb.FocusLost:Connect(function() applyRgbInput() end)
end

-- ─── Botão Confirmar ──────────────────────────────────────────────
local CONFIRM_BG  = Color3.fromRGB(38, 29, 8)
local CONFIRM_HOV = Color3.fromRGB(58, 44, 12)
local confirmBtn = mkBtn(gui,
	UDim2.new(0, 280, 0, 58), UDim2.new(0.5, -140, 1, -72),
	CONFIRM_BG, "CONFIRMAR", 20, Enum.Font.Antique)
confirmBtn.TextColor3 = C.gold
addStroke(confirmBtn, C.gold, 2)
addHover(confirmBtn, CONFIRM_BG, CONFIRM_HOV)
mkFrame(confirmBtn, UDim2.new(1,0,0,2), UDim2.fromScale(0,0), C.gold)
mkFrame(confirmBtn, UDim2.new(1,0,0,2), UDim2.new(0,0,1,-2), C.gold)

local loadLbl = mkLabel(gui, UDim2.new(0,300,0,40), UDim2.new(0.5,-150,0.5,-20),
	"A preparar...", 18, Enum.Font.Antique, C.gold)
loadLbl.TextXAlignment = Enum.TextXAlignment.Center
loadLbl.Visible        = false
task.spawn(function()
	local dots = {".", "..", "..."}
	local i = 1
	while loadLbl and loadLbl.Parent do
		if loadLbl.Visible then
			loadLbl.Text = "A preparar" .. dots[i]
			i = i % 3 + 1
		end
		task.wait(0.5)
	end
end)

-- ─── UI sync ─────────────────────────────────────────────────────

local function syncTabs()
	for i, btn in ipairs(tabBtns) do
		if i == S.cat then
			btn.BackgroundColor3       = C.gold
			btn.BackgroundTransparency = 0
			btn.TextColor3             = Color3.fromRGB(10, 5, 0)
		else
			btn.BackgroundColor3       = Color3.fromRGB(0, 0, 0)
			btn.BackgroundTransparency = 0.6
			btn.TextColor3             = C.textDim
		end
	end
end

local function syncColorPanel()
	local visible = (S.cat == 2 or S.cat == 3)
	cpanel.Visible = visible
	if not visible then return end
	local h, sat, v, col
	if S.cat == 2 then
		h,sat,v,col = S.hairH,S.hairS,S.hairV,hairCol()
		cpTitle.Text = "COR DO CABELO"
	else
		h,sat,v,col = S.beardH,S.beardS,S.beardV,beardCol()
		cpTitle.Text = "COR DA BARBA"
	end
	svBox.BackgroundColor3  = Color3.fromHSV(h, 1, 1)
	svDot.Position          = UDim2.fromScale(sat, 1-v)
	hueLine.Position        = UDim2.new(h, 0, 0.5, 0)
	swatch.BackgroundColor3 = col
	syncRgbInputs()
end

-- ─── Tab buttons ─────────────────────────────────────────────────
for i, btn in ipairs(tabBtns) do
	btn.MouseButton1Click:Connect(function()
		S.cat = i
		syncTabs()
		syncColorPanel()
		buildItemList()
		if updateCameraTarget then updateCameraTarget() end
	end)
end

-- ─── Color Picker — lógica de drag ───────────────────────────────
local dragSV, dragHue = false, false

local function applySV(pos)
	local abs = svBox.AbsolutePosition; local sz = svBox.AbsoluteSize
	if sz.X == 0 or sz.Y == 0 then return end
	local sx = math.clamp((pos.X-abs.X)/sz.X, 0, 1)
	local sy = math.clamp((pos.Y-abs.Y)/sz.Y, 0, 1)
	if S.cat==2 then S.hairS,S.hairV  = sx, 1-sy
	else             S.beardS,S.beardV = sx, 1-sy end
	svDot.Position          = UDim2.fromScale(sx, sy)
	swatch.BackgroundColor3 = (S.cat==2) and hairCol() or beardCol()
	if S.cat==2 then refreshHairDecal() else refreshBeardDecal() end
	syncRgbInputs()
end

local function applyHue(pos)
	local abs = hueBar.AbsolutePosition; local sz = hueBar.AbsoluteSize
	if sz.X == 0 then return end
	local hx = math.clamp((pos.X-abs.X)/sz.X, 0, 1)
	if S.cat==2 then S.hairH=hx else S.beardH=hx end
	svBox.BackgroundColor3  = Color3.fromHSV(hx, 1, 1)
	hueLine.Position        = UDim2.new(hx, 0, 0.5, 0)
	swatch.BackgroundColor3 = (S.cat==2) and hairCol() or beardCol()
	if S.cat==2 then refreshHairDecal() else refreshBeardDecal() end
	syncRgbInputs()
end

svBox.InputBegan:Connect(function(i)
	if i.UserInputType == Enum.UserInputType.MouseButton1 then dragSV=true; applySV(i.Position) end
end)
hueBar.InputBegan:Connect(function(i)
	if i.UserInputType == Enum.UserInputType.MouseButton1 then dragHue=true; applyHue(i.Position) end
end)

local globalConns = {}

table.insert(globalConns, UIS.InputChanged:Connect(function(i)
	if i.UserInputType ~= Enum.UserInputType.MouseMovement then return end
	if dragSV  then applySV(i.Position)  end
	if dragHue then applyHue(i.Position) end
end))
table.insert(globalConns, UIS.InputEnded:Connect(function(i)
	if i.UserInputType == Enum.UserInputType.MouseButton1 then
		dragSV=false; dragHue=false
	end
end))

-- ─── Câmara estática ─────────────────────────────────────────────
local FACE_CATS = {[1]=true, [2]=true, [3]=true}

local camConn          = nil
local camTargetCFrame  = nil
local camCurrentCFrame = nil

local function getRoomCameras()
	if not roomRef then return nil, nil end
	local def  = roomRef:FindFirstChild("CameraDefault", true)
	local face = roomRef:FindFirstChild("FaceCamera",    true)
	return def, face
end

updateCameraTarget = function()
	local def, face = getRoomCameras()
	if not def and not face then return end

	if FACE_CATS[S.cat] then
		camTargetCFrame = (face and face.CFrame) or (def and def.CFrame)
	else
		camTargetCFrame = def and def.CFrame
	end
end

local function startCam()
	local cam = getCam()
	cam.CameraType = Enum.CameraType.Scriptable

	updateCameraTarget()

	if camTargetCFrame then
		cam.CFrame       = camTargetCFrame
		camCurrentCFrame = camTargetCFrame
	end

	camConn = RunService.RenderStepped:Connect(function(dt)
		if not camTargetCFrame then return end

		local lf = math.min(1, dt * 6)
		camCurrentCFrame = camCurrentCFrame:Lerp(camTargetCFrame, lf)

		local freshCam = getCam()
		if freshCam.CameraType == Enum.CameraType.Scriptable then
			freshCam.CFrame = camCurrentCFrame
		end
	end)
end

local function stopCam()
	if camConn then camConn:Disconnect(); camConn = nil end
	camTargetCFrame  = nil
	camCurrentCFrame = nil
	getCam().CameraType = Enum.CameraType.Custom
end

-- ─── Open / Close ────────────────────────────────────────────────
local isOpen    = false
local confirmed = false

local function closeUI()
	if not isOpen then return end
	isOpen = false
	gui.Enabled = false
	stopCam()
	destroyMannequin()
	dragSV = false; dragHue = false
	roomRef = nil
end

local function openUI()
	if isOpen then return end
	isOpen    = true
	confirmed = false

	S.cat=1
	S.faceEyesIdx=1; S.faceMrkIdx=0; S.faceMrk2Idx=0
	S.hairIdx=1; S.beardIdx=0; S.clothIdx=1; S.accSlots={}
	S.hairH=30/360; S.hairS=0.65; S.hairV=0.38
	S.beardH=30/360; S.beardS=0.65; S.beardV=0.38

	syncTabs()
	buildItemList()
	syncColorPanel()

	loadLbl.Visible = true
	gui.Enabled     = true

	task.spawn(function()
		buildRoom()
		if not roomRef then
			warn("[CharCustomUI] Room não encontrado em 30s. A fechar UI.")
			isOpen = false; gui.Enabled = false; loadLbl.Visible = false
			return
		end

		task.wait()

		local man = createMannequin()
		if not man then
			player.CharacterAdded:Wait()
			task.wait(0.1)
			man = createMannequin()
			if not man then
				isOpen = false; gui.Enabled = false; loadLbl.Visible = false
				return
			end
		end

		loadLbl.Visible = false
		startCam()

		fullPreview()
	end)
end

-- ─── Confirm ─────────────────────────────────────────────────────
confirmBtn.MouseButton1Click:Connect(function()
	if not isOpen or confirmed then return end
	confirmed = true
	confirmBtn.BackgroundColor3 = Color3.fromRGB(55, 10, 10)

	ApplyCust:FireServer({
		eyesIndex      = S.faceEyesIdx,
		markingsIndex  = S.faceMrkIdx,
		markings2Index = S.faceMrk2Idx,
		hairIndex      = S.hairIdx,
		hairColor      = hairCol(),
		beardIndex     = S.beardIdx,
		beardColor     = beardCol(),
		clothingName      = CLOTH_LIST[S.clothIdx] or "Rags",
		accessoryIndices  = (function() local t={} for idx in pairs(S.accSlots) do table.insert(t,idx) end return t end)(),
	})

	closeUI()
end)

-- ─── Remote events ───────────────────────────────────────────────
OpenCust.OnClientEvent:Connect(openUI)

player.CharacterRemoving:Connect(function()
	if isOpen then closeUI() end
end)

player.CharacterAdded:Connect(function(char)
	CHAR = char
end)
