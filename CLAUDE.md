# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## リポジトリ概要

CPAN モジュール `WebService::Mailgun` — Mailgun API (https://mailgun.com/) の Perl クライアント。
実装はほぼ `lib/WebService/Mailgun.pm` の 1 ファイル (約 330 行 + POD)。ビルドは Minilla、
リリースは tagpr (下の「リリース」)。

## 開発コマンド

ローカルに Perl 環境を作らず、`docker-compose.yml` のコンテナを使う想定。イメージは repo の
`Dockerfile` (公式の `perl:5.42` に cpm を足したもの) からビルドされる。主なコマンドは次のとおり。

```sh
docker compose run --rm perl cpm install --with-develop   # cpanfile から依存を local/ に導入
docker compose run --rm perl prove -lr t                  # 全テスト
docker compose run --rm perl prove -lv t/01_message.t     # 単体テスト (verbose)
docker compose run --rm perl minil build                  # 生成物の作り直し (下)
```

- コンテナはホストのユーザー (既定は uid / gid 1000) で動くので、書き出したファイルは root 所有に
  ならない。ホストの uid が 1000 でなければ、repo 直下の `.env` (`.gitignore` 済み、compose が自動で
  読む) に `HOST_UID=<uid>` と `HOST_GID=<gid>` を書き、`docker compose build` からやり直す。
  ボリュームの所有者は作ったときの uid のまま変わらないので、作った後なら
  `docker compose down -v` で消してから入れ直す
- 依存は名前付きボリューム `perl-local-5.42` に入る。Perl の版を上げるときは、`Dockerfile` と一緒に
  ボリューム名も変える (別の版でビルドした XS モジュールは読み込めない)。前のボリュームは
  `docker volume rm p5-web-service-mailgun_<前の名前>` で消す (perl-cpm のころのものは
  `p5-web-service-mailgun_perl-local`)
- 依存の版は固定しない (`cpanfile.snapshot` を置かない)。CI も CPAN の利用者も、その時点の最新を入れる

ローカルに依存が入っている場合は `prove -lr t` / `prove -lv t/04_mime.t` を直接実行してよい。

### 生成物の作り直し (`minil build`)

`minil build` は POD から `README.md` を、`cpanfile` と `minil.toml` から `META.json` / `Build.PL` を作り直す。

- **POD、`cpanfile`、`minil.toml` を変えたら、同じ PR で `minil build` を実行し、作り直された
  `README.md` / `META.json` も一緒にコミットする。** リリース PR は `META.json` の版しか変えない。
  ここで作り直さないと、repo の `README.md` が古いまま残る。配布物の中のものは、`publish.yml` の
  `minil dist` が作り直す
- `minil release` は使わない (版を上げてタグを打つのは tagpr の役目)

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

| workflow | 起動 | 内容 |
| --- | --- | --- |
| `test.yml` | `master` への push、PR | perl 5.30〜5.38 のテスト (`test`)、`minil dist` の tarball に `scripts/` が入らないかの確認 (`dist`)、`scripts/tagpr/` と呼ぶ SHA の一致の確認 (`tagpr-subtree`) |
| `verify-lockfile.yml` | `master` への push、PR | `actions.lock` の検証 |
| `tagpr.yml` / `tagpr-label.yml` / `publish.yml` | リリース | 下の「リリース」 |

- テストの 3 つの環境変数は GitHub Secrets (`MAILGUN_API_KEY` / `MAILGUN_DOMAIN` / `MAILGUN_TO`) から
  渡す。fork からの PR では secret が渡らないため実 API テストは自動的にスキップされる
- action の版は `.github/workflows/actions.lock` で固定している。**`uses:` の行を変えたら、repo の
  ルートで `gh actions-lock` を実行し、書き換わった workflow と lockfile を一緒にコミットする。**
  lockfile を手で編集しない。Dependabot の更新 PR は lockfile も書き換える
- Travis CI と coveralls は廃止済み

## 運用

- **`master` へ直接 push しない。** ブランチを切って PR で入れる。tagpr はマージされた PR から
  リリース PR を組み立てるため、直接 push した変更はリリースの流れから漏れる
- tagpr のリリース PR では CI が走らない (`GITHUB_TOKEN` で作られた PR は workflow を起動しない)。
  リリース PR の版と CHANGELOG は、tagpr の run の中で `release-prepare.mjs` が確かめる

## リリース

リリースは tagpr で行う。`master` への push ごとに `tagpr.yml` がリリース PR を作り直し、
それをマージするとタグ (`vX.Y.Z`) が打たれ、`publish.yml` が CPAN (PAUSE) へアップロードして
GitHub Release を作る。仕組みと落ちたときの扱いは `scripts/tagpr/README.md` の「The tagpr workflow」。

1. 変更は PR で入れる。**利用者に見える変更の PR は、`CHANGELOG.md` の `## [Unreleased]` の下に
   1 行を足す。** その節がそのままリリースノートになる。外部の貢献者の変更には既存の行にならって
   `(thanks <名前>)` を付ける。リンクは行の中に書く (参照リンクの定義は節の外にあり、
   リリースノートではリンクにならない)。見出しや末尾のリンクの形は `scripts/tagpr/README.md` の
   「What the CHANGELOG has to look like」
2. `master` へマージされるたびに、リリース PR (ブランチ `tagpr-from-v<前の版>`) が作り直される。
   リリース PR は `Mailgun.pm` の `$VERSION` と `META.json` の版を上げ、`## [Unreleased]` を
   その版の節に変える
3. 出したくなったら、リリース PR の中身 (版と CHANGELOG の節) を確かめてマージする
   - **tagpr の run が赤いリリース PR はマージしない** (落ちた run がリリース PR を draft にする)
   - 版の上がり方はラベルで決まる。`enhancement` の PR が入っていれば minor、それ以外は patch。
     変えたいときはリリース PR に `tagpr:minor` / `tagpr:major` を付ける。`tagpr-label.yml` が
     リリース PR を draft にして作り直し、ready に戻す。ready に戻るのを待ってからマージする
4. マージすると tagpr がタグを打ち、`publish.yml` がテストして tarball を作り、PAUSE へ
   アップロードしてから GitHub Release を作る
5. PAUSE から届く索引のメールを確かめる

**PAUSE へのアップロードは取り消せない。** 同じファイル名は二度と受け付けられないので、壊れた版を
出したら版を上げて出し直す。

- **版を手で変えない。** 版は `Mailgun.pm` の `our $VERSION` と `META.json` にあり、どちらも
  リリース PR で tagpr が上げる (`.tagpr` の `versionFile`)
- **版は 3 つ組 (`1.0.1`、`1.1.0`) にする。** 0.x の 3 つ組は数値にすると 0.17 より小さくなり
  (0.18.0 は 0.018000)、PAUSE の索引に載らない。tagpr での最初のリリースを 1.0.0 にし (#16、
  最初のリリース PR に `tagpr:major`)、以後は 3 つ組のまま上げる
- **`scripts/tagpr/` を手で編集しない。** 変えるときは kan/tagpr-scripts を直し、
  `git subtree pull -S --prefix=scripts/tagpr https://github.com/kan/tagpr-scripts.git main --squash` で
  取り込む。同じ PR で `tagpr.yml` と `tagpr-label.yml` の `uses: kan/tagpr-scripts/...@<SHA>` を、
  squash のコミットの `git-subtree-split` の SHA へ上げる。食い違いは `test.yml` の `tagpr-subtree`
  ジョブが落とす。**この PR はマージコミットでマージする** (squash すると次の subtree pull が壊れる)
- PAUSE の認証情報は GitHub の `cpan` environment の secret (`PAUSE_USER` / `PAUSE_PASSWORD`) にある。
  PAUSE ID は `MIKIHOSHI`。repo のルートに `.pause` があってもコミットしない (`.gitignore` 済み)
- `0.17` 以前のタグは Minilla が打った `v` 無しの 2 つ組。tagpr は `vX.Y.Z` しか見ないので、
  0.17 のコミット (fc9825d) に起点として `v0.17.0` を annotated で打ってある
- **`Mailgun.pm` と `META.json` の版は、移行の PR で `0.17` から `0.17.0` に揃えてある。** tagpr は
  前のタグの版の文字列 (`0.17.0`) を `versionFile` から探して置き換えるので、`0.17` のままだと
  何も書き換わらない。`0.17.0` は数値にすると 0.017000 で 0.17 より小さいが、CPAN へは出さない
  (最初のリリース PR で 1.0.0 にする)

### 最初に一度だけ要る設定

- 起点のタグ `v0.17.0` を push する (`.tagpr` を `master` へ入れるより前)。無いと tagpr は前の版を
  0.0.0 と見て、版のファイルを書き換えられない
- Settings → Actions → General の「Allow GitHub Actions to create and approve pull requests」を
  有効にする (無いと最初の tagpr の run が 403 で落ちる)
- Settings → Environments に `cpan` を作り、secret `PAUSE_USER` (`MIKIHOSHI`) と `PAUSE_PASSWORD` を置く
- ラベル `tagpr:major` を作る (最初のリリース PR に付ける)

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

- **README.md は POD から自動生成** される (`Pod::Markdown::Github`)。
  ドキュメント修正は `lib/WebService/Mailgun.pm` の POD 側を直すこと。README を直接編集しない。
  作り直し方は上記「生成物の作り直し」。
- `Build.PL` / `META.json` も Minilla 生成物。手で編集しない。
- 依存追加は `cpanfile` に書く (`META.json` ではなく)。
- 版と履歴 (`CHANGELOG.md`) の扱いは上記「リリース」を参照。
- 最低 Perl バージョンはモジュール内 `use 5.008001` に対し cpanfile は `perl 5.010000` 要求という
  食い違いがある。`Test::MinimumVersion::Fast` (author test) が絡むので触るときは両方を見ること。
- 未実装 API (Domains / Stats / Tags / Suppressions / Routes / Webhooks / Email Validation、
  Templates は部分実装) は POD の TODO セクションに列挙されている。実装したら POD の TODO も更新する。
