# @plotdb/sfx

給確定性動畫 ( 例如 [lotion](https://github.com/plotdb/lotion) ) 用的音訊 runtime：

 - 時間軸：聲音綁在動畫時間上，播放、暫停、拖曳、倍速都會同步。
 - 指令式播放：互動用，與時間軸無關。
 - 程序化合成：在瀏覽器裡算出 UI 音效、撥弦、環境聲，免費、可重現 ( 同樣的參數永遠是同樣的聲音 )。
 - 離線混音：把時間軸混成一段音訊 ( 輸出影片配音用 )。

試玩：`npm install`、`npx fedep`、`npm run build` 後 `npm start` ( 即 `npx server -r web -o true` )。
頁面原始碼在 `web/src/pug`，建置到 `web/static`：每種合成聲都可以調參數試聽，也可以編輯一段時間軸播放、拖曳、倍速並混成 wav。


## 安裝與載入

    npm install github:plotdb/sfx

頁面裡在 lotion 之後載入 `dist/index.min.js`，全域變數 `window.sfx`：

    <script src="/assets/lib/@plotdb/lotion/main/index.min.js"></script>
    <script src="/assets/lib/@plotdb/sfx/main/index.min.js"></script>
    <script>
    const S = window.sfx;
    </script>

頁面上有 `lotion.player` 時會自動攔截它的 play / pause / seek，不用另外接。


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
| `chime` | `dur` ( 1.4 ) | `note` ( E6 ) | 鈴聲、完成一步 |
| `success` | 0.9s | | 成功 ( C-E-G 琶音 ) |
| `notify` | 0.7s | | 通知 |
| `whoosh` | `dur` ( 0.7 ) | `from` ( 400 )、`peak` ( 2600 )、`to` ( 600 )、`at` ( 0.45 )、`q` ( 1.2 ) | 轉場 |
| `swell` | `dur` ( 2 ) | | 段落前的醞釀 |
| `pluck` | `dur` ( 2.5 ) | `note` ( A3 )、`bright` ( 0~1 )、`slide` ( 半音 ) | 撥弦 ( 類古箏 ) |
| `melody` | 自動 | `notes: [[t, note, dur, vel], ...]`、`bright`、`slide` | 撥弦旋律 |
| `drone` | `dur` ( 8 ) | `notes` ( [A1, E2, A2] )、`attack`、`release` | 持續低音 |
| `wind` | `dur` ( 6 ) | `cutoff` ( 900 ) | 風 |
| `rain` | `dur` ( 6 ) | `density` ( 0.02 ) | 雨 |
| `buzz` | `dur` ( 1.5 ) | `freq` ( 220 ) | 昆蟲振翅 |

`whoosh` 是帶通濾波的雜訊，中心頻率依 `from` → `peak` → `to` 走，在 `at` ( 0~1 ) 處最亮最響：

 - 短促的掃過：`{dur: 0.35}`；更短更乾淨：`{dur: 0.25, q: 2}`。
 - 往上衝：`{from: 300, peak: 3500, to: 3000, at: 0.8}`；往下沉：`{from: 3000, peak: 3000, to: 300, at: 0.1}`。
 - `q` 小 ( 0.5 ) 像風，大 ( 3 ) 像哨音。


## 混音與檢查

 - 建議音量：配樂 0.3~0.4、音效 0.6~1、旁白 1。
 - `S.report()`：載入的聲音 ( 長度、起音點 )、時間軸數量、播放狀態、AudioContext 狀態、最近的錯誤。
 - `S.peak(buffer)`：起音點 ( 秒 )。
 - `S.render(duration)`：離線混音，回傳 Promise<AudioBuffer>。`S.wav(buffer)`：轉成 16-bit wav Blob。
