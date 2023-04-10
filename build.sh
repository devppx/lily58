#!/bin/bash

start=$(date +%s.%N)

declare -a pids=()

# Set defaults variables
verbose=false
quiet=false
async=true
shields=("lily58_enc_left" "lily58_enc_right")
board="nrfmicro_13"
config_path='/workspaces/zmk-retry/lily58/config'
zmk_root_path='/workspaces/zmk-retry'
zmk_app_path='/workspaces/zmk-retry/app'
pristine_build_flag=''  #clean build flag
ui_config_flag=''
ERROR_BUILD_FAILED=9
timestamp=$(date +%Y-%m-%d_%H-%M-%S)

# Define usage message function
usage() {
    # Loop through the array and concatenate each element with |
    for item in "${shields[@]}"
    do
        shields_text+="$item|"
    done
    # Remove the last |
    shields_text=${shields_text%|}
dsds
    echo "Usage: $0 [-h] [-s SHIELD_NAME] [-s BOARD_NAME] [-v]"
    echo "  -h                      Display this help message"
    echo "  -s SHIELD_NAME          Pick a specific shields[]. Avaliable shields: $shields_text"
    echo "  -b BOARD_NAME           Board name, default value [$board]"
    echo "  -c USER_CONFIG_PATH     ZMK user config path"
    echo "  -u                      ZMK UI config"
    echo "  -v                      Verbose output (async build will be disabled)"
    echo "  -p                      Enable pristine build - clean build / do not use previous build caches"
    echo "  -r                      Build setting reset firmware for split keyboard halves unable to pair issue. Not compatible with -s option"
    echo "  -i                      Initialize build environment. Run it inside of ZMK docker container."
    echo "Place this script in zmk root folder."
    echo "By default, it will run async build for shield  board $board and $shields_text."
}

init_build_env() {
    cd $zmk_root_path
    apt-get update && apt-get install bc -y
    west init -l app
    west update
    # python3 -m pip install remarshal
    west zephyr-export
    mkdir build
    # git clone git@github.com:devppx/lily58.git 
    # npm install @actions/artifact     # not sure if it is necessary, delte?
}

# Parse command line options
while getopts "hs:c:vpi" opt; do
    case ${opt} in
        s )
            shields=($OPTARG)
            async=false
            ;;
        c )
            config_path="$OPTARG/config"
            ;;
        h )
            usage
            exit 0
            ;;
        v )
            verbose=true
            ;;
        \? )
            echo "Invalid option: -$OPTARG" 1>&2
            usage
            exit 1
            ;;
        p )
            pristine_build_flag='-p'
            ;;
        r )
            shields=("settings_reset")
            ;;
        i )
            init_build_env
            ;;
        u )
            ui_config_flag='-t menuconfig'
    esac
done
shift $((OPTIND -1))

mkdir -p $zmk_root_path/build
declare -A pid_shield
for shield in ${shields[@]}
do
    if [[ "$async" = true ]] && [[ "$verbose" = false ]] && [[ "$ui_config_flag" = '' ]]; then
        # echo start building $board - $shield
        # nohup sh -c "sleep 2 && echo 1 || echo 000 && echo 111" &
        nohup sh -c "cd $zmk_app_path && west build $pristine_build_flag -d build/$shield -b $board -- -DSHIELD=$shield -DZMK_CONFIG=$config_path && cp $zmk_app_path/build/$shield/zephyr/zmk.uf2 $zmk_root_path/build/$shield-$timestamp.u2" > $zmk_app_path/build/$shield/zmk-build.log 2>&1 &
        pid=$!
        # pids+=($pid)  
        pid_shield[$pid]=$shield # Link process ID and building shield
    else 
        sh -c "cd $zmk_app_path && west build $ui_config_flag $pristine_build_flag -d build/$shield -b $board -- -DSHIELD=$shield -DZMK_CONFIG=$config_path && cp $zmk_app_path/build/$shield/zephyr/zmk.uf2 $zmk_root_path/build/$shield-$timestamp.u2"
    fi
done

pids=("${!pid_shield[@]}")

if [[ "$async" = true ]]; then
    for pid in "${pids[@]}"; do
        echo "pid[$pid] - building ${pid_shield[$pid]}..."
    done
    while [[ "${#pids[@]}" -gt 0 ]]; do
        for pid_index in "${!pids[@]}"; do
            pid="${pids[$pid_index]}"
            # check if the process has finished
            if kill -0 "$pid" >/dev/null 2>&1; then
                continue
            else
                # remove the finished process from the array
                unset "pids[$pid_index]"
                if [ -f "$zmk_root_path/build/${pid_shield[$pid]}-$timestamp.u2" ]; then 
                    echo "pid[$pid] - building ${pid_shield[$pid]} finished successfully. U2 file is saved at: $zmk_root_path/build/${pid_shield[$pid]}-$timestamp.u2"
                else
                    echo "pid[$pid] - building ${pid_shield[$pid]} failed. Error log: $zmk_app_path/build/${pid_shield[$pid]}/zmk-build.log"
                fi
            fi
        done
        # wait a bit before checking again
        sleep 1
    done
fi

end=$(date +%s.%N)
echo "Timestamp: $timestamp | Time elapsed: $(echo $end '-' $start | bc) seconds"