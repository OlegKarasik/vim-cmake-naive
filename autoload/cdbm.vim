let s:default_input_filename = 'compile_commands.json'
let s:default_output_filename = 'compile_commands.json'
let s:cmake_config_relative_path = '.vim/.cmake/.config.json'
let s:cmake_config_preset_key = 'preset'
let s:cmake_config_build_config_key = 'build'
let s:cmake_config_output_key = 'output'
let s:cmake_config_default_build = 'Debug'
let s:cmake_config_default_output = 'build'
let s:target_directory_pattern = '\v^(.{-}CMakeFiles[\\/][^\\/]+\.dir)([\\/]|$)'
let s:is_windows = has('win32') || has('win64') || has('win32unix')

function! cdbm#split(...) abort
  try
    let l:options = s:parse_split_args(a:000)
    call s:run_split(l:options)
  catch
    call s:write_error(s:format_exception(v:exception))
  endtry
endfunction

function! cdbm#switch(...) abort
  try
    let l:options = s:parse_switch_args(a:000)
    call s:run_switch(l:options)
  catch
    call s:write_error(s:format_exception(v:exception))
  endtry
endfunction

function! cdbm#cmake_config() abort
  try
    call s:run_cmake_config()
  catch
    call s:write_error(s:format_exception(v:exception))
  endtry
endfunction

function! cdbm#set_config_preset(preset) abort
  try
    call s:run_set_config_preset(a:preset)
  catch
    call s:write_error(s:format_exception(v:exception))
  endtry
endfunction

function! cdbm#reset_config_preset() abort
  try
    call s:run_reset_config_preset()
  catch
    call s:write_error(s:format_exception(v:exception))
  endtry
endfunction

function! cdbm#set_config_build_config(build_config) abort
  try
    call s:run_set_config_build_config(a:build_config)
  catch
    call s:write_error(s:format_exception(v:exception))
  endtry
endfunction

function! cdbm#set_config_output(output) abort
  try
    call s:run_set_config_output(a:output)
  catch
    call s:write_error(s:format_exception(v:exception))
  endtry
endfunction

function! cdbm#cmake_config_default() abort
  try
    call s:run_cmake_config_default()
  catch
    call s:write_error(s:format_exception(v:exception))
  endtry
endfunction

function! cdbm#generate() abort
  try
    call s:run_generate()
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
    throw 'Usage: :CdbmSwitch <build-directory> <target> [--output <path>]'
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
  if !filereadable(l:source_file_path)
    throw 'Source file not found: ' . l:source_file_path
  endif

  call mkdir(l:output_directory, 'p')
  let l:destination_file_path = s:path_join(l:output_directory, s:default_input_filename)
  call writefile(readfile(l:source_file_path, 'b'), l:destination_file_path, 'b')

  call s:write_info('Copied ' . s:default_input_filename . ' to ' . l:destination_file_path)
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
  echom '[cdbm] ' . a:message
endfunction

function! s:write_error(message) abort
  echohl ErrorMsg
  echom '[cdbm] ' . a:message
  echohl None
endfunction

function! s:format_exception(exception_text) abort
  let l:message = substitute(a:exception_text, '^Vim\%((\a\+)\)\?:', '', '')
  return trim(l:message)
endfunction
