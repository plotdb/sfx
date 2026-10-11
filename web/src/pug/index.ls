S = window.sfx

# ---------------------------------------------------------------- 參數規格
# range: 滑桿 ( def 要與 src 的預設一致, 滑桿才會停在正確位置 ); note: 音名或 Hz; json: 陣列等
R = (k, min, max, step, def) -> {k, type: \range, min, max, step, def}
N = (k, def, hint) -> {k, type: \note, def, hint}
J = (k, def) -> {k, type: \json, def}
O = (k, options, def) -> {k, type: \select, options, def}
seed = (def) -> R \seed, 1, 99, 1, def
pan = R \pan, -1, 1, 0.05, 0
# 殘響: 每種聲音都可以加
rv = (def = 0) -> [R(\reverb, 0, 1, 0.05, def), R(\room, 0, 1, 0.05, 0.5)]
INSTRUMENTS = <[pluck marimba xylophone vibraphone glockenspiel guitar chime bell]>
ROCK = {kick: 'x.......x.x.....', snare: '....x.......x...', hihat: 'x.x.x.x.x.x.x.x.'}

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
      * name: \snap, desc: '吸附、到位', params: [seed(41), pan]
  * name: \提示
    sounds:
      * name: \chime, desc: '鈴聲、完成一步', params: [N(\note, \E6), R(\dur, 0.3, 4, 0.1, 1.4), pan] ++ rv!
        presets: {E5: {note: \E5}, 長: {note: \B5, dur: 3}, 短: {note: \G6, dur: 0.5}, 殘響: {reverb: 0.4}}
      * name: \success, desc: '成功 ( C-E-G 琶音 )', params: [pan] ++ rv!
      * name: \notify, desc: \通知, params: [pan] ++ rv!
      * name: \error, desc: '錯誤 ( 預設三全音往下 )', params: [N(\from, \B3), N(\to, \F3), pan]
        presets: {小二度: {from: \E4, to: \D#4}, 低: {from: \E3, to: \A#2}}
      * name: \correct, desc: '答對 ( 叮咚 )', params: [O(\style, <[pingpong arp]>, \pingpong), J(\notes, null), R(\gap, 0.03, 0.4, 0.01, 0.2), pan] ++ rv(0.15)
        presets: {琶音: {style: \arp}, 高: {notes: <[E6 C6]>}, 快: {gap: 0.12}}
      * name: \wrong, desc: '答錯 ( 噗噗 )', params: [O(\style, <[buzzer trombone]>, \buzzer), R(\pitch, 60, 400, 1, 140), pan]
        presets: {長號: {style: \trombone}, 低沉: {pitch: 90}}
      * name: \reveal, desc: '揭曉 ( 鐘琴琶音 + 閃光 )'
        params: [J(\notes, <[C6 E6 G6 C7 E7]>), R(\gap, 0.02, 0.2, 0.01, 0.06), seed(53), pan] ++ rv(0.35)
        presets: {慢: {gap: 0.12}, 小調: {notes: <[A5 C6 E6 A6 C7]>}, 乾: {reverb: 0}}
  * name: \動作
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
      * name: \slide, desc: '滑入、滑出'
        params: [R(\dur, 0.1, 1, 0.05, 0.3), R(\from, 100, 6000, 10, 900), R(\to, 100, 6000, 10, 2600), R(\q, 0.3, 4, 0.1, 0.9), R(\dir, -1, 1, 0.1, 1), seed(37)]
        presets: {往左: {dir: -1}, 滑出: {from: 2600, to: 700}, 短: {dur: 0.18}}
      * name: \rise, desc: '數值上升', params: [N(\from, null, '300 Hz'), N(\to, null, '900 Hz'), R(\dur, 0.1, 3, 0.05, 0.6), pan]
        presets: {長: {dur: 1.5}, 八度: {from: \C4, to: \C5}}
      * name: \fall, desc: '數值下降', params: [N(\from, null, '900 Hz'), N(\to, null, '250 Hz'), R(\dur, 0.1, 3, 0.05, 0.6), pan]
      * name: \count, desc: '數字滾動'
        params: [R(\n, 2, 40, 1, 12), R(\dur, 0.2, 4, 0.1, 1.2), O(\ease, <[out in linear]>, \out), R(\climb, 0, 24, 1, 7), N(\note, \C6), pan]
        presets: {多: {n: 30, dur: 2}, 平: {ease: \linear, climb: 0}, 加速: {ease: \in}}
      * name: \draw, desc: '筆畫'
        params: [R(\dur, 0.2, 4, 0.1, 1), R(\rough, 0, 1, 0.05, 0.5), R(\pitch, 500, 8000, 50, 2500), seed(43), pan]
        presets: {鉛筆: {pitch: 4500, rough: 0.8}, 馬克筆: {pitch: 1500, rough: 0.2}}
      * name: \glitch, desc: \故障, params: [R(\dur, 0.1, 2, 0.05, 0.5), seed(47)]
      * name: \sweep, desc: '通用掃頻'
        params: [
          O(\wave, <[sine triangle square saw noise]>, \sine), O(\curve, <[exp lin]>, \exp)
          N(\from, null, '200 Hz'), N(\to, null, '2000 Hz'), R(\dur, 0.1, 4, 0.05, 1)
          R(\q, 0.3, 10, 0.1, 2), R(\attack, 0, 1, 0.01, 0.01), R(\release, 0, 2, 0.01, 0.1), pan
        ]
        presets: {雷射: {wave: \square, from: 3000, to: 200, dur: 0.25}, 升空: {wave: \noise, from: 200, to: 6000, dur: 2, q: 4}, 警笛: {wave: \saw, from: 600, to: 900, dur: 0.6}}
  * name: \敘事
    sounds:
      * name: \tension, desc: '緊張 ( 不和諧音簇 )', params: [N(\note, \A2), R(\dur, 1, 12, 0.5, 6)]
      * name: \heartbeat, desc: \心跳, params: [R(\bpm, 40, 180, 1, 70), R(\dur, 1, 10, 0.5, 4), pan]
        presets: {緊張: {bpm: 130}}
      * name: \clock, desc: '時鐘', params: [R(\bpm, 30, 240, 1, 60), R(\dur, 1, 10, 0.5, 4), seed(59), pan]
  * name: '人聲與人體'
    sounds:
      * name: \fingersnap, desc: \打響指, params: [R(\tone, 2000, 5000, 10, 3200), seed(137), pan]
        presets: {低: {tone: 2500}, 高: {tone: 4000}}
      * name: \huh, desc: '蛤? ( 疑問 )', params: [R(\pitch, 80, 400, 1, 200), R(\rise, 1, 3, 0.05, 1.9), R(\dur, 0.2, 1, 0.01, 0.45), R(\size, 0.8, 1.3, 0.01, 1), seed(151)]
        presets: {男聲: {pitch: 115, size: 0.9}, 小孩: {pitch: 300, size: 1.2}, 很驚訝: {rise: 2.4, dur: 0.6}}
      * name: \yay, desc: '耶! ( 開心 )', params: [R(\pitch, 100, 500, 1, 300), R(\dur, 0.2, 1.2, 0.01, 0.5), R(\size, 0.8, 1.3, 0.01, 1), seed(157)]
        presets: {男聲: {pitch: 170, size: 0.9}, 小孩: {pitch: 380, size: 1.2}, 拉長: {dur: 0.9}}
  * name: '擬音與環境'
    sounds:
      * name: \paper, desc: \翻頁, params: [R(\dur, 0.4, 2.5, 0.05, 1.2), R(\crisp, 0, 3, 0.1, 1), R(\flutter, 0, 1, 0.05, 0.6), seed(61)]
        presets: {軟紙: {crisp: 0.3}, 硬紙: {crisp: 2.5}, 快翻: {dur: 0.6}, 慢翻: {dur: 2, flutter: 0.9}}
      * name: \water, desc: '水滴、氣泡、溪流', params: [R(\n, 1, 300, 1, 1), R(\size, 0.5, 10, 0.1, 3), R(\rise, 0, 1, 0.05, 0.05), R(\dur, 0.2, 10, 0.1, 0.4), seed(67)]
        presets: {大水滴: {size: 6}, 小水滴: {size: 1.8}, 冒泡: {n: 40, size: 3, rise: 0.1, dur: 1.6}, 溪流: {n: 250, size: 2.5, rise: 0.1, dur: 6}}
      * name: \fire, desc: \火, params: [R(\dur, 1, 10, 0.5, 6), R(\density, 0, 4, 0.1, 1), seed(71)]
      * name: \steps, desc: \腳步, params: [O(\surface, <[wood concrete gravel snow grass]>, \wood), O(\gait, <[walk run]>, \walk), R(\n, 1, 12, 1, 4), R(\pace, 0.2, 1.2, 0.05, 0.5), seed(73)]
        presets: {水泥: {surface: \concrete}, 水泥跑步: {surface: \concrete, gait: \run, n: 8}, 碎石: {surface: \gravel}, 雪地: {surface: \snow}, 草地: {surface: \grass}, 跑: {gait: \run, n: 8}}
      * name: \bell, desc: '鐘 ( 教堂鐘、管鐘 )', params: [N(\note, \C5), R(\dur, 1, 10, 0.5, 5), pan] ++ rv(0.2)
        presets: {大鐘: {note: \C3, dur: 8}, 管鐘: {note: \G5, dur: 3}}
      * name: \thunder, desc: \雷, params: [R(\dur, 2, 12, 0.5, 6), R(\dist, 0, 1, 0.05, 0.5), seed(79)]
        presets: {近: {dist: 0}, 遠: {dist: 1}}
      * name: \wind, desc: \風, params: [R(\dur, 1, 10, 0.5, 6), R(\cutoff, 200, 3000, 10, 900), seed(17)]
        presets: {低沉: {cutoff: 400}, 尖: {cutoff: 2400}}
      * name: \rain, desc: \雨, params: [R(\dur, 1, 10, 0.5, 6), R(\density, 0.002, 0.2, 0.002, 0.02), seed(19)]
        presets: {毛毛雨: {density: 0.006}, 大雨: {density: 0.08}}
      * name: \buzz, desc: \昆蟲振翅, params: [R(\dur, 0.2, 4, 0.1, 1.5), R(\freq, 80, 600, 1, 220), pan]
        presets: {高: {freq: 330}, 大隻: {freq: 120, dur: 2.5}}
  * name: \樂器
    sounds:
      * name: \pluck, desc: '撥弦 ( 類古箏 )'
        params: [N(\note, \A3), R(\dur, 0.3, 5, 0.1, 2.5), R(\bright, 0, 1, 0.05, 0.6), R(\slide, 0, 3, 0.1, 0.6), seed(13), pan] ++ rv!
        presets: {亮: {note: \D4, bright: 0.9}, 悶: {note: \A2, bright: 0.1}, 不滑音: {slide: 0}}
      * name: \guitar, desc: '吉他 ( 單音或刷和弦 )'
        params: [
          N(\note, \E3), O(\chord, ['', ...<[C D Dm E Em F G A Am]>], ''), J(\notes, null), O(\dir, <[down up]>, \down)
          R(\strum, 0, 0.1, 0.005, 0.03), R(\dur, 0.5, 6, 0.1, 3), R(\bright, 0, 1, 0.05, 0.5)
          R(\pos, 0.05, 0.5, 0.01, 0.2), R(\mute, 0, 1, 0.05, 0), seed(89), pan
        ] ++ rv!
        presets: {Em: {chord: \Em}, G: {chord: \G}, 上刷: {chord: \Am, dir: \up, strum: 0.015}, 悶音: {note: \E2, mute: 0.8}, 泛音感: {note: \E4, pos: 0.5, bright: 0.9}}
      * name: \marimba, desc: '馬林巴 ( 木琴 )', params: [N(\note, \C4), R(\dur, 0.3, 4, 0.1, 1.5), R(\hard, 0, 1, 0.05, 0.5), pan] ++ rv!
        presets: {低: {note: \C3}, 硬槌: {hard: 1}, 軟槌: {hard: 0}}
      * name: \xylophone, desc: '木琴', params: [N(\note, \C5), R(\dur, 0.2, 3, 0.1, 0.8), R(\hard, 0, 1, 0.05, 0.5), pan] ++ rv!
      * name: \vibraphone, desc: '鐵琴 ( 顫音琴 )', params: [N(\note, \F4), R(\dur, 0.5, 6, 0.1, 3), R(\trem, 0, 1, 0.05, 0.35), R(\hard, 0, 1, 0.05, 0.5), pan] ++ rv!
        presets: {無顫音: {trem: 0}, 殘響: {reverb: 0.4}}
      * name: \glockenspiel, desc: '鐘琴', params: [N(\note, \C6), R(\dur, 0.3, 4, 0.1, 2), R(\hard, 0, 1, 0.05, 0.5), pan] ++ rv!
      * name: \melody, desc: '旋律 ( 可換樂器 )'
        params: [J(\notes, [[0, \A3], [0.4, \C4], [0.8, \E4], [1.2, \A4, 2]]), O(\instrument, INSTRUMENTS, \pluck), R(\bright, 0, 1, 0.05, 0.6), R(\slide, 0, 3, 0.1, 0.6)] ++ rv!
        presets:
          五聲: {notes: [[0, \D4], [0.25, \E4], [0.5, \G4], [0.75, \A4], [1, \D5, 2]]}
          和弦: {notes: [[0, \C3, 2.5], [0.03, \G3, 2.5], [0.06, \E4, 2.5]], slide: 0}
          馬林巴: {instrument: \marimba, notes: [[0, \C4], [0.2, \E4], [0.4, \G4], [0.6, \C5], [0.8, \G4], [1, \C5, 1.5]]}
          鐵琴: {instrument: \vibraphone, notes: [[0, \F4, 2], [0.5, \A4, 2], [1, \C5, 2], [1.5, \E5, 3]], reverb: 0.3}
      * name: \drone, desc: '持續低音'
        params: [J(\notes, <[A1 E2 A2]>), R(\dur, 1, 12, 0.5, 8), R(\attack, 0.1, 4, 0.1, 1.5), R(\release, 0.1, 4, 0.1, 2)]
        presets: {小調: {notes: <[A1 E2 C3]>}, 高: {notes: <[D3 A3 D4]>, dur: 4}}
  * name: \鼓組
    sounds:
      * name: \kick, desc: \大鼓, params: [R(\tune, 30, 120, 1, 50), R(\decay, 0.05, 1, 0.01, 0.3), R(\punch, 0, 1, 0.05, 0.5), pan]
        presets: {808: {tune: 42, decay: 0.8, punch: 0.2}, 緊: {decay: 0.15, punch: 1}}
      * name: \snare, desc: \小鼓, params: [R(\tune, 100, 400, 1, 180), R(\decay, 0.05, 0.5, 0.01, 0.15), R(\snappy, 0, 1, 0.05, 0.6), seed(101), pan]
      * name: \hihat, desc: 'hi-hat', params: [R(\open, 0, 1, 0.05, 0), R(\tune, 0.5, 2, 0.05, 1), seed(103), pan]
        presets: {開: {open: 0.7}}
      * name: \tom, desc: '中鼓 / 落地鼓', params: [N(\note, \A2), R(\decay, 0.1, 1, 0.01, 0.35), seed(107), pan]
        presets: {高: {note: \D3}, 落地: {note: \E2, decay: 0.6}}
      * name: \clap, desc: \拍手, params: [R(\decay, 0.03, 0.5, 0.01, 0.12), seed(109)]
      * name: \crash, desc: \碎音鈸, params: [R(\decay, 0.3, 3, 0.05, 1), R(\tune, 0.5, 2, 0.05, 1), seed(113)]
        presets: {短: {decay: 0.5}, 大: {decay: 1.8, tune: 0.8}, 小: {decay: 0.6, tune: 1.4}}
      * name: \ride, desc: \疊音鈸, params: [R(\decay, 0.3, 3, 0.05, 1), R(\bell, 0, 1, 0.05, 0), R(\tune, 0.5, 2, 0.05, 1), seed(127)]
        presets: {鈸心: {bell: 1}, 短: {decay: 0.5}}
      * name: \beat, desc: '節奏 ( 十六分音符一格 )'
        params: [J(\pattern, ROCK), R(\bpm, 50, 200, 1, 100), R(\bars, 1, 8, 1, 1), R(\swing, 0, 1, 0.05, 0)] ++ rv!
        presets:
          搖滾: {pattern: ROCK, bars: 2}
          四拍大鼓: {pattern: {kick: 'x...x...x...x...', clap: '....x.......x...', ohat: '..x...x...x...x.'}, bpm: 120, bars: 2}
          Hip-hop: {pattern: {kick: 'x......x..x.....', snare: '....x.......x..o', hihat: 'x.x.x.x.x.x.x.x.'}, bpm: 88, swing: 0.5, bars: 2}
          過門: {pattern: {kick: 'x...............', htom: 'x.x.x...........', tom: '......x.x.......', ltom: '..........x.x...', crash: '................|x'}, bpm: 110}

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
    "tune": ["melody", {"instrument": "marimba", "notes": [[0, "D4"], [0.3, "F4"], [0.6, "A4"], [0.9, "D5", 2]]}],
    "count": ["count", {"n": 10, "dur": 0.8}],
    "ta": ["reveal", {}]
  },
  "timeline": [
    {"t": 0, "sound": "bed", "bus": "music", "gain": 0.35, "fadeIn": 1, "fadeOut": 2},
    {"t": 0.8, "sound": "sw", "gain": 0.7},
    {"t": 1.5, "sound": "pop"},
    {"t": 1.9, "sound": "pop"},
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
