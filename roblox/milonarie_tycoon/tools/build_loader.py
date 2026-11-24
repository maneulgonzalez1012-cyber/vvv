#!/usr/bin/env python3
"""Aero :: Milonarie Tycoon :: genera loader.lua y bootstrap.lua.

Ambos ficheros se descargan y ejecutan por separado en el executor, asi que
llevan el cliente HTTP inlined. Para que el cliente no diverja entre los dos,
se genera desde una fuente unica: tools/http_client.lua.

Salidas (en la raiz del repo):
    loader.lua     -> GUI VANTA + descarga y ejecuta el payload
    bootstrap.lua  -> linea de paste autonoma (sin GUI)

    .venv/bin/python tools/build_loader.py
    .venv/bin/python tools/build_loader.py --check
"""
import argparse
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
REPO = ROOT.parents[1]
TOOLS = ROOT / "tools"

BASE = "https://raw.githubusercontent.com/maneulgonzalez1012-cyber/vvv/arena/5e9deb5f-vvv"
PAYLOAD_NAME = "milonarie_tycoon_obfuscated_compact"
PAYLOAD_URL = f"{BASE}/roblox/milonarie_tycoon/release/{PAYLOAD_NAME}.lua"
LOADER_URL = f"{BASE}/loader.lua"
PARTS_URL = f"{BASE}/roblox/milonarie_tycoon/release/parts/{PAYLOAD_NAME}.part%d"
MANIFEST_URL = f"{BASE}/roblox/milonarie_tycoon/release/parts/{PAYLOAD_NAME}.manifest"

LOADER_TEMPLATE = """--[[
    VANTA | MILONARIE TYCOON
    Loader

    Generado por roblox/milonarie_tycoon/tools/build_loader.py. No editar a mano.

    Se pega en el executor con el juego abierto. NO depende de game:HttpGet:
    Athena (y otros executors) lanzan "HttpGet is not a valid member of
    DataModel" al indexarlo, asi que el cliente HTTP prueba primero las APIs
    del executor y solo usa HttpGet como ultimo recurso.
]]

{client}
----------------------------------------------------------------------- URLs
-- Payload ofuscado con Prometheus. Cambia la URL para usar medium/strong:
--   .../milonarie_tycoon_obfuscated.lua        (Medium, register VM)
--   .../milonarie_tycoon_obfuscated_strong.lua  (Strong)
--   .../milonarie_tycoon_obfuscated_light.lua   (Light)
local PAYLOAD_URL = "{payload_url}"

-- Respaldo por partes: algunos executors recortan el body de la respuesta.
-- Si el payload truncado no compila, se descargan las partes y se concatenan.
local PAYLOAD_PARTS_URL = "{parts_url}"
local PAYLOAD_MANIFEST_URL = "{manifest_url}"

------------------------------------------------------------------- GUI (opcional)
-- La pantalla de carga es cosmetica: si el executor no deja crear GUI, el
-- payload se descarga y se ejecuta igual.
local ScreenGui, Frame, Status

local function setStatus(text)
\tif Status then
\t\tpcall(function()
\t\t\tStatus.Text = text
\t\tend)
\tend
end

local function buildGui()
\tlocal ok = pcall(function()
\t\tlocal TweenService = game:GetService("TweenService")
\t\tlocal CoreGui = game:GetService("CoreGui")

\t\tScreenGui = Instance.new("ScreenGui")
\t\tScreenGui.Name = "VANTA_Loader"
\t\tScreenGui.IgnoreGuiInset = true
\t\tScreenGui.ResetOnSpawn = false
\t\tScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
\t\tScreenGui.Parent = CoreGui

\t\tFrame = Instance.new("Frame")
\t\tFrame.Size = UDim2.new(1, 0, 1, 0)
\t\tFrame.BackgroundColor3 = Color3.fromRGB(12, 11, 10)
\t\tFrame.BorderSizePixel = 0
\t\tFrame.Parent = ScreenGui

\t\tlocal Title = Instance.new("TextLabel")
\t\tTitle.Size = UDim2.new(1, 0, 0, 40)
\t\tTitle.Position = UDim2.new(0, 0, 0.42, 0)
\t\tTitle.BackgroundTransparency = 1
\t\tTitle.Text = "VANTA"
\t\tTitle.TextColor3 = Color3.fromRGB(242, 239, 233)
\t\tTitle.TextSize = 32
\t\tTitle.Font = Enum.Font.GothamBold
\t\tTitle.Parent = Frame

\t\tlocal Subtitle = Instance.new("TextLabel")
\t\tSubtitle.Size = UDim2.new(1, 0, 0, 24)
\t\tSubtitle.Position = UDim2.new(0, 0, 0.48, 0)
\t\tSubtitle.BackgroundTransparency = 1
\t\tSubtitle.Text = "MILONARIE TYCOON"
\t\tSubtitle.TextColor3 = Color3.fromRGB(160, 155, 145)
\t\tSubtitle.TextSize = 16
\t\tSubtitle.Font = Enum.Font.Gotham
\t\tSubtitle.Parent = Frame

\t\tStatus = Instance.new("TextLabel")
\t\tStatus.Size = UDim2.new(1, 0, 0, 20)
\t\tStatus.Position = UDim2.new(0, 0, 0.58, 0)
\t\tStatus.BackgroundTransparency = 1
\t\tStatus.Text = "Cargando..."
\t\tStatus.TextColor3 = Color3.fromRGB(180, 175, 165)
\t\tStatus.TextSize = 14
\t\tStatus.Font = Enum.Font.Gotham
\t\tStatus.Parent = Frame

\t\tlocal BarBg = Instance.new("Frame")
\t\tBarBg.Size = UDim2.new(0, 220, 0, 4)
\t\tBarBg.Position = UDim2.new(0.5, -110, 0.63, 0)
\t\tBarBg.BackgroundColor3 = Color3.fromRGB(40, 38, 35)
\t\tBarBg.BorderSizePixel = 0
\t\tBarBg.Parent = Frame

\t\tlocal Bar = Instance.new("Frame")
\t\tBar.Size = UDim2.new(0, 0, 1, 0)
\t\tBar.BackgroundColor3 = Color3.fromRGB(242, 239, 233)
\t\tBar.BorderSizePixel = 0
\t\tBar.Parent = BarBg

\t\tTweenService:Create(Bar, TweenInfo.new(1.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {{
\t\t\tSize = UDim2.new(1, 0, 1, 0)
\t\t}}):Play()
\tend)
\treturn ok
end

local function fadeOut()
\tif not Frame then
\t\treturn
\tend
\tpcall(function()
\t\tlocal TweenService = game:GetService("TweenService")
\t\tlocal fade = TweenService:Create(Frame, TweenInfo.new(0.4), {{
\t\t\tBackgroundTransparency = 1
\t\t}})
\t\tfor _, child in ipairs(Frame:GetDescendants()) do
\t\t\tif child:IsA("TextLabel") then
\t\t\t\tTweenService:Create(child, TweenInfo.new(0.4), {{ TextTransparency = 1 }}):Play()
\t\t\telseif child:IsA("Frame") and child ~= Frame then
\t\t\t\tTweenService:Create(child, TweenInfo.new(0.4), {{ BackgroundTransparency = 1 }}):Play()
\t\t\tend
\t\tend
\t\tfade:Play()
\t\tfade.Completed:Wait()
\tend)
\tpcall(function()
\t\tif ScreenGui then
\t\t\tScreenGui:Destroy()
\t\tend
\tend)
end

------------------------------------------------------------------ descarga
-- Descarga por partes: el manifest dice cuantas hay y el tamano total.
local function fetchByParts()
\tlocal manifest = vantaHttpGet(PAYLOAD_MANIFEST_URL)
\tif not manifest then
\t\treturn nil, "sin manifest"
\tend
\tlocal total = tonumber(manifest:match("total=(%d+)"))
\tlocal size = tonumber(manifest:match("size=(%d+)"))
\tif not total or total < 1 then
\t\treturn nil, "manifest invalido"
\tend

\tlocal chunks = {{}}
\tfor i = 0, total - 1 do
\t\tlocal part = vantaHttpGet(string.format(PAYLOAD_PARTS_URL, i))
\t\tif not part then
\t\t\treturn nil, "falta la parte " .. i
\t\tend
\t\tchunks[#chunks + 1] = part
\tend

\tlocal source = table.concat(chunks)
\tif size and #source ~= size then
\t\treturn nil, "tamano inesperado: " .. #source .. " != " .. size
\tend
\treturn source
end

--------------------------------------------------------------------- arranque
buildGui()
setStatus("Descargando script...")

local success, err = pcall(function()
\tlocal source = vantaHttpGet(PAYLOAD_URL)
\tlocal chunk, compileErr
\tif source then
\t\tchunk, compileErr = vantaCompile(source, "=payload")
\tend
\tif not chunk then
\t\t-- Puede que el executor haya recortado el body: se reintenta por partes.
\t\tlocal parts, partsErr = fetchByParts()
\t\tif parts then
\t\t\tsource = parts
\t\t\tchunk, compileErr = vantaCompile(source, "=payload")
\t\telse
\t\t\tcompileErr = compileErr or partsErr
\t\tend
\tend
\tif not source then
\t\terror("no se pudo descargar el payload: " .. PAYLOAD_URL)
\tend
\tif not chunk then
\t\terror("el payload no compila: " .. tostring(compileErr))
\tend
\tchunk()
end)

if success then
\tsetStatus("Listo")
\tpcall(task.wait, 0.6)
else
\tsetStatus("Error al cargar")
\tpcall(function()
\t\twarn("[VANTA Loader]", err)
\tend)
\tpcall(task.wait, 2)
end

fadeOut()
"""

BOOTSTRAP_TEMPLATE = """--[[
    VANTA | MILONARIE TYCOON
    Bootstrap publico (la "linea de paste")

    Generado por roblox/milonarie_tycoon/tools/build_loader.py. No editar a mano.

    Este es el unico trozo que se pega a mano en el executor. Es autonomo:
    NO usa game:HttpGet como via principal, porque Athena (y otros executors)
    lanzan "HttpGet is not a valid member of DataModel" al indexarlo.

    Orden de intento:
        1. request({{Url=,Method=}})      -> string | {{Body=}} | (body, ok, code)
        2. http_request(url)              -> string | {{Body=}} | (body, ok, code)
        3. syn.request({{Url=,Method=}})  -> string | (body, ok, code)
        4. http.request({{Url=,Method=}}) -> string | {{Body=}} | (body, code, msg, hdr)
        5. game:HttpGet(url)              -> ultimo recurso

    Descarga loader.lua (GUI + payload con respaldo por partes) y lo ejecuta.

    Si ninguna via responde, avisa con un error claro en vez de fallar en silencio.
]]

{client}
----------------------------------------------------------------------- URLs
local LOADER_URL = "{loader_url}"

--------------------------------------------------------------------- arranque
local source = vantaHttpGet(LOADER_URL)
if not source then
\terror("[VANTA] no se pudo descargar el loader. Ningun metodo HTTP respondio "
\t\t.. "(request / http_request / syn.request / http.request / game:HttpGet).")
end

local chunk, compileErr = vantaCompile(source, "=loader")
if not chunk then
\terror("[VANTA] el loader no compila: " .. tostring(compileErr))
end

chunk()
"""

# La linea de paste de una linea que se publica en el landing y los READMEs.
PASTE_LINE = (
    'loadstring((function()local u="%s";'
    'local function b(r,e)if type(r)=="string"and #r>0 then return r end;'
    'if type(r)=="table" then local x=r.Body or r.body;'
    'if type(x)=="string"and #x>0 then return x end end;'
    'if type(e)=="string"and #e>0 then return e end;return nil end;'
    'local c={};'
    'if type(request)=="function" then c[#c+1]=request end;'
    'if type(http_request)=="function" then c[#c+1]=http_request end;'
    'if type(syn)=="table" and type(syn.request)=="function" then c[#c+1]=syn.request end;'
    'if type(http)=="table" and type(http.request)=="function" then c[#c+1]=http.request end;'
    'local s;'
    'for _,f in ipairs(c) do local ok,x=pcall(f,{Url=u,Method="GET"});'
    'if ok then s=b(x) end;if not s then local o,y=pcall(f,u);if o then s=b(y) end end;'
    'if s then break end end;'
    'if not s then local ok,x=pcall(function() return game:HttpGet(u) end);'
    'if ok then s=b(x) end end;'
    'if not s then error("[VANTA] no se pudo descargar el loader") end;'
    'return s end)())()'
) % LOADER_URL

def render(template: str) -> str:
    client = (TOOLS / "http_client.lua").read_text(encoding="utf-8").rstrip()
    return template.format(
        client=client,
        payload_url=PAYLOAD_URL,
        parts_url=PARTS_URL,
        manifest_url=MANIFEST_URL,
        loader_url=LOADER_URL,
    )


def build() -> dict[str, str]:
    outputs = {
        REPO / "loader.lua": render(LOADER_TEMPLATE),
        REPO / "bootstrap.lua": render(BOOTSTRAP_TEMPLATE),
    }
    for path, body in outputs.items():
        path.write_text(body, encoding="utf-8")
    return {str(k): v for k, v in outputs.items()}


def check(outputs: dict[str, str]) -> int:
    try:
        from lupa.lua55 import LuaRuntime
    except ImportError:
        print("lupa no instalado -> omito el syntax check")
        return 0
    lua = LuaRuntime(unpack_returned_tuples=True)
    problems = 0
    for path, body in outputs.items():
        try:
            lua.compile(body)
        except Exception as exc:  # lupa.LuaError
            print(f"SYNTAX ERROR in {path}:\n{exc}")
            problems += 1
    try:
        lua.compile(PASTE_LINE)
    except Exception as exc:
        print(f"SYNTAX ERROR in la linea de paste:\n{exc}")
        problems += 1
    if problems == 0:
        print(f"syntax ok ({len(outputs)} ficheros + linea de paste)")
    return problems


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()

    outputs = build()
    for path, body in outputs.items():
        print(f"built {path} ({len(body.encode('utf-8'))} bytes)")
    paste_path = REPO / "roblox" / "milonarie_tycoon" / "release" / "paste_line.txt"
    paste_path.write_text(PASTE_LINE + "\n", encoding="utf-8")
    print(f"built {paste_path} ({len(PASTE_LINE.encode('utf-8'))} bytes)")

    if args.check:
        return 1 if check(outputs) else 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
