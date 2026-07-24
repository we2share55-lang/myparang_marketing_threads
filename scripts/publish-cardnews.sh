#!/usr/bin/env bash
# 카드뉴스 이미지 폴더 -> Threads 캐러셀 게시물로 발행한다.
#
# Usage:
#   scripts/publish-cardnews.sh <cardnews-dir> --caption-file <path> [--publish]
#
# <cardnews-dir> 예: /c/claude/myparang_marketing_instagram/output/2026-07-22_cardnews_쇼핑검색광고
#   (그 안의 images/*.png 를 사용. cardnews-copy.json 은 필수 아님)
#
# --publish 없이 실행하면:
#   이미지를 이 저장소(assets/cardnews/<폴더명>/)로 복사 -> 커밋/푸시 -> Threads에
#   캐러셀 아이템 컨테이너 + 캐러셀 컨테이너까지만 생성하고 멈춘다. 실제 게시(publish) 안 함.
# --publish 를 주면 컨테이너 처리 대기 -> threads_publish 까지 진행해 실제로 게시된다.
#
# 이 스크립트를 호출하는 쪽은 --publish를 붙이기 전에 반드시 사람에게
# 캡션과 이미지 순서를 보여주고 명시적 확인을 받아야 한다.
#
# 필요한 .env 값 (이 저장소 루트, 스크립트가 상위로 올라가며 자동 탐색):
#   THREADS_ACCESS_TOKEN, THREADS_USER_ID
#   GITHUB_OWNER, GITHUB_REPO, GITHUB_BRANCH (이미지 공개 URL 조립용)

set -euo pipefail

CARDNEWS_DIR="${1:?cardnews-dir 필요}"
shift

CAPTION_FILE=""
PUBLISH=0

while [ $# -gt 0 ]; do
  case "$1" in
    --caption-file) CAPTION_FILE="$2"; shift 2 ;;
    --publish) PUBLISH=1; shift ;;
    *) echo "알 수 없는 옵션: $1" >&2; exit 2 ;;
  esac
done

# cd 하기 전에 상대경로 인자들을 절대경로로 고정
CARDNEWS_DIR="$(cd "$CARDNEWS_DIR" && pwd)"
if [ -n "$CAPTION_FILE" ]; then
  CAPTION_FILE="$(cd "$(dirname "$CAPTION_FILE")" && pwd)/$(basename "$CAPTION_FILE")"
fi

IMAGES_DIR="$CARDNEWS_DIR/images"
if [ ! -d "$IMAGES_DIR" ]; then
  echo "images 폴더를 찾을 수 없음: $IMAGES_DIR" >&2
  exit 1
fi
if [ -z "$CAPTION_FILE" ] || [ ! -f "$CAPTION_FILE" ]; then
  echo "--caption-file 필요 (UTF-8 텍스트 파일 경로, 500자 이내) — 예: node scripts/make-caption.js <cardnews-dir> > caption.txt" >&2
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

ENV_FILE="$REPO_ROOT/.env"
if [ ! -f "$ENV_FILE" ]; then
  echo "루트 .env를 찾을 수 없음 (THREADS_ACCESS_TOKEN 등 필요) — .env.example 참고" >&2
  exit 1
fi
set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a

: "${THREADS_ACCESS_TOKEN:?THREADS_ACCESS_TOKEN 필요}"
: "${THREADS_USER_ID:?THREADS_USER_ID 필요}"
GITHUB_OWNER="${GITHUB_OWNER:-we2share55-lang}"
GITHUB_REPO="${GITHUB_REPO:-myparang_marketing_threads}"
GITHUB_BRANCH="${GITHUB_BRANCH:-master}"

CARDNEWS_NAME="$(basename "$CARDNEWS_DIR")"
DEST_DIR="$REPO_ROOT/assets/cardnews/$CARDNEWS_NAME"

echo "[1/5] 이미지 복사: $IMAGES_DIR -> $DEST_DIR"
mkdir -p "$DEST_DIR"
cp "$IMAGES_DIR"/*.png "$DEST_DIR"/

# 캐러셀 순서 고정을 위해 파일명 정렬 (1-cover.png, 2-xxx.png, ...)
mapfile -t IMAGE_FILES < <(ls "$DEST_DIR"/*.png | sort -V)
if [ "${#IMAGE_FILES[@]}" -lt 2 ] || [ "${#IMAGE_FILES[@]}" -gt 20 ]; then
  echo "Threads 캐러셀은 2~20장만 지원함 (현재 ${#IMAGE_FILES[@]}장)" >&2
  exit 1
fi

echo "[2/5] 이미지 공개 호스팅용 git 커밋/푸시"
git add "$DEST_DIR"
if ! git diff --cached --quiet; then
  git commit -m "assets: add cardnews images for threads publish ($CARDNEWS_NAME)"
else
  echo "  변경 없음 (이미 커밋된 이미지) — 건너뜀"
fi
git push origin "$GITHUB_BRANCH"
COMMIT_SHA="$(git rev-parse HEAD)"

echo "[3/5] 캐러셀 아이템 컨테이너 생성 (${#IMAGE_FILES[@]}장)"
CHILD_IDS=()
for f in "${IMAGE_FILES[@]}"; do
  fname="$(basename "$f")"
  RAW_URL="https://raw.githubusercontent.com/${GITHUB_OWNER}/${GITHUB_REPO}/${COMMIT_SHA}/assets/cardnews/${CARDNEWS_NAME}/${fname}"
  echo "  - $fname -> $RAW_URL"
  ITEM_ID=$(curl -s -X POST "https://graph.threads.net/v1.0/${THREADS_USER_ID}/threads" \
    --data-urlencode "media_type=IMAGE" \
    --data-urlencode "image_url=${RAW_URL}" \
    --data-urlencode "is_carousel_item=true" \
    --data-urlencode "access_token=${THREADS_ACCESS_TOKEN}" \
    | node -e "process.stdin.once('data',d=>{const j=JSON.parse(d);if(j.error){console.error(JSON.stringify(j.error));process.exit(1)}console.log(j.id)})")
  echo "    컨테이너: $ITEM_ID"
  CHILD_IDS+=("$ITEM_ID")
done

CHILDREN_CSV="$(IFS=,; echo "${CHILD_IDS[*]}")"

echo "[4/5] 캐러셀 컨테이너 생성"
CAROUSEL_ID=$(curl -s -X POST "https://graph.threads.net/v1.0/${THREADS_USER_ID}/threads" \
  --data-urlencode "media_type=CAROUSEL" \
  --data-urlencode "children=${CHILDREN_CSV}" \
  --data-urlencode "text@${CAPTION_FILE}" \
  --data-urlencode "access_token=${THREADS_ACCESS_TOKEN}" \
  | node -e "process.stdin.once('data',d=>{const j=JSON.parse(d);if(j.error){console.error(JSON.stringify(j.error));process.exit(1)}console.log(j.id)})")

echo "  캐러셀 컨테이너: $CAROUSEL_ID"

if [ "$PUBLISH" -eq 0 ]; then
  echo "--publish 없이 실행됨 — 여기서 멈춤."
  echo "캡션/이미지 확인 후 게시하려면:"
  echo "  scripts/publish-cardnews.sh \"$CARDNEWS_DIR\" --caption-file \"$CAPTION_FILE\" --publish"
  exit 0
fi

echo "[5/5] 컨테이너 처리 대기 후 게시"
STATUS="IN_PROGRESS"
for i in $(seq 1 20); do
  STATUS=$(curl -s "https://graph.threads.net/v1.0/${CAROUSEL_ID}?fields=status&access_token=${THREADS_ACCESS_TOKEN}" \
    | node -e "process.stdin.once('data',d=>console.log(JSON.parse(d).status||'UNKNOWN'))")
  echo "  status ($i): $STATUS"
  [ "$STATUS" = "FINISHED" ] && break
  [ "$STATUS" = "ERROR" ] && { echo "컨테이너 처리 실패" >&2; exit 1; }
  sleep 8
done
if [ "$STATUS" != "FINISHED" ]; then
  echo "처리 시간 초과" >&2
  exit 1
fi

MEDIA_ID=$(curl -s -X POST "https://graph.threads.net/v1.0/${THREADS_USER_ID}/threads_publish" \
  --data-urlencode "creation_id=${CAROUSEL_ID}" \
  --data-urlencode "access_token=${THREADS_ACCESS_TOKEN}" \
  | node -e "process.stdin.once('data',d=>{const j=JSON.parse(d);if(j.error){console.error(JSON.stringify(j.error));process.exit(1)}console.log(j.id)})")

echo "게시 완료: media id $MEDIA_ID"
curl -s "https://graph.threads.net/v1.0/${MEDIA_ID}?fields=permalink&access_token=${THREADS_ACCESS_TOKEN}"
echo
