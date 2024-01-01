# Now

- Web

# Next

- Profile and coverage for server
- Don't restart server when only client code changes (cli flag to force restart)
- Cli pack command to produce an archive of server code
- Flag to override dist dir
- Different lua_modules for server and tests
- Don't build client lua if no lua pages
- Client sqlite enable/disable
- Terser/minifier for HTML, JS, CSS

# Later

- res/* arent tracked as dependencies for this project (changing
  template.rockspec doesn't re-build project/lib.lua)

- Implement init
- Re-initialize on iteration loop so that new files are picked up automatically

- Fix WASM luacheck, sanitize, luacov, profile (lua_close on atexit?)

- Clean up make.lua: differentiate between parameters for the build system and
  parameters for userland templates (e.g. for custom delimiters)

- In non-wasm, test all lua versions sequentially
- Split make.project into separate repo
- Support github dependencies
- WASM bins

# Eventually

- Allow toku make release --wasm with an optional distinct library name. This
  would allow build.wasm flags to be used in a release tarball

- Allow library to set default --wasm with --native to revert

- toku make bundle to produce bundled executables
    - with --wasm, produce js, use the -wasm directory
    - without --wasm, re-compile with static linking to produce static
      executable, use a new -bundle directory

- Consider removing multi-target concept so that only one target is passed to
  make:target(...)

- If a templated file is not changed after re-running a template, don't
  write it (this will prevent needless re-builds)

- Support luarocks' built in external dependencies functionality
- Remove basexx dependency
- Template file overrides

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
