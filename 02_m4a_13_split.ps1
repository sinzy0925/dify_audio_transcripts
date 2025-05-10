$IntermediateFile = "out_1.3x.m4a" # ffmpegスクリプトで使用する中間ファイル名に合わせてください

# --- 中間ファイルが存在すれば削除 ---
if (Test-Path $IntermediateFile) {
    Write-Host "ファイル「$IntermediateFile」を削除します..."
    try {
        Remove-Item -Path $IntermediateFile -Force -ErrorAction Stop
        Write-Host "ファイル「$IntermediateFile」を削除しました。"
    } catch {
        Write-Warning "ファイル「$IntermediateFile」の削除に失敗しました: $($_.Exception.Message)"
        # ここでスクリプトを停止するか、続行するかは要件によります
    }
    Write-Host ""
}

$FilePatternToDelete = "output_???.m4a" # "?" は任意の1文字にマッチ。数字3桁にマッチさせる。
                                       # または "output_*.m4a" でも可 (output_で始まる全てのm4a)

# --- ファイルが存在するディレクトリ (スクリプトと同じ場所を想定) ---
$TargetDirectory = ".\" # カレントディレクトリ
# もし特定のディレクトリを指定する場合はフルパスで:
# $TargetDirectory = "C:\path\to\your\audio_files"

Write-Host "ディレクトリ「$((Resolve-Path $TargetDirectory).Path)」内のパターン「$FilePatternToDelete」に一致するファイルを検索・削除します..."

# パターンに一致するファイルを取得
$FilesToDelete = Get-ChildItem -Path $TargetDirectory -Filter $FilePatternToDelete -File # -File でファイルのみを対象

if ($FilesToDelete.Count -gt 0) {
    Write-Host "$($FilesToDelete.Count) 個の対象ファイルが見つかりました。"
    foreach ($File in $FilesToDelete) {
        $FilePath = $File.FullName
        Write-Host "  削除中: $FilePath"
        try {
            Remove-Item -Path $FilePath -Force -ErrorAction Stop
            Write-Host "    削除成功: $FilePath" -ForegroundColor Green
        } catch {
            Write-Error "    削除失敗: $FilePath - エラー: $($_.Exception.Message)"
        }
    }
    Write-Host "指定されたパターンのファイルの削除処理が完了しました。"
} else {
    Write-Host "パターン「$FilePatternToDelete」に一致するファイルは見つかりませんでした。"
}

Write-Host ""
Write-Host ""

# --- コマンド1: 1.3倍速にする ---
Write-Host "Geminiが間違わない程度に早くして、ファイルサイズを小さくする。"
Write-Host "コマンド1: input.m4a を1.3倍速にして out_1.3x.m4a に保存します..."
ffmpeg -i input.m4a -filter:a "atempo=1.3" -vn out_1.3x.m4a

Write-Host "コマンド1 完了。"
Write-Host "" # 改行

# --- コマンド2: 分割する ---
Write-Host "Gemini文字起こしが、７分ではエラー　６分ならOKだが、余裕を見て４分(240秒)に分割する"
Write-Host "コマンド2: out_1.3x.m4a を5分(300秒)ごとに output_%03d.m4a のパターンで分割します..."
ffmpeg -i out_1.3x.m4a -f segment -segment_time 240 -c copy output_%03d.m4a

Write-Host "コマンド2 完了。"
Write-Host ""

Write-Host "全てのffmpeg処理が完了しました。"