; Subst!

[map all ./lst/subst.map]
[DEFAULT REL]

;
;Creates, deletes and displays subst drives.
;Order of arguments DOES NOT matter.
;Invoked by: 
; SUBST [drive 1: [drive2:]path] <- Mounts [drive2:]path on drive1:
; SUBST drive1: /D       <- Deletes the subst drive drive1:
; SUBST                  <- Displays current subst drives

BITS 64
%include "./inc/dosMacro.mac"
%include "./inc/dosStruc.inc"
%include "./inc/dosError.inc"
%include "./inc/dosVars.inc"
%include "./src/main.asm"
%include "./dat/strings.asm"
;Use a 45 QWORD stack
Segment transient align=8 follows=.text nobits
%include "./dat/bss.asm"
    dq 45 dup (?)
endOfAlloc: