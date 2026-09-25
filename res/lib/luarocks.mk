DEPS_DIRS = $(shell find deps/* -maxdepth 0 -type d 2>/dev/null) $(shell find test/deps/* -maxdepth 0 -type d 2>/dev/null)
DEPS_RESULTS = $(addsuffix /results.mk, $(DEPS_DIRS))

include $(DEPS_RESULTS)

all: $(DEPS_RESULTS) $(TEST_RUN_SH)
	@if [ -d lib ]; then $(MAKE) --no-print-directory -C lib PARENT_DEPS_RESULTS="$(DEPS_RESULTS)"; fi
	@if [ -d bin ]; then $(MAKE) --no-print-directory -C bin PARENT_DEPS_RESULTS="$(DEPS_RESULTS)"; fi

install: all
	@if [ -d lib ]; then $(MAKE) --no-print-directory -C lib install; fi
	@if [ -d bin ]; then $(MAKE) --no-print-directory -C bin install; fi

RESULTS_NEEDS_MAKEFILE = grep -Eq '^results\.mk:(.*[[:space:]])?Makefile([[:space:]]|$$)' "$<" || { echo "$<: the results.mk rule must list Makefile as a prerequisite, or editing this Makefile rebuilds nothing. Write: results.mk: Makefile" >&2; exit 1; }

deps/%/results.mk: deps/%/Makefile
	@$(RESULTS_NEEDS_MAKEFILE)
	@$(MAKE) --no-print-directory -C "$(dir $@)"

test/deps/%/results.mk: test/deps/%/Makefile
	@$(RESULTS_NEEDS_MAKEFILE)
	@$(MAKE) --no-print-directory -C "$(dir $@)"

.PHONY: all install
