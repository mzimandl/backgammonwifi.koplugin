# Backgammon for KOReader

Backgammon for two players, each on their own e-reader, over Wi-Fi. English, with a Czech translation (Vrchcáby).

## Playing
Both devices must be on the same Wi-Fi network. In the menu: **Tools → Backgammon**.

- **Host a game**: one player opens a game. The screen shows the device's address.
- **Find a game**: the other player sees games open on the local network (UDP broadcast) and taps one to join.
- **Join by address…**: when the search finds nothing (some networks block broadcasts), type the address shown on the host's screen, e.g. `192.168.1.10` (or `192.168.1.10:7541`).
- **Your name**: shown to the other player and in the list of games (default: the device model).

### Rules
- Each player has 15 checkers. The host plays white, the guest black. Each player sees the board from their own side: their home board (points 1–6) bottom right, checkers moving counter-clockwise towards it.
- The game starts as soon as the guest joins: the host's device rolls one die for each player, the higher one starts and plays both dice. After that each device rolls for its own player when their turn begins.
- Doubles are played four times. Both dice must be used when possible; when only one can be used, it must be the larger one if it can be played. The game enforces this: only legal moves can be made.
- A point with two or more opposing checkers is blocked. A single opposing checker is hit and goes to the bar; checkers on the bar must enter the opponent's home board before any other move.
- Once all 15 checkers are in the home board they are borne off; a higher die than needed bears off from the highest occupied point. Whoever bears off all their checkers first wins. **Play again** starts a new game once both players tap it; the subtitle counts the games won.

### Moving
Tap a checker to pick it up (it turns gray): the points it can move to are framed (the tray on the right when it can be borne off). Tap a framed point to move it there; one die is used per move. Checkers on the bar are picked up automatically. **Undo** takes back moves, **Done** ends the turn once the dice are played (or when no move is possible).

Board: own dice on the right half, the opponent's on the left; a used die is gray. A bar under a point number marks where the opponent's last moves ended. Borne-off checkers are stacked in the tray on the right (own at the bottom). The status line shows the last moves of the opponent from your side (`13/7* bar/22 3/off`, `*` = hit) and the pip counts.

## Network
- TCP 7541 (the game, host), UDP 7542 (host answers searches), UDP 7543 (searching device listens for answers).
- On Kindle the plugin opens these ports in the firewall (iptables) for the time of the game.
- The device doesn't go to standby during a game; going to sleep ends it.

## Development
Off-device tests (`lua5.1` works too when luajit isn't installed):

```bash
luajit tests/run.lua
```

```bash
luajit tests/smoke.lua
```

`SEED=n luajit tests/smoke.lua` changes the dice, and with them which player starts.
