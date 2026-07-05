;==============================================================================
; timekeeping.s  -  System time and timing services
;
; Design choice (Activity 2 offers RTC or a general timer): a Timer0 tick
; with a software HH:MM:SS clock is used instead of the RTC peripheral, so
; the project needs NO register addresses beyond those already verified in
; lpc2478.inc and no interrupt/VIC setup.  The rest of the code only ever
; calls the Time_* interface, so swapping in the RTC later would touch only
; this file.
;
; Timer0 is configured to set its MR0 match flag once per TICK_MS
; (1000 ms normally; shorter when DEMO_TIME_SCALE > 1 so schedules can be
; demonstrated live at high speed).  The flag is POLLED - no ISR.
;
; Provides:
;   Time_Init        - start Timer0 (clock tick) and Timer1 (us counter)
;   Time_Update      - call often from the super-loop; advances HH:MM:SS
;   Time_Set         - r0 = hour, r1 = minute (seconds reset to 0)
;   Time_AddHour     - +1 hour, wraps at 24        (for the LCD settings UI)
;   Time_Add10Min    - +10 minutes, carries into the hour
;   Time_GetHour     - r0 = current hour (0..23)
;   Time_GetMin      - r0 = current minute (0..59)
;   Time_GetMinutes  - r0 = minutes-of-day (hour*60 + minute)
;   Delay_us         - busy-wait r0 microseconds (Timer1, wrap-safe)
;==============================================================================
        AREA    TimeCode, CODE, READONLY
        GET     lpc2478.inc

        EXPORT  Time_Init
        EXPORT  Time_Update
        EXPORT  Time_Set
        EXPORT  Time_AddHour
        EXPORT  Time_Add10Min
        EXPORT  Time_GetHour
        EXPORT  Time_GetMin
        EXPORT  Time_GetMinutes
        EXPORT  Delay_us

;------------------------------------------------------------------------------
; Time_Init : start the timers and load a default time of 07:00:00.
;   In: -   Out: -   Clobbers: r0-r3
;------------------------------------------------------------------------------
Time_Init
        ; power up Timer0 and Timer1
        LDR     r0, =PCONP
        LDR     r1, [r0]
        ORR     r1, r1, #PCTIM0
        ORR     r1, r1, #PCTIM1
        STR     r1, [r0]

        ; ---- Timer0: 1 ms prescale, match flag every TICK_MS ----
        LDR     r0, =T0TCR
        MOV     r1, #2                  ; reset counters
        STR     r1, [r0]
        LDR     r0, =T0PR
        LDR     r1, =T0_PRESCALE        ; PC ticks every 1 ms
        STR     r1, [r0]
        LDR     r0, =T0MR0
        LDR     r1, =TICK_MS            ; one "second" of wall-clock time
        STR     r1, [r0]
        LDR     r0, =T0MCR
        MOV     r1, #3                  ; on MR0: set IR flag (bit0) + reset TC (bit1)
        STR     r1, [r0]
        LDR     r0, =T0IR
        MOV     r1, #0xFF               ; clear any pending flags
        STR     r1, [r0]
        LDR     r0, =T0TCR
        MOV     r1, #1                  ; enable Timer0
        STR     r1, [r0]

        ; ---- Timer1: free-running microsecond counter (debounce, chime,
        ;      LCD refresh pacing and Delay_us all read T1TC directly) ----
        LDR     r0, =T1TCR
        MOV     r1, #2                  ; reset
        STR     r1, [r0]
        LDR     r0, =T1PR
        LDR     r1, =T1_PRESCALE        ; TC ticks every 1 us
        STR     r1, [r0]
        LDR     r0, =T1TCR
        MOV     r1, #1                  ; enable, free-running
        STR     r1, [r0]

        ; default clock = 07:00:00 (no network time source; settable via LCD)
        MOV     r0, #7
        MOV     r1, #0
        B       Time_Set                ; tail call, returns to our caller

;------------------------------------------------------------------------------
; Time_Set : r0 = hour, r1 = minute.  Seconds reset to 0.   Clobbers: r2, r3
;------------------------------------------------------------------------------
Time_Set
        LDR     r2, =g_hour
        STR     r0, [r2]
        LDR     r2, =g_min
        STR     r1, [r2]
        LDR     r2, =g_sec
        MOV     r3, #0
        STR     r3, [r2]
        BX      lr

;------------------------------------------------------------------------------
; Time_AddHour : advance the clock one hour (wraps at 24).   Clobbers: r0, r1
;------------------------------------------------------------------------------
Time_AddHour
        LDR     r1, =g_hour
        LDR     r0, [r1]
        ADD     r0, r0, #1
        CMP     r0, #24
        MOVGE   r0, #0
        STR     r0, [r1]
        BX      lr

;------------------------------------------------------------------------------
; Time_Add10Min : advance the clock ten minutes (carries into the hour).
;   Clobbers: r0, r1
;------------------------------------------------------------------------------
Time_Add10Min
        LDR     r1, =g_min
        LDR     r0, [r1]
        ADD     r0, r0, #10
        CMP     r0, #60
        STRLT   r0, [r1]
        BXLT    lr
        SUB     r0, r0, #60
        STR     r0, [r1]
        B       Time_AddHour

;------------------------------------------------------------------------------
; Time_Update : if a wall-clock second has elapsed, advance HH:MM:SS.
;   In: -   Out: -   Clobbers: r0, r1
;------------------------------------------------------------------------------
Time_Update
        LDR     r0, =T0IR
        LDR     r1, [r0]
        TST     r1, #1                  ; MR0 match flag set?
        BXEQ    lr                      ; no tick yet -> return
        MOV     r1, #1
        STR     r1, [r0]                ; write-1-to-clear the flag

        ; seconds++
        LDR     r0, =g_sec
        LDR     r1, [r0]
        ADD     r1, r1, #1
        CMP     r1, #60
        STRLT   r1, [r0]
        BXLT    lr
        MOV     r1, #0
        STR     r1, [r0]                ; sec = 0

        ; minutes++
        LDR     r0, =g_min
        LDR     r1, [r0]
        ADD     r1, r1, #1
        CMP     r1, #60
        STRLT   r1, [r0]
        BXLT    lr
        MOV     r1, #0
        STR     r1, [r0]                ; min = 0
        B       Time_AddHour            ; hours++ (wraps at midnight)

;------------------------------------------------------------------------------
; Time_GetHour : r0 = hour (0..23).   Clobbers: -
;------------------------------------------------------------------------------
Time_GetHour
        LDR     r0, =g_hour
        LDR     r0, [r0]
        BX      lr

;------------------------------------------------------------------------------
; Time_GetMin : r0 = minute (0..59).   Clobbers: -
;------------------------------------------------------------------------------
Time_GetMin
        LDR     r0, =g_min
        LDR     r0, [r0]
        BX      lr

;------------------------------------------------------------------------------
; Time_GetMinutes : r0 = minutes-of-day = hour*60 + minute.   Clobbers: r1, r2
;------------------------------------------------------------------------------
Time_GetMinutes
        LDR     r0, =g_hour
        LDR     r0, [r0]
        MOV     r1, #60
        MUL     r2, r1, r0              ; r2 = hour*60   (Rd != Rm on ARMv4)
        LDR     r0, =g_min
        LDR     r0, [r0]
        ADD     r0, r0, r2
        BX      lr

;------------------------------------------------------------------------------
; Delay_us : busy-wait r0 microseconds using Timer1's free-running TC.
;   Wrap-safe (uses unsigned subtraction).   Clobbers: r1-r3
;------------------------------------------------------------------------------
Delay_us
        LDR     r1, =T1TC
        LDR     r2, [r1]                ; start count
Delay_wait
        LDR     r3, [r1]
        SUB     r3, r3, r2              ; elapsed
        CMP     r3, r0
        BLO     Delay_wait
        BX      lr

        LTORG

;------------------------------------------------------------------------------
        AREA    TimeData, DATA, READWRITE
g_hour  SPACE   4
g_min   SPACE   4
g_sec   SPACE   4

        END
