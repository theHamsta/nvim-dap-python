local api = vim.api
local M = {}


local get_python_path = function()
  local venv_path = os.getenv('VIRTUAL_ENV')
  if venv_path then
    return venv_path .. '/bin/python'
  end
  return nil
end


local enrich_config = function(config, on_config)
  if not config.pythonPath then
    config.pythonPath = get_python_path()
  end
  on_config(config)
end


local default_setup_opts = {
  include_configs = true,
  console = 'integratedTerminal'
}

local default_test_opts = {
  console = 'integratedTerminal'
}


local function load_dap()
  local ok, dap = pcall(require, 'dap')
  assert(ok, 'nvim-dap is required to use dap-python')
  return dap
end


--- Register the python debug adapter
function M.setup(adapter_python_path, opts)
  local dap = load_dap()
  adapter_python_path = vim.fn.expand(adapter_python_path)
  opts = opts or default_setup_opts
  dap.adapters.python = function(cb, config)
    if config.request == 'attach' then
      cb({
        type = 'server';
        port = config.port or 0;
        host = config.host or '127.0.0.1';
        enrich_config = enrich_config;
      })
    else
      cb({
        type = 'executable';
        command = adapter_python_path;
        args = { '-m', 'debugpy.adapter' };
        enrich_config = enrich_config;
      })
    end
  end

  if opts.include_configs then
    dap.configurations.python = dap.configurations.python or {}
    table.insert(dap.configurations.python, {
      type = 'python';
      request = 'launch';
      name = 'Launch file';
      program = '${file}';
      console = opts.console;
    })
    table.insert(dap.configurations.python, {
      type = 'python';
      request = 'attach';
      name = 'Attach remote';
      host = function()
        return vim.fn.input('Host: ') or '127.0.0.1'
      end;
      port = function()
        return tonumber(vim.fn.input('Port: '))
      end;
    })
  end
end


function M.test_class()
  assert(false, 'test_class is not yet implemented')
end



function M.test_method(opts)
  opts = opts or default_test_opts
  local ft = vim.api.nvim_buf_get_option(0, 'filetype')
  assert(ft == 'python', 'test_method of dap-python only works for python files, not ' .. ft)
  local query_str = [[
    (class_definition
      name: (identifier) @name) @definition.class

    (function_definition
      name: (identifier) @name) @definition.function
  ]]
  local query = vim.treesitter.parse_query(ft, query_str)
  assert(query, 'Could not parse treesitter query. Cannot find test method')
  local parser = vim.treesitter.get_parser(0)
  local tree = parser:parse()
  assert(tree, 'Could not parse current buffer with treesitter. Cannot find test method')

  local row, _ = unpack(api.nvim_win_get_cursor(0))
  local is_class = false
  local classname = nil
  local closest_function = nil
  for id, node in query:iter_captures(tree:root(), 0, 0, row) do
    local name = query.captures[id]
    local type = node:type()
    if name == 'definition.class' then
      is_class = true
    end
    local row1, col1, row2, col2 = node:range()
    if row1 == row2 then
      row2 = row2 +1
    end
    local lines = api.nvim_buf_get_lines(0, row1, row2, true)
    local ident = nil
    if type == 'identifier' and lines and #lines == 1 then
      ident = (lines[1]):sub(col1 + 1, col2)
    end
    if name == 'name' and type == 'identifier' then
      if is_class then
        is_class = false
        classname = ident
      else
        closest_function = ident
      end
    end
	end
  if classname and closest_function then
    local path = vim.fn.expand('%:r:s?/?.?')
    local fqn = table.concat({path, classname, closest_function}, '.')
    print('Running', fqn)
    load_dap().run({
      type = 'python',
      request = 'launch',
      module = 'unittest',
      args = {'-v', fqn},
      console = opts.console
    })
  else
    print('No suitable test method found')
  end
end


return M
