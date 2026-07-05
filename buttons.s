;==============================================================================
; buttons.s  -  Debounce and edge detection for every push-button and switch
;
; Never trust a single raw GPIO read: mechanical contacts bounce for a few
; milliseconds.  This module samples all inputs every DEBOUNCE_SAMPLE_US
; (10 ms, timed off Timer1's free-running microsecond counter - no ISR) and
; only accepts a new state after DEBOUNCE_STABLE_N identical samples in a
; row (3 x 10 ms = 30 ms).
;
; On an accepted change it latches:
;   * press EVENTS  (0 -> 1 edges)  - so the doorbell rings once per press
;     and the plug button toggles once per press, no matter how long the
;     button is held;
;   * switch CHANGE flags (either edge) for the blind toggle switches - a
;     flip in either direction is a "the user wants manual control" event.
;
; Consumers take events with a mask, so the doorbell and the automation
; logic each consume only their own bits.
;
; Provides:
;   Buttons_Init             - snapshot the boot-time input state (no
;                              spurious events if a button is held at reset)
;   Buttons_Poll             - call every super-loop pass (self rate-limits)
;   Buttons_TakeEvents       - r0 = mask in -> r0 = consumed press events
;   Buttons_TakeSwitchChanges- r0 = mask in -> r0 = consumed change flags
;   Buttons_GetStable        - r0 = current debounced INP_* state
;==============================================================================
        AREA    ButtonCode, CODE, READONLY
        GET     lpc2478.inc

        IMPORT  Inputs_ReadRaw

        EXPORT  Buttons_Init
        EXPORT  Buttons_Poll
        EXPORT  Buttons_TakeEvents
        EXPORT  Buttons_TakeSwitchChanges
        EXPORT  Buttons_GetStable

;------------------------------------------------------------------------------
; Buttons_Init
;   In: -   Out: -   Clobbers: r0, r1
;------------------------------------------------------------------------------
Buttons_Init
        PUSH    {lr}
        BL      Inputs_ReadRaw          ; whatever is held now is "normal"
        LDR     r1, =g_btn_stable
        STR     r0, [r1]
        LDR     r1, =g_btn_cand
        STR     r0, [r1]
        MOV     r0, #DEBOUNCE_STABLE_N
        LDR     r1, =g_btn_cnt
        STR     r0, [r1]
        MOV     r0, #0
        LDR     r1, =g_btn_events
        STR     r0, [r1]
        LDR     r1, =g_sw_changed
        STR     r0, [r1]
        LDR     r0, =T1TC
        LDR     r0, [r0]
        LDR     r1, =g_btn_last_t
        STR     r0, [r1]
        POP     {pc}

;------------------------------------------------------------------------------
; Buttons_Poll : sample + debounce.  Call every super-loop pass; it returns
;   immediately unless DEBOUNCE_SAMPLE_US has elapsed since the last sample.
;   In: -   Out: -   Clobbers: r0-r3 (r4-r6 saved)
;------------------------------------------------------------------------------
Buttons_Poll
        PUSH    {r4-r6, lr}
        ; ---- rate limit off Timer1 (wrap-safe unsigned arithmetic) ----
        LDR     r4, =T1TC
        LDR     r4, [r4]                ; now (us)
        LDR     r5, =g_btn_last_t
        LDR     r6, [r5]
        SUB     r6, r4, r6              ; elapsed
        LDR     r1, =DEBOUNCE_SAMPLE_US
        CMP     r6, r1
        BLO     BP_done
        STR     r4, [r5]                ; last sample time = now

        BL      Inputs_ReadRaw          ; r0 = raw sample

        ; ---- require N identical samples before accepting a change ----
        LDR     r1, =g_btn_cand
        LDR     r2, [r1]
        CMP     r0, r2
        BEQ     BP_same
        STR     r0, [r1]                ; new candidate state
        LDR     r1, =g_btn_cnt
        MOV     r2, #1
        STR     r2, [r1]
        B       BP_done
BP_same
        LDR     r1, =g_btn_cnt
        LDR     r2, [r1]
        ADD     r2, r2, #1
        CMP     r2, #DEBOUNCE_STABLE_N
        MOVGT   r2, #DEBOUNCE_STABLE_N  ; cap so the counter cannot wrap
        STR     r2, [r1]
        BLT     BP_done                 ; not stable long enough yet

        ; ---- candidate accepted: latch edges against the old stable state --
        LDR     r1, =g_btn_stable
        LDR     r2, [r1]
        EORS    r3, r0, r2              ; changed bits
        BEQ     BP_done                 ; no change
        STR     r0, [r1]

        AND     r4, r3, r0              ; rising edges (release->press)
        LDR     r1, =g_btn_events
        LDR     r2, [r1]
        ORR     r2, r2, r4
        STR     r2, [r1]

        LDR     r1, =(INP_SW_BLIND1 :OR: INP_SW_BLIND2)
        AND     r3, r3, r1              ; switch flips, either direction
        LDR     r1, =g_sw_changed
        LDR     r2, [r1]
        ORR     r2, r2, r3
        STR     r2, [r1]
BP_done
        POP     {r4-r6, pc}

;------------------------------------------------------------------------------
; Buttons_TakeEvents : r0 = INP_* mask the caller cares about.
;   Out: r0 = the requested press events; those bits are cleared (consumed).
;   Clobbers: r1, r2
;------------------------------------------------------------------------------
Buttons_TakeEvents
        LDR     r1, =g_btn_events
        LDR     r2, [r1]
        AND     r0, r0, r2
        BIC     r2, r2, r0
        STR     r2, [r1]
        BX      lr

;------------------------------------------------------------------------------
; Buttons_TakeSwitchChanges : r0 = INP_* mask -> r0 = consumed change flags.
;   Clobbers: r1, r2
;------------------------------------------------------------------------------
Buttons_TakeSwitchChanges
        LDR     r1, =g_sw_changed
        LDR     r2, [r1]
        AND     r0, r0, r2
        BIC     r2, r2, r0
        STR     r2, [r1]
        BX      lr

;------------------------------------------------------------------------------
; Buttons_GetStable : r0 = current debounced INP_* state.   Clobbers: -
;------------------------------------------------------------------------------
Buttons_GetStable
        LDR     r0, =g_btn_stable
        LDR     r0, [r0]
        BX      lr

        LTORG

;------------------------------------------------------------------------------
        AREA    ButtonData, DATA, READWRITE
g_btn_stable    SPACE   4       ; accepted (debounced) input state
g_btn_cand      SPACE   4       ; candidate state being counted
g_btn_cnt       SPACE   4       ; consecutive identical samples so far
g_btn_events    SPACE   4       ; latched press events (rising edges)
g_sw_changed    SPACE   4       ; latched switch-flip flags (either edge)
g_btn_last_t    SPACE   4       ; Timer1 time of the previous sample

        END
