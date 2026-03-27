if exists('g:loaded_vim_cmake_naive')
  finish
endif
let g:loaded_vim_cmake_naive = 1

command! -nargs=0 CMakeConfig call vim_cmake_naive#cmake_config()
command! -nargs=0 CMakeConfigDefault call vim_cmake_naive#cmake_config_default()
command! -nargs=0 CMakeSwitchPreset call vim_cmake_naive#switch_preset()
command! -nargs=0 CMakeGenerate call vim_cmake_naive#generate()
command! -nargs=+ CMakeConfigSetPreset call vim_cmake_naive#set_config_preset(<q-args>)
command! -nargs=0 CMakeConfigResetPreset call vim_cmake_naive#reset_config_preset()
command! -nargs=+ CMakeConfigSetBuild call vim_cmake_naive#set_config_build_config(<q-args>)
command! -nargs=+ CMakeConfigSetOutput call vim_cmake_naive#set_config_output(<q-args>)
