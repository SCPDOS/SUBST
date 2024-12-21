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
;Now we init the BSS to 0.
    lea rdi, bssStart
    xor eax, eax
    mov ecx, bssLen
    rep stosb
;Now let us resize ourselves so as to take up as little memory as possible
    lea rbx, endOfAlloc ;Number of bytes of the allocation
    sub rbx, r8
    add ebx, 0Fh        ;Round up
    shr ebx, 4          ;Turn into number of paragraphs
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
badPrmsExit:
;Too many parameters and/or badly formatted cmdline error
    lea rdx, badPrmsStr
    jmp badPrintExit
badParmExit:
;Bad but valid parameter passed in
    lea rdx, badParmStr
    jmp badPrintExit
endParse:
    test ecx, ecx
    jz printSubst   ;If no arguments found, print the substs!
    cmp ecx, 1      
    je badPrmsExit  ;Cannot have just 1 argument on the cmdline
    mov eax, 3700h  ;Get switchchar in dl
    int 21h
    xor ecx, ecx    ;Use as cntr (1 or 2) to indicate which var has ptr to /D
    mov rsi, qword [pVar1]
    cmp byte [rsi], dl
    jne .g2
    call checkSwitchOk  ;Now check rsi points to a bona fide /D 
    jc badPrmsExit
    inc ecx
.g2:
    mov rsi, qword [pVar2]
    cmp byte [rsi], dl
    jne .switchDone
    test ecx, ecx   ;Var2 can be /D ONLY IF Var1 was not /D
    jnz badPrmsExit
    call checkSwitchOk  ;Now check rsi points to a bona fide /D 
    jc badPrmsExit
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
    jne badPrmsExit
    cmp byte [rdi + 1], ":"
    jne badPrmsExit
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
;If drive specified to remove is past end of CDS array, error!
    cmp byte [rbx + sysVars.lastdrvNum], cl
    jbe .error
;Point rdi to the cds we are adjusting.
    mov rdi, qword [rbx + sysVars.cdsHeadPtr]   ;Point rdi to cds array
    mov eax, cds_size
    mul ecx
    add ecx, "A"    ;Turn offset back into a UC drive letter!
    add rdi, rax    ;rdi now points to the right CDS
;Check the cds we have chosen is really a subst drive
    test word [rdi + cds.wFlags], cdsSubstDrive
    jz .error      ;If this CDS is not a subst drive, error!
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
    jnz badParmExit ;Cmdline valid but invalid data passed!
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
    lea rdi, qword [inCDS + cds.sCurrentPath]
    mov eax, 121Ah
    int 2Fh
    jc badParmExit  ;Bad drive selected if CF=CY
    test al, al
    jnz .notDefault
    mov eax, 1900h
    int 21h
    inc eax
.notDefault:
    mov edx, eax    ;Save 1 based drive number in dl
    dec eax         ;Convert the drive number to 0 based
    cmp al, byte [destDrv]  ;Check drive numbers are not equal 
    je badParmExit
    mov byte [srcDrv], al   ;Save the drive letter in the var 
    add al, "A"
    mov ah, ":"
    stosw   ;Store drive letter 
    xor eax, eax
    lodsb   ;Get the first char of the path now and adv char ptr
    cmp al, "\"
    je .pathSepFnd
    cmp al, "/"
    mov al, "\"     ;No pathsep (relpath) or unix pathsep given
    je .pathSepFnd
    dec rsi         ;Return the source ptr to the first char again!
    stosb           ;Store the pathsep and adv rdi
    push rsi        ;Save the source pointer
    mov rsi, rdi    ;Store the rest of the path here
    mov eax, 4700h  ;Get the Current Directory for current drive
    int 21h
    pop rsi         ;Get back the pointer to the source in rsi
    xor eax, eax
    mov ecx, -1
    repne scasb     ;Move rdi past the terminating null
    dec rdi         ;And point back to it
    cmp byte [rdi - 1], "\" ;Skip adding extra pathsep if one present (rt only)
    je .cplp
    mov al, "\"
.pathSepFnd:
    stosb           ;Store the normalised pathsep
;Now copy the path specified by rsi to rdi. rsi is null terminated string.
;If a wildcard is found, fail the subst (cannot pass wildcards into subst)
.cplp:
    lodsb
    stosb
    cmp al, "?"
    je badParmExit
    cmp al, "*"
    je badParmExit
    test al, al
    jnz .cplp
;Now we normalise the CDS string and check it is of len leq 67
    lea rsi, inCDS
    mov rdi, rsi
    mov eax, 1211h  ;Normalise string (UC and swap slashes.)
    int 2Fh
    mov eax, 1212h  ;Strlen (including terminating null)
    int 2Fh
    cmp ecx, 67
    ja badParmExit
;Now the CDS string is setup :) 
;We now enter the critical section and 
; check the CDS string is a path to a directory!
    call enterDOSCrit   ;Now enter DOS critical section

    lea rdx, qword [inCDS + cds.sCurrentPath]
    mov eax, dword [rdx]
    shr eax, 8  ;Drop the drive letter
    cmp eax, ":\"
    je .rtDir   ;Root dir specified (check that FF doesnt fail this case)
    mov eax, 4E00h
    mov ecx, 10h    ;Subdir flag
    int 21h
    jnc .fnd
.substNotDir:
    lea rdx, badPathStr ;Bad path passed for substing
    call exitDOSCrit
    jmp badPrintExit
.fnd:
;Something found, check it is a directory, not a file!
    cmp byte [r8 + 80h + ffBlock.attribFnd], 10h  ;Subdir flag
    jne .substNotDir
;Subdir found, get sda ptr to get cur dir info w/o using FCB functions.
    mov eax, 5D06h  ;Get SDA ptr in rsi
    int 21h
    movzx edx, word [rsi + sda.curDirCopy + fatDirEntry.fstClusLo]
    movzx eax, word [rsi + sda.curDirCopy + fatDirEntry.fstClusHi]
    shl eax, 10h
    or eax, edx ;Add low bits to eax
    mov dword [inCDS + cds.dStartCluster], eax  ;Replace with real start clust
.rtDir:
;The path provided is a valid directory. Start cluster in CDS (0 if root dir)
    mov rbx, qword [pSysvars]
;!!!! CHECK THIS PATH IS NOT A JOIN PATH !!!!
    push rbx
    movzx ecx, byte [rbx + sysVars.lastdrvNum]
    lea rsi, qword [inCDS + cds.sCurrentPath]
.joinTest:
    dec ecx
    call .getCds    ;Get the ptr to the CDS here in rdi
    mov eax, 121Eh  ;ASCII compare the strings. ZF=ZE if strings equal
    int 2Fh
    jnz .joinNeq
    test word [rdi + cds.wFlags], cdsJoinDrive
    jnz .inDOSBadNetExit
.joinNeq:
    test ecx, ecx   ;Once we test drive zero, exit
    jnz .joinTest
    pop rbx
;!!!! CHECK THIS PATH IS NOT A JOIN PATH !!!!
;Now check the selected destination CDS is valid!
    movzx ecx, byte [destDrv]
    cmp byte [rbx + sysVars.lastdrvNum], cl
    ja .destNumOk ;Has to be above zero as cl is 0 based :)
    ;ERROR: DRIVE PAST THE LAST DRIVE VALUE!
.inDOSBadExit:
    call exitDOSCrit
    jmp badParmExit
.destNumOk:
    call .getCds    ;Get the CDS ptr for the destination in rdi
    ;test word [rdi + cds.wFlags], cdsValidDrive
    ;DO NOT CHECK VALIDITY AS WE CAN OVERWRITE A VALID LOCAL DRV
    ;jnz .inDOSBadExit
    test word [rdi + cds.wFlags], cdsSubstDrive | cdsJoinDrive | cdsRedirDrive
    jz .destNotNet   
;ERROR: SPECIFIED CDS ENTRY ALREADY IN USE FOR REDIR!
.inDOSBadNetExit:
    lea rdx, badNetStr
    call exitDOSCrit
    jmp badPrintExit
.destNotNet:
;Now we build the subst CDS.
    mov rbp, rdi    ;Save the destination cds pointer in rbp
    movzx ecx, byte [srcDrv]    
    cmp byte [rbx + sysVars.lastdrvNum], cl ;Ensure src drive in range too
    jbe .inDOSBadExit
    call .getCds    ;Get source cds in rdi
    test word [rdi + cds.wFlags], cdsSubstDrive | cdsJoinDrive | cdsRedirDrive
    jnz .inDOSBadNetExit
    mov word [inCDS + cds.wFlags], cdsValidDrive | cdsSubstDrive
    mov rsi, qword [rdi + cds.qDPBPtr]
    mov qword [inCDS + cds.qDPBPtr], rsi
    mov rsi, qword [rdi + cds.qIFSPtr]
    mov qword [inCDS + cds.qIFSPtr], rsi
    mov esi, dword [rdi + cds.dNetStore]
    mov dword [rdi + cds.dNetStore], esi
;Now compute the wBackslash offset
    lea rsi, inCDS
    mov eax, 1225h  ;Get strlen of str pointed to by rsi in ecx
    int 2fh
    dec ecx         ;Drop the terminating null from count
    add rsi, rcx    ;Go to last char
    cmp byte [rsi], "\"
    jne .notTrailing    ;No trailing slash, skip overwrite.
    dec ecx
    cmp ecx, 2          ;If C:\, dont overwrite the slash
    je .notTrailing
    mov byte [rsi], 0   ;Else overwrite null over the trailing slash
.notTrailing:
    mov word [inCDS + cds.wBackslashOffset], cx
    mov rdi, rbp
    lea rsi, inCDS
    mov ecx, cds_size
    rep movsb   ;Copy over the new CDS and exit!
    jmp exit
.getCds:
;Input: ecx = [byte] 0-based drive number
;       rbx -> sysVars
;Output: rdi -> CDS for drive
    mov rdi, qword [rbx + sysVars.cdsHeadPtr]   ;Point rdi to cds array
    mov eax, cds_size
    mul ecx
    add rdi, rax    ;rdi now points to the right CDS
    return


printSubst:
    call enterDOSCrit   ;Ensure the CDS size and ptr doesnt change
    mov rbx, qword [pSysvars]
    mov rdi, qword [rbx + sysVars.cdsHeadPtr]
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
    push rcx
    movzx ecx, word [rdi + cds.wBackslashOffset]
    lea rdx, qword [rdi + cds.sCurrentPath]
    mov ebx, 1          ;Print to STDOUT
    mov eax, 4000h
    int 21h
    pop rcx
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
    jnz findDelimOrCR
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