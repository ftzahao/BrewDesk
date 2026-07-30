#!/bin/bash
set -euo pipefail

PROJECT="BrewDesk.xcodeproj"
SCHEME="BrewDesk"
CONFIG="Release"
DERIVED_DATA="build"

usage() {
    cat <<EOF
用法: ./build.sh [命令]

命令:
  build     构建 Release 版本（默认）
  debug     构建 Debug 版本
  clean     清理构建产物
  archive   构建并归档为 .xcarchive
  export    归档并导出 .app（需先 archive）
  dmg       构建并打包为 .dmg 安装镜像
  help      显示帮助信息
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

# 主入口
case "${1:-build}" in
    build)  do_build "Release" ;;
    debug)  do_build "Debug" ;;
    clean)  do_clean ;;
    archive) do_archive ;;
    export) do_export ;;
    dmg)    do_dmg ;;
    help)   usage ;;
    *)      echo "未知命令: $1"; usage; exit 1 ;;
esac
