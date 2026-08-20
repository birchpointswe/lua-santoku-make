# Using santoku-make

Worked guide to the framework. See the [README](../README.md) for orientation. The
commands that drive all of this live in the [`toku` CLI](../../lua-santoku-cli/README.md);
here we cover the build engine, the descriptor, and how real projects use it.

## The build engine  ·  `test/spec/santoku/make.lua`

`santoku.make` on its own is a dependency-graph runner, independent of any project
config. `make()` returns a submake; `target(targets, deps, fn)` registers nodes and
`build(targets, verbosity)` resolves them by modification time, running only what is
stale.

```lua
local make = require("santoku.make")
local fs = require("santoku.fs")

local m = make()

m.target(
  { "out/main.txt" },                                  -- targets (files)
  { "out/header.txt", "out/body.txt" },                -- dependencies
  function (ts, ds)                                     -- build fn
    local parts = {}
    for i = 1, #ds do parts[i] = fs.readfile(ds[i]) end
    fs.writefile(ts[1], table.concat(parts))
  end)

m.target({ "out/header.txt" }, {}, function (ts) fs.writefile(ts[1], "H\n") end)
m.target({ "out/body.txt" },   {}, function (ts) fs.writefile(ts[1], "B\n") end)

m.target({ "all" }, { "out/main.txt" }, true)          -- fn=true: phony, always stale
m.build({ "all" }, 3)                                  -- 3 = verbosity
```

A target with a build `fn` rebuilds when any dependency is newer; a target with no
`fn` and an existing file is a leaf (its modtime is used); `fn = true` marks a phony
aggregate. Transitive source dependencies recorded in `.d` sidecar files (written by
the template layer) are read back so a change to an included file invalidates the
output. The test above builds a header/body/footer tree and asserts the assembled
output, which is the whole engine surface.

## The project layer

`santoku.make.project` turns a `make*.lua` descriptor into a set of engine targets.
`project.init(opts)` (driven by `toku`) does the following:

1. Loads the descriptor (`make.lua`, or `make.<env>.lua` when `--env` is given).
2. Classifies the project: a `client/` or `server/` tree means web, otherwise
   lib/bin.
3. Builds an environment table from the descriptor and merges it: a `base` env
   (paths, `is_wasm`, a `var` helper) underneath `env.*` from your descriptor,
   specialized into a `build` env and a `test` env, each further shaped by the
   `native`/`wasm` variant blocks.
4. Registers targets that render the framework templates with that environment and
   then run the lifecycle.

The templates are ordinary files. `res/lib/lib.mk`, `res/lib/luarocks.mk`, and the
rockspec template are rendered through `santoku.template` (the `<% %>` blocks run at
generation time, reading the injected env), written into `build/<env>/...`, and run
as Makefiles. Any file in your project named `*.tk` or `*.tk.*` is treated the same
way: rendered with the project env, with the `.tk` stripped from the output name.
Files are otherwise copied; `env.rules` (below) overrides classification.

So "what the build does" is determined by your descriptor's env flowing into those
templates, not by hand-written Makefiles.

## Descriptor reference

All fields live under the returned table's `env`. Only `name`/`version` are
required.

**Metadata**
- `name`, `version`, `license`, `homepage` (rockspec fields).
- `public` (boolean): enables `pack`/`release` (publishing to luarocks + a GitHub
  release).
- `variable_prefix`: prefix for the build env vars (defaults to the upper-cased
  name).

**Dependencies**
- `dependencies`: runtime luarocks deps.
- `test.dependencies`: test-only deps.
- `build.dependencies`: deps installed into a host environment for template
  rendering (so a `.tk` file can `require` them at build time).
- Variant forms exist: `test.wasm.dependencies`, `test.native.dependencies`.

**Vendored third-party sources**
- `vendor`: array of `{ file, url, sha256, mirror }` entries naming pristine
  upstream archives that ship inside the rock. `file` is a path under `deps/`
  relative to the project root. `mirror` defaults to
  `<homepage>/releases/download/vendor/<basename>` and is tried before `url`.
  See the vendored-dependency scenario below.

**C build flags** (arrays, joined onto the compile/link lines)
- `cflags`, `cxxflags`, `ldflags`: applied to every build.
- Scope by phase: `build.cflags` / `test.cflags` (and `ldflags`, etc.).
- Scope by variant: `native.cflags` / `wasm.cflags`, and the combined
  `build.native.cflags`, `build.wasm.cflags`, `test.native.cflags`,
  `test.wasm.cflags`. Use these to give one set of sources different flags for the
  native shared-object build vs the Emscripten/WASM build.

**Per-file rules**
- `rules.exclude`, `rules.copy`, `rules.template`: arrays of Lua patterns selecting
  files to ignore, force-copy (skip templating), or force-template. Variant rules
  (`build.native.rules`, etc.) attach extra per-file compiler flags.

**Hook**
- `configure(submake, envs, register_public_file)`: called after the standard
  targets are registered, so you can add your own (asset pipelines, codegen, SSL
  cert generation). `envs.root`/`envs.server`/`envs.client` give the merged envs.

**Web blocks** (web projects): `server`, `client`, `nginx` (covered below).

## Scenario: a plain Lua library

The minimal descriptor: metadata plus dependencies. No C, no build steps.

```lua
-- lua-santoku-fs/make.lua
return {
  env = {
    name = "santoku-fs",
    version = "0.0.46-1",
    license = "MIT",
    dependencies = { "lua == 5.1", "santoku >= 0.0.328-1" },
  },
}
```

Add `test.dependencies` to keep test-only tools (e.g. `luacov`) out of the runtime
deps (see santoku-markdown). `lib/*.lua` is installed as-is; a `lib/*.tk.lua` is
rendered first.

## Scenario: a C extension with a vendored dependency

A C-extension lib compiles `lib/**/*.c` to shared objects. To link an upstream C
library, add a `deps/<name>/Makefile` and point flags at what it produces:

```lua
-- lua-santoku-sqlite/make.lua (excerpt)
cflags = { "-I$(PWD)/deps/sqlite3/" },
ldflags = { "$(PWD)/deps/sqlite3/sqlite-amalgamation-3490200/libsqlite3.a", "-lm" },
```

```make
# deps/sqlite3/Makefile (shape)
results.mk:
	[ -f <archive> ] || { echo "missing vendored <archive>; run 'toku vendor'" >&2; exit 1; }
	tar xf <archive>
	cd <src> && $(CC) -c $(SQLITE_CFLAGS) $(CFLAGS) -o sqlite3.o sqlite3.c
	cd <src> && $(AR) rcs libsqlite3.a sqlite3.o
	echo "LIB_CFLAGS += -I$(CURDIR)/<src>" >> results.mk
	echo "LIB_LDFLAGS += $(CURDIR)/<src>/libsqlite3.a" >> results.mk
	touch results.mk
```

The build discovers every `deps/*/` and `test/deps/*/`, runs its `Makefile` to
produce `results.mk`, and includes the resulting `LIB_CFLAGS`/`LIB_LDFLAGS`. Compile
the upstream sources directly with `$(CC) $(CFLAGS)` (so they inherit the toolchain),
rather than running the upstream's own `./configure`; santoku-sqlite, santoku-mustache,
and santoku-markdown all follow this pattern.

A deps Makefile never downloads. The upstream archive is a vendored artifact:
declared in the `vendor` table, fetched once by `toku vendor` into the source
tree's `deps/`, verified against its `sha256`, and gitignored. Because `pack`
enumerates `deps/` from the filesystem, the archive ships inside the release
tarball, so a consumer's `luarocks install` never reaches a third-party host.
`pack` and `release` refuse to run if a declared artifact is missing, fails its
checksum, or would be filtered out of the tarball by a `rules.exclude` pattern.

```lua
-- lua-santoku-mustache/make.lua (excerpt)
vendor = {
  {
    file = "deps/mustach/mustach-1.2.10.tar.gz",
    url = "https://gitlab.com/jobol/mustach/-/archive/1.2.10/mustach-1.2.10.tar.gz",
    sha256 = "95a2a351e748db9eeb98f40ba8bfbf010c1c6d2e725d31a3c7e602526d05bf90",
  },
}
```

`toku vendor` fetches from the birchpointswe `vendor` release tag and nowhere
else. It never falls back to `url`: a fallback would silently paper over an
un-seeded mirror, which is the one failure this mechanism exists to make loud.
`url` is provenance only, recorded so a human knows where the bytes originally
came from and can seed the mirror once:

    download <url>, check its sha256 against the vendor table, then
    gh release upload vendor <file> -R birchpointswe/<repo>

Omit `sha256` on a new entry and `toku vendor` prints the computed digest to
paste into `make.lua`, then exits non-zero. Modified upstream code is not a
vendored artifact: it is first-party, and belongs in-tree under `lib/` (as with
the lpeg port in santoku-lpeg).

## Scenario: native and WASM variants

One source tree, two builds. Put shared flags at the top level and variant-specific
flags under `native`/`wasm`:

```lua
-- lua-santoku-learn/make.common.lua (excerpt)
native = { cflags = { "-fopenmp", "$(MATHLIBS_CFLAGS)" },
           ldflags = { "-fopenmp", "$(MATHLIBS_LDFLAGS)" } },
build = { wasm = { ldflags = { "-sWASM_BIGINT" } } },
test  = { wasm = { ldflags = { "-sWASM_BIGINT" } } },
```

santoku-web is the fullest example: its `build.wasm.ldflags` carries the Emscripten
exports (`-sEXPORTED_FUNCTIONS`, `-sEXPORTED_RUNTIME_METHODS`, ...) and its
`test.wasm.ldflags` adds debug flags. WASM builds are selected with `toku ... --wasm`
(the build directory becomes `build/<env>-wasm`), and the templates branch on
`_WASM` (set when the compiler is `emcc`).

## Scenario: a web project

A web project pairs a WASM `client/` with an OpenResty `server/`. The canonical
example is `submodules/tokuboilerplate-web`. Its descriptor adds `server`, `client`,
and `nginx` blocks:

```lua
-- submodules/tokuboilerplate-web/make.common.lua (excerpt)
server = { dependencies = { "lua == 5.1", "santoku-web >= ...", "santoku-sqlite >= ...", ... } },
client = {
  files = true,
  dependencies = { ... },
  rules = { ["bundle$"] = { ldflags = { "--pre-js", "res/pre.js" } } },
  pwa = { title = "tokuboilerplate", name = "Toku Boilerplate",
          theme_color = "#1e293b", background_color = "#f5f5f5",
          transforms = { js = build.minify_js, css = build.minify_css, html = lp.minify_html } },
},
nginx = { ssl_self_signed = true, hsts = false, ssl_port = env.var("SSL_PORT", "8443"),
          domain = "localhost", port = env.var("PORT", "8080"), workers = "auto",
          modules = { "tokuboilerplate.web.init", "tokuboilerplate.web.sync" } },
```

- `server.dependencies` / `client.dependencies` are separate dep sets (the client is
  compiled to WASM).
- `nginx` configures the generated OpenResty config: ports, workers, TLS, and the
  Lua `modules` wired in (request handling lives in those modules, not in the
  descriptor).
- `client.pwa` drives manifest/icon generation and asset minification transforms.
- The `configure` hook does the rest of the asset pipeline (the boilerplate
  generates a self-signed cert, fetches fonts, runs Tailwind, and renders icons and
  splash screens with `submake.target(...)` calls, using `register_public_file` to
  publish hashed static assets).

Web projects are driven with `toku build`, `toku start`/`toku stop` (dev server), and
`toku test`. The `submodules/tokuboilerplate-lib` project is the matching plain
lib/bin example.

## Scenario: environment profiles

Share a base descriptor and override per environment. `make.common.lua` holds the
shared config; `make.<env>.lua` loads it and tweaks it:

```lua
-- make.prod.lua
local fs = require("santoku.fs")
local base = fs.runfile("make.common.lua")
base.env.client.files = false          -- minified production client
return base
```

`toku <cmd> --env prod` selects `make.prod.lua` and builds under `build/prod/`.
an application (dev/prod/release) and a service (prod/beta, plus a submodule lib)
are real multi-profile examples; a service also shows a `Dockerfile` invoking
`toku build --env prod`.

## The lifecycle

The project layer registers these (run via the matching `toku` command):

- **vendor**: fetch and sha256-verify the `vendor` artifacts into `deps/`. Run
  once per fresh clone, before `build`.
- **build**: render templates, install deps, compile.
- **test**: build the test env, run the suite (santoku-test-runner) and `luacheck`
  (`--skip-check` to skip). `iterate` re-runs on file changes.
- **install**: `luarocks make` the built rock (or bundle `bin/` to standalone
  executables with `--bundled`).
- **pack** / **release** (when `public = true`): build a tarball; tag, push, create a
  GitHub release, and upload to luarocks.
- **exec**: run a command with the project's `LUA_PATH`/`LUA_CPATH` set.
- **clean**: remove generated artifacts (`--all` for the whole build dir, `--deps`
  for installed modules).

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
