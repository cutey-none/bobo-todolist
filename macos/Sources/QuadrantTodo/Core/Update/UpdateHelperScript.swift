import Foundation

/// 升级助手：应用退出后由它替换 .app，失败时还原，并写下结果供新版启动时提示。
/// 参数：<旧进程 pid> <暂存 app> <目标 app> <备份目录> <结果文件> <版本>
enum UpdateHelperScript {
    static let source = #"""
    #!/bin/zsh
    # 由四象限待办在升级时启动：等待旧进程退出后替换 .app，失败则还原旧版本。
    set -u
    PID=$1 STAGED=$2 TARGET=$3 BACKUP=$4 RESULT=$5 VERSION=$6
    WAIT_SECONDS=${QT_UPDATE_WAIT_SECONDS:-30}
    OPEN_CMD=${QT_UPDATE_OPEN_CMD:-/usr/bin/open}
    STAGING_DIR=${STAGED:h}

    json_escape() { local s=${1//\\/\\\\}; print -rn -- "${s//\"/\\\"}" }

    finish() {
        mkdir -p -- "${RESULT:h}"
        print -r -- "{\"status\":\"$1\",\"version\":\"$(json_escape "$VERSION")\",\"backup\":\"$(json_escape "$BACKUP")\"}" > "$RESULT.tmp" \
            && mv -f -- "$RESULT.tmp" "$RESULT"
        # 只清理应用自己创建的暂存目录。
        [[ ${STAGING_DIR:t} == .quadrant-update.* ]] && rm -rf -- "$STAGING_DIR"
        # 超时说明旧版本仍在运行，不再重复打开。
        [[ $1 == timeout ]] || "$OPEN_CMD" "$TARGET"
        exit $2
    }

    ticks=0
    while kill -0 "$PID" 2>/dev/null; do
        (( ticks >= WAIT_SECONDS * 10 )) && finish timeout 1
        sleep 0.1
        (( ticks++ ))
    done

    mkdir -p -- "$BACKUP" || finish failed 1
    if [[ -e $TARGET ]]; then
        mv -- "$TARGET" "$BACKUP/Previous.app" || finish failed 1
    fi
    if mv -- "$STAGED" "$TARGET"; then
        finish success 0
    fi
    [[ -e $BACKUP/Previous.app ]] && mv -- "$BACKUP/Previous.app" "$TARGET"
    finish restored 1
    """#

    static func write(to directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("quadrant-update-helper-\(UUID().uuidString).zsh")
        try source.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
