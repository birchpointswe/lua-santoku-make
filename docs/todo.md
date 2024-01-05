# Now

- Project structure
    - make.lua
    - make.beta.lua
    - make.prod.lua
    - client
        - lib/example/home.lua
        - lib/example/dashboard.lua
        - lib/example/worker.lua
        - lib/example/db.lua
        - static/home.html
        - static/dashboard.html
        - test/example/...
    - server
        - lib/example/init.lua
        - lib/example/db.lua
        - lib/example/notes/create.lua
        - lib/example/notes/retrieve.lua
        - lib/example/notes/update.lua
        - lib/example/notes/delete.lua
        - test/example/...

- Make.lua divided into 3 sections
    - Top-level
        - name, version, etc
    - "client"
        - Contains modules to be used on the frontend
        - Normal library parameters except for name/version
        - Additional parameters
            - scripts = {
                "example.client.home" = { name = "home" },
                "example.client.dashboard" = { name = "dashboard" },
                "example.client.worker" = { name = "worker", sqlite = true },
              }
    - "server"
        - Contains modules to be used on the backend
        - Normal library parameters except for name/version
        - Additional parameters:
            - port, ssl, etc.
            - dependencies = {}
            - test { dependencies = {} }
            - hooks { pre_make = fn, post_make = fn }
            - init = "example.server.init"
            - routes = {
                { "POST", "/notes", "example.server.notes.create" },
                { "GET", "/notes", "example.server.notes.retrieve" },
                { "PATCH", "/notes", "example.server.notes.update" },
                { "DELETE", "/notes", "example.server.notes.delete" },
              }

- toku web build / toku web start
    - builds in the build/{client,server} folders
    - copies final assets to the build/dist folder
    - runs out of the build/dist folder
    - builds client assets via:
        - lib.init({
            wasm = true,
            config = ...,
            luarocks_tree = build/client/lua_modules,
          }):install()
    - builds server assets via:
        - toku lib install --luarocks-config X --luarocks-tree build/server/lua_modules
        - X specifies openresty luajit installation

- toku web build --test / toku web test
    - builds in the test/{client,server} folders
    - copies final assets to the test/dist folder
    - runs out of the test/dist folder
    - re-use luacheck and luacov configs for both server and client

- Web server tests
- build/default/server-test
    - server subdir: everything needed to run nginx (+ extra deps)
    - spec subdir: everything needed to run the specs
    - environment = "test", component = "server"
    - environment = "test", components = "server-spec"
    - Profile and coverage

- Web client (skip tests for now)
    - Don't install to server-test
    - Terser/minifier for HTML, JS, CSS

# Next

- Only build client lua, etc if client lua pages exist
- Only build client sqlite if configured for a specific page
- Only build server if config.server ~= nil
- Client sqlite enable/disable

# Later

- res/* arent tracked as dependencies for this project (changing
  template.rockspec doesn't re-build project/lib.lua)

- Implement init
- Re-initialize on iteration loop so that new files are picked up automatically

- Fix WASM sanitize

- Split make.project into separate repo
- Support github and local dependencies (Is this necessary? Are hooks enough?)
- In non-wasm, test all lua versions sequentially
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
