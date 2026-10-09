on reminderDelayForChoice(reminderChoice)
    if reminderChoice is "10分後" then return 600
    if reminderChoice is "30分後" then return 1800
    if reminderChoice is "1時間後" then return 3600
    if reminderChoice is "2時間後" then return 7200
    error "再通知の時間を選択してください。" number -1700
end reminderDelayForChoice

on chooseReminderDelay(reminderTitle, reminderMessage)
    activate
    set reminderChoices to {"10分後", "30分後", "1時間後", "2時間後"}
    set reminderSelection to choose from list reminderChoices with title reminderTitle with prompt ("打刻しましょう！" & return & return & reminderMessage & return & return & "再通知までの時間を選んでください。") default items {"10分後"} OK button name "再通知" cancel button name "閉じる" multiple selections allowed false empty selection allowed false
    if reminderSelection is false then return false
    return my reminderDelayForChoice(item 1 of reminderSelection)
end chooseReminderDelay

on run
    try
        set reminderSeconds to my chooseReminderDelay("リマインダー表示テスト", "表示テストです。" & return & "実際の出社・退社予定の通知ではありません。")
        if reminderSeconds is false then return
        display dialog "表示テストです。" & return & return & ((reminderSeconds / 60) as integer) & "分後を選択しました。" & return & "実際の再通知は予約しません。" with title "リマインダー表示テスト" buttons {"閉じる"} default button "閉じる" cancel button "閉じる" with icon note giving up after 8
    on error errorMessage number errorNumber
        if errorNumber is not -128 then error errorMessage number errorNumber
    end try
end run
