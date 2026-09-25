# ForeverFogBeGone!

One button on the minimap. Click it and the volumetric fog is gone from the
next start of the game; click it again and it is back.

<img src="curseforge/foreverfogbegone-400.png" width="128" alt="the addon's icon: fog bands with a red stroke through them">

That is the whole addon. It does what `/console volumeFog 0` does, without
your having to remember the name of the setting or type it again after every
time the console settings are wiped.

## Using it

<img width="2560" height="1440" alt="image" src="https://github.com/user-attachments/assets/6fb6549f-263e-42ed-b12e-98482a50662d" />

<img width="2560" height="1440" alt="image" src="https://github.com/user-attachments/assets/32961dc4-38e8-43aa-8920-28b1e7460e05" />


**Left-click** for the fog. The mist is crossed out when the fog is off and unstruck when it is back.
The button shows the state you chose.
Drag it to move it around the minimap; where you put it is remembered.

**Right-click** for sharpening. `ResampleAlwaysSharpen` decides whether the
picture is sharpened after being resampled, which is what happens whenever the
game is not drawing at the monitor's own resolution. There is no tick box for
it. The icon does not change for this one: it says the fog.

Neither setting is changed while you play. A click records your choice, and
the addon writes it when you log out or quit, so the game starts with it next
time. On Forever build 1.60.1.70009, turning the fog on in the world froze the
game until it was closed; a game that starts with the setting never did. The
tooltip shows what is waiting, and `/ffbg log` shows what was written and
whether it stuck. `/ffbg now!` writes it straight away, for a client where
that is safe again.

`/ffbg cvars <text>` lists the client's own console variables whose name
contains that text, with their current value and the client's description of
each. Nothing on disk knows what a client supports — `Config.wtf` holds only
what somebody has already changed — so the client is asked instead. That is
how to find the next setting worth a button.

## What is in it

`Core.lua`, one icon, and nothing else — no libraries. LibDBIcon would be four
files and a dependency for one button, and this addon *is* one button.

`Tools/make_icon.py` exports the approved PNG artwork in `Tools/` as 64-pixel
TGA textures and CurseForge images. Both fog states use the same square, painted
icon: crossed-out mist means fog is off; plain mist means fog is on.

`tests/button.test.lua` covers the button, the picture following the choice,
the missing-setting case, the slash commands, and the write itself: never on a
click, never on a `/reload`, once at logout, checked at the next load.

```
lua tests/button.test.lua
python Tools/make_icon.py --preview
```

## Where it runs

World of Warcraft: Forever (interface 16001) and Retail 12.1 share a manifest;
Classic Era has its own. The setting exists wherever the client has volumetric
fog; where it does not, the button says so.

<img width="2560" height="1440" alt="image" src="https://github.com/user-attachments/assets/618cb84d-3a8c-4adf-a952-78cd610f3dbc" />

<img width="2560" height="1440" alt="image" src="https://github.com/user-attachments/assets/0327fdaf-57c1-4766-a5ae-d597b5943afc" />

<img width="326" height="333" alt="image" src="https://github.com/user-attachments/assets/f58bd104-dafc-4a17-aa03-490b893a2c48" />

<img width="2560" height="1440" alt="image" src="https://github.com/user-attachments/assets/30f863b2-0a99-4dc7-9798-806546722d63" />

<img width="2560" height="1440" alt="image" src="https://github.com/user-attachments/assets/97fb06ff-6406-4974-938e-01de4d116d75" />






