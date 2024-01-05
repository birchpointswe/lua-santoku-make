include $(addprefix ../, $(PARENT_DEPS_RESULTS))

LIB_LUA = $(shell find * -name '*.lua')
INST_LUA = $(addprefix $(INST_LUADIR)/, $(LIB_LUA))

all:
	@# Nothing to do

install: $(INST_LUA)

$(INST_LUADIR)/%.lua: ./%.lua
	@mkdir -p $(dir $@)
	@cp $< $@

.PHONY: all install
