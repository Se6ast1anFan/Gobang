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

MODE_PVP        equ 0             ; 二人对弈
MODE_AI         equ 1             ; 对战电脑

BTN_PVP         equ 1001          ; “二人对弈”按钮ID
BTN_AI          equ 1002          ; “对战电脑”按钮ID

;----------------------------------------
.data
hInstance       dd ?
hWinMain        dd ?

currentPlayer   dd 1              ; 当前落子方：1=黑棋  2=白棋
gameMode        dd MODE_PVP       ; 0=二人对弈  1=对战电脑
gameOver        dd 0              ; 0=正常, 1=已结束

board           dd 225 dup(0)     ; 15*15 棋盘数组, 0=空 1=黑 2=白

szClassName     db "五子棋",0

; 按钮文字与类名
szButtonClass   db "BUTTON",0
szBtnPVPText    db "二人对弈",0
szBtnAIText     db "对战电脑",0

; 提示信息
msgPlayerWin    db "你赢了！",0
msgAIWin        db "电脑赢了！",0
msgTitle        db "游戏结束",0

msgBlackWin     db "黑棋赢了！",0
msgWhiteWin     db "白棋赢了！",0

;----------------------------------------
.code

_ComputerMoveSmart PROTO
_EvaluateMove      PROTO :DWORD, :DWORD
_CheckWin          PROTO :DWORD, :DWORD


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

    ; 如果游戏已结束，不能再落子
    mov eax, gameOver
    cmp eax, 1
    je done_click

    ; 计算列 col = (xPos - BOARD_OFFSET) / GRID_SIZE
    mov eax, xPos
    sub eax, BOARD_OFFSET
    cmp eax, 0
    jl done_click
    add eax, GRID_SIZE/2        ; 吸附到最近网格
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

    ;--------------------------------
    ; 玩家落子：board[idx] = currentPlayer
    ;--------------------------------
    mov eax, currentPlayer
    mov [edx], eax        ; edx 指向 board[idx]

    ;--------------------------------
    ; 根据模式分支
    ;--------------------------------
    mov eax, gameMode
    cmp eax, MODE_PVP
    je mode_pvp

    ;================================
    ;        模式：对战电脑
    ;================================
mode_ai:
    ; 玩家固定为黑棋(1)
    mov eax, idx
    invoke _CheckWin, eax, 1
    cmp eax, 1
    je player_win_ai

    ; 电脑落子：返回 aiIdx 或 0FFFFFFFFh
    invoke _ComputerMoveSmart
    cmp eax, 0FFFFFFFFh
    je after_ai_move

    ; eax = aiIdx，用于检查电脑是否获胜
    mov ecx, eax
    invoke _CheckWin, ecx, 2
    cmp eax, 1
    je ai_win

after_ai_move:
    invoke InvalidateRect, hWinMain, NULL, TRUE
    jmp done_click

player_win_ai:
    mov gameOver, 1
    invoke InvalidateRect, hWinMain, NULL, TRUE
    invoke MessageBoxA, NULL, ADDR msgPlayerWin, ADDR msgTitle, MB_OK
    jmp done_click

ai_win:
    mov gameOver, 1
    invoke InvalidateRect, hWinMain, NULL, TRUE
    invoke MessageBoxA, NULL, ADDR msgAIWin, ADDR msgTitle, MB_OK
    jmp done_click

    ;================================
    ;        模式：二人对弈
    ;================================
mode_pvp:
    ; 当前玩家刚刚在 idx 落子
    mov eax, idx
    mov ecx, currentPlayer
    invoke _CheckWin, eax, ecx
    cmp eax, 1
    je pvp_win

    ; 未分出胜负 -> 切换玩家
    cmp currentPlayer, 1
    jne set_black
    mov currentPlayer, 2
    jmp after_switch
set_black:
    mov currentPlayer, 1
after_switch:
    invoke InvalidateRect, hWinMain, NULL, TRUE
    jmp done_click

pvp_win:
    mov gameOver, 1
    invoke InvalidateRect, hWinMain, NULL, TRUE
    cmp currentPlayer, 1
    je msg_black
    invoke MessageBoxA, NULL, ADDR msgWhiteWin, ADDR msgTitle, MB_OK
    jmp done_click
msg_black:
    invoke MessageBoxA, NULL, ADDR msgBlackWin, ADDR msgTitle, MB_OK
    jmp done_click


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
    jne chk_command

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

chk_command:
    cmp uMsg, WM_COMMAND
    jne chk_paint

    ; 低位字是控件ID
    mov eax, wParam
    and eax, 0FFFFh
    cmp eax, BTN_PVP
    je cmd_pvp
    cmp eax, BTN_AI
    je cmd_ai
    jmp cmd_end

cmd_pvp:
    mov gameMode, MODE_PVP
    mov gameOver, 0
    mov currentPlayer, 1
    invoke _ClearBoard
    invoke InvalidateRect, hWnd, NULL, TRUE
    xor eax, eax
    ret

cmd_ai:
    mov gameMode, MODE_AI
    mov gameOver, 0
    mov currentPlayer, 1
    invoke _ClearBoard
    invoke InvalidateRect, hWnd, NULL, TRUE
    xor eax, eax
    ret

cmd_end:
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

    ; 创建主窗口
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

    ;--------------------------------
    ; 创建右侧两个按钮
    ;--------------------------------
    invoke CreateWindowEx, 0, \
           ADDR szButtonClass, ADDR szBtnPVPText, \
           WS_CHILD or WS_VISIBLE or BS_PUSHBUTTON, \
           460, 80, 100, 30, \
           hWinMain, BTN_PVP, hInstance, NULL

    invoke CreateWindowEx, 0, \
           ADDR szButtonClass, ADDR szBtnAIText, \
           WS_CHILD or WS_VISIBLE or BS_PUSHBUTTON, \
           460, 130, 100, 30, \
           hWinMain, BTN_AI, hInstance, NULL


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

;=========================================
; 智能电脑落子：综合进攻 + 防守评分
; 返回：eax = 电脑落子位置 idx，或 0FFFFFFFFh 表示没落子
;=========================================
_ComputerMoveSmart PROC uses esi edi ebx
    LOCAL idx:DWORD
    LOCAL bestIdx:DWORD
    LOCAL bestScore:DWORD
    LOCAL attack:DWORD
    LOCAL defense:DWORD
    LOCAL temp:DWORD

    mov bestIdx, 0FFFFFFFFh
    mov bestScore, 0          ; 初始评分为0

    mov idx, 0

check_loop:
    cmp idx, 225
    jge choose_done

    ; 如果 board[idx] != 0，跳过
    mov eax, idx
    imul eax, 4
    mov edx, OFFSET board
    add edx, eax
    mov eax, [edx]
    cmp eax, 0
    jne next_idx

    ; attack = 电脑在此落子（白棋=2）的分
    mov eax, idx
    invoke _EvaluateMove, eax, 2
    mov attack, eax

    ; defense = 玩家在此落子（黑棋=1）的分
    mov eax, idx
    invoke _EvaluateMove, eax, 1
    mov defense, eax

    ; temp = attack*2 + defense*3
    mov eax, attack
    lea eax, [eax*2]          ; eax = attack * 2
    mov temp, eax

    mov eax, defense
    imul eax, 3               ; eax = defense * 3
    add temp, eax             ; temp = 2A + 3D

    ; 如果 temp > bestScore，就更新
    mov eax, temp
    cmp eax, bestScore
    jle next_idx

    mov bestScore, eax
    mov eax, idx
    mov bestIdx, eax

next_idx:
    mov eax, idx
    inc eax
    mov idx, eax
    jmp check_loop

choose_done:
    mov eax, bestIdx
    cmp eax, 0FFFFFFFFh
    je no_move

    ; board[bestIdx] = 2 (白棋)
    mov edx, eax          ; edx = bestIdx
    imul edx, 4
    mov ecx, OFFSET board
    add ecx, edx
    mov dword ptr [ecx], 2

    ; 返回 bestIdx
    ret

no_move:
    mov eax, 0FFFFFFFFh
    ret
_ComputerMoveSmart ENDP

;=========================================
; 评分函数：_EvaluateMove(idx, color)
; 返回：eax = 此位置对该 color 的价值
;=========================================
_EvaluateMove PROC uses esi edi ebx, idx:DWORD, color:DWORD
    LOCAL row:DWORD
    LOCAL col:DWORD
    LOCAL total:DWORD
    LOCAL len:DWORD
    LOCAL r:DWORD
    LOCAL colTmp:DWORD
    LOCAL scoreDir:DWORD

    ; 计算 row = idx / 15, col = idx % 15
    mov eax, idx
    xor edx, edx
    mov ebx, 15
    div ebx             ; eax=row, edx=col
    mov row, eax
    mov col, edx

    mov total, 0

    ;------------------ 水平方向 ------------------
    mov len, 1          ; 把当前位置当作已落子

    ; 向左
    mov eax, col
    dec eax
    mov colTmp, eax

h_left:
    mov eax, colTmp
    cmp eax, 0
    jl h_left_done

    mov edx, row
    mov ebx, 15
    imul edx, ebx
    add edx, colTmp

    mov esi, OFFSET board
    mov ebx, edx
    imul ebx, 4
    add esi, ebx
    mov eax, [esi]
    cmp eax, color
    jne h_left_done

    inc len
    dec colTmp
    jmp h_left

h_left_done:

    ; 向右
    mov eax, col
    inc eax
    mov colTmp, eax

h_right:
    mov eax, colTmp
    cmp eax, 14
    jg h_right_done

    mov edx, row
    mov ebx, 15
    imul edx, ebx
    add edx, colTmp

    mov esi, OFFSET board
    mov ebx, edx
    imul ebx, 4
    add esi, ebx
    mov eax, [esi]
    cmp eax, color
    jne h_right_done

    inc len
    inc colTmp
    jmp h_right

h_right_done:

    ; 根据 len 加分
    mov scoreDir, 0
    mov eax, len
    cmp eax, 5
    jl  h_len_not5
    mov scoreDir, 10000
    jmp h_score_done
h_len_not5:
    cmp eax, 4
    jne h_len_not4
    mov scoreDir, 1000
    jmp h_score_done
h_len_not4:
    cmp eax, 3
    jne h_len_not3
    mov scoreDir, 100
    jmp h_score_done
h_len_not3:
    cmp eax, 2
    jne h_score_done
    mov scoreDir, 10
h_score_done:
    mov eax, total
    add eax, scoreDir
    mov total, eax

    ;------------------ 垂直方向 ------------------
    mov len, 1

    ; 向上（row-1）
    mov eax, row
    dec eax
    mov r, eax

v_up:
    mov eax, r
    cmp eax, 0
    jl v_up_done

    mov edx, eax
    mov ebx, 15
    imul edx, ebx
    add edx, col

    mov esi, OFFSET board
    mov ebx, edx
    imul ebx, 4
    add esi, ebx
    mov eax, [esi]
    cmp eax, color
    jne v_up_done

    inc len
    dec r
    jmp v_up

v_up_done:

    ; 向下（row+1）
    mov eax, row
    inc eax
    mov r, eax

v_down:
    mov eax, r
    cmp eax, 14
    jg v_down_done

    mov edx, eax
    mov ebx, 15
    imul edx, ebx
    add edx, col

    mov esi, OFFSET board
    mov ebx, edx
    imul ebx, 4
    add esi, ebx
    mov eax, [esi]
    cmp eax, color
    jne v_down_done

    inc len
    inc r
    jmp v_down

v_down_done:

    mov scoreDir, 0
    mov eax, len
    cmp eax, 5
    jl  v_len_not5
    mov scoreDir, 10000
    jmp v_score_done
v_len_not5:
    cmp eax, 4
    jne v_len_not4
    mov scoreDir, 1000
    jmp v_score_done
v_len_not4:
    cmp eax, 3
    jne v_len_not3
    mov scoreDir, 100
    jmp v_score_done
v_len_not3:
    cmp eax, 2
    jne v_score_done
    mov scoreDir, 10
v_score_done:
    mov eax, total
    add eax, scoreDir
    mov total, eax

    ;------------------ 斜线方向1 (\) ------------------
    mov len, 1

    ; 左上 (row-1, col-1)
    mov eax, row
    dec eax
    mov r, eax
    mov eax, col
    dec eax
    mov colTmp, eax

d1_up_left:
    mov eax, r
    cmp eax, 0
    jl d1_up_left_done
    mov eax, colTmp
    cmp eax, 0
    jl d1_up_left_done

    mov edx, r
    mov ebx, 15
    imul edx, ebx
    add edx, colTmp

    mov esi, OFFSET board
    mov ebx, edx
    imul ebx, 4
    add esi, ebx
    mov eax, [esi]
    cmp eax, color
    jne d1_up_left_done

    inc len
    dec r
    dec colTmp
    jmp d1_up_left

d1_up_left_done:

    ; 右下 (row+1, col+1)
    mov eax, row
    inc eax
    mov r, eax
    mov eax, col
    inc eax
    mov colTmp, eax

d1_down_right:
    mov eax, r
    cmp eax, 14
    jg d1_down_right_done
    mov eax, colTmp
    cmp eax, 14
    jg d1_down_right_done

    mov edx, r
    mov ebx, 15
    imul edx, ebx
    add edx, colTmp

    mov esi, OFFSET board
    mov ebx, edx
    imul ebx, 4
    add esi, ebx
    mov eax, [esi]
    cmp eax, color
    jne d1_down_right_done

    inc len
    inc r
    inc colTmp
    jmp d1_down_right

d1_down_right_done:

    mov scoreDir, 0
    mov eax, len
    cmp eax, 5
    jl  d1_len_not5
    mov scoreDir, 10000
    jmp d1_score_done
d1_len_not5:
    cmp eax, 4
    jne d1_len_not4
    mov scoreDir, 1000
    jmp d1_score_done
d1_len_not4:
    cmp eax, 3
    jne d1_len_not3
    mov scoreDir, 100
    jmp d1_score_done
d1_len_not3:
    cmp eax, 2
    jne d1_score_done
    mov scoreDir, 10
d1_score_done:
    mov eax, total
    add eax, scoreDir
    mov total, eax

    ;------------------ 斜线方向2 (/) ------------------
    mov len, 1

    ; 左下 (row+1, col-1)
    mov eax, row
    inc eax
    mov r, eax
    mov eax, col
    dec eax
    mov colTmp, eax

d2_down_left:
    mov eax, r
    cmp eax, 14
    jg d2_down_left_done
    mov eax, colTmp
    cmp eax, 0
    jl d2_down_left_done

    mov edx, r
    mov ebx, 15
    imul edx, ebx
    add edx, colTmp

    mov esi, OFFSET board
    mov ebx, edx
    imul ebx, 4
    add esi, ebx
    mov eax, [esi]
    cmp eax, color
    jne d2_down_left_done

    inc len
    inc r
    dec colTmp
    jmp d2_down_left

d2_down_left_done:

    ; 右上 (row-1, col+1)
    mov eax, row
    dec eax
    mov r, eax
    mov eax, col
    inc eax
    mov colTmp, eax

d2_up_right:
    mov eax, r
    cmp eax, 0
    jl d2_up_right_done
    mov eax, colTmp
    cmp eax, 14
    jg d2_up_right_done

    mov edx, r
    mov ebx, 15
    imul edx, ebx
    add edx, colTmp

    mov esi, OFFSET board
    mov ebx, edx
    imul ebx, 4
    add esi, ebx
    mov eax, [esi]
    cmp eax, color
    jne d2_up_right_done

    inc len
    dec r
    inc colTmp
    jmp d2_up_right

d2_up_right_done:

    mov scoreDir, 0
    mov eax, len
    cmp eax, 5
    jl  d2_len_not5
    mov scoreDir, 10000
    jmp d2_score_done
d2_len_not5:
    cmp eax, 4
    jne d2_len_not4
    mov scoreDir, 1000
    jmp d2_score_done
d2_len_not4:
    cmp eax, 3
    jne d2_len_not3
    mov scoreDir, 100
    jmp d2_score_done
d2_len_not3:
    cmp eax, 2
    jne d2_score_done
    mov scoreDir, 10
d2_score_done:
    mov eax, total
    add eax, scoreDir
    mov total, eax

    ; 返回总分
    mov eax, total
    ret
_EvaluateMove ENDP

;=========================================
; _CheckWin(idx, color)
; 返回：
;   eax = 1  -> 五子连线
;   eax = 0  -> 未胜利
;=========================================
_CheckWin PROC uses esi edi ebx edx, idx:DWORD, color:DWORD
    LOCAL row:DWORD
    LOCAL col:DWORD
    LOCAL count:DWORD
    LOCAL rTemp:DWORD
    LOCAL colTemp:DWORD

    ;--- 计算 row 和 col ---
    mov eax, idx
    xor edx, edx
    mov ebx, 15
    div ebx             ; eax=row, edx=col
    mov row, eax
    mov col, edx

    ;=========================================
    ; 水平检查 (← →)
    ;=========================================
    mov count, 1

    ; 向左
    mov eax, col
    dec eax
    mov colTemp, eax

h2_left:
    mov eax, colTemp
    cmp eax, 0
    jl h2_left_end

    mov edx, row
    mov ebx, 15
    imul edx, ebx
    add edx, colTemp

    mov esi, OFFSET board
    mov ebx, edx
    imul ebx, 4
    add esi, ebx

    mov eax, [esi]
    cmp eax, color
    jne h2_left_end

    inc count
    dec colTemp
    jmp h2_left

h2_left_end:

    ; 向右
    mov eax, col
    inc eax
    mov colTemp, eax

h2_right:
    mov eax, colTemp
    cmp eax, 14
    jg h2_right_end

    mov edx, row
    mov ebx, 15
    imul edx, ebx
    add edx, colTemp

    mov esi, OFFSET board
    mov ebx, edx
    imul ebx, 4
    add esi, ebx

    mov eax, [esi]
    cmp eax, color
    jne h2_right_end

    inc count
    inc colTemp
    jmp h2_right

h2_right_end:

    cmp count, 5
    jge win_found


    ;=========================================
    ; 垂直检查 (↑ ↓)
    ;=========================================
    mov count, 1

    ; 向上
    mov eax, row
    dec eax
    mov rTemp, eax

v2_up:
    mov eax, rTemp
    cmp eax, 0
    jl v2_up_end

    mov edx, rTemp
    mov ebx, 15
    imul edx, ebx
    add edx, col

    mov esi, OFFSET board
    mov ebx, edx
    imul ebx, 4
    add esi, ebx

    mov eax, [esi]
    cmp eax, color
    jne v2_up_end

    inc count
    dec rTemp
    jmp v2_up

v2_up_end:

    ; 向下
    mov eax, row
    inc eax
    mov rTemp, eax

v2_down:
    mov eax, rTemp
    cmp eax, 14
    jg v2_down_end

    mov edx, rTemp
    mov ebx, 15
    imul edx, ebx
    add edx, col

    mov esi, OFFSET board
    mov ebx, edx
    imul ebx, 4
    add esi, ebx

    mov eax, [esi]
    cmp eax, color
    jne v2_down_end

    inc count
    inc rTemp
    jmp v2_down

v2_down_end:

    cmp count, 5
    jge win_found


    ;=========================================
    ; 主对角线检查 (\)
    ;=========================================
    mov count, 1

    ; 左上
    mov eax, row
    dec eax
    mov rTemp, eax
    mov eax, col
    dec eax
    mov colTemp, eax

d1_2_up_left:
    mov eax, rTemp
    cmp eax, 0
    jl d1_2_up_left_end
    mov eax, colTemp
    cmp eax, 0
    jl d1_2_up_left_end

    mov edx, rTemp
    mov ebx, 15
    imul edx, ebx
    add edx, colTemp

    mov esi, OFFSET board
    mov ebx, edx
    imul ebx, 4
    add esi, ebx

    mov eax, [esi]
    cmp eax, color
    jne d1_2_up_left_end

    inc count
    dec rTemp
    dec colTemp
    jmp d1_2_up_left

d1_2_up_left_end:

    ; 右下
    mov eax, row
    inc eax
    mov rTemp, eax
    mov eax, col
    inc eax
    mov colTemp, eax

d1_2_down_right:
    mov eax, rTemp
    cmp eax, 14
    jg d1_2_down_right_end
    mov eax, colTemp
    cmp eax, 14
    jg d1_2_down_right_end

    mov edx, rTemp
    mov ebx, 15
    imul edx, ebx
    add edx, colTemp

    mov esi, OFFSET board
    mov ebx, edx
    imul ebx, 4
    add esi, ebx

    mov eax, [esi]
    cmp eax, color
    jne d1_2_down_right_end

    inc count
    inc rTemp
    inc colTemp
    jmp d1_2_down_right

d1_2_down_right_end:

    cmp count, 5
    jge win_found


    ;=========================================
    ; 副对角线检查 (/)
    ;=========================================
    mov count, 1

    ; 左下
    mov eax, row
    inc eax
    mov rTemp, eax
    mov eax, col
    dec eax
    mov colTemp, eax

d2_2_down_left:
    mov eax, rTemp
    cmp eax, 14
    jg d2_2_down_left_end
    mov eax, colTemp
    cmp eax, 0
    jl d2_2_down_left_end

    mov edx, rTemp
    mov ebx, 15
    imul edx, ebx
    add edx, colTemp

    mov esi, OFFSET board
    mov ebx, edx
    imul ebx, 4
    add esi, ebx

    mov eax, [esi]
    cmp eax, color
    jne d2_2_down_left_end

    inc count
    inc rTemp
    dec colTemp
    jmp d2_2_down_left

d2_2_down_left_end:

    ; 右上
    mov eax, row
    dec eax
    mov rTemp, eax
    mov eax, col
    inc eax
    mov colTemp, eax

d2_2_up_right:
    mov eax, rTemp
    cmp eax, 0
    jl d2_2_up_right_end
    mov eax, colTemp
    cmp eax, 14
    jg d2_2_up_right_end

    mov edx, rTemp
    mov ebx, 15
    imul edx, ebx
    add edx, colTemp

    mov esi, OFFSET board
    mov ebx, edx
    imul ebx, 4
    add esi, ebx

    mov eax, [esi]
    cmp eax, color
    jne d2_2_up_right_end

    inc count
    dec rTemp
    inc colTemp
    jmp d2_2_up_right

d2_2_up_right_end:

    cmp count, 5
    jge win_found

    ; 没赢
    xor eax, eax
    ret

win_found:
    mov eax, 1
    ret

_CheckWin ENDP

;----------------------------------------
; 程序入口
;----------------------------------------
main PROC
    call _WinMain
    invoke ExitProcess, 0
main ENDP

END main
