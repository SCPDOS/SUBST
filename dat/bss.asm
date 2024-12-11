;BSS data
bssStart:
pSysvars    dq ?
pVar1       dq ?
pVar2       dq ?
;Used for create subst
srcDrv  db ?    ;0 based drive number of source drive of the SUBST
destDrv db ?    ;0 based drive number of the SUBST drive!
inCDS   db cds_size dup (?)   ;ASCIIZ path to the host directory
        db (128 - cds_size) dup (?)   ;Padding for if the string is too long!
bssLen equ $ - bssStart