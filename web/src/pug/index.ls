S = window.sfx

# ---------------------------------------------------------------- 參數規格
# range: 滑桿 ( def 要與 src 的預設一致, 滑桿才會停在正確位置 ); note: 音名或 Hz; json: 陣列等
R = (k, min, max, step, def) -> {k, type: \range, min, max, step, def}

# 群組與說明、範例; 參數的定義 ( 範圍、預設、選項 ) 來自 sfx.params
groups =
  * name: "UI 短音"
    sounds:
      * name: "click", desc: "點擊"
      * name: "tick", desc: "刻度、計數", presets: {"A5":{"note":"A5"},"C7":{"note":"C7"},"低":{"note":"E4"}}
      * name: "pop", desc: "元素出現", presets: {"低":{"from":200,"to":420},"下墜":{"from":900,"to":260},"高":{"from":700,"to":1800}}
      * name: "toggle", desc: "開關"
      * name: "type", desc: "打字 ( 每次換 seed 較自然 )"
      * name: "thump", desc: "落地、蓋章"
      * name: "snap", desc: "吸附、到位"
  * name: "提示"
    sounds:
      * name: "chime", desc: "鈴聲、完成一步", presets: {"E5":{"note":"E5"},"長":{"note":"B5","dur":3},"短":{"note":"G6","dur":0.5},"殘響":{"reverb":0.4}}
      * name: "success", desc: "成功 ( C-E-G 琶音 )"
      * name: "notify", desc: "通知"
      * name: "error", desc: "錯誤 ( 預設三全音往下 )", presets: {"小二度":{"from":"E4","to":"D#4"},"低":{"from":"E3","to":"A#2"}}
      * name: "correct", desc: "答對 ( 叮咚 )", presets: {"琶音":{"style":"arp"},"高":{"notes":["E6","C6"]},"快":{"gap":0.12}}
      * name: "wrong", desc: "答錯 ( 噗噗 )", presets: {"長號":{"style":"trombone"},"低沉":{"pitch":90}}
      * name: "reveal", desc: "揭曉 ( 鐘琴琶音 + 閃光 )", presets: {"慢":{"gap":0.12},"小調":{"notes":["A5","C6","E6","A6","C7"]},"乾":{"reverb":0}}
  * name: "動作"
    sounds:
      * name: "whoosh", desc: "轉場", presets: {"短":{"dur":0.35},"更短更乾淨":{"dur":0.25,"q":2},"往上衝":{"dur":0.6,"from":300,"peak":3500,"to":3000,"at":0.8},"往下沉":{"dur":0.6,"from":3000,"peak":3000,"to":300,"at":0.1},"像風":{"dur":1,"q":0.5},"像哨音":{"dur":0.6,"q":3}}
      * name: "swell", desc: "段落前的醞釀"
      * name: "slide", desc: "滑入、滑出", presets: {"往左":{"dir":-1},"滑出":{"from":2600,"to":700},"短":{"dur":0.18}}
      * name: "rise", desc: "數值上升", presets: {"長":{"dur":1.5},"八度":{"from":"C4","to":"C5"}}
      * name: "fall", desc: "數值下降"
      * name: "count", desc: "數字滾動", presets: {"多":{"n":30,"dur":2},"平":{"ease":"linear","climb":0},"加速":{"ease":"in"}}
      * name: "draw", desc: "筆畫", presets: {"鉛筆":{"pitch":4500,"rough":0.8},"馬克筆":{"pitch":1500,"rough":0.2}}
      * name: "glitch", desc: "故障"
      * name: "sweep", desc: "通用掃頻", presets: {"雷射":{"wave":"square","from":3000,"to":200,"dur":0.25},"升空":{"wave":"noise","from":200,"to":6000,"dur":2,"q":4},"警笛":{"wave":"saw","from":600,"to":900,"dur":0.6}}
  * name: "敘事"
    sounds:
      * name: "tension", desc: "緊張 ( 不和諧音簇 )"
      * name: "heartbeat", desc: "心跳", presets: {"緊張":{"bpm":130}}
      * name: "clock", desc: "時鐘"
  * name: "人聲與人體"
    sounds:
      * name: "fingersnap", desc: "打響指", presets: {"低":{"tone":2500},"高":{"tone":4000}}
      * name: "huh", desc: "蛤? ( 疑問 )", presets: {"男聲":{"pitch":115,"size":0.9},"小孩":{"pitch":300,"size":1.2},"很驚訝":{"rise":2.4,"dur":0.6}}
      * name: "yay", desc: "耶! ( 開心 )", presets: {"男聲":{"pitch":170,"size":0.9},"小孩":{"pitch":380,"size":1.2},"拉長":{"dur":0.9}}
  * name: "擬音與環境"
    sounds:
      * name: "paper", desc: "翻頁", presets: {"軟紙":{"crisp":0.3},"硬紙":{"crisp":2.5},"快翻":{"dur":0.6},"慢翻":{"dur":2,"flutter":0.9}}
      * name: "water", desc: "水滴、氣泡、溪流", presets: {"大水滴":{"size":6},"小水滴":{"size":1.8},"冒泡":{"n":40,"size":3,"rise":0.1,"dur":1.6},"溪流":{"n":250,"size":2.5,"rise":0.1,"dur":6}}
      * name: "fire", desc: "火"
      * name: "steps", desc: "腳步", presets: {"水泥":{"surface":"concrete"},"水泥跑步":{"surface":"concrete","gait":"run","n":8},"碎石":{"surface":"gravel"},"雪地":{"surface":"snow"},"草地":{"surface":"grass"},"跑":{"gait":"run","n":8}}
      * name: "bell", desc: "鐘 ( 教堂鐘、管鐘 )", presets: {"大鐘":{"note":"C3","dur":8},"管鐘":{"note":"G5","dur":3}}
      * name: "thunder", desc: "雷", presets: {"近":{"dist":0},"遠":{"dist":1}}
      * name: "wind", desc: "風", presets: {"低沉":{"cutoff":400},"尖":{"cutoff":2400}}
      * name: "rain", desc: "雨", presets: {"毛毛雨":{"density":0.006},"大雨":{"density":0.08}}
      * name: "buzz", desc: "昆蟲振翅", presets: {"高":{"freq":330},"大隻":{"freq":120,"dur":2.5}}
  * name: "樂器"
    sounds:
      * name: "pluck", desc: "撥弦 ( 類古箏 )", presets: {"亮":{"note":"D4","bright":0.9},"悶":{"note":"A2","bright":0.1},"不滑音":{"slide":0}}
      * name: "guitar", desc: "吉他 ( 單音或刷和弦 )", presets: {"Em":{"chord":"Em"},"G":{"chord":"G"},"上刷":{"chord":"Am","dir":"up","strum":0.015},"悶音":{"note":"E2","mute":0.8},"泛音感":{"note":"E4","pos":0.5,"bright":0.9}}
      * name: "marimba", desc: "馬林巴 ( 木琴 )", presets: {"低":{"note":"C3"},"硬槌":{"hard":1},"軟槌":{"hard":0}}
      * name: "xylophone", desc: "木琴"
      * name: "vibraphone", desc: "鐵琴 ( 顫音琴 )", presets: {"無顫音":{"trem":0},"殘響":{"reverb":0.4}}
      * name: "glockenspiel", desc: "鐘琴"
      * name: "score", desc: "照樂譜演奏 ( 任何聲音 )", presets: {"馬林巴": {"instrument": "marimba"}, "用 pop 演奏": {"instrument": "pop"}, "和弦": {"score": "C4+E4+G4/2 F4+A4+C5 | G4+B4+D5/1", "instrument": "guitar"}, "生日快樂 ( 附點 )": {"score": "G4/8. G4/16 A4/4 G4 C5 | B4/2 G4/8. G4/16 A4/4 | G4 D5 C5/2 | G4/8. G4/16 G5/4 E5 C5"}}
      * name: "melody", desc: "旋律 ( 可換樂器 )", presets: {"五聲":{"notes":[[0,"D4"],[0.25,"E4"],[0.5,"G4"],[0.75,"A4"],[1,"D5",2]]},"和弦":{"notes":[[0,"C3",2.5],[0.03,"G3",2.5],[0.06,"E4",2.5]],"slide":0},"馬林巴":{"instrument":"marimba","notes":[[0,"C4"],[0.2,"E4"],[0.4,"G4"],[0.6,"C5"],[0.8,"G4"],[1,"C5",1.5]]},"鐵琴":{"instrument":"vibraphone","notes":[[0,"F4",2],[0.5,"A4",2],[1,"C5",2],[1.5,"E5",3]],"reverb":0.3}}
      * name: "drone", desc: "持續低音", presets: {"小調":{"notes":["A1","E2","C3"]},"高":{"notes":["D3","A3","D4"],"dur":4}}
  * name: "鼓組"
    sounds:
      * name: "kick", desc: "大鼓", presets: {"808":{"tune":42,"decay":0.8,"punch":0.2},"緊":{"decay":0.15,"punch":1}}
      * name: "snare", desc: "小鼓"
      * name: "hihat", desc: "hi-hat", presets: {"開":{"open":0.7}}
      * name: "tom", desc: "中鼓 / 落地鼓", presets: {"高":{"note":"D3"},"落地":{"note":"E2","decay":0.6}}
      * name: "clap", desc: "拍手"
      * name: "crash", desc: "碎音鈸", presets: {"短":{"decay":0.5},"大":{"decay":1.8,"tune":0.8},"小":{"decay":0.6,"tune":1.4}}
      * name: "ride", desc: "疊音鈸", presets: {"鈸心":{"bell":1},"短":{"decay":0.5}}
      * name: "beat", desc: "節奏 ( 十六分音符一格 )", presets: {"搖滾":{"pattern":{"kick":"x.......x.x.....","snare":"....x.......x...","hihat":"x.x.x.x.x.x.x.x."},"bars":2},"四拍大鼓":{"pattern":{"kick":"x...x...x...x...","clap":"....x.......x...","ohat":"..x...x...x...x."},"bpm":120,"bars":2},"HipHop":{"pattern":{"kick":"x......x..x.....","snare":"....x.......x..o","hihat":"x.x.x.x.x.x.x.x."},"bpm":88,"swing":0.5,"bars":2},"過門":{"pattern":{"kick":"x...............","htom":"x.x.x...........","tom":"......x.x.......","ltom":"..........x.x...","crash":"................|x"},"bpm":110}}

sounds = []
for g in groups
  for s in g.sounds
    s <<< val: {}
    s.params = S.params[s.name].map((p) -> {} <<< p) ++ [R(\vary, 0, 1, 0.05, 0)]
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
  if p.type == \text => return (try (S.score.parse(txt); txt) catch => undefined)
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
last-variant = ''   # 最近一次 🎲 的程式碼
# 播放全部音效清單的變化 ( 不畫波形, 卡片保持原樣 )
audition-variant = (s) ->
  val = S.mutate s.name, {}, {amount: 0.5}
  if s.name == \melody => val.notes = [[0, \A3], [0.4, \C4], [0.8, \E4], [1.2, \A4, 2]]
  try buf = S.synth[s.name] val catch => return
  S.resume!
  if cur => cur.h.stop 0.05; (if !cur.variant => draw-wave cur.s)
  h = S.play buf, {gain: 0.9}
  cur := {s, h, at: S.ctx!currentTime, dur: buf.duration, variant: true}
  last-variant := "sfx.synth.#{s.name}(#{fmt val})"
  view.render <[qgroup lastvar]>
audition = (s) ->
  if !s.buf and !s.err => gen s; view.render!
  if !s.buf => return
  S.resume!
  if cur => cur.h.stop 0.05; (if !cur.variant => draw-wave cur.s)
  h = S.play s.buf, {gain: 0.9}
  cur := {s, h, at: S.ctx!currentTime, dur: s.buf.duration}
  view.render \qgroup

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
    "tune": ["melody", {"instrument": "marimba", "notes": [[0, "D4"], [0.3, "F4"], [0.6, "A4"], [0.9, "D5", 2]]}],
    "count": ["count", {"n": 10, "dur": 0.8}],
    "ta": ["reveal", {}]
  },
  "timeline": [
    {"t": 0, "sound": "bed", "bus": "music", "gain": 0.35, "fadeIn": 1, "fadeOut": 2},
    {"t": 0.8, "sound": "sw", "gain": 0.7},
    {"t": 1.5, "sound": "pop", "vary": 0.6},
    {"t": 1.9, "sound": "pop", "vary": 0.6},
    {"t": 2.3, "sound": "hi"},
    {"t": 3.4, "sound": "stamp"},
    {"t": 4.4, "sound": "tune", "bus": "music", "gain": 0.7},
    {"t": 5.6, "sound": "count", "gain": 0.6, "align": "start"},
    {"t": 6.6, "sound": "ta", "gain": 0.8}
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
    for it in sc.timeline
      for name in [].concat(it.sound) when !bufs[name] and !S.buffers[name]
        throw new Error("timeline 用到未定義的聲音: #{name}")
  catch e
    tl.err = e.message or "#e"
    return view.render \err
  tl.err = ''
  S.load(bufs).then ->
    tl.duration = +sc.duration or Math.max(...sc.timeline.map((it) -> it.t + 1))
    S.timeline sc.timeline
    tl.lanes = lanes S.items, tl.duration
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
    lastvar: -> last-variant
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
    qgroup:
      list: -> groups
      key: (.name)
      view:
        text: name: ({ctx}) -> ctx.name
        handler: quick:
          list: ({ctx}) -> if ctx => ctx.sounds else []
          key: (.name)
          view:
            text:
              qname: ({ctx}) -> ctx.name
              qdesc: ({ctx}) -> ctx.desc
            handler:
              chip: ({node, ctx}) -> node.classList.toggle \on, !!(cur and cur.s == ctx and !cur.variant)
              qdice: ({node, ctx}) -> node.classList.toggle \on, !!(cur and cur.s == ctx and cur.variant)
            action: click:
              chip: ({ctx}) -> audition ctx
              qdice: ({ctx}) -> audition-variant ctx
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
              len: ({ctx}) -> if ctx.err => '錯誤' else if ctx.buf => "#{ctx.buf.duration.toFixed(2)}s" else '…'
              code: ({ctx}) -> code ctx
            attr: len: ({ctx}) -> title: ctx.err or ''
            handler:
              wave: ({ctx}) -> draw-wave ctx
              reset: ({node, ctx}) -> node.classList.toggle \on, !Object.keys(ctx.val).length
              param:
                list: ({ctx}) -> if ctx => ctx.items else []
                key: (.p.k)
                view:
                  init:
                    input: ({node, ctx: {p}}) ->
                      if p.type == \select => node.remove!
                      else if p.type == \range
                        node <<< type: \range, min: p.min, max: p.max, step: p.step
                      else
                        node.type = \text
                        node.placeholder = p.hint or ''
                    select: ({node, ctx: {p}}) ->
                      if p.type != \select => return node.remove!
                      for v in p.options
                        opt = document.createElement \option
                        opt.value = v
                        opt.textContent = if v == '' => '( 無 )' else v
                        node.appendChild opt
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
                    select: ({node, ctx: {p, s}}) -> if p.type == \select => node.value = value(s, p) or ''
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
                    change:
                      input: ({ctx: {s}}) -> audition s
                      select: ({node, ctx: {p, s}}) ->
                        if node.value == p.def or node.value == '' => delete s.val[p.k] else s.val[p.k] = node.value
                        gen s
                        view.render!
                        audition s
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
              dice: ({ctx}) ->
                ctx.val = S.mutate ctx.name, ctx.val, {amount: 0.5}
                gen ctx
                view.render!
                audition ctx
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

view.render!
document.body.classList.add \ready
# 分批在背景產生聲音 ( 每次最多 40ms ), 不卡住第一次畫面
pending = sounds.slice!
gen-some = ->
  t0 = performance.now!
  while pending.length and performance.now! - t0 < 40
    s = pending.shift!
    if !s.buf and !s.err => gen s
  view.render!
  if pending.length => setTimeout gen-some, 0
setTimeout gen-some, 0
apply-scene scene-src

# ---------------------------------------------------------------- 每一幀
frame = ->
  if cur
    p = (S.ctx!currentTime - cur.at) / cur.dur
    if p >= 1
      if !cur.variant => draw-wave cur.s
      cur := null
      view.render \qgroup
    else if !cur.variant => draw-wave cur.s, p
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
