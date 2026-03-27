if exists('g:loaded_cdbm')
  finish
endif
let g:loaded_cdbm = 1

command! -nargs=+ -complete=dir CdbmSplit call cdbm#split(<f-args>)
command! -nargs=+ -complete=dir CdbmSwitch call cdbm#switch(<f-args>)
command! -nargs=0 CMakeConfig call cdbm#cmake_config()
command! -nargs=0 CMakeConfigDefault call cdbm#cmake_config_default()
command! -nargs=0 CMakeGenerate call cdbm#generate()
command! -nargs=+ CMakeConfigSetPreset call cdbm#set_config_preset(<q-args>)
command! -nargs=0 CMakeResetConfigPreset call cdbm#reset_config_preset()
command! -nargs=+ CMakeConfigSetBuild call cdbm#set_config_build_config(<q-args>)
command! -nargs=+ CMakeConfigSetOutput call cdbm#set_config_output(<q-args>)
