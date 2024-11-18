;Subst main routine
startMain:
    jmp short .cVersion
.vNum:  db 1
.cVersion:
    lea rsp, endOfAlloc   ;Move RSP to our internal stack
;Do a version check since this version cannot check the number of rows/cols
    cld
    mov eax, 3000h
    int 21h
    cmp al, byte [.vNum]    ;Version number 1 check
    jbe short okVersion
    lea rdx, badVerStr
badPrintExit:
    mov eax, 0900h
    int 21h
    mov eax, 4CFFh
    int 21h
okVersion:
    lea rsp, endOfAlloc   ;Move RSP to our internal stack
;Now let us resize ourselves so as to take up as little memory as possible
    mov ebx, endOfAlloc
    mov eax, 4A00h
    int 21h ;If this fails, we still proceed as we are just being polite!
;Now get the sysvars pointer and save it in var.
;This cannot change so it is fine to do it out of a critical section.
    mov eax, 5200h
    int 21h
    mov qword [pSysvars], rbx
parseCmdLine:
;Now parse the command line
    lea rsi, qword [r8 + psp.progTail]
    xor ecx, ecx    ;Keep a count of vars on cmd line in ecx
    xor eax, eax    ;Clear all upper bytes for fun
    mov qword [pVar1], rax  ;Init these vars
    mov qword [pVar2], rax
    call skipDelims ;Goto the first non-delimiter char
    cmp al, CR
    je endParse
    mov qword [pVar1], rsi    ;Save the ptr to the first var
    inc ecx
    call findDelimOrCR
    cmp al, CR
    je endParse
    call skipDelims
    mov qword [pVar2], rsi    ;Save the ptr to the second var
    inc ecx
    call findDelimOrCR
    cmp al, CR  ;The second arg shouldve been the last arg
    je endParse
badParmExit:
    lea rdx, badParmStr
    jmp badPrintExit
endParse:
    test ecx, ecx
    jz printSubst   ;If no arguments found, print the substs!
    cmp ecx, 1      
    je badParmExit  ;Cannot have just 1 argument on the cmdline
    mov eax, 3700h  ;Get switchchar in dl
    int 21h
    xor ecx, ecx    ;Use as cntr (1 or 2) to indicate which var has ptr to /D
    mov rsi, qword [pVar1]
    cmp byte [rsi], dl
    jne .g2
    call checkSwitchOk  ;Now check rsi points to a bona fide /D 
    jc badParmExit
    inc ecx
.g2:
    mov rsi, qword [pVar2]
    cmp byte [rdi], dl
    jne .switchDone
    test ecx, ecx   ;Var2 can be /D ONLY IF Var1 was not /D
    jnz badParmExit
    call checkSwitchOk  ;Now check rsi points to a bona fide /D 
    jc badParmExit
    mov ecx, 2      ;Else, indicate var2 has the /D flag!
.switchDone:
    test ecx, ecx   ;If ecx is zero, then we are adding a subst.
    jz addSubst
;Else we are deleting a subst drive.
delSubst:
    mov rsi, qword [pVar1]
    mov rdi, qword [pVar2]
    cmp ecx, 1          ;If ecx = 1, rsi points to the /D
    cmovne rdi, rsi     ;Make rdi point to the drive letter!
;rdi points to the drive letter in cmdline. Check it is legit.
    mov al, byte [rdi + 2]
    call isALDelimOrCR  ;Ensure the string length is 2!
    jne badParmExit
    cmp byte [rdi + 1], ":"
    jne badParmExit
;Here the char is legit! Now UC it and use it as offset into CDS
; to deactivate it!
    movzx eax, byte [rdi]
    push rax
    mov eax, 1213h  ;UC char
    int 2Fh
    movzx ecx, al   ;Move the UC char into ecx
    pop rax         ;Rebalance the stack
    sub ecx, "A"    ;Turn into an offset into CDS
;Check if we are deleting the current drive.
    mov eax, 1900h  ;Get current drive
    int 21h
    cmp al, cl  ;If we are deleting the current drive, error exit!
    je badParmExit
;Check if the subst drive we want to deactivate is a valid drive
; in our system (i.e. does such a drive entry exist in the CDS array)
    call enterDOSCrit   ;Enter crit, Exit in the exit routine!
    mov rbx, qword [pSysvars]   
    movzx eax, byte [rbx + sysVars.lastdrvNum]
    cmp cl, al  ;If drive specified is past end of CDS array, error!
    ja .error
;Point rdi to the cds we are adjusting.
    lea rdi, qword [rbx + sysVars.cdsHeadPtr]   ;Point rdi to cds array
    mov eax, cds_size
    mul ecx
    add ecx, "A"    ;Turn offset back into a UC drive letter!
    add rdi, rax    ;rdi now points to the right CDS
;Check the cds we have chosen is really a subst drive
    test word [rdi + cds.wFlags], cdsSubstDrive
    jne .error      ;If this CDS is not a subst drive, error!
;Start editing the CDS back to it's default state
    mov byte [rdi], cl  ;Place the drive letter...
    mov word [rdi + 2], "\"   ;... and root backslash with null terminator!
    mov byte [rdi + cds.wBackslashOffset], 2    ;Go to root!
    mov dword [rdi + cds.dStartCluster], 0      ;Set start cluster for root!
;Deactivate the subst but also the drive possibly temporarily!
    and word [rdi + cds.wFlags], ~(cdsSubstDrive | cdsValidDrive)
;Check for a physical DPB for this drive letter.
;I.E if drive D selected, search for the fourth DPB.
    sub ecx, "A"    ;Turn ecx back into a 0 based drive number
;If the drive number is above the number of physical drives, we 
; ignore the search as the physical drives always populate the 
; first drives. Acts as a minor optimisation to avoid walking DPB linked list.
    cmp cl, byte [rbx + sysVars.numPhysVol]
    ja .exit    ;If drv num > physical drvs, we ignore this search!
;Search the DPB linked list for the drive number associated to this drive!
    mov rbp, qword [rbx + sysVars.dpbHeadPtr]
.lp:
    cmp byte [rbp + dpb.bDriveNumber], cl
    je .dpbFnd  ;If DPB found for the drive in cl, 
    mov rbp, qword [rbp + dpb.qNextDPBPtr]
    cmp rbp, -1 ;We should never fall through but still better to be safe!
    jne .lp
.exit:
    jmp exit
.dpbFnd:
    mov qword [rdi + cds.qDPBPtr], rbp  ;Set this DPB as the CDS DPB!
    or word [rdi + cds.wFlags], cdsValidDrive   ;Reactivate this drive!
    jmp short .exit
.error:
;Invalid drive specified!
    call exitDOSCrit    ;Exit the critical section before exiting!!
    jmp badParmExit
    
addSubst:
;Here we add the subst path. We gotta check that path provided
; exists! It is not null terminated so we gotta null terminate it.
; We also gotta get rid of any trailing slashes from the path provided!
;
;Drive1 can be valid, be cannot be a subst, join or net drive!
;
    mov rsi, qword [pVar1]
    call findDelimOrCR
    mov byte [rsi], 0   ;Null terminate var1
    mov rsi, qword [pVar2]
    call findDelimOrCR
    mov byte [rsi], 0   ;Null terminate var2

    xor ebp, ebp        ;Use rbp as the ptr to the drive spec string

    mov rsi, qword [pVar1]  ;Check if var1 is drive specification
    cmp word [rsi + 1], ":" ;Is pVar1 a drive specification?
    cmove rbp, rsi  ;Move the ptr to the drive specifier into rbp

    mov rsi, qword [pVar2]  ;Check if var2 is drive specification
    cmp word [rsi + 1], ":" ;Is pVar2 a drive specification?
    jne .gotDrvSpec
    test rbp, rbp   ;rbp must be null, else two drives were specified. Error!
    jnz badParmExit
    mov rbp, rsi    ;Set rbp to point to the drive
.gotDrvSpec:
;Come here with rbp pointing to the new subst drive spec. 
    movzx eax, byte [rbp]
    push rax
    mov eax, 1213h  ;UC the char in al
    int 2Fh
    sub al, "A"     ;Turn into a 0 based drive number
    mov byte [destDrv], al
    pop rax
;Make rsi point to the other argument!
    mov rsi, qword [pVar1]
    mov rdi, qword [pVar2]
    cmp rbp, rsi  ;if rbp -> var1...  
    cmove rsi, rdi  ;... make rsi -> var2. Else, rsi -> var1
;rsi -> ASCIIZ path. Must check it is a legit path.
    lea rdi, pathBuffer
    movzx eax, dword [rsi]   
    xor al, al  ;Zero the first byte
    cmp eax, 005C3A00h  ;<NUL>:\<NUL>
    je .root
    cmp eax, 002F3A00h  ;<NUL>:/<NUL>
    jne .notRoot
.root:
;Skip using truename for mounting a root dir on another drive :)
    lodsb   ;Get the drive letter
    push rax
    mov eax, 1213h  ;UC the drive letter
    int 2Fh
    stosb   ;Store it!
    pop rax
    movsw   ;Copy the rest of the string
    movsb
    jmp short .checks
.notRoot:
    mov eax, 6000h  ;Use truename to get the real path provided
    int 21h
.checks:
    movzx eax, byte [rdi]   ;This is already uppercased by truename
    sub al, "A"             ;Turn into a 0 based drive number
    mov byte [srcDrv], al
    cmp byte [destDrv], al
    jne .notEqual
    ;HERE ERROR! CANNOT SUBST A DRIVE ONTO ITSELF!
.notEqual:
;CHECK CHECK CHECK CHECK
;Check that the directory we are swapping to exists and is a (SUB)DIR:)
;CHECK CHECK CHECK CHECK
    mov eax, 1900h  ;Get current drive
    int 21h
    cmp al, byte [destDrv]
    jne .notCurrent
    ;HERE ERROR! CANNOT SUBST OVER CURRENT DRIVE!
.notCurrent:
    call enterDOSCrit
    mov rbx, qword [pSysvars]   
    movzx eax, byte [rbx + sysVars.lastdrvNum]
    cmp al, byte [srcDrv]
    jnb .srcDrvNumOk
    ;HERE ERROR! SRC DRIVE REQUESTED PAST THE LENGTH OF CDS ARRAY!
.srcDrvNumOk:
    cmp al, byte [destDrv]
    jnb .destDrvNumOk
    ;HERE ERROR! SUBST DRIVE REQUESTED PAST THE LENGTH OF CDS ARRAY!
.destDrvNumOk:
;Get the CDS for the destination. Check it is valid!
    movzx ecx, byte [srcDrv]
    call .getCds
    test byte [rdi + cds.wFlags], cdsValidDrive
    jnz .srcDrvValid
    ;HERE ERROR! SPECIFIED HOST DRIVE NOT VALID (Should never happen?)
.srcDrvValid:
;Check host drive CDS is not NET, SUBST or JOIN!
    test byte [rdi + cds.wFlags], cdsJoinDrive | cdsSubstDrive | cdsRedirDrive
    jz .srcDrvOk
    ;HERE ERROR! SPECIFIED HOST DRIVE ALREADY A SUBST/JOIN/REDIR DRIVE!
.srcDrvOk:
;Get the CDS for the source. If it is NET, SUBST or JOIN, fail!
    mov rsi, rdi    ;Save the source cds pointer in rsi
    movzx ecx, byte [destDrv]
    call .getCds
    test byte [rdi + cds.wFlags], cdsJoinDrive | cdsSubstDrive | cdsRedirDrive
    jz .destDrvOk
    ;HERE ERROR! SPECIFIED SUBST DRIVE IF ALREADY A SUBST/JOIN/REDIR DRIVE!
.destDrvOk:
    mov rbp, qword [rsi + cds.qDPBPtr]
    mov qword [rdi + cds.qDPBPtr], rbp
    mov dword [rdi + cds.dStartCluster], 0  ;Setup to root dir
    mov word [rdi + cds.wBackslashOffset], 2
    lea rsi, buffer
    mov eax, 1212h  ;strlen on buffer in rsi preserving rsi
    int 2Fh         ;Get the strlen in ecx
    mov rdx, rsi
    push rcx
    push rdi
    rep movsb       ;Copy the path over
    pop rdi
    pop rcx

    mov word [rdi + cds.wFlags], cdsValidDrive | cdsSubstDrive  ;Setup flags
    mov eax, 3B00h  ;CHDIR for this drive (to get the cluster value)
    int 21h


.getCds:
;Input: ecx = [byte] 0-based drive number
;       rbx -> sysVars
;Output: rdi -> CDS for drive
    lea rdi, qword [rbx + sysVars.cdsHeadPtr]   ;Point rdi to cds array
    mov eax, cds_size
    mul ecx
    add rdi, rax    ;rdi now points to the right CDS
    return


printSubst:
    call enterDOSCrit   ;Ensure the CDS size and ptr doesnt change
    mov rbx, qword [pSysvars]
    lea rdi, qword [rbx + sysVars.cdsHeadPtr]
    movzx ecx, byte [rbx + sysVars.lastdrvNum]  ;Get # of CDS's
    mov ebx, "A"    
.lp:
    test word [rdi + cds.wFlags], cdsSubstDrive
    jz .gotoNextCDS
;Print the CDS drive letter and the rocket
    lea rdx, substStr
    mov byte [rdx], bl  ;Overwrite the drive letter in substStr
    mov eax, 0900h      ;Print the substStr
    int 21h
;Print the current path of the cds upto the backslash offset
    push rbx
    movzx ecx, word [rdi + cds.wBackslashOffset]
    lea rdx, qword [rdi + cds.sCurrentPath]
    mov ebx, 1          ;Print to STDOUT
    mov eax, 4000h
    int 21h
    pop rbx
;Print a CRLF
    lea rdx, crlf
    mov eax, 0900h
    int 21h
.gotoNextCDS:
    add rdi, cds_size
    inc ebx ;Goto next drive letter!
    dec ecx
    jnz .lp
exit:
    call exitDOSCrit
    mov eax, 4C00h
    int 21h

;------------------------------------------------------------------------
; Utility functions below!
;------------------------------------------------------------------------
checkSwitchOk:
;Checks if the switch char is D and if the char following is a 
; delimiter or CR. 
;Input: rsi -> Possible /D. Points to the /
;Output: CF=CY: Not ok to proceed.
;        CF=NC: Ok to proceed
    mov al, byte [rsi + 1]
    push rax
    mov eax, 1213h  ;UC char
    int 2Fh
    cmp al, "D"
    pop rax
    jne .bad
    mov al, byte [rsi + 2]
    cmp al, CR  ;If equal, clears CF
    rete
    call isALDelim  ;If return equal, we are ok!
    rete
.bad:
    stc
    return

enterDOSCrit:
    push rax
    mov eax, 8001h
    int 2Ah
    pop rax
    return 

exitDOSCrit:
    push rax
    mov eax, 8101h
    int 2Ah
    pop rax
    return 

skipDelims:
;Points rsi to the first non-delimiter char in a string, loads al with value
    lodsb
    call isALDelim
    jz skipDelims
;Else, point rsi back to that char :)
    dec rsi
    return

findDelimOrCR:
;Point rsi to the first delim or cmdtail terminator, loads al with value
    lodsb
    call isALDelimOrCR
    jz findDelimOrCR
    dec rsi ;Point back to the delim or CR char
    return

isALDelimOrCR:
    cmp al, CR
    rete
isALDelim:
    cmp al, SPC
    rete
    cmp al, TAB
    rete
    cmp al, "="
    rete
    cmp al, ","
    rete
    cmp al, ";"
    return