# santoku-make

The build and project framework behind the `toku` tool. It turns a project's
`make*.lua` descriptor into a built, tested, and installable luarocks package (a
library, a bin executable, or a web app), and underneath it provides a small
build-graph engine that the project layer is built on.

You normally drive this through the [`toku` CLI](../lua-santoku-cli/README.md);
this repo is the machinery it calls. This README orients the framework and the
project model; [`doc/usage.md`](doc/usage.md) is the by-example guide (the
low-level engine, the descriptor reference, and worked per-scenario examples).

Documentation and runnable examples: [santoku.dev](https://santoku.dev), under the
`santoku-make` tab.

## Two layers

- **`santoku.make`** (the engine): a dependency-graph build runner. `make()`
  returns a submake with `target(targets, deps, fn)` and `build(targets,
  verbosity)`; it resolves a target DAG by modification time, treats `fn = true`
  as a phony (always-stale) target, and reads `.d` sidecar files for transitive
  source dependencies. This is what `test/spec/santoku/make.lua` exercises.
- **`santoku.make.project`** (the project layer): `project.init(opts)` reads a
  `make*.lua` descriptor, classifies the project (lib/bin vs web), assembles an
  environment from the descriptor, and registers targets on a submake that render
  the framework's `.mk`/`.tk` templates and run the lifecycle (build/test/install/
  release).

The key idea: the `res/lib/*.mk` files (and any `*.tk*` file in a project) are not
special build scripts, they are templates. The project layer renders them with
[santoku.template](../lua-santoku-template/README.md), injecting an environment
inherited from your `make*.lua` (the merge chain is `base <- env.* ->
build/test`, further specialized by `native`/`wasm`). The rendered Makefiles are
then run.

## The descriptor

A project is a `make.lua` (or `make.common.lua`) that returns a table with an
`env` field:

```lua
return {
  env = {
    name = "my-lib",
    version = "0.0.1-1",
    license = "MIT",
    dependencies = { "lua == 5.1", "santoku >= 0.0.330-1" },
    test = { dependencies = { "luacov >= 0.15.0-1" } },
  },
}
```

`env` carries metadata (`name`/`version`/`license`/`public`/`homepage`), the
dependency sets (`dependencies`, `test.dependencies`, `build.dependencies`), C
build flags (`cflags`/`ldflags`, scoped by `build`/`test` and by `native`/`wasm`),
per-file `rules`, an optional `configure` hook, and, for web projects, `server`/
`client`/`nginx` blocks. See [`doc/usage.md`](doc/usage.md) for the full field
reference and real examples.

## Project layout

```
make.lua            descriptor (or make.common.lua + make.<env>.lua profiles)
lib/                library modules (.lua, .c, .tk.lua)
bin/                executable entry points (bin projects)
res/                resources (templated or copied)
test/spec/          test files
test/res/           test fixtures
deps/<name>/Makefile   vendored C dependency (writes results.mk)
```

Web projects add `client/` and `server/` trees. Builds are written under
`build/<env>/{build,test}` (e.g. `build/default/test`); `<env>` is selected with
`toku --env` and corresponds to a `make.<env>.lua` profile.

## Project types

- **lib**: compiles `lib/*.c` to shared objects, installs `.lua`/`.so` via
  luarocks. The common case.
- **bin**: ships executables under `bin/`; can be installed as luarocks command
  scripts or bundled to standalone binaries (via [santoku-bundle](../lua-santoku-bundle/README.md)).
- **web**: a `client/` (compiled to WebAssembly) plus a `server/` (OpenResty/Lua),
  with `start`/`stop` for a dev server. Demonstrated by
  `submodules/tokuboilerplate-web`.

## Vendored C dependencies

A `deps/<name>/Makefile` builds an upstream C library and appends `LIB_CFLAGS`/
`LIB_LDFLAGS` to a generated `results.mk`, which the build includes. The idiomatic
pattern is to compile the upstream sources directly with `$(CC) $(CFLAGS)` and
archive them (see santoku-sqlite, santoku-mustache, santoku-markdown for live
examples); `doc/usage.md` covers it.

## Building / testing

This repo uses the `toku` harness. `test/spec/santoku/make.lua` exercises the
engine. Run the suite through `toku`.

## License

Copyright 2025 Birch Point SWE

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
