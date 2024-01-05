<%

  str = require("santoku.string")
  fs = require("santoku.fs")
  gen = require("santoku.gen")

  files = gen.ivals(libs):pastel("lib"):chain(gen.ivals(bins):pastel("bin"))
    :map(function (dir, fp)
      local mod = fs.stripextension(str.stripprefix(fp, dir)):gsub("/", "."):gsub("^.", "")
      return { mod = mod, fp = fp }
    end):vec()

%>

modules = {
  <% return gen.ivals(files):map(function (d)
    return str.interp("[\"%mod\"] = \"%src\"", { mod = d.mod, src = d.fp })
  end):concat(",\n") %>
}

include = {
  <% return gen.ivals(files):map(function (d)
    return str.quote(d.fp)
  end):concat(",\n") %>
}

statsfile = "<% return luacov_stats_file %>"
reportfile = "<% return luacov_report_file %>"
