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

function! s:create_fake_ctest_script(root, args_output_path, cwd_output_path, exit_code) abort
  let l:bin_dir = s:path_join(a:root, 'fake-bin')
  call mkdir(l:bin_dir, 'p')
  let l:script_path = s:path_join(l:bin_dir, 'ctest')
  call writefile([
        \ '#!/bin/sh',
        \ 'printf "%s\n" "$@" > ' . shellescape(a:args_output_path),
        \ 'pwd > ' . shellescape(a:cwd_output_path),
        \ 'exit ' . string(a:exit_code)
        \ ], l:script_path, 'b')
  call system('chmod +x ' . shellescape(l:script_path))
  return l:bin_dir
endfunction

function! s:create_fake_cmake_generate_script_with_compile_commands(root, args_output_path, compile_commands, exit_code) abort
  let l:bin_dir = s:path_join(a:root, 'fake-bin')
  call mkdir(l:bin_dir, 'p')
  let l:script_path = s:path_join(l:bin_dir, 'cmake')
  let l:compile_commands_seed_path = s:path_join(a:root, 'fake-compile-commands-seed.json')
  call s:write_json(l:compile_commands_seed_path, a:compile_commands)
  call writefile([
        \ '#!/bin/sh',
        \ 'printf "%s\n" "$@" > ' . shellescape(a:args_output_path),
        \ 'build_dir=""',
        \ 'previous=""',
        \ 'for argument in "$@"; do',
        \ '  if [ "$previous" = "-B" ]; then',
        \ '    build_dir="$argument"',
        \ '  fi',
        \ '  previous="$argument"',
        \ 'done',
        \ 'if [ -n "$build_dir" ]; then',
        \ '  mkdir -p "$build_dir"',
        \ '  cat ' . shellescape(l:compile_commands_seed_path) . ' > "$build_dir/compile_commands.json"',
        \ 'fi',
        \ 'exit ' . string(a:exit_code)
        \ ], l:script_path, 'b')
  call system('chmod +x ' . shellescape(l:script_path))
  return l:bin_dir
endfunction

function! s:read_non_empty_lines(path) abort
  return filter(readfile(a:path, 'b'), '!empty(v:val)')
endfunction

function! s:assert_ctest_parallel_args(args_lines) abort
  call assert_equal(2, len(a:args_lines), 'Expected ctest to receive exactly two parallel arguments.')
  call assert_equal('--parallel', get(a:args_lines, 0, ''), 'Expected ctest to receive --parallel argument.')
  let l:parallel_level = get(a:args_lines, 1, '')
  call assert_true(
        \ l:parallel_level =~# '^[1-9][0-9]*$',
        \ 'Expected ctest parallel level to be a positive integer.')
endfunction

function! s:assert_cmake_build_parallel_args(args_lines, build_directory, ...) abort
  call assert_true(len(a:args_lines) >= 4, 'Expected cmake build to receive --build and --parallel arguments.')
  call assert_equal('--build', get(a:args_lines, 0, ''), 'Expected cmake build to start with --build.')
  call assert_equal(a:build_directory, get(a:args_lines, 1, ''), 'Expected cmake build directory argument to match.')
  call assert_equal('--parallel', get(a:args_lines, 2, ''), 'Expected cmake build to receive --parallel argument.')
  let l:parallel_level = get(a:args_lines, 3, '')
  call assert_true(
        \ l:parallel_level =~# '^[1-9][0-9]*$',
        \ 'Expected cmake build parallel level to be a positive integer.')
  call assert_equal(a:000, a:args_lines[4:])
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

function! s:wait_for_plugin_terminal_buffer_name(buffer_name, timeout_ms) abort
  let l:elapsed = 0
  while l:elapsed < a:timeout_ms
    for l:buffer_info in getbufinfo()
      let l:buffer_number = get(l:buffer_info, 'bufnr', -1)
      if l:buffer_number <= 0
            \ || !bufexists(l:buffer_number)
            \ || !getbufvar(l:buffer_number, 'vim_cmake_naive_build_terminal', 0)
        continue
      endif

      if bufname(l:buffer_number) ==# a:buffer_name
        return l:buffer_number
      endif
    endfor

    sleep 10m
    let l:elapsed += 10
  endwhile

  return -1
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

function! s:assert_plugin_plug_mappings(expected_mappings) abort
  for l:plug in sort(keys(a:expected_mappings))
    let l:rhs = maparg(l:plug, 'n')
    call assert_true(!empty(l:rhs), 'Expected mapping for ' . l:plug . '.')
    call assert_true(
          \ stridx(l:rhs, a:expected_mappings[l:plug]) >= 0,
          \ 'Expected mapping for ' . l:plug . ' to execute ' . a:expected_mappings[l:plug] . '.')
  endfor
endfunction

function! s:test_plugin_defines_plug_mappings_by_default() abort
  let l:expected_mappings = {
        \ '<Plug>(CMakeBuild)': 'CMakeBuild',
        \ '<Plug>(CMakeClose)': 'CMakeClose',
        \ '<Plug>(CMakeConfig)': 'CMakeConfig',
        \ '<Plug>(CMakeConfigDefault)': 'CMakeConfigDefault',
        \ '<Plug>(CMakeConfigSetOutput)': 'CMakeConfigSetOutput',
        \ '<Plug>(CMakeGenerate)': 'CMakeGenerate',
        \ '<Plug>(CMakeInfo)': 'CMakeInfo',
        \ '<Plug>(CMakeMenu)': 'CMakeMenu',
        \ '<Plug>(CMakeMenuFull)': 'CMakeMenuFull',
        \ '<Plug>(CMakeRun)': 'CMakeRun',
        \ '<Plug>(CMakeSwitchBuild)': 'CMakeSwitchBuild',
        \ '<Plug>(CMakeSwitchPreset)': 'CMakeSwitchPreset',
        \ '<Plug>(CMakeSwitchTarget)': 'CMakeSwitchTarget',
        \ '<Plug>(CMakeTest)': 'CMakeTest'
        \ }

  call s:assert_plugin_plug_mappings(l:expected_mappings)
endfunction

function! s:test_plugin_registers_plug_mappings_for_commands() abort
  let l:expected_mappings = {
        \ '<Plug>(CMakeBuild)': 'CMakeBuild',
        \ '<Plug>(CMakeClose)': 'CMakeClose',
        \ '<Plug>(CMakeConfig)': 'CMakeConfig',
        \ '<Plug>(CMakeConfigDefault)': 'CMakeConfigDefault',
        \ '<Plug>(CMakeConfigSetOutput)': 'CMakeConfigSetOutput',
        \ '<Plug>(CMakeGenerate)': 'CMakeGenerate',
        \ '<Plug>(CMakeInfo)': 'CMakeInfo',
        \ '<Plug>(CMakeMenu)': 'CMakeMenu',
        \ '<Plug>(CMakeMenuFull)': 'CMakeMenuFull',
        \ '<Plug>(CMakeRun)': 'CMakeRun',
        \ '<Plug>(CMakeSwitchBuild)': 'CMakeSwitchBuild',
        \ '<Plug>(CMakeSwitchPreset)': 'CMakeSwitchPreset',
        \ '<Plug>(CMakeSwitchTarget)': 'CMakeSwitchTarget',
        \ '<Plug>(CMakeTest)': 'CMakeTest'
        \ }

  call vim_cmake_naive#register_plug_mappings()
  call s:assert_plugin_plug_mappings(l:expected_mappings)
endfunction

function! s:test_plugin_startup_syncs_integration_files_from_local_config() abort
  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()
  let l:plugin_path = get(globpath(&runtimepath, 'plugin/vim_cmake_naive.vim', 1, 1), 0, '')
  let l:plugin_path = fnamemodify(l:plugin_path, ':p')
  let l:initial_loaded_plugin = get(g:, 'loaded_vim_cmake_naive', v:null)

  try
    call assert_true(!empty(l:plugin_path), 'Expected plugin/vim_cmake_naive.vim to exist in runtimepath.')
    let l:config_path = s:path_join(l:fixture.root, '.vim-cmake-naive-config.json')
    let l:target_state_path = s:path_join(l:fixture.root, '.vim-cmake-naive-target')
    let l:output_state_path = s:path_join(l:fixture.root, '.vim-cmake-naive-output')
    call s:write_json(l:config_path, {'output': 'out/build', 'preset': 'dev', 'target': 'my_target'})
    call delete(l:target_state_path)
    call delete(l:output_state_path)

    execute 'cd ' . fnameescape(l:fixture.root)
    unlet! g:loaded_vim_cmake_naive
    execute 'source ' . fnameescape(l:plugin_path)

    call assert_true(filereadable(l:target_state_path), 'Expected .vim-cmake-naive-target to be created during startup.')
    call assert_true(filereadable(l:output_state_path), 'Expected .vim-cmake-naive-output to be created during startup.')
    call assert_equal(['my_target'], readfile(l:target_state_path, 'b'))
    call assert_equal(['out/build/dev'], readfile(l:output_state_path, 'b'))
  finally
    if l:initial_loaded_plugin is v:null
      unlet! g:loaded_vim_cmake_naive
    else
      let g:loaded_vim_cmake_naive = l:initial_loaded_plugin
    endif
    execute 'cd ' . fnameescape(l:initial_cwd)
    call delete(l:fixture.root, 'rf')
  endtry
endfunction

function! s:test_cmake_config_creates_default_local_config() abort
  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()

  try
    execute 'cd ' . fnameescape(l:fixture.root)
    execute 'silent CMakeConfig'

    let l:config_path = s:path_join(l:fixture.root, '.vim-cmake-naive-config.json')
    call assert_true(filereadable(l:config_path), 'Expected .vim-cmake-naive-config.json to be created.')
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
    let l:config_path = s:path_join(l:fixture.root, '.vim-cmake-naive-config.json')
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
    call vim_cmake_naive#set_config_preset('debug')

    let l:config_path = s:path_join(l:fixture.root, '.vim-cmake-naive-config.json')
    call assert_true(filereadable(l:config_path), 'Expected .vim-cmake-naive-config.json to be created.')
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
    let l:config_path = s:path_join(l:fixture.root, '.vim-cmake-naive-config.json')
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

function! s:test_cmake_set_config_build_config_creates_config_with_value() abort
  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()

  try
    execute 'cd ' . fnameescape(l:fixture.root)
    execute 'silent CMakeConfig'
    call vim_cmake_naive#set_config_build_config('Debug')

    let l:config_path = s:path_join(l:fixture.root, '.vim-cmake-naive-config.json')
    call assert_true(filereadable(l:config_path), 'Expected .vim-cmake-naive-config.json to be created.')
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
    let l:config_path = s:path_join(l:fixture.root, '.vim-cmake-naive-config.json')
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

    let l:config_path = s:path_join(l:fixture.root, '.vim-cmake-naive-config.json')
    let l:output_state_path = s:path_join(l:fixture.root, '.vim-cmake-naive-output')
    call assert_true(filereadable(l:config_path), 'Expected .vim-cmake-naive-config.json to be created.')
    call assert_equal({'output': 'build'}, s:read_json(l:config_path))
    call assert_true(filereadable(l:output_state_path), 'Expected .vim-cmake-naive-output to be created.')
    call assert_equal(['build'], readfile(l:output_state_path, 'b'))
  finally
    execute 'cd ' . fnameescape(l:initial_cwd)
    call delete(l:fixture.root, 'rf')
  endtry
endfunction

function! s:test_cmake_set_config_output_preserves_other_keys() abort
  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()

  try
    let l:config_path = s:path_join(l:fixture.root, '.vim-cmake-naive-config.json')
    let l:output_state_path = s:path_join(l:fixture.root, '.vim-cmake-naive-output')
    call s:write_json(l:config_path, {'preset': 'debug', 'build': 'RelWithDebInfo', 'output': 'old'})

    execute 'cd ' . fnameescape(l:fixture.root)
    call vim_cmake_naive#set_config_output('out/build')

    call assert_equal(
          \ {'preset': 'debug', 'build': 'RelWithDebInfo', 'output': 'out/build'},
          \ s:read_json(l:config_path))
    call assert_true(filereadable(l:output_state_path), 'Expected .vim-cmake-naive-output to be created.')
    call assert_equal(['out/build/debug'], readfile(l:output_state_path, 'b'))
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

    call vim_cmake_naive#set_config_preset('release')
    call vim_cmake_naive#set_config_build_config('RelWithDebInfo')
    execute 'silent CMakeConfigSetOutput out/build'

    let l:root_config_path = s:path_join(l:fixture.root, '.vim-cmake-naive-config.json')
    let l:deep_config_path = s:path_join(l:deep_dir, '.vim-cmake-naive-config.json')
    let l:root_output_state_path = s:path_join(l:fixture.root, '.vim-cmake-naive-output')
    let l:deep_output_state_path = s:path_join(l:deep_dir, '.vim-cmake-naive-output')
    let l:config = s:read_json(l:root_config_path)

    call assert_equal('release', get(l:config, 'preset', ''))
    call assert_equal('RelWithDebInfo', get(l:config, 'build', ''))
    call assert_equal('out/build', get(l:config, 'output', ''))
    call assert_false(filereadable(l:deep_config_path), 'Set commands should update nearest existing parent config, not create nested config.')
    call assert_true(filereadable(l:root_output_state_path), 'Expected .vim-cmake-naive-output at project root.')
    call assert_equal(['out/build/release'], readfile(l:root_output_state_path, 'b'))
    call assert_false(filereadable(l:deep_output_state_path), 'Expected no .vim-cmake-naive-output in nested directory.')
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
    call assert_true(stridx(l:messages, '.vim-cmake-naive-config.json not found in current directory or any parent directory.') >= 0)
    call assert_false(filereadable(s:path_join(l:fixture.root, '.vim-cmake-naive-config.json')))
  finally
    execute 'cd ' . fnameescape(l:initial_cwd)
    call delete(l:fixture.root, 'rf')
  endtry
endfunction

function! s:test_cmake_set_commands_do_not_use_parent_project_config() abort
  let l:outer_fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()

  try
    let l:inner_root = s:path_join(l:outer_fixture.root, 'inner')
    let l:inner_deep_dir = s:path_join(l:inner_root, 'src')
    let l:outer_config_path = s:path_join(l:outer_fixture.root, '.vim-cmake-naive-config.json')
    let l:inner_config_path = s:path_join(l:inner_root, '.vim-cmake-naive-config.json')
    call mkdir(l:inner_deep_dir, 'p')
    call writefile(
          \ ['cmake_minimum_required(VERSION 3.20)', 'project(vim_cmake_naive_inner_test)'],
          \ s:path_join(l:inner_root, 'CMakeLists.txt'),
          \ 'b')
    call s:write_json(l:outer_config_path, {'output': 'outer-build', 'keep': 1})

    execute 'cd ' . fnameescape(l:inner_deep_dir)
    call vim_cmake_naive#set_config_output('inner-build')

    let l:messages = execute('messages')
    call assert_true(stridx(l:messages, '.vim-cmake-naive-config.json not found in current directory or any parent directory.') >= 0)
    call assert_false(filereadable(l:inner_config_path))
    call assert_equal({'output': 'outer-build', 'keep': 1}, s:read_json(l:outer_config_path))
  finally
    execute 'cd ' . fnameescape(l:initial_cwd)
    call delete(l:outer_fixture.root, 'rf')
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
    call vim_cmake_naive#switch_build()
    call vim_cmake_naive#switch_target()
    call vim_cmake_naive#generate()
    call vim_cmake_naive#build()
    call vim_cmake_naive#test()
    call vim_cmake_naive#run()
    call vim_cmake_naive#set_config_preset('dev')
    call vim_cmake_naive#set_config_build_config('Debug')
    call vim_cmake_naive#set_config_output('build')
    call vim_cmake_naive#info()
    call vim_cmake_naive#menu()
    call vim_cmake_naive#menu_full()

    let l:messages = execute('messages')
    call assert_true(stridx(l:messages, 'CMake: another command CMakeBuild is already running') >= 0)
    call assert_false(filereadable(s:path_join(l:fixture.root, '.vim-cmake-naive-config.json')))
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

    let l:config_path = s:path_join(l:root, '.vim-cmake-naive-config.json')
    call assert_true(filereadable(l:config_path), 'Expected CMakeConfig to succeed after prior failure.')
  finally
    execute 'cd ' . fnameescape(l:initial_cwd)
    call delete(l:root, 'rf')
  endtry
endfunction

function! s:test_cmake_command_lock_persists_while_async_terminal_command_runs() abort
  if !has('unix')
    return
  endif

  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()
  let l:initial_path = $PATH
  let l:initial_capture_terminal = get(g:, 'vim_cmake_naive_test_capture_build_terminal', v:null)

  try
    let l:args_path = s:path_join(l:fixture.root, 'cmake-build-lock-args.txt')
    let l:bin_dir = s:path_join(l:fixture.root, 'fake-bin')
    let l:script_path = s:path_join(l:bin_dir, 'cmake')
    call mkdir(l:bin_dir, 'p')
    call writefile([
          \ '#!/bin/sh',
          \ 'printf "%s\n" "$@" > ' . shellescape(l:args_path),
          \ 'sleep 2',
          \ 'exit 0'
          \ ], l:script_path, 'b')
    call system('chmod +x ' . shellescape(l:script_path))
    let $PATH = l:bin_dir . ':' . l:initial_path

    execute 'cd ' . fnameescape(l:fixture.root)
    let g:vim_cmake_naive_test_capture_build_terminal = 0
    call vim_cmake_naive#close()
    call vim_cmake_naive#build()

    let l:running_window_id = s:wait_for_running_terminal_window(1000)
    call assert_true(l:running_window_id > 0, 'Expected running build terminal window.')

    call vim_cmake_naive#info()
    let l:messages = execute('messages')
    call assert_true(stridx(l:messages, 'CMake: another command CMakeBuild is already running') >= 0)

    let l:success_buffer_number = s:wait_for_plugin_terminal_buffer_name('Success', 3000)
    call assert_true(l:success_buffer_number > 0, 'Expected build terminal title to become Success after command completion.')

    call vim_cmake_naive#set_config_output('out')
    let l:config_path = s:path_join(l:fixture.root, '.vim-cmake-naive-config.json')
    call assert_equal('out', get(s:read_json(l:config_path), 'output', ''))
  finally
    sleep 100m
    let $PATH = l:initial_path
    if l:initial_capture_terminal is v:null
      unlet! g:vim_cmake_naive_test_capture_build_terminal
    else
      let g:vim_cmake_naive_test_capture_build_terminal = l:initial_capture_terminal
    endif
    execute 'cd ' . fnameescape(l:initial_cwd)
    call delete(l:fixture.root, 'rf')
  endtry
endfunction

function! s:test_cmake_menu_popup_holds_command_lock_until_closed() abort
  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()
  let l:initial_use_popup = get(g:, 'vim_cmake_naive_test_use_popup_menu', v:null)
  let l:initial_popup_response = get(g:, 'vim_cmake_naive_test_popup_menu_response', v:null)
  let l:initial_menu_selection = get(g:, 'vim_cmake_naive_test_menu_response', v:null)
  let l:initial_inputlist_selection = get(g:, 'vim_cmake_naive_test_inputlist_response', v:null)
  let l:initial_forced_running_command = get(g:, 'vim_cmake_naive_test_forced_running_cmake_command', v:null)

  try
    execute 'cd ' . fnameescape(l:fixture.root)
    let g:vim_cmake_naive_test_use_popup_menu = 1
    let g:vim_cmake_naive_test_popup_menu_response = {'hold_lock': 1}
    unlet! g:vim_cmake_naive_test_menu_response
    unlet! g:vim_cmake_naive_test_inputlist_response

    call vim_cmake_naive#menu_full()

    call vim_cmake_naive#cmake_config()
    let l:messages = execute('messages')
    call assert_true(stridx(l:messages, 'CMake: another command CMakeMenuFull is already running') >= 0)
    call assert_false(filereadable(s:path_join(l:fixture.root, '.vim-cmake-naive-config.json')))

    let g:vim_cmake_naive_test_forced_running_cmake_command = ''
    call vim_cmake_naive#cmake_config()
    call assert_true(filereadable(s:path_join(l:fixture.root, '.vim-cmake-naive-config.json')))
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
    if l:initial_forced_running_command is v:null
      unlet! g:vim_cmake_naive_test_forced_running_cmake_command
    else
      let g:vim_cmake_naive_test_forced_running_cmake_command = l:initial_forced_running_command
    endif
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

    let l:config_path = s:path_join(l:fixture.root, '.vim-cmake-naive-config.json')
    call assert_true(filereadable(l:config_path), 'Expected .vim-cmake-naive-config.json to be created.')
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
    let l:config_path = s:path_join(l:fixture.root, '.vim-cmake-naive-config.json')
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

    let l:config_path = s:path_join(l:fixture.root, '.vim-cmake-naive-config.json')
    let l:wrong_path = s:path_join(l:deep_dir, '.vim-cmake-naive-config.json')
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
    call assert_false(filereadable(s:path_join(l:root, '.vim-cmake-naive-config.json')))
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

    let l:config_path = s:path_join(l:fixture.root, '.vim-cmake-naive-config.json')
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
    call assert_false(filereadable(s:path_join(l:root, '.vim-cmake-naive-config.json')))
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

    let l:config_path = s:path_join(l:fixture.root, '.vim-cmake-naive-config.json')
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
    let l:config_path = s:path_join(l:fixture.root, '.vim-cmake-naive-config.json')
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
          \   l:expected_preset_build_dir,
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

function! s:test_cmake_generate_opens_horizontal_terminal_with_command_output() abort
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
    call assert_equal(1, get(l:terminal, 'is_horizontal_split', 0))
    call assert_equal(1, get(l:terminal, 'is_preview_window', 0))
    call assert_equal(0, get(l:terminal, 'is_vertical_split', 0))
    call assert_equal(0, get(l:terminal, 'swapfile_enabled', 1))
    let l:expected_max_height = min([10, max([1, winheight(0) / 2])])
    call assert_equal(l:expected_max_height, get(l:terminal, 'max_height', 0))
    call assert_true(get(l:terminal, 'height', 0) <= get(l:terminal, 'max_height', 0))
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
    let l:expected_max_height = min([10, max([1, winheight(0) / 2])])
    call assert_equal(l:expected_max_height, get(l:second_terminal, 'max_height', 0))
    call assert_true(get(l:second_terminal, 'height', 0) <= get(l:second_terminal, 'max_height', 0))

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

function! s:test_cmake_generate_sets_running_terminal_name_on_subsequent_invocation() abort
  if !has('unix')
    return
  endif

  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()
  let l:initial_path = $PATH

  try
    let l:config_path = s:path_join(l:fixture.root, '.vim-cmake-naive-config.json')
    call s:write_json(
          \ l:config_path,
          \ {'output': 'build', 'preset': 'dev', 'build': 'Release'})

    let l:args_path = s:path_join(l:fixture.root, 'cmake-generate-args-subsequent-title.txt')
    let l:seed_compile_commands_path = s:path_join(l:fixture.root, 'cmake-generate-seed-subsequent-title.json')
    call s:write_json(l:seed_compile_commands_path, s:fixture_entries())

    let l:bin_dir = s:path_join(l:fixture.root, 'fake-bin')
    call mkdir(l:bin_dir, 'p')
    let l:script_path = s:path_join(l:bin_dir, 'cmake')
    call writefile([
          \ '#!/bin/sh',
          \ 'printf "%s\n" "$@" > ' . shellescape(l:args_path),
          \ 'build_dir=""',
          \ 'previous=""',
          \ 'for argument in "$@"; do',
          \ '  if [ "$previous" = "-B" ]; then',
          \ '    build_dir="$argument"',
          \ '  fi',
          \ '  previous="$argument"',
          \ 'done',
          \ 'if [ -n "$build_dir" ]; then',
          \ '  mkdir -p "$build_dir"',
          \ '  cat ' . shellescape(l:seed_compile_commands_path) . ' > "$build_dir/compile_commands.json"',
          \ 'fi',
          \ 'echo "generate-subsequent-first-run"',
          \ 'exit 0'
          \ ], l:script_path, 'b')
    call system('chmod +x ' . shellescape(l:script_path))
    let $PATH = l:bin_dir . ':' . l:initial_path

    execute 'cd ' . fnameescape(l:fixture.root)
    call vim_cmake_naive#close()
    call vim_cmake_naive#generate()

    call assert_true(s:wait_for_file(l:args_path, 1000), 'Expected first fake cmake generate args file to be created.')
    let l:first_success_buffer_number = s:wait_for_plugin_terminal_buffer_name('Success', 1000)
    call assert_true(l:first_success_buffer_number > 0, 'Expected first generate terminal title to become Success.')

    call writefile([
          \ '#!/bin/sh',
          \ 'printf "%s\n" "$@" > ' . shellescape(l:args_path),
          \ 'build_dir=""',
          \ 'previous=""',
          \ 'for argument in "$@"; do',
          \ '  if [ "$previous" = "-B" ]; then',
          \ '    build_dir="$argument"',
          \ '  fi',
          \ '  previous="$argument"',
          \ 'done',
          \ 'if [ -n "$build_dir" ]; then',
          \ '  mkdir -p "$build_dir"',
          \ '  cat ' . shellescape(l:seed_compile_commands_path) . ' > "$build_dir/compile_commands.json"',
          \ 'fi',
          \ 'echo "generate-subsequent-second-run-start"',
          \ 'sleep 2',
          \ 'echo "generate-subsequent-second-run-end"',
          \ 'exit 0'
          \ ], l:script_path, 'b')
    call system('chmod +x ' . shellescape(l:script_path))

    call vim_cmake_naive#generate()

    let l:running_window_id = s:wait_for_running_terminal_window(1000)
    call assert_true(l:running_window_id > 0, 'Expected running generate terminal window on second invocation.')
    let l:running_buffer_number = winbufnr(win_id2win(l:running_window_id))
    call assert_equal('cmake generate --preset=dev', bufname(l:running_buffer_number))
    let l:origin_window_id = win_getid()
    if win_gotoid(l:running_window_id)
      let l:current_window_number = winnr()
      let l:is_vertical_split = winnr('h') != l:current_window_number
            \ || winnr('l') != l:current_window_number
      let l:is_horizontal_split = winnr('k') != l:current_window_number
            \ || winnr('j') != l:current_window_number
      call assert_equal(1, l:is_horizontal_split)
      call assert_equal(0, l:is_vertical_split)
    endif
    if win_id2win(l:origin_window_id) > 0
      call win_gotoid(l:origin_window_id)
    endif

    sleep 2200m
    if win_id2win(l:running_window_id) > 0
      let l:completed_buffer_number = winbufnr(win_id2win(l:running_window_id))
      call assert_equal('Success', bufname(l:completed_buffer_number))
    endif
  finally
    sleep 100m
    let $PATH = l:initial_path
    execute 'cd ' . fnameescape(l:initial_cwd)
    call delete(l:fixture.root, 'rf')
  endtry
endfunction

function! s:test_cmake_build_reuses_generate_output_window_when_possible() abort
  if !has('unix')
    return
  endif

  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()
  let l:initial_path = $PATH
  let l:initial_capture_terminal = get(g:, 'vim_cmake_naive_test_capture_build_terminal', v:null)
  let l:initial_last_terminal = get(g:, 'vim_cmake_naive_test_last_build_terminal', v:null)

  try
    let l:generate_args_path = s:path_join(l:fixture.root, 'cmake-generate-args-cross-reuse.txt')
    let l:build_args_path = s:path_join(l:fixture.root, 'cmake-build-args-cross-reuse.txt')
    let l:bin_dir = s:path_join(l:fixture.root, 'fake-bin')
    call mkdir(l:bin_dir, 'p')
    let l:script_path = s:path_join(l:bin_dir, 'cmake')
    call writefile([
          \ '#!/bin/sh',
          \ 'if [ "$1" = "--build" ]; then',
          \ '  printf "%s\n" "$@" > ' . shellescape(l:build_args_path),
          \ '  echo "cross-reuse-build-after-generate"',
          \ '  exit 0',
          \ 'fi',
          \ 'printf "%s\n" "$@" > ' . shellescape(l:generate_args_path),
          \ 'echo "cross-reuse-generate-before-build"',
          \ 'exit 0'
          \ ], l:script_path, 'b')
    call system('chmod +x ' . shellescape(l:script_path))
    let $PATH = l:bin_dir . ':' . l:initial_path

    execute 'cd ' . fnameescape(l:fixture.root)
    let g:vim_cmake_naive_test_capture_build_terminal = 1
    unlet! g:vim_cmake_naive_test_last_build_terminal
    call vim_cmake_naive#generate()

    let l:first_terminal = s:wait_for_captured_build_terminal_output('cross-reuse-generate-before-build', 1000)
    let l:first_window_id = get(l:first_terminal, 'winid', 0)
    call assert_true(l:first_window_id > 0)

    unlet! g:vim_cmake_naive_test_last_build_terminal
    call vim_cmake_naive#build()

    let l:second_terminal = s:wait_for_captured_build_terminal_output('cross-reuse-build-after-generate', 1000)
    let l:second_window_id = get(l:second_terminal, 'winid', 0)
    call assert_true(l:second_window_id > 0)
    call assert_equal(l:first_window_id, l:second_window_id)

    let l:expected_root = s:normalized_path(l:fixture.root)
    call assert_true(s:wait_for_file(l:generate_args_path, 1000), 'Expected fake cmake generate args file to be created.')
    call assert_true(s:wait_for_file(l:build_args_path, 1000), 'Expected fake cmake build args file to be created.')
    call assert_equal(
          \ ['-S', l:expected_root, '-B', s:path_join(l:expected_root, 'build'), '--fresh', '-DCMAKE_BUILD_TYPE=Debug'],
          \ s:read_non_empty_lines(l:generate_args_path))
    call s:assert_cmake_build_parallel_args(
          \ s:read_non_empty_lines(l:build_args_path),
          \ s:path_join(l:expected_root, 'build'))
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

function! s:test_cmake_generate_updates_targets_cache_and_splits_compile_commands() abort
  if !has('unix')
    return
  endif

  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()
  let l:initial_path = $PATH
  let l:initial_capture_terminal = get(g:, 'vim_cmake_naive_test_capture_build_terminal', v:null)
  let l:initial_last_terminal = get(g:, 'vim_cmake_naive_test_last_build_terminal', v:null)

  try
    let l:args_path = s:path_join(l:fixture.root, 'cmake-generate-cache-args.txt')
    let l:bin_dir = s:create_fake_cmake_generate_script_with_compile_commands(
          \ l:fixture.root,
          \ l:args_path,
          \ s:fixture_entries(),
          \ 0)
    let $PATH = l:bin_dir . ':' . l:initial_path

    execute 'cd ' . fnameescape(l:fixture.root)
    let g:vim_cmake_naive_test_capture_build_terminal = 1
    unlet! g:vim_cmake_naive_test_last_build_terminal
    call vim_cmake_naive#generate()

    let l:cache_path = s:path_join(l:fixture.root, '.vim-cmake-naive-cache.json')
    let l:app_split_path = s:path_join(
          \ s:path_join(s:path_join(l:fixture.root, 'build/CMakeFiles'), 'app.dir'),
          \ 'compile_commands.json')
    let l:lib_split_path = s:path_join(
          \ s:path_join(s:path_join(l:fixture.root, 'build/lib/CMakeFiles'), 'mylib.dir'),
          \ 'compile_commands.json')
    call assert_true(s:wait_for_file(l:cache_path, 1000), 'Expected local cache file to be written.')
    call assert_equal(['app', 'mylib'], get(s:read_json(l:cache_path), 'targets', []))
    call assert_true(filereadable(l:app_split_path), 'Expected app split compile_commands.json to be written.')
    call assert_true(filereadable(l:lib_split_path), 'Expected mylib split compile_commands.json to be written.')
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

function! s:test_cmake_generate_updates_targets_cache_and_splits_compile_commands_for_preset_directory() abort
  if !has('unix')
    return
  endif

  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()
  let l:initial_path = $PATH
  let l:initial_capture_terminal = get(g:, 'vim_cmake_naive_test_capture_build_terminal', v:null)
  let l:initial_last_terminal = get(g:, 'vim_cmake_naive_test_last_build_terminal', v:null)

  try
    let l:config_path = s:path_join(l:fixture.root, '.vim-cmake-naive-config.json')
    call s:write_json(l:config_path, {'output': 'out/build-dir', 'preset': 'dev', 'build': 'Release'})

    let l:args_path = s:path_join(l:fixture.root, 'cmake-generate-cache-preset-args.txt')
    let l:bin_dir = s:create_fake_cmake_generate_script_with_compile_commands(
          \ l:fixture.root,
          \ l:args_path,
          \ s:fixture_entries(),
          \ 0)
    let $PATH = l:bin_dir . ':' . l:initial_path

    execute 'cd ' . fnameescape(l:fixture.root)
    let g:vim_cmake_naive_test_capture_build_terminal = 1
    unlet! g:vim_cmake_naive_test_last_build_terminal
    call vim_cmake_naive#generate()

    let l:cache_path = s:path_join(l:fixture.root, '.vim-cmake-naive-cache.json')
    let l:preset_root = s:path_join(l:fixture.root, 'out/build-dir/dev')
    let l:app_split_path = s:path_join(
          \ s:path_join(s:path_join(l:preset_root, 'CMakeFiles'), 'app.dir'),
          \ 'compile_commands.json')
    let l:lib_split_path = s:path_join(
          \ s:path_join(s:path_join(l:preset_root, 'lib/CMakeFiles'), 'mylib.dir'),
          \ 'compile_commands.json')
    call assert_true(s:wait_for_file(l:cache_path, 1000), 'Expected local cache file to be written.')
    call assert_equal(['app', 'mylib'], get(s:read_json(l:cache_path), 'targets', []))
    call assert_true(filereadable(l:app_split_path), 'Expected app split compile_commands.json in preset directory.')
    call assert_true(filereadable(l:lib_split_path), 'Expected mylib split compile_commands.json in preset directory.')
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

function! s:test_cmake_generate_ignores_targets_from_deps_directory() abort
  if !has('unix')
    return
  endif

  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()
  let l:initial_path = $PATH
  let l:initial_capture_terminal = get(g:, 'vim_cmake_naive_test_capture_build_terminal', v:null)
  let l:initial_last_terminal = get(g:, 'vim_cmake_naive_test_last_build_terminal', v:null)

  try
    let l:entries = copy(s:fixture_entries())
    call add(l:entries, {
          \ 'directory': '.',
          \ 'command': 'clang++ -I../build/_deps/zlib-src -o _deps/zlib-build/CMakeFiles/zlib.dir/adler32.c.o -c ../_deps/zlib-src/adler32.c',
          \ 'file': '../_deps/zlib-src/adler32.c',
          \ 'output': '_deps/zlib-build/CMakeFiles/zlib.dir/adler32.c.o'
          \ })

    let l:args_path = s:path_join(l:fixture.root, 'cmake-generate-cache-ignore-deps-args.txt')
    let l:bin_dir = s:create_fake_cmake_generate_script_with_compile_commands(
          \ l:fixture.root,
          \ l:args_path,
          \ l:entries,
          \ 0)
    let $PATH = l:bin_dir . ':' . l:initial_path

    execute 'cd ' . fnameescape(l:fixture.root)
    let g:vim_cmake_naive_test_capture_build_terminal = 1
    unlet! g:vim_cmake_naive_test_last_build_terminal
    call vim_cmake_naive#generate()

    let l:cache_path = s:path_join(l:fixture.root, '.vim-cmake-naive-cache.json')
    let l:deps_split_path = s:path_join(
          \ s:path_join(s:path_join(l:fixture.root, 'build/_deps/zlib-build/CMakeFiles'), 'zlib.dir'),
          \ 'compile_commands.json')
    call assert_true(s:wait_for_file(l:cache_path, 1000), 'Expected local cache file to be written.')
    call assert_equal(['app', 'mylib'], get(s:read_json(l:cache_path), 'targets', []))
    call assert_true(filereadable(l:deps_split_path), 'Expected split file for _deps target to be written.')
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

    let l:config_path = s:path_join(l:fixture.root, '.vim-cmake-naive-config.json')
    let l:expected_root = s:normalized_path(l:fixture.root)
    let l:expected_build_dir = s:path_join(l:expected_root, 'build')
    call assert_equal({'output': 'build', 'preset': '', 'build': 'Debug'}, s:read_json(l:config_path))
    call assert_true(s:wait_for_file(l:args_path, 1000), 'Expected fake cmake args file to be created.')
    call s:assert_cmake_build_parallel_args(s:read_non_empty_lines(l:args_path), l:expected_build_dir)
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
    let l:config_path = s:path_join(l:fixture.root, '.vim-cmake-naive-config.json')
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
    call s:assert_cmake_build_parallel_args(
          \ s:read_non_empty_lines(l:args_path),
          \ s:path_join(l:expected_root, 'out/build-dir/dev'),
          \ '--preset',
          \ 'dev',
          \ '--target',
          \ 'mylib')
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
    let l:config_path = s:path_join(l:fixture.root, '.vim-cmake-naive-config.json')
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

function! s:test_cmake_build_sets_running_terminal_name_on_subsequent_invocation() abort
  if !has('unix')
    return
  endif

  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()
  let l:initial_path = $PATH

  try
    let l:config_path = s:path_join(l:fixture.root, '.vim-cmake-naive-config.json')
    call s:write_json(
          \ l:config_path,
          \ {'output': 'build', 'preset': 'dev', 'target': 'mylib', 'build': 'Release'})

    let l:args_path = s:path_join(l:fixture.root, 'cmake-build-args-subsequent-title.txt')
    let l:bin_dir = s:path_join(l:fixture.root, 'fake-bin')
    call mkdir(l:bin_dir, 'p')
    let l:script_path = s:path_join(l:bin_dir, 'cmake')
    call writefile([
          \ '#!/bin/sh',
          \ 'printf "%s\n" "$@" > ' . shellescape(l:args_path),
          \ 'echo "build-subsequent-first-run"',
          \ 'exit 0'
          \ ], l:script_path, 'b')
    call system('chmod +x ' . shellescape(l:script_path))
    let $PATH = l:bin_dir . ':' . l:initial_path

    execute 'cd ' . fnameescape(l:fixture.root)
    call vim_cmake_naive#close()
    call vim_cmake_naive#build()

    call assert_true(s:wait_for_file(l:args_path, 1000), 'Expected first fake cmake build args file to be created.')
    let l:first_success_buffer_number = s:wait_for_plugin_terminal_buffer_name('Success', 1000)
    call assert_true(l:first_success_buffer_number > 0, 'Expected first build terminal title to become Success.')

    call writefile([
          \ '#!/bin/sh',
          \ 'printf "%s\n" "$@" > ' . shellescape(l:args_path),
          \ 'echo "build-subsequent-second-run-start"',
          \ 'sleep 2',
          \ 'echo "build-subsequent-second-run-end"',
          \ 'exit 0'
          \ ], l:script_path, 'b')
    call system('chmod +x ' . shellescape(l:script_path))

    call vim_cmake_naive#build()

    let l:running_window_id = s:wait_for_running_terminal_window(1000)
    call assert_true(l:running_window_id > 0, 'Expected running build terminal window on second invocation.')
    let l:running_buffer_number = winbufnr(win_id2win(l:running_window_id))
    call assert_equal('cmake build --preset=dev --target=mylib', bufname(l:running_buffer_number))

    sleep 2200m
    if win_id2win(l:running_window_id) > 0
      let l:completed_buffer_number = winbufnr(win_id2win(l:running_window_id))
      call assert_equal('Success', bufname(l:completed_buffer_number))
    endif
  finally
    sleep 100m
    let $PATH = l:initial_path
    execute 'cd ' . fnameescape(l:initial_cwd)
    call delete(l:fixture.root, 'rf')
  endtry
endfunction

function! s:test_cmake_build_opens_horizontal_terminal_with_command_output() abort
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
    call assert_equal(1, get(l:terminal, 'is_horizontal_split', 0))
    call assert_equal(1, get(l:terminal, 'is_preview_window', 0))
    call assert_equal(0, get(l:terminal, 'is_vertical_split', 0))
    call assert_equal(0, get(l:terminal, 'swapfile_enabled', 1))
    let l:expected_max_height = min([10, max([1, winheight(0) / 2])])
    call assert_equal(l:expected_max_height, get(l:terminal, 'max_height', 0))
    call assert_true(get(l:terminal, 'height', 0) <= get(l:terminal, 'max_height', 0))
    call assert_true(get(l:terminal, 'window_count', 0) >= 2)
    call assert_true(get(l:terminal, 'width', 0) > 0)
    call assert_equal('Success', get(l:terminal, 'buffer_name', ''))
    let l:terminal_text = join(get(l:terminal, 'lines', []), "\n")
    call assert_true(stridx(l:terminal_text, 'preview-build-line-1') >= 0)
    call assert_true(stridx(l:terminal_text, 'preview-build-line-2') >= 0)

    let l:expected_root = s:normalized_path(l:fixture.root)
    call assert_true(s:wait_for_file(l:args_path, 1000), 'Expected fake cmake args file to be created.')
    call s:assert_cmake_build_parallel_args(
          \ s:read_non_empty_lines(l:args_path),
          \ s:path_join(l:expected_root, 'build'))
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

function! s:test_cmake_build_opens_horizontal_terminal_with_stdout_and_stderr_output() abort
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
    call assert_equal(1, get(l:terminal, 'is_horizontal_split', 0))
    call assert_equal(1, get(l:terminal, 'is_preview_window', 0))
    call assert_equal(0, get(l:terminal, 'is_vertical_split', 0))
    call assert_equal('Success', get(l:terminal, 'buffer_name', ''))
    let l:terminal_text = join(get(l:terminal, 'lines', []), "\n")
    call assert_true(stridx(l:terminal_text, 'preview-stdout-line') >= 0)
    call assert_true(stridx(l:terminal_text, 'preview-stderr-line') >= 0)

    let l:expected_root = s:normalized_path(l:fixture.root)
    call assert_true(s:wait_for_file(l:args_path, 1000), 'Expected fake cmake args file to be created.')
    call s:assert_cmake_build_parallel_args(
          \ s:read_non_empty_lines(l:args_path),
          \ s:path_join(l:expected_root, 'build'))
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
    call s:assert_cmake_build_parallel_args(
          \ s:read_non_empty_lines(l:args_path),
          \ s:path_join(l:expected_root, 'build'))

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
    let l:expected_max_height = min([10, max([1, winheight(0) / 2])])
    call assert_equal(l:expected_max_height, get(l:second_terminal, 'max_height', 0))
    call assert_true(get(l:second_terminal, 'height', 0) <= get(l:second_terminal, 'max_height', 0))

    let l:expected_root = s:normalized_path(l:fixture.root)
    call assert_true(s:wait_for_file(l:args_path, 1000), 'Expected fake cmake args file to be created.')
    call s:assert_cmake_build_parallel_args(
          \ s:read_non_empty_lines(l:args_path),
          \ s:path_join(l:expected_root, 'build'))
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

function! s:test_cmake_build_does_not_resize_when_started_from_terminal_window() abort
  if !has('unix')
    return
  endif

  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()
  let l:initial_path = $PATH
  let l:initial_capture_terminal = get(g:, 'vim_cmake_naive_test_capture_build_terminal', v:null)
  let l:initial_last_terminal = get(g:, 'vim_cmake_naive_test_last_build_terminal', v:null)

  try
    let l:args_path = s:path_join(l:fixture.root, 'cmake-build-args-no-terminal-resize.txt')
    let l:bin_dir = s:path_join(l:fixture.root, 'fake-bin')
    call mkdir(l:bin_dir, 'p')
    let l:script_path = s:path_join(l:bin_dir, 'cmake')
    call writefile([
          \ '#!/bin/sh',
          \ 'printf "%s\n" "$@" > ' . shellescape(l:args_path),
          \ 'echo "origin-terminal-first-build"',
          \ 'exit 0'
          \ ], l:script_path, 'b')
    call system('chmod +x ' . shellescape(l:script_path))
    let $PATH = l:bin_dir . ':' . l:initial_path

    execute 'cd ' . fnameescape(l:fixture.root)
    let g:vim_cmake_naive_test_capture_build_terminal = 1
    unlet! g:vim_cmake_naive_test_last_build_terminal
    call vim_cmake_naive#build()

    let l:first_terminal = s:wait_for_captured_build_terminal_output('origin-terminal-first-build', 1000)
    let l:first_window_id = get(l:first_terminal, 'winid', 0)
    call assert_true(l:first_window_id > 0, 'Expected first build terminal window.')
    let l:first_height = get(l:first_terminal, 'height', 0)
    call assert_true(l:first_height > 0, 'Expected first build terminal window height to be positive.')

    call writefile([
          \ '#!/bin/sh',
          \ 'printf "%s\n" "$@" > ' . shellescape(l:args_path),
          \ 'echo "origin-terminal-second-build"',
          \ 'exit 0'
          \ ], l:script_path, 'b')
    call system('chmod +x ' . shellescape(l:script_path))

    call assert_true(win_gotoid(l:first_window_id), 'Expected build terminal window to become active.')
    let l:origin_terminal_buffer = bufnr('%')
    call assert_equal('terminal', getbufvar(l:origin_terminal_buffer, '&buftype', ''))

    unlet! g:vim_cmake_naive_test_last_build_terminal
    call vim_cmake_naive#build()

    let l:second_terminal = s:wait_for_captured_build_terminal_output('origin-terminal-second-build', 1000)
    let l:second_window_id = get(l:second_terminal, 'winid', 0)
    call assert_true(l:second_window_id > 0, 'Expected second build terminal window.')
    call assert_equal(l:first_window_id, l:second_window_id)
    call assert_equal(l:first_height, get(l:second_terminal, 'height', 0))

    let l:expected_root = s:normalized_path(l:fixture.root)
    call assert_true(s:wait_for_file(l:args_path, 1000), 'Expected fake cmake args file to be created.')
    call s:assert_cmake_build_parallel_args(
          \ s:read_non_empty_lines(l:args_path),
          \ s:path_join(l:expected_root, 'build'))
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

function! s:test_cmake_generate_reuses_build_output_window_when_possible() abort
  if !has('unix')
    return
  endif

  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()
  let l:initial_path = $PATH
  let l:initial_capture_terminal = get(g:, 'vim_cmake_naive_test_capture_build_terminal', v:null)
  let l:initial_last_terminal = get(g:, 'vim_cmake_naive_test_last_build_terminal', v:null)

  try
    let l:generate_args_path = s:path_join(l:fixture.root, 'cmake-generate-args-cross-reuse-2.txt')
    let l:build_args_path = s:path_join(l:fixture.root, 'cmake-build-args-cross-reuse-2.txt')
    let l:bin_dir = s:path_join(l:fixture.root, 'fake-bin')
    call mkdir(l:bin_dir, 'p')
    let l:script_path = s:path_join(l:bin_dir, 'cmake')
    call writefile([
          \ '#!/bin/sh',
          \ 'if [ "$1" = "--build" ]; then',
          \ '  printf "%s\n" "$@" > ' . shellescape(l:build_args_path),
          \ '  echo "cross-reuse-build-before-generate"',
          \ '  exit 0',
          \ 'fi',
          \ 'printf "%s\n" "$@" > ' . shellescape(l:generate_args_path),
          \ 'echo "cross-reuse-generate-after-build"',
          \ 'exit 0'
          \ ], l:script_path, 'b')
    call system('chmod +x ' . shellescape(l:script_path))
    let $PATH = l:bin_dir . ':' . l:initial_path

    execute 'cd ' . fnameescape(l:fixture.root)
    let g:vim_cmake_naive_test_capture_build_terminal = 1
    unlet! g:vim_cmake_naive_test_last_build_terminal
    call vim_cmake_naive#build()

    let l:first_terminal = s:wait_for_captured_build_terminal_output('cross-reuse-build-before-generate', 1000)
    let l:first_window_id = get(l:first_terminal, 'winid', 0)
    call assert_true(l:first_window_id > 0)

    unlet! g:vim_cmake_naive_test_last_build_terminal
    call vim_cmake_naive#generate()

    let l:second_terminal = s:wait_for_captured_build_terminal_output('cross-reuse-generate-after-build', 1000)
    let l:second_window_id = get(l:second_terminal, 'winid', 0)
    call assert_true(l:second_window_id > 0)
    call assert_equal(l:first_window_id, l:second_window_id)

    let l:expected_root = s:normalized_path(l:fixture.root)
    call assert_true(s:wait_for_file(l:generate_args_path, 1000), 'Expected fake cmake generate args file to be created.')
    call assert_true(s:wait_for_file(l:build_args_path, 1000), 'Expected fake cmake build args file to be created.')
    call assert_equal(
          \ ['-S', l:expected_root, '-B', s:path_join(l:expected_root, 'build'), '--fresh', '-DCMAKE_BUILD_TYPE=Debug'],
          \ s:read_non_empty_lines(l:generate_args_path))
    call s:assert_cmake_build_parallel_args(
          \ s:read_non_empty_lines(l:build_args_path),
          \ s:path_join(l:expected_root, 'build'))
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

function! s:test_cmake_generate_reuses_build_output_window_in_async_mode() abort
  if !has('unix') || !exists('*term_getstatus')
    return
  endif

  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()
  let l:initial_path = $PATH
  let l:initial_capture_terminal = get(g:, 'vim_cmake_naive_test_capture_build_terminal', v:null)

  try
    let l:build_args_path = s:path_join(l:fixture.root, 'cmake-build-args-async-cross-reuse.txt')
    let l:generate_args_path = s:path_join(l:fixture.root, 'cmake-generate-args-async-cross-reuse.txt')
    let l:bin_dir = s:path_join(l:fixture.root, 'fake-bin')
    call mkdir(l:bin_dir, 'p')
    let l:script_path = s:path_join(l:bin_dir, 'cmake')
    call writefile([
          \ '#!/bin/sh',
          \ 'if [ "$1" = "--build" ]; then',
          \ '  printf "%s\n" "$@" > ' . shellescape(l:build_args_path),
          \ '  echo "async-cross-reuse-build-start"',
          \ '  sleep 1',
          \ '  echo "async-cross-reuse-build-end"',
          \ '  exit 0',
          \ 'fi',
          \ 'printf "%s\n" "$@" > ' . shellescape(l:generate_args_path),
          \ 'echo "async-cross-reuse-generate-start"',
          \ 'sleep 2',
          \ 'echo "async-cross-reuse-generate-end"',
          \ 'exit 0'
          \ ], l:script_path, 'b')
    call system('chmod +x ' . shellescape(l:script_path))
    let $PATH = l:bin_dir . ':' . l:initial_path

    execute 'cd ' . fnameescape(l:fixture.root)
    call vim_cmake_naive#close()
    let g:vim_cmake_naive_test_capture_build_terminal = 0
    call vim_cmake_naive#build()

    let l:first_window_id = s:wait_for_running_terminal_window(1000)
    call assert_true(l:first_window_id > 0, 'Expected running build terminal window.')
    call assert_true(s:wait_for_file(l:build_args_path, 1000), 'Expected async build args file to be created.')

    sleep 1200m
    call vim_cmake_naive#generate()

    let l:second_window_id = s:wait_for_running_terminal_window(1000)
    call assert_true(l:second_window_id > 0, 'Expected running generate terminal window.')
    call assert_equal(l:first_window_id, l:second_window_id)

    call assert_true(s:wait_for_file(l:generate_args_path, 1000), 'Expected async generate args file to be created.')
    let l:expected_root = s:normalized_path(l:fixture.root)
    call s:assert_cmake_build_parallel_args(
          \ s:read_non_empty_lines(l:build_args_path),
          \ s:path_join(l:expected_root, 'build'))
    call assert_equal(
          \ ['-S', l:expected_root, '-B', s:path_join(l:expected_root, 'build'), '--fresh', '-DCMAKE_BUILD_TYPE=Debug'],
          \ s:read_non_empty_lines(l:generate_args_path))
  finally
    sleep 2200m
    let $PATH = l:initial_path
    if l:initial_capture_terminal is v:null
      unlet! g:vim_cmake_naive_test_capture_build_terminal
    else
      let g:vim_cmake_naive_test_capture_build_terminal = l:initial_capture_terminal
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

function! s:test_cmake_test_runs_ctest_in_output_directory_without_preset() abort
  if !has('unix')
    return
  endif

  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()
  let l:initial_path = $PATH

  try
    let l:args_path = s:path_join(l:fixture.root, 'ctest-args-no-preset.txt')
    let l:cwd_path = s:path_join(l:fixture.root, 'ctest-cwd-no-preset.txt')
    let l:bin_dir = s:create_fake_ctest_script(l:fixture.root, l:args_path, l:cwd_path, 0)
    let $PATH = l:bin_dir . ':' . l:initial_path

    let l:deep_dir = s:path_join(l:fixture.root, 'src')
    call mkdir(l:deep_dir, 'p')

    execute 'cd ' . fnameescape(l:deep_dir)
    execute 'silent CMakeTest'

    let l:config_path = s:path_join(l:fixture.root, '.vim-cmake-naive-config.json')
    let l:expected_root = s:normalized_path(l:fixture.root)
    let l:expected_test_dir = s:path_join(l:expected_root, 'build')
    call assert_equal({'output': 'build', 'preset': '', 'build': 'Debug'}, s:read_json(l:config_path))
    call assert_true(s:wait_for_file(l:args_path, 1000), 'Expected fake ctest args file to be created.')
    call assert_true(s:wait_for_file(l:cwd_path, 1000), 'Expected fake ctest cwd file to be created.')
    call s:assert_ctest_parallel_args(s:read_non_empty_lines(l:args_path))
    call assert_equal([l:expected_test_dir], s:read_non_empty_lines(l:cwd_path))
  finally
    let $PATH = l:initial_path
    execute 'cd ' . fnameescape(l:initial_cwd)
    call delete(l:fixture.root, 'rf')
  endtry
endfunction

function! s:test_cmake_test_runs_ctest_in_output_preset_directory_with_preset() abort
  if !has('unix')
    return
  endif

  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()
  let l:initial_path = $PATH

  try
    let l:config_path = s:path_join(l:fixture.root, '.vim-cmake-naive-config.json')
    call s:write_json(l:config_path, {'output': 'out/build-dir', 'preset': 'dev', 'build': 'Release'})

    let l:args_path = s:path_join(l:fixture.root, 'ctest-args-with-preset.txt')
    let l:cwd_path = s:path_join(l:fixture.root, 'ctest-cwd-with-preset.txt')
    let l:bin_dir = s:create_fake_ctest_script(l:fixture.root, l:args_path, l:cwd_path, 0)
    let $PATH = l:bin_dir . ':' . l:initial_path

    execute 'cd ' . fnameescape(l:fixture.root)
    call vim_cmake_naive#test()

    let l:expected_root = s:normalized_path(l:fixture.root)
    let l:expected_test_dir = s:path_join(l:expected_root, 'out/build-dir/dev')
    call assert_true(s:wait_for_file(l:args_path, 1000), 'Expected fake ctest args file to be created.')
    call assert_true(s:wait_for_file(l:cwd_path, 1000), 'Expected fake ctest cwd file to be created.')
    call s:assert_ctest_parallel_args(s:read_non_empty_lines(l:args_path))
    call assert_equal([l:expected_test_dir], s:read_non_empty_lines(l:cwd_path))
  finally
    let $PATH = l:initial_path
    execute 'cd ' . fnameescape(l:initial_cwd)
    call delete(l:fixture.root, 'rf')
  endtry
endfunction

function! s:test_cmake_test_sets_running_terminal_name_with_preset() abort
  if !has('unix')
    return
  endif

  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()
  let l:initial_path = $PATH

  try
    let l:config_path = s:path_join(l:fixture.root, '.vim-cmake-naive-config.json')
    call s:write_json(l:config_path, {'output': 'build', 'preset': 'dev'})

    let l:args_path = s:path_join(l:fixture.root, 'ctest-args-running-name-with-preset.txt')
    let l:cwd_path = s:path_join(l:fixture.root, 'ctest-cwd-running-name-with-preset.txt')
    let l:bin_dir = s:path_join(l:fixture.root, 'fake-bin')
    call mkdir(l:bin_dir, 'p')
    let l:script_path = s:path_join(l:bin_dir, 'ctest')
    call writefile([
          \ '#!/bin/sh',
          \ 'printf "%s\n" "$@" > ' . shellescape(l:args_path),
          \ 'pwd > ' . shellescape(l:cwd_path),
          \ 'echo "running-name-test-start"',
          \ 'sleep 2',
          \ 'echo "running-name-test-end"',
          \ 'exit 0'
          \ ], l:script_path, 'b')
    call system('chmod +x ' . shellescape(l:script_path))
    let $PATH = l:bin_dir . ':' . l:initial_path

    execute 'cd ' . fnameescape(l:fixture.root)
    call vim_cmake_naive#test()

    call assert_true(s:wait_for_file(l:args_path, 1000), 'Expected fake ctest args file to be created.')
    call s:assert_ctest_parallel_args(s:read_non_empty_lines(l:args_path))
    let l:running_window_id = s:wait_for_running_terminal_window(1000)
    call assert_true(l:running_window_id > 0, 'Expected running test terminal window.')
    let l:running_buffer_number = winbufnr(win_id2win(l:running_window_id))
    call assert_equal('ctest --preset=dev', bufname(l:running_buffer_number))
  finally
    sleep 2200m
    let $PATH = l:initial_path
    execute 'cd ' . fnameescape(l:initial_cwd)
    call delete(l:fixture.root, 'rf')
  endtry
endfunction

function! s:test_cmake_test_sets_running_terminal_name_without_preset() abort
  if !has('unix')
    return
  endif

  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()
  let l:initial_path = $PATH

  try
    let l:config_path = s:path_join(l:fixture.root, '.vim-cmake-naive-config.json')
    call s:write_json(l:config_path, {'output': 'build', 'preset': ''})

    let l:args_path = s:path_join(l:fixture.root, 'ctest-args-running-name-without-preset.txt')
    let l:cwd_path = s:path_join(l:fixture.root, 'ctest-cwd-running-name-without-preset.txt')
    let l:bin_dir = s:path_join(l:fixture.root, 'fake-bin')
    call mkdir(l:bin_dir, 'p')
    let l:script_path = s:path_join(l:bin_dir, 'ctest')
    call writefile([
          \ '#!/bin/sh',
          \ 'printf "%s\n" "$@" > ' . shellescape(l:args_path),
          \ 'pwd > ' . shellescape(l:cwd_path),
          \ 'echo "running-name-test-no-preset-start"',
          \ 'sleep 2',
          \ 'echo "running-name-test-no-preset-end"',
          \ 'exit 0'
          \ ], l:script_path, 'b')
    call system('chmod +x ' . shellescape(l:script_path))
    let $PATH = l:bin_dir . ':' . l:initial_path

    execute 'cd ' . fnameescape(l:fixture.root)
    call vim_cmake_naive#test()

    call assert_true(s:wait_for_file(l:args_path, 1000), 'Expected fake ctest args file to be created.')
    call s:assert_ctest_parallel_args(s:read_non_empty_lines(l:args_path))
    let l:running_window_id = s:wait_for_running_terminal_window(1000)
    call assert_true(l:running_window_id > 0, 'Expected running test terminal window.')
    let l:running_buffer_number = winbufnr(win_id2win(l:running_window_id))
    call assert_equal('ctest', bufname(l:running_buffer_number))
  finally
    sleep 2200m
    let $PATH = l:initial_path
    execute 'cd ' . fnameescape(l:initial_cwd)
    call delete(l:fixture.root, 'rf')
  endtry
endfunction

function! s:test_cmake_test_reuses_build_output_window_when_possible() abort
  if !has('unix')
    return
  endif

  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()
  let l:initial_path = $PATH
  let l:initial_capture_terminal = get(g:, 'vim_cmake_naive_test_capture_build_terminal', v:null)
  let l:initial_last_terminal = get(g:, 'vim_cmake_naive_test_last_build_terminal', v:null)

  try
    let l:build_args_path = s:path_join(l:fixture.root, 'cmake-build-args-cross-reuse-test.txt')
    let l:test_args_path = s:path_join(l:fixture.root, 'ctest-args-cross-reuse-test.txt')
    let l:test_cwd_path = s:path_join(l:fixture.root, 'ctest-cwd-cross-reuse-test.txt')
    let l:bin_dir = s:path_join(l:fixture.root, 'fake-bin')
    call mkdir(l:bin_dir, 'p')
    let l:cmake_script_path = s:path_join(l:bin_dir, 'cmake')
    call writefile([
          \ '#!/bin/sh',
          \ 'printf "%s\n" "$@" > ' . shellescape(l:build_args_path),
          \ 'echo "cross-reuse-build-before-test"',
          \ 'exit 0'
          \ ], l:cmake_script_path, 'b')
    call system('chmod +x ' . shellescape(l:cmake_script_path))
    let l:ctest_script_path = s:path_join(l:bin_dir, 'ctest')
    call writefile([
          \ '#!/bin/sh',
          \ 'printf "%s\n" "$@" > ' . shellescape(l:test_args_path),
          \ 'pwd > ' . shellescape(l:test_cwd_path),
          \ 'echo "cross-reuse-test-after-build"',
          \ 'exit 0'
          \ ], l:ctest_script_path, 'b')
    call system('chmod +x ' . shellescape(l:ctest_script_path))
    let $PATH = l:bin_dir . ':' . l:initial_path

    execute 'cd ' . fnameescape(l:fixture.root)
    let g:vim_cmake_naive_test_capture_build_terminal = 1
    unlet! g:vim_cmake_naive_test_last_build_terminal
    call vim_cmake_naive#build()

    let l:first_terminal = s:wait_for_captured_build_terminal_output('cross-reuse-build-before-test', 1000)
    let l:first_window_id = get(l:first_terminal, 'winid', 0)
    call assert_true(l:first_window_id > 0)

    unlet! g:vim_cmake_naive_test_last_build_terminal
    call vim_cmake_naive#test()

    let l:second_terminal = s:wait_for_captured_build_terminal_output('cross-reuse-test-after-build', 1000)
    let l:second_window_id = get(l:second_terminal, 'winid', 0)
    call assert_true(l:second_window_id > 0)
    call assert_equal(l:first_window_id, l:second_window_id)
    call assert_equal(0, get(l:second_terminal, 'swapfile_enabled', 1))

    let l:expected_root = s:normalized_path(l:fixture.root)
    call assert_true(s:wait_for_file(l:build_args_path, 1000), 'Expected fake cmake build args file to be created.')
    call assert_true(s:wait_for_file(l:test_args_path, 1000), 'Expected fake ctest args file to be created.')
    call assert_true(s:wait_for_file(l:test_cwd_path, 1000), 'Expected fake ctest cwd file to be created.')
    call s:assert_cmake_build_parallel_args(
          \ s:read_non_empty_lines(l:build_args_path),
          \ s:path_join(l:expected_root, 'build'))
    call s:assert_ctest_parallel_args(s:read_non_empty_lines(l:test_args_path))
    call assert_equal([s:path_join(l:expected_root, 'build')], s:read_non_empty_lines(l:test_cwd_path))
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

function! s:test_cmake_run_reports_missing_target_selection() abort
  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()

  try
    let l:config_path = s:path_join(l:fixture.root, '.vim-cmake-naive-config.json')
    call s:write_json(l:config_path, {'output': 'build', 'preset': '', 'build': 'Debug'})

    execute 'cd ' . fnameescape(l:fixture.root)
    call vim_cmake_naive#run()

    let l:messages = execute('messages')
    call assert_true(stridx(l:messages, 'No target selected. Please use CMakeSwitchTarget command first.') >= 0)
  finally
    execute 'cd ' . fnameescape(l:initial_cwd)
    call delete(l:fixture.root, 'rf')
  endtry
endfunction

function! s:test_cmake_run_runs_target_in_output_directory_without_preset() abort
  if !has('unix')
    return
  endif

  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()

  try
    let l:config_path = s:path_join(l:fixture.root, '.vim-cmake-naive-config.json')
    call s:write_json(l:config_path, {'output': 'build', 'preset': '', 'target': 'app', 'build': 'Debug'})

    let l:run_directory = s:path_join(l:fixture.root, 'build')
    let l:args_path = s:path_join(l:fixture.root, 'run-args-no-preset.txt')
    let l:cwd_path = s:path_join(l:fixture.root, 'run-cwd-no-preset.txt')
    let l:script_path = s:path_join(l:run_directory, 'app')
    call mkdir(l:run_directory, 'p')
    call writefile([
          \ '#!/bin/sh',
          \ 'printf "%s\n" "$@" > ' . shellescape(l:args_path),
          \ 'pwd > ' . shellescape(l:cwd_path),
          \ 'exit 0'
          \ ], l:script_path, 'b')
    call system('chmod +x ' . shellescape(l:script_path))

    execute 'cd ' . fnameescape(l:fixture.root)
    call vim_cmake_naive#run()

    let l:expected_run_directory = s:normalized_path(l:run_directory)
    call assert_true(s:wait_for_file(l:args_path, 1000), 'Expected run args file to be created.')
    call assert_true(s:wait_for_file(l:cwd_path, 1000), 'Expected run cwd file to be created.')
    call assert_equal([], s:read_non_empty_lines(l:args_path))
    call assert_equal([l:expected_run_directory], s:read_non_empty_lines(l:cwd_path))
  finally
    execute 'cd ' . fnameescape(l:initial_cwd)
    call delete(l:fixture.root, 'rf')
  endtry
endfunction

function! s:test_cmake_run_runs_target_in_output_preset_directory_with_preset() abort
  if !has('unix')
    return
  endif

  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()

  try
    let l:config_path = s:path_join(l:fixture.root, '.vim-cmake-naive-config.json')
    call s:write_json(l:config_path, {'output': 'out/build-dir', 'preset': 'dev', 'target': 'app', 'build': 'Release'})

    let l:run_directory = s:path_join(l:fixture.root, 'out/build-dir/dev')
    let l:args_path = s:path_join(l:fixture.root, 'run-args-with-preset.txt')
    let l:cwd_path = s:path_join(l:fixture.root, 'run-cwd-with-preset.txt')
    let l:script_path = s:path_join(l:run_directory, 'app')
    call mkdir(l:run_directory, 'p')
    call writefile([
          \ '#!/bin/sh',
          \ 'printf "%s\n" "$@" > ' . shellescape(l:args_path),
          \ 'pwd > ' . shellescape(l:cwd_path),
          \ 'exit 0'
          \ ], l:script_path, 'b')
    call system('chmod +x ' . shellescape(l:script_path))

    execute 'cd ' . fnameescape(l:fixture.root)
    call vim_cmake_naive#run()

    let l:expected_run_directory = s:normalized_path(l:run_directory)
    call assert_true(s:wait_for_file(l:args_path, 1000), 'Expected run args file to be created.')
    call assert_true(s:wait_for_file(l:cwd_path, 1000), 'Expected run cwd file to be created.')
    call assert_equal([], s:read_non_empty_lines(l:args_path))
    call assert_equal([l:expected_run_directory], s:read_non_empty_lines(l:cwd_path))
  finally
    execute 'cd ' . fnameescape(l:initial_cwd)
    call delete(l:fixture.root, 'rf')
  endtry
endfunction

function! s:test_cmake_run_sets_running_terminal_name_with_preset_and_target() abort
  if !has('unix')
    return
  endif

  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()

  try
    let l:config_path = s:path_join(l:fixture.root, '.vim-cmake-naive-config.json')
    call s:write_json(l:config_path, {'output': 'build', 'preset': 'dev', 'target': 'app', 'build': 'Release'})

    let l:run_directory = s:path_join(l:fixture.root, 'build/dev')
    let l:script_path = s:path_join(l:run_directory, 'app')
    call mkdir(l:run_directory, 'p')
    call writefile([
          \ '#!/bin/sh',
          \ 'echo "running-name-run-start"',
          \ 'sleep 2',
          \ 'echo "running-name-run-end"',
          \ 'exit 0'
          \ ], l:script_path, 'b')
    call system('chmod +x ' . shellescape(l:script_path))

    execute 'cd ' . fnameescape(l:fixture.root)
    call vim_cmake_naive#run()

    let l:running_window_id = s:wait_for_running_terminal_window(1000)
    call assert_true(l:running_window_id > 0, 'Expected running run terminal window.')
    let l:running_buffer_number = winbufnr(win_id2win(l:running_window_id))
    call assert_equal('cmake run --preset=dev --target=app', bufname(l:running_buffer_number))
  finally
    sleep 2200m
    execute 'cd ' . fnameescape(l:initial_cwd)
    call delete(l:fixture.root, 'rf')
  endtry
endfunction

function! s:test_cmake_run_opens_horizontal_terminal_with_command_output() abort
  if !has('unix')
    return
  endif

  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()
  let l:initial_capture_terminal = get(g:, 'vim_cmake_naive_test_capture_build_terminal', v:null)
  let l:initial_last_terminal = get(g:, 'vim_cmake_naive_test_last_build_terminal', v:null)

  try
    let l:config_path = s:path_join(l:fixture.root, '.vim-cmake-naive-config.json')
    call s:write_json(l:config_path, {'output': 'build', 'preset': '', 'target': 'app', 'build': 'Debug'})

    let l:run_directory = s:path_join(l:fixture.root, 'build')
    let l:run_marker_path = s:path_join(l:fixture.root, 'run-preview-marker.txt')
    let l:script_path = s:path_join(l:run_directory, 'app')
    call mkdir(l:run_directory, 'p')
    call writefile([
          \ '#!/bin/sh',
          \ 'echo "preview-run-line-1"',
          \ 'echo "preview-run-line-2"',
          \ 'echo "done" > ' . shellescape(l:run_marker_path),
          \ 'exit 0'
          \ ], l:script_path, 'b')
    call system('chmod +x ' . shellescape(l:script_path))

    execute 'cd ' . fnameescape(l:fixture.root)
    let g:vim_cmake_naive_test_capture_build_terminal = 1
    unlet! g:vim_cmake_naive_test_last_build_terminal
    call vim_cmake_naive#run()

    let l:terminal = get(g:, 'vim_cmake_naive_test_last_build_terminal', {})
    call assert_equal(1, get(l:terminal, 'is_terminal', 0))
    call assert_equal(1, get(l:terminal, 'is_horizontal_split', 0))
    call assert_equal(1, get(l:terminal, 'is_preview_window', 0))
    call assert_equal(0, get(l:terminal, 'is_vertical_split', 0))
    call assert_equal(0, get(l:terminal, 'swapfile_enabled', 1))
    let l:expected_max_height = min([10, max([1, winheight(0) / 2])])
    call assert_equal(l:expected_max_height, get(l:terminal, 'max_height', 0))
    call assert_equal('Success', get(l:terminal, 'buffer_name', ''))
    call assert_true(s:wait_for_file(l:run_marker_path, 1000), 'Expected run preview marker file to be created.')
  finally
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

function! s:test_cmake_run_reuses_build_output_window_when_possible() abort
  if !has('unix')
    return
  endif

  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()
  let l:initial_path = $PATH
  let l:initial_capture_terminal = get(g:, 'vim_cmake_naive_test_capture_build_terminal', v:null)
  let l:initial_last_terminal = get(g:, 'vim_cmake_naive_test_last_build_terminal', v:null)

  try
    let l:build_args_path = s:path_join(l:fixture.root, 'cmake-build-args-cross-reuse-run.txt')
    let l:run_args_path = s:path_join(l:fixture.root, 'run-args-cross-reuse-run.txt')
    let l:run_cwd_path = s:path_join(l:fixture.root, 'run-cwd-cross-reuse-run.txt')
    let l:bin_dir = s:path_join(l:fixture.root, 'fake-bin')
    call mkdir(l:bin_dir, 'p')
    let l:cmake_script_path = s:path_join(l:bin_dir, 'cmake')
    call writefile([
          \ '#!/bin/sh',
          \ 'printf "%s\n" "$@" > ' . shellescape(l:build_args_path),
          \ 'echo "cross-reuse-build-before-run"',
          \ 'exit 0'
          \ ], l:cmake_script_path, 'b')
    call system('chmod +x ' . shellescape(l:cmake_script_path))

    let l:run_directory = s:path_join(l:fixture.root, 'build')
    let l:run_script_path = s:path_join(l:run_directory, 'app')
    call mkdir(l:run_directory, 'p')
    call writefile([
          \ '#!/bin/sh',
          \ 'printf "%s\n" "$@" > ' . shellescape(l:run_args_path),
          \ 'pwd > ' . shellescape(l:run_cwd_path),
          \ 'echo "cross-reuse-run-after-build"',
          \ 'exit 0'
          \ ], l:run_script_path, 'b')
    call system('chmod +x ' . shellescape(l:run_script_path))

    let l:config_path = s:path_join(l:fixture.root, '.vim-cmake-naive-config.json')
    call s:write_json(l:config_path, {'output': 'build', 'preset': '', 'target': 'app', 'build': 'Debug'})
    let $PATH = l:bin_dir . ':' . l:initial_path

    execute 'cd ' . fnameescape(l:fixture.root)
    let g:vim_cmake_naive_test_capture_build_terminal = 1
    unlet! g:vim_cmake_naive_test_last_build_terminal
    call vim_cmake_naive#build()

    let l:first_terminal = s:wait_for_captured_build_terminal_output('cross-reuse-build-before-run', 1000)
    let l:first_window_id = get(l:first_terminal, 'winid', 0)
    call assert_true(l:first_window_id > 0)

    unlet! g:vim_cmake_naive_test_last_build_terminal
    call vim_cmake_naive#run()

    let l:second_terminal = s:wait_for_captured_build_terminal_output('cross-reuse-run-after-build', 1000)
    let l:second_window_id = get(l:second_terminal, 'winid', 0)
    call assert_true(l:second_window_id > 0)
    call assert_equal(l:first_window_id, l:second_window_id)

    let l:expected_root = s:normalized_path(l:fixture.root)
    call assert_true(s:wait_for_file(l:build_args_path, 1000), 'Expected fake cmake build args file to be created.')
    call assert_true(s:wait_for_file(l:run_args_path, 1000), 'Expected run args file to be created.')
    call assert_true(s:wait_for_file(l:run_cwd_path, 1000), 'Expected run cwd file to be created.')
    call s:assert_cmake_build_parallel_args(
          \ s:read_non_empty_lines(l:build_args_path),
          \ s:path_join(l:expected_root, 'build'),
          \ '--target',
          \ 'app')
    call assert_equal([], s:read_non_empty_lines(l:run_args_path))
    call assert_equal([s:path_join(l:expected_root, 'build')], s:read_non_empty_lines(l:run_cwd_path))
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

function! s:test_cmake_close_closes_generate_terminal_window() abort
  if !has('unix')
    return
  endif

  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()
  let l:initial_path = $PATH
  let l:initial_capture_terminal = get(g:, 'vim_cmake_naive_test_capture_build_terminal', v:null)
  let l:initial_last_terminal = get(g:, 'vim_cmake_naive_test_last_build_terminal', v:null)

  try
    let l:args_path = s:path_join(l:fixture.root, 'cmake-generate-args-close-window.txt')
    let l:state_path = s:path_join(l:fixture.root, 'generate-close-state.txt')
    let l:bin_dir = s:path_join(l:fixture.root, 'fake-bin')
    call mkdir(l:bin_dir, 'p')
    let l:script_path = s:path_join(l:bin_dir, 'cmake')
    call writefile([
          \ '#!/bin/sh',
          \ 'printf "%s\n" "$@" > ' . shellescape(l:args_path),
          \ 'echo "running" > ' . shellescape(l:state_path),
          \ 'echo "close-generate-start"',
          \ 'sleep 2',
          \ 'echo "close-generate-end"',
          \ 'exit 0'
          \ ], l:script_path, 'b')
    call system('chmod +x ' . shellescape(l:script_path))
    let $PATH = l:bin_dir . ':' . l:initial_path

    execute 'cd ' . fnameescape(l:fixture.root)
    let g:vim_cmake_naive_test_capture_build_terminal = 0
    unlet! g:vim_cmake_naive_test_last_build_terminal
    call vim_cmake_naive#generate()

    call assert_true(s:wait_for_file(l:state_path, 1000), 'Expected generate command to start.')
    let l:running_window_id = s:wait_for_running_terminal_window(1000)
    call assert_true(l:running_window_id > 0, 'Expected running generate terminal window.')

    call vim_cmake_naive#close()
    call assert_equal(0, win_id2win(l:running_window_id))
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

function! s:test_cmake_close_closes_build_terminal_window() abort
  if !has('unix')
    return
  endif

  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()
  let l:initial_path = $PATH
  let l:initial_capture_terminal = get(g:, 'vim_cmake_naive_test_capture_build_terminal', v:null)
  let l:initial_last_terminal = get(g:, 'vim_cmake_naive_test_last_build_terminal', v:null)

  try
    let l:args_path = s:path_join(l:fixture.root, 'cmake-build-args-close-window.txt')
    let l:state_path = s:path_join(l:fixture.root, 'build-close-state.txt')
    let l:bin_dir = s:path_join(l:fixture.root, 'fake-bin')
    call mkdir(l:bin_dir, 'p')
    let l:script_path = s:path_join(l:bin_dir, 'cmake')
    call writefile([
          \ '#!/bin/sh',
          \ 'printf "%s\n" "$@" > ' . shellescape(l:args_path),
          \ 'echo "running" > ' . shellescape(l:state_path),
          \ 'echo "close-build-start"',
          \ 'sleep 2',
          \ 'echo "close-build-end"',
          \ 'exit 0'
          \ ], l:script_path, 'b')
    call system('chmod +x ' . shellescape(l:script_path))
    let $PATH = l:bin_dir . ':' . l:initial_path

    execute 'cd ' . fnameescape(l:fixture.root)
    let g:vim_cmake_naive_test_capture_build_terminal = 0
    unlet! g:vim_cmake_naive_test_last_build_terminal
    call vim_cmake_naive#build()

    call assert_true(s:wait_for_file(l:state_path, 1000), 'Expected build command to start.')
    let l:running_window_id = s:wait_for_running_terminal_window(1000)
    call assert_true(l:running_window_id > 0, 'Expected running build terminal window.')

    call vim_cmake_naive#close()
    call assert_equal(0, win_id2win(l:running_window_id))
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

function! s:test_cmake_info_popup_shows_config_as_table() abort
  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()
  let l:initial_use_popup = get(g:, 'vim_cmake_naive_test_use_popup_menu', v:null)
  let l:initial_popup_response = get(g:, 'vim_cmake_naive_test_popup_menu_response', v:null)
  let l:initial_popup_items = get(g:, 'vim_cmake_naive_test_last_info_popup_items', v:null)
  let l:initial_popup_options = get(g:, 'vim_cmake_naive_test_last_info_popup_options', v:null)

  try
    let l:config_path = s:path_join(l:fixture.root, '.vim-cmake-naive-config.json')
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
    let l:expected_popup_width = min([100, max([10, strlen(l:popup_title), l:popup_line_width])])
    call assert_true(stridx(l:popup_title, 'CMake info [.vim-cmake-naive-config.json]') == 0)
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
    let l:expected_popup_width = min([100, max([10, strlen(l:popup_title), l:popup_line_width])])
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
          \ [' 1.   CMakeConfig', ' 2.   CMakeConfigDefault', ' 3.   CMakeSwitchPreset', ' 4.   CMakeSwitchBuild', ' 5.   CMakeSwitchTarget', ' 6.   CMakeGenerate', ' 7.   CMakeBuild', ' 8.   CMakeTest', ' 9.   CMakeRun', '10.   CMakeClose', '11.   CMakeInfo', '12.   CMakeMenu', '13.   CMakeMenuFull', '14.   CMakeConfigSetOutput'],
          \ get(g:, 'vim_cmake_naive_test_last_menu_popup_items', []))
    call assert_equal('Select command', get(g:vim_cmake_naive_test_last_menu_popup_options, 'title', ''))
    call assert_equal(30, get(g:vim_cmake_naive_test_last_menu_popup_options, 'minwidth', 0))
    call assert_equal(30, get(g:vim_cmake_naive_test_last_menu_popup_options, 'maxwidth', 0))
    call assert_equal(10, get(g:vim_cmake_naive_test_last_menu_popup_options, 'minheight', 0))
    call assert_equal(10, get(g:vim_cmake_naive_test_last_menu_popup_options, 'maxheight', 0))
    call assert_equal(1, get(g:vim_cmake_naive_test_last_menu_popup_options, 'scrollbar', 0))
    call assert_equal([1, 1, 1, 1], get(g:vim_cmake_naive_test_last_menu_popup_options, 'border', []))
    call assert_equal(['─', '│', '─', '│', '╭', '╮', '╯', '╰'], get(g:vim_cmake_naive_test_last_menu_popup_options, 'borderchars', []))
    call assert_equal('Pmenu', get(g:vim_cmake_naive_test_last_menu_popup_options, 'highlight', ''))
    call assert_equal(['Pmenu'], get(g:vim_cmake_naive_test_last_menu_popup_options, 'borderhighlight', []))
    call assert_equal(v:t_func, type(get(g:vim_cmake_naive_test_last_menu_popup_options, 'filter', v:null)))
    call assert_true(filereadable(s:path_join(l:fixture.root, '.vim-cmake-naive-config.json')))
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
    let g:vim_cmake_naive_test_popup_menu_response = 1
    let g:vim_cmake_naive_test_menu_command_args = {}
    let g:vim_cmake_naive_test_capture_build_terminal = 1
    unlet! g:vim_cmake_naive_test_menu_response
    unlet! g:vim_cmake_naive_test_inputlist_response
    unlet! g:vim_cmake_naive_test_last_menu_popup_items
    unlet! g:vim_cmake_naive_test_last_menu_popup_options
    unlet! g:vim_cmake_naive_test_last_build_terminal
    execute 'silent CMakeMenu'

    call assert_equal(
          \ ['1.   CMakeBuild', '2.   CMakeRun', '3.   CMakeTest', '4.   CMakeSwitchTarget', '5.   CMakeSwitchPreset'],
          \ get(g:, 'vim_cmake_naive_test_last_menu_popup_items', []))
    call assert_equal('Select command', get(g:vim_cmake_naive_test_last_menu_popup_options, 'title', ''))
    call assert_equal(30, get(g:vim_cmake_naive_test_last_menu_popup_options, 'minwidth', 0))
    call assert_equal(30, get(g:vim_cmake_naive_test_last_menu_popup_options, 'maxwidth', 0))
    call assert_equal(5, get(g:vim_cmake_naive_test_last_menu_popup_options, 'minheight', 0))
    call assert_equal(5, get(g:vim_cmake_naive_test_last_menu_popup_options, 'maxheight', 0))
    call assert_equal(1, get(g:vim_cmake_naive_test_last_menu_popup_options, 'scrollbar', 0))
    call assert_equal([1, 1, 1, 1], get(g:vim_cmake_naive_test_last_menu_popup_options, 'border', []))
    call assert_equal(['─', '│', '─', '│', '╭', '╮', '╯', '╰'], get(g:vim_cmake_naive_test_last_menu_popup_options, 'borderchars', []))
    call assert_equal('Pmenu', get(g:vim_cmake_naive_test_last_menu_popup_options, 'highlight', ''))
    call assert_equal(['Pmenu'], get(g:vim_cmake_naive_test_last_menu_popup_options, 'borderhighlight', []))
    call assert_equal(v:t_func, type(get(g:vim_cmake_naive_test_last_menu_popup_options, 'filter', v:null)))
    let l:terminal = s:wait_for_captured_build_terminal_output('compact-menu-build-output', 1000)
    call assert_equal(1, get(l:terminal, 'is_terminal', 0))
    call assert_equal(1, get(l:terminal, 'is_horizontal_split', 0))
    call assert_equal(1, get(l:terminal, 'is_preview_window', 0))
    call assert_equal(0, get(l:terminal, 'is_vertical_split', 0))
    let l:expected_root = s:normalized_path(l:fixture.root)
    call assert_true(s:wait_for_file(l:args_path, 1000), 'Expected fake cmake args file to be created.')
    let l:args_lines = filereadable(l:args_path)
          \ ? s:read_non_empty_lines(l:args_path)
          \ : []
    call s:assert_cmake_build_parallel_args(
          \ l:args_lines,
          \ s:path_join(l:expected_root, 'build'))
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
    let l:config_path = s:path_join(l:fixture.root, '.vim-cmake-naive-config.json')
    call s:write_json(l:config_path, {'keep': 1})
    execute 'cd ' . fnameescape(l:fixture.root)
    let g:vim_cmake_naive_test_use_popup_menu = 1
    let g:vim_cmake_naive_test_popup_menu_response = 14
    let g:vim_cmake_naive_test_menu_command_args = {'CMakeConfigSetOutput': 'out/build'}
    unlet! g:vim_cmake_naive_test_menu_response
    unlet! g:vim_cmake_naive_test_inputlist_response
    call vim_cmake_naive#menu_full()

    call assert_equal({'keep': 1, 'output': 'out/build'}, s:read_json(l:config_path))
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
    let l:config_path = s:path_join(l:fixture.root, '.vim-cmake-naive-config.json')
    call s:write_json(l:config_path, {'output': 'old'})
    execute 'cd ' . fnameescape(l:fixture.root)
    let g:vim_cmake_naive_test_use_popup_menu = 1
    let g:vim_cmake_naive_test_popup_menu_response = 14
    let g:vim_cmake_naive_test_menu_command_args = {'CMakeConfigSetOutput': ''}
    unlet! g:vim_cmake_naive_test_menu_response
    unlet! g:vim_cmake_naive_test_inputlist_response
    call vim_cmake_naive#menu_full()

    call assert_equal({'output': 'old'}, s:read_json(l:config_path))
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
    let l:config_path = s:path_join(l:fixture.root, '.vim-cmake-naive-config.json')
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

function! s:test_cmake_menu_popup_filters_items_by_search_query() abort
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
    let g:vim_cmake_naive_test_popup_menu_response = {'query': 'CONFIGDEFAULT', 'result': 1}
    let g:vim_cmake_naive_test_menu_command_args = {}
    unlet! g:vim_cmake_naive_test_menu_response
    unlet! g:vim_cmake_naive_test_inputlist_response
    unlet! g:vim_cmake_naive_test_last_menu_popup_items
    unlet! g:vim_cmake_naive_test_last_menu_popup_options
    call vim_cmake_naive#menu_full()

    call assert_equal(['1.   CMakeConfigDefault'], get(g:, 'vim_cmake_naive_test_last_menu_popup_items', []))
    call assert_equal('Select command [CONFIGDEFAULT] (Insert)', get(g:vim_cmake_naive_test_last_menu_popup_options, 'title', ''))
    call assert_true(filereadable(s:path_join(l:fixture.root, '.vim-cmake-naive-config.json')))
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

function! s:test_cmake_menu_popup_retains_filter_when_search_mode_exits() abort
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
    let g:vim_cmake_naive_test_popup_menu_response = {'query': 'CONFIGDEFAULT', 'search_mode': 0, 'result': 0}
    let g:vim_cmake_naive_test_menu_command_args = {}
    unlet! g:vim_cmake_naive_test_menu_response
    unlet! g:vim_cmake_naive_test_inputlist_response
    unlet! g:vim_cmake_naive_test_last_menu_popup_items
    unlet! g:vim_cmake_naive_test_last_menu_popup_options
    call vim_cmake_naive#menu_full()

    call assert_equal(['1.   CMakeConfigDefault'], get(g:, 'vim_cmake_naive_test_last_menu_popup_items', []))
    call assert_equal('Select command [CONFIGDEFAULT] (Insert)', get(g:vim_cmake_naive_test_last_menu_popup_options, 'title', ''))
    call assert_false(filereadable(s:path_join(l:fixture.root, '.vim-cmake-naive-config.json')))
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

function! s:test_cmake_switch_preset_sets_selected_visible_preset() abort
  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()
  let l:initial_selection = get(g:, 'vim_cmake_naive_test_inputlist_response', v:null)
  let l:initial_menu_selection = get(g:, 'vim_cmake_naive_test_menu_response', v:null)

  try
    let l:config_path = s:path_join(l:fixture.root, '.vim-cmake-naive-config.json')
    call s:write_json(l:config_path, {'preset': 'old', 'build': 'RelWithDebInfo', 'keep': 1})

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
    let g:vim_cmake_naive_test_menu_response = 2
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
    if l:initial_menu_selection is v:null
      unlet! g:vim_cmake_naive_test_menu_response
    else
      let g:vim_cmake_naive_test_menu_response = l:initial_menu_selection
    endif
    execute 'cd ' . fnameescape(l:initial_cwd)
    call delete(l:fixture.root, 'rf')
  endtry
endfunction

function! s:test_cmake_switch_preset_selects_none_and_removes_preset_key() abort
  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()
  let l:initial_selection = get(g:, 'vim_cmake_naive_test_inputlist_response', v:null)
  let l:initial_menu_selection = get(g:, 'vim_cmake_naive_test_menu_response', v:null)

  try
    let l:config_path = s:path_join(l:fixture.root, '.vim-cmake-naive-config.json')
    call s:write_json(l:config_path, {'preset': 'old', 'build': 'RelWithDebInfo', 'keep': 1})

    call s:write_cmake_presets(
          \ s:path_join(l:fixture.root, 'CMakePresets.json'),
          \ [
          \   {'name': 'dev', 'condition': {'type': 'equals', 'lhs': '${hostSystemName}', 'rhs': 'Darwin'}},
          \   {'name': 'default'}
          \ ])

    execute 'cd ' . fnameescape(l:fixture.root)
    let g:vim_cmake_naive_test_menu_response = 1
    let g:vim_cmake_naive_test_inputlist_response = 1
    execute 'silent CMakeSwitchPreset'

    call assert_equal(
          \ {'build': 'RelWithDebInfo', 'keep': 1},
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
    let l:config_path = s:path_join(l:fixture.root, '.vim-cmake-naive-config.json')
    call s:write_json(l:config_path, {'preset': 'dev'})

    execute 'cd ' . fnameescape(l:fixture.root)
    call vim_cmake_naive#switch_preset()

    let l:messages = execute('messages')
    call assert_true(stridx(l:messages, 'CMakePresets.json not found at project root:') >= 0)
  finally
    execute 'cd ' . fnameescape(l:initial_cwd)
    call delete(l:fixture.root, 'rf')
  endtry
endfunction

function! s:test_cmake_switch_preset_reports_missing_local_config() abort
  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()
  let l:initial_menu_selection = get(g:, 'vim_cmake_naive_test_menu_response', v:null)
  let l:initial_inputlist_selection = get(g:, 'vim_cmake_naive_test_inputlist_response', v:null)

  try
    call s:write_cmake_presets(
          \ s:path_join(l:fixture.root, 'CMakePresets.json'),
          \ [{'name': 'dev'}])

    execute 'cd ' . fnameescape(l:fixture.root)
    let g:vim_cmake_naive_test_menu_response = 0
    let g:vim_cmake_naive_test_inputlist_response = 0
    call vim_cmake_naive#switch_preset()

    let l:messages = execute('messages')
    call assert_true(stridx(l:messages, '.vim-cmake-naive-config.json not found in current directory or any parent directory.') >= 0)
    call assert_false(filereadable(s:path_join(l:fixture.root, '.vim-cmake-naive-config.json')))
  finally
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

function! s:test_cmake_switch_preset_cancels_without_changing_config() abort
  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()
  let l:initial_selection = get(g:, 'vim_cmake_naive_test_inputlist_response', v:null)
  let l:initial_menu_selection = get(g:, 'vim_cmake_naive_test_menu_response', v:null)

  try
    let l:config_path = s:path_join(l:fixture.root, '.vim-cmake-naive-config.json')
    call s:write_json(l:config_path, {'preset': 'stay', 'build': 'Debug'})
    call s:write_cmake_presets(
          \ s:path_join(l:fixture.root, 'CMakePresets.json'),
          \ [{'name': 'dev'}, {'name': 'default'}])

    execute 'cd ' . fnameescape(l:fixture.root)
    let g:vim_cmake_naive_test_menu_response = 0
    let g:vim_cmake_naive_test_inputlist_response = 0
    execute 'silent CMakeSwitchPreset'

    call assert_equal({'preset': 'stay', 'build': 'Debug'}, s:read_json(l:config_path))
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

function! s:test_cmake_switch_preset_only_none_is_selectable_when_no_visible_presets() abort
  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()
  let l:initial_selection = get(g:, 'vim_cmake_naive_test_inputlist_response', v:null)
  let l:initial_menu_selection = get(g:, 'vim_cmake_naive_test_menu_response', v:null)

  try
    let l:config_path = s:path_join(l:fixture.root, '.vim-cmake-naive-config.json')
    call s:write_json(l:config_path, {'preset': 'old', 'build': 'RelWithDebInfo', 'keep': 1})
    call s:write_cmake_presets(
          \ s:path_join(l:fixture.root, 'CMakePresets.json'),
          \ [
          \   {'name': 'hidden_release', 'hidden': v:true},
          \   {'name': 'blocked', 'condition': {'type': 'equals', 'lhs': 'x', 'rhs': 'y'}}
          \ ])

    execute 'cd ' . fnameescape(l:fixture.root)
    let g:vim_cmake_naive_test_menu_response = 1
    let g:vim_cmake_naive_test_inputlist_response = 1
    call vim_cmake_naive#switch_preset()

    call assert_equal({'build': 'RelWithDebInfo', 'keep': 1}, s:read_json(l:config_path))
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

function! s:test_cmake_switch_preset_menu_fallback_displays_parenthesized_none() abort
  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()
  let l:initial_menu_selection = get(g:, 'vim_cmake_naive_test_menu_response', v:null)
  let l:initial_inputlist_selection = get(g:, 'vim_cmake_naive_test_inputlist_response', v:null)
  let l:initial_menu_items = get(g:, 'vim_cmake_naive_test_last_menu_items', v:null)

  try
    let l:config_path = s:path_join(l:fixture.root, '.vim-cmake-naive-config.json')
    call s:write_json(l:config_path, {'preset': 'dev'})
    call s:write_cmake_presets(
          \ s:path_join(l:fixture.root, 'CMakePresets.json'),
          \ [{'name': 'default'}, {'name': 'dev'}])

    execute 'cd ' . fnameescape(l:fixture.root)
    let g:vim_cmake_naive_test_menu_response = 0
    let g:vim_cmake_naive_test_inputlist_response = 0
    call vim_cmake_naive#switch_preset()

    call assert_equal(['(none)', 'default', 'dev'], get(g:, 'vim_cmake_naive_test_last_menu_items', []))
  finally
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
    if l:initial_menu_items is v:null
      unlet! g:vim_cmake_naive_test_last_menu_items
    else
      let g:vim_cmake_naive_test_last_menu_items = l:initial_menu_items
    endif
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
    let l:config_path = s:path_join(l:fixture.root, '.vim-cmake-naive-config.json')
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
          \ ['1.   (none)', '2.   default', '3. * dev', '4.   release'],
          \ get(g:, 'vim_cmake_naive_test_last_preset_popup_items', []))
    call assert_equal('Select preset', get(g:vim_cmake_naive_test_last_preset_popup_options, 'title', ''))
    call assert_equal(30, get(g:vim_cmake_naive_test_last_preset_popup_options, 'minwidth', 0))
    call assert_equal(30, get(g:vim_cmake_naive_test_last_preset_popup_options, 'maxwidth', 0))
    call assert_equal(4, get(g:vim_cmake_naive_test_last_preset_popup_options, 'minheight', 0))
    call assert_equal(4, get(g:vim_cmake_naive_test_last_preset_popup_options, 'maxheight', 0))
    call assert_equal(1, get(g:vim_cmake_naive_test_last_preset_popup_options, 'scrollbar', 0))
    call assert_equal([1, 1, 1, 1], get(g:vim_cmake_naive_test_last_preset_popup_options, 'border', []))
    call assert_equal(['─', '│', '─', '│', '╭', '╮', '╯', '╰'], get(g:vim_cmake_naive_test_last_preset_popup_options, 'borderchars', []))
    call assert_equal('Pmenu', get(g:vim_cmake_naive_test_last_preset_popup_options, 'highlight', ''))
    call assert_equal(['Pmenu'], get(g:vim_cmake_naive_test_last_preset_popup_options, 'borderhighlight', []))
    call assert_equal(v:t_func, type(get(g:vim_cmake_naive_test_last_preset_popup_options, 'filter', v:null)))
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

function! s:test_switch_preset_popup_display_items_marks_none_when_preset_missing() abort
  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()
  let l:initial_use_popup = get(g:, 'vim_cmake_naive_test_use_popup_menu', v:null)
  let l:initial_popup_response = get(g:, 'vim_cmake_naive_test_popup_menu_response', v:null)
  let l:initial_popup_items = get(g:, 'vim_cmake_naive_test_last_preset_popup_items', v:null)
  let l:initial_popup_options = get(g:, 'vim_cmake_naive_test_last_preset_popup_options', v:null)
  let l:initial_menu_selection = get(g:, 'vim_cmake_naive_test_menu_response', v:null)
  let l:initial_inputlist_selection = get(g:, 'vim_cmake_naive_test_inputlist_response', v:null)

  try
    let l:config_path = s:path_join(l:fixture.root, '.vim-cmake-naive-config.json')
    call s:write_json(l:config_path, {'keep': 1})
    call s:write_cmake_presets(
          \ s:path_join(l:fixture.root, 'CMakePresets.json'),
          \ [{'name': 'release'}, {'name': 'default'}, {'name': 'dev'}])

    execute 'cd ' . fnameescape(l:fixture.root)
    let g:vim_cmake_naive_test_use_popup_menu = 1
    let g:vim_cmake_naive_test_popup_menu_response = 0
    unlet! g:vim_cmake_naive_test_last_preset_popup_items
    unlet! g:vim_cmake_naive_test_last_preset_popup_options
    unlet! g:vim_cmake_naive_test_menu_response
    unlet! g:vim_cmake_naive_test_inputlist_response
    call vim_cmake_naive#switch_preset()

    call assert_equal(
          \ ['1. * (none)', '2.   default', '3.   dev', '4.   release'],
          \ get(g:, 'vim_cmake_naive_test_last_preset_popup_items', []))
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

function! s:test_switch_preset_popup_filters_items_by_search_query() abort
  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()
  let l:initial_use_popup = get(g:, 'vim_cmake_naive_test_use_popup_menu', v:null)
  let l:initial_popup_response = get(g:, 'vim_cmake_naive_test_popup_menu_response', v:null)
  let l:initial_popup_items = get(g:, 'vim_cmake_naive_test_last_preset_popup_items', v:null)
  let l:initial_popup_options = get(g:, 'vim_cmake_naive_test_last_preset_popup_options', v:null)
  let l:initial_menu_selection = get(g:, 'vim_cmake_naive_test_menu_response', v:null)
  let l:initial_inputlist_selection = get(g:, 'vim_cmake_naive_test_inputlist_response', v:null)

  try
    let l:config_path = s:path_join(l:fixture.root, '.vim-cmake-naive-config.json')
    call s:write_json(l:config_path, {'preset': 'old', 'build': 'Debug', 'keep': 1})
    call s:write_cmake_presets(
          \ s:path_join(l:fixture.root, 'CMakePresets.json'),
          \ [{'name': 'release'}, {'name': 'default'}, {'name': 'dev'}])

    execute 'cd ' . fnameescape(l:fixture.root)
    let g:vim_cmake_naive_test_use_popup_menu = 1
    let g:vim_cmake_naive_test_popup_menu_response = {'query': 'DEV', 'result': 1}
    unlet! g:vim_cmake_naive_test_last_preset_popup_items
    unlet! g:vim_cmake_naive_test_last_preset_popup_options
    unlet! g:vim_cmake_naive_test_menu_response
    unlet! g:vim_cmake_naive_test_inputlist_response
    call vim_cmake_naive#switch_preset()

    call assert_equal(['1.   dev'], get(g:, 'vim_cmake_naive_test_last_preset_popup_items', []))
    call assert_equal('Select preset [DEV] (Insert)', get(g:vim_cmake_naive_test_last_preset_popup_options, 'title', ''))
    call assert_equal({'preset': 'dev', 'keep': 1}, s:read_json(l:config_path))
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

function! s:test_switch_preset_popup_retains_filter_when_search_mode_exits() abort
  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()
  let l:initial_use_popup = get(g:, 'vim_cmake_naive_test_use_popup_menu', v:null)
  let l:initial_popup_response = get(g:, 'vim_cmake_naive_test_popup_menu_response', v:null)
  let l:initial_popup_items = get(g:, 'vim_cmake_naive_test_last_preset_popup_items', v:null)
  let l:initial_popup_options = get(g:, 'vim_cmake_naive_test_last_preset_popup_options', v:null)
  let l:initial_menu_selection = get(g:, 'vim_cmake_naive_test_menu_response', v:null)
  let l:initial_inputlist_selection = get(g:, 'vim_cmake_naive_test_inputlist_response', v:null)

  try
    let l:config_path = s:path_join(l:fixture.root, '.vim-cmake-naive-config.json')
    call s:write_json(l:config_path, {'preset': 'old', 'build': 'Debug', 'keep': 1})
    call s:write_cmake_presets(
          \ s:path_join(l:fixture.root, 'CMakePresets.json'),
          \ [{'name': 'release'}, {'name': 'default'}, {'name': 'dev'}])

    execute 'cd ' . fnameescape(l:fixture.root)
    let g:vim_cmake_naive_test_use_popup_menu = 1
    let g:vim_cmake_naive_test_popup_menu_response = {'query': 'DEV', 'search_mode': 0, 'result': 0}
    unlet! g:vim_cmake_naive_test_last_preset_popup_items
    unlet! g:vim_cmake_naive_test_last_preset_popup_options
    unlet! g:vim_cmake_naive_test_menu_response
    unlet! g:vim_cmake_naive_test_inputlist_response
    call vim_cmake_naive#switch_preset()

    call assert_equal(['1.   dev'], get(g:, 'vim_cmake_naive_test_last_preset_popup_items', []))
    call assert_equal('Select preset [DEV] (Insert)', get(g:vim_cmake_naive_test_last_preset_popup_options, 'title', ''))
    call assert_equal({'preset': 'old', 'build': 'Debug', 'keep': 1}, s:read_json(l:config_path))
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

function! s:test_cmake_switch_build_sets_selected_build_and_removes_preset() abort
  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()
  let l:initial_selection = get(g:, 'vim_cmake_naive_test_inputlist_response', v:null)
  let l:initial_menu_selection = get(g:, 'vim_cmake_naive_test_menu_response', v:null)

  try
    let l:config_path = s:path_join(l:fixture.root, '.vim-cmake-naive-config.json')
    call s:write_json(l:config_path, {'build': 'Debug', 'preset': 'dev', 'keep': 1})

    execute 'cd ' . fnameescape(l:fixture.root)
    let g:vim_cmake_naive_test_menu_response = 4
    let g:vim_cmake_naive_test_inputlist_response = 4
    execute 'silent CMakeSwitchBuild'

    call assert_equal(
          \ {'build': 'RelWithDebInfo', 'keep': 1},
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

function! s:test_cmake_switch_build_selects_none_and_removes_build() abort
  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()
  let l:initial_selection = get(g:, 'vim_cmake_naive_test_inputlist_response', v:null)
  let l:initial_menu_selection = get(g:, 'vim_cmake_naive_test_menu_response', v:null)

  try
    let l:config_path = s:path_join(l:fixture.root, '.vim-cmake-naive-config.json')
    call s:write_json(l:config_path, {'build': 'RelWithDebInfo', 'preset': 'dev', 'keep': 1})

    execute 'cd ' . fnameescape(l:fixture.root)
    let g:vim_cmake_naive_test_menu_response = 1
    let g:vim_cmake_naive_test_inputlist_response = 1
    execute 'silent CMakeSwitchBuild'

    call assert_equal(
          \ {'preset': 'dev', 'keep': 1},
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

function! s:test_cmake_switch_build_reports_missing_local_config() abort
  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()
  let l:initial_menu_selection = get(g:, 'vim_cmake_naive_test_menu_response', v:null)
  let l:initial_inputlist_selection = get(g:, 'vim_cmake_naive_test_inputlist_response', v:null)

  try
    execute 'cd ' . fnameescape(l:fixture.root)
    let g:vim_cmake_naive_test_menu_response = 0
    let g:vim_cmake_naive_test_inputlist_response = 0
    call vim_cmake_naive#switch_build()

    let l:messages = execute('messages')
    call assert_true(stridx(l:messages, '.vim-cmake-naive-config.json not found in current directory or any parent directory.') >= 0)
    call assert_false(filereadable(s:path_join(l:fixture.root, '.vim-cmake-naive-config.json')))
  finally
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

function! s:test_cmake_switch_build_menu_fallback_displays_parenthesized_none() abort
  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()
  let l:initial_menu_selection = get(g:, 'vim_cmake_naive_test_menu_response', v:null)
  let l:initial_inputlist_selection = get(g:, 'vim_cmake_naive_test_inputlist_response', v:null)
  let l:initial_menu_items = get(g:, 'vim_cmake_naive_test_last_menu_items', v:null)

  try
    let l:config_path = s:path_join(l:fixture.root, '.vim-cmake-naive-config.json')
    call s:write_json(l:config_path, {'build': 'Debug'})

    execute 'cd ' . fnameescape(l:fixture.root)
    let g:vim_cmake_naive_test_menu_response = 0
    let g:vim_cmake_naive_test_inputlist_response = 0
    call vim_cmake_naive#switch_build()

    call assert_equal(['(none)', 'Debug', 'Release', 'RelWithDebInfo', 'MinSizeRel'], get(g:, 'vim_cmake_naive_test_last_menu_items', []))
  finally
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
    if l:initial_menu_items is v:null
      unlet! g:vim_cmake_naive_test_last_menu_items
    else
      let g:vim_cmake_naive_test_last_menu_items = l:initial_menu_items
    endif
    execute 'cd ' . fnameescape(l:initial_cwd)
    call delete(l:fixture.root, 'rf')
  endtry
endfunction

function! s:test_cmake_switch_build_popup_display_items_marks_current_selection() abort
  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()
  let l:initial_use_popup = get(g:, 'vim_cmake_naive_test_use_popup_menu', v:null)
  let l:initial_popup_response = get(g:, 'vim_cmake_naive_test_popup_menu_response', v:null)
  let l:initial_popup_items = get(g:, 'vim_cmake_naive_test_last_build_popup_items', v:null)
  let l:initial_popup_options = get(g:, 'vim_cmake_naive_test_last_build_popup_options', v:null)
  let l:initial_menu_selection = get(g:, 'vim_cmake_naive_test_menu_response', v:null)
  let l:initial_inputlist_selection = get(g:, 'vim_cmake_naive_test_inputlist_response', v:null)

  try
    let l:config_path = s:path_join(l:fixture.root, '.vim-cmake-naive-config.json')
    call s:write_json(l:config_path, {'build': 'RelWithDebInfo', 'preset': 'dev', 'keep': 1})

    execute 'cd ' . fnameescape(l:fixture.root)
    let g:vim_cmake_naive_test_use_popup_menu = 1
    let g:vim_cmake_naive_test_popup_menu_response = 0
    unlet! g:vim_cmake_naive_test_menu_response
    unlet! g:vim_cmake_naive_test_inputlist_response
    unlet! g:vim_cmake_naive_test_last_build_popup_items
    unlet! g:vim_cmake_naive_test_last_build_popup_options
    call vim_cmake_naive#switch_build()

    call assert_equal(
          \ ['1.   (none)', '2.   Debug', '3.   Release', '4. * RelWithDebInfo', '5.   MinSizeRel'],
          \ get(g:, 'vim_cmake_naive_test_last_build_popup_items', []))
    call assert_equal('Select build', get(g:vim_cmake_naive_test_last_build_popup_options, 'title', ''))
    call assert_equal(30, get(g:vim_cmake_naive_test_last_build_popup_options, 'minwidth', 0))
    call assert_equal(30, get(g:vim_cmake_naive_test_last_build_popup_options, 'maxwidth', 0))
    call assert_equal(5, get(g:vim_cmake_naive_test_last_build_popup_options, 'minheight', 0))
    call assert_equal(5, get(g:vim_cmake_naive_test_last_build_popup_options, 'maxheight', 0))
    call assert_equal(1, get(g:vim_cmake_naive_test_last_build_popup_options, 'scrollbar', 0))
    call assert_equal([1, 1, 1, 1], get(g:vim_cmake_naive_test_last_build_popup_options, 'border', []))
    call assert_equal(['─', '│', '─', '│', '╭', '╮', '╯', '╰'], get(g:vim_cmake_naive_test_last_build_popup_options, 'borderchars', []))
    call assert_equal('Pmenu', get(g:vim_cmake_naive_test_last_build_popup_options, 'highlight', ''))
    call assert_equal(['Pmenu'], get(g:vim_cmake_naive_test_last_build_popup_options, 'borderhighlight', []))
    call assert_equal(v:t_func, type(get(g:vim_cmake_naive_test_last_build_popup_options, 'filter', v:null)))
    call assert_equal({'build': 'RelWithDebInfo', 'preset': 'dev', 'keep': 1}, s:read_json(l:config_path))
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
      unlet! g:vim_cmake_naive_test_last_build_popup_items
    else
      let g:vim_cmake_naive_test_last_build_popup_items = l:initial_popup_items
    endif
    if l:initial_popup_options is v:null
      unlet! g:vim_cmake_naive_test_last_build_popup_options
    else
      let g:vim_cmake_naive_test_last_build_popup_options = l:initial_popup_options
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

function! s:test_cmake_switch_build_popup_display_items_marks_none_when_build_missing() abort
  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()
  let l:initial_use_popup = get(g:, 'vim_cmake_naive_test_use_popup_menu', v:null)
  let l:initial_popup_response = get(g:, 'vim_cmake_naive_test_popup_menu_response', v:null)
  let l:initial_popup_items = get(g:, 'vim_cmake_naive_test_last_build_popup_items', v:null)
  let l:initial_popup_options = get(g:, 'vim_cmake_naive_test_last_build_popup_options', v:null)
  let l:initial_menu_selection = get(g:, 'vim_cmake_naive_test_menu_response', v:null)
  let l:initial_inputlist_selection = get(g:, 'vim_cmake_naive_test_inputlist_response', v:null)

  try
    let l:config_path = s:path_join(l:fixture.root, '.vim-cmake-naive-config.json')
    call s:write_json(l:config_path, {'preset': 'dev', 'keep': 1})

    execute 'cd ' . fnameescape(l:fixture.root)
    let g:vim_cmake_naive_test_use_popup_menu = 1
    let g:vim_cmake_naive_test_popup_menu_response = 0
    unlet! g:vim_cmake_naive_test_menu_response
    unlet! g:vim_cmake_naive_test_inputlist_response
    unlet! g:vim_cmake_naive_test_last_build_popup_items
    unlet! g:vim_cmake_naive_test_last_build_popup_options
    call vim_cmake_naive#switch_build()

    call assert_equal(
          \ ['1. * (none)', '2.   Debug', '3.   Release', '4.   RelWithDebInfo', '5.   MinSizeRel'],
          \ get(g:, 'vim_cmake_naive_test_last_build_popup_items', []))
    call assert_equal({'preset': 'dev', 'keep': 1}, s:read_json(l:config_path))
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
      unlet! g:vim_cmake_naive_test_last_build_popup_items
    else
      let g:vim_cmake_naive_test_last_build_popup_items = l:initial_popup_items
    endif
    if l:initial_popup_options is v:null
      unlet! g:vim_cmake_naive_test_last_build_popup_options
    else
      let g:vim_cmake_naive_test_last_build_popup_options = l:initial_popup_options
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

function! s:test_switch_build_popup_filters_items_by_search_query() abort
  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()
  let l:initial_use_popup = get(g:, 'vim_cmake_naive_test_use_popup_menu', v:null)
  let l:initial_popup_response = get(g:, 'vim_cmake_naive_test_popup_menu_response', v:null)
  let l:initial_popup_items = get(g:, 'vim_cmake_naive_test_last_build_popup_items', v:null)
  let l:initial_popup_options = get(g:, 'vim_cmake_naive_test_last_build_popup_options', v:null)
  let l:initial_menu_selection = get(g:, 'vim_cmake_naive_test_menu_response', v:null)
  let l:initial_inputlist_selection = get(g:, 'vim_cmake_naive_test_inputlist_response', v:null)

  try
    let l:config_path = s:path_join(l:fixture.root, '.vim-cmake-naive-config.json')
    call s:write_json(l:config_path, {'build': 'RelWithDebInfo', 'preset': 'dev', 'keep': 1})

    execute 'cd ' . fnameescape(l:fixture.root)
    let g:vim_cmake_naive_test_use_popup_menu = 1
    let g:vim_cmake_naive_test_popup_menu_response = {'query': 'MIN', 'result': 1}
    unlet! g:vim_cmake_naive_test_last_build_popup_items
    unlet! g:vim_cmake_naive_test_last_build_popup_options
    unlet! g:vim_cmake_naive_test_menu_response
    unlet! g:vim_cmake_naive_test_inputlist_response
    call vim_cmake_naive#switch_build()

    call assert_equal(['1.   MinSizeRel'], get(g:, 'vim_cmake_naive_test_last_build_popup_items', []))
    call assert_equal('Select build [MIN] (Insert)', get(g:vim_cmake_naive_test_last_build_popup_options, 'title', ''))
    call assert_equal({'build': 'MinSizeRel', 'keep': 1}, s:read_json(l:config_path))
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
      unlet! g:vim_cmake_naive_test_last_build_popup_items
    else
      let g:vim_cmake_naive_test_last_build_popup_items = l:initial_popup_items
    endif
    if l:initial_popup_options is v:null
      unlet! g:vim_cmake_naive_test_last_build_popup_options
    else
      let g:vim_cmake_naive_test_last_build_popup_options = l:initial_popup_options
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

function! s:test_switch_build_popup_retains_filter_when_search_mode_exits() abort
  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()
  let l:initial_use_popup = get(g:, 'vim_cmake_naive_test_use_popup_menu', v:null)
  let l:initial_popup_response = get(g:, 'vim_cmake_naive_test_popup_menu_response', v:null)
  let l:initial_popup_items = get(g:, 'vim_cmake_naive_test_last_build_popup_items', v:null)
  let l:initial_popup_options = get(g:, 'vim_cmake_naive_test_last_build_popup_options', v:null)
  let l:initial_menu_selection = get(g:, 'vim_cmake_naive_test_menu_response', v:null)
  let l:initial_inputlist_selection = get(g:, 'vim_cmake_naive_test_inputlist_response', v:null)

  try
    let l:config_path = s:path_join(l:fixture.root, '.vim-cmake-naive-config.json')
    call s:write_json(l:config_path, {'build': 'RelWithDebInfo', 'preset': 'dev', 'keep': 1})

    execute 'cd ' . fnameescape(l:fixture.root)
    let g:vim_cmake_naive_test_use_popup_menu = 1
    let g:vim_cmake_naive_test_popup_menu_response = {'query': 'MIN', 'search_mode': 0, 'result': 0}
    unlet! g:vim_cmake_naive_test_last_build_popup_items
    unlet! g:vim_cmake_naive_test_last_build_popup_options
    unlet! g:vim_cmake_naive_test_menu_response
    unlet! g:vim_cmake_naive_test_inputlist_response
    call vim_cmake_naive#switch_build()

    call assert_equal(['1.   MinSizeRel'], get(g:, 'vim_cmake_naive_test_last_build_popup_items', []))
    call assert_equal('Select build [MIN] (Insert)', get(g:vim_cmake_naive_test_last_build_popup_options, 'title', ''))
    call assert_equal({'build': 'RelWithDebInfo', 'preset': 'dev', 'keep': 1}, s:read_json(l:config_path))
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
      unlet! g:vim_cmake_naive_test_last_build_popup_items
    else
      let g:vim_cmake_naive_test_last_build_popup_items = l:initial_popup_items
    endif
    if l:initial_popup_options is v:null
      unlet! g:vim_cmake_naive_test_last_build_popup_options
    else
      let g:vim_cmake_naive_test_last_build_popup_options = l:initial_popup_options
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
    let l:config_path = s:path_join(l:fixture.root, '.vim-cmake-naive-config.json')
    call s:write_json(l:config_path, {'output': 'build', 'preset': 'dev', 'target': 'old', 'keep': 1})
    call s:write_json(s:path_join(l:fixture.root, '.vim-cmake-naive-cache.json'), {'targets': ['app', 'mylib']})

    let l:target_app = s:path_join(l:fixture.root, 'build/dev/CMakeFiles/app.dir')
    let l:target_lib = s:path_join(l:fixture.root, 'build/dev/lib/CMakeFiles/mylib.dir')
    let l:root_commands = s:path_join(l:fixture.root, 'build/dev/compile_commands.json')
    let l:target_app_commands = s:path_join(l:target_app, 'compile_commands.json')
    let l:target_lib_commands = s:path_join(l:target_lib, 'compile_commands.json')
    call mkdir(l:target_app, 'p')
    call mkdir(l:target_lib, 'p')
    call s:write_json(l:root_commands, s:fixture_entries())
    call s:write_json(l:target_app_commands, [{'file': '../src/main.cpp'}])
    call s:write_json(l:target_lib_commands, [{'file': '../lib/foo.cpp'}])

    execute 'cd ' . fnameescape(l:fixture.root)
    let g:vim_cmake_naive_test_inputlist_response = 3
    execute 'silent CMakeSwitchTarget'

    let l:active_commands = s:path_join(l:fixture.root, 'build/compile_commands.json')
    let l:target_state_path = s:path_join(l:fixture.root, '.vim-cmake-naive-target')
    call assert_equal(
          \ {'output': 'build', 'preset': 'dev', 'target': 'mylib', 'keep': 1},
          \ s:read_json(l:config_path))
    call assert_true(filereadable(l:active_commands))
    call assert_equal(readfile(l:target_lib_commands, 'b'), readfile(l:active_commands, 'b'))
    call assert_true(filereadable(l:target_state_path), 'Expected .vim-cmake-naive-target to be created.')
    call assert_equal(['mylib'], readfile(l:target_state_path, 'b'))
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

function! s:test_cmake_switch_target_selects_all_and_removes_target_key() abort
  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()
  let l:initial_selection = get(g:, 'vim_cmake_naive_test_inputlist_response', v:null)
  let l:initial_use_popup = get(g:, 'vim_cmake_naive_test_use_popup_menu', v:null)
  let l:initial_popup_response = get(g:, 'vim_cmake_naive_test_popup_menu_response', v:null)

  try
    let l:config_path = s:path_join(l:fixture.root, '.vim-cmake-naive-config.json')
    call s:write_json(l:config_path, {'output': 'build', 'preset': 'dev', 'target': 'old', 'keep': 1})
    call s:write_json(s:path_join(l:fixture.root, '.vim-cmake-naive-cache.json'), {'targets': ['app', 'mylib']})

    let l:root_commands = s:path_join(l:fixture.root, 'build/dev/compile_commands.json')
    call s:write_json(l:root_commands, s:fixture_entries())

    execute 'cd ' . fnameescape(l:fixture.root)
    let g:vim_cmake_naive_test_inputlist_response = 1
    execute 'silent CMakeSwitchTarget'

    let l:active_commands = s:path_join(l:fixture.root, 'build/compile_commands.json')
    let l:target_state_path = s:path_join(l:fixture.root, '.vim-cmake-naive-target')
    call assert_equal(
          \ {'output': 'build', 'preset': 'dev', 'keep': 1},
          \ s:read_json(l:config_path))
    call assert_true(filereadable(l:active_commands))
    call assert_equal(readfile(l:root_commands, 'b'), readfile(l:active_commands, 'b'))
    call assert_true(filereadable(l:target_state_path), 'Expected .vim-cmake-naive-target to be created.')
    call assert_equal([''], readfile(l:target_state_path, 'b'))
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
    let l:config_path = s:path_join(l:fixture.root, '.vim-cmake-naive-config.json')
    call s:write_json(l:config_path, {'output': 'build', 'preset': 'dev', 'target': 'old', 'keep': 1})
    call s:write_json(s:path_join(l:fixture.root, '.vim-cmake-naive-cache.json'), {'targets': ['app', 'mylib']})

    let l:target_app = s:path_join(l:fixture.root, 'build/dev/CMakeFiles/app.dir')
    let l:target_lib = s:path_join(l:fixture.root, 'build/dev/lib/CMakeFiles/mylib.dir')
    let l:root_commands = s:path_join(l:fixture.root, 'build/dev/compile_commands.json')
    let l:target_app_commands = s:path_join(l:target_app, 'compile_commands.json')
    let l:target_lib_commands = s:path_join(l:target_lib, 'compile_commands.json')
    call mkdir(l:target_app, 'p')
    call mkdir(l:target_lib, 'p')
    call s:write_json(l:root_commands, s:fixture_entries())
    call s:write_json(l:target_app_commands, [{'file': '../src/main.cpp'}])
    call s:write_json(l:target_lib_commands, [{'file': '../lib/foo.cpp'}])

    execute 'cd ' . fnameescape(l:fixture.root)
    let g:vim_cmake_naive_test_use_popup_menu = 1
    let g:vim_cmake_naive_test_popup_menu_response = 3
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

function! s:test_cmake_switch_target_reports_missing_cache_file() abort
  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()
  let l:initial_errmsg = v:errmsg

  try
    let l:config_path = s:path_join(l:fixture.root, '.vim-cmake-naive-config.json')
    call s:write_json(l:config_path, {'output': 'build', 'preset': 'dev'})

    execute 'cd ' . fnameescape(l:fixture.root)
    let v:errmsg = ''
    call vim_cmake_naive#switch_target()

    let l:messages = execute('messages')
    call assert_true(stridx(l:messages, 'No cache found. Please run CMakeGenerate command first.') >= 0)
    call assert_true(stridx(v:errmsg, '[vim-cmake-naive] No cache found. Please run CMakeGenerate command first.') >= 0)
    call assert_false(has_key(s:read_json(l:config_path), 'target'))
  finally
    let v:errmsg = l:initial_errmsg
    execute 'cd ' . fnameescape(l:initial_cwd)
    call delete(l:fixture.root, 'rf')
  endtry
endfunction

function! s:test_cmake_switch_target_reports_cache_without_targets_key() abort
  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()

  try
    let l:config_path = s:path_join(l:fixture.root, '.vim-cmake-naive-config.json')
    let l:cache_path = s:path_join(l:fixture.root, '.vim-cmake-naive-cache.json')
    call s:write_json(l:config_path, {'output': 'build', 'preset': 'dev'})
    call s:write_json(l:cache_path, {'keep': 1})

    execute 'cd ' . fnameescape(l:fixture.root)
    call vim_cmake_naive#switch_target()

    let l:messages = execute('messages')
    call assert_true(stridx(l:messages, 'key "targets" must be a JSON array.') >= 0)
    call assert_true(stridx(l:messages, l:cache_path) >= 0)
    call assert_false(has_key(s:read_json(l:config_path), 'target'))
  finally
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
    let l:config_path = s:path_join(l:fixture.root, '.vim-cmake-naive-config.json')
    call s:write_json(l:config_path, {'output': 'build', 'preset': 'dev', 'target': 'stay'})
    call s:write_json(s:path_join(l:fixture.root, '.vim-cmake-naive-cache.json'), {'targets': ['app']})

    let l:target_dir = s:path_join(l:fixture.root, 'build/dev/CMakeFiles/app.dir')
    let l:root_commands = s:path_join(l:fixture.root, 'build/dev/compile_commands.json')
    let l:active_commands = s:path_join(l:fixture.root, 'build/compile_commands.json')
    call mkdir(l:target_dir, 'p')
    call s:write_json(l:root_commands, [
          \ {
          \   'directory': '.',
          \   'output': 'CMakeFiles/app.dir/main.cpp.o',
          \   'file': '../src/main.cpp'
          \ }
          \ ])
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

function! s:test_cmake_switch_target_inputlist_fallback_displays_parenthesized_all() abort
  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()
  let l:initial_selection = get(g:, 'vim_cmake_naive_test_inputlist_response', v:null)
  let l:initial_inputlist_lines = get(g:, 'vim_cmake_naive_test_last_inputlist_lines', v:null)
  let l:initial_use_popup = get(g:, 'vim_cmake_naive_test_use_popup_menu', v:null)

  try
    let l:config_path = s:path_join(l:fixture.root, '.vim-cmake-naive-config.json')
    call s:write_json(l:config_path, {'output': 'build'})
    call s:write_json(s:path_join(l:fixture.root, '.vim-cmake-naive-cache.json'), {'targets': ['app']})
    call mkdir(s:path_join(l:fixture.root, 'build'), 'p')

    execute 'cd ' . fnameescape(l:fixture.root)
    let g:vim_cmake_naive_test_use_popup_menu = 0
    let g:vim_cmake_naive_test_inputlist_response = 0
    call vim_cmake_naive#switch_target()

    call assert_equal(
          \ ['Select target', '1. (all)', '2. app'],
          \ get(g:, 'vim_cmake_naive_test_last_inputlist_lines', []))
  finally
    if l:initial_selection is v:null
      unlet! g:vim_cmake_naive_test_inputlist_response
    else
      let g:vim_cmake_naive_test_inputlist_response = l:initial_selection
    endif
    if l:initial_inputlist_lines is v:null
      unlet! g:vim_cmake_naive_test_last_inputlist_lines
    else
      let g:vim_cmake_naive_test_last_inputlist_lines = l:initial_inputlist_lines
    endif
    if l:initial_use_popup is v:null
      unlet! g:vim_cmake_naive_test_use_popup_menu
    else
      let g:vim_cmake_naive_test_use_popup_menu = l:initial_use_popup
    endif
    execute 'cd ' . fnameescape(l:initial_cwd)
    call delete(l:fixture.root, 'rf')
  endtry
endfunction

function! s:test_cmake_switch_target_reports_missing_build_directory() abort
  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()

  try
    let l:config_path = s:path_join(l:fixture.root, '.vim-cmake-naive-config.json')
    call s:write_json(l:config_path, {'output': 'missing-build', 'preset': 'dev'})
    call s:write_json(s:path_join(l:fixture.root, '.vim-cmake-naive-cache.json'), {'targets': ['app']})

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

function! s:test_cmake_switch_target_selects_all_when_cache_targets_are_empty() abort
  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()
  let l:initial_selection = get(g:, 'vim_cmake_naive_test_inputlist_response', v:null)
  let l:initial_use_popup = get(g:, 'vim_cmake_naive_test_use_popup_menu', v:null)
  let l:initial_popup_response = get(g:, 'vim_cmake_naive_test_popup_menu_response', v:null)

  try
    let l:config_path = s:path_join(l:fixture.root, '.vim-cmake-naive-config.json')
    call s:write_json(l:config_path, {'output': 'build', 'preset': 'dev', 'target': 'old', 'keep': 1})
    call s:write_json(s:path_join(l:fixture.root, '.vim-cmake-naive-cache.json'), {'targets': []})
    let l:root_commands = s:path_join(l:fixture.root, 'build/dev/compile_commands.json')
    let l:active_commands = s:path_join(l:fixture.root, 'build/compile_commands.json')
    call mkdir(s:path_join(l:fixture.root, 'build/dev'), 'p')
    call s:write_json(l:root_commands, [{'directory': '.', 'command': 'clang++ -c ../src/main.cpp', 'file': '../src/main.cpp'}])
    call s:write_json(l:active_commands, [{'file': '../active-before-all.cpp'}])

    execute 'cd ' . fnameescape(l:fixture.root)
    let g:vim_cmake_naive_test_inputlist_response = 1
    call vim_cmake_naive#switch_target()

    call assert_equal({'output': 'build', 'preset': 'dev', 'keep': 1}, s:read_json(l:config_path))
    call assert_true(filereadable(l:active_commands))
    call assert_equal(readfile(l:root_commands, 'b'), readfile(l:active_commands, 'b'))
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

function! s:test_cmake_switch_target_reports_missing_target_compile_commands() abort
  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()
  let l:initial_selection = get(g:, 'vim_cmake_naive_test_inputlist_response', v:null)
  let l:initial_use_popup = get(g:, 'vim_cmake_naive_test_use_popup_menu', v:null)
  let l:initial_popup_response = get(g:, 'vim_cmake_naive_test_popup_menu_response', v:null)

  try
    let l:config_path = s:path_join(l:fixture.root, '.vim-cmake-naive-config.json')
    call s:write_json(l:config_path, {'output': 'build', 'preset': 'dev'})
    call s:write_json(s:path_join(l:fixture.root, '.vim-cmake-naive-cache.json'), {'targets': ['app']})

    let l:scan_root = s:path_join(l:fixture.root, 'build/dev')
    let l:target_dir = s:path_join(l:scan_root, 'CMakeFiles/app.dir')
    call mkdir(l:target_dir, 'p')

    execute 'cd ' . fnameescape(l:fixture.root)
    let g:vim_cmake_naive_test_inputlist_response = 2
    call vim_cmake_naive#switch_target()

    let l:messages = execute('messages')
    call assert_true(stridx(l:messages, 'Source file not found:') >= 0)
    call assert_false(has_key(s:read_json(l:config_path), 'target'))
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

function! s:test_cmake_switch_target_reports_missing_root_compile_commands_for_all_selection() abort
  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()
  let l:initial_selection = get(g:, 'vim_cmake_naive_test_inputlist_response', v:null)

  try
    let l:config_path = s:path_join(l:fixture.root, '.vim-cmake-naive-config.json')
    call s:write_json(l:config_path, {'output': 'build'})
    call s:write_json(s:path_join(l:fixture.root, '.vim-cmake-naive-cache.json'), {'targets': ['app']})

    call mkdir(s:path_join(l:fixture.root, 'build/CMakeFiles/app.dir'), 'p')

    execute 'cd ' . fnameescape(l:fixture.root)
    let g:vim_cmake_naive_test_inputlist_response = 1
    call vim_cmake_naive#switch_target()

    let l:expected_root = s:path_join(l:fixture.root, 'build/compile_commands.json')
    let l:messages = execute('messages')
    call assert_true(stridx(l:messages, 'Root compile_commands.json not found at:') >= 0)
    call assert_true(stridx(l:messages, l:expected_root) >= 0)
    call assert_false(has_key(s:read_json(l:config_path), 'target'))
    call assert_false(filereadable(s:path_join(l:fixture.root, 'build/compile_commands.json')))
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

function! s:test_cmake_switch_target_does_not_fallback_to_output_root_when_preset_is_set() abort
  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()
  let l:initial_selection = get(g:, 'vim_cmake_naive_test_inputlist_response', v:null)

  try
    let l:config_path = s:path_join(l:fixture.root, '.vim-cmake-naive-config.json')
    call s:write_json(l:config_path, {'output': 'build', 'preset': 'dev'})
    call s:write_json(s:path_join(l:fixture.root, '.vim-cmake-naive-cache.json'), {'targets': ['app']})

    let l:target_dir = s:path_join(l:fixture.root, 'build/dev/CMakeFiles/app.dir')
    let l:output_root_commands = s:path_join(l:fixture.root, 'build/compile_commands.json')
    call mkdir(l:target_dir, 'p')
    call s:write_json(l:output_root_commands, s:fixture_entries())

    execute 'cd ' . fnameescape(l:fixture.root)
    let g:vim_cmake_naive_test_inputlist_response = 1
    call vim_cmake_naive#switch_target()

    let l:preset_root_commands = s:path_join(l:fixture.root, 'build/dev/compile_commands.json')
    let l:messages = execute('messages')
    call assert_true(stridx(l:messages, 'Root compile_commands.json not found at:') >= 0)
    call assert_true(stridx(l:messages, l:preset_root_commands) >= 0)
    let l:split_target_commands = s:path_join(l:fixture.root, 'build/CMakeFiles/app.dir/compile_commands.json')
    call assert_false(filereadable(l:split_target_commands))
    call assert_false(has_key(s:read_json(l:config_path), 'target'))
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
    let l:config_path = s:path_join(l:fixture.root, '.vim-cmake-naive-config.json')
    call s:write_json(l:config_path, {'output': 'build', 'preset': 'dev', 'target': 't11'})
    call s:write_json(s:path_join(l:fixture.root, '.vim-cmake-naive-cache.json'), {'targets': ['t01', 't02', 't03', 't04', 't05', 't06', 't07', 't08', 't09', 't10', 't11']})

    let l:targets = ['t01', 't02', 't03', 't04', 't05', 't06', 't07', 't08', 't09', 't10', 't11']
    let l:root_entries = []
    let l:index = 0
    while l:index < len(l:targets)
      call mkdir(s:path_join(l:fixture.root, 'build/dev/CMakeFiles/' . l:targets[l:index] . '.dir'), 'p')
      call add(l:root_entries, {
            \ 'directory': '.',
            \ 'output': 'CMakeFiles/' . l:targets[l:index] . '.dir/' . l:targets[l:index] . '.cpp.o',
            \ 'file': '../' . l:targets[l:index] . '.cpp'
            \ })
      let l:index += 1
    endwhile
    call s:write_json(s:path_join(l:fixture.root, 'build/dev/compile_commands.json'), l:root_entries)

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
          \ [' 1.   (all)', ' 2.   t01', ' 3.   t02', ' 4.   t03', ' 5.   t04', ' 6.   t05', ' 7.   t06', ' 8.   t07', ' 9.   t08', '10.   t09', '11.   t10', '12. * t11'],
          \ get(g:, 'vim_cmake_naive_test_last_target_popup_items', []))
    call assert_equal('Select target', get(g:vim_cmake_naive_test_last_target_popup_options, 'title', ''))
    call assert_equal(30, get(g:vim_cmake_naive_test_last_target_popup_options, 'minwidth', 0))
    call assert_equal(30, get(g:vim_cmake_naive_test_last_target_popup_options, 'maxwidth', 0))
    call assert_equal(10, get(g:vim_cmake_naive_test_last_target_popup_options, 'minheight', 0))
    call assert_equal(10, get(g:vim_cmake_naive_test_last_target_popup_options, 'maxheight', 0))
    call assert_equal(1, get(g:vim_cmake_naive_test_last_target_popup_options, 'scrollbar', 0))
    call assert_equal([1, 1, 1, 1], get(g:vim_cmake_naive_test_last_target_popup_options, 'border', []))
    call assert_equal(['─', '│', '─', '│', '╭', '╮', '╯', '╰'], get(g:vim_cmake_naive_test_last_target_popup_options, 'borderchars', []))
    call assert_equal('Pmenu', get(g:vim_cmake_naive_test_last_target_popup_options, 'highlight', ''))
    call assert_equal(['Pmenu'], get(g:vim_cmake_naive_test_last_target_popup_options, 'borderhighlight', []))
    call assert_equal(v:t_func, type(get(g:vim_cmake_naive_test_last_target_popup_options, 'filter', v:null)))
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
    let l:config_path = s:path_join(l:fixture.root, '.vim-cmake-naive-config.json')
    call s:write_json(l:config_path, {'output': 'build', 'preset': 'dev', 'target': 'old'})
    call s:write_json(s:path_join(l:fixture.root, '.vim-cmake-naive-cache.json'), {'targets': ['app', 'mylib']})

    let l:target_app = s:path_join(l:fixture.root, 'build/dev/CMakeFiles/app.dir')
    let l:target_lib = s:path_join(l:fixture.root, 'build/dev/lib/CMakeFiles/mylib.dir')
    let l:root_commands = s:path_join(l:fixture.root, 'build/dev/compile_commands.json')
    let l:target_app_commands = s:path_join(l:target_app, 'compile_commands.json')
    let l:target_lib_commands = s:path_join(l:target_lib, 'compile_commands.json')
    call mkdir(l:target_app, 'p')
    call mkdir(l:target_lib, 'p')
    call s:write_json(l:root_commands, s:fixture_entries())
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
    call assert_equal('Select target [LIB] (Insert)', get(g:vim_cmake_naive_test_last_target_popup_options, 'title', ''))
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

function! s:test_switch_target_popup_retains_filter_when_search_mode_exits() abort
  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()
  let l:initial_use_popup = get(g:, 'vim_cmake_naive_test_use_popup_menu', v:null)
  let l:initial_popup_response = get(g:, 'vim_cmake_naive_test_popup_menu_response', v:null)
  let l:initial_popup_items = get(g:, 'vim_cmake_naive_test_last_target_popup_items', v:null)
  let l:initial_popup_options = get(g:, 'vim_cmake_naive_test_last_target_popup_options', v:null)
  let l:initial_menu_selection = get(g:, 'vim_cmake_naive_test_menu_response', v:null)
  let l:initial_inputlist_selection = get(g:, 'vim_cmake_naive_test_inputlist_response', v:null)

  try
    let l:config_path = s:path_join(l:fixture.root, '.vim-cmake-naive-config.json')
    call s:write_json(l:config_path, {'output': 'build', 'preset': 'dev', 'target': 'old'})
    call s:write_json(s:path_join(l:fixture.root, '.vim-cmake-naive-cache.json'), {'targets': ['app', 'mylib']})

    let l:target_app = s:path_join(l:fixture.root, 'build/dev/CMakeFiles/app.dir')
    let l:target_lib = s:path_join(l:fixture.root, 'build/dev/lib/CMakeFiles/mylib.dir')
    let l:root_commands = s:path_join(l:fixture.root, 'build/dev/compile_commands.json')
    let l:target_app_commands = s:path_join(l:target_app, 'compile_commands.json')
    let l:target_lib_commands = s:path_join(l:target_lib, 'compile_commands.json')
    call mkdir(l:target_app, 'p')
    call mkdir(l:target_lib, 'p')
    call s:write_json(l:root_commands, s:fixture_entries())
    call s:write_json(l:target_app_commands, [{'file': '../src/main.cpp'}])
    call s:write_json(l:target_lib_commands, [{'file': '../lib/foo.cpp'}])

    execute 'cd ' . fnameescape(l:fixture.root)
    let g:vim_cmake_naive_test_use_popup_menu = 1
    let g:vim_cmake_naive_test_popup_menu_response = {'query': 'LIB', 'search_mode': 0, 'result': 0}
    unlet! g:vim_cmake_naive_test_last_target_popup_items
    unlet! g:vim_cmake_naive_test_last_target_popup_options
    unlet! g:vim_cmake_naive_test_menu_response
    unlet! g:vim_cmake_naive_test_inputlist_response
    call vim_cmake_naive#switch_target()

    call assert_equal(['1.   mylib'], get(g:, 'vim_cmake_naive_test_last_target_popup_items', []))
    call assert_equal('Select target [LIB] (Insert)', get(g:vim_cmake_naive_test_last_target_popup_options, 'title', ''))
    call assert_equal({'output': 'build', 'preset': 'dev', 'target': 'old'}, s:read_json(l:config_path))
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

function! s:test_switch_target_popup_display_items_marks_all_when_target_missing() abort
  let l:fixture = s:create_cmake_project_fixture()
  let l:initial_cwd = getcwd()
  let l:initial_use_popup = get(g:, 'vim_cmake_naive_test_use_popup_menu', v:null)
  let l:initial_popup_response = get(g:, 'vim_cmake_naive_test_popup_menu_response', v:null)
  let l:initial_popup_items = get(g:, 'vim_cmake_naive_test_last_target_popup_items', v:null)
  let l:initial_popup_options = get(g:, 'vim_cmake_naive_test_last_target_popup_options', v:null)
  let l:initial_menu_selection = get(g:, 'vim_cmake_naive_test_menu_response', v:null)
  let l:initial_inputlist_selection = get(g:, 'vim_cmake_naive_test_inputlist_response', v:null)

  try
    let l:config_path = s:path_join(l:fixture.root, '.vim-cmake-naive-config.json')
    call s:write_json(l:config_path, {'output': 'build', 'preset': 'dev'})
    call s:write_json(s:path_join(l:fixture.root, '.vim-cmake-naive-cache.json'), {'targets': ['app']})

    let l:target_dir = s:path_join(l:fixture.root, 'build/dev/CMakeFiles/app.dir')
    let l:root_commands = s:path_join(l:fixture.root, 'build/dev/compile_commands.json')
    let l:active_commands = s:path_join(l:fixture.root, 'build/compile_commands.json')
    call mkdir(l:target_dir, 'p')
    call s:write_json(l:root_commands, [
          \ {
          \   'directory': '.',
          \   'output': 'CMakeFiles/app.dir/main.cpp.o',
          \   'file': '../src/main.cpp'
          \ }
          \ ])
    call s:write_json(l:active_commands, [{'file': '../active-before-popup.cpp'}])

    execute 'cd ' . fnameescape(l:fixture.root)
    let g:vim_cmake_naive_test_use_popup_menu = 1
    let g:vim_cmake_naive_test_popup_menu_response = 0
    unlet! g:vim_cmake_naive_test_menu_response
    unlet! g:vim_cmake_naive_test_inputlist_response
    unlet! g:vim_cmake_naive_test_last_target_popup_items
    unlet! g:vim_cmake_naive_test_last_target_popup_options
    call vim_cmake_naive#switch_target()

    call assert_equal(['1. * (all)', '2.   app'], get(g:, 'vim_cmake_naive_test_last_target_popup_items', []))
    call assert_equal({'output': 'build', 'preset': 'dev'}, s:read_json(l:config_path))
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
  call s:test_plugin_defines_plug_mappings_by_default()
  call s:test_plugin_registers_plug_mappings_for_commands()
  call s:test_plugin_startup_syncs_integration_files_from_local_config()
  call s:test_cmake_config_creates_default_local_config()
  call s:test_cmake_config_preserves_existing_file()
  call s:test_cmake_set_config_preset_creates_config_with_preset()
  call s:test_cmake_set_config_preset_preserves_existing_keys()
  call s:test_cmake_set_config_build_config_creates_config_with_value()
  call s:test_cmake_set_config_build_config_preserves_other_keys()
  call s:test_cmake_set_config_output_creates_config_with_value()
  call s:test_cmake_set_config_output_preserves_other_keys()
  call s:test_cmake_set_commands_use_nearest_existing_local_config()
  call s:test_cmake_set_commands_error_when_no_local_config_found()
  call s:test_cmake_set_commands_do_not_use_parent_project_config()
  call s:test_cmake_commands_report_running_command_lock()
  call s:test_cmake_command_lock_resets_after_command_failure()
  call s:test_cmake_command_lock_persists_while_async_terminal_command_runs()
  call s:test_cmake_menu_popup_holds_command_lock_until_closed()
  call s:test_cmake_config_default_creates_default_values()
  call s:test_cmake_config_default_reapplies_defaults_and_preserves_other_keys()
  call s:test_cmake_config_uses_nearest_parent_cmakelists()
  call s:test_cmake_config_errors_when_no_cmakelists_found()
  call s:test_cmake_config_default_uses_nearest_parent_cmakelists()
  call s:test_cmake_config_default_errors_when_no_cmakelists_found()
  call s:test_cmake_generate_creates_default_config_and_invokes_cmake()
  call s:test_cmake_generate_uses_existing_config_values()
  call s:test_cmake_generate_opens_horizontal_terminal_with_command_output()
  call s:test_cmake_generate_reuses_visible_output_window_when_possible()
  call s:test_cmake_generate_sets_running_terminal_name_on_subsequent_invocation()
  call s:test_cmake_build_reuses_generate_output_window_when_possible()
  call s:test_cmake_generate_errors_when_no_cmakelists_found()
  call s:test_cmake_generate_updates_targets_cache_and_splits_compile_commands()
  call s:test_cmake_generate_updates_targets_cache_and_splits_compile_commands_for_preset_directory()
  call s:test_cmake_generate_ignores_targets_from_deps_directory()
  call s:test_cmake_build_creates_default_config_and_invokes_cmake_build()
  call s:test_cmake_build_uses_existing_config_preset_and_target()
  call s:test_cmake_build_sets_running_terminal_name_with_preset_and_target()
  call s:test_cmake_build_sets_running_terminal_name_on_subsequent_invocation()
  call s:test_cmake_build_opens_horizontal_terminal_with_command_output()
  call s:test_cmake_build_opens_horizontal_terminal_with_stdout_and_stderr_output()
  call s:test_cmake_build_sets_failure_terminal_name_with_exit_code()
  call s:test_cmake_build_reuses_visible_output_window_when_possible()
  call s:test_cmake_build_does_not_resize_when_started_from_terminal_window()
  call s:test_cmake_generate_reuses_build_output_window_when_possible()
  call s:test_cmake_generate_reuses_build_output_window_in_async_mode()
  call s:test_cmake_build_recreates_visible_output_window_when_reuse_not_possible()
  call s:test_cmake_build_errors_when_no_cmakelists_found()
  call s:test_cmake_test_runs_ctest_in_output_directory_without_preset()
  call s:test_cmake_test_runs_ctest_in_output_preset_directory_with_preset()
  call s:test_cmake_test_sets_running_terminal_name_with_preset()
  call s:test_cmake_test_sets_running_terminal_name_without_preset()
  call s:test_cmake_test_reuses_build_output_window_when_possible()
  call s:test_cmake_run_reports_missing_target_selection()
  call s:test_cmake_run_runs_target_in_output_directory_without_preset()
  call s:test_cmake_run_runs_target_in_output_preset_directory_with_preset()
  call s:test_cmake_run_sets_running_terminal_name_with_preset_and_target()
  call s:test_cmake_run_opens_horizontal_terminal_with_command_output()
  call s:test_cmake_run_reuses_build_output_window_when_possible()
  call s:test_cmake_close_closes_generate_terminal_window()
  call s:test_cmake_close_closes_build_terminal_window()
  call s:test_cmake_info_popup_shows_config_as_table()
  call s:test_cmake_info_popup_reports_missing_config()
  call s:test_cmake_menu_popup_lists_compact_commands_and_executes_selection()
  call s:test_cmake_menu_popup_lists_commands_and_executes_selection()
  call s:test_cmake_menu_executes_command_with_arguments()
  call s:test_cmake_menu_cancels_argument_command_when_args_empty()
  call s:test_cmake_menu_cancels_without_executing_when_popup_canceled()
  call s:test_cmake_menu_popup_filters_items_by_search_query()
  call s:test_cmake_menu_popup_retains_filter_when_search_mode_exits()
  call s:test_cmake_switch_preset_sets_selected_visible_preset()
  call s:test_cmake_switch_preset_selects_none_and_removes_preset_key()
  call s:test_cmake_switch_preset_reports_missing_presets_file()
  call s:test_cmake_switch_preset_reports_missing_local_config()
  call s:test_cmake_switch_preset_cancels_without_changing_config()
  call s:test_cmake_switch_preset_only_none_is_selectable_when_no_visible_presets()
  call s:test_cmake_switch_preset_menu_fallback_displays_parenthesized_none()
  call s:test_preset_popup_display_items_formats_ordered_list_and_current_marker()
  call s:test_switch_preset_popup_display_items_marks_none_when_preset_missing()
  call s:test_switch_preset_popup_filters_items_by_search_query()
  call s:test_switch_preset_popup_retains_filter_when_search_mode_exits()
  call s:test_cmake_switch_build_sets_selected_build_and_removes_preset()
  call s:test_cmake_switch_build_selects_none_and_removes_build()
  call s:test_cmake_switch_build_reports_missing_local_config()
  call s:test_cmake_switch_build_menu_fallback_displays_parenthesized_none()
  call s:test_cmake_switch_build_popup_display_items_marks_current_selection()
  call s:test_cmake_switch_build_popup_display_items_marks_none_when_build_missing()
  call s:test_switch_build_popup_filters_items_by_search_query()
  call s:test_switch_build_popup_retains_filter_when_search_mode_exits()
  call s:test_cmake_switch_target_sets_selected_target()
  call s:test_cmake_switch_target_selects_all_and_removes_target_key()
  call s:test_cmake_switch_target_popup_sets_selected_target()
  call s:test_cmake_switch_target_reports_missing_cache_file()
  call s:test_cmake_switch_target_reports_cache_without_targets_key()
  call s:test_cmake_switch_target_cancels_without_changing_config()
  call s:test_cmake_switch_target_inputlist_fallback_displays_parenthesized_all()
  call s:test_cmake_switch_target_reports_missing_build_directory()
  call s:test_cmake_switch_target_selects_all_when_cache_targets_are_empty()
  call s:test_cmake_switch_target_reports_missing_target_compile_commands()
  call s:test_cmake_switch_target_reports_missing_root_compile_commands_for_all_selection()
  call s:test_cmake_switch_target_does_not_fallback_to_output_root_when_preset_is_set()
  call s:test_switch_target_popup_display_items_marks_current_selection_and_limits_height()
  call s:test_switch_target_popup_filters_items_by_search_query()
  call s:test_switch_target_popup_retains_filter_when_search_mode_exits()
  call s:test_switch_target_popup_display_items_marks_all_when_target_missing()
endfunction
