# 五線譜: 4/4 拍 4 個小節, 以 sfx.synth.score 照樂譜演奏 ( 樂譜文字與五線譜雙向同步 )
#  - 音高以 step 表示: C4 = 0, 往上每個白鍵 +1 ( 高音譜號最下線 E4 = 2, 最上線 F5 = 10 )
#  - 音長以拍為單位: 全音符 4, 二分 2, 四分 1 ...; 附點乘 1.5
#  - 每個小節固定 4 拍: 音變長會吃掉後面的音, 變短會補上休止符
S = window.sfx

SP = 10                          # 線距 ( viewBox 單位 )
W = 960
TOP = 36                         # 最上線 ( F5 ) 的 y
BOTTOM = TOP + 4 * SP            # 最下線 ( E4 ) 的 y
H = BOTTOM + 52
LEFT = 78                        # 譜號、拍號之後
RIGHT = W - 12
MW = (RIGHT - LEFT) / 4          # 一個小節的寬度
NAMES = <[C D E F G A B]>
DURS = [4 2 1 0.5 0.25 0.125 0.0625 0.03125]   # 按鍵 1 ~ 8
MIN-STEP = -3                    # G3
MAX-STEP = 15                    # C6
INSTRUMENTS = (S.params.score.find (p) -> p.k == \instrument).options

len = (e) -> e.base * (if e.dot => 1.5 else 1)
note-name = (step) -> NAMES[((step % 7) + 7) % 7] + (4 + Math.floor(step / 7))
y-of = (step) -> BOTTOM - (step - 2) * SP / 2
n = (step, base = 1) -> {step, base, dot: false, rest: false}
# 拆成不帶附點的音長 ( 由長到短 )
decompose = (x) ->
  out = []
  for d in DURS => while x >= d - 1e-9 => out.push d; x -= d
  out

# 預設: 小星星
measures = [
  [n(0), n(0), n(4), n(4)]
  [n(5), n(5), n(4, 2)]
  [n(3), n(3), n(2), n(2)]
  [n(1), n(1), n(0, 2)]
]
st = {m: 0, i: 0, inst: \pluck, bpm: 100, play: null, msg: ''}

start-of = (m, i) -> measures[m].slice(0, i).reduce(((a, e) -> a + len e), 0)

# 改音長 ( 小節內覆寫 ); 放不下就回傳 false
set-len = (m, i, base, dot) ->
  E = measures[m]; e = E[i]
  d = base * (if dot => 1.5 else 1)
  if d > 4 - start-of(m, i) + 1e-9 => return false
  old = len e
  e.base = base; e.dot = dot
  if d < old - 1e-9
    E.splice i + 1, 0, ...decompose(old - d).map((b) -> {step: e.step, base: b, dot: false, rest: true})
  else if d > old + 1e-9
    need = d - old
    j = i + 1
    while need > 1e-9 and j < E.length
      L = len E[j]
      if L <= need + 1e-9
        need -= L
        E.splice j, 1
      else
        f = E[j]
        pieces = decompose(L - need)
        need = 0
        E.splice j, 1, ...pieces.map((b, k) -> {step: f.step, base: b, dot: false, rest: (if k == 0 => f.rest else true)})
  true

# ---------------------------------------------------------------- 樂譜文字 <-> 五線譜
# 五線譜 -> 文字: 音長與前一個相同就省略
to-text = ->
  last = null
  bars = for E in measures
    toks = for e in E
      d = "/#{4 / e.base}#{if e.dot => '.' else ''}"
      tok = (if e.rest => '-' else note-name e.step) + (if d == last => '' else d)
      last := d
      tok
    toks.join ' '
  bars.join ' | '
# 文字 -> 五線譜: 只支援自然音、單音、不跨小節; 不足 4 小節補休止符
from-text = (text) ->
  ms = [[] [] [] []]
  m = 0; used = 0
  for x in S.score.parse text
    if x.notes.length > 1 => throw new Error('五線譜不支援和弦')
    b = x.beats
    [base, dot] = if b in DURS => [b, false] else if (b / 1.5) in DURS => [b / 1.5, true] else throw new Error("不支援的音長: #{b} 拍")
    if used >= 4 - 1e-9 => m++; used = 0
    if m > 3 => throw new Error('超過 4 個小節')
    if used + b > 4 + 1e-9 => throw new Error("第 #{m + 1} 小節放不下 ( 音符不能跨小節 )")
    step = 0
    if x.notes.length
      mm = /^([A-G])(#|b)?(-?\d)$/.exec x.notes.0
      if mm.2 => throw new Error('五線譜只支援自然音 ( 沒有 # 或 b )')
      step = NAMES.indexOf(mm.1) + (+mm.3 - 4) * 7
      if step < MIN-STEP or step > MAX-STEP => throw new Error("音域只到 #{note-name MIN-STEP} ~ #{note-name MAX-STEP}")
    ms[m].push {step, base, dot, rest: !x.notes.length}
    used += b
  # 不足的地方補休止符
  for E, k in ms
    left = 4 - E.reduce(((a, e) -> a + len e), 0)
    for b in decompose(left) => E.push {step: 6, base: b, dot: false, rest: true}
  measures := ms
  st.m = 0; st.i = 0

# ---------------------------------------------------------------- 播放
events = ->
  out = []; t = 0
  for E, m in measures
    for e, i in E
      out.push {m, i, t, d: len(e), e}
      t += len e
  out
opts = -> {score: to-text!, instrument: st.inst, bpm: st.bpm}
code = -> "sfx.synth.score({score: '#{to-text!}', instrument: '#{st.inst}', bpm: #{st.bpm}})"

stop = ->
  if st.play => st.play.h.stop 0.05
  st.play = null
  render!
play = ->
  if st.play => return stop!
  S.resume!
  if !events!.some((x) -> !x.e.rest) => return
  spb = 60 / st.bpm
  buf = S.synth.score opts!
  h = S.play buf, {gain: 0.9}
  st.play = {h, at: S.ctx!currentTime, spb, cur: null}
  render!
# 試聽單一個音 ( 拖曳音高時 )
preview = (step) ->
  S.resume!
  try S.play S.synth.score({score: "#{note-name step}/4", instrument: st.inst, bpm: 120}), {gain: 0.7} catch

# ---------------------------------------------------------------- 畫譜
flag-path = (x, y, k, up) ->
  # 第 k 面符尾 ( 從符桿末端往下 / 往上彎 )
  dy = if up => k * 6 else -k * 6
  s = if up => 1 else -1
  "M#{x} #{y + dy} c 2 #{4 * s} 10 #{6 * s} 7 #{16 * s}"
rest-svg = (x, e, cls) ->
  b = e.base
  mid = TOP + 2 * SP
  g = switch
  | b >= 4 => "<rect x='#{x - 6}' y='#{TOP + SP}' width='12' height='#{SP / 2}'/>"
  | b >= 2 => "<rect x='#{x - 6}' y='#{mid - SP / 2}' width='12' height='#{SP / 2}'/>"
  | b >= 1 => "<path d='M#{x - 2} #{mid - 14} l6 7 l-6 6 l6 7 c-6 -2 -8 2 -3 6' fill='none' stroke-width='2.4'/>"
  | otherwise =>
    k = Math.round(Math.log2(1 / b))
    dots = [("<circle cx='#{x - 3 + j * 1.5}' cy='#{mid - 6 + j * 7}' r='2.6'/>") for j from 0 til k].join('')
    "<path d='M#{x + 4 + k * 1.5} #{mid - 9} L#{x - 2} #{mid + 4 + (k - 1) * 7}' fill='none' stroke-width='1.6'/>" + dots
  dot = if e.dot => "<circle cx='#{x + 10}' cy='#{mid - SP / 2}' r='1.8'/>" else ''
  "<g class='#{cls}'>#{g}#{dot}</g>"
note-svg = (x, e, cls) ->
  y = y-of e.step
  b = e.base
  up = e.step < 6
  filled = b <= 1
  out = []
  # 加線
  if e.step <= 0 => for s from 0 to e.step by -2 => out.push "<line class='ledger' x1='#{x - 9}' x2='#{x + 9}' y1='#{y-of s}' y2='#{y-of s}'/>"
  if e.step >= 12 => for s from 12 to e.step by 2 => out.push "<line class='ledger' x1='#{x - 9}' x2='#{x + 9}' y1='#{y-of s}' y2='#{y-of s}'/>"
  out.push "<ellipse cx='#{x}' cy='#{y}' rx='5.8' ry='4.2' transform='rotate(-20 #{x} #{y})' class='#{if filled => 'fill' else 'hollow'}'/>"
  if b < 4
    sx = if up => x + 5.2 else x - 5.2
    ey = if up => y - 32 else y + 32
    out.push "<line class='stem' x1='#{sx}' x2='#{sx}' y1='#{y}' y2='#{ey}'/>"
    if b < 1
      for k from 0 til Math.round(Math.log2(1 / b)) => out.push "<path class='flag' d='#{flag-path sx, ey, k, up}'/>"
  if e.dot
    dy = if (e.step % 2 + 2) % 2 == 0 => -SP / 2 else 0   # 在線上的音, 附點往上挪半格
    out.push "<circle class='fill' cx='#{x + 11}' cy='#{y + dy}' r='1.8'/>"
  "<g class='#{cls}'>#{out.join ''}</g>"

render = ->
  svg = document.querySelector '#staff svg'
  if !svg => return
  out = []
  bg = []                        # 選取的底色: 畫在最底層, 不蓋住譜線與其他音符
  for k from 0 til 5 => out.push "<line class='line' x1='8' x2='#{RIGHT}' y1='#{TOP + k * SP}' y2='#{TOP + k * SP}'/>"
  out.push "<text class='clef' x='10' y='#{BOTTOM + 9}'>𝄞</text>"
  out.push "<text class='meter' x='52' y='#{TOP + SP * 2 - 2}'>4</text><text class='meter' x='52' y='#{BOTTOM - 2}'>4</text>"
  for m from 0 til 4
    mx = LEFT + m * MW
    E = measures[m]
    # 小節內的間距: 依音長的 0.6 次方分配
    ws = E.map (e) -> Math.pow(len(e), 0.6)
    tot = ws.reduce ((a, b) -> a + b), 0
    acc = 0
    for e, i in E
      x = mx + 16 + acc / tot * (MW - 24)
      acc += ws[i]
      sel = st.m == m and st.i == i
      playing = st.play and st.play.cur and st.play.cur.m == m and st.play.cur.i == i
      cls = ['ev'] ++ (if sel => ['sel'] else []) ++ (if playing => ['on'] else [])
      if sel => bg.push "<rect x='#{x - 10}' y='#{TOP - 30}' width='22' height='#{H - TOP + 20}' class='selbox'/>"
      out.push "<g data-m='#{m}' data-i='#{i}' class='hit'><rect x='#{x - 10}' y='#{TOP - 30}' width='22' height='#{H - TOP + 20}' class='hitbox'/>"
      out.push (if e.rest => rest-svg(x, e, cls.join ' ') else note-svg(x, e, cls.join ' '))
      out.push "</g>"
    bx = mx + MW
    out.push "<line class='bar' x1='#{bx}' x2='#{bx}' y1='#{TOP}' y2='#{BOTTOM}'/>"
  out.push "<line class='bar end' x1='#{RIGHT + 4}' x2='#{RIGHT + 4}' y1='#{TOP}' y2='#{BOTTOM}'/>"
  svg.innerHTML = bg.join('') + out.join('')
  e = measures[st.m][st.i]
  q = (s) -> document.querySelector "\#staff #{s}"
  q('.sel-info').textContent = if e.rest => "第 #{st.m + 1} 小節: 休止符 #{len e} 拍" else "第 #{st.m + 1} 小節: #{note-name e.step}, #{len e} 拍"
  q('.msg').textContent = st.msg
  q('[data-act=play]').textContent = if st.play => '■ 停止' else '▶ 播放'
  q('select.inst').value = st.inst
  q('.bpm-val').textContent = st.bpm
  q('code.staff-code').textContent = code!
  # 打字中不覆寫
  ta = q('input.score-text')
  if ta != document.activeElement => ta.value = to-text!; ta.classList.remove \bad

flash = (msg) ->
  st.msg = msg
  setTimeout (-> st.msg = ''; render!), 1500

# ---------------------------------------------------------------- 操作
move = (d) ->
  flat = [[m, i] for E, m in measures for e, i in E]
  k = flat.findIndex ([m, i]) -> m == st.m and i == st.i
  [st.m, st.i] = flat[Math.max(0, Math.min(flat.length - 1, k + d))]

key = (evt) ->
  e = measures[st.m][st.i]
  k = evt.key
  if /^[1-8]$/.test(k)
    base = DURS[+k - 1]
    if !set-len(st.m, st.i, base, e.dot) and !set-len(st.m, st.i, base, false) => flash '這個小節放不下'
  else if k == '.' => (if !set-len(st.m, st.i, e.base, !e.dot) => flash '這個小節放不下附點')
  else if k in <[- Backspace Delete]> => e.rest = true
  else if k in <[+ =]> => e.rest = false; preview e.step
  else if k == \ArrowLeft => move -1
  else if k == \ArrowRight => move 1
  else if k in <[ArrowUp ArrowDown]>
    e.step = Math.max(MIN-STEP, Math.min(MAX-STEP, e.step + (if k == \ArrowUp => 1 else -1)))
    if !e.rest => preview e.step
  else if k == ' ' => play!
  else return
  evt.preventDefault!
  render!

drag = null
init = ->
  root = document.querySelector '#staff'
  svg = root.querySelector 'svg'
  svg.setAttribute \viewBox, "0 0 #W #H"
  box = root.querySelector '.staff-box'
  box.addEventListener \keydown, key
  svg.addEventListener \pointerdown, (evt) ->
    g = evt.target.closest '[data-m]'
    if !g => return
    box.focus!
    st.m = +g.dataset.m; st.i = +g.dataset.i
    e = measures[st.m][st.i]
    if !e.rest
      svg.setPointerCapture evt.pointerId
      drag := {y: evt.clientY, step: e.step, last: e.step}
    render!
  svg.addEventListener \pointermove, (evt) ->
    if !drag => return
    scale = W / svg.clientWidth
    e = measures[st.m][st.i]
    e.step = Math.max(MIN-STEP, Math.min(MAX-STEP, drag.step - Math.round((evt.clientY - drag.y) * scale / (SP / 2))))
    if e.step != drag.last => drag.last = e.step; preview e.step; render!
  svg.addEventListener \pointerup, -> drag := null
  sel = root.querySelector 'select.inst'
  for v in INSTRUMENTS
    o = document.createElement \option
    o.value = o.textContent = v
    sel.appendChild o
  sel.addEventListener \change, -> st.inst = sel.value; render!
  root.querySelector('[data-act=dice]').addEventListener \click, ->
    others = INSTRUMENTS.filter (v) -> v != st.inst
    st.inst = others[Math.floor(Math.random! * others.length)]
    render!
  root.querySelector('[data-act=play]').addEventListener \click, -> play!
  bpm = root.querySelector 'input.bpm'
  bpm.addEventListener \input, -> st.bpm = +bpm.value; render!
  root.querySelector('[data-act=copy]').addEventListener \click, (evt) ->
    navigator.clipboard.writeText(code!).then ->
      evt.target.textContent = '已複製'
      setTimeout (-> evt.target.textContent = '複製'), 1000
  ta = root.querySelector 'input.score-text'
  ta.addEventListener \input, ->
    try
      from-text ta.value
      ta.classList.remove \bad
      st.msg = ''
    catch e
      ta.classList.add \bad
      st.msg = e.message
    render!
  render!
  # 播放中標出目前的音
  tick = ->
    if st.play
      t = (S.ctx!currentTime - st.play.at) / st.play.spb
      if t >= 16 + 0.5 => stop!
      else
        x = events!.find (x) -> t >= x.t and t < x.t + x.d
        cur = if x => {m: x.m, i: x.i} else null
        if JSON.stringify(cur) != JSON.stringify(st.play.cur) => st.play.cur = cur; render!
    requestAnimationFrame tick
  requestAnimationFrame tick

init!
