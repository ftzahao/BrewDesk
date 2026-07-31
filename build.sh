#!/bin/bash
set -euo pipefail

PROJECT="BrewDesk.xcodeproj"
SCHEME="BrewDesk"
CONFIG="Release"
DERIVED_DATA="build"

APPCast="appcast.xml"
SUFeedURL="https://raw.githubusercontent.com/ftzahao/BrewDesk/main/appcast.xml"

# 从 Xcode 项目读取 MARKETING_VERSION
get_version() {
    grep 'MARKETING_VERSION' "$PROJECT"/project.pbxproj | grep -oE '[0-9]+\.[0-9]+([0-9.]+)?' | head -1
}

usage() {
    cat <<EOF
用法: ./build.sh [命令]

命令:
  build      构建 Release 版本（默认）
  debug      构建 Debug 版本
  clean      清理构建产物
  archive    构建并归档为 .xcarchive
  export     归档并导出 .app（需先 archive）
  dmg        构建并打包为 .dmg 安装镜像
  sign       sign_update 为 DMG 签名并输出 appcast 条目
  release    构建 → DMG → 签名 → 更新 appcast.xml → 打印摘要
  appcast    更新 appcast.xml 中的版本条目（基于 DMG 签名文件）
  bump       从 VERSION 文件读取版本号并更新项目
  help       显示帮助信息
EOF
}

do_clean() {
    echo "==> 清理构建产物..."
    rm -rf "$DERIVED_DATA"
    xcodebuild clean -project "$PROJECT" -scheme "$SCHEME" -quiet 2>/dev/null || true
    echo "✅ 清理完成"
}

do_build() {
    local config="${1:-Release}"
    echo "==> 构建 $config 版本..."
    xcodebuild build \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -configuration "$config" \
        -derivedDataPath "$DERIVED_DATA" \
        -quiet
    echo "✅ 构建完成: $DERIVED_DATA/Build/Products/$config/BrewDesk.app"
}

do_archive() {
    local archive_path="$DERIVED_DATA/BrewDesk.xcarchive"
    echo "==> 归档..."
    xcodebuild archive \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -configuration "$CONFIG" \
        -derivedDataPath "$DERIVED_DATA" \
        -archivePath "$archive_path" \
        -quiet
    echo "✅ 归档完成: $archive_path"
}

do_export() {
    local archive_path="$DERIVED_DATA/BrewDesk.xcarchive"
    local export_path="$DERIVED_DATA/export"

    if [ ! -d "$archive_path" ]; then
        echo "❌ 未找到归档文件，请先运行 ./build.sh archive"
        exit 1
    fi

    # 生成 ExportOptions.plist
    local plist="$DERIVED_DATA/ExportOptions.plist"
    cat > "$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>mac-application</string>
    <key>destination</key>
    <string>export</string>
</dict>
</plist>
PLIST

    echo "==> 导出 .app..."
    xcodebuild -exportArchive \
        -archivePath "$archive_path" \
        -exportOptionsPlist "$plist" \
        -exportPath "$export_path" \
        -quiet
    echo "✅ 导出完成: $export_path/BrewDesk.app"
}

do_dmg() {
    do_build "Release"
    local app_path="$DERIVED_DATA/Build/Products/$CONFIG/BrewDesk.app"
    local dmg_path="$DERIVED_DATA/BrewDesk.dmg"

    echo "==> 打包 DMG..."
    # 移除旧 DMG
    rm -f "$dmg_path"

    # 创建临时目录
    local tmp_dir="$DERIVED_DATA/dmg_staging"
    rm -rf "$tmp_dir"
    mkdir -p "$tmp_dir"
    cp -R "$app_path" "$tmp_dir/"

    # 创建 Applications 快捷方式
    ln -s /Applications "$tmp_dir/Applications"

    hdiutil create \
        -volname "BrewDesk" \
        -srcfolder "$tmp_dir" \
        -ov -format UDZO \
        "$dmg_path" \
        -quiet

    rm -rf "$tmp_dir"
    echo "✅ DMG 打包完成: $dmg_path"
}

do_sign() {
    local dmg_path="${1:-$DERIVED_DATA/BrewDesk.dmg}"

    if [ ! -f "$dmg_path" ]; then
        echo "❌ 未找到 DMG 文件: $dmg_path"
        echo "   请先运行 ./build.sh dmg"
        exit 1
    fi

    # 查找 Sparkle 的 sign_update 工具
    local sign_tool=""
    if command -v sign_update &>/dev/null; then
        sign_tool="sign_update"
    elif [ -f "$DERIVED_DATA/SourcePackages/sparkle/bin/sign_update" ]; then
        sign_tool="$DERIVED_DATA/SourcePackages/sparkle/bin/sign_update"
    elif [ -d "/Applications/Sparkle.app" ]; then
        sign_tool="/Applications/Sparkle.app/Contents/MacOS/sign_update"
    else
        # 尝试在 DerivedData 中查找
        sign_tool=$(find "$DERIVED_DATA" -path "*/sparkle*/bin/sign_update" -type f 2>/dev/null | head -1)
    fi

    if [ -z "$sign_tool" ] || [ ! -f "$sign_tool" ]; then
        echo "⚠️  未找到 sign_update 工具。请通过 Homebrew 安装 Sparkle CLI："
        echo "   brew install sparkle-cli"
        echo ""
        echo "或者手动使用 Sparkle.app 中的工具："
        echo "   /Applications/Sparkle.app/Contents/MacOS/sign_update $dmg_path"
        echo ""
        # 尝试用 openssl 计算基础信息
        local file_size
        file_size=$(stat -f%z "$dmg_path")
        echo "--- 手动填写到 appcast.xml ---"
        echo "文件大小: $file_size"
        echo "edSignature: （运行 sign_update 工具获取）"
        return 1
    fi

    echo "==> 签名 DMG: $(basename "$dmg_path")"
    local sign_output
    sign_output=$("$sign_tool" "$dmg_path")
    echo "$sign_output"

    # 解析签名输出
    local ed_signature
    local file_size
    ed_signature=$(echo "$sign_output" | grep -oE 'sparkle:edSignature="[^"]+"' | head -1 | sed 's/sparkle:edSignature="//;s/"//')
    file_size=$(stat -f%z "$dmg_path")

    if [ -z "$ed_signature" ]; then
        echo "⚠️  无法从输出中解析 edSignature，请手动填写。"
        return 1
    fi

    # 输出到文件供其他命令使用
    echo "$ed_signature" > "$DERIVED_DATA/last_ed_signature.txt"
    echo "$file_size" > "$DERIVED_DATA/last_dmg_size.txt"
    echo "$(basename "$dmg_path")" > "$DERIVED_DATA/last_dmg_name.txt"

    echo ""
    echo "=== AppCast 条目（可粘贴到 appcast.xml）==="
    echo "edSignature: $ed_signature"
    echo "length:      $file_size"
}

do_appcast() {
    local sig_file="$DERIVED_DATA/last_ed_signature.txt"
    local size_file="$DERIVED_DATA/last_dmg_size.txt"

    if [ ! -f "$sig_file" ] || [ ! -f "$size_file" ]; then
        echo "❌ 未找到签名信息，请先运行 ./build.sh sign"
        return 1
    fi

    local ed_signature
    local file_size
    ed_signature=$(cat "$sig_file")
    file_size=$(cat "$size_file")

    local version
    version=$(get_version)
    if [ -z "$version" ]; then
        echo "❌ 无法从项目中读取 MARKETING_VERSION"
        return 1
    fi

    local pub_date
    pub_date=$(date "+%a, %d %b %Y %H:%M:%S %z")
    local download_url="https://github.com/ftzahao/BrewDesk/releases/download/${version}/BrewDesk.dmg"

    echo "==> 生成 $APPCast..."

    cat > "$APPCast" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0"
     xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"
     xmlns:dc="http://purl.org/dc/elements/1.1/">
    <channel>
        <title>BrewDesk</title>
        <description>Homebrew 的原生 macOS 图形界面 — 自动更新</description>
        <language>zh-Hans</language>
        <link>https://github.com/ftzahao/BrewDesk</link>

        <item>
            <title>BrewDesk ${version}</title>
            <pubDate>${pub_date}</pubDate>
            <sparkle:channel>release</sparkle:channel>
            <sparkle:version>${version}</sparkle:version>
            <sparkle:shortVersionString>${version}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>26.5</sparkle:minimumSystemVersion>
            <sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements>
            <enclosure url="${download_url}" length="${file_size}" type="application/octet-stream" sparkle:edSignature="${ed_signature}" />
            <description sparkle:format="markdown"><![CDATA[
## ${version}

更新内容请补充
            ]]></description>
        </item>
    </channel>
</rss>
XML

    echo "✅ appcast.xml 已更新"
    echo "   版本: $version"
    echo "   edSignature: $ed_signature"
    echo "   length: $file_size"
    echo "   download: $download_url"
}

do_bump_version() {
    local version_file="VERSION"
    if [ ! -f "$version_file" ]; then
        echo "❌ 未找到 $version_file"
        return 1
    fi

    local new_version
    new_version=$(cat "$version_file" | tr -d '[:space:]')
    if [ -z "$new_version" ]; then
        echo "❌ $version_file 为空"
        return 1
    fi

    echo "==> 更新版本到 $new_version..."

    if [[ "$(uname)" == "Darwin" ]]; then
        sed -i '' "s/MARKETING_VERSION = [^;]*/MARKETING_VERSION = $new_version/" "$PROJECT"/project.pbxproj
        sed -i '' "s/CURRENT_PROJECT_VERSION = [^;]*/CURRENT_PROJECT_VERSION = $new_version/" "$PROJECT"/project.pbxproj
    else
        sed -i "s/MARKETING_VERSION = [^;]*/MARKETING_VERSION = $new_version/" "$PROJECT"/project.pbxproj
        sed -i "s/CURRENT_PROJECT_VERSION = [^;]*/CURRENT_PROJECT_VERSION = $new_version/" "$PROJECT"/project.pbxproj
    fi

    echo "✅ 版本已更新为 $new_version"
}

do_release() {
    local ok=true

    do_dmg || ok=false

    if [ "$ok" = true ]; then
        if do_sign; then
            do_appcast || true
        else
            echo "⚠️  跳过 appcast 更新（sign_update 未找到或签名失败）"
        fi
    fi

    echo ""
    echo "=== 发布摘要 ==="
    if [ -f "$DERIVED_DATA/BrewDesk.dmg" ]; then
        echo "DMG:  $DERIVED_DATA/BrewDesk.dmg ✅"
        local size
        size=$(stat -f%z "$DERIVED_DATA/BrewDesk.dmg" 2>/dev/null | numfmt --to=iec 2>/dev/null || stat -f%z "$DERIVED_DATA/BrewDesk.dmg" 2>/dev/null || echo "?")
        echo "大小: $size"
    else
        echo "DMG:  ❌ 未生成"
    fi
    echo "Cast: $APPCast"
    if [ -f "$DERIVED_DATA/last_ed_signature.txt" ]; then
        echo "签名: ✅ $(cat "$DERIVED_DATA/last_ed_signature.txt" | head -c 20)..."
    else
        echo "签名: ⚠️  未签名"
    fi
    echo ""
    echo "下一步:"
    if [ ! -f "$DERIVED_DATA/BrewDesk.dmg" ]; then
        echo "❌ 请先修复构建错误"
    else
        echo "1. 在 GitHub 上创建 Release 并上传 BrewDesk.dmg"
        echo "2. 确保 $APPCast 可通过 ${SUFeedURL:-https://raw.githubusercontent.com/ftzahao/BrewDesk/main/appcast.xml} 访问"
        echo "3. git add $APPCast && git commit -m \"chore: 更新 appcast\""
    fi
}

# 主入口
case "${1:-build}" in
    build)   do_build "Release" ;;
    debug)   do_build "Debug" ;;
    clean)   do_clean ;;
    archive) do_archive ;;
    export)  do_export ;;
    dmg)     do_dmg ;;
    sign)    do_sign ;;
    appcast) do_appcast ;;
    bump)    do_bump_version ;;
    release) do_release ;;
    help)    usage ;;
    *)       echo "未知命令: $1"; usage; exit 1 ;;
esac
