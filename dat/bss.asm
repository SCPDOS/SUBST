;BSS data
pSysvars    dq ?
pVar1       dq ?
pVar2       dq ?
;Used for create subst
srcDrv  db ?    ;0 based drive number of source drive of the SUBST
destDrv db ?    ;0 based drive number of the SUBST drive!
buffer  db 67 dup (?)   ;ASCIIZ path to the host directory