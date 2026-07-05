;==============================================================================
; fixtures.s  -  Raw I/O drivers for the simulated home fixtures
;
; The real 240V appliances are mimicked on the DESN2000 Daughter Board:
;   * two window blinds    -> two tricolour LEDs (UP=red, MID=green, DOWN=blue)
;   * ambient light level  -> 8-bar LED ladder (more bars = brighter)
;   * smart power plug     -> one indicator LED (coffee-machine simulation)
;   * doorbell + plug      -> two push buttons        (raw, debounced upstream)
;   * blind manual control -> two toggle switches     (raw, debounced upstream)
;
; This module is the ONLY place that touches the fixture GPIO registers;
; buttons.s layers debouncing on top of Inputs_ReadRaw, and everything else
; works with clean logical states.
;
; Provides:
;   Fixtures_Init     - pin functions, directions, all LEDs off
;   Blind_SetState    - r0 = blind id (0/1), r1 = BLIND_UP/MID/DOWN
;   SmartPlug_Set     - r0 = 0 (off) / non-zero (on)
;   LEDLadder_Show    - r0 = light level 0..1023 -> bar graph
;   Inputs_ReadRaw    - r0 = raw INP_* bitmask (no debounce)
;==============================================================================
        AREA    FixtureCode, CODE, READONLY
        GET     lpc2478.inc

        EXPORT  Fixtures_Init
        EXPORT  Blind_SetState
        EXPORT  SmartPlug_Set
        EXPORT  LEDLadder_Show
        EXPORT  Inputs_ReadRaw

;------------------------------------------------------------------------------
; Fixtures_Init
;   In: -   Out: -   Clobbers: r0-r2
;------------------------------------------------------------------------------
Fixtures_Init
        ; ---- pin functions: everything we drive/read here is plain GPIO ----
        LDR     r0, =PINSEL0
        LDR     r1, [r0]
        LDR     r2, =PINSEL0_GPIO_MASK  ; ladder P0.1-8 + buttons P0.10/11
        BIC     r1, r1, r2
        STR     r1, [r0]
        LDR     r0, =PINSEL1
        LDR     r1, [r0]
        LDR     r2, =PINSEL1_P022_MASK  ; ladder enable P0.22
        BIC     r1, r1, r2
        STR     r1, [r0]
        LDR     r0, =PINSEL3
        LDR     r1, [r0]
        LDR     r2, =PINSEL3_SW_MASK    ; blind toggle switches P1.16/17
        BIC     r1, r1, r2
        STR     r1, [r0]
        LDR     r0, =PINSEL7
        LDR     r1, [r0]
        LDR     r2, =PINSEL7_LED_MASK   ; tricolour LEDs P3.16-21
        BIC     r1, r1, r2
        STR     r1, [r0]

        ; ---- directions ----
        LDR     r0, =FIO0DIR
        LDR     r1, [r0]
        LDR     r2, =(LADDER_MASK :OR: LADDER_EN)
        ORR     r1, r1, r2              ; ladder pins are outputs
        LDR     r2, =BTN0_MASK
        BIC     r1, r1, r2              ; buttons are inputs
        STR     r1, [r0]
        LDR     r0, =FIO1DIR
        LDR     r1, [r0]
        LDR     r2, =SW1_MASK
        BIC     r1, r1, r2              ; switches are inputs
        STR     r1, [r0]
        LDR     r0, =FIO3DIR
        LDR     r1, [r0]
        LDR     r2, =BLIND_LED_MASK
        ORR     r1, r1, r2              ; blind LEDs are outputs
        STR     r1, [r0]
        LDR     r0, =FIO2DIR
        LDR     r1, [r0]
        LDR     r2, =PLUG_LED
        ORR     r1, r1, r2              ; plug LED is an output
        STR     r1, [r0]

        ; ---- initial LED state: everything off, ladder enabled ----
        LDR     r0, =FIO3CLR
        LDR     r1, =BLIND_LED_MASK
        STR     r1, [r0]
        LDR     r0, =FIO2CLR
        LDR     r1, =PLUG_LED
        STR     r1, [r0]
        LDR     r0, =FIO0CLR
        LDR     r1, =LADDER_MASK
        STR     r1, [r0]
        LDR     r0, =FIO0SET
        LDR     r1, =LADDER_EN          ; assumed active-HIGH enable  <<VERIFY>>
        STR     r1, [r0]
        LDR     r0, =g_ladder_last
        MVN     r1, #0                  ; force first LEDLadder_Show to draw
        STR     r1, [r0]
        BX      lr

;------------------------------------------------------------------------------
; Blind_SetState : r0 = blind id (0 or 1), r1 = state (BLIND_UP/MID/DOWN)
;   Clears all three colour bits for that blind, then lights exactly one.
;   Clobbers: r4-r6 saved; flags.
;------------------------------------------------------------------------------
Blind_SetState
        PUSH    {r4-r6, lr}
        LDR     r5, =FIO3SET
        LDR     r6, =FIO3CLR
        CMP     r0, #0
        BNE     Blind1

        ; ---- Blind 0 ----
        LDR     r4, =(BL1_R:OR:BL1_G:OR:BL1_B)
        STR     r4, [r6]                ; clear all three colours
        CMP     r1, #BLIND_UP
        LDREQ   r4, =BL1_R
        CMP     r1, #BLIND_MID
        LDREQ   r4, =BL1_G
        CMP     r1, #BLIND_DOWN
        LDREQ   r4, =BL1_B
        STR     r4, [r5]                ; light the selected colour
        POP     {r4-r6, pc}

        ; ---- Blind 1 ----
Blind1
        LDR     r4, =(BL2_R:OR:BL2_G:OR:BL2_B)
        STR     r4, [r6]
        CMP     r1, #BLIND_UP
        LDREQ   r4, =BL2_R
        CMP     r1, #BLIND_MID
        LDREQ   r4, =BL2_G
        CMP     r1, #BLIND_DOWN
        LDREQ   r4, =BL2_B
        STR     r4, [r5]
        POP     {r4-r6, pc}

;------------------------------------------------------------------------------
; SmartPlug_Set : r0 = 0 -> off, non-zero -> on.   Clobbers: r1, r2
;------------------------------------------------------------------------------
SmartPlug_Set
        LDR     r1, =PLUG_LED
        CMP     r0, #0
        LDRNE   r2, =FIO2SET
        LDREQ   r2, =FIO2CLR
        STR     r1, [r2]
        BX      lr

;------------------------------------------------------------------------------
; LEDLadder_Show : r0 = light level 0..1023.   Clobbers: r1-r3
;   Bar graph: bars lit = level/128 (0..7 bars), all 8 bars from level 960 up,
;   so pitch dark shows no bars and full sun shows the whole ladder.
;   Skips the GPIO writes when the picture hasn't changed (no flicker).
;------------------------------------------------------------------------------
LEDLadder_Show
        LDR     r2, =0x3C0              ; 960
        CMP     r0, r2
        MOVGE   r1, #8
        MOVLT   r1, r0, LSR #7          ; bars = level / 128
        MOV     r2, #1
        MOV     r2, r2, LSL r1
        SUB     r2, r2, #1              ; low <bars> bits set
        MOV     r2, r2, LSL #LADDER_SHIFT

        LDR     r1, =g_ladder_last
        LDR     r3, [r1]
        CMP     r2, r3
        BXEQ    lr                      ; unchanged -> nothing to do
        STR     r2, [r1]

        LDR     r1, =FIO0CLR
        LDR     r3, =LADDER_MASK
        STR     r3, [r1]
        LDR     r1, =FIO0SET
        STR     r2, [r1]
        BX      lr

;------------------------------------------------------------------------------
; Inputs_ReadRaw : r0 = current raw inputs as INP_* bits.   Clobbers: r1, r2
;   Buttons P0.10/11 and switches P1.16/17 are assumed active LOW  <<VERIFY>>;
;   the result is normalised so a SET bit always means pressed / "up" position.
;------------------------------------------------------------------------------
Inputs_ReadRaw
        ; push buttons (P0.10 -> INP bit0, P0.11 -> INP bit1)
        LDR     r1, =FIO0PIN
        LDR     r0, [r1]
        MVN     r0, r0                  ; active-low -> active-high
        MOV     r0, r0, LSR #10
        AND     r0, r0, #3
        ; blind toggle switches (P1.16 -> INP bit2, P1.17 -> INP bit3)
        LDR     r1, =FIO1PIN
        LDR     r2, [r1]
        MVN     r2, r2
        MOV     r2, r2, LSR #16
        AND     r2, r2, #3
        ORR     r0, r0, r2, LSL #2
        BX      lr

        LTORG

;------------------------------------------------------------------------------
        AREA    FixtureData, DATA, READWRITE
g_ladder_last   SPACE   4       ; last bar pattern written to the ladder

        END
