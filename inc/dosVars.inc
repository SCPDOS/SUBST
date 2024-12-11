struc sysVars
    .dpbHeadPtr  dq ?    ;Pointer to the first DPB in the DPB chain x
    .sftHeadPtr  dq ?    ;Pointer to the first SFT header in SFT chain
    .clockPtr    dq ?    ;Pointer to the current active CLOCK$ device header x
    ;                    The last driver loaded with the CLOCK$ bit[3] set 
    .vConPtr     dq ?    ;Ptr to the devdrv of the char dev controlling vCon x
    ;                    The last driver loaded with the STDIN bit[0] set
    .maxBytesSec dw ?    ;Maximum number of bytes per sector (size of buffers)x
    .bufHeadPtr  dq ?    ;Pointer to the head of the disk buffer chain x
    .cdsHeadPtr  dq ?    ;Pointer to the head of the CDS array x
    .fcbsHeadPtr dq ?    ;Pointer to the head of the System FCB chain
    .numSafeSFCB dw ?    ;Number of protected FCBs (y in FCBS=x,y)
    .numPhysVol  db ?    ;Number of physical volumes in the system x
    .lastdrvNum  db ?    ;Value of LASTDRIVE (default = 5) [Size of CDS array]x
    .numBuffers  db ?    ;Buffers=30 default
    .nulDevHdr   db 22h dup (?)
    .numJoinDrv  db ?    ;Number of Joined Drives
endstruc


struc sda
    .critErrFlag db ?  ;Critical error flag, set on entry to Int 24h x
    .inDOS       db ?  ;Inc on each DOS call, dec when leaving x
    .errorDrv    db ?  ;Drive on which error occured or FFh x
    .errorLocus  db ?  ;Where the error took place  
    .errorExCde  dw ?  ;Extended Error Code
    .errorAction db ?  ;Suggested action for error  
    .errorClass  db ?  ;Error Class
    .errorVolLbl dq ?    ;Sets a ptr to the volume label of the error disk
    .currentDTA  dq ?  ;Address of the current DTA x
    .currentPSP  dq ?  ;Address of current PSP x
    .xInt23hRSP  dq ?  ;Saves RSP across an Int 23h call
    .errorLevel  dw ?  ;Last return code returned by Int 21h/4Ch x
    .currentDrv  db ?  ;Default drive x
    .breakFlag   db ?  ;If set, check for CTRL+C on all DOS calls x
    .oldRAX      dq ?  ;Store rax on entering Int21h or returning Int 23h
    .serverPSP   dq ?  ;PSP of prog making server request, used by net & share
    .machineNum  dw ?  ;for sharing/networking 00h = default number (us)
    .firstMCB    dq ?  ;First fit MCB for request
    .bestMCB     dq ?  ;Best fit MCB for request
    .lastMCB     dq ?  ;Last fit MCB for request
    .dirEntryNum dw ?  ;Offset into directory of entry we are looking for
    .volIdFlag   db ?    ;If set, we are searching for a volume ID
    .xInt24hRSP  dq ?  ;RSP across an Int 24h call
    .Int24bitfld db ?  ;Copies the bit field given to the Int 24h handler
    .fileDirFlag db ?  ;File/Directory flag. 0 = Dir, ¬0 = File
    .Int24Fail   db ?  ;Set if Int 24h returned fail
    .oldoldRSP   dq ?  ;RSP at prev Int 21h entry if called from within Int 21h
    .dosReturn   dq ?  ;Used as a var to return when juggling stack
    .oldRSP      dq ?  ;RSP when entering Int 21h
    .oldRBX      dq ?  ;Temp var to save value of rbx during an Int 21 call
    .dirFlag     db ?  ;Directory Flag. 0 => Search for Dir, 1 => for File
    .ctrlCExit   db ?  ;-1 => CTRL+BREAK termination, 0 otherwise
    .fcbSpaceOk  db ?  ;If set, we allow embedded spaces in the filenames
    .dayOfMonth  db ?  ;01h - 1Fh (1 - 31)
    .monthOfYear db ?  ;01h - 0Ch (1 - 12)
    .years       db ?  ;00h - 7Fh (00 = 1980 - 127 = 2107)
    .daysOffset  dw ?  ;Days since 1-1-1980
    .dayOfWeek   db ?  ;0 = Sunday <-> 6 = Saturday
    .vConDrvSwp  db ?  ;Set if vCon controlled by a different driver to vConPtr
    .int28Flag   db ?  ;If set, Int 28h should be called, if clear no
    .Int24Trans  db ?  ;Set to -1 if Abort translated to Fail
    .secdReqPkt  db ioReqPkt_size dup (?) ;Secondary, Char IO Reqhdr
    .primReqPkt  db ioReqPkt_size dup (?) ;Main Drv Reqhdr 
    .critReqPkt  db ioReqPkt_size dup (?)  ;Used for ^C detection!
    .pspCopyFlg  db ?  ;Set to -1 for child process PSP, 0 for simple PSP copy
    .CLOCKrecrd  db 6 dup (?)  ;Clock driver record
    .singleIObyt dw ?  ;For single IO byte buffers
    .buffer1     db 128 dup (?)  ;Space for one path and file name
    .buffer2     db 128 dup (?) ;Space for a second path and file name
    .fname1Ptr   dq ?  ;Ptr to first filename argument
    .fname2Ptr   dq ?  ;Ptr to second filename argument
    .skipDisk    db ?  ;Set => Read Disk, Clear => Skip checking on disk
    .dosffblock  db ffBlock_size dup (?)  ;FF block (fullsize unlike DOS)
    .curDirCopy  db fatDirEntry_size dup (?)  ;Dir copy
endstruc

struc fatDirEntry

    .name       db 11 dup (?) ;8.3 File Name w/o fullstop
    .attribute  db ?  ;Usual attributes
    .ntRes      db ?  ;Reserved 0
    .crtTimeT   db ?  ;Count of tenths of a second of file creation time <=199
    .crtTime    dw ?  ;Creation time, granularity of 2 seconds
    .crtDate    dw ?  ;Creation date
    .lastAccDat dw ?  ;Last Read/Write date, not 100% supported (consider later)
    .fstClusHi  dw ?  ;Hi word of 1st data cluster for file/dir, 0 on FAT12/16
    .wrtTime    dw ?  ;Last modification (write) time
    .wrtDate    dw ?  ;Last modification (write) date
    .fstClusLo  dw ?  ;Lo word of 1st data cluster for file/dir
    .fileSize   dd ?  ;32-bit quantity with size of file described by entry

endstruc