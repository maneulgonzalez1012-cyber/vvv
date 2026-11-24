-- features/pet.lua
-- Twado, the dog. Two jobs: tell you what he wants, and hand it over.
--
-- What he wants is not a constant. The game exposes it in two places depending
-- on how far along you are:
--   * the phone UI: PlayerGui.Phone...DogInfo.TwadoWants.Text (a word)
--   * the note UI:  PlayerGui.Assets.Note.Note.Note, children named
--                   Circle<Item> whose Visible flag marks the wanted food
-- Older scripts read only one of those, so the button did nothing until the
-- player happened to open the right screen. This reads both, every time, and
-- also watches the dog's own billboard for a "!"/"?" state so a request can be
-- detected without the phone being open at all.
--
-- Feeding is a two-step the game validates: GiveTool the food, equip it, then
-- CatFed with the item name. Giving the wrong food costs 10 energy, so the
-- thing is read first, never guessed.

local Net = require("core/net")
local Items = require("features/items")
local U = require("core/util")

local Pet = {}

Pet.auto = false            -- watch and feed on its own
Pet.watch_interval = 2.0
Pet.max_attempts = 3        -- per request, then it stops and asks for attention
Pet.attempts = 0
Pet.last_fed = nil
Pet.last_want = nil
Pet.fed_total = 0
Pet.status = "sin pedir nada"

local function pg()
    return Net.Player and Net.Player:FindFirstChild("PlayerGui")
end

-- "Bloxy Cola" -> "BloxyCola"; the remote wants the tool name.
local function normalize(text)
    if type(text) ~= "string" then return nil end
    local clean = text:gsub("%s+", "")
    if clean == "" then return nil end
    return clean
end

-- Every reading of "what does Twado want", most reliable first.
function Pet.wants()
    local out, seen = {}, {}
    local function add(raw)
        local id = normalize(raw)
        if id and not seen[id] then
            seen[id] = true
            table.insert(out, id)
        end
    end

    local gui = pg()
    if not gui then return out end

    -- 1. the phone's dedicated label
    local twado = gui:FindFirstChild("TwadoWants", true)
    if twado and (twado:IsA("TextLabel") or twado:IsA("TextButton")) then
        add(twado.Text)
    end

    -- 2. the note's circle markers
    local assets = gui:FindFirstChild("Assets")
    local holder = assets and assets:FindFirstChild("Note", true)
    if holder then
        for _, v in ipairs(holder:GetDescendants()) do
            if v.Name:match("^Circle") and v.Visible then
                add((v.Name:gsub("Circle", "")))
            end
        end
    end

    return out
end

-- A cheap read of whether the dog is currently asking for anything at all.
-- Twado carries a billboard whose text changes between states; it is not the
-- item name, so it is only used to decide whether to look further.
function Pet.is_asking()
    local gui = pg()
    if gui then
        local twado = gui:FindFirstChild("TwadoWants", true)
        if twado and twado.Visible and normalize(twado.Text) then return true end
    end

    local world = game:GetService("Workspace")
    local dog = world:FindFirstChild("Twado", true)
        or world:FindFirstChild("SmallCat", true)
    if dog then
        local billboard = dog:FindFirstChild("BillboardGui", true)
        if billboard and billboard:IsA("BillboardGui") then
            if billboard.Enabled == false then return false end
            local label = billboard:FindFirstChildWhichIsA("TextLabel", true)
            if label then
                local text = normalize(label.Text)
                if text and text ~= "?" and text ~= "..." then return true end
            end
        end
        -- a bowl or a "wants" part appearing next to the dog means a request
        for _, child in ipairs(dog:GetChildren()) do
            if tostring(child.Name):lower():find("want") then return true end
        end
    end
    return false
end

-- Feed one specific item: give, equip, tell the game.
function Pet.feed(id)
    if not id then return false, "sin comida" end
    if not Items.obtain(id, 1.2) then
        return false, "no pude obtener " .. id
    end
    Items.unequip_all()
    task.wait(0.12)
    if not Items.equip_if_present(id) then
        return false, "no pude equipar " .. id
    end
    task.wait(0.2)
    local ok = Net.fire_wait("CatFed", id)
    if ok then
        Pet.last_fed = id
        Pet.last_want = id
        Pet.fed_total = Pet.fed_total + 1
        Pet.attempts = 0
        Pet.status = "alimentado con " .. id
    end
    return ok, ok and "ok" or "CatFed no respondio"
end

-- Read, then feed. Refusing to guess is deliberate: the wrong food is -10
-- energy, and the dog remembers.
function Pet.try_feed()
    local wants = Pet.wants()
    if #wants == 0 then
        if Pet.is_asking() then
            Pet.status = "pide algo pero la GUI no dice que; abre el telefono"
        else
            Pet.status = "no pide nada ahora"
        end
        return false, Pet.status
    end

    if Pet.attempts >= Pet.max_attempts then
        Pet.status = "me rendi tras " .. Pet.attempts .. " intentos con " .. table.concat(wants, ", ")
        return false, Pet.status
    end

    local tried = {}
    for _, id in ipairs(wants) do
        table.insert(tried, id)
        local ok, why = Pet.feed(id)
        if ok then return true, "alimentado con " .. id end
        U.log("twado: fallo", id, why)
        task.wait(0.25)
    end
    Pet.attempts = Pet.attempts + 1
    Pet.status = "no pude con: " .. table.concat(tried, ", ")
    return false, Pet.status
end

-- The watcher. Polls slowly - this is a once-a-minute event in the game, not a
-- combat loop - and stops itself if the toggle goes off.
function Pet.start()
    Pet.auto = true
    U.loop("twado", Pet.watch_interval, function()
        if not Pet.auto then U.stop("twado"); return end
        if not Pet.is_asking() and #Pet.wants() == 0 then
            Pet.status = "esperando a que pida"
            Pet.attempts = 0
            return
        end
        Pet.try_feed()
    end)
end

function Pet.stop()
    Pet.auto = false
    U.stop("twado")
end

function Pet.summary()
    local wants = Pet.wants()
    if #wants > 0 then
        return "quiere: " .. table.concat(wants, ", ")
    end
    return Pet.status
end

return Pet
