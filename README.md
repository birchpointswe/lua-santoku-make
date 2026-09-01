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

`toku-web` sets `TOKU_FG=1`, which keeps `toku start` in the foreground.
Backgrounding OpenResty and exiting would let toku, as PID 1 under `--rm`, stop
the container along with the server and the port mapping, and nothing would
report an error while the published port never answers. Set `TOKU_FG` or pass
`--fg` in a container you build yourself.

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

## Deployment images

`toku-web` and `toku-lib` are build images; nothing in the toolchain is needed
at runtime. Two runtime bases strip it out. Build them from this repository's
root, since `toku-web-deployment` copies a file from the build context:

```sh
docker build -t toku-web-deployment -f toku-web-deployment.dockerfile .
docker build -t toku-lib-deployment -f toku-lib-deployment.dockerfile .
```

### toku-web-deployment

What the image guarantees:

- `debian:bookworm-slim` with `openresty` installed from the upstream repo and
  `ca-certificates` kept. `gnupg` and `wget` are purged after repo setup.
- A working `apt`: the openresty apt source and its key stay configured, but
  `/var/lib/apt/lists` is removed, so a downstream layer must run
  `apt-get update` before any `apt-get install` (and should remove the lists
  again afterwards).
- A non-root system user `worker`, uid 10001, gid 0, no home, `nologin`. No
  `USER` directive is set: the nginx master starts as whatever the runtime
  assigns and the server config's `user` directive (or the orchestrator's
  arbitrary-uid convention) drops the workers. If your nginx config names a
  different user, add it downstream.
- `toku-deploy-setup <build-tree> [dist-dir]` on the PATH. It deletes
  `*.o`/`*.a`/`*.link` install intermediates, applies the arbitrary-uid
  permission convention (`chgrp -R 0`, `chmod -R g-w,o-w`, group-writable
  `temp`), marks `run.sh` executable, symlinks `logs/{access,error}.log` to
  stdout and stderr, and runs `ldconfig`. `dist-dir` defaults to
  `<build-tree>/main/dist`.
- `ENV OPENRESTY_DIR=/usr/local/openresty`, `WORKDIR /app`, and a default
  `CMD` of `sh -c "umask 002; exec ./run.sh --fg"`.

What a downstream image must add: the built tree, a `toku-deploy-setup` call,
and a `WORKDIR` pointing at the dist directory.

App configuration such as SSL cert and key paths, ports and domain belongs in
the **builder** stage. The configure hook reads those while rendering
`nginx.conf`, and the generated `run.sh` only exports the values baked in at
render time before exec'ing openresty against a static config. Nothing
re-renders when the container starts, so the same variables set in the runtime
stage have no effect. The names come from your `variable_prefix`, so a project
named `my-app` reads `MY_APP_SSL_CERT`, not `SSL_CERT`.

`--env prod` also requires a `make.prod.lua`; no scaffold ships one. The
smallest that works returns a table merged over `make.lua`:

```lua
return { env = { server = { host = "example.com" } } }
```

```dockerfile
FROM toku-web AS builder
WORKDIR /app
COPY . .
RUN MY_APP_SSL_CERT=/home/app/cert.pem \
    MY_APP_SSL_KEY=/home/app/privkey.pem \
    toku build --env prod

FROM toku-web-deployment
COPY --from=builder /app/build/prod /app/build/prod
RUN toku-deploy-setup /app/build/prod
WORKDIR /app/build/prod/main/dist
```

Extending with native dependencies:

```dockerfile
FROM toku-web-deployment
RUN apt-get update \
    && apt-get -y install --no-install-recommends libsqlite3-0 \
    && rm -rf /var/lib/apt/lists/*
```

### toku-lib-deployment

Library projects have no long-running runtime; the deployable artifact is a
bundled executable from `toku install --bundled`, whose dynamic dependencies
reduce to system libraries plus `liblua5.1`. The image is
`debian:bookworm-slim` plus `liblua5.1-0` and `ca-certificates`, the same
`worker` user, `WORKDIR /app`, and a working `apt` under the same
update-first rule:

```dockerfile
FROM toku-lib AS builder
WORKDIR /app
COPY . .
RUN toku install --bundled --prefix /usr/local

FROM toku-lib-deployment
COPY --from=builder /usr/local/bin/mytool /usr/local/bin/mytool
USER worker
ENTRYPOINT ["mytool"]
```

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
