#!/bin/bash
#
# KeyboardLocker 发版脚本
#
#   ./release.sh 1.0.1              发指定版本
#   ./release.sh patch              在最新 tag 上自动 +1（也可用 minor / major）
#   ./release.sh 1.0.1 --dry-run    只预览，不改文件、不推远程
#   ./release.sh 1.0.1 --notes-file notes.md   用自定义 Release 说明
#   ./release.sh 1.0.1 --draft      创建草稿，不对外发布
#   ./release.sh 1.0.1 -y           跳过确认（CI 用）
#
# 前置条件：工作区干净、位于 main 且与远程同步、gh 已登录。
# CHANGELOG.md 里若没有对应版本段落，会用 git log 自动生成条目。
#
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="KeyboardLocker"
REMOTE="origin"
BRANCH="main"
PLIST="Resources/Info.plist"
CHANGELOG="CHANGELOG.md"
BUILD_DIR="build"
APP="$BUILD_DIR/$APP_NAME.app"
ZIP="$BUILD_DIR/$APP_NAME.zip"

VERSION=""
NOTES_FILE=""
DRY_RUN=0
DRAFT=0
ASSUME_YES=0

# ---------------------------------------------------------------- 工具函数
die()  { printf '错误: %s\n' "$*" >&2; exit 1; }
warn() { printf '警告: %s\n' "$*" >&2; }
info() { printf '==> %s\n' "$*"; }

usage() {
    sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

# 严格 X.Y.Z，返回后可用 PARTS 读取三段数字
read_version() {
    [[ "$1" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] \
        || die "版本号格式应为 X.Y.Z（收到 '$1'）"
    V_MAJ=$((10#${BASH_REMATCH[1]}))
    V_MIN=$((10#${BASH_REMATCH[2]}))
    V_PAT=$((10#${BASH_REMATCH[3]}))
}

# $1 > $2 返回 0
version_gt() {
    local a1 a2 a3 b1 b2 b3
    IFS=. read -r a1 a2 a3 <<< "$1"
    IFS=. read -r b1 b2 b3 <<< "$2"
    (( 10#$a1 > 10#$b1 )) && return 0
    (( 10#$a1 < 10#$b1 )) && return 1
    (( 10#$a2 > 10#$b2 )) && return 0
    (( 10#$a2 < 10#$b2 )) && return 1
    (( 10#$a3 > 10#$b3 ))
}

TMP_DIR=""
cleanup() {
    [ -z "$TMP_DIR" ] || rm -rf "$TMP_DIR"
    return 0
}
trap cleanup EXIT

# ---------------------------------------------------------------- 解析参数
[ "$#" -ge 1 ] || usage
while [ "$#" -gt 0 ]; do
    case "$1" in
        -h|--help) usage ;;
        --dry-run) DRY_RUN=1 ;;
        --draft) DRAFT=1 ;;
        -y|--yes) ASSUME_YES=1 ;;
        --notes-file)
            shift
            [ "$#" -gt 0 ] || die "--notes-file 缺少文件路径"
            NOTES_FILE="$1"
            ;;
        --notes-file=*) NOTES_FILE="${1#*=}" ;;
        -*) die "未知参数: $1" ;;
        *) [ -z "$VERSION" ] || die "只能指定一个版本号"; VERSION="$1" ;;
    esac
    shift
done
[ -n "$VERSION" ] || die "缺少版本号"
[ -z "$NOTES_FILE" ] || [ -f "$NOTES_FILE" ] || die "notes 文件不存在: $NOTES_FILE"

# ---------------------------------------------------------------- 前置检查
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "当前目录不是 git 仓库"
command -v gh >/dev/null 2>&1 || die "未安装 GitHub CLI (gh)"
gh auth status >/dev/null 2>&1 || die "gh 未登录，先执行 gh auth login"
command -v /usr/libexec/PlistBuddy >/dev/null 2>&1 || die "缺少 PlistBuddy"

git remote get-url "$REMOTE" >/dev/null 2>&1 || die "缺少远程 $REMOTE"
[ "$(git branch --show-current)" = "$BRANCH" ] || die "请切换到 $BRANCH 分支再发版"

if [ "$DRY_RUN" -eq 0 ]; then
    [ -z "$(git status --porcelain)" ] || die "工作区有未提交改动，请先提交或 stash"
    info "检查远程同步状态"
    git fetch --quiet "$REMOTE" "$BRANCH"
    LOCAL_HEAD=$(git rev-parse HEAD)
    REMOTE_HEAD=$(git rev-parse "$REMOTE/$BRANCH")
    [ "$LOCAL_HEAD" = "$REMOTE_HEAD" ] \
        || die "本地 $BRANCH 与 $REMOTE/$BRANCH 不一致，请先 pull --rebase"
else
    [ -z "$(git status --porcelain)" ] || warn "工作区有未提交改动（dry-run 已忽略）"
fi

ALL_TAGS=$(git tag -l 'v[0-9]*' --sort=-v:refname)
LATEST_TAG=${ALL_TAGS%%$'\n'*}
LATEST_VERSION="${LATEST_TAG#v}"
[ -n "$LATEST_VERSION" ] || die "找不到已有版本 tag，无法比对版本"
read_version "$LATEST_VERSION"

# ---------------------------------------------------------------- 计算版本
case "$VERSION" in
    patch|minor|major)
        read_version "$LATEST_VERSION"
        case "$VERSION" in
            patch) NEW_VERSION="$V_MAJ.$V_MIN.$((V_PAT + 1))" ;;
            minor) NEW_VERSION="$V_MAJ.$((V_MIN + 1)).0" ;;
            major) NEW_VERSION="$((V_MAJ + 1)).0.0" ;;
        esac
        info "基于 $LATEST_TAG 自动递增 → $NEW_VERSION"
        VERSION="$NEW_VERSION"
        ;;
    *) read_version "$VERSION" ;;
esac

version_gt "$VERSION" "$LATEST_VERSION" \
    || die "新版本 $VERSION 必须大于当前版本 $LATEST_VERSION"
TAG="v$VERSION"

if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null 2>&1; then
    die "本地已存在 tag $TAG"
fi
if git ls-remote --exit-code --tags "$REMOTE" "refs/tags/$TAG" >/dev/null 2>&1; then
    die "远程已存在 tag $TAG"
fi
if gh release view "$TAG" >/dev/null 2>&1; then
    die "GitHub 上已存在 Release $TAG"
fi

CURRENT_PLIST_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST")
CURRENT_BUILD_NUMBER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PLIST")
NEEDS_BUMP=0
[ "$CURRENT_PLIST_VERSION" = "$VERSION" ] || NEEDS_BUMP=1

# ---------------------------------------------------------------- 生成 notes
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/keyboardlocker-release.XXXXXX")
NOTES="$TMP_DIR/notes.md"

if [ -n "$NOTES_FILE" ]; then
    cp "$NOTES_FILE" "$NOTES"
    info "使用自定义 Release 说明: $NOTES_FILE"
else
    BODY=$(awk -v ver="$VERSION" '
        /^## / { if (found) exit }
        $0 ~ "^## " ver "([ \t]|$)" { found = 1; next }
        found { lines[++n] = $0 }
        END {
            if (!found) exit 1
            s = 1; e = n
            while (s <= e && lines[s] ~ /^[ \t]*$/) s++
            while (e >= s && lines[e] ~ /^[ \t]*$/) e--
            for (i = s; i <= e; i++) print lines[i]
        }
    ' "$CHANGELOG" 2>/dev/null || true)

    if [ -z "$BODY" ]; then
        warn "$CHANGELOG 里没有 ## $VERSION 段落，改用 git log 生成条目"
        BODY=$(git log --no-merges --pretty=format:'- %s' "${LATEST_TAG}..HEAD" || true)
        [ -n "$BODY" ] || BODY="Maintenance release."
        BODY=$(printf '**Changes since %s**\n\n%s' "$LATEST_TAG" "$BODY")
    fi

    {
        printf '%s\n\n' "$BODY"
        cat <<'EOF'
**Install**

1. Download `KeyboardLocker.zip`, unzip and move `KeyboardLocker.app` to `/Applications`
2. First launch: right-click the app → **Open** (the build is ad-hoc signed, so Gatekeeper warns once)
3. Grant **Accessibility** in System Settings › Privacy & Security (and **Input Monitoring** if it isn't listed there)
4. Click the keyboard icon in the menu bar

Verify the download with `shasum -a 256 -c KeyboardLocker.zip.sha256`.

Requires macOS 13 or later.
EOF
    } > "$NOTES"
    info "已生成 Release 说明"
fi

# ---------------------------------------------------------------- 预览模式
if [ "$DRY_RUN" -eq 1 ]; then
    info "构建并打包（仅本地，不改动受版本控制的文件）"
    KEYBOARDLOCKER_ADHOC=1 ./build.sh >/dev/null
    rm -f "$ZIP"
    ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
    shasum -a 256 "$ZIP" | awk -v name="$(basename "$ZIP")" '{print $1 "  " name}' > "$ZIP.sha256"

    printf '\n──────── Release 说明预览 ────────\n'
    cat "$NOTES"
    printf '\n──────── 将执行的动作 ────────\n'
    printf '版本      : %s  (tag %s)\n' "$VERSION" "$TAG"
    printf '版本字段  : %s → %s，build %s → %s\n' \
        "$CURRENT_PLIST_VERSION" "$VERSION" "$CURRENT_BUILD_NUMBER" "$((CURRENT_BUILD_NUMBER + 1))"
    printf '提交      : %s\n' "$([ "$NEEDS_BUMP" -eq 1 ] && echo 'Bump version to '"$VERSION" || echo '（无需 bump，直接打 tag）')"
    printf '资产      : %s (%s) + sha256\n' "$(basename "$ZIP")" "$(du -h "$ZIP" | awk '{print $1}')"
    printf '推送      : git push %s %s && git push %s %s\n' "$REMOTE" "$BRANCH" "$REMOTE" "$TAG"
    printf '发布      : gh release create %s%s\n' "$TAG" "$([ "$DRAFT" -eq 1 ] && echo ' --draft' || echo '')"
    printf '\n这是 dry-run，没有修改任何受版本控制的文件，也没有推送。\n'
    exit 0
fi

# ---------------------------------------------------------------- 确认
printf '\n即将发布 %s：\n' "$TAG"
printf '  · 版本字段 %s → %s\n' "$CURRENT_PLIST_VERSION" "$VERSION"
printf '  · notes 预览前 5 行:\n'
sed -n '1,5p' "$NOTES" | sed 's/^/      /'
printf '\n'
if [ "$ASSUME_YES" -eq 0 ]; then
    read -r -p "确认发布? [y/N] " reply
    [[ "$reply" = "y" || "$reply" = "Y" ]] || die "已取消"
fi

# ---------------------------------------------------------------- 版本 bump
if [ "$NEEDS_BUMP" -eq 1 ]; then
    info "更新 $PLIST"
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $((CURRENT_BUILD_NUMBER + 1))" "$PLIST"
    git add "$PLIST"
    git commit -q -m "Bump version to $VERSION"
    info "已提交: $(git log -1 --pretty=%s)"
fi

# ---------------------------------------------------------------- 构建打包
info "构建 $APP_NAME（发布模式强制 ad-hoc 签名）"
KEYBOARDLOCKER_ADHOC=1 ./build.sh >/dev/null

[ -x "$APP/Contents/MacOS/$APP_NAME" ] || die "构建产物缺少可执行文件"
BUILT_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
[ "$BUILT_VERSION" = "$VERSION" ] || die "产物版本 $BUILT_VERSION 与目标 $VERSION 不一致"
codesign --verify --strict "$APP" || die "签名校验失败"

info "打包"
rm -f "$ZIP" "$ZIP.sha256"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
shasum -a 256 "$ZIP" | awk -v name="$(basename "$ZIP")" '{print $1 "  " name}' > "$ZIP.sha256"
printf '    %s (%s)\n' "$ZIP" "$(du -h "$ZIP" | awk '{print $1}')"

# ---------------------------------------------------------------- tag + push
info "创建并推送 tag"
git tag -a "$TAG" -m "$APP_NAME $VERSION"
git push --quiet "$REMOTE" "$BRANCH" || die "分支推送失败；本地 tag $TAG 已创建，请检查后重试"
git push --quiet "$REMOTE" "$TAG"   || die "tag 推送失败；可用 git push $REMOTE $TAG 重试"

# ---------------------------------------------------------------- Release
info "创建 GitHub Release"
GH_ARGS=(--title "$APP_NAME $VERSION" --notes-file "$NOTES" --verify-tag)
if [ "$DRAFT" -eq 1 ]; then GH_ARGS+=(--draft); fi
if ! gh release create "$TAG" "$ZIP" "$ZIP.sha256" "${GH_ARGS[@]}"; then
    die "Release 创建失败。tag 和文件已推送，可手动重试：gh release create $TAG $ZIP $ZIP.sha256 --notes-file <notes>"
fi

REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
info "完成: https://github.com/$REPO/releases/tag/$TAG"
