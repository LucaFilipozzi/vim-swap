" clock object - Measuring time.

" features
let s:has_reltime_and_float = has('reltime') && has('float')

function! swap#clock#new() abort  "{{{
  return deepcopy(s:clock_prototype)
endfunction
"}}}

let s:clock_prototype = {
      \   'started' : 0,
      \   'paused'  : 0,
      \   'losstime': 0,
      \   'zerotime': reltime(),
      \   'pause_at': reltime(),
      \ }
function! s:clock_prototype.start() dict abort  "{{{
  if self.started
    if self.paused
      let self.losstime += str2float(reltimestr(reltime(self.pause_at)))
      let self.paused = 0
    endif
  else
    if s:has_reltime_and_float
      let self.zerotime = reltime()
      let self.started  = 1
    endif
  endif
endfunction
"}}}
function! s:clock_prototype.pause() dict abort "{{{
  let self.pause_at = reltime()
  let self.paused   = 1
endfunction
"}}}
function! s:clock_prototype.elapsed() dict abort "{{{
  if self.started
    let total = str2float(reltimestr(reltime(self.zerotime)))
    return floor((total - self.losstime)*1000)
  else
    return 0
  endif
endfunction
"}}}
function! s:clock_prototype.stop() dict abort  "{{{
  let self.started  = 0
  let self.paused   = 0
  let self.losstime = 0
endfunction
"}}}

" vim:set foldmethod=marker:
" vim:set commentstring="%s:
" vim:set ts=2 sts=2 sw=2:
