let s:default_input_filename = 'compile_commands.json'
let s:default_output_filename = 'compile_commands.json'
let s:cmake_config_filename = '.vim-cmake-naive-config.json'
let s:cmake_presets_filename = 'CMakePresets.json'
let s:cmake_cache_filename = '.vim-cmake-naive-cache.json'
let s:cmake_config_preset_key = 'preset'
let s:cmake_config_build_config_key = 'build'
let s:cmake_config_output_key = 'output'
let s:cmake_config_target_key = 'target'
let s:cmake_config_default_build = 'Debug'
let s:cmake_config_default_output = 'build'
let s:cmake_environment_prefix = 'VIM_NAIVE_CMAKE_'
let s:cmake_switch_preset_none_name = 'none'
let s:cmake_switch_build_none_name = 'none'
let s:cmake_switch_target_all_name = 'all'
let s:cmake_switch_target_missing_cache_error = 'No cache found. Please run CMakeGenerate command first.'
let s:cmake_run_missing_target_error = 'No target selected. Please use CMakeSwitchTarget command first.'
let s:cmake_switch_build_default_types = ['Debug', 'Release', 'RelWithDebInfo', 'MinSizeRel']
let s:target_directory_pattern = '\v^(.{-}CMakeFiles[\\/][^\\/]+\.dir)([\\/]|$)'
let s:is_windows = has('win32') || has('win64') || has('win32unix')
let s:switch_popup_fixed_width = 30
let s:switch_popup_max_height = 10
let s:build_terminal_max_height = 10
let s:switch_target_popup_states = {}
let s:build_terminal_buffer_name = '[vim-cmake-naive-build]'
let s:last_cmake_build_window_id = -1
let s:last_cmake_build_buffer_number = -1
let s:last_cmake_build_split_orientation = 'vertical'
let s:build_terminal_success_callbacks = {}
let s:running_cmake_command_name = ''
let s:cmake_missing_local_config_error =
      \ s:cmake_config_filename . ' not found in current directory or any parent directory.'
let s:cmake_menu_prompt = 'Select CMake command'
let s:cmake_menu_full_command_specs = [
      \ {'name': 'CMakeConfig', 'needs_args': 0},
      \ {'name': 'CMakeConfigDefault', 'needs_args': 0},
      \ {'name': 'CMakeSwitchPreset', 'needs_args': 0},
      \ {'name': 'CMakeSwitchBuild', 'needs_args': 0},
      \ {'name': 'CMakeSwitchTarget', 'needs_args': 0},
      \ {'name': 'CMakeGenerate', 'needs_args': 0},
      \ {'name': 'CMakeBuild', 'needs_args': 0},
      \ {'name': 'CMakeTest', 'needs_args': 0},
      \ {'name': 'CMakeRun', 'needs_args': 0},
      \ {'name': 'CMakeClose', 'needs_args': 0},
      \ {'name': 'CMakeInfo', 'needs_args': 0},
      \ {'name': 'CMakeMenu', 'needs_args': 0},
      \ {'name': 'CMakeMenuFull', 'needs_args': 0},
      \ {'name': 'CMakeConfigSetOutput', 'needs_args': 1}
      \ ]
let s:cmake_menu_compact_command_specs = [
      \ {'name': 'CMakeBuild', 'needs_args': 0},
      \ {'name': 'CMakeRun', 'needs_args': 0},
      \ {'name': 'CMakeTest', 'needs_args': 0},
      \ {'name': 'CMakeSwitchTarget', 'needs_args': 0}
      \ ]

function! s:active_running_cmake_command() abort
  if exists('g:vim_cmake_naive_test_forced_running_cmake_command')
    return trim(s:to_string_or_empty(g:vim_cmake_naive_test_forced_running_cmake_command))
  endif

  return s:running_cmake_command_name
endfunction

function! s:run_cmake_command(command_name, command_funcref, command_args) abort
  let l:running_command = s:active_running_cmake_command()
  if !empty(l:running_command)
    throw 'CMake: another command ' . l:running_command . ' is already running'
  endif

  let s:running_cmake_command_name = a:command_name
  try
    return call(a:command_funcref, a:command_args)
  finally
    let s:running_cmake_command_name = ''
  endtry
endfunction

function! vim_cmake_naive#split(...) abort
  try
    let l:options = s:parse_split_args(a:000)
    call s:run_split(l:options)
  catch
    call s:write_error(s:format_exception(v:exception))
  endtry
endfunction

function! vim_cmake_naive#switch(...) abort
  try
    let l:options = s:parse_switch_args(a:000)
    call s:run_switch(l:options)
  catch
    call s:write_error(s:format_exception(v:exception))
  endtry
endfunction

function! vim_cmake_naive#cmake_config() abort
  try
    call s:run_cmake_command('CMakeConfig', function('s:run_cmake_config'), [])
  catch
    call s:write_error(s:format_exception(v:exception))
  endtry
endfunction

function! vim_cmake_naive#switch_preset() abort
  try
    call s:run_cmake_command('CMakeSwitchPreset', function('s:run_switch_preset'), [])
  catch
    call s:write_error(s:format_exception(v:exception))
  endtry
endfunction

function! vim_cmake_naive#switch_build() abort
  try
    call s:run_cmake_command('CMakeSwitchBuild', function('s:run_switch_build'), [])
  catch
    call s:write_error(s:format_exception(v:exception))
  endtry
endfunction

function! vim_cmake_naive#switch_target() abort
  try
    call s:run_cmake_command('CMakeSwitchTarget', function('s:run_switch_target'), [])
  catch
    let l:message = s:format_exception(v:exception)
    if l:message ==# s:cmake_switch_target_missing_cache_error
      call s:write_builtin_error(l:message)
      return
    endif
    call s:write_error(l:message)
  endtry
endfunction

function! vim_cmake_naive#set_config_preset(preset) abort
  try
    call s:run_cmake_command('CMakeConfigSetPreset', function('s:run_set_config_preset'), [a:preset])
  catch
    call s:write_error(s:format_exception(v:exception))
  endtry
endfunction

function! vim_cmake_naive#set_config_build_config(build_config) abort
  try
    call s:run_cmake_command('CMakeConfigSetBuild', function('s:run_set_config_build_config'), [a:build_config])
  catch
    call s:write_error(s:format_exception(v:exception))
  endtry
endfunction

function! vim_cmake_naive#set_config_output(output) abort
  try
    call s:run_cmake_command('CMakeConfigSetOutput', function('s:run_set_config_output'), [a:output])
  catch
    call s:write_error(s:format_exception(v:exception))
  endtry
endfunction

function! vim_cmake_naive#cmake_config_default() abort
  try
    call s:run_cmake_command('CMakeConfigDefault', function('s:run_cmake_config_default'), [])
  catch
    call s:write_error(s:format_exception(v:exception))
  endtry
endfunction

function! vim_cmake_naive#generate() abort
  try
    call s:run_cmake_command('CMakeGenerate', function('s:run_generate'), [])
  catch
    call s:write_error(s:format_exception(v:exception))
  endtry
endfunction

function! vim_cmake_naive#build() abort
  try
    call s:run_cmake_command('CMakeBuild', function('s:run_build'), [])
  catch
    call s:write_error(s:format_exception(v:exception))
  endtry
endfunction

function! vim_cmake_naive#test() abort
  try
    call s:run_cmake_command('CMakeTest', function('s:run_test'), [])
  catch
    call s:write_error(s:format_exception(v:exception))
  endtry
endfunction

function! vim_cmake_naive#run() abort
  try
    call s:run_cmake_command('CMakeRun', function('s:run_run'), [])
  catch
    call s:write_error(s:format_exception(v:exception))
  endtry
endfunction

function! vim_cmake_naive#close() abort
  try
    call s:run_cmake_command('CMakeClose', function('s:run_close'), [])
  catch
    call s:write_error(s:format_exception(v:exception))
  endtry
endfunction

function! vim_cmake_naive#info() abort
  try
    call s:run_cmake_command('CMakeInfo', function('s:run_info'), [])
  catch
    call s:write_error(s:format_exception(v:exception))
  endtry
endfunction

function! vim_cmake_naive#menu() abort
  try
    let l:selected_command = s:run_cmake_command(
          \ 'CMakeMenu',
          \ function('s:run_menu_with_specs'),
          \ [s:cmake_menu_compact_command_specs])
    if !empty(l:selected_command)
      call s:execute_menu_command(l:selected_command)
    endif
  catch
    call s:write_error(s:format_exception(v:exception))
  endtry
endfunction

function! vim_cmake_naive#menu_full() abort
  try
    let l:selected_command = s:run_cmake_command(
          \ 'CMakeMenuFull',
          \ function('s:run_menu_with_specs'),
          \ [s:cmake_menu_full_command_specs])
    if !empty(l:selected_command)
      call s:execute_menu_command(l:selected_command)
    endif
  catch
    call s:write_error(s:format_exception(v:exception))
  endtry
endfunction

function! vim_cmake_naive#sync_environment_from_local_config_on_startup() abort
  try
    call s:sync_environment_from_local_config(getcwd())
  catch
    call s:write_error(s:format_exception(v:exception))
  endtry
endfunction

function! s:run_info() abort
  let l:working_directory = s:normalize_full_path(getcwd())
  let l:config_exists = 1
  let l:config_path = ''
  let l:config = {}
  let l:display_lines = []
  let l:title = 'CMake info'

  try
    let l:config_path = s:resolve_existing_local_config_path(l:working_directory)
    let l:config = s:read_json_object(l:config_path)
  catch
    let l:message = s:format_exception(v:exception)
    if stridx(l:message, s:cmake_missing_local_config_error) < 0
      throw l:message
    endif
    let l:config_exists = 0
  endtry

  if !l:config_exists
    let l:display_lines = ['No configuration, please use CMakeConfigDefault to get started']
  else
    let l:display_lines = s:config_table_lines(l:config)
    let l:config_root = s:normalize_full_path(fnamemodify(l:config_path, ':h'))
    let l:title = l:title . ' [' . s:relative_path(l:config_path, l:config_root) . ']'
  endif

  call s:show_info_popup(l:title, l:display_lines)
endfunction

function! s:config_table_lines(config) abort
  let l:config_keys = keys(a:config)
  if empty(l:config_keys)
    return ['No values found in local configuration']
  endif

  call sort(l:config_keys)
  let l:key_width = 0
  for l:key in l:config_keys
    let l:key_width = max([l:key_width, strlen(l:key)])
  endfor

  let l:lines = []
  for l:key in l:config_keys
    let l:value = get(a:config, l:key, '')
    if type(l:value) == v:t_string
      let l:value_text = l:value
    else
      let l:value_text = json_encode(l:value)
    endif

    call add(l:lines, printf('%-' . l:key_width . 's | %s', l:key, l:value_text))
  endfor

  return l:lines
endfunction

function! s:show_info_popup(title, lines) abort
  let l:content_lines = empty(a:lines) ? [''] : copy(a:lines)
  let l:content_width = max(map(copy(l:content_lines), 'strlen(v:val)'))
  let l:title_width = strlen(a:title)
  let l:popup_width = max([s:switch_popup_fixed_width, l:content_width, l:title_width])
  let l:popup_height = max([1, min([len(l:content_lines), s:switch_popup_max_height])])
  let l:popup_options = {
        \ 'title': a:title,
        \ 'highlight': 'Pmenu',
        \ 'border': [1, 1, 1, 1],
        \ 'borderchars': ['─', '│', '─', '│', '╭', '╮', '╯', '╰'],
        \ 'borderhighlight': ['Pmenu'],
        \ 'minwidth': l:popup_width,
        \ 'maxwidth': l:popup_width,
        \ 'minheight': l:popup_height,
        \ 'maxheight': l:popup_height,
        \ 'scrollbar': 1,
        \ 'padding': [0, 1, 0, 1],
        \ 'mapping': 0,
        \ 'filter': 'popup_filter_menu'
        \ }

  if exists('g:vim_cmake_naive_test_popup_menu_response')
    let g:vim_cmake_naive_test_last_info_popup_items = copy(l:content_lines)
    let g:vim_cmake_naive_test_last_info_popup_options = copy(l:popup_options)
    return
  endif

  call popup_create(l:content_lines, l:popup_options)
endfunction

function! s:parse_split_args(argv) abort
  let l:args = copy(a:argv)
  if empty(l:args)
    throw 'Missing required argument: <build-directory>.'
  endif

  let l:options = {
        \ 'build_directory': remove(l:args, 0),
        \ 'input_path': '',
        \ 'output_name': s:default_output_filename,
        \ 'dry_run': 0
        \ }

  let l:index = 0
  while l:index < len(l:args)
    let l:arg = l:args[l:index]

    if l:arg ==# '--dry-run'
      let l:options.dry_run = 1
      let l:index += 1
      continue
    endif

    if l:arg ==# '-i' || l:arg ==# '--input'
      if l:index + 1 >= len(l:args)
        throw 'Missing value for option ' . l:arg . '.'
      endif

      let l:options.input_path = l:args[l:index + 1]
      let l:index += 2
      continue
    endif

    if l:arg =~# '^--input='
      let l:options.input_path = strpart(l:arg, strlen('--input='))
      let l:index += 1
      continue
    endif

    if l:arg ==# '-o' || l:arg ==# '--output-name'
      if l:index + 1 >= len(l:args)
        throw 'Missing value for option ' . l:arg . '.'
      endif

      let l:options.output_name = l:args[l:index + 1]
      let l:index += 2
      continue
    endif

    if l:arg =~# '^--output-name='
      let l:options.output_name = strpart(l:arg, strlen('--output-name='))
      let l:index += 1
      continue
    endif

    throw 'Unknown option: ' . l:arg
  endwhile

  if empty(trim(l:options.build_directory))
    throw 'Missing required argument: <build-directory>.'
  endif

  if empty(trim(l:options.output_name))
    throw 'Output file name cannot be empty.'
  endif

  if l:options.output_name =~# '[/\\]'
    throw 'Output file name must not contain path separators.'
  endif

  return l:options
endfunction

function! s:parse_switch_args(argv) abort
  let l:args = copy(a:argv)
  if len(l:args) < 2
    throw 'Usage: vim_cmake_naive#switch(<build-directory>, <target>, [--output <path>])'
  endif

  let l:options = {
        \ 'build_directory': remove(l:args, 0),
        \ 'target': remove(l:args, 0),
        \ 'output': ''
        \ }

  let l:index = 0
  while l:index < len(l:args)
    let l:arg = l:args[l:index]

    if l:arg ==# '-o' || l:arg ==# '--output'
      if l:index + 1 >= len(l:args)
        throw 'Missing value for option ' . l:arg . '.'
      endif

      let l:options.output = l:args[l:index + 1]
      let l:index += 2
      continue
    endif

    if l:arg =~# '^--output='
      let l:options.output = strpart(l:arg, strlen('--output='))
      let l:index += 1
      continue
    endif

    throw 'Unknown option: ' . l:arg
  endwhile

  if empty(trim(l:options.build_directory))
    throw 'Missing required argument: <build-directory>.'
  endif

  if empty(trim(l:options.target))
    throw 'Missing required argument: <target>.'
  endif

  if l:options.target =~# '[/\\]'
    throw 'The <target> argument must be a target name (for example: my_app), not a path.'
  endif

  if !empty(l:options.output) && empty(trim(l:options.output))
    throw 'Output path cannot be empty.'
  endif

  return l:options
endfunction

function! s:run_split(options) abort
  let l:build_directory = s:resolve_build_directory(a:options.build_directory)
  let l:input_path = s:resolve_input_file_path(a:options.input_path, l:build_directory)
  let l:entries = s:read_json_array(l:input_path)

  let l:grouped_entries = {}
  let l:processed_count = 0
  let l:assigned_count = 0
  let l:skipped_count = 0

  for l:entry in l:entries
    let l:processed_count += 1

    if type(l:entry) != v:t_dict
      call s:write_error('Skipping entry #' . l:processed_count . ': expected JSON object.')
      let l:skipped_count += 1
      continue
    endif

    let l:working_directory = s:resolve_working_directory(
          \ s:to_string_or_empty(get(l:entry, 'directory', '')),
          \ l:build_directory)
    let l:target_directory = s:infer_target_directory(
          \ l:build_directory,
          \ l:working_directory,
          \ s:to_string_or_empty(get(l:entry, 'output', '')),
          \ get(l:entry, 'arguments', v:null),
          \ s:to_string_or_empty(get(l:entry, 'command', '')))

    if empty(l:target_directory)
      let l:skipped_count += 1
      continue
    endif

    if !has_key(l:grouped_entries, l:target_directory)
      let l:grouped_entries[l:target_directory] = []
    endif

    call add(l:grouped_entries[l:target_directory], l:entry)
    let l:assigned_count += 1
  endfor

  if empty(keys(l:grouped_entries))
    throw 'No target directories were inferred from the input. Nothing was written.'
  endif

  let l:target_directories = keys(l:grouped_entries)
  call sort(l:target_directories)

  let l:file_write_count = 0
  for l:target_directory in l:target_directories
    let l:output_path = s:path_join(l:target_directory, a:options.output_name)
    let l:relative_output_path = s:relative_path(l:output_path, l:build_directory)

    if a:options.dry_run
      call s:write_info('[dry-run] ' . l:relative_output_path . ': ' . len(l:grouped_entries[l:target_directory]) . ' entries')
      continue
    endif

    call mkdir(l:target_directory, 'p')
    call s:write_json_file(l:output_path, l:grouped_entries[l:target_directory])

    let l:file_write_count += 1
    call s:write_info('Wrote ' . len(l:grouped_entries[l:target_directory]) . ' entries to ' . l:relative_output_path)
  endfor

  call s:write_info('')
  call s:write_info('Processed entries: ' . l:processed_count)
  call s:write_info('Assigned entries: ' . l:assigned_count)
  call s:write_info('Skipped entries: ' . l:skipped_count)
  if a:options.dry_run
    call s:write_info('Planned output files: ' . len(l:target_directories))
  else
    call s:write_info('Written files: ' . l:file_write_count)
  endif
endfunction

function! s:run_switch(options) abort
  let l:build_directory = s:resolve_build_directory(a:options.build_directory)
  let l:target_directory = s:resolve_switch_target_directory(a:options.target, l:build_directory)
  let l:output_directory = empty(a:options.output)
        \ ? l:build_directory
        \ : s:resolve_directory_path(a:options.output, l:build_directory, 'output', 0)

  let l:source_file_path = s:path_join(l:target_directory, s:default_input_filename)
  call s:copy_compile_commands_file(l:source_file_path, l:output_directory)
endfunction

function! s:run_cmake_config() abort
  let l:project_root = s:resolve_cmake_project_root(getcwd())
  let l:config_path = s:cmake_config_path(l:project_root)
  let l:config_directory = fnamemodify(l:config_path, ':h')

  if filereadable(l:config_path)
    call s:write_info('Config already exists: ' . s:relative_path(l:config_path, l:project_root))
    return
  endif

  let l:config = s:default_cmake_config_payload()
  call mkdir(l:config_directory, 'p')
  call s:write_json_file(l:config_path, l:config)
  call s:sync_environment_from_config(l:config)

  call s:write_info('Created ' . s:relative_path(l:config_path, l:project_root))
endfunction

function! s:run_set_config_preset(preset) abort
  let l:preset = s:to_string_or_empty(a:preset)
  if empty(trim(l:preset))
    throw 'Preset value cannot be empty.'
  endif
  call s:set_config_value(s:cmake_config_preset_key, l:preset, 1)
endfunction

function! s:run_set_config_build_config(build_config) abort
  let l:build_config = s:to_string_or_empty(a:build_config)
  if empty(trim(l:build_config))
    throw 'Build config value cannot be empty.'
  endif
  call s:set_config_value(s:cmake_config_build_config_key, l:build_config, 1)
endfunction

function! s:run_set_config_output(output) abort
  let l:output = s:to_string_or_empty(a:output)
  if empty(trim(l:output))
    throw 'Output value cannot be empty.'
  endif
  call s:set_config_value(s:cmake_config_output_key, l:output, 1)
endfunction

function! s:run_switch_preset() abort
  let l:working_directory = s:normalize_full_path(getcwd())
  let l:project_root = s:resolve_cmake_project_root(getcwd())
  let l:selection_prompt = 'Select CMake preset'
  let l:presets_path = s:cmake_presets_path(l:project_root)
  if !filereadable(l:presets_path)
    throw s:cmake_presets_filename . ' not found at project root: ' . l:presets_path
  endif

  let l:presets_payload = s:read_json_object(l:presets_path)
  let l:available_presets = s:available_configure_presets(l:presets_payload, l:project_root)
  call sort(l:available_presets)
  let l:current_preset = s:current_config_preset_for_switch(l:working_directory)
  if empty(l:current_preset)
    let l:current_preset = s:cmake_switch_preset_none_name
  endif
  call insert(l:available_presets, s:cmake_switch_preset_none_name)

  if s:should_use_popup_menu_for_preset_selection()
    call s:show_switch_preset_popup(l:selection_prompt, l:available_presets, l:current_preset)
    return
  endif

  let l:selected_preset = s:select_item_from_menu(l:selection_prompt, l:available_presets)
  if empty(l:selected_preset)
    call s:write_info('Preset selection canceled.')
    return
  endif

  call s:apply_switch_preset_selection(l:selected_preset)
endfunction

function! s:run_switch_build() abort
  let l:working_directory = s:normalize_full_path(getcwd())
  let l:selection_prompt = 'Select CMake build'
  let l:current_build = s:current_config_build_for_switch(l:working_directory)
  let l:available_builds = copy(s:cmake_switch_build_default_types)
  call insert(l:available_builds, s:cmake_switch_build_none_name)
  if empty(l:current_build)
    let l:current_build = s:cmake_switch_build_none_name
  endif

  if s:should_use_popup_menu_for_preset_selection()
    call s:show_switch_build_popup(l:selection_prompt, l:available_builds, l:current_build)
    return
  endif

  let l:selected_build = s:select_item_from_menu(l:selection_prompt, l:available_builds)
  if empty(l:selected_build)
    call s:write_info('Build selection canceled.')
    return
  endif

  call s:apply_switch_build_selection(l:selected_build)
endfunction

function! s:run_menu_with_specs(command_specs) abort
  let l:commands = s:menu_commands(a:command_specs)
  if empty(l:commands)
    throw 'No selectable CMake commands found.'
  endif

  if s:should_use_popup_menu_for_preset_selection()
    return s:show_menu_popup(s:cmake_menu_prompt, l:commands)
  endif

  let l:selected_command = s:select_item_from_list(s:cmake_menu_prompt, l:commands)
  if empty(l:selected_command)
    call s:write_info('CMake command selection canceled.')
    return ''
  endif

  return l:selected_command
endfunction

function! s:menu_commands(command_specs) abort
  let l:commands = []
  for l:command_spec in a:command_specs
    let l:command_name = s:to_string_or_empty(get(l:command_spec, 'name', ''))
    if exists(':' . l:command_name) == 2
      call add(l:commands, l:command_name)
    endif
  endfor

  return l:commands
endfunction

function! s:show_menu_popup(prompt, commands) abort
  let l:display_items = s:preset_popup_display_items(a:commands, '')
  let l:popup_options = s:switch_preset_popup_options(a:prompt, a:commands)
  if exists('g:vim_cmake_naive_test_popup_menu_response')
    let g:vim_cmake_naive_test_last_menu_popup_items = copy(l:display_items)
    let g:vim_cmake_naive_test_last_menu_popup_options = copy(l:popup_options)
    return s:selected_menu_command_from_popup_result(copy(a:commands), g:vim_cmake_naive_test_popup_menu_response)
  endif

  let l:popup_options.callback = function('s:on_menu_popup_selection', [copy(a:commands)])
  call popup_menu(l:display_items, l:popup_options)
  return ''
endfunction

function! s:selected_menu_command_from_popup_result(commands, result) abort
  let l:index = type(a:result) == v:t_number
        \ ? a:result
        \ : str2nr(s:to_string_or_empty(a:result))
  if l:index <= 0 || l:index > len(a:commands)
    call s:write_info('CMake command selection canceled.')
    return ''
  endif

  return a:commands[l:index - 1]
endfunction

function! s:on_menu_popup_selection(commands, _popup_id, result) abort
  let l:selected_command = s:selected_menu_command_from_popup_result(a:commands, a:result)
  if empty(l:selected_command)
    return
  endif

  call s:execute_menu_command(l:selected_command)
endfunction

function! s:execute_menu_command(command_name) abort
  let l:command_spec = s:menu_command_spec(a:command_name)
  let l:command_arguments = ''
  if get(l:command_spec, 'needs_args', 0)
    let l:command_arguments = s:menu_command_arguments(a:command_name)
    if empty(trim(l:command_arguments))
      call s:write_info(a:command_name . ' canceled.')
      return
    endif
  endif

  let l:command_line = 'silent ' . a:command_name
  if !empty(l:command_arguments)
    let l:command_line .= ' ' . l:command_arguments
  endif
  execute l:command_line
endfunction

function! s:menu_command_spec(command_name) abort
  for l:command_spec in s:cmake_menu_full_command_specs
    if s:to_string_or_empty(get(l:command_spec, 'name', '')) ==# a:command_name
      return l:command_spec
    endif
  endfor

  return {'name': a:command_name, 'needs_args': 0}
endfunction

function! s:menu_command_arguments(command_name) abort
  if exists('g:vim_cmake_naive_test_menu_command_args')
    return s:to_string_or_empty(get(g:vim_cmake_naive_test_menu_command_args, a:command_name, ''))
  endif

  return input('Arguments for ' . a:command_name . ': ')
endfunction

function! s:current_config_preset_for_switch(start_directory) abort
  try
    let l:config_path = s:resolve_existing_local_config_path(a:start_directory)
  catch
    let l:message = s:format_exception(v:exception)
    if stridx(l:message, s:cmake_missing_local_config_error) >= 0
      return ''
    endif
    throw l:message
  endtry

  let l:config = s:read_json_object(l:config_path)
  return trim(s:to_string_or_empty(get(l:config, s:cmake_config_preset_key, '')))
endfunction

function! s:current_config_build_for_switch(start_directory) abort
  try
    let l:config_path = s:resolve_existing_local_config_path(a:start_directory)
  catch
    let l:message = s:format_exception(v:exception)
    if stridx(l:message, s:cmake_missing_local_config_error) >= 0
      return ''
    endif
    throw l:message
  endtry

  let l:config = s:read_json_object(l:config_path)
  return trim(s:to_string_or_empty(get(l:config, s:cmake_config_build_config_key, '')))
endfunction

function! s:should_use_popup_menu_for_preset_selection() abort
  if exists('g:vim_cmake_naive_test_use_popup_menu')
    return s:as_condition_bool(g:vim_cmake_naive_test_use_popup_menu)
  endif

  return exists('*popup_menu')
        \ && !exists('g:vim_cmake_naive_test_menu_response')
        \ && !exists('g:vim_cmake_naive_test_inputlist_response')
endfunction

function! s:show_switch_preset_popup(prompt, items, current_preset) abort
  let l:display_items = s:preset_popup_display_items(
        \ a:items,
        \ a:current_preset,
        \ {s:cmake_switch_preset_none_name: '(' . s:cmake_switch_preset_none_name . ')'})
  let l:popup_options = s:switch_preset_popup_options(a:prompt, a:items)
  if exists('g:vim_cmake_naive_test_popup_menu_response')
    let g:vim_cmake_naive_test_last_preset_popup_items = copy(l:display_items)
    let g:vim_cmake_naive_test_last_preset_popup_options = copy(l:popup_options)
    call s:on_switch_preset_popup_selection(copy(a:items), 0, g:vim_cmake_naive_test_popup_menu_response)
    return
  endif

  call popup_menu(l:display_items, l:popup_options)
endfunction

function! s:switch_popup_height(items) abort
  return max([1, min([len(a:items), s:switch_popup_max_height])])
endfunction

function! s:switch_popup_options(prompt, items) abort
  let l:popup_height = s:switch_popup_height(a:items)
  return {
        \ 'title': a:prompt,
        \ 'highlight': 'Pmenu',
        \ 'border': [1, 1, 1, 1],
        \ 'borderchars': ['─', '│', '─', '│', '╭', '╮', '╯', '╰'],
        \ 'borderhighlight': ['Pmenu'],
        \ 'minwidth': s:switch_popup_fixed_width,
        \ 'maxwidth': s:switch_popup_fixed_width,
        \ 'minheight': l:popup_height,
        \ 'maxheight': l:popup_height,
        \ 'scrollbar': 1
        \ }
endfunction

function! s:switch_preset_popup_options(prompt, items) abort
  let l:popup_options = s:switch_popup_options(a:prompt, a:items)
  let l:popup_options.callback = function('s:on_switch_preset_popup_selection', [copy(a:items)])
  return l:popup_options
endfunction

function! s:preset_popup_display_items(items, current_preset, ...) abort
  let l:display_names = a:0 > 0 && type(a:1) == v:t_dict ? a:1 : {}
  let l:display_items = []
  let l:number_width = strlen(string(len(a:items)))
  let l:index = 0
  while l:index < len(a:items)
    let l:item = a:items[l:index]
    let l:display_name = get(l:display_names, l:item, l:item)
    let l:marker = (!empty(a:current_preset) && l:item ==# a:current_preset) ? '*' : ' '
    let l:display_item = printf('%' . l:number_width . 'd.', l:index + 1) . ' ' . l:marker . ' ' . l:display_name
    call add(l:display_items, l:display_item)
    let l:index += 1
  endwhile

  return l:display_items
endfunction

function! s:on_switch_preset_popup_selection(items, _popup_id, result) abort
  let l:index = type(a:result) == v:t_number
        \ ? a:result
        \ : str2nr(s:to_string_or_empty(a:result))
  if l:index <= 0 || l:index > len(a:items)
    call s:write_info('Preset selection canceled.')
    return
  endif

  let l:selected_preset = a:items[l:index - 1]
  try
    call s:apply_switch_preset_selection(l:selected_preset)
  catch
    call s:write_error(s:format_exception(v:exception))
  endtry
endfunction

function! s:show_switch_build_popup(prompt, items, current_build) abort
  let l:display_items = s:preset_popup_display_items(
        \ a:items,
        \ a:current_build,
        \ {s:cmake_switch_build_none_name: '(' . s:cmake_switch_build_none_name . ')'})
  let l:popup_options = s:switch_build_popup_options(a:prompt, a:items)
  if exists('g:vim_cmake_naive_test_popup_menu_response')
    let g:vim_cmake_naive_test_last_build_popup_items = copy(l:display_items)
    let g:vim_cmake_naive_test_last_build_popup_options = copy(l:popup_options)
    call s:on_switch_build_popup_selection(copy(a:items), 0, g:vim_cmake_naive_test_popup_menu_response)
    return
  endif

  call popup_menu(l:display_items, l:popup_options)
endfunction

function! s:switch_build_popup_options(prompt, items) abort
  let l:popup_options = s:switch_popup_options(a:prompt, a:items)
  let l:popup_options.callback = function('s:on_switch_build_popup_selection', [copy(a:items)])
  return l:popup_options
endfunction

function! s:on_switch_build_popup_selection(items, _popup_id, result) abort
  let l:index = type(a:result) == v:t_number
        \ ? a:result
        \ : str2nr(s:to_string_or_empty(a:result))
  if l:index <= 0 || l:index > len(a:items)
    call s:write_info('Build selection canceled.')
    return
  endif

  let l:selected_build = a:items[l:index - 1]
  try
    call s:apply_switch_build_selection(l:selected_build)
  catch
    call s:write_error(s:format_exception(v:exception))
  endtry
endfunction

function! s:apply_switch_preset_selection(selected_preset) abort
  if a:selected_preset ==# s:cmake_switch_preset_none_name
    call s:remove_config_value(s:cmake_config_preset_key, 1)
    return
  endif

  call s:run_set_config_preset(a:selected_preset)
  call s:remove_config_value(s:cmake_config_build_config_key, 1)
endfunction

function! s:apply_switch_build_selection(selected_build) abort
  if a:selected_build ==# s:cmake_switch_build_none_name
    call s:remove_config_value(s:cmake_config_build_config_key, 1)
    return
  endif

  call s:run_set_config_build_config(a:selected_build)
  call s:remove_config_value(s:cmake_config_preset_key, 1)
endfunction

function! s:run_switch_target() abort
  let l:working_directory = s:normalize_full_path(getcwd())
  let l:config_path = s:resolve_existing_local_config_path(l:working_directory)
  let l:config = s:read_json_object(l:config_path)
  let l:selection_prompt = 'Select CMake target'
  let l:project_root = s:normalize_full_path(fnamemodify(l:config_path, ':h'))
  let l:output_value = s:to_string_or_empty(get(l:config, s:cmake_config_output_key, s:cmake_config_default_output))
  let l:preset_value = trim(s:to_string_or_empty(get(l:config, s:cmake_config_preset_key, '')))
  let l:current_target = trim(s:to_string_or_empty(get(l:config, s:cmake_config_target_key, '')))
  let l:targets = s:cached_targets_for_switch(l:config_path)
  call insert(l:targets, s:cmake_switch_target_all_name)
  if empty(l:current_target)
    let l:current_target = s:cmake_switch_target_all_name
  endif
  if empty(trim(l:output_value))
    let l:output_value = s:cmake_config_default_output
  endif

  let l:build_directory = s:resolve_path(l:output_value, l:project_root)
  if !isdirectory(l:build_directory)
    throw 'Build directory not found: ' . l:build_directory
  endif

  let l:scan_directory = s:target_scan_directory(l:build_directory, l:preset_value)

  if s:should_use_popup_menu_for_preset_selection()
    call s:show_switch_target_popup(
          \ l:selection_prompt,
          \ l:targets,
          \ l:current_target,
          \ l:preset_value,
          \ l:build_directory,
          \ l:scan_directory)
    return
  endif

  let l:selected_target = s:select_item_from_list(l:selection_prompt, l:targets)
  if empty(l:selected_target)
    call s:write_info('Target selection canceled.')
    return
  endif

  call s:apply_switch_target_selection(l:selected_target, l:preset_value, l:build_directory, l:scan_directory)
endfunction

function! s:show_switch_target_popup(prompt, items, current_target, preset_value, build_directory, scan_directory) abort
  let l:state = {
        \ 'prompt': a:prompt,
        \ 'all_items': copy(a:items),
        \ 'filtered_items': copy(a:items),
        \ 'query': '',
        \ 'current_target': a:current_target,
        \ 'preset_value': a:preset_value,
        \ 'build_directory': a:build_directory,
        \ 'scan_directory': a:scan_directory
        \ }
  if exists('g:vim_cmake_naive_test_popup_menu_response')
    let l:test_response = g:vim_cmake_naive_test_popup_menu_response
    let l:test_result = l:test_response
    if type(l:test_response) == v:t_dict
      let l:state.query = s:to_string_or_empty(get(l:test_response, 'query', ''))
      let l:test_result = get(l:test_response, 'result', 0)
    endif
    let l:state.filtered_items = s:filter_switch_target_popup_items(l:state.all_items, l:state.query)
    let l:display_items = s:switch_target_popup_display_items(l:state.filtered_items, l:state.current_target)
    let l:popup_options = s:switch_target_popup_options(a:prompt, l:display_items, l:state.query)
    let g:vim_cmake_naive_test_last_target_popup_items = copy(l:display_items)
    let g:vim_cmake_naive_test_last_target_popup_options = copy(l:popup_options)
    call s:apply_switch_target_popup_selection(l:state, l:test_result)
    return
  endif

  let l:display_items = s:switch_target_popup_display_items(l:state.filtered_items, l:state.current_target)
  let l:popup_options = s:switch_target_popup_options(a:prompt, l:display_items, l:state.query)
  let l:popup_id = popup_menu(l:display_items, l:popup_options)
  if type(l:popup_id) == v:t_number && l:popup_id > 0
    let s:switch_target_popup_states[l:popup_id] = l:state
  endif
endfunction

function! s:switch_target_popup_options(prompt, display_items, query) abort
  let l:popup_options = s:switch_popup_options(
        \ s:switch_target_popup_title(a:prompt, a:query),
        \ a:display_items)
  let l:popup_options.callback = function('s:on_switch_target_popup_selection')
  let l:popup_options.filter = function('s:on_switch_target_popup_filter')
  return l:popup_options
endfunction

function! s:switch_target_popup_title(prompt, query) abort
  let l:query = s:to_string_or_empty(a:query)
  return empty(l:query) ? a:prompt : a:prompt . ' [' . l:query . ']'
endfunction

function! s:switch_target_popup_display_items(items, current_target) abort
  if empty(a:items)
    return ['1.   no matches']
  endif

  return s:preset_popup_display_items(
        \ a:items,
        \ a:current_target,
        \ {s:cmake_switch_target_all_name: '(' . s:cmake_switch_target_all_name . ')'})
endfunction

function! s:filter_switch_target_popup_items(items, query) abort
  let l:query = tolower(s:to_string_or_empty(a:query))
  if empty(l:query)
    return copy(a:items)
  endif

  let l:filtered_items = []
  for l:item in a:items
    if stridx(tolower(l:item), l:query) >= 0
      call add(l:filtered_items, l:item)
    endif
  endfor

  return l:filtered_items
endfunction

function! s:is_switch_target_popup_text_key(key) abort
  return strchars(a:key) == 1 && char2nr(a:key) >= 32
endfunction

function! s:is_switch_target_popup_backspace_key(key) abort
  return a:key ==# "\<BS>" || a:key ==# "\<C-H>" || a:key ==# "\<Del>" || a:key ==# "\<kDel>"
endfunction

function! s:on_switch_target_popup_filter(popup_id, key) abort
  if !has_key(s:switch_target_popup_states, a:popup_id)
    return popup_filter_menu(a:popup_id, a:key)
  endif

  let l:state = s:switch_target_popup_states[a:popup_id]
  if s:is_switch_target_popup_text_key(a:key)
    let l:state.query .= a:key
    call s:refresh_switch_target_popup(a:popup_id)
    return 1
  endif

  if s:is_switch_target_popup_backspace_key(a:key)
    let l:query_length = strchars(l:state.query)
    if l:query_length > 0
      let l:state.query = strcharpart(l:state.query, 0, l:query_length - 1)
      call s:refresh_switch_target_popup(a:popup_id)
    endif
    return 1
  endif

  if a:key ==# "\<C-U>"
    if !empty(l:state.query)
      let l:state.query = ''
      call s:refresh_switch_target_popup(a:popup_id)
    endif
    return 1
  endif

  return popup_filter_menu(a:popup_id, a:key)
endfunction

function! s:refresh_switch_target_popup(popup_id) abort
  let l:state = get(s:switch_target_popup_states, a:popup_id, {})
  if empty(l:state)
    return
  endif

  let l:state.filtered_items = s:filter_switch_target_popup_items(l:state.all_items, l:state.query)
  let l:display_items = s:switch_target_popup_display_items(l:state.filtered_items, l:state.current_target)
  let l:popup_options = s:switch_target_popup_options(l:state.prompt, l:display_items, l:state.query)
  call popup_settext(a:popup_id, l:display_items)
  call popup_setoptions(a:popup_id, {
        \ 'title': l:popup_options.title,
        \ 'minheight': l:popup_options.minheight,
        \ 'maxheight': l:popup_options.maxheight
        \ })
endfunction

function! s:on_switch_target_popup_selection(popup_id, result) abort
  if has_key(s:switch_target_popup_states, a:popup_id)
    let l:state = s:switch_target_popup_states[a:popup_id]
    call remove(s:switch_target_popup_states, a:popup_id)
  else
    let l:state = {}
  endif
  call s:apply_switch_target_popup_selection(l:state, a:result)
endfunction

function! s:apply_switch_target_popup_selection(state, result) abort
  let l:items = get(a:state, 'filtered_items', [])
  let l:index = type(a:result) == v:t_number
        \ ? a:result
        \ : str2nr(s:to_string_or_empty(a:result))
  if l:index <= 0 || l:index > len(l:items)
    call s:write_info('Target selection canceled.')
    return
  endif

  let l:selected_target = l:items[l:index - 1]
  try
    call s:apply_switch_target_selection(
          \ l:selected_target,
          \ get(a:state, 'preset_value', ''),
          \ get(a:state, 'build_directory', ''),
          \ get(a:state, 'scan_directory', ''))
  catch
    call s:write_error(s:format_exception(v:exception))
  endtry
endfunction

function! s:apply_switch_target_selection(selected_target, preset_value, build_directory, scan_directory) abort
  if a:selected_target ==# s:cmake_switch_target_all_name
    let l:root_compile_commands_path = s:resolve_root_compile_commands_path(
          \ a:build_directory,
          \ a:scan_directory,
          \ a:preset_value)
    call s:copy_compile_commands_file(l:root_compile_commands_path, a:build_directory)
    call s:remove_config_value(s:cmake_config_target_key, 1)
    return
  endif

  let l:target_directory = s:resolve_selected_target_directory(a:selected_target, a:scan_directory)
  let l:source_file_path = s:path_join(l:target_directory, s:default_input_filename)
  call s:copy_compile_commands_file(l:source_file_path, a:build_directory)
  call s:set_config_value(s:cmake_config_target_key, a:selected_target, 1)
endfunction

function! s:cached_targets_for_switch(config_path) abort
  if empty(trim(a:config_path))
    throw 'Config path cannot be empty.'
  endif

  let l:cache_path = s:cmake_cache_path(a:config_path)
  if !filereadable(l:cache_path)
    throw s:cmake_switch_target_missing_cache_error
  endif

  let l:cache_payload = s:read_json_object(l:cache_path)
  let l:targets = get(l:cache_payload, 'targets', [])
  if type(l:targets) != v:t_list
    throw 'Cache file ''' . l:cache_path . ''' key "targets" must be a JSON array.'
  endif

  let l:result = []
  let l:seen = {}
  for l:target in l:targets
    let l:target_name = trim(s:to_string_or_empty(l:target))
    if empty(l:target_name) || has_key(l:seen, l:target_name)
      continue
    endif

    let l:seen[l:target_name] = 1
    call add(l:result, l:target_name)
  endfor

  call sort(l:result)
  return l:result
endfunction

function! s:available_targets(scan_directory, root_compile_commands_path) abort
  if empty(trim(a:scan_directory))
    throw 'Build directory cannot be empty.'
  endif
  if empty(trim(a:root_compile_commands_path))
    throw 'Root compile_commands path cannot be empty.'
  endif

  let l:entries = s:read_json_array(a:root_compile_commands_path)
  let l:root_compile_commands_directory = s:normalize_full_path(fnamemodify(a:root_compile_commands_path, ':h'))
  let l:targets = []
  let l:seen = {}

  for l:entry in l:entries
    if type(l:entry) != v:t_dict
      continue
    endif

    let l:working_directory = s:resolve_working_directory(
          \ s:to_string_or_empty(get(l:entry, 'directory', '')),
          \ l:root_compile_commands_directory)
    let l:target_directory = s:infer_target_directory(
          \ a:scan_directory,
          \ l:working_directory,
          \ s:to_string_or_empty(get(l:entry, 'output', '')),
          \ get(l:entry, 'arguments', v:null),
          \ s:to_string_or_empty(get(l:entry, 'command', '')))
    if empty(l:target_directory)
      continue
    endif

    let l:target_name = s:target_name_from_directory(l:target_directory, a:scan_directory)
    if empty(l:target_name)
      continue
    endif

    if has_key(l:seen, l:target_name)
      continue
    endif

    let l:seen[l:target_name] = 1
    call add(l:targets, l:target_name)
  endfor

  call sort(l:targets)
  return l:targets
endfunction

function! s:target_name_from_directory(target_directory, scan_directory) abort
  let l:normalized_target_directory = s:normalize_full_path(a:target_directory)
  if !s:is_sub_path_of(l:normalized_target_directory, a:scan_directory)
    return ''
  endif

  let l:relative_target_directory = substitute(
        \ s:relative_path(l:normalized_target_directory, a:scan_directory),
        \ '\\',
        \ '/',
        \ 'g')
  if l:relative_target_directory =~# '\v(^|/)_deps(/|$)'
    return ''
  endif
  if l:relative_target_directory !~# '\v(^|/)CMakeFiles/[^/]+\.dir$'
    return ''
  endif

  return substitute(fnamemodify(l:relative_target_directory, ':t'), '\.dir$', '', '')
endfunction

function! s:target_scan_directory(build_directory, preset_value) abort
  if empty(trim(a:build_directory))
    throw 'Build directory cannot be empty.'
  endif

  let l:preset_value = trim(s:to_string_or_empty(a:preset_value))
  if empty(l:preset_value)
    return a:build_directory
  endif

  return s:resolve_path(l:preset_value, a:build_directory)
endfunction

function! s:resolve_selected_target_directory(target_name, scan_directory) abort
  if empty(trim(a:target_name))
    throw 'Missing required argument: <target>.'
  endif
  if empty(trim(a:scan_directory))
    throw 'Build directory cannot be empty.'
  endif

  let l:direct_directory = s:path_join(
        \ s:path_join(a:scan_directory, 'CMakeFiles'),
        \ a:target_name . '.dir')
  let l:direct_directory = s:normalize_full_path(l:direct_directory)
  if isdirectory(l:direct_directory)
    return l:direct_directory
  endif

  let l:glob_pattern = s:path_join(
        \ s:path_join(s:path_join(a:scan_directory, '**'), 'CMakeFiles'),
        \ a:target_name . '.dir')
  let l:matches = glob(l:glob_pattern, 0, 1)
  let l:directories = []
  let l:seen = {}

  for l:match in l:matches
    if !isdirectory(l:match)
      continue
    endif

    let l:normalized_match = s:normalize_full_path(l:match)
    if !s:is_sub_path_of(l:normalized_match, a:scan_directory) || has_key(l:seen, l:normalized_match)
      continue
    endif

    let l:seen[l:normalized_match] = 1
    call add(l:directories, l:normalized_match)
  endfor

  if empty(l:directories)
    throw 'target directory not found for ''' . a:target_name . ''': ' . l:direct_directory
  endif

  call sort(l:directories)
  if len(l:directories) > 1
    let l:relative_directories = []
    for l:directory in l:directories
      call add(l:relative_directories, s:relative_path(l:directory, a:scan_directory))
    endfor
    throw 'Multiple target directories found for ''' . a:target_name . ''' under '
          \ . a:scan_directory . ': ' . join(l:relative_directories, ', ')
  endif

  return l:directories[0]
endfunction

function! s:resolve_root_compile_commands_path(build_directory, scan_directory, preset_value) abort
  if empty(trim(a:build_directory))
    throw 'Build directory cannot be empty.'
  endif
  if empty(trim(a:scan_directory))
    throw 'Build directory cannot be empty.'
  endif

  let l:candidate = s:normalize_full_path(s:path_join(a:scan_directory, s:default_input_filename))
  if filereadable(l:candidate)
    return l:candidate
  endif

  throw 'Root ' . s:default_input_filename . ' not found at: ' . l:candidate
endfunction

function! s:ensure_target_compile_commands(target_name, target_directory, preset_value, build_directory, scan_directory) abort
  if empty(trim(a:target_name))
    throw 'Missing required argument: <target>.'
  endif
  if empty(trim(a:target_directory))
    throw 'Target directory cannot be empty.'
  endif
  let l:preset_value = trim(s:to_string_or_empty(a:preset_value))
  if empty(trim(a:build_directory))
    throw 'Build directory cannot be empty.'
  endif
  if empty(trim(a:scan_directory))
    throw 'Build directory cannot be empty.'
  endif

  let l:source_file_path = s:path_join(a:target_directory, s:default_input_filename)
  if filereadable(l:source_file_path)
    return l:source_file_path
  endif

  let l:root_compile_commands_path = s:resolve_root_compile_commands_path(
        \ a:build_directory,
        \ a:scan_directory,
        \ l:preset_value)
  let l:split_build_directory = s:normalize_full_path(fnamemodify(l:root_compile_commands_path, ':h'))
  call s:write_info(
        \ 'Target ' . s:default_input_filename . ' is missing for '
        \ . s:relative_path(a:target_directory, a:scan_directory)
        \ . '. Splitting root file: '
        \ . s:relative_path(l:root_compile_commands_path, l:split_build_directory))

  call s:run_split({
        \ 'build_directory': l:split_build_directory,
        \ 'input_path': l:root_compile_commands_path,
        \ 'output_name': s:default_output_filename,
        \ 'dry_run': 0
        \ })

  if !filereadable(l:source_file_path)
    let l:fallback_source_file_path = s:find_target_compile_commands_file(a:target_name, a:build_directory)
    if !empty(l:fallback_source_file_path)
      return l:fallback_source_file_path
    endif

    throw 'Source file not found: ' . l:source_file_path
  endif

  return l:source_file_path
endfunction

function! s:find_target_compile_commands_file(target_name, build_directory) abort
  if empty(trim(a:target_name))
    throw 'Missing required argument: <target>.'
  endif
  if empty(trim(a:build_directory))
    throw 'Build directory cannot be empty.'
  endif

  let l:glob_pattern = s:path_join(
        \ s:path_join(
        \   s:path_join(s:path_join(a:build_directory, '**'), 'CMakeFiles'),
        \   a:target_name . '.dir'),
        \ s:default_input_filename)
  let l:matches = glob(l:glob_pattern, 0, 1)
  let l:file_matches = []
  let l:seen = {}

  for l:match in l:matches
    if !filereadable(l:match)
      continue
    endif

    let l:normalized_match = s:normalize_full_path(l:match)
    if !s:is_sub_path_of(l:normalized_match, a:build_directory) || has_key(l:seen, l:normalized_match)
      continue
    endif

    let l:seen[l:normalized_match] = 1
    call add(l:file_matches, l:normalized_match)
  endfor

  if empty(l:file_matches)
    return ''
  endif

  call sort(l:file_matches)
  if len(l:file_matches) > 1
    let l:relative_matches = []
    for l:file_path in l:file_matches
      call add(l:relative_matches, s:relative_path(l:file_path, a:build_directory))
    endfor
    throw 'Multiple source files found for target ''' . a:target_name . ''' under '
          \ . a:build_directory . ': ' . join(l:relative_matches, ', ')
  endif

  return l:file_matches[0]
endfunction

function! s:copy_compile_commands_file(source_file_path, output_directory) abort
  if empty(trim(a:source_file_path))
    throw 'Source file path cannot be empty.'
  endif
  if empty(trim(a:output_directory))
    throw 'Output directory cannot be empty.'
  endif
  if !filereadable(a:source_file_path)
    throw 'Source file not found: ' . a:source_file_path
  endif

  call mkdir(a:output_directory, 'p')
  let l:destination_file_path = s:path_join(a:output_directory, s:default_input_filename)
  call writefile(readfile(a:source_file_path, 'b'), l:destination_file_path, 'b')

  call s:write_info('Copied ' . s:default_input_filename . ' to ' . l:destination_file_path)
endfunction

function! s:available_configure_presets(presets_payload, project_root) abort
  let l:configure_presets = get(a:presets_payload, 'configurePresets', [])
  if type(l:configure_presets) != v:t_list
    throw s:cmake_presets_filename . ' key "configurePresets" must be a JSON array.'
  endif

  let l:preset_map = {}
  for l:preset in l:configure_presets
    if type(l:preset) != v:t_dict
      continue
    endif

    let l:name = trim(s:to_string_or_empty(get(l:preset, 'name', '')))
    if empty(l:name)
      continue
    endif

    let l:preset_map[l:name] = l:preset
  endfor

  let l:context = s:cmake_condition_context(a:project_root)
  let l:available = []
  let l:seen = {}
  for l:preset in l:configure_presets
    if type(l:preset) != v:t_dict
      continue
    endif

    let l:name = trim(s:to_string_or_empty(get(l:preset, 'name', '')))
    if empty(l:name) || has_key(l:seen, l:name)
      continue
    endif

    if s:preset_is_hidden(l:preset)
      continue
    endif

    if !s:configure_preset_condition_passes(l:name, l:preset_map, l:context, {})
      continue
    endif

    let l:seen[l:name] = 1
    call add(l:available, l:name)
  endfor

  return l:available
endfunction

function! s:configure_preset_condition_passes(preset_name, preset_map, context, stack) abort
  if !has_key(a:preset_map, a:preset_name)
    throw 'Configure preset "' . a:preset_name . '" not found.'
  endif

  if has_key(a:stack, a:preset_name)
    throw 'CMake preset inheritance cycle detected at "' . a:preset_name . '".'
  endif

  let l:preset = a:preset_map[a:preset_name]
  let l:stack = copy(a:stack)
  let l:stack[a:preset_name] = 1

  for l:parent_name in s:preset_inherits_list(l:preset)
    if !has_key(a:preset_map, l:parent_name)
      throw 'Configure preset "' . a:preset_name . '" inherits missing preset "' . l:parent_name . '".'
    endif

    if !s:configure_preset_condition_passes(l:parent_name, a:preset_map, a:context, l:stack)
      return 0
    endif
  endfor

  if !has_key(l:preset, 'condition')
    return 1
  endif

  return s:evaluate_preset_condition(l:preset.condition, a:context, a:preset_name)
endfunction

function! s:preset_inherits_list(preset) abort
  let l:inherits = get(a:preset, 'inherits', [])
  if type(l:inherits) == v:t_string
    let l:name = trim(l:inherits)
    return empty(l:name) ? [] : [l:name]
  endif

  if type(l:inherits) != v:t_list
    return []
  endif

  let l:parent_names = []
  for l:item in l:inherits
    let l:name = trim(s:to_string_or_empty(l:item))
    if !empty(l:name)
      call add(l:parent_names, l:name)
    endif
  endfor

  return l:parent_names
endfunction

function! s:preset_is_hidden(preset) abort
  if !has_key(a:preset, 'hidden')
    return 0
  endif

  return s:as_condition_bool(a:preset.hidden)
endfunction

function! s:cmake_condition_context(project_root) abort
  let l:source_dir = s:normalize_full_path(a:project_root)
  let l:source_parent_dir = s:trim_path(fnamemodify(l:source_dir, ':h'))
  return {
        \ 'sourceDir': l:source_dir,
        \ 'sourceParentDir': l:source_parent_dir,
        \ 'sourceDirName': fnamemodify(l:source_dir, ':t'),
        \ 'hostSystemName': s:host_system_name()
        \ }
endfunction

function! s:host_system_name() abort
  if s:is_windows
    return 'Windows'
  endif

  if has('mac') || has('macunix')
    return 'Darwin'
  endif

  return has('unix') ? 'Linux' : ''
endfunction

function! s:evaluate_preset_condition(condition, context, preset_name) abort
  if a:condition is v:null
    return 1
  endif

  if type(a:condition) == v:t_number
    return a:condition != 0
  endif

  if exists('v:t_bool') && type(a:condition) == v:t_bool
    return a:condition == v:true
  endif

  if type(a:condition) == v:t_string
    return s:as_condition_bool(s:expand_condition_string(a:condition, a:context, a:preset_name))
  endif

  if type(a:condition) != v:t_dict
    throw 'Unsupported preset condition value type.'
  endif

  let l:condition_type = tolower(trim(s:to_string_or_empty(get(a:condition, 'type', ''))))
  if empty(l:condition_type)
    throw 'Preset condition object is missing required key "type".'
  endif

  if l:condition_type ==# 'const'
    return s:as_condition_bool(get(a:condition, 'value', 0))
  endif

  if l:condition_type ==# 'equals'
    return s:condition_string_value(get(a:condition, 'lhs', ''), a:context, a:preset_name)
          \ ==# s:condition_string_value(get(a:condition, 'rhs', ''), a:context, a:preset_name)
  endif

  if l:condition_type ==# 'notequals'
    return s:condition_string_value(get(a:condition, 'lhs', ''), a:context, a:preset_name)
          \ !=# s:condition_string_value(get(a:condition, 'rhs', ''), a:context, a:preset_name)
  endif

  if l:condition_type ==# 'inlist' || l:condition_type ==# 'notinlist'
    let l:needle = s:condition_string_value(get(a:condition, 'string', ''), a:context, a:preset_name)
    let l:list_values = s:condition_list_values(get(a:condition, 'list', []), a:context, a:preset_name)
    let l:contains = index(l:list_values, l:needle) >= 0
    return l:condition_type ==# 'inlist' ? l:contains : !l:contains
  endif

  if l:condition_type ==# 'matches' || l:condition_type ==# 'notmatches'
    let l:value = s:condition_string_value(get(a:condition, 'string', ''), a:context, a:preset_name)
    let l:regex = s:condition_string_value(get(a:condition, 'regex', ''), a:context, a:preset_name)
    let l:matches = 0
    try
      let l:matches = l:value =~# l:regex
    catch
      throw 'Invalid regex in preset condition: ' . l:regex
    endtry
    return l:condition_type ==# 'matches' ? l:matches : !l:matches
  endif

  if l:condition_type ==# 'anyof' || l:condition_type ==# 'allof'
    let l:conditions = get(a:condition, 'conditions', [])
    if type(l:conditions) != v:t_list
      throw 'Preset condition "' . l:condition_type . '" requires list key "conditions".'
    endif

    let l:is_any = l:condition_type ==# 'anyof'
    if empty(l:conditions)
      return l:is_any ? 0 : 1
    endif

    for l:item in l:conditions
      let l:passed = s:evaluate_preset_condition(l:item, a:context, a:preset_name)
      if l:is_any && l:passed
        return 1
      endif
      if !l:is_any && !l:passed
        return 0
      endif
    endfor

    return l:is_any ? 0 : 1
  endif

  if l:condition_type ==# 'not'
    if !has_key(a:condition, 'condition')
      throw 'Preset condition "not" requires key "condition".'
    endif
    return !s:evaluate_preset_condition(a:condition.condition, a:context, a:preset_name)
  endif

  throw 'Unsupported preset condition type "' . l:condition_type . '".'
endfunction

function! s:condition_string_value(value, context, preset_name) abort
  return s:expand_condition_string(s:to_string_or_empty(a:value), a:context, a:preset_name)
endfunction

function! s:condition_list_values(values, context, preset_name) abort
  if type(a:values) != v:t_list
    return []
  endif

  let l:result = []
  for l:item in a:values
    call add(l:result, s:condition_string_value(l:item, a:context, a:preset_name))
  endfor
  return l:result
endfunction

function! s:expand_condition_string(value, context, preset_name) abort
  let l:expanded = s:to_string_or_empty(a:value)
  if empty(l:expanded)
    return ''
  endif

  let l:expanded = substitute(
        \ l:expanded,
        \ '\${\([^}]\+\)}',
        \ '\=s:expand_braced_macro(submatch(1), a:context, a:preset_name)',
        \ 'g')
  let l:expanded = substitute(
        \ l:expanded,
        \ '\$env{\([^}]\+\)}',
        \ '\=s:expand_env_macro(submatch(1))',
        \ 'g')
  let l:expanded = substitute(
        \ l:expanded,
        \ '\$penv{\([^}]\+\)}',
        \ '\=s:expand_env_macro(submatch(1))',
        \ 'g')

  return l:expanded
endfunction

function! s:expand_braced_macro(name, context, preset_name) abort
  let l:name = trim(s:to_string_or_empty(a:name))
  if l:name ==# 'presetName'
    return a:preset_name
  endif

  return s:to_string_or_empty(get(a:context, l:name, ''))
endfunction

function! s:expand_env_macro(name) abort
  let l:name = trim(s:to_string_or_empty(a:name))
  return empty(l:name) ? '' : s:to_string_or_empty(get(environ(), l:name, ''))
endfunction

function! s:as_condition_bool(value) abort
  if type(a:value) == v:t_number
    return a:value != 0
  endif

  if exists('v:t_bool') && type(a:value) == v:t_bool
    return a:value == v:true
  endif

  if type(a:value) == v:t_string
    let l:normalized = tolower(trim(a:value))
    return !(empty(l:normalized) || l:normalized ==# '0' || l:normalized ==# 'false' || l:normalized ==# 'off' || l:normalized ==# 'no')
  endif

  return 0
endfunction

function! s:select_item_from_list(prompt, items) abort
  if empty(a:items)
    return ''
  endif

  let l:selected_index = s:inputlist_selection(a:prompt, a:items)
  let l:index = type(l:selected_index) == v:t_number
        \ ? l:selected_index
        \ : str2nr(s:to_string_or_empty(l:selected_index))
  if l:index <= 0 || l:index > len(a:items)
    return ''
  endif

  return a:items[l:index - 1]
endfunction

function! s:select_item_from_menu(prompt, items) abort
  if empty(a:items)
    return ''
  endif

  let l:selected_index = s:menu_selection(a:prompt, a:items)
  let l:index = type(l:selected_index) == v:t_number
        \ ? l:selected_index
        \ : str2nr(s:to_string_or_empty(l:selected_index))
  if l:index <= 0 || l:index > len(a:items)
    return ''
  endif

  return a:items[l:index - 1]
endfunction

function! s:menu_selection(prompt, items) abort
  if exists('g:vim_cmake_naive_test_menu_response')
    return g:vim_cmake_naive_test_menu_response
  endif

  if exists('g:vim_cmake_naive_test_inputlist_response')
    return g:vim_cmake_naive_test_inputlist_response
  endif

  if exists('*confirm')
    let l:choices = map(copy(a:items), 'substitute(v:val, "&", "&&", "g")')
    return confirm(a:prompt, join(l:choices, "\n"), 0)
  endif

  return s:inputlist_selection(a:prompt, a:items)
endfunction

function! s:inputlist_selection(prompt, items) abort
  if exists('g:vim_cmake_naive_test_inputlist_response')
    return g:vim_cmake_naive_test_inputlist_response
  endif

  let l:lines = [a:prompt]
  let l:index = 0
  while l:index < len(a:items)
    call add(l:lines, (l:index + 1) . '. ' . a:items[l:index])
    let l:index += 1
  endwhile

  return inputlist(l:lines)
endfunction

function! s:run_cmake_config_default() abort
  let l:project_root = s:resolve_cmake_project_root(getcwd())
  let l:config_path = s:cmake_config_path(l:project_root)
  let l:config = filereadable(l:config_path)
        \ ? s:read_json_object(l:config_path)
        \ : s:default_cmake_config_payload()

  call s:apply_default_cmake_config_values(l:config)

  call mkdir(fnamemodify(l:config_path, ':h'), 'p')
  call s:write_json_file(l:config_path, l:config)
  call s:sync_environment_from_config(l:config)

  call s:write_info('Applied default config in ' . s:relative_path(l:config_path, l:project_root))
endfunction

function! s:run_generate() abort
  let l:working_directory = s:normalize_full_path(getcwd())
  let l:project_root = s:resolve_cmake_project_root(l:working_directory)
  let l:config_path = s:resolve_or_create_local_config_for_generate(l:working_directory, l:project_root)
  let l:config = s:read_json_object(l:config_path)

  let l:output_value = s:to_string_or_empty(get(l:config, s:cmake_config_output_key, s:cmake_config_default_output))
  if empty(trim(l:output_value))
    let l:output_value = s:cmake_config_default_output
  endif

  let l:build_value = s:to_string_or_empty(get(l:config, s:cmake_config_build_config_key, s:cmake_config_default_build))
  if empty(trim(l:build_value))
    let l:build_value = s:cmake_config_default_build
  endif

  let l:preset_value = trim(s:to_string_or_empty(get(l:config, s:cmake_config_preset_key, '')))
  let l:build_directory = s:resolve_path(l:output_value, l:project_root)
  let l:preset_output_directory = s:generate_preset_output_directory(l:build_directory, l:preset_value)
  let l:generation_directory = empty(l:preset_value) ? l:build_directory : l:preset_output_directory
  call mkdir(l:build_directory, 'p')
  if !empty(l:preset_output_directory)
    call mkdir(l:preset_output_directory, 'p')
  endif

  let l:argv = [
        \ 'cmake',
        \ '-S',
        \ l:project_root,
        \ '-B',
        \ l:generation_directory,
        \ '--fresh',
        \ '-DCMAKE_BUILD_TYPE=' . l:build_value
        \ ]

  if !empty(l:preset_value)
    call add(l:argv, '--preset')
    call add(l:argv, l:preset_value)
  endif

  let l:generate_terminal_name = s:cmake_generate_terminal_running_name(l:preset_value)
  let l:generate_completion_context = {
        \ 'config_path': l:config_path,
        \ 'project_root': l:project_root,
        \ 'build_directory': l:build_directory,
        \ 'scan_directory': l:generation_directory
        \ }
  call s:run_build_command_in_vertical_terminal(l:argv, {
        \ 'reuse_previous_build_window': 1,
        \ 'split_orientation': 'horizontal',
        \ 'terminal_name': l:generate_terminal_name,
        \ 'success_terminal_name': 'Success',
        \ 'failure_terminal_name_prefix': 'Failure',
        \ 'on_success_callback': function('s:on_generate_command_success', [copy(l:generate_completion_context)])
        \ })
  call s:write_info('Started generate in ' . s:relative_path(l:generation_directory, l:project_root))
endfunction

function! s:on_generate_command_success(context) abort
  try
    call s:update_generate_targets_cache_and_split(a:context)
  catch
    call s:write_error(s:format_exception(v:exception))
  endtry
endfunction

function! s:update_generate_targets_cache_and_split(context) abort
  if type(a:context) != v:t_dict
    throw 'Generate completion context must be a JSON object.'
  endif

  let l:config_path = s:to_string_or_empty(get(a:context, 'config_path', ''))
  let l:project_root = s:to_string_or_empty(get(a:context, 'project_root', ''))
  let l:build_directory = s:to_string_or_empty(get(a:context, 'build_directory', ''))
  let l:scan_directory = s:to_string_or_empty(get(a:context, 'scan_directory', ''))
  if empty(trim(l:config_path))
    throw 'Config path cannot be empty.'
  endif
  if empty(trim(l:build_directory))
    throw 'Build directory cannot be empty.'
  endif
  if empty(trim(l:scan_directory))
    throw 'Build directory cannot be empty.'
  endif

  let l:root_compile_commands_path = s:resolve_root_compile_commands_path(
        \ l:build_directory,
        \ l:scan_directory,
        \ '')
  let l:targets = s:available_targets(l:scan_directory, l:root_compile_commands_path)
  let l:cache_path = s:update_local_targets_cache(l:config_path, l:targets)
  call s:run_split({
        \ 'build_directory': l:scan_directory,
        \ 'input_path': l:root_compile_commands_path,
        \ 'output_name': s:default_output_filename,
        \ 'dry_run': 0
        \ })

  if !empty(l:project_root)
    call s:write_info('Updated target cache in ' . s:relative_path(l:cache_path, l:project_root))
  else
    call s:write_info('Updated target cache in ' . l:cache_path)
  endif
endfunction

function! s:update_local_targets_cache(config_path, targets) abort
  if empty(trim(a:config_path))
    throw 'Config path cannot be empty.'
  endif
  if type(a:targets) != v:t_list
    throw 'Targets value must be a JSON array.'
  endif

  let l:cache_path = s:cmake_cache_path(a:config_path)
  let l:cache_payload = filereadable(l:cache_path)
        \ ? s:read_json_object(l:cache_path)
        \ : {}
  let l:cache_payload.targets = copy(a:targets)
  call mkdir(fnamemodify(l:cache_path, ':h'), 'p')
  call s:write_json_file(l:cache_path, l:cache_payload)

  return l:cache_path
endfunction

function! s:run_build() abort
  let l:working_directory = s:normalize_full_path(getcwd())
  let l:project_root = s:resolve_cmake_project_root(l:working_directory)
  let l:config_path = s:resolve_or_create_local_config_for_generate(l:working_directory, l:project_root)
  let l:config = s:read_json_object(l:config_path)

  let l:output_value = s:to_string_or_empty(get(l:config, s:cmake_config_output_key, s:cmake_config_default_output))
  if empty(trim(l:output_value))
    let l:output_value = s:cmake_config_default_output
  endif

  let l:preset_value = trim(s:to_string_or_empty(get(l:config, s:cmake_config_preset_key, '')))
  let l:build_directory = s:resolve_path(l:output_value, l:project_root)
  let l:preset_output_directory = s:generate_preset_output_directory(l:build_directory, l:preset_value)
  let l:build_target_directory = empty(l:preset_output_directory) ? l:build_directory : l:preset_output_directory
  let l:target_value = trim(s:to_string_or_empty(get(l:config, s:cmake_config_target_key, '')))
  let l:parallel_level = s:available_core_count()

  let l:argv = ['cmake', '--build', l:build_target_directory, '--parallel', string(l:parallel_level)]
  if !empty(l:preset_value)
    call add(l:argv, '--preset')
    call add(l:argv, l:preset_value)
  endif

  if !empty(l:target_value)
    call add(l:argv, '--target')
    call add(l:argv, l:target_value)
  endif

  let l:build_terminal_name = s:cmake_build_terminal_running_name(l:preset_value, l:target_value)
  call s:run_build_command_in_vertical_terminal(l:argv, {
        \ 'reuse_previous_build_window': 1,
        \ 'split_orientation': 'horizontal',
        \ 'terminal_name': l:build_terminal_name,
        \ 'success_terminal_name': 'Success',
        \ 'failure_terminal_name_prefix': 'Failure'
        \ })
  call s:write_info('Started build in ' . s:relative_path(l:build_target_directory, l:project_root))
endfunction

function! s:read_first_line_from_command(argv) abort
  let l:command_name = trim(s:to_string_or_empty(get(a:argv, 0, '')))
  if empty(l:command_name) || !executable(l:command_name)
    return ''
  endif

  let l:escaped_arguments = map(copy(a:argv), 'shellescape(v:val)')
  let l:output = systemlist(join(l:escaped_arguments, ' '))
  if v:shell_error != 0 || empty(l:output)
    return ''
  endif

  return trim(s:to_string_or_empty(get(l:output, 0, '')))
endfunction

function! s:available_core_count() abort
  let l:environment_value = exists('$NUMBER_OF_PROCESSORS') ? $NUMBER_OF_PROCESSORS : ''
  let l:environment_count = str2nr(trim(s:to_string_or_empty(l:environment_value)))
  if l:environment_count > 0
    return l:environment_count
  endif

  let l:command_candidates = has('macunix')
        \ ? [['sysctl', '-n', 'hw.logicalcpu'], ['sysctl', '-n', 'hw.ncpu']]
        \ : [['nproc'], ['getconf', '_NPROCESSORS_ONLN']]

  for l:candidate in l:command_candidates
    let l:detected_count = str2nr(s:read_first_line_from_command(l:candidate))
    if l:detected_count > 0
      return l:detected_count
    endif
  endfor

  return 1
endfunction

function! s:run_test() abort
  let l:working_directory = s:normalize_full_path(getcwd())
  let l:project_root = s:resolve_cmake_project_root(l:working_directory)
  let l:config_path = s:resolve_or_create_local_config_for_generate(l:working_directory, l:project_root)
  let l:config = s:read_json_object(l:config_path)

  let l:output_value = s:to_string_or_empty(get(l:config, s:cmake_config_output_key, s:cmake_config_default_output))
  if empty(trim(l:output_value))
    let l:output_value = s:cmake_config_default_output
  endif

  let l:preset_value = trim(s:to_string_or_empty(get(l:config, s:cmake_config_preset_key, '')))
  let l:build_directory = s:resolve_path(l:output_value, l:project_root)
  let l:preset_output_directory = s:generate_preset_output_directory(l:build_directory, l:preset_value)
  let l:test_directory = empty(l:preset_output_directory) ? l:build_directory : l:preset_output_directory
  call mkdir(l:test_directory, 'p')

  let l:parallel_level = s:available_core_count()
  let l:argv = ['ctest', '--parallel', string(l:parallel_level)]
  let l:test_terminal_name = s:cmake_test_terminal_running_name(l:preset_value)
  call s:run_build_command_in_vertical_terminal(l:argv, {
        \ 'reuse_previous_build_window': 1,
        \ 'split_orientation': 'horizontal',
        \ 'terminal_name': l:test_terminal_name,
        \ 'success_terminal_name': 'Success',
        \ 'failure_terminal_name_prefix': 'Failure',
        \ 'working_directory': l:test_directory
        \ })
  call s:write_info('Started tests in ' . s:relative_path(l:test_directory, l:project_root))
endfunction

function! s:run_run() abort
  let l:working_directory = s:normalize_full_path(getcwd())
  let l:project_root = s:resolve_cmake_project_root(l:working_directory)
  let l:config_path = s:resolve_or_create_local_config_for_generate(l:working_directory, l:project_root)
  let l:config = s:read_json_object(l:config_path)

  let l:output_value = s:to_string_or_empty(get(l:config, s:cmake_config_output_key, s:cmake_config_default_output))
  if empty(trim(l:output_value))
    let l:output_value = s:cmake_config_default_output
  endif

  let l:preset_value = trim(s:to_string_or_empty(get(l:config, s:cmake_config_preset_key, '')))
  let l:build_value = trim(s:to_string_or_empty(get(l:config, s:cmake_config_build_config_key, '')))
  let l:target_value = trim(s:to_string_or_empty(get(l:config, s:cmake_config_target_key, '')))
  if empty(l:target_value)
    throw s:cmake_run_missing_target_error
  endif

  let l:build_directory = s:resolve_path(l:output_value, l:project_root)
  let l:preset_output_directory = s:generate_preset_output_directory(l:build_directory, l:preset_value)
  let l:run_directory = empty(l:preset_output_directory) ? l:build_directory : l:preset_output_directory
  if !isdirectory(l:run_directory)
    throw 'Build directory not found: ' . l:run_directory
  endif

  let l:target_executable = s:resolve_target_executable_path(l:target_value, l:run_directory, l:build_value)
  let l:argv = [l:target_executable]
  let l:run_terminal_name = s:cmake_run_terminal_running_name(l:preset_value, l:target_value)
  call s:run_build_command_in_vertical_terminal(l:argv, {
        \ 'reuse_previous_build_window': 1,
        \ 'split_orientation': 'horizontal',
        \ 'terminal_name': l:run_terminal_name,
        \ 'success_terminal_name': 'Success',
        \ 'failure_terminal_name_prefix': 'Failure',
        \ 'working_directory': l:run_directory
        \ })
  call s:write_info('Started run in ' . s:relative_path(l:run_directory, l:project_root))
endfunction

function! s:run_target_executable_candidate_names(target_name) abort
  let l:target_name = trim(s:to_string_or_empty(a:target_name))
  if empty(l:target_name)
    throw 'Missing required argument: <target>.'
  endif
  if l:target_name =~# '[/\\]'
    throw 'The target parameter must be a target name (for example: my_app), not a path.'
  endif

  let l:names = [l:target_name]
  if s:is_windows
    call add(l:names, l:target_name . '.exe')
    call add(l:names, l:target_name . '.bat')
    call add(l:names, l:target_name . '.cmd')
  endif

  let l:result = []
  let l:seen = {}
  for l:name in l:names
    if has_key(l:seen, l:name)
      continue
    endif

    let l:seen[l:name] = 1
    call add(l:result, l:name)
  endfor

  return l:result
endfunction

function! s:run_target_executable_candidate_paths(candidate_names, run_directory, build_value) abort
  if empty(trim(a:run_directory))
    throw 'Build directory cannot be empty.'
  endif

  let l:build_value = trim(s:to_string_or_empty(a:build_value))
  let l:candidate_paths = []
  for l:candidate_name in a:candidate_names
    call add(l:candidate_paths, s:path_join(a:run_directory, l:candidate_name))
    if !empty(l:build_value)
      call add(
            \ l:candidate_paths,
            \ s:path_join(s:path_join(a:run_directory, l:build_value), l:candidate_name))
    endif
  endfor

  return l:candidate_paths
endfunction

function! s:is_run_target_executable_path_candidate(path, run_directory) abort
  if !filereadable(a:path) || !s:is_sub_path_of(a:path, a:run_directory)
    return 0
  endif

  let l:relative_path = substitute(s:relative_path(a:path, a:run_directory), '\\', '/', 'g')
  if l:relative_path =~# '\v(^|/)CMakeFiles(/|$)'
    return 0
  endif

  return 1
endfunction

function! s:resolve_target_executable_path(target_name, run_directory, build_value) abort
  if empty(trim(a:run_directory))
    throw 'Build directory cannot be empty.'
  endif
  let l:run_directory = s:normalize_full_path(a:run_directory)
  let l:candidate_names = s:run_target_executable_candidate_names(a:target_name)
  let l:candidate_paths = s:run_target_executable_candidate_paths(l:candidate_names, l:run_directory, a:build_value)
  let l:matches = []
  let l:non_executable_matches = []
  let l:seen = {}

  for l:candidate_path in l:candidate_paths
    let l:normalized_candidate_path = s:normalize_full_path(l:candidate_path)
    if has_key(l:seen, l:normalized_candidate_path)
          \ || !s:is_run_target_executable_path_candidate(l:normalized_candidate_path, l:run_directory)
      continue
    endif

    let l:seen[l:normalized_candidate_path] = 1
    if s:is_windows || executable(l:normalized_candidate_path)
      call add(l:matches, l:normalized_candidate_path)
    else
      call add(l:non_executable_matches, l:normalized_candidate_path)
    endif
  endfor

  if empty(l:matches)
    for l:candidate_name in l:candidate_names
      let l:glob_pattern = s:path_join(s:path_join(l:run_directory, '**'), l:candidate_name)
      for l:glob_match in glob(l:glob_pattern, 0, 1)
        let l:normalized_glob_match = s:normalize_full_path(l:glob_match)
        if has_key(l:seen, l:normalized_glob_match)
              \ || !s:is_run_target_executable_path_candidate(l:normalized_glob_match, l:run_directory)
          continue
        endif

        let l:seen[l:normalized_glob_match] = 1
        if s:is_windows || executable(l:normalized_glob_match)
          call add(l:matches, l:normalized_glob_match)
        else
          call add(l:non_executable_matches, l:normalized_glob_match)
        endif
      endfor
    endfor
  endif

  if len(l:matches) > 1
    let l:relative_matches = []
    for l:match in l:matches
      call add(l:relative_matches, s:relative_path(l:match, l:run_directory))
    endfor
    call sort(l:relative_matches)
    throw 'Multiple executable files found for target ''' . a:target_name . ''' under '
          \ . l:run_directory . ': ' . join(l:relative_matches, ', ')
  endif

  if len(l:matches) == 1
    return l:matches[0]
  endif

  if !empty(l:non_executable_matches)
    call sort(l:non_executable_matches)
    throw 'Target file is not executable: ' . l:non_executable_matches[0]
  endif

  throw 'Executable file not found for target ''' . a:target_name . ''' under ' . l:run_directory
endfunction

function! s:run_close() abort
  let l:closed_window_count = s:close_build_terminal_windows()
  let l:closed_buffer_count = s:close_build_terminal_hidden_buffers()
  call s:reset_previous_build_terminal_window()
  let s:build_terminal_success_callbacks = {}
  call s:write_info(
        \ 'Closed build terminals: '
        \ . l:closed_window_count
        \ . ' windows, '
        \ . l:closed_buffer_count
        \ . ' hidden buffers.')
endfunction

function! s:cmake_generate_terminal_running_name(preset_value) abort
  let l:name_parts = ['cmake', 'generate']
  let l:preset_value = trim(s:to_string_or_empty(a:preset_value))
  if !empty(l:preset_value)
    call add(l:name_parts, '--preset=' . l:preset_value)
  endif

  return join(l:name_parts, ' ')
endfunction

function! s:cmake_build_terminal_running_name(preset_value, target_value) abort
  let l:name_parts = ['cmake', 'build']
  let l:preset_value = trim(s:to_string_or_empty(a:preset_value))
  let l:target_value = trim(s:to_string_or_empty(a:target_value))

  if !empty(l:preset_value)
    call add(l:name_parts, '--preset=' . l:preset_value)
  endif

  if empty(l:target_value)
    let l:target_value = 'all'
  endif
  call add(l:name_parts, '--target=' . l:target_value)

  return join(l:name_parts, ' ')
endfunction

function! s:cmake_test_terminal_running_name(preset_value) abort
  let l:name_parts = ['ctest']
  let l:preset_value = trim(s:to_string_or_empty(a:preset_value))
  if !empty(l:preset_value)
    call add(l:name_parts, '--preset=' . l:preset_value)
  endif

  return join(l:name_parts, ' ')
endfunction

function! s:cmake_run_terminal_running_name(preset_value, target_value) abort
  let l:name_parts = ['cmake', 'run']
  let l:preset_value = trim(s:to_string_or_empty(a:preset_value))
  let l:target_value = trim(s:to_string_or_empty(a:target_value))
  if !empty(l:preset_value)
    call add(l:name_parts, '--preset=' . l:preset_value)
  endif
  if !empty(l:target_value)
    call add(l:name_parts, '--target=' . l:target_value)
  endif

  return join(l:name_parts, ' ')
endfunction

function! s:generate_preset_output_directory(build_directory, preset_value) abort
  let l:preset_value = trim(s:to_string_or_empty(a:preset_value))
  if empty(l:preset_value)
    return ''
  endif

  return s:resolve_path(l:preset_value, a:build_directory)
endfunction

function! s:resolve_cmake_project_root(start_directory) abort
  let l:current = s:normalize_full_path(a:start_directory)
  if !isdirectory(l:current)
    throw 'Current directory not found: ' . l:current
  endif

  while 1
    let l:cmake_lists_path = s:path_join(l:current, 'CMakeLists.txt')
    if filereadable(l:cmake_lists_path)
      return l:current
    endif

    let l:parent = s:trim_path(fnamemodify(l:current, ':h'))
    if s:path_equals(l:parent, l:current)
      break
    endif
    let l:current = l:parent
  endwhile

  throw 'CMakeLists.txt not found in current directory or any parent directory.'
endfunction

function! s:resolve_existing_local_config_path(start_directory) abort
  let l:current = s:normalize_full_path(a:start_directory)
  if !isdirectory(l:current)
    throw 'Current directory not found: ' . l:current
  endif

  while 1
    let l:config_path = s:cmake_config_path(l:current)
    if filereadable(l:config_path)
      return l:config_path
    endif

    let l:parent = s:trim_path(fnamemodify(l:current, ':h'))
    if s:path_equals(l:parent, l:current)
      break
    endif
    let l:current = l:parent
  endwhile

  throw s:cmake_missing_local_config_error
endfunction

function! s:resolve_or_create_local_config_for_generate(start_directory, project_root) abort
  try
    return s:resolve_existing_local_config_path(a:start_directory)
  catch
    let l:message = s:format_exception(v:exception)
    if stridx(l:message, s:cmake_missing_local_config_error) < 0
      throw l:message
    endif
  endtry

  let l:config_path = s:cmake_config_path(a:project_root)
  let l:config = s:default_cmake_config_payload()
  call s:apply_default_cmake_config_values(l:config)

  call mkdir(fnamemodify(l:config_path, ':h'), 'p')
  call s:write_json_file(l:config_path, l:config)
  call s:sync_environment_from_config(l:config)
  call s:write_info('Created default config: ' . s:relative_path(l:config_path, a:project_root))

  return l:config_path
endfunction

function! s:set_config_value(key, value, ...) abort
  let l:require_existing = get(a:000, 0, 0)
  let l:working_directory = s:normalize_full_path(getcwd())
  let l:config_path = l:require_existing
        \ ? s:resolve_existing_local_config_path(l:working_directory)
        \ : s:cmake_config_path(l:working_directory)
  let l:config_root = s:normalize_full_path(fnamemodify(l:config_path, ':h'))
  let l:config = filereadable(l:config_path)
        \ ? s:read_json_object(l:config_path)
        \ : s:default_cmake_config_payload()

  let l:config[a:key] = a:value
  call mkdir(fnamemodify(l:config_path, ':h'), 'p')
  call s:write_json_file(l:config_path, l:config)
  call s:sync_environment_from_config(l:config)

  call s:write_info('Set ' . a:key . ' "' . a:value . '" in ' . s:relative_path(l:config_path, l:config_root))
endfunction

function! s:remove_config_value(key, ...) abort
  let l:require_existing = get(a:000, 0, 0)
  let l:working_directory = s:normalize_full_path(getcwd())
  let l:config_path = l:require_existing
        \ ? s:resolve_existing_local_config_path(l:working_directory)
        \ : s:cmake_config_path(l:working_directory)
  let l:config_root = s:normalize_full_path(fnamemodify(l:config_path, ':h'))
  let l:config = filereadable(l:config_path)
        \ ? s:read_json_object(l:config_path)
        \ : s:default_cmake_config_payload()

  if has_key(l:config, a:key)
    call remove(l:config, a:key)
  endif
  call mkdir(fnamemodify(l:config_path, ':h'), 'p')
  call s:write_json_file(l:config_path, l:config)
  call s:sync_environment_from_config(l:config)

  call s:write_info('Removed ' . a:key . ' from ' . s:relative_path(l:config_path, l:config_root))
endfunction

function! s:apply_default_cmake_config_values(config) abort
  let a:config[s:cmake_config_output_key] = s:cmake_config_default_output
  let a:config[s:cmake_config_preset_key] = ''
  let a:config[s:cmake_config_build_config_key] = s:cmake_config_default_build
endfunction

function! s:default_cmake_config_payload() abort
  return {}
endfunction

function! s:sync_environment_from_local_config(start_directory) abort
  let l:start_directory = s:normalize_full_path(a:start_directory)

  try
    let l:config_path = s:resolve_existing_local_config_path(l:start_directory)
  catch
    let l:message = s:format_exception(v:exception)
    if stridx(l:message, s:cmake_missing_local_config_error) >= 0
      return 0
    endif
    throw l:message
  endtry

  let l:config = s:read_json_object(l:config_path)
  return s:sync_environment_from_config(l:config)
endfunction

function! s:sync_environment_from_config(config) abort
  if type(a:config) != v:t_dict
    throw 'Config value must be a JSON object.'
  endif

  let l:environment = s:local_config_environment_variables(a:config)
  return s:apply_environment_variables(l:environment)
endfunction

function! s:local_config_environment_variables(config) abort
  if type(a:config) != v:t_dict
    throw 'Local config must be a JSON object.'
  endif

  let l:environment = {}
  for l:key in keys(a:config)
    let l:environment_key = s:config_environment_key_from_config_key(l:key)
    if empty(l:environment_key)
      continue
    endif
    let l:environment[l:environment_key] = s:config_environment_value(get(a:config, l:key, v:null))
  endfor

  return l:environment
endfunction

function! s:config_environment_key_from_config_key(key) abort
  let l:key_text = toupper(s:to_string_or_empty(a:key))
  let l:key_text = substitute(l:key_text, '[^A-Z0-9]', '_', 'g')
  let l:key_text = substitute(l:key_text, '_\+', '_', 'g')
  let l:key_text = substitute(l:key_text, '^_\+', '', '')
  let l:key_text = substitute(l:key_text, '_\+$', '', '')
  if empty(l:key_text)
    return ''
  endif

  return s:cmake_environment_prefix . l:key_text
endfunction

function! s:config_environment_value(value) abort
  if type(a:value) == v:t_string
    return a:value
  endif

  if a:value is v:null
    return ''
  endif

  if exists('v:t_bool') && type(a:value) == v:t_bool
    return a:value == v:true ? 'true' : 'false'
  endif

  if type(a:value) == v:t_list || type(a:value) == v:t_dict
    return json_encode(a:value)
  endif

  return string(a:value)
endfunction

function! s:is_valid_environment_variable_name(name) abort
  let l:name = trim(s:to_string_or_empty(a:name))
  return !empty(l:name) && l:name =~# '^[A-Za-z_][A-Za-z0-9_]*$'
endfunction

function! s:normalize_environment_variables(environment) abort
  if type(a:environment) != v:t_dict
    throw 'Environment variables must be a JSON object.'
  endif

  let l:normalized_environment = {}
  for l:key in keys(a:environment)
    let l:key_text = trim(s:to_string_or_empty(l:key))
    if empty(l:key_text)
      continue
    endif
    if !s:is_valid_environment_variable_name(l:key_text)
      throw 'Environment variable name is invalid: ' . l:key_text
    endif
    let l:normalized_environment[l:key_text] = s:to_string_or_empty(get(a:environment, l:key, ''))
  endfor

  return l:normalized_environment
endfunction

function! s:apply_environment_variables(environment) abort
  let l:normalized_environment = s:normalize_environment_variables(a:environment)
  let l:current_environment = exists('*environ') ? environ() : {}
  if type(l:current_environment) != v:t_dict
    let l:current_environment = {}
  endif

  for l:key in keys(l:current_environment)
    if stridx(l:key, s:cmake_environment_prefix) != 0
      continue
    endif
    if has_key(l:normalized_environment, l:key)
      continue
    endif
    execute 'silent! unlet $' . l:key
  endfor

  for l:key in keys(l:normalized_environment)
    execute 'let $' . l:key . ' = ' . string(l:normalized_environment[l:key])
  endfor

  return len(keys(l:normalized_environment))
endfunction

function! s:run_shell_command(argv) abort
  if empty(a:argv)
    throw 'Command arguments cannot be empty.'
  endif

  let l:escaped_arguments = map(copy(a:argv), 'shellescape(v:val)')
  let l:output = systemlist(join(l:escaped_arguments, ' '))
  let l:exit_code = v:shell_error
  if l:exit_code != 0
    let l:detail = empty(l:output) ? '' : ': ' . join(l:output, "\n")
    throw 'Command failed with exit code ' . l:exit_code . l:detail
  endif

  return l:output
endfunction

function! s:build_terminal_max_allowed_height(main_window_height) abort
  let l:main_window_height = type(a:main_window_height) == v:t_number
        \ ? a:main_window_height
        \ : str2nr(s:to_string_or_empty(a:main_window_height))
  if l:main_window_height <= 0
    let l:main_window_height = winheight(0)
  endif

  return max([1, min([s:build_terminal_max_height, l:main_window_height / 2])])
endfunction

function! s:run_build_command_in_vertical_terminal(argv, ...) abort
  if empty(a:argv)
    throw 'Command arguments cannot be empty.'
  endif

  if !s:is_terminal_build_supported()
    throw 'Terminal build execution is not supported in this Vim build.'
  endif

  let l:options = get(a:000, 0, {})
  if type(l:options) != v:t_dict
    let l:options = {}
  endif

  let l:reuse_previous_build_window = s:as_condition_bool(get(l:options, 'reuse_previous_build_window', 0))
  let l:split_orientation = tolower(trim(s:to_string_or_empty(get(l:options, 'split_orientation', 'vertical'))))
  if l:split_orientation !=# 'vertical' && l:split_orientation !=# 'horizontal'
    throw 'Split orientation must be "vertical" or "horizontal".'
  endif
  let l:terminal_name = trim(s:to_string_or_empty(get(l:options, 'terminal_name', '')))
  let l:success_terminal_name = trim(s:to_string_or_empty(get(l:options, 'success_terminal_name', '')))
  let l:failure_terminal_name_prefix = trim(s:to_string_or_empty(get(l:options, 'failure_terminal_name_prefix', '')))
  let l:OnSuccessCallback = get(l:options, 'on_success_callback', v:null)
  let l:working_directory = trim(s:to_string_or_empty(get(l:options, 'working_directory', '')))
  if !empty(l:working_directory)
    let l:working_directory = s:normalize_full_path(l:working_directory)
    if !isdirectory(l:working_directory)
      throw 'Working directory not found: ' . l:working_directory
    endif
  endif
  let l:origin_window_id = win_getid()
  let l:origin_is_terminal_window = s:is_terminal_window(l:origin_window_id)
  let l:main_window_height = l:origin_is_terminal_window ? 0 : winheight(0)
  let l:terminal_max_height = l:split_orientation ==# 'horizontal'
        \ && !l:origin_is_terminal_window
        \ ? s:build_terminal_max_allowed_height(l:main_window_height)
        \ : 0
  let l:terminal_command_options = {
        \ 'terminal_name': l:terminal_name,
        \ 'success_terminal_name': l:success_terminal_name,
        \ 'failure_terminal_name_prefix': l:failure_terminal_name_prefix,
        \ 'on_success_callback': l:OnSuccessCallback,
        \ 'working_directory': l:working_directory,
        \ 'max_height': l:terminal_max_height
        \ }
  let l:terminal = l:reuse_previous_build_window
        \ ? s:open_previous_build_terminal_window_or_recreate(
        \   l:split_orientation,
        \   l:terminal_max_height,
        \   l:origin_is_terminal_window)
        \ : s:open_new_build_terminal_window(
        \   l:split_orientation,
        \   l:terminal_max_height,
        \   l:origin_is_terminal_window)

  try
    try
      call s:start_terminal_command_in_current_buffer(a:argv, l:terminal.window_id, l:terminal_command_options)
    catch
      let l:error_message = s:format_exception(v:exception)
      if !l:reuse_previous_build_window || !get(l:terminal, 'reused_existing_window', 0)
        throw l:error_message
      endif

      let l:terminal = s:replace_build_terminal_window(
            \ l:terminal.window_id,
            \ l:split_orientation,
            \ l:terminal_max_height,
            \ l:origin_is_terminal_window)
      call s:start_terminal_command_in_current_buffer(a:argv, l:terminal.window_id, l:terminal_command_options)
    endtry

    let l:terminal.buffer_number = bufnr('%')
    if l:reuse_previous_build_window
      call s:remember_previous_build_terminal_window(l:terminal)
    endif
  finally
    if win_id2win(l:origin_window_id) > 0
      call win_gotoid(l:origin_window_id)
    endif
  endtry
endfunction

function! s:open_previous_build_terminal_window_or_recreate(split_orientation, max_height, skip_resize) abort
  let l:split_orientation = tolower(trim(s:to_string_or_empty(a:split_orientation)))
  if l:split_orientation !=# 'vertical' && l:split_orientation !=# 'horizontal'
    throw 'Split orientation must be "vertical" or "horizontal".'
  endif

  let l:previous_terminal = s:previous_build_terminal_window()
  if empty(l:previous_terminal)
    return s:open_new_build_terminal_window(l:split_orientation, a:max_height, a:skip_resize)
  endif

  if get(l:previous_terminal, 'split_orientation', 'vertical') !=# l:split_orientation
    return s:replace_build_terminal_window(
          \ l:previous_terminal.window_id,
          \ l:split_orientation,
          \ a:max_height,
          \ a:skip_resize)
  endif

  if s:is_previous_build_terminal_window_reusable(l:previous_terminal)
    if win_gotoid(l:previous_terminal.window_id)
      if l:split_orientation ==# 'horizontal' && !a:skip_resize
        execute 'silent resize ' . max([1, a:max_height])
      endif
      let l:previous_terminal.reused_existing_window = 1
      return l:previous_terminal
    endif
  endif

  return s:replace_build_terminal_window(
        \ l:previous_terminal.window_id,
        \ l:split_orientation,
        \ a:max_height,
        \ a:skip_resize)
endfunction

function! s:open_new_build_terminal_window(split_orientation, max_height, skip_resize) abort
  let l:max_height = type(a:max_height) == v:t_number
        \ ? a:max_height
        \ : str2nr(s:to_string_or_empty(a:max_height))
  if l:max_height <= 0 && !a:skip_resize
    let l:max_height = s:build_terminal_max_allowed_height(winheight(0))
  endif

  if a:split_orientation ==# 'horizontal'
    if a:skip_resize
      execute 'silent keepalt botright new'
    else
      execute 'silent keepalt botright ' . l:max_height . 'new'
    endif
  else
    execute 'silent keepalt vertical botright new'
  endif
  call s:disable_swapfile_for_current_buffer()
  execute 'silent file ' . fnameescape(s:build_terminal_buffer_name)
  let b:vim_cmake_naive_build_terminal = 1
  return {
        \ 'window_id': win_getid(),
        \ 'buffer_number': bufnr('%'),
        \ 'split_orientation': a:split_orientation,
        \ 'reused_existing_window': 0
        \ }
endfunction

function! s:replace_build_terminal_window(window_id, split_orientation, max_height, skip_resize) abort
  if win_id2win(a:window_id) <= 0
    return s:open_new_build_terminal_window(a:split_orientation, a:max_height, a:skip_resize)
  endif

  call win_gotoid(a:window_id)
  let l:old_window_id = a:window_id
  let l:old_buffer_number = bufnr('%')
  let l:new_terminal = s:open_new_build_terminal_window(
        \ a:split_orientation,
        \ a:max_height,
        \ a:skip_resize)
  if win_id2win(l:old_window_id) > 0
    call win_gotoid(l:old_window_id)
    execute 'silent! close!'
    if win_id2win(l:old_window_id) > 0
          \ && l:old_buffer_number > 0
          \ && bufexists(l:old_buffer_number)
      execute 'silent! bwipeout! ' . l:old_buffer_number
    endif
    if win_id2win(l:new_terminal.window_id) > 0
      call win_gotoid(l:new_terminal.window_id)
    endif
  endif

  return l:new_terminal
endfunction

function! s:remember_previous_build_terminal_window(terminal) abort
  let l:split_orientation = tolower(trim(s:to_string_or_empty(get(a:terminal, 'split_orientation', 'vertical'))))
  if l:split_orientation !=# 'vertical' && l:split_orientation !=# 'horizontal'
    let l:split_orientation = 'vertical'
  endif
  let s:last_cmake_build_window_id = get(a:terminal, 'window_id', -1)
  let s:last_cmake_build_buffer_number = get(a:terminal, 'buffer_number', -1)
  let s:last_cmake_build_split_orientation = l:split_orientation
endfunction

function! s:previous_build_terminal_window() abort
  if type(s:last_cmake_build_window_id) != v:t_number || s:last_cmake_build_window_id <= 0
    return {}
  endif

  let l:window_number = win_id2win(s:last_cmake_build_window_id)
  if l:window_number <= 0
    return {}
  endif

  let l:buffer_number = winbufnr(l:window_number)
  if l:buffer_number <= 0 || !bufexists(l:buffer_number)
    return {}
  endif

  if getbufvar(l:buffer_number, '&buftype', '') !=# 'terminal'
    return {}
  endif

  let l:split_orientation = tolower(trim(s:to_string_or_empty(s:last_cmake_build_split_orientation)))
  if l:split_orientation !=# 'vertical' && l:split_orientation !=# 'horizontal'
    let l:split_orientation = 'vertical'
  endif

  return {
        \ 'window_id': s:last_cmake_build_window_id,
        \ 'buffer_number': l:buffer_number,
        \ 'split_orientation': l:split_orientation
        \ }
endfunction

function! s:is_previous_build_terminal_window_reusable(terminal) abort
  let l:window_id = get(a:terminal, 'window_id', -1)
  let l:buffer_number = get(a:terminal, 'buffer_number', -1)
  if win_id2win(l:window_id) <= 0 || l:buffer_number <= 0 || !bufexists(l:buffer_number)
    return 0
  endif

  return !s:is_terminal_buffer_job_running(l:buffer_number)
endfunction

function! s:close_build_terminal_windows() abort
  let l:window_ids = s:build_terminal_window_ids()
  let l:closed_window_count = 0
  let l:origin_window_id = win_getid()

  for l:window_id in l:window_ids
    if win_id2win(l:window_id) <= 0
      continue
    endif

    if win_gotoid(l:window_id)
      let l:buffer_number = bufnr('%')
      execute 'silent! close!'
      if l:buffer_number > 0 && bufexists(l:buffer_number)
        execute 'silent! bwipeout! ' . l:buffer_number
      endif
      if win_id2win(l:window_id) <= 0
        let l:closed_window_count += 1
      endif
    endif
  endfor

  if win_id2win(l:origin_window_id) > 0
    call win_gotoid(l:origin_window_id)
  endif

  return l:closed_window_count
endfunction

function! s:close_build_terminal_hidden_buffers() abort
  let l:closed_buffer_count = 0
  for l:buffer_info in getbufinfo()
    let l:buffer_number = get(l:buffer_info, 'bufnr', -1)
    if l:buffer_number <= 0
          \ || !bufexists(l:buffer_number)
          \ || getbufvar(l:buffer_number, '&buftype', '') !=# 'terminal'
          \ || !getbufvar(l:buffer_number, 'vim_cmake_naive_build_terminal', 0)
          \ || bufwinnr(l:buffer_number) >= 0
      continue
    endif

    execute 'silent! bwipeout! ' . l:buffer_number
    if !bufexists(l:buffer_number)
      let l:closed_buffer_count += 1
    endif
  endfor

  return l:closed_buffer_count
endfunction

function! s:build_terminal_window_ids() abort
  let l:window_ids = []
  let l:seen = {}
  if !exists('*getwininfo')
    return l:window_ids
  endif

  for l:window_info in getwininfo()
    let l:window_id = get(l:window_info, 'winid', 0)
    let l:buffer_number = get(l:window_info, 'bufnr', -1)
    if l:window_id <= 0
          \ || l:buffer_number <= 0
          \ || has_key(l:seen, l:window_id)
          \ || getbufvar(l:buffer_number, '&buftype', '') !=# 'terminal'
          \ || !getbufvar(l:buffer_number, 'vim_cmake_naive_build_terminal', 0)
      continue
    endif

    let l:seen[l:window_id] = 1
    call add(l:window_ids, l:window_id)
  endfor

  return l:window_ids
endfunction

function! s:reset_previous_build_terminal_window() abort
  let s:last_cmake_build_window_id = -1
  let s:last_cmake_build_buffer_number = -1
  let s:last_cmake_build_split_orientation = 'vertical'
endfunction

function! s:is_terminal_buffer_job_running(buffer_number) abort
  if a:buffer_number <= 0 || !bufexists(a:buffer_number)
    return 0
  endif
  if getbufvar(a:buffer_number, '&buftype', '') !=# 'terminal'
    return 0
  endif
  if !exists('*term_getstatus')
    return 0
  endif

  return stridx(term_getstatus(a:buffer_number), 'running') >= 0
endfunction

function! s:is_terminal_window(window_id) abort
  let l:window_number = win_id2win(a:window_id)
  if l:window_number <= 0
    return 0
  endif

  let l:buffer_number = winbufnr(l:window_number)
  if l:buffer_number <= 0 || !bufexists(l:buffer_number)
    return 0
  endif

  return getbufvar(l:buffer_number, '&buftype', '') ==# 'terminal'
endfunction

function! s:is_terminal_build_supported() abort
  return exists('*term_start')
        \ && exists('*job_info')
endfunction

function! s:disable_swapfile_for_current_buffer() abort
  if &l:swapfile
    setlocal noswapfile
  endif
endfunction

function! s:start_terminal_command_in_current_buffer(argv, window_id, ...) abort
  let l:options = get(a:000, 0, {})
  if type(l:options) != v:t_dict
    let l:options = {}
  endif

  let l:terminal_name = trim(s:to_string_or_empty(get(l:options, 'terminal_name', '')))
  let l:success_terminal_name = trim(s:to_string_or_empty(get(l:options, 'success_terminal_name', '')))
  let l:failure_terminal_name_prefix = trim(s:to_string_or_empty(get(l:options, 'failure_terminal_name_prefix', '')))
  let l:OnSuccessCallback = get(l:options, 'on_success_callback', v:null)
  let l:working_directory = trim(s:to_string_or_empty(get(l:options, 'working_directory', '')))
  let l:max_height = get(l:options, 'max_height', 0)
  if type(l:max_height) != v:t_number
    let l:max_height = str2nr(s:to_string_or_empty(l:max_height))
  endif

  let l:term_options = {'curwin': 1}
  call s:disable_swapfile_for_current_buffer()
  call s:set_build_terminal_success_callback(a:window_id, l:OnSuccessCallback)
  if !empty(l:working_directory)
    let l:term_options.cwd = l:working_directory
  endif
  if !s:should_capture_build_terminal_for_tests()
    let l:term_options.exit_cb = function(
          \ 's:on_build_terminal_command_exit',
          \ [a:window_id, l:success_terminal_name, l:failure_terminal_name_prefix])
  endif

  let l:term_start_options = copy(l:term_options)
  if !empty(l:terminal_name)
    let l:term_start_options.term_name = l:terminal_name
  endif

  try
    try
      let l:job = term_start(copy(a:argv), l:term_start_options)
    catch /^Vim\%((\a\+)\)\=:E475:/
      if !has_key(l:term_start_options, 'term_name')
        throw v:exception
      endif

      call remove(l:term_start_options, 'term_name')
      let l:job = term_start(copy(a:argv), l:term_start_options)
    endtry
  catch
    call s:take_build_terminal_success_callback(a:window_id)
    throw v:exception
  endtry
  if type(l:job) != v:t_number || l:job <= 0
    call s:take_build_terminal_success_callback(a:window_id)
    throw 'Failed to start build command in terminal window.'
  endif

  call s:disable_swapfile_for_current_buffer()
  let l:terminal_buffer_number = bufnr('%')
  let b:vim_cmake_naive_build_terminal = 1
  if l:max_height > 0
    let b:vim_cmake_naive_build_terminal_max_height = l:max_height
  else
    unlet! b:vim_cmake_naive_build_terminal_max_height
  endif
  call s:set_running_terminal_name(a:window_id, l:terminal_name, l:terminal_buffer_number)
  call s:capture_build_terminal_for_tests(a:window_id, l:terminal_buffer_number)
  if s:should_capture_build_terminal_for_tests()
    let l:exit_code = s:wait_for_terminal_command_and_read_exit_code(l:terminal_buffer_number)
    call s:set_terminal_name_for_window(
          \ a:window_id,
          \ s:terminal_completion_name(
          \   l:exit_code,
          \   l:success_terminal_name,
          \   l:failure_terminal_name_prefix))
    let l:terminal_buffer_number = s:terminal_buffer_number_for_window(a:window_id)
    if l:terminal_buffer_number > 0
      call s:capture_build_terminal_for_tests(a:window_id, l:terminal_buffer_number)
    endif
    let l:OnSuccessCallback = s:take_build_terminal_success_callback(a:window_id)
    if l:exit_code == 0
      call s:invoke_terminal_success_callback(l:OnSuccessCallback)
    else
      call s:write_error('Command failed with exit code ' . l:exit_code . '. See build terminal window for details.')
    endif
  endif
endfunction

function! s:set_running_terminal_name(window_id, terminal_name, buffer_number) abort
  let l:terminal_name = trim(s:to_string_or_empty(a:terminal_name))
  if empty(l:terminal_name)
    return
  endif

  call s:set_terminal_name_for_window(a:window_id, l:terminal_name)
  if a:buffer_number <= 0 || !bufexists(a:buffer_number) || bufname(a:buffer_number) ==# l:terminal_name
    return
  endif

  if exists('*term_wait') && s:is_terminal_buffer_job_running(a:buffer_number)
    call term_wait(a:buffer_number, 10)
  endif
  call s:set_terminal_name_for_window(a:window_id, l:terminal_name)
endfunction

function! s:on_build_terminal_command_exit(window_id, success_terminal_name, failure_terminal_name_prefix, job, status) abort
  let l:exit_code = s:terminal_job_exit_code(a:job, a:status)
  call s:set_terminal_name_for_window(
        \ a:window_id,
        \ s:terminal_completion_name(
        \   l:exit_code,
        \   a:success_terminal_name,
        \   a:failure_terminal_name_prefix))

  let l:terminal_buffer_number = s:terminal_buffer_number_for_window(a:window_id)
  if l:terminal_buffer_number > 0
    call s:capture_build_terminal_for_tests(a:window_id, l:terminal_buffer_number)
  endif

  let l:OnSuccessCallback = s:take_build_terminal_success_callback(a:window_id)
  if l:exit_code == 0
    call s:invoke_terminal_success_callback(l:OnSuccessCallback)
  else
    call s:write_error('Command failed with exit code ' . l:exit_code . '. See build terminal window for details.')
  endif
endfunction

function! s:set_build_terminal_success_callback(window_id, Callback) abort
  if type(a:window_id) != v:t_number || a:window_id <= 0
    return
  endif

  let l:key = string(a:window_id)
  if type(a:Callback) == v:t_func
    let s:build_terminal_success_callbacks[l:key] = a:Callback
    return
  endif

  if has_key(s:build_terminal_success_callbacks, l:key)
    call remove(s:build_terminal_success_callbacks, l:key)
  endif
endfunction

function! s:take_build_terminal_success_callback(window_id) abort
  if type(a:window_id) != v:t_number || a:window_id <= 0
    return v:null
  endif

  let l:key = string(a:window_id)
  let l:Callback = get(s:build_terminal_success_callbacks, l:key, v:null)
  if has_key(s:build_terminal_success_callbacks, l:key)
    call remove(s:build_terminal_success_callbacks, l:key)
  endif

  return l:Callback
endfunction

function! s:invoke_terminal_success_callback(Callback) abort
  if type(a:Callback) != v:t_func
    return
  endif

  try
    call call(a:Callback, [])
  catch
    call s:write_error(s:format_exception(v:exception))
  endtry
endfunction

function! s:terminal_completion_name(exit_code, success_terminal_name, failure_terminal_name_prefix) abort
  let l:success_terminal_name = trim(s:to_string_or_empty(a:success_terminal_name))
  if a:exit_code == 0
    return l:success_terminal_name
  endif

  let l:failure_terminal_name_prefix = trim(s:to_string_or_empty(a:failure_terminal_name_prefix))
  if empty(l:failure_terminal_name_prefix)
    return ''
  endif

  return l:failure_terminal_name_prefix . ' (' . a:exit_code . ')'
endfunction

function! s:terminal_buffer_number_for_window(window_id) abort
  let l:window_number = win_id2win(a:window_id)
  if l:window_number <= 0
    return -1
  endif

  return winbufnr(l:window_number)
endfunction

function! s:buffer_numbers_with_name(buffer_name) abort
  let l:buffer_numbers = []
  for l:buffer_info in getbufinfo()
    let l:buffer_number = get(l:buffer_info, 'bufnr', -1)
    if l:buffer_number > 0 && bufname(l:buffer_number) ==# a:buffer_name
      call add(l:buffer_numbers, l:buffer_number)
    endif
  endfor

  return l:buffer_numbers
endfunction

function! s:set_terminal_name_for_window(window_id, terminal_name) abort
  let l:terminal_name = trim(s:to_string_or_empty(a:terminal_name))
  if empty(l:terminal_name) || win_id2win(a:window_id) <= 0
    return
  endif

  let l:origin_window_id = win_getid()
  if !win_gotoid(a:window_id)
    return
  endif

  try
    let l:current_buffer_number = bufnr('%')
    for l:conflicting_buffer_number in s:buffer_numbers_with_name(l:terminal_name)
      if l:conflicting_buffer_number == l:current_buffer_number
        continue
      endif

      if !getbufvar(l:conflicting_buffer_number, 'vim_cmake_naive_build_terminal', 0)
            \ || bufwinnr(l:conflicting_buffer_number) >= 0
        return
      endif

      execute 'silent! bwipeout! ' . l:conflicting_buffer_number
    endfor

    call s:disable_swapfile_for_current_buffer()
    execute 'silent file ' . fnameescape(l:terminal_name)
    let b:vim_cmake_naive_build_terminal = 1
  finally
    if win_id2win(l:origin_window_id) > 0
      call win_gotoid(l:origin_window_id)
    endif
  endtry
endfunction

function! s:terminal_job_exit_code(job, status) abort
  if type(a:status) == v:t_number
    return a:status
  endif

  let l:status_text = trim(s:to_string_or_empty(a:status))
  if l:status_text =~# '^-\\?\d\+$'
    return str2nr(l:status_text)
  endif

  try
    let l:job_info = job_info(a:job)
  catch
    return 0
  endtry

  if type(l:job_info) == v:t_dict && has_key(l:job_info, 'exitval')
    return str2nr(s:to_string_or_empty(get(l:job_info, 'exitval', 0)))
  endif

  return 0
endfunction

function! s:wait_for_terminal_command_and_read_exit_code(buffer_number) abort
  if !exists('*term_wait') || !exists('*term_getstatus') || !exists('*term_getjob')
    return 0
  endif

  while stridx(term_getstatus(a:buffer_number), 'running') >= 0
    call term_wait(a:buffer_number, 10)
  endwhile
  call term_wait(a:buffer_number, 10)

  return s:terminal_job_exit_code(term_getjob(a:buffer_number), v:null)
endfunction

function! s:capture_build_terminal_for_tests(window_id, buffer_number) abort
  if !s:should_capture_build_terminal_for_tests()
    return
  endif

  let l:window_number = win_id2win(a:window_id)
  let l:window_width = l:window_number > 0 ? winwidth(l:window_number) : 0
  let l:window_height = l:window_number > 0 ? winheight(l:window_number) : 0
  let l:current_window_number = winnr()
  let l:is_vertical_split = winnr('h') != l:current_window_number
        \ || winnr('l') != l:current_window_number
  let l:is_horizontal_split = winnr('k') != l:current_window_number
        \ || winnr('j') != l:current_window_number
  let l:is_valid_buffer = a:buffer_number > 0 && bufexists(a:buffer_number)
  let l:is_terminal = l:is_valid_buffer && getbufvar(a:buffer_number, '&buftype', '') ==# 'terminal'
  let l:buffer_name = l:is_valid_buffer ? bufname(a:buffer_number) : ''
  let l:max_height = l:is_valid_buffer
        \ ? getbufvar(a:buffer_number, 'vim_cmake_naive_build_terminal_max_height', 0)
        \ : 0
  let l:swapfile_enabled = l:is_valid_buffer ? getbufvar(a:buffer_number, '&swapfile', 0) : 0
  let g:vim_cmake_naive_test_last_build_terminal = {
        \ 'winid': a:window_id,
        \ 'width': l:window_width,
        \ 'height': l:window_height,
        \ 'max_height': l:max_height,
        \ 'window_count': winnr('$'),
        \ 'is_vertical_split': l:is_vertical_split,
        \ 'is_horizontal_split': l:is_horizontal_split,
        \ 'is_terminal': l:is_terminal,
        \ 'swapfile_enabled': l:swapfile_enabled,
        \ 'buffer_name': l:buffer_name,
        \ 'lines': s:build_terminal_non_empty_lines(a:buffer_number)
        \ }
endfunction

function! s:should_capture_build_terminal_for_tests() abort
  return exists('g:vim_cmake_naive_test_capture_build_terminal')
        \ && s:as_condition_bool(g:vim_cmake_naive_test_capture_build_terminal)
endfunction

function! s:build_terminal_non_empty_lines(buffer_number) abort
  if a:buffer_number <= 0 || !bufexists(a:buffer_number)
    return []
  endif

  if getbufvar(a:buffer_number, '&buftype', '') ==# 'terminal' && exists('*term_getline')
    let l:lines = []
    let l:index = 1
    while l:index <= 500
      try
        let l:line = term_getline(a:buffer_number, l:index)
      catch
        break
      endtry

      if type(l:line) == v:t_string
        let l:line = substitute(l:line, '\r', '', 'g')
        if !empty(trim(l:line))
          call add(l:lines, l:line)
        endif
      endif
      let l:index += 1
    endwhile
    return l:lines
  endif

  return filter(getbufline(a:buffer_number, 1, '$'), '!empty(trim(v:val))')
endfunction

function! s:cmake_config_path(project_root) abort
  return s:path_join(a:project_root, s:cmake_config_filename)
endfunction

function! s:cmake_cache_path(config_path) abort
  if empty(trim(a:config_path))
    throw 'Config path cannot be empty.'
  endif

  return s:path_join(fnamemodify(a:config_path, ':h'), s:cmake_cache_filename)
endfunction

function! s:cmake_presets_path(project_root) abort
  return s:path_join(a:project_root, s:cmake_presets_filename)
endfunction

function! s:resolve_switch_target_directory(target_name, build_directory) abort
  if empty(trim(a:target_name))
    throw 'Missing required argument: <target>.'
  endif
  if empty(trim(a:build_directory))
    throw 'Build directory cannot be empty.'
  endif

  if a:target_name =~# '[/\\]'
    throw 'The target parameter must be a target name (for example: my_app), not a path.'
  endif

  let l:target_directory = s:normalize_full_path(
        \ s:path_join(
        \   s:path_join(a:build_directory, 'CMakeFiles'),
        \   a:target_name . '.dir'))
  if !isdirectory(l:target_directory)
    throw 'target directory not found for ''' . a:target_name . ''': ' . l:target_directory
  endif

  return l:target_directory
endfunction

function! s:resolve_build_directory(build_directory) abort
  if empty(trim(a:build_directory))
    throw 'Build directory cannot be empty.'
  endif

  let l:full_path = s:normalize_full_path(a:build_directory)
  if !isdirectory(l:full_path)
    throw 'Build directory not found: ' . l:full_path
  endif

  return s:normalize_full_path(resolve(l:full_path))
endfunction

function! s:resolve_input_file_path(input_path, build_directory) abort
  if empty(trim(a:build_directory))
    throw 'Build directory cannot be empty.'
  endif

  let l:candidate = empty(trim(a:input_path))
        \ ? s:path_join(a:build_directory, s:default_input_filename)
        \ : a:input_path
  let l:full_path = s:resolve_path(l:candidate, a:build_directory)
  if !filereadable(l:full_path)
    throw 'Input file not found: ' . l:full_path
  endif

  return l:full_path
endfunction

function! s:resolve_directory_path(candidate, build_directory, parameter_name, must_exist) abort
  if empty(trim(a:parameter_name))
    throw 'Parameter name cannot be empty.'
  endif
  if empty(trim(a:build_directory))
    throw 'Build directory cannot be empty.'
  endif
  if empty(trim(a:candidate))
    throw a:parameter_name . ' path cannot be empty.'
  endif

  let l:resolved_path = s:resolve_path(a:candidate, a:build_directory)
  if a:must_exist && !isdirectory(l:resolved_path)
    throw a:parameter_name . ' directory not found: ' . l:resolved_path
  endif

  return l:resolved_path
endfunction

function! s:resolve_working_directory(entry_directory, build_directory) abort
  if empty(trim(a:build_directory))
    throw 'Build directory cannot be empty.'
  endif

  if empty(trim(a:entry_directory))
    return a:build_directory
  endif

  return s:resolve_path(a:entry_directory, a:build_directory)
endfunction

function! s:infer_target_directory(build_directory, working_directory, output, arguments, command) abort
  if empty(trim(a:build_directory))
    throw 'Build directory cannot be empty.'
  endif
  if empty(trim(a:working_directory))
    throw 'Working directory cannot be empty.'
  endif

  let l:checked_candidates = {}
  for l:candidate in s:extract_path_candidates(a:output, a:arguments, a:command)
    if has_key(l:checked_candidates, l:candidate)
      continue
    endif

    let l:checked_candidates[l:candidate] = 1
    let l:target_directory = s:try_resolve_target_directory(l:candidate, a:working_directory, a:build_directory)
    if !empty(l:target_directory)
      return l:target_directory
    endif
  endfor

  return ''
endfunction

function! s:extract_path_candidates(output, arguments, command) abort
  let l:candidates = []

  if !empty(trim(a:output))
    call add(l:candidates, a:output)
  endif

  if type(a:arguments) == v:t_list
    call extend(l:candidates, s:extract_path_candidates_from_tokens(a:arguments))
  endif

  if type(a:command) == v:t_string && !empty(trim(a:command))
    call extend(l:candidates, s:extract_path_candidates_from_tokens(s:split_compiler_command(a:command)))
  endif

  return l:candidates
endfunction

function! s:extract_path_candidates_from_tokens(tokens) abort
  let l:candidates = []

  for l:index in range(0, len(a:tokens) - 1)
    let l:token = s:clean_token(s:to_string_or_empty(a:tokens[l:index]))
    if empty(trim(l:token))
      continue
    endif

    if l:token ==# '-o'
      if l:index + 1 < len(a:tokens)
        call add(l:candidates, s:clean_token(s:to_string_or_empty(a:tokens[l:index + 1])))
      endif
      continue
    endif

    if tolower(l:token) ==# '/fo'
      if l:index + 1 < len(a:tokens)
        call add(l:candidates, s:clean_token(s:to_string_or_empty(a:tokens[l:index + 1])))
      endif
      continue
    endif

    if l:token =~# '^-o'
      let l:value = s:trim_leading_equals(strpart(l:token, 2))
      if !empty(trim(l:value))
        call add(l:candidates, l:value)
      endif
    endif

    if l:token =~? '^/Fo'
      let l:value = s:trim_leading_equals(strpart(l:token, 3))
      if !empty(trim(l:value))
        call add(l:candidates, l:value)
      endif
    endif

    if l:token =~? 'CMakeFiles[\\/][^\\/]\+\.dir\([\\/]\|$\)'
      call add(l:candidates, l:token)
    endif
  endfor

  return l:candidates
endfunction

function! s:try_resolve_target_directory(candidate, working_directory, build_directory) abort
  if empty(trim(a:working_directory))
    throw 'Working directory cannot be empty.'
  endif
  if empty(trim(a:build_directory))
    throw 'Build directory cannot be empty.'
  endif

  let l:cleaned_candidate = s:clean_token(a:candidate)
  if empty(trim(l:cleaned_candidate))
    return ''
  endif

  let l:path_candidate = substitute(l:cleaned_candidate, '\\', '/', 'g')
  let l:absolute_path = s:resolve_path(l:path_candidate, a:working_directory)

  let l:match = matchlist(l:absolute_path, s:target_directory_pattern)
  if empty(l:match)
    return ''
  endif

  let l:target_directory = s:normalize_full_path(l:match[1])
  return s:is_sub_path_of(l:target_directory, a:build_directory) ? l:target_directory : ''
endfunction

function! s:is_sub_path_of(candidate_path, root_path) abort
  let l:candidate = s:normalize_full_path(a:candidate_path)
  let l:root = s:normalize_full_path(a:root_path)
  if s:path_equals(l:candidate, l:root)
    return 1
  endif

  let l:root_prefix = l:root ==# '/' ? '/' : l:root . '/'
  return s:path_starts_with(l:candidate, l:root_prefix)
endfunction

function! s:split_compiler_command(command) abort
  if empty(trim(a:command))
    return []
  endif

  let l:tokens = []
  let l:current = ''
  let l:quote_char = ''

  for l:character in split(a:command, '\zs')
    if empty(l:quote_char)
      if l:character ==# '"' || l:character ==# "'"
        let l:quote_char = l:character
        continue
      endif

      if l:character =~# '\s'
        if !empty(l:current)
          call add(l:tokens, l:current)
          let l:current = ''
        endif
        continue
      endif

      let l:current .= l:character
      continue
    endif

    if l:character ==# l:quote_char
      let l:quote_char = ''
      continue
    endif

    let l:current .= l:character
  endfor

  if !empty(l:current)
    call add(l:tokens, l:current)
  endif

  return l:tokens
endfunction

function! s:trim_leading_equals(value) abort
  if empty(a:value)
    return a:value
  endif

  return a:value[0] ==# '=' ? a:value[1:] : a:value
endfunction

function! s:clean_token(token) abort
  let l:cleaned = trim(s:to_string_or_empty(a:token))
  if empty(l:cleaned)
    return l:cleaned
  endif

  let l:cleaned = trim(l:cleaned, '"''')
  if l:cleaned =~# '[,;]$'
    let l:cleaned = l:cleaned[:-2]
  endif

  return l:cleaned
endfunction

function! s:read_json_array(path) abort
  let l:payload = join(readfile(a:path, 'b'), "\n")

  try
    let l:entries = json_decode(l:payload)
  catch
    throw 'Invalid JSON: ' . s:format_exception(v:exception)
  endtry

  if type(l:entries) != v:t_list
    throw 'Input file ''' . a:path . ''' must be a JSON array.'
  endif

  return l:entries
endfunction

function! s:read_json_object(path) abort
  let l:payload = join(readfile(a:path, 'b'), "\n")

  try
    let l:value = json_decode(l:payload)
  catch
    throw 'Invalid JSON: ' . s:format_exception(v:exception)
  endtry

  if type(l:value) != v:t_dict
    throw 'Config file ''' . a:path . ''' must be a JSON object.'
  endif

  return l:value
endfunction

function! s:write_json_file(path, value) abort
  call writefile([json_encode(a:value)], a:path, 'b')
endfunction

function! s:resolve_path(candidate, base_directory) abort
  let l:path = s:is_absolute_path(a:candidate)
        \ ? a:candidate
        \ : s:path_join(a:base_directory, a:candidate)
  return s:normalize_full_path(l:path)
endfunction

function! s:relative_path(path, root) abort
  let l:normalized_path = s:normalize_full_path(a:path)
  let l:normalized_root = s:normalize_full_path(a:root)

  if s:path_equals(l:normalized_path, l:normalized_root)
    return '.'
  endif

  let l:root_prefix = l:normalized_root ==# '/' ? '/' : l:normalized_root . '/'
  if s:path_starts_with(l:normalized_path, l:root_prefix)
    return l:normalized_path[strlen(l:root_prefix):]
  endif

  return l:normalized_path
endfunction

function! s:is_absolute_path(path) abort
  if empty(a:path)
    return 0
  endif

  if a:path =~# '^/'
    return 1
  endif

  if a:path =~? '^\a:[/\\]'
    return 1
  endif

  return a:path =~# '^\\\\'
endfunction

function! s:normalize_full_path(path) abort
  let l:full_path = simplify(fnamemodify(a:path, ':p'))
  let l:full_path = s:normalize_separators(l:full_path)
  return s:trim_path(l:full_path)
endfunction

function! s:path_join(left, right) abort
  let l:left = s:normalize_separators(a:left)
  let l:right = s:normalize_separators(a:right)
  if empty(l:left)
    return l:right
  endif
  if empty(l:right)
    return l:left
  endif

  let l:right = substitute(l:right, '^/\+', '', '')
  if l:left ==# '/'
    return '/' . l:right
  endif

  return l:left =~# '/$' ? l:left . l:right : l:left . '/' . l:right
endfunction

function! s:normalize_separators(path) abort
  return substitute(a:path, '\\', '/', 'g')
endfunction

function! s:trim_path(path) abort
  let l:path = s:normalize_separators(a:path)
  if l:path ==# '/' || l:path =~? '^\a:/$'
    return l:path
  endif

  return substitute(l:path, '/\+$', '', '')
endfunction

function! s:path_equals(left, right) abort
  return s:path_for_compare(a:left) ==# s:path_for_compare(a:right)
endfunction

function! s:path_starts_with(path, prefix) abort
  return stridx(s:path_for_compare(a:path), s:path_for_compare(a:prefix)) == 0
endfunction

function! s:path_for_compare(path) abort
  let l:path = s:normalize_separators(a:path)
  return s:is_windows ? tolower(l:path) : l:path
endfunction

function! s:to_string_or_empty(value) abort
  if type(a:value) == v:t_string
    return a:value
  endif

  if a:value is v:null
    return ''
  endif

  return string(a:value)
endfunction

function! s:write_info(message) abort
  echom '[vim-cmake-naive] ' . a:message
endfunction

function! s:write_error(message) abort
  echohl ErrorMsg
  echom '[vim-cmake-naive] ' . a:message
  echohl None
endfunction

function! s:write_builtin_error(message) abort
  let l:full_message = '[vim-cmake-naive] ' . a:message
  try
    execute 'echoerr ' . string(l:full_message)
  catch /^Vim(echoerr):/
    call s:write_error(a:message)
  endtry
  let v:errmsg = l:full_message
endfunction

function! s:format_exception(exception_text) abort
  let l:message = substitute(a:exception_text, '^Vim\%((\a\+)\)\?:', '', '')
  return trim(l:message)
endfunction
