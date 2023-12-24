# Now

- Basic WASM

- Cli args or config properties: test, profile, sanitize, wasm, env, template file
  overrides, TEST=xxx, TEST_CMD=xxx
  - toku make test
  - toku make release
  - toku make test --iterate --wasm --profile
  - toku make --dir .workdir --config config.beta.lua --env beta test --iterate (for client/server)
  - toku make --dir build --env beta test --iterate (for client/server)
  - Default config is make.lua
    - If --env is specified, config is make.[env].lua
  - Default build dir is build/default/xxx
    - --dir changes "build"
    - --env changes "default"
    - --config changes config file, and requires --env be specified
  - toku make init [ --web | --lib ]
    - create directories, boilerplate files, etc.
    - config file env.type is set to either "web" or "lib"

- Install make/* as as actual files (not embedded) to lua confdir
- Support release

# Next

- Generate and load .d files with renderfile
- Web

# Later

- In non-wasm, test all lua versions sequentially

# Eventually

- inotifywait shouldn't listen to access events
- Better error messages: no targets specified, nothing to do, etc.
- Returning nil should not mean failure (and it shouldn't fail silently anyway)
- Verbose/default mode
- Add indentation to output in verbose

- Add a time cache so that a file that is a dependency of many others is not
  checked repeatedly (make sure sibling times are cached when one of them is
  targeted and thus all of them are re-made)
- Use system cp instead of read/write

- Support luarocks' built in external dependencies functionality

- Allow single files to be passed in instead of tables

- Template should stream output so that it can be streamed to a file
