# menu.ps1 - What Every Screen Looks Like (v2026-09-14)

> Sample transcripts of `.\menu.ps1`. `<-` marks what YOU type (just a number or y/n, then Enter).
> Pressing Enter alone accepts the `[default N]`. Nothing runs until the final "Run this now?".

## The main menu (always first)
```

============================================
   Combined ESP-WIFI-MESH launcher
============================================

What do you want to do?
   [1] Run a board  (baseline / blackhole / wormhole)
   [2] Export a board only  (it already ran; just pull CSVs)
   [3] Wipe / full-erase a board  (start empty)
   [4] Identify a board  (read its MAC / node number)
   [5] Verify a run  (paper-backed 3-sigma attack check)
   [6] Quit
Choice [default 1]: 1        <- Run a board
```
Then it asks which board (COM port). If boards are plugged in it lists them:
```

Which COM port (board)?
   [1] COM3
   [2] COM8
   [3] Type it manually
Choice [default 1]: 2        <- COM8
```
(If no boards are detected it prints "(No COM ports detected...)" and just asks:
`Enter COM port (e.g. COM8):` - you type `COM8`.)

---

## Sample A - BASELINE, ROOT board (root goes LAST, with analysis)
```
Mesh role of THIS board?
   [1] root
   [2] child / victim
Choice [default 2]: 1        <- root

Topology (flash EVERY board in the run the SAME)?
   [1] tree     (default self-organising)
   [2] star     (all direct children of root)
   [3] linear   (forced chain)
   [4] partial  (physical placement)
Choice [default 1]: 1        <- tree (just press Enter)

Attack for this run?
   [1] none (baseline)
   [2] blackhole
   [3] wormhole
Choice [default 1]: 1        <- none

Board label / node id (e.g. node5), blank to skip: root1
Flash the firmware first? (needed to apply topology/attack) [Y/n]: y
Wipe/erase board BEFORE this run (fresh, unstacked run)? [Y/n]: y
Export the CSVs when you exit the monitor? [Y/n]: y

Where was this run captured?
   [1] home
   [2] G402
   [3] DLSU_Library
   [4] Goks
Choice [default 1]: 1        <- home

Auto-run analysis (M6+M7+M8) after export? (do this on the ROOT, exported LAST) [y/N]: y
Wipe the board AFTER a good export? [y/N]: n

Equivalent command:
   .\run.ps1 -Port COM8 -Role root -Topology tree -Attack none -Label root1 -Wipe -Flash -Export -Location home -Analyze
Run this now? [Y/n]: y
```
> `-Location` is required whenever `-Export`/`-Clean`/`-Analyze` is used — `run.ps1` throws
> without it. Pick the SAME location for every board in a run.
-> hands off to run.ps1: it flashes, opens the serial monitor; you press **Ctrl+]** at `terminate`
to export + analyze.

---

## Sample B - BASELINE, VICTIM board
```
Mesh role of THIS board?
   ...
Choice [default 2]:          <- (Enter = child/victim)
Topology ...  Choice [default 1]:      <- Enter = tree
Attack for this run?  Choice [default 1]:   <- Enter = none
Board label / node id (e.g. node5), blank to skip: node3
Flash the firmware first? ... [Y/n]:      <- Enter = yes
Wipe/erase board BEFORE this run? [Y/n]:  <- Enter = yes
Export the CSVs when you exit the monitor? [Y/n]:  <- Enter = yes
Where was this run captured?  Choice [default 1]:  <- Enter = home
Wipe the board AFTER a good export? [y/N]:          <- Enter = no
   (no Analyze question - that only appears for the ROOT)

Equivalent command:
   .\run.ps1 -Port COM3 -Role child -Topology tree -Attack none -Label node3 -Wipe -Flash -Export -Location home
Run this now? [Y/n]:
```

---

## Sample C - BLACKHOLE, ATTACKER board
```
Mesh role of THIS board?  Choice [default 2]:     <- child
Topology ...  Choice [default 1]: 3               <- linear
Attack for this run?  Choice [default 1]: 2        <- blackhole

Blackhole role of THIS board?
   [1] attacker  (relay that forwards then drops victim probes)
   [2] victim    (sends its probes to the attacker MAC)
Choice [default 1]: 1        <- attacker

Board label / node id (e.g. node5), blank to skip: node5
Flash ... [Y/n]: y   Wipe ... [Y/n]: y   Export ... [Y/n]: y
Where was this run captured? ... Choice [default 1]: 2   <- G402
Wipe after? [y/N]: n

Equivalent command:
   .\run.ps1 -Port COM5 -Role child -Topology linear -Attack blackhole -Label node5 -BlackholeRole attacker -Wipe -Flash -Export -Location G402
Run this now? [Y/n]:
```
(A blackhole **victim** looks the same but you pick `[2] victim` -> `-BlackholeRole victim`.)

---

## Sample D - WORMHOLE, NODE B (note the wiring reminder it prints)
```
Mesh role of THIS board?  Choice [default 2]:     <- child
Topology ...  Choice [default 1]:                 <- tree
Attack for this run?  Choice [default 1]: 3        <- wormhole

Wormhole tunnel end of THIS board? (UART cable A<->B required)
   [1] A  (exit / root-side: re-injects to root)
   [2] B  (entry / leaf-side: captures + tunnels)
Choice [default 2]: 2        <- B

Board label / node id (e.g. node5), blank to skip: node3
Flash ... [Y/n]: y   Wipe ... [Y/n]: y   Export ... [Y/n]: y
Where was this run captured? ... Choice [default 1]:  <- home
Wipe after? [y/N]: n

REMINDER (wormhole): wire the UART tunnel BEFORE powering on -
   Node A GPIO17(TX) -> Node B GPIO16(RX), Node A GPIO16(RX) -> Node B GPIO17(TX), shared GND.
   Run all THREE boards (root + A + B) with the same Attack=wormhole and Flash.

Equivalent command:
   .\run.ps1 -Port COM3 -Role child -Topology tree -Attack wormhole -Label node3 -WormholeEnd B -Wipe -Flash -Export -Location home
Run this now? [Y/n]:
```
(Node A is identical but you pick `[1] A` -> `-WormholeEnd A`.)

---

## Sample E - EXPORT a board only (already ran)
```
Choice [default 1]: 2        <- Export a board only
Which COM port (board)? ... -> COM8
Board role?  [1] child / victim  [2] root   Choice [default 1]: 2    <- root
Topology this run used?  [1] tree [2] star [3] linear [4] partial   Choice [default 1]: 1
Attack this run used?  [1] none (baseline) [2] blackhole [3] wormhole  Choice [default 1]: 2   <- blackhole
Where was this run captured? ... Choice [default 1]: 1   <- home
Board label / node id (e.g. node5), blank to skip: root1
Repeat number (r1/r2/r3 -> 1/2/3) [default 1]: 1
Wipe the board AFTER a good download? [y/N]: n

Equivalent command:
   python tools\export_logs.py --port COM8 --role root --topology tree --location home --attack blackhole --repeat 1 --label root1
Run this now? [Y/n]:
```

---

## Sample F - WIPE / full-erase a board
```
Choice [default 1]: 3        <- Wipe / full-erase
Which COM port (board)? ... -> COM8
Board role (only matters if you also re-flash)?  [1] child / victim  [2] root  Choice [default 1]: 1
FULL chip erase + re-flash? (fixes 'storage full' / crash-loops) [y/N]: y    <- yes

Equivalent command:
   .\run.ps1 -Port COM8 -Role child -Wipe -Flash
Run this now? [Y/n]:
```
(Answer `n` to the full-erase question for a light log-wipe instead: `.\run.ps1 -Port COM8 -Role child -Wipe`.)

---

## Sample G - IDENTIFY a board (which node is this?)
```
Choice [default 1]: 4        <- Identify a board
Which COM port (board)? ... -> COM8

Equivalent command:
   python tools\board_check.py --port COM8
Run this now? [Y/n]: y
```
-> prints the board's MAC and node number so you can label it on your field log.

---

## Sample H - VERIFY a run (paper-backed 3-sigma)
```
Choice [default 1]: 5        <- Verify a run

Which attack to verify?
   [1] auto-detect
   [2] blackhole
   [3] wormhole
Choice [default 1]: 2        <- blackhole

Topology?  [1] tree [2] star [3] linear [4] partial   Choice [default 1]: 3   <- linear
Where was this run captured?  Choice [default 1]: 1   <- home
feature_table.csv path [default: <repo>\analysis\blackhole\linear\home\feature_table.csv]:
   <- Enter to accept the default

Equivalent command:
   python tools\verify_attack.py <repo>\analysis\blackhole\linear\home\feature_table.csv --attack blackhole
Run this now? [Y/n]: y
```
-> prints the per-feature 3-sigma report and a `CONFIRMED` / `NOT CONFIRMED` verdict. This is
the panel-cited check (Zhukabayeva 2025 method) — no board touched, needs M7's
`feature_table.csv` to already exist (run analysis first, or pick `-Analyze` in Sample A).

---

### Notes
- **Enter alone = the default.** The defaults are set so a normal baseline run is almost all
  Enters (child, tree, none, flash yes, wipe yes, export yes).
- It **always shows the equivalent long command** and asks "Run this now?" before doing anything,
  so you can bail with `n` and nothing happens.
- Only these menus/prompts appear; there are no hidden steps.
