(function(){
  (function(){
    var SR, S, ctx, bus, isBuffer, peaks, voice, mediaVoice, stopVoice, currentMusic, stopTimeline, startTimeline, hook, NOTES, rng, make, biquad, noise, env, pan, synth;
    if (typeof window !== 'undefined' && window.sfx) {
      return;
    }
    SR = 48000;
    S = {
      buffers: {},
      urls: {},
      items: [],
      voices: [],
      errors: [],
      external: false,
      playing: false,
      rate: 1
    };
    ctx = null;
    S.ctx = function(){
      var AC, i$, ref$, len$, b;
      if (ctx) {
        return ctx;
      }
      AC = window.AudioContext || window.webkitAudioContext;
      ctx = new AC();
      S.master = ctx.createGain();
      S.master.connect(ctx.destination);
      S.buses = {};
      for (i$ = 0, len$ = (ref$ = ['music', 'sfx', 'voice']).length; i$ < len$; ++i$) {
        b = ref$[i$];
        S.buses[b] = ctx.createGain();
        S.buses[b].connect(S.master);
      }
      return ctx;
    };
    bus = function(name){
      S.ctx();
      return S.buses[name] || S.buses.sfx;
    };
    S.resume = function(){
      var c;
      c = S.ctx();
      if (c.state === 'suspended') {
        return c.resume();
      } else {
        return Promise.resolve();
      }
    };
    S.volume = function(name, v, dur){
      var g, now;
      dur == null && (dur = 0.2);
      S.ctx();
      g = name === 'master'
        ? S.master
        : S.buses[name];
      if (!g) {
        return;
      }
      now = ctx.currentTime;
      g.gain.cancelScheduledValues(now);
      g.gain.setValueAtTime(g.gain.value, now);
      return g.gain.linearRampToValueAtTime(v, now + Math.max(0.01, dur));
    };
    isBuffer = function(v){
      return !!(v && typeof v === 'object' && typeof v.getChannelData === 'function' && v.sampleRate);
    };
    S.pending = 0;
    S.load = function(map){
      map == null && (map = {});
      S.pending += Object.keys(map).length;
      return Promise.all(Object.keys(map).map(function(name){
        var v, p;
        v = map[name];
        p = isBuffer(v)
          ? Promise.resolve(v)
          : v && v.then
            ? v
            : fetch(v).then(function(r){
              if (!r.ok) {
                throw new Error(v + ": HTTP " + r.status);
              }
              return r.arrayBuffer();
            }).then(function(ab){
              return new Promise(function(res, rej){
                return S.ctx().decodeAudioData(ab, res, rej);
              });
            });
        if (typeof v === 'string') {
          S.urls[name] = v;
        }
        return p.then(function(buf){
          return S.buffers[name] = buf;
        })['catch'](function(e){
          return S.errors.push("load " + name + ": " + (e.message || e));
        })['finally'](function(){
          return S.pending--;
        });
      })).then(function(){
        return S.buffers;
      });
    };
    peaks = new WeakMap();
    S.peak = function(buf){
      var d, w, env, max, i$, to$, i, s, j$, to1$, j;
      if (peaks.has(buf)) {
        return peaks.get(buf);
      }
      d = buf.getChannelData(0);
      w = Math.max(1, Math.round(buf.sampleRate * 0.003));
      env = new Float32Array(Math.ceil(d.length / w));
      max = 0;
      for (i$ = 0, to$ = env.length; i$ < to$; ++i$) {
        i = i$;
        s = 0;
        for (j$ = i * w, to1$ = Math.min(d.length, (i + 1) * w); j$ < to1$; ++j$) {
          j = j$;
          s += d[j] * d[j];
        }
        env[i] = Math.sqrt(s / w);
        if (env[i] > max) {
          max = env[i];
        }
      }
      i = 0;
      while (i < env.length - 1 && env[i] < max * 0.8) {
        i++;
      }
      while (i < env.length - 1 && env[i + 1] > env[i]) {
        i++;
      }
      peaks.set(buf, i * w / buf.sampleRate);
      return peaks.get(buf);
    };
    voice = function(name, opt){
      var buf, c, src, g, when_, level, offset, end, v;
      opt == null && (opt = {});
      buf = isBuffer(name)
        ? name
        : S.buffers[name];
      if (!buf) {
        S.errors.push("unknown sound: " + name);
        return null;
      }
      c = S.ctx();
      src = c.createBufferSource();
      src.buffer = buf;
      src.loop = !!opt.loop;
      src.playbackRate.value = opt.rate || 1;
      g = c.createGain();
      src.connect(g);
      g.connect(bus(opt.bus || 'sfx'));
      when_ = opt.when || c.currentTime;
      level = opt.gain != null ? opt.gain : 1;
      if (opt.fadeIn) {
        g.gain.setValueAtTime(0, when_);
        g.gain.linearRampToValueAtTime(level, when_ + opt.fadeIn);
      } else {
        g.gain.setValueAtTime(level, when_);
      }
      offset = opt.offset || 0;
      if (opt.duration != null) {
        end = when_ + opt.duration;
        if (opt.fadeOut) {
          g.gain.setValueAtTime(level, Math.max(when_, end - opt.fadeOut));
          g.gain.linearRampToValueAtTime(0, end);
        }
        src.start(when_, offset, src.loop
          ? undefined
          : opt.duration * (opt.rate || 1));
        if (src.loop) {
          src.stop(end);
        }
      } else {
        src.start(when_, offset);
      }
      v = {
        name: name,
        src: src,
        gain: g,
        level: level,
        ended: false
      };
      src.onended = function(){
        v.ended = true;
        return S.voices = S.voices.filter(function(x){
          return x !== v;
        });
      };
      S.voices.push(v);
      return v;
    };
    mediaVoice = function(name, opt){
      var c, a, g, when_, level, end, v, go, delay;
      opt == null && (opt = {});
      c = S.ctx();
      a = new Audio();
      a.crossOrigin = 'anonymous';
      a.preload = 'auto';
      a.preservesPitch = true;
      a.loop = !!opt.loop;
      a.src = S.urls[name];
      a.playbackRate = opt.rate || 1;
      g = c.createGain();
      c.createMediaElementSource(a).connect(g);
      g.connect(bus(opt.bus || 'music'));
      when_ = opt.when || c.currentTime;
      level = opt.gain != null ? opt.gain : 1;
      if (opt.fadeIn) {
        g.gain.setValueAtTime(0, when_);
        g.gain.linearRampToValueAtTime(level, when_ + opt.fadeIn);
      } else {
        g.gain.setValueAtTime(level, when_);
      }
      if (opt.duration != null && opt.fadeOut) {
        end = when_ + opt.duration;
        g.gain.setValueAtTime(level, Math.max(when_, end - opt.fadeOut));
        g.gain.linearRampToValueAtTime(0, end);
      }
      v = {
        name: name,
        media: a,
        gain: g,
        level: level,
        ended: false,
        timers: []
      };
      go = function(){
        var seekThenPlay;
        if (v.ended) {
          return;
        }
        seekThenPlay = function(){
          a.currentTime = opt.offset || 0;
          return a.play()['catch'](function(){});
        };
        if (a.readyState >= 1) {
          return seekThenPlay();
        } else {
          return a.addEventListener('loadedmetadata', seekThenPlay, {
            once: true
          });
        }
      };
      delay = Math.max(0, when_ - c.currentTime);
      v.timers.push(setTimeout(go, delay * 1000));
      if (opt.duration != null) {
        v.timers.push(setTimeout(function(){
          return stopVoice(v, 0.02);
        }, (delay + opt.duration) * 1000));
      }
      a.onended = function(){
        v.ended = true;
        return S.voices = S.voices.filter(function(x){
          return x !== v;
        });
      };
      S.voices.push(v);
      return v;
    };
    stopVoice = function(v, fade){
      var now, i$, ref$, len$, h, e;
      fade == null && (fade = 0.05);
      if (!v || v.ended) {
        return;
      }
      now = ctx.currentTime;
      v.gain.gain.cancelScheduledValues(now);
      v.gain.gain.setValueAtTime(v.gain.gain.value, now);
      v.gain.gain.linearRampToValueAtTime(0, now + fade);
      if (v.media) {
        for (i$ = 0, len$ = (ref$ = v.timers).length; i$ < len$; ++i$) {
          h = ref$[i$];
          clearTimeout(h);
        }
        v.ended = true;
        setTimeout(function(){
          v.media.pause();
          v.media.removeAttribute('src');
          return v.media.load();
        }, (fade + 0.02) * 1000);
        S.voices = S.voices.filter(function(x){
          return x !== v;
        });
        return;
      }
      try {
        return v.src.stop(now + fade + 0.01);
      } catch (e$) {
        return e = e$;
      }
    };
    S.play = function(name, opt){
      var v;
      opt == null && (opt = {});
      S.resume();
      v = voice(name, opt);
      if (!v) {
        return null;
      }
      v.manual = true;
      return {
        stop: function(fade){
          return stopVoice(v, fade);
        },
        fade: function(to, dur){
          var now;
          dur == null && (dur = 0.5);
          now = ctx.currentTime;
          v.gain.gain.cancelScheduledValues(now);
          v.gain.gain.setValueAtTime(v.gain.gain.value, now);
          return v.gain.gain.linearRampToValueAtTime(to, now + dur);
        },
        voice: v
      };
    };
    S.stop = function(name, opt){
      var i$, ref$, len$, v, results$ = [];
      opt == null && (opt = {});
      for (i$ = 0, len$ = (ref$ = S.voices).length; i$ < len$; ++i$) {
        v = ref$[i$];
        if (v.manual && (!name || v.name === name)) {
          results$.push(stopVoice(v, opt.fade || 0.05));
        }
      }
      return results$;
    };
    currentMusic = null;
    S.music = function(name, opt){
      var fade;
      opt == null && (opt = {});
      fade = opt.fade != null ? opt.fade : 1;
      if (currentMusic) {
        currentMusic.stop(fade);
      }
      currentMusic = null;
      if (!name) {
        return null;
      }
      currentMusic = S.play(name, import$({
        loop: true,
        bus: 'music',
        fadeIn: fade
      }, opt));
      return currentMusic;
    };
    S.timeline = function(items){
      items == null && (items = []);
      S.items = items.map(function(it){
        return import$({}, it);
      });
      if (S.playing) {
        S.transport({
          playing: true,
          t: S.t || 0,
          force: true
        });
      }
      return S;
    };
    S.cues = function(cues, opt){
      cues == null && (cues = []);
      opt == null && (opt = {});
      return S.timeline(cues.map(function(c){
        return import$({
          t: c.t,
          sound: c.sfx || c.sound,
          gain: c.gain
        }, opt);
      }));
    };
    stopTimeline = function(){
      var i$, ref$, len$, v, results$ = [];
      for (i$ = 0, len$ = (ref$ = S.voices).length; i$ < len$; ++i$) {
        v = ref$[i$];
        if (!v.manual) {
          results$.push(stopVoice(v, 0.03));
        }
      }
      return results$;
    };
    startTimeline = function(t0){
      var c, now, R, i$, ref$, len$, it, buf, b, lead, start, len, skip, opt, ref1$, results$ = [];
      c = S.ctx();
      now = c.currentTime + 0.02;
      R = S.rate || 1;
      for (i$ = 0, len$ = (ref$ = S.items).length; i$ < len$; ++i$) {
        it = ref$[i$];
        buf = S.buffers[it.sound];
        if (!buf) {
          continue;
        }
        b = it.bus || 'sfx';
        lead = (it.align || (b === 'sfx' ? 'peak' : 'start')) === 'peak' ? S.peak(buf) : 0;
        start = it.t - lead;
        len = it.loop
          ? (it.until != null ? it.until : 1e9) - start
          : it.duration || buf.duration / (it.rate || 1);
        if (start + len <= t0) {
          continue;
        }
        skip = Math.max(0, t0 - start);
        opt = (ref1$ = import$({}, it), ref1$.bus = b, ref1$.when = now + Math.max(0, start - t0) / R, ref1$.duration = (len - skip) / R, ref1$.rate = (it.rate || 1) * R, ref1$);
        opt.offset = (it.offset || 0) + (it.loop
          ? skip % buf.duration
          : skip * (it.rate || 1));
        if (skip > 0 && it.fadeIn) {
          opt.fadeIn = 0;
        }
        if (R !== 1 && (b === 'voice' || b === 'music') && S.urls[it.sound]) {
          results$.push(mediaVoice(it.sound, opt));
        } else {
          results$.push(voice(buf, opt));
        }
      }
      return results$;
    };
    S.transport = function(arg$){
      var ref$, playing, t, ref1$, force, from, rate, was;
      ref$ = arg$ != null
        ? arg$
        : {}, playing = ref$.playing, t = (ref1$ = ref$.t) != null ? ref1$ : 0, force = ref$.force, from = ref$.from, rate = ref$.rate;
      if (from && from !== 'player') {
        S.external = true;
      }
      if (rate != null && +rate > 0 && +rate !== S.rate) {
        S.rate = +rate;
        force = true;
      }
      was = S.playing;
      S.playing = !!playing;
      S.t = t;
      S.tAt = (ctx && ctx.currentTime) || 0;
      if (!playing) {
        return stopTimeline();
      }
      S.resume();
      if (was && !force) {
        return;
      }
      stopTimeline();
      return startTimeline(t);
    };
    hook = function(L){
      var P, play, seek;
      if (!L || !L.player || L.player.__sound) {
        return;
      }
      P = L.player.prototype;
      play = P.play;
      seek = P.seek;
      P.play = function(go){
        var r;
        go == null && (go = true);
        r = play.apply(this, arguments);
        if (!S.external) {
          S.transport({
            playing: this.playing,
            t: this.t
          });
        }
        return r;
      };
      P.seek = function(t){
        var last, r;
        last = this.t;
        r = seek.apply(this, arguments);
        if (!S.external && this.started) {
          if (this.playing && (this.t < last - 0.01 || this.t - last > 0.3)) {
            S.transport({
              playing: true,
              t: this.t,
              force: true
            });
          }
          if (!this.playing && S.playing) {
            S.transport({
              playing: false,
              t: this.t
            });
          }
        }
        return r;
      };
      return L.player.__sound = true;
    };
    if (window.lotion) {
      hook(window.lotion);
    } else {
      document.addEventListener('DOMContentLoaded', function(){
        return hook(window.lotion);
      });
    }
    S.render = function(duration, opt){
      var sr, oc, i$, ref$, len$, it, buf, b, lead, start, src, g, level, at, len;
      opt == null && (opt = {});
      sr = opt.sampleRate || SR;
      oc = new OfflineAudioContext(2, Math.ceil(duration * sr), sr);
      for (i$ = 0, len$ = (ref$ = S.items).length; i$ < len$; ++i$) {
        it = ref$[i$];
        buf = S.buffers[it.sound];
        if (!buf) {
          continue;
        }
        b = it.bus || 'sfx';
        lead = (it.align || (b === 'sfx' ? 'peak' : 'start')) === 'peak' ? S.peak(buf) : 0;
        start = it.t - lead;
        src = oc.createBufferSource();
        src.buffer = buf;
        src.loop = !!it.loop;
        src.playbackRate.value = it.rate || 1;
        g = oc.createGain();
        level = it.gain != null ? it.gain : 1;
        g.gain.value = level;
        src.connect(g);
        g.connect(oc.destination);
        at = Math.max(0, start);
        if (it.fadeIn) {
          g.gain.setValueAtTime(0, at);
          g.gain.linearRampToValueAtTime(level, at + it.fadeIn);
        }
        len = it.loop
          ? (it.until != null ? it.until : duration) - start
          : it.duration || buf.duration / (it.rate || 1);
        if (it.fadeOut) {
          g.gain.setValueAtTime(level, Math.max(at, start + len - it.fadeOut));
          g.gain.linearRampToValueAtTime(0, start + len);
        }
        src.start(at, (it.offset || 0) + Math.max(0, -start));
        src.stop(start + len);
      }
      return oc.startRendering();
    };
    S.wav = function(buf){
      var ch, n, dv, w, data, res$, i$, c, o, i, j$, v;
      ch = buf.numberOfChannels;
      n = buf.length;
      dv = new DataView(new ArrayBuffer(44 + n * ch * 2));
      w = function(o, s){
        var i$, to$, i, results$ = [];
        for (i$ = 0, to$ = s.length; i$ < to$; ++i$) {
          i = i$;
          results$.push(dv.setUint8(o + i, s.charCodeAt(i)));
        }
        return results$;
      };
      w(0, 'RIFF');
      dv.setUint32(4, 36 + n * ch * 2, true);
      w(8, 'WAVE');
      w(12, 'fmt ');
      dv.setUint32(16, 16, true);
      dv.setUint16(20, 1, true);
      dv.setUint16(22, ch, true);
      dv.setUint32(24, buf.sampleRate, true);
      dv.setUint32(28, buf.sampleRate * ch * 2, true);
      dv.setUint16(32, ch * 2, true);
      dv.setUint16(34, 16, true);
      w(36, 'data');
      dv.setUint32(40, n * ch * 2, true);
      res$ = [];
      for (i$ = 0; i$ < ch; ++i$) {
        c = i$;
        res$.push(buf.getChannelData(c));
      }
      data = res$;
      o = 44;
      for (i$ = 0; i$ < n; ++i$) {
        i = i$;
        for (j$ = 0; j$ < ch; ++j$) {
          c = j$;
          v = Math.max(-1, Math.min(1, data[c][i]));
          dv.setInt16(o, v < 0
            ? v * 0x8000
            : v * 0x7fff, true);
          o += 2;
        }
      }
      return new Blob([dv], {
        type: 'audio/wav'
      });
    };
    S.report = function(){
      return {
        loaded: Object.keys(S.buffers).map(function(k){
          return {
            name: k,
            duration: +S.buffers[k].duration.toFixed(2),
            peak: +S.peak(S.buffers[k]).toFixed(3)
          };
        }),
        timeline: S.items.length,
        playing: S.playing,
        context: ctx ? ctx.state : null,
        errors: S.errors.slice(-10)
      };
    };
    NOTES = {
      C: -9,
      D: -7,
      E: -5,
      F: -4,
      G: -2,
      A: 0,
      B: 2
    };
    S.freq = function(n){
      var m, semi;
      if (typeof n === 'number') {
        return n;
      }
      m = /^([A-G])(#|b)?(-?\d)$/.exec(n);
      if (!m) {
        return 440;
      }
      semi = NOTES[m[1]] + (m[2] === '#'
        ? 1
        : m[2] === 'b' ? -1 : 0) + (+m[3] - 4) * 12;
      return 440 * Math.pow(2, semi / 12);
    };
    rng = function(seed){
      var s;
      seed == null && (seed = 1);
      s = seed >>> 0 || 1;
      return function(){
        s = s * 1664525 + 1013904223 >>> 0;
        return s / 4294967296;
      };
    };
    make = function(dur, fn, opt){
      var n, L, R, max, i$, i, k, buf;
      opt == null && (opt = {});
      n = Math.max(1, Math.round(dur * SR));
      L = new Float32Array(n);
      R = new Float32Array(n);
      fn(L, R, n);
      max = 0;
      for (i$ = 0; i$ < n; ++i$) {
        i = i$;
        max = Math.max(max, Math.abs(L[i]), Math.abs(R[i]));
      }
      k = max > 0 ? (opt.peak || 0.9) / max : 1;
      buf = new AudioBuffer({
        length: n,
        sampleRate: SR,
        numberOfChannels: 2
      });
      for (i$ = 0; i$ < n; ++i$) {
        i = i$;
        L[i] *= k;
        R[i] *= k;
      }
      buf.copyToChannel(L, 0);
      buf.copyToChannel(R, 1);
      return buf;
    };
    biquad = function(d, type, f, q){
      var w, cs, al, ref$, b0, b1, b2, a0, a1, a2, x1, x2, y1, y2, i$, to$, i, x, y;
      q == null && (q = 0.707);
      w = 2 * Math.PI * f / SR;
      cs = Math.cos(w);
      al = Math.sin(w) / (2 * q);
      ref$ = (function(){
        switch (type) {
        case 'lp':
          return [(1 - cs) / 2, 1 - cs, (1 - cs) / 2, 1 + al, -2 * cs, 1 - al];
        case 'hp':
          return [(1 + cs) / 2, -(1 + cs), (1 + cs) / 2, 1 + al, -2 * cs, 1 - al];
        default:
          return [al, 0, -al, 1 + al, -2 * cs, 1 - al];
        }
      }()), b0 = ref$[0], b1 = ref$[1], b2 = ref$[2], a0 = ref$[3], a1 = ref$[4], a2 = ref$[5];
      x1 = x2 = y1 = y2 = 0;
      for (i$ = 0, to$ = d.length; i$ < to$; ++i$) {
        i = i$;
        x = d[i];
        y = (b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2) / a0;
        x2 = x1;
        x1 = x;
        y2 = y1;
        y1 = y;
        d[i] = y;
      }
      return d;
    };
    noise = function(n, r){
      var d, i$, i;
      d = new Float32Array(n);
      for (i$ = 0; i$ < n; ++i$) {
        i = i$;
        d[i] = r() * 2 - 1;
      }
      return d;
    };
    env = function(t, a, d){
      if (t < a) {
        return t / a;
      } else {
        return Math.exp(-(t - a) / d);
      }
    };
    pan = function(L, R, src, p, gain){
      var gl, gr, i$, to$, i, results$ = [];
      p == null && (p = 0);
      gain == null && (gain = 1);
      gl = Math.cos((p + 1) * Math.PI / 4) * gain;
      gr = Math.sin((p + 1) * Math.PI / 4) * gain;
      for (i$ = 0, to$ = src.length; i$ < to$; ++i$) {
        i = i$;
        L[i] += src[i] * gl;
        results$.push(R[i] += src[i] * gr);
      }
      return results$;
    };
    synth = S.synth = {};
    synth.click = function(o){
      o == null && (o = {});
      return make(0.05, function(L, R, n){
        var r, nz, d, i$, i, t;
        r = rng(o.seed || 7);
        nz = biquad(noise(n, r), 'hp', 2500);
        d = new Float32Array(n);
        for (i$ = 0; i$ < n; ++i$) {
          i = i$;
          t = i / SR;
          d[i] = nz[i] * env(t, 0.0005, 0.004) + 0.5 * Math.sin(2 * Math.PI * (o.freq || 2000) * t) * env(t, 0.0005, 0.012);
        }
        return pan(L, R, d, o.pan);
      });
    };
    synth.tick = function(o){
      o == null && (o = {});
      return make(0.06, function(L, R, n){
        var f, d, i$, i, t;
        f = S.freq(o.note || o.freq || 1800);
        d = new Float32Array(n);
        for (i$ = 0; i$ < n; ++i$) {
          i = i$;
          t = i / SR;
          d[i] = Math.sin(2 * Math.PI * f * t) * env(t, 0.001, 0.018);
        }
        return pan(L, R, d, o.pan);
      });
    };
    synth.pop = function(o){
      o == null && (o = {});
      return make(0.15, function(L, R, n){
        var f0, f1, d, ph, i$, i, t, f;
        f0 = o.from || 380;
        f1 = o.to || 900;
        d = new Float32Array(n);
        ph = 0;
        for (i$ = 0; i$ < n; ++i$) {
          i = i$;
          t = i / SR;
          f = f0 + (f1 - f0) * Math.min(1, t / 0.03);
          ph += 2 * Math.PI * f / SR;
          d[i] = Math.sin(ph) * env(t, 0.002, 0.04);
        }
        return pan(L, R, d, o.pan);
      });
    };
    synth.toggle = function(o){
      o == null && (o = {});
      return make(0.12, function(L, R, n){
        var d, i$, i, t;
        d = new Float32Array(n);
        for (i$ = 0; i$ < n; ++i$) {
          i = i$;
          t = i / SR;
          d[i] = Math.sin(2 * Math.PI * 1500 * t) * env(t, 0.001, 0.012) + (t > 0.05 ? Math.sin(2 * Math.PI * 2200 * (t - 0.05)) * env(t - 0.05, 0.001, 0.015) : 0);
        }
        return pan(L, R, d, o.pan);
      });
    };
    synth.chime = function(o){
      var f, dur;
      o == null && (o = {});
      f = S.freq(o.note || 'E6');
      dur = o.dur || 1.4;
      return make(dur, function(L, R, n){
        var d, i$, i, t;
        d = new Float32Array(n);
        for (i$ = 0; i$ < n; ++i$) {
          i = i$;
          t = i / SR;
          d[i] = (Math.sin(2 * Math.PI * f * t) + 0.5 * Math.sin(2 * Math.PI * f * 2.01 * t) * Math.exp(-t * 2) + 0.25 * Math.sin(2 * Math.PI * f * 3.02 * t) * Math.exp(-t * 4)) * env(t, 0.003, dur / 4);
        }
        return pan(L, R, d, o.pan);
      });
    };
    synth.success = function(o){
      o == null && (o = {});
      return make(0.9, function(L, R, n){
        var d, i$, ref$, len$, ref1$, at, note, f, j$, i, t;
        d = new Float32Array(n);
        for (i$ = 0, len$ = (ref$ = [[0, 'C6'], [0.09, 'E6'], [0.18, 'G6']]).length; i$ < len$; ++i$) {
          ref1$ = ref$[i$], at = ref1$[0], note = ref1$[1];
          f = S.freq(note);
          for (j$ = Math.round(at * SR); j$ < n; ++j$) {
            i = j$;
            t = i / SR - at;
            d[i] += (Math.sin(2 * Math.PI * f * t) + 0.4 * Math.sin(2 * Math.PI * f * 2.01 * t)) * env(t, 0.003, 0.25);
          }
        }
        return pan(L, R, d, o.pan);
      });
    };
    synth.notify = function(o){
      o == null && (o = {});
      return make(0.7, function(L, R, n){
        var d, i$, ref$, len$, ref1$, at, note, f, j$, i, t;
        d = new Float32Array(n);
        for (i$ = 0, len$ = (ref$ = [[0, 'A5'], [0.12, 'E6']]).length; i$ < len$; ++i$) {
          ref1$ = ref$[i$], at = ref1$[0], note = ref1$[1];
          f = S.freq(note);
          for (j$ = Math.round(at * SR); j$ < n; ++j$) {
            i = j$;
            t = i / SR - at;
            d[i] += Math.sin(2 * Math.PI * f * t) * env(t, 0.004, 0.18);
          }
        }
        return pan(L, R, d, o.pan);
      });
    };
    synth.whoosh = function(o){
      var dur, f0, f1, f2, at, q;
      o == null && (o = {});
      dur = o.dur || 0.7;
      f0 = o.from || 400;
      f1 = o.peak || 2600;
      f2 = o.to || 600;
      at = o.at || 0.45;
      q = o.q || 1.2;
      return make(dur, function(L, R, n){
        var r, nz, d, seg, i$, s, u, fc, part, j$, to$, i, v, results$ = [];
        r = rng(o.seed || 3);
        nz = noise(n, r);
        d = new Float32Array(n);
        seg = 256;
        for (i$ = 0; seg < 0 ? i$ > n : i$ < n; i$ += seg) {
          s = i$;
          u = s / n;
          fc = u < at
            ? f0 + (f1 - f0) * (u / at)
            : f1 + (f2 - f1) * ((u - at) / (1 - at));
          part = biquad(nz.slice(s, s + seg), 'bp', fc, q);
          for (j$ = 0, to$ = part.length; j$ < to$; ++j$) {
            i = j$;
            v = (s + i) / n;
            d[s + i] = part[i] * (v < at
              ? Math.sin(Math.PI / 2 * v / at)
              : Math.cos(Math.PI / 2 * (v - at) / (1 - at)));
          }
        }
        for (i$ = 0; i$ < n; ++i$) {
          i = i$;
          L[i] = d[i] * (1 - i / n * 0.6);
          results$.push(R[i] = d[i] * (0.4 + i / n * 0.6));
        }
        return results$;
      });
    };
    synth.type = function(o){
      o == null && (o = {});
      return synth.click({
        freq: 1200 + 600 * rng(o.seed || 11)(),
        seed: o.seed
      });
    };
    synth.thump = function(o){
      o == null && (o = {});
      return make(0.35, function(L, R, n){
        var r, nz, d, ph, i$, i, t;
        r = rng(o.seed || 5);
        nz = biquad(noise(n, r), 'bp', 1800, 0.8);
        d = new Float32Array(n);
        ph = 0;
        for (i$ = 0; i$ < n; ++i$) {
          i = i$;
          t = i / SR;
          ph += 2 * Math.PI * (70 + 60 * Math.exp(-t / 0.04)) / SR;
          d[i] = Math.sin(ph) * env(t, 0.002, 0.09) + 0.35 * nz[i] * env(t, 0.001, 0.03);
        }
        return pan(L, R, d, o.pan);
      });
    };
    synth.pluck = function(o){
      var f, dur, bright, slide;
      o == null && (o = {});
      f = S.freq(o.note || 'A3');
      dur = o.dur || 2.5;
      bright = o.bright != null
        ? o.bright
        : (0.6, slide = o.slide || 0.6);
      return make(dur, function(L, R, n){
        var r, period, size, buf, i$, to$, k, j$, i, d, line, decay, p, j, j0, fr, a, b;
        r = rng(o.seed || 13);
        period = SR / f;
        size = Math.ceil(period * 2) + 4;
        buf = noise(size, r);
        for (i$ = 0, to$ = Math.round((1 - bright) * 4); i$ < to$; ++i$) {
          k = i$;
          for (j$ = 1; j$ < size; ++j$) {
            i = j$;
            buf[i] = (buf[i] + buf[i - 1]) / 2;
          }
        }
        d = new Float32Array(n);
        line = new Float32Array(n + size);
        for (i$ = 0; i$ < size; ++i$) {
          i = i$;
          line[i] = buf[i];
        }
        decay = Math.pow(0.996, 220 / f);
        for (i$ = size, to$ = n + size; i$ < to$; ++i$) {
          k = i$;
          p = period * Math.pow(2, slide * Math.exp(-(k - size) / SR / 0.09) / 12);
          j = k - p;
          j0 = Math.floor(j);
          fr = j - j0;
          a = line[j0] * (1 - fr) + line[j0 + 1] * fr;
          b = line[j0 - 1] * (1 - fr) + line[j0] * fr;
          line[k] = decay * (a + b) / 2;
          d[k - size] = line[k];
        }
        for (i$ = 0; i$ < n; ++i$) {
          i = i$;
          d[i] *= Math.min(1, (n - i) / (0.3 * SR));
        }
        return pan(L, R, d, o.pan);
      });
    };
    synth.drone = function(o){
      var notes, dur, att, rel;
      o == null && (o = {});
      notes = (o.notes || ['A1', 'E2', 'A2']).map(S.freq);
      dur = o.dur || 8;
      att = o.attack || 1.5;
      rel = o.release || 2;
      return make(dur, function(L, R, n){
        var i$, ref$, len$, k, f, d, j$, i, t, a, results$ = [];
        for (i$ = 0, len$ = (ref$ = notes).length; i$ < len$; ++i$) {
          k = i$;
          f = ref$[i$];
          d = new Float32Array(n);
          for (j$ = 0; j$ < n; ++j$) {
            i = j$;
            t = i / SR;
            a = Math.min(1, t / att, (dur - t) / rel);
            d[i] = (Math.sin(2 * Math.PI * f * t) + 0.3 * Math.sin(2 * Math.PI * f * 1.003 * 2 * t)) * a;
          }
          results$.push(pan(L, R, d, (k - (notes.length - 1) / 2) * 0.4, 1 / notes.length));
        }
        return results$;
      });
    };
    synth.wind = function(o){
      var dur;
      o == null && (o = {});
      dur = o.dur || 6;
      return make(dur, function(L, R, n){
        var r, d, lag, i$, i, t, a, results$ = [];
        r = rng(o.seed || 17);
        d = biquad(biquad(noise(n, r), 'hp', 150), 'lp', o.cutoff || 900);
        lag = 2400;
        for (i$ = 0; i$ < n; ++i$) {
          i = i$;
          t = i / SR;
          a = (0.6 + 0.4 * Math.sin(2 * Math.PI * 0.13 * t) * Math.sin(2 * Math.PI * 0.071 * t + 1)) * Math.min(1, t, dur - t);
          L[i] = d[i] * a;
          results$.push(R[i] = d[(i + lag) % n] * a);
        }
        return results$;
      });
    };
    synth.rain = function(o){
      var dur, density;
      o == null && (o = {});
      dur = o.dur || 6;
      density = o.density || 0.02;
      return make(dur, function(L, R, n){
        var r, bed, grains, i$, i, a, results$ = [];
        r = rng(o.seed || 19);
        bed = biquad(noise(n, r), 'bp', 4000, 0.5);
        grains = new Float32Array(n);
        for (i$ = 0; i$ < n; ++i$) {
          i = i$;
          if (r() < density * 0.05) {
            grains[i] = r() * 2 - 1;
          }
        }
        grains = biquad(biquad(grains, 'hp', 2500), 'lp', 9000);
        for (i$ = 0; i$ < n; ++i$) {
          i = i$;
          a = Math.min(1, i / SR, (n - i) / SR);
          L[i] = (bed[i] * 0.15 + grains[i] * 3) * a;
          results$.push(R[i] = (bed[(i + 1200) % n] * 0.15 + grains[(i + 777) % n] * 3) * a);
        }
        return results$;
      });
    };
    synth.buzz = function(o){
      var dur, f;
      o == null && (o = {});
      dur = o.dur || 1.5;
      f = S.freq(o.freq || 220);
      return make(dur, function(L, R, n){
        var d, ph, i$, i, t, ff, saw;
        d = new Float32Array(n);
        ph = 0;
        for (i$ = 0; i$ < n; ++i$) {
          i = i$;
          t = i / SR;
          ff = f * (1 + 0.03 * Math.sin(2 * Math.PI * 5.3 * t) + 0.015 * Math.sin(2 * Math.PI * 1.7 * t));
          ph += ff / SR;
          saw = 2 * (ph - Math.floor(ph + 0.5));
          d[i] = saw * (0.75 + 0.25 * Math.sin(2 * Math.PI * ff * 0.5 * t)) * Math.min(1, t / 0.08, (dur - t) / 0.15);
        }
        biquad(d, 'lp', 2200);
        biquad(d, 'bp', f * 3, 0.6);
        return pan(L, R, d, o.pan);
      });
    };
    synth.swell = function(o){
      var dur;
      o == null && (o = {});
      dur = o.dur || 2;
      return make(dur, function(L, R, n){
        var r, nz, seg, i$, s, lresult$, u, part, j$, to$, i, results$ = [];
        r = rng(o.seed || 23);
        nz = noise(n, r);
        seg = 512;
        for (i$ = 0; seg < 0 ? i$ > n : i$ < n; i$ += seg) {
          s = i$;
          lresult$ = [];
          u = s / n;
          part = biquad(nz.slice(s, s + seg), 'bp', 300 + 3000 * u * u, 0.9);
          for (j$ = 0, to$ = part.length; j$ < to$; ++j$) {
            i = j$;
            lresult$.push(L[s + i] = R[s + i] = part[i] * u * u);
          }
          results$.push(lresult$);
        }
        return results$;
      });
    };
    synth.melody = function(o){
      var seq, dur, voices;
      o == null && (o = {});
      seq = o.notes || [];
      dur = o.dur || Math.max.apply(Math, seq.map(function(x){
        return x[0] + (x[2] || 1.5);
      })) + 1;
      voices = seq.map(function(x, k){
        return [
          x, synth.pluck({
            note: x[1],
            dur: (x[2] || 1.5) + 0.8,
            bright: o.bright,
            slide: o.slide,
            seed: 31 + k
          })
        ];
      });
      return make(dur, function(L, R, n){
        var i$, ref$, len$, ref1$, ref2$, t, note, d, vel, b, lresult$, l, r_, o0, j$, to$, i, results$ = [];
        for (i$ = 0, len$ = (ref$ = voices).length; i$ < len$; ++i$) {
          ref1$ = ref$[i$], ref2$ = ref1$[0], t = ref2$[0], note = ref2$[1], d = ref2$[2], vel = ref2$[3], b = ref1$[1];
          lresult$ = [];
          l = b.getChannelData(0);
          r_ = b.getChannelData(1);
          o0 = Math.round(t * SR);
          for (j$ = 0, to$ = Math.min(l.length, n - o0); j$ < to$; ++j$) {
            i = j$;
            L[o0 + i] += l[i] * (vel || 0.8);
            lresult$.push(R[o0 + i] += r_[i] * (vel || 0.8));
          }
          results$.push(lresult$);
        }
        return results$;
      });
    };
    if (typeof module !== 'undefined' && module.exports) {
      module.exports = S;
    }
    if (typeof window !== 'undefined') {
      return window.sfx = S;
    }
  })();
  function import$(obj, src){
    var own = {}.hasOwnProperty;
    for (var key in src) if (own.call(src, key)) obj[key] = src[key];
    return obj;
  }
}).call(this);
