DEPS_DIRS = $(shell find deps/* -maxdepth 0 -type d 2>/dev/null) $(shell find test/deps/* -maxdepth 0 -type d 2>/dev/null)
DEPS_RESULTS = $(addsuffix /results.mk, $(DEPS_DIRS))

include $(DEPS_RESULTS)

all: $(DEPS_RESULTS) $(TEST_RUN_SH)
	@if [ -d lib ]; then $(MAKE) -C lib PARENT_DEPS_RESULTS="$(DEPS_RESULTS)"; fi

install: all
	@if [ -d lib ]; then $(MAKE) -C lib install; fi

deps/%/results.mk: deps/%/Makefile
	@$(MAKE) -C "$(dir $@)"

test/deps/%/results.mk: test/deps/%/Makefile
	@$(MAKE) -C "$(dir $@)"

.PHONY: all install
