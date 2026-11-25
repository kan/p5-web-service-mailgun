# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## リポジトリ概要

CPAN モジュール `WebService::Mailgun` — Mailgun API (https://mailgun.com/) の Perl クライアント。
実装はほぼ `lib/WebService/Mailgun.pm` の 1 ファイル (約 330 行 + POD)。ビルドは Minilla、
リリースは tagpr (下の「リリース」)。

## 開発コマンド

ローカルに Perl 環境を作らず、`docker-compose.yml` のコンテナを使う想定。イメージは repo の
`Dockerfile` (公式の `perl:5.44` に cpm を足したもの) からビルドされる。主なコマンドは次のとおり。

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
- 依存は名前付きボリューム `perl-local-5.44` に入る。Perl の版を上げるときは、`Dockerfile` と一緒に
  ボリューム名も変える (別の版でビルドした XS モジュールは読み込めない)。前のボリュームは
  `docker volume rm p5-web-service-mailgun_<前の名前>` で消す (perl-cpm のころのものは
  `p5-web-service-mailgun_perl-local`)
- **Perl の版は、`Dockerfile` の `FROM`、`test.yml` の `perl:<版>` のイメージ (`test` と `dist`)、
  `publish.yml` の `with:` の `perl-version`、`docker-compose.yml` のボリューム名で揃える。** Dependabot
  (`dependabot.yml` の `docker`) が PR で上げるのは `Dockerfile` だけなので、その PR を取り込むときは
  残りも同じ PR で手で上げる。CI が古い版のまま通っても、新しい版を試したことにはならない
- 依存の版は固定しない (`cpanfile.snapshot` を置かない)。CI も CPAN の利用者も、その時点の最新を入れる

ローカルに依存が入っている場合は `prove -lr t` / `prove -lv t/04_mime.t` を直接実行してよい。

### 生成物の作り直し (`minil build`)

`minil build` は POD から `README.md` を、`cpanfile` と `minil.toml` から `META.json` / `Build.PL` を作り直す。

- **POD、`cpanfile`、`minil.toml` を変えたら、同じ PR で `minil build` を実行し、作り直された
  `README.md` / `META.json` も一緒にコミットする。** リリース PR は `META.json` の版しか変えない。
  ここで作り直さないと、repo の `README.md` が古いまま残る。配布物の中のものは、`publish.yml` が
  呼ぶ共通の workflow (`publish-cpan.yml`) の `minil dist` が作り直す
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
`t/03_error.t` (ダミーの認証情報で動く)、HTTP クライアント (`$mailgun->{_client}`) を差し替えて
組み立てた URL やリクエストを見たり、応答を与えたりする `t/05_event_url.t` 以降。URL やリクエストの
組み立て、応答の扱いを確かめるテストは、この差し替えで書く。
実 API を叩くテストの失敗は、キー失効や
ネットワーク不通が原因のこともあるので即コードのバグと判断しないこと。

### CI

| workflow | 起動 | 内容 |
| --- | --- | --- |
| `test.yml` | `master` への push、PR | perl 5.44 のテスト (`test`、Docker Hub の `perl:5.44` のコンテナ、実 API を叩くのはこのジョブだけ)、宣言の最低版 5.20 のテスト (`oldest-perl`、actions-setup-perl、secret を渡さない)、`minil dist` の tarball に `scripts/` が入らないかの確認 (`dist`)、`scripts/tagpr/` と呼ぶ SHA の一致の確認 (`tagpr-subtree`) |
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
`publish.yml` は kan/tagpr-scripts の共通の workflow `publish-cpan.yml` を呼ぶだけ。ジョブの中身と
落ちたときの扱いは `scripts/tagpr/README.md` の「The CPAN publish workflow」にある。ジョブは
`publish / Build and check`、`publish / Upload to PAUSE`、`publish / Create the GitHub release` の 3 つ。
`uses:` の SHA は `tagpr.yml` / `tagpr-label.yml` と同じく、subtree を取り込む PR で上げる。

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
4. マージすると tagpr がタグを打ち、`publish.yml` が起動する。`Build and check` がテストして
   tarball を作り、`Upload to PAUSE` が PAUSE へアップロードし、`Create the GitHub release` が
   GitHub Release を作る
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
  取り込む。同じ PR で `tagpr.yml`、`tagpr-label.yml`、`publish.yml` の `uses: kan/tagpr-scripts/...@<SHA>` を、
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

### URL 組み立て

- `api_url($method)` — アカウント単位のエンドポイント (`lists/*`)
- `domain_api_url($method)` — ドメイン単位のエンドポイント (`messages`, `messages.mime`, `events`、
  templates のうち `add_template` / `delete_template(s)`)
- `api_url(_path($self->domain, ...))` / `api_url(_path('domains', $self->domain, ...))` — ドメイン単位のうち、
  suppressions と templates の残り (`_domain_url` / `recursive` に渡すパスは `_domain_path`)、webhooks
  (`_domain_webhook_url`)。domain も
  `_path` に通すので、domain が未設定なら送らずに `croak` する。`domain_api_url` は domain を検査しない
  (既存のメソッドの振る舞いを変えないため、そのままにしてある)。新しいドメイン単位のメソッドはこちらの形で書く

どれも `https://api:<api_key>@<base>/...` の形で **URL の userinfo に API キーを埋め込む** Basic 認証。
ベースホストは `api_base()` が `region` 属性 (`us` / `eu` / `au`、未指定は us) で `$API_BASE` /
`$API_BASE_EU` / `$API_BASE_AU` を切り替える。未知の region は `die`。どれもパッケージ変数なので
テストから差し替え可能。

### エラー処理は `decode_response` に一本化

全 API メソッドは最後に `$self->decode_response($res)` を呼ぶ。成功なら decode 済み JSON、
失敗なら `error` / `error_status` / `error_response` (応答そのもの。429 のヘッダーを読むため、#43) を
埋めたうえで、`RaiseError` が真なら `carp`+`croak`、偽なら `return;` (undef)。したがって呼び出し側は
`my $json = $self->decode_response($res) or return;` のように undef を通す形で書く。新しい API メソッドを
足すときもこの規約に従うこと。応答の形が想定と違うときなど、`decode_response` の外で失敗にするときは
`$self->_fail($message, $res)` を呼ぶ (3 つの属性と `RaiseError` の扱いがそろう)。

### ページング (`recursive`)

Mailgun の `*/pages` 系と events は `paging.next` を辿る。`recursive` は items が空になるまで
next を辿って全件を集め、`(\@items, $next_uri)` の **2 要素リスト** を返す。`$next_uri` は
空のページの `paging.next`。途中で失敗したときは、失敗したページの URL (渡し直せば続きから取れる。
`undef` にすると、`event(undef)` が条件なしで全件を取り直してしまう)。`paging.next` の無いページで
止まったときも、同じ理由で `undef` ではなくそのページの URL を返す。items の無いページと、辿った URL へ
戻る `paging.next` は失敗として扱う (#35)。templates の 2 つの一覧だけは、`{ null_items => 1 }` を渡して、
items のキーがあって値が `null` のページを空のページとして扱う (文書の型が「array か null」のため)。
items の場所は、キーの代わりにキーの配列で渡せる (`template_versions()` の `['template', 'versions']`)。
`lists()` / `list_members()` のクエリのうち `paging.next` に
無いキーは、次のページの URL に足し直す (#41。`subscribed` が落ちると 2 ページ目から絞り込みが外れる)。
返り値が 2 つなので呼び出し側はリストで受ける
(`my ($lists) = $mailgun->lists();`)。スカラーで受けると `$next_uri` が入る。POD の
「Lists of every page」に利用者向けの説明がある。途中のページで失敗しても `undef` は返さず、
それまでに集めた分を返す (POD の「Errors」)。

Mailgun が返す paging URL には認証情報が含まれないため、`$uri->userinfo('api:'.$self->api_key)` を
毎回付け直している。**返す `$next_uri` には API キーを付けない** (#38)。利用者は Event Polling のために
保存したりログに出したりするので。`$next_uri` は Event Polling 用にそのまま `event()` へ渡せる
(`event($url)` は URI か文字列をそのまま要求する経路。API キーを付けるので、https で `api_base()` の
ホストの URL 以外は `croak` する)。

- **2 つ目の戻り値を `paging.previous` に戻さない。** 空のページの `previous` は最後のページへ遡る
  URL で、渡すと毎回最大 `limit` 件を取り直す。空のページの `next` なら、その後に保存された
  イベントだけが返る (実 API で確かめた結果は #25)

### multipart/form-data 送信

`message()` / `mime()` / `add_template()` は Furl のショートカットではなく
`HTTP::Request::Common::POST` + `Content_type => 'form-data'` で組み立て `$self->client->request($req)` する。
`message()` と `add_template()` が HashRef と ArrayRef の両方を受けるのは、
**添付ファイルなど同一キーを複数回渡す必要がある場合に順序付きの ArrayRef が要る** ため
(`attachment => [ 'path' ]` の形式)。それ以外の ref は `die`。

`message()` と `mime()` は `_form_content` でフォームの中身を組み立てる。値の配列 ref は同じキーの
繰り返しに展開する (`to => [...]`、#36)。ファイルのキー (`message()` は `attachment` / `inline`、
`mime()` は `message`) の配列 ref だけは、HTTP::Request::Common のファイルの指定として残す。
`add_template()` は展開しない (配列 ref はファイル)。templates の版の追加と更新 (`add_template_version()` /
`update_template_version()`) と `update_template()` も、`add_template()` と同じ `_send_form` で送る
(更新は `HTTP::Request::Common::PUT`)。JSON の body は `_send_json` で送る。

`mime()` は渡された hash をコピーしてから組み立て、渡された hash を書き換えない (#39)。`message` の
文字列 (または文字列 ref) は、一時ファイルに書かず、メモリ上の内容としてフォームに載せる
(`[undef, 'message.mime', Content => $mime]`)。`file` 指定なら存在確認のうえそのまま使う。

### オブジェクト生成

`Class::Accessor::Lite` の `new => 1` を使っており、コンストラクタは自動生成 (hashref をそのまま bless)。
`api_key` / `domain` / `RaiseError` / `region` / `timeout` が rw、`error` / `error_status` が ro。
Furl クライアントは `client()` で遅延生成し `_client` にキャッシュ。`timeout` は生成のときに Furl へ
渡すので、最初のリクエストの後に変えても効かない (POD にもそう書いてある)。

## 変更時の注意

- **README.md は POD から自動生成** される (`Pod::Markdown::Github`)。
  ドキュメント修正は `lib/WebService/Mailgun.pm` の POD 側を直すこと。README を直接編集しない。
  作り直し方は上記「生成物の作り直し」。
- `Build.PL` / `META.json` も Minilla 生成物。手で編集しない。
- 依存追加は `cpanfile` に書く (`META.json` ではなく)。
- 版と履歴 (`CHANGELOG.md`) の扱いは上記「リリース」を参照。
- **最低の Perl は 5.20** (kan/coveralls-perl と同じ)。モジュールの `use 5.020`、cpanfile の
  `requires 'perl', '5.020000'`、`test.yml` の `oldest-perl` の版は一緒に変え、`minil build` で
  `META.json` も作り直す。5.22 以降の構文や機能 (`<<>>`、`<<~` のヒアドキュメント、`isa` 演算子など) は
  使わない。5.20 で experimental の postfix deref (`$ref->@*`) とサブルーチンのシグネチャも使わない。
  `//`、`say`、`state`、`s///r` は使ってよい
- 実 API を叩くテストは、`test.yml` の `test` ジョブ 1 つでだけ走らせる。メールの送信が sandbox の
  送信上限を使うため。版を足すときも secret を渡すジョブは増やさない。間の版は、リリース後の
  CPAN Testers で確かめられる
- **5.44 のジョブは Docker Hub の `perl:5.44` のコンテナで動かす。** actions-setup-perl は Perl を
  GitHub Releases から認証なしでダウンロードするので、GitHub が匿名のアクセスを絞ると 504 で落ちる
  (2026-11-09 の GitHub の障害)。actions-setup-perl のままなのは次の 2 つ。
  - `oldest-perl`: 今の runner で使える `perl` のイメージは 5.26 以降だけ (5.20 は schema 1 で
    pull できず、5.22 / 5.24 は glibc が古く actions/checkout の Node 24 が動かない)
  - `publish.yml` が呼ぶ共通の workflow の `Build and check`: 共通の workflow がコンテナを使わない
    (検査に Node も要る)。この actions-setup-perl の版は、この repo の `actions.lock` ではなく
    kan/tagpr-scripts の側で固定される
  - どちらも 504 で落ちたら `gh run rerun <run-id> --failed` で再実行する。publish の
    `Build and check` は PAUSE へ送る前に落ちるので、再実行してよい
- 未実装 API (Domains / Logs / Metrics / Tags (新) / Routes / Webhooks の v4 と account 単位 /
  Email Validation、account 単位の Templates) は POD の TODO セクションに列挙されている。実装したら POD の TODO も更新する。
