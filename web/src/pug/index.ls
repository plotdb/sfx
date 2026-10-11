S = window.sfx

# ---------------------------------------------------------------- 參數規格
# range: 滑桿 ( def 要與 src 的預設一致, 滑桿才會停在正確位置 ); note: 音名或 Hz; json: 陣列等
R = (k, min, max, step, def) -> {k, type: \range, min, max, step, def}
N = (k, def, hint) -> {k, type: \note, def, hint}
J = (k, def) -> {k, type: \json, def}
seed = (def) -> R \seed, 1, 99, 1, def
pan = R \pan, -1, 1, 0.05, 0

groups =
  * name: 'UI 短音'
    sounds:
      * name: \click, desc: \點擊, params: [R(\freq, 500, 5000, 10, 2000), seed(7), pan]
      * name: \tick, desc: '刻度、計數', params: [N(\note, null, '1800 Hz'), pan]
        presets: {A5: {note: \A5}, C7: {note: \C7}, 低: {note: \E4}}
      * name: \pop, desc: '元素出現', params: [R(\from, 100, 2000, 10, 380), R(\to, 100, 3000, 10, 900), pan]
        presets: {低: {from: 200, to: 420}, 下墜: {from: 900, to: 260}, 高: {from: 700, to: 1800}}
      * name: \toggle, desc: \開關, params: [pan]
      * name: \type, desc: '打字 ( 每次換 seed 較自然 )', params: [seed(11)]
      * name: \thump, desc: '落地、蓋章', params: [seed(5), pan]
  * name: \提示
    sounds:
      * name: \chime, desc: '鈴聲、完成一步', params: [N(\note, \E6), R(\dur, 0.3, 4, 0.1, 1.4), pan]
        presets: {E5: {note: \E5}, 長: {note: \B5, dur: 3}, 短: {note: \G6, dur: 0.5}}
      * name: \success, desc: '成功 ( C-E-G 琶音 )', params: [pan]
      * name: \notify, desc: \通知, params: [pan]
  * name: \轉場
    sounds:
      * name: \whoosh, desc: \轉場
        params: [
          R(\dur, 0.1, 2, 0.05, 0.7), R(\from, 50, 5000, 10, 400), R(\peak, 50, 6000, 10, 2600)
          R(\to, 50, 5000, 10, 600), R(\at, 0.05, 0.95, 0.01, 0.45), R(\q, 0.3, 6, 0.1, 1.2), seed(3)
        ]
        presets:
          短: {dur: 0.35}
          更短更乾淨: {dur: 0.25, q: 2}
          往上衝: {dur: 0.6, from: 300, peak: 3500, to: 3000, at: 0.8}
          往下沉: {dur: 0.6, from: 3000, peak: 3000, to: 300, at: 0.1}
          像風: {dur: 1, q: 0.5}
          像哨音: {dur: 0.6, q: 3}
      * name: \swell, desc: '段落前的醞釀', params: [R(\dur, 0.5, 6, 0.1, 2), seed(23)]
  * name: \樂音
    sounds:
      * name: \pluck, desc: '撥弦 ( 類古箏 )'
        params: [N(\note, \A3), R(\dur, 0.3, 5, 0.1, 2.5), R(\bright, 0, 1, 0.05, 0.6), R(\slide, 0, 3, 0.1, 0.6), seed(13), pan]
        presets: {亮: {note: \D4, bright: 0.9}, 悶: {note: \A2, bright: 0.1}, 不滑音: {slide: 0}}
      * name: \melody, desc: '撥弦旋律'
        params: [J(\notes, [[0, \A3], [0.4, \C4], [0.8, \E4], [1.2, \A4, 2]]), R(\bright, 0, 1, 0.05, 0.6), R(\slide, 0, 3, 0.1, 0.6)]
        presets:
          五聲: {notes: [[0, \D4], [0.25, \E4], [0.5, \G4], [0.75, \A4], [1, \D5, 2]]}
          和弦: {notes: [[0, \C3, 2.5], [0.03, \G3, 2.5], [0.06, \E4, 2.5]], slide: 0}
      * name: \drone, desc: '持續低音'
        params: [J(\notes, <[A1 E2 A2]>), R(\dur, 1, 12, 0.5, 8), R(\attack, 0.1, 4, 0.1, 1.5), R(\release, 0.1, 4, 0.1, 2)]
        presets: {小調: {notes: <[A1 E2 C3]>}, 高: {notes: <[D3 A3 D4]>, dur: 4}}
  * name: \環境
    sounds:
      * name: \wind, desc: \風, params: [R(\dur, 1, 10, 0.5, 6), R(\cutoff, 200, 3000, 10, 900), seed(17)]
        presets: {低沉: {cutoff: 400}, 尖: {cutoff: 2400}}
      * name: \rain, desc: \雨, params: [R(\dur, 1, 10, 0.5, 6), R(\density, 0.002, 0.2, 0.002, 0.02), seed(19)]
        presets: {毛毛雨: {density: 0.006}, 大雨: {density: 0.08}}
      * name: \buzz, desc: \昆蟲振翅, params: [R(\dur, 0.2, 4, 0.1, 1.5), R(\freq, 80, 600, 1, 220), pan]
        presets: {高: {freq: 330}, 大隻: {freq: 120, dur: 2.5}}

sounds = []
for g in groups
  for s in g.sounds
    s <<< val: {}
    s.items = s.params.map (p) -> {p, s}
    s.chips = Object.keys(s.presets or {}).map (label) -> {label, val: s.presets[label], s}
    sounds.push s

value = (s, p) -> if s.val[p.k]? => s.val[p.k] else p.def

# 參數物件 -> 程式碼裡的寫法
fmt = (o) ->
  if !Object.keys(o).length => return ''
  JSON.stringify(o).replace(/"(\w+)":/g, '$1: ').replace(/"/g, "'").replace(/,/g, ', ')
code = (s) -> "sfx.synth.#{s.name}(#{fmt s.val})"
same = (a, b) -> JSON.stringify(a) == JSON.stringify(b)
# 文字欄位 -> 值; null 表示清空 ( 用預設 ), undefined 表示不合法
parse = (p, txt) ->
  if !txt => return null
  if p.type == \json => return (try JSON.parse txt catch => undefined)
  if /^\d+(\.\d+)?$/.test(txt) => return +txt
  if /^[A-G](#|b)?-?\d$/.test(txt) => return txt
  undefined

gen = (s) ->
  try
    s.buf = S.synth[s.name] JSON.parse(JSON.stringify s.val)
    s.err = null
  catch e
    s.buf = null
    s.err = e.message or "#e"
  s.img = null

# ---------------------------------------------------------------- 波形
css = (k) -> getComputedStyle(document.documentElement).getPropertyValue(k).trim!

# canvas 依顯示大小調整解析度; 回傳是否變更過
fit = (node, h) ->
  dpr = window.devicePixelRatio or 1
  w = Math.round(node.clientWidth * dpr)
  h = Math.round((h or node.clientHeight) * dpr)
  if node.width == w and node.height == h => return false
  node.width = w
  node.height = h
  true

wave-image = (buf, w, h) ->
  c = document.createElement \canvas
  c.width = w; c.height = h
  g = c.getContext \2d
  g.fillStyle = css \--wave
  L = buf.getChannelData 0
  Rc = buf.getChannelData 1
  step = L.length / w
  mid = h / 2
  for x from 0 til w
    lo = 0; hi = 0
    for i from Math.floor(x * step) til Math.min(L.length, Math.floor((x + 1) * step))
      v = (L[i] + Rc[i]) / 2
      if v < lo => lo = v
      if v > hi => hi = v
    g.fillRect x, mid - hi * mid * 0.92, 1, Math.max(1, (hi - lo) * mid * 0.92)
  c

# progress: 0~1, 已播放的部分上色
draw-wave = (s, progress) ->
  node = s.canvas
  if !node or !node.clientWidth => return
  if fit(node) => s.img = null
  g = node.getContext \2d
  g.clearRect 0, 0, node.width, node.height
  if !s.buf => return
  if !s.img => s.img = wave-image s.buf, node.width, node.height
  g.drawImage s.img, 0, 0
  if progress? and progress > 0
    g.save!
    g.globalCompositeOperation = \source-atop
    g.fillStyle = css \--wave-hot
    g.fillRect 0, 0, node.width * Math.min(1, progress), node.height
    g.restore!

# ---------------------------------------------------------------- 試聽
cur = null   # 正在播放的卡片 {s, h, at, dur}
audition = (s) ->
  if !s.buf => return
  S.resume!
  if cur => cur.h.stop 0.05; draw-wave cur.s
  h = S.play s.buf, {gain: 0.9}
  cur := {s, h, at: S.ctx!currentTime, dur: s.buf.duration}

# ---------------------------------------------------------------- 時間軸
scene-src = '''
{
  "duration": 8,
  "sounds": {
    "bed": ["drone", {"notes": ["D2", "A2", "D3"], "dur": 8}],
    "sw": ["whoosh", {"dur": 0.6}],
    "pop": ["pop", {}],
    "hi": ["pop", {"from": 600, "to": 1500}],
    "stamp": ["thump", {}],
    "tune": ["melody", {"notes": [[0, "D4"], [0.3, "F4"], [0.6, "A4"], [0.9, "D5", 2]]}],
    "ok": ["success", {}]
  },
  "timeline": [
    {"t": 0, "sound": "bed", "bus": "music", "gain": 0.35, "fadeIn": 1, "fadeOut": 2},
    {"t": 0.8, "sound": "sw", "gain": 0.7},
    {"t": 1.5, "sound": "pop"},
    {"t": 1.9, "sound": "pop"},
    {"t": 2.3, "sound": "hi"},
    {"t": 3.4, "sound": "stamp"},
    {"t": 4.4, "sound": "tune", "bus": "music", "gain": 0.7},
    {"t": 6.6, "sound": "ok", "gain": 0.8}
  ]
}
'''

tl = {t: 0, playing: false, rate: 1, duration: 8, lanes: [], err: '', wav: null, rendering: false}

# 每一項在動畫時間上的範圍 ( 與 sfx 排程相同的算法 )
lanes = (items, dur) -> items.map (it, i) ->
  buf = S.buffers[it.sound]
  if !buf => return {it, i, start: it.t, len: 0, missing: true}
  b = it.bus or \sfx
  lead = if (it.align or (if b == \sfx => \peak else \start)) == \peak => S.peak(buf) else 0
  start = it.t - lead
  len = if it.loop => ((if it.until? => it.until else dur) - start) else (it.duration or buf.duration / (it.rate or 1))
  {it, i, start, len, bus: b}

apply-scene = (text) ->
  try
    sc = JSON.parse text
    if !(sc.timeline and Array.isArray(sc.timeline)) => throw new Error('缺少 timeline 陣列')
    if !(sc.sounds and typeof(sc.sounds) == \object) => throw new Error('缺少 sounds 物件')
    bufs = {}
    for name, def of sc.sounds
      [kind, opt] = if Array.isArray(def) => def else [def]
      if !S.synth[kind] => throw new Error("#name: 沒有 #kind 這種合成聲")
      bufs[name] = S.synth[kind](opt or {})
    for it in sc.timeline when !bufs[it.sound] and !S.buffers[it.sound]
      throw new Error("timeline 用到未定義的聲音: #{it.sound}")
  catch e
    tl.err = e.message or "#e"
    return view.render \err
  tl.err = ''
  S.load(bufs).then ->
    tl.duration = +sc.duration or Math.max(...sc.timeline.map((it) -> it.t + 1))
    S.timeline sc.timeline
    tl.lanes = lanes sc.timeline, tl.duration
    tl.t = Math.min tl.t, tl.duration
    view.render <[err hit time]>
    draw-track!

# 以 AudioContext 的時間當時鐘: 與 sfx 的排程同一個時間基準 ( context 被暫停時也一起停 )
clock-now = ->
  if !tl.playing => return tl.t
  tl.t0 + Math.max(0, S.ctx!currentTime - tl.c0) * tl.rate

transport = (playing) ->
  S.transport {playing, t: tl.t, rate: tl.rate, from: \demo, force: true}
  tl.t0 = tl.t
  # sfx 以 currentTime + 0.02 對應 t ( 見 start-timeline )
  tl.c0 = S.ctx!currentTime + 0.02

play = ->
  if tl.t >= tl.duration - 0.01 => tl.t = 0
  S.resume!
  tl.playing = true
  transport true
  view.render <[toggle]>
pause = ->
  tl.t = clock-now!
  tl.playing = false
  transport false
  view.render <[toggle time]>
seek = (t) ->
  tl.t = Math.max 0, Math.min(tl.duration, t)
  if tl.playing => transport true

draw-track = ->
  node = view.get \track
  lane-h = 14
  top = 22
  h = top + Math.max(1, tl.lanes.length) * lane-h + 6
  node.style.height = "#{h}px"
  fit node, h
  dpr = window.devicePixelRatio or 1
  g = node.getContext \2d
  g.setTransform dpr, 0, 0, dpr, 0, 0
  W = node.width / dpr
  g.clearRect 0, 0, W, h
  x = (t) -> t / tl.duration * W
  [line, muted, hot, fg, wave] = <[--line --muted --wave-hot --fg --wave]>.map css
  # 刻度
  g.font = '10px ui-monospace, Menlo, monospace'
  g.textBaseline = \top
  for s from 0 to Math.floor(tl.duration)
    g.fillStyle = line
    g.fillRect Math.round(x s), 0, 1, h
    g.fillStyle = muted
    g.fillText "#{s}s", x(s) + 3, 2
  # 每一項: 檔案範圍 ( 方塊 ) 與擊點 ( t )
  for l, i in tl.lanes
    y = top + i * lane-h
    g.globalAlpha = if l.bus == \music => 0.35 else 0.6
    g.fillStyle = wave
    g.fillRect x(Math.max 0, l.start), y + 3, Math.max(2, x(Math.min(tl.duration, l.start + l.len)) - x(Math.max 0, l.start)), lane-h - 6
    g.globalAlpha = 1
    g.fillStyle = hot
    g.fillRect x(l.it.t) - 1, y + 1, 2, lane-h - 2
  # 播放頭
  g.fillStyle = fg
  g.fillRect Math.round(x clock-now!) - 1, 0, 2, h

# 舞台: 每一項一個點, 在擊點時跳一下; music 在播放範圍內亮著
draw-stage = ->
  t = clock-now!
  for l in tl.lanes when l.dot
    k = if l.bus == \music =>
      if t >= l.start and t <= l.start + l.len => 0.55 + 0.15 * Math.sin((t - l.start) * 6) else 0
    else if t >= l.it.t => Math.exp(-(t - l.it.t) * 5) else 0
    l.dot.style.transform = "scale(#{1 + 0.8 * k})"
    l.dot.style.opacity = 0.35 + 0.65 * Math.min(1, k * 1.5)
    l.dot.style.background = if k > 0.05 => 'var(--wave-hot)' else ''

render-wav = ->
  if tl.rendering => return
  tl.rendering = true
  view.render \render
  S.render(tl.duration).then (buf) ->
    if tl.wav => URL.revokeObjectURL tl.wav
    tl.wav = URL.createObjectURL S.wav(buf)
  .catch (e) -> tl.err = "混音失敗: #{e.message or e}"
  .finally ->
    tl.rendering = false
    view.render <[render out download err]>

# ---------------------------------------------------------------- 畫面
buses = <[master music sfx voice]>.map (name) -> {name, v: 1}
pct = (v) -> "#{Math.round v * 100}%"

view = new ldview do
  root: document.body
  init:
    src: ({node}) -> node.value = scene-src
    track: ({node}) ->
      drag = null
      at = (e) -> (e.clientX - node.getBoundingClientRect!left) / node.clientWidth * tl.duration
      # 拖曳中先暫停, 放開後再從新位置播 ( 避免拖曳時不斷重新排程 )
      node.addEventListener \pointerdown, (e) ->
        node.setPointerCapture e.pointerId
        drag := {was: tl.playing}
        if tl.playing => pause!
        seek at(e)
      node.addEventListener \pointermove, (e) -> if drag => seek at(e)
      node.addEventListener \pointerup, (e) ->
        if !drag => return
        was = drag.was
        drag := null
        if was => play!
  text:
    toggle: -> if tl.playing => '❚❚ 暫停' else '▶ 播放'
    time: -> "#{clock-now!.toFixed(2)} / #{tl.duration.toFixed(2)} s"
    err: -> tl.err
    render: -> if tl.rendering => '混音中…' else '混成 wav'
  attr:
    download: -> href: tl.wav or '#'
  handler:
    out: ({node}) ->
      node.classList.toggle \on, !!tl.wav
      if tl.wav and node.src != tl.wav => node.src = tl.wav; node.load!
    download: ({node}) -> node.classList.toggle \on, !!tl.wav
    bus:
      list: -> buses
      key: (.name)
      view:
        text:
          name: ({ctx}) -> ctx.name
          val: ({ctx}) -> pct ctx.v
        handler: input: ({node, ctx}) -> node.value = ctx.v
        action: input: input: ({node, ctx}) ->
          ctx.v = +node.value
          S.volume ctx.name, ctx.v, 0.05
          view.render \bus
    rate:
      list: -> [0.5, 1, 1.5, 2]
      view:
        text: chip: ({ctx}) -> "#{ctx}×"
        handler: chip: ({node, ctx}) -> node.classList.toggle \on, tl.rate == ctx
        action: click: chip: ({ctx}) ->
          tl.t = clock-now!
          tl.rate = ctx
          if tl.playing => transport true
          view.render \rate
    hit:
      list: -> tl.lanes
      view:
        init: dot: ({node, ctx}) -> ctx.dot = node
        handler: dot: ({node, ctx}) -> ctx.dot = node; node.classList.toggle \music, ctx.bus == \music
        text: label: ({ctx}) -> "#{ctx.it.sound} @#{ctx.it.t}"
    group:
      list: -> groups
      key: (.name)
      view:
        text: name: ({ctx}) -> ctx.name
        handler: sound:
          list: ({ctx}) -> if ctx => ctx.sounds else []
          key: (.name)
          view:
            init: wave: ({node, ctx}) -> ctx.canvas = node
            text:
              name: ({ctx}) -> ctx.name
              desc: ({ctx}) -> ctx.desc
              len: ({ctx}) -> if ctx.err => '錯誤' else if ctx.buf => "#{ctx.buf.duration.toFixed(2)}s" else ''
              code: ({ctx}) -> code ctx
            attr: len: ({ctx}) -> title: ctx.err or ''
            handler:
              wave: ({ctx}) -> draw-wave ctx
              reset: ({node, ctx}) -> node.classList.toggle \on, !Object.keys(ctx.val).length
              param:
                list: ({ctx}) -> if ctx => ctx.items else []
                key: (.p.k)
                view:
                  init: input: ({node, ctx: {p}}) ->
                    if p.type == \range
                      node <<< type: \range, min: p.min, max: p.max, step: p.step
                    else
                      node.type = \text
                      node.placeholder = p.hint or ''
                  text:
                    key: ({ctx: {p}}) -> p.k
                    val: ({ctx: {p, s}}) -> if p.type == \range => "#{value s, p}" else ''
                  handler:
                    val: ({node, ctx: {p}}) -> node.style.display = if p.type == \range => '' else \none
                    input: ({node, ctx: {p, s}}) ->
                      v = value s, p
                      if p.type == \range => node.value = v
                      # 打字中不要覆寫
                      else if node != document.activeElement
                        node.value = if !v? => '' else if p.type == \json => JSON.stringify(v) else "#v"
                        node.classList.remove \bad
                  action:
                    input: input: ({node, ctx: {p, s}}) ->
                      if p.type == \range
                        v = +node.value
                        if v == p.def => delete s.val[p.k] else s.val[p.k] = v
                      else
                        v = parse p, node.value.trim!
                        if v == undefined => return node.classList.add \bad
                        node.classList.remove \bad
                        if !v? or same(v, p.def) => delete s.val[p.k] else s.val[p.k] = v
                      gen s
                      view.render!
                    change: input: ({ctx: {s}}) -> audition s
              preset:
                list: ({ctx}) -> if ctx => ctx.chips else []
                key: (.label)
                view:
                  text: chip: ({ctx}) -> ctx.label
                  handler: chip: ({node, ctx}) -> node.classList.toggle \on, same(ctx.val, ctx.s.val)
                  action: click: chip: ({ctx}) ->
                    ctx.s.val = JSON.parse JSON.stringify(ctx.val)
                    gen ctx.s
                    view.render!
                    audition ctx.s
            action: click:
              play: ({ctx}) -> audition ctx
              wave: ({ctx}) -> audition ctx
              reset: ({ctx}) -> ctx.val = {}; gen ctx; view.render!; audition ctx
              copy: ({node, ctx}) ->
                navigator.clipboard.writeText(code ctx).then ->
                  node.textContent = '已複製'
                  setTimeout (-> node.textContent = '複製'), 1000
  action: click:
    toggle: -> if tl.playing => pause! else play!
    render: -> render-wav!
    apply: -> apply-scene view.get(\src).value

for s in sounds => gen s
view.render!
apply-scene scene-src

# ---------------------------------------------------------------- 每一幀
frame = ->
  if cur
    p = (S.ctx!currentTime - cur.at) / cur.dur
    if p >= 1 => draw-wave cur.s; cur := null
    else draw-wave cur.s, p
  if tl.playing
    if clock-now! >= tl.duration
      tl.t = tl.duration
      pause!
    view.render \time
  draw-stage!
  draw-track!
  requestAnimationFrame frame
requestAnimationFrame frame

redraw = -> for s in sounds => s.img = null; draw-wave s
window.addEventListener \resize, redraw
# 深淺色切換時重畫 ( 波形顏色是畫進圖裡的 )
window.matchMedia('(prefers-color-scheme: dark)').addEventListener \change, redraw
