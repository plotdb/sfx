# Change Logs

## master

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
