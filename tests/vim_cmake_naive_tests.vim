function! s:path_join(left, right) abort
  if empty(a:left)
    return a:right
  endif
  if empty(a:right)
    return a:left
  endif

  let l:left = substitute(a:left, '/\+$', '', '')
  let l:right = substitute(a:right, '^/\+', '', '')
  return l:left . '/' . l:right
endfunction

function! s:write_json(path, value) abort
  call mkdir(fnamemodify(a:path, ':h'), 'p')
  call writefile([json_encode(a:value)], a:path, 'b')
endfunction

function! s:read_json(path) abort
  return json_decode(join(readfile(a:path, 'b'), "\n"))
endfunction

function! s:fixture_entries() abort
  return [
        \ {
        \   'directory': '.',
        \   'command': 'clang++ -I../include -o CMakeFiles/app.dir/src/main.cpp.o -c ../src/main.cpp',
        \   'file': '../src/main.cpp',
        \   'output': 'CMakeFiles/app.dir/src/main.cpp.o'
        \ },
        \ {
        \   'directory': '.',
        \   'arguments': [
        \     'clang++',
        \     '-I../include',
        \     '-o',
        \     'lib/CMakeFiles/mylib.dir/foo.cpp.o',
        \     '-c',
        \     '../lib/foo.cpp'
        \   ],
        \   'file': '../lib/foo.cpp'
        \ }
        \ ]
endfunction

function! s:create_build_fixture() abort
  let l:root = tempname()
  call mkdir(l:root, 'p')
  let l:build = s:path_join(l:root, 'build')
  call mkdir(l:build, 'p')
  return { 'root': l:root, 'build': l:build }
endfunction

function! s:create_cmake_project_fixture() abort
  let l:root = tempname()
  call mkdir(l:root, 'p')
  call writefile(['cmake_minimum_required(VERSION 3.20)', 'project(vim_cmake_naive_test)'], s:path_join(l:root, 'CMakeLists.txt'), 'b')
  return { 'root': l:root }
endfunction

function! s:write_cmake_presets(path, configure_presets) abort
  call s:write_json(a:path, {
        \ 'version': 6,
        \ 'configurePresets': a:configure_presets
        \ })
endfunction

function! s:normalized_path(path) abort
  let l:full_path = simplify(resolve(fnamemodify(a:path, ':p')))
  let l:full_path = substitute(l:full_path, '\\', '/', 'g')
  return substitute(l:full_path, '/\+$', '', '')
endfunction

function! s:create_fake_cmake_script(root, args_output_path, exit_code) abort
  let l:bin_dir = s:path_join(a:root, 'fake-bin')
  call mkdir(l:bin_dir, 'p')
  let l:script_path = s:path_join(l:bin_dir, 'cmake')
  call writefile([
        \ '#!/bin/sh',
        \ 'printf "%s\n" "$@" > ' . shellescape(a:args_output_path),
        \ 'exit ' . string(a:exit_code)
        \ ], l:script_path, 'b')
  call system('chmod +x ' . shellescape(l:script_path))
  return l:bin_dir
endfunction

function! s:read_non_empty_lines(path) abort
  return filter(readfile(a:path, 'b'), '!empty(v:val)')
endfunction

function! s:wait_for_file(path, timeout_ms) abort
  let l:elapsed = 0
  while !filereadable(a:path) && l:elapsed < a:timeout_ms
    sleep 10m
    let l:elapsed += 10
  endwhile

  return filereadable(a:path)
endfunction

function! s:wait_for_captured_build_terminal_output(fragment, timeout_ms) abort
  let l:elapsed = 0
  while l:elapsed < a:timeout_ms
    let l:terminal = get(g:, 'vim_cmake_naive_test_last_build_terminal', {})
    let l:terminal_text = join(get(l:terminal, 'lines', []), "\n")
    if stridx(l:terminal_text, a:fragment) >= 0
      return l:terminal
    endif
    sleep 10m
    let l:elapsed += 10
  endwhile

  return get(g:, 'vim_cmake_naive_test_last_build_terminal', {})
endfunction

function! s:wait_for_running_terminal_window(timeout_ms) abort
  if !exists('*getwininfo') || !exists('*term_getstatus')
    return 0
  endif

  let l:elapsed = 0
  while l:elapsed < a:timeout_ms
    for l:window_info in getwininfo()
      let l:buffer_number = get(l:window_info, 'bufnr', -1)
      if l:buffer_number <= 0
        continue
      endif
      if getbufvar(l:buffer_number, '&buftype', '') !=# 'terminal'
        continue
      endif
      if stridx(term_getstatus(l:buffer_number), 'running') >= 0
        return get(l:window_info, 'winid', 0)
      endif
    endfor
    sleep 10m
    let l:elapsed += 10
  endwhile

  return 0
endfunction

function! s:unique_id(prefix) abort
  return a:prefix . substitute(reltimestr(reltime()), '[^0-9A-Za-z]', '', 'g')
endfunction

function! s:test_split_writes_target_files() abort
  let l:fixture = s:create_build_fixture()
  try
    let l:input_path = s:path_join(l:fixture.build, 'compile_commands.json')
    call s:write_json(l:input_path, s:fixture_entries())

    call vim_cmake_naive#split(l:fixture.build)

    let l:app_output = s:path_join(
          \ s:path_join(s:path_join(l:fixture.build, 'CMakeFiles'), 'app.dir'),
          \ 'compile_commands.json')
    let l:lib_output = s:path_join(
          \ s:path_join(s:path_join(s:path_join(l:fixture.build, 'lib'), 'CMakeFiles'), 'mylib.dir'),
          \ 'compile_commands.json')

    call assert_true(filereadable(l:app_output), 'Expected app target output to be written.')
    call assert_true(filereadable(l:lib_output), 'Expected mylib target output to be written.')

    let l:app_entries = s:read_json(l:app_output)
    let l:lib_entries = s:read_json(l:lib_output)

    call assert_equal(1, len(l:app_entries))
    call assert_equal(1, len(l:lib_entries))
    call assert_equal('../src/main.cpp', get(l:app_entries[0], 'file', ''))
    call assert_equal('../lib/foo.cpp', get(l:lib_entries[0], 'file', ''))
  finally
    call delete(l:fixture.root, 'rf')
  endtry
endfunction

function! s:test_split_handles_symlinked_build_directory() abort
  if !has('unix')
    return
  endif

  let l:root = tempname()
  call mkdir(l:root, 'p')
  let l:real_build = s:path_join(l:root, 'real-build')
  let l:link_build = s:path_join(l:root, 'build-link')
  call mkdir(l:real_build, 'p')

  try
    if exists('*symlink')
      call symlink(l:real_build, l:link_build)
    elseif executable('ln')
      call system('ln -s ' . shellescape(l:real_build) . ' ' . shellescape(l:link_build))
    endif

    if !isdirectory(l:link_build)
      return
    endif

    call s:write_json(s:path_join(l:link_build, 'compile_commands.json'), s:fixture_entries())
    call vim_cmake_naive#split(l:link_build)

    let l:app_output = s:path_join(
          \ s:path_join(s:path_join(l:real_build, 'CMakeFiles'), 'app.dir'),
          \ 'compile_commands.json')
    let l:lib_output = s:path_join(
          \ s:path_join(s:path_join(s:path_join(l:real_build, 'lib'), 'CMakeFiles'), 'mylib.dir'),
          \ 'compile_commands.json')

    call assert_true(filereadable(l:app_output), 'Expected app target output via symlinked build path.')
    call assert_true(filereadable(l:lib_output), 'Expected mylib target output via symlinked build path.')
  finally
    call delete(l:root, 'rf')
  endtry
endfunction

function! s:test_split_dry_run_does_not_write_files() abort
  let l:fixture = s:create_build_fixture()
  try
    let l:input_path = s:path_join(l:fixture.build, 'compile_commands.json')
    call s:write_json(l:input_path, s:fixture_entries())

    call vim_cmake_naive#split(l:fixture.build, '--dry-run')

    let l:app_output = s:path_join(
          \ s:path_join(s:path_join(l:fixture.build, 'CMakeFiles'), 'app.dir'),
          \ 'compile_commands.json')
    let l:lib_output = s:path_join(
          \ s:path_join(s:path_join(s:path_join(l:fixture.build, 'lib'), 'CMakeFiles'), 'mylib.dir'),
          \ 'compile_commands.json')

    call assert_false(filereadable(l:app_output), 'Dry-run should not write app output file.')
    call assert_false(filereadable(l:lib_output), 'Dry-run should not write library output file.')
  finally
    call delete(l:fixture.root, 'rf')
  endtry
endfunction

function! s:test_split_honors_input_and_output_name() abort
  let l:fixture = s:create_build_fixture()
  try
    let l:input_path = s:path_join(l:fixture.build, 'all_commands.json')
    call s:write_json(l:input_path, s:fixture_entries())

    call vim_cmake_naive#split(
          \ l:fixture.build,
          \ '--input',
          \ l:input_path,
          \ '--output-name',
          \ 'target_commands.json')

    let l:app_output = s:path_join(
          \ s:path_join(s:path_join(l:fixture.build, 'CMakeFiles'), 'app.dir'),
          \ 'target_commands.json')
    let l:lib_output = s:path_join(
          \ s:path_join(s:path_join(s:path_join(l:fixture.build, 'lib'), 'CMakeFiles'), 'mylib.dir'),
          \ 'target_commands.json')
    let l:default_output = s:path_join(
          \ s:path_join(s:path_join(l:fixture.build, 'CMakeFiles'), 'app.dir'),
          \ 'compile_commands.json')

    call assert_true(filereadable(l:app_output))
    call assert_true(filereadable(l:lib_output))
    call assert_false(filereadable(l:default_output))
  finally
    call delete(l:fixture.root, 'rf')
  endtry
endfunction

function! s:test_split_honors_equals_style_input_and_output_name() abort
  let l:fixture = s:create_build_fixture()
  try
    let l:input_path = s:path_join(l:fixture.build, 'all_commands.json')
    call s:write_json(l:input_path, s:fixture_entries())

    call vim_cmake_naive#split(
          \ l:fixture.build,
          \ '--input=' . l:input_path,
          \ '--output-name=target_commands_equals.json')

    let l:app_output = s:path_join(
          \ s:path_join(s:path_join(l:fixture.build, 'CMakeFiles'), 'app.dir'),
          \ 'target_commands_equals.json')
    let l:lib_output = s:path_join(
          \ s:path_join(s:path_join(s:path_join(l:fixture.build, 'lib'), 'CMakeFiles'), 'mylib.dir'),
          \ 'target_commands_equals.json')

    call assert_true(filereadable(l:app_output))
    call assert_true(filereadable(l:lib_output))
  finally
    call delete(l:fixture.root, 'rf')
  endtry
endfunction

function! s:test_switch_copies_to_build_root_by_default() abort
  let l:fixture = s:create_build_fixture()
  try
    let l:target_dir = s:path_join(s:path_join(l:fixture.build, 'CMakeFiles'), 'app.dir')
    let l:source_path = s:path_join(l:target_dir, 'compile_commands.json')
    call s:write_json(l:source_path, [{'file': '../src/main.cpp', 'command': 'clang++ -c ../src/main.cpp'}])

    call vim_cmake_naive#switch(l:fixture.build, 'app')

    let l:destination_path = s:path_join(l:fixture.build, 'compile_commands.json')
    call assert_true(filereadable(l:destination_path))
    call assert_equal(readfile(l:source_path, 'b'), readfile(l:destination_path, 'b'))
  finally
    call delete(l:fixture.root, 'rf')
  endtry
endfunction

function! s:test_switch_honors_output_directory() abort
  let l:fixture = s:create_build_fixture()
  try
    let l:target_dir = s:path_join(s:path_join(l:fixture.build, 'CMakeFiles'), 'app.dir')
    let l:source_path = s:path_join(l:target_dir, 'compile_commands.json')
    call s:write_json(l:source_path, [{'file': '../src/main.cpp', 'arguments': ['clang++', '-c', '../src/main.cpp']}])

    let l:output_dir = s:path_join(l:fixture.root, 'selected')
    call vim_cmake_naive#switch(
          \ l:fixture.build,
          \ 'app',
          \ '--output',
          \ l:output_dir)

    let l:destination_path = s:path_join(l:output_dir, 'compile_commands.json')
    call assert_true(filereadable(l:destination_path))
    call assert_equal(readfile(l:source_path, 'b'), readfile(l:destination_path, 'b'))
  finally
    call delete(l:fixture.root, 'rf')
  endtry
endfunction

function! s:test_switch_honors_equals_style_output_directory() abort
  let l:fixture = s:create_build_fixture()
  try
    let l:target_dir = s:path_join(s:path_join(l:fixture.build, 'CMakeFiles'), 'app.dir')
    let l:source_path = s:path_join(l:target_dir, 'compile_commands.json')
    call s:write_json(l:source_path, [{'file': '../src/main.cpp', 'arguments': ['clang++', '-c', '../src/main.cpp']}])

    let l:output_dir = s:path_join(l:fixture.root, 'selected-equals')
    call vim_cmake_naive#switch(
          \ l:fixture.build,
          \ 'app',
          \ '--output=' . l:output_dir)

    let l:destination_path = s:path_join(l:output_dir, 'compile_commands.json')
    call assert_true(filereadable(l:destination_path))
    call assert_equal(readfile(l:source_path, 'b'), readfile(l:destination_path, 'b'))
  finally
    call delete(l:fixture.root, 'rf')
  endtry
endfunction

function! s:test_split_reports_missing_input_file() abort
  let l:fixture = s:create_build_fixture()
  try
    let l:missing_basename = s:unique_id('missing_input_') . '.json'
    let l:missing_input = s:path_join(l:fixture.build, l:missing_basename)

    call vim_cmake_naive#split(l:fixture.build, '--input', l:missing_input)

    let l:messages = execute('messages')
    call assert_true(stridx(l:messages, '[vim-cmake-naive] Input file not found:') >= 0)
    call assert_true(stridx(l:messages, l:missing_basename) >= 0)
  finally
    call delete(l:fixture.root, 'rf')
  endtry
endfunction

function! s:test_switch_reports_missing_target_directory() abort
  let l:fixture = s:create_build_fixture()
  try
    let l:missing_target = s:unique_id('missing_target_')
    call vim_cmake_naive#switch(l:fixture.build, l:missing_target)

    let l:messages = execute('messages')
    call assert_true(stridx(l:messages, 'target directory not found for') >= 0)
    call assert_true(stridx(l:messages, l:missing_target) >= 0)
    call assert_false(filereadable(s:path_join(l:fixture.build, 'compile_commands.json')))
  finally
    call delete(l:fixture.root, 'rf')
  endtry
endfunction

function! s:test_cmake_config_creates_default_local_config() abort
  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()

  try
    execute 'cd ' . fnameescape(l:fixture.root)
    execute 'silent CMakeConfig'

    let l:config_path = s:path_join(l:fixture.root, '.vim/.cmake/.config.json')
    call assert_true(filereadable(l:config_path), 'Expected .vim/.cmake/.config.json to be created.')
    call assert_equal({}, s:read_json(l:config_path))
  finally
    execute 'cd ' . fnameescape(l:initial_cwd)
    call delete(l:fixture.root, 'rf')
  endtry
endfunction

function! s:test_cmake_config_preserves_existing_file() abort
  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()

  try
    let l:config_path = s:path_join(l:fixture.root, '.vim/.cmake/.config.json')
    call s:write_json(l:config_path, {'keep': 1, 'nested': {'enabled': 1}})

    execute 'cd ' . fnameescape(l:fixture.root)
    execute 'silent CMakeConfig'

    call assert_equal({'keep': 1, 'nested': {'enabled': 1}}, s:read_json(l:config_path))
  finally
    execute 'cd ' . fnameescape(l:initial_cwd)
    call delete(l:fixture.root, 'rf')
  endtry
endfunction

function! s:test_cmake_set_config_preset_creates_config_with_preset() abort
  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()

  try
    execute 'cd ' . fnameescape(l:fixture.root)
    execute 'silent CMakeConfig'
    execute 'silent CMakeConfigSetPreset debug'

    let l:config_path = s:path_join(l:fixture.root, '.vim/.cmake/.config.json')
    call assert_true(filereadable(l:config_path), 'Expected .vim/.cmake/.config.json to be created.')
    call assert_equal({'preset': 'debug'}, s:read_json(l:config_path))
  finally
    execute 'cd ' . fnameescape(l:initial_cwd)
    call delete(l:fixture.root, 'rf')
  endtry
endfunction

function! s:test_cmake_set_config_preset_preserves_existing_keys() abort
  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()

  try
    let l:config_path = s:path_join(l:fixture.root, '.vim/.cmake/.config.json')
    call s:write_json(l:config_path, {'keep': 1, 'nested': {'enabled': 1}, 'preset': 'old'})

    execute 'cd ' . fnameescape(l:fixture.root)
    call vim_cmake_naive#set_config_preset('Release With DebInfo')

    call assert_equal(
          \ {'keep': 1, 'nested': {'enabled': 1}, 'preset': 'Release With DebInfo'},
          \ s:read_json(l:config_path))
  finally
    execute 'cd ' . fnameescape(l:initial_cwd)
    call delete(l:fixture.root, 'rf')
  endtry
endfunction

function! s:test_cmake_reset_config_preset_creates_config_with_empty_preset() abort
  let l:root = tempname()
  call mkdir(l:root, 'p')
  let l:initial_cwd = getcwd()

  try
    execute 'cd ' . fnameescape(l:root)
    execute 'silent CMakeResetPreset'

    let l:config_path = s:path_join(l:root, '.vim/.cmake/.config.json')
    call assert_true(filereadable(l:config_path), 'Expected .vim/.cmake/.config.json to be created.')
    call assert_equal({'preset': ''}, s:read_json(l:config_path))
  finally
    execute 'cd ' . fnameescape(l:initial_cwd)
    call delete(l:root, 'rf')
  endtry
endfunction

function! s:test_cmake_reset_config_preset_preserves_other_keys() abort
  let l:root = tempname()
  call mkdir(l:root, 'p')
  let l:initial_cwd = getcwd()

  try
    let l:config_path = s:path_join(l:root, '.vim/.cmake/.config.json')
    call s:write_json(l:config_path, {'keep': 1, 'nested': {'enabled': 1}, 'preset': 'debug'})

    execute 'cd ' . fnameescape(l:root)
    call vim_cmake_naive#reset_config_preset()

    call assert_equal(
          \ {'keep': 1, 'nested': {'enabled': 1}, 'preset': ''},
          \ s:read_json(l:config_path))
  finally
    execute 'cd ' . fnameescape(l:initial_cwd)
    call delete(l:root, 'rf')
  endtry
endfunction

function! s:test_cmake_reset_config_target_creates_config_with_empty_target() abort
  let l:root = tempname()
  call mkdir(l:root, 'p')
  let l:initial_cwd = getcwd()

  try
    execute 'cd ' . fnameescape(l:root)
    execute 'silent CMakeResetTarget'

    let l:config_path = s:path_join(l:root, '.vim/.cmake/.config.json')
    call assert_true(filereadable(l:config_path), 'Expected .vim/.cmake/.config.json to be created.')
    call assert_equal({'target': ''}, s:read_json(l:config_path))
  finally
    execute 'cd ' . fnameescape(l:initial_cwd)
    call delete(l:root, 'rf')
  endtry
endfunction

function! s:test_cmake_reset_config_target_preserves_other_keys() abort
  let l:root = tempname()
  call mkdir(l:root, 'p')
  let l:initial_cwd = getcwd()

  try
    let l:config_path = s:path_join(l:root, '.vim/.cmake/.config.json')
    call s:write_json(l:config_path, {'keep': 1, 'nested': {'enabled': 1}, 'target': 'app'})

    execute 'cd ' . fnameescape(l:root)
    call vim_cmake_naive#reset_config_target()

    call assert_equal(
          \ {'keep': 1, 'nested': {'enabled': 1}, 'target': ''},
          \ s:read_json(l:config_path))
  finally
    execute 'cd ' . fnameescape(l:initial_cwd)
    call delete(l:root, 'rf')
  endtry
endfunction

function! s:test_cmake_set_config_build_config_creates_config_with_value() abort
  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()

  try
    execute 'cd ' . fnameescape(l:fixture.root)
    execute 'silent CMakeConfig'
    execute 'silent CMakeConfigSetBuild Debug'

    let l:config_path = s:path_join(l:fixture.root, '.vim/.cmake/.config.json')
    call assert_true(filereadable(l:config_path), 'Expected .vim/.cmake/.config.json to be created.')
    call assert_equal({'build': 'Debug'}, s:read_json(l:config_path))
  finally
    execute 'cd ' . fnameescape(l:initial_cwd)
    call delete(l:fixture.root, 'rf')
  endtry
endfunction

function! s:test_cmake_set_config_build_config_preserves_other_keys() abort
  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()

  try
    let l:config_path = s:path_join(l:fixture.root, '.vim/.cmake/.config.json')
    call s:write_json(l:config_path, {'keep': 1, 'preset': 'debug', 'build': 'Release'})

    execute 'cd ' . fnameescape(l:fixture.root)
    call vim_cmake_naive#set_config_build_config('RelWithDebInfo')

    call assert_equal(
          \ {'keep': 1, 'preset': 'debug', 'build': 'RelWithDebInfo'},
          \ s:read_json(l:config_path))
  finally
    execute 'cd ' . fnameescape(l:initial_cwd)
    call delete(l:fixture.root, 'rf')
  endtry
endfunction

function! s:test_cmake_set_config_output_creates_config_with_value() abort
  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()

  try
    execute 'cd ' . fnameescape(l:fixture.root)
    execute 'silent CMakeConfig'
    execute 'silent CMakeConfigSetOutput build'

    let l:config_path = s:path_join(l:fixture.root, '.vim/.cmake/.config.json')
    call assert_true(filereadable(l:config_path), 'Expected .vim/.cmake/.config.json to be created.')
    call assert_equal({'output': 'build'}, s:read_json(l:config_path))
  finally
    execute 'cd ' . fnameescape(l:initial_cwd)
    call delete(l:fixture.root, 'rf')
  endtry
endfunction

function! s:test_cmake_set_config_output_preserves_other_keys() abort
  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()

  try
    let l:config_path = s:path_join(l:fixture.root, '.vim/.cmake/.config.json')
    call s:write_json(l:config_path, {'preset': 'debug', 'build': 'RelWithDebInfo', 'output': 'old'})

    execute 'cd ' . fnameescape(l:fixture.root)
    call vim_cmake_naive#set_config_output('out/build')

    call assert_equal(
          \ {'preset': 'debug', 'build': 'RelWithDebInfo', 'output': 'out/build'},
          \ s:read_json(l:config_path))
  finally
    execute 'cd ' . fnameescape(l:initial_cwd)
    call delete(l:fixture.root, 'rf')
  endtry
endfunction

function! s:test_cmake_set_commands_use_nearest_existing_local_config() abort
  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()

  try
    execute 'cd ' . fnameescape(l:fixture.root)
    execute 'silent CMakeConfig'

    let l:deep_dir = s:path_join(s:path_join(l:fixture.root, 'src'), 'nested')
    call mkdir(l:deep_dir, 'p')
    execute 'cd ' . fnameescape(l:deep_dir)

    execute 'silent CMakeConfigSetPreset release'
    execute 'silent CMakeConfigSetBuild RelWithDebInfo'
    execute 'silent CMakeConfigSetOutput out/build'

    let l:root_config_path = s:path_join(l:fixture.root, '.vim/.cmake/.config.json')
    let l:deep_config_path = s:path_join(l:deep_dir, '.vim/.cmake/.config.json')
    let l:config = s:read_json(l:root_config_path)

    call assert_equal('release', get(l:config, 'preset', ''))
    call assert_equal('RelWithDebInfo', get(l:config, 'build', ''))
    call assert_equal('out/build', get(l:config, 'output', ''))
    call assert_false(filereadable(l:deep_config_path), 'Set commands should update nearest existing parent config, not create nested config.')
  finally
    execute 'cd ' . fnameescape(l:initial_cwd)
    call delete(l:fixture.root, 'rf')
  endtry
endfunction

function! s:test_cmake_set_commands_error_when_no_local_config_found() abort
  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()

  try
    let l:deep_dir = s:path_join(s:path_join(l:fixture.root, 'x'), 'y')
    call mkdir(l:deep_dir, 'p')
    execute 'cd ' . fnameescape(l:deep_dir)
    call vim_cmake_naive#set_config_preset('debug')
    call vim_cmake_naive#set_config_build_config('Debug')
    call vim_cmake_naive#set_config_output('build')

    let l:messages = execute('messages')
    call assert_true(stridx(l:messages, '.vim/.cmake/.config.json not found in current directory or any parent directory.') >= 0)
    call assert_false(filereadable(s:path_join(l:fixture.root, '.vim/.cmake/.config.json')))
  finally
    execute 'cd ' . fnameescape(l:initial_cwd)
    call delete(l:fixture.root, 'rf')
  endtry
endfunction

function! s:test_cmake_commands_report_running_command_lock() abort
  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()
  let l:initial_forced_running_command = get(g:, 'vim_cmake_naive_test_forced_running_cmake_command', v:null)

  try
    execute 'cd ' . fnameescape(l:fixture.root)
    let g:vim_cmake_naive_test_forced_running_cmake_command = 'CMakeBuild'

    call vim_cmake_naive#cmake_config()
    call vim_cmake_naive#cmake_config_default()
    call vim_cmake_naive#switch_preset()
    call vim_cmake_naive#switch_target()
    call vim_cmake_naive#generate()
    call vim_cmake_naive#build()
    call vim_cmake_naive#set_config_preset('dev')
    call vim_cmake_naive#reset_config_preset()
    call vim_cmake_naive#reset_config_target()
    call vim_cmake_naive#set_config_build_config('Debug')
    call vim_cmake_naive#set_config_output('build')
    call vim_cmake_naive#info()
    call vim_cmake_naive#menu()
    call vim_cmake_naive#menu_full()

    let l:messages = execute('messages')
    call assert_true(stridx(l:messages, 'CMake: another command CMakeBuild is already running') >= 0)
    call assert_false(filereadable(s:path_join(l:fixture.root, '.vim/.cmake/.config.json')))
  finally
    if l:initial_forced_running_command is v:null
      unlet! g:vim_cmake_naive_test_forced_running_cmake_command
    else
      let g:vim_cmake_naive_test_forced_running_cmake_command = l:initial_forced_running_command
    endif
    execute 'cd ' . fnameescape(l:initial_cwd)
    call delete(l:fixture.root, 'rf')
  endtry
endfunction

function! s:test_cmake_command_lock_resets_after_command_failure() abort
  let l:root = tempname()
  call mkdir(l:root, 'p')
  let l:initial_cwd = getcwd()

  try
    execute 'cd ' . fnameescape(l:root)
    call vim_cmake_naive#cmake_config()
    call writefile(
          \ ['cmake_minimum_required(VERSION 3.20)', 'project(vim_cmake_naive_lock_reset)'],
          \ s:path_join(l:root, 'CMakeLists.txt'),
          \ 'b')
    call vim_cmake_naive#cmake_config()

    let l:config_path = s:path_join(l:root, '.vim/.cmake/.config.json')
    call assert_true(filereadable(l:config_path), 'Expected CMakeConfig to succeed after prior failure.')
  finally
    execute 'cd ' . fnameescape(l:initial_cwd)
    call delete(l:root, 'rf')
  endtry
endfunction

function! s:test_cmake_config_default_creates_default_values() abort
  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()

  try
    execute 'cd ' . fnameescape(l:fixture.root)
    execute 'silent CMakeConfigDefault'

    let l:config_path = s:path_join(l:fixture.root, '.vim/.cmake/.config.json')
    call assert_true(filereadable(l:config_path), 'Expected .vim/.cmake/.config.json to be created.')
    call assert_equal({'output': 'build', 'preset': '', 'build': 'Debug'}, s:read_json(l:config_path))
  finally
    execute 'cd ' . fnameescape(l:initial_cwd)
    call delete(l:fixture.root, 'rf')
  endtry
endfunction

function! s:test_cmake_config_default_reapplies_defaults_and_preserves_other_keys() abort
  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()

  try
    let l:config_path = s:path_join(l:fixture.root, '.vim/.cmake/.config.json')
    call s:write_json(
          \ l:config_path,
          \ {'output': 'custom-out', 'preset': 'release', 'build': 'RelWithDebInfo', 'keep': 1})

    execute 'cd ' . fnameescape(l:fixture.root)
    call vim_cmake_naive#cmake_config_default()

    call assert_equal(
          \ {'output': 'build', 'preset': '', 'build': 'Debug', 'keep': 1},
          \ s:read_json(l:config_path))
  finally
    execute 'cd ' . fnameescape(l:initial_cwd)
    call delete(l:fixture.root, 'rf')
  endtry
endfunction

function! s:test_cmake_config_uses_nearest_parent_cmakelists() abort
  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()

  try
    let l:src_dir = s:path_join(l:fixture.root, 'src')
    let l:deep_dir = s:path_join(l:src_dir, 'nested')
    call mkdir(l:deep_dir, 'p')

    execute 'cd ' . fnameescape(l:deep_dir)
    execute 'silent CMakeConfig'

    let l:config_path = s:path_join(l:fixture.root, '.vim/.cmake/.config.json')
    let l:wrong_path = s:path_join(l:deep_dir, '.vim/.cmake/.config.json')
    call assert_true(filereadable(l:config_path), 'Expected config to be created at nearest CMakeLists project root.')
    call assert_false(filereadable(l:wrong_path), 'Config should not be created in nested working directory.')
  finally
    execute 'cd ' . fnameescape(l:initial_cwd)
    call delete(l:fixture.root, 'rf')
  endtry
endfunction

function! s:test_cmake_config_errors_when_no_cmakelists_found() abort
  let l:root = tempname()
  call mkdir(l:root, 'p')
  let l:initial_cwd = getcwd()

  try
    execute 'cd ' . fnameescape(l:root)
    call vim_cmake_naive#cmake_config()

    let l:messages = execute('messages')
    call assert_true(stridx(l:messages, 'CMakeLists.txt not found in current directory or any parent directory.') >= 0)
    call assert_false(filereadable(s:path_join(l:root, '.vim/.cmake/.config.json')))
  finally
    execute 'cd ' . fnameescape(l:initial_cwd)
    call delete(l:root, 'rf')
  endtry
endfunction

function! s:test_cmake_config_default_uses_nearest_parent_cmakelists() abort
  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()

  try
    let l:deep_dir = s:path_join(s:path_join(l:fixture.root, 'a'), 'b')
    call mkdir(l:deep_dir, 'p')

    execute 'cd ' . fnameescape(l:deep_dir)
    execute 'silent CMakeConfigDefault'

    let l:config_path = s:path_join(l:fixture.root, '.vim/.cmake/.config.json')
    let l:config = s:read_json(l:config_path)
    call assert_true(filereadable(l:config_path))
    call assert_equal('build', get(l:config, 'output', ''))
    call assert_equal('', get(l:config, 'preset', ''))
    call assert_equal('Debug', get(l:config, 'build', ''))
  finally
    execute 'cd ' . fnameescape(l:initial_cwd)
    call delete(l:fixture.root, 'rf')
  endtry
endfunction

function! s:test_cmake_config_default_errors_when_no_cmakelists_found() abort
  let l:root = tempname()
  call mkdir(l:root, 'p')
  let l:initial_cwd = getcwd()

  try
    execute 'cd ' . fnameescape(l:root)
    call vim_cmake_naive#cmake_config_default()

    let l:messages = execute('messages')
    call assert_true(stridx(l:messages, 'CMakeLists.txt not found in current directory or any parent directory.') >= 0)
    call assert_false(filereadable(s:path_join(l:root, '.vim/.cmake/.config.json')))
  finally
    execute 'cd ' . fnameescape(l:initial_cwd)
    call delete(l:root, 'rf')
  endtry
endfunction

function! s:test_cmake_generate_creates_default_config_and_invokes_cmake() abort
  if !has('unix')
    return
  endif

  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()
  let l:initial_path = $PATH

  try
    let l:args_path = s:path_join(l:fixture.root, 'cmake-args.txt')
    let l:bin_dir = s:create_fake_cmake_script(l:fixture.root, l:args_path, 0)
    let $PATH = l:bin_dir . ':' . l:initial_path

    let l:deep_dir = s:path_join(l:fixture.root, 'src')
    call mkdir(l:deep_dir, 'p')

    execute 'cd ' . fnameescape(l:deep_dir)
    execute 'silent CMakeGenerate'

    let l:config_path = s:path_join(l:fixture.root, '.vim/.cmake/.config.json')
    let l:expected_root = s:normalized_path(l:fixture.root)
    let l:expected_build_dir = s:path_join(l:expected_root, 'build')
    call assert_equal({'output': 'build', 'preset': '', 'build': 'Debug'}, s:read_json(l:config_path))
    call assert_true(s:wait_for_file(l:args_path, 1000), 'Expected fake cmake args file to be created.')
    call assert_equal(
          \ ['-S', l:expected_root, '-B', l:expected_build_dir, '--fresh', '-DCMAKE_BUILD_TYPE=Debug'],
          \ s:read_non_empty_lines(l:args_path))
    call assert_true(isdirectory(l:expected_build_dir), 'Expected output directory to be created.')
  finally
    let $PATH = l:initial_path
    execute 'cd ' . fnameescape(l:initial_cwd)
    call delete(l:fixture.root, 'rf')
  endtry
endfunction

function! s:test_cmake_generate_uses_existing_config_values() abort
  if !has('unix')
    return
  endif

  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()
  let l:initial_path = $PATH

  try
    let l:config_path = s:path_join(l:fixture.root, '.vim/.cmake/.config.json')
    call s:write_json(l:config_path, {'output': 'out/build-dir', 'preset': 'dev', 'build': 'Release'})

    let l:args_path = s:path_join(l:fixture.root, 'cmake-args-existing.txt')
    let l:bin_dir = s:create_fake_cmake_script(l:fixture.root, l:args_path, 0)
    let $PATH = l:bin_dir . ':' . l:initial_path

    let l:deep_dir = s:path_join(s:path_join(l:fixture.root, 'sub'), 'dir')
    call mkdir(l:deep_dir, 'p')
    execute 'cd ' . fnameescape(l:deep_dir)
    execute 'silent CMakeGenerate'

    let l:expected_root = s:normalized_path(l:fixture.root)
    let l:expected_build_dir = s:path_join(l:expected_root, 'out/build-dir')
    let l:expected_preset_build_dir = s:path_join(l:expected_build_dir, 'dev')
    call assert_true(s:wait_for_file(l:args_path, 1000), 'Expected fake cmake args file to be created.')
    call assert_equal(
          \ [
          \   '-S',
          \   l:expected_root,
          \   '-B',
          \   l:expected_build_dir,
          \   '--fresh',
          \   '-DCMAKE_BUILD_TYPE=Release',
          \   '--preset',
          \   'dev'
          \ ],
          \ s:read_non_empty_lines(l:args_path))
    call assert_true(isdirectory(l:expected_build_dir), 'Expected output directory to be created.')
    call assert_true(isdirectory(l:expected_preset_build_dir), 'Expected output/preset directory to be created.')
  finally
    let $PATH = l:initial_path
    execute 'cd ' . fnameescape(l:initial_cwd)
    call delete(l:fixture.root, 'rf')
  endtry
endfunction

function! s:test_cmake_generate_opens_vertical_terminal_with_command_output() abort
  if !has('unix')
    return
  endif

  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()
  let l:initial_path = $PATH
  let l:initial_capture_terminal = get(g:, 'vim_cmake_naive_test_capture_build_terminal', v:null)
  let l:initial_last_terminal = get(g:, 'vim_cmake_naive_test_last_build_terminal', v:null)

  try
    let l:args_path = s:path_join(l:fixture.root, 'cmake-generate-args-preview.txt')
    let l:bin_dir = s:path_join(l:fixture.root, 'fake-bin')
    call mkdir(l:bin_dir, 'p')
    let l:script_path = s:path_join(l:bin_dir, 'cmake')
    call writefile([
          \ '#!/bin/sh',
          \ 'printf "%s\n" "$@" > ' . shellescape(l:args_path),
          \ 'echo "preview-generate-line-1"',
          \ 'echo "preview-generate-line-2"',
          \ 'exit 0'
          \ ], l:script_path, 'b')
    call system('chmod +x ' . shellescape(l:script_path))
    let $PATH = l:bin_dir . ':' . l:initial_path

    execute 'cd ' . fnameescape(l:fixture.root)
    let g:vim_cmake_naive_test_capture_build_terminal = 1
    unlet! g:vim_cmake_naive_test_last_build_terminal
    call vim_cmake_naive#generate()

    let l:terminal = get(g:, 'vim_cmake_naive_test_last_build_terminal', {})
    call assert_equal(1, get(l:terminal, 'is_terminal', 0))
    call assert_equal(1, get(l:terminal, 'is_vertical_split', 0))
    call assert_true(get(l:terminal, 'window_count', 0) >= 2)
    call assert_true(get(l:terminal, 'width', 0) > 0)

    let l:expected_root = s:normalized_path(l:fixture.root)
    let l:expected_build_dir = s:path_join(l:expected_root, 'build')
    call assert_true(s:wait_for_file(l:args_path, 1000), 'Expected fake cmake args file to be created.')
    call assert_equal(
          \ ['-S', l:expected_root, '-B', l:expected_build_dir, '--fresh', '-DCMAKE_BUILD_TYPE=Debug'],
          \ s:read_non_empty_lines(l:args_path))
  finally
    let $PATH = l:initial_path
    if l:initial_capture_terminal is v:null
      unlet! g:vim_cmake_naive_test_capture_build_terminal
    else
      let g:vim_cmake_naive_test_capture_build_terminal = l:initial_capture_terminal
    endif
    if l:initial_last_terminal is v:null
      unlet! g:vim_cmake_naive_test_last_build_terminal
    else
      let g:vim_cmake_naive_test_last_build_terminal = l:initial_last_terminal
    endif
    execute 'cd ' . fnameescape(l:initial_cwd)
    call delete(l:fixture.root, 'rf')
  endtry
endfunction

function! s:test_cmake_generate_reuses_visible_output_window_when_possible() abort
  if !has('unix')
    return
  endif

  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()
  let l:initial_path = $PATH
  let l:initial_capture_terminal = get(g:, 'vim_cmake_naive_test_capture_build_terminal', v:null)
  let l:initial_last_terminal = get(g:, 'vim_cmake_naive_test_last_build_terminal', v:null)

  try
    let l:args_path = s:path_join(l:fixture.root, 'cmake-generate-args-reuse-window.txt')
    let l:bin_dir = s:path_join(l:fixture.root, 'fake-bin')
    call mkdir(l:bin_dir, 'p')
    let l:script_path = s:path_join(l:bin_dir, 'cmake')
    call writefile([
          \ '#!/bin/sh',
          \ 'printf "%s\n" "$@" > ' . shellescape(l:args_path),
          \ 'echo "reuse-window-first-generate"',
          \ 'exit 0'
          \ ], l:script_path, 'b')
    call system('chmod +x ' . shellescape(l:script_path))
    let $PATH = l:bin_dir . ':' . l:initial_path

    execute 'cd ' . fnameescape(l:fixture.root)
    let g:vim_cmake_naive_test_capture_build_terminal = 1
    unlet! g:vim_cmake_naive_test_last_build_terminal
    call vim_cmake_naive#generate()

    let l:first_terminal = s:wait_for_captured_build_terminal_output('reuse-window-first-generate', 1000)
    let l:first_window_id = get(l:first_terminal, 'winid', 0)
    call assert_true(l:first_window_id > 0)

    call writefile([
          \ '#!/bin/sh',
          \ 'printf "%s\n" "$@" > ' . shellescape(l:args_path),
          \ 'echo "reuse-window-second-generate"',
          \ 'exit 0'
          \ ], l:script_path, 'b')
    call system('chmod +x ' . shellescape(l:script_path))

    unlet! g:vim_cmake_naive_test_last_build_terminal
    call vim_cmake_naive#generate()

    let l:second_terminal = s:wait_for_captured_build_terminal_output('reuse-window-second-generate', 1000)
    let l:second_window_id = get(l:second_terminal, 'winid', 0)
    call assert_true(l:second_window_id > 0)
    call assert_equal(l:first_window_id, l:second_window_id)

    let l:expected_root = s:normalized_path(l:fixture.root)
    call assert_true(s:wait_for_file(l:args_path, 1000), 'Expected fake cmake args file to be created.')
    call assert_equal(
          \ ['-S', l:expected_root, '-B', s:path_join(l:expected_root, 'build'), '--fresh', '-DCMAKE_BUILD_TYPE=Debug'],
          \ s:read_non_empty_lines(l:args_path))
  finally
    let $PATH = l:initial_path
    if l:initial_capture_terminal is v:null
      unlet! g:vim_cmake_naive_test_capture_build_terminal
    else
      let g:vim_cmake_naive_test_capture_build_terminal = l:initial_capture_terminal
    endif
    if l:initial_last_terminal is v:null
      unlet! g:vim_cmake_naive_test_last_build_terminal
    else
      let g:vim_cmake_naive_test_last_build_terminal = l:initial_last_terminal
    endif
    execute 'cd ' . fnameescape(l:initial_cwd)
    call delete(l:fixture.root, 'rf')
  endtry
endfunction

function! s:test_cmake_generate_errors_when_no_cmakelists_found() abort
  let l:root = tempname()
  call mkdir(l:root, 'p')
  let l:initial_cwd = getcwd()

  try
    execute 'cd ' . fnameescape(l:root)
    call vim_cmake_naive#generate()

    let l:messages = execute('messages')
    call assert_true(stridx(l:messages, 'CMakeLists.txt not found in current directory or any parent directory.') >= 0)
  finally
    execute 'cd ' . fnameescape(l:initial_cwd)
    call delete(l:root, 'rf')
  endtry
endfunction

function! s:test_cmake_build_creates_default_config_and_invokes_cmake_build() abort
  if !has('unix')
    return
  endif

  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()
  let l:initial_path = $PATH

  try
    let l:args_path = s:path_join(l:fixture.root, 'cmake-build-args.txt')
    let l:bin_dir = s:create_fake_cmake_script(l:fixture.root, l:args_path, 0)
    let $PATH = l:bin_dir . ':' . l:initial_path

    let l:deep_dir = s:path_join(l:fixture.root, 'src')
    call mkdir(l:deep_dir, 'p')

    execute 'cd ' . fnameescape(l:deep_dir)
    execute 'silent CMakeBuild'

    let l:config_path = s:path_join(l:fixture.root, '.vim/.cmake/.config.json')
    let l:expected_root = s:normalized_path(l:fixture.root)
    let l:expected_build_dir = s:path_join(l:expected_root, 'build')
    call assert_equal({'output': 'build', 'preset': '', 'build': 'Debug'}, s:read_json(l:config_path))
    call assert_true(s:wait_for_file(l:args_path, 1000), 'Expected fake cmake args file to be created.')
    call assert_equal(
          \ ['--build', l:expected_build_dir],
          \ s:read_non_empty_lines(l:args_path))
  finally
    let $PATH = l:initial_path
    execute 'cd ' . fnameescape(l:initial_cwd)
    call delete(l:fixture.root, 'rf')
  endtry
endfunction

function! s:test_cmake_build_uses_existing_config_preset_and_target() abort
  if !has('unix')
    return
  endif

  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()
  let l:initial_path = $PATH

  try
    let l:config_path = s:path_join(l:fixture.root, '.vim/.cmake/.config.json')
    call s:write_json(
          \ l:config_path,
          \ {'output': 'out/build-dir', 'preset': 'dev', 'target': 'mylib', 'build': 'Release'})

    let l:args_path = s:path_join(l:fixture.root, 'cmake-build-args-existing.txt')
    let l:bin_dir = s:create_fake_cmake_script(l:fixture.root, l:args_path, 0)
    let $PATH = l:bin_dir . ':' . l:initial_path

    let l:deep_dir = s:path_join(s:path_join(l:fixture.root, 'sub'), 'dir')
    call mkdir(l:deep_dir, 'p')
    execute 'cd ' . fnameescape(l:deep_dir)
    execute 'silent CMakeBuild'

    let l:expected_root = s:normalized_path(l:fixture.root)
    call assert_true(s:wait_for_file(l:args_path, 1000), 'Expected fake cmake args file to be created.')
    call assert_equal(
          \ [
          \   '--build',
          \   s:path_join(l:expected_root, 'out/build-dir'),
          \   '--preset',
          \   'dev',
          \   '--target',
          \   'mylib'
          \ ],
          \ s:read_non_empty_lines(l:args_path))
  finally
    let $PATH = l:initial_path
    execute 'cd ' . fnameescape(l:initial_cwd)
    call delete(l:fixture.root, 'rf')
  endtry
endfunction

function! s:test_cmake_build_sets_running_terminal_name_with_preset_and_target() abort
  if !has('unix')
    return
  endif

  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()
  let l:initial_path = $PATH

  try
    let l:config_path = s:path_join(l:fixture.root, '.vim/.cmake/.config.json')
    call s:write_json(
          \ l:config_path,
          \ {'output': 'build', 'preset': 'dev', 'target': 'mylib', 'build': 'Release'})

    let l:args_path = s:path_join(l:fixture.root, 'cmake-build-args-running-name.txt')
    let l:bin_dir = s:path_join(l:fixture.root, 'fake-bin')
    call mkdir(l:bin_dir, 'p')
    let l:script_path = s:path_join(l:bin_dir, 'cmake')
    call writefile([
          \ '#!/bin/sh',
          \ 'printf "%s\n" "$@" > ' . shellescape(l:args_path),
          \ 'echo "running-name-build-start"',
          \ 'sleep 2',
          \ 'echo "running-name-build-end"',
          \ 'exit 0'
          \ ], l:script_path, 'b')
    call system('chmod +x ' . shellescape(l:script_path))
    let $PATH = l:bin_dir . ':' . l:initial_path

    execute 'cd ' . fnameescape(l:fixture.root)
    call vim_cmake_naive#build()

    call assert_true(s:wait_for_file(l:args_path, 1000), 'Expected fake cmake args file to be created.')
    let l:running_window_id = s:wait_for_running_terminal_window(1000)
    call assert_true(l:running_window_id > 0, 'Expected running build terminal window.')
    let l:running_buffer_number = winbufnr(win_id2win(l:running_window_id))
    call assert_equal('cmake build --preset=dev --target=mylib', bufname(l:running_buffer_number))
  finally
    sleep 2200m
    let $PATH = l:initial_path
    execute 'cd ' . fnameescape(l:initial_cwd)
    call delete(l:fixture.root, 'rf')
  endtry
endfunction

function! s:test_cmake_build_opens_vertical_terminal_with_command_output() abort
  if !has('unix')
    return
  endif

  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()
  let l:initial_path = $PATH
  let l:initial_capture_terminal = get(g:, 'vim_cmake_naive_test_capture_build_terminal', v:null)
  let l:initial_last_terminal = get(g:, 'vim_cmake_naive_test_last_build_terminal', v:null)

  try
    let l:args_path = s:path_join(l:fixture.root, 'cmake-build-args-preview.txt')
    let l:bin_dir = s:path_join(l:fixture.root, 'fake-bin')
    call mkdir(l:bin_dir, 'p')
    let l:script_path = s:path_join(l:bin_dir, 'cmake')
    call writefile([
          \ '#!/bin/sh',
          \ 'printf "%s\n" "$@" > ' . shellescape(l:args_path),
          \ 'echo "preview-build-line-1"',
          \ 'echo "preview-build-line-2"',
          \ 'exit 0'
          \ ], l:script_path, 'b')
    call system('chmod +x ' . shellescape(l:script_path))
    let $PATH = l:bin_dir . ':' . l:initial_path

    execute 'cd ' . fnameescape(l:fixture.root)
    let g:vim_cmake_naive_test_capture_build_terminal = 1
    unlet! g:vim_cmake_naive_test_last_build_terminal
    call vim_cmake_naive#build()

    let l:terminal = s:wait_for_captured_build_terminal_output('preview-build-line-2', 1000)
    call assert_equal(1, get(l:terminal, 'is_terminal', 0))
    call assert_equal(1, get(l:terminal, 'is_vertical_split', 0))
    call assert_true(get(l:terminal, 'window_count', 0) >= 2)
    call assert_true(get(l:terminal, 'width', 0) > 0)
    call assert_equal('Success', get(l:terminal, 'buffer_name', ''))
    let l:terminal_text = join(get(l:terminal, 'lines', []), "\n")
    call assert_true(stridx(l:terminal_text, 'preview-build-line-1') >= 0)
    call assert_true(stridx(l:terminal_text, 'preview-build-line-2') >= 0)

    let l:expected_root = s:normalized_path(l:fixture.root)
    call assert_true(s:wait_for_file(l:args_path, 1000), 'Expected fake cmake args file to be created.')
    call assert_equal(
          \ ['--build', s:path_join(l:expected_root, 'build')],
          \ s:read_non_empty_lines(l:args_path))
  finally
    let $PATH = l:initial_path
    if l:initial_capture_terminal is v:null
      unlet! g:vim_cmake_naive_test_capture_build_terminal
    else
      let g:vim_cmake_naive_test_capture_build_terminal = l:initial_capture_terminal
    endif
    if l:initial_last_terminal is v:null
      unlet! g:vim_cmake_naive_test_last_build_terminal
    else
      let g:vim_cmake_naive_test_last_build_terminal = l:initial_last_terminal
    endif
    execute 'cd ' . fnameescape(l:initial_cwd)
    call delete(l:fixture.root, 'rf')
  endtry
endfunction

function! s:test_cmake_build_opens_vertical_terminal_with_stdout_and_stderr_output() abort
  if !has('unix')
    return
  endif

  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()
  let l:initial_path = $PATH
  let l:initial_capture_terminal = get(g:, 'vim_cmake_naive_test_capture_build_terminal', v:null)
  let l:initial_last_terminal = get(g:, 'vim_cmake_naive_test_last_build_terminal', v:null)

  try
    let l:args_path = s:path_join(l:fixture.root, 'cmake-build-args-preview-all-output.txt')
    let l:bin_dir = s:path_join(l:fixture.root, 'fake-bin')
    call mkdir(l:bin_dir, 'p')
    let l:script_path = s:path_join(l:bin_dir, 'cmake')
    call writefile([
          \ '#!/bin/sh',
          \ 'printf "%s\n" "$@" > ' . shellescape(l:args_path),
          \ 'echo "preview-stdout-line"',
          \ 'echo "preview-stderr-line" >&2',
          \ 'exit 0'
          \ ], l:script_path, 'b')
    call system('chmod +x ' . shellescape(l:script_path))
    let $PATH = l:bin_dir . ':' . l:initial_path

    execute 'cd ' . fnameescape(l:fixture.root)
    let g:vim_cmake_naive_test_capture_build_terminal = 1
    unlet! g:vim_cmake_naive_test_last_build_terminal
    call vim_cmake_naive#build()

    let l:terminal = s:wait_for_captured_build_terminal_output('preview-stderr-line', 1000)
    call assert_equal(1, get(l:terminal, 'is_terminal', 0))
    call assert_equal(1, get(l:terminal, 'is_vertical_split', 0))
    call assert_equal('Success', get(l:terminal, 'buffer_name', ''))
    let l:terminal_text = join(get(l:terminal, 'lines', []), "\n")
    call assert_true(stridx(l:terminal_text, 'preview-stdout-line') >= 0)
    call assert_true(stridx(l:terminal_text, 'preview-stderr-line') >= 0)

    let l:expected_root = s:normalized_path(l:fixture.root)
    call assert_true(s:wait_for_file(l:args_path, 1000), 'Expected fake cmake args file to be created.')
    call assert_equal(
          \ ['--build', s:path_join(l:expected_root, 'build')],
          \ s:read_non_empty_lines(l:args_path))
  finally
    let $PATH = l:initial_path
    if l:initial_capture_terminal is v:null
      unlet! g:vim_cmake_naive_test_capture_build_terminal
    else
      let g:vim_cmake_naive_test_capture_build_terminal = l:initial_capture_terminal
    endif
    if l:initial_last_terminal is v:null
      unlet! g:vim_cmake_naive_test_last_build_terminal
    else
      let g:vim_cmake_naive_test_last_build_terminal = l:initial_last_terminal
    endif
    execute 'cd ' . fnameescape(l:initial_cwd)
    call delete(l:fixture.root, 'rf')
  endtry
endfunction

function! s:test_cmake_build_sets_failure_terminal_name_with_exit_code() abort
  if !has('unix')
    return
  endif

  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()
  let l:initial_path = $PATH
  let l:initial_capture_terminal = get(g:, 'vim_cmake_naive_test_capture_build_terminal', v:null)
  let l:initial_last_terminal = get(g:, 'vim_cmake_naive_test_last_build_terminal', v:null)

  try
    let l:args_path = s:path_join(l:fixture.root, 'cmake-build-args-failure-name.txt')
    let l:bin_dir = s:path_join(l:fixture.root, 'fake-bin')
    call mkdir(l:bin_dir, 'p')
    let l:script_path = s:path_join(l:bin_dir, 'cmake')
    call writefile([
          \ '#!/bin/sh',
          \ 'printf "%s\n" "$@" > ' . shellescape(l:args_path),
          \ 'echo "failure-build-line"',
          \ 'exit 7'
          \ ], l:script_path, 'b')
    call system('chmod +x ' . shellescape(l:script_path))
    let $PATH = l:bin_dir . ':' . l:initial_path

    execute 'cd ' . fnameescape(l:fixture.root)
    let g:vim_cmake_naive_test_capture_build_terminal = 1
    unlet! g:vim_cmake_naive_test_last_build_terminal
    call vim_cmake_naive#build()

    let l:terminal = s:wait_for_captured_build_terminal_output('failure-build-line', 1000)
    call assert_equal(1, get(l:terminal, 'is_terminal', 0))
    call assert_equal('Failure (7)', get(l:terminal, 'buffer_name', ''))

    let l:expected_root = s:normalized_path(l:fixture.root)
    call assert_true(s:wait_for_file(l:args_path, 1000), 'Expected fake cmake args file to be created.')
    call assert_equal(
          \ ['--build', s:path_join(l:expected_root, 'build')],
          \ s:read_non_empty_lines(l:args_path))

    let l:messages = execute('messages')
    call assert_true(stridx(l:messages, 'Command failed with exit code 7. See build terminal window for details.') >= 0)
  finally
    let $PATH = l:initial_path
    if l:initial_capture_terminal is v:null
      unlet! g:vim_cmake_naive_test_capture_build_terminal
    else
      let g:vim_cmake_naive_test_capture_build_terminal = l:initial_capture_terminal
    endif
    if l:initial_last_terminal is v:null
      unlet! g:vim_cmake_naive_test_last_build_terminal
    else
      let g:vim_cmake_naive_test_last_build_terminal = l:initial_last_terminal
    endif
    execute 'cd ' . fnameescape(l:initial_cwd)
    call delete(l:fixture.root, 'rf')
  endtry
endfunction

function! s:test_cmake_build_reuses_visible_output_window_when_possible() abort
  if !has('unix')
    return
  endif

  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()
  let l:initial_path = $PATH
  let l:initial_capture_terminal = get(g:, 'vim_cmake_naive_test_capture_build_terminal', v:null)
  let l:initial_last_terminal = get(g:, 'vim_cmake_naive_test_last_build_terminal', v:null)

  try
    let l:args_path = s:path_join(l:fixture.root, 'cmake-build-args-reuse-window.txt')
    let l:bin_dir = s:path_join(l:fixture.root, 'fake-bin')
    call mkdir(l:bin_dir, 'p')
    let l:script_path = s:path_join(l:bin_dir, 'cmake')
    call writefile([
          \ '#!/bin/sh',
          \ 'printf "%s\n" "$@" > ' . shellescape(l:args_path),
          \ 'echo "reuse-window-first-build"',
          \ 'exit 0'
          \ ], l:script_path, 'b')
    call system('chmod +x ' . shellescape(l:script_path))
    let $PATH = l:bin_dir . ':' . l:initial_path

    execute 'cd ' . fnameescape(l:fixture.root)
    let g:vim_cmake_naive_test_capture_build_terminal = 1
    unlet! g:vim_cmake_naive_test_last_build_terminal
    call vim_cmake_naive#build()

    let l:first_terminal = s:wait_for_captured_build_terminal_output('reuse-window-first-build', 1000)
    let l:first_window_id = get(l:first_terminal, 'winid', 0)
    call assert_true(l:first_window_id > 0)

    call writefile([
          \ '#!/bin/sh',
          \ 'printf "%s\n" "$@" > ' . shellescape(l:args_path),
          \ 'echo "reuse-window-second-build"',
          \ 'exit 0'
          \ ], l:script_path, 'b')
    call system('chmod +x ' . shellescape(l:script_path))

    unlet! g:vim_cmake_naive_test_last_build_terminal
    call vim_cmake_naive#build()

    let l:second_terminal = s:wait_for_captured_build_terminal_output('reuse-window-second-build', 1000)
    let l:second_window_id = get(l:second_terminal, 'winid', 0)
    call assert_true(l:second_window_id > 0)
    call assert_equal(l:first_window_id, l:second_window_id)

    let l:expected_root = s:normalized_path(l:fixture.root)
    call assert_true(s:wait_for_file(l:args_path, 1000), 'Expected fake cmake args file to be created.')
    call assert_equal(
          \ ['--build', s:path_join(l:expected_root, 'build')],
          \ s:read_non_empty_lines(l:args_path))
  finally
    let $PATH = l:initial_path
    if l:initial_capture_terminal is v:null
      unlet! g:vim_cmake_naive_test_capture_build_terminal
    else
      let g:vim_cmake_naive_test_capture_build_terminal = l:initial_capture_terminal
    endif
    if l:initial_last_terminal is v:null
      unlet! g:vim_cmake_naive_test_last_build_terminal
    else
      let g:vim_cmake_naive_test_last_build_terminal = l:initial_last_terminal
    endif
    execute 'cd ' . fnameescape(l:initial_cwd)
    call delete(l:fixture.root, 'rf')
  endtry
endfunction

function! s:test_cmake_build_recreates_visible_output_window_when_reuse_not_possible() abort
  if !has('unix')
    return
  endif

  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()
  let l:initial_path = $PATH
  let l:initial_capture_terminal = get(g:, 'vim_cmake_naive_test_capture_build_terminal', v:null)
  let l:initial_last_terminal = get(g:, 'vim_cmake_naive_test_last_build_terminal', v:null)

  try
    let l:state_path = s:path_join(l:fixture.root, 'cmake-build-state.txt')
    let l:bin_dir = s:path_join(l:fixture.root, 'fake-bin')
    call mkdir(l:bin_dir, 'p')
    let l:script_path = s:path_join(l:bin_dir, 'cmake')
    call writefile([
          \ '#!/bin/sh',
          \ 'if [ ! -f ' . shellescape(l:state_path) . ' ]; then',
          \ '  echo "first" > ' . shellescape(l:state_path),
          \ '  echo "replace-window-first-build-start"',
          \ '  sleep 2',
          \ '  echo "replace-window-first-build-end"',
          \ '  exit 0',
          \ 'fi',
          \ 'echo "replace-window-second-build"',
          \ 'exit 0'
          \ ], l:script_path, 'b')
    call system('chmod +x ' . shellescape(l:script_path))
    let $PATH = l:bin_dir . ':' . l:initial_path

    execute 'cd ' . fnameescape(l:fixture.root)
    let g:vim_cmake_naive_test_capture_build_terminal = 0
    unlet! g:vim_cmake_naive_test_last_build_terminal
    call vim_cmake_naive#build()

    call assert_true(s:wait_for_file(l:state_path, 1000), 'Expected first build command to start.')
    let l:first_window_id = s:wait_for_running_terminal_window(1000)
    call assert_true(l:first_window_id > 0)
    let l:first_running_buffer_number = winbufnr(win_id2win(l:first_window_id))
    call assert_equal('cmake build --target=all', bufname(l:first_running_buffer_number))

    let g:vim_cmake_naive_test_capture_build_terminal = 1
    unlet! g:vim_cmake_naive_test_last_build_terminal
    call vim_cmake_naive#build()

    let l:second_terminal = s:wait_for_captured_build_terminal_output('replace-window-second-build', 2000)
    let l:second_window_id = get(l:second_terminal, 'winid', 0)
    call assert_true(l:second_window_id > 0)
    call assert_true(win_id2win(l:first_window_id) == 0)
  finally
    sleep 2200m
    let $PATH = l:initial_path
    if l:initial_capture_terminal is v:null
      unlet! g:vim_cmake_naive_test_capture_build_terminal
    else
      let g:vim_cmake_naive_test_capture_build_terminal = l:initial_capture_terminal
    endif
    if l:initial_last_terminal is v:null
      unlet! g:vim_cmake_naive_test_last_build_terminal
    else
      let g:vim_cmake_naive_test_last_build_terminal = l:initial_last_terminal
    endif
    execute 'cd ' . fnameescape(l:initial_cwd)
    call delete(l:fixture.root, 'rf')
  endtry
endfunction

function! s:test_cmake_build_errors_when_no_cmakelists_found() abort
  let l:root = tempname()
  call mkdir(l:root, 'p')
  let l:initial_cwd = getcwd()

  try
    execute 'cd ' . fnameescape(l:root)
    call vim_cmake_naive#build()

    let l:messages = execute('messages')
    call assert_true(stridx(l:messages, 'CMakeLists.txt not found in current directory or any parent directory.') >= 0)
  finally
    execute 'cd ' . fnameescape(l:initial_cwd)
    call delete(l:root, 'rf')
  endtry
endfunction

function! s:test_cmake_info_popup_shows_config_as_table() abort
  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()
  let l:initial_use_popup = get(g:, 'vim_cmake_naive_test_use_popup_menu', v:null)
  let l:initial_popup_response = get(g:, 'vim_cmake_naive_test_popup_menu_response', v:null)
  let l:initial_popup_items = get(g:, 'vim_cmake_naive_test_last_info_popup_items', v:null)
  let l:initial_popup_options = get(g:, 'vim_cmake_naive_test_last_info_popup_options', v:null)

  try
    let l:config_path = s:path_join(l:fixture.root, '.vim/.cmake/.config.json')
    call s:write_json(l:config_path, {'output': 'out/build-dir', 'preset': 'dev', 'build': 'Release', 'target': 'mylib'})
    execute 'cd ' . fnameescape(l:fixture.root)

    let g:vim_cmake_naive_test_use_popup_menu = 1
    let g:vim_cmake_naive_test_popup_menu_response = 0
    unlet! g:vim_cmake_naive_test_last_info_popup_items
    unlet! g:vim_cmake_naive_test_last_info_popup_options
    call vim_cmake_naive#info()

    call assert_equal(
          \ ['build  | Release', 'output | out/build-dir', 'preset | dev', 'target | mylib'],
          \ get(g:, 'vim_cmake_naive_test_last_info_popup_items', []))
    let l:popup_title = get(g:vim_cmake_naive_test_last_info_popup_options, 'title', '')
    let l:popup_lines = get(g:, 'vim_cmake_naive_test_last_info_popup_items', [])
    let l:popup_line_width = empty(l:popup_lines) ? 0 : max(map(copy(l:popup_lines), 'strlen(v:val)'))
    let l:expected_popup_width = max([30, strlen(l:popup_title), l:popup_line_width])
    call assert_true(stridx(l:popup_title, 'CMake info [.vim/.cmake/.config.json]') == 0)
    call assert_equal(l:expected_popup_width, get(g:vim_cmake_naive_test_last_info_popup_options, 'minwidth', 0))
    call assert_equal(l:expected_popup_width, get(g:vim_cmake_naive_test_last_info_popup_options, 'maxwidth', 0))
    call assert_equal(4, get(g:vim_cmake_naive_test_last_info_popup_options, 'minheight', 0))
    call assert_equal(4, get(g:vim_cmake_naive_test_last_info_popup_options, 'maxheight', 0))
    call assert_equal(1, get(g:vim_cmake_naive_test_last_info_popup_options, 'scrollbar', 0))
    call assert_equal([1, 1, 1, 1], get(g:vim_cmake_naive_test_last_info_popup_options, 'border', []))
    call assert_equal(['─', '│', '─', '│', '╭', '╮', '╯', '╰'], get(g:vim_cmake_naive_test_last_info_popup_options, 'borderchars', []))
    call assert_equal('Pmenu', get(g:vim_cmake_naive_test_last_info_popup_options, 'highlight', ''))
    call assert_equal(['Pmenu'], get(g:vim_cmake_naive_test_last_info_popup_options, 'borderhighlight', []))
  finally
    if l:initial_use_popup is v:null
      unlet! g:vim_cmake_naive_test_use_popup_menu
    else
      let g:vim_cmake_naive_test_use_popup_menu = l:initial_use_popup
    endif
    if l:initial_popup_response is v:null
      unlet! g:vim_cmake_naive_test_popup_menu_response
    else
      let g:vim_cmake_naive_test_popup_menu_response = l:initial_popup_response
    endif
    if l:initial_popup_items is v:null
      unlet! g:vim_cmake_naive_test_last_info_popup_items
    else
      let g:vim_cmake_naive_test_last_info_popup_items = l:initial_popup_items
    endif
    if l:initial_popup_options is v:null
      unlet! g:vim_cmake_naive_test_last_info_popup_options
    else
      let g:vim_cmake_naive_test_last_info_popup_options = l:initial_popup_options
    endif
    execute 'cd ' . fnameescape(l:initial_cwd)
    call delete(l:fixture.root, 'rf')
  endtry
endfunction

function! s:test_cmake_info_popup_reports_missing_config() abort
  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()
  let l:initial_use_popup = get(g:, 'vim_cmake_naive_test_use_popup_menu', v:null)
  let l:initial_popup_response = get(g:, 'vim_cmake_naive_test_popup_menu_response', v:null)
  let l:initial_popup_items = get(g:, 'vim_cmake_naive_test_last_info_popup_items', v:null)
  let l:initial_popup_options = get(g:, 'vim_cmake_naive_test_last_info_popup_options', v:null)

  try
    execute 'cd ' . fnameescape(l:fixture.root)
    let g:vim_cmake_naive_test_use_popup_menu = 1
    let g:vim_cmake_naive_test_popup_menu_response = 0
    unlet! g:vim_cmake_naive_test_last_info_popup_items
    unlet! g:vim_cmake_naive_test_last_info_popup_options
    call vim_cmake_naive#info()

    call assert_equal(
          \ ['No configuration, please use CMakeConfigDefault to get started'],
          \ get(g:, 'vim_cmake_naive_test_last_info_popup_items', []))
    let l:popup_title = get(g:vim_cmake_naive_test_last_info_popup_options, 'title', '')
    let l:popup_lines = get(g:, 'vim_cmake_naive_test_last_info_popup_items', [])
    let l:popup_line_width = empty(l:popup_lines) ? 0 : max(map(copy(l:popup_lines), 'strlen(v:val)'))
    let l:expected_popup_width = max([30, strlen(l:popup_title), l:popup_line_width])
    call assert_equal('CMake info', l:popup_title)
    call assert_equal(l:expected_popup_width, get(g:vim_cmake_naive_test_last_info_popup_options, 'minwidth', 0))
    call assert_equal(l:expected_popup_width, get(g:vim_cmake_naive_test_last_info_popup_options, 'maxwidth', 0))
    call assert_equal(1, get(g:vim_cmake_naive_test_last_info_popup_options, 'minheight', 0))
    call assert_equal(1, get(g:vim_cmake_naive_test_last_info_popup_options, 'maxheight', 0))
  finally
    if l:initial_use_popup is v:null
      unlet! g:vim_cmake_naive_test_use_popup_menu
    else
      let g:vim_cmake_naive_test_use_popup_menu = l:initial_use_popup
    endif
    if l:initial_popup_response is v:null
      unlet! g:vim_cmake_naive_test_popup_menu_response
    else
      let g:vim_cmake_naive_test_popup_menu_response = l:initial_popup_response
    endif
    if l:initial_popup_items is v:null
      unlet! g:vim_cmake_naive_test_last_info_popup_items
    else
      let g:vim_cmake_naive_test_last_info_popup_items = l:initial_popup_items
    endif
    if l:initial_popup_options is v:null
      unlet! g:vim_cmake_naive_test_last_info_popup_options
    else
      let g:vim_cmake_naive_test_last_info_popup_options = l:initial_popup_options
    endif
    execute 'cd ' . fnameescape(l:initial_cwd)
    call delete(l:fixture.root, 'rf')
  endtry
endfunction

function! s:test_cmake_menu_popup_lists_commands_and_executes_selection() abort
  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()
  let l:initial_use_popup = get(g:, 'vim_cmake_naive_test_use_popup_menu', v:null)
  let l:initial_popup_response = get(g:, 'vim_cmake_naive_test_popup_menu_response', v:null)
  let l:initial_popup_items = get(g:, 'vim_cmake_naive_test_last_menu_popup_items', v:null)
  let l:initial_popup_options = get(g:, 'vim_cmake_naive_test_last_menu_popup_options', v:null)
  let l:initial_menu_selection = get(g:, 'vim_cmake_naive_test_menu_response', v:null)
  let l:initial_inputlist_selection = get(g:, 'vim_cmake_naive_test_inputlist_response', v:null)
  let l:initial_menu_command_args = get(g:, 'vim_cmake_naive_test_menu_command_args', v:null)

  try
    execute 'cd ' . fnameescape(l:fixture.root)
    let g:vim_cmake_naive_test_use_popup_menu = 1
    let g:vim_cmake_naive_test_popup_menu_response = 1
    let g:vim_cmake_naive_test_menu_command_args = {}
    unlet! g:vim_cmake_naive_test_menu_response
    unlet! g:vim_cmake_naive_test_inputlist_response
    unlet! g:vim_cmake_naive_test_last_menu_popup_items
    unlet! g:vim_cmake_naive_test_last_menu_popup_options
    call vim_cmake_naive#menu_full()

    call assert_equal(
          \ [' 1.   CMakeConfig', ' 2.   CMakeConfigDefault', ' 3.   CMakeSwitchPreset', ' 4.   CMakeSwitchTarget', ' 5.   CMakeGenerate', ' 6.   CMakeBuild', ' 7.   CMakeInfo', ' 8.   CMakeMenu', ' 9.   CMakeMenuFull', '10.   CMakeResetPreset', '11.   CMakeResetTarget', '12.   CMakeConfigSetPreset', '13.   CMakeConfigSetBuild', '14.   CMakeConfigSetOutput'],
          \ get(g:, 'vim_cmake_naive_test_last_menu_popup_items', []))
    call assert_equal('Select CMake command', get(g:vim_cmake_naive_test_last_menu_popup_options, 'title', ''))
    call assert_equal(30, get(g:vim_cmake_naive_test_last_menu_popup_options, 'minwidth', 0))
    call assert_equal(30, get(g:vim_cmake_naive_test_last_menu_popup_options, 'maxwidth', 0))
    call assert_equal(10, get(g:vim_cmake_naive_test_last_menu_popup_options, 'minheight', 0))
    call assert_equal(10, get(g:vim_cmake_naive_test_last_menu_popup_options, 'maxheight', 0))
    call assert_equal(1, get(g:vim_cmake_naive_test_last_menu_popup_options, 'scrollbar', 0))
    call assert_equal([1, 1, 1, 1], get(g:vim_cmake_naive_test_last_menu_popup_options, 'border', []))
    call assert_equal(['─', '│', '─', '│', '╭', '╮', '╯', '╰'], get(g:vim_cmake_naive_test_last_menu_popup_options, 'borderchars', []))
    call assert_equal('Pmenu', get(g:vim_cmake_naive_test_last_menu_popup_options, 'highlight', ''))
    call assert_equal(['Pmenu'], get(g:vim_cmake_naive_test_last_menu_popup_options, 'borderhighlight', []))
    call assert_true(filereadable(s:path_join(l:fixture.root, '.vim/.cmake/.config.json')))
  finally
    if l:initial_use_popup is v:null
      unlet! g:vim_cmake_naive_test_use_popup_menu
    else
      let g:vim_cmake_naive_test_use_popup_menu = l:initial_use_popup
    endif
    if l:initial_popup_response is v:null
      unlet! g:vim_cmake_naive_test_popup_menu_response
    else
      let g:vim_cmake_naive_test_popup_menu_response = l:initial_popup_response
    endif
    if l:initial_popup_items is v:null
      unlet! g:vim_cmake_naive_test_last_menu_popup_items
    else
      let g:vim_cmake_naive_test_last_menu_popup_items = l:initial_popup_items
    endif
    if l:initial_popup_options is v:null
      unlet! g:vim_cmake_naive_test_last_menu_popup_options
    else
      let g:vim_cmake_naive_test_last_menu_popup_options = l:initial_popup_options
    endif
    if l:initial_menu_selection is v:null
      unlet! g:vim_cmake_naive_test_menu_response
    else
      let g:vim_cmake_naive_test_menu_response = l:initial_menu_selection
    endif
    if l:initial_inputlist_selection is v:null
      unlet! g:vim_cmake_naive_test_inputlist_response
    else
      let g:vim_cmake_naive_test_inputlist_response = l:initial_inputlist_selection
    endif
    if l:initial_menu_command_args is v:null
      unlet! g:vim_cmake_naive_test_menu_command_args
    else
      let g:vim_cmake_naive_test_menu_command_args = l:initial_menu_command_args
    endif
    execute 'cd ' . fnameescape(l:initial_cwd)
    call delete(l:fixture.root, 'rf')
  endtry
endfunction

function! s:test_cmake_menu_popup_lists_compact_commands_and_executes_selection() abort
  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()
  let l:initial_use_popup = get(g:, 'vim_cmake_naive_test_use_popup_menu', v:null)
  let l:initial_popup_response = get(g:, 'vim_cmake_naive_test_popup_menu_response', v:null)
  let l:initial_popup_items = get(g:, 'vim_cmake_naive_test_last_menu_popup_items', v:null)
  let l:initial_popup_options = get(g:, 'vim_cmake_naive_test_last_menu_popup_options', v:null)
  let l:initial_menu_selection = get(g:, 'vim_cmake_naive_test_menu_response', v:null)
  let l:initial_inputlist_selection = get(g:, 'vim_cmake_naive_test_inputlist_response', v:null)
  let l:initial_menu_command_args = get(g:, 'vim_cmake_naive_test_menu_command_args', v:null)
  let l:initial_capture_terminal = get(g:, 'vim_cmake_naive_test_capture_build_terminal', v:null)
  let l:initial_last_terminal = get(g:, 'vim_cmake_naive_test_last_build_terminal', v:null)
  let l:initial_path = $PATH

  try
    let l:args_path = s:path_join(l:fixture.root, 'cmake-build-args-menu-compact.txt')
    let l:bin_dir = s:path_join(l:fixture.root, 'fake-bin')
    call mkdir(l:bin_dir, 'p')
    let l:script_path = s:path_join(l:bin_dir, 'cmake')
    call writefile([
          \ '#!/bin/sh',
          \ 'printf "%s\n" "$@" > ' . shellescape(l:args_path),
          \ 'echo "compact-menu-build-output"',
          \ 'exit 0'
          \ ], l:script_path, 'b')
    call system('chmod +x ' . shellescape(l:script_path))
    let $PATH = l:bin_dir . ':' . l:initial_path

    execute 'cd ' . fnameescape(l:fixture.root)
    let g:vim_cmake_naive_test_use_popup_menu = 1
    let g:vim_cmake_naive_test_popup_menu_response = 2
    let g:vim_cmake_naive_test_menu_command_args = {}
    let g:vim_cmake_naive_test_capture_build_terminal = 1
    unlet! g:vim_cmake_naive_test_menu_response
    unlet! g:vim_cmake_naive_test_inputlist_response
    unlet! g:vim_cmake_naive_test_last_menu_popup_items
    unlet! g:vim_cmake_naive_test_last_menu_popup_options
    unlet! g:vim_cmake_naive_test_last_build_terminal
    execute 'silent CMakeMenu'

    call assert_equal(
          \ ['1.   CMakeGenerate', '2.   CMakeBuild', '3.   CMakeSwitchPreset', '4.   CMakeSwitchTarget'],
          \ get(g:, 'vim_cmake_naive_test_last_menu_popup_items', []))
    call assert_equal('Select CMake command', get(g:vim_cmake_naive_test_last_menu_popup_options, 'title', ''))
    call assert_equal(30, get(g:vim_cmake_naive_test_last_menu_popup_options, 'minwidth', 0))
    call assert_equal(30, get(g:vim_cmake_naive_test_last_menu_popup_options, 'maxwidth', 0))
    call assert_equal(4, get(g:vim_cmake_naive_test_last_menu_popup_options, 'minheight', 0))
    call assert_equal(4, get(g:vim_cmake_naive_test_last_menu_popup_options, 'maxheight', 0))
    call assert_equal(1, get(g:vim_cmake_naive_test_last_menu_popup_options, 'scrollbar', 0))
    call assert_equal([1, 1, 1, 1], get(g:vim_cmake_naive_test_last_menu_popup_options, 'border', []))
    call assert_equal(['─', '│', '─', '│', '╭', '╮', '╯', '╰'], get(g:vim_cmake_naive_test_last_menu_popup_options, 'borderchars', []))
    call assert_equal('Pmenu', get(g:vim_cmake_naive_test_last_menu_popup_options, 'highlight', ''))
    call assert_equal(['Pmenu'], get(g:vim_cmake_naive_test_last_menu_popup_options, 'borderhighlight', []))
    let l:terminal = s:wait_for_captured_build_terminal_output('compact-menu-build-output', 1000)
    call assert_equal(1, get(l:terminal, 'is_terminal', 0))
    call assert_equal(1, get(l:terminal, 'is_vertical_split', 0))
    let l:expected_root = s:normalized_path(l:fixture.root)
    call assert_true(s:wait_for_file(l:args_path, 1000), 'Expected fake cmake args file to be created.')
    let l:args_lines = filereadable(l:args_path)
          \ ? s:read_non_empty_lines(l:args_path)
          \ : []
    call assert_equal(
          \ ['--build', s:path_join(l:expected_root, 'build')],
          \ l:args_lines)
  finally
    let $PATH = l:initial_path
    if l:initial_use_popup is v:null
      unlet! g:vim_cmake_naive_test_use_popup_menu
    else
      let g:vim_cmake_naive_test_use_popup_menu = l:initial_use_popup
    endif
    if l:initial_popup_response is v:null
      unlet! g:vim_cmake_naive_test_popup_menu_response
    else
      let g:vim_cmake_naive_test_popup_menu_response = l:initial_popup_response
    endif
    if l:initial_popup_items is v:null
      unlet! g:vim_cmake_naive_test_last_menu_popup_items
    else
      let g:vim_cmake_naive_test_last_menu_popup_items = l:initial_popup_items
    endif
    if l:initial_popup_options is v:null
      unlet! g:vim_cmake_naive_test_last_menu_popup_options
    else
      let g:vim_cmake_naive_test_last_menu_popup_options = l:initial_popup_options
    endif
    if l:initial_menu_selection is v:null
      unlet! g:vim_cmake_naive_test_menu_response
    else
      let g:vim_cmake_naive_test_menu_response = l:initial_menu_selection
    endif
    if l:initial_inputlist_selection is v:null
      unlet! g:vim_cmake_naive_test_inputlist_response
    else
      let g:vim_cmake_naive_test_inputlist_response = l:initial_inputlist_selection
    endif
    if l:initial_menu_command_args is v:null
      unlet! g:vim_cmake_naive_test_menu_command_args
    else
      let g:vim_cmake_naive_test_menu_command_args = l:initial_menu_command_args
    endif
    if l:initial_capture_terminal is v:null
      unlet! g:vim_cmake_naive_test_capture_build_terminal
    else
      let g:vim_cmake_naive_test_capture_build_terminal = l:initial_capture_terminal
    endif
    if l:initial_last_terminal is v:null
      unlet! g:vim_cmake_naive_test_last_build_terminal
    else
      let g:vim_cmake_naive_test_last_build_terminal = l:initial_last_terminal
    endif
    execute 'cd ' . fnameescape(l:initial_cwd)
    call delete(l:fixture.root, 'rf')
  endtry
endfunction

function! s:test_cmake_menu_executes_command_with_arguments() abort
  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()
  let l:initial_use_popup = get(g:, 'vim_cmake_naive_test_use_popup_menu', v:null)
  let l:initial_popup_response = get(g:, 'vim_cmake_naive_test_popup_menu_response', v:null)
  let l:initial_menu_selection = get(g:, 'vim_cmake_naive_test_menu_response', v:null)
  let l:initial_inputlist_selection = get(g:, 'vim_cmake_naive_test_inputlist_response', v:null)
  let l:initial_menu_command_args = get(g:, 'vim_cmake_naive_test_menu_command_args', v:null)

  try
    let l:config_path = s:path_join(l:fixture.root, '.vim/.cmake/.config.json')
    call s:write_json(l:config_path, {'keep': 1})
    execute 'cd ' . fnameescape(l:fixture.root)
    let g:vim_cmake_naive_test_use_popup_menu = 1
    let g:vim_cmake_naive_test_popup_menu_response = 12
    let g:vim_cmake_naive_test_menu_command_args = {'CMakeConfigSetPreset': 'dev-preset'}
    unlet! g:vim_cmake_naive_test_menu_response
    unlet! g:vim_cmake_naive_test_inputlist_response
    call vim_cmake_naive#menu_full()

    call assert_equal({'keep': 1, 'preset': 'dev-preset'}, s:read_json(l:config_path))
  finally
    if l:initial_use_popup is v:null
      unlet! g:vim_cmake_naive_test_use_popup_menu
    else
      let g:vim_cmake_naive_test_use_popup_menu = l:initial_use_popup
    endif
    if l:initial_popup_response is v:null
      unlet! g:vim_cmake_naive_test_popup_menu_response
    else
      let g:vim_cmake_naive_test_popup_menu_response = l:initial_popup_response
    endif
    if l:initial_menu_selection is v:null
      unlet! g:vim_cmake_naive_test_menu_response
    else
      let g:vim_cmake_naive_test_menu_response = l:initial_menu_selection
    endif
    if l:initial_inputlist_selection is v:null
      unlet! g:vim_cmake_naive_test_inputlist_response
    else
      let g:vim_cmake_naive_test_inputlist_response = l:initial_inputlist_selection
    endif
    if l:initial_menu_command_args is v:null
      unlet! g:vim_cmake_naive_test_menu_command_args
    else
      let g:vim_cmake_naive_test_menu_command_args = l:initial_menu_command_args
    endif
    execute 'cd ' . fnameescape(l:initial_cwd)
    call delete(l:fixture.root, 'rf')
  endtry
endfunction

function! s:test_cmake_menu_cancels_argument_command_when_args_empty() abort
  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()
  let l:initial_use_popup = get(g:, 'vim_cmake_naive_test_use_popup_menu', v:null)
  let l:initial_popup_response = get(g:, 'vim_cmake_naive_test_popup_menu_response', v:null)
  let l:initial_menu_selection = get(g:, 'vim_cmake_naive_test_menu_response', v:null)
  let l:initial_inputlist_selection = get(g:, 'vim_cmake_naive_test_inputlist_response', v:null)
  let l:initial_menu_command_args = get(g:, 'vim_cmake_naive_test_menu_command_args', v:null)

  try
    let l:config_path = s:path_join(l:fixture.root, '.vim/.cmake/.config.json')
    call s:write_json(l:config_path, {'preset': 'old'})
    execute 'cd ' . fnameescape(l:fixture.root)
    let g:vim_cmake_naive_test_use_popup_menu = 1
    let g:vim_cmake_naive_test_popup_menu_response = 12
    let g:vim_cmake_naive_test_menu_command_args = {'CMakeConfigSetPreset': ''}
    unlet! g:vim_cmake_naive_test_menu_response
    unlet! g:vim_cmake_naive_test_inputlist_response
    call vim_cmake_naive#menu_full()

    call assert_equal({'preset': 'old'}, s:read_json(l:config_path))
  finally
    if l:initial_use_popup is v:null
      unlet! g:vim_cmake_naive_test_use_popup_menu
    else
      let g:vim_cmake_naive_test_use_popup_menu = l:initial_use_popup
    endif
    if l:initial_popup_response is v:null
      unlet! g:vim_cmake_naive_test_popup_menu_response
    else
      let g:vim_cmake_naive_test_popup_menu_response = l:initial_popup_response
    endif
    if l:initial_menu_selection is v:null
      unlet! g:vim_cmake_naive_test_menu_response
    else
      let g:vim_cmake_naive_test_menu_response = l:initial_menu_selection
    endif
    if l:initial_inputlist_selection is v:null
      unlet! g:vim_cmake_naive_test_inputlist_response
    else
      let g:vim_cmake_naive_test_inputlist_response = l:initial_inputlist_selection
    endif
    if l:initial_menu_command_args is v:null
      unlet! g:vim_cmake_naive_test_menu_command_args
    else
      let g:vim_cmake_naive_test_menu_command_args = l:initial_menu_command_args
    endif
    execute 'cd ' . fnameescape(l:initial_cwd)
    call delete(l:fixture.root, 'rf')
  endtry
endfunction

function! s:test_cmake_menu_cancels_without_executing_when_popup_canceled() abort
  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()
  let l:initial_use_popup = get(g:, 'vim_cmake_naive_test_use_popup_menu', v:null)
  let l:initial_popup_response = get(g:, 'vim_cmake_naive_test_popup_menu_response', v:null)
  let l:initial_menu_selection = get(g:, 'vim_cmake_naive_test_menu_response', v:null)
  let l:initial_inputlist_selection = get(g:, 'vim_cmake_naive_test_inputlist_response', v:null)
  let l:initial_menu_command_args = get(g:, 'vim_cmake_naive_test_menu_command_args', v:null)

  try
    let l:config_path = s:path_join(l:fixture.root, '.vim/.cmake/.config.json')
    call s:write_json(l:config_path, {'keep': 1})
    execute 'cd ' . fnameescape(l:fixture.root)
    let g:vim_cmake_naive_test_use_popup_menu = 1
    let g:vim_cmake_naive_test_popup_menu_response = 0
    let g:vim_cmake_naive_test_menu_command_args = {}
    unlet! g:vim_cmake_naive_test_menu_response
    unlet! g:vim_cmake_naive_test_inputlist_response
    call vim_cmake_naive#menu_full()

    call assert_equal({'keep': 1}, s:read_json(l:config_path))
  finally
    if l:initial_use_popup is v:null
      unlet! g:vim_cmake_naive_test_use_popup_menu
    else
      let g:vim_cmake_naive_test_use_popup_menu = l:initial_use_popup
    endif
    if l:initial_popup_response is v:null
      unlet! g:vim_cmake_naive_test_popup_menu_response
    else
      let g:vim_cmake_naive_test_popup_menu_response = l:initial_popup_response
    endif
    if l:initial_menu_selection is v:null
      unlet! g:vim_cmake_naive_test_menu_response
    else
      let g:vim_cmake_naive_test_menu_response = l:initial_menu_selection
    endif
    if l:initial_inputlist_selection is v:null
      unlet! g:vim_cmake_naive_test_inputlist_response
    else
      let g:vim_cmake_naive_test_inputlist_response = l:initial_inputlist_selection
    endif
    if l:initial_menu_command_args is v:null
      unlet! g:vim_cmake_naive_test_menu_command_args
    else
      let g:vim_cmake_naive_test_menu_command_args = l:initial_menu_command_args
    endif
    execute 'cd ' . fnameescape(l:initial_cwd)
    call delete(l:fixture.root, 'rf')
  endtry
endfunction

function! s:test_cmake_switch_preset_sets_selected_visible_preset() abort
  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()
  let l:initial_selection = get(g:, 'vim_cmake_naive_test_inputlist_response', v:null)
  let l:initial_menu_selection = get(g:, 'vim_cmake_naive_test_menu_response', v:null)

  try
    let l:config_path = s:path_join(l:fixture.root, '.vim/.cmake/.config.json')
    call s:write_json(l:config_path, {'preset': 'old', 'keep': 1})

    call s:write_cmake_presets(
          \ s:path_join(l:fixture.root, 'CMakePresets.json'),
          \ [
          \   {'name': 'hidden_release', 'hidden': v:true},
          \   {'name': 'blocked', 'condition': {'type': 'equals', 'lhs': 'a', 'rhs': 'b'}},
          \   {'name': 'linux_only', 'condition': {'type': 'equals', 'lhs': '${hostSystemName}', 'rhs': 'Linux'}},
          \   {'name': 'dev', 'condition': {'type': 'equals', 'lhs': '${hostSystemName}', 'rhs': 'Darwin'}},
          \   {'name': 'default'}
          \ ])

    execute 'cd ' . fnameescape(l:fixture.root)
    let g:vim_cmake_naive_test_menu_response = 1
    let g:vim_cmake_naive_test_inputlist_response = 1
    execute 'silent CMakeSwitchPreset'

    call assert_equal(
          \ {'preset': 'default', 'keep': 1},
          \ s:read_json(l:config_path))
  finally
    if l:initial_selection is v:null
      unlet! g:vim_cmake_naive_test_inputlist_response
    else
      let g:vim_cmake_naive_test_inputlist_response = l:initial_selection
    endif
    if l:initial_menu_selection is v:null
      unlet! g:vim_cmake_naive_test_menu_response
    else
      let g:vim_cmake_naive_test_menu_response = l:initial_menu_selection
    endif
    execute 'cd ' . fnameescape(l:initial_cwd)
    call delete(l:fixture.root, 'rf')
  endtry
endfunction

function! s:test_cmake_switch_preset_reports_missing_presets_file() abort
  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()

  try
    execute 'cd ' . fnameescape(l:fixture.root)
    call vim_cmake_naive#switch_preset()

    let l:messages = execute('messages')
    call assert_true(stridx(l:messages, 'CMakePresets.json not found at project root:') >= 0)
  finally
    execute 'cd ' . fnameescape(l:initial_cwd)
    call delete(l:fixture.root, 'rf')
  endtry
endfunction

function! s:test_cmake_switch_preset_cancels_without_changing_config() abort
  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()
  let l:initial_selection = get(g:, 'vim_cmake_naive_test_inputlist_response', v:null)
  let l:initial_menu_selection = get(g:, 'vim_cmake_naive_test_menu_response', v:null)

  try
    let l:config_path = s:path_join(l:fixture.root, '.vim/.cmake/.config.json')
    call s:write_json(l:config_path, {'preset': 'stay'})
    call s:write_cmake_presets(
          \ s:path_join(l:fixture.root, 'CMakePresets.json'),
          \ [{'name': 'dev'}, {'name': 'default'}])

    execute 'cd ' . fnameescape(l:fixture.root)
    let g:vim_cmake_naive_test_menu_response = 0
    let g:vim_cmake_naive_test_inputlist_response = 0
    execute 'silent CMakeSwitchPreset'

    call assert_equal({'preset': 'stay'}, s:read_json(l:config_path))
  finally
    if l:initial_selection is v:null
      unlet! g:vim_cmake_naive_test_inputlist_response
    else
      let g:vim_cmake_naive_test_inputlist_response = l:initial_selection
    endif
    if l:initial_menu_selection is v:null
      unlet! g:vim_cmake_naive_test_menu_response
    else
      let g:vim_cmake_naive_test_menu_response = l:initial_menu_selection
    endif
    execute 'cd ' . fnameescape(l:initial_cwd)
    call delete(l:fixture.root, 'rf')
  endtry
endfunction

function! s:test_cmake_switch_preset_reports_no_selectable_presets() abort
  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()

  try
    call s:write_cmake_presets(
          \ s:path_join(l:fixture.root, 'CMakePresets.json'),
          \ [
          \   {'name': 'hidden_release', 'hidden': v:true},
          \   {'name': 'blocked', 'condition': {'type': 'equals', 'lhs': 'x', 'rhs': 'y'}}
          \ ])

    execute 'cd ' . fnameescape(l:fixture.root)
    call vim_cmake_naive#switch_preset()

    let l:messages = execute('messages')
    call assert_true(stridx(l:messages, 'No selectable configure presets found in CMakePresets.json.') >= 0)
  finally
    execute 'cd ' . fnameescape(l:initial_cwd)
    call delete(l:fixture.root, 'rf')
  endtry
endfunction

function! s:test_preset_popup_display_items_formats_ordered_list_and_current_marker() abort
  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()
  let l:initial_use_popup = get(g:, 'vim_cmake_naive_test_use_popup_menu', v:null)
  let l:initial_popup_response = get(g:, 'vim_cmake_naive_test_popup_menu_response', v:null)
  let l:initial_popup_items = get(g:, 'vim_cmake_naive_test_last_preset_popup_items', v:null)
  let l:initial_popup_options = get(g:, 'vim_cmake_naive_test_last_preset_popup_options', v:null)
  let l:initial_menu_selection = get(g:, 'vim_cmake_naive_test_menu_response', v:null)
  let l:initial_inputlist_selection = get(g:, 'vim_cmake_naive_test_inputlist_response', v:null)

  try
    let l:config_path = s:path_join(l:fixture.root, '.vim/.cmake/.config.json')
    call s:write_json(l:config_path, {'preset': 'dev'})
    call s:write_cmake_presets(
          \ s:path_join(l:fixture.root, 'CMakePresets.json'),
          \ [{'name': 'release'}, {'name': 'default'}, {'name': 'dev'}])

    execute 'cd ' . fnameescape(l:fixture.root)
    let g:vim_cmake_naive_test_use_popup_menu = 1
    let g:vim_cmake_naive_test_popup_menu_response = 0
    unlet! g:vim_cmake_naive_test_last_preset_popup_items
    unlet! g:vim_cmake_naive_test_menu_response
    unlet! g:vim_cmake_naive_test_inputlist_response
    call vim_cmake_naive#switch_preset()

    call assert_equal(
          \ ['1.   default', '2. * dev', '3.   release'],
          \ get(g:, 'vim_cmake_naive_test_last_preset_popup_items', []))
    call assert_equal('Select CMake preset', get(g:vim_cmake_naive_test_last_preset_popup_options, 'title', ''))
    call assert_equal(30, get(g:vim_cmake_naive_test_last_preset_popup_options, 'minwidth', 0))
    call assert_equal(30, get(g:vim_cmake_naive_test_last_preset_popup_options, 'maxwidth', 0))
    call assert_equal(3, get(g:vim_cmake_naive_test_last_preset_popup_options, 'minheight', 0))
    call assert_equal(3, get(g:vim_cmake_naive_test_last_preset_popup_options, 'maxheight', 0))
    call assert_equal(1, get(g:vim_cmake_naive_test_last_preset_popup_options, 'scrollbar', 0))
    call assert_equal([1, 1, 1, 1], get(g:vim_cmake_naive_test_last_preset_popup_options, 'border', []))
    call assert_equal(['─', '│', '─', '│', '╭', '╮', '╯', '╰'], get(g:vim_cmake_naive_test_last_preset_popup_options, 'borderchars', []))
    call assert_equal('Pmenu', get(g:vim_cmake_naive_test_last_preset_popup_options, 'highlight', ''))
    call assert_equal(['Pmenu'], get(g:vim_cmake_naive_test_last_preset_popup_options, 'borderhighlight', []))
    call assert_equal({'preset': 'dev'}, s:read_json(l:config_path))
  finally
    if l:initial_use_popup is v:null
      unlet! g:vim_cmake_naive_test_use_popup_menu
    else
      let g:vim_cmake_naive_test_use_popup_menu = l:initial_use_popup
    endif
    if l:initial_popup_response is v:null
      unlet! g:vim_cmake_naive_test_popup_menu_response
    else
      let g:vim_cmake_naive_test_popup_menu_response = l:initial_popup_response
    endif
    if l:initial_popup_items is v:null
      unlet! g:vim_cmake_naive_test_last_preset_popup_items
    else
      let g:vim_cmake_naive_test_last_preset_popup_items = l:initial_popup_items
    endif
    if l:initial_popup_options is v:null
      unlet! g:vim_cmake_naive_test_last_preset_popup_options
    else
      let g:vim_cmake_naive_test_last_preset_popup_options = l:initial_popup_options
    endif
    if l:initial_menu_selection is v:null
      unlet! g:vim_cmake_naive_test_menu_response
    else
      let g:vim_cmake_naive_test_menu_response = l:initial_menu_selection
    endif
    if l:initial_inputlist_selection is v:null
      unlet! g:vim_cmake_naive_test_inputlist_response
    else
      let g:vim_cmake_naive_test_inputlist_response = l:initial_inputlist_selection
    endif
    execute 'cd ' . fnameescape(l:initial_cwd)
    call delete(l:fixture.root, 'rf')
  endtry
endfunction

function! s:test_cmake_switch_target_sets_selected_target() abort
  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()
  let l:initial_selection = get(g:, 'vim_cmake_naive_test_inputlist_response', v:null)
  let l:initial_use_popup = get(g:, 'vim_cmake_naive_test_use_popup_menu', v:null)
  let l:initial_popup_response = get(g:, 'vim_cmake_naive_test_popup_menu_response', v:null)

  try
    let l:config_path = s:path_join(l:fixture.root, '.vim/.cmake/.config.json')
    call s:write_json(l:config_path, {'output': 'build', 'preset': 'dev', 'target': 'old', 'keep': 1})

    let l:target_app = s:path_join(l:fixture.root, 'build/dev/CMakeFiles/app.dir')
    let l:target_lib = s:path_join(l:fixture.root, 'build/dev/lib/CMakeFiles/mylib.dir')
    let l:target_app_commands = s:path_join(l:target_app, 'compile_commands.json')
    let l:target_lib_commands = s:path_join(l:target_lib, 'compile_commands.json')
    call mkdir(l:target_app, 'p')
    call mkdir(l:target_lib, 'p')
    call s:write_json(l:target_app_commands, [{'file': '../src/main.cpp'}])
    call s:write_json(l:target_lib_commands, [{'file': '../lib/foo.cpp'}])

    execute 'cd ' . fnameescape(l:fixture.root)
    let g:vim_cmake_naive_test_inputlist_response = 2
    execute 'silent CMakeSwitchTarget'

    let l:active_commands = s:path_join(l:fixture.root, 'build/compile_commands.json')
    call assert_equal(
          \ {'output': 'build', 'preset': 'dev', 'target': 'mylib', 'keep': 1},
          \ s:read_json(l:config_path))
    call assert_true(filereadable(l:active_commands))
    call assert_equal(readfile(l:target_lib_commands, 'b'), readfile(l:active_commands, 'b'))
  finally
    if l:initial_selection is v:null
      unlet! g:vim_cmake_naive_test_inputlist_response
    else
      let g:vim_cmake_naive_test_inputlist_response = l:initial_selection
    endif
    if l:initial_use_popup is v:null
      unlet! g:vim_cmake_naive_test_use_popup_menu
    else
      let g:vim_cmake_naive_test_use_popup_menu = l:initial_use_popup
    endif
    if l:initial_popup_response is v:null
      unlet! g:vim_cmake_naive_test_popup_menu_response
    else
      let g:vim_cmake_naive_test_popup_menu_response = l:initial_popup_response
    endif
    execute 'cd ' . fnameescape(l:initial_cwd)
    call delete(l:fixture.root, 'rf')
  endtry
endfunction

function! s:test_cmake_switch_target_popup_sets_selected_target() abort
  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()
  let l:initial_use_popup = get(g:, 'vim_cmake_naive_test_use_popup_menu', v:null)
  let l:initial_popup_response = get(g:, 'vim_cmake_naive_test_popup_menu_response', v:null)
  let l:initial_menu_selection = get(g:, 'vim_cmake_naive_test_menu_response', v:null)
  let l:initial_inputlist_selection = get(g:, 'vim_cmake_naive_test_inputlist_response', v:null)

  try
    let l:config_path = s:path_join(l:fixture.root, '.vim/.cmake/.config.json')
    call s:write_json(l:config_path, {'output': 'build', 'preset': 'dev', 'target': 'old', 'keep': 1})

    let l:target_app = s:path_join(l:fixture.root, 'build/dev/CMakeFiles/app.dir')
    let l:target_lib = s:path_join(l:fixture.root, 'build/dev/lib/CMakeFiles/mylib.dir')
    let l:target_app_commands = s:path_join(l:target_app, 'compile_commands.json')
    let l:target_lib_commands = s:path_join(l:target_lib, 'compile_commands.json')
    call mkdir(l:target_app, 'p')
    call mkdir(l:target_lib, 'p')
    call s:write_json(l:target_app_commands, [{'file': '../src/main.cpp'}])
    call s:write_json(l:target_lib_commands, [{'file': '../lib/foo.cpp'}])

    execute 'cd ' . fnameescape(l:fixture.root)
    let g:vim_cmake_naive_test_use_popup_menu = 1
    let g:vim_cmake_naive_test_popup_menu_response = 2
    unlet! g:vim_cmake_naive_test_menu_response
    unlet! g:vim_cmake_naive_test_inputlist_response
    call vim_cmake_naive#switch_target()

    let l:active_commands = s:path_join(l:fixture.root, 'build/compile_commands.json')
    call assert_equal(
          \ {'output': 'build', 'preset': 'dev', 'target': 'mylib', 'keep': 1},
          \ s:read_json(l:config_path))
    call assert_true(filereadable(l:active_commands))
    call assert_equal(readfile(l:target_lib_commands, 'b'), readfile(l:active_commands, 'b'))
  finally
    if l:initial_use_popup is v:null
      unlet! g:vim_cmake_naive_test_use_popup_menu
    else
      let g:vim_cmake_naive_test_use_popup_menu = l:initial_use_popup
    endif
    if l:initial_popup_response is v:null
      unlet! g:vim_cmake_naive_test_popup_menu_response
    else
      let g:vim_cmake_naive_test_popup_menu_response = l:initial_popup_response
    endif
    if l:initial_menu_selection is v:null
      unlet! g:vim_cmake_naive_test_menu_response
    else
      let g:vim_cmake_naive_test_menu_response = l:initial_menu_selection
    endif
    if l:initial_inputlist_selection is v:null
      unlet! g:vim_cmake_naive_test_inputlist_response
    else
      let g:vim_cmake_naive_test_inputlist_response = l:initial_inputlist_selection
    endif
    execute 'cd ' . fnameescape(l:initial_cwd)
    call delete(l:fixture.root, 'rf')
  endtry
endfunction

function! s:test_cmake_switch_target_falls_back_when_preset_dir_missing() abort
  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()
  let l:initial_selection = get(g:, 'vim_cmake_naive_test_inputlist_response', v:null)
  let l:initial_use_popup = get(g:, 'vim_cmake_naive_test_use_popup_menu', v:null)
  let l:initial_popup_response = get(g:, 'vim_cmake_naive_test_popup_menu_response', v:null)

  try
    let l:config_path = s:path_join(l:fixture.root, '.vim/.cmake/.config.json')
    call s:write_json(l:config_path, {'output': 'build', 'preset': 'missing-preset'})

    let l:target_default = s:path_join(l:fixture.root, 'build/CMakeFiles/default_app.dir')
    let l:target_default_commands = s:path_join(l:target_default, 'compile_commands.json')
    call mkdir(l:target_default, 'p')
    call s:write_json(l:target_default_commands, [{'file': '../default.cpp'}])

    execute 'cd ' . fnameescape(l:fixture.root)
    let g:vim_cmake_naive_test_inputlist_response = 1
    call vim_cmake_naive#switch_target()

    let l:active_commands = s:path_join(l:fixture.root, 'build/compile_commands.json')
    call assert_equal(
          \ {'output': 'build', 'preset': 'missing-preset', 'target': 'default_app'},
          \ s:read_json(l:config_path))
    call assert_true(filereadable(l:active_commands))
    call assert_equal(readfile(l:target_default_commands, 'b'), readfile(l:active_commands, 'b'))
  finally
    if l:initial_selection is v:null
      unlet! g:vim_cmake_naive_test_inputlist_response
    else
      let g:vim_cmake_naive_test_inputlist_response = l:initial_selection
    endif
    if l:initial_use_popup is v:null
      unlet! g:vim_cmake_naive_test_use_popup_menu
    else
      let g:vim_cmake_naive_test_use_popup_menu = l:initial_use_popup
    endif
    if l:initial_popup_response is v:null
      unlet! g:vim_cmake_naive_test_popup_menu_response
    else
      let g:vim_cmake_naive_test_popup_menu_response = l:initial_popup_response
    endif
    execute 'cd ' . fnameescape(l:initial_cwd)
    call delete(l:fixture.root, 'rf')
  endtry
endfunction

function! s:test_cmake_switch_target_cancels_without_changing_config() abort
  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()
  let l:initial_selection = get(g:, 'vim_cmake_naive_test_inputlist_response', v:null)
  let l:initial_use_popup = get(g:, 'vim_cmake_naive_test_use_popup_menu', v:null)
  let l:initial_popup_response = get(g:, 'vim_cmake_naive_test_popup_menu_response', v:null)

  try
    let l:config_path = s:path_join(l:fixture.root, '.vim/.cmake/.config.json')
    call s:write_json(l:config_path, {'output': 'build', 'preset': 'dev', 'target': 'stay'})

    let l:target_dir = s:path_join(l:fixture.root, 'build/dev/CMakeFiles/app.dir')
    let l:active_commands = s:path_join(l:fixture.root, 'build/compile_commands.json')
    call mkdir(l:target_dir, 'p')
    call s:write_json(l:active_commands, [{'file': '../active-before-cancel.cpp'}])

    execute 'cd ' . fnameescape(l:fixture.root)
    let g:vim_cmake_naive_test_inputlist_response = 0
    execute 'silent CMakeSwitchTarget'

    call assert_equal({'output': 'build', 'preset': 'dev', 'target': 'stay'}, s:read_json(l:config_path))
    call assert_equal([json_encode([{'file': '../active-before-cancel.cpp'}])], readfile(l:active_commands, 'b'))
  finally
    if l:initial_selection is v:null
      unlet! g:vim_cmake_naive_test_inputlist_response
    else
      let g:vim_cmake_naive_test_inputlist_response = l:initial_selection
    endif
    if l:initial_use_popup is v:null
      unlet! g:vim_cmake_naive_test_use_popup_menu
    else
      let g:vim_cmake_naive_test_use_popup_menu = l:initial_use_popup
    endif
    if l:initial_popup_response is v:null
      unlet! g:vim_cmake_naive_test_popup_menu_response
    else
      let g:vim_cmake_naive_test_popup_menu_response = l:initial_popup_response
    endif
    execute 'cd ' . fnameescape(l:initial_cwd)
    call delete(l:fixture.root, 'rf')
  endtry
endfunction

function! s:test_cmake_switch_target_reports_missing_build_directory() abort
  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()

  try
    let l:config_path = s:path_join(l:fixture.root, '.vim/.cmake/.config.json')
    call s:write_json(l:config_path, {'output': 'missing-build', 'preset': 'dev'})

    execute 'cd ' . fnameescape(l:fixture.root)
    call vim_cmake_naive#switch_target()

    let l:messages = execute('messages')
    call assert_true(stridx(l:messages, 'Build directory not found:') >= 0)
    call assert_false(has_key(s:read_json(l:config_path), 'target'))
  finally
    execute 'cd ' . fnameescape(l:initial_cwd)
    call delete(l:fixture.root, 'rf')
  endtry
endfunction

function! s:test_cmake_switch_target_reports_when_no_targets_found() abort
  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()

  try
    let l:config_path = s:path_join(l:fixture.root, '.vim/.cmake/.config.json')
    call s:write_json(l:config_path, {'output': 'build', 'preset': 'dev'})
    call mkdir(s:path_join(l:fixture.root, 'build/dev'), 'p')

    execute 'cd ' . fnameescape(l:fixture.root)
    call vim_cmake_naive#switch_target()

    let l:messages = execute('messages')
    call assert_true(stridx(l:messages, 'No selectable targets found in directory:') >= 0)
    call assert_false(has_key(s:read_json(l:config_path), 'target'))
  finally
    execute 'cd ' . fnameescape(l:initial_cwd)
    call delete(l:fixture.root, 'rf')
  endtry
endfunction

function! s:test_cmake_switch_target_splits_root_when_selected_target_file_missing() abort
  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()
  let l:initial_selection = get(g:, 'vim_cmake_naive_test_inputlist_response', v:null)
  let l:initial_use_popup = get(g:, 'vim_cmake_naive_test_use_popup_menu', v:null)
  let l:initial_popup_response = get(g:, 'vim_cmake_naive_test_popup_menu_response', v:null)

  try
    let l:config_path = s:path_join(l:fixture.root, '.vim/.cmake/.config.json')
    call s:write_json(l:config_path, {'output': 'build', 'preset': 'dev'})

    let l:scan_root = s:path_join(l:fixture.root, 'build/dev')
    let l:target_dir = s:path_join(l:scan_root, 'CMakeFiles/app.dir')
    let l:root_commands = s:path_join(l:scan_root, 'compile_commands.json')
    let l:active_commands = s:path_join(l:fixture.root, 'build/compile_commands.json')
    call mkdir(l:target_dir, 'p')
    call s:write_json(l:root_commands, s:fixture_entries())

    execute 'cd ' . fnameescape(l:fixture.root)
    let g:vim_cmake_naive_test_inputlist_response = 1
    call vim_cmake_naive#switch_target()

    call assert_true(filereadable(s:path_join(l:scan_root, 'CMakeFiles/app.dir/compile_commands.json')))
    call assert_true(filereadable(l:active_commands))
    call assert_equal(
          \ readfile(s:path_join(l:scan_root, 'CMakeFiles/app.dir/compile_commands.json'), 'b'),
          \ readfile(l:active_commands, 'b'))
    call assert_equal('app', get(s:read_json(l:config_path), 'target', ''))
  finally
    if l:initial_selection is v:null
      unlet! g:vim_cmake_naive_test_inputlist_response
    else
      let g:vim_cmake_naive_test_inputlist_response = l:initial_selection
    endif
    if l:initial_use_popup is v:null
      unlet! g:vim_cmake_naive_test_use_popup_menu
    else
      let g:vim_cmake_naive_test_use_popup_menu = l:initial_use_popup
    endif
    if l:initial_popup_response is v:null
      unlet! g:vim_cmake_naive_test_popup_menu_response
    else
      let g:vim_cmake_naive_test_popup_menu_response = l:initial_popup_response
    endif
    execute 'cd ' . fnameescape(l:initial_cwd)
    call delete(l:fixture.root, 'rf')
  endtry
endfunction

function! s:test_cmake_switch_target_reports_missing_root_compile_commands_for_split() abort
  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()
  let l:initial_selection = get(g:, 'vim_cmake_naive_test_inputlist_response', v:null)
  let l:initial_use_popup = get(g:, 'vim_cmake_naive_test_use_popup_menu', v:null)
  let l:initial_popup_response = get(g:, 'vim_cmake_naive_test_popup_menu_response', v:null)

  try
    let l:config_path = s:path_join(l:fixture.root, '.vim/.cmake/.config.json')
    call s:write_json(l:config_path, {'output': 'build', 'preset': 'dev'})

    call mkdir(s:path_join(l:fixture.root, 'build/dev/CMakeFiles/app.dir'), 'p')

    execute 'cd ' . fnameescape(l:fixture.root)
    let g:vim_cmake_naive_test_inputlist_response = 1
    call vim_cmake_naive#switch_target()

    let l:messages = execute('messages')
    call assert_true(stridx(l:messages, 'Root compile_commands.json not found at:') >= 0)
    call assert_false(has_key(s:read_json(l:config_path), 'target'))
    call assert_false(filereadable(s:path_join(l:fixture.root, 'build/compile_commands.json')))
  finally
    if l:initial_selection is v:null
      unlet! g:vim_cmake_naive_test_inputlist_response
    else
      let g:vim_cmake_naive_test_inputlist_response = l:initial_selection
    endif
    if l:initial_use_popup is v:null
      unlet! g:vim_cmake_naive_test_use_popup_menu
    else
      let g:vim_cmake_naive_test_use_popup_menu = l:initial_use_popup
    endif
    if l:initial_popup_response is v:null
      unlet! g:vim_cmake_naive_test_popup_menu_response
    else
      let g:vim_cmake_naive_test_popup_menu_response = l:initial_popup_response
    endif
    execute 'cd ' . fnameescape(l:initial_cwd)
    call delete(l:fixture.root, 'rf')
  endtry
endfunction

function! s:test_cmake_switch_target_uses_output_root_compile_commands_when_preset_root_missing_file() abort
  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()
  let l:initial_selection = get(g:, 'vim_cmake_naive_test_inputlist_response', v:null)
  let l:initial_use_popup = get(g:, 'vim_cmake_naive_test_use_popup_menu', v:null)
  let l:initial_popup_response = get(g:, 'vim_cmake_naive_test_popup_menu_response', v:null)

  try
    let l:config_path = s:path_join(l:fixture.root, '.vim/.cmake/.config.json')
    call s:write_json(l:config_path, {'output': 'build', 'preset': 'dev'})

    let l:target_dir = s:path_join(l:fixture.root, 'build/dev/CMakeFiles/app.dir')
    let l:root_commands = s:path_join(l:fixture.root, 'build/compile_commands.json')
    let l:active_commands = s:path_join(l:fixture.root, 'build/compile_commands.json')
    call mkdir(l:target_dir, 'p')
    call s:write_json(l:root_commands, s:fixture_entries())

    execute 'cd ' . fnameescape(l:fixture.root)
    let g:vim_cmake_naive_test_inputlist_response = 1
    call vim_cmake_naive#switch_target()

    let l:split_target_commands = s:path_join(l:fixture.root, 'build/CMakeFiles/app.dir/compile_commands.json')
    call assert_true(filereadable(l:split_target_commands))
    call assert_equal(
          \ readfile(l:split_target_commands, 'b'),
          \ readfile(l:active_commands, 'b'))
    call assert_equal('app', get(s:read_json(l:config_path), 'target', ''))
  finally
    if l:initial_selection is v:null
      unlet! g:vim_cmake_naive_test_inputlist_response
    else
      let g:vim_cmake_naive_test_inputlist_response = l:initial_selection
    endif
    if l:initial_use_popup is v:null
      unlet! g:vim_cmake_naive_test_use_popup_menu
    else
      let g:vim_cmake_naive_test_use_popup_menu = l:initial_use_popup
    endif
    if l:initial_popup_response is v:null
      unlet! g:vim_cmake_naive_test_popup_menu_response
    else
      let g:vim_cmake_naive_test_popup_menu_response = l:initial_popup_response
    endif
    execute 'cd ' . fnameescape(l:initial_cwd)
    call delete(l:fixture.root, 'rf')
  endtry
endfunction

function! s:test_switch_target_popup_display_items_marks_current_selection_and_limits_height() abort
  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()
  let l:initial_use_popup = get(g:, 'vim_cmake_naive_test_use_popup_menu', v:null)
  let l:initial_popup_response = get(g:, 'vim_cmake_naive_test_popup_menu_response', v:null)
  let l:initial_popup_items = get(g:, 'vim_cmake_naive_test_last_target_popup_items', v:null)
  let l:initial_popup_options = get(g:, 'vim_cmake_naive_test_last_target_popup_options', v:null)
  let l:initial_menu_selection = get(g:, 'vim_cmake_naive_test_menu_response', v:null)
  let l:initial_inputlist_selection = get(g:, 'vim_cmake_naive_test_inputlist_response', v:null)

  try
    let l:config_path = s:path_join(l:fixture.root, '.vim/.cmake/.config.json')
    call s:write_json(l:config_path, {'output': 'build', 'preset': 'dev', 'target': 't11'})

    let l:targets = ['t01', 't02', 't03', 't04', 't05', 't06', 't07', 't08', 't09', 't10', 't11']
    let l:index = 0
    while l:index < len(l:targets)
      call mkdir(s:path_join(l:fixture.root, 'build/dev/CMakeFiles/' . l:targets[l:index] . '.dir'), 'p')
      let l:index += 1
    endwhile

    let l:active_commands = s:path_join(l:fixture.root, 'build/compile_commands.json')
    call s:write_json(l:active_commands, [{'file': '../active-before-popup.cpp'}])

    execute 'cd ' . fnameescape(l:fixture.root)
    let g:vim_cmake_naive_test_use_popup_menu = 1
    let g:vim_cmake_naive_test_popup_menu_response = 0
    unlet! g:vim_cmake_naive_test_menu_response
    unlet! g:vim_cmake_naive_test_inputlist_response
    unlet! g:vim_cmake_naive_test_last_target_popup_items
    unlet! g:vim_cmake_naive_test_last_target_popup_options
    call vim_cmake_naive#switch_target()

    call assert_equal(
          \ [' 1.   t01', ' 2.   t02', ' 3.   t03', ' 4.   t04', ' 5.   t05', ' 6.   t06', ' 7.   t07', ' 8.   t08', ' 9.   t09', '10.   t10', '11. * t11'],
          \ get(g:, 'vim_cmake_naive_test_last_target_popup_items', []))
    call assert_equal('Select CMake target', get(g:vim_cmake_naive_test_last_target_popup_options, 'title', ''))
    call assert_equal(30, get(g:vim_cmake_naive_test_last_target_popup_options, 'minwidth', 0))
    call assert_equal(30, get(g:vim_cmake_naive_test_last_target_popup_options, 'maxwidth', 0))
    call assert_equal(10, get(g:vim_cmake_naive_test_last_target_popup_options, 'minheight', 0))
    call assert_equal(10, get(g:vim_cmake_naive_test_last_target_popup_options, 'maxheight', 0))
    call assert_equal(1, get(g:vim_cmake_naive_test_last_target_popup_options, 'scrollbar', 0))
    call assert_equal([1, 1, 1, 1], get(g:vim_cmake_naive_test_last_target_popup_options, 'border', []))
    call assert_equal(['─', '│', '─', '│', '╭', '╮', '╯', '╰'], get(g:vim_cmake_naive_test_last_target_popup_options, 'borderchars', []))
    call assert_equal('Pmenu', get(g:vim_cmake_naive_test_last_target_popup_options, 'highlight', ''))
    call assert_equal(['Pmenu'], get(g:vim_cmake_naive_test_last_target_popup_options, 'borderhighlight', []))
    call assert_equal({'output': 'build', 'preset': 'dev', 'target': 't11'}, s:read_json(l:config_path))
    call assert_equal([json_encode([{'file': '../active-before-popup.cpp'}])], readfile(l:active_commands, 'b'))
  finally
    if l:initial_use_popup is v:null
      unlet! g:vim_cmake_naive_test_use_popup_menu
    else
      let g:vim_cmake_naive_test_use_popup_menu = l:initial_use_popup
    endif
    if l:initial_popup_response is v:null
      unlet! g:vim_cmake_naive_test_popup_menu_response
    else
      let g:vim_cmake_naive_test_popup_menu_response = l:initial_popup_response
    endif
    if l:initial_popup_items is v:null
      unlet! g:vim_cmake_naive_test_last_target_popup_items
    else
      let g:vim_cmake_naive_test_last_target_popup_items = l:initial_popup_items
    endif
    if l:initial_popup_options is v:null
      unlet! g:vim_cmake_naive_test_last_target_popup_options
    else
      let g:vim_cmake_naive_test_last_target_popup_options = l:initial_popup_options
    endif
    if l:initial_menu_selection is v:null
      unlet! g:vim_cmake_naive_test_menu_response
    else
      let g:vim_cmake_naive_test_menu_response = l:initial_menu_selection
    endif
    if l:initial_inputlist_selection is v:null
      unlet! g:vim_cmake_naive_test_inputlist_response
    else
      let g:vim_cmake_naive_test_inputlist_response = l:initial_inputlist_selection
    endif
    execute 'cd ' . fnameescape(l:initial_cwd)
    call delete(l:fixture.root, 'rf')
  endtry
endfunction

function! s:test_switch_target_popup_filters_items_by_search_query() abort
  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()
  let l:initial_use_popup = get(g:, 'vim_cmake_naive_test_use_popup_menu', v:null)
  let l:initial_popup_response = get(g:, 'vim_cmake_naive_test_popup_menu_response', v:null)
  let l:initial_popup_items = get(g:, 'vim_cmake_naive_test_last_target_popup_items', v:null)
  let l:initial_popup_options = get(g:, 'vim_cmake_naive_test_last_target_popup_options', v:null)
  let l:initial_menu_selection = get(g:, 'vim_cmake_naive_test_menu_response', v:null)
  let l:initial_inputlist_selection = get(g:, 'vim_cmake_naive_test_inputlist_response', v:null)

  try
    let l:config_path = s:path_join(l:fixture.root, '.vim/.cmake/.config.json')
    call s:write_json(l:config_path, {'output': 'build', 'preset': 'dev', 'target': 'old'})

    let l:target_app = s:path_join(l:fixture.root, 'build/dev/CMakeFiles/app.dir')
    let l:target_lib = s:path_join(l:fixture.root, 'build/dev/lib/CMakeFiles/mylib.dir')
    let l:target_app_commands = s:path_join(l:target_app, 'compile_commands.json')
    let l:target_lib_commands = s:path_join(l:target_lib, 'compile_commands.json')
    call mkdir(l:target_app, 'p')
    call mkdir(l:target_lib, 'p')
    call s:write_json(l:target_app_commands, [{'file': '../src/main.cpp'}])
    call s:write_json(l:target_lib_commands, [{'file': '../lib/foo.cpp'}])

    execute 'cd ' . fnameescape(l:fixture.root)
    let g:vim_cmake_naive_test_use_popup_menu = 1
    let g:vim_cmake_naive_test_popup_menu_response = {'query': 'LIB', 'result': 1}
    unlet! g:vim_cmake_naive_test_last_target_popup_items
    unlet! g:vim_cmake_naive_test_last_target_popup_options
    unlet! g:vim_cmake_naive_test_menu_response
    unlet! g:vim_cmake_naive_test_inputlist_response
    call vim_cmake_naive#switch_target()

    let l:active_commands = s:path_join(l:fixture.root, 'build/compile_commands.json')
    call assert_equal(['1.   mylib'], get(g:, 'vim_cmake_naive_test_last_target_popup_items', []))
    call assert_equal('Select CMake target [LIB]', get(g:vim_cmake_naive_test_last_target_popup_options, 'title', ''))
    call assert_equal(30, get(g:vim_cmake_naive_test_last_target_popup_options, 'minwidth', 0))
    call assert_equal(30, get(g:vim_cmake_naive_test_last_target_popup_options, 'maxwidth', 0))
    call assert_equal(1, get(g:vim_cmake_naive_test_last_target_popup_options, 'minheight', 0))
    call assert_equal(1, get(g:vim_cmake_naive_test_last_target_popup_options, 'maxheight', 0))
    call assert_equal({'output': 'build', 'preset': 'dev', 'target': 'mylib'}, s:read_json(l:config_path))
    call assert_true(filereadable(l:active_commands))
    call assert_equal(readfile(l:target_lib_commands, 'b'), readfile(l:active_commands, 'b'))
  finally
    if l:initial_use_popup is v:null
      unlet! g:vim_cmake_naive_test_use_popup_menu
    else
      let g:vim_cmake_naive_test_use_popup_menu = l:initial_use_popup
    endif
    if l:initial_popup_response is v:null
      unlet! g:vim_cmake_naive_test_popup_menu_response
    else
      let g:vim_cmake_naive_test_popup_menu_response = l:initial_popup_response
    endif
    if l:initial_popup_items is v:null
      unlet! g:vim_cmake_naive_test_last_target_popup_items
    else
      let g:vim_cmake_naive_test_last_target_popup_items = l:initial_popup_items
    endif
    if l:initial_popup_options is v:null
      unlet! g:vim_cmake_naive_test_last_target_popup_options
    else
      let g:vim_cmake_naive_test_last_target_popup_options = l:initial_popup_options
    endif
    if l:initial_menu_selection is v:null
      unlet! g:vim_cmake_naive_test_menu_response
    else
      let g:vim_cmake_naive_test_menu_response = l:initial_menu_selection
    endif
    if l:initial_inputlist_selection is v:null
      unlet! g:vim_cmake_naive_test_inputlist_response
    else
      let g:vim_cmake_naive_test_inputlist_response = l:initial_inputlist_selection
    endif
    execute 'cd ' . fnameescape(l:initial_cwd)
    call delete(l:fixture.root, 'rf')
  endtry
endfunction

function! VimCMakeNaiveTestRunAll() abort
  call s:test_split_writes_target_files()
  call s:test_split_handles_symlinked_build_directory()
  call s:test_split_dry_run_does_not_write_files()
  call s:test_split_honors_input_and_output_name()
  call s:test_split_honors_equals_style_input_and_output_name()
  call s:test_switch_copies_to_build_root_by_default()
  call s:test_switch_honors_output_directory()
  call s:test_switch_honors_equals_style_output_directory()
  call s:test_split_reports_missing_input_file()
  call s:test_switch_reports_missing_target_directory()
  call s:test_cmake_config_creates_default_local_config()
  call s:test_cmake_config_preserves_existing_file()
  call s:test_cmake_set_config_preset_creates_config_with_preset()
  call s:test_cmake_set_config_preset_preserves_existing_keys()
  call s:test_cmake_reset_config_preset_creates_config_with_empty_preset()
  call s:test_cmake_reset_config_preset_preserves_other_keys()
  call s:test_cmake_reset_config_target_creates_config_with_empty_target()
  call s:test_cmake_reset_config_target_preserves_other_keys()
  call s:test_cmake_set_config_build_config_creates_config_with_value()
  call s:test_cmake_set_config_build_config_preserves_other_keys()
  call s:test_cmake_set_config_output_creates_config_with_value()
  call s:test_cmake_set_config_output_preserves_other_keys()
  call s:test_cmake_set_commands_use_nearest_existing_local_config()
  call s:test_cmake_set_commands_error_when_no_local_config_found()
  call s:test_cmake_commands_report_running_command_lock()
  call s:test_cmake_command_lock_resets_after_command_failure()
  call s:test_cmake_config_default_creates_default_values()
  call s:test_cmake_config_default_reapplies_defaults_and_preserves_other_keys()
  call s:test_cmake_config_uses_nearest_parent_cmakelists()
  call s:test_cmake_config_errors_when_no_cmakelists_found()
  call s:test_cmake_config_default_uses_nearest_parent_cmakelists()
  call s:test_cmake_config_default_errors_when_no_cmakelists_found()
  call s:test_cmake_generate_creates_default_config_and_invokes_cmake()
  call s:test_cmake_generate_uses_existing_config_values()
  call s:test_cmake_generate_opens_vertical_terminal_with_command_output()
  call s:test_cmake_generate_reuses_visible_output_window_when_possible()
  call s:test_cmake_generate_errors_when_no_cmakelists_found()
  call s:test_cmake_build_creates_default_config_and_invokes_cmake_build()
  call s:test_cmake_build_uses_existing_config_preset_and_target()
  call s:test_cmake_build_sets_running_terminal_name_with_preset_and_target()
  call s:test_cmake_build_opens_vertical_terminal_with_command_output()
  call s:test_cmake_build_opens_vertical_terminal_with_stdout_and_stderr_output()
  call s:test_cmake_build_sets_failure_terminal_name_with_exit_code()
  call s:test_cmake_build_reuses_visible_output_window_when_possible()
  call s:test_cmake_build_recreates_visible_output_window_when_reuse_not_possible()
  call s:test_cmake_build_errors_when_no_cmakelists_found()
  call s:test_cmake_info_popup_shows_config_as_table()
  call s:test_cmake_info_popup_reports_missing_config()
  call s:test_cmake_menu_popup_lists_compact_commands_and_executes_selection()
  call s:test_cmake_menu_popup_lists_commands_and_executes_selection()
  call s:test_cmake_menu_executes_command_with_arguments()
  call s:test_cmake_menu_cancels_argument_command_when_args_empty()
  call s:test_cmake_menu_cancels_without_executing_when_popup_canceled()
  call s:test_cmake_switch_preset_sets_selected_visible_preset()
  call s:test_cmake_switch_preset_reports_missing_presets_file()
  call s:test_cmake_switch_preset_cancels_without_changing_config()
  call s:test_cmake_switch_preset_reports_no_selectable_presets()
  call s:test_preset_popup_display_items_formats_ordered_list_and_current_marker()
  call s:test_cmake_switch_target_sets_selected_target()
  call s:test_cmake_switch_target_popup_sets_selected_target()
  call s:test_cmake_switch_target_falls_back_when_preset_dir_missing()
  call s:test_cmake_switch_target_cancels_without_changing_config()
  call s:test_cmake_switch_target_reports_missing_build_directory()
  call s:test_cmake_switch_target_reports_when_no_targets_found()
  call s:test_cmake_switch_target_splits_root_when_selected_target_file_missing()
  call s:test_cmake_switch_target_reports_missing_root_compile_commands_for_split()
  call s:test_cmake_switch_target_uses_output_root_compile_commands_when_preset_root_missing_file()
  call s:test_switch_target_popup_display_items_marks_current_selection_and_limits_height()
  call s:test_switch_target_popup_filters_items_by_search_query()
endfunction
