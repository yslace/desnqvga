;==============================================================================
; doorbell.s  -  Doorbell button and chime
;
; A debounced doorbell PRESS (edge, not level - holding the button does not
; retrigger) starts a two-note "ding-dong" chime on the on-board speaker,
; driven by the LPC2478 DAC (AOUT on pin P0.26).
;
; The chime is NON-BLOCKING: Doorbell_Chime only records "a chime is playing"
; and Chime_Service (run from Doorbell_Poll every super-loop pass) toggles
; the DAC between full-scale and zero whenever Timer1 shows a half-period
; has elapsed.  The automation loop is never stalled by a ~450 ms busy-wait.
; (Pitch accuracy therefore depends on the loop being faster than the
; ~500 us half-period; the LCD module skips its slow redraws while the
; chime is playing to guarantee that.)
;
; Provides:
;   Doorbell_Init   - route P0.26 to the DAC, clear chime/edge state
;   Doorbell_Poll   - call every pass: start chime on a new press + service it
;   Doorbell_Chime  - start the chime (also called by the LCD "test" button)
;   Doorbell_Active - r0 = 1 while a chime is playing, else 0
;==============================================================================
        AREA    DoorbellCode, CODE, READONLY
        GET     lpc2478.inc

        IMPORT  Buttons_TakeEvents

        EXPORT  Doorbell_Init
        EXPORT  Doorbell_Poll
        EXPORT  Doorbell_Chime
        EXPORT  Doorbell_Active

;------------------------------------------------------------------------------
; Chime note table (all values computed at assembly time -> no runtime divide)
;   half-period(us) = 500000 / freq
;   half-cycles     = freq * duration_ms / 500
;------------------------------------------------------------------------------
DING_F          EQU     988             ; ~B5
DONG_F          EQU     784             ; ~G5
DING_MS         EQU     180
DONG_MS         EQU     260
DING_HP         EQU     (500000/DING_F)
DING_N          EQU     (DING_F*DING_MS/500)
DONG_HP         EQU     (500000/DONG_F)
DONG_N          EQU     (DONG_F*DONG_MS/500)
DAC_HIGH        EQU     (0x3FF:SHL:6)   ; full-scale DAC value in bits[15:6]

; g_ch_note values
NOTE_IDLE       EQU     0
NOTE_DING       EQU     1
NOTE_DONG       EQU     2

;------------------------------------------------------------------------------
; Doorbell_Init
;   In: -   Out: -   Clobbers: r0-r2
;------------------------------------------------------------------------------
Doorbell_Init
        ; route P0.26 to AOUT (PINSEL1 bits[21:20] = 10)
        LDR     r0, =PINSEL1
        LDR     r1, [r0]
        LDR     r2, =DACPIN_MASK
        BIC     r1, r1, r2
        LDR     r2, =DACPIN_SET
        ORR     r1, r1, r2
        STR     r1, [r0]

        ; chime idle, speaker silent
        MOV     r1, #NOTE_IDLE
        LDR     r0, =g_ch_note
        STR     r1, [r0]
        LDR     r0, =DACR
        MOV     r1, #0
        STR     r1, [r0]
        BX      lr

;------------------------------------------------------------------------------
; Doorbell_Poll : consume a debounced doorbell press event (one event per
;   physical press, courtesy of buttons.s) and keep the chime playing.
;   In: -   Out: -   Clobbers: r0-r3
;------------------------------------------------------------------------------
Doorbell_Poll
        PUSH    {lr}
        LDR     r0, =INP_DOORBELL
        BL      Buttons_TakeEvents
        CMP     r0, #0
        BLNE    Doorbell_Chime
        BL      Chime_Service
        POP     {pc}

;------------------------------------------------------------------------------
; Doorbell_Chime : start the "ding" (non-blocking; restarts if already playing).
;   In: -   Out: -   Clobbers: r0, r1
;------------------------------------------------------------------------------
Doorbell_Chime
        MOV     r0, #NOTE_DING
        LDR     r1, =g_ch_note
        STR     r0, [r1]
        LDR     r0, =DING_HP
        LDR     r1, =g_ch_hp
        STR     r0, [r1]
        LDR     r0, =DING_N
        LDR     r1, =g_ch_n
        STR     r0, [r1]
        MOV     r0, #1                  ; start in the high half-cycle
        LDR     r1, =g_ch_phase
        STR     r0, [r1]
        LDR     r1, =DACR
        LDR     r0, =DAC_HIGH
        STR     r0, [r1]
        LDR     r0, =T1TC
        LDR     r0, [r0]
        LDR     r1, =g_ch_last
        STR     r0, [r1]
        BX      lr

;------------------------------------------------------------------------------
; Doorbell_Active : r0 = 1 while a chime is playing, else 0.   Clobbers: -
;------------------------------------------------------------------------------
Doorbell_Active
        LDR     r0, =g_ch_note
        LDR     r0, [r0]
        CMP     r0, #NOTE_IDLE
        MOVNE   r0, #1
        BX      lr

;------------------------------------------------------------------------------
; Chime_Service : advance the square wave if a half-period has elapsed.
;   In: -   Out: -   Clobbers: r0-r3
;------------------------------------------------------------------------------
Chime_Service
        LDR     r0, =g_ch_note
        LDR     r0, [r0]
        CMP     r0, #NOTE_IDLE
        BXEQ    lr                      ; nothing playing

        LDR     r0, =T1TC
        LDR     r0, [r0]                ; now (us)
        LDR     r1, =g_ch_last
        LDR     r2, [r1]
        SUB     r2, r0, r2              ; elapsed (wrap-safe)
        LDR     r3, =g_ch_hp
        LDR     r3, [r3]
        CMP     r2, r3
        BXLO    lr                      ; half-period not over yet
        STR     r0, [r1]                ; timestamp this toggle

        ; toggle the speaker level
        LDR     r1, =g_ch_phase
        LDR     r2, [r1]
        EOR     r2, r2, #1
        STR     r2, [r1]
        CMP     r2, #0
        LDRNE   r0, =DAC_HIGH
        MOVEQ   r0, #0
        LDR     r1, =DACR
        STR     r0, [r1]

        ; one half-cycle done; move to the next note / stop when finished
        LDR     r1, =g_ch_n
        LDR     r2, [r1]
        SUBS    r2, r2, #1
        STR     r2, [r1]
        BXNE    lr                      ; current note still playing

        LDR     r1, =g_ch_note
        LDR     r2, [r1]
        CMP     r2, #NOTE_DING
        BNE     CS_stop
        ; ding finished -> load the dong
        MOV     r2, #NOTE_DONG
        STR     r2, [r1]
        LDR     r2, =DONG_HP
        LDR     r1, =g_ch_hp
        STR     r2, [r1]
        LDR     r2, =DONG_N
        LDR     r1, =g_ch_n
        STR     r2, [r1]
        BX      lr
CS_stop
        MOV     r2, #NOTE_IDLE
        STR     r2, [r1]
        LDR     r1, =DACR
        MOV     r2, #0
        STR     r2, [r1]                ; leave the speaker silent
        BX      lr

        LTORG

;------------------------------------------------------------------------------
        AREA    DoorbellData, DATA, READWRITE
g_ch_note   SPACE   4       ; NOTE_IDLE / NOTE_DING / NOTE_DONG
g_ch_hp     SPACE   4       ; current half-period (us)
g_ch_n      SPACE   4       ; half-cycles remaining in the current note
g_ch_phase  SPACE   4       ; current output level (0 = low, 1 = high)
g_ch_last   SPACE   4       ; Timer1 time of the previous toggle

        END
