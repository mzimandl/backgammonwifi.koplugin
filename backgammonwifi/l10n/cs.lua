-- Czech translation of the plugin's strings (msgid → translation), see backgammonwifi/l10n.lua.
-- tests/run.lua checks that every _("…") in main.lua has an entry here.
return {
    -- menu
    ["Backgammon"] = "Vrchcáby",
    ["Backgammon (Wi-Fi)"] = "Vrchcáby",
    ["Host a game"] = "Založit hru",
    ["Find a game"] = "Najít hru",
    ["Join by address…"] = "Připojit se podle adresy…",
    ["Your name: %1"] = "Vaše jméno: %1",
    ["Your name"] = "Vaše jméno",
    ["Shown to the other player and in the list of games."] = "Zobrazí se druhému hráči a v seznamu her.",
    ["Player"] = "Hráč",
    ["Save"] = "Uložit",
    ["Rules"] = "Pravidla",
    [ [[Each player has 15 checkers and moves them around the board by the numbers rolled on two dice, towards their home board (points 1–6, bottom right). Doubles are played four times. Both dice must be used when possible; when only one can be used, it must be the larger one if it can be played.

A checker may land on a point with at most one opposing checker; that checker is hit and goes to the bar. Checkers on the bar must enter the opponent's home board before any other move.

Once all 15 checkers are in the home board, they are borne off. Whoever bears off all their checkers first wins.

Before rolling, a player may offer to double the stakes (Double) when the doubling cube is in the middle or theirs. The opponent either takes – the game goes on for twice as much and the cube becomes theirs – or drops and loses the game at the stakes before the offer. The cube is in the tray on the right: in the middle until the first double, then on its owner's side.

The winner scores the stakes shown by the cube; twice as much (gammon) when the loser hasn't borne off any checker, three times (backgammon) when they also still have a checker on the bar or in the winner's home board.

Both devices must be on the same Wi-Fi network. One player hosts the game, the other finds it in Find a game or joins by the address shown on the host's screen.]] ] =
        [[Každý hráč má 15 kamenů a posouvá je po desce o čísla hozená dvěma kostkami směrem do svého domova (pole 1–6 vpravo dole). Dvojice se hrají čtyřikrát. Je-li to možné, musí se využít obě kostky; lze-li zahrát jen jednu, musí to být ta vyšší, pokud jde zahrát.

Kámen smí vstoupit na pole, kde je nejvýš jeden soupeřův kámen; ten je vyhozen a jde na bar. Kameny z baru se musí nejdřív vrátit do hry v soupeřově domově, teprve pak lze táhnout jinými.

Jakmile jsou všech 15 kamenů v domově, vyvádějí se z desky. Kdo první vyvede všechny své kameny, vyhrává.

Před hodem smí hráč nabídnout zdvojení sázky (Zdvojit), pokud je zdvojovací kostka uprostřed nebo patří jemu. Soupeř buď přijme – hraje se o dvojnásobek a kostka patří jemu –, nebo odmítne a prohrává hru o dosavadní sázku. Kostka je v přihrádce vpravo: do prvního zdvojení uprostřed, potom na straně svého majitele.

Vítěz získá sázku, kterou ukazuje kostka; dvojnásobek (gammon), pokud poražený nevyvedl ani jeden kámen, trojnásobek (backgammon), pokud mu navíc zůstal kámen na baru nebo v domově vítěze.

Obě zařízení musí být ve stejné síti Wi-Fi. Jeden hráč hru založí, druhý ji najde v Najít hru nebo se připojí podle adresy zobrazené na obrazovce zakládajícího hráče.]],

    -- joining
    ["Join by address"] = "Připojit se podle adresy",
    ["The address is shown on the host's screen."] = "Adresa je zobrazena na obrazovce zakládajícího hráče.",
    ["Cancel"] = "Zrušit",
    ["Join"] = "Připojit",
    ["Invalid address"] = "Neplatná adresa",
    ["Searching for games…"] = "Hledání her…",
    ["Cannot search for games: %1"] = "Hry nelze hledat: %1",
    ["Cannot host a game: %1"] = "Hru nelze založit: %1",
    ["Connecting to %1…"] = "Připojování k %1…",
    ["Cannot connect to %1: %2"] = "Nelze se připojit k %1: %2",
    ["Connecting…"] = "Připojování…",

    -- game screen
    ["Opponent: %1"] = "Soupeř: %1",
    ["Opponent: %1 · points %2 : %3"] = "Soupeř: %1 · body %2 : %3",
    ["Waiting for an opponent. Your address: %1"] = "Čeká se na soupeře. Vaše adresa: %1",
    ["Waiting for an opponent."] = "Čeká se na soupeře.",
    ["Waiting for %1…"] = "Čeká se na %1…",
    ["You rolled %1: no move possible. Tap Done."] = "Hodili jste %1: nelze táhnout. Klepněte na Hotovo.",
    ["All dice played. Tap Done, or Undo to take a move back."] =
        "Všechny kostky jsou zahrané. Klepněte na Hotovo, nebo tah vraťte tlačítkem Zpět.",
    ["Tap a framed point to move the checker there, or another checker."] =
        "Klepnutím na orámované pole tam kámen přesunete, případně vyberte jiný kámen.",
    ["Your turn (%1): tap a checker to move."] = "Jste na tahu (%1): klepněte na kámen, kterým chcete táhnout.",
    ["%1 is playing %2…"] = "%1 hraje %2…",
    ["%1 is rolling…"] = "%1 hází…",
    ["Pips: you %1, %2 %3"] = "Počet ok: vy %1, %2 %3",
    ["You won!"] = "Vyhráli jste!",
    ["Points: %1"] = "Body: %1",
    ["gammon"] = "gammon",
    ["backgammon"] = "backgammon",
    ["You offered to double the stakes to %1. Waiting for %2…"] = "Nabídli jste zdvojení sázky na %1. Čeká se na hráče %2…",
    ["%1 offers to double to %2. Take and play on for %2, or drop and lose %3."] =
        "%1 nabízí zdvojení na %2. Přijměte a hrajte o %2, nebo odmítněte a prohrajte %3.",
    ["Your turn: tap Roll or the board to roll the dice, or Double to double the stakes."] =
        "Jste na tahu: hoďte kostkami (Hodit nebo klepnutí na desku), nebo nabídněte zdvojení sázky (Zdvojit).",
    ["Double"] = "Zdvojit",
    ["Take"] = "Přijmout",
    ["Drop"] = "Odmítnout",
    ["Drop the double and lose this game?"] = "Odmítnout zdvojení a prohrát tuto hru?",
    ["%1 won."] = "Vyhrává %1.",
    ["%1 wants to play again."] = "%1 chce hrát znovu.",
    ["Close"] = "Zavřít",
    ["Undo"] = "Zpět",
    ["Roll"] = "Hodit",
    ["%1 rolled %2."] = "%1 hází %2.",
    ["Opening roll: tap Roll or the board. The higher die starts."] = "Úvodní hod: klepněte na Hodit nebo na desku. Začíná vyšší kostka.",
    ["You rolled %1. Waiting for %2…"] = "Hodili jste %1. Čeká se na hráče %2…",
    ["Both rolled %1: roll again."] = "Oba hody jsou %1: házejte znovu.",
    ["Your turn: tap Roll or the board to roll the dice."] = "Jste na tahu: hoďte kostkami tlačítkem Hodit nebo klepnutím na desku.",
    ["Done"] = "Hotovo",
    ["Play again"] = "Hrát znovu",
    ["The checker cannot move there."] = "Kámen tam táhnout nemůže.",
    ["Enter your checkers from the bar first."] = "Nejdřív vraťte do hry kameny z baru.",
    ["This checker cannot move."] = "Tímto kamenem nelze táhnout.",
    ["Leave the game?"] = "Opustit hru?",
    ["Leave"] = "Odejít",

    -- game events
    ["The other device has a different version of Backgammon."] = "Druhé zařízení má jinou verzi hry Vrchcáby.",
    ["This game already has two players."] = "Tato hra už má dva hráče.",
    ["The opponent"] = "Soupeř",
    ["%1 left."] = "%1 odchází.",
    ["%1 left the game."] = "%1 opouští hru.",
    ["Connection to %1 lost."] = "Spojení se soupeřem %1 bylo přerušeno.",
    ["Connection lost."] = "Spojení bylo přerušeno.",
    ["bar"] = "bar",
    ["off"] = "ven",
    ["%1 joined the game."] = "Do hry vstupuje %1.",
    ["You joined %1's game."] = "Připojeno ke hře: %1.",
    ["Opening roll: you %1, %2 %3."] = "Úvodní hod: vy %1, %2 %3.",
    ["You start."] = "Začínáte vy.",
    ["%1 starts."] = "Začíná %1.",
    ["%1 played %2."] = "%1 táhne %2.",
    ["%1 cannot move."] = "%1 nemůže táhnout.",
    ["Your checkers hit: %1."] = "Vyhozené kameny: %1.",
    ["New game."] = "Nová hra.",
    ["You took the double: the stakes are %1."] = "Přijali jste zdvojení: sázka je teď %1.",
    ["%1 took the double: the stakes are %2."] = "%1 přijímá zdvojení: sázka je teď %2.",
    ["You dropped the double."] = "Odmítli jste zdvojení.",
    ["%1 dropped the double."] = "%1 zdvojení odmítá.",
}
