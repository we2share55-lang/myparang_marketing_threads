#!/usr/bin/env node
// cardnews-copy.json에서 Threads 캡션 초안을 만든다 (Threads 본문 500자 제한).
// 결과는 stdout으로 출력 — 파일로 저장 후 반드시 사람이 검토/수정할 것.
//
// Usage: node scripts/make-caption.js <cardnews-dir> > caption.txt

import { readFileSync } from "node:fs";
import { join } from "node:path";

const dir = process.argv[2];
if (!dir) {
  console.error("Usage: node scripts/make-caption.js <cardnews-dir>");
  process.exit(1);
}

const copyPath = join(dir, "cardnews-copy.json");
const copy = JSON.parse(readFileSync(copyPath, "utf-8"));

const cover = copy.cards.find((c) => c.art_tag === "COVER") ?? copy.cards[0];
const cta = copy.cards.find((c) => c.art_tag === "CTA") ?? copy.cards[copy.cards.length - 1];

const lines = [
  cover.headline,
  "",
  cover.caption,
  "",
  cta.headline,
  cta.caption,
  "",
  `#${copy.keyword.replace(/\s+/g, "")} #마이파랑 #네이버쇼핑`,
];

let text = lines.join("\n").trim();
const LIMIT = 500;
if (text.length > LIMIT) {
  text = text.slice(0, LIMIT - 1).trimEnd() + "…";
}

process.stdout.write(text + "\n");
