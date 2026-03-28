let s:default_input_filename = 'compile_commands.json'
let s:default_output_filename = 'compile_commands.json'
let s:cmake_config_relative_path = '.vim/.cmake/.config.json'
let s:cmake_presets_filename = 'CMakePresets.json'
let s:cmake_config_preset_key = 'preset'
let s:cmake_config_build_config_key = 'build'
let s:cmake_config_output_key = 'output'
let s:cmake_config_target_key = 'target'
let s:cmake_config_default_build = 'Debug'
let s:cmake_config_default_output = 'build'
let s:target_directory_pattern = '\v^(.{-}CMakeFiles[\\/][^\\/]+\.dir)([\\/]|$)'
let s:is_windows = has('win32') || has('win64') || has('win32unix')

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
    call s:run_cmake_config()
  catch
    call s:write_error(s:format_exception(v:exception))
  endtry
endfunction

function! vim_cmake_naive#switch_preset() abort
  try
    call s:run_switch_preset()
  catch
    call s:write_error(s:format_exception(v:exception))
  endtry
endfunction

function! vim_cmake_naive#switch_target() abort
  try
    call s:run_switch_target()
  catch
    call s:write_error(s:format_exception(v:exception))
  endtry
endfunction

function! vim_cmake_naive#set_config_preset(preset) abort
  try
    call s:run_set_config_preset(a:preset)
  catch
    call s:write_error(s:format_exception(v:exception))
  endtry
endfunction

function! vim_cmake_naive#reset_config_preset() abort
  try
    call s:run_reset_config_preset()
  catch
    call s:write_error(s:format_exception(v:exception))
  endtry
endfunction

function! vim_cmake_naive#reset_config_target() abort
  try
    call s:run_reset_config_target()
  catch
    call s:write_error(s:format_exception(v:exception))
  endtry
endfunction

function! vim_cmake_naive#set_config_build_config(build_config) abort
  try
    call s:run_set_config_build_config(a:build_config)
  catch
    call s:write_error(s:format_exception(v:exception))
  endtry
endfunction

function! vim_cmake_naive#set_config_output(output) abort
  try
    call s:run_set_config_output(a:output)
  catch
    call s:write_error(s:format_exception(v:exception))
  endtry
endfunction

function! vim_cmake_naive#cmake_config_default() abort
  try
    call s:run_cmake_config_default()
  catch
    call s:write_error(s:format_exception(v:exception))
  endtry
endfunction

function! vim_cmake_naive#generate() abort
  try
    call s:run_generate()
  catch
    call s:write_error(s:format_exception(v:exception))
  endtry
endfunction

function! vim_cmake_naive#build() abort
  try
    call s:run_build()
  catch
    call s:write_error(s:format_exception(v:exception))
  endtry
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

  call mkdir(l:config_directory, 'p')
  call s:write_json_file(l:config_path, s:default_cmake_config_payload())

  call s:write_info('Created ' . s:relative_path(l:config_path, l:project_root))
endfunction

function! s:run_set_config_preset(preset) abort
  let l:preset = s:to_string_or_empty(a:preset)
  if empty(trim(l:preset))
    throw 'Preset value cannot be empty.'
  endif
  call s:set_config_value(s:cmake_config_preset_key, l:preset, 1)
endfunction

function! s:run_reset_config_preset() abort
  call s:set_config_value(s:cmake_config_preset_key, '')
endfunction

function! s:run_reset_config_target() abort
  call s:set_config_value(s:cmake_config_target_key, '')
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
  let l:presets_path = s:cmake_presets_path(l:project_root)
  if !filereadable(l:presets_path)
    throw s:cmake_presets_filename . ' not found at project root: ' . l:presets_path
  endif

  let l:presets_payload = s:read_json_object(l:presets_path)
  let l:available_presets = s:available_configure_presets(l:presets_payload, l:project_root)
  call sort(l:available_presets)
  let l:current_preset = s:current_config_preset_for_switch(l:working_directory)
  if empty(l:available_presets)
    throw 'No selectable configure presets found in ' . s:cmake_presets_filename . '.'
  endif

  if s:should_use_popup_menu_for_preset_selection()
    call s:show_switch_preset_popup('Select CMake preset:', l:available_presets, l:current_preset)
    return
  endif

  let l:selected_preset = s:select_item_from_menu('Select CMake preset:', l:available_presets)
  if empty(l:selected_preset)
    call s:write_info('Preset selection canceled.')
    return
  endif

  call s:run_set_config_preset(l:selected_preset)
endfunction

function! s:current_config_preset_for_switch(start_directory) abort
  try
    let l:config_path = s:resolve_existing_local_config_path(a:start_directory)
  catch
    let l:message = s:format_exception(v:exception)
    if stridx(l:message, '.vim/.cmake/.config.json not found in current directory or any parent directory.') >= 0
      return ''
    endif
    throw l:message
  endtry

  let l:config = s:read_json_object(l:config_path)
  return trim(s:to_string_or_empty(get(l:config, s:cmake_config_preset_key, '')))
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
  let l:display_items = s:preset_popup_display_items(a:items, a:current_preset)
  if exists('g:vim_cmake_naive_test_popup_menu_response')
    let g:vim_cmake_naive_test_last_preset_popup_items = copy(l:display_items)
    call s:on_switch_preset_popup_selection(copy(a:items), 0, g:vim_cmake_naive_test_popup_menu_response)
    return
  endif

  call popup_menu(l:display_items, {
        \ 'title': a:prompt,
        \ 'callback': function('s:on_switch_preset_popup_selection', [copy(a:items)])
        \ })
endfunction

function! s:preset_popup_display_items(items, current_preset) abort
  let l:display_items = []
  let l:index = 0
  while l:index < len(a:items)
    let l:item = a:items[l:index]
    let l:display_item = (l:index + 1) . '. ' . l:item
    if !empty(a:current_preset) && l:item ==# a:current_preset
      let l:display_item .= ' *'
    endif
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
    call s:run_set_config_preset(l:selected_preset)
  catch
    call s:write_error(s:format_exception(v:exception))
  endtry
endfunction

function! s:run_switch_target() abort
  let l:working_directory = s:normalize_full_path(getcwd())
  let l:config_path = s:resolve_existing_local_config_path(l:working_directory)
  let l:config = s:read_json_object(l:config_path)
  let l:project_root = s:normalize_full_path(fnamemodify(l:config_path, ':h:h:h'))
  let l:output_value = s:to_string_or_empty(get(l:config, s:cmake_config_output_key, s:cmake_config_default_output))
  let l:preset_value = trim(s:to_string_or_empty(get(l:config, s:cmake_config_preset_key, '')))
  if empty(trim(l:output_value))
    let l:output_value = s:cmake_config_default_output
  endif

  let l:build_directory = s:resolve_path(l:output_value, l:project_root)
  if !isdirectory(l:build_directory)
    throw 'Build directory not found: ' . l:build_directory
  endif

  let l:scan_directory = s:target_scan_directory(l:build_directory, l:preset_value)
  let l:targets = s:available_targets(l:build_directory, l:preset_value)
  if empty(l:targets)
    throw 'No selectable targets found in directory: ' . l:scan_directory
  endif

  let l:selected_target = s:select_item_from_list('Select CMake target:', l:targets)
  if empty(l:selected_target)
    call s:write_info('Target selection canceled.')
    return
  endif

  let l:target_directory = s:resolve_selected_target_directory(l:selected_target, l:scan_directory)
  let l:source_file_path = s:ensure_target_compile_commands(
        \ l:selected_target,
        \ l:target_directory,
        \ l:build_directory,
        \ l:scan_directory)
  call s:copy_compile_commands_file(l:source_file_path, l:build_directory)
  call s:set_config_value(s:cmake_config_target_key, l:selected_target, 1)
endfunction

function! s:available_targets(build_directory, preset_value) abort
  if empty(trim(a:build_directory))
    throw 'Build directory cannot be empty.'
  endif

  let l:scan_directory = s:target_scan_directory(a:build_directory, a:preset_value)
  let l:glob_pattern = s:path_join(s:path_join(l:scan_directory, '**'), '*.dir')
  let l:directory_matches = glob(l:glob_pattern, 0, 1)
  let l:targets = []
  let l:seen = {}

  for l:match in l:directory_matches
    if !isdirectory(l:match)
      continue
    endif

    let l:normalized_match = s:normalize_full_path(l:match)
    if !s:is_sub_path_of(l:normalized_match, l:scan_directory)
      continue
    endif

    let l:relative_path = s:relative_path(l:normalized_match, l:scan_directory)
    let l:relative_path = substitute(l:relative_path, '\\', '/', 'g')
    if l:relative_path !~# '\v(^|/)CMakeFiles/[^/]+\.dir$'
      continue
    endif

    let l:target_path = substitute(l:relative_path, '\.dir$', '', '')

    if l:target_path =~# '^CMakeFiles/'
      let l:target_path = strpart(l:target_path, strlen('CMakeFiles/'))
    elseif l:target_path =~# '/CMakeFiles/'
      let l:target_path = substitute(l:target_path, '^.\{-}/CMakeFiles/', '', '')
    endif

    if empty(trim(l:target_path))
      continue
    endif

    let l:target_path = substitute(l:target_path, '/\+', '/', 'g')
    if empty(trim(l:target_path))
      continue
    endif

    if has_key(l:seen, l:target_path)
      continue
    endif

    let l:seen[l:target_path] = 1
    call add(l:targets, l:target_path)
  endfor

  call sort(l:targets)
  return l:targets
endfunction

function! s:target_scan_directory(build_directory, preset_value) abort
  if empty(trim(a:build_directory))
    throw 'Build directory cannot be empty.'
  endif

  let l:preset_value = trim(s:to_string_or_empty(a:preset_value))
  if empty(l:preset_value)
    return a:build_directory
  endif

  let l:preset_directory = s:resolve_path(l:preset_value, a:build_directory)
  return isdirectory(l:preset_directory) ? l:preset_directory : a:build_directory
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

function! s:resolve_root_compile_commands_path(build_directory, scan_directory) abort
  if empty(trim(a:build_directory))
    throw 'Build directory cannot be empty.'
  endif
  if empty(trim(a:scan_directory))
    throw 'Build directory cannot be empty.'
  endif

  let l:candidates = [s:path_join(a:scan_directory, s:default_input_filename)]
  if !s:path_equals(a:scan_directory, a:build_directory)
    call add(l:candidates, s:path_join(a:build_directory, s:default_input_filename))
  endif

  for l:candidate in l:candidates
    if filereadable(l:candidate)
      return l:candidate
    endif
  endfor

  if len(l:candidates) == 1
    throw 'Root ' . s:default_input_filename . ' not found at: ' . l:candidates[0]
  endif

  throw 'Root ' . s:default_input_filename . ' not found at: '
        \ . l:candidates[0] . ' or ' . l:candidates[1]
endfunction

function! s:ensure_target_compile_commands(target_name, target_directory, build_directory, scan_directory) abort
  if empty(trim(a:target_name))
    throw 'Missing required argument: <target>.'
  endif
  if empty(trim(a:target_directory))
    throw 'Target directory cannot be empty.'
  endif
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
        \ a:scan_directory)
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

  let l:preset_value = s:to_string_or_empty(get(l:config, s:cmake_config_preset_key, ''))
  let l:build_directory = s:resolve_path(l:output_value, l:project_root)
  let l:argv = [
        \ 'cmake',
        \ '-S',
        \ l:project_root,
        \ '-B',
        \ l:build_directory,
        \ '-DCMAKE_BUILD_TYPE=' . l:build_value
        \ ]

  if !empty(trim(l:preset_value))
    call add(l:argv, '--preset')
    call add(l:argv, l:preset_value)
  endif

  call s:run_shell_command(l:argv)
  call s:write_info('Generated build system in ' . s:relative_path(l:build_directory, l:project_root))
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

  let l:build_directory = s:resolve_path(l:output_value, l:project_root)
  let l:preset_value = trim(s:to_string_or_empty(get(l:config, s:cmake_config_preset_key, '')))
  let l:target_value = trim(s:to_string_or_empty(get(l:config, s:cmake_config_target_key, '')))

  let l:argv = ['cmake', '--build', l:build_directory]
  if !empty(l:preset_value)
    call add(l:argv, '--preset')
    call add(l:argv, l:preset_value)
  endif

  if !empty(l:target_value)
    call add(l:argv, '--target')
    call add(l:argv, l:target_value)
  endif

  call s:run_shell_command(l:argv)
  call s:write_info('Built project in ' . s:relative_path(l:build_directory, l:project_root))
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

  throw '.vim/.cmake/.config.json not found in current directory or any parent directory.'
endfunction

function! s:resolve_or_create_local_config_for_generate(start_directory, project_root) abort
  try
    return s:resolve_existing_local_config_path(a:start_directory)
  catch
    let l:message = s:format_exception(v:exception)
    if stridx(l:message, '.vim/.cmake/.config.json not found in current directory or any parent directory.') < 0
      throw l:message
    endif
  endtry

  let l:config_path = s:cmake_config_path(a:project_root)
  let l:config = s:default_cmake_config_payload()
  call s:apply_default_cmake_config_values(l:config)

  call mkdir(fnamemodify(l:config_path, ':h'), 'p')
  call s:write_json_file(l:config_path, l:config)
  call s:write_info('Created default config: ' . s:relative_path(l:config_path, a:project_root))

  return l:config_path
endfunction

function! s:set_config_value(key, value, ...) abort
  let l:require_existing = get(a:000, 0, 0)
  let l:working_directory = s:normalize_full_path(getcwd())
  let l:config_path = l:require_existing
        \ ? s:resolve_existing_local_config_path(l:working_directory)
        \ : s:cmake_config_path(l:working_directory)
  let l:config_root = s:normalize_full_path(fnamemodify(l:config_path, ':h:h:h'))
  let l:config = filereadable(l:config_path)
        \ ? s:read_json_object(l:config_path)
        \ : s:default_cmake_config_payload()

  let l:config[a:key] = a:value
  call mkdir(fnamemodify(l:config_path, ':h'), 'p')
  call s:write_json_file(l:config_path, l:config)

  call s:write_info('Set ' . a:key . ' "' . a:value . '" in ' . s:relative_path(l:config_path, l:config_root))
endfunction

function! s:apply_default_cmake_config_values(config) abort
  let a:config[s:cmake_config_output_key] = s:cmake_config_default_output
  let a:config[s:cmake_config_preset_key] = ''
  let a:config[s:cmake_config_build_config_key] = s:cmake_config_default_build
endfunction

function! s:default_cmake_config_payload() abort
  return {}
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

function! s:cmake_config_path(project_root) abort
  return s:path_join(a:project_root, s:cmake_config_relative_path)
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

function! s:format_exception(exception_text) abort
  let l:message = substitute(a:exception_text, '^Vim\%((\a\+)\)\?:', '', '')
  return trim(l:message)
endfunction
