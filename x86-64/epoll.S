/*
 * epoll.S
 *
 * Assembly language demo of using linux epoll on x86-64. This makes use of
 * epoll to wait for input from stdin and echos it to the screen when available.
 *
 * Copyright (c) 2014, Simon Feltman <s.feltman@gmail.com>
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright notice, this
 *    list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright notice,
 *    this list of conditions and the following disclaimer in the documentation
 *    and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
 * ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */


/*
 Notes:
 x86-64 C calling convention arg registers:
   cdecl 64: RDI, RSI, RDX, RCX, R8, R9, XMM0–7
     additional args are pushed onto stack in reverse order
   syscalls: RDI, RSI, RDX, R10, R8, R9, XMM0–7 (destroys rcx and r11)
   callee must reserve: rbp, rbx, r12, r13, r14, r15
 Parameter order on stack: RTL (C)
 Stack cleanup by: Caller
*/

.file   "epoll.S"
.intel_syntax noprefix


.set stdin,  0
.set stdout, 1
.set stderr, 2

.set sys_read,          0
.set sys_write,         1
.set sys_exit,          60
.set sys_epoll_create,  213
.set sys_epoll_wait,    232
.set sys_epoll_ctl,     233

.set EPOLLIN,  0x001
.set EPOLLPRI, 0x002
.set EPOLLOUT, 0x004

.set EPOLL_CTL_ADD, 1  /* Add a file decriptor to the interface.  */
.set EPOLL_CTL_DEL, 2  /* Remove a file decriptor from the interface.  */
.set EPOLL_CTL_MOD, 3  /* Change file decriptor epoll_event structure.  */


/* struct epoll_event */
.struct    0
  epoll_event.events:    .word      0
                         .align     2
  epoll_event.fd:        .word      0
                         .align     2
  epoll_event.pad:       .word      0
                         .align     2
  epoll_event.size:


/* Data Section */
.section .data

hello:                 .asciz "Welcome to the echo console, use Ctrl+C to exit\n"
prompt:                .asciz ">>> "
main_error_msg:        .asciz "error: epoll_wait failed\n"
unknown_fd_error_msg:  .asciz "error: unknown file descriptor in epoll\n"
epoll_ctl_error:       .asciz "error: with epoll_ctl for stdin\n"

stdin_event:
stdin_event.events:    .word      EPOLLIN
                       .align     2
stdin_event.fd:        .word      stdin
                       .align     2
stdin_event.pad:       .word      0
                       .align     2


/* BSS Section */
.section .bss

the_epoll_fd:          .quad 1

the_events:            .skip epoll_event.size * 5    /* reserve place for 5 structures */
.set the_events_len,   (. - the_events) / epoll_event.size

buffer:                .skip 1024
.set buffer_len,       . - buffer


/* Code Section */
.section .text
  .align  2
  .global _start


/*
 * write:
 * @fd:  rdi: long fd
 * @buf: rsi: char *
 * @len: rdx: int
 *
 * Returns: rax: int: number of bytes written
 */
write:
  /* fd, str, and len passthrough to the syscall */
  mov rax, sys_write   /* The system call for write (sys_write) */
  syscall              /* Call the kernel */
  ret


/*
 * read:
 * @fd:  rdi: long fd
 * @buf: rsi: char *
 * @max: rdx: int
 *
 * Returns: rax: int: number of bytes read
 */
read:
  /* fd, str, and len passthrough to the syscall */
  mov rax, sys_read    /* The system call for write (sys_write) */
  syscall              /* Call the kernel */
  ret


/*
 * epoll_create:
 * @size: rdi: int
 *
 * Returns: rax: long: new epoll fd
 */
epoll_create:
  mov rax, sys_epoll_create
  syscall
  ret


/*
 * epoll_wait:
 * @epfd:      rdi: int
 * @events:    rsi: struct epoll_event *
 * @maxevents: rdx: int
 * @timeout:   r10: int
 *
 * Returns: rax: long: event count or -1 on error
 */
epoll_wait:
  mov rax, sys_epoll_wait
  syscall
  ret


/*
 * epoll_ctl
 * @epfd:    rdi: int
 * @op:      rsi: int
 * @fd:      rdx: int
 * @event:   r10: struct epoll_event *
 *
 * Returns: rax: long: 0 on success -1 on failure
 */
epoll_ctl:
  mov rax, sys_epoll_ctl
  syscall
  ret


/*
 * strlen:
 * @str: rdi: char *:
 *
 * http://www.int80h.org/strlen/
 *
 * Returns: rax: long: length of input string
 */
strlen:
  /* str:rdi passes through to scasb */
  sub rcx, rcx         /* rcx = 0 */
  not rcx              /* rcx = 2^64 (-1) (count used in repne) */
  sub al, al           /* al = 0 */
  cld                  /* clear the direction flag, causes repne to go up in direction */
  repne scasb          /* repeatedly decrement rcx until byte (from string in rdi) is not equal to al (0) */
  not rcx              /* absolute value of rcx */
  dec rcx              /* get rid of initial -1 */
  mov rax, rcx         /* return in rax */
  ret


/*
 * print:
 * @str: rdi: char *
 */
print:
  /* str already in rdi for strlen call */
  mov rsi, rdi         /* move str to rsi */
  call strlen
  mov rdx, rax         /* move length of string into rdx for write */
  mov rdi, stdout      /* File descriptor 1 - standard output */
  call write
  ret


/*
 * error:
 * @str: rdi: char *
 */
error:
  /* str already in rdi for strlen call */
  mov rsi, rdi         /* move str to rsi */
  call strlen
  mov rdx, rax         /* move length of string into rdx for write */
  mov rdi, stderr      /* File descriptor 1 - standard output */
  call write

  mov rdi, 1           /* Exit with return code of 1 */
  mov rax, sys_exit
  syscall

  ret


_start:
  mov rdi, offset hello      /* Put the offset of hello in rsi */
  call print

  mov rdi, 1
  call epoll_create
  mov the_epoll_fd, rax

  mov r10, offset stdin_event
  mov rdx, stdin
  mov rsi, EPOLL_CTL_ADD
  mov rdi, the_epoll_fd
  call epoll_ctl

  cmp rax, 0
  je main_loop            /* jump to the main_loop if epoll_ctl returned success */
  mov rdi, offset epoll_ctl_error
  call error

  main_loop:
    mov rdi, 0
    mov rdi, offset prompt
    call print

    mov r10, -1
    mov rdx, the_events_len
    mov rsi, offset the_events
    mov rdi, the_epoll_fd
    call epoll_wait

    mov r15, rax        /* keep event count in r15 */
    cmp r15, -1
    je main_error

    for_each_event:
      cmp r15, 0
      je main_loop
      dec r15           /* decrement the epoll event count/index */
      push r15          /* ensure our loop counter is not modified */

      /* ensure the event matches something we registered (although it probably must) */
      mov edi, [offset the_events + r15 + epoll_event.fd]
      cmp edi, stdin
      jne unknown_fd_error
      mov rsi, offset buffer
      mov rdx, buffer_len
      call read

      mov rdx, rax       /* from call to read */
      mov rsi, offset buffer
      mov rdi, stdout
      call write

      pop r15
      jmp for_each_event

    jmp main_loop

  main_success:
    mov rdi, 0           /* Exit with return code of 0 (no error) */
    mov rax, sys_exit
    syscall

  main_error:
    mov rdi, offset main_error_msg
    call error

  unknown_fd_error:
    mov rdi, offset unknown_fd_error_msg
    call error

.end
