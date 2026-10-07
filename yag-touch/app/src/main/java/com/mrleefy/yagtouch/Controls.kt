package com.mrleefy.yagtouch

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.os.SystemClock
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import org.json.JSONArray
import org.json.JSONObject
import kotlin.math.abs
import kotlin.math.hypot
import kotlin.math.min

/** What the overlay talks to; implemented by MainActivity. */
interface InputSink {
    fun key(code: Int, down: Boolean)
    fun mouseMove(dx: Float, dy: Float)
    fun mouseTo(xPx: Float, yPx: Float)
    fun mouseButton(button: Int, down: Boolean)
    fun editTap(c: Control)
}

/** One on-screen control. x/y are fractions of the view; size is a fraction of the short side. */
class Control(
    var type: String,   // "stick" or "btn"
    var x: Float,
    var y: Float,
    var key: Int = 0,   // btn: key code / MOUSE_*; stick: 0 = WASD, 1 = arrows
    var size: Float = 0.07f,
) {
    fun toJson() = JSONObject().put("t", type).put("x", x.toDouble()).put("y", y.toDouble())
        .put("k", key).put("s", size.toDouble())

    companion object {
        fun fromJson(o: JSONObject) = Control(
            o.getString("t"), o.getDouble("x").toFloat(), o.getDouble("y").toFloat(),
            o.getInt("k"), o.getDouble("s").toFloat()
        )

        fun defaults() = mutableListOf(
            Control("stick", 0.14f, 0.70f, 0, 0.13f),
            Control("btn", 0.88f, 0.78f, KeyEvent.KEYCODE_SPACE),
            Control("btn", 0.78f, 0.66f, KeyEvent.KEYCODE_ENTER),
            Control("btn", 0.96f, 0.64f, KeyEvent.KEYCODE_E),
            Control("btn", 0.70f, 0.82f, KeyEvent.KEYCODE_SHIFT_LEFT),
            Control("btn", 0.62f, 0.68f, KeyEvent.KEYCODE_CTRL_LEFT),
            Control("btn", 0.50f, 0.90f, MOUSE_LEFT),
            Control("btn", 0.58f, 0.90f, MOUSE_RIGHT),
        )
    }
}

class ControlsView(ctx: Context, private val sink: InputSink) : View(ctx) {
    var controls: MutableList<Control> = Control.defaults()
    var editMode = false
        set(v) { field = v; invalidate() }
    /** false = tap/drag act like an absolute mouse; true = trackpad (relative). */
    var padMode = false
    var onChanged: (() -> Unit)? = null

    private val density = ctx.resources.displayMetrics.density
    private val fill = Paint(Paint.ANTI_ALIAS_FLAG)
    private val line = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE; strokeWidth = 3f * density }
    private val text = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0xFFFFFFFF.toInt(); textAlign = Paint.Align.CENTER }

    private class Grab(val c: Control?, val kind: Int) { // kind: 0 control, 1 free pad touch
        var sx = 0f; var sy = 0f; var lx = 0f; var ly = 0f
        var t0 = 0L; var moved = false; var stickDx = 0f; var stickDy = 0f
        val held = HashSet<Int>()
    }
    private val grabs = HashMap<Int, Grab>()

    private fun radius(c: Control) = c.size * min(width, height)
    private fun cx(c: Control) = c.x * width
    private fun cy(c: Control) = c.y * height

    override fun onDraw(canvas: Canvas) {
        for (c in controls) {
            val r = radius(c)
            val g = grabs.values.firstOrNull { it.c === c }
            val on = g != null
            fill.color = if (on) 0x66FFFFFF else 0x33FFFFFF
            line.color = if (editMode) 0xCCFFB74D.toInt() else 0x88FFFFFF.toInt()
            if (c.type == "stick") {
                canvas.drawCircle(cx(c), cy(c), r * 1.5f, fill)
                canvas.drawCircle(cx(c), cy(c), r * 1.5f, line)
                val kx = cx(c) + (g?.stickDx ?: 0f) * r * 1.2f
                val ky = cy(c) + (g?.stickDy ?: 0f) * r * 1.2f
                fill.color = 0x88FFFFFF.toInt()
                canvas.drawCircle(kx, ky, r * 0.6f, fill)
                text.textSize = r * 0.4f
                canvas.drawText(if (c.key == 0) "WASD" else "ARROWS", cx(c), cy(c) + r * 1.95f, text)
            } else {
                canvas.drawCircle(cx(c), cy(c), r, fill)
                canvas.drawCircle(cx(c), cy(c), r, line)
                val label = keyLabel(c.key).let { if (it.startsWith("Mouse ")) "M" + it[6] else it }
                text.textSize = r * (if (label.length > 3) 0.5f else 0.8f)
                canvas.drawText(label, cx(c), cy(c) + text.textSize * 0.35f, text)
            }
        }
        if (editMode) {
            text.textSize = 14f * density
            canvas.drawText("Edit: drag to move, tap a control to resize/remove", width / 2f, 28f * density, text)
        }
    }

    private fun hit(x: Float, y: Float): Control? =
        controls.lastOrNull { hypot(x - cx(it), y - cy(it)) <= radius(it) * (if (it.type == "stick") 1.5f else 1.1f) }

    override fun onTouchEvent(e: MotionEvent): Boolean {
        when (e.actionMasked) {
            MotionEvent.ACTION_DOWN, MotionEvent.ACTION_POINTER_DOWN -> {
                val i = e.actionIndex
                begin(e.getPointerId(i), e.getX(i), e.getY(i))
            }
            MotionEvent.ACTION_MOVE -> for (i in 0 until e.pointerCount) move(e.getPointerId(i), e.getX(i), e.getY(i))
            MotionEvent.ACTION_UP, MotionEvent.ACTION_POINTER_UP -> {
                val i = e.actionIndex
                end(e.getPointerId(i), e.getX(i), e.getY(i), cancel = false)
            }
            MotionEvent.ACTION_CANCEL -> for (id in grabs.keys.toList()) end(id, 0f, 0f, cancel = true)
        }
        invalidate()
        return true
    }

    private fun begin(id: Int, x: Float, y: Float) {
        val c = hit(x, y)
        val g = Grab(c, if (c != null) 0 else 1)
        g.sx = x; g.sy = y; g.lx = x; g.ly = y; g.t0 = SystemClock.uptimeMillis()
        grabs[id] = g
        if (editMode) return
        if (c != null) {
            if (c.type == "btn") press(c.key, true, g)
        } else if (!padMode) {
            sink.mouseTo(x, y); sink.mouseButton(0, true)
        }
    }

    private fun move(id: Int, x: Float, y: Float) {
        val g = grabs[id] ?: return
        val dx = x - g.lx; val dy = y - g.ly
        if (abs(x - g.sx) + abs(y - g.sy) > 12 * density) g.moved = true
        g.lx = x; g.ly = y
        val c = g.c
        if (editMode) {
            if (c != null && g.moved) { c.x = (x / width).coerceIn(0.03f, 0.97f); c.y = (y / height).coerceIn(0.05f, 0.97f) }
            return
        }
        if (c == null) {
            if (padMode) sink.mouseMove(dx * 1.6f, dy * 1.6f) else sink.mouseTo(x, y)
        } else if (c.type == "stick") {
            val r = radius(c)
            var nx = (x - cx(c)) / (r * 1.2f); var ny = (y - cy(c)) / (r * 1.2f)
            val len = hypot(nx, ny)
            if (len > 1f) { nx /= len; ny /= len }
            g.stickDx = nx; g.stickDy = ny
            val (up, down, left, right) = if (c.key == 0)
                listOf(KeyEvent.KEYCODE_W, KeyEvent.KEYCODE_S, KeyEvent.KEYCODE_A, KeyEvent.KEYCODE_D)
            else listOf(KeyEvent.KEYCODE_DPAD_UP, KeyEvent.KEYCODE_DPAD_DOWN, KeyEvent.KEYCODE_DPAD_LEFT, KeyEvent.KEYCODE_DPAD_RIGHT)
            setHeld(g, up, ny < -0.35f); setHeld(g, down, ny > 0.35f)
            setHeld(g, left, nx < -0.35f); setHeld(g, right, nx > 0.35f)
        }
    }

    private fun end(id: Int, x: Float, y: Float, cancel: Boolean) {
        val g = grabs.remove(id) ?: return
        val c = g.c
        if (editMode) {
            if (c != null && !g.moved && !cancel) { sink.editTap(c); onChanged?.invoke() }
            else if (c != null) onChanged?.invoke()
            return
        }
        if (c == null) {
            if (!padMode) sink.mouseButton(0, false)
            else if (!cancel && !g.moved && SystemClock.uptimeMillis() - g.t0 < 250) {
                // Tap on the pad = left click; a tap while another finger is down = right click.
                val b = if (grabs.isNotEmpty()) 2 else 0
                sink.mouseButton(b, true); sink.mouseButton(b, false)
            }
        } else if (c.type == "btn") press(c.key, false, g)
        for (k in g.held.toList()) setHeld(g, k, false)
    }

    private fun setHeld(g: Grab, key: Int, want: Boolean) {
        if (want && g.held.add(key)) sink.key(key, true)
        else if (!want && g.held.remove(key)) sink.key(key, false)
    }

    private fun press(key: Int, down: Boolean, g: Grab) {
        when (key) {
            MOUSE_LEFT -> sink.mouseButton(0, down)
            MOUSE_RIGHT -> sink.mouseButton(2, down)
            else -> sink.key(key, down)
        }
    }

    fun toJson(): String = JSONArray().also { a -> controls.forEach { a.put(it.toJson()) } }.toString()

    fun loadJson(s: String?) {
        if (s.isNullOrEmpty()) return
        try {
            val a = JSONArray(s)
            controls = MutableList(a.length()) { Control.fromJson(a.getJSONObject(it)) }
        } catch (_: Exception) { /* keep defaults */ }
    }
}
