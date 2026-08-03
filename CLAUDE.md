# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## リポジトリ概要

CPAN モジュール `WebService::Mailgun` — Mailgun API (https://mailgun.com/) の Perl クライアント。
実装はほぼ `lib/WebService/Mailgun.pm` の 1 ファイル (約 330 行 + POD)。ビルド/リリースは Minilla 管理。

## 開発コマンド

ローカルに Perl 環境を作らず `docker-compose.yml` の perl-cpm イメージを使う想定:

```sh
docker compose run --rm perl cpm install          # cpanfile から依存を local/ に導入
docker compose run --rm perl prove -lr t          # 全テスト
docker compose run --rm perl prove -lv t/01_message.t   # 単体テスト (verbose)
```

ローカルに依存が入っている場合は `prove -lr t` / `prove -lv t/04_mime.t` を直接実行してよい。

Minilla 経由:

```sh
minil test      # xt/ の author test 込み (Test::Pod, Test::Spellunker 等)
minil build     # 配布物生成 (README.md / META.json / Build.PL を再生成)
minil release   # バージョン確定 + Changes 更新 + CPAN upload + git tag
```

### テストは実 API を叩く / 認証情報は環境変数

`t/01_message.t` `t/02_list_and_event.t` `t/04_mime.t` は Mailgun へ実際に HTTPS リクエストを送る。
認証情報は環境変数から取得し、未設定なら `plan skip_all` でスキップする:

| 環境変数 | 用途 | 必要なテスト |
| --- | --- | --- |
| `MAILGUN_API_KEY` | API キー | 01 / 02 / 04 |
| `MAILGUN_DOMAIN` | 送信ドメイン (sandbox 可) | 01 / 02 / 04 |
| `MAILGUN_TO` | 宛先アドレス (sandbox なら authorized recipient) | 01 / 04 |

```sh
docker compose run --rm \
  -e MAILGUN_API_KEY=... -e MAILGUN_DOMAIN=... -e MAILGUN_TO=... \
  perl prove -lr t
```

**テストにキーや個人のメールアドレスをハードコードしないこと** (以前ハードコードされていた
キーは失効済み)。ネットワーク非依存なのは `t/00_compile.t` と、パッケージ変数
`$WebService::Mailgun::API_BASE` を存在しないホストへ差し替えてエラー経路だけを見る
`t/03_error.t` (ダミーの認証情報で動く)。実 API を叩くテストの失敗は、キー失効や
ネットワーク不通が原因のこともあるので即コードのバグと判断しないこと。

### CI

`.github/workflows/test.yml` で perl 5.30〜5.38 のマトリクス実行 (`shogo82148/actions-setup-perl`)。
上記 3 つの環境変数は GitHub Secrets (`MAILGUN_API_KEY` / `MAILGUN_DOMAIN` / `MAILGUN_TO`) から渡す。
fork からの PR では secret が渡らないため実 API テストは自動的にスキップされる。
Travis CI と coveralls は廃止済み。

## リリース手順 (docker コンテナで実行する場合)

ローカルに Minilla は入っていない。コンテナ内で完結させるための前提と手順は以下 (0.17 リリースで検証済み)。

```sh
docker compose run --rm perl cpm install --with-develop   # Minilla 等の develop 依存を local/ へ
```

### コンテナで git を動かすための制約

- コンテナの git は **2.20** で、ホストの `~/.gitconfig` にある `gpg.format = ssh` (git 2.34 以降) を
  解釈できず全 git コマンドが fatal で止まる。最小限の `user.name` / `user.email` だけを書いた
  専用 HOME を用意してマウントする
- ホストの uid は コンテナの `/etc/passwd` に存在せず、ssh が `No user exists for uid 1000` で失敗する。
  `/etc/passwd` を ro マウントすれば解決する
- root で実行すると `.git` や生成物が root 所有になり、以後ホスト側の git 操作が壊れる。
  必ず `--user "$(id -u):$(id -g)"` を付ける

```sh
mkdir -p ~/.minilla-docker/.ssh && chmod 700 ~/.minilla-docker/.ssh
printf '[user]\n\tname = <NAME>\n\temail = <EMAIL>\n' > ~/.minilla-docker/.gitconfig
ssh-keyscan -t ed25519,rsa github.com > ~/.minilla-docker/.ssh/known_hosts 2>/dev/null

docker compose run --rm --user "$(id -u):$(id -g)" \
  -e HOME=/home/<USER> -e PATH=/app/local/bin:/usr/local/bin:/usr/bin:/bin \
  -v "$HOME/.minilla-docker:/home/<USER>" -v /etc/passwd:/etc/passwd:ro \
  perl <command>
```

### 分割リリース (コミットをホスト側で行う場合)

`minil release` は `BumpVersion → CheckChanges → RegenerateFiles → DistTest → MakeDist →
UploadToCPAN → RewriteChanges → Commit → Tag` の固定ステップで、**コミットだけ飛ばすオプションはない**
(あるのは `--no-test` / `--trial` / `--dry-run` / `--pause-config`)。ホストの署名設定でコミットしたい場合は
bump と Changes を手で確定させ、`minil dist` + `cpan-upload` に分割する。

1. `lib/WebService/Mailgun.pm` の `$VERSION` を上げる
2. `Changes` の `{{$NEXT}}` の直後に空行 + `<version> <YYYY-MM-DDThh:mm:ssZ>` の見出しを挿入する
   (`{{$NEXT}}` 自体は残す。Minilla の RewriteChanges と同じ形)
3. コンテナで `minil dist` — `README.md` / `META.json` / `Build.PL` を再生成し、`xt/` 込みの
   dist テストを実行して tarball を作る
4. コンテナで `cpan-upload -u <PAUSE_ID> /app/<dist>.tar.gz` (パスワードは対話入力。
   `minil release` を使う場合は `~/.pause` かリポジトリ直下の `.pause` が必須で、無いと die する)
5. ホストで `git commit -m "release version <version>"` → `git tag <version>` →
   `git push origin master` → `git push origin tag <version>`。タグ名はバージョン番号そのまま

## アーキテクチャ

### URL 組み立ての 2 系統

- `api_url($method)` — アカウント単位のエンドポイント (`lists/*`)
- `domain_api_url($method)` — ドメイン単位のエンドポイント (`messages`, `messages.mime`, `events`, `templates/*`)

どちらも `https://api:<api_key>@<base>/...` の形で **URL の userinfo に API キーを埋め込む** Basic 認証。
ベースホストは `api_base()` が `region` 属性 (`us` / `eu`、未指定は us) で `$API_BASE` / `$API_BASE_EU` を
切り替える。未知の region は `die`。両者はパッケージ変数なのでテストから差し替え可能。

### エラー処理は `decode_response` に一本化

全 API メソッドは最後に `$self->decode_response($res)` を呼ぶ。成功なら decode 済み JSON、
失敗なら `error` / `error_status` を埋めたうえで、`RaiseError` が真なら `carp`+`croak`、
偽なら `return;` (undef)。したがって呼び出し側は `my $json = $self->decode_response($res) or return;`
のように undef を通す形で書く。新しい API メソッドを足すときもこの規約に従うこと。

### ページング (`recursive`)

Mailgun の `*/pages` 系と events は `paging.next` を辿る。`recursive` は items が空になるまで
next を辿って全件を集め、`(\@items, $previous_uri)` の **2 要素リスト** を返す。
返り値が 2 つなので呼び出し側は `my ($lists, undef) = $mailgun->lists();` と受ける必要がある
(POD の例は 1 つで受けている箇所があり実態と食い違う)。

Mailgun が返す paging URL には認証情報が含まれないため、`$uri->userinfo('api:'.$self->api_key)` を
毎回付け直している。`previous` URL は Event Polling 用にそのまま `event()` へ渡せる
(`event($purl)` は URI をそのまま使う経路)。

### multipart/form-data 送信

`message()` / `mime()` / `add_template()` は Furl のショートカットではなく
`HTTP::Request::Common::POST` + `Content_type => 'form-data'` で組み立て `$self->client->request($req)` する。
`message()` と `add_template()` が HashRef と ArrayRef の両方を受けるのは、
**添付ファイルなど同一キーを複数回渡す必要がある場合に順序付きの ArrayRef が要る** ため
(`attachment => [ 'path' ]` の形式)。それ以外の ref は `die`。

`mime()` は `message` に文字列 (または文字列 ref) を渡された場合 `File::Temp` に書き出して
`[$filename]` としてフォームに載せる。`file` 指定なら存在確認のうえそのまま使う。
一時ファイルはリクエスト送信後に `undef $tmp` で破棄している。

### オブジェクト生成

`Class::Accessor::Lite` の `new => 1` を使っており、コンストラクタは自動生成 (hashref をそのまま bless)。
`api_key` / `domain` / `RaiseError` / `region` が rw、`error` / `error_status` が ro。
Furl クライアントは `client()` で遅延生成し `_client` にキャッシュ。

## 変更時の注意

- **README.md は POD から自動生成** される (`Pod::Markdown::Github`、`minil build` 時)。
  ドキュメント修正は `lib/WebService/Mailgun.pm` の POD 側を直すこと。README を直接編集しない。
- `Build.PL` / `META.json` も Minilla 生成物。手で編集しない。
- 依存追加は `cpanfile` に書く (`META.json` ではなく)。
- バージョンは `lib/WebService/Mailgun.pm` の `our $VERSION`、履歴は `Changes` の `{{$NEXT}}` 直下に追記。
  リリース手順は上記「リリース手順」を参照。
- 最低 Perl バージョンはモジュール内 `use 5.008001` に対し cpanfile は `perl 5.010000` 要求という
  食い違いがある。`Test::MinimumVersion::Fast` (author test) が絡むので触るときは両方を見ること。
- 未実装 API (Domains / Stats / Tags / Suppressions / Routes / Webhooks / Email Validation、
  Templates は部分実装) は POD の TODO セクションに列挙されている。実装したら POD の TODO も更新する。
