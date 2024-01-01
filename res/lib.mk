# TODO: Should use OBJ_EXTENSION

<% tbl = require("santoku.table") %>

include $(addprefix ../, $(PARENT_DEPS_RESULTS))

LIB_LUA = $(shell find * -name '*.lua')
LIB_C = $(shell find * -name '*.c')
LIB_CXX = $(shell find * -name '*.cpp')
LIB_O = $(LIB_C:.c=.o) $(LIB_CXX:.cpp=.o)
LIB_SO = $(LIB_O:.o=.$(LIB_EXTENSION))

INST_LUA = $(addprefix $(INST_LUADIR)/, $(LIB_LUA))
INST_SO = $(addprefix $(INST_LIBDIR)/, $(LIB_SO))

<% -- flags for all environments %>
LIB_CFLAGS += -Wall $(addprefix -I, $(LUA_INCDIR)) $(<% return var("CFLAGS") %>) <% return cflags %>
LIB_CXXFLAGS += -Wall $(addprefix -I, $(LUA_INCDIR)) $(<% return var("CXXFLAGS") %>) <% return cxxflags %>
LIB_LDFLAGS += -Wall $(addprefix -L, $(LUA_LIBDIR)) $(<% return var("LDFLAGS") %>) <% return ldflags %>

<% -- flags for build environments %>
<% template:push(environment == "build") %>
LIB_CFLAGS += <% return tbl.get(build or {}, "cflags") or "" %>
LIB_CXXFLAGS += <% return tbl.get(build or {}, "cxxflags") or "" %>
LIB_LDFLAGS += <% return tbl.get(build or {}, "ldflags") or "" %>
<% template:pop() %>

<% -- flags for test environments %>
<% template:push(environment == "test") %>
LIB_CFLAGS += <% return tbl.get(test or {}, "cflags") or "" %>
LIB_CXXFLAGS += <% return tbl.get(test or {}, "cxxflags") or "" %>
LIB_LDFLAGS += <% return tbl.get(test or {}, "ldflags") or "" %>
<% template:pop() %>

<% -- flags for build/native environments %>
<% template:push(environment == "build" and not wasm) %>
LIB_CFLAGS += <% return tbl.get(build or {}, "native", "cflags") or "" %>
LIB_CXXFLAGS += <% return tbl.get(build or {}, "native", "cxxflags") or "" %>
LIB_LDFLAGS += <% return tbl.get(build or {}, "native", "ldflags") or "" %>
<% template:pop() %>

<% -- flags for build/wasm environments %>
<% template:push(environment == "build" and wasm) %>
LIB_CFLAGS += <% return tbl.get(build or {}, "wasm", "cflags") or "" %>
LIB_CXXFLAGS += <% return tbl.get(build or {}, "wasm", "cxxflags") or "" %>
LIB_LDFLAGS += <% return tbl.get(build or {}, "wasm", "ldflags") or "" %>
<% template:pop() %>

<% -- flags for test/native environments %>
<% template:push(environment == "test" and not wasm) %>
LIB_CFLAGS += <% return tbl.get(test or {}, "native", "cflags") or "" %>
LIB_CXXFLAGS += <% return tbl.get(test or {}, "native", "cxxflags") or "" %>
LIB_LDFLAGS += <% return tbl.get(test or {}, "native", "ldflags") or "" %>
<% template:pop() %>

<% -- flags for test/wasm environments %>
<% template:push(environment == "test" and wasm) %>
LIB_CFLAGS += <% return tbl.get(test or {}, "wasm", "cflags") or "" %>
LIB_CXXFLAGS += <% return tbl.get(test or {}, "wasm", "cxxflags") or "" %>
LIB_LDFLAGS += <% return tbl.get(test or {}, "wasm", "ldflags") or "" %>
<% template:pop() %>

<% -- flags for test/sanitize %>
<% template:push(environment == "test" and sanitize) %>
LIB_CFLAGS := -fsanitize=address -fsanitize=leak $(LIB_CFLAGS)
LIB_CXXFLAGS := -fsanitize=address -fsanitize=leak $(LIB_CXXFLAGS)
LIB_LDFLAGS := -fsanitize=address -fsanitize=leak $(LIB_LDFLAGS)
<% template:pop() %>

<% -- flags for test/sanitize/wasm %>
<% template:push(environment == "test" and sanitize and wasm) %>
LIB_CFLAGS += <% return tbl.get(test or {}, "wasm", "sanitize", "cflags") or "" %>
LIB_CXXFLAGS += <% return tbl.get(test or {}, "wasm", "sanitize", "cxxflags") or "" %>
LIB_LDFLAGS += <% return tbl.get(test or {}, "wasm", "sanitize", "ldflags") or "" %>
<% template:pop() %>

all: $(LIB_O) $(LIB_SO)

%.o: %.c
	$(CC) $(CFLAGS) $(LIB_CFLAGS) -c -o $@ $<

%.o: %.cpp
	$(CXX) $(CXXFLAGS) $(LIB_CXXFLAGS) -c -o $@ $<

%.$(LIB_EXTENSION): %.o
	$(CC) $(LDFLAGS) $(LIB_LDFLAGS) $(LIBFLAG) -o $@ $<

install: $(INST_LUA) $(INST_SO)

$(INST_LUADIR)/%.lua: ./%.lua
	@mkdir -p $(dir $@)
	@cp $< $@

$(INST_LIBDIR)/%.$(LIB_EXTENSION): ./%.$(LIB_EXTENSION)
	@mkdir -p $(dir $@)
	@cp $< $@

.PHONY: all install
