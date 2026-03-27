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
    execute 'silent CMakeConfigResetPreset'

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
    call assert_equal(
          \ ['-S', l:expected_root, '-B', l:expected_build_dir, '-DCMAKE_BUILD_TYPE=Debug'],
          \ s:read_non_empty_lines(l:args_path))
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
    call assert_equal(
          \ [
          \   '-S',
          \   l:expected_root,
          \   '-B',
          \   s:path_join(l:expected_root, 'out/build-dir'),
          \   '-DCMAKE_BUILD_TYPE=Release',
          \   '--preset',
          \   'dev'
          \ ],
          \ s:read_non_empty_lines(l:args_path))
  finally
    let $PATH = l:initial_path
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

function! s:test_cmake_switch_preset_sets_selected_visible_preset() abort
  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()
  let l:initial_selection = get(g:, 'vim_cmake_naive_test_inputlist_response', v:null)

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
    let g:vim_cmake_naive_test_inputlist_response = 2
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

  try
    let l:config_path = s:path_join(l:fixture.root, '.vim/.cmake/.config.json')
    call s:write_json(l:config_path, {'preset': 'stay'})
    call s:write_cmake_presets(
          \ s:path_join(l:fixture.root, 'CMakePresets.json'),
          \ [{'name': 'dev'}, {'name': 'default'}])

    execute 'cd ' . fnameescape(l:fixture.root)
    let g:vim_cmake_naive_test_inputlist_response = 0
    execute 'silent CMakeSwitchPreset'

    call assert_equal({'preset': 'stay'}, s:read_json(l:config_path))
  finally
    if l:initial_selection is v:null
      unlet! g:vim_cmake_naive_test_inputlist_response
    else
      let g:vim_cmake_naive_test_inputlist_response = l:initial_selection
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
  call s:test_cmake_set_config_build_config_creates_config_with_value()
  call s:test_cmake_set_config_build_config_preserves_other_keys()
  call s:test_cmake_set_config_output_creates_config_with_value()
  call s:test_cmake_set_config_output_preserves_other_keys()
  call s:test_cmake_set_commands_use_nearest_existing_local_config()
  call s:test_cmake_set_commands_error_when_no_local_config_found()
  call s:test_cmake_config_default_creates_default_values()
  call s:test_cmake_config_default_reapplies_defaults_and_preserves_other_keys()
  call s:test_cmake_config_uses_nearest_parent_cmakelists()
  call s:test_cmake_config_errors_when_no_cmakelists_found()
  call s:test_cmake_config_default_uses_nearest_parent_cmakelists()
  call s:test_cmake_config_default_errors_when_no_cmakelists_found()
  call s:test_cmake_generate_creates_default_config_and_invokes_cmake()
  call s:test_cmake_generate_uses_existing_config_values()
  call s:test_cmake_generate_errors_when_no_cmakelists_found()
  call s:test_cmake_switch_preset_sets_selected_visible_preset()
  call s:test_cmake_switch_preset_reports_missing_presets_file()
  call s:test_cmake_switch_preset_cancels_without_changing_config()
  call s:test_cmake_switch_preset_reports_no_selectable_presets()
endfunction
