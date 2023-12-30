# Now

- WASM
    - Ignore bins (for now)
    - Changing --sanitize should rebuild lib.mk, libs, and tests
    - Changing --profile should rebuild tests

# Next

- Web

- Profile and coverage for server
- Don't restart server when only client code changes (cli flag to force restart)
- Cli pack command to produce an archive of server code
- Flag to override dist dir
- Different lua_modules for server and tests
- Don't build client lua if no lua pages
- Client sqlite enable/disable
- Terser/minifier for HTML, JS, CSS

# Later

- Implement init
- Re-initialize on iteration loop so that new files are picked up automatically

- In non-wasm, test all lua versions sequentially
- Split make.project into separate repo
- Support github dependencies
- WASM bins

# Eventually

- Consider removing multi-target concept so that only one target is passed to
  make:target(...)

- If a templated file is not changed after re-running a template, don't
  write it (this will prevent needless re-builds)

- Support luarocks' built in external dependencies functionality
- Remove basexx dependency
- Template file overrides

- Clean up handling of toku template configs, specifically excludes
- Returning nil should not mean failure (and it shouldn't fail silently anyway)
- Better error messages: no targets specified, nothing to do, etc.

- Add indentation to output in verbose
- Some dependencies are order-dependent when they should not be, like
  base_lua_modules_ok, which must come after base_lib_makefile and
  base_bin_makefile

- Make sure that sibling times are cached when one of them is targeted and thus
  all of them are re-made
- luacov summary sometimes shows 0%, especially after a rm -rf of the build
  directory

- Allow single files to be passed in instead of tables

- Template should stream output so that it can be streamed to a file
