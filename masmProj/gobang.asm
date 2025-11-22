.386
.model flat, stdcall
option casemap:none

include windows.inc
include user32.inc
includelib user32.lib
include kernel32.inc
includelib kernel32.lib
include gdi32.inc
includelib gdi32.lib
include masm32.inc
includelib masm32.lib

;----------------------------------------
; 常量
;----------------------------------------
GRID_SIZE       equ 30            ; 每个格子像素
BOARD_OFFSET    equ 30            ; 棋盘左上角起始偏移
BOARD_COUNT     equ 15            ; 15x15 棋盘

;----------------------------------------
.data
hInstance       dd ?
hWinMain        dd ?

currentPlayer   dd 1              ; 1=黑棋  2=白棋
board           dd 225 dup(0)     ; 15*15 棋盘数组, 0=空 1=黑 2=白

szClassName     db "五子棋",0

;----------------------------------------
.code

;----------------------------------------
; 清空棋盘
;----------------------------------------
_ClearBoard PROC
    mov ecx, 225
    mov edi, OFFSET board
    xor eax, eax
clear_loop:
    stosd
    loop clear_loop
    ret
_ClearBoard ENDP

;----------------------------------------
; 画棋盘网格
;----------------------------------------
_DrawBoard PROC _hDC:DWORD
    LOCAL i:DWORD
    LOCAL y:DWORD
    LOCAL x:DWORD

    ;------ 画横线 -------
    mov i, 0

draw_rows:
    mov eax, i
    imul eax, GRID_SIZE
    add eax, BOARD_OFFSET
    mov y, eax               ; 存到变量，避免被覆盖

    invoke MoveToEx, _hDC, BOARD_OFFSET, y, NULL
    invoke LineTo,   _hDC, 450, y

    inc i
    cmp i, BOARD_COUNT
    jl draw_rows


    ;------ 画竖线 -------
    mov i, 0

draw_cols:
    mov eax, i
    imul eax, GRID_SIZE
    add eax, BOARD_OFFSET
    mov x, eax               ; 存变量

    invoke MoveToEx, _hDC, x, BOARD_OFFSET, NULL
    invoke LineTo,   _hDC, x, 450

    inc i
    cmp i, BOARD_COUNT
    jl draw_cols

    ret
_DrawBoard ENDP



;----------------------------------------
; 画棋子
;----------------------------------------
_DrawStones PROC _hDC:DWORD
    LOCAL idx:DWORD
    LOCAL row:DWORD
    LOCAL col:DWORD
    LOCAL x:DWORD
    LOCAL y:DWORD
    LOCAL hBrushBlack:DWORD
    LOCAL hBrushWhite:DWORD

    ; 获取画刷
    invoke GetStockObject, BLACK_BRUSH
    mov hBrushBlack, eax
    invoke GetStockObject, WHITE_BRUSH
    mov hBrushWhite, eax

    mov idx, 0

stone_loop:
    ; 取 board[idx]
    mov eax, idx
    imul eax, 4
    mov edx, OFFSET board
    add edx, eax
    mov eax, [edx]
    cmp eax, 0
    je next_stone           ; 空格跳过

    ; row = idx / 15, col = idx % 15
    mov eax, idx
    xor edx, edx
    mov ebx, 15
    div ebx                 ; eax=row, edx=col
    mov row, eax
    mov col, edx

    ; x = col*GRID_SIZE + BOARD_OFFSET - 10
    mov eax, col
    imul eax, GRID_SIZE
    add eax, BOARD_OFFSET
    sub eax, 10
    mov x, eax

    ; y = row*GRID_SIZE + BOARD_OFFSET - 10
    mov eax, row
    imul eax, GRID_SIZE
    add eax, BOARD_OFFSET
    sub eax, 10
    mov y, eax

    ; 选画刷
    mov eax, idx
    imul eax, 4
    mov edx, OFFSET board
    add edx, eax
    mov eax, [edx]
    cmp eax, 1
    jne use_white
    mov eax, hBrushBlack
    jmp sel_brush
use_white:
    mov eax, hBrushWhite
sel_brush:
    invoke SelectObject, _hDC, eax

    ; 画圆，右下角 = x+20, y+20
    mov eax, x
    add eax, 20
    mov ebx, y
    add ebx, 20
    invoke Ellipse, _hDC, x, y, eax, ebx

next_stone:
    mov eax, idx
    inc eax
    mov idx, eax
    cmp eax, 225
    jl stone_loop

    ret
_DrawStones ENDP

;----------------------------------------
; 鼠标点击 -> 落子
;----------------------------------------
_OnClick PROC xPos:DWORD, yPos:DWORD
    LOCAL col:DWORD
    LOCAL row:DWORD
    LOCAL idx:DWORD

    ; 计算列 col = (xPos - BOARD_OFFSET) / GRID_SIZE
    mov eax, xPos
    sub eax, BOARD_OFFSET
    cmp eax, 0
    jl done_click
	add eax, GRID_SIZE/2
    xor edx, edx
    mov ebx, GRID_SIZE
    div ebx
    mov col, eax

    ; 计算行 row = (yPos - BOARD_OFFSET) / GRID_SIZE
    mov eax, yPos
    sub eax, BOARD_OFFSET
    cmp eax, 0
    jl done_click
	add eax, GRID_SIZE/2
    xor edx, edx
    mov ebx, GRID_SIZE
    div ebx
    mov row, eax

    ; 边界检查
    mov eax, col
    cmp eax, 0
    jl done_click
    cmp eax, BOARD_COUNT-1
    jg done_click

    mov eax, row
    cmp eax, 0
    jl done_click
    cmp eax, BOARD_COUNT-1
    jg done_click

    ; idx = row*15 + col
    mov eax, row
    mov ebx, 15
    imul eax, ebx
    mov ebx, col
    add eax, ebx
    mov idx, eax

    ; 如果该格已经有棋子，退出
    mov ecx, idx
    imul ecx, 4
    mov edx, OFFSET board
    add edx, ecx
    mov eax, [edx]
    cmp eax, 0
    jne done_click

    ; 落子：board[idx] = currentPlayer
    mov eax, currentPlayer
    mov [edx], eax

    ; 切换当前玩家
    cmp currentPlayer, 1
    jne set_black
    mov currentPlayer, 2
    jmp done_click
set_black:
    mov currentPlayer, 1

done_click:
    ret
_OnClick ENDP

;----------------------------------------
; 窗口过程
;----------------------------------------
_ProcWinMain PROC hWnd:DWORD, uMsg:DWORD, wParam:DWORD, lParam:DWORD
    LOCAL ps:PAINTSTRUCT
    LOCAL hDC:DWORD
    LOCAL xPos:DWORD
    LOCAL yPos:DWORD

    ; 左键落子
    cmp uMsg, WM_LBUTTONDOWN
    jne chk_paint

    mov eax, lParam
    and eax, 0FFFFh
    mov xPos, eax
    mov eax, lParam
    shr eax, 16
    mov yPos, eax

    invoke _OnClick, xPos, yPos
    invoke InvalidateRect, hWnd, NULL, TRUE

    xor eax, eax
    ret

chk_paint:
    cmp uMsg, WM_PAINT
    jne chk_destroy

    invoke BeginPaint, hWnd, ADDR ps
    mov hDC, eax

    invoke _DrawBoard, hDC
    invoke _DrawStones, hDC

    invoke EndPaint, hWnd, ADDR ps

    xor eax, eax
    ret

chk_destroy:
    cmp uMsg, WM_DESTROY
    jne def_proc

    invoke PostQuitMessage, 0
    xor eax, eax
    ret

def_proc:
    invoke DefWindowProc, hWnd, uMsg, wParam, lParam
    ret
_ProcWinMain ENDP

;----------------------------------------
; WinMain
;----------------------------------------
_WinMain PROC
    LOCAL wc:WNDCLASSEX
    LOCAL msg:MSG

    invoke GetModuleHandle, NULL
    mov hInstance, eax

    ; 清空结构
    invoke RtlZeroMemory, ADDR wc, SIZEOF WNDCLASSEX

    ; 设置结构字段
    mov eax, SIZEOF WNDCLASSEX
    mov wc.cbSize, eax

    mov eax, CS_HREDRAW or CS_VREDRAW
    mov wc.style, eax

    mov eax, OFFSET _ProcWinMain
    mov wc.lpfnWndProc, eax

    mov wc.cbClsExtra, 0
    mov wc.cbWndExtra, 0

    mov eax, hInstance
    mov wc.hInstance, eax

    mov wc.hbrBackground, COLOR_WINDOW+1

    invoke LoadCursor, 0, IDC_ARROW
    mov wc.hCursor, eax

    mov eax, OFFSET szClassName
    mov wc.lpszClassName, eax

    mov wc.lpszMenuName, 0
    mov wc.hIcon, 0
    mov wc.hIconSm, 0

    ; 注册
    invoke RegisterClassEx, ADDR wc

    ; 创建窗口
    invoke CreateWindowEx, 0, \
           OFFSET szClassName, OFFSET szClassName, \
           WS_OVERLAPPEDWINDOW, \
           CW_USEDEFAULT, CW_USEDEFAULT, \
           600, 600, \
           NULL, NULL, hInstance, NULL

    mov hWinMain, eax

    invoke ShowWindow, hWinMain, SW_SHOWNORMAL
    invoke UpdateWindow, hWinMain

    invoke _ClearBoard


msg_loop:
    invoke GetMessage, ADDR msg, NULL, 0, 0
    test eax, eax
    jz end_loop
    invoke TranslateMessage, ADDR msg
    invoke DispatchMessage, ADDR msg
    jmp msg_loop

end_loop:
    ret
_WinMain ENDP

;----------------------------------------
; 程序入口
;----------------------------------------
main PROC
    call _WinMain
    invoke ExitProcess, 0
main ENDP

END main
