# 打刻リマインダー

Outlookの「出社」「退社」予定の5分前に、KING OF TIMEの打刻を促すMacアプリです。

## ZIPからインストール（Node.js不要）

[Releases](https://github.com/ibj-labo/outlook-attendance-reminder/releases)から配布用の `AttendanceReminder-Mac-v2.1.0.zip` を取得します。GitHubが自動生成する「Source code」のZIPは開発用ソースです。

1. 配布用ZIPを解凍します。
2. 「打刻リマインダー.app」をFinderの「アプリケーション」へ移動します。
3. 移動したアプリを開き、「予定表を設定・変更」で自分のOutlook予定表のICSリンクを登録します。

Node.jsや開発用ツールの準備は不要です。詳しい使い方と制限は、ZIP内の「使い方.txt」にあります。配布者の予定表リンク・予定データ・通知履歴は含めません。

## Gitからインストール

このリポジトリを取得して、次のコマンドを実行します。非公開リポジトリの場合は、先にアクセス権を持つGitHubアカウントで認証してください。

```sh
git clone https://github.com/ibj-labo/outlook-attendance-reminder.git
cd outlook-attendance-reminder
npm install
```

Macの「アプリケーション」に「打刻リマインダー」が入り、設定画面が開きます。管理者権限で書き込めないMacでは、自分のホームフォルダの「アプリケーション」に入ります。sudoは不要です。

**Node.jsを入れていない場合**は、フォルダ内の `install.command` をダブルクリックするか、次を実行してください。

```sh
bash install.command
```

アプリ専用のNode.jsとライブラリを自動取得して同梱します。Xcode・開発用ツールの準備は不要です。Node.jsやライブラリの取得にインターネット接続が必要です。既存のNode.jsの設定は変更しません。

インストール後は取得したフォルダを削除しても使えます。Finderの「アプリケーション」またはSpotlightで「打刻リマインダー」を開いてください。

## 初回の設定

1. アプリの「予定表を設定・変更」を開きます。
2. **自分の**Outlook予定表のICSリンクを入力します。
3. 接続を確認できると通知を開始します。「表示をテスト」で表示を確認できます。

ICSリンクはOutlook Webの「設定 → 予定表 → 共有の予定表 → 予定表の公開」で取得します。予定名が見える公開範囲を選び、HTMLリンクではなくICSリンクを使ってください。会社が予定表の公開を許可していない場合、この方式では接続できません。[Microsoftの手順](https://support.microsoft.com/en-us/outlook/share-your-calendar-in-outlook-on-the-web)

ICSリンクを持つ人は公開された予定表を読めるため、他人に送らないでください。リンク・予定データ・通知履歴は各自のMacに保存し、このリポジトリには含めません。

## 使い方

- 出社・退社予定の5分前に「打刻しましょう！」と画面に出ます。
- 再通知は10分後・30分後・1時間後・2時間後から選べます。初期選択は10分後です。
- 「閉じる」でその通知の再通知を終了します。
- 「表示をテスト」は表示と選択肢を確認するだけで、実際の再通知は予約しません。
- 「通知を停止／通知を再開」は、Macを再起動しても維持します。

設定画面を閉じても通知は続きます。Macにログインして使用中に動作し、Outlook・ブラウザ・Codexを開いておく必要はありません。打刻は自分で行います。

## 通知対象と時刻

予定名は「出社」「退社」、または「【出社】9:45」「18:45 退社」などを対象にします。他の会議・終日予定・キャンセルされた予定は対象外です。繰り返し予定の日ごとの変更・除外にも対応します。

出社が0:00〜9:45のブロックなら終了時刻の5分前、通常の9:45開始の予定なら開始時刻の5分前に通知します。退社は開始時刻の5分前です。件名に書かれた時刻ではなく、予定表の実際の日時を使います。

予定表を5分ごとに取得し、毎分通知時刻を確認します。変更はOutlookの配信データに反映された後に取り込みます。スリープ中は画面を出せません。予定の5分前〜予定時刻に復帰した場合はその時点で通知し、予定時刻を過ぎた古い通知は出しません。通信エラー時は再試行し、取得から15分以内の予定だけを一時的に使います。

## 更新・削除

更新するときはGitから新しい版を取得し、再度 `npm install` または `bash install.command` を実行します。設定・通知履歴はアプリの外に保存するため、そのまま引き継ぎます。

削除するときはアプリの「通知を停止」を押してから、アプリをゴミ箱へ移動してください。個人設定は `~/Library/Application Support/OutlookAttendanceReminder`、自動実行設定は `~/Library/LaunchAgents/com.outlook-attendance-reminder.calendar.plist` にあります。

## 対応環境

macOS 11以降、Appleシリコン／Intel向けです。同梱の小さな実行ファイルは両方に対応し、Node.jsはそのMac用だけを取得します。AppleシリコンのMacで検証しています。Intel実機では未検証です。

Apple Developerの配布署名・公証は未対応です。初回にmacOSの確認が出る場合は、組織のルールに従って許可してください。[Appleの案内](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unknown-developer-mh40616/mac)

## 開発

依存ライブラリだけを取得する場合は、アプリをインストールするスクリプトを止めて実行します。

```sh
npm ci --ignore-scripts
npm test
```

画面のソースは `source/launcher.m`、予定表処理は `source/calendar-core.cjs` と `source/calendar-reminder.cjs` です。ネイティブ実行ファイルは約200KBだけをGitで管理し、大きなNode.js本体や個人設定はGitに入れません。

画面のソースを変更した場合は、XcodeまたはCommand Line Toolsを準備したMacで次を実行し、`native/launcher` と `native/launcher.sha256` を一緒に更新してください。

```sh
npm run build:native
```

Node.js 22.23.3は[公式配布物](https://nodejs.org/download/release/v22.23.3/)を取得し、固定した公式SHA-256で検証します。依存ライブラリは `package-lock.json` で固定します。ライセンスはアプリ内の各ライブラリとNode.jsに同梱しています。[同梱ソフトウェア](source/THIRD_PARTY_NOTICES.md)
