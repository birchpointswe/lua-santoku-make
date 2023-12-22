# TODO: Support deps

# include $(addprefix ../, $(PARENT_DEPS_RESULTS))

LIB_LUA = $(shell find * -name '*.lua')
LIB_C = $(shell find * -name '*.c')
LIB_CXX = $(shell find * -name '*.cpp')
LIB_O = $(LIB_C:.c=.o) $(LIB_CXX:.cpp=.o)
LIB_SO = $(LIB_O:.o=.$(LIB_EXTENSION))

INST_LUA = $(addprefix $(INST_LUADIR)/, $(LIB_LUA))
INST_SO = $(addprefix $(INST_LIBDIR)/, $(LIB_SO))

LIB_CFLAGS += -Wall $(addprefix -I, $(LUA_INCDIR))
LIB_CXXFLAGS += -Wall $(addprefix -I, $(LUA_INCDIR))
LIB_LDFLAGS += -Wall $(addprefix -L, $(LUA_LIBDIR))

<% template:push(build.istest) %>

ifeq ($(<% return variable_prefix %>_SANITIZE),1)
LIB_CFLAGS := -fsanitize=address -fsanitize=leak $(LIB_CFLAGS)
LIB_CXXFLAGS := -fsanitize=address -fsanitize=leak $(LIB_CXXFLAGS)
LIB_LDFLAGS := -fsanitize=address -fsanitize=leak $(LIB_LDFLAGS)
endif

<% template:pop() %>

all: $(LIB_O) $(LIB_SO)

%.o: %.c
	$(CC) $(LIB_CFLAGS) $(CFLAGS) -c -o $@ $<

%.o: %.cpp
	$(CXX) $(LIB_CXXFLAGS) $(CXXFLAGS) -c -o $@ $<

%.$(LIB_EXTENSION): %.o
	$(CC) $(LIB_LDFLAGS) $(LDFLAGS) $(LIBFLAG) -o $@ $<

install: $(INST_LUA) $(INST_SO)

$(INST_LUADIR)/%.lua: ./%.lua
	mkdir -p $(dir $@)
	cp $< $@

$(INST_LIBDIR)/%.$(LIB_EXTENSION): ./%.$(LIB_EXTENSION)
	mkdir -p $(dir $@)
	cp $< $@

.PHONY: all install
