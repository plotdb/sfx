# Change Logs

## master

 - feature: demo 網站改用專案慣例 ( `web/src/pug` 經 `@zbryikt/template` 建置到 `web/static` )，取代手寫的 `web/index.html`
   - 合成聲：每種聲音以滑桿 / 欄位調參數、範例標籤、波形與播放進度、可複製的程式碼
   - 時間軸：可編輯的場景 ( JSON )、播放 / 暫停 / 拖曳 / 倍速、各項的檔案範圍與擊點、離線混成 wav
   - bus 音量 ( master / music / sfx / voice )
 - bug fix: `synth.pluck` ( 與 `synth.melody` ) 的 `slide: 0` 被當成預設值 0.6，現在可以關掉滑音
 - tweak: `./build` 改把 `dist/` 複製到 `web/static/assets/lib/@plotdb/sfx/dev/`


## v0.0.1

 - 從 Shelf 的 shelfSound 抽出的音訊 runtime 與程序化合成
