;==============================================================================
; automation.s  -  Home-automation "smarts" (energy-minimising algorithms)
;
; The cottage is in alpine Jindabyne: occupied occasionally, big seasonal
; temperature swings (brief Fig. 2: Jul high 8degC .. Jan high 24degC), and
; the goal is to cut energy use while staying effortless for the user.
; Inputs available: light sensor, wall clock, current month.
;
;  BLINDS (passive thermal + lighting control, per season):
;    * Any season, night (by clock) -> DOWN: insulate the glazing and retain
;      heat overnight (even summer nights are ~10 degC up here); privacy.
;    * WINTER (Jun-Aug, highs <= 9 degC):
;        day + BRIGHT -> UP   (free passive-solar heating + daylight)
;        day + DIM    -> MID  (some daylight, less glass heat loss)
;        day + DARK   -> DOWN (heavy cloud: nothing to gain, insulate)
;    * SUMMER (Dec-Feb, highs >= 22 degC):
;        midday (10-16 h) + BRIGHT -> DOWN (block solar gain, cut cooling)
;        otherwise day             -> UP unless DARK (mornings/evenings are
;                                     mild; admit light)
;    * SHOULDER months: light-only rule (BRIGHT->UP, DIM->MID, DARK->DOWN).
;    All thresholds are named constants in lpc2478.inc.
;
;  SMART PLUG (espresso machine pre-heat, brief: the E61 group head must be
;  at temperature BEFORE the user pulls a shot):
;    * The user sets a target shot time on the LCD (default 07:00).
;    * PREHEAT_MINUTES before it, the plug switches ON automatically.
;    * IDLE_TIMEOUT_MINUTES after it, the plug switches OFF again UNLESS the
;      user touched the plug manually - so a machine nobody used never heats
;      an empty cottage, which is the brief's energy-saving goal.
;    * The physical plug button ALWAYS toggles the plug immediately,
;      whatever the schedule thinks.  Automatic scheduling can be disabled
;      entirely from the LCD (auto-mode off).
;
;  MANUAL ALWAYS WINS:
;    * Flipping a blind's toggle switch puts THAT blind into manual mode at
;      the switch's position (up/down); the LCD "blinds auto" control hands
;      it back to the automation.
;    * The schedule only acts at its two event minutes, so a manual plug
;      toggle is never fought by the automation in between.
;
; Provides (super-loop):
;   Automation_Init / Automation_Update
; Provides (shared by the LCD touch path AND the physical-button path, so
; control logic is never duplicated):
;   Automation_TogglePlug                       - manual plug toggle
;   Automation_SetBlindManual : r0=id, r1=state(0..2) or -1 for AUTO
;   Automation_SetAutoMode    : r0 = 0/1        Automation_GetAutoMode -> r0
;   Automation_GetPlugState  -> r0 = 0/1
;   Automation_GetBlindState  : r0 = id -> r0 = BLIND_UP/MID/DOWN
;   Automation_GetShotTime   -> r0 = minutes-of-day
;   Automation_AdjustShotTime : r0 = signed minutes delta (wraps at midnight)
;   Automation_AdjustMonth    : r0 = +1/-1 (wraps 1..12)
;   Automation_GetMonth      -> r0 = 1..12
;   Automation_GetLightRaw   -> r0 = 0..1023 (last reading, for the LCD)
;   Automation_GetLightCat   -> r0 = LIGHT_CAT_*
;==============================================================================
        AREA    AutomationCode, CODE, READONLY
        GET     lpc2478.inc

        IMPORT  Buttons_TakeEvents
        IMPORT  Buttons_TakeSwitchChanges
        IMPORT  Buttons_GetStable
        IMPORT  LightSensor_Read
        IMPORT  LightSensor_Category
        IMPORT  Blind_SetState
        IMPORT  SmartPlug_Set
        IMPORT  LEDLadder_Show
        IMPORT  Time_GetHour
        IMPORT  Time_GetMinutes

        EXPORT  Automation_Init
        EXPORT  Automation_Update
        EXPORT  Automation_TogglePlug
        EXPORT  Automation_SetBlindManual
        EXPORT  Automation_SetAutoMode
        EXPORT  Automation_GetAutoMode
        EXPORT  Automation_GetPlugState
        EXPORT  Automation_GetBlindState
        EXPORT  Automation_GetShotTime
        EXPORT  Automation_AdjustShotTime
        EXPORT  Automation_AdjustMonth
        EXPORT  Automation_GetMonth
        EXPORT  Automation_GetLightRaw
        EXPORT  Automation_GetLightCat

;------------------------------------------------------------------------------
; Automation_Init : plug off, schedule armed, blinds in AUTO.
;   In: -   Out: -   Clobbers: r0, r1
;------------------------------------------------------------------------------
Automation_Init
        MOV     r1, #1
        LDR     r0, =g_auto_mode        ; scheduling enabled by default
        STR     r1, [r0]
        MOV     r1, #0
        LDR     r0, =g_plug_on
        STR     r1, [r0]
        LDR     r0, =g_manual_used
        STR     r1, [r0]
        LDR     r0, =g_light_raw
        STR     r1, [r0]
        LDR     r0, =g_light_cat
        STR     r1, [r0]
        LDR     r0, =g_blind0_state
        STR     r1, [r0]
        LDR     r0, =g_blind1_state
        STR     r1, [r0]
        MVN     r1, #0                  ; -1
        LDR     r0, =g_sched_last
        STR     r1, [r0]                ; no minute processed yet
        LDR     r0, =g_blind0_manual
        STR     r1, [r0]                ; -1 = AUTO
        LDR     r0, =g_blind1_manual
        STR     r1, [r0]
        LDR     r1, =SHOT_DEFAULT_MIN
        LDR     r0, =g_shot_min
        STR     r1, [r0]
        MOV     r1, #DEFAULT_MONTH
        LDR     r0, =g_month
        STR     r1, [r0]
        BX      lr

;------------------------------------------------------------------------------
; Automation_Update : run every super-loop pass.
;   In: -   Out: -   Clobbers: r0-r3 (r4-r8 saved)
;------------------------------------------------------------------------------
Automation_Update
        PUSH    {r4-r8, lr}

        ; ---- 1. plug button: a debounced press toggles the plug ------------
        LDR     r0, =INP_PLUG
        BL      Buttons_TakeEvents
        CMP     r0, #0
        BLNE    Automation_TogglePlug

        ; ---- 2. blind toggle switches: a flip = manual override ------------
        LDR     r0, =(INP_SW_BLIND1 :OR: INP_SW_BLIND2)
        BL      Buttons_TakeSwitchChanges
        MOVS    r4, r0                  ; r4 = which switches flipped
        BEQ     AU_sched
        BL      Buttons_GetStable
        MOV     r5, r0                  ; r5 = current switch positions
        TST     r4, #INP_SW_BLIND1
        BEQ     AU_sw2
        TST     r5, #INP_SW_BLIND1      ; position: set = "up"
        MOVNE   r1, #BLIND_UP
        MOVEQ   r1, #BLIND_DOWN
        MOV     r0, #0
        BL      Automation_SetBlindManual
AU_sw2
        TST     r4, #INP_SW_BLIND2
        BEQ     AU_sched
        TST     r5, #INP_SW_BLIND2
        MOVNE   r1, #BLIND_UP
        MOVEQ   r1, #BLIND_DOWN
        MOV     r0, #1
        BL      Automation_SetBlindManual

        ; ---- 3. plug schedule: two events, each processed once per minute --
AU_sched
        BL      Time_GetMinutes         ; r0 = current minutes-of-day
        LDR     r1, =g_sched_last
        LDR     r2, [r1]
        CMP     r0, r2
        BEQ     AU_apply                ; this minute already processed
        STR     r0, [r1]
        MOV     r4, r0                  ; r4 = current minute
        LDR     r1, =g_auto_mode
        LDR     r1, [r1]
        CMP     r1, #0
        BEQ     AU_apply                ; scheduling disabled

        LDR     r5, =g_shot_min
        LDR     r5, [r5]                ; r5 = target shot time

        ; ON event at (shot - PREHEAT_MINUTES), wrapped past midnight
        LDR     r1, =PREHEAT_MINUTES
        SUB     r6, r5, r1
        CMP     r6, #0
        LDRLT   r1, =MINUTES_PER_DAY
        ADDLT   r6, r6, r1
        CMP     r4, r6
        BNE     AU_offchk
        MOV     r0, #1
        LDR     r1, =g_plug_on
        STR     r0, [r1]                ; start pre-heating
        MOV     r0, #0
        LDR     r1, =g_manual_used
        STR     r0, [r1]                ; new brewing window: nobody used it yet

        ; OFF event at (shot + IDLE_TIMEOUT), only if the user never touched it
AU_offchk
        LDR     r1, =IDLE_TIMEOUT_MINUTES
        ADD     r6, r5, r1
        LDR     r1, =MINUTES_PER_DAY
        CMP     r6, r1
        SUBGE   r6, r6, r1
        CMP     r4, r6
        BNE     AU_apply
        LDR     r1, =g_manual_used
        LDR     r1, [r1]
        CMP     r1, #0
        BNE     AU_apply                ; user took over -> leave it alone
        MOV     r0, #0
        LDR     r1, =g_plug_on
        STR     r0, [r1]                ; unused machine -> stop heating

        ; ---- 4. drive the plug LED from the decided state -------------------
AU_apply
        LDR     r0, =g_plug_on
        LDR     r0, [r0]
        BL      SmartPlug_Set

        ; ---- 5. light sensor -> ladder bar graph + category cache ----------
        BL      LightSensor_Read        ; r0 = raw 0..1023
        LDR     r1, =g_light_raw
        STR     r0, [r1]
        MOV     r7, r0
        BL      LEDLadder_Show          ; bar graph shows the raw level
        MOV     r0, r7
        BL      LightSensor_Category
        LDR     r1, =g_light_cat
        STR     r0, [r1]
        MOV     r8, r0                  ; r8 = DARK/DIM/BRIGHT for the blinds

        ; ---- 6. blinds: one automatic decision, manual override per blind --
        BL      Blind_AutoState         ; r0 = suggested state (uses r8)
        MOV     r6, r0
        ; blind 0
        LDR     r2, =g_blind0_manual
        LDR     r3, [r2]
        CMN     r3, #1                  ; AUTO?
        MOVEQ   r1, r6
        MOVNE   r1, r3
        LDR     r2, =g_blind0_state
        STR     r1, [r2]                ; remember for the LCD read-out
        MOV     r0, #0
        BL      Blind_SetState
        ; blind 1
        LDR     r2, =g_blind1_manual
        LDR     r3, [r2]
        CMN     r3, #1
        MOVEQ   r1, r6
        MOVNE   r1, r3
        LDR     r2, =g_blind1_state
        STR     r1, [r2]
        MOV     r0, #1
        BL      Blind_SetState

        POP     {r4-r8, pc}

;------------------------------------------------------------------------------
; Blind_AutoState : the seasonal decision described in the file header.
;   In: r8 = light category   Out: r0 = BLIND_UP/MID/DOWN   Clobbers: r0 (r4 saved)
;------------------------------------------------------------------------------
Blind_AutoState
        PUSH    {r4, lr}
        BL      Time_GetHour
        MOV     r4, r0                  ; r4 = hour
        CMP     r4, #DAY_START_HOUR
        BLT     BA_down                 ; night -> insulate + privacy
        CMP     r4, #DAY_END_HOUR
        BGE     BA_down

        LDR     r0, =g_month
        LDR     r0, [r0]
        CMP     r0, #WINTER_FIRST_MONTH
        BLT     BA_notwinter
        CMP     r0, #WINTER_LAST_MONTH
        BGT     BA_notwinter
        ; ---- winter: harvest every ray of passive solar heat ----
        CMP     r8, #LIGHT_CAT_BRIGHT
        BEQ     BA_up
        CMP     r8, #LIGHT_CAT_DIM
        BEQ     BA_mid
        B       BA_down
BA_notwinter
        CMP     r0, #12
        BEQ     BA_summer
        CMP     r0, #SUMMER_LAST_MONTH
        BLE     BA_summer
        ; ---- shoulder months: simple light-only rule ----
        CMP     r8, #LIGHT_CAT_BRIGHT
        BEQ     BA_up
        CMP     r8, #LIGHT_CAT_DIM
        BEQ     BA_mid
        B       BA_down
BA_summer
        ; ---- summer: block strong midday sun, otherwise open up ----
        CMP     r8, #LIGHT_CAT_DARK
        BEQ     BA_down
        CMP     r4, #SUMMER_SHADE_START_H
        BLT     BA_up
        CMP     r4, #SUMMER_SHADE_END_H
        BGE     BA_up
        CMP     r8, #LIGHT_CAT_BRIGHT
        BEQ     BA_down                 ; strong midday sun -> shade
        B       BA_up
BA_up
        MOV     r0, #BLIND_UP
        POP     {r4, pc}
BA_mid
        MOV     r0, #BLIND_MID
        POP     {r4, pc}
BA_down
        MOV     r0, #BLIND_DOWN
        POP     {r4, pc}

;------------------------------------------------------------------------------
; Automation_TogglePlug : manual toggle - the ONE routine both the physical
;   button and the LCD button call.  Applies immediately and marks the
;   brewing window as "used" so the idle timeout stands down.
;   In: -   Out: -   Clobbers: r0-r2
;------------------------------------------------------------------------------
Automation_TogglePlug
        PUSH    {lr}
        LDR     r1, =g_plug_on
        LDR     r0, [r1]
        EOR     r0, r0, #1
        STR     r0, [r1]
        LDR     r1, =g_manual_used
        MOV     r2, #1
        STR     r2, [r1]
        BL      SmartPlug_Set           ; r0 = new state, drive the LED now
        POP     {pc}

;------------------------------------------------------------------------------
; Simple accessors / mutators (shared by the LCD UI and the button paths)
;------------------------------------------------------------------------------
; r0 = blind id (0/1), r1 = state (0..2) or -1 for AUTO
Automation_SetBlindManual
        CMP     r0, #0
        LDREQ   r2, =g_blind0_manual
        LDRNE   r2, =g_blind1_manual
        STR     r1, [r2]
        BX      lr

; r0 = 0 (scheduling off) / 1 (scheduling on)
Automation_SetAutoMode
        LDR     r1, =g_auto_mode
        STR     r0, [r1]
        BX      lr

Automation_GetAutoMode
        LDR     r0, =g_auto_mode
        LDR     r0, [r0]
        BX      lr

Automation_GetPlugState
        LDR     r0, =g_plug_on
        LDR     r0, [r0]
        BX      lr

; r0 = blind id (0/1) -> r0 = applied state
Automation_GetBlindState
        CMP     r0, #0
        LDREQ   r0, =g_blind0_state
        LDRNE   r0, =g_blind1_state
        LDR     r0, [r0]
        BX      lr

Automation_GetShotTime
        LDR     r0, =g_shot_min
        LDR     r0, [r0]
        BX      lr

; r0 = signed delta in minutes (|delta| < 1440); wraps across midnight
Automation_AdjustShotTime
        LDR     r1, =g_shot_min
        LDR     r2, [r1]
        ADD     r2, r2, r0
        LDR     r3, =MINUTES_PER_DAY
        CMP     r2, #0
        ADDLT   r2, r2, r3
        CMP     r2, r3
        SUBGE   r2, r2, r3
        STR     r2, [r1]
        BX      lr

; r0 = +1 or -1; month wraps 1..12
Automation_AdjustMonth
        LDR     r1, =g_month
        LDR     r2, [r1]
        ADD     r2, r2, r0
        CMP     r2, #13
        MOVGE   r2, #1
        CMP     r2, #1
        MOVLT   r2, #12
        STR     r2, [r1]
        BX      lr

Automation_GetMonth
        LDR     r0, =g_month
        LDR     r0, [r0]
        BX      lr

Automation_GetLightRaw
        LDR     r0, =g_light_raw
        LDR     r0, [r0]
        BX      lr

Automation_GetLightCat
        LDR     r0, =g_light_cat
        LDR     r0, [r0]
        BX      lr

        LTORG

;------------------------------------------------------------------------------
        AREA    AutomationData, DATA, READWRITE
g_auto_mode      SPACE  4      ; 1 = plug schedule enabled
g_plug_on        SPACE  4      ; current plug state 0/1
g_manual_used    SPACE  4      ; 1 = user toggled the plug this brewing window
g_shot_min       SPACE  4      ; target shot time (minutes-of-day)
g_sched_last     SPACE  4      ; last minute-of-day the schedule processed
g_month          SPACE  4      ; current month 1..12 (drives the season rules)
g_blind0_manual  SPACE  4      ; -1 = AUTO, else forced BLIND_* state
g_blind1_manual  SPACE  4
g_blind0_state   SPACE  4      ; applied state (for the LCD read-out)
g_blind1_state   SPACE  4
g_light_raw      SPACE  4      ; last sensor reading (for the LCD)
g_light_cat      SPACE  4      ; last category (for the LCD + blinds)

        END
