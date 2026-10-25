# Change Logs

## v0.0.5

 - fix: lotion 0.10 的循環 ( `loop: true`、`player.loop(a, b)` ) 接回時聲音沒有跟著回去: 接回走 lotion 內部的 `_seek`,
   原本只攔截 `seek`. 改為攔截 `_seek` ( lotion 0.9 起; 較舊的版本照舊攔截 `seek` )

## v0.0.4

 - fix: 倍速時 ( `<audio>` 保持音高的路徑 ) 旁白 / 配樂結尾被切掉: 停止與淡出原本從排程時間起算, 沒算到載入、跳轉、play 的延遲;
   改為從實際發聲 ( `playing` ) 起算, 播到檔案結尾的交給 `onended`, 只有循環或刻意截短的才排停止

## v0.0.3

 - feature: 變化機制 ( 預設不變 )
   - 所有合成聲可加 `vary` ( 0~1 ): 換雜訊、音高與長度微調、音量略小; 同 seed 可重現
   - `S.variants(name, opt, count)`: 一次產生多個變化
   - 時間軸項目的 `sound` 可為陣列 ( 依位置與時間挑一個 ), 項目可加 `vary`; 皆可重現, 離線混音一致
   - `S.play` 可給陣列與 `vary` ( 隨機 )
   - `S.mutate(name, opt, {amount, seed})`: 以目前參數為中心產生變化的參數 ( 數值常態分布、選項隨機挑 )
 - feature: `S.params[name]`: 每種合成聲的參數定義 ( 範圍、預設、選項 ), demo 頁由它產生控制項
 - feature: demo 頁最上面加上全部音效的清單: 點名稱播預設, 點 🎲 播隨機變化; 每張卡片加 `vary` 與 🎲 ( 以目前設定為中心變化 )
 - feature: 樂譜: `S.synth.score({score, instrument, bpm})` 依文字樂譜 ( `C4/4 D4 E4/8. ...` ) 用任何聲音演奏
   ( 有 note 參數的合成聲以音高合成, 其他聲音以 base 為準變調 ); `S.score` / `S.score.parse` / `S.score.duration`
 - feature: `synth.melody` 新增 `release` ( 每個音之後的尾音, 預設 0.8 不變 )
 - feature: demo 頁新增五線譜 ( 4/4 拍 4 小節, 鍵盤編輯音長 / 附點 / 休止、拖曳改音高, 與樂譜文字雙向同步, 選樂器或 🎲 隨機 )
 - tweak: demo 頁標題改為「音效清單」與「全部音效：合成細節」; 混音器移到時間軸區
 - tweak: demo 頁資源改用相對路徑, `npm run deploy` 以 @zbryikt/deploy 發佈到 GitHub Pages ( 只帶用到的檔案 )
 - tweak: demo 頁先畫畫面再分批產生聲音, 並在畫好前隱藏, 不再閃出空的模板


## v0.0.2

 - feature: 新增合成聲
   - 動作：`slide` `rise` `fall` `count` `snap` `draw` `glitch`，以及通用的 `sweep`
   - 敘事：`reveal` `error` `tension` `heartbeat` `clock`
   - 擬音：`paper` `water` `fire` `steps` `bell` `thunder`
   - 樂器：`marimba` `xylophone` `vibraphone` `glockenspiel` ( 模態合成 )、`guitar` ( 單音或刷和弦 )
   - 人聲與人體：`fingersnap` ( 打響指 ) `huh` ( 蛤? ) `yay` ( 耶! )，人聲以共振峰合成
   - 答題：`correct` ( 叮咚 / 琶音 ) `wrong` ( 噗噗 / 悲傷長號 )
   - 鼓組：`kick` `snare` `hihat` `tom` `clap` `crash` `ride`，以及節奏器 `beat`
   - 擬音與鈸 ( `crash` `ride` `thunder` `steps` `paper` `water` ) 依真實錄音的頻譜與衰減分析調整；`steps` 有 `gait: run`
 - feature: 全部合成聲都可以加 `reverb` / `room` 殘響；另有 `S.reverb(buffer, {mix, room})`
 - feature: `synth.melody` 新增 `instrument`，可以換成任一有 `note` 參數的聲音 ( 預設仍是 `pluck` )
 - tweak: `whoosh` 與 `swell` 改用連續的時變濾波，去掉分段濾波造成的接縫雜音 ( 質感會略有不同 )
 - feature: demo 網站改用專案慣例 ( `web/src/pug` 經 `@zbryikt/template` 建置到 `web/static` )，取代手寫的 `web/index.html`
   - 合成聲：每種聲音以滑桿 / 欄位調參數、範例標籤、波形與播放進度、可複製的程式碼
   - 時間軸：可編輯的場景 ( JSON )、播放 / 暫停 / 拖曳 / 倍速、各項的檔案範圍與擊點、離線混成 wav
   - bus 音量 ( master / music / sfx / voice )
 - bug fix: `synth.pluck` ( 與 `synth.melody` ) 的 `slide: 0` 被當成預設值 0.6，現在可以關掉滑音
 - bug fix: `synth.pluck` 給了 `bright` 時 `slide` 沒有設定，整段變成 NaN ( 無聲 )；同一行 `if ... else x; y = ...` 會把後面的設定吞進 else
 - tweak: `./build` 改把 `dist/` 複製到 `web/static/assets/lib/@plotdb/sfx/dev/`


## v0.0.1

 - 從 Shelf 的 shelfSound 抽出的音訊 runtime 與程序化合成
