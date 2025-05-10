# スクリプトの実行には管理者権限が必要な場合があります。

# --- PowerShell 7 のインストール状況を確認 ---
Write-Host "PowerShell 7 のインストール状況を確認しています..."
$pwshPath = Get-Command pwsh -ErrorAction SilentlyContinue

if ($pwshPath) {
    $pwshVersion = (pwsh -Command "$PSVersionTable.PSVersion").ToString()
    Write-Host "PowerShell 7 (またはそれ以降) が既にインストールされています。" -ForegroundColor Green
    Write-Host "バージョン: $pwshVersion"
    Write-Host "パス: $($pwshPath.Source)"
    pwsh
} else {
    Write-Warning "PowerShell 7 はインストールされていないようです。"
    Write-Host "Winget を使用して PowerShell 7 (安定版) のインストールを試みます..."
    Write-Host "この処理には管理者権限が必要な場合があります。"

    # Wingetが利用可能か確認
    $wingetPath = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $wingetPath) {
        Write-Error "Winget コマンドが見つかりません。PowerShell 7 を手動でインストールしてください。"
        Write-Host "手動インストールの情報: https://learn.microsoft.com/ja-jp/powershell/scripting/install/installing-powershell-on-windows"
        exit 1
    }

    # 現在のユーザーが管理者権限を持っているか簡易的に確認
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if (-not $isAdmin) {
        Write-Warning "スクリプトが管理者権限で実行されていません。"
        Write-Warning "PowerShell 7 のインストールには管理者権限が必要です。"
        $choice = Read-Host "現在のセッションを管理者として再起動してインストールを試みますか？ (y/n)"
        if ($choice -eq 'y') {
            Start-Process pwsh -Verb RunAs -ArgumentList "-NoProfile -File `"$($MyInvocation.MyCommand.Path)`""
            exit
        } else {
            Write-Host "インストールを中止しました。手動でインストールするか、管理者としてスクリプトを再実行してください。"
            exit 1
        }
    }

    # Wingetを使ってPowerShell (安定版) をインストール
    # "--accept-source-agreements" と "--accept-package-agreements" で一部のプロンプトをスキップできる場合がある
    $InstallCommand = "winget install --id Microsoft.PowerShell --source winget --accept-source-agreements --accept-package-agreements -h" # -h でサイレントインストールを試みる

    Write-Host "以下のコマンドでインストールを実行します: $InstallCommand"
    Write-Host "インストールには数分かかることがあります。プロンプトが表示された場合は指示に従ってください。"

    try {
        Invoke-Expression -Command $InstallCommand -ErrorAction Stop
        Write-Host "PowerShell 7 のインストールコマンドが実行されました。" -ForegroundColor Green
        Write-Host "インストールが成功したか確認してください。"
        Write-Host "新しいPowerShell 7のウィンドウを開くには 'pwsh' と入力するか、スタートメニューから検索してください。"

        # インストール後の確認 (パスが通るのに時間がかかる場合がある)
        Write-Host "インストール後の確認を試みます..."
        Start-Sleep -Seconds 10 # パスが反映されるのを待つ
        $pwshPathAfterInstall = Get-Command pwsh -ErrorAction SilentlyContinue
        if ($pwshPathAfterInstall) {
            $pwshVersionAfterInstall = (pwsh -Command "$PSVersionTable.PSVersion").ToString()
            Write-Host "PowerShell 7 が正常にインストールされたようです。" -ForegroundColor Green
            Write-Host "バージョン: $pwshVersionAfterInstall"
            Write-Host "パス: $($pwshPathAfterInstall.Source)"
        } else {
            Write-Warning "PowerShell 7 のインストール確認に失敗しました。手動で確認してください。"
            Write-Warning "PCの再起動が必要な場合や、パスが反映されるのにもう少し時間がかかる場合があります。"
        }

    } catch {
        Write-Error "PowerShell 7 のインストール中にエラーが発生しました: $($_.Exception.Message)"
        if ($_.Exception.ErrorRecord) {
            Write-Error ($_.Exception.ErrorRecord | Format-List * -Force | Out-String)
        }
        Write-Host "手動でのインストールを検討してください: https://learn.microsoft.com/ja-jp/powershell/scripting/install/installing-powershell-on-windows"
    }
}

Write-Host ""
Write-Host "スクリプトの処理が完了しました。"