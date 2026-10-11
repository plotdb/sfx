# @plotdb/sfx: 給確定性動畫 ( 例如 lotion ) 用的音訊 runtime 與程序化合成. 瀏覽器全域 window.sfx
#
# 兩種用法並存:
#  - 時間軸 ( 宣告式 ): 聲音綁在動畫時間 t 上, 跟著播放 / 暫停 / 拖曳同步. sfx.timeline [{t, sound, ...}]
#  - 指令式 ( 互動 ): 立即播放, 與時間軸無關. sfx.play / sfx.stop / sfx.music / sfx.volume
#
# 時間軸由誰驅動:
#  - 頁面上的 lotion.player: 自動攔截 play / pause / seek
#  - 外部時鐘 ( 例如外層頁面經 postMessage 控制 iframe 裡的動畫 ): 呼叫 sfx.transport({playing, t, from: <名稱>}),
#    帶 from 之後忽略 player
#
# AudioContext: 第一次用到時建立. 瀏覽器的自動播放限制下, 要在使用者操作 ( 點擊 ) 後呼叫 sfx.resume()
do ->
  if typeof(window) != \undefined and window.sfx => return
  SR = 48000
  S = {buffers: {}, urls: {}, items: [], voices: [], errors: [], external: false, playing: false, rate: 1}

  # ---------------------------------------------------------------- context / 音軌
  ctx = null
  S.ctx = ->
    if ctx => return ctx
    AC = window.AudioContext or window.webkitAudioContext
    ctx := new AC!
    S.master = ctx.createGain!
    S.master.connect ctx.destination
    S.buses = {}
    for b in <[music sfx voice]>
      S.buses[b] = ctx.createGain!
      S.buses[b].connect S.master
    ctx
  bus = (name) -> S.ctx!; S.buses[name] or S.buses.sfx
  S.resume = -> c = S.ctx!; if c.state == \suspended => c.resume! else Promise.resolve!

  # 音量: bus 為 music | sfx | voice | master
  S.volume = (name, v, dur = 0.2) ->
    S.ctx!
    g = if name == \master => S.master else S.buses[name]
    if !g => return
    now = ctx.currentTime
    g.gain.cancelScheduledValues now
    g.gain.setValueAtTime g.gain.value, now
    g.gain.linearRampToValueAtTime v, now + Math.max(0.01, dur)

  # 不用 instanceof AudioBuffer: 頁面可能拿到別的 realm 建的 buffer ( 建構子不同 ). 以特徵判斷.
  is-buffer = (v) -> !!(v and typeof(v) == \object and typeof(v.getChannelData) == \function and v.sampleRate)

  # ---------------------------------------------------------------- 載入
  # map: {name: url | AudioBuffer | Promise<AudioBuffer>}
  S.pending = 0     # 載入中的數量 ( 輸出影片時等它歸零再混音 )
  S.load = (map = {}) ->
    S.pending += Object.keys(map).length
    Promise.all Object.keys(map).map (name) ->
      v = map[name]
      p = if is-buffer(v) => Promise.resolve(v)
      else if v and v.then => v
      else
        fetch(v).then (r) ->
          if !r.ok => throw new Error("#v: HTTP #{r.status}")
          r.arrayBuffer!
        .then (ab) -> new Promise (res, rej) -> S.ctx!decodeAudioData ab, res, rej
      if typeof(v) == \string => S.urls[name] = v   # 倍速播放旁白 / 配樂時用 <audio> ( 保持音高 ) 要用到網址
      p.then (buf) -> S.buffers[name] = buf
      .catch (e) -> S.errors.push "load #name: #{e.message or e}"
      .finally -> S.pending--
    .then -> S.buffers

  # 起音點: 3ms RMS 第一次到達最大值 80% 處, 再爬到局部最大 ( 對齊 cue 用, 同 lotitor sfx.py )
  peaks = new WeakMap!
  S.peak = (buf) ->
    if peaks.has buf => return peaks.get buf
    d = buf.getChannelData 0
    w = Math.max 1, Math.round(buf.sampleRate * 0.003)
    env = new Float32Array Math.ceil(d.length / w)
    max = 0
    for i from 0 til env.length
      s = 0
      for j from i * w til Math.min(d.length, (i + 1) * w) => s += d[j] * d[j]
      env[i] = Math.sqrt(s / w)
      if env[i] > max => max = env[i]
    i = 0
    while i < env.length - 1 and env[i] < max * 0.8 => i++
    while i < env.length - 1 and env[i + 1] > env[i] => i++
    peaks.set buf, i * w / buf.sampleRate
    peaks.get buf

  # ---------------------------------------------------------------- 發聲
  # opt: gain, rate, loop, fadeIn, fadeOut, offset, duration, bus, when ( ctx 時間 )
  voice = (name, opt = {}) ->
    buf = if is-buffer(name) => name else S.buffers[name]
    if !buf
      S.errors.push "unknown sound: #name"
      return null
    c = S.ctx!
    src = c.createBufferSource!
    src.buffer = buf
    src.loop = !!opt.loop
    src.playbackRate.value = opt.rate or 1
    g = c.createGain!
    src.connect g
    g.connect bus(opt.bus or \sfx)
    when_ = opt.when or c.currentTime
    level = if opt.gain? => opt.gain else 1
    if opt.fadeIn
      g.gain.setValueAtTime 0, when_
      g.gain.linearRampToValueAtTime level, when_ + opt.fadeIn
    else g.gain.setValueAtTime level, when_
    offset = opt.offset or 0
    if opt.duration?
      # duration 是實際經過的時間 ( ctx 時間 ); src.start 的長度要換成檔案內的時間 ( 乘上播放速率 )
      end = when_ + opt.duration
      if opt.fadeOut
        g.gain.setValueAtTime level, Math.max(when_, end - opt.fadeOut)
        g.gain.linearRampToValueAtTime 0, end
      src.start when_, offset, (if src.loop => undefined else opt.duration * (opt.rate or 1))
      if src.loop => src.stop end
    else src.start when_, offset
    v = {name, src, gain: g, level, ended: false}
    src.onended = -> v.ended = true; S.voices = S.voices.filter (x) -> x != v
    S.voices.push v
    v

  # 倍速時的旁白 / 配樂: AudioBuffer 調 playbackRate 會連音高一起變, 改用 <audio> ( preservesPitch ) 接到同一個 bus.
  # 開始時間用 setTimeout 對齊 ( 誤差約數十毫秒, 對語音與配樂可接受 ); 音量、淡入淡出仍在 ctx 時間上排
  media-voice = (name, opt = {}) ->
    c = S.ctx!
    a = new Audio!
    a.crossOrigin = \anonymous
    a.preload = \auto
    a.preservesPitch = true
    a.loop = !!opt.loop
    a.src = S.urls[name]
    a.playbackRate = opt.rate or 1
    g = c.createGain!
    c.createMediaElementSource(a).connect g
    g.connect bus(opt.bus or \music)
    when_ = opt.when or c.currentTime
    level = if opt.gain? => opt.gain else 1
    if opt.fadeIn
      g.gain.setValueAtTime 0, when_
      g.gain.linearRampToValueAtTime level, when_ + opt.fadeIn
    else g.gain.setValueAtTime level, when_
    if opt.duration? and opt.fadeOut
      end = when_ + opt.duration
      g.gain.setValueAtTime level, Math.max(when_, end - opt.fadeOut)
      g.gain.linearRampToValueAtTime 0, end
    v = {name, media: a, gain: g, level, ended: false, timers: []}
    go = ->
      if v.ended => return
      seek-then-play = -> a.currentTime = opt.offset or 0; a.play!catch(->)
      if a.readyState >= 1 => seek-then-play! else a.addEventListener \loadedmetadata, seek-then-play, {once: true}
    delay = Math.max 0, when_ - c.currentTime
    v.timers.push setTimeout(go, delay * 1000)
    if opt.duration? => v.timers.push setTimeout((-> stop-voice v, 0.02), (delay + opt.duration) * 1000)
    a.onended = -> v.ended = true; S.voices = S.voices.filter (x) -> x != v
    S.voices.push v
    v

  stop-voice = (v, fade = 0.05) ->
    if !v or v.ended => return
    now = ctx.currentTime
    v.gain.gain.cancelScheduledValues now
    v.gain.gain.setValueAtTime v.gain.gain.value, now
    v.gain.gain.linearRampToValueAtTime 0, now + fade
    if v.media
      for h in v.timers => clearTimeout h
      v.ended = true
      setTimeout (-> v.media.pause!; v.media.removeAttribute \src; v.media.load!), (fade + 0.02) * 1000
      S.voices = S.voices.filter (x) -> x != v
      return
    try v.src.stop now + fade + 0.01 catch e

  # 指令式播放: 回傳 handle {stop(fade), fade(to, dur)}
  S.play = (name, opt = {}) ->
    S.resume!
    v = voice name, opt
    if !v => return null
    v.manual = true
    stop: (fade) -> stop-voice v, fade
    fade: (to, dur = 0.5) ->
      now = ctx.currentTime
      v.gain.gain.cancelScheduledValues now
      v.gain.gain.setValueAtTime v.gain.gain.value, now
      v.gain.gain.linearRampToValueAtTime to, now + dur
    voice: v

  # 停止指令式播放的聲音 ( 不給 name 就全停 )
  S.stop = (name, opt = {}) ->
    for v in S.voices when v.manual and (!name or v.name == name) => stop-voice v, (opt.fade or 0.05)

  # 背景音樂槽: 同時只有一首, 換曲時交叉淡入淡出; name 為 null 則淡出停止
  current-music = null
  S.music = (name, opt = {}) ->
    fade = if opt.fade? => opt.fade else 1
    if current-music => current-music.stop fade
    current-music := null
    if !name => return null
    current-music := S.play name, {loop: true, bus: \music, fadeIn: fade} <<< opt
    current-music

  # ---------------------------------------------------------------- 時間軸
  # item: {t, sound, gain, rate, loop, until ( loop 到何時 ), duration, fadeIn, fadeOut, offset, bus, align: 'peak' | 'start'}
  #  - sfx bus 預設 align: 'peak', 讓起音點落在 t 上
  S.timeline = (items = []) ->
    S.items = items.map (it) -> {} <<< it
    if S.playing => S.transport {playing: true, t: S.t or 0, force: true}
    S

  # lotion 的 cues [{t, sfx, gain}] 轉成時間軸項目
  S.cues = (cues = [], opt = {}) -> S.timeline cues.map (c) -> {t: c.t, sound: c.sfx or c.sound, gain: c.gain} <<< opt

  stop-timeline = -> for v in S.voices when !v.manual => stop-voice v, 0.03

  # 倍速 R ( S.rate ): 動畫時間 Δ 對應 ctx 時間 Δ / R, 播放速率乘上 R
  start-timeline = (t0) ->
    c = S.ctx!
    now = c.currentTime + 0.02
    R = S.rate or 1
    for it in S.items
      buf = S.buffers[it.sound]
      if !buf => continue
      b = it.bus or \sfx
      lead = if (it.align or (if b == \sfx => \peak else \start)) == \peak => S.peak(buf) else 0
      start = it.t - lead                          # 檔案開頭對應的動畫時間
      len = if it.loop => ((if it.until? => it.until else 1e9) - start) else (it.duration or buf.duration / (it.rate or 1))
      if start + len <= t0 => continue
      skip = Math.max 0, t0 - start                 # 已經過去的部分
      opt = {} <<< it <<< {bus: b, when: now + Math.max(0, start - t0) / R, duration: (len - skip) / R, rate: (it.rate or 1) * R}
      opt.offset = (it.offset or 0) + (if it.loop => skip % buf.duration else skip * (it.rate or 1))
      if skip > 0 and it.fadeIn => opt.fadeIn = 0
      # 倍速時旁白與配樂要保持音高 ( 有網址才行; 程式合成的聲音沒有, 照樣變調 ); 短音效直接變速
      if R != 1 and b in <[voice music]> and S.urls[it.sound] => media-voice it.sound, opt else voice buf, opt

  # 外層或 player 告知播放狀態; 拖曳 ( 非連續的時間 ) 時重新排程
  # rate: 倍速 ( 外層的時鐘倍速 ); 改變時重新排程
  S.transport = ({playing, t = 0, force, from, rate} = {}) ->
    if from and from != \player => S.external = true
    if rate? and +rate > 0 and +rate != S.rate => S.rate = +rate; force = true
    was = S.playing
    S.playing = !!playing
    S.t = t
    S.t-at = (ctx and ctx.currentTime) or 0
    if !playing => return stop-timeline!
    S.resume!
    if was and !force => return
    stop-timeline!
    start-timeline t

  # ---------------------------------------------------------------- 攔截 lotion.player ( 自己播放時 )
  hook = (L) ->
    if !L or !L.player or L.player.__sound => return
    P = L.player.prototype
    play = P.play
    seek = P.seek
    P.play = (go = true) ->
      r = play.apply @, arguments
      if !S.external => S.transport {playing: @playing, t: @t}
      r
    P.seek = (t) ->
      last = @t
      r = seek.apply @, arguments
      if !S.external and @started
        # 播放中被拖到別處 ( 跳動 > 0.3 秒或往回 ): 重新排程
        if @playing and (@t < last - 0.01 or @t - last > 0.3) => S.transport {playing: true, t: @t, force: true}
        if !@playing and S.playing => S.transport {playing: false, t: @t}
      r
    L.player.__sound = true
  if window.lotion => hook window.lotion
  else
    # lotion 可能在本檔之後才載入: 等 DOMContentLoaded 再試
    document.addEventListener \DOMContentLoaded, -> hook window.lotion

  # ---------------------------------------------------------------- 離線混音 ( 輸出影片配音用 )
  S.render = (duration, opt = {}) ->
    sr = opt.sampleRate or SR
    oc = new OfflineAudioContext 2, Math.ceil(duration * sr), sr
    for it in S.items
      buf = S.buffers[it.sound]
      if !buf => continue
      b = it.bus or \sfx
      lead = if (it.align or (if b == \sfx => \peak else \start)) == \peak => S.peak(buf) else 0
      start = it.t - lead
      src = oc.createBufferSource!
      src.buffer = buf
      src.loop = !!it.loop
      src.playbackRate.value = it.rate or 1
      g = oc.createGain!
      level = if it.gain? => it.gain else 1
      g.gain.value = level
      src.connect g
      g.connect oc.destination
      at = Math.max 0, start
      if it.fadeIn => g.gain.setValueAtTime(0, at); g.gain.linearRampToValueAtTime(level, at + it.fadeIn)
      len = if it.loop => ((if it.until? => it.until else duration) - start) else (it.duration or buf.duration / (it.rate or 1))
      if it.fadeOut => g.gain.setValueAtTime(level, Math.max(at, start + len - it.fadeOut)); g.gain.linearRampToValueAtTime(0, start + len)
      src.start at, (it.offset or 0) + Math.max(0, -start)
      src.stop start + len
    oc.startRendering!

  # AudioBuffer -> wav Blob ( 16-bit )
  S.wav = (buf) ->
    ch = buf.numberOfChannels; n = buf.length
    dv = new DataView new ArrayBuffer(44 + n * ch * 2)
    w = (o, s) -> for i from 0 til s.length => dv.setUint8 o + i, s.charCodeAt(i)
    w 0, \RIFF; dv.setUint32 4, 36 + n * ch * 2, true; w 8, \WAVE; w 12, 'fmt '
    dv.setUint32 16, 16, true; dv.setUint16 20, 1, true; dv.setUint16 22, ch, true
    dv.setUint32 24, buf.sampleRate, true; dv.setUint32 28, buf.sampleRate * ch * 2, true
    dv.setUint16 32, ch * 2, true; dv.setUint16 34, 16, true; w 36, \data; dv.setUint32 40, n * ch * 2, true
    data = [buf.getChannelData(c) for c from 0 til ch]
    o = 44
    for i from 0 til n
      for c from 0 til ch
        v = Math.max(-1, Math.min(1, data[c][i]))
        dv.setInt16 o, (if v < 0 => v * 0x8000 else v * 0x7fff), true
        o += 2
    new Blob [dv], {type: \audio/wav}

  S.report = ->
    loaded: Object.keys(S.buffers).map (k) -> {name: k, duration: +S.buffers[k].duration.toFixed(2), peak: +S.peak(S.buffers[k]).toFixed(3)}
    timeline: S.items.length
    playing: S.playing
    # running | suspended ( 被自動播放限制擋住時停在 suspended )
    context: if ctx => ctx.state else null
    errors: S.errors.slice -10

  # ---------------------------------------------------------------- 程序化合成 ( 免費、可重現 )
  # 移植自 lotitor audio/sfx.py 與 sumi-ink score.py. 全部回傳 AudioBuffer ( 48kHz 雙聲道 )
  NOTES = {C: -9, D: -7, E: -5, F: -4, G: -2, A: 0, B: 2}
  S.freq = (n) ->
    if typeof(n) == \number => return n
    m = /^([A-G])(#|b)?(-?\d)$/.exec n
    if !m => return 440
    semi = NOTES[m.1] + (if m.2 == '#' => 1 else if m.2 == \b => -1 else 0) + (+m.3 - 4) * 12
    440 * Math.pow(2, semi / 12)

  # 可重現的亂數 ( 同樣的 seed 同樣的聲音 )
  rng = (seed = 1) ->
    s = seed .>>>. 0 or 1
    -> s := (s * 1664525 + 1013904223) .>>>. 0; s / 4294967296

  make = (dur, fn, opt = {}) ->
    n = Math.max 1, Math.round(dur * SR)
    L = new Float32Array n
    R = new Float32Array n
    fn L, R, n
    # 正規化到 peak ( 預設 0.9 )
    max = 0
    for i from 0 til n => max = Math.max max, Math.abs(L[i]), Math.abs(R[i])
    k = if max > 0 => (opt.peak or 0.9) / max else 1
    buf = new AudioBuffer {length: n, sampleRate: SR, numberOfChannels: 2}
    for i from 0 til n => L[i] *= k; R[i] *= k
    buf.copyToChannel L, 0
    buf.copyToChannel R, 1
    buf

  # 二階濾波 ( RBJ biquad ), 對 Float32Array 原地處理
  biquad = (d, type, f, q = 0.707) ->
    w = 2 * Math.PI * f / SR
    cs = Math.cos w; al = Math.sin(w) / (2 * q)
    [b0, b1, b2, a0, a1, a2] = switch type
    | \lp => [(1 - cs) / 2, 1 - cs, (1 - cs) / 2, 1 + al, -2 * cs, 1 - al]
    | \hp => [(1 + cs) / 2, -(1 + cs), (1 + cs) / 2, 1 + al, -2 * cs, 1 - al]
    | otherwise => [al, 0, -al, 1 + al, -2 * cs, 1 - al]
    x1 = x2 = y1 = y2 = 0
    for i from 0 til d.length
      x = d[i]
      y = (b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2) / a0
      x2 = x1; x1 = x; y2 = y1; y1 = y
      d[i] = y
    d

  noise = (n, r) -> d = new Float32Array n; (for i from 0 til n => d[i] = r! * 2 - 1); d
  env = (t, a, d) -> if t < a => t / a else Math.exp(-(t - a) / d)
  pan = (L, R, src, p = 0, gain = 1) ->
    gl = Math.cos((p + 1) * Math.PI / 4) * gain; gr = Math.sin((p + 1) * Math.PI / 4) * gain
    for i from 0 til src.length => L[i] += src[i] * gl; R[i] += src[i] * gr

  synth = S.synth = {}

  # 短促的 UI 聲
  synth.click = (o = {}) -> make 0.05, (L, R, n) ->
    r = rng(o.seed or 7)
    nz = biquad noise(n, r), \hp, 2500
    d = new Float32Array n
    for i from 0 til n
      t = i / SR
      d[i] = nz[i] * env(t, 0.0005, 0.004) + 0.5 * Math.sin(2 * Math.PI * (o.freq or 2000) * t) * env(t, 0.0005, 0.012)
    pan L, R, d, o.pan
  synth.tick = (o = {}) -> make 0.06, (L, R, n) ->
    f = S.freq(o.note or o.freq or 1800)
    d = new Float32Array n
    for i from 0 til n => t = i / SR; d[i] = Math.sin(2 * Math.PI * f * t) * env(t, 0.001, 0.018)
    pan L, R, d, o.pan
  synth.pop = (o = {}) -> make 0.15, (L, R, n) ->
    f0 = o.from or 380; f1 = o.to or 900
    d = new Float32Array n; ph = 0
    for i from 0 til n
      t = i / SR
      f = f0 + (f1 - f0) * Math.min(1, t / 0.03)
      ph += 2 * Math.PI * f / SR
      d[i] = Math.sin(ph) * env(t, 0.002, 0.04)
    pan L, R, d, o.pan
  synth.toggle = (o = {}) -> make 0.12, (L, R, n) ->
    d = new Float32Array n
    for i from 0 til n
      t = i / SR
      d[i] = Math.sin(2 * Math.PI * 1500 * t) * env(t, 0.001, 0.012) + (if t > 0.05 => Math.sin(2 * Math.PI * 2200 * (t - 0.05)) * env(t - 0.05, 0.001, 0.015) else 0)
    pan L, R, d, o.pan
  # 鐘聲: 泛音 1, 2.01, 3.02
  synth.chime = (o = {}) ->
    f = S.freq(o.note or 'E6'); dur = o.dur or 1.4
    make dur, (L, R, n) ->
      d = new Float32Array n
      for i from 0 til n
        t = i / SR
        d[i] = (Math.sin(2 * Math.PI * f * t) + 0.5 * Math.sin(2 * Math.PI * f * 2.01 * t) * Math.exp(-t * 2) + 0.25 * Math.sin(2 * Math.PI * f * 3.02 * t) * Math.exp(-t * 4)) * env(t, 0.003, dur / 4)
      pan L, R, d, o.pan
  synth.success = (o = {}) -> make 0.9, (L, R, n) ->
    d = new Float32Array n
    for [at, note] in [[0, 'C6'], [0.09, 'E6'], [0.18, 'G6']]
      f = S.freq note
      for i from Math.round(at * SR) til n
        t = i / SR - at
        d[i] += (Math.sin(2 * Math.PI * f * t) + 0.4 * Math.sin(2 * Math.PI * f * 2.01 * t)) * env(t, 0.003, 0.25)
    pan L, R, d, o.pan
  synth.notify = (o = {}) -> make 0.7, (L, R, n) ->
    d = new Float32Array n
    for [at, note] in [[0, 'A5'], [0.12, 'E6']]
      f = S.freq note
      for i from Math.round(at * SR) til n
        t = i / SR - at
        d[i] += Math.sin(2 * Math.PI * f * t) * env(t, 0.004, 0.18)
    pan L, R, d, o.pan
  # 掃頻雜訊: 轉場. 帶通濾波的中心頻率 from -> peak -> to ( Hz ), 在 at ( 0~1 ) 處最亮;
  # q 越大越尖銳 ( 像哨音 ), 越小越像風; seed 換一組雜訊 ( 同樣參數、不同質感 )
  synth.whoosh = (o = {}) ->
    dur = o.dur or 0.7
    f0 = o.from or 400; f1 = o.peak or 2600; f2 = o.to or 600; at = o.at or 0.45; q = o.q or 1.2
    make dur, (L, R, n) ->
      r = rng(o.seed or 3)
      nz = noise n, r
      d = new Float32Array n
      seg = 256
      for s from 0 til n by seg
        u = s / n
        fc = if u < at => f0 + (f1 - f0) * (u / at) else f1 + (f2 - f1) * ((u - at) / (1 - at))
        part = biquad nz.slice(s, s + seg), \bp, fc, q
        # 音量包絡: 在 at 處最大
        for i from 0 til part.length
          v = (s + i) / n
          d[s + i] = part[i] * (if v < at => Math.sin(Math.PI / 2 * v / at) else Math.cos(Math.PI / 2 * (v - at) / (1 - at)))
      for i from 0 til n => L[i] = d[i] * (1 - i / n * 0.6); R[i] = d[i] * (0.4 + i / n * 0.6)
  synth.type = (o = {}) -> synth.click {freq: 1200 + 600 * rng(o.seed or 11)!, seed: o.seed}
  # 低沉的落地 / 蓋章: 130 -> 70 Hz 掃頻 + 紙張雜訊
  synth.thump = (o = {}) -> make 0.35, (L, R, n) ->
    r = rng(o.seed or 5)
    nz = biquad noise(n, r), \bp, 1800, 0.8
    d = new Float32Array n; ph = 0
    for i from 0 til n
      t = i / SR
      ph += 2 * Math.PI * (70 + 60 * Math.exp(-t / 0.04)) / SR
      d[i] = Math.sin(ph) * env(t, 0.002, 0.09) + 0.35 * nz[i] * env(t, 0.001, 0.03)
    pan L, R, d, o.pan
  # 撥弦 ( Karplus-Strong ), 起音時往上滑 ( 類古箏 )
  synth.pluck = (o = {}) ->
    f = S.freq(o.note or 'A3'); dur = o.dur or 2.5; bright = if o.bright? => o.bright else 0.6; slide = if o.slide? => o.slide else 0.6
    make dur, (L, R, n) ->
      r = rng(o.seed or 13)
      period = SR / f
      size = Math.ceil(period * 2) + 4
      buf = noise size, r
      for k from 0 til Math.round((1 - bright) * 4)
        for i from 1 til size => buf[i] = (buf[i] + buf[i - 1]) / 2
      d = new Float32Array n
      line = new Float32Array n + size
      for i from 0 til size => line[i] = buf[i]
      decay = Math.pow(0.996, 220 / f)
      for k from size til n + size
        p = period * Math.pow(2, slide * Math.exp(-(k - size) / SR / 0.09) / 12)
        j = k - p; j0 = Math.floor j; fr = j - j0
        a = line[j0] * (1 - fr) + line[j0 + 1] * fr
        b = line[j0 - 1] * (1 - fr) + line[j0] * fr
        line[k] = decay * (a + b) / 2
        d[k - size] = line[k]
      for i from 0 til n => d[i] *= Math.min(1, (n - i) / (0.3 * SR))
      pan L, R, d, o.pan
  # 持續低音: 幾個略微走音的正弦
  synth.drone = (o = {}) ->
    notes = (o.notes or <[A1 E2 A2]>).map S.freq; dur = o.dur or 8; att = o.attack or 1.5; rel = o.release or 2
    make dur, (L, R, n) ->
      for f, k in notes
        d = new Float32Array n
        for i from 0 til n
          t = i / SR
          a = Math.min(1, t / att, (dur - t) / rel)
          d[i] = (Math.sin(2 * Math.PI * f * t) + 0.3 * Math.sin(2 * Math.PI * f * 1.003 * 2 * t)) * a
        pan L, R, d, (k - (notes.length - 1) / 2) * 0.4, 1 / notes.length
  # 風: 150~900Hz 帶通雜訊, 慢速起伏, 左右以位移去相關
  synth.wind = (o = {}) ->
    dur = o.dur or 6
    make dur, (L, R, n) ->
      r = rng(o.seed or 17)
      d = biquad biquad(noise(n, r), \hp, 150), \lp, (o.cutoff or 900)
      lag = 2400
      for i from 0 til n
        t = i / SR
        a = (0.6 + 0.4 * Math.sin(2 * Math.PI * 0.13 * t) * Math.sin(2 * Math.PI * 0.071 * t + 1)) * Math.min(1, t, dur - t)
        L[i] = d[i] * a
        R[i] = d[(i + lag) % n] * a
  # 雨: 稀疏的高頻顆粒 + 底噪
  synth.rain = (o = {}) ->
    dur = o.dur or 6; density = o.density or 0.02
    make dur, (L, R, n) ->
      r = rng(o.seed or 19)
      bed = biquad noise(n, r), \bp, 4000, 0.5
      grains = new Float32Array n
      for i from 0 til n => if r! < density * 0.05 => grains[i] = r! * 2 - 1
      grains = biquad biquad(grains, \hp, 2500), \lp, 9000
      for i from 0 til n
        a = Math.min(1, i / SR, (n - i) / SR)
        L[i] = (bed[i] * 0.15 + grains[i] * 3) * a
        R[i] = (bed[(i + 1200) % n] * 0.15 + grains[(i + 777) % n] * 3) * a
  # 昆蟲振翅 ( 蜜蜂 ): 鋸齒波 + 翅拍調幅 + 低通, 音高微幅晃動
  synth.buzz = (o = {}) ->
    dur = o.dur or 1.5; f = S.freq(o.freq or 220)
    make dur, (L, R, n) ->
      d = new Float32Array n; ph = 0
      for i from 0 til n
        t = i / SR
        ff = f * (1 + 0.03 * Math.sin(2 * Math.PI * 5.3 * t) + 0.015 * Math.sin(2 * Math.PI * 1.7 * t))
        ph += ff / SR
        saw = 2 * (ph - Math.floor(ph + 0.5))
        d[i] = saw * (0.75 + 0.25 * Math.sin(2 * Math.PI * ff * 0.5 * t)) * Math.min(1, t / 0.08, (dur - t) / 0.15)
      biquad d, \lp, 2200
      biquad d, \bp, f * 3, 0.6
      pan L, R, d, o.pan
  # 上升的雜訊 ( 段落前的醞釀 )
  synth.swell = (o = {}) ->
    dur = o.dur or 2
    make dur, (L, R, n) ->
      r = rng(o.seed or 23)
      nz = noise n, r
      seg = 512
      for s from 0 til n by seg
        u = s / n
        part = biquad nz.slice(s, s + seg), \bp, 300 + 3000 * u * u, 0.9
        for i from 0 til part.length => L[s + i] = R[s + i] = part[i] * u * u
  # 簡單旋律: notes [[t, note, dur?, vel?]] 以撥弦演奏
  synth.melody = (o = {}) ->
    seq = o.notes or []
    dur = o.dur or (Math.max(...seq.map((x) -> x.0 + (x.2 or 1.5))) + 1)
    voices = seq.map (x, k) -> [x, synth.pluck({note: x.1, dur: (x.2 or 1.5) + 0.8, bright: o.bright, slide: o.slide, seed: 31 + k})]
    make dur, (L, R, n) ->
      for [[t, note, d, vel], b] in voices
        l = b.getChannelData 0; r_ = b.getChannelData 1
        o0 = Math.round t * SR
        for i from 0 til Math.min(l.length, n - o0) => L[o0 + i] += l[i] * (vel or 0.8); R[o0 + i] += r_[i] * (vel or 0.8)

  if typeof(module) != \undefined and module.exports => module.exports = S
  if typeof(window) != \undefined => window.sfx = S
