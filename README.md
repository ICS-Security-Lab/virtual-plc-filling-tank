# Virtual PLC Filling Tank — Ladder Logic over Modbus TCP

A virtual PLC control loop: ladder logic running on **OpenPLC**, driving a **Factory I/O** process simulation over **Modbus TCP** — no physical hardware required.

![OpenPLC](https://img.shields.io/badge/OpenPLC-Runtime%20v4-1F3864)
![Protocol](https://img.shields.io/badge/Protocol-Modbus%20TCP-blue)
![Standard](https://img.shields.io/badge/IEC-61131--3%20Ladder%20Logic-orange)
![Simulator](https://img.shields.io/badge/Simulator-Factory%20I%2FO%20v2.5.10-green)

---

## What this is

I wanted to practise PLC programming but had no PLC, no tank and no valves. So I split the problem in two: a 3D simulator plays the plant, a soft PLC plays the controller, and a real industrial protocol sits between them.

The point of using Modbus TCP instead of a fake in-process link is that the two halves really are two separate devices talking over a socket. The PLC polls the simulated process every 100 ms, reads the operator's button presses as discrete inputs, and writes valve and lamp states back as coils.

**What it does**

- One press of **Fill** starts filling; the phase latches and stops by itself after 10 seconds
- One press of **Discharge** drains the tank for 10 seconds
- Fill and discharge are **cross-interlocked** — the tank can never do both at once
- The panel button lenses light up to show the active phase
- The remaining time is computed in the PLC and shown as a live countdown on the process display

No level sensor is used anywhere. The scene transmits zero analogue values, so time is the only control parameter — which is exactly what makes it a timer-based control problem.

![Factory I/O Filling Tank scene with the operator panel](https://dev-to-uploads.s3.us-east-2.amazonaws.com/uploads/articles/qbhcvvyobs25m7dtg30i.jpg)

---

## Architecture

| Piece | Plays the role of | Notes |
|---|---|---|
| Factory I/O v2.5.10 | The plant | Tank, two valves, two illuminated buttons, numeric display; runs a Modbus TCP/IP **server** on port 502 |
| OpenPLC Runtime v4 | The PLC | Executes the program; runs a Modbus **master** (client) and its own slave server |
| OpenPLC Editor v4 | Engineering station | Where the ladder diagram is written, downloaded and monitored live |
| Modbus TCP | The fieldbus | Carries all process I/O between the two programs |

The role assignment is the part people get wrong: **Factory I/O is the server (slave) and the PLC is the client (master)**. The controller is the one doing the polling.

**Runtime start-up** — the slave listening on 502, the master connecting on the first attempt, and the PLC in `RUNNING` with a 100 ms base tick:

![OpenPLC runtime console](https://dev-to-uploads.s3.us-east-2.amazonaws.com/uploads/articles/oj97hg27ggykixz0exzw.jpg)

**Editor attached to the runtime** — the `Disconnect` button and `PLC: RUNNING` status mean the debugger can watch the logic execute:

![OpenPLC Editor device configuration](https://dev-to-uploads.s3.us-east-2.amazonaws.com/uploads/articles/addy5hjqon4ukv05vw96.jpg)

**The PLC's own Modbus slave server** (used later for verification):

![Modbus server settings](https://dev-to-uploads.s3.us-east-2.amazonaws.com/uploads/articles/6tq1p3ozcc842pgqb29n.jpg)

---

## I/O map

The PLC is the client, so every signal is defined from the PLC's point of view:

| Direction | Factory I/O tag | Modbus reference | PLC address |
|---|---|---|---|
| Process → PLC | Fill (push button) | Discrete Input 0 — FC 02 | `%IX0.0` |
| Process → PLC | Discharge (push button) | Discrete Input 1 — FC 02 | `%IX0.1` |
| PLC → Process | Fill valve | Coil 0 — FC 15 | `%QX0.0` |
| PLC → Process | Discharge valve | Coil 1 — FC 15 | `%QX0.1` |
| PLC → Process | Filling lamp (panel lens) | Coil 2 — FC 15 | `%QX0.2` |
| PLC → Process | Discharging lamp (panel lens) | Coil 3 — FC 15 | `%QX0.3` |
| PLC → Process | Timer display | Holding Register 0 — FC 16 | `%QW0` |

![Remote device tag mapping](https://dev-to-uploads.s3.us-east-2.amazonaws.com/uploads/articles/ve0uwmg8hqqv35zigriy.jpg)

The remote device reads **two** discrete inputs (length 2). Factory I/O also publishes a `FACTORY I/O (Running)` bit as input 2, but with length 2 that value never reaches the program — extend the length to 3 if you want to use it as a "simulation is running" gate.

---

## The control program

Program `main` uses 14 variables: 2 inputs, 4 outputs, 1 display register, 2 timers, 2 phase bits and 3 scratch values for the countdown.

![Variable declaration](https://dev-to-uploads.s3.us-east-2.amazonaws.com/uploads/articles/hfh7vjcl8z1tq2ialxhm.jpg)

### The logic in Structured Text

```iecst
(* ---- Fill phase ---- *)
Fill_Seq  := (Fill_Btn OR Fill_Seq) AND NOT Disch_Seq AND NOT T_Fill.Q;
T_Fill(IN := Fill_Seq, PT := T#10s);
Fill_Valve := Fill_Seq;
Fill_Light := Fill_Seq;

(* ---- Discharge phase ---- *)
Disch_Seq := (Disch_Btn OR Disch_Seq) AND NOT Fill_Seq AND NOT T_Disch.Q;
T_Disch(IN := Disch_Seq, PT := T#10s);
Disch_Valve := Disch_Seq;
Disch_Light := Disch_Seq;

(* ---- Countdown shown on the panel display ---- *)
IF Fill_Seq THEN
    Fill_sec   := TIME_TO_S(T_Fill.ET);      (* elapsed time -> seconds *)
    Left_Calc  := 10.0 - Fill_sec;           (* remaining seconds *)
    Timer_Disp := TO_INT(Left_Calc);         (* display takes an integer *)
ELSIF Disch_Seq THEN
    Disch_sec  := TIME_TO_S(T_Disch.ET);
    Left_Calc  := 10.0 - Disch_sec;
    Timer_Disp := TO_INT(Left_Calc);
END_IF;
```

### Key rungs

**Rung 1 — fill phase latch.** The `Fill_Seq` contact in parallel with `Fill_Btn` is the seal-in path, so one press starts the phase. `NOT Disch_Seq` is the interlock and `NOT T_Fill.Q` ends the phase when the timer expires.

![Rung 1 — fill latch](https://dev-to-uploads.s3.us-east-2.amazonaws.com/uploads/articles/4d90o3qe0bebk8f661nr.jpg)

**Rung 4 — discharge latch.** The mirror image, with the safety condition `NOT Fill_Seq` in series.

![Rung 4 — discharge latch with interlock](https://dev-to-uploads.s3.us-east-2.amazonaws.com/uploads/articles/nmq5ccimyb2n03f4jfjz.jpg)

**Rung 11 — writing the countdown to the display.** The real value is truncated to an integer and written to holding register 0, from where it travels to the process panel.

![Rung 11 — writing the countdown](https://dev-to-uploads.s3.us-east-2.amazonaws.com/uploads/articles/ix1ka0l6za7oec0qatya.jpg)

<details>
<summary><strong>All 14 rungs (click to expand)</strong></summary>

**Rung 1 — fill phase latch**
![Rung 1](https://dev-to-uploads.s3.us-east-2.amazonaws.com/uploads/articles/4d90o3qe0bebk8f661nr.jpg)

**Rung 2 — fill timer, preset T#10s**
![Rung 2](https://dev-to-uploads.s3.us-east-2.amazonaws.com/uploads/articles/7104tdkg9zaf4odxwatc.jpg)

**Rung 3 — fill valve output**
![Rung 3](https://dev-to-uploads.s3.us-east-2.amazonaws.com/uploads/articles/y4jnfunoob5ictuovble.jpg)

**Rung 4 — discharge phase latch**
![Rung 4](https://dev-to-uploads.s3.us-east-2.amazonaws.com/uploads/articles/nmq5ccimyb2n03f4jfjz.jpg)

**Rung 5 — discharge timer, preset T#10s**
![Rung 5](https://dev-to-uploads.s3.us-east-2.amazonaws.com/uploads/articles/udanp9r2h0nx50k3nwsr.jpg)

**Rung 6 — discharge valve output**
![Rung 6](https://dev-to-uploads.s3.us-east-2.amazonaws.com/uploads/articles/zoybpqskzn2qw68bytqk.jpg)

**Rung 7 — fill lamp**
![Rung 7](https://dev-to-uploads.s3.us-east-2.amazonaws.com/uploads/articles/gcdq7hfqcbtid4kljtss.jpg)

**Rung 8 — discharge lamp**
![Rung 8](https://dev-to-uploads.s3.us-east-2.amazonaws.com/uploads/articles/8f6djjdq3h14j1ut7i0x.jpg)

**Rung 9 — elapsed fill time in seconds**
![Rung 9](https://dev-to-uploads.s3.us-east-2.amazonaws.com/uploads/articles/ycefx2x4h91m8sp86lfg.jpg)

**Rung 10 — remaining fill time**
![Rung 10](https://dev-to-uploads.s3.us-east-2.amazonaws.com/uploads/articles/m0tc6qhmvtu0y765hy23.jpg)

**Rung 11 — write countdown to the display register**
![Rung 11](https://dev-to-uploads.s3.us-east-2.amazonaws.com/uploads/articles/ix1ka0l6za7oec0qatya.jpg)

**Rung 12 — elapsed discharge time in seconds**
![Rung 12](https://dev-to-uploads.s3.us-east-2.amazonaws.com/uploads/articles/kplzunxjh01x2uqsi1ef.jpg)

**Rung 13 — remaining discharge time**
![Rung 13](https://dev-to-uploads.s3.us-east-2.amazonaws.com/uploads/articles/zxpfk4e0p01hamnrlbcp.jpg)

**Rung 14 — write countdown to the display register**
![Rung 14](https://dev-to-uploads.s3.us-east-2.amazonaws.com/uploads/articles/7ryhzmdayfqblwnrubpb.jpg)

</details>

---

## Simulator driver setup

In Factory I/O, select the **Modbus TCP/IP Server** driver:

```text
Port                : 502
Slave ID            : 1
Network adapter     : the adapter the PLC can reach
Write Digital       : Inputs              # simulator -> PLC
Read Digital        : Coils               # simulator <- PLC
Write Register      : Input Registers
Read Register       : Holding Registers
Scale               : 1
I/O points          : 3 DI, 4 DO, 0 register inputs, 1 register output
```

![Factory I/O driver view with the Modbus mapping](https://dev-to-uploads.s3.us-east-2.amazonaws.com/uploads/articles/26oln1hi0bqxzoj1kmfi.jpg)

![Factory I/O driver configuration](https://dev-to-uploads.s3.us-east-2.amazonaws.com/uploads/articles/msy2d9nt3n3r7xu47tsj.jpg)

---

## Running it

1. Install **Factory I/O** and open the scene `3 - Filling Tank (Timers)`.
2. Start the **OpenPLC Runtime** and confirm from the console that it reports `Server listening on 0.0.0.0:502`, a successful master connection, and `PLC State: RUNNING`.
3. In the **OpenPLC Editor**, create the project, set the device target, and configure the Modbus server plus the remote device with the mapping above.
4. Write the 14 rungs, then download the program to the runtime.
5. Start the Factory I/O **Modbus TCP/IP Server** driver and wait for the green connection indicator.
6. Attach the editor's debugger, press **Fill**, and watch the rungs and the tank at the same time.

---

## Verifying it

Don't trust the 3D window on its own — check the network and the PLC's I/O image.

```bash
# Can the PLC side reach the simulator?
ping 192.168.56.1

# Is something listening on 502?
netstat -ano | findstr :502     # Windows
ss -ltnp | grep 502             # Linux / macOS
```

Then read the live outputs straight from the runtime's own slave server:

```python
# pip install pymodbus
from pymodbus.client import ModbusTcpClient

client = ModbusTcpClient("127.0.0.1", port=502)
client.connect()

coils = client.read_coils(0, 4)               # %QX0.0 .. %QX0.3
regs  = client.read_holding_registers(0, 1)   # %QW0 = Timer_Disp

print("Fill valve      :", coils.bits[0])
print("Discharge valve :", coils.bits[1])
print("Fill lamp       :", coils.bits[2])
print("Discharge lamp  :", coils.bits[3])
print("Countdown       :", regs.registers[0])

client.close()
```

*Depending on your pymodbus version you may need `read_coils(0, 4, slave=1)` or `device_id=1`.*

While the tank is filling you should see the fill valve and lamp TRUE, the countdown decreasing, and the discharge valve FALSE. Press **Discharge** mid-fill and nothing should change — that is the interlock, seen from outside the PLC.

**Live fill phase** — Rung 1 energised, timer at 2.2 s elapsed / 7.8 s remaining, panel display reading 8:

![Debugger during the fill phase](https://dev-to-uploads.s3.us-east-2.amazonaws.com/uploads/articles/sqp3caixwgljnbkfulxv.jpg)

**Live discharge phase** — Rung 4 energised, fill timer held at 10.0 s, discharge timer at 1.9 s / 8.1 s remaining, display 8:

![Debugger during the discharge phase](https://dev-to-uploads.s3.us-east-2.amazonaws.com/uploads/articles/7zlfv53o6kea5zvjsa55.jpg)

---

## Gotchas

| Mistake | What you see | Fix |
|---|---|---|
| Mismatched slave IDs on the two ends | Silent timeouts, no useful error | Use the same slave ID on both sides |
| Starting the PLC before the simulator's driver | PLC connects, but nothing moves | Start the driver first, then check the connection indicator |
| Binding the simulator's server to the wrong adapter | Master never connects | Bind it to the adapter the PLC can actually reach |
| Expecting a level value over Modbus | No analogue data ever arrives | Check the register input count — if it is 0, the scene is timer-based |
| Level-sensed buttons, no edge detection | Holding the button restarts the cycle after the timer resets | Add a rising edge (`R_TRIG`) in front of each button contact |
| Hard-coding the preset in two places | Change `T#10s` and the countdown is still wrong | Use one constant for the duration |
| Forgetting the display is an integer register | Display never updates or looks off by one | Convert explicitly (`TO_INT`) before writing to `%QW0` |
| Something else already using port 502 | The slave plugin fails to bind | Check what is listening on 502 before starting |

---

## Repository layout

```text
.
├── README.md
├── docs/
│   ├── io-mapping.md          # signal table, FC codes, PLC addresses
│   └── images/                # screenshots used in this README
├── plc/
│   └── Tank_Filling/          # OpenPLC Editor project (program `main`)
│       └── main.ld            # 14 rungs of ladder logic
└── scripts/
    └── verify_modbus.py       # reads coils + holding register from the runtime
```

---

## What I'd add next

- An **emergency stop** that forces both valves closed regardless of phase
- **Edge detection** on the buttons so each phase is strictly one-shot
- A **level sensor** variant, to compare timer-based control against feedback control
- A small **HMI** reading the same Modbus server used for verification
