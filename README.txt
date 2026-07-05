================================================================================
 DESN2000 - Home Automation & Control Hub  (Keil QVGA board, LPC2478 / ARM7TDMI)
 Implementation code - README
================================================================================

WHAT THIS IS
------------
Prototype firmware for a holiday-cottage automation hub in Jindabyne NSW,
written in ARM assembly for the Keil QVGA Development Board.  Real 240V
appliances are mimicked on the DESN2000 Daughter Board (buttons, toggle
switches, tricolour LEDs, 8-bar LED ladder), per the Project Brief.

The hub runs a cooperative super-loop with NO interrupts (main.s).  Each pass
it keeps the clock, debounces the inputs, services the doorbell chime, runs
the energy-saving automation, and refreshes the LCD.


WHERE EACH GRADED FEATURE LIVES  (Code-implementation rubric)
-------------------------------------------------------------
 1. Readme file & code comments .......... this file + comments in every .s
 2. Configuring/reading the light sensor . light_sensor.s  (ADC AD0.0/P0.23,
                                            polling read + DARK/DIM/BRIGHT
                                            categorisation)
 3. Configuring/controlling fixtures ..... fixtures.s (LED + switch/button IO)
                                            + buttons.s (software DEBOUNCE:
                                            10 ms sampling, 3 stable reads,
                                            edge-detected press events)
 4. Doorbell feature ..................... doorbell.s (debounced press EDGE ->
                                            non-blocking DAC "ding-dong")
 5. Algorithms & "smarts" ................ automation.s (seasonal blind rules
                                            + espresso pre-heat schedule, all
                                            manually overridable)
 6. User interface (LCD touch screen) .... lcd_ui.s (home + settings screens,
                                            touch dispatches into the same
                                            functions the buttons use)

 Support modules:
    lpc2478.inc   - ALL register addresses, board wiring and tunable
                    constants - the single source of truth
    timekeeping.s - Timer0-based HH:MM:SS clock + Timer1 us services
    main.s        - init sequence and super-loop


PIN MAP  (Project Brief Figure 3 - DRAFT, the figure's OCR is not fully
legible; every entry is tagged <<VERIFY>> in lpc2478.inc)
--------------------------------------------------------------------------
  Tricolour LED bank 1 (blind 1) . P3.16 R / P3.17 G / P3.18 B   (per brief)
  Tricolour LED bank 2 (blind 2) . P3.19 R / P3.20 G / P3.21 B   (per brief)
  LED ladder (8-bar) ............. P0.1..P0.8 data, P0.22 enable (per brief;
                                   enable polarity ASSUMED active-high)
  Doorbell button ................ P0.10  (brief lists P0.10/P0.11 push-
  Smart-plug override button ..... P0.11   buttons; this pairing is OUR choice)
  Blind 1 / 2 toggle switches .... P1.16 / P1.17  (NO pins in the brief -
                                   pure PLACEHOLDERS, fix in lpc2478.inc)
  Smart-plug indicator LED ....... P2.6   (NO plug LED in the brief's table -
                                   PLACEHOLDER; plug state also shown on LCD)
  Light sensor ................... AD0.0 on P0.23 (real LPC2478 ADC mapping)
  Speaker ........................ AOUT on P0.26 (real LPC2478 DAC mapping)
  Buttons/switches assumed ACTIVE LOW with the chip's default pull-ups.
All of this lives in ONE place (lpc2478.inc); wrong guesses are fixed there
without touching any logic.  See TESTING.md for the bring-up procedure.


DESIGN DECISIONS  (to defend in the Design Journal)
---------------------------------------------------
* LED LADDER = light bar graph.  The brief does not pin down the ladder's
  use; we display the raw light-sensor reading (more bars = brighter), which
  gives an at-a-glance hardware readout of the sensor the whole automation
  depends on - and doubles as a live ADC demo for marking.

* TIMEKEEPING = Timer0 tick + software HH:MM:SS (the brief's Activity-2
  alternative to the RTC).  Chosen because it needs no register addresses
  beyond the timers we already use and no interrupt/VIC setup; the rest of
  the code only calls Time_* accessors, so swapping in the RTC peripheral
  later would touch only timekeeping.s.

* BLINDS (automation.s, thresholds in lpc2478.inc): season-aware, from the
  brief's Fig. 2 climate data for Jindabyne:
    - Night (any season): DOWN - insulate the glazing, retain heat, privacy.
    - Winter (Jun-Aug, highs <= 9 degC): bright day -> UP for free passive-
      solar heating; dim -> MID; dark -> DOWN.  Cuts active heating.
    - Summer (Dec-Feb, highs >= 22 degC): bright midday (10-16 h) -> DOWN to
      block solar gain and cut cooling; mornings/evenings -> UP.
    - Shoulder months: light-only rule (bright UP / dim MID / dark DOWN).
  MANUAL ALWAYS WINS: flipping a blind's toggle switch forces that blind to
  the switch position; the LCD "blind-auto" control hands it back.

* SMART PLUG (espresso machine): the E61 group head needs 15-20 min to reach
  temperature, so with auto-mode on, the plug switches ON PREHEAT_MINUTES
  (20) before the user-set target shot time and OFF IDLE_TIMEOUT_MINUTES
  (30) after it if nobody touched the machine - the plug is never on outside
  a ~50-minute window around actual use, which is the brief's energy goal
  for an occasionally-occupied cottage.  The physical button ALWAYS toggles
  the plug immediately; the schedule only acts at its two event minutes, so
  it never fights a manual decision.

* DOORBELL: debounced press EDGE (holding does not retrigger) starts a
  NON-BLOCKING two-note chime - the DAC square wave is advanced from the
  super-loop off Timer1, so automation never stalls while the bell rings.

* DEMO MODE: set DEMO_TIME_SCALE (lpc2478.inc) to e.g. 60 and rebuild - the
  clock runs a minute per second so night/day blind logic and the coffee
  schedule can be demonstrated live.  Light levels are demoed by covering /
  lighting the sensor; month and clock are settable on the LCD settings
  screen (or poke g_month / g_hour in a Keil Watch window).


BUILDING
--------
* Add all .s files (main, fixtures, buttons, light_sensor, timekeeping,
  doorbell, automation, lcd_ui) to your Keil uVision DESN2000 project (the
  same project that provides Startup.s).  Startup.s must set up the stacks
  and branch to `main`.  Do NOT add lpc2478.inc - it is GET-included.
* Default build: the LCD layer compiles as no-ops, so sensor + fixtures +
  doorbell + automation + clock run immediately with no LCD dependency.
* To enable the real touch UI: Options for Target > Asm > Define: USE_LCD,
  then wire the IMPORTs at the top of the USE_LCD section in lcd_ui.s to
  your lab's GLCD/touch driver (entry-point names and argument passing vary
  per team; the driver is assumed to preserve r4-r11).


ASSUMPTIONS TO VERIFY ON HARDWARE   (search the code for <<VERIFY>>/<<TUNE>>)
------------------------------------------------------------------------------
All concentrated in lpc2478.inc:
  * PCLK_HZ - peripheral clock; sets the ADC clock, the clock tick, the
    debounce sampling and the chime pitch.
  * The whole daughter-board pin map above, especially the two PLACEHOLDER
    entries (blind switches, plug LED), the P0.10/P0.11 button pairing, the
    ladder enable polarity, and active-low input polarity.
  * FIO3/PINSEL7 addresses (derived from the documented register strides).
Tunables (same file): LIGHT_DARK/LIGHT_BRIGHT, day window, season months,
summer shade window, PREHEAT/IDLE_TIMEOUT minutes, debounce timing.


A TEST CIRCUIT FOR THE LIGHT SENSOR
-----------------------------------
LDR from 3.3V to P0.23, fixed resistor (~10k) from P0.23 to GND (or swap for
inverse response). Covering the LDR drops the reading; shining a light raises
it. Verify LightSensor_Read spans roughly 0..1023 and set LIGHT_DARK /
LIGHT_BRIGHT in lpc2478.inc to sit between the observed extremes.
