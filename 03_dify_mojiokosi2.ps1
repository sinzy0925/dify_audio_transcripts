# Ensure output encoding is UTF-8, can be helpful
# $OutputEncoding = [System.Text.Encoding]::UTF8

# --- Dify API Settings (★ Replace with your actual values) ---
$DifyApiBaseUrl = "https://api.dify.ai/v1" # Base URL of your Dify instance
$DifyFileUploadEndpoint = "$DifyApiBaseUrl/files/upload"
$DifyWorkflowRunEndpoint = "$DifyApiBaseUrl/workflows/run" # Workflow endpoint
$DifyApiKey = "app-eAx08D3rouMzJKNBKfFZGupk" # ★ Your Dify App API Key
$UserIdentifier = "powershell_user_$(Get-Random)" # Unique user ID for each run (optional)

# --- Dify Workflow Variable Names (★ As per your Dify setup) ---
$DifyWorkflowAudioInputVariable = "input"    # Variable name for audio file input in workflow
$DifyWorkflowOutputVariable = "text"      # Variable name for transcription output in workflow

# --- Retry Settings for Workflow Execution ---
$MaxRetriesWorkflow = 1       # Max number of retries (total attempts = 1 + MaxRetries)
$RetrySleepSecondsWorkflow = 5 # Seconds to wait before retrying

# --- Target File Pattern and Location (★ Modify as needed) ---
$FilePattern = "output_*.m4a"
$AudioFilesDirectory = ".\" # If in the same directory as the script. Use full path otherwise (e.g., "C:\path\to\audio_files")

# --- Script Output Directory ---
$OutputDirectory = ".\dify_transcripts_workflow" # Directory to save results

# ★★★ ここから追加 ★★★
# Check if the output directory exists and delete it recursively if it does
if (Test-Path $OutputDirectory) {
    Write-Host "既存の出力ディレクトリ「$OutputDirectory」が見つかりました。中身ごと削除します..."
    try {
        Remove-Item -Path $OutputDirectory -Recurse -Force -ErrorAction Stop
        Write-Host "ディレクトリ「$OutputDirectory」を正常に削除しました。" -ForegroundColor Green
    } catch {
        Write-Error "ディレクトリ「$OutputDirectory」の削除中にエラーが発生しました: $($_.Exception.Message)"
        # エラーが発生した場合、スクリプトを続行するか停止するかを決定
        # ここでは続行するが、場合によっては exit 1 などで停止することも検討
        Write-Warning "ディレクトリ削除に失敗しましたが、処理を続行します。"
    }
    Write-Host ""
}
# ★★★ ここまで追加 ★★★

if (-not (Test-Path $OutputDirectory)) {
    New-Item -ItemType Directory -Path $OutputDirectory | Out-Null
}

# --- Headers ---
$FileUploadAuthHeader = @{ # For Step A
    "Authorization" = "Bearer $DifyApiKey"
}
$WorkflowRunHeaders = @{ # For Step B, Content-Type is application/json
    "Authorization" = "Bearer $DifyApiKey"
    "Content-Type"  = "application/json"
}

# --- Find Target Files ---
$AudioFiles = Get-ChildItem -Path $AudioFilesDirectory -Filter $FilePattern

if ($AudioFiles.Count -eq 0) {
    Write-Warning "No target files found: $AudioFilesDirectory\$FilePattern"
    exit
}

Write-Host "Starting to send files to Dify Workflow API for transcription..."
Write-Host ""

foreach ($AudioFile in $AudioFiles) {
    $CurrentAudioFilePath = $AudioFile.FullName
    $FileNameNoExt = $AudioFile.BaseName # Filename without extension

    Write-Host "--------------------------------------------------"
    Write-Host "Processing file: $CurrentAudioFilePath"

    # --- Step A: File Upload (Using Invoke-WebRequest for MIME type control) ---
    Write-Host "  Step A: Uploading file '$($AudioFile.Name)' with Invoke-WebRequest..."
    $UploadResponsePath = Join-Path -Path $OutputDirectory -ChildPath "upload_response_$FileNameNoExt.json"
    $UploadFileId = $null

    try {
        # ... (ファイルアップロードのコードは変更なし - 前回のバージョンを使用) ...
        $FileBytes = [System.IO.File]::ReadAllBytes($CurrentAudioFilePath)
        $FileName = $AudioFile.Name
        $Boundary = "---------------------------$([System.Guid]::NewGuid().ToString())"
        $CRLF = "`r`n"
        $BodyLines = @(
            "--$Boundary",
            "Content-Disposition: form-data; name=`"user`"$CRLF",
            $UserIdentifier,
            "--$Boundary",
            "Content-Disposition: form-data; name=`"file`"; filename=`"$FileName`"",
            "Content-Type: audio/m4a$CRLF"
        )
        $BodyPrefixString = ($BodyLines -join $CRLF) + $CRLF
        $BodySuffixString = "$CRLF--$Boundary--$CRLF"
        $PrefixBytes = [System.Text.Encoding]::UTF8.GetBytes($BodyPrefixString)
        $SuffixBytes = [System.Text.Encoding]::UTF8.GetBytes($BodySuffixString)
        $FullRequestBodyBytes = New-Object byte[] ($PrefixBytes.Length + $FileBytes.Length + $SuffixBytes.Length)
        [System.Array]::Copy($PrefixBytes, 0, $FullRequestBodyBytes, 0, $PrefixBytes.Length)
        [System.Array]::Copy($FileBytes, 0, $FullRequestBodyBytes, $PrefixBytes.Length, $FileBytes.Length)
        [System.Array]::Copy($SuffixBytes, 0, $FullRequestBodyBytes, ($PrefixBytes.Length + $FileBytes.Length), $SuffixBytes.Length)
        $UploadContentType = "multipart/form-data; boundary=`"$Boundary`""
        $RawUploadResponse = Invoke-WebRequest -Uri $DifyFileUploadEndpoint -Method Post -Headers $FileUploadAuthHeader -Body $FullRequestBodyBytes -ContentType $UploadContentType -UseBasicParsing -SkipHttpErrorCheck
        if ($RawUploadResponse.StatusCode -ge 400) {
            Write-Error "  Error: File upload failed with status code $($RawUploadResponse.StatusCode)."
            $ErrorBody = $RawUploadResponse.Content
            Write-Warning "    Error response body (Upload): $ErrorBody"
            $ErrorBody | Out-File -FilePath $UploadResponsePath -Encoding UTF8
            Continue
        }
        $UploadResponse = $RawUploadResponse.Content | ConvertFrom-Json
        $UploadResponse | ConvertTo-Json -Depth 5 | Out-File -FilePath $UploadResponsePath -Encoding UTF8
        $UploadFileId = $UploadResponse.id
        if (-not $UploadFileId) {
            Write-Error "  Error: Failed to get upload_file_id. Check response: $UploadResponsePath"
            Continue
        }
        Write-Host "    Upload successful. upload_file_id: $UploadFileId, Sent MIME Type for file: audio/m4a"
    } catch {
        Write-Error "  Error: Unexpected exception during file upload: $($_.Exception.Message)"
        Continue
    }

    # --- Step B: Run Workflow (Transcription Request) with Retry Logic ---
    Write-Host "  Step B: Running workflow (upload_file_id: $UploadFileId)..."
    $WorkflowPayloadPath = Join-Path -Path $OutputDirectory -ChildPath "workflow_payload_$FileNameNoExt.json"
    $WorkflowResponsePath = Join-Path -Path $OutputDirectory -ChildPath "workflow_response_$FileNameNoExt.json"

    $PayloadInputs = @{
        "$DifyWorkflowAudioInputVariable" = @{
            type             = "audio"
            transfer_method  = "local_file"
            upload_file_id   = $UploadFileId
        }
    }
    $WorkflowPayload = @{
        inputs         = $PayloadInputs
        response_mode  = "blocking"
        user           = $UserIdentifier
    }
    $WorkflowPayloadJson = $WorkflowPayload | ConvertTo-Json -Depth 5
    $WorkflowPayloadJson | Out-File -FilePath $WorkflowPayloadPath -Encoding UTF8

    $RetryCountWorkflow = 0
    $WorkflowSucceeded = $false

    while ($RetryCountWorkflow -le $MaxRetriesWorkflow -and -not $WorkflowSucceeded) {
        if ($RetryCountWorkflow -gt 0) {
            Write-Warning "    Retrying workflow execution ($($RetryCountWorkflow)/$($MaxRetriesWorkflow)). Waiting $($RetrySleepSecondsWorkflow) seconds..."
            Start-Sleep -Seconds $RetrySleepSecondsWorkflow
        }
        Write-Host "    Attempting API call (Attempt $($RetryCountWorkflow + 1))..."
        try {
            $RawWorkflowResponse = Invoke-RestMethod -Uri $DifyWorkflowRunEndpoint -Method Post -Headers $WorkflowRunHeaders -Body $WorkflowPayloadJson -SkipHttpErrorCheck

            # Check for Dify's specific error structure OR if it's a non-successful workflow status
            if ($RawWorkflowResponse.code -and ($RawWorkflowResponse.status -ge 400)) { # Direct API error (e.g., 400, 500, 504)
                Write-Error "    Error: Workflow execution failed (Dify error code: $($RawWorkflowResponse.code) - Status: $($RawWorkflowResponse.status)). Message: $($RawWorkflowResponse.message)"
                $ErrorBodyJson = $RawWorkflowResponse | ConvertTo-Json -Depth 10
                Write-Warning "      Error response body (Workflow): $ErrorBodyJson"
                $ErrorBodyJson | Out-File -FilePath $WorkflowResponsePath -Encoding UTF8 # Overwrite with last error
                if ($RawWorkflowResponse.status -lt 500) { # For 4xx errors, retrying might not help
                    Write-Warning "      Client-side error ($($RawWorkflowResponse.status)), not retrying."
                    break # Exit retry loop
                }
            } elseif ($RawWorkflowResponse.data -and $RawWorkflowResponse.data.status -and $RawWorkflowResponse.data.status -ne 'succeeded') { # Workflow executed but failed internally
                Write-Error "    Error: Workflow execution indicated failure (status: $($RawWorkflowResponse.data.status)). Error: $($RawWorkflowResponse.data.error)"
                $ErrorBodyJson = $RawWorkflowResponse | ConvertTo-Json -Depth 10
                Write-Warning "      Dify response (Workflow): $ErrorBodyJson"
                $ErrorBodyJson | Out-File -FilePath $WorkflowResponsePath -Encoding UTF8 # Overwrite
                if ($RawWorkflowResponse.data.status -eq 'failed') { # Definite failure
                     Write-Warning "      Workflow status 'failed', not retrying."
                     break # Exit retry loop
                }
            } else { # Potentially successful or unexpected good response
                $RawWorkflowResponse | ConvertTo-Json -Depth 10 | Out-File -FilePath $WorkflowResponsePath -Encoding UTF8
                Write-Host "    Workflow API call potentially successful. Response saved to $WorkflowResponsePath"

                if ($RawWorkflowResponse.data -and $RawWorkflowResponse.data.outputs -and $RawWorkflowResponse.data.outputs.$DifyWorkflowOutputVariable -ne $null) {
                    $Transcription = $RawWorkflowResponse.data.outputs.$DifyWorkflowOutputVariable
                    Write-Host "    --- Transcription Result ---"
                    Write-Host $Transcription
                    $WorkflowSucceeded = $true # Set success flag
                } else {
                    Write-Warning "    Could not find transcription in response: data.outputs.$DifyWorkflowOutputVariable"
                    Write-Warning "    Check $WorkflowResponsePath for the full response structure."
                    # Consider if this specific case should be retried or marked as failure.
                    # For now, it will retry if $WorkflowSucceeded is not set.
                }
            }
        } catch {
            Write-Error "    Error: Unexpected exception during workflow execution (Attempt $($RetryCountWorkflow + 1)): $($_.Exception.Message)"
            # This catch is for network errors etc., before a Dify JSON response is received.
        }

        if (-not $WorkflowSucceeded -and $RetryCountWorkflow -lt $MaxRetriesWorkflow) {
            Write-Host "    Workflow attempt failed. Will retry if applicable."
        }
        $RetryCountWorkflow++
    } # End of while loop

    if (-not $WorkflowSucceeded) {
        Write-Error "  Step B: Workflow execution ultimately failed for file '$($AudioFile.Name)' after $($MaxRetriesWorkflow + 1) attempts."
    }
    Write-Host ""
} # End of foreach loop


# --- 全ての文字起こし結果を1つのテキストファイルにまとめる ---
# ... (この部分のコードは変更なし - 前回のバージョンを使用) ...
$CombinedTranscriptionFile = Join-Path -Path $OutputDirectory -ChildPath "all_transcriptions.txt"
Write-Host "--------------------------------------------------"
Write-Host "全ての文字起こし結果を $CombinedTranscriptionFile にまとめています..."
if (Test-Path $CombinedTranscriptionFile) {
    Remove-Item $CombinedTranscriptionFile
}
Get-ChildItem -Path $OutputDirectory -Filter "workflow_response_*.json" | ForEach-Object {
    $ResponseFilePath = $_.FullName
    $OriginalFileName = $_.BaseName -replace "workflow_response_", ""
    Write-Host "  処理中: $ResponseFilePath (元ファイル: $OriginalFileName.m4a)"
    try {
        $JsonResponse = Get-Content -Path $ResponseFilePath -Raw | ConvertFrom-Json -ErrorAction Stop
        if ($JsonResponse.data -and $JsonResponse.data.outputs -and $JsonResponse.data.outputs.$DifyWorkflowOutputVariable -ne $null) {
            $TranscriptionText = $JsonResponse.data.outputs.$DifyWorkflowOutputVariable
            #Add-Content -Path $CombinedTranscriptionFile -Value "--- Transcription for: $OriginalFileName.m4a ---"
            Add-Content -Path $CombinedTranscriptionFile -Value $TranscriptionText
            Add-Content -Path $CombinedTranscriptionFile -Value ""
            Add-Content -Path $CombinedTranscriptionFile -Value ""
        } elseif ($JsonResponse.code -and $JsonResponse.message) {
            Add-Content -Path $CombinedTranscriptionFile -Value "--- Error for: $OriginalFileName.m4a ---"
            Add-Content -Path $CombinedTranscriptionFile -Value "Error Code: $($JsonResponse.code)"
            Add-Content -Path $CombinedTranscriptionFile -Value "Error Message: $($JsonResponse.message)"
            Add-Content -Path $CombinedTranscriptionFile -Value ""
            Add-Content -Path $CombinedTranscriptionFile -Value "--------------------------------------------------"
            Add-Content -Path $CombinedTranscriptionFile -Value ""
        } else {
            Write-Warning "    $ResponseFilePath から文字起こし結果を抽出できませんでした。内容は成功したレスポンス形式ではありません。"
            Add-Content -Path $CombinedTranscriptionFile -Value "--- No valid transcription found for: $OriginalFileName.m4a ---"
            Add-Content -Path $CombinedTranscriptionFile -Value ""
            Add-Content -Path $CombinedTranscriptionFile -Value "--------------------------------------------------"
            Add-Content -Path $CombinedTranscriptionFile -Value ""
        }
    } catch {
        Write-Warning "    $ResponseFilePath の読み込みまたはJSONパースに失敗しました: $($_.Exception.Message)"
        Add-Content -Path $CombinedTranscriptionFile -Value "--- Failed to process: $OriginalFileName.m4a (Error reading or parsing JSON) ---"
        Add-Content -Path $CombinedTranscriptionFile -Value ""
        Add-Content -Path $CombinedTranscriptionFile -Value "--------------------------------------------------"
        Add-Content -Path $CombinedTranscriptionFile -Value ""
    }
}
if (Test-Path $CombinedTranscriptionFile) {
    Write-Host "文字起こし結果が $CombinedTranscriptionFile に保存されました。"
} else {
    Write-Warning "$CombinedTranscriptionFile は作成されませんでした。処理対象のレスポンスファイルがなかったか、エラーが発生しました。"
}
Write-Host "--------------------------------------------------"
Write-Host "All processing complete."