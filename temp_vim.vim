if has('nvim')
    if !has('nvim-0.5')
        echoerr 'Works only with nvim version 0.5.x or later.'
        finish
    endif
    function! <SID>CheckNull(x)
        return a:x is v:null
    endfunction
else
    if version < 810
        echoerr 'Works only with vim version 8.1.0 or later.'
        finish
    endif
    function! <SID>CheckNull(x)
        return a:x == v:null
    endfunction
endif

function! <SID>OpenBuffer(dir, bufnr, pos)

    if a:dir ==# 'left'
        call <SID>NewTempBuf(2)
    elseif a:dir ==# 'right'
        call <SID>NewTempBuf(1)
    elseif a:dir ==# 'up'
        call <SID>NewTempBuf(4)
    elseif a:dir ==# 'down'
        call <SID>NewTempBuf(3)
    else
        call <SID>NewTempBuf(0)
    end

    silent! exec 'buffer '.a:bufnr

    call cursor(a:pos[0], a:pos[1])

endfunction

function! <SID>GetCursorPos(winid)
    let [_, l, c, _, _] = getcursorcharpos(a:winid)
    return [l, c]
endfunction

function! <SID>GetWinSize(winid)
    return [winheight(a:winid), winwidth(a:winid)]
endfunction

function! <SID>YankWindow(winnr)
    if a:winnr == 0 " Current window
        let s:yank_winnr = winnr()
    else
        let s:yank_winnr = a:winnr
    endif
    let s:yank_bufnr = winbufnr(s:yank_winnr)
    let s:yank_bufhidden = getbufvar(s:yank_bufnr, '&bufhidden')
    let s:yank_pos = <SID>GetCursorPos(win_getid(s:yank_winnr))
endfunction

function! <SID>CloseWindow()
    call <SID>YankWindow(0)
    close
endfunction

function! <SID>PasteWindow(direction)
    if !exists('s:yank_bufnr')
        echoerr 'Yank target window first.'
        return
    endif
    if &modified
        echoerr 'Save this buffer first.'
        return
    endif
    let l:target_bufnr = s:yank_bufnr
    let l:target_bufhidden = s:yank_bufhidden
    let l:target_pos = s:yank_pos
    call <SID>YankWindow(0)
    call <SID>OpenBuffer(a:direction, l:target_bufnr, l:target_pos)
    let &bufhidden = l:target_bufhidden
endfunction

function! <SID>SwapWindow(...)
    if &modified
        echoerr 'Save this buffer first.'
        return
    endif

    if a:0 > 1
        echoerr 'E118: Too many arguments for function: SwapWindow'
        return
    endif

    if a:0 == 1
        call <SID>YankWindow(a:1)
    else
        if !exists('s:yank_bufnr')
            echoerr 'Yank target window first.'
            return
        endif
    endif

    if getbufvar(s:yank_bufnr, '&modified')
        echoerr 'Save this buffer first.'
        return
    endif

    let l:target_winnr = s:yank_winnr
    call <SID>PasteWindow('here')
    exec l:target_winnr.'wincmd w'
    call <SID>PasteWindow('here')
    call <SID>YankWindow(0)

endfunction

" 복구 함수 정의
function! <SID>RestoreWindows(orig_bufs, orig_positions, win_count)
    for idx in range(1, a:win_count)
        exec idx . 'wincmd w'
        silent! exec 'buffer ' . a:orig_bufs[idx-1]
        call setpos('.', a:orig_positions[idx-1])
    endfor
endfunction

function! <SID>GetSingleChar()
    echo 'Press any key:'
    let l:ch = getchar()    " 사용자가 어떤 키를 누를 때까지 대기
    return l:ch
endfunction

function! <SID>MoveSwap()
    " 현재 탭의 모든 창 정보 백업
    let l:curwindow = winnr()
    let l:orig_bufs = []
    let l:orig_positions = []
    let l:win_count = winnr('$')

    " TODO: Currently, this feature supports maximum counts of English alphabet.
    if l:win_count > char2nr('z') - char2nr('a') + 1
        echoerr 'Too many opened windows'
        return
    endif

    " Stores original buffer number while traversing all windows.
    for i in range(1, l:win_count)
        exec i . 'wincmd w'
        let l:buf = bufnr('%')

        if getbufvar(l:buf, '&modified')
            echoerr 'Save all buffers first.'
            return
        endif

        call add(l:orig_bufs, l:buf)
        " Stores current cursor positions: [bufnum, lnum, col, off]
        call add(l:orig_positions, getpos('.'))
    endfor

    " Show the operation keys to each window.
    for i in range(1, l:win_count)
        exec i . 'wincmd w'
        call <SID>NewTempBuf(0)
        call setline(1, nr2char(char2nr('a') + i - 1))
        normal! gg
    endfor

    redraw

    let l:selected = <SID>GetSingleChar() - char2nr('a') + 1
    call <SID>RestoreWindows(l:orig_bufs, l:orig_positions, l:win_count)

    exec l:curwindow . 'wincmd w'

    if 1 <= l:selected && l:selected <= l:win_count
        call <SID>SwapWindow(l:selected)
    endif

endfunction


function! <SID>FindWindowCallback(parents, node)
    if a:node[1] == s:cur_winid
        return [a:parents, a:node]
    endif
    return v:null
endfunction

function! <SID>SaveLayoutCallback(parents, node)
    " a:node
    "   [0]: Type
    "   [1]: Window number
    "   [2]: Buffer number
    "   [3]: [Position line, Position column]
    "   [4]: [Window height, Window width]
    silent! call add(a:node, winbufnr(a:node[1]))
    silent! call add(a:node, <SID>GetCursorPos(a:node[1]))
    silent! call add(a:node, <SID>GetWinSize(a:node[1]))
    return v:null
endfunction

function! <SID>NewTempBuf(direction)
    if a:direction == 1 " Right
        silent! belowright vnew
    elseif a:direction == 2 " Left
        silent! aboveleft vnew
    elseif a:direction == 3 " Down
        silent! belowright new
    elseif a:direction == 4 " Up
        silent! aboveleft new
    else    " Here
        silent! enew
    endif
    setlocal buftype=nofile bufhidden=wipe noswapfile
endfunction

function! <SID>SaveLayout(node)
    call <SID>LayoutRecursive([['root', -1]], a:node, function('<SID>SaveLayoutCallback'))
endfunction

function! <SID>OnlyLayoutCallback(parents, node)
    silent! call win_gotoid(a:node[1])
    silent! close
    return v:null
endfunction

function! <SID>OnlyLayout(node)
    call <SID>LayoutRecursive([['root', -1]], a:node, function('<SID>OnlyLayoutCallback'))
endfunction

function! <SID>RestoreNodes(node)
    if a:node[0] ==# 'leaf'
        silent! execute 'buffer '.a:node[2]
        silent! call cursor(a:node[3][0], a:node[3][1])
        " TODO: Resize window size
        " resize a:node[4][0] | vertical resize a:node[4][1]
    else
        silent! call <SID>RestoreLayout(a:node)
    endif
endfunction

function! <SID>RestoreLayout(node)
    for l:i in range(0, len(a:node[1]) - 2)
        if a:node[0] ==# 'row'
            call <SID>NewTempBuf(2)
        else " 'column'
            call <SID>NewTempBuf(4)
        endif
        call <SID>RestoreNodes(a:node[1][l:i])
        silent! wincmd w
    endfor

    call <SID>RestoreNodes(a:node[1][-1])
endfunction

function! <SID>MoveWindow(dir, parents, node)
    let [height, width] = <SID>GetWinSize(a:node[1])
    let l:parent = a:parents[0]

    if l:parent[0] ==# 'root'
        return v:null
    endif

    let l:gp = a:parents[1]

    if a:dir ==# 'right'
        let l:axis = 'row'
        let l:negative = 0
        let l:split_types = [1, 2, 2]   " [leaf, dummy, restore]
        let l:wincmd = 'l'
    elseif a:dir ==# 'left'
        let l:axis = 'row'
        let l:negative = 1
        let l:split_types = [2, 2, 1]
        let l:wincmd = 'h'
    elseif a:dir ==# 'down'
        let l:axis = 'col'
        let l:negative = 0
        let l:split_types = [3, 4, 4]
        let l:wincmd = 'j'
    elseif a:dir ==# 'up'
        let l:axis = 'col'
        let l:negative = 1
        let l:split_types = [4, 4, 3]
        let l:wincmd = 'k'
    else
        return v:null
    endif

    if l:parent[0] !=# l:axis
        return v:null
    endif

    let l:next_node = v:null

    " If the direction is right or down, the iteration range is [0, length).
    " Otherwise, (0, length].
    for l:i in range(l:negative, len(l:parent[1]) - 2 + l:negative)
        let l:child = l:parent[1][l:i]
        if l:child[0] == a:node[0] && l:child[1] == a:node[1]
            let l:next_node = l:parent[1][l:i + 1 + (-2 * l:negative)]
            break
        endif
    endfor

    if <SID>CheckNull(l:next_node)
        return v:null
    endif

    if l:next_node[0] == 'leaf'
        silent! exec 'wincmd '.l:wincmd
        call <SID>NewTempBuf(l:split_types[0])
        return win_getid()
    else " l:next_node[0] == cross axis container
        let l:stored_layout = copy(l:next_node)
        call <SID>SaveLayout(l:stored_layout)

        " Add a dummy window
        silent! call win_gotoid(a:node[1])
        silent! exec 'wincmd '.l:wincmd
        call <SID>NewTempBuf(l:split_types[1])

        " Removes all sub windows except target window
        call <SID>OnlyLayout(l:next_node)
        let l:target_winid = win_getid()

        " TODO: Resize window size
        " resize height | vert resize width

        call <SID>NewTempBuf(l:split_types[2])
        call <SID>RestoreLayout(l:stored_layout)

        return l:target_winid
    endif

    return v:null
endfunction


function! <SID>MoveWindowAPI(dir)
    let s:cur_winid = win_getid()
    let l:cur_bufnr = winbufnr(s:cur_winid)
    let l:layout = winlayout()
    let [l:winline, l:wincol] = <SID>GetCursorPos(s:cur_winid)

    " Traverse all windows and verify that buffers are saved
    " TODO: Change the command to work even if the BUF of an unaffected window is being modified.
    for i in range(1, winnr('$'))
        if getbufvar(winbufnr(i), '&modified')
            echoerr 'Save all buffers first.'
            unlet s:cur_winid
            return
        endif
    endfor
    silent! call win_gotoid(s:cur_winid) " Come back to current window.

    let [parents, node] = <SID>LayoutRecursive([['root', -1]], l:layout, function('<SID>FindWindowCallback'))

    let l:target_winid = <SID>MoveWindow(a:dir, parents, node)
    if !<SID>CheckNull(l:target_winid)
        silent! call win_gotoid(s:cur_winid)
        silent! close
        silent! call win_gotoid(l:target_winid)
        silent! execute 'buffer '.l:cur_bufnr
        silent! call cursor(l:winline, l:wincol)
    endif
    unlet s:cur_winid
endfunction


function! <SID>PrintCallback(parents, node)
    echo a:parents[0][0].' '.a:node[1]
    return v:null
endfunction

" Evaluate LayoutRecursive
function! <SID>PrintWinIDs()
    let l:layout = winlayout()
    call <SID>LayoutRecursive([['root', -1]], l:layout, function('<SID>PrintCallback'))
endfunction

function! <SID>LayoutRecursive(parents, node, cb)
    let l:type = a:node[0]
    if l:type ==# 'leaf'
        let l:winid = a:node[1]
        let l:ret = a:cb(a:parents, a:node)
        if !<SID>CheckNull(l:ret)
            return l:ret
        endif
    else
        call insert(a:parents, a:node, 0)
        for l:child in a:node[1]
            let l:ret = <SID>LayoutRecursive(a:parents, l:child, a:cb)
            if !<SID>CheckNull(l:ret)
                return l:ret
            endif
        endfor
        call remove(a:parents, 0)
    endif
    return v:null
endfunction

command! PrintIDs call <SID>PrintWinIDs()


" Key Mapping
" ==================================================================================================
nnoremap <silent> <Plug>WMDelete :call <SID>CloseWindow()<CR>
nnoremap <silent> <Plug>WMYank :call <SID>YankWindow(0)<CR>
nnoremap <silent> <Plug>WMPasteUp :call <SID>PasteWindow('up')<CR>
nnoremap <silent> <Plug>WMPasteDown :call <SID>PasteWindow('down')<CR>
nnoremap <silent> <Plug>WMPasteLeft :call <SID>PasteWindow('left')<CR>
nnoremap <silent> <Plug>WMPasteRight :call <SID>PasteWindow('right')<CR>
nnoremap <silent> <Plug>WMPasteHere :call <SID>PasteWindow('here')<CR>
nnoremap <silent> <Plug>WMSwap :call <SID>SwapWindow()<CR>

nnoremap <silent> <Plug>WMMoveSwap :call <SID>MoveSwap()<CR>

nnoremap <silent> <Plug>WMMoveRight :call <SID>MoveWindowAPI('right')<CR>
nnoremap <silent> <Plug>WMMoveLeft :call <SID>MoveWindowAPI('left')<CR>
nnoremap <silent> <Plug>WMMoveDown :call <SID>MoveWindowAPI('down')<CR>
nnoremap <silent> <Plug>WMMoveUp :call <SID>MoveWindowAPI('up')<CR>

if !exists('g:wm_default_mappings')
    let g:wm_default_mappings = 1
endif

if !exists('g:wm_numbering_mapping_windows')
    let g:wm_numbering_mapping_windows = 1
endif

if g:wm_default_mappings
    nnoremap <c-w>d  <Plug>WMDelete
    nnoremap <c-w>y  <Plug>WMYank
    nnoremap <c-w>pk <Plug>WMPasteUp
    nnoremap <c-w>pj <Plug>WMPasteDown
    nnoremap <c-w>ph <Plug>WMPasteLeft
    nnoremap <c-w>pl <Plug>WMPasteRight
    nnoremap <c-w>pp <Plug>WMPasteHere
    nnoremap <c-w>P  <Plug>WMSwap

    nnoremap <c-s>   <Plug>WMMoveSwap

    nnoremap <C-w>l  <Plug>WMMoveRight
    nnoremap <C-w>h  <Plug>WMMoveLeft
    nnoremap <C-w>j  <Plug>WMMoveDown
    nnoremap <C-w>k  <Plug>WMMoveUp

    if g:wm_numbering_mapping_windows == 1
        for i in range(1, 10)
            exec 'nnoremap <C-w>'.i.' '.i.'<C-w>w'
        endfor
    endif

endif
