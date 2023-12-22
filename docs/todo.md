# Now

- Basic bins
- Basic deps
- Basic WASM

- Support .d files and generally adding dependencies to targets incrementally

- Cli args or config properties: profile, sanitize, wasm, env,

- Package top-level makefile as santoku.make.project and expose via santoku-cli:
    - toku make [ ...args ]
    - toku make init (creates project structure and config file)
    - toku make test
    - toku make release (uses )

# Next

- Web

# Later

- In non-wasm, test all lua versions sequentially

# Eventually

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
