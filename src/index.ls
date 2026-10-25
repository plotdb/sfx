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
    v = {name, media: a, gain: g, level, ended: false, timers: []}
    go = ->
      if v.ended => return
      seek-then-play = -> a.currentTime = opt.offset or 0; a.play!catch(->)
      if a.readyState >= 1 => seek-then-play! else a.addEventListener \loadedmetadata, seek-then-play, {once: true}
    delay = Math.max 0, when_ - c.currentTime
    v.timers.push setTimeout(go, delay * 1000)
    # 結束時間 ( 停止、淡出 ) 從真正發聲 ( playing ) 才開始算: go 之後還要等載入、跳轉、play, 常有數百毫秒到一秒以上;
    # 若照排程時間算, 結尾會被切掉同樣長度. 播到檔案結尾的不另外停 ( 交給 onended ), 只有循環或刻意截短的才排停止
    if opt.duration?
      buf = S.buffers[name]
      offset = opt.offset or 0
      to-end = !a.loop and buf and offset + opt.duration * a.playbackRate >= buf.duration - 0.02
      a.addEventListener \playing, (->
        if v.ended => return
        left = Math.max 0, opt.duration - (a.currentTime - offset) / a.playbackRate
        now = c.currentTime
        if opt.fadeOut
          g.gain.setValueAtTime level, Math.max(now, now + left - opt.fadeOut)
          g.gain.linearRampToValueAtTime 0, now + left
        if !to-end => v.timers.push setTimeout((-> stop-voice v, 0.02), left * 1000)
      ), {once: true}
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

  # 變化: 由 h1, h2 ( 0~1 ) 算出音高 ( vary 1 約 ±1 個半音 ) 與音量 ( 最多小 30% ) 的微調
  jitter = (vary, h1, h2) -> {rate: Math.pow(2, (h1 * 2 - 1) * vary / 12), gain: 1 - vary * 0.3 * h2}

  # 指令式播放: 回傳 handle {stop(fade), fade(to, dur)}
  #  - name 可以是陣列: 每次隨機挑一個 ( 例如幾種腳步聲輪流 )
  #  - vary ( 0~1 ): 每次播放的音高與音量略有不同 ( 隨機, 不可重現; 時間軸上的是可重現的 )
  S.play = (name, opt = {}) ->
    S.resume!
    if Array.isArray(name) => name = name[Math.floor(Math.random! * name.length)]
    if opt.vary
      j = jitter opt.vary, Math.random!, Math.random!
      opt = {} <<< opt <<< {rate: (opt.rate or 1) * j.rate, gain: (if opt.gain? => opt.gain else 1) * j.gain}
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
  #  - sound 可以是陣列: 依項目的位置與時間挑一個 ( 可重現, 拖曳、重播、離線混音都一樣 )
  #  - vary ( 0~1 ): 每個項目的音高與音量略有不同 ( 同樣可重現 )
  S.timeline = (items = []) ->
    S.items = items.map (it, k) ->
      it = {} <<< it
      if Array.isArray(it.sound) or it.vary
        h = rng(((k + 1) * 2654435761 .^. Math.round((it.t or 0) * 1000) * 40503) .>>>. 0)
        h!
        if Array.isArray(it.sound) => it.sound = it.sound[Math.floor(h! * it.sound.length)]
        if it.vary
          j = jitter it.vary, h!, h!
          it.rate = (it.rate or 1) * j.rate
          it.gain = (if it.gain? => it.gain else 1) * j.gain
      it
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
    # lotion 0.9 起所有跳轉 ( seek、循環區段接回 ) 都經過 _seek; 較舊的版本只有 seek
    sk = if P._seek => \_seek else \seek
    seek = P[sk]
    P.play = (go = true) ->
      r = play.apply @, arguments
      if !S.external => S.transport {playing: @playing, t: @t}
      r
    P[sk] = (t) ->
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

  # 二階濾波 ( RBJ biquad ) 的係數
  coef = (type, f, q) ->
    w = 2 * Math.PI * Math.min(f, SR * 0.49) / SR
    cs = Math.cos w; al = Math.sin(w) / (2 * q)
    switch type
    | \lp => [(1 - cs) / 2, 1 - cs, (1 - cs) / 2, 1 + al, -2 * cs, 1 - al]
    | \hp => [(1 + cs) / 2, -(1 + cs), (1 + cs) / 2, 1 + al, -2 * cs, 1 - al]
    | otherwise => [al, 0, -al, 1 + al, -2 * cs, 1 - al]

  # 二階濾波, 對 Float32Array 原地處理
  biquad = (d, type, f, q = 0.707) ->
    [b0, b1, b2, a0, a1, a2] = coef type, f, q
    x1 = x2 = y1 = y2 = 0
    for i from 0 til d.length
      x = d[i]
      y = (b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2) / a0
      x2 = x1; x1 = x; y2 = y1; y1 = y
      d[i] = y
    d

  # 時變的二階濾波: 頻率 fc(u) ( u: 0~1 為進度 ) 每 32 個樣本更新一次係數, 濾波狀態連續 ( 段落之間不會有接縫雜音 )
  biquad-tv = (d, type, fc, q = 0.707) ->
    n = d.length
    x1 = x2 = y1 = y2 = 0
    for s from 0 til n by 32
      [b0, b1, b2, a0, a1, a2] = coef type, fc(s / n), q
      for i from s til Math.min(n, s + 32)
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
      d = biquad-tv noise(n, r), \bp, ((u) -> if u < at => f0 + (f1 - f0) * (u / at) else f1 + (f2 - f1) * ((u - at) / (1 - at))), q
      # 音量包絡: 在 at 處最大
      for i from 0 til n
        v = i / n
        d[i] *= if v < at => Math.sin(Math.PI / 2 * v / at) else Math.cos(Math.PI / 2 * (v - at) / (1 - at))
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
    f = S.freq(o.note or 'A3'); dur = o.dur or 2.5
    # 注意: 同一行的 `if ... else x; y = ...` 會把 y 吞進 else, 要分行寫
    bright = if o.bright? => o.bright else 0.6
    slide = if o.slide? => o.slide else 0.6
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
      d = biquad-tv noise(n, r), \bp, ((u) -> 300 + 3000 * u * u), 0.9
      for i from 0 til n => u = i / n; L[i] = R[i] = d[i] * u * u
  # 簡單旋律: notes [[t, note, dur?, vel?]], instrument 為任一有 note 參數的合成聲 ( 預設 pluck 撥弦 )
  #  - release: 每個音在 dur 之後保留的尾音 ( 秒, 預設 0.8 ); 要聽得出音長時設小一點 ( 例如 0.1 )
  synth.melody = (o = {}) ->
    seq = o.notes or []
    rel = if o.release? => o.release else 0.8
    dur = o.dur or (Math.max(...seq.map((x) -> x.0 + (x.2 or 1.5))) + 1)
    inst = o.instrument or \pluck
    if !synth[inst] => inst = \pluck
    voices = seq.map (x, k) ->
      opt = if inst == \pluck => {bright: o.bright, slide: o.slide} else {}
      [x, synth[inst]({note: x.1, dur: (x.2 or 1.5) + rel, seed: 31 + k} <<< opt)]
    make dur, (L, R, n) ->
      for [[t, note, d, vel], b] in voices => place L, R, b, t, (vel or 0.8)

  # ---------------------------------------------------------------- 共用的小工具
  # 把 AudioBuffer 疊進 L / R ( 從 t 秒開始, 乘上 g )
  place = (L, R, b, t, g = 1) ->
    l = b.getChannelData 0; r_ = b.getChannelData 1
    o0 = Math.round t * SR
    for i from Math.max(0, -o0) til Math.min(l.length, L.length - o0) => L[o0 + i] += l[i] * g; R[o0 + i] += r_[i] * g

  # 疊一個衰減的正弦 ( 泛音 ): at 秒開始, 頻率 f, 振幅 amp, 衰減時間常數 dec, 起音 att
  partial = (d, at, f, amp, dec, att = 0.001) ->
    if f >= SR * 0.45 => return d
    o0 = Math.round at * SR
    w = 2 * Math.PI * f / SR
    for i from Math.max(0, o0) til d.length
      k = i - o0; t = k / SR
      a = amp * env(t, att, dec)
      if t > att and a < 1e-5 => break
      d[i] += a * Math.sin(w * k)
    d

  # 結尾淡出 ( 避免截斷的爆音 )
  fade-out = (d, sec = 0.02) ->
    m = Math.min d.length, Math.round(sec * SR)
    for i from 0 til m => d[d.length - 1 - i] *= i / m
    d

  # 平滑的隨機曲線 ( 0~1 ), 每 every 秒一個控制點, 線性內插
  wander = (n, every, r) ->
    step = Math.max 1, Math.round(every * SR)
    pts = [r! for k from 0 to Math.ceil(n / step) + 1]
    d = new Float32Array n
    for i from 0 til n
      k = Math.floor(i / step); u = (i % step) / step
      d[i] = pts[k] * (1 - u) + pts[k + 1] * u
    d

  # 正弦掃頻 ( 指數曲線 ): f(u) 由 f0 到 f1
  glide-osc = (n, f0, f1, harm = [1]) ->
    d = new Float32Array n; ph = 0
    for i from 0 til n
      ph += 2 * Math.PI * f0 * Math.pow(f1 / f0, i / n) / SR
      for a, k in harm => d[i] += a * Math.sin(ph * (k + 1))
    d

  # ---------------------------------------------------------------- 殘響 ( Freeverb: 8 個梳狀濾波 + 4 個全通濾波 )
  COMB = [1116 1188 1277 1356 1422 1491 1557 1617]
  ALLPASS = [556 441 341 225]
  reverb = (buf, mix = 0.3, room = 0.5) ->
    k = SR / 44100
    src = [buf.getChannelData(0), buf.getChannelData(1)]
    m = buf.length
    make buf.duration + 0.4 + room * 3, (L, R, n) ->
      fb = 0.7 + 0.27 * room; damp = 0.3
      input = new Float32Array n
      for i from 0 til m => input[i] = (src.0[i] + src.1[i]) * 0.015
      for out, ch in [L, R]
        wet = new Float32Array n
        for c in COMB
          len = Math.round((c + ch * 23) * k); line = new Float32Array len; idx = 0; filt = 0
          for i from 0 til n
            y = line[idx]
            filt = y * (1 - damp) + filt * damp
            line[idx] = input[i] + filt * fb
            idx = (idx + 1) % len
            wet[i] += y
        for c in ALLPASS
          len = Math.round((c + ch * 23) * k); line = new Float32Array len; idx = 0
          for i from 0 til n
            b = line[idx]; v = wet[i]
            line[idx] = v + b * 0.5
            wet[i] = b - v
            idx = (idx + 1) % len
        dry = src[ch]
        for i from 0 til n => out[i] = (if i < m => dry[i] * (1 - mix * 0.5) else 0) + wet[i] * mix * 3
  S.reverb = (buf, o = {}) -> reverb buf, (if o.mix? => o.mix else 0.3), (if o.room? => o.room else 0.5)

  # ---------------------------------------------------------------- 動作音
  # 滑入 / 滑出: 帶通雜訊由 from 掃到 to, 左右跟著 dir ( 1 往右, -1 往左 ) 移動
  synth.slide = (o = {}) ->
    dur = o.dur or 0.3; f0 = o.from or 900; f1 = o.to or 2600; q = o.q or 0.9
    dir = if o.dir? => o.dir else 1
    make dur, (L, R, n) ->
      d = biquad-tv noise(n, rng(o.seed or 37)), \bp, ((u) -> f0 * Math.pow(f1 / f0, u)), q
      for i from 0 til n
        u = i / n
        a = if u < 0.25 => Math.sin(Math.PI / 2 * u / 0.25) else Math.pow(Math.cos(Math.PI / 2 * (u - 0.25) / 0.75), 2)
        p = (u * 2 - 1) * 0.6 * dir
        L[i] = d[i] * a * Math.cos((p + 1) * Math.PI / 4)
        R[i] = d[i] * a * Math.sin((p + 1) * Math.PI / 4)
  # 音高滑動 ( 數值上升 / 下降 )
  glide = (o, d0, d1) ->
    dur = o.dur or 0.6; f0 = S.freq(o.from or d0); f1 = S.freq(o.to or d1)
    make dur, (L, R, n) ->
      d = glide-osc n, f0, f1, [1, 0.25, 0.08]
      for i from 0 til n
        t = i / SR
        d[i] *= Math.min(1, t / 0.02) * Math.min(1, (dur - t) / (dur * 0.35))
      pan L, R, d, o.pan
  synth.rise = (o = {}) -> glide o, 300, 900
  synth.fall = (o = {}) -> glide o, 900, 250
  # 數字滾動: n 個 tick, 音高爬升 climb 個半音; ease: out ( 越來越慢 ) | in | linear; 最後一下加重
  synth.count = (o = {}) ->
    cnt = Math.max 2, (o.n or 12); dur = o.dur or 1.2; f = S.freq(o.note or 'C6')
    climb = if o.climb? => o.climb else 7
    ease = switch o.ease
    | \in => (u) -> u * u
    | \linear => (u) -> u
    | otherwise => (u) -> 1 - (1 - u) * (1 - u)
    make dur + 0.2, (L, R, n) ->
      d = new Float32Array n
      for k from 0 til cnt
        u = k / (cnt - 1)
        last = k == cnt - 1
        ff = f * Math.pow(2, climb * u / 12)
        partial d, dur * ease(u), ff, (if last => 1 else 0.6), (if last => 0.09 else 0.02)
        if last => partial d, dur, ff * 2, 0.3, 0.06
      pan L, R, d, o.pan
  # 吸附、到位
  synth.snap = (o = {}) -> make 0.1, (L, R, n) ->
    nz = biquad noise(n, rng(o.seed or 41)), \lp, 6000
    d = new Float32Array n
    for i from 0 til n
      t = i / SR
      d[i] = 0.8 * nz[i] * env(t, 0.0003, 0.002) + 0.6 * Math.sin(2 * Math.PI * 1400 * t) * env(t, 0.0005, 0.01) + Math.sin(2 * Math.PI * 160 * t) * env(t, 0.001, 0.025)
    pan L, R, d, o.pan
  # 筆畫: 帶通雜訊, 力道隨機起伏; rough 越大顆粒越明顯; pitch 為筆尖的音色 ( Hz )
  synth.draw = (o = {}) ->
    dur = o.dur or 1; rough = if o.rough? => o.rough else 0.5
    make dur, (L, R, n) ->
      r = rng(o.seed or 43)
      d = biquad biquad(noise(n, r), \bp, (o.pitch or 2500), 0.8), \hp, 600
      speed = wander n, 0.06, r
      grain = wander n, 0.004, r
      for i from 0 til n
        t = i / SR
        g = grain[i] * grain[i]
        d[i] *= (0.3 + 0.7 * speed[i]) * (1 - rough + rough * g * 2) * Math.min(1, t / 0.03, (dur - t) / 0.05)
      pan L, R, d, o.pan
  # 故障: 一段段隨機的方波 / 降取樣雜訊 / 靜音
  synth.glitch = (o = {}) ->
    dur = o.dur or 0.5
    make dur, (L, R, n) ->
      r = rng(o.seed or 47)
      i = 0
      while i < n
        len = Math.round((0.015 + 0.05 * r!) * SR)
        kind = r!
        f = 100 + 1900 * r! * r!
        hold = 1 + Math.floor(r! * 40)
        p = r! * 1.6 - 0.8
        gl = Math.cos((p + 1) * Math.PI / 4); gr = Math.sin((p + 1) * Math.PI / 4)
        v = 0
        for j from i til Math.min(n, i + len)
          t = (j - i) / SR
          x = if kind < 0.4 => (if Math.sin(2 * Math.PI * f * t) > 0 => 0.6 else -0.6)
          else if kind < 0.8 => (if (j - i) % hold == 0 => v = r! * 2 - 1 else v)
          else 0
          L[j] = x * gl; R[j] = x * gr
        i += len

  # ---------------------------------------------------------------- 敘事
  # 揭曉: 快速上行的鐘琴琶音 + 高頻閃光 ( 預設帶殘響 )
  synth.reveal = (o = {}) ->
    notes = (o.notes or <[C6 E6 G6 C7 E7]>).map S.freq
    gap = if o.gap? => o.gap else 0.06
    make 1.6, (L, R, n) ->
      d = new Float32Array n
      for f, k in notes
        partial d, k * gap, f, 1, 0.5
        partial d, k * gap, f * 2.76, 0.25, 0.15
      sh = biquad noise(n, rng(o.seed or 53)), \hp, 6000
      for i from 0 til n
        t = i / SR
        d[i] += sh[i] * 0.12 * env(t, 0.25, 0.3)
      pan L, R, d, o.pan
  synth.reveal.reverb = 0.35
  # 錯誤: 兩個往下的柔和方波音 ( 預設三全音 )
  synth.error = (o = {}) ->
    notes = [S.freq(o.from or 'B3'), S.freq(o.to or 'F3')]
    make 0.5, (L, R, n) ->
      d = new Float32Array n
      for f, k in notes
        for h from 1 to 7 by 2 => partial d, k * 0.16, f * h, 1 / h, 0.12, 0.005
      fade-out biquad(d, \lp, 2000)
      pan L, R, d, o.pan
  # 緊張: 小二度與三全音的音簇, 顫音漸快, 漸強
  synth.tension = (o = {}) ->
    dur = o.dur or 6; f = S.freq(o.note or 'A2')
    make dur, (L, R, n) ->
      for ratio, k in [1, Math.pow(2, 1 / 12), Math.pow(2, 6 / 12), 2]
        d = new Float32Array n; ph = 0; tp = 0
        for i from 0 til n
          t = i / SR; u = t / dur
          tp += 2 * Math.PI * (3 + 5 * u) / SR
          ph += 2 * Math.PI * f * ratio / SR
          d[i] = (Math.sin(ph) + 0.3 * Math.sin(ph * 2) + 0.15 * Math.sin(ph * 3)) * (1 - 0.35 * (0.5 + 0.5 * Math.sin(tp + k))) * Math.pow(u, 1.5) * Math.min(1, (dur - t) / 0.3)
        pan L, R, d, (k - 1.5) * 0.4, 0.5
  # 心跳: bpm, 每拍 lub-dub
  synth.heartbeat = (o = {}) ->
    dur = o.dur or 4; period = 60 / (o.bpm or 70)
    make dur, (L, R, n) ->
      d = new Float32Array n
      t = 0.05
      while t < dur - 0.2
        for [at, f0, f1, a] in [[0, 75, 45, 1], [Math.min(0.3, period * 0.35), 85, 55, 0.7]]
          m = Math.round(0.25 * SR); o0 = Math.round((t + at) * SR)
          b = glide-osc m, f0, f1
          for i from 0 til Math.min(m, n - o0) => d[o0 + i] += b[i] * a * env(i / SR, 0.008, 0.06)
        t += period
      pan L, R, biquad(d, \lp, 300), o.pan
  # 時鐘: bpm, tick / tock 交替
  synth.clock = (o = {}) ->
    dur = o.dur or 4; period = 60 / (o.bpm or 60)
    make dur, (L, R, n) ->
      d = new Float32Array n
      nz = biquad noise(n, rng(o.seed or 59)), \hp, 2000
      k = 0; t = 0.02
      while t < dur - 0.05
        f = if k % 2 => 2400 else 3200
        partial d, t, f, 0.6, 0.012
        partial d, t, f * 1.5, 0.3, 0.006
        o0 = Math.round t * SR
        for i from 0 til Math.min(Math.round(0.002 * SR), n - o0) => d[o0 + i] += nz[o0 + i] * 0.8
        t += period; k++
      pan L, R, d, o.pan

  # ---------------------------------------------------------------- 擬音
  # 一顆短促的顆粒 ( 劈啪 / 碎石 ): 長度 len 秒的雜訊, 帶通 fc, 指數衰減, 疊進 L / R
  grain = (L, R, r, at, len, fc, q, amp, p = 0) ->
    m = Math.max 4, Math.round(len * SR)
    g = noise m, r
    biquad g, \bp, fc, q
    o0 = Math.round at * SR
    gl = Math.cos((p + 1) * Math.PI / 4) * amp; gr = Math.sin((p + 1) * Math.PI / 4) * amp
    for i from 0 til Math.min(m, L.length - o0)
      e = Math.exp(-4 * i / m) * Math.min(1, i / 8)
      L[o0 + i] += g[i] * e * gl; R[o0 + i] += g[i] * e * gr
  # 依權重函式 w(u) ( u: 0~1 ) 抽一個時間點 ( 拒絕取樣 )
  pick = (r, w) ->
    for k from 0 til 50
      u = r!
      if r! < w(u) => return u
    r!

  # 翻頁 ( 依三段錄音約 10 次翻頁的分析: 250Hz~6kHz 大致平坦, 8kHz 以上滾降; 音量有不規則的起伏 ( 紙張抖動 ) )
  #  - 掀起: 手指拖過紙緣, 偏高頻的小聲摩擦
  #  - 翻動: 寬頻的粉紅雜訊, 8~25Hz 的不規則抖動, 彎折時的劈啪聲
  #  - 落下: 柔和的寬頻拍擊, 再慢慢收掉
  #  - crisp: 劈啪聲的多寡 ( 0 柔軟的紙 ~ 3 硬挺的紙 ); flutter: 抖動的程度 ( 0~1 )
  synth.paper = (o = {}) ->
    dur = o.dur or 1.2
    crisp = if o.crisp? => o.crisp else 1
    flutter = if o.flutter? => o.flutter else 0.6
    lift = dur * 0.2; land = dur * 0.8
    make dur, (L, R, n) ->
      r = rng(o.seed or 61)
      # 翻動的音量: 漸強到 land, 中間有抖動
      flip = (t) -> if t < lift * 0.5 or t > land + 0.02 => 0 else Math.pow(Math.min(1, (t - lift * 0.5) / (land - lift * 0.5)), 0.7)
      fl = wander n, 0.035, r
      fl2 = wander n, 0.09, r
      for ch, c in [L, R]
        p = pink n, r
        sl = biquad noise(n, r), \bp, 4000, 0.7
        for i from 0 til n
          t = i / SR
          shake = 1 - flutter + flutter * (fl[i] * 0.7 + fl2[i] * 0.6)
          a = flip(t) * shake
          # 掀起的摩擦
          s = if t < lift => Math.sin(Math.PI / 2 * t / lift) * 0.25 else if t < land => 0.25 * Math.max(0, 1 - (t - lift) / (lift)) else 0
          # 落下: 拍擊 + 收尾
          d = if t >= land => env(t - land, 0.006, 0.07) * 1.1 + 0.25 * Math.max(0, 1 - (t - land) / (dur - land)) else 0
          ch[i] = p[i] * (a * 0.8 + d) + sl[i] * s
      # 彎折的劈啪聲 ( 翻動期間 )
      for k from 0 til Math.round(50 * dur * crisp)
        t = lift * 0.5 + (land - lift * 0.5) * pick(r, (u) -> 0.3 + 0.7 * u)
        grain L, R, r, t, 0.0002 + 0.0008 * r!, 1500 * Math.pow(5, r!), 0.5, (0.1 + r! * r!) * 8, r! * 0.6 - 0.3
      for ch in [L, R]
        biquad ch, \hp, 150
        biquad ch, \lp, 7500, 0.6
        fade-out ch, 0.05
  # 水: 氣泡模型 ( van den Doel ): 半徑 r mm 的氣泡音高 f0 = 3000 / r Hz, 衰減 d = 0.043 f0 + 0.0014 f0^1.5 ( 1/秒 ),
  # 音高隨時間上升 f = f0 ( 1 + rise · d · t ). 一顆是水滴, 大量大小不一的氣泡是溪流 / 冒泡
  #  - n: 氣泡數 ( 1 為水滴 ), size: 平均半徑 ( mm, 越大越低 ), rise: 音高上升的程度
  #  - 水滴依錄音調整: 音高幾乎不滑 ( rise 0.05 ), 容器的共鳴讓尾音較長 ( 衰減只有公式的一半 )
  bubble = (L, R, at, radius, amp, rise, p, damp = 1) ->
    f0 = 3000 / radius
    d = (0.043 * f0 + 0.0014 * Math.pow(f0, 1.5)) * damp
    m = Math.min Math.round(6 / d * SR), L.length - Math.round(at * SR)
    o0 = Math.round at * SR
    gl = Math.cos((p + 1) * Math.PI / 4) * amp; gr = Math.sin((p + 1) * Math.PI / 4) * amp
    ph = 0
    for i from 0 til m
      t = i / SR
      ph += 2 * Math.PI * f0 * (1 + rise * d * t) / SR
      v = Math.sin(ph) * Math.exp(-d * t) * Math.min(1, i / 24)
      L[o0 + i] += v * gl; R[o0 + i] += v * gr
  synth.water = (o = {}) ->
    cnt = o.n or 1; rise = if o.rise? => o.rise else (if cnt == 1 => 0.05 else 0.1)
    size = o.size or (if o.freq => 3000 / S.freq(o.freq) else (if cnt == 1 => 3 else 2.5))
    dur = o.dur or (if cnt == 1 => 0.4 else Math.max(1, cnt * 0.04))
    make dur, (L, R, n) ->
      r = rng(o.seed or 67)
      if cnt == 1
        # 水滴: 落水的輕微撞擊, 接著一顆氣泡
        grain L, R, r, 0.005, 0.001, 3000, 0.8, 0.25
        bubble L, R, 0.007, size, 1, rise, 0, 0.4
        bubble L, R, 0.012, size * 0.4, 0.12, rise, 0.1
        return
      for k from 0 til cnt
        # 小氣泡多、大氣泡少
        radius = size * (0.25 + 1.75 * Math.pow(r!, 2.5))
        at = r! * (dur - 0.1)
        bubble L, R, at, radius, Math.pow(radius / size, 0.7) * (0.3 + 0.7 * r!), rise * (0.5 + r!), r! * 1.4 - 0.7
  # 火: 低沉起伏的底噪 + 隨機的劈啪聲; density 劈啪的多寡
  synth.fire = (o = {}) ->
    dur = o.dur or 6; density = if o.density? => o.density else 1
    make dur, (L, R, n) ->
      r = rng(o.seed or 71)
      bed = biquad noise(n, r), \lp, 300
      hiss = biquad noise(n, r), \hp, 3000
      sw = wander n, 0.25, r
      for i from 0 til n
        a = (0.4 + 0.6 * sw[i]) * Math.min(1, i / SR / 0.3, (n - i) / SR / 0.3)
        L[i] = R[i] = (bed[i] * 0.5 + hiss[i] * 0.04) * a
      cnt = Math.round(dur * 10 * density)
      for k from 0 til cnt
        at = Math.round(r! * (n - 0.01 * SR)); amp = r! * r! * 1.5
        len = Math.round((0.0005 + 0.003 * r!) * SR)
        p = r! * 1.6 - 0.8
        gl = Math.cos((p + 1) * Math.PI / 4); gr = Math.sin((p + 1) * Math.PI / 4)
        for i from 0 til len
          v = (r! * 2 - 1) * amp * (1 - i / len)
          L[at + i] += v * gl; R[at + i] += v * gr
  # 腳步: 每一步 = 腳跟落地, 隨後腳尖落地
  #  - surface: wood ( 木地板 ) | concrete ( 水泥 / 磁磚 ) | gravel ( 碎石 ) | snow ( 雪 ) | grass ( 草地 )
  #  - gait: walk ( 走, 腳跟 → 約 0.1 秒後腳尖 ) | run ( 跑, 前腳掌先著地, 兩下幾乎重疊, 較重, 蹬地時有摩擦 )
  #  - n 步, 間隔 pace 秒 ( 走預設 0.5, 跑預設 0.3 ); 左右腳略微左右分開
  #  - 水泥依錄音調整: 極短 ( 約 10ms 衰減 20dB ) 的中頻「喀」, 能量在 400~1400Hz, 幾乎沒有低頻
  SURFACE =
    wood: {thud: 1, tones: [140 380 620], click: [[2200, 1.2, 0.012, 0.5]]}
    concrete: {thud: 0.04, tones: [], click: [[700, 0.8, 0.003, 1.6], [2600, 1.2, 0.002, 0.15]], scuff: 0.06}
    gravel: {thud: 0.45, grains: 90, band: [1200, 6000], len: [0.0004, 0.002], q: 1.5}
    snow: {thud: 0.35, grains: 70, band: [500, 2200], len: [0.002, 0.007], q: 0.8}
    grass: {thud: 0.25, grains: 90, band: [2500, 8000], len: [0.0005, 0.003], q: 1.2}
  synth.steps = (o = {}) ->
    run = o.gait == \run
    cnt = o.n or 4; pace = o.pace or (if run => 0.3 else 0.5)
    sf = SURFACE[o.surface] or SURFACE.wood
    make cnt * pace + 0.35, (L, R, n) ->
      r = rng(o.seed or 73)
      lp = biquad noise(n, r), \lp, 260
      for k from 0 til cnt
        T = 0.02 + k * pace + (r! - 0.5) * (if run => 0.01 else 0.02)
        w = (if run => 1.15 else 0.85) + 0.3 * r!
        p = if k % 2 => 0.12 else -0.12
        gl = Math.cos((p + 1) * Math.PI / 4); gr = Math.sin((p + 1) * Math.PI / 4)
        toe = if run => 0.025 + 0.015 * r! else 0.09 + 0.04 * r!
        for [at, a] in (if run => [[0, w * 0.8], [toe, w]] else [[0, w], [toe, w * 0.55]])
          o0 = Math.round((T + at) * SR)
          m = Math.min Math.round(0.15 * SR), n - o0
          d = new Float32Array m
          for i from 0 til m
            t = i / SR
            d[i] = lp[o0 + i] * 2.5 * sf.thud * env(t, 0.003, 0.025) + 0.5 * sf.thud * Math.sin(2 * Math.PI * (75 + 20 * a) * t) * env(t, 0.002, 0.03)
          for f in (sf.tones or []) => partial d, 0, f * (0.95 + 0.1 * r!), 0.12, 0.035
          for [fc, q, dec, amp] in (sf.click or [])
            c = biquad noise(m, r), \bp, fc * (0.85 + 0.3 * r!), q
            for i from 0 til m => d[i] += c[i] * amp * env(i / SR, 0.0004, dec)
          for i from 0 til m => L[o0 + i] += d[i] * a * gl; R[o0 + i] += d[i] * a * gr
        # 鞋底與地面的摩擦 ( 跑步時在蹬地處, 較明顯 )
        sc = (sf.scuff or 0.1) * (if run => 2.5 else 1)
        if sf.scuff or run
          o0 = Math.round((T + (if run => toe + 0.03 else 0.02)) * SR)
          s = biquad noise(Math.round((if run => 0.07 else 0.12) * SR), r), \bp, 2800, 0.8
          for i from 0 til Math.min(s.length, n - o0)
            e = Math.sin(Math.PI * i / s.length) * sc * w * 0.3
            L[o0 + i] += s[i] * e * gl; R[o0 + i] += s[i] * e * gr
        # 顆粒地面: 踩下時一顆顆的嘎吱聲, 集中在腳跟與腳尖兩處
        if sf.grains
          for j from 0 til Math.round(sf.grains * w)
            at = if r! < 0.6 => 0.07 * Math.pow(r!, 1.5) else toe + 0.09 * Math.pow(r!, 1.5)
            [f0, f1] = sf.band; [l0, l1] = sf.len
            grain L, R, r, T + at, l0 + (l1 - l0) * r!, f0 * Math.pow(f1 / f0, r!), sf.q, (0.15 + r! * r!) * 0.8 * w, p + r! * 0.3 - 0.15
  # 鐘 ( 教堂鐘 / 管鐘 ): 不諧和的泛音, 低音 hum 留得最久; note 為敲擊音
  synth.bell = (o = {}) ->
    f = S.freq(o.note or 'C5'); dur = o.dur or 5
    make dur, (L, R, n) ->
      d = new Float32Array n
      for [ratio, amp, dec] in [[0.5 0.5 1] [1 1 0.7] [1.2 0.55 0.5] [1.5 0.35 0.4] [2 0.6 0.35] [2.51 0.25 0.25] [2.66 0.2 0.22] [3.01 0.18 0.18] [4.17 0.1 0.12] [5.43 0.06 0.08]]
        partial d, 0, f * ratio, amp, dec * dur * 0.45, 0.002
        partial d, 0, f * ratio * 1.0015, amp * 0.5, dec * dur * 0.45, 0.002
      pan L, R, fade-out(d, 0.1), o.pan
  synth.bell.reverb = 0.2
  # 粉紅雜訊 ( 每八度能量相同; Paul Kellet 的濾波 )
  pink = (n, r) ->
    d = new Float32Array n
    b0 = b1 = b2 = b3 = b4 = b5 = b6 = 0
    for i from 0 til n
      w = r! * 2 - 1
      b0 = 0.99886 * b0 + w * 0.0555179; b1 = 0.99332 * b1 + w * 0.0750759; b2 = 0.969 * b2 + w * 0.153852
      b3 = 0.8665 * b3 + w * 0.3104856; b4 = 0.55 * b4 + w * 0.5329522; b5 = -0.7616 * b5 - w * 0.016898
      d[i] = (b0 + b1 + b2 + b3 + b4 + b5 + b6 + w * 0.5362) * 0.11
      b6 = w * 0.115926
    d
  # 雷 ( 依錄音分析: 近雷是 50Hz~8kHz 的寬頻撕裂聲, 接著數秒起伏的隆隆聲; 遠雷只剩 500Hz 以下 )
  #  - dist: 0 ( 近 ) ~ 1 ( 遠 )
  synth.thunder = (o = {}) ->
    dur = o.dur or 6; dist = if o.dist? => o.dist else 0.5
    near = 1 - dist
    make dur, (L, R, n) ->
      r = rng(o.seed or 79)
      # 撕裂: 開頭幾次快速的爆發 ( 越近越多 ); 隆隆: 之後幾次緩慢的起伏
      t0 = 0.02 + dist * 0.4
      cracks = [[t0, 1]] ++ [[t0 + 0.7 * Math.pow(r!, 1.5), 0.4 + 0.6 * r!] for k from 0 til Math.round(2 + 5 * near)]
      rolls = [[t0 + 0.3 + r! * dur * 0.5, 0.3 + 0.7 * r!] for k from 0 til 5]
      ca = new Float32Array n; ra = new Float32Array n
      for i from 0 til n
        t = i / SR
        for [at, g] in cracks => if t > at => ca[i] += g * env(t - at, 0.004, 0.1 + 0.25 * dist)
        for [at, g] in rolls => if t > at => ra[i] += g * env(t - at, 0.15 + 0.4 * dist, 0.7 + dist)
        fo = Math.min(1, (dur - t) / 0.6)
        ca[i] *= fo; ra[i] *= fo
      lpf = 400 + 11000 * near * near
      for ch in [L, R]
        p = biquad biquad(pink(n, r), \lp, lpf), \hp, 30
        b = biquad biquad(noise(n, r), \lp, 140), \lp, 140
        for i from 0 til n
          ch[i] = p[i] * (ca[i] * (0.4 + 0.6 * near) + ra[i] * 0.8 * near) + b[i] * ra[i] * (0.6 + 0.4 * dist) * 3 + b[i] * ca[i] * 2
      # 近雷的劈啪聲
      for k from 0 til Math.round(300 * near * near)
        at = t0 + 1.2 * Math.pow(r!, 2)
        grain L, R, r, at, 0.0003 + 0.002 * r!, 800 + 5000 * r!, 1, (0.1 + r! * r!) * near * 0.8, r! * 1.4 - 0.7

  # ---------------------------------------------------------------- 人體與人聲
  # 響指 ( 依錄音分析: 1ms 內衰減 10dB 的爆裂, 手掌共鳴約 3.2kHz, 能量在 3~8kHz; 手指打到掌心有一點 200Hz 的悶聲 )
  synth.fingersnap = (o = {}) -> make 0.12, (L, R, n) ->
    r = rng(o.seed or 137)
    tone = o.tone or 3200
    d = new Float32Array n
    nz = noise n, r
    crack = biquad Float32Array.from(nz), \hp, 5000
    res = biquad Float32Array.from(nz), \bp, tone, 5
    for i from 0 til n
      t = i / SR
      d[i] = crack[i] * 2.5 * env(t, 0.0001, 0.0015) + res[i] * 2.2 * env(t, 0.0002, 0.0025)
    partial d, 0, tone * 1.1, 0.12, 0.004
    partial d, 0.0005, 200 + 30 * r!, 0.02, 0.008, 0.001
    pan L, R, d, o.pan

  # 共振峰合成 ( Klatt 式 ): 聲帶脈衝 ( 諧波, 約 -6dB/八度 ) + 氣音, 經過串接的 4 個會移動的共振峰
  #  - track(u) ( u: 0~1 ) 回傳 {f0, voice ( 有聲的量 ), asp ( 氣音的量 ), F: [F1, F2, F3, F4], amp}
  #  - size: 聲道大小 ( 共振峰倍數, 小孩約 1.15, 大人男聲約 0.9 )
  formant-voice = (n, r, size, track) ->
    src = new Float32Array n
    ph = 0; jit = 0
    tr = []
    for s from 0 til n by 32 => tr.push track(s / n)
    for i from 0 til n
      p = tr[i .>>. 5]
      jit := jit * 0.999 + (r! - 0.5) * 0.002
      f0 = p.f0 * (1 + 0.006 * Math.sin(2 * Math.PI * 5.2 * i / SR) + jit)
      ph += f0 / SR
      ph -= Math.floor ph
      v = 0
      if p.voice > 0
        K = Math.min 40, Math.floor(5000 / f0)
        for k from 1 to K => v += Math.sin(2 * Math.PI * k * ph) / k
      # 氣音隨聲門開合起伏
      a = (r! * 2 - 1) * p.asp * (if p.voice > 0 => 0.6 + 0.4 * Math.sin(2 * Math.PI * ph) else 1)
      src[i] = (v * p.voice * 0.35 + a) * p.amp
    # 串接的共振峰 ( 二階共振, 頻寬隨頻率增加 )
    for j from 0 til 4
      y1 = y2 = 0
      for s from 0 til n by 32
        F = tr[s .>>. 5].F[j] * size
        B = 60 + F * 0.06
        rr = Math.exp(-Math.PI * B / SR)
        c = -rr * rr; b = 2 * rr * Math.cos(2 * Math.PI * F / SR); a = 1 - b - c
        for i from s til Math.min(n, s + 32)
          y = a * src[i] + b * y1 + c * y2
          y2 = y1; y1 = y; src[i] = y
    src
  mix = (a, b, u) -> a + (b - a) * u
  ease = (u) -> u * u * (3 - 2 * u)
  # 蛤? ( 依錄音分析: 約 0.08 秒的 /h/ 氣音, 接著母音 [a] ( F1 約 850, F2 約 1250 ); 音高大幅上揚, 約翻倍 )
  #  - pitch: 起始音高 ( 預設 200 ), rise: 上揚的倍數 ( 預設 1.9 ), size: 聲道大小
  synth.huh = (o = {}) ->
    dur = o.dur or 0.45; f0 = o.pitch or 200; rise = o.rise or 1.9; size = o.size or 1
    h = 0.08 / dur
    make dur, (L, R, n) ->
      r = rng(o.seed or 151)
      d = formant-voice n, r, size, (u) ->
        v = Math.max(0, Math.min(1, (u - h) / 0.08))
        w = Math.max 0, (u - h) / (1 - h)
        amp = Math.min(1, u / 0.06) * (if u > 0.75 => Math.max(0, 1 - (u - 0.75) / 0.25) else 1)
        {f0: f0 * mix(1, rise, Math.pow(w, 1.6)), voice: v, asp: 0.35 * (1 - v) + 0.06, amp, F: [mix(700, 850, v), 1250, 2700, 3600]}
      fade-out d, 0.03
      pan L, R, d, o.pan
  # 耶! ( 依錄音分析: 由 [j] 滑到 [ɛ] ( F1 300→650, F2 2600→1850 ); 音高先升後降, 偏高 )
  #  - pitch: 基準音高 ( 預設 300 ), size: 聲道大小
  synth.yay = (o = {}) ->
    dur = o.dur or 0.5; f0 = o.pitch or 300; size = o.size or 1
    make dur, (L, R, n) ->
      r = rng(o.seed or 157)
      d = formant-voice n, r, size, (u) ->
        g = ease Math.min(1, u / 0.25)
        amp = Math.min(1, u / 0.04) * (if u > 0.7 => Math.max(0, 1 - (u - 0.7) / 0.3) else 1)
        pc = if u < 0.35 => mix(0.88, 1.12, ease(u / 0.35)) else mix(1.12, 0.85, ease((u - 0.35) / 0.65))
        {f0: f0 * pc, voice: 1, asp: 0.05, amp, F: [mix(320, 660, g), mix(2600, 1850, g), mix(3200, 2650, g), 3800]}
      fade-out d, 0.03
      pan L, R, d, o.pan

  # 答對: style pingpong ( 預設, 「叮咚」兩個由高往下的鐘琴音 ) | arp ( 快速上行的琶音 + 閃光 )
  #  - notes: 音 ( pingpong 預設 [B5, G5] ), gap: 間隔
  synth.correct = (o = {}) ->
    arp = o.style == \arp
    notes = (o.notes or (if arp => <[C6 E6 G6 C7]> else <[B5 G5]>)).map S.freq
    gap = o.gap or (if arp => 0.07 else 0.2)
    make notes.length * gap + 1.1, (L, R, n) ->
      d = new Float32Array n
      for f, k in notes
        last = k == notes.length - 1
        dec = if last => 0.45 else (if arp => 0.15 else 0.25)
        partial d, k * gap, f, 1, dec, 0.002
        partial d, k * gap, f * 2, 0.25, dec * 0.4, 0.002
        partial d, k * gap, f * 3.01, 0.08, dec * 0.25, 0.002
      if arp
        sh = biquad noise(n, rng(o.seed or 163)), \hp, 7000
        for i from 0 til n => d[i] += sh[i] * 0.08 * env(i / SR - notes.length * gap * 0.6, 0.1, 0.25) * (if i / SR > notes.length * gap * 0.6 - 0.1 => 1 else 0)
      pan L, R, fade-out(d, 0.05), o.pan
  synth.correct.reverb = 0.15
  # 答錯: style buzzer ( 預設, 「噗、噗——」低頻蜂鳴 ) | trombone ( 「哇、哇、哇、哇~」下滑的悲傷長號 )
  #  - pitch: 蜂鳴的音高 ( 預設 140Hz )
  synth.wrong = (o = {}) ->
    if o.style == \trombone
      notes = <[D4 C#4 C4 B3]>.map S.freq
      return make 2.2, (L, R, n) ->
        d = new Float32Array n; ph = 0
        for i from 0 til n
          t = i / SR
          k = Math.min 3, Math.floor(t / 0.42)
          lt = t - k * 0.42
          f = notes[k] * (if k == 3 => 1 + 0.025 * Math.sin(2 * Math.PI * 5.5 * Math.max(0, lt - 0.15)) else 1) * (1 - 0.03 * Math.min(1, lt / 0.3))
          ph += f / SR
          p = ph % 1
          # 每個音: 吹出來 ( 起音稍慢 ), 最後一個拉長
          a = (if k < 3 => Math.min(1, lt / 0.04) * Math.max(0, 1 - Math.max(0, lt - 0.3) / 0.08) else Math.min(1, lt / 0.04) * Math.max(0, 1 - lt / 0.95))
          d[i] = (2 * p - 1) * a
        # 長號: 鋸齒波經過隨音量變亮的濾波 ( 用固定的低通近似 ) + 一點銅管的共振
        biquad d, \lp, 1400, 0.9
        b2 = biquad Float32Array.from(d), \bp, 1200, 2
        for i from 0 til n => d[i] += b2[i] * 0.5
        pan L, R, fade-out(d, 0.05), o.pan
    f = o.pitch or 140
    make 0.75, (L, R, n) ->
      d = new Float32Array n; p1 = 0; p2 = 0
      for i from 0 til n
        t = i / SR
        a = (if t < 0.13 => Math.min(1, t / 0.005) * Math.min(1, (0.13 - t) / 0.01) else if t > 0.19 => Math.min(1, (t - 0.19) / 0.005) * Math.min(1, (0.72 - t) / 0.03) else 0)
        p1 += f / SR; p2 += f * 1.012 / SR
        d[i] = ((if p1 % 1 < 0.5 => 1 else -1) + (if p2 % 1 < 0.5 => 1 else -1)) * 0.5 * Math.max(0, a)
      biquad d, \lp, 2500
      pan L, R, d, o.pan

  # ---------------------------------------------------------------- 樂器: 木琴 / 鐵琴 ( 模態合成: 幾個不諧和的泛音各自衰減 )
  # hard: 槌子的硬度 ( 0 軟 ~ 1 硬 ), 越硬高泛音與敲擊聲越多
  bar = (o, cfg) ->
    f = S.freq(o.note or cfg.note); dur = o.dur or cfg.dur
    hard = if o.hard? => o.hard else 0.5
    base = cfg.decay * Math.pow(S.freq(cfg.note) / f, 0.4)
    make dur, (L, R, n) ->
      d = new Float32Array n
      for ratio, k in cfg.ratios
        partial d, 0, f * ratio, cfg.amps[k] * (if k => 0.3 + 1.4 * hard else 1), base / (1 + k * cfg.damp), 0.0015
      if cfg.trem
        depth = if o.trem? => o.trem else 0.35
        for i from 0 til n => d[i] *= 1 - depth * (0.5 + 0.5 * Math.sin(2 * Math.PI * 5.5 * i / SR))
      m = biquad noise(Math.round(0.008 * SR), rng(o.seed or 83)), \lp, 2000 + 6000 * hard
      for i from 0 til m.length => d[i] += m[i] * 0.4 * hard * (1 - i / m.length)
      pan L, R, fade-out(d), o.pan
  synth.marimba = (o = {}) -> bar o, {note: \C4, dur: 1.5, ratios: [1 3.93 9.24], amps: [1 0.3 0.1], decay: 0.45, damp: 2.5}
  synth.xylophone = (o = {}) -> bar o, {note: \C5, dur: 0.8, ratios: [1 3 6.1], amps: [1 0.5 0.2], decay: 0.2, damp: 1.5}
  synth.vibraphone = (o = {}) -> bar o, {note: \F4, dur: 3, ratios: [1 4 10], amps: [1 0.25 0.08], decay: 1.4, damp: 3, trem: true}
  synth.glockenspiel = (o = {}) -> bar o, {note: \C6, dur: 2, ratios: [1 2.76 5.4 8.93], amps: [1 0.4 0.2 0.08], decay: 0.9, damp: 1.2}

  # ---------------------------------------------------------------- 樂器: 吉他 ( Karplus-Strong + 撥弦位置 + 琴身共鳴 )
  CHORDS =
    C: <[C3 E3 G3 C4 E4]>, D: <[D3 A3 D4 F#4]>, Dm: <[D3 A3 D4 F4]>, E: <[E2 B2 E3 G#3 B3 E4]>
    Em: <[E2 B2 E3 G3 B3 E4]>, F: <[F2 C3 F3 A3 C4 F4]>, G: <[G2 B2 D3 G3 B3 G4]>
    A: <[A2 E3 A3 C#4 E4]>, Am: <[A2 E3 A3 C4 E4]>
  string = (f, n, o, r) ->
    bright = if o.bright? => o.bright else 0.5
    mute = o.mute or 0
    s = 0.5 + 0.45 * bright * (1 - mute)
    period = SR / f - (1 - s)
    size = Math.ceil(period) + 3
    exc = noise size, r
    # 撥弦位置 pos ( 0~0.5, 離琴橋的比例 ): 減去延遲的自己, 削掉在該處是節點的泛音
    p = Math.max 1, Math.round(period * (o.pos or 0.2))
    for i from size - 1 to p by -1 => exc[i] -= exc[i - p]
    a = 0.15 + 0.8 * bright * (1 - mute * 0.7); y = 0
    for i from 0 til size => y := a * exc[i] + (1 - a) * y; exc[i] = y
    sustain = (o.sustain or 4) * (1 - 0.92 * mute)
    g = Math.pow(0.001, 1 / (f * sustain))
    line = new Float32Array n + size
    for i from 0 til size => line[i] = exc[i]
    d = new Float32Array n
    for k from size til n + size
      j = k - period; j0 = Math.floor j; fr = j - j0
      a1 = line[j0] * (1 - fr) + line[j0 + 1] * fr
      b1 = line[j0 - 1] * (1 - fr) + line[j0] * fr
      line[k] = g * (s * a1 + (1 - s) * b1)
      d[k - size] = line[k]
    d
  # note 單音, 或 chord ( 和弦名稱 ) / notes ( 音名陣列 ) 刷和弦; strum 每條弦的間隔, dir: down | up
  synth.guitar = (o = {}) ->
    notes = o.notes or CHORDS[o.chord] or [o.note or \E3]
    if o.dir == \up => notes = notes.slice!reverse!
    dur = o.dur or 3; gap = if o.strum? => o.strum else 0.03
    make dur, (L, R, n) ->
      r = rng(o.seed or 89)
      for note, k in notes
        at = Math.round(k * gap * SR)
        d = string S.freq(note), n - at, o, r
        body = biquad(Float32Array.from(d), \bp, 105, 1.5)
        body2 = biquad(Float32Array.from(d), \bp, 220, 2)
        for i from 0 til d.length => d[i] = d[i] + body[i] * 0.6 + body2[i] * 0.3
        fade-out d, 0.05
        p = (o.pan or 0) + (k / Math.max(1, notes.length - 1) - 0.5) * 0.3
        gl = Math.cos((p + 1) * Math.PI / 4); gr = Math.sin((p + 1) * Math.PI / 4)
        for i from 0 til d.length => L[at + i] += d[i] * gl; R[at + i] += d[i] * gr

  # ---------------------------------------------------------------- 鼓組
  # 大鼓: 正弦由 tune * 3 掉到 tune, punch 為起音的力道
  synth.kick = (o = {}) ->
    f1 = o.tune or 50; dec = o.decay or 0.3; punch = if o.punch? => o.punch else 0.5
    make dec * 2 + 0.05, (L, R, n) ->
      d = new Float32Array n; ph = 0
      ck = biquad noise(n, rng(o.seed or 97)), \lp, 4000
      for i from 0 til n
        t = i / SR
        ph += 2 * Math.PI * (f1 + f1 * 2 * Math.exp(-t / 0.03)) / SR
        d[i] = Math.tanh((Math.sin(ph) * env(t, 0.001, dec) + ck[i] * punch * 0.6 * env(t, 0.0002, 0.003)) * (1 + 2 * punch))
      pan L, R, fade-out(d), o.pan
  # 小鼓: 鼓皮的音 ( tune Hz ) + 響弦的雜訊 ( snappy )
  synth.snare = (o = {}) ->
    f = o.tune or 180; dec = o.decay or 0.15; snappy = if o.snappy? => o.snappy else 0.6
    make dec * 2 + 0.05, (L, R, n) ->
      d = new Float32Array n
      partial d, 0, f, 0.8, 0.05
      partial d, 0, f * 1.83, 0.4, 0.035
      nz = biquad biquad(noise(n, rng(o.seed or 101)), \hp, 1200), \lp, 9000
      for i from 0 til n => d[i] += nz[i] * snappy * 1.2 * env(i / SR, 0.001, dec * 0.8)
      pan L, R, fade-out(d), o.pan
  # 金屬聲: 六個不成倍數的方波 ( 808 的作法 ), 給鈸與 hi-hat
  metal = (n, scale = 1) ->
    d = new Float32Array n
    for f in [205.3 304.4 369.6 522.7 540 800]
      w = f * scale / SR; ph = 0
      for i from 0 til n
        ph += w
        d[i] += if ph % 1 < 0.5 => 1 else -1
    d
  # hi-hat: open 0 ( 閉合 ) ~ 1 ( 全開 )
  synth.hihat = (o = {}) ->
    open = o.open or 0; dec = 0.04 + open * 0.5
    make dec * 2.5 + 0.02, (L, R, n) ->
      m = metal n, (o.tune or 1)
      nz = noise n, rng(o.seed or 103)
      d = new Float32Array n
      for i from 0 til n => d[i] = m[i] * 0.15 + nz[i] * 0.5
      biquad biquad(d, \hp, 7000), \bp, 10000, 0.8
      for i from 0 til n => d[i] *= env(i / SR, 0.0008, dec)
      pan L, R, fade-out(d), o.pan
  # 中鼓 / 落地鼓: note 為鼓的音高
  synth.tom = (o = {}) ->
    f = S.freq(o.note or \A2); dec = o.decay or 0.35
    make dec * 2 + 0.05, (L, R, n) ->
      d = new Float32Array n; ph = 0
      nz = biquad noise(n, rng(o.seed or 107)), \bp, f * 4, 1
      for i from 0 til n
        t = i / SR
        # 起音時音高高一些, 約 50ms 內落到 f
        ph += 2 * Math.PI * f * (1 + 0.5 * Math.exp(-t / 0.04)) / SR
        d[i] = Math.sin(ph) * env(t, 0.002, dec) + nz[i] * 0.3 * env(t, 0.001, 0.02)
      pan L, R, fade-out(d), o.pan
  # 拍手: 幾次相隔約 10ms 的雜訊爆發, 再一段尾音
  synth.clap = (o = {}) ->
    dec = o.decay or 0.12
    make dec * 2.5 + 0.06, (L, R, n) ->
      nz = biquad noise(n, rng(o.seed or 109)), \bp, 1100, 1.2
      d = new Float32Array n
      for i from 0 til n
        t = i / SR
        a = 0
        for at in [0 0.011 0.022] => if t >= at => a += env(t - at, 0.0005, 0.006)
        if t >= 0.031 => a += env(t - 0.031, 0.001, dec)
        d[i] = nz[i] * a
      L.set d; R.set biquad(Float32Array.from(d), \bp, 1300, 1.5)
  # 衰減的正弦, 用旋轉算 ( 比 Math.sin 快 ): at 秒開始, 頻率 f, 振幅 a, 衰減時間常數 tau, 起音 att
  ring = (d, at, f, a, tau, att = 0.0005) ->
    if f >= SR * 0.45 => return
    o0 = Math.round at * SR
    g = Math.exp(-1 / (tau * SR))
    w = 2 * Math.PI * f / SR
    c = Math.cos w; s = Math.sin w
    x = 1; y = 0; A = a
    an = Math.max 1, Math.round(att * SR)
    for i from o0 til d.length
      k = i - o0
      d[i] += y * A * (if k < an => k / an else 1)
      t = x * c - y * s; y = x * s + y * c; x = t
      A *= g
      if A < 1e-5 => break
  # 常態分布的亂數
  gauss = (r) -> Math.sqrt(-2 * Math.log(r! + 1e-12)) * Math.cos(2 * Math.PI * r!)
  # 碎音鈸 ( 依錄音分析: 能量集中在 3~6kHz, 頻譜是密集的尖峰而不是白噪音; 敲擊後漸亮; 高頻衰減較快, 尾音漸暗 )
  #  - decay: 尾音長度的倍數 ( 1 約 2 秒 ), tune: 音高倍數
  synth.crash = (o = {}) ->
    dec = o.decay or 1; tune = o.tune or 1
    make 2.4 * dec + 0.1, (L, R, n) ->
      r = rng(o.seed or 113)
      for ch in [L, R]
        for k from 0 til 260
          f = Math.max(1200, Math.min(14000, 4200 * Math.pow(2, 0.55 * gauss(r)))) * tune
          ring ch, 0, f, (0.4 + r!) / 16, 0.3 * dec * Math.pow(f / 4200 / tune, -0.8) * (0.6 + 0.8 * r!), 0.002 + 0.07 * r! * Math.min(1, f / 4200 / tune)
        # 鈸身的低音
        for k from 0 til 30
          ring ch, 0, 350 * tune * Math.pow(3, r!), (0.3 + r!) / 14, 0.5 * dec * (0.6 + 0.8 * r!), 0.003
        nz = biquad noise(n, r), \lp, 9000
        # 尖峰之間的一層雜訊 ( 真的鈸不是純粹的正弦 )
        sh = biquad noise(n, r), \bp, 4200 * tune, 0.8
        for i from 0 til n
          t = i / SR
          ch[i] += nz[i] * 0.4 * env(t, 0.0005, 0.008) + sh[i] * 0.1 * env(t, 0.03, 0.3 * dec)
        biquad ch, \hp, 250
        fade-out ch, 0.1
  # 疊音鈸 ( 依錄音分析: 很短的高頻棒擊, 接著小 10dB、集中在 2~3kHz 的長尾音, 越來越暗 )
  #  - decay: 尾音長度的倍數 ( 1 約 3 秒 ), bell: 0~1 越靠近鈸心, 鐘音越重, tune: 音高倍數
  synth.ride = (o = {}) ->
    dec = o.decay or 1; tune = o.tune or 1; bell = o.bell or 0
    make 4 * dec + 0.1, (L, R, n) ->
      r = rng(o.seed or 127)
      st = biquad noise(n, r), \bp, 4800 * tune, 0.7
      for ch in [L, R]
        for i from 0 til Math.round(0.05 * SR) => ch[i] += st[i] * 0.9 * env(i / SR, 0.0003, 0.006)
        for k from 0 til 40 => ring ch, 0, (5000 + 4000 * r!) * tune, 0.04, 0.015 + 0.03 * r!
        for k from 0 til 180
          f = Math.max(700, Math.min(10000, 2600 * Math.pow(2, 0.55 * gauss(r)))) * tune
          ring ch, 0, f, (0.4 + r!) / 80, 0.9 * dec * Math.pow(f / 2600 / tune, -0.3) * (0.6 + 0.8 * r!), 0.001
        sh = biquad noise(n, r), \bp, 3000 * tune, 0.7
        for i from 0 til n => ch[i] += sh[i] * 0.05 * env(i / SR, 0.002, 0.35 * dec)
        if bell
          for k from 0 til 14
            f = 2800 * tune * Math.pow(2, 0.4 * gauss(r))
            ring ch, 0, f, bell * (0.5 + r!) / 6, 0.5 * dec * (0.6 + 0.8 * r!), 0.001
        biquad ch, \hp, 400
        fade-out ch, 0.1

  # 節奏: pattern {kick: 'x...x...', snare: '....x...', ...}, 一格是十六分音符
  #  - X 重音, x 一般, o 輕 ( ghost ), 其他字元 ( . - ) 休止; 空白與 | 忽略
  #  - 名稱: kick snare hihat ohat ( 開 hi-hat ) tom ltom htom clap crash ride, 或任一合成聲名稱
  #  - 值也可以是 [pattern, 參數], 例如 tom: ['....x...', {note: 'D3'}]
  #  - bpm, bars ( 重複幾次 ), swing ( 0~1, 反拍的十六分音符往後挪 )
  KIT =
    kick: [\kick, {}, 1], snare: [\snare, {}, 0.9], hihat: [\hihat, {}, 0.45], ohat: [\hihat, {open: 0.6}, 0.45]
    tom: [\tom, {}, 0.8], ltom: [\tom, {note: \E2}, 0.8], htom: [\tom, {note: \D3}, 0.8]
    clap: [\clap, {}, 0.8], crash: [\crash, {}, 0.55], ride: [\ride, {}, 0.4]
  VEL = {X: 1, x: 0.75, o: 0.4}
  synth.beat = (o = {}) ->
    step = 60 / (o.bpm or 100) / 4; bars = o.bars or 1; swing = o.swing or 0
    pat = o.pattern or {kick: 'x...x...x...x...', snare: '....x.......x...', hihat: 'x.x.x.x.x.x.x.x.'}
    hits = []; steps = 0; tail = 0
    for name, def of pat
      [str, opt] = if Array.isArray(def) => def else [def]
      opt = opt or {}
      [kind, base, g] = KIT[name] or [name, {}, 0.8]
      if !synth[kind] => continue
      b = synth[kind]({} <<< base <<< opt)
      tail = Math.max tail, b.duration
      s = (str or '').replace /[\s|]/g, ''
      steps = Math.max steps, s.length
      hits.push {b, s, g: (if opt.gain? => opt.gain else g)}
    total = steps * bars
    make Math.max(0.1, total * step + tail), (L, R, n) ->
      for {b, s, g} in hits
        for k from 0 til total
          v = VEL[s[k % steps]]
          if !v => continue
          place L, R, b, k * step + (if k % 2 => swing * step * 0.5 else 0), v * g

  # ---------------------------------------------------------------- 通用掃頻
  # wave: sine | triangle | square | saw | noise ( 帶通雜訊, 用 q ); curve: exp | lin
  synth.sweep = (o = {}) ->
    dur = o.dur or 1; f0 = S.freq(o.from or 200); f1 = S.freq(o.to or 2000)
    att = if o.attack? => o.attack else 0.01
    rel = if o.release? => o.release else 0.1
    fu = if o.curve == \lin => ((u) -> f0 + (f1 - f0) * u) else ((u) -> f0 * Math.pow(f1 / f0, u))
    make dur, (L, R, n) ->
      d = if o.wave == \noise => biquad-tv noise(n, rng(o.seed or 131)), \bp, fu, (o.q or 2)
      else
        x = new Float32Array n; ph = 0
        for i from 0 til n
          ph += fu(i / n) / SR
          p = ph % 1
          x[i] = switch o.wave
          | \square => (if p < 0.5 => 0.6 else -0.6)
          | \saw => (2 * p - 1) * 0.6
          | \triangle => 1 - 4 * Math.abs(p - 0.5)
          | otherwise => Math.sin(2 * Math.PI * p)
        x
      for i from 0 til n
        t = i / SR
        d[i] *= Math.min(1, t / Math.max(0.001, att), (dur - t) / Math.max(0.001, rel))
      pan L, R, d, o.pan

  # ---------------------------------------------------------------- 樂譜
  # 文字樂譜: "C4/4 C4 G4 G4 | A4 A4 G4/2 | F4/4 F4 E4 E4 | D4 D4 C4/2"
  #  - 音名 + 八度 ( C4、F#5、Bb3 ), /n 為音長 ( 1 全音符, 2 二分, 4 四分, 8, 16, 32, 64 ), 後面加 . 為附點 ( .. 為雙附點 )
  #  - - 或 r 為休止符; C4+E4+G4 為和弦; | 為小節線 ( 只是方便閱讀 )
  #  - 音長沒寫就沿用前一個 ( 第一個預設四分音符 )
  # S.score.parse(text) -> [{notes: [音名], beats ( 以四分音符為一拍 )}], 休止符的 notes 為空陣列
  # S.score(text, {bpm}) -> melody 用的 notes [[t, note, dur], ...] ( 和弦拆成同時的多個音 )
  parse-score = (text = '') ->
    beats = 1
    out = []
    for tok in text.split(/\s+/) when tok and tok != '|'
      m = /^([^\/]+?)(?:\/(\d+))?(\.*)$/.exec tok
      if !m => throw new Error("看不懂的樂譜: #tok")
      if m.2 => beats = 4 / +m.2
      b = beats * (if m.3.length == 1 => 1.5 else if m.3.length >= 2 => 1.75 else 1)
      notes = if m.1 in <[- r R]> => [] else m.1.split(\+)
      for nm in notes when !/^[A-G](#|b)?-?\d$/.test(nm) => throw new Error("看不懂的音名: #nm")
      out.push {notes, beats: b}
    out
  S.score = (text, o = {}) ->
    spb = 60 / (o.bpm or 100)
    t = 0
    out = []
    for x in parse-score(text)
      for nm in x.notes => out.push [+(t * spb).toFixed(4), nm, +(x.beats * spb * 0.92).toFixed(4)]
      t += x.beats
    out
  S.score.parse = parse-score
  S.score.duration = (text, o = {}) -> parse-score(text).reduce(((a, x) -> a + x.beats), 0) * 60 / (o.bpm or 100)

  # 照樂譜演奏: instrument 為任一合成聲名稱或 AudioBuffer
  #  - 有 note 參數的合成聲 ( pluck、marimba、guitar ... ) 以音高合成每個音
  #  - 其他聲音 ( 例如 pop、kick, 或載入的 AudioBuffer ) 以 base ( 預設 C4 ) 為準變調演奏
  #  - score: 文字樂譜 ( 預設小星星 ), bpm ( 100 ), release: 每個音之後保留的尾音 ( 秒, 預設 0.1 )
  TWINKLE = 'C4/4 C4 G4 G4 | A4 A4 G4/2 | F4/4 F4 E4 E4 | D4 D4 C4/2'
  synth.score = (o = {}) ->
    text = o.score or TWINKLE
    notes = S.score text, {bpm: o.bpm}
    total = S.score.duration text, {bpm: o.bpm}
    inst = o.instrument or \pluck
    rel = if o.release? => o.release else 0.1
    pitched = typeof(inst) == \string and S.params[inst] and S.params[inst].some((p) -> p.k == \note)
    if pitched => return synth.melody {notes, instrument: inst, release: rel, dur: total + rel + 1}
    src = if is-buffer(inst) => inst else (if synth[inst] => synth[inst]({}) else synth.pluck({}))
    base = S.freq(o.base or \C4)
    cache = {}
    make total + src.duration * 2 + 0.1, (L, R, n) ->
      for [t, nm] in notes
        ratio = S.freq(nm) / base
        cache[nm] ?= resample src, ratio, 1
        place L, R, cache[nm], t, 0.8

  # ---------------------------------------------------------------- 每種合成聲都可以加的共用參數
  #  - vary ( 0~1 ): 變化. 換一組雜訊, 音高與長度微調 ( 1 約 ±1 個半音 ), 音量略小; 同樣的 seed 永遠是同樣的變化
  #  - reverb ( 0~1, 濕聲比例 ), room ( 0~1, 空間大小 ): 殘響
  # 重新取樣: 速率 rate ( 音高與長度一起變 ), 音量 gain
  resample = (buf, rate, gain) ->
    src = [buf.getChannelData(0), buf.getChannelData(1)]
    m = buf.length
    n = Math.max 1, Math.round(m / rate)
    out = new AudioBuffer {length: n, sampleRate: SR, numberOfChannels: 2}
    for ch from 0 til 2
      d = new Float32Array n; x = src[ch]
      for i from 0 til n
        p = i * rate; j = Math.floor p; f = p - j
        d[i] = ((x[j] or 0) * (1 - f) + (x[j + 1] or 0) * f) * gain
      out.copyToChannel d, ch
    out
  wrap = (fn) -> (o = {}) ->
    if o.vary
      v = rng((o.seed or 1) * 7919 + 13)
      j = jitter o.vary, v!, v!
      b = fn({} <<< o <<< {seed: (o.seed or 1) * 1009 + 1 + Math.floor(v! * 1e5)})
      b = resample b, j.rate, j.gain
    else b = fn o
    mix = if o.reverb? => o.reverb else (fn.reverb or 0)
    if mix > 0 => reverb b, mix, (if o.room? => o.room else 0.5) else b
  for k of synth => synth[k] = wrap synth[k]

  # 一次產生 count 個變化 ( seed 1 ~ count, vary 預設 0.5 ), 例如幾種略有不同的腳步聲; 回傳 AudioBuffer 陣列
  #   [a, b, c] = S.variants('steps', {n: 1}, 3)
  #   S.load({step1: a, step2: b, step3: c})
  #   S.timeline([{t: 1, sound: ['step1', 'step2', 'step3']}, ...])
  S.variants = (name, opt = {}, count = 4) ->
    [synth[name]({vary: 0.5} <<< opt <<< {seed: (opt.seed or 0) + k + 1}) for k from 0 til count]

  # ---------------------------------------------------------------- 參數表 ( demo 頁與 S.mutate 用 )
  # [最小, 最大, 步進, 預設] 為數值; {note} 為音名或 Hz; {options} 為選項; {text} 為文字; {json} 為陣列等
  PARAMS =
    click: {freq: [500, 5000, 10, 2000], seed: [1, 99, 1, 7], pan: [-1, 1, 0.05, 0]}
    tick: {note: {note: null, hint: "1800 Hz"}, pan: [-1, 1, 0.05, 0]}
    pop: {from: [100, 2000, 10, 380], to: [100, 3000, 10, 900], pan: [-1, 1, 0.05, 0]}
    toggle: {pan: [-1, 1, 0.05, 0]}
    type: {seed: [1, 99, 1, 11]}
    thump: {seed: [1, 99, 1, 5], pan: [-1, 1, 0.05, 0]}
    snap: {seed: [1, 99, 1, 41], pan: [-1, 1, 0.05, 0]}
    chime: {note: {note: "E6"}, dur: [0.3, 4, 0.1, 1.4], pan: [-1, 1, 0.05, 0], reverb: [0, 1, 0.05, 0], room: [0, 1, 0.05, 0.5]}
    success: {pan: [-1, 1, 0.05, 0], reverb: [0, 1, 0.05, 0], room: [0, 1, 0.05, 0.5]}
    notify: {pan: [-1, 1, 0.05, 0], reverb: [0, 1, 0.05, 0], room: [0, 1, 0.05, 0.5]}
    error: {from: {note: "B3"}, to: {note: "F3"}, pan: [-1, 1, 0.05, 0]}
    correct: {style: {options: ["pingpong","arp"], def: "pingpong"}, notes: {json: null}, gap: [0.03, 0.4, 0.01, 0.2], pan: [-1, 1, 0.05, 0], reverb: [0, 1, 0.05, 0.15], room: [0, 1, 0.05, 0.5]}
    wrong: {style: {options: ["buzzer","trombone"], def: "buzzer"}, pitch: [60, 400, 1, 140], pan: [-1, 1, 0.05, 0]}
    reveal: {notes: {json: ["C6","E6","G6","C7","E7"]}, gap: [0.02, 0.2, 0.01, 0.06], seed: [1, 99, 1, 53], pan: [-1, 1, 0.05, 0], reverb: [0, 1, 0.05, 0.35], room: [0, 1, 0.05, 0.5]}
    whoosh: {dur: [0.1, 2, 0.05, 0.7], from: [50, 5000, 10, 400], peak: [50, 6000, 10, 2600], to: [50, 5000, 10, 600], at: [0.05, 0.95, 0.01, 0.45], q: [0.3, 6, 0.1, 1.2], seed: [1, 99, 1, 3]}
    swell: {dur: [0.5, 6, 0.1, 2], seed: [1, 99, 1, 23]}
    slide: {dur: [0.1, 1, 0.05, 0.3], from: [100, 6000, 10, 900], to: [100, 6000, 10, 2600], q: [0.3, 4, 0.1, 0.9], dir: [-1, 1, 0.1, 1], seed: [1, 99, 1, 37]}
    rise: {from: {note: null, hint: "300 Hz"}, to: {note: null, hint: "900 Hz"}, dur: [0.1, 3, 0.05, 0.6], pan: [-1, 1, 0.05, 0]}
    fall: {from: {note: null, hint: "900 Hz"}, to: {note: null, hint: "250 Hz"}, dur: [0.1, 3, 0.05, 0.6], pan: [-1, 1, 0.05, 0]}
    count: {n: [2, 40, 1, 12], dur: [0.2, 4, 0.1, 1.2], ease: {options: ["out","in","linear"], def: "out"}, climb: [0, 24, 1, 7], note: {note: "C6"}, pan: [-1, 1, 0.05, 0]}
    draw: {dur: [0.2, 4, 0.1, 1], rough: [0, 1, 0.05, 0.5], pitch: [500, 8000, 50, 2500], seed: [1, 99, 1, 43], pan: [-1, 1, 0.05, 0]}
    glitch: {dur: [0.1, 2, 0.05, 0.5], seed: [1, 99, 1, 47]}
    sweep: {wave: {options: ["sine","triangle","square","saw","noise"], def: "sine"}, curve: {options: ["exp","lin"], def: "exp"}, from: {note: null, hint: "200 Hz"}, to: {note: null, hint: "2000 Hz"}, dur: [0.1, 4, 0.05, 1], q: [0.3, 10, 0.1, 2], attack: [0, 1, 0.01, 0.01], release: [0, 2, 0.01, 0.1], pan: [-1, 1, 0.05, 0]}
    tension: {note: {note: "A2"}, dur: [1, 12, 0.5, 6]}
    heartbeat: {bpm: [40, 180, 1, 70], dur: [1, 10, 0.5, 4], pan: [-1, 1, 0.05, 0]}
    clock: {bpm: [30, 240, 1, 60], dur: [1, 10, 0.5, 4], seed: [1, 99, 1, 59], pan: [-1, 1, 0.05, 0]}
    fingersnap: {tone: [2000, 5000, 10, 3200], seed: [1, 99, 1, 137], pan: [-1, 1, 0.05, 0]}
    huh: {pitch: [80, 400, 1, 200], rise: [1, 3, 0.05, 1.9], dur: [0.2, 1, 0.01, 0.45], size: [0.8, 1.3, 0.01, 1], seed: [1, 99, 1, 151]}
    yay: {pitch: [100, 500, 1, 300], dur: [0.2, 1.2, 0.01, 0.5], size: [0.8, 1.3, 0.01, 1], seed: [1, 99, 1, 157]}
    paper: {dur: [0.4, 2.5, 0.05, 1.2], crisp: [0, 3, 0.1, 1], flutter: [0, 1, 0.05, 0.6], seed: [1, 99, 1, 61]}
    water: {n: [1, 300, 1, 1], size: [0.5, 10, 0.1, 3], rise: [0, 1, 0.05, 0.05], dur: [0.2, 10, 0.1, 0.4], seed: [1, 99, 1, 67]}
    fire: {dur: [1, 10, 0.5, 6], density: [0, 4, 0.1, 1], seed: [1, 99, 1, 71]}
    steps: {surface: {options: ["wood","concrete","gravel","snow","grass"], def: "wood"}, gait: {options: ["walk","run"], def: "walk"}, n: [1, 12, 1, 4], pace: [0.2, 1.2, 0.05, 0.5], seed: [1, 99, 1, 73]}
    bell: {note: {note: "C5"}, dur: [1, 10, 0.5, 5], pan: [-1, 1, 0.05, 0], reverb: [0, 1, 0.05, 0.2], room: [0, 1, 0.05, 0.5]}
    thunder: {dur: [2, 12, 0.5, 6], dist: [0, 1, 0.05, 0.5], seed: [1, 99, 1, 79]}
    wind: {dur: [1, 10, 0.5, 6], cutoff: [200, 3000, 10, 900], seed: [1, 99, 1, 17]}
    rain: {dur: [1, 10, 0.5, 6], density: [0.002, 0.2, 0.002, 0.02], seed: [1, 99, 1, 19]}
    buzz: {dur: [0.2, 4, 0.1, 1.5], freq: [80, 600, 1, 220], pan: [-1, 1, 0.05, 0]}
    pluck: {note: {note: "A3"}, dur: [0.3, 5, 0.1, 2.5], bright: [0, 1, 0.05, 0.6], slide: [0, 3, 0.1, 0.6], seed: [1, 99, 1, 13], pan: [-1, 1, 0.05, 0], reverb: [0, 1, 0.05, 0], room: [0, 1, 0.05, 0.5]}
    guitar: {note: {note: "E3"}, chord: {options: ["","C","D","Dm","E","Em","F","G","A","Am"], def: ""}, notes: {json: null}, dir: {options: ["down","up"], def: "down"}, strum: [0, 0.1, 0.005, 0.03], dur: [0.5, 6, 0.1, 3], bright: [0, 1, 0.05, 0.5], pos: [0.05, 0.5, 0.01, 0.2], mute: [0, 1, 0.05, 0], seed: [1, 99, 1, 89], pan: [-1, 1, 0.05, 0], reverb: [0, 1, 0.05, 0], room: [0, 1, 0.05, 0.5]}
    marimba: {note: {note: "C4"}, dur: [0.3, 4, 0.1, 1.5], hard: [0, 1, 0.05, 0.5], pan: [-1, 1, 0.05, 0], reverb: [0, 1, 0.05, 0], room: [0, 1, 0.05, 0.5]}
    xylophone: {note: {note: "C5"}, dur: [0.2, 3, 0.1, 0.8], hard: [0, 1, 0.05, 0.5], pan: [-1, 1, 0.05, 0], reverb: [0, 1, 0.05, 0], room: [0, 1, 0.05, 0.5]}
    vibraphone: {note: {note: "F4"}, dur: [0.5, 6, 0.1, 3], trem: [0, 1, 0.05, 0.35], hard: [0, 1, 0.05, 0.5], pan: [-1, 1, 0.05, 0], reverb: [0, 1, 0.05, 0], room: [0, 1, 0.05, 0.5]}
    glockenspiel: {note: {note: "C6"}, dur: [0.3, 4, 0.1, 2], hard: [0, 1, 0.05, 0.5], pan: [-1, 1, 0.05, 0], reverb: [0, 1, 0.05, 0], room: [0, 1, 0.05, 0.5]}
    score: {score: {text: "C4/4 C4 G4 G4 | A4 A4 G4/2 | F4/4 F4 E4 E4 | D4 D4 C4/2"}, instrument: {options: ["pluck", "marimba", "xylophone", "vibraphone", "glockenspiel", "guitar", "chime", "bell", "pop", "tick", "kick", "tom", "water"], def: "pluck"}, bpm: [40, 240, 1, 100], base: {note: "C4"}, release: [0.02, 2, 0.01, 0.1]}
    melody: {notes: {json: [[0,"A3"],[0.4,"C4"],[0.8,"E4"],[1.2,"A4",2]]}, instrument: {options: ["pluck","marimba","xylophone","vibraphone","glockenspiel","guitar","chime","bell"], def: "pluck"}, release: [0.02, 2, 0.01, 0.8], bright: [0, 1, 0.05, 0.6], slide: [0, 3, 0.1, 0.6], reverb: [0, 1, 0.05, 0], room: [0, 1, 0.05, 0.5]}
    drone: {notes: {json: ["A1","E2","A2"]}, dur: [1, 12, 0.5, 8], attack: [0.1, 4, 0.1, 1.5], release: [0.1, 4, 0.1, 2]}
    kick: {tune: [30, 120, 1, 50], decay: [0.05, 1, 0.01, 0.3], punch: [0, 1, 0.05, 0.5], pan: [-1, 1, 0.05, 0]}
    snare: {tune: [100, 400, 1, 180], decay: [0.05, 0.5, 0.01, 0.15], snappy: [0, 1, 0.05, 0.6], seed: [1, 99, 1, 101], pan: [-1, 1, 0.05, 0]}
    hihat: {open: [0, 1, 0.05, 0], tune: [0.5, 2, 0.05, 1], seed: [1, 99, 1, 103], pan: [-1, 1, 0.05, 0]}
    tom: {note: {note: "A2"}, decay: [0.1, 1, 0.01, 0.35], seed: [1, 99, 1, 107], pan: [-1, 1, 0.05, 0]}
    clap: {decay: [0.03, 0.5, 0.01, 0.12], seed: [1, 99, 1, 109]}
    crash: {decay: [0.3, 3, 0.05, 1], tune: [0.5, 2, 0.05, 1], seed: [1, 99, 1, 113]}
    ride: {decay: [0.3, 3, 0.05, 1], bell: [0, 1, 0.05, 0], tune: [0.5, 2, 0.05, 1], seed: [1, 99, 1, 127]}
    beat: {pattern: {json: {"kick":"x.......x.x.....","snare":"....x.......x...","hihat":"x.x.x.x.x.x.x.x."}}, bpm: [50, 200, 1, 100], bars: [1, 8, 1, 1], swing: [0, 1, 0.05, 0], reverb: [0, 1, 0.05, 0], room: [0, 1, 0.05, 0.5]}
  # 展開成 S.params[name] = [{k, type: range | note | select | json, min, max, step, def, options, hint}]
  S.params = {}
  for name, spec of PARAMS
    S.params[name] = for k, v of spec
      if Array.isArray(v) => {k, type: \range, min: v.0, max: v.1, step: v.2, def: v.3}
      else if v.options => {k, type: \select, options: v.options, def: v.def}
      else if \note of v => {k, type: \note, def: v.note, hint: v.hint}
      else if \text of v => {k, type: \text, def: v.text}
      else {k, type: \json, def: v.json}

  # 音名移調 ( 半音 ); Hz 則乘上對應的倍數
  SEMI = {C: 0, D: 2, E: 4, F: 5, G: 7, A: 9, B: 11}
  NAMES = <[C C# D D# E F F# G G# A A# B]>
  transpose = (note, semi) ->
    if typeof(note) == \number => return Math.round(note * Math.pow(2, semi / 12))
    m = /^([A-G])(#|b)?(-?\d)$/.exec note
    if !m => return note
    midi = 12 * (+m.3 + 1) + SEMI[m.1] + (if m.2 == '#' => 1 else if m.2 == \b => -1 else 0) + semi
    NAMES[((midi % 12) + 12) % 12] + (Math.floor(midi / 12) - 1)

  # 以目前的參數 ( 沒給的用預設 ) 為中心, 產生一組變化的參數 ( 不改原物件 ):
  #  - 數值: 常態分布, σ = amount × 範圍 × 0.15, 夾在範圍內並對齊步進
  #  - 選項 ( 例如 style ): 以 amount × 2 的機率 ( 0.5 以上即每次 ) 換成隨機的一個
  #  - 音名: 移 round( 常態 × amount × 2 ) 個半音
  #  - 換一個 seed, 並加上 vary ( amount × 0.5 ), 讓沒有可調參數的聲音也有變化
  #  - pan / reverb / room 不動
  # cfg: {amount ( 0~1, 預設 0.5 ), seed ( 給了就可重現, 否則隨機 )}
  #   S.synth.correct(S.mutate('correct'))
  S.mutate = (name, opt = {}, cfg = {}) ->
    amount = if cfg.amount? => cfg.amount else 0.5
    r = if cfg.seed? => rng(cfg.seed) else Math.random
    out = {} <<< opt
    for p in (S.params[name] or []) when p.k not in <[seed pan reverb room vary]>
      cur = if opt[p.k]? => opt[p.k] else p.def
      switch p.type
      | \range =>
        v = cur + gauss(r) * amount * (p.max - p.min) * 0.15
        v = +(Math.round(Math.max(p.min, Math.min(p.max, v)) / p.step) * p.step).toFixed(4)
        if v == p.def => delete out[p.k] else out[p.k] = v
      | \select =>
        if r! < amount * 2 => out[p.k] = p.options[Math.floor(r! * p.options.length)]
        if out[p.k] == p.def => delete out[p.k]
      | \note =>
        semi = Math.round(gauss(r) * amount * 2)
        if cur? and semi => out[p.k] = transpose cur, semi
    out.seed = 1 + Math.floor(r! * 99)
    if amount > 0 => out.vary = +(amount * 0.5).toFixed(2)
    out

  if typeof(module) != \undefined and module.exports => module.exports = S
  if typeof(window) != \undefined => window.sfx = S
