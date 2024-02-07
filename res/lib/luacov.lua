<%

  str = require("santoku.string")
  stripprefix = str.stripprefix
  sinterp = str.interp
  squote = str.quote

  fs = require("santoku.fs")
  extension = fs.extension
  stripextension = fs.stripextension

  arr = require("santoku.array")
  aincludes = arr.includes
  concat = arr.concat

  iter = require("santoku.iter")
  collect = iter.collect
  map = iter.map
  reduce = iter.reduce
  ivals = iter.ivals
  chain = iter.chain
  filter = iter.filter
  paste = iter.paste

  gsub = string.gsub

  local include_ext = { ".lua", ".c", ".cpp" }

  files = collect(map(function (dir, fp)
    local m = stripextension(stripprefix(fp, dir))
    m = gsub(m, "/", ".")
    m = gsub(m, "^.", "")
    return { mod = m, fp = fp }
  end, filter(function (_, fp)
    return aincludes(include_ext, extension(fp))
  end, chain(paste("lib", ivals(libs)), paste("bin", ivals(bins))))))

%>

modules = {
  <% return concat(reduce(function (t, n)
    t[#t + 1] = sinterp("[\"%mod\"] = \"%src\"", { mod = n.mod, src = n.fp })
    return t
  end, {}, ivals(files)), ",\n") %>
}

include = {
  <% return concat(reduce(function (t, n)
    t[#t + 1] = squote(n.fp)
    return t
  end, {}, ivals(files)), ",\n") %>
}

statsfile = "<% return luacov_stats_file %>"
reportfile = "<% return luacov_report_file %>"
