package com.mrleefy.yagtouch

import android.annotation.SuppressLint
import android.app.Activity
import android.app.AlertDialog
import android.content.Context
import android.graphics.Color
import android.os.Bundle
import android.os.SystemClock
import android.view.Gravity
import android.view.KeyEvent
import android.view.View
import android.view.WindowManager
import android.view.inputmethod.InputMethodManager
import android.webkit.WebChromeClient
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.TextView

private const val HOME = "https://yag.im"

/**
 * yag.im in a WebView with an optional on-screen controller on top.
 * Controller output is real Android key events (sent to the WebView) plus
 * synthetic mouse events injected through a small JS helper.
 */
class MainActivity : Activity(), InputSink {
    private lateinit var web: WebView
    private lateinit var controls: ControlsView
    private lateinit var menuBtn: TextView
    private val prefs by lazy { getSharedPreferences("yagtouch", Context.MODE_PRIVATE) }
    private var playing = false
    private var density = 1f

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        density = resources.displayMetrics.density

        web = WebView(this).apply {
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            settings.mediaPlaybackRequiresUserGesture = false
            settings.setSupportZoom(false)
            webChromeClient = WebChromeClient()
            webViewClient = object : WebViewClient() {
                override fun onPageFinished(view: WebView, url: String) = injectHelper()
            }
            isFocusable = true
            isFocusableInTouchMode = true
        }

        controls = ControlsView(this, this).apply {
            loadJson(prefs.getString("layout", null))
            padMode = prefs.getBoolean("pad", false)
            visibility = View.GONE
            onChanged = { save() }
        }

        menuBtn = TextView(this).apply {
            text = "☰"
            textSize = 22f
            setTextColor(Color.WHITE)
            setBackgroundColor(0x88000000.toInt())
            gravity = Gravity.CENTER
            setOnClickListener { showMenu() }
        }

        val root = FrameLayout(this)
        root.addView(web, FrameLayout.LayoutParams(-1, -1))
        root.addView(controls, FrameLayout.LayoutParams(-1, -1))
        val s = (44 * density).toInt()
        root.addView(menuBtn, FrameLayout.LayoutParams(s, s, Gravity.TOP or Gravity.END))
        setContentView(root)

        web.loadUrl(prefs.getString("url", HOME) ?: HOME)
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) window.decorView.systemUiVisibility = (View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
            or View.SYSTEM_UI_FLAG_FULLSCREEN or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
            or View.SYSTEM_UI_FLAG_LAYOUT_STABLE or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
            or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION)
    }

    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        if (web.canGoBack()) web.goBack() else super.onBackPressed()
    }

    override fun onPause() { super.onPause(); prefs.edit().putString("url", web.url ?: HOME).apply(); web.onPause() }
    override fun onResume() { super.onResume(); web.onResume() }

    // ---- menu -------------------------------------------------------------

    private fun showMenu() {
        val items = arrayOf(
            if (playing) "Browse mode (hide controls)" else "Play mode (show controls)",
            "Mouse: " + if (controls.padMode) "trackpad (tap = click)  → switch to direct" else "direct touch  → switch to trackpad",
            "Stick keys: " + (if (stickKeys() == 0) "WASD" else "Arrows") + "  → switch",
            if (controls.editMode) "Finish editing layout" else "Edit layout",
            "Add button",
            "Reset layout",
            "Show / hide keyboard (for typing)",
            "Reload page",
            "Go to yag.im home",
            "Go to URL…",
        )
        AlertDialog.Builder(this).setItems(items) { _, i ->
            when (i) {
                0 -> setPlaying(!playing)
                1 -> { controls.padMode = !controls.padMode; prefs.edit().putBoolean("pad", controls.padMode).apply() }
                2 -> { val k = 1 - stickKeys(); controls.controls.filter { it.type == "stick" }.forEach { it.key = k }; controls.invalidate(); save() }
                3 -> { if (!playing) setPlaying(true); controls.editMode = !controls.editMode; if (!controls.editMode) save() }
                4 -> addButtonDialog()
                5 -> { controls.controls = Control.defaults(); controls.invalidate(); save() }
                6 -> toggleKeyboard()
                7 -> web.reload()
                8 -> web.loadUrl(HOME)
                9 -> urlDialog()
            }
        }.show()
    }

    private fun stickKeys() = controls.controls.firstOrNull { it.type == "stick" }?.key ?: 0

    private fun setPlaying(p: Boolean) {
        playing = p
        controls.visibility = if (p) View.VISIBLE else View.GONE
        if (!p) controls.editMode = false
        web.requestFocus()
    }

    private fun addButtonDialog() {
        val names = KEY_CHOICES.map { it.first }.toTypedArray()
        AlertDialog.Builder(this).setTitle("Add a button").setItems(names) { _, i ->
            controls.controls.add(Control("btn", 0.5f, 0.5f, KEY_CHOICES[i].second))
            if (!playing) setPlaying(true)
            controls.editMode = true
            controls.invalidate(); save()
        }.show()
    }

    override fun editTap(c: Control) {
        val opts = arrayOf("Bigger", "Smaller", "Remove", "Cancel")
        AlertDialog.Builder(this).setItems(opts) { _, i ->
            when (i) {
                0 -> c.size = (c.size * 1.2f).coerceAtMost(0.25f)
                1 -> c.size = (c.size / 1.2f).coerceAtLeast(0.03f)
                2 -> controls.controls.remove(c)
            }
            controls.invalidate(); save()
        }.show()
    }

    private fun urlDialog() {
        val et = EditText(this).apply { setText(web.url ?: HOME); setSingleLine() }
        AlertDialog.Builder(this).setTitle("Open URL").setView(et)
            .setPositiveButton("Go") { _, _ ->
                var u = et.text.toString().trim()
                if (!u.startsWith("http")) u = "https://$u"
                web.loadUrl(u)
            }.setNegativeButton("Cancel", null).show()
    }

    private fun toggleKeyboard() {
        web.requestFocus()
        (getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager)
            .toggleSoftInput(InputMethodManager.SHOW_FORCED, 0)
    }

    private fun save() = prefs.edit().putString("layout", controls.toJson()).apply()

    // ---- InputSink --------------------------------------------------------

    override fun key(code: Int, down: Boolean) {
        val t = SystemClock.uptimeMillis()
        web.dispatchKeyEvent(KeyEvent(t, t, if (down) KeyEvent.ACTION_DOWN else KeyEvent.ACTION_UP, code, 0))
    }

    override fun mouseMove(dx: Float, dy: Float) = js("__yt.move(${dx / density},${dy / density})")
    override fun mouseTo(xPx: Float, yPx: Float) = js("__yt.to(${xPx / density},${yPx / density})")
    override fun mouseButton(button: Int, down: Boolean) = js("__yt.btn($button,$down)")

    private fun js(code: String) = web.evaluateJavascript("window.__yt&&$code", null)

    /** Virtual mouse: keeps a cursor position and dispatches pointer/mouse events at it. */
    private fun injectHelper() {
        web.evaluateJavascript("""
(function(){ if(window.__yt) return;
 var x=200,y=200,mask=0,
 dot=document.createElement('div');
 dot.style.cssText='position:fixed;width:10px;height:10px;margin:-5px 0 0 -5px;border-radius:50%;background:rgba(255,80,80,.8);pointer-events:none;z-index:2147483647;display:none';
 document.documentElement.appendChild(dot);
 function tgt(){return document.pointerLockElement||document.elementFromPoint(x,y)||document.body}
 function fire(type,b,mx,my){var t=tgt();
  var o={bubbles:true,cancelable:true,composed:true,view:window,clientX:x,clientY:y,screenX:x,screenY:y,
   button:b,buttons:mask,movementX:mx||0,movementY:my||0};
  var p=type.replace('mouse','pointer');
  try{t.dispatchEvent(new PointerEvent(p,Object.assign({pointerId:1,pointerType:'mouse',isPrimary:true},o)))}catch(e){}
  t.dispatchEvent(new MouseEvent(type,o)); return t}
 function show(){dot.style.left=x+'px';dot.style.top=y+'px';dot.style.display='block'}
 window.__yt={
  move:function(dx,dy){x=Math.max(0,Math.min(innerWidth-1,x+dx));y=Math.max(0,Math.min(innerHeight-1,y+dy));show();fire('mousemove',0,dx,dy)},
  to:function(nx,ny){var dx=nx-x,dy=ny-y;x=nx;y=ny;dot.style.display='none';fire('mousemove',0,dx,dy)},
  btn:function(b,d){var bit=b==2?2:1;
   if(d){mask|=bit;fire('mousedown',b)}else{mask&=~bit;var t=fire('mouseup',b);
    if(b==2)fire('contextmenu',2);else{fire('click',0);if(t&&t.focus)try{t.focus()}catch(e){}}}}
 };
})();""", null)
    }
}
