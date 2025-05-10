**実行手順　簡易版:**
### できること：input.m4aファイルを文字起こしする。
### Geminiを使って文字起こしします。
### Geminiの文字起こしは４分程度づつにしないと失敗します。
### 02_m4a_13_split.ps1を使って、４分づつに分割します。
### 03_dify_mojiokosi2.ps1を使って、文字起こしを実施し、
### 文字起こし結果をすべてを dify_transcripts_workflow\all_transcriptions.txt 
### に出力します。

1.  （初回）`01_powershell7_install.ps1` を管理者として実行し、PowerShell 7を準備。
2.  処理したいM4Aファイルを `input.m4a` として用意。
3.  `02_m4a_13_split.ps1` を実行し、`output_XXX.m4a` ファイル群を生成。
4.  PowerShell 7 (`pwsh`) で `03_dify_mojiokosi2.ps1` を実行。
5.  `dify_transcripts_workflow\all_transcriptions.txt` に結果が出力されるのを確認。


**このアプリ（DifyワークフローとPowerShellスクリプト）の目的:**

ローカルにある複数のM4A音声ファイル（例: `output_000.m4a`, `output_001.m4a`...）を、Difyで作成した文字起こしワークフローを使って順番に処理し、その結果（文字起こしされたテキスト）を1つのテキストファイルにまとめることです。

**全体の流れ:**

1.  **準備 (初回のみ、または必要に応じて):**
    *   **PowerShell 7のインストール:** `01_powershell7_install.ps1` を使って、お使いのPCにPowerShell 7がインストールされているか確認し、なければインストールします。PowerShell 7は、後続のスクリプトを正しく実行するために必要です。
    *   **ffmpegのインストール:** `02_m4a_13_split.ps1` スクリプトは `ffmpeg` コマンドを使用します。ffmpegがPCにインストールされ、コマンドラインから呼び出せる状態になっている必要があります。
    *   **Difyワークフローの作成と設定:** `[本番]文字起こし20250510.yml` は、Difyで既に作成済みのワークフローの設定ファイルです。このワークフローがDify上で正しく設定され、「公開 (Published)」されている必要があります。

2.  **音声ファイルの前処理 (ffmpegを使用):**
    *   `02_m4a_13_split.ps1` スクリプトを実行します。
    *   このスクリプトは、まず `input.m4a` という名前の音声ファイルを1.3倍速にし、`out_1.3x.m4a` という中間ファイルを作成します。
    *   次に、その中間ファイルを指定された時間（現在は4分=240秒）ごとに `output_000.m4a`, `output_001.m4a`, ... という連番のファイルに分割します。
    *   実行前に、カレントディレクトリに `input.m4a` という名前で処理したい元の音声ファイルを置いておく必要があります。
    *   また、前回の実行で生成された `out_1.3x.m4a` や `output_XXX.m4a` ファイルがあれば、スクリプトの冒頭で自動的に削除されます。

3.  **文字起こし処理の実行 (Dify APIを使用):**
    *   `03_dify_mojiokosi2.ps1` スクリプトを実行します。
    *   このスクリプトは、まず `dify_transcripts_workflow` という出力用フォルダがあれば、その中身ごと削除してクリーンな状態にします。
    *   次に、カレントディレクトリにある `output_*.m4a` というパターンのファイル（ステップ2で生成された分割ファイル）を順番に処理します。
    *   各音声ファイルに対して、以下の処理が行われます。
        *   **ステップA (ファイルアップロード):** 音声ファイルをDifyの `/files/upload` APIにアップロードし、`upload_file_id`（Dify上でファイルを一意に識別するID）を取得します。この際、MIMEタイプは `audio/m4a` として送信されます。
        *   **ステップB (ワークフロー実行):** 取得した `upload_file_id` を使って、Difyの `/workflows/run` APIを呼び出し、文字起こしワークフローを実行します。
            *   Difyワークフロー側の `input` という変数に、アップロードした音声ファイルが渡されます。
            *   APIからのレスポンス（文字起こし結果を含むJSON）は、`dify_transcripts_workflow` フォルダ内に `workflow_response_output_XXX.json` というファイル名で保存されます。
            *   もしAPI呼び出しが失敗した場合（特に5xx系のサーバーエラーやタイムアウト）、1回だけリトライ処理が行われます。
            *   文字起こし結果（Difyワークフローの `text` という出力変数）がコンソールに表示されます。
    *   全ての音声ファイルの処理が終わると、`dify_transcripts_workflow` フォルダ内の全ての `workflow_response_*.json` ファイルを読み込み、それぞれの文字起こし結果（またはエラー情報）を抽出して、`all_transcriptions.txt` という1つのテキストファイルにまとめます。

**各スクリプトファイルの詳細と使い方:**

**1. `01_powershell7_install.ps1`**

   *   **目的:** PowerShell 7がインストールされていなければ、`winget` を使って自動的にインストールを試みます。
   *   **使い方:**
      1.  PowerShellを**管理者として実行**します。
      2.  このスクリプトのあるディレクトリに `cd` コマンドで移動します。
      3.  `.\01_powershell7_install.ps1` を実行します。
   *   **注意点:**
      *   既にPowerShell 7がインストールされていれば、その情報を表示して `pwsh` (PowerShell 7の対話モード) に移行します。
      *   インストールされていない場合、管理者権限で実行されていなければ、管理者として再起動するか尋ねられます。
      *   `winget` が利用できない環境では動作しません。
      *   インストールにはインターネット接続が必要です。

**2. `02_m4a_13_split.ps1`**

   *   **目的:** 1つのM4A音声ファイルを1.3倍速にし、指定した時間で複数のファイルに分割します。
   *   **準備:**
      *   ffmpegがインストールされ、コマンドラインから `ffmpeg` コマンドが実行できる状態になっていること。
      *   スクリプトと同じディレクトリに、処理したい元の音声ファイルを `input.m4a` という名前で配置すること。
   *   **使い方:**
      1.  PowerShellコンソール (PowerShell 7推奨ですが、このスクリプト自体は5.1でも動作する可能性があります) を開きます。
      2.  このスクリプトのあるディレクトリに `cd` コマンドで移動します。
      3.  `.\02_m4a_13_split.ps1` を実行します。
   *   **出力:**
      *   `out_1.3x.m4a` (1.3倍速にされた中間ファイル)
      *   `output_000.m4a`, `output_001.m4a`, ... (分割されたファイル群)
   *   **カスタマイズ:**
      *   スクリプト内の `$IntermediateFile` (中間ファイル名)、`$SegmentTimeSeconds` (分割時間)、`$OutputSegmentPattern` (出力ファイル名パターン) を必要に応じて変更できます。現在は4分(240秒)で分割する設定になっています。
      *   ffmpegのエンコーダオプション (`-c:a libfdk_aac -vbr 4`) は、環境や好みに応じて変更可能です。もし `libfdk_aac` が使えない場合は `-c:a aac` などに変更してください。

**3. `03_dify_mojiokosi2.ps1`**

   *   **目的:** `output_XXX.m4a` という名前の分割された音声ファイルを順番にDify APIに送信し、文字起こし結果を取得して1つのファイルにまとめます。
   *   **準備:**
      *   PowerShell 7 がインストールされていること。
      *   Difyで文字起こし用のワークフローが作成され、「公開」されていること。
      *   ワークフローの入力変数名が `input` (ファイル型)、出力変数名が `text` になっていること。
      *   スクリプト冒頭の `$DifyApiKey` を、DifyアプリのAPIキーに正しく設定すること。
      *   カレントディレクトリに、`02_m4a_13_split.ps1` で生成された `output_XXX.m4a` ファイル群が存在すること。
   *   **使い方:**
      1.  PowerShell 7 (`pwsh`) のコンソールを開きます。
      2.  このスクリプトのあるディレクトリに `cd` コマンドで移動します。
      3.  `.\03_dify_mojiokosi2.ps1` を実行します。
   *   **出力:**
      *   `dify_transcripts_workflow` フォルダ:
          *   `upload_response_XXX.json` (各ファイルのアップロードAPIのレスポンス)
          *   `workflow_payload_XXX.json` (各ファイルのワークフロー実行APIへのリクエストボディ)
          *   `workflow_response_XXX.json` (各ファイルのワークフロー実行APIのレスポンス)
      *   `dify_transcripts_workflow\all_transcriptions.txt` (全ての文字起こし結果をまとめたテキストファイル)
   *   **カスタマイズ:**
      *   スクリプト冒頭の `$DifyApiBaseUrl`, `$DifyApiKey`, `$UserIdentifier`, `$DifyWorkflowAudioInputVariable`, `$DifyWorkflowOutputVariable`, `$MaxRetriesWorkflow`, `$RetrySleepSecondsWorkflow`, `$FilePattern`, `$AudioFilesDirectory`, `$OutputDirectory` などの変数を必要に応じて変更できます。

**ワークフロー設定ファイル (`[本番]文字起こし20250510.yml`) について:**

このファイルは、Difyのワークフローの設定をエクスポートしたものです。重要なのは以下の部分です。

*   `mode: workflow`: このアプリがワークフローであることを示します。
*   `graph.nodes`: ワークフローのノード構成。
    *   **開始ノード (`type: start`):**
        *   `variable: input`: `input` という名前の変数が定義されています。
        *   `type: file`: この変数がファイル型であることを示します。
        *   `allowed_file_types: [audio]`: 音声ファイルのみを受け付ける設定です。
    *   **LLMノード (`type: llm`):**
        *   `model.name: gemini-2.0-flash-exp`: Geminiモデルを使用しています。
        *   `prompt_template`: 「ビジョンに格納された音声ファイルを文字起こししてください」という固定のプロンプトが設定されています。
        *   `vision.enabled: true`: ビジョン機能（ファイル処理）が有効になっています。
        *   `vision.configs.variable_selector: ['1746846958118', input]`: 開始ノードの `input` 変数（ファイル）をこのLLMノードの入力として使用する設定です。
    *   **終了ノード (`type: end`):**
        *   `outputs.variable: text`: `text` という名前の出力変数を定義しています。
        *   `outputs.value_selector: ['1746846961452', text]`: LLMノードの出力（変数名 `text` と推測される）を、このワークフロー全体の `text` 出力としています。

この設定ファイルから、PowerShellスクリプトで `$DifyWorkflowAudioInputVariable = "input"` と `$DifyWorkflowOutputVariable = "text"` としているのは正しいことが確認できます。


