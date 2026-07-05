#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

prog=${0##*/}
workdirs=()
tmpfiles=()

msg() {
    printf '%s\n' "$*" >&2
}

die() {
    msg "$prog: error: $*"
    exit 1
}

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

show_log() {
    local file=$1
    local line=

    [ -s "$file" ] || return 0

    while IFS= read -r line || [ -n "$line" ]; do
        msg "$line"
    done < "$file"
}

random_12_digits() {
    local out=
    local i=

    for ((i = 0; i < 12; i++)); do
        out="${out}$((RANDOM % 10))"
    done

    printf '%s' "$out"
}

make_workdir() {
    local i=
    local d=

    for ((i = 0; i < 100; i++)); do
        d="/tmp/fix_$(random_12_digits)"
        if mkdir -m 700 -- "$d" 2>/dev/null; then
            workdirs+=("$d")
            printf '%s' "$d"
            return 0
        fi
    done

    return 1
}

make_tmp_output() {
    local dir=$1
    local base=$2
    local i=
    local f=

    for ((i = 0; i < 100; i++)); do
        f="${dir}/.${base}.fix.$(random_12_digits).tmp"
        if ( set -C; : > "$f" ) 2>/dev/null; then
            tmpfiles+=("$f")
            printf '%s' "$f"
            return 0
        fi
    done

    return 1
}

cleanup() {
    local p=

    for p in "${tmpfiles[@]}"; do
        if [ -n "${p:-}" ] && [ -e "$p" ]; then
            rm -f -- "$p" 2>/dev/null || true
        fi
    done

    for p in "${workdirs[@]}"; do
        if [ -n "${p:-}" ] && [ -d "$p" ]; then
            rm -rf -- "$p" 2>/dev/null || true
        fi
    done
}

on_interrupt() {
    die "interrupted"
}

check_list_paths() {
    local list_file=$1
    local name=
    local part=
    local old_ifs=
    local parts=()

    while IFS= read -r name || [ -n "$name" ]; do
        case "$name" in
            ""|"."|"./")
                continue
                ;;
            /*)
                msg "unsafe member path: $name"
                return 1
                ;;
        esac

        old_ifs=$IFS
        IFS='/'
        read -r -a parts <<< "$name"
        IFS=$old_ifs

        for part in "${parts[@]}"; do
            if [ "$part" = ".." ]; then
                msg "unsafe member path: $name"
                return 1
            fi
        done
    done < "$list_file"

    return 0
}

set_like_old_file() {
    local old_file=$1
    local new_file=$2
    local mode=
    local uid=
    local gid=

    mode=$(stat -c '%a' -- "$old_file" 2>/dev/null || true)
    uid=$(stat -c '%u' -- "$old_file" 2>/dev/null || true)
    gid=$(stat -c '%g' -- "$old_file" 2>/dev/null || true)

    if [ -n "$mode" ]; then
        chmod "$mode" -- "$new_file" 2>/dev/null || true
    fi

    if [ "${EUID:-1}" -eq 0 ] && [ -n "$uid" ] && [ -n "$gid" ]; then
        chown "$uid:$gid" -- "$new_file" 2>/dev/null || true
    fi
}

process_archive() {
    local input=$1
    local archive_dir=
    local archive_base=
    local archive_abs=
    local work=
    local extract_dir=
    local list_txt=
    local list_err=
    local extract_err=
    local repack_list=
    local verify_txt=
    local verify_err=
    local tmp_out=
    local extract_opts=()

    [ -n "$input" ] || die "empty file name"
    [ -e "$input" ] || die "not found: $input"
    [ -f "$input" ] || die "not a regular file: $input"
    [ ! -L "$input" ] || die "refuse symlink: $input"
    [ -r "$input" ] || die "not readable: $input"
    [ -w "$input" ] || die "not writable: $input"

    archive_dir=$(cd -P -- "$(dirname -- "$input")" && pwd) || die "cannot resolve directory: $input"
    archive_base=$(basename -- "$input")
    archive_abs="${archive_dir}/${archive_base}"

    [ -w "$archive_dir" ] || die "directory not writable: $archive_dir"

    msg "fixing: $archive_abs"

    if ! gzip -t -- "$archive_abs" 2>/dev/null; then
        die "gzip test failed: $archive_abs"
    fi

    work=$(make_workdir) || die "cannot create work directory under /tmp"
    extract_dir="${work}/root"
    list_txt="${work}/list.txt"
    list_err="${work}/list.err"
    extract_err="${work}/extract.err"
    repack_list="${work}/repack-list.nul"
    verify_txt="${work}/verify.txt"
    verify_err="${work}/verify.err"

    mkdir -- "$extract_dir"

    if ! tar -tzf "$archive_abs" > "$list_txt" 2> "$list_err"; then
        show_log "$list_err"
        die "tar list failed: $archive_abs"
    fi

    if ! check_list_paths "$list_txt"; then
        die "archive contains unsafe paths: $archive_abs"
    fi

    extract_opts=(-xzf "$archive_abs" -C "$extract_dir" --delay-directory-restore)

    if [ "${EUID:-1}" -ne 0 ]; then
        extract_opts+=(--no-same-owner)
    fi

    if ! tar "${extract_opts[@]}" 2> "$extract_err"; then
        show_log "$extract_err"
        die "tar extract failed: $archive_abs"
    fi

    (
        cd -- "$extract_dir"
        if command -v sort >/dev/null 2>&1; then
            find . -mindepth 1 -print0 | LC_ALL=C sort -z > "$repack_list"
        else
            find . -mindepth 1 -print0 > "$repack_list"
        fi
    )

    tmp_out=$(make_tmp_output "$archive_dir" "$archive_base") || die "cannot create temp output in: $archive_dir"

    if ! tar -czf "$tmp_out" -C "$extract_dir" --null -T "$repack_list"; then
        die "tar repack failed: $archive_abs"
    fi

    if ! gzip -t -- "$tmp_out" 2>/dev/null; then
        die "new gzip test failed: $tmp_out"
    fi

    if ! tar -tzf "$tmp_out" > "$verify_txt" 2> "$verify_err"; then
        show_log "$verify_err"
        die "new archive verify failed: $tmp_out"
    fi

    if grep -F 'Substituting "." for empty member name' "$verify_err" >/dev/null 2>&1; then
        show_log "$verify_err"
        die "new archive still has empty member name: $tmp_out"
    fi

    set_like_old_file "$archive_abs" "$tmp_out"

    if ! mv -f -- "$tmp_out" "$archive_abs"; then
        die "cannot replace original file: $archive_abs"
    fi

    rm -rf -- "$work"
    msg "fixed: $archive_abs"
}

usage() {
    msg "usage: $prog FILE.tar.gz [FILE2.tar.gz ...]"
}

trap cleanup EXIT
trap on_interrupt INT TERM

need_cmd tar
need_cmd gzip
need_cmd find
need_cmd grep
need_cmd mkdir
need_cmd mv
need_cmd rm
need_cmd stat

if [ "$#" -lt 1 ]; then
    usage
    exit 2
fi

for archive in "$@"; do
    process_archive "$archive"
done
