#!/usr/bin/env bash
# The Linux sanity cycle (the counterpart of sanity.ps1): an incremental ninja-clang Debug build and
# the tests labelled sanity, per repository.
#
# The repositories are dvv-build, the repositories of repos.txt cloned next to it (in that order) and
# the app (the folder above a libs/ root whose .gitmodules holds libs/dvv-build, as in bootstrap.sh).
# For each one: configures its ninja-clang tree (<root>/_build/<name>/ninja-clang) if it does not
# exist yet, builds it incrementally (cmake --build --preset ninja-clang) and runs
# ctest --preset ninja-clang-sanity with the GPU settings (DVV_REQUIRE_GPU=1,
# DVV_VK_VALIDATION=sync, DVV_VK_VALIDATION_REQUIRED=1 and the validation layer of
# <root>/_third_party/clang). VK_DRIVER_FILES defaults to the lavapipe ICD when the caller has not
# set it. dvv-build runs only its own dvv_build.* tests.
# Prints one PASS or FAIL line per repository and exits with 1 when any repository fails. The build
# and test output goes to <root>/_build/sanity-linux/<name>.log; a failure prints the log's last
# lines. Everything is resolved from this script's location (<root> is the folder that holds
# dvv-build). CMake 4.x, Ninja and Clang 19 must be on PATH.
set -u -o pipefail

usage() {
    cat <<'EOF'
Usage: sanity.sh [--repo <name>[,<name>...]]... [--gui] [--small] [--downstream] [--tests <regex>]

  --repo        the repositories to check: dvv-build, names from repos.txt or the app's folder
                name (repeatable or comma-separated). Default: every one that is cloned.
  --gui         also runs the sanity tests labelled display; needs DISPLAY (an X server, e.g.
                WSLg or Xvfb). Without it, or without DISPLAY, the display tests are left out.
  --small       the small cycle (T1): ninja-clang-small (every test except those labelled
                package) instead of ninja-clang-sanity in the selected repositories and in the
                app; repositories added by --downstream between them keep ninja-clang-sanity.
  --downstream  also checks every cloned repository after the first selected one in the sanity
                order (repos.txt, then the app): the users of a changed library.
  --tests       a regular expression passed on as ctest -R. Needs exactly one repository given
                with --repo; there it tests with ninja-clang-small (every test except those
                labelled package) and -R <regex> (in dvv-build it replaces the default
                ^dvv_build\. filter). Repositories added by --downstream keep their usual preset
                and get no -R. An empty value is an error.
EOF
}

script_dir=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null && pwd)
dvv_build=$(dirname "$script_dir")
root=$(dirname "$dvv_build")

trim() {
    local s=${1%$'\r'}
    s=${s#"${s%%[![:space:]]*}"}
    printf '%s' "${s%"${s##*[![:space:]]}"}"
}

# Names in sanity order (dvv-build, repos.txt, the app) and their work trees.
known=(dvv-build)
dirs=("$dvv_build")
while IFS= read -r line || [[ -n $line ]]; do
    line=$(trim "$line")
    [[ -z $line || $line == \#* ]] && continue
    known+=("$line")
    dirs+=("$root/$line")
done <"$dvv_build/repos.txt"
# The app: the root is its libs/ folder and its .gitmodules holds libs/dvv-build.
app=$(dirname "$root")
if [[ $(basename "$root") == libs && -f $app/.gitmodules && -e $app/.git ]] &&
    grep -Eq '^[[:space:]]*path[[:space:]]*=[[:space:]]*libs/dvv-build[[:space:]]*$' \
        <(tr -d '\r' <"$app/.gitmodules"); then
    app_name=$(basename "$app")
    known+=("$app_name")
    dirs+=("$app")
else
    app_name=
fi

# The work tree of a known name.
dir_of() {
    local i
    for i in "${!known[@]}"; do
        [[ ${known[i]} == "$1" ]] && { printf '%s' "${dirs[i]}"; return 0; }
    done
    return 1
}

requested=()
gui=0
small=0
downstream=0
test_regex=
while (($# > 0)); do
    case $1 in
    --repo)
        (($# >= 2)) || { usage >&2; exit 2; }
        IFS=',' read -r -a names <<<"$2"
        for name in "${names[@]}"; do
            name=$(trim "$name")
            [[ -n $name ]] && requested+=("$name")
        done
        shift 2
        ;;
    --gui) gui=1; shift ;;
    --small) small=1; shift ;;
    --downstream) downstream=1; shift ;;
    --tests)
        (($# >= 2)) || { usage >&2; exit 2; }
        [[ -n $2 ]] || { echo "sanity: --tests needs a non-empty regular expression (ctest -R)" >&2; exit 2; }
        test_regex=$2
        shift 2
        ;;
    -h | --help) usage; exit 0 ;;
    *) echo "sanity: unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done

if [[ -n $test_regex ]] && ((${#requested[@]} != 1)); then
    echo "sanity: --tests needs exactly one repository given with --repo (e.g. --repo dvv-base --tests <regex>)" >&2
    usage >&2
    exit 2
fi

is_known() {
    local k
    for k in "${known[@]}"; do [[ $k == "$1" ]] && return 0; done
    return 1
}

selected=()
if ((${#requested[@]} > 0)); then
    for name in "${requested[@]}"; do
        is_known "$name" || { echo "sanity: unknown repository: $name. Known: ${known[*]}" >&2; exit 2; }
        [[ -e $(dir_of "$name")/.git ]] || { echo "sanity: not cloned next to dvv-build: $name" >&2; exit 2; }
    done
    for name in "${known[@]}"; do
        for r in "${requested[@]}"; do
            if [[ $r == "$name" ]]; then selected+=("$name"); break; fi
        done
    done
else
    for i in "${!known[@]}"; do
        [[ -e ${dirs[i]}/.git ]] && selected+=("${known[i]}")
    done
fi
named=("${selected[@]}")

is_named() {
    local k
    for k in "${named[@]}"; do [[ $k == "$1" ]] && return 0; done
    return 1
}

if ((downstream && ${#selected[@]} > 0)); then
    selected=()
    after=0
    for i in "${!known[@]}"; do
        [[ ${known[i]} == "${named[0]}" ]] && after=1
        if ((after)) && { is_named "${known[i]}" || [[ -e ${dirs[i]}/.git ]]; }; then
            selected+=("${known[i]}")
        fi
    done
fi

# The test preset of a repository: --small applies to the selected repositories and the app;
# --tests to its one named repository, which also gets -R <regex>.
preset_of() {
    if { [[ -n $test_regex ]] && is_named "$1"; } ||
        { ((small)) && { is_named "$1" || [[ -n $app_name && $1 == "$app_name" ]]; }; }; then
        printf 'ninja-clang-small'
    else
        printf 'ninja-clang-sanity'
    fi
}
if ((small || downstream)) || [[ -n $test_regex ]]; then
    plan=
    for name in "${selected[@]}"; do
        filter=
        [[ -n $test_regex ]] && is_named "$name" && filter=", -R $test_regex"
        plan+="${plan:+, }$name ($(preset_of "$name")$filter)"
    done
    echo "sanity: $plan"
fi

export DVV_REQUIRE_GPU=1 DVV_VK_VALIDATION=sync DVV_VK_VALIDATION_REQUIRED=1
export VK_ADD_LAYER_PATH="$root/_third_party/clang/share/vulkan/explicit_layer.d"
lavapipe=/usr/share/vulkan/icd.d/lvp_icd.json
if [[ -z ${VK_DRIVER_FILES+set} && -f $lavapipe ]]; then
    export VK_DRIVER_FILES=$lavapipe
fi
# Keeps the GTK accessibility bridge quiet in the display tests.
export NO_AT_BRIDGE=${NO_AT_BRIDGE:-1}

display_filter=(-LE display)
if ((gui)); then
    if [[ -n ${DISPLAY:-} ]]; then
        display_filter=()
    else
        echo "sanity: --gui given but DISPLAY is not set; the display tests are left out"
    fi
fi
echo "sanity: VK_DRIVER_FILES=${VK_DRIVER_FILES:-<loader default>}, display tests: $( ((${#display_filter[@]})) && echo off || echo on)"

log_dir=$root/_build/sanity-linux
mkdir -p "$log_dir"

# Runs a command in a repository with its output appended to the log; returns its exit code.
run_logged() {
    local log=$1 dir=$2
    shift 2
    echo "> $*" >>"$log"
    (cd "$dir" && "$@") >>"$log" 2>&1
}

# Seconds since boot: monotonic, unlike the wall clock, which WSL may step while a run is going.
now() {
    local up _
    read -r up _ </proc/uptime
    printf '%s' "$up"
}
seconds() { awk -v a="$1" -v b="$2" 'BEGIN { printf "%.1f", b - a }'; }

failed=0
total_start=$(now)
for name in "${selected[@]}"; do
    dir=$(dir_of "$name")
    log=$log_dir/$name.log
    echo "sanity: $name" >"$log"
    stage=build
    code=0
    build_start=$(now)
    # Every preset tree is <root>/_build/<folder name>/<preset> (the app's libs/_build too).
    if [[ ! -f $root/_build/$name/ninja-clang/CMakeCache.txt ]]; then
        stage=configure
        run_logged "$log" "$dir" cmake --preset ninja-clang
        code=$?
        ((code == 0)) && stage=build
    fi
    if ((code == 0)); then
        run_logged "$log" "$dir" cmake --build --preset ninja-clang
        code=$?
    fi
    build_end=$(now)
    test_time=0.0
    if ((code == 0)); then
        stage=tests
        tests=(--preset "$(preset_of "$name")" "${display_filter[@]}")
        if [[ -n $test_regex ]] && is_named "$name"; then
            tests+=(-R "$test_regex")
        elif [[ $name == dvv-build ]]; then
            tests+=(-R '^dvv_build\.')
        fi
        test_start=$(now)
        run_logged "$log" "$dir" ctest "${tests[@]}"
        code=$?
        test_time=$(seconds "$test_start" "$(now)")
    fi
    times="build $(seconds "$build_start" "$build_end") s, tests $test_time s"
    if ((code == 0)); then
        summary=$(grep 'tests passed' "$log" | tail -n 1 | sed 's/^[[:space:]]*//')
        printf 'PASS %-18s %s; %s\n' "$name" "$times" "$summary"
    else
        failed=$((failed + 1))
        printf 'FAIL %-18s %s failed (exit %d); %s; log: %s\n' "$name" "$stage" "$code" "$times" \
            "_build/sanity-linux/$name.log"
        tail -n 25 "$log" | sed 's/^/    /'
    fi
done
printf 'sanity: %d passed, %d failed in %s s\n' $((${#selected[@]} - failed)) "$failed" \
    "$(seconds "$total_start" "$(now)")"
exit $((failed > 0))
