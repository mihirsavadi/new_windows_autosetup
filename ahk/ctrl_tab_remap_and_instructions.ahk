  #Requires AutoHotkey v2.0

/*
===========================================================
  AutoHotkey v2 Script for Mac-Style Key Remapping
===========================================================

This script assumes you've used **SharpKeys** to make a 
hardware-level swap between Left Alt and Left Ctrl:

    ▸ Left Alt  (Scan Code 00_38)  → Left Ctrl (Scan Code 00_1D)
    ▸ Left Ctrl (Scan Code 00_1D)  → Left Alt  (Scan Code 00_38)

🔧 Why SharpKeys?
-----------------------------------------------------------
AutoHotkey and PowerToys only simulate key behavior at the
software level, which does NOT work for mouse interactions
like Ctrl+Click in Chrome.

SharpKeys writes to the Windows Registry and remaps keys
at the scancode level. This ensures ALL system behavior
(including mouse + modifier input) behaves like the keys
were physically swapped.

📦 What This Script Does:
-----------------------------------------------------------
After SharpKeys has done the low-level swap, this script
adds a single fix:

    ▸ Pressing Ctrl + Tab (i.e. thumb + Tab)
      will simulate Alt + Tab to open the Windows
      app switcher (which relies on Alt and can't be 
      easily remapped via registry).

💡 Notes:
-----------------------------------------------------------
▪️ You must reboot your system after using SharpKeys.
▪️ To autorun this script at startup:
   - Save it as a .ahk file
   - Create a shortcut and place it in:
       shell:startup

===========================================================
*/

; LAlt::LCtrl
; LCtrl::LAlt
; The above part doing via SharpKeys.

LCtrl & Tab::AltTab