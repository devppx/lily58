#!/bin/bash

start=$(date +%s.%N)

declare -a pids=()

# Set defaults variables
verbose=false
quiet=false
async=true
shields=("lily58_enc_left" "lily58_enc_right")
board="nrfmicro_13"
config_path='/workspaces/zmk/lily58/config'
zmk_root_path='/workspaces/zmk'
zmk_app_path='/workspaces/zmk/app'
pristine_build_flag=''  #clean build flag
ui_config_flag=''
# Define usage message function
usage() {
    # Loop through the array and concatenate each element with |
    for item in "${shields[@]}"
    do
        shields_text+="$item|"
    done
    # Remove the last |
    shields_text=${shields_text%|}

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
    west init -l app
    west update
    # python3 -m pip install remarshal
    west zephyr-export
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

timestamp=$(date +%Y-%m-%d_%H-%M-%S)
for shiled in ${shields[@]}
do
    if [[ "$async" = true ]] && [[ "$verbose" = false ]]; then
          nohup sh -c "cd $zmk_app_path && west build $pristine_build_flag -d build/$shiled -b $board -- -DSHIELD=$shiled -DZMK_CONFIG=$config_path && cp /workspaces/zmk/app/build/$shiled/zephyr/zmk.uf2 /workspaces/zmk/build/$shiled-$timestamp.u2" > $shiled\\build.log 2>&1 &
        pids+=($!)  # Add the process ID of the first command to the array
    else 
        sh -c "cd $zmk_app_path && west build $ui_config_flag $pristine_build_flag -d build/$shiled -b $board -- -DSHIELD=$shiled -DZMK_CONFIG=$config_path && cp /workspaces/zmk/app/build/$shiled/zephyr/zmk.uf2 /workspaces/zmk/build/$shiled-$timestamp.u2"
    fi
done

if [[ "$async" = true ]]; then
    for pid in "${pids[@]}"; do
        wait $pid
    done
fi

end=$(date +%s.%N)
echo "Timestamp: $timestamp | Time elapsed: $(echo "$end - $start" | bc) seconds "
