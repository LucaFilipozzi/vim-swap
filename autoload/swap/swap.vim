" swap object - Managing a whole action.

let s:type_str    = type('')
let s:type_num    = type(0)
let s:null_pos    = [0, 0, 0, 0]
let s:null_region = {'head': copy(s:null_pos), 'tail': copy(s:null_pos), 'len': -1, 'type': ''}

function! swap#swap#new() abort "{{{
  return deepcopy(s:swap_prototype)
endfunction
"}}}

let s:swap_prototype = {
      \   'dotrepeat': 0,
      \   'mode': '',
      \   'undojoin': 0,
      \   'rules': [],
      \   'order_list': [],
      \   'error': {
      \     'catched': 0,
      \     'message': '',
      \   },
      \ }
function! s:swap_prototype.execute(motionwise) dict abort "{{{
  if self.mode ==# 'n'
    call self._normal(a:motionwise)
  elseif self.mode ==# 'x'
    call self._visual(a:motionwise)
  endif
  let self.dotrepeat = 1
endfunction
"}}}
function! s:swap_prototype._normal(motionwise) dict abort  "{{{
  if self.dotrepeat
    let rules = deepcopy(self.rules)
    let [buffer, _] = s:scan(rules, a:motionwise)
    call self._swap_sequential(buffer)
  else
    let rules = self._get_rules()
    let [buffer, rule] = s:scan(rules, a:motionwise)
    if has_key(rule, 'initialize')
      let self.rules = [rule.initialize()]
      let self.order_list = self._swap(buffer)
    endif
  endif
endfunction
"}}}
function! s:swap_prototype._visual(motionwise) dict abort  "{{{
  let region = s:get_assigned_region(a:motionwise)
  if self.dotrepeat
    let rules = deepcopy(self.rules)
    let [buffer, _] = s:check(region, rules)
    call self._swap_sequential(buffer)
  else
    let rules = self._get_rules()
    let [buffer, rule] = s:check(region, rules)
    let self.rules = [rule]
    let self.order_list = self._swap(buffer)
  endif
endfunction
"}}}
function! s:swap_prototype._get_rules() dict abort  "{{{
  let rules = deepcopy(get(g:, 'swap#rules', g:swap#default_rules))
  call map(rules, 'extend(v:val, {"priority": 0}, "keep")')
  call s:sort(reverse(rules), function('s:compare_priority'))
  call filter(rules, 's:filter_filetype(v:val) && s:filter_mode(v:val, self.mode)')
  if self.mode !=# 'x'
    call s:remove_duplicate_rules(rules)
  endif
  return map(rules, 'swap#rule#get(v:val)')
endfunction
"}}}
function! s:swap_prototype._swap(buffer) dict abort "{{{
  if self.order_list != []
    return self._swap_sequential(a:buffer)
  else
    return self._swap_interactive(a:buffer)
  endif
endfunction
"}}}
function! s:swap_prototype._swap_interactive(buffer) dict abort "{{{
  if a:buffer == {}
    return []
  endif

  let self.undojoin = 0
  let interface = swap#interface#new()
  try
    while 1
      let order = interface.query(a:buffer)
      if order == [] | break | endif
      call self._swap_once(a:buffer, order)
    endwhile
  catch /^Vim:Interrupt$/
  catch /^Vim\%((\a\+)\)\=:E21/
    let err = g:swap.error
    call err.catch('vim-swap: Cannot make changes to read-only buffer.', 'SwapModeErr')
  catch
    let err = g:swap.error
    call err.catch(printf('vim-swap: Unanticipated error. [%s] %s', v:throwpoint, v:exception), 'SwapModeErr')
  finally
    call a:buffer.clear_highlight()
  endtry
  return interface.history
endfunction
"}}}
function! s:swap_prototype._swap_sequential(buffer) dict abort  "{{{
  if a:buffer != {}
    let self.undojoin = 0
    for order in self.order_list
      call self._swap_once(a:buffer, order)
    endfor
  endif
  return self.order_list
endfunction
"}}}
function! s:swap_prototype._swap_once(buffer, order) dict abort "{{{
  if a:order == []
    return
  endif

  let order = deepcopy(a:order)

  " substitute symbols
  for symbol in ['#', '^', '$']
    if stridx(order[0], symbol) > -1 || stridx(order[1], symbol) > -1
      call s:substitute_symbol(order, symbol, a:buffer.symbols[symbol])
    endif
  endfor

  " evaluate after substituting symbols
  call map(order, 'type(v:val) == s:type_str ? eval(v:val) : v:val')

  let n = len(a:buffer.items) - 1
  let idx = map(copy(order), 'type(v:val) == s:type_num ? v:val - 1 : -1')
  if idx[0] < 0 || idx[0] > n || idx[1] < 0 || idx[1] > n
    " the index is out of range
    return
  endif

  " swap items in buffer
  call a:buffer.swap(idx[0], idx[1])
  call a:buffer.address()

  " reflect to the buffer
  call s:reflect(a:buffer, self.undojoin, idx[1])
  let self.undojoin = 1
endfunction
"}}}
function! s:swap_prototype.error.catch(msg, ...) dict abort  "{{{
    let self.catched = 1
    let self.message = a:msg
    if a:0
      throw a:1
    endif
endfunction
"}}}

function! s:filter_filetype(rule) abort  "{{{
  if !has_key(a:rule, 'filetype')
    return 1
  else
    let filetypes = split(&filetype, '\.')
    if filetypes == []
      let filter = 'v:val ==# ""'
    else
      let filter = 'v:val !=# "" && match(filetypes, v:val) > -1'
    endif
    return filter(copy(a:rule['filetype']), filter) != []
  endif
endfunction
"}}}
function! s:filter_mode(rule, mode) abort  "{{{
  if !has_key(a:rule, 'mode')
    return 1
  else
    return stridx(a:rule.mode, a:mode) > -1
  endif
endfunction
"}}}
function! s:remove_duplicate_rules(rules) abort "{{{
  let i = 0
  while i < len(a:rules)
    let representative = a:rules[i]
    let j = i + 1
    while j < len(a:rules)
      let target = a:rules[j]
      let duplicate_body = 0
      let duplicate_surrounds = 0
      if (has_key(representative, 'body') && has_key(target, 'body') && representative.body == target.body)
            \ || (!has_key(representative, 'body') && !has_key(target, 'body'))
        let duplicate_body = 1
      endif
      if (has_key(representative, 'surrounds') && has_key(target, 'surrounds') && representative.surrounds[0:1] == target.surrounds[0:1] && get(representative, 2, 1) == get(target, 2, 1))
            \ || (!has_key(representative, 'surrounds') && !has_key(target, 'surrounds'))
        let duplicate_surrounds = 1
      endif
      if duplicate_body && duplicate_surrounds
        call remove(a:rules, j)
      else
        let j += 1
      endif
    endwhile
    let i += 1
  endwhile
endfunction
"}}}
function! s:get_assigned_region(motionwise) abort "{{{
  let region = deepcopy(s:null_region)
  let region.head = getpos("'[")
  let region.tail = getpos("']")
  let region.type = a:motionwise
  let region.visualkey = s:motionwise2visualkey(a:motionwise)

  if !s:is_valid_region(region)
    return deepcopy(s:null_region)
  endif

  let endcol = col([region.tail[1], '$'])
  if a:motionwise ==# 'V'
    let region.head[2] = 1
    let region.tail[2] = endcol
  else
    if region.tail[2] >= endcol
      let region.tail[2] = endcol
    endif
  endif

  if !s:is_valid_region(region)
    return deepcopy(s:null_region)
  endif

  let region.len = s:get_buf_length(region)
  return region
endfunction
"}}}
function! s:get_priority_group(rules) abort "{{{
  " NOTE: This function move items in a:rules to priority_group.
  "       Thus it makes changes to a:rules also.
  let priority = get(a:rules[0], 'priority', 0)
  let priority_group = []
  while a:rules != []
    let rule = a:rules[0]
    if rule.priority != priority
      break
    endif
    call add(priority_group, remove(a:rules, 0))
  endwhile
  return priority_group
endfunction
"}}}
function! s:scan(rules, motionwise) abort "{{{
  let view = winsaveview()
  let curpos = getpos('.')
  let buffer = {}
  while a:rules != []
    let priority_group = s:get_priority_group(a:rules)
    let [buffer, rule] = s:scan_group(priority_group, curpos, a:motionwise)
    if buffer != {}
      break
    endif
  endwhile
  call winrestview(view)
  return buffer != {} ? [buffer, rule] : [{}, {}]
endfunction
"}}}
function! s:scan_group(priority_group, curpos, motionwise) abort "{{{
  while a:priority_group != []
    for rule in a:priority_group
      call rule.search(a:curpos, a:motionwise)
    endfor
    call filter(a:priority_group, 's:is_valid_region(v:val.region)')
    call s:sort(a:priority_group, function('s:compare_len'))

    for rule in a:priority_group
      let region = rule.region
      let buffer = swap#parser#parse(region, rule, a:curpos)
      if buffer.swappable()
        return [buffer, rule]
      endif
    endfor
  endwhile
  return [{}, {}]
endfunction
"}}}
function! s:check(region, rules) abort  "{{{
  if a:region == s:null_region
    return [{}, {}]
  endif

  let view = winsaveview()
  let curpos = getpos('.')
  let buffer = {}
  while a:rules != []
    let priority_group = s:get_priority_group(a:rules)
    let [buffer, rule] = s:check_group(a:region, priority_group, curpos)
    if buffer != {}
      break
    endif
  endwhile
  call winrestview(view)
  return buffer != {} ? [buffer, rule] : [{}, {}]
endfunction
"}}}
function! s:check_group(region, priority_group, curpos) abort "{{{
  for rule in a:priority_group
    if rule.check(a:region)
      let buffer = swap#parser#parse(a:region, rule, a:curpos)
      if buffer.swappable()
        return [buffer, rule]
      endif
    endif
  endfor
  return [{}, {}]
endfunction
"}}}
function! s:compare_priority(r1, r2) abort "{{{
  let priority_r1 = get(a:r1, 'priority', 0)
  let priority_r2 = get(a:r2, 'priority', 0)
  if priority_r1 > priority_r2
    return -1
  elseif priority_r1 < priority_r2
    return 1
  else
    return 0
  endif
endfunction
"}}}
function! s:compare_len(r1, r2) abort "{{{
  return a:r1.region.len - a:r2.region.len
endfunction
"}}}
function! s:substitute_symbol(order, symbol, symbol_idx) abort "{{{
  let symbol = s:escape(a:symbol)
  return map(a:order, 'type(v:val) == s:type_str ? substitute(v:val, symbol, a:symbol_idx, "") : v:val')
endfunction
"}}}
function! s:reflect(buffer, undojoin, cursor_idx) abort "{{{
  let view = winsaveview()
  let region = a:buffer.region
  let visualkey = region.visualkey

  " reflect to the buffer
  let undojoin_cmd = a:undojoin ? 'undojoin | ' : ''
  let reg = ['"', getreg('"'), getregtype('"')]
  call setreg('"', join(map(copy(a:buffer.all), 'v:val.string'), ''), visualkey)
  call setpos('.', region.head)
  execute printf('%snoautocmd normal! "_d%s:call setpos(".", %s)%s""P:', undojoin_cmd, visualkey, string(region.tail), "\<CR>")
  let region.head = getpos("'[")
  let region.tail = getpos("']")
  call call('setreg', reg)

  " move cursor
  call winrestview(view)
  call a:buffer.items[a:cursor_idx].cursor()
  let a:buffer.symbols['#'] = a:cursor_idx + 1
endfunction
"}}}

let [s:get_buf_length, s:sort, s:is_valid_region, s:escape, s:motionwise2visualkey]
      \ = swap#lib#funcref(['get_buf_length', 'sort', 'is_valid_region', 'escape', 'motionwise2visualkey'])

" vim:set foldmethod=marker:
" vim:set commentstring="%s:
" vim:set ts=2 sts=2 sw=2:
