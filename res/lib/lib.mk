# TODO: Should use OBJ_EXTENSION

<% tbl = require("santoku.table") %>
<% arr = require("santoku.array") %>
<% str = require("santoku.string") %>

include $(addprefix ../, $(PARENT_DEPS_RESULTS))

<% push(not wasm) %>
LIB_LUA = $(filter-out %.wasm.lua, $(shell find * -name '*.lua'))
LIB_C = $(filter-out %.wasm.c, $(shell find * -name '*.c'))
LIB_CXX = $(filter-out %.wasm.cpp, $(shell find * -name '*.cpp'))
<% pop() push(wasm) %>
LIB_LUA = $(shell find * -name '*.lua')
LIB_C = $(shell find * -name '*.c')
LIB_CXX = $(shell find * -name '*.cpp')
<% pop() %>
LIB_O = $(patsubst %.wasm.o,%.o,$(LIB_C:.c=.o) $(LIB_CXX:.cpp=.o))
LIB_SO = $(LIB_O:.o=.$(LIB_EXTENSION))
LIB_H = $(shell find * -name '*.h')

INST_LUA = $(patsubst %.wasm.lua,%.lua,$(addprefix $(INST_LUADIR)/, $(LIB_LUA)))
INST_SO = $(addprefix $(INST_LIBDIR)/, $(LIB_SO))
INST_H = $(addprefix $(INST_PREFIX)/include/, $(LIB_H))

LIBFLAG = -shared

<% inject_flags = function (env)
  if showing() then
    local out = { "\n" }
    for i = 1, #libs do
      local fp = str.match(libs[i], "lib/(.*)")
      local ext = str.lower(str.match(fp, ".*(%.[^%.]+)$"))
      local base = str.sub(fp, 1, #fp - #ext)
      if ext == ".c" or ext == ".cpp" then
        local flags = { cflags = {}, cxxflags = {}, ldflags = {} }
        for k, v in pairs(env or {}) do
          if (type(k) == "string" and str.find(fp, k)) or (type(k) == "function" and k(fp)) then
            if v.cflags then
              arr.extend(flags.cflags, v.cflags)
            end
            if v.cxxflags then
              arr.extend(flags.cxxflags, v.cxxflags)
            end
            if v.ldflags then
              arr.extend(flags.ldflags, v.ldflags)
            end
          end
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
      end
    end
    if #out > 1 then
      return arr.concat(out), false
    end
  end
end %>

<% -- flags for all environments %>
LIB_CFLAGS := -Wall -I. $(addprefix -I, $(LUA_INCDIR)) <% return arr.concat(cflags or {}, " ") %> $(<% return var("CFLAGS") %>) $(LIB_CFLAGS)
LIB_CXXFLAGS := -Wall -I. $(addprefix -I, $(LUA_INCDIR)) <% return arr.concat(cxxflags or {}, " ") %> $(<% return var("CXXFLAGS") %>) $(LIB_CXXFLAGS)
LIB_LDFLAGS := -Wall $(addprefix -L, $(LUA_LIBDIR)) <% return arr.concat(ldflags or {}, " ") %> $(<% return var("LDFLAGS") %>) $(LIB_LDFLAGS)

<% -- flags for build environments %>
<% push(environment == "build") %>
LIB_CFLAGS += <% return arr.concat(tbl.get(build or {}, "cflags") or {}, " ") %>
LIB_CXXFLAGS += <% return arr.concat(tbl.get(build or {}, "cxxflags") or {}, " ") %>
LIB_LDFLAGS += <% return arr.concat(tbl.get(build or {}, "ldflags") or {}, " ") %>
<% pop() push(environment == "test") %>
LIB_CFLAGS += <% return arr.concat(tbl.get(test or {}, "cflags") or {}, " ") %>
LIB_CXXFLAGS += <% return arr.concat(tbl.get(test or {}, "cxxflags") or {}, " ") %>
LIB_LDFLAGS += <% return arr.concat(tbl.get(test or {}, "ldflags") or {}, " ") %>
<% pop() push(environment == "build" and not wasm) %>
LIB_CFLAGS += <% return arr.concat(tbl.get(build or {}, "native", "cflags") or {}, " ") %>
LIB_CXXFLAGS += <% return arr.concat(tbl.get(build or {}, "native", "cxxflags") or {}, " ") %>
LIB_LDFLAGS += <% return arr.concat(tbl.get(build or {}, "native", "ldflags") or {}, " ") %>
<% pop() push(environment == "build" and wasm) %>
LIB_CFLAGS += <% return arr.concat(tbl.get(build or {}, "wasm", "cflags") or {}, " ") %>
LIB_CXXFLAGS += <% return arr.concat(tbl.get(build or {}, "wasm", "cxxflags") or {}, " ") %>
LIB_LDFLAGS += <% return arr.concat(tbl.get(build or {}, "wasm", "ldflags") or {}, " ") %>
<% pop() push(environment == "test" and not wasm) %>
LIB_CFLAGS += <% return arr.concat(tbl.get(test or {}, "native", "cflags") or {}, " ") %>
LIB_CXXFLAGS += <% return arr.concat(tbl.get(test or {}, "native", "cxxflags") or {}, " ") %>
LIB_LDFLAGS += <% return arr.concat(tbl.get(test or {}, "native", "ldflags") or {}, " ") %>
<% pop() push(environment == "test" and wasm) %>
LIB_CFLAGS += <% return arr.concat(tbl.get(test or {}, "wasm", "cflags") or {}, " ") %>
LIB_CXXFLAGS += <% return arr.concat(tbl.get(test or {}, "wasm", "cxxflags") or {}, " ") %>
LIB_LDFLAGS += <% return arr.concat(tbl.get(test or {}, "wasm", "ldflags") or {}, " ") %>
<% pop() %>

all: $(LIB_O) $(LIB_SO)

<% return inject_flags(rules) %>
<% push(environment == "build") %>
<% return inject_flags(tbl.get(build or {}, "rules")) %>
<% pop() push(environment == "test") %>
<% return inject_flags(tbl.get(test or {}, "rules")) %>
<% pop() push(environment == "build" and not wasm) %>
<% return inject_flags(tbl.get(build or {}, "native", "rules")) %>
<% pop() push(environment == "build" and wasm) %>
<% return inject_flags(tbl.get(build or {}, "wasm", "rules")) %>
<% pop() push(environment == "test" and not wasm) %>
<% return inject_flags(tbl.get(test or {}, "native", "rules")) %>
<% pop() push(environment == "test" and wasm) %>
<% return inject_flags(tbl.get(test or {}, "wasm", "rules")) %>
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
	$(CC) $(LIBFLAG) $< -o $@ $(LDFLAGS) $(LIB_LDFLAGS)

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
