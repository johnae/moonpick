local parse = require("moonscript.parse")
local pos_to_line, get_line
do
  local _obj_0 = require("moonscript.util")
  pos_to_line, get_line = _obj_0.pos_to_line, _obj_0.get_line
end
local append = table.insert
local builtin_whitelist_unused = {
  '_G',
  '...',
  '_',
  'tostring'
}
local builtin_whitelist_globals = {
  '_G',
  '_VERSION',
  'assert',
  'collectgarbage',
  'dofile',
  'error',
  'getfenv',
  'getmetatable',
  'ipairs',
  'load',
  'loadfile',
  'loadstring',
  'module',
  'next',
  'pairs',
  'pcall',
  'print',
  'rawequal',
  'rawget',
  'rawset',
  'require',
  'select',
  'setfenv',
  'setmetatable',
  'tonumber',
  'tostring',
  'type',
  'unpack',
  'xpcall',
  'coroutine',
  'debug',
  'io',
  'math',
  'os',
  'package',
  'string',
  'table',
  'true',
  'false',
  'nil'
}
local Scope
Scope = function(node, parent)
  assert(node, "Missing node")
  local declared = { }
  local used = { }
  local scopes = { }
  local pos = node[-1]
  if not pos and parent then
    pos = parent.pos
  end
  return {
    parent = parent,
    declared = declared,
    used = used,
    scopes = scopes,
    node = node,
    pos = pos,
    type = 'default',
    has_declared = function(self, name)
      if declared[name] then
        return true
      end
      return parent and parent:has_declared(name)
    end,
    has_parent = function(self, type)
      if not (parent) then
        return false
      end
      if parent.type == type then
        return true
      end
      return parent:has_parent(type)
    end,
    add_declaration = function(self, name, opts)
      declared[name] = opts
    end,
    add_assignment = function(self, name, ass)
      if self:has_declared(name) then
        return 
      end
      if not parent or not parent:has_declared(name) then
        declared[name] = ass
      end
    end,
    add_ref = function(self, name, ref)
      if declared[name] then
        used[name] = ref
      else
        if parent and parent:has_declared(name) then
          return parent:add_ref(name, ref)
        else
          used[name] = ref
        end
      end
    end,
    open_scope = function(self, node, type)
      local scope = Scope(node, self)
      scope.type = type
      append(scopes, scope)
      return scope
    end
  }
end
local has_subnode
has_subnode = function(node, types)
  if not (type(node) == 'table') then
    return false
  end
  for _index_0 = 1, #types do
    local t = types[_index_0]
    if node[1] == t then
      return true
    end
  end
  for _index_0 = 1, #node do
    local n = node[_index_0]
    if has_subnode(n, types) then
      return true
    end
  end
  return false
end
local is_loop_assignment
is_loop_assignment = function(list)
  local node = list[1]
  if not (type(node) == 'table') then
    return false
  end
  if not (node[1] == 'chain') then
    return false
  end
  local last = node[#node]
  if not (last[1] == 'call') then
    return false
  end
  local c_target = last[2]
  if not (type(c_target) == 'table' and #c_target == 1) then
    return false
  end
  local op = c_target[1][1]
  return op == 'for' or op == 'foreach'
end
local handlers = {
  update = function(node, scope, walk)
    local target, val = node[2], node[4]
    if not (scope.is_wrapper) then
      if is_loop_assignment({
        val
      }) then
        scope = scope:open_scope(node, 'loop-update')
        scope.is_wrapper = true
      end
    end
    if target[1] == 'ref' then
      scope:add_assignment(target[2], {
        pos = target[-1]
      })
    else
      walk(target, scope)
    end
    return walk({
      val
    }, scope)
  end,
  assign = function(node, scope, walk)
    local targets = node[2]
    local values = node[3]
    local pos = node[-1]
    if not (scope.is_wrapper) then
      if is_loop_assignment(values) then
        scope = scope:open_scope(node, 'loop-assignment')
        scope.is_wrapper = true
      end
    end
    for _index_0 = 1, #targets do
      local t = targets[_index_0]
      local _exp_0 = t[1]
      if 'ref' == _exp_0 then
        scope:add_assignment(t[2], {
          pos = t[-1] or pos
        })
      elseif 'chain' == _exp_0 then
        walk(t, scope)
      elseif 'table' == _exp_0 then
        local key_targets = t[2]
        for _index_1 = 1, #key_targets do
          local k_target = key_targets[_index_1]
          for _index_2 = 1, #k_target do
            local field = k_target[_index_2]
            if type(field) == 'table' and field[1] == 'ref' then
              scope:add_assignment(field[2], {
                pos = field[-1] or pos
              })
            end
          end
        end
      end
    end
    return walk(values, scope)
  end,
  chain = function(node, scope, walk)
    if not scope.is_wrapper and is_loop_assignment({
      node
    }) then
      scope = scope:open_scope(node, 'chain')
      scope.is_wrapper = true
    end
    return walk(node, scope)
  end,
  ref = function(node, scope)
    return scope:add_ref(node[2], {
      pos = node[-1]
    })
  end,
  fndef = function(node, scope, walk)
    local params, f_type, body = node[2], node[4], node[5]
    local t = f_type == 'fat' and 'method' or 'function'
    scope = scope:open_scope(node, t)
    for _index_0 = 1, #params do
      local p = params[_index_0]
      local def = p[1]
      if type(def) == 'string' then
        scope:add_declaration(def, {
          pos = node[-1],
          type = 'param'
        })
        if p[2] then
          walk({
            p[2]
          }, scope)
        end
      elseif type(def) == 'table' and def[1] == 'self' then
        scope:add_declaration(def[2], {
          pos = node[-1],
          type = 'param'
        })
        if p[2] then
          walk({
            p[2]
          }, scope)
        end
      else
        walk({
          p
        }, scope)
      end
    end
    return walk(body, scope)
  end,
  ["for"] = function(node, scope, walk)
    local var, args, body = node[2], node[3], node[4]
    if not (scope.is_wrapper) then
      scope = scope:open_scope(node, 'for')
    end
    scope:add_declaration(var, {
      pos = node[-1],
      type = 'for-var'
    })
    walk(args, scope)
    if body then
      return walk(body, scope)
    end
  end,
  foreach = function(node, scope, walk)
    local vars, args, body = node[2], node[3], node[4]
    if not body then
      body = args
      args = nil
    end
    if not (scope.is_wrapper) then
      scope = scope:open_scope(node, 'for-each')
    end
    for _index_0 = 1, #vars do
      local name = vars[_index_0]
      if type(name) == 'string' then
        scope:add_declaration(name, {
          pos = node[-1],
          type = 'for-each-var'
        })
      end
    end
    if args then
      walk(args, scope)
    end
    return walk(body, scope)
  end,
  declare_with_shadows = function(node, scope, walk)
    local names = node[2]
    for _index_0 = 1, #names do
      local name = names[_index_0]
      scope:add_declaration(name, {
        pos = node[-1]
      })
    end
  end,
  export = function(node, scope, walk)
    local names, vals = node[2], node[3]
    if type(names) == 'string' then
      scope.exported_from = node[-1]
    else
      for _index_0 = 1, #names do
        local name = names[_index_0]
        scope:add_declaration(name, {
          pos = node[-1],
          is_exported = true,
          type = 'export'
        })
      end
    end
    if vals then
      return walk({
        vals
      }, scope)
    end
  end,
  import = function(node, scope, walk)
    local names, values = node[2], node[3]
    for _index_0 = 1, #names do
      local name = names[_index_0]
      scope:add_declaration(name, {
        pos = node[-1],
        type = 'import'
      })
    end
    return walk({
      values
    }, scope)
  end,
  decorated = function(node, scope, walk)
    local stm, vals = node[2], node[3]
    if not (vals[1] == 'if' or vals[1] == 'unless') then
      scope = scope:open_scope(node, 'decorated')
      scope.is_wrapper = true
    end
    walk({
      stm
    }, scope)
    return walk({
      vals
    }, scope)
  end,
  comprehension = function(node, scope, walk)
    local exps, loop = node[2], node[3]
    if not (scope.is_wrapper) then
      scope = scope:open_scope(node, 'comprehension')
      scope.is_wrapper = true
    end
    if not (loop) then
      loop = exps
      exps = nil
    end
    walk({
      loop
    }, scope)
    if exps then
      return walk({
        exps
      }, scope)
    end
  end,
  tblcomprehension = function(node, scope, walk)
    local exps, loop = node[2], node[3]
    if not (scope.is_wrapper) then
      scope = scope:open_scope(node, 'tblcomprehension')
      scope.is_wrapper = true
    end
    if not (loop) then
      loop = exps
      exps = nil
    end
    walk({
      loop
    }, scope)
    if exps then
      return walk({
        exps
      }, scope)
    end
  end,
  class = function(node, scope, walk)
    local name, parent, body = node[2], node[3], node[4]
    scope:add_declaration(name, {
      pos = node[-1],
      type = 'class'
    })
    if scope.node[#scope.node] == node then
      scope:add_ref(name, {
        pos = node[-1]
      })
    end
    walk({
      parent
    }, scope)
    scope = scope:open_scope(node, 'class')
    return walk(body, scope)
  end,
  ["while"] = function(node, scope, walk)
    local conds, body = node[2], node[3]
    walk({
      conds
    }, scope)
    local cond_scope = scope:open_scope(node, 'while')
    if body then
      return walk(body, cond_scope)
    end
  end,
  cond_block = function(node, scope, walk)
    local op, conds, body = node[1], node[2], node[3]
    walk({
      conds
    }, scope)
    local cond_scope = scope:open_scope(node, op)
    if body then
      walk(body, cond_scope)
    end
    local rest
    do
      local _accum_0 = { }
      local _len_0 = 1
      for i, n in ipairs(node) do
        if i > 3 then
          _accum_0[_len_0] = n
          _len_0 = _len_0 + 1
        end
      end
      rest = _accum_0
    end
    if #rest > 0 then
      return walk(rest, scope)
    end
  end,
  ["else"] = function(node, scope, walk)
    local body = node[2]
    scope = scope:open_scope(node, 'else')
    return walk(body, scope)
  end
}
handlers['if'] = handlers.cond_block
handlers['elseif'] = handlers.cond_block
handlers['unless'] = handlers.cond_block
local walk
walk = function(tree, scope)
  if not (tree) then
    error("nil passed for node: " .. tostring(debug.traceback()))
  end
  for _index_0 = 1, #tree do
    local node = tree[_index_0]
    local handler = handlers[node[1]]
    if handler then
      handler(node, scope, walk)
    else
      for _index_1 = 1, #node do
        local sub_node = node[_index_1]
        if type(sub_node) == 'table' then
          walk({
            sub_node
          }, scope)
        end
      end
    end
  end
end
local report_on_scope
report_on_scope = function(scope, opts, inspections)
  if opts == nil then
    opts = { }
  end
  if inspections == nil then
    inspections = { }
  end
  local whitelist_unused, whitelist_globals
  whitelist_unused, whitelist_globals = opts.whitelist_unused, opts.whitelist_globals
  for name, decl in pairs(scope.declared) do
    local _continue_0 = false
    repeat
      if scope.used[name] or whitelist_unused[name] then
        _continue_0 = true
        break
      end
      if decl.is_exported or scope.exported_from and scope.exported_from < decl.pos then
        _continue_0 = true
        break
      end
      if decl.type == 'param' and not opts.report_params then
        _continue_0 = true
        break
      end
      append(inspections, {
        msg = "declared but unused - `" .. tostring(name) .. "`",
        pos = decl.pos or scope.pos
      })
      _continue_0 = true
    until true
    if not _continue_0 then
      break
    end
  end
  for name, node in pairs(scope.used) do
    local _continue_0 = false
    repeat
      if not (scope.declared[name] or whitelist_globals[name]) then
        if name == 'self' or name == 'super' then
          if scope.type == 'method' or scope:has_parent('method') then
            _continue_0 = true
            break
          end
        end
        append(inspections, {
          msg = "accessing global - `" .. tostring(name) .. "`",
          pos = node.pos or scope.pos
        })
      end
      _continue_0 = true
    until true
    if not _continue_0 then
      break
    end
  end
  local _list_0 = scope.scopes
  for _index_0 = 1, #_list_0 do
    scope = _list_0[_index_0]
    report_on_scope(scope, opts, inspections)
  end
  return inspections
end
local format_inspections
format_inspections = function(inspections)
  local chunks = { }
  for _index_0 = 1, #inspections do
    local inspection = inspections[_index_0]
    local chunk = "line " .. tostring(inspection.line) .. ": " .. tostring(inspection.msg) .. "\n"
    chunk = chunk .. (string.rep('=', #chunk - 1) .. '\n')
    chunk = chunk .. "> " .. tostring(inspection.code) .. "\n"
    chunks[#chunks + 1] = chunk
  end
  return table.concat(chunks, '\n')
end
local report
report = function(scope, code, opts)
  if opts == nil then
    opts = { }
  end
  local whitelist_unused = builtin_whitelist_unused
  if opts.whitelist_unused then
    do
      local _accum_0 = { }
      local _len_0 = 1
      for _index_0 = 1, #whitelist_unused do
        local t = whitelist_unused[_index_0]
        _accum_0[_len_0] = t
        _len_0 = _len_0 + 1
      end
      whitelist_unused = _accum_0
    end
    local _list_0 = opts.whitelist_unused
    for _index_0 = 1, #_list_0 do
      local t = _list_0[_index_0]
      append(whitelist_unused, t)
    end
  end
  do
    local _tbl_0 = { }
    for _index_0 = 1, #whitelist_unused do
      local k = whitelist_unused[_index_0]
      _tbl_0[k] = true
    end
    whitelist_unused = _tbl_0
  end
  local whitelist_globals = builtin_whitelist_globals
  if opts.whitelist_globals then
    do
      local _accum_0 = { }
      local _len_0 = 1
      for _index_0 = 1, #whitelist_globals do
        local t = whitelist_globals[_index_0]
        _accum_0[_len_0] = t
        _len_0 = _len_0 + 1
      end
      whitelist_globals = _accum_0
    end
    local _list_0 = opts.whitelist_globals
    for _index_0 = 1, #_list_0 do
      local t = _list_0[_index_0]
      append(whitelist_globals, t)
    end
  end
  do
    local _tbl_0 = { }
    for _index_0 = 1, #whitelist_globals do
      local k = whitelist_globals[_index_0]
      _tbl_0[k] = true
    end
    whitelist_globals = _tbl_0
  end
  local report_params = opts.report_params
  if report_params == nil then
    report_params = false
  end
  local inspections = { }
  opts = {
    whitelist_globals = whitelist_globals,
    whitelist_unused = whitelist_unused,
    report_params = report_params
  }
  report_on_scope(scope, opts, inspections)
  for _index_0 = 1, #inspections do
    local inspection = inspections[_index_0]
    local line = pos_to_line(code, inspection.pos)
    inspection.line = line
    inspection.code = get_line(code, line)
  end
  table.sort(inspections, function(a, b)
    return a.line < b.line
  end)
  return inspections
end
local config_for
config_for = function(path)
  local has_moonscript = pcall(require, 'moonscript')
  local look_for = {
    'lint_config.lua'
  }
  if has_moonscript then
    look_for[#look_for + 1] = 'lint_config.moon'
  end
  local exists
  exists = function(f)
    local fh = io.open(f, 'r')
    if fh then
      fh:close()
      return true
    end
    return false
  end
  path = path:match('(.+)[/\\].+$') or path
  while path do
    for _index_0 = 1, #look_for do
      local name = look_for[_index_0]
      local config = tostring(path) .. "/" .. tostring(name)
      if exists(config) then
        return config
      end
    end
    path = path:match('(.+)[/\\].+$')
  end
  return nil
end
local load_config
load_config = function(config_file, file)
  local loader = loadfile
  if config_file:match('.moon$') then
    loader = require("moonscript.base").loadfile
  end
  local chunk = assert(loader(config_file))
  local config = chunk() or { }
  local opts = { }
  local _list_0 = {
    'whitelist_globals',
    'whitelist_unused'
  }
  for _index_0 = 1, #_list_0 do
    local list = _list_0[_index_0]
    if config[list] then
      local wl = { }
      for k, v in pairs(config[list]) do
        if file:find(k) then
          for _index_1 = 1, #v do
            local token = v[_index_1]
            append(wl, token)
          end
        end
      end
      opts[list] = wl
    end
  end
  return opts
end
local lint
lint = function(code, opts)
  if opts == nil then
    opts = { }
  end
  local tree, err = parse.string(code)
  if not (tree) then
    return nil, err
  end
  local scope = Scope(tree)
  walk(tree, scope)
  return report(scope, code, opts)
end
local lint_file
lint_file = function(file, opts)
  if opts == nil then
    opts = { }
  end
  local fh = assert(io.open(file, 'r'))
  local code = fh:read('*a')
  fh:close()
  local config_file = opts.lint_config or config_for(file)
  opts = config_file and load_config(config_file, file) or { }
  opts.file = file
  return lint(code, opts)
end
return {
  lint = lint,
  lint_file = lint_file,
  config_for = config_for,
  load_config = load_config,
  format_inspections = format_inspections
}