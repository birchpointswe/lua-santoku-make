<p align="center">
  <img src="https://santoku.dev/logo-santoku-make.png" height="64" alt="santoku-make">
</p>

# santoku-make

The build framework behind `toku`. A make-style dependency graph written in
Lua: declare targets, their dependencies, and the function that produces them, then build.
On top of that sits the project model that turns a `make.lua` descriptor into a full
build, test, install, and release pipeline for libraries, executables, and web apps.

## Documentation

Runnable examples and the full API: [santoku.dev](https://santoku.dev/#santoku-make).

The container images in this repository, for building and for deployment, are
documented at [start-lib](https://santoku.dev/start-lib) and
[start-web](https://santoku.dev/start-web).

For agents and LLM tooling: [llms.txt](https://santoku.dev/llms.txt) for the index,
[llms-full.txt](https://santoku.dev/llms-full.txt) for every documented example.

## License

MIT, see [LICENSE](LICENSE).
