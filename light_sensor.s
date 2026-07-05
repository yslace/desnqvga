;==============================================================================
; light_sensor.s  -  Light sensor on the LPC2478 ADC
;
; The light sensor produces an analog voltage that is read on ADC channel
; AD0.0 (pin P0.23).  A simple light-dependent-resistor divider feeding P0.23
; is enough to demonstrate the code (see README for the test circuit).
;
; Conversion is POLLING-based (start, wait for DONE, read) - deterministic
; and simple; one conversion takes ~10us at the 1 MHz ADC clock, negligible
; per super-loop pass.
;
; Provides:
;   LightSensor_Init     - power up the ADC and route P0.23 to AD0.0
;   LightSensor_Read     - r0 = raw light level, 0 (dark) .. 1023 (bright)
;   LightSensor_Category - r0 = raw level in -> r0 = LIGHT_CAT_DARK/DIM/BRIGHT
;                          (thresholds LIGHT_DARK/LIGHT_BRIGHT in lpc2478.inc)
;==============================================================================
        AREA    LightCode, CODE, READONLY
        GET     lpc2478.inc

        EXPORT  LightSensor_Init
        EXPORT  LightSensor_Read
        EXPORT  LightSensor_Category

;------------------------------------------------------------------------------
; LightSensor_Init
;   In: -   Out: -   Clobbers: r0-r2
;------------------------------------------------------------------------------
LightSensor_Init
        ; power up the ADC block
        LDR     r0, =PCONP
        LDR     r1, [r0]
        ORR     r1, r1, #PCADC
        STR     r1, [r0]

        ; route P0.23 to AD0.0 (PINSEL1 bits[15:14] = 01)
        LDR     r0, =PINSEL1
        LDR     r1, [r0]
        LDR     r2, =ADPIN_MASK
        BIC     r1, r1, r2
        LDR     r2, =ADPIN_SET
        ORR     r1, r1, r2
        STR     r1, [r0]

        ; configure the ADC: channel 0, ADC clock <= 4.5 MHz, powered on
        LDR     r0, =AD0CR
        LDR     r1, =ADC_CFG
        STR     r1, [r0]
        BX      lr

;------------------------------------------------------------------------------
; LightSensor_Read : start one conversion, wait for DONE, return 10-bit result.
;   In: -   Out: r0 = 0..1023   Clobbers: r1-r3
;------------------------------------------------------------------------------
LightSensor_Read
        LDR     r1, =AD0CR
        LDR     r2, =(ADC_CFG :OR: ADC_START)
        STR     r2, [r1]                ; trigger a conversion

        LDR     r1, =AD0GDR
        LDR     r3, =0x80000000         ; DONE flag (bit31)
LSR_wait
        LDR     r0, [r1]
        TST     r0, r3
        BEQ     LSR_wait

        MOV     r0, r0, LSR #6          ; RESULT is in bits[15:6]
        LDR     r1, =0x3FF
        AND     r0, r0, r1              ; mask to 10 bits (0..1023)
        BX      lr

;------------------------------------------------------------------------------
; LightSensor_Category : classify a raw reading into DARK / DIM / BRIGHT.
;   In: r0 = raw 0..1023   Out: r0 = LIGHT_CAT_*   Clobbers: r1
;------------------------------------------------------------------------------
LightSensor_Category
        LDR     r1, =LIGHT_DARK
        CMP     r0, r1
        MOVLT   r0, #LIGHT_CAT_DARK
        BXLT    lr
        LDR     r1, =LIGHT_BRIGHT
        CMP     r0, r1
        MOVGE   r0, #LIGHT_CAT_BRIGHT
        MOVLT   r0, #LIGHT_CAT_DIM
        BX      lr

        LTORG
        END
