if exists('g:loaded_vim_cmake_naive')
  finish
endif
let g:loaded_vim_cmake_naive = 1

call vim_cmake_naive#sync_environment_from_local_config_on_startup()

command! -nargs=0 CMakeConfig call vim_cmake_naive#cmake_config()
command! -nargs=0 CMakeConfigDefault call vim_cmake_naive#cmake_config_default()
command! -nargs=0 CMakeSwitchPreset call vim_cmake_naive#switch_preset()
command! -nargs=0 CMakeSwitchBuild call vim_cmake_naive#switch_build()
command! -nargs=0 CMakeSwitchTarget call vim_cmake_naive#switch_target()
command! -nargs=0 CMakeGenerate call vim_cmake_naive#generate()
command! -nargs=0 CMakeBuild call vim_cmake_naive#build()
command! -nargs=0 CMakeClose call vim_cmake_naive#close()
command! -nargs=0 CMakeInfo call vim_cmake_naive#info()
command! -nargs=0 CMakeMenu call vim_cmake_naive#menu()
command! -nargs=0 CMakeMenuFull call vim_cmake_naive#menu_full()
command! -nargs=+ CMakeConfigSetPreset call vim_cmake_naive#set_config_preset(<q-args>)
command! -nargs=+ CMakeConfigSetBuild call vim_cmake_naive#set_config_build_config(<q-args>)
command! -nargs=+ CMakeConfigSetOutput call vim_cmake_naive#set_config_output(<q-args>)
