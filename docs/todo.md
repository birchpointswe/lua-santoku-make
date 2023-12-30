# Now

- WASM
    - Ignore bins (for now)
    - Changing --sanitize should rebuild lib.mk, libs, and tests
    - Changing --profile should rebuild tests

# Next

- Web

# Later

- Implement init
- In non-wasm, test all lua versions sequentially
- Split make.project into separate repo
- WASM bins

# Eventually

- Support github dependencies

- Clean up handling of toku template configs, specifically excludes
- Remove basexx dependency
- Template file overrides, store default template files in actual files under
  the luarocks package conf dir instead of embedding
- Better error messages: no targets specified, nothing to do, etc.
- Returning nil should not mean failure (and it shouldn't fail silently anyway)
- Verbose/default mode
- Add indentation to output in verbose
- Some dependencies are order-dependent when they should not be, like
  base_lua_modules_ok, which must come after base_lib_makefile and
  base_bin_makefile

- Add a time cache so that a file that is a dependency of many others is not
  checked repeatedly (make sure sibling times are cached when one of them is
  targeted and thus all of them are re-made)
- Use system cp instead of read/write
- Implement test --command or similar
- luacov summary sometimes shows 0%

- Support luarocks' built in external dependencies functionality

- Allow single files to be passed in instead of tables

- Template should stream output so that it can be streamed to a file
