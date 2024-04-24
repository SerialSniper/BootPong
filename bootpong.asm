[org 0x7c00]

jmp loader
times 0x3E db 0 ; bpb workaround

loader:
xor ax, ax
mov es, ax
mov bx, 0x7e00

mov ah, 2
mov al, 5 ; sector count
mov ch, 0 ; cylinder
mov cl, 2 ; sector
mov dh, 0 ; head
; dl = disk (already there)
int 13h

jmp code

times 510-($-$$) db 0
dw 0xAA55

%define PADDLE_WIDTH       10
%define PADDLE_HEIGHT      50
%define PADDLE_MARGIN      25
%define BALL_SIZE          8
%define BALL_SPEED         2

%define SCORE_Y            3
%define LEFT_SCORE_X       19 - 3
%define RIGHT_SCORE_X      20 + 3

%define SCREEN_WIDTH       320
%define SCREEN_HEIGHT      200
%define BACKBUFFER         0x9000

left_paddle:
dw (PADDLE_MARGIN - PADDLE_WIDTH / 2) * 128                 ; 128 * x
dw (SCREEN_HEIGHT / 2 - PADDLE_HEIGHT / 2) * 128            ; 128 * y
dw PADDLE_WIDTH                                             ; width
dw PADDLE_HEIGHT                                            ; height
dw 0                                                        ; y speed

right_paddle:
dw (SCREEN_WIDTH - PADDLE_MARGIN - PADDLE_WIDTH / 2) * 128  ; 128 * x
dw (SCREEN_HEIGHT / 2 - PADDLE_HEIGHT / 2) * 128            ; 128 * y
dw PADDLE_WIDTH                                             ; width
dw PADDLE_HEIGHT                                            ; height
dw 0                                                        ; y speed

ball:
dw (SCREEN_WIDTH / 2 - BALL_SIZE / 2) * 128                 ; 128 * x
dw (SCREEN_HEIGHT / 2 - BALL_SIZE / 2) * 128                ; 128 * y
dw BALL_SIZE                                                ; width
dw BALL_SIZE                                                ; height
dw 0                                                        ; x speed
dw 0                                                        ; y speed

initialized:        db 0
loop_clearance:     db 0

left_score:         db 0
right_score:        db 0
left_score_str:     dd 0
right_score_str:    dd 0
serve_right:        db 0xFF

ball_is_in:         db 0
ball_was_in:        db 0

code:

; initialize ds and es
xor ax, ax
mov ds, ax
mov es, ax

; 320x200
mov ax, 0x0013
int 10h

cli
xor ax, ax
mov ds, ax
; hook pit_isr to IRQ1
mov [ds:0x20], word pit_isr
mov [ds:0x22], word ax
; hook kb_handler to IRQ2
mov [ds:0x24], word kb_handler
mov [ds:0x26], word ax
sti

; PIT setup
mov al, 00110100b
out 0x43, al
mov ax, 19886 ; 60Hz (1193182 / 60)
out 0x40, al
mov al, ah
out 0x40, al

jmp game_loop
jmp $

pit_isr:
    push ax
        mov [loop_clearance], byte 1
        ; acknowledge interrupt
        mov al, 0x20
        out 0x20, al
    pop ax
    iret

game_loop:
    cmp [loop_clearance], byte 0
        je game_loop
    mov [loop_clearance], byte 0

    cli
    call tick
    call render
    sti

    jmp game_loop

tick:
    mov bx, left_paddle
    call tick_paddle
    mov bx, right_paddle
    call tick_paddle

    call tick_ball
    call tick_score
    
    mov al, [left_score]
    mov bx, left_score_str
    call score_to_str
    
    mov al, [right_score]
    mov bx, right_score_str
    call score_to_str

    ret

; bx = paddle pointer
tick_paddle:
    mov ax, [bx + 2]
    add ax, [bx + 8]
    mov [bx + 2], ax

    cmp ax, 0
        jnl top_collision_end
        mov [bx + 2], word 0
    top_collision_end:
    
    cmp ax, (SCREEN_HEIGHT - PADDLE_HEIGHT) * 128
        jng bottom_collision_end
        mov [bx + 2], word (SCREEN_HEIGHT - PADDLE_HEIGHT) * 128
    bottom_collision_end:
    ret

tick_ball:
    mov [ball_is_in], byte 0

    mov ax, [ball + 2]
    add ax, [ball + 10]

    cmp ax, 0
        jle tick_ball_wall_bounce
    cmp ax, (SCREEN_HEIGHT - BALL_SIZE) * 128
        jge tick_ball_wall_bounce
    jmp tick_ball_wall_bounce_else
    tick_ball_wall_bounce:
        neg word [ball + 10]
        jmp tick_ball_wall_bounce_end
    tick_ball_wall_bounce_else:
        mov [ball + 2], ax
    tick_ball_wall_bounce_end:

    mov ax, [ball]
    add ax, [ball + 8]
    mov [ball], ax

    cmp ax, word (PADDLE_MARGIN + PADDLE_WIDTH / 2) * 128
        jbe ball_left_paddle_bounce
    cmp ax, word (SCREEN_WIDTH - PADDLE_MARGIN - PADDLE_WIDTH / 2 - BALL_SIZE) * 128
        jae ball_right_paddle_bounce
    mov [ball_is_in], byte 0xFF
    jmp ball_paddle_bounce_end
    ball_left_paddle_bounce:
        mov ax, [ball + 2]
        sub ax, [left_paddle + 2]
        cmp ax, PADDLE_HEIGHT * 128
            ja ball_paddle_bounce_end
        mov al, [ball_was_in]
        cmp al, 0
            jz ball_paddle_bounce_end
        mov bx, left_paddle
        call redirect_ball
        jmp ball_paddle_bounce_end
    ball_right_paddle_bounce:
        mov ax, [ball + 2]
        sub ax, [right_paddle + 2]
        sub ax, BALL_SIZE
        cmp ax, PADDLE_HEIGHT * 128 + BALL_SIZE
            ja ball_paddle_bounce_end
        mov al, [ball_was_in]
        cmp al, 0
            jz ball_paddle_bounce_end
        mov bx, right_paddle
        call redirect_ball
        neg word [ball + 8]
    ball_paddle_bounce_end:

    mov al, [ball_is_in]
    mov [ball_was_in], al
    ret

tick_score:
    mov ax, [ball]
    sar ax, 7

    cmp ax, word 0
        jnle tick_score_score_right_check_end
    cmp ax, word -50
        jge tick_score_score_right
    tick_score_score_right_check_end:
    mov ax, [ball]
    shr ax, 7
    cmp ax, word SCREEN_WIDTH - BALL_SIZE
        jnge tick_score_end
    cmp ax, word SCREEN_WIDTH - BALL_SIZE + 50
        jle tick_score_score_left
    jmp tick_score_end
    tick_score_score_left:
        inc byte [left_score]
        mov [serve_right], byte 0
        jmp tick_score_score
    tick_score_score_right:
        inc byte [right_score]
        mov [serve_right], byte 0xFF
    tick_score_score:
        mov [initialized], byte 0
        mov [left_paddle + 2], word (100 - PADDLE_HEIGHT / 2) * 128
        mov [right_paddle + 2], word (100 - PADDLE_HEIGHT / 2) * 128
        mov [ball], word (160 - BALL_SIZE / 2) * 128
        mov [ball + 2], word (100 - BALL_SIZE / 2) * 128
        mov [ball + 8], dword 0
        mov [left_paddle + 8], word 0
        mov [right_paddle + 8], word 0
    tick_score_end:
    ret

; bx = paddle pointer
redirect_ball:
    ; ball y pos relative to the paddle
    mov ax, [ball + 2]
    shr ax, 7
    add ax, BALL_SIZE / 2
    mov bx, [bx + 2]
    shr bx, 7
    add bx, PADDLE_HEIGHT / 2
    sub ax, bx

    shl ax, 1 ; / 2
    call orient_ball_deg
    ret

; ax = angle
orient_ball_deg:
    fninit
    push ax
    fild word [esp]
    pop ax
    push 180
    fidiv word [esp]
    pop ax
    fldpi
    fmul st1, st0
    fstp st0
    fsincos
    push 128 * BALL_SPEED
    fimul word [esp]
    fistp word [ball + 8]
    fimul word [esp]
    fistp word [ball + 10]
    pop ax
    ret

; al = score
; bx = score str pointer
score_to_str:
    mov cx, 4 ; max 4 digits
    add bx, 3
    score_to_str_loop:
        cbw
        mov dl, 10
        div dl
        add ah, '0'
        mov [bx], ah
        dec bx
        loop score_to_str_loop
    ret

render:
    call clear_fb
    call render_net

    mov bp, left_paddle
    call fill_quad
    mov bp, right_paddle
    call fill_quad
    mov bp, ball
    call fill_quad
    
    ; copy fb stage 1
    ; for 4 char lines
    mov ax, BACKBUFFER
    mov ds, ax
    xor si, si
    mov ax, 0xA000
    mov es, ax
    xor di, di
    mov cx, SCREEN_WIDTH * 8 * 4 / 2
    rep movsw
    xor ax, ax
    mov ds, ax

    mov dl, LEFT_SCORE_X
    mov bp, left_score_str
    mov di, 0xFF
    call render_score

    mov dl, RIGHT_SCORE_X
    mov bp, right_score_str
    xor di, di
    call render_score
    
    ; copy fb stage 2
    ; remaining lines
    mov ax, BACKBUFFER
    mov ds, ax
    mov si, SCREEN_WIDTH * 8 * 4
    mov ax, 0xA000
    mov es, ax
    mov di, SCREEN_WIDTH * 8 * 4
    mov cx, SCREEN_WIDTH * SCREEN_HEIGHT / 2 - SCREEN_WIDTH * 8 * 4 / 2
    rep movsw
    xor ax, ax
    mov ds, ax

    ret

clear_fb:
    mov ax, BACKBUFFER
    mov es, ax
    xor ax, ax
    xor di, di
    mov cx, SCREEN_WIDTH * SCREEN_HEIGHT / 2
    rep stosw
    ret

render_net:
    mov ax, BACKBUFFER
    mov es, ax
    mov di, 159
    mov cx, SCREEN_HEIGHT
    render_net_loop:
        mov ax, cx
        and ax, 8
        cmp ax, 0
            jne render_net_loop_continue
        mov [es:di], word 0x1717
        render_net_loop_continue:
        add di, SCREEN_WIDTH
        loop render_net_loop
    ret

; bp = drawable object pointer
fill_quad:
    ; linearize
    mov ax, [bp + 2]
    mov bx, [bp]
    shr ax, 7
    shr bx, 7
    mov cx, SCREEN_WIDTH
    mul cx
    add ax, bx
    mov di, ax

    mov ax, BACKBUFFER
    mov es, ax
    mov al, 15

    mov si, [bp + 6]
    fill_quad_loop:
        mov cx, [bp + 4]
        rep stosb
        add di, SCREEN_WIDTH
        sub di, [bp + 4]
        dec si
        jnz fill_quad_loop
    ret

; dl = x coordinate
; bp = score pointer
; di = (bool) is left
render_score:
    ; find first digit to print correctly
    dec bp
    mov cx, 4
    render_score_find_first_digit_loop:
        inc bp
        mov al, [bp]
        cmp al, '0'
            loope render_score_find_first_digit_loop
    
    ; adjust x for left side (right align)
    cmp di, 0
        je render_score_left_adjust_end
    sub dl, cl
    render_score_left_adjust_end:

    mov ax, 0x1300
    mov bx, 0x000F
    inc cx
    mov dh, SCORE_Y
    xor si, si
    mov es, si
    int 10h
    ret

kb_handler:
    pusha

    in al, 0x60

    ; data without status bit
    mov bl, al
    and bl, 0x7F

    ; status bit 7 (inverted) to bool
    sar al, 7
    not al
    
    cmp al, 0
        jz kb_handler_release

        cmp bl, 0x11
            jne w_handler_end
            mov [left_paddle + 8], word -3 * 128
        w_handler_end:
        cmp bl, 0x1F
            jne s_handler_end
            mov [left_paddle + 8], word 3 * 128
        s_handler_end:
        cmp bl, 0x17
            jne i_handler_end
            mov [right_paddle + 8], word -3 * 128
        i_handler_end:
        cmp bl, 0x25
            jne k_handler_end
            mov [right_paddle + 8], word 3 * 128
        k_handler_end:
        
    jmp kb_handler_end
    kb_handler_release:
    
        cmp bl, 0x11
            jne w_release_handler_end
            mov [left_paddle + 8], word 0
        w_release_handler_end:
        cmp bl, 0x1F
            jne s_release_handler_end
            mov [left_paddle + 8], word 0
        s_release_handler_end:
        cmp bl, 0x17
            jne i_release_handler_end
            mov [right_paddle + 8], word 0
        i_release_handler_end:
        cmp bl, 0x25
            jne k_release_handler_end
            mov [right_paddle + 8], word 0
        k_release_handler_end:
        
    kb_handler_end:

    call init

    ; acknowledge interrupt
    mov al, 0x20
    out 0x20, al

    popa
    iret

init:
    mov al, byte [initialized]
    cmp al, 0
        jnz init_end

    ; read PIT
    in al, 0x40
    mov dl, al
    in al, 0x40
    mov dh, al

    ; clamp to -64; +64
    sal dx, 9
    sar dx, 9
    mov ax, dx
    call orient_ball_deg

    mov ax, [serve_right]
    cmp ax, 0
        jne init_ball_serve_reverse_end
        neg word [ball + 8]
    init_ball_serve_reverse_end:

    mov [initialized], byte 0xFF

    init_end:
    ret

times 1474560-($-$$) db 0