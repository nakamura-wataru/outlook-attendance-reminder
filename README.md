# 打刻リマインダー

出勤・退勤の打刻を忘れないためのMacアプリです。月〜金の予定を設定すると、出勤の5分前と退勤時刻にお知らせします。通知からKING OF TIMEの打刻画面も開けます。

macOS 11以降のAppleシリコン・Intel Macに対応しています。

## インストール

ターミナルで次を実行してください。GitHubアカウントは不要です。

```sh
git clone https://github.com/nakamura-wataru/outlook-attendance-reminder.git
cd outlook-attendance-reminder
bash install.command
```

インストールが終わると「打刻リマインダー」が開きます。次回からはFinderの「アプリケーション」またはSpotlightから開けます。

初回にmacOSの確認画面が出た場合は、組織のルールに従って許可してください。[Appleの手順](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unknown-developer-mh40616/mac)

## 通知を設定する

1. アプリで「通知の予定を設定」を開きます。
2. 全曜日が同じ時刻なら、「共通の時刻」に出勤・退勤を入力して「月〜金に適用」を押します。曜日ごとに違う場合は、下の表で入力します。通知しない曜日はチェックを外します。
3. 「保存して開始」を押します。

<img width="554" height="469" alt="Image" src="https://github.com/user-attachments/assets/e169bc09-ffbe-4fac-9041-7fac67451086" />

たとえば出勤を9:45、退勤を18:45にすると、9:40と18:45に通知します。日本時間で毎週繰り返します。祝日も、チェックした曜日なら通知します。

メイン画面の時計のカードには、次の通知時刻が表示されます。

## KING OF TIMEで打刻する

初回はアプリの「KING OF TIMEで打刻」を押し、普段使うMyレコーダーの接続先とログイン方法を選んでログインしてください。

通知が来たら「打刻画面を開く」を押し、表示されたMyレコーダーで出勤・退勤を打刻します。まだ仕事中なら、10分後・30分後・1時間後・2時間後から時間を選んで再通知できます。

<img width="547" height="311" alt="Image" src="https://github.com/user-attachments/assets/d992e037-ed2a-4d3d-b03a-7b0eeb35649a" />

ログインや打刻ができない場合は「ブラウザで開く」を使ってください。接続先やログイン方法は「接続設定」から変更できます。

「表示をテスト」では通知画面を確認できます。打刻画面を開くと公式の画面が表示されるため、そこで打刻すると実際の勤怠に記録されます。テストで再通知は予約されません。

## 通知を止める・再開する

「通知を停止」「通知を再開」で切り替えられます。設定画面を閉じたり、Macを再起動したりしても、停止・再開の状態は引き継がれます。

Macがスリープ中は通知を表示できません。復帰後、通知時刻から5分以内であればお知らせします。

## 更新と削除

更新するときは、最初に取得したフォルダにある `update.command` をダブルクリックしてください。曜日・時刻の設定や停止状態は引き継がれます。

ターミナルから更新する場合は、次を実行します。

```sh
git pull
bash install.command
```

以前の版でOutlook予定表のリンクを登録していた場合、更新時にリンクと取得済みの予定データをMacから削除します。Outlookで予定表を公開したままなら、Outlook側でも公開を停止してください。[Microsoftの手順](https://support.microsoft.com/en-us/outlook/share-your-calendar-in-outlook-on-the-web)

削除するときは「通知を停止」を押してから、アプリをゴミ箱へ移動してください。
