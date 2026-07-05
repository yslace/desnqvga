;==============================================================================
; lcd_ui.s  -  Touch-screen user interface for the hub
;
; Activity 3.  Two screens on the QVGA panel (320x240):
;
;   HOME     - live status: time, light level + category, both blind states,
;              plug state and auto/manual mode.  Touch controls: per-blind
;              UP/DOWN, blinds back to AUTO, plug toggle, plug auto-mode
;              toggle, chime test, and a button to the settings screen.
;   SETTINGS - set the clock (+1 h / +10 min), the target shot time
;              (+/-15 min), and the current month (drives the seasonal
;              blind rules).
;
; EVERY touch control dispatches into the same Automation_* / Time_* /
; Doorbell_* functions the physical buttons and switches use - the control
; logic exists exactly once, the UI is only another way in.
;
; Touch handling is edge-triggered (a held finger acts once), and the status
; redraw is rate-limited to LCD_REFRESH_US; redraws are also skipped while
; the doorbell chime is playing so the slow GLCD calls cannot distort the
; polled square wave.
;
; The QVGA board's LCD/touch is driven by the GLCD + touch-panel driver you
; already use in the DESN2000 labs.  Because each team's driver entry points
; differ slightly, the real driver is only linked when the build symbol
; USE_LCD is defined (Project > Options > Asm > Define: USE_LCD).
;
;   * DEFAULT build (USE_LCD not defined): these routines are safe no-ops, so
;     the rest of the hub (sensor, fixtures, doorbell, automation) builds and
;     runs immediately on the board with no LCD dependency.
;   * USE_LCD build: wire the IMPORTs below to your lab driver and adapt the
;     argument passing in the marked sections to match its calling
;     convention.  The driver is assumed to preserve r4-r11 (AAPCS).
;
; Provides:
;   LCD_UI_Init   - init driver, draw the static layout
;   LCD_UI_Update - refresh status text + handle one touch event per press
;==============================================================================
        AREA    LcdUiCode, CODE, READONLY
        GET     lpc2478.inc

        EXPORT  LCD_UI_Init
        EXPORT  LCD_UI_Update

;==============================================================================
        IF      :DEF: USE_LCD
;==============================================================================
; ---- Real implementation: link against your lab GLCD / touch driver. ----
; Adapt these names + argument passing to YOUR driver.                <<WIRE>>
        IMPORT  GLCD_Init
        IMPORT  GLCD_Clear              ; r0 = colour
        IMPORT  GLCD_DisplayString      ; r0 = text row, r1 = col, r2 = ASCIIZ ptr
        IMPORT  TP_Init
        IMPORT  TP_Read                 ; -> r0 = x, r1 = y, r2 = pressed(0/1)

        IMPORT  Time_GetMinutes
        IMPORT  Time_AddHour
        IMPORT  Time_Add10Min
        IMPORT  Doorbell_Chime
        IMPORT  Doorbell_Active
        IMPORT  Automation_GetPlugState
        IMPORT  Automation_GetAutoMode
        IMPORT  Automation_SetAutoMode
        IMPORT  Automation_GetBlindState
        IMPORT  Automation_SetBlindManual
        IMPORT  Automation_TogglePlug
        IMPORT  Automation_GetShotTime
        IMPORT  Automation_AdjustShotTime
        IMPORT  Automation_AdjustMonth
        IMPORT  Automation_GetMonth
        IMPORT  Automation_GetLightRaw
        IMPORT  Automation_GetLightCat

WHITE           EQU     0xFFFF
NAVY            EQU     0x000F

;------------------------------------------------------------------------------
; LCD_UI_Init
;------------------------------------------------------------------------------
LCD_UI_Init
        PUSH    {lr}
        BL      GLCD_Init
        BL      TP_Init
        MOV     r1, #0
        LDR     r0, =g_screen
        STR     r1, [r0]                ; start on the HOME screen
        LDR     r0, =g_touch_prev
        STR     r1, [r0]
        LDR     r0, =T1TC
        LDR     r0, [r0]
        LDR     r1, =g_ui_last
        STR     r0, [r1]
        BL      UI_DrawStatic
        BL      UI_DrawStatus
        POP     {pc}

;------------------------------------------------------------------------------
; LCD_UI_Update : rate-limited status refresh, then edge-triggered touch
;   dispatch against the current screen's hit-box table.
;------------------------------------------------------------------------------
LCD_UI_Update
        PUSH    {r4-r7, lr}

        ; ---- status refresh (skipped while the chime plays: GLCD is slow) --
        BL      Doorbell_Active
        CMP     r0, #0
        BNE     UIU_touch
        LDR     r0, =T1TC
        LDR     r0, [r0]
        LDR     r1, =g_ui_last
        LDR     r2, [r1]
        SUB     r2, r0, r2              ; elapsed us (wrap-safe)
        LDR     r3, =LCD_REFRESH_US
        CMP     r2, r3
        BLO     UIU_touch
        STR     r0, [r1]
        BL      UI_DrawStatus

        ; ---- touch handling (rising edge only) -----------------------------
UIU_touch
        BL      TP_Read                 ; r0 = x, r1 = y, r2 = pressed
        LDR     r3, =g_touch_prev
        LDR     r4, [r3]
        STR     r2, [r3]
        CMP     r2, #0
        BEQ     UIU_done                ; nothing touched
        CMP     r4, #0
        BNE     UIU_done                ; still holding the same touch
        MOV     r5, r0                  ; r5 = x
        MOV     r6, r1                  ; r6 = y

        LDR     r7, =tbl_home           ; pick this screen's hit-box table
        LDR     r0, =g_screen
        LDR     r0, [r0]
        CMP     r0, #0
        LDRNE   r7, =tbl_settings
UIU_scan
        LDR     r0, [r7]                ; x0 (or -1 = end of table)
        CMN     r0, #1
        BEQ     UIU_done
        LDR     r1, [r7, #4]            ; x1
        LDR     r2, [r7, #8]            ; y0
        LDR     r3, [r7, #12]           ; y1
        CMP     r5, r0
        BLT     UIU_next
        CMP     r5, r1
        BGT     UIU_next
        CMP     r6, r2
        BLT     UIU_next
        CMP     r6, r3
        BGT     UIU_next
        LDR     r0, [r7, #16]           ; handler address
        MOV     lr, pc
        BX      r0                      ; call the handler
        BL      UI_DrawStatus           ; reflect the change immediately
        B       UIU_done
UIU_next
        ADD     r7, r7, #20             ; next 5-word entry
        B       UIU_scan
UIU_done
        POP     {r4-r7, pc}

;------------------------------------------------------------------------------
; Hit-box tables: DCD x0, x1, y0, y1, handler.  Terminated by -1.     <<TUNE>>
;   Coordinates assume a 320x240 panel with (0,0) top-left; calibrate to
;   your touch driver.  Boxes match the legend rows drawn by UI_DrawStatic.
;------------------------------------------------------------------------------
tbl_home
        DCD     2,   78,  120, 155, H_B1Up          ; blind 1 up
        DCD     82,  158, 120, 155, H_B1Dn          ; blind 1 down
        DCD     162, 238, 120, 155, H_B2Up          ; blind 2 up
        DCD     242, 318, 120, 155, H_B2Dn          ; blind 2 down
        DCD     2,   158, 160, 195, H_BlAuto        ; both blinds -> AUTO
        DCD     162, 238, 160, 195, H_Plug          ; plug manual toggle
        DCD     242, 318, 160, 195, H_AutoMode      ; plug schedule on/off
        DCD     2,   158, 200, 235, H_Chime         ; doorbell chime test
        DCD     162, 318, 200, 235, H_GoSettings    ; -> settings screen
        DCD     -1

tbl_settings
        DCD     2,   158, 120, 155, H_TimeH         ; clock +1 hour
        DCD     162, 318, 120, 155, H_TimeM         ; clock +10 min
        DCD     2,   158, 160, 195, H_ShotP         ; shot time +15 min
        DCD     162, 318, 160, 195, H_ShotM         ; shot time -15 min
        DCD     2,   78,  200, 235, H_MonP          ; month +
        DCD     82,  158, 200, 235, H_MonM          ; month -
        DCD     162, 318, 200, 235, H_GoHome        ; -> home screen
        DCD     -1

;------------------------------------------------------------------------------
; Touch handlers.  Single-call handlers tail-branch (B) into the shared
; control functions; multi-step handlers save lr.  All clobber r0-r3 only.
;------------------------------------------------------------------------------
H_B1Up
        MOV     r0, #0
        MOV     r1, #BLIND_UP
        B       Automation_SetBlindManual
H_B1Dn
        MOV     r0, #0
        MOV     r1, #BLIND_DOWN
        B       Automation_SetBlindManual
H_B2Up
        MOV     r0, #1
        MOV     r1, #BLIND_UP
        B       Automation_SetBlindManual
H_B2Dn
        MOV     r0, #1
        MOV     r1, #BLIND_DOWN
        B       Automation_SetBlindManual
H_BlAuto
        PUSH    {lr}
        MOV     r0, #0
        MVN     r1, #0                  ; -1 = hand back to automation
        BL      Automation_SetBlindManual
        MOV     r0, #1
        MVN     r1, #0
        BL      Automation_SetBlindManual
        POP     {pc}
H_Plug
        B       Automation_TogglePlug   ; same routine as the physical button
H_AutoMode
        PUSH    {lr}
        BL      Automation_GetAutoMode
        EOR     r0, r0, #1
        BL      Automation_SetAutoMode
        POP     {pc}
H_Chime
        B       Doorbell_Chime
H_GoSettings
        PUSH    {lr}
        MOV     r0, #1
        LDR     r1, =g_screen
        STR     r0, [r1]
        BL      UI_DrawStatic
        POP     {pc}
H_GoHome
        PUSH    {lr}
        MOV     r0, #0
        LDR     r1, =g_screen
        STR     r0, [r1]
        BL      UI_DrawStatic
        POP     {pc}
H_TimeH
        B       Time_AddHour
H_TimeM
        B       Time_Add10Min
H_ShotP
        MOV     r0, #15
        B       Automation_AdjustShotTime
H_ShotM
        MVN     r0, #14                 ; -15
        B       Automation_AdjustShotTime
H_MonP
        MOV     r0, #1
        B       Automation_AdjustMonth
H_MonM
        MVN     r0, #0                  ; -1
        B       Automation_AdjustMonth

;------------------------------------------------------------------------------
; UI_DrawStatic : clear + title + this screen's button legend.
;   The legend text rows sit over the hit boxes above.               <<TUNE>>
;------------------------------------------------------------------------------
UI_DrawStatic
        PUSH    {lr}
        LDR     r0, =NAVY
        BL      GLCD_Clear
        MOV     r0, #0
        MOV     r1, #0
        LDR     r2, =s_title
        BL      GLCD_DisplayString
        LDR     r0, =g_screen
        LDR     r0, [r0]
        CMP     r0, #0
        BNE     UDS_set
        MOV     r0, #7
        MOV     r1, #0
        LDR     r2, =s_leg_h1
        BL      GLCD_DisplayString
        MOV     r0, #8
        MOV     r1, #0
        LDR     r2, =s_leg_h2
        BL      GLCD_DisplayString
        MOV     r0, #9
        MOV     r1, #0
        LDR     r2, =s_leg_h3
        BL      GLCD_DisplayString
        POP     {pc}
UDS_set
        MOV     r0, #7
        MOV     r1, #0
        LDR     r2, =s_leg_s1
        BL      GLCD_DisplayString
        MOV     r0, #8
        MOV     r1, #0
        LDR     r2, =s_leg_s2
        BL      GLCD_DisplayString
        MOV     r0, #9
        MOV     r1, #0
        LDR     r2, =s_leg_s3
        BL      GLCD_DisplayString
        POP     {pc}

;------------------------------------------------------------------------------
; UI_DrawStatus : rebuild and draw the live status lines for this screen.
;------------------------------------------------------------------------------
UI_DrawStatus
        PUSH    {r4-r5, lr}
        LDR     r0, =g_screen
        LDR     r0, [r0]
        CMP     r0, #0
        BNE     UDSt_set

        ; ================= HOME =================
        ; row 2: "TIME  HH:MM"
        BL      Time_GetMinutes
        MOV     r4, r0
        LDR     r1, =g_line
        LDR     r2, =s_time
        BL      PutStr
        MOV     r0, r4
        BL      PutHHMM
        BL      Term0
        MOV     r0, #2
        MOV     r1, #0
        LDR     r2, =g_line
        BL      GLCD_DisplayString

        ; row 3: "LIGHT NNNN CAT"
        BL      Automation_GetLightRaw
        MOV     r4, r0
        BL      Automation_GetLightCat
        MOV     r5, r0
        LDR     r1, =g_line
        LDR     r2, =s_light
        BL      PutStr
        MOV     r0, r4
        BL      Put4Dec
        MOV     r3, #' '
        STRB    r3, [r1], #1
        LDR     r2, =s_cats
        ADD     r2, r2, r5, LSL #2      ; 4-byte stride per category name
        BL      Put3
        BL      Term0
        MOV     r0, #3
        MOV     r1, #0
        LDR     r2, =g_line
        BL      GLCD_DisplayString

        ; row 4: "B1 xxx B2 xxx"
        MOV     r0, #0
        BL      Automation_GetBlindState
        MOV     r4, r0
        MOV     r0, #1
        BL      Automation_GetBlindState
        MOV     r5, r0
        LDR     r1, =g_line
        LDR     r2, =s_b1
        BL      PutStr
        LDR     r2, =s_blst
        ADD     r2, r2, r4, LSL #2
        BL      Put3
        LDR     r2, =s_b2
        BL      PutStr
        LDR     r2, =s_blst
        ADD     r2, r2, r5, LSL #2
        BL      Put3
        BL      Term0
        MOV     r0, #4
        MOV     r1, #0
        LDR     r2, =g_line
        BL      GLCD_DisplayString

        ; row 5: "PLUG ON  AUTO" / "PLUG OFF MAN "
        BL      Automation_GetPlugState
        MOV     r4, r0
        BL      Automation_GetAutoMode
        MOV     r5, r0
        LDR     r1, =g_line
        LDR     r2, =s_plug
        BL      PutStr
        CMP     r4, #0
        LDREQ   r2, =s_off
        LDRNE   r2, =s_on
        BL      PutStr
        CMP     r5, #0
        LDREQ   r2, =s_man
        LDRNE   r2, =s_auto
        BL      PutStr
        BL      Term0
        MOV     r0, #5
        MOV     r1, #0
        LDR     r2, =g_line
        BL      GLCD_DisplayString
        POP     {r4-r5, pc}

        ; ================ SETTINGS ================
UDSt_set
        ; row 2: "TIME  HH:MM" (current clock, adjusted by the buttons below)
        BL      Time_GetMinutes
        MOV     r4, r0
        LDR     r1, =g_line
        LDR     r2, =s_time
        BL      PutStr
        MOV     r0, r4
        BL      PutHHMM
        BL      Term0
        MOV     r0, #2
        MOV     r1, #0
        LDR     r2, =g_line
        BL      GLCD_DisplayString

        ; row 3: "SHOT  HH:MM" (target shot time for the espresso schedule)
        BL      Automation_GetShotTime
        MOV     r4, r0
        LDR     r1, =g_line
        LDR     r2, =s_shot
        BL      PutStr
        MOV     r0, r4
        BL      PutHHMM
        BL      Term0
        MOV     r0, #3
        MOV     r1, #0
        LDR     r2, =g_line
        BL      GLCD_DisplayString

        ; row 4: "MONTH NN" (drives the seasonal blind rules)
        BL      Automation_GetMonth
        MOV     r4, r0
        LDR     r1, =g_line
        LDR     r2, =s_month
        BL      PutStr
        MOV     r0, r4
        BL      Put2Dec
        BL      Term0
        MOV     r0, #4
        MOV     r1, #0
        LDR     r2, =g_line
        BL      GLCD_DisplayString
        POP     {r4-r5, pc}

;------------------------------------------------------------------------------
; Tiny text-building helpers.  Convention: r1 = cursor into g_line (advances),
; r2 = source pointer where applicable.  No division anywhere (ARM7 has none):
; decimal digits come from repeated subtraction.
;------------------------------------------------------------------------------
; PutStr : append the ASCIIZ string at r2.  Clobbers: r2, r3
PutStr
        LDRB    r3, [r2], #1
        CMP     r3, #0
        STRNEB  r3, [r1], #1
        BNE     PutStr
        BX      lr

; Put3 : append exactly 3 characters from r2 (category/state name tables).
;        Clobbers: r2, r3
Put3
        LDRB    r3, [r2], #1
        STRB    r3, [r1], #1
        LDRB    r3, [r2], #1
        STRB    r3, [r1], #1
        LDRB    r3, [r2], #1
        STRB    r3, [r1], #1
        BX      lr

; Put2Dec : append r0 (0..99) as two decimal digits.  Clobbers: r0, r2
Put2Dec
        MOV     r2, #0
P2_tens
        CMP     r0, #10
        SUBGE   r0, r0, #10
        ADDGE   r2, r2, #1
        BGE     P2_tens
        ADD     r2, r2, #'0'
        STRB    r2, [r1], #1
        ADD     r0, r0, #'0'
        STRB    r0, [r1], #1
        BX      lr

; Put4Dec : append r0 (0..9999) as four decimal digits.  Clobbers: r0, r2
Put4Dec
        PUSH    {r4, lr}
        LDR     r4, =1000
        BL      PD_div
        MOV     r4, #100
        BL      PD_div
        MOV     r4, #10
        BL      PD_div
        ADD     r0, r0, #'0'
        STRB    r0, [r1], #1
        POP     {r4, pc}
PD_div
        MOV     r2, #0
PDd_t
        CMP     r0, r4
        SUBGE   r0, r0, r4
        ADDGE   r2, r2, #1
        BGE     PDd_t
        ADD     r2, r2, #'0'
        STRB    r2, [r1], #1
        BX      lr

; PutHHMM : append r0 (minutes-of-day) as "HH:MM".  Clobbers: r0, r2, r3
PutHHMM
        PUSH    {r4, lr}
        MOV     r4, #0
PH_div
        CMP     r0, #60
        SUBGE   r0, r0, #60
        ADDGE   r4, r4, #1
        BGE     PH_div
        MOV     r3, r0                  ; r3 = minutes (survives Put2Dec)
        MOV     r0, r4
        BL      Put2Dec                 ; hours
        MOV     r2, #':'
        STRB    r2, [r1], #1
        MOV     r0, r3
        BL      Put2Dec                 ; minutes
        POP     {r4, pc}

; Term0 : NUL-terminate the built line.  Clobbers: r3
Term0
        MOV     r3, #0
        STRB    r3, [r1]
        BX      lr

;------------------------------------------------------------------------------
; Text.  Fixed-width name tables use a 4-byte stride so an index selects an
; entry with a shift, no multiply.
;------------------------------------------------------------------------------
s_title  DCB    "COTTAGE HUB", 0
s_time   DCB    "TIME  ", 0
s_light  DCB    "LIGHT ", 0
s_b1     DCB    "B1 ", 0
s_b2     DCB    " B2 ", 0
s_plug   DCB    "PLUG ", 0
s_shot   DCB    "SHOT  ", 0
s_month  DCB    "MONTH ", 0
s_on     DCB    "ON  ", 0
s_off    DCB    "OFF ", 0
s_auto   DCB    "AUTO", 0
s_man    DCB    "MAN ", 0
        ALIGN
s_cats   DCB    "DRK", 0                ; LIGHT_CAT_DARK   = 0
         DCB    "DIM", 0                ; LIGHT_CAT_DIM    = 1
         DCB    "BRT", 0                ; LIGHT_CAT_BRIGHT = 2
        ALIGN
s_blst   DCB    "UP ", 0                ; BLIND_UP   = 0
         DCB    "MID", 0                ; BLIND_MID  = 1
         DCB    "DN ", 0                ; BLIND_DOWN = 2
        ALIGN
s_leg_h1 DCB    "B1UP B1DN B2UP B2DN", 0
s_leg_h2 DCB    "BLIND-AUTO PLUG PAUTO", 0
s_leg_h3 DCB    "CHIME      SETUP", 0
s_leg_s1 DCB    "TIME+1H    TIME+10M", 0
s_leg_s2 DCB    "SHOT+15    SHOT-15", 0
s_leg_s3 DCB    "MON+ MON-  BACK", 0
        ALIGN

        LTORG

        AREA    LcdUiData, DATA, READWRITE
g_touch_prev    SPACE   4       ; previous touch pressed-state (edge detect)
g_screen        SPACE   4       ; 0 = home, 1 = settings
g_ui_last       SPACE   4       ; Timer1 time of the last status redraw
g_line          SPACE   40      ; scratch buffer for one status line

;==============================================================================
        ELSE
;==============================================================================
; ---- Default stub build: no LCD driver linked, hub still runs. ----
LCD_UI_Init
        BX      lr
LCD_UI_Update
        BX      lr
;==============================================================================
        ENDIF
;==============================================================================
        END
