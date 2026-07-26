# LifeSim 人生シミュレーション

テキスト主体の人生シミュレーションゲーム。生まれてから死ぬまで、各ライフステージでの選択が後々の出来事に影響する——できるだけリアルで自由度の高い人生追体験。

> **現在: 設計フェーズ（実装前）。** 設計を詰め切ってから実装に移る方針。

## このゲームの特徴（目標）

- **選択が効く**: 高校で部活を辞めた選択が、35歳の同窓会で固有のイベントを生む
- **高自由度**: 状態モデル＋条件付きイベントで、体験する組み合わせは指数的（著作コストは線形）
- **リアルな失敗**: 病気・事故・破産・離婚も本物の重みで。ただし文体には笑いと温かみ
- **シングル / マルチ両対応**: 一人でも、友達と「並走する人生」を交差させても遊べる
- **長さ選択可**: サクッと一生 / じっくり一生

## アーキテクチャ

Fallen London 由来の **Quality-Based Narrative**。プレイヤー（と主要NPC）は状態ドキュメントを持ち、イベントは宣言的条件で出現する。詳細は下記ドキュメント参照。

## ドキュメント

- [`dev-docs/LIFE_SIM_CONCEPT.md`](dev-docs/LIFE_SIM_CONCEPT.md) — **コンセプトシート（確定事項の正史）**。迷ったらここに戻る
- [`dev-docs/LIFE_SIM_DEV_PLAN.md`](dev-docs/LIFE_SIM_DEV_PLAN.md) — 開発プロセス工程表（STEP 0〜12）
- [`dev-docs/LIFE_SIM_ANALYSIS.md`](dev-docs/LIFE_SIM_ANALYSIS.md) — リファレンス分析（BitLife / Alter Ego / Fallen London / Princess Maker / Reigns）
- [`dev-docs/PROJECT_TODO.md`](dev-docs/PROJECT_TODO.md) — タスク台帳・恒久メモ・完了ログ
- [`CLAUDE.md`](CLAUDE.md) — プロジェクト指示・規約・確定事項のまとめ

## デモ

設計判断のための試作。ブラウザで直接開ける単体HTMLで、**画像・フォント・音声ファイルは一切使っていない**（見た目はCSS/SVG、音はWeb Audio合成）。

- [`demos/scene-proto.html`](demos/scene-proto.html) — イベントシーンの一枚絵。3場面を同じ9部品から組んだもの
- [`demos/portrait-proto.html`](demos/portrait-proto.html) — NPCのシルエット肖像。関係値と加齢が見た目に出る
- [`demos/hairstyle-kit.html`](demos/hairstyle-kit.html) — 髪型12種・髪飾り6種と、どこまで描き込むかの4段階比較

一覧と論点は [`demos/README.md`](demos/README.md)。

## 由来

SmartQ（リアルタイム・マルチプレイヤークイズ基盤）内のアイデアとして発案、規模とジャンルの違いから独立プロジェクト化。
