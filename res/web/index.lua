<%
  fs = require("santoku.fs")
  it = require("santoku.iter")
  arr = require("santoku.array")
  str = require("santoku.string")
%>

<% push(app.trace) %>
require("santoku.web.trace.index")("<% return app.trace_url %>", { name = "main" }, function ()
<% pop() %>

  local err = require("santoku.error")
  local error = err.error

  local js = require("santoku.web.js")
  local str = require("santoku.string")
  local it = require("santoku.iter")
  local arr = require("santoku.array")
  local util = require("santoku.web.util")
  local wrpc = require("santoku.web.worker.rpc.client")

  local scripts = {
    <%
      local viewdir = fs.join("client/spa", spa_name) .. "/"
      if fs.exists(viewdir) then
        return arr.concat(it.collect(it.map(function (fp)
          fp = str.stripprefix(fp, viewdir)
          fp = fs.stripextension(fp)
          fp = fp:gsub("/+", ".")
          return arr.concat({ "[", str.quote(fp), "] = require(\"", app.name, ".", spa_name, ".", fp, "\")" })
        end, it.filter(function (fp)
          return str.endswith(fp, ".html")
        end, fs.files(viewdir)))), ",\n")
      end
    %>
  }

  <% push(fs.exists(fs.join("client/lib", app.name, spa_name) .. ".lua")) %>
  <% if showing() then
    return arr.concat({ "local ctx = require(\"", app.name, ".", spa_name, "\").init()" })
  else
    return "local ctx = nil"
  end %>
  <% pop() %>

  local window = js.window
  local document = window.document
  local history = window.history
  local Array = js.Array
  local MutationObserver = js.MutationObserver

  local e_head = document.head
  local e_body = document.body
  local t_ripple = e_head:querySelector("template.ripple")

  local stack = {}
  local update_worker = false

  local M = {}

  M.setup_ripple = function (el)

    el:addEventListener("mousedown", function (_, ev)

      if el.disabled then
        return
      end

      ev:stopPropagation()
      ev:preventDefault()

      local e_ripple = util.clone(t_ripple)

      e_ripple:addEventListener("animationend", function ()
        e_ripple:remove()
      end)

      local e_wave = e_ripple:querySelector(".ripple-wave")
      local dia = math.min(el.offsetHeight, el.offsetWidth, 100)

      e_wave.style.width = dia .. "px"
      e_wave.style.height = dia .. "px"
      e_wave.style.left = (ev.offsetX - dia / 2) .. "px"
      e_wave.style.top = (ev.offsetY - dia / 2) .. "px"

      el:append(e_ripple)

    end)

  end

  -- TODO: there must be a better way to do this
  M.setup_observer = function (view)

    local old_classes = it.reduce(function (a, n)
      a[n] = true
      return a
    end, {}, it.map(str.sub, str.match(view.el.className, "[^%s]+")))

    view.observer = MutationObserver:new(function (_, mutations)

      return mutations:forEach(function (_, mu)

        local recs = view.observer:takeRecords()

        recs:push(mu)

        if not recs:find(function (_, mu)
          return mu["type"] == "attributes" and mu.attributeName == "class"
        end) then
          return
        end

        local fabs = false
        local snacks = false

        view.el.classList:forEach(function (_, c)
          if not old_classes[c] then
            if view.fab_observed_classes[c] then
              fabs = true
            end
            if view.snack_observed_classes[c] then
              snacks = true
            end
          end
        end)

        for c in it.keys(old_classes) do
          if not view.el.classList:contains(c) then
            if view.fab_observed_classes[c] then
              fabs = true
            end
            if view.snack_observed_classes[c] then
              snacks = true
            end
          end
        end

        old_classes = it.reduce(function (a, n)
          a[n] = true
          return a
        end, {}, it.map(str.sub, str.match(view.el.className or "", "[^%s]+")))

        if fabs then
          M.style_fabs(view, true)
        end

        if snacks then
          M.style_snacks(view, true)
        end

      end)

    end)

    view.observer:observe(view.el, {
      attributes = true,
      attributeFilter = { "class" }
    })

  end

  M.setup_fabs = function (next_view, last_view)

    next_view.e_fabs = next_view.el:querySelectorAll(".page > .fab")

    next_view.e_fabs_shared = {}
    next_view.e_fabs_top = {}
    next_view.e_fabs_bottom = {}
    next_view.fab_observed_classes = {}

    for i = 0, next_view.e_fabs.length - 1 do

      local el = next_view.e_fabs:item(i)

      for c in it.map(str.sub, str.match(el.dataset.hide or "", "[^%s]+")) do
        next_view.fab_observed_classes[c] = true
      end

      for c in it.map(str.sub, str.match(el.dataset.show or "", "[^%s]+")) do
        next_view.fab_observed_classes[c] = true
      end

      if el.classList:contains("minmax") then
        next_view.e_minmax = el
      end

      if not el.classList:contains("small") and
        last_view and last_view.el:querySelectorAll(".page > .fab:not(.small)")
      then
        arr.push(next_view.e_fabs_shared, el)
      elseif el.classList:contains("top") then
        arr.push(next_view.e_fabs_top, el)
      else
        arr.push(next_view.e_fabs_bottom, el)
      end

    end

    arr.reverse(next_view.e_fabs_bottom)

  end

  M.setup_snacks = function (next_view)

    next_view.e_snacks = next_view.el:querySelectorAll(".page > .snack")
    next_view.snack_observed_classes = {}

    for i = 0, next_view.e_snacks.length - 1 do

      local el = next_view.e_snacks:item(i)

      for c in it.map(str.sub, str.match(el.dataset.hide or "", "[^%s]+")) do
        next_view.snack_observed_classes[c] = true
      end

      for c in it.map(str.sub, str.match(el.dataset.show or "", "[^%s]+")) do
        next_view.snack_observed_classes[c] = true
      end

    end

  end

  -- TODO: Currently this figures out how many
  -- buttons are on either side of the title,
  -- and sets the title width such that it
  -- doesn't overlap the side with the most
  -- buttons. The problem is that if one side
  -- has a button and the other doesnt, and the
  -- title is long enough to overlap, it
  -- confusingly gets cut off on the side
  -- without buttons, when ideally it should
  -- only be getting cut off by the buttons. We
  -- need some sort of adaptive centering as the
  -- user types into the title input or based on
  -- the actual displayed length.
  M.setup_header_title_width = function (view)

    if not view.e_header then
      return
    end

    local e_title = view.e_header:querySelector(".header > .title")

    if not e_title then
      return
    end

    local offset_left = 0
    local offset_right = 0

    local lefting = true

    Array:from(view.e_header.children):forEach(function (_, el)

      if el.classList:contains("title") then
        return
      end

      if lefting and el.classList:contains("right") then
        lefting = false
      end

      if lefting then
        offset_left = offset_left + <% return app.header_height %>
      else
        offset_right = offset_right + <% return app.header_height %>
      end

    end)

    local shrink = math.max(offset_left, offset_right) * 2
    local width = "calc(100vw - " .. shrink .. "px)"

    e_title.style.width = width

  end

  M.style_maximized = function (view, animate)

    if view.maximized == nil then
      view.maximized = false
    end

    view.maximized = not view.maximized

    if view.maximized then
      view.el.classList:add("maximized")
      view.header_offset = view.header_offset - <% return app.header_height %>
      view.main_offset = view.main_offset - <% return app.header_height %>
      view.fabs_top_offset = (view.fabs_top_offset or 0) - <% return app.header_height %>
      view.snack_offset = view.snack_offset + <% return app.header_height %>
      view.snack_opacity = 0
    else
      view.el.classList:remove("maximized")
      view.header_offset = view.header_offset + <% return app.header_height %>
      view.main_offset = view.main_offset + <% return app.header_height %>
      view.fabs_top_offset = (view.fabs_top_offset or 0) + <% return app.header_height %>
      view.snack_offset = view.snack_offset - <% return app.header_height %>
      view.snack_opacity = 1
    end

    M.style_header(view, animate)
    M.style_main(view, animate)
    M.style_fabs(view, animate)
    M.style_snacks(view, animate)

  end

  M.setup_maximize = function (next_view)

    if not next_view.e_minmax then
      return
    end

    if next_view.e_header then
      next_view.e_header.classList:add("nohide")
    end

    next_view.e_minmax:addEventListener("click", function ()
      M.style_maximized(next_view, true)
    end)

  end

  M.setup_ripples = function (el)

    el:querySelectorAll(".button:not(.noripple)")
      :forEach(function (_, el)
        M.setup_ripple(el)
      end)

    el:querySelectorAll(".ripple")
      :forEach(function (_, el)
        if el ~= t_ripple then
          M.setup_ripple(el)
        end
      end)

  end

  M.get_base_main_offset = function (view)
    return (update_worker and <% return app.banner_height %> or 0) +
           (view.maximized and (- <% return app.header_height %>) or 0)
  end

  M.get_base_header_offset = function (view)
    return (update_worker and <% return app.banner_height %> or 0) +
           (view.maximized and (- <% return app.header_height %>) or 0)
  end

  M.get_base_fabs_top_offset = function (view)
    return (update_worker and <% return app.banner_height %> or 0) +
           (view.maximized and (- <% return app.header_height %>) or 0)
  end

  M.get_base_snack_offset = function (view)
    return (view.maximized and <% return app.header_height %> or 0)
  end

  M.should_show = function (view, el)

    local hides = it.collect(it.map(str.sub, str.match(el.dataset.hide or "", "[^%s]+")))

    for h in it.ivals(hides) do
      if view.el.classList:contains(h) then
        return false
      end
    end

    local shows = it.collect(it.map(str.sub, str.match(el.dataset.show or "", "[^%s]+")))

    if #shows == 0 then
      return true
    end

    for s in it.ivals(shows) do
      if view.el.classList:contains(s) then
        return true
      end
    end

    return false

  end

  M.style_header = function (view, animate)

    if not view.e_header then
      return
    end

    if animate then
      view.e_header.classList:add("animated")
      if view.header_animation then
        window:clearTimeout(view.header_animation)
        view.header_animation = nil
      end
      view.header_animation = M.after_transition(function ()
        view.e_header.classList:remove("animated")
        view.header_animation = nil
      end)
    end

    if view.last_scrolly then
      local diff = view.last_scrolly - view.curr_scrolly
      view.header_offset = view.header_offset + diff
      if diff > 0 then
        if view.header_offset > view.header_max then
          view.header_offset = view.header_max
        end
        view.e_header.style["box-shadow"] = "<% return app.shadow2 %>"
      else
        if view.header_offset < view.header_min then
          view.header_offset = view.header_min
          if not update_worker then
            view.e_header.style["box-shadow"] = "none"
          end
        end
      end
    end

    view.e_header.style.transform = "translateY(" .. view.header_offset .. "px)"
    view.e_header.style.opacity = view.header_opacity
    view.e_header.style["z-index"] = view.header_index
    view.e_header.style["box-shadow"] = view.header_shadow

  end

  M.style_main = function (view, animate)

    if not view.e_main then
      return
    end

    if animate then
      view.e_main.classList:add("animated")
      if view.main_animation then
        window:clearTimeout(view.main_animation)
        view.main_animation = nil
      end
      view.main_animation = M.after_transition(function ()
        view.e_main.classList:remove("animated")
        view.main_animation = nil
      end)
    end

    view.e_main.style.transform = "translateY(" .. view.main_offset .. "px)"
    view.e_main.style.opacity = view.main_opacity
    view.e_main.style["z-index"] = view.main_index

  end

  M.style_fabs = function (view, animate)

    if view.e_fabs.length <= 0 then
      return
    end

    if animate then
      view.e_fabs:forEach(function (_, e_fab)
        e_fab.classList:add("animated")
      end)
      if view.fabs_animation then
        window:clearTimeout(view.fabs_animation)
        view.fabs_animation = nil
      end
      view.fabs_animation = M.after_transition(function ()
        view.e_fabs:forEach(function (_, e_fab)
          e_fab.classList:remove("animated")
        end)
        view.fabs_animation = nil
      end)
    end

    local bottom_offset_total = 0
    local top_offset_total = 0

    arr.each(view.e_fabs_shared, function (el)

      el.style["z-index"] = view.fab_shared_index

      if not M.should_show(view, el) then
        el.style.opacity = 0
        el.style["box-shadow"] = view.fab_shared_shadow
        el.style["pointer-events"] = "none"
        el.style.transform =
          "scale(0.75) " ..
          "translateY(" .. view.fab_shared_offset .. "px)"
        return
      end

      local e_svg = el:querySelector("svg")

      el.style["z-index"] = view.fab_shared_index
      el.style.opacity = view.fab_shared_opacity
      el.style["pointer-events"] = "all"
      el.style["box-shadow"] = view.fab_shared_shadow

      el.style.transform =
        "scale(" .. view.fab_shared_scale .. ") " ..
          "translateY(" .. view.fab_shared_offset .. "px)"

      e_svg.style.transform =
        "translateY(" .. view.fab_shared_svg_offset .. "px)"

      if el.classList:contains("top") then
        top_offset_total = top_offset_total +
          (el.classList:contains("small") and
            <% return app.fab_width_small %> or
            <% return app.fab_width_large %>)
      else
        bottom_offset_total = bottom_offset_total +
          (el.classList:contains("small") and
            <% return app.fab_width_small %> or
            <% return app.fab_width_large %>)
      end

    end)

    arr.each(view.e_fabs_bottom, function (el)

      el.style["z-index"] = view.fabs_bottom_index

      if not M.should_show(view, el) then
        el.style.opacity = 0
        el.style["pointer-events"] = "none"
        el.style.transform =
          "scale(0.75) " ..
          "translateY(" .. (view.fabs_bottom_offset - bottom_offset_total) .. "px)"
        return
      end

      el.style["pointer-events"] = "all"
      el.style.opacity = view.fabs_bottom_opacity
      el.style.transform =
        "scale(" .. view.fabs_bottom_scale .. ") " ..
        "translateY(" .. (view.fabs_bottom_offset - bottom_offset_total) .. "px)"

      bottom_offset_total = bottom_offset_total +
        (el.classList:contains("small") and
          <% return app.fab_width_small %> or
          <% return app.fab_width_large %>) + 16

    end)

    arr.each(view.e_fabs_top, function (el)

      el.style["z-index"] = view.fabs_top_index

      if not M.should_show(view, el) then
        el.style.opacity = 0
        el.style["pointer-events"] = "none"
        el.style.transform =
          "scale(0.75) " ..
          "translateY(" .. (view.fabs_top_offset - top_offset_total) .. "px)"
        return
      end

      el.style["pointer-events"] = "all"
      el.style.opacity = view.fabs_top_opacity
      el.style.transform =
        "scale(" .. view.fabs_top_scale .. ") " ..
        "translateY(" .. (view.fabs_top_offset + top_offset_total) .. "px)"

      top_offset_total = top_offset_total +
        (el.classList:contains("small") and
          <% return app.fab_width_small %> or
          <% return app.fab_width_large %>) + 16

    end)

  end

  M.style_snacks = function (view, animate)

    if view.e_snacks.length <= 0 then
      return
    end

    if animate then
      view.e_snacks:forEach(function (_, e_snack)
        e_snack.classList:add("animated")
      end)
      if view.snack_animation then
        window:clearTimeout(view.snack_animation)
        view.snack_animation = nil
      end
      view.snack_animation = M.after_transition(function ()
        view.e_snacks:forEach(function (_, e_snack)
          e_snack.classList:remove("animated")
        end)
        view.snack_animation = nil
      end)
    end

    local bottom_offset_total = 0

    view.e_snacks:forEach(function (_, e_snack)
      e_snack.style["z-index"] = view.snack_index
      if not M.should_show(view, e_snack) then
        e_snack.style.opacity = 0
        e_snack.style["pointer-events"] = "none"
        e_snack.style.transform =
          "translateY(" .. (view.snack_offset - bottom_offset_total) .. "px)"
      else
        e_snack.style.opacity = view.snack_opacity
        e_snack.style["pointer-events"] = (view.snack_opacity or 0) == 0 and "none" or "all"
        e_snack.style.transform =
          "translateY(" .. (view.snack_offset - bottom_offset_total) .. "px)"
        bottom_offset_total = bottom_offset_total +
            <% return app.snack_height %> + 16
      end
    end)

  end

  M.style_header_transition = function (next_view, transition, direction, last_view)

    next_view.header_min = - <% return app.header_height %> + M.get_base_header_offset(next_view)
    next_view.header_max = M.get_base_header_offset(next_view)

    if not last_view and transition == "enter" then

      next_view.header_offset = M.get_base_header_offset(next_view)
      next_view.header_opacity = 1
      next_view.header_index = 99
      next_view.header_shadow = "<% return app.shadow2 %>"
      M.style_header(next_view)

    elseif not last_view and transition == "exit" then

      error("invalid state: header exit transition with no last view")

    elseif transition == "enter" and direction == "forward" then

      next_view.header_offset = <% return app.transition_forward_height %> + M.get_base_header_offset(next_view)
      next_view.header_opacity = 0
      next_view.header_index = 99
      next_view.header_shadow = "<% return app.shadow2 %>"
      M.style_header(next_view)

      M.after_frame(function ()
        next_view.header_offset = next_view.header_offset - <% return app.transition_forward_height %>
        next_view.header_opacity = 1
        M.style_header(next_view, true)
      end)

    elseif transition == "exit" and direction == "forward" then

      last_view.header_offset = M.get_base_header_offset(last_view) - <% return app.transition_forward_height %> / 2
      last_view.header_opacity = 1
      last_view.header_index = 97
      last_view.header_shadow = "<% return app.shadow2 %>"
      M.style_header(last_view, true)

    elseif transition == "enter" and direction == "backward" then

      next_view.header_offset = M.get_base_header_offset(next_view) - <% return app.transition_forward_height %> / 2
      next_view.header_opacity = 1
      next_view.header_index = 97
      next_view.header_shadow = "<% return app.shadow2 %>"
      M.style_header(next_view)

      M.after_frame(function ()
        next_view.header_offset = M.get_base_header_offset(next_view)
        M.style_header(next_view, true)
      end)

    elseif transition == "exit" and direction == "backward" then

      last_view.header_offset = <% return app.transition_forward_height %> + M.get_base_header_offset(last_view)
      last_view.header_opacity = 0
      last_view.header_index = 99
      last_view.header_shadow = "<% return app.shadow2 %>"
      M.style_header(last_view, true)

    else

      error("invalid state: header transition")

    end

  end

  M.style_main_transition = function (next_view, transition, direction, last_view)

    if not last_view and transition == "enter" then

      next_view.main_offset = M.get_base_main_offset(next_view)
      next_view.main_opacity = 1
      next_view.main_index = 96
      M.style_main(next_view)

    elseif not last_view and transition == "exit" then

      error("invalid state: main exit transition with no last view")

    elseif transition == "enter" and direction == "forward" then

      next_view.main_offset = M.get_base_main_offset(next_view) + <% return app.transition_forward_height %>
      next_view.main_opacity = 0
      next_view.main_index = 98
      M.style_main(next_view)

      M.after_frame(function ()
        next_view.main_offset = next_view.main_offset - <% return app.transition_forward_height %>
        next_view.main_opacity = 1
        M.style_main(next_view, true)
      end)

    elseif transition == "exit" and direction == "forward" then

      last_view.main_offset = M.get_base_main_offset(last_view) - <% return app.transition_forward_height %> / 2
      last_view.main_opacity = 1
      last_view.main_index = 96
      M.style_main(last_view, true)

    elseif transition == "enter" and direction == "backward" then

      next_view.main_offset = M.get_base_main_offset(next_view)  - <% return app.transition_forward_height %> / 2
      next_view.main_opacity = 1
      next_view.main_index = 96
      M.style_main(next_view)

      M.after_frame(function ()
        next_view.main_offset = M.get_base_main_offset(next_view)
        M.style_main(next_view, true)
      end)

    elseif transition == "exit" and direction == "backward" then

      last_view.main_offset = <% return app.transition_forward_height %> + M.get_base_main_offset(last_view)
      last_view.main_opacity = 0
      last_view.main_index = 98
      M.style_main(last_view, true)

    else

      error("invalid state: main transition")

    end

  end

  M.style_fabs_transition = function (next_view, transition, direction, last_view)

    local is_shared = last_view and next_view.e_fabs.length > 0 and last_view.e_fabs.length > 0

    if not last_view and transition == "enter" then

      next_view.fab_shared_index = 99
      next_view.fab_shared_scale = 1
      next_view.fab_shared_opacity = 1
      next_view.fab_shared_shadow = "<% return app.shadow3 %>"
      next_view.fab_shared_offset = 0
      next_view.fab_shared_svg_offset = 0

      next_view.fabs_bottom_index = 98
      next_view.fabs_bottom_scale = 1
      next_view.fabs_bottom_opacity = 1
      next_view.fabs_bottom_offset = 0

      next_view.fabs_top_index = 98
      next_view.fabs_top_scale = 1
      next_view.fabs_top_opacity = 1
      next_view.fabs_top_offset = M.get_base_fabs_top_offset(next_view)

      M.style_fabs(next_view)

    elseif not last_view and transition == "exit" then

      error("invalid state: fabs exit transition with no last view")

    elseif is_shared and transition == "enter" and direction == "forward" then

      next_view.fab_shared_index = 99
      next_view.fab_shared_scale = 1
      next_view.fab_shared_opacity = 0
      next_view.fab_shared_shadow = "<% return app.shadow3 %>"
      next_view.fab_shared_offset = 0
      next_view.fab_shared_svg_offset = <% return app.fab_shared_svg_transition_height %>

      next_view.fabs_bottom_index = 98
      next_view.fabs_bottom_scale = 0.75
      next_view.fabs_bottom_opacity = 0
      next_view.fabs_bottom_offset = <% return app.transition_forward_height %>

      next_view.fabs_top_index = 98
      next_view.fabs_top_scale = 0.75
      next_view.fabs_top_opacity = 0
      next_view.fabs_top_offset = <% return app.transition_forward_height %> + M.get_base_fabs_top_offset(next_view)

      M.style_fabs(next_view)

      M.after_frame(function ()
        next_view.fab_shared_svg_offset = 0
        next_view.fab_shared_opacity = 1
        next_view.fabs_bottom_scale = 1
        next_view.fabs_bottom_opacity = 1
        next_view.fabs_bottom_offset = 0
        next_view.fabs_top_scale = 1
        next_view.fabs_top_opacity = 1
        next_view.fabs_top_offset = M.get_base_fabs_top_offset(next_view)
        M.style_fabs(next_view, true)
      end)

    elseif is_shared and transition == "exit" and direction == "forward" then

      last_view.fab_shared_index = 99
      last_view.fab_shared_scale = 1
      last_view.fab_shared_opacity = 1
      last_view.fab_shared_shadow = "<% return app.shadow3_transparent %>"
      last_view.fab_shared_offset = 0
      last_view.fab_shared_svg_offset = - <% return app.fab_shared_svg_transition_height %>

      last_view.fabs_bottom_index = 96
      last_view.fabs_bottom_scale = 1
      last_view.fabs_bottom_opacity = 0
      last_view.fabs_bottom_offset = 0

      last_view.fabs_top_index = 96
      last_view.fabs_top_scale = 1
      last_view.fabs_top_opacity = 0
      last_view.fabs_top_offset = M.get_base_fabs_top_offset(last_view)

      M.style_fabs(last_view, true)

    elseif is_shared and transition == "enter" and direction == "backward" then

      next_view.fab_shared_index = 99
      next_view.fab_shared_scale = 1
      next_view.fab_shared_opacity = 0
      next_view.fab_shared_shadow = "<% return app.shadow3 %>"
      next_view.fab_shared_offset = 0
      next_view.fab_shared_svg_offset = - <% return app.fab_shared_svg_transition_height %>

      next_view.fabs_bottom_index = 96
      next_view.fabs_bottom_scale = 0.75
      next_view.fabs_bottom_opacity = 0
      next_view.fabs_bottom_offset = 0

      next_view.fabs_top_index = 96
      next_view.fabs_top_scale = 0.75
      next_view.fabs_top_opacity = 0
      next_view.fabs_top_offset = M.get_base_fabs_top_offset(next_view)

      M.style_fabs(next_view)

      M.after_frame(function ()
        next_view.fab_shared_svg_offset = 0
        next_view.fab_shared_opacity = 1
        next_view.fabs_bottom_scale = 1
        next_view.fabs_bottom_opacity = 1
        next_view.fabs_top_scale = 1
        next_view.fabs_top_opacity = 1
        M.style_fabs(next_view, true)
      end)

    elseif is_shared and transition == "exit" and direction == "backward" then

      last_view.fab_shared_index = 99
      last_view.fab_shared_scale = 1
      last_view.fab_shared_opacity = 1
      last_view.fab_shared_shadow = "<% return app.shadow3_transparent %>"
      last_view.fab_shared_offset = 0
      last_view.fab_shared_svg_offset = <% return app.fab_shared_svg_transition_height %>

      last_view.fabs_bottom_index = 98
      last_view.fabs_bottom_scale = 0.75
      last_view.fabs_bottom_opacity = 0
      last_view.fabs_bottom_offset = <% return app.transition_forward_height %>

      last_view.fabs_top_index = 100
      last_view.fabs_top_scale = 0.75
      last_view.fabs_top_opacity = 0
      last_view.fabs_top_offset = <% return app.transition_forward_height %> + M.get_base_fabs_top_offset(last_view)

      M.style_fabs(last_view, true)

    elseif transition == "enter" and direction == "forward" then

      next_view.fab_shared_index = 98
      next_view.fab_shared_scale = 0.75
      next_view.fab_shared_opacity = 0
      next_view.fab_shared_shadow = "<% return app.shadow3 %>"
      next_view.fab_shared_offset = <% return app.transition_forward_height %>
      next_view.fab_shared_svg_offset = 0

      next_view.fabs_bottom_index = 98
      next_view.fabs_bottom_scale = 0.75
      next_view.fabs_bottom_opacity = 0
      next_view.fabs_bottom_offset = <% return app.transition_forward_height %>

      next_view.fabs_top_index = 98
      next_view.fabs_bottom_scale = 0.75
      next_view.fabs_bottom_opacity = 0
      next_view.fabs_top_offset = <% return app.transition_forward_height %> + M.get_base_fabs_top_offset(next_view)

      M.style_fabs(next_view)

      M.after_frame(function ()
        next_view.fab_shared_scale = 1
        next_view.fab_shared_opacity = 1
        next_view.fab_shared_offset = 0
        next_view.fabs_bottom_scale = 1
        next_view.fabs_bottom_opacity = 1
        next_view.fabs_bottom_offset = 0
        next_view.fabs_top_scale = 1
        next_view.fabs_top_opacity = 1
        next_view.fabs_top_offset = M.get_base_fabs_top_offset(next_view)
        M.style_fabs(next_view, true)
      end)

    elseif transition == "enter" and direction == "backward" then

      next_view.fab_shared_index = 96
      next_view.fab_shared_scale = 0.75
      next_view.fab_shared_opacity = 0
      next_view.fab_shared_shadow = "<% return app.shadow3 %>"
      next_view.fab_shared_offset = 0
      next_view.fab_shared_svg_offset = 0

      next_view.fabs_bottom_index = 96
      next_view.fabs_bottom_scale = 0.75
      next_view.fabs_bottom_opacity = 0
      next_view.fabs_bottom_offset = 0

      next_view.fabs_top_index = 96
      next_view.fabs_bottom_scale = 0.75
      next_view.fabs_bottom_opacity = 0
      next_view.fabs_top_offset = M.get_base_fabs_top_offset(next_view)

      M.style_fabs(next_view)

      M.after_frame(function ()
        next_view.fab_shared_scale = 1
        next_view.fab_shared_opacity = 1
        next_view.fabs_bottom_scale = 1
        next_view.fabs_bottom_opacity = 1
        next_view.fabs_top_scale = 1
        next_view.fabs_top_opacity = 1
        M.style_fabs(next_view, true)
      end)

    elseif transition == "exit" and direction == "forward" then

      last_view.fab_shared_index = 96
      last_view.fab_shared_scale = 1
      last_view.fab_shared_opacity = 0
      last_view.fab_shared_shadow = "<% return app.shadow3 %>"
      last_view.fab_shared_offset = 0
      last_view.fab_shared_svg_offset = 0

      last_view.fabs_bottom_index = 96
      last_view.fabs_bottom_scale = 1
      last_view.fabs_bottom_opacity = 0
      last_view.fabs_bottom_offset = 0

      last_view.fabs_top_index = 96
      last_view.fabs_top_scale = 1
      last_view.fabs_top_opacity = 0
      last_view.fabs_top_offset = M.get_base_fabs_top_offset(last_view)

      M.style_fabs(last_view, true)

    elseif transition == "exit" and direction == "backward" then

      last_view.fab_shared_index = 96
      last_view.fab_shared_scale = 0.75
      last_view.fab_shared_opacity = 0
      last_view.fab_shared_shadow = "<% return app.shadow3 %>"
      last_view.fab_shared_offset = <% return app.transition_forward_height %>
      last_view.fab_shared_svg_offset = 0

      last_view.fabs_bottom_index = 96
      last_view.fabs_bottom_scale = 0.75
      last_view.fabs_bottom_opacity = 0
      last_view.fabs_bottom_offset = <% return app.transition_forward_height %>

      last_view.fabs_top_index = 96
      last_view.fabs_top_scale = 0.75
      last_view.fabs_top_opacity = 0
      last_view.fabs_top_offset = <% return app.transition_forward_height %> + M.get_base_fabs_top_offset(last_view)

      M.style_fabs(last_view, true)

    else

      error("invalid state: fabs transition")

    end

  end

  M.style_snacks_transition = function (next_view, transition, direction, last_view)

    if not last_view and transition == "enter" then

      next_view.snack_offset = M.get_base_snack_offset(next_view)
      next_view.snack_opacity = next_view.maximized and 0 or 1
      next_view.snack_index = 96
      M.style_snacks(next_view)

    elseif not last_view and transition == "exit" then

      error("invalid state: snack exit transition with no last view")

    elseif transition == "enter" and direction == "forward" then

      next_view.snack_offset = M.get_base_snack_offset(next_view) + <% return app.transition_forward_height %>
      next_view.snack_opacity = 0
      next_view.snack_index = 98
      M.style_snacks(next_view)

      M.after_frame(function ()
        next_view.snack_offset = next_view.snack_offset - <% return app.transition_forward_height %>
        next_view.snack_opacity = next_view.maximized and 0 or 1
        M.style_snacks(next_view, true)
      end)

    elseif transition == "exit" and direction == "forward" then

      last_view.snack_offset = M.get_base_snack_offset(last_view) - <% return app.transition_forward_height %> / 2
      last_view.snack_opacity = next_view.maximized and 0 or 1
      last_view.snack_index = 96
      M.style_snacks(last_view, true)

    elseif transition == "enter" and direction == "backward" then

      next_view.snack_offset = M.get_base_snack_offset(next_view)  - <% return app.transition_forward_height %> / 2
      next_view.snack_opacity = next_view.maximized and 0 or 1
      next_view.snack_index = 96
      M.style_snacks(next_view)

      M.after_frame(function ()
        next_view.snack_offset = M.get_base_snack_offset(next_view)
        M.style_snacks(next_view, true)
      end)

    elseif transition == "exit" and direction == "backward" then

      last_view.snack_offset = <% return app.transition_forward_height %> + M.get_base_snack_offset(last_view)
      last_view.snack_opacity = 0
      last_view.snack_index = 98
      M.style_snacks(last_view, true)

    else

      error("invalid state: main transition")

    end

  end

  M.scroll_listener = function (view)

    local ticking = false

    return function ()
      view.curr_scrolly = window.scrollY
      if not ticking then
        window:requestAnimationFrame(function ()
          M.style_header(view)
          view.last_scrolly = view.curr_scrolly
          ticking = false
        end)
        ticking = true
      end
    end

  end

  M.after_transition = function (fn)
    return window:setTimeout(function ()
      window:requestAnimationFrame(fn)
    end, <% return app.transition_time_ms %>)
  end

  M.after_frame = function (fn)
    return window:requestAnimationFrame(function ()
      window:requestAnimationFrame(fn)
    end)
  end

  M.post_exit = function (last_view, to_class)

    last_view.el.classList:remove("exit", "forward", "backward", to_class)

    last_view.el:remove()

    if last_view.script.post_remove then
      last_view.script.post_remove(ctx, last_view)
    end

  end

  M.post_enter = function (next_view, from_class)

    next_view.el.classList:remove("enter", "forward", "backward", from_class)

    e_body.classList:remove("transition")

    if next_view.script.post_append then
      next_view.script.post_append(ctx, next_view)
    end

    local e_back = next_view.el:querySelector(".page > .header > .back")

    if e_back then
      e_back:addEventListener("click", function ()
        M.backward()
      end)
    end

    if next_view.e_header and not next_view.e_header.classList:contains("nohide") then
      next_view.curr_scrolly = nil
      next_view.last_scrolly = nil
      next_view.scroll_listener = M.scroll_listener(next_view)
      window:addEventListener("scroll", next_view.scroll_listener)
    end

    M.setup_ripples(next_view.el)

  end

  M.enter = function (next_view, direction, last_view)

    next_view.el = util.clone(next_view.template)
    next_view.e_header = next_view.el:querySelector(".page > .header")
    next_view.e_main = next_view.el:querySelector(".page > .main")
    next_view.e_snacks = next_view.el:querySelector(".page > .snacks")

    M.setup_observer(next_view)
    M.setup_fabs(next_view, last_view)
    M.setup_snacks(next_view)
    M.setup_header_title_width(next_view)
    M.style_header_transition(next_view, "enter", direction, last_view)
    M.style_main_transition(next_view, "enter", direction, last_view)
    M.style_fabs_transition(next_view, "enter", direction, last_view)
    M.style_snacks_transition(next_view, "enter", direction, last_view)
    M.setup_maximize(next_view)

    if next_view.script.pre_append then
      next_view.script.pre_append(ctx, next_view)
    end

    local from_class = "from-" .. (last_view and last_view.name or "none")

    M.after_transition(function ()
      return M.post_enter(next_view, from_class)
    end)

    e_body.classList:add("transition")

    next_view.el.classList:add("enter", direction, from_class)

    e_body:append(next_view.el)

  end

  M.exit = function (last_view, direction, next_view)

    if last_view.script.pre_remove then
      last_view.script.pre_remove(ctx, last_view)
    end

    M.style_header_transition(next_view, "exit", direction, last_view)
    M.style_main_transition(next_view, "exit", direction, last_view)
    M.style_fabs_transition(next_view, "exit", direction, last_view)
    M.style_snacks_transition(next_view, "exit", direction, last_view)

    local to_class = "to-" .. (next_view and next_view.name or "none")

    if last_view.scroll_listener then
      window:removeEventListener("scroll", last_view.scroll_listener)
      last_view.scroll_listener = nil
    end

    M.after_transition(function ()
      return M.post_exit(last_view, to_class)
    end)

    last_view.el.classList:add("exit", direction, to_class)

  end

  M.init_view = function (name, template, script, opts)

    return {

      forward = M.forward,
      backward = M.backward,
      replace = M.replace,

      template = template,
      script = script,
      name = name,
      state = opts.state or {}

    }

  end

  M.forward = function (name, opts)

    opts = opts or {}

    local template = e_head:querySelector("template[data-view=\"" .. name .. "\"]")
    local script = scripts[name]

    if not template then
      return false, "no template found"
    end

    local last_view = stack[#stack]
    local next_view = M.init_view(name, template, script, opts)

    M.enter(next_view, "forward", last_view)

    if last_view then
      M.exit(last_view, "forward", next_view)
    end

    arr.push(stack, next_view)

  end

  M.replace = function (name, opts)

    opts = opts or {}
    opts.n = opts.n or 1

    local last_n = #stack

    M.forward(name, opts)

    arr.remove(stack, last_n - opts.n + 1, last_n)

  end

  M.backward = function (opts)

    opts = opts or {}
    opts.n = opts.n or 1

    local last_view = stack[#stack]
    local next_view = stack[#stack - opts.n]

    if not next_view then

      M.replace("home", opts)

    else

      if opts.state then
        next_view.state = opts.state
      end

      M.enter(next_view, "backward", last_view)
      M.exit(last_view, "backward", next_view)

      arr.remove(stack, #stack - opts.n + 1, #stack)

    end

  end

  window:addEventListener("popstate", function ()
    history:go()
  end)

  M.setup_ripples(e_body)

  <% push(app.service_worker) %>

    local navigator = window.navigator
    local serviceWorker = navigator.serviceWorker

    local e_reload = document:querySelector("body > .warn-update-worker")

    e_reload:addEventListener("click", function ()
      window.location = window.location
    end)

    M.style_update_worker = function ()

      if not update_worker then

        update_worker = true
        local active = stack[#stack]

        active.header_offset = active.header_offset + <% return app.banner_height %>
        active.main_offset = active.main_offset + <% return app.banner_height %>
        active.fabs_top_offset = active.fabs_top_offset + <% return app.banner_height %>
        active.header_min = - <% return app.header_height %> + M.get_base_header_offset(active)
        active.header_max = M.get_base_header_offset(active)

        M.style_header(active, true)
        M.style_main(active, true)
        M.style_fabs(active, true)

      end

      e_body.classList:add("update-worker")

    end

    M.poll_worker_update = function (reg)

      local polling = false
      local installing = false

      window:setInterval(function ()

        if polling then
          return
        end

        polling = true

        reg:update():await(function (_, ok, reg)

          polling = false

          if not ok then
            print("Service worker update error", reg and reg.message or reg)
          elseif reg.installing then
            installing = true
            print("Updated service worker installing")
          elseif reg.waiting then
            print("Updated service worker installed")
          elseif reg.active then
            if installing then
              installing = false
              M.style_update_worker()
            end
            print("Updated service worker active")
          end

        end)

      end, <% return app.service_worker_poll_time_ms %>)

    end

    if serviceWorker then

      serviceWorker:register("/sw.js", { scope = "/" }):await(function (_, ...)

        local reg = err.checkok(...)

        if reg.installing then
          print("Initial service worker installing")
        elseif reg.waiting then
          print("Initial service worker installed")
        elseif reg.active then
          print("Initial service worker active")
        end

        M.poll_worker_update(reg)

      end)

    end

  <% pop() %>

  M.forward("home")

<% push(app.trace) %>
end)
<% pop() %>
