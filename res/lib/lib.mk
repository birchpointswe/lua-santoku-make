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
<% push(environment == "build") %>
LIB_CFLAGS += <% return tbl.get(build or {}, "cflags") or "" %>
LIB_CXXFLAGS += <% return tbl.get(build or {}, "cxxflags") or "" %>
LIB_LDFLAGS += <% return tbl.get(build or {}, "ldflags") or "" %>
<% pop() %>

<% -- flags for test environments %>
<% push(environment == "test") %>
LIB_CFLAGS += <% return tbl.get(test or {}, "cflags") or "" %>
LIB_CXXFLAGS += <% return tbl.get(test or {}, "cxxflags") or "" %>
LIB_LDFLAGS += <% return tbl.get(test or {}, "ldflags") or "" %>
<% pop() %>

<% -- flags for build/native environments %>
<% push(environment == "build" and not wasm) %>
LIB_CFLAGS += <% return tbl.get(build or {}, "native", "cflags") or "" %>
LIB_CXXFLAGS += <% return tbl.get(build or {}, "native", "cxxflags") or "" %>
LIB_LDFLAGS += <% return tbl.get(build or {}, "native", "ldflags") or "" %>
<% pop() %>

<% -- flags for build/wasm environments %>
<% push(environment == "build" and wasm) %>
LIB_CFLAGS += <% return tbl.get(build or {}, "wasm", "cflags") or "" %>
LIB_CXXFLAGS += <% return tbl.get(build or {}, "wasm", "cxxflags") or "" %>
LIB_LDFLAGS += <% return tbl.get(build or {}, "wasm", "ldflags") or "" %>
<% pop() %>

<% -- flags for test/native environments %>
<% push(environment == "test" and not wasm) %>
LIB_CFLAGS += <% return tbl.get(test or {}, "native", "cflags") or "" %>
LIB_CXXFLAGS += <% return tbl.get(test or {}, "native", "cxxflags") or "" %>
LIB_LDFLAGS += <% return tbl.get(test or {}, "native", "ldflags") or "" %>
<% pop() %>

<% -- flags for test/wasm environments %>
<% push(environment == "test" and wasm) %>
LIB_CFLAGS += <% return tbl.get(test or {}, "wasm", "cflags") or "" %>
LIB_CXXFLAGS += <% return tbl.get(test or {}, "wasm", "cxxflags") or "" %>
LIB_LDFLAGS += <% return tbl.get(test or {}, "wasm", "ldflags") or "" %>
<% pop() %>

<% -- flags for test/sanitize %>
<% push(environment == "test" and sanitize) %>
LIB_CFLAGS := -fsanitize=address $(LIB_CFLAGS)
LIB_CXXFLAGS := -fsanitize=address $(LIB_CXXFLAGS)
LIB_LDFLAGS := -fsanitize=address $(LIB_LDFLAGS)
<% pop() %>

all: $(LIB_O) $(LIB_SO)

%.o: %.c
	$(CC) -c $< -o $@ $(CFLAGS) $(LIB_CFLAGS)

%.o: %.cpp
	$(CXX) -c $< -o $@ $(CXXFLAGS) $(LIB_CXXFLAGS)

%.$(LIB_EXTENSION): %.o
	$(CC) $(LIBFLAG) $< -o $@ $(LDFLAGS) $(LIB_LDFLAGS)

install: $(INST_LUA) $(INST_SO)

$(INST_LUADIR)/%.lua: ./%.lua
	@mkdir -p $(dir $@)
	@cp $< $@

$(INST_LIBDIR)/%.$(LIB_EXTENSION): ./%.$(LIB_EXTENSION)
	@mkdir -p $(dir $@)
	@cp $< $@

.PHONY: all install
