# tk: mk
<% tbl = require("santoku.table") %>
<% arr = require("santoku.array") %>
<% str = require("santoku.string") %>

include $(addprefix ../, $(PARENT_DEPS_RESULTS))

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
DEPFLAGS = -MMD -MP
LIB_SO = $(LIB_O:.o=.$(LIB_EXTENSION))
LIB_H = $(shell find * -name '*.h')
LIB_ARCHIVES = $(filter %.a, $(LDFLAGS) $(LIB_LDFLAGS))

LIB_REQ = $(LIB_O:.o=.requires)

TK_LUA_CDIR = $(if $(TK_ROCKS_DIR),$(TK_ROCKS_DIR)/../../lua/5.1)
TK_REQ_UNIVERSE := $(basename $(LIB_SO)) $(if $(TK_LUA_CDIR),$(patsubst $(TK_LUA_CDIR)/%.$(LIB_EXTENSION),%,$(shell find $(TK_LUA_CDIR) -name '*.$(LIB_EXTENSION)' 2>/dev/null)))
TK_REQ_HEADERS = $(foreach h,$(filter %.h,$(file < $(1))),$(lastword $(subst /include/, ,$(h))))
TK_REQ_MODULES = $(subst /,.,$(sort $(filter-out $(2),$(filter $(TK_REQ_UNIVERSE),$(foreach h,$(call TK_REQ_HEADERS,$(1)),$(basename $(h)) $(patsubst %/,%,$(dir $(h))))))))

INST_LUA = $(patsubst %.wasm.lua,%.lua,$(addprefix $(INST_LUADIR)/, $(LIB_LUA)))
INST_SO = $(addprefix $(INST_LIBDIR)/, $(LIB_SO))
INST_REQ = $(addprefix $(INST_LIBDIR)/, $(LIB_REQ))
INST_H = $(addprefix $(INST_PREFIX)/include/, $(LIB_H))

ifndef _WASM
LIB_LINK = $(LIB_O:.o=.link)
INST_O = $(addprefix $(INST_LIBDIR)/, $(LIB_O))
INST_LINK = $(addprefix $(INST_LIBDIR)/, $(LIB_LINK))
endif

LIBFLAG = -shared

ifdef _WASM
LIBFLAG = -r
WASM_LDFLAGS_FINAL =
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
            if v.cflags then arr.copy(flags.cflags, v.cflags) end
            if v.cxxflags then arr.copy(flags.cxxflags, v.cxxflags) end
            if v.ldflags then arr.copy(flags.ldflags, v.ldflags) end
          end
        end
        for k, v in pairs(wasm_env or {}) do
          if (type(k) == "string" and str.find(fp, k)) or (type(k) == "function" and k(fp)) then
            if v.cflags then arr.copy(wasm_flags.cflags, v.cflags) end
            if v.cxxflags then arr.copy(wasm_flags.cxxflags, v.cxxflags) end
            if v.ldflags then arr.copy(wasm_flags.ldflags, v.ldflags) end
          end
        end
        local has_native = #flags.cflags > 0 or #flags.cxxflags > 0 or #flags.ldflags > 0
        local has_wasm = #wasm_flags.cflags > 0 or #wasm_flags.cxxflags > 0 or #wasm_flags.ldflags > 0
        if has_native or has_wasm then
          if has_wasm then
            arr.push(out, "ifdef _WASM\n")
            if #wasm_flags.cflags > 0 then
              arr.push(out, base, ".o: ", fp, "\n", "\t$(CC) -c $< -o $@ $(DEPFLAGS) $(CFLAGS) $(LIB_CFLAGS) ",
                arr.concat(wasm_flags.cflags, " "), "\n\n")
            end
            if #wasm_flags.cxxflags > 0 then
              arr.push(out, base, ".o: ", fp, "\n", "\t$(CXX) -c $< -o $@ $(DEPFLAGS) $(CXXFLAGS) $(LIB_CXXFLAGS) ",
                arr.concat(wasm_flags.cxxflags, " "), "\n\n")
            end
            if #wasm_flags.ldflags > 0 then
              arr.push(out, base, ".$(LIB_EXTENSION): ", base, ".o $(LIB_ARCHIVES)\n", "\t$(CC) $(LIBFLAG) $< -o $@ $(LDFLAGS) $(LIB_LDFLAGS) ",
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
              arr.push(out, base, ".o: ", fp, "\n", "\t$(CC) -c $< -o $@ $(DEPFLAGS) $(CFLAGS) $(LIB_CFLAGS) ",
                arr.concat(flags.cflags, " "), "\n\n")
            end
            if #flags.cxxflags > 0 then
              arr.push(out, base, ".o: ", fp, "\n", "\t$(CXX) -c $< -o $@ $(DEPFLAGS) $(CXXFLAGS) $(LIB_CXXFLAGS) ",
                arr.concat(flags.cxxflags, " "), "\n\n")
            end
            if #flags.ldflags > 0 then
              arr.push(out, base, ".$(LIB_EXTENSION): ", base, ".o $(LIB_ARCHIVES)\n", "\t$(CC) $(LIBFLAG) $< -o $@ $(LDFLAGS) $(LIB_LDFLAGS) ",
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

TK_ROCK_INCDIR = $(or $(lastword $(sort $(wildcard $(TK_ROCKS_DIR)/$(1)/*/include))),$(error no headers found for rock '$(1)' under '$(TK_ROCKS_DIR)' - declare it as a dependency and install it into this tree))

LIB_CFLAGS := -I. $(addprefix -I, $(LUA_INCDIR)) <% return arr.concat(cflags or {}, " ") %> $(<% return var("CFLAGS") %>) $(LIB_CFLAGS)
LIB_CXXFLAGS := -I. $(addprefix -I, $(LUA_INCDIR)) <% return arr.concat(cxxflags or {}, " ") %> $(<% return var("CXXFLAGS") %>) $(LIB_CXXFLAGS)
LIB_LDFLAGS := $(addprefix -L, $(LUA_LIBDIR)) <% return arr.concat(ldflags or {}, " ") %> $(<% return var("LDFLAGS") %>) $(LIB_LDFLAGS)

<% push(environment == "build") %>
LIB_CFLAGS += <% return arr.concat(tbl.get(build or {}, {"cflags"}) or {}, " ") %>
LIB_CXXFLAGS += <% return arr.concat(tbl.get(build or {}, {"cxxflags"}) or {}, " ") %>
LIB_LDFLAGS += <% return arr.concat(tbl.get(build or {}, {"ldflags"}) or {}, " ") %>
<% pop() push(environment == "test") %>
LIB_CFLAGS += <% return arr.concat(tbl.get(test or {}, {"cflags"}) or {}, " ") %>
LIB_CXXFLAGS += <% return arr.concat(tbl.get(test or {}, {"cxxflags"}) or {}, " ") %>
LIB_LDFLAGS += <% return arr.concat(tbl.get(test or {}, {"ldflags"}) or {}, " ") %>
<% pop() %>

ifdef _WASM
<% push(environment == "build") %>
LIB_CFLAGS += -Oz
LIB_CXXFLAGS += -Oz
<% pop() %>
LIB_CFLAGS += <% return arr.concat(tbl.get(wasm or {}, {"cflags"}) or {}, " ") %>
LIB_CXXFLAGS += <% return arr.concat(tbl.get(wasm or {}, {"cxxflags"}) or {}, " ") %>
LIB_LDFLAGS += <% return arr.concat(tbl.get(wasm or {}, {"ldflags"}) or {}, " ") %>
<% push(environment == "build") %>
LIB_CFLAGS += <% return arr.concat(tbl.get(build or {}, {"wasm", "cflags"}) or {}, " ") %>
LIB_CXXFLAGS += <% return arr.concat(tbl.get(build or {}, {"wasm", "cxxflags"}) or {}, " ") %>
LIB_LDFLAGS += <% return arr.concat(tbl.get(build or {}, {"wasm", "ldflags"}) or {}, " ") %>
<% pop() push(environment == "test") %>
LIB_CFLAGS += <% return arr.concat(tbl.get(test or {}, {"wasm", "cflags"}) or {}, " ") %>
LIB_CXXFLAGS += <% return arr.concat(tbl.get(test or {}, {"wasm", "cxxflags"}) or {}, " ") %>
LIB_LDFLAGS += <% return arr.concat(tbl.get(test or {}, {"wasm", "ldflags"}) or {}, " ") %>
<% pop() %>
else
LIB_CFLAGS += <% return arr.concat(tbl.get(native or {}, {"cflags"}) or {}, " ") %>
LIB_CXXFLAGS += <% return arr.concat(tbl.get(native or {}, {"cxxflags"}) or {}, " ") %>
LIB_LDFLAGS += <% return arr.concat(tbl.get(native or {}, {"ldflags"}) or {}, " ") %>
<% push(environment == "build") %>
LIB_CFLAGS += <% return arr.concat(tbl.get(build or {}, {"native", "cflags"}) or {}, " ") %>
LIB_CXXFLAGS += <% return arr.concat(tbl.get(build or {}, {"native", "cxxflags"}) or {}, " ") %>
LIB_LDFLAGS += <% return arr.concat(tbl.get(build or {}, {"native", "ldflags"}) or {}, " ") %>
<% pop() push(environment == "test") %>
LIB_CFLAGS += <% return arr.concat(tbl.get(test or {}, {"native", "cflags"}) or {}, " ") %>
LIB_CXXFLAGS += <% return arr.concat(tbl.get(test or {}, {"native", "cxxflags"}) or {}, " ") %>
LIB_LDFLAGS += <% return arr.concat(tbl.get(test or {}, {"native", "ldflags"}) or {}, " ") %>
<% pop() %>
endif

all: $(LIB_O) $(LIB_SO) $(LIB_LINK) $(LIB_REQ)

<% return inject_flags(rules, rules) %>
<% push(environment == "build") %>
<% return inject_flags(tbl.get(build or {}, {"native", "rules"}), tbl.get(build or {}, {"wasm", "rules"})) %>
<% pop() push(environment == "test") %>
<% return inject_flags(tbl.get(test or {}, {"native", "rules"}), tbl.get(test or {}, {"wasm", "rules"})) %>
<% pop() %>

%.o: %.wasm.c
	$(CC) -c $< -o $@ $(DEPFLAGS) $(CFLAGS) $(LIB_CFLAGS)

%.o: %.wasm.cpp
	$(CXX) -c $< -o $@ $(DEPFLAGS) $(CXXFLAGS) $(LIB_CXXFLAGS)

%.o: %.c
	$(CC) -c $< -o $@ $(DEPFLAGS) $(CFLAGS) $(LIB_CFLAGS)

%.o: %.cpp
	$(CXX) -c $< -o $@ $(DEPFLAGS) $(CXXFLAGS) $(LIB_CXXFLAGS)

%.$(LIB_EXTENSION): %.o $(LIB_ARCHIVES)
	$(CC) $(LIBFLAG) $< -o $@ $(LDFLAGS) $(LIB_LDFLAGS) $(WASM_LDFLAGS_FINAL)

%.link: %.o Makefile
	@rm -f $@
	@printf '%s\n' $(notdir $<) > $@
	@printf '%s\n' $(notdir $(filter %.a, $(LDFLAGS) $(LIB_LDFLAGS))) >> $@
	@printf '%s\n' $(filter-out %.a, $(LDFLAGS) $(LIB_LDFLAGS)) >> $@

%.requires: %.o Makefile
	@rm -f $@
	@touch $@
	@for m in $(call TK_REQ_MODULES,$*.d,$*); do if LC_ALL=C grep -qaF "$$m" $<; then printf '%s\n' "$$m" >> $@; fi; done

install: $(INST_LUA) $(INST_SO) $(INST_O) $(INST_LINK) $(INST_REQ) $(INST_H)

$(INST_LUADIR)/%.lua: ./%.wasm.lua
	@mkdir -p $(dir $@)
	@cp $< $@

$(INST_LUADIR)/%.lua: ./%.lua
	@mkdir -p $(dir $@)
	@cp $< $@

$(INST_LIBDIR)/%.$(LIB_EXTENSION): ./%.$(LIB_EXTENSION)
	@mkdir -p $(dir $@)
	@cp $< $@

$(INST_LIBDIR)/%.o: ./%.o
	@mkdir -p $(dir $@)
	@cp $< $@

$(INST_LIBDIR)/%.link: ./%.link
	@mkdir -p $(dir $@)
	@cp $< $@
	@$(if $(filter %.a, $(LDFLAGS) $(LIB_LDFLAGS)),cp $(filter %.a, $(LDFLAGS) $(LIB_LDFLAGS)) $(dir $@),true)

$(INST_LIBDIR)/%.requires: ./%.requires
	@mkdir -p $(dir $@)
	@cp $< $@

$(INST_PREFIX)/include/%.h: ./%.h
	@mkdir -p $(dir $@)
	@cp $< $@

LIB_O_NO_D = $(foreach o,$(LIB_O),$(if $(wildcard $(o:.o=.d)),,$(o)))

$(LIB_O_NO_D): TK_FORCE_DEPS

TK_FORCE_DEPS:

.PHONY: all install TK_FORCE_DEPS

-include $(LIB_D)
