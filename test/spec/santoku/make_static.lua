local test = require("santoku.test")
local fs = require("santoku.fs")
local str = require("santoku.string")
local wasm = require("santoku.make.wasm")

local function has (t, v)
  for i = 1, #t do
    if t[i] == v then
      return true
    end
  end
  return false
end

test("wasm install context builds a node cli", function ()
  local flags = wasm.get_bundle_flags("/nonexistent", "install", {}, {})
  assert(has(flags, "-sSINGLE_FILE"), "install must embed the wasm in the js")
  assert(has(flags, "-lnoderawfs.js"), "install must reach the real filesystem")
  assert(has(flags, "-lnodefs.js"))
  assert(not has(flags, "-sNO_EXIT_RUNTIME"), "install must propagate exit codes")
end)

test("wasm build context stays a library", function ()
  local flags = wasm.get_bundle_flags("/nonexistent", "build", {}, {})
  assert(not has(flags, "-sSINGLE_FILE"))
  assert(not has(flags, "-lnoderawfs.js"))
  assert(has(flags, "-sNO_EXIT_RUNTIME"))
end)

test("wasm test context keeps assertions", function ()
  local flags = wasm.get_bundle_flags("/nonexistent", "test", {}, {})
  assert(has(flags, "-sASSERTIONS"))
  assert(has(flags, "-sSINGLE_FILE"))
  assert(not has(flags, "-sNO_EXIT_RUNTIME"))
end)

local mk = fs.readfile("res/lib/lib.mk")

local function plain (needle, msg)
  assert(str.find(mk, needle, 1, true), msg or ("lib.mk missing: " .. needle))
end

test("lib.mk declares sidecar targets, gated off for wasm", function ()
  plain("ifndef _WASM")
  plain("LIB_LINK = $(LIB_O:.o=.link)")
  plain("INST_O = $(addprefix $(INST_LIBDIR)/, $(LIB_O))")
  plain("INST_LINK = $(addprefix $(INST_LIBDIR)/, $(LIB_LINK))")
  plain("all: $(LIB_O) $(LIB_SO) $(LIB_LINK)")
end)

test("lib.mk writes the sidecar in link order", function ()
  plain("%.link: %.o")
  local obj = str.find(mk, "$(notdir $<) > $@", 1, true)
  local arc = str.find(mk, "$(notdir $(filter %.a, $(LDFLAGS) $(LIB_LDFLAGS)))", 1, true)
  local lib = str.find(mk, "$(filter -l%, $(LDFLAGS) $(LIB_LDFLAGS))", 1, true)
  assert(obj and arc and lib, "sidecar must record object, archives and -l flags")
  assert(obj < arc, "the module object must be linked before its archives")
  assert(arc < lib, "archives must be linked before -l flags")
end)

test("lib.mk installs objects, sidecars and vendored archives", function ()
  plain("install: $(INST_LUA) $(INST_SO) $(INST_O) $(INST_LINK) $(INST_H)")
  plain("$(INST_LIBDIR)/%.o: ./%.o")
  plain("$(INST_LIBDIR)/%.link: ./%.link")
  plain("cp $(filter %.a, $(LDFLAGS) $(LIB_LDFLAGS)) $(dir $@)",
    "vendored archives must land next to the sidecar that names them")
end)
