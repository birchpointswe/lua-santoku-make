# Now

- After prolonged iterate sessions, inotify-utils wakeups trigger FD_SETSIZE
  errors that perpetually re-throw until Ctrl-C restart. Suspected causes:
    - File descriptor leak in iterate loop (lib.tk.lua:668-742, web.tk.lua:1244-1313)
    - inotifywait spawned repeatedly without cleanup
    - .d file scanning may leak file handles

- When building JS code with client.files=true (embed files instead of bundling
  bytecode), the main program runs but all require() calls fail with "module not
  found". Suspected causes:
    - wasm.lua embed_main_template has hardcoded paths (/lua_modules/...)
    - Paths in generated C code may not match actual embedded file locations
    - LUA_PATH/CPATH in the compiled .c file may be incorrect relative to the
      --embed-file paths passed to emcc
    - Verify the relationship between bundle() options and the paths emcc uses for
      the virtual filesystem

- struct stat st_mtim not available on macos

# Next

- Changes to make.*.lua files don't trigger rebuilds
- Prevent stale modules from persisting (if lib removes a submodule between
  versions, the old module should fail to bundle - currently doesn't)
- Source maps for WASM builds
- res/* not tracked as dependencies (changing template.rockspec doesn't rebuild)

- Allow shared common lib for multiple generated .js files
- Client skip build if no env.client defined
- Server skip build if no env.server, still allow iterate
- Fix yield error in WASM tests (if still occurring)

- web test --iterate doesn't work without at least one test file

- Use openresty luajit instead of env.interpreter()[1] for server tests
- In non-wasm, test all lua versions sequentially

# Later

- Better error messages: no targets specified, nothing to do, etc.
- Add indentation to output in verbose mode
- Returning nil should not mean failure (shouldn't fail silently)

- Don't restart server when only client code changes (add cli flag to force)
- If templated file unchanged after re-running, don't write (prevent needless
  rebuilds)
- Checksum make.lua to detect config changes (encode json, sorted, no cycles)
- Flag to override dist dir
- Allow library to set default --wasm with --native to revert

- Some dependencies are order-dependent when they shouldn't be (e.g.
  base_lua_modules_ok must come after base_lib_makefile)
- Consider removing multi-target concept (single target to make:target())
- Leverage MAIN_MODULE, SIDE_MODULE for emscripten builds

- Template should stream output for large files
- Allow single files to be passed instead of tables
- Hide NM/LDSHARED/CXX missing warnings
- luacov summary sometimes shows 0% after rm -rf build
