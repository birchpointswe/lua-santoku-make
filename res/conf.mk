SRC_CONF = $(shell find * -type f)
INST_CONF = $(addprefix $(INST_CONFDIR)/, $(CONF))

all:
	@# Nothing to do here

install: $(INST_CONF)

$(INST_CONFDIR)/%: ./%
	@mkdir -p $(dir $@)
	@cp $< $@

.PHONY: all install
