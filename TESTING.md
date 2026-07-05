# Testing the Home Automation Hub on the Physical QVGA Board

Hardware bring-up and test guide for the DESN2000 home automation hub firmware
(Keil QVGA Development Board, LPC2478 / ARM7TDMI).

> **Golden rule:** don't flash-and-pray. The daughter-board pin map (Figure 3)
> is *assumed* in `lpc2478.inc` — two entries (blind toggle switches, plug
> LED) are pure placeholders — so bring the system up **one subsystem at a
> time, in dependency order**. Each stage below depends only on earlier ones.

---

## 1. Build it in Keil uVision

1. Open the uVision project that already contains your lab's **`Startup.s`**
   (it sets up the stacks and must branch to `main` — confirm it ends with
   something like `IMPORT main` / `LDR PC,=main`).
2. Add all `.s` files to the project: `main.s`, `fixtures.s`, `buttons.s`,
   `light_sensor.s`, `timekeeping.s`, `doorbell.s`, `automation.s`,
   `lcd_ui.s`. *Do not* add `lpc2478.inc` — it is `GET`-included.
3. **Project → Options for Target:**
   - **Device:** NXP LPC2478.
   - **Asm tab → Include Paths:** add the folder containing `lpc2478.inc`.
   - **Target tab:** note the **Xtal / clock** — needed to confirm `PCLK_HZ`.
4. Build (**F7**) and clear any assembler errors. The LCD is a no-op until
   you add `USE_LCD` (Asm → Define), so ignore the UI for now.

---

## 2. Pin down `PCLK_HZ` first

The clock tick, `Delay_us`, the debounce sampling, the chime pitch and the
ADC clock all derive from `PCLK_HZ` in `lpc2478.inc` (placeholder `12000000`).

- Check how `Startup.s` configures the PLL (CCLK) and the peripheral-clock
  dividers (`PCLKSEL0/1`).
- `PCLK = CCLK / divider`. Set `PCLK_HZ` to the real value.
- **If this is wrong, time runs fast/slow and the chime is the wrong pitch** —
  a useful sanity check later.

---

## 3. Flash / debug connection

Confirm the method with your demonstrator:

- **ULINK2 / CMSIS-DAP / J-Link:** Options → Debug → select the unit;
  Utilities → configure Flash with the LPC2478 algorithm.
  **Load (F8)** flashes; **Debug session (Ctrl+F5)** lets you single-step.
- **Serial ISP (Flash Magic over UART):** build a `.hex`, download via
  Flash Magic.

The **debug session is your main test instrument** — use Watch / Memory
windows and breakpoints rather than relying on the LCD.

---

## 4. Staged bring-up

Test in this order. Temporarily replace the `main` loop body with a
single-subsystem harness, or just set breakpoints and step.

### Stage A — Clock / timers
Run, then add `g_sec`, `g_min`, `g_hour` to a **Watch window**.
Confirm `g_sec` increments once per real second (stopwatch it).
Drift ⇒ `PCLK_HZ` is wrong → back to step 2.
(For later stages you can set `DEMO_TIME_SCALE EQU 60` — one minute per
second — but do stage A at real speed first.)

### Stage B — Blind LEDs (verify the P3 mapping)
Manually call `Blind_SetState` with:
- `r0=0, r1=0` (red / up), `r1=1` (green / mid), `r1=2` (blue / down)
- repeat for `r0=1` (second blind)

Watch the daughter-board LEDs. Wrong LED/colour ⇒ fix `BL1_*` / `BL2_*`
masks in `lpc2478.inc`. **Do not touch logic.**

### Stage C — LED ladder
Call `LEDLadder_Show` with `r0` = 0, 300, 700, 1023 ⇒ 0, 2, 5, 8 bars.
- Nothing ever lights ⇒ try inverting the `LADDER_EN` assumption in
  `Fixtures_Init` (enable may be active-low) or check `LADDER_MASK`.

### Stage D — Buttons & switches (debounce layer)
Run the full loop. Watch `g_btn_stable` (from `buttons.s`):
- hold the doorbell button (P0.10) ⇒ bit 0 sets ~30 ms later
- hold the plug button (P0.11) ⇒ bit 1
- flip blind toggle switches (P1.16/17 **placeholders!**) ⇒ bits 2/3

Inverted or dead ⇒ check active-low wiring / pin choices in `lpc2478.inc`.
Also watch `g_btn_events`: one press = the bit sets once and clears when
consumed — **no double-triggers even with a deliberately bouncy press**.

### Stage E — Light sensor (ADC)
Build the test divider (LDR + ~10k to P0.23, see `README.txt`).
Breakpoint after `LightSensor_Read`, watch `r0`:
- cover sensor ⇒ value drops; the LED ladder loses bars
- shine light ⇒ value rises; the ladder gains bars

Note the dark/bright extremes and set `LIGHT_DARK` / `LIGHT_BRIGHT` in
`lpc2478.inc` to sit between them.

### Stage F — Doorbell
Run the full loop. Press the doorbell once ⇒ one "ding-dong".
- Hold the button ⇒ still chimes exactly once (edge, not level).
- The chime is non-blocking: the blind LEDs / ladder keep updating while
  it plays.
- No sound ⇒ confirm the speaker is on the DAC / P0.26 path.
- Wrong pitch ⇒ `PCLK_HZ`.

### Stage G — Automation
Run the whole loop (`DEMO_TIME_SCALE 60` makes this pleasant):
- Sweep the light sensor ⇒ blind LEDs change per the current month's rule
  (default month 7 = winter: bright→UP/red, dim→MID/green, dark→DOWN/blue).
- Poke `g_month` to 1 (summer, Watch window) with the clock at midday and a
  bright reading ⇒ blinds go DOWN (midday shading) instead of UP.
- Set the clock past `DAY_END_HOUR` (20:00) ⇒ blinds DOWN regardless.
- Clock through (shot−20 min) — default shot 07:00, so 06:40 ⇒ plug LED on;
  through 07:30 with no button press ⇒ plug LED off (idle timeout).
- Press the plug button anytime ⇒ plug toggles **immediately**; after a
  manual press inside the window, the 07:30 auto-off stands down.
- Flip a blind switch ⇒ that blind obeys the switch, ignores the sensor.
  **Manual must win over auto in every one of these — test it explicitly.**

### Stage H — LCD UI
Only after A–G pass:
1. Add `USE_LCD` under Asm → Define.
2. Wire the IMPORTs in `lcd_ui.s` to your lab's GLCD / touch driver.
3. Calibrate the touch hit-box tables (`tbl_home` / `tbl_settings`).
4. Rebuild. Check: home screen status matches the physical LEDs at all
   times; every touch control changes the same state the buttons do
   (they call the same functions); settings screen sets clock, shot time
   and month.

---

## 5. Handy debug techniques

- **Watch window:** `g_sec`, `g_btn_stable`, `g_btn_events`, `g_plug_on`,
  `g_auto_mode`, `g_manual_used`, `g_blind0_state`, `g_month` — the whole
  system state is visible without the LCD.
- **Memory window:** GPIO regs, e.g. `0x3FFFC074` (`FIO3PIN`) for the blind
  LEDs, `0x3FFFC014` (`FIO0PIN`) for buttons/ladder.
- **Set variables live:** poke `g_hour`/`g_min`/`g_month` in the Watch
  window to fast-forward to any schedule event without waiting.
- **Logic analyzer** (Keil's, under Debug): probe the DAC or LED pins to
  verify the chime waveform / debounce timing.

---

## 6. Quick reference — what to tune where (all in `lpc2478.inc`)

| Symptom | Fix |
|---|---|
| Clock drifts / wrong chime pitch | `PCLK_HZ` |
| Wrong LED or colour lights | `BL1_*` / `BL2_*` / `PLUG_LED` |
| Ladder dead or inverted | `LADDER_MASK` / `LADDER_EN` polarity |
| Buttons/switches inverted or dead | `BTN_*` / `SW_*` pins + polarity |
| Presses missed or doubled | `DEBOUNCE_SAMPLE_US` / `DEBOUNCE_STABLE_N` |
| Blinds switch at wrong light level | `LIGHT_DARK` / `LIGHT_BRIGHT` |
| Night starts/ends at wrong time | `DAY_START_HOUR` / `DAY_END_HOUR` |
| Wrong season behaviour | `WINTER_*` / `SUMMER_*` months + shade window |
| Coffee on at wrong time | `PREHEAT_MINUTES` / `IDLE_TIMEOUT_MINUTES` (shot time is set on the LCD) |
| Demo too slow to mark | `DEMO_TIME_SCALE` |

> **Note:** the firmware cannot be compiled or flashed from a Mac/Linux box —
> it targets the Keil/Windows uVision ARM toolchain. Stages A–B are also where
> you will catch any remaining assembler-syntax issues.
