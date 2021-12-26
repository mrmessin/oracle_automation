##############################################################################################
# Script:  ora_deploy_oem_agent_status.sh
#
# Description:  Oracle Enterprise Manager OEM Agent Status
#
# Process:  Execute from a central deployment server
#           ssh equiv. that will allow scp and ssh
#           from deploy server to each server for agents 
#           Text file containing a list of servers to 
#           check status of OEM agent.
#
#           Text file can be in format of hostname	agent_home
#           The agent home should be the acutal running agent version location
#
#   		Example:
#						agoquaorm01		/u01/app/oracle/agent/agent_13.2.0.0.0
#						agoquaorm02		/u01/app/oracle/agent12c/agent_13.2.0.0.0
#						agoquaorl11		/u01/app/oracle/product/agent/agent_13.2.0.0.0
#						agoquaorl12		/u01/app/oracle/product/agent/agent_13.2.0.0.0
#
#           Text file containing the patches and their location to be applied
#               Example:
#
#
# Parameters: required:  Text File containing the list of servers and the agent homes
#
# Output:  <Script location on file system>/logs/ora_deploy_oem_agent_patch_<date>.log
#
# Execution:
#	/u01/app/oracle/scripts/ora_deploy_oem_agent_status.sh /u01/app/oracle/scripts/ora_deploy_oem_agent_prd.txt
#
############################################################################################## 
#
################################################################
# Accept parameter for file with list of nodes to work on
################################################################
export inputfile=$1

################################################################
# Set the file name for the patches
################################################################
export agent_patches=ora_deploy_oem_agent_patch.txt

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
export LOGFILE=ora_deploy_oem_agent_status_${DTE}.log
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
   echo "Oracle Agent Patch Failed -> ${inputfile} does not exist can not process upgrade."
   echo "Oracle Agent Patch Failed -> ${inputfile} does not exist can not process upgrade." >> ${LOG}
   exit 8
fi

# For each server we will want to grab the agent home then process the agent update
# Local hostname
export HOSTNAME=`hostname`

echo "Patching Agents for the Following Environments in ${inputfile}"
echo "Patching Agents for the Following Environments in ${inputfile}" >> ${LOG}
cat ${inputfile}
cat ${inputfile} >> ${LOG}

while read -r line
do
   ########################################################
   # Assign the nodename and agent home for processing
   export nodename=`echo ${line}| awk '{print $1}'`
   export agent_home=`echo ${line}| awk '{print $2}'`

   #########################################################
   # Show execution is processing for node and agent home
   echo "Status for OEM Agent on ${nodename} for Agent Home ${agent_home}"
   echo "Status for OEM Agent on ${nodename} for Agent Home ${agent_home}" >> ${LOG}

   echo "Status Agent on host ${nodename}"
   echo "Status Agent on host ${nodename}" >> ${LOG}
   export cmd="${agent_home}/bin/emctl status agent"
   echo ${cmd}
   ssh -n ${nodename} ${cmd} >> ${LOG}
   
   # Check status of the Agent Status
   if [ $? -eq 0 ]; then
       echo "OEM Agent Status on ${nodename} was successful."
       echo "OEM Agent Status on ${nodename} was successful." >> ${LOG}
   else
       echo "Patch Failed -> OEM Agent Status on ${nodename} Failed Due to Error Cancelling process."
       echo "Patch Failed -> OEM Agent Status on ${nodename} Failed Due to Error Cancelling process." >> ${LOG}
       exit 8
   fi
   
   echo "OEM Status on ${nodename} was successful." 
   echo "OEM Status on ${nodename} was successful."  >> ${LOG}
done < ${inputfile}

echo "-------------------------------------------------------------------------------------"
echo "-------------------------------------------------------------------------------------" >> ${LOG}
echo "All nodes in list ${inpufile} successful."
echo "All nodes in list ${inpufile} successful." >> ${LOG}

exit 0
