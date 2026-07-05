;==============================================================================
; lpc2478.inc  -  Register addresses, board wiring and ALL tunable constants
;
; Single source of truth for the DESN2000 Home Automation Hub.
; GET this file at the top of every source module:  GET lpc2478.inc
;
; ALL hardware-mapping assumptions live here.  Anything tagged  <<VERIFY>>
; must be checked against Figure 3 of the Project Brief and the QVGA /
; Daughter Board schematic BEFORE running on real hardware.  Anything tagged
; <<TUNE>> is a design decision to be justified in the Design Journal and
; adjusted during hardware bring-up.
;==============================================================================

;------------------------------------------------------------------------------
; Clock assumption
;   ADC clock, the 1 ms system tick and the microsecond delay timer are all
;   derived from PCLK.  Set this to your board's peripheral clock.   <<VERIFY>>
;------------------------------------------------------------------------------
PCLK_HZ         EQU     12000000        ; peripheral clock in Hz

;------------------------------------------------------------------------------
; Demo / marking aid: wall-clock speed multiplier                      <<TUNE>>
;   1  = real time.
;   60 = the clock runs ~60x fast (one "minute" per real second), so the
;        coffee schedule and night/day blind logic can be demonstrated live
;        in a workshop without waiting for real hours to pass.
;   (Implemented by shortening the 1-second timer match; HH:MM:SS logic is
;    untouched, so nothing else changes between demo and real builds.)
;------------------------------------------------------------------------------
DEMO_TIME_SCALE EQU     1
TICK_MS         EQU     (1000/DEMO_TIME_SCALE)  ; Timer0 match period in ms

;------------------------------------------------------------------------------
; Pin Connect Block (PINSEL)   [UM10237 ch.9]
;   Base 0xE002C000, PINSELn at base + 4*n.
;------------------------------------------------------------------------------
PINSEL0         EQU     0xE002C000      ; controls P0.0  .. P0.15
PINSEL1         EQU     0xE002C004      ; controls P0.16 .. P0.31
PINSEL3         EQU     0xE002C00C      ; controls P1.16 .. P1.31
PINSEL7         EQU     0xE002C01C      ; controls P3.16 .. P3.31    <<VERIFY>>

; Function-select clear masks (set the field to 00 = GPIO for our pins)
PINSEL0_GPIO_MASK EQU   0x00F3FFFC      ; P0.1-8 (ladder) + P0.10/11 (buttons)
PINSEL1_P022_MASK EQU   0x00003000      ; P0.22 (ladder enable)
PINSEL3_SW_MASK   EQU   0x0000000F      ; P1.16/17 (blind toggle switches)
PINSEL7_LED_MASK  EQU   0x00000FFF      ; P3.16-21 (tricolour LEDs)

;------------------------------------------------------------------------------
; Fast GPIO (LPC2478) - port stride is 0x20 from FIO0 at 0x3FFFC000
;------------------------------------------------------------------------------
FIO0DIR         EQU     0x3FFFC000
FIO0PIN         EQU     0x3FFFC014
FIO0SET         EQU     0x3FFFC018
FIO0CLR         EQU     0x3FFFC01C

FIO1DIR         EQU     0x3FFFC020
FIO1PIN         EQU     0x3FFFC034
FIO1SET         EQU     0x3FFFC038
FIO1CLR         EQU     0x3FFFC03C

FIO2DIR         EQU     0x3FFFC040
FIO2PIN         EQU     0x3FFFC054
FIO2SET         EQU     0x3FFFC058
FIO2CLR         EQU     0x3FFFC05C

FIO3DIR         EQU     0x3FFFC060      ; base + 3*0x20 (same stride) <<VERIFY>>
FIO3PIN         EQU     0x3FFFC074
FIO3SET         EQU     0x3FFFC078
FIO3CLR         EQU     0x3FFFC07C

;------------------------------------------------------------------------------
; ADC (10-bit) - used for the light sensor
;------------------------------------------------------------------------------
AD0CR           EQU     0xE0034000
AD0GDR          EQU     0xE0034004      ; Global Data Reg: RESULT bits[15:6], DONE bit31

;------------------------------------------------------------------------------
; DAC (10-bit) - drives the on-board speaker for the doorbell chime
;------------------------------------------------------------------------------
DACR            EQU     0xE006C000      ; VALUE in bits[15:6]

;------------------------------------------------------------------------------
; Timer0 (system tick for the clock)  and  Timer1 (free-running us counter)
;------------------------------------------------------------------------------
T0IR            EQU     0xE0004000
T0TCR           EQU     0xE0004004
T0PR            EQU     0xE000400C
T0MR0           EQU     0xE0004018
T0MCR           EQU     0xE0004014

T1TCR           EQU     0xE0008004
T1TC            EQU     0xE0008008
T1PR            EQU     0xE000800C

T0_PRESCALE     EQU     (PCLK_HZ/1000 - 1)      ; Timer0 PC ticks every 1 ms
T1_PRESCALE     EQU     (PCLK_HZ/1000000 - 1)   ; Timer1 TC ticks every 1 us

;------------------------------------------------------------------------------
; Power Control for Peripherals
;------------------------------------------------------------------------------
PCONP           EQU     0xE01FC0C4
PCTIM0          EQU     (1:SHL:1)
PCTIM1          EQU     (1:SHL:2)
PCADC           EQU     (1:SHL:12)

;==============================================================================
; BOARD WIRING  -  per Project Brief Figure 3 (OCR of the figure is not fully
; legible, so treat every pin below as a DRAFT).                <<VERIFY ALL>>
;==============================================================================

;------------------------------------------------------------------------------
; Tricolour LEDs = window blinds, on Port 3 (brief Fig. 3: P3.16 .. P3.21).
;   Blind position is shown as:  rolled UP = red, MID = green, DOWN = blue.
;------------------------------------------------------------------------------
BL1_R           EQU     (1:SHL:16)      ; Blind 1 (e.g. living room)
BL1_G           EQU     (1:SHL:17)
BL1_B           EQU     (1:SHL:18)
BL2_R           EQU     (1:SHL:19)      ; Blind 2 (e.g. bedroom)
BL2_G           EQU     (1:SHL:20)
BL2_B           EQU     (1:SHL:21)
BLIND_LED_MASK  EQU     0x003F0000      ; all of P3.16 .. P3.21

; Blind state codes (used throughout the project)
BLIND_UP        EQU     0               ; rolled up   -> red
BLIND_MID       EQU     1               ; mid-way     -> green
BLIND_DOWN      EQU     2               ; rolled down -> blue

;------------------------------------------------------------------------------
; LED ladder (8-bar) = light-level bar graph, on Port 0.
;   Brief Fig. 3: data on P0.1 .. P0.8, enable on P0.22.
;   Enable is ASSUMED active-high; if no bars ever light, try clearing
;   LADDER_EN in Fixtures_Init instead.                             <<VERIFY>>
;------------------------------------------------------------------------------
LADDER_MASK     EQU     0x000001FE      ; P0.1 .. P0.8
LADDER_SHIFT    EQU     1               ; bar 0 sits at P0.1
LADDER_EN       EQU     (1:SHL:22)      ; P0.22

;------------------------------------------------------------------------------
; Smart-plug indicator LED.
;   NO dedicated plug LED appears in the brief's Figure 3 table - P2.6 is a
;   placeholder; move it to any spare daughter-board LED.  Plug state is
;   also always visible on the LCD.                                 <<VERIFY>>
;------------------------------------------------------------------------------
PLUG_LED        EQU     (1:SHL:6)       ; P2.6 (placeholder)

;------------------------------------------------------------------------------
; Push buttons, on Port 0 (brief Fig. 3: P0.10, P0.11).
;   Mapping choice: P0.10 = doorbell, P0.11 = smart-plug override.
;   Assumed active LOW with the LPC2478's default pull-ups.         <<VERIFY>>
;------------------------------------------------------------------------------
BTN_DOORBELL_PIN EQU    (1:SHL:10)      ; P0.10  doorbell
BTN_PLUG_PIN     EQU    (1:SHL:11)      ; P0.11  smart-plug override
BTN0_MASK        EQU    (BTN_DOORBELL_PIN:OR:BTN_PLUG_PIN)

;------------------------------------------------------------------------------
; Blind toggle switches, on Port 1.
;   NO pin numbers are given in the brief for these - P1.16/P1.17 are pure
;   placeholders.  Assumed: switch closes to GND (reads LOW) in the "blind
;   up" position.                                                   <<VERIFY>>
;------------------------------------------------------------------------------
SW_BLIND1_PIN   EQU     (1:SHL:16)      ; P1.16  blind 1 toggle
SW_BLIND2_PIN   EQU     (1:SHL:17)      ; P1.17  blind 2 toggle
SW1_MASK        EQU     (SW_BLIND1_PIN:OR:SW_BLIND2_PIN)

;------------------------------------------------------------------------------
; Virtual (debounced) input bits - the buttons.s module normalises all the
; physical inputs above into this one bitmask; everything downstream
; (doorbell, automation) consumes ONLY these bits.
;------------------------------------------------------------------------------
INP_DOORBELL    EQU     (1:SHL:0)
INP_PLUG        EQU     (1:SHL:1)
INP_SW_BLIND1   EQU     (1:SHL:2)       ; set = switch in "up" position
INP_SW_BLIND2   EQU     (1:SHL:3)

;------------------------------------------------------------------------------
; Debounce parameters                                                 <<TUNE>>
;   Inputs are sampled every DEBOUNCE_SAMPLE_US and must read identically
;   DEBOUNCE_STABLE_N times in a row before a change is accepted
;   (3 x 10 ms = 30 ms, comfortably longer than typical contact bounce).
;------------------------------------------------------------------------------
DEBOUNCE_SAMPLE_US EQU  10000           ; 10 ms between samples
DEBOUNCE_STABLE_N  EQU  3               ; consecutive identical samples needed

;------------------------------------------------------------------------------
; Light sensor  -> ADC channel AD0.0 on P0.23   (real LPC2478 mapping)
;------------------------------------------------------------------------------
; PINSEL1 bits[15:14] = 01 selects AD0.0 on P0.23
ADPIN_MASK      EQU     0x0000C000
ADPIN_SET       EQU     0x00004000
; AD0CR: SEL=chan0(0x01), CLKDIV=0x0B (12MHz/12 = 1MHz <= 4.5MHz), PDN=1(bit21)
ADC_CFG         EQU     (0x01 :OR: (0x0B:SHL:8) :OR: (1:SHL:21))
ADC_START       EQU     (1:SHL:24)      ; START = 001 (start conversion now)

;------------------------------------------------------------------------------
; Speaker DAC output -> AOUT on P0.26     (real LPC2478 mapping)
;------------------------------------------------------------------------------
; PINSEL1 bits[21:20] = 10 selects AOUT on P0.26
DACPIN_MASK     EQU     0x00300000
DACPIN_SET      EQU     0x00200000

;==============================================================================
; TUNABLE ALGORITHM CONSTANTS  (design decisions - justify in Design Journal)
;==============================================================================

;------------------------------------------------------------------------------
; Light categories (raw ADC counts 0..1023)                           <<TUNE>>
;   Calibrate on hardware: note the covered/uncovered extremes of the real
;   sensor (TESTING.md stage E) and place these thresholds between them.
;------------------------------------------------------------------------------
LIGHT_DARK      EQU     150             ; below this  = DARK
LIGHT_BRIGHT    EQU     600             ; above this  = BRIGHT
LIGHT_CAT_DARK  EQU     0
LIGHT_CAT_DIM   EQU     1
LIGHT_CAT_BRIGHT EQU    2

;------------------------------------------------------------------------------
; Day window for the blind automation (hours, 24h clock)              <<TUNE>>
;   6..20 covers the Jindabyne daylight span across the year (Fig. 2 of the
;   brief: 9.5 h daylight in June to 14.5 h in Jan); outside it is "night".
;------------------------------------------------------------------------------
DAY_START_HOUR  EQU     6
DAY_END_HOUR    EQU     20

;------------------------------------------------------------------------------
; Season boundaries by month (from the brief's Fig. 2 climate table)  <<TUNE>>
;   Winter  = Jun..Aug  (daily highs <= 9 degC -> maximise passive solar gain)
;   Summer  = Dec..Feb  (daily highs >= 22 degC -> block midday solar gain)
;   Everything else is a "shoulder" month with a simple light-only rule.
;------------------------------------------------------------------------------
WINTER_FIRST_MONTH EQU  6
WINTER_LAST_MONTH  EQU  8
SUMMER_LAST_MONTH  EQU  2               ; summer = month 12, 1 or 2
SUMMER_SHADE_START_H EQU 10             ; midday shading window in summer
SUMMER_SHADE_END_H   EQU 16
DEFAULT_MONTH   EQU     7               ; boot-up month (settable on the LCD)

;------------------------------------------------------------------------------
; Espresso-machine smart plug schedule                                 <<TUNE>>
;   The E61 group head needs 15-20 min to reach brewing temperature, so the
;   plug switches on PREHEAT_MINUTES before the target shot time.  If nobody
;   touches the machine, it switches off IDLE_TIMEOUT_MINUTES after the
;   target so an empty cottage never heats an unused boiler.
;------------------------------------------------------------------------------
SHOT_DEFAULT_MIN     EQU (7*60)         ; default target shot time = 07:00
PREHEAT_MINUTES      EQU 20
IDLE_TIMEOUT_MINUTES EQU 30
MINUTES_PER_DAY      EQU 1440

;------------------------------------------------------------------------------
; LCD refresh period (us) - status lines are only redrawn this often so the
; screen doesn't flicker and the super-loop stays fast.               <<TUNE>>
;------------------------------------------------------------------------------
LCD_REFRESH_US  EQU     250000

        END
