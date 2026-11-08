# Backgammon (Wi-Fi) for KOReader

Backgammon for two players, each on their own e-reader, over Wi-Fi. English, with a Czech translation (Vrchcáby). Not to be confused with [backgammon.koplugin](https://github.com/EmirErtorer/backgammon.koplugin), a game against the computer; this one is played between two readers and installs as `backgammonwifi`.

## Playing
Both devices must be on the same Wi-Fi network. In the menu: **Tools → Backgammon (Wi-Fi)**.

- **Host a game**: one player opens a game. The screen shows the device's address.
- **Find a game**: the other player sees games open on the local network (UDP broadcast) and taps one to join.
- **Join by address…**: when the search finds nothing (some networks block broadcasts), type the address shown on the host's screen, e.g. `192.168.1.10` (or `192.168.1.10:7541`).
- **Your name**: shown to the other player and in the list of games (default: the device model).

### Rules
- Each player has 15 checkers. The host plays white, the guest black. Each player sees the board from their own side: their home board (points 1–6) bottom right, checkers moving counter-clockwise towards it.
- The game starts with the opening roll as soon as the guest joins: each player rolls one die, the higher one starts and plays both dice; equal dice are rolled again. After that each player rolls their own dice when their turn begins. **Roll** (or a tap on the board) shows a short animation and then the roll.
- Both devices need version 0.3.0 or newer (the doubling cube changed the protocol; older versions don't find or join newer games).
- Doubles are played four times. Both dice must be used when possible; when only one can be used, it must be the larger one if it can be played. The game enforces this: only legal moves can be made.
- A point with two or more opposing checkers is blocked. A single opposing checker is hit and goes to the bar; checkers on the bar must enter the opponent's home board before any other move.
- Once all 15 checkers are in the home board they are borne off; a higher die than needed bears off from the highest occupied point. Whoever bears off all their checkers first wins. **Play again** starts a new game once both players tap it.
- The doubling cube: before rolling, the player whose turn it is may tap **Double** when the cube is in the middle or theirs. The opponent either taps **Take** (the stakes double, the cube becomes theirs, so only they can redouble) or **Drop** (they lose the game at the stakes before the offer). The cube goes up to 64. It sits in the tray on the right: in the middle (showing 64) until the first double, then on its owner's side.
- Scoring: the winner gets the stakes shown by the cube; twice that for a gammon (the loser hasn't borne off any checker) and three times for a backgammon (the loser also still has a checker on the bar or in the winner's home board). The subtitle adds up the points of all games played since the guest joined. There is no match length: play as many games as you like.

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

## License

This plugin is free software: you can redistribute it and/or modify it under the
terms of the GNU Affero General Public License as published by the Free Software
Foundation, either version 3 of the License, or (at your option) any later version,
like KOReader itself. See [LICENSE](LICENSE).
