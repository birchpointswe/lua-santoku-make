# TODO: Should use OBJ_EXTENSION

<% tbl = require("santoku.table") %>
<% arr = require("santoku.array") %>
<% str = require("santoku.string") %>

include $(addprefix ../, $(PARENT_DEPS_RESULTS))

# Auto-detect WASM build from compiler
ifneq (,$(findstring emcc,$(CC)))
_WASM = 1
endif

ifdef _WASM
LIB_LUA = $(shell find * -name '*.lua')
LIB_C = $(shell find * -name '*.c')
LIB_CXX = $(shell find * -name '*.cpp')
else
LIB_LUA = $(filter-out %.wasm.lua, $(shell find * -name '*.lua'))
LIB_C = $(filter-out %.wasm.c, $(shell find * -name '*.c'))
LIB_CXX = $(filter-out %.wasm.cpp, $(shell find * -name '*.cpp'))
endif

LIB_O = $(patsubst %.wasm.o,%.o,$(LIB_C:.c=.o) $(LIB_CXX:.cpp=.o))
LIB_D = $(LIB_O:.o=.d)
LIB_SO = $(LIB_O:.o=.$(LIB_EXTENSION))
LIB_H = $(shell find * -name '*.h')

INST_LUA = $(patsubst %.wasm.lua,%.lua,$(addprefix $(INST_LUADIR)/, $(LIB_LUA)))
INST_SO = $(addprefix $(INST_LIBDIR)/, $(LIB_SO))
INST_H = $(addprefix $(INST_PREFIX)/include/, $(LIB_H))

LIBFLAG = -shared

ifdef _WASM
WASM_LDFLAGS_FINAL = -Wno-emcc
endif

<%
inject_flags = function (env, wasm_env)
  if showing() then
    local out = { "\n" }
    for i = 1, #libs do
      local fp = str.match(libs[i], "lib/(.*)")
      local ext = str.lower(str.match(fp, ".*(%.[^%.]+)$"))
      local base = str.sub(fp, 1, #fp - #ext)
      if ext == ".c" or ext == ".cpp" then
        local flags = { cflags = {}, cxxflags = {}, ldflags = {} }
        local wasm_flags = { cflags = {}, cxxflags = {}, ldflags = {} }
        for k, v in pairs(env or {}) do
          if (type(k) == "string" and str.find(fp, k)) or (type(k) == "function" and k(fp)) then
            if v.cflags then arr.extend(flags.cflags, v.cflags) end
            if v.cxxflags then arr.extend(flags.cxxflags, v.cxxflags) end
            if v.ldflags then arr.extend(flags.ldflags, v.ldflags) end
          end
        end
        for k, v in pairs(wasm_env or {}) do
          if (type(k) == "string" and str.find(fp, k)) or (type(k) == "function" and k(fp)) then
            if v.cflags then arr.extend(wasm_flags.cflags, v.cflags) end
            if v.cxxflags then arr.extend(wasm_flags.cxxflags, v.cxxflags) end
            if v.ldflags then arr.extend(wasm_flags.ldflags, v.ldflags) end
          end
        end
        -- Emit rules with ifdef for wasm vs native flags
        local has_native = #flags.cflags > 0 or #flags.cxxflags > 0 or #flags.ldflags > 0
        local has_wasm = #wasm_flags.cflags > 0 or #wasm_flags.cxxflags > 0 or #wasm_flags.ldflags > 0
        if has_native or has_wasm then
          if has_wasm then
            arr.push(out, "ifdef _WASM\n")
            if #wasm_flags.cflags > 0 then
              arr.push(out, base, ".o: ", fp, "\n", "\t$(CC) -c $< -o $@ $(CFLAGS) $(LIB_CFLAGS) ",
                arr.concat(wasm_flags.cflags, " "), "\n\n")
            end
            if #wasm_flags.cxxflags > 0 then
              arr.push(out, base, ".o: ", fp, "\n", "\t$(CXX) -c $< -o $@ $(CXXFLAGS) $(LIB_CXXFLAGS) ",
                arr.concat(wasm_flags.cxxflags, " "), "\n\n")
            end
            if #wasm_flags.ldflags > 0 then
              arr.push(out, base, ".$(LIB_EXTENSION): ", base, ".o\n", "\t$(CC) $(LIBFLAG) $< -o $@ $(LDFLAGS) $(LIB_LDFLAGS) ",
                arr.concat(wasm_flags.ldflags, " "), " $(WASM_LDFLAGS_FINAL)\n\n")
            end
            if has_native then
              arr.push(out, "else\n")
            else
              arr.push(out, "endif\n")
            end
          end
          if has_native then
            if not has_wasm then
              arr.push(out, "ifndef _WASM\n")
            end
            if #flags.cflags > 0 then
              arr.push(out, base, ".o: ", fp, "\n", "\t$(CC) -c $< -o $@ $(CFLAGS) $(LIB_CFLAGS) ",
                arr.concat(flags.cflags, " "), "\n\n")
            end
            if #flags.cxxflags > 0 then
              arr.push(out, base, ".o: ", fp, "\n", "\t$(CXX) -c $< -o $@ $(CXXFLAGS) $(LIB_CXXFLAGS) ",
                arr.concat(flags.cxxflags, " "), "\n\n")
            end
            if #flags.ldflags > 0 then
              arr.push(out, base, ".$(LIB_EXTENSION): ", base, ".o\n", "\t$(CC) $(LIBFLAG) $< -o $@ $(LDFLAGS) $(LIB_LDFLAGS) ",
                arr.concat(flags.ldflags, " "), "\n\n")
            end
            arr.push(out, "endif\n")
          end
        end
      end
    end
    if #out > 1 then
      return arr.concat(out), false
    end
  end
end
%>

<% -- flags for all environments %>
LIB_CFLAGS := -I. $(addprefix -I, $(LUA_INCDIR)) <% return arr.concat(cflags or {}, " ") %> $(<% return var("CFLAGS") %>) $(LIB_CFLAGS)
LIB_CXXFLAGS := -I. $(addprefix -I, $(LUA_INCDIR)) <% return arr.concat(cxxflags or {}, " ") %> $(<% return var("CXXFLAGS") %>) $(LIB_CXXFLAGS)
LIB_LDFLAGS := $(addprefix -L, $(LUA_LIBDIR)) <% return arr.concat(ldflags or {}, " ") %> $(<% return var("LDFLAGS") %>) $(LIB_LDFLAGS)

<% -- flags for build/test environments (non-wasm-specific) %>
<% push(environment == "build") %>
LIB_CFLAGS += <% return arr.concat(tbl.get(build or {}, "cflags") or {}, " ") %>
LIB_CXXFLAGS += <% return arr.concat(tbl.get(build or {}, "cxxflags") or {}, " ") %>
LIB_LDFLAGS += <% return arr.concat(tbl.get(build or {}, "ldflags") or {}, " ") %>
<% pop() push(environment == "test") %>
LIB_CFLAGS += <% return arr.concat(tbl.get(test or {}, "cflags") or {}, " ") %>
LIB_CXXFLAGS += <% return arr.concat(tbl.get(test or {}, "cxxflags") or {}, " ") %>
LIB_LDFLAGS += <% return arr.concat(tbl.get(test or {}, "ldflags") or {}, " ") %>
<% pop() %>

<% -- wasm vs native flags, selected at make time %>
ifdef _WASM
<% push(environment == "build") %>
LIB_CFLAGS += <% return arr.concat(tbl.get(build or {}, "wasm", "cflags") or {}, " ") %>
LIB_CXXFLAGS += <% return arr.concat(tbl.get(build or {}, "wasm", "cxxflags") or {}, " ") %>
LIB_LDFLAGS += <% return arr.concat(tbl.get(build or {}, "wasm", "ldflags") or {}, " ") %>
<% pop() push(environment == "test") %>
LIB_CFLAGS += <% return arr.concat(tbl.get(test or {}, "wasm", "cflags") or {}, " ") %>
LIB_CXXFLAGS += <% return arr.concat(tbl.get(test or {}, "wasm", "cxxflags") or {}, " ") %>
LIB_LDFLAGS += <% return arr.concat(tbl.get(test or {}, "wasm", "ldflags") or {}, " ") %>
<% pop() %>
else
<% push(environment == "build") %>
LIB_CFLAGS += <% return arr.concat(tbl.get(build or {}, "native", "cflags") or {}, " ") %>
LIB_CXXFLAGS += <% return arr.concat(tbl.get(build or {}, "native", "cxxflags") or {}, " ") %>
LIB_LDFLAGS += <% return arr.concat(tbl.get(build or {}, "native", "ldflags") or {}, " ") %>
<% pop() push(environment == "test") %>
LIB_CFLAGS += <% return arr.concat(tbl.get(test or {}, "native", "cflags") or {}, " ") %>
LIB_CXXFLAGS += <% return arr.concat(tbl.get(test or {}, "native", "cxxflags") or {}, " ") %>
LIB_LDFLAGS += <% return arr.concat(tbl.get(test or {}, "native", "ldflags") or {}, " ") %>
<% pop() %>
endif

all: $(LIB_O) $(LIB_SO)

<% return inject_flags(rules, rules) %>
<% push(environment == "build") %>
<% return inject_flags(tbl.get(build or {}, "native", "rules"), tbl.get(build or {}, "wasm", "rules")) %>
<% pop() push(environment == "test") %>
<% return inject_flags(tbl.get(test or {}, "native", "rules"), tbl.get(test or {}, "wasm", "rules")) %>
<% pop() %>

%.o: %.wasm.c
	$(CC) -c $< -o $@ $(CFLAGS) $(LIB_CFLAGS)

%.o: %.wasm.cpp
	$(CXX) -c $< -o $@ $(CXXFLAGS) $(LIB_CXXFLAGS)

%.o: %.c
	$(CC) -c $< -o $@ $(CFLAGS) $(LIB_CFLAGS)

%.o: %.cpp
	$(CXX) -c $< -o $@ $(CXXFLAGS) $(LIB_CXXFLAGS)

%.$(LIB_EXTENSION): %.o
	$(CC) $(LIBFLAG) $< -o $@ $(LDFLAGS) $(LIB_LDFLAGS) $(WASM_LDFLAGS_FINAL)

install: $(INST_LUA) $(INST_SO) $(INST_H)

$(INST_LUADIR)/%.lua: ./%.wasm.lua
	@mkdir -p $(dir $@)
	@cp $< $@

$(INST_LUADIR)/%.lua: ./%.lua
	@mkdir -p $(dir $@)
	@cp $< $@

$(INST_LIBDIR)/%.$(LIB_EXTENSION): ./%.$(LIB_EXTENSION)
	@mkdir -p $(dir $@)
	@cp $< $@

$(INST_PREFIX)/include/%.h: ./%.h
	@mkdir -p $(dir $@)
	@cp $< $@

.PHONY: all install
