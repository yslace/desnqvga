;==============================================================================
; main.s  -  Home Automation Hub: entry point and super-loop
;
; Links with the standard DESN2000 lab Startup.s, which sets up the stacks
; and branches to the exported label `main`.
;
; The hub runs a simple cooperative super-loop with NO interrupts: every
; pass it advances the software clock, debounces the inputs, services the
; doorbell chime, runs the automation "smarts", and refreshes the LCD UI.
; Each service self-limits its own rate (debounce sampling, once-per-minute
; scheduling, LCD refresh period), so the loop itself just spins.
;==============================================================================
        AREA    HubMain, CODE, READONLY
        GET     lpc2478.inc

        ; --- one-time initialisers ---
        IMPORT  Time_Init
        IMPORT  Fixtures_Init
        IMPORT  Buttons_Init
        IMPORT  LightSensor_Init
        IMPORT  Doorbell_Init
        IMPORT  Automation_Init
        IMPORT  LCD_UI_Init

        ; --- per-loop services ---
        IMPORT  Time_Update
        IMPORT  Buttons_Poll
        IMPORT  Doorbell_Poll
        IMPORT  Automation_Update
        IMPORT  LCD_UI_Update

        EXPORT  main
main
        BL      Time_Init               ; clock tick + us timer (needed first)
        BL      Fixtures_Init           ; LEDs, ladder, buttons, switches
        BL      Buttons_Init            ; debouncer (snapshots boot state)
        BL      LightSensor_Init        ; ADC for the light sensor
        BL      Doorbell_Init           ; speaker (DAC) + chime state
        BL      Automation_Init         ; energy-saving control logic
        BL      LCD_UI_Init             ; touch-screen interface

MainLoop
        BL      Time_Update             ; keep the wall clock running
        BL      Buttons_Poll            ; debounce inputs, latch press events
        BL      Doorbell_Poll           ; chime on a new press + keep it playing
        BL      Automation_Update       ; drive blinds + plug from sensor/time
        BL      LCD_UI_Update           ; redraw status + handle touch input
        B       MainLoop

        END
