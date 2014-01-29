; epoll.asm
;
; Copyright (c) 2014 Simon Feltman
;
; Assembly language demo of using linux epoll on x86-64. This makes use of
; epoll to wait for input from stdin and echos it to the screen when available.
;
; This program is free software: you can redistribute it and/or modify
; it under the terms of the GNU General Public License as published by
; the Free Software Foundation, either version 3 of the License, or
; (at your option) any later version.
;
; This program is distributed in the hope that it will be useful,
; but WITHOUT ANY WARRANTY; without even the implied warranty of
; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
; GNU General Public License for more details.
;
; You should have received a copy of the GNU General Public License
; along with this program.  If not, see <http://www.gnu.org/licenses/>.


; Notes:
; x86-64 C calling convention arg registers:
;   cdecl 64: RDI, RSI, RDX, RCX, R8, R9, XMM0–7
;   syscalls: RDI, RSI, RDX, R10, R8, R9, XMM0–7 (destroys rcx and r11)
; Parameter order on stack: RTL (C)
; Stack cleanup by: Caller


[bits 64]

%define stdin  0
%define stdout 1
%define stderr 2

%define sys_read          0
%define sys_write         1
%define sys_exit          60
%define sys_epoll_create  213
%define sys_epoll_wait    232
%define sys_epoll_ctl     233

%define EPOLLIN  0x001
%define EPOLLPRI 0x002
%define EPOLLOUT 0x004

%define EPOLL_CTL_ADD 1 ; /* Add a file decriptor to the interface.  */
%define EPOLL_CTL_DEL 2 ; /* Remove a file decriptor from the interface.  */
%define EPOLL_CTL_MOD 3 ; /* Change file decriptor epoll_event structure.  */


struc epoll_event
  .events:    resd  1    ; uint32
  .data:      resq  1    ; uint64
  .struc_size:
endstruc

struc epoll_event_fd
  .events:    resd  1    ; uint32
  .fd:        resd  1    ; int32
  .pad:       resd  1    ; uint32
  .struc_size:
endstruc


section .data
  hello:       db 'Welcome to the echo console, use Ctrl+C to exit',10,0
  hello_len:   equ $-hello

  prompt:      db '>>> ',0
  prompt_len:  equ $-prompt

  main_error_msg:        db 'error: epoll_wait failed',10,0
  unknown_fd_error_msg:  db 'error: unknown file descriptor in epoll',10,0
  epoll_ctl_error:       db 'error: with epoll_ctl for stdin',10,0

  stdin_event: istruc epoll_event_fd
    at epoll_event_fd.events, dd EPOLLIN
    AT epoll_event_fd.fd, dd stdin
  iend

segment .bss
  the_epoll_fd:     resq 1

  the_events:       resb epoll_event.struc_size * 5    ; reserve place for 5 structures
  the_events_len:   equ ($ - the_events) / epoll_event.struc_size

  buffer:           resb 1024
  buffer_len:       equ $-buffer


section .text
  global _start


; write(long fd, char *buf, int len)
write:
  ; fd:rdi, str:rsi, and len:rdx passthrough to the syscall
  mov rax, sys_write   ; The system call for write (sys_write)
  syscall              ; Call the kernel
  ret
; end print


; int read(long fd, char *buf, int max)
read:
  ; fd:rdi, str:rsi, and len:rdx passthrough to the syscall
  mov rax, sys_read    ; The system call for write (sys_write)
  syscall              ; Call the kernel
  ret
; end print


; long epoll_create(int size)
epoll_create:
  mov rax, sys_epoll_create
  syscall
  ret


; long epoll_wait(int epfd, struct epoll_event *events, int maxevents, int timeout)
;                     rdi,                      rsi,        rdx,           r10
epoll_wait:
  mov rax, sys_epoll_wait
  syscall
  ret


; long epoll_ctl(int epfd, int op, int fd, struct epoll_event *event)
epoll_ctl:
  mov rax, sys_epoll_ctl
  syscall
  ret


; long strlen(char *str)
; http://www.int80h.org/strlen/
strlen:
  ; str:rdi passes through to scasb
  sub rcx, rcx         ; rcx = 0
  not rcx              ; rcx = 2^64 (-1) (count used in repne)
  sub al, al           ; al = 0
  cld                  ; clear the direction flag, causes repne to go up in direction
  repne scasb          ; repeatedly decrement rcx until byte (from string in rdi) is not equal to al (0)
  not rcx              ; absolute value of rcx
  dec rcx              ; get rid of initial -1
  mov rax, rcx         ; setup return in rax
  ret
; end strlen


; print(char *str)
print:
  ; str already in rdi for strlen call
  mov rsi, rdi         ; move str to rsi
  call strlen
  mov rdx, rax         ; move length of string into rdx for write
  mov rdi, stdout      ; File descriptor 1 - standard output
  call write
  ret
; end print


; error(char *str)
error:
  ; str already in rdi for strlen call
  mov rsi, rdi         ; move str to rsi
  call strlen
  mov rdx, rax         ; move length of string into rdx for write
  mov rdi, stderr      ; File descriptor 1 - standard output
  call write

  mov rdi, 1           ; Exit with return code of 1
  mov rax, sys_exit
  syscall

  ret
; end error


_start:
  mov rdi, hello       ; Put the offset of hello in rsi
  call print

  mov rdi, 1
  call epoll_create
  mov [the_epoll_fd], rax

  mov rdi, [the_epoll_fd]
  mov rsi, EPOLL_CTL_ADD
  mov rdx, stdin
  mov r10, stdin_event
  call epoll_ctl

  cmp rax, 0
  je main_loop            ; jump to the main_loop if epoll_ctl returned success
  mov rdi, epoll_ctl_error
  call error

  main_loop:
    mov rdi, prompt
    call print

    mov rdi, [the_epoll_fd]
    mov rsi, the_events
    mov rdx, the_events_len
    mov r10, -1
    call epoll_wait

    mov r15, rax  ; keep event count in r15
    cmp r15, -1
    je main_error

    for_each_event:
      cmp r15, 0
      je end_for_each_event

      push r15          ; ensure our loop counter is not modified

      ; ensure the event matches something we registered (although it probably must)
      mov edi, [the_events + r15 + epoll_event_fd.fd]
      cmp edi, stdin
      jne unknown_fd_error
      mov rsi, buffer
      mov rdx, buffer_len
      call read

      mov rdi, stdout
      mov rsi, buffer
      mov rdx, rax       ; from call to read
      call write

      pop r15
      dec r15            ; decrement the epoll event count
      jmp for_each_event
    end_for_each_event:

    jmp main_loop

  main_success:
    mov rdi, 0           ; Exit with return code of 0 (no error)
    mov rax, sys_exit
    syscall

  main_error:
    mov rdi, main_error_msg
    call error

  unknown_fd_error:
    mov rdi, unknown_fd_error_msg
    call error
