local fs = require("santoku.fs")
local arr = require("santoku.array")
local str = require("santoku.string")
local err = require("santoku.error")

local function pages (manifest)
  local out = {}
  for orig, hashed in pairs(manifest) do
    if str.match(orig, "%.html$") then
      local dir = str.match(orig, "^(.+)/index%.html$")
      local url
      if orig == "index.html" then
        url = "/"
      elseif dir then
        url = "/" .. dir
      else
        url = "/" .. orig
      end
      out[url] = hashed
    end
  end
  return out
end

local function allowed_by (ref, allow)
  for i = 1, #allow do
    if str.match(ref, allow[i]) then
      return true
    end
  end
  return false
end

local function check_links (opts)
  local page_set = pages(opts.manifest)
  local allow = opts.allow or {}
  local assets = {}
  for _, hashed in pairs(opts.manifest) do
    assets["/" .. hashed] = true
  end
  for i = 1, #(opts.stable or {}) do
    assets["/" .. opts.stable[i]] = true
  end
  local contents = {}
  for url, hashed in pairs(page_set) do
    contents[url] = fs.readfile(fs.join(opts.public_dir, hashed))
  end
  for url, html in pairs(contents) do
    local stripped = str.gsub(html, "<code.-</code>", "")
    for ref in str.gmatch(stripped, "href=\"(/[^\"]*)\"") do
      local p, frag = str.match(ref, "^([^#]*)#?(.*)$")
      if not (contents[p] or assets[p] or allowed_by(p, allow)) then
        err.error("link check failed: " .. url .. " links to " .. ref ..
          ", which resolves to nothing in the output")
      end
      if frag ~= "" and contents[p]
        and not str.find(contents[p], "id=\"" .. frag .. "\"", 1, true)
      then
        err.error("link check failed: " .. url .. " links to " .. ref ..
          ", and " .. p .. " has no element with that id")
      end
    end
    for ref in str.gmatch(stripped, "src=\"(/[^\"]*)\"") do
      if not (assets[ref] or contents[ref] or allowed_by(ref, allow)) then
        err.error("link check failed: " .. url .. " references " .. ref ..
          ", which resolves to nothing in the output")
      end
    end
  end
  return page_set
end

local function sitemap (site, manifest)
  local page_set = pages(manifest)
  local urls = {}
  for url in pairs(page_set) do
    urls[#urls + 1] = url
  end
  arr.sort(urls)
  local out = {
    "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n",
    "<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">\n",
  }
  for i = 1, #urls do
    out[#out + 1] = "<url><loc>" .. site .. urls[i] .. "</loc></url>\n"
  end
  out[#out + 1] = "</urlset>\n"
  return arr.concat(out)
end

return {
  pages = pages,
  check_links = check_links,
  sitemap = sitemap,
}
