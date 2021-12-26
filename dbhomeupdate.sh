#!/bin/bash
# Oracle Platinum Patching, name=dbhomeupdate.sh, gc_version=18.09.27.14.30
#
# -E is needed so we can set/unset traps via a function
# pipefail is needed in order to return status from subshells
# extglob is needed so we can use regular expressions in case statements
# nullglob and dotglob are needed so we can check if directory is empty or not but we'll only set those when needed
set -E -o pipefail
shopt -s extglob 
shopt -u nullglob dotglob # Make sure these are off because they can break certain parts of the script
umask 0022
declare -r gc_myname=$(basename $0)
declare -r gc_version=18.09.27.14.30

#--------------------------------------------------------------------------------
# PROCEDURE    : _err_trap
# INPUT        :
# DESCRIPTION  : Trap unexpected errors
#------------------------------------------------------------------------------
function _err_trap
{
    local v_exit_status="$?" # This line has to be first!!
    local v_line=${BASH_LINENO[$((${#BASH_LINENO[@]} - 2))]}
    local v_command="${BASH_COMMAND:-unknown}"
    if [[ ${gv_trace:-1} -eq 1 ]]; then
        traceback 1 "${v_command}" "${v_exit_status}" "${v_line}" error
    fi
#    _showed_traceback=t
    if [ ! -z "${gv_runid_state}" ] && [[ ! " initialization checkTargetOOP checkSpaceOOP getHomeInfoOOP buildPatchLists " =~ ${gv_runid_state} ]]; then
        Log info "Check log file: ${gv_dbhomeupdate_log}" 1>&2
        Log info "Last saved state: ${gv_runid_state}" 1>&2
        Log info "To restart this run specify -r ${gv_runid}" 1>&2
    fi
    exit ${v_exit_status}
}

#--------------------------------------------------------------------------------
# PROCEDURE    : traceback
# INPUT        :
# DESCRIPTION  : Print call stack from unexpected error
#------------------------------------------------------------------------------
function traceback
{
    # Hide the traceback() call.
    local -i start=$(( ${1:-0} + 1 ))
    local -i end=${#BASH_SOURCE[@]}
    local -i i=0
    local -i j=0

    local v_time=$(date -u "${gc_date_format+%Y-%b-%d %H:%M:%S %Z}")

    if [ ! "${FUNCNAME[1]}" == "LogErrorAndExit" ] && [ ! "${FUNCNAME[1]}" == "LogErrorAndContinue" ]; then
        if [[ ${gv_orchestrator} -eq 0 ]]; then
            Log $5 "${bold}Unexpected error on line $4${gc_normal}" 1>&2
            Log $5 "${bold}Command: '$2' exited with exit code $3.${gc_normal}" 1>&2
        else
            Log $5 "Unexpected error on line $4" 1>&2
            Log $5 "Command: '$2' exited with exit code $3." 1>&2
        fi
    fi
    if [[ ${gv_orchestrator} -eq 0 ]]; then
        Log "       ${bold}Call stack (last called is first):${gc_normal}" 1>&2
    else
        Log "       ${bold}Call stack (last called is first):${gc_normal}" 1>&2
    fi
    Log "       ${bold}Call stack (last called is first):${gc_normal}" 1>&2
    for ((i=${start}; i < ${end}; i++)); do
        j=$(( $i - 1 ))
        local function="${FUNCNAME[$i]}"
        local file="$(basename ${BASH_SOURCE[$i]})"
        local line="${BASH_LINENO[$j]}"
        if [[ ${gv_orchestrator} -eq 0 ]]; then
            Log "       ${bold}${function}() in ${file} Line ${line}${gc_normal}" 1>&2
        else
            Log "       ${function}() in ${file} Line ${line}" 1>&2
        fi
    done
}


#--------------------------------------------------------------------------------
# PROCEDURE    : setTrap
# INPUT        :
# DESCRIPTION  : Enable error trapping
#------------------------------------------------------------------------------
setTrap()
{
    trap '_err_trap $LINENO' ERR
}

#--------------------------------------------------------------------------------
# PROCEDURE    : unsetTrap
# INPUT        :
# DESCRIPTION  : Disable error trapping
#------------------------------------------------------------------------------
unsetTrap()
{
    trap - ERR
}


#--------------------------------------------------------------------------------
# PROCEDURE    : printVersion
# DESCRIPTION  : Print the script version and release
#------------------------------------------------------------------------------
printVersion()
{
    local v_this_dir=$(dirname $(readlink -f $0))
    local v_parent_dir=$(dirname $v_this_dir)
    
    echo ""
    if [[ -e ${v_this_dir}/.patchutils-release ]]; then
        cat ${v_this_dir}/.patchutils-release
    elif [[ -e ${v_parent_dir}/.patchutils-release ]]; then
        cat ${v_parent_dir}/.patchutils-release
    fi
    echo ${gc_myname}, version ${gc_version}
    echo ""
}


#--------------------------------------------------------------------------------
# PROCEDURE    : parseOptions
# INPUT        :
# DESCRIPTION  : Parse command line options
#------------------------------------------------------------------------------
parseOptions()
{
    local key
    local v_rolling=""
    
    # Explicitly check for "-debug" on the command line and turn on debug ahead of time
    if [[ " $@ " =~ " --debug " ]] || [[ " $@ " =~ " -d " ]]; then
        gv_debug=1
        gv_trace=1
    fi
    # Explicitly check for "-g" on the command line 
    if [[ " $@ " =~ " --orchestrator " ]] || [[ " $@ " =~ " -g " ]]; then
        gv_orchestrator=1
    fi
    debug "$@"
    debug "number of command line options = $#"
    while [ $# -ge 1 ]
    do
    key="$1"
    unsetTrap
    [[ ${key} =~ ([[:digit:]]+) ]] # The home index we matched is contained in ${BASH_REMATCH[1]}
    setTrap
    case ${key} in
        -h@(${gc_home_index})|--dbhome@(${gc_home_index}))      # h0 and dbhome0 is always grid home. 
            if [ ${BASH_REMATCH[1]} -eq 0 ]; then # If h0 then ignore. We will programatically determine grid home location
                shift
                [[ $# -ge 1 ]] && [[ ${1:0:1} != "-" ]] && shift # if next argument does not start with "-" then shift again (ie, skip dir spec if supplied)
                continue
            fi  
            ga_directory[${gc_home[${BASH_REMATCH[1]}]}]=${2%/} # remove trailing slash, if any
            debug "ga_directory[${gc_home[${BASH_REMATCH[1]}]}] = ${ga_directory[${gc_home[${BASH_REMATCH[1]}]}]}"
            if [ ! -d ${2%/} ]; then
                LogErrorAndExit "${gc_home[${BASH_REMATCH[1]}]}: No such directory: ${ga_directory[${gc_home[${BASH_REMATCH[1]}]}]}"
            fi
            [ $# -gt 1 ] && shift
            ;;
        -h@(${gc_home_index})r|--dbhome@(${gc_home_index})-rollback)
            ga_rollbackOOB[${gc_home[${BASH_REMATCH[1]}]}]=$2
            debug "ga_rollbackOOB[${gc_home[${BASH_REMATCH[1]}]}] = ${ga_rollbackOOB[${gc_home[${BASH_REMATCH[1]}]}]}"
            [ $# -gt 1 ] && shift
            ;;
        -h@(${gc_home_index})p|--dbhome@(${gc_home_index})-patches)
            ga_applyOOB[${gc_home[${BASH_REMATCH[1]}]}]=$2
            debug "ga_applyOOB[${gc_home[${BASH_REMATCH[1]}]}] = ${ga_applyOOB[${gc_home[${BASH_REMATCH[1]}]}]}"
            [ $# -gt 1 ] && shift
            ;;
        -h@(${gc_home_index})b|--dbhome@(${gc_home_index})-bundle)
            ga_applyBP[${gc_home[${BASH_REMATCH[1]}]}]=$2
            debug "ga_applyBP[${gc_home[${BASH_REMATCH[1]}]}] = ${ga_applyBP[${gc_home[${BASH_REMATCH[1]}]}]}"
            [ $# -gt 1 ] && shift
            ;;
        -oop@(${gc_home_index})|--dbhome@(${gc_home_index})-outofplace)
            # Out of Place followed by optional directory
            # If the directory is not supplied we will automagically assign one
            # If directory is supplied then we need to account for possibility of different file system when checking space
            case "${2:0:1}" in
                "")
                    # No next argument
                    ga_targetOOP[${gc_home[${BASH_REMATCH[1]}]}]="" # Just put in the index with an empty string.
                    ;;
                "-")
                    # first char of $2 is "-" then no directory supplied
                    ga_targetOOP[${gc_home[${BASH_REMATCH[1]}]}]="" # Just put in the index with an empty string.
                    ;;
                "/")
                    # first char of $2 is "/" so we apparently got a directory
                    ga_targetOOP[${gc_home[${BASH_REMATCH[1]}]}]="$2" 
                    [ $# -gt 1 ] && shift
                    ;;
                *)
                    # otherwise invalid value specified for oop directory
                    LogErrorAndExit "Invalid value specified for ${key}"
            esac
            debug "Out-of-place switch detected for ${gc_home[${BASH_REMATCH[1]}]}"
            ;;
        -b|--backup-homes)
            # for future use
            debug "backup homes switch detected"
            ;;
        -?(non)rolling)
            if [ $1 == "-nonrolling" ]; then
                gv_rolling=0
                v_rolling=0
                debug "nonrolling switch detected"
            else
                gv_rolling=1
                v_rolling=1
                debug "rolling switch detected"
            fi
            ;;
        --recompile-config)
            gv_recompile_config=1
            debug "Recompile config.c flag detected"
            ;;
        -p|--patch-base)
            gv_patch_base=$2
            debug "gv_patch_base = ${gv_patch_base}"
            # Bug 26286231 - Reset variables that depend on gv_patch_base
            gv_dbhomeupdate_log=${gv_patch_logs}/dbhomeupdate.log
            gv_runid_logs=${gv_patch_logs}/${gv_runid}
            gv_patch_bp=${gv_patch_base}/BP
            gv_patch_oneoff=${gv_patch_base}/ONEOFF
            gv_patch_opatch=${gv_patch_base}/OPATCH
            gv_ocm_file=${gv_runid_logs}/ocm.rsp
            [ $# -gt 1 ] && shift
            ;;
        --oneoff-dir)
            gv_patch_oneoff=$2
            debug "gv_patch_oneoff = ${gv_patch_oneoff}"
            [ $# -gt 1 ] && shift
            ;;
        --switch?(-gridhome))
            gv_switch_gridhome=1
            case "${2:0:1}" in
                "")
                    # No next argument
                    ;;
                "-")
                    # first char of $2 is "-" then no directory supplied
                    ;;
                "/")
                    # first char of $2 is "/" so we apparently got a directory
                    gv_switch_gridhome_target=$2
                    [ $# -gt 1 ] && shift
                    ;;
                *)
                    # otherwise invalid value specified for grid clone directory
                    LogErrorAndExit "Invalid value specified for ${key}"
            esac
            debug "gv_switch_gridhome_target = ${gv_switch_gridhome_target}"
            ;;
#        --skipgrid)
#            gv_skipgrid=1
#            debug "gv_skipgrid switch detected"
#            ;;
        -r?(unid)|--runid)
            gv_cont_runid=$2
            debug "runid switch detected"
            debug "gv_cont_runid = ${gv_cont_runid}"
            [ $# -gt 1 ] && shift
            ;;
        -d?(ebug)|--debug)
            gv_debug=1
            gv_trace=1
            debug "debug switch detected"
            ;;
        -t?(race)|--trace)
            gv_trace=1
            debug "trace switch detected"
            ;;
        -v?(erify)|--verify)
            gv_verify=1
            debug "verify switch detected"
            ;;
        -g|--orchestrator)
            gv_orchestrator=1
            gv_orch_runid=$2
            [ $# -gt 1 ] && shift
            debug "orchestrator switch detected"
            debug "gv_orch_runid = ${gv_orch_runid}"
            ;;
        -q|--quiet)
            gv_quiet=1
            debug "quiet switch detected"
            ;;
        -a?(ll-homes)|--all-homes)
            gv_all_homes=1
            debug "all_homes switch detected"
            ;;
        -l?(spatches)|--lspatches)
            gv_lspatches=1
            # This option will bypass patching so set v_rolling flag
            v_rolling=0
            debug "lspatches switch detected"
            ;;
        -m?(d5sum)|--md5sum)
            gv_md5sum=1
            # This option will bypass patching so set v_rolling flag
            v_rolling=0
            debug "md5sum switch detected"
            ;;
        -V|--version)
            # display version and exit
            printVersion
            exit
            ;;
        -h?(elp)|--help) 
            usage
            exit 0
            ;;
        -s?(tep))
            gv_step=$2;
            [ $# -gt 1 ] && shift
            debug "step switch detected"
            debug "gv_step = ${gv_step}"
            ;;
        *)
            # Invalid option
            #usage
            LogErrorAndExit "Invalid option: ${key}"
            ;;
    esac
    shift
    done
    # Rolling/Non-rolling flag must be used when patching grid home
    if [[ " ${gv_options} " =~ " -h0" ]] || [[ " ${gv_options} " =~ " --dbhome0" ]]; then
        if [ -z ${v_rolling} ]; then
            LogErrorAndExit "Missing option: -rolling or -nonrolling"
        fi
    fi
    # if no grid options are supplied then skip anything grid related
    if [[ ! " ${gv_options} " =~ " -h0" ]] && [[ ! " ${gv_options} " =~ " --dbhome0" ]]; then
        debug "Setting gv_skipgrid=1"
        gv_skipgrid=1
    fi
    # Check option for switching grid home
    if [ "${ga_targetOOP[${gc_home[0]}]+isset}" ] && [ -n "${gv_switch_gridhome_target}" ]; then # If -oop0 specified then don't allow value for -switch-gridhome
        LogErrorAndExit "-switch-gridhome: Value not allowed in conjuction with -oop0"
    elif [ ! "${ga_targetOOP[${gc_home[0]}]+isset}" ] && [ ${gv_switch_gridhome} -eq 1 ] && [ -n "${gv_switch_gridhome_target}" ]; then # If -oop0 is not specified then -switch-gridhome must have a valid value and no other grid switches
        # Check if the home specified exists and appears to be a grid home
        if [ ! -d ${gv_switch_gridhome_target} ]; then
            LogErrorAndExit "Target grid home does not exist or is not a directory: ${gv_switch_gridhome_target}"
        elif [ ! -x ${gv_switch_gridhome_target}/bin/crsd.bin ]; then # make sure it appears to be a grid home
            LogErrorAndExit "Target grid home does not appear to be a grid home: ${gv_switch_gridhome_target}"
        else
            debug "Grid target ${gv_switch_gridhome_target} exists"
            debug "${gv_switch_gridhome_target} appears to be a grid home"
        fi
        if [ "${ga_applyBP[${gc_home[0]}]+isset}" ] || [ "${ga_applyOOB[${gc_home[0]}]+isset}" ] || [ "${ga_rollbackOOB[${gc_home[0]}]+isset}" ]; then
            LogErrorAndExit "--switch-gridhome not allowed in this context"
        fi
    fi
    # If any patches have been specified then make sure there is a corresponding home specified. We can skip home0 since it is always grid.
    for ((i=1; i<${#gc_home[@]}; i++))
    do
        if [ "${ga_rollbackOOB[${gc_home[$i]}]+isset}" ] || [ "${ga_applyOOB[${gc_home[$i]}]+isset}" ] || \
           [ "${ga_applyBP[${gc_home[$i]}]+isset}" ] || [ "${ga_targetOOP[${gc_home[$i]}]+isset}" ] && \
           [ ! "${ga_directory[${gc_home[$i]}]+isset}" ]
        then
            LogErrorAndExit "Missing option: -h$i"
        fi;
    done
    # If a home is set then make sure we have at least one option to operate on it. We can skip home0 since it is always grid.
    for ((i=1; i<${#gc_home[@]}; i++))
    do
        if [ "${ga_directory[${gc_home[$i]}]+isset}" ] && [ ! "${ga_rollbackOOB[${gc_home[$i]}]+isset}" ] && [ ! "${ga_applyOOB[${gc_home[$i]}]+isset}" ] && \
           [ ! "${ga_applyBP[${gc_home[$i]}]+isset}" ] && [ "${gv_lspatches}" -ne 1 ] && [ ! "${ga_targetOOP[${gc_home[$i]}]+isset}" ]
        then
            LogErrorAndExit "Nothing to do: ${gc_home[$i]}"
        fi;
    done
    # Don't allow both -r and -g
    if [ -n "${gv_orch_runid}" ] && [ -n "${gv_cont_runid}" ]; then
        LogErrorAndExit "Illegal option: Can't use -r and -g together"
    fi
    # Make sure we got a valid runid for orchestration
    if [ ${gv_orchestrator} -eq 1 ] && [ -z "${gv_orch_runid}" ]; then
        LogErrorAndExit "Missing runid value"
    fi
    if [ -n "${gv_orch_runid}" ] && [[ ! ${gv_orch_runid} =~ ^[0-9]{12}$ ]]; then
        LogErrorAndExit "Invalid runid value: ${gv_orch_runid}"
    fi
    # Make sure we got a valid runid for continuation
    if [ -n "${gv_cont_runid}" ] && [[ ! ${gv_cont_runid} =~ ^[0-9]{12}$ ]]; then
        LogErrorAndExit "Invalid runid value: ${gv_cont_runid}"
    fi
    # Make sure a step was passed when doing orchestration
    if [ ${gv_orchestrator} -eq 1 ] && [ -z "${gv_step}" ]; then 
        LogErrorAndExit "Mission option: -step"; 
    fi
    # Check if a valid step was passed
    if [ -n "${gv_step}" ] && [[ ! " ${gc_states[@]} " =~ " ${gv_step} " ]]; then 
        LogErrorAndExit "Invalid Step: ${gv_step}"; 
    fi
    # Make sure a runid was passed if there is a step passed
    if [ ${gv_orchestrator} -eq 0 ] && [ -n "${gv_step}" ]; then 
        LogErrorAndExit "Mission option: -g"; 
    fi

    debug   # This just prints a blank line in the debug output
}


#--------------------------------------------------------------------------------
# PROCEDURE    : usage
# INPUT        :
# DESCRIPTION  : Print usage info
#------------------------------------------------------------------------------
usage()
{
    echo ""
    echo ${gc_myname}, version ${gc_version}
    echo ""
    echo "Usage: $0 {options}"
    echo ""
    echo "Options:"
    echo "-h{${gc_home_index}} [<dbhome{${gc_home_index}}-directory>]"
    echo "--dbhome{${gc_home_index}} [<dbhome{${gc_home_index}}-directory>]"
    echo "      Specifies the Home directory to be patched."
    echo "      Ex, -h1 /u01/app/oracle/dbhome_1 -h2 /u01/app/oracle/dbhome_2"
    echo "      Note: dbhome0 is always the grid home and does not need to be specified."
    echo ""
    echo "-h{${gc_home_index}}r [<comma-separated-list-of-patches>]"
    echo "--dbhome{${gc_home_index}}-rollback [<comma-separated-list-of-patches>]"
    echo "      Comma separated (no spaces) list of patches to be rolled back."
    echo ""
    echo "-h{${gc_home_index}}p [<comma-separated-list-of-patches>]"
    echo "--dbhome{${gc_home_index}}-patches [<comma-separated-list-of-patches>]"
    echo "      Comma separated (no spaces) list of oneoff patches to be applied."
    echo ""
    echo "-h{${gc_home_index}}b [<bundle-patch>]"
    echo "--dbhome{${gc_home_index}}-bundle [<bundle-patch>]"
    echo "      Bundle patch number to be applied to a home."
    echo ""
    echo "-oop{${gc_home_index}} {<clone-target-directory>}"
    echo "--dbhome{${gc_home_index}}-outofplace  {<clone-target-directory>}"
    echo "      Home(s) to be patched out-of-place optionally followed by target home"
    echo "      directory. If no home is specified then one will be calculated based on"
    echo "      the source home."
    echo "      Note: If the target home already exists then it must be empty."
    echo ""
    echo "-rolling"
    echo "-nonrolling"
    echo "      Specifies is patching is being performs in serially or in parallel."
    echo ""
    echo "--switch-gridhome {<clone-target-directory>}"
    echo "      When used in conjunction with -oob0 then no target should be given. This"
    echo "      will cause a switch of the grid home after cloning."
    echo "      When used without -oob0 then you must specify the clone target. No other"
    echo "      arguments should be given. Performs a grid switch only."
    echo ""
#    echo "--skipgrid"
#    echo "Causes most actions with grid home to be skipped (ie, list patches). Should be used to avoid the warning message when no patches are to be applied or rolled back from grid home."
#    echo ""
    echo "--recompile-config"
    echo "      Recompiles the config.c file. Use this if there are mismatched binaries"
    echo "      across the cluster. ie, if one of more nodes has a different checksum for"
    echo "      the oracle executable."
    echo ""
    echo "--p [<patch-base-directory (default:/u01/patches)>]"
    echo "--patch-base [<patch-base-directory (default:/u01/patches)>]"
    echo "      Specifies the top level directory where patches are staged."
    echo ""
#    echo "--oneoff-dir          [<oneoff-directory (default:/u01/patches/ONEOFF)>]"
    echo ""
    echo "-r"
    echo "--runid"
    echo "      Used only when restarting a failed job. Picks up execution approximately"
    echo "      where it last stopped."
    echo ""
    echo "-d"
    echo "--debug"
    echo "      Displays various debugging messages to the screen. All debug messages are"
    echo "      always written to the master logfile (dbhomeupdate.log)."
    echo ""
    echo "-t"
    echo "--trace"
    echo "      Turned on by default when using -d flag. Enables call stack tracing when"
    echo "      an error occurs."
    echo ""
#    echo "-b    | --backup-homes"
    echo "-v"
    echo "--verify"
    echo "      aka precheck mode. Performs various prechecks on the patches passed in."
    echo ""
    echo "-a"
    echo "--all-homes"
    echo "      Lists all homes found in the central inventory file."
    echo ""
    echo "-l"
    echo "--lspatches"
    echo "      Display patches currently installed and exit."
    echo ""
    echo "-m"
    echo "--md5sum"
    echo "      Display md5sum for oracle executable."
    echo ""
    echo "-V"
    echo "--version"
    echo "      Displays the script version and exits."
    echo ""
    echo "-h"
    echo "--help"
    echo "      Displays this help message."
    echo ""
}


#--------------------------------------------------------------------------------
# PROCEDURE    : Log
# INPUT        :
# DESCRIPTION  : Log a message
#------------------------------------------------------------------------------
Log()
{

    local    v_time=$(date -u "${gc_date_format:-+%Y-%b-%d %H:%M:%S %Z}")
    local -u v_severity=$1
    local    v_severity_tag=""
    local    v_severity_tag_noesc=""
    local    v_message="$@"
    local    v_arg_cnt=$#
    
    case ${v_severity} in
        BLANK)
            v_severity_tag="          "
            v_severity_tag_noesc="          "
            ((v_arg_cnt--))
            shift
            ;;
        INFO)
            v_severity_tag="${gc_info}[INFO]${gc_normal}    "
            v_severity_tag_noesc="[INFO]    "
            ((v_arg_cnt--))
            shift
            ;;
        WARN)
            v_severity_tag="${gc_warn}[WARNING]${gc_normal} "
            v_severity_tag_noesc="[WARNING] "
            ((v_arg_cnt--))
            shift
            ;;
        PASS)
            v_severity_tag="${gc_pass}[PASS]${gc_normal}    "
            v_severity_tag_noesc="[PASS]    "
            ((v_arg_cnt--))
            shift
            ;;
        SUCCESS)
            v_severity_tag="${gc_success}[SUCCESS]${gc_normal} "
            v_severity_tag_noesc="[SUCCESS] "
            ((v_arg_cnt--))
            shift
            ;;
        FAIL)
            v_severity_tag="${gc_fail}[FAIL]${gc_normal}    "
            v_severity_tag_noesc="[FAIL]    "
            ((v_arg_cnt--))
            shift
            ;;
        ERROR)
            v_severity_tag="${gc_error}[ERROR]${gc_normal}   "
            v_severity_tag_noesc="[ERROR]   "
            ((v_arg_cnt--))
            shift
            ;;
        DEBUG)
            v_severity_tag="${gc_white}[DEBUG]${gc_normal}   "
            v_severity_tag_noesc="[DEBUG]   "
            ((v_arg_cnt--))
            shift
            ;;
        *)  # No severity passed
            v_severity="  " # 2 spaces -- you'll see why later
            ;;
    esac
    
    #print to the screen
    if [[ ${gv_orchestrator} -eq 0 ]]; then
        v_message=$(printf "${gc_bold}${v_time}${gc_normal} ${v_severity_tag} %b\n" "$*")
    else
        #v_message=$(printf "${v_time} ${v_severity_tag} %b\n" "$@"  | sed 's/\x1B[\[\(][0-9;(]*[BKm]//g')
        v_message=$(printf "${v_time} ${v_severity_tag_noesc} %b\n" "$*")
    fi
    if [ ${v_arg_cnt} -gt 0 ]; then
        if [[ ${gv_debug} -eq 1 ]]; then # print everything regardless of debug setting
            printf "${v_message}\n"
        elif [[ ${gv_debug} -ne 1 ]] && [ "${v_severity}" != "DEBUG" ]; then # don't print debug lines
            printf "${v_message}\n"
        fi
    elif [ ${gv_debug} -eq 1 ] || ([ ${gv_debug} -ne 1 ] && [ "${v_severity}" != "DEBUG" ]); then 
        printf "\n" 
    fi

    if [ -w ${gv_dbhomeupdate_log} ]; then # If the logfile is not writeable then we are not root or it doesn't exist (yet). This is so we can finish printing the error.
        # print to the logfile
        if [ ${v_arg_cnt} -gt 0 ]; then
            if [ "${v_severity}" != "  " ]; then v_severity=$(printf "%-10s" "[${v_severity}]"); fi
            v_message=$(printf "${v_time} ${v_severity} %b\n" "$*" | sed 's/\x1B[\[\(][0-9;(]*[BKm]//g')
            printf "${v_message}\n" >> ${gv_dbhomeupdate_log:-/dev/null}
        else
            printf "\n" >> ${gv_dbhomeupdate_log:-/dev/null}
        fi
    fi
    
}


#--------------------------------------------------------------------------------
# PROCEDURE    : debug
# INPUT        :
# DESCRIPTION  : Print debugging messages
#------------------------------------------------------------------------------
debug()
{
    local v_function=${FUNCNAME[1]} # The function that called debug
    local v_line
    
    if [ ${v_function} == "main" ]; then
        v_line=$(printf "%04d" ${BASH_LINENO[$((${#BASH_LINENO[@]} - 2))]})
    elif [ ${v_function} == "debugPrintArray" ]; then
        v_function=${FUNCNAME[2]}
        v_line=$(printf "%04d" ${BASH_LINENO[1]})
    else
        v_line=$(printf "%04d" ${BASH_LINENO[0]})
    fi
    if [ $# -ne 0 ]; then
        if [[ ${gv_orchestrator} -eq 0 ]]; then
            Log debug "${gc_debug}${v_function}(${v_line}): $@${gc_normal}"
        else
            Log debug "${v_function}(${v_line}): $@"
        fi
    else
        Log debug
    fi
}


#--------------------------------------------------------------------------------
# PROCEDURE    : debugPrintArray
# INPUT        :
# DESCRIPTION  : Print an array
#------------------------------------------------------------------------------
debugPrintArray()
{
    debug "$(declare -p $1 | awk '{print substr($0, index($0,$3))}')"
}


#--------------------------------------------------------------------------------
# PROCEDURE    : printAssociativeArray (obsolete)
# INPUT        :
# DESCRIPTION  : First attempt at printing an associative array. Abandoned after
#                coming up with much simpler debugPrintArray
#                Keeping as example of how to pass associative array as argument
#------------------------------------------------------------------------------
printAssociativeArray()
{
    # Call like this: printAssociativeArray "$(declare -p myarray1)"
    
    # eval string into a new assocociative array
    eval "local -A array="${1#*=}
    
    # The elements seem to be in reverse order (as in a stack)
    # so make an array of the indexes so we can iterate in reverse
    local -a index=(${!array[@]})

    printf "("
    for (( i=${#index[@]}-1 ; i>=0 ; i-- ))
    do
    printf "[%s]=\"%s\"" "${index[$i]}" "${array[${index[$i]}]}"
    if [ $i -gt 0 ]; then printf " "; fi
    done
    printf ")\n"
}


#--------------------------------------------------------------------------------
# PROCEDURE    : printFile
# INPUT        :
# DESCRIPTION  : Print a file line by line using Log procedure
#------------------------------------------------------------------------------
printFile()
{
    local v_file=$1
    local v_line
    
    while read v_line
    do
        Log blank ${v_line}
    done < ${v_file}
}


#--------------------------------------------------------------------------------
# PROCEDURE    : LogErrorAndContinue
# INPUT        :
# DESCRIPTION  : Log an error and continue
#------------------------------------------------------------------------------
LogErrorAndContinue()
{
    local v_exit_status="$?" # This line has to be first!!
    local v_command="${BASH_COMMAND:-unknown}"
    local v_line=${BASH_LINENO[$((${#BASH_LINENO[@]} - 2))]}

    local v_time=$(date -u "${gc_date_format}")

    if [ $# -ne 0 ]; then
        Log warn "Non-fatal error on line ${v_line}"
        Log warn "${bold}$@${gc_normal}"
        ((++gv_warnings))
        if [ ${gv_trace} -eq 1 ]; then
            traceback 1 "${v_command}" "${v_exit_status}" "${v_line}" warn
        fi
    else
        printf "\n"
    fi
}


#--------------------------------------------------------------------------------
# PROCEDURE    : LogErrorAndExit
# INPUT        :
# DESCRIPTION  : Log an error and exit
#------------------------------------------------------------------------------
LogErrorAndExit()
{
    local v_exit_status="$?" # This line has to be first!!
    local v_command="${BASH_COMMAND:-unknown}"
    local v_line=${BASH_LINENO[$((${#BASH_LINENO[@]} - 2))]}

    local v_time=$(date -u "${gc_date_format}")

    if [ $# -ne 0 ]; then
        Log error "Fatal error on line ${v_line}"
        Log error "${bold}$@${gc_normal}"
        if [ ${gv_trace} -eq 1 ]; then
            traceback 1 "${v_command}" "${v_exit_status}" "${v_line}" error
        fi
    else
        printf "\n"
    fi

    if [ ! -z "${gv_runid_state}" ] && [[ ! " initialization checkTargetOOP checkSpaceOOP getHomeInfoOOP buildPatchLists " =~ ${gv_runid_state} ]]; then
        Log info "Check log file: ${gv_dbhomeupdate_log}" 1>&2
        Log info "Last saved state: ${gv_runid_state}" 1>&2
        Log info "To restart this run specify -r ${gv_runid}" 1>&2
    fi
    exit 1
}


#--------------------------------------------------------------------------------
# PROCEDURE    : getGridHome
# DESCRIPTION  : 24743555  - Find the GI Home - use oratab as a last resort
#------------------------------------------------------------------------------
getGridHome()
{
	local v_oratab=/etc/oratab

    # Try init.ohasd for CRS_HOME location
    local v_gi_home=$(grep ^ORA_CRS_HOME /etc/init.d/init.ohasd 2>/dev/null | sort -u | awk -F "=" ' { print $2 } ')

    if [[ -f ${v_gi_home}/bin/oracle ]]
    then
        gv_grid_home="$(readlink -f ${v_gi_home})"
        debug "gv_grid_home: ${gv_grid_home}"
    else
        # Try ohasd for CRS_HOME if init.ohasd was not succesfull
        v_gi_home=$(grep ^ORA_CRS_HOME /etc/init.d/ohasd 2>/dev/null | sort -u | awk -F "=" '{ print $2 }')
        if [[ -f ${v_gi_home}/bin/oracle ]]
        then
            gv_grid_home="$(readlink -f ${v_gi_home})"
            debug "gv_grid_home: ${gv_grid_home}"
        else
            # Use oratab as a last resort
            v_gi_home=$(cat ${v_oratab} 2>/dev/null | grep -v "^#" | grep ^+ASM | head -1 | awk -F ":" '{ print $2 }')
            
            if [[ -f ${v_gi_home}/bin/oracle ]]
            then
                gv_grid_home="$(readlink -f ${v_gi_home})"
                debug "gv_grid_home: ${gv_grid_home}"
            else
               Log error "Cound not determine grid home"
                return 1
            fi
        fi
    fi

    if [[ -n ${gv_grid_home} ]]
    then
        if [[ -f ${gv_grid_home}/bin/oracle ]]
        then
           # Get the home owner
           gv_grid_owner=$(stat -c %U ${gv_grid_home}/bin/oracle 2>/dev/null)
           debug "gv_grid_owner: ${gv_grid_owner}"
        else
           Log error "No ${gv_grid_home}/bin/oracle binary found - this may not be the grid home"
           return 1
        fi
    else
        Log error "Could not determine grid home"
        return 1
    fi
    return 0
}


#--------------------------------------------------------------------------------
# PROCEDURE    : makeBundleStylesheet
# INPUT        :
# DESCRIPTION  : Create the sylesheet.xsl file used for parsing the bundle.xml file
#------------------------------------------------------------------------------
makeBundleStylesheet()
{
    local v_bundle_xsl=$1 # filename
    local v_home_id=$2 # if grid then crs, else rac
    local v_version
    local v_target

    debug "v_home_id = ${v_home_id}"
    debug "ga_version[$v_home_id]=${ga_version[$v_home_id]}"
    v_version=${ga_version[$v_home_id]%%.*} # We only need up to the first dot
    if [ ${gc_home[0]} == "${v_home_id}" ]; then
        v_target="crs"
    else
        v_target="rac"
    fi
    debug "v_target = ${v_target}"
    debug "v_version = ${v_version}"

    rm -f ${v_bundle_xsl}

    if [ ${v_version} -eq 12 ]; then
        debug "Making v12 stylesheet"
        cat >${v_bundle_xsl} <<EOF12
<?xml version="1.0"?>
<xsl:transform xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="2.0">
    <xsl:output method="text" indent="yes"/>
    <xsl:strip-space elements="*"/>
    <xsl:template match="/">
        <xsl:for-each select="//subpatch | //entity">
            <xsl:value-of select="@location" /> <xsl:text> </xsl:text>
        </xsl:for-each>
    </xsl:template>
</xsl:transform>
EOF12
    else
        debug "Making v11 stylesheet"
        cat >${v_bundle_xsl} <<EOF11
<?xml version="1.0"?>
<!--11g bundle stylesheet for crs-->
<xsl:transform xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="2.0">
    <xsl:output method="text" />
    <xsl:template match="/">
        <xsl:for-each select="//target">
            <xsl:if test="@type = '${v_target}'">
                <xsl:value-of select="../@location" /> <xsl:text> </xsl:text>
            </xsl:if>
        </xsl:for-each>
    </xsl:template>
</xsl:transform>
EOF11
    fi
    debug   # This just prints a blank line in the debug output
}


#--------------------------------------------------------------------------------
# PROCEDURE    : makeOOPStylesheet
# INPUT        :
# DESCRIPTION  : Create the sylesheet.xsl file used for parsing the inventory.xml file
#------------------------------------------------------------------------------
makeOOPStylesheet()
{
    local v_oop_xsl=$1 # filename
    local v_home_dir=$2 # directory we are looking up

    debug "v_home_dir = ${v_home_dir}"
    rm -f ${v_oop_xsl}

        debug "Making OOP stylesheet"
        cat >${v_oop_xsl} <<EOFOOP
<?xml version="1.0"?>
<!--11g bundle stylesheet for crs-->
<xsl:transform xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="2.0">
    <xsl:output method="text" />
    <xsl:template match="/">
      <xsl:for-each select="//HOME[@LOC='${v_home_dir}']">
      <xsl:choose>
         <xsl:when test="@REMOVED">
            <xsl:if test="@REMOVED!='T'">
                <xsl:value-of select="@NAME" /> <xsl:text>:</xsl:text>
                <xsl:for-each select="NODE_LIST/NODE">
                    <xsl:value-of select="@NAME" /> <xsl:text>,</xsl:text>
                </xsl:for-each>
                <xsl:text>;</xsl:text>
            </xsl:if>
         </xsl:when>
         <xsl:otherwise>
                <xsl:value-of select="@NAME" /> <xsl:text>:</xsl:text>
                <xsl:for-each select="NODE_LIST/NODE">
                    <xsl:value-of select="@NAME" /> <xsl:text>,</xsl:text>
                </xsl:for-each>
                <xsl:text>;</xsl:text>
         </xsl:otherwise>
      </xsl:choose>
        </xsl:for-each>
    </xsl:template>
</xsl:transform>
EOFOOP
    debug   # This just prints a blank line in the debug output
}


#--------------------------------------------------------------------------------
# PROCEDURE    : genResponseFile
# INPUT        :
# DESCRIPTION  : Generate an OCM Response file for use with opatch
#------------------------------------------------------------------------------
genResponseFile()
{
    local v_home_id=$1
    local v_emocmrsp=${ga_directory[$v_home_id]}/OPatch/ocm/bin/emocmrsp
    local v_home_opatch_version=$(${ga_directory[$v_home_id]}/OPatch/opatch version | awk '{print $3}') # version of opatch currently installed in this home

    [ -z "${v_home_id}" ] || [ -z "${ga_directory[$v_home_id]}" ] && return
    
    unsetTrap
    compareOpatchVersions ${v_home_opatch_version} "12.2.0.1.5"
    v_exit_status=$?
    setTrap
    case ${v_exit_status} in
        1|99) # 99 means major version is different, ie this is v11. 1 means we are v12 but less than 12.2.
            Log info "Generating OCM response file > ${gv_ocm_file}"

            /usr/bin/expect - <<EOF >/dev/null 2>&1
            spawn ${v_emocmrsp} -no_banner -output ${gv_ocm_file}
            expect {
              "Email address/User Name:"
              {
                send "\n"
                exp_continue
              }
              "Do you wish to remain uninformed of security issues*"
              {
                send "Y\n"
                exp_continue
              }
            }
EOF
                ;;
            0|2)
                debug ""
                touch ${gv_ocm_file}
                ;;
        esac

}


#--------------------------------------------------------------------------------
# PROCEDURE    : initPatchLists
# INPUT        :
# DESCRIPTION  : Initialize the patch lists
#------------------------------------------------------------------------------
initPatchLists()
{
    local v_home_id=$1
    local v_phbasefile=${gv_runid_logs}/${v_home_id}_phBaseFile
    local v_idfile=${gv_runid_logs}/${v_home_id}_idFile
    local v_found_patches=0

    [ -z "${v_home_id}" ] || [ -z "${ga_directory[$v_home_id]}" ] && return
    
    debug "v_home_id = ${v_home_id}"
    debug "ga_rollbackOOB[$v_home_id] = ${ga_rollbackOOB[$v_home_id]}"
    debug "ga_applyBP[$v_home_id]     = ${ga_applyBP[$v_home_id]}"
    debug "ga_applyOOB[$v_home_id]    = ${ga_applyOOB[$v_home_id]}"
    debug "ga_directory[$v_home_id]   = ${ga_directory[$v_home_id]}"

    if [ -z "${ga_rollbackOOB[$v_home_id]}" ] && [ -z "${ga_applyBP[$v_home_id]}" ] && [ -z "${ga_applyOOB[$v_home_id]}" ] && [ -n "${ga_directory[$v_home_id]}" ]; then
        if [[ "${v_home_id}" != "${gc_home[0]}" || ( "${v_home_id}" == "${gc_home[0]}" && ${gv_skipgrid} -eq 0 ) ]];then
            Log warn "No patches specified for ${v_home_id}"
            ((++gv_warnings))
        fi
        return
    fi

    # Bundle patch and oneoff patches use the same patchlist file
    if [ -n "${ga_applyBP[$v_home_id]}" ] || [ -n "${ga_applyOOB[$v_home_id]}" ] && [ -n "${ga_owner[$v_home_id]}" ]; then
        debug "Initializing ${v_phbasefile}"
        rm -f ${v_phbasefile}
        touch ${v_phbasefile}
        chown ${ga_owner[$v_home_id]}: ${v_phbasefile}
    fi
    if [ -n "${ga_rollbackOOB[$v_home_id]}" ] && [ -n "${ga_owner[$v_home_id]}" ]; then
        debug "Initializing ${v_idfile}"
        rm -f ${v_idfile}
        touch ${v_idfile}
        chown ${ga_owner[$v_home_id]}: ${v_idfile}
    fi

    if [ -n "${ga_rollbackOOB[$v_home_id]}" ] && [ -n "${ga_directory[$v_home_id]}" ]; then
        parseRollbackList  ${v_home_id}
    fi
    if [ -n "${ga_applyBP[$v_home_id]}" ] && [ -n "${ga_directory[$v_home_id]}" ]; then
        parseBundlePatch   ${v_home_id}
    fi
    if [ -n "${ga_applyOOB[$v_home_id]}" ] && [ -n "${ga_directory[$v_home_id]}" ]; then
        parseOneoffList    ${v_home_id}
    fi
    debug   # This just prints a blank line in the debug output
}


#--------------------------------------------------------------------------------
# PROCEDURE    : parseRollbackList
# INPUT        :
# DESCRIPTION  : Parse the list of patches to be rolled back
#------------------------------------------------------------------------------
parseRollbackList()
{
    local v_home_id=$1
    local v_patchlist=${gv_runid_logs}/${v_home_id}_idFile
    local v_exit_status
    local v_warnings=0
    local v_logfile=${gv_patch_logs}/prereq.out # This is just a temporary file. We'll overwrite it with each prereq check. ie, no "-a" on the tee command.
    
    [ -z "${v_home_id}" ] || [ -z "${ga_directory[$v_home_id]}" ] && return

    Log info "Analyzing patches to be rolled back from home ${ga_directory[$v_home_id]} > ${v_patchlist}"

    local IFS=","
    for v_patch in ${ga_rollbackOOB[$v_home_id]}
    do
            unsetTrap
            IFS=$' \t\n' debug su ${ga_owner[$v_home_id]} -c '"'"${ga_directory[$v_home_id]}/OPatch/opatch prereq CheckInstalledOneOffs -id ${v_patch} -oh ${ga_directory[$v_home_id]}"'"'
                               su ${ga_owner[$v_home_id]} -c "${ga_directory[$v_home_id]}/OPatch/opatch prereq CheckInstalledOneOffs -id ${v_patch} -oh ${ga_directory[$v_home_id]}" 2>&1 | /usr/bin/tee ${v_logfile} >>${gv_dbhomeupdate_log} 2>&1
            v_exit_status=${PIPESTATUS[0]}
            workAroundBug22969720 ${v_exit_status} ${v_logfile}
            v_exit_status=${PIPESTATUS[0]}
            debug CheckInstalledOneOffs ${v_patch}: Exit code: ${v_exit_status}
            if [ ${v_exit_status} -eq 0 ]; then # if ok then do CheckRollbackable
                if [ "$v_home_id" != "${gc_home[0]}" ]; then # Can't do CheckRollbackable on Grid Home unless it is down so skip
                    IFS=$' \t\n' debug su ${ga_owner[$v_home_id]} -c '"'"${ga_directory[$v_home_id]}/OPatch/opatch prereq CheckRollbackable -id ${v_patch} -oh ${ga_directory[$v_home_id]}"'"'
                    su ${ga_owner[$v_home_id]} -c "${ga_directory[$v_home_id]}/OPatch/opatch prereq CheckRollbackable -id ${v_patch} -oh ${ga_directory[$v_home_id]}" 2>&1 | /usr/bin/tee ${v_logfile} >>${gv_dbhomeupdate_log} 2>&1
                    v_exit_status=${PIPESTATUS[0]}
                    workAroundBug22969720 ${v_exit_status} ${v_logfile}
                    v_exit_status=${PIPESTATUS[0]}
                    debug CheckRollbackable ${v_patch}: Exit code: ${v_exit_status}
                fi
            fi
            if [ ${v_exit_status} -eq 0 ]; then
                printf "%s\n" ${v_patch} >> ${v_patchlist}
            else
                Log warn "CheckRollbackable: Return status: ${v_exit_status}: Patch ${v_patch} is not present in ${ga_directory[$v_home_id]}"
               ((++gv_warnings))
               ((++v_warnings))
            fi
            setTrap
    done
    if [ ${v_warnings} -eq 0 ]; then # we only produce warnings in this procedure so if no warnings all is good
        Log success "The following patches will be rolled back from ${ga_directory[$v_home_id]}"
        # cat ${v_patchlist}
        printFile ${v_patchlist}
    elif [ -s ${v_patchlist} ]; then # Check if anything was written to the patchlist
        Log warn "Some patches are not present in the installed patch list."
        Log info "Only the following patches will be rolled back from ${ga_directory[$v_home_id]}"
        # cat ${v_patchlist}
        printFile ${v_patchlist}
    else # file is empty
        Log warn "None of the patches are present in the installed patch list."
        Log info "No patches will be rolled back from ${ga_directory[$v_home_id]}"
        rm -f ${v_patchlist}
    fi
    debug   # This just prints a blank line in the debug output
}


#--------------------------------------------------------------------------------
# PROCEDURE    : parseBundlePatch
# INPUT        : bundle patch number and oracle home
# DESCRIPTION  : Parse a bundle patch bundle.xml file to get a list of applicable subpatches
#------------------------------------------------------------------------------
parseBundlePatch()
{
    local v_home_id=$1
    local v_bundle_xml=${gv_patch_bp}/${ga_applyBP[$v_home_id]}/bundle.xml
    local v_bundle_xsl=${gv_runid_logs}/sylesheet.xsl
    local v_patchlist=${gv_runid_logs}/${v_home_id}_phBaseFile
    local v_exit_status
    local v_warnings=0
    local v_errors=0
    local v_line
    local v_logfile=${gv_patch_logs}/prereq.out # This is just a temporary file. We'll overwrite it with each prereq check. ie, no "-a" on the tee command.
    local v_subpatch_count=0
    local v_version
    
    [ -z "${v_home_id}" ] && return
    
    touch ${v_patchlist}

    local IFS=","
    for v_patch in ${ga_applyBP[$v_home_id]}
    do

        v_subpatch_count=$(wc -l <${v_patchlist})
        
        Log info "Analyzing bundle patch ${ga_applyBP[$v_home_id]} for home ${ga_directory[$v_home_id]} > ${v_patchlist}"
    
        v_bundle_xml=${gv_patch_bp}/${v_patch}/bundle.xml
        
        [ ! -d "${gv_patch_bp}/${v_patch}" ] && LogErrorAndExit "Patch directory not found: ${gv_patch_bp}/${v_patch}"
    
        if [ ! -e "${v_bundle_xml}" ]; then
            LogErrorAndExit "bundle.xml not found: Patch ${v_patch} does not appear to be a bundle patch."
        else
            makeBundleStylesheet ${v_bundle_xsl} ${v_home_id}
            if [ ! -e "${v_bundle_xsl}" ]; then
                LogErrorAndExit "${v_bundle_xsl} not found!"
            fi
        fi
    
        debug v_bundle_xml=${v_bundle_xml}
        debug v_bundle_xsl=${v_bundle_xsl}
        debug ga_directory[${gc_home[0]}]=${ga_directory[${gc_home[0]}]}
        debug gv_patch_base=${gv_patch_base}
        debug 
    
        debug chown -R ${ga_owner[$v_home_id]}:${ga_group[$v_home_id]} ${gv_patch_bp}
        chown -R ${ga_owner[$v_home_id]}:${ga_group[$v_home_id]} ${gv_patch_bp} >/dev/null 2>&1
        
        debug "v_home_id = ${v_home_id}"
        debug "ga_version[$v_home_id]=${ga_version[$v_home_id]}"
        v_version=${ga_version[$v_home_id]%%.*} # We only need up to the first dot

        # PLAT-424 - Workaround for bug 27533600 - qopiprep.bat needs 755 permission and should be owned by Oracle Home user
        # PLAT-446 - Only need to check for v12 and higher
        if [[ ${v_version} -gt 11 ]] && [[ -x ${ga_directory[$v_home_id]}/QOpatch/qopiprep.bat ]]; then
            [[ ! $(stat -c %a ${ga_directory[$v_home_id]}/QOpatch/qopiprep.bat) -eq 755 ]] && chmod 755 ${ga_directory[$v_home_id]}/QOpatch/qopiprep.bat
            [[ ! $(stat -c %U ${ga_directory[$v_home_id]}/QOpatch/qopiprep.bat) = ${ga_owner[$v_home_id]} ]] && chown ${ga_owner[$v_home_id]} ${ga_directory[$v_home_id]}/QOpatch/qopiprep.bat
            [[ ! $(stat -c %U ${ga_directory[$v_home_id]}/QOpatch) = ${ga_owner[$v_home_id]} ]] && chown ${ga_owner[$v_home_id]} ${ga_directory[$v_home_id]}/QOpatch # check the owner of the directory too!
        fi
    
#        if [ ! -d "${gv_patch_bp}/${ga_applyBP[$v_home_id]}" ]; then
#            LogErrorAndExit "${gv_patch_bp}/${ga_applyBP[$v_home_id]} does not exist or is not a directory."
#        fi
    
        if [ -f "${v_bundle_xml}" ]; then
            CLASSPATHJ=${ga_directory[${gc_home[0]}]}/jdbc/lib/ojdbc.jar:${ga_directory[${gc_home[0]}]}/jlib/orai18n.jar CLASSPATH=.:${CLASSPATHJ}:${ga_directory[${gc_home[0]}]}/lib/xmlparserv2.jar:${ga_directory[${gc_home[0]}]}/lib/xsu12.jar:${ga_directory[${gc_home[0]}]}/lib/xml.jar \
            JAVA_HOME=${ga_directory[${gc_home[0]}]}/jdk LD_LIBRARY_PATH=${ga_directory[${gc_home[0]}]}/lib:${LD_LIBRARY_PATH} \
            PATH=${JAVA_HOME}/bin:$PATH ${ga_directory[${gc_home[0]}]}/bin/oraxsl  ${v_bundle_xml} ${v_bundle_xsl} | xargs printf "${gv_patch_bp}/${v_patch}/%s\n" | while read v_line
                do
                    unsetTrap
                    debug su ${ga_owner[$v_home_id]} -c '"'"${ga_directory[$v_home_id]}/OPatch/opatch prereq CheckForNoOpPatches -ph ${v_line} -oh ${ga_directory[$v_home_id]}"'"'
                    su ${ga_owner[$v_home_id]} -c "${ga_directory[$v_home_id]}/OPatch/opatch prereq CheckForNoOpPatches -ph ${v_line} -oh ${ga_directory[$v_home_id]}" 2>&1 | /usr/bin/tee ${v_logfile} >>${gv_dbhomeupdate_log} 2>&1
                    v_exit_status=${PIPESTATUS[0]}
                    workAroundBug22969720 ${v_exit_status} ${v_logfile}
                    v_exit_status=${PIPESTATUS[0]}
                    debug CheckForNoOpPatches ${v_line}: Exit code: ${v_exit_status}
                    if [ ${v_exit_status} -eq 0 ]; then # if ok then do CheckApplicable
                        if [ "$v_home_id" != "${gc_home[0]}" ]; then # Can't do CheckApplicable on Grid Home unless it is down so skip
                            debug su ${ga_owner[$v_home_id]} -c '"'"${ga_directory[$v_home_id]}/OPatch/opatch prereq CheckApplicable -ph ${v_line} -oh ${ga_directory[$v_home_id]}"'"'
                            su ${ga_owner[$v_home_id]} -c "${ga_directory[$v_home_id]}/OPatch/opatch prereq CheckApplicable -ph ${v_line} -oh ${ga_directory[$v_home_id]}" 2>&1 | /usr/bin/tee ${v_logfile} >>${gv_dbhomeupdate_log} 2>&1
                            v_exit_status=${PIPESTATUS[0]}
                            workAroundBug22969720 ${v_exit_status} ${v_logfile}
                            v_exit_status=${PIPESTATUS[0]}
                            debug CheckApplicable ${v_line}: Exit code: ${v_exit_status}
                        fi
                    fi
                    if [ ${v_exit_status} -eq 0 ]; then
                        echo ${v_line} >> ${v_patchlist}
                    else
                        case ${v_exit_status} in
                            135)
                                Log error "CheckForNoOpPatches: ${v_line}: Error 135: Argument Error: ${v_line}: Patch Location not valid or user '${ga_owner[$v_home_id]}' has no permission to access it. See ${gv_dbhomeupdate_log} for details."
                                ((++gv_errors))
                                ((++v_errors))
                                ;;
                            73)
                                Log error "CheckForNoOpPatches: ${v_line}: Error 73: PatchObject constructor: Input file does not exist. See ${gv_dbhomeupdate_log} for details."
                                ((++gv_errors))
                                ((++v_errors))
                                ;;
                            1)
                                # Log "CheckForNoOpPatches: Skipping ${v_line}: Patch not needed"
                                # This error is expected when analyzing bundle patch so we will ignore it
                                ;;
                            *)
                                LogErrorAndContinue "CheckForNoOpPatches: Error ${v_exit_status}: ${v_line}: Unknown error. Please collect ${gv_dbhomeupdate_log} and report the error."
                                ((++gv_errors))
                                ((++v_errors))
                                ;;
                        esac
                    fi
                    setTrap
                done
                if [[ ${v_subpatch_count} -eq $(wc -l <${v_patchlist}) ]];then # Check if found any applicable subpatches   
                    Log error "Bundle patch ${v_patch} is not applicable to home ${ga_directory[$v_home_id]}"
                    ((++gv_errors))
                fi
        else
            LogErrorAndExit "bundle.xml not found. Patch ${v_patch} does not appear to be a bundle patch."
        fi
    done

#    rm -f ${gv_patch_oneoff}/sylesheet.xsl
    if [ ${v_errors} -ne 0 ]; then
        Log error "Errors detected. See above."
    elif [ ${v_warnings} -ne 0 ]; then
        Log warn "Warnings detected. See above."
    elif [ ! -s ${v_patchlist} ]; then # Check if the patchlist file is zero size
        Log error "No bundle patches applicable to home ${ga_directory[$v_home_id]}"
        ((++gv_errors))
#        rm -f ${v_patchlist}
    else
        Log success "No issues detected with bundle patch "
        Log info "The following patches will be applied to home ${ga_directory[$v_home_id]} > ${v_patchlist}."
        # cat ${v_patchlist}
        printFile ${v_patchlist}
    fi
    debug   # This just prints a blank line in the debug output
}


#--------------------------------------------------------------------------------
# PROCEDURE    : parseBundlePatch_orig
# INPUT        : bundle patch number and oracle home
# DESCRIPTION  : Parse a bundle patch bundle.xml file to get a list of applicable subpatches
#------------------------------------------------------------------------------
parseBundlePatch_orig()
{
    local v_home_id=$1
    local v_bundle_xml=${gv_patch_bp}/${ga_applyBP[$v_home_id]}/bundle.xml
    local v_bundle_xsl=${gv_runid_logs}/sylesheet.xsl
    local v_patchlist=${gv_runid_logs}/${v_home_id}_phBaseFile
    local v_exit_status
    local v_warnings=0
    local v_errors=0
    local v_line
    local v_logfile=${gv_patch_logs}/prereq.out # This is just a temporary file. We'll overwrite it with each prereq check. ie, no "-a" on the tee command.
    
    [ -z "${v_home_id}" ] && return

    [ ! -d "${gv_patch_bp}/${ga_applyBP[$v_home_id]}" ] && LogErrorAndExit "Patch directory not found: ${gv_patch_bp}/${ga_applyBP[$v_home_id]}"

    if [ ! -e "${v_bundle_xml}" ]; then
        LogErrorAndExit "bundle.xml not found: Patch ${ga_applyBP[$v_home_id]} does not appear to be a bundle patch."
    else
        makeBundleStylesheet ${v_bundle_xsl} ${v_home_id}
        if [ ! -e "${v_bundle_xsl}" ]; then
            LogErrorAndExit "${v_bundle_xsl} not found!"
        fi
    fi

    Log info "Analyzing bundle patch ${ga_applyBP[$v_home_id]} for home ${ga_directory[$v_home_id]} > ${v_patchlist}"

    debug v_bundle_xml=${v_bundle_xml}
    debug v_bundle_xsl=${v_bundle_xsl}
    debug ga_directory[${gc_home[0]}]=${ga_directory[${gc_home[0]}]}
    debug gv_patch_base=${gv_patch_base}
    debug 

    debug chown -R ${ga_owner[$v_home_id]}:${ga_group[$v_home_id]} ${gv_patch_bp}
    chown -R ${ga_owner[$v_home_id]}:${ga_group[$v_home_id]} ${gv_patch_bp} >/dev/null 2>&1

    if [ ! -d "${gv_patch_bp}/${ga_applyBP[$v_home_id]}" ]; then
        LogErrorAndExit "${gv_patch_bp}/${ga_applyBP[$v_home_id]} does not exist or is not a directory."
    fi

    if [ -f "${v_bundle_xml}" ]; then
        CLASSPATHJ=${ga_directory[${gc_home[0]}]}/jdbc/lib/ojdbc.jar:${ga_directory[${gc_home[0]}]}/jlib/orai18n.jar CLASSPATH=.:${CLASSPATHJ}:${ga_directory[${gc_home[0]}]}/lib/xmlparserv2.jar:${ga_directory[${gc_home[0]}]}/lib/xsu12.jar:${ga_directory[${gc_home[0]}]}/lib/xml.jar \
        JAVA_HOME=${ga_directory[${gc_home[0]}]}/jdk LD_LIBRARY_PATH=${ga_directory[${gc_home[0]}]}/lib:${LD_LIBRARY_PATH} \
        PATH=${JAVA_HOME}/bin:$PATH ${ga_directory[${gc_home[0]}]}/bin/oraxsl  ${v_bundle_xml} ${v_bundle_xsl} | xargs printf "${gv_patch_bp}/${ga_applyBP[$v_home_id]}/%s\n" | while read v_line
            do
                unsetTrap
                debug su ${ga_owner[$v_home_id]} -c '"'"${ga_directory[$v_home_id]}/OPatch/opatch prereq CheckForNoOpPatches -ph ${v_line} -oh ${ga_directory[$v_home_id]}"'"'
                su ${ga_owner[$v_home_id]} -c "${ga_directory[$v_home_id]}/OPatch/opatch prereq CheckForNoOpPatches -ph ${v_line} -oh ${ga_directory[$v_home_id]}" 2>&1 | /usr/bin/tee ${v_logfile} >>${gv_dbhomeupdate_log} 2>&1
                v_exit_status=${PIPESTATUS[0]}
                workAroundBug22969720 ${v_exit_status} ${v_logfile}
                v_exit_status=${PIPESTATUS[0]}
                debug CheckForNoOpPatches ${v_line}: Exit code: ${v_exit_status}
                if [ ${v_exit_status} -eq 0 ]; then # if ok then do CheckApplicable
                    if [ "$v_home_id" != "${gc_home[0]}" ]; then # Can't do CheckApplicable on Grid Home unless it is down so skip
                        debug su ${ga_owner[$v_home_id]} -c '"'"${ga_directory[$v_home_id]}/OPatch/opatch prereq CheckApplicable -ph ${v_line} -oh ${ga_directory[$v_home_id]}"'"'
                        su ${ga_owner[$v_home_id]} -c "${ga_directory[$v_home_id]}/OPatch/opatch prereq CheckApplicable -ph ${v_line} -oh ${ga_directory[$v_home_id]}" 2>&1 | /usr/bin/tee ${v_logfile} >>${gv_dbhomeupdate_log} 2>&1
                        v_exit_status=${PIPESTATUS[0]}
                        workAroundBug22969720 ${v_exit_status} ${v_logfile}
                        v_exit_status=${PIPESTATUS[0]}
                        debug CheckApplicable ${v_line}: Exit code: ${v_exit_status}
                    fi
                fi
                if [ ${v_exit_status} -eq 0 ]; then
                    echo ${v_line} >> ${v_patchlist}
                else
                    case ${v_exit_status} in
                        135)
                            Log error "CheckForNoOpPatches: ${v_line}: Error 135: Argument Error: ${v_line}: Patch Location not valid or user '${ga_owner[$v_home_id]}' has no permission to access it. See ${gv_dbhomeupdate_log} for details."
                            ((++gv_errors))
                            ((++v_errors))
                            ;;
                        73)
                            Log error "CheckForNoOpPatches: ${v_line}: Error 73: PatchObject constructor: Input file does not exist. See ${gv_dbhomeupdate_log} for details."
                            ((++gv_errors))
                            ((++v_errors))
                            ;;
                        1)
                            # Log "CheckForNoOpPatches: Skipping ${v_line}: Patch not needed"
                            # This error is expected when analyzing bundle patch so we will ignore it
                            ;;
                        *)
                            LogErrorAndContinue "CheckForNoOpPatches: Error ${v_exit_status}: ${v_line}: Unknown error. Please collect ${gv_dbhomeupdate_log} and report the error."
                            ((++gv_errors))
                            ((++v_errors))
                            ;;
                     esac
                fi
                setTrap
            done
    else
        LogErrorAndExit "bundle.xml not found. Patch ${ga_applyBP[$v_home_id]} does not appear to be a bundle patch."
    fi
    rm -f ${gv_patch_oneoff}/sylesheet.xsl
    if [ ${v_errors} -ne 0 ]; then
        Log error "Errors detected. See above."
    elif [ ${v_warnings} -ne 0 ]; then
        Log warn "Warnings detected. See above."
    elif [ ! -s ${v_patchlist} ]; then # Check if the patchlist file is zero size
        Log error "Bundle patch ${ga_applyBP[$v_home_id]} is not applicable to home ${ga_directory[$v_home_id]}"
        ((++gv_errors))
        rm -f ${v_patchlist}
    else
        Log success "No issues detected with bundle patch "
        Log info "The following patches will be applied to home ${ga_directory[$v_home_id]} > ${v_patchlist}."
        # cat ${v_patchlist}
        printFile ${v_patchlist}
    fi
    debug   # This just prints a blank line in the debug output
}


#--------------------------------------------------------------------------------
# PROCEDURE    : parseOneoffList
# INPUT        :
# DESCRIPTION  : Parse the list of oneoff patches supplied
#------------------------------------------------------------------------------
parseOneoffList()
{
    local v_home_id=$1
    local v_patchlist=${gv_runid_logs}/${v_home_id}_phBaseFile
    local v_exit_status
    local v_warnings=0
    local v_errors=0
    local v_logfile=${gv_patch_logs}/prereq.out # This is just a temporary file. We'll overwrite it with each prereq check. ie, no "-a" on the tee command.

    [ -z "${v_home_id}" ] || [ -z "${ga_directory[$v_home_id]}" ] && return

    Log info "Analyzing patches to be applied to home ${ga_directory[$v_home_id]} > ${v_patchlist}"

    # Patches to be applied are assumed to be in the the ONEOFF directory under PATCH_BASE

    # (not implemented) If the patch directory does not exist then look for corresponding zip file and attempt to unzip it

    debug chown -R ${ga_owner[$v_home_id]}:${ga_group[$v_home_id]} ${gv_patch_oneoff}
    chown -R ${ga_owner[$v_home_id]}:${ga_group[$v_home_id]} ${gv_patch_oneoff} >/dev/null 2>&1

    local IFS=","
    for v_patch in ${ga_applyOOB[$v_home_id]}
    do
        unsetTrap
        if [ "${v_patch}" == "19215058" ]; then chmod u+w ${ga_directory[${v_home_id}]}/QOpatch/qopiprep.bat; fi # datapatch patch 19215058. Readme step 9
        IFS=" " debug su ${ga_owner[$v_home_id]} -c '"'"${ga_directory[${v_home_id}]}/OPatch/opatch prereq CheckForNoOpPatches -ph ${gv_patch_oneoff}/${v_patch} -oh ${ga_directory[$v_home_id]}"'"'
        su ${ga_owner[$v_home_id]} -c "${ga_directory[$v_home_id]}/OPatch/opatch prereq CheckForNoOpPatches -ph ${gv_patch_oneoff}/${v_patch} -oh ${ga_directory[$v_home_id]}" 2>&1 | /usr/bin/tee ${v_logfile} >>${gv_dbhomeupdate_log} 2>&1
            v_exit_status=${PIPESTATUS[0]}
            workAroundBug22969720 ${v_exit_status} ${v_logfile}
            v_exit_status=${PIPESTATUS[0]}
            debug CheckForNoOpPatches ${v_patch}}: Exit code: ${v_exit_status}
            if [ ${v_exit_status} -ne 0 ]; then
                case ${v_exit_status} in
                    135)
                        Log error "CheckForNoOpPatches: Error ${v_exit_status}: Argument Error: ${gv_patch_oneoff}/${v_patch}: Patch Location not valid. See ${gv_dbhomeupdate_log} for details."
                        ((++gv_errors))
                        ((++v_errors))
                        ;;
                    73)
                        Log error "CheckForNoOpPatches: Error ${v_exit_status}: PatchObject constructor: Input file does not exist. See ${gv_dbhomeupdate_log} for details."
                        ((++gv_errors))
                        ((++v_errors))
                        ;;
                    2)
                        Log error "CheckForNoOpPatches: Error ${v_exit_status}: Opatch inventory may be corrupted."
                        ((++gv_errors))
                        ((++v_errors))
                        ;;
                    1)
                        Log warn "CheckForNoOpPatches: Error ${v_exit_status}: Skipping ${gv_patch_oneoff}/${v_patch}: Patch not needed. See ${gv_dbhomeupdate_log} for details."
                        ((++gv_warnings))
                        ((++v_warnings))
                        ;;
                    *)
                        Log error "CheckForNoOpPatches: Error ${v_exit_status}: ${gv_patch_oneoff}/${v_patch}: Unknown error. Please collect ${gv_dbhomeupdate_log} and report the error."
                        ((++gv_errors))
                        ((++v_errors))
                        ;;
                 esac
            else # if ok then do CheckApplicable
                if [ "$v_home_id" != "${gc_home[0]}" ]; then # Can't do CheckApplicable on Grid Home unless it is down so skip
                    IFS=" " debug su ${ga_owner[$v_home_id]} -c '"'"${ga_directory[${v_home_id}]}/OPatch/opatch prereq CheckApplicable -ph ${gv_patch_oneoff}/${v_patch} -oh ${ga_directory[$v_home_id]}"'"'
                    su ${ga_owner[$v_home_id]} -c "${ga_directory[$v_home_id]}/OPatch/opatch prereq CheckApplicable -ph ${gv_patch_oneoff}/${v_patch} -oh ${ga_directory[$v_home_id]}" 2>&1 | /usr/bin/tee ${v_logfile} >>${gv_dbhomeupdate_log} 2>&1
                    v_exit_status=${PIPESTATUS[0]}
                    workAroundBug22969720 ${v_exit_status} ${v_logfile}
                    v_exit_status=${PIPESTATUS[0]}
                    debug CheckApplicable ${v_patch}: Exit code: ${v_exit_status}
                    if [ ${v_exit_status} -ne 0 ]; then
                        case ${v_exit_status} in
                            1)
                                Log error "CheckApplicable: Error ${v_exit_status} Patch ${v_patch} will fail to apply. See ${gv_dbhomeupdate_log} for details."
                                ((++gv_errors))
                                ((++v_errors))
                                ;;
                            *)
                                Log error "CheckApplicable: Error ${v_exit_status}: ${v_patch}: Unknown error. Please collect ${gv_dbhomeupdate_log} and report the error."
                                ;;
                        esac
                    else
                        printf "${gv_patch_oneoff}/%s\n" ${v_patch} >> ${v_patchlist}
                        checkPostApply ${gv_patch_oneoff} ${v_patch} ${v_home_id}
                    fi
                else
                    printf "${gv_patch_oneoff}/%s\n" ${v_patch} >> ${v_patchlist}
                    checkPostApply ${gv_patch_oneoff} ${v_patch} ${v_home_id}
                fi
            fi
            setTrap
    done
    if [ ${v_errors} -ne 0 ]; then
        Log error "Errors detected. See above."
    elif [ ${v_warnings} -ne 0 ]; then
        Log warn "Warnings detected. See above."
    elif [ ! -s ${v_patchlist} ]; then # Check if the patchlist file is zero size
        Log error "none of the patches specified are applicable to home ${ga_directory[$v_home_id]}"
        ((++gv_errors))
        rm -f ${v_patchlist}
    else
        Log success "No issues detected with oneoff patches "
        Log info "The following patches will be applied."
        # cat ${v_patchlist}
        printFile ${v_patchlist}
    fi
    debug   # This just prints a blank line in the debug output
}


#--------------------------------------------------------------------------------
# PROCEDURE    : showPatches
# INPUT        :
# DESCRIPTION  : Display lspatches for each home to screen
#------------------------------------------------------------------------------
showPatches()
{
    local v_home_id=$1

    [ -z "${v_home_id}" ] || [ -z "${ga_directory[$v_home_id]}" ] && return

    if [ -n "${ga_directory[$v_home_id]}" ]; then
        Log
        Log info "Patch listing for home ${ga_directory[$v_home_id]}\n"
        debug su ${ga_owner[$v_home_id]} -c '"'"${ga_directory[$v_home_id]}/OPatch/opatch lspatches -oh ${ga_directory[$v_home_id]}"'"'
        su ${ga_owner[$v_home_id]} -c "${ga_directory[$v_home_id]}/OPatch/opatch lspatches -oh ${ga_directory[$v_home_id]}"
        Log
    fi
    debug   # This just prints a blank line in the debug output
}


#--------------------------------------------------------------------------------
# PROCEDURE    : showMd5sum
# INPUT        :
# DESCRIPTION  : Display md5sum for each oracle executable to screen
#------------------------------------------------------------------------------
showMd5sum()
{
    local v_home_id=$1

    [ -z "${v_home_id}" ] || [ -z "${ga_directory[$v_home_id]}" ] && return

    if [ -n "${ga_directory[$v_home_id]}" ]; then
        Log
        Log info "md5sum for ${ga_directory[$v_home_id]}/bin/oracle"
        debug md5sum ${ga_directory[$v_home_id]}/bin/oracle
        md5sum ${ga_directory[$v_home_id]}/bin/oracle
        Log
    fi
    debug   # This just prints a blank line in the debug output
}


#--------------------------------------------------------------------------------
# PROCEDURE    : findOpatchZips
# INPUT        :
# DESCRIPTION  : Loop through the opatch directory to find all opatch zip files and record the version therein
#------------------------------------------------------------------------------
findOpatchZips() # This can be done up front in init section
{
    local v_version
    local v_file

    unsetTrap
    for v_file in ${gv_patch_opatch}/p6880880_*zip; do
        debug ${v_file}
        v_version=$(strings ${v_file} | grep OPATCH_VERSION | awk -F ":" '{print $2}')
        if [ $? -ne 0 ]; then continue; fi
        debug "Found file ${v_file} with version ${v_version}"
        ga_opatch_zips[${v_version%%.*}-file]=${v_file}    # associates zip file name to zip file version
        ga_opatch_zips[${v_version%%.*}-version]=${v_version}      # associates major version to zip file version
    done
    setTrap

}


#--------------------------------------------------------------------------------
# PROCEDURE    : compareOpatchVersions
# INPUT        : two opatch versions to compare in format a.b.c.d.e
# DESCRIPTION  : Compares two versions. returns 0 if v1=v2, 1 if v1<v2, 2 if v1>v2, 99 if major version does not match
#------------------------------------------------------------------------------
compareOpatchVersions()
{
    local -i ver1=$(numVer10 $1)
    local -i ver2=$(numVer10 $2)
    debug "ver1=$ver1"
    debug "ver2=$ver2"
        if [[ ${ver1} -eq 0 ]] && [[ ${ver2} -eq 0 ]]; then           # make sure we have a valid comparison
            debug "No versions supplied"
            return 99
        # compare only the first 2 digits
        elif [[ $((${ver1}/100000000)) -ne $((${ver2}/100000000)) ]]; then    # check major version matches
            debug "$((${ver1}/10000)) <> $((${ver2}/10000))"
            return 99
        elif [[ ${ver1} -lt ${ver2} ]]; then                          # v1<v2
            debug "${ver1[$i]} < ${ver2[$i]}"
            return 1
        elif [[ ${ver1} -gt ${ver2} ]]; then                          # v1>v2
            debug "${ver1} > ${ver2}"
            return 2
        else
            debug "${ver1} = ${ver2}"                                 # v1=v2
            return 0
        fi
}


#--------------------------------------------------------------------------------
# PROCEDURE    : updateOpatch
# INPUT        :
# DESCRIPTION  : 
#------------------------------------------------------------------------------
updateOpatch()
{
    local v_home_id=$1
    local v_home_opatch_version
    local v_min_opatch_version
    local v_zip_opatch_version
    local v_exit_status
    local -i i
    
    [ -z "${v_home_id}" ] || [ -z "${ga_directory[$v_home_id]}" ] && return

    if [ -n "${ga_directory[$v_home_id]}" ]; then
        Log
        Log info "Updating OPatch for home ${ga_directory[$v_home_id]}\n"
        debug ${ga_directory[$v_home_id]}/OPatch/opatch version
#        v_home_opatch_version=($(${ga_directory[$v_home_id]}/OPatch/opatch version | awk 'NR==1 {gsub(/\./," ",$3);print $3}')) # make an array out of the opatch version
        v_home_opatch_version=$(${ga_directory[$v_home_id]}/OPatch/opatch version | awk '{print $3}') # version of opatch currently installed in this home
        debugPrintArray ga_min_opatch
        debug "v_home_id=$v_home_id"
        debug "ga_version[$v_home_id]=${ga_version[$v_home_id]%%.*}"
        v_min_opatch_version=${ga_min_opatch[${ga_version[$v_home_id]%%.*}]} # min opatch version for this major version
        debug "v_home_opatch_version=${v_home_opatch_version}"
        debug "v_min_opatch_version=${v_min_opatch_version}"
        # first compare home version with zip file version
        v_zip_opatch_version=${ga_opatch_zips[${ga_version[$v_home_id]%%.*}-version]}
        v_zip_opatch_file=${ga_opatch_zips[${ga_version[$v_home_id]%%.*}-file]}
        debug "v_zip_opatch_file=${v_zip_opatch_file}"
        debug "v_zip_opatch_version=${v_zip_opatch_version}"
        if [ -n "${v_zip_opatch_version}" ]; then
            unsetTrap
            compareOpatchVersions ${v_home_opatch_version} ${v_zip_opatch_version}
            v_exit_status=$?
            setTrap
            case ${v_exit_status} in
                99)
                    Log error "Invalid OPatch version for this home"
                    ;;
                1)
                    Log info "Updating Opatch ..."
                    debug mv -f ${ga_directory[$v_home_id]}/OPatch ${ga_directory[$v_home_id]}/OPatch.$(date +%y%m%d%H%M%S)
                    mv -f ${ga_directory[$v_home_id]}/OPatch ${ga_directory[$v_home_id]}/OPatch.$(date +%y%m%d%H%M%S) >>${gv_dbhomeupdate_log} 2>&1
                    debug unzip ${v_zip_opatch_file} -d ${ga_directory[$v_home_id]}
                    unzip ${v_zip_opatch_file} -d ${ga_directory[$v_home_id]}  >>${gv_dbhomeupdate_log} 2>&1
                    debug chown -R ${ga_owner[$v_home_id]}:${ga_group[$v_home_id]} ${ga_directory[$v_home_id]}/OPatch
                    chown -R ${ga_owner[$v_home_id]}:${ga_group[$v_home_id]} ${ga_directory[$v_home_id]}/OPatch >>${gv_dbhomeupdate_log} 2>&1
                    ;;
                2)
                    Log pass "Opatch greater than version found in patch."
                    ;;
                0)
                    Log info "Opatch already updated."
                    ;;
            esac
        fi
        v_home_opatch_version=$(${ga_directory[$v_home_id]}/OPatch/opatch version | awk '{print $3}') # version of opatch currently installed in this home
        # second comparison after update
        unsetTrap
        compareOpatchVersions ${v_home_opatch_version} ${v_min_opatch_version}
        v_exit_status=$?
        setTrap
        case ${v_exit_status} in
            99)
                LogErrorAndExit "Invalid OPatch version for this home"
                ;;
            1)
                LogErrorAndExit "Opatch less than minimum required version."
                ;;
            2)
                Log pass "Opatch greater than minimum required version."
                ;;
            0)
                Log pass "Opatch matches minimum required version."
                ;;
        esac
    fi
    debug   # This just prints a blank line in the debug output
}


#--------------------------------------------------------------------------------
# PROCEDURE    : checkOpatch
# INPUT        :
# DESCRIPTION  : 
#------------------------------------------------------------------------------
checkOpatch()
{
    local v_home_id=$1
    local v_home_opatch_version
    local v_min_opatch_version
    local v_zip_opatch_version
    local v_exit_status
    local -i i
    
    [ -z "${v_home_id}" ] || [ -z "${ga_directory[$v_home_id]}" ] && return

    if [ -n "${ga_directory[$v_home_id]}" ]; then
        Log
        Log info "Checking OPatch for home ${ga_directory[$v_home_id]}\n"
        debug ${ga_directory[$v_home_id]}/OPatch/opatch version
#        v_home_opatch_version=($(${ga_directory[$v_home_id]}/OPatch/opatch version | awk 'NR==1 {gsub(/\./," ",$3);print $3}')) # make an array out of the opatch version
        v_home_opatch_version=$(${ga_directory[$v_home_id]}/OPatch/opatch version | awk '{print $3}') # version of opatch currently installed in this home
        debugPrintArray ga_min_opatch
        debug "v_home_id=$v_home_id"
        debug "ga_version[$v_home_id]=${ga_version[$v_home_id]%%.*}"
        v_min_opatch_version=${ga_min_opatch[${ga_version[$v_home_id]%%.*}]} # min opatch version for this major version
        debug "v_home_opatch_version=${v_home_opatch_version}"
        debug "v_min_opatch_version=${v_min_opatch_version}"
        unsetTrap
        compareOpatchVersions ${v_home_opatch_version} ${v_min_opatch_version}
        v_exit_status=$?
        setTrap
        case ${v_exit_status} in
            99)
                LogErrorAndExit "${v_home_id}: Invalid OPatch version."
                ;;
            1)

                if [ ${gv_verify} -eq 1 ]; then # This is a precheck run
                    ((++gv_warnings))
                    LogErrorAndContinue "${v_home_id}: Opatch less than minimum required version. Continuing with precheck session."
                else # This is a patch run
                    LogErrorAndExit "${v_home_id}: Opatch less than minimum required version."
                fi
                ;;
# Don't print anything for success. Just continue.
#            2)
#                Log pass "${v_home_id}: Opatch greater than minimum required version."
#                ;;
#            0)
#                Log pass "${v_home_id}: Opatch matches minimum required version."
#                ;;
        esac
    fi
    debug   # This just prints a blank line in the debug output
}


#--------------------------------------------------------------------------------
# PROCEDURE    : recordInventory
# INPUT        :
# DESCRIPTION  : Display lspatches for each home to screen
#------------------------------------------------------------------------------
recordInventory()
{
    local v_home_id=$1
    local v_run=$2

    [ -z "${v_home_id}" ] || [ -z "${ga_directory[$v_home_id]}" ] && return
    if [ -z "${v_run}" ]; then
        v_run="unknown"
    fi

    if [ -n "${ga_directory[$v_home_id]}" ]; then
        Log info "Collecting inventory listing ${v_run} patching for home ${ga_directory[$v_home_id]} > ${gv_runid_logs}/${v_home_id}_lsinventory.${v_run}"
        debug su ${ga_owner[$v_home_id]} -c '"'"${ga_directory[$v_home_id]}/OPatch/opatch lsinventory -detail -oh ${ga_directory[$v_home_id]}"'"'
        su ${ga_owner[$v_home_id]} -c "${ga_directory[$v_home_id]}/OPatch/opatch lsinventory -detail -oh ${ga_directory[$v_home_id]}"  >>${gv_runid_logs}/${v_home_id}_lsinventory.${v_run} 2>&1
    fi
    debug   # This just prints a blank line in the debug output
}


#--------------------------------------------------------------------------------
# PROCEDURE    : checkPostApply
# INPUT        :
# DESCRIPTION  : Looks for post apply script
#------------------------------------------------------------------------------
checkPostApply()
{
    local v_patch_directory=$1
    local v_patch_number=$2
    local v_home_id=$3
    local v_postlist=""

    if [ -e "${v_patch_directory}/${v_patch_number}/postinstall.sql" ]; then
        Log info "Patch ${v_patch_number} has a post apply script!"
        ((++gv_post_installs))
        v_postlist=${ga_postInstall[${v_home_id}]}
        if [ -z ${v_postlist} ]; then
            ga_postInstall[${v_home_id}]="${v_patch_number}"
        else
            ga_postInstall[${v_home_id}]="${v_postlist},${v_patch_number}"
        fi
        debug "Post install list for '${v_home_id}' home is ${ga_postInstall[${v_home_id}]}"
    fi
    debug   # This just prints a blank line in the debug output
}



#--------------------------------------------------------------------------------
# PROCEDURE    : stopGIStack
# INPUT        :
# DESCRIPTION  : Stop grid infrastructure, if required
#------------------------------------------------------------------------------
stopGIStack()
{
    local v_svc_cnt
    local v_exit_status
    
    # Get current status of GI
    unsetTrap
    v_svc_cnt=$(${ga_directory[${gc_home[0]}]}/bin/crsctl check crs | egrep -a -s -c 'CRS-4638|CRS-4537|CRS-4529|CRS-4533')
    setTrap
    debug "v_svc_cnt = ${v_svc_cnt}"
    
    case ${v_svc_cnt} in
        0)
            debug "Stack is down"
            ;;
        [1..3])
            debug "Stack is partially up"
            ;;
        4)  
            debug "Stack is up"
            ;;
        *)
            debug "Something is wrong!"
            ;;
    esac
    
    if [ ${v_svc_cnt} -gt 0 ]; then
        unsetTrap
        # Record cluster status to a log file before stopping
        # Send to both dbhomeupdate.log and also to a new log file for later use
        rm -f ${gv_runid_logs}/${gc_home[0]}_gistatus.before
        debug "${ga_directory[${gc_home[0]}]}/bin/crsctl status resource -t -init"
        ${ga_directory[${gc_home[0]}]}/bin/crsctl status resource -t -init 2>&1 | /usr/bin/tee -a ${gv_dbhomeupdate_log} >${gv_runid_logs}/${gc_home[0]}_gistatus.before
        debug "${ga_directory[${gc_home[0]}]}/bin/crsctl status resource -t"
        ${ga_directory[${gc_home[0]}]}/bin/crsctl status resource -t       2>&1 | /usr/bin/tee -a ${gv_dbhomeupdate_log} >>${gv_runid_logs}/${gc_home[0]}_gistatus.before
        
        # Stop cluster first
        debug "${ga_directory[${gc_home[0]}]}/bin/crsctl stop cluster"
        ${ga_directory[${gc_home[0]}]}/bin/crsctl stop cluster >>${gv_dbhomeupdate_log} 2>&1
        v_exit_status=${PIPESTATUS[0]}
        
        # We don't really care too much at this point if the 'stop cluster' failed because we are going to do a 'stop crs -f' next
        
        debug "${ga_directory[${gc_home[0]}]}/bin/crsctl stop crs -f"
        ${ga_directory[${gc_home[0]}]}/bin/crsctl stop crs -f >>${gv_dbhomeupdate_log} 2>&1
        v_exit_status=${PIPESTATUS[0]}

        if [[ ${v_exit_status} -ne 0 ]]; then
            LogErrorAndExit "CRS shutdown completed with failures."
        fi
        
        # Verify that the cluster is down
        v_svc_cnt=$(${ga_directory[${gc_home[0]}]}/bin/crsctl check crs | egrep -a -s -c 'CRS-4638|CRS-4537|CRS-4529|CRS-4533')
        debug "v_svc_cnt = ${v_svc_cnt}"
        
        if [[ ${v_svc_cnt} -ne 0 ]]; then
            LogErrorAndExit "CRS did not shutdown."
        fi
        setTrap
    fi
    
    debug   # This just prints a blank line in the debug output
}


#--------------------------------------------------------------------------------
# PROCEDURE    : numVer
# DESCRIPTION  : Convert version string into a 6 digit integer for use in comparisons
#              : Return 0 and an error status if missing or invalid version string
#              : Valid version is in the format dd.d[.d[.d[.d[.dddddd]]]]
#------------------------------------------------------------------------------
numVer()
{
    # Make sure that we have a valid version number string
    # This is basically dd.d[.d[.d[.d[.dddddd]]]]
    # The re can probably be optimized more but I couldn't find an easy way because bash re's are limited
    # If the version number is valid then take only the first 5 fields. 
    # Remove all of the dots.
    # If less than 6 chars then right pad with 0's
    re='^([0-9]{2})(([.][0-9]){1,4}$|([.][0-9]){4}[.][0-9]{6}$)'
    if [[ -z $1 ]]
    then
        echo 0
        return 1
    elif [[ ! $1 =~ $re ]] ; then
        echo 0
        return 1
    else
        echo $1 | cut -d \. -f1-5 | sed -e "s/\.//g" -e :a -e 's/^.\{1,5\}$/&0/;ta'
        return 0
    fi
}


#--------------------------------------------------------------------------------
# PROCEDURE    : numVer10
# DESCRIPTION  : Convert version string into a 10 digit integer for use in comparisons
#              : Return 0 and an error status if missing or invalid version string
#              : Valid version is in the format dd.dd[.dd[.dd[.dd[.dddddd]]]]
#------------------------------------------------------------------------------
numVer10()
{
    # Make sure that we have a valid version number string
    # This is basically dd.d[.d[.d[.d[.dddddd]]]]
    # The re can probably be optimized more but I couldn't find an easy way because bash re's are limited
    # If the version number is valid then take only the first 5 fields. 
    # Remove all of the dots.
    # If less than 6 chars then right pad with 0's

    local -i num=0
    local re='^([0-9]{2})(([.][0-9]{1,2}){1,4}$|([.][0-9]{1,2}){4}[.][0-9]{6}$)'
    if [[ -z $1 ]]
    then
        echo ${num}
        return 1
    elif [[ ! $1 =~ $re ]] ; then
        echo ${num}
        return 1
    else
        local numArray
        IFS='.' read -ra numArray <<< "$1"
        num=$(printf "%02d%02d%02d%02d%02d" ${numArray[0]} ${numArray[1]} ${numArray[2]} ${numArray[3]} ${numArray[4]})
        echo ${num}
        return 0
    fi
}


#--------------------------------------------------------------------------------
# PROCEDURE    : stopGIStackForPatching
# INPUT        :
# DESCRIPTION  : Stop grid infrastructure for patching, if required
#------------------------------------------------------------------------------
stopGIStackForPatching()
{
    local v_svc_cnt
    local v_exit_status
    local v_cluster_version=$(numVer ${ga_version[${gc_home[0]}]})
    local v_cluster_major_version=${ga_version[${gc_home[0]}]%%.*} # We only need up to the first dot
    local v_option=""
    local v_rootcrs_command=""
    
    Log info "Stopping GI for patching..."
    # Get current status of GI
    unsetTrap
    v_svc_cnt=$(${ga_directory[${gc_home[0]}]}/bin/crsctl check crs | egrep -a -s -c 'CRS-4638|CRS-4537|CRS-4529|CRS-4533')
    setTrap
    debug "v_svc_cnt = ${v_svc_cnt}"
    
    case ${v_svc_cnt} in
        0)
            debug "Stack is down"
            ;;
        [1..3])
            debug "Stack is partially up"
            ;;
        4)  
            debug "Stack is up"
            ;;
        *)
            debug "Something is wrong!"
            ;;
    esac
    
    unsetTrap
    if [ ${v_svc_cnt} -gt 0 ]; then
        # Record cluster status to a log file before stopping
        # Send to both dbhomeupdate.log and also to a new log file for later use
        rm -f ${gv_runid_logs}/${gc_home[0]}_gistatus.before
        touch ${gv_runid_logs}/${gc_home[0]}_gistatus.before
        debug "${ga_directory[${gc_home[0]}]}/bin/crsctl status resource -t -init"
        ${ga_directory[${gc_home[0]}]}/bin/crsctl status resource -t -init 2>&1 | /usr/bin/tee -a ${gv_dbhomeupdate_log} >${gv_runid_logs}/${gc_home[0]}_gistatus.before
        debug "${ga_directory[${gc_home[0]}]}/bin/crsctl status resource -t"
        ${ga_directory[${gc_home[0]}]}/bin/crsctl status resource -t       2>&1 | /usr/bin/tee -a ${gv_dbhomeupdate_log} >>${gv_runid_logs}/${gc_home[0]}_gistatus.before
        
        # Stop cluster first
        debug "${ga_directory[${gc_home[0]}]}/bin/crsctl stop cluster"
        ${ga_directory[${gc_home[0]}]}/bin/crsctl stop cluster 2>&1 | /usr/bin/tee -a ${gv_dbhomeupdate_log} >/dev/null 2>&1
        v_exit_status=${PIPESTATUS[0]}
        # We don't really care too much at this point if the 'stop cluster' failed
    fi
        
        
    if [ "${v_cluster_major_version}" == "11" ]; then
        v_option="-unlock"   # v11 option for rootcrs.pl
    elif [ "${v_cluster_major_version}" == "12" ]; then
        v_option="-prepatch" # v12 option for rootcrs.pl
        if [ ${gv_rolling} -eq 0 ]; then
            v_option+=" -nonrolling"
        fi
    else
        LogErrorAndExit "Could not determine GI version."
    fi

    if [[ ${v_cluster_version} -lt 122000 ]]; then
        v_rootcrs_command=${ga_directory[${gc_home[0]}]}/crs/install/rootcrs.pl
    else
        v_rootcrs_command=${ga_directory[${gc_home[0]}]}/crs/install/rootcrs.sh
    fi
    
    debug "${v_rootcrs_command} ${v_option}"
    ${v_rootcrs_command} ${v_option} 2>&1 | /usr/bin/tee -a ${gv_dbhomeupdate_log} >/dev/null 2>&1
    v_exit_status=${PIPESTATUS[0]}

    if [[ ${v_exit_status} -ne 0 ]]; then
        LogErrorAndExit "CRS shutdown completed with failures."
    fi
    
    # Verify grid home is unlocked
    local v_owner=$(stat -c %U ${ga_directory[${gc_home[0]}]})
    debug "Grid Check: v_owner = ${v_owner}"
    if [ "${v_owner}" != ${ga_owner[${gc_home[0]}]} ]; then
        LogErrorAndExit "GI is not unlocked."
    else
        Log success "GI is unlocked."
    fi

    # Verify that the cluster is down
    v_svc_cnt=$(${ga_directory[${gc_home[0]}]}/bin/crsctl check crs | egrep -a -s -c 'CRS-4638|CRS-4537|CRS-4529|CRS-4533')
    debug "v_svc_cnt = ${v_svc_cnt}"
    
    if [[ ${v_svc_cnt} -ne 0 ]]; then
        LogErrorAndExit "GI did not shutdown."
    else
        Log success "GI shutdown successfully."
    fi
    setTrap

    debug   # This just prints a blank line in the debug output
}


#--------------------------------------------------------------------------------
# PROCEDURE    : startGIStack
# INPUT        :
# DESCRIPTION  : Start grid infrastructure, if required
#------------------------------------------------------------------------------
startGIStack()
{
    local v_svc_cnt
    local v_exit_status
    local v_cluster_version=$(numVer ${ga_version[${gc_home[0]}]})
    local v_cluster_major_version=${ga_version[${gc_home[0]}]%%.*} # We only need up to the first dot
    local v_options=""
    local -i v_counter
    
    # Get current status of GI
    unsetTrap
    v_svc_cnt=$(${ga_directory[${gc_home[0]}]}/bin/crsctl check crs | egrep -a -s -c 'CRS-4638|CRS-4537|CRS-4529|CRS-4533')
    setTrap
    debug "v_svc_cnt = ${v_svc_cnt}"
    
    case ${v_svc_cnt} in
        0)
            debug "GI Stack is down"
            ;;
        [1..3])
            debug "GI Stack is partially up"
            ;;
        4)  
            debug "GI Stack is up"
            Log info "GI Stack is already up."
            return
            ;;
        *)
            debug "Something is wrong!"
            ;;
    esac
    
    if [ ${v_svc_cnt} -eq 0 ]; then
        # if service count is 0 then stack is completely down
        unsetTrap

        if [ "${v_cluster_major_version}" == "12" ]; then
            v_options="-wait" # v12 option to display all startup messages
        fi
        
        if [[ ${v_cluster_version} -lt 122000 ]]; then
            v_rootcrs_command=${ga_directory[${gc_home[0]}]}/crs/install/rootcrs.pl
        else
            v_rootcrs_command=${ga_directory[${gc_home[0]}]}/crs/install/rootcrs.sh
        fi
        
        debug "${ga_directory[${gc_home[0]}]}/bin/crsctl start crs ${v_options}"
        ${ga_directory[${gc_home[0]}]}/bin/crsctl start crs ${v_options} 2>&1 | /usr/bin/tee -a ${gv_dbhomeupdate_log} >/dev/null 2>&1
        v_exit_status=${PIPESTATUS[0]}
        
        if [[ ${v_exit_status} -ne 0 ]]; then
            LogErrorAndExit "GI stack startup completed with errors."
            exit 1
        fi
        
        # wait up to 15 minutes for cluster to startup
        v_counter=0
        while [ ${v_counter} -lt 15 ]
        do
            v_svc_cnt=$(${ga_directory[${gc_home[0]}]}/bin/crsctl check crs | egrep -a -s -c 'CRS-4638|CRS-4537|CRS-4529|CRS-4533')
            debug "(${v_counter}/15): Waiting for GI stack to start... v_svc_cnt = ${v_svc_cnt}"
            
            if [ ${v_svc_cnt} -eq 4 ]; then break; fi
            
            sleep 60
        
            ((${v_counter}++))

        done
        
        if [[ ${v_svc_cnt} -ne 4 ]]; then
            LogErrorAndExit "CRS did not startup after 15 minutes."
            exit 1
        else
            Log success "GI stack successfully started"
        fi
        setTrap
    else
        # HAS must already be running so we need to do a 'start cluster' instead
        unsetTrap

        debug "${ga_directory[${gc_home[0]}]}/bin/crsctl start cluster"
        ${ga_directory[${gc_home[0]}]}/bin/crsctl start cluster 2>&1 | /usr/bin/tee -a ${gv_dbhomeupdate_log} >/dev/null 2>&1
        v_exit_status=${PIPESTATUS[0]}
        
        if [[ ${v_exit_status} -ne 0 ]]; then
            LogErrorAndExit "GI stack startup completed with errors."
            exit 1
        fi
        
        # wait up to 15 minutes for cluster to startup
        ${v_counter}=0
        while [ ${v_counter} -lt 15 ]
        do
            v_svc_cnt=$(${ga_directory[${gc_home[0]}]}/bin/crsctl check crs | egrep -a -s -c 'CRS-4638|CRS-4537|CRS-4529|CRS-4533')
            debug "(${v_counter}/15): $v_svc_cnt = ${v_svc_cnt}"
            
            if [ ${v_svc_cnt} -eq 4 ]; then break; fi
            
            sleep 60
        
            ((${v_counter}++))

        done
        
        if [[ ${v_svc_cnt} -ne 4 ]]; then
            LogErrorAndExit "CRS did not startup after 15 minutes."
            exit 1
        fi
        setTrap
    fi
    
    # Record cluster status to a log file after starting
    # Send to both dbhomeupdate.log and also to a new log file for later use
    rm -f ${gv_runid_logs}/${gc_home[0]}_gistatus.after
    touch ${gv_runid_logs}/${gc_home[0]}_gistatus.after
    debug "${ga_directory[${gc_home[0]}]}/bin/crsctl status resource -t -init"
    ${ga_directory[${gc_home[0]}]}/bin/crsctl status resource -t -init 2>&1 | /usr/bin/tee -a ${gv_dbhomeupdate_log} >${gv_runid_logs}/${gc_home[0]}_gistatus.after
    debug "${ga_directory[${gc_home[0]}]}/bin/crsctl status resource -t"
    ${ga_directory[${gc_home[0]}]}/bin/crsctl status resource -t       2>&1 | /usr/bin/tee -a ${gv_dbhomeupdate_log} >>${gv_runid_logs}/${gc_home[0]}_gistatus.after
        
    debug   # This just prints a blank line in the debug output
}


#--------------------------------------------------------------------------------
# PROCEDURE    : startGIStackAfterPatching
# INPUT        :
# DESCRIPTION  : Start grid infrastructure, if required
#------------------------------------------------------------------------------
startGIStackAfterPatching()
{
    local v_svc_cnt
    local v_exit_status
    local v_cluster_version=$(numVer ${ga_version[${gc_home[0]}]})
    local v_cluster_major_version=${ga_version[${gc_home[0]}]%%.*} # We only need up to the first dot
    local v_options=""
    local -i v_counter
    local v_owner
    
    Log info "Restarting GI after patching..."
    # Get current status of GI
    unsetTrap
    v_svc_cnt=$(${ga_directory[${gc_home[0]}]}/bin/crsctl check crs | egrep -a -s -c 'CRS-4638|CRS-4537|CRS-4529|CRS-4533')
    setTrap
    debug "v_svc_cnt = ${v_svc_cnt}"
    
    case ${v_svc_cnt} in
        0)
            debug "GI Stack is down"
            ;;
        [1..3])
            debug "GI Stack is partially up"
            ;;
        4)  
            debug "GI Stack is up"
            ;;
        *)
            debug "Something is wrong!"
            ;;
    esac
    
    # Check if grid home is unlocked
    local v_owner=$(stat -c %U ${ga_directory[${gc_home[0]}]})
    debug "Grid Check: v_owner = ${v_owner}"
    if [ "${v_owner}" == "root" ] && [ ${v_svc_cnt} -eq 4 ]; then
        Log success "GI is already locked."
        return
    fi

    unsetTrap

    if [ "${v_cluster_major_version}" == "12" ]; then
        v_option="-postpatch"   # v12 option for rootcrs.pl
        if [ ${gv_rolling} -eq 0 ]; then
            v_option+=" -nonrolling"
        fi
    elif [ "${v_cluster_major_version}" == "11" ]; then
        v_option="-patch"       # v11 option for rootcrs.pl
    fi
    
    if [[ ${v_cluster_version} -lt 122000 ]]; then
        v_rootcrs_command=${ga_directory[${gc_home[0]}]}/crs/install/rootcrs.pl
    else
        v_rootcrs_command=${ga_directory[${gc_home[0]}]}/crs/install/rootcrs.sh
    fi
    
    debug "${v_rootcrs_command} ${v_option}"
    ${v_rootcrs_command} ${v_option} >>${gv_dbhomeupdate_log}  2>&1
    v_exit_status=${PIPESTATUS[0]}
    
    if [[ ${v_exit_status} -ne 0 ]]; then
        LogErrorAndExit "GI stack startup completed with errors."
    fi
    
    # wait up to 15 minutes for cluster to startup
    v_counter=0
    while [ ${v_counter} -lt 15 ]
    do
        v_svc_cnt=$(${ga_directory[${gc_home[0]}]}/bin/crsctl check crs | egrep -a -s -c 'CRS-4638|CRS-4537|CRS-4529|CRS-4533')
        debug "(${v_counter}/15): Waiting for GI stack to start... v_svc_cnt = ${v_svc_cnt}"
        
        if [ ${v_svc_cnt} -eq 4 ]; then break; fi
        
        sleep 60
    
        ((++${v_counter}))
    
    done
    
    if [[ ${v_svc_cnt} -ne 4 ]]; then
        LogErrorAndExit "CRS did not startup after 15 minutes."
        exit 1
    else
        Log success "GI stack successfully started"
    fi
    
    # Verify grid home is locked
    v_counter=0
    while [ ${v_counter} -le 1 ] # Only retry once
    do
        v_owner=$(stat -c %U ${ga_directory[${gc_home[0]}]})
        debug "Grid Check: v_owner = ${v_owner}"
        if [ "${v_owner}" != "root" ]; then
            if [ ${v_counter} -eq 0 ]; then 
                LogErrorAndContinue "GI is not locked. Attempting to lock..."
            else
                LogErrorAndExit "GI is still not locked after retry."
            fi
            debug ${v_rootcrs_command} -unlock
            ${v_rootcrs_command} -unlock >>${gv_dbhomeupdate_log} 2>&1
            debug "Return status = $?"
            debug ${v_rootcrs_command} -patch
            ${v_rootcrs_command} -patch >>${gv_dbhomeupdate_log} 2>&1
            debug "Return status = $?"
            ((++${v_counter}))
        else
            Log success "GI is locked."
            break
        fi
    done

    setTrap

    # Record cluster status to a log file after starting
    # Send to both dbhomeupdate.log and also to a new log file for later use
    rm -f ${gv_runid_logs}/${gc_home[0]}_gistatus.after
    touch ${gv_runid_logs}/${gc_home[0]}_gistatus.after
    debug "${ga_directory[${gc_home[0]}]}/bin/crsctl status resource -t -init"
    ${ga_directory[${gc_home[0]}]}/bin/crsctl status resource -t -init 2>&1 | /usr/bin/tee -a ${gv_dbhomeupdate_log} >${gv_runid_logs}/${gc_home[0]}_gistatus.after
    debug "${ga_directory[${gc_home[0]}]}/bin/crsctl status resource -t"
    ${ga_directory[${gc_home[0]}]}/bin/crsctl status resource -t       2>&1 | /usr/bin/tee -a ${gv_dbhomeupdate_log} >>${gv_runid_logs}/${gc_home[0]}_gistatus.after
        
    debug   # This just prints a blank line in the debug output
}


#--------------------------------------------------------------------------------
# PROCEDURE    : stopHome
# INPUT        :
# DESCRIPTION  : Stop the database home used in this patch run
#------------------------------------------------------------------------------
stopHome()
{
    local v_home_id=$1

    [ -z "${v_home_id}" ] || [ -z "${ga_directory[$v_home_id]}" ] && return

    if [ -n "${ga_directory[$v_home_id]}" ]; then
        unsetTrap
        debug "${v_home_id}: directory=${ga_directory[${v_home_id}]}"
        debug "state file: ${gv_runid_logs}/${v_home_id}.state"
        if [ ! -z "${ga_directory[${v_home_id}]}" ] && [ ! -f "${gv_runid_logs}/${v_home_id}.state" ]; then
            Log info "Stopping home ${ga_directory[${v_home_id}]} ..."
            debug "ORACLE_HOME=${ga_directory[${v_home_id}]} ${ga_directory[${gc_home[0]}]}/bin/srvctl stop home -o ${ga_directory[${v_home_id}]} -s ${gv_runid_logs}/${v_home_id}.state -n ${gv_hostname} -t immediate"
            ORACLE_HOME=${ga_directory[${v_home_id}]} ${ga_directory[${v_home_id}]}/bin/srvctl stop home -o ${ga_directory[${v_home_id}]} -s ${gv_runid_logs}/${v_home_id}.state -n ${gv_hostname} -t immediate
            v_exit_status=${PIPESTATUS[0]}
            if [ ${v_exit_status} -eq 0 ]; then
                Log success "Successfully stopped home ${ga_directory[${v_home_id}]}"
            else
                LogErrorAndContinue "Error stopping home ${ga_directory[${v_home_id}]}"
            fi
        fi
        setTrap
    fi
    debug   # This just prints a blank line in the debug output
}


#--------------------------------------------------------------------------------
# PROCEDURE    : startHome
# INPUT        :
# DESCRIPTION  : Start the database home used in this patch run
#------------------------------------------------------------------------------
startHome()
{
    local v_home_id=$1

    [ -z "${v_home_id}" ] || [ -z "${ga_directory[$v_home_id]}" ] && return

    if [ -n "${ga_directory[$v_home_id]}" ]; then
        unsetTrap
        if [ -z ${v_home_id} ]; then continue; fi
        debug "${v_home_id}: directory=${ga_directory[${v_home_id}]}"
        debug "state file: ${gv_runid_logs}/${v_home_id}.state"
        if [ ! -z "${ga_directory[${v_home_id}]}" ]; then
            Log info "Starting home ${ga_directory[${v_home_id}]} ..."
            debug "ORACLE_HOME=${ga_directory[${v_home_id}]} ${ga_directory[${gc_home[0]}]}/bin/srvctl start home -o ${ga_directory[${v_home_id}]} -s ${gv_runid_logs}/${v_home_id}.state -n ${gv_hostname}"
            ORACLE_HOME=${ga_directory[${v_home_id}]} ${ga_directory[${v_home_id}]}/bin/srvctl start home -o ${ga_directory[${v_home_id}]} -s ${gv_runid_logs}/${v_home_id}.state -n ${gv_hostname}
            v_exit_status=${PIPESTATUS[0]}
            if [ ${v_exit_status} -eq 0 ]; then
                Log success "Successfully started home ${ga_directory[${v_home_id}]}"
            else
                LogErrorAndContinue "Error starting home ${ga_directory[${v_home_id}]}"
            fi
        fi
        setTrap
    fi
    debug   # This just prints a blank line in the debug output
}


#--------------------------------------------------------------------------------
# PROCEDURE    : startAllHomes
# INPUT        :
# DESCRIPTION  : Start all home that have databases registered with CRS
#------------------------------------------------------------------------------
startAllHomes()
{
    declare -a a_databases
    declare v_state_file=""
    
    for v_home in ${!ga_databases[@]}
    do
        # start the home
        unsetTrap
        debug "v_home=${v_home}"
        a_databases=( ${ga_databases[${v_home}]} )
        debugPrintArray a_databases
        v_state_file=${gv_runid_logs}/${a_databases[0]}.state # Name the state file after the first database listed in ga_databases for a given home
        debug "state file=${v_state_file}"
        Log info "Starting home ${v_home} ..."
        debug "ORACLE_HOME=${v_home} ${v_home}/bin/srvctl start home -o ${v_home} -s ${v_state_file} -n ${gv_hostname}"
        ORACLE_HOME=${v_home} ${v_home}/bin/srvctl start home -o ${v_home} -s ${v_state_file} -n ${gv_hostname}
            v_exit_status=${PIPESTATUS[0]}
            if [ ${v_exit_status} -eq 0 ]; then
                Log success "Successfully started home ${v_home}"
            else
                LogErrorAndContinue "Error starting home ${v_home}"
            fi
        setTrap
    done
}


#--------------------------------------------------------------------------------
# PROCEDURE    : stopAllHomes
# INPUT        :
# DESCRIPTION  : Stop all home that have databases registered with CRS
#------------------------------------------------------------------------------
stopAllHomes()
{
    declare -a a_databases
    declare v_state_file=""
    
    for v_home in ${!ga_databases[@]}
    do
        # stop the home
        unsetTrap
        debug "v_home=${v_home}"
        a_databases=( ${ga_databases[${v_home}]} )
        v_state_file=${gv_runid_logs}/${a_databases[0]}.state # Name the state file after the first database listed in ga_databases for a given home
        debug "state file=${v_state_file}"
        if [ -f ${v_state_file} ]; then continue; fi # in case we do a restart
        Log info "Stopping home ${v_home} ..."
        debug "ORACLE_HOME=${v_home} ${v_home}/bin/srvctl stop home -o ${v_home} -s ${v_state_file} -n ${gv_hostname} -t immediate"
        ORACLE_HOME=${v_home} ${v_home}/bin/srvctl stop home -o ${v_home} -s ${v_state_file} -n ${gv_hostname} -t immediate
            v_exit_status=${PIPESTATUS[0]}
            if [ ${v_exit_status} -eq 0 ]; then
                Log success "Successfully stopped home ${v_home}"
            else
                LogErrorAndContinue "Error stopping home ${v_home}"
            fi
        setTrap
    done
}


#--------------------------------------------------------------------------------
# PROCEDURE    : saveState
# INPUT        :
# DESCRIPTION  : Save the current state of the run
#------------------------------------------------------------------------------
saveState()
{
    local v_state=$1
    
    debug "v_state           = ${v_state}"
    debug "gv_runid_statefile= ${gv_runid_statefile}"
    gv_runid_state=${v_state}
    set | egrep "^gv_|^ga_" 2>&1 >${gv_runid_statefile}
    debug   # This just prints a blank line in the debug output
}


#--------------------------------------------------------------------------------
# PROCEDURE    : recompileConfigC
# INPUT        :
# DESCRIPTION  : If the md5sum of oracle does not match across cluster then recompiling
#                config.c on all nodes will usually sync everything back up. Ref Doc ID 1637766.1
#------------------------------------------------------------------------------
recompileConfigC()
{
    local v_home_id=$1
    local v_cmd
    
    [ -z "${v_home_id}" ] || [ -z "${ga_directory[$v_home_id]}" ] && return

    # Make a backup of config.o using no clobber flag. This will prevent us from overwriting 
    # an already backed up file in case we run more than once. Then do rm -f to make sure that 
    # config.o is gone (it will still be present if there was already a backup when using no clobber).
    v_cmd="export ORACLE_HOME=${ga_directory[$v_home_id]}; cd ${ga_directory[$v_home_id]}/rdbms/lib; mv -n config.o config.o.$(date +%y%m%d); rm -f config.o; make -f ins_rdbms.mk config.o; make -f ins_rdbms.mk install"
    unsetTrap
    debug su ${ga_owner[$v_home_id]} -c '"'"${v_cmd}"'"'
    su ${ga_owner[$v_home_id]} -c "${v_cmd}" 2>&1 | /usr/bin/tee -a ${gv_dbhomeupdate_log} >/dev/null 2>&1
    setTrap
    debug   # This just prints a blank line in the debug output
}


#--------------------------------------------------------------------------------
# PROCEDURE    : executePatch
# INPUT        :
# DESCRIPTION  : Apply the patches
#------------------------------------------------------------------------------
executePatch()
{
    local v_home_id=$1
    local v_phbasefile=${gv_runid_logs}/${v_home_id}_phBaseFile
    local v_idfile=${gv_runid_logs}/${v_home_id}_idFile
    local v_exit_status

    [ -z "${v_home_id}" ] || [ -z "${ga_directory[$v_home_id]}" ] && return

    unsetTrap
    # Do rollbacks first
    if [ -f ${v_idfile} ] && [ ! -f "${v_idfile}.completed" ]; then
        if [ -n "${ga_directory[$v_home_id]}" ] && [ -n "${ga_owner[$v_home_id]}" ] && [ -n "${ga_rollbackOOB[$v_home_id]}" ]; then
            Log info "Rolling back patches from home ${ga_directory[$v_home_id]} ..."
            debug su ${ga_owner[$v_home_id]} -c '"'"${ga_directory[$v_home_id]}/OPatch/opatch nrollback -idFile ${v_idfile} -oh ${ga_directory[$v_home_id]} -local -silent"'"'
            su ${ga_owner[$v_home_id]} -c "${ga_directory[$v_home_id]}/OPatch/opatch nrollback -idFile ${v_idfile} -oh ${ga_directory[$v_home_id]} -local -silent"  2>&1 | /usr/bin/tee -a ${gv_dbhomeupdate_log} >>${gv_runid_logs}/${v_home_id}_lsinventory.${v_run}
            v_exit_status=${PIPESTATUS[0]}
            if [ ${v_exit_status} -eq 0 ]; then
                Log success "Successfully rolled back patches from ${ga_directory[$v_home_id]}"
                touch "${v_idfile}.completed"
            else
                LogErrorAndExit "Opatch returned with status $v_exit_status when rolling back patches from ${ga_directory[$v_home_id]}"
            fi
        fi
    fi

    # Do patches second
    if [ -f ${v_phbasefile} ] && [ ! -f "${v_phbasefile}.completed" ]; then
        if [ -n "${ga_directory[$v_home_id]}" ] && [ -n "${ga_owner[$v_home_id]}" ] && ([ -n "${ga_applyBP[$v_home_id]}" ] || [ -n "${ga_applyOOB[$v_home_id]}" ]); then
            Log info "Applying patches to home ${ga_directory[$v_home_id]} ..."
            if grep -q "19215058" ${v_phbasefile}; then chmod u+w ${ga_directory[${v_home_id}]}/QOpatch/qopiprep.bat 2>&1; fi # datapatch patch 19215058. Readme step 9
            debug chown -R ${ga_owner[$v_home_id]}:${ga_group[$v_home_id]} $(cat ${v_phbasefile})
            chown -R ${ga_owner[$v_home_id]}:${ga_group[$v_home_id]} $(cat ${v_phbasefile}) >/dev/null 2>&1
            debug su ${ga_owner[$v_home_id]} -c '"'"${ga_directory[$v_home_id]}/OPatch/opatch napply -phBaseFile ${v_phbasefile} -oh ${ga_directory[$v_home_id]} -local -silent -ocmrf ${gv_ocm_file}"'"'
            su ${ga_owner[$v_home_id]} -c "${ga_directory[$v_home_id]}/OPatch/opatch napply -phBaseFile ${v_phbasefile} -oh ${ga_directory[$v_home_id]} -local -silent -ocmrf ${gv_ocm_file}"  2>&1 | /usr/bin/tee -a ${gv_dbhomeupdate_log} >>${gv_runid_logs}/${v_home_id}_lsinventory.${v_run}
            v_exit_status=${PIPESTATUS[0]}
            if [ ${v_exit_status} -eq 0 ]; then
                Log success "Successfully applied patches to ${ga_directory[$v_home_id]}"
                touch "${v_phbasefile}.completed"
            else
                LogErrorAndExit "Opatch returned with status $v_exit_status when applying patches to ${ga_directory[$v_home_id]}"
            fi
        fi
    fi
    setTrap

    debug   # This just prints a blank line in the debug output
}


#--------------------------------------------------------------------------------
# PROCEDURE    : postChecks
# INPUT        :
# DESCRIPTION  : Do final checks
#------------------------------------------------------------------------------
postChecks()
{
    local v_cluster_state
    local v_owner
    local v_warning=0
    local v_error=0
    
#    unsetTrap
#    Log
#    Log "Checking differences in GI status before/after..."
#    debug diff ${gv_runid_logs}/${gc_home[0]}_gistatus.before ${gv_runid_logs}/${gc_home[0]}_gistatus.after
#    diff ${gv_runid_logs}/${gc_home[0]}_gistatus.before ${gv_runid_logs}/${gc_home[0]}_gistatus.after
#    setTrap
   
    Log
    for ((i=${gv_skipgrid}; i<${#gc_home[@]}; i++))
    do
        showPatches ${gc_home[$i]}
    done
    
    Log
    for ((i=${gv_skipgrid}; i<${#gc_home[@]}; i++))
    do
        showMd5sum ${gc_home[$i]}
    done
    
    debug "Verifying all patches got installed."
    unsetTrap
    for ((i=${gv_skipgrid}; i<${#gc_home[@]}; i++))
    do
        checkPatches ${gc_home[$i]}
        if [ $? -ne 0 ]; then v_warning=1; fi
    done

    # Check the clusterware upgrade state
    debug "Checking clusterware upgrade state."
    Log
    debug su ${ga_owner[${gc_home[0]}]} -c '"'"${ga_directory[${gc_home[0]}]}/bin/crsctl query crs activeversion -f"'"'
    v_cluster_state=$(su ${ga_owner[${gc_home[0]}]} -c "${ga_directory[${gc_home[0]}]}/bin/crsctl query crs activeversion -f")
    Log info "${v_cluster_state}"
    if [ $(echo ${v_cluster_state} | egrep -c "ROLLING PATCH") -gt 0 ]; then
        if [[ ${gv_rolling} -eq 0 ]]; then
            # For non-rolling cluster state should be NORMAL
            Log fail "Cluster is in ${gc_red}${gc_bold}ROLLING PATCH${gc_normal} state."
            v_error=1
        else
            # For rolling cluster state will be ROLLING PATCH on all but last node
            Log warn "Cluster is in ${gc_red}${gc_bold}ROLLING PATCH${gc_normal} state."
            v_warning=1
        fi
    elif [ $(echo ${v_cluster_state} | egrep -c "NORMAL") -gt 0 ]; then
        if [[ ${gv_orchestrator} -eq 0 ]]; then
            Log pass "Cluster is in ${gc_green}${gc_bold}NORMAL${gc_normal} state."
        else
            Log pass "Cluster is in NORMAL state."
        fi
    else
        Log fail "Unknown cluster state."
        v_error=1
    fi
    
    # Verify grid home is locked
    Log
    debug "Checking if grid home is locked"
    v_owner=$(stat -c %U ${ga_directory[${gc_home[0]}]})
    debug "Grid Check: v_owner = ${v_owner}"
    if [ "${v_owner}" != "root" ]; then
        Log fail "GI is not locked."
        v_error=1
    else
        Log pass "GI is locked."
    fi

    # Check if all of the instances running out of the homes we patched got restarted
    Log
    debug "Checking that database instances got restarted."
    for ((i=${gv_skipgrid}; i<${#gc_home[@]}; i++))
    do
        checkInstances ${gc_home[$i]}
        [[ $? -ne 0 ]] && Log error "checkInstances completed with error" && v_error=1
    done

    # Determine final exit status
    setTrap
    Log
    if [ ${v_warning} -eq 0 ] && [ ${v_error} -eq 0 ]; then
        Log success "Post checks completed successfully."
    elif [ ${v_error} -ne 0 ]; then
        Log error "Post checks completed with failures."
        exit 1
    else
        Log warn "Post checks completed with warnings."
    fi
    debug   # This just prints a blank line in the debug output
}


#--------------------------------------------------------------------------------
# PROCEDURE    : checkPatches
# INPUT        :
# DESCRIPTION  : Verify that all patches got installed
#------------------------------------------------------------------------------
checkPatches()
{
    local v_home_id=$1
    local v_phbasefile=${gv_runid_logs}/${v_home_id}_phBaseFile
    local v_inventory=${gv_runid_logs}/${v_home_id}_lsinventory.after
    local v_checked_cnt=0
    local v_found_cnt=0

    [ -z "${v_home_id}" ] || [ -z "${ga_directory[$v_home_id]}" ] && return
    
    if [ ! -f ${v_phbasefile} ]; then return; fi

    if [ -n "${ga_directory[$v_home_id]}" ]; then
        Log
        Log info "Checking patches for home ${ga_directory[$v_home_id]}\n"
        while read line;do
            v_patch=$(basename $line)
            ((++v_checked_cnt))
            if [ $(egrep -c ${v_patch} ${v_inventory}) -gt 0 ]; then
                Log pass "Patch ${v_patch} found."
                ((++v_found_cnt))
            else
                Log error "Patch ${v_patch} not found."
            fi
        done < ${v_phbasefile}
        if [ ${v_found_cnt} -eq ${v_checked_cnt} ]; then
            Log success "All patches installed in home ${ga_directory[$v_home_id]}."
            return 0
        else
            Log error "Some patches are missing in home ${ga_directory[$v_home_id]}."
            return 1
        fi
    fi
    debug   # This just prints a blank line in the debug output
}


#--------------------------------------------------------------------------------
# PROCEDURE    : workAroundBug22969720
# INPUT        :
# DESCRIPTION  : Workaround for opatch Bug 22969720 - OPATCH PREREQ RETURNS SUCCESS STATUS EVEN IF FAILED 
#------------------------------------------------------------------------------
workAroundBug22969720()
{
    local v_exit_status=$1
    local v_logfile=$2
    local v_error_flag=0
    
    if [ ${v_exit_status} -ne 0 ]; then return ${v_exit_status}; fi # If exit status is non-zero then just go with it. We already know its an error.
    
    v_error_flag=$(egrep -c "Prereq .* failed" ${v_logfile}) # A failed prereq is always of the form "Prereq <some variable text> failed."
    if [ ${v_error_flag} -ne 0 ]; then
        v_exit_status=1
        # Stopping here for now. We may need to figure out in more detail what happened.
    fi
    
    debug   # This just prints a blank line in the debug output
    return ${v_exit_status}
}


#--------------------------------------------------------------------------------
# PROCEDURE    : getFilesystem
# INPUT        : 1:<directory>
# DESCRIPTION  : Get filesystem that a directory resides on
#------------------------------------------------------------------------------
getFilesystem()
{
    local v_directory=$1
    local v_filesystem

    if [ -z "${v_directory}" ]; then
        v_filesystem=""
    elif [ -e ${v_directory} ]; then                                # Directory exists
        v_filesystem=$(df ${v_directory} | awk '/^\//{print $1}')   # determine filesystem that directory resides on
    else
        v_filesystem=$(getFilesystem $(dirname ${v_directory}))     # Directory doesn't exist so check 1 level up (recursive)
    fi
    printf "${v_filesystem}"
    # Always return successfully for now
    # if [ -z "${v_filesystem}" ]; then
    #     exit 1
    # fi
}


#--------------------------------------------------------------------------------
# PROCEDURE    : getNewBasename
# INPUT        : 1:<directory-basename>
# DESCRIPTION  : Derive a new directory basename
#------------------------------------------------------------------------------
getNewBasename()
{
    local v_basename=$1
    local v_idx
    
    unsetTrap
    [[ ${v_basename} =~ (.*_)([[:digit:]]+) ]]  # see if basename ends with "_x" where x is a number
    setTrap
    if [ ${#BASH_REMATCH[@]} -eq 0 ]; then   # no match. Append _2 like oplan would
        v_basename="${v_basename}_2"
    else
        v_idx=${BASH_REMATCH[2]}
        ((++v_idx))
        v_basename="${BASH_REMATCH[1]}${v_idx}"
    fi
    printf "${v_basename}"
}


#--------------------------------------------------------------------------------
# PROCEDURE    : checkTargetOOP
# INPUT        :
# DESCRIPTION  : If target not specified then derive one based on source home
#                If target is specified then check if it exists
#                If target exists then check if it is empty or not
#                Also save source directory in ga_sourceOOP and set ga_directory to ga_targetOOP
#------------------------------------------------------------------------------
checkTargetOOP()
{
    local v_home_id=$1
    local v_files
    local v_parent_directory
    local v_basename
    local v_warnings=0
    
    if [ -z "${ga_targetOOP[${v_home_id}]}" ]; then         # No target specified
        # Derive a target based on source home ${ga_directory[${v_home_id}]}
        v_parent_directory=$(dirname ${ga_directory[${v_home_id}]})
        v_basename=$(basename ${ga_directory[${v_home_id}]})
        debug "ga_targetOOP[${v_home_id}]: v_parent_directory=${v_parent_directory}"
        debug "ga_targetOOP[${v_home_id}]: v_basename=${v_basename}"
        for ((i=0; i<100; i++)) # limit loop to make sure we don't get into an infinite loop
        do
            v_basename=$(getNewBasename ${v_basename})
            if [ ! -d "${v_parent_directory}/${v_basename}" ]; then break; fi # break when we find a directory that doesn't exist
            if [ $i -eq 99 ]; then LogErrorAndExit "Could not derive new clone target directory for ${v_home_id} home"; fi
        done
        ga_targetOOP[${v_home_id}]="${v_parent_directory}/${v_basename}"
        Log info "You did not specify a target directory for ${v_home_id}"
        Log warn "Derived clone target directory ${ga_targetOOP[${v_home_id}]} based on ${ga_directory[${v_home_id}]}"
        Log warn "If this is not correct then stop and supply a target directory on next run"
        ((++gv_warnings))
        ((++v_warnings))
    elif [ -d "${ga_targetOOP[${v_home_id}]}" ]; then       # Target specified and exists. Make sure it is empty
        shopt -s nullglob dotglob
        v_files=(${ga_targetOOP[${v_home_id}]}/*)
        shopt -u nullglob dotglob
        if [ ${#v_files[@]} -gt 0 ]; then 
            LogErrorAndExit "Clone target ${ga_targetOOP[${v_home_id}]} contains files"
        fi
    fi  # Else not needed. Target specified and does not exist
    # Make sure filesystem does not reside on root filesystem
    if [ "$(getFilesystem ${ga_targetOOP[${v_home_id}]})" == "$(getFilesystem /)" ]; then
        LogErrorAndExit "Clone target ${ga_targetOOP[${v_home_id}]} resides on root filesystem"
    fi
    if [ ${v_warnings} -eq 0 ]; then
        Log pass "Clone target check for ${v_home_id} directory ${ga_targetOOP[${v_home_id}]}"
    fi
    ga_sourceOOP[${v_home_id}]=${ga_directory[${v_home_id}]}    # Save source directory
    debugPrintArray ga_sourceOOP
    debugPrintArray ga_targetOOP
    Log
}    


#--------------------------------------------------------------------------------
# PROCEDURE    : calculateSpaceRequiredOOP
# INPUT        :
# DESCRIPTION  : Get space required to clone a home and add it to ga_spaceOOP
#------------------------------------------------------------------------------
calculateSpaceRequiredOOP()
{
    local v_home_id=$1
    local v_space_required
    local v_filesystem
    local v_files
    
    [ -z "${v_home_id}" ] || [ -z "${ga_directory[$v_home_id]}" ] && return

    v_space_required=$(du -sk ${ga_sourceOOP[${v_home_id}]} | awk '{print $1}') # Get space used in this one home
    if [ -z "${ga_targetOOP[${v_home_id}]}" ]; then 
        v_filesystem=$(getFilesystem ${ga_source[${v_home_id}]})    # No target was specified. Use the same filesystem that source resides on
    else
        v_filesystem=$(getFilesystem ${ga_targetOOP[${v_home_id}]}) # Target is specified.
    fi
    debug "v_filesystem=${v_filesystem}"
    debug "v_space_required=${v_space_required}"
    ga_spaceOOP[${v_filesystem}]=$((ga_spaceOOP[${v_filesystem}] + v_space_required)) # running total in case more than one home on same filesystem
    debugPrintArray ga_spaceOOP
    debug
}


#--------------------------------------------------------------------------------
# PROCEDURE    : getHomeInfoOOP
# INPUT        :
# DESCRIPTION  : Get home info for Out-of-Place
#------------------------------------------------------------------------------
getHomeInfoOOP()
{
    local v_home_id=$1
    local v_inventory_xml
    local v_inventory_xsl=${gv_runid_logs}/sylesheetOOP.xsl
    local v_inventory_loc
    
    [ -z "${v_home_id}" ] || [ -z "${ga_directory[$v_home_id]}" ] && return

    makeOOPStylesheet ${v_inventory_xsl} ${ga_sourceOOP[${v_home_id}]}

    # Get home name and nodes
    # Nov-14-2016
    # Check for ORACLE_HOME/oraInst.loc first, if not found then check /etc/oraInst.loc
    if [ -e ${ga_sourceOOP[${v_home_id}]}/oraInst.loc ]; then
        v_inventory_loc=${ga_sourceOOP[${v_home_id}]}/oraInst.loc
    elif [ -e /etc/oraInst.loc ]; then
        v_inventory_loc=/etc/oraInst.loc
    else
        LogErrorAndExit "Could not find oraInst.loc"
    fi
    v_inventory_xml=$(cat ${v_inventory_loc} | awk -F "=" '/inventory_loc/{print $2}')/ContentsXML/inventory.xml
    debug "v_inventory_xml=${v_inventory_xml}"
    if [ -f "${v_inventory_xml}" ]; then
        # This monster statement should give a string of the format <HOME NAME>:<NODE1>,<NODEx>,;
        v_home_info=$(CLASSPATHJ=${ga_sourceOOP[${v_home_id}]}/jdbc/lib/ojdbc.jar:${ga_sourceOOP[${v_home_id}]}/jlib/orai18n.jar \
        CLASSPATH=.:${CLASSPATHJ}:${ga_sourceOOP[${v_home_id}]}/lib/xmlparserv2.jar:${ga_sourceOOP[${v_home_id}]}/lib/xsu12.jar:${ga_sourceOOP[${v_home_id}]}/lib/xml.jar \
        JAVA_HOME=${ga_sourceOOP[${v_home_id}]}/jdk LD_LIBRARY_PATH=${ga_sourceOOP[${v_home_id}]}/lib:${LD_LIBRARY_PATH} \
        PATH=${JAVA_HOME}/bin:$PATH ${ga_sourceOOP[${v_home_id}]}/bin/oraxsl  ${v_inventory_xml} ${v_inventory_xsl})
        debug "v_home_info=${v_home_info}"
        v_home_info=${v_home_info%%,;*} # remove everything after ",;"
        ga_nameOOP[${v_home_id}]=${v_home_info%%:*}  # grab everything before the ":"
        ga_nodesOOP[${v_home_id}]=${v_home_info#*:}   # grab everything after the ":"
        # debug "ga_nameOOP[${v_home_id}]=${ga_nameOOP[${v_home_id}]}"
        # debug "ga_nodesOOP[${v_home_id}]=${ga_nodesOOP[${v_home_id}]}"
    else
        LogErrorAndExit "Can't find inventory file ${v_inventory_xml}"
    fi
    # Get ORACLE_BASE
    if [ -x "${ga_sourceOOP[${v_home_id}]}/bin/orabase" ]; then
        ga_baseOOP[${v_home_id}]=$(ORACLE_HOME=${ga_sourceOOP[${v_home_id}]} ${ga_sourceOOP[${v_home_id}]}/bin/orabase)
    else
        LogErrorAndExit "Could not determine ORACLE_BASE for home ${ga_sourceOOP[${v_home_id}]}"
    fi
    debugPrintArray ga_nameOOP 
    debugPrintArray ga_nodesOOP 
    debugPrintArray ga_baseOOP 
    debug
}


#--------------------------------------------------------------------------------
# PROCEDURE    : getOsDbaInfoOOP
# INPUT        :
# DESCRIPTION  : Get osdba groups for Out-of-Place (needed for clone.pl)
#------------------------------------------------------------------------------
getOsDbaInfoOOP()
{
    local v_home_id=$1
    local v_version
    
    v_version=${ga_version[${v_home_id}]%%.*} # We only need up to the first dot
    
    case ${v_version} in
        12)
            [[ $(numVer ${ga_version[${v_home_id}]}) -ge 122000 ]] && ga_osdbaOOP[${v_home_id}-rac]=$(${ga_sourceOOP[${v_home_id}]}/bin/osdbagrp -r) #PLAT-349 (Bug 27771497)
            ga_osdbaOOP[${v_home_id}-bkp]=$(${ga_sourceOOP[${v_home_id}]}/bin/osdbagrp -b)
            ga_osdbaOOP[${v_home_id}-dgd]=$(${ga_sourceOOP[${v_home_id}]}/bin/osdbagrp -g)
            ga_osdbaOOP[${v_home_id}-kmt]=$(${ga_sourceOOP[${v_home_id}]}/bin/osdbagrp -k)
            ;& # 12 has extra stuff that 11 doesn't have so process 12 first and fall through to 11
        11)
            ga_osdbaOOP[${v_home_id}-dba]=$(${ga_sourceOOP[${v_home_id}]}/bin/osdbagrp -d)
            ga_osdbaOOP[${v_home_id}-asm]=$(${ga_sourceOOP[${v_home_id}]}/bin/osdbagrp -a)
            ga_osdbaOOP[${v_home_id}-oper]=$(${ga_sourceOOP[${v_home_id}]}/bin/osdbagrp -o)
            ;;
        *)
            LogErrorAndExit "Unknown version"
            ;;
    esac
    debugPrintArray ga_osdbaOOP
    debug
}


#--------------------------------------------------------------------------------
# PROCEDURE    : cloneHomeOOP
# INPUT        :
# DESCRIPTION  : 
#------------------------------------------------------------------------------
cloneHomeOOP()
{
    local v_home_id=$1
    local v_inventory
    local v_inventory_loc
    local v_hostname=$(hostname -s)
    local v_quot='"'
    local v_apos="'"
    local v_protocol
    local v_version=${ga_version[${v_home_id}]%%.*} # We only need up to the first dot

    local v_su_cmd

#    if [[ $(numVer ${ga_version[${v_home_id}]}) -gt 122000 ]]; then
#        Log warn "dbhomeupdate.sh has not been tested for cloning of 12.2 homes."
#    fi
    
    debug "ga_owner[${v_home_id}]=${ga_owner[${v_home_id}]}"
    debug "ga_group[${v_home_id}]=${ga_group[${v_home_id}]}"
    debug "ga_sourceOOP[${v_home_id}]=${ga_sourceOOP[${v_home_id}]}"
    debug "ga_targetOOP[${v_home_id}]=${ga_targetOOP[${v_home_id}]}"
    makeDirectory ${ga_targetOOP[${v_home_id}]} ${ga_owner[${v_home_id}]} ${ga_group[${v_home_id}]}
    Log info "Cloning directory ${ga_sourceOOP[${v_home_id}]} to ${ga_targetOOP[${v_home_id}]}"
    if [ -d ${ga_targetOOP[${v_home_id}]} ]; then
        debug "cp -pRT ${ga_sourceOOP[${v_home_id}]} ${ga_targetOOP[${v_home_id}]}"
        cp -pRT ${ga_sourceOOP[${v_home_id}]} ${ga_targetOOP[${v_home_id}]}
        debug "rm -f ${ga_targetOOP[${v_home_id}]}/root.sh"
        rm -f ${ga_targetOOP[${v_home_id}]}/root.sh
    else
        LogErrorAndExit "Clone target directory ${ga_targetOOP[${v_home_id}]} does not exist" 
    fi
    if [ "${v_home_id}" == "${gc_home[0]}" ]; then # This is the grid home
        # Nov-14-2016
        # Check for ORACLE_HOME/oraInst.loc first, if not found then check /etc/oraInst.loc
        if [ -e ${ga_sourceOOP[${v_home_id}]}/oraInst.loc ]; then
            v_inventory_loc=${ga_sourceOOP[${v_home_id}]}/oraInst.loc
        elif [ -e /etc/oraInst.loc ]; then
            v_inventory_loc=/etc/oraInst.loc
        else
            LogErrorAndExit "Could not find oraInst.loc"
        fi
        v_inventory=$(cat ${v_inventory_loc} | awk -F "=" '/inventory_loc/{print $2}')
        # v_inventory=$(cat ${ga_sourceOOP[${v_home_id}]}/oraInst.loc | awk -F "=" '/inventory_loc/{print $2}')
        if [ ! -d "${v_inventory}" ]; then
            LogErrorAndExit "Cound not determine oraInventory directory"
        fi
        if [ ${v_version} -eq 11 ]; then
            # Unlock the grid home v11
            /usr/bin/perl ${ga_targetOOP[${v_home_id}]}/crs/install/rootcrs.pl -unlock -destcrshome=${ga_targetOOP[${v_home_id}]}
            # run clone.pl
            v_su_cmd="/usr/bin/perl ${ga_targetOOP[${v_home_id}]}/clone/bin/clone.pl ORACLE_BASE=${ga_baseOOP[${v_home_id}]} ORACLE_HOME=${ga_targetOOP[${v_home_id}]} -defaultHomeName"
            v_su_cmd+=" INVENTORY_LOCATION=${v_inventory} -O${v_apos}${v_quot}CLUSTER_NODES={${ga_nodesOOP[${v_home_id}]}}${v_quot}${v_apos} -O${v_apos}${v_quot}LOCAL_NODE=${v_hostname}${v_quot}${v_apos}"
            v_su_cmd+=" CRS=false -O${v_apos}${v_quot}SHOW_ROOTSH_CONFIRMATION=false${v_quot}${v_apos} OSDBA_GROUP=${ga_osdbaOOP[${v_home_id}-dba]} OSOPER_GROUP=${ga_osdbaOOP[${v_home_id}-oper]}"
            v_su_cmd+=" OSASM_GROUP=${ga_osdbaOOP[${v_home_id}-asm]}"
            debug "su ${ga_owner[${v_home_id}]} -c ${v_quot}${v_su_cmd}${v_quot}"
            su ${ga_owner[${v_home_id}]} -c "${v_su_cmd}" >>${gv_dbhomeupdate_log} 2>&1
        else
            # Unlock the grid home v12
            ${ga_targetOOP[${v_home_id}]}/perl/bin/perl -I${ga_targetOOP[${v_home_id}]}/perl/lib -I${ga_targetOOP[${v_home_id}]}/crs/install ${ga_targetOOP[${v_home_id}]}/crs/install/rootcrs.pl -prepatch -dstcrshome ${ga_targetOOP[${v_home_id}]}
            # run clone.pl
            v_su_cmd="/usr/bin/perl ${ga_targetOOP[${v_home_id}]}/clone/bin/clone.pl ORACLE_BASE=${ga_baseOOP[${v_home_id}]} ORACLE_HOME=${ga_targetOOP[${v_home_id}]} INVENTORY_LOCATION=${v_inventory}"
            v_su_cmd+=" -defaultHomeName -O${v_apos}${v_quot}CLUSTER_NODES={${ga_nodesOOP[${v_home_id}]}}${v_quot}${v_apos} -O${v_apos}${v_quot}LOCAL_NODE=${v_hostname}${v_quot}${v_apos} CRS=false"
            v_su_cmd+=" -O${v_apos}${v_quot}SHOW_ROOTSH_CONFIRMATION=false${v_quot}${v_apos} OSDBA_GROUP=${ga_osdbaOOP[${v_home_id}-dba]} OSOPER_GROUP=${ga_osdbaOOP[${v_home_id}-oper]}"
            v_su_cmd+=" OSASM_GROUP=${ga_osdbaOOP[${v_home_id}-asm]}  OSBACKUPDBA_GROUP=${ga_osdbaOOP[${v_home_id}-bkp]} OSDGDBA_GROUP=${ga_osdbaOOP[${v_home_id}-dgd]} OSKMDBA_GROUP=${ga_osdbaOOP[${v_home_id}-kmt]}"
            #Add OSRACDBA_GROUP PLAT-349 (Bug 27771497)
            [[ $(numVer ${ga_version[${v_home_id}]}) -ge 122000 ]] && v_su_cmd+=" OSRACDBA_GROUP=${ga_osdbaOOP[${v_home_id}-rac]}"
            debug "su ${ga_owner[${v_home_id}]} -c ${v_quot}${v_su_cmd}${v_quot}"
            su ${ga_owner[${v_home_id}]} -c "${v_su_cmd}"  >>${gv_dbhomeupdate_log} 2>&1
        fi
        v_protocol=$(${ga_sourceOOP[${v_home_id}]}/bin/skgxpinfo)
        # Enable RDS
        if [ "${v_protocol}" == 'rds' ]; then 
            debug su ${ga_owner[${v_home_id}]} -c '"'"cd ${ga_targetOOP[${v_home_id}]}/rdbms/lib; ORACLE_HOME=${ga_targetOOP[${v_home_id}]} make -f ins_rdbms.mk ipc_rds ioracle"'"'
            su ${ga_owner[${v_home_id}]} -c "cd ${ga_targetOOP[${v_home_id}]}/rdbms/lib; ORACLE_HOME=${ga_targetOOP[${v_home_id}]} make -f ins_rdbms.mk ipc_rds ioracle" >>${gv_dbhomeupdate_log} 2>&1
        fi
        # Run root.sh
        debug ${ga_targetOOP[${v_home_id}]}/root.sh
        ${ga_targetOOP[${v_home_id}]}/root.sh >>${gv_dbhomeupdate_log} 2>&1
    else # database home
        if [ ${v_version} -eq 11 ]; then
            # run clone.pl
            v_su_cmd="/usr/bin/perl ${ga_targetOOP[${v_home_id}]}/clone/bin/clone.pl ORACLE_BASE=${ga_baseOOP[${v_home_id}]} ORACLE_HOME=${ga_targetOOP[${v_home_id}]}  -defaultHomeName"
            v_su_cmd+=" OSDBA_GROUP=${ga_osdbaOOP[${v_home_id}-dba]} OSOPER_GROUP=${ga_osdbaOOP[${v_home_id}-oper]} OSASM_GROUP=${ga_osdbaOOP[${v_home_id}-asm]}"
            debug "su ${ga_owner[${v_home_id}]} -c ${v_quot}${v_su_cmd}${v_quot}"
            su ${ga_owner[${v_home_id}]} -c "${v_su_cmd}" >>${gv_dbhomeupdate_log} 2>&1
        else
            # run clone.pl
            v_su_cmd="/usr/bin/perl ${ga_targetOOP[${v_home_id}]}/clone/bin/clone.pl ORACLE_BASE=${ga_baseOOP[${v_home_id}]} ORACLE_HOME=${ga_targetOOP[${v_home_id}]}  -defaultHomeName"
            v_su_cmd+=" OSDBA_GROUP=${ga_osdbaOOP[${v_home_id}-dba]} OSOPER_GROUP=${ga_osdbaOOP[${v_home_id}-oper]} OSASM_GROUP=${ga_osdbaOOP[${v_home_id}-asm]}"
            v_su_cmd+=" OSBACKUPDBA_GROUP=${ga_osdbaOOP[${v_home_id}-bkp]} OSDGDBA_GROUP=${ga_osdbaOOP[${v_home_id}-dgd]} OSKMDBA_GROUP=${ga_osdbaOOP[${v_home_id}-kmt]}"
            #Add OSRACDBA_GROUP PLAT-349 (Bug 27771497)
            [[ $(numVer ${ga_version[${v_home_id}]}) -ge 122000 ]] && v_su_cmd+=" OSRACDBA_GROUP=${ga_osdbaOOP[${v_home_id}-rac]}"
            debug "su ${ga_owner[${v_home_id}]} -c ${v_quot}${v_su_cmd}${v_quot}"
            su ${ga_owner[${v_home_id}]} -c "${v_su_cmd}" >>${gv_dbhomeupdate_log} 2>&1
        fi 
        v_protocol=$(${ga_sourceOOP[${v_home_id}]}/bin/skgxpinfo)
        # Enable RAC
        debug su ${ga_owner[${v_home_id}]} -c '"'"cd ${ga_targetOOP[${v_home_id}]}/rdbms/lib; ORACLE_HOME=${ga_targetOOP[${v_home_id}]} make -f ins_rdbms.mk rac_on ioracle"'"'
        su ${ga_owner[${v_home_id}]} -c "cd ${ga_targetOOP[${v_home_id}]}/rdbms/lib; ORACLE_HOME=${ga_targetOOP[${v_home_id}]} make -f ins_rdbms.mk rac_on ioracle"
        # Enable RDS
        if [ "${v_protocol}" == 'rds' ]; then 
            debug su ${ga_owner[${v_home_id}]} -c '"'"cd ${ga_targetOOP[${v_home_id}]}/rdbms/lib; ORACLE_HOME=${ga_targetOOP[${v_home_id}]} make -f ins_rdbms.mk ipc_rds ioracle"'"'
            su ${ga_owner[${v_home_id}]} -c "cd ${ga_targetOOP[${v_home_id}]}/rdbms/lib; ORACLE_HOME=${ga_targetOOP[${v_home_id}]} make -f ins_rdbms.mk ipc_rds ioracle" >>${gv_dbhomeupdate_log} 2>&1
        fi
        # Run root.sh
        debug ${ga_targetOOP[${v_home_id}]}/root.sh
        ${ga_targetOOP[${v_home_id}]}/root.sh >>${gv_dbhomeupdate_log} 2>&1
    fi
    ga_directory[${v_home_id}]=${ga_targetOOP[${v_home_id}]}    # Reset directory to be patched to targetOOP directory
    debugPrintArray ga_directory
}

#--------------------------------------------------------------------------------
# PROCEDURE    : findParentDirectories
# INPUT        :
# DESCRIPTION  : Return each of the individual directories in a given directory string
#                ie, findParentDirectories /temp/temp1/temp2/temp3
#                returns: /temp /temp/temp1 /temp/temp1/temp2 /temp/temp1/temp2/temp3
#------------------------------------------------------------------------------
findParentDirectories()
{
    # Sample usage:
    # declare -a my_array
    # my_array=($(findParentDirectories $1 $2))
    # echo ${my_array[@]}

    local v_dir=$1
    local v_end=${2%/}
    local -a v_array

    if [ -z "${v_end}" ]; then
        if [ "${v_dir:0:1}" == "/" ]; then
            v_end="/"
        else
            v_end="."
        fi
    fi
    while [[ ${v_dir} != "." ]] && [[ ${v_dir} != "/" ]] && [[ ${v_dir} != ${v_end} ]]
    do
        v_array=( ${v_dir} ${v_array[@]} )
        v_dir=$(dirname ${v_dir})
    done;
    echo ${v_array[@]}
}


#--------------------------------------------------------------------------------
# PROCEDURE    : makeDirectory
# INPUT        : 1:<directory> 2:<owner> 3:<group>
# DESCRIPTION  : Check if each level of the directory exists and create it doesn't exist
#                Similar to mkdir -p except assign owner:group for each directory created
#                Adapted (and improved) from code produced by Oplan
#------------------------------------------------------------------------------
makeDirectory()
{
    local v_path=$1
    local v_owner=$2
    local v_group=$3
    local v_dir
    local -a v_dir_array
    
    # Verify user and group are valid
    if ! id "${v_owner}" > /dev/null 2>&1
    then
        LogErrorAndExit "User ${v_owner} does not exist"
    fi
    if ! grep -iq "^${v_group}:" /etc/group
    then
        LogErrorAndExit "Group ${v_group} does not exist"
    fi
    
    v_dir_array=($(findParentDirectories ${v_path}))
    debugPrintArray v_dir_array
    for v_dir in "${v_dir_array[@]}"
    do
#        if [ "${v_dir}" == "${v_path}" ]; then continue; fi
        if [ ! -d ${v_dir} ]; then
            Log info "Creating ${v_dir}"
            mkdir ${v_dir}
            chgrp ${v_group} ${v_dir}
            chown ${v_owner} ${v_dir}
        fi
    done
}


#--------------------------------------------------------------------------------
# PROCEDURE    : switchGridhome
# INPUT        :
# DESCRIPTION  : Switch to new grid home
#------------------------------------------------------------------------------
switchGridhome()
{
    local v_quot='"'
    local v_apos="'"
    local v_su_cmd
    local v_target_version

    # For case where all we are doing is switching grid home
    if [ ${gv_switch_gridhome} -eq 1 ]; then
        if [ -n "${gv_switch_gridhome_target}" ]; then
            ga_sourceOOP[${gc_home[0]}]=${ga_directory[${gc_home[0]}]}
            ga_targetOOP[${gc_home[0]}]=${gv_switch_gridhome_target}
        fi
    fi

    v_target_version=$(ORACLE_HOME=ga_targetOOP[${gc_home[0]}] ga_targetOOP[${gc_home[0]}]/bin/sqlplus -V | awk 'NF { print $3 }')

    if [[ $(numVer ${v_target_version}) -gt 122000 ]]; then
        LogErrorAndExit "dbhomeupdate.sh has not been tested for cloning of 12.2 homes."
    fi
    Log info "Switching Grid Home ..."
    Log blank "    Old Home: ${ga_sourceOOP[${gc_home[0]}]}"
    Log blank "    New Home: ${ga_targetOOP[${gc_home[0]}]}"
    # Update nodelist on existing home (as grid user)
    v_su_cmd="${ga_sourceOOP[${gc_home[0]}]}/oui/bin/runInstaller -updateNodeList ORACLE_HOME=${ga_sourceOOP[${gc_home[0]}]} CRS=${v_quot}false${v_quot} -local"
    debug su ${ga_owner[${gc_home[0]}]} -c "${v_su_cmd}"
    su ${ga_owner[${gc_home[0]}]} -c "${v_su_cmd}" >>${gv_dbhomeupdate_log} 2>&1
    # Update nodelist on cloned home (as grid user)
    v_su_cmd="${ga_targetOOP[${gc_home[0]}]}/oui/bin/runInstaller -updateNodeList ORACLE_HOME=${ga_targetOOP[${gc_home[0]}]} CRS=${v_quot}true${v_quot} -local"
    debug su ${ga_owner[${gc_home[0]}]} -c "${v_su_cmd}"
    su ${ga_owner[${gc_home[0]}]} -c "${v_su_cmd}" >>${gv_dbhomeupdate_log} 2>&1

    # Verify grid clone is unlocked
    local v_owner=$(stat -c %U ${ga_targetOOP[${gc_home[0]}]})
    debug "Grid Clone Check: v_owner = ${v_owner}"
    if [ "${v_owner}" != ${ga_owner[${gc_home[0]}]} ]; then
        debug ${ga_targetOOP[${gc_home[0]}]}/perl/bin/perl -I${ga_targetOOP[${gc_home[0]}]}/perl/lib -I${ga_targetOOP[${gc_home[0]}]}/crs/install ${ga_targetOOP[${gc_home[0]}]}/crs/install/rootcrs.pl -prepatch -dstcrshome ${ga_targetOOP[${gc_home[0]}]}
        ${ga_targetOOP[${gc_home[0]}]}/perl/bin/perl -I${ga_targetOOP[${gc_home[0]}]}/perl/lib -I${ga_targetOOP[${gc_home[0]}]}/crs/install ${ga_targetOOP[${gc_home[0]}]}/crs/install/rootcrs.pl -prepatch -dstcrshome ${ga_targetOOP[${gc_home[0]}]} >>${gv_dbhomeupdate_log} 2>&1
    fi
    debug ${ga_targetOOP[${gc_home[0]}]}/perl/bin/perl -I${ga_targetOOP[${gc_home[0]}]}/perl/lib -I${ga_targetOOP[${gc_home[0]}]}/crs/install ${ga_targetOOP[${gc_home[0]}]}/crs/install/rootcrs.pl -postpatch -dstcrshome ${ga_targetOOP[${gc_home[0]}]}
    ${ga_targetOOP[${gc_home[0]}]}/perl/bin/perl -I${ga_targetOOP[${gc_home[0]}]}/perl/lib -I${ga_targetOOP[${gc_home[0]}]}/crs/install ${ga_targetOOP[${gc_home[0]}]}/crs/install/rootcrs.pl -postpatch -dstcrshome ${ga_targetOOP[${gc_home[0]}]} >>${gv_dbhomeupdate_log} 2>&1
    
    Log success "Successfully switched to Grid Home ${ga_targetOOP[${gc_home[0]}]}"
    ga_directory[${gc_home[0]}]=${ga_targetOOP[${gc_home[0]}]}

    debug
}


#--------------------------------------------------------------------------------
# PROCEDURE    : findAllHomes
# INPUT        :
# DESCRIPTION  : Find all database homes registered in the central inventory
#------------------------------------------------------------------------------
findAllHomes()
{
    local v_inventory_loc
    local v_inventory_xml
    local v_inventory_xsl=${gv_runid_logs}/sylesheetInventory.xsl
    
    # Bug 26591307 - DBHOMEUPDATE FINDALLHOMES MAY NOT SELECT ALL DB/GI HOMES FROM INVENTORY 
    cat >${v_inventory_xsl} <<EOFINV
<?xml version="1.0"?>
<xsl:transform xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="2.0">
    <xsl:comment>8-Aug-2017 Changed to be:</xsl:comment>
    <xsl:comment>Select all HOMEs that do not have REFHOMELIST or DEPHOMELIST and are not REMOVED</xsl:comment>
    <xsl:output method="text" indent="yes"/>
    <xsl:strip-space elements="*"/>
    <xsl:template match="/">
        <xsl:for-each select="//HOME[not (REFHOMELIST) and not (DEPHOMELIST) and not(@REMOVED='T')]">
            <xsl:value-of select="@LOC" /> <xsl:text> </xsl:text>
        </xsl:for-each>
    </xsl:template>
</xsl:transform>
EOFINV


    # Get inventory location from grid home
    # Nov-14-2016
    # Check for ORACLE_HOME/oraInst.loc first, if not found then check /etc/oraInst.loc
    if [ -e ${ga_directory[${gc_home[0]}]}/oraInst.loc ]; then
        v_inventory_loc=${ga_directory[${gc_home[0]}]}/oraInst.loc
    elif [ -e /etc/oraInst.loc ]; then
        v_inventory_loc=/etc/oraInst.loc
    else
        LogErrorAndExit "Could not find oraInst.loc"
    fi
    v_inventory_xml=$(cat ${v_inventory_loc} | awk -F "=" '/inventory_loc/{print $2}')/ContentsXML/inventory.xml
    #v_inventory_xml=$(cat ${ga_directory[${gc_home[0]}]}/oraInst.loc | awk -F "=" '/inventory_loc/{print $2}')/ContentsXML/inventory.xml
    Log info "Central Inventory File: ${v_inventory_xml}"
    if [ -f "${v_inventory_xml}" ]; then
        # This monster statement should give a string of the format <HOME NAME>:<NODE1>,<NODEx>,;
        ga_homes_inventory=($(CLASSPATHJ=${ga_directory[${gc_home[0]}]}/jdbc/lib/ojdbc.jar:${ga_directory[${gc_home[0]}]}/jlib/orai18n.jar \
                            CLASSPATH=.:${CLASSPATHJ}:${ga_directory[${gc_home[0]}]}/lib/xmlparserv2.jar:${ga_directory[${gc_home[0]}]}/lib/xsu12.jar:${ga_directory[${gc_home[0]}]}/lib/xml.jar \
                            JAVA_HOME=${ga_directory[${gc_home[0]}]}/jdk LD_LIBRARY_PATH=${ga_directory[${gc_home[0]}]}/lib:${LD_LIBRARY_PATH} \
                            PATH=${JAVA_HOME}/bin:$PATH ${ga_directory[${gc_home[0]}]}/bin/oraxsl  ${v_inventory_xml} ${v_inventory_xsl}))
        debugPrintArray ga_homes_inventory
    else
        LogErrorAndExit "Can't find inventory file ${v_inventory_xml}"
    fi
    debug
}


#--------------------------------------------------------------------------------
# FUNCTION     : localInstance
# INPUT        : output from srvctl status database
# RETURN       : Name of instance running on local node
# DESCRIPTION  : Checks if db is running on local node or not
#------------------------------------------------------------------------------
function localInstance
{
    local v_dbStatus="$1"
    
    v_pattern='Instance (.+) is running on node (.+)'
    while read -r v_line; do
        if [[ ${v_line} =~ ${v_pattern} ]]; then
            if [[ ${BASH_REMATCH[2]} = $(hostname -s) ]] || [[ ${BASH_REMATCH[2]} = $(hostname) ]]; then
                echo "${BASH_REMATCH[1]}" && exit 0
            fi
        fi
    done <<<"${v_dbStatus}"
    echo "" && exit 1
}


#--------------------------------------------------------------------------------
# PROCEDURE    : findAllDatabases
# INPUT        :
# DESCRIPTION  : Find all databases and their homes that are registered with CRS
#------------------------------------------------------------------------------
findAllDatabases()
{
    declare -a a_databases
    declare v_db=""
    declare v_dbhome="" # This will be the ORACLE_HOME of the database being checked
    declare v_status=""
    declare v_local_instance
    
    unsetTrap
    a_databases=($(${ga_directory[${gc_home[0]}]}/bin/crsctl status resource -t -w "TYPE = ora.database.type" | awk -F "." '/^ora\..*\.db$/ {print $2}'))
    for v_db in ${a_databases[@]}
    do
        v_dbhome=$(${ga_directory[${gc_home[0]}]}/bin/srvctl config database -d ${v_db} -a | awk '/^Oracle home:/{print $3};/PRCD-1229/{print substr($NF,1,length($NF)-1)}')
        debug "${v_db}: v_dbhome=${v_dbhome}"
        if [[ -z ${v_dbhome} ]]; then continue; fi
        if [[ ! -d ${v_dbhome} ]]; then continue; fi # PLAT-278 (bug 27110603)
        v_status=$(ORACLE_HOME=${v_dbhome} ${v_dbhome}/bin/srvctl status database -d ${v_db})
        v_local_instance=$(localInstance "${v_status}")
        [[ -n ${v_local_instance} ]] && debug "Local instance of database ${v_db}: ${v_local_instance}" || debug "No local instance of database ${v_db}"
        ga_databases[${v_dbhome}]="$v_db ${ga_databases[${v_dbhome}]}" # Space separated list of db's for a given home for ease of converting to array
        [[ -n ${v_local_instance} ]] && ga_local_instances[${v_dbhome}]="${v_db}:$v_local_instance ${ga_local_instances[${v_dbhome}]}" # Space separated list of instances running on each home
    done
    setTrap
    debugPrintArray ga_databases
    debugPrintArray ga_local_instances
    debug
}


#--------------------------------------------------------------------------------
# PROCEDURE    : checkInstances
# INPUT        : a dbhome directory
# DESCRIPTION  : Check to make sure the local instances got restarted
#------------------------------------------------------------------------------
checkInstances()
{
    local v_home_id=$1
    local v_dbhome
    local -a a_instances
    local return_status=0
    
    [ -z "${v_home_id}" ] || [ -z "${ga_directory[$v_home_id]}" ] && return

    v_dbhome=${ga_directory[$v_home_id]}
    a_instances=(${ga_local_instances[${v_dbhome}]})

    for v_pair in ${a_instances[@]}
    do
        v_db=${v_pair%%:*}
        v_instance=${v_pair##*:}
        debug "database: $v_db, instance: $v_instance"
        debug "ORACLE_HOME=${v_dbhome} ${v_dbhome}/bin/srvctl status database -d ${v_db}"
        v_status=$(ORACLE_HOME=${v_dbhome} ${v_dbhome}/bin/srvctl status database -d ${v_db})
        debug "${v_status}"
        v_local_instance=$(localInstance "${v_status}")
        if [[ -n ${v_local_instance} ]]; then
            Log pass "Database ${v_db} instance ${v_instance} is running"
        else
            Log fail "Database ${v_db} instance ${v_instance} is not running"
            return_status=1
        fi
    done
    return $return_status
}


#--------------------------------------------------------------------------------
# PROCEDURE    : printBanner
# INPUT        :
# DESCRIPTION  : Print startup banner
#------------------------------------------------------------------------------
printBanner()
{
    local -l v_response="" # force to lowercase
    
    Log info "############################"
    Log info "Runid ${gv_runid}"
    Log info "############################"
    Log
    Log info "dbhomeupdate.sh: ${gc_version}"
    Log info "Master Log File: ${gv_dbhomeupdate_log}"
    Log info "Runid directory: ${gv_runid_logs}"
    Log
    Log info "Grid Home: ${ga_directory[${gc_home[0]}]}"
    if [ ${gv_skipgrid} -eq 0 ]; then
        Log info "Grid Home Rollback Patches : ${ga_rollbackOOB[${gc_home[0]}]}"
        Log info "Grid Home Bundle Patch     : ${ga_applyBP[${gc_home[0]}]}"
        Log info "Grid Home Apply Patches    : ${ga_applyOOB[${gc_home[0]}]}"
        if [ ${ga_targetOOP[${gc_home[0]}]+exists} ]; then
            Log info "Grid Home Clone Home       : yes"
            [[ -n ${ga_targetOOP[${gc_home[0]}]} ]] && Log info "Grid Home Clone Directory  : ${ga_targetOOP[${gc_home[0]}]}" || Log info "Grid Home Clone Directory  : not supplied (use next available)"
        else
            Log info "Grid Home Clone Home       : no"
        fi
        Log
    fi
    if [ ${gv_switch_gridhome} -eq 1 ]; then
        Log info "Switching to new Grid Home"
        Log info "Old Grid Home: ${ga_directory[${gc_home[0]}]}"
        if [ -n "${gv_switch_gridhome_target}" ]; then
            Log info "New Grid Home: ${gv_switch_gridhome_target}"
        else
            Log info "New Grid Home: ${ga_targetOOP[${gc_home[0]}]}"
        fi
        Log
    fi

    for ((i=1; i<${#gc_home[@]}; i++))
    do
        if [ -z "${ga_directory[${gc_home[$i]}]}" ]; then continue; fi
        Log info "DB Home $i: ${ga_directory[${gc_home[$i]}]}"
        Log info "DB Home $i Rollback Patches : ${ga_rollbackOOB[${gc_home[$i]}]}"
        Log info "DB Home $i Bundle Patch     : ${ga_applyBP[${gc_home[$i]}]}"
        Log info "DB Home $i Apply Patches    : ${ga_applyOOB[${gc_home[$i]}]}"
        if [ ${ga_targetOOP[${gc_home[$i]}]+exists} ]; then
            Log info "DB Home $i Clone Home       : yes"
            [[ -n ${ga_targetOOP[${gc_home[$i]}]} ]] && Log info "DB Home $i Clone Directory  : ${ga_targetOOP[${gc_home[$i]}]}" || Log info "DB Home $i Clone Directory  : not supplied (use next available)"
        else
            Log info "DB Home $i Clone Home       : no"
        fi
        Log
    done
    Log

    if [ ${gv_orchestrator} -eq 0 ] && [ ${gv_quiet} -eq 0 ]; then
        while true; do
            read -p "Do you want to continue? [Yes/No] " v_response
            case ${v_response} in
                y?(es)) 
                    break
                    ;;
                n?(o)) 
                    exit
                    ;;
                *)  echo "Please answer yes or no.";;
            esac
        done
    fi
    Log
}


#--------------------------------------------------------------------------------
# PROCEDURE    : getPatchBase
# INPUT        :
# DESCRIPTION  : Parse command line to find --patch-base
#------------------------------------------------------------------------------
getPatchBase()
{
    local -i v_opt_cnt=0
    local v_opt
    local opts=( ${gv_options} )
    for v_opt in "${opts[@]}"
    do
            v_opt_cnt+=1
            if [[ ${v_opt} = "--patch-base" ]]; then
                gv_patch_base=${opts[$v_opt_cnt]}
                break
            fi
    done
}


#-------------------------------------------------------------------------------
# PROCEDURE    : makeLogDirectory
# DESCRIPTION  : Create log directory (if needed) and set permissions
#------------------------------------------------------------------------------
makeLogDirectory()
{
    local v_dir=$1
    
    if [[ -z ${v_dir} ]]; then
        log_message error "Log directory not specified"
        exit 1
    fi
    
    mkdir -p ${v_dir}
    while [[ ${v_dir} != "/" ]]
    do 
        chmod o+x ${v_dir}
        v_dir=$(dirname ${v_dir})
    done;
}


#--------------------------------------------------------------------------------
#--------------------------------------------------------------------------------
# PROCEDURE    : main
# INPUT        :
# DESCRIPTION  : main program
#------------------------------------------------------------------------------
#--------------------------------------------------------------------------------

setTrap

###############################
# Declare Globals
###############################
###############################
# Global Constants (gc_)
###############################

declare -a -r gc_states='([0]="initialization" \
                          [1]="checkTargetOOP" \
                          [2]="checkSpaceOOP" \
                          [3]="getHomeInfoOOP" \
                          [4]="buildPatchLists" \
                          [5]="cloneHomeOOP" \
                          [6]="updateOpatch" \
                          [7]="stopHomes" \
                          [8]="stopStack" \
                          [9]="executePatch" \
                          [10]="switchGridhome" \
                          [11]="startStack" \
                          [12]="startHomes" \
                          [13]="postChecks" \
                          [14]="epilogue")'

declare -r gc_home_index='0|1|2|3|4|5|6' # Used in parsing command line switches. These indexes correspond to the gc_home index values
declare -a -r gc_home=(grid dbhome1 dbhome2 dbhome3 dbhome4 dbhome5 dbhome6) # indexed array of home identifiers used as index into each of the attribute arrays (See Global Arrays below)

# initialize color constants
if [[ -t 1 ]] && [[ $(tput colors) -ge 8 ]]; then
    gc_red="$(tput setaf 1)"
    gc_green="$(tput setaf 2)"
    gc_yellow="$(tput setaf 3)"
    gc_blue="$(tput setaf 4)"
    gc_magenta="$(tput setaf 5)"
    gc_cyan="$(tput setaf 6)"
    gc_white="$(tput setaf 7)"
    gc_bold="$(tput bold)"
    gc_normal="$(tput sgr0)"
    gc_rev="$(tput rev)"
else
    gc_red=""
    gc_green=""
    gc_yellow=""
    gc_blue=""
    gc_magenta=""
    gc_cyan=""
    gc_white=""
    gc_bold=""
    gc_normal=""
    gc_rev=""
fi

# Now make them readonly
declare -r gc_red
declare -r gc_green
declare -r gc_yellow
declare -r gc_blue
declare -r gc_magenta
declare -r gc_cyan
declare -r gc_white
declare -r gc_bold
declare -r gc_normal
declare -r gc_rev

declare -r gc_pass=${gc_green}
declare -r gc_success=${gc_green}
declare -r gc_fail=${gc_red}
declare -r gc_info=${gc_cyan}
declare -r gc_warn=${gc_yellow}
declare -r gc_error=${gc_red}
declare -r gc_debug=${gc_cyan}${gc_rev}
declare -r gc_date_format="+%Y-%b-%d %H:%M:%S %Z"
#declare -r gc_date_format="+%H:%M:%S"

###############################
# Global Variables (gv_)
###############################

declare -i gv_debug=0                                               # debug flag
declare -i gv_trace=0                                               # trace flag (debug automatically enables tracing as well)
declare -i gv_warnings=0                                            # Warning counter
declare -i gv_errors=0                                              # Error counter
declare -i gv_quiet=0                                               # Quiet mode. Do no prompt. 
declare -i gv_verify=0                                              # Verify inputs only flag (ie, precheck mode) 
declare -i gv_recompile_config=0                                    # Recompile config.c flag
declare -i gv_lspatches=0                                           # lspatches flag
declare -i gv_md5sum=0                                              # md5sum flag
declare -i gv_skipgrid=0                                            # skip grip flag (since we don't ever pass -h0 tell script to skip grid related actions)
declare -i gv_orchestrator=0                                        # Orchestrator flag
declare -i gv_all_homes=0                                           # All homes flag
declare -i gv_post_installs=0                                       # number of post install scripts detected
declare gv_rolling=""                                               # Rolling/nonrolling mode
declare gv_cont_runid=""                                            # Continuation run id
declare gv_orch_runid=""                                            # Orchestration run id
declare gv_step=""                                                  # Step to run when orchestration
#declare gv_runid=$(date '+%d%m%y%H%M%S')                            # Runid for this run
declare gv_runid=$(date '+%y%m%d%H%M%S')                            # Runid for this run
declare gv_runid_state="initialization"                             # For use in continuing a run
declare gv_runid_statefile=""                                       # File containing the last state completed
declare gv_hostname=$(hostname -s)                                  # Short hostname of the current node
declare gv_options=$@                                               # Copy of options passed in
declare gv_oratab=/etc/oratab                                       # Oratab file
declare gv_patch_base=${gv_patch_base:-/u01/patches}                # (Command line option) Patch base directory where the patch directories are located
#declare gv_patch_logs=$(readlink -f $(dirname $0))/LOGS             # Location for log files (LOGS directory under where this procedure is executing
declare gv_patch_logs=/var/log/PlatinumPatching/DBHOMEUPDATE        # Location for log files (LOGS directory under where this procedure is executing
declare gv_dbhomeupdate_log=${gv_patch_logs}/dbhomeupdate.log       # Master log file
declare gv_runid_logs=${gv_patch_logs}/${gv_runid}                  # Location for log files (maybe)
declare gv_patch_bp=${gv_patch_bp:-${gv_patch_base}/BP}             # Directory containing bundle and OJVM patches
declare gv_patch_oneoff=${gv_patch_oneoff:-${gv_patch_base}/ONEOFF} # Directory containing oneoff patches
declare gv_patch_opatch=${gv_patch_opatch:-${gv_patch_base}/OPATCH} # Directory containing opatch patches and to store generated patchlists
declare gv_ocm_file=${gv_runid_logs}/ocm.rsp                        # OCM response file
declare gv_switch_gridhome=0                                        # Switch grid home flag
declare gv_switch_gridhome_target=""                                # Target grid home to switch to

###############################
# Global Arrays (ga_)
###############################

# The home array is an indexed array of home names. For now, this will be a fixed array consisting of grid home and two database homes.
# Later, if needed, we can either add more homes or make the list dynamic so it can grow to as many homes as needed.
# The grid home will always be index 0 because it is needed even if we don't patch the grid home. That convieniently makes each of
# the database homes fall into place with home1 being 1, home2 being 2, etc. The home array names will be used as the subscript 
# for each of the attribute arrays.
#
# For example:
# home=(grid home1 home2)
# ga_directory[grid]=/home/grid
#
# The grid home directory can be referenced as either
# ${ga_directory[grid]}       or
# ${ga_directory[${gc_home[0]}]}

declare -A ga_directory       # associative array of oracle home directories                              ex:([grid]="/u01/app/12.1.0.2/grid")
declare -A ga_owner           # associative array of oracle home owners                                   ex:([grid]="grid" [home1]="oracle")
declare -A ga_group           # associative array of oracle home groups                                   ex:([grid]="oinstall" [home1]="oinstall")
declare -A ga_version         # associative array of oracle home versions                                 ex:([grid]="12.1.0.2.0")
declare -A ga_applyBP         # associative array of bundle patch(es) to apply to oracle home             ex:([grid]="22243551")
declare -A ga_applyOOB        # associative array of OOBs to apply to oracle home                         ex:([home1]="18430870,19215058,20471759")
declare -A ga_rollbackOOB     # associative array of OOBs to rollback from oracle home                    ex:([home1]="22777907,22721307")
declare -A ga_postInstall     # associative array of patches that have post install scripts               ex:([home1]="22777907")
declare -A ga_opatch_zips     # associative array of opatch filenames and versions                        ex:([12-file]="p6880880_121010_Linux-x86-64.zip" [12-version]="12.1.0.1.10")
declare -A ga_min_opatch=([11]="11.2.0.3.19" [12]="12.2.0.1.13")
declare -A ga_databases       # associative array of databases and homes that are registered with CRS     ex:([/u01/app/oracle/product/11.2.0.4/dbhome_1]="db2 " [/u01/app/oracle/product/12.1.0.2/dbhome_1]="db1 db3 " )
declare -A ga_local_instances # associative array of local instances running on this home and homes that are registered with CRS     ex:([/u01/app/oracle/product/11.2.0.4/dbhome_1]="db2 " [/u01/app/oracle/product/12.1.0.2/dbhome_1]="db1 db3 " )
declare -a ga_homes_inventory # array of homes derived from central inventory

# Out-of-place stuff
declare -A ga_sourceOOP       # associative array of home indexes and source directories                  ex:([grid]="/u01/app/12.1.0.2/grid")
declare -A ga_targetOOP       # associative array of home indexes and target directories                  ex:([grid]="/u01/app/12.1.0.2/grid_2")
declare -A ga_baseOOP         # associative array of home indexes and ORACLE_BASE directories             ex:([grid]="/u01/app/12.1.0.2")
declare -A ga_nameOOP         # associative array of home names to be used for out-of-place               ex:([grid]="oraGridHome")
declare -A ga_nodesOOP        # associative array of node lists to be used for out-of-place               ex:([grid]="dmiscdb01vm02,dmiscdb02vm02")
declare -A ga_spaceOOP        # associative array of filesystems and space required for out-of-place      ex:([/dev/mapper/VGExaDb-LVDbOra1]="72248648")
declare -A ga_osdbaOOP        # associative array of osdba groups required for out-of-place               ex:([grid-dba]="dba" [grid-oper]="dba" [grid-asm]="asm")

###############################
# Check Requirements
###############################

parseOptions ${gv_options}

# Make sure we are root
if [ ${USER} != "root" ]; then
    Log
    Log error "You must be root to execute this script."
    if [ ${gv_orchestrator} -eq 1 ] && [ ${UID} -eq 0 ]; then # This is for the EM case where we used root credential without sudo.
        Log info "EM Credential is not setup properly. Root user detected in non-privileged context."
        Log info "Steps to correct:"
        Log info "    1. Verify that privilege delegation is configured."
        Log info "    2. Configure credential to use sudo and run as root. This is required even if the credential user is root."
    elif [ ${gv_orchestrator} -eq 1 ] && [ ${UID} -ne 0 ]; then
        Log info "EM Credential is not setup properly."
        Log info "Steps to correct:"
        Log info "    1. Verify that privilege delegation is configured."
        Log info "    2. Configure credential to use sudo and run as root."
    fi
    Log
    exit 1
fi

# Make sure we are at least Bash 4.x
if [ ${BASH_VERSINFO[0]} -lt 4 ]
then 
    Log
    Log error "Bash ${BASH_VERSION}: You need at least bash 4.0 to run this script." 
    Log
fi

# Make sure the LOGS directory exists
makeLogDirectory ${gv_patch_logs}
touch ${gv_patch_logs}/dbhomeupdate.log

###############################
# Pre-Inititialization
###############################

#getPatchBase
if [ ! -d ${gv_patch_base} ]; then
    Log error "No such directory: ${gv_patch_base}"
    Log error "Consider using \"--patch-base $( cd $(dirname $0) ; pwd -P )\""
    exit 1
else
    debug "gv_patch_base=${gv_patch_base}"
fi

[ ${gv_orchestrator} -eq 1 ] && x_sev="info" || x_sev="debug"
Log ${x_sev} "########################################################"
Log ${x_sev} "########################################################"
Log ${x_sev} "########################################################"
Log ${x_sev} ""
Log ${x_sev} "$(cat $(dirname $0)/.patchutils-release 2>/dev/null)"
Log ${x_sev} "${gc_myname}, version ${gc_version}"
Log ${x_sev} ""
Log ${x_sev} "command: $0 $@"
Log ${x_sev} "Local time: "$(date "${gc_date_format}")
Log ${x_sev} "Local time offset: "$(date "+%:z")
Log ${x_sev} "Host: "$(hostname)

[ ${gv_orchestrator} -eq 1 ] && gv_runid_state=${gv_step} # If this is an orchestration then set the runid state

# If this is a continuation run then source the the previous values from the state file
# gv_runid_state will be null on first run
if [ -n "${gv_cont_runid}" ] || ( [ -n "${gv_orch_runid}" ] && [ "${gv_step}" != "initialization" ] ); then
    [ -n "${gv_cont_runid}" ] && gv_runid=${gv_cont_runid} || gv_runid=${gv_orch_runid} # assign gv_runid value of either gv_cont_runid or gv_orch_runid
    [ ${gv_orchestrator} -eq 1 ] && debug "Orchestration runid: ${gv_runid}"
    gv_runid_logs=${gv_patch_logs}/${gv_runid}             # update log directory
    gv_runid_statefile="${gv_runid_logs}/dbhomeupdate.state"    # File containing the next state to execute
    gv_ocm_file=${gv_runid_logs}/ocm.rsp                        # OCM response file
    if [ ! -d "${gv_runid_logs}" ]; then
        LogErrorAndExit "${gv_runid_logs} does not exist or is not a directory. Unable to continue"
    elif [ ! -e "${gv_runid_statefile}" ]; then
        LogErrorAndExit "${gv_runid_statefile} does not exist. Unable to continue"
    else
        chmod 755 ${gv_patch_logs}/${gv_runid}
    fi
    if [ ${gv_debug} -eq 1 ] || [ ${gv_orchestrator} -eq 1 ]; then 
        Log
        Log info "Sourcing previous state"
        set -v; 
    fi
    declare v_step=${gv_step} # save gv_step so we don't clobber it.
    . ${gv_runid_statefile} 2>&1
    set +v
    if [ ${gv_debug} -eq 1 ] || [ ${gv_orchestrator} -eq 1 ]; then 
        Log
    fi
    # Explicitly check for "-debug" on the command line to override the saved state
    if [[ " $@ " =~ " --debug " ]] || [[ " $@ " =~ " -d " ]]; then
        gv_debug=1
    else
        gv_debug=0
    fi
    gv_step=${v_step}
    #debugPrintArray ga_version
    [ ${gv_orchestrator} -eq 1 ] && gv_runid_state=${gv_step} && debug "Setting state to ${gv_step}" # if orchestration then we have to reset the state again
    if [ ${gv_orchestrator} -eq 0 ] && [[ " initialization checkTargetOOP checkSpaceOOP getHomeInfoOOP buildPatchLists " =~ ${gv_runid_state} ]]; then
        Log error "Restart at state ${gv_runid_state} not supported. Please start a new run."
        exit
    fi
    Log info "########################################################"
    Log info "Resuming execution of runid ${gv_runid} at state ${gv_runid_state}"
    Log info "########################################################"
else
    gv_runid_logs=${gv_patch_logs}/${gv_runid}             # update log directory
    gv_runid_statefile="${gv_runid_logs}/dbhomeupdate.state"    # File containing the next state to execute
fi

# Do I really need to do this check?
if [ ! -d "${gv_patch_base}" ]; then
    LogErrorAndExit "${gv_patch_base} does not exist or is not a directory."
fi

# The currently executing state is saved in gv_runid_state.
# If execution gets halted for some reason we can skip the already 
# completed states and return to the beginning of the state that was
# executing when the script halted.


case ${gv_runid_state} in

###################################
initialization)
###################################
debug   # This just prints a blank line in the debug output
debug "Begin State: initialization"
debug "Old runid: ${gv_runid}"
debug "New runid: ${gv_orch_runid}"
if [ ${gv_orchestrator} -eq 1 ]; then # We have to check before we save the state so we save to the right place
    gv_runid=${gv_orch_runid}
    gv_runid_logs=${gv_patch_logs}/${gv_runid}
    gv_runid_statefile="${gv_runid_logs}/dbhomeupdate.state"    # File containing the next state to execute
    gv_ocm_file=${gv_runid_logs}/ocm.rsp                        # OCM response file
fi

# Initialize grid variables and check if grid home exists
# Use ${gc_home[0]} in case we ever decide to change the home array names
getGridHome # Replace old method of using oratab entry
ga_directory[${gc_home[0]}]=${gv_grid_home}

debug
# Get the owner and group for the homes specified
for ((i=0; i<${#gc_home[@]}; i++))
do
    if [ -z "${gc_home[$i]}" ]; then continue; fi
    
    debug "gc_home[$i]                 = '${gc_home[$i]}'"
    if [ ! -z "${gc_home[$i]}" ] && [ ! -z "${ga_directory[${gc_home[$i]}]}" ] && [ -d "${ga_directory[${gc_home[$i]}]}" ]; then
        ga_owner[${gc_home[$i]}]=$(stat -c %U ${ga_directory[${gc_home[$i]}]}/bin/sqlplus) # use sqlplus to determine owner/group because oracle file
        ga_group[${gc_home[$i]}]=$(stat -c %G ${ga_directory[${gc_home[$i]}]}/bin/sqlplus) # can change ownership in role separation
        debug "ga_version[${gc_home[$i]}]=$(ORACLE_HOME=${ga_directory[${gc_home[$i]}]} ${ga_directory[${gc_home[$i]}]}/bin/sqlplus -V | awk 'NF { print $3 }')"
        ga_version[${gc_home[$i]}]=$(ORACLE_HOME=${ga_directory[${gc_home[$i]}]} ${ga_directory[${gc_home[$i]}]}/bin/sqlplus -V | awk 'NF { print $3 }')
        debug "ga_directory[${gc_home[$i]}]   = ${ga_directory[${gc_home[$i]}]}"
        debug "ga_owner[${gc_home[$i]}]       = ${ga_owner[${gc_home[$i]}]}"
        debug "ga_group[${gc_home[$i]}]       = ${ga_group[${gc_home[$i]}]}"
        debug "ga_version[${gc_home[$i]}]     = ${ga_version[${gc_home[$i]}]}"
        debug "ga_applyBP[${gc_home[$i]}]     = ${ga_applyBP[${gc_home[$i]}]}"
        debug "ga_applyOOB[${gc_home[$i]}]    = ${ga_applyOOB[${gc_home[$i]}]}"
        debug "ga_rollbackOOB[${gc_home[$i]}] = ${ga_rollbackOOB[${gc_home[$i]}]}"
        debug   # This just prints a blank line in the debug output
    fi
    
    # If we got patches on the command line then make sure there was a home specified
    if [ ! -z "${gc_home[$i]}" ] && [ ! -z "${ga_applyBP[${gc_home[$i]}]}" ] || [ ! -z "${ga_applyOOB[${gc_home[$i]}]}" ] || [ ! -z "${ga_rollbackOOB[${gc_home[$i]}]}" ] && [ -z "${ga_directory[${gc_home[$i]}]}" ]; then
        LogErrorAndExit "Missing option '-oh$i'"
    fi
done
debug

if [ ${gv_switch_gridhome} -eq 1 ]; then
    if [ "${ga_directory[${gc_home[0]}]}" == "${ga_targetOOP[${gc_home[0]}]}" ] || [ "${ga_directory[${gc_home[0]}]}" == "${gv_switch_gridhome_target}" ]; then
        LogErrorAndExit "Target Grid Home is same as Source Grid Home"
    fi
fi

# Create the LOG directory if it doesn't exist
if [ ! -d "${gv_runid_logs}" ]; then
    mkdir -p ${gv_runid_logs}
    chmod 755 ${gv_runid_logs}
    debug "Created LOG directory ${gv_runid_logs}"
fi


if [ ${gv_all_homes} -eq 1 ]; then 
    findAllHomes
    #printAllHomes
    Log info "Homes registered in central inventory file"
    for i in "${ga_homes_inventory[@]}"
    do
        Log blank "    $i"
    done
fi

# if --lspatches on command line then just list patches and exit
if [ ${gv_lspatches} -eq 1 ]; then 
    case ${gv_all_homes} in
        0) 
            for ((i=${gv_skipgrid}; i<${#gc_home[@]}; i++))
            do
                showPatches ${gc_home[$i]}
            done
        ;;
        1)
            Log
            # List the inventory for each home
            for i in "${ga_homes_inventory[@]}"
            do
                # Bug 26591295 - DBHOMEUPDATE.SH -A -L STOPS WHEN ENCOUNTERING HOME THAT DOESN'T EXIST 
                [[ ! -e ${i}/bin/sqlplus ]] && Log error "${i} does not appear to be a valid home" && Log && continue
                o=$(stat -c %U ${i}/bin/sqlplus)
                Log info "Inventory for '$i'"
                debug su $o -c '"'"${i}/OPatch/opatch lspatches -oh ${i}"'"'
                su $o -c "${i}/OPatch/opatch lspatches -oh ${i}"
                Log
            done
        ;;
    esac
fi

if [ ${gv_md5sum} -eq 1 ]; then 
    case ${gv_all_homes} in
        0) 
            for ((i=${gv_skipgrid}; i<${#gc_home[@]}; i++))
                do
                showMd5sum ${gc_home[$i]}
            done
            ;;
        1)
            Log
            Log info "md5sum for homes registered in central inventory file"
            for i in "${ga_homes_inventory[@]}"
            do
                debug md5sum ${i}/bin/oracle
                md5sum ${i}/bin/oracle
            done
            ;;
    esac
fi
Log
# Exit if -all_homes, -lspatches or -md5sum switches are present
[ ${gv_all_homes} -eq 1 ] || [ ${gv_lspatches} -eq 1 ] || [ ${gv_md5sum} -eq 1 ] && exit


# Check Opatch
# If there were not any patches passed in then we can skip the steps in this phase
if [ ${#ga_applyBP[@]} -ne 0 ] || [ ${#ga_applyOOB[@]} -ne 0 ] || [ ${#ga_rollbackOOB[@]} -ne 0 ]; then
    for ((i=${gv_skipgrid}; i<${#gc_home[@]}; i++))
    do
        # PLAT-238
        # Check opatch inventory minimum version
        # Check opatch version matches home version
        checkOpatch ${gc_home[i]}
    done
fi

Log info "Gathering database info. Pease be patient."
findAllDatabases
Log

printBanner

# We set variables in this step so we need to save the state again.
saveState initialization
debug "End State: initialization"
[ "${gv_orchestrator}" -eq 1 ] && exit # If orchestrator then exit
;& 
# End of initialization state



###################################
checkTargetOOP)
###################################
debug   # This just prints a blank line in the debug output
debug "Begin State: checkTargetOOP"
saveState checkTargetOOP

# loop through all indexes for ga_targetOOP to check target directories, derive if necessary
for v_home_id in "${!ga_targetOOP[@]}"
do
    checkTargetOOP ${v_home_id}
    getOsDbaInfoOOP ${v_home_id}
done

# We set variables in this step so we need to save the state again.
saveState checkTargetOOP
debug "End State: checkTargetOOP"
[ "${gv_orchestrator}" -eq 1 ] && exit # If orchestrator then exit
;& 
# End of checkTargetOOP state



###################################
checkSpaceOOP)
###################################
debug   # This just prints a blank line in the debug output
debug "Begin State: checkSpaceOOP"
saveState checkSpaceOOP

# loop through all indexes for ga_targetOOP to add up space requirements
for v_home_id in "${!ga_targetOOP[@]}"
do
    calculateSpaceRequiredOOP ${v_home_id}
done

# Compare required space with available space
# Can't do this in the previous loop
for v_filesystem in "${!ga_spaceOOP[@]}"
do
#    v_filesystem=$(getFilesystem ${ga_targetOOP[${v_home_id}]})
    v_space_avail=$(df -k ${v_filesystem} | awk '/[0-9]%/{print $(NF-2)}') # only the line than has a number
    debug "v_filesystem=${v_filesystem}"
    debug "v_space_avail=${v_space_avail}"
    debug "ga_spaceOOP[${v_filesystem}]=${ga_spaceOOP[${v_filesystem}]}"
    if [ ${v_space_avail} -lt ${ga_spaceOOP[${v_filesystem}]} ]; then
        Log error "Not enough space on filesystem ${v_filesystem} to clone homes"
        ((++gv_errors))
    else
        Log pass "Clone space check for filesystem ${v_filesystem}"
    fi
    Log
done

# We set variables in this step so we need to save the state again.
saveState checkSpaceOOP
debug "End State: checkSpaceOOP"
[ "${gv_orchestrator}" -eq 1 ] && exit # If orchestrator then exit
;& 
# End of checkSpaceOOP state



###################################
getHomeInfoOOP)
###################################
debug   # This just prints a blank line in the debug output
debug "Begin State: getHomeInfoOOP"
saveState getHomeInfoOOP

for v_home_id in "${!ga_targetOOP[@]}"
do
    getHomeInfoOOP ${v_home_id}
done

# We set variables in this step so we need to save the state again.
saveState getHomeInfoOOP
debug "End State: getHomeInfoOOP"
[ "${gv_orchestrator}" -eq 1 ] && exit # If orchestrator then exit
;& 
# End of getHomeInfoOOP state



###################################
buildPatchLists)
###################################
debug   # This just prints a blank line in the debug output
debug "Begin State: buildPatchLists"
saveState buildPatchLists

# If there were not any patches passed in then we can skip the steps in this phase
if [ ${#ga_applyBP[@]} -ne 0 ] || [ ${#ga_applyOOB[@]} -ne 0 ] || [ ${#ga_rollbackOOB[@]} -ne 0 ]; then
    # Initialize and build the patch lists from command input
    for ((i=0; i<${#gc_home[@]}; i++))
    do
        initPatchLists ${gc_home[$i]}
    done
    
    declare -l v_response # force to lowercase
    
    Log
    
    # Check is this is a precheck run
    if [ ${gv_verify} -ne 0 ]; then
        if [ ${gv_errors} -ne 0 ]; then
            Log error "${gc_myname} precheck completed with errors."
            exit 1
        elif [ ${gv_warnings} -ne 0 ]; then
            Log warn "${gc_myname} precheck completed with warnings."
            exit 2
        else
            Log success "${gc_myname} precheck completed successfully."
            exit 0
        fi
    
    fi
    
    if [ ${gv_errors} -ne 0 ]; then
        Log error "Errors detected when building patch lists. Unable to continue."
        exit 1
    elif [ ${gv_warnings} -ne 0 ]; then
        echo "Warnings detected when building patch lists."
    else
        echo "No issues detected."
    fi
    if [ ${gv_orchestrator} -ne 0 ] || [ ${gv_quiet} -eq 1 ]; then
        if [ ${gv_errors} -ne 0 ] || [ ${gv_warnings} -ne 0 ]; then
            exit 1
        else
            echo "No issues detected."
        fi
    else
        while true; do
            read -p "Do you want to continue? [Yes/No] " v_response
            case ${v_response} in
                y?(es)) 
                    break
                    ;;
                n?(o)) 
                    exit
                    ;;
                *)  echo "Please answer yes or no.";;
            esac
        done
    fi
else
    # Check is this is a precheck run before blindly continuing
    if [ ${gv_verify} -ne 0 ]; then
        if [ ${gv_warnings} -ne 0 ]; then
            Log warn "${gc_myname} precheck completed with warnings."
            exit 1
        elif [ ${gv_errors} -ne 0 ]; then
            Log error "${gc_myname} precheck completed with errorss."
            exit 1
        else
            Log success "${gc_myname} precheck completed successfully."
            exit 0
        fi
    
    fi
fi

saveState buildPatchLists
debug "End State: buildPatchLists"
[ "${gv_orchestrator}" -eq 1 ] && exit # If orchestrator then exit
;& 
# End of buildPatchLists state



# This needs to move later in the process once debugging is done
###################################
cloneHomeOOP)
###################################
debug   # This just prints a blank line in the debug output
debug "Begin State: cloneHomeOOP"
saveState cloneHomeOOP

for v_home_id in "${!ga_targetOOP[@]}"
do
    cloneHomeOOP ${v_home_id}
done

# We set variables in this step so we need to save the state again.
saveState cloneHomeOOP
debug "End State: cloneHomeOOP"
[ "${gv_orchestrator}" -eq 1 ] && exit # If orchestrator then exit
;& 
# End of cloneHomeOOP state



###################################
updateOpatch)
###################################
debug   # This just prints a blank line in the debug output
debug "Begin State: updateOpatch"
saveState updateOpatch

# If there were not any patches passed in then we can skip the steps in this phase
if [ ${#ga_applyBP[@]} -ne 0 ] || [ ${#ga_applyOOB[@]} -ne 0 ] || [ ${#ga_rollbackOOB[@]} -ne 0 ]; then
    findOpatchZips
    
    
    for ((i=0; i<${#gc_home[@]}; i++))
    do
        # only update opatch if there is something to do in this home
        [ -n "${ga_applyBP[${gc_home[$i]}]}" ] || [ -n "${ga_applyOOB[${gc_home[$i]}]}" ] || [ -n "${ga_rollbackOOB[${gc_home[$i]}]}" ] && updateOpatch ${gc_home[$i]}
    done
fi

saveState updateOpatch
debug "End State: updateOpatch"
[ "${gv_orchestrator}" -eq 1 ] && exit # If orchestrator then exit
;& 
# End of updateOpatch state



###################################
stopHomes)
###################################
debug   # This just prints a blank line in the debug output
debug "Begin State: stopHomes"
saveState stopHomes

# Stop all database homes that were listed regardless if there are any patches
# skip gc_home[0] because that is always grid home
for ((i=1; i<${#gc_home[@]}; i++))
do
    stopHome ${gc_home[$i]}
done

saveState stopHomes
debug "End State: stopHomes"
[ "${gv_orchestrator}" -eq 1 ] && exit # If orchestrator then exit
;& 
# End of stopHomes state



###################################
stopStack)
###################################
debug   # This just prints a blank line in the debug output
debug "Begin State: stopStack"
saveState stopStack

# if there are any patches listed for grid home and patching in-place then stop GI stack. Don't stop grid if doing out-of-place for grid home.
if [ -n "${ga_applyBP[${gc_home[0]}]}" ] || [ -n "${ga_applyOOB[${gc_home[0]}]}" ] || [ -n "${ga_rollbackOOB[${gc_home[0]}]}" ] && \
   [ ! "${ga_targetOOP[${gc_home[0]}]+isset}" ] # check if we are doing out-of-place
then
    stopGIStackForPatching
fi

saveState stopStack
debug "End State: stopStack"
[ "${gv_orchestrator}" -eq 1 ] && exit # If orchestrator then exit
;& 
# End of stopStack state



###################################
executePatch)
###################################
debug   # This just prints a blank line in the debug output
debug "Begin State: executePatch"
saveState executePatch


# If there were not any patches passed in then we can skip the steps in this phase
if [ ${#ga_applyBP[@]} -ne 0 ] || [ ${#ga_applyOOB[@]} -ne 0 ] || [ ${#ga_rollbackOOB[@]} -ne 0 ]; then
    for ((i=${gv_skipgrid}; i<${#gc_home[@]}; i++))
    do
        if [ -z "${gc_home[$i]}" ]; then continue; fi;
        if [ -z "${ga_directory[${gc_home[$i]}]}" ]; then continue; fi;
        # inventory before
        recordInventory ${gc_home[$i]} before
        Log
        Log info "Inventory before patching ..."
        showPatches ${gc_home[$i]}
        showMd5sum ${gc_home[$i]}
        # recompile config.c only if requested
        if [ ${gv_recompile_config} -eq 1 ];then
            recompileConfigC ${gc_home[$i]}
        fi
        genResponseFile ${gc_home[$i]}
        executePatch ${gc_home[$i]}
        recordInventory ${gc_home[$i]} after
        Log
        Log info "Inventory after patching ..."
        showPatches ${gc_home[$i]}
        showMd5sum ${gc_home[$i]}
    done
fi

saveState executePatch
debug "End State: executePatch"
[ "${gv_orchestrator}" -eq 1 ] && exit # If orchestrator then exit
;& 
# End of executePatch state



###################################
switchGridhome)
###################################
debug   # This just prints a blank line in the debug output
debug "Begin State: switchGridhome"
saveState switchGridhome

if [ ${gv_switch_gridhome} -eq 1 ]; then
    # Because of the way stop homes works, if a home is already stopped it will produce an empty state file. So if the state file is empty when restarting it won't start anything.
    # stop all of the database homes before switching the grid home. Some may be already stopped from before. That's ok. We are using a different state file.
    stopAllHomes
    switchGridhome
    # restart all of the database homes after switching the grid home. This will only restart the homes that we stopped immediately before the switch
    startAllHomes
fi

saveState switchGridhome
debug "End State: switchGridhome"
[ "${gv_orchestrator}" -eq 1 ] && exit # If orchestrator then exit
;& 
# End of startStack state



###################################
startStack)
###################################
debug   # This just prints a blank line in the debug output
debug "Begin State: startStack"
saveState startStack

#LogErrorAndExit "Stop here for debugging"

# if there are any patches listed for grid home and patching in-place then start GI stack
if [ -n "${ga_applyBP[${gc_home[0]}]}" ] || [ -n "${ga_applyOOB[${gc_home[0]}]}" ] || [ -n "${ga_rollbackOOB[${gc_home[0]}]}" ] && \
   [ ! "${ga_targetOOP[${gc_home[0]}]+isset}" ] # check if we are doing out-of-place
then
    if [ ${gv_orchestrator} -eq 0 ] && [ ${gv_rolling} -eq 0 ]; then
        unsetTrap
        Log info "Ready to start Grid Infrastructure (wait until all nodes ready)"
        while true; do
            read -t 180 -p "Do you want to continue? [Yes/No] " v_response
            case ${v_response} in
                y?(es)) 
                    break
                    ;;
                n?(o)) 
                    exit
                    ;;
                *)  echo "Please answer yes or no.";;
            esac
        done
        setTrap
    fi
    startGIStackAfterPatching
fi

saveState startStack
debug "End State: startStack"
[ "${gv_orchestrator}" -eq 1 ] && exit # If orchestrator then exit
;& 
# End of startStack state



###################################
startHomes)
###################################
debug   # This just prints a blank line in the debug output
debug "Begin State: startHomes"
saveState startHomes

# skip gc_home[0] because that is always grid home
for ((i=1; i<${#gc_home[@]}; i++))
do
    startHome ${gc_home[$i]}
done

saveState startHomes
debug "End State: startHomes"
[ "${gv_orchestrator}" -eq 1 ] && exit # If orchestrator then exit
;& 
# End of startHomes state



###################################
postChecks)
###################################
debug   # This just prints a blank line in the debug output
debug "Begin State: postChecks"
saveState postChecks

postChecks

saveState postChecks
debug "End State: postChecks"
[ "${gv_orchestrator}" -eq 1 ] && exit # If orchestrator then exit
;& 
# End of postChecks state



###################################
epilogue)
###################################
debug   # This just prints a blank line in the debug output
debug "Begin State: epilogue"
#saveState epilogue

debug "Place any final cleanup here..."
${ga_directory[${gc_home[0]}]}/bin/crsctl status resource -t -w "TYPE = ora.database.type"

if [ ${gv_post_installs} -gt 0 ]; then
    Log info "Don't forget to run post install scripts for the following patches:"
    # print contents of ga_postInstall
    for i in "${!ga_postInstall[@]}"
    do
        echo "${ga_directory[$i]}: ${ga_postInstall[$i]}"
    done
fi
debug "End State: epilogue"
[ "${gv_orchestrator}" -eq 1 ] && exit # If orchestrator then exit
;& 
# End of epilogue state

esac

debug "End of Main"
exit
