# ForeverFogBeGone!

One button on the minimap. Click it and the volumetric fog is gone; click it
again and it is back.

<img src="curseforge/foreverfogbegone-400.png" width="128" alt="the addon's icon: fog bands with a red stroke through them">

That is the whole addon. It does what `/console volumeFog 0` does, without
your having to remember the name of the setting or type it again after every
time the console settings are wiped.

## Using it

Click the button. The sign is lit when the fog is off — the button shows what
it has done, not what it will do — and greyed when the fog is back. Drag it
to move it around the minimap; where you put it is remembered.

| command | what it does |
| --- | --- |
| `/fogbegone`, `/ffbg` | the same as clicking |
| `/ffbg hide` | put the button away; the command still works |
| `/ffbg show` | bring it back |
| `/ffbg reset` | put it back where it started |

It will not change the setting while you are in combat, and says so rather
than failing quietly. On a client that has no `volumeFog` setting it says
that too, instead of erroring.

## What is in it

`Core.lua`, one icon, and nothing else — no libraries. LibDBIcon would be four
files and a dependency for one button, and this addon *is* one button.

`Tools/make_icon.py` draws the icon. It is drawn at 1024 pixels and shrunk,
because the minimap shows it at about twenty, and every decision in it follows
from those twenty pixels: a dark disc so it reads against snow and against a
night sky, fog bands with hard white cores because a soft gradient at that
size is a grey smudge, and one diagonal stroke, thin enough that the fog is
still visible under it.

`tests/button.test.lua` covers the button, the toggle, the picture following
the setting, the combat refusal, the missing-setting case and the slash
commands. Ten deliberate breakages of `Core.lua` each fail it.

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




