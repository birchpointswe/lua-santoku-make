# Now

- Save init flags in a file that make.lua depends on, causing cascading re-build
- Implement test --single=spec/santoku/gen.lua
- Implement test --command=true
- Integrate with CLI

- Split make.project into separate repo

- Check if profile, sanitize work

- CLI:
  - toku make test
  - toku make release
  - toku make test --iterate --wasm --profile
  - toku make test --dir .workdir --config config.beta.lua --iterate
  - toku make test --dir build --env beta --iterate (reads make.beta.lua)
  - toku make init [ --web | --lib ]

# Next

- Lib WASM
- Generate and load .d files with renderfile
- Web

# Later

- Implement init
- In non-wasm, test all lua versions sequentially

# Eventually

- Clean up handling of toku template configs, specifically excludes
- Remove basexx dependency
- Template file overrides, store default template files in actual files under
  the luarocks package conf dir instead of embedding
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
