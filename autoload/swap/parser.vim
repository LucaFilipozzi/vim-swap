" parser - Parse a text to give a buffer object.

function! swap#parser#parse(region, rule, curpos) abort "{{{
  " s:parse_{type}wise() functions return a list of dictionaries which have two keys at least, attr and string.
  "   attr   : 'item' or 'delimiter' or 'immutable'.
  "            'item' means that the string is an item reordered.
  "            'delimiter' means that the string is an item for separation. It would not be regarded as an item reordered.
  "            'immutable' is not an 'item' and not a 'delimiter'. It is a string which should not be changed.
  "   string : The value is the string as 'item' or 'delimiter' or 'immutable'.
  " For instance,
  "   'foo,bar' is parsed to [{'attr': 'item', 'string': 'foo'}, {'attr': 'delimiter', 'string': ','}, {'attr': 'item': 'string': 'bar'}]
  " In case that motionwise ==# 'V' or "\<C-v>", delimiter string should be "\n".
  let text = s:get_buf_text(a:region)
  let buffer = swap#buffer#new()
  let buffer.region = a:region
  let buffer.all = s:parse_{a:region.type}wise(text, a:rule)
  let buffer.items = filter(copy(buffer.all), 'v:val.attr ==# "item"')
  let buffer.delimiters = filter(copy(buffer.all), 'v:val.attr ==# "delimiter"')
  call buffer.functionalize()
  call buffer.address()
  call buffer.set_sharp(a:curpos)
  call buffer.set_hat()
  call buffer.set_dollar()
  return buffer
endfunction
"}}}

function! s:parse_charwise(text, rule) abort  "{{{
  let idx = 0
  let end = strlen(a:text)
  let head = 0
  let last_delimiter_tail = -1/0
  let buffer = []

  let targets = {}
  let targets.delimiter = map(copy(get(a:rule, 'delimiter', [])), '[-1, v:val, 0, "delimiter"]')
  let targets.immutable = map(copy(get(a:rule, 'immutable', [])), '[-1, v:val, 0, "immutable"]')
  let targets.braket    = map(copy(get(a:rule, 'braket', [])), '[-1, v:val, 0, "braket"]')
  let targets.quotes    = map(copy(get(a:rule, 'quotes', [])), '[-1, v:val, 0, "quotes"]')
  let targets.literal_quotes = map(copy(get(a:rule, 'literal_quotes', [])), '[-1, v:val, 0, "literal_quotes"]')
  let targets.all = targets.delimiter + targets.immutable + targets.braket + targets.quotes + targets.literal_quotes

  while idx < end
    unlet! pattern  " ugly...
    let [idx, pattern, occurence, kind] = s:shift_to_something_start(a:text, targets.all, idx)
    if idx < 0
      call s:add_buffer_text(buffer, 'item', a:text, head, idx)
      break
    else
      if kind ==# 'delimiter'
        " a delimiter is found
        " NOTE: I would like to treat zero-width delimiter as possible.
        let last_elem = get(buffer, -1, {'attr': ''})
        if idx == last_delimiter_tail && last_elem.attr ==# 'delimiter' && last_elem.string ==# ''
          " zero-width delimiter is found
          let idx += 1
          continue
        endif

        if !(head == idx && last_elem.attr ==# 'immutable')
          call s:add_buffer_text(buffer, 'item', a:text, head, idx)
        endif
        if idx == last_delimiter_tail
          " successive delimiters
          let [head, idx] = [idx, s:shift_to_delimiter_end(a:text, pattern, idx, 0)]
        else
          let [head, idx] = [idx, s:shift_to_delimiter_end(a:text, pattern, idx, 1)]
        endif
        call s:add_buffer_text(buffer, 'delimiter', a:text, head, idx)
        if idx < 0 || idx >= end
          break
        else
          let head = idx
          let last_delimiter_tail = idx
        endif
      elseif kind ==# 'braket'
        " a bra is found
        let idx = s:shift_to_braket_end(a:text, pattern, targets.quotes, targets.literal_quotes, idx)
        if idx < 0 || idx >= end
          call s:add_buffer_text(buffer, 'item', a:text, head, idx)
          break
        endif
      elseif kind ==# 'quotes'
        " a quote is found
        let idx = s:shift_to_quote_end(a:text, pattern, idx)
        if idx < 0 || idx >= end
          call s:add_buffer_text(buffer, 'item', a:text, head, idx)
          break
        endif
      elseif kind ==# 'literal_quotes'
        " an literal quote (non-escaped quote) is found
        let idx = s:shift_to_literal_quote_end(a:text, pattern, idx)
        if idx < 0 || idx >= end
          call s:add_buffer_text(buffer, 'item', a:text, head, idx)
          break
        endif
      else
        " an immutable string is found
        if idx != head
          call s:add_buffer_text(buffer, 'item', a:text, head, idx)
        endif
        let [head, idx] = [idx, s:shift_to_immutable_end(a:text, pattern, idx)]
        call s:add_buffer_text(buffer, 'immutable', a:text, head, idx)
        if idx < 0 || idx >= end
          break
        else
          let head = idx
        endif
      endif
    endif
  endwhile

  if buffer != [] && buffer[-1]['attr'] ==# 'delimiter'
    " If the last item is a delimiter, put empty item at the end.
    call s:add_buffer_text(buffer, 'item', a:text, idx, idx)
  endif
  return buffer
endfunction
"}}}
function! s:parse_linewise(text, rule) abort  "{{{
  let buffer = []
  for text in split(a:text, "\n", 1)[0:-2]
    call s:add_an_item(buffer, 'item', text)
    call s:add_an_item(buffer, 'delimiter', "\n")
  endfor
  return buffer
endfunction
"}}}
function! s:parse_blockwise(text, rule) abort  "{{{
  let buffer = []
  for text in split(a:text, "\n", 1)
    call s:add_an_item(buffer, 'item', text)
    call s:add_an_item(buffer, 'delimiter', "\n")
  endfor
  call remove(buffer, -1)
  return buffer
endfunction
"}}}
function! s:get_buf_text(region) abort  "{{{
  " NOTE: Do *not* use operator+textobject in another textobject!
  "       For example, getting a text with the command is not appropriate.
  "         execute printf('normal! %s:call setpos(".", %s)%s""y', a:retion.motionwise, string(a:region.tail), "\<CR>")
  "       Because it causes confusions for the unit of dot-repeating.
  "       Use visual selection+operator as following.
  let text = ''
  let visual = [getpos("'<"), getpos("'>")]
  let registers = s:saveregisters()
  try
    call setpos('.', a:region.head)
    execute 'normal! ' . a:region.visualkey
    call setpos('.', a:region.tail)
    silent noautocmd normal! ""y
    let text = @@
  finally
    call s:restoreregisters(registers)
    call setpos("'<", visual[0])
    call setpos("'>", visual[1])
    return text
  endtry
endfunction
"}}}
function! s:saveregisters() abort "{{{
  let registers = {}
  let registers['0'] = s:getregister('0')
  let registers['1'] = s:getregister('1')
  let registers['2'] = s:getregister('2')
  let registers['3'] = s:getregister('3')
  let registers['4'] = s:getregister('4')
  let registers['5'] = s:getregister('5')
  let registers['6'] = s:getregister('6')
  let registers['7'] = s:getregister('7')
  let registers['8'] = s:getregister('8')
  let registers['9'] = s:getregister('9')
  let registers['"'] = s:getregister('"')
  if &clipboard =~# 'unnamed'
    let registers['*'] = s:getregister('*')
  endif
  if &clipboard =~# 'unnamedplus'
    let registers['+'] = s:getregister('+')
  endif
  return registers
endfunction
"}}}
function! s:restoreregisters(registers) abort "{{{
  for [register, contains] in items(a:registers)
    call s:setregister(register, contains)
  endfor
endfunction
"}}}
function! s:getregister(register) abort "{{{
  return [getreg(a:register), getregtype(a:register)]
endfunction
"}}}
function! s:setregister(register, contains) abort "{{{
  let [value, options] = a:contains
  return setreg(a:register, value, options)
endfunction
"}}}
function! s:click(text, target, idx) abort  "{{{
  let idx = a:target[0]
  if idx < a:idx
    let kind = a:target[3]
    if kind ==# 'delimiter' || kind ==# 'immutable'
      " delimiter or immutable
      let a:target[0:2] = s:match(a:text, a:target[0:2], a:idx, 1)
    else
      " braket or quotes
      let pair = a:target[1]
      let a:target[0] = stridx(a:text, pair[0], a:idx)
    endif
  endif
  return a:target
endfunction
"}}}
function! s:shift_to_something_start(text, targets, idx) abort  "{{{
  let result = [-1, '', 0, '']
  call map(a:targets, 's:click(a:text, v:val, a:idx)')
  call filter(a:targets, 'v:val[0] > -1')
  if a:targets != []
    call s:sort(a:targets, function('s:compare_idx'), 1)
    let result = a:targets[0]
  endif
  return result
endfunction
"}}}
function! s:shift_to_delimiter_end(text, delimiter, idx, current_match) abort  "{{{
  return s:matchend(a:text, [0, a:delimiter, 0], a:idx, a:current_match)[0]
endfunction
"}}}
function! s:shift_to_braket_end(text, pair, quotes, literal_quotes, idx) abort  "{{{
  let end = strlen(a:text)
  let idx = s:stridxend(a:text, a:pair[0], a:idx)

  let depth = 0
  while 1
    let lastidx = idx
    let ket = s:stridxend(a:text, a:pair[1], idx)
    " do not take into account 'zero width' braket
    if ket == lastidx
      let idx += 1
      continue
    endif

    if ket < 0
      let idx = -1
    elseif ket >= end
      let idx = end
    else
      let bra = s:stridxend(a:text, a:pair[0], idx)
      if bra == lastidx
        let bra = s:stridxend(a:text, a:pair[0], idx+1)
      endif

      call filter(a:quotes, 'v:val[0] > -1')
      if a:quotes != []
        let quote = s:shift_to_something_start(a:text, a:quotes, idx)
      else
        let quote = [-1]
      endif

      call filter(a:literal_quotes, 'v:val[0] > -1')
      if a:literal_quotes != []
        let literal_quote = s:shift_to_something_start(a:text, a:literal_quotes, idx)
      else
        let literal_quote = [-1]
      endif

      let list_idx = filter([ket, bra, quote[0], literal_quote[0]], 'v:val > -1')
      if list_idx == []
        let idx = -1
      else
        let idx = min(list_idx)
        if idx == ket
          let depth -= 1
        elseif idx == bra
          let depth += 1
        elseif idx == quote[0]
          let idx = s:shift_to_quote_end(a:text, quote[1], quote[0])
          if idx > end
            let idx = -1
          endif
        else
          let idx = s:shift_to_literal_quote_end(a:text, literal_quote[1], literal_quote[0])
          if idx > end
            let idx = -1
          endif
        endif
      endif
    endif

    if idx < 0 || idx >= end || depth < 0
      break
    endif
  endwhile
  return idx
endfunction
"}}}
function! s:shift_to_quote_end(text, pair, idx) abort  "{{{
  let idx = s:stridxend(a:text, a:pair[0], a:idx)
  let end = strlen(a:text)
  let quote = 0

  while 1
    let quote = s:stridxend(a:text, a:pair[1], idx)
    " do not take into account 'zero width' quote
    if quote == idx
      let idx += 1
      continue
    endif

    if quote < 0
      let idx = -1
    else
      let idx = quote
      if idx > 1 && idx <= end && stridx(&quoteescape, a:text[idx-2]) > -1
        let n = strchars(matchstr(a:text[: idx-2], printf('%s\+$', s:escape(a:text[idx-2]))))
        if n%2 == 1
          continue
        endif
      endif
    endif
    break
  endwhile
  return idx
endfunction
"}}}
function! s:shift_to_literal_quote_end(text, pair, idx) abort  "{{{
  let idx = s:stridxend(a:text, a:pair[0], a:idx)
  let literal_quote = s:stridxend(a:text, a:pair[1], idx)
  if literal_quote == idx
    let literal_quote = s:stridxend(a:text, a:pair[1], idx+1)
  endif
  return literal_quote
endfunction
"}}}
function! s:shift_to_immutable_end(text, immutable, idx) abort  "{{{
  " NOTE: Zero-width immutable would not be considered.
  return s:matchend(a:text, [0, a:immutable, 0], a:idx, 0)[0]
endfunction
"}}}
function! s:add_buffer_text(buffer, attr, text, head, next_head) abort  "{{{
  " NOTE: Zero-width 'item', 'delimiter' and 'immutable' should be possible.
  "       If it is not favolable, I should control outside of this function.
  if a:head >= 0
    if a:next_head < 0
      let string = a:text[a:head :]
    elseif a:next_head <= a:head
      let string = ''
    else
      let string = a:text[a:head : a:next_head-1]
    endif
    call s:add_an_item(a:buffer, a:attr, string)
  endif
endfunction
"}}}
function! s:add_an_item(buffer, attr, string) abort "{{{
  return add(a:buffer, {'attr': a:attr, 'string': a:string})
endfunction
"}}}
function! s:match(string, target, idx, ...) abort "{{{
  " NOTE: current_match is like 'c' flag in search()
  let current_match = get(a:000, 0, 1)

  " NOTE: Because s:match_by_occurence() is heavy, it is used only when
  "       a pattern includes '\zs', '\@<=' and '\@<!'.
  if match(a:target[1], '[^\\]\%(\\\\\)*\\zs') > -1 || match(a:target[1], '[^\\]\%(\\\\\)*\\@\d*<[!=]') > -1
    return s:match_by_occurence(a:string, a:target, a:idx, current_match)
  else
    return s:match_by_idx(a:string, a:target, a:idx, current_match)
  endif
endfunction
"}}}
function! s:match_by_idx(string, target, idx, current_match) abort  "{{{
  let [idx, pattern, occurrence] = a:target
  let idx = match(a:string, pattern, a:idx)
  if !a:current_match && idx == a:idx
    let idx = match(a:string, pattern, a:idx, 2)
  endif
  return [idx, pattern, occurrence]
endfunction
"}}}
function! s:match_by_occurence(string, target, idx, current_match) abort  "{{{
  let [idx, pattern, occurrence] = a:target
  if a:idx < idx
    let occurrence = 0
  endif
  while 1
    let idx = match(a:string, pattern, 0, occurrence + 1)
    if idx >= 0
      let occurrence += 1
      if (a:current_match && idx < a:idx) || (!a:current_match && idx <= a:idx)
        continue
      endif
    endif
    break
  endwhile
  return [idx, pattern, occurrence]
endfunction
"}}}
function! s:matchend(string, target, idx, ...) abort "{{{
  " NOTE: current_match is like 'c' flag in search()
  let current_match = get(a:000, 0, 1)

  " NOTE: Because s:match_by_occurence() is heavy, it is used only when
  "       a pattern includes '\zs', '\@<=' and '\@<!'.
  if match(a:target[1], '[^\\]\%(\\\\\)*\\zs') > -1 || match(a:target[1], '[^\\]\%(\\\\\)*\\@\d*<[!=]') > -1
    return s:matchend_by_occurence(a:string, a:target, a:idx, current_match)
  else
    return s:matchend_by_idx(a:string, a:target, a:idx, current_match)
  endif
endfunction
"}}}
function! s:matchend_by_occurence(string, target, idx, current_match) abort "{{{
  let [idx, pattern, occurrence] = a:target
  if a:idx < idx
    let occurrence = 0
  endif
  while 1
    let idx = matchend(a:string, pattern, 0, occurrence + 1)
    if idx >= 0
      let occurrence += 1
      if (a:current_match && idx < a:idx) || (!a:current_match && idx <= a:idx)
        continue
      endif
    endif
    break
  endwhile
  return [idx, pattern, occurrence]
endfunction
"}}}
function! s:matchend_by_idx(string, target, idx, current_match) abort "{{{
  let [idx, pattern, occurrence] = a:target
  let idx = matchend(a:string, pattern, a:idx)
  if !a:current_match && idx == a:idx
    let idx = matchend(a:string, pattern, a:idx, 2)
  endif
  return [idx, pattern, occurrence]
endfunction
"}}}
function! s:stridxend(heystack, needle, ...) abort  "{{{
  let start = get(a:000, 0, 0)
  let idx = stridx(a:heystack, a:needle, start)
  return idx >= 0 ? idx + strlen(a:needle) : idx
endfunction
"}}}
function! s:compare_idx(i1, i2) abort "{{{
  return a:i1[0] - a:i2[0]
endfunction
"}}}

let [s:sort, s:escape] = swap#lib#funcref(['sort', 'escape'])

" vim:set foldmethod=marker:
" vim:set commentstring="%s:
" vim:set ts=2 sts=2 sw=2:
