# @plotdb/sfx

給確定性動畫 ( 例如 [lotion](https://github.com/plotdb/lotion) ) 用的音訊 runtime：

 - 時間軸：聲音綁在動畫時間上，播放、暫停、拖曳、倍速都會同步。
 - 指令式播放：互動用，與時間軸無關。
 - 程序化合成：在瀏覽器裡算出 UI 音效、撥弦、環境聲，免費、可重現 ( 同樣的參數永遠是同樣的聲音 )。
 - 離線混音：把時間軸混成一段音訊 ( 輸出影片配音用 )。

試玩：`npm install`、`npx fedep`、`npm run build` 後 `npm start` ( 即 `npx server -r web -o true` )。
線上版：https://plotdb.github.io/sfx/ ( `npm run deploy` 發佈到 gh-pages )。
頁面原始碼在 `web/src/pug`，建置到 `web/static`：音效清單 ( 點了就播，🎲 隨機變化 )、可編輯的五線譜、每種合成聲的參數試聽，以及可以播放、拖曳、倍速並混成 wav 的時間軸。


## 安裝與載入

    npm install github:plotdb/sfx

頁面裡在 lotion 之後載入 `dist/index.min.js`，全域變數 `window.sfx`：

    <script src="/assets/lib/@plotdb/lotion/main/index.min.js"></script>
    <script src="/assets/lib/@plotdb/sfx/main/index.min.js"></script>
    <script>
    const S = window.sfx;
    </script>

頁面上有 `lotion.player` 時會自動攔截它的 play / pause / seek 與循環區段，不用另外接。


## 載入聲音

    S.load({bgm: 'assets/bgm.mp3', pop: S.synth.pop()}).then(() => { ... })

 - 值可以是網址、`AudioBuffer` ( 例如合成的聲音 ) 或回傳 `AudioBuffer` 的 Promise。
 - 載完再設時間軸，並在 `player.start()` 之前完成。
 - `S.pending`：載入中的數量。`S.errors`：載入或播放的錯誤訊息。


## 時間軸

    S.timeline([
      {t: 0, sound: 'bgm', bus: 'music', gain: 0.35, fadeIn: 1, fadeOut: 2},
      {t: 5.2, sound: 'pop', gain: 0.8}
    ])

每一項：

 - `t`：動畫時間 ( 秒 )。
 - `sound`：`S.load` 的名稱。
 - `bus`：`music` | `sfx` ( 預設 ) | `voice`。
 - `gain`、`rate` ( 播放速率 )、`offset` ( 從檔案的第幾秒開始 )、`duration`。
 - `fadeIn`、`fadeOut`：秒。
 - `loop: true` 搭配 `until`：循環到某個時間。
 - `align`：`peak` ( `sfx` 預設，讓聲音的起音點落在 `t` 上 ) | `start` ( 其他 bus 預設，從 `t` 開始播 )。

`S.cues(cues)`：把 lotion 的 cues `[{t, sfx, gain}]` 轉成時間軸。

### 外部時鐘

動畫由外層控制 ( 例如外層頁面經 postMessage 控制 iframe 裡的動畫 ) 時，由外層告知播放狀態：

    S.transport({playing: true, t: 12.3, rate: 1.5, from: 'host'})

 - 帶 `from` 之後不再跟隨頁面上的 player。
 - `rate`：倍速。旁白 ( `voice` ) 與配樂 ( `music` ) 用網址載入的會保持音高；合成的聲音與短音效直接變速。
 - 非連續的時間 ( 拖曳 ) 或 `force: true` 時重新排程。


### 等待 ( 事件聲音 )

書停下來等讀者時 ( 例如 `p.loop(19.6, 20.8)` 重播一小段，等讀者動手 )，時間軸的聲音如果跟著每圈接回，配樂與環境音會每圈倒退一次。sfx 把這段當成「等待」：

 - 進入等待：時間軸聲音在 0.5 秒內壓低到 0.3 ( 還沒開始的取消 )，循環接回時不重排；事件聲音開始播，用實際時間，不管 seek。
 - 離開等待：事件聲音淡出；時間軸從目前的時間重新排程，並短暫淡入。跳到別段時照一般的跳轉處理。
 - 沒有宣告事件聲音時：時間軸上 `loop: true` 的聲音 ( 配樂、環境音 ) 從同一個位置接著播，不會壓低，其他的聲音壓低。舊作品不用改就不會跳。
 - 讀者按暫停不算等待，一律安靜；按播放後回到等待。
 - 輸出影片與 `S.render` 只算時間軸：初始狀態不會等待，結果可重現。

什麼算等待：

 - 頁面上的 lotion.player：書自己的循環區段 `p.loop(a, b)` 生效、播放中，且時間在區段內。player 有 `waiting` 時以它為準 ( 書自己 `p.pause()` 等讀者要靠它分辨 )。
 - 外部時鐘：`S.transport({..., wait})`，或 `S.wait(w)`。`w` 為 `{kind: 'loop', span: [a, b]}`、`{kind: 'pause', t}`，結束時為 `null`。循環等待中，時間仍在區段內的接回 ( 即使帶 `force` ) 不重排。

宣告事件聲音 ( 放在 `S.timeline` 裡，帶 `hold` 的項目不排在時間軸上 )：

    S.timeline([
      ...,
      {hold: [19, 21], sound: 'pad', bus: 'music', loop: true, gain: 0.3, fadeIn: 0.5, fadeOut: 0.5},
      {hold: [19, 21], sound: 'tick', every: 1.2}
    ], {duck: 0.3, duckFade: 0.5})

 - `hold: [a, b]`：書在 [a, b] 內等待時才播 ( 循環區段落在裡面，或在裡面暫停 )，正常播放經過不會觸發。
 - `loop: true` 播到離開等待；`every`：每隔幾秒 ( 動畫時間，依倍速換算 ) 播一次，例如每圈的提示音；兩者都沒有就播一次。
 - `gain`、`bus` ( 預設 `sfx` )、`rate`、`offset`、`fadeIn` ( `loop` 預設 0.5 )、`fadeOut` ( 預設 0.5 )、`delay` ( `every` 第一聲之前等幾秒 )。
 - `duck`：這個等待中時間軸聲音壓到多少 ( 取最小值，0 為靜音 )。`S.timeline` 的第二個參數設定全部等待的預設值。
 - 有符合的事件聲音時，時間軸上的 `loop: true` 聲音也一起壓低。

指令式：`h = S.hold('pad', {loop: true, gain: 0.3})`，可在 `p.at` 的回呼裡呼叫。播到等待結束或讀者暫停時淡出，`h.stop(fade)` 可提前停止。選項同上。


## 指令式播放

    h = S.play('pop', {gain: 0.8, loop: false, fadeIn: 0})
    h.fade(0.2, 0.5)    // 0.5 秒內淡到 0.2
    h.stop(0.1)         // 0.1 秒淡出後停止
    S.stop('pop')       // 停止這個名稱的指令式聲音 ( 不給名稱全停 )
    S.music('bgm', {fade: 1})   // 背景音樂槽: 同時一首, 換曲時交叉淡入淡出; S.music(null) 淡出
    S.volume('music', 0.5)      // bus 音量: music | sfx | voice | master

瀏覽器的自動播放限制：要在使用者操作後呼叫 `S.resume()` ( `S.play` 會自己呼叫 )。


## 合成

全部回傳 `AudioBuffer` ( 48kHz 雙聲道 )，可直接 `S.load`。音高參數可以給 Hz 或音名 ( `'A4'`、`'C#5'` )。

 - `seed`：用到雜訊的聲音 ( click、type、thump、whoosh、swell、pluck、wind、rain ) 換一組雜訊，同樣參數、不同質感。
 - `pan`：-1 左 ~ 1 右，單點的聲音 ( click、tick、pop、toggle、thump、chime、success、notify、pluck、buzz ) 才有；
   whoosh、wind、rain 本身就有左右移動或去相關。

| 聲音 | 長度 | 參數 | 用途 |
| --- | --- | --- | --- |
| `click` | 0.05s | `freq` | 點擊 |
| `tick` | 0.06s | `note` / `freq` | 刻度、計數 |
| `pop` | 0.15s | `from`、`to` ( Hz，音高滑動 ) | 元素出現 |
| `toggle` | 0.12s | | 開關 |
| `type` | 0.05s | | 打字 ( 每次 seed 不同較自然 ) |
| `thump` | 0.35s | | 落地、蓋章 |
| `snap` | 0.1s | | 吸附、到位 |
| `chime` | `dur` ( 1.4 ) | `note` ( E6 ) | 鈴聲、完成一步 |
| `success` | 0.9s | | 成功 ( C-E-G 琶音 ) |
| `notify` | 0.7s | | 通知 |
| `error` | 0.5s | `from` ( B3 )、`to` ( F3 ) | 錯誤 |
| `reveal` | 1.6s | `notes` ( [C6, E6, G6, C7, E7] )、`gap` ( 0.06 ) | 揭曉 ( 預設 `reverb: 0.35` ) |
| `correct` | 自動 | `style` ( pingpong「叮咚」\| arp 琶音 )、`notes`、`gap` | 答對 |
| `wrong` | 自動 | `style` ( buzzer「噗噗」\| trombone 悲傷長號 )、`pitch` ( 140 ) | 答錯 |
| `whoosh` | `dur` ( 0.7 ) | `from` ( 400 )、`peak` ( 2600 )、`to` ( 600 )、`at` ( 0.45 )、`q` ( 1.2 ) | 轉場 |
| `swell` | `dur` ( 2 ) | | 段落前的醞釀 |
| `slide` | `dur` ( 0.3 ) | `from` ( 900 )、`to` ( 2600 )、`q` ( 0.9 )、`dir` ( 1 往右，-1 往左 ) | 滑入、滑出 |
| `rise` / `fall` | `dur` ( 0.6 ) | `from`、`to` ( Hz 或音名；300→900 / 900→250 ) | 數值上升 / 下降 |
| `count` | `dur` + 0.2 | `n` ( 12 )、`dur` ( 1.2 )、`ease` ( out \| in \| linear )、`climb` ( 7 半音 )、`note` ( C6 ) | 數字滾動 |
| `draw` | `dur` ( 1 ) | `rough` ( 0~1 )、`pitch` ( 2500 ) | 筆畫 |
| `glitch` | `dur` ( 0.5 ) | | 故障 |
| `sweep` | `dur` ( 1 ) | `wave` ( sine \| triangle \| square \| saw \| noise )、`from` ( 200 )、`to` ( 2000 )、`curve` ( exp \| lin )、`q`、`attack`、`release` | 通用掃頻 |
| `tension` | `dur` ( 6 ) | `note` ( A2 ) | 緊張 |
| `heartbeat` | `dur` ( 4 ) | `bpm` ( 70 ) | 心跳 |
| `clock` | `dur` ( 4 ) | `bpm` ( 60 ) | 時鐘 |
| `fingersnap` | 0.12s | `tone` ( 手掌共鳴 3200Hz ) | 打響指 |
| `huh` | `dur` ( 0.45 ) | `pitch` ( 200 )、`rise` ( 上揚倍數 1.9 )、`size` | 蛤? |
| `yay` | `dur` ( 0.5 ) | `pitch` ( 300 )、`size` | 耶! |
| `paper` | `dur` ( 1.2 ) | `crisp` ( 劈啪聲，0 軟紙 ~ 3 硬紙 )、`flutter` ( 紙張抖動 0~1 ) | 翻頁 |
| `water` | 自動 | `n` ( 氣泡數，1 為水滴 )、`size` ( 平均半徑 mm，越大越低 )、`rise` ( 音高上升 ) | 水滴、冒泡、溪流 |
| `fire` | `dur` ( 6 ) | `density` ( 1 ) | 火 |
| `steps` | 自動 | `surface` ( wood \| concrete \| gravel \| snow \| grass )、`gait` ( walk \| run )、`n` ( 4 )、`pace` ( 走 0.5 / 跑 0.3 ) | 腳步 |
| `bell` | `dur` ( 5 ) | `note` ( C5 ) | 教堂鐘、管鐘 ( 預設 `reverb: 0.2` ) |
| `thunder` | `dur` ( 6 ) | `dist` ( 0 近 ~ 1 遠 ) | 雷 |
| `wind` | `dur` ( 6 ) | `cutoff` ( 900 ) | 風 |
| `rain` | `dur` ( 6 ) | `density` ( 0.02 ) | 雨 |
| `buzz` | `dur` ( 1.5 ) | `freq` ( 220 ) | 昆蟲振翅 |
| `pluck` | `dur` ( 2.5 ) | `note` ( A3 )、`bright` ( 0~1 )、`slide` ( 半音 ) | 撥弦 ( 類古箏 ) |
| `guitar` | `dur` ( 3 ) | `note` ( E3 ) 或 `chord` ( C D Dm E Em F G A Am ) 或 `notes`、`strum` ( 0.03 )、`dir` ( down \| up )、`bright`、`pos` ( 撥弦位置 0.2 )、`mute` ( 0~1 ) | 吉他 |
| `marimba` | `dur` ( 1.5 ) | `note` ( C4 )、`hard` ( 槌子硬度 0~1 ) | 馬林巴 |
| `xylophone` | `dur` ( 0.8 ) | `note` ( C5 )、`hard` | 木琴 |
| `vibraphone` | `dur` ( 3 ) | `note` ( F4 )、`hard`、`trem` ( 顫音深度 0.35 ) | 鐵琴 |
| `glockenspiel` | `dur` ( 2 ) | `note` ( C6 )、`hard` | 鐘琴 |
| `melody` | 自動 | `notes: [[t, note, dur, vel], ...]`、`instrument` ( pluck )、`release` ( 0.8 )、`bright`、`slide` | 旋律 |
| `score` | 自動 | `score` ( 文字樂譜，見下方 )、`instrument`、`bpm`、`base`、`release` | 照樂譜演奏 |
| `drone` | `dur` ( 8 ) | `notes` ( [A1, E2, A2] )、`attack`、`release` | 持續低音 |
| `kick` | 自動 | `tune` ( 50 Hz )、`decay` ( 0.3 )、`punch` ( 0~1 ) | 大鼓 |
| `snare` | 自動 | `tune` ( 180 Hz )、`decay` ( 0.15 )、`snappy` ( 0~1 ) | 小鼓 |
| `hihat` | 自動 | `open` ( 0 閉 ~ 1 開 )、`tune` ( 1 ) | hi-hat |
| `tom` | 自動 | `note` ( A2 )、`decay` ( 0.35 ) | 中鼓 / 落地鼓 |
| `clap` | 自動 | `decay` ( 0.12 ) | 拍手 |
| `crash` | 自動 | `decay` ( 尾音倍數，1 約 2 秒 )、`tune` ( 1 ) | 碎音鈸 |
| `ride` | 自動 | `decay` ( 尾音倍數，1 約 3 秒 )、`bell` ( 0~1，越大越靠近鈸心 )、`tune` ( 1 ) | 疊音鈸 |
| `beat` | 自動 | `pattern`、`bpm` ( 100 )、`bars` ( 1 )、`swing` ( 0~1 ) | 節奏 |

擬音、鈸與人聲 ( `crash` `ride` `thunder` `steps` `paper` `water` `fingersnap` `huh` `yay` ) 依 Wikimedia Commons 上的錄音分析調整過頻譜分布、衰減曲線、音高與共振峰。

人聲 ( `huh` `yay` ) 以共振峰合成：聲帶脈衝與氣音經過 4 個會移動的共振峰。`size` 是聲道大小 ( 小孩約 1.15，大人男聲約 0.9 )。聽得出是人聲，但偏卡通，不像真人錄音。

全部的合成聲都可以加 `vary` ( 見下方「變化」)、`reverb` ( 0~1，濕聲比例 ) 與 `room` ( 0~1，空間大小 )，聲音會多出殘響的尾巴。
已經有的 `AudioBuffer` 也可以用 `S.reverb(buffer, {mix, room})` 加殘響。

### 樂譜

用文字寫樂譜，指定任何聲音照著演奏：

    S.load({tune: S.synth.score({score: 'C4/4 C4 G4 G4 | A4 A4 G4/2', instrument: 'marimba', bpm: 100})})

 - 音名 + 八度 ( `C4`、`F#5`、`Bb3` )，`/n` 是音長 ( 1 全音符、2 二分、4 四分、8、16、32、64 )，後面加 `.` 是附點。
 - `-` ( 或 `r` ) 是休止符，`C4+E4+G4` 是和弦，`|` 是小節線 ( 只是方便閱讀 )。音長沒寫就沿用前一個。
 - `instrument`：有 `note` 參數的合成聲 ( pluck、marimba、guitar … ) 以音高合成每個音；
   其他聲音 ( 例如 `pop`、`kick`，或載入的 `AudioBuffer` ) 以 `base` ( 預設 C4 ) 為準變調演奏。
 - `bpm` ( 100 )、`release` ( 每個音之後保留的尾音，預設 0.1 秒 )；也可以加 `vary`、`reverb`。
 - `S.score(text, {bpm})`：轉成 `melody` 的 `notes`；`S.score.parse(text)`：解析成 `[{notes, beats}]`；`S.score.duration(text, {bpm})`：秒數。

demo 頁的五線譜可以直接編輯並產生這段樂譜文字。

### 變化

同一個聲音重複出現 ( 腳步、打字、點擊 ) 時，每次略有不同會比較自然。預設不變，要用時再加：

 - 合成時加 `vary` ( 0~1 )：換一組雜訊，音高與長度微調 ( 1 約 ±1 個半音 )，音量略小。同樣的 `seed` 永遠是同樣的變化。

        S.synth.pop({vary: 0.5, seed: 3})

 - `S.variants(name, opt, count)`：一次產生 count 個變化 ( seed 1 ~ count，`vary` 預設 0.5 )。

        const [a, b, c] = S.variants('steps', {n: 1}, 3)
        S.load({step1: a, step2: b, step3: c})

 - 時間軸項目的 `sound` 可以是陣列，依項目的位置與時間挑一個；加 `vary` 則每個項目的音高與音量略有不同。
   兩者都可重現：拖曳、重播、離線混音結果都一樣。

        S.timeline([
          {t: 1.0, sound: ['step1', 'step2', 'step3'], vary: 0.3},
          {t: 1.5, sound: ['step1', 'step2', 'step3'], vary: 0.3}
        ])

 - `S.play(name, {vary})` 與 `S.play([...names])`：互動用，每次隨機 ( 不可重現 )。

 - `S.mutate(name, opt, {amount, seed})`：以目前的參數 ( 沒給的用預設 ) 為中心，產生一組變化的參數。
   數值依常態分布微調 ( σ = amount × 範圍 × 0.15 )，選項 ( 例如 `style`、`chord`、`surface` ) 以 amount × 2 的機率隨機挑，
   音名移幾個半音，並換 `seed`、加上 `vary`。`amount` 預設 0.5；給 `seed` 就可重現。

        S.synth.correct(S.mutate('correct'))                  // 可能是 pingpong 也可能是 arp
        S.synth.whoosh(S.mutate('whoosh', {dur: 0.4}, {amount: 0.3, seed: 7}))

 - `S.params[name]`：每種合成聲的參數定義 `[{k, type: range | note | select | json, min, max, step, def, options}]`，
   demo 頁的控制項也是由它產生。

`melody` 的 `instrument` 可以是任何有 `note` 參數的聲音：`pluck` ( 預設 )、`guitar`、`marimba`、`xylophone`、`vibraphone`、`glockenspiel`、`chime`、`bell`。

`beat` 的 `pattern` 一個字元是一格十六分音符：`X` 重音、`x` 一般、`o` 輕，其他字元 ( `.`、`-` ) 是休止，空白與 `|` 忽略。

    S.synth.beat({bpm: 96, bars: 2, swing: 0.3, pattern: {
      kick:  'x.......x.x.....',
      snare: '....x.......x..o',
      hihat: 'x.x.x.x.x.x.x.x.',
      tom:   ['..............x.', {note: 'D3'}]   // 也可以給 [pattern, 參數]
    }})

名稱可以是 `kick` `snare` `hihat` `ohat` ( 開 hi-hat ) `tom` `ltom` `htom` `clap` `crash` `ride`，或任何合成聲的名稱。

`whoosh` 是帶通濾波的雜訊，中心頻率依 `from` → `peak` → `to` 走，在 `at` ( 0~1 ) 處最亮最響：

 - 短促的掃過：`{dur: 0.35}`；更短更乾淨：`{dur: 0.25, q: 2}`。
 - 往上衝：`{from: 300, peak: 3500, to: 3000, at: 0.8}`；往下沉：`{from: 3000, peak: 3000, to: 300, at: 0.1}`。
 - `q` 小 ( 0.5 ) 像風，大 ( 3 ) 像哨音。


## 混音與檢查

 - 建議音量：配樂 0.3~0.4、音效 0.6~1、旁白 1。
 - `S.report()`：載入的聲音 ( 長度、起音點 )、時間軸數量、播放狀態、AudioContext 狀態、最近的錯誤。
 - `S.peak(buffer)`：起音點 ( 秒 )。
 - `S.render(duration)`：離線混音，回傳 Promise<AudioBuffer>。`S.wav(buffer)`：轉成 16-bit wav Blob。
