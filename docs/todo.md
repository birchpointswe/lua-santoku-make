# Now

- Client terser/minifier
- Client skip build if no env.client
- Client tests
- Client spa integrate service worker, sqlite db worker
- Server skip build if no env.server, still allow iterate

- Fix yield error in WASM tests
- Debounce inotify events

- Inject license and copyright

# Next

- Implement init
- In non-wasm, test all lua versions sequentially
- Use openresty luajit instead of env.interpreter()[1] for server tests

# Later

- Server profile doesn't print out as expected
- Coverage sometimes shows 0%

- res/* arent tracked as dependencies for this project (changing
  template.rockspec doesn't re-build project/lib.lua)

- Split make.project into separate repo
- Support github and local dependencies (Is this necessary? Are hooks enough?)
- WASM bins

- Clean up make.lua:
    - Separate sections for params required by build system and for template
      configuration and env for user files
    - Clean up handling of excludes

- Leverage MAIN_MODULE, SIDE_MODULE
- Don't restart server when only client code changes (cli flag to force restart)
- Cli pack command to produce an archive of server code
- Flag to override dist dir
- Checksum result of loading make.lua (encode to json? sorted? remove cycles,
  non-primitives, etc.)

# Eventually

- Hide or otherwise prevent NM/LDSHARED/CXX missing warnings from appearing

- Allow toku make release --wasm with an optional distinct library name. This
  would allow build.wasm flags to be used in a release tarball

- Allow library to set default --wasm with --native to revert

- Luacov in WASM doens't work due to bundling as a single chunk in a string, can
  luacov report on chunks? Can we fake a file? Is it work not bundling lua
  modules in WASM so coverage is reported?

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

- Save specify openresty_dir in a local .env.lua file

- Returning nil should not mean failure (and it shouldn't fail silently anyway)
- Better error messages: no targets specified, nothing to do, etc.

- Luacheck make.lua?

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
