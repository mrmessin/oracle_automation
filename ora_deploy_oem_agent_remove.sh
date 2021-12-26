##############################################################################################
# Script:  ora_deploy_oem_agent_remove.sh
#
# Description:  Oracle Enterprise Manager OEM Agent Removal
#
# Process:  Execute from a central deployment server
#           ssh equiv. that will allow scp and ssh
#           from deploy server to each server where java
#           for agent being updated.
#           Text file containing a list of servers to remove agents from 
#
#           Text file can be in format of hostname      agent_home
#           The agent home should be the acutal running agent version location
#
#               Example:
#                                               agoquaorm01             /u01/app/oracle/agent/agent_13.2.0.0.0
#                                               agoquaorm02             /u01/app/oracle/agent12c/agent_13.2.0.0.0
#                                               agoquaorl11             /u01/app/oracle/product/agent/agent_13.2.0.0.0
#                                               agoquaorl12             /u01/app/oracle/product/agent/agent_13.2.0.0.0
#
#           Text file containing the patches and their location to be applied
#               Example:
#
#
# Parameters: required:  Text File containing the list of servers and the agent homes
#
# Output:  <Script location on file system>/logs/ora_deploy_oem_agent_remove_<date>.log
#
# Execution:
#       /u01/app/oracle/scripts/ora_deploy_oem_agent_remove.sh /u01/app/oracle/scripts/ora_deploy_oem_agent_remove_prd.txt
#
##############################################################################################

################################################################
# Accept parameter for file with list of nodes to work on
################################################################
export inputfile=$1

#####################################################
# Script environment
#####################################################
# assign a date we can use as part of the logfile
export DTE=`/bin/date +%m%d%C%y%H%M`

# Get locations
export SCRIPTLOC=`dirname $0`
export SCRIPTDIR=`basename $0`

# Set the logfile directory
export LOGPATH=${SCRIPTLOC}/logs
export LOGFILE=ora_deploy_oem_agent_remove_${DTE}.log
export LOG=$LOGPATH/$LOGFILE

#####################################################
# Script Environment variables
#####################################################
# export the page list (Change as require for process notifications)
export PAGE_LIST=dbas@availity.com,dbas@realmed.com
export EMAIL_LIST=DBAs@availity.com

################################################################
# Check Parameter is valid and file exists
################################################################
if [ ! -f "${inputfile}" ]
then
   echo "Oracle Agent Remove Failed -> ${inputfile} does not exist can not process upgrade."
   echo "Oracle Agent Remove Failed -> ${inputfile} does not exist can not process upgrade." >> ${LOG}
   exit 8
fi

# For each server we will want to grab the agent home then process the agent update
# Local hostname
export HOSTNAME=`hostname`

#####################################################################
# Removal of Agents
#####################################################################
echo "Removing Agents for the Following Environments in ${inputfile}"
echo "Removing Agents for the Following Environments in ${inputfile}" >> ${LOG}
cat ${inputfile}
cat ${inputfile} >> ${LOG}

# go through each node in the list in the file and execute upgrade
while read -r line
do
   echo "-------------------------------------------------------------------------------------"
   echo "-------------------------------------------------------------------------------------" >> ${LOG}

   ########################################################
   # Assign the nodename and agent home for processing
   export nodename=`echo ${line}| awk '{print $1}'`
   export agent_home=`echo ${line}| awk '{print $2}'`

   #########################################################
   # Show execution is processing for node and agent home
   echo "Removing OEM Agent on ${nodename} for Agent Home ${agent_home}"
   echo "Removing OEM Agent on ${nodename} for Agent Home ${agent_home}" >> ${LOG}

   #########################################################
   # Shutdown the OEM Agent on remote node in case it is up
   echo "Shutting Down Agent on host ${nodename}"
   echo "Shutting Down Agent on host ${nodename}" >> ${LOG}
   export cmd="${agent_home}/bin/emctl stop agent"
   echo ${cmd}
   echo ${cmd} >> ${LOG}
   ssh -n ${nodename} ${cmd} >> ${LOG}

   #########################################################
   # Detach the agent home from the inventory   
   export cmd="export ORACLE_HOME=${agent_home}; ${agent_home}/oui/bin/detachHome.sh"
   echo ${cmd}
   echo ${cmd} >> ${LOG}
   ssh -n ${nodename} ${cmd} >> ${LOG}

   # Check status of OPatch
   #if [ $? -eq 0 ]; then
   #   echo "OEM Agent Detach on ${nodename} was successful."
   #   echo "OEM Agent Detach on ${nodename} was successful." >> ${LOG}
   #else
   #   echo "Patch Failed -> OEM Agent Detach on ${nodename} Failed Due to Error.... Cancelling process."
   #   echo "Patch Failed -> OEM Agent Detach on ${nodename} Failed Due to Error.... Cancelling process." >> ${LOG}
   #   exit 8
   #fi

   ###############################################################
   # Set command to remove the agent bianries on the file system
   agentbase=${agent_home%/*}
   export cmd="export ORACLE_HOME=${agent_home}; rm -rfv ${agentbase}/"
   echo ${cmd}
   echo ${cmd} >> ${LOG}
   ssh -n ${nodename} ${cmd} >> ${LOG}

   # Check status of OPatch
   if [ $? -eq 0 ]; then
      echo "OEM Agent Remove on ${nodename} was successful."
      echo "OEM Agent Remove on ${nodename} was successful." >> ${LOG}
   else
      echo "Patch Failed -> OEM Agent Remove on ${nodename} Failed Due to Error.... Cancelling process."
      echo "Patch Failed -> OEM Agent Remove on ${nodename} Failed Due to Error.... Cancelling process." >> ${LOG}
      exit 8
   fi
done < ${inputfile}

echo "-------------------------------------------------------------------------------------"
echo "-------------------------------------------------------------------------------------" >> ${LOG}
echo "OEM Agent Remove on All nodes in list ${inputfile} successful."
echo "OEM Agent Remove on All nodes in list ${inputfile} successful." >> ${LOG}

exit 0 
