-- SuperTerminal no WezTerm (prototipo). Vai para ~/.config/wezterm/ junto com header.ps1.
-- O "pin" e nativo: cada separador tem um painel de cabecalho em cima (header.ps1), com a altura que ele pede,
-- que nunca fica com o foco e fecha sozinho quando ja nao ha shells no separador.
local wezterm = require 'wezterm'
local act = wezterm.action
local config = wezterm.config_builder()

local PWSH = 'C:\\Program Files\\PowerShell\\7\\pwsh.exe'
local HEADER = wezterm.config_dir .. '\\header.ps1'
local AGENT = wezterm.home_dir .. '\\.local\\superterminal\\agent.exe'   -- Ctrl+Alt+T (terminal/agent)
-- separadores para reabrir. FORA da pasta da config: o WezTerm vigia essa pasta e recarrega a config a cada ficheiro
-- que la muda (gravar aqui de 3 em 3 s deixava-o a recarregar sem parar: 80% de CPU, letras atrasadas a escrever)
local SESSION = wezterm.home_dir .. '\\.local\\superterminal\\session.json'

-- ---- aspeto: o mesmo do Windows Terminal (One Dark, Caskaydia Mono) ----
-- (o comando theme escreve ~\.config\superterminal\theme.json com a paleta; muda-o e o WezTerm recarrega sozinho)
local THEME_FILE = wezterm.home_dir .. '\\.config\\superterminal\\theme.json'
wezterm.add_to_config_reload_watch_list(THEME_FILE)
local T = { bg = '#282C34', dark = '#21252B', surf = '#2C313A', sel = '#3E4451', line = '#4B5263', comment = '#5C6370', fg = '#ABB2BF', white = '#FFFFFF',
  red = '#E06C75', green = '#98C379', yellow = '#E5C07B', blue = '#61AFEF', magenta = '#C678DD', cyan = '#56B6C2', cursor = '#528BFF' }
do
  local f = io.open(THEME_FILE, 'r')
  if f then
    local ok, t = pcall(wezterm.json_parse, f:read('*a')); f:close()
    if ok and type(t) == 'table' then for k, v in pairs(t) do T[k] = v end end
  end
end
config.colors = {
  foreground = T.fg, background = T.bg, cursor_bg = T.cursor, cursor_border = T.cursor,
  selection_bg = T.sel, selection_fg = 'none', split = T.sel,
  ansi = { T.bg, T.red, T.green, T.yellow, T.blue, T.magenta, T.cyan, T.fg },
  brights = { T.comment, T.red, T.green, T.yellow, T.blue, T.magenta, T.cyan, T.white },
  tab_bar = {
    background = T.bg,   -- (a mesma cor da janela: a barra fica discreta)
    active_tab = { bg_color = T.sel, fg_color = T.fg },
    inactive_tab = { bg_color = T.bg, fg_color = T.comment },
    inactive_tab_hover = { bg_color = T.surf, fg_color = T.fg },
    new_tab = { bg_color = T.dark, fg_color = T.comment },
    new_tab_hover = { bg_color = T.surf, fg_color = T.fg },
  },
}
-- fonte escolhida no setup (~\.config\superterminal\font.txt, uma linha com a familia); sem ela, a CaskaydiaMono.
-- O ficheiro fica na lista de vigiados: escolher outra no setup muda ja a fonte
local FONT_FILE = wezterm.home_dir .. '\\.config\\superterminal\\font.txt'
local chosen_font = nil
do
  local f = io.open(FONT_FILE, 'r')
  if f then
    chosen_font = (f:read('*l') or ''):match('^%s*(.-)%s*$'); f:close()
    wezterm.add_to_config_reload_watch_list(FONT_FILE)
    if chosen_font == '' then chosen_font = nil end
  end
end
-- (sem nenhuma escolhida e sem a CaskaydiaMono instalada - PC novo - as que vem com o WezTerm: JetBrains Mono + os
-- icones Nerd Font. Pedir uma fonte que nao existe abria uma janela de aviso por cima de tudo e o terminal nao se usava)
local function font_installed(file)
  for _, dir in ipairs { (os.getenv('LOCALAPPDATA') or '') .. '\\Microsoft\\Windows\\Fonts', (os.getenv('WINDIR') or 'C:\\Windows') .. '\\Fonts' } do
    local f = io.open(dir .. '\\' .. file, 'rb'); if f then f:close(); return true end
  end
  return false
end
if chosen_font then
  config.font = wezterm.font_with_fallback { chosen_font, 'Symbols Nerd Font Mono' }
elseif font_installed('CaskaydiaMonoNerdFont-Regular.ttf') then
  config.font = wezterm.font_with_fallback { 'CaskaydiaMono Nerd Font', 'Symbols Nerd Font Mono' }
else
  config.font = wezterm.font_with_fallback { 'JetBrains Mono', 'Symbols Nerd Font Mono' }
end
config.font_size = 13   -- (o mesmo tamanho do Windows Terminal: com 12 as letras tinham menos pixeis e ficavam menos nitidas)
config.line_height = 1.25
-- letras nitidas como o ClearType do Windows Terminal (subpixel), sempre com o mesmo desenho
config.freetype_load_target = 'Light'
config.freetype_render_target = 'HorizontalLcd'
config.default_cursor_style = 'SteadyBar'
config.window_padding = { left = 16, right = 16, top = 12, bottom = 8 }
config.window_decorations = 'RESIZE'   -- (sem os botoes da janela na barra de baixo: o terminal vive em ecra inteiro)
config.use_fancy_tab_bar = false
config.tab_max_width = 28
-- barra em baixo e sempre visivel, como a barra de estado de um editor: separadores a esquerda, teclas a direita
config.hide_tab_bar_if_only_one_tab = false
config.tab_bar_at_bottom = true
config.show_new_tab_button_in_tab_bar = false
config.inactive_pane_hsb = { saturation = 1.0, brightness = 1.0 }   -- (o cabecalho nunca tem foco: nao o escurecer)
-- OpenGL: com WebGpu a janela demorava a aparecer depois de escondida (Ctrl+Alt+T); OpenGL pinta em ~10 ms
-- Sem placa grafica a serio (VM, PC sem drivers) nao ha OpenGL e o WezTerm fechava logo ao abrir ("OpenGL implementation
-- is too old"): o instalador ve isso no Windows e escreve "EGL" em ~\.config\superterminal\front_end.txt -> o OpenGL
-- passa pelo ANGLE (libEGL.dll, que vem com o WezTerm: desenha por DirectX, que numa VM e o WARP do Windows)
local function pick_front_end()
  local f = io.open(wezterm.home_dir .. '\\.config\\superterminal\\front_end.txt', 'r')
  if not f then return 'OpenGL' end
  local v = (f:read('*l') or ''):match('^%s*(%a+)%s*$'); f:close()
  if v == 'EGL' then config.prefer_egl = true; return 'OpenGL' end
  if v == 'Software' or v == 'WebGpu' or v == 'OpenGL' then return v end
  return 'OpenGL'
end
config.front_end = pick_front_end()
config.window_close_confirmation = 'NeverPrompt'
-- tamanho em modo janela (arranca em ecra inteiro; F11 passa a janela): cabe num ecra 1080p. Com 50 linhas a janela
-- ficava mais alta que o ecra e o topo, com o cabecalho, ficava de fora
config.initial_cols = 160
config.initial_rows = 38
config.status_update_interval = 250

-- ---- shell: pwsh; KVN_COMPACT = os shells nao desenham o fastfetch (esta no cabecalho) ----
config.default_prog = { PWSH, '-NoLogo' }
config.default_cwd = wezterm.home_dir   -- (o agente abre o WezTerm na pasta da tarefa que o arrancou, nao na home)
-- WSLENV: o KVN_COMPACT chega tambem ao zsh do WSL (o cabecalho ja esta em cima: o zsh nao desenha o seu)
config.set_environment_variables = { SUPERTERMINAL = '1', KVN_COMPACT = '1', WSLENV = 'KVN_COMPACT:SUPERTERMINAL:WEZTERM_UNIX_SOCKET:WEZTERM_PANE', POWERSHELL_UPDATECHECK = 'Off', POWERSHELL_TELEMETRY_OPTOUT = '1' }
-- sem o agent proprio do WezTerm: ele punha SSH_AUTH_SOCK num ficheiro que nao existe e o ssh deixava de ver o
-- ssh-agent do Windows (com a chave desbloqueada) -> "Permission denied (publickey)" no ssh / sync dentro do WezTerm
-- (pcall: o WezTerm de 2024 nao tem esta opcao e recusava o config inteiro)
pcall(function() config.mux_enable_ssh_agent = false end)

-- ---- cabecalho ----
local function role(pane) return pane:get_user_vars().role end

-- poe o painel de cabecalho em cima do painel 'pane' (que fica com o foco)
-- altura do cabecalho da ultima vez (linhas): o painel nasce logo com ela, sem desenhar duas vezes ao abrir
local ROWS_FILE = wezterm.home_dir .. '\\.local\\superterminal\\header-rows'
local function header_rows()
  if wezterm.GLOBAL.header_rows then return wezterm.GLOBAL.header_rows end
  local f = io.open(ROWS_FILE, 'r'); local n = f and tonumber(f:read('*a')); if f then f:close() end
  wezterm.GLOBAL.header_rows = n; return n
end
local function add_header(pane)
  pane:split {
    direction = 'Top', size = header_rows() or 0.3, top_level = true,   -- (em celulas; sem memoria, 30% e o cabecalho pede a altura certa)
    args = { PWSH, '-NoLogo', '-NoProfile', '-File', HEADER },
  }
  pane:activate()
end

-- ---- sessao: separadores e a pasta de cada shell (o prompt do perfil manda a pasta na user var "cwd") ----
local function shells(tab)
  local list = {}
  for _, p in ipairs(tab:panes_with_info()) do
    if role(p.pane) ~= 'header' then table.insert(list, p) end
  end
  table.sort(list, function(a, b) return a.left < b.left end)
  return list
end

local last_save = 0
local function save_session(window)
  -- instancias de teste (SUPERTERMINAL_TEST=1) nao mexem na sessao a sério
  if os.getenv('SUPERTERMINAL_TEST') or os.time() - last_save < 3 then return end
  last_save = os.time()
  -- (pcall: a fechar, a janela pode ja nao existir no mux: "window id not found")
  pcall(function()
    local tabs = {}
    for _, tab in ipairs(window:mux_window():tabs()) do
      local cwds = {}
      for _, p in ipairs(shells(tab)) do table.insert(cwds, p.pane:get_user_vars().cwd or '') end
      if #cwds > 0 then table.insert(tabs, cwds) end
    end
    if #tabs == 0 then return end
    local s = wezterm.json_encode { tabs = tabs }
    if s == wezterm.GLOBAL.last_session then return end   -- (so grava quando muda)
    local f = io.open(SESSION, 'w')
    if f then f:write(s); f:close(); wezterm.GLOBAL.last_session = s end
  end)
end

local function cwd_or_nil(d) if d and d ~= '' then return d end end

-- abre os separadores guardados (cada um com o cabecalho; varios shells = lado a lado)
local function restore_session()
  local f = io.open(SESSION, 'r')
  if not f then return false end
  local ok, s = pcall(wezterm.json_parse, f:read('*a')); f:close()
  if not ok or not s or not s.tabs or #s.tabs == 0 then return false end
  local window
  for i, cwds in ipairs(s.tabs) do
    local tab, pane
    if i == 1 then tab, pane, window = wezterm.mux.spawn_window { cwd = cwd_or_nil(cwds[1]) }
    else tab, pane = window:spawn_tab { cwd = cwd_or_nil(cwds[1]) } end
    local first = pane
    for j = 2, #cwds do pane = pane:split { direction = 'Right', cwd = cwd_or_nil(cwds[j]) } end
    add_header(first)
  end
  pcall(function() window:tabs()[1]:activate() end)
  return true
end

wezterm.on('gui-startup', function(cmd)
  if not cmd and restore_session() then return end
  local _, pane, _ = wezterm.mux.spawn_window(cmd or {})
  add_header(pane)
end)

-- o cabecalho diz quantas linhas precisa (user var rows): ajusta o painel a isso (tambem depois de mudar o tamanho da janela)
wezterm.on('user-var-changed', function(window, pane, name, value)
  if name ~= 'rows' then return end
  local want = tonumber(value:match("^%d+"))   -- (valor "linhas:contador": o contador faz o evento chegar mesmo com as mesmas linhas)
  local tab = pane:tab()
  if not want or not tab then return end
  if want > 1 and want ~= wezterm.GLOBAL.header_rows then
    wezterm.GLOBAL.header_rows = want
    local f = io.open(ROWS_FILE, 'w'); if f then f:write(tostring(want)); f:close() end
  end
  for _, p in ipairs(tab:panes_with_info()) do
    if p.pane:pane_id() == pane:pane_id() and p.height ~= want then
      local d = want - p.height
      window:perform_action(act.AdjustPaneSize { d > 0 and 'Down' or 'Up', math.abs(d) }, pane)
    end
  end
end)

-- a cada 250 ms: o cabecalho nunca fica com o foco; separador so com o cabecalho -> fecha-o
-- barra de baixo: as teclas principais a direita, a cinzento (como a barra de estado de um editor)
local function key_hint(k, t)
  return { { Background = { Color = T.sel } }, { Foreground = { Color = T.fg } }, { Text = ' ' .. k .. ' ' },
           { Background = { Color = T.bg } }, { Foreground = { Color = T.comment } }, { Text = ' ' .. t .. '   ' } }
end
local KEYS_HINT = {}
for _, kt in ipairs { { '^T', 'tab' }, { '^D', 'split' }, { '^R', 'history' }, { 'F1', 'help' } } do
  for _, x in ipairs(key_hint(kt[1], kt[2])) do table.insert(KEYS_HINT, x) end
end
KEYS_HINT = wezterm.format(KEYS_HINT)
-- um programa (yt, st...) pode pôr os seus atalhos na barra: user var "hints" = "tecla|texto;tecla|texto"
local function app_hints(s)
  local out = {}
  for pair in s:gmatch('[^;]+') do
    local k, t = pair:match('^(.-)|(.*)$')
    if k then for _, x in ipairs(key_hint(k, t)) do table.insert(out, x) end end
  end
  return wezterm.format(out)
end

-- separadores: so o numero de cada um
wezterm.on('format-tab-title', function(tab) return ' ' .. (tab.tab_index + 1) .. ' ' end)   -- (so o numero)

wezterm.on('update-status', function(window, pane)
  local h = pane:get_user_vars().hints
  window:set_right_status((h and h ~= '') and app_hints(h) or KEYS_HINT)
  -- cada janela arranca em ecra inteiro (so da 1.a vez: depois o F11 / Ctrl+B passam a janela e voltam)
  local seen = wezterm.GLOBAL.fullscreen_done or {}
  local id = tostring(window:window_id())
  if not seen[id] then
    seen[id] = true; wezterm.GLOBAL.fullscreen_done = seen
    if not window:get_dimensions().is_full_screen then window:toggle_fullscreen() end
  end
  local tab = window:active_tab()
  if not tab then return end
  local panes = tab:panes_with_info()
  local header, others = nil, {}
  for _, p in ipairs(panes) do
    if role(p.pane) == 'header' then header = p.pane else table.insert(others, p) end
  end
  if header and #others == 0 then
    if #window:mux_window():tabs() == 1 then
      -- "exit" no ultimo shell: como no Windows Terminal, o terminal nao fecha; abre um shell novo e esconde a janela
      header:split { direction = 'Bottom', size = 0.6 }
      if not os.getenv('SUPERTERMINAL_TEST') then wezterm.background_child_process { AGENT, '--hide' } end
    else
      window:perform_action(act.CloseCurrentPane { confirm = false }, header)
    end
  elseif header and pane:pane_id() == header:pane_id() then
    others[1].pane:activate()
  end
  save_session(window)
end)

-- Ctrl+W: fecha o painel; no ultimo shell da janela so a esconde (como no Windows Terminal; Ctrl+Alt+T volta)
local function close_or_hide(window, pane)
  -- dentro de um ssh: o Ctrl+W vai para o outro PC (o perfil de la sai so da sessao remota), o painel fica
  local fg = (pane:get_foreground_process_name() or ''):lower()
  -- (e dentro do WSL: o zsh do SuperTerminal faz exit e volta ao shell de onde veio; num painel so de WSL, fecha-o)
  if fg:match('ssh%.exe$') or fg:match('wsl%.exe$') or fg:match('wslhost%.exe$') then
    window:perform_action(act.SendKey { key = 'w', mods = 'CTRL' }, pane); return
  end
  local n = 0
  for _, tab in ipairs(window:mux_window():tabs()) do n = n + #shells(tab) end
  if n <= 1 then if not os.getenv('SUPERTERMINAL_TEST') then wezterm.background_child_process { AGENT, '--hide' } end
  else window:perform_action(act.CloseCurrentPane { confirm = false }, pane) end
end

-- ---- atalhos: os mesmos do Windows Terminal ----
local function new_tab(window, pane)
  local tab, p, _ = window:mux_window():spawn_tab {}
  add_header(p)
end

-- ---- Ctrl+P: command palette (comandos, apps, pastas recentes, PCs, setup); enter escreve-o no shell e corre ----
local function read_json(path)
  local f = io.open(path, 'r'); if not f then return nil end
  local s = f:read('*a'); f:close()
  local ok, t = pcall(wezterm.json_parse, s); if ok then return t end
end
local PALETTE_CMDS = {
  { 'yt', 'YouTube' }, { 'st', 'Stremio' }, { 'setup', 'SuperTerminal setup' }, { 'theme', 'change the colours' },
  { 'monitor', 'CPU, GPU, RAM of your PCs' }, { 'super status', 'up to date?' }, { 'super upgrade', 'latest version from GitHub' },
  { 'super sync', 'update every PC' }, { 'lg', 'lazygit' }, { 'reset', 'fix a broken terminal' }, { 'ff', 'clear' },
}
local SETUP_STEPS = { 'font', 'tailscale', 'youtube', 'stremio', 'logo', 'wsl', 'shortcuts', 'widgets', 'sudo' }
-- atalho do terminal so quando o painel esta num shell; dentro de um programa (micro, hx, lazygit...) a tecla e dele
-- (ex.: Ctrl+Q sai do micro). O ssh conta como shell: do outro lado esta um prompt.
local SHELLS = { ['pwsh.exe'] = true, ['powershell.exe'] = true, ['cmd.exe'] = true, ['wsl.exe'] = true, ['wslhost.exe'] = true, zsh = true, bash = true, ['ssh.exe'] = true }
local function in_shell(pane) return SHELLS[(pane:get_foreground_process_name() or ''):lower():match('[^\\/]+$') or ''] end
local function shell_only(key, action)
  return wezterm.action_callback(function(window, pane)
    if in_shell(pane) then window:perform_action(action, pane)
    else window:perform_action(act.SendKey { key = key, mods = 'CTRL' }, pane) end
  end)
end
local function palette(window, pane)
  local fg = (pane:get_foreground_process_name() or ''):lower():match('[^\\/]+$') or ''
  local is_pwsh = fg == 'pwsh.exe' or fg == 'powershell.exe'
  local is_sh = is_pwsh or fg == 'wsl.exe' or fg == 'wslhost.exe' or fg == 'zsh' or fg == 'bash'
  -- dentro de um programa (micro, hx, lazygit, ssh...) o Ctrl+P e dele
  if not is_sh then window:perform_action(act.SendKey { key = 'p', mods = 'CTRL' }, pane); return end
  local choices = {}
  local function add(kind, label, cmd) table.insert(choices, { id = cmd, label = kind .. '  ' .. label }) end
  for _, c in ipairs(PALETTE_CMDS) do add('\u{f120}', c[1] .. '   ' .. c[2], c[1]) end
  for name, _ in pairs(read_json(wezterm.home_dir .. '\\.config\\apps.json') or {}) do add('\u{f2d0}', name .. '   app', 'app ' .. name) end
  local me = wezterm.hostname():lower()
  for _, p in ipairs(read_json(wezterm.home_dir .. '\\.config\\superterminal\\pcs.json') or {}) do
    if p.name and (p.host or ''):lower() ~= me then add('\u{f108}', 'ssh ' .. p.name, 'ssh ' .. p.name) end
  end
  if is_pwsh then
    local ok, out = pcall(function() local s, o = wezterm.run_child_process { 'zoxide', 'query', '-l' }; return s and o end)
    if ok and out then
      local n = 0
      for d in out:gmatch('[^\r\n]+') do n = n + 1; if n > 20 then break end; add('\u{f07b}', d, "cd '" .. d:gsub("'", "''") .. "'") end
    end
  end
  for _, s in ipairs(SETUP_STEPS) do add('\u{f013}', 'setup ' .. s, 'setup ' .. s) end
  window:perform_action(act.InputSelector {
    title = 'SuperTerminal', fuzzy = true, fuzzy_description = '\u{f002}  ', choices = choices,
    action = wezterm.action_callback(function(w, p, id)
      if not id then return end
      -- limpa o que estiver escrito (pwsh: esc; zsh/bash: ctrl+u) e corre
      p:send_text((is_pwsh and '\x1b' or '\x15') .. id .. '\r')
    end),
  }, pane)
end

-- cada atalho tem um nome; o setup > Shortcuts muda-os em ~\.config\superterminal\keys.json ({"new_tab": "CTRL+SHIFT+t"})
local actions = {
  { 'new_tab', 'CTRL+t', wezterm.action_callback(new_tab) },
  { 'split', 'CTRL+d', act.SplitHorizontal { domain = 'CurrentPaneDomain' } },
  { 'close', 'CTRL+w', wezterm.action_callback(close_or_hide) },
  { 'prev_tab', 'CTRL+q', shell_only('q', act.ActivateTabRelative(-1)) },
  { 'next_tab', 'CTRL+e', shell_only('e', act.ActivateTabRelative(1)) },
  { 'zoom', 'CTRL+SHIFT+z', act.TogglePaneZoomState },
  { 'fullscreen', 'CTRL+b', act.ToggleFullScreen },
  { 'search', 'CTRL+SHIFT+f', act.Search 'CurrentSelectionOrEmptyString' },
  { 'paste', 'CTRL+v', act.PasteFrom 'Clipboard' },
  -- Ctrl+C: com texto selecionado copia; sem selecao chega ao programa (interromper)
  { 'copy', 'CTRL+c', wezterm.action_callback(function(window, pane)
      local sel = window:get_selection_text_for_pane(pane)
      if sel ~= '' then
        window:perform_action(act.CopyTo 'Clipboard', pane)
        window:perform_action(act.ClearSelection, pane)
      else
        window:perform_action(act.SendKey { key = 'c', mods = 'CTRL' }, pane)
      end
    end) },
  -- Alt+setas (como no Windows Terminal): as Ctrl+setas ficam para o shell / editores (saltar uma palavra)
  { 'pane_left', 'ALT+LeftArrow', act.ActivatePaneDirection 'Left' },
  { 'pane_right', 'ALT+RightArrow', act.ActivatePaneDirection 'Right' },
  { 'pane_up', 'ALT+UpArrow', act.ActivatePaneDirection 'Up' },
  { 'pane_down', 'ALT+DownArrow', act.ActivatePaneDirection 'Down' },
  { 'palette', 'CTRL+p', wezterm.action_callback(palette) },
}
local KEYS_FILE = wezterm.home_dir .. '\\.config\\superterminal\\keys.json'
local EDITING = wezterm.home_dir .. '\\.config\\superterminal\\keys-editing'
wezterm.add_to_config_reload_watch_list(KEYS_FILE); wezterm.add_to_config_reload_watch_list(EDITING)
local custom = {}
do
  local f = io.open(KEYS_FILE, 'r')
  if f then local s = f:read('*a'); f:close(); local ok, t = pcall(wezterm.json_parse, s); if ok and type(t) == 'table' then custom = t end end
end
local function bind(spec, action)   -- "CTRL+SHIFT+z" -> { key = 'z', mods = 'CTRL|SHIFT' }
  local parts = {}; for p in spec:gmatch('[^+]+') do table.insert(parts, p) end
  local key = table.remove(parts)
  return { key = key, mods = (#parts > 0) and table.concat(parts, '|') or 'NONE', action = action }
end
config.keys = {}
local f_ed = io.open(EDITING, 'r')
if f_ed then
  -- o editor de atalhos esta aberto: as teclas vao todas para ele (para se poder carregar o atalho novo)
  f_ed:close(); config.disable_default_key_bindings = true
else
  for _, a in ipairs(actions) do
    local spec = custom[a[1]] or a[2]
    if spec ~= '' then table.insert(config.keys, bind(spec, a[3])) end   -- "" = sem atalho
  end
  table.insert(config.keys, { key = 'F11', action = act.ToggleFullScreen })   -- ecra inteiro (como arranca) <-> janela
  for i = 1, 9 do
    table.insert(config.keys, { key = tostring(i), mods = 'CTRL', action = act.ActivateTab(i - 1) })
  end
end

return config
