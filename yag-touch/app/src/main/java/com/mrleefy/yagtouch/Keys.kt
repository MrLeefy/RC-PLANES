package com.mrleefy.yagtouch

import android.view.KeyEvent

/** Pseudo key codes for mouse buttons, used by on-screen buttons. */
const val MOUSE_LEFT = -1
const val MOUSE_RIGHT = -2

/** Keys the user can add as on-screen buttons. */
val KEY_CHOICES: List<Pair<String, Int>> = buildList {
    add("Mouse Left" to MOUSE_LEFT)
    add("Mouse Right" to MOUSE_RIGHT)
    add("Space" to KeyEvent.KEYCODE_SPACE)
    add("Enter" to KeyEvent.KEYCODE_ENTER)
    add("Esc" to KeyEvent.KEYCODE_ESCAPE)
    add("Shift" to KeyEvent.KEYCODE_SHIFT_LEFT)
    add("Ctrl" to KeyEvent.KEYCODE_CTRL_LEFT)
    add("Alt" to KeyEvent.KEYCODE_ALT_LEFT)
    add("Tab" to KeyEvent.KEYCODE_TAB)
    add("Backspace" to KeyEvent.KEYCODE_DEL)
    add("Up" to KeyEvent.KEYCODE_DPAD_UP)
    add("Down" to KeyEvent.KEYCODE_DPAD_DOWN)
    add("Left" to KeyEvent.KEYCODE_DPAD_LEFT)
    add("Right" to KeyEvent.KEYCODE_DPAD_RIGHT)
    for (c in 'A'..'Z') add(c.toString() to KeyEvent.KEYCODE_A + (c - 'A'))
    for (n in 0..9) add(n.toString() to KeyEvent.KEYCODE_0 + n)
    for (f in 1..12) add("F$f" to KeyEvent.KEYCODE_F1 + (f - 1))
    add("Page Up" to KeyEvent.KEYCODE_PAGE_UP)
    add("Page Down" to KeyEvent.KEYCODE_PAGE_DOWN)
    add("Home" to KeyEvent.KEYCODE_MOVE_HOME)
    add("End" to KeyEvent.KEYCODE_MOVE_END)
    add("Insert" to KeyEvent.KEYCODE_INSERT)
    add("Delete" to KeyEvent.KEYCODE_FORWARD_DEL)
}

fun keyLabel(code: Int): String = KEY_CHOICES.firstOrNull { it.second == code }?.first ?: "?"
