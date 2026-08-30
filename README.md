<p align="center">
  <img src="https://santoku.dev/logo-santoku-make.png" height="64" alt="santoku-make">
</p>

# santoku-make

The build framework behind `toku`. A make-style dependency graph written in
Lua: declare targets, their dependencies, and the function that produces them, then build.
On top of that sits the project model that turns a `make.lua` descriptor into a full
build, test, install, and release pipeline for libraries, executables, and web apps.

## Install

```sh
luarocks install santoku-make
```

## Running toku in a container

A web project needs a large toolchain: Emscripten, OpenResty, node, tailwindcss,
esbuild, a C compiler and luarocks. If you would rather not install all of that,
the two images here run `toku` against the codebase in your current directory,
so you edit locally and everything executes in the container.

Build the image once:

```sh
docker build -t toku-web -f toku-web.dockerfile .
docker build -t toku-lib -f toku-lib.dockerfile .
```

Then use the wrapper in place of `toku`:

```sh
./toku-web.sh -- build --test
./toku-web.sh -- test
./toku-lib.sh -- test
```

Everything after `--` is passed to `toku`. Anything before it goes to the
container runtime, which is how you publish a port:

```sh
./toku-web.sh -p 8080:8080 -p 8443:8443 -- start --test
```

Both wrappers mount the current directory at `/app` and delete the container on
exit, so the build tree lands in your working tree as usual.

Flags, all optional and all before `--`:

| Flag | Meaning |
| --- | --- |
| `-c docker` / `-c podman` | force a runtime; otherwise docker is preferred, then podman |
| `-i <image>` | override the image name |
| `-n` | print the command that would run and exit, without running it |

`toku-lib` is much smaller: no Emscripten, OpenResty, node or python. Use it for
library projects, and `toku-web` for anything with a `client/`.

Podman gets `--userns=keep-id` automatically so files stay owned by you. Docker
has no equivalent default, so files written into your tree will be owned by
root; pass `-u "$(id -u):$(id -g)"` before `--` if that matters to you.

## Example

```lua
local make = require("santoku.make")
local fs = require("santoku.fs")

local m = make()

m.target({ "out/all.txt" }, { "src/head.txt", "src/body.txt" }, function (ts, ds)
  fs.writefile(ts[1], fs.readfile(ds[1]) .. fs.readfile(ds[2]))
end)

m.build({ "out/all.txt" })
```

Targets are rebuilt only when a dependency is newer, including dependencies discovered
from a generated `.d` file. Passing `true` instead of a function declares a phony target.

## Documentation

Runnable examples and the full API: [santoku.dev](https://santoku.dev/#santoku-make).

For agents and LLM tooling: [llms.txt](https://santoku.dev/llms.txt) for the index,
[llms-full.txt](https://santoku.dev/llms-full.txt) for every documented example.

## Tests

The tests are the spec. For the exhaustive surface, read them:
[`test/spec/santoku/make.lua`](test/spec/santoku/make.lua),
[`test/spec/santoku/make_common.lua`](test/spec/santoku/make_common.lua), and
[`test/spec/santoku/make_local_deps.lua`](test/spec/santoku/make_local_deps.lua).

## License

MIT, see [LICENSE](LICENSE).

## More examples

```lua
local test = require("santoku.test")

local err = require("santoku.error")
local assert = err.assert

local validate = require("santoku.validate")
local eq = validate.isequal

local arr = require("santoku.array")
local fs = require("santoku.fs")
local make = require("santoku.make")

test("targets are built from their dependencies, dependencies first", function ()

  local dir = "test/res/readme"

  fs.mkdirp(dir)

  arr.ieach(function (fp)
    return fs.rm(fp)
  end, fs.files(dir))

  local ran = {}
  local m = make()

  m.target({ dir .. "/head.txt", dir .. "/body.txt" }, {}, function (ts)
    ran[#ran + 1] = "parts"
    fs.writefile(ts[1], "Header\n")
    fs.writefile(ts[2], "Body\n")
  end)

  m.target({ dir .. "/all.txt" }, { dir .. "/head.txt", dir .. "/body.txt" },
    function (ts, ds)
      ran[#ran + 1] = "all"
      local parts = {}
      for i = 1, #ds do parts[i] = fs.readfile(ds[i]) end
      fs.writefile(ts[1], arr.concat(parts))
    end)

  m.target({ "everything" }, { dir .. "/all.txt" }, true)

  m.build({ "everything" }, 0)

  assert(eq("Header\nBody\n", fs.readfile(dir .. "/all.txt")))
  assert(eq(2, #ran))
  assert(eq("parts", ran[1]))
  assert(eq("all", ran[2]))

end)
```
