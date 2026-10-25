(function(){
  (function(){
    var SR, S, ctx, bus, isBuffer, peaks, voice, mediaVoice, stopVoice, jitter, currentMusic, stopTimeline, startTimeline, hook, NOTES, rng, make, coef, biquad, biquadTv, noise, env, pan, synth, place, partial, fadeOut, wander, glideOsc, COMB, ALLPASS, reverb, glide, grain, pick, bubble, SURFACE, pink, formantVoice, mix, ease, bar, CHORDS, string, metal, ring, gauss, KIT, VEL, parseScore, TWINKLE, resample, wrap, k, PARAMS, name, spec, v, SEMI, NAMES, transpose;
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
      var c, a, g, when_, level, v, go, delay, buf, offset, toEnd;
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
        buf = S.buffers[name];
        offset = opt.offset || 0;
        toEnd = !a.loop && buf && offset + opt.duration * a.playbackRate >= buf.duration - 0.02;
        a.addEventListener('playing', function(){
          var left, now;
          if (v.ended) {
            return;
          }
          left = Math.max(0, opt.duration - (a.currentTime - offset) / a.playbackRate);
          now = c.currentTime;
          if (opt.fadeOut) {
            g.gain.setValueAtTime(level, Math.max(now, now + left - opt.fadeOut));
            g.gain.linearRampToValueAtTime(0, now + left);
          }
          if (!toEnd) {
            return v.timers.push(setTimeout(function(){
              return stopVoice(v, 0.02);
            }, left * 1000));
          }
        }, {
          once: true
        });
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
    jitter = function(vary, h1, h2){
      return {
        rate: Math.pow(2, (h1 * 2 - 1) * vary / 12),
        gain: 1 - vary * 0.3 * h2
      };
    };
    S.play = function(name, opt){
      var j, ref$, v;
      opt == null && (opt = {});
      S.resume();
      if (Array.isArray(name)) {
        name = name[Math.floor(Math.random() * name.length)];
      }
      if (opt.vary) {
        j = jitter(opt.vary, Math.random(), Math.random());
        opt = (ref$ = import$({}, opt), ref$.rate = (opt.rate || 1) * j.rate, ref$.gain = (opt.gain != null ? opt.gain : 1) * j.gain, ref$);
      }
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
      S.items = items.map(function(it, k){
        var h, j;
        it = import$({}, it);
        if (Array.isArray(it.sound) || it.vary) {
          h = rng(((k + 1) * 2654435761 ^ Math.round((it.t || 0) * 1000) * 40503) >>> 0);
          h();
          if (Array.isArray(it.sound)) {
            it.sound = it.sound[Math.floor(h() * it.sound.length)];
          }
          if (it.vary) {
            j = jitter(it.vary, h(), h());
            it.rate = (it.rate || 1) * j.rate;
            it.gain = (it.gain != null ? it.gain : 1) * j.gain;
          }
        }
        return it;
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
      var P, play, sk, seek;
      if (!L || !L.player || L.player.__sound) {
        return;
      }
      P = L.player.prototype;
      play = P.play;
      sk = P._seek ? '_seek' : 'seek';
      seek = P[sk];
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
      P[sk] = function(t){
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
    coef = function(type, f, q){
      var w, cs, al;
      w = 2 * Math.PI * Math.min(f, SR * 0.49) / SR;
      cs = Math.cos(w);
      al = Math.sin(w) / (2 * q);
      switch (type) {
      case 'lp':
        return [(1 - cs) / 2, 1 - cs, (1 - cs) / 2, 1 + al, -2 * cs, 1 - al];
      case 'hp':
        return [(1 + cs) / 2, -(1 + cs), (1 + cs) / 2, 1 + al, -2 * cs, 1 - al];
      default:
        return [al, 0, -al, 1 + al, -2 * cs, 1 - al];
      }
    };
    biquad = function(d, type, f, q){
      var ref$, b0, b1, b2, a0, a1, a2, x1, x2, y1, y2, i$, to$, i, x, y;
      q == null && (q = 0.707);
      ref$ = coef(type, f, q), b0 = ref$[0], b1 = ref$[1], b2 = ref$[2], a0 = ref$[3], a1 = ref$[4], a2 = ref$[5];
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
    biquadTv = function(d, type, fc, q){
      var n, x1, x2, y1, y2, i$, s, ref$, b0, b1, b2, a0, a1, a2, j$, to$, i, x, y;
      q == null && (q = 0.707);
      n = d.length;
      x1 = x2 = y1 = y2 = 0;
      for (i$ = 0; i$ < n; i$ += 32) {
        s = i$;
        ref$ = coef(type, fc(s / n), q), b0 = ref$[0], b1 = ref$[1], b2 = ref$[2], a0 = ref$[3], a1 = ref$[4], a2 = ref$[5];
        for (j$ = s, to$ = Math.min(n, s + 32); j$ < to$; ++j$) {
          i = j$;
          x = d[i];
          y = (b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2) / a0;
          x2 = x1;
          x1 = x;
          y2 = y1;
          y1 = y;
          d[i] = y;
        }
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
        var r, d, i$, i, v, results$ = [];
        r = rng(o.seed || 3);
        d = biquadTv(noise(n, r), 'bp', function(u){
          if (u < at) {
            return f0 + (f1 - f0) * (u / at);
          } else {
            return f1 + (f2 - f1) * ((u - at) / (1 - at));
          }
        }, q);
        for (i$ = 0; i$ < n; ++i$) {
          i = i$;
          v = i / n;
          d[i] *= v < at
            ? Math.sin(Math.PI / 2 * v / at)
            : Math.cos(Math.PI / 2 * (v - at) / (1 - at));
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
      bright = o.bright != null ? o.bright : 0.6;
      slide = o.slide != null ? o.slide : 0.6;
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
        var r, d, i$, i, u, results$ = [];
        r = rng(o.seed || 23);
        d = biquadTv(noise(n, r), 'bp', function(u){
          return 300 + 3000 * u * u;
        }, 0.9);
        for (i$ = 0; i$ < n; ++i$) {
          i = i$;
          u = i / n;
          results$.push(L[i] = R[i] = d[i] * u * u);
        }
        return results$;
      });
    };
    synth.melody = function(o){
      var seq, rel, dur, inst, voices;
      o == null && (o = {});
      seq = o.notes || [];
      rel = o.release != null ? o.release : 0.8;
      dur = o.dur || Math.max.apply(Math, seq.map(function(x){
        return x[0] + (x[2] || 1.5);
      })) + 1;
      inst = o.instrument || 'pluck';
      if (!synth[inst]) {
        inst = 'pluck';
      }
      voices = seq.map(function(x, k){
        var opt;
        opt = inst === 'pluck'
          ? {
            bright: o.bright,
            slide: o.slide
          }
          : {};
        return [
          x, synth[inst](import$({
            note: x[1],
            dur: (x[2] || 1.5) + rel,
            seed: 31 + k
          }, opt))
        ];
      });
      return make(dur, function(L, R, n){
        var i$, ref$, len$, ref1$, ref2$, t, note, d, vel, b, results$ = [];
        for (i$ = 0, len$ = (ref$ = voices).length; i$ < len$; ++i$) {
          ref1$ = ref$[i$], ref2$ = ref1$[0], t = ref2$[0], note = ref2$[1], d = ref2$[2], vel = ref2$[3], b = ref1$[1];
          results$.push(place(L, R, b, t, vel || 0.8));
        }
        return results$;
      });
    };
    place = function(L, R, b, t, g){
      var l, r_, o0, i$, to$, i, results$ = [];
      g == null && (g = 1);
      l = b.getChannelData(0);
      r_ = b.getChannelData(1);
      o0 = Math.round(t * SR);
      for (i$ = Math.max(0, -o0), to$ = Math.min(l.length, L.length - o0); i$ < to$; ++i$) {
        i = i$;
        L[o0 + i] += l[i] * g;
        results$.push(R[o0 + i] += r_[i] * g);
      }
      return results$;
    };
    partial = function(d, at, f, amp, dec, att){
      var o0, w, i$, to$, i, k, t, a;
      att == null && (att = 0.001);
      if (f >= SR * 0.45) {
        return d;
      }
      o0 = Math.round(at * SR);
      w = 2 * Math.PI * f / SR;
      for (i$ = Math.max(0, o0), to$ = d.length; i$ < to$; ++i$) {
        i = i$;
        k = i - o0;
        t = k / SR;
        a = amp * env(t, att, dec);
        if (t > att && a < 1e-5) {
          break;
        }
        d[i] += a * Math.sin(w * k);
      }
      return d;
    };
    fadeOut = function(d, sec){
      var m, i$, i;
      sec == null && (sec = 0.02);
      m = Math.min(d.length, Math.round(sec * SR));
      for (i$ = 0; i$ < m; ++i$) {
        i = i$;
        d[d.length - 1 - i] *= i / m;
      }
      return d;
    };
    wander = function(n, every, r){
      var step, pts, res$, i$, to$, k, d, i, u;
      step = Math.max(1, Math.round(every * SR));
      res$ = [];
      for (i$ = 0, to$ = Math.ceil(n / step) + 1; i$ <= to$; ++i$) {
        k = i$;
        res$.push(r());
      }
      pts = res$;
      d = new Float32Array(n);
      for (i$ = 0; i$ < n; ++i$) {
        i = i$;
        k = Math.floor(i / step);
        u = (i % step) / step;
        d[i] = pts[k] * (1 - u) + pts[k + 1] * u;
      }
      return d;
    };
    glideOsc = function(n, f0, f1, harm){
      var d, ph, i$, i, j$, len$, k, a;
      harm == null && (harm = [1]);
      d = new Float32Array(n);
      ph = 0;
      for (i$ = 0; i$ < n; ++i$) {
        i = i$;
        ph += 2 * Math.PI * f0 * Math.pow(f1 / f0, i / n) / SR;
        for (j$ = 0, len$ = harm.length; j$ < len$; ++j$) {
          k = j$;
          a = harm[j$];
          d[i] += a * Math.sin(ph * (k + 1));
        }
      }
      return d;
    };
    COMB = [1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617];
    ALLPASS = [556, 441, 341, 225];
    reverb = function(buf, mix, room){
      var k, src, m;
      mix == null && (mix = 0.3);
      room == null && (room = 0.5);
      k = SR / 44100;
      src = [buf.getChannelData(0), buf.getChannelData(1)];
      m = buf.length;
      return make(buf.duration + 0.4 + room * 3, function(L, R, n){
        var fb, damp, input, i$, to$, i, ref$, len$, ch, out, lresult$, wet, j$, ref1$, len1$, c, len, line, idx, filt, k$, y, b, v, dry, results$ = [];
        fb = 0.7 + 0.27 * room;
        damp = 0.3;
        input = new Float32Array(n);
        for (i$ = 0, to$ = m; i$ < to$; ++i$) {
          i = i$;
          input[i] = (src[0][i] + src[1][i]) * 0.015;
        }
        for (i$ = 0, len$ = (ref$ = [L, R]).length; i$ < len$; ++i$) {
          ch = i$;
          out = ref$[i$];
          lresult$ = [];
          wet = new Float32Array(n);
          for (j$ = 0, len1$ = (ref1$ = COMB).length; j$ < len1$; ++j$) {
            c = ref1$[j$];
            len = Math.round((c + ch * 23) * k);
            line = new Float32Array(len);
            idx = 0;
            filt = 0;
            for (k$ = 0; k$ < n; ++k$) {
              i = k$;
              y = line[idx];
              filt = y * (1 - damp) + filt * damp;
              line[idx] = input[i] + filt * fb;
              idx = (idx + 1) % len;
              wet[i] += y;
            }
          }
          for (j$ = 0, len1$ = (ref1$ = ALLPASS).length; j$ < len1$; ++j$) {
            c = ref1$[j$];
            len = Math.round((c + ch * 23) * k);
            line = new Float32Array(len);
            idx = 0;
            for (k$ = 0; k$ < n; ++k$) {
              i = k$;
              b = line[idx];
              v = wet[i];
              line[idx] = v + b * 0.5;
              wet[i] = b - v;
              idx = (idx + 1) % len;
            }
          }
          dry = src[ch];
          for (j$ = 0; j$ < n; ++j$) {
            i = j$;
            lresult$.push(out[i] = (i < m ? dry[i] * (1 - mix * 0.5) : 0) + wet[i] * mix * 3);
          }
          results$.push(lresult$);
        }
        return results$;
      });
    };
    S.reverb = function(buf, o){
      o == null && (o = {});
      return reverb(buf, o.mix != null ? o.mix : 0.3, o.room != null ? o.room : 0.5);
    };
    synth.slide = function(o){
      var dur, f0, f1, q, dir;
      o == null && (o = {});
      dur = o.dur || 0.3;
      f0 = o.from || 900;
      f1 = o.to || 2600;
      q = o.q || 0.9;
      dir = o.dir != null ? o.dir : 1;
      return make(dur, function(L, R, n){
        var d, i$, i, u, a, p, results$ = [];
        d = biquadTv(noise(n, rng(o.seed || 37)), 'bp', function(u){
          return f0 * Math.pow(f1 / f0, u);
        }, q);
        for (i$ = 0; i$ < n; ++i$) {
          i = i$;
          u = i / n;
          a = u < 0.25
            ? Math.sin(Math.PI / 2 * u / 0.25)
            : Math.pow(Math.cos(Math.PI / 2 * (u - 0.25) / 0.75), 2);
          p = (u * 2 - 1) * 0.6 * dir;
          L[i] = d[i] * a * Math.cos((p + 1) * Math.PI / 4);
          results$.push(R[i] = d[i] * a * Math.sin((p + 1) * Math.PI / 4));
        }
        return results$;
      });
    };
    glide = function(o, d0, d1){
      var dur, f0, f1;
      dur = o.dur || 0.6;
      f0 = S.freq(o.from || d0);
      f1 = S.freq(o.to || d1);
      return make(dur, function(L, R, n){
        var d, i$, i, t;
        d = glideOsc(n, f0, f1, [1, 0.25, 0.08]);
        for (i$ = 0; i$ < n; ++i$) {
          i = i$;
          t = i / SR;
          d[i] *= Math.min(1, t / 0.02) * Math.min(1, (dur - t) / (dur * 0.35));
        }
        return pan(L, R, d, o.pan);
      });
    };
    synth.rise = function(o){
      o == null && (o = {});
      return glide(o, 300, 900);
    };
    synth.fall = function(o){
      o == null && (o = {});
      return glide(o, 900, 250);
    };
    synth.count = function(o){
      var cnt, dur, f, climb, ease;
      o == null && (o = {});
      cnt = Math.max(2, o.n || 12);
      dur = o.dur || 1.2;
      f = S.freq(o.note || 'C6');
      climb = o.climb != null ? o.climb : 7;
      ease = (function(){
        switch (o.ease) {
        case 'in':
          return function(u){
            return u * u;
          };
        case 'linear':
          return function(u){
            return u;
          };
        default:
          return function(u){
            return 1 - (1 - u) * (1 - u);
          };
        }
      }());
      return make(dur + 0.2, function(L, R, n){
        var d, i$, to$, k, u, last, ff;
        d = new Float32Array(n);
        for (i$ = 0, to$ = cnt; i$ < to$; ++i$) {
          k = i$;
          u = k / (cnt - 1);
          last = k === cnt - 1;
          ff = f * Math.pow(2, climb * u / 12);
          partial(d, dur * ease(u), ff, last ? 1 : 0.6, last ? 0.09 : 0.02);
          if (last) {
            partial(d, dur, ff * 2, 0.3, 0.06);
          }
        }
        return pan(L, R, d, o.pan);
      });
    };
    synth.snap = function(o){
      o == null && (o = {});
      return make(0.1, function(L, R, n){
        var nz, d, i$, i, t;
        nz = biquad(noise(n, rng(o.seed || 41)), 'lp', 6000);
        d = new Float32Array(n);
        for (i$ = 0; i$ < n; ++i$) {
          i = i$;
          t = i / SR;
          d[i] = 0.8 * nz[i] * env(t, 0.0003, 0.002) + 0.6 * Math.sin(2 * Math.PI * 1400 * t) * env(t, 0.0005, 0.01) + Math.sin(2 * Math.PI * 160 * t) * env(t, 0.001, 0.025);
        }
        return pan(L, R, d, o.pan);
      });
    };
    synth.draw = function(o){
      var dur, rough;
      o == null && (o = {});
      dur = o.dur || 1;
      rough = o.rough != null ? o.rough : 0.5;
      return make(dur, function(L, R, n){
        var r, d, speed, grain, i$, i, t, g;
        r = rng(o.seed || 43);
        d = biquad(biquad(noise(n, r), 'bp', o.pitch || 2500, 0.8), 'hp', 600);
        speed = wander(n, 0.06, r);
        grain = wander(n, 0.004, r);
        for (i$ = 0; i$ < n; ++i$) {
          i = i$;
          t = i / SR;
          g = grain[i] * grain[i];
          d[i] *= (0.3 + 0.7 * speed[i]) * (1 - rough + rough * g * 2) * Math.min(1, t / 0.03, (dur - t) / 0.05);
        }
        return pan(L, R, d, o.pan);
      });
    };
    synth.glitch = function(o){
      var dur;
      o == null && (o = {});
      dur = o.dur || 0.5;
      return make(dur, function(L, R, n){
        var r, i, len, kind, f, hold, p, gl, gr, v, i$, to$, j, t, x, results$ = [];
        r = rng(o.seed || 47);
        i = 0;
        while (i < n) {
          len = Math.round((0.015 + 0.05 * r()) * SR);
          kind = r();
          f = 100 + 1900 * r() * r();
          hold = 1 + Math.floor(r() * 40);
          p = r() * 1.6 - 0.8;
          gl = Math.cos((p + 1) * Math.PI / 4);
          gr = Math.sin((p + 1) * Math.PI / 4);
          v = 0;
          for (i$ = i, to$ = Math.min(n, i + len); i$ < to$; ++i$) {
            j = i$;
            t = (j - i) / SR;
            x = kind < 0.4
              ? Math.sin(2 * Math.PI * f * t) > 0
                ? 0.6
                : -0.6
              : kind < 0.8 ? (j - i) % hold === 0 ? v = r() * 2 - 1 : v : 0;
            L[j] = x * gl;
            R[j] = x * gr;
          }
          results$.push(i += len);
        }
        return results$;
      });
    };
    synth.reveal = function(o){
      var notes, gap;
      o == null && (o = {});
      notes = (o.notes || ['C6', 'E6', 'G6', 'C7', 'E7']).map(S.freq);
      gap = o.gap != null ? o.gap : 0.06;
      return make(1.6, function(L, R, n){
        var d, i$, ref$, len$, k, f, sh, i, t;
        d = new Float32Array(n);
        for (i$ = 0, len$ = (ref$ = notes).length; i$ < len$; ++i$) {
          k = i$;
          f = ref$[i$];
          partial(d, k * gap, f, 1, 0.5);
          partial(d, k * gap, f * 2.76, 0.25, 0.15);
        }
        sh = biquad(noise(n, rng(o.seed || 53)), 'hp', 6000);
        for (i$ = 0; i$ < n; ++i$) {
          i = i$;
          t = i / SR;
          d[i] += sh[i] * 0.12 * env(t, 0.25, 0.3);
        }
        return pan(L, R, d, o.pan);
      });
    };
    synth.reveal.reverb = 0.35;
    synth.error = function(o){
      var notes;
      o == null && (o = {});
      notes = [S.freq(o.from || 'B3'), S.freq(o.to || 'F3')];
      return make(0.5, function(L, R, n){
        var d, i$, ref$, len$, k, f, j$, h;
        d = new Float32Array(n);
        for (i$ = 0, len$ = (ref$ = notes).length; i$ < len$; ++i$) {
          k = i$;
          f = ref$[i$];
          for (j$ = 1; j$ <= 7; j$ += 2) {
            h = j$;
            partial(d, k * 0.16, f * h, 1 / h, 0.12, 0.005);
          }
        }
        fadeOut(biquad(d, 'lp', 2000));
        return pan(L, R, d, o.pan);
      });
    };
    synth.tension = function(o){
      var dur, f;
      o == null && (o = {});
      dur = o.dur || 6;
      f = S.freq(o.note || 'A2');
      return make(dur, function(L, R, n){
        var i$, ref$, len$, k, ratio, d, ph, tp, j$, i, t, u, results$ = [];
        for (i$ = 0, len$ = (ref$ = [1, Math.pow(2, 1 / 12), Math.pow(2, 6 / 12), 2]).length; i$ < len$; ++i$) {
          k = i$;
          ratio = ref$[i$];
          d = new Float32Array(n);
          ph = 0;
          tp = 0;
          for (j$ = 0; j$ < n; ++j$) {
            i = j$;
            t = i / SR;
            u = t / dur;
            tp += 2 * Math.PI * (3 + 5 * u) / SR;
            ph += 2 * Math.PI * f * ratio / SR;
            d[i] = (Math.sin(ph) + 0.3 * Math.sin(ph * 2) + 0.15 * Math.sin(ph * 3)) * (1 - 0.35 * (0.5 + 0.5 * Math.sin(tp + k))) * Math.pow(u, 1.5) * Math.min(1, (dur - t) / 0.3);
          }
          results$.push(pan(L, R, d, (k - 1.5) * 0.4, 0.5));
        }
        return results$;
      });
    };
    synth.heartbeat = function(o){
      var dur, period;
      o == null && (o = {});
      dur = o.dur || 4;
      period = 60 / (o.bpm || 70);
      return make(dur, function(L, R, n){
        var d, t, i$, ref$, len$, ref1$, at, f0, f1, a, m, o0, b, j$, to$, i;
        d = new Float32Array(n);
        t = 0.05;
        while (t < dur - 0.2) {
          for (i$ = 0, len$ = (ref$ = [[0, 75, 45, 1], [Math.min(0.3, period * 0.35), 85, 55, 0.7]]).length; i$ < len$; ++i$) {
            ref1$ = ref$[i$], at = ref1$[0], f0 = ref1$[1], f1 = ref1$[2], a = ref1$[3];
            m = Math.round(0.25 * SR);
            o0 = Math.round((t + at) * SR);
            b = glideOsc(m, f0, f1);
            for (j$ = 0, to$ = Math.min(m, n - o0); j$ < to$; ++j$) {
              i = j$;
              d[o0 + i] += b[i] * a * env(i / SR, 0.008, 0.06);
            }
          }
          t += period;
        }
        return pan(L, R, biquad(d, 'lp', 300), o.pan);
      });
    };
    synth.clock = function(o){
      var dur, period;
      o == null && (o = {});
      dur = o.dur || 4;
      period = 60 / (o.bpm || 60);
      return make(dur, function(L, R, n){
        var d, nz, k, t, f, o0, i$, to$, i;
        d = new Float32Array(n);
        nz = biquad(noise(n, rng(o.seed || 59)), 'hp', 2000);
        k = 0;
        t = 0.02;
        while (t < dur - 0.05) {
          f = k % 2 ? 2400 : 3200;
          partial(d, t, f, 0.6, 0.012);
          partial(d, t, f * 1.5, 0.3, 0.006);
          o0 = Math.round(t * SR);
          for (i$ = 0, to$ = Math.min(Math.round(0.002 * SR), n - o0); i$ < to$; ++i$) {
            i = i$;
            d[o0 + i] += nz[o0 + i] * 0.8;
          }
          t += period;
          k++;
        }
        return pan(L, R, d, o.pan);
      });
    };
    grain = function(L, R, r, at, len, fc, q, amp, p){
      var m, g, o0, gl, gr, i$, to$, i, e, results$ = [];
      p == null && (p = 0);
      m = Math.max(4, Math.round(len * SR));
      g = noise(m, r);
      biquad(g, 'bp', fc, q);
      o0 = Math.round(at * SR);
      gl = Math.cos((p + 1) * Math.PI / 4) * amp;
      gr = Math.sin((p + 1) * Math.PI / 4) * amp;
      for (i$ = 0, to$ = Math.min(m, L.length - o0); i$ < to$; ++i$) {
        i = i$;
        e = Math.exp(-4 * i / m) * Math.min(1, i / 8);
        L[o0 + i] += g[i] * e * gl;
        results$.push(R[o0 + i] += g[i] * e * gr);
      }
      return results$;
    };
    pick = function(r, w){
      var i$, k, u;
      for (i$ = 0; i$ < 50; ++i$) {
        k = i$;
        u = r();
        if (r() < w(u)) {
          return u;
        }
      }
      return r();
    };
    synth.paper = function(o){
      var dur, crisp, flutter, lift, land;
      o == null && (o = {});
      dur = o.dur || 1.2;
      crisp = o.crisp != null ? o.crisp : 1;
      flutter = o.flutter != null ? o.flutter : 0.6;
      lift = dur * 0.2;
      land = dur * 0.8;
      return make(dur, function(L, R, n){
        var r, flip, fl, fl2, i$, ref$, len$, c, ch, p, sl, j$, i, t, shake, a, s, d, to$, k, results$ = [];
        r = rng(o.seed || 61);
        flip = function(t){
          if (t < lift * 0.5 || t > land + 0.02) {
            return 0;
          } else {
            return Math.pow(Math.min(1, (t - lift * 0.5) / (land - lift * 0.5)), 0.7);
          }
        };
        fl = wander(n, 0.035, r);
        fl2 = wander(n, 0.09, r);
        for (i$ = 0, len$ = (ref$ = [L, R]).length; i$ < len$; ++i$) {
          c = i$;
          ch = ref$[i$];
          p = pink(n, r);
          sl = biquad(noise(n, r), 'bp', 4000, 0.7);
          for (j$ = 0; j$ < n; ++j$) {
            i = j$;
            t = i / SR;
            shake = 1 - flutter + flutter * (fl[i] * 0.7 + fl2[i] * 0.6);
            a = flip(t) * shake;
            s = t < lift
              ? Math.sin(Math.PI / 2 * t / lift) * 0.25
              : t < land ? 0.25 * Math.max(0, 1 - (t - lift) / lift) : 0;
            d = t >= land ? env(t - land, 0.006, 0.07) * 1.1 + 0.25 * Math.max(0, 1 - (t - land) / (dur - land)) : 0;
            ch[i] = p[i] * (a * 0.8 + d) + sl[i] * s;
          }
        }
        for (i$ = 0, to$ = Math.round(50 * dur * crisp); i$ < to$; ++i$) {
          k = i$;
          t = lift * 0.5 + (land - lift * 0.5) * pick(r, fn$);
          grain(L, R, r, t, 0.0002 + 0.0008 * r(), 1500 * Math.pow(5, r()), 0.5, (0.1 + r() * r()) * 8, r() * 0.6 - 0.3);
        }
        for (i$ = 0, len$ = (ref$ = [L, R]).length; i$ < len$; ++i$) {
          ch = ref$[i$];
          biquad(ch, 'hp', 150);
          biquad(ch, 'lp', 7500, 0.6);
          results$.push(fadeOut(ch, 0.05));
        }
        return results$;
        function fn$(u){
          return 0.3 + 0.7 * u;
        }
      });
    };
    bubble = function(L, R, at, radius, amp, rise, p, damp){
      var f0, d, m, o0, gl, gr, ph, i$, i, t, v, results$ = [];
      damp == null && (damp = 1);
      f0 = 3000 / radius;
      d = (0.043 * f0 + 0.0014 * Math.pow(f0, 1.5)) * damp;
      m = Math.min(Math.round(6 / d * SR), L.length - Math.round(at * SR));
      o0 = Math.round(at * SR);
      gl = Math.cos((p + 1) * Math.PI / 4) * amp;
      gr = Math.sin((p + 1) * Math.PI / 4) * amp;
      ph = 0;
      for (i$ = 0; i$ < m; ++i$) {
        i = i$;
        t = i / SR;
        ph += 2 * Math.PI * f0 * (1 + rise * d * t) / SR;
        v = Math.sin(ph) * Math.exp(-d * t) * Math.min(1, i / 24);
        L[o0 + i] += v * gl;
        results$.push(R[o0 + i] += v * gr);
      }
      return results$;
    };
    synth.water = function(o){
      var cnt, rise, size, dur;
      o == null && (o = {});
      cnt = o.n || 1;
      rise = o.rise != null
        ? o.rise
        : cnt === 1 ? 0.05 : 0.1;
      size = o.size || (o.freq
        ? 3000 / S.freq(o.freq)
        : cnt === 1 ? 3 : 2.5);
      dur = o.dur || (cnt === 1
        ? 0.4
        : Math.max(1, cnt * 0.04));
      return make(dur, function(L, R, n){
        var r, i$, to$, k, radius, at, results$ = [];
        r = rng(o.seed || 67);
        if (cnt === 1) {
          grain(L, R, r, 0.005, 0.001, 3000, 0.8, 0.25);
          bubble(L, R, 0.007, size, 1, rise, 0, 0.4);
          bubble(L, R, 0.012, size * 0.4, 0.12, rise, 0.1);
          return;
        }
        for (i$ = 0, to$ = cnt; i$ < to$; ++i$) {
          k = i$;
          radius = size * (0.25 + 1.75 * Math.pow(r(), 2.5));
          at = r() * (dur - 0.1);
          results$.push(bubble(L, R, at, radius, Math.pow(radius / size, 0.7) * (0.3 + 0.7 * r()), rise * (0.5 + r()), r() * 1.4 - 0.7));
        }
        return results$;
      });
    };
    synth.fire = function(o){
      var dur, density;
      o == null && (o = {});
      dur = o.dur || 6;
      density = o.density != null ? o.density : 1;
      return make(dur, function(L, R, n){
        var r, bed, hiss, sw, i$, i, a, cnt, k, lresult$, at, amp, len, p, gl, gr, j$, v, results$ = [];
        r = rng(o.seed || 71);
        bed = biquad(noise(n, r), 'lp', 300);
        hiss = biquad(noise(n, r), 'hp', 3000);
        sw = wander(n, 0.25, r);
        for (i$ = 0; i$ < n; ++i$) {
          i = i$;
          a = (0.4 + 0.6 * sw[i]) * Math.min(1, i / SR / 0.3, (n - i) / SR / 0.3);
          L[i] = R[i] = (bed[i] * 0.5 + hiss[i] * 0.04) * a;
        }
        cnt = Math.round(dur * 10 * density);
        for (i$ = 0; i$ < cnt; ++i$) {
          k = i$;
          lresult$ = [];
          at = Math.round(r() * (n - 0.01 * SR));
          amp = r() * r() * 1.5;
          len = Math.round((0.0005 + 0.003 * r()) * SR);
          p = r() * 1.6 - 0.8;
          gl = Math.cos((p + 1) * Math.PI / 4);
          gr = Math.sin((p + 1) * Math.PI / 4);
          for (j$ = 0; j$ < len; ++j$) {
            i = j$;
            v = (r() * 2 - 1) * amp * (1 - i / len);
            L[at + i] += v * gl;
            lresult$.push(R[at + i] += v * gr);
          }
          results$.push(lresult$);
        }
        return results$;
      });
    };
    SURFACE = {
      wood: {
        thud: 1,
        tones: [140, 380, 620],
        click: [[2200, 1.2, 0.012, 0.5]]
      },
      concrete: {
        thud: 0.04,
        tones: [],
        click: [[700, 0.8, 0.003, 1.6], [2600, 1.2, 0.002, 0.15]],
        scuff: 0.06
      },
      gravel: {
        thud: 0.45,
        grains: 90,
        band: [1200, 6000],
        len: [0.0004, 0.002],
        q: 1.5
      },
      snow: {
        thud: 0.35,
        grains: 70,
        band: [500, 2200],
        len: [0.002, 0.007],
        q: 0.8
      },
      grass: {
        thud: 0.25,
        grains: 90,
        band: [2500, 8000],
        len: [0.0005, 0.003],
        q: 1.2
      }
    };
    synth.steps = function(o){
      var run, cnt, pace, sf;
      o == null && (o = {});
      run = o.gait === 'run';
      cnt = o.n || 4;
      pace = o.pace || (run ? 0.3 : 0.5);
      sf = SURFACE[o.surface] || SURFACE.wood;
      return make(cnt * pace + 0.35, function(L, R, n){
        var r, lp, i$, to$, k, lresult$, T, w, p, gl, gr, toe, j$, ref$, len$, ref1$, at, a, o0, m, d, k$, i, t, len1$, f, ref2$, fc, q, dec, amp, c, l$, sc, s, to1$, e, j, f0, f1, l0, l1, results$ = [];
        r = rng(o.seed || 73);
        lp = biquad(noise(n, r), 'lp', 260);
        for (i$ = 0, to$ = cnt; i$ < to$; ++i$) {
          k = i$;
          lresult$ = [];
          T = 0.02 + k * pace + (r() - 0.5) * (run ? 0.01 : 0.02);
          w = (run ? 1.15 : 0.85) + 0.3 * r();
          p = k % 2
            ? 0.12
            : -0.12;
          gl = Math.cos((p + 1) * Math.PI / 4);
          gr = Math.sin((p + 1) * Math.PI / 4);
          toe = run
            ? 0.025 + 0.015 * r()
            : 0.09 + 0.04 * r();
          for (j$ = 0, len$ = (ref$ = run
            ? [[0, w * 0.8], [toe, w]]
            : [[0, w], [toe, w * 0.55]]).length; j$ < len$; ++j$) {
            ref1$ = ref$[j$], at = ref1$[0], a = ref1$[1];
            o0 = Math.round((T + at) * SR);
            m = Math.min(Math.round(0.15 * SR), n - o0);
            d = new Float32Array(m);
            for (k$ = 0; k$ < m; ++k$) {
              i = k$;
              t = i / SR;
              d[i] = lp[o0 + i] * 2.5 * sf.thud * env(t, 0.003, 0.025) + 0.5 * sf.thud * Math.sin(2 * Math.PI * (75 + 20 * a) * t) * env(t, 0.002, 0.03);
            }
            for (k$ = 0, len1$ = (ref1$ = sf.tones || []).length; k$ < len1$; ++k$) {
              f = ref1$[k$];
              partial(d, 0, f * (0.95 + 0.1 * r()), 0.12, 0.035);
            }
            for (k$ = 0, len1$ = (ref1$ = sf.click || []).length; k$ < len1$; ++k$) {
              ref2$ = ref1$[k$], fc = ref2$[0], q = ref2$[1], dec = ref2$[2], amp = ref2$[3];
              c = biquad(noise(m, r), 'bp', fc * (0.85 + 0.3 * r()), q);
              for (l$ = 0; l$ < m; ++l$) {
                i = l$;
                d[i] += c[i] * amp * env(i / SR, 0.0004, dec);
              }
            }
            for (k$ = 0; k$ < m; ++k$) {
              i = k$;
              L[o0 + i] += d[i] * a * gl;
              R[o0 + i] += d[i] * a * gr;
            }
          }
          sc = (sf.scuff || 0.1) * (run ? 2.5 : 1);
          if (sf.scuff || run) {
            o0 = Math.round((T + (run ? toe + 0.03 : 0.02)) * SR);
            s = biquad(noise(Math.round((run ? 0.07 : 0.12) * SR), r), 'bp', 2800, 0.8);
            for (j$ = 0, to1$ = Math.min(s.length, n - o0); j$ < to1$; ++j$) {
              i = j$;
              e = Math.sin(Math.PI * i / s.length) * sc * w * 0.3;
              L[o0 + i] += s[i] * e * gl;
              R[o0 + i] += s[i] * e * gr;
            }
          }
          if (sf.grains) {
            for (j$ = 0, to1$ = Math.round(sf.grains * w); j$ < to1$; ++j$) {
              j = j$;
              at = r() < 0.6
                ? 0.07 * Math.pow(r(), 1.5)
                : toe + 0.09 * Math.pow(r(), 1.5);
              ref$ = sf.band, f0 = ref$[0], f1 = ref$[1];
              ref$ = sf.len, l0 = ref$[0], l1 = ref$[1];
              lresult$.push(grain(L, R, r, T + at, l0 + (l1 - l0) * r(), f0 * Math.pow(f1 / f0, r()), sf.q, (0.15 + r() * r()) * 0.8 * w, p + r() * 0.3 - 0.15));
            }
          }
          results$.push(lresult$);
        }
        return results$;
      });
    };
    synth.bell = function(o){
      var f, dur;
      o == null && (o = {});
      f = S.freq(o.note || 'C5');
      dur = o.dur || 5;
      return make(dur, function(L, R, n){
        var d, i$, ref$, len$, ref1$, ratio, amp, dec;
        d = new Float32Array(n);
        for (i$ = 0, len$ = (ref$ = [[0.5, 0.5, 1], [1, 1, 0.7], [1.2, 0.55, 0.5], [1.5, 0.35, 0.4], [2, 0.6, 0.35], [2.51, 0.25, 0.25], [2.66, 0.2, 0.22], [3.01, 0.18, 0.18], [4.17, 0.1, 0.12], [5.43, 0.06, 0.08]]).length; i$ < len$; ++i$) {
          ref1$ = ref$[i$], ratio = ref1$[0], amp = ref1$[1], dec = ref1$[2];
          partial(d, 0, f * ratio, amp, dec * dur * 0.45, 0.002);
          partial(d, 0, f * ratio * 1.0015, amp * 0.5, dec * dur * 0.45, 0.002);
        }
        return pan(L, R, fadeOut(d, 0.1), o.pan);
      });
    };
    synth.bell.reverb = 0.2;
    pink = function(n, r){
      var d, b0, b1, b2, b3, b4, b5, b6, i$, i, w;
      d = new Float32Array(n);
      b0 = b1 = b2 = b3 = b4 = b5 = b6 = 0;
      for (i$ = 0; i$ < n; ++i$) {
        i = i$;
        w = r() * 2 - 1;
        b0 = 0.99886 * b0 + w * 0.0555179;
        b1 = 0.99332 * b1 + w * 0.0750759;
        b2 = 0.969 * b2 + w * 0.153852;
        b3 = 0.8665 * b3 + w * 0.3104856;
        b4 = 0.55 * b4 + w * 0.5329522;
        b5 = -0.7616 * b5 - w * 0.016898;
        d[i] = (b0 + b1 + b2 + b3 + b4 + b5 + b6 + w * 0.5362) * 0.11;
        b6 = w * 0.115926;
      }
      return d;
    };
    synth.thunder = function(o){
      var dur, dist, near;
      o == null && (o = {});
      dur = o.dur || 6;
      dist = o.dist != null ? o.dist : 0.5;
      near = 1 - dist;
      return make(dur, function(L, R, n){
        var r, t0, cracks, k, rolls, res$, i$, ca, ra, i, t, j$, len$, ref$, at, g, fo, lpf, ch, p, b, to$, results$ = [];
        r = rng(o.seed || 79);
        t0 = 0.02 + dist * 0.4;
        cracks = [[t0, 1]].concat((function(){
          var i$, to$, results$ = [];
          for (i$ = 0, to$ = Math.round(2 + 5 * near); i$ < to$; ++i$) {
            k = i$;
            results$.push([t0 + 0.7 * Math.pow(r(), 1.5), 0.4 + 0.6 * r()]);
          }
          return results$;
        }()));
        res$ = [];
        for (i$ = 0; i$ < 5; ++i$) {
          k = i$;
          res$.push([t0 + 0.3 + r() * dur * 0.5, 0.3 + 0.7 * r()]);
        }
        rolls = res$;
        ca = new Float32Array(n);
        ra = new Float32Array(n);
        for (i$ = 0; i$ < n; ++i$) {
          i = i$;
          t = i / SR;
          for (j$ = 0, len$ = cracks.length; j$ < len$; ++j$) {
            ref$ = cracks[j$], at = ref$[0], g = ref$[1];
            if (t > at) {
              ca[i] += g * env(t - at, 0.004, 0.1 + 0.25 * dist);
            }
          }
          for (j$ = 0, len$ = rolls.length; j$ < len$; ++j$) {
            ref$ = rolls[j$], at = ref$[0], g = ref$[1];
            if (t > at) {
              ra[i] += g * env(t - at, 0.15 + 0.4 * dist, 0.7 + dist);
            }
          }
          fo = Math.min(1, (dur - t) / 0.6);
          ca[i] *= fo;
          ra[i] *= fo;
        }
        lpf = 400 + 11000 * near * near;
        for (i$ = 0, len$ = (ref$ = [L, R]).length; i$ < len$; ++i$) {
          ch = ref$[i$];
          p = biquad(biquad(pink(n, r), 'lp', lpf), 'hp', 30);
          b = biquad(biquad(noise(n, r), 'lp', 140), 'lp', 140);
          for (j$ = 0; j$ < n; ++j$) {
            i = j$;
            ch[i] = p[i] * (ca[i] * (0.4 + 0.6 * near) + ra[i] * 0.8 * near) + b[i] * ra[i] * (0.6 + 0.4 * dist) * 3 + b[i] * ca[i] * 2;
          }
        }
        for (i$ = 0, to$ = Math.round(300 * near * near); i$ < to$; ++i$) {
          k = i$;
          at = t0 + 1.2 * Math.pow(r(), 2);
          results$.push(grain(L, R, r, at, 0.0003 + 0.002 * r(), 800 + 5000 * r(), 1, (0.1 + r() * r()) * near * 0.8, r() * 1.4 - 0.7));
        }
        return results$;
      });
    };
    synth.fingersnap = function(o){
      o == null && (o = {});
      return make(0.12, function(L, R, n){
        var r, tone, d, nz, crack, res, i$, i, t;
        r = rng(o.seed || 137);
        tone = o.tone || 3200;
        d = new Float32Array(n);
        nz = noise(n, r);
        crack = biquad(Float32Array.from(nz), 'hp', 5000);
        res = biquad(Float32Array.from(nz), 'bp', tone, 5);
        for (i$ = 0; i$ < n; ++i$) {
          i = i$;
          t = i / SR;
          d[i] = crack[i] * 2.5 * env(t, 0.0001, 0.0015) + res[i] * 2.2 * env(t, 0.0002, 0.0025);
        }
        partial(d, 0, tone * 1.1, 0.12, 0.004);
        partial(d, 0.0005, 200 + 30 * r(), 0.02, 0.008, 0.001);
        return pan(L, R, d, o.pan);
      });
    };
    formantVoice = function(n, r, size, track){
      var src, ph, jit, tr, i$, s, i, p, f0, v, K, j$, k, a, j, y1, y2, F, B, rr, c, b, k$, to$, y;
      src = new Float32Array(n);
      ph = 0;
      jit = 0;
      tr = [];
      for (i$ = 0; i$ < n; i$ += 32) {
        s = i$;
        tr.push(track(s / n));
      }
      for (i$ = 0; i$ < n; ++i$) {
        i = i$;
        p = tr[i >> 5];
        jit = jit * 0.999 + (r() - 0.5) * 0.002;
        f0 = p.f0 * (1 + 0.006 * Math.sin(2 * Math.PI * 5.2 * i / SR) + jit);
        ph += f0 / SR;
        ph -= Math.floor(ph);
        v = 0;
        if (p.voice > 0) {
          K = Math.min(40, Math.floor(5000 / f0));
          for (j$ = 1; j$ <= K; ++j$) {
            k = j$;
            v += Math.sin(2 * Math.PI * k * ph) / k;
          }
        }
        a = (r() * 2 - 1) * p.asp * (p.voice > 0 ? 0.6 + 0.4 * Math.sin(2 * Math.PI * ph) : 1);
        src[i] = (v * p.voice * 0.35 + a) * p.amp;
      }
      for (i$ = 0; i$ < 4; ++i$) {
        j = i$;
        y1 = y2 = 0;
        for (j$ = 0; j$ < n; j$ += 32) {
          s = j$;
          F = tr[s >> 5].F[j] * size;
          B = 60 + F * 0.06;
          rr = Math.exp(-Math.PI * B / SR);
          c = -rr * rr;
          b = 2 * rr * Math.cos(2 * Math.PI * F / SR);
          a = 1 - b - c;
          for (k$ = s, to$ = Math.min(n, s + 32); k$ < to$; ++k$) {
            i = k$;
            y = a * src[i] + b * y1 + c * y2;
            y2 = y1;
            y1 = y;
            src[i] = y;
          }
        }
      }
      return src;
    };
    mix = function(a, b, u){
      return a + (b - a) * u;
    };
    ease = function(u){
      return u * u * (3 - 2 * u);
    };
    synth.huh = function(o){
      var dur, f0, rise, size, h;
      o == null && (o = {});
      dur = o.dur || 0.45;
      f0 = o.pitch || 200;
      rise = o.rise || 1.9;
      size = o.size || 1;
      h = 0.08 / dur;
      return make(dur, function(L, R, n){
        var r, d;
        r = rng(o.seed || 151);
        d = formantVoice(n, r, size, function(u){
          var v, w, amp;
          v = Math.max(0, Math.min(1, (u - h) / 0.08));
          w = Math.max(0, (u - h) / (1 - h));
          amp = Math.min(1, u / 0.06) * (u > 0.75 ? Math.max(0, 1 - (u - 0.75) / 0.25) : 1);
          return {
            f0: f0 * mix(1, rise, Math.pow(w, 1.6)),
            voice: v,
            asp: 0.35 * (1 - v) + 0.06,
            amp: amp,
            F: [mix(700, 850, v), 1250, 2700, 3600]
          };
        });
        fadeOut(d, 0.03);
        return pan(L, R, d, o.pan);
      });
    };
    synth.yay = function(o){
      var dur, f0, size;
      o == null && (o = {});
      dur = o.dur || 0.5;
      f0 = o.pitch || 300;
      size = o.size || 1;
      return make(dur, function(L, R, n){
        var r, d;
        r = rng(o.seed || 157);
        d = formantVoice(n, r, size, function(u){
          var g, amp, pc;
          g = ease(Math.min(1, u / 0.25));
          amp = Math.min(1, u / 0.04) * (u > 0.7 ? Math.max(0, 1 - (u - 0.7) / 0.3) : 1);
          pc = u < 0.35
            ? mix(0.88, 1.12, ease(u / 0.35))
            : mix(1.12, 0.85, ease((u - 0.35) / 0.65));
          return {
            f0: f0 * pc,
            voice: 1,
            asp: 0.05,
            amp: amp,
            F: [mix(320, 660, g), mix(2600, 1850, g), mix(3200, 2650, g), 3800]
          };
        });
        fadeOut(d, 0.03);
        return pan(L, R, d, o.pan);
      });
    };
    synth.correct = function(o){
      var arp, notes, gap;
      o == null && (o = {});
      arp = o.style === 'arp';
      notes = (o.notes || (arp
        ? ['C6', 'E6', 'G6', 'C7']
        : ['B5', 'G5'])).map(S.freq);
      gap = o.gap || (arp ? 0.07 : 0.2);
      return make(notes.length * gap + 1.1, function(L, R, n){
        var d, i$, ref$, len$, k, f, last, dec, sh, i;
        d = new Float32Array(n);
        for (i$ = 0, len$ = (ref$ = notes).length; i$ < len$; ++i$) {
          k = i$;
          f = ref$[i$];
          last = k === notes.length - 1;
          dec = last
            ? 0.45
            : arp ? 0.15 : 0.25;
          partial(d, k * gap, f, 1, dec, 0.002);
          partial(d, k * gap, f * 2, 0.25, dec * 0.4, 0.002);
          partial(d, k * gap, f * 3.01, 0.08, dec * 0.25, 0.002);
        }
        if (arp) {
          sh = biquad(noise(n, rng(o.seed || 163)), 'hp', 7000);
          for (i$ = 0; i$ < n; ++i$) {
            i = i$;
            d[i] += sh[i] * 0.08 * env(i / SR - notes.length * gap * 0.6, 0.1, 0.25) * (i / SR > notes.length * gap * 0.6 - 0.1 ? 1 : 0);
          }
        }
        return pan(L, R, fadeOut(d, 0.05), o.pan);
      });
    };
    synth.correct.reverb = 0.15;
    synth.wrong = function(o){
      var notes, f;
      o == null && (o = {});
      if (o.style === 'trombone') {
        notes = ['D4', 'C#4', 'C4', 'B3'].map(S.freq);
        return make(2.2, function(L, R, n){
          var d, ph, i$, i, t, k, lt, f, p, a, b2;
          d = new Float32Array(n);
          ph = 0;
          for (i$ = 0; i$ < n; ++i$) {
            i = i$;
            t = i / SR;
            k = Math.min(3, Math.floor(t / 0.42));
            lt = t - k * 0.42;
            f = notes[k] * (k === 3 ? 1 + 0.025 * Math.sin(2 * Math.PI * 5.5 * Math.max(0, lt - 0.15)) : 1) * (1 - 0.03 * Math.min(1, lt / 0.3));
            ph += f / SR;
            p = ph % 1;
            a = k < 3
              ? Math.min(1, lt / 0.04) * Math.max(0, 1 - Math.max(0, lt - 0.3) / 0.08)
              : Math.min(1, lt / 0.04) * Math.max(0, 1 - lt / 0.95);
            d[i] = (2 * p - 1) * a;
          }
          biquad(d, 'lp', 1400, 0.9);
          b2 = biquad(Float32Array.from(d), 'bp', 1200, 2);
          for (i$ = 0; i$ < n; ++i$) {
            i = i$;
            d[i] += b2[i] * 0.5;
          }
          return pan(L, R, fadeOut(d, 0.05), o.pan);
        });
      }
      f = o.pitch || 140;
      return make(0.75, function(L, R, n){
        var d, p1, p2, i$, i, t, a;
        d = new Float32Array(n);
        p1 = 0;
        p2 = 0;
        for (i$ = 0; i$ < n; ++i$) {
          i = i$;
          t = i / SR;
          a = t < 0.13
            ? Math.min(1, t / 0.005) * Math.min(1, (0.13 - t) / 0.01)
            : t > 0.19 ? Math.min(1, (t - 0.19) / 0.005) * Math.min(1, (0.72 - t) / 0.03) : 0;
          p1 += f / SR;
          p2 += f * 1.012 / SR;
          d[i] = ((p1 % 1 < 0.5
            ? 1
            : -1) + (p2 % 1 < 0.5
            ? 1
            : -1)) * 0.5 * Math.max(0, a);
        }
        biquad(d, 'lp', 2500);
        return pan(L, R, d, o.pan);
      });
    };
    bar = function(o, cfg){
      var f, dur, hard, base;
      f = S.freq(o.note || cfg.note);
      dur = o.dur || cfg.dur;
      hard = o.hard != null ? o.hard : 0.5;
      base = cfg.decay * Math.pow(S.freq(cfg.note) / f, 0.4);
      return make(dur, function(L, R, n){
        var d, i$, ref$, len$, k, ratio, depth, i, m, to$;
        d = new Float32Array(n);
        for (i$ = 0, len$ = (ref$ = cfg.ratios).length; i$ < len$; ++i$) {
          k = i$;
          ratio = ref$[i$];
          partial(d, 0, f * ratio, cfg.amps[k] * (k ? 0.3 + 1.4 * hard : 1), base / (1 + k * cfg.damp), 0.0015);
        }
        if (cfg.trem) {
          depth = o.trem != null ? o.trem : 0.35;
          for (i$ = 0; i$ < n; ++i$) {
            i = i$;
            d[i] *= 1 - depth * (0.5 + 0.5 * Math.sin(2 * Math.PI * 5.5 * i / SR));
          }
        }
        m = biquad(noise(Math.round(0.008 * SR), rng(o.seed || 83)), 'lp', 2000 + 6000 * hard);
        for (i$ = 0, to$ = m.length; i$ < to$; ++i$) {
          i = i$;
          d[i] += m[i] * 0.4 * hard * (1 - i / m.length);
        }
        return pan(L, R, fadeOut(d), o.pan);
      });
    };
    synth.marimba = function(o){
      o == null && (o = {});
      return bar(o, {
        note: 'C4',
        dur: 1.5,
        ratios: [1, 3.93, 9.24],
        amps: [1, 0.3, 0.1],
        decay: 0.45,
        damp: 2.5
      });
    };
    synth.xylophone = function(o){
      o == null && (o = {});
      return bar(o, {
        note: 'C5',
        dur: 0.8,
        ratios: [1, 3, 6.1],
        amps: [1, 0.5, 0.2],
        decay: 0.2,
        damp: 1.5
      });
    };
    synth.vibraphone = function(o){
      o == null && (o = {});
      return bar(o, {
        note: 'F4',
        dur: 3,
        ratios: [1, 4, 10],
        amps: [1, 0.25, 0.08],
        decay: 1.4,
        damp: 3,
        trem: true
      });
    };
    synth.glockenspiel = function(o){
      o == null && (o = {});
      return bar(o, {
        note: 'C6',
        dur: 2,
        ratios: [1, 2.76, 5.4, 8.93],
        amps: [1, 0.4, 0.2, 0.08],
        decay: 0.9,
        damp: 1.2
      });
    };
    CHORDS = {
      C: ['C3', 'E3', 'G3', 'C4', 'E4'],
      D: ['D3', 'A3', 'D4', 'F#4'],
      Dm: ['D3', 'A3', 'D4', 'F4'],
      E: ['E2', 'B2', 'E3', 'G#3', 'B3', 'E4'],
      Em: ['E2', 'B2', 'E3', 'G3', 'B3', 'E4'],
      F: ['F2', 'C3', 'F3', 'A3', 'C4', 'F4'],
      G: ['G2', 'B2', 'D3', 'G3', 'B3', 'G4'],
      A: ['A2', 'E3', 'A3', 'C#4', 'E4'],
      Am: ['A2', 'E3', 'A3', 'C4', 'E4']
    };
    string = function(f, n, o, r){
      var bright, mute, s, period, size, exc, p, i$, i, a, y, sustain, g, line, d, to$, k, j, j0, fr, a1, b1;
      bright = o.bright != null ? o.bright : 0.5;
      mute = o.mute || 0;
      s = 0.5 + 0.45 * bright * (1 - mute);
      period = SR / f - (1 - s);
      size = Math.ceil(period) + 3;
      exc = noise(size, r);
      p = Math.max(1, Math.round(period * (o.pos || 0.2)));
      for (i$ = size - 1; i$ >= p; --i$) {
        i = i$;
        exc[i] -= exc[i - p];
      }
      a = 0.15 + 0.8 * bright * (1 - mute * 0.7);
      y = 0;
      for (i$ = 0; i$ < size; ++i$) {
        i = i$;
        y = a * exc[i] + (1 - a) * y;
        exc[i] = y;
      }
      sustain = (o.sustain || 4) * (1 - 0.92 * mute);
      g = Math.pow(0.001, 1 / (f * sustain));
      line = new Float32Array(n + size);
      for (i$ = 0; i$ < size; ++i$) {
        i = i$;
        line[i] = exc[i];
      }
      d = new Float32Array(n);
      for (i$ = size, to$ = n + size; i$ < to$; ++i$) {
        k = i$;
        j = k - period;
        j0 = Math.floor(j);
        fr = j - j0;
        a1 = line[j0] * (1 - fr) + line[j0 + 1] * fr;
        b1 = line[j0 - 1] * (1 - fr) + line[j0] * fr;
        line[k] = g * (s * a1 + (1 - s) * b1);
        d[k - size] = line[k];
      }
      return d;
    };
    synth.guitar = function(o){
      var notes, dur, gap;
      o == null && (o = {});
      notes = o.notes || CHORDS[o.chord] || [o.note || 'E3'];
      if (o.dir === 'up') {
        notes = notes.slice().reverse();
      }
      dur = o.dur || 3;
      gap = o.strum != null ? o.strum : 0.03;
      return make(dur, function(L, R, n){
        var r, i$, ref$, len$, k, note, lresult$, at, d, body, body2, j$, to$, i, p, gl, gr, results$ = [];
        r = rng(o.seed || 89);
        for (i$ = 0, len$ = (ref$ = notes).length; i$ < len$; ++i$) {
          k = i$;
          note = ref$[i$];
          lresult$ = [];
          at = Math.round(k * gap * SR);
          d = string(S.freq(note), n - at, o, r);
          body = biquad(Float32Array.from(d), 'bp', 105, 1.5);
          body2 = biquad(Float32Array.from(d), 'bp', 220, 2);
          for (j$ = 0, to$ = d.length; j$ < to$; ++j$) {
            i = j$;
            d[i] = d[i] + body[i] * 0.6 + body2[i] * 0.3;
          }
          fadeOut(d, 0.05);
          p = (o.pan || 0) + (k / Math.max(1, notes.length - 1) - 0.5) * 0.3;
          gl = Math.cos((p + 1) * Math.PI / 4);
          gr = Math.sin((p + 1) * Math.PI / 4);
          for (j$ = 0, to$ = d.length; j$ < to$; ++j$) {
            i = j$;
            L[at + i] += d[i] * gl;
            lresult$.push(R[at + i] += d[i] * gr);
          }
          results$.push(lresult$);
        }
        return results$;
      });
    };
    synth.kick = function(o){
      var f1, dec, punch;
      o == null && (o = {});
      f1 = o.tune || 50;
      dec = o.decay || 0.3;
      punch = o.punch != null ? o.punch : 0.5;
      return make(dec * 2 + 0.05, function(L, R, n){
        var d, ph, ck, i$, i, t;
        d = new Float32Array(n);
        ph = 0;
        ck = biquad(noise(n, rng(o.seed || 97)), 'lp', 4000);
        for (i$ = 0; i$ < n; ++i$) {
          i = i$;
          t = i / SR;
          ph += 2 * Math.PI * (f1 + f1 * 2 * Math.exp(-t / 0.03)) / SR;
          d[i] = Math.tanh((Math.sin(ph) * env(t, 0.001, dec) + ck[i] * punch * 0.6 * env(t, 0.0002, 0.003)) * (1 + 2 * punch));
        }
        return pan(L, R, fadeOut(d), o.pan);
      });
    };
    synth.snare = function(o){
      var f, dec, snappy;
      o == null && (o = {});
      f = o.tune || 180;
      dec = o.decay || 0.15;
      snappy = o.snappy != null ? o.snappy : 0.6;
      return make(dec * 2 + 0.05, function(L, R, n){
        var d, nz, i$, i;
        d = new Float32Array(n);
        partial(d, 0, f, 0.8, 0.05);
        partial(d, 0, f * 1.83, 0.4, 0.035);
        nz = biquad(biquad(noise(n, rng(o.seed || 101)), 'hp', 1200), 'lp', 9000);
        for (i$ = 0; i$ < n; ++i$) {
          i = i$;
          d[i] += nz[i] * snappy * 1.2 * env(i / SR, 0.001, dec * 0.8);
        }
        return pan(L, R, fadeOut(d), o.pan);
      });
    };
    metal = function(n, scale){
      var d, i$, ref$, len$, f, w, ph, j$, i;
      scale == null && (scale = 1);
      d = new Float32Array(n);
      for (i$ = 0, len$ = (ref$ = [205.3, 304.4, 369.6, 522.7, 540, 800]).length; i$ < len$; ++i$) {
        f = ref$[i$];
        w = f * scale / SR;
        ph = 0;
        for (j$ = 0; j$ < n; ++j$) {
          i = j$;
          ph += w;
          d[i] += ph % 1 < 0.5
            ? 1
            : -1;
        }
      }
      return d;
    };
    synth.hihat = function(o){
      var open, dec;
      o == null && (o = {});
      open = o.open || 0;
      dec = 0.04 + open * 0.5;
      return make(dec * 2.5 + 0.02, function(L, R, n){
        var m, nz, d, i$, i;
        m = metal(n, o.tune || 1);
        nz = noise(n, rng(o.seed || 103));
        d = new Float32Array(n);
        for (i$ = 0; i$ < n; ++i$) {
          i = i$;
          d[i] = m[i] * 0.15 + nz[i] * 0.5;
        }
        biquad(biquad(d, 'hp', 7000), 'bp', 10000, 0.8);
        for (i$ = 0; i$ < n; ++i$) {
          i = i$;
          d[i] *= env(i / SR, 0.0008, dec);
        }
        return pan(L, R, fadeOut(d), o.pan);
      });
    };
    synth.tom = function(o){
      var f, dec;
      o == null && (o = {});
      f = S.freq(o.note || 'A2');
      dec = o.decay || 0.35;
      return make(dec * 2 + 0.05, function(L, R, n){
        var d, ph, nz, i$, i, t;
        d = new Float32Array(n);
        ph = 0;
        nz = biquad(noise(n, rng(o.seed || 107)), 'bp', f * 4, 1);
        for (i$ = 0; i$ < n; ++i$) {
          i = i$;
          t = i / SR;
          ph += 2 * Math.PI * f * (1 + 0.5 * Math.exp(-t / 0.04)) / SR;
          d[i] = Math.sin(ph) * env(t, 0.002, dec) + nz[i] * 0.3 * env(t, 0.001, 0.02);
        }
        return pan(L, R, fadeOut(d), o.pan);
      });
    };
    synth.clap = function(o){
      var dec;
      o == null && (o = {});
      dec = o.decay || 0.12;
      return make(dec * 2.5 + 0.06, function(L, R, n){
        var nz, d, i$, i, t, a, j$, ref$, len$, at;
        nz = biquad(noise(n, rng(o.seed || 109)), 'bp', 1100, 1.2);
        d = new Float32Array(n);
        for (i$ = 0; i$ < n; ++i$) {
          i = i$;
          t = i / SR;
          a = 0;
          for (j$ = 0, len$ = (ref$ = [0, 0.011, 0.022]).length; j$ < len$; ++j$) {
            at = ref$[j$];
            if (t >= at) {
              a += env(t - at, 0.0005, 0.006);
            }
          }
          if (t >= 0.031) {
            a += env(t - 0.031, 0.001, dec);
          }
          d[i] = nz[i] * a;
        }
        L.set(d);
        return R.set(biquad(Float32Array.from(d), 'bp', 1300, 1.5));
      });
    };
    ring = function(d, at, f, a, tau, att){
      var o0, g, w, c, s, x, y, A, an, i$, to$, i, k, t, results$ = [];
      att == null && (att = 0.0005);
      if (f >= SR * 0.45) {
        return;
      }
      o0 = Math.round(at * SR);
      g = Math.exp(-1 / (tau * SR));
      w = 2 * Math.PI * f / SR;
      c = Math.cos(w);
      s = Math.sin(w);
      x = 1;
      y = 0;
      A = a;
      an = Math.max(1, Math.round(att * SR));
      for (i$ = o0, to$ = d.length; i$ < to$; ++i$) {
        i = i$;
        k = i - o0;
        d[i] += y * A * (k < an ? k / an : 1);
        t = x * c - y * s;
        y = x * s + y * c;
        x = t;
        A *= g;
        if (A < 1e-5) {
          break;
        }
      }
      return results$;
    };
    gauss = function(r){
      return Math.sqrt(-2 * Math.log(r() + 1e-12)) * Math.cos(2 * Math.PI * r());
    };
    synth.crash = function(o){
      var dec, tune;
      o == null && (o = {});
      dec = o.decay || 1;
      tune = o.tune || 1;
      return make(2.4 * dec + 0.1, function(L, R, n){
        var r, i$, ref$, len$, ch, j$, k, f, nz, sh, i, t, results$ = [];
        r = rng(o.seed || 113);
        for (i$ = 0, len$ = (ref$ = [L, R]).length; i$ < len$; ++i$) {
          ch = ref$[i$];
          for (j$ = 0; j$ < 260; ++j$) {
            k = j$;
            f = Math.max(1200, Math.min(14000, 4200 * Math.pow(2, 0.55 * gauss(r)))) * tune;
            ring(ch, 0, f, (0.4 + r()) / 16, 0.3 * dec * Math.pow(f / 4200 / tune, -0.8) * (0.6 + 0.8 * r()), 0.002 + 0.07 * r() * Math.min(1, f / 4200 / tune));
          }
          for (j$ = 0; j$ < 30; ++j$) {
            k = j$;
            ring(ch, 0, 350 * tune * Math.pow(3, r()), (0.3 + r()) / 14, 0.5 * dec * (0.6 + 0.8 * r()), 0.003);
          }
          nz = biquad(noise(n, r), 'lp', 9000);
          sh = biquad(noise(n, r), 'bp', 4200 * tune, 0.8);
          for (j$ = 0; j$ < n; ++j$) {
            i = j$;
            t = i / SR;
            ch[i] += nz[i] * 0.4 * env(t, 0.0005, 0.008) + sh[i] * 0.1 * env(t, 0.03, 0.3 * dec);
          }
          biquad(ch, 'hp', 250);
          results$.push(fadeOut(ch, 0.1));
        }
        return results$;
      });
    };
    synth.ride = function(o){
      var dec, tune, bell;
      o == null && (o = {});
      dec = o.decay || 1;
      tune = o.tune || 1;
      bell = o.bell || 0;
      return make(4 * dec + 0.1, function(L, R, n){
        var r, st, i$, ref$, len$, ch, j$, to$, i, k, f, sh, results$ = [];
        r = rng(o.seed || 127);
        st = biquad(noise(n, r), 'bp', 4800 * tune, 0.7);
        for (i$ = 0, len$ = (ref$ = [L, R]).length; i$ < len$; ++i$) {
          ch = ref$[i$];
          for (j$ = 0, to$ = Math.round(0.05 * SR); j$ < to$; ++j$) {
            i = j$;
            ch[i] += st[i] * 0.9 * env(i / SR, 0.0003, 0.006);
          }
          for (j$ = 0; j$ < 40; ++j$) {
            k = j$;
            ring(ch, 0, (5000 + 4000 * r()) * tune, 0.04, 0.015 + 0.03 * r());
          }
          for (j$ = 0; j$ < 180; ++j$) {
            k = j$;
            f = Math.max(700, Math.min(10000, 2600 * Math.pow(2, 0.55 * gauss(r)))) * tune;
            ring(ch, 0, f, (0.4 + r()) / 80, 0.9 * dec * Math.pow(f / 2600 / tune, -0.3) * (0.6 + 0.8 * r()), 0.001);
          }
          sh = biquad(noise(n, r), 'bp', 3000 * tune, 0.7);
          for (j$ = 0; j$ < n; ++j$) {
            i = j$;
            ch[i] += sh[i] * 0.05 * env(i / SR, 0.002, 0.35 * dec);
          }
          if (bell) {
            for (j$ = 0; j$ < 14; ++j$) {
              k = j$;
              f = 2800 * tune * Math.pow(2, 0.4 * gauss(r));
              ring(ch, 0, f, bell * (0.5 + r()) / 6, 0.5 * dec * (0.6 + 0.8 * r()), 0.001);
            }
          }
          biquad(ch, 'hp', 400);
          results$.push(fadeOut(ch, 0.1));
        }
        return results$;
      });
    };
    KIT = {
      kick: ['kick', {}, 1],
      snare: ['snare', {}, 0.9],
      hihat: ['hihat', {}, 0.45],
      ohat: [
        'hihat', {
          open: 0.6
        }, 0.45
      ],
      tom: ['tom', {}, 0.8],
      ltom: [
        'tom', {
          note: 'E2'
        }, 0.8
      ],
      htom: [
        'tom', {
          note: 'D3'
        }, 0.8
      ],
      clap: ['clap', {}, 0.8],
      crash: ['crash', {}, 0.55],
      ride: ['ride', {}, 0.4]
    };
    VEL = {
      X: 1,
      x: 0.75,
      o: 0.4
    };
    synth.beat = function(o){
      var step, bars, swing, pat, hits, steps, tail, name, def, ref$, str, opt, kind, base, g, b, s, total;
      o == null && (o = {});
      step = 60 / (o.bpm || 100) / 4;
      bars = o.bars || 1;
      swing = o.swing || 0;
      pat = o.pattern || {
        kick: 'x...x...x...x...',
        snare: '....x.......x...',
        hihat: 'x.x.x.x.x.x.x.x.'
      };
      hits = [];
      steps = 0;
      tail = 0;
      for (name in pat) {
        def = pat[name];
        ref$ = Array.isArray(def)
          ? def
          : [def], str = ref$[0], opt = ref$[1];
        opt = opt || {};
        ref$ = KIT[name] || [name, {}, 0.8], kind = ref$[0], base = ref$[1], g = ref$[2];
        if (!synth[kind]) {
          continue;
        }
        b = synth[kind](import$(import$({}, base), opt));
        tail = Math.max(tail, b.duration);
        s = (str || '').replace(/[\s|]/g, '');
        steps = Math.max(steps, s.length);
        hits.push({
          b: b,
          s: s,
          g: opt.gain != null ? opt.gain : g
        });
      }
      total = steps * bars;
      return make(Math.max(0.1, total * step + tail), function(L, R, n){
        var i$, ref$, len$, ref1$, b, s, g, lresult$, j$, to$, k, v, results$ = [];
        for (i$ = 0, len$ = (ref$ = hits).length; i$ < len$; ++i$) {
          ref1$ = ref$[i$], b = ref1$.b, s = ref1$.s, g = ref1$.g;
          lresult$ = [];
          for (j$ = 0, to$ = total; j$ < to$; ++j$) {
            k = j$;
            v = VEL[s[k % steps]];
            if (!v) {
              continue;
            }
            lresult$.push(place(L, R, b, k * step + (k % 2 ? swing * step * 0.5 : 0), v * g));
          }
          results$.push(lresult$);
        }
        return results$;
      });
    };
    synth.sweep = function(o){
      var dur, f0, f1, att, rel, fu;
      o == null && (o = {});
      dur = o.dur || 1;
      f0 = S.freq(o.from || 200);
      f1 = S.freq(o.to || 2000);
      att = o.attack != null ? o.attack : 0.01;
      rel = o.release != null ? o.release : 0.1;
      fu = o.curve === 'lin'
        ? function(u){
          return f0 + (f1 - f0) * u;
        }
        : function(u){
          return f0 * Math.pow(f1 / f0, u);
        };
      return make(dur, function(L, R, n){
        var d, x, ph, i, p, i$, t;
        d = o.wave === 'noise'
          ? biquadTv(noise(n, rng(o.seed || 131)), 'bp', fu, o.q || 2)
          : (x = new Float32Array(n), ph = 0, (function(){
            var i$, to$, results$ = [];
            for (i$ = 0, to$ = n; i$ < to$; ++i$) {
              i = i$;
              ph += fu(i / n) / SR;
              p = ph % 1;
              results$.push(x[i] = (fn$()));
            }
            return results$;
            function fn$(){
              switch (o.wave) {
              case 'square':
                if (p < 0.5) {
                  return 0.6;
                } else {
                  return -0.6;
                }
              case 'saw':
                return (2 * p - 1) * 0.6;
              case 'triangle':
                return 1 - 4 * Math.abs(p - 0.5);
              default:
                return Math.sin(2 * Math.PI * p);
              }
            }
          }()), x);
        for (i$ = 0; i$ < n; ++i$) {
          i = i$;
          t = i / SR;
          d[i] *= Math.min(1, t / Math.max(0.001, att), (dur - t) / Math.max(0.001, rel));
        }
        return pan(L, R, d, o.pan);
      });
    };
    parseScore = function(text){
      var beats, out, i$, ref$, len$, tok, m, b, notes, ref1$, j$, len1$, nm;
      text == null && (text = '');
      beats = 1;
      out = [];
      for (i$ = 0, len$ = (ref$ = text.split(/\s+/)).length; i$ < len$; ++i$) {
        tok = ref$[i$];
        if (tok && tok !== '|') {
          m = /^([^\/]+?)(?:\/(\d+))?(\.*)$/.exec(tok);
          if (!m) {
            throw new Error("看不懂的樂譜: " + tok);
          }
          if (m[2]) {
            beats = 4 / +m[2];
          }
          b = beats * (m[3].length === 1
            ? 1.5
            : m[3].length >= 2 ? 1.75 : 1);
          notes = (ref1$ = m[1]) === '-' || ref1$ === 'r' || ref1$ === 'R'
            ? []
            : m[1].split('+');
          for (j$ = 0, len1$ = notes.length; j$ < len1$; ++j$) {
            nm = notes[j$];
            if (!/^[A-G](#|b)?-?\d$/.test(nm)) {
              throw new Error("看不懂的音名: " + nm);
            }
          }
          out.push({
            notes: notes,
            beats: b
          });
        }
      }
      return out;
    };
    S.score = function(text, o){
      var spb, t, out, i$, ref$, len$, x, j$, ref1$, len1$, nm;
      o == null && (o = {});
      spb = 60 / (o.bpm || 100);
      t = 0;
      out = [];
      for (i$ = 0, len$ = (ref$ = parseScore(text)).length; i$ < len$; ++i$) {
        x = ref$[i$];
        for (j$ = 0, len1$ = (ref1$ = x.notes).length; j$ < len1$; ++j$) {
          nm = ref1$[j$];
          out.push([+(t * spb).toFixed(4), nm, +(x.beats * spb * 0.92).toFixed(4)]);
        }
        t += x.beats;
      }
      return out;
    };
    S.score.parse = parseScore;
    S.score.duration = function(text, o){
      o == null && (o = {});
      return parseScore(text).reduce(function(a, x){
        return a + x.beats;
      }, 0) * 60 / (o.bpm || 100);
    };
    TWINKLE = 'C4/4 C4 G4 G4 | A4 A4 G4/2 | F4/4 F4 E4 E4 | D4 D4 C4/2';
    synth.score = function(o){
      var text, notes, total, inst, rel, pitched, src, base, cache;
      o == null && (o = {});
      text = o.score || TWINKLE;
      notes = S.score(text, {
        bpm: o.bpm
      });
      total = S.score.duration(text, {
        bpm: o.bpm
      });
      inst = o.instrument || 'pluck';
      rel = o.release != null ? o.release : 0.1;
      pitched = typeof inst === 'string' && S.params[inst] && S.params[inst].some(function(p){
        return p.k === 'note';
      });
      if (pitched) {
        return synth.melody({
          notes: notes,
          instrument: inst,
          release: rel,
          dur: total + rel + 1
        });
      }
      src = isBuffer(inst)
        ? inst
        : synth[inst]
          ? synth[inst]({})
          : synth.pluck({});
      base = S.freq(o.base || 'C4');
      cache = {};
      return make(total + src.duration * 2 + 0.1, function(L, R, n){
        var i$, ref$, len$, ref1$, t, nm, ratio, results$ = [];
        for (i$ = 0, len$ = (ref$ = notes).length; i$ < len$; ++i$) {
          ref1$ = ref$[i$], t = ref1$[0], nm = ref1$[1];
          ratio = S.freq(nm) / base;
          cache[nm] == null && (cache[nm] = resample(src, ratio, 1));
          results$.push(place(L, R, cache[nm], t, 0.8));
        }
        return results$;
      });
    };
    resample = function(buf, rate, gain){
      var src, m, n, out, i$, ch, d, x, j$, i, p, j, f;
      src = [buf.getChannelData(0), buf.getChannelData(1)];
      m = buf.length;
      n = Math.max(1, Math.round(m / rate));
      out = new AudioBuffer({
        length: n,
        sampleRate: SR,
        numberOfChannels: 2
      });
      for (i$ = 0; i$ < 2; ++i$) {
        ch = i$;
        d = new Float32Array(n);
        x = src[ch];
        for (j$ = 0; j$ < n; ++j$) {
          i = j$;
          p = i * rate;
          j = Math.floor(p);
          f = p - j;
          d[i] = ((x[j] || 0) * (1 - f) + (x[j + 1] || 0) * f) * gain;
        }
        out.copyToChannel(d, ch);
      }
      return out;
    };
    wrap = function(fn){
      return function(o){
        var v, j, b, ref$, mix;
        o == null && (o = {});
        if (o.vary) {
          v = rng((o.seed || 1) * 7919 + 13);
          j = jitter(o.vary, v(), v());
          b = fn((ref$ = import$({}, o), ref$.seed = (o.seed || 1) * 1009 + 1 + Math.floor(v() * 1e5), ref$));
          b = resample(b, j.rate, j.gain);
        } else {
          b = fn(o);
        }
        mix = o.reverb != null
          ? o.reverb
          : fn.reverb || 0;
        if (mix > 0) {
          return reverb(b, mix, o.room != null ? o.room : 0.5);
        } else {
          return b;
        }
      };
    };
    for (k in synth) {
      synth[k] = wrap(synth[k]);
    }
    S.variants = function(name, opt, count){
      var i$, k, ref$, results$ = [];
      opt == null && (opt = {});
      count == null && (count = 4);
      for (i$ = 0; i$ < count; ++i$) {
        k = i$;
        results$.push(synth[name]((ref$ = import$({
          vary: 0.5
        }, opt), ref$.seed = (opt.seed || 0) + k + 1, ref$)));
      }
      return results$;
    };
    PARAMS = {
      click: {
        freq: [500, 5000, 10, 2000],
        seed: [1, 99, 1, 7],
        pan: [-1, 1, 0.05, 0]
      },
      tick: {
        note: {
          note: null,
          hint: "1800 Hz"
        },
        pan: [-1, 1, 0.05, 0]
      },
      pop: {
        from: [100, 2000, 10, 380],
        to: [100, 3000, 10, 900],
        pan: [-1, 1, 0.05, 0]
      },
      toggle: {
        pan: [-1, 1, 0.05, 0]
      },
      type: {
        seed: [1, 99, 1, 11]
      },
      thump: {
        seed: [1, 99, 1, 5],
        pan: [-1, 1, 0.05, 0]
      },
      snap: {
        seed: [1, 99, 1, 41],
        pan: [-1, 1, 0.05, 0]
      },
      chime: {
        note: {
          note: "E6"
        },
        dur: [0.3, 4, 0.1, 1.4],
        pan: [-1, 1, 0.05, 0],
        reverb: [0, 1, 0.05, 0],
        room: [0, 1, 0.05, 0.5]
      },
      success: {
        pan: [-1, 1, 0.05, 0],
        reverb: [0, 1, 0.05, 0],
        room: [0, 1, 0.05, 0.5]
      },
      notify: {
        pan: [-1, 1, 0.05, 0],
        reverb: [0, 1, 0.05, 0],
        room: [0, 1, 0.05, 0.5]
      },
      error: {
        from: {
          note: "B3"
        },
        to: {
          note: "F3"
        },
        pan: [-1, 1, 0.05, 0]
      },
      correct: {
        style: {
          options: ["pingpong", "arp"],
          def: "pingpong"
        },
        notes: {
          json: null
        },
        gap: [0.03, 0.4, 0.01, 0.2],
        pan: [-1, 1, 0.05, 0],
        reverb: [0, 1, 0.05, 0.15],
        room: [0, 1, 0.05, 0.5]
      },
      wrong: {
        style: {
          options: ["buzzer", "trombone"],
          def: "buzzer"
        },
        pitch: [60, 400, 1, 140],
        pan: [-1, 1, 0.05, 0]
      },
      reveal: {
        notes: {
          json: ["C6", "E6", "G6", "C7", "E7"]
        },
        gap: [0.02, 0.2, 0.01, 0.06],
        seed: [1, 99, 1, 53],
        pan: [-1, 1, 0.05, 0],
        reverb: [0, 1, 0.05, 0.35],
        room: [0, 1, 0.05, 0.5]
      },
      whoosh: {
        dur: [0.1, 2, 0.05, 0.7],
        from: [50, 5000, 10, 400],
        peak: [50, 6000, 10, 2600],
        to: [50, 5000, 10, 600],
        at: [0.05, 0.95, 0.01, 0.45],
        q: [0.3, 6, 0.1, 1.2],
        seed: [1, 99, 1, 3]
      },
      swell: {
        dur: [0.5, 6, 0.1, 2],
        seed: [1, 99, 1, 23]
      },
      slide: {
        dur: [0.1, 1, 0.05, 0.3],
        from: [100, 6000, 10, 900],
        to: [100, 6000, 10, 2600],
        q: [0.3, 4, 0.1, 0.9],
        dir: [-1, 1, 0.1, 1],
        seed: [1, 99, 1, 37]
      },
      rise: {
        from: {
          note: null,
          hint: "300 Hz"
        },
        to: {
          note: null,
          hint: "900 Hz"
        },
        dur: [0.1, 3, 0.05, 0.6],
        pan: [-1, 1, 0.05, 0]
      },
      fall: {
        from: {
          note: null,
          hint: "900 Hz"
        },
        to: {
          note: null,
          hint: "250 Hz"
        },
        dur: [0.1, 3, 0.05, 0.6],
        pan: [-1, 1, 0.05, 0]
      },
      count: {
        n: [2, 40, 1, 12],
        dur: [0.2, 4, 0.1, 1.2],
        ease: {
          options: ["out", "in", "linear"],
          def: "out"
        },
        climb: [0, 24, 1, 7],
        note: {
          note: "C6"
        },
        pan: [-1, 1, 0.05, 0]
      },
      draw: {
        dur: [0.2, 4, 0.1, 1],
        rough: [0, 1, 0.05, 0.5],
        pitch: [500, 8000, 50, 2500],
        seed: [1, 99, 1, 43],
        pan: [-1, 1, 0.05, 0]
      },
      glitch: {
        dur: [0.1, 2, 0.05, 0.5],
        seed: [1, 99, 1, 47]
      },
      sweep: {
        wave: {
          options: ["sine", "triangle", "square", "saw", "noise"],
          def: "sine"
        },
        curve: {
          options: ["exp", "lin"],
          def: "exp"
        },
        from: {
          note: null,
          hint: "200 Hz"
        },
        to: {
          note: null,
          hint: "2000 Hz"
        },
        dur: [0.1, 4, 0.05, 1],
        q: [0.3, 10, 0.1, 2],
        attack: [0, 1, 0.01, 0.01],
        release: [0, 2, 0.01, 0.1],
        pan: [-1, 1, 0.05, 0]
      },
      tension: {
        note: {
          note: "A2"
        },
        dur: [1, 12, 0.5, 6]
      },
      heartbeat: {
        bpm: [40, 180, 1, 70],
        dur: [1, 10, 0.5, 4],
        pan: [-1, 1, 0.05, 0]
      },
      clock: {
        bpm: [30, 240, 1, 60],
        dur: [1, 10, 0.5, 4],
        seed: [1, 99, 1, 59],
        pan: [-1, 1, 0.05, 0]
      },
      fingersnap: {
        tone: [2000, 5000, 10, 3200],
        seed: [1, 99, 1, 137],
        pan: [-1, 1, 0.05, 0]
      },
      huh: {
        pitch: [80, 400, 1, 200],
        rise: [1, 3, 0.05, 1.9],
        dur: [0.2, 1, 0.01, 0.45],
        size: [0.8, 1.3, 0.01, 1],
        seed: [1, 99, 1, 151]
      },
      yay: {
        pitch: [100, 500, 1, 300],
        dur: [0.2, 1.2, 0.01, 0.5],
        size: [0.8, 1.3, 0.01, 1],
        seed: [1, 99, 1, 157]
      },
      paper: {
        dur: [0.4, 2.5, 0.05, 1.2],
        crisp: [0, 3, 0.1, 1],
        flutter: [0, 1, 0.05, 0.6],
        seed: [1, 99, 1, 61]
      },
      water: {
        n: [1, 300, 1, 1],
        size: [0.5, 10, 0.1, 3],
        rise: [0, 1, 0.05, 0.05],
        dur: [0.2, 10, 0.1, 0.4],
        seed: [1, 99, 1, 67]
      },
      fire: {
        dur: [1, 10, 0.5, 6],
        density: [0, 4, 0.1, 1],
        seed: [1, 99, 1, 71]
      },
      steps: {
        surface: {
          options: ["wood", "concrete", "gravel", "snow", "grass"],
          def: "wood"
        },
        gait: {
          options: ["walk", "run"],
          def: "walk"
        },
        n: [1, 12, 1, 4],
        pace: [0.2, 1.2, 0.05, 0.5],
        seed: [1, 99, 1, 73]
      },
      bell: {
        note: {
          note: "C5"
        },
        dur: [1, 10, 0.5, 5],
        pan: [-1, 1, 0.05, 0],
        reverb: [0, 1, 0.05, 0.2],
        room: [0, 1, 0.05, 0.5]
      },
      thunder: {
        dur: [2, 12, 0.5, 6],
        dist: [0, 1, 0.05, 0.5],
        seed: [1, 99, 1, 79]
      },
      wind: {
        dur: [1, 10, 0.5, 6],
        cutoff: [200, 3000, 10, 900],
        seed: [1, 99, 1, 17]
      },
      rain: {
        dur: [1, 10, 0.5, 6],
        density: [0.002, 0.2, 0.002, 0.02],
        seed: [1, 99, 1, 19]
      },
      buzz: {
        dur: [0.2, 4, 0.1, 1.5],
        freq: [80, 600, 1, 220],
        pan: [-1, 1, 0.05, 0]
      },
      pluck: {
        note: {
          note: "A3"
        },
        dur: [0.3, 5, 0.1, 2.5],
        bright: [0, 1, 0.05, 0.6],
        slide: [0, 3, 0.1, 0.6],
        seed: [1, 99, 1, 13],
        pan: [-1, 1, 0.05, 0],
        reverb: [0, 1, 0.05, 0],
        room: [0, 1, 0.05, 0.5]
      },
      guitar: {
        note: {
          note: "E3"
        },
        chord: {
          options: ["", "C", "D", "Dm", "E", "Em", "F", "G", "A", "Am"],
          def: ""
        },
        notes: {
          json: null
        },
        dir: {
          options: ["down", "up"],
          def: "down"
        },
        strum: [0, 0.1, 0.005, 0.03],
        dur: [0.5, 6, 0.1, 3],
        bright: [0, 1, 0.05, 0.5],
        pos: [0.05, 0.5, 0.01, 0.2],
        mute: [0, 1, 0.05, 0],
        seed: [1, 99, 1, 89],
        pan: [-1, 1, 0.05, 0],
        reverb: [0, 1, 0.05, 0],
        room: [0, 1, 0.05, 0.5]
      },
      marimba: {
        note: {
          note: "C4"
        },
        dur: [0.3, 4, 0.1, 1.5],
        hard: [0, 1, 0.05, 0.5],
        pan: [-1, 1, 0.05, 0],
        reverb: [0, 1, 0.05, 0],
        room: [0, 1, 0.05, 0.5]
      },
      xylophone: {
        note: {
          note: "C5"
        },
        dur: [0.2, 3, 0.1, 0.8],
        hard: [0, 1, 0.05, 0.5],
        pan: [-1, 1, 0.05, 0],
        reverb: [0, 1, 0.05, 0],
        room: [0, 1, 0.05, 0.5]
      },
      vibraphone: {
        note: {
          note: "F4"
        },
        dur: [0.5, 6, 0.1, 3],
        trem: [0, 1, 0.05, 0.35],
        hard: [0, 1, 0.05, 0.5],
        pan: [-1, 1, 0.05, 0],
        reverb: [0, 1, 0.05, 0],
        room: [0, 1, 0.05, 0.5]
      },
      glockenspiel: {
        note: {
          note: "C6"
        },
        dur: [0.3, 4, 0.1, 2],
        hard: [0, 1, 0.05, 0.5],
        pan: [-1, 1, 0.05, 0],
        reverb: [0, 1, 0.05, 0],
        room: [0, 1, 0.05, 0.5]
      },
      score: {
        score: {
          text: "C4/4 C4 G4 G4 | A4 A4 G4/2 | F4/4 F4 E4 E4 | D4 D4 C4/2"
        },
        instrument: {
          options: ["pluck", "marimba", "xylophone", "vibraphone", "glockenspiel", "guitar", "chime", "bell", "pop", "tick", "kick", "tom", "water"],
          def: "pluck"
        },
        bpm: [40, 240, 1, 100],
        base: {
          note: "C4"
        },
        release: [0.02, 2, 0.01, 0.1]
      },
      melody: {
        notes: {
          json: [[0, "A3"], [0.4, "C4"], [0.8, "E4"], [1.2, "A4", 2]]
        },
        instrument: {
          options: ["pluck", "marimba", "xylophone", "vibraphone", "glockenspiel", "guitar", "chime", "bell"],
          def: "pluck"
        },
        release: [0.02, 2, 0.01, 0.8],
        bright: [0, 1, 0.05, 0.6],
        slide: [0, 3, 0.1, 0.6],
        reverb: [0, 1, 0.05, 0],
        room: [0, 1, 0.05, 0.5]
      },
      drone: {
        notes: {
          json: ["A1", "E2", "A2"]
        },
        dur: [1, 12, 0.5, 8],
        attack: [0.1, 4, 0.1, 1.5],
        release: [0.1, 4, 0.1, 2]
      },
      kick: {
        tune: [30, 120, 1, 50],
        decay: [0.05, 1, 0.01, 0.3],
        punch: [0, 1, 0.05, 0.5],
        pan: [-1, 1, 0.05, 0]
      },
      snare: {
        tune: [100, 400, 1, 180],
        decay: [0.05, 0.5, 0.01, 0.15],
        snappy: [0, 1, 0.05, 0.6],
        seed: [1, 99, 1, 101],
        pan: [-1, 1, 0.05, 0]
      },
      hihat: {
        open: [0, 1, 0.05, 0],
        tune: [0.5, 2, 0.05, 1],
        seed: [1, 99, 1, 103],
        pan: [-1, 1, 0.05, 0]
      },
      tom: {
        note: {
          note: "A2"
        },
        decay: [0.1, 1, 0.01, 0.35],
        seed: [1, 99, 1, 107],
        pan: [-1, 1, 0.05, 0]
      },
      clap: {
        decay: [0.03, 0.5, 0.01, 0.12],
        seed: [1, 99, 1, 109]
      },
      crash: {
        decay: [0.3, 3, 0.05, 1],
        tune: [0.5, 2, 0.05, 1],
        seed: [1, 99, 1, 113]
      },
      ride: {
        decay: [0.3, 3, 0.05, 1],
        bell: [0, 1, 0.05, 0],
        tune: [0.5, 2, 0.05, 1],
        seed: [1, 99, 1, 127]
      },
      beat: {
        pattern: {
          json: {
            "kick": "x.......x.x.....",
            "snare": "....x.......x...",
            "hihat": "x.x.x.x.x.x.x.x."
          }
        },
        bpm: [50, 200, 1, 100],
        bars: [1, 8, 1, 1],
        swing: [0, 1, 0.05, 0],
        reverb: [0, 1, 0.05, 0],
        room: [0, 1, 0.05, 0.5]
      }
    };
    S.params = {};
    for (name in PARAMS) {
      spec = PARAMS[name];
      S.params[name] = (fn$());
    }
    SEMI = {
      C: 0,
      D: 2,
      E: 4,
      F: 5,
      G: 7,
      A: 9,
      B: 11
    };
    NAMES = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
    transpose = function(note, semi){
      var m, midi;
      if (typeof note === 'number') {
        return Math.round(note * Math.pow(2, semi / 12));
      }
      m = /^([A-G])(#|b)?(-?\d)$/.exec(note);
      if (!m) {
        return note;
      }
      midi = 12 * (+m[3] + 1) + SEMI[m[1]] + (m[2] === '#'
        ? 1
        : m[2] === 'b' ? -1 : 0) + semi;
      return NAMES[(midi % 12 + 12) % 12] + (Math.floor(midi / 12) - 1);
    };
    S.mutate = function(name, opt, cfg){
      var amount, r, out, i$, ref$, len$, p, ref1$, cur, v, semi;
      opt == null && (opt = {});
      cfg == null && (cfg = {});
      amount = cfg.amount != null ? cfg.amount : 0.5;
      r = cfg.seed != null
        ? rng(cfg.seed)
        : Math.random;
      out = import$({}, opt);
      for (i$ = 0, len$ = (ref$ = S.params[name] || []).length; i$ < len$; ++i$) {
        p = ref$[i$];
        if ((ref1$ = p.k) !== 'seed' && ref1$ !== 'pan' && ref1$ !== 'reverb' && ref1$ !== 'room' && ref1$ !== 'vary') {
          cur = opt[p.k] != null
            ? opt[p.k]
            : p.def;
          switch (p.type) {
          case 'range':
            v = cur + gauss(r) * amount * (p.max - p.min) * 0.15;
            v = +(Math.round(Math.max(p.min, Math.min(p.max, v)) / p.step) * p.step).toFixed(4);
            if (v === p.def) {
              delete out[p.k];
            } else {
              out[p.k] = v;
            }
            break;
          case 'select':
            if (r() < amount * 2) {
              out[p.k] = p.options[Math.floor(r() * p.options.length)];
            }
            if (out[p.k] === p.def) {
              delete out[p.k];
            }
            break;
          case 'note':
            semi = Math.round(gauss(r) * amount * 2);
            if (cur != null && semi) {
              out[p.k] = transpose(cur, semi);
            }
          }
        }
      }
      out.seed = 1 + Math.floor(r() * 99);
      if (amount > 0) {
        out.vary = +(amount * 0.5).toFixed(2);
      }
      return out;
    };
    if (typeof module !== 'undefined' && module.exports) {
      module.exports = S;
    }
    if (typeof window !== 'undefined') {
      return window.sfx = S;
    }
    function fn$(){
      var ref$, results$ = [];
      for (k in ref$ = spec) {
        v = ref$[k];
        if (Array.isArray(v)) {
          results$.push({
            k: k,
            type: 'range',
            min: v[0],
            max: v[1],
            step: v[2],
            def: v[3]
          });
        } else if (v.options) {
          results$.push({
            k: k,
            type: 'select',
            options: v.options,
            def: v.def
          });
        } else if ('note' in v) {
          results$.push({
            k: k,
            type: 'note',
            def: v.note,
            hint: v.hint
          });
        } else if ('text' in v) {
          results$.push({
            k: k,
            type: 'text',
            def: v.text
          });
        } else {
          results$.push({
            k: k,
            type: 'json',
            def: v.json
          });
        }
      }
      return results$;
    }
  })();
  function import$(obj, src){
    var own = {}.hasOwnProperty;
    for (var key in src) if (own.call(src, key)) obj[key] = src[key];
    return obj;
  }
}).call(this);
