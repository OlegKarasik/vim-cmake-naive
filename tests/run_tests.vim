set nocompatible
set nomore

let s:repo_root = fnamemodify(expand('<sfile>:p'), ':h:h')
execute 'set runtimepath^=' . fnameescape(s:repo_root)

runtime plugin/cdbm.vim
execute 'source ' . fnameescape(s:repo_root . '/tests/cdbm_tests.vim')

call CdbmTestRunAll()

if !empty(v:errors)
  for s:error in v:errors
    echom s:error
  endfor
  cquit 1
endif

quitall!
