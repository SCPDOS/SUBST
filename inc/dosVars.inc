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